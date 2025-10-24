#Requires -Version 7.0

<#
.SYNOPSIS
    Core Infrastructure Module - Consolidated Configuration, Logging, and File Organization

.DESCRIPTION
    Consolidated core infrastructure module that provides configuration management,
    structured logging, and file organization capabilities in a single module.
    Combines the functionality of ConfigManager, LoggingManager, and FileOrganizationManager.

.NOTES
    Module Type: Core Infrastructure (Consolidated)
    Dependencies: JSON files in config/ directory
    Author: Windows Maintenance Automation Project
    Version: 2.0.0 (Consolidated)
#>

using namespace System.Collections.Generic
using namespace System.IO

#region Global Path Discovery System

# Global project path discovery - makes entire project aware of its structure
$script:MaintenanceProjectPaths = @{
    # Auto-detect project root based on multiple sources
    ProjectRoot = $null
    ScriptRoot  = $null
    ConfigRoot  = $null
    ModulesRoot = $null
    TempRoot    = $null
    ReportsRoot = $null
    Initialized = $false
}

function Initialize-GlobalPathDiscovery {
    [CmdletBinding()]
    param(
        [string]$HintPath,  # Optional hint from calling script
        [switch]$Force
    )
    
    # Thread-safe initialization check with lock
    if ($script:MaintenanceProjectPaths.Initialized -and -not $Force) {
        return $true
    }
    
    # Use a simple lock to prevent multiple initializations
    $lockKey = 'GlobalPathsInitLock'
    if ($Global:MaintenanceInitLocks -and $Global:MaintenanceInitLocks.ContainsKey($lockKey)) {
        # Another thread is initializing, wait briefly and return
        Start-Sleep -Milliseconds 100
        return $script:MaintenanceProjectPaths.Initialized
    }
    
    # Set lock
    if (-not $Global:MaintenanceInitLocks) { $Global:MaintenanceInitLocks = @{} }
    $Global:MaintenanceInitLocks[$lockKey] = $true
    
    try {
        # Double-check pattern - another thread might have completed initialization
        if ($script:MaintenanceProjectPaths.Initialized -and -not $Force) {
            return $true
        }
        
        Write-Information "Initializing global path discovery system..." -InformationAction Continue
    
        # Method 1: Use environment variables set by orchestrator
        if ($env:MAINTENANCE_PROJECT_ROOT) {
            $script:MaintenanceProjectPaths.ProjectRoot = $env:MAINTENANCE_PROJECT_ROOT
            Write-Information "  Found project root from environment: $($script:MaintenanceProjectPaths.ProjectRoot)" -InformationAction Continue
        }
    
        # Method 2: Use hint path from caller
        elseif ($HintPath -and (Test-Path $HintPath)) {
            $script:MaintenanceProjectPaths.ProjectRoot = $HintPath
            Write-Information "  Using hint path as project root: $HintPath" -InformationAction Continue
        }
    
        # Method 3: Auto-detect from calling script location
        elseif ($PSScriptRoot) {
            # Look for project structure indicators
            $testPath = $PSScriptRoot
            while ($testPath -and $testPath -ne (Split-Path $testPath -Parent)) {
                if ((Test-Path (Join-Path $testPath 'config')) -and 
                    (Test-Path (Join-Path $testPath 'modules')) -and 
                    (Test-Path (Join-Path $testPath 'MaintenanceOrchestrator.ps1'))) {
                    $script:MaintenanceProjectPaths.ProjectRoot = $testPath
                    Write-Information "  Auto-detected project root: $testPath" -InformationAction Continue
                    break
                }
                $testPath = Split-Path $testPath -Parent
            }
        }
    
        # Method 4: Use current working directory if it looks like project root
        if (-not $script:MaintenanceProjectPaths.ProjectRoot) {
            $currentDir = Get-Location | Select-Object -ExpandProperty Path
            if ((Test-Path (Join-Path $currentDir 'config')) -and 
                (Test-Path (Join-Path $currentDir 'modules'))) {
                $script:MaintenanceProjectPaths.ProjectRoot = $currentDir
                Write-Information "  Using current directory as project root: $currentDir" -InformationAction Continue
            }
        }
    
        # Validate we found a project root
        if (-not $script:MaintenanceProjectPaths.ProjectRoot) {
            throw "Unable to auto-detect project root. Please ensure you're running from the maintenance project directory."
        }
    
        # Set up all standard paths based on project root
        $projectRoot = $script:MaintenanceProjectPaths.ProjectRoot
        $script:MaintenanceProjectPaths.ScriptRoot = $projectRoot
        $script:MaintenanceProjectPaths.ConfigRoot = Join-Path $projectRoot 'config'
        $script:MaintenanceProjectPaths.ModulesRoot = Join-Path $projectRoot 'modules'
        $script:MaintenanceProjectPaths.TempRoot = Join-Path $projectRoot 'temp_files'
        $script:MaintenanceProjectPaths.ReportsRoot = $projectRoot  # Reports go to project root for portability
    
        # Set global environment variables for all modules to access
        $env:MAINTENANCE_PROJECT_ROOT = $script:MaintenanceProjectPaths.ProjectRoot
        $env:MAINTENANCE_CONFIG_ROOT = $script:MaintenanceProjectPaths.ConfigRoot
        $env:MAINTENANCE_MODULES_ROOT = $script:MaintenanceProjectPaths.ModulesRoot
        $env:MAINTENANCE_TEMP_ROOT = $script:MaintenanceProjectPaths.TempRoot
        $env:MAINTENANCE_REPORTS_ROOT = $script:MaintenanceProjectPaths.ReportsRoot
    
        # Set Global:ProjectPaths as the primary path access method
        $Global:ProjectPaths = @{
            'Root'      = $script:MaintenanceProjectPaths.ProjectRoot
            'Config'    = $script:MaintenanceProjectPaths.ConfigRoot
            'Modules'   = $script:MaintenanceProjectPaths.ModulesRoot
            'TempFiles' = $script:MaintenanceProjectPaths.TempRoot
            'ParentDir' = Split-Path -Parent $script:MaintenanceProjectPaths.ProjectRoot  # Report destination
        }
    
        # Create necessary directories with v3.0 structure
        $requiredDirectories = @(
            $Global:ProjectPaths.TempFiles,
            (Join-Path $Global:ProjectPaths.TempFiles 'data'),
            (Join-Path $Global:ProjectPaths.TempFiles 'logs'),
            (Join-Path $Global:ProjectPaths.TempFiles 'temp'),
            (Join-Path $Global:ProjectPaths.TempFiles 'reports')
        )
    
        foreach ($directory in $requiredDirectories) {
            if (-not (Test-Path $directory)) {
                try {
                    New-Item -Path $directory -ItemType Directory -Force | Out-Null
                    Write-Information "  📁 Created directory: $directory" -InformationAction Continue
                }
                catch {
                    Write-Warning "Failed to create directory $directory`: $($_.Exception.Message)"
                }
            }
        }
    
        $script:MaintenanceProjectPaths.Initialized = $true
    
        Write-Information "  Global path discovery completed:" -InformationAction Continue
        Write-Information "     Project Root: $($Global:ProjectPaths.Root)" -InformationAction Continue
        Write-Information "     Config Root: $($Global:ProjectPaths.Config)" -InformationAction Continue
        Write-Information "     Modules Root: $($Global:ProjectPaths.Modules)" -InformationAction Continue
        Write-Information "     Temp Root: $($Global:ProjectPaths.TempFiles)" -InformationAction Continue
        Write-Information "     Reports Root: $($Global:ProjectPaths.ParentDir)" -InformationAction Continue
    
        return $true
    }
    finally {
        # Release lock
        if ($Global:MaintenanceInitLocks -and $Global:MaintenanceInitLocks.ContainsKey($lockKey)) {
            $Global:MaintenanceInitLocks.Remove($lockKey)
        }
    }
}

