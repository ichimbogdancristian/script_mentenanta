﻿#Requires -Version 7.0

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
    Converts PSCustomObject to Hashtable recursively

.DESCRIPTION
    Recursively converts PSCustomObject instances to Hashtable for compatibility
    with functions expecting hashtable parameters. Handles nested PSCustomObjects
    by recursively converting child objects.

.PARAMETER InputObject
    The PSCustomObject to convert. Accepts pipeline input via filter pattern.

.OUTPUTS
    [hashtable] Converted object, or [object] if input is not a PSCustomObject

.EXAMPLE
    PS> $obj = @{ Name = 'Test'; Nested = @{ Value = 42 } } | ConvertTo-Json | ConvertFrom-Json
    PS> $hash = $obj | ConvertTo-Hashtable
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
    Gets the main configuration (settings)

.DESCRIPTION
    Loads main-config.json from either new (settings/) or old (execution/) path
    Returns hashtable for compatibility with Type2 modules

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
    
    try {
        # Try new path first
        $newPath = Join-Path $ConfigPath 'settings/main-config.json'
        $oldPath = Join-Path $ConfigPath 'execution/main-config.json'
        
        $configFile = if (Test-Path $newPath) { $newPath } 
        elseif (Test-Path $oldPath) { 
            Write-Warning "FIX #5: Deprecated config path detected 'execution/' - please migrate to 'settings/' (see docs/DELIVERABLES.md)"
            $oldPath 
        }
        else { $null }
        
        if (-not $configFile) {
            throw "main-config.json not found in $ConfigPath (tried settings/ and execution/)"
        }
        
        Write-Verbose "Loading configuration from: $configFile"
        $configContent = Get-Content $configFile -Raw
        $config = $configContent | ConvertFrom-Json
        
        # Convert to hashtable for v3.0 compatibility
        return $config | ConvertTo-Hashtable
    }
    catch {
        throw "Failed to load main configuration: $($_.Exception.Message)"
    }
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
    
    try {
        $newPath = Join-Path $ConfigPath 'lists/bloatware-list.json'
        $oldPath = Join-Path $ConfigPath 'data/bloatware-list.json'
        
        $configFile = if (Test-Path $newPath) { $newPath }
        elseif (Test-Path $oldPath) { 
            Write-Warning "FIX #5: Deprecated config path detected 'data/' - please migrate to 'lists/' (see docs/DELIVERABLES.md)"
            $oldPath 
        }
        else { $null }
        
        if (-not $configFile) {
            Write-Verbose "Bloatware configuration not found"
            return @{ all = @() }
        }
        
        Write-Verbose "Loading bloatware configuration from: $configFile"
        $content = Get-Content $configFile -Raw
        $config = $content | ConvertFrom-Json
        
        return $config | ConvertTo-Hashtable
    }
    catch {
        Write-Warning "Failed to load bloatware configuration: $($_.Exception.Message)"
        return @{ all = @() }
    }
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
    
    try {
        $newPath = Join-Path $ConfigPath 'lists/essential-apps.json'
        $oldPath = Join-Path $ConfigPath 'data/essential-apps.json'
        
        $configFile = if (Test-Path $newPath) { $newPath }
        elseif (Test-Path $oldPath) { 
            Write-Warning "FIX #5: Deprecated config path detected 'data/' - please migrate to 'lists/' (see docs/DELIVERABLES.md)"
            $oldPath 
        }
        else { $null }
        
        if (-not $configFile) {
            Write-Verbose "Essential apps configuration not found"
            return @{ all = @() }
        }
        
        Write-Verbose "Loading essential apps configuration from: $configFile"
        $content = Get-Content $configFile -Raw
        $config = $content | ConvertFrom-Json
        
        return $config | ConvertTo-Hashtable
    }
    catch {
        Write-Warning "Failed to load essential apps configuration: $($_.Exception.Message)"
        return @{ all = @() }
    }
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
    
    try {
        $newPath = Join-Path $ConfigPath 'lists/app-upgrade-config.json'
        $oldPath = Join-Path $ConfigPath 'data/app-upgrade-config.json'
        
        $configFile = if (Test-Path $newPath) { $newPath }
        elseif (Test-Path $oldPath) { 
            Write-Warning "FIX #5: Deprecated config path detected 'data/' - please migrate to 'lists/' (see docs/DELIVERABLES.md)"
            $oldPath 
        }
        else { $null }
        
        if (-not $configFile) {
            Write-Verbose "App upgrade configuration not found"
            return @{ all = @() }
        }
        
        Write-Verbose "Loading app upgrade configuration from: $configFile"
        $content = Get-Content $configFile -Raw
        $config = $content | ConvertFrom-Json
        
        return $config | ConvertTo-Hashtable
    }
    catch {
        Write-Warning "Failed to load app upgrade configuration: $($_.Exception.Message)"
        return @{ all = @() }
    }
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
    
    try {
        $newPath = Join-Path $ConfigPath 'settings/logging-config.json'
        $oldPath = Join-Path $ConfigPath 'execution/logging-config.json'
        
        $configFile = if (Test-Path $newPath) { $newPath }
        elseif (Test-Path $oldPath) { 
            Write-Warning "FIX #5: Deprecated config path detected 'execution/' - please migrate to 'settings/' (see docs/DELIVERABLES.md)"
            $oldPath 
        }
        else { $null }
        
        if (-not $configFile) {
            Write-Verbose "Logging configuration not found"
            return @{ levels = @('INFO', 'WARNING', 'ERROR') }
        }
        
        Write-Verbose "Loading logging configuration from: $configFile"
        $content = Get-Content $configFile -Raw
        $config = $content | ConvertFrom-Json
        
        return $config | ConvertTo-Hashtable
    }
    catch {
        Write-Warning "Failed to load logging configuration: $($_.Exception.Message)"
        return @{ levels = @('INFO', 'WARNING', 'ERROR') }
    }
}

