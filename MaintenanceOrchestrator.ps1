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

Write-Information "Windows Maintenance Automation - Central Orchestrator v2.0.0" -InformationAction Continue
Write-Information "Working Directory: $WorkingDirectory" -InformationAction Continue
Write-Information "Script Root: $ScriptRoot" -InformationAction Continue

# 🎯 Initialize Global Path Discovery System
Write-Information "`n🔍 Initializing global path discovery..." -InformationAction Continue
$env:MAINTENANCE_PROJECT_ROOT = $ScriptRoot
$env:MAINTENANCE_CONFIG_ROOT = Join-Path $ScriptRoot 'config'
$env:MAINTENANCE_MODULES_ROOT = Join-Path $ScriptRoot 'modules'
$env:MAINTENANCE_TEMP_ROOT = Join-Path $ScriptRoot 'temp_files'
$env:MAINTENANCE_REPORTS_ROOT = $ScriptRoot

Write-Information "  ✅ Global environment variables set:" -InformationAction Continue
Write-Information "     🎯 PROJECT_ROOT: $env:MAINTENANCE_PROJECT_ROOT" -InformationAction Continue
Write-Information "     ⚙️  CONFIG_ROOT: $env:MAINTENANCE_CONFIG_ROOT" -InformationAction Continue
Write-Information "     🧩 MODULES_ROOT: $env:MAINTENANCE_MODULES_ROOT" -InformationAction Continue
Write-Information "     📂 TEMP_ROOT: $env:MAINTENANCE_TEMP_ROOT" -InformationAction Continue
Write-Information "     📊 REPORTS_ROOT: $env:MAINTENANCE_REPORTS_ROOT" -InformationAction Continue

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

Write-Information "Configuration Path: $ConfigPath" -InformationAction Continue

# Initialize session management
$Global:MaintenanceSessionId = [guid]::NewGuid().ToString()
$Global:MaintenanceSessionTimestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$Global:MaintenanceSessionStartTime = Get-Date

Write-Information "Session ID: $Global:MaintenanceSessionId" -InformationAction Continue
Write-Information "Session Timestamp: $Global:MaintenanceSessionTimestamp" -InformationAction Continue

# Set session environment variables for modules to access
$env:MAINTENANCE_SESSION_ID = $Global:MaintenanceSessionId
$env:MAINTENANCE_SESSION_TIMESTAMP = $Global:MaintenanceSessionTimestamp
# Note: MAINTENANCE_TEMP_ROOT already set above in global path discovery

# Set up temp directories (using global environment variables)
$TempRoot = $env:MAINTENANCE_TEMP_ROOT
$ReportsDir = Join-Path $TempRoot 'reports'
$LogsDir = Join-Path $TempRoot 'logs'
$MainLogFile = Join-Path $TempRoot 'maintenance.log'
$InventoryDir = Join-Path $TempRoot 'inventory'

@($TempRoot, $ReportsDir, $LogsDir, $InventoryDir) | ForEach-Object {
    if (-not (Test-Path $_)) {
        New-Item -Path $_ -ItemType Directory -Force | Out-Null
        Write-Information "Created directory: $_" -InformationAction Continue
    }
}

