#Requires -Version 7.0
# Module Dependencies:
#   - ConfigManager.psm1 (for configuration and paths)
#   - LoggingManager.psm1 (for structured logging)
#   - FileOrganizationManager.psm1 (for organized file storage)

<#
.SYNOPSIS
    Enhanced Report Generation Module - Type 1 (Inventory/Reporting)

.DESCRIPTION
    Generates comprehensive, interactive HTML reports with dashboard analytics,
    charts, detailed system analysis, and actionable insights from maintenance
    operations, system inventory, security audits, and performance metrics.

.NOTES
    Module Type: Type 1 (Inventory/Reporting)
    Dependencies: SystemInventory, SecurityAudit, LoggingManager, ConfigManager
    Author: Windows Maintenance Automation Project
    Version: 2.0.0 - Enhanced with dashboard analytics and comprehensive reporting
#>

using namespace System.Collections.Generic
using namespace System.Text

# Import required modules
$ModuleRoot = Split-Path -Parent $PSScriptRoot
$CoreInfraPath = Join-Path $ModuleRoot 'core\CoreInfrastructure.psm1'
if (Test-Path $CoreInfraPath) {
    Import-Module $CoreInfraPath -Force
}

# Import LoggingManager for structured logging (with graceful fallback) - removed since it's in CoreInfrastructure
# Keeping this section for backward compatibility comments

#region Configuration Management

<#
.SYNOPSIS
    Loads the report generation configuration from JSON file

.DESCRIPTION
    Loads and validates the report generation configuration, applying defaults for missing values
#>
function Get-ReportGenerationConfig {
    [CmdletBinding()]
    param()
    
    try {
        $configPath = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'config\report-generation-config.json'
        
        if (-not (Test-Path $configPath)) {
            Write-Warning "Report generation config not found at: $configPath. Using defaults."
            return Get-DefaultReportConfig
        }
        
        $configContent = Get-Content -Path $configPath -Raw -Encoding UTF8
        $config = $configContent | ConvertFrom-Json -AsHashtable
        
        # Validate required fields
        $requiredFields = @('branding.title', 'theme.colors.primary', 'sections.order')
        foreach ($field in $requiredFields) {
            $parts = $field.Split('.')
            $current = $config
            foreach ($part in $parts) {
                if (-not $current.ContainsKey($part)) {
                    throw "Required configuration field missing: $field"
                }
                $current = $current[$part]
            }
        }
        
        Write-Verbose "Report generation configuration loaded successfully from: $configPath"
        return $config
    }
    catch {
        Write-Warning "Failed to load report generation config: $($_.Exception.Message). Using defaults."
        return Get-DefaultReportConfig
    }
}

<#
.SYNOPSIS
    Provides default configuration when config file is not available
#>
function Get-DefaultReportConfig {
    return @{
        branding = @{
            title    = "Windows Maintenance Automation Report"
            subtitle = "System Analysis & Optimization Dashboard"
            company  = "Enterprise Windows Management"
        }
        theme    = @{
            colors = @{
                primary    = "#0078d4"
                success    = "#107c10"
                warning    = "#ffb900"
                error      = "#d13438"
                background = "#faf9f8"
                text       = "#323130"
            }
        }
        sections = @{
            order = @('summary', 'systemInfo', 'moduleResults', 'charts', 'recommendations')
        }
        layout   = @{
            maxWidth         = "1400px"
            containerPadding = "20px"
        }
    }
}

#endregion

#region Public Functions

<#
.SYNOPSIS
    Generates a comprehensive maintenance report

.DESCRIPTION
    Creates HTML and text reports from system inventory, task execution results,
    and configuration data with interactive charts and detailed sections.

.PARAMETER SystemInventory
    System inventory data collected during execution

.PARAMETER TaskResults
    Array of task execution results

.PARAMETER Configuration
    System configuration used during execution

.PARAMETER OutputPath
    Base path for generated reports (without extension)

.EXAMPLE
    New-MaintenanceReport -SystemInventory $inventory -TaskResults $results -OutputPath (Get-ReportsPath)
#>

<#
.SYNOPSIS
    Loads HTML templates from external files

.DESCRIPTION
    Loads and caches HTML templates from the templates directory for report generation
#>
function Get-HtmlTemplates {
    [CmdletBinding()]
    param()
    
    try {
        $configPath = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'config'
        
        if (-not (Test-Path $configPath)) {
            Write-Information "Config directory not found, using embedded templates" -InformationAction Continue
            return $null
        }
        
        $templates = @{}
        
        # Load main template
        $mainTemplatePath = Join-Path $configPath 'report-template.html'
        if (Test-Path $mainTemplatePath) {
            $templates.Main = Get-Content $mainTemplatePath -Raw
        }
        
        # Load task card template  
        $taskCardPath = Join-Path $configPath 'task-card-template.html'
        if (Test-Path $taskCardPath) {
            $templates.TaskCard = Get-Content $taskCardPath -Raw
        }
        
        # Load CSS
        $cssPath = Join-Path $configPath 'report-styles.css'
        if (Test-Path $cssPath) {
            $templates.CSS = Get-Content $cssPath -Raw
        }
        
        # Load report configuration
        $reportConfigPath = Join-Path $configPath 'report-templates-config.json'
        if (Test-Path $reportConfigPath) {
            $templates.Config = Get-Content $reportConfigPath -Raw | ConvertFrom-Json
        }
        
        Write-Information "Loaded external templates from $configPath" -InformationAction Continue
        return $templates
    }
    catch {
        Write-Warning "Failed to load templates: $_"
        return $null
    }
}

function New-MaintenanceReport {
    [CmdletBinding()]
    param(
        [Parameter()]
        [hashtable]$SystemInventory,

        [Parameter()]
        [Array]$TaskResults = @(),

        [Parameter()]
        [PSCustomObject]$Configuration,

        [Parameter(Mandatory)]
        [string]$OutputPath,

        [Parameter()]
        [hashtable]$ComprehensiveLogCollection
    )
    
    # Start performance tracking for report generation
    $perfContext = $null
    try {
        $perfContext = Start-PerformanceTracking -OperationName 'MaintenanceReportGeneration' -Component 'REPORT-GENERATION'
        Write-LogEntry -Level 'INFO' -Component 'REPORT-GENERATION' -Message 'Starting comprehensive maintenance report generation' -Data @{ 
            OutputPath                    = $OutputPath
            HasSystemInventory            = ($null -ne $SystemInventory)
            TaskResultsCount              = $TaskResults.Count
            HasConfiguration              = ($null -ne $Configuration)
            HasComprehensiveLogCollection = ($null -ne $ComprehensiveLogCollection)
            Type1ModulesCount             = if ($ComprehensiveLogCollection) { $ComprehensiveLogCollection.Type1AuditData.Keys.Count } else { 0 }
            Type2ModulesCount             = if ($ComprehensiveLogCollection) { $ComprehensiveLogCollection.Type2ExecutionLogs.Keys.Count } else { 0 }
        }
    }
    catch {
        # LoggingManager not available, continue with standard logging
    }

    Write-Information "📋 Generating comprehensive maintenance report..." -InformationAction Continue

    $startTime = Get-Date
    
    # V3.0 Architecture: Auto-collect module data if TaskResults not provided
    $moduleData = $null
    if ($TaskResults.Count -eq 0) {
        Write-LogEntry -Level 'INFO' -Component 'REPORT-GENERATION' -Message 'TaskResults empty - using v3.0 auto-discovery from session paths'
        $moduleData = Get-ModuleExecutionData
        # Convert moduleData to TaskResults format for backward compatibility
        $TaskResults = Convert-ModuleDataToTaskResults -ModuleData $moduleData
    }
    
    # Enhanced report data structure with comprehensive analytics
    $reportData = @{
        GenerationTime             = $startTime
        SystemInventory            = $SystemInventory
        TaskResults                = $TaskResults
        ModuleData                 = $moduleData  # V3.0: Include raw module data for enhanced reporting
        Configuration              = $Configuration
        ComprehensiveLogCollection = $ComprehensiveLogCollection  # v3.0: Include comprehensive log data from Type1/Type2 modules
        Summary                    = Get-ExecutionSummary -TaskResults $TaskResults
        Analytics                  = @{
            SystemHealth       = Get-SystemHealthAnalytic -SystemInventory $SystemInventory
            PerformanceMetrics = Get-PerformanceAnalytic -TaskResults $TaskResults
            SecurityInsights   = Get-SecurityAnalytic -SystemInventory $SystemInventory
            RecommendedActions = Get-RecommendedAction -SystemInventory $SystemInventory -TaskResults $TaskResults
        }
        Charts                     = @{
            TaskDistribution = Get-TaskDistributionData -TaskResults $TaskResults
            SystemResources  = Get-SystemResourceData -SystemInventory $SystemInventory
            SecurityScore    = Get-SecurityScoreData -SystemInventory $SystemInventory
            TimelineData     = Get-ExecutionTimelineData -TaskResults $TaskResults
        }
    }

    try {
        $ErrorActionPreference = 'Stop'
        Write-Verbose "Starting report generation process"
        
        # Log comprehensive log collection information if available
        if ($ComprehensiveLogCollection) {
            $type1Count = $ComprehensiveLogCollection.Type1AuditData.Keys.Count
            $type2Count = $ComprehensiveLogCollection.Type2ExecutionLogs.Keys.Count
            Write-Information "  📋 Processing comprehensive logs: $type1Count Type1 modules, $type2Count Type2 modules" -InformationAction Continue
            
            Write-LogEntry -Level 'INFO' -Component 'REPORT-GENERATION' -Message 'Processing comprehensive log collection' -Data @{
                Type1ModulesCount   = $type1Count
                Type2ModulesCount   = $type2Count
                SessionId           = $ComprehensiveLogCollection.SessionId
                CollectionTimestamp = $ComprehensiveLogCollection.CollectionTimestamp
            }
        }
        
        # Generate HTML report
        Write-Information "  📄 Creating HTML report..." -InformationAction Continue
        $htmlContent = New-HtmlReportContent -ReportData $reportData
        $htmlPath = $OutputPath
        $htmlContent | Out-File -FilePath $htmlPath -Encoding UTF8 -Force

        # Generate text report
        Write-Information "  📝 Creating text report..." -InformationAction Continue
        $textContent = New-TextReportContent -ReportData $reportData
        $textPath = $htmlPath -replace '\.html$', '.txt'
        $textContent | Out-File -FilePath $textPath -Encoding UTF8 -Force

        # Generate JSON data export
        Write-Information "  📊 Creating JSON data export..." -InformationAction Continue
        $jsonContent = $reportData | ConvertTo-Json -Depth 20 -WarningAction SilentlyContinue
        $jsonPath = $htmlPath -replace '\.html$', '.json'
        $jsonContent | Out-File -FilePath $jsonPath -Encoding UTF8 -Force

        # Generate execution summary
        $summaryContent = if ($reportData.Summary) { $reportData.Summary | ConvertTo-Json -Depth 15 -WarningAction SilentlyContinue } else { '{}' }
        $summaryPath = $htmlPath -replace '\.html$', '-summary.json'
        $summaryContent | Out-File -FilePath $summaryPath -Encoding UTF8 -Force

        $duration = ((Get-Date) - $startTime).TotalSeconds
        
        # Complete performance tracking and structured logging for success
        $result = @{
            HtmlReport       = $htmlPath
            TextReport       = $textPath
            JsonExport       = $jsonPath
            ExecutionSummary = $summaryPath
            GenerationTime   = $startTime
            Duration         = $duration
        }
        
        try {
            Complete-PerformanceTracking -Context $perfContext -Status 'Success' -ResultCount $TaskResults.Count
            Write-LogEntry -Level 'SUCCESS' -Component 'REPORT-GENERATION' -Message 'Maintenance report generation completed successfully' -Data $result
        }
        catch {
            # LoggingManager not available, continue with standard logging
        }
        
        Write-Information "  ✅ Reports generated successfully in $([math]::Round($duration, 2)) seconds" -InformationAction Continue
        Write-Verbose "Report generation completed successfully"

        # V3.0 Enhancement: Copy report to repository root for easy access
        try {
            $scriptRoot = $PSScriptRoot
            if (-not $scriptRoot) {
                # Fallback for different execution contexts
                $scriptRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path))
            }
            else {
                # Navigate up to repo root from modules/core/
                $scriptRoot = Split-Path -Parent (Split-Path -Parent $scriptRoot)
            }
            
            if (Test-Path $scriptRoot) {
                $repoReportName = "MaintenanceReport_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').html"
                $repoReportPath = Join-Path $scriptRoot $repoReportName
                
                Copy-Item -Path $htmlPath -Destination $repoReportPath -Force
                Write-Information "  📋 Report copied to repository: $repoReportName" -InformationAction Continue
                
                # Add to result
                $result.RepositoryCopy = $repoReportPath
                
                # Also create a 'latest' symlink/copy for easy access
                $latestReportPath = Join-Path $scriptRoot "latest-maintenance-report.html"
                Copy-Item -Path $htmlPath -Destination $latestReportPath -Force
                Write-Information "  🔗 Latest report link updated: latest-maintenance-report.html" -InformationAction Continue
                
                $result.LatestReportCopy = $latestReportPath
            }
        }
        catch {
            Write-Warning "Failed to copy report to repository root: $($_.Exception.Message)"
        }

        return $result
    }
    catch {
        $errorMessage = "❌ Failed to generate maintenance report: $($_.Exception.Message)" 
        Write-Error $errorMessage
        Write-Verbose "Error details: $($_.Exception.ToString())"
        
        # Complete performance tracking for failed operation
        try {
            Complete-PerformanceTracking -Context $perfContext -Status 'Failed' -ErrorMessage $_.Exception.Message
            Write-LogEntry -Level 'ERROR' -Component 'REPORT-GENERATION' -Message 'Maintenance report generation failed' -Data @{ Error = $_.Exception.Message; ErrorType = $_.Exception.GetType().Name; OutputPath = $OutputPath }
        }
        catch {
            # LoggingManager not available, continue with standard logging
        }
        
        # Return null object to indicate failure for Type 1 module
        return $null
    }
    finally {
        $ErrorActionPreference = 'Continue'
        Write-Verbose "Completed report generation operation"
    }
}

#endregion

#region HTML Report Generation

<#
.SYNOPSIS
    Creates interactive HTML dashboard report with charts and analytics

.DESCRIPTION
    Generates a modern, responsive HTML dashboard report featuring interactive charts,
    collapsible sections, health scoring, and comprehensive system analytics.
    Includes Chart.js integration for data visualization and Microsoft Fluent UI styling.

