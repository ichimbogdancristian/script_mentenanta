#Requires -Version 7.0

using namespace System.Collections.Generic

<#
.SYNOPSIS
    Windows Maintenance Automation - Central Orchestrator

.DESCRIPTION
    Central coordination script for the modular Windows maintenance system.
    Handles module loading, configuration management, interactive menus, and task execution.

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

.EXAMPLE
    .\MaintenanceOrchestrator.ps1
    # Interactive mode with menus

.EXAMPLE
    .\MaintenanceOrchestrator.ps1 -NonInteractive
    # Unattended mode with all tasks

.EXAMPLE
    .\MaintenanceOrchestrator.ps1 -DryRun -TaskNumbers "1,2,3"
    # Dry-run mode with specific tasks

.NOTES
    Author: Windows Maintenance Automation Project
    Version: 2.0.0
    Requires: PowerShell 7.0+, Administrator privileges
#>

param(
    [string]$LogFilePath,
    [string]$ConfigPath,
    [switch]$NonInteractive,
    [switch]$DryRun,
    [string]$TaskNumbers
)

#region Script Initialization

# Script path detection and environment setup
$ScriptRoot = $PSScriptRoot
if (-not $ScriptRoot) {
    $ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
}

# Always use the script's actual location as working directory for reliable module loading
# This ensures modules are found relative to the orchestrator script, not environment variables
$WorkingDirectory = $ScriptRoot

Write-Host "Windows Maintenance Automation - Central Orchestrator v2.0.0" -ForegroundColor Cyan
Write-Host "Working Directory: $WorkingDirectory" -ForegroundColor Gray
Write-Host "Script Root: $ScriptRoot" -ForegroundColor Gray
Write-Host "Environment WORKING_DIRECTORY: $env:WORKING_DIRECTORY" -ForegroundColor Gray

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

Write-Host "Configuration Path: $ConfigPath" -ForegroundColor Gray

# Set up temp directories
$TempRoot = Join-Path $WorkingDirectory 'temp_files'
$ReportsDir = Join-Path $TempRoot 'reports'
$LogsDir = Join-Path $TempRoot 'logs'
$InventoryDir = Join-Path $TempRoot 'inventory'

@($TempRoot, $ReportsDir, $LogsDir, $InventoryDir) | ForEach-Object {
    if (-not (Test-Path $_)) {
        New-Item -Path $_ -ItemType Directory -Force | Out-Null
        Write-Verbose "Created directory: $_"
    }
}

# Set up log file
if (-not $LogFilePath) {
    $LogFilePath = if ($env:SCRIPT_LOG_FILE) { 
        $env:SCRIPT_LOG_FILE 
    } else { 
        Join-Path $WorkingDirectory 'maintenance.log' 
    }
}

Write-Host "Log File: $LogFilePath" -ForegroundColor Gray

#endregion

#region Module Loading

Write-Host "`nLoading modules..." -ForegroundColor Yellow

# Import core modules
$ModulesPath = Join-Path $WorkingDirectory 'modules'
$CoreModulesPath = Join-Path $ModulesPath 'core'

Write-Host "Module Path Resolution:" -ForegroundColor Gray
Write-Host "  ModulesPath: $ModulesPath" -ForegroundColor Gray
Write-Host "  CoreModulesPath: $CoreModulesPath" -ForegroundColor Gray

$CoreModules = @(
    'ConfigManager',
    'MenuSystem'
)

foreach ($moduleName in $CoreModules) {
    $modulePath = Join-Path $CoreModulesPath "$moduleName.psm1"
    if (Test-Path $modulePath) {
        try {
            Import-Module $modulePath -Force -ErrorAction Stop
            Write-Host "  ✓ Loaded: $moduleName" -ForegroundColor Green
        }
        catch {
            Write-Error "Failed to load module $moduleName`: $_"
            exit 1
        }
    } else {
        Write-Error "Module not found: $modulePath"
        exit 1
    }
}

#endregion