function Get-MaintenanceProjectPath {
    [CmdletBinding()]
    param(
        [ValidateSet('Root', 'Config', 'Modules', 'TempFiles', 'ParentDir')]
        [string]$PathType = 'Root'
    )
    
    if (-not $Global:ProjectPaths -or -not $script:MaintenanceProjectPaths.Initialized) {
        Initialize-GlobalPathDiscovery
    }
    
    return $Global:ProjectPaths[$PathType]
}

function Get-MaintenanceModulePath {
    [CmdletBinding()]
    param(
        [ValidateSet('core', 'type1', 'type2')]
        [string]$ModuleType,
        
        [string]$ModuleName
    )
    
    $modulesRoot = Get-MaintenanceProjectPath -PathType 'Modules'
    
    if ($ModuleType) {
        $typePath = Join-Path $modulesRoot $ModuleType
        if ($ModuleName) {
            return Join-Path $typePath "$ModuleName.psm1"
        }
        return $typePath
    }
    
    return $modulesRoot
}

#endregion

#region Module Variables

# Configuration Management Variables
$script:LoadedConfig = $null
$script:ConfigPaths = @{}
$script:BloatwareLists = @{}
$script:EssentialApps = @{}

# Logging Management Variables
$script:LoggingContext = @{
    SessionId          = [guid]::NewGuid().ToString()
    StartTime          = Get-Date
    LogPath            = $null
    Config             = $null
    LogBuffer          = [List[hashtable]]::new()
    PerformanceMetrics = @{}
}

# File Organization Variables
$script:FileOrgContext = @{
    BaseDir            = $null
    CurrentSession     = $null
    DirectoryStructure = @{
        Logs    = @('session.log', 'orchestrator.log', 'modules', 'performance')
        Data    = @('inventory', 'apps', 'security')
        Reports = @()
        Temp    = @()
    }
}

#endregion

#region Configuration Management Functions

<#
.SYNOPSIS
    Initializes the configuration system

.DESCRIPTION
    Sets up configuration paths and performs initial validation of config directory structure.

.PARAMETER ConfigRootPath
    Root path to the config directory

.EXAMPLE
    Initialize-ConfigSystem -ConfigRootPath "C:\MaintenanceScript\config"
#>
function Initialize-ConfigSystem {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({ Test-Path $_ -PathType Container })]
        [string]$ConfigRootPath
    )

    Write-Verbose "Initializing configuration system with root path: $ConfigRootPath"

    if (-not (Test-Path $ConfigRootPath)) {
        throw "Configuration root path does not exist: $ConfigRootPath"
    }

    # Set up configuration paths
    $script:ConfigPaths = @{
        Root          = $ConfigRootPath
        MainConfig    = Join-Path $ConfigRootPath 'main-config.json'
        LoggingConfig = Join-Path $ConfigRootPath 'logging-config.json'
        BloatwareList = Join-Path $ConfigRootPath 'bloatware-list.json'
        EssentialApps = Join-Path $ConfigRootPath 'essential-apps.json'
    }

    # Validate required configuration files exist
    $requiredFiles = @('main-config.json', 'logging-config.json')
    foreach ($file in $requiredFiles) {
        $filePath = Join-Path $ConfigRootPath $file
        if (-not (Test-Path $filePath)) {
            throw "Required configuration file not found: $filePath"
        }
    }

    # Load and validate JSON syntax
    try {
        $script:LoadedConfig = Get-Content $script:ConfigPaths.MainConfig | ConvertFrom-Json
        Write-Verbose "Configuration system initialized successfully"
    }
    catch {
        throw "Failed to load main configuration: $($_.Exception.Message)"
    }
}

<#
.SYNOPSIS
    Converts PSCustomObject to Hashtable recursively

.DESCRIPTION
    Helper function to convert JSON-deserialized PSCustomObject to hashtable
    for compatibility with Type2 modules that expect [hashtable] parameters.
#>
function ConvertTo-HashtableDeep {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [object]$InputObject
    )
    
    process {
        if ($null -eq $InputObject) {
            return $null
        }
        
        if ($InputObject -is [hashtable]) {
            $output = @{}
            foreach ($key in $InputObject.Keys) {
                $output[$key] = ConvertTo-HashtableDeep -InputObject $InputObject[$key]
            }
            return $output
        }
        
        if ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string]) {
            $collection = @()
            foreach ($item in $InputObject) {
                $collection += ConvertTo-HashtableDeep -InputObject $item
            }
            return $collection
        }
        
        if ($InputObject -is [PSCustomObject]) {
            $output = @{}
            foreach ($property in $InputObject.PSObject.Properties) {
                $output[$property.Name] = ConvertTo-HashtableDeep -InputObject $property.Value
            }
            return $output
        }
        
        return $InputObject
    }
}

<#
.SYNOPSIS
    Gets the main configuration object as PSCustomObject

.DESCRIPTION
    Returns the raw configuration object loaded from JSON.
    Use Get-MainConfigHashtable for hashtable format.
#>
function Get-MainConfig {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    if (-not $script:LoadedConfig) {
        throw "Configuration system not initialized. Call Initialize-ConfigSystem first."
    }
    
    return $script:LoadedConfig
}

<#
.SYNOPSIS
    Gets the main configuration as a hashtable

.DESCRIPTION
    Converts the configuration PSCustomObject to hashtable format
    for compatibility with Type2 modules that expect [hashtable] parameters.
#>
function Get-MainConfigHashtable {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    if (-not $script:LoadedConfig) {
        throw "Configuration system not initialized. Call Initialize-ConfigSystem first."
    }
    
    return ConvertTo-HashtableDeep -InputObject $script:LoadedConfig
}

<#
.SYNOPSIS
    Gets bloatware list by category
#>
function Get-BloatwareList {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter()]
        [ValidateSet('OEM', 'Windows', 'Gaming', 'Security', 'all')]
        [string]$Category = 'all'
    )

    if (-not (Test-Path $script:ConfigPaths.BloatwareList)) {
        Write-Warning "Bloatware list file not found: $($script:ConfigPaths.BloatwareList)"
        return @()
    }

    try {
        $bloatwareData = Get-Content $script:ConfigPaths.BloatwareList | ConvertFrom-Json
        
        if ($Category -eq 'all') {
            return $bloatwareData
        }
        else {
            return $bloatwareData | Where-Object { $_.category -eq $Category }
        }
    }
    catch {
        Write-Error "Failed to load bloatware list: $($_.Exception.Message)"
        return @()
    }
}

<#
.SYNOPSIS
    Gets essential apps list
#>
function Get-UnifiedEssentialAppsList {
    [CmdletBinding()]
    [OutputType([array])]
    param()

    if (-not (Test-Path $script:ConfigPaths.EssentialApps)) {
        Write-Warning "Essential apps list file not found: $($script:ConfigPaths.EssentialApps)"
        return @()
    }

    try {
        $essentialApps = Get-Content $script:ConfigPaths.EssentialApps | ConvertFrom-Json
        return $essentialApps
    }
    catch {
        Write-Error "Failed to load essential apps list: $($_.Exception.Message)"
        return @()
    }
}

#endregion

#region Logging Management Functions

<#
.SYNOPSIS
    Gets the logging configuration from JSON file or returns defaults
#>
function Get-LoggingConfiguration {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    $configPath = $script:ConfigPaths.LoggingConfig

    if (-not (Test-Path $configPath)) {
        Write-Verbose "Logging configuration file not found. Using defaults."
        return @{
            logLevel                  = 'INFO'
            enableConsoleLog          = $true
            enableFileLog             = $true
            enablePerformanceTracking = $true
            logBufferSize             = 1000
        }
    }

    try {
        Write-Verbose "Loading logging configuration from: $configPath"
        $configJson = Get-Content $configPath -Raw -ErrorAction Stop
        $config = $configJson | ConvertFrom-Json -ErrorAction Stop
        
        # Convert to hashtable
        $configHash = @{}
        foreach ($property in $config.PSObject.Properties) {
            $configHash[$property.Name] = $property.Value
        }
        
        return $configHash
    }
    catch {
        Write-Warning "Failed to load logging configuration: $($_.Exception.Message). Using defaults."
        return @{
            logLevel                  = 'INFO'
            enableConsoleLog          = $true
            enableFileLog             = $true
            enablePerformanceTracking = $true
            logBufferSize             = 1000
        }
    }
}

