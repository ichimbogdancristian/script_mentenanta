#Requires -Version 7.0
# Module Dependencies: ConfigManager.psm1 (for path resolution)

<#
.SYNOPSIS
    Logging Manager Module - Core Infrastructure

.DESCRIPTION
    Comprehensive logging system with structured data collection, multiple output formats,
    log rotation, and integration with the reporting system. Provides centralized logging
    for all maintenance operations with configurable levels and destinations.

.NOTES
    Module Type: Core (Infrastructure)
    Dependencies: ConfigManager
    Author: Windows Maintenance Automation Project
    Version: 2.0.0
#>

using namespace System.Collections.Generic
using namespace System.IO

# Import FileOrganizationManager if available (may not be loaded yet during initialization)
$FileOrgPath = Join-Path $PSScriptRoot 'FileOrganizationManager.psm1'
if (Test-Path $FileOrgPath) {
    try {
        Import-Module $FileOrgPath -Force -ErrorAction SilentlyContinue
    }
    catch {
        Write-Verbose "FileOrganizationManager not available during LoggingManager initialization"
    }
}

#region Module Variables

# Global logging context for session tracking
$script:LoggingContext = @{
    SessionId          = [guid]::NewGuid().ToString()
    StartTime          = Get-Date
    LogPath            = $null
    Config             = $null
    LogBuffer          = [List[hashtable]]::new()
    PerformanceMetrics = @{}
}

#endregion

#region Public Functions

<#
.SYNOPSIS
    Initializes the logging system with configuration

.DESCRIPTION
    Sets up the logging infrastructure, creates log directories, initializes log files,
    and configures the logging context based on the loaded configuration.

.PARAMETER LoggingConfig
    Logging configuration object from ConfigManager

.PARAMETER BaseLogPath
    Base directory for log files (optional, uses config default)

.EXAMPLE
    Initialize-LoggingSystem -LoggingConfig $config
#>
function Initialize-LoggingSystem {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$LoggingConfig,

        [Parameter()]
        [string]$BaseLogPath
    )

    try {
        Write-Verbose "Initializing logging system..."
        
        # Store configuration
        $script:LoggingContext.Config = $LoggingConfig

        # Use FileOrganizationManager for log path if available
        try {
            $script:LoggingContext.LogPath = Get-OrganizedFilePath -FileType 'Log' -FileName 'session.log'
            Write-Verbose "Using organized file path: $($script:LoggingContext.LogPath)"
        }
        catch {
            # Fallback to traditional path if FileOrganizationManager not available
            Write-Verbose "FileOrganizationManager not available, using fallback path"
            if ($BaseLogPath) {
                $logDir = $BaseLogPath
            }
            else {
                $scriptRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
                # Import ConfigManager for path resolution
                $ConfigManagerPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'core\ConfigManager.psm1'
                if (Test-Path $ConfigManagerPath) {
                    Import-Module $ConfigManagerPath -Force -Global
                    $logDir = Get-LogsPath
                }
                else {
                    $logDir = Join-Path $scriptRoot "temp_files\logs"
                }
            }

            # Ensure log directory exists
            if (-not (Test-Path $logDir)) {
                New-Item -Path $logDir -ItemType Directory -Force | Out-Null
            }

            # Set up log file path with session timestamp
            $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
            $logFileName = "maintenance-$timestamp.log"
            $script:LoggingContext.LogPath = Join-Path $logDir $logFileName
        }

        # Perform log rotation if enabled
        if ($LoggingConfig.logging.logRotation) {
            Invoke-LogRotation -LogDirectory $logDir -KeepFiles $LoggingConfig.logging.keepLogFiles
        }

        # Write initial log entry
        Write-LogEntry -Level 'INFO' -Component 'LOGGING' -Message "Logging system initialized - Session: $($script:LoggingContext.SessionId)"
        Write-LogEntry -Level 'INFO' -Component 'LOGGING' -Message "Log file: $($script:LoggingContext.LogPath)"

        Write-Verbose "Logging system initialized successfully"
        return $true
    }
    catch {
        Write-Error "Failed to initialize logging system: $_"
        return $false
    }
}

<#
.SYNOPSIS
    Writes a structured log entry

.DESCRIPTION
    Creates a structured log entry with timestamp, level, component, and message.
    Supports multiple output destinations including console, file, and structured buffer.

.PARAMETER Level
    Log level (DEBUG, INFO, SUCCESS, WARN, ERROR, CRITICAL)

.PARAMETER Component
    Component or module name generating the log entry

