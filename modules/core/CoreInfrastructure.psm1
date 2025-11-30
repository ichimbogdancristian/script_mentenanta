#Requires -Version 7.0

<#
.SYNOPSIS
    Core Infrastructure Module v3.0 - Unified Infrastructure Provider

.DESCRIPTION
    Consolidated infrastructure providing unified access to all core system functions:
    - Configuration management (loading, validation, caching)
    - Structured logging (multiple output formats, performance tracking)
    - File organization (session management, temp directory structure)
    - Audit path standardization (Type1 results, Type2 diffs)

.MODULE ARCHITECTURE
    Purpose: 
        Serve as the single point of entry for all core infrastructure functions.
        All modules import this with -Global flag to make functions available to all dependencies.
    
    Dependencies:
        None - this is the foundation module
    
    Exports:
        • Get-InfrastructureStatus - Check infrastructure health
        • Initialize-MaintenanceInfrastructure - Initialize all systems
        • Get-AuditResultsPath - Standard Type1 audit result paths (FIX #4)
        • Save-DiffResults - Standard Type2 diff persistence (FIX #6)
    
    Import Pattern:
        Import-Module CoreInfrastructure.psm1 -Force -Global
        # Makes all functions available to importing module and its dependencies
    
    Used By:
        - UserInterface.psm1
        - LogProcessor.psm1
        - ReportGenerator.psm1
        - All Type2 modules (internally)
        - All Type1 modules (via global scope)

.EXECUTION FLOW
    1. MaintenanceOrchestrator imports CoreInfrastructure with -Global
    2. All functions become available globally in PowerShell session
    3. Other core modules import CoreInfrastructure (functions already available)
    4. Type2 modules import CoreInfrastructure with -Global (availability cascades)
    5. Type1 modules access CoreInfrastructure functions via inherited global scope

.DATA ORGANIZATION
    - Config: config/lists/ (bloatware-list.json, essential-apps.json, app-upgrade-config.json)
    - Config: config/settings/ (main-config.json, logging-config.json)
    - Audit Results: temp_files/data/[module]-results.json (Type1 output)
    - Diff Lists: temp_files/temp/[module]-diff.json (Type2 processing)
    - Execution Logs: temp_files/logs/[module]/execution.log (Type2 output)
    - Session Manifest: temp_files/data/session-[sessionId].json (FIX #9)

.NOTES
    Module Type: Core Infrastructure (Unified Interface - v3.0)
    Architecture: v3.0 - Split with Consolidated Core
    Line Count: 263 lines
    Version: 3.0

    Version: 3.0.0 (Refactored - Modular Architecture)
#>

using namespace System.Collections.Generic
using namespace System.IO

#region Module Architecture Notes

# v3.0 Refactoring: Path B - Consolidation
# Previously, CoreInfrastructure imported 4 separate modules:
#   - CorePaths.psm1 (path discovery functions)
#   - ConfigurationManager.psm1 (config loading/validation)
#   - LoggingSystem.psm1 (structured logging)
#   - FileOrganization.psm1 (session file management)
#
# All functions from these modules are now inlined below for simplified maintenance
# and to eliminate inter-module dependency issues.
# The archived modules remain in archive/modules/core/ for reference.

Write-Verbose "CoreInfrastructure: Consolidated module loading (Path B refactoring)"

#endregion

#region Helper Functions

<#
.SYNOPSIS
    Converts PSCustomObject to Hashtable recursively [INTERNAL HELPER]

.DESCRIPTION
    **Internal helper function - not exported from module.**
    
    Recursively converts PSCustomObject instances to Hashtable for compatibility
    with functions expecting hashtable parameters. Handles nested PSCustomObjects
    by recursively converting child objects.
    
    Used internally by configuration management functions (Get-MainConfiguration,
    Get-BloatwareConfiguration, etc.) to ensure returned data is in hashtable format
    for compatibility with Type2 modules that expect hashtable parameters.

.PARAMETER InputObject
    The PSCustomObject to convert. Accepts pipeline input via filter pattern.

.OUTPUTS
    [hashtable] Converted object, or [object] if input is not a PSCustomObject

.EXAMPLE
    PS> $obj = @{ Name = 'Test'; Nested = @{ Value = 42 } } | ConvertTo-Json | ConvertFrom-Json
    PS> $hash = $obj | ConvertTo-Hashtable
    
.NOTES
    This is an internal helper function and is intentionally NOT exported via
    Export-ModuleMember. It should only be used within CoreInfrastructure.psm1.
    
    Used by:
    - Get-MainConfiguration (line 457)
    - Get-LoggingConfiguration (line 531)
    - Get-BloatwareConfiguration (line 574)
    - Get-EssentialAppsConfiguration (line 623)
    - Get-AppUpgradeConfiguration (line 665)
    PS> $hash['Name']
    Test
    
    Converts JSON-parsed PSCustomObject to nested hashtable structure.

.NOTES
    Used internally for configuration loading and data transformation.
    Preserves all property values during conversion.
#>
filter ConvertTo-Hashtable {
    $obj = $_
    if ($obj -is [PSCustomObject]) {
        $hash = @{}
        $obj.PSObject.Properties | ForEach-Object {
            $value = $_.Value
            if ($value -is [PSCustomObject]) {
                $hash[$_.Name] = $value | ConvertTo-Hashtable
            }
            else {
                $hash[$_.Name] = $value
            }
        }
        return $hash
    }
    else {
        return $obj
    }
}

#endregion Helper Functions

#region ============================================================
#region PATH DISCOVERY SYSTEM (From CorePaths.psm1)
#region ============================================================

# Global project path discovery - makes entire project aware of its structure
$script:MaintenanceProjectPaths = @{
    ProjectRoot = $null
    ConfigRoot  = $null
    ModulesRoot = $null
    TempRoot    = $null
    ParentDir   = $null
    Initialized = $false
    InitLock    = [System.Threading.ReaderWriterLockSlim]::new([System.Threading.LockRecursionPolicy]::SupportsRecursion)
}

<#
.SYNOPSIS
    Initializes global path discovery system

.DESCRIPTION
    Performs thread-safe discovery of project root and related paths.
    Auto-detects structure and sets environment variables for all modules.

.PARAMETER HintPath
    Optional hint for project root location

.PARAMETER Force
    Force re-initialization even if already initialized

.OUTPUTS
    Boolean indicating success
#>
function Initialize-GlobalPathDiscovery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$HintPath,
        
        [Parameter(Mandatory = $false)]
        [switch]$Force
    )
    
    # Acquire write lock for thread-safe initialization
    $script:MaintenanceProjectPaths.InitLock.EnterWriteLock()
    
    try {
        # Early return if already initialized and not forcing
        if ($script:MaintenanceProjectPaths.Initialized -and -not $Force) {
            $script:MaintenanceProjectPaths.InitLock.ExitWriteLock()
            return $true
        }
        
        Write-Verbose "Initializing global path discovery system"
        
        # Method 1: Use environment variables set by orchestrator
        if ($env:MAINTENANCE_PROJECT_ROOT) {
            $script:MaintenanceProjectPaths.ProjectRoot = $env:MAINTENANCE_PROJECT_ROOT
            Write-Verbose "  Found project root from environment"
        }
        # Method 2: Use hint path
        elseif ($HintPath -and (Test-Path $HintPath)) {
            $script:MaintenanceProjectPaths.ProjectRoot = $HintPath
            Write-Verbose "  Using hint path as project root"
        }
        # Method 3: Auto-detect from calling script
        elseif ($PSScriptRoot) {
            $testPath = $PSScriptRoot
            while ($testPath -and $testPath -ne (Split-Path $testPath -Parent)) {
                if ((Test-Path (Join-Path $testPath 'config')) -and 
                    (Test-Path (Join-Path $testPath 'modules')) -and 
                    (Test-Path (Join-Path $testPath 'MaintenanceOrchestrator.ps1'))) {
                    $script:MaintenanceProjectPaths.ProjectRoot = $testPath
                    Write-Verbose "  Auto-detected project root"
                    break
                }
                $testPath = Split-Path $testPath -Parent
            }
        }
        
        # If still not found, use current location as fallback
        if (-not $script:MaintenanceProjectPaths.ProjectRoot) {
            $script:MaintenanceProjectPaths.ProjectRoot = Get-Location
            Write-Verbose "  Using current location as fallback"
        }
        
        # Initialize related paths
        $script:MaintenanceProjectPaths.ConfigRoot = Join-Path $script:MaintenanceProjectPaths.ProjectRoot 'config'
        $script:MaintenanceProjectPaths.ModulesRoot = Join-Path $script:MaintenanceProjectPaths.ProjectRoot 'modules'
        $script:MaintenanceProjectPaths.TempRoot = Join-Path $script:MaintenanceProjectPaths.ProjectRoot 'temp_files'
        $script:MaintenanceProjectPaths.ParentDir = Split-Path -Parent $script:MaintenanceProjectPaths.ProjectRoot
        
        # Set environment variables for all modules
        $env:MAINTENANCE_PROJECT_ROOT = $script:MaintenanceProjectPaths.ProjectRoot
        $env:MAINTENANCE_CONFIG_ROOT = $script:MaintenanceProjectPaths.ConfigRoot
        $env:MAINTENANCE_MODULES_ROOT = $script:MaintenanceProjectPaths.ModulesRoot
        $env:MAINTENANCE_TEMP_ROOT = $script:MaintenanceProjectPaths.TempRoot
        $env:MAINTENANCE_PARENT_DIR = $script:MaintenanceProjectPaths.ParentDir
        
        # Generate and set session ID if not already set
        if (-not $env:MAINTENANCE_SESSION_ID) {
            $sessionId = [guid]::NewGuid().ToString()
            $env:MAINTENANCE_SESSION_ID = $sessionId
        }
        
        # Make paths available globally to Type2 modules (v3.0 requirement)
        # Type2 modules reference $Global:ProjectPaths.TempFiles, $Global:ProjectPaths.Config, etc.
        $Global:ProjectPaths = @{
            ProjectRoot = $script:MaintenanceProjectPaths.ProjectRoot
            ConfigRoot  = $script:MaintenanceProjectPaths.ConfigRoot
            ModulesRoot = $script:MaintenanceProjectPaths.ModulesRoot
            TempFiles   = $script:MaintenanceProjectPaths.TempRoot
            ParentDir   = $script:MaintenanceProjectPaths.ParentDir
            Config      = $script:MaintenanceProjectPaths.ConfigRoot  # Alias
            Modules     = $script:MaintenanceProjectPaths.ModulesRoot # Alias
        }
        
        Write-Verbose "Global ProjectPaths initialized: $($Global:ProjectPaths | ConvertTo-Json)"
        
        $script:MaintenanceProjectPaths.Initialized = $true
        Write-Verbose "Path discovery completed successfully"
        return $true
    }
    finally {
        $script:MaintenanceProjectPaths.InitLock.ExitWriteLock()
    }
}

<#
.SYNOPSIS
    Gets all discovered paths

.OUTPUTS
    Hashtable with ProjectRoot, ConfigRoot, ModulesRoot, TempRoot, ParentDir, SessionId
#>
function Get-MaintenancePaths {
    [CmdletBinding()]
    param()
    
    $script:MaintenanceProjectPaths.InitLock.EnterReadLock()
    
    try {
        if (-not $script:MaintenanceProjectPaths.Initialized) {
            throw "Path discovery not initialized - call Initialize-GlobalPathDiscovery first"
        }
        
        return @{
            ProjectRoot = $script:MaintenanceProjectPaths.ProjectRoot
            ConfigRoot  = $script:MaintenanceProjectPaths.ConfigRoot
            ModulesRoot = $script:MaintenanceProjectPaths.ModulesRoot
            TempRoot    = $script:MaintenanceProjectPaths.TempRoot
            ParentDir   = $script:MaintenanceProjectPaths.ParentDir
            SessionId   = $env:MAINTENANCE_SESSION_ID
        }
    }
    finally {
        $script:MaintenanceProjectPaths.InitLock.ExitReadLock()
    }
}

<#
.SYNOPSIS
    Gets specific path by key

.PARAMETER PathKey
    Path key to retrieve

.OUTPUTS
    System.String - Full path to requested location
#>
function Get-MaintenancePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('ProjectRoot', 'ConfigRoot', 'ModulesRoot', 'TempRoot', 'ParentDir')]
        [string]$PathKey
    )
    
    $paths = Get-MaintenancePaths
    return $paths[$PathKey]
}

