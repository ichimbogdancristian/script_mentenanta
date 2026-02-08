#Requires -Version 7.0

<#
.SYNOPSIS
    Parallel Execution Engine - Phase A.2.2 (Intelligent Task Orchestration)

.DESCRIPTION
    Provides parallel execution capabilities for maintenance modules using PowerShell runspaces.
    Supports concurrent module execution with resource management and result aggregation.

.NOTES
    Module Type: Core Infrastructure
    Architecture: v4.0 - Intelligent Orchestration
    Author: Windows Maintenance Automation Project
    Version: 4.0.0

    Design Pattern: Runspace pool for efficient parallelism
    Performance: ~3-4x faster than sequential execution for independent modules
#>

# Import CoreInfrastructure for logging and paths
$CoreInfraPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'core\CoreInfrastructure.psm1'
if (Test-Path $CoreInfraPath) {
    Import-Module $CoreInfraPath -Force -Global -ErrorAction SilentlyContinue
}

#region Public Functions

<#
.SYNOPSIS
    Executes multiple modules in parallel using runspace pool

.DESCRIPTION
    Creates a runspace pool and executes modules concurrently with resource management.
    Supports configurable concurrency limits and comprehensive result collection.

.PARAMETER Modules
    Array of module names to execute in parallel

.PARAMETER MaxConcurrentModules
    Maximum number of modules to run simultaneously (default: 3)

.PARAMETER DryRun
    If true, simulates execution without making system changes

.PARAMETER SessionId
    Current maintenance session ID for correlation

.PARAMETER SharedContext
    Hashtable of shared data available to all modules (paths, config, etc.)

.OUTPUTS
    PSCustomObject with parallel execution results

.EXAMPLE
    $result = Invoke-ModulesInParallel -Modules @('TelemetryDisable', 'SecurityEnhancement') -MaxConcurrentModules 2

.NOTES
    Uses runspaces for true parallelism (not background jobs)
    Each module executes in isolated runspace with shared initial state
