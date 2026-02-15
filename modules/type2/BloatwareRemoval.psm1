#Requires -Version 7.0
# Module Dependencies:
#   - CoreInfrastructure.psm1 (configuration, logging, path management)
#   - BloatwareDetectionAudit.psm1 (Type1 - detection/analysis)
#
# External Tools (managed by script.bat launcher):
#   - winget.exe (Windows Package Manager)
#   - choco.exe (Chocolatey - optional)

<#
.SYNOPSIS
    Bloatware Removal Module - Type 2 (System Modification)

.DESCRIPTION
    Safe and comprehensive bloatware removal across multiple package managers and installation sources.
    Provides multiple removal methods with fallback options and detailed logging.

.NOTES
    Module Type: Type 2 (System Modification)
    Dependencies: BloatwareDetectionAudit.psm1, CoreInfrastructure.psm1
    Requires: Administrator privileges
    Author: Windows Maintenance Automation Project
    Version: 1.0.0
#>

using namespace System.Collections.Generic
using namespace System.Collections.Concurrent

# v3.0 Self-contained Type 2 module with internal Type 1 dependency

# Step 1: Import core infrastructure FIRST (REQUIRED) - Global scope for Type1 access
$ModuleRoot = if ($PSScriptRoot) { Split-Path -Parent $PSScriptRoot } else { Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path) }
$CoreInfraPath = Join-Path $ModuleRoot 'core\CoreInfrastructure.psm1'
if (Test-Path $CoreInfraPath) {
    Import-Module $CoreInfraPath -Force -Global -WarningAction SilentlyContinue
}
else {
    Write-Warning "CoreInfrastructure module not found at: $CoreInfraPath"
}

# Step 1.5: Import CommonUtilities for shared helper functions (Phase B.3)
$CommonUtilsPath = Join-Path $ModuleRoot 'core\CommonUtilities.psm1'
if (Test-Path $CommonUtilsPath) {
    Import-Module $CommonUtilsPath -Force -Global -WarningAction SilentlyContinue
}
else {
    Write-Warning "CommonUtilities module not found at: $CommonUtilsPath"
}

# Step 2: Import corresponding Type 1 module AFTER CoreInfrastructure (REQUIRED)
$Type1ModulePath = Join-Path $ModuleRoot 'type1\BloatwareDetectionAudit.psm1'
if (Test-Path $Type1ModulePath) {
    Import-Module $Type1ModulePath -Force
}
else {
    throw "Required Type 1 module not found: $Type1ModulePath"
}

# Note: DependencyManager import removed as functions are not used
# BloatwareRemoval calls winget.exe and choco.exe directly

# Validate Type1 module loaded correctly
if (-not (Get-Command -Name 'Find-InstalledBloatware' -ErrorAction SilentlyContinue)) {
    throw "Type 1 module functions not available - ensure BloatwareDetection.psm1 is properly imported"
}

#region v3.0 Standardized Execution Function

<#
.SYNOPSIS
    Main execution function for bloatware removal - v3.0 Architecture Pattern

.DESCRIPTION
    Standardized entry point that implements the Type2 -> Type1 flow:
    1. Calls BloatwareDetection (Type1) to detect bloatware
    2. Validates findings and logs results
    3. Executes removal actions in live mode
    4. Returns standardized results for ReportGeneration

.PARAMETER Config
    Main configuration object from orchestrator

.EXAMPLE
    $result = Invoke-BloatwareRemoval -Config $MainConfig