.PARAMETER Message
    Log message content

.PARAMETER Data
    Additional structured data to include with the log entry

.PARAMETER OperationId
    Optional operation identifier for tracking related log entries

.EXAMPLE
    Write-LogEntry -Level 'INFO' -Component 'ORCHESTRATOR' -Message 'Starting maintenance tasks'

.EXAMPLE
    Write-LogEntry -Level 'ERROR' -Component 'TYPE2' -Message 'Failed to remove bloatware' -Data @{AppName='TestApp'; Error=$_.Exception.Message}
#>
function Write-LogEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('DEBUG', 'INFO', 'SUCCESS', 'WARN', 'ERROR', 'CRITICAL')]
        [string]$Level,

        [Parameter(Mandatory = $true)]
        [string]$Component,

        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter()]
        [hashtable]$Data = @{},

        [Parameter()]
        [string]$OperationId
    )

    try {
        # Skip if logging level is not enabled
        if ($script:LoggingContext.Config -and 
            $script:LoggingContext.Config.levels.$Level -and 
            -not $script:LoggingContext.Config.levels.$Level.enabled) {
            return
        }

        $timestamp = Get-Date
        $logEntry = @{
            Timestamp   = $timestamp
            Level       = $Level
            Component   = $Component
            Message     = $Message
            Data        = $Data
            OperationId = $OperationId
            SessionId   = $script:LoggingContext.SessionId
            ThreadId    = [System.Threading.Thread]::CurrentThread.ManagedThreadId
        }

        # Add to structured buffer for reporting
        $script:LoggingContext.LogBuffer.Add($logEntry)

        # Console output (if enabled)
        if ($script:LoggingContext.Config.logging.enableConsoleOutput) {
            Write-ConsoleLogEntry -LogEntry $logEntry
        }

        # File output (if enabled)
        if ($script:LoggingContext.Config.logging.enableFileOutput -and $script:LoggingContext.LogPath) {
            Write-FileLogEntry -LogEntry $logEntry
        }

        # Performance tracking for critical operations
        if ($Level -in @('ERROR', 'CRITICAL')) {
            Register-PerformanceMetric
        }
    }
    catch {
        # Fallback to basic console output if logging system fails
        Write-Warning "[$Level] [$Component] $Message"
        Write-Error "LOGGING ERROR: $_"
    }
}

<#
.SYNOPSIS
    Convenience wrapper that enriches log data with optional context

.DESCRIPTION
    Provides a friendly facade for module authors that mirrors the signature
    used across the codebase. Normalizes level names, attaches exception
    details when supplied, and forwards structured data to Write-LogEntry.

.PARAMETER Level
    Log level string (INFO, WARNING, ERROR, DEBUG, SUCCESS, CRITICAL, etc.)

.PARAMETER Component
    Component identifier producing the log entry.

.PARAMETER Message
    Human readable log message.

.PARAMETER Data
    Optional hashtable of additional structured data to capture.

.PARAMETER OpId
    Optional operation identifier for correlating related events.

.PARAMETER Exception
    Optional exception/error record to include in the log metadata.
#>
function Write-DetailedLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Level,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Component,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Message,

        [Parameter()]
        [hashtable]$Data,

        [Parameter()]
        [Alias('OperationId')]
        [string]$OpId,

        [Parameter()]
        [Alias('Error')]
        [System.Management.Automation.ErrorRecord]$Exception
    )

    $normalizedLevel = ($Level ?? 'INFO').ToUpperInvariant()
    switch ($normalizedLevel) {
        'WARNING' { $normalizedLevel = 'WARN' }
        'FATAL' { $normalizedLevel = 'CRITICAL' }
        default { }
    }

    $logData = @{}
    if ($null -ne $Data) {
        if ($Data -is [hashtable]) {
            $logData = $Data.Clone()
        }
        elseif ($Data -is [pscustomobject]) {
            foreach ($property in $Data.PSObject.Properties) {
                $logData[$property.Name] = $property.Value
            }
        }
        else {
            $logData['Value'] = $Data
        }
    }

    if ($Exception) {
        $exceptionMessage = $Exception.Exception.Message
        $exceptionType = $Exception.Exception.GetType().FullName
        $logData['ExceptionMessage'] = $exceptionMessage
        $logData['ExceptionType'] = $exceptionType
        if ($Exception.FullyQualifiedErrorId) {
            $logData['ErrorId'] = $Exception.FullyQualifiedErrorId
        }
        if ($Exception.ScriptStackTrace) {
            $logData['ScriptStackTrace'] = $Exception.ScriptStackTrace
        }
    }

    try {
        Write-LogEntry -Level $normalizedLevel -Component $Component -Message $Message -Data $logData -OperationId $OpId
    }
    catch {
        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        $fallback = "[$timestamp] [$normalizedLevel] [$Component] $Message"
        Write-Warning "Logging fallback: $fallback"
        if ($Exception) {
            Write-Warning "Exception: $($Exception.Exception.Message)"
        }
    }
}

