#Requires -Version 7.0

<#
.SYNOPSIS
    Detailed test to verify CoreInfrastructure function availability during Type1 import
#>

$ScriptRoot = $PSScriptRoot
Write-Host "`n🔍 DETAILED MODULE LOADING SEQUENCE TEST`n" -ForegroundColor Cyan

# Set up environment
$env:MAINTENANCE_PROJECT_ROOT = $ScriptRoot
$env:MAINTENANCE_CONFIG_ROOT = Join-Path $ScriptRoot 'config'
$env:MAINTENANCE_MODULES_ROOT = Join-Path $ScriptRoot 'modules'
$env:MAINTENANCE_TEMP_ROOT = Join-Path $ScriptRoot 'temp_files'
$env:MAINTENANCE_REPORTS_ROOT = $ScriptRoot

$ModulesPath = Join-Path $ScriptRoot 'modules'

Write-Host "Step 1: Checking if Write-LogEntry exists BEFORE any imports" -ForegroundColor Yellow
$beforeImport = Get-Command 'Write-LogEntry' -ErrorAction SilentlyContinue
Write-Host "  Result: $($beforeImport -ne $null ? 'EXISTS' : 'DOES NOT EXIST')" -ForegroundColor $(if ($beforeImport) { 'Green' } else { 'Red' })

Write-Host "`nStep 2: Importing CoreInfrastructure module" -ForegroundColor Yellow
Import-Module (Join-Path $ModulesPath 'core\CoreInfrastructure.psm1') -Force -Verbose 4>&1 | Where-Object { $_ -match 'Importing function' } | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }

Write-Host "`nStep 3: Checking if Write-LogEntry exists AFTER CoreInfrastructure import" -ForegroundColor Yellow
$afterCoreImport = Get-Command 'Write-LogEntry' -ErrorAction SilentlyContinue
if ($afterCoreImport) {
    Write-Host "  ✅ Write-LogEntry EXISTS" -ForegroundColor Green
    Write-Host "     Source: $($afterCoreImport.Source)" -ForegroundColor Cyan
    Write-Host "     Module: $($afterCoreImport.ModuleName)" -ForegroundColor Cyan
}
else {
    Write-Host "  ❌ Write-LogEntry DOES NOT EXIST" -ForegroundColor Red
}

Write-Host "`nStep 4: Importing TelemetryDisable Type2 module (which imports TelemetryAudit Type1)" -ForegroundColor Yellow
Write-Host "  This will trigger the check inside TelemetryAudit.psm1..." -ForegroundColor Gray

try {
    Import-Module (Join-Path $ModulesPath 'type2\TelemetryDisable.psm1') -Force -WarningVariable warnings -Verbose 4>&1 | 
    Where-Object { $_ -match 'Importing function|WARNING' } | 
    ForEach-Object { 
        if ($_ -match 'WARNING') {
            Write-Host "  ⚠️  $_" -ForegroundColor Yellow
        }
        else {
            Write-Host "  $_" -ForegroundColor Gray
        }
    }
}
catch {
    Write-Host "  ❌ Error: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "`nStep 5: Final verification - checking Write-LogEntry availability" -ForegroundColor Yellow
$finalCheck = Get-Command 'Write-LogEntry' -ErrorAction SilentlyContinue
if ($finalCheck) {
    Write-Host "  ✅ Write-LogEntry is available" -ForegroundColor Green
    Write-Host "     Source: $($finalCheck.Source)" -ForegroundColor Cyan
}
else {
    Write-Host "  ❌ Write-LogEntry is NOT available" -ForegroundColor Red
}

Write-Host "`nStep 6: Testing if Type1 module function works (Get-TelemetryAnalysis)" -ForegroundColor Yellow
$telemetryFunc = Get-Command 'Get-TelemetryAnalysis' -ErrorAction SilentlyContinue
if ($telemetryFunc) {
    Write-Host "  ✅ Get-TelemetryAnalysis is available" -ForegroundColor Green
    Write-Host "     Source: $($telemetryFunc.Source)" -ForegroundColor Cyan
}
else {
    Write-Host "  ❌ Get-TelemetryAnalysis is NOT available" -ForegroundColor Red
}

Write-Host "`n" + ("=" * 80) -ForegroundColor Cyan
Write-Host "CONCLUSION:" -ForegroundColor Cyan
Write-Host ("=" * 80) -ForegroundColor Cyan

if ($afterCoreImport -and $warnings -match 'CoreInfrastructure module not yet loaded') {
    Write-Host "⚠️  WARNING IS A FALSE POSITIVE!" -ForegroundColor Yellow
    Write-Host "   CoreInfrastructure WAS loaded before Type1 import," -ForegroundColor Yellow
    Write-Host "   but Type1 module still shows warning." -ForegroundColor Yellow
    Write-Host "`n   This suggests the Type1 check happens in a different scope" -ForegroundColor Yellow
    Write-Host "   or there's a timing issue with Get-Command visibility." -ForegroundColor Yellow
}
elseif (-not $afterCoreImport) {
    Write-Host "❌ WARNING IS LEGITIMATE - CoreInfrastructure didn't load properly!" -ForegroundColor Red
}
else {
    Write-Host "✅ Everything loaded correctly without warnings" -ForegroundColor Green
}

Write-Host ("=" * 80) + "`n" -ForegroundColor Cyan