<#
.SYNOPSIS
    Validates that all required paths exist

.OUTPUTS
    PSCustomObject with validation results
#>
<#
.SYNOPSIS
    Gets the full path for a session directory or file

.DESCRIPTION
    Builds paths for session-based storage (temp_files directory structure)

.PARAMETER Category
    Category of path (data, logs, reports, temp, inventory)

.PARAMETER SubCategory
    Optional subdirectory under category (e.g., module name for logs)

.PARAMETER FileName
    Optional filename for the full path

.OUTPUTS
    System.String - Full path to the requested location

.EXAMPLE
    Get-SessionPath -Category 'data' -FileName 'essential-apps-results.json'
#>
function Get-SessionPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('data', 'logs', 'reports', 'temp', 'inventory')]
        [string]$Category,
        
        [Parameter()]
        [string]$SubCategory,
        
        [Parameter()]
        [string]$FileName
    )
    
    $tempRoot = Get-MaintenancePath 'TempRoot'
    
    if ([string]::IsNullOrEmpty($tempRoot)) {
        Write-Error "TempRoot path is not available"
        return $null
    }
    
    # Build the base path
    $basePath = Join-Path $tempRoot $Category
    
    # Add subcategory if provided
    if (-not [string]::IsNullOrEmpty($SubCategory)) {
        $basePath = Join-Path $basePath $SubCategory
    }
    
    # Ensure directory exists
    if (-not (Test-Path $basePath)) {
        New-Item -Path $basePath -ItemType Directory -Force | Out-Null
    }
    
    # Add filename if provided
    if (-not [string]::IsNullOrEmpty($FileName)) {
        return Join-Path $basePath $FileName
    }
    
    return $basePath
}

function Test-MaintenancePathsIntegrity {
    [CmdletBinding()]
    param()
    
    $paths = Get-MaintenancePaths
    $result = @{
        IsValid = $true
        Errors  = @()
    }
    
    $pathsToCheck = @(
        @{ Key = 'ProjectRoot'; Name = 'Project Root' }
        @{ Key = 'ConfigRoot'; Name = 'Config Root' }
        @{ Key = 'ModulesRoot'; Name = 'Modules Root' }
    )
    
    foreach ($pathCheck in $pathsToCheck) {
        if (-not (Test-Path $paths[$pathCheck.Key])) {
            $result.IsValid = $false
            $result.Errors += "Missing: $($pathCheck.Name)"
        }
    }
    
    return [PSCustomObject]$result
}

#endregion PATH DISCOVERY SYSTEM

#region Configuration Management System

<#
.SYNOPSIS
    Generic JSON configuration loader

.DESCRIPTION
    Loads any JSON configuration file from the standardized config directory structure.
    Supports both settings/ and lists/ subdirectories. Returns hashtable or PSCustomObject.

.PARAMETER ConfigType
    Type of configuration to load. Valid options: Main, Bloatware, EssentialApps, AppUpgrade, Logging, ReportTemplates

.PARAMETER ConfigPath
    Optional override for config root directory. Defaults to $env:MAINTENANCE_CONFIG_ROOT

.PARAMETER AsHashtable
    Convert result to hashtable (default: true). Set to false to return PSCustomObject

.OUTPUTS
    [hashtable] or [PSCustomObject] Configuration data

.EXAMPLE
    $config = Get-JsonConfiguration -ConfigType 'Main'
    
.EXAMPLE
    $bloatware = Get-JsonConfiguration -ConfigType 'Bloatware' -AsHashtable $false
    
.NOTES
    This is the primary configuration loader. Other Get-*Configuration functions
    are backward-compatible wrappers around this function.
#>
function Get-JsonConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Main', 'Bloatware', 'EssentialApps', 'AppUpgrade', 'SystemOptimization', 'Security', 'Logging', 'ReportTemplates')]
        [string]$ConfigType,
        
        [Parameter()]
        [string]$ConfigPath = $env:MAINTENANCE_CONFIG_ROOT,
        
        [Parameter()]
        [bool]$AsHashtable = $true
    )
    
    # Map config types to file paths (relative to CONFIG_ROOT)
    $configFiles = @{
        'Main'               = 'settings\main-config.json'
        'Bloatware'          = 'lists\bloatware-list.json'
        'EssentialApps'      = 'lists\essential-apps.json'
        'AppUpgrade'         = 'lists\app-upgrade-config.json'
        'SystemOptimization' = 'lists\system-optimization-config.json'
        'Security'           = 'settings\security-config.json'
        'Logging'            = 'settings\logging-config.json'
        'ReportTemplates'    = 'templates\report-template-config.json'
    }
    
    # Default return values for each config type
    $defaultValues = @{
        'Main'               = @{}
        'Bloatware'          = @{ all = @() }
        'EssentialApps'      = @{ all = @() }
        'AppUpgrade'         = @{ all = @() }
        'SystemOptimization' = @{ startupPrograms = @{ safeToDisablePatterns = @() }; services = @{ safeToDisable = @() } }
        'Security'           = @{ security = @{ enableDigitalSignatureVerification = $true; enableRealTimeProtection = $true; defenderIntegration = $true; enableAuditLogging = $true }; compliance = @{ enableCISBaseline = $true; enforceExecutionPolicy = 'RemoteSigned' } }
        'Logging'            = @{ levels = @('INFO', 'WARNING', 'ERROR') }
        'ReportTemplates'    = @{}
    }
    
    try {
        $configFile = Join-Path $ConfigPath $configFiles[$ConfigType]
        
        if (-not (Test-Path $configFile)) {
            # For AppUpgrade, check legacy path
            if ($ConfigType -eq 'AppUpgrade') {
                $legacyPath = Join-Path $ConfigPath 'data\app-upgrade-config.json'
                if (Test-Path $legacyPath) {
                    Write-Warning "Using legacy config path 'data/' - please migrate to 'lists/' directory"
                    $configFile = $legacyPath
                }
                else {
                    Write-Verbose "$ConfigType configuration not found at: $configFile"
                    return $defaultValues[$ConfigType]
                }
            }
            else {
                Write-Verbose "$ConfigType configuration not found at: $configFile"
                return $defaultValues[$ConfigType]
            }
        }
        
        Write-Verbose "Loading $ConfigType configuration from: $configFile"
        $content = Get-Content $configFile -Raw -ErrorAction Stop
        $config = $content | ConvertFrom-Json -ErrorAction Stop
        
        if ($AsHashtable) {
            return $config | ConvertTo-Hashtable
        }
        else {
            return $config
        }
    }
    catch {
        $errorMsg = "Failed to load $ConfigType configuration from ${configFile}: $($_.Exception.Message)"
        
        # Main config failure should throw (critical)
        if ($ConfigType -eq 'Main') {
            throw $errorMsg
        }
        else {
            Write-Warning $errorMsg
            return $defaultValues[$ConfigType]
        }
    }
}

<#
.SYNOPSIS
    Gets main system configuration

.DESCRIPTION
    Loads main-config.json from settings/ directory.
    This is a backward-compatible wrapper around Get-JsonConfiguration.

.PARAMETER ConfigPath
    Optional override for config root directory

.OUTPUTS
    Hashtable with configuration settings

.EXAMPLE
    $config = Get-MainConfiguration
#>
function Get-MainConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$ConfigPath = $env:MAINTENANCE_CONFIG_ROOT
    )
    
    return Get-JsonConfiguration -ConfigType 'Main' -ConfigPath $ConfigPath
}

#region Privilege and Security Validation

<#
.SYNOPSIS
    Asserts that the current process has administrator privileges

.DESCRIPTION
    Verifies that the script is running with administrator privileges.
    If not, throws an exception with the provided operation description.

.PARAMETER Operation
    Description of the operation requiring admin privileges (for error message)

.EXAMPLE
    Assert-AdminPrivilege -Operation "Windows service modification"
#>
function Assert-AdminPrivilege {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Operation
    )
    
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    
    if (-not $isAdmin) {
        throw "Administrator privileges are required for: $Operation"
    }
}

#endregion

<#
.SYNOPSIS
    Initializes module execution environment with standard validations

.DESCRIPTION
    Performs common initialization checks required by Type2 modules:
    - Validates temp_files structure exists
    - Optionally checks administrator privileges
    
    This consolidates duplicate validation code across modules.

.PARAMETER ModuleName
    Name of the calling module (for error messages)

.PARAMETER RequireAdmin
    If specified, validates administrator privileges

.PARAMETER Operation
    Description of operation requiring admin rights (used with -RequireAdmin)

.EXAMPLE
    Initialize-ModuleExecution -ModuleName 'BloatwareRemoval'

.EXAMPLE
    Initialize-ModuleExecution -ModuleName 'WindowsUpdates' -RequireAdmin -Operation 'Windows Update installation'
#>
function Initialize-ModuleExecution {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ModuleName,
        
        [Parameter()]
        [switch]$RequireAdmin,
        
        [Parameter()]
        [string]$Operation
    )
    
    # Validate temp_files structure
    if (-not (Test-TempFilesStructure)) {
        throw "$ModuleName`: Failed to initialize temp_files directory structure"
    }
    
    # Validate admin privileges if required
    if ($RequireAdmin) {
        $operationDesc = if ($Operation) { $Operation } else { "$ModuleName execution" }
        Assert-AdminPrivilege -Operation $operationDesc
    }
}

#endregion

<#
.SYNOPSIS
    Gets bloatware configuration list

.DESCRIPTION
    Loads bloatware-list.json from lists/ or data/ directory
    Returns hashtable with 'all' key containing array of apps

.OUTPUTS
    Hashtable with bloatware entries

.EXAMPLE
    $bloatware = Get-BloatwareConfiguration
    $bloatware.all  # Returns array of bloatware names
#>
function Get-BloatwareConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$ConfigPath = $env:MAINTENANCE_CONFIG_ROOT
    )
    
    return Get-JsonConfiguration -ConfigType 'Bloatware' -ConfigPath $ConfigPath
}

<#
.SYNOPSIS
    Gets essential applications configuration

.DESCRIPTION
    Loads essential-apps.json from lists/ or data/ directory
    Returns hashtable with application definitions

.OUTPUTS
    Hashtable with essential apps configuration

.EXAMPLE
    $apps = Get-EssentialAppsConfiguration
    $apps.all  # Returns array of app definitions
#>
function Get-EssentialAppsConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$ConfigPath = $env:MAINTENANCE_CONFIG_ROOT
    )
    
    return Get-JsonConfiguration -ConfigType 'EssentialApps' -ConfigPath $ConfigPath
}

<#
.SYNOPSIS
    Gets app upgrade configuration

.DESCRIPTION
    Loads app-upgrade-config.json from lists/ or data/ directory
    Returns hashtable with app upgrade settings

.OUTPUTS
    Hashtable with app upgrade configuration

.EXAMPLE
    $upgradeConfig = Get-AppUpgradeConfiguration
#>
function Get-AppUpgradeConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$ConfigPath = $env:MAINTENANCE_CONFIG_ROOT
    )
    
    return Get-JsonConfiguration -ConfigType 'AppUpgrade' -ConfigPath $ConfigPath
}

<#
.SYNOPSIS
    Gets system optimization configuration

.DESCRIPTION
    Loads system-optimization-config.json from lists/ directory
    Returns hashtable with optimization settings (startup programs, services, etc.)

.OUTPUTS
    Hashtable with system optimization configuration

.EXAMPLE
    $optimizationConfig = Get-SystemOptimizationConfiguration
#>
function Get-SystemOptimizationConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$ConfigPath = $env:MAINTENANCE_CONFIG_ROOT
    )
    
    return Get-JsonConfiguration -ConfigType 'SystemOptimization' -ConfigPath $ConfigPath
}

<#
.SYNOPSIS
    Gets security configuration

.DESCRIPTION
    Loads security-config.json configuration for security enhancement module

.OUTPUTS
    Hashtable with security configuration
#>
function Get-SecurityConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$ConfigPath = $env:MAINTENANCE_CONFIG_ROOT
    )
    
    return Get-JsonConfiguration -ConfigType 'Security' -ConfigPath $ConfigPath
}

<#
.SYNOPSIS
    Gets logging configuration

.DESCRIPTION
    Loads logging-config.json configuration

.OUTPUTS
    Hashtable with logging configuration
#>
function Get-LoggingConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$ConfigPath = $env:MAINTENANCE_CONFIG_ROOT
    )
    
    return Get-JsonConfiguration -ConfigType 'Logging' -ConfigPath $ConfigPath
}

