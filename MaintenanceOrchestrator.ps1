# Note: PowerShell 7+ verification is handled by the launcher (script.bat).
# The launcher ensures a compatible pwsh.exe is available before invoking this orchestrator.
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
    [ValidateScript({ [string]::IsNullOrEmpty($_) -or (Test-Path (Split-Path $_ -Parent)) })]
    [string]$LogFilePath,
    
    [ValidateScript({ [string]::IsNullOrEmpty($_) -or (Test-Path $_ -PathType Container) })]
    [string]$ConfigPath,
    
    [switch]$NonInteractive,
    [switch]$DryRun,
    
    [ValidatePattern('^(\d+)(,\d+)*$|^$')]
    [string]$TaskNumbers
)

#region Script Initialization

# Script path detection and environment setup
$ScriptRoot = $PSScriptRoot
if (-not $ScriptRoot) {
    $ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
}

$WorkingDirectory = if ($env:WORKING_DIRECTORY) { $env:WORKING_DIRECTORY } else { $ScriptRoot }

Write-Host "Windows Maintenance Automation - Central Orchestrator v2.0.0" -ForegroundColor Cyan
Write-Host "Working Directory: $WorkingDirectory" -ForegroundColor Gray
Write-Host "Script Root: $ScriptRoot" -ForegroundColor Gray

# Detect configuration path (always relative to script location)
if (-not $ConfigPath) {
    $ConfigPath = Join-Path $ScriptRoot 'config'
    if (-not (Test-Path $ConfigPath)) {
        # Fallback to working directory if set by batch script
        $fallbackConfigPath = Join-Path $WorkingDirectory 'config'
        if (Test-Path $fallbackConfigPath) {
            $ConfigPath = $fallbackConfigPath
        }
    }
}

if (-not (Test-Path $ConfigPath)) {
    throw "Configuration directory not found. Expected at: $ConfigPath or $(Join-Path $WorkingDirectory 'config')"
}

Write-Host "Configuration Path: $ConfigPath" -ForegroundColor Gray

# Initialize session management
$Global:MaintenanceSessionId = [guid]::NewGuid().ToString()
$Global:MaintenanceSessionTimestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$Global:MaintenanceSessionStartTime = Get-Date

Write-Host "Session ID: $Global:MaintenanceSessionId" -ForegroundColor Gray
Write-Host "Session Timestamp: $Global:MaintenanceSessionTimestamp" -ForegroundColor Gray

# Set session environment variables for modules to access
$env:MAINTENANCE_SESSION_ID = $Global:MaintenanceSessionId
$env:MAINTENANCE_SESSION_TIMESTAMP = $Global:MaintenanceSessionTimestamp

# Set up temp directories (always relative to script location, not working directory)
$TempRoot = Join-Path $ScriptRoot 'temp_files'
$ReportsDir = Join-Path $TempRoot 'reports'
$LogsDir = Join-Path $TempRoot 'logs'
$InventoryDir = Join-Path $TempRoot 'inventory'

@($TempRoot, $ReportsDir, $LogsDir, $InventoryDir) | ForEach-Object {
    if (-not (Test-Path $_)) {
        New-Item -Path $_ -ItemType Directory -Force | Out-Null
        Write-Host "Created directory: $_" -ForegroundColor Green
    }
}

Write-Host "Temp Root Directory: $TempRoot" -ForegroundColor Gray

# Initialize Session-based Cache Management
$SessionStartTime = Get-Date
$CacheTimeoutMinutes = 5  # Cache inventory data for 5 minutes within same session
$UseInventoryCache = $false

# Check if recent inventory data exists and is within cache timeout
$recentInventory = Get-ChildItem -Path $InventoryDir -Filter "system-inventory-*.json" -ErrorAction SilentlyContinue |
Sort-Object LastWriteTime -Descending |
Select-Object -First 1

if ($recentInventory) {
    $cacheAge = (Get-Date) - $recentInventory.LastWriteTime
    if ($cacheAge.TotalMinutes -le $CacheTimeoutMinutes) {
        $UseInventoryCache = $true
        Write-Host "  🗂️  Recent inventory data found (age: $([math]::Round($cacheAge.TotalMinutes, 1)) minutes) - caching enabled" -ForegroundColor Green
    }
    else {
        Write-Host "  🔄 Inventory data is $([math]::Round($cacheAge.TotalMinutes, 1)) minutes old - will refresh" -ForegroundColor Yellow
    }
}
else {
    Write-Host "  📋 No cached inventory data found - will collect fresh data" -ForegroundColor Cyan
}

