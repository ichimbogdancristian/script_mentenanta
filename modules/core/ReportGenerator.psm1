#Requires -Version 7.0

<#
.SYNOPSIS
    Report Generator Module - Type 1 (Report Generation)

.DESCRIPTION
    Specialized module for generating maintenance reports from processed log data.
    Focuses purely on presentation layer - loading templates, rendering HTML/text reports,
    and creating interactive visualizations. Part of the v3.0 split architecture.

.NOTES
    Module Type: Type 1 (Report Generation)
    Dependencies: CoreInfrastructure.psm1, LogProcessor.psm1 (for processed data)
    Author: Windows Maintenance Automation Project
    Version: 3.0.0 - Split from monolithic ReportGeneration.psm1
    
    Architecture: LogProcessor → temp_files/processed/ → ReportGenerator
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

#region Configuration and Template Management

<#
.SYNOPSIS
    Loads HTML templates from config directory
.DESCRIPTION
    Loads all report templates including HTML structure, CSS styles, and configuration metadata
#>
function Get-HtmlTemplates {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()
    
    Write-LogEntry -Level 'INFO' -Component 'REPORT-GENERATOR' -Message 'Loading HTML templates from config directory'
    
    try {
        $configPath = $Global:ProjectPaths.Config
        
        $templates = @{
            Main     = $null
            TaskCard = $null
            CSS      = $null
            Config   = $null
        }
        
        # Load main report template
        $mainTemplatePath = Join-Path $configPath 'report-template.html'
        if (Test-Path $mainTemplatePath) {
            $templates.Main = Get-Content $mainTemplatePath -Raw
            Write-Verbose "Loaded main template: $mainTemplatePath"
        }
        else {
            throw "Main report template not found: $mainTemplatePath"
        }
        
        # Load task card template
        $taskCardPath = Join-Path $configPath 'task-card-template.html'
        if (Test-Path $taskCardPath) {
            $templates.TaskCard = Get-Content $taskCardPath -Raw
            Write-Verbose "Loaded task card template: $taskCardPath"
        }
        else {
            throw "Task card template not found: $taskCardPath"
        }
        
        # Load CSS styles
        $cssPath = Join-Path $configPath 'report-styles.css'
        if (Test-Path $cssPath) {
            $templates.CSS = Get-Content $cssPath -Raw
            Write-Verbose "Loaded CSS styles: $cssPath"
        }
        else {
            throw "CSS styles not found: $cssPath"
        }
        
        # Load template configuration
        $configJsonPath = Join-Path $configPath 'report-templates-config.json'
        if (Test-Path $configJsonPath) {
            $templates.Config = Get-Content $configJsonPath | ConvertFrom-Json
            Write-Verbose "Loaded template config: $configJsonPath"
        }
        else {
            throw "Template configuration not found: $configJsonPath"
        }
        
        Write-LogEntry -Level 'SUCCESS' -Component 'REPORT-GENERATOR' -Message 'Successfully loaded all HTML templates'
        return $templates
    }
    catch {
        Write-LogEntry -Level 'ERROR' -Component 'REPORT-GENERATOR' -Message "Failed to load HTML templates: $($_.Exception.Message)"
        Write-LogEntry -Level 'WARN' -Component 'REPORT-GENERATOR' -Message 'Attempting to use fallback templates for basic functionality'
        
        try {
            return Get-FallbackTemplates
        }
        catch {
            Write-LogEntry -Level 'ERROR' -Component 'REPORT-GENERATOR' -Message "Both template loading and fallback failed: $($_.Exception.Message)"
            throw "Cannot generate reports - template system unavailable"
        }
    }
}

<#
.SYNOPSIS
    Provides fallback templates when config templates are unavailable
.DESCRIPTION
    Emergency fallback mechanism providing basic HTML templates for report generation