<#
.SYNOPSIS
    Gets configuration file path

.DESCRIPTION
    Returns path to a configuration file
#>
function Get-ConfigFilePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ConfigName
    )
    
    $configPath = Join-Path $env:MAINTENANCE_CONFIG_ROOT "settings/$ConfigName"
    return $configPath
}

<#
.SYNOPSIS
    Tests configuration integrity properties from objects using dot notation

.DESCRIPTION
    Retrieves nested property values from hashtables or PSCustomObjects using
    dot notation paths (e.g., "execution.countdownSeconds")

.PARAMETER Object
    The object to query (hashtable or PSCustomObject)

.PARAMETER PropertyPath
    Dot-notation path to the property (e.g., "execution.countdownSeconds")

.OUTPUTS
    The property value, or $null if not found

.EXAMPLE
    $value = Get-NestedProperty -Object $config -PropertyPath "execution.countdownSeconds"
#>
function Get-NestedProperty {
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Object,
        
        [Parameter(Mandatory = $true)]
        [string]$PropertyPath
    )
    
    try {
        $parts = $PropertyPath -split '\.'
        $current = $Object
        
        foreach ($part in $parts) {
            if ($null -eq $current) {
                return $null
            }
            
            if ($current -is [hashtable]) {
                $current = $current[$part]
            }
            elseif ($current.PSObject.Properties[$part]) {
                $current = $current.PSObject.Properties[$part].Value
            }
            else {
                return $null
            }
        }
        
        return $current
    }
    catch {
        Write-Verbose "Failed to get nested property '$PropertyPath': $($_.Exception.Message)"
        return $null
    }
}

<#
.SYNOPSIS
    Validates configuration against schema definitions

.DESCRIPTION
    v3.1: Comprehensive configuration schema validation beyond JSON syntax checking.
    Validates required fields, data types, value ranges, and enumerations.

.PARAMETER ConfigObject
    The configuration object to validate (hashtable or PSCustomObject)

.PARAMETER ConfigName
    Name of the configuration file (e.g., "main-config.json")

.PARAMETER ThrowOnError
    If specified, throws an exception on validation failure instead of returning false

.OUTPUTS
    Boolean indicating validation success, or throws exception if ThrowOnError is set

.EXAMPLE
    $valid = Test-ConfigurationSchema -ConfigObject $config -ConfigName "main-config.json"
    
.EXAMPLE
    Test-ConfigurationSchema -ConfigObject $config -ConfigName "main-config.json" -ThrowOnError
#>
function Test-ConfigurationSchema {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [object]$ConfigObject,
        
        [Parameter(Mandatory = $true)]
        [string]$ConfigName,
        
        [switch]$ThrowOnError
    )
    
    # Define configuration schemas (v3.1)
    $schemas = @{
        'main-config.json'    = @{
            'execution.countdownSeconds'      = @{ Type = 'int'; Min = 5; Max = 300; Required = $true; Description = 'Menu countdown duration in seconds' }
            'execution.defaultMode'           = @{ Type = 'string'; Enum = @('unattended', 'interactive', 'dryrun'); Required = $false; Description = 'Default execution mode' }
            'execution.enableDryRun'          = @{ Type = 'bool'; Required = $false; Description = 'Enable dry-run mode by default' }
            'modules.skipBloatwareRemoval'    = @{ Type = 'bool'; Required = $false; Description = 'Skip bloatware removal module' }
            'modules.skipEssentialApps'       = @{ Type = 'bool'; Required = $false; Description = 'Skip essential apps module' }
            'modules.skipWindowsUpdates'      = @{ Type = 'bool'; Required = $false; Description = 'Skip Windows updates module' }
            'system.createSystemRestorePoint' = @{ Type = 'bool'; Required = $false; Description = 'Create restore point before changes' }
            'system.maxLogSizeMB'             = @{ Type = 'int'; Min = 1; Max = 100; Required = $false; Description = 'Maximum log file size in MB' }
            'reporting.enableHtmlReport'      = @{ Type = 'bool'; Required = $false; Description = 'Generate HTML reports' }
            'paths.tempFolder'                = @{ Type = 'string'; Required = $false; Description = 'Temporary files directory' }
        }
        
        'logging-config.json' = @{
            'logging.level'        = @{ Type = 'string'; Enum = @('DEBUG', 'INFO', 'WARN', 'ERROR', 'CRITICAL'); Required = $false; Description = 'Default logging level' }
            'logging.maxLogSizeKB' = @{ Type = 'int'; Min = 100; Max = 102400; Required = $false; Description = 'Maximum log size in KB' }
        }
        
        'bloatware-list.json' = @{
            '_type'        = 'object'
            '_description' = 'Bloatware configuration with whitelist'
            'bloatware'    = @{ Type = 'array'; Required = $false; Description = 'List of bloatware definitions' }
            'whitelist'    = @{ Type = 'array'; Required = $false; Description = 'Apps to never remove' }
        }
        
        'essential-apps.json' = @{
            '_type'         = 'object'
            '_description'  = 'Essential applications configuration'
            'essentialApps' = @{ Type = 'array'; Required = $false; Description = 'List of essential applications' }
        }
    }
    
    # Get schema for this config
    $schema = $schemas[$ConfigName]
    if (-not $schema) {
        Write-Verbose "No schema defined for configuration: $ConfigName (skipping validation)"
        return $true
    }
    
    $errors = @()
    
    try {
        # Validate each field in the schema
        foreach ($fieldPath in $schema.Keys) {
            # Skip metadata fields
            if ($fieldPath -like '_*') {
                continue
            }
            
            $fieldSchema = $schema[$fieldPath]
            $value = Get-NestedProperty -Object $ConfigObject -PropertyPath $fieldPath
            
            # Check required fields
            if ($fieldSchema.Required -and $null -eq $value) {
                $errors += "Required field missing: $fieldPath ($($fieldSchema.Description))"
                continue
            }
            
            # Skip validation if field is optional and not present
            if ($null -eq $value -and -not $fieldSchema.Required) {
                continue
            }
            
            # Type validation
            $expectedType = $fieldSchema.Type
            $actualValue = $value
            
            switch ($expectedType) {
                'int' {
                    if ($actualValue -isnot [int] -and $actualValue -isnot [int32] -and $actualValue -isnot [int64]) {
                        try {
                            $actualValue = [int]$actualValue
                        }
                        catch {
                            $errors += "Field '$fieldPath' must be an integer (got: $($value.GetType().Name))"
                            continue
                        }
                    }
                    
                    # Range validation
                    if ($fieldSchema.Min -and $actualValue -lt $fieldSchema.Min) {
                        $errors += "Field '$fieldPath' value $actualValue is below minimum $($fieldSchema.Min)"
                    }
                    if ($fieldSchema.Max -and $actualValue -gt $fieldSchema.Max) {
                        $errors += "Field '$fieldPath' value $actualValue exceeds maximum $($fieldSchema.Max)"
                    }
                }
                
                'bool' {
                    if ($actualValue -isnot [bool]) {
                        $errors += "Field '$fieldPath' must be a boolean (got: $($value.GetType().Name))"
                    }
                }
                
                'string' {
                    if ($actualValue -isnot [string]) {
                        $errors += "Field '$fieldPath' must be a string (got: $($value.GetType().Name))"
                        continue
                    }
                    
                    # Enum validation
                    if ($fieldSchema.Enum -and $actualValue -notin $fieldSchema.Enum) {
                        $errors += "Field '$fieldPath' value '$actualValue' not in allowed values: $($fieldSchema.Enum -join ', ')"
                    }
                }
                
                'array' {
                    if ($actualValue -isnot [array] -and $actualValue -isnot [System.Collections.IEnumerable]) {
                        $errors += "Field '$fieldPath' must be an array (got: $($value.GetType().Name))"
                    }
                }
                
                'object' {
                    if ($actualValue -isnot [hashtable] -and $actualValue -isnot [PSCustomObject]) {
                        $errors += "Field '$fieldPath' must be an object (got: $($value.GetType().Name))"
                    }
                }
            }
        }
        
        # Report results
        if ($errors.Count -gt 0) {
            $errorMessage = "Configuration validation failed for $ConfigName`:`n  • " + ($errors -join "`n  • ")
            
            if ($ThrowOnError) {
                throw $errorMessage
            }
            else {
                Write-Warning $errorMessage
                return $false
            }
        }
        
        Write-Verbose "Configuration schema validation passed for: $ConfigName"
        return $true
    }
    catch {
        if ($ThrowOnError) {
            throw
        }
        else {
            Write-Warning "Configuration validation error for $ConfigName`: $($_.Exception.Message)"
            return $false
        }
    }
}

#endregion Configuration Management System

<#
.SYNOPSIS
    Initializes the configuration system

.DESCRIPTION
    Validates that all required configuration files exist
    This is called during MaintenanceOrchestrator startup

.PARAMETER ConfigRootPath
    Path to configuration root directory

.OUTPUTS
    Boolean indicating success

.EXAMPLE
    Initialize-ConfigurationSystem -ConfigRootPath $env:MAINTENANCE_CONFIG_ROOT
#>
function Initialize-ConfigurationSystem {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ConfigRootPath
    )
    
    Write-Verbose "Initializing configuration system at: $ConfigRootPath"
    
    try {
        # Validate required configuration files
        $requiredFiles = @(
            @{ Name = 'main-config.json'; NewPath = 'settings'; OldPath = 'execution' },
            @{ Name = 'logging-config.json'; NewPath = 'settings'; OldPath = 'execution' }
        )
        
        foreach ($file in $requiredFiles) {
            $newPath = Join-Path $ConfigRootPath "$($file.NewPath)/$($file.Name)"
            $oldPath = Join-Path $ConfigRootPath "$($file.OldPath)/$($file.Name)"
            
            if (-not ((Test-Path $newPath) -or (Test-Path $oldPath))) {
                throw "Required configuration file not found: $($file.Name)"
            }
        }
        
        Write-Verbose "Configuration system initialized successfully"
        return $true
    }
    catch {
        Write-Error "Configuration system initialization failed: $($_.Exception.Message)"
        return $false
    }
}

#endregion Configuration Management System

#region Backward Compatibility Aliases

# Note: Removed unused aliases (Get-MainConfig, Get-BloatwareList) as of v3.1
# All code now uses full function names for clarity
New-Alias -Name 'Get-UnifiedEssentialAppsList' -Value 'Get-EssentialAppsConfiguration' -Force
Export-ModuleMember -Alias 'Get-UnifiedEssentialAppsList'

#endregion

#region Logging System

# Logging standards for unified format across all components
$script:LoggingStandards = @{
    TimestampFormat = 'yyyy-MM-ddTHH:mm:ss.fffK'  # ISO 8601 with timezone
    EntryFormat     = '[{0}] [{1}] [{2}] {3}'      # [TIMESTAMP] [LEVEL] [COMPONENT] MESSAGE
    Levels          = @('DEBUG', 'INFO', 'WARNING', 'SUCCESS', 'ERROR')
    Components      = @('LAUNCHER', 'ORCHESTRATOR', 'CORE', 'TYPE1', 'TYPE2', 'REPORTER')
}

<#
.SYNOPSIS
    Creates a standardized log entry string

.DESCRIPTION
    Generates log entry following unified format: [TIMESTAMP] [LEVEL] [COMPONENT] MESSAGE
    Uses ISO 8601 timestamp format for consistency across all system components

.PARAMETER Level
    Log level (DEBUG, INFO, WARNING, SUCCESS, ERROR)

.PARAMETER Component
    Component identifier (e.g., LAUNCHER, ORCHESTRATOR, module name)

.PARAMETER Message
    Log message content

.OUTPUTS
    Formatted log entry string

.EXAMPLE
    New-StandardLogEntry -Level 'INFO' -Component 'ORCHESTRATOR' -Message 'Starting maintenance'
    # Returns: [2025-10-27T14:30:15.123+00:00] [INFO] [ORCHESTRATOR] Starting maintenance
#>
function New-StandardLogEntry {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('DEBUG', 'INFO', 'WARNING', 'SUCCESS', 'ERROR')]
        [string]$Level,
        
        [Parameter(Mandatory = $true)]
        [string]$Component,
        
        [Parameter(Mandatory = $true)]
        [string]$Message
    )
    
    $timestamp = Get-Date -Format $script:LoggingStandards.TimestampFormat
    return $script:LoggingStandards.EntryFormat -f $timestamp, $Level, $Component, $Message
}