# Set up log file
if (-not $LogFilePath) {
    $LogFilePath = if ($env:SCRIPT_LOG_FILE) {
        $env:SCRIPT_LOG_FILE
    }
    else {
        Join-Path $ScriptRoot 'maintenance.log'
    }
}

Write-Host "Log File: $LogFilePath" -ForegroundColor Gray

#endregion

#region Module Loading

Write-Host "`nLoading modules..." -ForegroundColor Yellow

# Import core modules (always relative to script location)
$ModulesPath = Join-Path $ScriptRoot 'modules'
if (-not (Test-Path $ModulesPath)) {
    # Fallback to working directory if set by batch script
    $fallbackModulesPath = Join-Path $WorkingDirectory 'modules'
    if (Test-Path $fallbackModulesPath) {
        $ModulesPath = $fallbackModulesPath
    }
}
$CoreModulesPath = Join-Path $ModulesPath 'core'

Write-Host "Modules Path: $ModulesPath" -ForegroundColor Gray

$CoreModules = @(
    'ConfigManager',
    'LoggingManager',
    'FileOrganizationManager',
    'MenuSystem'
)

foreach ($moduleName in $CoreModules) {
    $modulePath = Join-Path $CoreModulesPath "$moduleName.psm1"
    try {
        if (-not (Test-Path $modulePath)) {
            throw "Module file not found: $modulePath"
        }

        # Import PowerShell script module directly (no manifest validation needed for .psm1 files)
        Import-Module $modulePath -Force -ErrorAction Stop
        Write-Host "  ✓ Loaded: $moduleName" -ForegroundColor Green
        
        # Verify module loaded successfully
        $loadedModule = Get-Module -Name $moduleName -ErrorAction SilentlyContinue
        if (-not $loadedModule) {
            throw "Module $moduleName failed to load properly - not found in loaded modules"
        }
    }
    catch [System.UnauthorizedAccessException] {
        Write-Error "Access denied loading module $moduleName. Ensure you have administrator privileges and the file is not blocked."
        Write-Host "  ℹ️ Try running: Unblock-File '$modulePath'" -ForegroundColor Cyan
        exit 1
    }
    catch [System.Security.SecurityException] {
        Write-Error "Security error loading module $moduleName. Check execution policy and file permissions."
        Write-Host "  ℹ️ Current execution policy: $(Get-ExecutionPolicy)" -ForegroundColor Cyan
        exit 1
    }
    catch [System.IO.FileNotFoundException] {
        Write-Error "Module file not found: $modulePath"
        Write-Host "  ℹ️ Ensure all module files are present in the modules/core directory" -ForegroundColor Cyan
        exit 1
    }
    catch {
        Write-Error "Failed to load core module $moduleName`: $_"
        Write-Host "  ℹ️ Error Type: $($_.Exception.GetType().Name)" -ForegroundColor Cyan
        Write-Host "  ℹ️ Error Details: $($_.Exception.Message)" -ForegroundColor Cyan
        if ($_.ScriptStackTrace) {
            Write-Host "  ℹ️ Stack Trace: $($_.ScriptStackTrace)" -ForegroundColor Gray
        }
        exit 1
    }
}

#endregion

#region Configuration Loading

Write-Host "`nInitializing configuration..." -ForegroundColor Yellow

