# Logging.psm1 - Centralized logging module for Windows Maintenance Automation
# Provides comprehensive logging capabilities with configuration support

# Global logging configuration
$global:LoggingConfig = @{
    LogLevel           = 'INFO'
    LogFile            = $null  # Will be set by caller
    EnableColors       = $true
    EnableProgressBars = $true
    MaxLogSizeMB       = 10
    LogRotation        = $true
    DateTimeFormat     = 'HH:mm:ss'
    MessageFormat      = '[{timestamp}] [{level}] [{component}] {message}'
    LogLevels          = @{
        'VERBOSE'  = 0
        'DEBUG'    = 1
        'INFO'     = 2
        'WARN'     = 3
        'ERROR'    = 4
        'SUCCESS'  = 5
        'PROGRESS' = 6
        'ACTION'   = 7
        'COMMAND'  = 8
    }
}

# ================================================================
# Function: Initialize-Logging
# ================================================================
# Purpose: Initialize logging system with configuration loading
# Parameters: $ConfigPath - Path to logging.json config file
# ================================================================
function Initialize-Logging {
    param(
        [string]$ConfigPath
    )

    if (Test-Path $ConfigPath) {
        try {
            $loggingConfig = Get-Content $ConfigPath | ConvertFrom-Json
            # Override defaults with loaded config
            $global:LoggingConfig.LogLevel = $loggingConfig.LogLevel
            $global:LoggingConfig.EnableColors = $loggingConfig.EnableColors
            $global:LoggingConfig.EnableProgressBars = $loggingConfig.EnableProgressBars
            $global:LoggingConfig.MaxLogSizeMB = $loggingConfig.MaxLogSizeMB
            $global:LoggingConfig.LogRotation = $loggingConfig.LogRotation
            $global:LoggingConfig.DateTimeFormat = $loggingConfig.DateTimeFormat
            $global:LoggingConfig.MessageFormat = $loggingConfig.MessageFormat
            $global:LoggingConfig.LogLevels = @{}
        foreach ($key in $loggingConfig.LogLevels.PSObject.Properties.Name) {
            $global:LoggingConfig.LogLevels[$key] = $loggingConfig.LogLevels.$key
        }
            Write-Log "Logging configuration loaded from $ConfigPath" 'INFO' 'Logging'
        }
        catch {
            Write-Log "Error loading logging config from $ConfigPath : $_" 'WARN' 'Logging'
        }
    }
    else {
        Write-Log "No logging config found at $ConfigPath, using defaults" 'INFO' 'Logging'
    }
}

# ================================================================
# Function: Write-Log
# ================================================================
# Purpose: Main logging function with level filtering and file/console output
# Parameters: Message, Level, Component
# ================================================================
function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('DEBUG', 'INFO', 'WARN', 'ERROR', 'SUCCESS', 'PROGRESS', 'ACTION', 'COMMAND', 'VERBOSE')]
        [string]$Level = 'INFO',
        [string]$Component = 'PS1'
    )

    # Check if logging is enabled for this level
    if ($global:LoggingConfig -and $global:LoggingConfig.LogLevels -and $global:LoggingConfig.LogLevels.ContainsKey) {
        $currentLevelValue = $global:LoggingConfig.LogLevels[$global:LoggingConfig.LogLevel]
        $messageLevelValue = $global:LoggingConfig.LogLevels[$Level]
        if ($messageLevelValue -lt $currentLevelValue) {
            return  # Skip logging this message
        }
    }

    $timestamp = Get-Date -Format $global:LoggingConfig.DateTimeFormat
    $logEntry = $global:LoggingConfig.MessageFormat -replace '\{timestamp\}', $timestamp -replace '\{level\}', $Level -replace '\{component\}', $Component -replace '\{message\}', $Message

    # Write to file with enhanced error handling
    try {
        if ($global:LoggingConfig.LogFile) {
            Add-Content -Path $global:LoggingConfig.LogFile -Value $logEntry -ErrorAction SilentlyContinue -Encoding UTF8
        }
    }
    catch {
        # If main log fails, try writing to backup location
        try {
            $backupLog = Join-Path $global:TempFolder "maintenance_backup.log"
            Add-Content -Path $backupLog -Value $logEntry -ErrorAction SilentlyContinue -Encoding UTF8
        }
        catch {
            # Silently continue if all logging fails
        }
    }

    # Write to console with enhanced color coding
    if ($global:LoggingConfig.EnableColors) {
        $color = switch ($Level) {
            'DEBUG' { 'DarkGray' }
            'INFO' { 'White' }
            'WARN' { 'Yellow' }
            'ERROR' { 'Red' }
            'SUCCESS' { 'Green' }
            'PROGRESS' { 'Cyan' }
            'ACTION' { 'Magenta' }
            'COMMAND' { 'DarkCyan' }
            default { 'White' }
        }

        Write-Host $logEntry -ForegroundColor $color
    }
    else {
        Write-Host $logEntry
    }

    # For important actions, also write to host using Write-Output for comprehensive logging
    if ($Level -in @('ACTION', 'COMMAND', 'ERROR', 'SUCCESS')) {
        Write-Output $logEntry
    }
}

