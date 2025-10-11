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

        [Parameter(Mandatory)]
        [string]$OutputPath
    )

    Write-Information "📋 Generating comprehensive maintenance report..." -InformationAction Continue

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
        Write-Information "  📄 Creating HTML report..." -InformationAction Continue
        New-HtmlReport -ReportData $reportData -OutputPath $htmlPath

        # Generate text report
        $textPath = "$OutputPath.txt"
        Write-Information "  📝 Creating text report..." -InformationAction Continue
        New-TextReport -ReportData $reportData -OutputPath $textPath

        # Generate JSON data export
        $jsonPath = "$OutputPath.json"
        Write-Information "  📊 Creating JSON data export..." -InformationAction Continue
        $reportData | ConvertTo-Json -Depth 10 | Out-File -FilePath $jsonPath -Encoding UTF8

        $duration = ((Get-Date) - $startTime).TotalSeconds
        Write-Information "  ✅ Reports generated successfully in $([math]::Round($duration, 2)) seconds" -InformationAction Continue

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

        @media (max-width: 768px) {
            .container { padding: 10px; }
            .header { padding: 20px; }
            .header h1 { font-size: 2em; }
            .summary-grid { grid-template-columns: 1fr; }
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

            $html.AppendLine(@"
                    <li class="task-item">
                        <div class="task-status" style="background-color: $statusColor">$statusIcon</div>
                        <div class="task-details">
                            <div class="task-name">$($task.TaskName)</div>
                            <div class="task-description">$($task.Description)</div>
                            $(if (-not $task.Success -and $task.Error) { "<div style='color: var(--error-color); font-size: 0.9em; margin-top: 5px;'>Error: $($task.Error)</div>" })
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