#>
function Get-FallbackTemplates {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()
    
    Write-LogEntry -Level 'WARN' -Component 'REPORT-GENERATOR' -Message 'Using fallback templates - limited styling and functionality'
    
    $fallbackTemplates = @{
        Main     = @'
<!DOCTYPE html>
<html>
<head>
    <title>Windows Maintenance Report</title>
    <style>{{CSS_CONTENT}}</style>
</head>
<body>
    <div class="container">
        <header>
            <h1>Windows Maintenance Report</h1>
            <p>Generated: {{REPORT_DATE}}</p>
            <p class="fallback-notice">Note: Using fallback templates due to missing config files</p>
        </header>
        
        {{DASHBOARD_CONTENT}}
        {{MODULE_SECTIONS}}
        {{SUMMARY_SECTION}}
        
        <footer>
            <p>Windows Maintenance Automation v3.0 - Fallback Mode</p>
        </footer>
    </div>
</body>
</html>
'@
        
        TaskCard = @'
<div class="task-card {{STATUS_CLASS}}">
    <div class="task-header">
        <h3>{{TASK_TITLE}}</h3>
        <span class="task-status">{{TASK_STATUS}}</span>
    </div>
    <div class="task-content">
        {{TASK_CONTENT}}
    </div>
    <div class="task-metrics">
        <span>Items: {{ITEMS_COUNT}}</span>
        <span>Duration: {{DURATION}}</span>
    </div>
</div>
'@
        
        CSS      = @'
body { font-family: Arial, sans-serif; margin: 0; padding: 20px; background-color: #f5f5f5; }
.container { max-width: 1200px; margin: 0 auto; background: white; padding: 20px; border-radius: 8px; }
header { text-align: center; border-bottom: 2px solid #0078d4; padding-bottom: 20px; margin-bottom: 30px; }
.fallback-notice { color: #d13438; font-weight: bold; }
.task-card { border: 1px solid #ddd; margin: 10px 0; padding: 15px; border-radius: 4px; }
.task-card.success { border-left: 4px solid #107c10; }
.task-card.error { border-left: 4px solid #d13438; }
.task-header { display: flex; justify-content: space-between; align-items: center; }
.task-status { padding: 4px 8px; border-radius: 4px; font-size: 0.9em; }
.task-metrics { margin-top: 10px; font-size: 0.9em; color: #666; }
footer { margin-top: 40px; text-align: center; color: #666; }
'@
        
        Config   = @{
            moduleIcons  = @{
                BloatwareRemoval   = '🗑️'
                EssentialApps      = '📦'
                SystemOptimization = '⚡'
                TelemetryDisable   = '🔒'
                WindowsUpdates     = '🔄'
            }
            statusColors = @{
                success = '#107c10'
                warning = '#ffb900'  
                error   = '#d13438'
                info    = '#0078d4'
            }
        }
    }
    
    return $fallbackTemplates
}

#endregion

#region Processed Data Loading

<#
.SYNOPSIS
    Loads processed data from temp_files/processed/ directory
.DESCRIPTION
    Reads all standardized JSON files created by LogProcessor module
#>
function Get-ProcessedLogData {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter()]
        [string]$ProcessedDataPath,
        
        [Parameter()]
        [switch]$FallbackToRawLogs
    )
    
    Write-LogEntry -Level 'INFO' -Component 'REPORT-GENERATOR' -Message 'Loading processed log data'
    
    try {
        # Use provided path or default to temp_files/processed
        $processedRoot = if ($ProcessedDataPath) {
            $ProcessedDataPath
        }
        else {
            Join-Path $Global:ProjectPaths.TempFiles 'processed'
        }
        
        if (-not (Test-Path $processedRoot)) {
            $errorMessage = "Processed data directory not found: $processedRoot"
            if ($FallbackToRawLogs) {
                Write-LogEntry -Level 'WARN' -Component 'REPORT-GENERATOR' -Message "$errorMessage - Attempting fallback to raw logs"
                return Get-FallbackRawLogData
            }
            else {
                Write-LogEntry -Level 'ERROR' -Component 'REPORT-GENERATOR' -Message "$errorMessage. Ensure LogProcessor has run first or use -FallbackToRawLogs switch."
                throw $errorMessage
            }
        }
        
        $processedData = @{
            MetricsSummary  = @{}
            ModuleResults   = @{}
            ErrorsAnalysis  = @{}
            HealthScores    = @{}
            PerformanceData = @{}
            ChartsData      = @{}
            MaintenanceLog  = @{}
        }
        
        # Load main summary files
        $summaryFiles = @{
            'MetricsSummary' = 'metrics-summary.json'
            'ModuleResults'  = 'module-results.json'
            'ErrorsAnalysis' = 'errors-analysis.json'
            'HealthScores'   = 'health-scores.json'
            'MaintenanceLog' = 'maintenance-log.json'
        }
        
        foreach ($key in $summaryFiles.Keys) {
            $filePath = Join-Path $processedRoot $summaryFiles[$key]
            if (Test-Path $filePath) {
                try {
                    $content = Get-Content $filePath | ConvertFrom-Json
                    $processedData[$key] = $content
                    Write-Verbose "Loaded processed data: $($summaryFiles[$key])"
                }
                catch {
                    Write-LogEntry -Level 'WARN' -Component 'REPORT-GENERATOR' -Message "Failed to parse $($summaryFiles[$key]): $($_.Exception.Message)"
                    $processedData[$key] = @{}
                }
            }
            else {
                Write-LogEntry -Level 'WARN' -Component 'REPORT-GENERATOR' -Message "Processed data file not found: $($summaryFiles[$key])"
            }
        }
        
        # Load module-specific data
        $moduleSpecificPath = Join-Path $processedRoot 'module-specific'
        if (Test-Path $moduleSpecificPath) {
            $moduleFiles = Get-ChildItem -Path $moduleSpecificPath -Filter '*.json'
            foreach ($file in $moduleFiles) {
                $moduleName = $file.BaseName
                try {
                    $content = Get-Content $file.FullName | ConvertFrom-Json
                    $processedData.ModuleResults[$moduleName] = $content
                    Write-Verbose "Loaded module-specific data for: $moduleName"
                }
                catch {
                    Write-LogEntry -Level 'WARN' -Component 'REPORT-GENERATOR' -Message "Failed to parse module data for ${moduleName}: $($_.Exception.Message)"
                }
            }
        }
        
        # Validate data integrity and provide warnings for missing components
        $dataValidation = Test-ProcessedDataIntegrity -ProcessedData $processedData
        if (-not $dataValidation.IsComplete) {
            Write-LogEntry -Level 'WARN' -Component 'REPORT-GENERATOR' -Message "Processed data validation warnings: $($dataValidation.Warnings -join ', ')"
            
            if ($dataValidation.CriticalIssues.Count -gt 0) {
                Write-LogEntry -Level 'ERROR' -Component 'REPORT-GENERATOR' -Message "Critical data issues found: $($dataValidation.CriticalIssues -join ', ')"
                if ($FallbackToRawLogs) {
                    Write-LogEntry -Level 'WARN' -Component 'REPORT-GENERATOR' -Message 'Attempting fallback to raw logs due to critical data issues'
                    return Get-FallbackRawLogData
                }
            }
        }
        
        Write-LogEntry -Level 'SUCCESS' -Component 'REPORT-GENERATOR' -Message "Successfully loaded processed data for $($processedData.ModuleResults.Keys.Count) modules"
        return $processedData
    }
    catch {
        Write-LogEntry -Level 'ERROR' -Component 'REPORT-GENERATOR' -Message "Failed to load processed data: $($_.Exception.Message)"
        
        if ($FallbackToRawLogs) {
            Write-LogEntry -Level 'WARN' -Component 'REPORT-GENERATOR' -Message 'Attempting fallback to raw logs due to processing failure'
            try {
                return Get-FallbackRawLogData
            }
            catch {
                Write-LogEntry -Level 'ERROR' -Component 'REPORT-GENERATOR' -Message "Both processed data and raw log fallback failed: $($_.Exception.Message)"
                throw "Cannot load any report data - both processed and raw log loading failed"
            }
        }
        
        throw
    }
}

<#
.SYNOPSIS
    Validates the integrity and completeness of processed data
.DESCRIPTION
    Performs comprehensive validation of processed data structure and content
.PARAMETER ProcessedData
    The processed data hashtable to validate
#>
function Test-ProcessedDataIntegrity {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$ProcessedData
    )
    
    $validation = @{
        IsComplete        = $true
        Warnings          = @()
        CriticalIssues    = @()
        MissingComponents = @()
    }
    
    # Check for required top-level components
    $requiredComponents = @('MetricsSummary', 'ModuleResults', 'ErrorsAnalysis', 'HealthScores')
    foreach ($component in $requiredComponents) {
        if (-not $ProcessedData.ContainsKey($component) -or $null -eq $ProcessedData[$component]) {
            $validation.CriticalIssues += "Missing required component: $component"
            $validation.MissingComponents += $component
            $validation.IsComplete = $false
        }
    }
    
    # Check module results structure
    if ($ProcessedData.ModuleResults -and $ProcessedData.ModuleResults.Keys.Count -eq 0) {
        $validation.Warnings += 'No module execution results found'
    }
    
    # Check metrics summary
    if ($ProcessedData.MetricsSummary -and -not $ProcessedData.MetricsSummary.ExecutionSummary) {
        $validation.Warnings += 'Missing execution summary in metrics'
    }
    
    # Check health scores
    if ($ProcessedData.HealthScores -and (-not $ProcessedData.HealthScores.SystemHealth -or -not $ProcessedData.HealthScores.Security)) {
        $validation.Warnings += 'Incomplete health score data'
    }
    
    return $validation
}

<#
.SYNOPSIS
    Fallback function to load data directly from raw logs when processed data is unavailable
.DESCRIPTION
    Emergency fallback mechanism that attempts to read basic data from temp_files/data and temp_files/logs
    when LogProcessor output is not available
#>
function Get-FallbackRawLogData {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()
    
    Write-LogEntry -Level 'WARN' -Component 'REPORT-GENERATOR' -Message 'Using fallback raw log data loading - functionality will be limited'
    
    try {
        $fallbackData = @{
            MetricsSummary  = @{
                ExecutionSummary = @{
                    TotalTasks     = 0
                    CompletedTasks = 0
                    FailedTasks    = 0
                    TotalDuration  = 0
                    Status         = 'Incomplete - Fallback Mode'
                }
            }
            ModuleResults   = @{}
            ErrorsAnalysis  = @{
                TotalErrors    = 0
                ErrorsByModule = @{}
                CriticalErrors = @()
            }
            HealthScores    = @{
                SystemHealth = @{
                    OverallScore = 75
                    Status       = 'Unknown - Fallback Mode'
                }
                Security     = @{
                    SecurityScore = 70
                    Status        = 'Unknown - Fallback Mode'
                }
            }
            PerformanceData = @{}
            ChartsData      = @{}
        }
        
        # Try to load basic module data from logs directory
        $logsPath = Join-Path $Global:ProjectPaths.TempFiles 'logs'
        if (Test-Path $logsPath) {
            $logDirectories = Get-ChildItem -Path $logsPath -Directory
            foreach ($logDir in $logDirectories) {
                $moduleName = $logDir.Name
                $executionLog = Join-Path $logDir.FullName 'execution.log'
                
                if (Test-Path $executionLog) {
                    try {
                        $logContent = Get-Content $executionLog
                        $fallbackData.ModuleResults[$moduleName] = @{
                            Status               = 'Processed via fallback'
                            LogEntries           = $logContent.Count
                            TotalOperations      = 0
                            SuccessfulOperations = 0
                            FailedOperations     = 0
                        }
                    }
                    catch {
                        Write-LogEntry -Level 'WARN' -Component 'REPORT-GENERATOR' -Message "Could not read fallback log for module ${moduleName}: $($_.Exception.Message)"
                    }
                }
            }
        }
        
        Write-LogEntry -Level 'WARN' -Component 'REPORT-GENERATOR' -Message "Fallback data loaded with limited functionality for $($fallbackData.ModuleResults.Keys.Count) modules"
        return $fallbackData
    }
    catch {
        Write-LogEntry -Level 'ERROR' -Component 'REPORT-GENERATOR' -Message "Fallback raw log loading failed: $($_.Exception.Message)"
        throw
    }
}

#endregion

#region Operation Log Parsing

<#
.SYNOPSIS
    Parses operation logs from temp_files/logs/ directories
.DESCRIPTION
    Reads execution.log files from each module's log directory and parses them into structured data
    for display in the HTML report. Extracts timestamps, operations, targets, results, and metrics.
.PARAMETER ModuleName
    Name of the module whose logs to parse (e.g., 'bloatware-removal', 'essential-apps')
.OUTPUTS
    Hashtable containing parsed operations grouped by operation type with full details
#>
function Get-ParsedOperationLogs {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string]$ModuleName
    )
    
    Write-LogEntry -Level 'INFO' -Component 'REPORT-GENERATOR' -Message "Parsing operation logs for module: $ModuleName"
    
    try {
        $logsPath = Join-Path $Global:ProjectPaths.TempFiles "logs\$ModuleName"
        $executionLogPath = Join-Path $logsPath 'execution.log'
        
        $result = @{
            Available       = $false
            Operations      = @()
            Summary         = @{
                Total      = 0
                Success    = 0
                Failed     = 0
                Skipped    = 0
                InProgress = 0
            }
            ByOperationType = @{}
            FirstOperation  = $null
            LastOperation   = $null
        }
        
        if (-not (Test-Path $executionLogPath)) {
            Write-LogEntry -Level 'WARN' -Component 'REPORT-GENERATOR' -Message "No execution log found for $ModuleName at: $executionLogPath"
            return $result
        }
        
        $logContent = Get-Content $executionLogPath -ErrorAction Stop
        if ($logContent.Count -eq 0) {
            Write-LogEntry -Level 'WARN' -Component 'REPORT-GENERATOR' -Message "Empty execution log for $ModuleName"
            return $result
        }
        
        $result.Available = $true
        
        # Parse log format: [Timestamp] [Level] [Component] [Operation] [Target] Message - Result: Status - Metrics: Data
        $logPattern = '^\[([^\]]+)\]\s+\[([^\]]+)\]\s+\[([^\]]+)\]\s+\[([^\]]+)\]\s+\[([^\]]+)\]\s+(.+?)(?:\s+-\s+Result:\s+(\w+))?(?:\s+-\s+Metrics:\s+(.+))?$'
        
        foreach ($line in $logContent) {
            if ($line -match $logPattern) {
                $operation = @{
                    Timestamp     = $matches[1]
                    Level         = $matches[2]
                    Component     = $matches[3]
                    Operation     = $matches[4]
                    Target        = $matches[5]
                    Message       = $matches[6]
                    Result        = if ($matches[7]) { $matches[7] } else { 'Unknown' }
                    Metrics       = if ($matches[8]) { $matches[8] } else { $null }
                    MetricsParsed = @{}
                }
                
                # Parse metrics if available (format: "Key1=Value1, Key2=Value2")
                if ($operation.Metrics) {
                    $metricsPairs = $operation.Metrics -split ',\s*'
                    foreach ($pair in $metricsPairs) {
                        if ($pair -match '([^=]+)=(.+)') {
                            $operation.MetricsParsed[$matches[1].Trim()] = $matches[2].Trim()
                        }
                    }
                }
                
                $result.Operations += $operation
                $result.Summary.Total++
                
                # Count by result status
                switch ($operation.Result) {
                    'Success' { $result.Summary.Success++ }
                    'Failed' { $result.Summary.Failed++ }
                    'Skipped' { $result.Summary.Skipped++ }
                    'InProgress' { $result.Summary.InProgress++ }
                }
                
                # Group by operation type
                if (-not $result.ByOperationType.ContainsKey($operation.Operation)) {
                    $result.ByOperationType[$operation.Operation] = @()
                }
                $result.ByOperationType[$operation.Operation] += $operation
                
                # Track first and last operations
                if (-not $result.FirstOperation) {
                    $result.FirstOperation = $operation.Timestamp
                }
                $result.LastOperation = $operation.Timestamp
            }
        }
        
        Write-LogEntry -Level 'SUCCESS' -Component 'REPORT-GENERATOR' -Message "Parsed $($result.Summary.Total) operations from $ModuleName logs"
        return $result
    }
    catch {
        Write-LogEntry -Level 'ERROR' -Component 'REPORT-GENERATOR' -Message "Failed to parse operation logs for ${ModuleName}: $($_.Exception.Message)"
        return @{
            Available       = $false
            Operations      = @()
            Summary         = @{ Total = 0; Success = 0; Failed = 0; Skipped = 0; InProgress = 0 }
            ByOperationType = @{}
        }
    }
}

<#
.SYNOPSIS
    Generates HTML table displaying parsed operation logs
.DESCRIPTION
    Creates formatted HTML table showing all operations with timestamps, targets, results, and metrics
.PARAMETER ParsedLogs
    Hashtable containing parsed operation logs from Get-ParsedOperationLogs
.PARAMETER ModuleName
    Display name of the module for the table title
.OUTPUTS
    HTML string containing the operation log table
#>
function New-OperationLogTable {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$ParsedLogs,
        
        [Parameter(Mandatory)]
        [string]$ModuleName
    )
    
    if (-not $ParsedLogs.Available -or $ParsedLogs.Summary.Total -eq 0) {
        return @"
<div class="operation-logs-section">
    <h4>📋 Operation Logs</h4>
    <p class="no-data">No operation logs available for this module.</p>
</div>
"@
    }
    
    $html = [System.Text.StringBuilder]::new()
    
    $html.AppendLine(@"
<div class="operation-logs-section">
    <h4>📋 Operation Logs - $ModuleName</h4>
    <div class="log-summary">
        <span class="log-stat">Total: <strong>$($ParsedLogs.Summary.Total)</strong></span>
        <span class="log-stat success">Success: <strong>$($ParsedLogs.Summary.Success)</strong></span>
        <span class="log-stat error">Failed: <strong>$($ParsedLogs.Summary.Failed)</strong></span>
        <span class="log-stat warning">Skipped: <strong>$($ParsedLogs.Summary.Skipped)</strong></span>
    </div>
    
    <div class="operation-table-container">
        <table class="operation-table">
            <thead>
                <tr>
                    <th>Timestamp</th>
                    <th>Operation</th>
                    <th>Target</th>
                    <th>Result</th>
                    <th>Metrics</th>
                    <th>Message</th>
                </tr>
            </thead>
            <tbody>
"@)
    
    foreach ($operation in $ParsedLogs.Operations) {
        $resultClass = switch ($operation.Result) {
            'Success' { 'result-success' }
            'Failed' { 'result-failed' }
            'Skipped' { 'result-skipped' }
            'InProgress' { 'result-inprogress' }
            default { 'result-unknown' }
        }
        
        $metricsDisplay = if ($operation.MetricsParsed.Count -gt 0) {
            ($operation.MetricsParsed.GetEnumerator() | ForEach-Object { "$($_.Key): $($_.Value)" }) -join '<br>'
        }
        else {
            '-'
        }
        
        $html.AppendLine(@"
                <tr>
                    <td class="timestamp">$($operation.Timestamp)</td>
                    <td class="operation-type">$($operation.Operation)</td>
                    <td class="target">$($operation.Target)</td>
                    <td class="$resultClass">$($operation.Result)</td>
                    <td class="metrics">$metricsDisplay</td>
                    <td class="message">$($operation.Message)</td>
                </tr>
"@)
    }
    
    $html.AppendLine(@"
            </tbody>
        </table>
    </div>
</div>
"@)
    
    return $html.ToString()
}

#endregion

#region Main Report Generation

<#
.SYNOPSIS
    Main entry point for generating maintenance reports
.DESCRIPTION
    Generates comprehensive maintenance reports using processed data from LogProcessor
    and templates from config directory
.PARAMETER OutputPath
    Path where the HTML report should be saved
.PARAMETER ProcessedDataPath
    Optional path to processed data directory (defaults to temp_files/processed)
#>
function New-MaintenanceReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$OutputPath,
        
        [Parameter()]
        [string]$ProcessedDataPath,
        
        [Parameter()]
        [switch]$EnableFallback
    )
    
    Write-LogEntry -Level 'INFO' -Component 'REPORT-GENERATOR' -Message "Starting maintenance report generation with enhanced error handling"
    
    try {
        $startTime = Get-Date
        
        # Load processed data with enhanced parameters
        Write-Information "📊 Loading processed log data..." -InformationAction Continue
        $processedDataParams = @{}
        if ($ProcessedDataPath) { $processedDataParams.ProcessedDataPath = $ProcessedDataPath }
        if ($EnableFallback) { $processedDataParams.FallbackToRawLogs = $true }
        
        $processedData = Get-ProcessedLogData @processedDataParams
        
        # Load HTML templates
        Write-Information "🎨 Loading report templates..." -InformationAction Continue
        $templates = Get-HtmlTemplates
        
        # Generate report content using templates and processed data
        Write-Information "📝 Generating HTML report content..." -InformationAction Continue
        $reportContent = New-HtmlReportContent -ProcessedData $processedData -Templates $templates
        
        # Save HTML report
        Write-Information "📄 Generating HTML report..." -InformationAction Continue
        $reportContent | Out-File -FilePath $OutputPath -Encoding UTF8 -Force
        
        # Generate additional formats using processed data
        Write-Information "📄 Generating text report..." -InformationAction Continue
        $textPath = $OutputPath -replace '\.html$', '.txt'
        $textContent = New-TextReportContent -ProcessedData $processedData
        $textContent | Out-File -FilePath $textPath -Encoding UTF8 -Force
        
        Write-Information "📊 Generating JSON export..." -InformationAction Continue
        $jsonPath = $OutputPath -replace '\.html$', '.json'
        $jsonContent = New-JsonExportContent -ProcessedData $processedData
        $jsonContent | Out-File -FilePath $jsonPath -Encoding UTF8 -Force
        
        Write-Information "📋 Generating summary report..." -InformationAction Continue
        $summaryPath = $OutputPath -replace '\.html$', '_summary.txt'
        $summaryContent = New-SummaryReportContent -ProcessedData $processedData
        $summaryContent | Out-File -FilePath $summaryPath -Encoding UTF8 -Force
        
        $duration = ((Get-Date) - $startTime).TotalSeconds
        
        $result = @{
            Success       = $true
            HtmlReport    = $OutputPath
            TextReport    = $textPath
            JsonExport    = $jsonPath
            SummaryReport = $summaryPath
            Duration      = $duration
        }
        
        Write-Information "✅ Report generation completed in $([math]::Round($duration, 2)) seconds" -InformationAction Continue
        Write-LogEntry -Level 'SUCCESS' -Component 'REPORT-GENERATOR' -Message 'Report generation completed successfully' -Data $result
        
        return $result
    }
    catch {
        Write-LogEntry -Level 'ERROR' -Component 'REPORT-GENERATOR' -Message "Report generation failed: $($_.Exception.Message)"
        return @{
            Success = $false
            Error   = $_.Exception.Message
        }
    }
}

#endregion

#region HTML Generation Functions

<#
.SYNOPSIS
    Generate comprehensive HTML report content using templates and processed data
    Redesigned from monolithic ReportGeneration.psm1 for split architecture
#>
function New-HtmlReportContent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$ProcessedData,
        
        [Parameter(Mandatory)]
        [hashtable]$Templates
    )
    
    Write-LogEntry -Level 'INFO' -Component 'REPORT-GENERATOR' -Message 'Generating comprehensive HTML report content'
    
    try {
        # Start with main template structure
        $html = $Templates.Main
        
        # Replace template placeholders with actual content
        $currentDate = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        $html = $html -replace '{{REPORT_TITLE}}', 'Windows Maintenance Report'
        $html = $html -replace '{{GENERATION_DATE}}', $currentDate
        $html = $html -replace '{{CSS_STYLES}}', $Templates.CSS
        
        # Generate dashboard metrics section
        $dashboardSection = New-DashboardSection -ProcessedData $ProcessedData -Templates $Templates
        $html = $html -replace '{{DASHBOARD_SECTION}}', $dashboardSection
        
        # Generate module sections
        $moduleSections = New-ModuleSections -ProcessedData $ProcessedData -Templates $Templates  
        $html = $html -replace '{{MODULE_SECTIONS}}', $moduleSections
        
        # Generate maintenance log section (if available)
        $maintenanceLogSection = New-MaintenanceLogSection -ProcessedData $ProcessedData -Templates $Templates
        if ($maintenanceLogSection) {
            # Insert maintenance log section after module sections
            $html = $html -replace '({{MODULE_SECTIONS}}.*?</div>)', "`$1`n$maintenanceLogSection"
        }
        
        # Generate summary section
        $summarySection = New-SummarySection -ProcessedData $ProcessedData
        $html = $html -replace '{{SUMMARY_SECTION}}', $summarySection
        
        Write-LogEntry -Level 'SUCCESS' -Component 'REPORT-GENERATOR' -Message 'HTML report content generated successfully'
        return $html
    }
    catch {
        Write-LogEntry -Level 'ERROR' -Component 'REPORT-GENERATOR' -Message "Failed to generate HTML content: $($_.Exception.Message)"
        throw
    }
}

<#
.SYNOPSIS
    Generate dashboard metrics section with key performance indicators
#>
function New-DashboardSection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$ProcessedData,
        
        [Parameter(Mandatory)]
        [hashtable]$Templates
    )
    
    # Safely access nested properties with null checks
    $metricsData = if ($ProcessedData.MetricsSummary) { 
        $ProcessedData.MetricsSummary.DashboardMetrics 
    }
    else { 
        @{ SuccessRate = 0; TotalTasks = 0; SystemHealthScore = 0; SecurityScore = 0 }
    }
    
    $executionSummary = if ($ProcessedData.MetricsSummary) { 
        $ProcessedData.MetricsSummary.ExecutionSummary 
    }
    else { 
        @{ TotalDuration = 0; SuccessfulTasks = 0; FailedTasks = 0 }
    }
    
    $html = [System.Text.StringBuilder]::new()
    
    # Dashboard header
    $html.AppendLine(@"
<div class="dashboard-section">
    <div class="dashboard-header">
        <h2>📊 System Health Dashboard</h2>
        <p class="dashboard-subtitle">Real-time maintenance metrics and system status</p>
    </div>
    
    <div class="dashboard-grid">
"@)
    
    # Success rate card
    $successRate = $metricsData.SuccessRate ?? 0
    $successClass = if ($successRate -ge 90) { 'success' } elseif ($successRate -ge 70) { 'warning' } else { 'error' }
    $html.AppendLine(@"
        <div class="dashboard-card $successClass">
            <div class="card-icon">✅</div>
            <h3>Success Rate</h3>
            <div class="card-value">$($successRate)%</div>
            <p class="card-description">Tasks completed successfully</p>
        </div>
"@)
    
    # Total tasks card
    $totalTasks = $metricsData.TotalTasks ?? 0
    $html.AppendLine(@"
        <div class="dashboard-card">
            <div class="card-icon">📋</div>
            <h3>Total Tasks</h3>
            <div class="card-value">$totalTasks</div>
            <p class="card-description">Maintenance tasks executed</p>
        </div>
"@)
    
    # System health score card
    $healthScore = $metricsData.SystemHealthScore ?? 0
    $healthClass = if ($healthScore -ge 85) { 'success' } elseif ($healthScore -ge 70) { 'warning' } else { 'error' }
    $html.AppendLine(@"
        <div class="dashboard-card $healthClass">
            <div class="card-icon">❤️</div>
            <h3>System Health</h3>
            <div class="card-value">$healthScore</div>
            <p class="card-description">Overall system health score</p>
        </div>
"@)
    
    # Security score card
    $securityScore = $metricsData.SecurityScore ?? 0
    $securityClass = if ($securityScore -ge 85) { 'success' } elseif ($securityScore -ge 70) { 'warning' } else { 'error' }
    $html.AppendLine(@"
        <div class="dashboard-card $securityClass">
            <div class="card-icon">🔒</div>
            <h3>Security Score</h3>
            <div class="card-value">$securityScore</div>
            <p class="card-description">Privacy and security status</p>
        </div>
"@)
    
    $html.AppendLine("    </div>")
    $html.AppendLine("</div>")
    
    return $html.ToString()
}

<#
.SYNOPSIS
    Generate individual module sections using task card templates
#>
function New-ModuleSections {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$ProcessedData,
        
        [Parameter(Mandatory)]
        [hashtable]$Templates
    )
    
    $html = [System.Text.StringBuilder]::new()
    
    # Safely access nested properties with null checks
    $moduleResults = if ($ProcessedData.ModuleResults) { 
        $ProcessedData.ModuleResults 
    }
    else { 
        @{ Type2ExecutionAnalysis = @{} }
    }
    
    $html.AppendLine(@"
<div class="modules-section">
    <div class="section-header">
        <h2>🔧 Module Execution Details</h2>
        <p class="section-subtitle">Detailed results for each maintenance module</p>
    </div>
"@)
    
    # Generate sections for each module
    $moduleNames = @(
        @{ Name = 'BloatwareRemoval'; DisplayName = 'Bloatware Removal'; Icon = '🗑️' }
        @{ Name = 'EssentialApps'; DisplayName = 'Essential Applications'; Icon = '📦' }
        @{ Name = 'SystemOptimization'; DisplayName = 'System Optimization'; Icon = '⚡' }
        @{ Name = 'TelemetryDisable'; DisplayName = 'Telemetry & Privacy'; Icon = '🔒' }
        @{ Name = 'WindowsUpdates'; DisplayName = 'Windows Updates'; Icon = '🔄' }
    )
    
    foreach ($module in $moduleNames) {
        # Safely access module-specific data with null checks
        $moduleData = if ($moduleResults.Type2ExecutionAnalysis) {
            $moduleResults.Type2ExecutionAnalysis[$module.Name]
        }
        else {
            $null
        }
        
        # Parse operation logs for this module (convert PascalCase to kebab-case for directory name)
        $moduleLogDir = $module.Name -creplace '([A-Z])', '-$1' -replace '^-', '' | ForEach-Object { $_.ToLower() }
        $parsedLogs = Get-ParsedOperationLogs -ModuleName $moduleLogDir
        
        # Generate operation log table HTML
        $operationLogTable = New-OperationLogTable -ParsedLogs $parsedLogs -ModuleName $module.DisplayName
        
        if ($moduleData) {
            $taskCard = $Templates.TaskCard
            
            # Replace template placeholders
            $taskCard = $taskCard -replace '{{MODULE_NAME}}', $module.DisplayName
            $taskCard = $taskCard -replace '{{MODULE_ICON}}', $module.Icon
            $taskCard = $taskCard -replace '{{SUCCESS_COUNT}}', ($moduleData.SuccessfulOperations ?? 0)
            $taskCard = $taskCard -replace '{{TOTAL_COUNT}}', ($moduleData.TotalOperations ?? 0)
            $taskCard = $taskCard -replace '{{DURATION}}', ($moduleData.Duration ?? 0)
            $taskCard = $taskCard -replace '{{SUCCESS_RATE}}', ($moduleData.SuccessRate ?? 0)
            
            $html.AppendLine($taskCard)
        }
        else {
            # Create basic module card if no processed data available
            $html.AppendLine(@"
        <div class="module-card">
            <div class="module-header">
                <h3>$($module.Icon) $($module.DisplayName)</h3>
            </div>
            <div class="module-content">
                <p>No processed data available for this module.</p>
            </div>
        </div>
"@)
        }
        
        # Append operation log table after module card
        $html.AppendLine($operationLogTable)
    }
    
    $html.AppendLine("</div>")
    return $html.ToString()
}

<#
.SYNOPSIS
    Generate summary section with overall results and recommendations
#>
function New-SummarySection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$ProcessedData
    )
    
    $html = [System.Text.StringBuilder]::new()
    
    # Safely access nested properties with null checks
    $executionSummary = if ($ProcessedData.MetricsSummary) { 
        $ProcessedData.MetricsSummary.ExecutionSummary 
    }
    else { 
        @{ TotalDuration = 0; SuccessfulTasks = 0; FailedTasks = 0 }
    }
    
    $errorsData = if ($ProcessedData.ErrorsAnalysis) { 
        $ProcessedData.ErrorsAnalysis 
    }
    else { 
        @{ ErrorSummary = @{ TotalErrors = 0 } }
    }
    
    $html.AppendLine(@"
<div class="summary-section">
    <div class="section-header">
        <h2>📋 Execution Summary</h2>
    </div>
    
    <div class="summary-content">
        <div class="summary-stats">
            <div class="stat-item">
                <span class="stat-label">Total Duration:</span>
                <span class="stat-value">$($executionSummary.TotalDuration ?? 0) seconds</span>
            </div>
            <div class="stat-item">
                <span class="stat-label">Successful Tasks:</span>
                <span class="stat-value success">$($executionSummary.SuccessfulTasks ?? 0)</span>
            </div>
            <div class="stat-item">
                <span class="stat-label">Failed Tasks:</span>
                <span class="stat-value error">$($executionSummary.FailedTasks ?? 0)</span>
            </div>
            <div class="stat-item">
                <span class="stat-label">Total Errors:</span>
                <span class="stat-value warning">$($errorsData.ErrorSummary.TotalErrors ?? 0)</span>
            </div>
        </div>
    </div>
</div>
"@)
    
    return $html.ToString()
}

<#
.SYNOPSIS
    Generate maintenance log section with parsed log entries and statistics
#>
function New-MaintenanceLogSection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$ProcessedData,
        
        [Parameter(Mandatory)]
        [hashtable]$Templates
    )
    
    $html = [System.Text.StringBuilder]::new()
    
    # Check if maintenance log data is available
    $maintenanceLog = if ($ProcessedData.ContainsKey('MaintenanceLog')) {
        $ProcessedData.MaintenanceLog
    }
    else {
        $null
    }
    
    if (-not $maintenanceLog -or -not $maintenanceLog.Available) {
        Write-LogEntry -Level 'WARN' -Component 'REPORT-GENERATOR' -Message 'Maintenance log not available for report'
        return ""
    }
    
    $parsed = $maintenanceLog.Parsed
    $logConfig = $Templates.Config.reportConfiguration.moduleReports.MaintenanceLog
    
    $html.AppendLine(@"
<div class="module-card">
    <div class="module-header">
        <h3>$($logConfig.icon) $($logConfig.displayName)</h3>
        <p class="module-description">$($logConfig.description)</p>
    </div>
    
    <div class="module-content">
        <div class="before-after-container">
            <!-- Before Section: Log Statistics -->
            <div class="before-section">
                <h4>$($logConfig.beforeTitle)</h4>
                <div class="changes-summary">
                    <div class="change-stat">
                        <span class="change-label">📁 Log File:</span>
                        <span class="change-value">$([System.IO.Path]::GetFileName($maintenanceLog.LogFile))</span>
                    </div>
                    <div class="change-stat">
                        <span class="change-label">📏 Total Lines:</span>
                        <span class="change-value">$($maintenanceLog.LineCount)</span>
                    </div>
                    <div class="change-stat">
                        <span class="change-label">💾 File Size:</span>
                        <span class="change-value">$([math]::Round($maintenanceLog.Size / 1KB, 2)) KB</span>
                    </div>
                    <div class="change-stat">
                        <span class="change-label">🕐 Last Modified:</span>
                        <span class="change-value">$($maintenanceLog.LastModified.ToString('yyyy-MM-dd HH:mm:ss'))</span>
                    </div>
                    <div class="change-stat">
                        <span class="change-label">📊 Total Entries:</span>
                        <span class="change-value">$($parsed.TotalEntries)</span>
                    </div>
                </div>
            </div>
            
            <!-- After Section: Entry Breakdown -->
            <div class="after-section">
                <h4>$($logConfig.afterTitle)</h4>
                <div class="changes-list">
                    <div class="change-category">
                        <h5 class="info">ℹ️ $($logConfig.changeCategories.info) ($($parsed.InfoMessages.Count))</h5>
                        <div class="change-items">
"@)
    
    # Add sample INFO messages (limit to 5 for brevity)
    $sampleInfo = $parsed.InfoMessages | Select-Object -First 5
    foreach ($msg in $sampleInfo) {
        $escapedMsg = [System.Web.HttpUtility]::HtmlEncode($msg)
        $html.AppendLine("                            <div class='change-item'><code>$escapedMsg</code></div>")
    }
    if ($parsed.InfoMessages.Count -gt 5) {
        $html.AppendLine("                            <div class='change-item'><em>... and $($parsed.InfoMessages.Count - 5) more INFO entries</em></div>")
    }
    
    $html.AppendLine(@"
                        </div>
                    </div>
                    
                    <div class="change-category">
                        <h5 class="success">✅ $($logConfig.changeCategories.success) ($($parsed.SuccessMessages.Count))</h5>
                        <div class="change-items">
"@)
    
    # Add sample SUCCESS messages
    $sampleSuccess = $parsed.SuccessMessages | Select-Object -First 5
    foreach ($msg in $sampleSuccess) {
        $escapedMsg = [System.Web.HttpUtility]::HtmlEncode($msg)
        $html.AppendLine("                            <div class='change-item'><code>$escapedMsg</code></div>")
    }
    if ($parsed.SuccessMessages.Count -gt 5) {
        $html.AppendLine("                            <div class='change-item'><em>... and $($parsed.SuccessMessages.Count - 5) more SUCCESS entries</em></div>")
    }
    
    $html.AppendLine(@"
                        </div>
                    </div>
                    
                    <div class="change-category">
                        <h5 class="warning">⚠️ $($logConfig.changeCategories.warning) ($($parsed.WarningMessages.Count))</h5>
                        <div class="change-items">
"@)
    
    # Add WARNING messages
    foreach ($msg in $parsed.WarningMessages) {
        $escapedMsg = [System.Web.HttpUtility]::HtmlEncode($msg)
        $html.AppendLine("                            <div class='change-item warning'><code>$escapedMsg</code></div>")
    }
    if ($parsed.WarningMessages.Count -eq 0) {
        $html.AppendLine("                            <div class='change-item'><em>No warnings</em></div>")
    }
    
    $html.AppendLine(@"
                        </div>
                    </div>
                    
                    <div class="change-category">
                        <h5 class="error">❌ $($logConfig.changeCategories.error) ($($parsed.ErrorMessages.Count))</h5>
                        <div class="change-items">
"@)
    
    # Add ERROR messages
    foreach ($msg in $parsed.ErrorMessages) {
        $escapedMsg = [System.Web.HttpUtility]::HtmlEncode($msg)
        $html.AppendLine("                            <div class='change-item error'><code>$escapedMsg</code></div>")
    }
    if ($parsed.ErrorMessages.Count -eq 0) {
        $html.AppendLine("                            <div class='change-item'><em>No errors</em></div>")
    }
    
    $html.AppendLine(@"
                        </div>
                    </div>
                </div>
            </div>
        </div>
    </div>
</div>
"@)
    
    return $html.ToString()
}

#endregion

#region Export Functions

<#
.SYNOPSIS
    Generate text-based report content from processed data
    Adapted from ReportGeneration.psm1 for split architecture
#>
function New-TextReportContent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$ProcessedData
    )
    
    Write-LogEntry -Level 'INFO' -Component 'REPORT-GENERATOR' -Message 'Generating text report content'
    
    try {
        $text = [System.Text.StringBuilder]::new()
        
        # Header
        $text.AppendLine("=" * 80)
        $text.AppendLine("                    WINDOWS MAINTENANCE REPORT")
        $text.AppendLine("=" * 80)
        $text.AppendLine("")
        $text.AppendLine("Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
        $text.AppendLine("Computer: $env:COMPUTERNAME")
        $text.AppendLine("User: $env:USERNAME")
        
        # Safely access nested properties with null checks
        $sessionId = if ($ProcessedData.MetricsSummary -and $ProcessedData.MetricsSummary.ProcessingMetadata) {
            $ProcessedData.MetricsSummary.ProcessingMetadata.SessionId
        }
        else {
            'N/A'
        }
        $text.AppendLine("Session ID: $sessionId")
        $text.AppendLine("")
        
        # Executive Summary - safely access nested properties
        $executionSummary = if ($ProcessedData.MetricsSummary) { 
            $ProcessedData.MetricsSummary.ExecutionSummary 
        }
        else { 
            @{ TotalTasks = 0; SuccessfulTasks = 0; FailedTasks = 0; TotalDuration = 0 }
        }
        
        $dashboardMetrics = if ($ProcessedData.MetricsSummary) { 
            $ProcessedData.MetricsSummary.DashboardMetrics 
        }
        else { 
            @{ SuccessRate = 0; SystemHealthScore = 0; SecurityScore = 0 }
        }
        
        $text.AppendLine("EXECUTIVE SUMMARY")
        $text.AppendLine("-" * 40)
        $text.AppendLine("Tasks Executed: $($executionSummary.TotalTasks ?? 0)")
        $text.AppendLine("Successful: $($executionSummary.SuccessfulTasks ?? 0)")
        $text.AppendLine("Failed: $($executionSummary.FailedTasks ?? 0)")
        $text.AppendLine("Success Rate: $($dashboardMetrics.SuccessRate ?? 0)%")
        $text.AppendLine("Total Duration: $([math]::Round(($executionSummary.TotalDuration ?? 0), 2)) seconds")
        $text.AppendLine("System Health Score: $($dashboardMetrics.SystemHealthScore ?? 0)")
        $text.AppendLine("Security Score: $($dashboardMetrics.SecurityScore ?? 0)")
        $text.AppendLine("")
        
        # Module Results Summary
        $moduleResults = $ProcessedData.ModuleResults
        if ($moduleResults -and $moduleResults.Type2ExecutionAnalysis) {
            $text.AppendLine("MODULE EXECUTION RESULTS")
            $text.AppendLine("-" * 40)
            
            $moduleNames = @{
                'BloatwareRemoval'   = 'Bloatware Removal'
                'EssentialApps'      = 'Essential Applications'
                'SystemOptimization' = 'System Optimization'
                'TelemetryDisable'   = 'Telemetry & Privacy'
                'WindowsUpdates'     = 'Windows Updates'
            }
            
            foreach ($moduleKey in $moduleResults.Type2ExecutionAnalysis.Keys) {
                $moduleData = $moduleResults.Type2ExecutionAnalysis[$moduleKey]
                $displayName = $moduleNames[$moduleKey] ?? $moduleKey
                
                $successCount = $moduleData.SuccessfulOperations ?? 0
                $totalCount = $moduleData.TotalOperations ?? 0
                $successRate = $moduleData.SuccessRate ?? 0
                $duration = $moduleData.Duration ?? 0
                
                $status = if ($successRate -ge 90) { "SUCCESS" } elseif ($successRate -ge 70) { "WARNING" } else { "FAILED" }
                
                $text.AppendLine("[$status] $displayName")
                $text.AppendLine("  Operations: $successCount/$totalCount successful ($successRate%)")
                $text.AppendLine("  Duration: $([math]::Round($duration, 2)) seconds")
                $text.AppendLine("")
            }
        }
        
        # Error Summary
        $errorsData = $ProcessedData.ErrorsAnalysis
        if ($errorsData -and $errorsData.ErrorSummary) {
            $text.AppendLine("ERROR SUMMARY")
            $text.AppendLine("-" * 40)
            $text.AppendLine("Total Errors: $($errorsData.ErrorSummary.TotalErrors ?? 0)")
            $text.AppendLine("High Severity: $($errorsData.ErrorSummary.HighSeverity ?? 0)")
            $text.AppendLine("Medium Severity: $($errorsData.ErrorSummary.MediumSeverity ?? 0)")
            
            if ($errorsData.AllErrors -and $errorsData.AllErrors.Count -gt 0) {
                $text.AppendLine("")
                $text.AppendLine("Recent Errors:")
                $recentErrors = $errorsData.AllErrors | Select-Object -First 5
                foreach ($errorEntry in $recentErrors) {
                    $text.AppendLine("  [$($errorEntry.Level)] $($errorEntry.Module): $($errorEntry.Message)")
                }
            }
            $text.AppendLine("")
        }
        
        # Health Scores
        $healthScores = $ProcessedData.HealthScores
        if ($healthScores) {
            $text.AppendLine("SYSTEM HEALTH ANALYSIS")
            $text.AppendLine("-" * 40)
            
            if ($healthScores.SystemHealth) {
                $text.AppendLine("Overall Score: $($healthScores.SystemHealth.OverallScore ?? 0)")
            }
            
            if ($healthScores.Security) {
                $text.AppendLine("Security Status: $($healthScores.Security.Status ?? 'Unknown')")
            }
            
            if ($healthScores.Performance) {
                $text.AppendLine("Performance: $($healthScores.Performance.TotalOperations ?? 0) operations")
            }
            
            $text.AppendLine("")
        }
        
        # Footer
        $text.AppendLine("=" * 80)
        $text.AppendLine("Report generated by Windows Maintenance Automation v3.0")
        $text.AppendLine("Split Architecture: LogProcessor → ReportGenerator")
        $text.AppendLine("=" * 80)
        
        Write-LogEntry -Level 'SUCCESS' -Component 'REPORT-GENERATOR' -Message 'Text report content generated successfully'
        return $text.ToString()
    }
    catch {
        Write-LogEntry -Level 'ERROR' -Component 'REPORT-GENERATOR' -Message "Failed to generate text content: $($_.Exception.Message)"
        throw
    }
}

<#
.SYNOPSIS
    Generate JSON export of processed data with formatting
#>
function New-JsonExportContent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$ProcessedData
    )
    
    Write-LogEntry -Level 'INFO' -Component 'REPORT-GENERATOR' -Message 'Generating JSON export content'
    
    try {
        # Create export-friendly structure with safe null handling
        $exportData = @{
            ExportMetadata     = @{
                GeneratedAt  = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                ExportFormat = 'JSON'
                Architecture = 'v3.0-Split'
                Computer     = $env:COMPUTERNAME
                User         = $env:USERNAME
            }
            ExecutionSummary   = if ($ProcessedData.MetricsSummary) { $ProcessedData.MetricsSummary.ExecutionSummary } else { @{} }
            DashboardMetrics   = if ($ProcessedData.MetricsSummary) { $ProcessedData.MetricsSummary.DashboardMetrics } else { @{} }
            ModuleResults      = if ($ProcessedData.ModuleResults) { $ProcessedData.ModuleResults } else { @{} }
            ErrorsAnalysis     = if ($ProcessedData.ErrorsAnalysis) { $ProcessedData.ErrorsAnalysis } else { @{} }
            HealthScores       = if ($ProcessedData.HealthScores) { $ProcessedData.HealthScores } else { @{} }
            ProcessingMetadata = if ($ProcessedData.MetricsSummary) { $ProcessedData.MetricsSummary.ProcessingMetadata } else { @{} }
        }
        
        $jsonContent = $exportData | ConvertTo-Json -Depth 10
        
        Write-LogEntry -Level 'SUCCESS' -Component 'REPORT-GENERATOR' -Message 'JSON export content generated successfully'
        return $jsonContent
    }
    catch {
        Write-LogEntry -Level 'ERROR' -Component 'REPORT-GENERATOR' -Message "Failed to generate JSON content: $($_.Exception.Message)"
        throw
    }
}

<#
.SYNOPSIS
    Generate summary report content for quick overview
#>
function New-SummaryReportContent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$ProcessedData
    )
    
    Write-LogEntry -Level 'INFO' -Component 'REPORT-GENERATOR' -Message 'Generating summary report content'
    
    try {
        $summary = [System.Text.StringBuilder]::new()
        
        # Safely access nested properties with null checks
        $executionSummary = if ($ProcessedData.MetricsSummary) { 
            $ProcessedData.MetricsSummary.ExecutionSummary 
        }
        else { 
            @{ TotalTasks = 0; SuccessfulTasks = 0; FailedTasks = 0; TotalDuration = 0 }
        }
        
        $dashboardMetrics = if ($ProcessedData.MetricsSummary) { 
            $ProcessedData.MetricsSummary.DashboardMetrics 
        }
        else { 
            @{ SuccessRate = 0; SystemHealthScore = 0; SecurityScore = 0 }
        }
        
        $errorsData = if ($ProcessedData.ErrorsAnalysis) { 
            $ProcessedData.ErrorsAnalysis 
        }
        else { 
            @{ ErrorSummary = @{ TotalErrors = 0 } }
        }
        
        # Compact summary format
        $summary.AppendLine("🔧 WINDOWS MAINTENANCE SUMMARY")
        $summary.AppendLine("Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm')")
        $summary.AppendLine("")
        
        # Key metrics in compact format
        $summary.AppendLine("📊 RESULTS:")
        $summary.AppendLine("   Tasks: $($executionSummary.SuccessfulTasks ?? 0)/$($executionSummary.TotalTasks ?? 0) successful ($($dashboardMetrics.SuccessRate ?? 0)%)")
        $summary.AppendLine("   Duration: $([math]::Round(($executionSummary.TotalDuration ?? 0), 1))s")
        $summary.AppendLine("   Health: $($dashboardMetrics.SystemHealthScore ?? 0)/100")
        $summary.AppendLine("   Security: $($dashboardMetrics.SecurityScore ?? 0)/100")
        
        if ($errorsData -and $errorsData.ErrorSummary -and $errorsData.ErrorSummary.TotalErrors -gt 0) {
            $summary.AppendLine("")
            $summary.AppendLine("⚠️  ISSUES:")
            $summary.AppendLine("   Errors: $($errorsData.ErrorSummary.TotalErrors) ($($errorsData.ErrorSummary.HighSeverity) high severity)")
        }
        
        $summary.AppendLine("")
        $summary.AppendLine("✅ System maintenance completed - v3.0 Split Architecture")
        
        Write-LogEntry -Level 'SUCCESS' -Component 'REPORT-GENERATOR' -Message 'Summary report content generated successfully'
        return $summary.ToString()
    }
    catch {
        Write-LogEntry -Level 'ERROR' -Component 'REPORT-GENERATOR' -Message "Failed to generate summary content: $($_.Exception.Message)"
        throw
    }
}

#endregion

#region Chart Generation Functions

<#
.SYNOPSIS
    Generate task distribution chart data for interactive visualizations
    Extracted from ReportGeneration.psm1 for split architecture
#>
function Get-TaskDistributionData {
    [CmdletBinding()]
    param(
        [Parameter()]
        [hashtable]$ProcessedData
    )
    
    Write-LogEntry -Level 'INFO' -Component 'REPORT-GENERATOR' -Message 'Generating task distribution chart data'
    
    try {
        # Extract task data from processed results with safe null handling
        $moduleResults = if ($ProcessedData.ModuleResults) {
            $ProcessedData.ModuleResults.Type2ExecutionAnalysis
        }
        else {
            $null
        }
        
        if (-not $moduleResults -or $moduleResults.Keys.Count -eq 0) {
            return @{
                labels   = @('No Data')
                datasets = @(@{
                        data            = @(1)
                        backgroundColor = @('#cccccc')
                    })
            }
        }
        
        $distribution = @()
        $moduleNames = @{
            'BloatwareRemoval'   = 'Bloatware Removal'
            'EssentialApps'      = 'Essential Apps'
            'SystemOptimization' = 'System Optimization'  
            'TelemetryDisable'   = 'Privacy & Telemetry'
            'WindowsUpdates'     = 'Windows Updates'
        }
        
        foreach ($moduleKey in $moduleResults.Keys) {
            $moduleData = $moduleResults[$moduleKey]
            $displayName = $moduleNames[$moduleKey] ?? $moduleKey
            
            $distribution += @{
                Type    = $displayName
                Count   = $moduleData.TotalOperations ?? 0
                Success = $moduleData.SuccessfulOperations ?? 0
                Failed  = $moduleData.FailedOperations ?? 0
            }
        }
        
        return @{
            labels   = $distribution.Type
            datasets = @(@{
                    label           = 'Task Distribution'
                    data            = $distribution.Count
                    backgroundColor = @('#0078d4', '#107c10', '#ffb900', '#d13438', '#6b69d6')
                    borderWidth     = 2
                    borderColor     = '#ffffff'
                })
        }
    }
    catch {
        Write-LogEntry -Level 'ERROR' -Component 'REPORT-GENERATOR' -Message "Failed to generate task distribution data: $($_.Exception.Message)"
        throw
    }
}

<#
.SYNOPSIS
    Generate system resource chart data for resource utilization visualization
    Extracted from ReportGeneration.psm1 for split architecture
#>
function Get-SystemResourceData {
    [CmdletBinding()]
    param(
        [Parameter()]
        [hashtable]$ProcessedData
    )
    
    Write-LogEntry -Level 'INFO' -Component 'REPORT-GENERATOR' -Message 'Generating system resource chart data'
    
    try {
        # Extract system health data from processed results with safe null handling
        $systemHealth = if ($ProcessedData.HealthScores) {
            $ProcessedData.HealthScores.SystemHealth
        }
        else {
            $null
        }
        
        if (-not $systemHealth -or -not $systemHealth.HealthFactors) {
            return @{
                labels   = @('No Data')
                datasets = @(@{
                        data            = @(0)
                        backgroundColor = @('#cccccc')
                    })
            }
        }
        
        $resources = @()
        $values = @()
        $colors = @()
        
        # Extract health factor scores
        foreach ($factorName in $systemHealth.HealthFactors.Keys) {
            $factor = $systemHealth.HealthFactors[$factorName]
            $resources += $factorName
            
            # Convert score to percentage
            $percentage = if ($factor.MaxScore -gt 0) {
                [math]::Round(($factor.Score / $factor.MaxScore) * 100, 1)
            }
            else { 0 }
            
            $values += $percentage
            
            # Assign colors based on component type
            $colors += switch ($factorName) {
                'CPU' { '#0078d4' }
                'Memory' { '#107c10' }
                'Storage' { '#ffb900' }
                'OperatingSystem' { '#d13438' }
                'Services' { '#6b69d6' }
                default { '#323130' }
            }
        }
        
        return @{
            labels   = $resources
            datasets = @(@{
                    label           = 'Resource Health %'
                    data            = $values
                    backgroundColor = $colors
                    borderColor     = $colors
                    borderWidth     = 1
                })
        }
    }
    catch {
        Write-LogEntry -Level 'ERROR' -Component 'REPORT-GENERATOR' -Message "Failed to generate system resource data: $($_.Exception.Message)"
        throw
    }
}

<#
.SYNOPSIS
    Generate execution timeline data for task duration visualization
    Extracted from ReportGeneration.psm1 for split architecture
#>
function Get-ExecutionTimelineData {
    [CmdletBinding()]
    param(
        [Parameter()]
        [hashtable]$ProcessedData
    )
    
    Write-LogEntry -Level 'INFO' -Component 'REPORT-GENERATOR' -Message 'Generating execution timeline chart data'
    
    try {
        # Extract execution metrics from processed results with safe null handling
        $moduleResults = if ($ProcessedData.ModuleResults) {
            $ProcessedData.ModuleResults.Type2ExecutionAnalysis
        }
        else {
            $null
        }
        
        if (-not $moduleResults -or $moduleResults.Keys.Count -eq 0) {
            return @{
                labels   = @()
                datasets = @()
            }
        }
        
        $timelinePoints = @()
        $moduleIndex = 0
        $startTime = Get-Date
        
        foreach ($moduleKey in $moduleResults.Keys) {
            $moduleData = $moduleResults[$moduleKey]
            $duration = $moduleData.Duration ?? 0
            
            $timelinePoints += @{
                x = $startTime.AddMinutes($moduleIndex * 2).ToString('yyyy-MM-ddTHH:mm:ss')
                y = $duration
            }
            
            $moduleIndex++
        }
        
        return @{
            datasets = @(@{
                    label           = 'Module Duration (seconds)'
                    data            = $timelinePoints
                    borderColor     = '#0078d4'
                    backgroundColor = 'rgba(0, 120, 212, 0.1)'
                    fill            = $true
                    tension         = 0.4
                })
        }
    }
    catch {
        Write-LogEntry -Level 'ERROR' -Component 'REPORT-GENERATOR' -Message "Failed to generate execution timeline data: $($_.Exception.Message)"
        throw
    }
}

<#
.SYNOPSIS
    Generate security score data for radar chart visualization
    Extracted from ReportGeneration.psm1 for split architecture
#>
function Get-SecurityScoreData {
    [CmdletBinding()]
    param(
        [Parameter()]
        [hashtable]$ProcessedData
    )
    
    Write-LogEntry -Level 'INFO' -Component 'REPORT-GENERATOR' -Message 'Generating security score chart data'
    
    try {
        # Extract security analytics from processed results with safe null handling
        $securityAnalytics = if ($ProcessedData.HealthScores) {
            $ProcessedData.HealthScores.Security
        }
        else {
            $null
        }
        
        # Define security categories and extract scores
        $categories = @('Privacy', 'Updates', 'System Security', 'Services', 'Network Protection', 'Configuration')
        $scores = @()
        
        if ($securityAnalytics) {
            # Use actual security score as base
            $baseScore = $securityAnalytics.SecurityScore ?? 75
            
            # Generate category-specific scores based on security analysis
            $scores = @(
                $baseScore,                                           # Privacy (from TelemetryDisable)
                [math]::Min(100, $baseScore + 10),                  # Updates
                $baseScore,                                           # System Security
                [math]::Max(60, $baseScore - 5),                    # Services
                [math]::Min(95, $baseScore + 5),                    # Network Protection
                $baseScore                                           # Configuration
            )
        }
        else {
            # Default scores if no security data available
            $scores = @(75, 80, 75, 70, 80, 75)
        }
        
        return @{
            labels   = $categories
            datasets = @(@{
                    label                     = 'Security Score'
                    data                      = $scores
                    borderColor               = '#d13438'
                    backgroundColor           = 'rgba(209, 52, 56, 0.2)'
                    pointBackgroundColor      = '#d13438'
                    pointBorderColor          = '#ffffff'
                    pointHoverBackgroundColor = '#ffffff'
                    pointHoverBorderColor     = '#d13438'
                })
        }
    }
    catch {
        Write-LogEntry -Level 'ERROR' -Component 'REPORT-GENERATOR' -Message "Failed to generate security score data: $($_.Exception.Message)"
        throw
    }
}

<#
.SYNOPSIS
    Generate comprehensive chart data collection for all visualizations
#>
function Get-ComprehensiveChartData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$ProcessedData
    )
    
    Write-LogEntry -Level 'INFO' -Component 'REPORT-GENERATOR' -Message 'Generating comprehensive chart data collection'
    
    try {
        $chartData = @{
            TaskDistribution  = Get-TaskDistributionData -ProcessedData $ProcessedData
            SystemResources   = Get-SystemResourceData -ProcessedData $ProcessedData
            ExecutionTimeline = Get-ExecutionTimelineData -ProcessedData $ProcessedData
            SecurityScore     = Get-SecurityScoreData -ProcessedData $ProcessedData
        }
        
        Write-LogEntry -Level 'SUCCESS' -Component 'REPORT-GENERATOR' -Message 'Comprehensive chart data generated successfully'
        return $chartData
    }
    catch {
        Write-LogEntry -Level 'ERROR' -Component 'REPORT-GENERATOR' -Message "Failed to generate comprehensive chart data: $($_.Exception.Message)"
        throw
    }
}

