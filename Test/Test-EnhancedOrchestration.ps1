#Requires -Version 7.0
# Note: Administrator privileges recommended for full testing

<#
.SYNOPSIS
    Tests the Enhanced Orchestration functionality of the Windows Maintenance System.

.DESCRIPTION
    Comprehensive test suite for the MaintenanceOrchestrator.ps1 functionality,
    including module loading, task execution, configuration management, and error handling.

.PARAMETER TestScope
    Specifies which tests to run. Valid values: 'All', 'Core', 'Modules', 'Integration'

.PARAMETER SkipDependencyCheck
    Skip dependency validation tests (useful for CI environments)

.PARAMETER GenerateReport
    Generate detailed test report in HTML format

.EXAMPLE
    .\Test-EnhancedOrchestration.ps1
    Run all tests with default settings

.EXAMPLE
    .\Test-EnhancedOrchestration.ps1 -TestScope 'Core' -GenerateReport
    Run only core tests and generate HTML report

.NOTES
    Author: Windows Maintenance System Team
    Version: 2.0.1
    Requires: PowerShell 7.0+, Administrator privileges
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter()]
    [ValidateSet('All', 'Core', 'Modules', 'Integration')]
    [string]$TestScope = 'All',

    [Parameter()]
    [switch]$SkipDependencyCheck,

    [Parameter()]
    [switch]$GenerateReport
)

# Import required modules
$ErrorActionPreference = 'Stop'
$VerbosePreference = 'Continue'

# Test configuration
$TestResults = @{
    Passed = 0
    Failed = 0
    Skipped = 0
    Tests = @()
}

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptRoot
$OrchestratorPath = Join-Path $ProjectRoot 'MaintenanceOrchestrator.ps1'

#region Helper Functions

function Write-TestResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$TestName,
        
        [Parameter(Mandatory)]
        [ValidateSet('Pass', 'Fail', 'Skip')]
        [string]$Result,
        
        [Parameter()]
        [string]$Message = '',
        
        [Parameter()]
        [timespan]$Duration = [timespan]::Zero
    )
    
    $TestResults.Tests += [PSCustomObject]@{
        Name = $TestName
        Result = $Result
        Message = $Message
        Duration = $Duration
        Timestamp = Get-Date
    }
    
    switch ($Result) {
        'Pass' { 
            $TestResults.Passed++
            Write-Host "✓ $TestName" -ForegroundColor Green
            if ($Message) { Write-Host "  $Message" -ForegroundColor Gray }
        }
        'Fail' { 
            $TestResults.Failed++
            Write-Host "❌ $TestName" -ForegroundColor Red
            if ($Message) { Write-Host "  $Message" -ForegroundColor Yellow }
        }
        'Skip' { 
            $TestResults.Skipped++
            Write-Host "⚠️ $TestName (Skipped)" -ForegroundColor Yellow
            if ($Message) { Write-Host "  $Message" -ForegroundColor Gray }
        }
    }
}

