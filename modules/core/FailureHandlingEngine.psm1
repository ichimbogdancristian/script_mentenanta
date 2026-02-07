#Requires -Version 7.0

<#
.SYNOPSIS
    Failure Handling Engine - Phase A.2.3 (Intelligent Task Orchestration)

.DESCRIPTION
    Provides intelligent failure handling for module execution with dependency awareness.
    Analyzes failure impact, manages retry logic, and determines continuation strategy.

.NOTES
    Module Type: Core Infrastructure
    Architecture: v4.0 - Intelligent Orchestration
    Author: Windows Maintenance Automation Project
    Version: 4.0.0
    
    Design Pattern: Dependency-aware failure cascade analysis
    Features: Impact analysis, retry logic, skip strategies
#>

# Import CoreInfrastructure for logging
$CoreInfraPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'core\CoreInfrastructure.psm1'
if (Test-Path $CoreInfraPath) {
    Import-Module $CoreInfraPath -Force -Global -ErrorAction SilentlyContinue
}

# Import ModuleDependencyGraph for impact analysis
$DependencyGraphPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'core\ModuleDependencyGraph.psm1'
if (Test-Path $DependencyGraphPath) {
    Import-Module $DependencyGraphPath -Force -Global -ErrorAction SilentlyContinue
}

#region Public Functions

<#
.SYNOPSIS
    Analyzes the impact of a module failure on dependent modules

.DESCRIPTION
    Identifies all modules affected by a failure using dependency graph analysis.
    Returns direct dependents and transitive dependency chains.

.PARAMETER Graph
    Module dependency graph from ModuleDependencyGraph

.PARAMETER FailedModule
    Name of the module that failed

.OUTPUTS
    PSCustomObject with failure impact analysis

.EXAMPLE
    $impact = Get-FailureImpact -Graph $graph -FailedModule 'BloatwareRemoval'
    # Returns: DirectDependents, TransitiveDependents, TotalImpactedModules
#>
function Get-FailureImpact {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [PSCustomObject]$Graph,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$FailedModule
    )

    try {
        Write-LogEntry -Level 'DEBUG' -Component 'FAILURE-HANDLER' -Message "Analyzing failure impact for module: $FailedModule"

        # Find all modules that directly depend on the failed module
        $directDependents = [System.Collections.Generic.List[string]]::new()
        
        foreach ($module in $Graph.Modules) {
            $dependencies = $Graph.AdjacencyList[$module].DependsOn
            if ($dependencies -contains $FailedModule) {
                $directDependents.Add($module)
            }
        }

        # Find transitive dependents (modules that depend on direct dependents)
        $transitiveDependents = [System.Collections.Generic.HashSet[string]]::new()
        $visited = [System.Collections.Generic.HashSet[string]]::new()
        
        function Find-TransitiveDependents {
            param([string]$ModuleName)
            
            if ($visited.Contains($ModuleName)) {
                return
            }
            
            $null = $visited.Add($ModuleName)
            
            foreach ($module in $Graph.Modules) {
                $deps = $Graph.AdjacencyList[$module].DependsOn
                if ($deps -contains $ModuleName) {
                    $null = $transitiveDependents.Add($module)
                    Find-TransitiveDependents -ModuleName $module
                }
            }
        }
        
        foreach ($dependent in $directDependents) {
            Find-TransitiveDependents -ModuleName $dependent
        }

        # Remove direct dependents from transitive set (avoid duplication)
        foreach ($direct in $directDependents) {
            $transitiveDependents.Remove($direct) | Out-Null
        }

        $result = [PSCustomObject]@{
            FailedModule         = $FailedModule
            DirectDependents     = [array]$directDependents
            TransitiveDependents = [array]$transitiveDependents
            TotalImpactedModules = $directDependents.Count + $transitiveDependents.Count
            ImpactLevel          = if ($directDependents.Count + $transitiveDependents.Count -eq 0) { 'None' }
            elseif ($directDependents.Count + $transitiveDependents.Count -le 2) { 'Low' }
            elseif ($directDependents.Count + $transitiveDependents.Count -le 4) { 'Medium' }
            else { 'High' }
            AnalyzedAt           = Get-Date
        }

        Write-LogEntry -Level 'INFO' -Component 'FAILURE-HANDLER' -Message "Failure impact: $($result.TotalImpactedModules) modules affected (Level: $($result.ImpactLevel))"
        
        if ($directDependents.Count -gt 0) {
            Write-LogEntry -Level 'WARNING' -Component 'FAILURE-HANDLER' -Message "Direct dependents: $($directDependents -join ', ')"
        }
        
        if ($transitiveDependents.Count -gt 0) {
            Write-LogEntry -Level 'WARNING' -Component 'FAILURE-HANDLER' -Message "Transitive dependents: $($transitiveDependents -join ', ')"
        }

        return $result
    }
    catch {
        Write-LogEntry -Level 'ERROR' -Component 'FAILURE-HANDLER' -Message "Error analyzing failure impact: $_"
        throw
    }
}

