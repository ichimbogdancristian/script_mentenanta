#Requires -Version 7.0

<#
.SYNOPSIS
    Configuration Manager Module for Windows Maintenance Automation

.DESCRIPTION
    Handles loading, validation, and management of configuration files including
    main config, logging config, bloatware lists, and essential apps lists.

.NOTES
    Module Type: Core Infrastructure
    Dependencies: JSON files in config/ directory
    Author: Windows Maintenance Automation Project
    Version: 1.0.0
#>

using namespace System.Collections.Generic

# Module variables
$script:LoadedConfig = $null
$script:ConfigPaths = @{}
$script:BloatwareLists = @{}
$script:EssentialApps = @{}

#region Public Functions

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
        [string]$ConfigRootPath
    )
    
    Write-Verbose "Initializing configuration system with root path: $ConfigRootPath"
    
    if (-not (Test-Path $ConfigRootPath)) {
        throw "Configuration root path does not exist: $ConfigRootPath"
    }
    
    # Set up configuration paths
    $script:ConfigPaths = @{
        Root = $ConfigRootPath
        MainConfig = Join-Path $ConfigRootPath 'main-config.json'
        LoggingConfig = Join-Path $ConfigRootPath 'logging-config.json'
        BloatwareLists = Join-Path $ConfigRootPath 'bloatware.json'
        EssentialApps = Join-Path $ConfigRootPath 'essential-apps.json'
    }
    
    # Validate required paths
    $requiredPaths = @('MainConfig', 'BloatwareLists', 'EssentialApps')
    foreach ($pathKey in $requiredPaths) {
        $path = $script:ConfigPaths[$pathKey]
        if (-not (Test-Path $path)) {
            throw "Required configuration file does not exist: $path"
        }
    }
    
    Write-Verbose "Configuration system initialized successfully"
}

<#
.SYNOPSIS
    Loads the main configuration file
    
.DESCRIPTION
    Reads and validates the main configuration JSON file, applying defaults for missing values.
    
.EXAMPLE
    $config = Get-MainConfiguration
#>
function Get-MainConfiguration {
    [CmdletBinding()]
    param()
    
    if ($null -ne $script:LoadedConfig) {
        return $script:LoadedConfig
    }
    
    $configPath = $script:ConfigPaths.MainConfig
    
    if (-not (Test-Path $configPath)) {
        Write-Warning "Main configuration file not found at: $configPath. Using defaults."
        $script:LoadedConfig = Get-DefaultConfiguration
        return $script:LoadedConfig
    }
    
    try {
        Write-Verbose "Loading main configuration from: $configPath"
        $configJson = Get-Content $configPath -Raw -ErrorAction Stop
        $config = $configJson | ConvertFrom-Json -ErrorAction Stop
        
        # Merge with defaults to ensure all required properties exist
        $script:LoadedConfig = Merge-ConfigurationWithDefaults -Config $config
        
        Write-Verbose "Main configuration loaded successfully"
        return $script:LoadedConfig
    }
    catch {
        Write-Error "Failed to load configuration from $configPath`: $_"
        Write-Warning "Using default configuration"
        $script:LoadedConfig = Get-DefaultConfiguration
        return $script:LoadedConfig
    }
}

<#
.SYNOPSIS
    Loads logging configuration
    
.DESCRIPTION
    Reads the logging configuration file and returns logging settings.
    
.EXAMPLE
    $loggingConfig = Get-LoggingConfiguration
#>
function Get-LoggingConfiguration {
    [CmdletBinding()]
    param()
    
    $configPath = $script:ConfigPaths.LoggingConfig
    
    if (-not (Test-Path $configPath)) {
        Write-Verbose "Logging configuration file not found. Using defaults."
        return Get-DefaultLoggingConfiguration
    }
    
    try {
        Write-Verbose "Loading logging configuration from: $configPath"
        $configJson = Get-Content $configPath -Raw -ErrorAction Stop
        $config = $configJson | ConvertFrom-Json -ErrorAction Stop
        
        # Merge with defaults
        $defaultConfig = Get-DefaultLoggingConfiguration
        return Merge-HashTables -Default $defaultConfig -Override $config
    }
    catch {
        Write-Error "Failed to load logging configuration from $configPath`: $_"
        Write-Warning "Using default logging configuration"
        return Get-DefaultLoggingConfiguration
    }
}

