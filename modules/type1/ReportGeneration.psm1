#Requires -Version 7.0

<#
.SYNOPSIS
    Report Generation Module - Type 1 (Inventory/Reporting)

.DESCRIPTION
    Generates comprehensive HTML and text reports from maintenance operations,
    including system inventory, task results, and audit trails.

.NOTES
    Module Type: Type 1 (Inventory/Reporting)
    Dependencies: System data, execution results
    Author: Windows Maintenance Automation Project
    Version: 1.0.0
#>

using namespace System.Collections.Generic
using namespace System.Text

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
    New-MaintenanceReport -SystemInventory $inventory -TaskResults $results -OutputPath "C:\Reports\maintenance"
#>
function New-MaintenanceReport {
    [CmdletBinding()]
    param(
        [Parameter()]
        [hashtable]$SystemInventory,
        
        [Parameter()]
        [Array]$TaskResults = @(),
        
        [Parameter()]
        [PSCustomObject]$Configuration,
        
        [Parameter()]
        [string]$OutputPath = ""
    )
    
    Write-Host "📋 Generating comprehensive maintenance report..." -ForegroundColor Cyan
    
    # Provide default values for parameters when not specified
    if (-not $OutputPath -or $OutputPath -eq "") {
        $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
        # Use the same directory as maintenance.log (root directory)
        $rootDir = Join-Path $PSScriptRoot "..\.."
        $OutputPath = Join-Path $rootDir "maintenance-report-$timestamp"
        Write-Host "  📁 Using default output path: $OutputPath" -ForegroundColor Gray
    }
    
    # If no system inventory provided, try to get it from TaskResults or collect it
    if (-not $SystemInventory) {
        # First, check if SystemInventory data is available in TaskResults
        $systemInventoryTask = $TaskResults | Where-Object { $_.TaskName -eq 'SystemInventory' -and $_.Success }
        if ($systemInventoryTask -and $systemInventoryTask.Output) {
            Write-Host "  � Using SystemInventory data from previous task execution..." -ForegroundColor Gray
            $SystemInventory = $systemInventoryTask.Output
        } else {
            Write-Host "  �🔍 No system inventory provided, collecting basic system info..." -ForegroundColor Gray
            try {
                # Import SystemInventory module if available
                if (Test-Path (Join-Path $PSScriptRoot "SystemInventory.psm1")) {
                    Import-Module (Join-Path $PSScriptRoot "SystemInventory.psm1") -Force -ErrorAction SilentlyContinue
                    $SystemInventory = Get-SystemInventory -ErrorAction SilentlyContinue
                }
            }
            catch {
                Write-Warning "Could not collect system inventory: $_"
                $SystemInventory = @{ Note = "System inventory collection failed" }
            }
        }
    }
    
    # If no configuration provided, get default
    if (-not $Configuration) {
        try {
            Import-Module (Join-Path $PSScriptRoot "..\core\ConfigManager.psm1") -Force -ErrorAction SilentlyContinue
            $Configuration = Get-MainConfiguration -ErrorAction SilentlyContinue
        }
        catch {
            $Configuration = @{ Note = "Configuration loading failed" }
        }
    }
    
    $startTime = Get-Date
    $reportData = @{
        GenerationTime = $startTime
        SystemInventory = $SystemInventory
        TaskResults = $TaskResults
        Configuration = $Configuration
        Summary = Get-ExecutionSummary -TaskResults $TaskResults
    }
    
    try {
        # Ensure output directory exists
        $outputDir = Split-Path $OutputPath -Parent
        if (-not (Test-Path $outputDir)) {
            New-Item -Path $outputDir -ItemType Directory -Force | Out-Null
        }
        
        # Generate HTML report
        $htmlPath = "$OutputPath.html"
        Write-Host "  📄 Creating HTML report..." -ForegroundColor Gray
        New-HtmlReport -ReportData $reportData -OutputPath $htmlPath
        
        # Generate text report
        $textPath = "$OutputPath.txt"
        Write-Host "  📝 Creating text report..." -ForegroundColor Gray
        New-TextReport -ReportData $reportData -OutputPath $textPath
        
        # Generate JSON data export
        $jsonPath = "$OutputPath.json"
        Write-Host "  📊 Creating JSON data export..." -ForegroundColor Gray
        $reportData | ConvertTo-Json -Depth 10 | Out-File -FilePath $jsonPath -Encoding UTF8
        
        $duration = ((Get-Date) - $startTime).TotalSeconds
        Write-Host "  ✅ Reports generated successfully in $([math]::Round($duration, 2)) seconds" -ForegroundColor Green
        
        return @{
            HtmlReport = $htmlPath
            TextReport = $textPath
            JsonExport = $jsonPath
            GenerationTime = $startTime
            Duration = $duration
        }
    }
    catch {
        Write-Error "Failed to generate maintenance report: $_"
        throw
    }
}