<#
.SYNOPSIS
    Determines execution strategy after module failure

.DESCRIPTION
    Decides whether to continue, retry, or abort based on failure impact and policy.
    Supports configurable retry attempts and skip strategies.

.PARAMETER FailureImpact
    Impact analysis from Get-FailureImpact

.PARAMETER FailurePolicy
    Policy configuration for handling failures

.PARAMETER CurrentAttempt
    Current retry attempt number (default: 1)

.OUTPUTS
    PSCustomObject with strategy decision

.EXAMPLE
    $strategy = Get-FailureStrategy -FailureImpact $impact -FailurePolicy $policy
#>
function Get-FailureStrategy {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [PSCustomObject]$FailureImpact,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [hashtable]$FailurePolicy,

        [Parameter()]
        [int]$CurrentAttempt = 1
    )

    try {
        Write-LogEntry -Level 'DEBUG' -Component 'FAILURE-HANDLER' -Message "Determining failure strategy (attempt $CurrentAttempt)"

        $maxRetries = $FailurePolicy.MaxRetries ?? 0
        $abortOnCriticalFailure = $FailurePolicy.AbortOnCriticalFailure ?? $true
        $criticalModules = $FailurePolicy.CriticalModules ?? @()
        $continueOnNonCriticalFailure = $FailurePolicy.ContinueOnNonCriticalFailure ?? $true

        # Check if module is critical
        $isCritical = $criticalModules -contains $FailureImpact.FailedModule

        # Determine strategy
        $strategy = 'Continue'  # Default
        $reason = ''

        # Retry logic
        if ($CurrentAttempt -le $maxRetries) {
            $strategy = 'Retry'
            $reason = "Retry attempt $CurrentAttempt of $maxRetries"
        }
        # Critical module failure with abort policy
        elseif ($isCritical -and $abortOnCriticalFailure) {
            $strategy = 'Abort'
            $reason = "Critical module '$($FailureImpact.FailedModule)' failed - aborting execution"
        }
        # High impact failure (5+ modules affected)
        elseif ($FailureImpact.ImpactLevel -eq 'High' -and $abortOnCriticalFailure) {
            $strategy = 'Abort'
            $reason = "High-impact failure affecting $($FailureImpact.TotalImpactedModules) modules"
        }
        # Continue with skip
        elseif ($continueOnNonCriticalFailure) {
            $strategy = 'SkipDependents'
            $reason = "Non-critical failure - skipping $($FailureImpact.TotalImpactedModules) dependent modules"
        }
        else {
            $strategy = 'Abort'
            $reason = "Failure policy requires abort on any failure"
        }

        $result = [PSCustomObject]@{
            Strategy         = $strategy
            Reason           = $reason
            IsCriticalModule = $isCritical
            SkipModules      = if ($strategy -eq 'SkipDependents') {
                $FailureImpact.DirectDependents + $FailureImpact.TransitiveDependents
            }
            else { @() }
            RetryModule      = if ($strategy -eq 'Retry') { $FailureImpact.FailedModule } else { $null }
            AbortExecution   = ($strategy -eq 'Abort')
            NextAttempt      = if ($strategy -eq 'Retry') { $CurrentAttempt + 1 } else { 0 }
            DecidedAt        = Get-Date
        }

        Write-LogEntry -Level 'INFO' -Component 'FAILURE-HANDLER' -Message "Strategy: $($result.Strategy) - $($result.Reason)"

        return $result
    }
    catch {
        Write-LogEntry -Level 'ERROR' -Component 'FAILURE-HANDLER' -Message "Error determining failure strategy: $_"
        throw
    }
}