<#
.SYNOPSIS
    Loads all bloatware lists from configuration files
    
.DESCRIPTION
    Reads the consolidated bloatware.json file and loads all bloatware categories.
    
.EXAMPLE
    $bloatwareLists = Get-BloatwareConfiguration
#>
function Get-BloatwareConfiguration {
    [CmdletBinding()]
    param()
    
    if ($script:BloatwareLists.Count -gt 0) {
        return $script:BloatwareLists
    }
    
    $bloatwareFile = $script:ConfigPaths.BloatwareLists
    
    if (-not (Test-Path $bloatwareFile)) {
        Write-Warning "Bloatware configuration file not found: $bloatwareFile"
        return @{}
    }
    
    try {
        Write-Verbose "Loading bloatware configuration from: $bloatwareFile"
        
        $configJson = Get-Content $bloatwareFile -Raw -ErrorAction Stop
        $bloatwareConfig = $configJson | ConvertFrom-Json -ErrorAction Stop
        
        # Convert the object properties to the script variable format
        foreach ($category in $bloatwareConfig.PSObject.Properties) {
            $categoryName = $category.Name
            $categoryList = $category.Value
            
            # Convert to array if it's not already
            if ($categoryList -is [Array]) {
                $script:BloatwareLists[$categoryName] = $categoryList
            } else {
                $script:BloatwareLists[$categoryName] = @($categoryList)
            }
            
            Write-Verbose "Loaded bloatware category '$categoryName' with $($script:BloatwareLists[$categoryName].Count) entries"
        }
        
        Write-Verbose "Loaded $($script:BloatwareLists.Keys.Count) bloatware categories"
        return $script:BloatwareLists
    }
    catch {
        Write-Error "Failed to load bloatware configuration: $_"
        return @{}
    }
}

<#
.SYNOPSIS
    Loads all essential apps lists from configuration files
    
.DESCRIPTION
    Reads the consolidated essential-apps.json file and groups apps by category.
    
.EXAMPLE
    $essentialApps = Get-EssentialAppsConfiguration
#>
function Get-EssentialAppsConfiguration {
    [CmdletBinding()]
    param()
    
    if ($script:EssentialApps.Count -gt 0) {
        return $script:EssentialApps
    }
    
    $appsFile = $script:ConfigPaths.EssentialApps
    
    if (-not (Test-Path $appsFile)) {
        Write-Warning "Essential apps configuration file not found: $appsFile"
        return @{}
    }
    
    try {
        Write-Verbose "Loading essential apps configuration from: $appsFile"
        
        $configJson = Get-Content $appsFile -Raw -ErrorAction Stop
        $appsArray = $configJson | ConvertFrom-Json -ErrorAction Stop
        
        # Group apps by category for backwards compatibility
        $groupedApps = $appsArray | Group-Object -Property category
        
        foreach ($group in $groupedApps) {
            $categoryName = $group.Name.ToLower()
            $categoryApps = $group.Group
            
            $script:EssentialApps[$categoryName] = $categoryApps
            Write-Verbose "Loaded essential apps category '$categoryName' with $($categoryApps.Count) entries"
        }
        
        # Also store the full array for direct access
        $script:EssentialApps['all'] = $appsArray
        
        Write-Verbose "Loaded $($script:EssentialApps.Keys.Count) essential apps categories"
        return $script:EssentialApps
    }
    catch {
        Write-Error "Failed to load essential apps configuration: $_"
        return @{}
    }
}

<#
.SYNOPSIS
    Gets a unified bloatware list from all categories
    
.DESCRIPTION
    Combines all bloatware categories into a single deduplicated list.
    
.PARAMETER IncludeCategories
    Specific categories to include (default: all)
    
.EXAMPLE
    $allBloatware = Get-UnifiedBloatwareList
    $oemOnly = Get-UnifiedBloatwareList -IncludeCategories @('oem-bloatware')
