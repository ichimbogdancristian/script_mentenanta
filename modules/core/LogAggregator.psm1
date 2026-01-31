#Requires -Version 7.0

<#
.SYNOPSIS
    Log Aggregator Module - Result Collection & Correlation

.DESCRIPTION
    Provides unified log aggregation and result correlation across all modules.
    Collects execution results from individual modules, normalizes them to a standard schema,
    and prepares aggregated data for report generation. Implements correlation IDs for tracing
    and standardized result object structure.

.MODULE ARCHITECTURE
    Purpose:
        Serve as the data aggregation layer between module execution and report generation.
        Collects results from Type1 (audit) and Type2 (execution) modules.
        Provides standardized result objects and correlation tracking.

    Dependencies:
        • CoreInfrastructure.psm1 - For path management and logging

    Exports:
        • New-CorrelationId - Generate unique correlation ID
        • New-ModuleResult - Create standardized result object
        • Add-ModuleResult - Add result to session results collection
        • Get-AggregatedResults - Retrieve all aggregated results
        • Get-ModuleResultsByName - Query results by module name
        • Start-ResultCollection - Initialize result collection session
        • Complete-ResultCollection - Finalize and export results
        • Get-ResultsReport - Generate text summary of results

    Import Pattern:
        Import-Module LogAggregator.psm1 -Force
        # Functions available in MaintenanceOrchestrator context

    Used By:
        - MaintenanceOrchestrator.ps1 (primary consumer)
        - LogProcessor.psm1 (data source preparation)
        - ReportGenerator.psm1 (data consumer)

.EXECUTION FLOW
    1. MaintenanceOrchestrator calls Start-ResultCollection
    2. As each module completes, Add-ModuleResult is called
    3. Modules provide itemsDetected, itemsProcessed, duration, errors
    4. Results are stored with correlation to session ID
    5. MaintenanceOrchestrator calls Complete-ResultCollection before report generation
    6. ReportGenerator queries Get-AggregatedResults for report data

.DATA STRUCTURES

    ModuleResult Object:
    @{
        ModuleName = "SystemInventory"
        CorrelationId = "eadf22e4-f811-447a-8672-3910b93c89b0"
        ExecutionSequence = 1
        Status = "Success|Failed|Skipped|DryRun"

        Metrics = @{
            ItemsDetected = 63
            ItemsProcessed = 1
            ItemsSkipped = 0
            ItemsFailed = 0
            DurationSeconds = 12.73
            StartTime = "2025-10-26T19:51:37.547941+02:00"
            EndTime = "2025-10-26T19:51:50.274891+02:00"
        }

        Results = @{
            # Module-specific detail
            ProcessorName = "AMD Ryzen 7 4800H"
            ProcessorCores = 8
            MemoryGB = 32
            StorageGB = 476.07
            FreeStorageGB = 286.99
        }

        Errors = @()  # Array of error objects if Status = "Failed"
        Warnings = @()  # Array of warning messages
        LogPath = "temp_files/logs/system-inventory/execution.log"
        RawData = @{}  # Original module output for fallback
    }

.NOTES
    Module Type: Core Infrastructure
    Architecture: v3.0 - New module for enhanced logging
    Version: 1.0.0

    Key Features:
    - Standardized result schema across all modules
    - Correlation ID tracking for traceability
    - Result aggregation and summary generation
    - Support for module-specific data with common interface
    - Error and warning collection
    - Metrics calculation and normalization

    Design Patterns:
    - Factory pattern: New-ModuleResult creates standardized objects
    - Repository pattern: Session results collection
    - Query pattern: GetModuleResultsByName, Get-AggregatedResults
    - Reporting pattern: Get-ResultsReport generates summaries
#>

using namespace System.Collections.Generic

# Import core infrastructure for path management and logging
$CoreInfraPath = Join-Path $PSScriptRoot 'CoreInfrastructure.psm1'
if (Test-Path $CoreInfraPath) {
    Import-Module $CoreInfraPath -Force -WarningAction SilentlyContinue
}
else {
    Write-Warning "CoreInfrastructure module not found at: $CoreInfraPath"
}

#region Module State

