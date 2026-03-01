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
    [CmdletBinding(SupportsShouldProcess)]
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

    $processed = 0; $failed = 0; $errors = @()

    Write-Log -Level INFO -Component SECURITY -Message "Applying $($diff.Count) security fix(es)"

    foreach ($item in $diff) {
        $name = $item.Name ?? "$item"
        $type = $item.Type ?? 'registry'
        try {
            switch ($type) {
                'registry' {
                    $path = $item.Path ?? $item.RegistryPath
                    $vname = $item.ValueName ?? $item.Name
                    $val = $item.DesiredValue
                    $vtype = $item.ValueType ?? 'DWord'
                    if ($path -and $vname -and $null -ne $val) {
                        if ($PSCmdlet.ShouldProcess("$path\$vname", "Set $val")) {
                            Set-RegistryValue -Path $path -Name $vname -Value $val -Type $vtype
                            Write-Log -Level SUCCESS -Component SECURITY -Message "Registry: $path\$vname = $val"
                        }
                    }
                }
                'defender' {
                    $feature = $item.Feature ?? $item.Name
                    $enable = $item.ShouldEnable ?? $true
                    if ($PSCmdlet.ShouldProcess("Defender.$feature", ($enable ? 'Enable' : 'Disable'))) {
                        switch ($feature) {
                            'RealTimeProtection' { Set-MpPreference -DisableRealtimeMonitoring (-not $enable) -ErrorAction Stop }
                            'CloudProtection' { Set-MpPreference -MAPSReporting (if ($enable) { 2 } else { 0 }) -ErrorAction Stop }
                            'NetworkProtection' { Set-MpPreference -EnableNetworkProtection (if ($enable) { 1 } else { 0 }) -ErrorAction Stop }
                            'PUAProtection' { Set-MpPreference -PUAProtection (if ($enable) { 1 } else { 0 }) -ErrorAction Stop }
                            default { Write-Log -Level WARN -Component SECURITY -Message "Unknown Defender feature: $feature" }
                        }
                        Write-Log -Level SUCCESS -Component SECURITY -Message "Defender.$feature -> $enable"
                    }
                }
                'firewall' {
                    $profile = $item.Profile ?? 'Domain,Private,Public'
                    if ($PSCmdlet.ShouldProcess("Firewall ($profile)", 'Enable')) {
                        Set-NetFirewallProfile -Profile $profile.Split(',') -Enabled True -ErrorAction Stop
                        Write-Log -Level SUCCESS -Component SECURITY -Message "Firewall enabled: $profile"
                    }
                }
                'service' {
                    $svc = $item.ServiceName ?? $item.Name
                    $action = $item.Action ?? 'EnsureRunning'
                    if ($PSCmdlet.ShouldProcess($svc, $action)) {
                        if ($action -eq 'EnsureRunning') {
                            Set-Service -Name $svc -StartupType Automatic -ErrorAction Stop
                            Start-Service -Name $svc -ErrorAction Stop
                            Write-Log -Level SUCCESS -Component SECURITY -Message "Service started: $svc"
                        }
                        elseif ($action -eq 'EnsureDisabled') {
                            Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
                            Set-Service -Name $svc -StartupType Disabled -ErrorAction Stop
                            Write-Log -Level SUCCESS -Component SECURITY -Message "Service disabled: $svc"
                        }
                    }
                }
                default {
                    Write-Log -Level WARN -Component SECURITY -Message "Unknown type '$type' for $name"
                }
            }
            $processed++
        }
        catch {
            Write-Log -Level ERROR -Component SECURITY -Message "Failed [$name]: $_"
            $errors += "[$name] $_"; $failed++
        }
    }

    $status = if ($failed -eq 0) { 'Success' } elseif ($processed -gt 0) { 'Warning' } else { 'Failed' }
    Write-Log -Level INFO -Component SECURITY -Message "Done: $processed applied, $failed failed"
    return New-ModuleResult -ModuleName 'SecurityEnhancement' -Status $status -ItemsDetected $diff.Count `
        -ItemsProcessed $processed -ItemsFailed $failed -Errors $errors
}

Export-ModuleMember -Function 'Invoke-SecurityEnhancement'