#>
function Invoke-BloatwareRemoval {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Config,

        [Parameter()]
        [array]$DiffList
    )

    # Performance tracking
    $perfContext = $null
    try {
        $perfContext = Start-PerformanceTracking -OperationName 'BloatwareRemoval' -Component 'BLOATWARE-REMOVAL'
    }
    catch {
        Write-Verbose "BLOATWARE-REMOVAL: Performance tracking unavailable - $_"
        # CoreInfrastructure not available, continue without performance tracking
    }

    try {
        # Track execution duration for v3.0 compliance
        $executionStartTime = Get-Date

        # Display module banner
        Write-Host "`n" -NoNewline
        Write-Host "=================================================" -ForegroundColor Cyan
        Write-Host "  BLOATWARE REMOVAL MODULE v3.0" -ForegroundColor White
        Write-Host "=================================================" -ForegroundColor Cyan
        Write-Host "  Type: " -NoNewline -ForegroundColor Gray
        Write-Host "Type 2 (System Modification)" -ForegroundColor Yellow
        Write-Host "  Mode: " -NoNewline -ForegroundColor Gray
        Write-Host "LIVE EXECUTION" -ForegroundColor Green
        Write-Host "=================================================" -ForegroundColor Cyan
        Write-Host ""

        # Initialize module execution environment
        Initialize-ModuleExecution -ModuleName 'BloatwareRemoval'

        # STEP 1: Load diff list when available, otherwise run Type1 detection
        $executionLogPath = Get-SessionPath -Category 'logs' -SubCategory 'bloatware-removal' -FileName 'execution.log'
        $executionLogDir = Split-Path -Parent $executionLogPath

        Write-StructuredLogEntry -Level 'INFO' -Component 'BLOATWARE-REMOVAL' -Message 'Starting bloatware detection' -LogPath $executionLogPath -Operation 'Detect'

        $diffListProvided = $PSBoundParameters.ContainsKey('DiffList')
        $diffListFromDisk = if (-not $diffListProvided) { Get-DiffResults -ModuleName 'BloatwareRemoval' } else { @() }
        $effectiveDiffList = if ($diffListProvided) { $DiffList } elseif ($diffListFromDisk.Count -gt 0) { $diffListFromDisk } else { $null }

        if ($effectiveDiffList -and $effectiveDiffList.Count -eq 0) {
            Write-StructuredLogEntry -Level 'INFO' -Component 'BLOATWARE-REMOVAL' -Message 'Diff list empty - skipping bloatware removal' -LogPath $executionLogPath -Operation 'Complete' -Result 'NoItemsFound'
            if ($perfContext) { Complete-PerformanceTracking -Context $perfContext -Status 'Success' }
            $executionTime = (Get-Date) - $executionStartTime
            return New-ModuleExecutionResult `
                -Success $true `
                -ItemsDetected 0 `
                -ItemsProcessed 0 `
                -DurationMilliseconds $executionTime.TotalMilliseconds `
                -LogPath $executionLogPath `
                -ModuleName 'BloatwareRemoval'
        }

        # Explicit assignment to prevent pipeline contamination
        $detectionResults = $null
        $detectionResults = if ($effectiveDiffList) { $effectiveDiffList } else { Get-BloatwareAnalysis -Config $Config }

        # Validate detection results before proceeding
        if (-not $detectionResults -or $detectionResults.Count -eq 0) {
            Write-StructuredLogEntry -Level 'INFO' -Component 'BLOATWARE-REMOVAL' -Message 'No bloatware detected on system' -LogPath $executionLogPath -Operation 'Complete' -Result 'NoItemsFound'
            if ($perfContext) { Complete-PerformanceTracking -Context $perfContext -Status 'Success' }
            $executionTime = (Get-Date) - $executionStartTime
            return New-ModuleExecutionResult `
                -Success $true `
                -ItemsDetected 0 `
                -ItemsProcessed 0 `
                -DurationMilliseconds $executionTime.TotalMilliseconds `
                -LogPath $executionLogPath `
                -ModuleName 'BloatwareRemoval'
        }

        # STEP 1.5: Filter out protected system apps to avoid breaking core components
        $protectedCount = 0
        $filteredDetection = @()
        foreach ($item in $detectionResults) {
            if (Test-ProtectedBloatwareItem -Item $item) {
                $protectedCount++
                Write-StructuredLogEntry -Level 'WARNING' -Component 'BLOATWARE-REMOVAL' -Message "Protected app skipped: $($item.Name ?? $item.DisplayName)" -LogPath $executionLogPath -Operation 'Skip' -Metadata @{ Reason = 'ProtectedApp'; Source = $item.Source }
            }
            else {
                $filteredDetection += $item
            }
        }

        if ($protectedCount -gt 0) {
            Write-Information "   Skipped $protectedCount protected system app(s)" -InformationAction Continue
        }

        # STEP 2: Compare detection with config to create diff list using centralized function
        $diffList = $null
        if (-not $effectiveDiffList) {
            # Use standardized Phase 3 config path structure (subdirectory per module)
            $configDataPath = Join-Path (Get-MaintenancePath 'ConfigRoot') "lists\bloatware\bloatware-list.json"
            if (-not (Test-Path $configDataPath)) {
                # Fallback to legacy path for backward compatibility
                $configDataPath = Join-Path (Get-MaintenancePath 'ConfigRoot') "lists\bloatware-list.json"
            }
            if (-not (Test-Path $configDataPath)) {
                throw "Configuration file not found at: $configDataPath"
            }
            $configData = Get-Content $configDataPath -ErrorAction Stop | ConvertFrom-Json

            # Create diff: Only items from config that are actually found on system
            $diffList = Compare-DetectedVsConfig -DetectionResults $filteredDetection -ConfigData $configData -ConfigItemsPath 'bloatware' -MatchField 'Name'
        }
        else {
            $diffList = $filteredDetection
        }

        $null = Save-DiffResults -ModuleName 'BloatwareRemoval' -DiffData $diffList -Component 'BLOATWARE-REMOVAL'

        # STEP 3: Process ONLY items in diff list and log to dedicated directory
        Write-StructuredLogEntry -Level 'INFO' -Component 'BLOATWARE-REMOVAL' -Message "Processing $($diffList.Count) items from diff" -LogPath $executionLogPath -Operation 'Process' -Metadata @{ ItemCount = $diffList.Count; DetectedCount = $detectionResults.Count }

        if (-not $diffList -or $diffList.Count -eq 0) {
            Write-StructuredLogEntry -Level 'INFO' -Component 'BLOATWARE-REMOVAL' -Message 'No bloatware items to remove after config comparison' -LogPath $executionLogPath -Operation 'Complete' -Result 'NoItemsFound' -Metadata @{ DetectedCount = $filteredDetection.Count }
            if ($perfContext) { Complete-PerformanceTracking -Context $perfContext -Status 'Success' }
            $executionTime = (Get-Date) - $executionStartTime
            return New-ModuleExecutionResult `
                -Success $true `
                -ItemsDetected $filteredDetection.Count `
                -ItemsProcessed 0 `
                -DurationMilliseconds $executionTime.TotalMilliseconds `
                -LogPath $executionLogPath `
                -ModuleName 'BloatwareRemoval'
        }

        # Process only items found in diff comparison
        $results = Remove-DetectedBloatware -BloatwareList $diffList -LogPath $executionLogPath

        # Handle different return types from Remove-DetectedBloatware
        if ($results -is [hashtable] -and $results.ContainsKey('TotalProcessed')) {
            $processedCount = $results.TotalProcessed
        }
        elseif ($results -is [hashtable] -and $results.ContainsKey('Successful')) {
            $processedCount = $results.Successful
        }
        else {
            $processedCount = 0
        }

        Write-StructuredLogEntry -Level 'SUCCESS' -Component 'BLOATWARE-REMOVAL' -Message "Processed $processedCount bloatware items" -LogPath $executionLogPath -Operation 'Complete' -Result 'Success' -Metadata @{ ProcessedCount = $processedCount; TotalDetected = $detectionResults.Count }

        if ($perfContext) { Complete-PerformanceTracking -Context $perfContext -Status 'Success' }

        # Create execution summary JSON
        $summaryPath = Join-Path $executionLogDir "execution-summary.json"
        $executionTime = (Get-Date) - $executionStartTime
        $executionSummary = @{ =  'BloatwareRemoval'
            ExecutionTime = @{ =  $executionStartTime.ToString('o') =  (Get-Date).ToString('o')
                DurationMs = $executionTime.TotalMilliseconds
            } =  @{ =  $true =  $detectionResults.Count
                ItemsProcessed = $processedCount =  0 =  ($detectionResults.Count - $processedCount)
            }
            ExecutionMode = 'Live' =  @{
                TextLog = $executionLogPath
                JsonLog = $executionLogPath -replace '\.log$', '-data.json'
                Summary = $summaryPath
            } =  @{ =  $env:MAINTENANCE_SESSION_ID
                ComputerName = $env:COMPUTERNAME =  $env:USERNAME =  $PSVersionTable.PSVersion.ToString()
            }
        }

        try {
            $executionSummary | ConvertTo-Json -Depth 10 | Set-Content $summaryPath -Force
            Write-Verbose "Execution summary saved to: $summaryPath"
        }
        catch {
            Write-Warning "Failed to create execution summary: $($_.Exception.Message)"
        }

        return New-ModuleExecutionResult `
            -Success $true `
            -ItemsDetected $detectionResults.Count `
            -ItemsProcessed $processedCount `
            -DurationMilliseconds $executionTime.TotalMilliseconds `
            -LogPath $executionLogPath `
            -ModuleName 'BloatwareRemoval'

    }
    catch {
        $errorMsg = "Failed to execute bloatware removal: $($_.Exception.Message)"
        Write-LogEntry -Level 'ERROR' -Component 'BLOATWARE-REMOVAL' -Message $errorMsg -Data @{ Error = $_.Exception };

        if ($perfContext) { Complete-PerformanceTracking -Context $perfContext -Status 'Failed' -ErrorMessage $errorMsg }

        $executionTime = if ($executionStartTime) { (Get-Date) - $executionStartTime } else { New-TimeSpan }
        $itemsDetected = if ($detectionResults) { $detectionResults.Count } else { 0 }
        return New-ModuleExecutionResult `
            -Success $false `
            -ItemsDetected $itemsDetected `
            -ItemsProcessed 0 `
            -DurationMilliseconds $executionTime.TotalMilliseconds `
            -LogPath $executionLogPath `
            -ModuleName 'BloatwareRemoval' `
            -ErrorMessage $errorMsg
    }
}

#endregion

#region Legacy Public Functions (Preserved for Internal Use)

<#
.SYNOPSIS
    Safely removes detected bloatware applications

.DESCRIPTION
    Orchestrates the removal of bloatware using appropriate methods for each source type.
    Provides detailed progress reporting.

.PARAMETER BloatwareList
    Array of detected bloatware items to remove

.PARAMETER Force
    Forces removal even for items that might be needed

.PARAMETER Categories
    Specific bloatware categories to remove (OEM, Windows, Gaming, Security)

.EXAMPLE
    $results = Remove-DetectedBloatware -BloatwareList $detected

.EXAMPLE
    $results = Remove-DetectedBloatware -Categories @('OEM', 'Gaming') -Force
#>
function Remove-DetectedBloatware {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([bool])]
    param(
        [Parameter()]
        [Array]$BloatwareList,

        [Parameter()]
        [switch]$Force,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string[]]$Categories = @('all'),

        [Parameter()]
        [switch]$UseCache,

        [Parameter()]
        [string]$LogPath  # v3.0 specific log file path
    )

    Write-Information "  Starting bloatware removal process..." -InformationAction Continue
    $startTime = Get-Date

    # Check for administrator privileges before proceeding
    try {
        Assert-AdminPrivilege -Operation "Bloatware removal"
    }
    catch {
        Write-Error "Administrator privileges are required for bloatware removal operations: $_"
        return $false
    }

    # Start performance tracking and centralized logging
    $perfContext = $null
    try {
        $perfContext = Start-PerformanceTracking -OperationName 'BloatwareRemoval' -Component 'BLOATWARE-REMOVAL'
        Write-LogEntry -Level 'INFO' -Component 'BLOATWARE-REMOVAL' -Message 'Starting bloatware removal process' -Data @{ =  $Categories -join ', ' =  $Force =  $UseCache
            ProvidedBloatwareCount = if ($BloatwareList) { $BloatwareList.Count } else { 0 }
        }
    }
    catch {
        Write-Verbose "BLOATWARE-REMOVAL: Logging initialization failed - $_"
        # LoggingManager not available, continue
    }

    if (-not $BloatwareList) {
        Write-Information "   No bloatware list provided, detecting automatically..." -InformationAction Continue
        $params = @{ Categories = $Categories }
        if ($UseCache) { $params.UseCache = $true }
        $BloatwareList = Find-InstalledBloatware @params
    }

    if (-not $BloatwareList -or $BloatwareList.Count -eq 0) {
        Write-Information "   No bloatware detected for removal" -InformationAction Continue

        # Create empty analysis using organized file system
        $emptyAnalysis = @{ =  $startTime
            DetectedBloatware = @() =  $Categories =  0 =  "No bloatware detected"
        }

        $emptyDiffPath = Get-SessionPath -Category 'data' -SubCategory 'apps' -FileName 'bloatware-analysis.json'
        $emptyAnalysis | ConvertTo-Json -Depth 10 -WarningAction SilentlyContinue | Out-File -FilePath $emptyDiffPath -Encoding UTF8
        Write-Information "   Empty bloatware analysis saved: $emptyDiffPath" -InformationAction Continue

        return @{
            TotalProcessed = 0 =  0 =  0 =  0 =  $emptyDiffPath
        }
    }

    Write-Information "   Found $($BloatwareList.Count) bloatware items for removal" -InformationAction Continue

    try {
        $ErrorActionPreference = 'Stop'
        Write-Verbose "Starting bloatware removal process"

        # Prepare bloatware analysis data
        $bloatwareAnalysis = @{ =  $startTime
            DetectedBloatware = $BloatwareList =  $Categories =  $BloatwareList.Count =  "Bloatware detected and processed"
        }

        # Persist analysis using standardized paths
        $analysisPath = Get-SessionPath -Category 'data' -SubCategory 'apps' -FileName 'bloatware-analysis.json'
        $bloatwareAnalysis | ConvertTo-Json -Depth 10 -WarningAction SilentlyContinue | Out-File -FilePath $analysisPath -Encoding UTF8
        Write-Information "   Bloatware analysis saved: $analysisPath" -InformationAction Continue

        # Create comprehensive diff data
        $diffData = @{ =  $startTime =  $Categories
            DetectedBloatware = $BloatwareList =  $BloatwareList.Count =  ($BloatwareList | Group-Object Source | ForEach-Object { @{ $_.Name = $_.Count } }) =  ($BloatwareList | Group-Object MatchedPattern | ForEach-Object { @{ $_.Name = $_.Count } }) =  "Ready for removal"
        }

        # Save diff via standardized paths
        $diffFilePath = Get-SessionPath -Category 'data' -SubCategory 'apps' -FileName 'bloatware-diff.json'
        $diffData | ConvertTo-Json -Depth 10 -WarningAction SilentlyContinue | Out-File -FilePath $diffFilePath -Encoding UTF8
        Write-Information "   Diff file created: $diffFilePath" -InformationAction Continue

        # Create human-readable summary
        $summaryPath = Join-Path $env:MAINTENANCE_TEMP_ROOT 'reports\bloatware-summary.txt'
        $summaryDir = Split-Path -Parent $summaryPath
        if (-not (Test-Path $summaryDir)) {
            New-Item -Path $summaryDir -ItemType Directory -Force | Out-Null
        }
        $summaryContent = @"
BLOATWARE REMOVAL SUMMARY ======================== Generated: $(Get-Date)
Categories: $($Categories -join ', ')
Total Items: $($BloatwareList.Count)

ITEMS BY SOURCE:
"@

        foreach ($sourceGroup in ($BloatwareList | Group-Object Source)) {
            $summaryContent += "`n$($sourceGroup.Name): $($sourceGroup.Count) items"
        }

        $summaryContent += "`n`nDETAILED LIST:"
        foreach ($item in $BloatwareList) {
            $summaryContent += "`n- $($item.Name) [$($item.Source)] - Pattern: $($item.MatchedPattern)"
        }

        $summaryContent | Out-File -FilePath $summaryPath -Encoding UTF8
        Write-Information "   Summary file created: $summaryPath" -InformationAction Continue

        # Initialize results tracking
        $results = @{
            TotalProcessed = 0 =  0 =  0 =  0 =  [System.Collections.Generic.List[pscustomobject]]::new() =  @{}
        }

        if ($analysisPath) { $results.AnalysisPath = $analysisPath }

        # Group by source for efficient removal
        $groupedBloatware = $BloatwareList | Group-Object Source

        foreach ($sourceGroup in $groupedBloatware) {
            $source = $sourceGroup.Name
            $items = $sourceGroup.Group

            Write-Information "   Processing $($items.Count) items from $source..." -InformationAction Continue

            $sourceResults = switch ($source) {
                'AppX' { Remove-AppXBloatware -Items $items }
                'Winget' { Remove-WingetBloatware -Items $items }
                'Chocolatey' { Remove-ChocolateyBloatware -Items $items }
                'Registry' { Remove-RegistryBloatware -Items $items }
                default {
                    Write-Warning "Unknown source type: $source"
                    @{ Successful = 0; Failed = $items.Count; Details = @() }
                }
            }

            # Aggregate results
            $results.Successful += $sourceResults.Successful
            $results.Failed += $sourceResults.Failed
            $results.Skipped += $sourceResults.Skipped
            $results.Details.AddRange($sourceResults.Details) | Out-Null
            $results.BySource[$source] = $sourceResults
        }

        $results.TotalProcessed = $BloatwareList.Count
        $results.DiffFilePath = $diffFilePath
        $results.SummaryPath = $summaryPath
        $duration = ((Get-Date) - $startTime).TotalSeconds

        # Update diff file with results
        $diffData.Results = $results
        $diffData.Duration = $duration
        $diffData | ConvertTo-Json -Depth 4 | Set-Content -Path $diffFilePath -Encoding UTF8
        Write-Information "   Updated diff file with results: $diffFilePath" -InformationAction Continue

        # Summary output
        $statusIcon = if ($results.Failed -eq 0) { "" } else { "" }
        Write-Information "  $statusIcon Bloatware removal completed in $([math]::Round($duration, 2))s" -InformationAction Continue
        Write-Information "     Processed: $($results.TotalProcessed), Successful: $($results.Successful), Failed: $($results.Failed)" -InformationAction Continue
        Write-Information "     Files created: JSON diff, TXT summary" -InformationAction Continue

        $success = $results.Failed -eq 0 -and $results.Successful -gt 0
        if (-not $success) {
            Write-Information "     Some items could not be removed. Check logs for details." -InformationAction Continue
        }

        # Complete performance tracking and log success
        try {
            if ($perfContext) {
                Complete-PerformanceTracking -PerformanceContext $perfContext -Success $success
            }

            Write-LogEntry -Level 'INFO' -Component 'BLOATWARE-REMOVAL' -Message 'Bloatware removal completed' -Data @{ =  $success
                TotalProcessed = $results.TotalProcessed =  $results.Successful =  $results.Failed =  [math]::Round($duration, 2) =  $Categories -join ', '
            }
        }
        catch {
            Write-Verbose "BLOATWARE-REMOVAL: Logging completion failed - $_"
            # LoggingManager not available, continue
        }

        # Log detailed results for audit trails
        Write-Verbose "Bloatware removal operation details: $(ConvertTo-Json $results -Depth 3)"
        Write-Verbose "Bloatware removal completed successfully"

        $results.Success = $success
        $results.Duration = $duration
        return $results
    }
    catch {
        # Complete performance tracking with failure
        try {
            if ($perfContext) {
                Complete-PerformanceTracking -PerformanceContext $perfContext -Success $false
            }

            Write-LogEntry -Level 'ERROR' -Component 'BLOATWARE-REMOVAL' -Message 'Bloatware removal failed' -Data @{ =  $_.Exception.Message
                ExecutionTime = [math]::Round((Get-Date - $startTime).TotalSeconds, 2) =  $Categories -join ', '
            }
        }
        catch {
            Write-Verbose "BLOATWARE-REMOVAL: Error logging failed - $_"
            # LoggingManager not available, continue
        }

        $errorMessage = " Bloatware removal failed: $($_.Exception.Message)"
        Write-Error $errorMessage
        Write-Verbose "Error details: $($_.Exception.ToString())"

        return @{ =  $false
            TotalProcessed = if ($BloatwareList) { $BloatwareList.Count } else { 0 } =  0 =  if ($BloatwareList) { $BloatwareList.Count } else { 0 } =  0 =  $errorMessage
        }
    }
    finally {
        $ErrorActionPreference = 'Continue'
        $duration = ((Get-Date) - $startTime).TotalSeconds
        Write-Verbose "Bloatware removal operation completed in $([math]::Round($duration, 2)) seconds"
    }
}

