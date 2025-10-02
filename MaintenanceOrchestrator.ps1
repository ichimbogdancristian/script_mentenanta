#Requires -Version 7.0

using namespace System.Collections.Generic

<#
.SYNOPSIS
    Windows Maintenance Automation - Enhanced Central Orchestrator v2.1

.DESCRIPTION
    Next-generation central coordination script with comprehensive module execution protocol,
    dependency management, completion reporting, and robust error handling.

.PARAMETER LogFilePath
    Path to the log file (optional)

.PARAMETER ConfigPath
    Path to the configuration directory (optional, auto-detected if not provided)

.PARAMETER NonInteractive
    Skip interactive menus and use default settings

.PARAMETER DryRun
    Run in dry-run mode (simulate changes without modifying the system)

.PARAMETER TaskNumbers
    Comma-separated list of task numbers to execute (e.g., "1,3,5")

.PARAMETER ModuleName
    Execute a specific module by name

.PARAMETER EnableDetailedLogging
    Enable comprehensive logging including dependency tracking

.EXAMPLE
    .\EnhancedMaintenanceOrchestrator.ps1
    # Interactive mode with enhanced protocol

.EXAMPLE
    .\EnhancedMaintenanceOrchestrator.ps1 -NonInteractive -DryRun
    # Unattended dry-run with full dependency validation

.EXAMPLE
    .\EnhancedMaintenanceOrchestrator.ps1 -ModuleName "SystemInventory" -EnableDetailedLogging
    # Execute specific module with detailed logging

.NOTES
    Author: Windows Maintenance Automation Project
    Version: 2.1.0
    Requires: PowerShell 7.0+, Administrator privileges for Type2 modules
#>

param(
    [string]$LogFilePath,
    [string]$ConfigPath,
    [switch]$NonInteractive,
    [switch]$DryRun,
    [string]$TaskNumbers,
    [string]$ModuleName,
    [switch]$EnableDetailedLogging
)

#region Script Initialization

# Script path detection and environment setup
$ScriptRoot = $PSScriptRoot
if (-not $ScriptRoot) {
    $ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
}

$WorkingDirectory = $ScriptRoot
$StartTime = Get-Date

Write-Host "╔══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║                          Windows Maintenance Automation - Enhanced Orchestrator v2.1                                       ║" -ForegroundColor Cyan
Write-Host "║                                     Advanced Module Execution Protocol                                                      ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan

# Set up temp directories
$TempRoot = Join-Path $WorkingDirectory 'temp_files'
$ReportsDir = Join-Path $TempRoot 'reports'
$LogsDir = Join-Path $TempRoot 'logs'
$InventoryDir = Join-Path $TempRoot 'inventory'

@($TempRoot, $ReportsDir, $LogsDir, $InventoryDir) | ForEach-Object {
    if (-not (Test-Path $_)) {
        New-Item -Path $_ -ItemType Directory -Force | Out-Null
    }
}

# Set up log file
if (-not $LogFilePath) {
    $LogFilePath = if ($env:SCRIPT_LOG_FILE) { 
        $env:SCRIPT_LOG_FILE 
    } else { 
        Join-Path $LogsDir 'maintenance.log' 
    }
}

$Global:MaintenanceLogFile = $LogFilePath

# Detect configuration path
if (-not $ConfigPath) {
    $ConfigPath = Join-Path $WorkingDirectory 'config'
    if (-not (Test-Path $ConfigPath)) {
        $ConfigPath = Join-Path $ScriptRoot 'config'
    }
}

if (-not (Test-Path $ConfigPath)) {
    throw "Configuration directory not found. Expected at: $ConfigPath"
}

Write-Host ""
Write-Host "🔧 System Initialization:" -ForegroundColor Yellow
Write-Host "  Working Directory: $WorkingDirectory" -ForegroundColor Gray
Write-Host "  Configuration: $ConfigPath" -ForegroundColor Gray
Write-Host "  Log File: $LogFilePath" -ForegroundColor Gray
Write-Host "  Execution Mode: $(if($DryRun){'DRY-RUN'}else{'LIVE'})" -ForegroundColor $(if($DryRun){'Blue'}else{'Green'})

#endregion

#region Enhanced Privilege Validation

Write-Host ""
Write-Host "🔐 Enhanced Privilege Validation:" -ForegroundColor Yellow

