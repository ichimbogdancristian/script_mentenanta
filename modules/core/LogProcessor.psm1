#Requires -Version 7.0

<#
.SYNOPSIS
    Log Processor Module v3.1 - Type 1 Data Processing Pipeline (Simplified)

.DESCRIPTION
    Specialized module for processing raw maintenance logs from temp_files/data/ and 
    temp_files/logs/ into standardized, structured data for report generation.
    Part of the v3.1 simplified architecture that separates log processing (Type 1) from 
    report rendering (Report Generation). Handles data aggregation and normalization
    with direct file access (caching removed for performance - see LOGGING_SYSTEM_ANALYSIS.md).

.MODULE ARCHITECTURE
    Purpose:
        Serve as the data processing layer between execution logs and report generation.
        Aggregates Type1 audit results and Type2 execution logs into unified structured data.
        Uses direct file reads for optimal performance in single-execution scenarios.
    
    Dependencies:
        • CoreInfrastructure.psm1 - For path management and logging
    
    Exports:
        • Get-Type1AuditData - Load Type1 audit results from JSON files
        • Get-Type2ExecutionLogs - Load Type2 execution logs from text files
        • Get-MaintenanceLog - Load and parse maintenance.log
        • Invoke-LogProcessing - Full pipeline: load → parse → normalize → export
        • Get-ModuleExecutionData - Collect all module execution data
        • Various helper functions for safe data loading and processing
    
    Import Pattern:
        Import-Module LogProcessor.psm1 -Force
        # Functions available in MaintenanceOrchestrator context

    Used By:
        - ReportGenerator.psm1 (loads processed data for rendering)
        - MaintenanceOrchestrator.ps1 (invokes full processing pipeline)

.EXECUTION FLOW
    1. MaintenanceOrchestrator completes all Type1 and Type2 module execution
    2. Calls Invoke-LogProcessing to begin data processing phase
    3. Pipeline loads raw logs directly from temp_files/logs/[module]/ and temp_files/data/
    4. Parses and normalizes each log entry into structured format
    5. Aggregates by module and execution type (audit vs. execution)
    6. Writes final processed data to temp_files/processed/ for ReportGenerator
    7. ReportGenerator loads processed data and generates reports

.DATA ORGANIZATION
    Input Sources:
        • temp_files/data/[module]-results.json - Type1 audit result snapshots
        • temp_files/logs/[module]/execution.log - Type2 detailed execution logs
        • temp_files/logs/maintenance.log - Central execution log with all operations
    
    Output:
        • temp_files/processed/[module]-audit.json - Standardized Type1 data
        • temp_files/processed/[module]-execution.json - Standardized Type2 data
        • temp_files/processed/session-summary.json - Overall session statistics

.PERFORMANCE OPTIMIZATION
    • Direct file reads: No caching overhead (74% faster than v3.0)
    • Batch processing: Processes logs in 50-item batches to limit memory usage
    • Lazy loading: Only loads requested modules' data
    • Zero memory overhead: No cache structures consuming memory
    • Always fresh data: No stale cache issues

.NOTES
    Module Type: Type 1 (Data Processing - Read-Only)
    Architecture: v3.1 - Caching removed for performance (December 2025)
    Line Count: ~2,100 lines (264 lines removed from v3.0)
    Version: 3.1.0 (Simplified - No Caching)
    
    Key Design Patterns:
    - Pipeline architecture: Load → Parse → Normalize → Aggregate → Export
    - Modular data extraction: Each module's data processed independently
    - Direct file access: Always reads current data from disk
    - Error resilience: Non-critical parsing failures logged but don't stop pipeline
    
    Performance Analysis:
    - Old system (v3.0 with cache): ~140ms for 18 files (first run)
    - New system (v3.1 no cache): ~36ms for 18 files (74% faster)
    - See LOGGING_SYSTEM_ANALYSIS.md for detailed benchmarks
    
    Related Modules in v3.1 Architecture:
    - CoreInfrastructure.psm1 → Path management, logging infrastructure
    - ReportGenerator.psm1 → Consumes processed data for rendering
#>

using namespace System.Collections.Generic
using namespace System.Text

# Import core infrastructure for path management and logging
$CoreInfraPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'core\CoreInfrastructure.psm1'
if (Test-Path $CoreInfraPath) {
    Import-Module $CoreInfraPath -Force
}
else {
    throw "CoreInfrastructure module not found at: $CoreInfraPath - v3.0 requires proper module dependencies"
}

# Ensure path discovery is initialized (if not already done by orchestrator)
# This handles the case where LogProcessor is called in a new scope
try {
    Get-MaintenancePaths -ErrorAction Stop | Out-Null
}
catch {
    # Path discovery not yet initialized, try to initialize from environment variables
    try {
        $projectRoot = $env:MAINTENANCE_PROJECT_ROOT
        if ($projectRoot -and (Test-Path $projectRoot)) {
            Initialize-GlobalPathDiscovery -HintPath $projectRoot -Force
        }
    }
    catch {
        Write-Verbose "LogProcessor: Path initialization fallback failed - $_"
        # If initialization fails, it will be caught when functions try to access paths
    }
}

#region Maintenance Log Organization

<#
.SYNOPSIS
    Moves maintenance.log from repository root to organized temp_files/logs location

.DESCRIPTION
    Handles moving bootstrap maintenance.log from script root to the organized logs directory.
    This is called by LogProcessor on first invocation to organize logs that were written
    during the bootstrap phase. LogProcessor is aware of the project root and temp paths
    through the Initialize-GlobalPathDiscovery system.
    
    - Source: $ProjectRoot/maintenance.log (from bootstrap phase)
    - Target: $ProjectRoot/temp_files/logs/maintenance.log
    
    Uses atomic MOVE when possible, falls back to COPY+DELETE for compatibility.
    Idempotent: Safe to call multiple times, only moves if source exists and target doesn't.

.OUTPUTS
    Boolean - $true if moved/already organized, $false if not found or error
#>
function Move-MaintenanceLogToOrganized {
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    
    try {
        # Get paths from initialized path discovery system
        $projectRoot = (Get-MaintenancePaths).ProjectRoot
        $tempRoot = (Get-MaintenancePaths).TempRoot
        
        if (-not $projectRoot -or -not $tempRoot) {
            Write-LogEntry -Level 'WARNING' -Component 'LOG-PROCESSOR' -Message 'Path discovery not fully initialized, cannot organize maintenance.log'
            return $false
        }
        
        $sourceLog = Join-Path $projectRoot 'maintenance.log'
        $targetLog = Join-Path $tempRoot 'logs\maintenance.log'
        
        # Check if source exists
        if (-not (Test-Path $sourceLog)) {
            Write-LogEntry -Level 'DEBUG' -Component 'LOG-PROCESSOR' -Message "Bootstrap maintenance.log not found at root (already organized or first run): $sourceLog"
            return $true
        }
        
        # Check if already organized
        if (Test-Path $targetLog) {
            Write-LogEntry -Level 'DEBUG' -Component 'LOG-PROCESSOR' -Message "maintenance.log already at organized location: $targetLog"
            return $true
        }
        
        # Ensure target directory exists
        $targetDir = Split-Path -Parent $targetLog
        if (-not (Test-Path $targetDir)) {
            New-Item -Path $targetDir -ItemType Directory -Force | Out-Null
        }
        
        Write-LogEntry -Level 'INFO' -Component 'LOG-PROCESSOR' -Message "Organizing maintenance.log from bootstrap location to: $targetLog"
        
        # Try atomic MOVE first (preferred)
        try {
            Move-Item -Path $sourceLog -Destination $targetLog -Force -ErrorAction Stop
            Write-LogEntry -Level 'SUCCESS' -Component 'LOG-PROCESSOR' -Message "Successfully moved maintenance.log to organized location"
            return $true
        }
        catch {
            Write-LogEntry -Level 'WARNING' -Component 'LOG-PROCESSOR' -Message "MOVE operation failed, attempting COPY+DELETE: $($_.Exception.Message)"
            
            # Fallback: COPY then DELETE
            try {
                Copy-Item -Path $sourceLog -Destination $targetLog -Force -ErrorAction Stop
                Remove-Item -Path $sourceLog -Force -ErrorAction SilentlyContinue
                Write-LogEntry -Level 'SUCCESS' -Component 'LOG-PROCESSOR' -Message "Successfully organized maintenance.log via COPY+DELETE fallback"
                return $true
            }
            catch {
                Write-LogEntry -Level 'ERROR' -Component 'LOG-PROCESSOR' -Message "Failed to organize maintenance.log: $($_.Exception.Message)"
                return $false
            }
        }
    }
    catch {
        Write-LogEntry -Level 'ERROR' -Component 'LOG-PROCESSOR' -Message "Error organizing maintenance.log: $($_.Exception.Message)"
        return $false
    }
}

#endregion

#region Performance Optimization and Caching

# Caching removed in v3.1 - Direct file reads are faster and simpler for single-execution scripts
# See LOGGING_SYSTEM_ANALYSIS.md for performance analysis showing 74% improvement

<#
.SYNOPSIS
    Processes data in batches for improved performance with large datasets
#>
function Invoke-BatchProcessing {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [array]$InputData,
        
        [Parameter(Mandatory)]
        [scriptblock]$ProcessingScript,
        
        [int]$BatchSize = 50,
        
        [switch]$ContinueOnError,
        
        [string]$OperationName = 'Batch Processing'
    )
    
    Write-LogEntry -Level 'INFO' -Component 'BATCH-PROC' -Message "Starting $OperationName`: $($InputData.Count) items in batches of ${BatchSize}"
    
    $results = [List[object]]::new()
    $totalBatches = [Math]::Ceiling($InputData.Count / $BatchSize)
    $currentBatch = 0
    $processedItems = 0
    $errors = 0
    
    try {
        for ($i = 0; $i -lt $InputData.Count; $i += $BatchSize) {
            $currentBatch++
            $batch = $InputData[$i..([Math]::Min($i + $BatchSize - 1, $InputData.Count - 1))]
            
            Write-LogEntry -Level 'DEBUG' -Component 'BATCH-PROC' -Message "Processing batch $currentBatch of $totalBatches ($($batch.Count) items)"
            
            try {
                $batchResults = foreach ($item in $batch) {
                    try {
                        & $ProcessingScript -InputObject $item
                        $processedItems++
                    }
                    catch {
                        $errors++
                        Write-LogEntry -Level 'ERROR' -Component 'BATCH-PROC' -Message "Item processing failed: $($_.Exception.Message)"
                        
                        if (-not $ContinueOnError) {
                            throw
                        }
                        
                        # Return error placeholder
                        @{ 'Error' = $_.Exception.Message; 'Item' = $item }
                    }
                }
                
                $results.AddRange(@($batchResults))
            }
            catch {
                $errors++
                Write-LogEntry -Level 'ERROR' -Component 'BATCH-PROC' -Message "Batch $currentBatch processing failed: $($_.Exception.Message)"
                
                if (-not $ContinueOnError) {
                    throw
                }
            }
        }
        
        Write-LogEntry -Level 'INFO' -Component 'BATCH-PROC' -Message "$OperationName complete: $processedItems processed, $errors errors"
        return $results.ToArray()
    }
    catch {
        Write-LogEntry -Level 'ERROR' -Component 'BATCH-PROC' -Message "$OperationName failed: $($_.Exception.Message)"
        throw
    }
}

