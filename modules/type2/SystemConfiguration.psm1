#Requires -Version 7.0
<#
.SYNOPSIS    System Configuration - Type 2 (Consolidated Security + Telemetry + Optimization)
.DESCRIPTION Applies all system-state changes identified by SystemConfigurationAudit.
             Dispatches each diff item on its ConfigType then Type:
               security     -> registry | defender | firewall | sysmon
               telemetry    -> service | registry | scheduledtask
               optimization -> service | powerplan | startup | visualfx | background
             Sysmon is installed via winget (Microsoft.Sysinternals.Sysmon) and configured
             with config/sysmon/sysmonconfig.xml.
.NOTES       Module Type: Type2 | DiffKey: SystemConfiguration | Version: 6.0 (Consolidated)
#>

$_corePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'core\Maintenance.psm1'
if (-not (Get-Command 'Write-Log' -ErrorAction SilentlyContinue)) {
    Import-Module $_corePath -Force -Global -WarningAction SilentlyContinue
}

<#
.SYNOPSIS
    Backs up the current registry value before applying a change. Used for rollback.
.OUTPUTS
    [hashtable] with backup data: Path, Name, Exists, Value, Backed, Timestamp.
#>
function Backup-RegistryValue {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [string]$Name
    )

    $current = Get-RegistryValue -Path $Path -Name $Name
    $exists = Test-Path -Path "$Path" -ErrorAction SilentlyContinue

    return @{
        Path = $Path
        Name = $Name
        Exists = $exists
        Value = $current
        Backed = $true
        Timestamp = Get-Date -Format 'o'
    }
}

<#
.SYNOPSIS
    Verifies that a registry value was successfully applied to the system.
.OUTPUTS
    [bool] $true if the value matches the expected value.
#>
function Test-RegistryValueApplied {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [string]$Name,
        [Parameter(Mandatory)] [object]$ExpectedValue
    )

    try {
        $actual = Get-RegistryValue -Path $Path -Name $Name
        return $actual -eq $ExpectedValue
    }
    catch {
        Write-Log -Level DEBUG -Component CONFIG -Message "Registry verification failed for $Path\$Name : $_"
        return $false
    }
}

<#
.SYNOPSIS
    Rolls back a registry value to its pre-change state using a backup hashtable.
.OUTPUTS
    [bool] $true if rollback succeeded.
#>
function Restore-RegistryValue {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)] [hashtable]$Backup
    )

    try {
        $path = $Backup.Path
        $name = $Backup.Name
        $value = $Backup.Value
        $existed = $Backup.Exists

        if (-not $existed -and (Test-Path $path)) {
            Remove-ItemProperty -Path $path -Name $name -Force -ErrorAction Stop
            Write-Log -Level INFO -Component CONFIG -Message "Rollback: Removed $path\$name (did not exist before)"
        }
        elseif ($existed -and $null -ne $value) {
            Set-ItemProperty -Path $path -Name $name -Value $value -Force -ErrorAction Stop
            Write-Log -Level INFO -Component CONFIG -Message "Rollback: Restored $path\$name to previous value"
        }
        return $true
    }
    catch {
        Write-Log -Level ERROR -Component CONFIG -Message "Rollback FAILED for $($Backup.Path)\$($Backup.Name): $_"
        return $false
    }
}

<#
.SYNOPSIS
    Installs Sysinternals Sysmon via winget and applies the bundled sysmonconfig.xml.
.DESCRIPTION
    Idempotent: if the Sysmon service already exists the config is re-applied (-c) rather
    than reinstalled (-i). Resolves the Sysmon binary from PATH or the winget install
    location. Config file: config/sysmon/sysmonconfig.xml under the project root.
.OUTPUTS
    [bool] $true on success.
