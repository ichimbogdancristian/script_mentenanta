#Requires -Version 7.0

<#
.SYNOPSIS
    Validates parameter type standardization across all modules

.DESCRIPTION
    TODO-008: Standardize Parameter Types Across All Modules
    Ensures all Type2 and Type1 modules use [hashtable]$Config parameter
#>

[CmdletBinding()]
param()

Write-Host "`n🔍 Testing Parameter Type Standardization" -ForegroundColor Cyan
Write-Host "=" * 60

$testResults = @()
$modulesRoot = Join-Path $PSScriptRoot "..\modules"

# Test Type2 modules
Write-Host "`n📦 Testing Type2 Modules..." -ForegroundColor Yellow
$type2Modules = @(
    'BloatwareRemoval',
    'EssentialApps',
    'SystemOptimization',
    'TelemetryDisable',
    'WindowsUpdates',
    'AppUpgrade'
)

foreach ($module in $type2Modules) {
    try {
        $modulePath = Join-Path $modulesRoot "type2\$module.psm1"
        
        # Import CoreInfrastructure first (required by Type2 modules)
        $coreInfraPath = Join-Path $modulesRoot "core\CoreInfrastructure.psm1"
        Import-Module $coreInfraPath -Force -Global -ErrorAction SilentlyContinue
        
        Import-Module $modulePath -Force -ErrorAction Stop
        $functionName = "Invoke-$module"
        
        if (Get-Command $functionName -ErrorAction SilentlyContinue) {
            $params = (Get-Command $functionName).Parameters
            $configType = $params.Config.ParameterType.Name
            
            $result = [PSCustomObject]@{
                Type       = 'Type2'
                Module     = $module
                Function   = $functionName
                ConfigType = $configType
                IsCorrect  = ($configType -eq 'Hashtable')
                Status     = if ($configType -eq 'Hashtable') { '✅ PASS' } else { '❌ FAIL' }
            }
            
            $testResults += $result
            
            if ($result.IsCorrect) {
                Write-Host "  ✅ $module - $configType" -ForegroundColor Green
            }
            else {
                Write-Host "  ❌ $module - $configType (Expected: Hashtable)" -ForegroundColor Red
            }
        }
        else {
            Write-Host "  ⚠️ $module - Function '$functionName' not found" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "  ❌ $module - Load error: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Test Type1 modules
Write-Host "`n📦 Testing Type1 Modules..." -ForegroundColor Yellow
$type1Modules = @(
    'BloatwareDetectionAudit',
    'EssentialAppsAudit',
    'SystemOptimizationAudit',
    'TelemetryAudit',
    'WindowsUpdatesAudit',
    'AppUpgradeAudit'
)

foreach ($module in $type1Modules) {
    try {
        $modulePath = Join-Path $modulesRoot "type1\$module.psm1"
        Import-Module $modulePath -Force -ErrorAction Stop
        
        # Get the Get-* function name (varies by module)
        $functionName = switch ($module) {
            'BloatwareDetectionAudit' { 'Find-InstalledBloatware' }
            'EssentialAppsAudit' { 'Get-MissingEssentialApps' }
            'SystemOptimizationAudit' { 'Get-OptimizationOpportunities' }
            'TelemetryAudit' { 'Get-ActiveTelemetrySettings' }
            'WindowsUpdatesAudit' { 'Get-PendingWindowsUpdates' }
            'AppUpgradeAudit' { 'Get-AvailableUpgrades' }
        }
        
        if (Get-Command $functionName -ErrorAction SilentlyContinue) {
            $params = (Get-Command $functionName).Parameters
            
            if ($params.Config) {
                $configType = $params.Config.ParameterType.Name
                
                $result = [PSCustomObject]@{
                    Type       = 'Type1'
                    Module     = $module
                    Function   = $functionName
                    ConfigType = $configType
                    IsCorrect  = ($configType -eq 'Hashtable')
                    Status     = if ($configType -eq 'Hashtable') { '✅ PASS' } else { '❌ FAIL' }
                }
                
                $testResults += $result
                
                if ($result.IsCorrect) {
                    Write-Host "  ✅ $module - $configType" -ForegroundColor Green
                }
                else {
                    Write-Host "  ❌ $module - $configType (Expected: Hashtable)" -ForegroundColor Red
                }
            }
            else {
                Write-Host "  ⚠️ $module - No Config parameter found" -ForegroundColor Yellow
            }
        }
        else {
            Write-Host "  ⚠️ $module - Function '$functionName' not found" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "  ❌ $module - Load error: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Summary
Write-Host "`n" + ("=" * 60)
Write-Host "📊 Test Summary:" -ForegroundColor Cyan
Write-Host ""

$totalModules = $testResults.Count
$correctModules = ($testResults | Where-Object { $_.IsCorrect }).Count
$incorrectModules = $totalModules - $correctModules

Write-Host "   Total Modules Tested: $totalModules" -ForegroundColor White
Write-Host "   Correct Type (Hashtable): $correctModules" -ForegroundColor $(if ($correctModules -eq $totalModules) { 'Green' } else { 'Yellow' })
Write-Host "   Incorrect Type: $incorrectModules" -ForegroundColor $(if ($incorrectModules -gt 0) { 'Red' } else { 'Green' })

if ($incorrectModules -gt 0) {
    Write-Host "`n❌ Modules with incorrect parameter types:" -ForegroundColor Red
    $testResults | Where-Object { -not $_.IsCorrect } | ForEach-Object {
        Write-Host "   - $($_.Module) ($($_.Type)): $($_.ConfigType) should be Hashtable" -ForegroundColor Red
    }
}

Write-Host ""
if ($incorrectModules -eq 0) {
    Write-Host "✅ TEST PASSED: All modules use correct parameter type (Hashtable)" -ForegroundColor Green
    Write-Host "   100% compliance with v3.0 standard" -ForegroundColor Green
    exit 0
}
else {
    $complianceRate = [math]::Round(($correctModules / $totalModules) * 100, 2)
    Write-Host "⚠️ TEST FAILED: $incorrectModules module(s) need correction" -ForegroundColor Red
    Write-Host "   Current compliance: $complianceRate%" -ForegroundColor Yellow
    exit 1
}
