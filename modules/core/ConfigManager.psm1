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

# Import LoggingManager for structured logging (with graceful fallback)
try {
    $loggingManagerPath = Join-Path $PSScriptRoot 'LoggingManager.psm1'
    if (Test-Path $loggingManagerPath) {
        Import-Module $loggingManagerPath -Force -ErrorAction SilentlyContinue
    }
}
catch {
    # LoggingManager not available, continue without structured logging
}

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
        [ValidateNotNullOrEmpty()]
        [ValidateScript({ Test-Path $_ -PathType Container })]
        [string]$ConfigRootPath
    )

    # Start performance tracking for configuration initialization
    $perfContext = $null
    try {
        $perfContext = Start-PerformanceTracking -OperationName 'ConfigSystemInitialization' -Component 'CONFIG-MANAGER'
        Write-LogEntry -Level 'INFO' -Component 'CONFIG-MANAGER' -Message 'Starting configuration system initialization' -Data @{ ConfigRootPath = $ConfigRootPath }
    }
    catch {
        # LoggingManager not available, continue with standard logging
    }

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

    # Validate required paths
    $requiredPaths = @('MainConfig', 'BloatwareList', 'EssentialApps')
    foreach ($pathKey in $requiredPaths) {
        $path = $script:ConfigPaths[$pathKey]
        if (-not (Test-Path $path)) {
            throw "Required configuration file does not exist: $path"
        }
    }

    # Complete performance tracking and structured logging
    try {
        Complete-PerformanceTracking -PerformanceContext $perfContext -Success $true -ResultData @{
            ConfigRootPath = $ConfigRootPath
            ValidatedPaths = $requiredPaths.Count
            ConfigPaths    = $script:ConfigPaths.Keys -join ', '
        }
        Write-LogEntry -Level 'SUCCESS' -Component 'CONFIG-MANAGER' -Message 'Configuration system initialization completed successfully' -Data @{ ConfigRootPath = $ConfigRootPath; ValidatedPaths = $requiredPaths.Count }
    }
    catch {
        # LoggingManager not available, continue with standard logging
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
    [OutputType([PSCustomObject])]
    param()

    if ($null -ne $script:LoadedConfig) {
        return $script:LoadedConfig
    }

    # Start performance tracking for configuration loading
    $perfContext = $null
    try {
        $perfContext = Start-PerformanceTracking -OperationName 'MainConfigurationLoad' -Component 'CONFIG-MANAGER'
        Write-LogEntry -Level 'INFO' -Component 'CONFIG-MANAGER' -Message 'Loading main configuration'
    }
    catch {
        # LoggingManager not available, continue with standard logging
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

        # Convert to hashtable for validation
        $configHash = @{}
        foreach ($property in $config.PSObject.Properties) {
            if ($property.Value -is [PSCustomObject]) {
                $configHash[$property.Name] = @{}
                foreach ($subProperty in $property.Value.PSObject.Properties) {
                    $configHash[$property.Name][$subProperty.Name] = $subProperty.Value
                }
            }
            else {
                $configHash[$property.Name] = $property.Value
            }
        }

        # Validate configuration schema
        Write-Verbose "Validating main configuration schema"
        try {
            $validationResult = Test-ConfigurationSchema -ConfigData $configHash -SchemaType 'MainConfig'
            
            if (-not $validationResult.IsValid) {
                if ($validationResult.Issues -and $validationResult.Issues.Count -gt 0) {
                    Write-Warning "Main configuration validation failed with $($validationResult.Issues.Count) issues:"
                    foreach ($issue in $validationResult.Issues) {
                        Write-Warning "  - $issue"
                    }
                }
                else {
                    Write-Warning "Main configuration validation failed (no specific issues available)"
                }
                Write-Warning "Proceeding with default configuration values for invalid properties"
            }
        }
        catch {
            Write-Warning "Configuration validation encountered an error: $_"
            Write-Warning "Skipping validation and proceeding with loaded configuration"
        }

        # Merge with defaults to ensure all required properties exist
        $script:LoadedConfig = Merge-ConfigurationWithDefault -Config $config

        # Complete performance tracking for successful load
        try {
            Complete-PerformanceTracking -PerformanceContext $perfContext -Success $true -ResultData @{
                ConfigPath       = $configPath
                ConfigLoaded     = $true
                ValidationStatus = if ($validationResult.IsValid) { 'Valid' } else { 'DefaultsApplied' }
            }
            Write-LogEntry -Level 'SUCCESS' -Component 'CONFIG-MANAGER' -Message 'Main configuration loaded and validated successfully' -Data @{ ConfigPath = $configPath }
        }
        catch {
            # LoggingManager not available, continue with standard logging
        }

        Write-Verbose "Main configuration loaded and validated successfully"
        return $script:LoadedConfig
    }
    catch {
        Write-Error "Failed to load configuration from $configPath`: $_"
        Write-Warning "Using default configuration"
        
        # Complete performance tracking for failed load
        try {
            Complete-PerformanceTracking -PerformanceContext $perfContext -Success $false -ResultData @{
                ConfigPath   = $configPath
                Error        = $_.Exception.Message
                FallbackUsed = $true
            }
            Write-LogEntry -Level 'WARN' -Component 'CONFIG-MANAGER' -Message 'Main configuration load failed, using defaults' -Data @{ ConfigPath = $configPath; Error = $_.Exception.Message }
        }
        catch {
            # LoggingManager not available, continue with standard logging
        }
        
        $script:LoadedConfig = Get-DefaultConfiguration
        return $script:LoadedConfig
    }
}

<#
.SYNOPSIS
    Retrieves a configuration value using dot-path notation with defaults

.DESCRIPTION
    Provides convenient access to nested configuration values without requiring
    callers to manually traverse the configuration object. Accepts dotted paths
    (for example "inventory.cacheExpirationMinutes") and falls back to the
    supplied default when the path is missing or empty.

.PARAMETER Name
    Dot-delimited configuration path (alias: Path)

.PARAMETER Default
    Default value returned when the requested configuration path is undefined
    or resolves to an empty string.
