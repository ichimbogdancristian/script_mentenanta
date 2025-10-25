#Requires -Version 7.0

<#
.SYNOPSIS
    Core Paths Module - Global path discovery and management

.DESCRIPTION
    Extracted and simplified path discovery component from CoreInfrastructure.psm1.
    Provides thread-safe global path discovery and environment variable setup
    for all maintenance operations.

.NOTES
    Module Type: Core Infrastructure (Path Discovery Specialist)
    Dependencies: None
    Extracted from: CoreInfrastructure.psm1
    Version: 1.0.0
    Architecture: v3.0
#>

using namespace System.Collections.Generic
using namespace System.IO
using namespace System.Threading

#region Global Path Discovery

# Global project path discovery - makes entire project aware of its structure
$script:MaintenanceProjectPaths = @{
    ProjectRoot    = $null
    ConfigRoot     = $null
    ModulesRoot    = $null
    TempRoot       = $null
    ParentDir      = $null
    Initialized    = $false
    InitLock       = [System.Threading.ReaderWriterLockSlim]::new()
}

#endregion

#region Path Discovery Functions

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
    Hashtable with all discovered paths
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
    $script:MaintenanceProjectPaths.InitLock.AcquireWriteLock([System.TimeSpan]::FromSeconds(10))
    
    try {
        # Early return if already initialized and not forcing
        if ($script:MaintenanceProjectPaths.Initialized -and -not $Force) {
            return $true
        }
        
        Write-Verbose "Initializing global path discovery system"
        
        # Method 1: Use environment variables set by orchestrator
        if ($env:MAINTENANCE_PROJECT_ROOT) {
            $script:MaintenanceProjectPaths.ProjectRoot = $env:MAINTENANCE_PROJECT_ROOT
            Write-Verbose "  Found project root from environment: $($script:MaintenanceProjectPaths.ProjectRoot)"
        }
        # Method 2: Use hint path
        elseif ($HintPath -and (Test-Path $HintPath)) {
            $script:MaintenanceProjectPaths.ProjectRoot = $HintPath
            Write-Verbose "  Using hint path as project root: $HintPath"
        }
        # Method 3: Auto-detect from calling script
        elseif ($PSScriptRoot) {
            $testPath = $PSScriptRoot
            while ($testPath -and $testPath -ne (Split-Path $testPath -Parent)) {
                if ((Test-Path (Join-Path $testPath 'config')) -and 
                    (Test-Path (Join-Path $testPath 'modules')) -and 
                    (Test-Path (Join-Path $testPath 'MaintenanceOrchestrator.ps1'))) {
                    $script:MaintenanceProjectPaths.ProjectRoot = $testPath
                    Write-Verbose "  Auto-detected project root: $testPath"
                    break
                }
                $testPath = Split-Path $testPath -Parent
            }
        }
        
        # If still not found, use current location as fallback
        if (-not $script:MaintenanceProjectPaths.ProjectRoot) {
            $script:MaintenanceProjectPaths.ProjectRoot = Get-Location
            Write-Verbose "  Using current location as fallback: $($script:MaintenanceProjectPaths.ProjectRoot)"
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
        
        # Generate and set session ID
        $sessionId = [guid]::NewGuid().ToString()
        $env:MAINTENANCE_SESSION_ID = $sessionId
        
        $script:MaintenanceProjectPaths.Initialized = $true
        
        Write-Verbose "Path discovery completed successfully"
        Write-Verbose "  Project Root: $($script:MaintenanceProjectPaths.ProjectRoot)"
        Write-Verbose "  Config Root: $($script:MaintenanceProjectPaths.ConfigRoot)"
        Write-Verbose "  Modules Root: $($script:MaintenanceProjectPaths.ModulesRoot)"
        Write-Verbose "  Temp Root: $($script:MaintenanceProjectPaths.TempRoot)"
        
        return $true
    }
    finally {
        $script:MaintenanceProjectPaths.InitLock.ReleaseWriteLock()
    }
}

<#
.SYNOPSIS
    Gets all discovered paths

.OUTPUTS
    Hashtable with ProjectRoot, ConfigRoot, ModulesRoot, TempRoot, ParentDir
#>
function Get-MaintenancePaths {
    [CmdletBinding()]
    param()
    
    # Acquire read lock
    $script:MaintenanceProjectPaths.InitLock.AcquireReadLock([System.TimeSpan]::FromSeconds(5))
    
    try {
        if (-not $script:MaintenanceProjectPaths.Initialized) {
            throw "Path discovery not initialized - call Initialize-GlobalPathDiscovery first"
        }
        
        return @{
            ProjectRoot = $script:MaintenanceProjectPaths.ProjectRoot
            ConfigRoot = $script:MaintenanceProjectPaths.ConfigRoot
            ModulesRoot = $script:MaintenanceProjectPaths.ModulesRoot
            TempRoot = $script:MaintenanceProjectPaths.TempRoot
            ParentDir = $script:MaintenanceProjectPaths.ParentDir
            SessionId = $env:MAINTENANCE_SESSION_ID
        }
    }
    finally {
        $script:MaintenanceProjectPaths.InitLock.ReleaseReadLock()
    }
}

<#
.SYNOPSIS
    Gets specific path by key

.PARAMETER PathKey
    Path key to retrieve (ProjectRoot, ConfigRoot, ModulesRoot, TempRoot, ParentDir)

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
function Test-MaintenancePathsIntegrity {
    [CmdletBinding()]
    param()
    
    $paths = Get-MaintenancePaths
    $result = @{
        IsValid = $true
        Errors = @()
    }
    
    $pathsToCheck = @(
        @{ Key = 'ProjectRoot'; Name = 'Project Root' }
        @{ Key = 'ConfigRoot'; Name = 'Config Root' }
        @{ Key = 'ModulesRoot'; Name = 'Modules Root' }
    )
    
    foreach ($pathCheck in $pathsToCheck) {
        if (-not (Test-Path $paths[$pathCheck.Key])) {
            $result.IsValid = $false
            $result.Errors += "Missing: $($pathCheck.Name) at $($paths[$pathCheck.Key])"
        }
    }
    
    return [PSCustomObject]$result
}

#endregion

#region Module Exports

Export-ModuleMember -Function @(
    'Initialize-GlobalPathDiscovery',
    'Get-MaintenancePaths',
    'Get-MaintenancePath',
    'Test-MaintenancePathsIntegrity'
)

# Export global paths for convenience (though environment variables are preferred)
Export-ModuleMember -Variable @(
    'MaintenanceProjectPaths'
)

#endregion
