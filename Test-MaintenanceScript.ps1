#Requires -Version 7.0

<#
.SYNOPSIS
    Comprehensive smoke test for Windows Maintenance Automation

.DESCRIPTION
    Runs dry-run tests to validate that the orchestrator works correctly,
    modules are registered and executed, logs are created, and inventory
    files are generated as expected.

.PARAMETER TestMode
    The type of test to run: All, Basic, Logs, Inventory, or Modules

.PARAMETER NonInteractive
    Run tests without interactive prompts

.EXAMPLE
    .\Test-MaintenanceScript.ps1
    # Runs all smoke tests

.EXAMPLE
    .\Test-MaintenanceScript.ps1 -TestMode Basic -NonInteractive
    # Runs basic tests without interaction

.NOTES
    Author: Windows Maintenance Automation Project
    Version: 1.0.0
    This script performs comprehensive testing of the maintenance automation system
#>

param(
    [Parameter()]
    [ValidateSet('All', 'Basic', 'Logs', 'Inventory', 'Modules')]
    [string]$TestMode = 'All',
    
    [Parameter()]
    [switch]$NonInteractive
)

# Set up test environment
$ErrorActionPreference = 'Stop'
$TestStartTime = Get-Date
$WorkingDirectory = $PSScriptRoot
$TestResults = @{
    Passed = 0
    Failed = 0
    Skipped = 0
    Details = @()
}

# Test output functions
function Write-TestResult {
    param(
        [Parameter(Mandatory)]
        [string]$TestName,
        
        [Parameter(Mandatory)]
        [ValidateSet('PASS', 'FAIL', 'SKIP')]
        [string]$Result,
        
        [Parameter()]
        [string]$Message = ""
    )
    
    $icon = switch ($Result) {
        'PASS' { '✅'; $TestResults.Passed++ }
        'FAIL' { '❌'; $TestResults.Failed++ }
        'SKIP' { '⏭️'; $TestResults.Skipped++ }
    }
    
    $color = switch ($Result) {
        'PASS' { 'Green' }
        'FAIL' { 'Red' }
        'SKIP' { 'Yellow' }
    }
    
    $resultText = "[$Result] $TestName"
    if ($Message) {
        $resultText += " - $Message"
    }
    
    Write-Host "$icon $resultText" -ForegroundColor $color
    
    $TestResults.Details += @{
        TestName = $TestName
        Result = $Result
        Message = $Message
        Timestamp = Get-Date
    }
}

function Test-FileExists {
    param(
        [string]$FilePath,
        [string]$Description
    )
    
    if (Test-Path $FilePath) {
        Write-TestResult -TestName "File Exists: $Description" -Result 'PASS' -Message $FilePath
        return $true
    } else {
        Write-TestResult -TestName "File Exists: $Description" -Result 'FAIL' -Message "Not found: $FilePath"
        return $false
    }
}

# Main test execution
Write-Host "╔══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║                              Windows Maintenance Automation - Smoke Test Suite                                             ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""
Write-Host "🧪 Test Mode: $TestMode" -ForegroundColor Yellow
Write-Host "📁 Working Directory: $WorkingDirectory" -ForegroundColor Gray
Write-Host "⏰ Test Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
Write-Host ""