#>
function Get-UnifiedBloatwareList {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string[]]$IncludeCategories = @()
    )
    
    $bloatwareLists = Get-BloatwareConfiguration
    $unifiedList = [List[string]]::new()
    
    $categoriesToProcess = if ($IncludeCategories.Count -gt 0) { 
        $IncludeCategories 
    } else { 
        $bloatwareLists.Keys 
    }
    
    foreach ($category in $categoriesToProcess) {
        if ($bloatwareLists.ContainsKey($category)) {
            foreach ($item in $bloatwareLists[$category]) {
                if (-not $unifiedList.Contains($item)) {
                    $unifiedList.Add($item)
                }
            }
        } else {
            Write-Warning "Bloatware category not found: $category"
        }
    }
    
    return $unifiedList.ToArray() | Sort-Object
}

<#
.SYNOPSIS
    Gets a unified essential apps list from all categories
    
.DESCRIPTION
    Combines all essential apps categories into a single list with metadata.
    
.PARAMETER IncludeCategories
    Specific categories to include (default: all)
    
.EXAMPLE
    $allApps = Get-UnifiedEssentialAppsList
    $browsersOnly = Get-UnifiedEssentialAppsList -IncludeCategories @('web-browsers')
#>
function Get-UnifiedEssentialAppsList {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string[]]$IncludeCategories = @()
    )
    
    $appLists = Get-EssentialAppsConfiguration
    $unifiedList = [List[PSCustomObject]]::new()
    
    $categoriesToProcess = if ($IncludeCategories.Count -gt 0) { 
        $IncludeCategories 
    } else { 
        $appLists.Keys 
    }
    
    foreach ($category in $categoriesToProcess) {
        if ($appLists.ContainsKey($category)) {
            foreach ($app in $appLists[$category]) {
                # Ensure each app has the source category
                if ($app -is [PSCustomObject]) {
                    $app | Add-Member -NotePropertyName 'SourceCategory' -NotePropertyValue $category -Force
                    $unifiedList.Add($app)
                } else {
                    # Handle string entries by converting to objects
                    $appObj = [PSCustomObject]@{
                        name = $app
                        winget = $null
                        choco = $null
                        category = 'Unknown'
                        SourceCategory = $category
                    }
                    $unifiedList.Add($appObj)
                }
            }
        } else {
            Write-Warning "Essential apps category not found: $category"
        }
    }
    
    return $unifiedList.ToArray()
}

<#
.SYNOPSIS
    Saves the current configuration back to files
    
.DESCRIPTION
    Writes the current configuration state back to the JSON configuration files.
    
.PARAMETER Configuration
    The configuration object to save
    
.EXAMPLE
    Save-Configuration -Configuration $modifiedConfig
#>
function Save-Configuration {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Configuration
    )
    
    $configPath = $script:ConfigPaths.MainConfig
    
    if ($PSCmdlet.ShouldProcess($configPath, "Save Configuration")) {
        try {
            $configJson = $Configuration | ConvertTo-Json -Depth 10 -ErrorAction Stop
            $configJson | Out-File -FilePath $configPath -Encoding UTF8 -ErrorAction Stop
            
            # Update loaded config
            $script:LoadedConfig = $Configuration
            
            Write-Verbose "Configuration saved to: $configPath"
        }
        catch {
            throw "Failed to save configuration to $configPath`: $_"
        }
    }
}

#endregion

#region Private Functions

<#
.SYNOPSIS
    Gets the default configuration object
