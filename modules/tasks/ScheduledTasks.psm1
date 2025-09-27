# ScheduledTasks.psm1 - Windows scheduled tasks management
# Contains functions for creating, managing, and monitoring scheduled tasks

# ================================================================
# Function: New-MaintenanceScheduledTask
# ================================================================
# Purpose: Create a scheduled task for automated maintenance
# ================================================================
function New-MaintenanceScheduledTask {
    [CmdletBinding()]
    param(
        [string]$TaskName = "WindowsMaintenance",
        [string]$Description = "Automated Windows maintenance tasks",
        [string]$ScriptPath,
        [string]$Schedule = "Weekly", # Daily, Weekly, Monthly
        [int]$Interval = 1, # Every X days/weeks/months
        [string]$StartTime = "02:00", # 2 AM by default
        [switch]$RunAsSystem,
        [switch]$RunWithHighestPrivileges,
        [switch]$WakeToRun,
        [switch]$RunMissedTasks
    )

    Write-Log "Creating scheduled maintenance task: $TaskName" 'INFO'

    try {
        # Determine script path if not provided
        if (-not $ScriptPath) {
            $ScriptPath = Join-Path $PSScriptRoot "..\..\MaintenanceLauncher.ps1"
        }

        if (-not (Test-Path $ScriptPath)) {
            Write-Log "Script path not found: $ScriptPath" 'ERROR'
            return $false
        }

        # Build schtasks command arguments
        $arguments = @()

        # Task creation
        $arguments += "/Create"
        $arguments += "/TN"
        $arguments += "`"$TaskName`""
        $arguments += "/TR"
        $arguments += "`"pwsh.exe -ExecutionPolicy Bypass -File `"$ScriptPath`"`""

        # Schedule type
        switch ($Schedule.ToLower()) {
            "daily" {
                $arguments += "/SC"
                $arguments += "DAILY"
                if ($Interval -gt 1) {
                    $arguments += "/MO"
                    $arguments += $Interval.ToString()
                }
            }
            "weekly" {
                $arguments += "/SC"
                $arguments += "WEEKLY"
                $arguments += "/D"
                $arguments += "SUN" # Run on Sunday
                if ($Interval -gt 1) {
                    $arguments += "/MO"
                    $arguments += $Interval.ToString()
                }
            }
            "monthly" {
                $arguments += "/SC"
                $arguments += "MONTHLY"
                $arguments += "/MO"
                $arguments += "FIRST"
                $arguments += "/D"
                $arguments += "1" # First day of month
            }
            default {
                Write-Log "Invalid schedule type: $Schedule. Using weekly." 'WARN'
                $arguments += "/SC"
                $arguments += "WEEKLY"
                $arguments += "/D"
                $arguments += "SUN"
            }
        }

        # Start time
        $arguments += "/ST"
        $arguments += $StartTime

        # Run as
        if ($RunAsSystem) {
            $arguments += "/RU"
            $arguments += "SYSTEM"
        }
        else {
            $arguments += "/RU"
            $arguments += $env:USERNAME
        }

        # Additional options
        if ($RunWithHighestPrivileges) {
            $arguments += "/RL"
            $arguments += "HIGHEST"
        }

        if ($WakeToRun) {
            $arguments += "/WAKE"
        }

        if ($RunMissedTasks) {
            $arguments += "/RI"
            $arguments += "10" # Retry every 10 minutes
            $arguments += "/DU"
            $arguments += "1H" # For 1 hour
        }

        # Description
        $arguments += "/F" # Force overwrite if exists
        $arguments += "/Z" # Delete task after run (for testing)

        # Execute schtasks command
        $command = "schtasks.exe"
        $argumentString = $arguments -join " "

        Write-Log "Executing: $command $argumentString" 'DEBUG'

        $result = & $command $arguments 2>&1

        if ($LASTEXITCODE -eq 0) {
            Write-Log "Scheduled task '$TaskName' created successfully" 'SUCCESS'
            return $true
        }
        else {
            Write-Log "Failed to create scheduled task: $result" 'ERROR'
            return $false
        }
    }
    catch {
        Write-Log "Critical error creating scheduled task: $_" 'ERROR'
        return $false
    }
}

# ================================================================
# Function: Get-ScheduledTaskStatus
# ================================================================
# Purpose: Check the status of scheduled tasks
# ================================================================
function Get-ScheduledTaskStatus {
    [CmdletBinding()]
    param(
        [string]$TaskName = "WindowsMaintenance"
    )

    Write-Log "Checking scheduled task status: $TaskName" 'INFO'

    try {
        $result = schtasks.exe /Query /TN $TaskName /FO CSV /NH 2>$null

        if ($LASTEXITCODE -eq 0) {
            # Parse CSV output
            $taskInfo = $result | ConvertFrom-Csv
            Write-Log "Task '$TaskName' found. Status: $($taskInfo.Status), Next Run: $($taskInfo.'Next Run Time')" 'INFO'
            return @{
                Exists = $true
                Status = $taskInfo.Status
                NextRunTime = $taskInfo.'Next Run Time'
                LastRunTime = $taskInfo.'Last Run Time'
                LastResult = $taskInfo.'Last Result'
            }
        }
        else {
            Write-Log "Scheduled task '$TaskName' not found" 'WARN'
            return @{
                Exists = $false
                Status = "Not Found"
                NextRunTime = $null
                LastRunTime = $null
                LastResult = $null
            }
        }
    }
    catch {
        Write-Log "Error checking scheduled task status: $_" 'ERROR'
        return $null
    }
}

