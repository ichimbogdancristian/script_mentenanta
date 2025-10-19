#Requires -Version 7.0

<#
.SYNOPSIS
    Quick test script to verify all Type2 modules load and register correctly
#>

$ScriptRoot = $PSScriptRoot
Write-Host "`n🧪 Testing Module Loading System`n" -ForegroundColor Cyan

# Set up environment like orchestrator does
$env:MAINTENANCE_PROJECT_ROOT = $ScriptRoot
$env:MAINTENANCE_CONFIG_ROOT = Join-Path $ScriptRoot 'config'
$env:MAINTENANCE_MODULES_ROOT = Join-Path $ScriptRoot 'modules'
$env:MAINTENANCE_TEMP_ROOT = Join-Path $ScriptRoot 'temp_files'
$env:MAINTENANCE_REPORTS_ROOT = $ScriptRoot

$ModulesPath = Join-Path $ScriptRoot 'modules'

# Load CoreInfrastructure first
Write-Host "📦 Loading CoreInfrastructure..." -ForegroundColor Yellow
Import-Module (Join-Path $ModulesPath 'core\CoreInfrastructure.psm1') -Force

# Test Type2 modules
$Type2Modules = @('BloatwareRemoval', 'EssentialApps', 'SystemOptimization', 'TelemetryDisable', 'WindowsUpdates')
$LoadedCount = 0
$FailedModules = @()

foreach ($moduleName in $Type2Modules) {
    Write-Host "`n📦 Loading Type2 module: $moduleName" -ForegroundColor Yellow
    try {
        $modulePath = Join-Path $ModulesPath "type2\$moduleName.psm1"
        Import-Module $modulePath -Force -ErrorAction Stop
        
        $invokeFunction = "Invoke-$moduleName"
        if (Get-Command $invokeFunction -ErrorAction SilentlyContinue) {
            Write-Host "  ✅ $moduleName loaded successfully, $invokeFunction available" -ForegroundColor Green
            $LoadedCount++
        }
        else {
            Write-Host "  ❌ $moduleName loaded but $invokeFunction not found" -ForegroundColor Red
            $FailedModules += $moduleName
        }
    }
    catch {
        Write-Host "  ❌ Failed to load $moduleName" -ForegroundColor Red
        Write-Host "     Error: $($_.Exception.Message)" -ForegroundColor Red
        $FailedModules += $moduleName
    }
}

# Summary
Write-Host "`n" + ("=" * 60) -ForegroundColor Cyan
Write-Host "📊 MODULE LOADING SUMMARY" -ForegroundColor Cyan
Write-Host ("=" * 60) -ForegroundColor Cyan
Write-Host "✅ Successfully loaded: $LoadedCount/$($Type2Modules.Count) modules" -ForegroundColor Green

if ($FailedModules.Count -gt 0) {
    Write-Host "❌ Failed modules: $($FailedModules -join ', ')" -ForegroundColor Red
}
else {
    Write-Host "🎉 ALL MODULES LOADED SUCCESSFULLY!" -ForegroundColor Green
}

Write-Host ("=" * 60) + "`n" -ForegroundColor Cyan