#endregion

#region Configuration and Initialization

<#
.SYNOPSIS
    Initialize processed data directories and validate paths
#>
function Initialize-ProcessedDataPaths {
    [CmdletBinding()]
    param()
    
    Write-LogEntry -Level 'INFO' -Component 'LOG-PROCESSOR' -Message 'Initializing processed data directory structure'
    
    try {
        # Ensure processed data directories exist
        $processedRoot = Join-Path (Get-MaintenancePath 'TempRoot') 'processed'
        $directories = @(
            $processedRoot,
            (Join-Path $processedRoot 'module-specific'),
            (Join-Path $processedRoot 'charts-data'),
            (Join-Path $processedRoot 'analytics')
        )
        
        foreach ($dir in $directories) {
            if (-not (Test-Path $dir)) {
                New-Item -Path $dir -ItemType Directory -Force | Out-Null
                Write-Verbose "Created directory: $dir"
            }
        }
        
        return $processedRoot
    }
    catch {
        Write-LogEntry -Level 'ERROR' -Component 'LOG-PROCESSOR' -Message "Failed to initialize processed data paths: $($_.Exception.Message)"
        throw
    }
}

#endregion

#region Raw Data Collection

<#
.SYNOPSIS
    Scans temp_files/data/ for Type1 audit results (JSON files)
#>
function Get-Type1AuditData {
    [CmdletBinding()]
    param()
    
    Write-LogEntry -Level 'DEBUG' -Component 'LOG-PROCESSOR' -Message 'Loading Type1 audit data files'
    
    $auditData = @{}
    $dataPath = Join-Path (Get-MaintenancePath 'TempRoot') 'data'
    
    if (-not (Test-Path $dataPath)) {
        Write-LogEntry -Level 'WARNING' -Component 'LOG-PROCESSOR' -Message "Type1 audit data directory not found: $dataPath"
        return $auditData
    }
    
    try {
        # Use safe directory scanning with error recovery
        $jsonFiles = Get-SafeDirectoryContents -DirectoryPath $dataPath -Filter '*.json' -FilesOnly
        
        # Process files in batches for better performance with many modules
        $processingScript = {
            param($InputObject)
            
            $file = $InputObject
            $moduleName = $file.BaseName -replace '-results$', ''
            
            # Use safe JSON loading with validation
            $defaultData = @{
                ModuleName       = $moduleName
                Status           = 'No Data'
                ItemsFound       = 0
                ProcessingErrors = @("Failed to load audit data for $moduleName")
            }
            
            $content = Import-SafeJsonData -JsonPath $file.FullName -DefaultData $defaultData -ContinueOnError
            
            if ($content) {
                Write-Verbose " Loaded audit data for module: $moduleName"
                return @{ ModuleName = $moduleName; Data = $content }
            }
            else {
                Write-LogEntry -Level 'WARNING' -Component 'LOG-PROCESSOR' -Message "Using fallback data for module: $moduleName"
                return @{ ModuleName = $moduleName; Data = $defaultData }
            }
        }
        
        # Process in batches for performance
        $batchResults = Invoke-BatchProcessing -InputData $jsonFiles -ProcessingScript $processingScript -ContinueOnError -OperationName 'Type1 Audit Data Loading'
        
        # Assemble final audit data structure
        foreach ($result in $batchResults) {
            if ($result -and $result.ModuleName -and $result.Data) {
                $auditData[$result.ModuleName] = $result.Data
            }
        }
        
        Write-LogEntry -Level 'SUCCESS' -Component 'LOG-PROCESSOR' -Message "Audit data loading completed: $($auditData.Keys.Count) modules processed"
        return $auditData
    }
    catch {
        Write-LogEntry -Level 'ERROR' -Component 'LOG-PROCESSOR' -Message "Critical error scanning Type1 audit data: $($_.Exception.Message)"
        # Return empty data structure for graceful degradation
        return $auditData
    }
}

<#
.SYNOPSIS
    Scans temp_files/logs/ for Type2 execution logs (text files)
#>
function Get-Type2ExecutionLogs {
    [CmdletBinding()]
    param()
    
    Write-LogEntry -Level 'DEBUG' -Component 'LOG-PROCESSOR' -Message 'Loading Type2 execution logs'
    
    $executionLogs = @{}
    $logsPath = Join-Path (Get-MaintenancePath 'TempRoot') 'logs'
    
    if (-not (Test-Path $logsPath)) {
        Write-LogEntry -Level 'WARNING' -Component 'LOG-PROCESSOR' -Message "Type2 execution logs directory not found: $logsPath"
        return $executionLogs
    }
    
    try {
        # Use safe directory scanning for module directories
        $moduleDirectories = Get-SafeDirectoryContents -DirectoryPath $logsPath -DirectoriesOnly
        
        # Process directories in batches for performance
        $processingScript = {
            param($InputObject)
            
            $moduleDir = $InputObject
            $moduleName = $moduleDir.Name
            $executionLogPath = Join-Path $moduleDir.FullName 'execution.log'
            
            # Use safe log file reading operation
            $logLoadOperation = {
                param($ExecutionLogPath)
                
                if (-not (Test-Path $ExecutionLogPath)) {
                    throw "Execution log file not found: $ExecutionLogPath"
                }
                
                return Get-Content $ExecutionLogPath -Raw -ErrorAction Stop
            }
            
            $fallbackOperation = {
                param($ExecutionLogPath, $ModuleName)
                Write-LogEntry -Level 'WARNING' -Component 'LOG-PROCESSOR' -Message "Using placeholder log content for module: $ModuleName"
                return "# Execution log for $ModuleName - Content unavailable (file read error)`n# This is fallback content generated by LogProcessor error handling"
            }
            
            $result = Invoke-SafeLogOperation -OperationName "Load execution log for $moduleName" -Operation $logLoadOperation -Parameters @{
                ExecutionLogPath = $executionLogPath
            } -FallbackOperation $fallbackOperation -FallbackMessage "Using placeholder content for $moduleName execution log" -ContinueOnError
            
            return @{
                ModuleName   = $moduleName
                Data         = $result.Data
                Success      = $result.Success
                FallbackUsed = $result.FallbackUsed
            }
        }
        
        # Process in batches for performance
        $batchResults = Invoke-BatchProcessing -InputData $moduleDirectories -ProcessingScript $processingScript -ContinueOnError -OperationName 'Type2 Execution Logs Loading'
        
        # Assemble final execution logs structure
        foreach ($result in $batchResults) {
            if ($result -and $result.Success) {
                $executionLogs[$result.ModuleName] = $result.Data
                $status = if ($result.FallbackUsed) { " (fallback)" } else { "" }
                Write-Verbose "$status Loaded execution log for module: $($result.ModuleName)"
            }
            elseif ($result) {
                Write-LogEntry -Level 'WARNING' -Component 'LOG-PROCESSOR' -Message "Skipped execution log for module: $($result.ModuleName) (no recovery possible)"
            }
        }
        
        Write-LogEntry -Level 'INFO' -Component 'LOG-PROCESSOR' -Message "Loaded execution logs for $($executionLogs.Keys.Count) modules"
        return $executionLogs
    }
    catch {
        Write-LogEntry -Level 'ERROR' -Component 'LOG-PROCESSOR' -Message "Error scanning Type2 execution logs: $($_.Exception.Message)"
        return $executionLogs
    }
}

<#
.SYNOPSIS
    Retrieves and parses the main maintenance.log file from temp_files
.DESCRIPTION
    Loads the orchestrator's maintenance.log file that contains all core operations,
    module loading, and execution flow information for inclusion in final reports.
#>
function Get-MaintenanceLog {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()
    
    Write-LogEntry -Level 'INFO' -Component 'LOG-PROCESSOR' -Message 'Loading main maintenance.log file'
    
    $maintenanceLogData = @{
        LogFile      = $null
        Content      = $null
        LineCount    = 0
        Size         = 0
        LastModified = $null
        Parsed       = @{
            InfoMessages    = @()
            WarningMessages = @()
            ErrorMessages   = @()
            SuccessMessages = @()
            DebugMessages   = @()
            TotalEntries    = 0
        }
        Available    = $false
    }
    
    try {
        # Try to locate maintenance.log in temp_files
        $mainLogPath = Join-Path (Get-MaintenancePath 'TempRoot') 'maintenance.log'
        
        if (-not (Test-Path $mainLogPath)) {
            Write-LogEntry -Level 'WARNING' -Component 'LOG-PROCESSOR' -Message "Maintenance log not found at: $mainLogPath"
            return $maintenanceLogData
        }
        
        $logFile = Get-Item $mainLogPath
        $maintenanceLogData.LogFile = $mainLogPath
        $maintenanceLogData.Size = $logFile.Length
        $maintenanceLogData.LastModified = $logFile.LastWriteTime
        
        # Read log content with safe operation
        $logLoadOperation = {
            param($LogPath)
            if (-not (Test-Path $LogPath)) {
                throw "Maintenance log file not found: $LogPath"
            }
            return Get-Content $LogPath -Raw -ErrorAction Stop
        }
        
        $fallbackOperation = {
            param($LogPath)
            Write-LogEntry -Level 'WARNING' -Component 'LOG-PROCESSOR' -Message "Using placeholder content for maintenance.log"
            return "# Maintenance log content unavailable (file read error)`n# This is fallback content generated by LogProcessor error handling"
        }
        
        $result = Invoke-SafeLogOperation `
            -OperationName "Load maintenance.log" `
            -Operation $logLoadOperation `
            -Parameters @{ LogPath = $mainLogPath } `
            -FallbackOperation $fallbackOperation `
            -FallbackMessage "Using placeholder content for maintenance.log" `
            -ContinueOnError
        
        if ($result.Success) {
            $maintenanceLogData.Content = $result.Data
            $maintenanceLogData.Available = $true
            
            # Parse log entries by level
            $logLines = $result.Data -split "`r?`n"
            $maintenanceLogData.LineCount = $logLines.Count
            
            foreach ($line in $logLines) {
                # Null safety check
                if ([string]::IsNullOrWhiteSpace($line)) {
                    continue
                }
                
                if ($line -match '\[(INFO|WARN|ERROR|SUCCESS|DEBUG)\]') {
                    $level = $matches[1]
                    
                    switch ($level) {
                        'INFO' { $maintenanceLogData.Parsed.InfoMessages += $line }
                        'WARN' { $maintenanceLogData.Parsed.WarningMessages += $line }
                        'ERROR' { $maintenanceLogData.Parsed.ErrorMessages += $line }
                        'SUCCESS' { $maintenanceLogData.Parsed.SuccessMessages += $line }
                        'DEBUG' { $maintenanceLogData.Parsed.DebugMessages += $line }
                    }
                    $maintenanceLogData.Parsed.TotalEntries++
                }
            }
            
            Write-LogEntry -Level 'SUCCESS' -Component 'LOG-PROCESSOR' -Message "Loaded maintenance.log: $($maintenanceLogData.LineCount) lines, $($maintenanceLogData.Parsed.TotalEntries) structured entries"
        }
        else {
            $maintenanceLogData.Content = $result.Data
            $maintenanceLogData.Available = $result.FallbackUsed
            Write-LogEntry -Level 'WARNING' -Component 'LOG-PROCESSOR' -Message "Maintenance.log loaded with fallback content"
        }
        
        return $maintenanceLogData
    }
    catch {
        Write-LogEntry -Level 'ERROR' -Component 'LOG-PROCESSOR' -Message "Error loading maintenance.log: $($_.Exception.Message)"
        return $maintenanceLogData
    }
}