try {
    # Validate configuration directory structure
    $requiredConfigFiles = @('main-config.json', 'logging-config.json')
    foreach ($configFile in $requiredConfigFiles) {
        $configFilePath = Join-Path $ConfigPath $configFile
        if (-not (Test-Path $configFilePath)) {
            throw "Required configuration file not found: $configFilePath"
        }
        
        # Validate JSON syntax
        try {
            $null = Get-Content $configFilePath | ConvertFrom-Json -ErrorAction Stop
        }
        catch {
            throw "Invalid JSON syntax in configuration file $configFile`: $($_.Exception.Message)"
        }
    }
    
    # Initialize configuration system with error handling
    try {
        Initialize-ConfigSystem -ConfigRootPath $ConfigPath -ErrorAction Stop
        Write-Host "  ✓ Configuration system initialized" -ForegroundColor Green
    }
    catch {
        throw "Failed to initialize configuration system: $($_.Exception.Message)"
    }
    
    # Load configurations with validation
    try {
        $MainConfig = Get-MainConfiguration -ErrorAction Stop
        if (-not $MainConfig) {
            throw "Main configuration is null or empty"
        }
        Write-Host "  ✓ Main configuration loaded" -ForegroundColor Green
    }
    catch {
        throw "Failed to load main configuration: $($_.Exception.Message)"
    }
    
    try {
        $LoggingConfig = Get-LoggingConfiguration -ErrorAction Stop
        if (-not $LoggingConfig) {
            throw "Logging configuration is null or empty"
        }
        Write-Host "  ✓ Logging configuration loaded" -ForegroundColor Green
    }
    catch {
        throw "Failed to load logging configuration: $($_.Exception.Message)"
    }

    # Initialize file organization system first (required by logging system)
    try {
        $fileOrgResult = Initialize-FileOrganization -BaseDir $ScriptRoot -SessionId $Global:MaintenanceSessionTimestamp -ErrorAction Stop
        if ($fileOrgResult) {
            Write-Host "  ✓ File organization system initialized" -ForegroundColor Green
        }
        else {
            throw "File organization initialization returned false"
        }
    }
    catch {
        Write-Host "  ⚠️ File organization system failed to initialize: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host "  ℹ️ Continuing with basic file operations - some features may be limited" -ForegroundColor Gray
        # Don't exit here as this is not critical for basic operation
    }

    # Initialize logging system (depends on file organization)
    try {
        $loggingInitResult = Initialize-LoggingSystem -LoggingConfig $LoggingConfig -BaseLogPath $LogsDir -ErrorAction Stop
        if ($loggingInitResult) {
            Write-Host "  ✓ Logging system initialized" -ForegroundColor Green
            # LoggingManager functions are now available
        }
        else {
            throw "Logging system initialization returned false"
        }
    }
    catch {
        Write-Host "  ⚠️ Logging system failed to initialize: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host "  ℹ️ Continuing without enhanced logging - basic console output only" -ForegroundColor Gray
    }
    
    # Ensure Write-LogEntry is always available (fallback if LoggingManager failed)
    if (-not (Get-Command -Name 'Write-LogEntry' -ErrorAction SilentlyContinue)) {
        function Write-LogEntry {
            param($Level, $Component, $Message, $Data)
            Write-Host "[$Level] [$Component] $Message" -ForegroundColor Gray
        }
    }
}
catch [System.IO.DirectoryNotFoundException] {
    Write-Error "Configuration directory not found: $ConfigPath"
    Write-Host "  ℹ️ Ensure the 'config' directory exists and contains required configuration files" -ForegroundColor Cyan
    exit 1
}
catch [System.IO.FileNotFoundException] {
    Write-Error "Required configuration file not found: $($_.Exception.Message)"
    Write-Host "  ℹ️ Ensure all required configuration files are present in: $ConfigPath" -ForegroundColor Cyan
    exit 1
}
catch [System.Management.Automation.RuntimeException] {
    Write-Error "Configuration system error: $($_.Exception.Message)"
    Write-Host "  ℹ️ Check configuration file syntax and module dependencies" -ForegroundColor Cyan
    exit 1
}
catch {
    Write-Error "Failed to initialize configuration: $($_.Exception.Message)"
    Write-Host "  ℹ️ Error Type: $($_.Exception.GetType().Name)" -ForegroundColor Cyan
    Write-Host "  ℹ️ This may indicate missing dependencies or corrupted configuration files" -ForegroundColor Cyan
    exit 1
}