<#
.SYNOPSIS
    Initializes the logging system
#>
function Initialize-LoggingSystem {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$LoggingConfig,

        [Parameter()]
        [string]$BaseLogPath
    )

    try {
        Write-Verbose "Initializing logging system..."
        
        # Store configuration
        $script:LoggingContext.Config = $LoggingConfig
        
        # Set up log path
        if ($BaseLogPath) {
            $script:LoggingContext.LogPath = $BaseLogPath
        }
        else {
            # Prefer temp_files/maintenance.log if project paths initialized
            try {
                $tempPath = Get-MaintenanceProjectPath -PathType 'TempFiles' -ErrorAction SilentlyContinue
                if ($tempPath) {
                    $script:LoggingContext.LogPath = Join-Path $tempPath 'maintenance.log'
                }
                else {
                    $script:LoggingContext.LogPath = Join-Path (Get-Location) 'maintenance.log'
                }
            }
            catch {
                $script:LoggingContext.LogPath = Join-Path (Get-Location) 'maintenance.log'
            }
        }

        # Ensure LogPath is not empty - resolve from Global:ProjectPaths if necessary
        if (-not $script:LoggingContext.LogPath -or [string]::IsNullOrWhiteSpace($script:LoggingContext.LogPath)) {
            $tempPath = Get-MaintenanceProjectPath -PathType 'TempFiles' -ErrorAction SilentlyContinue
            if ($tempPath) {
                $script:LoggingContext.LogPath = Join-Path $tempPath 'maintenance.log'
            }
            else {
                $script:LoggingContext.LogPath = Join-Path (Get-Location) 'maintenance.log'
            }
        }
        Write-Verbose "Logging system initialized with path: $($script:LoggingContext.LogPath)"
        # Ensure directory exists and header added if missing
        try {
            $logDir = Split-Path -Parent $script:LoggingContext.LogPath
            if (-not (Test-Path $logDir)) { New-Item -Path $logDir -ItemType Directory -Force | Out-Null }
            if (-not (Test-Path $script:LoggingContext.LogPath)) {
                $dateHeader = "=== Maintenance Log - $(Get-Date -Format 'yyyy-MM-dd') ===" 
                $dateHeader | Out-File -FilePath $script:LoggingContext.LogPath -Encoding UTF8
            }
        }
        catch {
            Write-Verbose "Failed to ensure main log file/header: $($_.Exception.Message)"
        }

        return $true
    }
    catch {
        Write-Error "Failed to initialize logging system: $($_.Exception.Message)"
        throw
    }
}

<#
.SYNOPSIS
    Gets the current verbosity settings from logging configuration
#>
function Get-VerbositySetting {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()
    
    try {
        # Get logging configuration
        $loggingConfig = Get-LoggingConfiguration
        
        # Get current verbosity level
        $verbosityLevel = 'Detailed'  # Default
        if ($loggingConfig.logging -and $loggingConfig.logging.operationVerbosity) {
            $verbosityLevel = $loggingConfig.logging.operationVerbosity
        }
        elseif ($loggingConfig.verbosity -and $loggingConfig.verbosity.currentLevel) {
            $verbosityLevel = $loggingConfig.verbosity.currentLevel
        }
        
        # Get settings for current level
        if ($loggingConfig.verbosity -and $loggingConfig.verbosity.levels -and $loggingConfig.verbosity.levels.$verbosityLevel) {
            return $loggingConfig.verbosity.levels.$verbosityLevel
        }
        
        # Return default Detailed settings if not found
        return @{
            logOperationStart   = $true
            logOperationSuccess = $true
            logOperationFailure = $true
            logOperationSkipped = $true
            logDetectionResults = $true
            logPreChecks        = $true
            logVerification     = $true
            logMetrics          = $true
            logAdditionalInfo   = $true
            logCommands         = $true
        }
    }
    catch {
        Write-Verbose "Failed to get verbosity settings, using defaults: $_"
        # Return default Detailed settings on error
        return @{
            logOperationStart   = $true
            logOperationSuccess = $true
            logOperationFailure = $true
            logOperationSkipped = $true
            logDetectionResults = $true
            logPreChecks        = $true
            logVerification     = $true
            logMetrics          = $true
            logAdditionalInfo   = $true
            logCommands         = $true
        }
    }
}

<#
.SYNOPSIS
    Tests if a specific operation should be logged based on verbosity settings
#>
function Test-ShouldLogOperation {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('OperationStart', 'OperationSuccess', 'OperationFailure', 'OperationSkipped', 
            'DetectionResults', 'PreCheck', 'Verification', 'Metrics', 'AdditionalInfo', 'Commands')]
        [string]$OperationType
    )
    
    try {
        $verbositySettings = Get-VerbositySetting
        
        $settingKey = switch ($OperationType) {
            'OperationStart' { 'logOperationStart' }
            'OperationSuccess' { 'logOperationSuccess' }
            'OperationFailure' { 'logOperationFailure' }
            'OperationSkipped' { 'logOperationSkipped' }
            'DetectionResults' { 'logDetectionResults' }
            'PreCheck' { 'logPreChecks' }
            'Verification' { 'logVerification' }
            'Metrics' { 'logMetrics' }
            'AdditionalInfo' { 'logAdditionalInfo' }
            'Commands' { 'logCommands' }
            default { return $true }  # Log by default
        }
        
        if ($verbositySettings.ContainsKey($settingKey)) {
            return $verbositySettings[$settingKey]
        }
        
        return $true  # Log by default if setting not found
    }
    catch {
        Write-Verbose "Error checking verbosity setting for $OperationType : $_"
        return $true  # Log by default on error
    }
}

<#
.SYNOPSIS
    Writes a structured log entry with optional operation context
