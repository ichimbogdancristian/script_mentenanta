#Requires -Version 7.0

<#
.SYNOPSIS
    Task Scheduler Module - Core Infrastructure

.DESCRIPTION
    Manages Windows scheduled tasks for automation, including creation, modification,
    and execution of maintenance tasks on schedules.

.NOTES
    Module Type: Core Infrastructure
    Dependencies: Windows Task Scheduler service, Administrator privileges
    Author: Windows Maintenance Automation Project
    Version: 1.0.0
#>

using namespace System.Collections.Generic

#region Public Functions

<#
.SYNOPSIS
    Creates or updates a scheduled maintenance task
    
.DESCRIPTION
    Creates a Windows scheduled task for automated maintenance execution with
    configurable schedule, user context, and execution parameters.
    
.PARAMETER TaskName
    Name of the scheduled task to create
    
.PARAMETER ScriptPath
    Path to the script file to execute
    
.PARAMETER Schedule
    Schedule type: Daily, Weekly, Monthly, AtLogon, AtStartup
    
.PARAMETER Time
    Time to run the task (for Daily, Weekly, Monthly schedules)
    
.PARAMETER DayOfWeek
    Day of week for Weekly schedule (Sunday, Monday, etc.)
    
.PARAMETER DayOfMonth
    Day of month for Monthly schedule (1-31)
    
.PARAMETER RunAsSystem
    Run task as SYSTEM account (highest privileges)
    
.PARAMETER Arguments
    Additional arguments to pass to the script
    
.PARAMETER Force
    Force recreation of existing tasks
    
.EXAMPLE
    $result = New-MaintenanceTask -TaskName "DailyMaintenance" -ScriptPath "C:\Scripts\maintenance.ps1" -Schedule Daily -Time "02:00"
    
.EXAMPLE
    $result = New-MaintenanceTask -TaskName "WeeklyCleanup" -ScriptPath "C:\Scripts\cleanup.ps1" -Schedule Weekly -DayOfWeek Sunday -Time "03:00" -RunAsSystem
