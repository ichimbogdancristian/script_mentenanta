# Coordinator.psm1 - Central coordination module for Windows Maintenance Automation
# Manages task execution, dependencies, and supervision of all maintenance tasks

# Import specialized task modules
$modulePath = Split-Path -Parent $PSScriptRoot
$taskModulesPath = Join-Path $modulePath "tasks"

# Import system tasks
$systemTasksPath = Join-Path $taskModulesPath "system\SystemTasks.psm1"
if (Test-Path $systemTasksPath) {
    Import-Module $systemTasksPath -Force -ErrorAction SilentlyContinue
}

# Import application tasks
$appTasksPath = Join-Path $taskModulesPath "applications\ApplicationTasks.psm1"
if (Test-Path $appTasksPath) {
    Import-Module $appTasksPath -Force -ErrorAction SilentlyContinue
}

# Import update tasks
$updateTasksPath = Join-Path $taskModulesPath "updates\UpdateTasks.psm1"
if (Test-Path $updateTasksPath) {
    Import-Module $updateTasksPath -Force -ErrorAction SilentlyContinue
}

# Import monitoring tasks
$monitoringTasksPath = Join-Path $taskModulesPath "monitoring\MonitoringTasks.psm1"
if (Test-Path $monitoringTasksPath) {
    Import-Module $monitoringTasksPath -Force -ErrorAction SilentlyContinue
}

# Import scheduled tasks
$scheduledTasksPath = Join-Path $taskModulesPath "ScheduledTasks.psm1"
if (Test-Path $scheduledTasksPath) {
    Import-Module $scheduledTasksPath -Force -ErrorAction SilentlyContinue
}

# Global task results tracking
$global:TaskResults = @{}