#>
function Invoke-ModulesInParallel {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Modules,

        [Parameter()]
        [ValidateRange(1, 10)]
        [int]$MaxConcurrentModules = 3,

        [Parameter()]
        [switch]$DryRun,

        [Parameter()]
        [string]$SessionId = [guid]::NewGuid().ToString(),

        [Parameter()]
        [hashtable]$SharedContext = @{}
    )

    try {
        $startTime = Get-Date
        Write-LogEntry -Level 'INFO' -Component 'PARALLEL-ENGINE' -Message "Starting parallel execution: $($Modules.Count) modules, max concurrency: $MaxConcurrentModules"

        # Validate module availability
        $availableModules = Get-AvailableType2Modules
        $missingModules = $Modules | Where-Object { $_ -notin $availableModules.Keys }
        if ($missingModules.Count -gt 0) {
            Write-LogEntry -Level 'WARNING' -Component 'PARALLEL-ENGINE' -Message "Missing modules: $($missingModules -join ', ')"
        }

        # Create runspace pool
        $runspacePool = [runspacefactory]::CreateRunspacePool(1, $MaxConcurrentModules)
        $runspacePool.Open()
        Write-LogEntry -Level 'DEBUG' -Component 'PARALLEL-ENGINE' -Message "Runspace pool created (min: 1, max: $MaxConcurrentModules)"

        # Prepare module execution jobs
        $jobs = [System.Collections.Generic.List[PSCustomObject]]::new()

        foreach ($moduleName in $Modules) {
            if ($moduleName -notin $availableModules.Keys) {
                Write-LogEntry -Level 'WARNING' -Component 'PARALLEL-ENGINE' -Message "Skipping unavailable module: $moduleName"
                continue
            }

            # Create PowerShell instance
            $ps = [powershell]::Create()
            $ps.RunspacePool = $runspacePool

            # Build script block for module execution
            $scriptBlock = {
                param($ModuleName, $DryRunFlag, $SessionId, $SharedContext)

                try {
                    $moduleStartTime = Get-Date

                    # Import CoreInfrastructure in runspace (suppress output)
                    $coreInfraPath = Join-Path $SharedContext.ProjectRoot 'modules\core\CoreInfrastructure.psm1'
                    if (Test-Path $coreInfraPath) {
                        $null = Import-Module $coreInfraPath -Force -Global -ErrorAction Stop
                    }

                    # Initialize paths in runspace (suppress output)
                    $null = Initialize-GlobalPathDiscovery

                    # Import target module (suppress output)
                    $modulePath = Join-Path $SharedContext.ProjectRoot "modules\type2\$ModuleName.psm1"
                    if (-not (Test-Path $modulePath)) {
                        throw "Module file not found: $modulePath"
                    }

                    $null = Import-Module $modulePath -Force -ErrorAction Stop

                    # Execute module
                    $invokeFunctionName = "Invoke-$ModuleName"
                    if (-not (Get-Command $invokeFunctionName -ErrorAction SilentlyContinue)) {
                        throw "Module function '$invokeFunctionName' not found"
                    }

                    Write-LogEntry -Level 'INFO' -Component "PARALLEL-$ModuleName" -Message "Starting module execution" | Out-Null

                    # Invoke module with DryRun parameter
                    $moduleResult = if ($DryRunFlag) {
                        & $invokeFunctionName -DryRun
                    }
                    else {
                        & $invokeFunctionName
                    }

                    $duration = ((Get-Date) - $moduleStartTime).TotalSeconds

                    Write-LogEntry -Level 'SUCCESS' -Component "PARALLEL-$ModuleName" -Message "Module completed (${duration}s)" | Out-Null

                    # Return standardized result as PSCustomObject for better serialization
                    return [PSCustomObject]@{
                        ModuleName = $ModuleName
                        Status = 'Success'
                        Result = $moduleResult
                        DurationSeconds = [math]::Round($duration, 2)
                        StartTime = $moduleStartTime
                        EndTime = Get-Date
                        SessionId = $SessionId
                        Error = $null
                    }
                }
                catch {
                    $duration = ((Get-Date) - $moduleStartTime).TotalSeconds
                    Write-LogEntry -Level 'ERROR' -Component "PARALLEL-$ModuleName" -Message "Module failed: $_" | Out-Null

                    return [PSCustomObject]@{
                        ModuleName = $ModuleName
                        Status = 'Failed'
                        Result = $null
                        DurationSeconds = [math]::Round($duration, 2)
                        StartTime = $moduleStartTime
                        EndTime = Get-Date
                        SessionId = $SessionId
                        Error = $_.Exception.Message
                    }
                }
            }

            # Add script and parameters
            $null = $ps.AddScript($scriptBlock)
            $null = $ps.AddArgument($moduleName)
            $null = $ps.AddArgument($DryRun.IsPresent)
            $null = $ps.AddArgument($SessionId)
            $null = $ps.AddArgument($SharedContext)

            # Start async execution
            $handle = $ps.BeginInvoke()

            # Track job
            $jobs.Add([PSCustomObject]@{
                    ModuleName = $moduleName
                    PowerShell = $ps
                    Handle = $handle
                    StartTime = Get-Date
                    Processed = $false
                })

            Write-LogEntry -Level 'DEBUG' -Component 'PARALLEL-ENGINE' -Message "Started job for module: $moduleName"
        }

        # Wait for all jobs to complete and collect results
        $results = if ($jobs.Count -gt 0) {
            Wait-ParallelModuleCompletion -Jobs $jobs -TimeoutSeconds 1800
        }
        else {
            @()
        }

        # Close runspace pool
        $runspacePool.Close()
        $runspacePool.Dispose()

        $totalDuration = ((Get-Date) - $startTime).TotalSeconds

        # Ensure results is array
        $resultsArray = @($results)
        $successCount = @($resultsArray | Where-Object { $_.Status -eq 'Success' }).Count
        $failedCount = @($resultsArray | Where-Object { $_.Status -eq 'Failed' }).Count

        Write-LogEntry -Level 'INFO' -Component 'PARALLEL-ENGINE' -Message "Parallel execution completed: $successCount succeeded, $failedCount failed (${totalDuration}s total)"

        return [PSCustomObject]@{
            ExecutionMode = 'Parallel'
            TotalModules = $Modules.Count
            SuccessCount = $successCount
            FailedCount = $failedCount
            Results = $resultsArray
            TotalDurationSeconds = [math]::Round($totalDuration, 2)
            MaxConcurrency = $MaxConcurrentModules
            SessionId = $SessionId
        }
    }
    catch {
        Write-LogEntry -Level 'ERROR' -Component 'PARALLEL-ENGINE' -Message "Parallel execution failed: $_"
        throw
    }
    finally {
        # Cleanup
        if ($runspacePool) {
            try {
                $runspacePool.Dispose()
            }
            catch {
                Write-Verbose "Runspace pool disposal error (non-critical): $($_.Exception.Message)"
            }
        }
    }
}

<#
.SYNOPSIS
    Waits for parallel module executions to complete and collects results

.DESCRIPTION
    Monitors running jobs, enforces timeout, and aggregates execution results.
    Handles both successful completions and timeouts gracefully.

.PARAMETER Jobs
    Array of job objects created by Invoke-ModulesInParallel

.PARAMETER TimeoutSeconds
    Maximum time to wait for all jobs (default: 1800 = 30 minutes)

