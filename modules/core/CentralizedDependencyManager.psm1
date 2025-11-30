#Requires -Version 7.0

<#
.SYNOPSIS
    Centralized Dependency Management Module for Windows Maintenance Automation

.DESCRIPTION
    Provides centralized dependency import functionality to eliminate code duplication
    across all modules. Handles module loading, validation, error handling, and fallback
    scenarios in a consistent manner.

.NOTES
    Module Type: Core Infrastructure  
    Dependencies: None (self-sufficient)
    Author: Windows Maintenance Automation Project
    Version: 1.0.0
#>

using namespace System.Collections.Generic

#region Module Variables

# Cache for loaded dependencies to avoid redundant operations
$script:LoadedDependencies = [Dictionary[string, hashtable]]::new()

# Module root discovery for relative path resolution
$script:ModuleRootPath = Split-Path -Parent $PSScriptRoot

#endregion

#region Public Functions

<#
.SYNOPSIS
    Imports module dependencies with standardized error handling and caching

.DESCRIPTION
    Centralized dependency import function that handles module loading, validation,
    error handling, and fallback scenarios. Eliminates code duplication across modules.

.PARAMETER Dependencies
    Array of dependency hashtables with Path, Name, Required, and Description properties

.PARAMETER CallingModule
    Name of the module requesting the dependencies (for logging context)

.PARAMETER ModuleRoot
    Override the default module root path (optional)

.EXAMPLE
    $dependencies = @(
        @{ Path = 'core\ConfigManager.psm1'; Name = 'ConfigManager'; Required = $true; Description = 'Configuration management' }
    )
    Import-ModuleDependencies -Dependencies $dependencies -CallingModule 'BloatwareRemoval'

.OUTPUTS
    [hashtable] Status report containing success/failure information for each dependency
#>
function Import-ModuleDependencies {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [hashtable[]]$Dependencies,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$CallingModule,

        [Parameter()]
        [string]$ModuleRoot = $script:ModuleRootPath
    )

    # Initialize result tracking
    $importResults = @{
        Successful      = [List[hashtable]]::new()
        Failed          = [List[hashtable]]::new()
        AlreadyLoaded   = [List[hashtable]]::new()
        TotalProcessed  = 0
        CriticalFailure = $false
    }

    Write-Verbose "[$CallingModule] Starting dependency import process (Module Root: $ModuleRoot)"

    foreach ($dependency in $Dependencies) {
        $importResults.TotalProcessed++
        $dependencyPath = Join-Path $ModuleRoot $dependency.Path
        $dependencyId = "$($dependency.Name):$($dependency.Path)"

        try {
            # Check cache first to avoid redundant operations
            if ($script:LoadedDependencies.ContainsKey($dependencyId)) {
                $cachedInfo = $script:LoadedDependencies[$dependencyId]
                Write-Verbose "[$CallingModule] Using cached dependency: $($dependency.Name)"
                
                $importResults.AlreadyLoaded.Add(@{
                        Name        = $dependency.Name
                        Path        = $dependency.Path
                        CacheTime   = $cachedInfo.LoadTime
                        Description = $dependency.Description
                    })
                continue
            }

            # Validate dependency file exists
            if (-not (Test-Path $dependencyPath -PathType Leaf)) {
                $errorMsg = "Dependency file not found: $dependencyPath"
                
                if ($dependency.Required) {
                    Write-Error "[$CallingModule] ❌ $errorMsg"
                    $importResults.Failed.Add(@{
                            Name        = $dependency.Name
                            Path        = $dependency.Path
                            Error       = $errorMsg
                            ErrorType   = 'FileNotFound'
                            Required    = $true
                            Description = $dependency.Description
                        })
                    $importResults.CriticalFailure = $true
                    throw "Critical dependency file missing: $($dependency.Path)"
                }
                else {
                    Write-Warning "[$CallingModule] ⚠️ $errorMsg - continuing with fallback functionality"
                    $importResults.Failed.Add(@{
                            Name        = $dependency.Name
                            Path        = $dependency.Path
                            Error       = $errorMsg
                            ErrorType   = 'FileNotFound'
                            Required    = $false
                            Description = $dependency.Description
                        })
                    continue
                }
            }

            # Check if module is already loaded globally
            $existingModule = Get-Module -Name $dependency.Name -ErrorAction SilentlyContinue
            if ($existingModule) {
                Write-Verbose "[$CallingModule] ✓ Dependency already loaded globally: $($dependency.Name)"
                
                # Cache the already-loaded module info
                $script:LoadedDependencies[$dependencyId] = @{
                    LoadTime   = Get-Date
                    LoadedBy   = 'Global'
                    ModulePath = $existingModule.Path
                    Version    = $existingModule.Version
                }

                $importResults.AlreadyLoaded.Add(@{
                        Name        = $dependency.Name
                        Path        = $dependency.Path
                        LoadedBy    = 'Global'
                        Version     = $existingModule.Version
                        Description = $dependency.Description
                    })
                continue
            }

            # Import the module
            Write-Verbose "[$CallingModule] 🔄 Importing dependency: $($dependency.Name) from $dependencyPath"
            $importedModule = Import-Module $dependencyPath -PassThru -ErrorAction Stop
            
            # Cache successful import
            $script:LoadedDependencies[$dependencyId] = @{
                LoadTime   = Get-Date
                LoadedBy   = $CallingModule
                ModulePath = $dependencyPath
                Version    = $importedModule.Version
            }

            Write-Verbose "[$CallingModule] ✓ Successfully imported dependency: $($dependency.Name)"
            $importResults.Successful.Add(@{
                    Name        = $dependency.Name
                    Path        = $dependency.Path
                    LoadTime    = Get-Date
                    Version     = $importedModule.Version
                    Description = $dependency.Description
                })
        }
        catch {
            $errorMsg = "Failed to import dependency '$($dependency.Name)': $($_.Exception.Message)"
            
            if ($dependency.Required) {
                Write-Error "[$CallingModule] ❌ $errorMsg"
                $importResults.Failed.Add(@{
                        Name        = $dependency.Name
                        Path        = $dependency.Path
                        Error       = $_.Exception.Message
                        ErrorType   = $_.Exception.GetType().Name
                        Required    = $true
                        Description = $dependency.Description
                    })
                $importResults.CriticalFailure = $true
                throw "Critical dependency '$($dependency.Name)' could not be loaded: $($_.Exception.Message)"
            }
            else {
                Write-Warning "[$CallingModule] ⚠️ $errorMsg - continuing with fallback functionality"
                $importResults.Failed.Add(@{
                        Name        = $dependency.Name
                        Path        = $dependency.Path
                        Error       = $_.Exception.Message
                        ErrorType   = $_.Exception.GetType().Name
                        Required    = $false
                        Description = $dependency.Description
                    })
            }
        }
    }

    # Log summary
    $successCount = $importResults.Successful.Count
    $alreadyLoadedCount = $importResults.AlreadyLoaded.Count
    $failedCount = $importResults.Failed.Count
    
    Write-Verbose "[$CallingModule] Dependency import complete: $successCount new, $alreadyLoadedCount cached, $failedCount failed"
    
    return $importResults
}