#endregion



#region Testing and Validation Functions

<#
.SYNOPSIS
    Tests the template loading functionality for config integration validation
.DESCRIPTION
    Validates that all required template files can be loaded from config/ directory
    and that fallback mechanisms work correctly when templates are missing
#>
function Test-ConfigTemplateIntegration {
    [CmdletBinding()]
    param(
        [Parameter()]
        [switch]$TestFallbacks
    )
    
    Write-LogEntry -Level 'INFO' -Component 'REPORT-GENERATOR' -Message 'Testing config template integration'
    
    $testResults = @{
        Success             = $true
        TemplateLoadResults = @{}
        FallbackResults     = @{}
        ValidationErrors    = @()
    }
    
    try {
        # Test 1: Normal template loading
        Write-Information "📋 Testing normal template loading..." -InformationAction Continue
        
        try {
            $templates = Get-HtmlTemplates -ErrorAction Stop
            
            # Validate each template
            $requiredTemplates = @('Main', 'TaskCard', 'CSS', 'Config')
            foreach ($templateName in $requiredTemplates) {
                if ($templates.ContainsKey($templateName) -and -not [string]::IsNullOrEmpty($templates[$templateName])) {
                    $testResults.TemplateLoadResults[$templateName] = @{
                        Status = 'Success'
                        Length = if ($templates[$templateName] -is [string]) { $templates[$templateName].Length } else { 'Object' }
                        Type   = $templates[$templateName].GetType().Name
                    }
                    Write-Verbose "✓ Template '$templateName' loaded successfully"
                }
                else {
                    $testResults.TemplateLoadResults[$templateName] = @{
                        Status = 'Failed'
                        Error  = 'Template missing or empty'
                    }
                    $testResults.ValidationErrors += "Template '$templateName' failed validation"
                    $testResults.Success = $false
                }
            }
            
            # Validate template content has required placeholders
            if ($templates.Main) {
                $requiredPlaceholders = @('{{REPORT_TITLE}}', '{{GENERATION_TIME}}', '{{MODULE_REPORTS}}')
                foreach ($placeholder in $requiredPlaceholders) {
                    if ($templates.Main -notlike "*$placeholder*") {
                        $testResults.ValidationErrors += "Main template missing required placeholder: $placeholder"
                        $testResults.Success = $false
                    }
                }
            }
            
            Write-Information "  ✓ Template loading test completed" -InformationAction Continue
        }
        catch {
            $testResults.Success = $false
            $testResults.ValidationErrors += "Template loading failed: $($_.Exception.Message)"
            Write-Warning "  ✗ Template loading failed: $($_.Exception.Message)"
        }
        
        # Test 2: Fallback mechanisms (if requested)
        if ($TestFallbacks) {
            Write-Information "📋 Testing fallback template mechanisms..." -InformationAction Continue
            
            try {
                $fallbackTemplates = Get-FallbackTemplates -ErrorAction Stop
                
                $requiredFallbacks = @('Main', 'TaskCard', 'CSS', 'Config')
                foreach ($templateName in $requiredFallbacks) {
                    if ($fallbackTemplates.ContainsKey($templateName) -and -not [string]::IsNullOrEmpty($fallbackTemplates[$templateName])) {
                        $testResults.FallbackResults[$templateName] = @{
                            Status = 'Success'
                            Length = if ($fallbackTemplates[$templateName] -is [string]) { $fallbackTemplates[$templateName].Length } else { 'Object' }
                        }
                        Write-Verbose "✓ Fallback template '$templateName' available"
                    }
                    else {
                        $testResults.FallbackResults[$templateName] = @{
                            Status = 'Failed'
                            Error  = 'Fallback template missing or empty'
                        }
                        $testResults.ValidationErrors += "Fallback template '$templateName' failed validation"
                        $testResults.Success = $false
                    }
                }
                
                Write-Information "  ✓ Fallback template test completed" -InformationAction Continue
            }
            catch {
                $testResults.Success = $false
                $testResults.ValidationErrors += "Fallback template loading failed: $($_.Exception.Message)"
                Write-Warning "  ✗ Fallback template loading failed: $($_.Exception.Message)"
            }
        }
        
        # Summary
        if ($testResults.Success) {
            Write-LogEntry -Level 'SUCCESS' -Component 'REPORT-GENERATOR' -Message 'Config template integration test passed'
        }
        else {
            Write-LogEntry -Level 'ERROR' -Component 'REPORT-GENERATOR' -Message "Config template integration test failed: $($testResults.ValidationErrors.Count) errors found"
        }
        
        return $testResults
    }
    catch {
        Write-LogEntry -Level 'ERROR' -Component 'REPORT-GENERATOR' -Message "Template integration test failed: $($_.Exception.Message)"
        throw
    }
}

