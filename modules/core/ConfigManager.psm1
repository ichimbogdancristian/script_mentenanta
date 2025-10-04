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

#region Universal Path Discovery

<#
.SYNOPSIS
    Gets standardized module environment paths with comprehensive fallbacks

.DESCRIPTION
    Universal function for discovering module locations and repository structure.
    Handles various deployment scenarios including extraction, network paths, and
    different working directory contexts with robust fallback strategies.

.PARAMETER ModulePath
    Optional override for the module's path (uses $PSScriptRoot if not specified)

.PARAMETER ModuleType
    The type of module: Core, Type1, or Type2 (for relative path calculations)

.EXAMPLE
    $env = Get-ModuleEnvironment -ModuleType 'Core'
    
.EXAMPLE
    $env = Get-ModuleEnvironment -ModulePath $MyInvocation.MyCommand.Path -ModuleType 'Type1'
#>
function Get-ModuleEnvironment {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$ModulePath,
        
        [Parameter()]
        [ValidateSet('Core', 'Type1', 'Type2')]
        [string]$ModuleType = 'Core'
    )
    
    $environment = @{
        ModuleRoot = $null
        RepositoryRoot = $null
        ConfigPath = $null
        ModulesPath = $null
        LogsPath = $null
        InventoryPath = $null
        TempPath = $null
        IsNetworkPath = $false
        IsValidStructure = $false
        ModuleType = $ModuleType
    }
    
    try {
        # Determine module root with multiple fallback strategies
        if ($ModulePath) {
            if (Test-Path $ModulePath -PathType Leaf) {
                $environment.ModuleRoot = Split-Path -Parent $ModulePath
            } else {
                $environment.ModuleRoot = $ModulePath
            }
        }
        elseif ($PSScriptRoot) {
            $environment.ModuleRoot = $PSScriptRoot
        }
        elseif ($MyInvocation.MyCommand.Path) {
            $environment.ModuleRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
        }
        elseif ($MyInvocation.MyCommand.Definition) {
            $environment.ModuleRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
        }
        else {
            # Last resort: use current location
            $environment.ModuleRoot = (Get-Location).Path
        }
        
        # Resolve to absolute path
        if (Test-Path $environment.ModuleRoot) {
            $environment.ModuleRoot = Resolve-Path $environment.ModuleRoot -ErrorAction SilentlyContinue
            if ($environment.ModuleRoot) {
                $environment.ModuleRoot = $environment.ModuleRoot.Path
            }
        }
        
        # Network path detection
        $environment.IsNetworkPath = $environment.ModuleRoot -like "\\*"
        
        # Calculate repository root based on module type
        switch ($ModuleType) {
            'Core'  { $environment.RepositoryRoot = Join-Path $environment.ModuleRoot '..\..'}
            'Type1' { $environment.RepositoryRoot = Join-Path $environment.ModuleRoot '..\..'}
            'Type2' { $environment.RepositoryRoot = Join-Path $environment.ModuleRoot '..\..'}
        }
        
        # Resolve repository root
        if (Test-Path $environment.RepositoryRoot) {
            $environment.RepositoryRoot = Resolve-Path $environment.RepositoryRoot -ErrorAction SilentlyContinue
            if ($environment.RepositoryRoot) {
                $environment.RepositoryRoot = $environment.RepositoryRoot.Path
            }
        }
        
        # Environment variable overrides with fallbacks
        $environment.RepositoryRoot = if ($env:MAINTENANCE_ROOT) { 
            $env:MAINTENANCE_ROOT 
        } else { 
            $environment.RepositoryRoot 
        }
        
        # Set standard paths with environment variable overrides
        $environment.ConfigPath = if ($env:MAINTENANCE_CONFIG) {
            $env:MAINTENANCE_CONFIG
        } else {
            Join-Path $environment.RepositoryRoot 'config'
        }
        
        $environment.ModulesPath = if ($env:MAINTENANCE_MODULES) {
            $env:MAINTENANCE_MODULES
        } else {
            Join-Path $environment.RepositoryRoot 'modules'
        }
        
        $environment.LogsPath = if ($env:MAINTENANCE_LOGS) {
            $env:MAINTENANCE_LOGS
        } else {
            Join-Path $environment.RepositoryRoot 'temp_files\logs'
        }
        
        $environment.InventoryPath = if ($env:MAINTENANCE_INVENTORY) {
            $env:MAINTENANCE_INVENTORY
        } else {
            Join-Path $environment.RepositoryRoot 'temp_files\inventory'
        }
        
        $environment.TempPath = if ($env:MAINTENANCE_TEMP) {
            $env:MAINTENANCE_TEMP
        } else {
            Join-Path $environment.RepositoryRoot 'temp_files'
        }
        
        # Validate repository structure
        $requiredPaths = @('config', 'modules')
        $foundPaths = 0
        
        foreach ($reqPath in $requiredPaths) {
            $testPath = Join-Path $environment.RepositoryRoot $reqPath
            if (Test-Path $testPath) {
                $foundPaths++
            }
        }
        
        $environment.IsValidStructure = ($foundPaths -eq $requiredPaths.Count)
        
        # Additional validation for orchestrator presence
        $orchestratorPath = Join-Path $environment.RepositoryRoot 'MaintenanceOrchestrator.ps1'
        if (Test-Path $orchestratorPath) {
            $environment.IsValidStructure = $true
        }
        
        # Fallback search if structure not found
        if (-not $environment.IsValidStructure) {
            $searchResult = Find-MaintenanceStructure -BaseDirectory $environment.RepositoryRoot
            if ($searchResult.IsComplete) {
                $environment.RepositoryRoot = Split-Path $searchResult.ConfigPath -Parent
                $environment.ConfigPath = $searchResult.ConfigPath
                $environment.ModulesPath = $searchResult.ModulesPath
                $environment.IsValidStructure = $true
            }
        }
        
        # Enhanced fallback strategies for edge cases
        if (-not $environment.IsValidStructure) {
            Write-Verbose "Applying enhanced fallback strategies for path discovery..."
            
            # Strategy 1: Check common extraction patterns
            $extractionPatterns = @(
                'script_mentenanta-main',
                'script_mentenanta-master', 
                'Windows-Maintenance-Automation',
                'maintenance'
            )
            
            $searchBase = Split-Path $environment.ModuleRoot -Parent
            for ($level = 0; $level -lt 2; $level++) {
                foreach ($pattern in $extractionPatterns) {
                    $testPath = Join-Path $searchBase $pattern
                    if (Test-Path $testPath) {
                        $testResult = Find-MaintenanceStructure -BaseDirectory $testPath
                        if ($testResult.IsComplete) {
                            $environment.RepositoryRoot = $testPath
                            $environment.ConfigPath = $testResult.ConfigPath
                            $environment.ModulesPath = $testResult.ModulesPath
                            $environment.IsValidStructure = $true
                            break
                        }
                    }
                }
                if ($environment.IsValidStructure) { break }
                $searchBase = Split-Path $searchBase -Parent
                if (-not $searchBase) { break }
            }
        }
        
        # Strategy 2: Network path handling
        if ($environment.IsNetworkPath -and -not $environment.IsValidStructure) {
            Write-Verbose "Applying network path fallback strategies..."
            # For network paths, be more permissive and create structure if needed
            $minimalPaths = @('config', 'modules\core', 'modules\type1', 'modules\type2')
            $allExist = $true
            foreach ($path in $minimalPaths) {
                if (-not (Test-Path (Join-Path $environment.RepositoryRoot $path))) {
                    $allExist = $false
                    break
                }
            }
            if ($allExist) {
                $environment.IsValidStructure = $true
            }
        }
        
        # Strategy 3: Permission-aware fallback
        if (-not $environment.IsValidStructure) {
            Write-Verbose "Applying permission-aware fallback strategies..."
            try {
                # Test write access to temp directory
                $testFile = Join-Path $environment.TempPath 'write-test.tmp'
                $null = New-Item -Path (Split-Path $testFile -Parent) -ItemType Directory -Force -ErrorAction SilentlyContinue
                'test' | Out-File -FilePath $testFile -Force -ErrorAction Stop
                Remove-Item $testFile -Force -ErrorAction SilentlyContinue
                
                # If we can write to temp, the structure is usable even if not perfect
                if (Test-Path $environment.RepositoryRoot) {
                    $environment.IsValidStructure = $true
                }
            } catch {
                # If we can't write to our preferred temp location, fallback to system temp
                $environment.TempPath = $env:TEMP
                $environment.LogsPath = Join-Path $env:TEMP 'MaintenanceLogs'
                $environment.InventoryPath = Join-Path $env:TEMP 'MaintenanceInventory'
            }
        }
        
        # Final validation and directory creation
        $criticalPaths = @($environment.LogsPath, $environment.InventoryPath, $environment.TempPath)
        foreach ($path in $criticalPaths) {
            if ($path -and -not (Test-Path $path)) {
                try {
                    New-Item -Path $path -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
                } catch {
                    Write-Verbose "Could not create directory: $path"
                }
            }
        }
        
    } catch {
        Write-Warning "Error in Get-ModuleEnvironment: $_"
        # Ensure we return a valid structure even on error
        if (-not $environment.ModuleRoot) {
            $environment.ModuleRoot = (Get-Location).Path
        }
        
        # Emergency fallback - use system temp directories
        if (-not $environment.RepositoryRoot) {
            $environment.RepositoryRoot = $environment.ModuleRoot
        }
        if (-not $environment.TempPath) {
            $environment.TempPath = $env:TEMP
        }
        if (-not $environment.LogsPath) {
            $environment.LogsPath = Join-Path $env:TEMP 'MaintenanceLogs'
        }
        if (-not $environment.InventoryPath) {
            $environment.InventoryPath = Join-Path $env:TEMP 'MaintenanceInventory'
        }
    }
    
    return $environment
}