# Load app configurations with comprehensive error handling
try {
    Write-Host "`nLoading application configurations..." -ForegroundColor Yellow
    
    try {
        $BloatwareLists = Get-BloatwareConfiguration -ErrorAction Stop
        if (-not $BloatwareLists) {
            Write-Warning "Bloatware configuration is empty or null - bloatware removal tasks may be limited"
        }
        else {
            Write-Host "  ✓ Bloatware configuration loaded" -ForegroundColor Green
        }
    }
    catch {
        Write-Host "  ⚠️ Failed to load bloatware configuration: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host "  ℹ️ Bloatware removal tasks will be skipped" -ForegroundColor Gray
        $BloatwareLists = @()
    }
    
    try {
        $EssentialApps = Get-EssentialAppsConfiguration -ErrorAction Stop
        if (-not $EssentialApps) {
            Write-Warning "Essential apps configuration is empty or null - app installation tasks may be limited"
        }
        else {
            Write-Host "  ✓ Essential apps configuration loaded" -ForegroundColor Green
        }
    }
    catch {
        Write-Host "  ⚠️ Failed to load essential apps configuration: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host "  ℹ️ Essential app installation tasks will be skipped" -ForegroundColor Gray
        $EssentialApps = @()
    }

    # Calculate configuration statistics with error handling
    try {
        $totalBloatware = if ($BloatwareLists -and $BloatwareLists.ContainsKey('all')) { $BloatwareLists['all'].Count } else { 0 }
        $totalEssentialApps = if ($EssentialApps -and $EssentialApps.ContainsKey('all')) { $EssentialApps['all'].Count } else { 0 }

        Write-Host "  ✓ Bloatware list: $totalBloatware total entries" -ForegroundColor Green
        Write-Host "  ✓ Essential apps: $totalEssentialApps total entries" -ForegroundColor Green
    }
    catch {
        Write-Host "  ⚠️ Error calculating configuration statistics: $($_.Exception.Message)" -ForegroundColor Yellow
        $totalBloatware = 0
        $totalEssentialApps = 0
    }
}
catch [System.IO.FileNotFoundException] {
    Write-Error "App configuration file not found: $($_.Exception.Message)"
    Write-Host "  ℹ️ Ensure bloatware-list.json and essential-apps.json exist in: $ConfigPath" -ForegroundColor Cyan
    exit 1
}
catch [System.ArgumentException] {
    Write-Error "Invalid app configuration format: $($_.Exception.Message)"
    Write-Host "  ℹ️ Check JSON syntax and structure in app configuration files" -ForegroundColor Cyan
    exit 1
}
catch {
    Write-Error "Failed to load app configurations: $($_.Exception.Message)"
    Write-Host "  ℹ️ Error Type: $($_.Exception.GetType().Name)" -ForegroundColor Cyan
    Write-Host "  ℹ️ Check app configuration files in: $ConfigPath" -ForegroundColor Cyan
    exit 1
}

#endregion

#region Session Management Functions

<#
.SYNOPSIS
    Gets a standardized filename using the current session timestamp
.DESCRIPTION
    Provides a consistent file naming pattern across all modules for the current maintenance session
.PARAMETER BaseName
    The base name for the file (without timestamp or extension)
.PARAMETER Extension
    The file extension (optional)
.EXAMPLE
    Get-SessionFileName -BaseName "maintenance-report" -Extension "html"
    Returns: maintenance-report-20241012-110054.html
#>
function Get-SessionFileName {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BaseName,
        [Parameter()]
        [string]$Extension
    )
    
    $fileName = "$BaseName-$Global:MaintenanceSessionTimestamp"
    if ($Extension) {
        $fileName += ".$Extension"
    }
    return $fileName
}

# Export session functions globally so modules can access them
$Global:GetSessionFileName = ${function:Get-SessionFileName}

#endregion

#region Helper Functions

function Invoke-TaskWithParameters {
    param(
        [string]$TaskName,
        [string]$FunctionName,
        [switch]$DryRun
    )

    # Prepare task-specific parameters
    switch ($TaskName) {
        'ReportGeneration' {
            # Pass path without extension - ReportGeneration module will add .html, .txt, .json
            # Use session timestamp for consistent naming
            $reportPath = Join-Path $TempRoot "reports\maintenance-report-$Global:MaintenanceSessionTimestamp"
            $params = @{
                OutputPath      = $reportPath
                SystemInventory = $null  # Will be populated by the function if needed
                TaskResults     = $TaskResults
                Configuration   = $MainConfig
            }
            return & $FunctionName @params
        }
        'EssentialApps' {
            $params = @{}
            if ($DryRun) { $params.DryRun = $true }
            return & $FunctionName @params
        }
        'BloatwareRemoval' {
            $params = @{}
            if ($DryRun) { $params.DryRun = $true }
            if ($UseInventoryCache) { $params.UseCache = $true }
            return & $FunctionName @params
        }
        'TelemetryDisable' {
            $params = @{}
            if ($DryRun) { $params.DryRun = $true }
            return & $FunctionName @params
        }
        'BloatwareDetection' {
            # Call with intelligent caching
            $params = @{}
            if ($UseInventoryCache) { $params.UseCache = $true }
            return & $FunctionName @params
        }
        'SystemInventory' {
            # Call with detailed information and caching
            $params = @{ IncludeDetailed = $true }
            if ($UseInventoryCache) { $params.UseCache = $true }
            return & $FunctionName @params
        }
        default {
            # For other tasks, call without parameters
            return & $FunctionName
        }
    }
}