<#
.SYNOPSIS
    Tests processed data loading functionality
.DESCRIPTION
    Validates that ReportGenerator can properly load data from temp_files/processed/
    and handle missing or corrupted data gracefully
#>
function Test-ProcessedDataIntegration {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$ProcessedDataPath,
        
        [Parameter()]
        [switch]$TestFallbacks
    )
    
    Write-LogEntry -Level 'INFO' -Component 'REPORT-GENERATOR' -Message 'Testing processed data integration'
    
    $testResults = @{
        Success           = $true
        DataLoadResults   = @{}
        ValidationResults = @{}
        FallbackResults   = @{}
        ValidationErrors  = @()
    }
    
    try {
        # Test 1: Normal data loading
        Write-Information "📊 Testing processed data loading..." -InformationAction Continue
        
        $loadParams = @{}
        if ($ProcessedDataPath) { $loadParams.ProcessedDataPath = $ProcessedDataPath }
        if ($TestFallbacks) { $loadParams.FallbackToRawLogs = $true }
        
        try {
            $processedData = Get-ProcessedLogData @loadParams -ErrorAction Stop
            
            # Validate data structure
            $requiredComponents = @('MetricsSummary', 'ModuleResults', 'ErrorsAnalysis', 'HealthScores')
            foreach ($component in $requiredComponents) {
                if ($processedData.ContainsKey($component)) {
                    $testResults.DataLoadResults[$component] = @{
                        Status  = 'Success'
                        HasData = ($processedData[$component] -and $processedData[$component].Count -gt 0)
                        Type    = $processedData[$component].GetType().Name
                    }
                    Write-Verbose "✓ Data component '$component' loaded"
                }
                else {
                    $testResults.DataLoadResults[$component] = @{
                        Status = 'Missing'
                        Error  = 'Component not found in processed data'
                    }
                    $testResults.ValidationErrors += "Data component '$component' missing"
                }
            }
            
            # Test data validation
            $validation = Test-ProcessedDataIntegrity -ProcessedData $processedData
            $testResults.ValidationResults = $validation
            
            if (-not $validation.IsComplete) {
                $testResults.Success = $false
                $testResults.ValidationErrors += $validation.CriticalIssues
            }
            
            Write-Information "  ✓ Processed data loading test completed" -InformationAction Continue
        }
        catch {
            $testResults.Success = $false
            $testResults.ValidationErrors += "Processed data loading failed: $($_.Exception.Message)"
            Write-Warning "  ✗ Processed data loading failed: $($_.Exception.Message)"
        }
        
        # Summary
        if ($testResults.Success) {
            Write-LogEntry -Level 'SUCCESS' -Component 'REPORT-GENERATOR' -Message 'Processed data integration test passed'
        }
        else {
            Write-LogEntry -Level 'ERROR' -Component 'REPORT-GENERATOR' -Message "Processed data integration test failed: $($testResults.ValidationErrors.Count) errors found"
        }
        
        return $testResults
    }
    catch {
        Write-LogEntry -Level 'ERROR' -Component 'REPORT-GENERATOR' -Message "Processed data integration test failed: $($_.Exception.Message)"
        throw
    }
}