<#
.SYNOPSIS
    Initializes structured logging system

.DESCRIPTION
    Sets up logging infrastructure for Type2 modules
    Creates log directory structure and initializes logging variables

.PARAMETER LoggingConfig
    Logging configuration object from main config

.PARAMETER BaseLogPath
    Base path for log files

.OUTPUTS
    Boolean indicating success

.EXAMPLE
    Initialize-LoggingSystem -LoggingConfig $loggingConfig -BaseLogPath "C:\logs"
#>
function Initialize-LoggingSystem {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$BaseLogPath = (Join-Path $env:MAINTENANCE_TEMP_ROOT 'logs\maintenance.log')
    )
    
    try {
        # Create log directory
        $logDir = Split-Path -Parent $BaseLogPath
        if (-not (Test-Path $logDir)) {
            New-Item -Path $logDir -ItemType Directory -Force | Out-Null
        }
        
        Write-Verbose "Logging system initialized at: $BaseLogPath"
        return $true
    }
    catch {
        Write-Error "Failed to initialize logging system: $($_.Exception.Message)"
        return $false
    }
}

<#
.SYNOPSIS
    Writes a structured log entry

.DESCRIPTION
    Writes a log entry with level, component, and message
    Supports both console and file output

.PARAMETER Level
    Log level (INFO, WARNING, ERROR, SUCCESS, DEBUG)

.PARAMETER Component
    Component name (e.g., 'ORCHESTRATOR', 'BLOATWARE-REMOVAL')

.PARAMETER Message
    Log message

.PARAMETER Data
    Optional hashtable of additional data

.EXAMPLE
    Write-ModuleLogEntry -Level 'INFO' -Component 'ORCHESTRATOR' -Message "Task started"
#>
function Write-ModuleLogEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('INFO', 'WARNING', 'ERROR', 'SUCCESS', 'DEBUG')]
        [string]$Level,
        
        [Parameter(Mandatory = $true)]
        [string]$Component,
        
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [Parameter(Mandatory = $false)]
        [hashtable]$Data = @{}
    )
    
    # Use standardized log entry format
    $logEntry = New-StandardLogEntry -Level $Level -Component $Component -Message $Message
    
    if ($Data.Count -gt 0) {
        $logEntry += " | Data: $(($Data.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ', ')"
    }
    
    Write-Information $logEntry -InformationAction Continue
}

# Backward compatibility alias
New-Alias -Name 'Write-LogEntry' -Value 'Write-ModuleLogEntry' -Force

<#
.SYNOPSIS
    Starts performance tracking for an operation

.DESCRIPTION
    Creates a context object for tracking operation performance
    Returns context that should be passed to Complete-PerformanceTracking

.PARAMETER OperationName
    Name of operation being tracked

.PARAMETER Component
    Component performing operation

.OUTPUTS
    PSCustomObject with tracking context

.EXAMPLE
    $context = Start-PerformanceTracking -OperationName 'BloatwareRemoval' -Component 'BLOATWARE'
#>
<#
.SYNOPSIS
    Safely starts performance tracking with automatic error handling

.DESCRIPTION
    Wrapper around Start-PerformanceTracking that handles errors gracefully.
    Returns $null if performance tracking is not available.

.PARAMETER OperationName
    Name of the operation to track

.PARAMETER Component
    Component identifier for logging

.OUTPUTS
    Performance context object or $null if unavailable

.EXAMPLE
    $perfContext = Start-PerformanceTrackingSafe -OperationName 'ModuleName' -Component 'MODULE'
#>
function Start-PerformanceTrackingSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$OperationName,
        
        [Parameter(Mandatory = $false)]
        [string]$Component = 'UNKNOWN'
    )
    
    try {
        return Start-PerformanceTracking -OperationName $OperationName -Component $Component
    }
    catch {
        Write-Verbose "Performance tracking not available: $($_.Exception.Message)"
        return $null
    }
}

function Start-PerformanceTracking {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$OperationName,
        
        [Parameter(Mandatory = $false)]
        [string]$Component = 'UNKNOWN'
    )
    
    return @{
        OperationName = $OperationName
        Component     = $Component
        StartTime     = Get-Date
        Status        = 'Running'
    }
}

<#
.SYNOPSIS
    Completes performance tracking

.DESCRIPTION
    Calculates performance metrics and logs results

.PARAMETER Context
    Context object from Start-PerformanceTracking

.PARAMETER Status
    Final status (Success, Failed, Cancelled)

.PARAMETER ErrorMessage
    Optional error message if failed

.EXAMPLE
    Complete-PerformanceTracking -Context $context -Status 'Success'
#>
function Complete-PerformanceTracking {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Context,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet('Success', 'Failed', 'Cancelled')]
        [string]$Status = 'Success',
        
        [Parameter(Mandatory = $false)]
        [string]$ErrorMessage = ''
    )
    
    $endTime = Get-Date
    $duration = ($endTime - $Context.StartTime).TotalMilliseconds
    
    $message = "[$($Context.Component)] $($Context.OperationName): $Status (${duration}ms)"
    if ($ErrorMessage) {
        $message += " | Error: $ErrorMessage"
    }
    
    Write-ModuleLogEntry -Level $(if ($Status -eq 'Success') { 'SUCCESS' } else { 'ERROR' }) `
        -Component $Context.Component `
        -Message $message
    
    # Don't return anything - avoid pipeline contamination
    # Performance data is already logged
    [void]0
}

<#
.SYNOPSIS
    Write operation start message

.DESCRIPTION
    Logs the start of an operation
#>
function Write-OperationStart {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false, ParameterSetName = 'Modern')]
        [string]$Operation,
        
        [Parameter(Mandatory = $false, ParameterSetName = 'Modern')]
        [string]$Target,
        
        [Parameter(Mandatory = $false, ParameterSetName = 'Modern')]
        [string]$Component = 'OPERATION',
        
        [Parameter(Mandatory = $false, ParameterSetName = 'Modern')]
        [string]$LogPath,
        
        [Parameter(Mandatory = $false, ParameterSetName = 'Modern')]
        [hashtable]$AdditionalInfo,
        
        # Legacy parameter support
        [Parameter(Mandatory = $false, ParameterSetName = 'Legacy')]
        [string]$OperationName,
        
        [Parameter(Mandatory = $false, ParameterSetName = 'Legacy')]
        [string]$ComponentName = 'OPERATION'
    )
    
    if ($PSCmdlet.ParameterSetName -eq 'Legacy') {
        Write-ModuleLogEntry -Level 'INFO' -Component $ComponentName -Message "Starting: $OperationName"
    }
    else {
        $message = "Starting: $Operation"
        if (-not [string]::IsNullOrEmpty($Target)) {
            $message += " - Target: $Target"
        }
        
        if (-not [string]::IsNullOrEmpty($LogPath)) {
            Write-StructuredLogEntry -Level 'INFO' -Component $Component -Message $message -LogPath $LogPath -Operation $Operation -Target $Target -Metadata $AdditionalInfo
        }
        else {
            Write-ModuleLogEntry -Level 'INFO' -Component $Component -Message $message
        }
    }
}

#endregion

#region Enhanced Operation Logging - Modern Signatures

<#
.SYNOPSIS
    Write operation success message
.DESCRIPTION
    Logs successful completion of an operation
#>
function Write-OperationSuccess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false, ParameterSetName = 'Modern')]
        [string]$Operation,
        
        [Parameter(Mandatory = $false, ParameterSetName = 'Modern')]
        [string]$Target,
        
        [Parameter(Mandatory = $false, ParameterSetName = 'Modern')]
        [string]$Component = 'OPERATION',
        
        [Parameter(Mandatory = $false, ParameterSetName = 'Modern')]
        [string]$LogPath,
        
        [Parameter(Mandatory = $false, ParameterSetName = 'Modern')]
        [hashtable]$Metrics,
        
        # Legacy parameter support
        [Parameter(Mandatory = $false, ParameterSetName = 'Legacy')]
        [string]$OperationName,
        
        [Parameter(Mandatory = $false, ParameterSetName = 'Legacy')]
        [string]$ComponentName = 'OPERATION'
    )
    
    if ($PSCmdlet.ParameterSetName -eq 'Legacy') {
        Write-ModuleLogEntry -Level 'SUCCESS' -Component $ComponentName -Message "Completed: $OperationName"
    }
    else {
        $message = "Completed: $Operation"
        if (-not [string]::IsNullOrEmpty($Target)) {
            $message += " - Target: $Target"
        }
        
        if (-not [string]::IsNullOrEmpty($LogPath)) {
            Write-StructuredLogEntry -Level 'SUCCESS' -Component $Component -Message $message -LogPath $LogPath -Operation $Operation -Target $Target -Result 'Success' -Metadata $Metrics
        }
        else {
            Write-ModuleLogEntry -Level 'SUCCESS' -Component $Component -Message $message
        }
    }
}

<#
.SYNOPSIS
    Write operation failure message
.DESCRIPTION
    Logs failed operation
#>
function Write-OperationFailure {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Operation,
        
        [Parameter(Mandatory = $false)]
        [string]$Target,
        
        [Parameter(Mandatory = $false)]
        [string]$Component = 'OPERATION',
        
        [Parameter(Mandatory = $false)]
        [string]$LogPath,
        
        [Parameter(Mandatory = $false)]
        [object]$Error,
        
        [Parameter(Mandatory = $false)]
        [hashtable]$AdditionalInfo,
        
        # Legacy parameters
        [Parameter(Mandatory = $false)]
        [string]$OperationName,
        
        [Parameter(Mandatory = $false)]
        [string]$ComponentName = 'OPERATION'
    )
    
    try {
        if (-not [string]::IsNullOrEmpty($OperationName)) {
            # Legacy usage
            Write-ModuleLogEntry -Level 'ERROR' -Component $ComponentName -Message "Failed: $OperationName"
        }
        else {
            # Modern usage
            $message = "Failed: $Operation"
            if (-not [string]::IsNullOrEmpty($Target)) {
                $message += " - Target: $Target"
            }
            if ($Error) {
                $message += " - Error: $($Error.ToString())"
            }
            
            if (-not [string]::IsNullOrEmpty($LogPath)) {
                Write-StructuredLogEntry -Level 'ERROR' -Component $Component -Message $message -LogPath $LogPath -Operation $Operation -Target $Target -Result 'Failed' -Metadata $AdditionalInfo
            }
            else {
                Write-ModuleLogEntry -Level 'ERROR' -Component $Component -Message $message
            }
        }
    }
    catch {
        Write-ModuleLogEntry -Level 'ERROR' -Component $Component -Message "Error in Write-OperationFailure: $_"
    }
}

<#
.SYNOPSIS
    Write operation skipped message
.DESCRIPTION
    Logs skipped operation
#>
function Write-OperationSkipped {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Operation,
        
        [Parameter(Mandatory = $false)]
        [string]$Target,
        
        [Parameter(Mandatory = $false)]
        [string]$Component = 'OPERATION',
        
        [Parameter(Mandatory = $false)]
        [string]$LogPath,
        
        [Parameter(Mandatory = $false)]
        [string]$Reason,
        
        [Parameter(Mandatory = $false)]
        [hashtable]$AdditionalInfo
    )
    
    $message = "Skipped: $Operation"
    if (-not [string]::IsNullOrEmpty($Target)) {
        $message += " - Target: $Target"
    }
    if (-not [string]::IsNullOrEmpty($Reason)) {
        $message += " - Reason: $Reason"
    }
    
    if (-not [string]::IsNullOrEmpty($LogPath)) {
        Write-StructuredLogEntry -Level 'WARNING' -Component $Component -Message $message -LogPath $LogPath -Operation $Operation -Target $Target -Result 'Skipped' -Metadata $AdditionalInfo
    }
    else {
        Write-ModuleLogEntry -Level 'WARNING' -Component $Component -Message $message
    }
}

#region Logging Control

<#
.SYNOPSIS
    Enable or disable logging
#region Session File Organization

<#
.SYNOPSIS
    Initialize session file organization

.DESCRIPTION
    Sets up directory structure for session files
#>
function Initialize-SessionFileOrganization {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$SessionRoot = $env:MAINTENANCE_TEMP_ROOT
    )
    
    try {
        $directories = @('data', 'logs', 'reports', 'temp', 'inventory')
        foreach ($dir in $directories) {
            $path = Join-Path $SessionRoot $dir
            if (-not (Test-Path $path)) {
                New-Item -Path $path -ItemType Directory -Force | Out-Null
            }
        }
        return $true
    }
    catch {
        Write-Error "Failed to initialize session file organization: $_"
        return $false
    }
}

