#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Comprehensive fix for all malformed OutputType patterns
#>

$problemFiles = @(
    'modules\type1\SystemInventory.psm1',
    'modules\type1\SecurityAudit.psm1',
    'modules\core\ReportGenerator.psm1',
    'modules\core\LogProcessor.psm1'
)

foreach ($file in $problemFiles) {
    if (Test-Path $file) {
        $content = Get-Content $file -Raw
        $before = $content
        
        # Fix: ]( + newline(s) + param -> ]\nparam
        $content = $content -replace '\]\([\r\n\s]+param', "]`nparam"
        
        if ($before -ne $content) {
            $content | Set-Content $file -Encoding UTF8BOM
            Write-Host "Fixed: $(Split-Path -Leaf $file)" -ForegroundColor Green
        }
    }
}

Write-Host "`nDone!" -ForegroundColor Cyan