#>
function New-MaintenanceTask {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact='Medium')]
    param(
        [Parameter(Mandatory)]
        [string]$TaskName,
        
        [Parameter(Mandatory)]
        [string]$ScriptPath,
        
        [Parameter(Mandatory)]
        [ValidateSet('Daily', 'Weekly', 'Monthly', 'AtLogon', 'AtStartup')]
        [string]$Schedule,
        
        [Parameter()]
        [string]$Time = "02:00",
        
        [Parameter()]
        [ValidateSet('Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday')]
        [string]$DayOfWeek,
        
        [Parameter()]
        [ValidateRange(1, 31)]
        [int]$DayOfMonth = 1,
        
        [Parameter()]
        [switch]$RunAsSystem,
        
        [Parameter()]
        [string]$Arguments,
        
        [Parameter()]
        [switch]$Force
    )
    
    Write-Host "📅 Creating scheduled maintenance task: $TaskName" -ForegroundColor Cyan
    
    $result = @{
        TaskName = $TaskName
        Status = 'Unknown'
        Created = $false
        Updated = $false
        Error = $null
        Details = @{}
    }
    
    try {
        # Validate script path
        if (-not (Test-Path $ScriptPath)) {
            throw "Script file not found: $ScriptPath"
        }
        
        # Check if task already exists
        $existingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        
        if ($existingTask -and -not $Force) {
            Write-Host "  ⚠️  Task '$TaskName' already exists. Use -Force to recreate." -ForegroundColor Yellow
            $result.Status = 'Exists'
            $result.Details = Get-TaskDetails -Task $existingTask
            return $result
        }
        
        if ($existingTask -and $Force) {
            Write-Host "  🔄 Removing existing task..." -ForegroundColor Gray
            Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        }
        
        # Build task components
        $action = New-ScheduledTaskAction -Execute "pwsh.exe" -Argument "-ExecutionPolicy Bypass -File `"$ScriptPath`" $Arguments"
        
        # Create trigger based on schedule
        $trigger = switch ($Schedule) {
            'Daily' { 
                New-ScheduledTaskTrigger -Daily -At $Time
            }
            'Weekly' { 
                if (-not $DayOfWeek) { throw "DayOfWeek parameter required for Weekly schedule" }
                New-ScheduledTaskTrigger -Weekly -WeeksInterval 1 -DaysOfWeek $DayOfWeek -At $Time
            }
            'Monthly' { 
                New-ScheduledTaskTrigger -Monthly -DaysOfMonth $DayOfMonth -At $Time
            }
            'AtLogon' { 
                New-ScheduledTaskTrigger -AtLogon
            }
            'AtStartup' { 
                New-ScheduledTaskTrigger -AtStartup
            }
        }
        
        # Configure principal (user context)
        $principal = if ($RunAsSystem) {
            New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\SYSTEM" -LogonType ServiceAccount -RunLevel Highest
        } else {
            New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest
        }
        
        # Configure settings
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RunOnlyIfNetworkAvailable
        
        # Register the task
        $task = Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description "Automated maintenance task created by Windows Maintenance Script"
        
        if ($task) {
            $result.Status = 'Created'
            $result.Created = $true
            $result.Details = Get-TaskDetails -Task $task
            
            Write-Host "  ✅ Task '$TaskName' created successfully" -ForegroundColor Green
            Write-Host "    📅 Schedule: $Schedule" -ForegroundColor Gray
            
            if ($Schedule -in @('Daily', 'Weekly', 'Monthly')) {
                Write-Host "    ⏰ Time: $Time" -ForegroundColor Gray
            }
            
            if ($Schedule -eq 'Weekly') {
                Write-Host "    📆 Day: $DayOfWeek" -ForegroundColor Gray
            }
            
            if ($RunAsSystem) {
                Write-Host "    👤 User: SYSTEM (elevated)" -ForegroundColor Gray
            }
        } else {
            throw "Task registration returned null"
        }
        
        return $result
    }
    catch {
        $result.Status = 'Error'
        $result.Error = $_.Exception.Message
        Write-Error "Failed to create scheduled task '$TaskName': $_"
        return $result
    }
}

<#
.SYNOPSIS
    Gets information about maintenance scheduled tasks
    
.DESCRIPTION
    Retrieves status and configuration of maintenance-related scheduled tasks.
    
.PARAMETER TaskName
    Specific task name to query (optional)
    
.PARAMETER IncludeSystem
    Include system tasks in results
    
.EXAMPLE
    $tasks = Get-MaintenanceTasks
    
.EXAMPLE
    $task = Get-MaintenanceTasks -TaskName "DailyMaintenance"
#>
function Get-MaintenanceTasks {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$TaskName,
        
        [Parameter()]
        [switch]$IncludeSystem
    )
    
    Write-Host "📋 Retrieving scheduled maintenance tasks..." -ForegroundColor Cyan
    
    try {
        if ($TaskName) {
            # Get specific task
            $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
            if ($task) {
                $taskInfo = Get-TaskDetails -Task $task -IncludeHistory
                Write-Host "  📅 Task: $($task.TaskName)" -ForegroundColor Gray
                Write-Host "    Status: $($taskInfo.State)" -ForegroundColor Gray
                Write-Host "    Last Run: $($taskInfo.LastRunTime)" -ForegroundColor Gray
                Write-Host "    Next Run: $($taskInfo.NextRunTime)" -ForegroundColor Gray
                return $taskInfo
            } else {
                Write-Host "  ❌ Task '$TaskName' not found" -ForegroundColor Red
                return $null
            }
        } else {
            # Get all maintenance-related tasks
            $allTasks = Get-ScheduledTask | Where-Object { 
                $_.Description -like "*maintenance*" -or 
                $_.TaskName -like "*Maintenance*" -or 
                $_.TaskName -like "*Cleanup*" -or
                $_.TaskName -like "*Update*"
            }
            
            if (-not $IncludeSystem) {
                $allTasks = $allTasks | Where-Object { $_.Principal.UserId -notlike "NT AUTHORITY\*" }
            }
            
            $taskList = [List[PSCustomObject]]::new()
            
            foreach ($task in $allTasks) {
                $taskInfo = Get-TaskDetails -Task $task
                $taskList.Add($taskInfo)
                
                $statusIcon = switch ($taskInfo.State) {
                    'Ready' { "✅" }
                    'Running' { "🔄" }
                    'Disabled' { "❌" }
                    default { "❓" }
                }
                
                Write-Host "  $statusIcon $($task.TaskName) ($($taskInfo.State))" -ForegroundColor Gray
            }
            
            Write-Host "  📊 Found $($taskList.Count) maintenance tasks" -ForegroundColor Blue
            return $taskList
        }
    }
    catch {
        Write-Error "Failed to retrieve maintenance tasks: $_"
        throw
    }
}

<#
.SYNOPSIS
    Removes a scheduled maintenance task
    
.DESCRIPTION
    Safely removes a scheduled task with optional backup of configuration.
    
.PARAMETER TaskName
    Name of the task to remove
    
.PARAMETER BackupConfig
    Create backup of task configuration before removal
    
.EXAMPLE
    Remove-MaintenanceTask -TaskName "DailyMaintenance" -BackupConfig
#>
function Remove-MaintenanceTask {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact='High')]
    param(
        [Parameter(Mandatory)]
        [string]$TaskName,
        
        [Parameter()]
        [switch]$BackupConfig
    )
    
    Write-Host "🗑️  Removing scheduled task: $TaskName" -ForegroundColor Yellow
    
    try {
        $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        
        if (-not $task) {
            Write-Host "  ❌ Task '$TaskName' not found" -ForegroundColor Red
            return $false
        }
        
        if ($BackupConfig) {
            Write-Host "  💾 Creating configuration backup..." -ForegroundColor Blue
            $backupPath = "$env:TEMP\TaskBackup_${TaskName}_$(Get-Date -Format 'yyyyMMdd_HHmmss').xml"
            Export-ScheduledTask -TaskName $TaskName | Out-File -FilePath $backupPath -Encoding UTF8
            Write-Host "    📄 Backup saved to: $backupPath" -ForegroundColor Gray
        }
        
        if ($PSCmdlet.ShouldProcess($TaskName, 'Remove Scheduled Task')) {
            Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
            Write-Host "  ✅ Task '$TaskName' removed successfully" -ForegroundColor Green
            return $true
        }
        
        return $false
    }
    catch {
        Write-Error "Failed to remove task '$TaskName': $_"
        return $false
    }
}

<#
.SYNOPSIS
    Runs a scheduled task immediately
    
.DESCRIPTION
    Executes a scheduled task outside of its normal schedule for testing or immediate execution.
    
.PARAMETER TaskName
    Name of the task to run
    
.PARAMETER Wait
    Wait for task completion before returning
    
.PARAMETER TimeoutMinutes
    Maximum time to wait for completion (default: 30 minutes)
    
.EXAMPLE
    Start-MaintenanceTask -TaskName "DailyMaintenance" -Wait
#>
function Start-MaintenanceTask {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$TaskName,
        
        [Parameter()]
        [switch]$Wait,
        
        [Parameter()]
        [int]$TimeoutMinutes = 30
    )
    
    Write-Host "▶️  Starting scheduled task: $TaskName" -ForegroundColor Cyan
    
    try {
        $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        
        if (-not $task) {
            Write-Host "  ❌ Task '$TaskName' not found" -ForegroundColor Red
            return $false
        }
        
        # Start the task
        Start-ScheduledTask -TaskName $TaskName
        Write-Host "  🚀 Task started" -ForegroundColor Green
        
        if ($Wait) {
            Write-Host "  ⏳ Waiting for completion (timeout: ${TimeoutMinutes}m)..." -ForegroundColor Blue
            
            $startTime = Get-Date
            $timeoutTime = $startTime.AddMinutes($TimeoutMinutes)
            
            do {
                Start-Sleep -Seconds 5
                $taskInfo = Get-ScheduledTaskInfo -TaskName $TaskName
                $currentTime = Get-Date
                
                Write-Host "    🔄 Status: $($taskInfo.LastTaskResult) (Running: $($currentTime - $startTime))" -ForegroundColor Gray
                
                if ($currentTime -gt $timeoutTime) {
                    Write-Host "    ⏰ Timeout reached after $TimeoutMinutes minutes" -ForegroundColor Yellow
                    return $false
                }
                
            } while ($taskInfo.LastTaskResult -eq 267009) # SCHED_S_TASK_RUNNING
            
            $duration = $currentTime - $startTime
            $success = $taskInfo.LastTaskResult -eq 0
            
            if ($success) {
                Write-Host "  ✅ Task completed successfully in $($duration.TotalMinutes.ToString('F1')) minutes" -ForegroundColor Green
            } else {
                Write-Host "  ❌ Task completed with error code: $($taskInfo.LastTaskResult)" -ForegroundColor Red
            }
            
            return $success
        }
        
        return $true
    }
    catch {
        Write-Error "Failed to start task '$TaskName': $_"
        return $false
    }
}

#endregion

#region Helper Functions

function Get-TaskDetails {
    param(
        [Parameter(Mandatory)]
        [Microsoft.Management.Infrastructure.CimInstance]$Task,
        
        [Parameter()]
        [switch]$IncludeHistory
    )
    
    try {
        $taskInfo = Get-ScheduledTaskInfo -TaskName $Task.TaskName -ErrorAction SilentlyContinue
        
        $details = @{
            TaskName = $Task.TaskName
            State = $Task.State.ToString()
            Description = $Task.Description
            Author = $Task.Author
            Principal = $Task.Principal.UserId
            RunLevel = $Task.Principal.RunLevel.ToString()
            LastRunTime = if ($taskInfo.LastRunTime -eq (Get-Date '1/1/1899')) { 'Never' } else { $taskInfo.LastRunTime }
            NextRunTime = if ($taskInfo.NextRunTime -eq (Get-Date '1/1/1899')) { 'Not Scheduled' } else { $taskInfo.NextRunTime }
            LastResult = $taskInfo.LastTaskResult
            NumberOfMissedRuns = $taskInfo.NumberOfMissedRuns
        }
        
        # Get trigger information
        if ($Task.Triggers) {
            $details.Triggers = @()
            foreach ($trigger in $Task.Triggers) {
                $triggerInfo = @{
                    Type = $trigger.CimClass.CimClassName
                    Enabled = $trigger.Enabled
                }
                
                # Add schedule-specific details
                if ($trigger.StartBoundary) {
                    $triggerInfo.StartTime = $trigger.StartBoundary
                }
                
                if ($trigger.DaysOfWeek) {
                    $triggerInfo.DaysOfWeek = $trigger.DaysOfWeek
                }
                
                $details.Triggers += $triggerInfo
            }
        }
        
        # Get action information
        if ($Task.Actions) {
            $details.Actions = @()
            foreach ($action in $Task.Actions) {
                $details.Actions += @{
                    Type = $action.CimClass.CimClassName
                    Execute = $action.Execute
                    Arguments = $action.Arguments
                    WorkingDirectory = $action.WorkingDirectory
                }
            }
        }
        
        return [PSCustomObject]$details
    }
    catch {
        Write-Warning "Failed to get task details for '$($Task.TaskName)': $_"
        return @{
            TaskName = $Task.TaskName
            State = 'Unknown'
            Error = $_.Exception.Message
        }
    }
}

function Test-TaskSchedulerService {
    try {
        $service = Get-Service -Name "Schedule" -ErrorAction SilentlyContinue
        return $service -and $service.Status -eq 'Running'
    }
    catch {
        return $false
    }
}

#endregion

# Ensure Task Scheduler service is running
if (-not (Test-TaskSchedulerService)) {
    Write-Warning "Task Scheduler service is not running. Some functions may not work properly."
}

# Export module functions
Export-ModuleMember -Function @(
    'New-MaintenanceTask',
    'Get-MaintenanceTasks', 
    'Remove-MaintenanceTask',
    'Start-MaintenanceTask'
)