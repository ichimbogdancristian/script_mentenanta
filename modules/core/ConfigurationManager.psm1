#Requires -Version 7.0

<#
.SYNOPSIS
    Configuration Manager Module - Specialized configuration loading and management

.DESCRIPTION
    Extracted configuration management component from CoreInfrastructure.psm1.
    Handles all configuration file loading, validation, path resolution,
    and configuration-related operations with smart fallback mechanisms.

.NOTES
    Module Type: Core Infrastructure (Configuration Specialist)
    Dependencies: None (imports CorePaths if needed)
    Extracted from: CoreInfrastructure.psm1
    Version: 1.0.0
    Architecture: v3.0
#>

using namespace System.Collections.Generic
using namespace System.IO

#region Module Imports

# ConfigurationManager can optionally use CorePaths for path discovery
# Try to import but continue if not available (CoreInfrastructure handles exports)
try {
    $CorePathsPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'core\CorePaths.psm1'
    if (Test-Path $CorePathsPath) {
        Import-Module $CorePathsPath -Force -WarningAction SilentlyContinue
    }
}
catch {
    Write-Verbose "CorePaths module not available - will rely on environment variables"
}

#endregion

#region Private Variables

# Configuration cache - stores loaded configurations to reduce file I/O
$script:ConfigCache = @{}
$script:ConfigPaths = @{}
$script:ConfigValidationRules = @{}

#endregion

#region Helper Functions

<#
.SYNOPSIS
    Gets the full path to a configuration file with smart fallback logic

.DESCRIPTION
    Attempts to locate config files in the new subdirectory structure first,
    then falls back to root level for backward compatibility.

.PARAMETER FileName
    Name of the configuration file (e.g., 'main-config.json')

.PARAMETER Subdirectory
    Subdirectory to search (execution, data, templates)
    
.OUTPUTS
    System.String - Full path to configuration file if found, $null otherwise
#>
function Get-ConfigFilePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FileName,
        
        [Parameter(Mandatory = $false)]
        [string]$Subdirectory
    )
    
    if (-not $env:MAINTENANCE_CONFIG_ROOT) {
        throw "MAINTENANCE_CONFIG_ROOT environment variable not set"
    }
    
    $configRoot = $env:MAINTENANCE_CONFIG_ROOT
    
    # Try subdirectory first if specified
    if ($Subdirectory) {
        $subdirPath = Join-Path $configRoot $Subdirectory $FileName
        if (Test-Path $subdirPath) {
            return $subdirPath
        }
    }
    
    # Try root level (backward compatibility)
    $rootPath = Join-Path $configRoot $FileName
    if (Test-Path $rootPath) {
        return $rootPath
    }
    
    # File not found
    return $null
}

#endregion

#region Configuration Initialization

<#
.SYNOPSIS
    Initializes the configuration system

.DESCRIPTION
    Loads all required configuration files and validates structure.
    Sets up caching and path resolution.

.PARAMETER ConfigRootPath
    Root path to configuration directory
#>
function Initialize-ConfigurationSystem {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ConfigRootPath
    )
    
    Write-Verbose "Initializing Configuration System from: $ConfigRootPath"
    
    if (-not (Test-Path $ConfigRootPath)) {
        throw "Configuration root path not found: $ConfigRootPath"
    }
    
    # Store config root for Get-ConfigFilePath
    $env:MAINTENANCE_CONFIG_ROOT = $ConfigRootPath
    
    try {
        # Load main configuration (execution subdirectory or root)
        $mainConfigPath = Get-ConfigFilePath -FileName 'main-config.json' -Subdirectory 'execution'
        if (-not $mainConfigPath) {
            throw "main-config.json not found"
        }
        $script:ConfigCache['MainConfig'] = Get-Content $mainConfigPath -Raw | ConvertFrom-Json
        Write-Verbose "Loaded main-config.json from: $mainConfigPath"
        
        # Load logging configuration
        $loggingConfigPath = Get-ConfigFilePath -FileName 'logging-config.json' -Subdirectory 'execution'
        if (-not $loggingConfigPath) {
            throw "logging-config.json not found"
        }
        $script:ConfigCache['LoggingConfig'] = Get-Content $loggingConfigPath -Raw | ConvertFrom-Json
        Write-Verbose "Loaded logging-config.json from: $loggingConfigPath"
        
        # Load bloatware list (data subdirectory or root)
        $bloatwareConfigPath = Get-ConfigFilePath -FileName 'bloatware-list.json' -Subdirectory 'data'
        if (-not $bloatwareConfigPath) {
            throw "bloatware-list.json not found"
        }
        $script:ConfigCache['BloatwareList'] = Get-Content $bloatwareConfigPath -Raw | ConvertFrom-Json
        Write-Verbose "Loaded bloatware-list.json from: $bloatwareConfigPath"
        
        # Load essential apps list
        $essentialAppsPath = Get-ConfigFilePath -FileName 'essential-apps.json' -Subdirectory 'data'
        if (-not $essentialAppsPath) {
            throw "essential-apps.json not found"
        }
        $script:ConfigCache['EssentialAppsList'] = Get-Content $essentialAppsPath -Raw | ConvertFrom-Json
        Write-Verbose "Loaded essential-apps.json from: $essentialAppsPath"
        
        # Load app upgrade configuration
        $appUpgradeConfigPath = Get-ConfigFilePath -FileName 'app-upgrade-config.json' -Subdirectory 'data'
        if ($appUpgradeConfigPath) {
            $script:ConfigCache['AppUpgradeConfig'] = Get-Content $appUpgradeConfigPath -Raw | ConvertFrom-Json
            Write-Verbose "Loaded app-upgrade-config.json from: $appUpgradeConfigPath"
        }
        
        # Load report templates configuration
        $reportTemplatesPath = Get-ConfigFilePath -FileName 'report-templates-config.json' -Subdirectory 'templates'
        if ($reportTemplatesPath) {
            $script:ConfigCache['ReportTemplatesConfig'] = Get-Content $reportTemplatesPath -Raw | ConvertFrom-Json
            Write-Verbose "Loaded report-templates-config.json from: $reportTemplatesPath"
        }
        
        Write-Verbose "Configuration system initialized successfully with $(($script:ConfigCache).Count) configurations"
        return $true
    }
    catch {
        Write-Error "Configuration system initialization failed: $($_.Exception.Message)"
        return $false
    }
}