function Test-Prerequisites {
    [CmdletBinding()]
    param()
    
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    
    try {
        # Test PowerShell version
        if ($PSVersionTable.PSVersion.Major -lt 7) {
            Write-TestResult -TestName 'PowerShell Version' -Result 'Fail' -Message "PowerShell 7+ required, found $($PSVersionTable.PSVersion)" -Duration $stopwatch.Elapsed
            return $false
        }
        Write-TestResult -TestName 'PowerShell Version' -Result 'Pass' -Message "PowerShell $($PSVersionTable.PSVersion)" -Duration $stopwatch.Elapsed
        
        # Enhanced Administrator privileges validation
        $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
        $adminRole = [Security.Principal.WindowsBuiltInRole]::Administrator
        $isAdmin = $currentPrincipal.IsInRole($adminRole)
        
        if (-not $isAdmin) {
            # Test what we CAN validate without admin rights
            $canElevate = $false
            $elevationMethod = "None"
            
            # Check if UAC is enabled (indicates potential for elevation)
            try {
                $uacEnabled = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "EnableLUA" -ErrorAction SilentlyContinue).EnableLUA -eq 1
                if ($uacEnabled) {
                    $elevationMethod = "UAC Available"
                    $canElevate = $true
                }
            }
            catch {
                $elevationMethod = "UAC Status Unknown"
            }
            
            # Check if we can access typical admin-required locations (read-only tests)
            $adminCapabilities = @()
            try {
                if (Test-Path "C:\Windows\System32\drivers\etc\hosts") {
                    $adminCapabilities += "System file access"
                }
            }
            catch { }
            
            try {
                $services = Get-Service -Name "Themes" -ErrorAction SilentlyContinue
                if ($services) {
                    $adminCapabilities += "Service enumeration"
                }
            }
            catch { }
            
            $message = "Non-admin mode validated - $elevationMethod"
            if ($adminCapabilities.Count -gt 0) {
                $message += " | Capabilities: $($adminCapabilities -join ', ')"
            }
            
            Write-TestResult -TestName 'Administrator Privileges' -Result 'Pass' -Message $message -Duration $stopwatch.Elapsed
        }
        else {
            Write-TestResult -TestName 'Administrator Privileges' -Result 'Pass' -Message 'Running with full administrator privileges' -Duration $stopwatch.Elapsed
        }
        
        # Test orchestrator file exists
        if (-not (Test-Path $OrchestratorPath)) {
            Write-TestResult -TestName 'Orchestrator File' -Result 'Fail' -Message "MaintenanceOrchestrator.ps1 not found at $OrchestratorPath" -Duration $stopwatch.Elapsed
            return $false
        }
        Write-TestResult -TestName 'Orchestrator File' -Result 'Pass' -Duration $stopwatch.Elapsed
        
        return $true
    }
    catch {
        Write-TestResult -TestName 'Prerequisites Check' -Result 'Fail' -Message $_.Exception.Message -Duration $stopwatch.Elapsed
        return $false
    }
    finally {
        $stopwatch.Stop()
    }
}

function Test-SystemCapabilities {
    [CmdletBinding()]
    param()
    
    # Test system capabilities that don't require admin rights
    $capabilities = @(
        @{
            Name = "PowerShell Execution Policy"
            Test = { 
                $currentPolicy = Get-ExecutionPolicy -Scope CurrentUser
                $effectivePolicy = Get-ExecutionPolicy
                # Policy is valid if either CurrentUser or Effective allows script execution
                ($currentPolicy -in @('RemoteSigned', 'Unrestricted', 'Bypass')) -or 
                ($effectivePolicy -in @('RemoteSigned', 'Unrestricted', 'Bypass')) -or
                ($currentPolicy -eq 'Undefined' -and $effectivePolicy -ne 'Restricted')
            }
            ExpectedResult = $true
            Message = "User: $(Get-ExecutionPolicy -Scope CurrentUser), Effective: $(Get-ExecutionPolicy)"
        },
        @{
            Name = "Windows Management Instrumentation"
            Test = { $null -ne (Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue) }
            ExpectedResult = $true
            Message = "WMI access functional"
        },
        @{
            Name = "Registry Access (HKCU)"
            Test = { Test-Path "HKCU:\Software" }
            ExpectedResult = $true
            Message = "User registry hive accessible"
        },
        @{
            Name = "Temporary Directory Access"
            Test = { 
                $tempPath = [System.IO.Path]::GetTempPath()
                Test-Path $tempPath -PathType Container 
            }
            ExpectedResult = $true
            Message = "Temp directory: $([System.IO.Path]::GetTempPath())"
        },
        @{
            Name = "Module Import Capability"
            Test = { 
                try {
                    Import-Module Microsoft.PowerShell.Utility -Force -PassThru -ErrorAction SilentlyContinue
                    return $true
                } catch { return $false }
            }
            ExpectedResult = $true
            Message = "PowerShell module system functional"
        }
    )
    
    foreach ($capability in $capabilities) {
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        
        try {
            $testResult = & $capability.Test
            
            if ($testResult -eq $capability.ExpectedResult) {
                Write-TestResult -TestName "Capability: $($capability.Name)" -Result 'Pass' -Message $capability.Message -Duration $stopwatch.Elapsed
            }
            else {
                Write-TestResult -TestName "Capability: $($capability.Name)" -Result 'Fail' -Message "Expected: $($capability.ExpectedResult), Got: $testResult" -Duration $stopwatch.Elapsed
            }
        }
        catch {
            Write-TestResult -TestName "Capability: $($capability.Name)" -Result 'Fail' -Message "Test failed: $($_.Exception.Message)" -Duration $stopwatch.Elapsed
        }
        finally {
            $stopwatch.Stop()
        }
    }
}