#>
function Get-ConfigValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [Alias('Path')]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Position = 1)]
        [object]$Default
    )

    try {
        $config = Get-MainConfiguration
        $value = Get-NestedProperty -Object $config -PropertyPath $Name

        if ($null -ne $value) {
            if ($value -is [string]) {
                if (-not [string]::IsNullOrWhiteSpace($value)) {
                    return $value
                }
            }
            else {
                return $value
            }
        }
    }
    catch {
        Write-Verbose "Get-ConfigValue failed for path '$Name': $($_.Exception.Message)"
    }

    return $Default
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
    [OutputType([hashtable])]
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

        # Convert to hashtable for validation
        $configHash = @{}
        foreach ($property in $config.PSObject.Properties) {
            if ($property.Value -is [PSCustomObject]) {
                $configHash[$property.Name] = @{}
                foreach ($subProperty in $property.Value.PSObject.Properties) {
                    if ($subProperty.Value -is [PSCustomObject]) {
                        $configHash[$property.Name][$subProperty.Name] = @{}
                        foreach ($subSubProperty in $subProperty.Value.PSObject.Properties) {
                            $configHash[$property.Name][$subProperty.Name][$subSubProperty.Name] = $subSubProperty.Value
                        }
                    }
                    else {
                        $configHash[$property.Name][$subProperty.Name] = $subProperty.Value
                    }
                }
            }
            else {
                $configHash[$property.Name] = $property.Value
            }
        }

        # Validate configuration schema
        Write-Verbose "Validating logging configuration schema"
        try {
            $validationResult = Test-ConfigurationSchema -ConfigData $configHash -SchemaType 'LoggingConfig'
            
            if (-not $validationResult.IsValid) {
                if ($validationResult.Issues -and $validationResult.Issues.Count -gt 0) {
                    Write-Warning "Logging configuration validation failed with $($validationResult.Issues.Count) issues:"
                    foreach ($issue in $validationResult.Issues) {
                        Write-Warning "  - $issue"
                    }
                }
                else {
                    Write-Warning "Logging configuration validation failed (no specific issues available)"
                }
                Write-Warning "Proceeding with default values for invalid properties"
            }
        }
        catch {
            Write-Warning "Logging configuration validation encountered an error: $_"
            Write-Warning "Skipping validation and proceeding with loaded configuration"
        }

        # Merge with defaults
        $defaultConfig = Get-DefaultLoggingConfiguration
        return Merge-HashTable -Default $defaultConfig -Override $config
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
    Reads all JSON files in the bloatware-lists directory and combines them into categories.

.EXAMPLE
    $bloatwareLists = Get-BloatwareConfiguration
#>
function Get-BloatwareConfiguration {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    if ($script:BloatwareLists.Count -gt 0) {
        return $script:BloatwareLists
    }

    # Load from main consolidated list first
    $bloatwareFile = Join-Path $script:ConfigPaths.Root "lists\bloatware-list.json"
    
    if (Test-Path $bloatwareFile) {
        try {
            Write-Verbose "Loading consolidated bloatware configuration from: $bloatwareFile"
            $configJson = Get-Content $bloatwareFile -Raw -ErrorAction Stop
            $bloatwareList = $configJson | ConvertFrom-Json -ErrorAction Stop
            
            # Convert to array if it's not already
            if ($bloatwareList -is [Array]) {
                $script:BloatwareLists['all'] = $bloatwareList
            }
            elseif ($bloatwareList.all) {
                $script:BloatwareLists['all'] = @($bloatwareList.all)
            }
            else {
                $script:BloatwareLists['all'] = @($bloatwareList)
            }
            
            Write-Verbose "Loaded consolidated bloatware list with $($script:BloatwareLists['all'].Count) entries"
            return $script:BloatwareLists
        }
        catch {
            Write-Warning "Failed to load consolidated bloatware list: $_"
        }
    }
    
    # Fallback: Load from individual category files in bloatware-lists directory
    $bloatwareListsDir = Join-Path $script:ConfigPaths.Root "bloatware-lists"
    
    if (Test-Path $bloatwareListsDir) {
        Write-Verbose "Loading individual bloatware category files from: $bloatwareListsDir"
        
        $allBloatware = @()
        $categoryFiles = @{
            'gaming'   = 'gaming-bloatware.json'
            'oem'      = 'oem-bloatware.json' 
            'security' = 'security-bloatware.json'
            'windows'  = 'windows-bloatware.json'
        }
        
        foreach ($category in $categoryFiles.Keys) {
            $categoryFile = Join-Path $bloatwareListsDir $categoryFiles[$category]
            if (Test-Path $categoryFile) {
                try {
                    $categoryJson = Get-Content $categoryFile -Raw -ErrorAction Stop
                    $categoryList = $categoryJson | ConvertFrom-Json -ErrorAction Stop
                    
                    if ($categoryList -is [Array]) {
                        $script:BloatwareLists[$category] = $categoryList
                        $allBloatware += $categoryList
                        Write-Verbose "Loaded $($categoryList.Count) entries from $($categoryFiles[$category])"
                    }
                }
                catch {
                    Write-Warning "Failed to load $($categoryFiles[$category]): $_"
                }
            }
        }
        
        # Deduplicate and store as 'all' category
        $script:BloatwareLists['all'] = @($allBloatware | Sort-Object -Unique)
        Write-Verbose "Combined bloatware list with $($script:BloatwareLists['all'].Count) unique entries"
        
        return $script:BloatwareLists
    }
    
    # Final fallback: Check legacy path
    $legacyFile = Join-Path $script:ConfigPaths.Root "data\bloatware-list.json"
    
    if (Test-Path $legacyFile) {
        Write-Warning "Using legacy bloatware configuration path - consider migrating to lists/bloatware-list.json"
        try {
            Write-Verbose "Loading legacy bloatware configuration from: $legacyFile"
            $configJson = Get-Content $legacyFile -Raw -ErrorAction Stop
            $bloatwareList = $configJson | ConvertFrom-Json -ErrorAction Stop

            # Convert to array if it's not already
            if ($bloatwareList -is [Array]) {
                $script:BloatwareLists['all'] = $bloatwareList
            }
            elseif ($bloatwareList.all) {
                $script:BloatwareLists['all'] = @($bloatwareList.all)
            }
            else {
                $script:BloatwareLists['all'] = @($bloatwareList)
            }
            
            Write-Verbose "Loaded legacy bloatware list with $($script:BloatwareLists['all'].Count) entries"
            return $script:BloatwareLists
        }
        catch {
            Write-Warning "Failed to load legacy bloatware configuration: $_"
        }
    }
    
    # No configuration found
    Write-Warning "No bloatware configuration found in any expected location"
    $script:BloatwareLists = @{ 'all' = @() }
    return $script:BloatwareLists
}