#>
function Write-LogEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('DEBUG', 'INFO', 'WARN', 'ERROR', 'FATAL', 'SUCCESS', 'TRACE')]
        [string]$Level,

        [Parameter(Mandatory)]
        [string]$Component,

        [Parameter(Mandatory)]
        [string]$Message,

        [Parameter()]
        [hashtable]$Data = @{},
        
        [Parameter()]
        [string]$LogPath,  # Optional specific log file path for Type2 modules
        
        # NEW: Operation context parameters for detailed logging
        [Parameter()]
        [ValidateSet('Detect', 'Remove', 'Install', 'Modify', 'Disable', 'Enable', 'Update', 'Configure', 'Verify', 'Analyze', 'Execute')]
        [string]$Operation,
        
        [Parameter()]
        [string]$Target,  # What is being operated on (app name, registry key, service, etc.)
        
        [Parameter()]
        [ValidateSet('Success', 'Failed', 'Skipped', 'Pending', 'InProgress')]
        [string]$Result,
        
        [Parameter()]
        [hashtable]$Metrics  # Performance metrics (Duration, Size, Count, etc.)
    )

    try {
        # Simplified timestamp format (time only, date in log header)
        $timestamp = Get-Date -Format "HH:mm:ss"
        $sessionId = $script:LoggingContext.SessionId
        
        $logEntry = @{
            Timestamp = $timestamp
            Level     = $Level
            Component = $Component
            Message   = $Message
            SessionId = $sessionId
            Data      = $Data
        }
        
        # Add operation context if provided
        if ($Operation) { $logEntry.Operation = $Operation }
        if ($Target) { $logEntry.Target = $Target }
        if ($Result) { $logEntry.Result = $Result }
        if ($Metrics) { $logEntry.Metrics = $Metrics }

        # Add to buffer
        $script:LoggingContext.LogBuffer.Add($logEntry)

        # Format for console and file - enhanced with operation context
        $formattedMessage = "[$timestamp] [$Level] [$Component]"
        if ($Operation) { $formattedMessage += " [$Operation]" }
        if ($Target) { $formattedMessage += " [$Target]" }
        $formattedMessage += " $Message"
        if ($Result) { $formattedMessage += " - Result: $Result" }
        if ($Metrics) {
            $metricsStr = ($Metrics.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ', '
            $formattedMessage += " - Metrics: $metricsStr"
        }
        
        # Output to console based on level
        switch ($Level) {
            'DEBUG' { Write-Verbose $formattedMessage }
            'INFO' { Write-Information $formattedMessage -InformationAction Continue }
            'WARN' { Write-Warning $formattedMessage }
            'ERROR' { Write-Error $formattedMessage }
            'FATAL' { Write-Error $formattedMessage }
        }

        # Write to specific log file if provided (for Type2 modules)
        # When LogPath is specified, write ONLY to that path (not to main log)
        if ($LogPath) {
            try {
                # If LogPath is relative, resolve it under the project's temp_files root
                if (-not [System.IO.Path]::IsPathRooted($LogPath)) {
                    try {
                        if ($Global:ProjectPaths -and $Global:ProjectPaths.TempFiles) {
                            $LogPath = Join-Path $Global:ProjectPaths.TempFiles $LogPath
                        }
                        elseif ($script:MaintenanceProjectPaths -and $script:MaintenanceProjectPaths.TempRoot) {
                            $LogPath = Join-Path $script:MaintenanceProjectPaths.TempRoot $LogPath
                        }
                    }
                    catch {
                        # leave LogPath as-is if resolution fails
                    }
                }

                # Normalize path (remove any trailing directory separator)
                if ($LogPath.EndsWith([System.IO.Path]::DirectorySeparatorChar) -or $LogPath.EndsWith([System.IO.Path]::AltDirectorySeparatorChar)) {
                    $LogPath = $LogPath.TrimEnd('\', '/')
                }

                # Ensure the directory exists
                $logDir = Split-Path -Parent $LogPath
                if (-not (Test-Path $logDir)) {
                    New-Item -Path $logDir -ItemType Directory -Force | Out-Null
                }
                # Add date header if file missing
                if (-not (Test-Path $LogPath)) {
                    $dateHeader = "=== Execution Log - $(Get-Date -Format 'yyyy-MM-dd') ==="
                    $dateHeader | Out-File -FilePath $LogPath -Encoding UTF8
                }
                $formattedMessage | Out-File -FilePath $LogPath -Append -Encoding UTF8
            }
            catch {
                Write-Warning "Failed to write to specific log path $LogPath`: $($_.Exception.Message)"
            }
        }
        # Write to main log file only if no specific LogPath was provided
        elseif ($script:LoggingContext.LogPath) {
            try {
                $formattedMessage | Out-File -FilePath $script:LoggingContext.LogPath -Append -Encoding UTF8
            }
            catch {
                Write-Warning "Failed to write to main log file: $($_.Exception.Message)"
            }
        }

    }
    catch {
        Write-Warning "Failed to write log entry: $($_.Exception.Message)"
    }
}

<#
.SYNOPSIS
    Logs the start of an operation with details
.DESCRIPTION
    Helper function for consistent operation start logging across all modules
.EXAMPLE
    Write-OperationStart -Component 'BLOATWARE-REMOVAL' -Operation 'Remove' -Target 'Microsoft.BingWeather' -LogPath $logPath -Details @{ Version = '4.25'; Size = '12.5MB' }
#>
function Write-OperationStart {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Component,
        
        [Parameter(Mandatory)]
        [ValidateSet('Detect', 'Remove', 'Install', 'Modify', 'Disable', 'Enable', 'Update', 'Configure', 'Verify', 'Analyze', 'Execute')]
        [string]$Operation,
        
        [Parameter(Mandatory)]
        [string]$Target,
        
        [Parameter()]
        [string]$LogPath,
        
        [Parameter()]
        [hashtable]$AdditionalInfo = @{}
    )
    
    # Check verbosity setting
    if (-not (Test-ShouldLogOperation -OperationType 'OperationStart')) {
        return
    }
    
    Write-LogEntry -Level 'INFO' -Component $Component `
        -Message "Starting $Operation operation" `
        -Operation $Operation -Target $Target -Result 'InProgress' `
        -LogPath $LogPath -Data $AdditionalInfo
}

<#
.SYNOPSIS
    Logs successful completion of an operation
.DESCRIPTION
    Helper function for consistent operation success logging across all modules
.EXAMPLE
    Write-OperationSuccess -Component 'BLOATWARE-REMOVAL' -Operation 'Remove' -Target 'Microsoft.BingWeather' -LogPath $logPath -Metrics @{ Duration = 1.2; SpaceFreed = '12.5MB' }
#>
function Write-OperationSuccess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Component,
        
        [Parameter(Mandatory)]
        [ValidateSet('Detect', 'Remove', 'Install', 'Modify', 'Disable', 'Enable', 'Update', 'Configure', 'Verify', 'Analyze', 'Execute')]
        [string]$Operation,
        
        [Parameter(Mandatory)]
        [string]$Target,
        
        [Parameter()]
        [string]$LogPath,
        
        [Parameter()]
        [hashtable]$Metrics,
        
        [Parameter()]
        [hashtable]$Details
    )
    
    # Check verbosity setting
    if (-not (Test-ShouldLogOperation -OperationType 'OperationSuccess')) {
        return
    }
    
    # Initialize hashtables if null
    if (-not $Metrics) { $Metrics = @{} }
    if (-not $Details) { $Details = @{} }
    
    $combinedData = $Details.Clone()
    if ($Metrics.Count -gt 0) {
        # Only include metrics if verbosity allows
        if (Test-ShouldLogOperation -OperationType 'Metrics') {
            $combinedData['Metrics'] = $Metrics
        }
    }
    
    Write-LogEntry -Level 'SUCCESS' -Component $Component `
        -Message "Completed $Operation operation successfully" `
        -Operation $Operation -Target $Target -Result 'Success' `
        -LogPath $LogPath -Metrics $Metrics -Data $combinedData
}

<#
.SYNOPSIS
    Logs failure of an operation
.DESCRIPTION
    Helper function for consistent operation failure logging across all modules
.EXAMPLE
    Write-OperationFailure -Component 'BLOATWARE-REMOVAL' -Operation 'Remove' -Target 'Microsoft.BingWeather' -LogPath $logPath -Error $_.Exception -Details @{ Reason = 'Access denied' }
#>
function Write-OperationFailure {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Component,
        
        [Parameter(Mandatory)]
        [ValidateSet('Detect', 'Remove', 'Install', 'Modify', 'Disable', 'Enable', 'Update', 'Configure', 'Verify', 'Analyze', 'Execute')]
        [string]$Operation,
        
        [Parameter(Mandatory)]
        [string]$Target,
        
        [Parameter()]
        [string]$LogPath,
        
        [Parameter()]
        [System.Management.Automation.ErrorRecord]$ErrorRecord,
        
        [Parameter()]
        [hashtable]$AdditionalInfo
    )
    
    # Always log failures regardless of verbosity
    if (-not (Test-ShouldLogOperation -OperationType 'OperationFailure')) {
        return
    }
    
    # Initialize parameters if null
    if (-not $AdditionalInfo) { $AdditionalInfo = @{} }
    
    $errorData = $AdditionalInfo.Clone()
    if ($ErrorRecord) {
        $errorData['ErrorMessage'] = $ErrorRecord.Exception.Message
        $errorData['ErrorType'] = $ErrorRecord.Exception.GetType().FullName
        # Only include stack trace if verbosity allows (Debug level)
        $verbositySettings = Get-VerbositySetting
        if ($verbositySettings.logStackTraces -eq $true) {
            $errorData['StackTrace'] = $ErrorRecord.ScriptStackTrace
        }
    }
    
    Write-LogEntry -Level 'ERROR' -Component $Component `
        -Message "Failed $Operation operation" `
        -Operation $Operation -Target $Target -Result 'Failed' `
        -LogPath $LogPath -Data $errorData
}

<#
.SYNOPSIS
    Logs that an operation was skipped
.DESCRIPTION
    Helper function for logging when an operation is intentionally skipped
.EXAMPLE
    Write-OperationSkipped -Component 'BLOATWARE-REMOVAL' -Operation 'Remove' -Target 'Microsoft.Store' -LogPath $logPath -Reason 'Protected system app'
#>
function Write-OperationSkipped {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Component,
        [Parameter(Mandatory)]
        [ValidateSet('Detect', 'Remove', 'Install', 'Modify', 'Disable', 'Enable', 'Update', 'Configure', 'Verify', 'Analyze', 'Execute')]
        [string]$Operation,
        [Parameter(Mandatory)]
        [string]$Target,
        [Parameter()]
        [string]$LogPath,
        [Parameter()]
        [string]$Reason,
        [Parameter()]
        [hashtable]$AdditionalInfo
    )
    
    # Check verbosity setting
    if (-not (Test-ShouldLogOperation -OperationType 'OperationSkipped')) {
        return
    }
    
    # Initialize parameters if null
    if (-not $Reason) { $Reason = 'Not applicable' }
    if (-not $AdditionalInfo) { $AdditionalInfo = @{} }
    
    $skipData = $AdditionalInfo.Clone()
    $skipData['SkipReason'] = $Reason
    
    Write-LogEntry -Level 'INFO' -Component $Component `
        -Message "Skipped $Operation operation: $Reason" `
        -Operation $Operation -Target $Target -Result 'Skipped' `
        -LogPath $LogPath -Data $skipData
}