# ================================================================
# Function: Remove-MaintenanceScheduledTask
# ================================================================
# Purpose: Remove a scheduled maintenance task
# ================================================================
function Remove-MaintenanceScheduledTask {
    [CmdletBinding()]
    param(
        [string]$TaskName = "WindowsMaintenance"
    )

    Write-Log "Removing scheduled task: $TaskName" 'INFO'

    try {
        $result = schtasks.exe /Delete /TN $TaskName /F 2>&1

        if ($LASTEXITCODE -eq 0) {
            Write-Log "Scheduled task '$TaskName' removed successfully" 'SUCCESS'
            return $true
        }
        else {
            Write-Log "Failed to remove scheduled task: $result" 'ERROR'
            return $false
        }
    }
    catch {
        Write-Log "Critical error removing scheduled task: $_" 'ERROR'
        return $false
    }
}

# ================================================================
# Function: Enable-MaintenanceScheduling
# ================================================================
# Purpose: Enable automated maintenance scheduling
# ================================================================
function Enable-MaintenanceScheduling {
    [CmdletBinding()]
    param(
        [string]$TaskName = "WindowsMaintenance",
        [string]$Schedule = "Weekly",
        [string]$StartTime = "02:00",
        [switch]$RunAsSystem
    )

    Write-Log "Enabling automated maintenance scheduling..." 'INFO'

    try {
        # Check if task already exists
        $taskStatus = Get-ScheduledTaskStatus -TaskName $TaskName

        if ($taskStatus.Exists) {
            Write-Log "Scheduled task '$TaskName' already exists. Removing old task first." 'INFO'
            Remove-MaintenanceScheduledTask -TaskName $TaskName
        }

        # Create new scheduled task
        $scriptPath = Join-Path $PSScriptRoot "..\..\MaintenanceLauncher.ps1"

        $result = New-MaintenanceScheduledTask -TaskName $TaskName `
                                              -Description "Automated Windows maintenance tasks" `
                                              -ScriptPath $scriptPath `
                                              -Schedule $Schedule `
                                              -StartTime $StartTime `
                                              -RunAsSystem:$RunAsSystem `
                                              -RunWithHighestPrivileges `
                                              -WakeToRun `
                                              -RunMissedTasks

        if ($result) {
            Write-Log "Automated maintenance scheduling enabled successfully" 'SUCCESS'
            return $true
        }
        else {
            Write-Log "Failed to enable automated maintenance scheduling" 'ERROR'
            return $false
        }
    }
    catch {
        Write-Log "Critical error enabling maintenance scheduling: $_" 'ERROR'
        return $false
    }
}

# ================================================================
# Function: Disable-MaintenanceScheduling
# ================================================================
# Purpose: Disable automated maintenance scheduling
# ================================================================
function Disable-MaintenanceScheduling {
    [CmdletBinding()]
    param(
        [string]$TaskName = "WindowsMaintenance"
    )

    Write-Log "Disabling automated maintenance scheduling..." 'INFO'

    try {
        $result = Remove-MaintenanceScheduledTask -TaskName $TaskName

        if ($result) {
            Write-Log "Automated maintenance scheduling disabled successfully" 'SUCCESS'
            return $true
        }
        else {
            Write-Log "Failed to disable automated maintenance scheduling" 'ERROR'
            return $false
        }
    }
    catch {
        Write-Log "Critical error disabling maintenance scheduling: $_" 'ERROR'
        return $false
    }
}

# ================================================================
# Function: Test-ScheduledTaskExecution
# ================================================================
# Purpose: Test scheduled task execution manually
# ================================================================
function Test-ScheduledTaskExecution {
    [CmdletBinding()]
    param(
        [string]$TaskName = "WindowsMaintenance"
    )

    Write-Log "Testing scheduled task execution: $TaskName" 'INFO'

    try {
        $result = schtasks.exe /Run /TN $TaskName 2>&1

        if ($LASTEXITCODE -eq 0) {
            Write-Log "Scheduled task '$TaskName' execution started successfully" 'SUCCESS'
            return $true
        }
        else {
            Write-Log "Failed to start scheduled task execution: $result" 'ERROR'
            return $false
        }
    }
    catch {
        Write-Log "Critical error testing scheduled task execution: $_" 'ERROR'
        return $false
    }
}

# ================================================================
# Function: Get-ScheduledTaskHistory
# ================================================================
# Purpose: Get execution history of scheduled tasks
# ================================================================
function Get-ScheduledTaskHistory {
    [CmdletBinding()]
    param(
        [string]$TaskName = "WindowsMaintenance",
        [int]$LastRuns = 5
    )

    Write-Log "Retrieving scheduled task history: $TaskName" 'INFO'

    try {
        # Use wevtutil to query event logs for scheduled task events
        $events = Get-WinEvent -LogName "Microsoft-Windows-TaskScheduler/Operational" -MaxEvents 100 -ErrorAction SilentlyContinue |
            Where-Object { $_.Message -like "*$TaskName*" } |
            Select-Object -First $LastRuns

        $history = @()
        foreach ($evt in $events) {
            $history += @{
                Time = $evt.TimeCreated
                EventId = $evt.Id
                Message = $evt.Message
                Level = $evt.LevelDisplayName
            }
        }

        Write-Log "Retrieved $($history.Count) historical events for task '$TaskName'" 'INFO'
        return $history
    }
    catch {
        Write-Log "Error retrieving scheduled task history: $_" 'ERROR'
        return @()
    }
}

# Export functions
Export-ModuleMember -Function New-MaintenanceScheduledTask, Get-ScheduledTaskStatus, Remove-MaintenanceScheduledTask, Enable-MaintenanceScheduling, Disable-MaintenanceScheduling, Test-ScheduledTaskExecution, Get-ScheduledTaskHistory