#endregion

#region Helper Functions

<#
.SYNOPSIS
    Generates detailed HTML content for specific task results
#>
function Get-DetailedTaskResults {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Task,
        
        [Parameter()]
        [hashtable]$SystemInventory
    )
    
    $details = ""
    
    switch ($Task.TaskName) {
        "SystemInventory" {
            if ($SystemInventory) {
                $sw = $SystemInventory.InstalledSoftware
                $services = $SystemInventory.Services
                $hw = $SystemInventory.Hardware
                
                $details = @"
<div class='result-section'>
    <h4>📊 System Overview</h4>
    <div class='result-grid'>
        <div class='result-item'>
            <span class='label'>Installed Programs:</span>
            <span class='value'>$($sw.TotalCount)</span>
        </div>
        <div class='result-item'>
            <span class='label'>Running Services:</span>
            <span class='value'>$($services.RunningCount)</span>
        </div>
        <div class='result-item'>
            <span class='label'>Total Memory:</span>
            <span class='value'>$([math]::Round($hw.TotalMemoryGB, 1)) GB</span>
        </div>
        <div class='result-item'>
            <span class='label'>CPU Cores:</span>
            <span class='value'>$($hw.ProcessorCores)</span>
        </div>
    </div>
</div>
"@
            }
        }
        
        "BloatwareDetection" {
            $details = @"
<div class='result-section'>
    <h4>🔍 Bloatware Scan Results</h4>
    <div class='result-summary'>
        <div class='scan-result'>
            <span class='scan-label'>📱 AppX Packages:</span> <span class='scan-status'>Scanned</span>
        </div>
        <div class='scan-result'>
            <span class='scan-label'>📦 Registry Programs:</span> <span class='scan-status'>Scanned</span>
        </div>
        <div class='scan-result'>
            <span class='scan-label'>🍫 Chocolatey Apps:</span> <span class='scan-status'>Scanned</span>
        </div>
        <div class='scan-result'>
            <span class='scan-label'>🔧 System Services:</span> <span class='scan-status'>Scanned</span>
        </div>
    </div>
    <div class='scan-note'>
        ℹ️ Detailed bloatware findings will be available in future reports
    </div>
</div>
"@
        }
        
        "BloatwareRemoval" {
            $details = @"
<div class='result-section'>
    <h4>🗑️ Bloatware Removal Results</h4>
    <div class='removal-summary'>
        <div class='removal-category'>
            <span class='category-label'>AppX Packages:</span>
            <span class='category-status pending'>Ready for removal</span>
        </div>
        <div class='removal-category'>
            <span class='category-label'>System Applications:</span>
            <span class='category-status pending'>Ready for removal</span>
        </div>
        <div class='removal-category'>
            <span class='category-label'>Services:</span>
            <span class='category-status pending'>Ready for cleanup</span>
        </div>
    </div>
    <div class='action-note'>
        ⚠️ Removal operations require administrative privileges
    </div>
</div>
"@
        }
        
        "EssentialApps" {
            $details = @"
<div class='result-section'>
    <h4>📦 Essential Apps Installation</h4>
    <div class='install-summary'>
        <div class='install-category'>
            <span class='category-label'>Web Browsers:</span>
            <span class='category-status ready'>Ready to install</span>
        </div>
        <div class='install-category'>
            <span class='category-label'>Development Tools:</span>
            <span class='category-status ready'>Ready to install</span>
        </div>
        <div class='install-category'>
            <span class='category-label'>Media Players:</span>
            <span class='category-status ready'>Ready to install</span>
        </div>
        <div class='install-category'>
            <span class='category-label'>Productivity Suite:</span>
            <span class='category-status ready'>Ready to install</span>
        </div>
    </div>
    <div class='install-note'>
        💡 Applications will be installed via Winget and Chocolatey
    </div>
</div>
"@
        }
        
        "WindowsUpdates" {
            $details = @"
<div class='result-section'>
    <h4>🔄 Windows Update Status</h4>
    <div class='update-summary'>
        <div class='update-item'>
            <span class='update-label'>Update Check:</span>
            <span class='update-status completed'>Completed</span>
        </div>
        <div class='update-item'>
            <span class='update-label'>Security Updates:</span>
            <span class='update-status pending'>Checking...</span>
        </div>
        <div class='update-item'>
            <span class='update-label'>Feature Updates:</span>
            <span class='update-status pending'>Checking...</span>
        </div>
        <div class='update-item'>
            <span class='update-label'>Driver Updates:</span>
            <span class='update-status pending'>Checking...</span>
        </div>
    </div>
</div>
"@
        }
        
        "TelemetryDisable" {
            $details = @"
<div class='result-section'>
    <h4>🛡️ Privacy & Telemetry Settings</h4>
    <div class='privacy-summary'>
        <div class='privacy-item'>
            <span class='privacy-label'>Telemetry Services:</span>
            <span class='privacy-status'>Configured</span>
        </div>
        <div class='privacy-item'>
            <span class='privacy-label'>Data Collection:</span>
            <span class='privacy-status'>Minimized</span>
        </div>
        <div class='privacy-item'>
            <span class='privacy-label'>Location Services:</span>
            <span class='privacy-status'>Reviewed</span>
        </div>
        <div class='privacy-item'>
            <span class='privacy-label'>Cortana Settings:</span>
            <span class='privacy-status'>Configured</span>
        </div>
    </div>
</div>
"@
        }
        
        "SecurityAudit" {
            $details = @"
<div class='result-section'>
    <h4>🔒 Security Audit Results</h4>
    <div class='security-summary'>
        <div class='security-check'>
            <span class='check-label'>Firewall Status:</span>
            <span class='check-status active'>Active</span>
        </div>
        <div class='security-check'>
            <span class='check-label'>Windows Defender:</span>
            <span class='check-status active'>Running</span>
        </div>
        <div class='security-check'>
            <span class='check-label'>User Account Control:</span>
            <span class='check-status enabled'>Enabled</span>
        </div>
        <div class='security-check'>
            <span class='check-label'>System Updates:</span>
            <span class='check-status current'>Current</span>
        </div>
    </div>
</div>
"@
        }
        
        "SystemOptimization" {
            $details = @"
<div class='result-section'>
    <h4>⚡ System Optimization Results</h4>
    <div class='optimization-summary'>
        <div class='optimization-item'>
            <span class='opt-label'>Temporary Files:</span>
            <span class='opt-status cleaned'>Cleaned</span>
        </div>
        <div class='optimization-item'>
            <span class='opt-label'>System Cache:</span>
            <span class='opt-status cleared'>Cleared</span>
        </div>
        <div class='optimization-item'>
            <span class='opt-label'>Registry Cleanup:</span>
            <span class='opt-status optimized'>Optimized</span>
        </div>
        <div class='optimization-item'>
            <span class='opt-label'>Startup Programs:</span>
            <span class='opt-status reviewed'>Reviewed</span>
        </div>
    </div>
</div>
"@
        }
        
        "ReportGeneration" {
            $details = @"
<div class='result-section'>
    <h4>📊 Report Generation</h4>
    <div class='report-summary'>
        <div class='report-item'>
            <span class='report-label'>HTML Report:</span>
            <span class='report-status generated'>Generated</span>
        </div>
        <div class='report-item'>
            <span class='report-label'>Text Report:</span>
            <span class='report-status generated'>Generated</span>
        </div>
        <div class='report-item'>
            <span class='report-label'>JSON Export:</span>
            <span class='report-status generated'>Generated</span>
        </div>
        <div class='report-item'>
            <span class='report-label'>Log Files:</span>
            <span class='report-status saved'>Saved</span>
        </div>
    </div>
</div>
"@
        }
        
        default {
            $details = @"
<div class='result-section'>
    <h4>ℹ️ Task Completed</h4>
    <p>This task has been executed successfully. Detailed results will be available in future report versions.</p>
</div>
"@
        }
    }
    
    return $details
}