<#
.SYNOPSIS
    Logs detection of an item
.DESCRIPTION
    Helper function for Type1 modules to log each detected item with full details
.EXAMPLE
    Write-DetectionLog -Component 'BLOATWARE-AUDIT' -Target 'Microsoft.BingWeather' -LogPath $logPath -Details @{ Source = 'AppX'; Version = '4.25'; Size = '12.5MB'; MatchedPattern = 'Microsoft.Bing*' }
#>
function Write-DetectionLog {
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateSet('Detect', 'Remove', 'Install', 'Modify', 'Disable', 'Enable', 'Update', 'Configure', 'Verify', 'Analyze', 'Execute')]
        [string]$Operation,
    
        [Parameter(Mandatory)]
        [string]$Component,
    
        [Parameter(Mandatory)]
        [string]$Target,
    
        [Parameter()]
        [string]$LogPath,
    
        [Parameter()]
        [hashtable]$AdditionalInfo
    )
    
    # Check verbosity setting
    if (-not (Test-ShouldLogOperation -OperationType 'DetectionResults')) {
        return
    }
    
    Write-LogEntry -Level 'INFO' -Component $Component `
        -Message "Detected item: $Target" `
        -Operation $Operation -Target $Target -Result 'Success' `
        -LogPath $LogPath -Data $AdditionalInfo
}

<#
.SYNOPSIS
    Writes structured log entry to both text and JSON logs

.DESCRIPTION
    Enhanced logging function that maintains human-readable text logs
    while also creating machine-readable JSON logs for better parsing.
    Backwards compatible with Write-LogEntry.

.PARAMETER Level
    Log level (DEBUG, INFO, SUCCESS, WARN, ERROR)

.PARAMETER Component
    Component name (e.g., BLOATWARE-REMOVAL)

.PARAMETER Message
    Human-readable log message

.PARAMETER LogPath
    Path to text log file (JSON log will be created alongside with -data.json extension)

.PARAMETER Metadata
    Structured data to include in JSON log (hashtable)

.PARAMETER Operation
    Optional operation type for categorization

.PARAMETER Target
    Optional target identifier for the operation

.PARAMETER Result
    Optional result status for the operation

.EXAMPLE
    Write-StructuredLogEntry -Level 'SUCCESS' -Component 'BLOATWARE-REMOVAL' `
        -Message "Removed Candy Crush" -LogPath $executionLogPath `
        -Metadata @{ AppName = "Candy Crush"; Size = "125MB"; Source = "AppX" }

.EXAMPLE
    Write-StructuredLogEntry -Level 'INFO' -Component 'BLOATWARE-REMOVAL' `
        -Message "Starting bloatware detection" -LogPath $executionLogPath

.NOTES
    JSON logging is non-critical - failures are logged but don't stop execution
#>
function Write-StructuredLogEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('DEBUG', 'INFO', 'SUCCESS', 'WARN', 'ERROR')]
        [string]$Level,
        
        [Parameter(Mandatory)]
        [string]$Component,
        
        [Parameter(Mandatory)]
        [string]$Message,
        
        [Parameter()]
        [string]$LogPath,
        
        [Parameter()]
        [hashtable]$Metadata = @{},
        
        [Parameter()]
        [ValidateSet('Detect', 'Remove', 'Install', 'Modify', 'Disable', 'Enable', 'Update', 'Configure', 'Verify', 'Analyze', 'Execute', 'Process', 'ProcessGroup', 'Complete', 'Start', 'Filter', 'Upgrade', 'Simulate')]
        [string]$Operation,
        
        [Parameter()]
        [string]$Target,
        
        [Parameter()]
        [ValidateSet('Success', 'Failed', 'Skipped', 'Pending', 'InProgress', 'NoItemsFound', 'Unknown', 'Error')]
        [string]$Result
    )
    
    # Write traditional text log (backwards compatible)
    $logParams = @{
        Level     = $Level
        Component = $Component
        Message   = $Message
        Data      = $Metadata
    }
    if ($LogPath) { $logParams.LogPath = $LogPath }
    if ($Operation) { $logParams.Operation = $Operation }
    if ($Target) { $logParams.Target = $Target }
    if ($Result) { $logParams.Result = $Result }
    
    Write-LogEntry @logParams
    
    # If LogPath specified, also write to JSON log
    if ($LogPath) {
        try {
            # Determine JSON log path (same directory, different extension)
            $jsonLogPath = $LogPath -replace '\.log$', '-data.json'
            
            # Create log entry object
            $logEntry = [PSCustomObject]@{
                Timestamp = Get-Date -Format 'o'  # ISO 8601 format
                Level     = $Level
                Component = $Component
                Message   = $Message
                Metadata  = if ($Metadata.Count -gt 0) { $Metadata } else { $null }
            }
            
            # Add optional fields if provided
            if ($Operation) { $logEntry | Add-Member -MemberType NoteProperty -Name 'Operation' -Value $Operation }
            if ($Target) { $logEntry | Add-Member -MemberType NoteProperty -Name 'Target' -Value $Target }
            if ($Result) { $logEntry | Add-Member -MemberType NoteProperty -Name 'Result' -Value $Result }
            
            # Load existing JSON log or create new array
            $logData = if (Test-Path $jsonLogPath) {
                try {
                    $existingJson = Get-Content $jsonLogPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
                    # Ensure it's an array
                    if ($existingJson -is [System.Collections.IEnumerable] -and $existingJson -isnot [string]) {
                        [System.Collections.ArrayList]@($existingJson)
                    }
                    else {
                        [System.Collections.ArrayList]@($existingJson)
                    }
                }
                catch {
                    # Corrupted JSON, start fresh
                    Write-Verbose "JSON log corrupted or invalid, creating new: $jsonLogPath"
                    [System.Collections.ArrayList]@()
                }
            }
            else {
                [System.Collections.ArrayList]@()
            }
            
            # Add new entry
            [void]$logData.Add($logEntry)
            
            # Write back to file (atomic write via temp file)
            $tempPath = "$jsonLogPath.tmp"
            $logData | ConvertTo-Json -Depth 10 -Compress:$false | Set-Content $tempPath -Force -Encoding UTF8
            Move-Item $tempPath $jsonLogPath -Force
        }
        catch {
            # JSON logging is non-critical, don't break execution
            Write-Verbose "Failed to write JSON log entry: $($_.Exception.Message)"
        }
    }
}

<#
.SYNOPSIS
    Starts performance tracking for an operation
