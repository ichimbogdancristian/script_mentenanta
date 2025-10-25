#Requires -Version 7.0

<#
.SYNOPSIS
    Logging System Module - Specialized structured logging and performance tracking

.DESCRIPTION
    Extracted logging component from CoreInfrastructure.psm1.
    Provides structured logging with multiple output formats, performance tracking,
    operation context, and configurable verbosity levels.

.NOTES
    Module Type: Core Infrastructure (Logging Specialist)
    Dependencies: None
    Extracted from: CoreInfrastructure.psm1
    Version: 1.0.0
    Architecture: v3.0
#>

using namespace System.Collections.Generic
using namespace System.IO

#region Private Variables

# Logging configuration cache
$script:LoggingConfig = @{
    Enabled = $true
    DefaultLevel = 'INFO'
    DefaultLogPath = $null
    PerformanceTracking = @{}
    OperationContexts = @{}
}

#endregion

#region Logging Initialization

<#
.SYNOPSIS
    Initializes the logging system

.DESCRIPTION
    Sets up logging configuration, defaults, and performance tracking.

.PARAMETER DefaultLogPath
    Default path for log files

.PARAMETER Verbosity
    Default verbosity level (INFO, DEBUG, WARN, ERROR, SUCCESS)
#>
function Initialize-LoggingSystem {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$DefaultLogPath,
        
        [Parameter(Mandatory = $false)]
        [string]$Verbosity = 'INFO'
    )
    
    Write-Verbose "Initializing Logging System"
    
    $script:LoggingConfig.DefaultLogPath = $DefaultLogPath
    $script:LoggingConfig.DefaultLevel = $Verbosity
    $script:LoggingConfig.Enabled = $true
    
    Write-Verbose "Logging system initialized with verbosity: $Verbosity"
}

#endregion

#region Core Logging Functions

<#
.SYNOPSIS
    Main unified logging function for all module operations

.DESCRIPTION
    Provides comprehensive logging with support for text, structured, and JSON formats.
    Includes optional operation context, metrics, and additional data.

.PARAMETER Level
    Log level (INFO, DEBUG, WARN, ERROR, SUCCESS)

.PARAMETER Message
    Primary log message

.PARAMETER Component
    Component/module name logging the message

.PARAMETER AdditionalData
    Optional hashtable of additional context data

.PARAMETER LogPath
    Path to write log file (uses default if not specified)

.PARAMETER Operation
    Optional operation name for context tracking

.PARAMETER Target
    Optional target of the operation

.PARAMETER Result
    Optional operation result

.PARAMETER Metrics
    Optional performance metrics

.PARAMETER EnableJsonLogging
    If $true, also write JSON-formatted log entry