#endregion

#region Log Collection and Parsing Functions

<#
.SYNOPSIS
    Collect module execution data from v3.0 standardized paths
    Extracted from ReportGeneration.psm1 for split architecture
#>
function Get-ModuleExecutionData {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()
    
    try {
        Write-LogEntry -Level 'INFO' -Component 'LOG-PROCESSOR' -Message 'Collecting module execution data from v3.0 standardized paths'
        
        $moduleData = @{
            Type1Results = @{}  # Audit/detection results from Type1 modules
            Type2Results = @{}  # Execution results from Type2 modules  
            LogPaths     = @{}      # Paths to module-specific log files
            DataPaths    = @{}     # Paths to module-specific data files
        }
        
        # Define v3.0 module mapping (Type2 -> Type1)
        $moduleMapping = @{
            'BloatwareRemoval'   = 'BloatwareDetectionAudit'
            'EssentialApps'      = 'EssentialAppsAudit'
            'SystemOptimization' = 'SystemOptimizationAudit'
            'TelemetryDisable'   = 'TelemetryAudit'
            'WindowsUpdates'     = 'WindowsUpdatesAudit'
        }
        
        foreach ($type2Module in $moduleMapping.Keys) {
            # Null safety check
            if ([string]::IsNullOrWhiteSpace($type2Module)) {
                Write-LogEntry -Level 'WARNING' -Component 'LOG-PROCESSOR' -Message "Skipping null or empty module name in mapping"
                continue
            }
            
            $type1Module = $moduleMapping[$type2Module]
            if ([string]::IsNullOrWhiteSpace($type1Module)) {
                Write-LogEntry -Level 'WARNING' -Component 'LOG-PROCESSOR' -Message "Skipping null Type1 module mapping for $type2Module"
                continue
            }
            
            # Collect Type1 audit data (detection/analysis results)
            try {
                $auditDataPath = Get-SessionPath -Category 'data' -FileName "$($type2Module.ToLower())-results.json"
                if (Test-Path $auditDataPath) {
                    $auditData = Get-Content $auditDataPath -Raw | ConvertFrom-Json
                    $moduleData.Type1Results[$type1Module] = $auditData
                    $moduleData.DataPaths[$type1Module] = $auditDataPath
                    Write-LogEntry -Level 'DEBUG' -Component 'LOG-PROCESSOR' -Message "Loaded audit data for $type1Module"
                }
            }
            catch {
                Write-LogEntry -Level 'WARNING' -Component 'LOG-PROCESSOR' -Message "Failed to load audit data for $type1Module : $($_.Exception.Message)"
            }
            
            # Collect Type2 execution data and logs
            try {
                $executionLogPath = Get-SessionPath -Category 'logs' -SubCategory $type2Module.ToLower() -FileName 'execution.log'
                if (Test-Path $executionLogPath) {
                    $moduleData.LogPaths[$type2Module] = $executionLogPath
                    # Parse execution results from log or separate data file if available
                    $executionDataPath = Get-SessionPath -Category 'data' -FileName "$($type2Module.ToLower())-execution-results.json"
                    if (Test-Path $executionDataPath) {
                        $executionData = Get-Content $executionDataPath -Raw | ConvertFrom-Json
                        $moduleData.Type2Results[$type2Module] = $executionData
                        $moduleData.DataPaths[$type2Module] = $executionDataPath
                    }
                    Write-LogEntry -Level 'DEBUG' -Component 'LOG-PROCESSOR' -Message "Loaded execution data for $type2Module"
                }
            }
            catch {
                Write-LogEntry -Level 'WARNING' -Component 'LOG-PROCESSOR' -Message "Failed to load execution data for $type2Module : $($_.Exception.Message)"
            }
        }
        
        Write-LogEntry -Level 'INFO' -Component 'LOG-PROCESSOR' -Message "Module data collection completed" -Data @{
            Type1ModulesFound = $moduleData.Type1Results.Count
            Type2ModulesFound = $moduleData.Type2Results.Count
            TotalLogPaths     = $moduleData.LogPaths.Count
            TotalDataPaths    = $moduleData.DataPaths.Count
        }
        
        return $moduleData
    }
    catch {
        Write-LogEntry -Level 'ERROR' -Component 'LOG-PROCESSOR' -Message "Failed to collect module execution data: $($_.Exception.Message)"
        # Return empty structure to allow report generation to continue
        return @{
            Type1Results = @{}
            Type2Results = @{}
            LogPaths     = @{}
            DataPaths    = @{}
        }
    }
}

<#
.SYNOPSIS
    Convert execution log content to structured analysis data
    Extracted from ReportGeneration.psm1 for split architecture
#>
function ConvertFrom-ModuleExecutionLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ModuleName,
        
        [Parameter(Mandatory)]
        [string]$LogContent
    )
    
    $analysis = @{
        Metrics           = @{
            TotalOperations      = 0
            SuccessfulOperations = 0
            FailedOperations     = 0
            WarningCount         = 0
            StartTime            = $null
            EndTime              = $null
            Duration             = 0
        }
        TaskDetails       = @()
        Modifications     = @()
        Performance       = @{}
        Errors            = @()
        Warnings          = @()
        SuccessOperations = @()
    }
    
    if (-not $LogContent) {
        Write-Verbose "No log content for $ModuleName"
        return $analysis
    }
    
    $logLines = $LogContent -split "`n"
    
    foreach ($line in $logLines) {
        # Skip null or empty lines to avoid "cannot call method on null-valued expression" errors
        if ($null -eq $line -or [string]::IsNullOrWhiteSpace($line)) { 
            continue 
        }
        
        $line = $line.Trim()
        
        # Parse structured log entries
        if ($line -match '^\[([^\]]+)\]\s+\[(INFO|SUCCESS|WARN|ERROR|FAILED)\]\s+\[([^\]]+)\]\s+(.+)$') {
            $timestamp = $matches[1]
            $level = $matches[2]
            $component = $matches[3]
            $message = $matches[4]
            
            # Track timing
            if (-not $analysis.Metrics.StartTime) {
                $analysis.Metrics.StartTime = $timestamp
            }
            $analysis.Metrics.EndTime = $timestamp
            
            switch ($level) {
                'SUCCESS' { 
                    $analysis.Metrics.SuccessfulOperations++
                    $analysis.SuccessOperations += @{
                        Timestamp = $timestamp
                        Component = $component
                        Message   = $message
                        Action    = Get-ActionFromMessage -Message $message
                    }
                }
                { $_ -in @('ERROR', 'FAILED') } { 
                    $analysis.Metrics.FailedOperations++
                    $analysis.Errors += @{
                        Timestamp = $timestamp
                        Level     = $level
                        Component = $component
                        Message   = $message
                        Severity  = 'High'
                    }
                }
                'WARN' { 
                    $analysis.Metrics.WarningCount++
                    $analysis.Warnings += @{
                        Timestamp = $timestamp
                        Component = $component
                        Message   = $message
                        Severity  = 'Medium'
                    }
                }
                'INFO' {
                    # Extract system modifications from INFO messages
                    $modification = Get-SystemModificationFromMessage -Message $message -Timestamp $timestamp -Component $component
                    if ($modification) {
                        $analysis.Modifications += $modification
                    }
                    
                    # Extract task details
                    $taskDetail = Get-TaskDetailFromMessage -Message $message -Timestamp $timestamp -Component $component
                    if ($taskDetail) {
                        $analysis.TaskDetails += $taskDetail
                    }
                }
            }
            
            $analysis.Metrics.TotalOperations++
        }
        
        # Parse Write-LogEntry style entries
        elseif ($line -match 'Write-LogEntry:.*\[([^\]]+)\]\s+\[(ERROR|WARN|INFO|SUCCESS)\].*(.+)$') {
            $timestamp = $matches[1]
            $level = $matches[2]
            $message = $matches[3].Trim()
            
            switch ($level) {
                'ERROR' { 
                    $analysis.Metrics.FailedOperations++
                    $analysis.Errors += @{
                        Timestamp = $timestamp
                        Level     = $level
                        Component = if ($ModuleName) { $ModuleName.ToUpper() } else { 'UNKNOWN' }
                        Message   = $message
                        Severity  = 'High'
                    }
                }
                'WARN' { 
                    $analysis.Metrics.WarningCount++
                }
                'SUCCESS' { 
                    $analysis.Metrics.SuccessfulOperations++
                }
            }
        }
        
        # Parse performance indicators
        elseif ($line -match 'Completed.*in\s+(\d+\.?\d*)(ms|s|seconds)' -or $line -match 'Duration[:\s]+(\d+\.?\d*)(ms|s)') {
            $duration = [double]$matches[1]
            $unit = $matches[2]
            
            if ($unit -eq 'ms') {
                $duration = $duration / 1000
            }
            
            $analysis.Performance.ExecutionTime = $duration
            $analysis.Metrics.Duration = $duration
        }
        
        # Parse specific operation counts
        elseif ($line -match '(\d+)\s+(installed|removed|optimized|disabled|updated|processed|detected)' -or 
            $line -match '(installed|removed|optimized|disabled|updated|processed)\s+(\d+)') {
            $count = if ($matches[1] -match '^\d+$') { [int]$matches[1] } else { [int]$matches[2] }
            $operation = if ($matches[1] -match '^\d+$') { $matches[2] } else { $matches[1] }
            
            $analysis.Performance[$operation] = $count
        }
    }
    
    # Calculate success rate
    if ($analysis.Metrics.TotalOperations -gt 0) {
        $analysis.Metrics.SuccessRate = [math]::Round(
            ($analysis.Metrics.SuccessfulOperations / $analysis.Metrics.TotalOperations) * 100, 1
        )
    }
    
    Write-Verbose "$ModuleName analysis: $($analysis.Metrics.TotalOperations) total ops, $($analysis.Metrics.SuccessfulOperations) success, $($analysis.Errors.Count) errors"
    
    return $analysis
}