#region Configuration Loading

Write-Host "`nInitializing configuration..." -ForegroundColor Yellow

try {
    Initialize-ConfigSystem -ConfigRootPath $ConfigPath
    $MainConfig = Get-MainConfiguration
    $null = Get-LoggingConfiguration  # Load logging config but don't store unused variable
    
    Write-Host "  ✓ Main configuration loaded" -ForegroundColor Green
    Write-Host "  ✓ Logging configuration loaded" -ForegroundColor Green
}
catch {
    Write-Error "Failed to initialize configuration: $_"
    exit 1
}

# Load app configurations
try {
    $BloatwareLists = Get-BloatwareConfiguration
    $EssentialApps = Get-EssentialAppsConfiguration
    
    $totalBloatware = ($BloatwareLists.Values | Measure-Object -Sum { $_.Count }).Sum
    $totalEssentialApps = ($EssentialApps.Values | Measure-Object -Sum { $_.Count }).Sum
    
    Write-Host "  ✓ Bloatware lists: $($BloatwareLists.Keys.Count) categories, $totalBloatware total entries" -ForegroundColor Green
    Write-Host "  ✓ Essential apps: $($EssentialApps.Keys.Count) categories, $totalEssentialApps total entries" -ForegroundColor Green
}
catch {
    Write-Error "Failed to load app configurations: $_"
    exit 1
}

#endregion

#region Task Definitions

Write-Host "`nRegistering maintenance tasks..." -ForegroundColor Yellow

# Define available maintenance tasks
$MaintenanceTasks = @(
    @{
        Name = 'SystemInventory'
        Description = 'Collect comprehensive system information and generate inventory reports'
        ModulePath = Join-Path $ModulesPath 'type1\SystemInventory.psm1'
        Function = 'Get-SystemInventory'
        Type = 'Type1'
        Category = 'Inventory'
    },
    @{
        Name = 'BloatwareDetection'
        Description = 'Scan for bloatware applications and system components'
        ModulePath = Join-Path $ModulesPath 'type1\BloatwareDetection.psm1'
        Function = 'Find-InstalledBloatware'
        Type = 'Type1'
        Category = 'Detection'
    },
    @{
        Name = 'BloatwareRemoval'
        Description = 'Remove detected bloatware applications using multiple methods'
        ModulePath = Join-Path $ModulesPath 'type2\BloatwareRemoval.psm1'
        Function = 'Remove-DetectedBloatware'
        Type = 'Type2'
        Category = 'Cleanup'
    },
    @{
        Name = 'EssentialApps'
        Description = 'Install essential applications from curated lists'
        ModulePath = Join-Path $ModulesPath 'type2\EssentialApps.psm1'
        Function = 'Install-EssentialApplications'
        Type = 'Type2'
        Category = 'Installation'
    },
    @{
        Name = 'WindowsUpdates'
        Description = 'Check for and install Windows updates'
        ModulePath = Join-Path $ModulesPath 'type2\WindowsUpdates.psm1'
        Function = 'Install-WindowsUpdates'
        Type = 'Type2'
        Category = 'Updates'
    },
    @{
        Name = 'TelemetryDisable'
        Description = 'Disable Windows telemetry and privacy-invasive features'
        ModulePath = Join-Path $ModulesPath 'type2\TelemetryDisable.psm1'
        Function = 'Disable-TelemetryFeatures'
        Type = 'Type2'
        Category = 'Privacy'
    },
    @{
        Name = 'SecurityAudit'
        Description = 'Perform security audit and apply hardening recommendations'
        ModulePath = Join-Path $ModulesPath 'type1\SecurityAudit.psm1'
        Function = 'Start-SecurityAudit'
        Type = 'Type1'
        Category = 'Security'
    },
    @{
        Name = 'SystemOptimization'
        Description = 'Apply performance optimizations and cleanup temporary files'
        ModulePath = Join-Path $ModulesPath 'type2\SystemOptimization.psm1'
        Function = 'Optimize-SystemPerformance'
        Type = 'Type2'
        Category = 'Optimization'
    },
    @{
        Name = 'ReportGeneration'
        Description = 'Generate comprehensive HTML and text reports of all operations'
        ModulePath = Join-Path $ModulesPath 'type1\ReportGeneration.psm1'
        Function = 'Generate-MaintenanceReport'
        Type = 'Type1'
        Category = 'Reporting'
    }
)

