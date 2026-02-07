#Requires -Version 7.0

<#
.SYNOPSIS
    Module Dependency Graph - Phase A.2.1 (Intelligent Task Orchestration)

.DESCRIPTION
    Manages module execution dependencies and calculates safe execution order.
    Provides dependency validation, topological sorting, and circular dependency detection.

.NOTES
    Module Type: Core Infrastructure
    Architecture: v4.0 - Intelligent Orchestration
    Author: Windows Maintenance Automation Project
    Version: 4.0.0
#>

#region Public Functions

<#
.SYNOPSIS
    Creates a module dependency graph from configuration

.DESCRIPTION
    Builds a dependency graph structure that defines which modules depend on others.
    Used to calculate safe execution order and enable parallel execution.

.PARAMETER DependencyConfig
    Hashtable defining module dependencies. Format:
    @{
        ModuleName = @{
            DependsOn = @('Module1', 'Module2')
            CanRunInParallel = $true
        }
    }

.OUTPUTS
    PSCustomObject with dependency graph structure

.EXAMPLE
    $graph = New-ModuleDependencyGraph -DependencyConfig $config
#>
function New-ModuleDependencyGraph {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$DependencyConfig
    )

    try {
        Write-Verbose "Building module dependency graph from configuration"

        # Validate configuration structure
        foreach ($module in $DependencyConfig.Keys) {
            if (-not $DependencyConfig[$module].ContainsKey('DependsOn')) {
                throw "Module '$module' missing required 'DependsOn' property"
            }
        }

        # Build adjacency list representation
        $adjacencyList = @{}
        $allModules = [System.Collections.Generic.HashSet[string]]::new()

        foreach ($module in $DependencyConfig.Keys) {
            $null = $allModules.Add($module)
            $dependencies = $DependencyConfig[$module].DependsOn
            
            # Add dependencies to set
            foreach ($dep in $dependencies) {
                $null = $allModules.Add($dep)
            }

            $adjacencyList[$module] = @{
                DependsOn        = $dependencies
                CanRunInParallel = $DependencyConfig[$module].CanRunInParallel ?? $false
                Description      = $DependencyConfig[$module].Description ?? ""
            }
        }

        # Ensure all modules have entries (including those only referenced as dependencies)
        foreach ($module in $allModules) {
            if (-not $adjacencyList.ContainsKey($module)) {
                $adjacencyList[$module] = @{
                    DependsOn        = @()
                    CanRunInParallel = $true
                    Description      = "Auto-generated entry for dependency"
                }
            }
        }

        # Calculate in-degrees for each module (number of dependencies)
        $inDegrees = @{}
        foreach ($module in $allModules) {
            $inDegrees[$module] = $adjacencyList[$module].DependsOn.Count
        }

        $graph = [PSCustomObject]@{
            Modules       = [array]$allModules
            AdjacencyList = $adjacencyList
            InDegrees     = $inDegrees
            ModuleCount   = $allModules.Count
            CreatedAt     = Get-Date
        }

        Write-Verbose "Dependency graph created with $($graph.ModuleCount) modules"
        return $graph
    }
    catch {
        Write-Error "Failed to create dependency graph: $_"
        throw
    }
}

<#
.SYNOPSIS
    Tests dependency graph for circular dependencies

.DESCRIPTION
    Performs depth-first search to detect circular dependencies in the module graph.
    Returns $true if graph is acyclic (no circular dependencies), $false otherwise.

.PARAMETER Graph
    Dependency graph created by New-ModuleDependencyGraph

.OUTPUTS
    Boolean indicating if graph is valid (no circular dependencies)

.EXAMPLE
    $isValid = Test-DependencyCircularity -Graph $graph