<#
.SYNOPSIS
    Helper function to extract action information from log messages
#>
function Get-ActionFromMessage {
    [CmdletBinding()]
    param([string]$Message)
    
    # Extract specific actions from log messages
    if ($Message -match '(Installing|Removing|Uninstalling|Optimizing|Disabling|Updating|Processing)\s+(.+)') {
        return @{
            Type   = $matches[1]
            Target = $matches[2]
        }
    }
    
    if ($Message -match '(Installed|Removed|Uninstalled|Optimized|Disabled|Updated|Processed)\s+(.+)') {
        return @{
            Type      = $matches[1] -replace 'd$', 'ing'  # Convert past tense to present
            Target    = $matches[2]
            Completed = $true
        }
    }
    
    return $null
}

<#
.SYNOPSIS
    Helper function to extract system modification information from log messages
#>
function Get-SystemModificationFromMessage {
    [CmdletBinding()]
    param(
        [string]$Message,
        [string]$Timestamp,
        [string]$Component
    )
    
    # Identify system modifications from log messages
    $modifications = @()
    
    # Application installations/removals
    if ($Message -match '(Successfully installed|Successfully removed|Successfully uninstalled|Installed|Removed|Uninstalled)\s+(.+?)(\s+\(|\s*$)') {
        $modifications += @{
            Type      = 'Application'
            Action    = if ($matches[1] -match 'install') { 'Install' } else { 'Remove' }
            Target    = $matches[2].Trim()
            Timestamp = $Timestamp
            Component = $Component
            Category  = 'Software Management'
        }
    }
    
    # Service modifications
    if ($Message -match '(Started|Stopped|Disabled|Enabled)\s+service[:\s]+(.+?)(\s+\(|\s*$)') {
        $modifications += @{
            Type      = 'Service'
            Action    = $matches[1]
            Target    = $matches[2].Trim()
            Timestamp = $Timestamp
            Component = $Component
            Category  = 'System Services'
        }
    }
    
    # Registry modifications
    if ($Message -match '(Set|Modified|Created|Deleted)\s+(registry\s+)?(key|value)[:\s]+(.+?)(\s+\(|\s*$)') {
        $modifications += @{
            Type      = 'Registry'
            Action    = $matches[1]
            Target    = $matches[4].Trim()
            Timestamp = $Timestamp
            Component = $Component
            Category  = 'System Configuration'
        }
    }
    
    # System optimizations
    if ($Message -match '(Applied|Enabled|Disabled)\s+(optimization|setting)[:\s]+(.+?)(\s+\(|\s*$)') {
        $modifications += @{
            Type      = 'Optimization'
            Action    = $matches[1]
            Target    = $matches[3].Trim()
            Timestamp = $Timestamp
            Component = $Component
            Category  = 'Performance Tuning'
        }
    }
    
    return $modifications
}

<#
.SYNOPSIS
    Helper function to extract task detail information from log messages
#>
function Get-TaskDetailFromMessage {
    [CmdletBinding()]
    param(
        [string]$Message,
        [string]$Timestamp,
        [string]$Component
    )
    
    # Extract task execution details
    if ($Message -match 'Starting\s+(.+?)(\s+analysis|\s+installation|\s+removal|\s+optimization|\s+processing)') {
        return @{
            Type      = 'TaskStart'
            Operation = $matches[1] + $matches[2]
            Timestamp = $Timestamp
            Component = $Component
        }
    }
    
    if ($Message -match 'Completed\s+(.+?)(\s+in\s+[\d.]+\w+)') {
        return @{
            Type      = 'TaskComplete'
            Operation = $matches[1]
            Duration  = $matches[2]
            Timestamp = $Timestamp
            Component = $Component
        }
    }
    
    if ($Message -match 'Processing\s+(\d+)\s+(.+?)(\s+items|\s+apps|\s+services)') {
        return @{
            Type      = 'TaskProgress'
            Count     = [int]$matches[1]
            Items     = $matches[2] + $matches[3]
            Timestamp = $Timestamp
            Component = $Component
        }
    }
    
    return $null
}

<#
.SYNOPSIS
    Convert audit data to structured analysis format
    Extracted from ReportGeneration.psm1 for split architecture
#>
function ConvertFrom-AuditData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ModuleName,
        
        [Parameter(Mandatory)]
        $AuditData
    )
    
    $analysis = @{
        DetectedCount = 0
        Details       = @()
        HealthScore   = 0
        Categories    = @{}
    }
    
    # Handle different audit data structures
    if ($AuditData -is [array]) {
        $analysis.DetectedCount = $AuditData.Count
        $analysis.Details = $AuditData
    }
    elseif ($AuditData -is [hashtable] -or $AuditData.PSObject) {
        # Handle structured audit data
        if ($AuditData.Summary) {
            $analysis.DetectedCount = $AuditData.Summary.TotalFound ?? $AuditData.Summary.TotalScanned ?? 0
        }
        
        if ($AuditData.HealthScore) {
            $analysis.HealthScore = $AuditData.HealthScore
        }
        
        # Extract categorized data
        foreach ($property in $AuditData.PSObject.Properties) {
            if ($property.Name -match '(Count|Found|Detected)$' -and $property.Value -is [int]) {
                $category = $property.Name -replace '(Count|Found|Detected)$', ''
                $analysis.Categories[$category] = $property.Value
            }
        }
    }
    
    Write-Verbose "$ModuleName audit: $($analysis.DetectedCount) items detected, health score: $($analysis.HealthScore)"
    
    return $analysis
}

#endregion

#region Log Analysis Functions

<#
.SYNOPSIS
    Perform comprehensive analysis of all collected logs
    Extracted from ReportGeneration.psm1 for split architecture
#>
function Get-ComprehensiveLogAnalysis {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$ComprehensiveLogCollection
    )
    
    Write-Verbose "Starting comprehensive log analysis for all report sections"
    
    $logAnalysis = @{
        ExecutionMetrics     = @{}
        TaskDetails          = @{}
        SystemModifications  = @{}
        PerformanceData      = @{}
        SecurityEvents       = @{}
        HealthMetrics        = @{}
        Errors               = @{}
        Warnings             = @{}
        SuccessfulOperations = @{}
    }
    
    # Process Type2 Execution Logs for detailed metrics
    if ($ComprehensiveLogCollection.Type2ExecutionLogs) {
        foreach ($moduleName in $ComprehensiveLogCollection.Type2ExecutionLogs.Keys) {
            $logContent = $ComprehensiveLogCollection.Type2ExecutionLogs[$moduleName]
            
            Write-Verbose "Processing $moduleName execution logs"
            
            $moduleAnalysis = ConvertFrom-ModuleExecutionLog -ModuleName $moduleName -LogContent $logContent
            
            # Store parsed data for different report sections
            $logAnalysis.ExecutionMetrics[$moduleName] = $moduleAnalysis.Metrics
            $logAnalysis.TaskDetails[$moduleName] = $moduleAnalysis.TaskDetails
            $logAnalysis.SystemModifications[$moduleName] = $moduleAnalysis.Modifications
            $logAnalysis.PerformanceData[$moduleName] = $moduleAnalysis.Performance
            $logAnalysis.Errors[$moduleName] = $moduleAnalysis.Errors
            $logAnalysis.Warnings[$moduleName] = $moduleAnalysis.Warnings
            $logAnalysis.SuccessfulOperations[$moduleName] = $moduleAnalysis.SuccessOperations
        }
    }
    
    # Process Type1 Audit Data for additional insights
    if ($ComprehensiveLogCollection.Type1AuditData) {
        foreach ($moduleName in $ComprehensiveLogCollection.Type1AuditData.Keys) {
            $auditData = $ComprehensiveLogCollection.Type1AuditData[$moduleName]
            
            Write-Verbose "Processing $moduleName audit data"
            
            $auditAnalysis = ConvertFrom-AuditData -ModuleName $moduleName -AuditData $auditData
            
            # Merge audit insights with execution data
            if ($logAnalysis.ExecutionMetrics[$moduleName]) {
                $logAnalysis.ExecutionMetrics[$moduleName].ItemsDetected = $auditAnalysis.DetectedCount
                $logAnalysis.ExecutionMetrics[$moduleName].DetectionDetails = $auditAnalysis.Details
            }
            
            # Add health metrics from audit data
            $logAnalysis.HealthMetrics[$moduleName] = $auditAnalysis.HealthScore
        }
    }
    
    Write-Verbose "Comprehensive log analysis completed"
    return $logAnalysis
}

<#
.SYNOPSIS
    Calculate comprehensive dashboard metrics from log collection
    Extracted from ReportGeneration.psm1 for split architecture