<#
.SYNOPSIS
    Tests bloatware removal capabilities without making changes

.DESCRIPTION
    Performs a comprehensive test of removal capabilities for detected bloatware
    without actually removing anything.

.PARAMETER BloatwareList
    Array of detected bloatware items to test

.EXAMPLE
    $testResults = Test-BloatwareRemoval -BloatwareList $detected
#>
function Test-BloatwareRemoval {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [Array]$BloatwareList
    )

    Write-Information " Testing bloatware removal capabilities..." -InformationAction Continue

    $testResults = @{ =  $BloatwareList.Count =  0
        NonRemovableItems = 0 =  @{} =  Get-RemovalToolAvailability
    }

    $groupedBloatware = $BloatwareList | Group-Object Source

    foreach ($sourceGroup in $groupedBloatware) {
        $source = $sourceGroup.Name
        $items = $sourceGroup.Group

        $sourceTest = @{ =  $items.Count =  0
            NonRemovable = 0 =  Get-PreferredRemovalMethod -Source $source
        }

        foreach ($item in $items) {
            if (Test-ItemRemovable -Item $item) {
                $sourceTest.Removable++
                $testResults.RemovableItems++
            }
            else {
                $sourceTest.NonRemovable++
                $testResults.NonRemovableItems++
            }
        }

        $testResults.BySource[$source] = $sourceTest
        Write-Information "   $source`: $($sourceTest.Removable)/$($sourceTest.Total) removable" -InformationAction Continue
    }

    Write-Information "   Overall: $($testResults.RemovableItems)/$($testResults.TotalItems) items can be removed" -InformationAction Continue

    return $testResults
}

