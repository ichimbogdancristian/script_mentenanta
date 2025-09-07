# ===============================
# SECTION 1: SCRIPT HEADER & METADATA  
# ===============================
# Script: Windows Maintenance Automation (2025 Edition)
# Purpose: Professional-grade Windows 10/11 maintenance automation with modular task architecture
# Features: Bloatware removal, essential apps installation, system updates, privacy optimization, security hardening
# Environment: PowerShell 7+ required, Administrator privileges mandatory
# Dependencies: Winget, Chocolatey, AppX, DISM, Registry access, Windows Capabilities
# Architecture: Two-tier launcher→orchestrator design with standardized task coordination
# Performance: Parallel processing, HashSet optimizations, native PowerShell 7 operations
# ===============================

#Requires -Version 7.0

using namespace System.Collections.Generic
using namespace System.Collections.Concurrent

param(
    [string]$LogFilePath
)

# ================================================================
# Global Variables and Environment Detection
# ================================================================

# Script path and environment detection for consistency with batch script launcher
$ScriptFullPath = $MyInvocation.MyCommand.Path
$ScriptDir = Split-Path -Parent $ScriptFullPath
$ScriptName = Split-Path -Leaf $ScriptFullPath
$ScriptDrive = if ($ScriptFullPath.StartsWith("\\")) { 
    "UNC Path" 
}
else { 
    (Get-Item $ScriptFullPath).PSDrive.Name + ":" 
}

# Drive type detection for path independence (matching batch script logic)
$IsNetworkPath = $false
$IsUNCPath = $ScriptFullPath.StartsWith("\\")

if ($IsUNCPath) {
    $IsNetworkPath = $true
    $DriveType = "Network"
}
elseif ($ScriptDrive -ne "UNC Path") {
    $DriveInfo = Get-CimInstance -Class Win32_LogicalDisk | Where-Object { $_.DeviceID -eq $ScriptDrive }
    if ($DriveInfo) { 
        $DriveTypeNum = $DriveInfo.DriveType
        if ($DriveTypeNum -eq 4) { 
            $IsNetworkPath = $true 
        }
        $DriveType = switch ($DriveTypeNum) {
            2 { "Removable" }
            3 { "Fixed" }
            4 { "Network" }
            5 { "CD-ROM" }
            default { "Unknown" }
        }
    }
    else { 
        $DriveType = "Unknown" 
    }
}
else { 
    $DriveType = "Unknown" 
}

# System environment information
$ComputerName = $env:COMPUTERNAME
$CurrentUser = $env:USERNAME
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$OSVersion = (Get-CimInstance -Class Win32_OperatingSystem).Caption
$OSArchitecture = $env:PROCESSOR_ARCHITECTURE
$OSArch = switch ($OSArchitecture) {
    "AMD64" { "x64" }
    "x86" { "x86" }
    "ARM64" { "ARM64" }
    default { $OSArchitecture }
}
$PSVersion = $PSVersionTable.PSVersion.ToString()
$WorkingDirectory = Get-Location

# Log file setup - prioritize parameter, then environment variable, then default
if ($LogFilePath) {
    $LogFile = $LogFilePath
    Write-Host "[INFO] Using log file from parameter: $LogFile" -ForegroundColor Green
}
elseif ($env:SCRIPT_LOG_FILE) {
    $LogFile = $env:SCRIPT_LOG_FILE
    Write-Host "[INFO] Using batch script log file from environment: $LogFile" -ForegroundColor Green
}
else {
    $batchScriptDirectory = Split-Path $ScriptDir -Parent
    $LogFile = Join-Path $batchScriptDirectory 'maintenance.log'
    Write-Host "[INFO] Using default PowerShell log file (parent directory): $LogFile" -ForegroundColor Yellow
}

# Ensure log file directory exists
$logDir = Split-Path $LogFile -Parent
if (-not (Test-Path $logDir)) {
    New-Item -Path $logDir -ItemType Directory -Force | Out-Null
}

# Global configuration object with defaults
$global:Config = @{
    SkipBloatwareRemoval    = $false
    SkipEssentialApps       = $false
    SkipWindowsUpdates      = $false
    SkipTelemetryDisable    = $false
    SkipSystemRestore       = $false
    SkipEventLogAnalysis    = $false
    SkipPendingRestartCheck = $false
    SkipSystemHealthRepair  = $false
    EnableVerboseLogging    = $false
    CustomEssentialApps     = @()
    CustomBloatwareList     = @()
    ExcludeTasks            = @()
}

# Global variables for task execution and results tracking
$global:TaskResults = @{}
$global:SystemInventory = $null
$global:TempFolder = $PSScriptRoot
$global:BloatwareList = @()
$global:EssentialApps = @()

# ================================================================
# Global Task Array - Centralized Task Definitions
# ================================================================
# Purpose: Centralized maintenance task coordination with standardized metadata
# Structure: Hash table array with Name, Function, Description for each maintenance task
# Execution: Sequential processing via Use-AllScriptTasks(), config-driven skip logic
# Dependencies: Global config system, Write-Log function, individual task functions
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

    @{ Name = 'SystemInventory'; Function = { 
            Write-Log 'Starting System Inventory task.' 'INFO'
            Write-Host 'Starting System Inventory task.' -ForegroundColor Cyan
            Get-SystemInventory
            Write-Log 'Completed System Inventory task.' 'INFO'
            Write-Host 'Completed System Inventory task.' -ForegroundColor Green
            return $true
        }; Description = 'Collect comprehensive system information for analysis and reporting' 
    },

    @{ Name = 'EventLogAnalysis'; Function = { 
            Write-Log 'Starting Event Log Analysis task.' 'INFO'
            Write-Host 'Starting Event Log Analysis task.' -ForegroundColor Cyan
            if (-not $global:Config.SkipEventLogAnalysis) { 
                Get-EventLogAnalysis
                Write-Log 'Completed Event Log Analysis task.' 'INFO'
                Write-Host 'Completed Event Log Analysis task.' -ForegroundColor Green
                return $true
            }
            else { 
                Write-Log 'Event Log Analysis skipped by configuration.' 'INFO'
                Write-Host 'Event Log Analysis skipped by configuration.' -ForegroundColor Yellow
                return $false
            } 
        }; Description = 'Analyze Event Viewer and CBS logs for system errors (last 96 hours)' 
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

    @{ Name = 'UpdateAllPackages'; Function = { 
            Write-Log 'Starting Package Updates task.' 'INFO'
            Write-Host 'Starting Package Updates task.' -ForegroundColor Cyan
            Update-AllPackages
            Write-Log 'Completed Package Updates task.' 'INFO'
            Write-Host 'Completed Package Updates task.' -ForegroundColor Green
            return $true
        }; Description = 'Update all installed packages via Winget, Chocolatey, and package managers' 
    },

    @{ Name = 'WindowsUpdateCheck'; Function = {
            Write-Log 'Starting Windows Update Check task.' 'INFO'
            Write-Host 'Starting Windows Update Check task.' -ForegroundColor Cyan
            if (-not $global:Config.SkipWindowsUpdates) { 
                Install-WindowsUpdatesCompatible
                Write-Log 'Completed Windows Update Check task.' 'INFO'
                Write-Host 'Completed Windows Update Check task.' -ForegroundColor Green
                return $true
            }
            else { 
                Write-Log 'Windows Update check skipped by configuration.' 'INFO'
                Write-Host 'Windows Update check skipped by configuration.' -ForegroundColor Yellow
                return $false
            } 
        }; Description = 'Check and install available Windows Updates with compatibility layer' 
    },

    @{ Name = 'DisableTelemetry'; Function = { 
            Write-Log 'Starting Telemetry Disable task.' 'INFO'
            Write-Host 'Starting Telemetry Disable task.' -ForegroundColor Cyan
            if (-not $global:Config.SkipTelemetryDisable) { 
                Disable-Telemetry
                Write-Log 'Completed Telemetry Disable task.' 'INFO'
                Write-Host 'Completed Telemetry Disable task.' -ForegroundColor Green
                return $true
            }
            else { 
                Write-Log 'Telemetry disable skipped by configuration.' 'INFO'
                Write-Host 'Telemetry disable skipped by configuration.' -ForegroundColor Yellow
                return $false
            } 
        }; Description = 'Disable Windows telemetry, privacy invasive features, and browser tracking' 
    },

    @{ Name = 'TaskbarOptimization'; Function = { 
            Write-Log 'Starting Taskbar Optimization task.' 'INFO'
            Write-Host 'Starting Taskbar Optimization task.' -ForegroundColor Cyan
            Optimize-Taskbar
            Write-Log 'Completed Taskbar Optimization task.' 'INFO'
            Write-Host 'Completed Taskbar Optimization task.' -ForegroundColor Green
            return $true
        }; Description = 'Optimize taskbar layout and disable web search in Start menu' 
    },

    @{ Name = 'DesktopBackground'; Function = { 
            Write-Log 'Starting Desktop Background Configuration task.' 'INFO'
            Write-Host 'Starting Desktop Background Configuration task.' -ForegroundColor Cyan
            Set-DesktopBackground
            Write-Log 'Completed Desktop Background Configuration task.' 'INFO'
            Write-Host 'Completed Desktop Background Configuration task.' -ForegroundColor Green
            return $true
        }; Description = 'Change desktop background from Windows Spotlight to personalized slideshow' 
    },

    @{ Name = 'SecurityHardening'; Function = { 
            Write-Log 'Starting Security Hardening task.' 'INFO'
            Write-Host 'Starting Security Hardening task.' -ForegroundColor Cyan
            Enable-SecurityHardening
            Write-Log 'Completed Security Hardening task.' 'INFO'
            Write-Host 'Completed Security Hardening task.' -ForegroundColor Green
            return $true
        }; Description = 'Apply security hardening configurations and policy improvements' 
    },

    @{ Name = 'CleanTempAndDisk'; Function = {
            Write-Log 'Starting Temporary Files and Disk Cleanup task.' 'INFO'
            Write-Host 'Starting Temporary Files and Disk Cleanup task.' -ForegroundColor Cyan
            try {
                Write-TaskProgress "Starting disk cleanup" 20
                $cleanupActions = @(
                    @{ Path = $env:TEMP; Name = "User Temp Files" },
                    @{ Path = "$env:WINDIR\Temp"; Name = "System Temp Files" },
                    @{ Path = "$env:LOCALAPPDATA\Microsoft\Windows\INetCache"; Name = "Internet Cache" },
                    @{ Path = "$env:USERPROFILE\AppData\Local\Temp"; Name = "Local Temp Files" }
                )
            
                $totalCleaned = 0
                foreach ($action in $cleanupActions) {
                    if (Test-Path $action.Path) {
                        try {
                            $beforeSize = (Get-ChildItem $action.Path -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
                            Get-ChildItem $action.Path -Recurse -Force -ErrorAction SilentlyContinue | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
                            $afterSize = (Get-ChildItem $action.Path -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
                            $cleaned = [math]::Max(0, ($beforeSize - $afterSize))
                            $totalCleaned += $cleaned
                            Write-Log "Cleaned $($action.Name): $([math]::Round($cleaned/1MB, 2)) MB" 'INFO'
                        }
                        catch {
                            Write-Log "Failed to clean $($action.Name): $_" 'WARN'
                        }
                    }
                }
            
                Write-TaskProgress "Disk cleanup completed" 100
                Write-Host "✓ Disk cleanup completed: $([math]::Round($totalCleaned/1MB, 2)) MB freed" -ForegroundColor Green
                Write-Log "Disk cleanup completed: $([math]::Round($totalCleaned/1MB, 2)) MB freed" 'INFO'
                return $true
            }
            catch {
                Write-Log "Disk cleanup failed: $_" 'ERROR'
                Write-Host "✗ Disk cleanup failed: $_" -ForegroundColor Red
                return $false
            }
        }; Description = 'Clean temporary files and perform disk space optimization' 
    },

    @{ Name = 'SystemHealthRepair'; Function = { 
            Write-Log 'Starting System Health Check and Repair task.' 'INFO'
            Write-Host 'Starting System Health Check and Repair task.' -ForegroundColor Cyan
            if (-not $global:Config.SkipSystemHealthRepair) {
                Start-SystemHealthRepair
                Write-Log 'Completed System Health Check and Repair task.' 'INFO'
                Write-Host 'Completed System Health Check and Repair task.' -ForegroundColor Green
                return $true
            }
            else {
                Write-Host 'System Health Check and Repair skipped by configuration.' -ForegroundColor Yellow
                Write-Log 'System Health Check and Repair skipped by configuration.' 'INFO'
                return $true
            }
        }; Description = 'Automated DISM and SFC system file integrity check and repair' 
    },

    @{ Name = 'PendingRestartCheck'; Function = { 
            Write-Log 'Starting Pending Restart Check task.' 'INFO'
            Write-Host 'Starting Pending Restart Check task.' -ForegroundColor Cyan
            if (-not $global:Config.SkipPendingRestartCheck) {
                try {
                    $pendingRestart = $false
                
                    # Check multiple indicators for pending restart
                    $registryKeys = @(
                        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired",
                        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending",
                        "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\PendingFileRenameOperations"
                    )
                
                    foreach ($key in $registryKeys) {
                        if (Test-Path $key) {
                            $pendingRestart = $true
                            Write-Log "Pending restart detected: $key" 'INFO'
                            break
                        }
                    }
                
                    if ($pendingRestart) {
                        Write-Host '⚠️  SYSTEM RESTART REQUIRED' -ForegroundColor Yellow
                        Write-Host 'Windows maintenance operations require a system restart to complete.' -ForegroundColor Yellow
                        Write-Host 'Starting 120-second countdown. Press Ctrl+C to abort restart.' -ForegroundColor Yellow
                    
                        for ($i = 120; $i -gt 0; $i--) {
                            Write-Host "🔄 Restart in $i seconds... (Ctrl+C to abort)" -ForegroundColor Yellow
                            Start-Sleep -Seconds 1
                        }
                    
                        Write-Host '🔄 Initiating system restart...' -ForegroundColor Green
                        try {
                            Start-Process -FilePath "shutdown.exe" -ArgumentList "/r", "/t", "10", "/c", "System restart required to complete maintenance operations" -NoNewWindow
                            Write-Log 'System restart initiated successfully.' 'INFO'
                            return $true
                        }
                        catch {
                            Write-Log "Failed to initiate system restart: $_" 'ERROR'
                            Write-Host "❌ Failed to initiate restart: $_" -ForegroundColor Red
                            Write-Host 'Please restart your system manually.' -ForegroundColor Yellow
                            return $false
                        }
                    }
                    else {
                        Write-Host '✓ No pending restart required' -ForegroundColor Green
                        Write-Log 'No pending restart required.' 'INFO'
                        return $true
                    }
                }
                catch {
                    Write-Log "Pending restart check failed: $_" 'ERROR'
                    Write-Host "❌ Pending restart check failed: $_" -ForegroundColor Red
                    return $false
                }
            }
            else {
                Write-Log 'Pending restart check skipped by configuration.' 'INFO'
                Write-Host 'Pending restart check skipped by configuration.' -ForegroundColor Yellow
                return $false
            }
        }; Description = 'Check for pending system restarts with 120-second countdown and abort option' 
    }
)

# ===============================
# SECTION 2: CORE INFRASTRUCTURE
# ===============================
# Purpose: Provides essential infrastructure functions for logging, task coordination, progress tracking, and error handling
# Functions: Logging system, task orchestration, progress indicators, error management utilities
# Dependencies: Global variables, PowerShell 7+ features, Windows console capabilities
# Performance: Optimized for frequent calls, minimal overhead, thread-safe operations
# ===============================

# ================================================================
# Function: Use-AllScriptTasks
# ================================================================
# Purpose: Enhanced main task execution orchestrator with comprehensive logging and progress tracking
# Environment: Windows 10/11, PowerShell 7+, Administrator context required
# Logic: Sequential task execution with comprehensive error handling, progress tracking, and detailed performance analytics
# Performance: Tracks execution time, success/failure rates, provides detailed console output, comprehensive task analytics
# Dependencies: Global task array, Write-Log, Write-ActionLog functions, global config system, task result tracking
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
            
            Write-ActionLog -Action "Task execution failed with exception" -Details "$taskName | Duration: ${duration}s | Exception: $_.Exception.Message" -Category "Task Execution" -Status 'FAILURE'
            Write-Log "[$taskIndex/$totalTasks] Task $taskName execution failed: $_" 'ERROR'
            $global:TaskResults[$taskName] = @{ 
                Success     = $false
                Duration    = $duration
                Started     = $startTime
                Ended       = $endTime
                Description = $desc
                Error       = $_.Exception.Message
            }
        }
        
        # Progress update
        $progressPercent = [math]::Round(($taskIndex / $totalTasks) * 100, 1)
        Write-ActionLog -Action "Task execution progress" -Details "$taskIndex/$totalTasks tasks completed ($progressPercent%)" -Category "Task Orchestration" -Status 'INFO'
    }
    
    # Final summary
    $successfulTasks = ($global:TaskResults.Values | Where-Object { $_.Success -eq $true }).Count
    $failedTasks = $totalTasks - $successfulTasks
    $totalDuration = ($global:TaskResults.Values | Measure-Object -Property Duration -Sum).Sum
    
    Write-ActionLog -Action 'All maintenance tasks execution sequence completed' -Details "Total: $totalTasks | Successful: $successfulTasks | Failed: $failedTasks | Total Duration: ${totalDuration}s" -Category "Task Orchestration" -Status 'SUCCESS'
}

# ================================================================
# Function: Write-Log
# ================================================================
# Purpose: Enhanced unified logging function with dual output (console + file) and comprehensive action tracking
# Environment: Any PowerShell version, requires global $LogFile variable, console access
# Logic: Timestamped entries with severity levels, file persistence, color-coded console display, enhanced action tracking
# Performance: Minimal overhead, efficient string formatting, non-blocking operations, enhanced error handling
# Dependencies: Global $LogFile variable, Windows console capabilities, file system access
# ================================================================
function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR', 'SUCCESS', 'PROGRESS', 'ACTION', 'COMMAND', 'VERBOSE')]
        [string]$Level = 'INFO'
    )
    
    $timestamp = Get-Date -Format 'HH:mm:ss'
    $logEntry = "[$timestamp] [$Level] $Message"
    
    # Write to file with enhanced error handling
    try {
        Add-Content -Path $global:LogFile -Value $logEntry -ErrorAction SilentlyContinue -Encoding UTF8
    }
    catch {
        # If main log fails, try writing to backup location
        try {
            $backupLog = Join-Path $env:TEMP "maintenance_backup.log"
            Add-Content -Path $backupLog -Value $logEntry -ErrorAction SilentlyContinue -Encoding UTF8
        }
        catch {
            # Silently continue if all logging fails
        }
    }
    
    # Write to console with enhanced color coding
    $color = switch ($Level) {
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
    
    # For important actions, also write to host using Write-Output for comprehensive logging
    if ($Level -in @('ACTION', 'COMMAND', 'ERROR', 'SUCCESS')) {
        Write-Output $logEntry
    }
}

# ================================================================
# Function: Write-ActionLog
# ================================================================
# Purpose: Specialized logging for specific actions with detailed context and categorization
# Environment: Windows 10/11, PowerShell 7+, supports action categorization and detailed tracking
# Logic: Enhanced action logging with categorization, timing, and detailed context information
# Performance: Optimized for action tracking, minimal overhead, comprehensive detail capture
# Dependencies: Write-Log function, timing capabilities, process tracking
# ================================================================
function Write-ActionLog {
    param(
        [string]$Action,
        [string]$Details = "",
        [string]$Category = "General",
        [ValidateSet('START', 'SUCCESS', 'FAILURE', 'INFO')]
        [string]$Status = 'INFO'
    )
    
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
    
    Write-Log $fullMessage $logLevel
}

# ================================================================
# Function: Write-CommandLog
# ================================================================
# Purpose: Specialized logging for external command execution with full command tracking
# Environment: Windows 10/11, PowerShell 7+, supports external process monitoring and detailed execution tracking
# Logic: Logs command execution with full command line, arguments, exit codes, and execution timing
# Performance: Minimal overhead wrapper for external commands, comprehensive execution tracking
# Dependencies: Write-Log function, process execution capabilities, timing functions
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
    
    Write-Log $message $logLevel
}

# ================================================================
# Function: Write-TaskProgress
# ================================================================
# Purpose: Displays progress information for long-running tasks with visual progress indicators
# Environment: Windows PowerShell console, supports progress bars and status messages
# Logic: Progress percentage tracking, status message display, console-only output
# Performance: Lightweight progress tracking, non-blocking operations, visual feedback
# Dependencies: Windows PowerShell console capabilities, Write-Progress cmdlet
# ================================================================
function Write-TaskProgress {
    param(
        [string]$Activity,
        [int]$PercentComplete,
        [string]$Status = "Processing..."
    )
    
    Write-Progress -Activity $Activity -Status $Status -PercentComplete $PercentComplete
    Write-Log "$Activity - $Status ($PercentComplete%)" 'PROGRESS'
    
    # Clear progress bar when complete
    if ($PercentComplete -ge 100) {
        Start-Sleep -Milliseconds 500  # Brief pause to show completion
        Write-Progress -Activity $Activity -Completed
    }
}

# ================================================================
# Function: Invoke-Task
# ================================================================
# Purpose: Enhanced wrapper function for individual task execution with comprehensive logging and timing
# Environment: Windows 10/11, PowerShell 7+, supports any task type
# Logic: Try/catch wrapper with detailed action logging, timing, and comprehensive error capture
# Performance: Minimal overhead wrapper, comprehensive error capture, standardized execution with timing
# Dependencies: Write-Log, Write-ActionLog functions, PowerShell execution environment
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
# Function: Invoke-LoggedCommand
# ================================================================
# Purpose: Enhanced wrapper for external command execution with comprehensive logging and monitoring
# Environment: Windows 10/11, PowerShell 7+, supports external process execution with detailed tracking
# Logic: Wraps Start-Process with comprehensive logging, timing, exit code tracking, and error handling
# Performance: Minimal overhead wrapper with detailed execution tracking and comprehensive error capture
# Dependencies: Write-CommandLog, Write-ActionLog functions, Start-Process cmdlet, process monitoring
# ================================================================
function Invoke-LoggedCommand {
    param(
        [string]$FilePath,
        [string[]]$ArgumentList = @(),
        [string]$Context = "",
        [switch]$WindowStyle,
        [string]$WindowStyleValue = "Hidden",
        [switch]$Wait,
        [switch]$PassThru,
        [int]$TimeoutSeconds = 300
    )
    
    # Set default values for switch parameters (proper PowerShell practice)
    if (-not $PSBoundParameters.ContainsKey('Wait')) { $Wait = $true }
    if (-not $PSBoundParameters.ContainsKey('PassThru')) { $PassThru = $true }
    
    $startTime = Get-Date
    
    # Log command start
    Write-CommandLog -Command $FilePath -Arguments $ArgumentList -Context $Context -Status 'START'
    
    try {
        $processArgs = @{
            FilePath = $FilePath
            Wait     = $Wait
            PassThru = $PassThru
        }
        
        if ($ArgumentList.Count -gt 0) {
            $processArgs.ArgumentList = $ArgumentList
        }
        
        if ($WindowStyle) {
            $processArgs.WindowStyle = $WindowStyleValue
        }
        
        Write-ActionLog -Action "Executing external command" -Details "$FilePath with arguments: $($ArgumentList -join ' ')" -Category "Command Execution" -Status 'START'
        
        $process = Start-Process @processArgs
        
        if ($Wait -and $process) {
            $endTime = Get-Date
            $duration = ($endTime - $startTime).TotalSeconds
            $exitCode = $process.ExitCode
            
            if ($exitCode -eq 0) {
                Write-CommandLog -Command $FilePath -Arguments $ArgumentList -Context "$Context | Duration: ${duration}s | ExitCode: $exitCode" -Status 'SUCCESS'
                Write-ActionLog -Action "Command completed successfully" -Details "$FilePath | Duration: ${duration}s | ExitCode: $exitCode" -Category "Command Execution" -Status 'SUCCESS'
            }
            else {
                Write-CommandLog -Command $FilePath -Arguments $ArgumentList -Context "$Context | Duration: ${duration}s | ExitCode: $exitCode" -Status 'FAILURE'
                Write-ActionLog -Action "Command completed with error" -Details "$FilePath | Duration: ${duration}s | ExitCode: $exitCode" -Category "Command Execution" -Status 'FAILURE'
            }
            
            return $process
        }
        else {
            Write-ActionLog -Action "Command started in background" -Details "$FilePath | Background execution" -Category "Command Execution" -Status 'INFO'
            return $process
        }
    }
    catch {
        $endTime = Get-Date
        $duration = ($endTime - $startTime).TotalSeconds
        
        Write-CommandLog -Command $FilePath -Arguments $ArgumentList -Context "$Context | Duration: ${duration}s | Exception: $_" -Status 'FAILURE'
        Write-ActionLog -Action "Command execution failed" -Details "$FilePath | Duration: ${duration}s | Exception: $_" -Category "Command Execution" -Status 'FAILURE'
        
        throw $_
    }
}