<#
.SYNOPSIS
    Loads all essential apps lists from configuration files

.DESCRIPTION
    Reads all JSON files in the essential-apps directory and combines them into categories.

.EXAMPLE
    $essentialApps = Get-EssentialAppsConfiguration
#>
function Get-EssentialAppsConfiguration {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    if ($script:EssentialApps.Count -gt 0) {
        return $script:EssentialApps
    }

    $appsFile = Join-Path $script:ConfigPaths.Root "essential-apps.json"

    if (-not (Test-Path $appsFile)) {
        Write-Warning "Essential apps configuration file not found: $appsFile"
        return @{}
    }

    try {
        Write-Verbose "Loading essential apps configuration from: $appsFile"

        $configJson = Get-Content $appsFile -Raw -ErrorAction Stop
        $essentialAppsList = $configJson | ConvertFrom-Json -ErrorAction Stop

        # Convert to array if it's not already
        if ($essentialAppsList -is [Array]) {
            $script:EssentialApps['all'] = $essentialAppsList
        }
        else {
            $script:EssentialApps['all'] = @($essentialAppsList)
        }

        Write-Verbose "Loaded essential apps list with $($script:EssentialApps['all'].Count) entries"
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
    [OutputType([array])]
    param(
        [Parameter()]
        [string[]]$IncludeCategories = @('all')
    )

    $bloatwareLists = Get-BloatwareConfiguration
    
    if ($IncludeCategories -contains 'all' -or $IncludeCategories.Count -eq 0) {
        if ($bloatwareLists.ContainsKey('all')) {
            return $bloatwareLists['all'] | Sort-Object
        }
        else {
            Write-Warning "No bloatware patterns found in configuration"
            return @()
        }
    }
    
    # Get specific categories
    $categoryList = @()
    foreach ($category in $IncludeCategories) {
        if ($bloatwareLists.ContainsKey($category)) {
            $categoryList += $bloatwareLists[$category]
        }
        else {
            Write-Warning "Bloatware category '$category' not found in configuration"
        }
    }
    
    return $categoryList | Sort-Object -Unique
}

<#
.SYNOPSIS
    Gets bloatware list for specific categories

.DESCRIPTION
    Returns bloatware patterns for specified categories, with fallback to all categories.

.PARAMETER Categories
    Array of category names to retrieve (gaming, oem, security, windows, all)

.EXAMPLE
    $oemBloatware = Get-BloatwareList -Categories @('oem')
    $allBloatware = Get-BloatwareList -Categories @('all')
#>
function Get-BloatwareList {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter()]
        [string[]]$Categories = @('all')
    )
    
    return Get-UnifiedBloatwareList -IncludeCategories $Categories
}

<#
.SYNOPSIS
    Gets available bloatware categories

.DESCRIPTION
    Returns list of available bloatware categories from configuration.

.OUTPUTS
    Array of category names

.EXAMPLE
    $categories = Get-BloatwareCategories
#>
function Get-BloatwareCategories {
    [CmdletBinding()]
    [OutputType([array])]
    param()
    
    $bloatwareLists = Get-BloatwareConfiguration
    $categories = @($bloatwareLists.Keys | Where-Object { $_ -ne 'all' })
    
    if ($categories.Count -eq 0) {
        return @('all')  # Fallback if no specific categories found
    }
    
    return $categories + 'all'  # Include 'all' as an option
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
    [OutputType([array])]
    param()

    $appLists = Get-EssentialAppsConfiguration

    if ($appLists.ContainsKey('all')) {
        return $appLists['all']
    }
    else {
        Write-Warning "No essential apps found in configuration"
        return @()
    }
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
    [OutputType([void])]
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
        execution     = [PSCustomObject]@{
            defaultMode       = 'unattended'
            countdownSeconds  = 20
            enableDryRun      = $true
            autoSelectDefault = $true
            showProgressBars  = $true
        }
        modules       = [PSCustomObject]@{
            skipBloatwareRemoval   = $false
            skipEssentialApps      = $false
            skipWindowsUpdates     = $false
            skipTelemetryDisable   = $false
            skipSystemOptimization = $false
            skipSecurityAudit      = $false
            customModulesPath      = ''
        }
        bloatware     = [PSCustomObject]@{
            enableDiffBasedProcessing = $true
            parallelRemoval           = $true
            createBackups             = $true
            customBloatwareList       = @()
        }
        essentialApps = [PSCustomObject]@{
            enableParallelInstallation = $true
            fallbackToLibreOffice      = $true
            customEssentialApps        = @()
            skipConflictResolution     = $false
        }
        system        = [PSCustomObject]@{
            createSystemRestorePoint       = $true
            enableVerboseLogging           = $false
            maxLogSizeMB                   = 10
            enablePerformanceOptimizations = $true
        }
        reporting     = [PSCustomObject]@{
            enableHtmlReport              = $true
            enableDetailedAudit           = $true
            includeSystemInventory        = $true
            generateBeforeAfterComparison = $true
        }
        paths         = [PSCustomObject]@{
            tempFolder      = 'temp_files'
            reportsFolder   = 'temp_files/reports'
            logsFolder      = 'temp_files/logs'
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
        logging    = @{
            logLevel            = 'INFO'
            enableConsoleOutput = $true
            enableFileOutput    = $true
            enableProgressBars  = $true
            coloredOutput       = $true
            maxLogSizeMB        = 10
            logRotation         = $true
            keepLogFiles        = 5
        }
        formatting = @{
            dateTimeFormat   = 'yyyy-MM-dd HH:mm:ss'
            messageFormat    = '[{timestamp}] [{level}] [{component}] {message}'
            progressBarStyle = 'detailed'
        }
        levels     = @{
            DEBUG    = @{ enabled = $false; color = 'Gray' }
            INFO     = @{ enabled = $true; color = 'White' }
            SUCCESS  = @{ enabled = $true; color = 'Green' }
            WARN     = @{ enabled = $true; color = 'Yellow' }
            ERROR    = @{ enabled = $true; color = 'Red' }
            CRITICAL = @{ enabled = $true; color = 'Magenta' }
        }
        components = @{
            BAT          = 'Batch Launcher'
            ORCHESTRATOR = 'Main Orchestrator'
            TYPE1        = 'Inventory/Reporting'
            TYPE2        = 'System Modification'
            CONFIG       = 'Configuration Manager'
            MENU         = 'Interactive Menu'
        }
    }
}