<#
.SYNOPSIS
    Starts performance tracking for an operation

.DESCRIPTION
    Begins timing an operation and returns a performance context object
    for later completion tracking.

.PARAMETER OperationName
    Name of the operation being tracked

.PARAMETER Component
    Component performing the operation

.EXAMPLE
    $perf = Start-PerformanceTracking -OperationName 'BloatwareRemoval' -Component 'TYPE2'
#>
function Start-PerformanceTracking {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$OperationName,

        [Parameter(Mandatory = $true)]
        [string]$Component
    )

    $operationId = [guid]::NewGuid().ToString()
    $startTime = Get-Date

    $performanceContext = @{
        OperationId   = $operationId
        OperationName = $OperationName
        Component     = $Component
        StartTime     = $startTime
    }

    # Store in global tracking
    $script:LoggingContext.PerformanceMetrics[$operationId] = $performanceContext

    Write-LogEntry -Level 'DEBUG' -Component $Component -Message "Started operation: $OperationName" -OperationId $operationId

    return $performanceContext
}

<#
.SYNOPSIS
    Completes performance tracking for an operation

.DESCRIPTION
    Finalizes timing for an operation and logs the performance metrics.

.PARAMETER PerformanceContext
    Performance context object from Start-PerformanceTracking

.PARAMETER Success
    Whether the operation completed successfully

.PARAMETER ResultData
    Additional result data to include in metrics

.EXAMPLE
    Complete-PerformanceTracking -PerformanceContext $perf -Success $true -ResultData @{ItemsProcessed=25}
#>
function Complete-PerformanceTracking {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$PerformanceContext,

        [Parameter()]
        [bool]$Success = $true,

        [Parameter()]
        [hashtable]$ResultData = @{}
    )

    $endTime = Get-Date
    $duration = ($endTime - $PerformanceContext.StartTime).TotalSeconds

    $performanceData = @{
        Duration   = $duration
        Success    = $Success
        EndTime    = $endTime
        ResultData = $ResultData
    }

    # Update stored metrics
    $operationId = $PerformanceContext.OperationId
    if ($script:LoggingContext.PerformanceMetrics.ContainsKey($operationId)) {
        $script:LoggingContext.PerformanceMetrics[$operationId] += $performanceData
    }

    $level = if ($Success) { 'SUCCESS' } else { 'WARN' }
    $message = "Completed operation: $($PerformanceContext.OperationName) in $([math]::Round($duration, 2))s"

    Write-LogEntry -Level $level -Component $PerformanceContext.Component -Message $message -Data $performanceData -OperationId $operationId
}

<#
.SYNOPSIS
    Gets structured log data for reporting

.DESCRIPTION
    Retrieves filtered log entries from the current session for use in reports
    and analysis. Supports filtering by level, component, and time range.

.PARAMETER Level
    Filter by log level

.PARAMETER Component
    Filter by component name

.PARAMETER MinTimestamp
    Minimum timestamp for log entries

.PARAMETER MaxTimestamp
    Maximum timestamp for log entries

.EXAMPLE
    $errors = Get-LogData -Level 'ERROR'
    $typeErrors = Get-LogData -Component 'TYPE2' -Level 'ERROR'
#>
function Get-LogData {
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateSet('DEBUG', 'INFO', 'SUCCESS', 'WARN', 'ERROR', 'CRITICAL')]
        [string]$Level,

        [Parameter()]
        [string]$Component,

        [Parameter()]
        [datetime]$MinTimestamp,

        [Parameter()]
        [datetime]$MaxTimestamp
    )

    $filteredLogs = $script:LoggingContext.LogBuffer

    if ($Level) {
        $filteredLogs = $filteredLogs | Where-Object { $_.Level -eq $Level }
    }

    if ($Component) {
        $filteredLogs = $filteredLogs | Where-Object { $_.Component -eq $Component }
    }

    if ($MinTimestamp) {
        $filteredLogs = $filteredLogs | Where-Object { $_.Timestamp -ge $MinTimestamp }
    }

    if ($MaxTimestamp) {
        $filteredLogs = $filteredLogs | Where-Object { $_.Timestamp -le $MaxTimestamp }
    }

    return $filteredLogs
}