#>
function Start-PerformanceTracking {
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string]$OperationName,

        [Parameter(Mandatory)]
        [string]$Component
    )

    $perfId = [guid]::NewGuid().ToString()
    $perfContext = @{
        Id            = $perfId
        OperationName = $OperationName
        Component     = $Component
        StartTime     = Get-Date
        StartTicks    = [System.Diagnostics.Stopwatch]::GetTimestamp()
    }

    if ($PSCmdlet.ShouldProcess("PerformanceMetrics", "Register new performance context for $OperationName")) {
        $script:LoggingContext.PerformanceMetrics[$perfId] = $perfContext
    }
    
    Write-LogEntry -Level 'DEBUG' -Component $Component -Message "Started operation: $OperationName" -Data @{ PerformanceId = $perfId }
    
    return $perfContext
}

<#
.SYNOPSIS
    Completes performance tracking for an operation
#>
function Complete-PerformanceTracking {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Context,

        [Parameter(Mandatory)]
        [ValidateSet('Success', 'Failed', 'Cancelled')]
        [string]$Status,

        [Parameter()]
        [string]$ErrorMessage,

        [Parameter()]
        [int]$ResultCount = 0
    )

    try {
        $endTime = Get-Date
        $endTicks = [System.Diagnostics.Stopwatch]::GetTimestamp()
        $duration = [TimeSpan]::FromTicks($endTicks - $Context.StartTicks)
        
        $Context.EndTime = $endTime
        $Context.Duration = $duration
        $Context.Status = $Status
        $Context.ResultCount = $ResultCount
        
        if ($ErrorMessage) {
            $Context.ErrorMessage = $ErrorMessage
        }

        $logData = @{
            PerformanceId = $Context.Id
            Duration      = $duration.TotalMilliseconds
            Status        = $Status
            ResultCount   = $ResultCount
        }

        Write-LogEntry -Level 'INFO' -Component $Context.Component -Message "Completed operation: $($Context.OperationName) in $([math]::Round($duration.TotalMilliseconds, 2))ms" -Data $logData

    }
    catch {
        Write-Warning "Failed to complete performance tracking: $($_.Exception.Message)"
    }
}

#endregion

#region Security and Privilege Functions

<#
.SYNOPSIS
    Asserts that the current process has administrator privileges

.DESCRIPTION
    Checks if the current PowerShell session is running with administrator privileges.
    Throws an error if admin rights are not available.

.PARAMETER Operation
    Description of the operation that requires admin privileges (for error messages)

.EXAMPLE
    Assert-AdminPrivilege -Operation "Windows Updates installation"

.NOTES
    This function will throw an exception if administrator privileges are not present.
#>
function Assert-AdminPrivilege {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Operation = "this operation"
    )
    
    try {
        $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
        $isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        
        if (-not $isAdmin) {
            throw "Administrator privileges are required for $Operation. Please run PowerShell as Administrator."
        }
        
        Write-Verbose "Administrator privilege check passed for: $Operation"
        return $true
    }
    catch {
        Write-Error "Administrator privilege check failed: $($_.Exception.Message)"
        throw
    }
}

#endregion

#region File Organization Functions

<#
.SYNOPSIS
    Initializes the file organization system
#>
function Initialize-FileOrganization {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$BaseDirectory
    )

    try {
        $script:FileOrgContext.BaseDir = $BaseDirectory
        
        # Create main directory structure
        $directories = @('logs', 'data', 'temp', 'reports')
        foreach ($dir in $directories) {
            $fullPath = Join-Path $BaseDirectory $dir
            if (-not (Test-Path $fullPath)) {
                New-Item -Path $fullPath -ItemType Directory -Force | Out-Null
                Write-Verbose "Created directory: $fullPath"
            }
        }

        # Create log subdirectories for Type2 modules
        $logSubdirectories = @('bloatware-removal', 'essential-apps', 'system-optimization', 'telemetry-disable', 'windows-updates')
        $logsPath = Join-Path $BaseDirectory 'logs'
        foreach ($subdir in $logSubdirectories) {
            $fullPath = Join-Path $logsPath $subdir
            if (-not (Test-Path $fullPath)) {
                New-Item -Path $fullPath -ItemType Directory -Force | Out-Null
                Write-Verbose "Created log subdirectory: $fullPath"
            }
        }

        Write-Verbose "File organization initialized with base directory: $BaseDirectory"
        return $true
    }
    catch {
        Write-Error "Failed to initialize file organization: $($_.Exception.Message)"
        return $false
    }
}

<#
.SYNOPSIS
    Gets a session-specific file path using global path discovery
#>
function Get-SessionPath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('logs', 'data', 'temp', 'reports')]
        [string]$Category,

        [Parameter()]
        [string]$SubCategory,

        [Parameter(Mandatory)]
        [string]$FileName
    )

    # Use global path discovery system as primary method
    if (-not $script:MaintenanceProjectPaths.Initialized) {
        try {
            Initialize-GlobalPathDiscovery
        }
        catch {
            Write-Warning "Global path discovery failed: $($_.Exception.Message)"
        }
    }
    
    # Primary: Use global path discovery
    if ($script:MaintenanceProjectPaths.Initialized) {
        $tempRoot = Get-MaintenanceProjectPath -PathType 'TempFiles'
        $categoryPath = Join-Path $tempRoot $Category
        
        if ($SubCategory) {
            $categoryPath = Join-Path $categoryPath $SubCategory
            # Ensure subcategory directory exists
            if (-not (Test-Path $categoryPath)) {
                try {
                    New-Item -Path $categoryPath -ItemType Directory -Force | Out-Null
                }
                catch {
                    Write-Warning "Failed to create subcategory directory: $categoryPath"
                }
            }
        }
        
        return Join-Path $categoryPath $FileName
    }
    
    # Fallback 1: Use legacy file organization if available
    if ($script:FileOrgContext.BaseDir) {
        $categoryPath = Join-Path $script:FileOrgContext.BaseDir $Category
        
        if ($SubCategory) {
            $categoryPath = Join-Path $categoryPath $SubCategory
            if (-not (Test-Path $categoryPath)) {
                try {
                    New-Item -Path $categoryPath -ItemType Directory -Force | Out-Null
                }
                catch {
                    Write-Warning "Failed to create subcategory directory: $categoryPath"
                }
            }
        }
        
        return Join-Path $categoryPath $FileName
    }
    
    # Fallback 2: Use environment variables
    if ($env:MAINTENANCE_TEMP_ROOT) {
        $categoryPath = Join-Path $env:MAINTENANCE_TEMP_ROOT $Category
        
        if ($SubCategory) {
            $categoryPath = Join-Path $categoryPath $SubCategory
            if (-not (Test-Path $categoryPath)) {
                try {
                    New-Item -Path $categoryPath -ItemType Directory -Force | Out-Null
                }
                catch {}
            }
        }
        
        return Join-Path $categoryPath $FileName
    }
    
    # Final fallback: Current directory (not ideal but works)
    Write-Warning "All path discovery methods failed - using current directory fallback"
    return $FileName
}

<#
.SYNOPSIS
    Validates and creates the complete temp_files directory structure

.DESCRIPTION
    Ensures all required temp_files directories exist before Type1/Type2 execution.
    Creates the standardized directory structure for session-based file organization.
    This implements v3.0 architecture requirement for organized data flow.

.PARAMETER ValidateOnly
    When specified, only validates existing structure without creating directories

.EXAMPLE
    Initialize-TempFilesStructure

.EXAMPLE
    $isValid = Initialize-TempFilesStructure -ValidateOnly
