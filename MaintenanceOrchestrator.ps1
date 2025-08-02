# MaintenanceOrchestrator.ps1
# Main orchestrator script that coordinates all maintenance tasks using modular architecture

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ConfigPath = (Join-Path $PSScriptRoot "config\maintenance-config.json"),
    
    [Parameter(Mandatory = $false)]
    [switch]$TestMode,
    
    [Parameter(Mandatory = $false)]
    [string[]]$TaskFilter = @(),
    
    [Parameter(Mandatory = $false)]
    [switch]$GenerateReport
)

# Import required modules
$ModulePath = Join-Path $PSScriptRoot "modules"
Import-Module (Join-Path $ModulePath "ConfigManager.psm1") -Force
Import-Module (Join-Path $ModulePath "LoggingManager.psm1") -Force  
Import-Module (Join-Path $ModulePath "SystemTasks.psm1") -Force

function Start-MaintenanceSession {
    <#
    .SYNOPSIS
    Main entry point for the maintenance script.
    #>
    [CmdletBinding()]
    param()
    
    try {
        # Load configuration
        Write-Host "Loading configuration..." -ForegroundColor Cyan
        $config = Import-MaintenanceConfig -ConfigPath $ConfigPath
        
        # Initialize logging
        $logPath = Join-Path $PSScriptRoot "logs"
        Initialize-Logger -LogPath $logPath -LogLevel $config.system.logLevel -RetentionDays $config.system.logRetentionDays
        
        Write-LogMessage -Level "Info" -Message "=== Maintenance Session Started ==="
        Write-LogMessage -Level "Info" -Message "Script Version: 2.0.0"
        Write-LogMessage -Level "Info" -Message "Configuration: $ConfigPath"
        
        if ($TestMode) {
            Write-LogMessage -Level "Info" -Message "Running in TEST MODE - no actual changes will be made"
        }
        
        # Validate system requirements
        Write-LogMessage -Level "Info" -Message "Validating system requirements..."
        if (-not (Test-SystemRequirements -Config $config)) {
            throw "System requirements validation failed"
        }
        
        # Get enabled tasks
        $tasks = Get-EnabledTasks -Config $config
        
        # Filter tasks if specified
        if ($TaskFilter.Count -gt 0) {
            $tasks = $tasks | Where-Object { $_.Name -in $TaskFilter }
            Write-LogMessage -Level "Info" -Message "Task filter applied. Running tasks: $($TaskFilter -join ', ')"
        }
        
        if ($tasks.Count -eq 0) {
            Write-LogMessage -Level "Warning" -Message "No tasks enabled or matched filter criteria"
            return
        }
        
        Write-LogMessage -Level "Info" -Message "Found $($tasks.Count) enabled tasks to execute"
        
        # Execute tasks
        $results = @()
        foreach ($task in $tasks) {
            $result = Invoke-MaintenanceTask -Task $task -TestMode:$TestMode
            $results += $result
        }
        
        # Generate summary
        $successCount = ($results | Where-Object { $_.Success }).Count
        $failureCount = $results.Count - $successCount
        
        Write-LogMessage -Level "Info" -Message "=== Maintenance Session Summary ==="
        Write-LogMessage -Level "Info" -Message "Total Tasks: $($results.Count)"
        Write-LogMessage -Level "Info" -Message "Successful: $successCount"
        Write-LogMessage -Level "Info" -Message "Failed: $failureCount"
        
        # Generate report if requested
        if ($GenerateReport -or $config.reporting.generateReport) {
            Write-LogMessage -Level "Info" -Message "Generating maintenance report..."
            New-MaintenanceReport -Results $results -Config $config
        }
        
        Write-LogMessage -Level "Info" -Message "=== Maintenance Session Completed ==="
        
        return $results
    }
    catch {
        Write-LogMessage -Level "Error" -Message "Maintenance session failed" -Exception $_.Exception
        throw
    }
}

