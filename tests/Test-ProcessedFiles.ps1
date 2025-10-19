#Requires -Version 7.0

<#
.SYNOPSIS
    Verifies all required processed data files are created by LogProcessor

.DESCRIPTION
    TODO-004: Verify Processed Data Files Creation
    Checks for existence and validity of all 5 processed files
#>

[CmdletBinding()]
param()

Write-Host "`n🔍 Testing Processed Data Files Creation" -ForegroundColor Cyan
Write-Host "=" * 60

$processedPath = Join-Path $PSScriptRoot "..\temp_files\processed"
$requiredFiles = @(
    'health-scores.json',
    'metrics-summary.json',
    'module-results.json',
    'maintenance-log.json',
    'errors-analysis.json'
)

$results = @{
    Total   = $requiredFiles.Count
    Found   = 0
    Missing = 0
    Valid   = 0
    Invalid = 0
}

foreach ($file in $requiredFiles) {
    $filePath = Join-Path $processedPath $file
    
    if (Test-Path $filePath) {
        $results.Found++
        $fileInfo = Get-Item $filePath
        $size = $fileInfo.Length
        
        Write-Host "✅ $file" -ForegroundColor Green
        Write-Host "   Path: $filePath" -ForegroundColor Gray
        Write-Host "   Size: $size bytes" -ForegroundColor Gray
        Write-Host "   Modified: $($fileInfo.LastWriteTime)" -ForegroundColor Gray
        
        # Try to parse as JSON
        try {
            $content = Get-Content $filePath -Raw | ConvertFrom-Json
            Write-Host "   JSON: Valid ✓" -ForegroundColor Green
            
            # Count properties/items
            if ($content -is [System.Array]) {
                Write-Host "   Items: $($content.Count)" -ForegroundColor Cyan
            }
            elseif ($content.PSObject.Properties) {
                Write-Host "   Properties: $($content.PSObject.Properties.Count)" -ForegroundColor Cyan
            }
            
            $results.Valid++
        }
        catch {
            Write-Host "   JSON: Invalid ✗ - $($_.Exception.Message)" -ForegroundColor Red
            $results.Invalid++
        }
    }
    else {
        $results.Missing++
        Write-Host "❌ $file - MISSING" -ForegroundColor Red
        Write-Host "   Expected: $filePath" -ForegroundColor Gray
    }
    Write-Host ""
}

# Summary
Write-Host "=" * 60
Write-Host "📊 Summary:" -ForegroundColor Cyan
Write-Host "   Total Required: $($results.Total)" -ForegroundColor White
Write-Host "   Found: $($results.Found)" -ForegroundColor $(if ($results.Found -eq $results.Total) { 'Green' } else { 'Yellow' })
Write-Host "   Missing: $($results.Missing)" -ForegroundColor $(if ($results.Missing -gt 0) { 'Red' } else { 'Green' })
Write-Host "   Valid JSON: $($results.Valid)" -ForegroundColor $(if ($results.Valid -eq $results.Found) { 'Green' } else { 'Yellow' })
Write-Host "   Invalid JSON: $($results.Invalid)" -ForegroundColor $(if ($results.Invalid -gt 0) { 'Red' } else { 'Green' })

# Overall result
Write-Host ""
if ($results.Missing -eq 0 -and $results.Invalid -eq 0) {
    Write-Host "✅ TEST PASSED: All processed files present and valid" -ForegroundColor Green
    exit 0
}
elseif ($results.Missing -gt 0) {
    Write-Host "❌ TEST FAILED: $($results.Missing) files missing" -ForegroundColor Red
    Write-Host "   Run LogProcessor after fixing TODO-001 to generate missing files" -ForegroundColor Yellow
    exit 1
}
else {
    Write-Host "⚠️ TEST WARNING: All files present but $($results.Invalid) have invalid JSON" -ForegroundColor Yellow
    exit 2
}