#endregion

#region Task Definitions

Write-Host "`nRegistering maintenance tasks..." -ForegroundColor Yellow

# Define available maintenance tasks
$MaintenanceTasks = @(
    @{
        Name        = 'SystemInventory'
        Description = 'Collect comprehensive system information and generate inventory reports'
        ModulePath  = Join-Path $ModulesPath 'type1\SystemInventory.psm1'
        Function    = 'Get-SystemInventory'
        Type        = 'Type1'
        Category    = 'Inventory'
    },
    @{
        Name        = 'BloatwareDetection'
        Description = 'Scan for bloatware applications and system components'
        ModulePath  = Join-Path $ModulesPath 'type1\BloatwareDetection.psm1'
        Function    = 'Find-InstalledBloatware'
        Type        = 'Type1'
        Category    = 'Detection'
    },
    @{
        Name        = 'BloatwareRemoval'
        Description = 'Remove detected bloatware applications using multiple methods'
        ModulePath  = Join-Path $ModulesPath 'type2\BloatwareRemoval.psm1'
        Function    = 'Remove-DetectedBloatware'
        Type        = 'Type2'
        Category    = 'Cleanup'
    },
    @{
        Name        = 'EssentialApps'
        Description = 'Install essential applications from curated lists'
        ModulePath  = Join-Path $ModulesPath 'type2\EssentialApps.psm1'
        Function    = 'Install-EssentialApplication'
        Type        = 'Type2'
        Category    = 'Installation'
    },
    @{
        Name        = 'WindowsUpdates'
        Description = 'Check for and install Windows updates'
        ModulePath  = Join-Path $ModulesPath 'type2\WindowsUpdates.psm1'
        Function    = 'Install-WindowsUpdate'
        Type        = 'Type2'
        Category    = 'Updates'
    },
    @{
        Name        = 'TelemetryDisable'
        Description = 'Disable Windows telemetry and privacy-invasive features'
        ModulePath  = Join-Path $ModulesPath 'type2\TelemetryDisable.psm1'
        Function    = 'Disable-WindowsTelemetry'
        Type        = 'Type2'
        Category    = 'Privacy'
    },
    @{
        Name        = 'SecurityAudit'
        Description = 'Perform security audit and apply hardening recommendations'
        ModulePath  = Join-Path $ModulesPath 'type1\SecurityAudit.psm1'
        Function    = 'Start-SecurityAudit'
        Type        = 'Type1'
        Category    = 'Security'
    },
    @{
        Name        = 'SystemOptimization'
        Description = 'Apply performance optimizations and cleanup temporary files'
        ModulePath  = Join-Path $ModulesPath 'type2\SystemOptimization.psm1'
        Function    = 'Optimize-SystemPerformance'
        Type        = 'Type2'
        Category    = 'Optimization'
    },
    @{
        Name        = 'ReportGeneration'
        Description = 'Generate comprehensive HTML and text reports of all operations'
        ModulePath  = Join-Path $ModulesPath 'type1\ReportGeneration.psm1'
        Function    = 'New-MaintenanceReport'
        Type        = 'Type1'
        Category    = 'Reporting'
    }
)

# Filter tasks based on configuration
$AvailableTasks = @()
foreach ($task in $MaintenanceTasks) {
    $skipProperty = "skip$($task.Name)"
    if ($MainConfig.modules.PSObject.Properties.Name -contains $skipProperty) {
        if (-not $MainConfig.modules.$skipProperty) {
            $AvailableTasks += $task
        }
        else {
            Write-Host "  ⊘ Skipped: $($task.Name) (disabled in configuration)" -ForegroundColor DarkGray
        }
    }
    else {
        $AvailableTasks += $task
    }
}

Write-Host "  ✓ Registered $($AvailableTasks.Count) available tasks" -ForegroundColor Green

#endregion

#region Execution Mode Selection

$ExecutionParams = @{
    Mode          = 'Execute'
    DryRun        = $false
    SelectedTasks = $AvailableTasks
}