<#
.SYNOPSIS
    Merges configuration with defaults
#>
function Merge-ConfigurationWithDefault {
    param(
        [PSCustomObject]$Config
    )

    $defaults = Get-DefaultConfiguration
    return Merge-PSCustomObject -Default $defaults -Override $Config
}

<#
.SYNOPSIS
    Merges two PSCustomObject instances
#>
function Merge-PSCustomObject {
    param(
        [PSCustomObject]$Default,
        [PSCustomObject]$Override
    )

    $result = $Default.PSObject.Copy()

    foreach ($property in $Override.PSObject.Properties) {
        if ($result.PSObject.Properties.Name -contains $property.Name) {
            if ($property.Value -is [PSCustomObject] -and $result.($property.Name) -is [PSCustomObject]) {
                $result.($property.Name) = Merge-PSCustomObject -Default $result.($property.Name) -Override $property.Value
            }
            else {
                $result.($property.Name) = $property.Value
            }
        }
        else {
            $result | Add-Member -NotePropertyName $property.Name -NotePropertyValue $property.Value
        }
    }

    return $result
}

<#
.SYNOPSIS
    Merges hash tables
#>
function Merge-HashTable {
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
                $result[$property.Name] = Merge-HashTable -Default $result[$property.Name] -Override $overrideHash
            }
            else {
                $result[$property.Name] = $property.Value
            }
        }
        else {
            $result[$property.Name] = $property.Value
        }
    }

    return $result
}

#endregion

#region Path Resolution Functions

<#
.SYNOPSIS
    Gets the configured path for temporary files

.DESCRIPTION
    Returns the configured temporary files directory path from configuration,
    with fallback to default 'temp_files' if not configured.

.OUTPUTS
    [string] Absolute path to temporary files directory

.EXAMPLE
    $tempPath = Get-TempDirectoryPath
#>
function Get-TempDirectoryPath {
    [CmdletBinding()]
    [OutputType([string])]
    param()
    
    try {
        $config = Get-MainConfiguration
        $tempFolder = $config.paths.tempFolder
        
        if ([string]::IsNullOrWhiteSpace($tempFolder)) {
            $tempFolder = 'temp_files'
        }
        
        # Convert to absolute path if relative
        if (-not [System.IO.Path]::IsPathRooted($tempFolder)) {
            $scriptRoot = $script:ConfigPaths.Root
            $tempFolder = Join-Path $scriptRoot $tempFolder
        }
        
        return $tempFolder
    }
    catch {
        Write-Verbose "Failed to get temp files path from config, using default: $_"
        return Join-Path $script:ConfigPaths.Root 'temp_files'
    }
}

<#
.SYNOPSIS
    Gets the configured path for reports

.DESCRIPTION
    Returns the configured reports directory path from configuration,
    with fallback if not configured.

.OUTPUTS
    [string] Absolute path to reports directory

.EXAMPLE
    $reportsPath = Get-ReportsPath
#>
function Get-ReportsPath {
    [CmdletBinding()]
    [OutputType([string])]
    param()
    
    try {
        $config = Get-MainConfiguration
        $reportsFolder = $config.paths.reportsFolder
        
        if ([string]::IsNullOrWhiteSpace($reportsFolder)) {
            $reportsFolder = 'temp_files/reports'
        }
        
        # Convert to absolute path if relative
        if (-not [System.IO.Path]::IsPathRooted($reportsFolder)) {
            $scriptRoot = $script:ConfigPaths.Root
            $reportsFolder = Join-Path $scriptRoot $reportsFolder
        }
        
        return $reportsFolder
    }
    catch {
        Write-Verbose "Failed to get reports path from config, using default: $_"
        return Join-Path $script:ConfigPaths.Root 'temp_files/reports'
    }
}

<#
.SYNOPSIS
    Gets the configured path for logs

.DESCRIPTION
    Returns the configured logs directory path from configuration,
    with fallback if not configured.

.OUTPUTS
    [string] Absolute path to logs directory

.EXAMPLE
    $logsPath = Get-LogsPath
#>
function Get-LogsPath {
    [CmdletBinding()]
    [OutputType([string])]
    param()
    
    try {
        $config = Get-MainConfiguration
        $logsFolder = $config.paths.logsFolder
        
        if ([string]::IsNullOrWhiteSpace($logsFolder)) {
            $logsFolder = 'temp_files/logs'
        }
        
        # Convert to absolute path if relative
        if (-not [System.IO.Path]::IsPathRooted($logsFolder)) {
            $scriptRoot = $script:ConfigPaths.Root
            $logsFolder = Join-Path $scriptRoot $logsFolder
        }
        
        return $logsFolder
    }
    catch {
        Write-Verbose "Failed to get logs path from config, using default: $_"
        return Join-Path $script:ConfigPaths.Root 'temp_files/logs'
    }
}

<#
.SYNOPSIS
    Gets the configured path for inventory files

.DESCRIPTION
    Returns the configured inventory directory path from configuration,
    with fallback if not configured.

.OUTPUTS
    [string] Absolute path to inventory directory

.EXAMPLE
    $inventoryPath = Get-InventoryPath
#>
function Get-InventoryPath {
    [CmdletBinding()]
    [OutputType([string])]
    param()
    
    try {
        $config = Get-MainConfiguration
        $inventoryFolder = $config.paths.inventoryFolder
        
        if ([string]::IsNullOrWhiteSpace($inventoryFolder)) {
            $inventoryFolder = 'temp_files/inventory'
        }
        
        # Convert to absolute path if relative
        if (-not [System.IO.Path]::IsPathRooted($inventoryFolder)) {
            $scriptRoot = $script:ConfigPaths.Root
            $inventoryFolder = Join-Path $scriptRoot $inventoryFolder
        }
        
        return $inventoryFolder
    }
    catch {
        Write-Verbose "Failed to get inventory path from config, using default: $_"
        return Join-Path $script:ConfigPaths.Root 'temp_files/inventory'
    }
}

<#
.SYNOPSIS
    Saves structured inventory data to the configured cache location

.DESCRIPTION
    Persists inventory objects produced by Type1 modules into the inventory cache
    directory. Ensures directories exist, handles JSON serialization, and applies
    basic file locking when available to avoid concurrent write conflicts.

.PARAMETER Category
    Logical inventory category (e.g. Privacy, Security, Apps). Used to derive the
    default file name when not explicitly supplied.

