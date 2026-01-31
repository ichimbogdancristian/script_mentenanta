#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Final comprehensive PSScriptAnalyzer validation
#>

Write-Host "🔍 Running PSScriptAnalyzer on all modules..." -ForegroundColor Cyan
Write-Host ""

$modules = Get-ChildItem modules -Filter "*.psm1" -Recurse
$totalIssues = 0
$totalFiles = $modules.Count
$filesWithErrors = 0

$analysis = @()
foreach ($mod in $modules) {
    $result = @(Invoke-ScriptAnalyzer -Path $mod.FullName 2>$null)
    if ($result) {
        $analysis += $result
        $totalIssues += $result.Count
        if (@($result | Where-Object Severity -eq Error).Count -gt 0) {
            $filesWithErrors++
        }
    }
}

Write-Host "Summary:" -ForegroundColor Yellow
Write-Host "  Total modules scanned: $totalFiles"
Write-Host "  Total issues found: $totalIssues"
Write-Host "  Files with parse errors: $filesWithErrors"
Write-Host ""

if ($filesWithErrors -gt 0) {
    Write-Host "⚠️  PARSE ERRORS FOUND:" -ForegroundColor Red
    $analysis | Where-Object Severity -eq Error | ForEach-Object {
        Write-Host "  [$($_.RuleName)] $(Split-Path -Leaf $_.ScriptPath) Line $($_.Line): $($_.Message)"
    }
} else {
    Write-Host "✅ NO PARSE ERRORS!" -ForegroundColor Green
}

Write-Host ""
Write-Host "Issue breakdown:" -ForegroundColor Cyan
$analysis | Group-Object RuleName | Sort-Object Count -Descending | ForEach-Object {
    Write-Host "  $($_.Name): $($_.Count)"
}