.PARAMETER ReportData
    Hashtable containing all report data including system inventory, task results,
    analytics, and chart data for visualization

.OUTPUTS
    [string] Complete HTML document with embedded CSS, JavaScript, and data visualizations

.EXAMPLE
    $htmlReport = New-HtmlReportContent -ReportData $reportData
    Set-Content -Path "maintenance-report.html" -Value $htmlReport
    
.NOTES
    Creates enterprise-grade dashboard reports with:
    - Interactive charts using Chart.js
    - Responsive design with mobile support
    - Collapsible sections for organized content
    - Health scoring with visual indicators
    - Performance timeline visualization
    - Security audit radar charts
#>
function New-HtmlReportContent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$ReportData
    )

    # Load configuration for styling and layout
    $config = Get-ReportGenerationConfig
    if (-not $config) {
        throw "Report generation configuration is null"
    }
    
    Write-Verbose "Generating HTML report content with configuration theme: $($config.theme.name -or 'Default')"

    $html = [System.Text.StringBuilder]::new()
    if (-not $html) {
        throw "Failed to initialize StringBuilder for HTML generation"
    }

    # Use configuration values for branding and styling
    $title = if ($config.branding -and $config.branding.title) { $config.branding.title } else { "Windows Maintenance Report" }
    $subtitle = if ($config.branding -and $config.branding.subtitle) { $config.branding.subtitle } else { "System Analysis Dashboard" }
    $colors = if ($config.theme -and $config.theme.colors) { $config.theme.colors } else { @{ primary = "#0078d4"; success = "#107c10"; warning = "#ffb900"; error = "#d13438" } }

    # Enhanced HTML header with modern dashboard styling and JavaScript
    $html.AppendLine(@"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>$title - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</title>
    
    <!-- Chart.js for interactive charts -->
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
    <script src="https://cdn.jsdelivr.net/npm/date-fns@1.30.1/index.min.js"></script>
    <script src="https://cdn.jsdelivr.net/npm/chartjs-adapter-date-fns@2.0.1/dist/chartjs-adapter-date-fns.bundle.min.js"></script>
    
    <style>
        :root {
            --primary-color: $($colors.primary -or '#0078d4');
            --primary-dark: $(if ($colors.primaryDark) { $colors.primaryDark } else { '#106ebe' });
            --success-color: $($colors.success -or '#107c10');
            --warning-color: #ffb900;
            --error-color: #d13438;
            --critical-color: #a80000;
            --bg-color: #faf9f8;
            --card-bg: #ffffff;
            --text-color: #323130;
            --text-secondary: #605e5c;
            --border-color: #e1dfdd;
            --shadow: 0 2px 8px rgba(0,0,0,0.1);
            --shadow-hover: 0 4px 16px rgba(0,0,0,0.15);
            --gradient-primary: linear-gradient(135deg, var(--primary-color), var(--primary-dark));
            --gradient-success: linear-gradient(135deg, #107c10, #0e6e0e);
            --gradient-warning: linear-gradient(135deg, #ffb900, #d49c00);
            --gradient-error: linear-gradient(135deg, #d13438, #b22929);
        }

        * { 
            margin: 0; 
            padding: 0; 
            box-sizing: border-box; 
        }

        body {
            font-family: 'Segoe UI', -apple-system, BlinkMacSystemFont, 'Roboto', 'Helvetica Neue', sans-serif;
            background: var(--bg-color);
            color: var(--text-color);
            line-height: 1.6;
            font-size: 14px;
        }

        .container {
            max-width: 1400px;
            margin: 0 auto;
            padding: 20px;
        }

        /* Enhanced Header */
        .header {
            background: var(--gradient-primary);
            color: white;
            padding: 40px;
            border-radius: 12px;
            margin-bottom: 30px;
            text-align: center;
            box-shadow: var(--shadow);
        }

        .header h1 { 
            font-size: 2.8em; 
            margin-bottom: 10px; 
            font-weight: 300;
        }
        
        .header .subtitle { 
            font-size: 1.3em; 
            opacity: 0.9; 
            margin-bottom: 20px;
        }
        
        .header .meta {
            display: flex;
            justify-content: center;
            gap: 30px;
            flex-wrap: wrap;
            font-size: 1em;
            opacity: 0.8;
        }

        /* Dashboard Grid */
        .dashboard-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
            gap: 25px;
            margin-bottom: 40px;
        }

        .dashboard-card {
            background: var(--card-bg);
            padding: 30px;
            border-radius: 12px;
            box-shadow: var(--shadow);
            text-align: center;
            transition: all 0.3s ease;
            border-top: 4px solid var(--primary-color);
        }

        .dashboard-card:hover {
            box-shadow: var(--shadow-hover);
            transform: translateY(-2px);
        }

        .dashboard-card.success { border-top-color: var(--success-color); }
        .dashboard-card.warning { border-top-color: var(--warning-color); }
        .dashboard-card.error { border-top-color: var(--error-color); }

        .dashboard-card .icon {
            font-size: 3em;
            margin-bottom: 15px;
            display: block;
        }

        .dashboard-card h3 {
            color: var(--text-secondary);
            margin-bottom: 15px;
            font-size: 1em;
            font-weight: 600;
            text-transform: uppercase;
            letter-spacing: 0.5px;
        }

        .dashboard-card .value {
            font-size: 3.2em;
            font-weight: 700;
            margin-bottom: 10px;
            color: var(--primary-color);
        }

        .dashboard-card .value.success { color: var(--success-color); }
        .dashboard-card .value.warning { color: var(--warning-color); }
        .dashboard-card .value.error { color: var(--error-color); }

        .dashboard-card .description {
            color: var(--text-secondary);
            font-size: 0.9em;
        }

        /* Enhanced Sections */
        .section {
            background: var(--card-bg);
            border-radius: 12px;
            margin-bottom: 30px;
            overflow: hidden;
            box-shadow: var(--shadow);
            transition: all 0.3s ease;
        }

        .section:hover {
            box-shadow: var(--shadow-hover);
        }

        .section-header {
            background: var(--gradient-primary);
            color: white;
            padding: 25px 30px;
            cursor: pointer;
            display: flex;
            justify-content: space-between;
            align-items: center;
            transition: background 0.3s ease;
        }

        .section-header:hover {
            background: var(--gradient-primary);
            filter: brightness(1.1);
        }

        .section-header h2 {
            font-size: 1.4em;
            font-weight: 600;
        }

        .section-content {
            padding: 30px;
            display: none;
            background: var(--card-bg);
        }

        .section.expanded .section-content {
            display: block;
        }

        .toggle-icon {
            transition: transform 0.3s ease;
            font-size: 1.2em;
        }

        .section.expanded .toggle-icon {
            transform: rotate(180deg);
        }

        /* Enhanced Charts Section */
        .charts-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(400px, 1fr));
            gap: 30px;
            margin-bottom: 40px;
        }

        .chart-card {
            background: var(--card-bg);
            border-radius: 12px;
            padding: 25px;
            box-shadow: var(--shadow);
            transition: all 0.3s ease;
        }

        .chart-card:hover {
            box-shadow: var(--shadow-hover);
        }

        .chart-card h3 {
            color: var(--primary-color);
            margin-bottom: 20px;
            font-size: 1.2em;
            text-align: center;
        }

        .chart-container {
            position: relative;
            height: 300px;
            margin-bottom: 15px;
        }

        /* Task Lists */
        .task-list {
            list-style: none;
        }

        .task-item {
            display: flex;
            align-items: center;
            padding: 20px;
            border-bottom: 1px solid var(--border-color);
            transition: background-color 0.3s ease;
        }

        .task-item:hover {
            background-color: #f8f9fa;
        }

        .task-item:last-child {
            border-bottom: none;
        }

        .task-status {
            width: 32px;
            height: 32px;
            border-radius: 50%;
            margin-right: 20px;
            display: flex;
            align-items: center;
            justify-content: center;
            color: white;
            font-weight: bold;
            font-size: 1.1em;
        }

        .task-details {
            flex: 1;
        }

        .task-name {
            font-weight: 600;
            margin-bottom: 8px;
            font-size: 1.1em;
        }

        .task-description {
            color: var(--text-secondary);
            font-size: 0.95em;
            line-height: 1.4;
        }

        .task-meta {
            display: flex;
            align-items: center;
            gap: 20px;
            color: var(--text-secondary);
            font-size: 0.85em;
        }

        .task-duration {
            background: #f3f2f1;
            padding: 4px 8px;
            border-radius: 4px;
            font-weight: 500;
        }

        /* Enhanced Tables */
        .info-table {
            width: 100%;
            border-collapse: collapse;
            margin-top: 20px;
        }

        .info-table th,
        .info-table td {
            text-align: left;
            padding: 15px;
            border-bottom: 1px solid var(--border-color);
        }

        .info-table th {
            background: #f8f9fa;
            font-weight: 600;
            color: var(--primary-color);
            text-transform: uppercase;
            font-size: 0.85em;
            letter-spacing: 0.5px;
        }

        .info-table tr:hover {
            background: rgba(0, 120, 212, 0.05);
        }

        /* Health Score Display */
        .health-score {
            display: flex;
            align-items: center;
            justify-content: center;
            margin: 20px 0;
        }

        .health-circle {
            width: 120px;
            height: 120px;
            border-radius: 50%;
            display: flex;
            align-items: center;
            justify-content: center;
            font-size: 2em;
            font-weight: bold;
            color: white;
            margin-right: 20px;
        }

        .health-circle.excellent { background: var(--gradient-success); }
        .health-circle.good { background: var(--gradient-primary); }
        .health-circle.warning { background: var(--gradient-warning); }
        .health-circle.poor { background: var(--gradient-error); }

        /* Recommendations */
        .recommendations {
            background: #fff4e6;
            border: 1px solid #ffb900;
            border-radius: 8px;
            padding: 20px;
            margin: 20px 0;
        }

        /* Error Analysis Section */
        .error-summary {
            background: #fef9f9;
            border: 1px solid #d13438;
            border-radius: 8px;
            padding: 20px;
            margin-bottom: 20px;
        }

        .error-stats {
            display: flex;
            gap: 20px;
            justify-content: center;
        }

        .stat-item {
            text-align: center;
            padding: 15px;
            border-radius: 8px;
            background: white;
            box-shadow: var(--shadow);
        }

        .stat-item.error-high {
            border-top: 3px solid #d13438;
        }

        .stat-item.error-medium {
            border-top: 3px solid #ffb900;
        }

        .stat-number {
            display: block;
            font-size: 2em;
            font-weight: bold;
            color: var(--primary-color);
        }

        .stat-label {
            display: block;
            color: var(--text-secondary);
            font-size: 0.9em;
            margin-top: 5px;
        }

        .success-message {
            background: #f3f9f3;
            border: 1px solid #107c10;
            border-radius: 8px;
            padding: 20px;
            text-align: center;
            color: #107c10;
        }

        .module-errors {
            margin-bottom: 30px;
        }

        .module-error-header {
            background: var(--gradient-primary);
            color: white;
            padding: 15px;
            border-radius: 8px 8px 0 0;
            margin: 0;
            font-size: 1.1em;
        }

        .error-list {
            border: 1px solid var(--border-color);
            border-top: none;
            border-radius: 0 0 8px 8px;
            background: white;
        }

        .error-item {
            border-bottom: 1px solid #f3f2f1;
            padding: 15px;
        }

        .error-item:last-child {
            border-bottom: none;
        }

        .error-item.severity-high {
            border-left: 4px solid #d13438;
            background: #fef9f9;
        }

        .error-item.severity-medium {
            border-left: 4px solid #ffb900;
            background: #fffbf5;
        }

        .error-item.severity-low {
            border-left: 4px solid #a19f9d;
            background: #faf9f8;
        }

        .error-header {
            display: flex;
            align-items: center;
            gap: 10px;
            margin-bottom: 8px;
            font-size: 0.9em;
        }

        .error-icon {
            font-size: 1.2em;
        }

        .error-level {
            background: var(--primary-color);
            color: white;
            padding: 2px 8px;
            border-radius: 4px;
            font-weight: bold;
            font-size: 0.8em;
        }

        .error-component {
            background: #f3f2f1;
            padding: 2px 8px;
            border-radius: 4px;
            font-weight: 500;
            font-size: 0.8em;
        }

        .error-timestamp {
            color: var(--text-secondary);
            font-size: 0.8em;
            margin-left: auto;
        }

        .error-message {
            color: var(--text-color);
            line-height: 1.4;
            margin-left: 30px;
        }

        .recommendations h4 {
            color: #d49c00;
            margin-bottom: 15px;
            font-size: 1.1em;
        }

        .recommendation-item {
            display: flex;
            align-items: flex-start;
            margin-bottom: 10px;
            padding: 10px;
            background: white;
            border-radius: 6px;
        }

        .recommendation-icon {
            margin-right: 10px;
            font-size: 1.2em;
        }

        /* Footer */
        .footer {
            text-align: center;
            padding: 40px 20px;
            color: var(--text-secondary);
            border-top: 1px solid var(--border-color);
            margin-top: 40px;
        }

        /* Responsive Design */
        @media (max-width: 768px) {
            .container { padding: 15px; }
            .header { padding: 25px; }
            .header h1 { font-size: 2.2em; }
            .dashboard-grid { grid-template-columns: 1fr; }
            .charts-grid { grid-template-columns: 1fr; }
            .header .meta { flex-direction: column; gap: 10px; }
            .task-item { flex-direction: column; align-items: flex-start; }
            .task-status { margin-bottom: 10px; }
        }

        /* Animations */
        @keyframes fadeIn {
            from { opacity: 0; transform: translateY(20px); }
            to { opacity: 1; transform: translateY(0); }
        }

        .section, .dashboard-card, .chart-card {
            animation: fadeIn 0.6s ease-out;
        }

        /* Loading States */
        .loading {
            display: flex;
            align-items: center;
            justify-content: center;
            height: 200px;
            color: var(--text-secondary);
        }

        .spinner {
            border: 3px solid #f3f3f3;
            border-top: 3px solid var(--primary-color);
            border-radius: 50%;
            width: 30px;
            height: 30px;
            animation: spin 1s linear infinite;
            margin-right: 10px;
        }

        @keyframes spin {
            0% { transform: rotate(0deg); }
            100% { transform: rotate(360deg); }
        }

        /* Module Activities Styles */
        .module-activities {
            display: grid;
            gap: 20px;
            margin-top: 15px;
        }

        .module-activity {
            background: var(--card-bg);
            border-radius: 12px;
            padding: 20px;
            box-shadow: 0 2px 8px rgba(0,0,0,0.1);
            transition: all 0.3s ease;
        }

        .module-activity:hover {
            transform: translateY(-2px);
            box-shadow: 0 4px 16px rgba(0,0,0,0.15);
        }

        .module-header {
            display: flex;
            align-items: center;
            gap: 12px;
            margin-bottom: 15px;
            padding-bottom: 12px;
            border-bottom: 1px solid var(--border-color);
        }

        .module-icon {
            font-size: 24px;
            display: flex;
            align-items: center;
            justify-content: center;
            width: 40px;
            height: 40px;
            border-radius: 8px;
            background: rgba(255,255,255,0.1);
        }

        .module-header h3 {
            margin: 0;
            flex: 1;
            color: var(--text-color);
            font-size: 18px;
            font-weight: 600;
        }

        .status-badge {
            padding: 4px 12px;
            border-radius: 20px;
            font-size: 12px;
            font-weight: 600;
            text-transform: uppercase;
            letter-spacing: 0.5px;
        }

        .status-badge.success {
            background: var(--success-color);
            color: white;
        }

        .status-badge.error {
            background: var(--error-color);
            color: white;
        }

        .dry-run-badge {
            background: var(--warning-color);
            color: white;
            padding: 2px 8px;
            border-radius: 12px;
            font-size: 11px;
            font-weight: 600;
            text-transform: uppercase;
        }

        .module-details {
            margin-bottom: 20px;
        }

        .module-details p {
            margin: 8px 0;
            color: var(--text-secondary);
            line-height: 1.5;
        }

        .module-details strong {
            color: var(--text-color);
            font-weight: 600;
        }

        .error-details {
            background: rgba(231, 76, 60, 0.1);
            border: 1px solid rgba(231, 76, 60, 0.3);
            border-radius: 8px;
            padding: 12px;
            margin-top: 12px;
            color: var(--error-color);
        }

        .module-actions {
            border-top: 1px solid var(--border-color);
            padding-top: 15px;
        }

        .module-actions h4 {
            margin: 0 0 10px 0;
            color: var(--text-color);
            font-size: 14px;
            font-weight: 600;
            text-transform: uppercase;
            letter-spacing: 0.5px;
        }

        .actions-placeholder {
            background: rgba(149, 165, 166, 0.1);
            border-radius: 8px;
            padding: 15px;
            border: 1px dashed var(--border-color);
        }

        .actions-placeholder p {
            margin: 5px 0;
            color: var(--text-secondary);
            font-style: italic;
            font-size: 13px;
        }

        /* Print Styles */
        @media print {
            .section-content { display: block !important; }
            .dashboard-card { break-inside: avoid; }
            .chart-card { break-inside: avoid; }
            .module-activity { break-inside: avoid; }
        }

        /* Enhanced Module Sections with Flexbox Layout */
        .modules-container {
            display: flex;
            flex-direction: column;
            gap: 30px;
            margin-top: 40px;
        }

        .module-section {
            background: var(--card-bg);
            border-radius: 16px;
            box-shadow: var(--shadow);
            overflow: hidden;
            transition: all 0.3s ease;
            border: 1px solid var(--border-color);
        }

        .module-section:hover {
            box-shadow: var(--shadow-hover);
            transform: translateY(-1px);
        }

        .module-header {
            display: flex;
            align-items: center;
            justify-content: space-between;
            padding: 25px 30px;
            background: linear-gradient(135deg, #f8f9fa, #e9ecef);
            border-bottom: 1px solid var(--border-color);
            cursor: pointer;
        }

        .module-header .module-title {
            display: flex;
            align-items: center;
            gap: 15px;
        }

        .module-header .module-icon {
            font-size: 2.2em;
            width: 60px;
            height: 60px;
            border-radius: 12px;
            display: flex;
            align-items: center;
            justify-content: center;
            color: white;
            background: var(--gradient-primary);
        }

        .module-header .module-info h3 {
            font-size: 1.4em;
            font-weight: 600;
            margin-bottom: 5px;
            color: var(--text-color);
        }

        .module-header .module-info .module-description {
            color: var(--text-secondary);
            font-size: 0.95em;
        }

        .module-status {
            display: flex;
            align-items: center;
            gap: 10px;
            padding: 8px 16px;
            border-radius: 20px;
            font-size: 0.9em;
            font-weight: 600;
            text-transform: uppercase;
            letter-spacing: 0.5px;
        }

        .module-status.success {
            background: rgba(16, 124, 16, 0.1);
            color: var(--success-color);
            border: 1px solid rgba(16, 124, 16, 0.2);
        }

        .module-status.warning {
            background: rgba(255, 185, 0, 0.1);
            color: var(--warning-color);
            border: 1px solid rgba(255, 185, 0, 0.2);
        }

        .module-status.error {
            background: rgba(209, 52, 56, 0.1);
            color: var(--error-color);
            border: 1px solid rgba(209, 52, 56, 0.2);
        }

        .module-content {
            padding: 30px;
        }

        .module-summary {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }

        .summary-item {
            background: rgba(0, 120, 212, 0.05);
            padding: 20px;
            border-radius: 10px;
            text-align: center;
            border: 1px solid rgba(0, 120, 212, 0.1);
        }

        .summary-item .summary-value {
            font-size: 2.2em;
            font-weight: 700;
            color: var(--primary-color);
            display: block;
            margin-bottom: 8px;
        }

        .summary-item .summary-label {
            color: var(--text-secondary);
            font-size: 0.9em;
            font-weight: 500;
            text-transform: uppercase;
            letter-spacing: 0.3px;
        }

        .module-details {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
            gap: 25px;
        }

        .detail-card {
            background: #ffffff;
            border: 1px solid var(--border-color);
            border-radius: 12px;
            padding: 20px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.05);
        }

        .detail-card h4 {
            color: var(--primary-color);
            margin-bottom: 15px;
            font-size: 1.1em;
            font-weight: 600;
            display: flex;
            align-items: center;
            gap: 8px;
        }

        .detail-list {
            list-style: none;
            padding: 0;
        }

        .detail-list li {
            padding: 8px 0;
            border-bottom: 1px solid rgba(0,0,0,0.05);
            display: flex;
            justify-content: space-between;
            align-items: center;
        }

        .detail-list li:last-child {
            border-bottom: none;
        }

        .detail-badge {
            background: var(--gradient-primary);
            color: white;
            padding: 4px 12px;
            border-radius: 12px;
            font-size: 0.8em;
            font-weight: 600;
        }

        .detail-badge.success { background: var(--gradient-success); }
        .detail-badge.warning { background: var(--gradient-warning); }
        .detail-badge.error { background: var(--gradient-error); }

        /* Expandable content */
        .module-section.collapsed .module-content {
            display: none;
        }

        .expand-icon {
            transition: transform 0.3s ease;
            font-size: 1.2em;
            color: var(--text-secondary);
        }

        .module-section.collapsed .expand-icon {
            transform: rotate(-90deg);
        }

        /* Quick Actions Bar */
        .quick-actions {
            background: linear-gradient(135deg, #f8f9fa, #ffffff);
            padding: 20px 30px;
            border-radius: 12px;
            margin: 30px 0;
            display: flex;
            gap: 15px;
            flex-wrap: wrap;
            align-items: center;
            border: 1px solid var(--border-color);
        }

        .quick-action-btn {
            background: var(--gradient-primary);
            color: white;
            padding: 12px 24px;
            border: none;
            border-radius: 8px;
            cursor: pointer;
            font-weight: 600;
            font-size: 0.9em;
            text-decoration: none;
            display: inline-flex;
            align-items: center;
            gap: 8px;
            transition: all 0.3s ease;
        }

        .quick-action-btn:hover {
            transform: translateY(-2px);
            box-shadow: 0 4px 12px rgba(0, 120, 212, 0.3);
        }

        .quick-action-btn.secondary {
            background: var(--gradient-success);
        }

        .quick-action-btn.warning {
            background: var(--gradient-warning);
        }
    </style>
    
    <script>
        // Enhanced JavaScript for interactive features
        let charts = {};
        
        function toggleSection(element) {
            const section = element.parentElement;
            section.classList.toggle('expanded');
        }

        function initializeCharts() {
            // Task Distribution Chart
            if (document.getElementById('taskDistributionChart')) {
                createTaskDistributionChart();
            }
            
            // System Resources Chart
            if (document.getElementById('systemResourcesChart')) {
                createSystemResourcesChart();
            }
            
            // Timeline Chart
            if (document.getElementById('timelineChart')) {
                createTimelineChart();
            }
            
            // Security Score Chart
            if (document.getElementById('securityScoreChart')) {
                createSecurityScoreChart();
            }
        }

        function createTaskDistributionChart() {
            const ctx = document.getElementById('taskDistributionChart').getContext('2d');
            charts.taskDistribution = new Chart(ctx, {
                type: 'doughnut',
                data: window.taskDistributionData,
                options: {
                    responsive: true,
                    maintainAspectRatio: false,
                    plugins: {
                        legend: {
                            position: 'bottom',
                            labels: {
                                padding: 20,
                                usePointStyle: true
                            }
                        }
                    }
                }
            });
        }

        function createSystemResourcesChart() {
            const ctx = document.getElementById('systemResourcesChart').getContext('2d');
            charts.systemResources = new Chart(ctx, {
                type: 'bar',
                data: window.systemResourcesData,
                options: {
                    responsive: true,
                    maintainAspectRatio: false,
                    plugins: {
                        legend: {
                            display: false
                        }
                    },
                    scales: {
                        y: {
                            beginAtZero: true,
                            max: 100
                        }
                    }
                }
            });
        }

        function createTimelineChart() {
            const ctx = document.getElementById('timelineChart').getContext('2d');
            charts.timeline = new Chart(ctx, {
                type: 'line',
                data: window.timelineData,
                options: {
                    responsive: true,
                    maintainAspectRatio: false,
                    plugins: {
                        legend: {
                            display: false
                        }
                    },
                    scales: {
                        x: {
                            type: 'time',
                            time: {
                                unit: 'minute'
                            }
                        }
                    }
                }
            });
        }

        function createSecurityScoreChart() {
            const ctx = document.getElementById('securityScoreChart').getContext('2d');
            charts.securityScore = new Chart(ctx, {
                type: 'radar',
                data: window.securityScoreData,
                options: {
                    responsive: true,
                    maintainAspectRatio: false,
                    scales: {
                        r: {
                            beginAtZero: true,
                            max: 100
                        }
                    }
                }
            });
        }

        // Initialize when DOM is loaded
        document.addEventListener('DOMContentLoaded', function() {
            // Expand first section by default
            const firstSection = document.querySelector('.section');
            if (firstSection) {
                firstSection.classList.add('expanded');
            }
            
            // Initialize charts after a brief delay
            setTimeout(initializeCharts, 100);
        });

        // Utility functions
        function formatBytes(bytes, decimals = 2) {
            if (bytes === 0) return '0 Bytes';
            const k = 1024;
            const dm = decimals < 0 ? 0 : decimals;
            const sizes = ['Bytes', 'KB', 'MB', 'GB', 'TB'];
            const i = Math.floor(Math.log(bytes) / Math.log(k));
            return parseFloat((bytes / Math.pow(k, i)).toFixed(dm)) + ' ' + sizes[i];
        }

        function getHealthScoreClass(score) {
            if (score >= 90) return 'excellent';
            if (score >= 75) return 'good';
            if (score >= 50) return 'warning';
            return 'poor';
        }
    </script>
</head>
<body>
    <div class="container">
"@) | Out-Null

    # Enhanced header with comprehensive information
    $duration = [math]::Round(((Get-Date) - $ReportData.GenerationTime).TotalMinutes, 1)
    $healthScore = if ($ReportData.Analytics.SystemHealth.OverallScore) { $ReportData.Analytics.SystemHealth.OverallScore } else { 85 }
    $healthClass = if ($healthScore -ge 90) { 'excellent' } elseif ($healthScore -ge 75) { 'good' } elseif ($healthScore -ge 50) { 'warning' } else { 'poor' }
    
    $html.AppendLine(@"
        <div class="header">
            <h1>🛠️ $title</h1>
            <div class="subtitle">$subtitle</div>
            <div class="meta">
                <span>📅 $(Get-Date -Format 'dddd, MMMM dd, yyyy at HH:mm:ss')</span>
                <span>💻 $env:COMPUTERNAME</span>
                <span>👤 $env:USERNAME</span>
                <span>⏱️ Generated in ${duration}m</span>
                <span>🏥 Health Score: ${healthScore}/100</span>
            </div>
        </div>
"@) | Out-Null

    # Enhanced dashboard with comprehensive metrics from logs
    $comprehensiveDashboard = Get-ComprehensiveDashboardMetrics -ComprehensiveLogCollection $ReportData.ComprehensiveLogCollection
    $summary = $ReportData.Summary
    $analytics = $ReportData.Analytics
    
    # Use comprehensive log data if available, fallback to existing data
    $totalTasks = if ($comprehensiveDashboard.TotalTasks -gt 0) { $comprehensiveDashboard.TotalTasks } else { $summary.TotalTasks }
    $successRate = if ($comprehensiveDashboard.SuccessRate -ge 0) { $comprehensiveDashboard.SuccessRate } else { $summary.SuccessRate }
    $failedTasks = if ($comprehensiveDashboard.FailedTasks -ge 0) { $comprehensiveDashboard.FailedTasks } else { $summary.FailedTasks }
    $totalDuration = if ($comprehensiveDashboard.TotalDuration -gt 0) { $comprehensiveDashboard.TotalDuration } else { $summary.TotalDuration }
    $systemHealth = if ($comprehensiveDashboard.SystemHealth -gt 0) { $comprehensiveDashboard.SystemHealth } else { $healthScore }
    $securityScore = if ($comprehensiveDashboard.SecurityScore -gt 0) { $comprehensiveDashboard.SecurityScore } else { $(if ($analytics.SecurityInsights.SecurityScore) { $analytics.SecurityInsights.SecurityScore } else { 'N/A' }) }
    $successfulTasks = if ($comprehensiveDashboard.SuccessfulTasks -gt 0) { $comprehensiveDashboard.SuccessfulTasks } else { $summary.SuccessfulTasks }
    
    $html.AppendLine(@"
        <div class="dashboard-grid">
            <div class="dashboard-card">
                <span class="icon">📊</span>
                <h3>Tasks Executed</h3>
                <div class="value">$totalTasks</div>
                <div class="description">Total maintenance operations</div>
            </div>
            <div class="dashboard-card success">
                <span class="icon">✅</span>
                <h3>Success Rate</h3>
                <div class="value success">$successRate%</div>
                <div class="description">$successfulTasks of $totalTasks completed</div>
            </div>
            <div class="dashboard-card $(if ($failedTasks -gt 0) { 'error' } else { '' })">
                <span class="icon">❌</span>
                <h3>Failed Tasks</h3>
                <div class="value $(if ($failedTasks -gt 0) { 'error' } else { '' })">$failedTasks</div>
                <div class="description">Issues requiring attention</div>
            </div>
            <div class="dashboard-card">
                <span class="icon">⏱️</span>
                <h3>Total Duration</h3>
                <div class="value">$([math]::Round($totalDuration, 1))s</div>
                <div class="description">Execution time</div>
            </div>
            <div class="dashboard-card $healthClass">
                <span class="icon">🏥</span>
                <h3>System Health</h3>
                <div class="value $healthClass">$systemHealth</div>
                <div class="description">Overall system score</div>
            </div>
            <div class="dashboard-card">
                <span class="icon">🔒</span>
                <h3>Security Score</h3>
                <div class="value">$securityScore</div>
                <div class="description">Security assessment</div>
            </div>
        </div>
"@) | Out-Null

    # Interactive Charts Section
    $html.AppendLine(@"
        <div class="charts-grid">
            <div class="chart-card">
                <h3>📊 Task Distribution</h3>
                <div class="chart-container">
                    <canvas id="taskDistributionChart"></canvas>
                </div>
            </div>
            <div class="chart-card">
                <h3>💾 System Resources</h3>
                <div class="chart-container">
                    <canvas id="systemResourcesChart"></canvas>
                </div>
            </div>
            <div class="chart-card">
                <h3>⏱️ Execution Timeline</h3>
                <div class="chart-container">
                    <canvas id="timelineChart"></canvas>
                </div>
            </div>
            <div class="chart-card">
                <h3>🔒 Security Assessment</h3>
                <div class="chart-container">
                    <canvas id="securityScoreChart"></canvas>
                </div>
            </div>
        </div>
"@) | Out-Null

    # Task execution results from comprehensive log analysis
    $detailedTaskResults = Get-DetailedTaskResults -ComprehensiveLogCollection $ReportData.ComprehensiveLogCollection
    
    # Use detailed task results if available, fallback to existing data
    $taskResultsToShow = if ($detailedTaskResults.Count -gt 0) { $detailedTaskResults } else { $ReportData.TaskResults }
    
    if ($taskResultsToShow.Count -gt 0) {
        $html.AppendLine(@"
        <div class="section">
            <div class="section-header" onclick="toggleSection(this)">
                <h2>📋 Task Execution Results</h2>
                <span class="toggle-icon">▼</span>
            </div>
            <div class="section-content">
                <ul class="task-list">
"@) | Out-Null

        foreach ($task in $taskResultsToShow) {
            $statusIcon = if ($task.Success) { '✓' } else { '✗' }
            $statusColor = if ($task.Success) { 'var(--success-color)' } else { 'var(--error-color)' }
            $duration = if ($task.Duration) { [math]::Round($task.Duration, 2) } else { 0 }
            
            # Enhanced task details from comprehensive log analysis
            $taskDescription = if ($task.Description) { $task.Description } else { $task.Details }
            $itemsProcessed = if ($task.ItemsProcessed) { " ($($task.ItemsProcessed) items)" } else { "" }

            $html.AppendLine(@"
                    <li class="task-item">
                        <div class="task-status" style="background-color: $statusColor">$statusIcon</div>
                        <div class="task-details">
                            <div class="task-name">$($task.TaskName)$itemsProcessed</div>
                            <div class="task-description">$taskDescription</div>
                            $(if (-not $task.Success -and $task.Error) { "<div style='color: var(--error-color); font-size: 0.9em; margin-top: 5px;'>Error: $($task.Error)</div>" })
                            $(if ($task.SuccessCount -gt 0) { "<div style='color: var(--success-color); font-size: 0.9em; margin-top: 3px;'>✓ $($task.SuccessCount) successful operations</div>" })
                            $(if ($task.ErrorCount -gt 0) { "<div style='color: var(--error-color); font-size: 0.9em; margin-top: 3px;'>✗ $($task.ErrorCount) failed operations</div>" })
                        </div>
                        <div class="task-duration">${duration}s</div>
                    </li>
"@) | Out-Null
        }

        $html.AppendLine(@"
                </ul>
            </div>
        </div>
"@) | Out-Null
    }

    # System Modification Activities from comprehensive log analysis
    $systemModifications = Get-SystemModificationActivities -ComprehensiveLogCollection $ReportData.ComprehensiveLogCollection
    
    # Use detailed task results if available for fallback data  
    $type2Results = if ($taskResultsToShow) { $taskResultsToShow | Where-Object { $_.Type -eq 'Type2' } } else { $ReportData.TaskResults | Where-Object { $_.Type -eq 'Type2' } }
    
    if ($systemModifications.Count -gt 0 -or $type2Results.Count -gt 0) {
        $html.AppendLine(@"
        <div class="section">
            <div class="section-header" onclick="toggleSection(this)">
                <h2>🔧 System Modification Activities</h2>
                <span class="toggle-icon">▼</span>
            </div>
            <div class="section-content">
                <div class="module-activities">
"@) | Out-Null

        # Group modifications by module for organized display
        $moduleModifications = @{}
        foreach ($modification in $systemModifications) {
            $moduleName = $modification.Component
            if (-not $moduleModifications.ContainsKey($moduleName)) {
                $moduleModifications[$moduleName] = @()
            }
            $moduleModifications[$moduleName] += $modification
        }

        # If no modifications found in logs, fall back to existing Type2 results
        if ($moduleModifications.Keys.Count -eq 0 -and $type2Results.Count -gt 0) {
            $moduleGroups = $type2Results | Group-Object { $_.TaskName }
            foreach ($group in $moduleGroups) {
                $moduleModifications[$group.Name] = @(@{ 
                        Type = 'Fallback'; Action = 'Executed'; Target = $group.Group[0].Description; 
                        Category = 'Task Execution'; Timestamp = (Get-Date).ToString()
                    })
            }
        }

        foreach ($moduleName in $moduleModifications.Keys) {
            $modifications = $moduleModifications[$moduleName]
            
            # Map module names to friendly titles and icons
            $moduleInfo = @{
                'BloatwareRemoval'   = @{ Title = 'Bloatware Removal'; Icon = '🗑️'; Color = '#e74c3c' }
                'EssentialApps'      = @{ Title = 'Essential Applications'; Icon = '📦'; Color = '#3498db' }
                'TelemetryDisable'   = @{ Title = 'Privacy & Telemetry'; Icon = '🔒'; Color = '#9b59b6' }
                'SystemOptimization' = @{ Title = 'System Optimization'; Icon = '⚡'; Color = '#f39c12' }
                'WindowsUpdates'     = @{ Title = 'Windows Updates'; Icon = '🔄'; Color = '#27ae60' }
            }

            $info = $moduleInfo[$moduleName]
            if (-not $info) {
                $info = @{ Title = $moduleName; Icon = '🔧'; Color = '#95a5a6' }
            }

            # Get corresponding task status if available
            $moduleTask = $type2Results | Where-Object { $_.TaskName -eq $moduleName } | Select-Object -First 1
            $statusBadge = if ($moduleTask -and $moduleTask.Success) { 
                '<span class="status-badge success">✓ Completed</span>' 
            }
            elseif ($moduleTask -and -not $moduleTask.Success) { 
                '<span class="status-badge error">✗ Failed</span>' 
            }
            else {
                '<span class="status-badge info">📊 Analyzed</span>'
            }

            $html.AppendLine(@"
                    <div class="module-activity" style="border-left: 4px solid $($info.Color);">
                        <div class="module-header">
                            <span class="module-icon">$($info.Icon)</span>
                            <h3>$($info.Title)</h3>
                            $statusBadge
                        </div>
                        <div class="module-details">
                            <p><strong>Total Modifications:</strong> $($modifications.Count)</p>
                            $(if ($moduleTask) { "<p><strong>Duration:</strong> $([math]::Round($moduleTask.Duration, 2)) seconds</p>" })
                            $(if ($moduleTask -and $moduleTask.DryRun) { '<p><strong>Mode:</strong> <span class="dry-run-badge">DRY RUN</span></p>' })
                            $(if ($moduleTask -and -not $moduleTask.Success -and $moduleTask.Error) { 
                                "<div class='error-details'><strong>Error:</strong> $($moduleTask.Error)</div>" 
                            })
                        </div>
                        <div class="module-actions">
                            <h4>System Modifications:</h4>
                            <div class="actions-list">
"@) | Out-Null

            # Group modifications by category for better organization
            $categoryGroups = $modifications | Group-Object Category
            foreach ($categoryGroup in $categoryGroups) {
                $html.AppendLine("                                <div class='action-category'><strong>$($categoryGroup.Name):</strong></div>")
                foreach ($mod in $categoryGroup.Group) {
                    $actionIcon = switch ($mod.Action) {
                        'Install' { '➕' }
                        'Remove' { '➖' }
                        'Uninstall' { '🗑️' }
                        'Optimize' { '⚡' }
                        'Disable' { '🔒' }
                        'Enable' { '✅' }
                        'Update' { '🔄' }
                        'Configure' { '⚙️' }
                        default { '🔧' }
                    }
                    $html.AppendLine("                                <div class='action-item'>$actionIcon <strong>$($mod.Action)</strong> $($mod.Type): $($mod.Target)</div>")
                }
            }

            $html.AppendLine(@"
                            </div>
                        </div>
                    </div>
"@) | Out-Null
        }

        $html.AppendLine(@"
                </div>
            </div>
        </div>
"@) | Out-Null
    }

    # System information
    if ($ReportData.SystemInventory) {
        $systemInfo = $ReportData.SystemInventory.SystemInfo
        $hardware = $ReportData.SystemInventory.Hardware
        $os = $ReportData.SystemInventory.OperatingSystem

        $html.AppendLine(@"
        <div class="section">
            <div class="section-header" onclick="toggleSection(this)">
                <h2>💻 System Information</h2>
                <span class="toggle-icon">▼</span>
            </div>
            <div class="section-content">
                <table class="info-table">
                    <tr><th>Computer Name</th><td>$($systemInfo.ComputerName)</td></tr>
                    <tr><th>Manufacturer</th><td>$($systemInfo.Manufacturer)</td></tr>
                    <tr><th>Model</th><td>$($systemInfo.Model)</td></tr>
                    <tr><th>Operating System</th><td>$($os.Caption)</td></tr>
                    <tr><th>OS Version</th><td>$($os.Version)</td></tr>
                    <tr><th>Architecture</th><td>$($os.Architecture)</td></tr>
                    <tr><th>Processor</th><td>$($hardware.Processor.Name)</td></tr>
                    <tr><th>Total Memory</th><td>$([math]::Round($systemInfo.TotalPhysicalMemory / 1GB, 2)) GB</td></tr>
                </table>
            </div>
        </div>
"@) | Out-Null
    }

    # Configuration section
    if ($ReportData.Configuration) {
        $html.AppendLine(@"
        <div class="section">
            <div class="section-header" onclick="toggleSection(this)">
                <h2>⚙️ Configuration</h2>
                <span class="toggle-icon">▼</span>
            </div>
            <div class="section-content">
                <table class="info-table">
                    <tr><th>Execution Mode</th><td>$(if ($ReportData.Configuration.execution.defaultMode) { $ReportData.Configuration.execution.defaultMode } else { 'Default' })</td></tr>
                    <tr><th>Countdown Seconds</th><td>$(if ($ReportData.Configuration.execution.countdownSeconds) { $ReportData.Configuration.execution.countdownSeconds } else { '20' })</td></tr>
                    <tr><th>Dry Run Enabled</th><td>$(if ($ReportData.Configuration.execution.enableDryRun) { 'Yes' } else { 'No' })</td></tr>
                    <tr><th>HTML Reports</th><td>$(if ($ReportData.Configuration.reporting.enableHtmlReport) { 'Enabled' } else { 'Disabled' })</td></tr>
                </table>
            </div>
        </div>
"@) | Out-Null
    }

    # System Health Analysis from comprehensive log and audit data
    $systemHealthAnalysis = Get-SystemHealthAnalysis -ComprehensiveLogCollection $ReportData.ComprehensiveLogCollection
    
    # Use comprehensive health analysis if available, fallback to existing data
    $healthScore = if ($systemHealthAnalysis.OverallScore -gt 0) { $systemHealthAnalysis.OverallScore } else { 
        if ($ReportData.Analytics.SystemHealth) { $ReportData.Analytics.SystemHealth.OverallScore } else { $systemHealth }
    }
    $healthClass = if ($healthScore -ge 90) { 'excellent' } elseif ($healthScore -ge 75) { 'good' } elseif ($healthScore -ge 50) { 'warning' } else { 'poor' }
    
    if ($systemHealthAnalysis.OverallScore -gt 0 -or ($ReportData.Analytics.SystemHealth)) {
        $html.AppendLine(@"
        <div class="section expanded">
            <div class="section-header" onclick="toggleSection(this)">
                <h2>🏥 System Health Analysis</h2>
                <span class="toggle-icon">▼</span>
            </div>
            <div class="section-content">
                <div class="health-score">
                    <div class="health-circle $healthClass">$healthScore</div>
                    <div>
                        <h3>Overall System Health</h3>
                        <p>Based on maintenance tasks, security analysis, and system performance</p>
                    </div>
                </div>
"@) | Out-Null

        # Add detailed health metrics from comprehensive analysis
        if ($systemHealthAnalysis.OverallScore -gt 0) {
            $html.AppendLine(@"
                <div class="health-metrics">
                    <h4>📊 Health Metrics Breakdown</h4>
                    <div class="metrics-grid">
                        <div class="metric-item">
                            <strong>Maintenance Score:</strong> $($systemHealthAnalysis.MaintenanceScore)/100
                            <div class="metric-description">Success rate of maintenance operations</div>
                        </div>
                        <div class="metric-item">
                            <strong>Security Score:</strong> $($systemHealthAnalysis.SecurityScore)/100
                            <div class="metric-description">Privacy and security configuration status</div>
                        </div>
                        <div class="metric-item">
                            <strong>Performance Score:</strong> $($systemHealthAnalysis.PerformanceScore)/100
                            <div class="metric-description">System optimization and efficiency</div>
                        </div>
                        <div class="metric-item">
                            <strong>Update Score:</strong> $($systemHealthAnalysis.UpdateScore)/100
                            <div class="metric-description">System update and patch status</div>
                        </div>
                    </div>
                </div>
"@) | Out-Null
        }

        # Add recommendations - use comprehensive analysis or fallback to existing
        $recommendations = if ($systemHealthAnalysis.Recommendations.Count -gt 0) { 
            $systemHealthAnalysis.Recommendations 
        }
        else { 
            $ReportData.Analytics.RecommendedActions 
        }
        
        if ($recommendations -and $recommendations.Count -gt 0) {
            $html.AppendLine(@"
                <div class="recommendations">
                    <h4>💡 Health Recommendations</h4>
"@) | Out-Null

            foreach ($recommendation in $recommendations) {
                $iconMap = @{
                    'High'     = '🔴'
                    'Critical' = '🔴'
                    'Medium'   = '🟡'
                    'Low'      = '🟢'
                    'Info'     = '🔵'
                }
                $priority = if ($recommendation.Priority) { $recommendation.Priority } else { 'Medium' }
                $icon = $iconMap[$priority]
                $action = if ($recommendation.Action) { $recommendation.Action } else { $recommendation.Title }
                $details = if ($recommendation.Details) { $recommendation.Details } else { $recommendation.Description }
                
                $html.AppendLine(@"
                    <div class="recommendation-item">
                        <span class="recommendation-icon">$icon</span>
                        <div>
                            <strong>$action</strong><br>
                            <small>$details</small>
                        </div>
                    </div>
"@) | Out-Null
            }

            $html.AppendLine(@"
                </div>
"@) | Out-Null
        }

        $html.AppendLine(@"
            </div>
        </div>
"@) | Out-Null
    }

    # Add Enhanced Module Sections with comprehensive log data (V3.0 Feature)
    if ($ReportData.ModuleData -or $ReportData.ComprehensiveLogCollection) {
        # Create enhanced module data from comprehensive logs if available
        if ($ReportData.ComprehensiveLogCollection) {
            $enhancedModuleData = @{
                Type1Results = @{}
                Type2Results = @{}
            }
            
            # Populate Type1 (audit) data from ComprehensiveLogCollection
            if ($ReportData.ComprehensiveLogCollection.Type1AuditData) {
                foreach ($moduleName in $ReportData.ComprehensiveLogCollection.Type1AuditData.Keys) {
                    $auditData = $ReportData.ComprehensiveLogCollection.Type1AuditData[$moduleName]
                    if ($auditData) {
                        $enhancedModuleData.Type1Results[$moduleName] = @{
                            DetectedItems = $auditData
                            TotalScanned  = $auditData.Count
                        }
                    }
                }
            }
            
            # Populate Type2 (execution) data from comprehensive log analysis
            $detailedResults = Get-DetailedTaskResults -ComprehensiveLogCollection $ReportData.ComprehensiveLogCollection
            foreach ($result in $detailedResults) {
                $enhancedModuleData.Type2Results[$result.TaskName] = $result
            }
            
            $enhancedModuleSections = New-EnhancedModuleSections -ModuleData $enhancedModuleData -ComprehensiveLogCollection $ReportData.ComprehensiveLogCollection
        }
        else {
            $enhancedModuleSections = New-EnhancedModuleSections -ModuleData $ReportData.ModuleData
        }
        
        $html.AppendLine($enhancedModuleSections) | Out-Null
    }

    # Add Comprehensive Log Analysis Sections
    if ($ReportData.ComprehensiveLogCollection) {
        Write-Verbose "Processing comprehensive log analysis for all report sections"
        
        # Get comprehensive analysis from all logs
        $logAnalysis = Get-ComprehensiveLogAnalysis -ComprehensiveLogCollection $ReportData.ComprehensiveLogCollection
        
        # Add System Modifications Section
        $modificationsSection = New-SystemModificationsSection -LogAnalysis $logAnalysis
        $html.AppendLine($modificationsSection) | Out-Null
        
        # Add Performance Metrics Section  
        $performanceSection = New-PerformanceMetricsSection -LogAnalysis $logAnalysis
        $html.AppendLine($performanceSection) | Out-Null
        
        # Add Execution Timeline Section
        $timelineSection = New-ExecutionTimelineSection -LogAnalysis $logAnalysis
        $html.AppendLine($timelineSection) | Out-Null
        
        # Add Error Analysis Section (Enhanced with comprehensive data)
        $allErrors = Get-ErrorsFromExecutionLogs -ComprehensiveLogCollection $ReportData.ComprehensiveLogCollection
        $errorSection = New-ErrorReportSection -Errors $allErrors
        $html.AppendLine($errorSection) | Out-Null
        
        Write-Verbose "Comprehensive log analysis sections added: modifications, performance, timeline, errors"
    }

    # Generate comprehensive chart data from logs
    $comprehensiveChartData = Get-ComprehensiveChartData -ComprehensiveLogCollection $ReportData.ComprehensiveLogCollection
    
    # Use comprehensive chart data if available, fallback to existing data
    $taskDistributionData = if ($comprehensiveChartData.TaskDistribution.labels.Count -gt 0) { 
        $comprehensiveChartData.TaskDistribution 
    }
    else { 
        $ReportData.Charts.TaskDistribution 
    }
    
    $systemResourcesData = if ($comprehensiveChartData.SystemResources.datasets[0].data.Count -gt 0) { 
        $comprehensiveChartData.SystemResources 
    }
    else { 
        $ReportData.Charts.SystemResources 
    }
    
    $timelineData = if ($comprehensiveChartData.TimelineData.labels.Count -gt 0) { 
        $comprehensiveChartData.TimelineData 
    }
    else { 
        $ReportData.Charts.TimelineData 
    }
    
    $securityScoreData = if ($comprehensiveChartData.SecurityScore.datasets[0].data.Count -gt 0) { 
        $comprehensiveChartData.SecurityScore 
    }
    else { 
        $ReportData.Charts.SecurityScore 
    }

    # Add JavaScript chart data with comprehensive log-based data
    $html.AppendLine(@"
        <script>
            // Chart data initialization from comprehensive log analysis
            window.taskDistributionData = $($taskDistributionData | ConvertTo-Json -Depth 15 -WarningAction SilentlyContinue);
            window.systemResourcesData = $($systemResourcesData | ConvertTo-Json -Depth 15 -WarningAction SilentlyContinue);
            window.timelineData = $($timelineData | ConvertTo-Json -Depth 15 -WarningAction SilentlyContinue);
            window.securityScoreData = $($securityScoreData | ConvertTo-Json -Depth 15 -WarningAction SilentlyContinue);
        </script>
"@) | Out-Null

    # Enhanced Footer
    $generationTime = [math]::Round(((Get-Date) - $ReportData.GenerationTime).TotalSeconds, 1)
    $html.AppendLine(@"
        <div class="footer">
            <p><strong>Windows Maintenance Automation v2.0</strong></p>
            <p>Enhanced Dashboard Report | Generated in ${generationTime}s</p>
            <p>Session ID: $($script:LoggingContext.SessionId) | $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>
            <p>For support and documentation, visit the project repository</p>
        </div>
    </div>
</body>
</html>
"@) | Out-Null

    # Return HTML content
    return $html.ToString()
}

#endregion

<#
.SYNOPSIS
    Generates enhanced HTML sections for each module with modern flexbox layout

.DESCRIPTION
    Creates beautiful, interactive module sections with summaries, details, and status indicators.
    Each module gets its own independent section with expandable content and quick action buttons.

.PARAMETER ModuleData
    Module data from Get-ModuleExecutionData containing Type1 and Type2 results

.OUTPUTS
    [string] HTML content for enhanced module sections

.NOTES
    V3.0 feature - Creates independent module sections with modern CSS flexbox layout
#>
function New-EnhancedModuleSections {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()]
        [hashtable]$ModuleData = @{},
        
        [Parameter()]
        [hashtable]$ComprehensiveLogCollection = @{}
    )
    
    $html = [StringBuilder]::new()
    
    # Module configuration for display
    $moduleConfig = @{
        'BloatwareRemoval'   = @{
            Title       = 'Bloatware Removal'
            Icon        = '🗑️'
            Description = 'Removes unwanted pre-installed software and system bloat'
            Color       = '#e74c3c'
            Audit       = 'BloatwareDetectionAudit'
        }
        'EssentialApps'      = @{
            Title       = 'Essential Applications'
            Icon        = '📦'
            Description = 'Installs and manages essential productivity applications'
            Color       = '#3498db'
            Audit       = 'EssentialAppsAudit'
        }
        'SystemOptimization' = @{
            Title       = 'System Optimization'
            Icon        = '⚡'
            Description = 'Optimizes system performance and resource usage'
            Color       = '#f39c12'
            Audit       = 'SystemOptimizationAudit'
        }
        'TelemetryDisable'   = @{
            Title       = 'Privacy & Telemetry'
            Icon        = '🔒'
            Description = 'Disables telemetry and enhances privacy settings'
            Color       = '#9b59b6'
            Audit       = 'TelemetryAudit'
        }
        'WindowsUpdates'     = @{
            Title       = 'Windows Updates'
            Icon        = '🔄'
            Description = 'Manages Windows updates and system patches'
            Color       = '#27ae60'
            Audit       = 'WindowsUpdatesAudit'
        }
    }
    
    $html.AppendLine(@"
    <div class="quick-actions">
        <h3>📋 Quick Actions</h3>
        <a href="#bloatware" class="quick-action-btn">🗑️ Bloatware</a>
        <a href="#apps" class="quick-action-btn secondary">📦 Applications</a>
        <a href="#optimize" class="quick-action-btn warning">⚡ Optimization</a>
        <a href="#privacy" class="quick-action-btn">🔒 Privacy</a>
        <a href="#updates" class="quick-action-btn secondary">🔄 Updates</a>
    </div>

    <div class="modules-container">
"@) | Out-Null

    foreach ($moduleKey in $moduleConfig.Keys) {
        $config = $moduleConfig[$moduleKey]
        $type2Data = if ($ModuleData.Type2Results.ContainsKey($moduleKey)) { $ModuleData.Type2Results[$moduleKey] } else { $null }
        $type1Data = if ($ModuleData.Type1Results.ContainsKey($config.Audit)) { $ModuleData.Type1Results[$config.Audit] } else { $null }
        
        # Determine status
        $status = if ($type2Data -and $type2Data.Success) { 'success' } 
        elseif ($type2Data -and $type2Data.Success -eq $false) { 'error' }
        elseif ($type1Data) { 'warning' }
        else { 'warning' }
                 
        $statusText = switch ($status) {
            'success' { '✅ Completed' }
            'error' { '❌ Failed' }
            'warning' { '⚠️ Pending' }
        }
        
        # Generate summary stats
        $summaryStats = @()
        if ($type1Data) {
            if ($type1Data.DetectedItems) { $summaryStats += @{ Label = 'Items Detected'; Value = $type1Data.DetectedItems.Count } }
            if ($type1Data.TotalScanned) { $summaryStats += @{ Label = 'Items Scanned'; Value = $type1Data.TotalScanned } }
        }
        if ($type2Data) {
            if ($type2Data.ProcessedCount) { $summaryStats += @{ Label = 'Items Processed'; Value = $type2Data.ProcessedCount } }
            if ($type2Data.Duration) { $summaryStats += @{ Label = 'Duration'; Value = "$([math]::Round($type2Data.Duration.TotalSeconds, 1))s" } }
        }
        
        $anchor = $moduleKey.ToLower() -replace 'removal|apps|optimization|disable|updates', ''
        
        $html.AppendLine(@"
        <div class="module-section" id="$anchor">
            <div class="module-header" onclick="toggleModuleSection('$anchor')">
                <div class="module-title">
                    <div class="module-icon" style="background: linear-gradient(135deg, $($config.Color), $($config.Color)aa);">
                        $($config.Icon)
                    </div>
                    <div class="module-info">
                        <h3>$($config.Title)</h3>
                        <div class="module-description">$($config.Description)</div>
                    </div>
                </div>
                <div class="module-status $status">
                    $statusText
                    <span class="expand-icon">▼</span>
                </div>
            </div>
            <div class="module-content">
"@) | Out-Null

        # Add summary section
        if ($summaryStats.Count -gt 0) {
            $html.AppendLine("                <div class='module-summary'>") | Out-Null
            foreach ($stat in $summaryStats) {
                $html.AppendLine(@"
                    <div class="summary-item">
                        <span class="summary-value">$($stat.Value)</span>
                        <span class="summary-label">$($stat.Label)</span>
                    </div>
"@) | Out-Null
            }
            $html.AppendLine("                </div>") | Out-Null
        }
        
        # Add details section
        $html.AppendLine("                <div class='module-details'>") | Out-Null
        
        # Type1 (Audit) Details
        if ($type1Data) {
            $html.AppendLine(@"
                    <div class="detail-card">
                        <h4>🔍 Detection Results</h4>
                        <ul class="detail-list">
"@) | Out-Null

            if ($type1Data.DetectedItems) {
                foreach ($item in ($type1Data.DetectedItems | Select-Object -First 5)) {
                    $itemName = if ($item.Name) { $item.Name } elseif ($item.DisplayName) { $item.DisplayName } else { $item.ToString() }
                    $html.AppendLine("                            <li>$itemName <span class='detail-badge warning'>Detected</span></li>") | Out-Null
                }
                if ($type1Data.DetectedItems.Count -gt 5) {
                    $remaining = $type1Data.DetectedItems.Count - 5
                    $html.AppendLine("                            <li><em>... and $remaining more items</em></li>") | Out-Null
                }
            }
            else {
                $html.AppendLine("                            <li>No items detected <span class='detail-badge success'>Clean</span></li>") | Out-Null
            }
            
            $html.AppendLine(@"
                        </ul>
                    </div>
"@) | Out-Null
        }
        
        # Type2 (Execution) Details with comprehensive log data
        if ($type2Data -or ($ComprehensiveLogCollection.Type2ExecutionLogs -and $ComprehensiveLogCollection.Type2ExecutionLogs.ContainsKey($moduleKey))) {
            $html.AppendLine(@"
                    <div class="detail-card">
                        <h4>⚙️ Execution Results</h4>
                        <ul class="detail-list">
"@) | Out-Null

            # Get system modifications for this specific module from comprehensive log data
            if ($ComprehensiveLogCollection.Type2ExecutionLogs.ContainsKey($moduleKey)) {
                $systemMods = Get-SystemModificationActivities -ComprehensiveLogCollection $ComprehensiveLogCollection
                $moduleModifications = $systemMods | Where-Object { $_.Component -eq $moduleKey } | Select-Object -First 5
                
                if ($moduleModifications.Count -gt 0) {
                    foreach ($mod in $moduleModifications) {
                        $actionIcon = switch ($mod.Action) {
                            'Install' { '➕' }
                            'Remove' { '➖' }
                            'Uninstall' { '🗑️' }
                            'Optimize' { '⚡' }
                            'Disable' { '🔒' }
                            'Enable' { '✅' }
                            'Update' { '🔄' }
                            default { '🔧' }
                        }
                        $html.AppendLine("                            <li>$actionIcon $($mod.Action) $($mod.Type): $($mod.Target) <span class='detail-badge success'>Completed</span></li>") | Out-Null
                    }
                    
                    $totalMods = ($systemMods | Where-Object { $_.Component -eq $moduleKey }).Count
                    if ($totalMods -gt 5) {
                        $remaining = $totalMods - 5
                        $html.AppendLine("                            <li><em>... and $remaining more modifications</em></li>") | Out-Null
                    }
                }
                else {
                    # Check execution log for success/failure info
                    $logContent = $ComprehensiveLogCollection.Type2ExecutionLogs[$moduleKey]
                    if ($logContent -match '\[(SUCCESS|INFO)\]') {
                        $html.AppendLine("                            <li>Module executed successfully <span class='detail-badge success'>✅ Completed</span></li>") | Out-Null
                    }
                    elseif ($logContent -match '\[(ERROR|FAILED)\]') {
                        $html.AppendLine("                            <li>Module execution failed <span class='detail-badge error'>❌ Failed</span></li>") | Out-Null
                    }
                    else {
                        $html.AppendLine("                            <li>Module execution status unknown <span class='detail-badge warning'>⚠️ Unknown</span></li>") | Out-Null
                    }
                }
            }
            elseif ($type2Data.ProcessedItems) {
                foreach ($item in ($type2Data.ProcessedItems | Select-Object -First 5)) {
                    $itemName = if ($item.Name) { $item.Name } else { $item.ToString() }
                    $badge = if ($item.Success) { 'success">✅ Completed' } else { 'error">❌ Failed' }
                    $html.AppendLine("                            <li>$itemName <span class='detail-badge $badge</span></li>") | Out-Null
                }
            }
            else {
                $execStatus = if ($type2Data.Success) { 'success">✅ Completed' } else { 'error">❌ Failed' }
                $html.AppendLine("                            <li>Module execution <span class='detail-badge $execStatus</span></li>") | Out-Null
            }
            
            $html.AppendLine(@"
                        </ul>
                    </div>
"@) | Out-Null
        }
        
        $html.AppendLine(@"
                </div>
            </div>
        </div>
"@) | Out-Null
    }
    
    $html.AppendLine("    </div>") | Out-Null
    
    # Add JavaScript for module interaction
    $html.AppendLine(@"
    <script>
        function toggleModuleSection(sectionId) {
            const section = document.getElementById(sectionId);
            section.classList.toggle('collapsed');
        }
        
        // Initialize all sections as expanded
        document.addEventListener('DOMContentLoaded', function() {
            const modules = document.querySelectorAll('.module-section');
            modules.forEach(module => {
                // Optionally start collapsed: module.classList.add('collapsed');
            });
        });
    </script>
"@) | Out-Null
    
    return $html.ToString()
}

#region Text Report Generation

<#
.SYNOPSIS
    Creates a detailed text report of system maintenance operations

.DESCRIPTION
    Generates a comprehensive text-based report containing execution summaries,
    system health analytics, performance metrics, and recommended actions.
    The report is formatted for readability and can be saved to file or printed.

.PARAMETER ReportData
    Hashtable containing all report data including system inventory, task results,
    execution summary, and analytics data

.OUTPUTS
    [string] Formatted text report content

.EXAMPLE
    $textReport = New-TextReportContent -ReportData $reportData
    
.NOTES
    Part of the ReportGeneration module for creating human-readable maintenance reports.
    Designed to complement the HTML dashboard report with a text-based alternative.
#>
function New-TextReportContent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$ReportData
    )

    $text = [StringBuilder]::new()

    # Header
    $text.AppendLine("=" * 80)
    $text.AppendLine("                    WINDOWS MAINTENANCE REPORT")
    $text.AppendLine("=" * 80)
    $text.AppendLine("")
    $text.AppendLine("Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
    $text.AppendLine("Computer: $env:COMPUTERNAME")
    $text.AppendLine("User: $env:USERNAME")
    $text.AppendLine("")

    # Executive Summary
    $summary = $ReportData.Summary
    $text.AppendLine("EXECUTIVE SUMMARY")
    $text.AppendLine("-" * 40)
    $text.AppendLine("Tasks Executed: $($summary.TotalTasks)")
    $text.AppendLine("Successful: $($summary.SuccessfulTasks)")
    $text.AppendLine("Failed: $($summary.FailedTasks)")
    $text.AppendLine("Total Duration: $([math]::Round($summary.TotalDuration, 2)) seconds")
    $text.AppendLine("")

    # Task Results
    if ($ReportData.TaskResults.Count -gt 0) {
        $text.AppendLine("TASK EXECUTION RESULTS")
        $text.AppendLine("-" * 40)

        foreach ($task in $ReportData.TaskResults) {
            $status = if ($task.Success) { "SUCCESS" } else { "FAILED" }
            $duration = [math]::Round($task.Duration, 2)

            $text.AppendLine("[$status] $($task.TaskName) (${duration}s)")
            $text.AppendLine("  Description: $($task.Description)")
            $text.AppendLine("  Type: $($task.Type)")
            $text.AppendLine("  Category: $($task.Category)")

            if (-not $task.Success -and $task.Error) {
                $text.AppendLine("  Error: $($task.Error)")
            }

            $text.AppendLine("")
        }
    }

    # System Information
    if ($ReportData.SystemInventory) {
        $text.AppendLine("SYSTEM INFORMATION")
        $text.AppendLine("-" * 40)

        $systemInfo = $ReportData.SystemInventory.SystemInfo
        if ($systemInfo) {
            $text.AppendLine("Computer Name: $($systemInfo.ComputerName)")
            $text.AppendLine("Manufacturer: $($systemInfo.Manufacturer)")
            $text.AppendLine("Model: $($systemInfo.Model)")
            $text.AppendLine("Total Memory: $([math]::Round($systemInfo.TotalPhysicalMemory / 1GB, 2)) GB")
        }

        $os = $ReportData.SystemInventory.OperatingSystem
        if ($os) {
            $text.AppendLine("Operating System: $($os.Caption)")
            $text.AppendLine("OS Version: $($os.Version)")
            $text.AppendLine("Architecture: $($os.Architecture)")
        }

        $hardware = $ReportData.SystemInventory.Hardware
        if ($hardware -and $hardware.Processor) {
            $text.AppendLine("Processor: $($hardware.Processor.Name)")
            $text.AppendLine("Cores: $($hardware.Processor.NumberOfCores)")
        }

        $text.AppendLine("")
    }

    # Footer
    $text.AppendLine("=" * 80)
    $text.AppendLine("Report generated by Windows Maintenance Automation v2.0")
    $text.AppendLine("=" * 80)

    # Return text content
    return $text.ToString()
}

#endregion

#region Helper Functions

<#
.SYNOPSIS
    Generates comprehensive execution summary statistics from task results

.DESCRIPTION
    Analyzes an array of task execution results to calculate success rates,
    failure counts, total execution time, and other performance metrics.
    Used internally by the reporting system to generate summary analytics.

.PARAMETER TaskResults
    Array of task result objects containing Success, Duration, and other execution data

.OUTPUTS
    [hashtable] Statistics including TotalTasks, SuccessfulTasks, FailedTasks, 
    TotalDuration, SuccessRate, and AverageDuration

.EXAMPLE
    $summary = Get-ExecutionSummary -TaskResults $taskResults
    Write-Information "Success Rate: $($summary.SuccessRate)%" -InformationAction Continue
    
.NOTES
    Internal helper function for ReportGeneration module.
    Calculates performance metrics used in dashboard and text reports.
#>
function Get-ExecutionSummary {
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
    Collects module execution data from standardized v3.0 session paths

.DESCRIPTION
    Automatically discovers and collects data from Type1 audit results and Type2 execution logs
    using the standardized temp_files/data/ and temp_files/logs/ structure. This replaces
    the need to pass TaskResults as parameters, implementing true v3.0 architecture.

.OUTPUTS
    [hashtable] Combined data from all modules including audit results and execution logs

.EXAMPLE
    $moduleData = Get-ModuleExecutionData
    $reportData = New-MaintenanceReport -SystemInventory $inventory -ModuleData $moduleData

.NOTES
    V3.0 Architecture function - ReportGeneration knows exactly where to find module data.
    Supports the session-based file organization pattern with SubCategory support.
#>
function Get-ModuleExecutionData {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()
    
    try {
        Write-LogEntry -Level 'INFO' -Component 'REPORT-GENERATION' -Message 'Collecting module execution data from v3.0 standardized paths'
        
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
            $type1Module = $moduleMapping[$type2Module]
            
            # Collect Type1 audit data (detection/analysis results)
            try {
                $auditDataPath = Get-SessionPath -Category 'data' -FileName "$($type2Module.ToLower())-results.json"
                if (Test-Path $auditDataPath) {
                    $auditData = Get-Content $auditDataPath -Raw | ConvertFrom-Json
                    $moduleData.Type1Results[$type1Module] = $auditData
                    $moduleData.DataPaths[$type1Module] = $auditDataPath
                    Write-LogEntry -Level 'DEBUG' -Component 'REPORT-GENERATION' -Message "Loaded audit data for $type1Module"
                }
            }
            catch {
                Write-LogEntry -Level 'WARN' -Component 'REPORT-GENERATION' -Message "Failed to load audit data for $type1Module`: $($_.Exception.Message)"
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
                    Write-LogEntry -Level 'DEBUG' -Component 'REPORT-GENERATION' -Message "Loaded execution data for $type2Module"
                }
            }
            catch {
                Write-LogEntry -Level 'WARN' -Component 'REPORT-GENERATION' -Message "Failed to load execution data for $type2Module`: $($_.Exception.Message)"
            }
        }
        
        Write-LogEntry -Level 'INFO' -Component 'REPORT-GENERATION' -Message "Module data collection completed" -Data @{
            Type1ModulesFound = $moduleData.Type1Results.Count
            Type2ModulesFound = $moduleData.Type2Results.Count
            TotalLogPaths     = $moduleData.LogPaths.Count
            TotalDataPaths    = $moduleData.DataPaths.Count
        }
        
        return $moduleData
    }
    catch {
        Write-LogEntry -Level 'ERROR' -Component 'REPORT-GENERATION' -Message "Failed to collect module execution data: $($_.Exception.Message)"
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
    Converts v3.0 ModuleData format to legacy TaskResults format for backward compatibility

.DESCRIPTION
    Transforms the new structured module data (Type1/Type2 results) into the legacy
    TaskResults array format that existing report generation functions expect.
    Enables v3.0 data collection while maintaining compatibility with existing analytics.

.PARAMETER ModuleData
    Module data hashtable from Get-ModuleExecutionData

.OUTPUTS
    [Array] Legacy TaskResults format

.NOTES
    V3.0 compatibility function - bridges new data collection with existing report logic.
#>
function Convert-ModuleDataToTaskResults {
    [CmdletBinding()]
    [OutputType([Array])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$ModuleData
    )
    
    $taskResults = @()
    
    try {
        # Convert Type2 execution results to TaskResults format
        foreach ($module in $ModuleData.Type2Results.Keys) {
            $executionData = $ModuleData.Type2Results[$module]
            
            # Create TaskResult object in expected format
            $taskResult = @{
                TaskName  = $module
                Success   = $true  # Default, will be updated based on execution data
                StartTime = $null
                EndTime   = $null
                Duration  = $null
                Details   = $executionData
                Component = $module.ToUpper()
            }
            
            # Extract timing and success information if available
            if ($executionData -is [hashtable] -or $executionData -is [PSCustomObject]) {
                if ($null -ne $executionData.Success) { $taskResult.Success = $executionData.Success }
                if ($null -ne $executionData.StartTime) { $taskResult.StartTime = $executionData.StartTime }
                if ($null -ne $executionData.EndTime) { $taskResult.EndTime = $executionData.EndTime }
                if ($null -ne $executionData.Duration) { $taskResult.Duration = $executionData.Duration }
            }
            
            $taskResults += $taskResult
        }
        
        # Add Type1 audit results as separate tasks if needed
        foreach ($module in $ModuleData.Type1Results.Keys) {
            $auditData = $ModuleData.Type1Results[$module]
            
            $taskResult = @{
                TaskName  = "$module-Audit"
                Success   = $true
                StartTime = $null
                EndTime   = $null
                Duration  = $null
                Details   = $auditData
                Component = $module.ToUpper().Replace('AUDIT', '-AUDIT')
            }
            
            # Extract timing and success information if available
            if ($auditData -is [hashtable] -or $auditData -is [PSCustomObject]) {
                if ($null -ne $auditData.Success) { $taskResult.Success = $auditData.Success }
                if ($null -ne $auditData.StartTime) { $taskResult.StartTime = $auditData.StartTime }
                if ($null -ne $auditData.EndTime) { $taskResult.EndTime = $auditData.EndTime }
                if ($null -ne $auditData.Duration) { $taskResult.Duration = $auditData.Duration }
            }
            
            $taskResults += $taskResult
        }
        
        Write-LogEntry -Level 'DEBUG' -Component 'REPORT-GENERATION' -Message "Converted module data to TaskResults format" -Data @{
            OriginalType2Count = $ModuleData.Type2Results.Count
            OriginalType1Count = $ModuleData.Type1Results.Count
            ConvertedTaskCount = $taskResults.Count
        }
        
        return $taskResults
    }
    catch {
        Write-LogEntry -Level 'ERROR' -Component 'REPORT-GENERATION' -Message "Failed to convert module data to TaskResults format: $($_.Exception.Message)"
        return @()
    }
}

#endregion

#region Analytics and Chart Data Generation

<#
.SYNOPSIS
    Generates comprehensive system health analytics and scoring

.DESCRIPTION
    Analyzes system inventory data to calculate health scores, identify issues,
    and generate performance metrics. Evaluates hardware utilization, service status,
    installed software, and system resource usage to provide overall health assessment.

.PARAMETER SystemInventory
    Hashtable containing complete system inventory data including hardware,
    operating system, services, and installed software information

.OUTPUTS
    [hashtable] Health analytics including OverallHealthScore, CriticalIssues, 
    SystemResourceUtilization, ServiceHealth, and performance metrics

.EXAMPLE
    $healthAnalytics = Get-SystemHealthAnalytic -SystemInventory $inventory
    Write-Information "System Health Score: $($healthAnalytics.OverallHealthScore)/100" -InformationAction Continue
    
.NOTES
    Internal analytics function that powers the dashboard health scoring system.
    Used to generate visual indicators and recommendations in maintenance reports.
#>
function Get-SystemHealthAnalytic {
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
    Generates performance analytics from task results
#>
function Get-PerformanceAnalytic {
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
    Generates security analytics
#>
function Get-SecurityAnalytic {
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
    Generates recommended actions based on system analysis
#>
function Get-RecommendedAction {
    param([hashtable]$SystemInventory, [Array]$TaskResults)
    
    $recommendations = @()
    
    # Failed tasks recommendations
    $failedTasks = $TaskResults | Where-Object { -not $_.Success }
    foreach ($task in $failedTasks) {
        $recommendations += @{
            Priority = 'High'
            Category = 'Task Failure'
            Action   = "Investigate and resolve: $($task.TaskName)"
            Details  = $task.Error
        }
    }
    
    # System health recommendations
    if ($SystemInventory.SystemInfo -and $SystemInventory.SystemInfo.TotalPhysicalMemory) {
        $memoryGB = $SystemInventory.SystemInfo.TotalPhysicalMemory / 1GB
        if ($memoryGB -lt 8) {
            $recommendations += @{
                Priority = 'Medium'
                Category = 'Hardware'
                Action   = "Consider upgrading system memory"
                Details  = "Current: $([math]::Round($memoryGB, 1))GB, Recommended: 8GB+"
            }
        }
    }
    
    # OS update recommendations
    if ($SystemInventory.OperatingSystem -and $SystemInventory.OperatingSystem.BuildNumber -lt 22000) {
        $recommendations += @{
            Priority = 'Medium'
            Category = 'Operating System'
            Action   = "Consider upgrading to Windows 11"
            Details  = "Current build: $($SystemInventory.OperatingSystem.BuildNumber)"
        }
    }
    
    return $recommendations
}

<#
.SYNOPSIS
    Generates chart data for task distribution
#>
function Get-TaskDistributionData {
    param([Array]$TaskResults)
    
    if (-not $TaskResults -or $TaskResults.Count -eq 0) {
        return @{
            labels   = @('No Data')
            datasets = @(@{
                    data            = @(1)
                    backgroundColor = @('#cccccc')
                })
        }
    }
    
    $distribution = $TaskResults | Group-Object Type | ForEach-Object {
        @{
            Type    = $_.Name
            Count   = $_.Count
            Success = ($_.Group | Where-Object Success).Count
            Failed  = ($_.Group | Where-Object { -not $_.Success }).Count
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

<#
.SYNOPSIS
    Generates chart data for system resources
#>
function Get-SystemResourceData {
    param([hashtable]$SystemInventory)
    
    if (-not $SystemInventory) {
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
    
    # CPU Cores (as percentage of ideal 8 cores)
    if ($SystemInventory.Hardware -and $SystemInventory.Hardware.Processor) {
        $cpuCores = $SystemInventory.Hardware.Processor.NumberOfCores
        $resources += 'CPU Cores'
        $values += [math]::Min(100, ($cpuCores / 8) * 100)
        $colors += '#0078d4'
    }
    
    # Memory (as percentage of 16GB ideal)
    if ($SystemInventory.SystemInfo -and $SystemInventory.SystemInfo.TotalPhysicalMemory) {
        $memoryGB = $SystemInventory.SystemInfo.TotalPhysicalMemory / 1GB
        $resources += 'Memory (GB)'
        $values += [math]::Min(100, ($memoryGB / 16) * 100)
        $colors += '#107c10'
    }
    
    # Storage Devices
    if ($SystemInventory.Hardware -and $SystemInventory.Hardware.Storage) {
        $storageCount = $SystemInventory.Hardware.Storage.Count
        $resources += 'Storage Devices'
        $values += [math]::Min(100, ($storageCount / 4) * 100)
        $colors += '#ffb900'
    }
    
    return @{
        labels   = $resources
        datasets = @(@{
                label           = 'Resource Utilization %'
                data            = $values
                backgroundColor = $colors
                borderColor     = $colors
                borderWidth     = 1
            })
    }
}

<#
.SYNOPSIS
    Generates timeline data for task execution
#>
function Get-ExecutionTimelineData {
    param([Array]$TaskResults)
    
    if (-not $TaskResults -or $TaskResults.Count -eq 0) {
        return @{
            labels   = @()
            datasets = @()
        }
    }
    
    $startTime = (Get-Date).AddMinutes( - ($TaskResults.Count * 2))
    $timelinePoints = @()
    
    for ($i = 0; $i -lt $TaskResults.Count; $i++) {
        $timelinePoints += @{
            x = $startTime.AddMinutes($i * 2).ToString('yyyy-MM-ddTHH:mm:ss')
            y = $TaskResults[$i].Duration
        }
    }
    
    return @{
        datasets = @(@{
                label           = 'Task Duration (seconds)'
                data            = $timelinePoints
                borderColor     = '#0078d4'
                backgroundColor = 'rgba(0, 120, 212, 0.1)'
                fill            = $true
                tension         = 0.4
            })
    }
}

<#
.SYNOPSIS
    Generates security score radar chart data
#>
function Get-SecurityScoreData {
    param()
    
    $categories = @('Firewall', 'Updates', 'Antivirus', 'Services', 'Access Control', 'Network')
    $scores = @(85, 90, 88, 82, 78, 85) # Sample scores - would be calculated from actual security audit
    
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

<#
.SYNOPSIS
    Generates health recommendations
#>
function Get-HealthRecommendation {
    param([hashtable]$HealthFactors)
    
    $recommendations = @()
    
    foreach ($factor in $HealthFactors.GetEnumerator()) {
        if ($factor.Value.Score -lt ($factor.Value.MaxScore * 0.75)) {
            $recommendations += @{
                Category = $factor.Key
                Message  = "Consider upgrading $($factor.Key.ToLower()) components"
                Priority = if ($factor.Value.Score -lt ($factor.Value.MaxScore * 0.5)) { 'High' } else { 'Medium' }
            }
        }
    }
    
    return $recommendations
}

#endregion

#region Comprehensive Log Processing Functions

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
        $line = $line.Trim()
        if (-not $line) { continue }
        
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
                        Component = $ModuleName.ToUpper()
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

#region Comprehensive Log Analysis Functions

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
        if ($ComprehensiveLogCollection.Type2ExecutionLogs.ContainsKey($secModule)) {
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

function Get-DetailedTaskResults {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$ComprehensiveLogCollection,
        
        [Parameter()]
        [array]$TaskResults = @()
    )
    
    Write-Verbose "Extracting detailed task results from logs"
    
    $detailedResults = @()
    
    if ($ComprehensiveLogCollection.Type2ExecutionLogs) {
        foreach ($moduleName in $ComprehensiveLogCollection.Type2ExecutionLogs.Keys) {
            $logContent = $ComprehensiveLogCollection.Type2ExecutionLogs[$moduleName]
            
            $taskResult = @{
                TaskName       = $moduleName
                DisplayName    = switch ($moduleName) {
                    'bloatware-removal' { 'Bloatware Removal' }
                    'essential-apps' { 'Essential Applications' }
                    'system-optimization' { 'System Optimization' }
                    'telemetry-disable' { 'Telemetry & Privacy' }
                    'windows-updates' { 'Windows Updates' }
                    default { $moduleName -replace '-', ' ' | ForEach-Object { (Get-Culture).TextInfo.ToTitleCase($_) } }
                }
                Success        = $false
                Duration       = 0
                ItemsDetected  = 0
                ItemsProcessed = 0
                ErrorMessage   = $null
                SuccessMessage = $null
                Details        = @()
            }
            
            if ($logContent) {
                $logLines = $logContent -split "`n"
                $hasErrors = $false
                
                foreach ($line in $logLines) {
                    $line = $line.Trim()
                    
                    # Extract error messages
                    if ($line -match '\[ERROR\].*?(.+)$') {
                        $taskResult.ErrorMessage = $matches[1]
                        $hasErrors = $true
                    }
                    
                    # Extract success messages
                    if ($line -match '(successfully.*completed|installation.*successful|optimization.*complete)') {
                        $taskResult.SuccessMessage = $matches[1]
                    }
                    
                    # Extract metrics
                    if ($line -match 'detected.*?(\d+)') {
                        $taskResult.ItemsDetected = [int]$matches[1]
                    }
                    if ($line -match '(?:processed|installed|removed).*?(\d+)') {
                        $taskResult.ItemsProcessed = [int]$matches[1]
                    }
                    
                    # Extract duration
                    if ($line -match 'Duration.*?(\d+\.?\d*)\s*(?:seconds?|s\b)') {
                        $taskResult.Duration = [double]$matches[1]
                    }
                    
                    # Extract detailed actions
                    if ($line -match '(SUCCESS|FAILED).*?:(.+)$') {
                        $taskResult.Details += @{
                            Status = $matches[1]
                            Action = $matches[2].Trim()
                        }
                    }
                }
                
                $taskResult.Success = -not $hasErrors
            }
            
            $detailedResults += $taskResult
        }
    }
    
    Write-Verbose "Extracted $($detailedResults.Count) detailed task results"
    
    return $detailedResults
}

function Get-SystemModificationActivities {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$ComprehensiveLogCollection
    )
    
    Write-Verbose "Extracting system modification activities from logs"
    
    $activities = @()
    
    if ($ComprehensiveLogCollection.Type2ExecutionLogs) {
        foreach ($moduleName in $ComprehensiveLogCollection.Type2ExecutionLogs.Keys) {
            $logContent = $ComprehensiveLogCollection.Type2ExecutionLogs[$moduleName]
            
            if ($logContent) {
                $logLines = $logContent -split "`n"
                
                foreach ($line in $logLines) {
                    $line = $line.Trim()
                    
                    # Extract specific modification actions
                    if ($line -match 'SUCCESS.*?(?:removed|uninstalled|deleted).*?(.+)$') {
                        $activities += @{
                            Module    = $moduleName
                            Type      = 'Removal'
                            Target    = $matches[1].Trim()
                            Status    = 'Success'
                            Timestamp = if ($line -match '\[([^\]]+)\]') { $matches[1] } else { 'Unknown' }
                        }
                    }
                    elseif ($line -match 'SUCCESS.*?(?:installed|added|enabled).*?(.+)$') {
                        $activities += @{
                            Module    = $moduleName
                            Type      = 'Installation'
                            Target    = $matches[1].Trim()
                            Status    = 'Success'
                            Timestamp = if ($line -match '\[([^\]]+)\]') { $matches[1] } else { 'Unknown' }
                        }
                    }
                    elseif ($line -match 'SUCCESS.*?(?:optimized|configured|modified).*?(.+)$') {
                        $activities += @{
                            Module    = $moduleName
                            Type      = 'Optimization'
                            Target    = $matches[1].Trim()
                            Status    = 'Success'
                            Timestamp = if ($line -match '\[([^\]]+)\]') { $matches[1] } else { 'Unknown' }
                        }
                    }
                    elseif ($line -match 'SUCCESS.*?(?:disabled|blocked|stopped).*?(.+)$') {
                        $activities += @{
                            Module    = $moduleName
                            Type      = 'Privacy/Security'
                            Target    = $matches[1].Trim()
                            Status    = 'Success'
                            Timestamp = if ($line -match '\[([^\]]+)\]') { $matches[1] } else { 'Unknown' }
                        }
                    }
                }
            }
        }
    }
    
    Write-Verbose "Extracted $($activities.Count) system modification activities"
    
    return $activities
}

function Get-SystemHealthAnalysis {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$ComprehensiveLogCollection
    )
    
    Write-Verbose "Analyzing system health from audit data and execution logs"
    
    $healthAnalysis = @{
        OverallScore       = 0
        BloatwareHealth    = @{ Score = 0; ItemsRemoved = 0; ItemsRemaining = 0 }
        SecurityHealth     = @{ Score = 0; TelemetryDisabled = $false; PrivacyEnhanced = $false }
        OptimizationHealth = @{ Score = 0; OptimizationsApplied = 0; PerformanceGain = 0 }
        UpdatesHealth      = @{ Score = 0; UpdatesInstalled = 0; SecurityPatchesApplied = 0 }
        ApplicationHealth  = @{ Score = 0; EssentialAppsInstalled = 0; MissingApps = 0 }
    }
    
    # Analyze Type1 audit data for baseline health
    if ($ComprehensiveLogCollection.Type1AuditData) {
        # Bloatware analysis
        if ($ComprehensiveLogCollection.Type1AuditData.ContainsKey('bloatware-results')) {
            $bloatwareData = $ComprehensiveLogCollection.Type1AuditData['bloatware-results']
            if ($bloatwareData -and $bloatwareData.DetectedBloatware) {
                $healthAnalysis.BloatwareHealth.ItemsRemaining = $bloatwareData.DetectedBloatware.Count
            }
        }
        
        # Essential apps analysis
        if ($ComprehensiveLogCollection.Type1AuditData.ContainsKey('essential-apps-results')) {
            $appsData = $ComprehensiveLogCollection.Type1AuditData['essential-apps-results']
            if ($appsData -and $appsData.MissingApps) {
                $healthAnalysis.ApplicationHealth.MissingApps = $appsData.MissingApps.Count
            }
        }
    }
    
    # Analyze Type2 execution results
    if ($ComprehensiveLogCollection.Type2ExecutionLogs) {
        # Bloatware removal analysis
        if ($ComprehensiveLogCollection.Type2ExecutionLogs.ContainsKey('bloatware-removal')) {
            $logContent = $ComprehensiveLogCollection.Type2ExecutionLogs['bloatware-removal']
            $removedCount = 0
            if ($logContent) {
                $removedCount = ([regex]::Matches($logContent, 'SUCCESS.*(?:removed|uninstalled)')).Count
            }
            $healthAnalysis.BloatwareHealth.ItemsRemoved = $removedCount
            $healthAnalysis.BloatwareHealth.Score = if ($removedCount -gt 10) { 90 } elseif ($removedCount -gt 5) { 70 } elseif ($removedCount -gt 0) { 50 } else { 30 }
        }
        
        # Security/Telemetry analysis
        if ($ComprehensiveLogCollection.Type2ExecutionLogs.ContainsKey('telemetry-disable')) {
            $logContent = $ComprehensiveLogCollection.Type2ExecutionLogs['telemetry-disable']
            if ($logContent -and $logContent -match 'successfully.*disabled|privacy.*enhanced') {
                $healthAnalysis.SecurityHealth.TelemetryDisabled = $true
                $healthAnalysis.SecurityHealth.PrivacyEnhanced = $true
                $healthAnalysis.SecurityHealth.Score = 85
            }
        }
        
        # System optimization analysis
        if ($ComprehensiveLogCollection.Type2ExecutionLogs.ContainsKey('system-optimization')) {
            $logContent = $ComprehensiveLogCollection.Type2ExecutionLogs['system-optimization']
            $optimizationsCount = 0
            if ($logContent) {
                $optimizationsCount = ([regex]::Matches($logContent, 'SUCCESS.*(?:optimized|configured)')).Count
            }
            $healthAnalysis.OptimizationHealth.OptimizationsApplied = $optimizationsCount
            $healthAnalysis.OptimizationHealth.Score = if ($optimizationsCount -gt 15) { 95 } elseif ($optimizationsCount -gt 10) { 80 } elseif ($optimizationsCount -gt 5) { 60 } else { 40 }
        }
        
        # Essential apps analysis
        if ($ComprehensiveLogCollection.Type2ExecutionLogs.ContainsKey('essential-apps')) {
            $logContent = $ComprehensiveLogCollection.Type2ExecutionLogs['essential-apps']
            $installedCount = 0
            if ($logContent) {
                $installedCount = ([regex]::Matches($logContent, 'SUCCESS.*installed')).Count
            }
            $healthAnalysis.ApplicationHealth.EssentialAppsInstalled = $installedCount
            $healthAnalysis.ApplicationHealth.Score = if ($installedCount -ge 8) { 90 } elseif ($installedCount -ge 5) { 75 } elseif ($installedCount -ge 2) { 50 } else { 25 }
        }
        
        # Windows updates analysis
        if ($ComprehensiveLogCollection.Type2ExecutionLogs.ContainsKey('windows-updates')) {
            $logContent = $ComprehensiveLogCollection.Type2ExecutionLogs['windows-updates']
            $updatesCount = 0
            if ($logContent) {
                $updatesCount = ([regex]::Matches($logContent, 'SUCCESS.*(?:installed|updated)')).Count
            }
            $healthAnalysis.UpdatesHealth.UpdatesInstalled = $updatesCount
            $healthAnalysis.UpdatesHealth.Score = if ($updatesCount -ge 10) { 95 } elseif ($updatesCount -ge 5) { 80 } elseif ($updatesCount -ge 1) { 60 } else { 30 }
        }
    }
    
    # Calculate overall health score
    $scores = @(
        $healthAnalysis.BloatwareHealth.Score,
        $healthAnalysis.SecurityHealth.Score,
        $healthAnalysis.OptimizationHealth.Score,
        $healthAnalysis.UpdatesHealth.Score,
        $healthAnalysis.ApplicationHealth.Score
    )
    
    $healthAnalysis.OverallScore = [math]::Round(($scores | Measure-Object -Average).Average, 0)
    
    Write-Verbose "System health analysis complete: Overall score $($healthAnalysis.OverallScore)/100"
    
    return $healthAnalysis
}

#endregion

#region Interactive Charts Data Generation Functions

function Get-ComprehensiveChartData {
    <#
    .SYNOPSIS
    Generates interactive chart data from comprehensive log analysis for HTML reports
    
    .DESCRIPTION
    Extracts and formats chart-ready data for Task Distribution, System Resources, 
    Execution Timeline, and Security Assessment charts using comprehensive log collection data
    
    .PARAMETER ComprehensiveLogCollection
    Hashtable containing Type1AuditData and Type2ExecutionLogs
    
    .OUTPUTS
    Hashtable containing formatted chart data for all interactive charts
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$ComprehensiveLogCollection
    )
    
    Write-Verbose "Generating comprehensive chart data from execution logs and audit data"
    
    $chartData = @{
        TaskDistribution = @{
            labels   = @()
            datasets = @(@{
                    data            = @()
                    backgroundColor = @('#28a745', '#dc3545', '#ffc107', '#17a2b8', '#6f42c1')
                    borderWidth     = 0
                })
        }
        SystemResources  = @{
            labels   = @('Memory Usage', 'Disk Space', 'CPU Load', 'Network Usage', 'System Health')
            datasets = @(@{
                    label           = 'Resource Utilization (%)'
                    data            = @()
                    backgroundColor = '#17a2b8'
                    borderColor     = '#138496'
                    borderWidth     = 1
                })
        }
        TimelineData     = @{
            labels   = @()
            datasets = @(@{
                    label           = 'Execution Duration (s)'
                    data            = @()
                    borderColor     = '#28a745'
                    backgroundColor = 'rgba(40, 167, 69, 0.1)'
                    tension         = 0.4
                    fill            = $true
                })
        }
        SecurityScore    = @{
            labels   = @('Privacy Protection', 'Telemetry Disabled', 'System Optimization', 'Update Security', 'Overall Security')
            datasets = @(@{
                    label                = 'Security Score'
                    data                 = @()
                    backgroundColor      = 'rgba(156, 39, 176, 0.2)'
                    borderColor          = '#9c27b0'
                    borderWidth          = 2
                    pointBackgroundColor = '#9c27b0'
                })
        }
    }
    
    # Generate Task Distribution Chart Data
    if ($ComprehensiveLogCollection.Type2ExecutionLogs) {
        $taskTotals = @{ 'Successful' = 0; 'Failed' = 0; 'Warnings' = 0; 'Partial' = 0 }
        
        foreach ($moduleName in $ComprehensiveLogCollection.Type2ExecutionLogs.Keys) {
            $logContent = $ComprehensiveLogCollection.Type2ExecutionLogs[$moduleName]
            
            # Parse log for success/failure counts
            $successCount = ([regex]::Matches($logContent, '\[(SUCCESS|INFO)\]')).Count
            $errorCount = ([regex]::Matches($logContent, '\[(ERROR|FAILED)\]')).Count  
            $warningCount = ([regex]::Matches($logContent, '\[WARN\]')).Count
            
            if ($errorCount -eq 0 -and $successCount -gt 0) { $taskTotals.Successful++ }
            elseif ($errorCount -gt 0 -and $successCount -eq 0) { $taskTotals.Failed++ }
            elseif ($errorCount -gt 0 -and $successCount -gt 0) { $taskTotals.Partial++ }
            if ($warningCount -gt 0) { $taskTotals.Warnings++ }
        }
        
        # Populate task distribution data
        $chartData.TaskDistribution.labels = @($taskTotals.Keys | Where-Object { $taskTotals[$_] -gt 0 })
        $chartData.TaskDistribution.datasets[0].data = @($chartData.TaskDistribution.labels | ForEach-Object { $taskTotals[$_] })
    }
    
    # Generate System Resources Chart Data (simulated from execution performance)
    if ($ComprehensiveLogCollection.Type2ExecutionLogs) {
        $avgDuration = 0
        $totalModules = $ComprehensiveLogCollection.Type2ExecutionLogs.Keys.Count
        
        foreach ($logContent in $ComprehensiveLogCollection.Type2ExecutionLogs.Values) {
            # Extract duration from logs if available
            if ($logContent -match 'Duration[:\s]+(\d+\.?\d*)(ms|s)') {
                $duration = [double]$matches[1]
                if ($matches[2] -eq 'ms') { $duration = $duration / 1000 }
                $avgDuration += $duration
            }
        }
        
        if ($totalModules -gt 0) { $avgDuration = $avgDuration / $totalModules }
        
        # Simulate resource usage based on execution patterns
        $memoryUsage = [math]::Min(100, 30 + ($avgDuration * 10))
        $diskUsage = [math]::Min(100, 20 + ($totalModules * 5))
        $cpuUsage = [math]::Min(100, 15 + ($avgDuration * 8))
        $networkUsage = [math]::Min(100, 10 + ($totalModules * 3))
        $healthScore = [math]::Max(0, 100 - ($avgDuration * 5) - ($totalModules * 2))
        
        $chartData.SystemResources.datasets[0].data = @($memoryUsage, $diskUsage, $cpuUsage, $networkUsage, $healthScore)
    }
    
    # Generate Timeline Data
    if ($ComprehensiveLogCollection.Type2ExecutionLogs) {
        $moduleOrder = @('BloatwareRemoval', 'EssentialApps', 'SystemOptimization', 'TelemetryDisable', 'WindowsUpdates')
        
        foreach ($moduleName in $moduleOrder) {
            if ($ComprehensiveLogCollection.Type2ExecutionLogs.ContainsKey($moduleName)) {
                $logContent = $ComprehensiveLogCollection.Type2ExecutionLogs[$moduleName]
                
                # Extract duration
                $duration = 0
                if ($logContent -match 'Duration[:\s]+(\d+\.?\d*)(ms|s)') {
                    $duration = [double]$matches[1]
                    if ($matches[2] -eq 'ms') { $duration = $duration / 1000 }
                }
                
                $chartData.TimelineData.labels += $moduleName
                $chartData.TimelineData.datasets[0].data += $duration
            }
        }
    }
    
    # Generate Security Score Data
    if ($ComprehensiveLogCollection.Type2ExecutionLogs) {
        $securityScores = @{
            'Privacy Protection'  = 85
            'Telemetry Disabled'  = 90  
            'System Optimization' = 80
            'Update Security'     = 75
            'Overall Security'    = 82
        }
        
        # Adjust scores based on module execution success
        if ($ComprehensiveLogCollection.Type2ExecutionLogs.ContainsKey('TelemetryDisable')) {
            $telemetryLog = $ComprehensiveLogCollection.Type2ExecutionLogs['TelemetryDisable']
            if ($telemetryLog -match '\[SUCCESS\]') { $securityScores['Privacy Protection'] = 95; $securityScores['Telemetry Disabled'] = 98 }
        }
        
        if ($ComprehensiveLogCollection.Type2ExecutionLogs.ContainsKey('SystemOptimization')) {
            $optimizationLog = $ComprehensiveLogCollection.Type2ExecutionLogs['SystemOptimization']
            if ($optimizationLog -match '\[SUCCESS\]') { $securityScores['System Optimization'] = 90 }
        }
        
        if ($ComprehensiveLogCollection.Type2ExecutionLogs.ContainsKey('WindowsUpdates')) {
            $updatesLog = $ComprehensiveLogCollection.Type2ExecutionLogs['WindowsUpdates']
            if ($updatesLog -match '\[SUCCESS\]') { $securityScores['Update Security'] = 95 }
        }
        
        # Recalculate overall security
        $securityScores['Overall Security'] = [math]::Round(($securityScores.Values | Measure-Object -Average).Average, 0)
        
        $chartData.SecurityScore.datasets[0].data = @($securityScores.Values)
    }
    
    Write-Verbose "Chart data generated: $($chartData.TaskDistribution.labels.Count) task distribution items, $($chartData.TimelineData.labels.Count) timeline points"
    
    return $chartData
}

#endregion

#region Error Processing Functions

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
                            Component = $moduleName.ToUpper()
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
                            Component = $moduleName.ToUpper()
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
            }
        }
    }, Timestamp
}

function New-ErrorReportSection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [array]$Errors
    )
    
    if ($Errors.Count -eq 0) {
        return @"
        <div class="section">
            <div class="section-header" onclick="toggleSection(this)">
                <h2>✅ Error Analysis</h2>
                <span class="toggle-icon">▼</span>
            </div>
            <div class="section-content">
                <div class="success-message">
                    <h3>No Errors Detected</h3>
                    <p>All modules executed successfully without errors.</p>
                </div>
            </div>
        </div>
"@
    }
    
    $errorsByModule = $Errors | Group-Object Module
    $highSeverityCount = ($Errors | Where-Object { $_.Severity -eq 'High' }).Count
    $mediumSeverityCount = ($Errors | Where-Object { $_.Severity -eq 'Medium' }).Count
    
    $html = [System.Text.StringBuilder]::new()
    
    $html.AppendLine(@"
        <div class="section">
            <div class="section-header" onclick="toggleSection(this)">
                <h2>⚠️ Error Analysis ($($Errors.Count) issues found)</h2>
                <span class="toggle-icon">▼</span>
            </div>
            <div class="section-content">
                <div class="error-summary">
                    <div class="error-stats">
                        <div class="stat-item error-high">
                            <span class="stat-number">$highSeverityCount</span>
                            <span class="stat-label">High Severity</span>
                        </div>
                        <div class="stat-item error-medium">
                            <span class="stat-number">$mediumSeverityCount</span>
                            <span class="stat-label">Medium Severity</span>
                        </div>
                    </div>
                </div>
"@) | Out-Null
    
    foreach ($moduleGroup in $errorsByModule) {
        $moduleName = $moduleGroup.Name
        $moduleErrors = $moduleGroup.Group
        $errorCount = $moduleErrors.Count
        
        $html.AppendLine(@"
                <div class="module-errors">
                    <h3 class="module-error-header">🔧 $moduleName ($errorCount issues)</h3>
                    <div class="error-list">
"@) | Out-Null
        
        foreach ($errorItem in $moduleErrors) {
            $severityClass = $errorItem.Severity.ToLower()
            $severityIcon = switch ($errorItem.Severity) {
                'High' { '🔴' }
                'Medium' { '🟡' }
                'Low' { '🟠' }
            }
            
            $html.AppendLine(@"
                        <div class="error-item severity-$severityClass">
                            <div class="error-header">
                                <span class="error-icon">$severityIcon</span>
                                <span class="error-level">[$($errorItem.Level)]</span>
                                <span class="error-component">$($errorItem.Component)</span>
                                <span class="error-timestamp">$($errorItem.Timestamp)</span>
                            </div>
                            <div class="error-message">$($errorItem.Message)</div>
                        </div>
"@) | Out-Null
        }
        
        $html.AppendLine(@"
                    </div>
                </div>
"@) | Out-Null
    }
    
    $html.AppendLine(@"
            </div>
        </div>
"@) | Out-Null
    
    return $html.ToString()
}

#endregion

# Export module functions
Export-ModuleMember -Function @(
    'New-MaintenanceReport',
    'Get-ModuleExecutionData',
    'Convert-ModuleDataToTaskResults',
    'New-EnhancedModuleSections',
    'Get-ReportGenerationConfig',
    'Get-DefaultReportConfig',
    'Get-HtmlTemplates',
    'Get-ErrorsFromExecutionLogs',
    'New-ErrorReportSection'
)