<#
.SYNOPSIS
    Validates temp_files directory structure

.DESCRIPTION
    Verifies that the complete temp_files directory structure exists and is accessible.
    Creates missing directories if necessary. Required by Type2 modules to ensure
    proper data organization before execution.

.PARAMETER TempRoot
    Root path of temp_files directory (defaults to MAINTENANCE_TEMP_ROOT environment variable)

.OUTPUTS
    [bool] $true if structure is valid and accessible, $false otherwise

.EXAMPLE
    PS> Test-TempFilesStructure
    
    Verifies standard temp_files structure exists (data/, temp/, logs/, reports/)

.NOTES
    Called automatically by each Type2 module at execution start.
    Creates any missing subdirectories to prevent runtime failures.
#>
function Test-TempFilesStructure {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $false)]
        [string]$TempRoot = $env:MAINTENANCE_TEMP_ROOT
    )
    
    try {
        if (-not $TempRoot) {
            Write-LogEntry -Level 'ERROR' -Component 'FILE-ORG' -Message 'TempRoot path not set (MAINTENANCE_TEMP_ROOT environment variable missing)'
            return $false
        }
        
        # Ensure root temp directory exists
        if (-not (Test-Path $TempRoot)) {
            Write-LogEntry -Level 'WARNING' -Component 'FILE-ORG' -Message "Creating missing TempRoot directory: $TempRoot"
            New-Item -Path $TempRoot -ItemType Directory -Force -ErrorAction Stop | Out-Null
        }
        
        # Required subdirectories for v3.0 architecture
        $requiredDirs = @('data', 'temp', 'logs', 'reports', 'inventory')
        $missingDirs = @()
        
        foreach ($dir in $requiredDirs) {
            $fullPath = Join-Path $TempRoot $dir
            if (-not (Test-Path $fullPath)) {
                $missingDirs += $dir
                Write-LogEntry -Level 'WARNING' -Component 'FILE-ORG' -Message "Creating missing subdirectory: $fullPath"
                New-Item -Path $fullPath -ItemType Directory -Force -ErrorAction Stop | Out-Null
            }
        }
        
        # Verify write access
        $testFile = Join-Path $TempRoot '.test-access'
        try {
            'test' | Set-Content $testFile -Force -ErrorAction Stop
            Remove-Item $testFile -Force -ErrorAction SilentlyContinue
        }
        catch {
            Write-LogEntry -Level 'ERROR' -Component 'FILE-ORG' -Message "No write access to TempRoot: $TempRoot"
            return $false
        }
        
        if ($missingDirs.Count -gt 0) {
            Write-LogEntry -Level 'INFO' -Component 'FILE-ORG' -Message "Temp structure validated and repaired (created: $($missingDirs -join ', '))"
        }
        else {
            Write-LogEntry -Level 'DEBUG' -Component 'FILE-ORG' -Message "Temp structure validated - all required directories present"
        }
        
        return $true
    }
    catch {
        Write-LogEntry -Level 'ERROR' -Component 'FILE-ORG' -Message "Failed to validate temp_files structure: $($_.Exception.Message)"
        return $false
    }
}

<#
.SYNOPSIS
    Get session file path

.DESCRIPTION
    Returns path for a session file
#>
<#
.SYNOPSIS
    Get session directory path

.DESCRIPTION
    Returns path for a session directory
#>
function Get-SessionDirectoryPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [ValidateSet('data', 'logs', 'reports', 'temp')]
        [string]$Type = 'temp'
    )
    
    return Join-Path $env:MAINTENANCE_TEMP_ROOT $Type
}

<#
.SYNOPSIS
    Save session data

.DESCRIPTION
    Saves data to session storage
#>
function Save-SessionData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FileName,
        
        [Parameter(Mandatory = $true)]
        [object]$Data,
        
        [Parameter(Mandatory = $false)]
        [string]$Type = 'data'
    )
    
    $path = Get-SessionFilePath -FileName $FileName -Type $Type
    $Data | ConvertTo-Json | Set-Content -Path $path -Encoding UTF8
}

<#
.SYNOPSIS
    Get session data

.DESCRIPTION
    Retrieves data from session storage
#>
function Get-SessionData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FileName,
        
        [Parameter(Mandatory = $false)]
        [string]$Type = 'data'
    )
    
    $path = Get-SessionFilePath -FileName $FileName -Type $Type
    if (Test-Path $path) {
        Get-Content -Path $path -Raw | ConvertFrom-Json
    }
}

<#
.SYNOPSIS
    Clear session temporary files

.DESCRIPTION
    Cleans up temporary session files
#>
function Clear-SessionTemporaryFiles {
    [CmdletBinding()]
    param()
    
    $tempPath = Get-SessionDirectoryPath -Type 'temp'
    if (Test-Path $tempPath) {
        Get-ChildItem -Path $tempPath -File | Remove-Item -Force -ErrorAction SilentlyContinue
    }
}

<#
.SYNOPSIS
    Get session statistics

.DESCRIPTION
    Returns statistics about session files
#>
function Get-SessionStatistics {
    [CmdletBinding()]
    param()
    
    return @{
        TotalFiles  = (Get-ChildItem -Path $env:MAINTENANCE_TEMP_ROOT -Recurse -File | Measure-Object).Count
        DataFiles   = (Get-ChildItem -Path (Get-SessionDirectoryPath -Type 'data') -File -ErrorAction SilentlyContinue | Measure-Object).Count
        LogFiles    = (Get-ChildItem -Path (Get-SessionDirectoryPath -Type 'logs') -File -ErrorAction SilentlyContinue | Measure-Object).Count
        ReportFiles = (Get-ChildItem -Path (Get-SessionDirectoryPath -Type 'reports') -File -ErrorAction SilentlyContinue | Measure-Object).Count
    }
}

#endregion Session File Organization

#region Infrastructure Status Function

<#
.SYNOPSIS
    Check infrastructure initialization status and health

.DESCRIPTION
    Validates that all core infrastructure systems are properly initialized.
    Tests path integrity, configuration loading, and session setup.
    
    This function is called during initialization to verify that CoreInfrastructure
    has successfully loaded all dependencies and is ready for use by other modules.

.OUTPUTS
    PSCustomObject with properties:
    - PathsInitialized: Boolean indicating if paths are valid
    - PathErrors: Array of path validation errors (if any)
    - ConfigsLoaded: Boolean indicating if configs loaded successfully
    - ConfigErrors: Array of config validation errors (if any)
    - SessionId: Current session GUID
    - Timestamp: Current time in ISO 8601 format

.EXAMPLE
    $status = Get-InfrastructureStatus
    if ($status.PathsInitialized -and $status.ConfigsLoaded) {
        Write-Host "Infrastructure ready"
    }
#>
function Get-InfrastructureStatus {
    [CmdletBinding()]
    param()
    
    $pathsTest = Test-MaintenancePathsIntegrity
    $configTest = Test-ConfigurationIntegrity
    
    return [PSCustomObject]@{
        PathsInitialized = $pathsTest.IsValid
        PathErrors       = $pathsTest.Errors
        ConfigsLoaded    = $configTest.IsValid
        ConfigErrors     = $configTest.Errors
        SessionId        = $env:MAINTENANCE_SESSION_ID
        Timestamp        = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    }
}

<#
.SYNOPSIS
    Initialize all maintenance infrastructure systems

.DESCRIPTION
    Consolidated initialization function that sets up all infrastructure:
    1. Global path discovery (project structure auto-detection)
    2. Configuration system (load and validate all configs)
    3. Logging system (initialize structured logging)
    4. File organization (create session directories)
    
    Called once during MaintenanceOrchestrator initialization.
    All functions become available globally after this completes.

.PARAMETER ProjectRootPath
    Optional hint for project root directory

.PARAMETER ConfigRootPath
    Optional override for configuration directory

.PARAMETER TempRootPath
    Optional override for temporary files directory

.OUTPUTS
    Boolean: $true if all systems initialized successfully, $false otherwise

.NOTES
    Called During: MaintenanceOrchestrator.ps1 startup (after module load)
    Critical For: All subsequent module operations
    Side Effects: Creates temp_files directory structure, sets environment variables

.EXAMPLE
    $initialized = Initialize-MaintenanceInfrastructure
    if (-not $initialized) { exit 1 }
#>
function Initialize-MaintenanceInfrastructure {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$ProjectRootPath,
        [Parameter(Mandatory = $false)]
        [string]$ConfigRootPath,
        [Parameter(Mandatory = $false)]
        [string]$TempRootPath
    )
    
    Write-Verbose "Initializing Maintenance Infrastructure..."
    
    try {
        Initialize-GlobalPathDiscovery -HintPath $ProjectRootPath -Force
        $paths = Get-MaintenancePaths
        $configPath = $ConfigRootPath -or $paths.ConfigRoot
        Initialize-ConfigurationSystem -ConfigRootPath $configPath
        Initialize-LoggingSystem -DefaultLogPath (Join-Path $paths.TempRoot 'logs\maintenance.log')
        $tempPath = $TempRootPath -or $paths.TempRoot
        Initialize-SessionFileOrganization -TempRootPath $tempPath
        Write-Verbose "Maintenance Infrastructure initialization complete"
        return $true
    }
    catch {
        Write-Error "Infrastructure initialization failed: $($_.Exception.Message)"
        return $false
    }
}

#region v3.0 FIX #4: Standardized Audit Results Path Function

<#
.SYNOPSIS
    Gets the standardized path for Type1 audit results

.DESCRIPTION
    FIX #4: Provides centralized, standardized path for all Type1 modules to save detection results.
    This ensures consistent file organization and prevents path inconsistencies across different modules.

.PARAMETER ModuleName
    Name of the Type1 module (e.g., 'BloatwareDetection', 'EssentialApps', 'SystemOptimization')

.OUTPUTS
    System.String - Full path to audit results JSON file

.EXAMPLE
    $auditPath = Get-AuditResultsPath -ModuleName 'BloatwareDetection'
    # Returns: C:\...\temp_files\data\bloatware-detection-results.json
#>
function Get-AuditResultsPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ModuleName
    )
    
    try {
        # Get base data directory path
        $dataDir = Get-SessionDirectoryPath -Type 'data'
        
        # Standardize module name format: convert CamelCase to kebab-case
        # Step 1: Remove 'Detection' or 'Audit' suffixes
        $cleanName = $ModuleName -replace 'Detection$|Audit$', ''
        
        # Step 2: Convert CamelCase to kebab-case using proper regex
        # Insert hyphen before each uppercase letter (except the first character)
        $normalizedName = [System.Text.RegularExpressions.Regex]::Replace($cleanName, '([A-Z])', '-$1')
        
        # Step 3: Remove leading hyphen if present, then convert to lowercase
        $normalizedName = $normalizedName.TrimStart('-').ToLower()
        
        # Build standardized path: temp_files/data/[module-name]-results.json
        $resultFileName = "$normalizedName-results.json"
        $fullPath = Join-Path $dataDir $resultFileName
        
        return $fullPath
    }
    catch {
        Write-Error "Failed to get audit results path for module '$ModuleName': $($_.Exception.Message)"
        return $null
    }
}

#endregion

#region v3.0 FIX #6: Standardized Diff Results Persistence Function

<#
.SYNOPSIS
    Saves Type2 module diff results to standardized location

.DESCRIPTION
    FIX #6: Provides centralized function for Type2 modules to persist diff lists.
    Diff lists contain only items from configuration that were actually detected on the system.
    These are saved for audit compliance and can be referenced for validation.

.PARAMETER ModuleName
    Name of the Type2 module (e.g., 'BloatwareRemoval', 'EssentialApps', 'SystemOptimization')

.PARAMETER DiffData
    Array of diff items to save (items matched from config)

.PARAMETER Component
    Component name for logging (e.g., 'BLOATWARE-REMOVAL', 'ESSENTIAL-APPS')

.OUTPUTS
    System.String - Full path where diff was saved

.EXAMPLE
    $diffPath = Save-DiffResults -ModuleName 'BloatwareRemoval' -DiffData $diffList -Component 'BLOATWARE-REMOVAL'
    # Returns: C:\...\temp_files\temp\bloatware-removal-diff.json
