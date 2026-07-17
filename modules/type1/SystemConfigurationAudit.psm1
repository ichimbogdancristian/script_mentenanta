#Requires -Version 7.0
<#
.SYNOPSIS    System Configuration Audit - Type 1 (Consolidated Security + Telemetry + Optimization)
.DESCRIPTION Single system-state audit. Produces one diff whose items are tagged with a
             ConfigType discriminator:
               ConfigType = 'security'      Defender, firewall, security registry, Sysmon
               ConfigType = 'telemetry'     privacy services/registry/scheduled tasks
               ConfigType = 'optimization'  services, power plan, startup, visual fx, background
             Consumes baselines: security, telemetry, system-optimization.
.NOTES       Module Type: Type1 | DiffKey: SystemConfiguration | Version: 6.0 (Consolidated)
#>

$_corePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'core\Maintenance.psm1'
if (-not (Get-Command 'Write-Log' -ErrorAction SilentlyContinue)) {
    Import-Module $_corePath -Force -Global -WarningAction SilentlyContinue
}

function Compare-RegistryBaselineWithFallback {
    param([Parameter(Mandatory)] $Entries)

    $results = @()

    # Layer 1: Try PowerShell native (fastest)
    try {
        $results = @(Compare-RegistryBaseline -Entries $Entries -ErrorAction Stop)
        Write-Log -Level DEBUG -Component CONFIG-AUDIT -Message "Registry baseline comparison via PowerShell succeeded (Layer 1)"
        return $results
    }
    catch {
        Write-Log -Level DEBUG -Component CONFIG-AUDIT -Message "PowerShell registry comparison failed: $_. Trying Layer 2 (registry.exe fallback)"
    }

    # Layer 2: Fallback to registry.exe queries
    try {
        foreach ($entry in $Entries) {
            if (-not $entry.path -or -not $entry.name) { continue }

            $regPath = $entry.path -replace 'HKEY_LOCAL_MACHINE\\', 'HKLM\'
            $regPath = $regPath -replace 'HKEY_CURRENT_USER\\', 'HKCU\'

            $regQuery = & reg query $regPath /v $entry.name 2>&1
            if ($regQuery -match 'REG_\w+\s+(.+?)(?:\s|$)') {
                $currentValue = $Matches[1].Trim()
                if ($currentValue -ne $entry.desiredValue.ToString()) {
                    $results += @{
                        path = $entry.path
                        name = $entry.name
                        currentValue = $currentValue
                        desiredValue = $entry.desiredValue
                        DetectionMethod = 'registry.exe'
                    }
                }
            }
        }
        if ($results) {
            Write-Log -Level DEBUG -Component CONFIG-AUDIT -Message "Registry baseline comparison via registry.exe succeeded (Layer 2)"
        }
        return $results
    }
    catch {
        Write-Log -Level WARN -Component CONFIG-AUDIT -Message "Registry fallback also failed: $_"
        return @()
    }
}