.PARAMETER Data
    Inventory payload to persist.

.PARAMETER FileName
    Optional override for the target file name. Defaults to
    "<category>-inventory.json" when omitted.

.PARAMETER Depth
    JSON serialization depth. Defaults to 10 to accommodate nested objects.
#>
function Save-InventoryFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Category,

        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [object]$Data,

        [Parameter()]
        [string]$FileName,

        [Parameter()]
        [ValidateRange(2, 32)]
        [int]$Depth = 10
    )

    $targetPath = Resolve-InventoryFilePath -Category $Category -FileName $FileName

    try {
        $json = $Data | ConvertTo-Json -Depth $Depth
    }
    catch {
        Write-Error "Failed to serialize inventory data for '$Category': $($_.Exception.Message)"
        return $null
    }

    try {
        $writeScript = {
            param()
            $using:json | Set-Content -Path $using:targetPath -Encoding UTF8 -ErrorAction Stop
        }

        if (Get-Command 'Invoke-WithFileLock' -ErrorAction SilentlyContinue) {
            Invoke-WithFileLock -FilePath $targetPath -ScriptBlock $writeScript | Out-Null
        }
        else {
            & $writeScript
        }

        return $targetPath
    }
    catch {
        Write-Error "Failed to save inventory file at $targetPath`: $($_.Exception.Message)"
        return $null
    }
}

<#
.SYNOPSIS
    Loads cached inventory data for the specified category

.DESCRIPTION
    Reads previously saved inventory artifacts. Automatically resolves the file
    location, handles locking when available, and deserializes the JSON payload
    unless the caller requests the raw text.

.PARAMETER Category
    Inventory category name used when the cache file was saved.

.PARAMETER FileName
    Optional explicit file name when the default naming convention is not used.

.PARAMETER Raw
    Returns the raw JSON string rather than converting to a PowerShell object.

.PARAMETER SuppressWarnings
    Suppresses warning output when cache files are missing.
#>
function Import-InventoryFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Category,

        [Parameter()]
        [string]$FileName,

        [Parameter()]
        [switch]$Raw,

        [Parameter()]
        [switch]$SuppressWarnings
    )

    $targetPath = Resolve-InventoryFilePath -Category $Category -FileName $FileName

    if (-not (Test-Path $targetPath)) {
        if (-not $SuppressWarnings) {
            Write-Verbose "Inventory cache not found for category '$Category' at $targetPath"
        }
        return $null
    }

    try {
        $readScript = {
            param()
            Get-Content -Path $using:targetPath -Raw -Encoding UTF8 -ErrorAction Stop
        }

        $content = if (Get-Command 'Invoke-WithFileLock' -ErrorAction SilentlyContinue) {
            Invoke-WithFileLock -FilePath $targetPath -ScriptBlock $readScript
        }
        else {
            & $readScript
        }

        if ($Raw) {
            return $content
        }

        if (-not $content) {
            return $null
        }

        return $content | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        Write-Warning "Failed to import inventory for category '$Category': $($_.Exception.Message)"
        return $null
    }
}

<#
.SYNOPSIS
    Gets the script root directory path

.DESCRIPTION
    Returns the root directory of the maintenance script system.

.OUTPUTS
    [string] Absolute path to script root directory

.EXAMPLE
    $scriptRoot = Get-ScriptRootPath
#>
function Get-ScriptRootPath {
    [CmdletBinding()]
    [OutputType([string])]
    param()
    
    return $script:ConfigPaths.Root
}

#endregion

#region JSON Schema Validation

<#
.SYNOPSIS
    Validates JSON configuration against defined schema

.DESCRIPTION
    Performs comprehensive schema validation for configuration files to catch
    malformed JSON, missing required properties, invalid data types, and 
    constraint violations early in the configuration loading process.

.PARAMETER ConfigData
    The configuration hashtable to validate

.PARAMETER SchemaType
    Type of schema to validate against (MainConfig, LoggingConfig, BloatwareConfig, EssentialAppsConfig)

.OUTPUTS
    [hashtable] Validation result containing IsValid boolean and Issues array

.EXAMPLE
    $result = Test-ConfigurationSchema -ConfigData $config -SchemaType 'MainConfig'
    if (-not $result.IsValid) { Write-Warning "Configuration issues: $($result.Issues -join ', ')" }
#>
function Test-ConfigurationSchema {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$ConfigData,
        
        [Parameter(Mandatory)]
        [ValidateSet('MainConfig', 'LoggingConfig', 'BloatwareConfig', 'EssentialAppsConfig')]
        [string]$SchemaType
    )
    
    $validationResult = @{
        IsValid = $true
        Issues  = [System.Collections.Generic.List[string]]::new()
    }
    
    try {
        switch ($SchemaType) {
            'MainConfig' {
                try {
                    $validationResult = Test-MainConfigSchema -ConfigData $ConfigData
                    if (-not $validationResult -or -not $validationResult.Issues) {
                        $validationResult = @{
                            IsValid = $true
                            Issues  = [System.Collections.Generic.List[string]]::new()
                        }
                    }
                }
                catch {
                    Write-Warning "MainConfig schema validation failed: $_"
                    $errorIssues = [System.Collections.Generic.List[string]]::new()
                    $errorIssues.Add("MainConfig validation error: $($_.Exception.Message)")
                    $validationResult = @{
                        IsValid = $false
                        Issues  = $errorIssues
                    }
                }
            }
            'LoggingConfig' {
                try {
                    $validationResult = Test-LoggingConfigSchema -ConfigData $ConfigData
                    if (-not $validationResult -or -not $validationResult.Issues) {
                        $validationResult = @{
                            IsValid = $true
                            Issues  = [System.Collections.Generic.List[string]]::new()
                        }
                    }
                }
                catch {
                    Write-Warning "LoggingConfig schema validation failed: $_"
                    $errorIssues = [System.Collections.Generic.List[string]]::new()
                    $errorIssues.Add("LoggingConfig validation error: $($_.Exception.Message)")
                    $validationResult = @{
                        IsValid = $false
                        Issues  = $errorIssues
                    }
                }
            }
            'BloatwareConfig' {
                $validationResult = Test-BloatwareConfigSchema -ConfigData $ConfigData
            }
            'EssentialAppsConfig' {
                $validationResult = Test-EssentialAppsConfigSchema -ConfigData $ConfigData
            }
        }
        
        Write-Verbose "Schema validation for $SchemaType completed: $($validationResult.IsValid)"
        if ($validationResult.Issues -and $validationResult.Issues.Count -gt 0) {
            Write-Verbose "Validation issues found: $($validationResult.Issues.Count)"
        }
        
        return $validationResult
    }
    catch {
        Write-Error "Schema validation failed: $_"
        $errorIssues = [System.Collections.Generic.List[string]]::new()
        $errorIssues.Add("Schema validation error: $($_.Exception.Message)")
        return @{
            IsValid = $false
            Issues  = $errorIssues
        }
    }
}