# Module results collection - keyed by module name for quick access
$script:SessionResults = @{
    SessionId         = $null
    CorrelationId     = $null
    StartTime         = $null
    EndTime           = $null
    Results           = [ordered]@{}  # ModuleName => ModuleResult
    ErrorLog          = [System.Collections.Generic.List[PSObject]]::new()
    WarningLog        = [System.Collections.Generic.List[PSObject]]::new()
    ExecutionSequence = 0
}

# Configuration
$script:Config = @{
    MaxErrors        = 1000
    MaxWarnings      = 5000
    ResultsCachePath = $null
    EnableAutoExport = $true
}

#endregion

#region Public Functions

<#
.SYNOPSIS
    Initialize result collection for a maintenance session

.DESCRIPTION
    Creates a new session for result collection with unique correlation ID.
    Called at the start of MaintenanceOrchestrator execution.

.PARAMETER SessionId
    Unique session identifier (e.g., GUID)

.EXAMPLE
    Start-ResultCollection -SessionId $Global:MaintenanceSessionId
#>
function Start-ResultCollection {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string]$SessionId,

        [Parameter()]
        [string]$CachePath = $null
    )

    $script:SessionResults.SessionId = $SessionId
    $script:SessionResults.CorrelationId = (New-CorrelationId)
    $script:SessionResults.StartTime = Get-Date
    $script:SessionResults.EndTime = $null
    $script:SessionResults.Results.Clear()
    $script:SessionResults.ErrorLog.Clear()
    $script:SessionResults.WarningLog.Clear()
    $script:SessionResults.ExecutionSequence = 0

    if (-not [string]::IsNullOrEmpty($CachePath)) {
        $script:Config.ResultsCachePath = $CachePath
    }

    Write-Verbose "ResultCollection session started: SessionId=$SessionId, CorrelationId=$($script:SessionResults.CorrelationId)"
}

<#
.SYNOPSIS
    Generate a unique correlation ID

.DESCRIPTION
    Creates a correlation ID that can be used to trace related operations
    across modules and log entries.

.OUTPUTS
    [string] Correlation ID in format: YYYYMMDD-HHmmss-XXXXX (5-char random)

.EXAMPLE
    $correlationId = New-CorrelationId
#>
function New-CorrelationId {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $random = [guid]::NewGuid().ToString().Substring(0, 5)
    return "$timestamp-$random"
}

<#
.SYNOPSIS
    Create a standardized module result object

.DESCRIPTION
    Constructs a result object with standard schema for storing execution results.
    All modules should normalize their results to this schema.

.PARAMETER ModuleName
    Name of the module (e.g., "SystemInventory", "BloatwareRemoval")

.PARAMETER Status
    Execution status: Success, Failed, Skipped, DryRun

.PARAMETER ItemsDetected
    Count of items detected by module (audit modules) or actions discovered

.PARAMETER ItemsProcessed
    Count of items successfully processed/executed

.PARAMETER ItemsSkipped
    Count of items skipped (e.g., filtered out, already complete)

.PARAMETER ItemsFailed
    Count of items that failed to process

.PARAMETER DurationSeconds
    Execution duration in seconds

.PARAMETER LogPath
    Path to module's execution log file

.PARAMETER Results
    [hashtable] Module-specific results data

.PARAMETER Errors
    [array] Array of error objects or strings

.PARAMETER Warnings
    [array] Array of warning strings

.EXAMPLE
    $result = New-ModuleResult `
        -ModuleName "BloatwareRemoval" `
        -Status "Success" `
        -ItemsDetected 25 `
        -ItemsProcessed 18 `
        -DurationSeconds 34.5 `
        -LogPath "temp_files/logs/bloatware-removal/execution.log"