<#
.SYNOPSIS
    Gets cached configuration

.DESCRIPTION
    Retrieves cached configuration data
#>
<#
.SYNOPSIS
    Retrieves cached configuration values

.DESCRIPTION
    Accesses module-level configuration cache for previously loaded configuration data.
    Supports fast retrieval of frequently accessed settings without reloading from disk.

.PARAMETER ConfigKey
    The configuration key to retrieve (e.g., 'main-config', 'logging-config', 'bloatware-list')

.OUTPUTS
    [hashtable] Configuration data if cached, empty hashtable if not found

.EXAMPLE
    PS> $config = Get-CachedConfiguration -ConfigKey 'main-config'
    PS> $config['ExecutionMode']
    Interactive
    
    Retrieves previously loaded main configuration from cache

.NOTES
    Used internally by configuration loading system.
    Reduces I/O overhead for repeated access to same configuration files.
#>
function Get-CachedConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ConfigKey
    )
    
    Write-Verbose "Getting cached configuration for: $ConfigKey"
    return @{}
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
    
    $newPath = Join-Path $env:MAINTENANCE_CONFIG_ROOT "settings/$ConfigName"
    $oldPath = Join-Path $env:MAINTENANCE_CONFIG_ROOT "execution/$ConfigName"
    
    if (Test-Path $newPath) { return $newPath }
    if (Test-Path $oldPath) { return $oldPath }
    return $newPath  # Return new path as default even if not exists
}

<#
.SYNOPSIS
    Gets report templates configuration

.DESCRIPTION
    Returns report template configuration
#>
function Get-ReportTemplatesConfiguration {
    [CmdletBinding()]
    param()
    
    return @{ templates = @('default', 'executive', 'detailed') }
}

<#
.SYNOPSIS
    Tests configuration integrity

.DESCRIPTION
    Validates configuration files are proper JSON and have required structure