# ================================================================
# Global Task Array - Centralized Task Definitions
# ================================================================
# Purpose: Centralized maintenance task coordination with standardized metadata
# ================================================================
$global:ScriptTasks = @(
    @{ Name = 'SystemRestoreProtection'; Function = {
            Write-Log 'Starting System Restore Protection task.' 'INFO'
            Write-Host 'Starting System Restore Protection task.' -ForegroundColor Cyan
            if (-not $global:Config.SkipSystemRestore) {
                Protect-SystemRestore
                Write-Log 'Completed System Restore Protection task.' 'INFO'
                Write-Host 'Completed System Restore Protection task.' -ForegroundColor Green
                return $true
            }
            else {
                Write-Log 'System Restore Protection skipped by configuration.' 'INFO'
                Write-Host 'System Restore Protection skipped by configuration.' -ForegroundColor Yellow
                return $false
            }
        }; Description = 'Enable System Restore and create pre-maintenance checkpoint'
    },

    @{ Name = 'SystemHealthOptimization'; Function = {
            Write-Log 'Starting System Health Optimization task.' 'INFO'
            Write-Host 'Starting System Health Optimization task.' -ForegroundColor Cyan
            if (-not $global:Config.SkipSystemHealth) {
                Optimize-SystemHealth
                Write-Log 'Completed System Health Optimization task.' 'INFO'
                Write-Host 'Completed System Health Optimization task.' -ForegroundColor Green
                return $true
            }
            else {
                Write-Log 'System Health Optimization skipped by configuration.' 'INFO'
                Write-Host 'System Health Optimization skipped by configuration.' -ForegroundColor Yellow
                return $false
            }
        }; Description = 'Optimize system performance and health settings'
    },

    @{ Name = 'SystemInventory'; Function = {
            Write-Log 'Starting System Inventory task.' 'INFO'
            Write-Host 'Starting System Inventory task.' -ForegroundColor Cyan
            Get-SystemInventory
            Write-Log 'Completed System Inventory task.' 'INFO'
            Write-Host 'Completed System Inventory task.' -ForegroundColor Green
            return $true
        }; Description = 'Collect comprehensive system information for analysis and reporting'
    },

    @{ Name = 'RemoveBloatware'; Function = {
            Write-Log 'Starting Bloatware Removal task.' 'INFO'
            Write-Host 'Starting Bloatware Removal task.' -ForegroundColor Cyan
            if (-not $global:Config.SkipBloatwareRemoval) {
                Remove-Bloatware
                Write-Log 'Completed Bloatware Removal task.' 'INFO'
                Write-Host 'Completed Bloatware Removal task.' -ForegroundColor Green
                return $true
            }
            else {
                Write-Log 'Bloatware removal skipped by configuration.' 'INFO'
                Write-Host 'Bloatware removal skipped by configuration.' -ForegroundColor Yellow
                return $false
            }
        }; Description = 'Remove unwanted apps via AppX, DISM, Registry, and Windows Capabilities'
    },

    @{ Name = 'InstallEssentialApps'; Function = {
            Write-Log 'Starting Essential Apps Installation task.' 'INFO'
            Write-Host 'Starting Essential Apps Installation task.' -ForegroundColor Cyan
            if (-not $global:Config.SkipEssentialApps) {
                Install-EssentialApps
                Write-Log 'Completed Essential Apps Installation task.' 'INFO'
                Write-Host 'Completed Essential Apps Installation task.' -ForegroundColor Green
                return $true
            }
            else {
                Write-Log 'Essential apps installation skipped by configuration.' 'INFO'
                Write-Host 'Essential apps installation skipped by configuration.' -ForegroundColor Yellow
                return $false
            }
        }; Description = 'Install curated essential applications via parallel processing'
    },

    @{ Name = 'UpdateInstalledApplications'; Function = {
            Write-Log 'Starting Application Updates task.' 'INFO'
            Write-Host 'Starting Application Updates task.' -ForegroundColor Cyan
            if (-not $global:Config.SkipAppUpdates) {
                Update-InstalledApplications
                Write-Log 'Completed Application Updates task.' 'INFO'
                Write-Host 'Completed Application Updates task.' -ForegroundColor Green
                return $true
            }
            else {
                Write-Log 'Application updates skipped by configuration.' 'INFO'
                Write-Host 'Application updates skipped by configuration.' -ForegroundColor Yellow
                return $false
            }
        }; Description = 'Update all installed applications via Winget, Chocolatey, and package managers'
    },

    @{ Name = 'InstallWindowsUpdates'; Function = {
            Write-Log 'Starting Windows Updates task.' 'INFO'
            Write-Host 'Starting Windows Updates task.' -ForegroundColor Cyan
            if (-not $global:Config.SkipWindowsUpdates) {
                Install-WindowsUpdates
                Write-Log 'Completed Windows Updates task.' 'INFO'
                Write-Host 'Completed Windows Updates task.' -ForegroundColor Green
                return $true
            }
            else {
                Write-Log 'Windows updates skipped by configuration.' 'INFO'
                Write-Host 'Windows updates skipped by configuration.' -ForegroundColor Yellow
                return $false
            }
        }; Description = 'Install pending Windows updates and security patches'
    },

    @{ Name = 'InstallOptionalUpdates'; Function = {
            Write-Log 'Starting Optional Updates task.' 'INFO'
            Write-Host 'Starting Optional Updates task.' -ForegroundColor Cyan
            if (-not $global:Config.SkipOptionalUpdates) {
                Install-OptionalUpdates
                Write-Log 'Completed Optional Updates task.' 'INFO'
                Write-Host 'Completed Optional Updates task.' -ForegroundColor Green
                return $true
            }
            else {
                Write-Log 'Optional updates skipped by configuration.' 'INFO'
                Write-Host 'Optional updates skipped by configuration.' -ForegroundColor Yellow
                return $false
            }
        }; Description = 'Install optional Windows features and updates'
    },

    @{ Name = 'UpdateDeviceDrivers'; Function = {
            Write-Log 'Starting Device Driver Updates task.' 'INFO'
            Write-Host 'Starting Device Driver Updates task.' -ForegroundColor Cyan
            if (-not $global:Config.SkipDriverUpdates) {
                Update-DeviceDrivers
                Write-Log 'Completed Device Driver Updates task.' 'INFO'
                Write-Host 'Completed Device Driver Updates task.' -ForegroundColor Green
                return $true
            }
            else {
                Write-Log 'Device driver updates skipped by configuration.' 'INFO'
                Write-Host 'Device driver updates skipped by configuration.' -ForegroundColor Yellow
                return $false
            }
        }; Description = 'Update device drivers using Windows Update'
    },

    @{ Name = 'TestSystemHealth'; Function = {
            Write-Log 'Starting System Health Check task.' 'INFO'
            Write-Host 'Starting System Health Check task.' -ForegroundColor Cyan
            if (-not $global:Config.SkipHealthCheck) {
                Test-SystemHealth
                Write-Log 'Completed System Health Check task.' 'INFO'
                Write-Host 'Completed System Health Check task.' -ForegroundColor Green
                return $true
            }
            else {
                Write-Log 'System health check skipped by configuration.' 'INFO'
                Write-Host 'System health check skipped by configuration.' -ForegroundColor Yellow
                return $false
            }
        }; Description = 'Run system health checks and repairs using DISM and SFC'
    },

    @{ Name = 'OptimizeWindowsUpdate'; Function = {
            Write-Log 'Starting Windows Update Optimization task.' 'INFO'
            Write-Host 'Starting Windows Update Optimization task.' -ForegroundColor Cyan
            if (-not $global:Config.SkipUpdateOptimization) {
                Optimize-WindowsUpdate
                Write-Log 'Completed Windows Update Optimization task.' 'INFO'
                Write-Host 'Completed Windows Update Optimization task.' -ForegroundColor Green
                return $true
            }
            else {
                Write-Log 'Windows Update optimization skipped by configuration.' 'INFO'
                Write-Host 'Windows Update optimization skipped by configuration.' -ForegroundColor Yellow
                return $false
            }
        }; Description = 'Optimize Windows Update settings and cleanup old files'
    },

    @{ Name = 'EnableSystemMonitoring'; Function = {
            Write-Log 'Starting System Monitoring Setup task.' 'INFO'
            Write-Host 'Starting System Monitoring Setup task.' -ForegroundColor Cyan
            if (-not $global:Config.SkipMonitoringSetup) {
                Enable-SystemMonitoring
                Write-Log 'Completed System Monitoring Setup task.' 'INFO'
                Write-Host 'Completed System Monitoring Setup task.' -ForegroundColor Green
                return $true
            }
            else {
                Write-Log 'System monitoring setup skipped by configuration.' 'INFO'
                Write-Host 'System monitoring setup skipped by configuration.' -ForegroundColor Yellow
                return $false
            }
        }; Description = 'Enable system monitoring services and Sysmon configuration'
    },

    @{ Name = 'SetEventLogging'; Function = {
            Write-Log 'Starting Event Logging Configuration task.' 'INFO'
            Write-Host 'Starting Event Logging Configuration task.' -ForegroundColor Cyan
            if (-not $global:Config.SkipEventLogging) {
                Set-EventLogging
                Write-Log 'Completed Event Logging Configuration task.' 'INFO'
                Write-Host 'Completed Event Logging Configuration task.' -ForegroundColor Green
                return $true
            }
            else {
                Write-Log 'Event logging configuration skipped by configuration.' 'INFO'
                Write-Host 'Event logging configuration skipped by configuration.' -ForegroundColor Yellow
                return $false
            }
        }; Description = 'Configure Windows Event Log settings and retention policies'
    },

    @{ Name = 'EnableTelemetryReporting'; Function = {
            Write-Log 'Starting Telemetry Reporting Setup task.' 'INFO'
            Write-Host 'Starting Telemetry Reporting Setup task.' -ForegroundColor Cyan
            if (-not $global:Config.SkipTelemetry) {
                Enable-TelemetryReporting
                Write-Log 'Completed Telemetry Reporting Setup task.' 'INFO'
                Write-Host 'Completed Telemetry Reporting Setup task.' -ForegroundColor Green
                return $true
            }
            else {
                Write-Log 'Telemetry reporting setup skipped by configuration.' 'INFO'
                Write-Host 'Telemetry reporting setup skipped by configuration.' -ForegroundColor Yellow
                return $false
            }
        }; Description = 'Configure Windows telemetry and diagnostic reporting'
    },

    @{ Name = 'WatchSystemResources'; Function = {
            Write-Log 'Starting System Resource Monitoring task.' 'INFO'
            Write-Host 'Starting System Resource Monitoring task.' -ForegroundColor Cyan
            if (-not $global:Config.SkipResourceMonitoring) {
                Watch-SystemResources
                Write-Log 'Completed System Resource Monitoring task.' 'INFO'
                Write-Host 'Completed System Resource Monitoring task.' -ForegroundColor Green
                return $true
            }
            else {
                Write-Log 'System resource monitoring skipped by configuration.' 'INFO'
                Write-Host 'System resource monitoring skipped by configuration.' -ForegroundColor Yellow
                return $false
            }
        }; Description = 'Monitor system resources and generate alerts for high usage'
    },

    @{ Name = 'NewSystemReport'; Function = {
            Write-Log 'Starting System Report Generation task.' 'INFO'
            Write-Host 'Starting System Report Generation task.' -ForegroundColor Cyan
            if (-not $global:Config.SkipReportGeneration) {
                New-SystemReport
                Write-Log 'Completed System Report Generation task.' 'INFO'
                Write-Host 'Completed System Report Generation task.' -ForegroundColor Green
                return $true
            }
            else {
                Write-Log 'System report generation skipped by configuration.' 'INFO'
                Write-Host 'System report generation skipped by configuration.' -ForegroundColor Yellow
                return $false
            }
        }; Description = 'Generate comprehensive system monitoring report'
    },

    @{ Name = 'ClearApplicationCache'; Function = {
            Write-Log 'Starting Application Cache Cleanup task.' 'INFO'
            Write-Host 'Starting Application Cache Cleanup task.' -ForegroundColor Cyan
            if (-not $global:Config.SkipCacheCleanup) {
                Clear-ApplicationCache
                Write-Log 'Completed Application Cache Cleanup task.' 'INFO'
                Write-Host 'Completed Application Cache Cleanup task.' -ForegroundColor Green
                return $true
            }
            else {
                Write-Log 'Application cache cleanup skipped by configuration.' 'INFO'
                Write-Host 'Application cache cleanup skipped by configuration.' -ForegroundColor Yellow
                return $false
            }
        }; Description = 'Clean application caches and temporary data'
    },

    @{ Name = 'RepairBrokenApplications'; Function = {
            Write-Log 'Starting Application Repair task.' 'INFO'
            Write-Host 'Starting Application Repair task.' -ForegroundColor Cyan
            if (-not $global:Config.SkipAppRepair) {
                Repair-BrokenApplications
                Write-Log 'Completed Application Repair task.' 'INFO'
                Write-Host 'Completed Application Repair task.' -ForegroundColor Green
                return $true
            }
            else {
                Write-Log 'Application repair skipped by configuration.' 'INFO'
                Write-Host 'Application repair skipped by configuration.' -ForegroundColor Yellow
                return $false
            }
        }; Description = 'Attempt to repair broken or corrupted applications'
    },

    @{ Name = 'EnableMaintenanceScheduling'; Function = {
            Write-Log 'Starting Maintenance Scheduling Setup task.' 'INFO'
            Write-Host 'Starting Maintenance Scheduling Setup task.' -ForegroundColor Cyan
            if (-not $global:Config.SkipSchedulingSetup) {
                Enable-MaintenanceScheduling
                Write-Log 'Completed Maintenance Scheduling Setup task.' 'INFO'
                Write-Host 'Completed Maintenance Scheduling Setup task.' -ForegroundColor Green
                return $true
            }
            else {
                Write-Log 'Maintenance scheduling setup skipped by configuration.' 'INFO'
                Write-Host 'Maintenance scheduling setup skipped by configuration.' -ForegroundColor Yellow
                return $false
            }
        }; Description = 'Enable automated maintenance scheduling'
    },

    @{ Name = 'CheckScheduledTaskStatus'; Function = {
            Write-Log 'Starting Scheduled Task Status Check task.' 'INFO'
            Write-Host 'Starting Scheduled Task Status Check task.' -ForegroundColor Cyan
            $taskStatus = Get-ScheduledTaskStatus
            if ($taskStatus.Exists) {
                Write-Log "Scheduled task status: $($taskStatus.Status), Next run: $($taskStatus.NextRunTime)" 'INFO'
                Write-Host "Scheduled task status: $($taskStatus.Status), Next run: $($taskStatus.NextRunTime)" -ForegroundColor Green
            }
            else {
                Write-Log 'No scheduled maintenance task found' 'WARN'
                Write-Host 'No scheduled maintenance task found' -ForegroundColor Yellow
            }
            Write-Log 'Completed Scheduled Task Status Check task.' 'INFO'
            Write-Host 'Completed Scheduled Task Status Check task.' -ForegroundColor Green
            return $true
        }; Description = 'Check the status of scheduled maintenance tasks'
    }
)


