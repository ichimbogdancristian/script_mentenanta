# v3.0 Architecture - Type2 Module Independence Test
# Tests each Type2 module can load and execute independently with its Type1 dependency

param(
    [Parameter()]
    [switch]$VerboseOutput
)

$ErrorActionPreference = 'Stop'
$VerbosePreference = if ($VerboseOutput) { 'Continue' } else { 'SilentlyContinue' }

Write-Host "`n🧪 Type2 Module Independence Test - v3.0 Architecture" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan

$ScriptRoot = $PSScriptRoot
$ModulesPath = Join-Path $ScriptRoot 'modules'
$Type2ModulesPath = Join-Path $ModulesPath 'type2'
$ConfigPath = Join-Path $ScriptRoot 'config'

# Test configuration (minimal)
$TestConfig = @{
    modules = @{
        skipBloatwareRemoval   = $false
        skipEssentialApps      = $false
        skipSystemOptimization = $false
        skipTelemetryDisable   = $false
        skipWindowsUpdates     = $false
    }
    system  = @{
        createSystemRestorePoint = $false
        enableVerboseLogging     = $true
    }
}

# Convert to PSCustomObject for compatibility
$TestConfigObject = [PSCustomObject]$TestConfig

# Define Type2 modules to test
$Type2Modules = @(
    @{ Name = 'BloatwareRemoval'; Function = 'Invoke-BloatwareRemoval'; Type1 = 'BloatwareDetection' }
    @{ Name = 'EssentialApps'; Function = 'Invoke-EssentialApps'; Type1 = 'EssentialAppsAudit' }
    @{ Name = 'SystemOptimization'; Function = 'Invoke-SystemOptimization'; Type1 = 'SystemOptimizationAudit' }
    @{ Name = 'TelemetryDisable'; Function = 'Invoke-TelemetryDisable'; Type1 = 'TelemetryAudit' }
    @{ Name = 'WindowsUpdates'; Function = 'Invoke-WindowsUpdates'; Type1 = 'WindowsUpdatesAudit' }
)

$TestResults = @()
$SuccessCount = 0
$FailureCount = 0

Write-Host "`n🔍 Testing Type2 modules for independence and v3.0 compliance..." -ForegroundColor Yellow

