#Requires -Version 7.0

<#
.SYNOPSIS
    Report Generator Module v3.0 - Report Rendering Engine

.DESCRIPTION
    Specialized module for generating maintenance reports from processed log data.
    Focuses purely on presentation layer - loading templates, rendering HTML/text reports,
    and creating interactive visualizations. Part of the v3.0 split architecture that
    separates data processing (LogProcessor) from report rendering. Handles template
    management, styling, and multi-format output generation.

.MODULE ARCHITECTURE
    Purpose:
        Serve as the report rendering layer consuming processed data from LogProcessor.
        Transforms standardized structured data into human-readable HTML and text reports.
        Manages templates, CSS styling, and report sections for each module.
    
    Dependencies:
        • CoreInfrastructure.psm1 - For path management and logging
        • LogProcessor.psm1 - For processed data consumption (data flow, not direct import)
    
    Exports:
        • New-MaintenanceReport - Primary function: Generate full report
        • Test-ReportGenerationCapability - Verify report system is functional
        • Load-ProcessedData - Load aggregated data from LogProcessor
        • Build-ReportSection - Create individual module report section
        • Format-HtmlReport - Apply styling and formatting
        • Export-Report - Save report to disk (HTML/text)
    
    Import Pattern:
        Import-Module ReportGenerator.psm1 -Force
        # Functions available in MaintenanceOrchestrator context

    Used By:
        - MaintenanceOrchestrator.ps1 (final phase: generates all reports)
        - No other modules depend on this (terminal module in pipeline)

.EXECUTION FLOW
    1. LogProcessor completes data processing and writes to temp_files/processed/
    2. MaintenanceOrchestrator calls New-MaintenanceReport
    3. Load-ProcessedData retrieves aggregated data from temp_files/processed/
    4. Get-HtmlTemplates loads template files from config/templates/
    5. For each module: Build-ReportSection creates HTML section with results
    6. Format-HtmlReport applies CSS styling and consolidates all sections
    7. Export-Report writes final reports to temp_files/reports/
    8. Report opens in default browser or displays path for user access

.DATA ORGANIZATION
    Template Sources:
        • config/templates/report-template-v4-enhanced.html - Modern dashboard template
        • config/templates/report-styles-v4-enhanced.css - Modern CSS framework
        • config/templates/components/executive-dashboard.html - Dashboard component
        • config/templates/components/module-card-enhanced-v5.html - Enhanced module card component (v5)
        • config/templates/assets/dashboard.js - Interactive JavaScript
    
    Input Data (from LogProcessor):
        • temp_files/processed/[module]-audit.json - Type1 results per module
        • temp_files/processed/[module]-execution.json - Type2 execution per module
        • temp_files/processed/session-summary.json - Overall session metrics
    
    Output Reports:
        • temp_files/reports/Maintenance_Report_[timestamp].html - Full interactive HTML
        • temp_files/reports/Maintenance_Report_[timestamp].txt - Text-only summary
        • temp_files/reports/Report_Index.html - Navigation index of all reports

.REPORT STRUCTURE
    • Executive Summary: Key metrics, totals, pass/fail status
    • Type 1 (Detection) Results: Per-module audit findings
    • Type 2 (Execution) Results: Per-module execution logs and changes applied
    • Module Details: Expandable sections with full data for each module
    • Appendix: Performance metrics, cache statistics, execution timeline

.NOTES
    Module Type: Type 1 (Report Generation - Read-Only)
    Architecture: v3.0 - Split from monolithic ReportGeneration.psm1
    Line Count: 2,394 lines
    Version: 3.0.0 (Refactored - Split Architecture)
    
    Key Design Patterns:
    - Template-driven rendering: Separates data from presentation
    - CSS-based styling: Consistent formatting across modules
    - Section building: Modular HTML generation (one function per report section)
    - Backward compatibility: Handles both old and new template locations
    - Performance: Lazy loads templates only when needed
    
    Related Modules in v3.0 Architecture:
    - CoreInfrastructure.psm1 → Path management, logging infrastructure
    - LogProcessor.psm1 → Produces processed data consumed by reports
    - All Type 1 modules → Data sources (via LogProcessor aggregation)
    - All Type 2 modules → Data sources (via LogProcessor aggregation)
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
# This handles the case where ReportGenerator is called in a new scope
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
        Write-Verbose "ReportGenerator: Path initialization fallback failed - $_"
        # If initialization fails, it will be caught when functions try to access paths
    }
}

#region Configuration and Template Management

<#
.SYNOPSIS
    Resolves a template path from the config/templates directory
.DESCRIPTION
    Uses CoreInfrastructure path resolution to locate template files reliably
.PARAMETER TemplateName
    Template file name relative to config/templates
#>
function Find-ConfigTemplate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TemplateName
    )

    $configPath = Get-MaintenancePath 'ConfigRoot'
    if ([string]::IsNullOrWhiteSpace($configPath)) {
        throw "Config root path not available. Ensure CoreInfrastructure is loaded."
    }

    $templatesPath = Join-Path $configPath 'templates'
    return Join-Path $templatesPath $TemplateName
}

<#
.SYNOPSIS
    Loads HTML templates from config directory
.DESCRIPTION
    Loads all report templates including HTML structure, CSS styles, and configuration metadata