try {
    # Test 1: Basic file structure validation
    if ($TestMode -eq 'All' -or $TestMode -eq 'Basic') {
        Write-Host "🔍 Basic Structure Validation:" -ForegroundColor Yellow
        
        # Core files
        Test-FileExists -FilePath (Join-Path $WorkingDirectory 'MaintenanceOrchestrator.ps1') -Description 'Main Orchestrator'
        Test-FileExists -FilePath (Join-Path $WorkingDirectory 'script.bat') -Description 'Batch Launcher'
        Test-FileExists -FilePath (Join-Path $WorkingDirectory 'README.md') -Description 'Documentation'
        
        # Core modules
        $coreModulesPath = Join-Path $WorkingDirectory 'modules\core'
        Test-FileExists -FilePath (Join-Path $coreModulesPath 'ConfigManager.psm1') -Description 'Core: ConfigManager'
        Test-FileExists -FilePath (Join-Path $coreModulesPath 'ModuleExecutionProtocol.psm1') -Description 'Core: ModuleExecutionProtocol'
        Test-FileExists -FilePath (Join-Path $coreModulesPath 'MenuSystem.psm1') -Description 'Core: MenuSystem'
        
        # Type1 modules (Inventory/Reporting)
        $type1ModulesPath = Join-Path $WorkingDirectory 'modules\type1'
        Test-FileExists -FilePath (Join-Path $type1ModulesPath 'SystemInventory.psm1') -Description 'Type1: SystemInventory'
        Test-FileExists -FilePath (Join-Path $type1ModulesPath 'BloatwareDetection.psm1') -Description 'Type1: BloatwareDetection'
        Test-FileExists -FilePath (Join-Path $type1ModulesPath 'SecurityAudit.psm1') -Description 'Type1: SecurityAudit'
        Test-FileExists -FilePath (Join-Path $type1ModulesPath 'ReportGeneration.psm1') -Description 'Type1: ReportGeneration'
        
        # Type2 modules (System Modification)
        $type2ModulesPath = Join-Path $WorkingDirectory 'modules\type2'
        Test-FileExists -FilePath (Join-Path $type2ModulesPath 'BloatwareRemoval.psm1') -Description 'Type2: BloatwareRemoval'
        Test-FileExists -FilePath (Join-Path $type2ModulesPath 'EssentialApps.psm1') -Description 'Type2: EssentialApps'
        Test-FileExists -FilePath (Join-Path $type2ModulesPath 'WindowsUpdates.psm1') -Description 'Type2: WindowsUpdates'
        Test-FileExists -FilePath (Join-Path $type2ModulesPath 'TelemetryDisable.psm1') -Description 'Type2: TelemetryDisable'
        Test-FileExists -FilePath (Join-Path $type2ModulesPath 'SystemOptimization.psm1') -Description 'Type2: SystemOptimization'
        
        # Configuration files
        $configPath = Join-Path $WorkingDirectory 'config'
        Test-FileExists -FilePath (Join-Path $configPath 'main-config.json') -Description 'Config: Main Configuration'
        Test-FileExists -FilePath (Join-Path $configPath 'bloatware.json') -Description 'Config: Bloatware Lists'
        Test-FileExists -FilePath (Join-Path $configPath 'essential-apps.json') -Description 'Config: Essential Apps'
        
        Write-Host ""
    }
    
    # Test 2: Orchestrator dry-run execution
    if ($TestMode -eq 'All' -or $TestMode -eq 'Modules') {
        Write-Host "🚀 Orchestrator Execution Test:" -ForegroundColor Yellow
        
        # Clear any existing temp files for clean test
        $tempFiles = Join-Path $WorkingDirectory 'temp_files'
        if (Test-Path $tempFiles) {
            Remove-Item $tempFiles -Recurse -Force -ErrorAction SilentlyContinue
        }
        
        # Run orchestrator in dry-run mode with SystemInventory only
        $orchestratorPath = Join-Path $WorkingDirectory 'MaintenanceOrchestrator.ps1'
        
        try {
            Write-Host "  🔧 Executing orchestrator in dry-run mode..." -ForegroundColor Gray
            
            # Capture output from orchestrator execution
            $orchestratorOutput = & pwsh.exe -ExecutionPolicy Bypass -NoProfile -File $orchestratorPath -NonInteractive -DryRun -ModuleName "SystemInventory" 2>&1
            
            if ($LASTEXITCODE -eq 0) {
                Write-TestResult -TestName "Orchestrator Execution" -Result 'PASS' -Message "Dry-run completed successfully"
            } else {
                Write-TestResult -TestName "Orchestrator Execution" -Result 'FAIL' -Message "Exit code: $LASTEXITCODE"
                if ($Verbose) {
                    Write-Host "Orchestrator Output:" -ForegroundColor Yellow
                    $orchestratorOutput | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }
                }
            }
            
            # Check if temp_files structure was created
            $tempFilesCreated = Test-Path $tempFiles
            if ($tempFilesCreated) {
                Write-TestResult -TestName "Temp Directory Creation" -Result 'PASS' -Message "temp_files directory created"
                
                # Check subdirectories
                $logsDir = Join-Path $tempFiles 'logs'
                $reportsDir = Join-Path $tempFiles 'reports'
                $inventoryDir = Join-Path $tempFiles 'inventory'
                
                Test-FileExists -FilePath $logsDir -Description 'Logs Directory'
                Test-FileExists -FilePath $reportsDir -Description 'Reports Directory'
                Test-FileExists -FilePath $inventoryDir -Description 'Inventory Directory'
            } else {
                Write-TestResult -TestName "Temp Directory Creation" -Result 'FAIL' -Message "temp_files not created"
            }
            
        } catch {
            Write-TestResult -TestName "Orchestrator Execution" -Result 'FAIL' -Message $_.Exception.Message
        }
        
        Write-Host ""
    }
    
    # Test 3: Log file validation
    if ($TestMode -eq 'All' -or $TestMode -eq 'Logs') {
        Write-Host "📝 Log Files Validation:" -ForegroundColor Yellow
        
        $logsDir = Join-Path $WorkingDirectory 'temp_files\logs'
        
        if (Test-Path $logsDir) {
            # Check main maintenance log
            $mainLog = Join-Path $logsDir 'maintenance.log'
            if (Test-Path $mainLog) {
                Write-TestResult -TestName "Main Maintenance Log" -Result 'PASS' -Message $mainLog
                
                # Check log content for key indicators
                $logContent = Get-Content $mainLog -ErrorAction SilentlyContinue
                if ($logContent) {
                    $hasOrchestratorEntries = $logContent | Where-Object { $_ -like '*ORCHESTRATOR*' }
                    if ($hasOrchestratorEntries) {
                        Write-TestResult -TestName "Log Content - Orchestrator" -Result 'PASS' -Message "Found orchestrator log entries"
                    } else {
                        Write-TestResult -TestName "Log Content - Orchestrator" -Result 'FAIL' -Message "No orchestrator entries found"
                    }
                    
                    $hasSystemInventory = $logContent | Where-Object { $_ -like '*SystemInventory*' }
                    if ($hasSystemInventory) {
                        Write-TestResult -TestName "Log Content - SystemInventory" -Result 'PASS' -Message "Found SystemInventory log entries"
                    } else {
                        Write-TestResult -TestName "Log Content - SystemInventory" -Result 'FAIL' -Message "No SystemInventory entries found"
                    }
                }
            } else {
                Write-TestResult -TestName "Main Maintenance Log" -Result 'FAIL' -Message "maintenance.log not found"
            }
            
            # Check for module-specific logs
            $moduleLogPattern = Join-Path $logsDir '*.log'
            $moduleLogs = Get-ChildItem $moduleLogPattern -ErrorAction SilentlyContinue
            
            if ($moduleLogs.Count -gt 0) {
                Write-TestResult -TestName "Module-Specific Logs" -Result 'PASS' -Message "Found $($moduleLogs.Count) module log files"
                
                foreach ($moduleLog in $moduleLogs) {
                    if ($Verbose) {
                        Write-Host "    📋 $($moduleLog.Name)" -ForegroundColor Gray
                    }
                }
            } else {
                Write-TestResult -TestName "Module-Specific Logs" -Result 'FAIL' -Message "No module-specific logs found"
            }
            
        } else {
            Write-TestResult -TestName "Logs Directory" -Result 'FAIL' -Message "Logs directory not created"
        }
        
        Write-Host ""
    }
    
    # Test 4: Inventory system validation
    if ($TestMode -eq 'All' -or $TestMode -eq 'Inventory') {
        Write-Host "📊 Inventory System Validation:" -ForegroundColor Yellow
        
        # Test SystemInventory module directly
        try {
            $systemInventoryPath = Join-Path $WorkingDirectory 'modules\type1\SystemInventory.psm1'
            Import-Module $systemInventoryPath -Force
            
            # Test basic inventory collection
            $inventory = Get-SystemInventory -UseCache:$false
            
            if ($inventory -and $inventory.Metadata) {
                Write-TestResult -TestName "SystemInventory Collection" -Result 'PASS' -Message "Inventory collected successfully"
                
                # Validate key sections
                $expectedSections = @('SystemInfo', 'Hardware', 'OperatingSystem', 'InstalledSoftware', 'Services', 'Network', 'Metadata')
                foreach ($section in $expectedSections) {
                    if ($inventory.ContainsKey($section)) {
                        Write-TestResult -TestName "Inventory Section: $section" -Result 'PASS' -Message "Section present and populated"
                    } else {
                        Write-TestResult -TestName "Inventory Section: $section" -Result 'FAIL' -Message "Section missing"
                    }
                }
                
                # Test cache functionality
                $cacheInfo = Get-SystemInventoryCacheInfo
                if ($cacheInfo.IsCached) {
                    Write-TestResult -TestName "Inventory Caching" -Result 'PASS' -Message "Cache is working (age: $($cacheInfo.CacheAgeMinutes) min)"
                } else {
                    Write-TestResult -TestName "Inventory Caching" -Result 'FAIL' -Message "Cache not populated"
                }
                
                # Test export functionality
                $inventoryDir = Join-Path $WorkingDirectory 'temp_files\inventory'
                if (Test-Path $inventoryDir) {
                    try {
                        # Test export with explicit path
                        $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
                        $testExportPath = Join-Path $inventoryDir "test-inventory-$timestamp.json"
                        
                        $exportPaths = Export-SystemInventory -InventoryData $inventory -OutputPath $testExportPath -Format 'JSON'
                        if ($exportPaths) {
                            if (Test-Path $exportPaths) {
                                Write-TestResult -TestName "Inventory Export" -Result 'PASS' -Message "JSON export successful"
                            } else {
                                Write-TestResult -TestName "Inventory Export" -Result 'FAIL' -Message "Export path returned but file not found: $exportPaths"
                            }
                        } else {
                            Write-TestResult -TestName "Inventory Export" -Result 'FAIL' -Message "Export function returned no paths"
                        }
                    } catch {
                        Write-TestResult -TestName "Inventory Export" -Result 'FAIL' -Message $_.Exception.Message
                    }
                } else {
                    Write-TestResult -TestName "Inventory Export" -Result 'SKIP' -Message "Inventory directory not available"
                }
                
            } else {
                Write-TestResult -TestName "SystemInventory Collection" -Result 'FAIL' -Message "Inventory collection failed or incomplete"
            }
            
        } catch {
            Write-TestResult -TestName "SystemInventory Collection" -Result 'FAIL' -Message $_.Exception.Message
        }
        
        Write-Host ""
    }
    
    # Test 5: Configuration system validation
    if ($TestMode -eq 'All' -or $TestMode -eq 'Basic') {
        Write-Host "⚙️ Configuration System Validation:" -ForegroundColor Yellow
        
        try {
            $configManagerPath = Join-Path $WorkingDirectory 'modules\core\ConfigManager.psm1'
            Import-Module $configManagerPath -Force
            
            $configPath = Join-Path $WorkingDirectory 'config'
            Initialize-ConfigSystem -ConfigRootPath $configPath
            
            # Test main configuration
            $mainConfig = Get-MainConfiguration
            if ($mainConfig) {
                Write-TestResult -TestName "Main Configuration Loading" -Result 'PASS' -Message "Configuration loaded successfully"
                
                # Test new helper functions
                $inventoryFolder = Get-InventoryFolder
                if ($inventoryFolder) {
                    Write-TestResult -TestName "Inventory Folder Helper" -Result 'PASS' -Message $inventoryFolder
                } else {
                    Write-TestResult -TestName "Inventory Folder Helper" -Result 'FAIL' -Message "Failed to get inventory folder"
                }
                
                $moduleLogPath = Get-ModuleLogPath -ModuleName 'TestModule'
                if ($moduleLogPath) {
                    Write-TestResult -TestName "Module Log Path Helper" -Result 'PASS' -Message $moduleLogPath
                } else {
                    Write-TestResult -TestName "Module Log Path Helper" -Result 'FAIL' -Message "Failed to get module log path"
                }
                
            } else {
                Write-TestResult -TestName "Main Configuration Loading" -Result 'FAIL' -Message "Configuration loading failed"
            }
            
        } catch {
            Write-TestResult -TestName "Configuration System" -Result 'FAIL' -Message $_.Exception.Message
        }
        
        Write-Host ""
    }
    
} catch {
    Write-Host "❌ Critical test failure: $($_.Exception.Message)" -ForegroundColor Red
    $TestResults.Failed++
}