#>
function Install-SysmonWithConfig {
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    $configPath = Join-Path $env:MAINT_CONFIG 'sysmon\sysmonconfig.xml'
    if (-not (Test-Path $configPath)) {
        Write-Log -Level WARN -Component CONFIG -Message "Sysmon config not found: $configPath - skipping Sysmon"
        return $false
    }

    # Install the package if the service is not already present
    $sysmonSvc = Get-Service -Name 'Sysmon', 'Sysmon64' -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $sysmonSvc) {
        if (-not (Test-CommandAvailable 'winget')) {
            Write-Log -Level WARN -Component CONFIG -Message 'winget unavailable - cannot install Sysmon'
            return $false
        }
        Write-Log -Level INFO -Component CONFIG -Message 'Installing Sysmon via winget (Microsoft.Sysinternals.Sysmon)'
        $exit = Invoke-ExternalPackageCommand -FilePath 'winget' -ArgumentList @(
            'install', '--id', 'Microsoft.Sysinternals.Sysmon', '--source', 'winget', '--silent',
            '--disable-interactivity', '--accept-package-agreements', '--accept-source-agreements', '--scope', 'machine')
        if ($exit -notin 0, -1978335135, -1978335189) {
            Write-Log -Level WARN -Component CONFIG -Message "winget Sysmon install returned exit $exit"
        }
    }

    # Resolve the Sysmon executable (winget installs under Links/WindowsApps, name varies)
    $sysmonExe = $null
    foreach ($candidate in 'Sysmon64.exe', 'Sysmon.exe') {
        $cmd = Get-Command $candidate -ErrorAction SilentlyContinue
        if ($cmd) { $sysmonExe = $cmd.Source; break }
    }
    if (-not $sysmonExe) {
        $searchRoots = @(
            (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links'),
            (Join-Path $env:ProgramFiles 'WinGet\Links'),
            "$env:ProgramFiles\WindowsApps"
        )
        foreach ($root in $searchRoots) {
            if (-not (Test-Path $root)) { continue }
            $found = Get-ChildItem -Path $root -Filter 'Sysmon*.exe' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($found) { $sysmonExe = $found.FullName; break }
        }
    }
    if (-not $sysmonExe) {
        Write-Log -Level WARN -Component CONFIG -Message 'Sysmon executable not found after install'
        return $false
    }

    # Apply config: -i installs+configures a fresh Sysmon; -c updates config on an existing install
    $sysmonSvc = Get-Service -Name 'Sysmon', 'Sysmon64' -ErrorAction SilentlyContinue | Select-Object -First 1
    $applyArgs = if ($sysmonSvc) { @('-c', $configPath) } else { @('-accepteula', '-i', $configPath) }
    $exit = Invoke-ExternalPackageCommand -FilePath $sysmonExe -ArgumentList $applyArgs
    if ($exit -eq 0) {
        Write-Log -Level SUCCESS -Component CONFIG -Message "Sysmon configured with $configPath"
        return $true
    }
    Write-Log -Level WARN -Component CONFIG -Message "Sysmon config apply returned exit $exit"
    return $false
}