#>
function New-ModuleResult {
    [CmdletBinding()]
    [OutputType([PSObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ModuleName,

        [Parameter()]
        [ValidateSet('Success', 'Failed', 'Skipped', 'DryRun')]
        [string]$Status = 'Success',

        [Parameter()]
        [int]$ItemsDetected = 0,

        [Parameter()]
        [int]$ItemsProcessed = 0,

        [Parameter()]
        [int]$ItemsSkipped = 0,

        [Parameter()]
        [int]$ItemsFailed = 0,

        [Parameter()]
        [decimal]$DurationSeconds = 0,

        [Parameter()]
        [datetime]$StartTime = $null,

        [Parameter()]
        [datetime]$EndTime = $null,

        [Parameter()]
        [string]$LogPath = $null,

        [Parameter()]
        [hashtable]$Results = @{},

        [Parameter()]
        [array]$Errors = @(),

        [Parameter()]
        [array]$Warnings = @(),

        # Enhanced reporting parameters
        [Parameter()]
        [string]$Summary = '',

        [Parameter()]
        [hashtable]$ExecutionPhases = @{},

        [Parameter()]
        [array]$Recommendations = @(),

        [Parameter()]
        [string]$Icon = '⚙️'
    )

    if ($null -eq $StartTime) { $StartTime = Get-Date }
    if ($null -eq $EndTime) { $EndTime = Get-Date }

    $moduleResult = [PSCustomObject]@{
        PSTypeName        = 'MaintenanceAutomation.ModuleResult'
        ModuleName        = $ModuleName
        Status            = $Status
        CorrelationId     = $script:SessionResults.CorrelationId
        ExecutionSequence = ++$script:SessionResults.ExecutionSequence

        Metrics           = [PSCustomObject]@{
            ItemsDetected   = [int]$ItemsDetected
            ItemsProcessed  = [int]$ItemsProcessed
            ItemsSkipped    = [int]$ItemsSkipped
            ItemsFailed     = [int]$ItemsFailed
            DurationSeconds = [decimal]$DurationSeconds
            StartTime       = $StartTime.ToString('o')
            EndTime         = $EndTime.ToString('o')
        }

        Results           = $Results
        Errors            = @($Errors)
        Warnings          = @($Warnings)
        LogPath           = $LogPath
        Timestamp         = Get-Date

        # Enhanced reporting fields
        Summary           = $Summary
        ExecutionPhases   = $ExecutionPhases
        Recommendations   = @($Recommendations)
        Icon              = $Icon
    }

    return $moduleResult
}

<#
.SYNOPSIS
    Add a module result to the session collection

.DESCRIPTION
    Registers a module result in the aggregated results collection.
    Results are stored by module name for quick retrieval.

.PARAMETER Result
    ModuleResult object (from New-ModuleResult)

.PARAMETER Force
    If specified, overwrites existing result for the module

.EXAMPLE
    $result = New-ModuleResult -ModuleName "SystemInventory" -Status "Success" -ItemsDetected 63 -DurationSeconds 12.73
    Add-ModuleResult -Result $result

.EXAMPLE
    Add-ModuleResult -Result $result -Force  # Replace existing result
#>
function Add-ModuleResult {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [PSObject]$Result,

        [Parameter()]
        [switch]$Force
    )

    process {
        $moduleName = $Result.ModuleName

        if ($script:SessionResults.Results.ContainsKey($moduleName) -and -not $Force) {
            Write-Warning "Result for module '$moduleName' already exists. Use -Force to overwrite."
            return
        }

        $script:SessionResults.Results[$moduleName] = $Result

        # Collect errors and warnings
        if ($Result.Errors.Count -gt 0) {
            $Result.Errors | ForEach-Object {
                if ($script:SessionResults.ErrorLog.Count -lt $script:Config.MaxErrors) {
                    $script:SessionResults.ErrorLog.Add(@{
                            ModuleName = $moduleName
                            Error      = $_
                            Timestamp  = Get-Date
                        })
                }
            }
        }

        if ($Result.Warnings.Count -gt 0) {
            $Result.Warnings | ForEach-Object {
                if ($script:SessionResults.WarningLog.Count -lt $script:Config.MaxWarnings) {
                    $script:SessionResults.WarningLog.Add(@{
                            ModuleName = $moduleName
                            Warning    = $_
                            Timestamp  = Get-Date
                        })
                }
            }
        }

        Write-Verbose "Added result for module: $moduleName (Status: $($Result.Status))"
    }
}

<#
.SYNOPSIS
    Retrieve all aggregated results

.DESCRIPTION
    Returns the complete collection of module results for current session.

.PARAMETER AsHashtable
    If specified, returns results as hashtable instead of array

.EXAMPLE
    $allResults = Get-AggregatedResults

.EXAMPLE
    $resultsHash = Get-AggregatedResults -AsHashtable
#>
function Get-AggregatedResults {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter()]
        [switch]$AsHashtable
    )

    if ($AsHashtable) {
        return $script:SessionResults.Results
    }
    else {
        return @($script:SessionResults.Results.Values)
    }
}

