# Script: maintenance_report.ps1
# Purpose: Aggregate and summarize maintenance logs for install, uninstall, update, remove, delete actions

$logFolder = $PSScriptRoot
$reportFile = Join-Path $logFolder 'final_report.txt'

$actions = @('install', 'uninstall', 'update', 'remove', 'delete')
$taskLogs = Get-ChildItem -Path $logFolder -Filter 'task_*.log' -File

$summary = @()
foreach ($log in $taskLogs) {
    $lines = Get-Content $log.FullName
    foreach ($action in $actions) {
        $actionMatches = $lines | Select-String -Pattern $action -CaseSensitive:$false
        foreach ($match in $actionMatches) {
            $summary += "[$($log.Name)] $($match.Line)"
        }
    }
}

if ($summary.Count -eq 0) {
    $summary = 'No install, uninstall, update, remove, or delete actions found in logs.'
}

$summary | Out-File -FilePath $reportFile -Encoding UTF8
Write-Host "Final report generated: $reportFile"
