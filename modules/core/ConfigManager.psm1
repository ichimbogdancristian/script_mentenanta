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
        BloatwareLists = Join-Path $ConfigRootPath 'bloatware-lists'
        EssentialApps = Join-Path $ConfigRootPath 'essential-apps'
    }
    
    # Validate required paths
    $requiredPaths = @('MainConfig', 'BloatwareLists', 'EssentialApps')
    foreach ($pathKey in $requiredPaths) {
        $path = $script:ConfigPaths[$pathKey]
        if (-not (Test-Path $path)) {
            throw "Required configuration path does not exist: $path"
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
    Reads all JSON files in the bloatware-lists directory and combines them into categories.
    
.EXAMPLE
    $bloatwareLists = Get-BloatwareConfiguration
#>
function Get-BloatwareConfiguration {
    [CmdletBinding()]
    param()
    
    if ($script:BloatwareLists.Count -gt 0) {
        return $script:BloatwareLists
    }
    
    $bloatwareDir = $script:ConfigPaths.BloatwareLists
    
    if (-not (Test-Path $bloatwareDir)) {
        Write-Warning "Bloatware configuration directory not found: $bloatwareDir"
        return @{}
    }
    
    try {
        Write-Verbose "Loading bloatware configurations from: $bloatwareDir"
        
        $bloatwareFiles = Get-ChildItem -Path $bloatwareDir -Filter "*.json" -ErrorAction Stop
        
        foreach ($file in $bloatwareFiles) {
            try {
                $categoryName = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
                $configJson = Get-Content $file.FullName -Raw -ErrorAction Stop
                $categoryList = $configJson | ConvertFrom-Json -ErrorAction Stop
                
                # Convert to array if it's not already
                if ($categoryList -is [Array]) {
                    $script:BloatwareLists[$categoryName] = $categoryList
                } else {
                    $script:BloatwareLists[$categoryName] = @($categoryList)
                }
                
                Write-Verbose "Loaded bloatware category '$categoryName' with $($script:BloatwareLists[$categoryName].Count) entries"
            }
            catch {
                Write-Warning "Failed to load bloatware configuration from $($file.FullName): $_"
            }
        }
        
        Write-Verbose "Loaded $($script:BloatwareLists.Keys.Count) bloatware categories"
        return $script:BloatwareLists
    }
    catch {
        Write-Error "Failed to load bloatware configurations: $_"
        return @{}
    }
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
    param()
    
    if ($script:EssentialApps.Count -gt 0) {
        return $script:EssentialApps
    }
    
    $appsDir = $script:ConfigPaths.EssentialApps
    
    if (-not (Test-Path $appsDir)) {
        Write-Warning "Essential apps configuration directory not found: $appsDir"
        return @{}
    }
    
    try {
        Write-Verbose "Loading essential apps configurations from: $appsDir"
        
        $appFiles = Get-ChildItem -Path $appsDir -Filter "*.json" -ErrorAction Stop
        
        foreach ($file in $appFiles) {
            try {
                $categoryName = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
                $configJson = Get-Content $file.FullName -Raw -ErrorAction Stop
                $categoryApps = $configJson | ConvertFrom-Json -ErrorAction Stop
                
                # Convert to array if it's not already
                if ($categoryApps -is [Array]) {
                    $script:EssentialApps[$categoryName] = $categoryApps
                } else {
                    $script:EssentialApps[$categoryName] = @($categoryApps)
                }
                
                Write-Verbose "Loaded essential apps category '$categoryName' with $($script:EssentialApps[$categoryName].Count) entries"
            }
            catch {
                Write-Warning "Failed to load essential apps configuration from $($file.FullName): $_"
            }
        }
        
        Write-Verbose "Loaded $($script:EssentialApps.Keys.Count) essential apps categories"
        return $script:EssentialApps
    }
    catch {
        Write-Error "Failed to load essential apps configurations: $_"
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

# Export module functions
Export-ModuleMember -Function @(
    'Initialize-ConfigSystem',
    'Get-MainConfiguration',
    'Get-LoggingConfiguration', 
    'Get-BloatwareConfiguration',
    'Get-EssentialAppsConfiguration',
    'Get-UnifiedBloatwareList',
    'Get-UnifiedEssentialAppsList',
    'Save-Configuration'
)