<#
.SYNOPSIS
    Query results by module name

.DESCRIPTION
    Retrieves result for a specific module.

.PARAMETER ModuleName
    Name of the module to retrieve

.EXAMPLE
    $sysResult = Get-ModuleResultsByName -ModuleName "SystemInventory"
#>
function Get-ModuleResultsByName {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string]$ModuleName
    )

    return $script:SessionResults.Results[$ModuleName]
}

<#
.SYNOPSIS
    Generate aggregated summary statistics

.DESCRIPTION
    Calculates summary metrics across all module results.
    Returns object with total modules, success count, total duration, etc.

.EXAMPLE
    $summary = Get-ResultsSummary

.OUTPUTS
    [PSCustomObject] with properties:
    - TotalModules: Total modules executed
    - SuccessfulModules: Modules with Status = Success
    - FailedModules: Modules with Status = Failed
    - SkippedModules: Modules with Status = Skipped
    - DryRunModules: Modules with Status = DryRun
    - TotalDurationSeconds: Sum of all module durations
    - TotalItemsDetected: Sum of ItemsDetected across modules
    - TotalItemsProcessed: Sum of ItemsProcessed across modules
    - TotalErrors: Error count
    - TotalWarnings: Warning count
    - SuccessRate: Percentage of successful modules
#>
function Get-ResultsSummary {
    [CmdletBinding()]
    [OutputType([hashtable])]()
param(

    $allResults = Get-AggregatedResults

    $summary = [PSCustomObject]@{
        TotalModules         = $allResults.Count
        SuccessfulModules    = ($allResults | Where-Object { $_.Status -eq 'Success' }).Count
        FailedModules        = ($allResults | Where-Object { $_.Status -eq 'Failed' }).Count
        SkippedModules       = ($allResults | Where-Object { $_.Status -eq 'Skipped' }).Count
        DryRunModules        = ($allResults | Where-Object { $_.Status -eq 'DryRun' }).Count
        TotalDurationSeconds = ($allResults | Measure-Object -Property { $_.Metrics.DurationSeconds } -Sum).Sum
        TotalItemsDetected   = ($allResults | Measure-Object -Property { $_.Metrics.ItemsDetected } -Sum).Sum
        TotalItemsProcessed  = ($allResults | Measure-Object -Property { $_.Metrics.ItemsProcessed } -Sum).Sum
        TotalErrors          = $script:SessionResults.ErrorLog.Count
        TotalWarnings        = $script:SessionResults.WarningLog.Count
        SuccessRate          = if ($allResults.Count -gt 0) {
            [math]::Round(($allResults | Where-Object { $_.Status -eq 'Success' }).Count / $allResults.Count * 100, 2)
        }
        else { 0 }
    }

    return $summary
}

<#
.SYNOPSIS
    Finalize result collection and prepare for export

.DESCRIPTION
    Marks result collection as complete. Optionally exports results to JSON.
    Called before report generation.

.PARAMETER ExportPath
    If specified, exports aggregated results to JSON file

.EXAMPLE
    Complete-ResultCollection -ExportPath "temp_files/processed/aggregated-results.json"
#>
function Complete-ResultCollection {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter()]
        [string]$ExportPath = $null
    )

    $script:SessionResults.EndTime = Get-Date

    $sessionData = @{
        SessionId       = $script:SessionResults.SessionId
        CorrelationId   = $script:SessionResults.CorrelationId
        StartTime       = $script:SessionResults.StartTime.ToString('o')
        EndTime         = $script:SessionResults.EndTime.ToString('o')
        DurationSeconds = ($script:SessionResults.EndTime - $script:SessionResults.StartTime).TotalSeconds
        Summary         = Get-ResultsSummary
        ModuleResults   = @($script:SessionResults.Results.Values)
        Errors          = $script:SessionResults.ErrorLog
        Warnings        = $script:SessionResults.WarningLog
    }

    if (-not [string]::IsNullOrEmpty($ExportPath)) {
        try {
            $sessionData | ConvertTo-Json -Depth 10 | Set-Content -Path $ExportPath -Force -Encoding UTF8
            Write-Verbose "Session results exported to: $ExportPath"
        }
        catch {
            Write-Error "Failed to export session results: $_"
        }
    }

    return $sessionData
}