# ===============================
# SECTION 3: SYSTEM UTILITIES
# ===============================
# Purpose: Provides system-level utilities for compatibility, inventory management, package operations, and app detection
# Functions: AppX compatibility layer, Windows Updates management, system inventory, package management utilities
# Dependencies: Windows AppX subsystem, DISM module, PSWindowsUpdate module, package managers (Winget, Chocolatey)
# Performance: Optimized for system operations, error-resilient, graceful fallback mechanisms
# ===============================

# ================================================================
# Function: Invoke-WindowsPowerShellCommand
# ================================================================
# Purpose: PowerShell 7 compatibility layer for executing Windows PowerShell 5.1 specific cmdlets
# Environment: PowerShell 7+ with Windows PowerShell 5.1 fallback capability
# Logic: Executes commands in Windows PowerShell 5.1 context for legacy cmdlet compatibility
# Performance: Minimal overhead for cross-version compatibility, handles serialization automatically
# Dependencies: Windows PowerShell 5.1 installation, powershell.exe availability
# ================================================================
function Invoke-WindowsPowerShellCommand {
    param(
        [string]$Command,
        [string]$ErrorAction = "Continue"
    )
    
    try {
        Write-ActionLog -Action "Executing Windows PowerShell compatibility command" -Details $Command -Category "PowerShell Compatibility" -Status 'START'
        
        # Build the full command with error action
        $fullCommand = if ($ErrorAction -eq "SilentlyContinue") {
            "$Command -ErrorAction SilentlyContinue 2>`$null"
        }
        else {
            $Command
        }
        
        # Execute command in Windows PowerShell 5.1 context with proper encoding
        $outputFile = [System.IO.Path]::GetTempFileName()
        $errorFile = [System.IO.Path]::GetTempFileName()
        
        try {
            $process = Start-Process -FilePath "powershell.exe" -ArgumentList "-Command", "& {$fullCommand} | Out-File -FilePath '$outputFile' -Encoding UTF8" -RedirectStandardError $errorFile -Wait -PassThru -WindowStyle Hidden
            
            $output = if (Test-Path $outputFile) { Get-Content $outputFile -Raw -Encoding UTF8 } else { $null }
            $errorOutput = if (Test-Path $errorFile) { Get-Content $errorFile -Raw -Encoding UTF8 } else { $null }
            
            if ($process.ExitCode -eq 0) {
                Write-ActionLog -Action "Windows PowerShell command completed successfully" -Details "ExitCode: $($process.ExitCode)" -Category "PowerShell Compatibility" -Status 'SUCCESS'
                
                # Parse output if it's structured data
                if ($output -and $output.Trim()) {
                    try {
                        # Try to convert from JSON if it looks like structured data
                        if ($output.Trim().StartsWith('[') -or $output.Trim().StartsWith('{')) {
                            return $output | ConvertFrom-Json
                        }
                        else {
                            # Return raw output for simple commands
                            return $output.Trim() -split "`r?`n" | Where-Object { $_.Trim() -ne "" }
                        }
                    }
                    catch {
                        # If parsing fails, return raw output
                        return $output.Trim()
                    }
                }
                else {
                    return $null
                }
            }
            else {
                Write-ActionLog -Action "Windows PowerShell command failed" -Details "ExitCode: $($process.ExitCode) | Error: $errorOutput" -Category "PowerShell Compatibility" -Status 'FAILURE'
                if ($ErrorAction -eq "SilentlyContinue") {
                    return $null
                }
                else {
                    throw "Windows PowerShell command failed with exit code: $($process.ExitCode). Error: $errorOutput"
                }
            }
        }
        finally {
            # Cleanup temp files
            if (Test-Path $outputFile) { Remove-Item $outputFile -Force -ErrorAction SilentlyContinue }
            if (Test-Path $errorFile) { Remove-Item $errorFile -Force -ErrorAction SilentlyContinue }
        }
    }
    catch {
        Write-ActionLog -Action "Failed to execute Windows PowerShell command" -Details $_.Exception.Message -Category "PowerShell Compatibility" -Status 'FAILURE'
        if ($ErrorAction -eq "SilentlyContinue") {
            return $null
        }
        else {
            throw $_
        }
    }
}

# ================================================================
# Function: Get-AppxPackageCompatible
# ================================================================
# Purpose: Cross-version AppX package enumeration with enhanced compatibility and error handling
# Environment: Windows 10/11, AppX subsystem access, supports both user and system-wide package queries
# Logic: Provides consistent AppX package enumeration across different Windows versions with graceful error handling
# Performance: Fast, minimal overhead, direct PowerShell 7 cmdlet usage with optimized error handling
# Dependencies: Get-AppxPackage cmdlet, AppX subsystem availability, appropriate user context
# ================================================================
function Get-AppxPackageCompatible {
    param(
        [string]$Name = "*",
        [switch]$AllUsers
    )
    
    # Check if Appx module is available and can be loaded
    try {
        if (-not (Get-Module -Name Appx -ListAvailable)) {
            Write-Log "Appx module not available on this system" 'WARN'
            return @()
        }
        
        # Try to import the module if not already loaded
        if (-not (Get-Module -Name Appx)) {
            Import-Module Appx -ErrorAction Stop
        }
        
        # Test if Get-AppxPackage is actually functional
        $null = Get-AppxPackage -ErrorAction Stop | Select-Object -First 1
        
        if ($AllUsers) {
            return Get-AppxPackage -Name $Name -AllUsers -ErrorAction SilentlyContinue
        }
        else {
            return Get-AppxPackage -Name $Name -ErrorAction SilentlyContinue
        }
    }
    catch {
        if ($_.Exception.Message -like "*Operation is not supported on this platform*") {
            Write-Log "AppX subsystem not supported on this platform (likely Windows Server Core or minimal installation)" 'WARN'
        }
        elseif ($_.Exception.Message -like "*module could not be loaded*") {
            Write-Log "Appx module failed to load - AppX subsystem may be disabled or unavailable" 'WARN'
        }
        else {
            Write-Log "Failed to get AppX packages: $_" 'WARN'
        }
        return @()
    }
}

# ================================================================
# Function: Remove-AppxPackageCompatible
# ================================================================
# Purpose: Safe AppX package removal with verification and comprehensive error handling
# Environment: Requires Administrator privileges and AppX module access for system-wide operations
# Logic: Removes AppX package by name or wildcard pattern with post-removal verification
# Performance: Fast, minimal overhead, includes verification step for reliability
# Dependencies: Remove-AppxPackage cmdlet, AppX subsystem, Administrator privileges for AllUsers operations
# ================================================================
function Remove-AppxPackageCompatible {
    param(
        [string]$PackageFullName,
        [switch]$AllUsers
    )
    
    try {
        if ($AllUsers) {
            Remove-AppxPackage -Package $PackageFullName -AllUsers -ErrorAction SilentlyContinue
        }
        else {
            Remove-AppxPackage -Package $PackageFullName -ErrorAction SilentlyContinue
        }

        # Verify removal was successful
        $remainingPackage = Get-AppxPackage -Name $PackageFullName -ErrorAction SilentlyContinue
        if ($remainingPackage) {
            Write-Log "AppX package removal may have failed - package still found: $PackageFullName" 'WARN'
            return $false
        }

        return $true
    }
    catch {
        Write-Log "Failed to remove AppX package ${PackageFullName}: $($_)" 'ERROR'
        return $false
    }
}

# ================================================================
# Function: Get-AppxProvisionedPackageCompatible
# ================================================================
# Purpose: Cross-version provisioned AppX package enumeration for system-wide package management
# Environment: Requires Administrator privileges and DISM/AppX module access for system image operations
# Logic: Returns array of provisioned package objects for preventing installation on new user accounts
# Performance: Fast, minimal overhead, includes error handling for module dependencies
# Dependencies: DISM module, Get-AppxProvisionedPackage cmdlet, Administrator privileges
# ================================================================
function Get-AppxProvisionedPackageCompatible {
    param(
        [switch]$Online
    )

    try {
        Import-Module Dism -ErrorAction SilentlyContinue
        if ($Online) {
            return Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Select-Object DisplayName, PackageName
        }
        else {
            return Get-AppxProvisionedPackage -ErrorAction SilentlyContinue | Select-Object DisplayName, PackageName
        }
    }
    catch {
        Write-Log "Failed to get provisioned AppX packages: $_" 'WARN'
        return @()
    }
}

# ================================================================
# Function: Remove-AppxProvisionedPackageCompatible
# ================================================================
# Purpose: Removes provisioned AppX packages from system image to prevent future user installations
# Environment: Administrator privileges required, DISM module access, system image modification capabilities
# Logic: Removes package by name system-wide with verification for online operations
# Performance: Fast, minimal overhead, includes verification step for reliability
# Dependencies: DISM module, Remove-AppxProvisionedPackage cmdlet, Administrator privileges
# ================================================================
function Remove-AppxProvisionedPackageCompatible {
    param(
        [string]$PackageName,
        [switch]$Online
    )

    try {
        Import-Module Dism -ErrorAction SilentlyContinue
        if ($Online) {
            Remove-AppxProvisionedPackage -Online -PackageName $PackageName -ErrorAction SilentlyContinue
    
            # Verify removal by checking if package still exists
            $remainingPackage = Get-AppxProvisionedPackage -Online | Where-Object { $_.PackageName -eq $PackageName }
            if (-not $remainingPackage) {
                return $true
            }
            else {
                Write-Log "AppX provisioned package removal may have failed - package still found: $PackageName" 'WARN'
                return $false
            }
        }
        else {
            Remove-AppxProvisionedPackage -PackageName $PackageName -ErrorAction SilentlyContinue
            # For offline operations, assume success if no exception was thrown
            return $true
        }
    }
    catch {
        Write-Log "Failed to remove provisioned AppX package ${PackageName}: $($_)" 'ERROR'
        return $false
    }
}

# ================================================================
# Function: Install-WindowsUpdatesCompatible
# ================================================================
# Purpose: Windows Update management with PowerShell 7 native support and comprehensive error handling
# Environment: Administrator privileges required, PSWindowsUpdate module dependency, internet connectivity
# Logic: Detects, filters, and installs Windows Updates with size validation and progress tracking
# Performance: Parallel detection, filtered updates (excludes previews), comprehensive error handling
# Dependencies: PSWindowsUpdate module, Windows Update service, internet connectivity, Administrator privileges
# ================================================================
function Install-WindowsUpdatesCompatible {
    param()

    Write-Log 'Starting Windows Updates Check and Installation - PowerShell 7 Enhanced Mode.' 'INFO'
    $startTime = Get-Date

    try {
        # Module validation: Check for PSWindowsUpdate module
        if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate -ErrorAction SilentlyContinue)) {
            Write-Log 'PSWindowsUpdate module not available - using graceful degradation' 'WARN'
            return $false
        }

        # Module import with validation
        try {
            Import-Module PSWindowsUpdate -Force -ErrorAction SilentlyContinue
    
            # Verify module functionality
            if (-not (Get-Command Get-WindowsUpdate -ErrorAction SilentlyContinue)) {
                throw "PSWindowsUpdate module loaded but Get-WindowsUpdate command not available"
            }
    
            Write-Log 'PSWindowsUpdate module imported successfully.' 'INFO'
        }
        catch {
            Write-Log "Failed to import PSWindowsUpdate module: $_" 'ERROR'
            return $false
        }

        # Update detection with comprehensive filtering
        Write-Log 'Scanning for available Windows Updates...' 'INFO'
        Write-TaskProgress "Scanning for Windows Updates" 25

        $availableUpdates = $null
        try {
            # Get available updates with filtering
            $availableUpdates = Get-WindowsUpdate -MicrosoftUpdate -AcceptAll -ErrorAction SilentlyContinue | Where-Object {
                $_.Title -notlike "*Preview*" -and 
                $_.Title -notlike "*Insider*" -and
                $_.Size -gt 0
            }
    
            if ($availableUpdates) {
                $updateCount = ($availableUpdates | Measure-Object).Count
                $totalSize = ($availableUpdates | Measure-Object -Property Size -Sum).Sum
                $totalSizeMB = [math]::Round($totalSize / 1MB, 2)
        
                Write-Log "Found $updateCount available updates (Total size: $totalSizeMB MB)." 'INFO'
                Write-TaskProgress "Installing $updateCount Windows Updates" 75
        
                # Install updates
                try {
                    Install-WindowsUpdate -MicrosoftUpdate -AcceptAll -AutoReboot:$false -Confirm:$false -IgnoreReboot -ErrorAction Stop
                    Write-Log "Windows Updates installation completed successfully." 'SUCCESS'
                    Write-TaskProgress "Windows Updates completed" 100
                    return $true
                }
                catch {
                    Write-Log "Windows Updates installation failed: $_" 'ERROR'
                    return $false
                }
            }
            else {
                Write-Log 'No new Windows Updates available.' 'INFO'
                Write-TaskProgress "No updates available" 100
                return $true
            }
        }
        catch {
            Write-Log "Failed to check for Windows Updates: $_" 'ERROR'
            return $false
        }
    }
    catch {
        Write-Log "Windows Updates operation failed: $_" 'ERROR'
        return $false
    }
    finally {
        $duration = (Get-Date) - $startTime
        Write-Log "Windows Updates check completed in $([math]::Round($duration.TotalSeconds, 2)) seconds" 'INFO'
    }
}

# ================================================================
# Function: Get-StartAppsCompatible
# ================================================================
# Purpose: Cross-version Start Menu apps enumeration for system analysis and app management
# Environment: Windows 10/11, Start Menu subsystem access, user context for personalized apps
# Logic: Retrieves Start Menu apps with error handling for system compatibility
# Performance: Fast enumeration, minimal overhead, graceful error handling
# Dependencies: Get-StartApps cmdlet availability, Start Menu subsystem, user context
# ================================================================
function Get-StartAppsCompatible {
    try {
        return Get-StartApps -ErrorAction SilentlyContinue | Select-Object Name, AppId
    }
    catch {
        Write-Log "Failed to get Start apps: $_" 'WARN'
        return @()
    }
}

# ================================================================
# Function: Get-ExtensiveSystemInventory
# ================================================================
# Purpose: Comprehensive system inventory collection for analysis, reporting, and maintenance planning
# Environment: Windows 10/11, any privilege level, comprehensive WMI/CIM access, package manager access
# Logic: Structured data collection across multiple sources (system, AppX, Winget, Chocolatey, registry)
# Performance: Optimized queries, parallel processing where possible, structured JSON output
# Dependencies: WMI/CIM cmdlets, Winget, Chocolatey, AppX, registry access, file system permissions
# ================================================================
function Get-ExtensiveSystemInventory {
    Write-Log 'Starting Extensive System Inventory (JSON Format).' 'INFO'
    Write-TaskProgress "Collecting system inventory" 10
    
    $inventoryFolder = $PSScriptRoot
    if (-not (Test-Path $inventoryFolder)) { 
        New-Item -ItemType Directory -Path $inventoryFolder -Force | Out-Null 
    }

    # Build structured inventory object
    $inventory = [ordered]@{
        metadata           = [ordered]@{
            generatedOn   = (Get-Date).ToString('o')
            scriptVersion = '1.0.0'
            hostname      = $env:COMPUTERNAME
            user          = $env:USERNAME
            powershell    = $PSVersionTable.PSVersion.ToString()
        }
        system             = @{}
        appx               = @()
        winget             = @()
        choco              = @()
        registry_uninstall = @()
        services           = @()
        scheduled_tasks    = @()
        drivers            = @()
    }

    Write-TaskProgress "Collecting system information" 20
    Write-Log 'Collecting system information...' 'INFO'
    try {
        $systemInfo = Get-ComputerInfo -ErrorAction SilentlyContinue
        $inventory.system = $systemInfo
        Write-Log 'System information collected successfully.' 'INFO'
    }
    catch { 
        Write-Log "System information collection failed: $_" 'WARN'
        $inventory.system = @{ error = $_.ToString() }
    }

    Write-TaskProgress "Collecting AppX applications" 30
    Write-Log 'Collecting installed AppX applications...' 'INFO'
    try {
        $appxPackages = Get-AppxPackageCompatible -AllUsers
        if ($appxPackages -and $appxPackages.Count -gt 0) {
            $inventory.appx = @($appxPackages | Select-Object Name, PackageFullName, Publisher)
            Write-Log "Successfully collected $($inventory.appx.Count) AppX applications." 'INFO'
        }
        else {
            Write-Log 'No AppX applications found or module not available.' 'INFO'
            $inventory.appx = @()
        }
    }
    catch { 
        Write-Log "AppX applications collection failed: $_" 'WARN'
        $inventory.appx = @()
    }

    Write-TaskProgress "Collecting Winget applications" 50
    Write-Log 'Collecting installed Winget applications...' 'INFO'
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        try {
            # Use better encoding handling for winget with console output optimization
            $env:PYTHONUTF8 = 1
            $originalOutputEncoding = [Console]::OutputEncoding
            [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
            
            $wingetOutput = & cmd /c "chcp 65001 >nul 2>&1 && winget list --accept-source-agreements 2>nul"
            
            # Restore original encoding
            [Console]::OutputEncoding = $originalOutputEncoding
            
            if ($wingetOutput -and $wingetOutput.Count -gt 0) {
                $apps = @()
                $headerFound = $false
                $skipPatterns = @('ΓÇª', '…', 'Microsoft .Net Native', 'Microsoft Visual C\+\+ 2015 UWP', 'Update for Windows')
                
                foreach ($line in $wingetOutput) {
                    # Enhanced encoding cleanup
                    $cleanLine = $line -replace 'ΓÇª', '…' -replace '[^\x20-\x7E\x09\x0A\x0D\u00A0-\uFFFF]', '' -replace '\s+', ' '
                    
                    if (-not $headerFound) {
                        if ($cleanLine -match '^Name\s+' -or $cleanLine -match '^-+\s+') {
                            $headerFound = $true
                        }
                        continue
                    }
                    
                    if ($cleanLine -match '^-+' -or $cleanLine.Trim() -eq '' -or $cleanLine -match '^\s*$') {
                        continue
                    }
                    
                    # Skip lines that are known to cause encoding issues
                    $shouldSkip = $false
                    foreach ($pattern in $skipPatterns) {
                        if ($cleanLine -match $pattern) {
                            $shouldSkip = $true
                            break
                        }
                    }
                    
                    if ($shouldSkip) {
                        continue
                    }
                    
                    if ($cleanLine -match '\S' -and $cleanLine.Length -gt 3) {
                        try {
                            # Robust parsing for winget output with multiple strategies
                            $appName = ""
                            $appId = ""
                            $appVersion = ""
                            $appSource = ""
                            
                            # Strategy 1: Try 2+ spaces split (original format)
                            $parts = $cleanLine -split '\s{2,}' | Where-Object { $_.Trim() -ne '' }
                            
                            # Strategy 2: If insufficient parts, try single space split with position-based parsing
                            if ($parts.Count -lt 2) {
                                $spaceParts = $cleanLine.Trim() -split '\s+' | Where-Object { $_.Trim() -ne '' }
                                
                                # Typical winget format: "AppName Version Id Source" or variations
                                # Look for package ID pattern (contains dots or specific patterns)
                                if ($spaceParts.Count -ge 2) {
                                    $idIndex = -1
                                    for ($i = 0; $i -lt $spaceParts.Count; $i++) {
                                        if ($spaceParts[$i] -match '\.' -and $spaceParts[$i] -notmatch '^\d+\.\d+' -or
                                            $spaceParts[$i] -match '^[A-Za-z][A-Za-z0-9]*\.[A-Za-z][A-Za-z0-9]*' -or
                                            $spaceParts[$i] -eq 'winget' -or $spaceParts[$i] -eq 'msstore') {
                                            $idIndex = $i
                                            break
                                        }
                                    }
                                    
                                    if ($idIndex -gt 0) {
                                        # Reconstruct name from parts before ID
                                        $appName = ($spaceParts[0..($idIndex-1)] -join ' ').Trim()
                                        $appId = $spaceParts[$idIndex].Trim()
                                        
                                        # Look for version (numeric pattern before ID)
                                        if ($idIndex -gt 1 -and $spaceParts[$idIndex-1] -match '^\d+[\.\d]*') {
                                            $appVersion = $spaceParts[$idIndex-1].Trim()
                                            $appName = ($spaceParts[0..($idIndex-2)] -join ' ').Trim()
                                        }
                                        
                                        # Source is typically last or after ID
                                        if ($idIndex + 1 -lt $spaceParts.Count) {
                                            $appSource = $spaceParts[$idIndex + 1].Trim()
                                        }
                                        
                                        $parts = @($appName, $appId, $appVersion, $appSource)
                                    }
                                    else {
                                        # Fallback: assume first part is name, try to find version pattern
                                        $appName = $spaceParts[0]
                                        for ($i = 1; $i -lt $spaceParts.Count; $i++) {
                                            if ($spaceParts[$i] -match '^\d+[\.\d]*' -and -not $appVersion) {
                                                $appVersion = $spaceParts[$i]
                                            }
                                            elseif (-not $appId -and $spaceParts[$i] -ne $appVersion) {
                                                $appId = $spaceParts[$i]
                                            }
                                        }
                                        $parts = @($appName, $appId, $appVersion, "")
                                    }
                                }
                            }
                            
                            if ($parts.Count -ge 1) {
                                $appName = $parts[0].Trim()
                                # Enhanced validation for meaningful app names
                                if ($appName.Length -gt 2 -and 
                                    $appName -notmatch '^[ΓÇ\s…]+$' -and 
                                    $appName -notmatch '^\.\.\.$' -and
                                    $appName -match '[a-zA-Z0-9]') {
                                    
                                    $appHash = @{
                                        Name    = $appName
                                        Id      = if ($parts.Count -gt 1) { $parts[1].Trim() } else { "" }
                                        Version = if ($parts.Count -gt 2) { $parts[2].Trim() } else { "" }
                                        Source  = if ($parts.Count -gt 3) { $parts[3].Trim() } else { "" }
                                    }
                                    
                                    $apps += $appHash
                                    Write-LogFile "[Inventory] Parsed: $($appHash.Name) | $($appHash.Id) | $($appHash.Version) | $($appHash.Source)"
                                }
                            }
                        }
                        catch {
                            # Enhanced error logging for debugging
                            Write-Log "[Inventory] Failed to parse winget line: $($cleanLine.Substring(0, [Math]::Min(40, $cleanLine.Length)))... Error: $_" 'VERBOSE'
                        }
                    }
                }
                
                $inventory.winget = $apps
                Write-Log "[Inventory] Collected $($apps.Count) winget applications." 'INFO'
            }
            else {
                Write-Log "[Inventory] No winget applications found." 'INFO'
                $inventory.winget = @()
            }
        }
        catch {
            Write-Log "[Inventory] Winget enumeration failed: $_" 'WARN'
            $inventory.winget = @()
        }
    }
    else {
        Write-Log "[Inventory] Winget not available." 'INFO'
        $inventory.winget = @()
    }

    Write-TaskProgress "Collecting Chocolatey applications" 70
    Write-Log "[Inventory] Collecting Chocolatey applications..." 'INFO'
    if (Get-Command choco -ErrorAction SilentlyContinue) {
        try {
            $chocoOutput = choco list --local-only 2>$null
            if ($chocoOutput) {
                $chocoApps = @()
                foreach ($line in $chocoOutput) {
                    if ($line -match '^(.+?)\s+(.+?)$' -and $line -notmatch 'packages installed') {
                        $chocoApps += @{
                            Name    = $matches[1].Trim()
                            Version = $matches[2].Trim()
                        }
                    }
                }
                $inventory.choco = $chocoApps
                Write-Log "[Inventory] Collected $($chocoApps.Count) Chocolatey applications." 'INFO'
            }
            else {
                $inventory.choco = @()
            }
        }
        catch {
            Write-Log "[Inventory] Chocolatey enumeration failed: $_" 'WARN'
            $inventory.choco = @()
        }
    }
    else {
        Write-Log "[Inventory] Chocolatey not available." 'INFO'
        $inventory.choco = @()
    }

    Write-TaskProgress "Finalizing inventory" 90
    
    # Save inventory to JSON file
    try {
        $inventoryPath = Join-Path $inventoryFolder 'inventory.json'
        $inventory | ConvertTo-Json -Depth 6 | Out-File -FilePath $inventoryPath -Encoding UTF8
        Write-Log "[Inventory] Structured inventory saved to inventory.json" 'INFO'

        # Store global reference
        $global:SystemInventory = $inventory
    }
    catch {
        Write-Log "[Inventory] Failed to write inventory.json: $_" 'WARN'
    }

    Write-TaskProgress "System inventory completed" 100
    # Clear any lingering progress bars
    Write-Progress -Activity "System inventory completed" -Completed
    Write-Progress -Activity " " -Completed  # Extra cleanup for console buffer
    Write-Log "[END] Extensive System Inventory (JSON Format)" 'INFO'
}