<#
.SYNOPSIS
    Gets information about currently loaded dependencies

.DESCRIPTION
    Returns detailed information about all dependencies loaded through the centralized
    dependency management system, including cache information and load times.

.EXAMPLE
    Get-LoadedDependencies | Format-Table -AutoSize

.OUTPUTS
    [hashtable[]] Array of dependency information objects
#>
function Get-LoadedDependencies {
    [CmdletBinding()]
    [OutputType([hashtable[]])]
    param()

    $results = [List[hashtable]]::new()

    foreach ($key in $script:LoadedDependencies.Keys) {
        $dependency = $script:LoadedDependencies[$key]
        $parts = $key -split ':'
        
        $results.Add(@{
                Name       = $parts[0]
                Path       = $parts[1]
                LoadTime   = $dependency.LoadTime
                LoadedBy   = $dependency.LoadedBy
                ModulePath = $dependency.ModulePath
                Version    = $dependency.Version
                CacheKey   = $key
            })
    }

    return $results.ToArray()
}

<#
.SYNOPSIS
    Clears the dependency cache (primarily for testing)

.DESCRIPTION
    Clears the internal dependency cache. Primarily intended for testing scenarios
    or when you need to force re-import of all dependencies.

.PARAMETER Confirm
    Prompts for confirmation before clearing the cache

.EXAMPLE
    Clear-DependencyCache -Confirm:$false

.NOTES
    Use with caution in production scenarios
#>
function Clear-DependencyCache {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([void])]
    param()

    if ($PSCmdlet.ShouldProcess("Dependency Cache", "Clear all cached dependency information")) {
        $cacheCount = $script:LoadedDependencies.Count
        $script:LoadedDependencies.Clear()
        Write-Verbose "Cleared dependency cache ($cacheCount entries removed)"
        Write-Information "🗑️ Dependency cache cleared" -InformationAction Continue
    }
}

#endregion

#region Module Exports

Export-ModuleMember -Function @(
    'Import-ModuleDependencies',
    'Get-LoadedDependencies', 
    'Clear-DependencyCache'
)

#endregion