# ================================================================
# Function: Write-ActionLog
# ================================================================
# Purpose: Specialized logging for specific actions with detailed context
# Parameters: Action, Details, Category, Status
# ================================================================
function Write-ActionLog {
    param(
        [string]$Action,
        [string]$Details = "",
        [string]$Category = "General",
        [ValidateSet('START', 'SUCCESS', 'FAILURE', 'INFO')]
        [string]$Status = 'INFO'
    )

    # Ensure Status is not null or empty
    if (-not $Status -or $Status -notin @('START', 'SUCCESS', 'FAILURE', 'INFO')) {
        $Status = 'INFO'
    }

    $contextInfo = ""
    if ($Details) {
        $contextInfo = " | Details: $Details"
    }

    $fullMessage = "[$Category] $Action$contextInfo"

    $logLevel = switch ($Status) {
        'START' { 'ACTION' }
        'SUCCESS' { 'SUCCESS' }
        'FAILURE' { 'ERROR' }
        'INFO' { 'INFO' }
        default { 'INFO' }
    }

    Write-Log $fullMessage $logLevel 'PS1'
}

# ================================================================
# Function: Write-CommandLog
# ================================================================
# Purpose: Specialized logging for external command execution
# Parameters: Command, Arguments, Context, Status
# ================================================================
function Write-CommandLog {
    param(
        [string]$Command,
        [string[]]$Arguments = @(),
        [string]$Context = "",
        [ValidateSet('START', 'SUCCESS', 'FAILURE')]
        [string]$Status = 'START'
    )

    $fullCommand = $Command
    if ($Arguments.Count -gt 0) {
        $argString = $Arguments -join " "
        $fullCommand = "$Command $argString"
    }

    $contextInfo = if ($Context) { " | Context: $Context" } else { "" }
    $message = "COMMAND: $fullCommand$contextInfo"

    $logLevel = switch ($Status) {
        'START' { 'COMMAND' }
        'SUCCESS' { 'SUCCESS' }
        'FAILURE' { 'ERROR' }
        default { 'COMMAND' }
    }

    Write-Log $message $logLevel 'PS1'
}

# ================================================================
# Function: Write-TaskProgress
# ================================================================
# Purpose: Displays progress information for long-running tasks
# Parameters: TaskName, PercentComplete, Status
# ================================================================
function Write-TaskProgress {
    param(
        [string]$TaskName,
        [int]$PercentComplete = 0,
        [string]$Status = ""
    )

    if ($global:LoggingConfig.EnableProgressBars) {
        Write-Progress -Activity "Maintenance Task: $TaskName" -Status $Status -PercentComplete $PercentComplete
    }

    if ($global:LoggingConfig.EnableVerboseLogging) {
        Write-Log "Task Progress: $TaskName - $PercentComplete% - $Status" 'PROGRESS' 'Progress'
    }
}

# Export functions
Export-ModuleMember -Function Initialize-Logging, Write-Log, Write-ActionLog, Write-CommandLog, Write-TaskProgress