# ================================================================
# Function: Invoke-Task
# ================================================================
# Purpose: Execute a single task function with standardized logging and error handling
# ================================================================
function Invoke-Task {
    param(
        [string]$TaskName,
        [scriptblock]$Action
    )

    $startTime = Get-Date
    Write-ActionLog -Action "Starting task execution" -Details $TaskName -Category "Task Management" -Status 'START'

    try {
        $result = & $Action
        $endTime = Get-Date
        $duration = ($endTime - $startTime).TotalSeconds

        Write-ActionLog -Action "Task completed successfully" -Details "$TaskName | Duration: ${duration}s" -Category "Task Management" -Status 'SUCCESS'
        return $result
    }
    catch {
        $endTime = Get-Date
        $duration = ($endTime - $startTime).TotalSeconds

        Write-ActionLog -Action "Task execution failed" -Details "$TaskName | Duration: ${duration}s | Error: $_" -Category "Task Management" -Status 'FAILURE'
        return $false
    }
}

# ================================================================
# Function: Use-AllScriptTasks
# ================================================================
# Purpose: Execute all registered maintenance tasks with coordination and supervision
# ================================================================
function Use-AllScriptTasks {
    Write-ActionLog -Action 'Initiating maintenance tasks execution sequence' -Details "Total tasks to execute: $($global:ScriptTasks.Count)" -Category "Task Orchestration" -Status 'START'
    $global:TaskResults = @{}
    $taskIndex = 0
    $totalTasks = $global:ScriptTasks.Count

    foreach ($task in $global:ScriptTasks) {
        $taskIndex++
        $taskName = $task.Name
        $desc = $task.Description

        Write-ActionLog -Action "Preparing task execution" -Details "$taskName ($taskIndex/$totalTasks) - $desc" -Category "Task Execution" -Status 'START'
        Write-Log "[$taskIndex/$totalTasks] Executing task: $taskName - $desc" 'INFO'

        $startTime = Get-Date
        try {
            Write-ActionLog -Action "Starting task function" -Details "$taskName | Function execution beginning" -Category "Task Execution" -Status 'START'
            $result = Invoke-Task $taskName $task.Function
            $endTime = Get-Date
            $duration = ($endTime - $startTime).TotalSeconds

            if ($result) {
                Write-ActionLog -Action "Task completed successfully" -Details "$taskName | Duration: ${duration}s | Result: $result" -Category "Task Execution" -Status 'SUCCESS'
            }
            else {
                Write-ActionLog -Action "Task completed with issues" -Details "$taskName | Duration: ${duration}s | Result: $result" -Category "Task Execution" -Status 'FAILURE'
            }

            Write-Log "[$taskIndex/$totalTasks] Task $taskName completed in $duration seconds - Result: $result" 'SUCCESS'
            $global:TaskResults[$taskName] = @{
                Success     = $result
                Duration    = $duration
                Started     = $startTime
                Ended       = $endTime
                Description = $desc
            }
        }
        catch {
            $endTime = Get-Date
            $duration = ($endTime - $startTime).TotalSeconds
            Write-ActionLog -Action "Task execution failed" -Details "$taskName | Duration: ${duration}s | Error: $_" -Category "Task Execution" -Status 'FAILURE'
            Write-Log "[$taskIndex/$totalTasks] Task $taskName failed after $duration seconds - Error: $_" 'ERROR'
            $global:TaskResults[$taskName] = @{
                Success     = $false
                Duration    = $duration
                Started     = $startTime
                Ended       = $endTime
                Description = $desc
                Error       = $_.ToString()
            }
        }
    }

    # Generate execution summary
    $successfulTasks = ($global:TaskResults.Values | Where-Object { $_.Success }).Count
    $totalTasks = $global:TaskResults.Count
    $totalDuration = ($global:TaskResults.Values | Measure-Object -Property Duration -Sum).Sum

    Write-ActionLog -Action "Task execution sequence completed" -Details "Successful: $successfulTasks/$totalTasks | Total Duration: $([math]::Round($totalDuration, 2))s" -Category "Task Orchestration" -Status 'SUCCESS'
    Write-Log "Maintenance sequence completed: $successfulTasks/$totalTasks tasks successful in $([math]::Round($totalDuration, 2)) seconds" 'SUCCESS'

    return $global:TaskResults
}