<#
.SYNOPSIS
    Processes module failure with dependency-aware handling

.DESCRIPTION
    Complete failure handling workflow: analyze impact, determine strategy, execute action.
    Returns updated execution plan with failures, skips, and retries.

.PARAMETER Graph
    Module dependency graph

.PARAMETER FailedModule
    Name of the failed module

.PARAMETER FailurePolicy
    Failure handling policy configuration

.PARAMETER ExecutionState
    Current execution state tracking

.OUTPUTS
    PSCustomObject with updated execution state

.EXAMPLE
    $newState = Invoke-FailureHandling -Graph $graph -FailedModule 'EssentialApps' -FailurePolicy $policy -ExecutionState $state
#>
function Invoke-FailureHandling {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [PSCustomObject]$Graph,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$FailedModule,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [hashtable]$FailurePolicy,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [hashtable]$ExecutionState
    )

    try {
        Write-LogEntry -Level 'ERROR' -Component 'FAILURE-HANDLER' -Message "Processing failure for module: $FailedModule"

        # Step 1: Analyze impact
        $impact = Get-FailureImpact -Graph $Graph -FailedModule $FailedModule

        # Step 2: Get current retry attempt
        $currentAttempt = if ($ExecutionState.RetryAttempts.ContainsKey($FailedModule)) {
            $ExecutionState.RetryAttempts[$FailedModule]
        }
        else {
            1
        }

        # Step 3: Determine strategy
        $strategy = Get-FailureStrategy -FailureImpact $impact -FailurePolicy $FailurePolicy -CurrentAttempt $currentAttempt

        # Step 4: Update execution state
        $newState = @{
            FailedModules       = $ExecutionState.FailedModules + @($FailedModule)
            SkippedModules      = $ExecutionState.SkippedModules + $strategy.SkipModules
            RetryAttempts       = $ExecutionState.RetryAttempts.Clone()
            ShouldAbort         = $strategy.AbortExecution
            LastFailureImpact   = $impact
            LastFailureStrategy = $strategy
        }

        # Update retry counter
        if ($strategy.Strategy -eq 'Retry') {
            $newState.RetryAttempts[$FailedModule] = $strategy.NextAttempt
        }

        # Log impact
        if ($impact.DirectDependents.Count -gt 0) {
            Write-LogEntry -Level 'WARNING' -Component 'FAILURE-HANDLER' -Message "Module '$FailedModule' failure impacts: $($impact.DirectDependents -join ', ')"
        }

        # Log strategy decision
        if ($strategy.Strategy -eq 'SkipDependents' -and $strategy.SkipModules.Count -gt 0) {
            Write-LogEntry -Level 'WARNING' -Component 'FAILURE-HANDLER' -Message "Skipping dependent modules: $($strategy.SkipModules -join ', ')"
        }
        elseif ($strategy.Strategy -eq 'Abort') {
            Write-LogEntry -Level 'ERROR' -Component 'FAILURE-HANDLER' -Message "Aborting execution: $($strategy.Reason)"
        }
        elseif ($strategy.Strategy -eq 'Retry') {
            Write-LogEntry -Level 'INFO' -Component 'FAILURE-HANDLER' -Message "Will retry module '$FailedModule' (attempt $($strategy.NextAttempt))"
        }

        return $newState
    }
    catch {
        Write-LogEntry -Level 'ERROR' -Component 'FAILURE-HANDLER' -Message "Error processing failure: $_"
        throw
    }
}