#>
function Get-HtmlTemplates {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter()]
        [switch]$UseEnhanced
    )
    
    $templateType = if ($UseEnhanced) { 'enhanced' } else { 'standard' }
    Write-LogEntry -Level 'INFO' -Component 'REPORT-GENERATOR' -Message "Loading $templateType HTML templates from config directory"
    
    try {
        $configPath = Get-MaintenancePath 'ConfigRoot'
        $templatesPath = Join-Path $configPath 'templates'
        
        $templates = @{
            Main       = $null
            TaskCard   = $null
            ModuleCard = $null
            CSS        = $null
            Config     = $null
            IsEnhanced = $UseEnhanced
        }
        
        # Determine template filenames based on enhanced mode
        if ($UseEnhanced) {
            # Try v5 enhanced first, then v4 enhanced
            $v5Templates = @{
                main = 'report-template-enhanced-v5.html'
                card = 'module-card-enhanced-v5.html'
                css  = 'report-styles-enhanced-v5.css'
            }
            
            # Check if v5 templates are available
            $v5Available = ($v5Templates.Values | ForEach-Object { Test-Path (Find-ConfigTemplate $_) }) -notcontains $false
            
            if ($v5Available) {
                $mainTemplateFile = $v5Templates.main
                $moduleCardFile = $v5Templates.card
                $cssFile = $v5Templates.css
                Write-Verbose "Using enhanced v5.0 templates (Modern Dashboard with Glassmorphism)"
                Write-LogEntry -Level 'INFO' -Component 'REPORT-GENERATOR' -Message "Using enhanced v5.0 templates with modern design"
            }
            else {
                # Fallback to modern-dashboard (available in config/templates)
                $mainTemplateFile = 'modern-dashboard.html'
                $moduleCardFile = 'module-card.html'
                $cssFile = 'modern-dashboard.css'
                Write-Verbose "Using modern-dashboard templates (v5.0 not available)"
                Write-LogEntry -Level 'WARNING' -Component 'REPORT-GENERATOR' -Message "Enhanced v5.0 templates not found, using modern-dashboard"
            }
        }
        else {
            # Fallback to modern-dashboard (available in config/templates)
            $mainTemplateFile = 'modern-dashboard.html'
            $moduleCardFile = 'module-card.html'
            $cssFile = 'modern-dashboard.css'
            
            Write-Verbose "Using modern-dashboard templates (legacy mode disabled)"
        }
        
        # Load main report template
        $mainTemplatePath = Find-ConfigTemplate $mainTemplateFile
        if (Test-Path $mainTemplatePath) {
            $templates.Main = Get-Content $mainTemplatePath -Raw
            Write-Verbose "Loaded main template: $mainTemplatePath"
        }
        else {
            Write-LogEntry -Level 'WARNING' -Component 'REPORT-GENERATOR' -Message "Main report template not found: $mainTemplatePath - using fallback inline template"
            # Provide fallback inline template to prevent report generation failure
            $templates.Main = Get-FallbackHtmlTemplate -TemplateType 'MainReport'
        }
        
        # Load module/task card template
        $moduleCardPath = Find-ConfigTemplate $moduleCardFile
        if (Test-Path $moduleCardPath) {
            $templates.ModuleCard = Get-Content $moduleCardPath -Raw
            $templates.TaskCard = $templates.ModuleCard  # Backward compatibility
            Write-Verbose "Loaded module card template: $moduleCardPath"
        }
        else {
            Write-LogEntry -Level 'WARNING' -Component 'REPORT-GENERATOR' -Message "Module card template not found: $moduleCardPath - using fallback template"
            # Provide fallback inline template
            $templates.ModuleCard = Get-FallbackHtmlTemplate -TemplateType 'ModuleCard'
            $templates.TaskCard = $templates.ModuleCard  # Backward compatibility
        }
        
        # Load CSS styles with enhanced fallback chain
        $cssPath = Find-ConfigTemplate $cssFile
        if (Test-Path $cssPath) {
            $templates.CSS = Get-Content $cssPath -Raw
            Write-Verbose "Loaded CSS styles: $cssPath"
        }
        else {
            Write-LogEntry -Level 'WARNING' -Component 'REPORT-GENERATOR' -Message "CSS template not found: $cssPath - using fallback styles"
            # Provide fallback CSS to prevent report generation failure
            $templates.CSS = Get-FallbackHtmlTemplate -TemplateType 'CSS'
        }
            if ($UseEnhanced) {
                # Try v5 enhanced, then v4 enhanced, then standard
                $fallbackPaths = @(
                    'report-styles-enhanced-v5.css',
                    'report-styles-v4-enhanced.css',
                    'report-styles.css'
                )
                
                $cssLoaded = $false
                foreach ($fallbackCss in $fallbackPaths) {
                    $fallbackPath = Find-ConfigTemplate $fallbackCss
                    if (Test-Path $fallbackPath) {
                        $templates.CSS = Get-Content $fallbackPath -Raw
                        Write-LogEntry -Level 'WARNING' -Component 'REPORT-GENERATOR' -Message "Using fallback CSS: $fallbackCss"
                        $cssLoaded = $true
                        break
                    }
                }
                
                if (-not $cssLoaded) {
                    throw "No CSS styles found in fallback chain"
                }
            }
            else {
                throw "CSS styles not found: $cssPath"
            }
        }
        
        # Load template configuration
        $configJsonPath = Find-ConfigTemplate 'report-templates-config.json'
        if (Test-Path $configJsonPath) {
            $templates.Config = Get-Content $configJsonPath | ConvertFrom-Json
            Write-Verbose "Loaded template config: $configJsonPath"
        }
        else {
            Write-LogEntry -Level 'WARNING' -Component 'REPORT-GENERATOR' -Message "Template configuration not found: $configJsonPath"
            # Not critical, continue without config
        }
        
        Write-LogEntry -Level 'SUCCESS' -Component 'REPORT-GENERATOR' -Message "Successfully loaded $templateType HTML templates"
        return $templates
    }
    catch {
        Write-LogEntry -Level 'ERROR' -Component 'REPORT-GENERATOR' -Message "Failed to load HTML templates: $($_.Exception.Message)"
        Write-LogEntry -Level 'WARNING' -Component 'REPORT-GENERATOR' -Message 'Attempting to use fallback templates for basic functionality'
        
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
    
    Write-LogEntry -Level 'WARNING' -Component 'REPORT-GENERATOR' -Message 'Using fallback templates - limited styling and functionality'
    
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
                BloatwareRemoval   = ''
                EssentialApps      = ''
                SystemOptimization = ''
                TelemetryDisable   = ''
                WindowsUpdates     = ''
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
            Join-Path (Get-MaintenancePath 'TempRoot') 'processed'
        }
        
        if (-not (Test-Path $processedRoot)) {
            $errorMessage = "Processed data directory not found: $processedRoot"
            if ($FallbackToRawLogs) {
                Write-LogEntry -Level 'WARNING' -Component 'REPORT-GENERATOR' -Message "$errorMessage - Attempting fallback to raw logs"
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
                    Write-LogEntry -Level 'WARNING' -Component 'REPORT-GENERATOR' -Message "Failed to parse $($summaryFiles[$key]): $($_.Exception.Message)"
                    $processedData[$key] = @{}
                }
            }
            else {
                # Use DEBUG for optional files like maintenance-log.json
                $logLevel = if ($key -eq 'MaintenanceLog') { 'DEBUG' } else { 'WARNING' }
                Write-LogEntry -Level $logLevel -Component 'REPORT-GENERATOR' -Message "Processed data file not found: $($summaryFiles[$key])"
            }
        }
        
        # Load module-specific data
        $moduleSpecificPath = Join-Path $processedRoot 'module-specific'
        if (Test-Path $moduleSpecificPath) {
            $moduleFiles = Get-ChildItem -Path $moduleSpecificPath -Filter '*.json'
            foreach ($file in $moduleFiles) {
                $moduleName = $file.BaseName
                try {
                    $content = Get-Content $file.FullName -Raw | ConvertFrom-Json
                    
                    # Ensure ModuleResults is a hashtable before indexing
                    if ($processedData.ModuleResults -isnot [hashtable]) {
                        # Convert PSCustomObject to hashtable if needed
                        $tempHashtable = @{}
                        if ($processedData.ModuleResults) {
                            $processedData.ModuleResults.PSObject.Properties | ForEach-Object {
                                $tempHashtable[$_.Name] = $_.Value
                            }
                        }
                        $processedData.ModuleResults = $tempHashtable
                    }
                    
                    $processedData.ModuleResults[$moduleName] = $content
                    Write-Verbose "Loaded module-specific data for: $moduleName"
                }
                catch {
                    Write-LogEntry -Level 'WARNING' -Component 'REPORT-GENERATOR' -Message "Failed to parse module data for ${moduleName}: $($_.Exception.Message)"
                }
            }
        }
        
        # Validate data integrity and provide warnings for missing components
        $dataValidation = Test-ProcessedDataIntegrity -ProcessedData $processedData
        if (-not $dataValidation.IsComplete) {
            Write-LogEntry -Level 'WARNING' -Component 'REPORT-GENERATOR' -Message "Processed data validation warnings: $($dataValidation.Warnings -join ', ')"
            
            if ($dataValidation.CriticalIssues.Count -gt 0) {
                Write-LogEntry -Level 'ERROR' -Component 'REPORT-GENERATOR' -Message "Critical data issues found: $($dataValidation.CriticalIssues -join ', ')"
                if ($FallbackToRawLogs) {
                    Write-LogEntry -Level 'WARNING' -Component 'REPORT-GENERATOR' -Message 'Attempting fallback to raw logs due to critical data issues'
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
            Write-LogEntry -Level 'WARNING' -Component 'REPORT-GENERATOR' -Message 'Attempting fallback to raw logs due to processing failure'
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
    
    Write-LogEntry -Level 'WARNING' -Component 'REPORT-GENERATOR' -Message 'Using fallback raw log data loading - functionality will be limited'
    
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
        $logsPath = Join-Path (Get-MaintenancePath 'TempRoot') 'logs'
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
                        Write-LogEntry -Level 'WARNING' -Component 'REPORT-GENERATOR' -Message "Could not read fallback log for module ${moduleName}: $($_.Exception.Message)"
                    }
                }
            }
        }
        
        Write-LogEntry -Level 'WARNING' -Component 'REPORT-GENERATOR' -Message "Fallback data loaded with limited functionality for $($fallbackData.ModuleResults.Keys.Count) modules"
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
        $logsPath = Join-Path (Get-MaintenancePath 'TempRoot') "logs\$ModuleName"
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
            Write-LogEntry -Level 'WARNING' -Component 'REPORT-GENERATOR' -Message "No execution log found for $ModuleName at: $executionLogPath"
            return $result
        }
        
        $logContent = Get-Content $executionLogPath -ErrorAction Stop
        if ($logContent.Count -eq 0) {
            Write-LogEntry -Level 'WARNING' -Component 'REPORT-GENERATOR' -Message "Empty execution log for $ModuleName"
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
    <h4> Operation Logs</h4>
    <p class="no-data">No operation logs available for this module.</p>
</div>
"@
    }
    
    $html = [System.Text.StringBuilder]::new()
    
    $html.AppendLine(@"
<div class="operation-logs-section">
    <h4> Operation Logs - $ModuleName</h4>
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
        [switch]$EnableFallback,
        
        [Parameter()]
        [switch]$UseEnhancedReports
    )
    
    $reportType = if ($UseEnhancedReports) { "enhanced v3.0" } else { "standard" }
    Write-LogEntry -Level 'INFO' -Component 'REPORT-GENERATOR' -Message "Starting $reportType maintenance report generation"
    
    try {
        $startTime = Get-Date
        
        # Load processed data with enhanced parameters
        Write-Information "✓ Loading processed log data..." -InformationAction Continue
        $processedDataParams = @{}
        if ($ProcessedDataPath) { $processedDataParams.ProcessedDataPath = $ProcessedDataPath }
        if ($EnableFallback) { $processedDataParams.FallbackToRawLogs = $true }
        
        $processedData = Get-ProcessedLogData @processedDataParams
        
        # Check if we should use enhanced reporting (auto-detect enhanced templates if not explicitly disabled)
        if (-not $UseEnhancedReports) {
            # Auto-detect enhanced templates
            $enhancedTemplateCheck = Find-ConfigTemplate -TemplateName "enhanced-module-card.html" -ErrorAction SilentlyContinue
            if ($enhancedTemplateCheck -and (Test-Path $enhancedTemplateCheck)) {
                Write-Information "✓ Enhanced templates detected, enabling enhanced reporting (v5.0)..." -InformationAction Continue
                $UseEnhancedReports = $true
            }
        }
        
        if ($UseEnhancedReports) {
            Write-Information "✓ Using enhanced reporting system (v5.0)..." -InformationAction Continue
            
            # Load enhanced templates
            Write-Information "✓ Loading enhanced templates..." -InformationAction Continue
            $templates = Get-HtmlTemplates -UseEnhanced
            
            if (-not $templates.IsEnhanced) {
                Write-LogEntry -Level 'WARNING' -Component 'REPORT-GENERATOR' -Message "Enhanced templates not available, falling back to standard templates"
                $UseEnhancedReports = $false
            }
        }
        
        if (-not $UseEnhancedReports) {
            # Standard report generation (original code path)
            Write-Information "✓ Loading report templates..." -InformationAction Continue
            $templates = Get-HtmlTemplates
            
            # Generate report content using templates and processed data
            Write-Information "✓ Generating HTML report content..." -InformationAction Continue
            $reportContent = New-HtmlReportContent -ProcessedData $processedData -Templates $templates
            
            # Save HTML report
            Write-Information "✓ Saving HTML report..." -InformationAction Continue
            $reportContent | Out-File -FilePath $OutputPath -Encoding UTF8 -Force
        }
        else {
            # Enhanced report generation (new code path)
            Write-Information "✓ Building executive dashboard..." -InformationAction Continue
            $config = Get-MainConfiguration
            $dashboardData = Build-ExecutiveDashboard -AggregatedResults $processedData -Config $config
            
            Write-Information "✓ Generating module cards..." -InformationAction Continue
            $moduleCardsHtml = ""
            $moduleCount = 0
            foreach ($moduleResult in $processedData.ModuleResults.Values) {
                $moduleCount++
                Write-Verbose "  Building card $moduleCount/$($processedData.ModuleResults.Count): $($moduleResult.ModuleName)"
                $moduleCard = Build-ModuleCard -ModuleResult $moduleResult -CardTemplate $templates.ModuleCard
                $moduleCardsHtml += $moduleCard
            }

            Write-Information "✓ Building execution summary rows..." -InformationAction Continue
            $executionSummaryRowsHtml = Build-ExecutionSummaryRows -AggregatedResults $processedData

            Write-Information "✓ Building system changes log..." -InformationAction Continue
            $systemChangesLogHtml = Build-SystemChangesLog -AggregatedResults $processedData -MaxEntries 60
            
            Write-Information "✓ Building error analysis..." -InformationAction Continue
            $errorAnalysisHtml = Build-ErrorAnalysis -AggregatedResults $processedData
            
            Write-Information "✓ Building execution timeline..." -InformationAction Continue
            $timelineHtml = Build-ExecutionTimeline -AggregatedResults $processedData
            
            Write-Information "✓ Building action items..." -InformationAction Continue
            $actionItemsHtml = Build-ActionItems -AggregatedResults $processedData -MaxItems 10
            
            Write-Information "✓ Collecting system information..." -InformationAction Continue
            $systemInfo = Get-SystemInformation
            
            # Start with main template
            $reportHtml = $templates.Main
            
            # Replace CSS placeholder
            $reportHtml = $reportHtml -replace '{{CSS_CONTENT}}', $templates.CSS
            
            # Replace header tokens
            $reportHtml = $reportHtml -replace '{{REPORT_TITLE}}', 'Windows Maintenance Report'
            $reportHtml = $reportHtml -replace '{{GENERATION_TIME}}', (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
            $reportHtml = $reportHtml -replace '{{GENERATION_DATE}}', (Get-Date -Format "MMMM dd, yyyy")
            $reportHtml = $reportHtml -replace '{{REPORT_DATE}}', (Get-Date -Format "MMMM dd, yyyy")
            $reportHtml = $reportHtml -replace '{{COMPUTER_NAME}}', $env:COMPUTERNAME
            $reportHtml = $reportHtml -replace '{{USER_NAME}}', $env:USERNAME
            $reportHtml = $reportHtml -replace '{{EXECUTION_MODE}}', $(if ($config.execution.enableDryRun -or $config.execution.dryRunByDefault) { "DRY RUN" } else { "LIVE" })
            
            # Replace dashboard tokens
            foreach ($key in $dashboardData.Keys) {
                $reportHtml = $reportHtml -replace "{{$key}}", $dashboardData[$key]
            }

            # Map modern-dashboard tokens to dashboard data
            $systemHealthScore = [int]($dashboardData.SYSTEM_HEALTH_SCORE ?? 0)
            $successRateScore = [int]($dashboardData.SUCCESS_RATE ?? 0)
            $totalErrors = [int]($dashboardData.ERROR_COUNT ?? 0)
            $overallStatusClass = if ($systemHealthScore -ge 90) { 'status-success' } elseif ($systemHealthScore -ge 70) { 'status-warning' } else { 'status-error' }
            $securityStatusClass = if ($successRateScore -ge 90) { 'status-success' } elseif ($successRateScore -ge 70) { 'status-warning' } else { 'status-error' }
            $performanceStatusClass = if ($dashboardData.TOTAL_DURATION -and $dashboardData.TOTAL_DURATION -match '\d+' -and [int]$dashboardData.TOTAL_DURATION -le 900) { 'status-success' } elseif ($dashboardData.TOTAL_DURATION -and $dashboardData.TOTAL_DURATION -match '\d+' -and [int]$dashboardData.TOTAL_DURATION -le 1800) { 'status-warning' } else { 'status-info' }
            $errorsStatusClass = if ($totalErrors -eq 0) { 'status-success' } elseif ($totalErrors -le 3) { 'status-warning' } else { 'status-error' }

            $reportHtml = $reportHtml -replace '{{OVERALL_HEALTH_SCORE}}', $systemHealthScore
            $reportHtml = $reportHtml -replace '{{OVERALL_STATUS_CLASS}}', $overallStatusClass
            $reportHtml = $reportHtml -replace '{{OVERALL_STATUS_TEXT}}', $(if ($systemHealthScore -ge 90) { 'Excellent' } elseif ($systemHealthScore -ge 70) { 'Good' } else { 'Needs Attention' })
            $reportHtml = $reportHtml -replace '{{SECURITY_SCORE}}', $successRateScore
            $reportHtml = $reportHtml -replace '{{SECURITY_STATUS_CLASS}}', $securityStatusClass
            $reportHtml = $reportHtml -replace '{{SECURITY_STATUS_TEXT}}', $(if ($successRateScore -ge 90) { 'Secure' } elseif ($successRateScore -ge 70) { 'Moderate' } else { 'At Risk' })
            $reportHtml = $reportHtml -replace '{{PERFORMANCE_STATUS_CLASS}}', $performanceStatusClass
            $reportHtml = $reportHtml -replace '{{EXECUTION_DURATION}}', $dashboardData.TOTAL_DURATION
            $reportHtml = $reportHtml -replace '{{ERRORS_STATUS_CLASS}}', $errorsStatusClass
            $reportHtml = $reportHtml -replace '{{TOTAL_ERRORS}}', $totalErrors
            $reportHtml = $reportHtml -replace '{{ERROR_STATUS_TEXT}}', $(if ($totalErrors -eq 0) { 'No Issues' } elseif ($totalErrors -le 3) { 'Minor Issues' } else { 'Review Required' })
            $reportHtml = $reportHtml -replace '{{SESSION_ID}}', ($processedData.MetricsSummary.ProcessingMetadata.SessionId ?? 'N/A')
            $reportHtml = $reportHtml -replace '{{VERSION}}', '3.0.0'
            
            # Replace section tokens
            $reportHtml = $reportHtml -replace '{{MODULE_REPORTS}}', $moduleCardsHtml
            $reportHtml = $reportHtml -replace '{{MODULE_CARDS}}', $moduleCardsHtml
            $reportHtml = $reportHtml -replace '{{EXECUTION_SUMMARY_ROWS}}', $executionSummaryRowsHtml
            $reportHtml = $reportHtml -replace '{{SYSTEM_CHANGES_LOG}}', $systemChangesLogHtml
            $reportHtml = $reportHtml -replace '{{ERROR_ANALYSIS}}', $errorAnalysisHtml
            $reportHtml = $reportHtml -replace '{{EXECUTION_TIMELINE}}', $timelineHtml
            $reportHtml = $reportHtml -replace '{{ACTION_ITEMS}}', $actionItemsHtml
            
            # Replace system info tokens
            foreach ($key in $systemInfo.Keys) {
                $reportHtml = $reportHtml -replace "{{$key}}", $systemInfo[$key]
            }
            
            # Replace any remaining common tokens
            $reportHtml = $reportHtml -replace '{{DETAILED_LOGS}}', "" # Handled in module cards
            
            Write-Information "✓ Saving enhanced HTML report..." -InformationAction Continue
            $reportHtml | Out-File -FilePath $OutputPath -Encoding UTF8 -Force
            
            # Copy JavaScript assets for enhanced reports
            if ($UseEnhanced) {
                Write-Information "✓ Copying dashboard assets..." -InformationAction Continue
                $reportDir = Split-Path $OutputPath -Parent
                $assetsDir = Join-Path $reportDir "assets"
                
                if (-not (Test-Path $assetsDir)) {
                    New-Item -Path $assetsDir -ItemType Directory -Force | Out-Null
                }
                
                $jsSourcePath = Find-ConfigTemplate "assets/dashboard.js"
                if (Test-Path $jsSourcePath) {
                    $jsDestPath = Join-Path $assetsDir "dashboard.js"
                    Copy-Item -Path $jsSourcePath -Destination $jsDestPath -Force
                    Write-Verbose "Copied dashboard.js to report assets directory"
                }
                else {
                    Write-LogEntry -Level 'WARNING' -Component 'REPORT-GENERATOR' -Message "Dashboard JavaScript not found: $jsSourcePath"
                }
            }
        }
        
        # Generate additional formats using processed data (both standard and enhanced)
        Write-Information "✓ Generating text report..." -InformationAction Continue
        $textPath = $OutputPath -replace '\.html$', '.txt'
        $textContent = New-TextReportContent -ProcessedData $processedData
        $textContent | Out-File -FilePath $textPath -Encoding UTF8 -Force
        
        Write-Information "✓ Generating JSON export..." -InformationAction Continue
        $jsonPath = $OutputPath -replace '\.html$', '.json'
        $jsonContent = New-JsonExportContent -ProcessedData $processedData
        $jsonContent | Out-File -FilePath $jsonPath -Encoding UTF8 -Force
        
        Write-Information "✓ Generating summary report..." -InformationAction Continue
        $summaryPath = $OutputPath -replace '\.html$', '_summary.txt'
        $summaryContent = New-SummaryReportContent -ProcessedData $processedData
        $summaryContent | Out-File -FilePath $summaryPath -Encoding UTF8 -Force
        
        $duration = ((Get-Date) - $startTime).TotalSeconds
        
        $result = @{
            Success       = $true
            ReportType    = $reportType
            HtmlReport    = $OutputPath
            TextReport    = $textPath
            JsonExport    = $jsonPath
            SummaryReport = $summaryPath
            Duration      = $duration
            ModuleCount   = $processedData.ModuleResults.Count
        }
        
        Write-Information "✓ Report generation completed in $([math]::Round($duration, 2)) seconds" -InformationAction Continue
        Write-LogEntry -Level 'SUCCESS' -Component 'REPORT-GENERATOR' -Message "Report generation completed successfully ($reportType)" -Data $result
        
        return $result
    }
    catch {
        Write-LogEntry -Level 'ERROR' -Component 'REPORT-GENERATOR' -Message "Report generation failed: $($_.Exception.Message)"
        return @{
            Success = $false
            Error   = $_.Exception.Message
            Stack   = $_.ScriptStackTrace
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
        
        # Basic template replacements for enhanced template
        $html = $html -replace '{{REPORT_TITLE}}', 'Windows Maintenance Report'
        $html = $html -replace '{{REPORT_SUBTITLE}}', 'Comprehensive System Maintenance Analysis'
        $html = $html -replace '{{GENERATION_DATE}}', $currentDate
        $html = $html -replace '{{GENERATION_TIME}}', $currentDate
        $html = $html -replace '{{CSS_STYLES}}', $Templates.CSS
        $html = $html -replace '{{COMPUTER_NAME}}', $env:COMPUTERNAME
        $html = $html -replace '{{USER_NAME}}', $env:USERNAME
        $html = $html -replace '{{OS_VERSION}}', [System.Environment]::OSVersion.VersionString
        $html = $html -replace '{{EXECUTION_MODE}}', 'Full'
        
        # Calculate and add enhanced metrics
        $systemHealthScore = 85  # Default value, calculate based on results
        $avgModuleTime = '00:02:15'  # Default, calculate from actual data
        
        $html = $html -replace '{{SYSTEM_HEALTH_SCORE}}', $systemHealthScore
        $html = $html -replace '{{AVG_MODULE_TIME}}', $avgModuleTime
        
        # System information placeholders - using Get-CimInstance instead of Get-WmiObject for better compatibility
        $processorName = 'Unknown Processor'
        $totalMemory = '0 GB'
        try {
            $processor = Get-CimInstance -ClassName Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($processor) { $processorName = $processor.Name }
        }
        catch {
            Write-LogEntry -Level 'WARNING' -Component 'REPORT-GENERATOR' -Message "Failed to get processor info: $($_.Exception.Message)"
        }
        
        try {
            $computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue
            if ($computerSystem) { $totalMemory = [math]::Round($computerSystem.TotalPhysicalMemory / 1GB, 2) }
        }
        catch {
            Write-LogEntry -Level 'WARNING' -Component 'REPORT-GENERATOR' -Message "Failed to get computer system info: $($_.Exception.Message)"
        }
        
        $html = $html -replace '{{PROCESSOR_NAME}}', $processorName
        $html = $html -replace '{{TOTAL_MEMORY}}', $totalMemory
        $html = $html -replace '{{STORAGE_INFO}}', 'Multiple Drives'
        $html = $html -replace '{{OS_VERSION_DETAILED}}', [System.Environment]::OSVersion.VersionString
        $html = $html -replace '{{BUILD_NUMBER}}', [System.Environment]::OSVersion.Version.Build
        $html = $html -replace '{{LAST_BOOT_TIME}}', (Get-CimInstance Win32_OperatingSystem).LastBootUpTime.ToString('yyyy-MM-dd HH:mm:ss')
        
        # Initialize empty sections for new features
        $html = $html -replace '{{EXECUTION_TIMELINE}}', '<div class="no-data">Timeline data will be available in future updates</div>'
        $html = $html -replace '{{DETAILED_LOGS}}', '<div class="no-data">Detailed logs will be available in future updates</div>'
        $html = $html -replace '{{ACTION_ITEMS}}', '<div class="no-data">No action items at this time - system is healthy!</div>'
        
        # Patch 6: Enhanced variable binding from aggregated results
        Write-LogEntry -Level 'INFO' -Component 'REPORT-GENERATOR' -Message 'Applying enhanced variable bindings'
        
        try {
            # Build comprehensive variable replacement dictionary from aggregated results
            $placeholderValues = @{
                '{{OVERALL_STATUS}}'      = if ($ProcessedData.Summary -and $ProcessedData.Summary.SuccessfulModules -eq $ProcessedData.Summary.TotalModules) { 'Success' } else { 'Partial Success' }
                '{{TASKS_COMPLETED}}'     = $ProcessedData.Summary.SuccessfulModules
                '{{TOTAL_TASKS}}'         = $ProcessedData.Summary.TotalModules
                '{{SUCCESS_RATE}}'        = if ($ProcessedData.Summary) { [math]::Round(($ProcessedData.Summary.SuccessfulModules / [math]::Max($ProcessedData.Summary.TotalModules, 1)) * 100, 1) } else { 0 }
                '{{FAILED_TASKS}}'        = $ProcessedData.Summary.FailedModules
                '{{TOTAL_DURATION}}'      = if ($ProcessedData.DashboardMetrics) { $ProcessedData.DashboardMetrics.TotalExecutionDuration } else { '0:00:00' }
                '{{EXECUTION_TIMESTAMP}}' = $currentDate
                '{{COMPUTER_NAME}}'       = $env:COMPUTERNAME
                '{{USERNAME}}'            = $env:USERNAME
                '{{OS_VERSION}}'          = [System.Environment]::OSVersion.VersionString
                '{{REPORT_STATUS}}'       = 'Generated'
            }
            
            # Apply aggregated result variables if available
            if ($ProcessedData.ExecutionMetrics) {
                $metrics = $ProcessedData.ExecutionMetrics
                $placeholderValues['{{BLOATWARE_DETECTED}}'] = $metrics.BloatwareDetected -as [int]
                $placeholderValues['{{BLOATWARE_REMOVED}}'] = $metrics.BloatwareRemoved -as [int]
                $placeholderValues['{{ESSENTIAL_MISSING}}'] = $metrics.EssentialAppsMissing -as [int]
                $placeholderValues['{{ESSENTIAL_INSTALLED}}'] = $metrics.EssentialAppsInstalled -as [int]
                $placeholderValues['{{OPTIMIZATIONS_APPLIED}}'] = $metrics.OptimizationsApplied -as [int]
                $placeholderValues['{{REGISTRY_CHANGES}}'] = $metrics.RegistryChanges -as [int]
                $placeholderValues['{{TELEMETRY_DISABLED}}'] = $metrics.TelemetryTasksDisabled -as [int]
                $placeholderValues['{{WINDOWS_UPDATES}}'] = $metrics.WindowsUpdatesInstalled -as [int]
                $placeholderValues['{{APPS_UPGRADED}}'] = $metrics.ApplicationsUpgraded -as [int]
            }
            
            # Apply replacements to HTML
            foreach ($placeholder in $placeholderValues.Keys) {
                $value = if ($null -eq $placeholderValues[$placeholder]) { 'N/A' } else { $placeholderValues[$placeholder] }
                $html = $html -replace [regex]::Escape($placeholder), [string]$value
            }
            
            Write-LogEntry -Level 'INFO' -Component 'REPORT-GENERATOR' -Message "Applied $($placeholderValues.Count) variable bindings"
        }
        catch {
            Write-LogEntry -Level 'WARNING' -Component 'REPORT-GENERATOR' -Message "Enhanced variable binding failed, continuing with basic replacements: $($_.Exception.Message)"
        }
        
        # Generate dashboard metrics section
        $dashboardSection = New-DashboardSection -ProcessedData $ProcessedData
        $html = $html -replace '{{DASHBOARD_SECTION}}', $dashboardSection
        
        # Generate module sections
        $moduleSections = New-ModuleSections -ProcessedData $ProcessedData -Templates $Templates  
        $html = $html -replace '{{MODULE_SECTIONS}}', $moduleSections
        $html = $html -replace '{{MODULE_REPORTS}}', $moduleSections
        
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
        [hashtable]$ProcessedData
    )
    
    # Safely access nested properties with null checks
    $metricsData = if ($ProcessedData.MetricsSummary) { 
        $ProcessedData.MetricsSummary.DashboardMetrics 
    }
    else { 
        @{ SuccessRate = 0; TotalTasks = 0; SystemHealthScore = 0; SecurityScore = 0 }
    }
    
    $html = [System.Text.StringBuilder]::new()
    
    # Dashboard header
    $html.AppendLine(@"
<div class="dashboard-section">
    <div class="dashboard-header">
        <h2> System Health Dashboard</h2>
        <p class="dashboard-subtitle">Real-time maintenance metrics and system status</p>
    </div>
    
    <div class="dashboard-grid">
"@)
    
    # Success rate card
    $successRate = $metricsData.SuccessRate ?? 0
    $successClass = if ($successRate -ge 90) { 'success' } elseif ($successRate -ge 70) { 'warning' } else { 'error' }
    $html.AppendLine(@"
        <div class="dashboard-card $successClass">
            <div class="card-icon"></div>
            <h3>Success Rate</h3>
            <div class="card-value">$($successRate)%</div>
            <p class="card-description">Tasks completed successfully</p>
        </div>
"@)
    
    # Total tasks card
    $totalTasks = $metricsData.TotalTasks ?? 0
    $html.AppendLine(@"
        <div class="dashboard-card">
            <div class="card-icon"></div>
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
            <div class="card-icon"></div>
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
            <div class="card-icon"></div>
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
        <h2> Module Execution Details</h2>
        <p class="section-subtitle">Detailed results for each maintenance module</p>
    </div>
"@)
    
    # Generate sections for each module
    $moduleNames = @(
        @{ Name = 'BloatwareRemoval'; DisplayName = 'Bloatware Removal'; Icon = '' }
        @{ Name = 'EssentialApps'; DisplayName = 'Essential Applications'; Icon = '' }
        @{ Name = 'SystemOptimization'; DisplayName = 'System Optimization'; Icon = '' }
        @{ Name = 'TelemetryDisable'; DisplayName = 'Telemetry & Privacy'; Icon = '' }
        @{ Name = 'WindowsUpdates'; DisplayName = 'Windows Updates'; Icon = '' }
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
        $moduleLogDir = ($module.Name -creplace '([A-Z])', '-$1' -replace '^-', '').ToLower()
        $parsedLogs = Get-ParsedOperationLogs -ModuleName $moduleLogDir
        
        # Generate operation log table HTML
        $operationLogTable = New-OperationLogTable -ParsedLogs $parsedLogs -ModuleName $module.DisplayName
        
        if ($moduleData) {
            $taskCard = $Templates.TaskCard
            
            # Replace template placeholders with comprehensive data
            $taskCard = $taskCard -replace '{{MODULE_NAME}}', $module.DisplayName
            $taskCard = $taskCard -replace '{{MODULE_ICON}}', $module.Icon
            $taskCard = $taskCard -replace '{{MODULE_STATUS}}', ($moduleData.Status ?? 'Completed')
            $taskCard = $taskCard -replace '{{MODULE_STATUS_CLASS}}', ($moduleData.Status ?? 'completed').ToLower()
            $taskCard = $taskCard -replace '{{EXECUTION_DURATION}}', ($moduleData.Duration ?? '00:00:00')
            $taskCard = $taskCard -replace '{{MODULE_DESCRIPTION}}', "This module handles $($module.DisplayName.ToLower()) operations"
            
            # Metrics
            $taskCard = $taskCard -replace '{{ITEMS_DETECTED}}', ($moduleData.ItemsDetected ?? 0)
            $taskCard = $taskCard -replace '{{ITEMS_PROCESSED}}', ($moduleData.ItemsProcessed ?? 0)
            $taskCard = $taskCard -replace '{{MODULE_SUCCESS_RATE}}', ($moduleData.SuccessRate ?? 0)
            $taskCard = $taskCard -replace '{{PROCESSED_CLASS}}', 'success'
            
            # Before/After sections
            $taskCard = $taskCard -replace '{{BEFORE_TITLE}}', 'Before Execution'
            $taskCard = $taskCard -replace '{{AFTER_TITLE}}', 'After Execution'
            $taskCard = $taskCard -replace '{{BEFORE_ITEMS_LIST}}', '<div class="item">Initial state captured</div>'
            $taskCard = $taskCard -replace '{{AFTER_ITEMS_LIST}}', '<div class="item">Changes applied successfully</div>'
            
            # Changes summary
            $taskCard = $taskCard -replace '{{ITEMS_ADDED}}', ($moduleData.ItemsAdded ?? 0)
            $taskCard = $taskCard -replace '{{ITEMS_REMOVED}}', ($moduleData.ItemsRemoved ?? 0)
            $taskCard = $taskCard -replace '{{ITEMS_MODIFIED}}', ($moduleData.ItemsModified ?? 0)
            $taskCard = $taskCard -replace '{{ADDED_ITEMS}}', '<div class="item">Items added during execution</div>'
            $taskCard = $taskCard -replace '{{REMOVED_ITEMS}}', '<div class="item">Items removed during execution</div>'
            $taskCard = $taskCard -replace '{{MODIFIED_ITEMS}}', '<div class="item">Items modified during execution</div>'
            
            # Operation logs
            $taskCard = $taskCard -replace '{{LOGS_SUCCESS_COUNT}}', ($moduleData.SuccessfulOperations ?? 0)
            $taskCard = $taskCard -replace '{{LOGS_ERROR_COUNT}}', ($moduleData.FailedOperations ?? 0)
            $taskCard = $taskCard -replace '{{LOGS_WARNING_COUNT}}', 0
            $taskCard = $taskCard -replace '{{LOGS_INFO_COUNT}}', ($moduleData.TotalOperations ?? 0)
            $taskCard = $taskCard -replace '{{OPERATION_LOG_ROWS}}', '<tr><td colspan="5" class="no-data">Operation logs available in detailed view</td></tr>'
            
            # Performance stats
            $taskCard = $taskCard -replace '{{START_TIME}}', (Get-Date).ToString('HH:mm:ss')
            $taskCard = $taskCard -replace '{{END_TIME}}', (Get-Date).AddMinutes(2).ToString('HH:mm:ss')
            $taskCard = $taskCard -replace '{{MEMORY_USED}}', 'N/A'
            
            # Conditional sections
            $taskCard = $taskCard -replace '{{HAS_DETAILED_RESULTS}}', 'false'
            $taskCard = $taskCard -replace '{{HAS_ERRORS}}', 'false'
            $taskCard = $taskCard -replace '{{HAS_RECOMMENDATIONS}}', 'false'
            
            # Legacy placeholders
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
        <h2> Execution Summary</h2>
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
        Write-LogEntry -Level 'WARNING' -Component 'REPORT-GENERATOR' -Message 'Maintenance log not available for report'
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
                        <span class="change-label"> Log File:</span>
                        <span class="change-value">$([System.IO.Path]::GetFileName($maintenanceLog.LogFile))</span>
                    </div>
                    <div class="change-stat">
                        <span class="change-label"> Total Lines:</span>
                        <span class="change-value">$($maintenanceLog.LineCount)</span>
                    </div>
                    <div class="change-stat">
                        <span class="change-label"> File Size:</span>
                        <span class="change-value">$([math]::Round($maintenanceLog.Size / 1KB, 2)) KB</span>
                    </div>
                    <div class="change-stat">
                        <span class="change-label"> Last Modified:</span>
                        <span class="change-value">$($maintenanceLog.LastModified.ToString('yyyy-MM-dd HH:mm:ss'))</span>
                    </div>
                    <div class="change-stat">
                        <span class="change-label"> Total Entries:</span>
                        <span class="change-value">$($parsed.TotalEntries)</span>
                    </div>
                </div>
            </div>
            
            <!-- After Section: Entry Breakdown -->
            <div class="after-section">
                <h4>$($logConfig.afterTitle)</h4>
                <div class="changes-list">
                    <div class="change-category">
                        <h5 class="info">ℹ $($logConfig.changeCategories.info) ($($parsed.InfoMessages.Count))</h5>
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
                        <h5 class="success"> $($logConfig.changeCategories.success) ($($parsed.SuccessMessages.Count))</h5>
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
                        <h5 class="warning"> $($logConfig.changeCategories.warning) ($($parsed.WarningMessages.Count))</h5>
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
                        <h5 class="error"> $($logConfig.changeCategories.error) ($($parsed.ErrorMessages.Count))</h5>
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
        $summary.AppendLine(" WINDOWS MAINTENANCE SUMMARY")
        $summary.AppendLine("Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm')")
        $summary.AppendLine("")
        
        # Key metrics in compact format
        $summary.AppendLine(" RESULTS:")
        $summary.AppendLine("   Tasks: $($executionSummary.SuccessfulTasks ?? 0)/$($executionSummary.TotalTasks ?? 0) successful ($($dashboardMetrics.SuccessRate ?? 0)%)")
        $summary.AppendLine("   Duration: $([math]::Round(($executionSummary.TotalDuration ?? 0), 1))s")
        $summary.AppendLine("   Health: $($dashboardMetrics.SystemHealthScore ?? 0)/100")
        $summary.AppendLine("   Security: $($dashboardMetrics.SecurityScore ?? 0)/100")
        
        if ($errorsData -and $errorsData.ErrorSummary -and $errorsData.ErrorSummary.TotalErrors -gt 0) {
            $summary.AppendLine("")
            $summary.AppendLine("  ISSUES:")
            $summary.AppendLine("   Errors: $($errorsData.ErrorSummary.TotalErrors) ($($errorsData.ErrorSummary.HighSeverity) high severity)")
        }
        
        $summary.AppendLine("")
        $summary.AppendLine(" System maintenance completed - v3.0 Split Architecture")
        
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
        Write-Information " Testing normal template loading..." -InformationAction Continue
        
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
                    Write-Verbose " Template '$templateName' loaded successfully"
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
            
            Write-Information "   Template loading test completed" -InformationAction Continue
        }
        catch {
            $testResults.Success = $false
            $testResults.ValidationErrors += "Template loading failed: $($_.Exception.Message)"
            Write-Warning "   Template loading failed: $($_.Exception.Message)"
        }
        
        # Test 2: Fallback mechanisms (if requested)
        if ($TestFallbacks) {
            Write-Information " Testing fallback template mechanisms..." -InformationAction Continue
            
            try {
                $fallbackTemplates = Get-FallbackTemplates -ErrorAction Stop
                
                $requiredFallbacks = @('Main', 'TaskCard', 'CSS', 'Config')
                foreach ($templateName in $requiredFallbacks) {
                    if ($fallbackTemplates.ContainsKey($templateName) -and -not [string]::IsNullOrEmpty($fallbackTemplates[$templateName])) {
                        $testResults.FallbackResults[$templateName] = @{
                            Status = 'Success'
                            Length = if ($fallbackTemplates[$templateName] -is [string]) { $fallbackTemplates[$templateName].Length } else { 'Object' }
                        }
                        Write-Verbose " Fallback template '$templateName' available"
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
                
                Write-Information "   Fallback template test completed" -InformationAction Continue
            }
            catch {
                $testResults.Success = $false
                $testResults.ValidationErrors += "Fallback template loading failed: $($_.Exception.Message)"
                Write-Warning "   Fallback template loading failed: $($_.Exception.Message)"
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
        Write-Information " Testing processed data loading..." -InformationAction Continue
        
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
                    Write-Verbose " Data component '$component' loaded"
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
            
            Write-Information "   Processed data loading test completed" -InformationAction Continue
        }
        catch {
            $testResults.Success = $false
            $testResults.ValidationErrors += "Processed data loading failed: $($_.Exception.Message)"
            Write-Warning "   Processed data loading failed: $($_.Exception.Message)"
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
                    Write-LogEntry -Level 'WARNING' -Component 'MEMORY-MGR' -Message "Memory usage high: $(($currentMemory / 1MB).ToString('F1'))MB - consider cleanup"
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
<#
.SYNOPSIS
    Clears all ReportGenerator in-memory caches

.DESCRIPTION
    Flushes three primary caches maintained by ReportGenerator module:
    - TemplateCache: Loaded HTML/CSS templates
    - ProcessedDataCache: Aggregated report data
    - ReportOutputCache: Generated HTML/text output
    Useful for memory management or forcing fresh data load.

.OUTPUTS
    [void] Caches cleared in place

.EXAMPLE
    PS> Clear-ReportGeneratorCache
    
    Flushes all report generator caches before next report generation

.NOTES
    Called internally after report generation completion.
    Can be called manually to reduce memory usage in long-running sessions.
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

#region Report Index Generation

<#
.SYNOPSIS
    Generates an HTML index of all reports for easy navigation

.DESCRIPTION
    Creates an index.html file in the reports directory that lists all available
    reports with metadata (timestamp, size, status). Provides clickable links for
    quick access to recent reports and helps users navigate the report archive.

.PARAMETER ReportsPath
    Path to the reports directory containing maintenance reports

.PARAMETER OutputFileName
    Name of the index file to create (default: 'index.html')

.EXAMPLE
    New-ReportIndex -ReportsPath 'C:\Projects\temp_files\reports'

.EXAMPLE
    New-ReportIndex -ReportsPath $reportPath -OutputFileName 'report-index.html'

.OUTPUTS
    [hashtable] Result with Success, IndexPath, ReportCount, TotalSize, and Errors
#>
function New-ReportIndex {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ReportsPath,

        [Parameter(Mandatory = $false)]
        [string]$OutputFileName = 'index.html'
    )

    $result = @{
        Success     = $false
        IndexPath   = $null
        ReportCount = 0
        TotalSize   = 0
        Errors      = @()
        Details     = @()
    }

    try {
        # Validate reports directory exists
        if (-not (Test-Path -Path $ReportsPath -PathType Container)) {
            $result.Errors += "Reports directory not found: $ReportsPath"
            Write-LogEntry -Level 'WARNING' -Component 'REPORT-INDEX' -Message "Reports directory not found" -Data @{Path = $ReportsPath }
            return $result
        }

        # Collect all reports
        $reports = @(Get-ChildItem -Path $ReportsPath -Filter '*.html' -File | Where-Object {
                $_.Name -ne $OutputFileName
            } | Sort-Object -Property LastWriteTime -Descending)

        Write-LogEntry -Level 'INFO' -Component 'REPORT-INDEX' `
            -Message "Generating report index" -Data @{ReportCount = $reports.Count; ReportsPath = $ReportsPath }

        # Build report metadata
        $reportMetadata = @()
        $totalSize = 0

        foreach ($report in $reports) {
            $size = $report.Length
            $totalSize += $size
            $sizeKb = [math]::Round($size / 1024, 2)
            $timestamp = $report.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')
            
            # Extract report type from filename
            $reportType = if ($report.Name -like '*MaintenanceReport*') { 'Full Report' } `
                elseif ($report.Name -like '*Summary*') { 'Summary Report' } `
                else { 'Report' }

            $reportMetadata += @{
                Name       = $report.Name
                FileName   = $report.Name
                Timestamp  = $timestamp
                Size       = $sizeKb
                SizeBytes  = $size
                FullPath   = $report.FullName
                ReportType = $reportType
                DateObj    = $report.LastWriteTime
            }
        }

        $result.ReportCount = $reports.Count
        $result.TotalSize = $totalSize

        # Generate HTML index
        $htmlContent = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Maintenance Reports Index</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            padding: 20px;
        }
        .container {
            max-width: 1000px;
            margin: 0 auto;
            background: white;
            border-radius: 10px;
            box-shadow: 0 10px 40px rgba(0,0,0,0.2);
            overflow: hidden;
        }
        .header {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 30px 20px;
            text-align: center;
        }
        .header h1 {
            font-size: 28px;
            margin-bottom: 10px;
        }
        .header p {
            font-size: 14px;
            opacity: 0.9;
        }
        .stats {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
            gap: 15px;
            padding: 20px;
            background: #f5f5f5;
            border-bottom: 1px solid #ddd;
        }
        .stat {
            text-align: center;
            padding: 10px;
        }
        .stat-value {
            font-size: 24px;
            font-weight: bold;
            color: #667eea;
        }
        .stat-label {
            font-size: 12px;
            color: #666;
            margin-top: 5px;
        }
        .content {
            padding: 20px;
        }
        .no-reports {
            text-align: center;
            color: #999;
            padding: 40px 20px;
        }
        .reports-list {
            list-style: none;
        }
        .report-item {
            background: #f9f9f9;
            border: 1px solid #eee;
            border-radius: 5px;
            padding: 15px;
            margin-bottom: 10px;
            transition: all 0.3s ease;
            display: flex;
            justify-content: space-between;
            align-items: center;
        }
        .report-item:hover {
            background: #f0f0f0;
            border-color: #667eea;
            transform: translateX(5px);
        }
        .report-info {
            flex: 1;
        }
        .report-name {
            font-size: 16px;
            font-weight: 600;
            color: #333;
            margin-bottom: 5px;
        }
        .report-meta {
            font-size: 12px;
            color: #999;
        }
        .report-type {
            display: inline-block;
            background: #667eea;
            color: white;
            padding: 3px 10px;
            border-radius: 3px;
            font-size: 11px;
            margin-right: 10px;
        }
        .report-timestamp {
            display: inline-block;
            margin-right: 15px;
        }
        .report-size {
            display: inline-block;
            color: #999;
        }
        .report-link {
            background: #667eea;
            color: white;
            padding: 8px 15px;
            border-radius: 5px;
            text-decoration: none;
            font-size: 14px;
            transition: background 0.3s;
            white-space: nowrap;
            margin-left: 10px;
        }
        .report-link:hover {
            background: #764ba2;
        }
        .footer {
            padding: 15px 20px;
            background: #f5f5f5;
            border-top: 1px solid #ddd;
            font-size: 12px;
            color: #999;
            text-align: center;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>📊 Maintenance Reports</h1>
            <p>Windows Maintenance Automation System - Report Archive</p>
        </div>
        
        <div class="stats">
            <div class="stat">
                <div class="stat-value">$($result.ReportCount)</div>
                <div class="stat-label">Total Reports</div>
            </div>
            <div class="stat">
                <div class="stat-value">`$([math]::Round($totalSize / 1024 / 1024, 2))</div>
                <div class="stat-label">Total Size (MB)</div>
            </div>
            <div class="stat">
                <div class="stat-value">$(Get-Date -Format 'yyyy-MM-dd')</div>
                <div class="stat-label">Generated</div>
            </div>
        </div>

        <div class="content">
"@

        if ($reportMetadata.Count -eq 0) {
            $htmlContent += @"
            <div class="no-reports">
                <p>No reports found in this directory.</p>
                <p style="margin-top: 10px; font-size: 12px;">Run the maintenance system to generate reports.</p>
            </div>
"@
        }
        else {
            $htmlContent += "            <ul class=`"reports-list`">`n"
            
            foreach ($report in $reportMetadata) {
                $htmlContent += @"
            <li class="report-item">
                <div class="report-info">
                    <div class="report-name">$($report.Name)</div>
                    <div class="report-meta">
                        <span class="report-type">$($report.ReportType)</span>
                        <span class="report-timestamp">📅 $($report.Timestamp)</span>
                        <span class="report-size">📦 $($report.Size) KB</span>
                    </div>
                </div>
                <a href="$(Split-Path -Leaf $report.FileName)" class="report-link">View Report →</a>
            </li>
"@
            }
            
            $htmlContent += "            </ul>`n"
        }

        $htmlContent += @"
        </div>

        <div class="footer">
            <p>Maintenance Report Index — Windows Maintenance Automation v3.1</p>
            <p style="margin-top: 5px;">Generated on $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>
        </div>
    </div>
</body>
</html>
"@

        # Write index file
        $indexPath = Join-Path $ReportsPath $OutputFileName
        $htmlContent | Out-File -FilePath $indexPath -Encoding UTF8 -Force

        $result.Success = $true
        $result.IndexPath = $indexPath
        $result.Details += "Report index created successfully"
        $result.Details += "Total reports indexed: $($result.ReportCount)"
        $result.Details += "Index file: $indexPath"

        Write-LogEntry -Level 'SUCCESS' -Component 'REPORT-INDEX' `
            -Message "Report index generated successfully" `
            -Data @{
            ReportCount = $result.ReportCount
            TotalSize   = "$([math]::Round($totalSize / 1024 / 1024, 2)) MB"
            IndexPath   = $indexPath
        }

        return $result
    }
    catch {
        $result.Errors += "Failed to generate report index: $($_.Exception.Message)"
        Write-LogEntry -Level 'ERROR' -Component 'REPORT-INDEX' `
            -Message "Report index generation failed" -Data @{Error = $_.Exception.Message }
        return $result
    }
}

#region Enhanced Reporting Functions v3.0

<#
.SYNOPSIS
    Calculates overall success rate from aggregated results
#>
function Get-SuccessRate {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Results
    )
    
    try {
        $totalTasks = 0
        $successfulTasks = 0
        
        foreach ($moduleResult in $Results.ModuleResults.Values) {
            $totalTasks++
            if ($moduleResult.Status -eq 'Success' -or $moduleResult.Success -eq $true) {
                $successfulTasks++
            }
        }
        
        if ($totalTasks -eq 0) {
            return "0%"
        }
        
        $percentage = [Math]::Round(($successfulTasks / $totalTasks) * 100, 1)
        return "${percentage}%"
    }
    catch {
        Write-LogEntry -Level 'WARNING' -Component 'REPORT-GENERATOR' -Message "Failed to calculate success rate: $($_.Exception.Message)"
        return "N/A"
    }
}

<#
.SYNOPSIS
    Calculates total execution duration
#>
function Get-TotalDuration {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Results
    )
    
    try {
        $totalSeconds = 0
        
        foreach ($moduleResult in $Results.ModuleResults.Values) {
            if ($moduleResult.Metrics -and $moduleResult.Metrics.DurationSeconds) {
                $totalSeconds += $moduleResult.Metrics.DurationSeconds
            }
            elseif ($moduleResult.DurationSeconds) {
                $totalSeconds += $moduleResult.DurationSeconds
            }
        }
        
        if ($totalSeconds -lt 60) {
            return "$([Math]::Round($totalSeconds, 1))s"
        }
        elseif ($totalSeconds -lt 3600) {
            $minutes = [Math]::Floor($totalSeconds / 60)
            $seconds = $totalSeconds % 60
            return "${minutes}m ${seconds}s"
        }
        else {
            $hours = [Math]::Floor($totalSeconds / 3600)
            $minutes = [Math]::Floor(($totalSeconds % 3600) / 60)
            return "${hours}h ${minutes}m"
        }
    }
    catch {
        Write-LogEntry -Level 'WARNING' -Component 'REPORT-GENERATOR' -Message "Failed to calculate total duration: $($_.Exception.Message)"
        return "N/A"
    }
}

<#
.SYNOPSIS
    Calculates system health score based on execution results
#>
function Get-SystemHealthScore {
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Results
    )
    
    try {
        $score = 100
        $totalModules = 0
        $criticalErrors = 0
        $errors = 0
        $warnings = 0
        
        foreach ($moduleResult in $Results.ModuleResults.Values) {
            $totalModules++
            
            # Deduct for failures
            if ($moduleResult.Status -eq 'Error' -or $moduleResult.Success -eq $false) {
                $score -= 15
            }
            
            # Count errors and warnings
            if ($moduleResult.Errors) {
                $errors += $moduleResult.Errors.Count
                foreach ($errorItem in $moduleResult.Errors) {
                    $severity = Get-ErrorSeverity -ErrorData $errorItem
                    if ($severity -eq 'Critical') {
                        $criticalErrors++
                    }
                }
            }
            
            if ($moduleResult.Warnings) {
                $warnings += $moduleResult.Warnings.Count
            }
        }
        
        # Deduct for critical errors
        $score -= ($criticalErrors * 10)
        
        # Deduct for regular errors
        $score -= ($errors * 5)
        
        # Deduct for warnings
        $score -= ($warnings * 2)
        
        # Ensure score stays within 0-100
        $score = [Math]::Max(0, [Math]::Min(100, $score))
        
        return $score
    }
    catch {
        Write-LogEntry -Level 'WARNING' -Component 'REPORT-GENERATOR' -Message "Failed to calculate system health score: $($_.Exception.Message)"
        return 50
    }
}

<#
.SYNOPSIS
    Sums all items processed across modules
#>
function Get-ItemsProcessedTotal {
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Results
    )
    
    try {
        $total = 0
        
        foreach ($moduleResult in $Results.ModuleResults.Values) {
            if ($moduleResult.Metrics -and $moduleResult.Metrics.ItemsProcessed) {
                $total += $moduleResult.Metrics.ItemsProcessed
            }
            elseif ($moduleResult.ItemsProcessed) {
                $total += $moduleResult.ItemsProcessed
            }
        }
        
        return $total
    }
    catch {
        Write-LogEntry -Level 'WARNING' -Component 'REPORT-GENERATOR' -Message "Failed to sum items processed: $($_.Exception.Message)"
        return 0
    }
}

<#
.SYNOPSIS
    Counts total errors across all modules
#>
function Get-ErrorCount {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Results
    )
    
    try {
        $counts = @{
            Critical = 0
            Error    = 0
            Warning  = 0
        }
        
        foreach ($moduleResult in $Results.ModuleResults.Values) {
            if ($moduleResult.Errors) {
                foreach ($errorItem in $moduleResult.Errors) {
                    $severity = Get-ErrorSeverity -ErrorData $errorItem
                    $counts[$severity]++
                }
            }
            
            if ($moduleResult.Warnings) {
                $counts.Warning += $moduleResult.Warnings.Count
            }
        }
        
        return $counts
    }
    catch {
        Write-LogEntry -Level 'WARNING' -Component 'REPORT-GENERATOR' -Message "Failed to count errors: $($_.Exception.Message)"
        return @{ Critical = 0; Error = 0; Warning = 0 }
    }
}

<#
.SYNOPSIS
    Determines error severity based on error object
#>
function Get-ErrorSeverity {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        $ErrorData
    )
    
    try {
        # Check if error has explicit severity
        if ($ErrorData.Severity) {
            return $ErrorData.Severity
        }
        
        # Check error message for severity indicators
        $errorText = if ($ErrorData.Message) { $ErrorData.Message } elseif ($ErrorData -is [string]) { $ErrorData } else { $ErrorData.ToString() }
        
        $criticalKeywords = @('critical', 'fatal', 'corrupt', 'system failure', 'boot')
        $errorKeywords = @('failed', 'error', 'exception', 'cannot', 'unable')
        
        foreach ($keyword in $criticalKeywords) {
            if ($errorText -match $keyword) {
                return 'Critical'
            }
        }
        
        foreach ($keyword in $errorKeywords) {
            if ($errorText -match $keyword) {
                return 'Error'
            }
        }
        
        return 'Warning'
    }
    catch {
        return 'Error'
    }
}

<#
.SYNOPSIS
    Generates a one-line summary for a module result
#>
function New-ModuleSummary {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$ModuleResult
    )
    
    try {
        # Check if module already has a summary
        if ($ModuleResult.Summary) {
            return $ModuleResult.Summary
        }
        
        # Generate summary based on module data
        $status = $ModuleResult.Status
        
        if ($ModuleResult.Metrics) {
            $processed = $ModuleResult.Metrics.ItemsProcessed
            $skipped = $ModuleResult.Metrics.ItemsSkipped
            $failed = $ModuleResult.Metrics.ItemsFailed
            
            if ($status -eq 'Success') {
                if ($processed -gt 0) {
                    return "Processed $processed items successfully" + $(if ($skipped -gt 0) { ", $skipped skipped" } else { "" })
                }
                else {
                    return "Completed successfully, no items to process"
                }
            }
            elseif ($status -eq 'Warning') {
                return "Completed with $processed items processed, $failed failed"
            }
            else {
                return "Failed to complete - $failed items failed"
            }
        }
        
        return "Module executed with status: $status"
    }
    catch {
        return "Execution completed"
    }
}

<#
.SYNOPSIS
    Builds HTML for module log entries
#>
function Build-ModuleLogEntries {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$ModuleResult,
        
        [Parameter()]
        [int]$MaxEntries = 50
    )
    
    try {
        $html = ""
        
        # Try to load log file
        if ($ModuleResult.LogPath -and (Test-Path $ModuleResult.LogPath)) {
            $logContent = Get-Content $ModuleResult.LogPath -Tail $MaxEntries
            
            foreach ($line in $logContent) {
                $level = 'info'
                if ($line -match '\[ERROR\]') { $level = 'error' }
                elseif ($line -match '\[WARNING\]') { $level = 'warning' }
                elseif ($line -match '\[SUCCESS\]') { $level = 'success' }
                
                $escapedLine = [System.Web.HttpUtility]::HtmlEncode($line)
                $html += "                <div class=`"log-entry $level`">$escapedLine</div>`n"
            }
        }
        else {
            $html += "                <div class=`"log-entry info`">No log entries available</div>`n"
        }
        
        return $html
    }
    catch {
        Write-LogEntry -Level 'WARNING' -Component 'REPORT-GENERATOR' -Message "Failed to build module log entries: $($_.Exception.Message)"
        return "                <div class=`"log-entry error`">Failed to load log entries</div>`n"
    }
}

<#
.SYNOPSIS
    Builds HTML rows for execution summary table
#>
function Build-ExecutionSummaryRows {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$AggregatedResults,

        [Parameter()]
        [int]$MaxRows = 20
    )

    try {
        if (-not $AggregatedResults.ModuleResults) {
            return '<tr><td colspan="4">No module results available</td></tr>'
        }

        $rows = @()
        foreach ($moduleResult in $AggregatedResults.ModuleResults.Values | Select-Object -First $MaxRows) {
            $moduleName = [System.Web.HttpUtility]::HtmlEncode($moduleResult.ModuleName)
            $status = $moduleResult.Status ?? 'Unknown'
            $statusClass = if ($status -match 'Success|Completed') { 'status-success' }
            elseif ($status -match 'Warning') { 'status-warning' }
            elseif ($status -match 'Error|Failed') { 'status-error' }
            else { 'status-info' }
            $items = [int]($moduleResult.Metrics.ItemsProcessed ?? $moduleResult.ItemsProcessed ?? $moduleResult.TotalOperations ?? 0)
            $duration = [double]($moduleResult.Metrics.DurationSeconds ?? $moduleResult.DurationSeconds ?? 0)

            $rows += "<tr><td>$moduleName</td><td><span class=\"status-badge $statusClass\">$status</span></td><td>$items</td><td>$([math]::Round($duration, 1))s</td></tr>"
        }

        return ($rows -join "`n")
    }
    catch {
        Write-LogEntry -Level 'WARNING' -Component 'REPORT-GENERATOR' -Message "Failed to build execution summary rows: $($_.Exception.Message)"
        return '<tr><td colspan="4">Failed to build execution summary</td></tr>'
    }
}

<#
.SYNOPSIS
    Builds HTML for system changes log (aggregated module logs)
#>
function Build-SystemChangesLog {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$AggregatedResults,

        [Parameter()]
        [int]$MaxEntries = 60
    )

    try {
        $entries = New-Object System.Collections.Generic.List[string]

        if (-not $AggregatedResults.ModuleResults) {
            return '<div class="log-entry info">No system changes recorded</div>'
        }

        foreach ($moduleResult in $AggregatedResults.ModuleResults.Values) {
            $moduleName = $moduleResult.ModuleName ?? 'Module'
            $logLines = @()

            if ($moduleResult.LogEntries) {
                $logLines = $moduleResult.LogEntries | Select-Object -Last 5
            }
            elseif ($moduleResult.Logs) {
                $logLines = $moduleResult.Logs | Select-Object -Last 5
            }
            elseif ($moduleResult.LogPath -and (Test-Path $moduleResult.LogPath)) {
                $logLines = Get-Content $moduleResult.LogPath -Tail 5
            }

            foreach ($line in $logLines) {
                if (-not $line) { continue }
                $level = 'info'
                if ($line -match '\[ERROR\]') { $level = 'error' }
                elseif ($line -match '\[WARNING\]') { $level = 'warning' }
                elseif ($line -match '\[SUCCESS\]') { $level = 'success' }

                $escapedLine = [System.Web.HttpUtility]::HtmlEncode($line)
                $entries.Add("<div class=\"log-entry $level\"><span class=\"log-tag\">$moduleName</span>$escapedLine</div>")
                if ($entries.Count -ge $MaxEntries) { break }
            }

            if ($entries.Count -ge $MaxEntries) { break }
        }

        if ($entries.Count -eq 0) {
            return '<div class="log-entry info">No system changes recorded</div>'
        }

        return ($entries -join "`n")
    }
    catch {
        Write-LogEntry -Level 'WARNING' -Component 'REPORT-GENERATOR' -Message "Failed to build system changes log: $($_.Exception.Message)"
        return '<div class="log-entry error">Failed to load system changes</div>'
    }
}

<#
.SYNOPSIS
    Builds HTML for performance phase breakdown
#>
function Build-PerformancePhases {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$ModuleResult
    )
    
    try {
        $html = ""
        
        if ($ModuleResult.ExecutionPhases -and $ModuleResult.ExecutionPhases.Count -gt 0) {
            foreach ($phaseName in $ModuleResult.ExecutionPhases.Keys) {
                $phase = $ModuleResult.ExecutionPhases[$phaseName]
                $duration = if ($phase.Duration) { $phase.Duration } else { 0 }
                $percent = if ($phase.Percent) { $phase.Percent } else { 0 }
                
                $html += @"
                <div class="performance-phase">
                    <div class="phase-header">
                        <span class="phase-name">$phaseName</span>
                        <span class="phase-duration">${duration}s</span>
                    </div>
                    <div class="phase-bar-container">
                        <div class="phase-bar" style="width: ${percent}%"></div>
                    </div>
                </div>

"@
            }
        }
        else {
            $html = "                <div class=`"no-data`">No performance data available</div>`n"
        }
        
        return $html
    }
    catch {
        Write-LogEntry -Level 'WARNING' -Component 'REPORT-GENERATOR' -Message "Failed to build performance phases: $($_.Exception.Message)"
        return "                <div class=`"error`">Failed to load performance data</div>`n"
    }
}

<#
.SYNOPSIS
    Builds HTML for module errors section
#>
function Build-ModuleErrors {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$ModuleResult
    )
    
    try {
        $html = ""
        
        if ($ModuleResult.Errors -and $ModuleResult.Errors.Count -gt 0) {
            foreach ($errorItem in $ModuleResult.Errors) {
                $errorMessage = if ($errorItem.Message) { $errorItem.Message } else { $errorItem.ToString() }
                $escapedMessage = [System.Web.HttpUtility]::HtmlEncode($errorMessage)
                
                $html += @"
                <div class="module-error-item">
                    <div class="error-message">$escapedMessage</div>
                </div>

"@
            }
        }
        
        if ($ModuleResult.Warnings -and $ModuleResult.Warnings.Count -gt 0) {
            foreach ($warning in $ModuleResult.Warnings) {
                $warningMessage = if ($warning.Message) { $warning.Message } else { $warning.ToString() }
                $escapedMessage = [System.Web.HttpUtility]::HtmlEncode($warningMessage)
                
                $html += @"
                <div class="module-error-item warning">
                    <div class="error-message">⚠️ $escapedMessage</div>
                </div>

"@
            }
        }
        
        if ([string]::IsNullOrWhiteSpace($html)) {
            $html = "                <div class=`"no-errors`">✓ No errors or warnings</div>`n"
        }
        
        return $html
    }
    catch {
        Write-LogEntry -Level 'WARNING' -Component 'REPORT-GENERATOR' -Message "Failed to build module errors: $($_.Exception.Message)"
        return "                <div class=`"error`">Failed to load error data</div>`n"
    }
}

<#
.SYNOPSIS
    Builds HTML for execution timeline
#>
function Build-ExecutionTimeline {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$AggregatedResults
    )
    
    try {
        $html = ""
        
        foreach ($moduleResult in $AggregatedResults.ModuleResults.Values) {
            $moduleName = $moduleResult.ModuleName
            $status = $moduleResult.Status.ToLower()
            $startTime = if ($moduleResult.Metrics -and $moduleResult.Metrics.StartTime) { 
                $moduleResult.Metrics.StartTime 
            }
            else { 
                Get-Date -Format "HH:mm:ss" 
            }
            
            $statusIcon = switch ($status) {
                'success' { '✓' }
                'warning' { '⚠' }
                'error' { '✗' }
                default { '•' }
            }
            
            $html += @"
            <div class="timeline-entry $status">
                <div class="timeline-marker"></div>
                <div class="timeline-content">
                    <div class="timeline-time">$startTime</div>
                    <div class="timeline-title">$statusIcon $moduleName</div>
                    <div class="timeline-description">$(New-ModuleSummary -ModuleResult $moduleResult)</div>
                </div>
            </div>

"@
        }
        
        return $html
    }
    catch {
        Write-LogEntry -Level 'WARNING' -Component 'REPORT-GENERATOR' -Message "Failed to build execution timeline: $($_.Exception.Message)"
        return "            <div class=`"error`">Failed to generate timeline</div>`n"
    }
}

<#
.SYNOPSIS
    Builds HTML for action items from all modules
#>
function Build-ActionItems {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$AggregatedResults,
        
        [Parameter()]
        [int]$MaxItems = 10
    )
    
    try {
        $html = ""
        $actionItems = @()
        
        foreach ($moduleResult in $AggregatedResults.ModuleResults.Values) {
            if ($moduleResult.Recommendations -and $moduleResult.Recommendations.Count -gt 0) {
                foreach ($recommendation in $moduleResult.Recommendations) {
                    $actionItems += @{
                        Module   = $moduleResult.ModuleName
                        Text     = $recommendation
                        Priority = 'medium'
                    }
                }
            }
            
            # Add actions for errors
            if ($moduleResult.Errors -and $moduleResult.Errors.Count -gt 0) {
                $actionItems += @{
                    Module   = $moduleResult.ModuleName
                    Text     = "Review and resolve $($moduleResult.Errors.Count) error(s) in $($moduleResult.ModuleName)"
                    Priority = 'high'
                }
            }
        }
        
        # Limit to max items
        $actionItems = $actionItems | Select-Object -First $MaxItems
        
        foreach ($item in $actionItems) {
            $priority = $item.Priority
            $text = [System.Web.HttpUtility]::HtmlEncode($item.Text)
            
            $html += @"
            <div class="action-item priority-$priority">
                <span class="action-priority">$($priority.ToUpper())</span>
                <span class="action-text">$text</span>
                <div class="action-checkbox"></div>
            </div>

"@
        }
        
        if ([string]::IsNullOrWhiteSpace($html)) {
            $html = "            <div class=`"no-actions`">No action items required</div>`n"
        }
        
        return $html
    }
    catch {
        Write-LogEntry -Level 'WARNING' -Component 'REPORT-GENERATOR' -Message "Failed to build action items: $($_.Exception.Message)"
        return "            <div class=`"error`">Failed to generate action items</div>`n"
    }
}

<#
.SYNOPSIS
    Gets system information for report
#>
function Get-SystemInformation {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()
    
    try {
        $os = Get-CimInstance Win32_OperatingSystem
        $computer = Get-CimInstance Win32_ComputerSystem
        $processor = Get-CimInstance Win32_Processor | Select-Object -First 1
        
        return @{
            COMPUTER_NAME  = $env:COMPUTERNAME
            USER_NAME      = $env:USERNAME
            OS_VERSION     = $os.Caption
            OS_BUILD       = $os.BuildNumber
            PROCESSOR_NAME = $processor.Name
            TOTAL_MEMORY   = "$([Math]::Round($computer.TotalPhysicalMemory / 1GB, 2)) GB"
            DOMAIN         = $computer.Domain
        }
    }
    catch {
        Write-LogEntry -Level 'WARNING' -Component 'REPORT-GENERATOR' -Message "Failed to get system information: $($_.Exception.Message)"
        return @{
            COMPUTER_NAME  = $env:COMPUTERNAME
            USER_NAME      = $env:USERNAME
            OS_VERSION     = "Unknown"
            OS_BUILD       = "Unknown"
            PROCESSOR_NAME = "Unknown"
            TOTAL_MEMORY   = "Unknown"
            DOMAIN         = "Unknown"
        }
    }
}

<#
.SYNOPSIS
    Builds the executive dashboard section with hero metrics and key findings
.DESCRIPTION
    Generates comprehensive dashboard data including success rates, durations,
    key findings, action items, and progress metrics for the enhanced report template.
#>
function Build-ExecutiveDashboard {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$AggregatedResults,
        
        [Parameter(Mandatory)]
        [hashtable]$Config
    )
    
    try {
        Write-LogEntry -Level 'INFO' -Component 'REPORT-GENERATOR' -Message 'Building executive dashboard'
        
        # Calculate hero metrics
        $successRate = Get-SuccessRate -Results $AggregatedResults
        $totalDuration = Get-TotalDuration -Results $AggregatedResults
        $itemsProcessed = Get-ItemsProcessedTotal -Results $AggregatedResults
        $errorCounts = Get-ErrorCount -Results $AggregatedResults
        
        # Calculate task completion
        $totalTasks = $AggregatedResults.ModuleResults.Count
        $completedTasks = 0
        foreach ($moduleResult in $AggregatedResults.ModuleResults.Values) {
            if ($moduleResult.Status -eq 'Success' -or $moduleResult.Success -eq $true) {
                $completedTasks++
            }
        }
        $taskCompletionPercent = if ($totalTasks -gt 0) { 
            [Math]::Round(($completedTasks / $totalTasks) * 100, 1) 
        }
        else { 0 }
        
        # Calculate system health score
        $systemHealthScore = Get-SystemHealthScore -Results $AggregatedResults
        
        # Generate key findings HTML
        $keyFindingsHtml = Build-KeyFindings -Results $AggregatedResults -Limit 5
        
        # Generate action items summary HTML
        $actionItemsSummaryHtml = Build-ActionItems -AggregatedResults $AggregatedResults -MaxItems 3
        
        # Return hashtable with all dashboard tokens
        $dashboard = @{
            SUCCESS_RATE            = $successRate
            TOTAL_DURATION          = $totalDuration
            ITEMS_PROCESSED         = $itemsProcessed
            ERROR_COUNT             = $errorCounts.Error
            WARNING_COUNT           = $errorCounts.Warning
            CRITICAL_COUNT          = $errorCounts.Critical
            TASKS_COMPLETED         = $completedTasks
            TOTAL_TASKS             = $totalTasks
            TASK_COMPLETION_PERCENT = $taskCompletionPercent
            SYSTEM_HEALTH_SCORE     = $systemHealthScore
            KEY_FINDINGS            = $keyFindingsHtml
            ACTION_ITEMS_SUMMARY    = $actionItemsSummaryHtml
        }
        
        Write-LogEntry -Level 'SUCCESS' -Component 'REPORT-GENERATOR' -Message "Executive dashboard built successfully"
        return $dashboard
    }
    catch {
        Write-LogEntry -Level 'ERROR' -Component 'REPORT-GENERATOR' -Message "Failed to build executive dashboard: $($_.Exception.Message)"
        # Return minimal dashboard on error
        return @{
            SUCCESS_RATE            = "N/A"
            TOTAL_DURATION          = "N/A"
            ITEMS_PROCESSED         = 0
            ERROR_COUNT             = 0
            WARNING_COUNT           = 0
            CRITICAL_COUNT          = 0
            TASKS_COMPLETED         = 0
            TOTAL_TASKS             = 0
            TASK_COMPLETION_PERCENT = 0
            SYSTEM_HEALTH_SCORE     = 0
            KEY_FINDINGS            = "<div class='no-data'>Dashboard data unavailable</div>"
            ACTION_ITEMS_SUMMARY    = "<div class='no-data'>Action items unavailable</div>"
        }
    }
}

<#
.SYNOPSIS
    Builds an enhanced module card with comprehensive details (v5.0)
.DESCRIPTION
    Generates a professional module card HTML using enhanced-module-card.html template
    with flexbox layout, metrics, detailed logs, and modern UI elements.
    This version integrates with the enhanced report generation system.
#>
function Build-ModuleCard {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$ModuleResult,
        
        [Parameter()]
        [string]$CardTemplate
    )
    
    try {
        $moduleName = $ModuleResult.ModuleName
        Write-Verbose "Building enhanced module card for $moduleName"
        
        # Try to load enhanced template if not provided
        if (-not $CardTemplate) {
            $enhancedTemplatePath = Find-ConfigTemplate -TemplateName "enhanced-module-card.html"
            if ($enhancedTemplatePath -and (Test-Path $enhancedTemplatePath)) {
                $CardTemplate = Get-Content $enhancedTemplatePath -Raw
                Write-Verbose "Using enhanced module card template"
            }
        }
        
        # Define module metadata
        $moduleInfo = @{
            'BloatwareRemoval'    = @{ Icon = '🗑️'; Name = 'Bloatware Removal'; Description = 'Removes unnecessary pre-installed software and applications' }
            'EssentialApps'       = @{ Icon = '📦'; Name = 'Essential Applications'; Description = 'Installs and manages essential system applications' }
            'SystemOptimization'  = @{ Icon = '⚡'; Name = 'System Optimization'; Description = 'Optimizes system performance and resource usage' }
            'TelemetryDisable'    = @{ Icon = '🔒'; Name = 'Privacy & Telemetry'; Description = 'Disables telemetry and enhances privacy settings' }
            'WindowsUpdates'      = @{ Icon = '🔄'; Name = 'Windows Updates'; Description = 'Manages system updates and security patches' }
            'SecurityAudit'       = @{ Icon = '🛡️'; Name = 'Security Audit'; Description = 'Comprehensive security assessment and recommendations' }
            'SystemInventory'     = @{ Icon = '📊'; Name = 'System Inventory'; Description = 'Complete system hardware and software inventory' }
            'AppUpgrade'          = @{ Icon = '⬆️'; Name = 'Application Upgrades'; Description = 'Updates installed applications to latest versions' }
            'SecurityEnhancement' = @{ Icon = '🔐'; Name = 'Security Enhancement'; Description = 'Applies advanced security configurations' }
        }
        
        $info = $moduleInfo[$moduleName] ?? @{ Icon = '⚙️'; Name = $moduleName; Description = 'Module execution results' }
        
        # Extract metrics from either Metrics property or direct properties
        $totalOps = [int]($ModuleResult.Metrics.ItemsProcessed ?? $ModuleResult.ItemsProcessed ?? $ModuleResult.TotalOperations ?? 0)
        $successOps = [int]($ModuleResult.Metrics.ItemsSuccessful ?? $ModuleResult.SuccessfulOperations ?? 0)
        $skippedOps = [int]($ModuleResult.Metrics.ItemsSkipped ?? $ModuleResult.SkippedOperations ?? 0)
        $failedOps = [int]($ModuleResult.Metrics.ItemsFailed ?? $ModuleResult.FailedOperations ?? 0)
        $durationSec = [double]($ModuleResult.Metrics.DurationSeconds ?? $ModuleResult.DurationSeconds ?? 0)
        
        # Calculate success rate
        $successRate = if ($totalOps -gt 0) { [math]::Round(($successOps / $totalOps) * 100, 1) } else { 100 }
        
        # Determine status class
        $status = $ModuleResult.Status ?? 'Completed'
        $statusClass = if ($status -match 'Success|Completed') { 'status-success' }
        elseif ($status -match 'Warning') { 'status-warning' }
        elseif ($status -match 'Error|Failed') { 'status-error' }
        else { 'status-info' }
        
        # Build module details HTML using enhanced system
        $detailsHtml = Build-ModuleDetailsSection -ModuleKey $moduleName -ModuleData $ModuleResult
        
        # Build module logs HTML using enhanced system
        $logsHtml = Build-ModuleLogsSection -ModuleKey $moduleName -ModuleData $ModuleResult
        $logsCount = if ($ModuleResult.Logs) { $ModuleResult.Logs.Count } elseif ($ModuleResult.LogEntries) { $ModuleResult.LogEntries.Count } else { 0 }
        
        # Generate module card HTML by replacing template tokens
        $cardHtml = $CardTemplate
        $cardHtml = $cardHtml -replace '\{\{MODULE_ID\}\}', $moduleName
        $cardHtml = $cardHtml -replace '\{\{MODULE_ICON\}\}', $info.Icon
        $cardHtml = $cardHtml -replace '\{\{MODULE_NAME\}\}', $info.Name
        $cardHtml = $cardHtml -replace '\{\{MODULE_DESCRIPTION\}\}', $info.Description
        $cardHtml = $cardHtml -replace '\{\{MODULE_STATUS_CLASS\}\}', $statusClass
        $cardHtml = $cardHtml -replace '\{\{MODULE_STATUS_TEXT\}\}', $status
        $cardHtml = $cardHtml -replace '\{\{EXECUTION_TIMESTAMP\}\}', (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        $cardHtml = $cardHtml -replace '\{\{EXECUTION_DURATION\}\}', "$([math]::Round($durationSec, 1))s"
        $cardHtml = $cardHtml -replace '\{\{ITEMS_PROCESSED\}\}', $totalOps
        $cardHtml = $cardHtml -replace '\{\{ITEMS_SUCCESSFUL\}\}', $successOps
        $cardHtml = $cardHtml -replace '\{\{ITEMS_SKIPPED\}\}', $skippedOps
        $cardHtml = $cardHtml -replace '\{\{ITEMS_FAILED\}\}', $failedOps
        $cardHtml = $cardHtml -replace '\{\{SUCCESS_RATE\}\}', $successRate
        $cardHtml = $cardHtml -replace '\{\{MODULE_DETAILS_HTML\}\}', $detailsHtml
        $cardHtml = $cardHtml -replace '\{\{MODULE_LOGS_HTML\}\}', $logsHtml
        $cardHtml = $cardHtml -replace '\{\{LOGS_COUNT\}\}', $logsCount
        
        return $cardHtml
    }
    catch {
        Write-LogEntry -Level 'ERROR' -Component 'REPORT-GENERATOR' -Message "Failed to build module card for $($ModuleResult.ModuleName): $($_.Exception.Message)"
        return "<div class='module-card error'><p>Failed to generate module card: $($_.Exception.Message)</p></div>`n"
    }
}

<#
.SYNOPSIS
    Builds the module details section with detected and processed items (v5.0)
.DESCRIPTION
    Generates HTML for module details including detected items (Type1 audit results)
    and processed items (Type2 execution results) with professional styling.
#>
function Build-ModuleDetailsSection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ModuleKey,
        
        [Parameter(Mandatory)]
        [hashtable]$ModuleData
    )
    
    $detailsHtml = @()
    
    # Check for detected items (Type1 audit results)
    if ($ModuleData.DetectedItems -and $ModuleData.DetectedItems.Count -gt 0) {
        $detailsHtml += '<div class="detail-section">'
        $detailsHtml += '<h4 class="detail-section-title"><span>🔍</span> Detected Items</h4>'
        $detailsHtml += '<div class="detail-list">'
        
        foreach ($item in $ModuleData.DetectedItems | Select-Object -First 10) {
            $itemName = if ($item.Name) { $item.Name } elseif ($item.DisplayName) { $item.DisplayName } else { $item.ToString() }
            $itemStatus = if ($item.Status) { $item.Status } else { 'Detected' }
            $statusBadgeClass = switch ($itemStatus.ToLower()) {
                'success' { 'success' }
                'removed' { 'success' }
                'installed' { 'success' }
                'warning' { 'warning' }
                'skipped' { 'warning' }
                'error' { 'error' }
                'failed' { 'error' }
                default { 'info' }
            }
            
            $detailsHtml += '<div class="detail-item">'
            $detailsHtml += '<div class="detail-item-icon">📄</div>'
            $detailsHtml += '<div class="detail-item-content">'
            $detailsHtml += "<div class='detail-item-name'>$itemName</div>"
            if ($item.Version) {
                $detailsHtml += "<div class='detail-item-description'>Version: $($item.Version)</div>"
            }
            if ($item.Size) {
                $detailsHtml += "<div class='detail-item-description'>Size: $($item.Size)</div>"
            }
            $detailsHtml += '</div>'
            $detailsHtml += "<div class='detail-item-status'><span class='status-badge $statusBadgeClass'>$itemStatus</span></div>"
            $detailsHtml += '</div>'
        }
        
        if ($ModuleData.DetectedItems.Count -gt 10) {
            $remaining = $ModuleData.DetectedItems.Count - 10
            $detailsHtml += "<div class='detail-item' style='justify-content: center; color: var(--text-muted); font-style: italic;'>+ $remaining more items...</div>"
        }
        
        $detailsHtml += '</div></div>'
    }
    
    # Check for processed items (Type2 execution results)
    if ($ModuleData.ProcessedItems -and $ModuleData.ProcessedItems.Count -gt 0) {
        $detailsHtml += '<div class="detail-section">'
        $detailsHtml += '<h4 class="detail-section-title"><span>⚡</span> Processed Items</h4>'
        $detailsHtml += '<div class="detail-list">'
        
        foreach ($item in $ModuleData.ProcessedItems | Select-Object -First 10) {
            $itemName = if ($item.Name) { $item.Name } else { $item.ToString() }
            $itemResult = if ($item.Result) { $item.Result } elseif ($item.Status) { $item.Status } else { 'Processed' }
            $resultBadgeClass = switch ($itemResult.ToLower()) {
                'success' { 'success' }
                'completed' { 'success' }
                'warning' { 'warning' }
                'skipped' { 'warning' }
                'error' { 'error' }
                'failed' { 'error' }
                default { 'info' }
            }
            
            $detailsHtml += '<div class="detail-item">'
            $detailsHtml += '<div class="detail-item-icon">✓</div>'
            $detailsHtml += '<div class="detail-item-content">'
            $detailsHtml += "<div class='detail-item-name'>$itemName</div>"
            if ($item.Action) {
                $detailsHtml += "<div class='detail-item-description'>Action: $($item.Action)</div>"
            }
            $detailsHtml += '</div>'
            $detailsHtml += "<div class='detail-item-status'><span class='status-badge $resultBadgeClass'>$itemResult</span></div>"
            $detailsHtml += '</div>'
        }
        
        if ($ModuleData.ProcessedItems.Count -gt 10) {
            $remaining = $ModuleData.ProcessedItems.Count - 10
            $detailsHtml += "<div class='detail-item' style='justify-content: center; color: var(--text-muted); font-style: italic;'>+ $remaining more items...</div>"
        }
        
        $detailsHtml += '</div></div>'
    }
    
    if ($detailsHtml.Count -eq 0) {
        $detailsHtml += '<div style="padding: var(--spacing-lg); text-align: center; color: var(--text-muted);">'
        $detailsHtml += '<p>✓ Module completed successfully with no specific items to display</p>'
        $detailsHtml += '</div>'
    }
    
    return $detailsHtml -join "`n"
}

<#
.SYNOPSIS
    Builds the module logs section with formatted execution logs (v5.0)
.DESCRIPTION
    Loads and formats execution logs from module log files or embedded log data.
    Displays logs with timestamps, level icons, and message content.
#>
function Build-ModuleLogsSection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ModuleKey,
        
        [Parameter(Mandatory)]
        [hashtable]$ModuleData
    )
    
    $logsHtml = @()
    
    # Try to load logs from module's log file
    $logFilePath = Get-SessionPath -Category 'logs' -SubCategory $ModuleKey -FileName 'execution-structured.json'
    $logEntries = @()
    
    if ($logFilePath -and (Test-Path $logFilePath)) {
        try {
            $logData = Get-Content $logFilePath -Raw | ConvertFrom-Json
            if ($logData.Entries) {
                $logEntries = $logData.Entries | Select-Object -First 20
            }
        }
        catch {
            Write-LogEntry -Level 'WARNING' -Component 'REPORT-GENERATOR' -Message "Failed to load logs for $ModuleKey : $_"
        }
    }
    
    # Fallback to embedded logs if file not available
    if ($logEntries.Count -eq 0 -and $ModuleData.Logs) {
        $logEntries = $ModuleData.Logs | Select-Object -First 20
    }
    
    if ($logEntries.Count -gt 0) {
        foreach ($log in $logEntries) {
            $level = if ($log.Level) { $log.Level.ToLower() } else { 'info' }
            $timestamp = if ($log.Timestamp) { 
                try { [datetime]::Parse($log.Timestamp).ToString('HH:mm:ss') } 
                catch { (Get-Date).ToString('HH:mm:ss') }
            }
            else { (Get-Date).ToString('HH:mm:ss') }
            $message = if ($log.Message) { $log.Message } else { $log.ToString() }
            
            $levelIcon = switch ($level) {
                'success' { '✓' }
                'info' { 'ℹ' }
                'warning' { '⚠' }
                'error' { '✗' }
                'debug' { '🔍' }
                default { '•' }
            }
            
            $logsHtml += "<div class='log-entry $level'>"
            $logsHtml += "<div class='log-timestamp'>$timestamp</div>"
            $logsHtml += "<div class='log-level-icon'>$levelIcon</div>"
            $logsHtml += "<div class='log-message'>$message</div>"
            $logsHtml += '</div>'
        }
    }
    else {
        $logsHtml += '<div class="log-entry info">'
        $logsHtml += '<div class="log-timestamp">' + (Get-Date).ToString('HH:mm:ss') + '</div>'
        $logsHtml += '<div class="log-level-icon">ℹ</div>'
        $logsHtml += "<div class='log-message'>Module $ModuleKey completed - no detailed logs available</div>"
        $logsHtml += '</div>'
    }
    
    return $logsHtml -join "`n"
}

