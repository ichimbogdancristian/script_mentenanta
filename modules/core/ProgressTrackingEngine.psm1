#Requires -Version 7.0

<#
.SYNOPSIS
    Progress Tracking Engine - Phase A.2.4 (Intelligent Task Orchestration)

.DESCRIPTION
    Provides real-time progress tracking for module execution with ETA calculation.
    Displays visual progress bars and generates comprehensive progress reports.

.NOTES
    Module Type: Core Infrastructure
    Architecture: v4.0 - Intelligent Orchestration
    Author: Windows Maintenance Automation Project
    Version: 4.0.0

    Design Pattern: State-based progress tracking with ETA calculation
    Features: Real-time updates, visual progress bars, accuracy metrics
#>

# Import CoreInfrastructure for logging
$CoreInfraPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'core\CoreInfrastructure.psm1'
if (Test-Path $CoreInfraPath) {
    Import-Module $CoreInfraPath -Force -Global -ErrorAction SilentlyContinue
}

<#
.SYNOPSIS
    Initializes progress tracking state

.DESCRIPTION
    Creates initial progress tracking state with module list and estimated durations.
    Uses dependency configuration to extract module metadata.

.PARAMETER Modules
    Array of module names to track

.PARAMETER EstimatedDurations
    Hashtable mapping module names to estimated duration in seconds

.OUTPUTS
    Hashtable with initialized progress state

.EXAMPLE
    $durations = @{ 'BloatwareRemoval' = 45; 'EssentialApps' = 30 }
    $tracker = Initialize-ProgressTracker -Modules @('BloatwareRemoval', 'EssentialApps') -EstimatedDurations $durations
#>
function Initialize-ProgressTracker {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Modules,

        [Parameter()]
        [hashtable]$EstimatedDurations = @{}
    )

    try {
        Write-LogEntry -Level 'DEBUG' -Component 'PROGRESS-TRACKER' -Message "Initializing progress tracker for $($Modules.Count) modules"

        # Calculate total estimated duration
        $totalEstimated = 0
        foreach ($module in $Modules) {
            $estimate = if ($EstimatedDurations.ContainsKey($module)) {
                $EstimatedDurations[$module]
            }
            else {
                30  # Default 30 seconds if not specified
            }
            $totalEstimated += $estimate
        }

        $state = @{
            StartTime = Get-Date
            TotalModules = $Modules.Count
            CompletedModules = @()
            CurrentModule = $null
            RemainingModules = @($Modules)
            EstimatedDurations = $EstimatedDurations
            ActualDurations = @{}
            TotalEstimatedSeconds = $totalEstimated
            ElapsedSeconds = 0
            ProgressPercentage = 0
            EstimatedRemainingSeconds = $totalEstimated
            EstimatedCompletionTime = (Get-Date).AddSeconds($totalEstimated)
        }

        Write-LogEntry -Level 'INFO' -Component 'PROGRESS-TRACKER' -Message "Tracker initialized: $($Modules.Count) modules, estimated $totalEstimated seconds total"

        return $state
    }
    catch {
        Write-LogEntry -Level 'ERROR' -Component 'PROGRESS-TRACKER' -Message "Error initializing tracker: $_"
        throw
    }
}

<#
.SYNOPSIS
    Updates progress tracking state

.DESCRIPTION
    Records module completion and updates progress calculations including ETA.

.PARAMETER ProgressState
    Current progress tracking state

.PARAMETER ModuleName
    Name of completed module

.PARAMETER ActualDuration
    Actual execution duration in seconds

.OUTPUTS
    Updated progress state hashtable

.EXAMPLE
    $tracker = Update-ProgressTracker -ProgressState $tracker -ModuleName 'BloatwareRemoval' -ActualDuration 42.5