<#
.SYNOPSIS
    Gets performance metrics for reporting

.DESCRIPTION
    Retrieves performance tracking data for all operations in the current session.
    Provides operation timing, success rates, and detailed metrics.

.EXAMPLE
    $metrics = Get-PerformanceMetric
#>
function Get-PerformanceMetric {
    [CmdletBinding()]
    param()

    $completedOperations = $script:LoggingContext.PerformanceMetrics.Values | Where-Object { $_.EndTime }
    
    $summary = @{
        TotalOperations      = $completedOperations.Count
        SuccessfulOperations = ($completedOperations | Where-Object { $_.Success }).Count
        FailedOperations     = ($completedOperations | Where-Object { -not $_.Success }).Count
        TotalDuration        = ($completedOperations | Measure-Object Duration -Sum).Sum
        AverageDuration      = ($completedOperations | Measure-Object Duration -Average).Average
        Operations           = $completedOperations
    }

    return $summary
}

<#
.SYNOPSIS
    Exports log data to various formats

.DESCRIPTION
    Exports the current session's log data to JSON, CSV, or XML formats
    for external analysis and long-term storage.

.PARAMETER OutputPath
    Base path for output files (without extension)

.PARAMETER Format
    Export format (JSON, CSV, XML, or All)

.PARAMETER IncludePerformanceMetrics
    Include performance metrics in the export

.EXAMPLE
    Export-LogData -OutputPath 'C:\Reports\SessionLog' -Format 'All' -IncludePerformanceMetrics
#>
function Export-LogData {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$OutputPath,

        [Parameter()]
        [ValidateSet('JSON', 'CSV', 'XML', 'All')]
        [string]$Format = 'JSON',

        [Parameter()]
        [switch]$IncludePerformanceMetrics
    )

    $baseDir = Split-Path $OutputPath -Parent
    if (-not (Test-Path $baseDir)) {
        New-Item -Path $baseDir -ItemType Directory -Force | Out-Null
    }

    $exportData = @{
        SessionInfo = @{
            SessionId  = $script:LoggingContext.SessionId
            StartTime  = $script:LoggingContext.StartTime
            EndTime    = Get-Date
            LogEntries = $script:LoggingContext.LogBuffer.Count
        }
        LogEntries  = $script:LoggingContext.LogBuffer
    }

    if ($IncludePerformanceMetrics) {
        $exportData.PerformanceMetrics = Get-PerformanceMetric
    }

    $exports = @()

    if ($Format -eq 'All' -or $Format -eq 'JSON') {
        $jsonPath = "$OutputPath.json"
        if ($PSCmdlet.ShouldProcess($jsonPath, "Export logs to JSON")) {
            $exportData | ConvertTo-Json -Depth 10 | Out-File -FilePath $jsonPath -Encoding UTF8
            $exports += $jsonPath
        }
    }

    if ($Format -eq 'All' -or $Format -eq 'CSV') {
        $csvPath = "$OutputPath.csv"
        if ($PSCmdlet.ShouldProcess($csvPath, "Export logs to CSV")) {
            $script:LoggingContext.LogBuffer | Export-Csv -Path $csvPath -NoTypeInformation
            $exports += $csvPath
        }
    }

    if ($Format -eq 'All' -or $Format -eq 'XML') {
        $xmlPath = "$OutputPath.xml"
        if ($PSCmdlet.ShouldProcess($xmlPath, "Export logs to XML")) {
            $exportData | Export-Clixml -Path $xmlPath -Depth 10
            $exports += $xmlPath
        }
    }

    return $exports
}

#endregion

#region Private Functions

<#
.SYNOPSIS
    Writes log entry to console with formatting