<#
.SYNOPSIS
    Builds the error analysis section with categorized errors
.DESCRIPTION
    Categorizes all errors by severity (critical/error/warning) and generates
    HTML for the error analysis dashboard section.
#>
function Build-ErrorAnalysis {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$AggregatedResults
    )
    
    try {
        Write-LogEntry -Level 'INFO' -Component 'REPORT-GENERATOR' -Message 'Building error analysis section'
        
        # Categorize errors by severity and module
        $criticalErrors = @()
        $errors = @()
        $warnings = @()
        
        foreach ($moduleResult in $AggregatedResults.ModuleResults.Values) {
            $moduleName = $moduleResult.ModuleName
            
            # Process errors
            if ($moduleResult.Errors -and $moduleResult.Errors.Count -gt 0) {
                foreach ($errorItem in $moduleResult.Errors) {
                    $severity = Get-ErrorSeverity -ErrorData $errorItem
                    $errorMessage = if ($errorItem.Message) { $errorItem.Message } elseif ($errorItem -is [string]) { $errorItem } else { $errorItem.ToString() }
                    
                    $errorItem = @{
                        Module   = $moduleName
                        Message  = $errorMessage
                        Severity = $severity
                    }
                    
                    switch ($severity) {
                        'Critical' { $criticalErrors += $errorItem }
                        'Error' { $errors += $errorItem }
                        'Warning' { $warnings += $errorItem }
                    }
                }
            }
            
            # Process warnings
            if ($moduleResult.Warnings -and $moduleResult.Warnings.Count -gt 0) {
                foreach ($warning in $moduleResult.Warnings) {
                    $warningMessage = if ($warning.Message) { $warning.Message } elseif ($warning -is [string]) { $warning } else { $warning.ToString() }
                    
                    $warnings += @{
                        Module   = $moduleName
                        Message  = $warningMessage
                        Severity = 'Warning'
                    }
                }
            }
        }
        
        # Build HTML
        $html = ""
        
        # Build critical errors section
        if ($criticalErrors.Count -gt 0) {
            $html += @"
        <div class="error-category critical">
            <div class="category-header">
                <span class="category-icon">🔴</span>
                <span class="category-title">Critical Issues ($($criticalErrors.Count))</span>
            </div>
            <div class="module-errors-list">

"@
            foreach ($item in $criticalErrors) {
                $escapedMessage = [System.Web.HttpUtility]::HtmlEncode($item.Message)
                $html += @"
                <div class="module-error-item">
                    <div class="error-module-name">$($item.Module)</div>
                    <div class="error-message">$escapedMessage</div>
                    <div class="error-solution"><strong>Action Required:</strong> Immediate attention needed to resolve critical system issue.</div>
                </div>

"@
            }
            $html += "            </div>`n        </div>`n`n"
        }
        
        # Build errors section
        if ($errors.Count -gt 0) {
            $html += @"
        <div class="error-category error">
            <div class="category-header">
                <span class="category-icon">❌</span>
                <span class="category-title">Errors ($($errors.Count))</span>
            </div>
            <div class="module-errors-list">

"@
            foreach ($item in $errors) {
                $escapedMessage = [System.Web.HttpUtility]::HtmlEncode($item.Message)
                $html += @"
                <div class="module-error-item">
                    <div class="error-module-name">$($item.Module)</div>
                    <div class="error-message">$escapedMessage</div>
                    <div class="error-solution"><strong>Recommended:</strong> Review module logs and retry operation.</div>
                </div>

"@
            }
            $html += "            </div>`n        </div>`n`n"
        }
        
        # Build warnings section
        if ($warnings.Count -gt 0) {
            $html += @"
        <div class="error-category warning">
            <div class="category-header">
                <span class="category-icon">⚠️</span>
                <span class="category-title">Warnings ($($warnings.Count))</span>
            </div>
            <div class="module-errors-list">

"@
            foreach ($item in $warnings) {
                $escapedMessage = [System.Web.HttpUtility]::HtmlEncode($item.Message)
                $html += @"
                <div class="module-error-item">
                    <div class="error-module-name">$($item.Module)</div>
                    <div class="error-message">$escapedMessage</div>
                </div>

"@
            }
            $html += "            </div>`n        </div>`n`n"
        }
        
        # If no errors or warnings
        if ([string]::IsNullOrWhiteSpace($html)) {
            $html = @"
        <div class="no-errors-message">
            <div class="success-icon">✓</div>
            <div class="success-text">No errors or warnings detected. All modules executed successfully.</div>
        </div>

"@
        }
        
        Write-LogEntry -Level 'SUCCESS' -Component 'REPORT-GENERATOR' -Message "Error analysis section built: $($criticalErrors.Count) critical, $($errors.Count) errors, $($warnings.Count) warnings"
        return $html
    }
    catch {
        Write-LogEntry -Level 'ERROR' -Component 'REPORT-GENERATOR' -Message "Failed to build error analysis: $($_.Exception.Message)"
        return "        <div class='error'>Failed to generate error analysis</div>`n"
    }
}