#>
function Save-DiffResults {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ModuleName,
        
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [array]$DiffData,
        
        [Parameter(Mandatory = $false)]
        [string]$Component = 'CORE'
    )
    
    try {
        # Get base temp directory path for diff storage
        $tempDir = Get-SessionDirectoryPath -Type 'temp'
        
        # Standardize module name format: convert to lowercase with hyphens
        $normalizedName = ($ModuleName -replace 'Type2|Module|Removal|Disable|Optimization', '' -replace '(?<=[a-z])(?=[A-Z])', '-').ToLower()
        
        # Build standardized path: temp_files/temp/[module-name]-diff.json
        $diffFileName = "$normalizedName-diff.json"
        $diffPath = Join-Path $tempDir $diffFileName
        
        # Ensure temp directory exists
        if (-not (Test-Path $tempDir)) {
            New-Item -Path $tempDir -ItemType Directory -Force | Out-Null
        }
        
        # Save diff data as JSON
        $DiffData | ConvertTo-Json -Depth 20 -WarningAction SilentlyContinue | Set-Content $diffPath -Encoding UTF8 -Force
        
        # Log the operation
        Write-ModuleLogEntry -Level 'DEBUG' -Component $Component -Message "Saved diff list for $ModuleName`: $($DiffData.Count) items to $diffPath"
        
        return $diffPath
    }
    catch {
        Write-Error "Failed to save diff results for module '$ModuleName': $($_.Exception.Message)"
        return $null
    }
}

#endregion

#region v3.0 Module Execution Result

<#
.SYNOPSIS
    Creates standardized module execution result object

.DESCRIPTION
    Constructs a consistent result structure that all Type2 modules return.
    This standardizes how the orchestrator processes module outcomes.

.PARAMETER Success
    Boolean indicating if the operation succeeded

.PARAMETER ItemsDetected
    Number of items found during detection phase

.PARAMETER ItemsProcessed
    Number of items actually processed

.PARAMETER DurationMilliseconds
    How long the operation took in milliseconds

.PARAMETER LogPath
    Path to the execution log file

.PARAMETER ModuleName
    Name of the module that produced this result

.PARAMETER ErrorMessage
    Error message if operation failed

.PARAMETER DryRun
    Whether this was a dry-run (simulation) execution

.PARAMETER AdditionalData
    Any extra data to include in result

.EXAMPLE
    $result = New-ModuleExecutionResult -Success $true -ItemsDetected 5 -ItemsProcessed 3 `
        -DurationMilliseconds 1234 -ModuleName 'BloatwareRemoval' -LogPath 'C:\...\exec.log'

.OUTPUTS
    [hashtable] Standardized result object
#>
function New-ModuleExecutionResult {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [bool]$Success,
        
        [Parameter(Mandatory = $true)]
        [int]$ItemsDetected,
        
        [Parameter(Mandatory = $true)]
        [int]$ItemsProcessed,
        
        [Parameter(Mandatory = $true)]
        [double]$DurationMilliseconds,
        
        [Parameter(Mandatory = $false)]
        [string]$LogPath,
        
        [Parameter(Mandatory = $false)]
        [string]$ModuleName,
        
        [Parameter(Mandatory = $false)]
        [string]$ErrorMessage,
        
        [Parameter(Mandatory = $false)]
        [switch]$DryRun,
        
        [Parameter(Mandatory = $false)]
        [hashtable]$AdditionalData = @{}
    )
    
    # Build standardized result object
    $result = @{
        Success            = [bool]$Success
        ItemsDetected      = [int]$ItemsDetected
        ItemsProcessed     = [int]$ItemsProcessed
        Duration           = [double]$DurationMilliseconds
        LogPath            = $LogPath
        ModuleName         = $ModuleName
        Error              = $ErrorMessage
        DryRun             = $DryRun.IsPresent
        ExecutionTimestamp = Get-Date -Format 'o'
        AdditionalData     = $AdditionalData
    }
    
    # Use Write-Output -NoEnumerate to prevent array wrapping
    Write-Output -NoEnumerate $result
}

#endregion

#region v3.0 Structured Logging

<#
.SYNOPSIS
    Writes structured log entry with multiple output formats

.DESCRIPTION
    Writes a log entry to multiple outputs:
    - Console (for user visibility)
    - Text log file (for easy review)
    - JSON log file (for programmatic analysis)
    
    Ensures consistent logging across all modules.

.PARAMETER Level
    Severity level: DEBUG, INFO, WARN, SUCCESS, ERROR

.PARAMETER Component
    Module or component that generated the log entry

.PARAMETER Message
    The actual log message

.PARAMETER LogPath
    Path to text log file (optional, writes to console if not specified)

.PARAMETER Operation
    Name of operation (Detect, Process, Execute, etc.) - optional

.PARAMETER Target
    Target item being processed (for context) - optional

.PARAMETER Result
    Result of operation (Success, Failed, Skipped, etc.) - optional

.PARAMETER Metadata
    Additional structured data as hashtable - optional

.EXAMPLE
    Write-StructuredLogEntry -Level 'INFO' -Component 'BLOATWARE-REMOVAL' `
        -Message 'Starting bloatware detection' -LogPath 'C:\...\exec.log' `
        -Operation 'Detect' -Metadata @{ ItemCount = 5 }

.NOTES
    Always writes to console.
    Writes to text log if LogPath provided.
    Creates JSON companion log for structure analysis.
#>

<#
.SYNOPSIS
    Write detection log entry (backward compatibility wrapper)

.DESCRIPTION
    Compatibility wrapper for Type1 audit modules that use Write-DetectionLog.
    Wraps Write-LogEntry with detection-specific semantics.

.PARAMETER Operation
    Operation being performed (Detect, Process, etc.)

.PARAMETER Target
    Target item being detected/processed

.PARAMETER Component
    Component performing the operation

.PARAMETER AdditionalInfo
    Additional contextual information as hashtable

.EXAMPLE
    Write-DetectionLog -Operation 'Detect' -Target 'AppName' -Component 'BLOATWARE' -AdditionalInfo @{ Version = '1.0' }
#>
function Write-DetectionLog {
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Operation,
        
        [Parameter(Mandatory = $true)]
        [string]$Target,
        
        [Parameter(Mandatory = $true)]
        [string]$Component,
        
        [Parameter(Mandatory = $false)]
        [hashtable]$AdditionalInfo = @{}
    )
    
    $message = "$Operation : $Target"
    Write-LogEntry -Level 'INFO' -Component $Component -Message $message -Data $AdditionalInfo
}

function Write-StructuredLogEntry {
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('DEBUG', 'INFO', 'WARNING', 'SUCCESS', 'ERROR')]
        [string]$Level,
        
        [Parameter(Mandatory = $true)]
        [string]$Component,
        
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [Parameter(Mandatory = $false)]
        [string]$LogPath,
        
        [Parameter(Mandatory = $false)]
        [string]$Operation,
        
        [Parameter(Mandatory = $false)]
        [string]$Target,
        
        [Parameter(Mandatory = $false)]
        [string]$Result,
        
        [Parameter(Mandatory = $false)]
        [hashtable]$Metadata = @{}
    )
    
    # Build enhanced message with operation details
    $enhancedMessage = $Message
    
    if ($Operation) {
        $enhancedMessage = "[$Operation] $enhancedMessage"
    }
    
    if ($Target) {
        $enhancedMessage += " | Target: $Target"
    }
    
    if ($Result) {
        $enhancedMessage += " | Result: $Result"
    }
    
    # Use standardized log entry format
    $logMessage = New-StandardLogEntry -Level $Level -Component $Component -Message $enhancedMessage
    
    # Write to console
    Write-Information $logMessage -InformationAction Continue
    
    # Write to text log file if path specified
    if ($LogPath) {
        try {
            # Ensure log directory exists
            $logDir = Split-Path $LogPath -Parent
            if (-not (Test-Path $logDir)) {
                New-Item -Path $logDir -ItemType Directory -Force | Out-Null
            }
            
            # Append to log file
            Add-Content -Path $LogPath -Value $logMessage -Encoding UTF8 -ErrorAction SilentlyContinue
        }
        catch {
            # Silently fail if log file writing fails
            Write-Debug "Failed to write to log file: $_"
        }
    }
    
    # Write to JSON structured log if text log specified
    if ($LogPath) {
        try {
            $jsonLogPath = $LogPath -replace '\.log$', '-structured.json'
            
            # Ensure JSON log directory exists
            $jsonLogDir = Split-Path $jsonLogPath -Parent
            if (-not (Test-Path $jsonLogDir)) {
                New-Item -Path $jsonLogDir -ItemType Directory -Force | Out-Null
            }
            
            # Create JSON entry with ISO 8601 timestamp
            $isoTimestamp = Get-Date -Format $script:LoggingStandards.TimestampFormat
            $jsonEntry = @{
                timestamp  = $isoTimestamp
                level      = $Level
                component  = $Component
                message    = $Message
                operation  = $Operation
                target     = $Target
                result     = $Result
                metadata   = $Metadata
                entry_time = Get-Date -Format 'o'  # Keep for backward compatibility
            }
            
            # Append to JSON structured log
            $jsonLine = $jsonEntry | ConvertTo-Json -Compress
            Add-Content -Path $jsonLogPath -Value $jsonLine -Encoding UTF8 -ErrorAction SilentlyContinue
        }
        catch {
            # Silently fail if JSON logging fails (optional feature)
            Write-Debug "Failed to write JSON structured log: $_"
        }
    }
}

#endregion

#region v3.0 Config Comparison

<#
.SYNOPSIS
    Compares detected system items against configuration list

.DESCRIPTION
    Used in Type2→Type1 flow to determine which detected items should actually be processed.
    Only items that are:
    1. Detected on the system (Type1 output)
    2. AND configured to be processed (config file)
    
    Are included in the diff list.

.PARAMETER DetectionResults
    Array of items detected by Type1 module

.PARAMETER ConfigData
    Configuration data from JSON config file

.PARAMETER ConfigItemsPath
    Path in config to items (e.g., 'bloatware' or 'items')

.PARAMETER MatchField
    Which field to use for matching (e.g., 'Name', 'AppId')

.EXAMPLE
    $diff = Compare-DetectedVsConfig -DetectionResults $detected -ConfigData $config `
        -ConfigItemsPath 'bloatware' -MatchField 'Name'
    # Returns: @() array with only items found in both detected and config

.OUTPUTS
    [array] Items present in both detection results and configuration
#>
function Compare-DetectedVsConfig {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true)]
        [array]$DetectionResults,
        
        [Parameter(Mandatory = $true)]
        $ConfigData,
        
        [Parameter(Mandatory = $false)]
        [string]$MatchField = 'Name'
    )
    
    $diffList = @()
    
    # Extract items from config data
    $configItems = @()
    if ($ConfigData -is [hashtable]) {
        # If config has 'all' key, use that
        if ($ConfigData.ContainsKey('all')) {
            $configItems = $ConfigData['all']
        }
        # Otherwise try to find array in config
        else {
            $configItems = $ConfigData.Values | Where-Object { $_ -is [array] } | Select-Object -First 1
        }
    }
    elseif ($ConfigData -is [array]) {
        $configItems = $ConfigData
    }
    else {
        # Config data is not usable
        return @()
    }
    
    # Ensure we have arrays
    if (-not $configItems) {
        $configItems = @()
    }
    if (-not $DetectionResults) {
        $DetectionResults = @()
    }
    
    # Compare: only include items found in BOTH lists
    foreach ($detected in $DetectionResults) {
        # Look for this item in config
        $configMatch = $configItems | Where-Object { $_.$MatchField -eq $detected.$MatchField } | Select-Object -First 1
        
        if ($configMatch) {
            # Item is in both detected and config, include in diff
            $diffList += $detected
        }
    }
    
    return @($diffList)
}

#endregion

#region System Requirements Validation

<#
.SYNOPSIS
    Tests system requirements for maintenance execution

.DESCRIPTION
    Validates that the system meets all prerequisites for safe maintenance execution:
    - PowerShell 7+ installed
    - Administrator privileges
    - Sufficient disk space (minimum 1GB free)
    - Adequate available memory (minimum 2GB)
    - System not in pending reboot state

.OUTPUTS
    [hashtable] Requirements check results with detailed status
    
.EXAMPLE
    $requirements = Test-SystemRequirements
    if (-not $requirements.AllMet) {
        Write-Host "System requirements not met:"
        $requirements.Failed | ForEach-Object { Write-Host "  - $_" }
    }