# Filter tasks based on configuration
$AvailableTasks = @()
foreach ($task in $MaintenanceTasks) {
    $skipProperty = "skip$($task.Name)"
    if ($MainConfig.modules.PSObject.Properties.Name -contains $skipProperty) {
        if (-not $MainConfig.modules.$skipProperty) {
            $AvailableTasks += $task
        } else {
            Write-Host "  ⊘ Skipped: $($task.Name) (disabled in configuration)" -ForegroundColor DarkGray
        }
    } else {
        $AvailableTasks += $task
    }
}

Write-Host "  ✓ Registered $($AvailableTasks.Count) available tasks" -ForegroundColor Green

#endregion

#region Execution Mode Selection

$ExecutionParams = @{
    Mode = 'Execute'
    DryRun = $false
    SelectedTasks = $AvailableTasks
}

if (-not $NonInteractive) {
    Write-Host "`nStarting interactive mode..." -ForegroundColor Yellow
    
    # Configure menu system
    Set-MenuConfiguration -CountdownSeconds 20
    
    # Show hierarchical execution menu system (only if TaskNumbers not specified)
    if (-not $TaskNumbers) {
        Write-Host "`nPresenting execution options with 20-second countdowns..." -ForegroundColor Cyan
        $executionSelection = Show-HierarchicalExecutionMenu -AvailableTasks $AvailableTasks
        
        # Apply the selection results
        $ExecutionParams.DryRun = $executionSelection.DryRun
        $ExecutionParams.SelectedTasks = $executionSelection.Tasks
        
        Write-Host "`nExecution Configuration:" -ForegroundColor Yellow
        Write-Host "  Mode: " -NoNewline -ForegroundColor Gray
        if ($ExecutionParams.DryRun) {
            Write-Host "DRY-RUN SIMULATION" -ForegroundColor Blue
        } else {
            Write-Host "LIVE EXECUTION" -ForegroundColor Green
        }
        Write-Host "  Selected Tasks: $($ExecutionParams.SelectedTasks.Count)/$($AvailableTasks.Count)" -ForegroundColor Gray
        
    } else {
        # TaskNumbers parameter provided - use simplified selection
        Write-Host "`nTask numbers specified via parameter - using simplified selection..." -ForegroundColor Gray
        
        # Show simple execution mode menu for TaskNumbers scenario
        Write-Host "`nPlease select execution mode for specified tasks:" -ForegroundColor Yellow
        Write-Host "  [1] Normal Execution " -ForegroundColor Green -NoNewline
        Write-Host "[DEFAULT]" -ForegroundColor Cyan
        Write-Host "  [2] Dry-Run Execution" -ForegroundColor Blue
        
        $selection = Start-CountdownSelection -CountdownSeconds 20 -DefaultOption 1 -OptionsCount 2
        $ExecutionParams.DryRun = ($selection -eq 2)
        
        Write-Host ""
        if ($ExecutionParams.DryRun) {
            Write-Host "✓ Selected: Dry-Run Execution for specified tasks" -ForegroundColor Blue
        } else {
            Write-Host "✓ Selected: Normal Execution for specified tasks" -ForegroundColor Green
        }
    }
} else {
    Write-Host "`nNon-interactive mode enabled" -ForegroundColor Yellow
    if ($DryRun) {
        $ExecutionParams.DryRun = $true
        Write-Host "  ✓ Dry-run mode enabled" -ForegroundColor Blue
    }
}