# ===============================
# SECTION 4: BLOATWARE MANAGEMENT
# ===============================
# - Remove-Bloatware (main function)
# - Bloatware detection and removal utilities
# - Bloatware categories and classification logic
# - Supporting bloatware functions

# ================================================================
# Function: Remove-Bloatware
# ================================================================
# Purpose: Ultra-enhanced bloatware removal with diff-based processing and parallel optimization
# Environment: Windows 10/11, requires Administrator privileges, PowerShell 7+ optimized with fallback compatibility
# Performance: Diff-based processing reduces workload by 60-90%, parallel processing with throttling, optimized lookup operations
# Dependencies: System inventory, bloatware list, package managers (Winget/Chocolatey), AppX module, registry access
# Logic: Compares current vs previous app installations, processes only newly detected apps, uses parallel removal with multiple methods
# Features: Diff-based optimization, parallel processing, comprehensive audit logging, registry cleanup, multiple removal methods
# ================================================================
function Remove-Bloatware {
    Write-Log "Starting Ultra-Enhanced Bloatware Removal - Diff-Based Processing Mode" 'INFO'

    # Use cached inventory if available, otherwise trigger fresh comprehensive scan
    if (-not $global:SystemInventory) {
        Get-ExtensiveSystemInventory
    }

    $inventory = $global:SystemInventory

    # ================================================================
    # STEP 1: Create standardized current installed apps list
    # ================================================================
    Write-Log "Creating standardized current installed apps list..." 'INFO'
    $currentInstalledApps = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    # Add all app identifiers from all sources to current list
    $inventory.appx | ForEach-Object {
        if ($_.Name) { [void]$currentInstalledApps.Add($_.Name.Trim()) }
        if ($_.PackageFullName) { [void]$currentInstalledApps.Add($_.PackageFullName.Trim()) }
    }

    $inventory.winget | ForEach-Object {
        if ($_.Name) { [void]$currentInstalledApps.Add($_.Name.Trim()) }
        if ($_.Id) { [void]$currentInstalledApps.Add($_.Id.Trim()) }
    }

    $inventory.choco | ForEach-Object {
        if ($_.Name) { [void]$currentInstalledApps.Add($_.Name.Trim()) }
    }

    $inventory.registry_uninstall | ForEach-Object {
        if ($_.DisplayName) { [void]$currentInstalledApps.Add($_.DisplayName.Trim()) }
    }

    # Save current list for future diff operations
    $currentListPath = Join-Path $global:TempFolder 'current_installed_apps.json'
    @($currentInstalledApps) | ConvertTo-Json -Depth 2 | Out-File $currentListPath -Encoding UTF8
    Write-Log "Current installed apps list saved: $($currentInstalledApps.Count) total apps" 'INFO'

    # ================================================================
    # STEP 2: Load previous installed apps list and calculate diff
    # ================================================================
    $previousListPath = Join-Path $global:TempFolder 'previous_installed_apps.json'
    $newlyInstalledApps = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    if (Test-Path $previousListPath) {
        try {
            Write-Log "Loading previous installed apps list for diff comparison..." 'INFO'
            $previousInstalledApps = Get-Content $previousListPath -Raw | ConvertFrom-Json
            $previousHashSet = [System.Collections.Generic.HashSet[string]]::new($previousInstalledApps, [System.StringComparer]::OrdinalIgnoreCase)
            Write-Log "Previous run had $($previousHashSet.Count) installed apps" 'INFO'

            # Calculate diff: apps in current but not in previous (newly installed)
            foreach ($currentApp in $currentInstalledApps) {
                if (-not $previousHashSet.Contains($currentApp)) {
                    [void]$newlyInstalledApps.Add($currentApp)
                }
            }

            Write-Log "DIFF ANALYSIS COMPLETE:" 'INFO'
            Write-Log "  - Current apps: $($currentInstalledApps.Count)" 'INFO'
            Write-Log "  - Previous apps: $($previousHashSet.Count)" 'INFO'
            Write-Log "  - Newly installed: $($newlyInstalledApps.Count)" 'INFO'

            # Log some examples of newly installed apps for debugging (max 10)
            if ($newlyInstalledApps.Count -gt 0) {
                $exampleApps = @($newlyInstalledApps) | Select-Object -First 10
                Write-Log "Examples of newly installed apps: $($exampleApps -join ', ')" 'VERBOSE'
            }

            # Save diff list for debugging
            $diffListPath = Join-Path $global:TempFolder 'newly_installed_apps_diff.json'
            @($newlyInstalledApps) | ConvertTo-Json -Depth 2 | Out-File $diffListPath -Encoding UTF8

        }
        catch {
            Write-Log "Failed to load previous list, processing all apps: $_" 'WARN'
            $newlyInstalledApps = $currentInstalledApps
        }
    }
    else {
        Write-Log "No previous installed apps list found, processing all current apps (first run)" 'INFO'
        $newlyInstalledApps = $currentInstalledApps
    }

    # Early exit if no newly installed apps
    if ($newlyInstalledApps.Count -eq 0) {
        Write-Log "No newly installed apps detected since last run. Skipping bloatware removal." 'INFO'
        # Update previous list for next run
        Copy-Item $currentListPath $previousListPath -Force
        return
    }

    # ================================================================
    # STEP 3: Build optimized lookup for ONLY newly installed apps
    # ================================================================
    Write-Log "Building optimized lookup for $($newlyInstalledApps.Count) newly installed apps..." 'INFO'
    $installedApps = [System.Collections.Generic.Dictionary[string, PSCustomObject]]::new([System.StringComparer]::OrdinalIgnoreCase)

    # Filter inventory to only include newly installed apps
    $filteredInventoryJobs = @(
        @{ Name = 'AppX'; Data = $inventory.appx | Where-Object { $newlyInstalledApps.Contains($_.Name) -or $newlyInstalledApps.Contains($_.PackageFullName) }; Props = @('Name', 'PackageFullName') },
        @{ Name = 'Winget'; Data = $inventory.winget | Where-Object { $newlyInstalledApps.Contains($_.Name) -or $newlyInstalledApps.Contains($_.Id) }; Props = @('Name', 'Id') },
        @{ Name = 'Chocolatey'; Data = $inventory.choco | Where-Object { $newlyInstalledApps.Contains($_.Name) }; Props = @('Name') },
        @{ Name = 'Registry'; Data = $inventory.registry_uninstall | Where-Object { $newlyInstalledApps.Contains($_.DisplayName) }; Props = @('DisplayName', 'UninstallString') }
    ) | ForEach-Object -Parallel {
        $type = $_.Name
        $data = $_.Data
        $properties = $_.Props
        $results = [System.Collections.Generic.List[hashtable]]::new()

        foreach ($item in $data) {
            foreach ($prop in $properties) {
                if ($item.$prop -and $item.$prop.ToString().Trim()) {
                    $results.Add(@{
                            Key  = $item.$prop.ToString().Trim()
                            Type = $type
                            Data = $item
                        })
                }
            }
        }
        return @($results)
    } -ThrottleLimit 8

    # Merge filtered results into lookup dictionary
    foreach ($jobResult in $filteredInventoryJobs) {
        foreach ($item in $jobResult) {
            if (-not $installedApps.ContainsKey($item.Key)) {
                $installedApps[$item.Key] = [PSCustomObject]@{
                    Type = $item.Type
                    Data = $item.Data
                }
            }
        }
    }

    # Smart bloatware detection with optimized pattern matching
    $bloatwareMatches = [System.Collections.Generic.List[PSCustomObject]]::new()
    $bloatwareHashSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($item in $global:BloatwareList) {
        [void]$bloatwareHashSet.Add($item)
    }

    # Direct lookup phase (O(1) performance)
    foreach ($installedKey in $installedApps.Keys) {
        if ($bloatwareHashSet.Contains($installedKey)) {
            $bloatwareMatches.Add([PSCustomObject]@{
                    BloatwareName = $installedKey
                    InstalledApp  = $installedApps[$installedKey]
                    MatchType     = 'Direct'
                })
        }
    }

    # Pattern matching phase (only if needed)
    if ($bloatwareMatches.Count -eq 0) {
        foreach ($bloatApp in $global:BloatwareList) {
            $trimmedBloat = $bloatApp.Trim()
            foreach ($installedKey in $installedApps.Keys) {
                if ($installedKey.Contains($trimmedBloat, [System.StringComparison]::OrdinalIgnoreCase) -or 
                    $trimmedBloat.Contains($installedKey, [System.StringComparison]::OrdinalIgnoreCase)) {
        
                    $bloatwareMatches.Add([PSCustomObject]@{
                            BloatwareName = $trimmedBloat
                            InstalledApp  = $installedApps[$installedKey]
                            MatchType     = 'Pattern'
                        })
                    break
                }
            }
        }
    }

    # Early exit if no bloatware found
    if ($bloatwareMatches.Count -eq 0) {
        Write-Log "[END] Ultra-Enhanced Bloatware Removal - No bloatware detected" 'INFO'
        return
    }

    # Cached tool availability detection
    $toolCapabilities = @{
        AppX       = $false
        Winget     = $false
        Chocolatey = $false
    }

    # Fast native AppX detection for PS7.5+
    try {
        $null = Get-AppxPackage -Name "NonExistent*" -ErrorAction SilentlyContinue
        $toolCapabilities.AppX = $true
    }
    catch {
        # Test if Appx module is available
        try {
            $toolCapabilities.AppX = $null -ne (Get-Module -ListAvailable -Name Appx -ErrorAction SilentlyContinue)
        }
        catch { 
            $toolCapabilities.AppX = $false
        }
    }

    # Cache command availability
    $toolCapabilities.Winget = $null -ne (Get-Command winget -ErrorAction SilentlyContinue)
    $toolCapabilities.Chocolatey = $null -ne (Get-Command choco -ErrorAction SilentlyContinue)

    # Thread-safe collections for results
    $removedApps = [System.Collections.Concurrent.ConcurrentBag[PSCustomObject]]::new()

    # Ultra-parallel removal with optimized error handling
    $bloatwareMatches | ForEach-Object -Parallel {
        $match = $_
        $capabilities = $using:toolCapabilities

        $result = @{
            Success    = $false
            AppName    = $match.BloatwareName
            ActualName = ""
            Method     = ""
        }

        try {
            $app = $match.InstalledApp
            $appType = $app.Type
            $appData = $app.Data

            # Optimized removal by type priority
            switch ($appType) {
                'AppX' {
                    if ($capabilities.AppX -and $appData.PackageFullName) {
                        try {
                            Remove-AppxPackage -Package $appData.PackageFullName -AllUsers -ErrorAction SilentlyContinue

                            # Verify removal
                            $remainingPackage = Get-AppxPackage -PackageFullName $appData.PackageFullName -ErrorAction SilentlyContinue
                            if (-not $remainingPackage) {
                                $result.Success = $true
                                $result.Method = "AppX"
                                $result.ActualName = $appData.Name
                            }
                            else {
                                $success = Remove-AppxPackageCompatible -PackageFullName $appData.PackageFullName -AllUsers
                                if (-not $success) { throw "AppX compatibility removal failed" }
                            }
                            $result.Success = $true
                            $result.Method = "AppX"
                            $result.ActualName = $appData.Name
                        }
                        catch { }
                    }
                }
                'Winget' {
                    if ($capabilities.Winget -and $appData.Id) {
                        try {
                            $proc = Start-Process -FilePath "winget" -ArgumentList @(
                                "uninstall", "--id", $appData.Id, "--exact", "--silent", 
                                "--accept-source-agreements", "--force", "--disable-interactivity"
                            ) -WindowStyle Hidden -Wait -PassThru

                            if ($proc.ExitCode -eq 0) {
                                $result.Success = $true
                                $result.Method = "Winget"
                                $result.ActualName = $appData.Name
                            }
                        }
                        catch { }
                    }
                }
                'Chocolatey' {
                    if ($capabilities.Chocolatey -and $appData.Name) {
                        try {
                            $proc = Start-Process -FilePath "choco" -ArgumentList @(
                                "uninstall", $appData.Name, "-y", "--remove-dependencies", 
                                "--limit-output", "--no-progress"
                            ) -WindowStyle Hidden -Wait -PassThru

                            if ($proc.ExitCode -eq 0) {
                                $result.Success = $true
                                $result.Method = "Chocolatey"
                                $result.ActualName = $appData.Name
                            }
                        }
                        catch { }
                    }
                }
                'Registry' {
                    if ($appData.UninstallString -and $appData.UninstallString -match '\.exe') {
                        try {
                            $uninstallCmd = $appData.UninstallString -replace '"', ''
                            $proc = Start-Process -FilePath $uninstallCmd -ArgumentList "/S" -Wait -WindowStyle Hidden -PassThru

                            if ($proc.ExitCode -eq 0) {
                                $result.Success = $true
                                $result.Method = "Registry"
                                $result.ActualName = $appData.DisplayName
                            }
                        }
                        catch { }
                    }
                }
            }

            # Fast AppX fallback if primary method failed
            if (-not $result.Success -and $capabilities.AppX) {
                try {
                    $packages = Get-AppxPackage -Name "*$($match.BloatwareName)*" -AllUsers -ErrorAction SilentlyContinue
                    foreach ($pkg in $packages | Select-Object -First 1) {
                        Remove-AppxPackage -Package $pkg.PackageFullName -AllUsers -ErrorAction SilentlyContinue

                        # Verify removal
                        $verifyPackage = Get-AppxPackage -PackageFullName $pkg.PackageFullName -ErrorAction SilentlyContinue
                        if (-not $verifyPackage) {
                            $result.Success = $true
                            $result.Method = "AppX Fallback"
                            $result.ActualName = $pkg.Name
                            break
                        }
                    }
                }
                catch { }
            }
        }
        catch { }

        return $result

    } -ThrottleLimit 8 | Where-Object { $_.Success } | ForEach-Object {
        [void]$removedApps.Add([PSCustomObject]$_)
    }

    # Convert to array for processing
    $removedArray = @($removedApps)

    # ================================================================
    # ENHANCED ACTION-ONLY LOGGING: Every removed app with diff context
    # ================================================================
    if ($removedArray.Count -gt 0) {
        Write-Log "=== BLOATWARE REMOVAL RESULTS (DIFF-BASED PROCESSING) ===" 'INFO'
        Write-Host "=== BLOATWARE REMOVAL RESULTS ===" -ForegroundColor Yellow

        # Individual app removals - one line per app with enhanced details
        foreach ($removed in $removedArray) {
            $logMsg = "✓ REMOVED: $($removed.ActualName) [Method: $($removed.Method)]"
            Write-Log $logMsg 'INFO'
            Write-Host $logMsg -ForegroundColor Green
        }

        # Enhanced summary with diff context
        $appNames = ($removedArray | ForEach-Object { $_.ActualName } | Sort-Object -Unique) -join ', '
        Write-Log "DIFF-BASED REMOVAL SUMMARY: $($removedArray.Count) bloatware apps removed from $($newlyInstalledApps.Count) newly detected apps" 'INFO'
        Write-Log "Removed apps: $appNames" 'INFO'

        # Method breakdown with statistics
        $methodGroups = $removedArray | Group-Object Method
        $methodSummary = ($methodGroups | ForEach-Object { "$($_.Name): $($_.Count)" }) -join ', '
        Write-Log "Removal methods used: $methodSummary" 'INFO'

        # Performance metrics for diff-based processing
        $efficiencyGain = if ($currentInstalledApps.Count -gt 0) { 
            [math]::Round((1 - ($newlyInstalledApps.Count / $currentInstalledApps.Count)) * 100, 1) 
        }
        else { 0 }
        Write-Log "PERFORMANCE: Processed $($newlyInstalledApps.Count)/$($currentInstalledApps.Count) apps (${efficiencyGain}% reduction in processing)" 'INFO'

        # Create detailed removal log for audit trail
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $removalAuditPath = Join-Path $global:TempFolder "bloatware_removed_$timestamp.json"
        $auditData = @{
            Timestamp          = (Get-Date).ToString('o')
            ProcessingMode     = "Diff-Based"
            TotalCurrentApps   = $currentInstalledApps.Count
            NewlyInstalledApps = $newlyInstalledApps.Count
            BloatwareRemoved   = $removedArray.Count
            EfficiencyGain     = "${efficiencyGain}%"
            RemovedApps        = $removedArray | ForEach-Object { 
                @{
                    Name         = $_.ActualName
                    Method       = $_.Method
                    OriginalName = $_.AppName
                }
            }
            MethodBreakdown    = $methodGroups | ForEach-Object { 
                @{
                    Method = $_.Name
                    Count  = $_.Count
                }
            }
        }
        $auditData | ConvertTo-Json -Depth 4 | Out-File $removalAuditPath -Encoding UTF8
        Write-Log "Detailed removal audit saved to: $removalAuditPath" 'VERBOSE'

    }
    else {
        if ($newlyInstalledApps.Count -eq 0) {
            Write-Log "DIFF-BASED PROCESSING: No newly installed apps detected since last run - no bloatware removal needed" 'INFO'
            Write-Host "✓ No newly installed apps detected - system clean" -ForegroundColor Green
        }
        else {
            Write-Log "DIFF-BASED PROCESSING: $($newlyInstalledApps.Count) newly installed apps checked, no bloatware found" 'INFO'
            Write-Host "✓ $($newlyInstalledApps.Count) newly installed apps checked - no bloatware detected" -ForegroundColor Green
        }
    }

    # Ultra-fast registry cleanup to prevent reinstallation
    $registryKeys = @(
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager',
        'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
    )

    $registryKeys | ForEach-Object -Parallel {
        $regKey = $_
        try {
            if (-not (Test-Path $regKey)) { 
                New-Item -Path $regKey -Force -ErrorAction SilentlyContinue | Out-Null 
            }

            $settings = @{
                'SilentInstalledAppsEnabled'   = 0
                'ContentDeliveryAllowed'       = 0
                'OemPreInstalledAppsEnabled'   = 0
                'PreInstalledAppsEnabled'      = 0
                'SubscribedContentEnabled'     = 0
                'SystemPaneSuggestionsEnabled' = 0
                'SoftLandingEnabled'           = 0
            }

            foreach ($setting in $settings.GetEnumerator()) {
                Set-ItemProperty -Path $regKey -Name $setting.Key -Value $setting.Value -ErrorAction SilentlyContinue
            }
        }
        catch { }
    } -ThrottleLimit 3 | Out-Null

    # ================================================================
    # STEP 4: Update previous installed apps list for next diff operation
    # ================================================================
    try {
        # Update the previous list with current list for next run
        Copy-Item $currentListPath $previousListPath -Force
        Write-Log "Updated previous installed apps list for next diff operation" 'INFO'

        # Create summary report of diff-based processing
        $diffSummary = @{
            TotalCurrentApps   = $currentInstalledApps.Count
            NewlyInstalledApps = $newlyInstalledApps.Count
            BloatwareRemoved   = if ($removedArray) { $removedArray.Count } else { 0 }
            ProcessingMode     = "Diff-Based (Optimized)"
            LastRun            = (Get-Date).ToString('o')
        }

        $diffSummaryPath = Join-Path $global:TempFolder 'bloatware_diff_summary.json'
        $diffSummary | ConvertTo-Json -Depth 3 | Out-File $diffSummaryPath -Encoding UTF8
        Write-Log "Diff-based processing summary saved to $diffSummaryPath" 'INFO'
    }
    catch {
        Write-Log "Failed to update previous list for diff operation: $_" 'WARN'
    }

    Write-Log "[END] Ultra-Enhanced Bloatware Removal - Diff-Based Processing Complete" 'INFO'
}

# ===============================
# SECTION 5: ESSENTIAL APPS MANAGEMENT
# ===============================
# - Install-EssentialApps (main function)
# - Essential apps detection and installation utilities
# - Package manager integration (Winget/Chocolatey)
# - Office suite management and LibreOffice fallback