#endregion

#region Configuration Retrieval

<#
.SYNOPSIS
    Gets the main configuration object

.OUTPUTS
    PSCustomObject containing main configuration
#>
function Get-MainConfiguration {
    [CmdletBinding()]
    param()
    
    if (-not $script:ConfigCache['MainConfig']) {
        throw "Main configuration not loaded - call Initialize-ConfigurationSystem first"
    }
    
    return $script:ConfigCache['MainConfig']
}

<#
.SYNOPSIS
    Gets the logging configuration

.OUTPUTS
    PSCustomObject containing logging settings
#>
function Get-LoggingConfiguration {
    [CmdletBinding()]
    param()
    
    if (-not $script:ConfigCache['LoggingConfig']) {
        throw "Logging configuration not loaded - call Initialize-ConfigurationSystem first"
    }
    
    return $script:ConfigCache['LoggingConfig']
}

<#
.SYNOPSIS
    Gets the bloatware application list

.OUTPUTS
    PSCustomObject containing bloatware list
#>
function Get-BloatwareConfiguration {
    [CmdletBinding()]
    param()
    
    if (-not $script:ConfigCache['BloatwareList']) {
        throw "Bloatware configuration not loaded - call Initialize-ConfigurationSystem first"
    }
    
    return $script:ConfigCache['BloatwareList']
}

<#
.SYNOPSIS
    Gets the essential applications list

.OUTPUTS
    PSCustomObject containing essential apps
#>
function Get-EssentialAppsConfiguration {
    [CmdletBinding()]
    param()
    
    if (-not $script:ConfigCache['EssentialAppsList']) {
        throw "Essential apps configuration not loaded - call Initialize-ConfigurationSystem first"
    }
    
    return $script:ConfigCache['EssentialAppsList']
}

<#
.SYNOPSIS
    Gets the app upgrade configuration

.OUTPUTS
    PSCustomObject containing app upgrade settings, or $null if not available
#>
function Get-AppUpgradeConfiguration {
    [CmdletBinding()]
    param()
    
    return $script:ConfigCache['AppUpgradeConfig']
}

<#
.SYNOPSIS
    Gets the report templates configuration

.OUTPUTS
    PSCustomObject containing report template metadata
#>
function Get-ReportTemplatesConfiguration {
    [CmdletBinding()]
    param()
    
    if (-not $script:ConfigCache['ReportTemplatesConfig']) {
        throw "Report templates configuration not loaded - call Initialize-ConfigurationSystem first"
    }
    
    return $script:ConfigCache['ReportTemplatesConfig']
}

<#
.SYNOPSIS
    Gets any cached configuration by key

.PARAMETER Key
    Configuration key to retrieve

.OUTPUTS
    Configuration object or $null if not found
#>
function Get-CachedConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Key
    )
    
    return $script:ConfigCache[$Key]
}

#endregion

#region Configuration Validation

<#
.SYNOPSIS
    Validates that all required configurations are loaded

.OUTPUTS
    PSCustomObject with validation results and any errors
#>
function Test-ConfigurationIntegrity {
    [CmdletBinding()]
    param()
    
    $result = @{
        IsValid = $true
        Errors = @()
        LoadedConfigs = @()
    }
    
    $requiredConfigs = @('MainConfig', 'LoggingConfig', 'BloatwareList', 'EssentialAppsList')
    
    foreach ($config in $requiredConfigs) {
        if ($script:ConfigCache.ContainsKey($config)) {
            $result.LoadedConfigs += $config
        }
        else {
            $result.Errors += "Missing required configuration: $config"
            $result.IsValid = $false
        }
    }
    
    return [PSCustomObject]$result
}

#endregion

#region Module Exports

Export-ModuleMember -Function @(
    'Initialize-ConfigurationSystem',
    'Get-ConfigFilePath',
    'Get-MainConfiguration',
    'Get-LoggingConfiguration',
    'Get-BloatwareConfiguration',
    'Get-EssentialAppsConfiguration',
    'Get-AppUpgradeConfiguration',
    'Get-ReportTemplatesConfiguration',
    'Get-CachedConfiguration',
    'Test-ConfigurationIntegrity'
)

#endregion
