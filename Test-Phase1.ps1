# Phase 1 Quick Test Script
# Tests ModuleRegistry, CommonUtilities, and merged ShutdownManager functions

param(
    [switch]$Verbose
)

$ErrorActionPreference = 'Stop'
$testResults = @()

function Test-Module {
    param(
        [string]$TestName,
        [scriptblock]$TestScript
    )
    
    Write-Host "`n═══════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "  TEST: $TestName" -ForegroundColor White
    Write-Host "═══════════════════════════════════════" -ForegroundColor Cyan
    
    try {
        & $TestScript
        Write-Host "✓ PASS" -ForegroundColor Green
        $script:testResults += @{ Test = $TestName; Result = 'PASS' }
        return $true
    }
    catch {
        Write-Host "✗ FAIL: $_" -ForegroundColor Red
        $script:testResults += @{ Test = $TestName; Result = 'FAIL'; Error = $_.Exception.Message }
        return $false
    }
}

Write-Host "`n╔════════════════════════════════════════╗" -ForegroundColor Magenta
Write-Host "║  PHASE 1 IMPLEMENTATION TEST SUITE   ║" -ForegroundColor Magenta
Write-Host "╚════════════════════════════════════════╝" -ForegroundColor Magenta

$scriptRoot = $PSScriptRoot

# TEST 1: ModuleRegistry Exists
Test-Module "ModuleRegistry.psm1 Exists" {
    $path = Join-Path $scriptRoot 'modules\core\ModuleRegistry.psm1'
    if (-not (Test-Path $path)) {
        throw "ModuleRegistry.psm1 not found at $path"
    }
    Write-Host "  Found: $path"
}

# TEST 2: CommonUtilities Exists
Test-Module "CommonUtilities.psm1 Exists" {
    $path = Join-Path $scriptRoot 'modules\core\CommonUtilities.psm1'
    if (-not (Test-Path $path)) {
        throw "CommonUtilities.psm1 not found at $path"
    }
    Write-Host "  Found: $path"
}

# TEST 3: ModuleRegistry Import
Test-Module "ModuleRegistry Import" {
    $path = Join-Path $scriptRoot 'modules\core\ModuleRegistry.psm1'
    Import-Module $path -Force -ErrorAction Stop
    
    $functions = @('Get-RegisteredModules', 'Get-ModuleMetadata', 'Test-ModuleDependencies', 'Show-ModuleInventory')
    foreach ($func in $functions) {
        if (-not (Get-Command $func -ErrorAction SilentlyContinue)) {
            throw "Function $func not exported"
        }
        Write-Host "  ✓ $func exported"
    }
}

# TEST 4: CommonUtilities Import
Test-Module "CommonUtilities Import" {
    $path = Join-Path $scriptRoot 'modules\core\CommonUtilities.psm1'
    Import-Module $path -Force -ErrorAction Stop
    
    $functions = @('Get-SafeValue', 'Invoke-WithRetry', 'ConvertTo-StandardizedResult', 'Format-DurationString')
    foreach ($func in $functions) {
        if (-not (Get-Command $func -ErrorAction SilentlyContinue)) {
            throw "Function $func not exported"
        }
        Write-Host "  ✓ $func exported"
    }
}

# TEST 5: Module Discovery
Test-Module "Module Discovery" {
    $modules = Get-RegisteredModules -ModuleType 'All'
    if ($modules.Count -lt 10) {
        throw "Expected at least 10 modules, found $($modules.Count)"
    }
    Write-Host "  Discovered $($modules.Count) modules"
    
    $type1 = ($modules.Values | Where-Object { $_.Type -eq 'Type1' }).Count
    $type2 = ($modules.Values | Where-Object { $_.Type -eq 'Type2' }).Count
    $core = ($modules.Values | Where-Object { $_.Type -eq 'Core' }).Count
    
    Write-Host "    Type1: $type1"
    Write-Host "    Type2: $type2"
    Write-Host "    Core: $core"
}

# TEST 6: Get-SafeValue Function
Test-Module "Get-SafeValue Function" {
    $testObj = @{
        execution = @{
            countdownSeconds = 120
            enableDryRun = $true
        }
    }
    
    $value = Get-SafeValue -Object $testObj -Path "execution.countdownSeconds" -Default 30
    if ($value -ne 120) {
        throw "Expected 120, got $value"
    }
    Write-Host "  ✓ Valid path returned: $value"
    
    $value2 = Get-SafeValue -Object $testObj -Path "execution.nonexistent" -Default 99
    if ($value2 -ne 99) {
        throw "Expected default 99, got $value2"
    }
    Write-Host "  ✓ Invalid path returned default: $value2"
}