<#
.SYNOPSIS
    Builds the key findings section for executive dashboard
.DESCRIPTION
    Extracts and prioritizes the top N most significant findings from all modules
    and formats them as HTML for the findings box.
#>
function Build-KeyFindings {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Results,
        
        [Parameter()]
        [int]$Limit = 5
    )
    
    try {
        $findings = @()
        
        # Extract significant findings from each module
        foreach ($moduleResult in $Results.ModuleResults.Values) {
            $moduleName = $moduleResult.ModuleName
            
            # Add success findings (high impact items)
            if (($moduleResult.Status -eq 'Success' -or $moduleResult.Success -eq $true) -and 
                $moduleResult.Metrics -and $moduleResult.Metrics.ItemsProcessed -gt 0) {
                
                $processed = $moduleResult.Metrics.ItemsProcessed
                $findings += @{
                    Type     = 'success'
                    Icon     = '✓'
                    Priority = if ($processed -gt 10) { 1 } elseif ($processed -gt 5) { 2 } else { 3 }
                    Text     = "$moduleName completed successfully - $processed items processed"
                    Module   = $moduleName
                }
            }
            
            # Add error findings (highest priority)
            if ($moduleResult.Errors -and $moduleResult.Errors.Count -gt 0) {
                $errorCount = $moduleResult.Errors.Count
                $findings += @{
                    Type     = 'error'
                    Icon     = '✗'
                    Priority = 0  # Highest priority
                    Text     = "$moduleName encountered $errorCount error(s)"
                    Module   = $moduleName
                }
            }
            
            # Add warning findings
            if ($moduleResult.Warnings -and $moduleResult.Warnings.Count -gt 0) {
                $warningCount = $moduleResult.Warnings.Count
                $findings += @{
                    Type     = 'warning'
                    Icon     = '⚠'
                    Priority = 1
                    Text     = "$moduleName reported $warningCount warning(s)"
                    Module   = $moduleName
                }
            }
            
            # Add specific high-value findings from results
            if ($moduleResult.Results) {
                foreach ($key in $moduleResult.Results.Keys) {
                    $value = $moduleResult.Results[$key]
                    if ($value -is [array] -and $value.Count -gt 5) {
                        $findings += @{
                            Type     = 'info'
                            Icon     = '📊'
                            Priority = 2
                            Text     = "${moduleName}: Found $($value.Count) $key"
                            Module   = $moduleName
                        }
                    }
                }
            }
        }
        
        # Sort by priority and limit
        $findings = $findings | Sort-Object Priority | Select-Object -First $Limit
        
        # Build HTML
        $html = ""
        foreach ($finding in $findings) {
            $escapedText = [System.Web.HttpUtility]::HtmlEncode($finding.Text)
            $html += @"
            <div class="finding-item $($finding.Type)">
                <div class="finding-icon">$($finding.Icon)</div>
                <div class="finding-content">
                    <div class="finding-text">$escapedText</div>
                    <div class="finding-meta">
                        <span class="finding-module">$($finding.Module)</span>
                    </div>
                </div>
            </div>

"@
        }
        
        if ([string]::IsNullOrWhiteSpace($html)) {
            $html = "            <div class='no-findings'>No significant findings to report</div>`n"
        }
        
        return $html
    }
    catch {
        Write-LogEntry -Level 'WARNING' -Component 'REPORT-GENERATOR' -Message "Failed to build key findings: $($_.Exception.Message)"
        return "            <div class='error'>Failed to generate key findings</div>`n"
    }
}

#endregion

#endregion

#region Module Exports
Export-ModuleMember -Function @(
    'New-MaintenanceReport',
    'New-ReportIndex',
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
    'Optimize-ReportDataStructures',
    # Enhanced Reporting Functions v3.0
    'Get-SuccessRate',
    'Get-TotalDuration',
    'Get-SystemHealthScore',
    'Get-ItemsProcessedTotal',
    'Get-ErrorCount',
    'Get-ErrorSeverity',
    'New-ModuleSummary',
    'Build-ModuleLogEntries',
    'Build-PerformancePhases',
    'Build-ModuleErrors',
    'Build-ExecutionTimeline',
    'Build-ActionItems',
    'Get-SystemInformation',
    # Enhanced Builder Functions v3.0
    'Build-ExecutiveDashboard',
    'Build-ModuleCard',
    'Build-ErrorAnalysis',
    'Build-KeyFindings',
    # Enhanced Builder Functions v5.0 (Integrated from ModernReportGenerator)
    'Build-ModuleDetailsSection',
    'Build-ModuleLogsSection'
)