#>
function Get-DefaultConfiguration {
    return [PSCustomObject]@{
        execution = [PSCustomObject]@{
            defaultMode = 'unattended'
            countdownSeconds = 20
            enableDryRun = $true
            autoSelectDefault = $true
            showProgressBars = $true
        }
        modules = [PSCustomObject]@{
            skipBloatwareRemoval = $false
            skipEssentialApps = $false
            skipWindowsUpdates = $false
            skipTelemetryDisable = $false
            skipSystemOptimization = $false
            skipSecurityAudit = $false
            customModulesPath = ''
        }
        bloatware = [PSCustomObject]@{
            enableDiffBasedProcessing = $true
            parallelRemoval = $true
            createBackups = $true
            customBloatwareList = @()
        }
        essentialApps = [PSCustomObject]@{
            enableParallelInstallation = $true
            fallbackToLibreOffice = $true
            customEssentialApps = @()
            skipConflictResolution = $false
        }
        system = [PSCustomObject]@{
            createSystemRestorePoint = $true
            enableVerboseLogging = $false
            maxLogSizeMB = 10
            enablePerformanceOptimizations = $true
            moveBatchLogToOrchestrator = $true
        }
        reporting = [PSCustomObject]@{
            enableHtmlReport = $true
            enableDetailedAudit = $true
            includeSystemInventory = $true
            generateBeforeAfterComparison = $true
        }
        paths = [PSCustomObject]@{
            tempFolder = 'temp_files'
            reportsFolder = 'temp_files/reports'
            logsFolder = 'temp_files/logs'
            inventoryFolder = 'temp_files/inventory'
        }
    }
}

<#
.SYNOPSIS
    Gets the default logging configuration
#>
function Get-DefaultLoggingConfiguration {
    return @{
        logging = @{
            logLevel = 'INFO'
            enableConsoleOutput = $true
            enableFileOutput = $true
            enableProgressBars = $true
            coloredOutput = $true
            maxLogSizeMB = 10
            logRotation = $true
            keepLogFiles = 5
        }
        formatting = @{
            dateTimeFormat = 'yyyy-MM-dd HH:mm:ss'
            messageFormat = '[{timestamp}] [{level}] [{component}] {message}'
            progressBarStyle = 'detailed'
        }
        levels = @{
            DEBUG = @{ enabled = $false; color = 'Gray' }
            INFO = @{ enabled = $true; color = 'White' }
            SUCCESS = @{ enabled = $true; color = 'Green' }
            WARN = @{ enabled = $true; color = 'Yellow' }
            ERROR = @{ enabled = $true; color = 'Red' }
            CRITICAL = @{ enabled = $true; color = 'Magenta' }
        }
        components = @{
            BAT = 'Batch Launcher'
            ORCHESTRATOR = 'Main Orchestrator'
            TYPE1 = 'Inventory/Reporting'
            TYPE2 = 'System Modification'
            CONFIG = 'Configuration Manager'
            MENU = 'Interactive Menu'
        }
    }
}

<#
.SYNOPSIS
    Merges configuration with defaults
#>
function Merge-ConfigurationWithDefaults {
    param(
        [PSCustomObject]$Config
    )
    
    $defaults = Get-DefaultConfiguration
    return Merge-PSCustomObjects -Default $defaults -Override $Config
}

<#
.SYNOPSIS
    Merges two PSCustomObject instances
#>
function Merge-PSCustomObjects {
    param(
        [PSCustomObject]$Default,
        [PSCustomObject]$Override
    )
    
    $result = $Default.PSObject.Copy()
    
    foreach ($property in $Override.PSObject.Properties) {
        if ($result.PSObject.Properties.Name -contains $property.Name) {
            if ($property.Value -is [PSCustomObject] -and $result.($property.Name) -is [PSCustomObject]) {
                $result.($property.Name) = Merge-PSCustomObjects -Default $result.($property.Name) -Override $property.Value
            } else {
                $result.($property.Name) = $property.Value
            }
        } else {
            $result | Add-Member -NotePropertyName $property.Name -NotePropertyValue $property.Value
        }
    }
    
    return $result
}

<#
.SYNOPSIS
    Merges hash tables
#>
function Merge-HashTables {
    param(
        [hashtable]$Default,
        [PSCustomObject]$Override
    )
    
    $result = $Default.Clone()
    
    foreach ($property in $Override.PSObject.Properties) {
        if ($result.ContainsKey($property.Name)) {
            if ($property.Value -is [PSCustomObject] -and $result[$property.Name] -is [hashtable]) {
                # Convert PSCustomObject to hashtable for nested merging
                $overrideHash = @{}
                foreach ($subProp in $property.Value.PSObject.Properties) {
                    $overrideHash[$subProp.Name] = $subProp.Value
                }
                $result[$property.Name] = Merge-HashTables -Default $result[$property.Name] -Override $overrideHash
            } else {
                $result[$property.Name] = $property.Value
            }
        } else {
            $result[$property.Name] = $property.Value
        }
    }
    
    return $result
}