foreach ($module in $Type2Modules) {
    $testResult = @{
        ModuleName           = $module.Name
        Success              = $false
        LoadTime             = $null
        ExecutionTime        = $null
        Issues               = @()
        Type1Loaded          = $false
        CoreInfraLoaded      = $false
        StandardizedFunction = $false
        ReturnFormat         = $false
        Error                = $null
    }
    
    Write-Host "`n📦 Testing: $($module.Name)" -ForegroundColor White
    Write-Host "   Function: $($module.Function)" -ForegroundColor Gray
    Write-Host "   Type1 Dependency: $($module.Type1)" -ForegroundColor Gray
    
    try {
        # Test 1: Module Loading
        $loadStartTime = Get-Date
        $modulePath = Join-Path $Type2ModulesPath "$($module.Name).psm1"
        
        if (-not (Test-Path $modulePath)) {
            throw "Module file not found: $modulePath"
        }
        
        # Clean environment before testing
        Get-Module -Name $module.Name -ErrorAction SilentlyContinue | Remove-Module -Force
        Get-Module -Name $module.Type1 -ErrorAction SilentlyContinue | Remove-Module -Force
        Get-Module -Name 'CoreInfrastructure' -ErrorAction SilentlyContinue | Remove-Module -Force
        
        Write-Verbose "Loading module: $modulePath"
        Import-Module $modulePath -Force -ErrorAction Stop
        
        $testResult.LoadTime = ((Get-Date) - $loadStartTime).TotalMilliseconds
        Write-Host "   ✓ Module loaded successfully ($([math]::Round($testResult.LoadTime, 2))ms)" -ForegroundColor Green
        
        # Test 2: Verify Type1 functions are available (better test than module name)
        $type1Functions = @()
        switch ($module.Type1) {
            'BloatwareDetection' { $type1Functions = @('Find-InstalledBloatware', 'Get-BloatwareStatistic') }
            'EssentialAppsAudit' { $type1Functions = @('Get-EssentialAppsAudit') }
            'SystemOptimizationAudit' { $type1Functions = @('Get-SystemOptimizationAudit') }
            'TelemetryAudit' { $type1Functions = @('Get-TelemetryAudit') }
            'WindowsUpdatesAudit' { $type1Functions = @('Get-WindowsUpdatesAudit') }
        }
        
        $availableType1Functions = $type1Functions | Where-Object { Get-Command -Name $_ -ErrorAction SilentlyContinue }
        if ($availableType1Functions.Count -eq $type1Functions.Count) {
            $testResult.Type1Loaded = $true
            Write-Host "   ✓ Type1 functions available: $($availableType1Functions -join ', ')" -ForegroundColor Green
        }
        else {
            $missing = $type1Functions | Where-Object { $_ -notin $availableType1Functions }
            $testResult.Issues += "Type1 functions not available: $($missing -join ', ')"
            Write-Host "   ⚠️ Missing Type1 functions: $($missing -join ', ')" -ForegroundColor Yellow
        }
        
        # Test 3: Verify CoreInfrastructure functions are available
        $coreCoreFunctions = @('Write-LogEntry', 'Start-PerformanceTracking', 'Complete-PerformanceTracking')
        $availableCoreFunctions = $coreCoreFunctions | Where-Object { Get-Command -Name $_ -ErrorAction SilentlyContinue }
        if ($availableCoreFunctions.Count -eq $coreCoreFunctions.Count) {
            $testResult.CoreInfraLoaded = $true
            Write-Host "   ✓ CoreInfrastructure functions available" -ForegroundColor Green
        }
        else {
            $missing = $coreCoreFunctions | Where-Object { $_ -notin $availableCoreFunctions }
            $testResult.Issues += "CoreInfrastructure functions not available: $($missing -join ', ')"
            Write-Host "   ⚠️ Missing CoreInfrastructure functions: $($missing -join ', ')" -ForegroundColor Yellow
        }
        
        # Test 4: Verify standardized function exists
        $invokeFunction = Get-Command -Name $module.Function -ErrorAction SilentlyContinue
        if ($invokeFunction) {
            $testResult.StandardizedFunction = $true
            Write-Host "   ✓ Standardized function available: $($module.Function)" -ForegroundColor Green
            
            # Check function parameters
            $expectedParams = @('Config', 'DryRun')
            $functionParams = $invokeFunction.Parameters.Keys
            $missingParams = $expectedParams | Where-Object { $_ -notin $functionParams }
            if ($missingParams) {
                $testResult.Issues += "Missing expected parameters: $($missingParams -join ', ')"
                Write-Host "   ⚠️ Missing parameters: $($missingParams -join ', ')" -ForegroundColor Yellow
            }
            else {
                Write-Host "   ✓ Function has required parameters (Config, DryRun)" -ForegroundColor Green
            }
        }
        else {
            $testResult.Issues += "Standardized function not found"
            Write-Host "   ✗ Function not found: $($module.Function)" -ForegroundColor Red
        }
        
        # Test 5: Execute function in DryRun mode
        if ($testResult.StandardizedFunction) {
            Write-Host "   🔄 Testing function execution (DryRun mode)..." -ForegroundColor Cyan
            
            $execStartTime = Get-Date
            try {
                $result = & $module.Function -Config $TestConfigObject -DryRun
                $testResult.ExecutionTime = ((Get-Date) - $execStartTime).TotalMilliseconds
                
                Write-Host "   ✓ Function executed successfully ($([math]::Round($testResult.ExecutionTime, 2))ms)" -ForegroundColor Green
                
                # Test 6: Verify standardized return format
                if ($result -is [hashtable] -and $result.ContainsKey('Success')) {
                    $testResult.ReturnFormat = $true
                    Write-Host "   ✓ Returns standardized format (Success: $($result.Success))" -ForegroundColor Green
                    
                    # Check for expected fields
                    $expectedFields = @('Success', 'ItemsDetected', 'ItemsProcessed', 'DryRun')
                    $missingFields = $expectedFields | Where-Object { -not $result.ContainsKey($_) }
                    if ($missingFields) {
                        $testResult.Issues += "Missing return fields: $($missingFields -join ', ')"
                        Write-Host "   ⚠️ Missing return fields: $($missingFields -join ', ')" -ForegroundColor Yellow
                    }
                    else {
                        Write-Host "   ✓ All expected return fields present" -ForegroundColor Green
                    }
                }
                else {
                    $testResult.Issues += "Non-standard return format"
                    Write-Host "   ⚠️ Non-standard return format" -ForegroundColor Yellow
                }
                
            }
            catch {
                $testResult.Issues += "Function execution failed: $($_.Exception.Message)"
                Write-Host "   ✗ Function execution failed: $($_.Exception.Message)" -ForegroundColor Red
            }
        }
        
        # Overall success determination
        if ($testResult.Issues.Count -eq 0) {
            $testResult.Success = $true
            $SuccessCount++
            Write-Host "   🎉 Module test PASSED - Fully v3.0 compliant" -ForegroundColor Green
        }
        else {
            $FailureCount++
            Write-Host "   ❌ Module test FAILED - Issues found" -ForegroundColor Red
        }
        
    }
    catch {
        $testResult.Error = $_.Exception.Message
        $FailureCount++
        Write-Host "   💥 Module test ERROR: $($_.Exception.Message)" -ForegroundColor Red
    }
    
    $TestResults += $testResult
    
    # Clean up for next test
    try {
        Get-Module -Name $module.Name -ErrorAction SilentlyContinue | Remove-Module -Force
        Get-Module -Name $module.Type1 -ErrorAction SilentlyContinue | Remove-Module -Force
        Get-Module -Name 'CoreInfrastructure' -ErrorAction SilentlyContinue | Remove-Module -Force
    }
    catch {
        Write-Verbose "Cleanup warning: $($_.Exception.Message)"
    }
}