try {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    
    if ($isAdmin) {
        Write-Host "  ✅ Administrator privileges confirmed" -ForegroundColor Green
        Write-Host "  🔑 Elevation Context: PowerShell $($PSVersionTable.PSVersion)" -ForegroundColor Green
    } else {
        Write-Host "  ⚠️  Running without Administrator privileges" -ForegroundColor Yellow
        Write-Host "  💡 Type2 modules will be skipped or may fail" -ForegroundColor Yellow
        if (-not $DryRun) {
            Write-Host "  🛠️  Recommendation: Right-click script.bat and select 'Run as administrator'" -ForegroundColor Cyan
        }
    }
} catch {
    Write-Host "  ❌ Unable to determine privilege level: $_" -ForegroundColor Red
}

#endregion

#region Core Module Loading

Write-Host ""
Write-Host "📦 Loading Enhanced Core Modules:" -ForegroundColor Yellow

$ModulesPath = Join-Path $WorkingDirectory 'modules'
$CoreModulesPath = Join-Path $ModulesPath 'core'

# Core modules in load order
$CoreModules = @(
    'ConfigManager',
    'MenuSystem',
    'ModuleExecutionProtocol'
)

foreach ($coreModuleName in $CoreModules) {
    $modulePath = Join-Path $CoreModulesPath "$coreModuleName.psm1"
    if (Test-Path $modulePath) {
        try {
            Import-Module $modulePath -Force -ErrorAction Stop
            Write-Host "  ✅ Loaded: $coreModuleName" -ForegroundColor Green
        }
        catch {
            Write-Host "  ❌ Failed to load $coreModuleName`: $_" -ForegroundColor Red
            exit 1
        }
    } else {
        Write-Host "  ❌ Module not found: $modulePath" -ForegroundColor Red
        exit 1
    }
}

#endregion

#region Configuration Loading

Write-Host ""
Write-Host "⚙️  Enhanced Configuration Loading:" -ForegroundColor Yellow

try {
    Initialize-ConfigSystem -ConfigRootPath $ConfigPath
    $MainConfig = Get-MainConfiguration
    $null = Get-LoggingConfiguration
    
    Write-Host "  ✅ Main configuration loaded successfully" -ForegroundColor Green
    Write-Host "  ✅ Logging configuration loaded successfully" -ForegroundColor Green
    
    # Load app configurations for dependency validation
    $BloatwareLists = Get-BloatwareConfiguration
    $EssentialApps = Get-EssentialAppsConfiguration
    
    $totalBloatware = ($BloatwareLists.Values | Measure-Object -Sum { $_.Count }).Sum
    $totalEssentialApps = ($EssentialApps.Values | Measure-Object -Sum { $_.Count }).Sum
    
    Write-Host "  📋 Bloatware lists: $($BloatwareLists.Keys.Count) categories, $totalBloatware total entries" -ForegroundColor Green
    Write-Host "  📱 Essential apps: $($EssentialApps.Keys.Count) categories, $totalEssentialApps total entries" -ForegroundColor Green
    
} catch {
    Write-Host "  ❌ Configuration loading failed: $_" -ForegroundColor Red
    exit 1
}

#endregion

#region Enhanced Module Registration with Dependencies

Write-Host ""
Write-Host "🏗️  Enhanced Module Registration with Dependency Analysis:" -ForegroundColor Yellow

# Create module executor
# Convert PSCustomObject to hashtable for compatibility
if ($MainConfig -is [PSCustomObject]) {
    $configHash = @{}
    $MainConfig.PSObject.Properties | ForEach-Object { $configHash[$_.Name] = $_.Value }
    $MainConfig = $configHash
}
$moduleExecutor = New-ModuleExecutor -Configuration $MainConfig -DryRun $DryRun