if (-not $NonInteractive) {
    Write-Host "`nStarting interactive mode..." -ForegroundColor Yellow

    # Configure menu system
    Set-MenuConfiguration -CountdownSeconds $MainConfig.execution.countdownSeconds

    # Show main menu
    $mainSelection = Show-MainMenu -CountdownSeconds $MainConfig.execution.countdownSeconds
    $ExecutionParams.DryRun = $mainSelection.DryRun

    # Show task selection menu if not overridden by parameter
    if (-not $TaskNumbers) {
        $taskSelection = Show-TaskSelectionMenu -IsDryRun $ExecutionParams.DryRun -AvailableTasks $AvailableTasks
        $ExecutionParams.SelectedTasks = $taskSelection.Tasks
    }
}
else {
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
            }
            else {
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

# Log execution start
Write-LogEntry -Level 'INFO' -Component 'ORCHESTRATOR' -Message "Starting maintenance execution" -Data @{
    ExecutionMode      = $executionMode
    SelectedTasksCount = $ExecutionParams.SelectedTasks.Count
    TotalTasksCount    = $AvailableTasks.Count
    DryRun             = $ExecutionParams.DryRun
}

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
        TaskName    = $task.Name
        Description = $task.Description
        Type        = $task.Type
        Category    = $task.Category
        StartTime   = $taskStartTime
        Success     = $false
        DryRun      = $ExecutionParams.DryRun
        Output      = ''
        Error       = $null
        Duration    = $null
    }

    try {
        # Validate task properties
        if ([string]::IsNullOrEmpty($task.ModulePath)) {
            throw "Task configuration error: ModulePath is null or empty"
        }
        if ([string]::IsNullOrEmpty($task.Function)) {
            throw "Task configuration error: Function name is null or empty"
        }

        # Log task start
        Write-LogEntry -Level 'INFO' -Component 'ORCHESTRATOR' -Message "Starting task: $($task.Name)" -Data @{
            TaskType     = $task.Type
            TaskCategory = $task.Category
            ModulePath   = $task.ModulePath
            Function     = $task.Function
            DryRun       = $ExecutionParams.DryRun
        }

        # Check if module exists and load it with comprehensive error handling
        if (-not (Test-Path $task.ModulePath)) {
            throw "Module file not found: $($task.ModulePath)"
        }

        try {
            # Validate module syntax before import
            $null = [System.Management.Automation.PSParser]::Tokenize((Get-Content -Path $task.ModulePath -Raw), [ref]$null)
            
            Import-Module $task.ModulePath -Force -ErrorAction Stop
            Write-Host "  ✓ Module loaded: $($task.ModulePath | Split-Path -Leaf)" -ForegroundColor Green
            
            # Verify the target function exists in the loaded module
            $moduleName = [System.IO.Path]::GetFileNameWithoutExtension($task.ModulePath)
            $loadedModule = Get-Module -Name $moduleName -ErrorAction SilentlyContinue
            if (-not $loadedModule) {
                throw "Module $moduleName failed to load properly"
            }
            
            $availableFunctions = $loadedModule.ExportedFunctions.Keys
            if ($task.Function -notin $availableFunctions) {
                throw "Function '$($task.Function)' not found in module. Available functions: $($availableFunctions -join ', ')"
            }
        }
        catch [System.UnauthorizedAccessException] {
            throw "Access denied loading module: $($task.ModulePath). Check file permissions and ensure administrator privileges."
        }
        catch [System.Management.Automation.ParseException] {
            throw "Module syntax error in $($task.ModulePath): $($_.Exception.Message)"
        }
        catch {
            throw "Failed to load module $($task.ModulePath): $($_.Exception.Message)"
        }

        # Execute the task function with comprehensive error handling
        $result = $null
        try {
            if ($ExecutionParams.DryRun) {
                Write-Host "  ▶ Simulating: $($task.Function)" -ForegroundColor Blue
                # Try to call with -WhatIf if the function supports it
                $functionDef = Get-Command $task.Function -ErrorAction SilentlyContinue
                if ($functionDef -and $functionDef.Parameters.ContainsKey('WhatIf')) {
                    $result = & $task.Function -WhatIf
                }
                else {
                    $result = "DRY-RUN: Task would be executed (function does not support -WhatIf)"
                }
            }
            else {
                Write-Host "  ▶ Executing: $($task.Function)" -ForegroundColor Green
                $result = Invoke-TaskWithParameters -TaskName $task.Name -FunctionName $task.Function -DryRun:$ExecutionParams.DryRun
            }
        }
        catch [System.Management.Automation.CommandNotFoundException] {
            throw "Function '$($task.Function)' not found or not accessible"
        }
        catch [System.Management.Automation.ParameterBindingException] {
            throw "Parameter binding error for function '$($task.Function)': $($_.Exception.Message)"
        }
        catch [System.Security.SecurityException] {
            throw "Security error executing function '$($task.Function)': $($_.Exception.Message). Check execution policy and permissions."
        }
        catch [System.UnauthorizedAccessException] {
            throw "Access denied executing function '$($task.Function)': $($_.Exception.Message). Ensure administrator privileges."
        }
        catch {
            # Capture detailed error information for debugging
            $errorDetails = @{
                Message    = $_.Exception.Message
                Type       = $_.Exception.GetType().Name
                StackTrace = $_.ScriptStackTrace
                Function   = $task.Function
                Line       = $_.InvocationInfo.ScriptLineNumber
            }
            throw "Task execution failed: $($_.Exception.Message)"
        }

        $taskResult.Success = $true
        $taskResult.Output = $result
        Write-Host "  ✓ Completed successfully" -ForegroundColor Green

        # Log task success with detailed metrics
        Write-LogEntry -Level 'SUCCESS' -Component 'ORCHESTRATOR' -Message "Task completed successfully: $($task.Name)" -Data @{
            Duration   = ((Get-Date) - $taskStartTime).TotalSeconds
            OutputType = if ($null -ne $result) { $result.GetType().Name } else { 'null' }
            ResultSize = if ($null -ne $result -and $result -is [string]) { $result.Length } elseif ($null -ne $result -and $result -is [array]) { $result.Count } else { 0 }
        }

    }
    catch [System.OperationCanceledException] {
        $taskResult.Success = $false
        $taskResult.Error = "Task was cancelled by user or system"
        Write-Host "  ⏸️ Cancelled: Task was cancelled" -ForegroundColor Yellow
        
        Write-LogEntry -Level 'WARNING' -Component 'ORCHESTRATOR' -Message "Task cancelled: $($task.Name)" -Data @{
            Duration = ((Get-Date) - $taskStartTime).TotalSeconds
        }
    }
    catch [System.TimeoutException] {
        $taskResult.Success = $false
        $taskResult.Error = "Task timed out: $($_.Exception.Message)"
        Write-Host "  ⏱️ Timeout: $($_.Exception.Message)" -ForegroundColor Yellow
        
        Write-LogEntry -Level 'ERROR' -Component 'ORCHESTRATOR' -Message "Task timeout: $($task.Name)" -Data @{
            Error    = $_.Exception.Message
            Duration = ((Get-Date) - $taskStartTime).TotalSeconds
        }
    }
    catch [System.OutOfMemoryException] {
        $taskResult.Success = $false
        $taskResult.Error = "Out of memory error during task execution"
        Write-Host "  💾 Memory Error: Insufficient memory to complete task" -ForegroundColor Red
        
        Write-LogEntry -Level 'CRITICAL' -Component 'ORCHESTRATOR' -Message "Out of memory error: $($task.Name)" -Data @{
            Duration    = ((Get-Date) - $taskStartTime).TotalSeconds
            MemoryUsage = [System.GC]::GetTotalMemory($false)
        }
        
        # Force garbage collection
        [System.GC]::Collect()
        [System.GC]::WaitForPendingFinalizers()
    }
    catch {
        $taskResult.Success = $false
        $taskResult.Error = $_.Exception.Message
        Write-Host "  ✗ Failed: $($_.Exception.Message)" -ForegroundColor Red
        
        # Enhanced error logging with full context
        $errorContext = @{
            Error        = $_.Exception.Message
            ErrorType    = $_.Exception.GetType().Name
            Duration     = ((Get-Date) - $taskStartTime).TotalSeconds
            StackTrace   = $_.ScriptStackTrace
            TaskFunction = $task.Function
            ModulePath   = $task.ModulePath
            ScriptLine   = $_.InvocationInfo.ScriptLineNumber
            Command      = $_.InvocationInfo.MyCommand.Name
        }
        
        Write-LogEntry -Level 'ERROR' -Component 'ORCHESTRATOR' -Message "Task failed: $($task.Name)" -Data $errorContext
        
        # Additional troubleshooting information
        Write-Host "  ℹ️ Error Type: $($_.Exception.GetType().Name)" -ForegroundColor Gray
        if ($_.InvocationInfo.ScriptLineNumber) {
            Write-Host "  ℹ️ Error at line: $($_.InvocationInfo.ScriptLineNumber)" -ForegroundColor Gray
        }
        if ($_.ScriptStackTrace) {
            Write-Verbose "Full stack trace: $($_.ScriptStackTrace)"
        }
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
Write-Host "Task Duration: " -NoNewline -ForegroundColor Gray
Write-Host "$([math]::Round($totalDuration, 2)) seconds" -ForegroundColor White
Write-Host "Total Session: " -NoNewline -ForegroundColor Gray
Write-Host "$([math]::Round(((Get-Date) - $SessionStartTime).TotalSeconds, 2)) seconds" -ForegroundColor White
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
    ExecutionMode          = $executionMode
    SessionStartTime       = $SessionStartTime
    TaskExecutionStartTime = $StartTime
    EndTime                = Get-Date
    TotalDuration          = $totalDuration
    SessionDuration        = ((Get-Date) - $SessionStartTime).TotalSeconds
    TasksExecuted          = $TaskResults.Count
    SuccessfulTasks        = $successfulTasks
    FailedTasks            = $failedTasks
    TaskResults            = $TaskResults
    Configuration          = $MainConfig
}