function Invoke-SystemConfigurationAudit {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    Write-Log -Level INFO -Component CONFIG-AUDIT -Message 'Starting system configuration audit (security + telemetry + optimization)'

    try {
        $osCtx = (Get-Variable -Name 'OSContext' -Scope Global -ValueOnly -ErrorAction SilentlyContinue)
        if (-not $osCtx) { $osCtx = Get-OSContext }

        $diff = [System.Collections.Generic.List[hashtable]]::new()
        $securityFound = 0
        $telemetryFound = 0
        $optimizationFound = 0

        # ═══ SECURITY ════════════════════════════════════════════════════════
        $securityBaseline = Get-BaselineList -ModuleFolder 'security' -FileName 'security-baseline.json'
        if ($securityBaseline) {
            Write-Log -Level DEBUG -Component CONFIG-AUDIT -Message 'Auditing security settings...'

            # Security registry (with fallback detection)
            if ($securityBaseline.registry) {
                Compare-RegistryBaselineWithFallback -Entries @($securityBaseline.registry) | ForEach-Object {
                    $_.ConfigType = 'security'
                    $diff.Add($_); $securityFound++
                }
            }

            # Services that must be running / disabled for a hardened baseline
            if ($securityBaseline.services.ensureDisabled) {
                Compare-ServiceBaseline -ServiceNames @($securityBaseline.services.ensureDisabled) -Action 'EnsureDisabled' | ForEach-Object {
                    $_.ConfigType = 'security'
                    $diff.Add($_); $securityFound++
                }
            }
            if ($securityBaseline.services.ensureRunning) {
                Compare-ServiceBaseline -ServiceNames @($securityBaseline.services.ensureRunning) -Action 'EnsureRunning' | ForEach-Object {
                    $_.ConfigType = 'security'
                    $diff.Add($_); $securityFound++
                }
            }

            # Windows Defender feature checks
            if ($securityBaseline.windowsDefender) {
                $wd = $securityBaseline.windowsDefender
                try {
                    $mpStatus = Get-MpComputerStatus -ErrorAction Stop
                    if ($wd.realTimeProtection -and -not $mpStatus.RealTimeProtectionEnabled) {
                        $diff.Add(@{ ConfigType = 'security'; Type = 'defender'; Name = 'RealTimeProtection'; Feature = 'RealTimeProtection'; ShouldEnable = $true; CurrentState = $false; DesiredState = $true })
                        $securityFound++
                        Write-Log -Level WARN -Component CONFIG-AUDIT -Message 'Defender: Real-time protection DISABLED'
                    }
                    if (-not $mpStatus.AntivirusEnabled) {
                        $diff.Add(@{ ConfigType = 'security'; Type = 'defender'; Name = 'AntivirusEnabled'; Feature = 'AntivirusEnabled'; ShouldEnable = $true; CurrentState = $false; DesiredState = $true })
                        $securityFound++
                    }
                }
                catch {
                    Write-Log -Level WARN -Component CONFIG-AUDIT -Message "Defender status query failed: $_"
                }
                try {
                    $mpPrefs = Get-MpPreference -ErrorAction Stop
                    if ($wd.cloudProtection -and $mpPrefs.MAPSReporting -eq 0) {
                        $diff.Add(@{ ConfigType = 'security'; Type = 'defender'; Name = 'CloudProtection'; Feature = 'CloudProtection'; ShouldEnable = $true; CurrentState = $false; DesiredState = $true })
                        $securityFound++
                    }
                    if ($wd.networkProtection -and $mpPrefs.EnableNetworkProtection -eq 0) {
                        $diff.Add(@{ ConfigType = 'security'; Type = 'defender'; Name = 'NetworkProtection'; Feature = 'NetworkProtection'; ShouldEnable = $true; CurrentState = $false; DesiredState = $true })
                        $securityFound++
                    }
                    if ($wd.pua -and $mpPrefs.PUAProtection -eq 0) {
                        $diff.Add(@{ ConfigType = 'security'; Type = 'defender'; Name = 'PUAProtection'; Feature = 'PUAProtection'; ShouldEnable = $true; CurrentState = $false; DesiredState = $true })
                        $securityFound++
                    }
                }
                catch {
                    Write-Log -Level WARN -Component CONFIG-AUDIT -Message "Defender preference query failed: $_"
                }
            }

            # Firewall profiles
            if ($securityBaseline.firewall.enabled) {
                try {
                    $fwProfiles = Get-NetFirewallProfile -ErrorAction Stop
                    foreach ($profileName in @('Domain', 'Private', 'Public')) {
                        $key = $profileName.ToLowerInvariant()
                        if ($securityBaseline.firewall.enabled.$key) {
                            $prof = $fwProfiles | Where-Object { $_.Name -eq $profileName }
                            if ($prof -and -not $prof.Enabled) {
                                $diff.Add(@{ ConfigType = 'security'; Type = 'firewall'; Name = "Firewall.$profileName"; Profile = $profileName; CurrentState = $false; DesiredState = $true })
                                $securityFound++
                            }
                        }
                    }
                }
                catch { Write-Log -Level WARN -Component CONFIG-AUDIT -Message "Firewall query failed: $_" }
            }

            # Sysmon presence check (installed via SystemConfiguration Type2 with sysmonconfig.xml)
            $sysmonSvc = Get-Service -Name 'Sysmon', 'Sysmon64' -ErrorAction SilentlyContinue | Select-Object -First 1
            if (-not $sysmonSvc) {
                $diff.Add(@{ ConfigType = 'security'; Type = 'sysmon'; Name = 'Sysmon'; CurrentState = 'NotInstalled'; DesiredState = 'Installed' })
                $securityFound++
                Write-Log -Level INFO -Component CONFIG-AUDIT -Message 'Sysmon not installed - queued for install'
            }
        }

        # ═══ TELEMETRY / PRIVACY ═════════════════════════════════════════════
        $telemetryBaseline = Get-BaselineList -ModuleFolder 'telemetry' -FileName 'telemetry-list.json'
        if ($telemetryBaseline) {
            Write-Log -Level DEBUG -Component CONFIG-AUDIT -Message 'Auditing telemetry/privacy settings...'

            if ($telemetryBaseline.services.disable) {
                Compare-ServiceBaseline -ServiceNames @($telemetryBaseline.services.disable) -Action 'EnsureDisabled' | ForEach-Object {
                    $_.ConfigType = 'telemetry'
                    $diff.Add($_); $telemetryFound++
                }
            }

            if ($telemetryBaseline.registry) {
                foreach ($grp in @('telemetry', 'advertising', 'cortana', 'privacy')) {
                    if (-not $telemetryBaseline.registry.$grp) { continue }
                    Compare-RegistryBaselineWithFallback -Entries @($telemetryBaseline.registry.$grp) | ForEach-Object {
                        $_.ConfigType = 'telemetry'
                        $diff.Add($_); $telemetryFound++
                    }
                }
            }

            if ($telemetryBaseline.scheduledTasks.disable) {
                foreach ($taskPath in $telemetryBaseline.scheduledTasks.disable) {
                    try {
                        $taskName = Split-Path $taskPath -Leaf
                        $taskFolder = Split-Path $taskPath -Parent
                        $task = Get-ScheduledTask -TaskName $taskName -TaskPath "$taskFolder\" -ErrorAction SilentlyContinue
                        if ($task -and $task.State -ne 'Disabled') {
                            $diff.Add(@{ ConfigType = 'telemetry'; Type = 'scheduledtask'; Name = $taskPath; TaskPath = "$taskFolder\"; TaskName = $taskName; CurrentState = $task.State.ToString(); DesiredState = 'Disabled' })
                            $telemetryFound++
                        }
                    }
                    catch { Write-Log -Level WARN -Component CONFIG-AUDIT -Message "Task query failed '$taskPath': $_" }
                }
            }
        }

        # ═══ OPTIMIZATION ════════════════════════════════════════════════════
        $optBaseline = Get-BaselineList -ModuleFolder 'system-optimization' -FileName 'system-optimization-config.json'
        if ($optBaseline -and $optBaseline.common) {
            Write-Log -Level DEBUG -Component CONFIG-AUDIT -Message 'Auditing optimization settings...'

            # Services to disable
            $svcsToDisable = [System.Collections.Generic.List[string]]::new()
            if ($optBaseline.common.services.safeToDisable) { $optBaseline.common.services.safeToDisable | ForEach-Object { $svcsToDisable.Add($_) } }
            if ($osCtx.IsWindows11 -and $optBaseline.windows11.services.safeToDisable) {
                $optBaseline.windows11.services.safeToDisable | ForEach-Object { $svcsToDisable.Add($_) }
            }
            elseif (-not $osCtx.IsWindows11 -and $optBaseline.windows10.services.safeToDisable) {
                $optBaseline.windows10.services.safeToDisable | ForEach-Object { $svcsToDisable.Add($_) }
            }
            Compare-ServiceBaseline -ServiceNames @($svcsToDisable) -Action 'EnsureDisabled' | ForEach-Object {
                $_.ConfigType = 'optimization'
                $diff.Add($_); $optimizationFound++
            }

            # Power plan
            if ($optBaseline.common.powerPlan.defaultPlan) {
                $desiredPlan = $optBaseline.common.powerPlan.defaultPlan
                try {
                    $powercfg = Join-Path $env:SystemRoot 'System32\powercfg.exe'
                    $currentPlan = & $powercfg /getactivescheme 2>&1
                    if ($currentPlan -notmatch [regex]::Escape($desiredPlan)) {
                        $planGuid = $null
                        & $powercfg /list 2>&1 | ForEach-Object {
                            if ($_ -match 'GUID:\s+([0-9a-f-]{36})\s+\(([^)]+)\)' -and $Matches[2] -like "*$desiredPlan*") {
                                $planGuid = $Matches[1]
                            }
                        }
                        $diff.Add(@{ ConfigType = 'optimization'; Type = 'powerplan'; Name = 'ActivePlan'; GUID = $planGuid ?? '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'; CurrentState = "$currentPlan"; DesiredState = $desiredPlan })
                        $optimizationFound++
                    }
                }
                catch { Write-Log -Level WARN -Component CONFIG-AUDIT -Message "Power plan query failed: $_" }
            }

            # Startup programs
            if ($optBaseline.common.startupPrograms) {
                $safePatterns = $optBaseline.common.startupPrograms.safeToDisablePatterns ?? @()
                $neverDisable = $optBaseline.common.startupPrograms.neverDisable ?? @()
                $runPaths = @(
                    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
                    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
                )
                foreach ($runPath in $runPaths) {
                    try {
                        $props = Get-ItemProperty -Path $runPath -ErrorAction SilentlyContinue
                        if (-not $props) { continue }
                        $props.PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' } | ForEach-Object {
                            $entryName = $_.Name
                            $isSafe = $false
                            foreach ($pattern in $safePatterns) { if ($entryName -like $pattern) { $isSafe = $true; break } }
                            if (-not $isSafe) { return }
                            $isProtected = $false
                            foreach ($pattern in $neverDisable) { if ($entryName -like $pattern) { $isProtected = $true; break } }
                            if ($isProtected) { return }
                            $diff.Add(@{ ConfigType = 'optimization'; Type = 'startup'; Name = $entryName; RegistryPath = $runPath; CurrentState = 'Enabled'; DesiredState = 'Disabled' })
                        }
                    }
                    catch { Write-Log -Level WARN -Component CONFIG-AUDIT -Message "Failed to read $runPath : $_" }
                }
                # Recompute optimization count from diff (ForEach-Object scope can't ++ outer reliably)
                $optimizationFound = @($diff | Where-Object { $_.ConfigType -eq 'optimization' }).Count
            }

            # Visual effects
            $visualPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects'
            $currentVisual = Get-RegistryValue -Path $visualPath -Name 'VisualFXSetting'
            if ($null -eq $currentVisual -or $currentVisual -ne 3) {
                $diff.Add(@{ ConfigType = 'optimization'; Type = 'visualfx'; Name = 'VisualFXSetting'; CurrentState = $currentVisual; DesiredState = 3 })
                $optimizationFound++
            }

            # Desktop background (Spotlight -> Picture)
            if ($optBaseline.common.background.type -eq 'Picture') {
                $cdmPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
                $spotlightEnabled = Get-RegistryValue -Path $cdmPath -Name 'RotatingLockScreenEnabled'
                $cdmSubscriptions = Get-RegistryValue -Path $cdmPath -Name 'SubscribedContent-338387Enabled'
                if ($spotlightEnabled -eq 1 -or $cdmSubscriptions -eq 1) {
                    $diff.Add(@{ ConfigType = 'optimization'; Type = 'background'; Name = 'DesktopBackground'; CurrentState = 'Spotlight'; DesiredState = 'Picture' })
                    $optimizationFound++
                }
            }
        }

        Write-Log -Level INFO -Component CONFIG-AUDIT -Message "Configuration items found: $($diff.Count) (Security: $securityFound, Telemetry: $telemetryFound, Optimization: $optimizationFound)"

        Save-DiffList -ModuleName 'SystemConfiguration' -DiffList $diff.ToArray()

        $auditPath = Get-TempPath -Category 'data' -FileName 'system-configuration-audit.json'
        @{
            Timestamp         = (Get-Date -Format 'o')
            TotalItems        = $diff.Count
            SecurityItems     = $securityFound
            TelemetryItems    = $telemetryFound
            OptimizationItems = $optimizationFound
            OS                = $osCtx.DisplayText
        } | ConvertTo-Json -Depth 6 | Set-Content -Path $auditPath -Encoding UTF8 -Force

        return New-ModuleResult -ModuleName 'SystemConfigurationAudit' -Status 'Success' `
            -ItemsDetected $diff.Count `
            -Message "$($diff.Count) config item(s): $securityFound security, $telemetryFound telemetry, $optimizationFound optimization"
    }
    catch {
        Write-Log -Level ERROR -Component CONFIG-AUDIT -Message "Audit failed: $_"
        return New-ModuleResult -ModuleName 'SystemConfigurationAudit' -Status 'Failed' -Errors @($_.ToString())
    }
}

Export-ModuleMember -Function 'Invoke-SystemConfigurationAudit'