#>
function Write-ConsoleLogEntry {
    [CmdletBinding()]
    param([hashtable]$LogEntry)

    if (-not $script:LoggingContext.Config.logging.coloredOutput) {
        $formatString = $script:LoggingContext.Config.formatting.messageFormat
        $formattedMessage = $formatString -replace '\{timestamp\}', $LogEntry.Timestamp.ToString($script:LoggingContext.Config.formatting.dateTimeFormat) `
            -replace '\{level\}', $LogEntry.Level `
            -replace '\{component\}', $LogEntry.Component `
            -replace '\{message\}', $LogEntry.Message
        Write-Information $formattedMessage -InformationAction Continue
        return
    }

    $timestamp = $LogEntry.Timestamp.ToString($script:LoggingContext.Config.formatting.dateTimeFormat)
    $levelIcon = Get-LevelIcon -Level $LogEntry.Level
    
    # Build formatted message for Information stream
    $formattedOutput = "[$timestamp] $levelIcon [$($LogEntry.Component)] $($LogEntry.Message)"
    
    # Choose appropriate output stream based on level
    switch ($LogEntry.Level) {
        'ERROR' { Write-Error $formattedOutput }
        'WARN' { Write-Warning $formattedOutput }
        'INFO' { Write-Information $formattedOutput -InformationAction Continue }
        'DEBUG' { Write-Verbose $formattedOutput }
        default { Write-Information $formattedOutput -InformationAction Continue }
    }

    # Additional data on separate line if present
    if ($LogEntry.Data.Count -gt 0) {
        $dataString = ($LogEntry.Data.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ', '
        Write-Verbose "    Data: $dataString"
    }
}

<#
.SYNOPSIS
    Writes log entry to file
#>
function Write-FileLogEntry {
    [CmdletBinding()]
    param([hashtable]$LogEntry)

    try {
        $formatString = $script:LoggingContext.Config.formatting.messageFormat
        $formattedMessage = $formatString -replace '\{timestamp\}', $LogEntry.Timestamp.ToString($script:LoggingContext.Config.formatting.dateTimeFormat) `
            -replace '\{level\}', $LogEntry.Level `
            -replace '\{component\}', $LogEntry.Component `
            -replace '\{message\}', $LogEntry.Message

        # Add structured data if present
        if ($LogEntry.Data.Count -gt 0) {
            $dataJson = $LogEntry.Data | ConvertTo-Json -Compress
            $formattedMessage += " | Data: $dataJson"
        }

        if ($LogEntry.OperationId) {
            $formattedMessage += " | OpId: $($LogEntry.OperationId)"
        }

        # Simple retry-based file writing to avoid locking conflicts
        $retryCount = 0
        $maxRetries = 5
        $success = $false
        
        while (-not $success -and $retryCount -lt $maxRetries) {
            try {
                Add-Content -Path $script:LoggingContext.LogPath -Value $formattedMessage -Encoding UTF8 -ErrorAction Stop
                $success = $true
            }
            catch [System.IO.IOException] {
                $retryCount++
                if ($retryCount -lt $maxRetries) {
                    Start-Sleep -Milliseconds (50 * $retryCount)  # Progressive delay
                }
                else {
                    Write-Verbose "Failed to write to log after $maxRetries attempts: $_"
                }
            }
        }
    }
    catch {
        Write-Verbose "Failed to write log entry to file: $_"
    }
}

<#
.SYNOPSIS
    Gets icon for log level
#>
function Get-LevelIcon {
    param([string]$Level)
    
    switch ($Level) {
        'DEBUG' { return '🔍' }
        'INFO' { return 'ℹ️' }
        'SUCCESS' { return '✅' }
        'WARN' { return '⚠️' }
        'ERROR' { return '❌' }
        'CRITICAL' { return '🚨' }
        default { return '•' }
    }
}

<#
.SYNOPSIS
    Performs log rotation
#>
function Invoke-LogRotation {
    [CmdletBinding()]
    param(
        [string]$LogDirectory,
        [int]$KeepFiles
    )

    try {
        $logFiles = Get-ChildItem -Path $LogDirectory -Filter "maintenance-*.log" | Sort-Object LastWriteTime -Descending
        
        if ($logFiles.Count -gt $KeepFiles) {
            $filesToDelete = $logFiles | Select-Object -Skip $KeepFiles
            foreach ($file in $filesToDelete) {
                Remove-Item -Path $file.FullName -Force
                Write-Verbose "Rotated log file: $($file.Name)"
            }
        }
    }
    catch {
        Write-Verbose "Log rotation failed: $_"
    }
}

<#
.SYNOPSIS
    Updates performance metrics tracking
#>
function Register-PerformanceMetric {
    [CmdletBinding()]
    param()

    # Track error patterns and performance issues
    # This could be expanded for more sophisticated monitoring
}

#endregion

# Export module functions
<#
.SYNOPSIS
    Creates a module-specific log file for Type 2 modules

.DESCRIPTION
    Sets up individual log files for Type 2 modules to track their specific operations
    like installs, uninstalls, deletions, and configuration changes.