# TEST 7: CoreInfrastructure Shutdown Functions
Test-Module "CoreInfrastructure Shutdown Functions" {
    $path = Join-Path $scriptRoot 'modules\core\CoreInfrastructure.psm1'
    Import-Module $path -Force -Global -ErrorAction Stop
    
    $functions = @('Start-MaintenanceCountdown', 'Invoke-MaintenanceCleanup')
    foreach ($func in $functions) {
        if (-not (Get-Command $func -ErrorAction SilentlyContinue)) {
            throw "Function $func not found in CoreInfrastructure"
        }
        Write-Host "  ✓ $func available"
    }
}

# TEST 8: Dependency Validation
Test-Module "Dependency Validation" {
    $modules = Get-RegisteredModules -ModuleType 'All' -IncludeMetadata
    
    # Test a known Type2 module with dependency
    if ($modules.ContainsKey('BloatwareRemoval')) {
        $isValid = Test-ModuleDependencies -ModuleName 'BloatwareRemoval' -Modules $modules
        if (-not $isValid) {
            throw "BloatwareRemoval dependency validation failed"
        }
        Write-Host "  ✓ BloatwareRemoval → BloatwareDetectionAudit validated"
    } else {
        Write-Host "  ⊗ BloatwareRemoval not found (skipped)"
    }
}

# TEST 9: ConvertTo-StandardizedResult
Test-Module "ConvertTo-StandardizedResult Function" {
    $rawResult = @{
        TotalOperations = 10
        SuccessfulOperations = 8
        FailedOperations = 2
        Results = @{ SomeData = "test" }
    }
    
    $standardized = ConvertTo-StandardizedResult -RawResult $rawResult -ModuleName 'TestModule' -DurationSeconds 5.5
    
    if ($standardized.ModuleName -ne 'TestModule') {
        throw "ModuleName mismatch"
    }
    if ($standardized.Metrics.ItemsDetected -ne 10) {
        throw "ItemsDetected mismatch"
    }
    if ($standardized.Metrics.DurationSeconds -ne 5.5) {
        throw "DurationSeconds mismatch"
    }
    
    Write-Host "  ✓ Result structure validated"
    Write-Host "    ModuleName: $($standardized.ModuleName)"
    Write-Host "    Status: $($standardized.Status)"
    Write-Host "    Duration: $($standardized.Metrics.DurationSeconds)s"
}

# TEST 10: Format-DurationString
Test-Module "Format-DurationString Function" {
    $duration1 = Format-DurationString -Seconds 45.3
    if ($duration1 -notlike "*45*") {
        throw "Expected seconds format"
    }
    Write-Host "  ✓ Seconds: $duration1"
    
    $duration2 = Format-DurationString -Seconds 150
    if ($duration2 -notlike "*2m*") {
        throw "Expected minutes format"
    }
    Write-Host "  ✓ Minutes: $duration2"
}

# Summary
Write-Host "`n╔════════════════════════════════════════╗" -ForegroundColor Magenta
Write-Host "║  TEST RESULTS SUMMARY                 ║" -ForegroundColor Magenta
Write-Host "╚════════════════════════════════════════╝" -ForegroundColor Magenta

$passed = ($testResults | Where-Object { $_.Result -eq 'PASS' }).Count
$failed = ($testResults | Where-Object { $_.Result -eq 'FAIL' }).Count

Write-Host "`nTotal Tests: $($testResults.Count)" -ForegroundColor White
Write-Host "Passed: $passed" -ForegroundColor Green
Write-Host "Failed: $failed" -ForegroundColor $(if ($failed -gt 0) { 'Red' } else { 'Green' })

if ($failed -gt 0) {
    Write-Host "`nFailed Tests:" -ForegroundColor Red
    $testResults | Where-Object { $_.Result -eq 'FAIL' } | ForEach-Object {
        Write-Host "  ✗ $($_.Test): $($_.Error)" -ForegroundColor Red
    }
}

Write-Host "`n════════════════════════════════════════`n" -ForegroundColor Magenta

if ($failed -eq 0) {
    Write-Host "✓ All Phase 1 tests passed!" -ForegroundColor Green
    Write-Host "Phase 1 implementation is ready for integration." -ForegroundColor Cyan
    exit 0
} else {
    Write-Host "✗ Some tests failed. Review errors above." -ForegroundColor Red
    exit 1
}
