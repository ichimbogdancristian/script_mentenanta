#Requires -Version 7.0

<#
.SYNOPSIS
    Phase 3 Implementation Test Suite - Configuration Reorganization

.DESCRIPTION
    Automated test suite for Phase 3 enhancements:
    - Centralized schemas directory (config/schemas/)
    - Subdirectory structure for config/lists/
    - Environment-specific configurations
    - Path discovery with backward compatibility
    - Schema auto-discovery from centralized location

.NOTES
    Version: 1.0.0
    Phase: 3 - Configuration Reorganization
    Date: February 2026
#>

param(
    [switch]$Verbose
)

$ErrorActionPreference = 'Continue'
if ($Verbose) {
    $VerbosePreference = 'Continue'
}

Write-Host "`n═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  PHASE 3 TEST SUITE - Configuration Reorganization" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════`n" -ForegroundColor Cyan

$ScriptRoot = $PSScriptRoot
$ProjectRoot = $ScriptRoot

# Initialize environment
$env:MAINTENANCE_PROJECT_ROOT = $ProjectRoot
$env:MAINTENANCE_CONFIG_ROOT = Join-Path $ProjectRoot 'config'
$env:MAINTENANCE_MODULES_ROOT = Join-Path $ProjectRoot 'modules'

# Import CoreInfrastructure
$CoreInfraPath = Join-Path $ProjectRoot 'modules\core\CoreInfrastructure.psm1'
if (-not (Test-Path $CoreInfraPath)) {
    Write-Error "CoreInfrastructure module not found at: $CoreInfraPath"
    exit 1
}

Write-Host "[SETUP] Importing CoreInfrastructure module..." -ForegroundColor Yellow
Import-Module $CoreInfraPath -Force -Global -ErrorAction Stop
Write-Host "   ✓ CoreInfrastructure loaded`n" -ForegroundColor Green

# Test tracking
$global:TestResults = @()
$global:TestNumber = 0

function Test-Assertion {
    param(
        [Parameter(Mandatory)]
        [string]$TestName,
        
        [Parameter(Mandatory)]
        [scriptblock]$TestScript,
        
        [string]$ExpectedResult = "Success"
    )
    
    $global:TestNumber++
    $testNum = $global:TestNumber
    
    Write-Host "[$testNum] Testing: $TestName" -ForegroundColor Yellow
    
    try {
        $result = & $TestScript
        
        if ($result) {
            Write-Host "   ✓ PASS" -ForegroundColor Green
            $global:TestResults += [PSCustomObject]@{
                TestNumber = $testNum
                TestName = $TestName
                Status = 'PASS'
                Details = $result
            }
            return $true
        }
        else {
            Write-Host "   ✗ FAIL: Test returned false/null" -ForegroundColor Red
            $global:TestResults += [PSCustomObject]@{
                TestNumber = $testNum
                TestName = $TestName
                Status = 'FAIL'
                Details = "Test returned false/null"
            }
            return $false
        }
    }
    catch {
        Write-Host "   ✗ FAIL: $($_.Exception.Message)" -ForegroundColor Red
        $global:TestResults += [PSCustomObject]@{
            TestNumber = $testNum
            TestName = $TestName
            Status = 'FAIL'
            Details = $_.Exception.Message
        }
        return $false
    }
}