# Handle TaskNumbers parameter
if ($TaskNumbers) {
    try {
        $taskNumbersArray = $TaskNumbers -split ',' | ForEach-Object { [int]$_.Trim() }
        $selectedTasks = @()
        
        foreach ($taskNum in $taskNumbersArray) {
            if ($taskNum -ge 1 -and $taskNum -le $AvailableTasks.Count) {
                $selectedTasks += $AvailableTasks[$taskNum - 1]
            } else {
                Write-Warning "Invalid task number: $taskNum (valid range: 1-$($AvailableTasks.Count))"
            }
        }
        
        $ExecutionParams.SelectedTasks = $selectedTasks
        Write-Host "  ✓ Task selection: $($taskNumbersArray -join ', ')" -ForegroundColor Green
    }
    catch {
        Write-Error "Invalid TaskNumbers parameter format: $TaskNumbers"
        exit 1
    }
}

#endregion

#region Task Execution

Write-Host "`nStarting maintenance execution..." -ForegroundColor Yellow

$executionMode = if ($ExecutionParams.DryRun) { "DRY-RUN" } else { "LIVE" }
Write-Host "Execution Mode: $executionMode" -ForegroundColor $(if ($ExecutionParams.DryRun) { 'Blue' } else { 'Green' })
Write-Host "Selected Tasks: $($ExecutionParams.SelectedTasks.Count)/$($AvailableTasks.Count)" -ForegroundColor Cyan

if ($ExecutionParams.SelectedTasks.Count -eq 0) {
    Write-Warning "No tasks selected for execution"
    exit 0
}

# Show final confirmation for system modification tasks
$type2Tasks = $ExecutionParams.SelectedTasks | Where-Object { $_.Type -eq 'Type2' }
if ($type2Tasks.Count -gt 0 -and -not $ExecutionParams.DryRun -and -not $NonInteractive) {
    $confirmMessage = "About to execute $($type2Tasks.Count) system modification task(s). Continue?"
    $confirmed = Show-ConfirmationDialog -Message $confirmMessage -CountdownSeconds 10
    if (-not $confirmed) {
        Write-Host "Operation cancelled by user" -ForegroundColor Yellow
        exit 0
    }
}

# Initialize execution tracking
$TaskResults = @()
$StartTime = Get-Date

Write-Host "`nExecuting tasks..." -ForegroundColor Yellow
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan

for ($i = 0; $i -lt $ExecutionParams.SelectedTasks.Count; $i++) {
    $task = $ExecutionParams.SelectedTasks[$i]
    $taskNumber = $i + 1
    $totalTasks = $ExecutionParams.SelectedTasks.Count
    
    Write-Host ""
    Write-Host "[$taskNumber/$totalTasks] $($task.Name)" -ForegroundColor White -BackgroundColor DarkBlue
    Write-Host "Description: $($task.Description)" -ForegroundColor Gray
    Write-Host "Type: $($task.Type) | Category: $($task.Category)" -ForegroundColor Gray
    
    if ($ExecutionParams.DryRun) {
        Write-Host "Mode: DRY-RUN (simulation)" -ForegroundColor Blue
    }
    
    $taskStartTime = Get-Date
    $taskResult = @{
        TaskName = $task.Name
        Description = $task.Description
        Type = $task.Type
        Category = $task.Category
        StartTime = $taskStartTime
        Success = $false
        DryRun = $ExecutionParams.DryRun
        Output = ''
        Error = $null
        Duration = $null
    }
    
    try {
        # Check if module exists and load it
        if (Test-Path $task.ModulePath) {
            Import-Module $task.ModulePath -Force -ErrorAction Stop
            Write-Host "  ✓ Module loaded: $($task.ModulePath | Split-Path -Leaf)" -ForegroundColor Green
        } else {
            throw "Module not found: $($task.ModulePath)"
        }
        
        # Execute the task function
        if ($ExecutionParams.DryRun) {
            Write-Host "  ▶ Simulating: $($task.Function)" -ForegroundColor Blue
            # In dry-run mode, we could call with -WhatIf parameter if supported
            $result = "DRY-RUN: Task would be executed"
        } else {
            Write-Host "  ▶ Executing: $($task.Function)" -ForegroundColor Green
            $result = & $task.Function
        }
        
        $taskResult.Success = $true
        $taskResult.Output = $result
        Write-Host "  ✓ Completed successfully" -ForegroundColor Green
        
    }
    catch {
        $taskResult.Success = $false
        $taskResult.Error = $_.Exception.Message
        Write-Host "  ✗ Failed: $($_.Exception.Message)" -ForegroundColor Red
    }
    finally {
        $taskResult.Duration = ((Get-Date) - $taskStartTime).TotalSeconds
        $TaskResults += $taskResult
        
        Write-Host "  Duration: $([math]::Round($taskResult.Duration, 2)) seconds" -ForegroundColor Gray
    }
}