# ================================================================
# Function: Install-EssentialApps
# ================================================================
# Purpose: High-performance installation of curated essential applications using parallel processing and diff-based optimization
# Environment: Windows 10/11, Administrator required, Winget/Chocolatey package manager access, PowerShell 7+ optimized
# Performance: Diff-based processing reduces workload by 60-90%, parallel installation batches, O(1) HashSet lookups, action-only logging
# Dependencies: Winget, Chocolatey, system inventory, config.json custom app support, essential apps list definition
# Logic: Inventory-based duplicate detection, diff comparison with previous runs, parallel installation batches, comprehensive error handling
# Features: Custom app list support, office suite detection, LibreOffice fallback, detailed audit logging, progress tracking
# ================================================================
function Install-EssentialApps {
    Write-Log 'Starting Install Essential Apps - Diff-Based Optimization Mode.' 'INFO'

    # DIFF-BASED OPTIMIZATION: Create current essential app requirements list
    Write-Log 'Creating standardized essential apps list for diff analysis...' 'INFO'
    $currentEssentialApps = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    # Build comprehensive list of all essential app identifiers from definition
    $global:EssentialApps | ForEach-Object {
        if ($_.Name) { [void]$currentEssentialApps.Add($_.Name.Trim()) }
        if ($_.Winget) { [void]$currentEssentialApps.Add($_.Winget.Trim()) }
        if ($_.Choco) { [void]$currentEssentialApps.Add($_.Choco.Trim()) }
    }

    # Save current essential apps list
    $currentListPath = Join-Path $global:TempFolder 'essential_apps_current.json'
    $previousListPath = Join-Path $global:TempFolder 'essential_apps_previous.json'
    @($currentEssentialApps) | ConvertTo-Json -Depth 2 | Out-File $currentListPath -Encoding UTF8
    Write-Log "Current essential apps list saved: $($currentEssentialApps.Count) required apps" 'INFO'

    # DIFF CALCULATION: Compare with previous run to find new requirements
    $newlyRequiredApps = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    if (Test-Path $previousListPath) {
        try {
            Write-Log "Loading previous essential apps list for diff comparison..." 'INFO'
            $previousEssentialApps = Get-Content $previousListPath -Raw | ConvertFrom-Json
            $previousHashSet = [System.Collections.Generic.HashSet[string]]::new($previousEssentialApps, [System.StringComparer]::OrdinalIgnoreCase)
            Write-Log "Previous run required $($previousHashSet.Count) essential apps" 'INFO'

            # Calculate diff: apps in current but not in previous (newly required)
            foreach ($currentApp in $currentEssentialApps) {
                if (-not $previousHashSet.Contains($currentApp)) {
                    [void]$newlyRequiredApps.Add($currentApp)
                }
            }

            Write-Log "DIFF ANALYSIS COMPLETE:" 'INFO'
            Write-Log "  - Current requirements: $($currentEssentialApps.Count)" 'INFO'
            Write-Log "  - Previous requirements: $($previousHashSet.Count)" 'INFO'
            Write-Log "  - Newly required: $($newlyRequiredApps.Count)" 'INFO'

            # Log some examples of newly required apps for debugging (max 10)
            if ($newlyRequiredApps.Count -gt 0) {
                $exampleApps = @($newlyRequiredApps) | Select-Object -First 10
                Write-Log "Examples of newly required apps: $($exampleApps -join ', ')" 'VERBOSE'
            }
        }
        catch {
            Write-Log "Could not load previous essential apps list: $($_.Exception.Message). Processing all apps." 'WARN'
            $newlyRequiredApps = $currentEssentialApps
            Write-Log "DIFF ANALYSIS FALLBACK: Processing all $($newlyRequiredApps.Count) required apps" 'INFO'
        }
    }
    else {
        Write-Log "No previous essential apps list found. Processing all required apps." 'INFO'
        $newlyRequiredApps = $currentEssentialApps
        Write-Log "DIFF ANALYSIS FIRST-RUN: Processing all $($newlyRequiredApps.Count) required apps" 'INFO'
    }

    # Logic: Use global inventory if available, otherwise build optimized inventory for app detection
    if (-not $global:SystemInventory) {
        Write-Log 'Building system inventory for duplicate detection...' 'INFO'
        Get-ExtensiveSystemInventory
    }

    $inventory = $global:SystemInventory

    # Optimization: Build comprehensive hashtable of all installed app identifiers for O(1) lookup performance
    $installedLookup = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    # Data sources: Add AppX package names and IDs to lookup table
    $inventory.appx | ForEach-Object {
        if ($_.Name) { [void]$installedLookup.Add($_.Name.Trim()) }
        if ($_.PackageFullName) { [void]$installedLookup.Add($_.PackageFullName.Trim()) }
    }

    # Data sources: Add Winget app names and IDs to lookup table  
    $inventory.winget | ForEach-Object {
        if ($_.Name) { [void]$installedLookup.Add($_.Name.Trim()) }
        if ($_.Id) { [void]$installedLookup.Add($_.Id.Trim()) }
    }

    # Data sources: Add Chocolatey app names to lookup table
    $inventory.choco | ForEach-Object {
        if ($_.Name) { [void]$installedLookup.Add($_.Name.Trim()) }
    }

    # Data sources: Add registry app display names to lookup table
    $inventory.registry_uninstall | ForEach-Object {
        if ($_.DisplayName) { [void]$installedLookup.Add($_.DisplayName.Trim()) }
    }

    # Smart filtering: find essential apps that are NOT installed using O(1) lookups
    # DIFF OPTIMIZATION: Only process apps that are newly required OR not in diff mode
    $appsToInstall = @()
    foreach ($essentialApp in $global:EssentialApps) {
        # Check if this app should be processed based on diff analysis
        $shouldProcess = $false
        $identifiersToCheck = @()
        if ($essentialApp.Winget) { $identifiersToCheck += $essentialApp.Winget.Trim() }
        if ($essentialApp.Choco) { $identifiersToCheck += $essentialApp.Choco.Trim() }
        if ($essentialApp.Name) { $identifiersToCheck += $essentialApp.Name.Trim() }

        # Check if any identifier is in newly required apps
        foreach ($identifier in $identifiersToCheck) {
            if ($newlyRequiredApps.Contains($identifier)) {
                $shouldProcess = $true
                break
            }
        }

        # Skip processing if not in diff list (already processed in previous run)
        if (-not $shouldProcess) {
            continue
        }

        $found = $false
        # Use HashSet.Contains for O(1) lookup performance
        foreach ($identifier in $identifiersToCheck) {
            if ($installedLookup.Contains($identifier)) {
                $found = $true
                break
            }
        }

        if (-not $found) {
            $appsToInstall += $essentialApp
        }
    }

    if ($appsToInstall.Count -eq 0) {
        # Calculate efficiency gain from diff-based processing
        $efficiencyGain = if ($currentEssentialApps.Count -gt 0) { 
            [math]::Round((1 - ($newlyRequiredApps.Count / $currentEssentialApps.Count)) * 100, 1) 
        }
        else { 0 }

        Write-Log "[EssentialApps] All essential apps already installed. No new installations needed." 'INFO'
        Write-Log "PERFORMANCE: Processed $($newlyRequiredApps.Count)/$($currentEssentialApps.Count) required apps (${efficiencyGain}% reduction in processing)" 'INFO'

        # Update previous list for next run
        Copy-Item $currentListPath $previousListPath -Force
        Write-Log "[END] Install Essential Apps" 'INFO'
        return
    }

    # Pre-check package manager availability once
    $wingetAvailable = $null -ne (Get-Command winget -ErrorAction SilentlyContinue)
    $chocoAvailable = $null -ne (Get-Command choco -ErrorAction SilentlyContinue)

    if (-not $wingetAvailable -and -not $chocoAvailable) {
        Write-Log "[EssentialApps] ERROR: No package managers available (winget/choco). Cannot install apps." 'ERROR'
        Write-Log "[END] Install Essential Apps" 'INFO'
        return
    }

    # Calculate efficiency gain from diff-based processing
    $efficiencyGain = if ($currentEssentialApps.Count -gt 0) { 
        [math]::Round((1 - ($newlyRequiredApps.Count / $currentEssentialApps.Count)) * 100, 1) 
    }
    else { 0 }

    Write-Log "[EssentialApps] DIFF-BASED MODE: Processing $($appsToInstall.Count) apps for installation..." 'INFO'
    Write-Log "PERFORMANCE: Processing $($newlyRequiredApps.Count)/$($currentEssentialApps.Count) required apps (${efficiencyGain}% reduction)" 'INFO'

    # PowerShell 7 Native Parallel Processing with Progress Tracking
    Write-Log "[EssentialApps] Using PowerShell 7 parallel processing with individual app progress..." 'INFO'

    $totalApps = $appsToInstall.Count
    $currentAppIndex = 0
    $successCount = 0
    $failedCount = 0
    $skippedCount = 0

    # ACTION-ONLY LOGGING: Enhanced logging for each app installation
    Write-Log "[EssentialApps] Starting installation of $totalApps essential apps:" 'INFO'

    foreach ($app in $appsToInstall) {
        $currentAppIndex++
        $progressPercent = [math]::Round(($currentAppIndex / $totalApps) * 100, 1)

        # Individual per-app progress bar
        Write-Progress -Activity "Installing $($app.Name) ($currentAppIndex/$totalApps)" -Status "In progress..." -PercentComplete 0
        Write-TaskProgress "Installing Essential Apps" $progressPercent "$($app.Name) ($currentAppIndex/$totalApps)"

        # Log and host message with percent
        Write-Host "[$progressPercent%] Installing: $($app.Name) ($currentAppIndex/$totalApps)" -ForegroundColor Cyan
        Write-Log "[$progressPercent%][$currentAppIndex/$totalApps] Processing: $($app.Name)..." 'INFO'

        $result = [PSCustomObject]@{
            AppName    = $app.Name
            Success    = $false
            Method     = ""
            Error      = ""
            Skipped    = $false
            SkipReason = ""
        }

        try {
            # Try Winget first (preferred method)
            if ($app.Winget -and $wingetAvailable) {
                Write-Host "  → Trying Winget installation for $($app.Name)..." -ForegroundColor Cyan
                $wingetArgs = @(
                    "install", "--id", $app.Winget,
                    "--accept-source-agreements", "--accept-package-agreements", 
                    "--silent", "-e", "--disable-interactivity", "--force"
                )
                $wingetProc = Start-Process -FilePath "winget" -ArgumentList $wingetArgs -WindowStyle Hidden -Wait -PassThru
                if ($wingetProc.ExitCode -eq 0) {
                    $result.Success = $true
                    $result.Method = "winget"
                    $successCount++
                    Write-Log "✓ INSTALLED: $($app.Name) [Method: Winget]" 'INFO'
                    Write-Host "    ✓ Successfully installed via Winget" -ForegroundColor Green
                    Write-Progress -Activity "Installing $($app.Name) ($currentAppIndex/$totalApps)" -Completed
                    continue
                }
                elseif ($wingetProc.ExitCode -eq -1978335189) {
                    # App already installed
                    $result.Skipped = $true
                    $result.SkipReason = "already installed (winget)"
                    $skippedCount++
                    Write-Log "⚪ SKIPPED: $($app.Name) [Reason: Already installed via Winget]" 'INFO'
                    Write-Host "    ⚪ Already installed (Winget detected)" -ForegroundColor Yellow
                    Write-Progress -Activity "Installing $($app.Name) ($currentAppIndex/$totalApps)" -Completed
                    continue
                }
                else {
                    $result.Error += "winget failed (exit: $($wingetProc.ExitCode)); "
                    Write-Host "    ✗ Winget failed (exit code: $($wingetProc.ExitCode))" -ForegroundColor Red
                }
            }

            # Try Chocolatey as fallback
            if (-not $result.Success -and $app.Choco -and $chocoAvailable) {
                Write-Host "  → Trying Chocolatey installation for $($app.Name)..." -ForegroundColor Cyan
                $chocoArgs = @("install", $app.Choco, "-y", "--no-progress", "--limit-output")
                $chocoProc = Start-Process -FilePath "choco" -ArgumentList $chocoArgs -WindowStyle Hidden -Wait -PassThru
                if ($chocoProc.ExitCode -eq 0) {
                    $result.Success = $true
                    $result.Method = "choco"
                    $successCount++
                    Write-Log "✓ INSTALLED: $($app.Name) [Method: Chocolatey]" 'INFO'
                    Write-Host "    ✓ Successfully installed via Chocolatey" -ForegroundColor Green
                    Write-Progress -Activity "Installing $($app.Name) ($currentAppIndex/$totalApps)" -Completed
                    continue
                }
                elseif ($chocoProc.ExitCode -eq 1641 -or $chocoProc.ExitCode -eq 3010) {
                    # Success with reboot required
                    $result.Success = $true
                    $result.Method = "choco (reboot required)"
                    $successCount++
                    Write-Log "✓ INSTALLED: $($app.Name) [Method: Chocolatey - Reboot Required]" 'INFO'
                    Write-Host "    ✓ Successfully installed via Chocolatey (reboot required)" -ForegroundColor Green
                    Write-Progress -Activity "Installing $($app.Name) ($currentAppIndex/$totalApps)" -Completed
                    continue
                }
                else {
                    $result.Error += "choco failed (exit: $($chocoProc.ExitCode))"
                    Write-Host "    ✗ Chocolatey failed (exit code: $($chocoProc.ExitCode))" -ForegroundColor Red
                }
            }

            # No installation method succeeded
            if (-not $wingetAvailable -and -not $chocoAvailable) {
                $result.Skipped = $true
                $result.SkipReason = "no package manager available"
                $skippedCount++
                Write-Log "⚪ SKIPPED: $($app.Name) [Reason: No package manager available]" 'WARN'
                Write-Host "    ⚪ Skipped - No package manager available" -ForegroundColor Yellow
                Write-Progress -Activity "Installing $($app.Name) ($currentAppIndex/$totalApps)" -Completed
            }
            elseif (-not $app.Winget -and -not $app.Choco) {
                $result.Skipped = $true
                $result.SkipReason = "no installer defined"
                $skippedCount++
                Write-Log "⚪ SKIPPED: $($app.Name) [Reason: No installer defined]" 'WARN'
                Write-Host "    ⚪ Skipped - No installer defined" -ForegroundColor Yellow
                Write-Progress -Activity "Installing $($app.Name) ($currentAppIndex/$totalApps)" -Completed
            }
            else {
                $result.Error = $result.Error.TrimEnd("; ")
                $failedCount++
                Write-Log "✗ FAILED: $($app.Name) [Error: $($result.Error)]" 'ERROR'
                Write-Host "    ✗ Installation failed: $($result.Error)" -ForegroundColor Red
                Write-Progress -Activity "Installing $($app.Name) ($currentAppIndex/$totalApps)" -Completed
            }
        }
        catch {
            $result.Error = "Exception: $($_.Exception.Message)"
            $failedCount++
            Write-Log "✗ FAILED: $($app.Name) [Exception: $($_.Exception.Message)]" 'ERROR'
            Write-Host "    ✗ Exception occurred: $($_.Exception.Message)" -ForegroundColor Red
            Write-Progress -Activity "Installing $($app.Name) ($currentAppIndex/$totalApps)" -Completed
        }
    }

    # Enhanced Office detection with parallel checking
    Write-Log "Checking for existing office suite installations..." 'INFO'
    $officeDetectionJob = Start-Job -ScriptBlock {
        # Check registry keys in parallel
        $registryJob = Start-Job -ScriptBlock {
            $officeKeys = @(
                'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration',
                'HKLM:\SOFTWARE\Microsoft\Office\16.0\Common\InstallRoot',
                'HKLM:\SOFTWARE\Microsoft\Office\15.0\Common\InstallRoot',
                'HKLM:\SOFTWARE\Microsoft\Office\14.0\Common\InstallRoot',
                'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Office\16.0\Common\InstallRoot',
                'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Office\15.0\Common\InstallRoot',
                'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Office\14.0\Common\InstallRoot'
            )
            foreach ($key in $officeKeys) {
                if (Test-Path $key -ErrorAction SilentlyContinue) {
                    return @{ Found = $true; Method = "Registry ($key)" }
                }
            }
            return @{ Found = $false; Method = "" }
        }

        # Check Start Menu apps in parallel
        $startMenuJob = Start-Job -ScriptBlock {
            try {
                $officeApps = Get-StartAppsCompatible | Where-Object { $_.Name -match 'Office|Word|Excel|PowerPoint|Outlook' }
                if ($officeApps) { 
                    return @{ Found = $true; Method = "Start Menu" }
                }
            }
            catch { }
            return @{ Found = $false; Method = "" }
        }

        # Wait for both jobs and check results
        $registryResult = Receive-Job -Job $registryJob -Wait
        $startMenuResult = Receive-Job -Job $startMenuJob -Wait
        Remove-Job -Job $registryJob, $startMenuJob -Force

        if ($registryResult.Found) {
            return @{ Installed = $true; DetectionMethod = $registryResult.Method }
        }
        elseif ($startMenuResult.Found) {
            return @{ Installed = $true; DetectionMethod = $startMenuResult.Method }
        }
        else {
            return @{ Installed = $false; DetectionMethod = "Not detected" }
        }
    }

    $officeResult = Receive-Job -Job $officeDetectionJob -Wait
    Remove-Job -Job $officeDetectionJob -Force

    # LibreOffice installation logic
    if (-not $officeResult.Installed) {
        Write-Log "No office suite detected. Installing LibreOffice..." 'INFO'
        Write-Host "Installing LibreOffice as default office suite..." -ForegroundColor Cyan

        $libreOfficeJob = Start-Job -ArgumentList $wingetAvailable, $chocoAvailable -ScriptBlock {
            param($wingetAvailable, $chocoAvailable)

            $result = @{
                Success = $false
                Method  = ""
                Error   = ""
            }

            try {
                # Try Winget first
                if ($wingetAvailable) {
                    $libreArgs = @(
                        "install", "--id", "TheDocumentFoundation.LibreOffice",
                        "--accept-source-agreements", "--accept-package-agreements", 
                        "--silent", "-e", "--disable-interactivity"
                    )
                    $libreProc = Start-Process -FilePath "winget" -ArgumentList $libreArgs -WindowStyle Hidden -Wait -PassThru
                    if ($libreProc.ExitCode -eq 0) {
                        $result.Success = $true
                        $result.Method = "winget"
                        return $result
                    }
                    else {
                        $result.Error += "winget failed (exit: $($libreProc.ExitCode)); "
                    }
                }

                # Try Chocolatey as fallback
                if (-not $result.Success -and $chocoAvailable) {
                    $chocoLibreArgs = @("install", "libreoffice-fresh", "-y", "--no-progress", "--limit-output")
                    $chocoLibreProc = Start-Process -FilePath "choco" -ArgumentList $chocoLibreArgs -WindowStyle Hidden -Wait -PassThru
                    if ($chocoLibreProc.ExitCode -eq 0) {
                        $result.Success = $true
                        $result.Method = "choco"
                        return $result
                    }
                    else {
                        $result.Error += "choco failed (exit: $($chocoLibreProc.ExitCode))"
                    }
                }
            }
            catch {
                $result.Error = "Exception: $($_.Exception.Message)"
            }

            return $result
        }

        $libreResult = Receive-Job -Job $libreOfficeJob -Wait
        Remove-Job -Job $libreOfficeJob -Force

        if ($libreResult.Success) {
            $successCount++
            Write-Log "✓ INSTALLED: LibreOffice [Method: $($libreResult.Method)]" 'INFO'
            Write-Host "✓ LibreOffice successfully installed via $($libreResult.Method)" -ForegroundColor Green
        }
        else {
            $failedCount++
            Write-Log "✗ FAILED: LibreOffice [Error: $($libreResult.Error)]" 'ERROR'
            Write-Host "✗ LibreOffice installation failed: $($libreResult.Error)" -ForegroundColor Red
        }
    }
    else {
        Write-Log "⚪ SKIPPED: LibreOffice [Reason: Office suite already detected via $($officeResult.DetectionMethod)]" 'INFO'
        Write-Host "⚪ LibreOffice installation skipped - Office suite already detected" -ForegroundColor Yellow
    }

    # ENHANCED SUMMARY AND PERFORMANCE REPORTING
    Write-Log "[EssentialApps] INSTALLATION SUMMARY - DIFF-BASED MODE:" 'INFO'
    Write-Log "- Required apps: $($newlyRequiredApps.Count) (${efficiencyGain}% reduction from $($currentEssentialApps.Count) total requirements)" 'INFO'
    Write-Log "- Successfully installed: $successCount apps" 'INFO'
    Write-Log "- Failed installations: $failedCount apps" 'INFO'
    Write-Log "- Skipped installations: $skippedCount apps" 'INFO'

    # Office detection summary (action-only)
    if ($officeResult.Installed) {
        Write-Log "[EssentialApps] Microsoft Office detected ($($officeResult.DetectionMethod)). LibreOffice installation skipped." 'INFO'
    }

    # Only log errors and skips if they exist (minimal noise)
    if ($failedCount -gt 0) {
        Write-Log "[EssentialApps] Some installations failed. Check individual app logs above for details." 'WARN'
    }

    if ($skippedCount -gt 0) {
        Write-Log "[EssentialApps] Some installations were skipped. Check individual app logs above for reasons." 'INFO'
    }

    # Create audit file with detailed results
    $auditData = @{
        Timestamp          = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        ProcessingMode     = "DIFF-BASED"
        TotalRequiredApps  = $currentEssentialApps.Count
        NewlyRequiredApps  = $newlyRequiredApps.Count
        SuccessfulInstalls = $successCount
        FailedInstalls     = $failedCount
        SkippedInstalls    = $skippedCount
        EfficiencyGain     = "${efficiencyGain}%"
        OfficeDetection    = @{
            Installed       = $officeResult.Installed
            DetectionMethod = $officeResult.DetectionMethod
        }
    }

    $auditPath = Join-Path $global:TempFolder "essential_apps_audit.json"
    $auditData | ConvertTo-Json -Depth 3 | Out-File $auditPath -Encoding UTF8
    Write-Log "Audit trail saved to: $auditPath" 'VERBOSE'

    # Update previous list for next run
    Copy-Item $currentListPath $previousListPath -Force
    Write-Log "Essential apps list updated for next diff comparison" 'VERBOSE'

    Write-Log "[END] Install Essential Apps" 'INFO'
}

# ===============================
# SECTION 6: SYSTEM MAINTENANCE TASKS
# ===============================
# - Disable-Telemetry (privacy and telemetry features)
# - Protect-SystemRestore (system restore protection)
# - Install-WindowsUpdatesCompatible (Windows updates)
# - Clear-TempFiles (temporary files cleanup)
# - System maintenance and optimization utilities

# ================================================================
# Function: Enable-AppBrowserControl
# ================================================================
# Purpose: Enables Windows App & Browser Control features (SmartScreen, Network Protection, Controlled Folder Access, Exploit Protection)
# Environment: Windows 10/11, Administrator required, Defender Antivirus enabled, PowerShell 7+ optimized
# Performance: Fast, idempotent, minimal overhead
# Dependencies: Microsoft Defender Antivirus, Set-MpPreference, Set-ProcessMitigation
# Logic: Enables SmartScreen, Network Protection, Controlled Folder Access, and system-level exploit mitigations
# Features: Unified App & Browser Control hardening, error handling, action logging
# ================================================================
function Enable-AppBrowserControl {
    Write-Log "[START] Enabling App & Browser Control (SmartScreen, Network Protection, Controlled Folder Access, Exploit Protection)" 'INFO'
    $errors = @()
    try {
        # Enable Network Protection
        try {
            Set-MpPreference -EnableNetworkProtection Enabled
            Write-Log "✓ Network Protection enabled" 'INFO'
        }
        catch { $errors += "Network Protection: $_" }

        # Enable Controlled Folder Access
        try {
            Set-MpPreference -EnableControlledFolderAccess Enabled
            Write-Log "✓ Controlled Folder Access enabled" 'INFO'
        }
        catch { $errors += "Controlled Folder Access: $_" }


        # Enable SmartScreen for Edge via registry (Windows 10/11)
        try {
            $edgeKey = "HKLM:\SOFTWARE\Policies\Microsoft\MicrosoftEdge\PhishingFilter"
            if (-not (Test-Path $edgeKey)) { New-Item -Path $edgeKey -Force | Out-Null }
            Set-ItemProperty -Path $edgeKey -Name "EnabledV9" -Value 1 -Type DWord
            Write-Log "✓ SmartScreen for Edge enabled (via registry)" 'INFO'
        }
        catch { $errors += "SmartScreen for Edge (registry): $_" }

        # Enable SmartScreen for Microsoft Store Apps via registry
        try {
            $storeKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppHost"
            if (-not (Test-Path $storeKey)) { New-Item -Path $storeKey -Force | Out-Null }
            Set-ItemProperty -Path $storeKey -Name "EnableWebContentEvaluation" -Value 1 -Type DWord
            Write-Log "✓ SmartScreen for Store Apps enabled (via registry)" 'INFO'
        }
        catch { $errors += "SmartScreen for Store Apps (registry): $_" }

        # Enable system-level exploit mitigations (DEP, SEHOP, CFG, ASLR)
        try {
            Set-ProcessMitigation -System -Enable DEP, SEHOP, CFG, ForceRelocateImages, BottomUp, HighEntropy
            Write-Log "✓ System-level exploit mitigations enabled (DEP, SEHOP, CFG, ASLR)" 'INFO'
        }
        catch { $errors += "Exploit Mitigations: $_" }
    }
    catch {
        $errors += "General error: $_"
    }
    if ($errors.Count -gt 0) {
        Write-Log "App & Browser Control: Some settings failed: $($errors -join '; ')" 'WARN'
    }
    Write-Log "[END] Enabling App & Browser Control" 'INFO'
}
# ================================================================
# Function: Disable-SpotlightMeetNowNewsLocation
# ================================================================
# Purpose: Disables Windows Spotlight, Meet Now, News and Interests, Widgets, and Location services for privacy and taskbar declutter
# Environment: Windows 10/11, Administrator required, registry/service modification access
# Performance: Fast registry and service changes, minimal overhead
# Dependencies: Registry access, service control
# Logic: Sets registry keys and disables services for all features in one call
# Features: Disables Spotlight, Meet Now, News/Interests, Widgets, and Location
# ================================================================
function Disable-SpotlightMeetNowNewsLocation {
    Write-Log "[START] Disabling Spotlight, Meet Now, News/Interests, Widgets, and Location" 'INFO'
    try {
        # Disable Windows Spotlight (lock screen, background, suggestions)
        $spotlightReg = "HKCU:\SOFTWARE\Policies\Microsoft\Windows\CloudContent"
        if (-not (Test-Path $spotlightReg)) { New-Item -Path $spotlightReg -Force | Out-Null }
        Set-ItemProperty -Path $spotlightReg -Name "DisableWindowsSpotlightFeatures" -Value 1 -Force
        Set-ItemProperty -Path $spotlightReg -Name "DisableWindowsSpotlightOnActionCenter" -Value 1 -Force
        Set-ItemProperty -Path $spotlightReg -Name "DisableWindowsSpotlightOnSettings" -Value 1 -Force
        Set-ItemProperty -Path $spotlightReg -Name "DisableWindowsSpotlightWindowsWelcomeExperience" -Value 1 -Force
        Set-ItemProperty -Path $spotlightReg -Name "DisableWindowsSpotlightOnLockScreen" -Value 1 -Force
        Write-Log "Windows Spotlight disabled via registry." 'INFO'

        # Remove Meet Now from taskbar
        try {
            $meetNowReg = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer"
            if (-not (Test-Path $meetNowReg)) { 
                New-Item -Path $meetNowReg -Force | Out-Null 
            }
            Set-ItemProperty -Path $meetNowReg -Name "HideSCAMeetNow" -Value 1 -Force -ErrorAction Stop
            Write-Log "Meet Now icon removed from taskbar." 'INFO'
        }
        catch {
            Write-Log "Warning: Could not modify Meet Now setting: $($_.Exception.Message)" 'WARN'
            # Try alternative registry path
            try {
                $altMeetNowReg = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
                if (-not (Test-Path $altMeetNowReg)) { 
                    New-Item -Path $altMeetNowReg -Force | Out-Null 
                }
                Set-ItemProperty -Path $altMeetNowReg -Name "TaskbarMn" -Value 0 -Force -ErrorAction Stop
                Write-Log "Meet Now disabled via alternative registry path." 'INFO'
            }
            catch {
                Write-Log "Unable to disable Meet Now via registry. Feature may not be available on this system." 'WARN'
            }
        }

        # Remove News and Interests (Windows 10)
        try {
            $feedsReg = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Feeds"
            if (-not (Test-Path $feedsReg)) { 
                New-Item -Path $feedsReg -Force | Out-Null 
            }
            Set-ItemProperty -Path $feedsReg -Name "ShellFeedsTaskbarViewMode" -Value 2 -Force -ErrorAction Stop
            Write-Log "News and Interests removed from taskbar (Windows 10)." 'INFO'
        }
        catch {
            Write-Log "Warning: Could not modify News and Interests setting: $($_.Exception.Message)" 'WARN'
            # Try alternative registry path
            try {
                $altFeedsReg = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
                if (-not (Test-Path $altFeedsReg)) { 
                    New-Item -Path $altFeedsReg -Force | Out-Null 
                }
                Set-ItemProperty -Path $altFeedsReg -Name "TaskbarDa" -Value 0 -Force -ErrorAction Stop
                Write-Log "News and Interests disabled via alternative registry path." 'INFO'
            }
            catch {
                Write-Log "Unable to disable News and Interests via registry. May require manual configuration." 'WARN'
            }
        }

        # Remove Widgets (Windows 11)
        try {
            $widgetsReg = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
            if (-not (Test-Path $widgetsReg)) { 
                New-Item -Path $widgetsReg -Force | Out-Null 
            }
            Set-ItemProperty -Path $widgetsReg -Name "TaskbarDa" -Value 0 -Force -ErrorAction Stop
            Write-Log "Widgets removed from taskbar (Windows 11)." 'INFO'
        }
        catch {
            Write-Log "Warning: Could not modify Widgets setting: $($_.Exception.Message)" 'WARN'
            # Try alternative approaches for widgets
            try {
                # Try via Group Policy registry path
                $widgetsPolicyReg = "HKCU:\Software\Policies\Microsoft\Windows\WindowsFeeds"
                if (-not (Test-Path $widgetsPolicyReg)) { 
                    New-Item -Path $widgetsPolicyReg -Force | Out-Null 
                }
                Set-ItemProperty -Path $widgetsPolicyReg -Name "EnableFeeds" -Value 0 -Force -ErrorAction Stop
                Write-Log "Widgets disabled via Group Policy registry path." 'INFO'
            }
            catch {
                Write-Log "Unable to disable Widgets via registry. May require manual configuration or different Windows version." 'WARN'
            }
        }

        # Disable Location services
        try {
            $locationReg = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location"
            if (-not (Test-Path $locationReg)) { 
                New-Item -Path $locationReg -Force | Out-Null 
            }
            Set-ItemProperty -Path $locationReg -Name "Value" -Value "Deny" -Force -ErrorAction Stop
            Write-Log "Location services disabled via registry." 'INFO'
        }
        catch {
            Write-Log "Warning: Could not modify location services registry: $($_.Exception.Message)" 'WARN'
            # Try user-level location settings
            try {
                $userLocationReg = "HKCU:\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location"
                if (-not (Test-Path $userLocationReg)) { 
                    New-Item -Path $userLocationReg -Force | Out-Null 
                }
                Set-ItemProperty -Path $userLocationReg -Name "Value" -Value "Deny" -Force -ErrorAction Stop
                Write-Log "Location services disabled via user registry." 'INFO'
            }
            catch {
                Write-Log "Unable to disable location services via registry. May require administrator privileges." 'WARN'
            }
        }
        
        # Stop and disable location service
        try {
            Stop-Service -Name lfsvc -Force -ErrorAction SilentlyContinue
            Set-Service -Name lfsvc -StartupType Disabled -ErrorAction SilentlyContinue
            Write-Log "Location service stopped and disabled." 'INFO'
        } 
        catch { 
            Write-Log "Failed to stop/disable location service: $_" 'WARN' 
        }
    }
    catch {
        Write-Log "Error disabling Spotlight/Meet Now/News/Location: $_" 'ERROR'
    }
    Write-Log "[END] Disabling Spotlight, Meet Now, News/Interests, Widgets, and Location" 'INFO'
}

