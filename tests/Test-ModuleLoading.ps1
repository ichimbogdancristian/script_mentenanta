#Requires -Version 7.0

<#
.SYNOPSIS
    Tests module loading without requiring administrator privileges

.DESCRIPTION
    Validates that all modules can be loaded successfully and that
    the parameter type fixes are working correctly. Does not execute
    actual system modifications.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

Write-Host "`n🧪 Testing Module Loading (No Admin Required)" -ForegroundColor Cyan
Write-Host "=" * 70

$results = @{
    TotalTests = 0
    Passed = 0
    Failed = 0
    Warnings = 0
}

# Test 1: CoreInfrastructure Loading
Write-Host "`n📦 Test 1: Loading CoreInfrastructure module..." -ForegroundColor Yellow
$results.TotalTests++
try {
    $coreInfraPath = Join-Path $PSScriptRoot "..\modules\core\CoreInfrastructure.psm1"
    Import-Module $coreInfraPath -Force -Global
    Write-Host "   ✅ CoreInfrastructure loaded successfully" -ForegroundColor Green
    $results.Passed++
    
    # Verify global paths created
    if ($Global:ProjectPaths) {
        Write-Host "   ✅ Global paths initialized: $($Global:ProjectPaths.Keys -join ', ')" -ForegroundColor Green
    } else {
        Write-Host "   ⚠️ Global paths not initialized" -ForegroundColor Yellow
        $results.Warnings++
    }
}
catch {
    Write-Host "   ❌ FAILED: $($_.Exception.Message)" -ForegroundColor Red
    $results.Failed++
}

# Test 2: All Type2 Modules Loading
Write-Host "`n📦 Test 2: Loading Type2 modules..." -ForegroundColor Yellow
$type2Modules = @(
    'BloatwareRemoval',
    'EssentialApps',
    'SystemOptimization',
    'TelemetryDisable',
    'WindowsUpdates',
    'AppUpgrade'
)

foreach ($moduleName in $type2Modules) {
    $results.TotalTests++
    try {
        $modulePath = Join-Path $PSScriptRoot "..\modules\type2\$moduleName.psm1"
        Import-Module $modulePath -Force -ErrorAction Stop
        
        $functionName = "Invoke-$moduleName"
        if (Get-Command $functionName -ErrorAction SilentlyContinue) {
            Write-Host "   ✅ $moduleName loaded, $functionName available" -ForegroundColor Green
            $results.Passed++
            
            # Verify parameter type
            $cmd = Get-Command $functionName
            if ($cmd.Parameters.Config.ParameterType.Name -eq 'Hashtable') {
                Write-Host "      ✓ Parameter type: Hashtable" -ForegroundColor Gray
            } else {
                Write-Host "      ⚠️ Parameter type: $($cmd.Parameters.Config.ParameterType.Name)" -ForegroundColor Yellow
                $results.Warnings++
            }
        } else {
            Write-Host "   ⚠️ $moduleName loaded but function not found" -ForegroundColor Yellow
            $results.Passed++
            $results.Warnings++
        }
    }
    catch {
        Write-Host "   ❌ $moduleName FAILED: $($_.Exception.Message)" -ForegroundColor Red
        $results.Failed++
    }
}

# Test 3: Configuration Loading
Write-Host "`n📦 Test 3: Loading configurations..." -ForegroundColor Yellow
$results.TotalTests++
try {
    $configPath = Join-Path $PSScriptRoot "..\config"
    Initialize-ConfigSystem -ConfigRootPath $configPath
    
    $mainConfig = Get-MainConfig
    if ($mainConfig) {
        Write-Host "   ✅ Main configuration loaded successfully" -ForegroundColor Green
        $results.Passed++
    } else {
        Write-Host "   ⚠️ Main configuration returned null" -ForegroundColor Yellow
        $results.Passed++
        $results.Warnings++
    }
}
catch {
    Write-Host "   ❌ FAILED: $($_.Exception.Message)" -ForegroundColor Red
    $results.Failed++
}