#endregion

#region Logging Functions

<#
.SYNOPSIS
    Writes log messages to file and console based on logging configuration

.PARAMETER Message
    The message to log

.PARAMETER Level
    Log level (DEBUG, INFO, SUCCESS, WARN, ERROR, CRITICAL)

.PARAMETER Component
    Component name for the log entry

.PARAMETER LogFilePath
    Path to the log file (uses global variable if not specified)
#>
function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        
        [Parameter()]
        [ValidateSet('DEBUG', 'INFO', 'SUCCESS', 'WARN', 'ERROR', 'CRITICAL')]
        [string]$Level = 'INFO',
        
        [Parameter()]
        [string]$Component = 'SYSTEM',
        
        [Parameter()]
        [string]$LogFilePath
    )
    
    try {
        # Get logging configuration
        $loggingConfig = Get-LoggingConfiguration
        
        # Check if level is enabled
        if (-not $loggingConfig.levels.$Level.enabled) {
            return
        }
        
        # Determine log file paths
        $mainLogPath = $LogFilePath
        if (-not $mainLogPath -and $Global:MaintenanceLogFile) {
            $mainLogPath = $Global:MaintenanceLogFile
        }
        
        # Create component-specific log file path
        $componentLogPath = $null
        if ($mainLogPath -and $Component -ne 'SYSTEM') {
            $logDir = Split-Path $mainLogPath -Parent
            $componentFileName = "$Component-$(Get-Date -Format 'yyyy-MM-dd').log"
            $componentLogPath = Join-Path $logDir $componentFileName
        }
        
        # Format timestamp
        $timestamp = Get-Date -Format $loggingConfig.formatting.dateTimeFormat
        
        # Format message
        $formattedMessage = $loggingConfig.formatting.messageFormat -replace '\{timestamp\}', $timestamp -replace '\{level\}', $Level -replace '\{component\}', $Component -replace '\{message\}', $Message
        
        # Console output
        if ($loggingConfig.logging.enableConsoleOutput) {
            $color = $loggingConfig.levels.$Level.color
            if ($loggingConfig.logging.coloredOutput -and $color) {
                Write-Host $formattedMessage -ForegroundColor $color
            } else {
                Write-Host $formattedMessage
            }
        }
        
        # File output - Write to main log file
        if ($loggingConfig.logging.enableFileOutput -and $mainLogPath) {
            # Ensure log directory exists
            $logDir = Split-Path $mainLogPath -Parent
            if ($logDir -and $logDir.Length -gt 0 -and -not (Test-Path $logDir)) {
                New-Item -Path $logDir -ItemType Directory -Force | Out-Null
            }
            
            # Append to main log file
            $formattedMessage | Add-Content -Path $mainLogPath -Encoding UTF8
        }
        
        # Component-specific file output
        if ($loggingConfig.logging.enableFileOutput -and $componentLogPath) {
            # Ensure log directory exists
            $componentLogDir = Split-Path $componentLogPath -Parent
            if ($componentLogDir -and $componentLogDir.Length -gt 0 -and -not (Test-Path $componentLogDir)) {
                New-Item -Path $componentLogDir -ItemType Directory -Force | Out-Null
            }
            
            # Append to component-specific log file
            $formattedMessage | Add-Content -Path $componentLogPath -Encoding UTF8
            
            # Store component log path for later retrieval
            if (-not $Global:ComponentLogFiles) {
                $Global:ComponentLogFiles = @{}
            }
            $Global:ComponentLogFiles[$Component] = $componentLogPath
        }

        # Additionally write to a per-module log file if orchestrator requested one
        if ($Global:ModuleLogFile) {
            try {
                $moduleLogDir = Split-Path $Global:ModuleLogFile -Parent
                if (-not (Test-Path $moduleLogDir)) { New-Item -Path $moduleLogDir -ItemType Directory -Force | Out-Null }
                $formattedMessage | Add-Content -Path $Global:ModuleLogFile -Encoding UTF8 -ErrorAction SilentlyContinue
            } catch {
                Write-Warning "Failed to write to module log $Global:ModuleLogFile: $($_.Exception.Message)"
            }
        }
    }
    catch {
        Write-Warning "Failed to write log: $_"
    }
}