#>
function Get-ComprehensiveDashboardMetrics {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$ComprehensiveLogCollection,
        
        [Parameter()]
        [array]$TaskResults = @()
    )
    
    Write-Verbose "Analyzing logs for dashboard metrics"
    
    $metrics = @{
        TotalTasks          = 0
        SuccessfulTasks     = 0
        FailedTasks         = 0
        TotalDuration       = 0
        TotalItemsDetected  = 0
        TotalItemsProcessed = 0
        ModulesExecuted     = 0
        ErrorCount          = 0
        WarningCount        = 0
        SuccessRate         = 0
        SystemHealthScore   = 0
        SecurityScore       = 0
    }
    
    # Parse Type2 execution logs for detailed metrics
    if ($ComprehensiveLogCollection.Type2ExecutionLogs) {
        $metrics.ModulesExecuted = $ComprehensiveLogCollection.Type2ExecutionLogs.Keys.Count
        
        foreach ($moduleName in $ComprehensiveLogCollection.Type2ExecutionLogs.Keys) {
            $logContent = $ComprehensiveLogCollection.Type2ExecutionLogs[$moduleName]
            
            if ($logContent) {
                $logLines = $logContent -split "`n"
                
                # Count tasks from logs
                $metrics.TotalTasks++
                
                # Extract success/failure from logs
                $hasErrors = $false
                $taskDuration = 0
                $itemsDetected = 0
                $itemsProcessed = 0
                
                foreach ($line in $logLines) {
                    $line = $line.Trim()
                    
                    # Count errors and warnings
                    if ($line -match '\[(ERROR|FAILED)\]') {
                        $metrics.ErrorCount++
                        $hasErrors = $true
                    }
                    elseif ($line -match '\[WARN\]') {
                        $metrics.WarningCount++
                    }
                    
                    # Extract completion messages for success detection
                    if ($line -match 'completed.*successfully|SUCCESS.*processed|Installation.*complete') {
                        # This suggests successful completion
                    }
                    
                    # Extract items detected/processed
                    if ($line -match 'detected.*(\d+).*items?|found.*(\d+).*items?') {
                        $itemsDetected = [int]($matches[1] -replace '\D', '')
                    }
                    if ($line -match 'processed.*(\d+).*items?|installed.*(\d+).*apps?|removed.*(\d+).*items?') {
                        $itemsProcessed = [int]($matches[1] -replace '\D', '')
                    }
                    
                    # Extract duration
                    if ($line -match 'Duration.*(\d+\.?\d*)\s*(seconds?|s\b)') {
                        $taskDuration = [double]$matches[1]
                    }
                }
                
                # Determine success/failure
                if (-not $hasErrors) {
                    $metrics.SuccessfulTasks++
                }
                else {
                    $metrics.FailedTasks++
                }
                
                $metrics.TotalDuration += $taskDuration
                $metrics.TotalItemsDetected += $itemsDetected
                $metrics.TotalItemsProcessed += $itemsProcessed
            }
        }
    }
    
    # Use TaskResults if available for more accurate metrics
    if ($TaskResults -and $TaskResults.Count -gt 0) {
        $metrics.TotalTasks = $TaskResults.Count
        $metrics.SuccessfulTasks = ($TaskResults | Where-Object { $_.Success }).Count
        $metrics.FailedTasks = $metrics.TotalTasks - $metrics.SuccessfulTasks
        $metrics.TotalDuration = ($TaskResults | Measure-Object Duration -Sum).Sum
    }
    
    # Calculate success rate
    if ($metrics.TotalTasks -gt 0) {
        $metrics.SuccessRate = [math]::Round(($metrics.SuccessfulTasks / $metrics.TotalTasks) * 100, 1)
    }
    
    # Calculate system health score based on various factors
    $healthFactors = @{
        SuccessRate          = if ($metrics.SuccessRate -ge 90) { 25 } elseif ($metrics.SuccessRate -ge 75) { 20 } elseif ($metrics.SuccessRate -ge 50) { 15 } else { 5 }
        ErrorRate            = if ($metrics.ErrorCount -eq 0) { 25 } elseif ($metrics.ErrorCount -le 2) { 20 } elseif ($metrics.ErrorCount -le 5) { 15 } else { 5 }
        ProcessingEfficiency = if ($metrics.TotalItemsProcessed -ge $metrics.TotalItemsDetected * 0.9) { 25 } elseif ($metrics.TotalItemsProcessed -ge $metrics.TotalItemsDetected * 0.7) { 20 } else { 10 }
        ModuleCompletion     = if ($metrics.ModulesExecuted -ge 5) { 25 } elseif ($metrics.ModulesExecuted -ge 3) { 20 } else { 10 }
    }
    
    $metrics.SystemHealthScore = $healthFactors.SuccessRate + $healthFactors.ErrorRate + $healthFactors.ProcessingEfficiency + $healthFactors.ModuleCompletion
    
    # Calculate security score based on telemetry and privacy modules
    $securityModules = @('telemetry-disable', 'system-optimization')
    $securityScore = 50 # Base score
    
    foreach ($secModule in $securityModules) {
        if ($ComprehensiveLogCollection -and $ComprehensiveLogCollection.Type2ExecutionLogs -and $ComprehensiveLogCollection.Type2ExecutionLogs.ContainsKey($secModule)) {
            $logContent = $ComprehensiveLogCollection.Type2ExecutionLogs[$secModule]
            if ($logContent -and $logContent -match 'successfully.*disabled|privacy.*enhanced|telemetry.*blocked') {
                $securityScore += 25
            }
        }
    }
    
    $metrics.SecurityScore = [math]::Min($securityScore, 100)
    
    Write-Verbose "Dashboard metrics calculated: $($metrics.SuccessfulTasks)/$($metrics.TotalTasks) tasks successful, $($metrics.ErrorCount) errors"
    
    return $metrics
}

<#
.SYNOPSIS
    Extract and parse all errors from execution logs
    Extracted from ReportGeneration.psm1 for split architecture
#>
function Get-ErrorsFromExecutionLogs {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$ComprehensiveLogCollection
    )
    
    Write-Verbose "Parsing errors from Type2 execution logs"
    
    $allErrors = @()
    
    if ($ComprehensiveLogCollection.Type2ExecutionLogs) {
        foreach ($moduleName in $ComprehensiveLogCollection.Type2ExecutionLogs.Keys) {
            $logContent = $ComprehensiveLogCollection.Type2ExecutionLogs[$moduleName]
            
            if ($logContent) {
                # Parse log entries - look for ERROR and FAILED entries
                $logLines = $logContent -split "`n"
                
                foreach ($line in $logLines) {
                    $line = $line.Trim()
                    
                    # Match log entry patterns: [TIMESTAMP] [LEVEL] [COMPONENT] Message
                    if ($line -match '^\[([^\]]+)\]\s+\[(ERROR|FAILED|WARN)\]\s+\[([^\]]+)\]\s+(.+)$') {
                        $timestamp = $matches[1]
                        $level = $matches[2]
                        $component = $matches[3]
                        $message = $matches[4]
                        
                        $allErrors += @{
                            Module    = $moduleName
                            Timestamp = $timestamp
                            Level     = $level
                            Component = $component
                            Message   = $message
                            Severity  = switch ($level) {
                                'ERROR' { 'High' }
                                'FAILED' { 'High' }
                                'WARN' { 'Medium' }
                                default { 'Low' }
                            }
                        }
                    }
                    # Also catch Write-LogEntry style ERROR messages
                    elseif ($line -match 'Write-LogEntry:.*\[ERROR\].*(.+)$') {
                        $message = $matches[1].Trim()
                        
                        $allErrors += @{
                            Module    = $moduleName
                            Timestamp = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
                            Level     = 'ERROR'
                            Component = if ($moduleName) { $moduleName.ToUpper() } else { 'UNKNOWN' }
                            Message   = $message
                            Severity  = 'High'
                        }
                    }
                    # Catch generic error patterns
                    elseif ($line -match '(error|failed|exception).*:(.+)' -and $line -notmatch '^\s*#') {
                        $message = $line.Trim()
                        
                        $allErrors += @{
                            Module    = $moduleName
                            Timestamp = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
                            Level     = 'ERROR'
                            Component = if ($moduleName) { $moduleName.ToUpper() } else { 'UNKNOWN' }
                            Message   = $message
                            Severity  = 'Medium'
                        }
                    }
                }
            }
        }
    }
    
    Write-Verbose "Found $($allErrors.Count) errors/warnings across all modules"
    
    # Sort by severity and timestamp
    return $allErrors | Sort-Object @{Expression = {
            switch ($_.Severity) {
                'High' { 1 }
                'Medium' { 2 }
                'Low' { 3 }
                default { 4 }
            }
        }
    }, Timestamp -Descending
}

#endregion

#region Analytics Functions

<#
.SYNOPSIS
    Generate execution summary analytics from task results
    Extracted from ReportGeneration.psm1 for split architecture
#>
function Get-ExecutionSummary {
    [CmdletBinding()]
    param([Array]$TaskResults)

    $successful = $TaskResults | Where-Object { $_.Success }
    $failed = $TaskResults | Where-Object { -not $_.Success }
    $totalDuration = ($TaskResults | Measure-Object Duration -Sum).Sum

    return @{
        TotalTasks      = $TaskResults.Count
        SuccessfulTasks = $successful.Count
        FailedTasks     = $failed.Count
        TotalDuration   = $totalDuration
        SuccessRate     = if ($TaskResults.Count -gt 0) {
            [math]::Round(($successful.Count / $TaskResults.Count) * 100, 1)
        }
        else { 0 }
    }
}

<#
.SYNOPSIS
    Generate system health analytics based on system inventory
    Extracted from ReportGeneration.psm1 for split architecture
#>
function Get-SystemHealthAnalytic {
    [CmdletBinding()]
    param([hashtable]$SystemInventory)
    
    if (-not $SystemInventory) { return @{} }
    
    $healthFactors = @{}
    $totalScore = 0
    $maxScore = 0
    
    # CPU Health (20 points)
    if ($SystemInventory.Hardware -and $SystemInventory.Hardware.Processor) {
        $cpuCores = $SystemInventory.Hardware.Processor.NumberOfCores
        $cpuScore = [math]::Min(20, $cpuCores * 2.5)
        $healthFactors.CPU = @{ Score = $cpuScore; MaxScore = 20; Status = if ($cpuScore -ge 15) { 'Good' } else { 'Needs Attention' } }
        $totalScore += $cpuScore
    }
    $maxScore += 20
    
    # Memory Health (25 points)
    if ($SystemInventory.SystemInfo -and $SystemInventory.SystemInfo.TotalPhysicalMemory) {
        $memoryGB = $SystemInventory.SystemInfo.TotalPhysicalMemory / 1GB
        $memoryScore = [math]::Min(25, $memoryGB * 3.125)
        $healthFactors.Memory = @{ Score = $memoryScore; MaxScore = 25; Status = if ($memoryScore -ge 20) { 'Good' } else { 'Needs Attention' } }
        $totalScore += $memoryScore
    }
    $maxScore += 25
    
    # Storage Health (20 points)
    if ($SystemInventory.Hardware -and $SystemInventory.Hardware.Storage) {
        $storageCount = $SystemInventory.Hardware.Storage.Count
        $storageScore = [math]::Min(20, $storageCount * 10)
        $healthFactors.Storage = @{ Score = $storageScore; MaxScore = 20; Status = if ($storageScore -ge 15) { 'Good' } else { 'Needs Attention' } }
        $totalScore += $storageScore
    }
    $maxScore += 20
    
    # OS Health (20 points) 
    if ($SystemInventory.OperatingSystem) {
        $osVersion = $SystemInventory.OperatingSystem.BuildNumber
        $osScore = if ($osVersion -ge 22000) { 20 } elseif ($osVersion -ge 19041) { 15 } else { 10 }
        $healthFactors.OperatingSystem = @{ Score = $osScore; MaxScore = 20; Status = if ($osScore -ge 18) { 'Good' } else { 'Needs Update' } }
        $totalScore += $osScore
    }
    $maxScore += 20
    
    # Services Health (15 points)
    if ($SystemInventory.Services) {
        $runningServices = ($SystemInventory.Services | Where-Object { $_.Status -eq 'Running' }).Count
        $serviceScore = [math]::Min(15, $runningServices / 10)
        $healthFactors.Services = @{ Score = $serviceScore; MaxScore = 15; Status = 'Monitoring' }
        $totalScore += $serviceScore
    }
    $maxScore += 15
    
    $overallScore = if ($maxScore -gt 0) { [math]::Round(($totalScore / $maxScore) * 100, 1) } else { 0 }
    
    return @{
        OverallScore    = $overallScore
        HealthFactors   = $healthFactors
        Recommendations = Get-HealthRecommendation -HealthFactors $healthFactors
    }
}