#>
function Write-ModuleLogEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('DEBUG', 'INFO', 'SUCCESS', 'WARN', 'ERROR')]
        [string]$Level,
        
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [Parameter(Mandatory = $true)]
        [string]$Component,
        
        [Parameter(Mandatory = $false)]
        [hashtable]$AdditionalData,
        
        [Parameter(Mandatory = $false)]
        [string]$LogPath,
        
        [Parameter(Mandatory = $false)]
        [string]$Operation,
        
        [Parameter(Mandatory = $false)]
        [string]$Target,
        
        [Parameter(Mandatory = $false)]
        [string]$Result,
        
        [Parameter(Mandatory = $false)]
        [hashtable]$Metrics,
        
        [Parameter(Mandatory = $false)]
        [switch]$EnableJsonLogging
    )
    
    if (-not $script:LoggingConfig.Enabled) {
        return
    }
    
    try {
        # Use provided log path or default
        if (-not $LogPath) {
            $LogPath = $script:LoggingConfig.DefaultLogPath
        }
        
        # Format timestamp
        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        
        # Build text log entry
        $textEntry = "[$timestamp] [$Level] [$Component] $Message"
        
        # Add operation context if provided
        if ($Operation) {
            $textEntry += " [Operation: $Operation]"
        }
        
        if ($Target) {
            $textEntry += " [Target: $Target]"
        }
        
        if ($Result) {
            $textEntry += " [Result: $Result]"
        }
        
        # Write to console with appropriate color
        $consoleColor = switch ($Level) {
            'DEBUG' { 'DarkGray' }
            'INFO' { 'White' }
            'SUCCESS' { 'Green' }
            'WARN' { 'Yellow' }
            'ERROR' { 'Red' }
            default { 'White' }
        }
        Write-Host $textEntry -ForegroundColor $consoleColor
        
        # Write to log file if path provided
        if ($LogPath) {
            # Ensure directory exists
            $logDir = Split-Path -Parent $LogPath
            if (-not (Test-Path $logDir)) {
                New-Item -Path $logDir -ItemType Directory -Force | Out-Null
            }
            
            # Write text entry
            Add-Content -Path $LogPath -Value $textEntry -Encoding UTF8
            
            # Write JSON entry if enabled
            if ($EnableJsonLogging) {
                $jsonEntry = @{
                    Timestamp = $timestamp
                    Level = $Level
                    Component = $Component
                    Message = $Message
                    Operation = $Operation
                    Target = $Target
                    Result = $Result
                    Metrics = $Metrics
                    AdditionalData = $AdditionalData
                } | ConvertTo-Json -Compress
                
                $jsonLogPath = $LogPath -replace '\.log$', '-data.json'
                Add-Content -Path $jsonLogPath -Value $jsonEntry -Encoding UTF8
            }
        }
        
        # Write additional data if provided
        if ($AdditionalData -and $AdditionalData.Count -gt 0) {
            foreach ($key in $AdditionalData.Keys) {
                $additionalEntry = "  └─ $key`: $($AdditionalData[$key])"
                Write-Host $additionalEntry -ForegroundColor DarkGray
                
                if ($LogPath) {
                    Add-Content -Path $LogPath -Value $additionalEntry -Encoding UTF8
                }
            }
        }
    }
    catch {
        Write-Warning "Failed to write log entry: $($_.Exception.Message)"
    }
}

<#
.SYNOPSIS
    Writes a log entry for operation start

.PARAMETER Operation
    Operation name

.PARAMETER Component
    Component performing the operation

.PARAMETER LogPath
    Path to log file
#>
function Write-OperationStart {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Operation,
        
        [Parameter(Mandatory = $true)]
        [string]$Component,
        
        [Parameter(Mandatory = $false)]
        [string]$LogPath
    )
    
    Write-ModuleLogEntry -Level 'INFO' -Message "Starting: $Operation" `
        -Component $Component -Operation $Operation -LogPath $LogPath
}

<#
.SYNOPSIS
    Writes a log entry for successful operation completion

.PARAMETER Operation
    Operation name

.PARAMETER Component
    Component name

.PARAMETER Message
    Completion message

.PARAMETER LogPath
    Path to log file
#>
function Write-OperationSuccess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Operation,
        
        [Parameter(Mandatory = $true)]
        [string]$Component,
        
        [Parameter(Mandatory = $false)]
        [string]$Message = 'Completed successfully',
        
        [Parameter(Mandatory = $false)]
        [string]$LogPath
    )
    
    Write-ModuleLogEntry -Level 'SUCCESS' -Message "$Message" `
        -Component $Component -Operation $Operation -LogPath $LogPath
}

<#
.SYNOPSIS
    Writes a log entry for operation failure

.PARAMETER Operation
    Operation name

.PARAMETER Component
    Component name

.PARAMETER ErrorMessage
    Error message

.PARAMETER Exception
    Optional exception object

.PARAMETER LogPath
    Path to log file