<#
.SYNOPSIS
    Creates default failure handling policy

.DESCRIPTION
    Returns default failure policy configuration with sensible defaults.
    Can be customized per execution requirements.

.OUTPUTS
    Hashtable with default failure policy

.EXAMPLE
    $policy = New-FailureHandlingPolicy
    $policy.MaxRetries = 2
    $policy.CriticalModules = @('BloatwareRemoval', 'SecurityEnhancement')
#>
function New-FailureHandlingPolicy {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter()]
        [int]$MaxRetries = 1,

        [Parameter()]
        [bool]$AbortOnCriticalFailure = $true,

        [Parameter()]
        [bool]$ContinueOnNonCriticalFailure = $true,

        [Parameter()]
        [string[]]$CriticalModules = @()
    )

    return @{
        MaxRetries                   = $MaxRetries
        AbortOnCriticalFailure       = $AbortOnCriticalFailure
        ContinueOnNonCriticalFailure = $ContinueOnNonCriticalFailure
        CriticalModules              = $CriticalModules
        RetryDelaySeconds            = 5
        LogFailureDetails            = $true
    }
}

<#
.SYNOPSIS
    Initializes execution state for failure tracking

.DESCRIPTION
    Creates initial execution state structure for tracking failures, skips, and retries.

.OUTPUTS
    Hashtable with initial execution state

.EXAMPLE
    $state = Initialize-ExecutionState
#>
function Initialize-ExecutionState {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    return @{
        FailedModules       = @()
        SkippedModules      = @()
        RetryAttempts       = @{}
        ShouldAbort         = $false
        LastFailureImpact   = $null
        LastFailureStrategy = $null
    }
}

<#
.SYNOPSIS
    Generates failure handling report

.DESCRIPTION
    Creates detailed report of failures, impacts, and recovery actions taken.

.PARAMETER ExecutionState
    Final execution state after all operations

.OUTPUTS
    PSCustomObject with failure report

.EXAMPLE
    $report = Get-FailureReport -ExecutionState $finalState
#>
function Get-FailureReport {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [hashtable]$ExecutionState
    )

    try {
        $totalRetries = 0
        foreach ($attempts in $ExecutionState.RetryAttempts.Values) {
            $totalRetries += ($attempts - 1)  # Subtract 1 because first attempt is not a retry
        }

        $report = [PSCustomObject]@{
            TotalFailures    = $ExecutionState.FailedModules.Count
            FailedModules    = $ExecutionState.FailedModules
            TotalSkipped     = $ExecutionState.SkippedModules.Count
            SkippedModules   = $ExecutionState.SkippedModules
            TotalRetries     = $totalRetries
            RetriedModules   = $ExecutionState.RetryAttempts.Keys
            ExecutionAborted = $ExecutionState.ShouldAbort
            LastImpactLevel  = $ExecutionState.LastFailureImpact.ImpactLevel ?? 'None'
            GeneratedAt      = Get-Date
        }

        Write-LogEntry -Level 'INFO' -Component 'FAILURE-HANDLER' -Message "Failure report: $($report.TotalFailures) failed, $($report.TotalSkipped) skipped, $($report.TotalRetries) retries"

        return $report
    }
    catch {
        Write-LogEntry -Level 'ERROR' -Component 'FAILURE-HANDLER' -Message "Error generating failure report: $_"
        throw
    }
}

#endregion

#region Export
Export-ModuleMember -Function @(
    'Get-FailureImpact',
    'Get-FailureStrategy',
    'Invoke-FailureHandling',
    'New-FailureHandlingPolicy',
    'Initialize-ExecutionState',
    'Get-FailureReport'
)
#endregion