<#
.SYNOPSIS
    Generate performance analytics from task results
    Extracted from ReportGeneration.psm1 for split architecture
#>
function Get-PerformanceAnalytic {
    [CmdletBinding()]
    param([Array]$TaskResults)
    
    if (-not $TaskResults -or $TaskResults.Count -eq 0) { return @{} }
    
    $durations = $TaskResults | Where-Object { $_.Duration } | ForEach-Object { $_.Duration }
    $avgDuration = if ($durations) { ($durations | Measure-Object -Average).Average } else { 0 }
    $maxDuration = if ($durations) { ($durations | Measure-Object -Maximum).Maximum } else { 0 }
    $minDuration = if ($durations) { ($durations | Measure-Object -Minimum).Minimum } else { 0 }
    
    $typeAnalysis = $TaskResults | Group-Object Type | ForEach-Object {
        @{
            Type        = $_.Name
            Count       = $_.Count
            SuccessRate = [math]::Round((($_.Group | Where-Object Success).Count / $_.Count) * 100, 1)
            AvgDuration = [math]::Round((($_.Group | Measure-Object Duration -Average).Average), 2)
        }
    }
    
    return @{
        AverageDuration = [math]::Round($avgDuration, 2)
        MaxDuration     = [math]::Round($maxDuration, 2)
        MinDuration     = [math]::Round($minDuration, 2)
        TypeAnalysis    = $typeAnalysis
        TotalOperations = $TaskResults.Count
    }
}

<#
.SYNOPSIS
    Generate security analytics from system inventory
    Extracted from ReportGeneration.psm1 for split architecture
#>
function Get-SecurityAnalytic {
    [CmdletBinding()]
    param([hashtable]$SystemInventory)
    
    if (-not $SystemInventory) { return @{} }
    
    $securityScore = 85 # Base score
    $issues = @()
    $recommendations = @()
    
    # Check Windows version for security
    if ($SystemInventory.OperatingSystem -and $SystemInventory.OperatingSystem.BuildNumber -lt 19041) {
        $securityScore -= 15
        $issues += "Outdated Windows version"
        $recommendations += "Update to Windows 10 version 2004 or later"
    }
    
    # Check for potential security services
    if ($SystemInventory.Services) {
        $securityServices = $SystemInventory.Services | Where-Object { 
            $_.Name -like "*Defender*" -or $_.Name -like "*Security*" -or $_.Name -like "*Firewall*" 
        }
        
        $runningSecurityServices = ($securityServices | Where-Object { $_.Status -eq 'Running' }).Count
        if ($runningSecurityServices -lt 3) {
            $securityScore -= 10
            $issues += "Insufficient security services running"
            $recommendations += "Verify Windows Defender and Firewall are active"
        }
    }
    
    return @{
        SecurityScore   = $securityScore
        Issues          = $issues
        Recommendations = $recommendations
        Status          = if ($securityScore -ge 80) { 'Good' } elseif ($securityScore -ge 60) { 'Fair' } else { 'Poor' }
    }
}

<#
.SYNOPSIS
    Helper function to get health recommendations based on health factors
#>
function Get-HealthRecommendation {
    [CmdletBinding()]
    param([hashtable]$HealthFactors)
    
    $recommendations = @()
    
    if ($HealthFactors.CPU -and $HealthFactors.CPU.Score -lt 15) {
        $recommendations += "Consider upgrading CPU for better performance"
    }
    
    if ($HealthFactors.Memory -and $HealthFactors.Memory.Score -lt 20) {
        $recommendations += "Consider adding more RAM for better system performance"
    }
    
    if ($HealthFactors.Storage -and $HealthFactors.Storage.Score -lt 15) {
        $recommendations += "Consider adding additional storage or upgrading to SSD"
    }
    
    if ($HealthFactors.OperatingSystem -and $HealthFactors.OperatingSystem.Score -lt 18) {
        $recommendations += "Update to the latest Windows version for security and performance"
    }
    
    return $recommendations
}

#endregion

#region Log Parsing Functions

<#
.SYNOPSIS
    Main entry point for processing all maintenance logs
.DESCRIPTION
    Orchestrates the complete log processing pipeline:
    1. Scan raw log files from temp_files/data/ and temp_files/logs/
    2. Parse and analyze log content 
    3. Calculate metrics and analytics
    4. Generate standardized processed data files
.PARAMETER Force
    Force reprocessing even if processed data already exists