function Invoke-MaintenanceTask {
    <#
    .SYNOPSIS
    Executes a single maintenance task.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Task,
        
        [Parameter(Mandatory = $false)]
        [switch]$TestMode
    )
    
    $result = [PSCustomObject]@{
        TaskName = $Task.Name
        Description = $Task.Description
        StartTime = Get-Date
        EndTime = $null
        Duration = $null
        Success = $false
        ErrorMessage = $null
        TestMode = $TestMode.IsPresent
    }
    
    try {
        Start-TaskLogging -TaskName $Task.Name
        
        if ($TestMode) {
            Write-LogMessage -Level "Info" -Message "TEST MODE: Would execute task '$($Task.Name)'"
            Start-Sleep -Seconds 1  # Simulate execution time
            $taskSuccess = $true
        } else {
            # Execute the actual task based on task name
            $taskSuccess = switch ($Task.Name) {
                "systemRestore" { Invoke-SystemRestorePoint -TaskSettings $Task.Settings }
                "defenderScan" { Invoke-DefenderScan -TaskSettings $Task.Settings }
                "diskCleanup" { Invoke-DiskCleanup -TaskSettings $Task.Settings }
                "systemFileCheck" { Invoke-SystemFileCheck -TaskSettings $Task.Settings }
                "windowsUpdates" { Invoke-WindowsUpdates -TaskSettings $Task.Settings }
                default {
                    Write-LogMessage -Level "Warning" -Message "Unknown task: $($Task.Name)"
                    $false
                }
            }
        }
        
        $result.Success = $taskSuccess
        Stop-TaskLogging -Success $taskSuccess
    }
    catch {
        $result.ErrorMessage = $_.Exception.Message
        Write-LogMessage -Level "Error" -Message "Task '$($Task.Name)' failed" -Exception $_.Exception
        Stop-TaskLogging -Success $false
    }
    finally {
        $result.EndTime = Get-Date
        $result.Duration = $result.EndTime - $result.StartTime
    }
    
    return $result
}

function New-MaintenanceReport {
    <#
    .SYNOPSIS
    Generates a maintenance report.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject[]]$Results,
        
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Config
    )
    
    try {
        $reportPath = Join-Path $PSScriptRoot "reports"
        if (-not (Test-Path $reportPath)) {
            New-Item -Path $reportPath -ItemType Directory -Force | Out-Null
        }
        
        $reportFile = Join-Path $reportPath "maintenance_report_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"
        
        $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>System Maintenance Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .header { background-color: #f0f0f0; padding: 10px; border-radius: 5px; }
        .success { color: green; }
        .failure { color: red; }
        table { border-collapse: collapse; width: 100%; margin-top: 20px; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #f2f2f2; }
    </style>
</head>
<body>
    <div class="header">
        <h1>System Maintenance Report</h1>
        <p><strong>Generated:</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>
        <p><strong>Computer:</strong> $env:COMPUTERNAME</p>
        <p><strong>User:</strong> $env:USERNAME</p>
    </div>
    
    <h2>Summary</h2>
    <p><strong>Total Tasks:</strong> $($Results.Count)</p>
    <p><strong>Successful:</strong> <span class="success">$(($Results | Where-Object {$_.Success}).Count)</span></p>
    <p><strong>Failed:</strong> <span class="failure">$(($Results | Where-Object {-not $_.Success}).Count)</span></p>
    
    <h2>Task Details</h2>
    <table>
        <tr>
            <th>Task Name</th>
            <th>Description</th>
            <th>Status</th>
            <th>Duration</th>
            <th>Error Message</th>
        </tr>
"@
        
        foreach ($result in $Results) {
            $statusClass = if ($result.Success) { "success" } else { "failure" }
            $statusText = if ($result.Success) { "SUCCESS" } else { "FAILED" }
            $duration = if ($result.Duration) { $result.Duration.ToString("mm\:ss") } else { "N/A" }
            $errorMsg = if ($result.ErrorMessage) { $result.ErrorMessage } else { "-" }
            
            $html += @"
        <tr>
            <td>$($result.TaskName)</td>
            <td>$($result.Description)</td>
            <td class="$statusClass">$statusText</td>
            <td>$duration</td>
            <td>$errorMsg</td>
        </tr>
"@
        }
        
        $html += @"
    </table>
</body>
</html>
"@
        
        $html | Out-File -FilePath $reportFile -Encoding UTF8
        Write-LogMessage -Level "Info" -Message "Maintenance report generated: $reportFile"
    }
    catch {
        Write-LogMessage -Level "Error" -Message "Failed to generate report" -Exception $_.Exception
    }
}

# Main execution
if ($MyInvocation.InvocationName -eq $MyInvocation.MyCommand.Name) {
    try {
        $results = Start-MaintenanceSession
        exit 0
    }
    catch {
        Write-Error "Maintenance session failed: $($_.Exception.Message)"
        exit 1
    }
}
