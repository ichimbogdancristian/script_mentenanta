#Requires -Version 7.0
<#
.SYNOPSIS    Telemetry Disable - Type 2 (system modification)
.DESCRIPTION Stops and disables telemetry services, sets registry values to block data collection,
             and disables scheduled tasks found non-compliant during audit.
.NOTES       Module Type: Type2 | DiffKey: TelemetryDisable | Version: 5.0
#>

$_corePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'core\Maintenance.psm1'
if (-not (Get-Command 'Write-Log' -ErrorAction SilentlyContinue)) {
    Import-Module $_corePath -Force -Global -WarningAction SilentlyContinue
}

function Invoke-TelemetryDisable {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([hashtable])]
    param(
        [Parameter()][hashtable]$OSContext
    )

    Write-Log -Level INFO -Component TELEMETRY -Message 'Starting telemetry disable'

    $diff = Get-DiffList -ModuleName 'TelemetryDisable'
    if (-not $diff -or $diff.Count -eq 0) {
        Write-Log -Level INFO -Component TELEMETRY -Message 'Telemetry already disabled'
        return New-ModuleResult -ModuleName 'TelemetryDisable' -Status 'Skipped' -Message 'Already compliant'
    }

    $processed = 0; $failed = 0; $errors = @()

    Write-Log -Level INFO -Component TELEMETRY -Message "Applying $($diff.Count) telemetry change(s)"

    foreach ($item in $diff) {
        $name = $item.Name ?? "$item"
        $type = $item.Type ?? 'registry'
        try {
            switch ($type) {
                'service' {
                    $svc = $item.ServiceName ?? $item.Name
                    if ($PSCmdlet.ShouldProcess($svc, 'Stop and disable service')) {
                        Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
                        Set-Service -Name $svc -StartupType Disabled -ErrorAction Stop
                        Write-Log -Level SUCCESS -Component TELEMETRY -Message "Disabled service: $svc"
                    }
                }
                'registry' {
                    $path  = $item.Path ?? $item.RegistryPath
                    $vname = $item.ValueName ?? $item.Name
                    $val   = $item.DesiredValue ?? 0
                    $vtype = $item.ValueType ?? 'DWord'
                    if ($path -and $vname) {
                        if ($PSCmdlet.ShouldProcess("$path\$vname", "Set $val")) {
                            Set-RegistryValue -Path $path -Name $vname -Value $val -Type $vtype
                            Write-Log -Level SUCCESS -Component TELEMETRY -Message "Registry: $path\$vname = $val"
                        }
                    }
                }
                'scheduledtask' {
                    $taskPath = $item.TaskPath ?? '\Microsoft\Windows\'
                    $taskName = $item.TaskName ?? $item.Name
                    if ($PSCmdlet.ShouldProcess("$taskPath$taskName", 'Disable-ScheduledTask')) {
                        Disable-ScheduledTask -TaskPath $taskPath -TaskName $taskName -ErrorAction Stop
                        Write-Log -Level SUCCESS -Component TELEMETRY -Message "Disabled task: $taskPath$taskName"
                    }
                }
                default {
                    Write-Log -Level WARN -Component TELEMETRY -Message "Unknown type '$type' for $name"
                }
            }
            $processed++
        }
        catch {
            Write-Log -Level ERROR -Component TELEMETRY -Message "Failed [$name]: $_"
            $errors += "[$name] $_"; $failed++
        }
    }

    $status = if ($failed -eq 0) { 'Success' } elseif ($processed -gt 0) { 'Warning' } else { 'Failed' }
    Write-Log -Level INFO -Component TELEMETRY -Message "Done: $processed applied, $failed failed"
    return New-ModuleResult -ModuleName 'TelemetryDisable' -Status $status -ItemsDetected $diff.Count `
                            -ItemsProcessed $processed -ItemsFailed $failed -Errors $errors
}

Export-ModuleMember -Function 'Invoke-TelemetryDisable'