#>
function Update-ProgressTracker {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [hashtable]$ProgressState,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ModuleName,

        [Parameter(Mandatory)]
        [ValidateRange(0, [double]::MaxValue)]
        [double]$ActualDuration
    )

    try {
        Write-LogEntry -Level 'DEBUG' -Component 'PROGRESS-TRACKER' -Message "Updating progress: $ModuleName completed in $ActualDuration seconds"

        # Record completion
        $ProgressState.CompletedModules += @($ModuleName)
        $ProgressState.ActualDurations[$ModuleName] = $ActualDuration
        $ProgressState.RemainingModules = $ProgressState.RemainingModules | Where-Object { $_ -ne $ModuleName }
        $ProgressState.CurrentModule = $null

        # Calculate elapsed time
        $ProgressState.ElapsedSeconds = ((Get-Date) - $ProgressState.StartTime).TotalSeconds

        # Calculate progress percentage
        $ProgressState.ProgressPercentage = [math]::Round(($ProgressState.CompletedModules.Count / $ProgressState.TotalModules) * 100, 2)

        # Calculate estimated remaining time
        if ($ProgressState.CompletedModules.Count -gt 0) {
            # Use actual average duration for better accuracy
            $avgActualDuration = ($ProgressState.ActualDurations.Values | Measure-Object -Average).Average
            $remainingModuleCount = $ProgressState.RemainingModules.Count

            # Calculate remaining time based on actual performance
            $estimatedRemaining = $avgActualDuration * $remainingModuleCount
            $ProgressState.EstimatedRemainingSeconds = [math]::Max(0, $estimatedRemaining)
            $ProgressState.EstimatedCompletionTime = (Get-Date).AddSeconds($estimatedRemaining)
        }
        else {
            # No data yet, use original estimates
            $ProgressState.EstimatedRemainingSeconds = $ProgressState.TotalEstimatedSeconds
            $ProgressState.EstimatedCompletionTime = $ProgressState.StartTime.AddSeconds($ProgressState.TotalEstimatedSeconds)
        }

        Write-LogEntry -Level 'INFO' -Component 'PROGRESS-TRACKER' -Message "Progress: $($ProgressState.ProgressPercentage)% complete ($($ProgressState.CompletedModules.Count)/$($ProgressState.TotalModules) modules)"

        return $ProgressState
    }
    catch {
        Write-LogEntry -Level 'ERROR' -Component 'PROGRESS-TRACKER' -Message "Error updating progress: $_"
        throw
    }
}

<#
.SYNOPSIS
    Marks a module as currently executing

.DESCRIPTION
    Updates state to indicate which module is currently being processed.

.PARAMETER ProgressState
    Current progress tracking state

.PARAMETER ModuleName
    Name of module starting execution

.OUTPUTS
    Updated progress state hashtable

.EXAMPLE
    $tracker = Set-CurrentModule -ProgressState $tracker -ModuleName 'EssentialApps'
#>
function Set-CurrentModule {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [hashtable]$ProgressState,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ModuleName
    )

    try {
        $ProgressState.CurrentModule = $ModuleName
        Write-LogEntry -Level 'DEBUG' -Component 'PROGRESS-TRACKER' -Message "Current module: $ModuleName"
        return $ProgressState
    }
    catch {
        Write-LogEntry -Level 'ERROR' -Component 'PROGRESS-TRACKER' -Message "Error setting current module: $_"
        throw
    }
}

<#
.SYNOPSIS
    Gets current progress status

.DESCRIPTION
    Calculates and returns comprehensive progress metrics including ETA.

.PARAMETER ProgressState
    Current progress tracking state

.OUTPUTS
    PSCustomObject with progress metrics

.EXAMPLE
    $status = Get-ProgressStatus -ProgressState $tracker
    Write-Host "Progress: $($status.ProgressPercentage)% - ETA: $($status.EstimatedCompletionTime)"
#>
function Get-ProgressStatus {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [hashtable]$ProgressState
    )

    try {
        $status = [PSCustomObject]@{
            TotalModules = $ProgressState.TotalModules
            CompletedModules = $ProgressState.CompletedModules.Count
            RemainingModules = $ProgressState.RemainingModules.Count
            CurrentModule = $ProgressState.CurrentModule
            ProgressPercentage = $ProgressState.ProgressPercentage
            ElapsedSeconds = [math]::Round($ProgressState.ElapsedSeconds, 2)
            ElapsedTimeFormatted = [TimeSpan]::FromSeconds($ProgressState.ElapsedSeconds).ToString('hh\:mm\:ss')
            EstimatedRemainingSeconds = [math]::Round($ProgressState.EstimatedRemainingSeconds, 2)
            RemainingTimeFormatted = [TimeSpan]::FromSeconds($ProgressState.EstimatedRemainingSeconds).ToString('hh\:mm\:ss')
            EstimatedCompletionTime = $ProgressState.EstimatedCompletionTime
            EstimatedTotalSeconds = [math]::Round($ProgressState.ElapsedSeconds + $ProgressState.EstimatedRemainingSeconds, 2)
            AverageModuleDuration = if ($ProgressState.CompletedModules.Count -gt 0) {
                [math]::Round(($ProgressState.ActualDurations.Values | Measure-Object -Average).Average, 2)
            }
            else { 0 }
        }

        return $status
    }
    catch {
        Write-LogEntry -Level 'ERROR' -Component 'PROGRESS-TRACKER' -Message "Error getting progress status: $_"
        throw
    }
}

<#
.SYNOPSIS
    Displays visual progress bar

.DESCRIPTION
    Shows PowerShell progress bar with current status and ETA.

.PARAMETER ProgressState
    Current progress tracking state

.PARAMETER Activity
    Activity description for progress bar

.EXAMPLE
    Show-ProgressBar -ProgressState $tracker -Activity "System Maintenance"