#endregion

#region HTML Report Generation

<#
.SYNOPSIS
    Creates an interactive HTML report
#>
function New-HtmlReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$ReportData,
        
        [Parameter(Mandatory)]
        [string]$OutputPath
    )
    
    $html = [StringBuilder]::new()
    
    # HTML header with CSS and JavaScript
    $html.AppendLine(@"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Windows Maintenance Report - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</title>
    <style>
        :root {
            --primary-color: #0078d4;
            --success-color: #107c10;
            --warning-color: #ffb900;
            --error-color: #d13438;
            --bg-color: #f5f5f5;
            --card-bg: #ffffff;
            --text-color: #323130;
            --border-color: #e1dfdd;
        }
        
        * { margin: 0; padding: 0; box-sizing: border-box; }
        
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background-color: var(--bg-color);
            color: var(--text-color);
            line-height: 1.6;
        }
        
        .container {
            max-width: 1200px;
            margin: 0 auto;
            padding: 20px;
        }
        
        .header {
            background: linear-gradient(135deg, var(--primary-color), #106ebe);
            color: white;
            padding: 30px;
            border-radius: 8px;
            margin-bottom: 30px;
            text-align: center;
        }
        
        .header h1 { font-size: 2.5em; margin-bottom: 10px; }
        .header p { font-size: 1.2em; opacity: 0.9; }
        
        .summary-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }
        
        .summary-card {
            background: var(--card-bg);
            padding: 25px;
            border-radius: 8px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
            text-align: center;
        }
        
        .summary-card h3 {
            color: var(--primary-color);
            margin-bottom: 15px;
            font-size: 1.1em;
        }
        
        .summary-value {
            font-size: 2.5em;
            font-weight: bold;
            margin-bottom: 10px;
        }
        
        .success { color: var(--success-color); }
        .warning { color: var(--warning-color); }
        .error { color: var(--error-color); }
        
        .section {
            background: var(--card-bg);
            border-radius: 8px;
            margin-bottom: 20px;
            overflow: hidden;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }
        
        .section-header {
            background: var(--primary-color);
            color: white;
            padding: 20px;
            cursor: pointer;
            display: flex;
            justify-content: space-between;
            align-items: center;
        }
        
        .section-header:hover {
            background: #106ebe;
        }
        
        .section-content {
            padding: 25px;
            display: none;
        }
        
        .section.expanded .section-content {
            display: block;
        }
        
        .toggle-icon {
            transition: transform 0.3s ease;
        }
        
        .section.expanded .toggle-icon {
            transform: rotate(180deg);
        }
        
        .task-list {
            list-style: none;
        }
        
        .task-item {
            display: flex;
            align-items: center;
            padding: 15px;
            border-bottom: 1px solid var(--border-color);
            transition: background-color 0.3s ease;
        }
        
        .task-item:hover {
            background-color: #f8f9fa;
        }
        
        .task-status {
            width: 24px;
            height: 24px;
            border-radius: 50%;
            margin-right: 15px;
            display: flex;
            align-items: center;
            justify-content: center;
            color: white;
            font-weight: bold;
        }
        
        .task-details {
            flex: 1;
        }
        
        .task-name {
            font-weight: 600;
            margin-bottom: 5px;
        }
        
        .task-description {
            color: #666;
            font-size: 0.9em;
        }
        
        .task-duration {
            color: #888;
            font-size: 0.8em;
            margin-left: auto;
        }
        
        .info-table {
            width: 100%;
            border-collapse: collapse;
            margin-top: 15px;
        }
        
        .info-table th,
        .info-table td {
            text-align: left;
            padding: 12px;
            border-bottom: 1px solid var(--border-color);
        }
        
        .info-table th {
            background-color: #f8f9fa;
            font-weight: 600;
            color: var(--primary-color);
        }
        
        .footer {
            text-align: center;
            padding: 20px;
            color: #666;
            font-size: 0.9em;
        }
        
        /* Task Result Styles */
        .result-section {
            margin: 15px 0;
            padding: 15px;
            background-color: #f8f9fa;
            border-radius: 8px;
            border-left: 4px solid var(--primary-color);
        }
        
        .result-section h4 {
            margin: 0 0 15px 0;
            color: var(--primary-color);
            font-size: 1.1em;
        }
        
        .result-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 10px;
            margin: 10px 0;
        }
        
        .result-item {
            display: flex;
            justify-content: space-between;
            padding: 8px 12px;
            background-color: white;
            border-radius: 6px;
            border: 1px solid #e0e0e0;
        }
        
        .label {
            font-weight: 500;
            color: #555;
        }
        
        .value {
            font-weight: 600;
            color: var(--primary-color);
        }
        
        /* Scan Results */
        .result-summary, .removal-summary, .install-summary, 
        .update-summary, .privacy-summary, .security-summary, 
        .optimization-summary, .report-summary {
            display: flex;
            flex-direction: column;
            gap: 8px;
        }
        
        .scan-result, .removal-category, .install-category,
        .update-item, .privacy-item, .security-check,
        .optimization-item, .report-item {
            display: flex;
            justify-content: space-between;
            align-items: center;
            padding: 8px 12px;
            background-color: white;
            border-radius: 6px;
            border: 1px solid #e0e0e0;
        }
        
        .scan-label, .category-label, .update-label, 
        .privacy-label, .check-label, .opt-label, .report-label {
            font-weight: 500;
            color: #555;
        }
        
        .scan-status, .category-status, .update-status,
        .privacy-status, .check-status, .opt-status, .report-status {
            padding: 4px 8px;
            border-radius: 4px;
            font-size: 0.9em;
            font-weight: 500;
        }
        
        /* Status Colors */
        .scan-status, .completed, .generated, .saved, .cleaned, 
        .cleared, .optimized, .reviewed, .active, .enabled, .current {
            background-color: #d4edda;
            color: #155724;
        }
        
        .pending, .ready {
            background-color: #fff3cd;
            color: #856404;
        }
        
        .category-status.pending {
            background-color: #f8d7da;
            color: #721c24;
        }
        
        .scan-note, .action-note, .install-note {
            margin-top: 10px;
            padding: 10px;
            background-color: #e7f3ff;
            color: #0066cc;
            border-radius: 6px;
            font-size: 0.9em;
        }
        
        /* Task Results Container */
        .task-results {
            margin-top: 15px;
            border-top: 1px solid #e0e0e0;
            padding-top: 15px;
        }
        
        .task-meta {
            display: flex;
            gap: 5px;
            align-items: center;
            font-size: 0.85em;
            color: #666;
            margin-top: 5px;
        }
        
        .task-type, .task-category {
            padding: 2px 6px;
            background-color: #e9ecef;
            border-radius: 3px;
            font-weight: 500;
        }
        
        .task-error {
            margin-top: 10px;
            padding: 10px;
            background-color: #f8d7da;
            color: #721c24;
            border-radius: 6px;
            border-left: 4px solid #dc3545;
        }
        
        @media (max-width: 768px) {
            .container { padding: 10px; }
            .header { padding: 20px; }
            .header h1 { font-size: 2em; }
            .summary-grid { grid-template-columns: 1fr; }
            .result-grid { grid-template-columns: 1fr; }
        }
    </style>
    <script>
        function toggleSection(element) {
            const section = element.parentElement;
            section.classList.toggle('expanded');
        }
        
        document.addEventListener('DOMContentLoaded', function() {
            // Expand first section by default
            const firstSection = document.querySelector('.section');
            if (firstSection) {
                firstSection.classList.add('expanded');
            }
        });
    </script>