#>
function Initialize-TempFilesStructure {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter()]
        [switch]$ValidateOnly
    )
    
    Write-LogEntry -Level 'INFO' -Component 'CORE-INFRASTRUCTURE' -Message 'Initializing temp_files directory structure'
    
    try {
        # Determine temp files root using global path discovery
        $tempRoot = $null
        try {
            $tempRoot = Get-MaintenanceProjectPath -PathType 'TempFiles'
        }
        catch {
            if ($env:MAINTENANCE_TEMP_ROOT) {
                $tempRoot = $env:MAINTENANCE_TEMP_ROOT
            }
            else {
                Write-Warning "Cannot determine temp files root - attempting to initialize global paths"
                Initialize-GlobalPathDiscovery
                $tempRoot = Get-MaintenanceProjectPath -PathType 'TempFiles'
            }
        }
        
        # Define required directory structure (v3.0 Split Architecture)
        $requiredDirectories = @(
            'data',                        # Type1 audit results
            'temp',                        # Processing diffs
            'reports',                     # Temporary report data
            'logs',                        # Base logs directory
            'logs\bloatware-removal',      # BloatwareRemoval execution logs
            'logs\essential-apps',         # EssentialApps execution logs
            'logs\system-optimization',    # SystemOptimization execution logs
            'logs\telemetry-disable',      # TelemetryDisable execution logs
            'logs\windows-updates',        # WindowsUpdates execution logs
            'processed',                   # v3.0: LogProcessor output directory
            'processed\module-specific',   # v3.0: Module-specific processed data
            'processed\charts-data',       # v3.0: Chart generation data
            'processed\analytics'          # v3.0: Analytics and metrics data
        )
        
        $allPathsValid = $true
        $createdPaths = @()
        $validatedPaths = @()
        
        foreach ($directory in $requiredDirectories) {
            $fullPath = Join-Path $tempRoot $directory
            
            if (Test-Path $fullPath -PathType Container) {
                $validatedPaths += $fullPath
                Write-Verbose "✓ Validated: $directory"
            }
            elseif (-not $ValidateOnly) {
                try {
                    New-Item -Path $fullPath -ItemType Directory -Force | Out-Null
                    $createdPaths += $fullPath
                    Write-Verbose "✓ Created: $directory"
                }
                catch {
                    Write-LogEntry -Level 'ERROR' -Component 'CORE-INFRASTRUCTURE' -Message "Failed to create directory: $directory" -Data @{ Error = $_.Exception.Message }
                    $allPathsValid = $false
                }
            }
            else {
                Write-Verbose "✗ Missing: $directory"
                $allPathsValid = $false
            }
        }
        
        # Initialize v3.0 processed data structure as part of temp files setup
        if ($allPathsValid) {
            $processedValid = Initialize-ProcessedDataStructure -ValidateOnly:$ValidateOnly
            $allPathsValid = $allPathsValid -and $processedValid
        }
        
        if (-not $ValidateOnly) {
            Write-LogEntry -Level 'SUCCESS' -Component 'CORE-INFRASTRUCTURE' -Message 'Complete temp files structure initialization finished' -Data @{
                TempRoot             = $tempRoot
                TotalDirectories     = $requiredDirectories.Count
                ValidatedDirectories = $validatedPaths.Count
                CreatedDirectories   = $createdPaths.Count
                ProcessedDataValid   = $processedValid
                AllPathsValid        = $allPathsValid
            }
        }
        
        return $allPathsValid
    }
    catch {
        Write-LogEntry -Level 'ERROR' -Component 'CORE-INFRASTRUCTURE' -Message "Failed to initialize temp files structure: $($_.Exception.Message)"
        return $false
    }
}

<#
.SYNOPSIS
    Initializes the processed data directory structure for v3.0 split architecture
.DESCRIPTION
    Creates and validates the processed data directories used by LogProcessor → ReportGenerator pipeline.
    Ensures standardized JSON data exchange locations exist before module execution.
.PARAMETER ValidateOnly
    Only validates existing structure without creating missing directories
#>
function Initialize-ProcessedDataStructure {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter()]
        [switch]$ValidateOnly
    )
    
    Write-LogEntry -Level 'INFO' -Component 'CORE-INFRASTRUCTURE' -Message 'Initializing processed data directory structure for v3.0 split architecture'
    
    try {
        # Get temp files root from global paths
        $tempRoot = $null
        try {
            $tempRoot = Get-MaintenanceProjectPath -PathType 'TempFiles'
        }
        catch {
            Write-LogEntry -Level 'ERROR' -Component 'CORE-INFRASTRUCTURE' -Message 'Global project paths not initialized - call Initialize-GlobalPathDiscovery first'
            return $false
        }
        
        $processedRoot = Join-Path $tempRoot 'processed'
        
        # Define v3.0 processed data structure
        $processedDirectories = @{
            'module-specific' = 'Individual module processing results'
            'charts-data'     = 'Chart generation and visualization data'
            'analytics'       = 'System analytics and calculated metrics'
        }
        
        $allValid = $true
        $createdDirs = @()
        $validatedDirs = @()
        
        # Ensure base processed directory exists
        if (-not (Test-Path $processedRoot -PathType Container)) {
            if (-not $ValidateOnly) {
                try {
                    New-Item -Path $processedRoot -ItemType Directory -Force | Out-Null
                    Write-Verbose "✓ Created base processed directory: $processedRoot"
                }
                catch {
                    Write-LogEntry -Level 'ERROR' -Component 'CORE-INFRASTRUCTURE' -Message "Failed to create processed directory: $($_.Exception.Message)"
                    return $false
                }
            }
            else {
                Write-LogEntry -Level 'WARN' -Component 'CORE-INFRASTRUCTURE' -Message 'Base processed directory does not exist'
                $allValid = $false
            }
        }
        
        # Create/validate subdirectories
        foreach ($dirName in $processedDirectories.Keys) {
            $dirPath = Join-Path $processedRoot $dirName
            $description = $processedDirectories[$dirName]
            
            if (Test-Path $dirPath -PathType Container) {
                $validatedDirs += $dirName
                Write-Verbose "✓ Validated processed subdirectory: $dirName ($description)"
            }
            elseif (-not $ValidateOnly) {
                try {
                    New-Item -Path $dirPath -ItemType Directory -Force | Out-Null
                    $createdDirs += $dirName
                    Write-Verbose "✓ Created processed subdirectory: $dirName ($description)"
                }
                catch {
                    Write-LogEntry -Level 'ERROR' -Component 'CORE-INFRASTRUCTURE' -Message "Failed to create processed subdirectory '$dirName': $($_.Exception.Message)"
                    $allValid = $false
                }
            }
            else {
                Write-LogEntry -Level 'WARN' -Component 'CORE-INFRASTRUCTURE' -Message "Processed subdirectory missing: $dirName ($description)"
                $allValid = $false
            }
        }
        
        # Log initialization results
        if ($ValidateOnly) {
            $message = "Processed data structure validation: $($validatedDirs.Count) directories confirmed"
            if (-not $allValid) {
                $message += " (validation issues found)"
            }
            Write-LogEntry -Level 'INFO' -Component 'CORE-INFRASTRUCTURE' -Message $message
        }
        else {
            $message = "Processed data structure initialized: $($createdDirs.Count) created, $($validatedDirs.Count) validated"
            Write-LogEntry -Level 'SUCCESS' -Component 'CORE-INFRASTRUCTURE' -Message $message
            
            if ($createdDirs.Count -gt 0) {
                Write-LogEntry -Level 'INFO' -Component 'CORE-INFRASTRUCTURE' -Message "Created processed subdirectories: $($createdDirs -join ', ')"
            }
        }
        
        return $allValid
    }
    catch {
        Write-LogEntry -Level 'ERROR' -Component 'CORE-INFRASTRUCTURE' -Message "Failed to initialize processed data structure: $($_.Exception.Message)"
        return $false
    }
}

<#
.SYNOPSIS
    Saves session data to organized file structure
#>
function Save-SessionData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('logs', 'data', 'temp', 'reports')]
        [string]$Category,

        [Parameter(Mandatory)]
        [object]$Data,

        [Parameter(Mandatory)]
        [string]$FileName
    )

    try {
        $filePath = Get-SessionPath -Category $Category -FileName $FileName
        
        if ($Data -is [string]) {
            $Data | Out-File -FilePath $filePath -Encoding UTF8
        }
        else {
            $Data | ConvertTo-Json -Depth 20 -WarningAction SilentlyContinue | Out-File -FilePath $filePath -Encoding UTF8
        }
        
        Write-Verbose "Saved session data to: $filePath"
        return $filePath
    }
    catch {
        Write-Error "Failed to save session data: $($_.Exception.Message)"
        throw
    }
}