#>
function Invoke-LogProcessing {
    [CmdletBinding()]
    param(
        [Parameter()]
        [switch]$Force
    )
    
    Write-LogEntry -Level 'INFO' -Component 'LOG-PROCESSOR' -Message 'Starting comprehensive log processing pipeline'
    
    # FIRST: Organize bootstrap maintenance.log to proper location if needed
    $logOrganized = Move-MaintenanceLogToOrganized
    if (-not $logOrganized) {
        Write-LogEntry -Level 'WARNING' -Component 'LOG-PROCESSOR' -Message 'Failed to organize bootstrap maintenance.log, continuing with processing'
    }
    
    # Patch 5: Load aggregated results from LogAggregator
    Write-Information " Loading pre-aggregated results from LogAggregator..." -InformationAction Continue
    $aggregatedResults = $null
    $aggregatedResultsPath = Join-Path (Join-Path $env:MAINTENANCE_TEMP_ROOT 'processed') 'aggregated-results.json'
    
    if (Test-Path $aggregatedResultsPath) {
        try {
            $aggregatedResults = Get-Content -Path $aggregatedResultsPath -Raw | ConvertFrom-Json
            Write-Information "  [OK] Loaded aggregated results from: $aggregatedResultsPath" -InformationAction Continue
            Write-LogEntry -Level 'INFO' -Component 'LOG-PROCESSOR' -Message "Loaded pre-aggregated results containing $($aggregatedResults.ModuleResults.Count) module results"
        }
        catch {
            Write-Warning "  Failed to load aggregated results: $($_.Exception.Message)"
            Write-LogEntry -Level 'WARNING' -Component 'LOG-PROCESSOR' -Message "Failed to parse aggregated results: $($_.Exception.Message)"
        }
    }
    else {
        Write-Information "  [INFO] No pre-aggregated results found - will use traditional log parsing" -InformationAction Continue
    }
    
    try {
        # Initialize processed data paths
        $processedRoot = Initialize-ProcessedDataPaths
        
        # Collect raw data with defensive error handling
        Write-Information " Collecting raw log data..." -InformationAction Continue
        
        $type1AuditData = @{}
        try {
            $type1AuditData = Get-Type1AuditData
        }
        catch {
            Write-LogEntry -Level 'WARNING' -Component 'LOG-PROCESSOR' -Message "Failed to collect Type1 audit data: $($_.Exception.Message)"
        }
        
        $type2ExecutionLogs = @{}
        try {
            $type2ExecutionLogs = Get-Type2ExecutionLogs
        }
        catch {
            Write-LogEntry -Level 'WARNING' -Component 'LOG-PROCESSOR' -Message "Failed to collect Type2 execution logs: $($_.Exception.Message)"
        }
        
        $maintenanceLog = $null
        try {
            $maintenanceLog = Get-MaintenanceLog
        }
        catch {
            Write-LogEntry -Level 'WARNING' -Component 'LOG-PROCESSOR' -Message "Failed to collect maintenance log: $($_.Exception.Message)"
        }
        
        # Create comprehensive log collection
        $logCollection = @{
            Type1AuditData      = $type1AuditData
            Type2ExecutionLogs  = $type2ExecutionLogs
            MaintenanceLog      = $maintenanceLog
            SessionId           = (New-Guid).ToString()
            CollectionTimestamp = Get-Date
            ProcessedAt         = Get-Date
        }
        
        # Process logs and generate standardized data files
        Write-Information " Analyzing logs and calculating metrics..." -InformationAction Continue
        
        # Generate comprehensive log analysis with error handling
        $comprehensiveAnalysis = $null
        try {
            $comprehensiveAnalysis = Get-ComprehensiveLogAnalysis -ComprehensiveLogCollection $logCollection
        }
        catch {
            Write-LogEntry -Level 'WARNING' -Component 'LOG-PROCESSOR' -Message "Failed to generate comprehensive analysis: $($_.Exception.Message)"
            # Create minimal fallback structure
            $comprehensiveAnalysis = @{
                ExecutionMetrics    = @{}
                SystemModifications = @{}
                PerformanceData     = @{}
                Errors              = @{}
                Warnings            = @{}
                HealthMetrics       = @{}
                TaskDetails         = @{}
            }
        }
        
        # Calculate dashboard metrics (mock TaskResults - in real implementation this would come from orchestrator)
        $mockTaskResults = @()
        foreach ($moduleName in $type2ExecutionLogs.Keys) {
            $mockTaskResults += @{
                Success  = $true
                Duration = 1.5
                Type     = $moduleName
            }
        }
        
        $dashboardMetrics = @{}
        try {
            $dashboardMetrics = Get-ComprehensiveDashboardMetrics -ComprehensiveLogCollection $logCollection -TaskResults $mockTaskResults
        }
        catch {
            Write-LogEntry -Level 'WARNING' -Component 'LOG-PROCESSOR' -Message "Failed to calculate dashboard metrics: $($_.Exception.Message)"
        }
        
        # Extract errors analysis with error handling
        $errorsAnalysis = @()
        try {
            $errorsAnalysis = Get-ErrorsFromExecutionLogs -ComprehensiveLogCollection $logCollection
        }
        catch {
            Write-LogEntry -Level 'WARNING' -Component 'LOG-PROCESSOR' -Message "Failed to extract errors analysis: $($_.Exception.Message)"
        }
        
        # Generate analytics (requires system inventory - mock for now)
        $mockSystemInventory = @{
            OperatingSystem = @{ BuildNumber = 22000 }
            Hardware        = @{
                Processor = @{ NumberOfCores = 8 }
                Storage   = @(@{}, @{})
            }
            SystemInfo      = @{ TotalPhysicalMemory = 16GB }
            Services        = @(@{ Status = 'Running' }, @{ Status = 'Running' }, @{ Status = 'Running' })
        }
        
        $executionSummary = @{}
        try {
            $executionSummary = Get-ExecutionSummary -TaskResults $mockTaskResults
        }
        catch {
            Write-LogEntry -Level 'WARNING' -Component 'LOG-PROCESSOR' -Message "Failed to generate execution summary: $($_.Exception.Message)"
        }
        
        $systemHealthAnalytics = @{}
        try {
            $systemHealthAnalytics = Get-SystemHealthAnalytic -SystemInventory $mockSystemInventory
        }
        catch {
            Write-LogEntry -Level 'WARNING' -Component 'LOG-PROCESSOR' -Message "Failed to generate system health analytics: $($_.Exception.Message)"
        }
        
        $performanceAnalytics = @{}
        try {
            $performanceAnalytics = Get-PerformanceAnalytic -TaskResults $mockTaskResults
        }
        catch {
            Write-LogEntry -Level 'WARNING' -Component 'LOG-PROCESSOR' -Message "Failed to generate performance analytics: $($_.Exception.Message)"
        }
        
        $securityAnalytics = @{}
        try {
            $securityAnalytics = Get-SecurityAnalytic -SystemInventory $mockSystemInventory
        }
        catch {
            Write-LogEntry -Level 'WARNING' -Component 'LOG-PROCESSOR' -Message "Failed to generate security analytics: $($_.Exception.Message)"
        }
        
        # Save processed data to standardized JSON files (with defensive error handling)
        Write-Information " Saving processed data files..." -InformationAction Continue
        
        # Main metrics summary
        try {
            $metricsSummary = @{
                ProcessingMetadata    = @{
                    SessionId    = $logCollection.SessionId
                    ProcessedAt  = $logCollection.ProcessedAt
                    ModulesCount = @{
                        Type1 = if ($type1AuditData) { $type1AuditData.Keys.Count } else { 0 }
                        Type2 = if ($type2ExecutionLogs) { $type2ExecutionLogs.Keys.Count } else { 0 }
                    }
                }
                DashboardMetrics      = if ($dashboardMetrics) { $dashboardMetrics } else { @{} }
                ExecutionSummary      = if ($executionSummary) { $executionSummary } else { @{} }
                ComprehensiveAnalysis = if ($comprehensiveAnalysis) { $comprehensiveAnalysis } else { @{} }
            }
            $metricsSummary | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $processedRoot 'metrics-summary.json')
            Write-Information "   Metrics summary saved" -InformationAction Continue
        }
        catch {
            Write-LogEntry -Level 'ERROR' -Component 'LOG-PROCESSOR' -Message "Failed to save metrics-summary.json: $($_.Exception.Message)"
        }
        
        # Module-specific results
        try {
            $moduleResults = @{
                Type1AuditResults      = if ($type1AuditData) { $type1AuditData } else { @{} }
                Type2ExecutionAnalysis = if ($comprehensiveAnalysis -and $comprehensiveAnalysis.ExecutionMetrics) { $comprehensiveAnalysis.ExecutionMetrics } else { @{} }
                SystemModifications    = if ($comprehensiveAnalysis -and $comprehensiveAnalysis.SystemModifications) { $comprehensiveAnalysis.SystemModifications } else { @{} }
                PerformanceData        = if ($comprehensiveAnalysis -and $comprehensiveAnalysis.PerformanceData) { $comprehensiveAnalysis.PerformanceData } else { @{} }
            }
            $moduleResults | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $processedRoot 'module-results.json')
            Write-Information "   Module results saved" -InformationAction Continue
        }
        catch {
            Write-LogEntry -Level 'ERROR' -Component 'LOG-PROCESSOR' -Message "Failed to save module-results.json: $($_.Exception.Message)"
        }
        
        # Save maintenance log data separately for easy access
        try {
            if ($maintenanceLog -and $maintenanceLog.Available) {
                $maintenanceLog | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $processedRoot 'maintenance-log.json')
                Write-Information "   Maintenance log data saved" -InformationAction Continue
            }
            else {
                Write-Information "   No maintenance log data available" -InformationAction Continue
            }
        }
        catch {
            Write-LogEntry -Level 'ERROR' -Component 'LOG-PROCESSOR' -Message "Failed to save maintenance-log.json: $($_.Exception.Message)"
        }
        
        # Errors and warnings analysis
        try {
            $errorsData = @{
                AllErrors        = if ($errorsAnalysis) { $errorsAnalysis } else { @() }
                ErrorsByModule   = if ($comprehensiveAnalysis -and $comprehensiveAnalysis.Errors) { $comprehensiveAnalysis.Errors } else { @{} }
                WarningsByModule = if ($comprehensiveAnalysis -and $comprehensiveAnalysis.Warnings) { $comprehensiveAnalysis.Warnings } else { @{} }
                ErrorSummary     = @{
                    TotalErrors    = if ($errorsAnalysis) { $errorsAnalysis.Count } else { 0 }
                    HighSeverity   = if ($errorsAnalysis) { ($errorsAnalysis | Where-Object { $_.Severity -eq 'High' }).Count } else { 0 }
                    MediumSeverity = if ($errorsAnalysis) { ($errorsAnalysis | Where-Object { $_.Severity -eq 'Medium' }).Count } else { 0 }
                }
            }
            $errorsData | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $processedRoot 'errors-analysis.json')
            Write-Information "   Errors analysis saved" -InformationAction Continue
        }
        catch {
            Write-LogEntry -Level 'ERROR' -Component 'LOG-PROCESSOR' -Message "Failed to save errors-analysis.json: $($_.Exception.Message)"
        }
        
        # Health scores and analytics
        try {
            $healthScores = @{
                SystemHealth        = if ($systemHealthAnalytics) { $systemHealthAnalytics } else { @{} }
                Security            = if ($securityAnalytics) { $securityAnalytics } else { @{} }
                Performance         = if ($performanceAnalytics) { $performanceAnalytics } else { @{} }
                ModuleHealthMetrics = if ($comprehensiveAnalysis -and $comprehensiveAnalysis.HealthMetrics) { $comprehensiveAnalysis.HealthMetrics } else { @{} }
            }
            $healthScores | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $processedRoot 'health-scores.json')
            Write-Information "   Health scores saved" -InformationAction Continue
        }
        catch {
            Write-LogEntry -Level 'ERROR' -Component 'LOG-PROCESSOR' -Message "Failed to save health-scores.json: $($_.Exception.Message)"
        }
        
        # Save individual module data to module-specific subdirectory
        try {
            $moduleSpecificDir = Join-Path $processedRoot 'module-specific'
            if ($type1AuditData -and $type1AuditData.Keys.Count -gt 0) {
                foreach ($moduleName in $type1AuditData.Keys) {
                    try {
                        $moduleData = @{
                            AuditData        = if ($type1AuditData[$moduleName]) { $type1AuditData[$moduleName] } else { @{} }
                            ExecutionMetrics = if ($comprehensiveAnalysis -and $comprehensiveAnalysis.ExecutionMetrics -and $comprehensiveAnalysis.ExecutionMetrics[$moduleName]) { $comprehensiveAnalysis.ExecutionMetrics[$moduleName] } else { @{} }
                            TaskDetails      = if ($comprehensiveAnalysis -and $comprehensiveAnalysis.TaskDetails -and $comprehensiveAnalysis.TaskDetails[$moduleName]) { $comprehensiveAnalysis.TaskDetails[$moduleName] } else { @{} }
                            Modifications    = if ($comprehensiveAnalysis -and $comprehensiveAnalysis.SystemModifications -and $comprehensiveAnalysis.SystemModifications[$moduleName]) { $comprehensiveAnalysis.SystemModifications[$moduleName] } else { @{} }
                        }
                        $moduleData | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $moduleSpecificDir "$moduleName.json")
                    }
                    catch {
                        Write-LogEntry -Level 'WARNING' -Component 'LOG-PROCESSOR' -Message "Failed to save module-specific data for ${moduleName}: $($_.Exception.Message)"
                    }
                }
                Write-Information "   Module-specific data files saved" -InformationAction Continue
            }
        }
        catch {
            Write-LogEntry -Level 'ERROR' -Component 'LOG-PROCESSOR' -Message "Failed to save module-specific data: $($_.Exception.Message)"
        }
        
        Write-Information " Log processing completed successfully" -InformationAction Continue
        Write-LogEntry -Level 'SUCCESS' -Component 'LOG-PROCESSOR' -Message 'Log processing pipeline completed' -Data @{
            Type1Modules      = $type1AuditData.Keys.Count
            Type2Modules      = $type2ExecutionLogs.Keys.Count
            ProcessedDataPath = $processedRoot
        }
        
        return @{
            Success           = $true
            ProcessedDataPath = $processedRoot
            ModulesProcessed  = @{
                Type1Count = $type1AuditData.Keys.Count
                Type2Count = $type2ExecutionLogs.Keys.Count
            }
            LogCollection     = $logCollection
        }
    }
    catch {
        Write-LogEntry -Level 'ERROR' -Component 'LOG-PROCESSOR' -Message "Log processing failed: $($_.Exception.Message)"
        return @{
            Success = $false
            Error   = $_.Exception.Message
        }
    }
}

#endregion

#region Module Export



#region Enhanced Error Handling Framework

<#
.SYNOPSIS
    Enhanced error handling framework for graceful degradation
.DESCRIPTION
    Provides centralized error handling with recovery strategies for LogProcessor operations
#>
function Invoke-SafeLogOperation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$OperationName,
        
        [Parameter(Mandatory)]
        [ScriptBlock]$Operation,
        
        [Parameter()]
        [hashtable]$Parameters = @{},
        
        [Parameter()]
        [ScriptBlock]$FallbackOperation,
        
        [Parameter()]
        [string]$FallbackMessage,
        
        [Parameter()]
        [switch]$ContinueOnError
    )
    
    $result = @{
        Success       = $false
        Data          = $null
        Error         = $null
        OperationName = $OperationName
        FallbackUsed  = $false
    }
    
    try {
        Write-Verbose "Executing operation: $OperationName"
        $result.Data = & $Operation @Parameters
        $result.Success = $true
        Write-Verbose " Operation '$OperationName' completed successfully"
    }
    catch {
        $result.Error = $_.Exception.Message
        Write-LogEntry -Level 'ERROR' -Component 'LOG-PROCESSOR' -Message "Operation '$OperationName' failed: $($_.Exception.Message)"
        
        # Try fallback if available
        if ($FallbackOperation) {
            try {
                Write-LogEntry -Level 'WARNING' -Component 'LOG-PROCESSOR' -Message "Attempting fallback for operation: $OperationName"
                $result.Data = & $FallbackOperation @Parameters
                $result.Success = $true
                $result.FallbackUsed = $true
                
                if ($FallbackMessage) {
                    Write-LogEntry -Level 'WARNING' -Component 'LOG-PROCESSOR' -Message $FallbackMessage
                }
            }
            catch {
                Write-LogEntry -Level 'ERROR' -Component 'LOG-PROCESSOR' -Message "Fallback for '$OperationName' also failed: $($_.Exception.Message)"
                if (-not $ContinueOnError) {
                    throw "Critical operation '$OperationName' failed: Primary and fallback operations both failed"
                }
            }
        }
        elseif (-not $ContinueOnError) {
            throw
        }
    }
    
    return $result
}

<#
.SYNOPSIS
    Validates JSON content for corruption and structure issues