<#
.SYNOPSIS
    Finds maintenance automation structure from any base directory

.DESCRIPTION
    Searches for config and modules directories using multiple strategies.
    This is the same function used by MaintenanceOrchestrator.ps1 but
    made available to all modules for consistency.

.PARAMETER BaseDirectory
    Starting directory for the search

.EXAMPLE
    $structure = Find-MaintenanceStructure -BaseDirectory $PWD
#>
function Find-MaintenanceStructure {
    param([string]$BaseDirectory)
    
    $structure = @{
        ConfigPath  = $null
        ModulesPath = $null
        IsComplete  = $false
    }
    
    # Enhanced search strategies for any PC/path scenario
    $searchStrategies = @(
        # Strategy 1: Direct subdirectories
        @{
            Config  = Join-Path $BaseDirectory 'config'
            Modules = Join-Path $BaseDirectory 'modules'
        },
        # Strategy 2: Parent directory (extracted zip scenario)
        @{
            Config  = Join-Path (Split-Path $BaseDirectory -Parent) 'config'
            Modules = Join-Path (Split-Path $BaseDirectory -Parent) 'modules'
        },
        # Strategy 3: Sibling directories
        @{
            Config  = Join-Path (Split-Path $BaseDirectory -Parent) 'config'
            Modules = Join-Path (Split-Path $BaseDirectory -Parent) 'modules'
        }
    )
    
    # Test each strategy
    foreach ($strategy in $searchStrategies) {
        if ((Test-Path $strategy.Config) -and (Test-Path $strategy.Modules)) {
            $structure.ConfigPath = $strategy.Config
            $structure.ModulesPath = $strategy.Modules
            $structure.IsComplete = $true
            return $structure
        }
    }
    
    # Environment variable strategy
    if ($env:MAINTENANCE_CONFIG -and $env:MAINTENANCE_MODULES) {
        if ((Test-Path $env:MAINTENANCE_CONFIG) -and (Test-Path $env:MAINTENANCE_MODULES)) {
            $structure.ConfigPath = $env:MAINTENANCE_CONFIG
            $structure.ModulesPath = $env:MAINTENANCE_MODULES
            $structure.IsComplete = $true
            return $structure
        }
    }
    
    # Recursive search (limited depth for performance)
    $searchRoot = $BaseDirectory
    for ($level = 0; $level -lt 3; $level++) {
        try {
            Get-ChildItem -Path $searchRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                $testConfig = Join-Path $_.FullName 'config'
                $testModules = Join-Path $_.FullName 'modules'
                
                if ((Test-Path $testConfig) -and (Test-Path $testModules)) {
                    $structure.ConfigPath = $testConfig
                    $structure.ModulesPath = $testModules  
                    $structure.IsComplete = $true
                    return $structure
                }
            }
        } catch {
            # Ignore search errors and continue
        }
        
        # Move up one level
        $parentPath = Split-Path $searchRoot -Parent
        if (-not $parentPath -or $parentPath -eq $searchRoot) { break }
        $searchRoot = $parentPath
    }
    
    return $structure
}