.OUTPUTS
    Array of module execution results

.EXAMPLE
    $results = Wait-ParallelModuleCompletion -Jobs $jobs -TimeoutSeconds 900
#>
function Wait-ParallelModuleCompletion {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [array]$Jobs,

        [Parameter()]
        [int]$TimeoutSeconds = 1800
    )

    try {
        Write-LogEntry -Level 'DEBUG' -Component 'PARALLEL-ENGINE' -Message "Waiting for $($Jobs.Count) jobs to complete (timeout: ${TimeoutSeconds}s)"

        $results = [System.Collections.Generic.List[object]]::new()
        $maxWaitTime = Get-Date
        $maxWaitTime = $maxWaitTime.AddSeconds($TimeoutSeconds)

        $completedJobs = 0
        $totalJobs = $Jobs.Count

        while ($completedJobs -lt $totalJobs -and (Get-Date) -lt $maxWaitTime) {
            foreach ($job in $Jobs) {
                if ($job.Handle.IsCompleted -and -not $job.Processed) {
                    try {
                        # Retrieve result - EndInvoke returns collection
                        $resultCollection = $job.PowerShell.EndInvoke($job.Handle)

                        # Get first non-null result from collection
                        $result = $null
                        foreach ($item in $resultCollection) {
                            if ($null -ne $item) {
                                $result = $item
                                break
                            }
                        }

                        if ($result) {
                            $results.Add($result)
                            $duration = ((Get-Date) - $job.StartTime).TotalSeconds
                            $statusText = if ($result.Status) { $result.Status } else { 'Unknown' }
                            Write-LogEntry -Level 'INFO' -Component 'PARALLEL-ENGINE' -Message "Module '$($job.ModuleName)' completed (${duration}s) - Status: $statusText"
                        }
                        else {
                            # No result returned (unexpected)
                            $results.Add([PSCustomObject]@{
                                    ModuleName = $job.ModuleName
                                    Status = 'Failed'
                                    Error = 'No result returned from module execution'
                                    DurationSeconds = ((Get-Date) - $job.StartTime).TotalSeconds
                                })
                            Write-LogEntry -Level 'WARNING' -Component 'PARALLEL-ENGINE' -Message "Module '$($job.ModuleName)' returned no result"
                        }
                    }
                    catch {
                        # Execution error
                        $results.Add([PSCustomObject]@{
                                ModuleName = $job.ModuleName
                                Status = 'Failed'
                                Error = $_.Exception.Message
                                DurationSeconds = ((Get-Date) - $job.StartTime).TotalSeconds
                            })
                        Write-LogEntry -Level 'ERROR' -Component 'PARALLEL-ENGINE' -Message "Error retrieving result for '$($job.ModuleName)': $_"
                    }
                    finally {
                        # Cleanup PowerShell instance
                        try {
                            $job.PowerShell.Dispose()
                        }
                        catch {
                            Write-LogEntry -Level 'DEBUG' -Component 'PARALLEL-ENGINE' -Message "Error disposing PowerShell instance: $_"
                        }
                        $job.Processed = $true
                        $completedJobs++
                    }
                }
            }

            # Brief sleep to avoid tight loop
            if ($completedJobs -lt $totalJobs) {
                Start-Sleep -Milliseconds 100
            }
        }

        # Handle timeouts
        if ($completedJobs -lt $totalJobs) {
            Write-LogEntry -Level 'WARNING' -Component 'PARALLEL-ENGINE' -Message "Timeout reached - $($totalJobs - $completedJobs) jobs did not complete"

            foreach ($job in $Jobs | Where-Object { -not $_.Processed }) {
                $results.Add([PSCustomObject]@{
                        ModuleName = $job.ModuleName
                        Status = 'Timeout'
                        Error = "Execution exceeded ${TimeoutSeconds}s timeout"
                        DurationSeconds = ((Get-Date) - $job.StartTime).TotalSeconds
                    })
                Write-LogEntry -Level 'ERROR' -Component 'PARALLEL-ENGINE' -Message "Module '$($job.ModuleName)' timed out"

                # Cleanup
                try {
                    $job.PowerShell.Stop()
                    $job.PowerShell.Dispose()
                }
                catch {
                    Write-Verbose "PowerShell job disposal error (non-critical): $($_.Exception.Message)"
                }
            }
        }

        Write-LogEntry -Level 'DEBUG' -Component 'PARALLEL-ENGINE' -Message "All jobs processed: $($results.Count) results collected"
        return $results
    }
    catch {
        Write-LogEntry -Level 'ERROR' -Component 'PARALLEL-ENGINE' -Message "Error waiting for parallel jobs: $_"
        throw
    }
}