#>
function Test-JsonDataIntegrity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$JsonPath,
        
        [Parameter()]
        [string[]]$RequiredProperties
    )
    
    $validation = @{
        IsValid               = $false
        HasRequiredProperties = $false
        FileExists            = $false
        IsReadable            = $false
        IsValidJson           = $false
        ValidationErrors      = @()
        Data                  = $null
    }
    
    try {
        # Check file existence
        if (-not (Test-Path $JsonPath)) {
            $validation.ValidationErrors += "File does not exist: $JsonPath"
            return $validation
        }
        $validation.FileExists = $true
        
        # Check file readability
        try {
            $content = Get-Content $JsonPath -Raw -ErrorAction Stop
            $validation.IsReadable = $true
        }
        catch {
            $validation.ValidationErrors += "File is not readable: $($_.Exception.Message)"
            return $validation
        }
        
        # Check JSON validity
        try {
            $jsonData = $content | ConvertFrom-Json -ErrorAction Stop
            $validation.IsValidJson = $true
            $validation.Data = $jsonData
        }
        catch {
            $validation.ValidationErrors += "Invalid JSON format: $($_.Exception.Message)"
            return $validation
        }
        
        # Check required properties
        if ($RequiredProperties -and $RequiredProperties.Count -gt 0) {
            $missingProperties = @()
            foreach ($property in $RequiredProperties) {
                # Null safety: check if jsonData exists and has PSObject properties
                if ($null -eq $jsonData -or $null -eq $jsonData.PSObject -or $null -eq $jsonData.PSObject.Properties) {
                    $missingProperties += $property
                }
                elseif (-not ($jsonData.PSObject.Properties.Name -contains $property)) {
                    $missingProperties += $property
                }
            }
            
            if ($missingProperties.Count -eq 0) {
                $validation.HasRequiredProperties = $true
            }
            else {
                $validation.ValidationErrors += "Missing required properties: $($missingProperties -join ', ')"
            }
        }
        else {
            $validation.HasRequiredProperties = $true  # No requirements specified
        }
        
        # Overall validation
        $validation.IsValid = $validation.FileExists -and $validation.IsReadable -and $validation.IsValidJson -and $validation.HasRequiredProperties
        
        return $validation
    }
    catch {
        $validation.ValidationErrors += "Validation failed: $($_.Exception.Message)"
        return $validation
    }
}

<#
.SYNOPSIS
    Safe JSON loading with error recovery
#>
function Import-SafeJsonData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$JsonPath,
        
        [Parameter()]
        [string[]]$RequiredProperties,
        
        [Parameter()]
        [hashtable]$DefaultData = @{},
        
        [Parameter()]
        [switch]$ContinueOnError
    )
    
    $operation = {
        param($JsonPath, $RequiredProperties)
        
        # Validate first
        $validation = Test-JsonDataIntegrity -JsonPath $JsonPath -RequiredProperties $RequiredProperties
        
        if ($validation.IsValid) {
            return $validation.Data
        }
        else {
            throw "JSON validation failed: $($validation.ValidationErrors -join '; ')"
        }
    }
    
    $fallback = {
        param($JsonPath, $RequiredProperties, $DefaultData)
        Write-LogEntry -Level 'WARNING' -Component 'LOG-PROCESSOR' -Message "Using default data for failed JSON load: $(Split-Path -Leaf $JsonPath)"
        return $DefaultData
    }
    
    $result = Invoke-SafeLogOperation -OperationName "Import JSON: $(Split-Path -Leaf $JsonPath)" -Operation $operation -Parameters @{
        JsonPath           = $JsonPath
        RequiredProperties = $RequiredProperties
    } -FallbackOperation $fallback -FallbackMessage "Using default data due to JSON load failure" -ContinueOnError:$ContinueOnError
    
    return $result.Data
}

<#
.SYNOPSIS
    Safe directory scanning with error recovery
#>
function Get-SafeDirectoryContents {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$DirectoryPath,
        
        [Parameter()]
        [string]$Filter = '*',
        
        [Parameter()]
        [switch]$FilesOnly,
        
        [Parameter()]
        [switch]$DirectoriesOnly
    )
    
    $operation = {
        param($DirectoryPath, $Filter, $FilesOnly, $DirectoriesOnly)
        
        if (-not (Test-Path $DirectoryPath -PathType Container)) {
            throw "Directory does not exist or is not accessible: $DirectoryPath"
        }
        
        $getChildItemParams = @{
            Path        = $DirectoryPath
            Filter      = $Filter
            ErrorAction = 'Stop'
        }
        
        if ($FilesOnly) { $getChildItemParams.File = $true }
        if ($DirectoriesOnly) { $getChildItemParams.Directory = $true }
        
        return Get-ChildItem @getChildItemParams
    }
    
    $fallback = {
        Write-LogEntry -Level 'WARNING' -Component 'LOG-PROCESSOR' -Message "Directory scan failed, returning empty collection"
        return @()
    }
    
    $result = Invoke-SafeLogOperation -OperationName "Scan Directory: $(Split-Path -Leaf $DirectoryPath)" -Operation $operation -Parameters @{
        DirectoryPath   = $DirectoryPath
        Filter          = $Filter
        FilesOnly       = $FilesOnly
        DirectoriesOnly = $DirectoriesOnly
    } -FallbackOperation $fallback -ContinueOnError
    
    return $result.Data
}

<#
.SYNOPSIS
    Retrieves module execution data from JSON logs and summaries

.DESCRIPTION
    Reads structured JSON logs (execution-data.json) and execution summaries
    (execution-summary.json) created by Type2 modules with structured logging.
    Provides easy access to structured log data for report generation.

.PARAMETER ModuleName
    Name of the module to retrieve data for (e.g., 'BloatwareRemoval')

.OUTPUTS
    Hashtable with Summary, LogEntries, and HasStructuredData properties

.EXAMPLE
    $data = Get-ModuleExecutionDataFromJson -ModuleName 'BloatwareRemoval'
    if ($data.HasStructuredData) {
        Write-Host "Processed: $($data.Summary.Results.ItemsProcessed)"
    }
#>
function Get-ModuleExecutionDataFromJson {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('BloatwareRemoval', 'EssentialApps', 'SystemOptimization', 'TelemetryDisable', 'WindowsUpdates', 'AppUpgrade', 'SystemInventory', 
            'bloatware-removal', 'essential-apps', 'system-optimization', 'telemetry-disable', 'windows-updates', 'app-upgrade', 'system-inventory')]
        [string]$ModuleName
    )
    
    try {
        # Normalize module name to directory format (lowercase with hyphens)
        $normalizedName = switch -Regex ($ModuleName) {
            '^BloatwareRemoval$' { 'bloatware-removal' }
            '^EssentialApps$' { 'essential-apps' }
            '^SystemOptimization$' { 'system-optimization' }
            '^TelemetryDisable$' { 'telemetry-disable' }
            '^WindowsUpdates$' { 'windows-updates' }
            '^AppUpgrade$' { 'app-upgrade' }
            '^SystemInventory$' { 'system-inventory' }
            default { $ModuleName.ToLower() }
        }
        
        $logsPath = Join-Path (Get-MaintenancePath 'TempRoot') "logs\$normalizedName"
        
        if (-not (Test-Path $logsPath)) {
            Write-LogEntry -Level 'WARNING' -Component 'LOG-PROCESSOR' -Message "Module logs directory not found: $logsPath"
            return @{
                Summary           = $null
                LogEntries        = @()
                HasStructuredData = $false
                ModuleName        = $ModuleName
                Error             = "Logs directory not found"
            }
        }
        
        # Load execution summary
        $summaryPath = Join-Path $logsPath 'execution-summary.json'
        $summary = if (Test-Path $summaryPath) {
            try {
                Get-Content $summaryPath -Raw | ConvertFrom-Json
            }
            catch {
                Write-LogEntry -Level 'WARNING' -Component 'LOG-PROCESSOR' -Message "Failed to parse summary JSON: $($_.Exception.Message)"
                $null
            }
        }
        else {
            Write-LogEntry -Level 'DEBUG' -Component 'LOG-PROCESSOR' -Message "No execution summary found for $ModuleName"
            $null
        }
        
        # Load detailed log entries
        $jsonLogPath = Join-Path $logsPath 'execution-data.json'
        $logEntries = if (Test-Path $jsonLogPath) {
            try {
                $jsonContent = Get-Content $jsonLogPath -Raw | ConvertFrom-Json
                # Ensure it's an array
                if ($jsonContent -is [System.Collections.IEnumerable] -and $jsonContent -isnot [string]) {
                    @($jsonContent)
                }
                else {
                    @($jsonContent)
                }
            }
            catch {
                Write-LogEntry -Level 'WARNING' -Component 'LOG-PROCESSOR' -Message "Failed to parse execution log JSON: $($_.Exception.Message)"
                @()
            }
        }
        else {
            Write-LogEntry -Level 'DEBUG' -Component 'LOG-PROCESSOR' -Message "No JSON execution log found for $ModuleName"
            @()
        }
        
        return @{
            Summary           = $summary
            LogEntries        = $logEntries
            HasStructuredData = ($null -ne $summary -and $logEntries.Count -gt 0)
            ModuleName        = $ModuleName
            LogsPath          = $logsPath
            SummaryPath       = $summaryPath
            JsonLogPath       = $jsonLogPath
        }
    }
    catch {
        Write-LogEntry -Level 'ERROR' -Component 'LOG-PROCESSOR' -Message "Failed to load JSON data for ${ModuleName}: $($_.Exception.Message)"
        return @{
            Summary           = $null
            LogEntries        = @()
            HasStructuredData = $false
            ModuleName        = $ModuleName
            Error             = $_.Exception.Message
        }
    }
}

#endregion

#endregion

# Export main functions for LogProcessor module - placed at end after all function definitions
Export-ModuleMember -Function @(
    'Invoke-LogProcessing',
    'Initialize-ProcessedDataPaths',
    'Move-MaintenanceLogToOrganized',
    'Get-Type1AuditData', 
    'Get-Type2ExecutionLogs',
    'Get-MaintenanceLog',
    'Get-ModuleExecutionData',
    'Get-ModuleExecutionDataFromJson',
    'ConvertFrom-ModuleExecutionLog',
    'ConvertFrom-AuditData',
    'Get-ComprehensiveLogAnalysis',
    'Get-ComprehensiveDashboardMetrics',
    'Get-ErrorsFromExecutionLogs',
    'Get-ExecutionSummary',
    'Get-SystemHealthAnalytic',
    'Get-PerformanceAnalytic',
    'Get-SecurityAnalytic',
    'Invoke-SafeLogOperation',
    'Test-JsonDataIntegrity',
    'Import-SafeJsonData',
    'Get-SafeDirectoryContents',
    'Invoke-BatchProcessing'
)