# Define enhanced module manifests with explicit dependencies
$ModuleManifests = @(
    @{
        Name = 'SystemInventory'
        Version = '1.0.0'
        Description = 'Collect comprehensive system information and generate inventory reports'
        Type = 'Type1'
        Category = 'Inventory'
        ModulePath = Join-Path $ModulesPath 'type1\SystemInventory.psm1'
        EntryFunction = 'Get-SystemInventory'
        Dependencies = @()  # No dependencies - foundational module
        RequiresElevation = $false
        TimeoutSeconds = 180
        ConfigurationDependencies = @()
    },
    @{
        Name = 'BloatwareDetection'
        Version = '1.0.0'
        Description = 'Scan for bloatware applications and system components'
        Type = 'Type1'
        Category = 'Detection'
        ModulePath = Join-Path $ModulesPath 'type1\BloatwareDetection.psm1'
        EntryFunction = 'Find-InstalledBloatware'
        Dependencies = @('SystemInventory')  # Depends on system inventory for comprehensive scanning
        RequiresElevation = $false
        TimeoutSeconds = 300
        ConfigurationDependencies = @('bloatware-lists')
    },
    @{
        Name = 'SecurityAudit'
        Version = '1.0.0'
        Description = 'Perform security audit and apply hardening recommendations'
        Type = 'Type1'
        Category = 'Security'
        ModulePath = Join-Path $ModulesPath 'type1\SecurityAudit.psm1'
        EntryFunction = 'Start-SecurityAudit'
        Dependencies = @('SystemInventory')  # Uses system info for context
        RequiresElevation = $false
        TimeoutSeconds = 240
        ConfigurationDependencies = @()
    },
    @{
        Name = 'BloatwareRemoval'
        Version = '1.0.0'
        Description = 'Remove detected bloatware applications using multiple methods'
        Type = 'Type2'
        Category = 'Cleanup'
        ModulePath = Join-Path $ModulesPath 'type2\BloatwareRemoval.psm1'
        EntryFunction = 'Remove-DetectedBloatware'
        Dependencies = @('BloatwareDetection')  # Must run after detection
        RequiresElevation = $true
        TimeoutSeconds = 600
        ConfigurationDependencies = @('bloatware-lists')
    },
    @{
        Name = 'EssentialApps'
        Version = '1.0.0'
        Description = 'Install essential applications from curated lists'
        Type = 'Type2'
        Category = 'Installation'
        ModulePath = Join-Path $ModulesPath 'type2\EssentialApps.psm1'
        EntryFunction = 'Install-EssentialApplications'
        Dependencies = @('SystemInventory')  # Uses system info to avoid conflicts
        RequiresElevation = $true
        TimeoutSeconds = 1800  # 30 minutes for installations
        ConfigurationDependencies = @('essential-apps')
    },
    @{
        Name = 'WindowsUpdates'
        Version = '1.0.0'
        Description = 'Check for and install Windows updates'
        Type = 'Type2'
        Category = 'Updates'
        ModulePath = Join-Path $ModulesPath 'type2\WindowsUpdates.psm1'
        EntryFunction = 'Install-WindowsUpdates'
        Dependencies = @()  # Independent operation
        RequiresElevation = $true
        TimeoutSeconds = 3600  # 60 minutes for updates
        ConfigurationDependencies = @()
    },
    @{
        Name = 'TelemetryDisable'
        Version = '1.0.0'
        Description = 'Disable Windows telemetry and privacy-invasive features'
        Type = 'Type2'
        Category = 'Privacy'
        ModulePath = Join-Path $ModulesPath 'type2\TelemetryDisable.psm1'
        EntryFunction = 'Disable-WindowsTelemetry'
        Dependencies = @()  # Independent operation
        RequiresElevation = $true
        TimeoutSeconds = 300
        ConfigurationDependencies = @()
    },
    @{
        Name = 'SystemOptimization'
        Version = '1.0.0'
        Description = 'Apply performance optimizations and cleanup temporary files'
        Type = 'Type2'
        Category = 'Optimization'
        ModulePath = Join-Path $ModulesPath 'type2\SystemOptimization.psm1'
        EntryFunction = 'Optimize-SystemPerformance'
        Dependencies = @('SystemInventory')  # Uses system info for optimization decisions
        RequiresElevation = $true
        TimeoutSeconds = 600
        ConfigurationDependencies = @()
    },
    @{
        Name = 'ReportGeneration'
        Version = '1.0.0'
        Description = 'Generate comprehensive HTML and text reports of all operations'
        Type = 'Type1'
        Category = 'Reporting'
        ModulePath = Join-Path $ModulesPath 'type1\ReportGeneration.psm1'
        EntryFunction = 'New-MaintenanceReport'
        Dependencies = @('SystemInventory', 'SecurityAudit')  # Aggregates results from other modules
        RequiresElevation = $false
        TimeoutSeconds = 120
        ConfigurationDependencies = @()
    }
)