#>
function Test-SystemRequirements {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()
    
    $results = @{
        AllMet   = $true
        Checks   = @()
        Failed   = @()
        Warnings = @()
    }
    
    # Check 1: PowerShell Version
    $psCheck = @{
        Name     = 'PowerShell Version'
        Required = '7.0'
        Actual   = $PSVersionTable.PSVersion.ToString()
        Met      = $PSVersionTable.PSVersion.Major -ge 7
    }
    $results.Checks += $psCheck
    if (-not $psCheck.Met) {
        $results.AllMet = $false
        $results.Failed += "PowerShell 7+ required (found $($psCheck.Actual))"
    }
    
    # Check 2: Administrator Privileges
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    $adminCheck = @{
        Name     = 'Administrator Privileges'
        Required = 'Administrator'
        Actual   = if ($isAdmin) { 'Administrator' } else { 'User' }
        Met      = $isAdmin
    }
    $results.Checks += $adminCheck
    if (-not $adminCheck.Met) {
        $results.AllMet = $false
        $results.Failed += "Administrator privileges required"
    }
    
    # Check 3: Disk Space (minimum 1GB free on system drive)
    try {
        $systemDrive = $env:SystemDrive
        $drive = Get-PSDrive -Name $systemDrive.TrimEnd(':') -PSProvider FileSystem -ErrorAction Stop
        $freeSpaceGB = [math]::Round($drive.Free / 1GB, 2)
        $minSpaceGB = 1
        
        $diskCheck = @{
            Name     = 'Disk Space'
            Required = "$minSpaceGB GB free"
            Actual   = "$freeSpaceGB GB free"
            Met      = $freeSpaceGB -ge $minSpaceGB
        }
        $results.Checks += $diskCheck
        
        if (-not $diskCheck.Met) {
            $results.AllMet = $false
            $results.Failed += "Insufficient disk space (need $minSpaceGB GB, have $freeSpaceGB GB)"
        }
        elseif ($freeSpaceGB -lt 5) {
            $results.Warnings += "Low disk space warning: $freeSpaceGB GB free"
        }
    }
    catch {
        $results.Warnings += "Could not check disk space: $($_.Exception.Message)"
    }
    
    # Check 4: Available Memory (minimum 2GB free)
    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        $freeMemoryMB = [math]::Round($os.FreePhysicalMemory / 1KB, 0)
        $freeMemoryGB = [math]::Round($freeMemoryMB / 1024, 2)
        $minMemoryGB = 2
        
        $memoryCheck = @{
            Name     = 'Available Memory'
            Required = "$minMemoryGB GB free"
            Actual   = "$freeMemoryGB GB free"
            Met      = $freeMemoryGB -ge $minMemoryGB
        }
        $results.Checks += $memoryCheck
        
        if (-not $memoryCheck.Met) {
            $results.AllMet = $false
            $results.Failed += "Insufficient available memory (need $minMemoryGB GB, have $freeMemoryGB GB)"
        }
    }
    catch {
        $results.Warnings += "Could not check available memory: $($_.Exception.Message)"
    }
    
    # Check 5: Pending Reboot
    try {
        $rebootPending = $false
        
        # Check Component Based Servicing
        if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') {
            $rebootPending = $true
        }
        
        # Check Windows Update
        if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') {
            $rebootPending = $true
        }
        
        # Check Pending File Rename Operations
        $pendingFileRename = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name 'PendingFileRenameOperations' -ErrorAction SilentlyContinue
        if ($pendingFileRename) {
            $rebootPending = $true
        }
        
        $rebootCheck = @{
            Name     = 'System Reboot Status'
            Required = 'No pending reboot'
            Actual   = if ($rebootPending) { 'Reboot pending' } else { 'No reboot pending' }
            Met      = -not $rebootPending
        }
        $results.Checks += $rebootCheck
        
        if ($rebootPending) {
            $results.Warnings += "System has pending reboot - some operations may fail"
        }
    }
    catch {
        $results.Warnings += "Could not check reboot status: $($_.Exception.Message)"
    }
    
    # Check 6: System Protection Enabled (for restore points)
    try {
        $spEnabled = $false
        $spAutoEnabled = $false
        
        # Try WMI first (more reliable across PS versions)
        try {
            $spService = Get-CimInstance -ClassName Win32_SystemRestore -ErrorAction SilentlyContinue
            $spEnabled = $null -ne $spService
        }
        catch {
            # Fallback: Check registry for System Protection
            $regPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore'
            if (Test-Path $regPath) {
                $spReg = Get-ItemProperty $regPath -Name 'DisableSR' -ErrorAction SilentlyContinue
                # DisableSR = 0 means enabled, 1 means disabled
                $spEnabled = $null -eq $spReg -or $spReg.DisableSR -eq 0
            }
        }
        
        # If disabled, try to enable it automatically (if configured)
        if (-not $spEnabled) {
            try {
                $mainConfig = Get-MainConfiguration
                $autoEnable = $mainConfig.system.enableSystemProtectionIfDisabled ?? $true
                
                if ($autoEnable) {
                    Write-Verbose "Attempting to enable System Protection automatically..."
                    $enableResult = Enable-SystemProtection
                    if ($enableResult.Success) {
                        $spEnabled = $true
                        $spAutoEnabled = $true
                        Write-Verbose "System Protection enabled automatically"
                    }
                }
            }
            catch {
                Write-Verbose "Could not auto-enable System Protection: $($_.Exception.Message)"
            }
        }
        
        $actualStatus = if ($spEnabled) { 
            if ($spAutoEnabled) { 'Enabled (auto-enabled)' } else { 'Enabled' }
        }
        else { 'Disabled' }
        
        $spCheck = @{
            Name     = 'System Protection'
            Required = 'Enabled'
            Actual   = $actualStatus
            Met      = $spEnabled
        }
        $results.Checks += $spCheck
        
        if (-not $spEnabled) {
            $results.Warnings += "System Protection disabled - cannot create restore points"
        }
        elseif ($spAutoEnabled) {
            $results.Warnings += "System Protection was disabled but has been enabled automatically"
        }
    }
    catch {
        $results.Warnings += "Could not verify System Protection status: $($_.Exception.Message)"
    }
    
    return $results
}

<#
.SYNOPSIS
    Displays system readiness check results

.DESCRIPTION
    Performs comprehensive system requirements validation and displays results
    in a user-friendly format. Returns exit code indicating readiness.

.PARAMETER StopOnFailure
    If specified, throws an error and stops execution if requirements not met

.OUTPUTS
    [bool] True if all requirements met, False otherwise
    
.EXAMPLE
    if (-not (Test-SystemReadiness)) {
        Write-Host "System not ready for maintenance"
        exit 1
    }
    
.EXAMPLE
    Test-SystemReadiness -StopOnFailure
    # Throws error if requirements not met
#>
function Test-SystemReadiness {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [switch]$StopOnFailure
    )
    
    Write-Host "`n=== System Readiness Check ===" -ForegroundColor Cyan
    Write-Host "Validating system requirements for maintenance execution...`n"
    
    $requirements = Test-SystemRequirements
    
    # Display all checks
    foreach ($check in $requirements.Checks) {
        $status = if ($check.Met) { 
            "[OK]" 
        }
        else { 
            "[FAIL]" 
        }
        $color = if ($check.Met) { 'Green' } else { 'Red' }
        
        Write-Host "$status $($check.Name): " -ForegroundColor $color -NoNewline
        Write-Host "$($check.Actual)" -ForegroundColor Gray
    }
    
    # Display warnings
    if ($requirements.Warnings.Count -gt 0) {
        Write-Host "`nWarnings:" -ForegroundColor Yellow
        foreach ($warning in $requirements.Warnings) {
            Write-Host "  ⚠ $warning" -ForegroundColor Yellow
        }
    }
    
    # Display results
    Write-Host ""
    if ($requirements.AllMet) {
        Write-Host "✓ System ready for maintenance execution" -ForegroundColor Green
        Write-Host ""
        return $true
    }
    else {
        Write-Host "✗ System requirements not met:" -ForegroundColor Red
        foreach ($failure in $requirements.Failed) {
            Write-Host "  • $failure" -ForegroundColor Red
        }
        Write-Host ""
        
        if ($StopOnFailure) {
            throw "System requirements validation failed. Please resolve the issues above before continuing."
        }
        
        return $false
    }
}

#endregion

#region Operation Timeout Mechanism

<#
.SYNOPSIS
    Executes a PowerShell script block with a configurable timeout

.DESCRIPTION
    Runs code in an isolated runspace with a specified timeout. If execution
    exceeds the timeout, the runspace is stopped and an error is raised.
    Useful for preventing hung tasks from blocking maintenance execution.

.PARAMETER ScriptBlock
    The code block to execute

.PARAMETER TimeoutSeconds
    Maximum execution time in seconds (default: 600 = 10 minutes)

.PARAMETER ArgumentList
    Arguments to pass to the script block

.OUTPUTS
    [object] Output from the script block, or $null if timeout occurred

.EXAMPLE
    $result = Invoke-WithTimeout { Get-Process } -TimeoutSeconds 30
    
.EXAMPLE
    $result = Invoke-WithTimeout { 
        Start-Sleep -Seconds 60
        return "Done"
    } -TimeoutSeconds 10
    # This will timeout after 10 seconds
#>    
function Invoke-WithTimeout {
    [CmdletBinding()]
    [OutputType([object])]    
    param(
        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock,
        
        [Parameter(Mandatory = $false)]
        [int]$TimeoutSeconds = 600,
        
        [Parameter(Mandatory = $false)]
        [object[]]$ArgumentList = @()
    )
    
    # Create a new runspace
    $runspace = [runspacefactory]::CreateRunspace()
    $runspace.Open()
    
    # Create PowerShell instance in the runspace
    $ps = [powershell]::Create()
    $ps.Runspace = $runspace
    
    # Add the script block and arguments
    $ps.AddScript($ScriptBlock) | Out-Null
    foreach ($arg in $ArgumentList) {
        $ps.AddArgument($arg) | Out-Null
    }
    
    # Start asynchronous execution
    $handle = $ps.BeginInvoke()
    
    # Wait for completion or timeout
    $completed = $handle.AsyncWaitHandle.WaitOne([timespan]::FromSeconds($TimeoutSeconds))
    
    if ($completed) {
        # Task completed within timeout
        try {
            $result = $ps.EndInvoke($handle)
            return $result
        }
        catch {
            Write-Error "Error during script execution: $($_.Exception.Message)"
            return $null
        }
    }
    else {
        # Timeout occurred
        $ps.Stop()
        $ps.Dispose()
        $runspace.Close()
        $runspace.Dispose()
        
        throw [System.TimeoutException]"Script execution exceeded timeout of $TimeoutSeconds seconds"
    }
    
    # Cleanup
    $ps.Dispose()
    $runspace.Close()
    $runspace.Dispose()
}

<#
.SYNOPSIS
    Wraps a module function call with timeout protection

.DESCRIPTION
    Executes a Type2 module's Invoke-* function with automatic timeout handling.
    Logs timeout events and handles exceptions gracefully.

.PARAMETER ModuleName
    Name of the module to execute (e.g., 'BloatwareRemoval')

.PARAMETER Config
    Configuration hashtable to pass to the module

.PARAMETER DryRun
    Whether to execute in dry-run mode

.PARAMETER TimeoutSeconds
    Maximum execution time (uses config default if not specified)

.OUTPUTS
    [hashtable] Module execution result with timeout status

.EXAMPLE
    $result = Invoke-ModuleWithTimeout -ModuleName 'BloatwareRemoval' -Config $config -TimeoutSeconds 300