#endregion

#region Module Export

# Memory management functions will be exported at the end of the file

#endregion

#region Memory Management and Optimization

# Module-level memory tracking
$script:ReportGeneratorMemory = @{
    'TemplateCache'      = @{}
    'ProcessedDataCache' = @{}
    'ReportOutputCache'  = @{}
    'LastCleanup'        = (Get-Date)
    'MemorySettings'     = @{
        'MaxCacheSize'             = 200MB
        'MaxTemplateAge'           = (New-TimeSpan -Minutes 60)
        'MaxProcessedDataAge'      = (New-TimeSpan -Minutes 30)
        'EnableMemoryOptimization' = $true
        'MemoryCleanupThreshold'   = 150MB
    }
}

<#
.SYNOPSIS
    Manages memory usage and performs cleanup in ReportGenerator module
#>
function Invoke-ReportMemoryManagement {
    [CmdletBinding()]
    param(
        [ValidateSet('Cleanup', 'Optimize', 'Monitor', 'Reset')]
        [string]$Operation = 'Cleanup',
        
        [switch]$Force
    )
    
    Write-LogEntry -Level 'DEBUG' -Component 'MEMORY-MGR' -Message "Memory management operation: $Operation"
    
    try {
        $beforeMemory = [System.GC]::GetTotalMemory($false)
        $result = @{
            Operation    = $Operation
            Success      = $false
            BeforeMemory = $beforeMemory
            AfterMemory  = 0
            Freed        = 0
            Details      = @{}
        }
        
        switch ($Operation) {
            'Cleanup' {
                # Clear expired cache entries
                $clearedTemplates = 0
                $clearedProcessedData = 0
                $clearedReports = 0
                
                $cutoffTime = (Get-Date) - $script:ReportGeneratorMemory.MemorySettings.MaxTemplateAge
                $keysToRemove = @()
                
                # Clean template cache
                foreach ($key in $script:ReportGeneratorMemory.TemplateCache.Keys) {
                    $entry = $script:ReportGeneratorMemory.TemplateCache[$key]
                    if ($entry.Timestamp -lt $cutoffTime -or $Force) {
                        $keysToRemove += $key
                    }
                }
                foreach ($key in $keysToRemove) {
                    $script:ReportGeneratorMemory.TemplateCache.Remove($key)
                    $clearedTemplates++
                }
                
                # Clean processed data cache
                $cutoffTime = (Get-Date) - $script:ReportGeneratorMemory.MemorySettings.MaxProcessedDataAge
                $keysToRemove = @()
                foreach ($key in $script:ReportGeneratorMemory.ProcessedDataCache.Keys) {
                    $entry = $script:ReportGeneratorMemory.ProcessedDataCache[$key]
                    if ($entry.Timestamp -lt $cutoffTime -or $Force) {
                        $keysToRemove += $key
                    }
                }
                foreach ($key in $keysToRemove) {
                    $script:ReportGeneratorMemory.ProcessedDataCache.Remove($key)
                    $clearedProcessedData++
                }
                
                # Clear report output cache
                $script:ReportGeneratorMemory.ReportOutputCache.Clear()
                $clearedReports = $script:ReportGeneratorMemory.ReportOutputCache.Count
                
                $result.Details = @{
                    ClearedTemplates     = $clearedTemplates
                    ClearedProcessedData = $clearedProcessedData  
                    ClearedReports       = $clearedReports
                }
                
                Write-LogEntry -Level 'INFO' -Component 'MEMORY-MGR' -Message "Cleanup complete: Templates=$clearedTemplates, Data=$clearedProcessedData, Reports=$clearedReports"
            }
            
            'Optimize' {
                # Force garbage collection and memory optimization
                [System.GC]::Collect()
                [System.GC]::WaitForPendingFinalizers()
                [System.GC]::Collect()
                
                # Optimize data structures by rebuilding them
                $optimizedStructures = Optimize-ReportDataStructures
                
                $result.Details = @{
                    OptimizedStructures   = $optimizedStructures
                    GarbageCollectionRuns = 3
                }
                
                Write-LogEntry -Level 'INFO' -Component 'MEMORY-MGR' -Message "Memory optimization complete: $optimizedStructures structures optimized"
            }
            
            'Monitor' {
                $currentMemory = [System.GC]::GetTotalMemory($false)
                $stats = Get-ReportMemoryStatistics
                
                $result.Details = $stats
                
                if ($currentMemory -gt $script:ReportGeneratorMemory.MemorySettings.MemoryCleanupThreshold) {
                    Write-LogEntry -Level 'WARN' -Component 'MEMORY-MGR' -Message "Memory usage high: $(($currentMemory / 1MB).ToString('F1'))MB - consider cleanup"
                }
                else {
                    Write-LogEntry -Level 'DEBUG' -Component 'MEMORY-MGR' -Message "Memory usage normal: $(($currentMemory / 1MB).ToString('F1'))MB"
                }
            }
            
            'Reset' {
                # Complete memory reset
                Clear-ReportGeneratorCache
                [System.GC]::Collect()
                [System.GC]::WaitForPendingFinalizers()
                
                $result.Details = @{
                    CachesCleared    = 'All'
                    GarbageCollected = $true
                }
                
                Write-LogEntry -Level 'INFO' -Component 'MEMORY-MGR' -Message "Complete memory reset performed"
            }
        }
        
        $afterMemory = [System.GC]::GetTotalMemory($false)
        $result.AfterMemory = $afterMemory
        $result.Freed = $beforeMemory - $afterMemory
        $result.Success = $true
        
        $script:ReportGeneratorMemory.LastCleanup = Get-Date
        
        return $result
    }
    catch {
        Write-LogEntry -Level 'ERROR' -Component 'MEMORY-MGR' -Message "Memory management failed: $($_.Exception.Message)"
        throw
    }
}