.PARAMETER Component
    The module component name (BLOATWARE, APPS, UPDATES, OPTIMIZATION, TELEMETRY)

.PARAMETER SessionTimestamp
    The session timestamp to use for consistent naming

.EXAMPLE
    New-ModuleLogFile -Component 'BLOATWARE' -SessionTimestamp '20241012-110054'
#>
function New-ModuleLogFile {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('BLOATWARE', 'APPS', 'UPDATES', 'OPTIMIZATION', 'TELEMETRY')]
        [string]$Component,

        [Parameter()]
        [string]$SessionTimestamp
    )

    if (-not $script:LoggingContext.Config.logging.enableModuleSpecificLogs) {
        Write-Verbose "Module-specific logging is disabled"
        return $null
    }

    if (-not $SessionTimestamp) {
        $SessionTimestamp = if ($env:MAINTENANCE_SESSION_TIMESTAMP) {
            $env:MAINTENANCE_SESSION_TIMESTAMP
        }
        else {
            Get-Date -Format "yyyyMMdd-HHmmss"
        }
    }

    # Create module-specific log file using organized file system
    $moduleLogMap = @{
        'BLOATWARE'    = 'bloatware-removal'
        'APPS'         = 'essential-apps'
        'UPDATES'      = 'windows-updates'
        'OPTIMIZATION' = 'system-optimization'
        'TELEMETRY'    = 'telemetry-disable'
    }

    $logFileName = "$($moduleLogMap[$Component]).log"
    
    try {
        $moduleLogPath = Get-OrganizedFilePath -FileType 'Log' -Category 'modules' -FileName $logFileName
        Write-Verbose "Using organized module log path: $moduleLogPath"
    }
    catch {
        # Fallback to traditional path
        Write-Verbose "FileOrganizationManager not available, using fallback for module logs"
        $scriptRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
        # Use ConfigManager for path resolution if available
        try {
            $logDir = Get-LogsPath
        }
        catch {
            $logDir = Join-Path $scriptRoot "temp_files\logs"
        }
        if (-not (Test-Path $logDir)) {
            New-Item -Path $logDir -ItemType Directory -Force | Out-Null
        }
        $moduleLogPath = Join-Path $logDir "$($moduleLogMap[$Component])-$SessionTimestamp.log"
    }

    # Initialize module log with header
    $header = @"
Windows Maintenance Automation - $Component Module Log
Session ID: $($script:LoggingContext.SessionId)
Session Start: $($script:LoggingContext.StartTime.ToString("yyyy-MM-dd HH:mm:ss"))
Module: $Component
Component: $($script:LoggingContext.Config.components.$Component)
===============================================

"@

    $header | Out-File -FilePath $moduleLogPath -Encoding UTF8

    Write-LogEntry -Level 'INFO' -Component 'LOGGING' -Message "Created module log file: $logFileName" -Data @{
        Component = $Component
        LogPath   = $moduleLogPath
    }

    return $moduleLogPath
}

<#
.SYNOPSIS
    Writes an entry specifically to a module log file

.DESCRIPTION
    Writes structured log entries to both the main log and a module-specific log file.

.PARAMETER Component
    The module component name

.PARAMETER Level
    Log level

.PARAMETER Message
    Log message

.PARAMETER Operation
    Specific operation being performed (Install, Uninstall, Delete, Configure, etc.)

.PARAMETER Target
    Target of the operation (app name, service name, registry key, etc.)

.PARAMETER Success
    Whether the operation succeeded

.PARAMETER Details
    Additional operation details

.EXAMPLE
    Write-ModuleLogEntry -Component 'BLOATWARE' -Level 'INFO' -Message 'Removing bloatware app' -Operation 'Uninstall' -Target 'Microsoft.BingWeather' -Success $true