<#
.SYNOPSIS
    Validates main configuration schema

.DESCRIPTION
    Validates the main-config.json file structure, required properties,
    and data type constraints for execution, modules, bloatware, 
    essentialApps, system, reporting, and paths sections.

.PARAMETER ConfigData
    Main configuration hashtable to validate

.OUTPUTS
    [hashtable] Validation result with IsValid boolean and Issues array
#>
function Test-MainConfigSchema {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$ConfigData
    )
    
    $issues = [System.Collections.Generic.List[string]]::new()
    
    # Required top-level sections
    $requiredSections = @('execution', 'modules', 'bloatware', 'essentialApps', 'system', 'reporting', 'paths')
    foreach ($section in $requiredSections) {
        if (-not $ConfigData.ContainsKey($section)) {
            $issues.Add("Missing required section: $section")
        }
    }
    
    # Validate execution section
    if ($ConfigData.ContainsKey('execution')) {
        $execution = $ConfigData.execution
        Test-ConfigProperty -Object $execution -PropertyName 'defaultMode' -ExpectedType 'String' -ValidValues @('interactive', 'unattended') -Issues $issues
        Test-ConfigProperty -Object $execution -PropertyName 'countdownSeconds' -ExpectedType 'Int32' -MinValue 5 -MaxValue 300 -Issues $issues
        Test-ConfigProperty -Object $execution -PropertyName 'enableDryRun' -ExpectedType 'Boolean' -Issues $issues
        Test-ConfigProperty -Object $execution -PropertyName 'autoSelectDefault' -ExpectedType 'Boolean' -Issues $issues
        Test-ConfigProperty -Object $execution -PropertyName 'showProgressBars' -ExpectedType 'Boolean' -Issues $issues
    }
    
    # Validate modules section
    if ($ConfigData.ContainsKey('modules')) {
        $modules = $ConfigData.modules
        $moduleProperties = @('skipBloatwareRemoval', 'skipEssentialApps', 'skipWindowsUpdates', 'skipTelemetryDisable', 'skipSystemOptimization', 'skipSecurityAudit')
        foreach ($prop in $moduleProperties) {
            Test-ConfigProperty -Object $modules -PropertyName $prop -ExpectedType 'Boolean' -Issues $issues
        }
        Test-ConfigProperty -Object $modules -PropertyName 'customModulesPath' -ExpectedType 'String' -AllowEmpty -Issues $issues
    }
    
    # Validate bloatware section
    if ($ConfigData.ContainsKey('bloatware')) {
        $bloatware = $ConfigData.bloatware
        Test-ConfigProperty -Object $bloatware -PropertyName 'enableDiffBasedProcessing' -ExpectedType 'Boolean' -Issues $issues
        Test-ConfigProperty -Object $bloatware -PropertyName 'parallelRemoval' -ExpectedType 'Boolean' -Issues $issues
        Test-ConfigProperty -Object $bloatware -PropertyName 'createBackups' -ExpectedType 'Boolean' -Issues $issues
        # customBloatwareList can be an empty array, so skip validation
    }
    
    # Validate essentialApps section
    if ($ConfigData.ContainsKey('essentialApps')) {
        $essentialApps = $ConfigData.essentialApps
        Test-ConfigProperty -Object $essentialApps -PropertyName 'enableParallelInstallation' -ExpectedType 'Boolean' -Issues $issues
        Test-ConfigProperty -Object $essentialApps -PropertyName 'fallbackToLibreOffice' -ExpectedType 'Boolean' -Issues $issues
        Test-ConfigProperty -Object $essentialApps -PropertyName 'skipConflictResolution' -ExpectedType 'Boolean' -Issues $issues
        # customEssentialApps can be an empty array, so skip validation
    }
    
    # Validate system section
    if ($ConfigData.ContainsKey('system')) {
        $system = $ConfigData.system
        Test-ConfigProperty -Object $system -PropertyName 'createSystemRestorePoint' -ExpectedType 'Boolean' -Issues $issues
        Test-ConfigProperty -Object $system -PropertyName 'enableVerboseLogging' -ExpectedType 'Boolean' -Issues $issues
        Test-ConfigProperty -Object $system -PropertyName 'maxLogSizeMB' -ExpectedType 'Int32' -MinValue 1 -MaxValue 100 -Issues $issues
        Test-ConfigProperty -Object $system -PropertyName 'enablePerformanceOptimizations' -ExpectedType 'Boolean' -Issues $issues
    }
    
    # Validate reporting section
    if ($ConfigData.ContainsKey('reporting')) {
        $reporting = $ConfigData.reporting
        Test-ConfigProperty -Object $reporting -PropertyName 'enableHtmlReport' -ExpectedType 'Boolean' -Issues $issues
        Test-ConfigProperty -Object $reporting -PropertyName 'enableDetailedAudit' -ExpectedType 'Boolean' -Issues $issues
        Test-ConfigProperty -Object $reporting -PropertyName 'includeSystemInventory' -ExpectedType 'Boolean' -Issues $issues
        Test-ConfigProperty -Object $reporting -PropertyName 'generateBeforeAfterComparison' -ExpectedType 'Boolean' -Issues $issues
    }
    
    # Validate paths section
    if ($ConfigData.ContainsKey('paths')) {
        $paths = $ConfigData.paths
        $pathProperties = @('tempFolder', 'reportsFolder', 'logsFolder', 'inventoryFolder')
        foreach ($prop in $pathProperties) {
            Test-ConfigProperty -Object $paths -PropertyName $prop -ExpectedType 'String' -Issues $issues
        }
    }
    
    return @{
        IsValid = $issues.Count -eq 0
        Issues  = $issues.ToArray()
    }
}

<#
.SYNOPSIS
    Validates logging configuration schema

.DESCRIPTION
    Validates the logging-config.json file structure including logging levels,
    formatting options, component definitions, and performance tracking settings.