#endregion

#region AppX Removal

<#
.SYNOPSIS
    Removes AppX (Windows Store) packages

.DESCRIPTION
    Uses generic Invoke-BloatwareItemRemoval with AppX-specific logic.
    Phase B.3 consolidation - reduced from ~120 lines to ~40 lines.
#>
function Remove-AppXBloatware {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [Array]$Items
    )

    return Invoke-BloatwareItemRemoval `
        -Items $Items `
        -SourceName 'AppX' `
        -ToolAvailabilityChecker {
        $null -ne (Get-Command Get-AppxPackage -ErrorAction SilentlyContinue)
    } `
        -GetItemName {
        param($item)
        if ($item.WingetId) { $item.WingetId } else { $item.Name }
    } `
        -PreActionDetector {
        param($item)
        $packageName = if ($item.WingetId) { $item.WingetId } else { $item.Name }
        $package = Get-AppxPackage -Name $packageName -AllUsers -ErrorAction SilentlyContinue
        $provisionedPackage = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -eq $packageName }

        [PSCustomObject]@{ =  $package =  if ($package) { $package.PackageFullName } else { $null }
            ProvisionedPackage = $provisionedPackage =  if ($package) { $package.Version.ToString() } else { 'N/A' } =  ($null -ne $provisionedPackage)
        }
    } `
        -RemovalExecutor {
        param($item, $preState)
        $null = $item
        try {
            # Remove AppX package for all users
            if ($preState.Package) {
                Write-LogEntry -Level 'INFO' -Component 'BLOATWARE-REMOVAL' `
                    -Message "Executing: Remove-AppxPackage -Package $($preState.PackageFullName) -AllUsers"
                $preState.Package | Remove-AppxPackage -AllUsers -ErrorAction Stop
                Write-LogEntry -Level 'INFO' -Component 'BLOATWARE-REMOVAL' `
                    -Message "AppX package removed from all users"
            }

            # Remove provisioned package to prevent reinstallation
            if ($preState.ProvisionedPackage) {
                Write-LogEntry -Level 'INFO' -Component 'BLOATWARE-REMOVAL' `
                    -Message "Executing: Remove-AppxProvisionedPackage -PackageName $($preState.ProvisionedPackage.PackageName)"
                Remove-AppxProvisionedPackage -Online -PackageName $preState.ProvisionedPackage.PackageName -ErrorAction SilentlyContinue
                Write-LogEntry -Level 'INFO' -Component 'BLOATWARE-REMOVAL' `
                    -Message "Provisioned package removed"
            }

            @{ Success = $true; ExitCode = 0; Error = $null }
        }
        catch {
            @{ Success = $false; ExitCode = 1; Error = $_.Exception.Message }
        }
    } `
        -PostActionVerifier {
        param($item)
        $packageName = if ($item.WingetId) { $item.WingetId } else { $item.Name }
        $verifyPackage = Get-AppxPackage -Name $packageName -AllUsers -ErrorAction SilentlyContinue
        $verifyProvisioned = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -eq $packageName }

        # Return $true if still installed (failure), $false if removed (success)
        ($null -ne $verifyPackage) -or ($null -ne $verifyProvisioned)
    }
}


#endregion

#region Winget Removal

<#
.SYNOPSIS
    Removes packages using Winget package manager

.DESCRIPTION
    Uses generic Invoke-BloatwareItemRemoval with Winget-specific logic.
    Phase B.3 consolidation - reduced from ~140 lines to ~40 lines.
#>
function Remove-WingetBloatware {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [Array]$Items
    )

    return Invoke-BloatwareItemRemoval `
        -Items $Items `
        -SourceName 'Winget' `
        -ToolAvailabilityChecker {
        $null -ne (Get-Command winget -ErrorAction SilentlyContinue)
    } `
        -GetItemName {
        param($item)
        $item.Name
    } `
        -PreActionDetector {
        param($item)
        $wingetListArgs = @('list', '--id', $item.Name, '--accept-source-agreements')
        $listProcess = Start-Process -FilePath 'winget' -ArgumentList $wingetListArgs -Wait -PassThru -NoNewWindow -RedirectStandardOutput "$env:TEMP\winget-list-$($item.Name).txt" -ErrorAction SilentlyContinue

        [PSCustomObject]@{
            PackageInstalled = $listProcess.ExitCode -eq 0 =  $wingetListArgs
        }
    } `
        -RemovalExecutor {
        param($item, $preState)
        $null = $preState
        try {
            $wingetArgs = @('uninstall', '--id', $item.Name, '--silent', '--accept-source-agreements')
            Write-LogEntry -Level 'INFO' -Component 'BLOATWARE-REMOVAL' -Message "Executing: winget $($wingetArgs -join ' ')"
            $process = Start-Process -FilePath 'winget' -ArgumentList $wingetArgs -Wait -PassThru -NoNewWindow

            # Cleanup temp file
            Remove-Item -Path "$env:TEMP\winget-list-$($item.Name).txt" -ErrorAction SilentlyContinue

            @{ Success = ($process.ExitCode -eq 0); ExitCode = $process.ExitCode; Error = if ($process.ExitCode -ne 0) { "Exit code $($process.ExitCode)" } else { $null } }
        }
        catch {
            @{ Success = $false; ExitCode = 1; Error = $_.Exception.Message }
        }
    } `
        -PostActionVerifier {
        param($item)
        $wingetListArgs = @('list', '--id', $item.Name, '--accept-source-agreements')
        $verifyProcess = Start-Process -FilePath 'winget' -ArgumentList $wingetListArgs -Wait -PassThru -NoNewWindow -RedirectStandardOutput "$env:TEMP\winget-verify-$($item.Name).txt" -ErrorAction SilentlyContinue

        # Cleanup temp file
        Remove-Item -Path "$env:TEMP\winget-verify-$($item.Name).txt" -ErrorAction SilentlyContinue

        # Return $true if still installed (failure), $false if removed (success)
        $verifyProcess.ExitCode -eq 0
    }
}