# Register all modules and validate dependencies
$registeredModules = @()
foreach ($manifestData in $ModuleManifests) {
    try {
        # Validate module file exists
        if (-not (Test-Path $manifestData.ModulePath)) {
            Write-Host "  ⚠️  Module file not found: $($manifestData.Name) at $($manifestData.ModulePath)" -ForegroundColor Yellow
            continue
        }
        
        # Validate configuration dependencies
        $configErrors = @()
        foreach ($configDep in $manifestData.ConfigurationDependencies) {
            $configPath = Join-Path $ConfigPath $configDep
            if (-not (Test-Path $configPath)) {
                $configErrors += "Missing configuration: $configDep"
            }
        }
        
        if ($configErrors.Count -gt 0) {
            Write-Host "  ⚠️  Configuration dependencies missing for $($manifestData.Name): $($configErrors -join ', ')" -ForegroundColor Yellow
        }
        
        # Create and register manifest
        $manifest = New-ModuleManifest -Properties $manifestData
        $moduleExecutor.RegisterModule($manifest)
        $registeredModules += $manifest
        
        $depStr = if ($manifest.Dependencies.Count -gt 0) { " (depends: $($manifest.Dependencies -join ', '))" } else { " (no dependencies)" }
        $elevStr = if ($manifest.RequiresElevation) { " [ADMIN]" } else { " [USER]" }
        
        Write-Host "  ✅ $($manifest.Name)$elevStr$depStr" -ForegroundColor Green
        
        if ($EnableDetailedLogging) {
            Write-Host "    📋 Timeout: $($manifest.TimeoutSeconds)s, Config deps: $($manifest.ConfigurationDependencies -join ', ')" -ForegroundColor Gray
        }
        
    } catch {
        Write-Host "  ❌ Failed to register module $($manifestData.Name): $_" -ForegroundColor Red
    }
}

Write-Host "  📊 Total registered modules: $($registeredModules.Count)" -ForegroundColor Cyan

#endregion

#region Module Selection & Execution Planning

Write-Host ""
Write-Host "🎯 Module Selection & Execution Planning:" -ForegroundColor Yellow

$selectedModules = @()

if ($ModuleName) {
    # Single module execution
    Write-Host "  🔍 Debug: Looking for module '$ModuleName' among $($registeredModules.Count) registered modules" -ForegroundColor Gray
    $selectedModule = $registeredModules | Where-Object { $_.Name -eq $ModuleName }
    if ($selectedModule) {
        $selectedModules = @($ModuleName)
        Write-Host "  🎯 Single module selected: $ModuleName" -ForegroundColor Cyan
    } else {
        Write-Host "  ❌ Module not found: $ModuleName" -ForegroundColor Red
        Write-Host "  Available modules: $($registeredModules.Name -join ', ')" -ForegroundColor Gray
        exit 1
    }
} elseif ($TaskNumbers) {
    # Task number selection (backward compatibility)
    $taskNums = $TaskNumbers.Split(',') | ForEach-Object { $_.Trim() }
    $selectedModules = @()
    foreach ($num in $taskNums) {
        if ([int]$num -le $registeredModules.Count) {
            $selectedModules += $registeredModules[[int]$num - 1].Name
        }
    }
    Write-Host "  🔢 Selected by task numbers: $($selectedModules -join ', ')" -ForegroundColor Cyan
} elseif ($NonInteractive) {
    # All modules in non-interactive mode
    $selectedModules = $registeredModules.Name
    Write-Host "  🤖 Non-interactive mode: All modules selected" -ForegroundColor Cyan
} else {
    # Interactive selection (simplified for now)
    Write-Host "  🖱️  Interactive mode: All modules selected (enhanced UI coming soon)" -ForegroundColor Cyan
    $selectedModules = $registeredModules.Name
}

Write-Host "  📋 Modules to execute: $($selectedModules.Count)" -ForegroundColor Green
if ($EnableDetailedLogging) {
    Write-Host "  📝 Module list: $($selectedModules -join ' → ')" -ForegroundColor Gray
}

#endregion

#region Enhanced Module Execution

Write-Host ""
Write-Host "🚀 Enhanced Module Execution Engine:" -ForegroundColor Yellow
Write-Host "══════════════════════════════════════════════════════════════" -ForegroundColor Cyan

try {
    # Execute modules with full dependency management
    $executionResults = $moduleExecutor.ExecuteAllModules($selectedModules)
    
    Write-Host ""
    Write-Host "📊 Execution Results Summary:" -ForegroundColor Yellow
    Write-Host "────────────────────────────────" -ForegroundColor DarkCyan
    
    foreach ($result in $executionResults) {
        $statusIcon = switch ($result.CompletionStatus) {
            'Success' { '✅' }
            'Failed' { '❌' }
            'Timeout' { '⏱️' }
            'Cancelled' { '🚫' }
            'DependencyFailure' { '🔗' }
            default { '❓' }
        }
        
        $statusColor = switch ($result.CompletionStatus) {
            'Success' { 'Green' }
            'Failed' { 'Red' }
            'Timeout' { 'Yellow' }
            'Cancelled' { 'Gray' }
            'DependencyFailure' { 'Magenta' }
            default { 'White' }
        }
        
        Write-Host "  $statusIcon " -NoNewline
        Write-Host "$($result.ModuleName) " -NoNewline -ForegroundColor White
        Write-Host "($([math]::Round($result.DurationSeconds, 2))s) " -NoNewline -ForegroundColor Gray
        Write-Host "- $($result.CompletionStatus)" -ForegroundColor $statusColor
        
        if ($result.Error -and $EnableDetailedLogging) {
            Write-Host "    💬 Error: $($result.Error)" -ForegroundColor Red
        }
        
        if ($result.ConfigurationErrors.Count -gt 0) {
            Write-Host "    ⚠️  Config Issues: $($result.ConfigurationErrors -join ', ')" -ForegroundColor Yellow
        }
    }
    
} catch {
    Write-Host "❌ Critical execution engine failure: $_" -ForegroundColor Red
    exit 1
}

