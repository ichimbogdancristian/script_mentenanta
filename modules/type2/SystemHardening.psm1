#Requires -Version 7.0
<#
.SYNOPSIS    System Hardening - Type 2 (Consolidated Security + Telemetry)
.DESCRIPTION Applies security hardening and telemetry/privacy disabling changes
             identified by the SystemHardeningAudit (Type1) module.
             Processes both security items (Defender, registry, firewall) and
             telemetry items (services, registry, tasks).
.NOTES       Module Type: Type2 | DiffKey: SystemHardening | Version: 5.1 (Consolidated)
#>

$_corePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'core\Maintenance.psm1'
if (-not (Get-Command 'Write-Log' -ErrorAction SilentlyContinue)) {
    Import-Module $_corePath -Force -Global -WarningAction SilentlyContinue
}

function Invoke-SystemHardening {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter()][hashtable]$OSContext
    )

    Write-Log -Level INFO -Component HARDENING -Message 'Starting system hardening (security + telemetry)'

    $diff = Get-DiffList -ModuleName 'SystemHardening'
    if (-not $diff -or $diff.Count -eq 0) {
        Write-Log -Level INFO -Component HARDENING -Message 'System already hardened'
        return New-ModuleResult -ModuleName 'SystemHardening' -Status 'Skipped' -ModuleType 'Type2' -Message 'Already compliant'
    }

    $processed = 0
    $failed = 0
    $errors = @()
    $rebootNeeded = $false

    # Split diff into security and telemetry for logging
    $securityItems = @($diff | Where-Object { $_.HardeningType -eq 'security' })
    $telemetryItems = @($diff | Where-Object { $_.HardeningType -eq 'telemetry' })

    Write-Log -Level INFO -Component HARDENING -Message "Applying $($diff.Count) hardening change(s): $($securityItems.Count) security, $($telemetryItems.Count) telemetry"

    # Export pre-hardening state for rollback/audit purposes
    try {
        $preHardeningState = @{
            Timestamp = Get-Date -Format 'o'
        }

        if ($securityItems.Count -gt 0) {
            $preHardeningState['DefenderPreferences'] = Get-MpPreference -ErrorAction SilentlyContinue |
                Select-Object DisableRealtimeMonitoring, MAPSReporting, EnableNetworkProtection, PUAProtection, EnableControlledFolderAccess, SubmitSamplesConsent
            $preHardeningState['FirewallProfiles'] = Get-NetFirewallProfile -ErrorAction SilentlyContinue |
                Select-Object Name, Enabled
        }

        $backupPath = Get-TempPath -Category 'data' -FileName "hardening-pre-state-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
        $preHardeningState | ConvertTo-Json -Depth 10 | Set-Content -Path $backupPath -Encoding UTF8 -Force
        Write-Log -Level INFO -Component HARDENING -Message "Pre-hardening state backed up: $backupPath"
    }
    catch {
        Write-Log -Level WARN -Component HARDENING -Message "Could not backup pre-hardening state: $_"
    }

    foreach ($item in $diff) {
        $name = $item.Name ?? "$item"
        $type = $item.Type ?? 'registry'
        $hardeningType = $item.HardeningType ?? 'unknown'

        try {
            $changed = $false

            # ─── SECURITY ITEMS ──────────────────────────────────────────
            if ($hardeningType -eq 'security') {
                switch ($type) {
                    'registry' {
                        $changed = Invoke-RegistryChangeItem -Item $item -Component 'HARDENING'
                    }
                    'defender' {
                        $feature = $item.Feature ?? $item.Name
                        $enable = $item.ShouldEnable ?? $true
                        $defChanged = $true

                        switch ($feature) {
                            'RealTimeProtection' {
                                Set-MpPreference -DisableRealtimeMonitoring (-not $enable) -ErrorAction Stop
                                Write-Log -Level SUCCESS -Component HARDENING -Message "Defender.RealTimeProtection -> $enable"
                            }
                            'CloudProtection' {
                                Set-MpPreference -MAPSReporting $(if ($enable) { 2 } else { 0 }) -ErrorAction Stop
                                Write-Log -Level SUCCESS -Component HARDENING -Message "Defender.CloudProtection -> $enable"
                            }
                            'NetworkProtection' {
                                Set-MpPreference -EnableNetworkProtection $(if ($enable) { 1 } else { 0 }) -ErrorAction Stop
                                Write-Log -Level SUCCESS -Component HARDENING -Message "Defender.NetworkProtection -> $enable"
                            }
                            'PUAProtection' {
                                Set-MpPreference -PUAProtection $(if ($enable) { 1 } else { 0 }) -ErrorAction Stop
                                Write-Log -Level SUCCESS -Component HARDENING -Message "Defender.PUAProtection -> $enable"
                            }
                            'ControlledFolderAccess' {
                                Set-MpPreference -EnableControlledFolderAccess $(if ($enable) { 1 } else { 0 }) -ErrorAction Stop
                                Write-Log -Level SUCCESS -Component HARDENING -Message "Defender.ControlledFolderAccess -> $enable"
                            }
                            'AutomaticSampleSubmission' {
                                Set-MpPreference -SubmitSamplesConsent $(if ($enable) { 1 } else { 0 }) -ErrorAction Stop
                                Write-Log -Level SUCCESS -Component HARDENING -Message "Defender.AutomaticSampleSubmission -> $enable"
                            }
                            'AntivirusEnabled' {
                                # Remove policy that disables AV, ensure service running
                                $null = Set-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender' `
                                    -Name 'DisableAntiSpyware' -Value 0 -Type DWord
                                Set-Service -Name WinDefend -StartupType Automatic -ErrorAction Stop
                                Start-Service -Name WinDefend -ErrorAction Stop
                                $rebootNeeded = $true
                                Write-Log -Level SUCCESS -Component HARDENING -Message "Defender.AntivirusEnabled -> $enable"
                            }
                            default {
                                Write-Log -Level WARN -Component HARDENING -Message "Unknown Defender feature: $feature"
                                $defChanged = $false
                            }
                        }
                        $changed = $defChanged
                    }
                    'firewall' {
                        $fwProfile = $item.Profile
                        if (-not $fwProfile) {
                            Write-Log -Level WARN -Component HARDENING -Message "Firewall missing Profile: $name"
                            $errors += "[No Profile] $name"
                            $failed++
                            continue
                        }
                        $enabled = if ($item.DesiredState -eq $false) { 'False' } else { 'True' }
                        Set-NetFirewallProfile -Profile $fwProfile.Split(',') -Enabled $enabled -ErrorAction Stop
                        Write-Log -Level SUCCESS -Component HARDENING -Message "Firewall.$fwProfile -> Enabled=$enabled"
                        $changed = $true
                    }
                    default {
                        Write-Log -Level WARN -Component HARDENING -Message "Unknown security type '$type': $name"
                        $errors += "[Unknown type] $name"
                        $failed++
                    }
                }
            }

            # ─── TELEMETRY ITEMS ─────────────────────────────────────────
            elseif ($hardeningType -eq 'telemetry') {
                switch ($type) {
                    'service' {
                        $changed = Invoke-ServiceChangeItem -Item $item -Component 'HARDENING'
                    }
                    'registry' {
                        $changed = Invoke-RegistryChangeItem -Item $item -Component 'HARDENING'
                    }
                    'scheduledtask' {
                        $taskPath = $item.TaskPath ?? '\Microsoft\Windows\'
                        $taskName = $item.TaskName ?? $item.Name
                        $null = Disable-ScheduledTask -TaskPath $taskPath -TaskName $taskName -ErrorAction Stop
                        Write-Log -Level SUCCESS -Component HARDENING -Message "Disabled task: $taskPath$taskName"
                        $changed = $true
                    }
                    default {
                        Write-Log -Level WARN -Component HARDENING -Message "Unknown telemetry type '$type': $name"
                        $errors += "[Unknown type] $name"
                        $failed++
                    }
                }
            }

            if ($changed) { $processed++ }
        }
        catch {
            Write-Log -Level ERROR -Component HARDENING -Message "Failed [$name]: $_"
            $errors += "[$name] $_"
            $failed++
        }
    }

    $status = if ($failed -eq 0) { 'Success' } elseif ($processed -gt 0) { 'Warning' } else { 'Failed' }
    Write-Log -Level INFO -Component HARDENING -Message "Done: $processed applied, $failed failed, Reboot: $(if ($rebootNeeded) { 'Yes' } else { 'No' })"

    return New-ModuleResult -ModuleName 'SystemHardening' -Status $status -ModuleType 'Type2' `
        -ItemsDetected $diff.Count -ItemsProcessed $processed -ItemsFailed $failed -Errors $errors `
        -RebootRequired $rebootNeeded
}

Export-ModuleMember -Function 'Invoke-SystemHardening'