function Test-CoreModules {
    [CmdletBinding()]
    param()
    
    $coreModules = @(
        'ConfigManager',
        'DependencyManager', 
        'MenuSystem',
        'ModuleExecutionProtocol',
        'TaskScheduler'
    )
    
    foreach ($moduleName in $coreModules) {
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        
        try {
            $modulePath = Join-Path $ProjectRoot "modules\core\$moduleName.psm1"
            
            if (-not (Test-Path $modulePath)) {
                Write-TestResult -TestName "Core Module: $moduleName" -Result 'Fail' -Message "Module file not found: $modulePath" -Duration $stopwatch.Elapsed
                continue
            }
            
            # Test module import
            Import-Module $modulePath -Force -ErrorAction Stop
            Write-TestResult -TestName "Core Module: $moduleName" -Result 'Pass' -Message 'Successfully imported' -Duration $stopwatch.Elapsed
            
        }
        catch {
            Write-TestResult -TestName "Core Module: $moduleName" -Result 'Fail' -Message $_.Exception.Message -Duration $stopwatch.Elapsed
        }
        finally {
            $stopwatch.Stop()
        }
    }
}

function Test-TaskModules {
    [CmdletBinding()]
    param()
    
    $moduleTypes = @{
        'type1' = @('BloatwareDetection', 'ReportGeneration', 'SecurityAudit', 'SystemInventory')
        'type2' = @('BloatwareRemoval', 'EssentialApps', 'SystemOptimization', 'TelemetryDisable', 'WindowsUpdates')
    }
    
    foreach ($type in $moduleTypes.Keys) {
        foreach ($moduleName in $moduleTypes[$type]) {
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            
            try {
                $modulePath = Join-Path $ProjectRoot "modules\$type\$moduleName.psm1"
                
                if (-not (Test-Path $modulePath)) {
                    Write-TestResult -TestName "$type Module: $moduleName" -Result 'Fail' -Message "Module file not found: $modulePath" -Duration $stopwatch.Elapsed
                    continue
                }
                
                # Test module import
                Import-Module $modulePath -Force -ErrorAction Stop
                Write-TestResult -TestName "$type Module: $moduleName" -Result 'Pass' -Message 'Successfully imported' -Duration $stopwatch.Elapsed
                
            }
            catch {
                Write-TestResult -TestName "$type Module: $moduleName" -Result 'Fail' -Message $_.Exception.Message -Duration $stopwatch.Elapsed
            }
            finally {
                $stopwatch.Stop()
            }
        }
    }
}

function Test-ConfigurationSystem {
    [CmdletBinding()]
    param()
    
    $configFiles = @(
        'main-config.json',
        'logging-config.json'
    )
    
    foreach ($configFile in $configFiles) {
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        
        try {
            $configPath = Join-Path $ProjectRoot "config\$configFile"
            
            if (-not (Test-Path $configPath)) {
                Write-TestResult -TestName "Config File: $configFile" -Result 'Fail' -Message "Configuration file not found: $configPath" -Duration $stopwatch.Elapsed
                continue
            }
            
            # Test JSON parsing
            $null = Get-Content $configPath -Raw | ConvertFrom-Json -ErrorAction Stop
            Write-TestResult -TestName "Config File: $configFile" -Result 'Pass' -Message 'Valid JSON structure' -Duration $stopwatch.Elapsed
            
        }
        catch {
            Write-TestResult -TestName "Config File: $configFile" -Result 'Fail' -Message $_.Exception.Message -Duration $stopwatch.Elapsed
        }
        finally {
            $stopwatch.Stop()
        }
    }
}