function Invoke-SystemConfiguration {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter()][hashtable]$OSContext
    )

    Write-Log -Level INFO -Component CONFIG -Message 'Starting system configuration (security + telemetry + optimization)'

    $diff = Get-DiffList -ModuleName 'SystemConfiguration'
    if (-not $diff -or $diff.Count -eq 0) {
        Write-Log -Level INFO -Component CONFIG -Message 'System already in desired configuration'
        return New-ModuleResult -ModuleName 'SystemConfiguration' -Status 'Skipped' -ModuleType 'Type2' -Message 'Already compliant'
    }

    $processed = 0; $failed = 0; $errors = @(); $rebootNeeded = $false

    $securityItems = @($diff | Where-Object { $_.ConfigType -eq 'security' })
    $telemetryItems = @($diff | Where-Object { $_.ConfigType -eq 'telemetry' })
    $optimizationItems = @($diff | Where-Object { $_.ConfigType -eq 'optimization' })

    Write-Log -Level INFO -Component CONFIG -Message "Applying $($diff.Count) change(s): $($securityItems.Count) security, $($telemetryItems.Count) telemetry, $($optimizationItems.Count) optimization"

    # Backup pre-change security state for audit/rollback
    if ($securityItems.Count -gt 0) {
        try {
            $preState = @{
                Timestamp           = Get-Date -Format 'o'
                DefenderPreferences = Get-MpPreference -ErrorAction SilentlyContinue |
                    Select-Object DisableRealtimeMonitoring, MAPSReporting, EnableNetworkProtection, PUAProtection, EnableControlledFolderAccess, SubmitSamplesConsent
                FirewallProfiles    = Get-NetFirewallProfile -ErrorAction SilentlyContinue | Select-Object Name, Enabled
            }
            $backupPath = Get-TempPath -Category 'data' -FileName "config-pre-state-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
            $preState | ConvertTo-Json -Depth 10 | Set-Content -Path $backupPath -Encoding UTF8 -Force
            Write-Log -Level INFO -Component CONFIG -Message "Pre-change state backed up: $backupPath"
        }
        catch { Write-Log -Level WARN -Component CONFIG -Message "Could not back up pre-change state: $_" }
    }

    foreach ($item in $diff) {
        $name = $item.Name ?? "$item"
        $configType = $item.ConfigType ?? 'unknown'
        $type = $item.Type ?? 'registry'

        try {
            $changed = $false
            $backup = $null

            switch ($configType) {
                # ─── SECURITY ────────────────────────────────────────────────
                'security' {
                    switch ($type) {
                        'registry' {
                            $vname = $item.ValueName ?? $item.Name
                            if ($vname) {
                                $backup = Backup-RegistryValue -Path $item.Path -Name $vname
                                $changed = Invoke-RegistryChangeItem -Item $item -Component 'CONFIG'
                                if ($changed) {
                                    $verified = Test-RegistryValueApplied -Path $item.Path -Name $vname -ExpectedValue $item.DesiredValue
                                    if (-not $verified) {
                                        Write-Log -Level WARN -Component CONFIG -Message "Registry verification FAILED: $($item.Path)\$vname"
                                        if ($backup) { Restore-RegistryValue -Backup $backup | Out-Null }
                                        $errors += "[Verification Failed] $name"; $failed++; $changed = $false
                                    }
                                }
                            }
                        }
                        'service' { $changed = Invoke-ServiceChangeItem -Item $item -Component 'CONFIG' }
                        'defender' {
                            $feature = $item.Feature ?? $item.Name
                            $enable = $item.ShouldEnable ?? $true
                            $changed = $true
                            switch ($feature) {
                                'RealTimeProtection' { Set-MpPreference -DisableRealtimeMonitoring (-not $enable) -ErrorAction Stop }
                                'CloudProtection' { Set-MpPreference -MAPSReporting $(if ($enable) { 2 } else { 0 }) -ErrorAction Stop }
                                'NetworkProtection' { Set-MpPreference -EnableNetworkProtection $(if ($enable) { 1 } else { 0 }) -ErrorAction Stop }
                                'PUAProtection' { Set-MpPreference -PUAProtection $(if ($enable) { 1 } else { 0 }) -ErrorAction Stop }
                                'ControlledFolderAccess' { Set-MpPreference -EnableControlledFolderAccess $(if ($enable) { 1 } else { 0 }) -ErrorAction Stop }
                                'AutomaticSampleSubmission' { Set-MpPreference -SubmitSamplesConsent $(if ($enable) { 1 } else { 0 }) -ErrorAction Stop }
                                'AntivirusEnabled' {
                                    $null = Set-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender' -Name 'DisableAntiSpyware' -Value 0 -Type DWord
                                    Set-Service -Name WinDefend -StartupType Automatic -ErrorAction Stop
                                    Start-Service -Name WinDefend -ErrorAction Stop
                                    $rebootNeeded = $true
                                }
                                default { Write-Log -Level WARN -Component CONFIG -Message "Unknown Defender feature: $feature"; $changed = $false }
                            }
                            if ($changed) { Write-Log -Level SUCCESS -Component CONFIG -Message "Defender.$feature -> $enable" }
                        }
                        'firewall' {
                            $fwProfile = $item.Profile
                            if (-not $fwProfile) {
                                Write-Log -Level WARN -Component CONFIG -Message "Firewall missing Profile: $name"
                                $errors += "[No Profile] $name"; $failed++; continue
                            }
                            $enabled = if ($item.DesiredState -eq $false) { 'False' } else { 'True' }
                            Set-NetFirewallProfile -Profile $fwProfile.Split(',') -Enabled $enabled -ErrorAction Stop
                            Write-Log -Level SUCCESS -Component CONFIG -Message "Firewall.$fwProfile -> Enabled=$enabled"
                            $changed = $true
                        }
                        'sysmon' { $changed = Install-SysmonWithConfig }
                        default {
                            Write-Log -Level WARN -Component CONFIG -Message "Unknown security type '$type': $name"
                            $errors += "[Unknown type] $name"; $failed++
                        }
                    }
                }

                # ─── TELEMETRY ───────────────────────────────────────────────
                'telemetry' {
                    switch ($type) {
                        'service' { $changed = Invoke-ServiceChangeItem -Item $item -Component 'CONFIG' }
                        'registry' {
                            $vname = $item.ValueName ?? $item.Name
                            if ($vname) {
                                $backup = Backup-RegistryValue -Path $item.Path -Name $vname
                                $changed = Invoke-RegistryChangeItem -Item $item -Component 'CONFIG'
                                if ($changed) {
                                    $verified = Test-RegistryValueApplied -Path $item.Path -Name $vname -ExpectedValue $item.DesiredValue
                                    if (-not $verified) {
                                        Write-Log -Level WARN -Component CONFIG -Message "Registry verification FAILED: $($item.Path)\$vname"
                                        if ($backup) { Restore-RegistryValue -Backup $backup | Out-Null }
                                        $errors += "[Verification Failed] $name"; $failed++; $changed = $false
                                    }
                                }
                            }
                        }
                        'scheduledtask' {
                            $taskPath = $item.TaskPath ?? '\Microsoft\Windows\'
                            $taskName = $item.TaskName ?? $item.Name
                            $null = Disable-ScheduledTask -TaskPath $taskPath -TaskName $taskName -ErrorAction Stop
                            Write-Log -Level SUCCESS -Component CONFIG -Message "Disabled task: $taskPath$taskName"
                            $changed = $true
                        }
                        default {
                            Write-Log -Level WARN -Component CONFIG -Message "Unknown telemetry type '$type': $name"
                            $errors += "[Unknown type] $name"; $failed++
                        }
                    }
                }

                # ─── OPTIMIZATION ────────────────────────────────────────────
                'optimization' {
                    switch ($type) {
                        'service' { $changed = Invoke-ServiceChangeItem -Item $item -Component 'CONFIG' }
                        'registry' {
                            $vname = $item.ValueName ?? $item.Name
                            if ($vname) {
                                $backup = Backup-RegistryValue -Path $item.Path -Name $vname
                                $changed = Invoke-RegistryChangeItem -Item $item -Component 'CONFIG'
                                if ($changed) {
                                    $verified = Test-RegistryValueApplied -Path $item.Path -Name $vname -ExpectedValue $item.DesiredValue
                                    if (-not $verified) {
                                        Write-Log -Level WARN -Component CONFIG -Message "Registry verification FAILED: $($item.Path)\$vname"
                                        if ($backup) { Restore-RegistryValue -Backup $backup | Out-Null }
                                        $errors += "[Verification Failed] $name"; $failed++; $changed = $false
                                    }
                                }
                            }
                        }
                        'powerplan' {
                            $planGuid = $item.GUID ?? '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
                            $powercfg = Join-Path $env:SystemRoot 'System32\powercfg.exe'
                            $null = & $powercfg /setactive $planGuid 2>&1
                            Write-Log -Level SUCCESS -Component CONFIG -Message "Power plan set to GUID $planGuid"
                            $changed = $true
                        }
                        'visualfx' {
                            $null = Set-RegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' -Name 'VisualFXSetting' -Value 3 -Type DWord
                            $desktop = 'HKCU:\Control Panel\Desktop'
                            $null = Set-RegistryValue -Path $desktop -Name 'MinAnimate' -Value '0' -Type String
                            $null = Set-RegistryValue -Path $desktop -Name 'FontSmoothing' -Value '2' -Type String
                            $null = Set-RegistryValue -Path $desktop -Name 'DragFullWindows' -Value '1' -Type String
                            $adv = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
                            $null = Set-RegistryValue -Path $adv -Name 'TaskbarAnimations' -Value 0 -Type DWord
                            $null = Set-RegistryValue -Path $adv -Name 'ListviewShadow' -Value 0 -Type DWord
                            $null = Set-RegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name 'EnableTransparency' -Value 0 -Type DWord
                            Write-Log -Level SUCCESS -Component CONFIG -Message 'Visual effects set to balanced (custom)'
                            $changed = $true
                        }
                        'background' {
                            $cdm = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
                            $null = Set-RegistryValue -Path $cdm -Name 'RotatingLockScreenEnabled' -Value 0 -Type DWord
                            $null = Set-RegistryValue -Path $cdm -Name 'RotatingLockScreenOverlayEnabled' -Value 0 -Type DWord
                            $null = Set-RegistryValue -Path $cdm -Name 'SubscribedContent-338387Enabled' -Value 0 -Type DWord
                            $wp = 'HKCU:\Control Panel\Desktop'
                            $null = Set-RegistryValue -Path $wp -Name 'WallpaperStyle' -Value '10' -Type String
                            $null = Set-RegistryValue -Path $wp -Name 'TileWallpaper' -Value '0' -Type String
                            Write-Log -Level SUCCESS -Component CONFIG -Message 'Desktop background changed from Spotlight to Picture'
                            $changed = $true
                        }
                        'startup' {
                            $regPath = $item.RegistryPath
                            $entryName = $item.Name
                            if ($regPath -and $entryName) {
                                Remove-ItemProperty -Path $regPath -Name $entryName -Force -ErrorAction Stop
                                Write-Log -Level SUCCESS -Component CONFIG -Message "Startup program disabled: $entryName"
                                $changed = $true
                            }
                        }
                        default {
                            Write-Log -Level WARN -Component CONFIG -Message "Unknown optimization type '$type': $name"
                            $errors += "[Unknown type] $name"; $failed++
                        }
                    }
                }

                default {
                    Write-Log -Level WARN -Component CONFIG -Message "Unknown ConfigType '$configType': $name"
                    $errors += "[Unknown ConfigType] $name"; $failed++
                }
            }

            if ($changed) { $processed++ }
        }
        catch {
            Write-Log -Level ERROR -Component CONFIG -Message "Failed [$configType/$type $name]: $_"
            $errors += "[$name] $_"; $failed++
        }
    }

    $status = if ($failed -eq 0) { 'Success' } elseif ($processed -gt 0) { 'Warning' } else { 'Failed' }
    Write-Log -Level INFO -Component CONFIG -Message "Done: $processed applied, $failed failed, Reboot: $(if ($rebootNeeded) { 'Yes' } else { 'No' })"

    return New-ModuleResult -ModuleName 'SystemConfiguration' -Status $status -ModuleType 'Type2' `
        -ItemsDetected $diff.Count -ItemsProcessed $processed -ItemsFailed $failed -Errors $errors `
        -RebootRequired $rebootNeeded
}

Export-ModuleMember -Function 'Invoke-SystemConfiguration'
