# LoggingManager Module
# Handles all logging operations with configurable levels and formats

function Initialize-Logger {
    <#
    .SYNOPSIS
    Initializes the logging system with specified configuration.
    
    .PARAMETER LogPath
    Directory path where log files will be stored.
    
    .PARAMETER LogLevel
    Minimum log level (Debug, Info, Warning, Error).
    
    .PARAMETER RetentionDays
    Number of days to retain log files.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$LogPath,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet("Debug", "Info", "Warning", "Error")]
        [string]$LogLevel = "Info",
        
        [Parameter(Mandatory = $false)]
        [int]$RetentionDays = 30
    )
    
    try {
        # Create log directory if it doesn't exist
        if (-not (Test-Path $LogPath)) {
            New-Item -Path $LogPath -ItemType Directory -Force | Out-Null
        }
        
        # Set global variables for logging
        $Global:LogPath = $LogPath
        $Global:LogLevel = $LogLevel
        $Global:LogRetentionDays = $RetentionDays
        $Global:LogFile = Join-Path $LogPath "maintenance_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
        
        # Clean old log files
        Remove-OldLogFiles -LogPath $LogPath -RetentionDays $RetentionDays
        
        Write-LogMessage -Level "Info" -Message "Logging initialized. Log file: $Global:LogFile"
    }
    catch {
        Write-Error "Failed to initialize logging: $($_.Exception.Message)"
        throw
    }
}

function Write-LogMessage {
    <#
    .SYNOPSIS
    Writes a message to both console and log file.
    
    .PARAMETER Level
    Log level (Debug, Info, Warning, Error).
    
    .PARAMETER Message
    Message to log.
    
    .PARAMETER Exception
    Optional exception object for error logging.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("Debug", "Info", "Warning", "Error")]
        [string]$Level,
        
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [Parameter(Mandatory = $false)]
        [System.Exception]$Exception
    )
    
    # Check if we should log this level
    $levelPriority = @{
        "Debug" = 0
        "Info" = 1
        "Warning" = 2
        "Error" = 3
    }
    
    if ($levelPriority[$Level] -lt $levelPriority[$Global:LogLevel]) {
        return
    }
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    
    if ($Exception) {
        $logEntry += " | Exception: $($Exception.Message)"
    }
    
    # Write to console
    switch ($Level) {
        "Debug" { Write-Verbose $Message }
        "Info" { Write-Host $Message -ForegroundColor Green }
        "Warning" { Write-Warning $Message }
        "Error" { Write-Error $Message }
    }
    
    # Write to log file
    if ($Global:LogFile) {
        try {
            Add-Content -Path $Global:LogFile -Value $logEntry -ErrorAction Stop
        }
        catch {
            Write-Warning "Failed to write to log file: $($_.Exception.Message)"
        }
    }
}

function Remove-OldLogFiles {
    <#
    .SYNOPSIS
    Removes log files older than specified retention period.
    #>
    [CmdletBinding()]
    param(
        [string]$LogPath,
        [int]$RetentionDays
    )
    
    try {
        $cutoffDate = (Get-Date).AddDays(-$RetentionDays)
        $oldLogs = Get-ChildItem -Path $LogPath -Filter "*.log" | Where-Object { $_.LastWriteTime -lt $cutoffDate }
        
        foreach ($log in $oldLogs) {
            Remove-Item -Path $log.FullName -Force
            Write-LogMessage -Level "Info" -Message "Removed old log file: $($log.Name)"
        }
    }
    catch {
        Write-LogMessage -Level "Warning" -Message "Failed to clean old log files: $($_.Exception.Message)"
    }
}

function Start-TaskLogging {
    <#
    .SYNOPSIS
    Starts logging for a specific maintenance task.
    
    .PARAMETER TaskName
    Name of the task being started.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TaskName
    )
    
    $Global:CurrentTask = $TaskName
    $Global:TaskStartTime = Get-Date
    
    Write-LogMessage -Level "Info" -Message "=== Starting Task: $TaskName ==="
}

function Stop-TaskLogging {
    <#
    .SYNOPSIS
    Stops logging for the current task and reports execution time.
    
    .PARAMETER Success
    Whether the task completed successfully.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [bool]$Success
    )
    
    if ($Global:CurrentTask -and $Global:TaskStartTime) {
        $duration = (Get-Date) - $Global:TaskStartTime
        $status = if ($Success) { "COMPLETED" } else { "FAILED" }
        
        Write-LogMessage -Level "Info" -Message "=== Task: $Global:CurrentTask $status (Duration: $($duration.ToString('mm\:ss'))) ==="
        
        $Global:CurrentTask = $null
        $Global:TaskStartTime = $null
    }
}

Export-ModuleMember -Function Initialize-Logger, Write-LogMessage, Start-TaskLogging, Stop-TaskLogging