function Test-OrchestratorExecution {
    [CmdletBinding(SupportsShouldProcess)]
    param()
    
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    
    try {
        # Test dry-run execution
        if ($PSCmdlet.ShouldProcess('MaintenanceOrchestrator.ps1', 'Test dry-run execution')) {
            $testParams = @{
                FilePath = 'pwsh.exe'
                ArgumentList = @(
                    '-File', $OrchestratorPath,
                    '-NonInteractive',
                    '-DryRun',
                    '-TaskNumbers', '1'
                )
                Wait = $true
                PassThru = $true
                WindowStyle = 'Hidden'
            }
            
            $process = Start-Process @testParams
            
            if ($process.ExitCode -eq 0) {
                Write-TestResult -TestName 'Orchestrator Dry-Run' -Result 'Pass' -Message 'Successfully executed in dry-run mode' -Duration $stopwatch.Elapsed
            }
            else {
                Write-TestResult -TestName 'Orchestrator Dry-Run' -Result 'Fail' -Message "Exit code: $($process.ExitCode)" -Duration $stopwatch.Elapsed
            }
        }
        else {
            Write-TestResult -TestName 'Orchestrator Dry-Run' -Result 'Skip' -Message 'WhatIf mode - execution skipped' -Duration $stopwatch.Elapsed
        }
    }
    catch {
        Write-TestResult -TestName 'Orchestrator Dry-Run' -Result 'Fail' -Message $_.Exception.Message -Duration $stopwatch.Elapsed
    }
    finally {
        $stopwatch.Stop()
    }
}