#>
function Write-ModuleLogEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('BLOATWARE', 'APPS', 'UPDATES', 'OPTIMIZATION', 'TELEMETRY')]
        [string]$Component,

        [Parameter(Mandatory = $true)]
        [ValidateSet('DEBUG', 'INFO', 'SUCCESS', 'WARN', 'ERROR', 'CRITICAL')]
        [string]$Level,

        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter()]
        [string]$Operation,

        [Parameter()]
        [string]$Target,

        [Parameter()]
        [bool]$Success,

        [Parameter()]
        [hashtable]$Details = @{}
    )

    # Build structured data
    $logData = $Details.Clone()
    if ($Operation) { $logData.Operation = $Operation }
    if ($Target) { $logData.Target = $Target }
    if ($PSBoundParameters.ContainsKey('Success')) { $logData.Success = $Success }

    # Write to main log
    Write-LogEntry -Level $Level -Component $Component -Message $Message -Data $logData

    # Write to module-specific log if enabled
    if ($script:LoggingContext.Config.logging.enableModuleSpecificLogs) {
        $moduleLogMap = @{
            'BLOATWARE'    = 'bloatware-removal'
            'APPS'         = 'essential-apps'
            'UPDATES'      = 'windows-updates'
            'OPTIMIZATION' = 'system-optimization'
            'TELEMETRY'    = 'telemetry-disable'
        }

        $sessionTimestamp = if ($env:MAINTENANCE_SESSION_TIMESTAMP) {
            $env:MAINTENANCE_SESSION_TIMESTAMP
        }
        else {
            Get-Date -Format "yyyyMMdd-HHmmss"
        }

        $logFileName = "$($moduleLogMap[$Component])-$sessionTimestamp.log"
        $scriptRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
        $moduleLogPath = Join-Path $scriptRoot "temp_files\logs\$logFileName"

        if (Test-Path $moduleLogPath) {
            $timestamp = Get-Date -Format $script:LoggingContext.Config.formatting.dateTimeFormat
            $formattedEntry = "[$timestamp] [$Level] $Message"
            
            if ($Operation) { $formattedEntry += " | Operation: $Operation" }
            if ($Target) { $formattedEntry += " | Target: $Target" }
            if ($PSBoundParameters.ContainsKey('Success')) { $formattedEntry += " | Success: $Success" }
            if ($Details.Count -gt 0) { $formattedEntry += " | Details: $($Details | ConvertTo-Json -Compress)" }

            # Simple retry-based file writing for module logs
            $retryCount = 0
            $maxRetries = 3
            $success = $false
            
            while (-not $success -and $retryCount -lt $maxRetries) {
                try {
                    Add-Content -Path $moduleLogPath -Value $formattedEntry -Encoding UTF8 -ErrorAction Stop
                    $success = $true
                }
                catch [System.IO.IOException] {
                    $retryCount++
                    if ($retryCount -lt $maxRetries) {
                        Start-Sleep -Milliseconds (25 * $retryCount)
                    }
                    else {
                        Write-Verbose "Failed to write to module log after $maxRetries attempts: $_"
                    }
                }
            }
        }
    }
}

#endregion

#region File Locking Functions

<#
.SYNOPSIS
    Acquires a file lock for safe concurrent access

.DESCRIPTION
    Creates a mutex-based file lock to prevent concurrent access to critical files
    like logs and configuration files. Uses a combination of file locks and mutexes.

.PARAMETER FilePath
    The path to the file to lock

.PARAMETER TimeoutSeconds
    Maximum time to wait for the lock (default: 30 seconds)

.EXAMPLE
    $lockHandle = Get-FileLock -FilePath "C:\temp\logfile.txt"
    if ($lockHandle) {
        # Perform file operations
        Unlock-FileLock -LockHandle $lockHandle
    }

.OUTPUTS
    [hashtable] Lock handle containing mutex and file stream, or $null if failed
#>
function Get-FileLock {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$FilePath,

        [Parameter()]
        [ValidateRange(1, 300)]
        [int]$TimeoutSeconds = 30
    )

    try {
        Write-Verbose "Attempting to acquire file lock for: $FilePath"
        
        # Create a unique mutex name based on the file path
        $mutexName = "Global\FileAccess_" + ($FilePath -replace '[\\/:*?"<>|]', '_')
        $mutex = [System.Threading.Mutex]::new($false, $mutexName)
        
        # Try to acquire the mutex
        if ($mutex.WaitOne([TimeSpan]::FromSeconds($TimeoutSeconds))) {
            Write-Verbose "✓ Mutex acquired for: $FilePath"
            
            # Ensure parent directory exists
            $parentDir = Split-Path -Parent $FilePath
            if ($parentDir -and -not (Test-Path $parentDir)) {
                New-Item -Path $parentDir -ItemType Directory -Force | Out-Null
            }
            
            # Create or open the file with exclusive access
            try {
                $fileStream = [System.IO.FileStream]::new(
                    $FilePath,
                    [System.IO.FileMode]::OpenOrCreate,
                    [System.IO.FileAccess]::ReadWrite,
                    [System.IO.FileShare]::None
                )
                
                Write-Verbose "✓ File lock acquired for: $FilePath"
                
                return @{
                    Mutex      = $mutex
                    FileStream = $fileStream
                    FilePath   = $FilePath
                    AcquiredAt = Get-Date
                }
            }
            catch {
                Write-Warning "Failed to acquire file stream lock for $FilePath : $_"
                $mutex.ReleaseMutex()
                $mutex.Dispose()
                return $null
            }
        }
        else {
            Write-Warning "Failed to acquire mutex for $FilePath within $TimeoutSeconds seconds"
            $mutex.Dispose()
            return $null
        }
    }
    catch {
        Write-Warning "Failed to create file lock for $FilePath : $_"
        return $null
    }
}