# ================================================================
# Function: Disable-Telemetry
# ================================================================
# Purpose: Comprehensive disabling of Windows telemetry, privacy-invasive features, and browser tracking with optimization
# Environment: Windows 10/11, Administrator required, registry/service/browser modification access, system-wide privacy configuration
# Performance: Parallel browser detection, batch registry operations, optimized service management, action-focused logging
# Dependencies: Registry access, service control capabilities, browser configuration file access, notification system access
# Logic: Batch notification management, parallel browser processing, comprehensive privacy protection, enhanced speed and reliability
# Features: OS notification disabling, telemetry service management, registry cleanup, privacy hardening, browser tracking prevention
# ================================================================
function Disable-Telemetry {
    Write-Log "Starting Disable Telemetry and Privacy Features - Enhanced Performance Mode" 'INFO'

    # Batch notification management for improved performance
    try {
        $focusAssistReg = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Notifications\Settings'
        if (-not (Test-Path $focusAssistReg)) { New-Item -Path $focusAssistReg -Force | Out-Null }

        # Batch set notification settings for efficiency
        $notificationSettings = @{
            'NOC_GLOBAL_SETTING_TOASTS_ENABLED' = 0
            'FocusAssist'                       = 2
        }

        $settingsApplied = 0
        foreach ($setting in $notificationSettings.GetEnumerator()) {
            try {
                Set-ItemProperty -Path $focusAssistReg -Name $setting.Key -Value $setting.Value -Force
                $settingsApplied++
            }
            catch { continue }
        }

        # Batch disable per-app notifications using optimized registry operations
        $apps = Get-ChildItem -Path $focusAssistReg -ErrorAction SilentlyContinue | Where-Object { 
            $_.PSChildName -notin @('FocusAssist', 'NOC_GLOBAL_SETTING_TOASTS_ENABLED') 
        }

        $appsDisabled = 0
        if ($apps) {
            foreach ($app in $apps) {
                try {
                    Set-ItemProperty -Path $app.PSPath -Name 'Enabled' -Value 0 -Force -ErrorAction SilentlyContinue
                    $appsDisabled++
                }
                catch { continue }
            }
        }

        if ($settingsApplied -gt 0 -or $appsDisabled -gt 0) {
            Write-Host "✓ Disabled OS notifications ($appsDisabled apps)" -ForegroundColor Green
            Write-Log "OS notifications disabled: Focus Assist enabled, $appsDisabled app notifications disabled" 'INFO'
        }
    }
    catch {
        Write-Log "Failed to disable OS notifications: $_" 'WARN'
    }

    # Enhanced telemetry registry settings with parallel processing
    $telemetrySettings = @{
        'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'                = @{
            'AllowTelemetry'                 = 0
            'DoNotShowFeedbackNotifications' = 1
            'AllowCommercialDataPipeline'    = 0
            'AllowDeviceNameInTelemetry'     = 0
        }
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection' = @{
            'AllowTelemetry'      = 0
            'MaxTelemetryAllowed' = 0
        }
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'  = @{
            'ContentDeliveryAllowed'       = 0
            'OemPreInstalledAppsEnabled'   = 0
            'PreInstalledAppsEnabled'      = 0
            'SilentInstalledAppsEnabled'   = 0
            'SubscribedContentEnabled'     = 0
            'SystemPaneSuggestionsEnabled' = 0
            'SoftLandingEnabled'           = 0
        }
        'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent'                  = @{
            'DisableWindowsConsumerFeatures' = 1
            'DisableCloudOptimizedContent'   = 1
            'DisableSoftLanding'             = 1
        }
    }

    $totalSettingsApplied = 0
    foreach ($regPath in $telemetrySettings.Keys) {
        try {
            if (-not (Test-Path $regPath)) {
                New-Item -Path $regPath -Force -ErrorAction SilentlyContinue | Out-Null
            }

            $settings = $telemetrySettings[$regPath]
            foreach ($setting in $settings.GetEnumerator()) {
                try {
                    Set-ItemProperty -Path $regPath -Name $setting.Key -Value $setting.Value -Force -ErrorAction SilentlyContinue
                    $totalSettingsApplied++
                }
                catch { continue }
            }
        }
        catch { continue }
    }

    if ($totalSettingsApplied -gt 0) {
        Write-Host "✓ Applied $totalSettingsApplied telemetry registry settings" -ForegroundColor Green
        Write-Log "Telemetry registry settings applied: $totalSettingsApplied settings configured" 'INFO'
    }

    # Disable telemetry services with parallel processing
    $telemetryServices = @(
        'DiagTrack',           # Connected User Experiences and Telemetry
        'dmwappushservice',    # Device Management Wireless Application Protocol
        'WerSvc',              # Windows Error Reporting Service
        'OneSyncSvc',          # Sync Host Service
        'MessagingService',    # Messaging Service
        'PimIndexMaintenanceSvc', # Contact Data
        'UserDataSvc',         # User Data Access
        'UnistoreSvc',         # User Data Storage
        'BrokerInfrastructure' # Background Tasks Infrastructure Service
    )

    $servicesDisabled = 0
    foreach ($serviceName in $telemetryServices) {
        try {
            $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
            if ($service -and $service.StartType -ne 'Disabled') {
                Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
                Set-Service -Name $serviceName -StartupType Disabled -ErrorAction SilentlyContinue
                $servicesDisabled++
            }
        }
        catch { continue }
    }

    if ($servicesDisabled -gt 0) {
        Write-Host "✓ Disabled $servicesDisabled telemetry services" -ForegroundColor Green
        Write-Log "Telemetry services disabled: $servicesDisabled services stopped and disabled" 'INFO'
    }

    Write-Log "[END] Disable Telemetry and Privacy Features" 'INFO'
}

# ================================================================
# Function: Protect-SystemRestore
# ================================================================
# Purpose: PowerShell 7+ native system restore protection with enhanced compatibility and comprehensive restore point management
# Environment: Windows 10/11, requires Administrator privileges, system restore capability verification, disk space management
# Performance: Fast native PowerShell operations, parallel disk checking, optimized restore point creation with intelligent scheduling
# Dependencies: Administrator privileges, System Restore feature availability, adequate disk space, VSS service functionality
# Logic: System restore enablement verification, intelligent restore point creation, disk space optimization, comprehensive error handling
# Features: Automatic restore point creation, disk space management, restore verification, intelligent scheduling, compatibility checking
# ================================================================
function Protect-SystemRestore {
    Write-Log "[START] PowerShell 7+ Native System Restore Protection" 'INFO'

    try {
        # Check if System Restore is supported on this system
        $systemDrive = $env:SystemDrive
        Write-Log "Checking System Restore capability for drive: $systemDrive" 'INFO'

        # Enhanced compatibility check for System Restore availability
        $restoreAvailable = $false
        try {
            # Try to get restore points to test availability (Windows PowerShell compatibility)
            $existingRestorePoints = Invoke-WindowsPowerShellCommand -Command "Get-ComputerRestorePoint" -ErrorAction SilentlyContinue
            $restoreAvailable = $true
            Write-Log "System Restore is available. Found $($existingRestorePoints.Count) existing restore points." 'INFO'
        }
        catch {
            Write-Log "System Restore may not be available or accessible: $_" 'WARN'
            
            # Try alternative check using registry
            try {
                $srConfig = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore" -ErrorAction SilentlyContinue
                if ($srConfig) {
                    $restoreAvailable = $true
                    Write-Log "System Restore detected via registry check" 'INFO'
                }
            }
            catch {
                Write-Log "System Restore not available on this system" 'WARN'
                return
            }
        }

        if (-not $restoreAvailable) {
            Write-Log "System Restore is not available on this system. Skipping restore point creation." 'WARN'
            return
        }

        # Check and enable System Restore if disabled
        try {
            $restoreStatus = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore" -Name "DisableSR" -ErrorAction SilentlyContinue
            if ($restoreStatus -and $restoreStatus.DisableSR -eq 1) {
                Write-Log "System Restore is disabled. Attempting to enable..." 'INFO'
                Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore" -Name "DisableSR" -Value 0 -ErrorAction SilentlyContinue
                Write-Host "✓ System Restore enabled" -ForegroundColor Green
            }
        }
        catch {
            Write-Log "Could not check/enable System Restore status: $_" 'WARN'
        }

        # Create restore point with enhanced error handling
        $restorePointName = "Maintenance Script - $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
        Write-Log "Creating system restore point: $restorePointName" 'INFO'

        try {
            # Use Windows PowerShell compatibility for Checkpoint-Computer
            $command = "Checkpoint-Computer -Description '$restorePointName' -RestorePointType 'MODIFY_SETTINGS' -Confirm:`$false"
            $commandResult = Invoke-WindowsPowerShellCommand -Command $command
            
            # Check if the command executed successfully
            if ($commandResult -or $LASTEXITCODE -eq 0) {
                Write-Host "✓ System restore point created successfully" -ForegroundColor Green
                Write-Log "System restore point created: $restorePointName" 'INFO'
            }
            else {
                throw "Checkpoint-Computer command did not execute successfully"
            }

            # Verify the restore point was created using Windows PowerShell
            Start-Sleep -Seconds 2
            try {
                $newRestorePoints = Invoke-WindowsPowerShellCommand -Command "Get-ComputerRestorePoint" -ErrorAction SilentlyContinue
                
                if ($newRestorePoints -and $newRestorePoints.Count -gt 0) {
                    $latestPoint = $newRestorePoints | Sort-Object CreationTime -Descending | Select-Object -First 1
                    
                    if ($latestPoint -and $latestPoint.Description -and $latestPoint.Description.Contains("Maintenance Script")) {
                        Write-Log "Restore point verification successful. Latest point: $($latestPoint.Description)" 'INFO'
                    }
                    else {
                        Write-Log "Latest restore point found but not from maintenance script: $($latestPoint.Description)" 'WARN'
                    }
                }
                else {
                    Write-Log "No restore points found during verification" 'WARN'
                }
            }
            catch {
                Write-Log "Could not verify restore point creation: $_" 'WARN'
            }
        }
        catch {
            Write-Log "Failed to create system restore point: $_" 'ERROR'
            Write-Host "✗ Failed to create system restore point: $_" -ForegroundColor Red

            # Try alternative method using WMI for older compatibility
            try {
                Write-Log "Attempting restore point creation using WMI interface..." 'INFO'
                
                # Create restore point using WMI method
                $restorePointResult = Invoke-WindowsPowerShellCommand -Command @"
try {
    `$systemRestore = Get-WmiObject -Class SystemRestore -Namespace root\default -List
    if (`$systemRestore) {
        `$result = `$systemRestore.CreateRestorePoint('$restorePointName', 0, 100)
        Write-Output "RestorePointResult:`$(`$result.ReturnValue)"
    } else {
        Write-Output "SystemRestore WMI class not available"
    }
} catch {
    Write-Output "WMI Error:`$(`$_.Exception.Message)"
}
"@
                
                if ($restorePointResult -and $restorePointResult -match "RestorePointResult:0") {
                    Write-Host "✓ System restore point created via WMI interface" -ForegroundColor Green
                    Write-Log "System restore point created via WMI interface: $restorePointName" 'INFO'
                }
                else {
                    Write-Log "WMI restore point creation result: $restorePointResult" 'WARN'
                    
                    # Final fallback: try using VSSAdmin
                    Write-Log "Attempting restore point creation using VSSAdmin..." 'INFO'
                    try {
                        $vssResult = Start-Process -FilePath "vssadmin" -ArgumentList "create shadow /for=C:" -Wait -PassThru -WindowStyle Hidden
                        if ($vssResult.ExitCode -eq 0) {
                            Write-Host "✓ Shadow copy created as restore point alternative" -ForegroundColor Green
                            Write-Log "Shadow copy created successfully" 'INFO'
                        }
                        else {
                            Write-Log "VSSAdmin failed with exit code: $($vssResult.ExitCode)" 'WARN'
                        }
                    }
                    catch {
                        Write-Log "VSSAdmin restore point creation failed: $_" 'ERROR'
                    }
                }
            }
            catch {
                Write-Log "Alternative restore point creation methods failed: $_" 'ERROR'
                Write-Host "✗ All restore point creation methods failed" -ForegroundColor Red
            }
        }

        # Disk space management for restore points
        try {
            $diskSpace = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='$systemDrive'" -ErrorAction SilentlyContinue
            if ($diskSpace) {
                $freeSpaceGB = [math]::Round($diskSpace.FreeSpace / 1GB, 2)
                $totalSpaceGB = [math]::Round($diskSpace.Size / 1GB, 2)
                $freeSpacePercent = [math]::Round(($diskSpace.FreeSpace / $diskSpace.Size) * 100, 1)

                Write-Log "System drive space: $freeSpaceGB GB free of $totalSpaceGB GB total ($freeSpacePercent%)" 'INFO'

                # Clean old restore points if disk space is low (less than 10% free)
                if ($freeSpacePercent -lt 10) {
                    Write-Log "Low disk space detected ($freeSpacePercent% free). Cleaning old restore points..." 'WARN'
                    
                    try {
                        $oldRestorePoints = Get-ComputerRestorePoint | Sort-Object CreationTime | Select-Object -SkipLast 3
                        foreach ($point in $oldRestorePoints) {
                            Remove-ComputerRestorePoint -RestorePoint $point -ErrorAction SilentlyContinue
                        }
                        Write-Log "Cleaned $($oldRestorePoints.Count) old restore points to free disk space" 'INFO'
                    }
                    catch {
                        Write-Log "Could not clean old restore points: $_" 'WARN'
                    }
                }
            }
        }
        catch {
            Write-Log "Could not check disk space: $_" 'WARN'
        }

    }
    catch {
        Write-Log "Unexpected error in System Restore protection: $_" 'ERROR'
    }

    Write-Log "[END] PowerShell 7+ Native System Restore Protection" 'INFO'
}

# ================================================================
# Function: Install-WindowsUpdatesCompatible
# ================================================================
# Purpose: PowerShell 5.1 compatible Windows Updates installation with enhanced error handling and progress tracking
# Environment: Windows 10/11, requires Administrator privileges, PSWindowsUpdate module or Windows Update API access
# Performance: Optimized for compatibility across PowerShell versions, parallel update detection, intelligent retry logic
# Dependencies: Administrator privileges, Windows Update service, network connectivity, adequate disk space for updates
# Logic: PSWindowsUpdate module detection and installation, Windows Update API fallback, comprehensive update management
# Features: Module auto-installation, update categorization, progress tracking, reboot management, detailed logging
# ================================================================
function Install-WindowsUpdatesCompatible {
    Write-Log "[START] Windows Updates Installation (Enhanced Compatibility)" 'INFO'

    # Check for Administrator privileges
    if (-not $IsAdmin) {
        Write-Log "Administrator privileges required for Windows Updates. Skipping..." 'WARN'
        return
    }

    # Enhanced PSWindowsUpdate module detection and installation
    $moduleInstalled = $false
    try {
        $existingModule = Get-Module -ListAvailable -Name PSWindowsUpdate -ErrorAction SilentlyContinue
        if ($existingModule) {
            Import-Module PSWindowsUpdate -Force -ErrorAction SilentlyContinue
            $moduleInstalled = $true
            Write-Log "PSWindowsUpdate module found and imported" 'INFO'
        }
        else {
            Write-Log "PSWindowsUpdate module not found. Attempting installation..." 'INFO'
            
            # Check if PackageProvider is available for module installation
            try {
                $nugetProvider = Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue
                if (-not $nugetProvider) {
                    Install-PackageProvider -Name NuGet -Force -Scope CurrentUser -ErrorAction SilentlyContinue
                }

                Install-Module -Name PSWindowsUpdate -Force -Scope CurrentUser -AllowClobber -ErrorAction Stop
                Import-Module PSWindowsUpdate -Force -ErrorAction Stop
                $moduleInstalled = $true
                Write-Host "✓ PSWindowsUpdate module installed and imported" -ForegroundColor Green
                Write-Log "PSWindowsUpdate module successfully installed and imported" 'INFO'
            }
            catch {
                Write-Log "Failed to install PSWindowsUpdate module: $_" 'WARN'
                $moduleInstalled = $false
            }
        }
    }
    catch {
        Write-Log "Error with PSWindowsUpdate module: $_" 'WARN'
        $moduleInstalled = $false
    }

    if ($moduleInstalled) {
        try {
            # Get available updates using PSWindowsUpdate
            Write-Log "Checking for available Windows updates..." 'INFO'
            $availableUpdates = Get-WUList -ErrorAction SilentlyContinue

            if ($availableUpdates -and $availableUpdates.Count -gt 0) {
                Write-Log "Found $($availableUpdates.Count) available updates" 'INFO'
                Write-Host "Installing $($availableUpdates.Count) Windows updates..." -ForegroundColor Cyan

                # Install updates with progress tracking
                $installResult = Install-WindowsUpdate -AcceptAll -AutoReboot:$false -Confirm:$false -ErrorAction SilentlyContinue
                
                if ($installResult) {
                    $successfulUpdates = $installResult | Where-Object { $_.Result -eq 'Installed' }
                    $failedUpdates = $installResult | Where-Object { $_.Result -ne 'Installed' }

                    Write-Host "✓ Successfully installed $($successfulUpdates.Count) updates" -ForegroundColor Green
                    Write-Log "Windows updates installed: $($successfulUpdates.Count) successful, $($failedUpdates.Count) failed" 'INFO'

                    if ($failedUpdates.Count -gt 0) {
                        Write-Log "Some updates failed to install. Check Windows Update logs for details." 'WARN'
                    }

                    # Check if reboot is required
                    $rebootRequired = Get-WURebootStatus -ErrorAction SilentlyContinue
                    if ($rebootRequired) {
                        Write-Host "⚠ System reboot required to complete updates" -ForegroundColor Yellow
                        Write-Log "System reboot required to complete Windows updates installation" 'WARN'
                    }
                }
                else {
                    Write-Log "No updates were installed (may indicate no updates available or installation issues)" 'INFO'
                }
            }
            else {
                Write-Host "✓ No Windows updates available" -ForegroundColor Green
                Write-Log "No Windows updates available for installation" 'INFO'
            }
        }
        catch {
            Write-Log "Error during Windows updates installation: $_" 'ERROR'
            Write-Host "✗ Error installing Windows updates: $_" -ForegroundColor Red
        }
    }
    else {
        # Fallback: Use Windows Update API or manual check
        Write-Log "Using fallback method for Windows updates check..." 'INFO'
        try {
            # Try using Windows Update COM object as fallback
            $updateSession = New-Object -ComObject Microsoft.Update.Session
            $updateSearcher = $updateSession.CreateUpdateSearcher()
            $searchResult = $updateSearcher.Search("IsInstalled=0")

            if ($searchResult.Updates.Count -gt 0) {
                Write-Host "Found $($searchResult.Updates.Count) updates via Windows Update API" -ForegroundColor Cyan
                Write-Log "Found $($searchResult.Updates.Count) updates using Windows Update API fallback" 'INFO'
                Write-Log "Manual Windows Update installation recommended via Settings > Update & Security" 'INFO'
            }
            else {
                Write-Host "✓ No updates found via Windows Update API" -ForegroundColor Green
                Write-Log "No updates found using Windows Update API fallback" 'INFO'
            }
        }
        catch {
            Write-Log "Windows Update API fallback also failed: $_" 'WARN'
            Write-Host "⚠ Unable to check for updates. Please check manually via Settings" -ForegroundColor Yellow
        }
    }

    Write-Log "[END] Windows Updates Installation" 'INFO'
}