#>
function Test-DependencyCircularity {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Graph
    )

    try {
        Write-Verbose "Testing dependency graph for circular dependencies"

        $visited = @{}
        $recursionStack = @{}

        # Initialize visited tracking
        foreach ($module in $Graph.Modules) {
            $visited[$module] = $false
            $recursionStack[$module] = $false
        }

        # Depth-first search to detect cycles
        # Internal helper function for cycle detection using DFS algorithm
        function Test-CycleDFS {
            param($module, $path)

            $visited[$module] = $true
            $recursionStack[$module] = $true
            $path += $module

            $dependencies = $Graph.AdjacencyList[$module].DependsOn
            foreach ($dep in $dependencies) {
                if (-not $visited[$dep]) {
                    $result = Test-CycleDFS $dep $path
                    if (-not $result.IsValid) {
                        return $result
                    }
                }
                elseif ($recursionStack[$dep]) {
                    # Found cycle
                    $cycleStart = $path.IndexOf($dep)
                    $cyclePath = $path[$cycleStart..($path.Count - 1)] + $dep
                    return @{
                        IsValid      = $false
                        CircularPath = $cyclePath
                        Message      = "Circular dependency detected: $($cyclePath -join ' -> ')"
                    }
                }
            }

            $recursionStack[$module] = $false
            return @{ IsValid = $true }
        }

        # Check each module
        foreach ($module in $Graph.Modules) {
            if (-not $visited[$module]) {
                $result = Test-CycleDFS $module @()
                if (-not $result.IsValid) {
                    Write-Warning "Circular dependency detected: $($result.CircularPath -join ' -> ')"
                    return $result
                }
            }
        }

        Write-Verbose "No circular dependencies found"
        return @{
            IsValid = $true
            Message = "Dependency graph is valid (acyclic)"
        }
    }
    catch {
        Write-Error "Failed to test for circular dependencies: $_"
        throw
    }
}

<#
.SYNOPSIS
    Calculates safe module execution order using topological sort

.DESCRIPTION
    Performs Kahn's algorithm (topological sort) to determine safe execution order.
    Modules with no dependencies execute first, followed by modules whose dependencies are met.
    Also groups modules by execution level for parallel execution.

.PARAMETER Graph
    Dependency graph created by New-ModuleDependencyGraph

.OUTPUTS
    PSCustomObject with execution order and parallelization levels

.EXAMPLE
    $order = Get-ModuleExecutionOrder -Graph $graph
    # Returns: ExecutionOrder = @('Module1', 'Module2', ...), ExecutionLevels = @(@('M1'), @('M2', 'M3'), ...)
#>
function Get-ModuleExecutionOrder {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Graph
    )

    try {
        Write-Verbose "Calculating module execution order (topological sort)"

        # Calculate in-degree (number of dependencies) for each module
        # In-degree = how many modules must execute before this one
        $inDegree = @{}
        foreach ($module in $Graph.Modules) {
            $inDegree[$module] = $Graph.AdjacencyList[$module].DependsOn.Count
        }

        # Queue modules with no dependencies (in-degree = 0)
        $queue = [System.Collections.Generic.Queue[string]]::new()
        foreach ($module in $Graph.Modules) {
            if ($inDegree[$module] -eq 0) {
                $queue.Enqueue($module)
                Write-Verbose "Module '$module' has no dependencies (can execute first)"
            }
        }

        # Process queue and build execution order + levels
        $executionOrder = [System.Collections.Generic.List[string]]::new()
        $executionLevels = [System.Collections.Generic.List[object]]::new()
        
        while ($queue.Count -gt 0) {
            # Current level: all modules ready to execute now
            $currentLevel = [System.Collections.Generic.List[string]]::new()
            $levelSize = $queue.Count

            for ($i = 0; $i -lt $levelSize; $i++) {
                $module = $queue.Dequeue()
                $executionOrder.Add($module)
                $currentLevel.Add($module)

                # Find all modules that depend on this module (reverse lookup)
                # When $module completes, their in-degree decreases
                foreach ($otherModule in $Graph.Modules) {
                    if ($Graph.AdjacencyList[$otherModule].DependsOn -contains $module) {
                        $inDegree[$otherModule]--
                        if ($inDegree[$otherModule] -eq 0) {
                            $queue.Enqueue($otherModule)
                        }
                    }
                }
            }

            $executionLevels.Add([array]$currentLevel)
            Write-Verbose "Execution Level $($executionLevels.Count): $($currentLevel -join ', ')"
        }

        # Verify all modules processed (no circular dependencies)
        if ($executionOrder.Count -ne $Graph.ModuleCount) {
            throw "Circular dependency detected - only $($executionOrder.Count) of $($Graph.ModuleCount) modules can be ordered"
        }

        $result = [PSCustomObject]@{
            ExecutionOrder  = [array]$executionOrder
            ExecutionLevels = [array]$executionLevels
            LevelCount      = $executionLevels.Count
            CalculatedAt    = Get-Date
        }

        Write-Verbose "Execution order calculated: $($executionOrder.Count) modules in $($executionLevels.Count) levels"
        return $result
    }
    catch {
        Write-Error "Failed to calculate execution order: $_"
        throw
    }
}