<#
.SYNOPSIS
    Gets the log file paths for all components

.DESCRIPTION
    Returns a hashtable with component names and their corresponding log file paths

.EXAMPLE
    Get-ComponentLogFiles
#>
function Get-ComponentLogFiles {
    [CmdletBinding()]
    param()
    
    if ($Global:ComponentLogFiles) {
        return $Global:ComponentLogFiles
    }
    
    return @{}
}

<#
.SYNOPSIS
    Reads the content of a component's log file

.DESCRIPTION
    Returns the log entries for a specific component from its dedicated log file

.PARAMETER Component
    The component name to read logs for

.EXAMPLE
    Get-ComponentLogContent -Component 'MODULE_EXECUTOR'
#>
function Get-ComponentLogContent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Component
    )
    
    $componentLogs = Get-ComponentLogFiles
    
    if ($componentLogs.ContainsKey($Component) -and (Test-Path $componentLogs[$Component])) {
        return Get-Content -Path $componentLogs[$Component] -Encoding UTF8
    }
    
    return @()
}

<#
.SYNOPSIS
    Gets the standardized inventory folder path

.DESCRIPTION
    Returns the canonical inventory folder path based on configuration, creating 
    the directory if it doesn't exist.

.PARAMETER ConfigurationOverride
    Optional configuration object to use instead of loading from file

.EXAMPLE
    $inventoryFolder = Get-InventoryFolder
    
.EXAMPLE
    $inventoryFolder = Get-InventoryFolder -ConfigurationOverride $customConfig
#>
function Get-InventoryFolder {
    [CmdletBinding()]
    param(
        [Parameter()]
        [PSCustomObject]$ConfigurationOverride
    )
    
    # Get configuration
    $config = if ($ConfigurationOverride) { 
        $ConfigurationOverride 
    } else { 
        Get-MainConfiguration 
    }
    
    # Determine base working directory
    $workingDir = if ($PSScriptRoot) {
        Join-Path $PSScriptRoot '..\..\..' | Resolve-Path -ErrorAction SilentlyContinue
    } else {
        Get-Location
    }
    
    # Get inventory folder path from config
    $inventoryFolder = if ($config.paths.inventoryFolder) {
        if ([System.IO.Path]::IsPathRooted($config.paths.inventoryFolder)) {
            $config.paths.inventoryFolder
        } else {
            Join-Path $workingDir $config.paths.inventoryFolder
        }
    } else {
        Join-Path $workingDir 'temp_files\inventory'
    }
    
    # Ensure directory exists
    if (-not (Test-Path $inventoryFolder)) {
        New-Item -Path $inventoryFolder -ItemType Directory -Force | Out-Null
    }
    
    return $inventoryFolder
}

<#
.SYNOPSIS
    Gets standardized inventory file paths for exports

.DESCRIPTION
    Returns canonical file paths for inventory exports with standardized naming
    including module name, hostname, timestamp, and format.

.PARAMETER ModuleName
    The name of the module creating the inventory export

.PARAMETER Format
    The export format (JSON, XML, CSV, or All)

.PARAMETER IncludeTimestamp
    Whether to include timestamp in filename (default: true)

.PARAMETER InventoryFolder
    Base inventory folder (uses Get-InventoryFolder if not specified)

.EXAMPLE
    $paths = Get-StandardInventoryPath -ModuleName 'SystemInventory' -Format 'JSON'
    
.EXAMPLE
    $paths = Get-StandardInventoryPath -ModuleName 'BloatwareDetection' -Format 'All'