#>
function Invoke-ModuleWithTimeout {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ModuleName,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$Config,
        
        [Parameter(Mandatory = $false)]
        [switch]$DryRun,
        
        [Parameter(Mandatory = $false)]
        [int]$TimeoutSeconds = 600
    )
    
    $functionName = "Invoke-$ModuleName"
    $startTime = Get-Date
    
    # Verify function exists
    if (-not (Get-Command -Name $functionName -ErrorAction SilentlyContinue)) {
        return @{
            Success       = $false
            ModuleName    = $ModuleName
            Errors        = @("Function $functionName not found")
            ExecutionTime = 0
            TimedOut      = $false
        }
    }
    
    try {
        # Execute with timeout
        $scriptBlock = if ($DryRun) {
            { & $functionName -Config $args[0] -DryRun }
        }
        else {
            { & $functionName -Config $args[0] }
        }
        
        $result = Invoke-WithTimeout -ScriptBlock $scriptBlock -TimeoutSeconds $TimeoutSeconds -ArgumentList @($Config)
        
        # Ensure result is a hashtable
        if ($result -is [hashtable]) {
            $result.ExecutionTime = ([DateTime]::Now - $startTime).TotalSeconds
            $result.TimedOut = $false
            return $result
        }
        else {
            return @{
                Success       = $true
                ModuleName    = $ModuleName
                ExecutionTime = ([DateTime]::Now - $startTime).TotalSeconds
                TimedOut      = $false
                Output        = $result
            }
        }
    }
    catch [System.TimeoutException] {
        $executionTime = ([DateTime]::Now - $startTime).TotalSeconds
        Write-LogEntry -Level 'ERROR' -Component $ModuleName -Message "Module execution timeout after $executionTime seconds"
        
        return @{
            Success       = $false
            ModuleName    = $ModuleName
            Errors        = @("Execution timeout after $TimeoutSeconds seconds")
            ExecutionTime = $executionTime
            TimedOut      = $true
        }
    }
    catch {
        $executionTime = ([DateTime]::Now - $startTime).TotalSeconds
        Write-LogEntry -Level 'ERROR' -Component $ModuleName -Message "Module execution failed: $($_.Exception.Message)"
        
        return @{
            Success       = $false
            ModuleName    = $ModuleName
            Errors        = @($_.Exception.Message)
            ExecutionTime = $executionTime
            TimedOut      = $false
        }
    }
}

#endregion

#region Change Tracking & Rollback Mechanism

<#
.SYNOPSIS
    Tracks system changes for potential rollback

.DESCRIPTION
    Internal script variable that maintains a log of all system changes
    performed during execution. Used by Undo-AllChanges to revert changes
    if needed. Each entry contains: ChangeType, Target, Description, UndoCommand, Timestamp
#>
$script:ChangeLog = @()

<#
.SYNOPSIS
    Registers a system change for potential rollback

.DESCRIPTION
    Records a change that was made to the system. The change is added to the
    internal ChangeLog and can later be undone using Undo-AllChanges.
    Multiple undo commands can be provided for complex operations.

.PARAMETER ChangeType
    Type of change: 'FileOperation', 'RegistryOperation', 'ServiceOperation', 'AppOperation', 'ConfigOperation'

.PARAMETER Target
    What was changed (e.g., file path, registry key, app name, service name)

.PARAMETER Description
    Human-readable description of the change

.PARAMETER UndoCommands
    String array of PowerShell commands to execute to undo this change.
    Commands will be executed in order when rollback is requested.

.EXAMPLE
    Register-SystemChange -ChangeType 'FileOperation' -Target 'C:\Temp\config.json' `
        -Description 'Modified configuration file' `
        -UndoCommands @('Copy-Item -Path "C:\Temp\config.json.bak" -Destination "C:\Temp\config.json" -Force')

.EXAMPLE
    Register-SystemChange -ChangeType 'AppOperation' -Target 'Bloatware.App' `
        -Description 'Removed bloatware application' `
        -UndoCommands @('winget install --id Bloatware.App --accept-package-agreements --accept-source-agreements')

.OUTPUTS
    [void] Change is recorded in internal ChangeLog
#>
function Register-SystemChange {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('FileOperation', 'RegistryOperation', 'ServiceOperation', 'AppOperation', 'ConfigOperation')]
        [string]$ChangeType,
        
        [Parameter(Mandatory = $true)]
        [string]$Target,
        
        [Parameter(Mandatory = $true)]
        [string]$Description,
        
        [Parameter(Mandatory = $true)]
        [string[]]$UndoCommands
    )
    
    $changeEntry = @{
        ChangeType   = $ChangeType
        Target       = $Target
        Description  = $Description
        UndoCommands = $UndoCommands
        Timestamp    = [DateTime]::UtcNow.ToString('o')
        SessionId    = $env:MAINTENANCE_SESSION_ID
    }
    
    $script:ChangeLog += $changeEntry
    
    Write-LogEntry -Level 'DEBUG' -Component 'ChangeTracking' `
        -Message "Registered $ChangeType`: $Target - $Description" `
        -Data @{UndoCommandCount = $UndoCommands.Count }
}

<#
.SYNOPSIS
    Undoes all recorded system changes in reverse order

.DESCRIPTION
    Executes undo commands for all changes recorded during this session,
    in reverse chronological order (LIFO - Last In, First Out). This helps
    restore the system to a known good state if operations fail partway through.
    
    Changes are only undone for the current session (matching $env:MAINTENANCE_SESSION_ID).

.PARAMETER ConfirmPrompt
    If $true, displays confirmation dialog before rolling back each change.
    Allows user to skip specific changes if desired.

.PARAMETER StopOnError
    If $true, stops rollback if any undo command fails.
    If $false, continues rolling back remaining changes despite errors.

.OUTPUTS
    [hashtable] Results of rollback operation:
    - Success: $true if all rollbacks succeeded
    - RolledBackCount: Number of changes successfully undone
    - FailedCount: Number of changes that failed to rollback
    - Errors: Array of error messages
    - Details: Array of rollback operation details

.EXAMPLE
    $result = Undo-AllChanges
    if ($result.Success) { Write-Host "All changes rolled back successfully" }

.EXAMPLE
    $result = Undo-AllChanges -ConfirmPrompt -StopOnError
    # Prompts user before each rollback, stops on first error
#>
function Undo-AllChanges {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [switch]$ConfirmPrompt,
        [switch]$StopOnError
    )
    
    $result = @{
        Success         = $true
        RolledBackCount = 0
        FailedCount     = 0
        Errors          = @()
        Details         = @()
    }
    
    if ($script:ChangeLog.Count -eq 0) {
        Write-LogEntry -Level 'INFO' -Component 'ChangeTracking' -Message "No changes recorded for rollback"
        return $result
    }
    
    Write-LogEntry -Level 'INFO' -Component 'ChangeTracking' `
        -Message "Beginning rollback of $($script:ChangeLog.Count) changes" `
        -Data @{ReverseOrder = $true }
    
    # Process changes in reverse order (LIFO)
    $reversedLog = @($script:ChangeLog) | Where-Object { $_.SessionId -eq $env:MAINTENANCE_SESSION_ID } | Sort-Object -Descending { [DateTime]::Parse($_.Timestamp) }
    
    foreach ($change in $reversedLog) {
        $changeDescription = "$($change.ChangeType): $($change.Target) - $($change.Description)"
        
        if ($ConfirmPrompt) {
            $confirmation = Read-Host "Undo $changeDescription`? [Y/n]"
            if ($confirmation -eq 'n') {
                Write-LogEntry -Level 'INFO' -Component 'ChangeTracking' `
                    -Message "Skipped rollback for: $changeDescription"
                $result.Details += "SKIPPED: $changeDescription"
                continue
            }
        }
        
        Write-LogEntry -Level 'INFO' -Component 'ChangeTracking' `
            -Message "Rolling back: $changeDescription" `
            -Data @{UndoCommandCount = $change.UndoCommands.Count }
        
        try {
            foreach ($undoCommand in $change.UndoCommands) {
                Write-LogEntry -Level 'DEBUG' -Component 'ChangeTracking' `
                    -Message "Executing undo command" -Data @{Command = $undoCommand }
                
                # Execute undo command in current scope
                Invoke-Expression -Command $undoCommand -ErrorAction Stop
            }
            
            $result.RolledBackCount += 1
            $result.Details += "SUCCESS: $changeDescription"
            Write-LogEntry -Level 'SUCCESS' -Component 'ChangeTracking' `
                -Message "Successfully rolled back: $changeDescription"
        }
        catch {
            $errorMsg = "Failed to rollback $changeDescription`:`n$($_.Exception.Message)"
            $result.FailedCount += 1
            $result.Errors += $errorMsg
            $result.Details += "FAILED: $changeDescription - $($_.Exception.Message)"
            
            Write-LogEntry -Level 'ERROR' -Component 'ChangeTracking' `
                -Message "Failed to rollback: $changeDescription" `
                -Data @{Error = $_.Exception.Message }
            
            if ($StopOnError) {
                $result.Success = $false
                break
            }
        }
    }
    
    # Update overall success status
    if ($result.FailedCount -gt 0) {
        $result.Success = $false
    }
    
    Write-LogEntry -Level 'INFO' -Component 'ChangeTracking' `
        -Message "Rollback complete: $($result.RolledBackCount) succeeded, $($result.FailedCount) failed" `
        -Data $result
    
    return $result
}

<#
.SYNOPSIS
    Clears the recorded change log

.DESCRIPTION
    Removes all entries from the change log. Typically called after successful
    operations or after rollback completes.

.EXAMPLE
    Clear-ChangeLog
#>
function Clear-ChangeLog {
    [CmdletBinding()]
    param()
    
    $count = $script:ChangeLog.Count
    $script:ChangeLog = @()
    
    Write-LogEntry -Level 'DEBUG' -Component 'ChangeTracking' `
        -Message "Cleared change log" -Data @{ClearedEntries = $count }
}

<#
.SYNOPSIS
    Gets the current change log

.DESCRIPTION
    Returns all changes recorded for the current session for inspection or reporting.

.PARAMETER SessionOnly
    If $true, only returns changes from current session.
    If $false, returns all recorded changes.

.OUTPUTS
    [array] Array of change entries

.EXAMPLE
    $changes = Get-ChangeLog
    $changes | Format-Table ChangeType, Target, Timestamp
#>
function Get-ChangeLog {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [switch]$SessionOnly
    )
    
    if ($SessionOnly) {
        return @($script:ChangeLog | Where-Object { $_.SessionId -eq $env:MAINTENANCE_SESSION_ID })
    }
    else {
        return @($script:ChangeLog)
    }
}

#endregion

#region Module Exports

Export-ModuleMember -Function @(
    'Initialize-GlobalPathDiscovery', 'Get-MaintenancePaths', 'Get-MaintenancePath', 'Test-MaintenancePathsIntegrity',
    'Initialize-ConfigurationSystem', 'Get-ConfigFilePath', 'Get-JsonConfiguration', 'Get-MainConfiguration', 'Get-LoggingConfiguration',
    'Get-BloatwareConfiguration', 'Get-EssentialAppsConfiguration', 'Get-AppUpgradeConfiguration', 'Get-SystemOptimizationConfiguration', 'Get-SecurityConfiguration', 'Get-ReportTemplatesConfiguration',
    'Get-CachedConfiguration', 'Test-ConfigurationIntegrity', 'Test-ConfigurationSchema', 'Get-NestedProperty',
    'Initialize-LoggingSystem', 'Write-ModuleLogEntry', 'Write-OperationStart', 'Write-OperationSuccess', 'Write-OperationFailure',
    'Write-DetectionLog',
    'Assert-AdminPrivilege', 'Initialize-ModuleExecution',
    'Start-PerformanceTracking', 'Start-PerformanceTrackingSafe', 'Complete-PerformanceTracking', 'Set-LoggingVerbosity', 'Set-LoggingEnabled',
    'Initialize-SessionFileOrganization', 'Test-TempFilesStructure', 'Get-SessionFilePath', 'Save-SessionData', 'Get-SessionData', 'Get-SessionDirectoryPath',
    'Clear-SessionTemporaryFiles', 'Get-SessionStatistics',
    'Initialize-MaintenanceInfrastructure', 'Get-InfrastructureStatus',
    'Get-AuditResultsPath', 'Save-DiffResults',
    'New-ModuleExecutionResult', 'Write-StructuredLogEntry', 'Compare-DetectedVsConfig',
    'New-StandardLogEntry',
    'Test-SystemRequirements', 'Test-SystemReadiness', 'Enable-SystemProtection', 'New-SystemRestorePoint',
    'Invoke-WithTimeout', 'Invoke-ModuleWithTimeout',
    'Register-SystemChange', 'Undo-AllChanges', 'Clear-ChangeLog', 'Get-ChangeLog'
) -Alias @('Write-LogEntry')

#endregion

#region Auto-Initialization

try {
    if (-not $env:MAINTENANCE_SESSION_ID) {
        Write-Verbose "Auto-initializing maintenance infrastructure on module import"
        Initialize-MaintenanceInfrastructure -ErrorAction SilentlyContinue | Out-Null
    }
}
catch {
    Write-Verbose "Infrastructure auto-initialization deferred: $($_.Exception.Message)"
}

#endregion