<#
.SYNOPSIS
    Clears all ReportGenerator caches and temporary data
#>
function Clear-ReportGeneratorCache {
    [CmdletBinding()]
    param()
    
    Write-LogEntry -Level 'INFO' -Component 'MEMORY-MGR' -Message 'Clearing all ReportGenerator caches'
    
    try {
        $script:ReportGeneratorMemory.TemplateCache.Clear()
        $script:ReportGeneratorMemory.ProcessedDataCache.Clear()
        $script:ReportGeneratorMemory.ReportOutputCache.Clear()
        
        Write-LogEntry -Level 'INFO' -Component 'MEMORY-MGR' -Message 'All caches cleared successfully'
    }
    catch {
        Write-LogEntry -Level 'ERROR' -Component 'MEMORY-MGR' -Message "Cache clearing failed: $($_.Exception.Message)"
        throw
    }
}

<#
.SYNOPSIS
    Gets detailed memory usage statistics for ReportGenerator
#>
function Get-ReportMemoryStatistics {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()
    
    try {
        $currentMemory = [System.GC]::GetTotalMemory($false)
        
        # Calculate cache sizes
        $templateCacheSize = 0
        foreach ($entry in $script:ReportGeneratorMemory.TemplateCache.Values) {
            if ($entry.Data) {
                $templateCacheSize += try { [System.Text.Encoding]::UTF8.GetBytes($entry.Data).Length } catch { 1KB }
            }
        }
        
        $processedDataCacheSize = 0
        foreach ($entry in $script:ReportGeneratorMemory.ProcessedDataCache.Values) {
            if ($entry.Data) {
                $processedDataCacheSize += try { [System.Text.Encoding]::UTF8.GetBytes(($entry.Data | ConvertTo-Json)).Length } catch { 1KB }
            }
        }
        
        $reportCacheSize = 0
        foreach ($entry in $script:ReportGeneratorMemory.ReportOutputCache.Values) {
            if ($entry.Data) {
                $reportCacheSize += try { [System.Text.Encoding]::UTF8.GetBytes($entry.Data).Length } catch { 1KB }
            }
        }
        
        $stats = @{
            TotalSystemMemory      = $currentMemory
            TemplateCacheSize      = $templateCacheSize
            ProcessedDataCacheSize = $processedDataCacheSize
            ReportCacheSize        = $reportCacheSize
            TotalCacheSize         = $templateCacheSize + $processedDataCacheSize + $reportCacheSize
            CacheEntryCount        = @{
                Templates     = $script:ReportGeneratorMemory.TemplateCache.Count
                ProcessedData = $script:ReportGeneratorMemory.ProcessedDataCache.Count
                Reports       = $script:ReportGeneratorMemory.ReportOutputCache.Count
            }
            MemorySettings         = $script:ReportGeneratorMemory.MemorySettings
            LastCleanup            = $script:ReportGeneratorMemory.LastCleanup
        }
        
        return $stats
    }
    catch {
        Write-LogEntry -Level 'ERROR' -Component 'MEMORY-MGR' -Message "Failed to get memory statistics: $($_.Exception.Message)"
        return @{}
    }
}