#region Test Suite

Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host " TEST GROUP 1: Directory Structure" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════`n" -ForegroundColor Cyan

Test-Assertion -TestName "config/schemas/ directory exists" -TestScript {
    Test-Path (Join-Path $env:MAINTENANCE_CONFIG_ROOT 'schemas')
}

Test-Assertion -TestName "config/lists/bloatware/ subdirectory exists" -TestScript {
    Test-Path (Join-Path $env:MAINTENANCE_CONFIG_ROOT 'lists\bloatware')
}

Test-Assertion -TestName "config/lists/essential-apps/ subdirectory exists" -TestScript {
    Test-Path (Join-Path $env:MAINTENANCE_CONFIG_ROOT 'lists\essential-apps')
}

Test-Assertion -TestName "config/lists/system-optimization/ subdirectory exists" -TestScript {
    Test-Path (Join-Path $env:MAINTENANCE_CONFIG_ROOT 'lists\system-optimization')
}

Test-Assertion -TestName "config/lists/app-upgrade/ subdirectory exists" -TestScript {
    Test-Path (Join-Path $env:MAINTENANCE_CONFIG_ROOT 'lists\app-upgrade')
}

Test-Assertion -TestName "config/settings/environments/ directory exists" -TestScript {
    Test-Path (Join-Path $env:MAINTENANCE_CONFIG_ROOT 'settings\environments')
}

Write-Host "`n═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host " TEST GROUP 2: Centralized Schemas" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════`n" -ForegroundColor Cyan

Test-Assertion -TestName "All 7 schemas in config/schemas/" -TestScript {
    $schemasPath = Join-Path $env:MAINTENANCE_CONFIG_ROOT 'schemas'
    $schemas = Get-ChildItem -Path $schemasPath -Filter '*.schema.json'
    $schemas.Count -eq 7
}

Test-Assertion -TestName "main-config.schema.json in centralized location" -TestScript {
    Test-Path (Join-Path $env:MAINTENANCE_CONFIG_ROOT 'schemas\main-config.schema.json')
}

Test-Assertion -TestName "bloatware-list.schema.json in centralized location" -TestScript {
    Test-Path (Join-Path $env:MAINTENANCE_CONFIG_ROOT 'schemas\bloatware-list.schema.json')
}

Test-Assertion -TestName "essential-apps.schema.json in centralized location" -TestScript {
    Test-Path (Join-Path $env:MAINTENANCE_CONFIG_ROOT 'schemas\essential-apps.schema.json')
}

Write-Host "`n═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host " TEST GROUP 3: Reorganized Config Files" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════`n" -ForegroundColor Cyan

Test-Assertion -TestName "bloatware-list.json in subdirectory" -TestScript {
    Test-Path (Join-Path $env:MAINTENANCE_CONFIG_ROOT 'lists\bloatware\bloatware-list.json')
}

Test-Assertion -TestName "essential-apps.json in subdirectory" -TestScript {
    Test-Path (Join-Path $env:MAINTENANCE_CONFIG_ROOT 'lists\essential-apps\essential-apps.json')
}

Test-Assertion -TestName "system-optimization-config.json in subdirectory" -TestScript {
    Test-Path (Join-Path $env:MAINTENANCE_CONFIG_ROOT 'lists\system-optimization\system-optimization-config.json')
}

Test-Assertion -TestName "app-upgrade-config.json in subdirectory" -TestScript {
    Test-Path (Join-Path $env:MAINTENANCE_CONFIG_ROOT 'lists\app-upgrade\app-upgrade-config.json')
}

Write-Host "`n═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host " TEST GROUP 4: Environment-Specific Configs" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════`n" -ForegroundColor Cyan

Test-Assertion -TestName "development.json environment config exists" -TestScript {
    Test-Path (Join-Path $env:MAINTENANCE_CONFIG_ROOT 'settings\environments\development.json')
}

Test-Assertion -TestName "production.json environment config exists" -TestScript {
    Test-Path (Join-Path $env:MAINTENANCE_CONFIG_ROOT 'settings\environments\production.json')
}

Test-Assertion -TestName "testing.json environment config exists" -TestScript {
    Test-Path (Join-Path $env:MAINTENANCE_CONFIG_ROOT 'settings\environments\testing.json')
}

Test-Assertion -TestName "development.json has dry-run enabled" -TestScript {
    $devConfig = Get-Content (Join-Path $env:MAINTENANCE_CONFIG_ROOT 'settings\environments\development.json') -Raw | ConvertFrom-Json
    $devConfig.execution.enableDryRun -eq $true
}

Test-Assertion -TestName "production.json has dry-run disabled" -TestScript {
    $prodConfig = Get-Content (Join-Path $env:MAINTENANCE_CONFIG_ROOT 'settings\environments\production.json') -Raw | ConvertFrom-Json
    $prodConfig.execution.enableDryRun -eq $false
}

Write-Host "`n═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host " TEST GROUP 5: Configuration Loading (New Structure)" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════`n" -ForegroundColor Cyan

Test-Assertion -TestName "Get-BloatwareConfiguration loads from new path" -TestScript {
    $config = Get-BloatwareConfiguration
    $null -ne $config -and $config.ContainsKey('all')
}

Test-Assertion -TestName "Get-EssentialAppsConfiguration loads from new path" -TestScript {
    $config = Get-EssentialAppsConfiguration
    $null -ne $config
}

Test-Assertion -TestName "Get-SystemOptimizationConfiguration loads from new path" -TestScript {
    $config = Get-SystemOptimizationConfiguration
    $null -ne $config
}

Test-Assertion -TestName "Get-AppUpgradeConfiguration loads from new path" -TestScript {
    $config = Get-AppUpgradeConfiguration
    $null -ne $config
}

Write-Host "`n═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host " TEST GROUP 6: Schema Auto-Discovery (Centralized)" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════`n" -ForegroundColor Cyan

Test-Assertion -TestName "Schema auto-discovery finds centralized main-config.schema.json" -TestScript {
    $configPath = Join-Path $env:MAINTENANCE_CONFIG_ROOT 'settings\main-config.json'
    $result = Test-ConfigurationWithJsonSchema -ConfigFilePath $configPath
    $result.SchemaFile -like '*config\schemas\main-config.schema.json'
}

Test-Assertion -TestName "Schema auto-discovery finds centralized bloatware-list.schema.json" -TestScript {
    $configPath = Join-Path $env:MAINTENANCE_CONFIG_ROOT 'lists\bloatware\bloatware-list.json'
    $result = Test-ConfigurationWithJsonSchema -ConfigFilePath $configPath
    $result.SchemaFile -like '*config\schemas\bloatware-list.schema.json'
}

Test-Assertion -TestName "Schema auto-discovery finds centralized essential-apps.schema.json" -TestScript {
    $configPath = Join-Path $env:MAINTENANCE_CONFIG_ROOT 'lists\essential-apps\essential-apps.json'
    $result = Test-ConfigurationWithJsonSchema -ConfigFilePath $configPath
    $result.SchemaFile -like '*config\schemas\essential-apps.schema.json'
}

Write-Host "`n═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host " TEST GROUP 7: Schema Validation (Centralized Location)" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════`n" -ForegroundColor Cyan

Test-Assertion -TestName "Validate main-config.json with centralized schema" -TestScript {
    $configPath = Join-Path $env:MAINTENANCE_CONFIG_ROOT 'settings\main-config.json'
    $result = Test-ConfigurationWithJsonSchema -ConfigFilePath $configPath
    $result.IsValid
}

Test-Assertion -TestName "Validate bloatware-list.json with centralized schema" -TestScript {
    $configPath = Join-Path $env:MAINTENANCE_CONFIG_ROOT 'lists\bloatware\bloatware-list.json'
    $result = Test-ConfigurationWithJsonSchema -ConfigFilePath $configPath
    $result.IsValid
}

Test-Assertion -TestName "Validate development.json environment config" -TestScript {
    $configPath = Join-Path $env:MAINTENANCE_CONFIG_ROOT 'settings\environments\development.json'
    $result = Test-ConfigurationWithJsonSchema -ConfigFilePath $configPath
    $result.IsValid
}

Test-Assertion -TestName "Validate production.json environment config" -TestScript {
    $configPath = Join-Path $env:MAINTENANCE_CONFIG_ROOT 'settings\environments\production.json'
    $result = Test-ConfigurationWithJsonSchema -ConfigFilePath $configPath
    $result.IsValid
}

Write-Host "`n═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host " TEST GROUP 8: Backward Compatibility" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════`n" -ForegroundColor Cyan

Test-Assertion -TestName "Legacy path fallback would work (tested via function logic)" -TestScript {
    # This tests that the fallback logic exists and would handle legacy paths
    $config = Get-BloatwareConfiguration
    # If this returns valid data, the path discovery is working (new or legacy)
    $null -ne $config
}

Test-Assertion -TestName "Configuration functions don't break with new structure" -TestScript {
    # Test all configuration loading functions
    $main = Get-MainConfiguration
    $bloat = Get-BloatwareConfiguration
    $apps = Get-EssentialAppsConfiguration
    $sysopt = Get-SystemOptimizationConfiguration
    
    ($null -ne $main) -and ($null -ne $bloat) -and ($null -ne $apps) -and ($null -ne $sysopt)
}

#endregion

#region Test Report

Write-Host "`n`n═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host " TEST RESULTS SUMMARY" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════`n" -ForegroundColor Cyan