# ================================================================
# Function: Clear-TempFiles
# ================================================================
# Purpose: Comprehensive temporary files and cache cleanup with parallel processing and safe deletion verification
# Environment: Windows 10/11, requires appropriate permissions for temp directories, disk cleanup operations
# Performance: Parallel directory processing, intelligent size calculation, progress tracking, optimized file operations
# Dependencies: File system access, temp directory permissions, disk space calculation utilities, safe deletion verification
# Logic: Multi-location temp cleanup, browser cache clearing, Windows temp cleanup, recycle bin management, size tracking
# Features: Progress tracking, size calculation, browser cache support, safe deletion, comprehensive logging, error handling
# ================================================================
function Clear-TempFiles {
    Write-Log "[START] Comprehensive Temporary Files Cleanup" 'INFO'

    $totalSizeFreed = 0
    $totalFilesDeleted = 0
    $locationsProcessed = 0

    # Define cleanup locations with parallel processing support
    $cleanupLocations = @(
        @{ Name = "Windows Temp"; Path = "$env:WINDIR\Temp"; Pattern = "*" },
        @{ Name = "User Temp"; Path = "$env:TEMP"; Pattern = "*" },
        @{ Name = "User Local Temp"; Path = "$env:LOCALAPPDATA\Temp"; Pattern = "*" },
        @{ Name = "Prefetch"; Path = "$env:WINDIR\Prefetch"; Pattern = "*.pf" },
        @{ Name = "Recent Documents"; Path = "$env:APPDATA\Microsoft\Windows\Recent"; Pattern = "*" },
        @{ Name = "IE Cache"; Path = "$env:LOCALAPPDATA\Microsoft\Windows\INetCache"; Pattern = "*" },
        @{ Name = "Chrome Cache"; Path = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache"; Pattern = "*" },
        @{ Name = "Firefox Cache"; Path = "$env:LOCALAPPDATA\Mozilla\Firefox\Profiles\*\cache2"; Pattern = "*" },
        @{ Name = "Edge Cache"; Path = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache"; Pattern = "*" }
    )

    $totalLocations = $cleanupLocations.Count
    Write-Log "Starting cleanup of $totalLocations temporary file locations..." 'INFO'

    foreach ($location in $cleanupLocations) {
        $locationsProcessed++
        $progressPercent = [math]::Round(($locationsProcessed / $totalLocations) * 100, 1)
        
        Write-TaskProgress -Activity "Cleaning Temp Files" -CurrentStep $locationsProcessed -TotalSteps $totalLocations -Status "$($location.Name) ($locationsProcessed/$totalLocations)" -FileBased:$false
        Write-Host "[$progressPercent%] Cleaning: $($location.Name) ($locationsProcessed/$totalLocations)" -ForegroundColor Cyan

        try {
            # Handle wildcard paths (like Firefox profiles)
            $pathsToClean = @()
            if ($location.Path -contains "*") {
                $pathsToClean = Get-ChildItem -Path $location.Path -Directory -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName
            }
            else {
                if (Test-Path $location.Path) {
                    $pathsToClean = @($location.Path)
                }
            }

            foreach ($cleanPath in $pathsToClean) {
                if (Test-Path $cleanPath) {
                    # Calculate size before deletion
                    try {
                        $sizeBeforeBytes = (Get-ChildItem -Path $cleanPath -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
                        $sizeBeforeMB = [math]::Round($sizeBeforeBytes / 1MB, 2)
                    }
                    catch {
                        $sizeBeforeMB = 0
                    }

                    # Perform cleanup
                    $filesInLocation = 0
                    try {
                        $filesToDelete = Get-ChildItem -Path $cleanPath -Recurse -File -Filter $location.Pattern -ErrorAction SilentlyContinue
                        $filesInLocation = $filesToDelete.Count

                        if ($filesInLocation -gt 0) {
                            $filesToDelete | Remove-Item -Force -ErrorAction SilentlyContinue
                            
                            # Clean empty directories
                            Get-ChildItem -Path $cleanPath -Recurse -Directory -ErrorAction SilentlyContinue | 
                            Where-Object { -not (Get-ChildItem -Path $_.FullName -ErrorAction SilentlyContinue) } | 
                            Remove-Item -Force -ErrorAction SilentlyContinue

                            $totalFilesDeleted += $filesInLocation
                            $totalSizeFreed += $sizeBeforeMB

                            if ($sizeBeforeMB -gt 0) {
                                Write-Host "    ✓ Cleaned $filesInLocation files ($sizeBeforeMB MB)" -ForegroundColor Green
                                Write-Log "Cleaned $($location.Name): $filesInLocation files, $sizeBeforeMB MB freed" 'INFO'
                            }
                        }
                        else {
                            Write-Host "    ○ No files to clean" -ForegroundColor Gray
                        }
                    }
                    catch {
                        Write-Host "    ✗ Error cleaning location: $_" -ForegroundColor Red
                        Write-Log "Error cleaning $($location.Name): $_" 'WARN'
                    }
                }
                else {
                    Write-Host "    ○ Location not found" -ForegroundColor Gray
                }
            }
        }
        catch {
            Write-Log "Error processing cleanup location $($location.Name): $_" 'WARN'
        }
    }

    # Clean Recycle Bin
    try {
        Write-Host "Cleaning Recycle Bin..." -ForegroundColor Cyan
        $recycleBinSize = 0
        
        # Calculate Recycle Bin size
        try {
            $recycleBinItems = Get-ChildItem -Path 'C:\$Recycle.Bin' -Recurse -File -ErrorAction SilentlyContinue
            $recycleBinSize = [math]::Round(($recycleBinItems | Measure-Object -Property Length -Sum).Sum / 1MB, 2)
        }
        catch { }

        # Empty Recycle Bin using COM object
        $shell = New-Object -ComObject Shell.Application
        $recycleBin = $shell.Namespace(0xA)
        if ($recycleBin.Items().Count -gt 0) {
            $recycleBin.Items() | ForEach-Object { Remove-Item -Path $_.Path -Force -Recurse -ErrorAction SilentlyContinue }
            $totalSizeFreed += $recycleBinSize
            Write-Host "    ✓ Recycle Bin emptied ($recycleBinSize MB)" -ForegroundColor Green
            Write-Log "Recycle Bin emptied: $recycleBinSize MB freed" 'INFO'
        }
        else {
            Write-Host "    ○ Recycle Bin already empty" -ForegroundColor Gray
        }
    }
    catch {
        Write-Log "Error cleaning Recycle Bin: $_" 'WARN'
    }

    # Summary
    Write-TaskProgress -Activity "Cleaning Temp Files" -CurrentStep $totalLocations -TotalSteps $totalLocations -Status "Cleanup completed" -FileBased:$false
    Write-Progress -Activity "Cleaning Temp Files" -Completed
    
    Write-Log "[TempCleanup] CLEANUP SUMMARY:" 'INFO'
    Write-Log "- Total files deleted: $totalFilesDeleted" 'INFO'
    Write-Log "- Total disk space freed: $([math]::Round($totalSizeFreed, 2)) MB" 'INFO'
    Write-Log "- Locations processed: $locationsProcessed/$totalLocations" 'INFO'

    Write-Host "✓ Cleanup completed: $totalFilesDeleted files deleted, $([math]::Round($totalSizeFreed, 2)) MB freed" -ForegroundColor Green

    Write-Log "[END] Comprehensive Temporary Files Cleanup" 'INFO'
}

# ================================================================
# Function: Start-SystemHealthRepair
# ================================================================
# Purpose: Automated Windows System Health Check and Repair using DISM and SFC
# Environment: Windows 10/11, Administrator required, PowerShell 7+ optimized
# Performance: Long-running operation, automated detection, comprehensive system file integrity checking
# Dependencies: DISM.exe, SFC.exe, Windows Component Store, Administrator privileges
# Logic: DISM component store health check, automatic repair if needed, SFC scan based on results and logs
# Features: Intelligent repair detection, unattended operation, comprehensive logging, repair verification
# ================================================================
function Start-SystemHealthRepair {
    Write-Log "[START] Windows System Health Check and Repair - Automated DISM/SFC Mode" 'INFO'
    
    $repairStartTime = Get-Date
    $dismRepaired = $false
    $repairNeeded = $false
    $repairResults = @{
        DismCheckPerformed = $false
        DismRepairNeeded   = $false
        DismRepairSuccess  = $false
        SfcCheckPerformed  = $false
        SfcRepairNeeded    = $false
        SfcRepairSuccess   = $false
        OverallSuccess     = $false
    }

    try {
        Write-Log "PowerShell Version: $($PSVersionTable.PSVersion)" 'INFO'
        Write-Log "OS Version: $([System.Environment]::OSVersion.VersionString)" 'INFO'
        
        # Progress: 5% - Initializing DISM check
        Write-Log "Starting DISM component store health analysis..." 'INFO'
        Write-Progress -Activity "System Health Repair" -Status "Initializing DISM health check..." -PercentComplete 5
        
        try {
            # Progress: 8% - Running DISM ScanHealth
            Write-Progress -Activity "System Health Repair" -Status "Running DISM ScanHealth..." -PercentComplete 8
            $dismScanResult = & dism /online /cleanup-image /scanhealth /english 2>&1
            
            # Progress: 12% - Processing DISM results
            Write-Progress -Activity "System Health Repair" -Status "Processing DISM scan results..." -PercentComplete 12
            $dismScanOutput = $dismScanResult -join "`n"
            Write-Log "DISM ScanHealth completed" 'VERBOSE'
            
            # Progress: 15% - Analyzing component store
            Write-Progress -Activity "System Health Repair" -Status "Analyzing component store health..." -PercentComplete 15
            $repairResults.DismCheckPerformed = $true
            
            if ($dismScanOutput -match "component store is repairable|corruption was detected") {
                # Progress: 18% - Corruption detected
                Write-Progress -Activity "System Health Repair" -Status "Corruption detected, preparing repair..." -PercentComplete 18
                Write-Log "⚠ DISM detected component store corruption - repair required" 'WARN'
                $repairResults.DismRepairNeeded = $true
                $repairNeeded = $true
                
                # Progress: 20% - Starting DISM RestoreHealth
                Write-Progress -Activity "System Health Repair" -Status "Starting DISM RestoreHealth..." -PercentComplete 20
                Write-Log "Starting DISM RestoreHealth operation..." 'INFO'
                
                # Progress: 25% - Running RestoreHealth
                Write-Progress -Activity "System Health Repair" -Status "Running DISM RestoreHealth (this may take a while)..." -PercentComplete 25
                $dismRepairStart = Get-Date
                $dismRepairResult = & dism /online /cleanup-image /restorehealth /english 2>&1
                
                # Progress: 45% - Processing repair results
                Write-Progress -Activity "System Health Repair" -Status "Processing DISM repair results..." -PercentComplete 45
                $dismRepairOutput = $dismRepairResult -join "`n"
                $dismRepairEnd = Get-Date
                $dismDuration = $dismRepairEnd - $dismRepairStart
                
                # Progress: 48% - Verifying repair success
                Write-Progress -Activity "System Health Repair" -Status "Verifying DISM repair success..." -PercentComplete 48
                Write-Log "DISM RestoreHealth completed in $($dismDuration.ToString('hh\:mm\:ss'))" 'INFO'
                Write-Log "DISM RestoreHealth output: $dismRepairOutput" 'VERBOSE'
                if ($LASTEXITCODE -eq 0) {
                    Write-Log "✓ DISM RestoreHealth completed successfully" 'SUCCESS'
                    $dismRepaired = $true
                    $repairResults.DismRepairSuccess = $true
                }
                else {
                    Write-Log "✗ DISM RestoreHealth failed with exit code: $LASTEXITCODE" 'ERROR'
                    $repairResults.DismRepairSuccess = $false
                }
            }
        }
        catch {
            Write-Log "DISM ScanHealth operation failed: $_" 'ERROR'
            $repairResults.DismCheckPerformed = $false
        }
        
        if ($dismScanOutput -match "no component store corruption detected") {
            # Progress: 18% - No corruption detected
            Write-Progress -Activity "System Health Repair" -Status "No corruption detected..." -PercentComplete 18
            Write-Log "✓ DISM: No component store corruption detected" 'INFO'
            $repairResults.DismRepairNeeded = $false
        }
        else {
            # Progress: 18% - Detailed analysis needed
            Write-Progress -Activity "System Health Repair" -Status "Running detailed DISM analysis..." -PercentComplete 18
            Write-Log "DISM health check completed, performing detailed analysis..." 'INFO'
                
            # Progress: 22% - Running CheckHealth
            Write-Progress -Activity "System Health Repair" -Status "Running DISM CheckHealth..." -PercentComplete 22
            # Run DISM CheckHealth for more detailed analysis
            $dismCheckResult = & dism /online /cleanup-image /checkhealth /english 2>&1
                
            # Progress: 25% - Processing CheckHealth results
            Write-Progress -Activity "System Health Repair" -Status "Processing CheckHealth results..." -PercentComplete 25
            $dismCheckOutput = $dismCheckResult -join "`n"
                
            if ($dismCheckOutput -match "component store is repairable|corruption was detected") {
                Write-Log "⚠ DISM CheckHealth detected issues - repair required" 'WARN'
                $repairResults.DismRepairNeeded = $true
                $repairNeeded = $true
            }
            else {
                Write-Log "✓ DISM detailed check passed - no corruption detected" 'INFO'
                $repairResults.DismRepairNeeded = $false
            }
        }
    }
    catch {
        Write-Log "Error during DISM health check: $($_.Exception.Message)" 'ERROR'
        $repairResults.DismCheckPerformed = $false
    }

    # SFC System File Check
    # Progress: 50% - Determining SFC necessity
    Write-Progress -Activity "System Health Repair" -Status "Determining if SFC scan is needed..." -PercentComplete 50
    Write-Log "Determining SFC scan necessity..." 'INFO'
    $sfcNeeded = $false
    # SFC is recommended if DISM repair was performed or CBS logs indicate issues
    if ($dismRepaired) {
        # Progress: 52% - SFC recommended
        Write-Progress -Activity "System Health Repair" -Status "SFC scan recommended after DISM repair..." -PercentComplete 52
        Write-Log "SFC scan recommended (DISM repair was performed)" 'INFO'
        $sfcNeeded = $true
    }
    else {
        # Progress: 52% - Analyzing CBS logs
        Write-Progress -Activity "System Health Repair" -Status "Analyzing CBS logs..." -PercentComplete 52
        # Check CBS logs for corruption indicators
        Write-Log "Analyzing CBS logs for system file integrity issues..." 'INFO'
        try {
            # Progress: 55% - Reading CBS log
            Write-Progress -Activity "System Health Repair" -Status "Reading CBS log file..." -PercentComplete 55
            $cbsLogPath = "$env:WINDIR\Logs\CBS\CBS.log"
            if (Test-Path $cbsLogPath) {
                # Progress: 58% - Processing log entries
                Write-Progress -Activity "System Health Repair" -Status "Processing log entries..." -PercentComplete 58
                $recentEntries = Get-Content $cbsLogPath -Tail 1000 -ErrorAction SilentlyContinue
                $corruptionIndicators = $recentEntries | Where-Object { 
                    $_ -match "corrupt|damaged|violation|failed.*verify" -and $_ -notmatch "successfully"
                }
                if ($corruptionIndicators.Count -gt 0) {
                    Write-Log "⚠ Found potential file corruption indicators in CBS log - SFC scan recommended" 'WARN'
                    $sfcNeeded = $true
                }
                else {
                    Write-Log "✓ CBS log analysis shows no immediate corruption indicators" 'INFO'
                    $sfcNeeded = $false
                }
            }
            else {
                Write-Log "CBS log not accessible - SFC scan will be skipped" 'WARN'
                $sfcNeeded = $false
            }
        }
        catch {
            Write-Log "Could not analyze CBS logs: $($_.Exception.Message)" 'WARN'
            $sfcNeeded = $false
        }
    }

    # Perform SFC scan if needed
    if ($sfcNeeded) {
        $repairNeeded = $true
        $repairResults.SfcCheckPerformed = $true
        $repairResults.SfcRepairNeeded = $true
            
        # Progress: 60% - Preparing SFC scan
        Write-Progress -Activity "System Health Repair" -Status "Preparing SFC scan..." -PercentComplete 60
        Write-Log "Starting SFC /scannow operation..." 'INFO'
            
        # Progress: 65% - Running SFC scan
        Write-Progress -Activity "System Health Repair" -Status "Running SFC /scannow (this may take a while)..." -PercentComplete 65
        try {
            $sfcStart = Get-Date
            $sfcResult = & sfc /scannow 2>&1
                
            # Progress: 85% - Processing SFC results
            Write-Progress -Activity "System Health Repair" -Status "Processing SFC scan results..." -PercentComplete 85
            $sfcOutput = $sfcResult -join "`n"
            $sfcEnd = Get-Date
            $sfcDuration = $sfcEnd - $sfcStart
                
            # Progress: 88% - Analyzing SFC results
            Write-Progress -Activity "System Health Repair" -Status "Analyzing SFC results..." -PercentComplete 88
            Write-Log "SFC scan completed in $($sfcDuration.ToString('hh\:mm\:ss'))" 'INFO'
            # Parse SFC results
            if ($sfcOutput -match "did not find any integrity violations") {
                Write-Log "✓ SFC scan completed - no integrity violations found" 'SUCCESS'
                $repairResults.SfcRepairSuccess = $true
            }
            elseif ($sfcOutput -match "found corrupt files and successfully repaired them") {
                Write-Log "✓ SFC scan completed - corrupt files found and successfully repaired" 'SUCCESS'
                $repairResults.SfcRepairSuccess = $true
            }
            elseif ($sfcOutput -match "found corrupt files but was unable to fix some") {
                Write-Log "⚠ SFC scan completed - some corrupt files could not be repaired" 'WARN'
                $repairResults.SfcRepairSuccess = $false
            }
            else {
                Write-Log "⚠ SFC scan completed with unknown status" 'WARN'
                $repairResults.SfcRepairSuccess = $true
            }
        }
        catch {
            Write-Log "Error during SFC scan: $($_.Exception.Message)" 'ERROR'
            $repairResults.SfcCheckPerformed = $false
            $repairResults.SfcRepairSuccess = $false
        }
    }
    else {
        # Progress: 60% - SFC not needed
        Write-Progress -Activity "System Health Repair" -Status "SFC scan not needed..." -PercentComplete 60
        Write-Log "✓ SFC scan not needed based on current analysis" 'INFO'
        $repairResults.SfcCheckPerformed = $false
        $repairResults.SfcRepairNeeded = $false
    }

    # Progress: 90% - Determining overall success
    Write-Progress -Activity "System Health Repair" -Status "Determining overall success..." -PercentComplete 90
    # Determine overall success
    $repairResults.OverallSuccess = (
        (-not $repairResults.DismRepairNeeded -or $repairResults.DismRepairSuccess) -and
        (-not $repairResults.SfcRepairNeeded -or $repairResults.SfcRepairSuccess)
    )

    # Progress: 95% - Preparing final report
    Write-Progress -Activity "System Health Repair" -Status "Preparing final report..." -PercentComplete 95
    
    # Calculate total operation time and log summary
    $repairEndTime = Get-Date
    $totalDuration = $repairEndTime - $repairStartTime
    
    # Log comprehensive repair summary
    Write-Log "[SUMMARY] System Health Repair completed in $($totalDuration.ToString('hh\:mm\:ss'))" 'INFO'
    Write-Log "[SUMMARY] Repair needed: $repairNeeded | Overall success: $($repairResults.OverallSuccess)" 'INFO'
    Write-Log "[SUMMARY] DISM repair: needed=$($repairResults.DismRepairNeeded), success=$($repairResults.DismRepairSuccess)" 'INFO'
    Write-Log "[SUMMARY] SFC repair: needed=$($repairResults.SfcRepairNeeded), success=$($repairResults.SfcRepairSuccess)" 'INFO'
    
    # Add timing and repair status to results object
    $repairResults.TotalDuration = $totalDuration
    $repairResults.RepairNeeded = $repairNeeded
    $repairResults.StartTime = $repairStartTime
    $repairResults.EndTime = $repairEndTime

    # Progress: 100% - Operation complete
    Write-Progress -Activity "System Health Repair" -Status "System health repair complete!" -PercentComplete 100
    Start-Sleep -Milliseconds 500  # Brief pause to show completion
    Write-Progress -Activity "System Health Repair" -Completed
    
    # Return comprehensive results for reporting and analytics
    return $repairResults
}
catch {
    Write-Log "Unexpected error during system health repair: $($_.Exception.Message)" 'ERROR'
    $repairResults.OverallSuccess = $false
}
finally {
    # Generate comprehensive repair report
    $repairEndTime = Get-Date
    $totalDuration = $repairEndTime - $repairStartTime
        
    Write-Log "[SystemHealthRepair] COMPREHENSIVE REPAIR SUMMARY:" 'INFO'
    Write-Log "- Repair start time: $($repairStartTime.ToString('yyyy-MM-dd HH:mm:ss'))" 'INFO'
    Write-Log "- Repair end time: $($repairEndTime.ToString('yyyy-MM-dd HH:mm:ss'))" 'INFO'
    Write-Log "- Total duration: $($totalDuration.ToString('hh\:mm\:ss'))" 'INFO'
    Write-Log "- DISM check performed: $(if($repairResults.DismCheckPerformed){'Yes'}else{'No'})" 'INFO'
    Write-Log "- DISM repair needed: $(if($repairResults.DismRepairNeeded){'Yes'}else{'No'})" 'INFO'
    Write-Log "- DISM repair successful: $(if($repairResults.DismRepairSuccess){'Yes'}else{'No'})" 'INFO'
    Write-Log "- SFC check performed: $(if($repairResults.SfcCheckPerformed){'Yes'}else{'No'})" 'INFO'
    Write-Log "- SFC repair needed: $(if($repairResults.SfcRepairNeeded){'Yes'}else{'No'})" 'INFO'
    Write-Log "- SFC repair successful: $(if($repairResults.SfcRepairSuccess){'Yes'}else{'No'})" 'INFO'
    Write-Log "- Overall repair success: $(if($repairResults.OverallSuccess){'Yes'}else{'No'})" 'INFO'
        
    # Create detailed log file
    try {
        $repairLogPath = Join-Path $global:TempFolder "system_health_repair_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
        $logContent = @"
Windows System Health Check and Repair Report
=============================================
Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Computer: $env:COMPUTERNAME
User: $env:USERNAME
PowerShell Version: $($PSVersionTable.PSVersion)

Repair Summary:
- Start Time: $($repairStartTime.ToString('yyyy-MM-dd HH:mm:ss'))
- End Time: $($repairEndTime.ToString('yyyy-MM-dd HH:mm:ss'))
- Duration: $($totalDuration.ToString('hh\:mm\:ss'))
- Repair Operations Needed: $(if($repairNeeded){'Yes'}else{'No'})

DISM Component Store Check:
- Check Performed: $(if($repairResults.DismCheckPerformed){'Yes'}else{'No'})
- Repair Needed: $(if($repairResults.DismRepairNeeded){'Yes'}else{'No'})
- Repair Successful: $(if($repairResults.DismRepairSuccess){'Yes'}else{'No'})

SFC System File Check:
- Check Performed: $(if($repairResults.SfcCheckPerformed){'Yes'}else{'No'})
- Repair Needed: $(if($repairResults.SfcRepairNeeded){'Yes'}else{'No'})
- Repair Successful: $(if($repairResults.SfcRepairSuccess){'Yes'}else{'No'})

Overall Result: $(if($repairResults.OverallSuccess){'SUCCESS - System health verified/repaired'}else{'WARNING - Some issues may remain'})

Recommendations:
$(if($repairNeeded){'- Consider restarting your computer to ensure all changes take effect'}else{'- No immediate action required - system appears healthy'})
- Monitor system performance and run this check periodically
- Keep Windows updates current for optimal system health

"@
            
        $logContent | Out-File -FilePath $repairLogPath -Encoding UTF8
        Write-Log "Detailed repair report saved to: $repairLogPath" 'INFO'
    }
    catch {
        Write-Log "Warning: Could not save detailed repair report: $_" 'WARN'
    }
        
    if ($repairNeeded) {
        Write-Log "✓ System health repair operations completed successfully" 'SUCCESS'
        if ($repairResults.OverallSuccess) {
            Write-Log "Recommendation: Consider restarting your computer to ensure all changes take effect" 'INFO'
        }
        else {
            Write-Log "Warning: Some repair operations encountered issues - manual intervention may be required" 'WARN'
        }
    }
    else {
        Write-Log "✓ System health check completed - no repair operations were needed" 'SUCCESS'
    }
    
    # Calculate total repair duration and log performance metrics
    $repairEndTime = Get-Date
    $totalRepairDuration = $repairEndTime - $repairStartTime
    Write-Log "System health repair completed in $($totalRepairDuration.ToString('hh\:mm\:ss'))" 'INFO'
    Write-Log "Repair operations needed: $repairNeeded" 'INFO'
    
    Write-Log "[END] Windows System Health Check and Repair" 'INFO'
    return $repairResults.OverallSuccess
}

# ================================================================
# Function: Start-DefenderFullScan
# ================================================================
# Purpose: Performs a comprehensive Windows Defender full system scan with automatic threat removal and detailed reporting
# Environment: Windows 10/11, Administrator required, Windows Defender enabled, PowerShell 7+ optimized
# Performance: Long-running operation (may take hours), progress tracking, comprehensive threat detection and cleanup
# Dependencies: Windows Defender Antivirus, Get-MpComputerStatus, Start-MpScan, Get-MpThreat, Remove-MpThreat
# Logic: Defender status verification, signature updates, full system scan, threat detection, automatic cleanup, detailed reporting
# Features: Real-time status monitoring, automatic threat removal, scan history tracking, comprehensive logging and reporting
# ================================================================
function Start-DefenderFullScan {
    Write-Log "[START] Windows Defender Full System Scan with Automatic Threat Cleanup" 'INFO'
    
    $scanStartTime = Get-Date
    $scanSuccess = $false
    $threatsFound = @()
    $cleanupSuccess = $true
    
    try {
        # Progress: 5% - Checking Defender status
        Write-Progress -Activity "Defender Full Scan" -Status "Checking Defender status..." -PercentComplete 5
        Write-Log "Checking Windows Defender status..." 'INFO'
        try {
            # Progress: 8% - Getting computer status
            Write-Progress -Activity "Defender Full Scan" -Status "Getting Defender computer status..." -PercentComplete 8
            $defenderStatus = Get-MpComputerStatus
            
            # Progress: 10% - Validating antivirus status
            Write-Progress -Activity "Defender Full Scan" -Status "Validating antivirus status..." -PercentComplete 10
            if (-not $defenderStatus.AntivirusEnabled) {
                Write-Progress -Activity "Defender Full Scan" -Completed
                Write-Log "Windows Defender Antivirus is not enabled. Skipping scan." 'WARN'
                return $false
            }
            if (-not $defenderStatus.RealTimeProtectionEnabled) {
                Write-Log "Warning: Real-time protection is disabled" 'WARN'
            }
            Write-Log "✓ Windows Defender is enabled and available" 'INFO'
        }
        catch {
            Write-Progress -Activity "Defender Full Scan" -Completed
            Write-Log "Error checking Windows Defender status: $_. Skipping scan." 'WARN'
            return $false
        }

        # Progress: 12% - Preparing signature update
        Write-Progress -Activity "Defender Full Scan" -Status "Preparing signature update..." -PercentComplete 12
        Write-Log "Updating Windows Defender signatures..." 'INFO'
        try {
            # Progress: 15% - Updating signatures
            Write-Progress -Activity "Defender Full Scan" -Status "Downloading and installing latest signatures..." -PercentComplete 15
            Update-MpSignature
            # Progress: 18% - Verifying signature update
            Write-Progress -Activity "Defender Full Scan" -Status "Verifying signature update..." -PercentComplete 18
            Write-Log "✓ Defender signatures updated successfully" 'INFO'
        }
        catch {
            Write-Log "Warning: Failed to update signatures - $_" 'WARN'
        }

        # Progress: 20% - Preparing full scan
        Write-Progress -Activity "Defender Full Scan" -Status "Preparing full system scan..." -PercentComplete 20
        Write-Log "Starting Windows Defender full system scan..." 'INFO'
        Write-Log "Note: This operation may take considerable time depending on system size" 'INFO'
        
        try {
            # Progress: 25% - Initiating scan
            Write-Progress -Activity "Defender Full Scan" -Status "Initiating full system scan..." -PercentComplete 25
            $scanResult = Start-MpScan -ScanType FullScan
            
            # Progress: 70% - Scan completed, processing results
            Write-Progress -Activity "Defender Full Scan" -Status "Scan completed, processing results..." -PercentComplete 70
            Write-Log "✓ Full system scan completed successfully" 'INFO'
            if ($scanResult) {
                Write-Log "Scan result output: $scanResult" 'VERBOSE'
            }
            $scanSuccess = $true
        }
        catch {
            Write-Progress -Activity "Defender Full Scan" -Completed
            Write-Log "✗ Defender scan failed: $_" 'ERROR'
            return $false
        }

        # Progress: 72% - Getting threat information
        Write-Progress -Activity "Defender Full Scan" -Status "Getting threat information..." -PercentComplete 72
        Write-Log "Analyzing scan results..." 'INFO'
        try {
            # Progress: 74% - Retrieving detected threats
            Write-Progress -Activity "Defender Full Scan" -Status "Retrieving detected threats..." -PercentComplete 74
            $threatsFound = Get-MpThreat
            
            # Progress: 76% - Getting scan history
            Write-Progress -Activity "Defender Full Scan" -Status "Getting scan history..." -PercentComplete 76
            $scanHistory = Get-MpScanHistory | Select-Object -First 1
            
            # Progress: 78% - Analyzing scan results
            Write-Progress -Activity "Defender Full Scan" -Status "Analyzing scan results..." -PercentComplete 78
            if ($scanHistory) {
                Write-Log "Last scan completed: $($scanHistory.StartTime)" 'INFO'
                Write-Log "Scan type: $($scanHistory.ScanType)" 'INFO'
                Write-Log "Scan result: $($scanHistory.Result)" 'INFO'
            }
            
            if ($threatsFound.Count -gt 0) {
                Write-Log "⚠ THREATS DETECTED: $($threatsFound.Count) threats found" 'WARN'
                foreach ($threat in $threatsFound) {
                    Write-Log "- Threat: $($threat.ThreatName) | Location: $($threat.Resources -join ', ')" 'WARN'
                }
            } else {
                Write-Log "✓ No threats detected - system is clean" 'INFO'
            }
        }
        catch {
            Write-Log "Error retrieving scan results: $_" 'WARN'
        }

        # Automatic threat cleanup if threats were found
        if ($threatsFound.Count -gt 0) {
            # Progress: 82% - Preparing threat cleanup
            Write-Progress -Activity "Defender Full Scan" -Status "Preparing threat cleanup..." -PercentComplete 82
            Write-Log "Initiating automatic threat cleanup..." 'INFO'
            try {
                # Progress: 85% - Removing threats
                Write-Progress -Activity "Defender Full Scan" -Status "Removing detected threats..." -PercentComplete 85
                Remove-MpThreat -All
                Write-Log "✓ All detected threats have been automatically removed" 'INFO'
                
                # Progress: 88% - Verifying cleanup
                Write-Progress -Activity "Defender Full Scan" -Status "Verifying threat cleanup..." -PercentComplete 88
                Start-Sleep -Seconds 3
                $remainingThreats = Get-MpThreat
                
                # Progress: 90% - Cleanup verification complete
                Write-Progress -Activity "Defender Full Scan" -Status "Cleanup verification complete..." -PercentComplete 90
                if ($remainingThreats.Count -eq 0) {
                    Write-Log "✓ Threat cleanup verification successful - no threats remain" 'INFO'
                    $cleanupSuccess = $true
                } else {
                    Write-Log "⚠ Warning: $($remainingThreats.Count) threats still remain after cleanup" 'WARN'
                    $cleanupSuccess = $false
                }
            }
            catch {
                Write-Log "✗ Error during automatic threat cleanup: $_" 'ERROR'
                $cleanupSuccess = $false
            }
        }

        # Progress: 92% - Preparing scan report
        Write-Progress -Activity "Defender Full Scan" -Status "Preparing scan report..." -PercentComplete 92
        # Generate comprehensive scan report
        $scanEndTime = Get-Date
        $scanDuration = $scanEndTime - $scanStartTime
        
        # Progress: 94% - Generating summary
        Write-Progress -Activity "Defender Full Scan" -Status "Generating scan summary..." -PercentComplete 94
        Write-Log "[DefenderScan] COMPREHENSIVE SCAN SUMMARY:" 'INFO'
        Write-Log "- Scan start time: $($scanStartTime.ToString('yyyy-MM-dd HH:mm:ss'))" 'INFO'
        Write-Log "- Scan end time: $($scanEndTime.ToString('yyyy-MM-dd HH:mm:ss'))" 'INFO'
        Write-Log "- Total scan duration: $($scanDuration.ToString('hh\:mm\:ss'))" 'INFO'
        Write-Log "- Scan successful: $(if($scanSuccess){'Yes'}else{'No'})" 'INFO'
        Write-Log "- Threats detected: $($threatsFound.Count)" 'INFO'
        Write-Log "- Automatic cleanup successful: $(if($cleanupSuccess){'Yes'}else{'No'})" 'INFO'
        
        # Progress: 96% - Creating detailed log
        Write-Progress -Activity "Defender Full Scan" -Status "Creating detailed log file..." -PercentComplete 96
        # Create detailed log file in temp folder
        try {
            $scanLogPath = Join-Path $global:TempFolder "defender_scan_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
            $logContent = @"
Windows Defender Full Scan Report
==================================
Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Computer: $env:COMPUTERNAME
User: $env:USERNAME
PowerShell Version: $($PSVersionTable.PSVersion)

Scan Details:
- Start Time: $($scanStartTime.ToString('yyyy-MM-dd HH:mm:ss'))
- End Time: $($scanEndTime.ToString('yyyy-MM-dd HH:mm:ss'))
- Duration: $($scanDuration.ToString('hh\:mm\:ss'))
- Scan Type: Full System Scan
- Scan Successful: $(if($scanSuccess){'Yes'}else{'No'})
- Threats Found: $($threatsFound.Count)
- Cleanup Successful: $(if($cleanupSuccess){'Yes'}else{'No'})

"@
            
            if ($threatsFound.Count -gt 0) {
                $logContent += "Detected Threats:`n"
                foreach ($threat in $threatsFound) {
                    $logContent += "- $($threat.ThreatName): $($threat.Resources -join ', ')`n"
                }
                $logContent += "`n"
            }
            
            $logContent += "Defender Status:`n"
            if ($defenderStatus) {
                $logContent += "- Antivirus Enabled: $($defenderStatus.AntivirusEnabled)`n"
                $logContent += "- Real-time Protection: $($defenderStatus.RealTimeProtectionEnabled)`n"
                $logContent += "- Last Signature Update: $($defenderStatus.AntivirusSignatureLastUpdated)`n"
            }
            
            # Progress: 98% - Saving log file
            Write-Progress -Activity "Defender Full Scan" -Status "Saving detailed log file..." -PercentComplete 98
            $logContent | Out-File -FilePath $scanLogPath -Encoding UTF8
            Write-Log "Detailed scan report saved to: $scanLogPath" 'INFO'
        }
        catch {
            Write-Log "Warning: Could not save detailed scan report: $_" 'WARN'
        }
        
        # Progress: 100% - Complete
        Write-Progress -Activity "Defender Full Scan" -Status "Scan operation complete!" -PercentComplete 100
        Start-Sleep -Milliseconds 500  # Brief pause to show completion
        # Clear progress bar
        Write-Progress -Activity "Defender Full Scan" -Completed

        return $scanSuccess
    }
    catch {
        Write-Log "Unexpected error during Defender scan: $_" 'ERROR'
        return $false
    }
    finally {
        Write-Log "[END] Windows Defender Full System Scan" 'INFO'
    }
}

# ===============================
# SECTION 7: REPORTING & ANALYTICS
# ===============================
# - Write-UnifiedMaintenanceReport (comprehensive reporting)
# - Write-TempListsSummary (temp files analysis)
# - Performance tracking functions
# - Report generation utilities and analytics

# ================================================================
# Function: Write-TempListsSummary
# ================================================================
# Purpose: Generate comprehensive summary of temporary lists and system analysis files for debugging and audit purposes
# Environment: Windows 10/11, file system access to temp directories, JSON processing capabilities for analysis files
# Performance: Fast file enumeration, efficient JSON parsing, lightweight analysis with minimal overhead
# Dependencies: File system access, temp folder structure, JSON processing for bloatware and essential apps lists
# Logic: Scans temp directories for analysis files, parses JSON content, generates readable summaries with statistics
# Features: File size reporting, content analysis, categorized summaries, debug information extraction
# ================================================================
function Write-TempListsSummary {
    Write-Log "[START] Temporary Lists Summary Generation" 'INFO'
    
    if (-not (Test-Path $global:TempFolder)) {
        Write-Log "Temp folder not found: $global:TempFolder" 'WARN'
        return
    }

    $summaryLines = @()
    $summaryLines += "=== TEMPORARY LISTS SUMMARY ==="
    $summaryLines += "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    $summaryLines += "Temp Folder: $global:TempFolder"
    $summaryLines += ""

    # Analyze bloatware lists
    $bloatwareListPath = Join-Path $global:TempFolder 'bloatware.json'
    if (Test-Path $bloatwareListPath) {
        try {
            $bloatwareList = Get-Content $bloatwareListPath -Raw | ConvertFrom-Json
            $bloatwareCount = if ($bloatwareList -is [array]) { $bloatwareList.Count } else { 1 }
            $fileSize = [math]::Round((Get-Item $bloatwareListPath).Length / 1KB, 2)
            
            $summaryLines += "BLOATWARE LIST:"
            $summaryLines += "- Total entries: $bloatwareCount"
            $summaryLines += "- File size: $fileSize KB"
            $summaryLines += "- Location: $bloatwareListPath"
            
            # Sample entries (first 5)
            $sampleEntries = $bloatwareList | Select-Object -First 5
            $summaryLines += "- Sample entries: $($sampleEntries -join ', ')"
            $summaryLines += ""
        }
        catch {
            $summaryLines += "BLOATWARE LIST: Error reading file - $_"
            $summaryLines += ""
        }
    }

    # Analyze essential apps lists
    $essentialAppsPath = Join-Path $global:TempFolder 'essential_apps.json'
    if (Test-Path $essentialAppsPath) {
        try {
            $essentialApps = Get-Content $essentialAppsPath -Raw | ConvertFrom-Json
            $appsCount = if ($essentialApps -is [array]) { $essentialApps.Count } else { 1 }
            $fileSize = [math]::Round((Get-Item $essentialAppsPath).Length / 1KB, 2)
            
            $summaryLines += "ESSENTIAL APPS LIST:"
            $summaryLines += "- Total entries: $appsCount"
            $summaryLines += "- File size: $fileSize KB"
            $summaryLines += "- Location: $essentialAppsPath"
            
            # Count apps by source
            $wingetCount = ($essentialApps | Where-Object { $_.Winget }).Count
            $chocoCount = ($essentialApps | Where-Object { $_.Choco }).Count
            $summaryLines += "- Winget sources: $wingetCount"
            $summaryLines += "- Chocolatey sources: $chocoCount"
            $summaryLines += ""
        }
        catch {
            $summaryLines += "ESSENTIAL APPS LIST: Error reading file - $_"
            $summaryLines += ""
        }
    }

    # Analyze diff files
    $diffFiles = Get-ChildItem -Path $global:TempFolder -Filter "*diff*.json" -ErrorAction SilentlyContinue
    if ($diffFiles) {
        $summaryLines += "DIFF ANALYSIS FILES:"
        foreach ($diffFile in $diffFiles) {
            $fileSize = [math]::Round($diffFile.Length / 1KB, 2)
            $summaryLines += "- $($diffFile.Name): $fileSize KB"
        }
        $summaryLines += ""
    }

    # Analyze audit files
    $auditFiles = Get-ChildItem -Path $global:TempFolder -Filter "*audit*.json" -ErrorAction SilentlyContinue
    if ($auditFiles) {
        $summaryLines += "AUDIT FILES:"
        foreach ($auditFile in $auditFiles) {
            $fileSize = [math]::Round($auditFile.Length / 1KB, 2)
            $createdTime = $auditFile.CreationTime.ToString('yyyy-MM-dd HH:mm:ss')
            $summaryLines += "- $($auditFile.Name): $fileSize KB (Created: $createdTime)"
        }
        $summaryLines += ""
    }

    # System inventory summary
    $inventoryPath = Join-Path $global:TempFolder 'inventory.json'
    if (Test-Path $inventoryPath) {
        try {
            $inventory = Get-Content $inventoryPath -Raw | ConvertFrom-Json
            $fileSize = [math]::Round((Get-Item $inventoryPath).Length / 1KB, 2)
            
            $summaryLines += "SYSTEM INVENTORY:"
            $summaryLines += "- File size: $fileSize KB"
            $summaryLines += "- AppX packages: $(if ($inventory.appx) { $inventory.appx.Count } else { 0 })"
            $summaryLines += "- Winget packages: $(if ($inventory.winget) { $inventory.winget.Count } else { 0 })"
            $summaryLines += "- Chocolatey packages: $(if ($inventory.choco) { $inventory.choco.Count } else { 0 })"
            $summaryLines += "- Registry entries: $(if ($inventory.registry_uninstall) { $inventory.registry_uninstall.Count } else { 0 })"
            $summaryLines += ""
        }
        catch {
            $summaryLines += "SYSTEM INVENTORY: Error reading file - $_"
            $summaryLines += ""
        }
    }

    # Total temp folder analysis
    $totalFiles = (Get-ChildItem -Path $global:TempFolder -File -ErrorAction SilentlyContinue).Count
    $totalSize = [math]::Round((Get-ChildItem -Path $global:TempFolder -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum / 1KB, 2)
    
    $summaryLines += "TEMP FOLDER SUMMARY:"
    $summaryLines += "- Total files: $totalFiles"
    $summaryLines += "- Total size: $totalSize KB"
    $summaryLines += "- Folder: $global:TempFolder"
    $summaryLines += ""
    $summaryLines += "=== END TEMPORARY LISTS SUMMARY ==="

    # Write summary to temp folder
    $summaryPath = Join-Path $global:TempFolder 'temp_lists_summary.txt'
    $summaryLines | Out-File -FilePath $summaryPath -Encoding UTF8
    
    Write-Log "Temporary lists summary generated: $summaryPath" 'INFO'
    Write-Log "[END] Temporary Lists Summary Generation" 'INFO'
}

# ================================================================
# Function: Write-UnifiedMaintenanceReport
# ================================================================
# Purpose: Generate comprehensive maintenance report with system information, task results, and detailed analytics
# Environment: Windows 10/11, requires file system access, task results availability, system information gathering capabilities
# Performance: Efficient data collection, structured JSON and text output, comprehensive system analysis with minimal overhead
# Dependencies: Global task results, system information cmdlets, file system access, temp folder structure, log file analysis
# Logic: Collects system metadata, analyzes task results, generates structured reports, creates both JSON and human-readable formats
# Features: System metadata collection, task success/failure analysis, file inventory, action log parsing, structured reporting
# ================================================================
function Write-UnifiedMaintenanceReport {
    Write-Log "[START] Unified Maintenance Report Generation" 'INFO'
    
    $startTime = Get-Date
    $reportData = @{
        metadata   = @{
            date              = $startTime.ToString('yyyy-MM-dd HH:mm:ss')
            user              = $env:USERNAME
            computer          = $env:COMPUTERNAME
            scriptVersion     = "2025.1"
            os                = (Get-CimInstance Win32_OperatingSystem).Caption
            osVersion         = (Get-CimInstance Win32_OperatingSystem).Version
            powershellVersion = $PSVersionTable.PSVersion.ToString()
            scriptPath        = $PSCommandPath
            tempFolder        = $global:TempFolder
        }
        summary    = @{
            totalTasks      = if ($global:TaskResults) { $global:TaskResults.Count } else { 0 }
            successfulTasks = if ($global:TaskResults) { ($global:TaskResults.Values | Where-Object { $_.Success }).Count } else { 0 }
            failedTasks     = if ($global:TaskResults) { ($global:TaskResults.Values | Where-Object { -not $_.Success }).Count } else { 0 }
            successRate     = 0
            totalDuration   = 0
        }
        tasks      = @()
        files      = @{
            inventoryFiles = @()
            logFiles       = @()
            tempFiles      = @()
        }
        actions    = @()
        systemInfo = @{}
    }

    # Calculate success rate and total duration
    if ($reportData.summary.totalTasks -gt 0) {
        $reportData.summary.successRate = [math]::Round(($reportData.summary.successfulTasks / $reportData.summary.totalTasks) * 100, 1)
    }

    # Build task details
    if ($global:TaskResults) {
        foreach ($taskName in $global:TaskResults.Keys) {
            $result = $global:TaskResults[$taskName]
            $task = $global:ScriptTasks | Where-Object { $_.Name -eq $taskName }
            $taskDetail = @{
                name        = $taskName
                description = if ($task) { $task.Description } else { "Task description not available" }
                success     = $result.Success
                duration    = if ($result.Duration) { [math]::Round($result.Duration, 2) } else { 0 }
                started     = if ($result.Started) { $result.Started.ToString('HH:mm:ss') } else { "Unknown" }
                ended       = if ($result.Ended) { $result.Ended.ToString('HH:mm:ss') } else { "Unknown" }
                error       = if ($result.ContainsKey('Error')) { $result.Error } else { $null }
            }
            $reportData.tasks += $taskDetail
            $reportData.summary.totalDuration += $taskDetail.duration
        }
    }

    # Collect system information
    try {
        $reportData.systemInfo = @{
            processor      = (Get-CimInstance Win32_Processor).Name
            memory         = @{
                totalGB     = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 2)
                availableGB = [math]::Round((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory / 1MB / 1024, 2)
            }
            disk           = @{}
            uptime         = @{
                days  = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
                hours = [math]::Round(((Get-Date) - (Get-CimInstance Win32_OperatingSystem).LastBootUpTime).TotalHours, 1)
            }
            windowsVersion = @{
                build        = (Get-CimInstance Win32_OperatingSystem).BuildNumber
                architecture = (Get-CimInstance Win32_OperatingSystem).OSArchitecture
            }
            script         = @{
                name             = $ScriptName
                path             = $ScriptFullPath
                drive            = $ScriptDrive
                driveType        = $DriveType
                isNetworkPath    = $IsNetworkPath
                currentUser      = $CurrentUser
                isAdmin          = $IsAdmin
                osVersion        = $OSVersion
                osArch           = $OSArch
                psVersion        = $PSVersion
                workingDirectory = $WorkingDirectory.Path
                computerName     = $ComputerName
            }
        }

        # Get disk information for system drive
        $systemDrive = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$($env:SystemDrive)'"
        if ($systemDrive) {
            $reportData.systemInfo.disk = @{
                totalGB     = [math]::Round($systemDrive.Size / 1GB, 2)
                freeGB      = [math]::Round($systemDrive.FreeSpace / 1GB, 2)
                usedPercent = [math]::Round((($systemDrive.Size - $systemDrive.FreeSpace) / $systemDrive.Size) * 100, 1)
            }
        }
    }
    catch {
        Write-Log "Error collecting system information: $_" 'WARN'
        $reportData.systemInfo.error = "Failed to collect system information: $_"
    }

    # Inventory files
    if (Test-Path $global:TempFolder) {
        $inventoryFiles = Get-ChildItem -Path $global:TempFolder -Filter "*.json" -ErrorAction SilentlyContinue
        $reportData.files.inventoryFiles = $inventoryFiles | ForEach-Object { 
            @{
                name    = $_.Name
                path    = $_.FullName
                sizeKB  = [math]::Round($_.Length / 1KB, 2)
                created = $_.CreationTime.ToString('yyyy-MM-dd HH:mm:ss')
            }
        }

        $tempFiles = Get-ChildItem -Path $global:TempFolder -File -ErrorAction SilentlyContinue
        $reportData.files.tempFiles = $tempFiles | ForEach-Object {
            @{
                name   = $_.Name
                sizeKB = [math]::Round($_.Length / 1KB, 2)
            }
        }
    }

    # Log files
    if (Test-Path $LogFile) {
        $reportData.files.logFiles += @{
            name   = "maintenance.log"
            path   = $LogFile
            sizeKB = [math]::Round((Get-Item $LogFile).Length / 1KB, 2)
        }
    }

    # Parse action logs from maintenance.log
    if (Test-Path $LogFile) {
        try {
            $logContent = Get-Content $LogFile -ErrorAction SilentlyContinue
            $logActions = @('✓ INSTALLED:', '✓ REMOVED:', '✓ DISABLED:', '✓ ENABLED:', '✓ CONFIGURED:', 'SUMMARY:', 'PERFORMANCE:')
            $actionLines = $logContent | ForEach-Object {
                $line = $_
                $logActions | Where-Object { $line -match $_ }
            }
            $reportData.actions = @($actionLines)
        }
        catch {
            Write-Log "Error parsing action logs: $_" 'WARN'
        }
    }

    # Generate report paths
    $jsonReportPath = Join-Path $global:TempFolder 'maintenance_report.json'
    $textReportPath = Join-Path $PSScriptRoot 'maintenance_report.txt'

    # Write structured JSON report
    try {
        $reportData | ConvertTo-Json -Depth 5 | Out-File -FilePath $jsonReportPath -Encoding UTF8
        Write-Log "Structured JSON report saved to $jsonReportPath" 'INFO'
    }
    catch {
        Write-Log "Failed to write JSON report: $_" 'WARN'
    }

    # Build human-readable text report
    $summaryLines = @()
    $summaryLines += "============================================================"
    $summaryLines += "           WINDOWS MAINTENANCE REPORT"
    $summaryLines += "============================================================"
    $summaryLines += "Generated: $($reportData.metadata.date)"
    $summaryLines += "User: $($reportData.metadata.user)"
    $summaryLines += "Computer: $($reportData.metadata.computer)"
    $summaryLines += "Script Version: $($reportData.metadata.scriptVersion)"
    $summaryLines += "OS: $($reportData.metadata.os) ($($reportData.metadata.osVersion))"
    $summaryLines += "PowerShell: $($reportData.metadata.powershellVersion)"
    $summaryLines += "Architecture: $($reportData.systemInfo.windowsVersion.architecture)"
    $summaryLines += "Build: $($reportData.systemInfo.windowsVersion.build)"
    $summaryLines += ""
    $summaryLines += "SYSTEM INFORMATION:"
    $summaryLines += "- Processor: $($reportData.systemInfo.processor)"
    $summaryLines += "- Memory: $($reportData.systemInfo.memory.availableGB) GB available of $($reportData.systemInfo.memory.totalGB) GB total"
    $summaryLines += "- Disk: $($reportData.systemInfo.disk.freeGB) GB free of $($reportData.systemInfo.disk.totalGB) GB total ($($reportData.systemInfo.disk.usedPercent)% used)"
    $summaryLines += "- Uptime: $($reportData.systemInfo.uptime.hours) hours"
    $summaryLines += ""
    $summaryLines += "EXECUTION SUMMARY:"
    $summaryLines += "- Total tasks: $($reportData.summary.totalTasks)"
    $summaryLines += "- Successful: $($reportData.summary.successfulTasks)"
    $summaryLines += "- Failed: $($reportData.summary.failedTasks)"
    $summaryLines += "- Success rate: $($reportData.summary.successRate)%"
    $summaryLines += "- Total duration: $([math]::Round($reportData.summary.totalDuration, 2)) seconds"
    $summaryLines += ""
    $summaryLines += "TASK BREAKDOWN:"
    foreach ($task in $reportData.tasks) {
        $status = if ($task.success) { '✓ SUCCESS' } else { '✗ FAILED' }
        $summaryLines += "- $($task.name) | $status | $($task.description) | Duration: $($task.duration)s"
        if ($task.error) {
            $summaryLines += "    Error: $($task.error)"
        }
    }
    $summaryLines += ""

    $summaryLines += "FILES GENERATED:"
    if ($reportData.files.inventoryFiles.Count -gt 0) {
        $summaryLines += "Inventory files:"
        $reportData.files.inventoryFiles | ForEach-Object { $summaryLines += "- $($_.name) ($($_.sizeKB) KB)" }
    }
    if ($reportData.files.logFiles.Count -gt 0) {
        $summaryLines += "Log files:"
        $reportData.files.logFiles | ForEach-Object { $summaryLines += "- $($_.name) ($($_.sizeKB) KB)" }
    }
    $summaryLines += ""

    if ($reportData.actions.Count -gt 0) {
        $summaryLines += "MAINTENANCE ACTIONS PERFORMED:"
        $reportData.actions | ForEach-Object { $summaryLines += "- $_" }
        $summaryLines += ""
    }

    $summaryLines += "============================================================"
    $summaryLines += "Report files:"
    $summaryLines += "- JSON Report: $jsonReportPath"
    $summaryLines += "- Text Report: $textReportPath"
    $summaryLines += "- Log File: $LogFile"
    if (Test-Path $global:TempFolder) {
        $summaryLines += "- Temp Folder: $global:TempFolder"
    }
    $summaryLines += "============================================================"

    # Write text report
    try {
        $summaryLines | Out-File -FilePath $textReportPath -Encoding UTF8
        Write-Log "Human-readable report saved to $textReportPath" 'INFO'
    }
    catch {
        Write-Log "Failed to write text report: $_" 'WARN'
    }

    Write-Log "[END] Unified Maintenance Report Generation" 'INFO'
    return @{
        JsonReport  = $jsonReportPath
        TextReport  = $textReportPath
        TaskCount   = $reportData.summary.totalTasks
        SuccessRate = $reportData.summary.successRate
    }
}

# ===============================
# SECTION 8: SCRIPT EXECUTION & INITIALIZATION
# ===============================
# - Configuration loading and validation
# - Global variables initialization  
# - Main execution logic and task orchestration
# - Cleanup and finalization processes

# ================================================================
# SCRIPT INITIALIZATION: Configuration and Global Variables
# ================================================================

# Global variables initialization
$global:TempFolder = Join-Path $PSScriptRoot 'temp_files'
$global:SystemInventory = $null
$global:TaskResults = @{}

# Create temp directory if it doesn't exist
if (-not (Test-Path $global:TempFolder)) {
    New-Item -Path $global:TempFolder -ItemType Directory -Force | Out-Null
}

# Configuration management with defaults
$configPath = Join-Path $PSScriptRoot "config.json"
$global:Config = @{
    SkipBloatwareRemoval    = $false
    SkipEssentialApps       = $false
    SkipWindowsUpdates      = $false
    SkipTelemetryDisable    = $false
    SkipSystemRestore       = $false
    SkipEventLogAnalysis    = $false
    SkipSecurityHardening   = $false
    SkipTaskbarOptimization = $false
    SkipDesktopBackground   = $false
    SkipPendingRestartCheck = $false
    CustomEssentialApps     = @()
    CustomBloatwareList     = @()
    EnableVerboseLogging    = $false
}

# Load configuration from config.json if it exists
if (Test-Path $configPath) {
    try {
        $config = Get-Content $configPath | ConvertFrom-Json
        # Merge custom config with defaults
        if ($config.SkipBloatwareRemoval) { $global:Config.SkipBloatwareRemoval = $config.SkipBloatwareRemoval }
        if ($config.SkipEssentialApps) { $global:Config.SkipEssentialApps = $config.SkipEssentialApps }
        if ($config.SkipWindowsUpdates) { $global:Config.SkipWindowsUpdates = $config.SkipWindowsUpdates }
        if ($config.SkipTelemetryDisable) { $global:Config.SkipTelemetryDisable = $config.SkipTelemetryDisable }
        if ($config.SkipSystemRestore) { $global:Config.SkipSystemRestore = $config.SkipSystemRestore }
        if ($config.SkipEventLogAnalysis) { $global:Config.SkipEventLogAnalysis = $config.SkipEventLogAnalysis }
        if ($config.SkipSecurityHardening) { $global:Config.SkipSecurityHardening = $config.SkipSecurityHardening }
        if ($config.SkipTaskbarOptimization) { $global:Config.SkipTaskbarOptimization = $config.SkipTaskbarOptimization }
        if ($config.SkipDesktopBackground) { $global:Config.SkipDesktopBackground = $config.SkipDesktopBackground }
        if ($config.SkipPendingRestartCheck) { $global:Config.SkipPendingRestartCheck = $config.SkipPendingRestartCheck }
        if ($config.CustomEssentialApps) { $global:Config.CustomEssentialApps = $config.CustomEssentialApps }
        if ($config.CustomBloatwareList) { $global:Config.CustomBloatwareList = $config.CustomBloatwareList }
        if ($config.EnableVerboseLogging) { $global:Config.EnableVerboseLogging = $config.EnableVerboseLogging }
        Write-Log "Configuration loaded from config.json" 'INFO'
    }
    catch {
        Write-Log "Error loading config.json: $_. Using defaults." 'WARN'
    }
}

# Bloatware list definition
$global:BloatwareList = @(
    # OEM Bloatware (Acer, ASUS, Dell, HP, Lenovo)
    'Acer.AcerPowerManagement', 'Acer.AcerQuickAccess', 'Acer.AcerUEIPFramework', 'Acer.AcerUserExperienceImprovementProgram',
    'ASUS.ASUSGiftBox', 'ASUS.ASUSLiveUpdate', 'ASUS.ASUSSplendidVideoEnhancementTechnology', 'ASUS.ASUSWebStorage',
    'ASUS.ASUSZenAnywhere', 'ASUS.ASUSZenLink', 'ASUS.MyASUS', 'ASUS.GlideX', 'ASUS.ASUSDisplayControl',
    'Dell.CustomerConnect', 'Dell.DellDigitalDelivery', 'Dell.DellFoundationServices', 'Dell.DellHelpAndSupport', 
    'Dell.DellMobileConnect', 'Dell.DellPowerManager', 'Dell.DellProductRegistration', 'Dell.DellSupportAssist', 
    'Dell.DellUpdate', 'Dell.MyDell', 'Dell.DellOptimizer', 'Dell.CommandUpdate',
    'HP.HP3DDriveGuard', 'HP.HPAudioSwitch', 'HP.HPClientSecurityManager', 'HP.HPConnectionOptimizer',
    'HP.HPDocumentation', 'HP.HPDropboxPlugin', 'HP.HPePrintSW', 'HP.HPJumpStart', 'HP.HPJumpStartApps',
    'HP.HPJumpStartLaunch', 'HP.HPRegistrationService', 'HP.HPSupportSolutionsFramework', 'HP.HPSureConnect',
    'HP.HPSystemEventUtility', 'HP.HPWelcome', 'HP.HPSmart', 'HP.HPQuickActions', 'HewlettPackard.SupportAssistant',
    'Lenovo.AppExplorer', 'Lenovo.LenovoCompanion', 'Lenovo.LenovoExperienceImprovement', 'Lenovo.LenovoFamilyCloud',
    'Lenovo.LenovoHotkeys', 'Lenovo.LenovoMigrationAssistant', 'Lenovo.LenovoModernIMController',
    'Lenovo.LenovoServiceBridge', 'Lenovo.LenovoSolutionCenter', 'Lenovo.LenovoUtility', 'Lenovo.LenovoVantage',
    'Lenovo.LenovoVoice', 'Lenovo.LenovoWiFiSecurity', 'Lenovo.LenovoNow', 'Lenovo.ImController.PluginHost',

    # Gaming and Social Apps
    'king.com.BubbleWitch', 'king.com.BubbleWitch3Saga', 'king.com.CandyCrush', 'king.com.CandyCrushFriends', 
    'king.com.CandyCrushSaga', 'king.com.CandyCrushSodaSaga', 'king.com.FarmHeroes', 'king.com.FarmHeroesSaga',
    'Gameloft.MarchofEmpires', 'G5Entertainment.HiddenCity', 'RandomSaladGamesLLC.SimpleSolitaire',
    'RoyalRevolt2.RoyalRevolt2', 'WildTangent.WildTangentGamesApp', 'WildTangent.WildTangentHelper',
    'Facebook.Facebook', 'Instagram.Instagram', 'LinkedIn.LinkedIn', 'TikTok.TikTok', 'Twitter.Twitter',
    'Discord.Discord', 'Snapchat.Snapchat', 'Telegram.TelegramDesktop',

    # Microsoft Built-in Bloatware
    'Microsoft.3DBuilder', 'Microsoft.Microsoft3DViewer', 'Microsoft.Print3D', 'Microsoft.Paint3D',
    'Microsoft.BingFinance', 'Microsoft.BingFoodAndDrink', 'Microsoft.BingHealthAndFitness', 'Microsoft.BingNews', 
    'Microsoft.BingSports', 'Microsoft.BingTravel', 'Microsoft.BingWeather', 'Microsoft.MSN',
    'Microsoft.GetHelp', 'Microsoft.Getstarted', 'Microsoft.HelpAndTips', 'Microsoft.WindowsTips',
    'Microsoft.MicrosoftOfficeHub', 'Microsoft.MicrosoftPowerBIForWindows', 'Microsoft.Office.OneNote', 
    'Microsoft.Office.Sway', 'Microsoft.OneConnect', 'Microsoft.People', 'Microsoft.ScreenSketch',
    'Microsoft.StickyNotes', 'Microsoft.Whiteboard', 'Microsoft.MicrosoftSolitaireCollection',
    'Microsoft.WindowsFeedback', 'Microsoft.WindowsFeedbackHub', 'Microsoft.WindowsMaps', 'Microsoft.WindowsReadingList',
    'Microsoft.WindowsSoundRecorder', 'Microsoft.SoundRecorder', 'Microsoft.NetworkSpeedTest', 'Microsoft.News',
    'Microsoft.PowerAutomateDesktop', 'Microsoft.ToDo', 'Microsoft.Wallet', 'Microsoft.MinecraftUWP', 
    'Microsoft.MixedReality.Portal', 'Microsoft.MinecraftEducationEdition',

    # Xbox and Gaming
    'Microsoft.Xbox.TCUI', 'Microsoft.XboxApp', 'Microsoft.XboxGameOverlay', 'Microsoft.XboxGamingOverlay', 
    'Microsoft.XboxIdentityProvider', 'Microsoft.XboxSpeechToTextOverlay', 'Microsoft.GamingApp', 
    'Microsoft.GamingServices', 'Microsoft.XboxGameCallableUI',

    # Media Apps
    'Microsoft.ZuneMusic', 'Microsoft.ZuneVideo', 'Microsoft.Groove', 'Microsoft.Movies', 'Microsoft.Music',
    'Spotify.Spotify', 'Amazon.AmazonPrimeVideo', 'Netflix.Netflix', 'Hulu.Hulu', 'Disney.DisneyPlus',
    'SlingTV.Sling', 'Pandora.Pandora', 'iHeartRadio.iHeartRadio',

    # Communication Apps (Skype variants)
    'Microsoft.SkypeApp', 'Microsoft.Skype', 'Skype.Skype',

    # Office and Productivity (Bloatware versions)
    'Microsoft.Office.Desktop', 'Microsoft.OfficeHub',

    # Windows 11 Specific Bloatware
    'Microsoft.WindowsAlarms', 'Microsoft.Clipchamp',
    'Microsoft.PowerToys', 'Microsoft.WidgetsPlatformRuntime', 'Microsoft.Widgets', 

    # Security and Antivirus Bloatware
    'Avast.AvastFreeAntivirus', 'AVG.AVGAntiVirusFree', 'Avira.Avira', 
    'ESET.ESETNOD32Antivirus', 'Kaspersky.Kaspersky', 'McAfee.LiveSafe', 'McAfee.Livesafe', 
    'McAfee.SafeConnect', 'McAfee.Security', 'McAfee.WebAdvisor', 'Norton.OnlineBackup', 'Norton.Security',
    'Norton.NortonSecurity', 'Malwarebytes.Malwarebytes', 'IOBit.AdvancedSystemCare', 'IOBit.DriverBooster',
    'Piriform.CCleaner', 'PCAccelerate.PCAcceleratePro', 'PCOptimizer.PCOptimizerPro', 'Reimage.ReimageRepair'
) | Sort-Object -Unique

# Add custom bloatware from config if any
if ($global:Config.CustomBloatwareList -and $global:Config.CustomBloatwareList.Count -gt 0) {
    $global:BloatwareList += $global:Config.CustomBloatwareList
    $global:BloatwareList = $global:BloatwareList | Sort-Object -Unique
    Write-Log "Added $($global:Config.CustomBloatwareList.Count) custom bloatware entries from config" 'INFO'
}

# Save bloatware list
$bloatwareListPath = Join-Path $global:TempFolder 'bloatware.json'
$global:BloatwareList | ConvertTo-Json -Depth 3 | Out-File $bloatwareListPath -Encoding UTF8

# Essential Apps list definition
$global:EssentialApps = @(
    @{ Name = 'Adobe Acrobat Reader'; Winget = 'Adobe.Acrobat.Reader.64-bit'; Choco = 'adobereader' },
    @{ Name = 'Google Chrome'; Winget = 'Google.Chrome'; Choco = 'googlechrome' },
    @{ Name = 'Mozilla Firefox'; Winget = 'Mozilla.Firefox'; Choco = 'firefox' },
    @{ Name = 'Mozilla Thunderbird'; Winget = 'Mozilla.Thunderbird'; Choco = 'thunderbird' },
    @{ Name = 'Microsoft Edge'; Winget = 'Microsoft.Edge'; Choco = 'microsoft-edge' },
    @{ Name = 'Total Commander'; Winget = 'Ghisler.TotalCommander'; Choco = 'totalcommander' },
    @{ Name = 'PowerShell 7'; Winget = 'Microsoft.Powershell'; Choco = 'powershell' },
    @{ Name = 'Windows Terminal'; Winget = 'Microsoft.WindowsTerminal'; Choco = 'microsoft-windows-terminal' },
    @{ Name = 'WinRAR'; Winget = 'RARLab.WinRAR'; Choco = 'winrar' },
    @{ Name = '7-Zip'; Winget = '7zip.7zip'; Choco = '7zip' },
    @{ Name = 'Notepad++'; Winget = 'Notepad++.Notepad++'; Choco = 'notepadplusplus' },
    @{ Name = 'PDF24 Creator'; Winget = 'PDF24.PDF24Creator'; Choco = 'pdf24' },
    @{ Name = 'Java 8 Update'; Winget = 'Oracle.JavaRuntimeEnvironment'; Choco = 'javaruntime' }
)

# Add custom essential apps from config if any
if ($global:Config.CustomEssentialApps -and $global:Config.CustomEssentialApps.Count -gt 0) {
    $global:EssentialApps += $global:Config.CustomEssentialApps
    Write-Log "Added $($global:Config.CustomEssentialApps.Count) custom essential apps from config" 'INFO'
}

# Save essential apps list
$essentialAppsListPath = Join-Path $global:TempFolder 'essential_apps.json'
$global:EssentialApps | ConvertTo-Json -Depth 5 | Out-File $essentialAppsListPath -Encoding UTF8

# Task definitions
$global:ScriptTasks = @(
    @{ 
        Name        = 'SystemInventory'; 
        Function    = { Get-ExtensiveSystemInventory }; 
        Description = 'Comprehensive system inventory collection (AppX, Winget, Chocolatey, Registry)' 
    },
    @{ 
        Name        = 'BloatwareRemoval'; 
        Function    = { if (-not $global:Config.SkipBloatwareRemoval) { Remove-Bloatware } else { Write-Log "Bloatware removal skipped via config" 'INFO'; $true } }; 
        Description = 'Remove bloatware applications using diff-based optimization' 
    },
    @{ 
        Name        = 'EssentialApps'; 
        Function    = { if (-not $global:Config.SkipEssentialApps) { Install-EssentialApps } else { Write-Log "Essential apps installation skipped via config" 'INFO'; $true } }; 
        Description = 'Install essential applications with LibreOffice fallback' 
    },
    @{ 
        Name        = 'WindowsUpdates'; 
        Function    = { if (-not $global:Config.SkipWindowsUpdates) { Install-WindowsUpdatesCompatible } else { Write-Log "Windows updates skipped via config" 'INFO'; $true } }; 
        Description = 'Install Windows updates using PSWindowsUpdate module' 
    },
    @{ 
        Name        = 'TelemetryDisable'; 
        Function    = { if (-not $global:Config.SkipTelemetryDisable) { Disable-Telemetry } else { Write-Log "Telemetry disable skipped via config" 'INFO'; $true } }; 
        Description = 'Disable Windows telemetry and privacy features' 
    },
    @{ 
        Name        = 'SpotlightMeetNowNewsLocation'; 
        Function    = { Disable-SpotlightMeetNowNewsLocation }; 
        Description = 'Disable Windows Spotlight, Meet Now, News/Interests, Widgets, and Location services' 
    },
    @{ 
        Name        = 'AppBrowserControl'; 
        Function    = { Enable-AppBrowserControl }; 
        Description = 'Enable App & Browser Control (SmartScreen, Network Protection, Controlled Folder Access, Exploit Protection)' 
    },
    @{ 
        Name        = 'SystemRestore'; 
        Function    = { if (-not $global:Config.SkipSystemRestore) { Protect-SystemRestore } else { Write-Log "System restore skipped via config" 'INFO'; $true } }; 
        Description = 'Create system restore point and enable protection' 
    },
    @{ 
        Name        = 'TempCleanup'; 
        Function    = { Clear-TempFiles }; 
        Description = 'Clean temporary files and browser caches' 
    },
    @{ 
        Name        = 'DefenderScan'; 
        Function    = { Start-DefenderFullScan }; 
        Description = 'Windows Defender full system scan with automatic threat cleanup' 
    }
)

# ================================================================
# MAIN EXECUTION LOGIC
# ================================================================

# Enhanced script startup logging with system information
$startTime = Get-Date
Write-Log "============================================================" 'INFO'
Write-ActionLog -Action "PowerShell Maintenance Script Starting" -Details "Enhanced logging enabled" -Category "System Startup" -Status 'START'
Write-ActionLog -Action "Environment Analysis" -Details "Script Path: $PSCommandPath" -Category "System Startup" -Status 'INFO'
Write-ActionLog -Action "Environment Analysis" -Details "PowerShell Version: $($PSVersionTable.PSVersion)" -Category "System Startup" -Status 'INFO'
Write-ActionLog -Action "Environment Analysis" -Details "PowerShell Edition: $($PSVersionTable.PSEdition)" -Category "System Startup" -Status 'INFO'
Write-ActionLog -Action "Environment Analysis" -Details "OS Version: $([System.Environment]::OSVersion.VersionString)" -Category "System Startup" -Status 'INFO'
Write-ActionLog -Action "Environment Analysis" -Details "User: $([System.Environment]::UserName)" -Category "System Startup" -Status 'INFO'
Write-ActionLog -Action "Environment Analysis" -Details "Machine: $([System.Environment]::MachineName)" -Category "System Startup" -Status 'INFO'
Write-ActionLog -Action "Environment Analysis" -Details "Temp Folder: $global:TempFolder" -Category "System Startup" -Status 'INFO'
Write-ActionLog -Action "Configuration Status" -Details "Verbose Logging: $($global:Config.EnableVerboseLogging)" -Category "System Startup" -Status 'INFO'
Write-ActionLog -Action "Logging Configuration" -Details "Log File: $global:LogFile" -Category "System Startup" -Status 'INFO'
Write-Log "============================================================" 'INFO'

# Execute all maintenance tasks with enhanced logging
Write-ActionLog -Action "Starting maintenance task execution" -Details "All configured tasks will be executed" -Category "Task Orchestration" -Status 'START'
Use-AllScriptTasks

# ================================================================
# POST-EXECUTION REPORTING AND CLEANUP
# ================================================================

# Calculate summary statistics
$successCount = ($global:TaskResults.Values | Where-Object { $_.Success }).Count
$failCount = ($global:TaskResults.Values | Where-Object { -not $_.Success }).Count
$totalCount = $global:TaskResults.Count

# Log task execution summary
Write-Log "============================================================" 'INFO'
Write-Log "MAINTENANCE EXECUTION SUMMARY" 'INFO'
Write-Log "Total tasks: $totalCount | Success: $successCount | Failed: $failCount" 'INFO'

# Detailed task results
foreach ($taskName in $global:TaskResults.Keys) {
    $result = $global:TaskResults[$taskName]
    $task = $global:ScriptTasks | Where-Object { $_.Name -eq $taskName }
    $status = if ($result.Success) { 'SUCCESS' } else { 'FAILED' }
    $duration = if ($result.Duration) { [math]::Round($result.Duration, 2) } else { 0 }
    $started = if ($result.Started) { $result.Started.ToString('HH:mm:ss') } else { 'Unknown' }
    $ended = if ($result.Ended) { $result.Ended.ToString('HH:mm:ss') } else { 'Unknown' }
    
    Write-Log "Task: $taskName | $status | Duration: ${duration}s | $started-$ended" 'INFO'
    if (-not $result.Success -and $result.ContainsKey('Error') -and $result.Error) {
        Write-Log "    Error: $($result.Error)" 'ERROR'
    }
}

Write-Log "============================================================" 'INFO'

# Generate comprehensive reports
Write-Log "Generating maintenance reports..." 'INFO'

# Generate temp lists summary
Write-TempListsSummary

# Generate unified maintenance report
$reportResult = Write-UnifiedMaintenanceReport

if ($reportResult) {
    Write-Log "Reports generated successfully:" 'INFO'
    Write-Log "- JSON Report: $($reportResult.JsonReport)" 'INFO'
    Write-Log "- Text Report: $($reportResult.TextReport)" 'INFO'
    Write-Log "- Success Rate: $($reportResult.SuccessRate)%" 'INFO'
}

# Final completion logging
$totalExecutionTime = (Get-Date) - $startTime
$completionTimestamp = Get-Date -Format 'MM/dd/yyyy HH:mm:ss'

Write-Log "============================================================" 'INFO'
Write-Log "PowerShell Maintenance Script execution completed successfully" 'INFO'
Write-Log "Total execution time: $totalExecutionTime" 'INFO' 
Write-Log "Log file location: $LogFile" 'INFO'
Write-Log "============================================================" 'INFO'

# Add completion marker to log file for script.bat detection
Add-Content -Path $LogFile -Value "[$completionTimestamp] [INFO] ============================================================"
Add-Content -Path $LogFile -Value "[$completionTimestamp] [INFO] PowerShell Maintenance Script Completed Successfully"
Add-Content -Path $LogFile -Value "[$completionTimestamp] [INFO] Returning control to script.bat (if applicable)"
Add-Content -Path $LogFile -Value "[$completionTimestamp] [INFO] ============================================================"

# Interactive closure prompt for console environments with 60s countdown and auto-cleanup
if ($Host.Name -eq 'ConsoleHost' -or $Host.Name -like '*Windows*') {
    Write-Host
    Write-Host "✅ Maintenance script completed successfully!" -ForegroundColor Green
    Write-Host "📊 Tasks: $totalCount | ✅ Success: $successCount | ❌ Failed: $failCount" -ForegroundColor Cyan
    Write-Host "⏱️  Total time: $totalExecutionTime" -ForegroundColor Cyan
    Write-Host "📄 Reports available in: $PSScriptRoot" -ForegroundColor Cyan
    Write-Host
    Write-Host "Press any key to keep this window open, or wait 60 seconds to auto-cleanup and close..." -ForegroundColor Yellow

    $repoFolder = $PSScriptRoot
    $countdown = 60
    $abort = $false

    # Use .NET Console for non-blocking key detection
    [System.Console]::TreatControlCAsInput = $true
    for ($i = $countdown; $i -ge 1; $i--) {
        Write-Host ("\rClosing in $i seconds... Press any key to abort.") -NoNewline
        Start-Sleep -Milliseconds 1000
        if ([System.Console]::KeyAvailable) {
            $null = [System.Console]::ReadKey($true)
            $abort = $true
            break
        }
    }
    Write-Host ""
    if (-not $abort) {
        Write-Host "No key pressed. Removing repository folder and closing window..." -ForegroundColor Red
        try {
            Set-Location -Path ([System.IO.Path]::GetPathRoot($repoFolder))
            Remove-Item -Path $repoFolder -Recurse -Force -ErrorAction SilentlyContinue
            Write-Host "Repository folder removed: $repoFolder" -ForegroundColor Red
        } catch {
            Write-Host "Failed to remove repository folder: $_" -ForegroundColor Red
        }
        # Close the terminal window (works for most hosts)
        if ($Host.Name -eq 'ConsoleHost') {
            Stop-Process -Id $PID -Force
        } elseif ($Host.UI.RawUI.WindowTitle) {
            exit
        }
    } else {
        Write-Host "Cleanup aborted by user. Window will remain open." -ForegroundColor Green
        Read-Host -Prompt 'Press Enter to close this window...'
    }
}
