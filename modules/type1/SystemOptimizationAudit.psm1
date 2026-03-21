#Requires -Version 7.0
<#
.SYNOPSIS    System Optimization Audit - Type 1
.DESCRIPTION Audits services, startup programs, and power plan against the optimization baseline.
             Diff = settings that differ from desired state.
.NOTES       Module Type: Type1 | DiffKey: SystemOptimization | Version: 5.0
#>

$_corePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'core\Maintenance.psm1'
if (-not (Get-Command 'Write-Log' -ErrorAction SilentlyContinue)) {
    Import-Module $_corePath -Force -Global -WarningAction SilentlyContinue
}

function Invoke-SystemOptimizationAudit {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    Write-Log -Level INFO -Component SYSOPT-AUDIT -Message 'Starting system optimization audit'

    try {
        # 1. Load baseline
        $baseline = Get-BaselineList -ModuleFolder 'system-optimization' -FileName 'system-optimization-config.json'
        if (-not $baseline) {
            return New-ModuleResult -ModuleName 'SystemOptimizationAudit' -Status 'Failed' `
                -Message 'System optimization baseline not found'
        }
        if (-not $baseline.common) {
            return New-ModuleResult -ModuleName 'SystemOptimizationAudit' -Status 'Failed' `
                -Message 'Invalid system optimization baseline structure (missing common section)'
        }

        $osCtx = if ($global:OSContext) { $global:OSContext } else { Get-OSContext }
        $diff = [System.Collections.Generic.List[hashtable]]::new()

        # 2. Audit services that should be disabled
        $svcsToDisable = [System.Collections.Generic.List[string]]::new()
        if ($baseline.common.services.safeToDisable) { $baseline.common.services.safeToDisable | ForEach-Object { $svcsToDisable.Add($_) } }
        if ($osCtx.IsWindows11 -and $baseline.windows11.services.safeToDisable) {
            $baseline.windows11.services.safeToDisable | ForEach-Object { $svcsToDisable.Add($_) }
        }
        elseif (-not $osCtx.IsWindows11 -and $baseline.windows10.services.safeToDisable) {
            $baseline.windows10.services.safeToDisable | ForEach-Object { $svcsToDisable.Add($_) }
        }

        foreach ($svcName in $svcsToDisable) {
            try {
                $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
                if ($svc -and $svc.StartType -ne 'Disabled') {
                    $diff.Add(@{ Type = 'service'; Name = $svcName; CurrentState = $svc.StartType.ToString(); DesiredState = 'Disabled' })
                    Write-Log -Level DEBUG -Component SYSOPT-AUDIT -Message "Service needs disable: $svcName ($($svc.StartType)))"
                }
            }
            catch { Write-Log -Level WARN -Component SYSOPT-AUDIT -Message "Service query failed for $svcName" }
        }

        # 3. Audit power plan
        if ($baseline.common.powerPlan.defaultPlan) {
            $desiredPlan = $baseline.common.powerPlan.defaultPlan
            try {
                $powercfg = Join-Path $env:SystemRoot 'System32\powercfg.exe'
                $currentPlan = & $powercfg /getactivescheme 2>&1
                if ($currentPlan -notmatch [regex]::Escape($desiredPlan)) {
                    # Resolve the GUID for the desired plan name so the Type2 module can apply it directly
                    $planGuid = $null
                    try {
                        & $powercfg /list 2>&1 | ForEach-Object {
                            if ($_ -match 'GUID:\s+([0-9a-f-]{36})\s+\(([^)]+)\)' -and
                                $Matches[2] -like "*$desiredPlan*") {
                                $planGuid = $Matches[1]
                            }
                        }
                    }
                    catch { Write-Log -Level WARN -Component SYSOPT-AUDIT -Message "Power plan list failed: $_" }
                    $diff.Add(@{
                            Type         = 'powerplan'
                            Name         = 'ActivePlan'
                            GUID         = $planGuid ?? '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
                            CurrentState = $currentPlan
                            DesiredState = $desiredPlan
                        })
                    Write-Log -Level DEBUG -Component SYSOPT-AUDIT -Message "Power plan mismatch: desired '$desiredPlan'"
                }
            }
            catch { Write-Log -Level WARN -Component SYSOPT-AUDIT -Message "Power plan query failed: $_" }
        }

        # 4. Audit startup programs
        if ($baseline.common.startupPrograms) {
            $safePatterns = $baseline.common.startupPrograms.safeToDisablePatterns ?? @()
            $neverDisable = $baseline.common.startupPrograms.neverDisable ?? @()

            # Gather startup entries from registry Run keys
            $startupEntries = @()
            $runPaths = @(
                'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
                'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
            )
            foreach ($runPath in $runPaths) {
                try {
                    $props = Get-ItemProperty -Path $runPath -ErrorAction SilentlyContinue
                    if ($props) {
                        $props.PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' } | ForEach-Object {
                            $startupEntries += @{ Name = $_.Name; Command = $_.Value; Source = $runPath }
                        }
                    }
                }
                catch { Write-Log -Level WARN -Component SYSOPT-AUDIT -Message "Failed to read $runPath : $_" }
            }

            foreach ($entry in $startupEntries) {
                $entryName = $entry.Name
                # Check if this matches a safe-to-disable pattern
                $isSafe = $false
                foreach ($pattern in $safePatterns) {
                    if ($entryName -like $pattern) { $isSafe = $true; break }
                }
                if (-not $isSafe) { continue }

                # Ensure it's not in the never-disable list
                $isProtected = $false
                foreach ($pattern in $neverDisable) {
                    if ($entryName -like $pattern) { $isProtected = $true; break }
                }
                if ($isProtected) { continue }

                $diff.Add(@{
                        Type         = 'startup'
                        Name         = $entryName
                        Command      = $entry.Command
                        RegistryPath = $entry.Source
                        CurrentState = 'Enabled'
                        DesiredState = 'Disabled'
                    })
                Write-Log -Level DEBUG -Component SYSOPT-AUDIT -Message "Startup program to disable: $entryName"
            }
        }

        # 5. Audit visual effects (check registry)
        $visualAudioPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects'
        $currentVisual = Get-RegistryValue -Path $visualAudioPath -Name 'VisualFXSetting'
        # 3 = Custom (balanced); anything else means not optimized to our balanced preset
        if ($null -eq $currentVisual -or $currentVisual -ne 3) {
            $diff.Add(@{ Type = 'visualfx'; Name = 'VisualFXSetting'; CurrentState = $currentVisual; DesiredState = 3 })
        }

        # 5b. Audit desktop background (Spotlight → Picture)
        if ($baseline.common.background.type -eq 'Picture') {
            $contentDeliveryPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
            $spotlightEnabled = Get-RegistryValue -Path $contentDeliveryPath -Name 'RotatingLockScreenEnabled'
            $spotlightOverride = Get-RegistryValue -Path $contentDeliveryPath -Name 'RotatingLockScreenOverlayEnabled'
            # Check the wallpaper personalization path for Creative/Spotlight
            $personalizePath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
            # SystemUsesLightTheme is unrelated but check for Spotlight via ContentDeliveryManager
            $cdmSubscriptions = Get-RegistryValue -Path $contentDeliveryPath -Name 'SubscribedContent-338387Enabled'
            if ($spotlightEnabled -eq 1 -or $cdmSubscriptions -eq 1) {
                $diff.Add(@{
                        Type         = 'background'
                        Name         = 'DesktopBackground'
                        Description  = 'Change desktop background from Windows Spotlight to Picture'
                        CurrentState = 'Spotlight'
                        DesiredState = 'Picture'
                    })
                Write-Log -Level DEBUG -Component SYSOPT-AUDIT -Message 'Desktop background: Spotlight detected, should be Picture'
            }
        }

        Write-Log -Level INFO -Component SYSOPT-AUDIT -Message "Optimization gaps: $($diff.Count)"

        # 6. Save diff
        Save-DiffList -ModuleName 'SystemOptimization' -DiffList $diff.ToArray()

        # 7. Persist audit data
        $auditPath = Get-TempPath -Category 'data' -FileName 'sysopt-audit.json'
        @{ Timestamp = (Get-Date -Format 'o'); Gaps = $diff.ToArray(); OS = $osCtx.DisplayText } `
        | ConvertTo-Json -Depth 6 | Set-Content -Path $auditPath -Encoding UTF8 -Force

        Write-Log -Level SUCCESS -Component SYSOPT-AUDIT -Message "System optimization audit complete: $($diff.Count) gaps"
        return New-ModuleResult -ModuleName 'SystemOptimizationAudit' -Status 'Success' `
            -ItemsDetected $diff.Count `
            -Message "$($diff.Count) optimization settings need adjustment"
    }
    catch {
        Write-Log -Level ERROR -Component SYSOPT-AUDIT -Message "Audit failed: $_"
        return New-ModuleResult -ModuleName 'SystemOptimizationAudit' -Status 'Failed' -Errors @($_.ToString())
    }
}

Export-ModuleMember -Function 'Invoke-SystemOptimizationAudit'