<#
.SYNOPSIS
    Generate text summary of all results

.DESCRIPTION
    Creates a formatted text report summarizing execution results.
    Useful for logging or display purposes.

.EXAMPLE
    $report = Get-ResultsReport
    $report | Out-Host
#>
function Get-ResultsReport {
    [CmdletBinding()]
    [OutputType([string[]])]
    param()

    $lines = @()
    $lines += "=========================================="
    $lines += "Maintenance Execution Results"
    $lines += "=========================================="
    $lines += ""

    $summary = Get-ResultsSummary
    $lines += "SUMMARY:"
    $lines += "  Total Modules:     $($summary.TotalModules)"
    $lines += "  Successful:        $($summary.SuccessfulModules)"
    $lines += "  Failed:            $($summary.FailedModules)"
    $lines += "  Skipped:           $($summary.SkippedModules)"
    $lines += "  Success Rate:      $($summary.SuccessRate)%"
    $lines += "  Total Duration:    $([math]::Round($summary.TotalDurationSeconds, 2))s"
    $lines += "  Items Detected:    $($summary.TotalItemsDetected)"
    $lines += "  Items Processed:   $($summary.TotalItemsProcessed)"
    $lines += ""

    $lines += "MODULE RESULTS:"
    foreach ($result in (Get-AggregatedResults)) {
        $lines += "  $($result.ModuleName)"
        $lines += "    Status:         $($result.Status)"
        $lines += "    Detected:       $($result.Metrics.ItemsDetected)"
        $lines += "    Processed:      $($result.Metrics.ItemsProcessed)"
        $lines += "    Duration:       $([math]::Round($result.Metrics.DurationSeconds, 2))s"
        $lines += ""
    }

    if ($summary.TotalErrors -gt 0) {
        $lines += "ERRORS ($($summary.TotalErrors)):"
        $script:SessionResults.ErrorLog | ForEach-Object { $lines += "  [$($_.ModuleName)] $($_.Error)" }
        $lines += ""
    }

    if ($summary.TotalWarnings -gt 0) {
        $lines += "WARNINGS ($($summary.TotalWarnings)):"
        $script:SessionResults.WarningLog | ForEach-Object { $lines += "  [$($_.ModuleName)] $($_.Warning)" }
        $lines += ""
    }

    $lines += "=========================================="
    return $lines
}

<#
.SYNOPSIS
    Get errors from result collection

.DESCRIPTION
    Retrieves all collected errors, optionally filtered by module.

.PARAMETER ModuleName
    If specified, returns only errors from this module

.EXAMPLE
    $errors = Get-CollectedErrors
    Get-CollectedErrors -ModuleName "AppUpgrade"
#>
function Get-CollectedErrors {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter()]
        [string]$ModuleName = $null
    )

    if ([string]::IsNullOrEmpty($ModuleName)) {
        return @($script:SessionResults.ErrorLog)
    }
    else {
        return @($script:SessionResults.ErrorLog | Where-Object { $_.ModuleName -eq $ModuleName })
    }
}

<#
.SYNOPSIS
    Get warnings from result collection

.DESCRIPTION
    Retrieves all collected warnings, optionally filtered by module.

.PARAMETER ModuleName
    If specified, returns only warnings from this module

.EXAMPLE
    $warnings = Get-CollectedWarnings
    Get-CollectedWarnings -ModuleName "BloatwareRemoval"
#>
function Get-CollectedWarnings {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter()]
        [string]$ModuleName = $null
    )

    if ([string]::IsNullOrEmpty($ModuleName)) {
        return @($script:SessionResults.WarningLog)
    }
    else {
        return @($script:SessionResults.WarningLog | Where-Object { $_.ModuleName -eq $ModuleName })
    }
}

#endregion

#region Module Export

Export-ModuleMember -Function @(
    'Start-ResultCollection',
    'New-CorrelationId',
    'New-ModuleResult',
    'Add-ModuleResult',
    'Get-AggregatedResults',
    'Get-ModuleResultsByName',
    'Get-ResultsSummary',
    'Complete-ResultCollection',
    'Get-ResultsReport',
    'Get-CollectedErrors',
    'Get-CollectedWarnings'
)

#endregion




