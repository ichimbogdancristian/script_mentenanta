<#
.SYNOPSIS
    Comprehensive configuration validation test script

.DESCRIPTION
    Tests all configuration files against their schemas and provides detailed analysis
    of any validation errors to prevent runtime issues.
#>

#Requires -Version 7.0

# Import CoreInfrastructure for validation functions
$coreInfraPath = Join-Path $PSScriptRoot "modules\core\CoreInfrastructure.psm1"
Import-Module $coreInfraPath -Force -Global

Write-Host "`n=== COMPREHENSIVE CONFIGURATION VALIDATION ===" -ForegroundColor Cyan
Write-Host "Analyzing all configuration files against their JSON schemas`n" -ForegroundColor White

# Initialize path discovery
Initialize-GlobalPathDiscovery

$configRoot = $env:MAINTENANCE_CONFIG_ROOT

# Define all configurations with their expected properties
$configTests = @(
    @{
        Name               = "Main Configuration"
        Path               = "$configRoot\settings\main-config.json"
        Schema             = "$configRoot\schemas\main-config.schema.json"
        ExpectedProperties = @("execution", "modules", "bloatware", "essentialApps", "system", "reporting", "paths")
    }
    @{
        Name               = "Logging Configuration"
        Path               = "$configRoot\settings\logging-config.json"
        Schema             = "$configRoot\schemas\logging-config.schema.json"
        ExpectedProperties = @("logging", "verbosity", "formatting", "levels", "components", "reporting", "performance", "alerts")
    }
    @{
        Name               = "Security Configuration"
        Path               = "$configRoot\settings\security-config.json"
        Schema             = "$configRoot\schemas\security-config.schema.json"
        ExpectedProperties = @("security", "compliance", "firewall", "services", "updates", "privacy")
    }
    @{
        Name               = "Bloatware List"
        Path               = "$configRoot\lists\bloatware\bloatware-list.json"
        Schema             = "$configRoot\schemas\bloatware-list.schema.json"
        ExpectedProperties = @("all")
    }
    @{
        Name    = "Essential Apps"
        Path    = "$configRoot\lists\essential-apps\essential-apps.json"
        Schema  = "$configRoot\schemas\essential-apps.schema.json"
        IsArray = $true
    }
    @{
        Name               = "App Upgrade Config"
        Path               = "$configRoot\lists\app-upgrade\app-upgrade-config.json"
        Schema             = "$configRoot\schemas\app-upgrade-config.schema.json"
        ExpectedProperties = @("ModuleName", "EnabledSources", "ExcludePatterns", "safety", "ExecutionSettings", "LoggingSettings", "ReportingSettings")
    }
    @{
        Name               = "System Optimization"
        Path               = "$configRoot\lists\system-optimization\system-optimization-config.json"
        Schema             = "$configRoot\schemas\system-optimization-config.schema.json"
        ExpectedProperties = @("startupPrograms", "services", "visualEffects", "powerPlan")
    }
)

$results = @()
$totalTests = $configTests.Count
$passedTests = 0
$failedTests = 0

foreach ($test in $configTests) {
    Write-Host "Testing: $($test.Name)" -ForegroundColor Yellow
    Write-Host "  Config: $($test.Path)" -ForegroundColor Gray
    Write-Host "  Schema: $($test.Schema)" -ForegroundColor Gray
    
    $result = @{
        Name       = $test.Name
        ConfigPath = $test.Path
        SchemaPath = $test.Schema
        Passed     = $false
        Errors     = @()
        Warnings   = @()
    }
    
    # Check if files exist
    if (-not (Test-Path $test.Path)) {
        $result.Errors += "Configuration file not found: $($test.Path)"
        Write-Host "  ✗ FAILED: Config file not found" -ForegroundColor Red
        $results += $result
        $failedTests++
        continue
    }
    
    if (-not (Test-Path $test.Schema)) {
        $result.Errors += "Schema file not found: $($test.Schema)"
        Write-Host "  ✗ FAILED: Schema file not found" -ForegroundColor Red
        $results += $result
        $failedTests++
        continue
    }
    
    # Load and validate JSON syntax
    try {
        $configContent = Get-Content $test.Path -Raw | ConvertFrom-Json -ErrorAction Stop
        Write-Host "  ✓ JSON syntax valid" -ForegroundColor Green
    }
    catch {
        $result.Errors += "Invalid JSON syntax: $($_.Exception.Message)"
        Write-Host "  ✗ FAILED: Invalid JSON syntax" -ForegroundColor Red
        $results += $result
        $failedTests++
        continue
    }
    
    # Check expected properties (if defined)
    if ($test.ExpectedProperties) {
        $missingProps = @()
        foreach ($prop in $test.ExpectedProperties) {
            if (-not (Get-Member -InputObject $configContent -Name $prop -ErrorAction SilentlyContinue)) {
                $missingProps += $prop
            }
        }
        
        if ($missingProps.Count -gt 0) {
            $result.Warnings += "Missing expected properties: $($missingProps -join ', ')"
            Write-Host "  ⚠ WARNING: Missing properties: $($missingProps -join ', ')" -ForegroundColor Yellow
        }
        else {
            Write-Host "  ✓ All expected properties present" -ForegroundColor Green
        }
    }
    
    # Validate against schema
    try {
        $validation = Test-ConfigurationWithJsonSchema -ConfigFilePath $test.Path -ErrorAction Stop
        
        if ($validation.IsValid) {
            Write-Host "  ✓ Schema validation PASSED" -ForegroundColor Green
            $result.Passed = $true
            $passedTests++
        }
        else {
            Write-Host "  ✗ Schema validation FAILED" -ForegroundColor Red
            $result.Errors += $validation.ErrorDetails
            Write-Host "    Error: $($validation.ErrorDetails)" -ForegroundColor Red
            $failedTests++
        }
    }
    catch {
        $result.Errors += "Schema validation error: $($_.Exception.Message)"
        Write-Host "  ✗ FAILED: Schema validation error" -ForegroundColor Red
        Write-Host "    $($_.Exception.Message)" -ForegroundColor Red
        $failedTests++
    }
    
    $results += $result
    Write-Host ""
}

# Summary
Write-Host "=== VALIDATION SUMMARY ===" -ForegroundColor Cyan
Write-Host "Total Tests: $totalTests" -ForegroundColor White
Write-Host "Passed:      $passedTests" -ForegroundColor Green
Write-Host "Failed:      $failedTests" -ForegroundColor Red
Write-Host ""

if ($failedTests -eq 0) {
    Write-Host "✓ ALL CONFIGURATIONS VALID!" -ForegroundColor Green
    Write-Host "Your system is ready to run maintenance tasks.`n" -ForegroundColor White
}
else {
    Write-Host "✗ VALIDATION FAILED - Issues found:" -ForegroundColor Red
    Write-Host ""
    
    foreach ($result in $results | Where-Object { -not $_.Passed }) {
        Write-Host "  $($result.Name):" -ForegroundColor Yellow
        foreach ($error in $result.Errors) {
            Write-Host "    - $error" -ForegroundColor Red
        }
        foreach ($warning in $result.Warnings) {
            Write-Host "    ⚠ $warning" -ForegroundColor Yellow
        }
        Write-Host ""
    }
    
    Write-Host "Please fix the above issues before running maintenance tasks.`n" -ForegroundColor White
}

# Export detailed results
$reportPath = Join-Path $PSScriptRoot "temp_files\config-validation-report.json"
$results | ConvertTo-Json -Depth 10 | Out-File $reportPath -Encoding UTF8
Write-Host "Detailed report saved to: $reportPath`n" -ForegroundColor Gray