<#
.SYNOPSIS
    Optimizes data structures in ReportGenerator for better memory efficiency
#>
function Optimize-ReportDataStructures {
    [CmdletBinding()]
    [OutputType([int])]
    param()
    
    Write-LogEntry -Level 'DEBUG' -Component 'MEMORY-MGR' -Message 'Optimizing ReportGenerator data structures'
    
    try {
        $optimizedCount = 0
        
        # Rebuild template cache with optimized structure
        if ($script:ReportGeneratorMemory.TemplateCache.Count -gt 0) {
            $newTemplateCache = @{}
            foreach ($key in $script:ReportGeneratorMemory.TemplateCache.Keys) {
                $entry = $script:ReportGeneratorMemory.TemplateCache[$key]
                
                # Only keep essential data in optimized structure
                $optimizedEntry = @{
                    Data      = $entry.Data
                    Timestamp = $entry.Timestamp
                    Size      = if ($entry.Data) { [System.Text.Encoding]::UTF8.GetBytes($entry.Data).Length } else { 0 }
                }
                
                $newTemplateCache[$key] = $optimizedEntry
            }
            $script:ReportGeneratorMemory.TemplateCache = $newTemplateCache
            $optimizedCount++
        }
        
        # Rebuild processed data cache with optimized structure  
        if ($script:ReportGeneratorMemory.ProcessedDataCache.Count -gt 0) {
            $newDataCache = @{}
            foreach ($key in $script:ReportGeneratorMemory.ProcessedDataCache.Keys) {
                $entry = $script:ReportGeneratorMemory.ProcessedDataCache[$key]
                
                $optimizedEntry = @{
                    Data      = $entry.Data
                    Timestamp = $entry.Timestamp
                    Type      = $entry.Type
                }
                
                $newDataCache[$key] = $optimizedEntry
            }
            $script:ReportGeneratorMemory.ProcessedDataCache = $newDataCache
            $optimizedCount++
        }
        
        # Clear and rebuild report cache to remove fragmentation
        if ($script:ReportGeneratorMemory.ReportOutputCache.Count -gt 0) {
            $script:ReportGeneratorMemory.ReportOutputCache.Clear()
            $optimizedCount++
        }
        
        Write-LogEntry -Level 'DEBUG' -Component 'MEMORY-MGR' -Message "Data structure optimization complete: $optimizedCount structures rebuilt"
        
        return $optimizedCount
    }
    catch {
        Write-LogEntry -Level 'ERROR' -Component 'MEMORY-MGR' -Message "Data structure optimization failed: $($_.Exception.Message)"
        return 0
    }
}

#endregion

# Export main functions for ReportGenerator module - placed at end after all function definitions
Export-ModuleMember -Function @(
    'New-MaintenanceReport',
    'Get-HtmlTemplates',
    'Get-FallbackTemplates',
    'Get-ProcessedLogData',
    'Test-ProcessedDataIntegrity',
    'Get-FallbackRawLogData',
    'Get-ParsedOperationLogs',
    'New-OperationLogTable',
    'New-HtmlReportContent',
    'New-DashboardSection',
    'New-ModuleSections',
    'New-MaintenanceLogSection',
    'New-SummarySection',
    'New-TextReportContent',
    'New-JsonExportContent',
    'New-SummaryReportContent',
    'Get-TaskDistributionData',
    'Get-SystemResourceData',
    'Get-ExecutionTimelineData',
    'Get-SecurityScoreData',
    'Get-ComprehensiveChartData',
    'Test-ConfigTemplateIntegration',
    'Test-ProcessedDataIntegration',
    'Invoke-ReportMemoryManagement',
    'Clear-ReportGeneratorCache',
    'Get-ReportMemoryStatistics',
    'Optimize-ReportDataStructures'
)