<#
.SYNOPSIS
    Gets dependencies for a specific module

.DESCRIPTION
    Retrieves direct dependencies and optionally transitive dependencies for a module.

.PARAMETER Graph
    Dependency graph created by New-ModuleDependencyGraph

.PARAMETER ModuleName
    Name of module to query

.PARAMETER Transitive
    Include transitive dependencies (dependencies of dependencies)

.OUTPUTS
    Array of module names that given module depends on

.EXAMPLE
    $deps = Get-ModuleDependencies -Graph $graph -ModuleName 'EssentialApps'
#>
function Get-ModuleDependencies {
    [CmdletBinding()]
    [OutputType([System.Object[]])]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Graph,

        [Parameter(Mandatory)]
        [string]$ModuleName,

        [Parameter()]
        [switch]$Transitive
    )

    try {
        if (-not $Graph.AdjacencyList.ContainsKey($ModuleName)) {
            Write-Warning "Module '$ModuleName' not found in dependency graph"
            return @()
        }

        $directDeps = $Graph.AdjacencyList[$ModuleName].DependsOn

        if (-not $Transitive) {
            return $directDeps
        }

        # Calculate transitive dependencies via DFS
        $visited = @{}
        $allDeps = [System.Collections.Generic.List[string]]::new()

        # Internal helper function for transitive dependency discovery
        function Get-TransitiveDFS {
            param($module)

            if ($visited.ContainsKey($module)) {
                return
            }

            $visited[$module] = $true
            $deps = $Graph.AdjacencyList[$module].DependsOn

            foreach ($dep in $deps) {
                $allDeps.Add($dep)
                Get-TransitiveDFS $dep
            }
        }

        Get-TransitiveDFS $ModuleName

        # Remove duplicates and return
        return ($allDeps | Select-Object -Unique)
    }
    catch {
        Write-Error "Failed to get dependencies for '$ModuleName': $_"
        throw
    }
}

<#
.SYNOPSIS
    Validates that all module dependencies exist

.DESCRIPTION
    Checks that all referenced dependencies are valid module names.
    Returns validation result with details of any missing modules.

.PARAMETER Graph
    Dependency graph created by New-ModuleDependencyGraph

.PARAMETER AvailableModules
    Array of module names that are available (optional validation)

.OUTPUTS
    Hashtable with IsValid and ValidationErrors

.EXAMPLE
    $validation = Test-DependencyGraphValidity -Graph $graph
#>
function Test-DependencyGraphValidity {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Graph,

        [Parameter()]
        [string[]]$AvailableModules
    )

    try {
        $errors = [System.Collections.Generic.List[string]]::new()

        # Check for self-dependencies
        foreach ($module in $Graph.Modules) {
            $deps = $Graph.AdjacencyList[$module].DependsOn
            if ($deps -contains $module) {
                $errors.Add("Module '$module' depends on itself (self-dependency)")
            }
        }

        # Check all dependencies exist in graph
        foreach ($module in $Graph.Modules) {
            $deps = $Graph.AdjacencyList[$module].DependsOn
            foreach ($dep in $deps) {
                if (-not $Graph.AdjacencyList.ContainsKey($dep)) {
                    $errors.Add("Module '$module' depends on unknown module '$dep'")
                }
            }
        }

        # If available modules provided, check all graph modules exist
        if ($AvailableModules) {
            foreach ($module in $Graph.Modules) {
                if ($module -notin $AvailableModules) {
                    $errors.Add("Module '$module' in graph but not available in system")
                }
            }
        }

        $isValid = $errors.Count -eq 0

        if ($isValid) {
            Write-Verbose "Dependency graph validation passed"
        }
        else {
            Write-Warning "Dependency graph validation failed with $($errors.Count) errors"
            foreach ($validationError in $errors) {
                Write-Warning "  - $validationError"
            }
        }

        return @{
            IsValid          = $isValid
            ErrorCount       = $errors.Count
            ValidationErrors = [array]$errors
            Message          = if ($isValid) { "Dependency graph is valid" } else { "$($errors.Count) validation errors found" }
        }
    }
    catch {
        Write-Error "Failed to validate dependency graph: $_"
        throw
    }
}

#endregion

#region Module Exports

Export-ModuleMember -Function @(
    'New-ModuleDependencyGraph',
    'Test-DependencyCircularity',
    'Get-ModuleExecutionOrder',
    'Get-ModuleDependencies',
    'Test-DependencyGraphValidity'
)

#endregion
