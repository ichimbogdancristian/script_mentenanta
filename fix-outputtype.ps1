#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Bulk fix all malformed OutputType declarations
#>

$modules = Get-ChildItem -Path "modules" -Filter "*.psm1" -Recurse
$fixCount = 0

foreach ($module in $modules) {
    $path = $module.FullName
    $content = Get-Content $path -Raw
    $original = $content
    
    # Pattern 1: ])\nparam( -> ]\nparam(
    $content = $content -replace '\]\)[\r\n]+param\(', "]`nparam("
    
    # Pattern 2: ]\nparam( -> ]\nparam(  (ensure proper spacing)
    $content = $content -replace '\]\\[\r\n]+param\(', "]`nparam("
    
    # Pattern 3: ]()newline param -> ]newline param
    $content = $content -replace '\]\(\)[\r\n]+param', "]`nparam"
    
    # Pattern 4: ]([params])newline param -> ]\nnew param line
    $content = $content -replace '\]\([^\)]*\)[\r\n]+param', "]`nparam"
    
    if ($original -ne $content) {
        $content | Set-Content $path -Encoding UTF8BOM
        $fixCount++
        Write-Host "✓ Fixed: $($module.Name)" -ForegroundColor Green
    }
}

Write-Host "`nTotal files fixed: $fixCount" -ForegroundColor Cyan
Write-Host "Run PSScriptAnalyzer to verify..." -ForegroundColor Yellow