#endregion

#region Enhanced Execution Summary

Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║                                            ENHANCED EXECUTION SUMMARY                                                       ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan

$totalDuration = ((Get-Date) - $StartTime).TotalSeconds
$successfulModules = ($executionResults | Where-Object { $_.Success }).Count
$failedModules = ($executionResults | Where-Object { -not $_.Success }).Count
$dependencyFailures = ($executionResults | Where-Object { $_.CompletionStatus -eq 'DependencyFailure' }).Count
$timeouts = ($executionResults | Where-Object { $_.CompletionStatus -eq 'Timeout' }).Count

Write-Host ""
Write-Host "📊 Overall Statistics:" -ForegroundColor Yellow
Write-Host "  🕒 Total Duration: $([math]::Round($totalDuration, 2)) seconds" -ForegroundColor White
Write-Host "  📦 Modules Executed: $($executionResults.Count)" -ForegroundColor White
Write-Host "  ✅ Successful: $successfulModules" -ForegroundColor Green
Write-Host "  ❌ Failed: $failedModules" -ForegroundColor $(if ($failedModules -gt 0) { 'Red' } else { 'Green' })
Write-Host "  🔗 Dependency Failures: $dependencyFailures" -ForegroundColor $(if ($dependencyFailures -gt 0) { 'Magenta' } else { 'Green' })
Write-Host "  ⏱️ Timeouts: $timeouts" -ForegroundColor $(if ($timeouts -gt 0) { 'Yellow' } else { 'Green' })

if ($executionResults.Count -gt 0) {
    $successRate = [math]::Round(($successfulModules / $executionResults.Count) * 100, 1)
    Write-Host "  📈 Success Rate: $successRate%" -ForegroundColor $(if ($successRate -ge 80) { 'Green' } elseif ($successRate -ge 60) { 'Yellow' } else { 'Red' })
}

# Save enhanced execution summary
$enhancedSummary = @{
    StartTime = $StartTime
    EndTime = Get-Date
    TotalDuration = $totalDuration
    ExecutionMode = if ($DryRun) { 'DRY-RUN' } else { 'LIVE' }
    ModulesExecuted = $executionResults.Count
    SuccessfulModules = $successfulModules
    FailedModules = $failedModules
    DependencyFailures = $dependencyFailures
    Timeouts = $timeouts
    SuccessRate = if ($executionResults.Count -gt 0) { ($successfulModules / $executionResults.Count) * 100 } else { 0 }
    Configuration = $MainConfig
    ExecutionResults = $executionResults
    DependencyGraph = $moduleExecutor.DependencyResolver.DependencyGraph
}

$summaryPath = Join-Path $ReportsDir "enhanced-execution-summary-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
try {
    $enhancedSummary | ConvertTo-Json -Depth 10 | Set-Content -Path $summaryPath -Encoding UTF8
    Write-Host ""
    Write-Host "📄 Enhanced execution summary saved: $summaryPath" -ForegroundColor Cyan
} catch {
    Write-Host "⚠️  Could not save execution summary: $_" -ForegroundColor Yellow
}

Write-Host ""
if ($failedModules -eq 0 -and $dependencyFailures -eq 0 -and $timeouts -eq 0) {
    Write-Host "🎉 All modules completed successfully with enhanced protocol!" -ForegroundColor Green
} elseif ($successfulModules -gt 0) {
    Write-Host "⚠️  Execution completed with some issues - see detailed logs above" -ForegroundColor Yellow
} else {
    Write-Host "❌ Execution completed with significant failures" -ForegroundColor Red
}

#endregion

# Exit with appropriate code
exit $(if ($failedModules -gt $successfulModules) { 1 } else { 0 })