$summaryPath = Join-Path $ReportsDir "execution-summary-$Global:MaintenanceSessionTimestamp.json"
$executionSummary | ConvertTo-Json -Depth 10 | Out-File -FilePath $summaryPath -Encoding UTF8

Write-Host ""
Write-Host "Execution summary saved to: $summaryPath" -ForegroundColor Gray

# Copy final reports to parent directory (same level as repo folder)
Write-Host ""
Write-Host "📄 Copying final reports to parent directory..." -ForegroundColor Yellow

# Get parent directory of the script root (one level up from repo folder)
$ParentDir = Split-Path $ScriptRoot -Parent
Write-Host "  📁 Target directory: $ParentDir" -ForegroundColor Gray

$finalReports = @()
$reportsToMove = @(
    @{ Pattern = "maintenance-report-$Global:MaintenanceSessionTimestamp.html"; Description = "HTML maintenance report" }
    @{ Pattern = "maintenance-report-$Global:MaintenanceSessionTimestamp.txt"; Description = "Text maintenance report" }
    @{ Pattern = "maintenance-log-$Global:MaintenanceSessionTimestamp.log"; Description = "Maintenance log file" }
)

foreach ($reportInfo in $reportsToMove) {
    $sourcePattern = $reportInfo.Pattern
    $description = $reportInfo.Description
    
    # Look for the file in temp directories
    $sourceFile = $null
    $searchPaths = @($ReportsDir, $LogsDir, $TempRoot)
    
    foreach ($searchPath in $searchPaths) {
        $potentialPath = Join-Path $searchPath $sourcePattern
        if (Test-Path $potentialPath) {
            $sourceFile = $potentialPath
            break
        }
    }
    
    if ($sourceFile) {
        $fileName = Split-Path $sourceFile -Leaf
        $destPath = Join-Path $ParentDir $fileName
        
        try {
            # Ensure parent directory is accessible
            if (-not (Test-Path $ParentDir)) {
                Write-Host "  ⚠️ Parent directory not accessible: $ParentDir" -ForegroundColor Yellow
                continue
            }
            
            Copy-Item -Path $sourceFile -Destination $destPath -Force
            Write-Host "  ✓ Copied $description to: $destPath" -ForegroundColor Green
            $finalReports += $destPath
        }
        catch {
            Write-Host "  ⚠️ Failed to copy $description`: $_" -ForegroundColor Yellow
        }
    }
}

if ($finalReports.Count -gt 0) {
    Write-Host ""
    Write-Host "📋 Final reports available in parent directory:" -ForegroundColor Cyan
    Write-Host "  📁 Location: $ParentDir" -ForegroundColor Gray
    foreach ($report in $finalReports) {
        Write-Host "  • $(Split-Path $report -Leaf)" -ForegroundColor White
    }
}

if ($failedTasks -gt 0) {
    Write-Host ""
    Write-Host "⚠️  Some tasks failed. Check the logs for detailed error information." -ForegroundColor Yellow
    exit 1
}
else {
    Write-Host ""
    Write-Host "🎉 All tasks completed successfully!" -ForegroundColor Green
    exit 0
}

#endregion