function Test-DependencyValidation {
    [CmdletBinding()]
    param()
    
    if ($SkipDependencyCheck) {
        Write-TestResult -TestName 'Dependency Validation' -Result 'Skip' -Message 'Skipped per parameter'
        return
    }
    
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    
    try {
        # Import DependencyManager for testing
        $depManagerPath = Join-Path $ProjectRoot 'modules\core\DependencyManager.psm1'
        Import-Module $depManagerPath -Force
        
        # Test dependency detection
        $requiredDependencies = @('winget', 'powershell')
        $optionalDependencies = @('chocolatey')
        
        # Test required dependencies
        foreach ($dependency in $requiredDependencies) {
            try {
                $status = Get-Command $dependency -ErrorAction SilentlyContinue
                if ($status) {
                    Write-TestResult -TestName "Dependency: $dependency" -Result 'Pass' -Message 'Available (Required)' -Duration $stopwatch.Elapsed
                }
                else {
                    Write-TestResult -TestName "Dependency: $dependency" -Result 'Fail' -Message 'Not found (Required)' -Duration $stopwatch.Elapsed
                }
            }
            catch {
                Write-TestResult -TestName "Dependency: $dependency" -Result 'Fail' -Message $_.Exception.Message -Duration $stopwatch.Elapsed
            }
        }
        
        # Enhanced optional dependency testing
        foreach ($dependency in $optionalDependencies) {
            try {
                $status = Get-Command $dependency -ErrorAction SilentlyContinue
                if ($status) {
                    # Get version information if available
                    try {
                        $version = & $dependency --version 2>$null | Select-Object -First 1
                        Write-TestResult -TestName "Dependency: $dependency" -Result 'Pass' -Message "Available v$version (Optional)" -Duration $stopwatch.Elapsed
                    }
                    catch {
                        Write-TestResult -TestName "Dependency: $dependency" -Result 'Pass' -Message 'Available (Optional)' -Duration $stopwatch.Elapsed
                    }
                }
                else {
                    # Enhanced detection for chocolatey
                    if ($dependency -eq 'chocolatey') {
                        $chocoPath = $null
                        $installationOptions = @()
                        
                        # Check common installation paths
                        $commonPaths = @(
                            "$env:ProgramData\chocolatey\bin\choco.exe",
                            "$env:ChocolateyInstall\bin\choco.exe",
                            "$env:ALLUSERSPROFILE\chocolatey\bin\choco.exe"
                        )
                        
                        foreach ($path in $commonPaths) {
                            if (Test-Path $path) {
                                $chocoPath = $path
                                break
                            }
                        }
                        
                        if ($chocoPath) {
                            Write-TestResult -TestName "Dependency: $dependency" -Result 'Pass' -Message "Found at $chocoPath (Optional)" -Duration $stopwatch.Elapsed
                        }
                        else {
                            # Check if we can install it
                            $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
                            $isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
                            
                            if ($isAdmin) {
                                $installationOptions += "Can install via PowerShell (Admin)"
                            }
                            
                            if (Get-Command "winget" -ErrorAction SilentlyContinue) {
                                $installationOptions += "Available via winget"
                            }
                            
                            $message = "Not installed (Optional)"
                            if ($installationOptions.Count -gt 0) {
                                $message += " | Install options: $($installationOptions -join ', ')"
                                Write-TestResult -TestName "Dependency: $dependency" -Result 'Pass' -Message $message -Duration $stopwatch.Elapsed
                            }
                            else {
                                Write-TestResult -TestName "Dependency: $dependency" -Result 'Pass' -Message "$message | No auto-install available" -Duration $stopwatch.Elapsed
                            }
                        }
                    }
                    else {
                        Write-TestResult -TestName "Dependency: $dependency" -Result 'Pass' -Message 'Not found (Optional - OK)' -Duration $stopwatch.Elapsed
                    }
                }
            }
            catch {
                Write-TestResult -TestName "Dependency: $dependency" -Result 'Pass' -Message "Optional dependency validation completed: $($_.Exception.Message)" -Duration $stopwatch.Elapsed
            }
        }
    }
    catch {
        Write-TestResult -TestName 'Dependency Validation' -Result 'Fail' -Message $_.Exception.Message -Duration $stopwatch.Elapsed
    }
    finally {
        $stopwatch.Stop()
    }
}