#endregion

#region Execution Summary

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "    EXECUTION SUMMARY" -ForegroundColor White -BackgroundColor DarkBlue  
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan

$totalDuration = ((Get-Date) - $StartTime).TotalSeconds
$successfulTasks = ($TaskResults | Where-Object { $_.Success }).Count
$failedTasks = ($TaskResults | Where-Object { -not $_.Success }).Count

Write-Host ""
Write-Host "Execution Mode: " -NoNewline -ForegroundColor Gray
Write-Host $executionMode -ForegroundColor $(if ($ExecutionParams.DryRun) { 'Blue' } else { 'Green' })
Write-Host "Total Duration: " -NoNewline -ForegroundColor Gray  
Write-Host "$([math]::Round($totalDuration, 2)) seconds" -ForegroundColor White
Write-Host "Tasks Executed: " -NoNewline -ForegroundColor Gray
Write-Host "$($TaskResults.Count)" -ForegroundColor White
Write-Host "Successful: " -NoNewline -ForegroundColor Gray
Write-Host "$successfulTasks" -ForegroundColor Green
Write-Host "Failed: " -NoNewline -ForegroundColor Gray
Write-Host "$failedTasks" -ForegroundColor $(if ($failedTasks -gt 0) { 'Red' } else { 'Green' })

Write-Host ""
Write-Host "Task Results:" -ForegroundColor Yellow
Write-Host "─────────────────────────────────────────────────────────────" -ForegroundColor DarkCyan

foreach ($result in $TaskResults) {
    $status = if ($result.Success) { '✓' } else { '✗' }
    $statusColor = if ($result.Success) { 'Green' } else { 'Red' }
    $durationText = "$([math]::Round($result.Duration, 2))s"
    
    Write-Host "  $status " -NoNewline -ForegroundColor $statusColor
    Write-Host "$($result.TaskName)" -NoNewline -ForegroundColor White
    Write-Host " ($durationText)" -ForegroundColor Gray
    
    if (-not $result.Success -and $result.Error) {
        Write-Host "    Error: $($result.Error)" -ForegroundColor Red
    }
}

# Save execution results
$executionSummary = @{
    ExecutionMode = $executionMode
    StartTime = $StartTime
    EndTime = Get-Date
    TotalDuration = $totalDuration
    TasksExecuted = $TaskResults.Count
    SuccessfulTasks = $successfulTasks
    FailedTasks = $failedTasks
    TaskResults = $TaskResults
    Configuration = $MainConfig
}

$summaryPath = Join-Path $ReportsDir "execution-summary-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
$executionSummary | ConvertTo-Json -Depth 10 | Out-File -FilePath $summaryPath -Encoding UTF8

Write-Host ""
Write-Host "Execution summary saved to: $summaryPath" -ForegroundColor Gray

if ($failedTasks -gt 0) {
    Write-Host ""
    Write-Host "⚠️  Some tasks failed. Check the logs for detailed error information." -ForegroundColor Yellow
    exit 1
} else {
    Write-Host ""
    Write-Host "🎉 All tasks completed successfully!" -ForegroundColor Green
    exit 0
}

#endregion