<#
.SYNOPSIS
    Gets session data from organized file structure
#>
function Get-SessionData {
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('logs', 'data', 'temp', 'reports')]
        [string]$Category,

        [Parameter(Mandatory)]
        [string]$FileName
    )

    try {
        $filePath = Get-SessionPath -Category $Category -FileName $FileName
        
        if (-not (Test-Path $filePath)) {
            Write-Warning "Session data file not found: $filePath"
            return $null
        }

        $content = Get-Content $filePath -Raw
        
        # Try to parse as JSON, fallback to raw content
        try {
            return $content | ConvertFrom-Json
        }
        catch {
            return $content
        }
    }
    catch {
        Write-Error "Failed to get session data: $($_.Exception.Message)"
        return $null
    }
}

#endregion

#region Compatibility Functions for Orchestrator

<#
.SYNOPSIS
    Gets bloatware configuration in the format expected by orchestrator (compatibility wrapper)
#>
function Get-BloatwareConfiguration {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    try {
        $bloatwareData = Get-BloatwareList -Category 'all'
        
        # Return in expected format with categorized data
        $result = @{
            all = $bloatwareData
        }
        
        # Group by category for compatibility
        $categories = @('OEM', 'Windows', 'Gaming', 'Security')
        foreach ($category in $categories) {
            $categoryData = $bloatwareData | Where-Object { $_.category -eq $category }
            if ($categoryData) {
                $result[$category.ToLower()] = $categoryData
            }
        }
        
        return $result
    }
    catch {
        Write-LogEntry -Level 'ERROR' -Component 'CORE-INFRASTRUCTURE' -Message "Failed to load bloatware configuration: $($_.Exception.Message)"
        return @{ all = @() }
    }
}

<#
.SYNOPSIS
    Gets essential apps configuration in the format expected by orchestrator (compatibility wrapper)
#>
function Get-EssentialAppsConfiguration {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    try {
        $essentialApps = Get-UnifiedEssentialAppsList
        
        # Return in expected format with categorized data
        $result = @{
            all = $essentialApps
        }
        
        # Group by category for compatibility
        $categories = @('productivity', 'development', 'multimedia', 'utilities', 'security')
        foreach ($category in $categories) {
            $categoryData = $essentialApps | Where-Object { $_.category -eq $category }
            if ($categoryData) {
                $result[$category] = $categoryData
            }
        }
        
        return $result
    }
    catch {
        Write-LogEntry -Level 'ERROR' -Component 'CORE-INFRASTRUCTURE' -Message "Failed to load essential apps configuration: $($_.Exception.Message)"
        return @{ all = @() }
    }
}

#endregion

#region Save-OrganizedFile Function
function Save-OrganizedFile {
    <#
    .SYNOPSIS
        Saves content to a file in an organized directory structure
    .DESCRIPTION
        Creates an organized file with proper directory structure and content
    .PARAMETER Content
        The content to save to the file
    .PARAMETER FilePath
        The full path where to save the file
    .PARAMETER Category
        Optional category for session-based organization
    .PARAMETER FileName
        Optional filename for session-based organization
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Content,

        [Parameter(ParameterSetName = 'DirectPath', Mandatory)]
        [string]$FilePath,

        [Parameter(ParameterSetName = 'SessionPath')]
        [ValidateSet('logs', 'data', 'temp', 'reports')]
        [string]$Category,

        [Parameter(ParameterSetName = 'SessionPath')]
        [string]$FileName
    )

    try {
        # Determine the target path
        if ($PSCmdlet.ParameterSetName -eq 'SessionPath') {
            $targetPath = Get-SessionPath -Category $Category -FileName $FileName
        }
        else {
            $targetPath = $FilePath
        }

        # Ensure directory exists
        $directory = Split-Path -Parent $targetPath
        if (-not (Test-Path $directory)) {
            New-Item -Path $directory -ItemType Directory -Force | Out-Null
        }

        # Save the content
        $Content | Out-File -FilePath $targetPath -Encoding UTF8 -Force

        Write-LogEntry -Level 'DEBUG' -Component 'FILE-ORGANIZATION' -Message "File saved successfully" -Data @{
            TargetPath    = $targetPath
            ContentLength = $Content.Length
        }

        return @{
            Success  = $true
            FilePath = $targetPath
            Size     = $Content.Length
        }
    }
    catch {
        Write-LogEntry -Level 'ERROR' -Component 'FILE-ORGANIZATION' -Message "Failed to save file" -Data @{
            TargetPath = $targetPath
            Error      = $_.Exception.Message
        }
        
        return @{
            Success = $false
            Error   = $_.Exception.Message
        }
    }
}

<#
.SYNOPSIS
    Gets standardized paths for processed data files in the v3.0 split architecture
.DESCRIPTION
    Helper function to generate consistent paths for LogProcessor → ReportGenerator data exchange
.PARAMETER Category
    The processed data category (main, module-specific, charts-data, analytics)
.PARAMETER FileName
    The file name within the category
.PARAMETER ModuleName
    Optional module name for module-specific data
#>
function Get-ProcessedDataPath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('main', 'module-specific', 'charts-data', 'analytics')]
        [string]$Category,
        
        [Parameter(Mandatory)]
        [string]$FileName,
        
        [Parameter()]
        [string]$ModuleName
    )
    
    try {
        # Get temp files root from global paths
        $tempRoot = Get-MaintenanceProjectPath -PathType 'TempFiles'
        $processedRoot = Join-Path $tempRoot 'processed'
        
        # Build path based on category
        switch ($Category) {
            'main' {
                $filePath = Join-Path $processedRoot $FileName
            }
            'module-specific' {
                if ([string]::IsNullOrEmpty($ModuleName)) {
                    throw "ModuleName parameter required for module-specific category"
                }
                $moduleDir = Join-Path $processedRoot 'module-specific'
                $filePath = Join-Path $moduleDir "$ModuleName-$FileName"
            }
            'charts-data' {
                $chartsDir = Join-Path $processedRoot 'charts-data'
                $filePath = Join-Path $chartsDir $FileName
            }
            'analytics' {
                $analyticsDir = Join-Path $processedRoot 'analytics'
                $filePath = Join-Path $analyticsDir $FileName
            }
        }
        
        return $filePath
    }
    catch {
        Write-LogEntry -Level 'ERROR' -Component 'CORE-INFRASTRUCTURE' -Message "Failed to get processed data path: $($_.Exception.Message)"
        throw
    }
}

#endregion

# Export all public functions
Export-ModuleMember -Function @(
    # Configuration Management
    'Initialize-ConfigSystem',
    'Get-MainConfig',
    'Get-MainConfigHashtable',
    'ConvertTo-HashtableDeep',
    'Get-BloatwareList',
    'Get-UnifiedEssentialAppsList',
    'Get-BloatwareConfiguration',
    'Get-EssentialAppsConfiguration',
    
    # Logging Management
    'Get-LoggingConfiguration',
    'Initialize-LoggingSystem',
    'Write-LogEntry',
    'Write-StructuredLogEntry',
    'Get-VerbositySetting',
    'Test-ShouldLogOperation',
    'Write-OperationStart',
    'Write-OperationSuccess',
    'Write-OperationFailure',
    'Write-OperationSkipped',
    'Write-DetectionLog',
    'Start-PerformanceTracking',
    'Complete-PerformanceTracking',
    
    # Security and Privilege
    'Assert-AdminPrivilege',
    
    # File Organization
    'Initialize-FileOrganization',
    'Initialize-TempFilesStructure',
    'Initialize-ProcessedDataStructure',
    'Get-SessionPath',
    'Get-ProcessedDataPath',
    'Save-SessionData',
    'Get-SessionData',
    'Save-OrganizedFile'
)

# Auto-initialize global paths when module is imported
try {
    if (-not $script:MaintenanceProjectPaths.Initialized) {
        Initialize-GlobalPathDiscovery -ErrorAction SilentlyContinue
    }
}
catch {
    # Path discovery will be attempted again when needed
    Write-Verbose "Global path discovery will be attempted when required: $($_.Exception.Message)"
}