# Test summary
$duration = ((Get-Date) - $TestStartTime).TotalSeconds
$totalTests = $TestResults.Passed + $TestResults.Failed + $TestResults.Skipped
$successRate = if ($totalTests -gt 0) { [math]::Round(($TestResults.Passed / $totalTests) * 100, 1) } else { 0 }

Write-Host "╔══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║                                              TEST SUMMARY                                                                    ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""
Write-Host "📊 Test Results:" -ForegroundColor Yellow
Write-Host "  ✅ Passed: $($TestResults.Passed)" -ForegroundColor Green
Write-Host "  ❌ Failed: $($TestResults.Failed)" -ForegroundColor Red
Write-Host "  ⏭️ Skipped: $($TestResults.Skipped)" -ForegroundColor Yellow
Write-Host "  📈 Success Rate: $successRate%" -ForegroundColor $(if ($successRate -ge 80) { 'Green' } elseif ($successRate -ge 60) { 'Yellow' } else { 'Red' })
Write-Host "  ⏱️ Duration: $([math]::Round($duration, 2)) seconds" -ForegroundColor Gray
Write-Host ""

# Overall result
if ($TestResults.Failed -eq 0) {
    Write-Host "🎉 All tests completed successfully!" -ForegroundColor Green
    $exitCode = 0
} elseif ($TestResults.Failed -le 2 -and $TestResults.Passed -gt 0) {
    Write-Host "⚠️ Tests completed with minor issues" -ForegroundColor Yellow
    $exitCode = 1
} else {
    Write-Host "❌ Tests completed with significant failures" -ForegroundColor Red
    $exitCode = 2
}

# Detailed failure report
if ($TestResults.Failed -gt 0 -and -not $NonInteractive) {
    Write-Host ""
    Write-Host "🔍 Failed Tests Details:" -ForegroundColor Red
    $failedTests = $TestResults.Details | Where-Object { $_.Result -eq 'FAIL' }
    foreach ($failedTest in $failedTests) {
        Write-Host "  ❌ $($failedTest.TestName): $($failedTest.Message)" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "Test completed at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray

exit $exitCode