.PARAMETER ConfigData
    Logging configuration hashtable to validate

.OUTPUTS
    [hashtable] Validation result with IsValid boolean and Issues array
#>
function Test-LoggingConfigSchema {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$ConfigData
    )
    
    $issues = [System.Collections.Generic.List[string]]::new()
    
    # Required top-level sections
    $requiredSections = @('logging', 'formatting', 'levels', 'components')
    foreach ($section in $requiredSections) {
        if (-not $ConfigData.ContainsKey($section)) {
            $issues.Add("Missing required section: $section")
        }
    }
    
    # Validate logging section
    if ($ConfigData.ContainsKey('logging')) {
        $logging = $ConfigData.logging
        Test-ConfigProperty -Object $logging -PropertyName 'logLevel' -ExpectedType 'String' -ValidValues @('DEBUG', 'INFO', 'WARN', 'ERROR', 'CRITICAL') -Issues $issues
        Test-ConfigProperty -Object $logging -PropertyName 'enableConsoleOutput' -ExpectedType 'Boolean' -Issues $issues
        Test-ConfigProperty -Object $logging -PropertyName 'enableFileOutput' -ExpectedType 'Boolean' -Issues $issues
        Test-ConfigProperty -Object $logging -PropertyName 'maxLogSizeMB' -ExpectedType 'Int32' -MinValue 1 -MaxValue 1000 -Issues $issues
        Test-ConfigProperty -Object $logging -PropertyName 'logBufferSize' -ExpectedType 'Int32' -MinValue 100 -MaxValue 10000 -Issues $issues
    }
    
    # Validate levels section
    if ($ConfigData.ContainsKey('levels')) {
        $levels = $ConfigData.levels
        $requiredLevels = @('DEBUG', 'INFO', 'WARN', 'ERROR', 'CRITICAL')
        foreach ($level in $requiredLevels) {
            if (-not $levels.ContainsKey($level)) {
                $issues.Add("Missing required log level configuration: $level")
            }
            else {
                $levelConfig = $levels[$level]
                Test-ConfigProperty -Object $levelConfig -PropertyName 'enabled' -ExpectedType 'Boolean' -Issues $issues
                Test-ConfigProperty -Object $levelConfig -PropertyName 'color' -ExpectedType 'String' -Issues $issues
                Test-ConfigProperty -Object $levelConfig -PropertyName 'fileOutput' -ExpectedType 'Boolean' -Issues $issues
                Test-ConfigProperty -Object $levelConfig -PropertyName 'consoleOutput' -ExpectedType 'Boolean' -Issues $issues
            }
        }
    }
    
    # Validate performance section if present
    if ($ConfigData.ContainsKey('performance')) {
        $performance = $ConfigData.performance
        Test-ConfigProperty -Object $performance -PropertyName 'slowOperationThreshold' -ExpectedType 'Double' -MinValue 1.0 -MaxValue 300.0 -Issues $issues
    }
    
    return @{
        IsValid = $issues.Count -eq 0
        Issues  = $issues.ToArray()
    }
}

<#
.SYNOPSIS
    Validates bloatware configuration schema

.DESCRIPTION
    Validates bloatware-list.json structure including categories, apps, patterns,
    and metadata for comprehensive bloatware detection configuration.

.PARAMETER ConfigData
    Bloatware configuration hashtable to validate

.OUTPUTS
    [hashtable] Validation result with IsValid boolean and Issues array
#>
function Test-BloatwareConfigSchema {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$ConfigData
    )
    
    $issues = [System.Collections.Generic.List[string]]::new()
    
    # Validate each category has required structure
    foreach ($categoryKey in $ConfigData.Keys) {
        $category = $ConfigData[$categoryKey]
        
        if ($category -isnot [hashtable] -and $category -isnot [PSCustomObject]) {
            $issues.Add("Category '$categoryKey' must be an object")
            continue
        }
        
        # Check for apps array
        if (-not $category.ContainsKey('apps')) {
            $issues.Add("Category '$categoryKey' missing required 'apps' property")
        }
        elseif ($category.apps -isnot [array]) {
            $issues.Add("Category '$categoryKey' 'apps' property must be an array")
        }
        else {
            # Validate each app in the category
            foreach ($app in $category.apps) {
                if ($app -isnot [hashtable] -and $app -isnot [PSCustomObject]) {
                    $issues.Add("App entry in category '$categoryKey' must be an object")
                    continue
                }
                
                # Required app properties
                Test-ConfigProperty -Object $app -PropertyName 'name' -ExpectedType 'String' -Issues $issues
                Test-ConfigProperty -Object $app -PropertyName 'description' -ExpectedType 'String' -AllowEmpty -Issues $issues
            }
        }
    }
    
    return @{
        IsValid = $issues.Count -eq 0
        Issues  = $issues.ToArray()
    }
}

<#
.SYNOPSIS
    Validates essential apps configuration schema

.DESCRIPTION
    Validates essential-apps.json structure including categories, apps, 
    installation methods, and metadata for application installation configuration.

.PARAMETER ConfigData
    Essential apps configuration hashtable to validate

.OUTPUTS
    [hashtable] Validation result with IsValid boolean and Issues array
#>
function Test-EssentialAppsConfigSchema {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$ConfigData
    )
    
    $issues = [System.Collections.Generic.List[string]]::new()
    
    # Validate each category structure
    foreach ($categoryKey in $ConfigData.Keys) {
        $category = $ConfigData[$categoryKey]
        
        if ($category -isnot [hashtable] -and $category -isnot [PSCustomObject]) {
            $issues.Add("Category '$categoryKey' must be an object")
            continue
        }
        
        # Check for apps array
        if (-not $category.ContainsKey('apps')) {
            $issues.Add("Category '$categoryKey' missing required 'apps' property")
        }
        elseif ($category.apps -isnot [array]) {
            $issues.Add("Category '$categoryKey' 'apps' property must be an array")
        }
        else {
            # Validate each app
            foreach ($app in $category.apps) {
                if ($app -isnot [hashtable] -and $app -isnot [PSCustomObject]) {
                    $issues.Add("App entry in category '$categoryKey' must be an object")
                    continue
                }
                
                # Required app properties
                Test-ConfigProperty -Object $app -PropertyName 'name' -ExpectedType 'String' -Issues $issues
                Test-ConfigProperty -Object $app -PropertyName 'description' -ExpectedType 'String' -AllowEmpty -Issues $issues
                
                # At least one installation method should be present
                $installMethods = @('winget', 'chocolatey', 'manual')
                $hasInstallMethod = $false
                foreach ($method in $installMethods) {
                    if ($app.ContainsKey($method) -and -not [string]::IsNullOrWhiteSpace($app[$method])) {
                        $hasInstallMethod = $true
                        break
                    }
                }
                
                if (-not $hasInstallMethod) {
                    $issues.Add("App '$($app.name)' in category '$categoryKey' must have at least one installation method (winget, chocolatey, or manual)")
                }
            }
        }
    }
    
    return @{
        IsValid = $issues.Count -eq 0
        Issues  = $issues.ToArray()
    }
}

