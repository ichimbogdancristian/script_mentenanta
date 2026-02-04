#Requires -Version 7.0

<#
.SYNOPSIS
    Phase 2 Implementation Test Suite - JSON Schema Validation

.DESCRIPTION
    Automated test suite for Phase 2 enhancements:
    - JSON Schema validation functions
    - Configuration validation against schemas
    - Schema auto-discovery
    - Batch validation
    - Error handling and reporting

.NOTES
    Version: 1.0.0
    Phase: 2 - JSON Schema Validation Framework
    Date: 2025-01-XX
#>

param(
    [switch]$Verbose
)

$ErrorActionPreference = 'Continue'
if ($Verbose) {
    $VerbosePreference = 'Continue'
}

Write-Host "`n═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  PHASE 2 TEST SUITE - JSON Schema Validation Framework" -ForegroundColor Cyan
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
Write-Host " TEST GROUP 1: Schema Files Existence" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════`n" -ForegroundColor Cyan

Test-Assertion -TestName "main-config.schema.json exists" -TestScript {
    $schemaPath = Join-Path $env:MAINTENANCE_CONFIG_ROOT 'settings\main-config.schema.json'
    Test-Path $schemaPath
}

Test-Assertion -TestName "logging-config.schema.json exists" -TestScript {
    $schemaPath = Join-Path $env:MAINTENANCE_CONFIG_ROOT 'settings\logging-config.schema.json'
    Test-Path $schemaPath
}

Test-Assertion -TestName "security-config.schema.json exists" -TestScript {
    $schemaPath = Join-Path $env:MAINTENANCE_CONFIG_ROOT 'settings\security-config.schema.json'
    Test-Path $schemaPath
}

Test-Assertion -TestName "bloatware-list.schema.json exists" -TestScript {
    $schemaPath = Join-Path $env:MAINTENANCE_CONFIG_ROOT 'lists\bloatware-list.schema.json'
    Test-Path $schemaPath
}

Test-Assertion -TestName "essential-apps.schema.json exists" -TestScript {
    $schemaPath = Join-Path $env:MAINTENANCE_CONFIG_ROOT 'lists\essential-apps.schema.json'
    Test-Path $schemaPath
}

Test-Assertion -TestName "app-upgrade-config.schema.json exists" -TestScript {
    $schemaPath = Join-Path $env:MAINTENANCE_CONFIG_ROOT 'lists\app-upgrade-config.schema.json'
    Test-Path $schemaPath
}

Test-Assertion -TestName "system-optimization-config.schema.json exists" -TestScript {
    $schemaPath = Join-Path $env:MAINTENANCE_CONFIG_ROOT 'lists\system-optimization-config.schema.json'
    Test-Path $schemaPath
}

Write-Host "`n═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host " TEST GROUP 2: Function Availability" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════`n" -ForegroundColor Cyan

Test-Assertion -TestName "Test-ConfigurationWithJsonSchema function exists" -TestScript {
    $null -ne (Get-Command -Name 'Test-ConfigurationWithJsonSchema' -ErrorAction SilentlyContinue)
}

Test-Assertion -TestName "Test-AllConfigurationsWithSchema function exists" -TestScript {
    $null -ne (Get-Command -Name 'Test-AllConfigurationsWithSchema' -ErrorAction SilentlyContinue)
}

Test-Assertion -TestName "Test-ConfigurationSchema function (legacy) still exists" -TestScript {
    $null -ne (Get-Command -Name 'Test-ConfigurationSchema' -ErrorAction SilentlyContinue)
}

Write-Host "`n═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host " TEST GROUP 3: Schema Validation - Valid Configs" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════`n" -ForegroundColor Cyan

Test-Assertion -TestName "Validate main-config.json" -TestScript {
    $configPath = Join-Path $env:MAINTENANCE_CONFIG_ROOT 'settings\main-config.json'
    $result = Test-ConfigurationWithJsonSchema -ConfigFilePath $configPath
    $result.IsValid
}

Test-Assertion -TestName "Validate logging-config.json" -TestScript {
    $configPath = Join-Path $env:MAINTENANCE_CONFIG_ROOT 'settings\logging-config.json'
    $result = Test-ConfigurationWithJsonSchema -ConfigFilePath $configPath
    $result.IsValid
}

Test-Assertion -TestName "Validate bloatware-list.json" -TestScript {
    $configPath = Join-Path $env:MAINTENANCE_CONFIG_ROOT 'lists\bloatware-list.json'
    $result = Test-ConfigurationWithJsonSchema -ConfigFilePath $configPath
    $result.IsValid
}

Test-Assertion -TestName "Validate essential-apps.json" -TestScript {
    $configPath = Join-Path $env:MAINTENANCE_CONFIG_ROOT 'lists\essential-apps.json'
    $result = Test-ConfigurationWithJsonSchema -ConfigFilePath $configPath
    $result.IsValid
}

Write-Host "`n═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host " TEST GROUP 4: Schema Auto-Discovery" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════`n" -ForegroundColor Cyan

Test-Assertion -TestName "Schema auto-discovery for main-config.json" -TestScript {
    $configPath = Join-Path $env:MAINTENANCE_CONFIG_ROOT 'settings\main-config.json'
    $result = Test-ConfigurationWithJsonSchema -ConfigFilePath $configPath
    $result.SchemaFile -like '*main-config.schema.json'
}

Test-Assertion -TestName "Schema auto-discovery for essential-apps.json" -TestScript {
    $configPath = Join-Path $env:MAINTENANCE_CONFIG_ROOT 'lists\essential-apps.json'
    $result = Test-ConfigurationWithJsonSchema -ConfigFilePath $configPath
    $result.SchemaFile -like '*essential-apps.schema.json'
}

Write-Host "`n═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host " TEST GROUP 5: Batch Validation" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════`n" -ForegroundColor Cyan

Test-Assertion -TestName "Batch validation with Test-AllConfigurationsWithSchema" -TestScript {
    $result = Test-AllConfigurationsWithSchema -ConfigRoot $env:MAINTENANCE_CONFIG_ROOT
    $result.TotalConfigs -gt 0
}

Test-Assertion -TestName "Batch validation reports all valid" -TestScript {
    $result = Test-AllConfigurationsWithSchema -ConfigRoot $env:MAINTENANCE_CONFIG_ROOT
    Write-Host "      Valid: $($result.ValidConfigs), Invalid: $($result.InvalidConfigs)" -ForegroundColor Gray
    $result.AllValid
}

Write-Host "`n═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host " TEST GROUP 6: Error Handling" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════`n" -ForegroundColor Cyan

Test-Assertion -TestName "Graceful handling of missing config file" -TestScript {
    $fakePath = Join-Path $env:MAINTENANCE_CONFIG_ROOT 'settings\nonexistent.json'
    $result = Test-ConfigurationWithJsonSchema -ConfigFilePath $fakePath
    -not $result.IsValid -and $result.Errors.Count -gt 0
}

Test-Assertion -TestName "Graceful handling of missing schema file" -TestScript {
    # Create a temporary config file without schema
    $tempConfig = Join-Path $env:MAINTENANCE_CONFIG_ROOT 'settings\temp-no-schema.json'
    '{"test": true}' | Set-Content -Path $tempConfig -Force
    
    try {
        $result = Test-ConfigurationWithJsonSchema -ConfigFilePath $tempConfig
        # Should mark as valid when schema doesn't exist (allows gradual adoption)
        $result.IsValid
    }
    finally {
        Remove-Item -Path $tempConfig -Force -ErrorAction SilentlyContinue
    }
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
    Write-Host "`n✓ ALL TESTS PASSED - Phase 2 implementation successful!" -ForegroundColor Green
    exit 0
}
else {
    Write-Host "`n✗ SOME TESTS FAILED - Please review and fix issues" -ForegroundColor Red
    exit 1
}

#endregion