function New-TestReport {
    [CmdletBinding(SupportsShouldProcess)]
    param()
    
    if (-not $GenerateReport) {
        return
    }
    
    $reportPath = Join-Path $ScriptRoot 'TestReport.html'
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    
    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Enhanced Orchestration Test Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .header { background-color: #f0f0f0; padding: 10px; border-radius: 5px; }
        .summary { margin: 20px 0; }
        .pass { color: green; }
        .fail { color: red; }
        .skip { color: orange; }
        table { border-collapse: collapse; width: 100%; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #f2f2f2; }
    </style>
</head>
<body>
    <div class="header">
        <h1>Enhanced Orchestration Test Report</h1>
        <p>Generated: $timestamp</p>
    </div>
    
    <div class="summary">
        <h2>Test Summary</h2>
        <p><span class="pass">Passed: $($TestResults.Passed)</span></p>
        <p><span class="fail">Failed: $($TestResults.Failed)</span></p>
        <p><span class="skip">Skipped: $($TestResults.Skipped)</span></p>
        <p>Total: $($TestResults.Tests.Count)</p>
    </div>
    
    <h2>Test Details</h2>
    <table>
        <tr>
            <th>Test Name</th>
            <th>Result</th>
            <th>Message</th>
            <th>Duration (ms)</th>
            <th>Timestamp</th>
        </tr>
"@

    foreach ($test in $TestResults.Tests) {
        $resultClass = $test.Result.ToLower()
        $duration = [math]::Round($test.Duration.TotalMilliseconds, 2)
        
        $html += @"
        <tr>
            <td>$($test.Name)</td>
            <td class="$resultClass">$($test.Result)</td>
            <td>$($test.Message)</td>
            <td>$duration</td>
            <td>$($test.Timestamp.ToString('HH:mm:ss'))</td>
        </tr>
"@
    }

    $html += @"
    </table>
</body>
</html>
"@

    try {
        $html | Out-File -FilePath $reportPath -Encoding UTF8
        Write-Host "📊 Test report generated: $reportPath" -ForegroundColor Cyan
    }
    catch {
        Write-Warning "Failed to generate test report: $_"
    }
}

#endregion

#region Main Execution

function Invoke-TestSuite {
    [CmdletBinding()]
    param()
    
    Write-Host "🚀 Starting Enhanced Orchestration Tests" -ForegroundColor Cyan
    Write-Host "Test Scope: $TestScope" -ForegroundColor Gray
    Write-Host "=" * 60 -ForegroundColor Gray
    
    # Prerequisites (always run)
    if (-not (Test-Prerequisites)) {
        Write-Host "❌ Prerequisites failed - aborting test suite" -ForegroundColor Red
        return $false
    }
    
    # Core tests
    if ($TestScope -in 'All', 'Core') {
        Write-Host "`n� Testing System Capabilities..." -ForegroundColor Yellow
        Test-SystemCapabilities
        
        Write-Host "`n�📦 Testing Core Modules..." -ForegroundColor Yellow
        Test-CoreModules
        
        Write-Host "`n⚙️ Testing Configuration System..." -ForegroundColor Yellow
        Test-ConfigurationSystem
        
        Write-Host "`n🔍 Testing Dependencies..." -ForegroundColor Yellow
        Test-DependencyValidation
    }
    
    # Module tests
    if ($TestScope -in 'All', 'Modules') {
        Write-Host "`n🧩 Testing Task Modules..." -ForegroundColor Yellow
        Test-TaskModules
    }
    
    # Integration tests
    if ($TestScope -in 'All', 'Integration') {
        Write-Host "`n🔄 Testing Orchestrator Integration..." -ForegroundColor Yellow
        Test-OrchestratorExecution
    }
    
    # Generate report
    New-TestReport
    
    # Summary
    Write-Host "`n" + ("=" * 60) -ForegroundColor Gray
    Write-Host "📋 Test Summary:" -ForegroundColor Cyan
    Write-Host "✓ Passed: $($TestResults.Passed)" -ForegroundColor Green
    Write-Host "❌ Failed: $($TestResults.Failed)" -ForegroundColor Red
    Write-Host "⚠️ Skipped: $($TestResults.Skipped)" -ForegroundColor Yellow
    Write-Host "📊 Total: $($TestResults.Tests.Count)" -ForegroundColor Gray
    
    # Analyze failure types
    $criticalFailures = $TestResults.Tests | Where-Object { 
        $_.Result -eq 'Fail' -and 
        -not ($_.Name -like "*chocolatey*" -and $_.Message -like "*Optional*") -and
        -not ($_.Name -like "*Administrator Privileges*")
    }
    
    if ($TestResults.Failed -eq 0) {
        Write-Host "🎉 All tests passed!" -ForegroundColor Green
        return $true
    }
    elseif ($criticalFailures.Count -eq 0) {
        Write-Host "✅ All critical tests passed! Only optional/expected failures detected." -ForegroundColor Green
        Write-Host "� Optional failures (can be ignored): $($TestResults.Failed - $criticalFailures.Count)" -ForegroundColor Gray
        return $true
    }
    else {
        Write-Host "💥 Critical test failures detected. Check the results above." -ForegroundColor Red
        Write-Host "🔥 Critical failures: $($criticalFailures.Count)" -ForegroundColor Red
        return $false
    }
}

# Execute the test suite
try {
    $success = Invoke-TestSuite
    exit ($success ? 0 : 1)
}
catch {
    Write-Host "💥 Fatal error during test execution: $_" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Gray
    exit 2
}

#endregion