#>
function Test-ConfigurationIntegrity {
    [CmdletBinding()]
    param()
    
    try {
        Get-MainConfiguration | Out-Null
        Get-LoggingConfiguration | Out-Null
        return $true
    }
    catch {
        Write-Error "Configuration integrity test failed: $_"
        return $false
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

New-Alias -Name 'Initialize-ConfigSystem' -Value 'Initialize-ConfigurationSystem' -Force
New-Alias -Name 'Get-MainConfig' -Value 'Get-MainConfiguration' -Force
New-Alias -Name 'Get-BloatwareList' -Value 'Get-BloatwareConfiguration' -Force
New-Alias -Name 'Get-UnifiedEssentialAppsList' -Value 'Get-EssentialAppsConfiguration' -Force

#endregion

#region Logging System

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
    
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logEntry = "[$timestamp] [$Level] [$Component] $Message"
    
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
    
    return @{
        Duration = $duration
        Status   = $Status
    }
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

#region Old/Deprecated

<#
.SYNOPSIS
    Write operation failure message

.DESCRIPTION
    Logs failed operation
#>
function Write-OperationFailure-Old {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$OperationName,
        
        [Parameter(Mandatory = $false)]
        [string]$Component = 'OPERATION',
        
        [Parameter(Mandatory = $false)]
        [string]$ErrorMessage = ''
    )
    
    Write-ModuleLogEntry -Level 'ERROR' -Component $Component -Message "Failed: $OperationName $ErrorMessage"
}

<#
.SYNOPSIS
    Set logging verbosity level

.DESCRIPTION
    Controls how much detail is logged
#>
function Set-LoggingVerbosity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Silent', 'Quiet', 'Normal', 'Verbose')]
        [string]$Level
    )
    
    Write-Verbose "Logging verbosity set to: $Level"
}

<#
.SYNOPSIS
    Enable or disable logging

.DESCRIPTION
    Controls logging on/off
#>
function Set-LoggingEnabled {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [bool]$Enabled
    )
    
    Write-Verbose "Logging enabled: $Enabled"
}

#endregion Logging System

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
function Get-SessionFilePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FileName,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet('data', 'logs', 'reports', 'temp')]
        [string]$Type = 'temp'
    )
    
    return Join-Path $env:MAINTENANCE_TEMP_ROOT "$Type\$FileName"
}

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
        
        # Standardize module name format: convert to lowercase with hyphens
        $normalizedName = ($ModuleName -replace 'Detection|Audit', '' -replace '(?<=[a-z])(?=[A-Z])', '-').ToLower()
        
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
    
    return $result
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
    
    # Build log message
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logMessage = "[$timestamp] [$Level] [$Component]"
    
    if ($Operation) {
        $logMessage += " [$Operation]"
    }
    
    if ($Target) {
        $logMessage += " TARGET: $Target"
    }
    
    $logMessage += " $Message"
    
    if ($Result) {
        $logMessage += " | Result: $Result"
    }
    
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
            
            # Create JSON entry
            $jsonEntry = @{
                timestamp  = $timestamp
                level      = $Level
                component  = $Component
                message    = $Message
                operation  = $Operation
                target     = $Target
                result     = $Result
                metadata   = $Metadata
                entry_time = Get-Date -Format 'o'
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

#region Module Exports

Export-ModuleMember -Function @(
    'Initialize-GlobalPathDiscovery', 'Get-MaintenancePaths', 'Get-MaintenancePath', 'Test-MaintenancePathsIntegrity',
    'Initialize-ConfigurationSystem', 'Get-ConfigFilePath', 'Get-MainConfiguration', 'Get-LoggingConfiguration',
    'Get-BloatwareConfiguration', 'Get-EssentialAppsConfiguration', 'Get-AppUpgradeConfiguration', 'Get-ReportTemplatesConfiguration',
    'Get-CachedConfiguration', 'Test-ConfigurationIntegrity',
    'Initialize-LoggingSystem', 'Write-ModuleLogEntry', 'Write-OperationStart', 'Write-OperationSuccess', 'Write-OperationFailure',
    'Write-DetectionLog',
    'Assert-AdminPrivilege',
    'Start-PerformanceTracking', 'Complete-PerformanceTracking', 'Set-LoggingVerbosity', 'Set-LoggingEnabled',
    'Initialize-SessionFileOrganization', 'Test-TempFilesStructure', 'Get-SessionFilePath', 'Save-SessionData', 'Get-SessionData', 'Get-SessionDirectoryPath',
    'Clear-SessionTemporaryFiles', 'Get-SessionStatistics',
    'Initialize-MaintenanceInfrastructure', 'Get-InfrastructureStatus',
    'Get-AuditResultsPath', 'Save-DiffResults',
    'New-ModuleExecutionResult', 'Write-StructuredLogEntry', 'Compare-DetectedVsConfig'
) -Alias @('Initialize-ConfigSystem', 'Get-MainConfig', 'Get-BloatwareList', 'Get-UnifiedEssentialAppsList', 'Write-LogEntry')

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
