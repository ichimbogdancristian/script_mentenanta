#Requires -Version 7.0
<#
.SYNOPSIS    Telemetry & Privacy Audit - Type 1
.DESCRIPTION Audits Windows telemetry services, registry keys, and scheduled tasks.
             Diff = telemetry items still active that should be disabled.
.NOTES       Module Type: Type1 | DiffKey: TelemetryDisable | Version: 5.0
#>

$_corePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'core\Maintenance.psm1'
if (-not (Get-Command 'Write-Log' -ErrorAction SilentlyContinue)) {
    Import-Module $_corePath -Force -Global -WarningAction SilentlyContinue
}

function Invoke-TelemetryAudit {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    Write-Log -Level INFO -Component TELEM-AUDIT -Message 'Starting telemetry & privacy audit'

    try {
        # 1. Load baseline
        $baseline = Get-BaselineList -ModuleFolder 'telemetry' -FileName 'telemetry-list.json'
        if (-not $baseline) {
            return New-ModuleResult -ModuleName 'TelemetryAudit' -Status 'Failed' `
                                    -Message 'Telemetry baseline list not found'
        }

        $diff = [System.Collections.Generic.List[hashtable]]::new()

        # 2. Services that should be disabled
        foreach ($svcName in $baseline.services.disable) {
            try {
                $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
                if ($svc -and $svc.StartType -ne 'Disabled') {
                    $diff.Add(@{
                        Category = 'Service'; Name = $svcName
                        CurrentState = $svc.StartType.ToString(); DesiredState = 'Disabled'
                    })
                    Write-Log -Level DEBUG -Component TELEM-AUDIT -Message "Service active (should disable): $svcName"
                }
            }
            catch { }
        }

        # 3. Registry keys (all sub-arrays: telemetry, advertising, cortana, privacy)
        $regGroups = @('telemetry', 'advertising', 'cortana', 'privacy')
        foreach ($grp in $regGroups) {
            if (-not $baseline.registry.$grp) { continue }
            foreach ($entry in $baseline.registry.$grp) {
                $current = Get-RegistryValue -Path $entry.path -Name $entry.name
                if ($null -eq $current -or $current -ne $entry.desiredValue) {
                    $diff.Add(@{
                        Category     = "Registry-$grp"
                        Name         = "$($entry.path)\$($entry.name)"
                        CurrentState = $current
                        DesiredState = $entry.desiredValue
                        Entry        = $entry
                    })
                    Write-Log -Level DEBUG -Component TELEM-AUDIT -Message "Registry mismatch: $($entry.name) = $current (want $($entry.desiredValue))"
                }
            }
        }

        # 4. Scheduled tasks that should be disabled
        foreach ($taskPath in $baseline.scheduledTasks.disable) {
            try {
                $taskName   = Split-Path $taskPath -Leaf
                $taskFolder = Split-Path $taskPath -Parent
                $task = Get-ScheduledTask -TaskName $taskName -TaskPath "$taskFolder\" -ErrorAction SilentlyContinue
                if ($task -and $task.State -ne 'Disabled') {
                    $diff.Add(@{
                        Category = 'ScheduledTask'; Name = $taskPath
                        CurrentState = $task.State.ToString(); DesiredState = 'Disabled'
                    })
                    Write-Log -Level DEBUG -Component TELEM-AUDIT -Message "Task active (should disable): $taskPath"
                }
            }
            catch { }
        }

        Write-Log -Level INFO -Component TELEM-AUDIT -Message "Telemetry items active: $($diff.Count)"

        # 5. Save diff
        Save-DiffList -ModuleName 'TelemetryDisable' -DiffList $diff.ToArray()

        # 6. Persist
        $auditPath = Get-TempPath -Category 'data' -FileName 'telemetry-audit.json'
        @{ Timestamp = (Get-Date -Format 'o'); ActiveItems = $diff.ToArray() } `
            | ConvertTo-Json -Depth 8 | Set-Content -Path $auditPath -Encoding UTF8 -Force

        Write-Log -Level SUCCESS -Component TELEM-AUDIT -Message "Telemetry audit complete: $($diff.Count) active"
        return New-ModuleResult -ModuleName 'TelemetryAudit' -Status 'Success' `
                                -ItemsDetected $diff.Count `
                                -Message "$($diff.Count) telemetry/privacy items are active"
    }
    catch {
        Write-Log -Level ERROR -Component TELEM-AUDIT -Message "Audit failed: $_"
        return New-ModuleResult -ModuleName 'TelemetryAudit' -Status 'Failed' -Errors @($_.ToString())
    }
}

Export-ModuleMember -Function 'Invoke-TelemetryAudit'