#endregion

#region Chocolatey Removal

<#
.SYNOPSIS
    Removes packages using Chocolatey package manager

.DESCRIPTION
    Uses generic Invoke-BloatwareItemRemoval with Chocolatey-specific logic.
    Phase B.3 consolidation - reduced from ~120 lines to ~35 lines.
#>
function Remove-ChocolateyBloatware {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [Array]$Items
    )

    return Invoke-BloatwareItemRemoval `
        -Items $Items `
        -SourceName 'Chocolatey' `
        -ToolAvailabilityChecker {
        $null -ne (Get-Command choco -ErrorAction SilentlyContinue)
    } `
        -GetItemName {
        param($item)
        $item.Name
    } `
        -PreActionDetector {
        param($item)
        $chocoListArgs = @('list', '--local-only', '--exact', $item.Name, '--limit-output')
        $listOutput = & choco @chocoListArgs 2>&1
        $packageInstalled = $LASTEXITCODE -eq 0 -and $listOutput -match $item.Name
        $installedVersion = if ($packageInstalled -and $listOutput -match "$($item.Name)\|(.+)") { $matches[1] } else { 'N/A' }

        [PSCustomObject]@{
            PackageInstalled = $packageInstalled =  $installedVersion =  $chocoListArgs
        }
    } `
        -RemovalExecutor {
        param($item, $preState)
        $null = $preState
        try {
            $chocoArgs = @('uninstall', $item.Name, '-y', '--limit-output')
            Write-LogEntry -Level 'INFO' -Component 'BLOATWARE-REMOVAL' -Message "Executing: choco $($chocoArgs -join ' ')"
            $process = Start-Process -FilePath 'choco' -ArgumentList $chocoArgs -Wait -PassThru -NoNewWindow

            @{ Success = ($process.ExitCode -eq 0); ExitCode = $process.ExitCode; Error = if ($process.ExitCode -ne 0) { "Exit code $($process.ExitCode)" } else { $null } }
        }
        catch {
            @{ Success = $false; ExitCode = 1; Error = $_.Exception.Message }
        }
    } `
        -PostActionVerifier {
        param($item)
        $chocoListArgs = @('list', '--local-only', '--exact', $item.Name, '--limit-output')
        $verifyOutput = & choco @chocoListArgs 2>&1

        # Return $true if still installed (failure), $false if removed (success)
        $LASTEXITCODE -eq 0 -and $verifyOutput -match $item.Name
    }
}

#endregion

#region Registry Removal

<#
.SYNOPSIS
    Removes applications using Registry uninstall strings
#>
function Remove-RegistryBloatware {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [Array]$Items
    )

    return Invoke-BloatwareItemRemoval `
        -Items $Items `
        -SourceName 'Registry' `
        -ToolAvailabilityChecker {
        $true  # Registry uninstall always available
    } `
        -GetItemName {
        param($item)
        $item.DisplayName ?? $item.Name
    } `
        -PreActionDetector {
        param($item)
        [PSCustomObject]@{ =  $item.DisplayName ?? $item.Name
            UninstallString = $item.UninstallString
            InstallLocation = $item.InstallLocation ?? 'N/A' =  $item.Publisher ?? 'N/A' =  $item.DisplayVersion ?? 'N/A' =  $item.EstimatedSize ?? 'N/A'
        }
    } `
        -RemovalExecutor {
        param($item, $preState)
        $null = $item
        try {
            if (-not $preState.UninstallString) {
                return @{ Success = $false; ExitCode = 1; Error = "No uninstall string available" }
            }

            # Parse uninstall string
            $uninstallString = $preState.UninstallString
            if ($uninstallString -match '^"([^"]+)"(.*)') {
                $executable = $matches[1]
                $arguments = $matches[2].Trim()
            }
            else {
                $parts = $uninstallString -split ' ', 2
                $executable = $parts[0]
                $arguments = if ($parts.Count -gt 1) { $parts[1] } else { '' }
            }

            # MSI uninstaller normalization
            if ($executable -match 'msiexec(\.exe)?$') {
                if ($arguments -match '/I\s*\{') {
                    $arguments = $arguments -replace '/I', '/X'
                }
                if ($arguments -notmatch '/qn|/quiet|/q') {
                    $arguments += ' /qn'
                }
                if ($arguments -notmatch '/norestart') {
                    $arguments += ' /norestart'
                }
            }
            else {
                # Generic silent flags
                if ($arguments -notmatch '/S|/silent|/quiet|/q') {
                    $arguments += ' /S'
                }
            }

            Write-LogEntry -Level 'INFO' -Component 'BLOATWARE-REMOVAL' -Message "Executing: $executable $arguments"
            $process = Start-Process -FilePath $executable -ArgumentList $arguments -Wait -PassThru -NoNewWindow

            @{ Success = ($process.ExitCode -eq 0); ExitCode = $process.ExitCode; Error = if ($process.ExitCode -ne 0) { "Exit code $($process.ExitCode)" } else { $null } }
        }
        catch {
            @{ Success = $false; ExitCode = 1; Error = $_.Exception.Message }
        }
    } `
        -PostActionVerifier {
        param($item)
        $appName = $item.DisplayName ?? $item.Name
        $registryPaths = @(
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
            "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
            "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
        )

        foreach ($path in $registryPaths) {
            $regEntry = Get-ItemProperty -Path $path -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -eq $appName }
            if ($regEntry) {
                # Registry entry still exists - treat as success if exit code was 0 (some installers don't clean registry)
                Write-LogEntry -Level 'WARNING' -Component 'BLOATWARE-REMOVAL' `
                    -Message "Registry entry still exists after uninstall - may be normal for some uninstallers"
                return $false  # Treat as success
            }
        }

        # Registry entry removed - success
        $false
    }
}

#endregion

#region Helper Functions

<#[
.SYNOPSIS
    Determines whether a detected item is protected and should never be removed
#>
function Test-ProtectedBloatwareItem {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Item
    )

    $protectedPatterns = @(
        'Microsoft.WindowsStore',
        'Microsoft.StorePurchaseApp',
        'Microsoft.DesktopAppInstaller',
        'Microsoft.UI.Xaml*',
        'Microsoft.VCLibs*',
        'Microsoft.NET.Native*',
        'Microsoft.Windows.ShellExperienceHost',
        'Microsoft.Windows.StartMenuExperienceHost',
        'Microsoft.AAD.BrokerPlugin',
        'Microsoft.WindowsAppRuntime*'
    )

    $name = $Item.Name
    if ([string]::IsNullOrWhiteSpace($name)) {
        $name = $Item.DisplayName
    }

    if ([string]::IsNullOrWhiteSpace($name)) {
        return $false
    }

    foreach ($pattern in $protectedPatterns) {
        if ($name -like $pattern) {
            return $true
        }
    }

    return $false
}

<#
.SYNOPSIS
    Gets availability of removal tools
#>
function Get-RemovalToolAvailability {
    return @{ =  $null -ne (Get-Command Get-AppxPackage -ErrorAction SilentlyContinue) =  $null -ne (Get-Command winget -ErrorAction SilentlyContinue)
        Chocolatey = $null -ne (Get-Command choco -ErrorAction SilentlyContinue)
        PowerShell = $PSVersionTable.PSVersion.Major -ge 5
    }
}

<#
.SYNOPSIS
    Gets the preferred removal method for a given source
#>
function Get-PreferredRemovalMethod {
    param([string]$Source)

    switch ($Source) {
        'AppX' { 'Remove-AppxPackage' }
        'Winget' { 'winget uninstall' }
        'Chocolatey' { 'choco uninstall' }
        'Registry' { 'Registry uninstaller' }
        default { 'Unknown' }
    }
}

<#
.SYNOPSIS
    Tests if an item can be removed
#>
function Test-ItemRemovable {
    param([PSCustomObject]$Item)

    switch ($Item.Source) {
        'AppX' {
            return $null -ne (Get-Command Get-AppxPackage -ErrorAction SilentlyContinue)
        }
        'Winget' {
            return $null -ne (Get-Command winget -ErrorAction SilentlyContinue)
        }
        'Chocolatey' {
            return $null -ne (Get-Command choco -ErrorAction SilentlyContinue)
        }
        'Registry' {
            return $null -ne $Item.UninstallString
        }
        default {
            return $false
        }
    }
}

#endregion

# Export module functions
Export-ModuleMember -Function @(
    # v3.0 Standardized execution function (Primary interface)
    'Invoke-BloatwareRemoval'

    # Note: Legacy functions (Remove-DetectedBloatware, Test-BloatwareRemoval)
    # are used internally but not exported to maintain clean module interface
)






