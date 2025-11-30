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
    Standardized entry point that implements the Type2 → Type1 flow:
    1. Calls BloatwareDetection (Type1) to detect bloatware
    2. Validates findings and logs results
    3. Executes removal actions (Type2) based on DryRun mode
    4. Returns standardized results for ReportGeneration

.PARAMETER Config
    Main configuration object from orchestrator

.PARAMETER DryRun
    When specified, simulates removal without making changes

.EXAMPLE
    $result = Invoke-BloatwareRemoval -Config $MainConfig -DryRun

.EXAMPLE
    $result = Invoke-BloatwareRemoval -Config $MainConfig
#>
function Invoke-BloatwareRemoval {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Config,
        
        [Parameter()]
        [switch]$DryRun
    )
    
    # Performance tracking
    $perfContext = $null
    try {
        $perfContext = Start-PerformanceTracking -OperationName 'BloatwareRemoval' -Component 'BLOATWARE-REMOVAL'
    }
    catch {
        # CoreInfrastructure not available, continue without performance tracking
    }
    
    try {
        # Track execution duration for v3.0 compliance
        $executionStartTime = Get-Date
        
        # Validate temp_files structure (FIX #12)
        if (-not (Test-TempFilesStructure)) {
            throw "Failed to initialize temp_files directory structure"
        }
        
        # STEP 1: Always run Type1 detection first and save to temp_files/data/
        $executionLogDir = Join-Path (Get-MaintenancePath 'TempRoot') "logs\bloatware-removal"
        New-Item -Path $executionLogDir -ItemType Directory -Force | Out-Null
        $executionLogPath = Join-Path $executionLogDir "execution.log"
        
        Write-StructuredLogEntry -Level 'INFO' -Component 'BLOATWARE-REMOVAL' -Message 'Starting bloatware detection' -LogPath $executionLogPath -Operation 'Detect' -Metadata @{ DryRun = $DryRun.IsPresent }
        # Explicit assignment to prevent pipeline contamination
        $detectionResults = $null
        $detectionResults = Get-BloatwareAnalysis -Config $Config
        
        # STEP 2: Compare detection with config to create diff list using centralized function
        # Use standardized config path structure
        $configDataPath = Join-Path (Get-MaintenancePath 'ConfigRoot') "lists\bloatware-list.json"
        $configData = Get-Content $configDataPath | ConvertFrom-Json
        
        # Create diff: Only items from config that are actually found on system
        $diffList = Compare-DetectedVsConfig -DetectionResults $detectionResults -ConfigData $configData -ConfigItemsPath 'bloatware' -MatchField 'Name'
        
        $diffPath = Join-Path (Get-MaintenancePath 'TempRoot') "temp\bloatware-diff.json"
        $diffList | ConvertTo-Json -Depth 20 -WarningAction SilentlyContinue | Set-Content $diffPath
        
        # STEP 3: Process ONLY items in diff list and log to dedicated directory
        Write-StructuredLogEntry -Level 'INFO' -Component 'BLOATWARE-REMOVAL' -Message "Processing $($diffList.Count) items from diff" -LogPath $executionLogPath -Operation 'Process' -Metadata @{ ItemCount = $diffList.Count; DetectedCount = $detectionResults.Count }
        
        if (-not $diffList -or $diffList.Count -eq 0) {
            Write-StructuredLogEntry -Level 'INFO' -Component 'BLOATWARE-REMOVAL' -Message 'No bloatware items to remove after config comparison' -LogPath $executionLogPath -Operation 'Complete' -Result 'NoItemsFound' -Metadata @{ DetectedCount = $detectionResults.Count }
            if ($perfContext) { Complete-PerformanceTracking -Context $perfContext -Status 'Success' }
            $executionTime = (Get-Date) - $executionStartTime
            return @{ 
                Success        = $true
                ItemsDetected  = $detectionResults.Count
                ItemsProcessed = 0
                Duration       = $executionTime.TotalMilliseconds
            }
        }
        
        if ($DryRun) {
            Write-StructuredLogEntry -Level 'INFO' -Component 'BLOATWARE-REMOVAL' -Message " DRY-RUN: Would process $($diffList.Count) bloatware items" -LogPath $executionLogPath -Operation 'Simulate' -Metadata @{ DryRun = $true; ItemCount = $diffList.Count }
            $processedCount = 0
        }
        else {
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
        }
        
        if ($perfContext) { Complete-PerformanceTracking -Context $perfContext -Status 'Success' }
        
        # Create execution summary JSON
        $summaryPath = Join-Path $executionLogDir "execution-summary.json"
        $executionTime = (Get-Date) - $executionStartTime
        $executionSummary = @{
            ModuleName    = 'BloatwareRemoval'
            ExecutionTime = @{
                Start      = $executionStartTime.ToString('o')
                End        = (Get-Date).ToString('o')
                DurationMs = $executionTime.TotalMilliseconds
            }
            Results       = @{
                Success        = $true
                ItemsDetected  = $detectionResults.Count
                ItemsProcessed = $processedCount
                ItemsFailed    = 0
                ItemsSkipped   = ($detectionResults.Count - $processedCount)
            }
            ExecutionMode = if ($DryRun) { 'DryRun' } else { 'Live' }
            LogFiles      = @{
                TextLog = $executionLogPath
                JsonLog = $executionLogPath -replace '\.log$', '-data.json'
                Summary = $summaryPath
            }
            SessionInfo   = @{
                SessionId    = $env:MAINTENANCE_SESSION_ID
                ComputerName = $env:COMPUTERNAME
                UserName     = $env:USERNAME
                PSVersion    = $PSVersionTable.PSVersion.ToString()
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
            -ModuleName 'BloatwareRemoval' `
            -DryRun $DryRun.IsPresent
        
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
    Supports dry run mode and provides detailed progress reporting.

.PARAMETER BloatwareList
    Array of detected bloatware items to remove

.PARAMETER DryRun
    When specified, simulates removal without making changes

.PARAMETER Force
    Forces removal even for items that might be needed

.PARAMETER Categories
    Specific bloatware categories to remove (OEM, Windows, Gaming, Security)

.EXAMPLE
    $results = Remove-DetectedBloatware -BloatwareList $detected -DryRun

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
        [switch]$DryRun,

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
        Write-LogEntry -Level 'INFO' -Component 'BLOATWARE-REMOVAL' -Message 'Starting bloatware removal process' -Data @{
            Categories             = $Categories -join ', '
            DryRun                 = $DryRun
            Force                  = $Force
            UseCache               = $UseCache
            ProvidedBloatwareCount = if ($BloatwareList) { $BloatwareList.Count } else { 0 }
        }
    }
    catch {
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
        $emptyAnalysis = @{
            Timestamp         = $startTime
            DetectedBloatware = @()
            Categories        = $Categories
            TotalItems        = 0
            Status            = "No bloatware detected"
        }

        $emptyDiffPath = Save-OrganizedFile -Data $emptyAnalysis -FileType 'Data' -Category 'apps' -FileName 'bloatware-analysis' -Format 'JSON'
        if ($emptyDiffPath) {
            Write-Information "   Empty bloatware analysis saved: $emptyDiffPath" -InformationAction Continue
        }

        return @{
            TotalProcessed = 0
            Successful     = 0
            Failed         = 0
            Skipped        = 0
            DryRun         = $DryRun.IsPresent
            DiffFilePath   = $emptyDiffPath
        }
    }

    Write-Information "   Found $($BloatwareList.Count) bloatware items for removal" -InformationAction Continue

    try {
        $ErrorActionPreference = 'Stop' 
        Write-Verbose "Starting bloatware removal process"

        # Prepare bloatware analysis data
        $bloatwareAnalysis = @{
            Timestamp         = $startTime
            DetectedBloatware = $BloatwareList
            Categories        = $Categories
            TotalItems        = $BloatwareList.Count
            Status            = "Bloatware detected and processed"
        }

        # Persist analysis using organized file system
        $analysisPath = Save-OrganizedFile -Data $bloatwareAnalysis -FileType 'Data' -Category 'apps' -FileName 'bloatware-analysis' -Format 'JSON'
        if ($analysisPath) {
            Write-Information "   Bloatware analysis saved: $analysisPath" -InformationAction Continue
        }

        # Create comprehensive diff data
        $diffData = @{
            Timestamp         = $startTime
            Categories        = $Categories
            DetectedBloatware = $BloatwareList
            TotalItems        = $BloatwareList.Count
            BySource          = ($BloatwareList | Group-Object Source | ForEach-Object { @{ $_.Name = $_.Count } })
            ByCategory        = ($BloatwareList | Group-Object MatchedPattern | ForEach-Object { @{ $_.Name = $_.Count } })
            Status            = "Ready for removal"
            DryRun            = $DryRun.IsPresent
        }

        # Save diff via organized file system
        $diffFilePath = Save-OrganizedFile -Data $diffData -FileType 'Data' -Category 'apps' -FileName 'bloatware-diff' -Format 'JSON'
        if ($diffFilePath) {
            Write-Information "   Diff file created: $diffFilePath" -InformationAction Continue
        }

        # Create human-readable summary in organized file system
        $summaryPath = Get-OrganizedFilePath -FileType 'Report' -Category 'apps' -FileName 'bloatware-summary.txt'
        $summaryContent = @"
BLOATWARE REMOVAL SUMMARY
========================
Generated: $(Get-Date)
Categories: $($Categories -join ', ')
Total Items: $($BloatwareList.Count)
Dry Run: $($DryRun.IsPresent)

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

        if ($DryRun) {
            Write-Information "   DRY RUN MODE - No changes will be made" -InformationAction Continue
        }

        # Initialize results tracking
        $results = @{
            TotalProcessed = 0
            Successful     = 0
            Failed         = 0
            Skipped        = 0
            DryRun         = $DryRun.IsPresent
            Details        = [System.Collections.Generic.List[pscustomobject]]::new()
            BySource       = @{}
        }

        if ($analysisPath) { $results.AnalysisPath = $analysisPath }

        # Group by source for efficient removal
        $groupedBloatware = $BloatwareList | Group-Object Source

        foreach ($sourceGroup in $groupedBloatware) {
            $source = $sourceGroup.Name
            $items = $sourceGroup.Group

            Write-Information "   Processing $($items.Count) items from $source..." -InformationAction Continue

            $sourceResults = switch ($source) {
                'AppX' { Remove-AppXBloatware -Items $items -DryRun:$DryRun }
                'Winget' { Remove-WingetBloatware -Items $items -DryRun:$DryRun }
                'Chocolatey' { Remove-ChocolateyBloatware -Items $items -DryRun:$DryRun }
                'Registry' { Remove-RegistryBloatware -Items $items -DryRun:$DryRun }
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
            
            Write-LogEntry -Level 'INFO' -Component 'BLOATWARE-REMOVAL' -Message 'Bloatware removal completed' -Data @{
                Success        = $success
                TotalProcessed = $results.TotalProcessed
                Successful     = $results.Successful
                Failed         = $results.Failed
                ExecutionTime  = [math]::Round($duration, 2)
                Categories     = $Categories -join ', '
            }
        }
        catch {
            # LoggingManager not available, continue
        }
        
        # Log detailed results for audit trails
        Write-Verbose "Bloatware removal operation details: $(ConvertTo-Json $results -Depth 3)"
        Write-Verbose "Bloatware removal completed successfully"
        
        return $success
    }
    catch {
        # Complete performance tracking with failure
        try {
            if ($perfContext) {
                Complete-PerformanceTracking -PerformanceContext $perfContext -Success $false
            }
            
            Write-LogEntry -Level 'ERROR' -Component 'BLOATWARE-REMOVAL' -Message 'Bloatware removal failed' -Data @{
                Error         = $_.Exception.Message
                ExecutionTime = [math]::Round((Get-Date - $startTime).TotalSeconds, 2)
                Categories    = $Categories -join ', '
            }
        }
        catch {
            # LoggingManager not available, continue
        }
        
        $errorMessage = " Bloatware removal failed: $($_.Exception.Message)"
        Write-Error $errorMessage
        Write-Verbose "Error details: $($_.Exception.ToString())"
        
        # Type 2 module returns boolean for failure
        return $false
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

    $testResults = @{
        TotalItems        = $BloatwareList.Count
        RemovableItems    = 0
        NonRemovableItems = 0
        BySource          = @{}
        ToolAvailability  = Get-RemovalToolAvailability
    }

    $groupedBloatware = $BloatwareList | Group-Object Source

    foreach ($sourceGroup in $groupedBloatware) {
        $source = $sourceGroup.Name
        $items = $sourceGroup.Group

        $sourceTest = @{
            Total        = $items.Count
            Removable    = 0
            NonRemovable = 0
            Method       = Get-PreferredRemovalMethod -Source $source
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
#>
function Remove-AppXBloatware {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [Array]$Items,

        [Parameter()]
        [switch]$DryRun
    )

    $results = @{
        Successful = 0
        Failed     = 0
        Skipped    = 0
        Details    = [List[PSCustomObject]]::new()
    }

    if (-not (Get-Command Get-AppxPackage -ErrorAction SilentlyContinue)) {
        Write-Verbose "AppX cmdlets not available - skipping AppX package removals"
        $results.Skipped = $Items.Count
        return $results
    }

    foreach ($item in $Items) {
        $packageName = $item.Name
        $operationStart = Get-Date
        $result = @{
            Name    = $packageName
            Source  = 'AppX'
            Success = $false
            Action  = if ($DryRun) { 'Simulated' } else { 'Removed' }
            Error   = $null
        }

        try {
            # Enhanced logging: Pre-action state detection
            $package = Get-AppxPackage -Name $packageName -AllUsers -ErrorAction SilentlyContinue
            $provisionedPackage = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -eq $packageName }
            
            $preActionState = @{
                PackageFound    = ($null -ne $package)
                PackageFullName = if ($package) { $package.PackageFullName } else { 'N/A' }
                Version         = if ($package) { $package.Version } else { 'N/A' }
                IsProvisioned   = ($null -ne $provisionedPackage)
                InstallLocation = if ($package) { $package.InstallLocation } else { 'N/A' }
            }
            
            Write-OperationStart -Component 'BLOATWARE-REMOVAL' -Operation 'Remove' -Target $packageName -AdditionalInfo "AppX Package - Version: $($preActionState.Version), Provisioned: $($preActionState.IsProvisioned)"
            
            if ($DryRun) {
                Write-Information "    [DRY RUN] Would remove AppX package: $packageName" -InformationAction Continue
                Write-OperationSkipped -Component 'BLOATWARE-REMOVAL' -Operation 'Remove' -Target $packageName -Reason 'DryRun mode enabled'
                $result.Success = $true
            }
            else {
                Write-Information "     Removing AppX package: $packageName" -InformationAction Continue

                # Try to remove for all users first
                if ($package) {
                    Write-LogEntry -Level 'INFO' -Component 'BLOATWARE-REMOVAL' -Message "Executing: Remove-AppxPackage -Package $($package.PackageFullName) -AllUsers"
                    $package | Remove-AppxPackage -ErrorAction Stop
                    Write-LogEntry -Level 'INFO' -Component 'BLOATWARE-REMOVAL' -Message "AppX package removed from all users: $packageName"
                }

                # Remove provisioned package to prevent reinstallation
                if ($provisionedPackage) {
                    Write-LogEntry -Level 'INFO' -Component 'BLOATWARE-REMOVAL' -Message "Executing: Remove-AppxProvisionedPackage -PackageName $($provisionedPackage.PackageName)"
                    Remove-AppxProvisionedPackage -Online -PackageName $provisionedPackage.PackageName -ErrorAction SilentlyContinue
                    Write-LogEntry -Level 'INFO' -Component 'BLOATWARE-REMOVAL' -Message "Provisioned package removed: $packageName"
                }
                
                # Post-action verification
                Write-LogEntry -Level 'INFO' -Component 'BLOATWARE-REMOVAL' -Operation 'Verify' -Target $packageName -Message 'Verifying AppX package removal'
                
                $verifyPackage = Get-AppxPackage -Name $packageName -AllUsers -ErrorAction SilentlyContinue
                $verifyProvisioned = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -eq $packageName }
                
                if (-not $verifyPackage -and -not $verifyProvisioned) {
                    $operationDuration = ((Get-Date) - $operationStart).TotalSeconds
                    
                    # Log successful verification
                    Write-OperationSuccess -Component 'BLOATWARE-REMOVAL' -Operation 'Verify' -Target $packageName -Metrics @{
                        PackageStillPresent     = $false
                        ProvisionedStillPresent = $false
                        VerificationPassed      = $true
                    }
                    
                    # Log successful removal
                    Write-OperationSuccess -Component 'BLOATWARE-REMOVAL' -Operation 'Remove' -Target $packageName -Metrics @{
                        Duration           = $operationDuration
                        PackageRemoved     = $true
                        ProvisionedRemoved = ($null -ne $provisionedPackage)
                    }
                    $result.Success = $true
                    Write-Information "       Successfully removed AppX package: $packageName (${operationDuration}s)" -InformationAction Continue
                }
                else {
                    # Log failed verification
                    Write-OperationFailure -Component 'BLOATWARE-REMOVAL' -Operation 'Verify' -Target $packageName -Error (New-Object Exception("Package still present after removal attempt"))
                    throw "Verification failed: Package still present after removal"
                }
            }

            $results.Successful++
        }
        catch {
            $result.Error = $_.Exception.Message
            $results.Failed++
            Write-OperationFailure -Component 'BLOATWARE-REMOVAL' -Operation 'Remove' -Target $packageName -Error $_
            Write-Warning "Failed to remove AppX package ${packageName}: $_"
        }

        $results.Details.Add([PSCustomObject]$result) | Out-Null
    }

    return $results
}

#endregion

#region Winget Removal

<#
.SYNOPSIS
    Removes packages using Winget package manager
#>
function Remove-WingetBloatware {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [Array]$Items,

        [Parameter()]
        [switch]$DryRun
    )

    $results = @{
        Successful = 0
        Failed     = 0
        Skipped    = 0
        Details    = [List[PSCustomObject]]::new()
    }

    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Warning "Winget not available, skipping Winget removals"
        $results.Skipped = $Items.Count
        return $results
    }

    foreach ($item in $Items) {
        $packageName = $item.Name
        $operationStart = Get-Date
        $result = @{
            Name    = $packageName
            Source  = 'Winget'
            Success = $false
            Action  = if ($DryRun) { 'Simulated' } else { 'Removed' }
            Error   = $null
        }

        try {
            # Enhanced logging: Pre-action state detection
            Write-OperationStart -Component 'BLOATWARE-REMOVAL' -Operation 'Remove' -Target $packageName -AdditionalInfo "Winget Package - Querying installed state"
            
            # Check if package is installed before attempting removal
            $wingetListArgs = @('list', '--id', $packageName, '--accept-source-agreements')
            $listProcess = Start-Process -FilePath 'winget' -ArgumentList $wingetListArgs -Wait -PassThru -NoNewWindow -RedirectStandardOutput "$env:TEMP\winget-list-$packageName.txt" -ErrorAction SilentlyContinue
            $packageInstalled = $listProcess.ExitCode -eq 0
            
            Write-LogEntry -Level 'INFO' -Component 'BLOATWARE-REMOVAL' -Message "Pre-check: Winget package '$packageName' installed: $packageInstalled"
            
            if ($DryRun) {
                Write-Information "    [DRY RUN] Would uninstall Winget package: $packageName" -InformationAction Continue
                Write-OperationSkipped -Component 'BLOATWARE-REMOVAL' -Operation 'Remove' -Target $packageName -Reason 'DryRun mode enabled'
                $result.Success = $true
            }
            else {
                Write-Information "     Uninstalling Winget package: $packageName" -InformationAction Continue

                $wingetArgs = @(
                    'uninstall',
                    '--id', $packageName,
                    '--silent',
                    '--accept-source-agreements'
                )
                
                Write-LogEntry -Level 'INFO' -Component 'BLOATWARE-REMOVAL' -Message "Executing: winget $($wingetArgs -join ' ')"

                $process = Start-Process -FilePath 'winget' -ArgumentList $wingetArgs -Wait -PassThru -NoNewWindow

                if ($process.ExitCode -eq 0) {
                    # Post-action verification
                    Write-LogEntry -Level 'INFO' -Component 'BLOATWARE-REMOVAL' -Operation 'Verify' -Target $packageName -Message 'Verifying Winget package removal'
                    
                    $verifyProcess = Start-Process -FilePath 'winget' -ArgumentList $wingetListArgs -Wait -PassThru -NoNewWindow -RedirectStandardOutput "$env:TEMP\winget-verify-$packageName.txt" -ErrorAction SilentlyContinue
                    $stillInstalled = $verifyProcess.ExitCode -eq 0
                    
                    if (-not $stillInstalled) {
                        $operationDuration = ((Get-Date) - $operationStart).TotalSeconds
                        
                        # Log successful verification
                        Write-OperationSuccess -Component 'BLOATWARE-REMOVAL' -Operation 'Verify' -Target $packageName -Metrics @{
                            StillInstalled     = $false
                            VerificationPassed = $true
                        }
                        
                        # Log successful removal
                        Write-OperationSuccess -Component 'BLOATWARE-REMOVAL' -Operation 'Remove' -Target $packageName -Metrics @{
                            Duration = $operationDuration
                            ExitCode = $process.ExitCode
                            Verified = $true
                        }
                        $result.Success = $true
                        Write-Information "       Successfully uninstalled Winget package: $packageName (${operationDuration}s)" -InformationAction Continue
                    }
                    else {
                        # Log failed verification
                        Write-OperationFailure -Component 'BLOATWARE-REMOVAL' -Operation 'Verify' -Target $packageName -Error (New-Object Exception("Package still installed after uninstall"))
                        throw "Verification failed: Package still installed after uninstall"
                    }
                }
                else {
                    throw "Winget uninstall failed with exit code $($process.ExitCode)"
                }
            }

            $results.Successful++
        }
        catch {
            $result.Error = $_.Exception.Message
            $results.Failed++
            Write-OperationFailure -Component 'BLOATWARE-REMOVAL' -Operation 'Remove' -Target $packageName -Error $_
            Write-Warning "Failed to uninstall Winget package ${packageName}: $_"
        }
        finally {
            # Cleanup temporary files
            Remove-Item -Path "$env:TEMP\winget-list-$packageName.txt" -ErrorAction SilentlyContinue
            Remove-Item -Path "$env:TEMP\winget-verify-$packageName.txt" -ErrorAction SilentlyContinue
        }

        $results.Details.Add([PSCustomObject]$result) | Out-Null
    }

    return $results
}

#endregion

#region Chocolatey Removal

<#
.SYNOPSIS
    Removes packages using Chocolatey package manager
#>
function Remove-ChocolateyBloatware {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [Array]$Items,

        [Parameter()]
        [switch]$DryRun
    )

    $results = @{
        Successful = 0
        Failed     = 0
        Skipped    = 0
        Details    = [List[PSCustomObject]]::new()
    }

    if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
        Write-Warning "Chocolatey not available, skipping Chocolatey removals"
        $results.Skipped = $Items.Count
        return $results
    }

    foreach ($item in $Items) {
        $packageName = $item.Name
        $operationStart = Get-Date
        $result = @{
            Name    = $packageName
            Source  = 'Chocolatey'
            Success = $false
            Action  = if ($DryRun) { 'Simulated' } else { 'Removed' }
            Error   = $null
        }

        try {
            # Enhanced logging: Pre-action state detection
            Write-OperationStart -Component 'BLOATWARE-REMOVAL' -Operation 'Remove' -Target $packageName -AdditionalInfo "Chocolatey Package - Querying installed state"
            
            # Check if package is installed before attempting removal
            $chocoListArgs = @('list', '--local-only', '--exact', $packageName, '--limit-output')
            $listOutput = & choco @chocoListArgs 2>&1
            $packageInstalled = $LASTEXITCODE -eq 0 -and $listOutput -match $packageName
            $installedVersion = if ($packageInstalled -and $listOutput -match "$packageName\|(.+)") { $matches[1] } else { 'N/A' }
            
            Write-LogEntry -Level 'INFO' -Component 'BLOATWARE-REMOVAL' -Message "Pre-check: Chocolatey package '$packageName' installed: $packageInstalled, Version: $installedVersion"
            
            if ($DryRun) {
                Write-Information "    [DRY RUN] Would uninstall Chocolatey package: $packageName" -InformationAction Continue
                Write-OperationSkipped -Component 'BLOATWARE-REMOVAL' -Operation 'Remove' -Target $packageName -Reason 'DryRun mode enabled'
                $result.Success = $true
            }
            else {
                Write-Information "     Uninstalling Chocolatey package: $packageName" -InformationAction Continue

                $chocoArgs = @(
                    'uninstall',
                    $packageName,
                    '-y',
                    '--limit-output'
                )
                
                Write-LogEntry -Level 'INFO' -Component 'BLOATWARE-REMOVAL' -Message "Executing: choco $($chocoArgs -join ' ')"

                $process = Start-Process -FilePath 'choco' -ArgumentList $chocoArgs -Wait -PassThru -NoNewWindow

                if ($process.ExitCode -eq 0) {
                    # Post-action verification
                    Write-LogEntry -Level 'INFO' -Component 'BLOATWARE-REMOVAL' -Operation 'Verify' -Target $packageName -Message 'Verifying Chocolatey package removal'
                    
                    $verifyOutput = & choco @chocoListArgs 2>&1
                    $stillInstalled = $LASTEXITCODE -eq 0 -and $verifyOutput -match $packageName
                    
                    if (-not $stillInstalled) {
                        $operationDuration = ((Get-Date) - $operationStart).TotalSeconds
                        
                        # Log successful verification
                        Write-OperationSuccess -Component 'BLOATWARE-REMOVAL' -Operation 'Verify' -Target $packageName -Metrics @{
                            StillInstalled     = $false
                            VerificationPassed = $true
                        }
                        
                        # Log successful removal
                        Write-OperationSuccess -Component 'BLOATWARE-REMOVAL' -Operation 'Remove' -Target $packageName -Metrics @{
                            Duration        = $operationDuration
                            ExitCode        = $process.ExitCode
                            PreviousVersion = $installedVersion
                            Verified        = $true
                        }
                        $result.Success = $true
                        Write-Information "       Successfully uninstalled Chocolatey package: $packageName v$installedVersion (${operationDuration}s)" -InformationAction Continue
                    }
                    else {
                        # Log failed verification
                        Write-OperationFailure -Component 'BLOATWARE-REMOVAL' -Operation 'Verify' -Target $packageName -Error (New-Object Exception("Package still installed after uninstall"))
                        throw "Verification failed: Package still installed after uninstall"
                    }
                }
                else {
                    throw "Chocolatey uninstall failed with exit code $($process.ExitCode)"
                }
            }

            $results.Successful++
        }
        catch {
            $result.Error = $_.Exception.Message
            $results.Failed++
            Write-OperationFailure -Component 'BLOATWARE-REMOVAL' -Operation 'Remove' -Target $packageName -Error $_
            Write-Warning "Failed to uninstall Chocolatey package ${packageName}: $_"
        }

        $results.Details.Add([PSCustomObject]$result) | Out-Null
    }

    return $results
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
        [Array]$Items,

        [Parameter()]
        [switch]$DryRun
    )

    $results = @{
        Successful = 0
        Failed     = 0
        Skipped    = 0
        Details    = [List[PSCustomObject]]::new()
    }

    foreach ($item in $Items) {
        $appName = $item.DisplayName ?? $item.Name
        $uninstallString = $item.UninstallString
        $operationStart = Get-Date

        $result = @{
            Name    = $appName
            Source  = 'Registry'
            Success = $false
            Action  = if ($DryRun) { 'Simulated' } else { 'Removed' }
            Error   = $null
        }

        try {
            if (-not $uninstallString) {
                throw "No uninstall string available"
            }
            
            # Enhanced logging: Pre-action state detection
            $preActionState = @{
                DisplayName     = $appName
                UninstallString = $uninstallString
                InstallLocation = $item.InstallLocation ?? 'N/A'
                Publisher       = $item.Publisher ?? 'N/A'
                Version         = $item.DisplayVersion ?? 'N/A'
                EstimatedSize   = $item.EstimatedSize ?? 'N/A'
            }
            
            Write-OperationStart -Component 'BLOATWARE-REMOVAL' -Operation 'Remove' -Target $appName -AdditionalInfo "Registry Uninstaller - Version: $($preActionState.Version), Publisher: $($preActionState.Publisher)"

            if ($DryRun) {
                Write-Information "    [DRY RUN] Would execute uninstaller: $appName" -InformationAction Continue
                Write-LogEntry -Level 'INFO' -Component 'BLOATWARE-REMOVAL' -Message "Would execute: $uninstallString"
                Write-OperationSkipped -Component 'BLOATWARE-REMOVAL' -Operation 'Remove' -Target $appName -Reason 'DryRun mode enabled'
                $result.Success = $true
            }
            else {
                Write-Information "     Executing uninstaller: $appName" -InformationAction Continue

                # Parse uninstall string to extract executable and arguments
                if ($uninstallString -match '^"([^"]+)"(.*)') {
                    $executable = $matches[1]
                    $arguments = $matches[2].Trim()
                }
                else {
                    $parts = $uninstallString -split ' ', 2
                    $executable = $parts[0]
                    $arguments = if ($parts.Count -gt 1) { $parts[1] } else { '' }
                }

                # Add silent flags if not present
                if ($arguments -notmatch '/S|/silent|/quiet|/q') {
                    $arguments += ' /S'
                }
                
                Write-LogEntry -Level 'INFO' -Component 'BLOATWARE-REMOVAL' -Message "Executing: $executable $arguments"

                $process = Start-Process -FilePath $executable -ArgumentList $arguments -Wait -PassThru -NoNewWindow

                if ($process.ExitCode -eq 0) {
                    # Post-action verification - Check if registry entry still exists
                    $registryPaths = @(
                        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
                        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
                        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
                    )
                    
                    $stillExists = $false
                    foreach ($path in $registryPaths) {
                        $regEntry = Get-ItemProperty -Path $path -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -eq $appName }
                        if ($regEntry) {
                            $stillExists = $true
                            break
                        }
                    }
                    
                    $operationDuration = ((Get-Date) - $operationStart).TotalSeconds
                    
                    if (-not $stillExists) {
                        Write-OperationSuccess -Component 'BLOATWARE-REMOVAL' -Operation 'Remove' -Target $appName -Metrics @{
                            Duration        = $operationDuration
                            ExitCode        = $process.ExitCode
                            PreviousVersion = $preActionState.Version
                            EstimatedSize   = $preActionState.EstimatedSize
                            Verified        = $true
                        }
                        $result.Success = $true
                        Write-Information "       Successfully uninstalled: $appName v$($preActionState.Version) (${operationDuration}s)" -InformationAction Continue
                    }
                    else {
                        Write-LogEntry -Level 'WARNING' -Component 'BLOATWARE-REMOVAL' -Message "Registry entry still exists after uninstall, but exit code was 0 - treating as success"
                        Write-OperationSuccess -Component 'BLOATWARE-REMOVAL' -Operation 'Remove' -Target $appName -Metrics @{
                            Duration = $operationDuration
                            ExitCode = $process.ExitCode
                            Verified = $false
                        }
                        $result.Success = $true
                    }
                }
                else {
                    throw "Uninstaller failed with exit code $($process.ExitCode)"
                }
            }

            $results.Successful++
        }
        catch {
            $result.Error = $_.Exception.Message
            $results.Failed++
            Write-OperationFailure -Component 'BLOATWARE-REMOVAL' -Operation 'Remove' -Target $appName -Error $_
            Write-Warning "Failed to uninstall ${appName}: $_"
        }

        $results.Details.Add([PSCustomObject]$result) | Out-Null
    }

    return $results
}

#endregion

#region Helper Functions

<#
.SYNOPSIS
    Gets availability of removal tools
#>
function Get-RemovalToolAvailability {
    return @{
        AppX       = $null -ne (Get-Command Get-AppxPackage -ErrorAction SilentlyContinue)
        Winget     = $null -ne (Get-Command winget -ErrorAction SilentlyContinue)
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