#>
function Write-OperationFailure {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Operation,
        
        [Parameter(Mandatory = $true)]
        [string]$Component,
        
        [Parameter(Mandatory = $true)]
        [string]$ErrorMessage,
        
        [Parameter(Mandatory = $false)]
        [System.Exception]$Exception,
        
        [Parameter(Mandatory = $false)]
        [string]$LogPath
    )
    
    $message = "Failed: $ErrorMessage"
    if ($Exception) {
        $message += " | Exception: $($Exception.Message)"
    }
    
    Write-ModuleLogEntry -Level 'ERROR' -Message $message `
        -Component $Component -Operation $Operation -LogPath $LogPath
}

#endregion

#region Performance Tracking

<#
.SYNOPSIS
    Starts performance tracking for an operation

.PARAMETER OperationName
    Name of the operation to track

.PARAMETER Component
    Component performing the operation

.OUTPUTS
    Context object for tracking
#>
function Start-PerformanceTracking {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$OperationName,
        
        [Parameter(Mandatory = $true)]
        [string]$Component
    )
    
    $context = @{
        OperationName = $OperationName
        Component = $Component
        StartTime = Get-Date
        EndTime = $null
        Duration = $null
        DurationMs = $null
    }
    
    $contextId = [guid]::NewGuid().ToString()
    $script:LoggingConfig.PerformanceTracking[$contextId] = $context
    
    Write-ModuleLogEntry -Level 'DEBUG' -Message "Performance tracking started for: $OperationName" `
        -Component $Component
    
    return $contextId
}

<#
.SYNOPSIS
    Completes performance tracking and returns duration metrics

.PARAMETER ContextId
    Context ID returned from Start-PerformanceTracking

.OUTPUTS
    Hashtable with performance metrics
#>
function Complete-PerformanceTracking {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ContextId
    )
    
    $context = $script:LoggingConfig.PerformanceTracking[$ContextId]
    
    if (-not $context) {
        Write-Warning "Performance tracking context not found: $ContextId"
        return @{ DurationMs = 0 }
    }
    
    $context.EndTime = Get-Date
    $context.Duration = $context.EndTime - $context.StartTime
    $context.DurationMs = $context.Duration.TotalMilliseconds
    
    Write-ModuleLogEntry -Level 'DEBUG' `
        -Message "Performance tracking completed for: $($context.OperationName) - Duration: $($context.DurationMs)ms" `
        -Component $context.Component `
        -Metrics @{ DurationMs = $context.DurationMs }
    
    # Clean up
    $script:LoggingConfig.PerformanceTracking.Remove($ContextId)
    
    return @{
        OperationName = $context.OperationName
        DurationMs = $context.DurationMs
        Duration = $context.Duration
        StartTime = $context.StartTime
        EndTime = $context.EndTime
    }
}

#endregion

#region Logging Configuration

<#
.SYNOPSIS
    Gets current logging configuration

.OUTPUTS
    Hashtable with logging settings
#>
function Get-LoggingConfiguration {
    [CmdletBinding()]
    param()
    
    return $script:LoggingConfig.Clone()
}

<#
.SYNOPSIS
    Sets logging verbosity level

.PARAMETER Level
    Verbosity level to set
#>
function Set-LoggingVerbosity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('DEBUG', 'INFO', 'WARN', 'ERROR')]
        [string]$Level
    )
    
    $script:LoggingConfig.DefaultLevel = $Level
    Write-Verbose "Logging verbosity set to: $Level"
}

<#
.SYNOPSIS
    Enables or disables logging

.PARAMETER Enable
    Whether to enable logging
#>
function Set-LoggingEnabled {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [bool]$Enable
    )
    
    $script:LoggingConfig.Enabled = $Enable
    Write-Verbose "Logging enabled: $Enable"
}

#endregion

#region Module Exports

Export-ModuleMember -Function @(
    'Initialize-LoggingSystem',
    'Write-ModuleLogEntry',
    'Write-OperationStart',
    'Write-OperationSuccess',
    'Write-OperationFailure',
    'Start-PerformanceTracking',
    'Complete-PerformanceTracking',
    'Get-LoggingConfiguration',
    'Set-LoggingVerbosity',
    'Set-LoggingEnabled'
)

#endregion