#>
function Get-StandardInventoryPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ModuleName,
        
        [Parameter()]
        [ValidateSet('JSON', 'XML', 'CSV', 'All')]
        [string]$Format = 'JSON',
        
        [Parameter()]
        [switch]$IncludeTimestamp = $true,
        
        [Parameter()]
        [string]$InventoryFolder
    )
    
    # Get inventory folder
    if (-not $InventoryFolder) {
        $InventoryFolder = Get-InventoryFolder
    }
    
    # Generate standardized filename components
    $hostname = $env:COMPUTERNAME
    $timestamp = if ($IncludeTimestamp) { "-$(Get-Date -Format 'yyyyMMdd-HHmmss')" } else { "" }
    $baseFileName = "$ModuleName-inventory-$hostname$timestamp"
    
    # Return paths based on format
    $paths = @{}
    
    if ($Format -eq 'All') {
        $paths.JSON = Join-Path $InventoryFolder "$baseFileName.json"
        $paths.XML = Join-Path $InventoryFolder "$baseFileName.xml"
        $paths.CSV = Join-Path $InventoryFolder "$baseFileName-csv"  # Directory for CSV files
    } else {
        $extension = $Format.ToLower()
        if ($Format -eq 'CSV') {
            $paths.CSV = Join-Path $InventoryFolder "$baseFileName-csv"  # Directory for CSV files
        } else {
            $paths[$Format] = Join-Path $InventoryFolder "$baseFileName.$extension"
        }
    }
    
    return $paths
}

<#
.SYNOPSIS
    Gets or creates the log file path for a specific module

.DESCRIPTION
    Returns the standardized log file path for a module and registers it in 
    $Global:ComponentLogFiles for easy retrieval. Creates the log directory if needed.

.PARAMETER ModuleName
    The name of the module to get the log path for

.PARAMETER LogDirectory
    The base log directory (uses global maintenance log dir if not specified)

.EXAMPLE
    $logPath = Get-ModuleLogPath -ModuleName 'SystemInventory'
    
.EXAMPLE
    $logPath = Get-ModuleLogPath -ModuleName 'BloatwareDetection' -LogDirectory 'C:\Logs'
#>
function Get-ModuleLogPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ModuleName,
        
        [Parameter()]
        [string]$LogDirectory
    )
    
    # Determine log directory
    if (-not $LogDirectory) {
        if ($Global:MaintenanceLogFile) {
            $LogDirectory = Split-Path $Global:MaintenanceLogFile -Parent
        } else {
            # Fallback to temp_files/logs in working directory
            $workingDir = if ($PSScriptRoot) { 
                Join-Path $PSScriptRoot '..\..\..' | Resolve-Path -ErrorAction SilentlyContinue
            } else {
                Get-Location
            }
            $LogDirectory = Join-Path $workingDir 'temp_files\logs'
        }
    }
    
    # Ensure log directory exists
    if (-not (Test-Path $LogDirectory)) {
        New-Item -Path $LogDirectory -ItemType Directory -Force | Out-Null
    }
    
    # Generate standardized log file name with current date
    $logFileName = "$ModuleName-$(Get-Date -Format 'yyyy-MM-dd').log"
    $logPath = Join-Path $LogDirectory $logFileName
    
    # Register in global component log files for easy retrieval
    if (-not $Global:ComponentLogFiles) {
        $Global:ComponentLogFiles = @{}
    }
    $Global:ComponentLogFiles[$ModuleName] = $logPath
    
    return $logPath
}

#endregion

# Export module functions
Export-ModuleMember -Function @(
    'Initialize-ConfigSystem',
    'Get-MainConfiguration',
    'Get-LoggingConfiguration', 
    'Get-BloatwareConfiguration',
    'Get-EssentialAppsConfiguration',
    'Get-UnifiedBloatwareList',
    'Get-UnifiedEssentialAppsList',
    'Save-Configuration',
    'Write-Log',
    'Get-ComponentLogFiles',
    'Get-ComponentLogContent',
    'Get-ModuleLogPath',
    'Get-InventoryFolder',
    'Get-StandardInventoryPath'
)