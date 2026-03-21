#Requires -Version 7.0
<#
.SYNOPSIS    Security Enhancement - Type 2 (system modification)
.DESCRIPTION Applies security baseline: enables Defender features, hardens registry,
             configures firewall, and ensures required services are running.
.NOTES       Module Type: Type2 | DiffKey: SecurityEnhancement | Version: 5.0
#>

$_corePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'core\Maintenance.psm1'
if (-not (Get-Command 'Write-Log' -ErrorAction SilentlyContinue)) {
    Import-Module $_corePath -Force -Global -WarningAction SilentlyContinue
}

function Invoke-SecurityEnhancement {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter()][hashtable]$OSContext
    )

    Write-Log -Level INFO -Component SECURITY -Message 'Starting security enhancement'

    $diff = Get-DiffList -ModuleName 'SecurityEnhancement'
    if (-not $diff -or $diff.Count -eq 0) {
        Write-Log -Level INFO -Component SECURITY -Message 'Security baseline already met'
        return New-ModuleResult -ModuleName 'SecurityEnhancement' -Status 'Skipped' -Message 'Already compliant'
    }

    $processed = 0; $failed = 0; $errors = @(); $rebootNeeded = $false

    Write-Log -Level INFO -Component SECURITY -Message "Applying $($diff.Count) security fix(es)"

    foreach ($item in $diff) {
        $name = $item.Name ?? "$item"
        $type = $item.Type ?? 'registry'
        try {
            $changed = $false
            switch ($type) {
                'registry' {
                    $path = $item.Path ?? $item.RegistryPath
                    $vname = $item.ValueName ?? $item.Name
                    $val = $item.DesiredValue
                    $vtype = $item.ValueType ?? 'DWord'
                    if ($path -and $vname -and $null -ne $val) {
                        $null = Set-RegistryValue -Path $path -Name $vname -Value $val -Type $vtype
                        Write-Log -Level SUCCESS -Component SECURITY -Message "Registry: $path\$vname = $val"
                        $changed = $true
                    }
                }
                'defender' {
                    $feature = $item.Feature ?? $item.Name
                    $enable = $item.ShouldEnable ?? $true
                    $defChanged = $true
                    switch ($feature) {
                        'RealTimeProtection' { Set-MpPreference -DisableRealtimeMonitoring (-not $enable) -ErrorAction Stop }
                        'CloudProtection' { Set-MpPreference -MAPSReporting $(if ($enable) { 2 } else { 0 }) -ErrorAction Stop }
                        'NetworkProtection' { Set-MpPreference -EnableNetworkProtection $(if ($enable) { 1 } else { 0 }) -ErrorAction Stop }
                        'PUAProtection' { Set-MpPreference -PUAProtection $(if ($enable) { 1 } else { 0 }) -ErrorAction Stop }
                        'AntivirusEnabled' {
                            # Remove policy key that prevents AV from running, then ensure service is started
                            $null = Set-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender' `
                                -Name 'DisableAntiSpyware' -Value 0 -Type DWord
                            Set-Service  -Name WinDefend -StartupType Automatic -ErrorAction Stop
                            Start-Service -Name WinDefend -ErrorAction Stop
                            $rebootNeeded = $true   # DisableAntiSpyware change may require reboot
                        }
                        default {
                            Write-Log -Level WARN -Component SECURITY -Message "Unknown Defender feature: $feature"
                            $defChanged = $false
                        }
                    }
                    if ($defChanged) {
                        Write-Log -Level SUCCESS -Component SECURITY -Message "Defender.$feature -> $enable"
                        $changed = $true
                    }
                }
                'firewall' {
                    $fwProfile = $item.Profile
                    if (-not $fwProfile) {
                        Write-Log -Level WARN -Component SECURITY -Message "Firewall diff missing Profile — skipping: $name"
                        $errors += "[No Profile] $name"; $failed++; continue
                    }
                    $enabled = if ($item.DesiredState -eq $false) { 'False' } else { 'True' }
                    Set-NetFirewallProfile -Profile $fwProfile.Split(',') -Enabled $enabled -ErrorAction Stop
                    Write-Log -Level SUCCESS -Component SECURITY -Message "Firewall $fwProfile -> Enabled=$enabled"
                    $changed = $true
                }
                'service' {
                    $svc = $item.ServiceName ?? $item.Name
                    $action = $item.Action ?? 'EnsureRunning'
                    if ($action -eq 'EnsureRunning') {
                        Set-Service -Name $svc -StartupType Automatic -ErrorAction Stop
                        Start-Service -Name $svc -ErrorAction Stop
                        Write-Log -Level SUCCESS -Component SECURITY -Message "Service started: $svc"
                        $changed = $true
                    }
                    elseif ($action -eq 'EnsureDisabled') {
                        Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
                        Set-Service -Name $svc -StartupType Disabled -ErrorAction Stop
                        Write-Log -Level SUCCESS -Component SECURITY -Message "Service disabled: $svc"
                        $changed = $true
                    }
                }
                default {
                    Write-Log -Level WARN -Component SECURITY -Message "Unknown type '$type' for $name"
                    $errors += "[Unknown type] $name"; $failed++
                }
            }
            if ($changed) { $processed++ }
        }
        catch {
            Write-Log -Level ERROR -Component SECURITY -Message "Failed [$name]: $_"
            $errors += "[$name] $_"; $failed++
        }
    }

    $status = if ($failed -eq 0) { 'Success' } elseif ($processed -gt 0) { 'Warning' } else { 'Failed' }
    Write-Log -Level INFO -Component SECURITY -Message "Done: $processed applied, $failed failed"
    return New-ModuleResult -ModuleName 'SecurityEnhancement' -Status $status -ItemsDetected $diff.Count `
        -ItemsProcessed $processed -ItemsFailed $failed -Errors $errors -RebootRequired $rebootNeeded
}

Export-ModuleMember -Function 'Invoke-SecurityEnhancement'