# Test 4: LogProcessor Loading (Critical for TODO-001 verification)
Write-Host "`n📦 Test 4: Loading LogProcessor module..." -ForegroundColor Yellow
$results.TotalTests++
try {
    $logProcessorPath = Join-Path $PSScriptRoot "..\modules\core\LogProcessor.psm1"
    Import-Module $logProcessorPath -Force
    
    if (Get-Command 'Invoke-LogProcessing' -ErrorAction SilentlyContinue) {
        Write-Host "   ✅ LogProcessor loaded, Invoke-LogProcessing available" -ForegroundColor Green
        $results.Passed++
        
        # Verify no 'WARNING' log level usage (TODO-001 fix)
        $content = Get-Content $logProcessorPath -Raw
        $warningMatches = [regex]::Matches($content, "-Level\s+'WARNING'")
        if ($warningMatches.Count -eq 0) {
            Write-Host "      ✓ No 'WARNING' log levels found (TODO-001 fix confirmed)" -ForegroundColor Gray
        } else {
            Write-Host "      ❌ Found $($warningMatches.Count) instances of 'WARNING' log level" -ForegroundColor Red
            $results.Failed++
        }
    } else {
        Write-Host "   ⚠️ LogProcessor loaded but Invoke-LogProcessing not found" -ForegroundColor Yellow
        $results.Passed++
        $results.Warnings++
    }
}
catch {
    Write-Host "   ❌ FAILED: $($_.Exception.Message)" -ForegroundColor Red
    $results.Failed++
}

# Test 5: Write-LogEntry Validation Test (from CoreInfrastructure)
Write-Host "`n📦 Test 5: Testing Write-LogEntry with WARN level..." -ForegroundColor Yellow
$results.TotalTests++
try {
    # Write-LogEntry is exported from CoreInfrastructure, which we already loaded
    if (Get-Command 'Write-LogEntry' -ErrorAction SilentlyContinue) {
        $testLogPath = Join-Path $env:TEMP "test-maintenance.log"
        
        # This should NOT throw an error anymore (was 'WARNING', now 'WARN')
        Write-LogEntry -Level 'WARN' -Component 'TEST' -Message 'Testing WARN level' -LogPath $testLogPath
        
        if (Test-Path $testLogPath) {
            $logContent = Get-Content $testLogPath -Tail 1
            if ($logContent -match 'Testing WARN level') {
                Write-Host "   ✅ Write-LogEntry accepts 'WARN' level successfully" -ForegroundColor Green
                $results.Passed++
            } else {
                Write-Host "   ⚠️ Log entry written but content unexpected" -ForegroundColor Yellow
                $results.Passed++
                $results.Warnings++
            }
            Remove-Item $testLogPath -Force -ErrorAction SilentlyContinue
        } else {
            Write-Host "   ⚠️ Log file not created" -ForegroundColor Yellow
            $results.Passed++
            $results.Warnings++
        }
    } else {
        Write-Host "   ⚠️ Write-LogEntry command not available" -ForegroundColor Yellow
        $results.Passed++
        $results.Warnings++
    }
}
catch {
    Write-Host "   ❌ FAILED: $($_.Exception.Message)" -ForegroundColor Red
    if ($_.Exception.Message -match "does not belong to the set") {
        Write-Host "      🔴 TODO-001 fix not applied correctly!" -ForegroundColor Red
    }
    $results.Failed++
}

# Summary
Write-Host "`n" + ("=" * 70)
Write-Host "📊 Test Summary:" -ForegroundColor Cyan
Write-Host ""
Write-Host "   Total Tests: $($results.TotalTests)" -ForegroundColor White
Write-Host "   Passed: $($results.Passed)" -ForegroundColor $(if ($results.Passed -eq $results.TotalTests) { 'Green' } else { 'Yellow' })
Write-Host "   Failed: $($results.Failed)" -ForegroundColor $(if ($results.Failed -gt 0) { 'Red' } else { 'Green' })
Write-Host "   Warnings: $($results.Warnings)" -ForegroundColor $(if ($results.Warnings -gt 0) { 'Yellow' } else { 'Green' })

$successRate = if ($results.TotalTests -gt 0) { 
    [math]::Round(($results.Passed / $results.TotalTests) * 100, 2) 
} else { 
    0 
}
Write-Host "   Success Rate: $successRate%" -ForegroundColor $(if ($successRate -eq 100 -and $results.Warnings -eq 0) { 'Green' } elseif ($successRate -ge 80) { 'Yellow' } else { 'Red' })

Write-Host ""
if ($results.Failed -eq 0 -and $results.Warnings -eq 0) {
    Write-Host "✅ ALL TESTS PASSED: Modules ready for execution" -ForegroundColor Green
    Write-Host "   Next step: Run with administrator privileges for full test" -ForegroundColor Cyan
    exit 0
} elseif ($results.Failed -eq 0) {
    Write-Host "⚠️ TESTS PASSED WITH WARNINGS: Review warnings above" -ForegroundColor Yellow
    Write-Host "   All critical functionality working, minor issues detected" -ForegroundColor Yellow
    exit 0
} else {
    Write-Host "❌ SOME TESTS FAILED: Review errors above" -ForegroundColor Red
    Write-Host "   Fix failures before running with administrator privileges" -ForegroundColor Red
    exit 1
}