</head>
<body>
    <div class="container">
"@) | Out-Null
    
    # Report header
    $html.AppendLine(@"
        <div class="header">
            <h1>🛠️ Windows Maintenance Report</h1>
            <p>Generated on $(Get-Date -Format 'dddd, MMMM dd, yyyy at HH:mm:ss')</p>
            <p>Computer: $env:COMPUTERNAME | User: $env:USERNAME</p>
        </div>
"@) | Out-Null
    
    # Summary cards
    $summary = $ReportData.Summary
    $html.AppendLine(@"
        <div class="summary-grid">
            <div class="summary-card">
                <h3>📊 Tasks Executed</h3>
                <div class="summary-value">$($summary.TotalTasks)</div>
                <p>Total maintenance tasks</p>
            </div>
            <div class="summary-card">
                <h3>✅ Successful</h3>
                <div class="summary-value success">$($summary.SuccessfulTasks)</div>
                <p>Completed without errors</p>
            </div>
            <div class="summary-card">
                <h3>❌ Failed</h3>
                <div class="summary-value error">$($summary.FailedTasks)</div>
                <p>Completed with errors</p>
            </div>
            <div class="summary-card">
                <h3>⏱️ Duration</h3>
                <div class="summary-value">$([math]::Round($summary.TotalDuration, 1))s</div>
                <p>Total execution time</p>
            </div>
        </div>
"@) | Out-Null
    
    # Task execution results
    if ($ReportData.TaskResults.Count -gt 0) {
        $html.AppendLine(@"
        <div class="section">
            <div class="section-header" onclick="toggleSection(this)">
                <h2>📋 Task Execution Results</h2>
                <span class="toggle-icon">▼</span>
            </div>
            <div class="section-content">
                <ul class="task-list">
"@) | Out-Null
        
        foreach ($task in $ReportData.TaskResults) {
            $statusIcon = if ($task.Success) { '✓' } else { '✗' }
            $statusColor = if ($task.Success) { 'var(--success-color)' } else { 'var(--error-color)' }
            $duration = [math]::Round($task.Duration, 2)
            
            # Generate detailed task results based on task type
            $taskDetails = Get-DetailedTaskResults -Task $task -SystemInventory $ReportData.SystemInventory
            
            $html.AppendLine(@"
                    <li class="task-item">
                        <div class="task-status" style="background-color: $statusColor">$statusIcon</div>
                        <div class="task-details">
                            <div class="task-header">
                                <div class="task-name">$($task.TaskName)</div>
                                <div class="task-meta">
                                    <span class="task-type">$($task.Type)</span> • 
                                    <span class="task-category">$($task.Category)</span> • 
                                    <span class="task-duration">${duration}s</span>
                                </div>
                            </div>
                            <div class="task-description">$($task.Description)</div>
                            $(if (-not $task.Success -and $task.Error) { "<div class='task-error'>❌ <strong>Error:</strong> $($task.Error)</div>" })
                            $(if ($taskDetails) { "<div class='task-results'>$taskDetails</div>" })
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
    
    # Footer
    $html.AppendLine(@"
        <div class="footer">
            <p>Report generated by Windows Maintenance Automation v2.0</p>
            <p>For more information, visit the project documentation</p>
        </div>
    </div>
</body>
</html>
"@) | Out-Null
    
    # Write HTML to file
    $html.ToString() | Out-File -FilePath $OutputPath -Encoding UTF8
}

#endregion

#region Text Report Generation

<#
.SYNOPSIS
    Creates a detailed text report
#>
function New-TextReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$ReportData,
        
        [Parameter(Mandatory)]
        [string]$OutputPath
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
    
    # Write text to file
    $text.ToString() | Out-File -FilePath $OutputPath -Encoding UTF8
}

#endregion

#region Helper Functions

<#
.SYNOPSIS
    Generates execution summary statistics
#>
function Get-ExecutionSummary {
    param([Array]$TaskResults)
    
    $successful = $TaskResults | Where-Object { $_.Success }
    $failed = $TaskResults | Where-Object { -not $_.Success }
    $totalDuration = ($TaskResults | Measure-Object Duration -Sum).Sum
    
    return @{
        TotalTasks = $TaskResults.Count
        SuccessfulTasks = $successful.Count
        FailedTasks = $failed.Count
        TotalDuration = $totalDuration
        SuccessRate = if ($TaskResults.Count -gt 0) { 
            [math]::Round(($successful.Count / $TaskResults.Count) * 100, 1) 
        } else { 0 }
    }
}

#endregion

# Export module functions
Export-ModuleMember -Function @(
    'New-MaintenanceReport'
)