# Generate Test Report
Write-Host "`n📊 TEST RESULTS SUMMARY" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "Total Modules Tested: $($Type2Modules.Count)" -ForegroundColor White
Write-Host "Successful: $SuccessCount" -ForegroundColor Green  
Write-Host "Failed: $FailureCount" -ForegroundColor Red
Write-Host "Success Rate: $([math]::Round(($SuccessCount / $Type2Modules.Count) * 100, 1))%" -ForegroundColor $(if ($SuccessCount -eq $Type2Modules.Count) { 'Green' } else { 'Yellow' })

if ($FailureCount -gt 0) {
    Write-Host "`n⚠️ ISSUES FOUND:" -ForegroundColor Yellow
    foreach ($result in $TestResults | Where-Object { -not $_.Success -or $_.Issues.Count -gt 0 }) {
        Write-Host "   $($result.ModuleName):" -ForegroundColor White
        if ($result.Error) {
            Write-Host "     • ERROR: $($result.Error)" -ForegroundColor Red
        }
        foreach ($issue in $result.Issues) {
            Write-Host "     • $issue" -ForegroundColor Yellow
        }
    }
}

Write-Host "`n🎯 v3.0 ARCHITECTURE COMPLIANCE:" -ForegroundColor Cyan
$type1LoadedCount = ($TestResults | Where-Object { $_.Type1Loaded }).Count
$coreLoadedCount = ($TestResults | Where-Object { $_.CoreInfraLoaded }).Count
$standardFuncCount = ($TestResults | Where-Object { $_.StandardizedFunction }).Count
$standardReturnCount = ($TestResults | Where-Object { $_.ReturnFormat }).Count

Write-Host "Self-contained Type1 loading: $type1LoadedCount/$($Type2Modules.Count) ($([math]::Round(($type1LoadedCount / $Type2Modules.Count) * 100, 1))%)" -ForegroundColor $(if ($type1LoadedCount -eq $Type2Modules.Count) { 'Green' } else { 'Red' })
Write-Host "CoreInfrastructure integration: $coreLoadedCount/$($Type2Modules.Count) ($([math]::Round(($coreLoadedCount / $Type2Modules.Count) * 100, 1))%)" -ForegroundColor $(if ($coreLoadedCount -eq $Type2Modules.Count) { 'Green' } else { 'Red' })
Write-Host "Standardized functions: $standardFuncCount/$($Type2Modules.Count) ($([math]::Round(($standardFuncCount / $Type2Modules.Count) * 100, 1))%)" -ForegroundColor $(if ($standardFuncCount -eq $Type2Modules.Count) { 'Green' } else { 'Red' })
Write-Host "Standardized return format: $standardReturnCount/$($Type2Modules.Count) ($([math]::Round(($standardReturnCount / $Type2Modules.Count) * 100, 1))%)" -ForegroundColor $(if ($standardReturnCount -eq $Type2Modules.Count) { 'Green' } else { 'Red' })

# Performance metrics
$avgLoadTime = ($TestResults | Where-Object { $_.LoadTime } | Measure-Object -Property LoadTime -Average).Average
$avgExecTime = ($TestResults | Where-Object { $_.ExecutionTime } | Measure-Object -Property ExecutionTime -Average).Average

if ($avgLoadTime) {
    Write-Host "`n⚡ PERFORMANCE METRICS:" -ForegroundColor Cyan
    Write-Host "Average Load Time: $([math]::Round($avgLoadTime, 2))ms" -ForegroundColor White
    if ($avgExecTime) {
        Write-Host "Average Execution Time: $([math]::Round($avgExecTime, 2))ms" -ForegroundColor White
    }
}

# Final result
if ($SuccessCount -eq $Type2Modules.Count) {
    Write-Host "`n🎉 ALL TESTS PASSED - v3.0 Architecture is fully functional!" -ForegroundColor Green
    exit 0
}
else {
    Write-Host "`n❌ TESTS FAILED - v3.0 Architecture needs attention!" -ForegroundColor Red
    exit 1
}