Write-Information "Temp Root Directory: $TempRoot" -InformationAction Continue

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
        Write-Information "  🗂️  Recent inventory data found (age: $([math]::Round($cacheAge.TotalMinutes, 1)) minutes) - caching enabled" -InformationAction Continue
    }
    else {
        Write-Information "  🔄 Inventory data is $([math]::Round($cacheAge.TotalMinutes, 1)) minutes old - will refresh" -InformationAction Continue
    }
}
else {
    Write-Information "  📋 No cached inventory data found - will collect fresh data" -InformationAction Continue
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

Write-Information "Log File: $LogFilePath" -InformationAction Continue

#endregion

#region Module Loading

Write-Information "`nLoading modules..." -InformationAction Continue

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

Write-Information "Modules Path: $ModulesPath" -InformationAction Continue

# v3.0 Architecture: Load only essential core modules
$CoreModules = @(
    'CoreInfrastructure',
    'UserInterface',
    'ReportGeneration'
)

# Type2 modules (self-contained with internal Type1 dependencies)
$Type2Modules = @(
    'BloatwareRemoval',
    'EssentialApps',
    'SystemOptimization',
    'TelemetryDisable',
    'WindowsUpdates'
)

$Type2ModulesPath = Join-Path $ModulesPath 'type2'

foreach ($moduleName in $CoreModules) {
    $modulePath = Join-Path $CoreModulesPath "$moduleName.psm1"
    try {
        if (-not (Test-Path $modulePath)) {
            throw "Module file not found: $modulePath"
        }

        # Import PowerShell script module directly (no manifest validation needed for .psm1 files)
        Import-Module $modulePath -Force -Global -ErrorAction Stop
        Write-Information "  ✓ Loaded: $moduleName" -InformationAction Continue
        
        # Verify module loaded successfully
        $loadedModule = Get-Module -Name $moduleName -ErrorAction SilentlyContinue
        if (-not $loadedModule) {
            throw "Module $moduleName failed to load properly - not found in loaded modules"
        }
    }
    catch [System.UnauthorizedAccessException] {
        Write-Error "Access denied loading module $moduleName. Ensure you have administrator privileges and the file is not blocked."
        Write-Information "  ℹ️ Try running: Unblock-File '$modulePath'" -InformationAction Continue
        exit 1
    }
    catch [System.Security.SecurityException] {
        Write-Error "Security error loading module $moduleName. Check execution policy and file permissions."
        Write-Information "  ℹ️ Current execution policy: $(Get-ExecutionPolicy)" -InformationAction Continue
        exit 1
    }
    catch [System.IO.FileNotFoundException] {
        Write-Error "Module file not found: $modulePath"
        Write-Information "  ℹ️ Ensure all module files are present in the modules/core directory" -InformationAction Continue
        exit 1
    }
    catch {
        Write-Error "Failed to load core module $moduleName`: $_"
        Write-Information "  ℹ️ Error Type: $($_.Exception.GetType().Name)" -InformationAction Continue
        Write-Information "  ℹ️ Error Details: $($_.Exception.Message)" -InformationAction Continue
        if ($_.ScriptStackTrace) {
            Write-Information "  ℹ️ Stack Trace: $($_.ScriptStackTrace)" -InformationAction Continue
        }
        exit 1
    }
}

# Load Type2 modules (self-contained with internal Type1 dependencies)
Write-Information "`nLoading Type2 modules..." -InformationAction Continue
foreach ($moduleName in $Type2Modules) {
    $modulePath = Join-Path $Type2ModulesPath "$moduleName.psm1"
    try {
        if (-not (Test-Path $modulePath)) {
            Write-Warning "Type2 module not found: $modulePath - will be skipped"
            continue
        }

        Import-Module $modulePath -Force -Global -ErrorAction Stop
        Write-Information "  ✓ Loaded: $moduleName (Type2 - self-contained)" -InformationAction Continue
        
        # Verify the standardized Invoke-[ModuleName] function is available
        $invokeFunction = "Invoke-$moduleName"
        if (Get-Command -Name $invokeFunction -ErrorAction SilentlyContinue) {
            Write-Information "    ✓ $invokeFunction function available" -InformationAction Continue
        }
        else {
            Write-Warning "    ⚠️ $invokeFunction function not found - module may not be v3.0 compliant"
        }
    }
    catch {
        Write-Warning "Failed to load Type2 module $moduleName`: $($_.Exception.Message)"
        Write-Information "  ℹ️ This module will be skipped during execution" -InformationAction Continue
        
        # Additional diagnostic information
        if ($_.Exception.InnerException) {
            Write-Information "  🔍 Inner exception: $($_.Exception.InnerException.Message)" -InformationAction Continue
        }
        if ($_.ScriptStackTrace) {
            Write-Information "  📍 Stack trace: $($_.ScriptStackTrace -split "`n" | Select-Object -First 2 -Join '; ')" -InformationAction Continue
        }
        
        # Check common issues
        if ($_.Exception.Message -like "*access*denied*" -or $_.Exception.Message -like "*unauthorized*") {
            Write-Information "  💡 Suggestion: Run as Administrator or unblock files with Unblock-File '$modulePath'" -InformationAction Continue
        }
        elseif ($_.Exception.Message -like "*execution*policy*") {
            Write-Information "  💡 Suggestion: Check PowerShell execution policy with Get-ExecutionPolicy" -InformationAction Continue
        }
        elseif ($_.Exception.Message -like "*dependency*" -or $_.Exception.Message -like "*import*") {
            Write-Information "  💡 Suggestion: Check module dependencies and verify all required modules are available" -InformationAction Continue
        }
    }
}

# Ensure Write-LogEntry is available after module loading (modules may have overridden it)
if (-not (Get-Command -Name 'Write-LogEntry' -ErrorAction SilentlyContinue)) {
    function global:Write-LogEntry {
        param($Level, $Component, $Message, $Data)
        Write-Information "[$Level] [$Component] $Message" -InformationAction Continue
    }
    Write-Information "  ⚠️ Write-LogEntry function was lost during module loading, reinstated fallback" -InformationAction Continue
}
else {
    $logFunction = Get-Command -Name 'Write-LogEntry'
    Write-Information "  ✓ Write-LogEntry available from: $($logFunction.Source)" -InformationAction Continue
}

#endregion

#region Configuration Loading

Write-Information "`nInitializing configuration..." -InformationAction Continue

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
        Write-Information "  Checking for Initialize-ConfigSystem function..." -InformationAction Continue
        
        # First, check if CoreInfrastructure module is loaded
        $coreModule = Get-Module -Name CoreInfrastructure -ErrorAction SilentlyContinue
        if (-not $coreModule) {
            Write-Information "  CoreInfrastructure module not found, attempting to re-import..." -InformationAction Continue
            $coreModulePath = Join-Path $CoreModulesPath "CoreInfrastructure.psm1"
            Import-Module $coreModulePath -Force -Global -ErrorAction Stop
            Write-Information "  ✓ CoreInfrastructure module re-imported" -InformationAction Continue
        }
        else {
            Write-Information "  CoreInfrastructure module is loaded (Version: $($coreModule.Version))" -InformationAction Continue
        }
        
        # Check for the specific function
        $configFunction = Get-Command Initialize-ConfigSystem -ErrorAction SilentlyContinue
        if (-not $configFunction) {
            Write-Information "  Available functions from CoreInfrastructure:" -InformationAction Continue
            $availableFunctions = Get-Command -Module CoreInfrastructure -ErrorAction SilentlyContinue
            if ($availableFunctions) {
                $availableFunctions | ForEach-Object { Write-Information "    $($_.Name)" -InformationAction Continue }
            }
            else {
                Write-Information "    No functions found from CoreInfrastructure module" -InformationAction Continue
            }
            
            # Also check all available functions with this name pattern
            Write-Information "  Searching for Initialize-ConfigSystem in all modules:" -InformationAction Continue
            Get-Command "*Initialize-ConfigSystem*" -ErrorAction SilentlyContinue | ForEach-Object { 
                Write-Information "    Found: $($_.Name) in module: $($_.ModuleName)" -InformationAction Continue 
            }
            
            throw "Initialize-ConfigSystem function not found"
        }
        
        Write-Information "  Found Initialize-ConfigSystem (Source: $($configFunction.Source)), calling with path: $ConfigPath" -InformationAction Continue
        Initialize-ConfigSystem -ConfigRootPath $ConfigPath -ErrorAction Stop
        Write-Information "  ✓ Configuration system initialized" -InformationAction Continue
    }
    catch {
        throw "Failed to initialize configuration system: $($_.Exception.Message)"
    }
    
    # Load configurations with validation
    try {
        $MainConfig = Get-MainConfig -ErrorAction Stop
        if (-not $MainConfig) {
            throw "Main configuration is null or empty"
        }
        Write-Information "  ✓ Main configuration loaded" -InformationAction Continue
    }
    catch {
        throw "Failed to load main configuration: $($_.Exception.Message)"
    }
    
    try {
        $LoggingConfig = Get-LoggingConfiguration -ErrorAction Stop
        if (-not $LoggingConfig) {
            throw "Logging configuration is null or empty"
        }
        Write-Information "  ✓ Logging configuration loaded" -InformationAction Continue
    }
    catch {
        throw "Failed to load logging configuration: $($_.Exception.Message)"
    }

    # Initialize file organization system first (required by logging system)
    try {
        $fileOrgResult = Initialize-FileOrganization -BaseDirectory $TempRoot -ErrorAction Stop
        if ($fileOrgResult) {
            Write-Information "  ✓ File organization system initialized" -InformationAction Continue
        }
        else {
            throw "File organization initialization returned false"
        }
    }
    catch {
        Write-Information "  ⚠️ File organization system failed to initialize: $($_.Exception.Message)" -InformationAction Continue
        Write-Information "  ℹ️ Continuing with basic file operations - some features may be limited" -InformationAction Continue
        # Don't exit here as this is not critical for basic operation
    }

    # Initialize temp_files directory structure (v3.0 requirement for Type1/Type2 module flow)
    try {
        Write-Information "  Initializing temp_files directory structure..." -InformationAction Continue
        $tempStructureValid = Initialize-TempFilesStructure
        if ($tempStructureValid) {
            Write-Information "  ✓ Temp files directory structure validated/created" -InformationAction Continue
        }
        else {
            Write-Information "  ⚠️ Some temp files directories could not be created - continuing with available structure" -InformationAction Continue
        }
    }
    catch {
        Write-Information "  ⚠️ Temp files structure validation failed: $($_.Exception.Message)" -InformationAction Continue
        Write-Information "  ℹ️ Modules will attempt to create directories as needed" -InformationAction Continue
    }

    # Initialize logging system (depends on file organization)
    try {
        $loggingInitResult = Initialize-LoggingSystem -LoggingConfig $LoggingConfig -BaseLogPath $MainLogFile -ErrorAction Stop
        if ($loggingInitResult) {
            Write-Information "  ✓ Logging system initialized" -InformationAction Continue
            # LoggingManager functions are now available
        }
        else {
            throw "Logging system initialization returned false"
        }
    }
    catch {
        Write-Information "  ⚠️ Logging system failed to initialize: $($_.Exception.Message)" -InformationAction Continue
        Write-Information "  ℹ️ Continuing without enhanced logging - basic console output only" -InformationAction Continue
    }
    
    # Ensure Write-LogEntry is always available (fallback if LoggingManager failed)
    if (-not (Get-Command -Name 'Write-LogEntry' -ErrorAction SilentlyContinue)) {
        function global:Write-LogEntry {
            param($Level, $Component, $Message, $Data)
            Write-Information "[$Level] [$Component] $Message" -InformationAction Continue
        }
        Write-Information "  ⚠️ Using fallback Write-LogEntry function" -InformationAction Continue
    }
    else {
        Write-Information "  ✓ Write-LogEntry function available from LoggingManager" -InformationAction Continue
    }
}
catch [System.IO.DirectoryNotFoundException] {
    Write-Error "Configuration directory not found: $ConfigPath"
    Write-Information "  ℹ️ Ensure the 'config' directory exists and contains required configuration files" -InformationAction Continue
    exit 1
}
catch [System.IO.FileNotFoundException] {
    Write-Error "Required configuration file not found: $($_.Exception.Message)"
    Write-Information "  ℹ️ Ensure all required configuration files are present in: $ConfigPath" -InformationAction Continue
    exit 1
}
catch [System.Management.Automation.RuntimeException] {
    Write-Error "Configuration system error: $($_.Exception.Message)"
    Write-Information "  ℹ️ Check configuration file syntax and module dependencies" -InformationAction Continue
    exit 1
}
catch {
    Write-Error "Failed to initialize configuration: $($_.Exception.Message)"
    Write-Information "  ℹ️ Error Type: $($_.Exception.GetType().Name)" -InformationAction Continue
    Write-Information "  ℹ️ This may indicate missing dependencies or corrupted configuration files" -InformationAction Continue
    exit 1
}

# Load app configurations with comprehensive error handling
try {
    Write-Information "`nLoading application configurations..." -InformationAction Continue
    
    try {
        $BloatwareLists = Get-BloatwareConfiguration -ErrorAction Stop
        if (-not $BloatwareLists) {
            Write-Warning "Bloatware configuration is empty or null - bloatware removal tasks may be limited"
        }
        else {
            Write-Information "  ✓ Bloatware configuration loaded" -InformationAction Continue
        }
    }
    catch {
        Write-Information "  ⚠️ Failed to load bloatware configuration: $($_.Exception.Message)" -InformationAction Continue
        Write-Information "  ℹ️ Bloatware removal tasks will be skipped" -InformationAction Continue
        $BloatwareLists = @()
    }
    
    try {
        $EssentialApps = Get-EssentialAppsConfiguration -ErrorAction Stop
        if (-not $EssentialApps) {
            Write-Warning "Essential apps configuration is empty or null - app installation tasks may be limited"
        }
        else {
            Write-Information "  ✓ Essential apps configuration loaded" -InformationAction Continue
        }
    }
    catch {
        Write-Information "  ⚠️ Failed to load essential apps configuration: $($_.Exception.Message)" -InformationAction Continue
        Write-Information "  ℹ️ Essential app installation tasks will be skipped" -InformationAction Continue
        $EssentialApps = @()
    }

    # Calculate configuration statistics with error handling
    try {
        $totalBloatware = if ($BloatwareLists -and $BloatwareLists.ContainsKey('all')) { $BloatwareLists['all'].Count } else { 0 }
        $totalEssentialApps = if ($EssentialApps -and $EssentialApps.ContainsKey('all')) { $EssentialApps['all'].Count } else { 0 }

        Write-Information "  ✓ Bloatware list: $totalBloatware total entries" -InformationAction Continue
        Write-Information "  ✓ Essential apps: $totalEssentialApps total entries" -InformationAction Continue
    }
    catch {
        Write-Information "  ⚠️ Error calculating configuration statistics: $($_.Exception.Message)" -InformationAction Continue
        $totalBloatware = 0
        $totalEssentialApps = 0
    }
}
catch [System.IO.FileNotFoundException] {
    Write-Error "App configuration file not found: $($_.Exception.Message)"
    Write-Information "  ℹ️ Ensure bloatware-list.json and essential-apps.json exist in: $ConfigPath" -InformationAction Continue
    exit 1
}
catch [System.ArgumentException] {
    Write-Error "Invalid app configuration format: $($_.Exception.Message)"
    Write-Information "  ℹ️ Check JSON syntax and structure in app configuration files" -InformationAction Continue
    exit 1
}
catch {
    Write-Error "Failed to load app configurations: $($_.Exception.Message)"
    Write-Information "  ℹ️ Error Type: $($_.Exception.GetType().Name)" -InformationAction Continue
    Write-Information "  ℹ️ Check app configuration files in: $ConfigPath" -InformationAction Continue
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

<#
.SYNOPSIS
    Collects all log files from temp_files/data/ and temp_files/logs/ for comprehensive reporting

.DESCRIPTION
    Aggregates Type1 audit results and Type2 execution logs into a comprehensive collection
    for ReportGeneration to process. This implements the v3.0 flow where orchestrator
    collects ALL logs after task completion.

.EXAMPLE
    $logCollection = Get-ComprehensiveLogCollection
#>
function Get-ComprehensiveLogCollection {
    [CmdletBinding()]
    param()
    
    Write-Information "  📋 Collecting comprehensive log data..." -InformationAction Continue
    
    try {
        $logCollection = @{
            Type1AuditData      = @{}
            Type2ExecutionLogs  = @{}
            CollectionTimestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            SessionId           = $Global:MaintenanceSessionId
        }
        
        # Collect Type1 audit results from temp_files/data/
        $dataPath = Join-Path $env:MAINTENANCE_TEMP_ROOT "data"
        if (Test-Path $dataPath) {
            $auditFiles = Get-ChildItem -Path $dataPath -Filter "*.json" -ErrorAction SilentlyContinue
            foreach ($file in $auditFiles) {
                try {
                    $moduleName = $file.BaseName -replace '-results$', ''
                    $auditData = Get-Content $file.FullName | ConvertFrom-Json
                    $logCollection.Type1AuditData[$moduleName] = $auditData
                    Write-Information "    ✓ Collected Type1 data: $($file.Name)" -InformationAction Continue
                }
                catch {
                    Write-Warning "    ⚠️ Failed to parse audit data: $($file.Name) - $($_.Exception.Message)"
                }
            }
        }
        
        # Collect Type2 execution logs from temp_files/logs/
        $logsPath = Join-Path $env:MAINTENANCE_TEMP_ROOT "logs"
        if (Test-Path $logsPath) {
            $logDirectories = Get-ChildItem -Path $logsPath -Directory -ErrorAction SilentlyContinue
            foreach ($dir in $logDirectories) {
                $executionLogPath = Join-Path $dir.FullName "execution.log"
                if (Test-Path $executionLogPath) {
                    try {
                        $logContent = Get-Content $executionLogPath -Raw
                        $logCollection.Type2ExecutionLogs[$dir.Name] = $logContent
                        Write-Information "    ✓ Collected Type2 logs: $($dir.Name)" -InformationAction Continue
                    }
                    catch {
                        Write-Warning "    ⚠️ Failed to read execution log: $($dir.Name) - $($_.Exception.Message)"
                    }
                }
            }
        }
        
        $auditDataCount = $logCollection.Type1AuditData.Keys.Count
        $executionLogsCount = $logCollection.Type2ExecutionLogs.Keys.Count
        
        Write-Information "  📊 Log collection summary: $auditDataCount Type1 modules, $executionLogsCount Type2 modules" -InformationAction Continue
        
        Write-LogEntry -Level 'INFO' -Component 'ORCHESTRATOR' -Message "Comprehensive log collection completed" -Data @{
            Type1ModulesCollected = $auditDataCount
            Type2ModulesCollected = $executionLogsCount
            CollectionTimestamp   = $logCollection.CollectionTimestamp
        }
        
        return $logCollection
    }
    catch {
        Write-LogEntry -Level 'ERROR' -Component 'ORCHESTRATOR' -Message "Failed to collect comprehensive logs: $($_.Exception.Message)"
        return @{
            Type1AuditData      = @{}
            Type2ExecutionLogs  = @{}
            CollectionTimestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            Error               = $_.Exception.Message
        }
    }
}

#endregion

#region Task Definitions

Write-Information "`nRegistering maintenance tasks..." -InformationAction Continue

# v3.0 Architecture: Define standardized maintenance tasks using Invoke-[ModuleName] pattern
$MaintenanceTasks = @(
    @{
        Name        = 'BloatwareRemoval'
        Description = 'Detect and remove bloatware applications (Type2→Type1 flow)'
        ModuleName  = 'BloatwareRemoval'
        Function    = 'Invoke-BloatwareRemoval'
        Type        = 'Type2'
        Category    = 'Cleanup'
        Enabled     = (-not $MainConfig.modules.skipBloatwareRemoval)
    },
    @{
        Name        = 'EssentialApps'
        Description = 'Analyze and install essential applications (Type2→Type1 flow)'
        ModuleName  = 'EssentialApps'
        Function    = 'Invoke-EssentialApps'
        Type        = 'Type2'
        Category    = 'Installation'
        Enabled     = (-not $MainConfig.modules.skipEssentialApps)
    },
    @{
        Name        = 'SystemOptimization'
        Description = 'Analyze and optimize system performance (Type2→Type1 flow)'
        ModuleName  = 'SystemOptimization'
        Function    = 'Invoke-SystemOptimization'
        Type        = 'Type2'
        Category    = 'Optimization'
        Enabled     = (-not $MainConfig.modules.skipSystemOptimization)
    },
    @{
        Name        = 'TelemetryDisable'
        Description = 'Analyze and disable Windows telemetry (Type2→Type1 flow)'
        ModuleName  = 'TelemetryDisable'
        Function    = 'Invoke-TelemetryDisable'
        Type        = 'Type2'
        Category    = 'Privacy'
        Enabled     = (-not $MainConfig.modules.skipTelemetryDisable)
    },
    @{
        Name        = 'WindowsUpdates'
        Description = 'Analyze and install Windows updates (Type2→Type1 flow)'
        ModuleName  = 'WindowsUpdates'
        Function    = 'Invoke-WindowsUpdates'
        Type        = 'Type2'
        Category    = 'Updates'
        Enabled     = (-not $MainConfig.modules.skipWindowsUpdates)
    }
)

# v3.0: Filter enabled tasks and verify functions are available
$AvailableTasks = @()
foreach ($task in $MaintenanceTasks) {
    if ($task.Enabled) {
        # Verify the standardized Invoke-[ModuleName] function is available
        if (Get-Command -Name $task.Function -ErrorAction SilentlyContinue) {
            $AvailableTasks += $task
            Write-Information "  ✓ Available: $($task.Name) - $($task.Function)" -InformationAction Continue
        }
        else {
            Write-Warning "  ⚠️ Skipped: $($task.Name) - function $($task.Function) not available (module may not be v3.0 compliant)"
        }
    }
    else {
        Write-Information "  ⊝ Disabled: $($task.Name) (disabled in configuration)" -InformationAction Continue
    }
}

Write-Information "  ✓ Registered $($AvailableTasks.Count) available tasks" -InformationAction Continue

#endregion

#region Execution Mode Selection

$ExecutionParams = @{
    Mode          = 'Execute'
    DryRun        = $false
    SelectedTasks = $AvailableTasks
}

if (-not $NonInteractive) {
    Write-Information "`nStarting interactive mode..." -InformationAction Continue

    # Show hierarchical menu with integrated task selection
    $menuResult = Show-MainMenu -CountdownSeconds $MainConfig.execution.countdownSeconds -AvailableTasks $AvailableTasks
    
    # Apply menu selections
    $ExecutionParams.DryRun = $menuResult.DryRun
    if (-not $TaskNumbers) {
        # Use tasks selected from the integrated menu system
        $ExecutionParams.SelectedTasks = @()
        foreach ($taskIndex in $menuResult.SelectedTasks) {
            if ($taskIndex -ge 1 -and $taskIndex -le $AvailableTasks.Count) {
                $ExecutionParams.SelectedTasks += $AvailableTasks[$taskIndex - 1]
            }
        }
        
        Write-Information "  ✓ Menu selections applied:" -InformationAction Continue
        Write-Information "    - Execution mode: $(if ($ExecutionParams.DryRun) { 'DRY-RUN' } else { 'NORMAL' })" -InformationAction Continue
        Write-Information "    - Selected tasks: $($ExecutionParams.SelectedTasks.Count)/$($AvailableTasks.Count)" -InformationAction Continue
    }
}
else {
    Write-Information "`nNon-interactive mode enabled" -InformationAction Continue
    if ($DryRun) {
        $ExecutionParams.DryRun = $true
        Write-Information "  ✓ Dry-run mode enabled" -InformationAction Continue
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
        Write-Information "  ✓ Task selection: $($taskNumbersArray -join ', ')" -InformationAction Continue
    }
    catch {
        Write-Error "Invalid TaskNumbers parameter format: $TaskNumbers"
        exit 1
    }
}

#endregion

#region Task Execution

Write-Information "`nStarting maintenance execution..." -InformationAction Continue

$executionMode = if ($ExecutionParams.DryRun) { "DRY-RUN" } else { "LIVE" }
Write-Information "Execution Mode: $executionMode" -InformationAction Continue
Write-Information "Selected Tasks: $($ExecutionParams.SelectedTasks.Count)/$($AvailableTasks.Count)" -InformationAction Continue

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
        Write-Information "Operation cancelled by user" -InformationAction Continue
        exit 0
    }
}

# Initialize execution tracking
$TaskResults = @()
$StartTime = Get-Date

Write-Information "`nExecuting tasks..." -InformationAction Continue
Write-Information "═══════════════════════════════════════════════════════════════" -InformationAction Continue

for ($i = 0; $i -lt $ExecutionParams.SelectedTasks.Count; $i++) {
    $task = $ExecutionParams.SelectedTasks[$i]
    $taskNumber = $i + 1
    $totalTasks = $ExecutionParams.SelectedTasks.Count

    Write-Information "" -InformationAction Continue
    Write-Information "[$taskNumber/$totalTasks] $($task.Name)" -InformationAction Continue
    Write-Information "Description: $($task.Description)" -InformationAction Continue
    Write-Information "Type: $($task.Type) | Category: $($task.Category)" -InformationAction Continue

    if ($ExecutionParams.DryRun) {
        Write-Information "Mode: DRY-RUN (simulation)" -InformationAction Continue
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
        # v3.0 Architecture: Simplified execution using standardized Invoke-[ModuleName] functions
        # Type2 modules are already loaded and self-contained with their Type1 dependencies
        
        # Log task start
        Write-LogEntry -Level 'INFO' -Component 'ORCHESTRATOR' -Message "Starting task: $($task.Name)" -Data @{
            TaskType     = $task.Type
            TaskCategory = $task.Category
            Function     = $task.Function
            DryRun       = $ExecutionParams.DryRun
            Architecture = 'v3.0'
        }

        # Verify function is available (already checked during module loading)
        if (-not (Get-Command -Name $task.Function -ErrorAction SilentlyContinue)) {
            throw "Function '$($task.Function)' not available - ensure $($task.ModuleName) module is properly loaded"
        }

        # Execute the standardized v3.0 function with consistent parameters
        $result = $null
        try {
            if ($ExecutionParams.DryRun) {
                Write-Information "  ▶ Simulating: $($task.Function)" -InformationAction Continue
                $result = & $task.Function -Config $MainConfig -DryRun
            }
            else {
                Write-Information "  ▶ Executing: $($task.Function)" -InformationAction Continue
                $result = & $task.Function -Config $MainConfig
            }
            
            # Validate standardized return structure (support both hashtable and PSCustomObject)
            $hasValidStructure = $false
            if ($result) {
                if ($result -is [hashtable] -and $result.ContainsKey('Success')) {
                    $hasValidStructure = $true
                }
                elseif ($result -is [PSCustomObject] -and (Get-Member -InputObject $result -Name 'Success' -ErrorAction SilentlyContinue)) {
                    $hasValidStructure = $true
                }
            }
            
            if ($hasValidStructure) {
                Write-Information "  ✓ v3.0 compliant result: Success=$($result.Success), Items Detected=$($result.ItemsDetected), Items Processed=$($result.ItemsProcessed)" -InformationAction Continue
            }
            else {
                $resultType = if ($result) { $result.GetType().Name } else { 'null' }
                Write-Warning "  ⚠️ Non-standard result format from $($task.Function) - Result type: $resultType, may not be v3.0 compliant"
            }
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
            
            # Log detailed error information for debugging
            Write-Information "[ERROR] [ORCHESTRATOR] Task failed: $($task.Name)" -InformationAction Continue
            Write-Information "  Error Type: $($errorDetails.Type)" -InformationAction Continue
            Write-Information "  Message: $($errorDetails.Message)" -InformationAction Continue
            Write-Information "  Function: $($errorDetails.Function) at line $($errorDetails.Line)" -InformationAction Continue
            
            throw "Task execution failed: $($_.Exception.Message)"
        }

        $taskResult.Success = $true
        $taskResult.Output = $result
        Write-Information "  ✓ Completed successfully" -InformationAction Continue

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
        Write-Information "  ⏸️ Cancelled: Task was cancelled" -InformationAction Continue
        
        Write-LogEntry -Level 'WARNING' -Component 'ORCHESTRATOR' -Message "Task cancelled: $($task.Name)" -Data @{
            Duration = ((Get-Date) - $taskStartTime).TotalSeconds
        }
    }
    catch [System.TimeoutException] {
        $taskResult.Success = $false
        $taskResult.Error = "Task timed out: $($_.Exception.Message)"
        Write-Information "  ⏱️ Timeout: $($_.Exception.Message)" -InformationAction Continue
        
        Write-LogEntry -Level 'ERROR' -Component 'ORCHESTRATOR' -Message "Task timeout: $($task.Name)" -Data @{
            Error    = $_.Exception.Message
            Duration = ((Get-Date) - $taskStartTime).TotalSeconds
        }
    }
    catch [System.OutOfMemoryException] {
        $taskResult.Success = $false
        $taskResult.Error = "Out of memory error during task execution"
        Write-Information "  💾 Memory Error: Insufficient memory to complete task" -InformationAction Continue
        
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
        Write-Information "  ✗ Failed: $($_.Exception.Message)" -InformationAction Continue
        
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
        Write-Information "  ℹ️ Error Type: $($_.Exception.GetType().Name)" -InformationAction Continue
        if ($_.InvocationInfo.ScriptLineNumber) {
            Write-Information "  ℹ️ Error at line: $($_.InvocationInfo.ScriptLineNumber)" -InformationAction Continue
        }
        if ($_.ScriptStackTrace) {
            Write-Verbose "Full stack trace: $($_.ScriptStackTrace)"
        }
    }
    finally {
        $taskResult.Duration = ((Get-Date) - $taskStartTime).TotalSeconds
        $TaskResults += $taskResult

        Write-Information "  Duration: $([math]::Round($taskResult.Duration, 2)) seconds" -InformationAction Continue
    }
}

#endregion

#region Log Collection (v3.0 Architecture)

# Collect comprehensive logs from Type1 audit results and Type2 execution logs
Write-Information "" -InformationAction Continue
Write-Information "📋 Collecting comprehensive log data..." -InformationAction Continue

$comprehensiveLogCollection = Get-ComprehensiveLogCollection

#endregion

#region Report Generation (v3.0 Architecture - Preserved)

# Generate comprehensive reports using ReportGeneration module (still orchestrator-loaded)
Write-Information "" -InformationAction Continue
Write-Information "📋 Generating maintenance reports..." -InformationAction Continue

try {
    # Collect system inventory using SystemAnalysis (core module)
    $systemInventory = $null
    if (Get-Command -Name 'Get-SystemInventory' -ErrorAction SilentlyContinue) {
        try {
            $systemInventory = Get-SystemInventory -UseCache -IncludeDetailed
            Write-Information "  ✓ System inventory collected" -InformationAction Continue
        }
        catch {
            Write-Warning "  ⚠️ Failed to collect system inventory: $($_.Exception.Message)"
        }
    }
    else {
        Write-Warning "  ⚠️ SystemAnalysis module not available for inventory collection"
    }

    # Generate reports using the ReportGeneration module (v3.0: Portable report in parent directory)
    if (Get-Command -Name 'New-MaintenanceReport' -ErrorAction SilentlyContinue) {
        # v3.0: Generate all reports in temp_files/reports/, then copy HTML to parent directory
        $reportsDir = Join-Path $Global:ProjectPaths.TempFiles "reports"
        New-Item -Path $reportsDir -ItemType Directory -Force | Out-Null
        
        $reportBasePath = Join-Path $reportsDir "MaintenanceReport_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').html"
        
        $reportResult = New-MaintenanceReport -SystemInventory $systemInventory -TaskResults $TaskResults -Configuration $MainConfig -OutputPath $reportBasePath -ComprehensiveLogCollection $comprehensiveLogCollection
        
        if ($reportResult -and $reportResult.Success) {
            Write-Information "  ✓ Reports generated successfully in temp_files/reports/" -InformationAction Continue
            if ($reportResult.ReportPaths) {
                foreach ($reportPath in $reportResult.ReportPaths) {
                    Write-Information "    • $reportPath" -InformationAction Continue
                }
            }
            
            # Copy only the main HTML report to parent directory (Desktop/Documents/USB root)
            if ($reportResult.HtmlReport -and (Test-Path $reportResult.HtmlReport)) {
                try {
                    $parentHtmlPath = Join-Path $Global:ProjectPaths.ParentDir (Split-Path -Leaf $reportResult.HtmlReport)
                    Copy-Item -Path $reportResult.HtmlReport -Destination $parentHtmlPath -Force
                    Write-Information "  ✓ HTML report copied to: $parentHtmlPath" -InformationAction Continue
                    
                    # Update result to include parent copy location
                    if (-not $reportResult.ParentCopy) {
                        $reportResult | Add-Member -NotePropertyName 'ParentCopy' -NotePropertyValue $parentHtmlPath -Force
                    }
                }
                catch {
                    Write-Warning "  ⚠️ Failed to copy HTML report to parent directory: $($_.Exception.Message)"
                }
            }
        }
        else {
            Write-Warning "  ⚠️ Report generation failed"
        }
    }
    else {
        Write-Warning "  ⚠️ ReportGeneration module not available - reports will not be generated"
    }
}
catch {
    Write-Warning "  ⚠️ Error during report generation: $($_.Exception.Message)"
}

#endregion

#region Execution Summary

Write-Information "" -InformationAction Continue
Write-Information "═══════════════════════════════════════════════════════════════" -InformationAction Continue
Write-Information "    EXECUTION SUMMARY" -InformationAction Continue
Write-Information "═══════════════════════════════════════════════════════════════" -InformationAction Continue

$totalDuration = ((Get-Date) - $StartTime).TotalSeconds
$successfulTasks = ($TaskResults | Where-Object { $_.Success }).Count
$failedTasks = ($TaskResults | Where-Object { -not $_.Success }).Count

Write-Information "" -InformationAction Continue
Write-Information "Execution Mode: $executionMode" -InformationAction Continue
Write-Information "Task Duration: $([math]::Round($totalDuration, 2)) seconds" -InformationAction Continue
Write-Information "Total Session: $([math]::Round(((Get-Date) - $SessionStartTime).TotalSeconds, 2)) seconds" -InformationAction Continue
Write-Information "Tasks Executed: $($TaskResults.Count)" -InformationAction Continue
Write-Information "Successful: $successfulTasks" -InformationAction Continue
Write-Information "Failed: $failedTasks" -InformationAction Continue

Write-Information "" -InformationAction Continue
Write-Information "Task Results:" -InformationAction Continue
Write-Information "─────────────────────────────────────────────────────────────" -InformationAction Continue

foreach ($result in $TaskResults) {
    $status = if ($result.Success) { '✓' } else { '✗' }
    $statusColor = if ($result.Success) { 'Green' } else { 'Red' }
    $durationText = "$([math]::Round($result.Duration, 2))s"

    # Use colored output for better visual feedback
    Write-Host "  $status $($result.TaskName) ($durationText)" -ForegroundColor $statusColor

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
$executionSummary | ConvertTo-Json -Depth 20 -WarningAction SilentlyContinue | Out-File -FilePath $summaryPath -Encoding UTF8

Write-Information "" -InformationAction Continue
Write-Information "Execution summary saved to: $summaryPath" -InformationAction Continue

# Copy final reports to parent directory (same level as repo folder)
Write-Information "" -InformationAction Continue
Write-Information "📄 Copying final reports to parent directory..." -InformationAction Continue

# Get parent directory of the script root (one level up from repo folder)
$ParentDir = Split-Path $ScriptRoot -Parent
Write-Information "  📁 Target directory: $ParentDir" -InformationAction Continue

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
                Write-Information "  ⚠️ Parent directory not accessible: $ParentDir" -InformationAction Continue
                continue
            }
            
            Copy-Item -Path $sourceFile -Destination $destPath -Force
            Write-Information "  ✓ Copied $description to: $destPath" -InformationAction Continue
            $finalReports += $destPath
        }
        catch {
            Write-Information "  ⚠️ Failed to copy $description`: $_" -InformationAction Continue
        }
    }
}

if ($finalReports.Count -gt 0) {
    Write-Information "" -InformationAction Continue
    Write-Information "📋 Final reports available in parent directory:" -InformationAction Continue
    Write-Information "  📁 Location: $ParentDir" -InformationAction Continue
    foreach ($report in $finalReports) {
        Write-Information "  • $(Split-Path $report -Leaf)" -InformationAction Continue
    }
}

if ($failedTasks -gt 0) {
    Write-Information "" -InformationAction Continue
    Write-Information "⚠️  Some tasks failed. Check the logs for detailed error information." -InformationAction Continue
    exit 1
}
else {
    Write-Information "" -InformationAction Continue
    Write-Information "🎉 All tasks completed successfully!" -InformationAction Continue
    exit 0
}

#endregion