<#
.SYNOPSIS
    Releases a previously acquired file lock

.DESCRIPTION
    Properly releases both the file stream and mutex components of a file lock.

.PARAMETER LockHandle
    The lock handle returned from Get-FileLock

.EXAMPLE
    Unlock-FileLock -LockHandle $lockHandle
#>
function Unlock-FileLock {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [hashtable]$LockHandle
    )

    if ($null -eq $LockHandle) {
        Write-Verbose "Lock handle is null, nothing to release"
        return
    }

    try {
        Write-Verbose "Releasing file lock for: $($LockHandle.FilePath)"
        
        # Close file stream first
        if ($LockHandle.FileStream) {
            try {
                $LockHandle.FileStream.Close()
                $LockHandle.FileStream.Dispose()
                Write-Verbose "✓ File stream released for: $($LockHandle.FilePath)"
            }
            catch {
                Write-Warning "Failed to close file stream: $_"
            }
        }
        
        # Release mutex
        if ($LockHandle.Mutex) {
            try {
                $LockHandle.Mutex.ReleaseMutex()
                $LockHandle.Mutex.Dispose()
                Write-Verbose "✓ Mutex released for: $($LockHandle.FilePath)"
            }
            catch {
                Write-Warning "Failed to release mutex: $_"
            }
        }
        
        # Calculate lock duration for diagnostics
        if ($LockHandle.AcquiredAt) {
            $duration = (Get-Date) - $LockHandle.AcquiredAt
            Write-Verbose "Lock held for: $([math]::Round($duration.TotalSeconds, 2)) seconds"
        }
    }
    catch {
        Write-Warning "Error releasing file lock: $_"
    }
}

<#
.SYNOPSIS
    Executes a script block with file locking

.DESCRIPTION
    Safely executes a script block while holding a file lock, ensuring proper cleanup.

.PARAMETER FilePath
    The path to the file to lock

.PARAMETER ScriptBlock
    The script block to execute while holding the lock

.PARAMETER TimeoutSeconds
    Maximum time to wait for the lock (default: 30 seconds)

.EXAMPLE
    Invoke-WithFileLock -FilePath "C:\temp\config.json" -ScriptBlock {
        $content = Get-Content $FilePath | ConvertFrom-Json
        $content.LastModified = Get-Date
        $content | ConvertTo-Json | Set-Content $FilePath
    }

.OUTPUTS
    The result of the script block execution, or $null if lock acquisition failed
#>
function Invoke-WithFileLock {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$FilePath,

        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock,

        [Parameter()]
        [ValidateRange(1, 300)]
        [int]$TimeoutSeconds = 30
    )

    $lockHandle = $null
    try {
        Write-Verbose "Executing with file lock for: $FilePath"
        
        $lockHandle = Get-FileLock -FilePath $FilePath -TimeoutSeconds $TimeoutSeconds
        if ($null -eq $lockHandle) {
            Write-Warning "Failed to acquire file lock for: $FilePath"
            return $null
        }
        
        # Execute the script block
        $result = & $ScriptBlock
        Write-Verbose "✓ Script block executed successfully with file lock"
        return $result
    }
    catch {
        Write-Error "Error executing script block with file lock: $_"
        return $null
    }
    finally {
        if ($lockHandle) {
            Unlock-FileLock -LockHandle $lockHandle
        }
    }
}

#endregion

Export-ModuleMember -Function @(
    'Initialize-LoggingSystem',
    'Write-LogEntry',
    'Write-DetailedLog',
    'Start-PerformanceTracking',
    'Complete-PerformanceTracking',
    'Get-LogData',
    'Get-PerformanceMetric',
    'Export-LogData',
    'New-ModuleLogFile',
    'Write-ModuleLogEntry',
    'Get-FileLock',
    'Unlock-FileLock',
    'Invoke-WithFileLock'
)