# ================================================================
# Function: Get-TaskDependencies
# ================================================================
# Purpose: Determine task execution dependencies and order
# ================================================================
function Get-TaskDependencies {
    param([string]$TaskName)

    # Define task dependencies (example)
    $dependencies = @{
        'SystemInventory'        = @()  # No dependencies
        'SystemRestoreProtection' = @()  # No dependencies
        'RemoveBloatware'        = @('SystemInventory')  # Needs inventory first
        'InstallEssentialApps'   = @()  # Can run anytime
        'UpdateAllPackages'      = @('InstallEssentialApps')  # After essential apps
        'WindowsUpdateCheck'     = @()  # Can run anytime
        'DisableTelemetry'       = @()  # Can run anytime
        'SystemHealthRepair'     = @()  # Can run anytime
        'EventLogAnalysis'       = @()  # Can run anytime
        'PendingRestartCheck'    = @('WindowsUpdateCheck', 'UpdateAllPackages')  # After updates
    }

    return $dependencies[$TaskName] ?? @()
}

# ================================================================
# Function: Test-TaskPrerequisites
# ================================================================
# Purpose: Check if prerequisites are met before executing a task
# ================================================================
function Test-TaskPrerequisites {
    param([string]$TaskName)

    # Example prerequisite checks
    switch ($TaskName) {
        'RemoveBloatware' {
            # Check if inventory exists
            if (-not $global:SystemInventory) {
                Write-Log "Prerequisite failed: System inventory not available for bloatware removal" 'WARN'
                return $false
            }
        }
        'InstallEssentialApps' {
            # Check if running as admin
            if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
                Write-Log "Prerequisite failed: Administrator privileges required for app installation" 'WARN'
                return $false
            }
        }
    }

    return $true
}

# Export functions
Export-ModuleMember -Function Use-AllScriptTasks, Invoke-Task, Get-TaskDependencies, Test-TaskPrerequisites -Variable global:ScriptTasks, global:TaskResults