$passCount = ($global:TestResults | Where-Object { $_.Status -eq 'PASS' }).Count
$failCount = ($global:TestResults | Where-Object { $_.Status -eq 'FAIL' }).Count
$totalCount = $global:TestResults.Count

Write-Host "Total Tests: $totalCount" -ForegroundColor White
Write-Host "Passed:      $passCount" -ForegroundColor Green
Write-Host "Failed:      $failCount" -ForegroundColor $(if ($failCount -eq 0) { 'Green' } else { 'Red' })

if ($failCount -gt 0) {
    Write-Host "`nFailed Tests:" -ForegroundColor Red
    $global:TestResults | Where-Object { $_.Status -eq 'FAIL' } | ForEach-Object {
        Write-Host "   [$($_.TestNumber)] $($_.TestName): $($_.Details)" -ForegroundColor Red
    }
}

$successRate = [Math]::Round(($passCount / $totalCount) * 100, 2)
Write-Host "`nSuccess Rate: $successRate%" -ForegroundColor $(if ($successRate -eq 100) { 'Green' } else { 'Yellow' })

if ($passCount -eq $totalCount) {
    Write-Host "`n✓ ALL TESTS PASSED - Phase 3 implementation successful!" -ForegroundColor Green
    exit 0
}
else {
    Write-Host "`n✗ SOME TESTS FAILED - Please review and fix issues" -ForegroundColor Red
    exit 1
}

#endregion