#endregion

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
    
    # Use standardized path discovery
    $moduleEnv = Get-ModuleEnvironment -ModuleType 'Core'
    
    # Get inventory folder path from config with environment variable override
    $inventoryFolder = if ($env:MAINTENANCE_INVENTORY) {
        $env:MAINTENANCE_INVENTORY
    } elseif ($config.paths.inventoryFolder) {
        if ([System.IO.Path]::IsPathRooted($config.paths.inventoryFolder)) {
            $config.paths.inventoryFolder
        } else {
            Join-Path $moduleEnv.RepositoryRoot $config.paths.inventoryFolder
        }
    } else {
        $moduleEnv.InventoryPath
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
    
    # Determine log directory using standardized path discovery
    if (-not $LogDirectory) {
        if ($env:MAINTENANCE_LOGS) {
            $LogDirectory = $env:MAINTENANCE_LOGS
        } elseif ($Global:MaintenanceLogFile) {
            $LogDirectory = Split-Path $Global:MaintenanceLogFile -Parent
        } else {
            # Use standardized path discovery
            $moduleEnv = Get-ModuleEnvironment -ModuleType 'Core'
            $LogDirectory = $moduleEnv.LogsPath
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
    'Get-ModuleEnvironment',
    'Find-MaintenanceStructure',
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