<#
.SYNOPSIS
    Merges results from parallel module executions

.DESCRIPTION
    Combines individual module results into unified execution summary.
    Calculates aggregate statistics and identifies failures.

.PARAMETER ParallelResults
    Results object returned by Invoke-ModulesInParallel

.OUTPUTS
    PSCustomObject with merged result summary

.EXAMPLE
    $summary = Merge-ParallelResults -ParallelResults $results
#>
function Merge-ParallelResults {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [PSCustomObject]$ParallelResults
    )

    try {
        Write-LogEntry -Level 'DEBUG' -Component 'PARALLEL-ENGINE' -Message "Merging parallel execution results"

        $successfulModules = $ParallelResults.Results | Where-Object { $_.Status -eq 'Success' }
        $failedModules = $ParallelResults.Results | Where-Object { $_.Status -ne 'Success' }

        # Calculate statistics
        $totalOperations = 0
        $successfulOperations = 0
        $failedOperations = 0

        foreach ($result in $successfulModules) {
            if ($result.Result) {
                $totalOperations += ($result.Result.TotalOperations ?? 0)
                $successfulOperations += ($result.Result.SuccessfulOperations ?? 0)
                $failedOperations += ($result.Result.FailedOperations ?? 0)
            }
        }

        # Build summary
        $summary = [PSCustomObject]@{
            ExecutionMode = 'Parallel'
            TotalModules = $ParallelResults.TotalModules
            SuccessfulModules = $successfulModules.Count
            FailedModules = $failedModules.Count
            TotalOperations = $totalOperations
            SuccessfulOperations = $successfulOperations
            FailedOperations = $failedOperations
            TotalDurationSeconds = $ParallelResults.TotalDurationSeconds
            MaxConcurrency = $ParallelResults.MaxConcurrency
            AverageDurationPerModule = if ($ParallelResults.TotalModules -gt 0) {
                [math]::Round($ParallelResults.TotalDurationSeconds / $ParallelResults.TotalModules, 2)
            }
            else { 0 }
            SuccessRate = if ($ParallelResults.TotalModules -gt 0) {
                [math]::Round(($successfulModules.Count / $ParallelResults.TotalModules) * 100, 2)
            }
            else { 0 }
            SuccessfulModuleNames = $successfulModules.ModuleName
            FailedModuleNames = $failedModules.ModuleName
            Errors = $failedModules | ForEach-Object { @{ Module = $_.ModuleName; Error = $_.Error } }
            SessionId = $ParallelResults.SessionId
        }

        Write-LogEntry -Level 'INFO' -Component 'PARALLEL-ENGINE' -Message "Results merged: $($summary.SuccessfulModules)/$($summary.TotalModules) modules succeeded"

        return $summary
    }
    catch {
        Write-LogEntry -Level 'ERROR' -Component 'PARALLEL-ENGINE' -Message "Error merging results: $_"
        throw
    }
}

<#
.SYNOPSIS
    Gets available Type2 modules for execution

.DESCRIPTION
    Scans modules/type2 directory and returns available modules with metadata.
    Used for validation before parallel execution.

.OUTPUTS
    Hashtable of available modules with paths

.EXAMPLE
    $modules = Get-AvailableType2Modules
#>
function Get-AvailableType2Modules {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    try {
        $projectRoot = $env:MAINTENANCE_PROJECT_ROOT
        if (-not $projectRoot) {
            # Fallback: Calculate from current script location
            $projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        }

        $type2Path = Join-Path $projectRoot 'modules\type2'
        if (-not (Test-Path $type2Path)) {
            Write-LogEntry -Level 'WARNING' -Component 'PARALLEL-ENGINE' -Message "Type2 modules directory not found: $type2Path"
            return @{}
        }

        $modules = @{}
        $moduleFiles = Get-ChildItem -Path $type2Path -Filter '*.psm1' -File

        foreach ($file in $moduleFiles) {
            $moduleName = $file.BaseName
            $modules[$moduleName] = @{
                Path = $file.FullName
                Name = $moduleName
                LastModified = $file.LastWriteTime
            }
        }

        Write-LogEntry -Level 'DEBUG' -Component 'PARALLEL-ENGINE' -Message "Found $($modules.Count) Type2 modules"
        return $modules
    }
    catch {
        Write-LogEntry -Level 'ERROR' -Component 'PARALLEL-ENGINE' -Message "Error getting available modules: $_"
        return @{}
    }
}

#endregion

#region Export
Export-ModuleMember -Function @(
    'Invoke-ModulesInParallel',
    'Wait-ParallelModuleCompletion',
    'Merge-ParallelResults',
    'Get-AvailableType2Modules'
)
#endregion