<#
.SYNOPSIS
    Helper function to validate configuration properties

.DESCRIPTION
    Validates individual configuration properties against expected types,
    value constraints, and other validation rules.

.PARAMETER Object
    The object containing the property to validate

.PARAMETER PropertyName
    Name of the property to validate

.PARAMETER ExpectedType
    Expected .NET type name (String, Int32, Boolean, etc.)

.PARAMETER ValidValues
    Array of valid values for the property (optional)

.PARAMETER MinValue
    Minimum value for numeric types (optional)

.PARAMETER MaxValue
    Maximum value for numeric types (optional)

.PARAMETER AllowEmpty
    Allow empty string values (optional, default: false)

.PARAMETER Issues
    List object to add validation issues to

.NOTES
    Internal helper function for schema validation.
#>
function Test-ConfigProperty {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Object,
        
        [Parameter(Mandatory)]
        [string]$PropertyName,
        
        [Parameter(Mandatory)]
        [string]$ExpectedType,
        
        [Parameter()]
        [array]$ValidValues,
        
        [Parameter()]
        [double]$MinValue,
        
        [Parameter()]
        [double]$MaxValue,
        
        [Parameter()]
        [switch]$AllowEmpty,
        
        [Parameter(Mandatory)]
        [System.Collections.Generic.List[string]]$Issues
    )
    
    if (-not $Object.ContainsKey($PropertyName)) {
        $Issues.Add("Missing required property: $PropertyName")
        return
    }
    
    $value = $Object[$PropertyName]
    
    # Type validation
    if ($null -eq $value) {
        $Issues.Add("Property '$PropertyName' cannot be null")
        return
    }
    
    $actualType = $value.GetType().Name
    if ($actualType -ne $ExpectedType) {
        # Handle some common type compatibility cases
        $compatible = $false
        if ($ExpectedType -eq 'Int32' -and $actualType -eq 'Int64') {
            $compatible = $true
        }
        elseif ($ExpectedType -eq 'Double' -and ($actualType -eq 'Int32' -or $actualType -eq 'Int64')) {
            $compatible = $true
        }
        
        if (-not $compatible) {
            $Issues.Add("Property '$PropertyName' expected type $ExpectedType but found $actualType")
            return
        }
    }
    
    # String-specific validation
    if ($ExpectedType -eq 'String') {
        if (-not $AllowEmpty -and [string]::IsNullOrWhiteSpace($value)) {
            $Issues.Add("Property '$PropertyName' cannot be empty")
            return
        }
    }
    
    # Valid values validation
    if ($ValidValues -and $ValidValues.Count -gt 0) {
        if ($value -notin $ValidValues) {
            $Issues.Add("Property '$PropertyName' value '$value' not in valid values: $($ValidValues -join ', ')")
        }
    }
    
    # Numeric range validation
    if ($ExpectedType -in @('Int32', 'Int64', 'Double', 'Single') -and ($PSBoundParameters.ContainsKey('MinValue') -or $PSBoundParameters.ContainsKey('MaxValue'))) {
        $numValue = [double]$value
        
        if ($PSBoundParameters.ContainsKey('MinValue') -and $numValue -lt $MinValue) {
            $Issues.Add("Property '$PropertyName' value $numValue is below minimum $MinValue")
        }
        
        if ($PSBoundParameters.ContainsKey('MaxValue') -and $numValue -gt $MaxValue) {
            $Issues.Add("Property '$PropertyName' value $numValue is above maximum $MaxValue")
        }
    }
}

<#
.SYNOPSIS
    Resolves the full path for inventory files

.DESCRIPTION
    Creates standardized file paths for inventory data storage with automatic directory creation.

.PARAMETER Category
    Category name for the inventory file

.PARAMETER FileName
    Optional specific filename (defaults to category-inventory.json)

.OUTPUTS
    String path to the inventory file
#>
function Resolve-InventoryFilePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Category,

        [Parameter()]
        [string]$FileName
    )

    $inventoryRoot = Get-InventoryPath

    if (-not (Test-Path $inventoryRoot)) {
        New-Item -Path $inventoryRoot -ItemType Directory -Force | Out-Null
    }

    $sanitizedCategory = ($Category -replace '[^A-Za-z0-9]+', '-').Trim('-')
    if ([string]::IsNullOrWhiteSpace($sanitizedCategory)) {
        $sanitizedCategory = 'inventory'
    }

    if ([string]::IsNullOrWhiteSpace($FileName)) {
        $FileName = "$sanitizedCategory-inventory.json"
    }

    if (-not [System.IO.Path]::GetExtension($FileName)) {
        $FileName = "$FileName.json"
    }

    $fullPath = Join-Path $inventoryRoot $FileName

    $parentDir = Split-Path -Parent $fullPath
    if (-not (Test-Path $parentDir)) {
        New-Item -Path $parentDir -ItemType Directory -Force | Out-Null
    }

    return $fullPath
}

#endregion

# Export module functions
Export-ModuleMember -Function @(
    'Initialize-ConfigSystem',
    'Get-MainConfiguration',
    'Get-ConfigValue',
    'Get-LoggingConfiguration',
    'Get-BloatwareConfiguration',
    'Get-EssentialAppsConfiguration',
    'Get-UnifiedBloatwareList',
    'Get-UnifiedEssentialAppsList',
    'Get-BloatwareList',
    'Get-BloatwareCategories',
    'Save-Configuration',
    'Test-ConfigurationSchema',
    'Get-TempDirectoryPath',
    'Get-ReportsPath',
    'Get-LogsPath',
    'Get-InventoryPath',
    'Get-ScriptRootPath',
    'Save-InventoryFile',
    'Import-InventoryFile',
    'Resolve-InventoryFilePath'
)
