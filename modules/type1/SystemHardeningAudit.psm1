#Requires -Version 7.0
<#
.SYNOPSIS    System Hardening Audit - Type 1 (Consolidated Security + Telemetry)
.DESCRIPTION Audits system security and privacy settings against baseline.
             Combines security hardening (Defender, registry, firewall) with
             telemetry/privacy disabling (services, registry, tasks).
             Diff = items that don't match desired state.
.NOTES       Module Type: Type1 | DiffKey: SystemHardening | Version: 5.1 (Consolidated)
#>

$_corePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'core\Maintenance.psm1'
if (-not (Get-Command 'Write-Log' -ErrorAction SilentlyContinue)) {
    Import-Module $_corePath -Force -Global -WarningAction SilentlyContinue
}

function Invoke-SystemHardeningAudit {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    Write-Log -Level INFO -Component HARDENING-AUDIT -Message 'Starting system hardening audit (security + telemetry)'

    try {
        # 1. Load both baselines
        $securityBaseline = Get-BaselineList -ModuleFolder 'security' -FileName 'security-baseline.json'
        $telemetryBaseline = Get-BaselineList -ModuleFolder 'telemetry' -FileName 'telemetry-list.json'

        if (-not $securityBaseline -and -not $telemetryBaseline) {
            return New-ModuleResult -ModuleName 'SystemHardeningAudit' -Status 'Failed' `
                -Message 'Neither security nor telemetry baseline found'
        }

        $diff = [System.Collections.Generic.List[hashtable]]::new()
        $securityItemsFound = 0
        $telemetryItemsFound = 0

        # ─── SECURITY HARDENING AUDIT ────────────────────────────────────────
        if ($securityBaseline) {
            if (-not $securityBaseline.registry -and -not $securityBaseline.windowsDefender) {
                Write-Log -Level WARN -Component HARDENING-AUDIT -Message 'Invalid security baseline (missing registry/defender)'
            }
            else {
                Write-Log -Level DEBUG -Component HARDENING-AUDIT -Message 'Auditing security settings...'

                # Security registry checks
                if ($securityBaseline.registry) {
                    Compare-RegistryBaseline -Entries @($securityBaseline.registry) | ForEach-Object {
                        $_.HardeningType = 'security'
                        $diff.Add($_)
                        $securityItemsFound++
                        Write-Log -Level DEBUG -Component HARDENING-AUDIT -Message "Security mismatch: $($_.Description)"
                    }
                }

                # Windows Defender checks
                if ($securityBaseline.windowsDefender.realTimeProtection) {
                    try {
                        $mpStatus = Get-MpComputerStatus -ErrorAction Stop
                        if (-not $mpStatus.RealTimeProtectionEnabled) {
                            $diff.Add(@{
                                HardeningType = 'security'
                                Type          = 'defender'
                                Name          = 'RealTimeProtection'
                                Feature       = 'RealTimeProtection'
                                ShouldEnable  = $true
                                Description   = 'Windows Defender real-time protection'
                                CurrentState  = $false
                                DesiredState  = $true
                            })
                            $securityItemsFound++
                            Write-Log -Level WARN -Component HARDENING-AUDIT -Message 'Defender: Real-time protection DISABLED'
                        }
                        if (-not $mpStatus.AntivirusEnabled) {
                            $diff.Add(@{
                                HardeningType = 'security'
                                Type          = 'defender'
                                Name          = 'AntivirusEnabled'
                                Feature       = 'AntivirusEnabled'
                                ShouldEnable  = $true
                                Description   = 'Windows Defender antivirus service'
                                CurrentState  = $false
                                DesiredState  = $true
                            })
                            $securityItemsFound++
                        }
                    }
                    catch {
                        Write-Log -Level WARN -Component HARDENING-AUDIT -Message "Defender query failed: $_"
                        $diff.Add(@{
                            HardeningType = 'security'
                            Type          = 'defender'
                            Name          = 'DefenderStatusUnknown'
                            Feature       = 'RealTimeProtection'
                            ShouldEnable  = $true
                            Description   = 'Windows Defender status unknown'
                            CurrentState  = 'Unknown'
                            DesiredState  = $true
                        })
                        $securityItemsFound++
                    }
                }

                # Cloud + Network protection (check independently of realTimeProtection)
                if ($securityBaseline.windowsDefender.cloudProtection -or $securityBaseline.windowsDefender.networkProtection -or $securityBaseline.windowsDefender.pua) {
                    try {
                        $mpPrefs = Get-MpPreference -ErrorAction Stop
                        if ($securityBaseline.windowsDefender.cloudProtection -and $mpPrefs.MAPSReporting -eq 0) {
                            $diff.Add(@{
                                HardeningType = 'security'
                                Type          = 'defender'
                                Name          = 'CloudProtection'
                                Feature       = 'CloudProtection'
                                ShouldEnable  = $true
                                Description   = 'Windows Defender cloud-delivered protection'
                                CurrentState  = $false
                                DesiredState  = $true
                            })
                            $securityItemsFound++
                        }
                        if ($securityBaseline.windowsDefender.networkProtection -and $mpPrefs.EnableNetworkProtection -eq 0) {
                            $diff.Add(@{
                                HardeningType = 'security'
                                Type          = 'defender'
                                Name          = 'NetworkProtection'
                                Feature       = 'NetworkProtection'
                                ShouldEnable  = $true
                                Description   = 'Windows Defender network-based threat protection'
                                CurrentState  = $false
                                DesiredState  = $true
                            })
                            $securityItemsFound++
                        }
                        if ($securityBaseline.windowsDefender.pua -and $mpPrefs.PUAProtection -eq 0) {
                            $diff.Add(@{
                                HardeningType = 'security'
                                Type          = 'defender'
                                Name          = 'PUAProtection'
                                Feature       = 'PUAProtection'
                                ShouldEnable  = $true
                                Description   = 'Windows Defender potentially unwanted app protection'
                                CurrentState  = $false
                                DesiredState  = $true
                            })
                            $securityItemsFound++
                        }
                    }
                    catch {
                        Write-Log -Level WARN -Component HARDENING-AUDIT -Message "Defender preference query failed: $_"
                    }
                }
            }
        }

        # ─── TELEMETRY & PRIVACY AUDIT ────────────────────────────────────────
        if ($telemetryBaseline) {
            if (-not $telemetryBaseline.services -or -not $telemetryBaseline.registry) {
                Write-Log -Level WARN -Component HARDENING-AUDIT -Message 'Invalid telemetry baseline (missing services/registry)'
            }
            else {
                Write-Log -Level DEBUG -Component HARDENING-AUDIT -Message 'Auditing telemetry/privacy settings...'

                # Telemetry services to disable
                if ($telemetryBaseline.services.disable) {
                    Compare-ServiceBaseline -ServiceNames @($telemetryBaseline.services.disable) -Action 'EnsureDisabled' | ForEach-Object {
                        $_.HardeningType = 'telemetry'
                        $diff.Add($_)
                        $telemetryItemsFound++
                        Write-Log -Level DEBUG -Component HARDENING-AUDIT -Message "Service active (should disable): $($_.Name)"
                    }
                }

                # Telemetry registry keys
                if ($telemetryBaseline.registry) {
                    $regGroups = @('telemetry', 'advertising', 'cortana', 'privacy')
                    foreach ($grp in $regGroups) {
                        if (-not $telemetryBaseline.registry.$grp) { continue }
                        Compare-RegistryBaseline -Entries @($telemetryBaseline.registry.$grp) | ForEach-Object {
                            $_.HardeningType = 'telemetry'
                            $diff.Add($_)
                            $telemetryItemsFound++
                            Write-Log -Level DEBUG -Component HARDENING-AUDIT -Message "Registry mismatch: $($_.ValueName)"
                        }
                    }
                }

                # Telemetry scheduled tasks
                if ($telemetryBaseline.scheduledTasks.disable) {
                    foreach ($taskPath in $telemetryBaseline.scheduledTasks.disable) {
                        try {
                            $taskName = Split-Path $taskPath -Leaf
                            $taskFolder = Split-Path $taskPath -Parent
                            $task = Get-ScheduledTask -TaskName $taskName -TaskPath "$taskFolder\" -ErrorAction SilentlyContinue
                            if ($task -and $task.State -ne 'Disabled') {
                                $diff.Add(@{
                                    HardeningType = 'telemetry'
                                    Type          = 'scheduledtask'
                                    Name          = $taskPath
                                    TaskPath      = "$taskFolder\"
                                    TaskName      = $taskName
                                    CurrentState  = $task.State.ToString()
                                    DesiredState  = 'Disabled'
                                })
                                $telemetryItemsFound++
                                Write-Log -Level DEBUG -Component HARDENING-AUDIT -Message "Task active (should disable): $taskPath"
                            }
                        }
                        catch {
                            Write-Log -Level WARN -Component HARDENING-AUDIT -Message "Task query failed '$taskPath': $_"
                        }
                    }
                }
            }
        }

        Write-Log -Level INFO -Component HARDENING-AUDIT -Message "Hardening items found: $($diff.Count) (Security: $securityItemsFound, Telemetry: $telemetryItemsFound)"

        # Save consolidated diff
        Save-DiffList -ModuleName 'SystemHardening' -DiffList $diff.ToArray()

        return New-ModuleResult -ModuleName 'SystemHardeningAudit' -Status 'Success' `
            -ItemsDetected $diff.Count `
            -Message "$($diff.Count) hardening item(s): $securityItemsFound security, $telemetryItemsFound telemetry"
    }
    catch {
        Write-Log -Level ERROR -Component HARDENING-AUDIT -Message "Audit failed: $_"
        return New-ModuleResult -ModuleName 'SystemHardeningAudit' -Status 'Failed' -Errors @($_.ToString())
    }
}

Export-ModuleMember -Function 'Invoke-SystemHardeningAudit'