#>
function Show-ProgressBar {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [hashtable]$ProgressState,

        [Parameter()]
        [string]$Activity = "Module Execution Progress"
    )

    try {
        $status = Get-ProgressStatus -ProgressState $ProgressState

        $statusMessage = if ($ProgressState.CurrentModule) {
            "Processing: $($ProgressState.CurrentModule) ($($status.CompletedModules)/$($status.TotalModules) completed)"
        }
        else {
            "$($status.CompletedModules)/$($status.TotalModules) modules completed"
        }

        $currentOperation = "Elapsed: $($status.ElapsedTimeFormatted) | Remaining: $($status.RemainingTimeFormatted) | ETA: $($status.EstimatedCompletionTime.ToString('HH:mm:ss'))"

        Write-Progress `
            -Activity $Activity `
            -Status $statusMessage `
            -CurrentOperation $currentOperation `
            -PercentComplete $status.ProgressPercentage
    }
    catch {
        Write-LogEntry -Level 'ERROR' -Component 'PROGRESS-TRACKER' -Message "Error showing progress bar: $_"
        # Don't throw - visual display errors shouldn't halt execution
    }
}

<#
.SYNOPSIS
    Generates comprehensive progress report

.DESCRIPTION
    Creates detailed report with execution statistics, accuracy metrics, and performance analysis.

.PARAMETER ProgressState
    Final progress tracking state

.OUTPUTS
    PSCustomObject with comprehensive progress report

.EXAMPLE
    $report = Get-ProgressReport -ProgressState $finalTracker
    Write-Host "Total execution time: $($report.TotalElapsedTimeFormatted)"
#>
function Get-ProgressReport {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [hashtable]$ProgressState
    )

    try {
        Write-LogEntry -Level 'DEBUG' -Component 'PROGRESS-TRACKER' -Message "Generating progress report"

        $totalElapsed = ((Get-Date) - $ProgressState.StartTime).TotalSeconds
        $actualDurations = $ProgressState.ActualDurations.Values

        # Calculate accuracy metrics
        $estimateAccuracy = if ($ProgressState.TotalEstimatedSeconds -gt 0) {
            $diff = [math]::Abs($totalElapsed - $ProgressState.TotalEstimatedSeconds)
            $accuracy = 100 - (($diff / $ProgressState.TotalEstimatedSeconds) * 100)
            [math]::Max(0, [math]::Round($accuracy, 2))
        }
        else { 0 }

        # Performance metrics
        $avgDuration = if ($actualDurations.Count -gt 0) {
            ($actualDurations | Measure-Object -Average).Average
        }
        else { 0 }

        $minDuration = if ($actualDurations.Count -gt 0) {
            ($actualDurations | Measure-Object -Minimum).Minimum
        }
        else { 0 }

        $maxDuration = if ($actualDurations.Count -gt 0) {
            ($actualDurations | Measure-Object -Maximum).Maximum
        }
        else { 0 }

        $report = [PSCustomObject]@{
            TotalModules = $ProgressState.TotalModules
            CompletedModules = $ProgressState.CompletedModules.Count
            CompletionRate = [math]::Round(($ProgressState.CompletedModules.Count / $ProgressState.TotalModules) * 100, 2)

            TotalElapsedSeconds = [math]::Round($totalElapsed, 2)
            TotalElapsedTimeFormatted = [TimeSpan]::FromSeconds($totalElapsed).ToString('hh\:mm\:ss')

            TotalEstimatedSeconds = $ProgressState.TotalEstimatedSeconds
            EstimateAccuracyPercentage = $estimateAccuracy

            AverageModuleDuration = [math]::Round($avgDuration, 2)
            MinimumModuleDuration = [math]::Round($minDuration, 2)
            MaximumModuleDuration = [math]::Round($maxDuration, 2)

            CompletedModulesList = $ProgressState.CompletedModules
            ActualDurations = $ProgressState.ActualDurations

            StartTime = $ProgressState.StartTime
            EndTime = Get-Date
        }

        Write-LogEntry -Level 'INFO' -Component 'PROGRESS-TRACKER' -Message "Progress report: $($report.CompletedModules)/$($report.TotalModules) modules, $($report.TotalElapsedTimeFormatted) elapsed, $($report.EstimateAccuracyPercentage)% estimate accuracy"

        return $report
    }
    catch {
        Write-LogEntry -Level 'ERROR' -Component 'PROGRESS-TRACKER' -Message "Error generating progress report: $_"
        throw
    }
}

<#
.SYNOPSIS
    Clears progress bar display

.DESCRIPTION
    Hides the progress bar after operations complete.

.EXAMPLE
    Clear-ProgressBar
#>
function Clear-ProgressBar {
    [CmdletBinding()]
    param()

    try {
        Write-Progress -Activity "Complete" -Completed
    }
    catch {
        # Ignore errors clearing progress bar
    }
}

# Export public functions
Export-ModuleMember -Function @(
    'Initialize-ProgressTracker',
    'Update-ProgressTracker',
    'Set-CurrentModule',
    'Get-ProgressStatus',
    'Show-ProgressBar',
    'Get-ProgressReport',
    'Clear-ProgressBar'
)

