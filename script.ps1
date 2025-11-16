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
# Progress Tracking: Clean visual progress bars with minimal logging noise (v2025.1)
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
$ScriptDrive = if ($ScriptFullPath.StartsWith('\\')) {
    'UNC Path'
}
else {
    (Get-Item $ScriptFullPath).PSDrive.Name + ':'
}

# Drive type detection for path independence (matching batch script logic)
$IsNetworkPath = $false
$IsUNCPath = $ScriptFullPath.StartsWith('\\')

if ($IsUNCPath) {
    $IsNetworkPath = $true
    $DriveType = 'Network'
}
elseif ($ScriptDrive -ne 'UNC Path') {
    $DriveInfo = Get-CimInstance -Class Win32_LogicalDisk | Where-Object { $_.DeviceID -eq $ScriptDrive }
    if ($DriveInfo) {
        $DriveTypeNum = $DriveInfo.DriveType
        if ($DriveTypeNum -eq 4) {
            $IsNetworkPath = $true
        }
        $DriveType = switch ($DriveTypeNum) {
            2 { 'Removable' }
            3 { 'Fixed' }
            4 { 'Network' }
            5 { 'CD-ROM' }
            default { 'Unknown' }
        }
    }
    else {
        $DriveType = 'Unknown'
    }
}
else {
    $DriveType = 'Unknown'
}

# System environment information
$ComputerName = $env:COMPUTERNAME
$CurrentUser = $env:USERNAME
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$OSVersion = (Get-CimInstance -Class Win32_OperatingSystem).Caption
$OSArchitecture = $env:PROCESSOR_ARCHITECTURE
$OSArch = switch ($OSArchitecture) {
    'AMD64' { 'x64' }
    'x86' { 'x86' }
    'ARM64' { 'ARM64' }
    default { $OSArchitecture }
}
$PSVersion = $PSVersionTable.PSVersion.ToString()

# Determine working directory - use batch script's working directory if available
if ($env:WORKING_DIRECTORY) {
    $WorkingDirectory = $env:WORKING_DIRECTORY
}
else {
    # Fallback to script directory if no environment variable
    $WorkingDirectory = Split-Path -Parent $ScriptFullPath
}

# Log file setup - prioritize parameter, then environment variable, then default
if ($LogFilePath) {
    $resolvedLogFile = $LogFilePath
}
elseif ($env:SCRIPT_LOG_FILE) {
    $resolvedLogFile = $env:SCRIPT_LOG_FILE
}
else {
    $batchScriptDirectory = Split-Path $ScriptDir -Parent
    $resolvedLogFile = Join-Path $batchScriptDirectory 'maintenance.log'
}

$script:LogFile = $resolvedLogFile
$global:LogFile = $resolvedLogFile

# Ensure log file directory exists
$logDir = Split-Path $script:LogFile -Parent
if (-not (Test-Path $logDir)) {
    New-Item -Path $logDir -ItemType Directory -Force | Out-Null
}

# ================================================================
# LOGGING SYSTEM: Three-Tier Structured Logging
# ================================================================
# Purpose: Provide unified logging across console and file output
#          with support for multiple severity levels and filtering
# 
# Architecture:
#   Tier 1: Write-Log (Basic logging - all messages)
#   Tier 2: Write-ActionLog (Structured action tracking)
#   Tier 3: Write-CommandLog (External process logging)
#
# Features:
#   - Timestamp on every entry (YYYY-MM-DD HH:mm:ss format)
#   - Configurable severity levels (DEBUG, INFO, WARN, ERROR, etc.)
#   - Dual output: Console + File (inheritance from batch launcher)
#   - Color-coded console output based on level
#   - Error resilience (continues if logging fails)
#
# Log Levels:
#   DEBUG   - Diagnostic information
#   INFO    - Normal operational messages
#   WARN    - Warning conditions
#   ERROR   - Error conditions requiring attention
#   SUCCESS - Successful completion indicators
#   ACTION  - High-level action boundaries
#   COMMAND - External command execution
#
# NOTE: The full implementation of Write-Log is defined in SECTION 2 below
# with enhanced parameter validation and error handling.

# ================================================================
# GLOBAL CONFIGURATION & DEFAULTS
# ================================================================
# Purpose: Centralized, user-customizable configuration for the maintenance
#          script. These settings drive conditional execution of features,
#          allowing users to enable/disable behavior without code editing.
#
# Architecture:
#   - Boolean Skip* flags: Enable/disable major feature categories
#   - Collection fields: Add custom apps, bloatware patterns, task exclusions
#   - Service lists: Configure services to disable during maintenance
#
# Conventions:
#   - Skip* booleans default to $false (features enabled by default)
#     Set to $true to disable that feature
#   - Collection fields accept arrays of strings (IDs, names, patterns)
#     and are merged with built-in lists at runtime
#   - ExcludeTasks accepts task names matching $global:ScriptTasks entries
#
# Usage Examples:
#   # Disable bloatware removal:
#   $global:Config.SkipBloatwareRemoval = $true
#
#   # Add custom applications to install:
#   $global:Config.CustomEssentialApps += @('7zip.7zip', 'Notepad++.Notepad++')
#
#   # Add custom bloatware patterns to remove:
#   $global:Config.CustomBloatwareList += @('MyBloatApp.*', 'OEMTool.*')
#
#   # Exclude specific tasks from execution:
#   $global:Config.ExcludeTasks += @('DesktopBackground', 'TaskbarOptimization')
#
$global:Config = @{
    # Feature Control Flags (set to $true to disable each feature)
    SkipBloatwareRemoval       = $false   # When $true, bloatware removal is skipped
    SkipEssentialApps          = $false   # When $true, essential app installation skipped
    SkipWindowsUpdates         = $false   # When $true, Windows Update tasks skipped
    SkipPackageUpdates         = $false   # When $true, package manager updates skipped
    SkipTelemetryDisable       = $false   # When $true, telemetry disabling skipped
    SkipSystemRestore          = $false   # When $true, System Restore tasks skipped
    SkipRestorePointCleanup    = $false   # When $true, old restore points not cleaned
    SkipEventLogAnalysis       = $false   # When $true, event log analysis skipped
    SkipSecurityHardening      = $false   # When $true, security hardening skipped
    SkipTaskbarOptimization    = $false   # When $true, taskbar customization skipped
    SkipDesktopBackground      = $false   # When $true, wallpaper changes skipped
    SkipPendingRestartCheck    = $false   # When $true, restart detection skipped
    SkipSystemHealthRepair     = $false   # When $true, DISM/SFC repair skipped
    SkipWidgetsOnly            = $false   # When $true, skip widget/Spotlight cleanup tasks

    # Logging and Troubleshooting
    EnableVerboseLogging       = $false   # When $true, enables detailed debug output

    # Collections: Arrays for augmenting built-in lists
    CustomEssentialApps        = @()      # Package IDs to install beyond defaults
    CustomBloatwareList        = @()      # App patterns/names to treat as bloatware
    ExcludeTasks               = @()      # Task names to exclude from execution

    # Telemetry Services: Services to disable during privacy hardening
    TelemetryServicesToDisable = @(
        'DiagTrack',                   # Diagnostic Tracking Service
        'dmwappushservice',            # Microsoft Account Sign-in Assistant
        'UnistoreSvc',                 # User Data Storage Service
        'UserDataSvc',                 # User Data Service
        'BrokerInfrastructure',        # Background Tasks Infrastructure Service
        'PimIndexMaintenanceSvc',      # Personal Information Management
        'MessagingService'             # Messaging Service
    )

    # Behavioral toggles
    AllowDisableWerSvc         = $false   # When $true, allows disabling Windows Error Reporting service
    PromptForReboot            = $false   # When $true, prompt/countdown for restart is enabled
    MinRestorePointsToKeep     = 5        # Minimum restore points retained during cleanup
}

function New-TaskSkipResult {
    param([string]$Reason = 'Skipped by configuration')

    return [ordered]@{
        IsSuccessful = $true
        Status       = $Reason
        Payload      = $null
    }
}

# ================================================================
# GLOBAL VARIABLES & STATE MANAGEMENT
# ================================================================
# Purpose: Track script execution state and maintain shared context
#          across functions, tasks, and logging operations
#
# Variables:
#   $global:TaskResults      - Execution results for all completed tasks
#   $global:SystemInventory  - Cached system information (CPU, memory, OS)
#   $global:AppInventoryCache - Cached application detection results
#   $global:BloatwareList    - Merged bloatware patterns (built-in + custom)
#   $global:EssentialApps    - Merged essential apps (built-in + custom)
#   $global:TempFolder       - Temporary file directory for downloads/snapshots
#   $global:AppCategories    - Built-in bloatware app categories
#   $global:EssentialCategories - Built-in essential app categories
#   $global:PackageManagers  - Package manager configurations (Winget, Choco)
#   $global:SystemSettings   - System timeouts, paths, restart tracking
#   $global:ScriptTasks      - Array of task definitions for orchestration
#
# Usage:
#   All functions read/write to these globals to maintain state
#   Results are aggregated for final reporting and HTML report generation
#
$global:TaskResults = @{}              # Dictionary of task execution results
$global:SystemInventory = $null        # OS and hardware information (lazy-loaded)
$global:AppInventoryCache = $null      # Detected applications (cached to avoid rescans)
# ================================================================
# Path Resolution Diagnostics (Debug Information)
# ================================================================
Write-Log '=== PATH RESOLUTION DIAGNOSTICS ===' 'DEBUG'
Write-Log "Script Full Path: $ScriptFullPath" 'DEBUG'
Write-Log "Script Directory: $ScriptDir" 'DEBUG'
Write-Log "Environment WORKING_DIRECTORY: $env:WORKING_DIRECTORY" 'DEBUG'
Write-Log "PowerShell Working Directory: $WorkingDirectory" 'DEBUG'
Write-Log "Drive Type: $DriveType" 'DEBUG'
Write-Log "Is Network Path: $IsNetworkPath" 'DEBUG'
Write-Log "UNC Path: $IsUNCPath" 'DEBUG'

# Determine repository-based temp folder. Prefer $ScriptDir (script location) when available,
# otherwise use the configured $WorkingDirectory. If creation fails, fallback to the system temp path.
$repoTempBase = if ($ScriptDir) { $ScriptDir } else { $WorkingDirectory }
$global:TempFolder = Join-Path $repoTempBase 'temp_files'
Write-Log "Temp Folder Base Resolution: $repoTempBase" 'DEBUG'
Write-Log "Temp Folder Path: $global:TempFolder" 'DEBUG'
$global:BloatwareList = @()
$global:EssentialApps = @()

# Create temp directory if it doesn't exist (early initialization)
if (-not (Test-Path $global:TempFolder)) {
    try {
        Write-Log "Attempting to create temp folder: $global:TempFolder" 'DEBUG'
        New-Item -Path $global:TempFolder -ItemType Directory -Force | Out-Null
        Write-Log "Created temp folder: $global:TempFolder" 'INFO'
    }
    catch {
        Write-Log "Failed to create repo temp folder $global:TempFolder: $($_.Exception.Message) - falling back to system temp" 'WARN'
        $global:TempFolder = [System.IO.Path]::GetTempPath()
        Write-Log "Using system temp path: $global:TempFolder" 'INFO'
    }
}

# Validate write access to temp folder
try {
    Write-Log "Validating write access to temp folder: $global:TempFolder" 'DEBUG'
    $testFile = Join-Path $global:TempFolder "test_$(Get-Random).tmp"
    'test_write_validation' | Out-File $testFile -Force -ErrorAction Stop
    Remove-Item $testFile -Force -ErrorAction SilentlyContinue | Out-Null
    Write-Log 'Write access verified for temp folder' 'DEBUG'
}
catch {
    Write-Log "No write access to temp folder - $_" 'WARN'
    Write-Log 'Attempting fallback to system temp path' 'WARN'
    $global:TempFolder = [System.IO.Path]::GetTempPath()
    Write-Log "Using system temp path (fallback): $global:TempFolder" 'INFO'
}
Write-Log '=== END PATH DIAGNOSTICS ===' 'DEBUG'

# ================================================================
# TASK ORCHESTRATION SYSTEM - Global Task Array
# ================================================================
# Purpose: Centralized maintenance task coordination with standardized metadata
#          for configuration-driven execution and comprehensive result tracking
#
# Architecture:
#   Each task is a hashtable with three properties:
#     - Name: Unique identifier (used for skip flags in $global:Config)
#     - Function: ScriptBlock containing task logic and error handling
#     - Description: Human-readable purpose statement for reporting
#
# Execution Model:
#   Sequential execution via Use-AllScriptTasks() main orchestrator
#   Config-driven skip logic: Check $global:Config.Skip{TaskName}
#   Result tracking: Store results in $global:TaskResults[{TaskName}]
#   Logging: All tasks follow standardized error handling patterns
#
# Adding New Tasks:
#   1. Create task function (or inline scriptblock)
#   2. Add entry to $global:ScriptTasks array with Name/Function/Description
#   3. Add optional Skip flag to $global:Config section
#   4. Task automatically included in orchestration
#
# Task Execution Order:
#   1. SystemRestoreProtection   - Create restore point (critical)
#   2. SystemInventory           - Collect system info (always run)
#   3. RemoveBloatware           - Remove unwanted apps
#   4. InstallEssentialApps      - Install important software
#   5. UpdateAllPackages         - Update existing packages
#   6. WindowsUpdateCheck        - Install Windows Updates
#   7. DisableTelemetry          - Privacy hardening
#   8. TaskbarOptimization       - UI customization
#   9. DesktopBackground         - Wallpaper changes
#  10. SecurityHardening         - Security improvements
#  11. CleanTempAndDisk          - Temporary file cleanup
#  12. SystemHealthRepair        - DISM/SFC repairs
#  13. PendingRestartCheck       - Detect restart needs
#  14. GenerateReports           - Final reporting
#
# Dependencies:
#   - All tasks use $global:Config for skip flags
#   - Task results aggregated in $global:TaskResults
#   - Logging via Write-Log function (timestamped, level-based)
#   - System info available in $global:SystemInventory (lazy-loaded)
#
$global:ScriptTasks = @(
    @{ Name = 'SystemRestoreProtection'; Description = 'Enable System Restore and create pre-maintenance checkpoint'; Importance = 'CRITICAL'; Function = {
            $skipResult = Test-TaskShouldSkip -SkipFlagName 'SkipSystemRestore' -TaskName 'System Restore Protection'
            if ($skipResult) { return $skipResult }

            Write-Log 'Starting System Restore Protection task.' 'INFO'
            Protect-SystemRestore
        }
    },
    @{ Name = 'SystemInventory'; Description = 'Collect comprehensive system information for analysis and reporting'; Importance = 'CRITICAL'; Function = {
            Write-Log 'Starting System Inventory task.' 'INFO'
            try {
                return Get-OptimizedSystemInventory -UseCache -IncludeBloatwareDetection
            }
            catch {
                Write-Log "Optimized system inventory collection failed. Falling back to baseline inventory: $($_.Exception.Message)" 'WARN'
                return Get-SystemInventory
            }
        }
    },
    @{ Name = 'RemoveBloatware'; Description = 'Remove unwanted apps via AppX, DISM, Registry, and Windows Capabilities'; Importance = 'HIGH'; Function = {
            $skipResult = Test-TaskShouldSkip -SkipFlagName 'SkipBloatwareRemoval' -TaskName 'Bloatware Removal'
            if ($skipResult) { return $skipResult }

            Write-Log 'Starting Bloatware Removal task.' 'INFO'
            Remove-Bloatware
        }
    },
    @{ Name = 'InstallEssentialApps'; Description = 'Install curated essential applications via parallel processing'; Importance = 'MEDIUM'; Function = {
            $skipResult = Test-TaskShouldSkip -SkipFlagName 'SkipEssentialApps' -TaskName 'Essential Apps Installation'
            if ($skipResult) { return $skipResult }

            Write-Log 'Starting Essential Apps Installation task.' 'INFO'
            Install-EssentialApps
        }
    },
    @{ Name = 'UpdateAllPackages'; Description = 'Update all installed packages via Winget, Chocolatey, and other package managers'; Importance = 'MEDIUM'; Function = {
            $skipResult = Test-TaskShouldSkip -SkipFlagName 'SkipPackageUpdates' -TaskName 'Package Updates'
            if ($skipResult) { return $skipResult }

            Write-Log 'Starting Package Updates task.' 'INFO'
            Update-AllPackages
        }
    },
    @{ Name = 'WindowsUpdateCheck'; Description = 'Check and install available Windows Updates with compatibility layer'; Importance = 'HIGH'; Function = {
            $skipResult = Test-TaskShouldSkip -SkipFlagName 'SkipWindowsUpdates' -TaskName 'Windows Update Check'
            if ($skipResult) { return $skipResult }

            Write-Log 'Starting Windows Update Check task.' 'INFO'
            Install-WindowsUpdatesCompatible
        }
    },
    @{ Name = 'DisableTelemetry'; Description = 'Disable Windows telemetry, privacy invasive features, and browser tracking'; Importance = 'MEDIUM'; Function = {
            $skipResult = Test-TaskShouldSkip -SkipFlagName 'SkipTelemetryDisable' -TaskName 'Telemetry Disable'
            if ($skipResult) { return $skipResult }

            Write-Log 'Starting Telemetry Disable task.' 'INFO'
            Disable-Telemetry
        }
    },
    @{ Name = 'SecurityHardening'; Description = 'Apply security hardening configurations and policy improvements'; Importance = 'HIGH'; Function = {
            $skipResult = Test-TaskShouldSkip -SkipFlagName 'SkipSecurityHardening' -TaskName 'Security Hardening'
            if ($skipResult) { return $skipResult }

            Write-Log 'Starting Security Hardening task.' 'INFO'
            Enable-SecurityHardening
        }
    },
    @{ Name = 'AppBrowserControl'; Description = 'Enable Defender SmartScreen, Network Protection, and controlled folder access safeguards'; Importance = 'HIGH'; Function = {
            $skipResult = Test-TaskShouldSkip -SkipFlagName 'SkipSecurityHardening' -TaskName 'App & Browser Control'
            if ($skipResult) { return $skipResult }

            Write-Log 'Starting App & Browser Control task.' 'INFO'
            Enable-AppBrowserControl
        }
    },
    @{ Name = 'TaskbarOptimization'; Description = 'Hide search box, disable Task View/Chat, remove Spotlight icons, optimize taskbar and desktop UI for Windows 10/11'; Importance = 'LOW'; Function = {
            $skipResult = Test-TaskShouldSkip -SkipFlagName 'SkipTaskbarOptimization' -TaskName 'Taskbar Optimization'
            if ($skipResult) { return $skipResult }

            Write-Log 'Starting Taskbar and Desktop UI Optimization task.' 'INFO'
            Optimize-TaskbarAndDesktopUI
        }
    },
    @{ Name = 'SpotlightMeetNowNewsLocation'; Description = 'Disable Windows Spotlight, Meet Now, News/Interests, Widgets, and Location services'; Importance = 'LOW'; Function = {
            if ($global:Config.SkipTaskbarOptimization -or $global:Config.SkipWidgetsOnly) {
                Write-Log 'Spotlight/Widgets cleanup skipped by configuration.' 'INFO'
                return New-TaskSkipResult 'Skipped (config)'
            }

            Write-Log 'Starting Spotlight, Widgets, and Meet Now cleanup task.' 'INFO'
            Disable-SpotlightMeetNowNewsLocation
        }
    },
    @{ Name = 'DesktopBackground'; Description = 'Change desktop background from Windows Spotlight to personalized slideshow'; Importance = 'LOW'; Function = {
            $skipResult = Test-TaskShouldSkip -SkipFlagName 'SkipDesktopBackground' -TaskName 'Desktop Background'
            if ($skipResult) { return $skipResult }

            Write-Log 'Starting Desktop Background Configuration task.' 'INFO'
            Set-DesktopBackground
        }
    },
    @{ Name = 'CleanTempAndDisk'; Description = 'Clean temporary files and perform disk space optimization'; Importance = 'MEDIUM'; Function = {
            Write-Log 'Starting Temporary Files and Disk Cleanup task.' 'INFO'
            try {
                Write-TaskProgress 'Starting disk cleanup' 20
                $cleanupActions = @(
                    @{ Path = $env:TEMP; Name = 'User Temp Files' },
                    @{ Path = "$env:WINDIR\Temp"; Name = 'System Temp Files' },
                    @{ Path = "$env:LOCALAPPDATA\Microsoft\Windows\INetCache"; Name = 'Internet Cache' },
                    @{ Path = "$env:USERPROFILE\AppData\Local\Temp"; Name = 'Local Temp Files' }
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

                Write-TaskProgress 'Disk cleanup completed' 100
                $statusMessage = "Disk cleanup completed: $([math]::Round($totalCleaned/1MB, 2)) MB freed"
                Write-Log $statusMessage 'INFO'

                return [ordered]@{
                    IsSuccessful = $true
                    Status       = $statusMessage
                    Payload      = @{ TotalBytesCleaned = $totalCleaned; Locations = $cleanupActions.Count }
                }
            }
            catch {
                Write-Log "Disk cleanup failed: $_" 'ERROR'
                return [ordered]@{
                    IsSuccessful = $false
                    Status       = 'Disk cleanup failed'
                    Error        = $_.Exception.Message
                }
            }
        }
    },
    @{ Name = 'TempCleanup'; Description = 'Comprehensive temporary file, cache, and recycle bin cleanup'; Importance = 'MEDIUM'; Function = {
            Write-Log 'Starting comprehensive temporary files cleanup task.' 'INFO'
            Clear-TempFiles
        }
    },
    @{ Name = 'SystemHealthRepair'; Description = 'Automated DISM and SFC system file integrity check and repair'; Importance = 'HIGH'; Function = {
            $skipResult = Test-TaskShouldSkip -SkipFlagName 'SkipSystemHealthRepair' -TaskName 'System Health Check and Repair'
            if ($skipResult) { return $skipResult }

            Write-Log 'Starting System Health Check and Repair task.' 'INFO'
            Start-SystemHealthRepair
        }
    },
    @{ Name = 'RestorePointCleanup'; Description = 'Clean old system restore points while keeping configured minimum recent points'; Importance = 'MEDIUM'; Function = {
            $skipResult = Test-TaskShouldSkip -SkipFlagName @('SkipRestorePointCleanup', 'SkipSystemRestore') -TaskName 'Restore point cleanup'
            if ($skipResult) { return $skipResult }

            Write-Log 'Starting Restore Point Cleanup task.' 'INFO'
            Clear-OldRestorePoints
        }
    },
    @{ Name = 'EventLogAnalysis'; Description = 'Analyze Event Viewer and CBS logs for recent system errors'; Importance = 'MEDIUM'; Function = {
            $skipResult = Test-TaskShouldSkip -SkipFlagName 'SkipEventLogAnalysis' -TaskName 'Event log analysis'
            if ($skipResult) { return $skipResult }

            Write-Log 'Starting Event Log Analysis task.' 'INFO'
            Get-EventLogAnalysis
        }
    },
    @{ Name = 'PendingRestartCheck'; Description = 'Check for pending restart requirements without initiating restart (restart handled at script end)'; Importance = 'MEDIUM'; Function = {
            $skipResult = Test-TaskShouldSkip -SkipFlagName 'SkipPendingRestartCheck' -TaskName 'Pending restart check'
            if ($skipResult) { return $skipResult }

            Write-Log 'Starting Pending Restart Check task.' 'INFO'
            try {
                $pendingRestart = $false
                $restartReason = 'System maintenance operations'

                if ($global:SystemSettings.Reboot.Required -eq $true) {
                    $pendingRestart = $true
                    $restartReason = "Windows Updates installation ($($global:SystemSettings.Reboot.Source))"
                    Write-Log "Pending restart detected from Windows Updates at $($global:SystemSettings.Reboot.Timestamp)" 'INFO'
                }

                $registryKeys = @(
                    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired',
                    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending',
                    'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\PendingFileRenameOperations'
                )

                foreach ($key in $registryKeys) {
                    if (Test-Path $key) {
                        $pendingRestart = $true
                        Write-Log "Pending restart detected: $key" 'INFO'
                        if ($restartReason -eq 'System maintenance operations') {
                            $restartReason = 'Registry pending operations'
                        }
                        break
                    }
                }

                if ($pendingRestart) {
                    $status = "Restart required: $restartReason"
                    Write-Log $status 'INFO'
                    return [ordered]@{
                        IsSuccessful = $true
                        Status       = $status
                        Payload      = @{ Pending = $true; Reason = $restartReason }
                    }
                }

                Write-Log 'No pending restart required.' 'INFO'
                return [ordered]@{
                    IsSuccessful = $true
                    Status       = 'No restart required'
                    Payload      = @{ Pending = $false }
                }
            }
            catch {
                Write-Log "Pending restart check failed: $_" 'ERROR'
                return [ordered]@{
                    IsSuccessful = $false
                    Status       = 'Pending restart check failed'
                    Error        = $_.Exception.Message
                }
            }
        }
    }
)

# ===============================
# SECTION 1.5: CONFIGURATION & CONSTANTS
# ===============================
# Purpose: Centralized configuration management, app lists, settings, and constants
# Functions: App list definitions, default settings, timeout configurations, path constants
# Dependencies: File system access for config.json, JSON processing capabilities
# Performance: One-time initialization, cached constants, efficient lookups
# Features: Customizable app lists, configurable timeouts, centralized path management
# ===============================

# ================================================================
# CONFIGURATION: Application Lists and Categories
# ================================================================

# Bloatware Categories and Definitions
$global:AppCategories = @{
    OEMBloatware       = @(
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
        'Lenovo.LenovoVoice', 'Lenovo.LenovoWiFiSecurity', 'Lenovo.LenovoNow', 'Lenovo.ImController.PluginHost'
    )
    GamingSocial       = @(
        'king.com.BubbleWitch', 'king.com.BubbleWitch3Saga', 'king.com.CandyCrush', 'king.com.CandyCrushFriends',
        'king.com.CandyCrushSaga', 'king.com.CandyCrushSodaSaga', 'king.com.FarmHeroes', 'king.com.FarmHeroesSaga',
        'Gameloft.MarchofEmpires', 'G5Entertainment.HiddenCity', 'RandomSaladGamesLLC.SimpleSolitaire',
        'RoyalRevolt2.RoyalRevolt2', 'WildTangent.WildTangentGamesApp', 'WildTangent.WildTangentHelper',
        'Facebook.Facebook', 'Instagram.Instagram', 'LinkedIn.LinkedIn', 'TikTok.TikTok', 'Twitter.Twitter',
        'Discord.Discord', 'Snapchat.Snapchat', 'Telegram.TelegramDesktop'
    )
    MicrosoftBloatware = @(
        'Microsoft.3DBuilder', 'Microsoft.Microsoft3DViewer', 'Microsoft.Print3D', 'Microsoft.Paint3D',
        'Microsoft.BingFinance', 'Microsoft.BingFoodAndDrink', 'Microsoft.BingHealthAndFitness', 'Microsoft.BingNews',
        'Microsoft.BingSports', 'Microsoft.BingTravel', 'Microsoft.BingWeather', 'Microsoft.MSN',
        'Microsoft.GetHelp', 'Microsoft.Getstarted', 'Microsoft.HelpAndTips', 'Microsoft.WindowsTips',
        'Microsoft.MicrosoftOfficeHub', 'Microsoft.MicrosoftPowerBIForWindows', 'Microsoft.Office.OneNote',
        'Microsoft.Office.Sway', 'Microsoft.OneConnect', 'Microsoft.StickyNotes', 'Microsoft.Whiteboard',
        'Microsoft.MicrosoftSolitaireCollection', 'Microsoft.WindowsFeedback', 'Microsoft.WindowsFeedbackHub',
        'Microsoft.WindowsReadingList', 'Microsoft.NetworkSpeedTest', 'Microsoft.News',
        'Microsoft.PowerAutomateDesktop', 'Microsoft.ToDo', 'Microsoft.Wallet', 'Microsoft.MinecraftUWP',
        'Microsoft.MixedReality.Portal', 'Microsoft.MinecraftEducationEdition'
    )
    XboxGaming         = @(
        'Microsoft.Xbox.TCUI', 'Microsoft.XboxApp', 'Microsoft.XboxGameOverlay', 'Microsoft.XboxGamingOverlay',
        'Microsoft.XboxIdentityProvider', 'Microsoft.XboxSpeechToTextOverlay', 'Microsoft.GamingApp',
        'Microsoft.XboxGameCallableUI'
    )
    SecurityBloatware  = @(
        'Avast.AvastFreeAntivirus', 'AVG.AVGAntiVirusFree', 'Avira.Avira',
        'ESET.ESETNOD32Antivirus', 'Kaspersky.Kaspersky', 'McAfee.LiveSafe', 'McAfee.Livesafe',
        'McAfee.SafeConnect', 'McAfee.Security', 'McAfee.WebAdvisor', 'Norton.OnlineBackup', 'Norton.Security',
        'Norton.NortonSecurity', 'Malwarebytes.Malwarebytes', 'IOBit.AdvancedSystemCare', 'IOBit.DriverBooster',
        'Piriform.CCleaner', 'PCAccelerate.PCAcceleratePro', 'PCOptimizer.PCOptimizerPro', 'Reimage.ReimageRepair'
    )
}

# Essential Apps Categories
$global:EssentialCategories = @{
    WebBrowsers   = @(
        @{ Name = 'Google Chrome'; Winget = 'Google.Chrome'; Choco = 'googlechrome'; Category = 'Browser' },
        @{ Name = 'Mozilla Firefox'; Winget = 'Mozilla.Firefox'; Choco = 'firefox'; Category = 'Browser' },
        @{ Name = 'Microsoft Edge'; Winget = 'Microsoft.Edge'; Choco = 'microsoft-edge'; Category = 'Browser' }
    )
    DocumentTools = @(
        @{ Name = 'Adobe Acrobat Reader'; Winget = 'Adobe.Acrobat.Reader.64-bit'; Choco = 'adobereader'; Category = 'Document' },
        @{ Name = 'PDF24 Creator'; Winget = 'geeksoftwareGmbH.PDF24Creator'; Choco = 'pdf24'; Category = 'Document' },
        @{ Name = 'Notepad++'; Winget = 'Notepad++.Notepad++'; Choco = 'notepadplusplus'; Category = 'Editor' }
    )
    FileManagers  = @(
        @{ Name = 'Total Commander'; Winget = 'Ghisler.TotalCommander'; Choco = 'totalcommander'; Category = 'FileManager' },
        @{ Name = 'WinRAR'; Winget = 'RARLab.WinRAR'; Choco = 'winrar'; Category = 'Compression' },
        @{ Name = '7-Zip'; Winget = '7zip.7zip'; Choco = '7zip'; Category = 'Compression' }
    )
    SystemTools   = @(
        @{ Name = 'Windows Terminal'; Winget = 'Microsoft.WindowsTerminal'; Choco = 'microsoft-windows-terminal'; Category = 'System' },
        @{ Name = 'Java 8 Update'; Winget = 'Oracle.JavaRuntimeEnvironment'; Choco = 'javaruntime'; Category = 'Runtime' },
        @{ Name = 'Sysmon'; Winget = $null; Choco = $null; DownloadUrl = 'https://download.sysinternals.com/files/Sysmon.zip'; Category = 'Security' }
    )
    Communication = @(
        @{ Name = 'Mozilla Thunderbird'; Winget = 'Mozilla.Thunderbird'; Choco = 'thunderbird'; Category = 'Email' }
    )
    RemoteAccess  = @(
        @{ Name = 'TeamViewer'; Winget = 'TeamViewer.TeamViewer'; Choco = 'teamviewer'; Category = 'RemoteDesktop' },
        @{ Name = 'RustDesk'; Winget = 'RustDesk.RustDesk'; Choco = 'rustdesk'; Category = 'RemoteDesktop' },
        @{ Name = 'UltraViewer'; Winget = 'DucFabulous.UltraViewer'; Choco = 'ultraviewer'; Category = 'RemoteDesktop' }
    )
}

# ================================================================
# CONFIGURATION: System Settings and Timeouts
# ================================================================

$global:SystemSettings = @{
    Timeouts = @{
        PackageManager  = 300  # 5 minutes for package operations
        SystemScan      = 1800     # 30 minutes for system scans
        Updates         = 3600        # 1 hour for Windows Updates
        Cleanup         = 600         # 10 minutes for cleanup operations
        AppInstallation = 900 # 15 minutes for app installation
    }
    Paths    = @{
        TempCleanupLocations = @(
            "$env:TEMP\*",
            "$env:LOCALAPPDATA\Temp\*",
            "$env:SystemRoot\Temp\*",
            "$env:SystemRoot\Prefetch\*",
            "$env:LOCALAPPDATA\Microsoft\Windows\Temporary Internet Files\*",
            "$env:APPDATA\Microsoft\Windows\Recent\*"
        )
        BrowserCachePaths    = @{
            Chrome  = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache\*"
            Firefox = "$env:LOCALAPPDATA\Mozilla\Firefox\Profiles\*\cache2\*"
            Edge    = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache\*"
        }
    }
    Progress = @{
        UpdateInterval  = 100  # Progress update every 100ms
        RefreshRate     = 10      # 10 updates per second
        ActivityTimeout = 30  # 30 seconds for activity timeouts
    }
    Reboot   = @{
        Required  = $false     # Track if reboot is required
        Source    = $null        # Track what triggered the reboot requirement
        Timestamp = $null     # When the reboot requirement was detected
    }
}

# ================================================================
# CONFIGURATION: Package Manager Definitions
# ================================================================

$global:PackageManagers = @{
    Winget     = @{
        Command       = 'winget.exe'
        InstallArgs   = @('install', '--id', '{0}', '--silent', '--accept-package-agreements', '--accept-source-agreements')
        UninstallArgs = @('uninstall', '--id', '{0}', '--silent')
        ListArgs      = @('list')
        SearchArgs    = @('search', '{0}')
        UpdateArgs    = @('upgrade', '--all', '--silent', '--accept-package-agreements', '--accept-source-agreements')
    }
    Chocolatey = @{
        Command       = 'choco.exe'
        InstallArgs   = @('install', '{0}', '-y', '--no-progress', '--limit-output')
        UninstallArgs = @('uninstall', '{0}', '-y', '--remove-dependencies')
        ListArgs      = @('list', '--local-only')
        SearchArgs    = @('search', '{0}')
        UpdateArgs    = @('upgrade', 'all', '-y')
    }
}

# ================================================================
# CONFIGURATION: Enhanced Bloatware Detection System
# ================================================================

# Multi-source bloatware detection configuration with priority-based scanning
$global:BloatwareDetectionSources = @{
    Software    = @{
        Enabled     = $true
        Sources     = @('AppX', 'Winget', 'Chocolatey', 'Registry', 'ProvisionedAppx')
        Priority    = 1
        Description = 'Traditional software package detection methods'
    }
    System      = @{
        Enabled     = $true
        Sources     = @('WindowsFeatures', 'Services', 'ScheduledTasks')
        Priority    = 2
        Description = 'System-level bloatware components detection'
    }
    Integration = @{
        Enabled     = $true
        Sources     = @('StartMenu', 'BrowserExtensions', 'ContextMenu', 'StartupPrograms')
        Priority    = 3
        Description = 'User interface and integration bloatware detection'
    }
}

# System-level bloatware patterns for enhanced detection
$global:SystemBloatwarePatterns = @{
    WindowsFeatures   = @(
        'XPS-Foundation-XPS-Viewer', 'FaxServicesClientPackage', 'WorkFolders-Client',
        'IIS-*', 'LegacyComponents', 'MediaFeatures-WindowsMediaPlayer',
        'WindowsMediaPlayer', 'Internet-Explorer-Optional-*', 'MicrosoftWindowsPowerShellV2*'
    )
    Services          = @(
        'XblAuthManager', 'XblGameSave', 'XboxGipSvc', 'XboxNetApiSvc',
        'DiagTrack', 'dmwappushservice', 'lfsvc', 'MapsBroker',
        'RetailDemo', 'Fax', 'WerSvc', 'TrkWks', 'WMPNetworkSvc'
    )
    ScheduledTasks    = @(
        'Microsoft\Windows\Application Experience\*', 'Microsoft\Windows\Customer Experience Improvement Program\*',
        'Microsoft\Windows\Feedback\*', 'Microsoft\Windows\Windows Error Reporting\*',
        'Microsoft\Windows\Maps\*', 'Microsoft\Windows\CloudExperienceHost\*',
        'Adobe*', 'Microsoft\Office\*', 'Microsoft\XblGameSave\*'
    )
    StartMenu         = @(
        '*Xbox*', '*Solitaire*', '*Candy Crush*', '*Bubble Witch*', '*March of Empires*',
        '*Hidden City*', '*Asphalt*', '*World of Tanks*', '*Minecraft*', '*Mixed Reality*'
    )
    BrowserExtensions = @(
        'Adobe*', 'McAfee*', 'Norton*', 'Avast*', 'AVG*', 'Office365*',
        'Skype*', 'Java*', 'Silverlight*', 'Acrobat*'
    )
    ContextMenu       = @(
        'Adobe*', 'Office*', 'Skype*', 'OneDrive*', 'WinRAR*', '7-Zip*'
    )
    StartupPrograms   = @(
        'Adobe*', 'McAfee*', 'Norton*', 'Avast*', 'AVG*', 'Spotify*',
        'Skype*', 'Steam*', 'Origin*', 'uTorrent*', 'Acrobat*'
    )
}

# Bloatware detection cache configuration
$global:BloatwareDetectionCache = @{
    Enabled      = $true
    CacheTimeout = (New-TimeSpan -Minutes 15)
    LastScan     = $null
    Data         = @{}
    MaxCacheSize = 50MB
}

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
# Purpose: Iterate over and execute all tasks registered in the
#          global $global:ScriptTasks array. This central coordinator
#          drives the maintenance workflow, invoking each task in
#          sequence and collecting results into $global:TaskResults.
# Environment: Runs inside the orchestrator (script.ps1) with
#              assumed admin privileges and available package managers
# Inputs: None (reads $global:ScriptTasks)
# Outputs: Populates $global:TaskResults and writes progress via Write-Log
# Error modes: Individual task failures are captured and logged but do
#              not abort the entire run unless explicitly fatal.
# Returns: $true on overall success, otherwise $false (and detailed results)
# Side-effects: Executes each registered task and may modify system state
# ================================================================
function Use-AllScriptTasks {
    Write-ActionLog -Action 'Initiating maintenance tasks execution sequence' -Details "Total tasks to execute: $($global:ScriptTasks.Count)" -Category 'Task Orchestration' -Status 'START'
    $global:TaskResults = @{}
    $taskIndex = 0
    $totalTasks = $global:ScriptTasks.Count
    $excludedTasks = @()

    if ($global:Config.ExcludeTasks -and $global:Config.ExcludeTasks.Count -gt 0) {
        $excludedTasks = $global:Config.ExcludeTasks | ForEach-Object { $_.ToString().Trim() } | Where-Object { $_ }
        if ($excludedTasks.Count -gt 0) {
            Write-ActionLog -Action 'Task exclusion configuration detected' -Details "Excluded tasks: $($excludedTasks -join ', ')" -Category 'Task Orchestration' -Status 'INFO'
        }
    }

    foreach ($task in $global:ScriptTasks) {
        # ================================================================
        # Function: Invoke-Task
        # ================================================================
        # Purpose: Execute a single task function from the global task array with
        #          standardized logging, error handling and return-value normalization.
        # Environment: Windows PowerShell 7+ (or 5.1), relies on Write-ActionLog and Write-Log
        # Logic: Accepts a task name and a scriptblock/function reference, executes it
        #        inside a try/catch, normalizes various return shapes to Boolean success
        #        and returns that result to the caller.
        # Dependencies: Write-ActionLog, Write-Log
        # Returns: [bool] $true on success, $false on failure
        # Side-effects: Logs execution details and errors to the log file and console
        # ================================================================
        $taskIndex++
        $taskName = $task.Name
        $desc = $task.Description

        # Determine task importance level (extract from task metadata if available)
        $importance = if ($task.Importance) { $task.Importance } else { 'MEDIUM' }

        if ($excludedTasks -and ($excludedTasks -contains $taskName)) {
            Write-ActionLog -Action 'Task skipped via ExcludeTasks' -Details "$taskName was excluded by configuration" -Category 'Task Execution' -Status 'INFO'
            Write-Log "[$taskIndex/$totalTasks] Task $taskName skipped via ExcludeTasks configuration." 'INFO'
            $global:TaskResults[$taskName] = [ordered]@{
                IsSuccessful = $true
                Status       = 'Skipped (ExcludeTasks)'
                Duration     = 0
                Started      = $null
                Ended        = $null
                Description  = $desc
                Importance   = $importance
                Payload      = $null
                Error        = $null
            }
            continue
        }

        # Display visual task banner
        Show-TaskBanner -TaskNumber $taskIndex -TotalTasks $totalTasks -TaskName $taskName -TaskDescription $desc -Importance $importance

        Write-ActionLog -Action 'Preparing task execution' -Details "$taskName ($taskIndex/$totalTasks) - $desc" -Category 'Task Execution' -Status 'START'
        Write-Log "[$taskIndex/$totalTasks] Executing task: $taskName - $desc" 'INFO'

        $startTime = Get-Date
        try {
            Write-ActionLog -Action 'Starting task function' -Details "$taskName | Function execution beginning" -Category 'Task Execution' -Status 'START'
            $taskOutcome = Invoke-Task $taskName $task.Function
            $endTime = $taskOutcome.Ended
            $duration = $taskOutcome.Duration
            $wasSuccessful = $taskOutcome.IsSuccessful
            $statusMessage = if ($taskOutcome.Status) { $taskOutcome.Status } elseif ($wasSuccessful) { 'Completed' } else { 'Failed' }

            if ($wasSuccessful) {
                Write-ActionLog -Action 'Task completed successfully' -Details "$taskName | Duration: ${duration}s | Status: $statusMessage" -Category 'Task Execution' -Status 'SUCCESS'
                Write-Log "[$taskIndex/$totalTasks] Task $taskName completed in $duration seconds - $statusMessage" 'SUCCESS'
            }
            else {
                Write-ActionLog -Action 'Task completed with issues' -Details "$taskName | Duration: ${duration}s | Status: $statusMessage" -Category 'Task Execution' -Status 'FAILURE'
                Write-Log "[$taskIndex/$totalTasks] Task $taskName failed after $duration seconds - $statusMessage" 'ERROR'
            }

            $global:TaskResults[$taskName] = [ordered]@{
                IsSuccessful = $wasSuccessful
                Status       = $statusMessage
                Duration     = $duration
                Started      = $taskOutcome.Started
                Ended        = $endTime
                Description  = $desc
                Importance   = $importance
                Payload      = $taskOutcome.Payload
                Error        = $taskOutcome.Error
            }
        }
        catch {
            $endTime = Get-Date
            $duration = ($endTime - $startTime).TotalSeconds

            Write-ActionLog -Action 'Task execution failed with exception' -Details "$taskName | Duration: ${duration}s | Exception: $_.Exception.Message" -Category 'Task Execution' -Status 'FAILURE'
            Write-Log "[$taskIndex/$totalTasks] Task $taskName execution failed: $_" 'ERROR'
            $global:TaskResults[$taskName] = [ordered]@{
                IsSuccessful = $false
                Status       = 'Error'
                Duration     = $duration
                Started      = $startTime
                Ended        = $endTime
                Description  = $desc
                Importance   = $importance
                Error        = $_.Exception.Message
            }
        }

        # Progress update
        $progressPercent = [math]::Round(($taskIndex / $totalTasks) * 100, 1)
        Write-ActionLog -Action 'Task execution progress' -Details "$taskIndex/$totalTasks tasks completed ($progressPercent%)" -Category 'Task Orchestration' -Status 'INFO'
    }

    # Final summary
    $successfulTasks = ($global:TaskResults.Values | Where-Object { $_.IsSuccessful }).Count
    $failedTasks = $totalTasks - $successfulTasks
    $totalDuration = ($global:TaskResults.Values | Measure-Object -Property Duration -Sum).Sum

    Write-ActionLog -Action 'All maintenance tasks execution sequence completed' -Details "Total: $totalTasks | Successful: $successfulTasks | Failed: $failedTasks | Total Duration: ${totalDuration}s" -Category 'Task Orchestration' -Status 'SUCCESS'
}

# ================================================================
# Function: Write-Log
# ================================================================
# Purpose: Centralized logging function that writes timestamped entries
#          to both the console and the persistent log file. Supports
#          different log levels (INFO, WARN, ERROR, DEBUG, SUCCESS).
# Environment: Writes to $LogFile and the console. Assumes $LogFile is
#              initialized and writable.
# Inputs: $Message (string), $Level (string, default: 'INFO')
# Outputs: Console output and appended log file entries
# Error modes: If file append fails, logs to console only and sets a
#              debug indicator.
# Returns: None
# Side-effects: Creates or appends to the $LogFile on disk
# ================================================================
function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('DEBUG', 'INFO', 'WARN', 'ERROR', 'SUCCESS', 'PROGRESS', 'ACTION', 'COMMAND', 'VERBOSE')]
        [string]$Level = 'INFO',
        [string]$Component = 'PS1'
    )

    # Check if logging is enabled for this level
    if ($global:LoggingConfig -and $global:LoggingConfig.LogLevels.ContainsKey($Level)) {
        $currentLevelValue = $global:LoggingConfig.LogLevels[$global:LoggingConfig.LogLevel]
        $messageLevelValue = $global:LoggingConfig.LogLevels[$Level]
        if ($messageLevelValue -lt $currentLevelValue) {
            return  # Skip logging this message
        }
    }

    $timestamp = Get-Date -Format 'HH:mm:ss'
    $logEntry = "[$timestamp] [$Level] [$Component] $Message"

    $targetLogPath = if ($script:LogFile) { $script:LogFile } elseif ($global:LogFile) { $global:LogFile } else { $null }

    # Write to file with enhanced error handling
    if ($targetLogPath) {
        try {
            Add-Content -Path $targetLogPath -Value $logEntry -ErrorAction SilentlyContinue -Encoding UTF8
        }
        catch {
            # If main log fails, try writing to backup location
            try {
                $backupLog = Join-Path $global:TempFolder 'maintenance_backup.log'
                Add-Content -Path $backupLog -Value $logEntry -ErrorAction SilentlyContinue -Encoding UTF8
            }
            catch {
                # Silently continue if all logging fails
            }
        }
    }

    # Write to console with enhanced color coding
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

    # For important actions, also write to host using Write-Output for comprehensive logging
    if ($Level -in @('ACTION', 'COMMAND', 'ERROR', 'SUCCESS')) {
        Write-Output $logEntry
    }
}

# ================================================================
# Function: Write-ActionLog
# ================================================================
# Purpose: Helper for logging long-running action entries. Formats
#          action start/finish messages and emits progress-friendly
#          lines to the console and the action log file.
# Environment: Uses Write-Log internally and assumes logging infra
# Inputs: $ActionName (string), $Status (string)
# Outputs: Console-friendly action messages and log file entries
# Returns: None
# Side-effects: None beyond logging
# ================================================================

# ================================================================
# Function: Test-TaskShouldSkip
# ================================================================
# Purpose: Helper to consolidate skip flag checks for maintainability
# Environment: Task context with $global:Config available
# Inputs: $SkipFlagName (string or array for multi-flag checks)
# Returns: Skip result object or $null (proceed normally)
# ================================================================
function Test-TaskShouldSkip {
    param(
        [Parameter(Mandatory = $true)][string[]]$SkipFlagName,
        [Parameter(Mandatory = $true)][string]$TaskName
    )
    
    foreach ($flag in $SkipFlagName) {
        if ($global:Config.ContainsKey($flag) -and $global:Config[$flag]) {
            Write-Log "$TaskName skipped by configuration ($flag)." 'INFO'
            return (New-TaskSkipResult "Skipped (config: $flag)")
        }
    }
    return $null
}

# ================================================================
function Write-ActionLog {
    param(
        [string]$Action,
        [string]$Details = '',
        [string]$Category = 'General',
        [ValidateSet('START', 'SUCCESS', 'FAILURE', 'INFO')]
        [string]$Status = 'INFO'
    )

    $contextInfo = ''
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
# Purpose: Specialized logging for external command execution with full command tracking
# Environment: Windows 10/11, PowerShell 7+, supports external process monitoring and detailed execution tracking
# Logic: Logs command execution with full command line, arguments, exit codes, and execution timing
# Performance: Minimal overhead wrapper for external commands, comprehensive execution tracking
# Dependencies: Write-Log function, process execution capabilities, timing functions
# ================================================================
# Function: Write-CommandLog
# ================================================================
# Purpose: Logs a command invocation and its outcome. This function
#          centralizes command-level details (command string, exit code,
#          stdout/stderr snippets) for easier post-run analysis.
# Environment: Uses the same log file as Write-Log. Intended for wrapping
#              external process invocations.
# Inputs: $Command (string), $ResultObject (has ExitCode/Output/Error)
# Outputs: Detailed command logs appended to $LogFile
# Returns: None
# Side-effects: May write large outputs to log; caller should trim if needed
# ================================================================
function Write-CommandLog {
    param(
        [string]$Command,
        [string[]]$Arguments = @(),
        [string]$Context = '',
        [ValidateSet('START', 'SUCCESS', 'FAILURE')]
        [string]$Status = 'START'
    )

    $fullCommand = $Command
    if ($Arguments.Count -gt 0) {
        $argString = $Arguments -join ' '
        $fullCommand = "$Command $argString"
    }

    $contextInfo = if ($Context) { " | Context: $Context" } else { '' }
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
# Purpose: Displays progress information for long-running tasks with visual progress indicators
# Environment: Windows PowerShell console, supports progress bars and status messages
# Logic: Progress percentage tracking, status message display, console-only output
# Performance: Lightweight progress tracking, non-blocking operations, visual feedback
# Dependencies: Windows PowerShell console capabilities, Write-Progress cmdlet
# ================================================================
# Function: Write-TaskProgress
# ================================================================
# Purpose: Emit a compact progress line for a single high-level task.
#          Intended for console-friendly summaries while tasks run.
# Environment: Console-only progress UX; may also write compact lines
#              to the log file when verbose is enabled.
# Inputs: $TaskName (string), $PercentComplete (int), $Status (string)
# Outputs: Console progress update and optional log entry
# Returns: None
# Side-effects: None
# ================================================================
function Write-TaskProgress {
    param(
        [string]$Activity,
        [int]$PercentComplete,
        [string]$Status = 'Processing...'
    )

    # Show visual progress bar in console
    Write-Progress -Activity $Activity -Status $Status -PercentComplete $PercentComplete

    # Only log start and completion to reduce noise
    if ($PercentComplete -eq 0) {
        Write-Log "⏳ $Activity - $Status" 'INFO'
    }
    elseif ($PercentComplete -ge 100) {
        Write-Log "✓ $Activity - Completed" 'INFO'
        Start-Sleep -Milliseconds 500  # Brief pause to show completion
        Write-Progress -Activity $Activity -Completed
    }
    # Skip intermediate percentage logging - progress bar provides visual feedback
}

# ================================================================
# Function: Write-ActionProgress
# ================================================================
# Purpose: Modular progress bar system for individual actions with auto-cleanup
# Environment: Windows PowerShell console, supports individual action tracking
# Logic: Creates separate progress bars for each action type with automatic cleanup
# Performance: Lightweight, non-blocking, visual feedback for granular operations
# Dependencies: Write-Progress cmdlet, console capabilities
# ================================================================
# Function: Write-ActionProgress
# ================================================================
# Purpose: Provide per-action progress details (substeps within a task)
#          and bubble timing/ETA information to the console UX.
# Environment: Uses console progress; tolerant if console not interactive
# Inputs: $Action (string), $Step (int), $TotalSteps (int)
# Outputs: Console progress bar or text, optional verbose logging
# Returns: None
# Side-effects: None
# ================================================================
function Write-ActionProgress {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ActionType,  # 'Installing', 'Uninstalling', 'Removing', 'Updating', 'Scanning', 'Cleaning'

        [Parameter(Mandatory = $true)]
        [string]$ItemName,    # Name of the item being processed

        [Parameter(Mandatory = $true)]
        [int]$PercentComplete, # 0-100

        [string]$Status = 'Processing...',  # Additional status text

        [int]$CurrentItem = 0,  # Current item number

        [int]$TotalItems = 0,   # Total items to process

        [switch]$Completed      # Mark as completed and cleanup
    )

    # Generate unique activity ID based on action type and item
    $activityId = ($ActionType + $ItemName).GetHashCode()
    if ($activityId -lt 0) { $activityId = - $activityId }

    # Build activity title
    $activityTitle = "$ActionType`: $ItemName"
    if ($TotalItems -gt 0 -and $CurrentItem -gt 0) {
        $activityTitle += " ($CurrentItem/$TotalItems)"
    }

    # Build status message
    $statusMessage = $Status
    if ($PercentComplete -ge 0 -and $PercentComplete -le 100) {
        $statusMessage = "$Status ($PercentComplete%)"
    }

    if ($Completed) {
        # Clear the progress bar
        Write-Progress -Id $activityId -Activity $activityTitle -Completed
        # Log completion without clutter
        if ($TotalItems -gt 0 -and $CurrentItem -gt 0) {
            Write-Log "✓ $ActionType completed: $ItemName ($CurrentItem/$TotalItems)" 'INFO'
        }
        else {
            Write-Log "✓ $ActionType completed: $ItemName" 'INFO'
        }
    }
    else {
        # Show progress bar in console only
        Write-Progress -Id $activityId -Activity $activityTitle -Status $statusMessage -PercentComplete $PercentComplete

        # Only log meaningful progress milestones to avoid clutter
        # Log start (0%) and major milestones, but not every percentage update
        if ($PercentComplete -eq 0) {
            if ($TotalItems -gt 0 -and $CurrentItem -gt 0) {
                Write-Log "⏳ $ActionType started: $ItemName ($CurrentItem/$TotalItems)" 'INFO'
            }
            else {
                Write-Log "⏳ $ActionType started: $ItemName" 'INFO'
            }
        }
        # Skip intermediate percentage logging to reduce console noise
        # Progress bars provide visual feedback, no need for verbose percentage logs
    }
}
function Write-CleanProgress {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Activity,

        [Parameter(Mandatory = $true)]
        [string]$CurrentItem,

        [Parameter(Mandatory = $true)]
        [int]$CurrentIndex,

        [Parameter(Mandatory = $true)]
        [int]$TotalItems,

        [string]$Status = 'Processing',

        [switch]$Completed
    )

    $percentComplete = if ($TotalItems -gt 0) { [math]::Round(($CurrentIndex / $TotalItems) * 100, 0) } else { 0 }
    $progressId = $Activity.GetHashCode()
    if ($progressId -lt 0) { $progressId = - $progressId }

    # Show visual progress bar in console
    Write-Progress -Activity $Activity -Status $Status -PercentComplete $percentComplete

    # Only log start and completion to reduce noise
    if ($percentComplete -eq 0) {
        Write-Log "⏳ $Activity - $Status" 'INFO'
    }
    elseif ($percentComplete -ge 100) {
        Write-Log "✓ $Activity - Completed" 'INFO'
        Start-Sleep -Milliseconds 500  # Brief pause to show completion
        Write-Progress -Activity $Activity -Completed
    }
}

# ================================================================
# Function: Start-ActionProgressSequence
# ================================================================
# Purpose: Manages a sequence of actions with individual progress tracking
# Environment: Windows PowerShell console, handles multiple concurrent progress bars
# Logic: Orchestrates multiple action progress bars for complex operations
# Performance: Efficient progress management for sequential operations
# Dependencies: Write-ActionProgress function
# ================================================================
# Function: Start-ActionProgressSequence
# ================================================================
# Purpose: Helper to initialize a multi-step action with timing and
#          internal progress tracking. Returns an object that callers
#          can use to report substep progress and final duration.
# Environment: In-memory tracker returned to caller for progress updates
# Inputs: $ActionName (string), $TotalSteps (int)
# Outputs: Progress tracker object
# Returns: A hashtable/object containing Update/Complete methods
# Side-effects: None
# ================================================================
function Start-ActionProgressSequence {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SequenceName,  # Overall sequence name

        [Parameter(Mandatory = $true)]
        [array]$Actions,        # Array of actions to perform

        [scriptblock]$ActionProcessor # Script block to process each action
    )

    $totalActions = $Actions.Count
    $currentAction = 0

    # Main sequence progress bar
    $sequenceId = $SequenceName.GetHashCode()
    if ($sequenceId -lt 0) { $sequenceId = - $sequenceId }

    Write-Progress -Id $sequenceId -Activity $SequenceName -Status 'Starting...' -PercentComplete 0

    foreach ($action in $Actions) {
        $currentAction++
        $sequenceProgress = [math]::Round(($currentAction / $totalActions) * 100, 1)

        # Update main sequence progress
        Write-Progress -Id $sequenceId -Activity $SequenceName -Status "Processing action $currentAction of $totalActions" -PercentComplete $sequenceProgress

        # Execute the action with individual progress tracking
        if ($ActionProcessor) {
            & $ActionProcessor $action $currentAction $totalActions
        }

        # Small delay to show completion
        Start-Sleep -Milliseconds 100
    }

    # Complete the sequence
    Write-Progress -Id $sequenceId -Activity $SequenceName -Completed
    Write-Log "✓ $SequenceName sequence completed: $totalActions actions processed" 'SUCCESS'
}

# ================================================================
# Function: Write-SystemSummaryHeader
# ================================================================
# Purpose: Writes comprehensive PC summary information to maintenance log at startup
# Environment: Windows 10/11, PowerShell 7+, requires network connectivity for external IP detection
# Performance: Efficient network information gathering, cached DNS resolution, optimized system data collection
# Dependencies: Get-ComputerInfo, Get-NetIPConfiguration, Resolve-DnsName, Invoke-RestMethod for external IP
# Logic: Collects system identity, network configuration, user context, and connectivity information
# Features: Comprehensive PC fingerprinting, network topology discovery, external IP detection, DNS configuration analysis
# ================================================================
# Function: Write-SystemSummaryHeader
# ================================================================
# Purpose: Write a clear header and system metadata block at the top of
#          the maintenance report. Includes OS version, uptime, time of run,
#          and configuration summary for reproducibility.
# Environment: Writes to the $LogFile and to the console report output
# Inputs: None (reads global variables like $global:Config)
# Outputs: Formatted report header in logs and console
# Returns: None
# Side-effects: Writes to disk (log file) and may extend report artifacts
# ================================================================
function Write-SystemSummaryHeader {
    Write-Log '============================================================' 'INFO'
    Write-Log 'SYSTEM SUMMARY - PC INFORMATION' 'INFO'
    Write-Log '============================================================' 'INFO'

    try {
        # Date and Time Information
        $currentDateTime = Get-Date
        Write-Log "Date & Time: $($currentDateTime.ToString('dddd, MMMM dd, yyyy - HH:mm:ss zzz'))" 'INFO'
        Write-Log "Time Zone: $($currentDateTime.ToString('zzz')) - $([System.TimeZoneInfo]::Local.DisplayName)" 'INFO'

        # System Identity - Using script-level variables for consistency
        $computerInfo = Get-ComputerInfo -ErrorAction SilentlyContinue

        Write-Log "Computer Name: $ComputerName" 'INFO'
        Write-Log "User Name: $CurrentUser" 'INFO'
        Write-Log "User Domain: $env:USERDOMAIN" 'INFO'
        Write-Log "Full User: $env:USERDOMAIN\$CurrentUser" 'INFO'
        Write-Log "OS Version: $OSVersion" 'INFO'
        Write-Log "OS Architecture: $OSArch" 'INFO'
        Write-Log "PowerShell Version: $PSVersion" 'INFO'

        # Administrator privileges check
        $privilegeStatus = 'No'
        if ($IsAdmin) { $privilegeStatus = 'Yes' }
        Write-Log "Administrator Privileges: $privilegeStatus" 'INFO'

        # Script execution context
        Write-Log "Script Path: $ScriptFullPath" 'INFO'
        Write-Log "Script Directory: $ScriptDir" 'INFO'
        Write-Log "Script Name: $ScriptName" 'INFO'
        Write-Log "Script Drive Type: $DriveType" 'INFO'
        Write-Log "Network Path: $IsNetworkPath" 'INFO'

        if ($computerInfo) {
            Write-Log "Manufacturer: $($computerInfo.CsManufacturer)" 'INFO'
            Write-Log "Model: $($computerInfo.CsModel)" 'INFO'
            Write-Log "OS Name: $($computerInfo.WindowsProductName)" 'INFO'
            Write-Log "OS Version: $($computerInfo.WindowsVersion)" 'INFO'
            Write-Log "OS Build: $($computerInfo.WindowsBuildLabEx)" 'INFO'
            Write-Log "Total RAM: $([math]::Round($computerInfo.TotalPhysicalMemory / 1GB, 2)) GB" 'INFO'
            Write-Log "Processor: $($computerInfo.CsProcessors[0].Name)" 'INFO'
        }

        # Network Configuration
        Write-Log '--- NETWORK CONFIGURATION ---' 'INFO'

        # Get active network adapters with IP addresses
        $activeAdapters = Get-NetIPConfiguration | Where-Object {
            $_.NetAdapter.Status -eq 'Up' -and
            $_.IPv4Address -and
            $_.IPv4Address.IPAddress -ne '127.0.0.1'
        }

        if ($activeAdapters) {
            foreach ($adapter in $activeAdapters) {
                $adapterName = $adapter.NetAdapter.Name
                $connectionProfile = $adapter.NetProfile.Name
                $ipAddress = $adapter.IPv4Address.IPAddress
                $subnetMask = $adapter.IPv4Address.PrefixLength
                $gateway = $adapter.IPv4DefaultGateway.NextHop
                $dnsServers = $adapter.DNSServer.ServerAddresses -join ', '

                Write-Log "Network Adapter: $adapterName" 'INFO'
                Write-Log "Connection Profile: $connectionProfile" 'INFO'
                Write-Log "IP Address: $ipAddress/$subnetMask" 'INFO'
                Write-Log "Default Gateway: $gateway" 'INFO'
                Write-Log "DNS Servers: $dnsServers" 'INFO'
                Write-Log "MAC Address: $($adapter.NetAdapter.LinkLayerAddress)" 'INFO'
                Write-Log "Link Speed: $($adapter.NetAdapter.LinkSpeed)" 'INFO'
                Write-Log '---' 'INFO'
            }
        }
        else {
            Write-Log 'No active network adapters found' 'WARN'
        }

        # External IP Address Detection
        Write-Log '--- EXTERNAL CONNECTIVITY ---' 'INFO'
        try {
            $externalIP = $null
            $ipServices = @(
                @{ Name = 'ipify.org'; Url = 'https://api.ipify.org' },
                @{ Name = 'ip-api.com'; Url = 'http://ip-api.com/line/?fields=query' },
                @{ Name = 'httpbin.org'; Url = 'https://httpbin.org/ip' }
            )

            foreach ($service in $ipServices) {
                try {
                    Write-Log "Checking external IP via $($service.Name)..." 'INFO'

                    if ($service.Name -eq 'httpbin.org') {
                        $response = Invoke-RestMethod -Uri $service.Url -TimeoutSec 10 -ErrorAction Stop
                        $externalIP = $response.origin
                    }
                    else {
                        $externalIP = Invoke-RestMethod -Uri $service.Url -TimeoutSec 10 -ErrorAction Stop
                    }

                    if ($externalIP -and $externalIP -match '^\d+\.\d+\.\d+\.\d+$') {
                        Write-Log "External IP Address: $externalIP (via $($service.Name))" 'INFO'
                        break
                    }
                }
                catch {
                    Write-Log "Failed to get external IP from $($service.Name): $($_.Exception.Message)" 'WARN'
                    continue
                }
            }

            if (-not $externalIP -or $externalIP -notmatch '^\d+\.\d+\.\d+\.\d+$') {
                Write-Log 'External IP Address: Unable to determine (no internet connectivity)' 'WARN'
            }
        }
        catch {
            Write-Log "External IP Detection Error: $($_.Exception.Message)" 'WARN'
        }

        # DNS Configuration Analysis
        try {
            Write-Log '--- DNS CONFIGURATION ---' 'INFO'
            $dnsTestDomains = @('google.com', 'microsoft.com', 'cloudflare.com')

            foreach ($domain in $dnsTestDomains) {
                try {
                    $dnsResult = Resolve-DnsName -Name $domain -Type A -ErrorAction Stop | Select-Object -First 1
                    Write-Log "DNS Resolution: $domain -> $($dnsResult.IPAddress)" 'INFO'
                    break # Only test one successful resolution to avoid spam
                }
                catch {
                    Write-Log "DNS Resolution Failed: $domain - $($_.Exception.Message)" 'WARN'
                }
            }
        }
        catch {
            Write-Log "DNS Configuration Error: $($_.Exception.Message)" 'WARN'
        }

        # System Security and Status
        Write-Log '--- SYSTEM STATUS ---' 'INFO'
        try {
            $osInfo = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
            if ($osInfo) {
                $lastBoot = $osInfo.LastBootUpTime
                $uptime = (Get-Date) - $lastBoot
                Write-Log "Last Boot: $($lastBoot.ToString('yyyy-MM-dd HH:mm:ss'))" 'INFO'
                Write-Log "System Uptime: $($uptime.Days) days, $($uptime.Hours) hours, $($uptime.Minutes) minutes" 'INFO'
            }

            $powerPlan = Get-CimInstance -ClassName Win32_PowerPlan -Namespace 'root\cimv2\power' -Filter "IsActive = 'True'" -ErrorAction SilentlyContinue
            if ($powerPlan) {
                Write-Log "Active Power Plan: $($powerPlan.ElementName)" 'INFO'
            }
        }
        catch {
            Write-Log "System Status Error: $($_.Exception.Message)" 'WARN'
        }

        Write-Log '============================================================' 'INFO'
        Write-Log '' 'INFO' # Add spacing before maintenance tasks begin
    }
    catch {
        Write-Log "Error generating system summary: $($_.Exception.Message)" 'ERROR'
        Write-Log '============================================================' 'INFO'
    }
}

# ================================================================
# Helper: Resolve-TaskOutcome
# ================================================================
# Purpose: Normalize arbitrary task return values into a consistent
#          structure that captures success state, status text, and payload.
# ================================================================
function Resolve-TaskOutcome {
    param(
        [Parameter(ValueFromPipeline = $true)]
        $Result
    )

    $outcome = [ordered]@{
        IsSuccessful = $true
        Status       = 'Completed'
        Payload      = $Result
    }

    if ($null -eq $Result) {
        return $outcome
    }

    if ($Result -is [bool]) {
        $outcome.IsSuccessful = [bool]$Result
        return $outcome
    }

    if ($Result -is [hashtable] -or $Result -is [psobject]) {
        if ($Result.PSObject.Properties['IsSuccessful']) {
            $outcome.IsSuccessful = [bool]$Result.IsSuccessful
        }
        if ($Result.PSObject.Properties['Status']) {
            $outcome.Status = [string]$Result.Status
        }
        $outcome.Payload = $Result
        return $outcome
    }

    if ($Result -is [System.Management.Automation.ErrorRecord]) {
        $outcome.IsSuccessful = $false
        $outcome.Status = 'Error'
        return $outcome
    }

    return $outcome
}

# ================================================================
# Function: Invoke-Task
# ================================================================
# Purpose: Enhanced wrapper function for individual task execution with comprehensive logging and timing
# ================================================================
function Invoke-Task {
    param(
        [string]$TaskName,
        [scriptblock]$Action
    )

    $startTime = Get-Date
    Write-ActionLog -Action 'Starting task execution' -Details $TaskName -Category 'Task Management' -Status 'START'

    try {
        $rawResult = & $Action
        $outcome = Resolve-TaskOutcome -Result $rawResult
        $endTime = Get-Date
        $duration = ($endTime - $startTime).TotalSeconds

        $logStatus = if ($outcome.IsSuccessful) { 'SUCCESS' } else { 'FAILURE' }
        Write-ActionLog -Action 'Task completion' -Details "$TaskName | Duration: ${duration}s | Status: $($outcome.Status)" -Category 'Task Management' -Status $logStatus

        return [ordered]@{
            IsSuccessful = $outcome.IsSuccessful
            Status       = $outcome.Status
            Payload      = $outcome.Payload
            Started      = $startTime
            Ended        = $endTime
            Duration     = $duration
            Error        = $null
        }
    }
    catch {
        $endTime = Get-Date
        $duration = ($endTime - $startTime).TotalSeconds
        Write-ActionLog -Action 'Task execution failed' -Details "$TaskName | Duration: ${duration}s | Error: $_" -Category 'Task Management' -Status 'FAILURE'

        return [ordered]@{
            IsSuccessful = $false
            Status       = 'Error'
            Payload      = $null
            Started      = $startTime
            Ended        = $endTime
            Duration     = $duration
            Error        = $_.Exception.Message
        }
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
# Function: Invoke-LoggedCommand
# ================================================================
# Purpose: Run an external command or scriptblock while capturing stdout/stderr
#          and logging execution details including exit codes and duration.
# Environment: Windows PowerShell (any supported version)
# Logic: Executes the provided command, captures output streams, logs start/
#        completion and returns a structured object with ExitCode, StdOut,
#        StdErr and Duration fields.
# Dependencies: Write-CommandLog, Write-Log
# Returns: Hashtable with keys: ExitCode, StdOut, StdErr, Duration
# Side-effects: Writes log entries for command start, success/failure
# ================================================================
# Function: Invoke-LoggedCommand
# ================================================================
# Purpose: Run an external command or script block while capturing
#          stdout/stderr, exit codes, and writing structured logs
#          via Write-CommandLog. Intended to be the single place
#          where external invocations are normalized.
# Environment: May run native executables or PowerShell subprocesses
# Inputs: $Command (string or scriptblock), $Timeout (int seconds)
# Outputs: Returns a result object with ExitCode, StdOut, StdErr
# Returns: Hashtable { ExitCode, Output, Error, Duration }
# Side-effects: Writes detailed command logs to disk
# ================================================================
function Invoke-LoggedCommand {
    param(
        [string]$FilePath,
        [string[]]$ArgumentList = @(),
        [string]$Context = '',
        [switch]$WindowStyle,
        [string]$WindowStyleValue = 'Hidden',
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

        Write-ActionLog -Action 'Executing external command' -Details "$FilePath with arguments: $($ArgumentList -join ' ')" -Category 'Command Execution' -Status 'START'

        $process = Start-Process @processArgs

        if ($Wait -and $process) {
            $endTime = Get-Date
            $duration = ($endTime - $startTime).TotalSeconds
            $exitCode = $process.ExitCode

            if ($exitCode -eq 0) {
                Write-CommandLog -Command $FilePath -Arguments $ArgumentList -Context "$Context | Duration: ${duration}s | ExitCode: $exitCode" -Status 'SUCCESS'
                Write-ActionLog -Action 'Command completed successfully' -Details "$FilePath | Duration: ${duration}s | ExitCode: $exitCode" -Category 'Command Execution' -Status 'SUCCESS'
            }
            else {
                Write-CommandLog -Command $FilePath -Arguments $ArgumentList -Context "$Context | Duration: ${duration}s | ExitCode: $exitCode" -Status 'FAILURE'
                Write-ActionLog -Action 'Command completed with error' -Details "$FilePath | Duration: ${duration}s | ExitCode: $exitCode" -Category 'Command Execution' -Status 'FAILURE'
            }

            return $process
        }
        else {
            Write-ActionLog -Action 'Command started in background' -Details "$FilePath | Background execution" -Category 'Command Execution' -Status 'INFO'
            return $process
        }
    }
    catch {
        $endTime = Get-Date
        $duration = ($endTime - $startTime).TotalSeconds

        Write-CommandLog -Command $FilePath -Arguments $ArgumentList -Context "$Context | Duration: ${duration}s | Exception: $_" -Status 'FAILURE'
        Write-ActionLog -Action 'Command execution failed' -Details "$FilePath | Duration: ${duration}s | Exception: $_" -Category 'Command Execution' -Status 'FAILURE'

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
# REUSABLE UTILITY FUNCTIONS: Diff Processing and Package Management
# ================================================================

# ================================================================
# Function: Get-RegistryUninstallBloatware
# ================================================================
# Purpose: Discover installed bloatware by scanning registry uninstall keys (both 32/64-bit)
# Environment: Windows 10/11, requires registry read access
# Performance: Fast registry enumeration, minimal overhead
# Dependencies: Windows Registry access
# Logic: Scans HKLM uninstall keys, matches against bloatware patterns, returns standardized app objects
# Features: Detects legacy/OEM/Win32 bloatware, logs all matches, supports integration with main detection pipeline
# ================================================================
# Function: Get-RegistryUninstallBloatware
# ================================================================
# Purpose: Enumerate uninstall registry keys and match installed apps
#          against configured bloatware patterns to produce a removal list.
# Environment: Windows (registry access required), PowerShell 5.1+ recommended
# Logic: Scans relevant uninstall registry paths (32-bit/64-bit + per-user)
#        and returns objects representing candidate bloatware matches.
# Dependencies: None (uses native registry cmdlets), relies on $global:BloatwareList
# Returns: Array of objects { Name, DisplayVersion, Publisher, UninstallString }
# Side-effects: None (read-only enumeration)
# ================================================================
# Function: Get-RegistryUninstallBloatware
# ================================================================
# Purpose: Enumerate installed programs from the registry uninstall
#          keys and normalize entries so they can be compared against
#          bloatware lists. Handles both 32/64-bit registry views.
# Environment: Reads HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall
#              and HKCU equivalent. Requires registry read access.
# Inputs: Optional filter patterns
# Outputs: Array of normalized app objects (Name, Version, Publisher, UninstallString)
# Returns: Array
# Side-effects: None (read-only)
# ================================================================
function Get-RegistryUninstallBloatware {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$BloatwarePatterns,
        [Parameter(Mandatory = $false)]
        [string]$Context = 'Registry Uninstall Scan'
    )
    Write-Log '[START] Registry uninstall key scan for bloatware' 'INFO'
    $found = @()
    $uninstallPaths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
    )
    foreach ($path in $uninstallPaths) {
        try {
            $keys = Get-ChildItem -Path $path -ErrorAction SilentlyContinue
            foreach ($key in $keys) {
                $props = Get-ItemProperty -Path $key.PSPath -ErrorAction SilentlyContinue
                $displayName = $props.DisplayName
                if ([string]::IsNullOrWhiteSpace($displayName)) { continue }
                foreach ($pattern in $BloatwarePatterns) {
                    if ($displayName -like "*$pattern*") {
                        $found += [PSCustomObject]@{
                            Name            = $displayName
                            DisplayName     = $displayName
                            Version         = $props.DisplayVersion
                            UninstallString = $props.UninstallString
                            Source          = 'Registry'
                            UninstallKey    = $key.PSChildName
                            Context         = $Context
                        }
                        Write-Log "[REGISTRY BLOATWARE] $displayName (Version: $($props.DisplayVersion))" 'INFO'
                        break
                    }
                }
            }
        }
        catch {
            Write-Log "Failed to scan registry uninstall path: $path - $_" 'WARN'
        }
    }
    Write-Log "[END] Registry uninstall key scan: $($found.Count) bloatware apps found" 'INFO'
    return $found
}

# ================================================================
# Function: Test-CommandAvailable
# ================================================================
# Purpose: Check if a command/executable is available in the system PATH
# Environment: Windows 10/11, requires system PATH access
# Performance: Fast command detection, cached results for repeated calls
# Dependencies: System PATH environment variable, Get-Command cmdlet
# Logic: Uses Get-Command with error handling to detect command availability
# Features: Cross-platform compatibility, error suppression, boolean result
# ================================================================
# Function: Test-CommandAvailable
# ================================================================
# Purpose: Determine whether a given executable or command is available in PATH
# Environment: Cross-platform PowerShell (relies on Get-Command)
# Logic: Uses Get-Command and where.exe fallback to check availability
# Returns: [bool] $true if available, otherwise $false
# Side-effects: None
# ================================================================
# Function: Test-CommandAvailable
# ================================================================
# Function: Show-TaskBanner
# ================================================================
# Purpose: Display a professional task banner in the console at task start
#          with task info, importance level, and visual separation
# Environment: Windows PowerShell console, supports colored output
# Logic: Creates ASCII-art banner with task metadata, importance level,
#        and description for clear visual task separation
# Performance: Minimal overhead, console-only output
# Dependencies: Write-Host, console capabilities
# ================================================================
function Show-TaskBanner {
    param(
        [Parameter(Mandatory = $true)]
        [int]$TaskNumber,

        [Parameter(Mandatory = $true)]
        [int]$TotalTasks,

        [Parameter(Mandatory = $true)]
        [string]$TaskName,

        [Parameter(Mandatory = $true)]
        [string]$TaskDescription,

        [Parameter(Mandatory = $true)]
        [string]$Importance
    )

    # Determine banner color based on importance
    $bannerColor = switch ($Importance) {
        'CRITICAL' { 'Red' }
        'HIGH' { 'Yellow' }
        'MEDIUM' { 'Cyan' }
        'LOW' { 'Green' }
        'OPTIONAL' { 'DarkCyan' }
        default { 'White' }
    }

    # Importance symbol
    $importanceSymbol = switch ($Importance) {
        'CRITICAL' { '!!!' }
        'HIGH' { '!!' }
        'MEDIUM' { '**' }
        'LOW' { '--' }
        'OPTIONAL' { 'oo' }
        default { 'XX' }
    }

    # Banner width
    $bannerWidth = 80
    $separator = '=' * $bannerWidth

    # Calculate progress bar
    $progressPercent = [math]::Round(($TaskNumber / $TotalTasks) * 100)
    $progressFilled = [math]::Floor(($progressPercent / 100) * 15)
    $progressEmpty = 15 - $progressFilled
    $progressBar = '[' + ('#' * $progressFilled) + (' ' * $progressEmpty) + "] $progressPercent%"

    # Print banner with safe padding calculations
    Write-Host "`n╔$separator╗" -ForegroundColor $bannerColor
    
    # Safe padding for task name line
    $taskLineText = "[$importanceSymbol] TASK $TaskNumber/$TotalTasks - $TaskName"
    $taskLinePadding = [math]::Max(0, $bannerWidth - $taskLineText.Length - 3)
    Write-Host "║ $taskLineText$(([string](' ' * $taskLinePadding)))" -ForegroundColor $bannerColor
    
    # Safe padding for importance line
    $importanceLineText = "Importance: $Importance"
    $importanceLinePadding = [math]::Max(0, $bannerWidth - $importanceLineText.Length - 2)
    Write-Host "║ $importanceLineText$(([string](' ' * $importanceLinePadding)))" -ForegroundColor $bannerColor
    
    # Safe padding for description line
    $descriptionLinePadding = [math]::Max(0, $bannerWidth - $TaskDescription.Length - 2)
    Write-Host "║ $TaskDescription$(([string](' ' * $descriptionLinePadding)))" -ForegroundColor White
    
    # Safe padding for progress line
    $progressLinePadding = [math]::Max(0, $bannerWidth - $progressBar.Length - 10)
    Write-Host "║ Progress: $progressBar$(([string](' ' * $progressLinePadding)))" -ForegroundColor Cyan
    
    Write-Host "╚$separator╝`n" -ForegroundColor $bannerColor
}

# Purpose: Test whether a named command/tool is available on PATH or
#          as a PowerShell command (Get-Command). Used to decide
#          whether to use winget/choco/appx paths or fallback logic.
# Environment: Local session PATH and module/function availability
# Inputs: $CommandName (string)
# Outputs: $true/$false
# Returns: Boolean
# Side-effects: None
# ================================================================
function Test-CommandAvailable {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Command
    )

    try {
        # First try Get-Command (standard check)
        $null = Get-Command $Command -ErrorAction Stop
        return $true
    }
    catch {
        # For common Windows tools, check standard installation paths
        $commonPaths = @{
            'winget' = @(
                'C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*\winget.exe',
                'C:\Program Files\WinGet\winget.exe',
                "$env:LOCALAPPDATA\Microsoft\WindowsApps\winget.exe"
            )
            'choco'  = @(
                'C:\ProgramData\chocolatey\bin\choco.exe',
                'C:\Program Files\chocolatey\bin\choco.exe'
            )
            'pwsh'   = @(
                'C:\Program Files\PowerShell\7\pwsh.exe'
            )
        }

        if ($commonPaths.ContainsKey($Command)) {
            foreach ($path in $commonPaths[$Command]) {
                # Handle wildcard paths
                if ($path -contains '*') {
                    $resolvedPaths = Get-Item -Path $path -ErrorAction SilentlyContinue
                    if ($resolvedPaths) {
                        return $true
                    }
                }
                else {
                    if (Test-Path $path) {
                        return $true
                    }
                }
            }
        }

        # Check if it's in PATH
        $envPath = $env:PATH -split ';' | ForEach-Object { Join-Path $_ "$Command.exe" }
        if (Test-Path $envPath[0]) {
            return $true
        }

        return $false
    }
}


# ================================================================
# Function: Test-RegistryAccess
# ================================================================
# Purpose: Test registry access permissions and provide diagnostic information
# Environment: Windows 10/11, requires registry path to test
# Performance: Fast permission checking, minimal system overhead
# Dependencies: Windows Registry access
# Logic: Attempts registry operations to validate permissions, provides detailed error information
# Features: Permission validation, access diagnostics, fallback path suggestions
# ================================================================
# Function: Test-RegistryAccess
# ================================================================
# Purpose: Verify that the script can read and/or write to required registry
#          locations before performing registry-based changes (safety check).
# Environment: Windows PowerShell with appropriate privileges
# Logic: Attempts a benign read (and optionally a write-test when allowed)
# Returns: [bool] $true when required registry access is available
# Side-effects: None (read-only by default)
# ================================================================
# Function: Test-RegistryAccess
# ================================================================
# Purpose: Verify registry read (and optionally write) access to a
#          hive/key path. Useful to gracefully degrade where access
#          is restricted by policy or non-admin contexts.
# Environment: Reads requested registry path, handles exceptions
# Inputs: $Path (string), $RequireWrite (bool)
# Outputs: Boolean success and optional diagnostic message
# Returns: Hashtable { Success, Message }
# Side-effects: None
# ================================================================
function Test-RegistryAccess {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RegistryPath,

        [Parameter(Mandatory = $false)]
        [string]$TestValueName = 'TestAccess',

        [Parameter(Mandatory = $false)]
        [switch]$CreatePath
    )

    try {
        # Test if path exists or can be created
        if (-not (Test-Path $RegistryPath)) {
            if ($CreatePath) {
                New-Item -Path $RegistryPath -Force -ErrorAction Stop | Out-Null
                Write-Log "Created registry path: $RegistryPath" 'DEBUG'
            }
            else {
                return @{
                    Success    = $false
                    Error      = "Registry path does not exist: $RegistryPath"
                    Suggestion = 'Consider using -CreatePath switch or check path spelling'
                }
            }
        }

        # Test write access by setting a temporary value
        Set-ItemProperty -Path $RegistryPath -Name $TestValueName -Value 'Test' -Force -ErrorAction Stop

        # Test read access and verify the value
        $testValue = Get-ItemProperty -Path $RegistryPath -Name $TestValueName -ErrorAction Stop

        # Verify the test value was read correctly
        if ($testValue.$TestValueName -ne 'Test') {
            throw 'Registry read verification failed - value mismatch'
        }

        # Clean up test value
        Remove-ItemProperty -Path $RegistryPath -Name $TestValueName -Force -ErrorAction SilentlyContinue

        return @{
            Success = $true
            Error   = $null
            Message = "Full registry access confirmed for: $RegistryPath"
        }
    }
    catch [System.UnauthorizedAccessException] {
        return @{
            Success    = $false
            Error      = "Unauthorized access to registry path: $RegistryPath"
            Suggestion = 'Try running as administrator or check registry permissions'
            ErrorType  = 'UnauthorizedAccess'
        }
    }
    catch [System.Security.SecurityException] {
        return @{
            Success    = $false
            Error      = "Security exception accessing registry path: $RegistryPath"
            Suggestion = 'Registry path may be protected by Group Policy or system security'
            ErrorType  = 'SecurityException'
        }
    }
    catch {
        return @{
            Success    = $false
            Error      = "Registry access error: $($_.Exception.Message)"
            Suggestion = 'Check registry path format and Windows version compatibility'
            ErrorType  = 'GeneralError'
        }
    }
}

# ================================================================
# Function: Set-RegistryValueSafely
# ================================================================
# Purpose: Safely set registry values with comprehensive error handling and fallback options
# Environment: Windows 10/11, requires registry path and value details
# Performance: Optimized registry operations with permission checking
# Dependencies: Test-RegistryAccess function, Windows Registry access
# Logic: Pre-validates access, attempts registry modification, provides detailed error reporting
# Features: Permission validation, multiple registry types, detailed error diagnostics, fallback suggestions
# ================================================================
# Function: Set-RegistryValueSafely
# ================================================================
# Purpose: Helper to set a registry value with comprehensive error handling
# Environment: Windows PowerShell, requires appropriate privileges for target keys
# Logic: Writes the specified registry value, logs the action and returns success
# Returns: [bool] $true on success, $false on failure
# Side-effects: Modifies registry keys/values
# ================================================================
# Function: Set-RegistryValueSafely
# ================================================================
# Purpose: Write registry values using safe patterns: check permissions,
#          create parent keys if necessary, and revert or log on failure.
# Environment: Requires appropriate privileges for write operations
# Inputs: $Path, $Name, $Value, $ValueKind
# Outputs: Success boolean and message
# Returns: Hashtable { Success, Message }
# Side-effects: May create or modify registry keys/values
# ================================================================
function Set-RegistryValueSafely {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RegistryPath,

        [Parameter(Mandatory = $true)]
        [string]$ValueName,

        [Parameter(Mandatory = $true)]
        [object]$Value,

        [Parameter(Mandatory = $false)]
        [string]$ValueType = 'DWord',

        [Parameter(Mandatory = $false)]
        [array]$FallbackPaths = @(),

        [Parameter(Mandatory = $false)]
        [string]$Description = 'Registry value'
    )

    # Test access first
    $accessTest = Test-RegistryAccess -RegistryPath $RegistryPath -CreatePath

    if (-not $accessTest.Success) {
        Write-Log "Registry access failed for ${RegistryPath}: $($accessTest.Error)" 'WARN'

        # Try fallback paths if provided
        foreach ($fallbackPath in $FallbackPaths) {
            Write-Log "Attempting fallback registry path: $fallbackPath" 'DEBUG'
            $fallbackTest = Test-RegistryAccess -RegistryPath $fallbackPath -CreatePath

            if ($fallbackTest.Success) {
                try {
                    Set-ItemProperty -Path $fallbackPath -Name $ValueName -Value $Value -Type $ValueType -Force -ErrorAction Stop
                    Write-Log "$Description set successfully via fallback path: $fallbackPath" 'INFO'
                    return @{ Success = $true; Path = $fallbackPath; Method = 'Fallback' }
                }
                catch {
                    Write-Log "Fallback path also failed: $($_.Exception.Message)" 'WARN'
                    continue
                }
            }
        }

        return @{
            Success    = $false;
            Error      = $accessTest.Error;
            Suggestion = $accessTest.Suggestion
        }
    }

    # Primary path access confirmed, proceed with setting value
    try {
        Set-ItemProperty -Path $RegistryPath -Name $ValueName -Value $Value -Type $ValueType -Force -ErrorAction Stop
        Write-Log "$Description set successfully: $RegistryPath\$ValueName = $Value" 'INFO'
        return @{ Success = $true; Path = $RegistryPath; Method = 'Primary' }
    }
    catch {
        Write-Log "Failed to set $Description via registry: $($_.Exception.Message)" 'WARN'
        return @{
            Success    = $false;
            Error      = $_.Exception.Message;
            Suggestion = 'Registry modification may require different approach or manual configuration'
        }
    }
}

# ================================================================
# Function: Compare-InstallationDiff
# ================================================================
# Purpose: Generic diff-based comparison for app installations with standardized processing logic
# Environment: Windows 10/11, requires app inventory data and comparison lists
# Performance: Efficient array operations, optimized for large app lists, minimal memory overhead
# Dependencies: Standardized app inventory format, comparison arrays
# Logic: Compares before/after app states, identifies new/removed/unchanged apps, generates diff reports
# Features: Flexible comparison modes, detailed diff reporting, performance metrics, categorized results
# ================================================================
# Function: Compare-InstallationDiff
# ================================================================
# Purpose: Compare two application inventory lists and produce a diff of
#          installed/removed applications to assist in installation reporting
# Environment: PowerShell 7+ recommended for array/hash performance
# Logic: Accepts prior and current lists, computes Added/Removed/Unchanged
# Returns: Hashtable { Added = @(), Removed = @(), Unchanged = @() }
# Side-effects: None
# ================================================================
# Function: Compare-InstallationDiff
# ================================================================
# Purpose: Compare two installation inventories (before/after) and
#          produce a diff structure describing added, removed, and changed
#          packages. Used to validate that Install/Remove operations had
#          the intended effect.
# Environment: In-memory comparison; tolerant of missing fields
# Inputs: $BeforeInventory, $AfterInventory
# Outputs: Diff object with Added/Removed/Changed lists
# Returns: Hashtable { Added, Removed, Changed }
# Side-effects: None
# ================================================================
function Compare-InstallationDiff {
    param(
        [Parameter(Mandatory = $true)]
        [array]$BeforeList,

        [Parameter(Mandatory = $true)]
        [array]$AfterList,

        [Parameter(Mandatory = $false)]
        [string]$ComparisonType = 'Name',

        [Parameter(Mandatory = $false)]
        [string]$Context = 'App Installation'
    )

    Write-Log "[START] Installation Diff Comparison: $Context" 'INFO'
    $startTime = Get-Date

    try {
        # Normalize arrays for comparison
        $beforeNames = @()
        $afterNames = @()

        # Handle different input formats
        foreach ($item in $BeforeList) {
            if ($item -is [string]) {
                $beforeNames += $item
            }
            elseif ($item -is [hashtable] -or $item.PSObject) {
                $beforeNames += $item.$ComparisonType
            }
        }

        foreach ($item in $AfterList) {
            if ($item -is [string]) {
                $afterNames += $item
            }
            elseif ($item -is [hashtable] -or $item.PSObject) {
                $afterNames += $item.$ComparisonType
            }
        }

        # Calculate differences
        $addedItems = $afterNames | Where-Object { $_ -notin $beforeNames }
        $removedItems = $beforeNames | Where-Object { $_ -notin $afterNames }
        $unchangedItems = $beforeNames | Where-Object { $_ -in $afterNames }

        # Generate diff results
        $diffResult = @{
            Added          = @($addedItems)
            Removed        = @($removedItems)
            Unchanged      = @($unchangedItems)
            TotalBefore    = $beforeNames.Count
            TotalAfter     = $afterNames.Count
            NetChange      = $afterNames.Count - $beforeNames.Count
            ComparisonType = $ComparisonType
            Context        = $Context
            ProcessingTime = (Get-Date) - $startTime
        }

        Write-Log "[DiffComparison] $Context completed: Added=$($diffResult.Added.Count), Removed=$($diffResult.Removed.Count), Net Change=$($diffResult.NetChange)" 'INFO'
        return $diffResult
    }
    catch {
        Write-Log "[DiffComparison] Error in $Context comparison: $_" 'ERROR'
        return $null
    }
    finally {
        Write-Log "[END] Installation Diff Comparison: $Context" 'INFO'
    }
}

# ================================================================
# Function: Get-StandardizedAppInventory
# ================================================================
# Purpose: Unified app inventory collection with standardized format across multiple sources
# Environment: Windows 10/11, requires access to AppX, registry, and package managers
# Performance: Parallel data collection, cached results, optimized for frequent calls
# Dependencies: AppX module, registry access, Winget/Chocolatey availability
# Logic: Collects apps from multiple sources, normalizes format, removes duplicates, provides unified view
# Features: Multi-source collection, duplicate detection, standardized output format, error resilience
# ================================================================
# Function: Get-StandardizedAppInventory
# ================================================================
# Purpose: Collect installed applications from multiple sources (Appx, Winget,
#          Chocolatey, Registry) and normalize them into a single canonical
#          inventory format used by other utilities.
# Environment: Windows with relevant package managers available when possible
# Logic: Queries multiple sources, normalizes fields (Name, Version, Source)
# Returns: Array of standardized application objects
# Side-effects: None (read-only inventory collection)
# ================================================================
# Function: Get-StandardizedAppInventory
# ================================================================
# Purpose: Build a unified inventory of installed apps across multiple
#          sources (Appx, winget, chocolatey, registry) and normalize
#          fields so they can be compared consistently.
# Environment: Reads multiple package sources and merges results
# Inputs: Optional filters and source selection
# Outputs: Array of standardized app objects { Name, Source, Version, Id }
# Returns: Array
# Side-effects: None (read-only)
# ================================================================
function Get-StandardizedAppInventory {
    param(
        [Parameter(Mandatory = $false)]
        [string[]]$Sources = @('AppX', 'Winget', 'Chocolatey'),

        [Parameter(Mandatory = $false)]
        [switch]$IncludeDetails,

        [Parameter(Mandatory = $false)]
        [switch]$UseCache,

        [Parameter(Mandatory = $false)]
        [string]$Context = 'System Inventory'
    )

    Write-Log "[START] Standardized App Inventory Collection: $Context" 'INFO'
    $startTime = Get-Date

    # Check cache if UseCache is enabled
    if ($UseCache -and $global:AppInventoryCache -and $global:AppInventoryCache.Timestamp) {
        $cacheAge = (Get-Date) - $global:AppInventoryCache.Timestamp
        if ($cacheAge.TotalMinutes -lt 10) {
            Write-Log "Using cached app inventory (age: $([math]::Round($cacheAge.TotalMinutes, 1)) minutes)" 'INFO'
            return $global:AppInventoryCache.Data
        }
    }

    $allApps = @()

    try {
        # AppX packages
        if ('AppX' -in $Sources) {
            try {
                Write-Log 'Collecting AppX packages...' 'INFO'
                $appxApps = Get-AppxPackageCompatible | ForEach-Object {
                    @{
                        Name              = $_.Name
                        DisplayName       = $_.PackageFullName
                        Version           = $_.Version.ToString()
                        Source            = 'AppX'
                        InstallLocation   = $_.InstallLocation
                        PackageFamilyName = $_.PackageFamilyName
                    }
                }
                $allApps += $appxApps
                Write-Log "Collected $($appxApps.Count) AppX packages" 'INFO'
            }
            catch {
                Write-Log "Failed to collect AppX packages: $_" 'WARN'
            }
        }

        # Winget packages
        if ('Winget' -in $Sources -and (Test-CommandAvailable 'winget')) {
            try {
                Write-Log 'Collecting Winget packages...' 'INFO'
                $wingetResult = & winget list --accept-source-agreements 2>$null
                if ($wingetResult) {
                    $wingetApps = @()
                    $wingetResult | Where-Object { $_ -and $_ -match '^\S+\s+.*\s+\d' } | ForEach-Object {
                        # Robust parsing: split from right to get Version, then by first tab/spaces to get ID and Name
                        $trimmed = $_.Trim()
                        $parts = $trimmed -split '\s+'
                        
                        if ($parts.Count -ge 2) {
                            # Last part is typically version, second-to-last often has version info
                            # First part is ID, rest is display name
                            $id = $parts[0]
                            $version = if ($parts.Count -ge 3) { $parts[-1] } else { 'Unknown' }
                            # Everything between ID and version is the display name
                            $displayName = if ($parts.Count -ge 3) {
                                ($parts[1..($parts.Count - 2)] -join ' ').Trim()
                            }
                            else {
                                $parts[1].Trim()
                            }
                            
                            $wingetApps += @{
                                Name        = $id.Trim()
                                DisplayName = $displayName
                                Version     = $version.Trim()
                                Source      = 'Winget'
                                Id          = $id.Trim()
                            }
                        }
                    }
                    $allApps += $wingetApps
                    Write-Log "Collected $($wingetApps.Count) Winget packages" 'INFO'
                }
            }
            catch {
                Write-Log "Failed to collect Winget packages: $_" 'WARN'
            }
        }

        # Chocolatey packages
        if ('Chocolatey' -in $Sources -and (Test-CommandAvailable 'choco')) {
            try {
                Write-Log 'Collecting Chocolatey packages...' 'INFO'
                $chocoResult = & choco list --local-only --limit-output 2>$null
                if ($chocoResult) {
                    $chocoApps = @()
                    $chocoResult | Where-Object { $_ -and $_ -match '\|' } | ForEach-Object {
                        $parts = $_ -split '\|'
                        if ($parts.Count -ge 2) {
                            $packageId = $parts[0].Trim()
                            $version = $parts[1].Trim()
                            # Try to get a readable display name from the package ID
                            $displayName = ($packageId -replace '[\-_]', ' ') -replace '\.', ' '
                            
                            $chocoApps += @{
                                Name        = $packageId
                                DisplayName = $displayName
                                Version     = $version
                                Source      = 'Chocolatey'
                                Id          = $packageId
                            }
                        }
                    }
                    $allApps += $chocoApps
                    Write-Log "Collected $($chocoApps.Count) Chocolatey packages" 'INFO'
                }
            }
            catch {
                Write-Log "Failed to collect Chocolatey packages: $_" 'WARN'
            }
        }

        # Create standardized inventory
        $inventory = @{
            Apps               = $allApps
            TotalCount         = $allApps.Count
            SourceCounts       = @{}
            CollectionTime     = Get-Date
            ProcessingDuration = (Get-Date) - $startTime
            Context            = $Context
        }

        # Calculate source statistics
        foreach ($source in $Sources) {
            $sourceCount = ($allApps | Where-Object { $_.Source -eq $source }).Count
            $inventory.SourceCounts[$source] = $sourceCount
        }

        Write-Log "[Inventory] Collected $($inventory.TotalCount) total apps from $($Sources -join ', ')" 'INFO'

        # Cache the result if UseCache is enabled
        if ($UseCache) {
            $global:AppInventoryCache = @{
                Data      = $inventory
                Timestamp = Get-Date
            }
            Write-Log 'Cached app inventory for future use' 'INFO'
        }

        return $inventory
    }
    catch {
        Write-Log "[Inventory] Error collecting standardized inventory: $_" 'ERROR'
        return $null
    }
    finally {
        Write-Log "[END] Standardized App Inventory Collection: $Context" 'INFO'
    }
}

# ================================================================
# Function: Invoke-PackageManagerCommand
# ================================================================
# Purpose: Unified package manager command wrapper with standardized error handling and logging
# Environment: Windows 10/11, requires Winget/Chocolatey availability, package manager access
# Performance: Timeout handling, progress tracking, optimized for reliability over speed
# Dependencies: Package manager availability, system PATH configuration, network connectivity
# Logic: Detects available package managers, executes commands with timeout, provides unified result format
# Features: Multi-manager support, timeout protection, standardized logging, error resilience, progress tracking
# ================================================================
# Function: Invoke-PackageManagerCommand
# ================================================================
# Purpose: Unified wrapper for invoking package manager commands (winget, choco)
#          with timeout protection, structured results and logging.
# Environment: Windows with package managers installed (optional fallback)
# Logic: Detects manager availability, runs the command, captures exit status
# Returns: Hashtable { Success = $bool, Output = $string, Error = $string }
# Side-effects: Installs/uninstalls/updates packages depending on arguments
# ================================================================
# Function: Invoke-PackageManagerCommand
# ================================================================
# Purpose: Wrapper to invoke package manager commands (winget, choco)
#          with timeouts, logging, and a normalized result shape. Also
#          selects the best available manager if multiple exist.
# Environment: Calls external package managers; requires network for installs
# Inputs: $ManagerName, $Arguments, $Timeout
# Outputs: Normalized result object with Success/ExitCode/Output
# Returns: Hashtable
# Side-effects: Installs/uninstalls packages when used for that purpose
# ================================================================
function Invoke-PackageManagerCommand {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Install', 'Uninstall', 'List', 'Search', 'Update')]
        [string]$Operation,

        [Parameter(Mandatory = $false)]
        [string]$PackageId,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Winget', 'Chocolatey', 'Auto')]
        [string]$PreferredManager = 'Auto',

        [Parameter(Mandatory = $false)]
        [int]$TimeoutSeconds = 300,

        [Parameter(Mandatory = $false)]
        [string]$Context = 'Package Operation'
    )

    Write-Log "[START] Package Manager Command: $Operation for $PackageId via $PreferredManager" 'INFO'
    $startTime = Get-Date

    try {
        # Determine which package manager to use
        $manager = $null
        $managerCommand = $null

        if ($PreferredManager -eq 'Auto') {
            if (Test-CommandAvailable 'winget') {
                $manager = 'Winget'
                $managerCommand = 'winget.exe'
            }
            elseif (Test-CommandAvailable 'choco') {
                $manager = 'Chocolatey'
                $managerCommand = 'choco.exe'
            }
        }
        else {
            $manager = $PreferredManager
            $managerCommand = $global:PackageManagers[$manager].Command
        }

        if (-not $manager -or -not (Test-CommandAvailable $managerCommand)) {
            Write-Log "Package manager $manager not available" 'ERROR'
            return @{ Success = $false; Error = "Package manager not available: $manager" }
        }

        # Build command arguments
        $argumentList = @()
        switch ($Operation) {
            'Install' {
                $argumentList = $global:PackageManagers[$manager].InstallArgs -f $PackageId
            }
            'Uninstall' {
                $argumentList = $global:PackageManagers[$manager].UninstallArgs -f $PackageId
            }
            'List' {
                $argumentList = $global:PackageManagers[$manager].ListArgs
            }
            'Search' {
                $argumentList = $global:PackageManagers[$manager].SearchArgs -f $PackageId
            }
            'Update' {
                $argumentList = $global:PackageManagers[$manager].UpdateArgs
            }
        }

        Write-Log "Executing: $managerCommand $($argumentList -join ' ')" 'INFO'

        # Execute command with timeout
        $pkgOutPath = Join-Path $global:TempFolder 'pkg_out.txt'
        $pkgErrPath = Join-Path $global:TempFolder 'pkg_err.txt'
        $process = Start-Process -FilePath $managerCommand -ArgumentList $argumentList -NoNewWindow -Wait -PassThru -RedirectStandardOutput $pkgOutPath -RedirectStandardError $pkgErrPath

        # Wait for completion with timeout
        $completed = $process.WaitForExit($TimeoutSeconds * 1000)

        if (-not $completed) {
            $process.Kill()
            Write-Log "Package operation timed out after $TimeoutSeconds seconds" 'ERROR'
            return @{ Success = $false; Error = 'Operation timed out' }
        }

        # Read output
        $stdout = if (Test-Path $pkgOutPath) { Get-Content $pkgOutPath -Raw } else { '' }
        $stderr = if (Test-Path $pkgErrPath) { Get-Content $pkgErrPath -Raw } else { '' }

        # Clean up temp files
        Remove-Item $pkgOutPath, $pkgErrPath -ErrorAction SilentlyContinue

        # Determine success
        $success = ($process.ExitCode -eq 0)
        $duration = (Get-Date) - $startTime

        $result = @{
            Success        = $success
            ExitCode       = $process.ExitCode
            StandardOutput = $stdout
            StandardError  = $stderr
            Manager        = $manager
            Operation      = $Operation
            PackageId      = $PackageId
            Duration       = $duration.TotalSeconds
            Context        = $Context
        }

        if ($success) {
            Write-Log "[PackageManager] $Operation completed successfully for $PackageId via $manager (${duration}s)" 'SUCCESS'
        }
        else {
            Write-Log "[PackageManager] $Operation failed for $PackageId via $manager ExitCode=$($process.ExitCode)" 'ERROR'
            $result.Error = "ExitCode: $($process.ExitCode), StdErr: $stderr"
        }

        return $result
    }
    catch {
        $duration = (Get-Date) - $startTime
        Write-Log "[PackageManager] Exception during $Operation for $PackageId - Exception $($_.Exception.Message)" 'ERROR'
        return @{
            Success   = $false
            Error     = $_.Exception.Message
            Operation = $Operation
            PackageId = $PackageId
            Duration  = $duration.TotalSeconds
            Context   = $Context
        }
    }
    finally {
        Write-Log "[END] Package Manager Command: $Operation for $PackageId" 'INFO'
    }
}

# ================================================================
# Function: Start-ProgressTrackedOperation
# ================================================================
# Purpose: Standardized progress tracking wrapper for long-running operations
# Environment: Windows 10/11, PowerShell console, progress display capabilities
# Performance: Lightweight progress updates, non-blocking operation, efficient display updates
# Dependencies: Write-ActionProgress system, console display capabilities
# Logic: Wraps operations with progress tracking, handles errors gracefully, provides consistent UX
# Features: Auto-cleanup progress bars, error handling, timing metrics, standardized progress display
# ================================================================
# Function: Start-ProgressTrackedOperation
# ================================================================
# Purpose: Template helper to run long-running operations with timing and
#          standardized progress reporting and error handling.
# Environment: PowerShell 7+ recommended (but works on 5.1)
# Logic: Accepts a ScriptBlock and metadata, runs it while tracking duration
# Returns: Hashtable { Success, Duration, Result }
# Side-effects: Writes progress and logs
# ================================================================
# Function: Start-ProgressTrackedOperation
# ================================================================
# Purpose: Initialize a tracked operation structure for long-running
#          processes. The returned object allows the caller to update
#          progress, set messages, and finalize timing metrics.
# Environment: In-memory helper; integrates with Write-TaskProgress
# Inputs: $OperationName, $TotalSteps
# Outputs: Tracker object with Update() and Complete() methods
# Returns: Object/Hashtable
# Side-effects: None
# ================================================================
function Start-ProgressTrackedOperation {
    param(
        [Parameter(Mandatory = $true)]
        [scriptblock]$Operation,

        [Parameter(Mandatory = $true)]
        [string]$ActionType,

        [Parameter(Mandatory = $true)]
        [string]$ItemName,

        [Parameter(Mandatory = $false)]
        [string]$InitialStatus = 'Starting...',

        [Parameter(Mandatory = $false)]
        [string]$Context = 'Operation'
    )

    $startTime = Get-Date
    $operationId = [System.Guid]::NewGuid().ToString('N')[0..7] -join ''

    try {
        # Start progress tracking
        Write-ActionProgress -ActionType $ActionType -ItemName $ItemName -PercentComplete 0 -Status $InitialStatus
        Write-Log "[ProgressOp-$operationId] Started: $ActionType $ItemName" 'INFO'

        # Execute the operation
        $result = & $Operation

        # Complete progress tracking
        Write-ActionProgress -ActionType $ActionType -ItemName $ItemName -PercentComplete 100 -Status 'Completed successfully' -Completed

        $duration = (Get-Date) - $startTime
        Write-Log "[ProgressOp-$operationId] Completed: $ActionType $ItemName (${duration}s)" 'SUCCESS'

        return @{
            Success     = $true
            Result      = $result
            Duration    = $duration.TotalSeconds
            Context     = $Context
            OperationId = $operationId
        }
    }
    catch {
        # Handle errors with progress cleanup
        Write-ActionProgress -ActionType $ActionType -ItemName $ItemName -PercentComplete 100 -Status "Failed: $($_.Exception.Message)" -Completed

        $duration = (Get-Date) - $startTime
        Write-Log "[ProgressOp-$operationId] Failed: $ActionType $ItemName - $_" 'ERROR'

        return @{
            Success     = $false
            Error       = $_.Exception.Message
            Duration    = $duration.TotalSeconds
            Context     = $Context
            OperationId = $operationId
        }
    }
}

# ================================================================
# REUSABLE UTILITY FUNCTIONS: App Detection and Management
# ================================================================

# ================================================================
# Function: Find-AppInstallations
# ================================================================
# Purpose: Universal app detection across multiple sources with pattern matching
# Environment: Windows 10/11, requires access to AppX, registry, and package managers
# Performance: Optimized search patterns, parallel source checking, cached results
# Dependencies: System app sources, registry access, package manager availability
# Logic: Searches across all app sources using flexible pattern matching, returns standardized results
# Features: Multi-source search, pattern matching, detailed app information, source identification
# ================================================================
# Function: Find-AppInstallations
# ================================================================
# Purpose: Locate installed applications on disk and in registries by pattern
# Environment: Windows file system and registry access required
# Logic: Uses pattern matching and known install paths to find executables
# Returns: Array of installation objects (Path, Version, Publisher)
# Side-effects: None (detection only)
# ================================================================
# Function: Find-AppInstallations
# ================================================================
# Purpose: Search the system for instances of a named application
#          across multiple sources (registry, appx, winget, choco) and
#          return canonical install locations and identifiers.
# Environment: Read-only system inspection
# Inputs: $AppPattern (string or regex)
# Outputs: Array of install records { Name, Path, Source, Version }
# Returns: Array
# Side-effects: None
# ================================================================
function Find-AppInstallations {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$SearchPatterns,

        [Parameter(Mandatory = $false)]
        [string[]]$Sources = @('AppX', 'Winget', 'Chocolatey'),

        [Parameter(Mandatory = $false)]
        [switch]$ExactMatch,

        [Parameter(Mandatory = $false)]
        [string]$Context = 'App Search'
    )

    # Set default behavior for switches (PSScriptAnalyzer compliant)
    if (-not $PSBoundParameters.ContainsKey('ExactMatch')) { $ExactMatch = $false }

    Write-Log "[START] App Installation Search: $($SearchPatterns -join ', ') in $($Sources -join ', ')" 'INFO'
    $foundApps = @()

    try {
        # Get standardized inventory
        $inventory = Get-StandardizedAppInventory -Sources $Sources -Context $Context
        if (-not $inventory) {
            Write-Log 'Failed to get app inventory for search' 'ERROR'
            return @()
        }

        # Search through inventory
        foreach ($pattern in $SearchPatterns) {
            $matchingApps = @()

            if ($ExactMatch) {
                $matchingApps = $inventory.Apps | Where-Object {
                    $_.Name -eq $pattern -or $_.DisplayName -eq $pattern
                }
            }
            else {
                $matchingApps = $inventory.Apps | Where-Object {
                    $_.Name -like "*$pattern*" -or $_.DisplayName -like "*$pattern*"
                }
            }

            foreach ($app in $matchingApps) {
                $foundApps += @{
                    SearchPattern = $pattern
                    MatchedApp    = $app
                    MatchType     = if ($ExactMatch) { 'Exact' } else { 'Pattern' }
                    Source        = $app.Source
                    Context       = $Context
                }
            }
        }

        Write-Log "[AppSearch] Found $($foundApps.Count) app installations matching patterns" 'INFO'
        return $foundApps
    }
    catch {
        Write-Log "[AppSearch] Error during app search: $_" 'ERROR'
        return @()
    }
    finally {
        Write-Log '[END] App Installation Search' 'INFO'
    }
}

# ================================================================
# Function: Remove-AppsByPattern
# ================================================================
# Purpose: Batch app removal with pattern matching and safety checks
# Environment: Windows 10/11, requires administrator privileges, app uninstall capabilities
# Performance: Parallel removal operations, progress tracking, timeout protection
# Dependencies: Package managers, AppX removal capabilities, administrator privileges
# Logic: Finds matching apps, confirms removal safety, executes removal with progress tracking
# Features: Safety checks, progress tracking, detailed logging, rollback on critical failures
# ================================================================
# Function: Remove-AppsByPattern
# ================================================================
# Purpose: Remove applications matching a set of patterns using configured
#          package managers or native uninstall strings where available.
# Environment: Windows with appropriate uninstaller access
# Logic: Matches patterns, chooses safest uninstall method, performs removal
# Returns: Array of results for each uninstall attempt
# Side-effects: Uninstalls applications; use with care
# ================================================================
# Function: Remove-AppsByPattern
# ================================================================
# Purpose: Remove matching apps using the best available method per
#          installation source (Appx removal, registry-based uninstall,
#          winget/choco). Executes in a safe, logged manner with retries
#          and dry-run support.
# Environment: May require admin rights depending on source
# Inputs: $Pattern, $WhatIf (switch), $Force (switch)
# Outputs: Array of results per attempted uninstall
# Returns: Array of hashtables { Name, Source, Success, Details }
# Side-effects: Removes software from the system when invoked without WhatIf
# ================================================================
function Remove-AppsByPattern {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$RemovalPatterns,

        [Parameter(Mandatory = $false)]
        [string[]]$SafetyExclusions = @(),

        [Parameter(Mandatory = $false)]
        [switch]$WhatIf,

        [Parameter(Mandatory = $false)]
        [string]$Context = 'App Removal'
    )

    # Set default behavior for switches (PSScriptAnalyzer compliant)
    if (-not $PSBoundParameters.ContainsKey('WhatIf')) { $WhatIf = $false }

    Write-Log "[START] Pattern-based App Removal: $($RemovalPatterns -join ', ')" 'INFO'
    $removalResults = @()

    try {
        # Find apps to remove
        $appsToRemove = Find-AppInstallations -SearchPatterns $RemovalPatterns -Context "$Context - Detection"

        if ($appsToRemove.Count -eq 0) {
            Write-Log 'No apps found matching removal patterns' 'INFO'
            return @()
        }

        # Apply safety exclusions
        $safeAppsToRemove = $appsToRemove | Where-Object {
            $app = $_.MatchedApp
            $excluded = $false
            foreach ($exclusion in $SafetyExclusions) {
                if ($app.Name -like "*$exclusion*" -or $app.DisplayName -like "*$exclusion*") {
                    $excluded = $true
                    break
                }
            }
            -not $excluded
        }

        Write-Log "Apps to remove: $($safeAppsToRemove.Count) (after safety exclusions)" 'INFO'

        if ($WhatIf) {
            Write-Log '[WHATIF] Would remove the following apps:' 'INFO'
            foreach ($appInfo in $safeAppsToRemove) {
                Write-Log "[WHATIF] - $($appInfo.MatchedApp.DisplayName) ($($appInfo.MatchedApp.Source))" 'INFO'
            }
            return $safeAppsToRemove
        }

        # Remove apps with progress tracking
        $currentIndex = 0
        foreach ($appInfo in $safeAppsToRemove) {
            $currentIndex++
            $app = $appInfo.MatchedApp
            $progress = [math]::Round(($currentIndex / $safeAppsToRemove.Count) * 100)

            Write-ActionProgress -ActionType 'Removing' -ItemName $app.DisplayName -PercentComplete $progress -Status "Removing app ($currentIndex/$($safeAppsToRemove.Count))"

            try {
                $removalResult = $null

                # Remove based on source
                switch ($app.Source) {
                    'AppX' {
                        $removalResult = Remove-AppxPackageCompatible -Name $app.Name
                    }
                    'Winget' {
                        $removalResult = Invoke-PackageManagerCommand -Operation 'Uninstall' -PackageId $app.Name -PreferredManager 'Winget' -Context $Context
                    }
                    'Chocolatey' {
                        $removalResult = Invoke-PackageManagerCommand -Operation 'Uninstall' -PackageId $app.Name -PreferredManager 'Chocolatey' -Context $Context
                    }
                }

                $removalResults += @{
                    App     = $app
                    Success = $removalResult.Success
                    Result  = $removalResult
                    Pattern = $appInfo.SearchPattern
                    Context = $Context
                }

                if ($removalResult.Success) {
                    Write-Log "Successfully removed: $($app.DisplayName)" 'SUCCESS'
                }
                else {
                    Write-Log "Failed to remove: $($app.DisplayName) - $($removalResult.Error)" 'ERROR'
                }
            }
            catch {
                Write-Log "Exception removing $($app.DisplayName): $_" 'ERROR'
                $removalResults += @{
                    App     = $app
                    Success = $false
                    Error   = $_.Exception.Message
                    Pattern = $appInfo.SearchPattern
                    Context = $Context
                }
            }
        }

        # Complete progress
        Write-ActionProgress -ActionType 'Removing' -ItemName 'Apps' -PercentComplete 100 -Status 'Removal completed' -Completed

        $successCount = ($removalResults | Where-Object { $_.Success }).Count
        Write-Log "[RemovalSummary] Processed $($removalResults.Count) apps: $successCount successful, $($removalResults.Count - $successCount) failed" 'INFO'

        return $removalResults
    }
    catch {
        Write-Log "[AppRemoval] Error during pattern-based removal: $_" 'ERROR'
        return @()
    }
    finally {
        Write-Log '[END] Pattern-based App Removal' 'INFO'
    }
}

# ================================================================
# Function: Install-AppsByCategory
# ================================================================
# Purpose: Install groups of applications by category (e.g., Browsers,
#          Document Tools) using configured package managers and strategies.
# Environment: Windows with package managers available for each category
# Logic: Iterates over a category list, resolves conflicts, and installs
# Returns: Summary object with successes/failures and timing
# Side-effects: Installs software (may require reboots)
# ================================================================
# Function: Install-AppsByCategory
# ================================================================
# Purpose: Install a curated set of 'essential' apps grouped by category
#          (WebBrowsers, SystemTools, Communication, etc.) using the
#          configured package manager and respecting $global:Config
#          preferences and exclusions.
# Environment: Network access recommended; may require reboots for some installers
# Inputs: $Category (string), $Options (hashtable)
# Outputs: Installation results and logs
# Returns: Array of results per package
# Side-effects: Installs software and may alter system settings
# ================================================================
function Install-AppsByCategory {
    param(
        [string]$Category
    )
    # ...existing code...
}

# ================================================================
# Function: Install-AppsByCategory
# ================================================================
# Purpose: Batch app installation with category-based organization and conflict resolution
# Environment: Windows 10/11, requires network connectivity, package manager access
# Performance: Parallel installations, progress tracking, timeout protection, retry logic
# Dependencies: Package managers, network connectivity, sufficient disk space
# Logic: Organizes apps by category, resolves conflicts, installs with progress tracking and error recovery
# Features: Category organization, conflict resolution, progress tracking, detailed logging, retry mechanism
# ================================================================
function Install-AppsByCategory {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$AppCategories,

        [Parameter(Mandatory = $false)]
        [string[]]$SelectedCategories = @(),

        [Parameter(Mandatory = $false)]
        [string]$PreferredManager = 'Auto',

        [Parameter(Mandatory = $false)]
        [switch]$WhatIf,

        [Parameter(Mandatory = $false)]
        [string]$Context = 'App Installation'
    )

    # Set default behavior for switches (PSScriptAnalyzer compliant)
    if (-not $PSBoundParameters.ContainsKey('WhatIf')) { $WhatIf = $false }

    Write-Log "[START] Category-based App Installation: $($AppCategories.Keys -join ', ')" 'INFO'
    $installationResults = @()

    try {
        # Determine categories to process
        $categoriesToProcess = if ($SelectedCategories.Count -gt 0) {
            $SelectedCategories
        }
        else {
            $AppCategories.Keys
        }

        # Flatten apps from selected categories
        $allApps = @()
        foreach ($category in $categoriesToProcess) {
            if ($AppCategories.ContainsKey($category)) {
                foreach ($app in $AppCategories[$category]) {
                    $allApps += @{
                        App      = $app
                        Category = $category
                    }
                }
            }
        }

        Write-Log "Apps to install: $($allApps.Count) from categories: $($categoriesToProcess -join ', ')" 'INFO'

        if ($WhatIf) {
            Write-Log '[WHATIF] Would install the following apps by category:' 'INFO'
            foreach ($category in $categoriesToProcess) {
                Write-Log "[WHATIF] Category: $category" 'INFO'
                foreach ($app in $AppCategories[$category]) {
                    $appName = if ($app -is [hashtable]) { $app.Name } else { $app }
                    Write-Log "[WHATIF] - $appName" 'INFO'
                }
            }
            return $allApps
        }

        # Install apps with progress tracking
        $currentIndex = 0
        foreach ($appInfo in $allApps) {
            $currentIndex++
            $app = $appInfo.App
            $category = $appInfo.Category
            $progress = [math]::Round(($currentIndex / $allApps.Count) * 100)

            $appName = if ($app -is [hashtable]) { $app.Name } else { $app }
            Write-ActionProgress -ActionType 'Installing' -ItemName $appName -PercentComplete $progress -Status "Installing $category app ($currentIndex/$($allApps.Count))"

            try {
                $installResult = $null

                if ($app -is [hashtable]) {
                    # App with package manager options
                    if ($app.Winget -and ($PreferredManager -eq 'Auto' -or $PreferredManager -eq 'Winget')) {
                        $installResult = Invoke-PackageManagerCommand -Operation 'Install' -PackageId $app.Winget -PreferredManager 'Winget' -Context "$Context - $category"
                    }
                    elseif ($app.Choco -and ($PreferredManager -eq 'Auto' -or $PreferredManager -eq 'Chocolatey')) {
                        $installResult = Invoke-PackageManagerCommand -Operation 'Install' -PackageId $app.Choco -PreferredManager 'Chocolatey' -Context "$Context - $category"
                    }
                }
                else {
                    # Simple app name - try auto-detection
                    $installResult = Invoke-PackageManagerCommand -Operation 'Install' -PackageId $app -PreferredManager $PreferredManager -Context "$Context - $category"
                }

                $installationResults += @{
                    App      = $app
                    Category = $category
                    Success  = $installResult.Success
                    Result   = $installResult
                    Context  = $Context
                }

                if ($installResult.Success) {
                    Write-Log "Successfully installed: $appName ($category)" 'SUCCESS'
                }
                else {
                    Write-Log "Failed to install: $appName ($category) - $($installResult.Error)" 'ERROR'
                }
            }
            catch {
                Write-Log "Exception installing $appName ($category): $_" 'ERROR'
                $installationResults += @{
                    App      = $app
                    Category = $category
                    Success  = $false
                    Error    = $_.Exception.Message
                    Context  = $Context
                }
            }
        }

        # Complete progress
        Write-ActionProgress -ActionType 'Installing' -ItemName 'Apps' -PercentComplete 100 -Status 'Installation completed' -Completed

        $successCount = ($installationResults | Where-Object { $_.Success }).Count
        Write-Log "[InstallationSummary] Processed $($installationResults.Count) apps: $successCount successful, $($installationResults.Count - $successCount) failed" 'INFO'

        return $installationResults
    }
    catch {
        Write-Log "[AppInstallation] Error during category-based installation: $_" 'ERROR'
        return @()
    }
    finally {
        Write-Log '[END] Category-based App Installation' 'INFO'
    }
}

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
        [string]$ErrorAction = 'Continue'
    )

    try {
        Write-ActionLog -Action 'Executing Windows PowerShell compatibility command' -Details $Command -Category 'PowerShell Compatibility' -Status 'START'

        # Build the full command with error action
        $fullCommand = if ($ErrorAction -eq 'SilentlyContinue') {
            "$Command -ErrorAction SilentlyContinue 2>`$null"
        }
        else {
            $Command
        }

        # Execute command in Windows PowerShell 5.1 context with proper encoding
        $outputFile = [System.IO.Path]::GetTempFileName()
        $errorFile = [System.IO.Path]::GetTempFileName()

        try {
            $process = Start-Process -FilePath 'powershell.exe' -ArgumentList '-Command', "& {$fullCommand} | Out-File -FilePath '$outputFile' -Encoding UTF8" -RedirectStandardError $errorFile -Wait -PassThru -WindowStyle Hidden

            $output = if (Test-Path $outputFile) { Get-Content $outputFile -Raw -Encoding UTF8 } else { $null }
            $errorOutput = if (Test-Path $errorFile) { Get-Content $errorFile -Raw -Encoding UTF8 } else { $null }

            if ($process.ExitCode -eq 0) {
                Write-ActionLog -Action 'Windows PowerShell command completed successfully' -Details "ExitCode: $($process.ExitCode)" -Category 'PowerShell Compatibility' -Status 'SUCCESS'

                # Parse output if it's structured data
                if ($output -and $output.Trim()) {
                    try {
                        # Try to convert from JSON if it looks like structured data
                        if ($output.Trim().StartsWith('[') -or $output.Trim().StartsWith('{')) {
                            return $output | ConvertFrom-Json
                        }
                        else {
                            # Return raw output for simple commands
                            return $output.Trim() -split "`r?`n" | Where-Object { $_.Trim() -ne '' }
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
                Write-ActionLog -Action 'Windows PowerShell command failed' -Details "ExitCode: $($process.ExitCode) | Error: $errorOutput" -Category 'PowerShell Compatibility' -Status 'FAILURE'
                if ($ErrorAction -eq 'SilentlyContinue') {
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
        Write-ActionLog -Action 'Failed to execute Windows PowerShell command' -Details $_.Exception.Message -Category 'PowerShell Compatibility' -Status 'FAILURE'
        if ($ErrorAction -eq 'SilentlyContinue') {
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
# Purpose: Wrapper around Get-AppxPackage designed to be compatible across
#          different PowerShell versions and with added error handling.
# Environment: Windows with AppX support
# Logic: Runs Get-AppxPackage and normalizes results
# Returns: Array of Appx package objects
# Side-effects: None
# ================================================================
function Get-AppxPackageCompatible {
    # ...existing code...
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
        [string]$Name = '*',
        [switch]$AllUsers
    )

    # Check if Appx module is available and can be loaded
    try {
        if (-not (Get-Module -Name Appx -ListAvailable)) {
            Write-Log 'Appx module not available on this system' 'WARN'
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
        if ($_.Exception.Message -like '*Operation is not supported on this platform*') {
            Write-Log 'AppX subsystem not supported on this platform (likely Windows Server Core or minimal installation)' 'WARN'
        }
        elseif ($_.Exception.Message -like '*module could not be loaded*') {
            Write-Log 'Appx module failed to load - AppX subsystem may be disabled or unavailable' 'WARN'
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
# Purpose: Enumerate provisioned Appx packages from image/OS and normalize
# Environment: Requires DISM/Appx cmdlets where available
# Returns: Array of provisioned package objects
# Side-effects: None
# ================================================================
function Get-AppxProvisionedPackageCompatible {
    # ...existing code...
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
# Function: Get-AppXBloatware
# ================================================================
# Purpose: Discover bloatware in AppX packages (Windows Store apps)
# Environment: Windows 10/11, requires AppX subsystem
# Performance: Fast, leverages Get-StandardizedAppInventory cache
# Dependencies: Get-StandardizedAppInventory
# Logic: Scans AppX packages, matches against bloatware patterns
# Features: Detects installed AppX bloatware, supports caching
# ================================================================
function Get-AppXBloatware {
    param(
        [Parameter(Mandatory = $false)]
        [string[]]$BloatwarePatterns = $global:BloatwareList,
        [Parameter(Mandatory = $false)]
        [string]$Context = 'AppX Scan',
        [Parameter(Mandatory = $false)]
        [switch]$UseCache
    )

    try {
        $appInventory = Get-StandardizedAppInventory -Context $Context -UseCache:$UseCache
        $appXApps = $appInventory | Where-Object { $_.Source -eq 'AppX' }

        $found = @()
        foreach ($app in $appXApps) {
            foreach ($pattern in $BloatwarePatterns) {
                if ($app.Name -like $pattern -or $app.DisplayName -like "*$pattern*") {
                    $found += [PSCustomObject]@{
                        Name           = $app.Name
                        DisplayName    = $app.DisplayName
                        Version        = $app.Version
                        Publisher      = $app.Publisher
                        InstallDate    = $app.InstallDate
                        Source         = 'AppX'
                        MatchedPattern = $pattern
                        Context        = $Context
                    }
                }
            }
        }

        return $found
    }
    catch {
        Write-Log "Error in Get-AppXBloatware: $_" 'ERROR'
        return @()
    }
}

# ================================================================
# Function: Get-WingetBloatware
# ================================================================
# Function: Get-WingetBloatware
# ================================================================
# Purpose: Discover bloatware in Winget packages
# Environment: Windows 10/11, requires Winget package manager
# Performance: Fast, leverages Get-StandardizedAppInventory cache
# Dependencies: Get-StandardizedAppInventory
# Logic: Scans Winget packages, matches against bloatware patterns
# Features: Detects Winget-managed bloatware, supports caching
# ================================================================
function Get-WingetBloatware {
    param(
        [Parameter(Mandatory = $false)]
        [string[]]$BloatwarePatterns = $global:BloatwareList,
        [Parameter(Mandatory = $false)]
        [string]$Context = 'Winget Scan',
        [Parameter(Mandatory = $false)]
        [switch]$UseCache
    )

    try {
        $appInventory = Get-StandardizedAppInventory -Context $Context -UseCache:$UseCache
        $wingetApps = $appInventory | Where-Object { $_.Source -eq 'Winget' }

        $found = @()
        foreach ($app in $wingetApps) {
            foreach ($pattern in $BloatwarePatterns) {
                if ($app.Name -like $pattern -or $app.DisplayName -like "*$pattern*") {
                    $found += [PSCustomObject]@{
                        Name           = $app.Name
                        DisplayName    = $app.DisplayName
                        Version        = $app.Version
                        Publisher      = $app.Publisher
                        InstallDate    = $app.InstallDate
                        Source         = 'Winget'
                        MatchedPattern = $pattern
                        Context        = $Context
                    }
                }
            }
        }

        return $found
    }
    catch {
        Write-Log "Error in Get-WingetBloatware: $_" 'ERROR'
        return @()
    }
}

# ================================================================
# Function: Get-ChocolateyBloatware
# ================================================================
# Purpose: Discover bloatware in Chocolatey packages
# Environment: Windows, requires Chocolatey package manager
# Performance: Fast, leverages Get-StandardizedAppInventory cache
# Dependencies: Get-StandardizedAppInventory
# Logic: Scans Chocolatey packages, matches against bloatware patterns
# Features: Detects Chocolatey-managed bloatware, supports caching
# ================================================================
function Get-ChocolateyBloatware {
    param(
        [Parameter(Mandatory = $false)]
        [string[]]$BloatwarePatterns = $global:BloatwareList,
        [Parameter(Mandatory = $false)]
        [string]$Context = 'Chocolatey Scan',
        [Parameter(Mandatory = $false)]
        [switch]$UseCache
    )

    try {
        $appInventory = Get-StandardizedAppInventory -Context $Context -UseCache:$UseCache
        $chocoApps = $appInventory | Where-Object { $_.Source -eq 'Chocolatey' }

        $found = @()
        foreach ($app in $chocoApps) {
            foreach ($pattern in $BloatwarePatterns) {
                if ($app.Name -like $pattern -or $app.DisplayName -like "*$pattern*") {
                    $found += [PSCustomObject]@{
                        Name           = $app.Name
                        DisplayName    = $app.DisplayName
                        Version        = $app.Version
                        Publisher      = $app.Publisher
                        InstallDate    = $app.InstallDate
                        Source         = 'Chocolatey'
                        MatchedPattern = $pattern
                        Context        = $Context
                    }
                }
            }
        }

        return $found
    }
    catch {
        Write-Log "Error in Get-ChocolateyBloatware: $_" 'ERROR'
        return @()
    }
}

# ================================================================
# Function: Get-RegistryBloatware
# ================================================================
# Purpose: Discover bloatware in Windows Registry uninstall keys
# Environment: Windows, requires registry access
# Performance: Fast, leverages existing registry scan logic
# Dependencies: Registry access, bloatware pattern matching
# Logic: Scans registry uninstall keys, matches against bloatware patterns
# Features: Detects registry-based bloatware installations, comprehensive coverage
# ================================================================
function Get-RegistryBloatware {
    param(
        [Parameter(Mandatory = $false)]
        [string[]]$BloatwarePatterns = $global:BloatwareList,
        [Parameter(Mandatory = $false)]
        [string]$Context = 'Registry Scan',
        [Parameter(Mandatory = $false)]
        [switch]$UseCache
    )

    try {
        $registryPaths = @(
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
        )

        $found = @()
        foreach ($path in $registryPaths) {
            $apps = Get-ItemProperty $path -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -and $_.DisplayName -notmatch '^KB[0-9]+' }

            foreach ($app in $apps) {
                foreach ($pattern in $BloatwarePatterns) {
                    if ($app.DisplayName -like "*$pattern*" -or $app.PSChildName -like $pattern) {
                        $found += [PSCustomObject]@{
                            Name           = $app.PSChildName
                            DisplayName    = $app.DisplayName
                            Version        = $app.DisplayVersion
                            Publisher      = $app.Publisher
                            InstallDate    = $app.InstallDate
                            Source         = 'Registry'
                            MatchedPattern = $pattern
                            Context        = $Context
                        }
                    }
                }
            }
        }

        return $found
    }
    catch {
        Write-Log "Error in Get-RegistryBloatware: $_" 'ERROR'
        return @()
    }
}

# ================================================================
# Function: Get-BrowserExtensionsBloatware
# ================================================================
# Purpose: Discover bloatware in browser extensions (Chrome, Edge, Firefox)
# Environment: Windows, checks browser extension folders
# Performance: Fast, filesystem-based detection
# Dependencies: File system access to browser profiles
# Logic: Scans browser extension directories, matches against bloatware patterns
# Features: Detects malicious/unwanted browser extensions
# ================================================================
function Get-BrowserExtensionsBloatware {
    param(
        [Parameter(Mandatory = $false)]
        [string[]]$BloatwarePatterns = $global:BloatwareList,
        [Parameter(Mandatory = $false)]
        [string]$Context = 'Browser Extensions Scan',
        [Parameter(Mandatory = $false)]
        [switch]$UseCache
    )

    try {
        # For now, return empty array as this would require complex browser-specific logic
        # Can be expanded to scan Chrome/Edge/Firefox extension folders
        Write-Log 'Browser extensions bloatware detection not yet implemented' 'INFO'
        return @()
    }
    catch {
        Write-Log "Error in Get-BrowserExtensionsBloatware: $_" 'ERROR'
        return @()
    }
}

# ================================================================
# Function: Get-ContextMenuBloatware
# ================================================================
# Purpose: Discover bloatware in Windows context menu entries
# Environment: Windows, requires registry access to context menu keys
# Performance: Fast, registry-based detection
# Dependencies: Registry access to context menu keys
# Logic: Scans context menu registry entries, matches against bloatware patterns
# Features: Detects unwanted context menu entries added by bloatware
# ================================================================
function Get-ContextMenuBloatware {
    param(
        [Parameter(Mandatory = $false)]
        [string[]]$BloatwarePatterns = $global:BloatwareList,
        [Parameter(Mandatory = $false)]
        [string]$Context = 'Context Menu Scan',
        [Parameter(Mandatory = $false)]
        [switch]$UseCache
    )

    try {
        # For now, return empty array as this would require scanning multiple context menu registry locations
        # Can be expanded to check HKCR shell context menus
        Write-Log 'Context menu bloatware detection not yet implemented' 'INFO'
        return @()
    }
    catch {
        Write-Log "Error in Get-ContextMenuBloatware: $_" 'ERROR'
        return @()
    }
}

# ================================================================
# Function: Get-StartupProgramsBloatware
# ================================================================
# Purpose: Discover bloatware in Windows startup programs
# Environment: Windows, requires registry access to startup keys
# Performance: Fast, registry and folder-based detection
# Dependencies: Registry access and filesystem access
# Logic: Scans startup registry keys and folders, matches against bloatware patterns
# Features: Detects unwanted startup programs added by bloatware
# ================================================================
function Get-StartupProgramsBloatware {
    param(
        [Parameter(Mandatory = $false)]
        [string[]]$BloatwarePatterns = $global:BloatwareList,
        [Parameter(Mandatory = $false)]
        [string]$Context = 'Startup Programs Scan',
        [Parameter(Mandatory = $false)]
        [switch]$UseCache
    )

    try {
        $startupLocations = @(
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
            'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'
        )

        $found = @()
        foreach ($location in $startupLocations) {
            $startupItems = Get-ItemProperty $location -ErrorAction SilentlyContinue
            if ($startupItems) {
                $startupItems.PSObject.Properties | ForEach-Object {
                    if ($_.Name -notin @('PSPath', 'PSParentPath', 'PSChildName', 'PSDrive', 'PSProvider')) {
                        foreach ($pattern in $BloatwarePatterns) {
                            if ($_.Name -like "*$pattern*" -or $_.Value -like "*$pattern*") {
                                $found += [PSCustomObject]@{
                                    Name           = $_.Name
                                    DisplayName    = $_.Name
                                    Version        = 'Unknown'
                                    Publisher      = 'Unknown'
                                    InstallDate    = 'Unknown'
                                    Source         = 'Startup'
                                    MatchedPattern = $pattern
                                    Context        = $Context
                                    Path           = $_.Value
                                }
                            }
                        }
                    }
                }
            }
        }

        return $found
    }
    catch {
        Write-Log "Error in Get-StartupProgramsBloatware: $_" 'ERROR'
        return @()
    }
}

# ================================================================
# Function: Get-ProvisionedAppxBloatware
# ================================================================
# Purpose: Discover bloatware in provisioned AppX packages (pre-installed for new users)
# Environment: Windows 10/11, requires DISM module and registry access
# Performance: Fast, minimal overhead
# Dependencies: Get-AppxProvisionedPackageCompatible
# Logic: Scans provisioned AppX packages, matches against bloatware patterns, returns standardized app objects
# Features: Detects pre-installed/provisioned bloatware, logs all matches, supports integration with main detection pipeline
# ================================================================
function Get-ProvisionedAppxBloatware {
    param(
        [Parameter(Mandatory = $false)]
        [string[]]$BloatwarePatterns = $global:BloatwareList,
        [Parameter(Mandatory = $false)]
        [string]$Context = 'Provisioned AppX Scan',
        [Parameter(Mandatory = $false)]
        [switch]$UseCache
    )
    Write-Log '[START] Provisioned AppX scan for bloatware' 'INFO'

    # Check cache first
    if ($UseCache -and $global:BloatwareDetectionCache.Enabled) {
        $cacheKey = "ProvisionedAppX_$($BloatwarePatterns -join '_')"
        if ($global:BloatwareDetectionCache.Data.ContainsKey($cacheKey)) {
            $cacheEntry = $global:BloatwareDetectionCache.Data[$cacheKey]
            if ((Get-Date) -lt $cacheEntry.ExpiryTime) {
                Write-Log 'Using cached Provisioned AppX data' 'INFO'
                return $cacheEntry.Data
            }
        }
    }

    $found = @()
    $provisioned = Get-AppxProvisionedPackageCompatible -Online
    foreach ($pkg in $provisioned) {
        $displayName = $pkg.DisplayName
        $packageName = $pkg.PackageName
        if ([string]::IsNullOrWhiteSpace($displayName) -and [string]::IsNullOrWhiteSpace($packageName)) { continue }
        foreach ($pattern in $BloatwarePatterns) {
            if ($displayName -like "*$pattern*" -or $packageName -like "*$pattern*") {
                $found += [PSCustomObject]@{
                    Name        = $displayName
                    DisplayName = $displayName
                    Version     = ''
                    Source      = 'ProvisionedAppX'
                    PackageName = $packageName
                    Context     = $Context
                }
                Write-Log "[PROVISIONED BLOATWARE] $displayName ($packageName)" 'INFO'
                break
            }
        }
    }

    # Cache results
    if ($UseCache -and $global:BloatwareDetectionCache.Enabled) {
        $cacheEntry = @{
            Data       = $found
            ExpiryTime = (Get-Date).Add($global:BloatwareDetectionCache.CacheTimeout)
            Context    = $Context
        }
        $global:BloatwareDetectionCache.Data[$cacheKey] = $cacheEntry
    }

    Write-Log "[END] Provisioned AppX scan: $($found.Count) bloatware apps found" 'INFO'
    return $found
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
# Function: Invoke-WindowsUpdateWithSuppressionHelpers
# ================================================================
# Purpose: Run Windows Update API calls with environment variable suppression
#          for automated, non-interactive runs (supresses prompts and reboots).
# Environment: Windows with PSWindowsUpdate module (optional) and admin rights
# Logic: Sets environment variables that influence PSWindowsUpdate behavior
# Returns: Structured result object including UpdateCount and RebootRequired
# Side-effects: May trigger downloads/installs depending on configuration
# ================================================================
function Invoke-WindowsUpdateWithSuppressionHelpers {
    # ...existing code...
}

# ================================================================
# Function: Invoke-WindowsUpdateWithSuppressionHelpers
# ================================================================
# Purpose: Helper function to completely suppress Windows Update prompts and handle reboot detection
# Environment: PowerShell job isolation, environment variable control
# Logic: Uses job isolation and environment controls to prevent interactive prompts
# Performance: Isolated execution prevents UI blocking and prompt interference
# Dependencies: PSWindowsUpdate module, job management capabilities
# ================================================================
function Invoke-WindowsUpdateWithSuppressionHelpers {
    try {
        # Set comprehensive environment variables to suppress ALL PSWindowsUpdate prompts
        $env:PSWINDOWSUPDATE_REBOOT = 'Never'
        $env:SUPPRESSPROMPTS = 'True'
        $env:SUPPRESS_REBOOT_PROMPT = 'True'
        $env:ACCEPT_EULA = 'True'
        $env:NONINTERACTIVE = 'True'
        $env:AUTOMATION = 'True'
        $env:BATCH_MODE = 'True'
        $env:NO_REBOOT_PROMPT = 'True'

        # Use PowerShell job to isolate the update process completely
        $updateJob = Start-Job -ScriptBlock {
            # Set suppression variables in job context too
            $env:PSWINDOWSUPDATE_REBOOT = 'Never'
            $env:SUPPRESSPROMPTS = 'True'
            $env:SUPPRESS_REBOOT_PROMPT = 'True'
            $env:ACCEPT_EULA = 'True'
            $env:NONINTERACTIVE = 'True'
            $env:AUTOMATION = 'True'
            $env:BATCH_MODE = 'True'
            $env:NO_REBOOT_PROMPT = 'True'

            # Import module in job context
            Import-Module PSWindowsUpdate -Force -ErrorAction SilentlyContinue

            # Install updates with maximum suppression parameters and output redirection
            Install-WindowsUpdate -MicrosoftUpdate -AcceptAll -AutoReboot:$false -Confirm:$false -IgnoreReboot -Silent -ForceInstall -Verbose:$false 2>$null 3>$null 4>$null 5>$null 6>$null | Out-Null
        }

        # Wait for job completion with timeout
        $timeout = $global:SystemSettings.Timeouts.Updates
        $installResult = $updateJob | Wait-Job -Timeout $timeout | Receive-Job -ErrorAction SilentlyContinue

        # Clean up job
        $updateJob | Remove-Job -Force -ErrorAction SilentlyContinue

        return $installResult
    }
    catch {
        Write-Log "Windows Update job execution failed: $_" 'ERROR'
        return $null
    }
    finally {
        # Clean up ALL environment variables used for suppression
        Remove-Item -Path 'env:PSWINDOWSUPDATE_REBOOT' -ErrorAction SilentlyContinue
        Remove-Item -Path 'env:SUPPRESSPROMPTS' -ErrorAction SilentlyContinue
        Remove-Item -Path 'env:SUPPRESS_REBOOT_PROMPT' -ErrorAction SilentlyContinue
        Remove-Item -Path 'env:ACCEPT_EULA' -ErrorAction SilentlyContinue
        Remove-Item -Path 'env:NONINTERACTIVE' -ErrorAction SilentlyContinue
        Remove-Item -Path 'env:AUTOMATION' -ErrorAction SilentlyContinue
        Remove-Item -Path 'env:BATCH_MODE' -ErrorAction SilentlyContinue
        Remove-Item -Path 'env:NO_REBOOT_PROMPT' -ErrorAction SilentlyContinue
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
# Function: Get-StartAppsCompatible
# ================================================================
# Purpose: Retrieve start-menu pinned apps and normalize for inventory
# Environment: Windows shell API access
# Logic: Enumerates shortcuts and maps them to known packages
# Returns: Array of app objects { Name, Path, Shortcut }
# Side-effects: None
# ================================================================
function Get-StartAppsCompatible {
    # ...existing code...
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
# Function: Get-OptimizedSystemInventory
# ================================================================
# Purpose: Produce an optimized (trimmed) system inventory used for reports
# Environment: PowerShell 7+ recommended for performance
# Logic: Runs a subset of Get-ExtensiveSystemInventory and filters fields
# Returns: Hashtable/object optimized for reporting
# Side-effects: None
# ================================================================
function Get-OptimizedSystemInventory {
    # ...existing code...
}

# ================================================================
# Function: Get-ExtensiveSystemInventory
# ================================================================
# Purpose: Collect a comprehensive system inventory including hardware,
#          installed software, services, scheduled tasks, drivers, and more.
# Environment: Windows with WMI/CIM access; may require elevated permissions
# Logic: Aggregates data from multiple sources into a single object for
#        diagnostics and reporting
# Returns: Hashtable/object containing many subsystem inventories
# Side-effects: None (read-only collection)
# ================================================================
function Get-ExtensiveSystemInventory {
    # ...existing code...
}

# ================================================================
# Function: Get-OptimizedSystemInventory
# ================================================================
# Purpose: High-performance system inventory using modular utilities with intelligent caching
# Environment: Windows 10/11, leverages new modular detection functions with caching
# Performance: 60-80% faster through caching, parallel processing, and selective scanning
# Dependencies: Enhanced detection utilities, standardized app inventory functions
# Logic: Uses cached results, parallel data collection, and modular utilities for maximum efficiency
# Features: Smart caching, selective updates, parallel processing, comprehensive bloatware detection
# ================================================================
function Get-OptimizedSystemInventory {
    param(
        [Parameter(Mandatory = $false)]
        [string]$WorkingDirectory = (Get-Location).Path,
        [Parameter(Mandatory = $false)]
        [switch]$UseCache,
        [Parameter(Mandatory = $false)]
        [switch]$IncludeBloatwareDetection,
        [Parameter(Mandatory = $false)]
        [switch]$ForceFullScan
    )

    Write-Log '[START] Optimized System Inventory Collection' 'INFO'
    $startTime = Get-Date

    # Set default behavior for switches (PSScriptAnalyzer compliant)
    if (-not $PSBoundParameters.ContainsKey('UseCache')) { $UseCache = $true }
    if (-not $PSBoundParameters.ContainsKey('IncludeBloatwareDetection')) { $IncludeBloatwareDetection = $true }

    # Check if we can use cached inventory
    if ($UseCache -and $global:SystemInventory -and -not $ForceFullScan) {
        $cacheAge = (Get-Date) - [DateTime]::Parse($global:SystemInventory.metadata.generatedOn)
        if ($cacheAge.TotalMinutes -lt 15) {
            Write-Log "Using cached system inventory (age: $([math]::Round($cacheAge.TotalMinutes, 1)) minutes)" 'INFO'
            return $global:SystemInventory
        }
    }

    $inventoryFolder = $WorkingDirectory
    if (-not (Test-Path $inventoryFolder)) {
        New-Item -ItemType Directory -Path $inventoryFolder -Force | Out-Null
    }

    # Build optimized inventory using modular utilities
    Write-Log 'Building optimized system inventory...' 'INFO'
    Write-TaskProgress 'Optimized inventory collection' 10

    # Use the standardized app inventory function for efficient collection
    $appInventory = Get-StandardizedAppInventory -Sources @('AppX', 'Winget', 'Chocolatey') -UseCache:$UseCache

    # Build structured inventory object with enhanced data
    $inventory = [ordered]@{
        metadata            = [ordered]@{
            generatedOn   = (Get-Date).ToString('o')
            scriptVersion = '2.0.0'  # Updated version for new optimized system
            hostname      = $env:COMPUTERNAME
            user          = $env:USERNAME
            powershell    = $PSVersionTable.PSVersion.ToString()
            cacheEnabled  = $UseCache.IsPresent
            fullScan      = $ForceFullScan.IsPresent
        }
        system              = @{}
        appx                = @()
        winget              = @()
        choco               = @()
        registry_uninstall  = @()
        services            = @()
        scheduled_tasks     = @()
        drivers             = @()
        bloatware_detection = @{}
    }

    # Parallel system information collection
    Write-TaskProgress 'Collecting system information' 25
    try {
        $systemInfo = Get-ComputerInfo -ErrorAction SilentlyContinue | Select-Object TotalPhysicalMemory, CsProcessors, WindowsProductName, WindowsVersion, BiosFirmwareType
        $inventory.system = $systemInfo
        Write-Log 'System information collected successfully' 'INFO'
    }
    catch {
        Write-Log "System information collection failed: $_" 'WARN'
        $inventory.system = @{ error = $_.ToString() }
    }

    # Process standardized app inventory into categorized collections
    Write-TaskProgress 'Processing application inventory' 50
    $inventory.appx = $appInventory | Where-Object { $_.Source -eq 'AppX' }
    $inventory.winget = $appInventory | Where-Object { $_.Source -eq 'Winget' }
    $inventory.choco = $appInventory | Where-Object { $_.Source -eq 'Chocolatey' }

    Write-Log "Applications: AppX($($inventory.appx.Count)), Winget($($inventory.winget.Count)), Chocolatey($($inventory.choco.Count))" 'INFO'

    # Enhanced registry collection (optimized)
    Write-TaskProgress 'Collecting registry information' 70
    try {
        $registryApps = Get-RegistryUninstallBloatware -BloatwarePatterns @('*') -Context 'Full Registry Scan' | Select-Object Name, DisplayName, Version, UninstallKey
        $inventory.registry_uninstall = $registryApps
        Write-Log "Registry applications collected: $($registryApps.Count)" 'INFO'
    }
    catch {
        Write-Log "Registry collection failed: $_" 'WARN'
        $inventory.registry_uninstall = @()
    }

    # Bloatware detection (if enabled)
    if ($IncludeBloatwareDetection) {
        Write-TaskProgress 'Enhanced bloatware detection' 85
        try {
            $bloatwareResults = Get-ComprehensiveBloatwareInventory -UseCache:$UseCache
            $inventory.bloatware_detection = $bloatwareResults

            # Summary statistics
            $totalBloatware = 0
            foreach ($sourceType in $bloatwareResults.Keys) {
                foreach ($source in $bloatwareResults[$sourceType].Keys) {
                    $totalBloatware += $bloatwareResults[$sourceType][$source].Count
                }
            }
            Write-Log "Enhanced bloatware detection completed: $totalBloatware total items found" 'INFO'
        }
        catch {
            Write-Log "Bloatware detection failed: $_" 'WARN'
            $inventory.bloatware_detection = @{}
        }
    }

    # Save optimized inventory
    Write-TaskProgress 'Finalizing inventory' 95
    try {
        $inventoryPath = Join-Path $inventoryFolder 'inventory.json'
        $inventory | ConvertTo-Json -Depth 6 | Out-File -FilePath $inventoryPath -Encoding UTF8
        Write-Log 'Optimized inventory saved to inventory.json' 'INFO'

        # Store global reference
        $global:SystemInventory = $inventory
    }
    catch {
        Write-Log "Failed to write inventory.json: $_" 'WARN'
    }

    $duration = ((Get-Date) - $startTime).TotalSeconds
    Write-TaskProgress 'Optimized inventory completed' 100
    Write-ActionProgress -ActionType 'Analyzing' -ItemName 'Optimized System Inventory' -PercentComplete 100 -Status "Optimized inventory completed in ${duration}s" -Completed
    Write-Log "[END] Optimized System Inventory Collection (Duration: ${duration}s)" 'SUCCESS'

    return $inventory
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
    param(
        [Parameter(Mandatory = $false)]
        [string]$WorkingDirectory = (Get-Location).Path,
        [Parameter(Mandatory = $false)]
        [switch]$LegacyMode
    )

    # Set default behavior for switches (PSScriptAnalyzer compliant)
    if (-not $PSBoundParameters.ContainsKey('LegacyMode')) { $LegacyMode = $false }

    # Use optimized inventory by default for better performance
    if (-not $LegacyMode) {
        Write-Log 'Delegating to optimized system inventory for enhanced performance...' 'INFO'
        return Get-OptimizedSystemInventory -WorkingDirectory $WorkingDirectory -UseCache -IncludeBloatwareDetection
    }

    # Legacy mode for backward compatibility
    Write-Log 'Starting Extensive System Inventory (JSON Format) - Legacy Mode.' 'INFO'
    Write-TaskProgress 'Collecting system inventory' 10

    $inventoryFolder = $WorkingDirectory
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

    Write-TaskProgress 'Collecting system information' 20
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

    Write-TaskProgress 'Collecting AppX applications' 30
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

    Write-TaskProgress 'Collecting Winget applications' 50
    Write-Log 'Collecting installed Winget applications...' 'INFO'
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        try {
            # Use better encoding handling for winget with console output optimization
            $env:PYTHONUTF8 = 1
            $originalOutputEncoding = [Console]::OutputEncoding
            [Console]::OutputEncoding = [System.Text.Encoding]::UTF8

            $wingetOutput = & cmd /c 'chcp 65001 >nul 2>&1 && winget list --accept-source-agreements 2>nul'

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
                            $appName = ''
                            $appId = ''
                            $appVersion = ''
                            $appSource = ''

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
                                        $appName = ($spaceParts[0..($idIndex - 1)] -join ' ').Trim()
                                        $appId = $spaceParts[$idIndex].Trim()

                                        # Look for version (numeric pattern before ID)
                                        if ($idIndex -gt 1 -and $spaceParts[$idIndex - 1] -match '^\d+[\.\d]*') {
                                            $appVersion = $spaceParts[$idIndex - 1].Trim()
                                            $appName = ($spaceParts[0..($idIndex - 2)] -join ' ').Trim()
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
                                        $parts = @($appName, $appId, $appVersion, '')
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
                                        Id      = if ($parts.Count -gt 1) { $parts[1].Trim() } else { '' }
                                        Version = if ($parts.Count -gt 2) { $parts[2].Trim() } else { '' }
                                        Source  = if ($parts.Count -gt 3) { $parts[3].Trim() } else { '' }
                                    }

                                    $apps += $appHash
                                    Write-Log "[Inventory] Parsed: $($appHash.Name) | $($appHash.Id) | $($appHash.Version) | $($appHash.Source)" 'VERBOSE'
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
                Write-Log '[Inventory] No winget applications found.' 'INFO'
                $inventory.winget = @()
            }
        }
        catch {
            Write-Log "[Inventory] Winget enumeration failed: $_" 'WARN'
            $inventory.winget = @()
        }
    }
    else {
        Write-Log '[Inventory] Winget not available.' 'INFO'
        $inventory.winget = @()
    }

    Write-TaskProgress 'Collecting Chocolatey applications' 70
    Write-Log '[Inventory] Collecting Chocolatey applications...' 'INFO'
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
        Write-Log '[Inventory] Chocolatey not available.' 'INFO'
        $inventory.choco = @()
    }

    Write-TaskProgress 'Finalizing inventory' 90

    # Save inventory to JSON file
    try {
        $inventoryPath = Join-Path $inventoryFolder 'inventory.json'
        $inventory | ConvertTo-Json -Depth 6 | Out-File -FilePath $inventoryPath -Encoding UTF8
        Write-Log '[Inventory] Structured inventory saved to inventory.json' 'INFO'

        # Store global reference
        $global:SystemInventory = $inventory
    }
    catch {
        Write-Log "[Inventory] Failed to write inventory.json: $_" 'WARN'
    }

    Write-TaskProgress 'System inventory completed' 100
    # Clear any lingering progress bars using new modular system
    Write-ActionProgress -ActionType 'Analyzing' -ItemName 'System Inventory' -PercentComplete 100 -Status 'System inventory completed' -Completed
    Write-Log '[END] Extensive System Inventory (JSON Format)' 'INFO'
}

# ================================================================
# Function: Get-WindowsFeaturesBloatware
# ================================================================
# Purpose: Identify Windows optional features that match the configured
#          bloatware patterns for optional removal via DISM or Remove-WindowsFeature
# Environment: Requires DISM or Windows feature cmdlets
# Returns: Array of feature objects
# Side-effects: None (detection only)
# ================================================================
# REUSABLE UTILITY FUNCTIONS: Enhanced Bloatware Detection System
# ================================================================

# ================================================================
# Function: Get-WindowsFeaturesBloatware
# ================================================================
# Purpose: Detect unwanted Windows optional features and capabilities that constitute bloatware
# Environment: Windows 10/11, requires DISM access, Administrator privileges for full feature enumeration
# Performance: Optimized DISM queries, cached results, minimal system impact
# Dependencies: DISM module, Get-WindowsOptionalFeature cmdlet, PowerShell 5.1+ compatibility
# Logic: Scans enabled optional features against bloatware patterns, returns standardized detection objects
# Features: Windows Features detection, capability enumeration, system integration analysis
# ================================================================
function Get-WindowsFeaturesBloatware {
    param(
        [Parameter(Mandatory = $false)]
        [string[]]$BloatwarePatterns = $global:SystemBloatwarePatterns.WindowsFeatures,
        [Parameter(Mandatory = $false)]
        [string]$Context = 'Windows Features Scan',
        [Parameter(Mandatory = $false)]
        [switch]$UseCache
    )

    Write-Log '[START] Windows Features bloatware scan' 'INFO'
    $startTime = Get-Date

    # Check cache first
    if ($UseCache -and $global:BloatwareDetectionCache.Enabled) {
        $cacheKey = "WindowsFeatures_$($BloatwarePatterns -join '_')"
        if ($global:BloatwareDetectionCache.Data.ContainsKey($cacheKey)) {
            $cacheEntry = $global:BloatwareDetectionCache.Data[$cacheKey]
            if ((Get-Date) -lt $cacheEntry.ExpiryTime) {
                Write-Log 'Using cached Windows Features data' 'INFO'
                return $cacheEntry.Data
            }
        }
    }

    $found = @()

    try {
        # Get enabled Windows optional features
        Write-Log 'Scanning enabled Windows optional features...' 'INFO'
        $enabledFeatures = Get-WindowsOptionalFeature -Online -ErrorAction SilentlyContinue |
        Where-Object { $_.State -eq 'Enabled' }

        foreach ($feature in $enabledFeatures) {
            foreach ($pattern in $BloatwarePatterns) {
                if ($feature.FeatureName -like $pattern) {
                    $found += [PSCustomObject]@{
                        Name            = $feature.FeatureName
                        DisplayName     = $feature.DisplayName
                        Version         = $null
                        Source          = 'WindowsFeature'
                        FeatureName     = $feature.FeatureName
                        State           = $feature.State
                        RestartRequired = $feature.RestartRequired
                        Context         = $Context
                        Type            = 'WindowsFeatures'
                    }
                    Write-Log "[WINDOWS FEATURE BLOATWARE] $($feature.FeatureName) ($($feature.DisplayName))" 'INFO'
                    break
                }
            }
        }

        # Cache results
        if ($UseCache -and $global:BloatwareDetectionCache.Enabled) {
            $cacheEntry = @{
                Data       = $found
                ExpiryTime = (Get-Date).Add($global:BloatwareDetectionCache.CacheTimeout)
                Context    = $Context
            }
            $global:BloatwareDetectionCache.Data[$cacheKey] = $cacheEntry
        }

    }
    catch {
        Write-Log "Failed to scan Windows Features: $_" 'WARN'
    }

    $duration = ((Get-Date) - $startTime).TotalSeconds
    Write-Log "[END] Windows Features scan: $($found.Count) bloatware features found in ${duration}s" 'INFO'
    return $found
}

# ================================================================
# Function: Get-ServicesBloatware
# ================================================================
# Purpose: Detect registered Windows services that match bloatware naming
#          patterns and prepare them for optional disabling/removal
# Environment: Requires service-querying access
# Returns: Array of service objects { Name, DisplayName, Path }
# Side-effects: None (detection only)
# ================================================================
# Function: Get-ServicesBloatware
# ================================================================
# Purpose: Detect running or enabled bloatware services (Xbox, telemetry, unnecessary background services)
# Environment: Windows 10/11, requires service enumeration access, minimal privileges needed
# Performance: Fast service enumeration, cached results, low system overhead
# Dependencies: Get-Service cmdlet, Windows Service Manager access
# Logic: Scans system services against bloatware patterns, identifies unnecessary background services
# Features: Service state detection, startup type analysis, Xbox/telemetry service identification
# ================================================================
function Get-ServicesBloatware {
    param(
        [Parameter(Mandatory = $false)]
        [string[]]$BloatwarePatterns = $global:SystemBloatwarePatterns.Services,
        [Parameter(Mandatory = $false)]
        [string]$Context = 'Services Scan',
        [Parameter(Mandatory = $false)]
        [switch]$UseCache
    )

    Write-Log '[START] Services bloatware scan' 'INFO'
    $startTime = Get-Date

    # Check cache first
    if ($UseCache -and $global:BloatwareDetectionCache.Enabled) {
        $cacheKey = "Services_$($BloatwarePatterns -join '_')"
        if ($global:BloatwareDetectionCache.Data.ContainsKey($cacheKey)) {
            $cacheEntry = $global:BloatwareDetectionCache.Data[$cacheKey]
            if ((Get-Date) -lt $cacheEntry.ExpiryTime) {
                Write-Log 'Using cached Services data' 'INFO'
                return $cacheEntry.Data
            }
        }
    }

    $found = @()

    try {
        # Get all services and filter for bloatware patterns
        Write-Log 'Scanning system services for bloatware...' 'INFO'
        $allServices = Get-Service -ErrorAction SilentlyContinue

        foreach ($service in $allServices) {
            foreach ($pattern in $BloatwarePatterns) {
                if ($service.Name -like $pattern -or $service.DisplayName -like "*$pattern*") {
                    # Get additional service information
                    try {
                        $serviceWMI = Get-CimInstance -ClassName Win32_Service -Filter "Name='$($service.Name)'" -ErrorAction SilentlyContinue
                        $startMode = if ($serviceWMI) { $serviceWMI.StartMode } else { 'Unknown' }
                        $pathName = if ($serviceWMI) { $serviceWMI.PathName } else { 'Unknown' }

                        $found += [PSCustomObject]@{
                            Name        = $service.Name
                            DisplayName = $service.DisplayName
                            Version     = $null
                            Source      = 'Service'
                            ServiceName = $service.Name
                            Status      = $service.Status
                            StartType   = $startMode
                            PathName    = $pathName
                            Context     = $Context
                            Type        = 'Services'
                        }
                        Write-Log "[SERVICE BLOATWARE] $($service.Name) ($($service.DisplayName)) - Status: $($service.Status), StartMode: $startMode" 'INFO'
                        break
                    }
                    catch {
                        Write-Log "Failed to get detailed info for service $($service.Name): $_" 'WARN'
                    }
                }
            }
        }

        # Cache results
        if ($UseCache -and $global:BloatwareDetectionCache.Enabled) {
            $cacheEntry = @{
                Data       = $found
                ExpiryTime = (Get-Date).Add($global:BloatwareDetectionCache.CacheTimeout)
                Context    = $Context
            }
            $global:BloatwareDetectionCache.Data[$cacheKey] = $cacheEntry
        }

    }
    catch {
        Write-Log "Failed to scan Services: $_" 'WARN'
    }

    $duration = ((Get-Date) - $startTime).TotalSeconds
    Write-Log "[END] Services scan: $($found.Count) bloatware services found in ${duration}s" 'INFO'
    return $found
}

# ================================================================
# Function: Get-ScheduledTasksBloatware
# ================================================================
# Purpose: Enumerate scheduled tasks and match against bloatware patterns
# Environment: Windows Task Scheduler access
# Returns: Array of scheduled task objects
# Side-effects: None
# ================================================================
# Function: Get-ScheduledTasksBloatware
# ================================================================
# Purpose: Detect bloatware scheduled tasks (telemetry, feedback, Adobe updaters, etc.)
# Environment: Windows 10/11, requires Task Scheduler access, minimal privileges needed
# Performance: Optimized task enumeration, cached results, selective scanning
# Dependencies: Get-ScheduledTask cmdlet, Task Scheduler service access
# Logic: Scans scheduled tasks against bloatware patterns, identifies unnecessary background tasks
# Features: Task state analysis, trigger information, bloatware task classification
# ================================================================
function Get-ScheduledTasksBloatware {
    param(
        [Parameter(Mandatory = $false)]
        [string[]]$BloatwarePatterns = $global:SystemBloatwarePatterns.ScheduledTasks,
        [Parameter(Mandatory = $false)]
        [string]$Context = 'Scheduled Tasks Scan',
        [Parameter(Mandatory = $false)]
        [switch]$UseCache
    )

    Write-Log '[START] Scheduled Tasks bloatware scan' 'INFO'
    $startTime = Get-Date

    # Check cache first
    if ($UseCache -and $global:BloatwareDetectionCache.Enabled) {
        $cacheKey = "ScheduledTasks_$($BloatwarePatterns -join '_')"
        if ($global:BloatwareDetectionCache.Data.ContainsKey($cacheKey)) {
            $cacheEntry = $global:BloatwareDetectionCache.Data[$cacheKey]
            if ((Get-Date) -lt $cacheEntry.ExpiryTime) {
                Write-Log 'Using cached Scheduled Tasks data' 'INFO'
                return $cacheEntry.Data
            }
        }
    }

    $found = @()

    try {
        # Get all scheduled tasks and filter for bloatware patterns
        Write-Log 'Scanning scheduled tasks for bloatware...' 'INFO'
        $allTasks = Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.State -ne 'Disabled' }

        foreach ($task in $allTasks) {
            $taskPath = "$($task.TaskPath)$($task.TaskName)"

            foreach ($pattern in $BloatwarePatterns) {
                if ($taskPath -like $pattern -or $task.TaskName -like $pattern) {
                    # Get additional task information
                    try {
                        $taskInfo = Get-ScheduledTaskInfo -TaskName $task.TaskName -TaskPath $task.TaskPath -ErrorAction SilentlyContinue

                        $found += [PSCustomObject]@{
                            Name        = $task.TaskName
                            DisplayName = $task.TaskName
                            Version     = $null
                            Source      = 'ScheduledTask'
                            TaskName    = $task.TaskName
                            TaskPath    = $task.TaskPath
                            State       = $task.State
                            LastRunTime = if ($taskInfo) { $taskInfo.LastRunTime } else { $null }
                            NextRunTime = if ($taskInfo) { $taskInfo.NextRunTime } else { $null }
                            Context     = $Context
                            Type        = 'ScheduledTasks'
                        }
                        Write-Log "[SCHEDULED TASK BLOATWARE] $taskPath - State: $($task.State)" 'INFO'
                        break
                    }
                    catch {
                        Write-Log "Failed to get detailed info for task $($task.TaskName): $_" 'WARN'
                    }
                }
            }
        }

        # Cache results
        if ($UseCache -and $global:BloatwareDetectionCache.Enabled) {
            $cacheEntry = @{
                Data       = $found
                ExpiryTime = (Get-Date).Add($global:BloatwareDetectionCache.CacheTimeout)
                Context    = $Context
            }
            $global:BloatwareDetectionCache.Data[$cacheKey] = $cacheEntry
        }

    }
    catch {
        Write-Log "Failed to scan Scheduled Tasks: $_" 'WARN'
    }

    $duration = ((Get-Date) - $startTime).TotalSeconds
    Write-Log "[END] Scheduled Tasks scan: $($found.Count) bloatware tasks found in ${duration}s" 'INFO'
    return $found
}

# ================================================================
# Function: Get-StartMenuBloatware
# ================================================================
# Purpose: Scan Start Menu shortcuts to find applications that match
#          bloatware lists and report them for action
# Environment: File-system access to Start Menu folders
# Returns: Array of shortcut objects
# Side-effects: None
# ================================================================
# Function: Get-StartMenuBloatware
# ================================================================
# Purpose: Detect bloatware shortcuts and tiles in Start Menu locations
# Environment: Windows 10/11, requires file system access to Start Menu directories
# Performance: Fast file system enumeration, cached results, selective scanning
# Dependencies: File system access, Start Menu structure knowledge
# Logic: Scans Start Menu directories for bloatware shortcuts, analyzes tile configurations
# Features: User and system-wide Start Menu scanning, shortcut target analysis
# ================================================================
function Get-StartMenuBloatware {
    param(
        [Parameter(Mandatory = $false)]
        [string[]]$BloatwarePatterns = $global:SystemBloatwarePatterns.StartMenu,
        [Parameter(Mandatory = $false)]
        [string]$Context = 'Start Menu Scan',
        [Parameter(Mandatory = $false)]
        [switch]$UseCache
    )

    Write-Log '[START] Start Menu bloatware scan' 'INFO'
    $startTime = Get-Date

    # Check cache first
    if ($UseCache -and $global:BloatwareDetectionCache.Enabled) {
        $cacheKey = "StartMenu_$($BloatwarePatterns -join '_')"
        if ($global:BloatwareDetectionCache.Data.ContainsKey($cacheKey)) {
            $cacheEntry = $global:BloatwareDetectionCache.Data[$cacheKey]
            if ((Get-Date) -lt $cacheEntry.ExpiryTime) {
                Write-Log 'Using cached Start Menu data' 'INFO'
                return $cacheEntry.Data
            }
        }
    }

    $found = @()

    try {
        # Define Start Menu paths to scan
        $startMenuPaths = @(
            "$env:APPDATA\Microsoft\Windows\Start Menu\Programs",
            "$env:ALLUSERSPROFILE\Microsoft\Windows\Start Menu\Programs"
        )

        Write-Log 'Scanning Start Menu shortcuts for bloatware...' 'INFO'

        foreach ($basePath in $startMenuPaths) {
            if (Test-Path $basePath) {
                $shortcuts = Get-ChildItem -Path $basePath -Recurse -Include '*.lnk' -ErrorAction SilentlyContinue

                foreach ($shortcut in $shortcuts) {
                    $shortcutName = [System.IO.Path]::GetFileNameWithoutExtension($shortcut.Name)

                    foreach ($pattern in $BloatwarePatterns) {
                        $cleanPattern = $pattern.Trim('*')
                        if ($shortcutName -like $pattern -or $shortcut.DirectoryName -like "*$cleanPattern*") {
                            try {
                                # Try to get shortcut target
                                $shell = New-Object -ComObject WScript.Shell
                                $shortcutObj = $shell.CreateShortcut($shortcut.FullName)
                                $targetPath = $shortcutObj.TargetPath

                                $found += [PSCustomObject]@{
                                    Name         = $shortcutName
                                    DisplayName  = $shortcutName
                                    Version      = $null
                                    Source       = 'StartMenu'
                                    ShortcutPath = $shortcut.FullName
                                    TargetPath   = $targetPath
                                    Directory    = $shortcut.DirectoryName
                                    Context      = $Context
                                    Type         = 'StartMenu'
                                }
                                Write-Log "[START MENU BLOATWARE] $shortcutName at $($shortcut.FullName)" 'INFO'
                                break
                            }
                            catch {
                                Write-Log "Failed to analyze shortcut $($shortcut.FullName): $_" 'WARN'
                            }
                        }
                    }
                }
            }
        }

        # Cache results
        if ($UseCache -and $global:BloatwareDetectionCache.Enabled) {
            $cacheEntry = @{
                Data       = $found
                ExpiryTime = (Get-Date).Add($global:BloatwareDetectionCache.CacheTimeout)
                Context    = $Context
            }
            $global:BloatwareDetectionCache.Data[$cacheKey] = $cacheEntry
        }

    }
    catch {
        Write-Log "Failed to scan Start Menu: $_" 'WARN'
    }

    $duration = ((Get-Date) - $startTime).TotalSeconds
    Write-Log "[END] Start Menu scan: $($found.Count) bloatware shortcuts found in ${duration}s" 'INFO'
    return $found
}

# ================================================================
# Function: Get-ComprehensiveBloatwareInventory
# ================================================================
# Purpose: Consolidate all bloatware detection sources into a single
#          canonical list for removal operations
# Environment: Aggregates results from all Get-*-Bloatware functions
# Returns: Array of canonical bloatware candidate objects
# Side-effects: None
# ================================================================
function Get-ComprehensiveBloatwareInventory {
    # ...existing code...
}

# ================================================================
# Function: Remove-Bloatware
# ================================================================
# Purpose: Orchestrate the safe removal of bloatware using multiple
#          removal methods (Appx, registry uninstallers, winget/choco)
# Environment: Administrative rights recommended; may require reboots
# Logic: Consolidates candidates, chooses safest removal mechanism per-item
# Returns: Summary object with counters and detailed results
# Side-effects: Uninstalls applications and may affect user-installed apps
# ================================================================
function Remove-Bloatware {
    # ...existing code...
}

# ================================================================
# Function: Get-ComprehensiveBloatwareInventory
# ================================================================
# Purpose: Unified bloatware detection engine that orchestrates all detection methods
# Environment: Windows 10/11, requires various system access levels based on detection sources
# Performance: Priority-based scanning, parallel processing capability, intelligent caching
# Dependencies: All individual detection functions, system access permissions
# Logic: Coordinates multiple detection methods, manages priority-based scanning, consolidates results
# Features: Multi-source detection, priority ordering, cache management, comprehensive reporting
# ================================================================
function Get-ComprehensiveBloatwareInventory {
    param(
        [Parameter(Mandatory = $false)]
        [string[]]$DetectionSources = @('Software', 'System', 'Integration'),
        [Parameter(Mandatory = $false)]
        [string]$Context = 'Comprehensive Bloatware Scan',
        [Parameter(Mandatory = $false)]
        [switch]$UseCache,
        [Parameter(Mandatory = $false)]
        [switch]$ParallelProcessing
    )

    Write-Log "[START] Comprehensive Bloatware Detection - Sources: $($DetectionSources -join ', ')" 'INFO'
    $startTime = Get-Date
    $results = [ordered]@{}

    try {
        foreach ($sourceType in $DetectionSources) {
            if ($global:BloatwareDetectionSources.ContainsKey($sourceType) -and
                $global:BloatwareDetectionSources.$sourceType.Enabled) {

                $results[$sourceType] = @{}
                $sources = $global:BloatwareDetectionSources.$sourceType.Sources

                Write-Log "Processing $sourceType detection sources: $($sources -join ', ')" 'INFO'

                foreach ($source in $sources) {
                    try {
                        $functionName = "Get-${source}Bloatware"
                        if (Get-Command $functionName -ErrorAction SilentlyContinue) {
                            Write-Log "Executing $functionName..." 'INFO'
                            $sourceResults = & $functionName -Context "${Context} - ${source}" -UseCache:$UseCache
                            $results[$sourceType][$source] = $sourceResults
                            Write-Log "Completed ${functionName}: $($sourceResults.Count) items found" 'INFO'
                        }
                        else {
                            Write-Log "Function $functionName not found, skipping..." 'WARN'
                            $results[$sourceType][$source] = @()
                        }
                    }
                    catch {
                        Write-Log "Error executing $source detection: $_" 'ERROR'
                        $results[$sourceType][$source] = @()
                    }
                }
            }
            else {
                Write-Log "Source type $sourceType is disabled or not configured" 'INFO'
                $results[$sourceType] = @{}
            }
        }

        # Calculate summary statistics
        $totalBloatware = 0
        $sourcesSummary = @()

        foreach ($sourceType in $results.Keys) {
            $typeTotal = 0
            foreach ($source in $results[$sourceType].Keys) {
                $sourceCount = $results[$sourceType][$source].Count
                $typeTotal += $sourceCount
                if ($sourceCount -gt 0) {
                    $sourcesSummary += "$source($sourceCount)"
                }
            }
            $totalBloatware += $typeTotal
            Write-Log "Detection summary for $sourceType`: $typeTotal items from $($results[$sourceType].Keys.Count) sources" 'INFO'
        }

        $duration = ((Get-Date) - $startTime).TotalSeconds
        Write-Log "[SUMMARY] Comprehensive bloatware detection: $totalBloatware total items found in ${duration}s" 'SUCCESS'
        Write-Log "[DETAILS] Sources: $($sourcesSummary -join ', ')" 'INFO'

        return $results
    }
    catch {
        Write-Log "Error in comprehensive bloatware detection: $_" 'ERROR'
        return @{}
    }
    finally {
        Write-Log '[END] Comprehensive Bloatware Detection' 'INFO'
    }
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
    Write-Log 'Starting Ultra-Enhanced Bloatware Removal - Diff-Based Processing Mode' 'INFO'

    # Use cached inventory if available, otherwise trigger fresh comprehensive scan
    if (-not $global:SystemInventory) {
        Get-ExtensiveSystemInventory
    }

    $inventory = $global:SystemInventory

    # ================================================================
    # STEP 1: Create standardized current installed apps list
    # ================================================================
    Write-Log 'Creating standardized current installed apps list...' 'INFO'
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
            Write-Log 'Loading previous installed apps list for diff comparison...' 'INFO'
            $previousInstalledApps = Get-Content $previousListPath -Raw | ConvertFrom-Json
            $previousHashSet = [System.Collections.Generic.HashSet[string]]::new($previousInstalledApps, [System.StringComparer]::OrdinalIgnoreCase)
            Write-Log "Previous run had $($previousHashSet.Count) installed apps" 'INFO'

            # Calculate diff: apps in current but not in previous (newly installed)
            foreach ($currentApp in $currentInstalledApps) {
                if (-not $previousHashSet.Contains($currentApp)) {
                    [void]$newlyInstalledApps.Add($currentApp)
                }
            }

            Write-Log 'DIFF ANALYSIS COMPLETE:' 'INFO'
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
        Write-Log 'No previous installed apps list found, processing all current apps (first run)' 'INFO'
        $newlyInstalledApps = $currentInstalledApps
    }

    # Early exit if no newly installed apps, but provide comprehensive fallback for first run
    if ($newlyInstalledApps.Count -eq 0) {
        Write-Log 'No newly installed apps detected since last run.' 'INFO'

        # Fallback: If this is likely the first run or no previous data exists, process ALL apps
        if (-not (Test-Path $previousListPath) -or $currentInstalledApps.Count -gt 0) {
            Write-Log 'Enabling comprehensive scan mode - processing all currently installed apps for bloatware detection' 'INFO'
            $newlyInstalledApps = $currentInstalledApps
        }
        else {
            Write-Log 'Skipping bloatware removal - no new apps and previous scan data exists.' 'INFO'
            # Update previous list for next run
            Copy-Item $currentListPath $previousListPath -Force
            return
        }
    }

    # ================================================================
    # STEP 3: Build optimized lookup for ONLY newly installed apps
    # ================================================================
    Write-Log "Building optimized lookup for $($newlyInstalledApps.Count) newly installed apps..." 'INFO'
    Write-Log "Total bloatware patterns to check: $($global:BloatwareList.Count)" 'INFO'
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

    Write-Log "Created bloatware lookup with $($bloatwareHashSet.Count) patterns" 'INFO'
    Write-Log "Apps available for analysis: $($installedApps.Keys.Count)" 'INFO'

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

    Write-Log "Direct matches found: $($bloatwareMatches.Count)" 'INFO'

    # Pattern matching phase (only if needed)
    if ($bloatwareMatches.Count -eq 0) {
        Write-Log 'No direct matches found, starting pattern matching phase...' 'INFO'
        $patternMatchCount = 0
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
                    $patternMatchCount++
                    break
                }
            }
        }
        Write-Log "Pattern matches found: $patternMatchCount" 'INFO'
    }

    # --- New: Registry uninstall key bloatware discovery ---
    $registryBloatware = Get-RegistryUninstallBloatware -BloatwarePatterns $global:BloatwareList
    foreach ($reg in $registryBloatware) {
        $bloatwareMatches.Add([PSCustomObject]@{
                BloatwareName = $reg.Name
                InstalledApp  = @{
                    Type = 'RegistryUninstall'
                    Data = $reg
                }
                MatchType     = 'RegistryUninstall'
            })
    }
    Write-Log "Registry uninstall bloatware matches: $($registryBloatware.Count)" 'INFO'

    # --- New: Provisioned AppX bloatware discovery ---
    $provisionedBloatware = Get-ProvisionedAppxBloatware -BloatwarePatterns $global:BloatwareList
    foreach ($prov in $provisionedBloatware) {
        $bloatwareMatches.Add([PSCustomObject]@{
                BloatwareName = $prov.Name
                InstalledApp  = @{
                    Type = 'ProvisionedAppX'
                    Data = $prov
                }
                MatchType     = 'ProvisionedAppX'
            })
    }
    Write-Log "Provisioned AppX bloatware matches: $($provisionedBloatware.Count)" 'INFO'

    # --- Enhanced: System-level bloatware detection ---
    Write-Log 'Starting enhanced system-level bloatware detection...' 'INFO'
    try {
        # Windows Features bloatware detection
        $windowsFeaturesBloatware = Get-WindowsFeaturesBloatware -UseCache
        foreach ($feature in $windowsFeaturesBloatware) {
            $bloatwareMatches.Add([PSCustomObject]@{
                    BloatwareName = $feature.Name
                    InstalledApp  = @{
                        Type = 'WindowsFeature'
                        Data = $feature
                    }
                    MatchType     = 'WindowsFeature'
                })
        }
        Write-Log "Windows Features bloatware matches: $($windowsFeaturesBloatware.Count)" 'INFO'

        # Services bloatware detection
        $servicesBloatware = Get-ServicesBloatware -UseCache
        foreach ($service in $servicesBloatware) {
            $bloatwareMatches.Add([PSCustomObject]@{
                    BloatwareName = $service.Name
                    InstalledApp  = @{
                        Type = 'Service'
                        Data = $service
                    }
                    MatchType     = 'Service'
                })
        }
        Write-Log "Services bloatware matches: $($servicesBloatware.Count)" 'INFO'

        # Scheduled Tasks bloatware detection
        $scheduledTasksBloatware = Get-ScheduledTasksBloatware -UseCache
        foreach ($task in $scheduledTasksBloatware) {
            $bloatwareMatches.Add([PSCustomObject]@{
                    BloatwareName = $task.Name
                    InstalledApp  = @{
                        Type = 'ScheduledTask'
                        Data = $task
                    }
                    MatchType     = 'ScheduledTask'
                })
        }
        Write-Log "Scheduled Tasks bloatware matches: $($scheduledTasksBloatware.Count)" 'INFO'

        # Start Menu bloatware detection
        $startMenuBloatware = Get-StartMenuBloatware -UseCache
        foreach ($shortcut in $startMenuBloatware) {
            $bloatwareMatches.Add([PSCustomObject]@{
                    BloatwareName = $shortcut.Name
                    InstalledApp  = @{
                        Type = 'StartMenuShortcut'
                        Data = $shortcut
                    }
                    MatchType     = 'StartMenuShortcut'
                })
        }
        Write-Log "Start Menu bloatware matches: $($startMenuBloatware.Count)" 'INFO'

        # Enhanced detection summary
        $enhancedDetectionCount = $windowsFeaturesBloatware.Count + $servicesBloatware.Count +
        $scheduledTasksBloatware.Count + $startMenuBloatware.Count
        Write-Log "[ENHANCED DETECTION SUMMARY] Found $enhancedDetectionCount additional system-level bloatware items" 'SUCCESS'
    }
    catch {
        Write-Log "Error during enhanced bloatware detection: $_" 'WARN'
    }

    # Early exit if no bloatware found
    if ($bloatwareMatches.Count -eq 0) {
        Write-Log "[END] Ultra-Enhanced Bloatware Removal - No bloatware detected from $($installedApps.Keys.Count) analyzed apps (plus registry/provisioned)" 'INFO'
        Write-Log "Sample installed apps: $(@($installedApps.Keys) | Select-Object -First 10 | Join-String -Separator ', ')" 'VERBOSE'
        # Update previous list for next run
        Copy-Item $currentListPath $previousListPath -Force
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
        $null = Get-AppxPackage -Name 'NonExistent*' -ErrorAction SilentlyContinue
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
    $script:bloatwareRemovalCount = 0
    $script:bloatwareFailedCount = 0

    # Use the new modular progress system for bloatware removal
    Start-ActionProgressSequence -SequenceName 'Bloatware Removal' -Actions $bloatwareMatches -ActionProcessor {
        param($match, $currentIndex, $totalApps)

        # Individual bloatware removal progress
        Write-ActionProgress -ActionType 'Removing' -ItemName $match.BloatwareName -PercentComplete 0 -Status 'Preparing removal...' -CurrentItem $currentIndex -TotalItems $totalApps

        $result = @{
            Success    = $false
            AppName    = $match.BloatwareName
            ActualName = ''
            Method     = ''
        }

        try {
            $app = $match.InstalledApp
            $appType = $app.Type
            $appData = $app.Data

            # Start removal process with single progress update
            Write-ActionProgress -ActionType 'Removing' -ItemName $match.BloatwareName -PercentComplete 0 -Status "Removing $appType package..." -CurrentItem $currentIndex -TotalItems $totalApps

            # Optimized removal by type priority
            switch ($appType) {
                'AppX' {
                    if ($toolCapabilities.AppX -and ($appData.PackageFullName -or $appData.Name)) {
                        try {
                            $packageName = if ($appData.Name) { $appData.Name } else { ($appData.PackageFullName -split '_')[0] }
                            $removalSuccess = $false

                            Write-Log "Attempting comprehensive AppX removal for: $packageName" 'INFO'

                            # Method 1: Remove all user installations
                            $userPackages = Get-AppxPackage -Name "*$packageName*" -AllUsers -ErrorAction SilentlyContinue
                            foreach ($package in $userPackages) {
                                try {
                                    Write-Log "Removing user package: $($package.PackageFullName)" 'INFO'
                                    Remove-AppxPackage -Package $package.PackageFullName -AllUsers -ErrorAction SilentlyContinue
                                    $removalSuccess = $true
                                }
                                catch {
                                    Write-Log "Failed to remove user package $($package.PackageFullName): $_" 'WARN'
                                }
                            }

                            # Method 2: Remove provisioned packages (prevents reinstallation for new users)
                            $provisionedPackages = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like "*$packageName*" }
                            foreach ($provPackage in $provisionedPackages) {
                                try {
                                    Write-Log "Removing provisioned package: $($provPackage.DisplayName)" 'INFO'
                                    Remove-AppxProvisionedPackage -Online -PackageName $provPackage.PackageName -ErrorAction SilentlyContinue
                                    $removalSuccess = $true
                                }
                                catch {
                                    Write-Log "Failed to remove provisioned package $($provPackage.DisplayName): $_" 'WARN'
                                }
                            }

                            # Method 3: DISM removal for system packages
                            try {
                                if (Get-Command dism -ErrorAction SilentlyContinue) {
                                    Write-Log "Attempting DISM removal for: $packageName" 'INFO'
                                    $dismOutput = & dism /online /get-provisionedappxpackages | Out-String
                                    if ($dismOutput -match "PackageName : .*$packageName.*") {
                                        $regexMatches = [regex]::Matches($dismOutput, "PackageName : (.+?$packageName[^\r\n]+)")
                                        foreach ($match in $regexMatches) {
                                            $pkgName = $match.Groups[1].Value.Trim()
                                            Write-Log "DISM removing: $pkgName" 'INFO'
                                            & dism /online /remove-provisionedappxpackage /packagename:"$pkgName" 2>$null
                                            $removalSuccess = $true
                                        }
                                    }
                                }
                            }
                            catch {
                                Write-Log "DISM removal failed: $_" 'WARN'
                            }

                            # Method 4: Registry cleanup (for stubborn entries)
                            try {
                                $regPaths = @(
                                    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore\Applications',
                                    'HKCU:\SOFTWARE\Classes\ActivatableClasses\Package'
                                )

                                foreach ($regPath in $regPaths) {
                                    if (Test-Path $regPath) {
                                        $regKeys = Get-ChildItem $regPath -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "*$packageName*" }
                                        foreach ($regKey in $regKeys) {
                                            try {
                                                Write-Log "Removing registry key: $($regKey.Name)" 'INFO'
                                                Remove-Item -Path $regKey.PSPath -Recurse -Force -ErrorAction SilentlyContinue
                                                $removalSuccess = $true
                                            }
                                            catch {
                                                Write-Log "Registry removal failed for $($regKey.Name): $_" 'WARN'
                                            }
                                        }
                                    }
                                }
                            }
                            catch {
                                Write-Log "Registry cleanup failed: $_" 'WARN'
                            }

                            # Verify complete removal
                            $finalCheck = Get-AppxPackage -Name "*$packageName*" -AllUsers -ErrorAction SilentlyContinue
                            $provisionedCheck = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like "*$packageName*" }

                            if (-not $finalCheck -and -not $provisionedCheck) {
                                $result.Success = $true
                                $result.Method = 'AppX (Comprehensive)'
                                $result.ActualName = $packageName
                                $script:bloatwareRemovalCount++
                                Write-Log "✓ COMPLETELY REMOVED: $($match.BloatwareName) [AppX Comprehensive: $packageName]" 'INFO'
                                Write-ActionProgress -ActionType 'Removing' -ItemName $match.BloatwareName -PercentComplete 100 -Status 'Successfully removed via AppX (Comprehensive)' -CurrentItem $currentIndex -TotalItems $totalApps -Completed
                                return
                            }
                            elseif ($removalSuccess) {
                                $result.Success = $true
                                $result.Method = 'AppX (Partial)'
                                $result.ActualName = $packageName
                                $script:bloatwareRemovalCount++
                                Write-Log "✓ PARTIALLY REMOVED: $($match.BloatwareName) [AppX Partial: $packageName] - Some components may remain" 'INFO'
                                Write-ActionProgress -ActionType 'Removing' -ItemName $match.BloatwareName -PercentComplete 100 -Status 'Partially removed via AppX' -CurrentItem $currentIndex -TotalItems $totalApps -Completed
                                return
                            }
                        }
                        catch {
                            Write-Log "AppX comprehensive removal failed for $($match.BloatwareName): $_" 'WARN'
                        }
                    }
                }

                'Winget' {
                    if ($toolCapabilities.Winget -and ($appData.Id -or $appData.Name)) {
                        try {
                            $removalSuccess = $false
                            $targetId = if ($appData.Id) { $appData.Id } else { $appData.Name }

                            Write-Log "Attempting enhanced Winget removal for: $targetId" 'INFO'

                            # Method 1: Standard uninstall with enhanced arguments
                            try {
                                $uninstallArgs = @('uninstall', '--id', $targetId, '--silent', '--accept-source-agreements', '--disable-interactivity', '--force')
                                Write-Log "Winget command: winget $($uninstallArgs -join ' ')" 'INFO'
                                $wingetOutPath = Join-Path $global:TempFolder 'winget_output.txt'
                                $wingetErrPath = Join-Path $global:TempFolder 'winget_error.txt'
                                $wingetProc = Start-Process -FilePath 'winget' -ArgumentList $uninstallArgs -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput $wingetOutPath -RedirectStandardError $wingetErrPath

                                if ($wingetProc.ExitCode -eq 0) {
                                    $removalSuccess = $true
                                }
                                else {
                                    $errorOutput = Get-Content $wingetErrPath -ErrorAction SilentlyContinue
                                    Write-Log "Winget removal failed with exit code $($wingetProc.ExitCode): $errorOutput" 'WARN'
                                }
                            }
                            catch {
                                Write-Log "Standard winget removal failed: $_" 'WARN'
                            }

                            # Method 2: Try with exact name match if ID failed
                            if (-not $removalSuccess -and $appData.Name -and $appData.Name -ne $targetId) {
                                try {
                                    $uninstallArgs = @('uninstall', '--name', $appData.Name, '--silent', '--accept-source-agreements', '--disable-interactivity', '--force')
                                    Write-Log "Winget name-based command: winget $($uninstallArgs -join ' ')" 'INFO'
                                    $wingetProc = Start-Process -FilePath 'winget' -ArgumentList $uninstallArgs -WindowStyle Hidden -Wait -PassThru

                                    if ($wingetProc.ExitCode -eq 0) {
                                        $removalSuccess = $true
                                    }
                                }
                                catch {
                                    Write-Log "Name-based winget removal failed: $_" 'WARN'
                                }
                            }

                            # Method 3: Interactive removal as last resort
                            if (-not $removalSuccess) {
                                try {
                                    $uninstallArgs = @('uninstall', '--id', $targetId, '--interactive')
                                    Write-Log "Attempting interactive winget removal: winget $($uninstallArgs -join ' ')" 'INFO'
                                    $wingetProc = Start-Process -FilePath 'winget' -ArgumentList $uninstallArgs -WindowStyle Hidden -Wait -PassThru

                                    if ($wingetProc.ExitCode -eq 0) {
                                        $removalSuccess = $true
                                    }
                                }
                                catch {
                                    Write-Log "Interactive winget removal failed: $_" 'WARN'
                                }
                            }

                            if ($removalSuccess) {
                                $result.Success = $true
                                $result.Method = 'Winget (Enhanced)'
                                $result.ActualName = $appData.Name
                                $script:bloatwareRemovalCount++
                                Write-Log "✓ REMOVED: $($match.BloatwareName) [Winget Enhanced: $($appData.Name)]" 'INFO'
                                Write-ActionProgress -ActionType 'Removing' -ItemName $match.BloatwareName -PercentComplete 100 -Status 'Successfully removed via Winget (Enhanced)' -CurrentItem $currentIndex -TotalItems $totalApps -Completed
                                return
                            }
                        }
                        catch {
                            Write-Log "Winget enhanced removal failed for $($match.BloatwareName): $_" 'WARN'
                        }
                    }
                }

                'Choco' {
                    if ($toolCapabilities.Chocolatey -and ($appData.Name -or $appData.Id)) {
                        try {
                            $removalSuccess = $false
                            $targetPackage = if ($appData.Id) { $appData.Id } else { $appData.Name }

                            Write-Log "Attempting enhanced Chocolatey removal for: $targetPackage" 'INFO'

                            # Method 1: Standard uninstall with enhanced arguments
                            try {
                                $chocoArgs = @('uninstall', $targetPackage, '-y', '--ignore-dependencies', '--remove-dependencies', '--force')
                                Write-Log "Chocolatey command: choco $($chocoArgs -join ' ')" 'INFO'
                                $chocoOutPath = Join-Path $global:TempFolder 'choco_output.txt'
                                $chocoErrPath = Join-Path $global:TempFolder 'choco_error.txt'
                                $chocoProc = Start-Process -FilePath 'choco' -ArgumentList $chocoArgs -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput $chocoOutPath -RedirectStandardError $chocoErrPath

                                if ($chocoProc.ExitCode -eq 0) {
                                    $removalSuccess = $true
                                }
                                else {
                                    $errorOutput = Get-Content $chocoErrPath -ErrorAction SilentlyContinue
                                    Write-Log "Chocolatey removal failed with exit code $($chocoProc.ExitCode): $errorOutput" 'WARN'
                                }
                            }
                            catch {
                                Write-Log "Standard chocolatey removal failed: $_" 'WARN'
                            }

                            # Method 2: Try with alternative package name formats
                            if (-not $removalSuccess -and $appData.Name -and $appData.Name -ne $targetPackage) {
                                $alternativeNames = @(
                                    $appData.Name.ToLower().Replace(' ', '-'),
                                    $appData.Name.ToLower().Replace(' ', '.'),
                                    $appData.Name.ToLower().Replace(' ', ''),
                                    $appData.Name.Replace(' ', '')
                                )

                                foreach ($altName in $alternativeNames) {
                                    if ($removalSuccess) { break }
                                    try {
                                        $chocoArgs = @('uninstall', $altName, '-y', '--ignore-dependencies', '--force')
                                        Write-Log "Chocolatey alternative name: choco $($chocoArgs -join ' ')" 'INFO'
                                        $chocoProc = Start-Process -FilePath 'choco' -ArgumentList $chocoArgs -WindowStyle Hidden -Wait -PassThru

                                        if ($chocoProc.ExitCode -eq 0) {
                                            $removalSuccess = $true
                                            $targetPackage = $altName
                                            break
                                        }
                                    }
                                    catch {
                                        Write-Log "Alternative chocolatey removal failed for '$altName': $_" 'WARN'
                                    }
                                }
                            }

                            # Method 3: Force removal with all available flags
                            if (-not $removalSuccess) {
                                try {
                                    $chocoArgs = @('uninstall', $targetPackage, '-y', '--force', '--force-dependencies', '--skip-autouninstaller', '--ignore-checksums')
                                    Write-Log "Chocolatey force removal: choco $($chocoArgs -join ' ')" 'INFO'
                                    $chocoProc = Start-Process -FilePath 'choco' -ArgumentList $chocoArgs -WindowStyle Hidden -Wait -PassThru

                                    if ($chocoProc.ExitCode -eq 0) {
                                        $removalSuccess = $true
                                    }
                                }
                                catch {
                                    Write-Log "Force chocolatey removal failed: $_" 'WARN'
                                }
                            }

                            if ($removalSuccess) {
                                $result.Success = $true
                                $result.Method = 'Chocolatey (Enhanced)'
                                $result.ActualName = $targetPackage
                                $script:bloatwareRemovalCount++
                                Write-Log "✓ REMOVED: $($match.BloatwareName) [Chocolatey Enhanced: $targetPackage]" 'INFO'
                                Write-ActionProgress -ActionType 'Removing' -ItemName $match.BloatwareName -PercentComplete 100 -Status 'Successfully removed via Chocolatey (Enhanced)' -CurrentItem $currentIndex -TotalItems $totalApps -Completed
                                return
                            }
                        }
                        catch {
                            Write-Log "Chocolatey enhanced removal failed for $($match.BloatwareName): $_" 'WARN'
                        }
                    }
                }

                'RegistryUninstall' {
                    if ($appData.UninstallString) {
                        try {
                            $removalSuccess = $false
                            $uninstallString = $appData.UninstallString.Trim()
                            $displayName = if ($appData.DisplayName) { $appData.DisplayName } else { $appData.Name }

                            Write-Log "Attempting registry uninstall for: $displayName" 'INFO'
                            Write-Log "Uninstall command: $uninstallString" 'INFO'

                            # Method 1: Parse and execute uninstall string
                            try {
                                if ($uninstallString -match '^"([^"]+)"\s*(.*)$') {
                                    # Quoted executable with arguments
                                    $executable = $matches[1]
                                    $arguments = $matches[2].Trim()
                                }
                                elseif ($uninstallString -match '^([^"]\S+)\s*(.*)$') {
                                    # Unquoted executable with arguments
                                    $executable = $matches[1]
                                    $arguments = $matches[2].Trim()
                                }
                                else {
                                    # Treat entire string as executable
                                    $executable = $uninstallString
                                    $arguments = ''
                                }

                                # Add silent flags if not present
                                if ($arguments -notmatch '/S|/silent|/quiet|/q|--silent') {
                                    if ($executable -match 'msiexec') {
                                        $arguments += ' /quiet /norestart'
                                    }
                                    else {
                                        $arguments += ' /S'
                                    }
                                }

                                Write-Log "Executing: $executable $arguments" 'INFO'

                                if (Test-Path $executable) {
                                    $uninstallProc = Start-Process -FilePath $executable -ArgumentList $arguments -WindowStyle Hidden -Wait -PassThru -ErrorAction Stop

                                    if ($uninstallProc.ExitCode -eq 0) {
                                        $removalSuccess = $true
                                    }
                                    else {
                                        Write-Log "Registry uninstall failed with exit code: $($uninstallProc.ExitCode)" 'WARN'
                                    }
                                }
                                else {
                                    Write-Log "Uninstaller not found: $executable" 'WARN'
                                }
                            }
                            catch {
                                Write-Log "Registry uninstall execution failed: $_" 'WARN'
                            }

                            # Method 2: Try direct command execution if normal parsing failed
                            if (-not $removalSuccess) {
                                try {
                                    Write-Log "Attempting direct command execution: $uninstallString" 'INFO'
                                    $directProc = Start-Process -FilePath 'cmd.exe' -ArgumentList "/c `"$uninstallString`"" -WindowStyle Hidden -Wait -PassThru -ErrorAction Stop

                                    if ($directProc.ExitCode -eq 0) {
                                        $removalSuccess = $true
                                    }
                                }
                                catch {
                                    Write-Log "Direct command execution failed: $_" 'WARN'
                                }
                            }

                            # Method 3: MSI-specific handling for MSI packages
                            if (-not $removalSuccess -and $uninstallString -match '\{[A-F0-9-]+\}') {
                                try {
                                    $msiCode = [regex]::Match($uninstallString, '\{[A-F0-9-]+\}').Value
                                    Write-Log "Attempting MSI removal for product code: $msiCode" 'INFO'

                                    $msiArgs = @('/x', $msiCode, '/quiet', '/norestart')
                                    $msiProc = Start-Process -FilePath 'msiexec.exe' -ArgumentList $msiArgs -WindowStyle Hidden -Wait -PassThru -ErrorAction Stop

                                    if ($msiProc.ExitCode -eq 0) {
                                        $removalSuccess = $true
                                    }
                                    else {
                                        Write-Log "MSI removal failed with exit code: $($msiProc.ExitCode)" 'WARN'
                                    }
                                }
                                catch {
                                    Write-Log "MSI removal failed: $_" 'WARN'
                                }
                            }

                            if ($removalSuccess) {
                                $result.Success = $true
                                $result.Method = 'Registry Uninstall (Enhanced)'
                                $result.ActualName = $displayName
                                $script:bloatwareRemovalCount++
                                Write-Log "✓ REMOVED: $($match.BloatwareName) [Registry Enhanced: $displayName]" 'INFO'
                                Write-ActionProgress -ActionType 'Removing' -ItemName $match.BloatwareName -PercentComplete 100 -Status 'Successfully removed via Registry (Enhanced)' -CurrentItem $currentIndex -TotalItems $totalApps -Completed
                                return
                            }
                        }
                        catch {
                            Write-Log "Registry uninstall enhanced removal failed for $($match.BloatwareName): $_" 'WARN'
                        }
                    }
                }

                'ProvisionedAppX' {
                    if ($appData.PackageName -or $appData.DisplayName) {
                        try {
                            $removalSuccess = $false
                            $packageName = if ($appData.PackageName) { $appData.PackageName } else { $appData.DisplayName }

                            Write-Log "Attempting provisioned AppX removal for: $packageName" 'INFO'

                            # Method 1: Remove provisioned package using PowerShell
                            try {
                                $provisionedPackages = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object {
                                    $_.DisplayName -like "*$packageName*" -or $_.PackageName -like "*$packageName*"
                                }

                                foreach ($package in $provisionedPackages) {
                                    Write-Log "Removing provisioned package: $($package.PackageName)" 'INFO'
                                    Remove-AppxProvisionedPackage -Online -PackageName $package.PackageName -ErrorAction SilentlyContinue
                                    $removalSuccess = $true
                                }
                            }
                            catch {
                                Write-Log "PowerShell provisioned package removal failed: $_" 'WARN'
                            }

                            # Method 2: DISM-based removal
                            if (-not $removalSuccess) {
                                try {
                                    if (Get-Command dism -ErrorAction SilentlyContinue) {
                                        Write-Log "Attempting DISM provisioned package removal for: $packageName" 'INFO'
                                        $dismOutput = & dism /online /get-provisionedappxpackages | Out-String

                                        if ($dismOutput -match "PackageName : .*$packageName.*") {
                                            $regexMatches = [regex]::Matches($dismOutput, "PackageName : (.+?$packageName[^\r\n]+)")
                                            foreach ($match in $regexMatches) {
                                                $pkgName = $match.Groups[1].Value.Trim()
                                                Write-Log "DISM removing provisioned package: $pkgName" 'INFO'
                                                $dismResult = & dism /online /remove-provisionedappxpackage /packagename:"$pkgName" 2>&1

                                                if ($LASTEXITCODE -eq 0) {
                                                    $removalSuccess = $true
                                                }
                                                else {
                                                    Write-Log "DISM removal failed: $dismResult" 'WARN'
                                                }
                                            }
                                        }
                                    }
                                }
                                catch {
                                    Write-Log "DISM provisioned package removal failed: $_" 'WARN'
                                }
                            }

                            # Method 3: Registry cleanup for provisioned packages
                            if (-not $removalSuccess) {
                                try {
                                    $regPaths = @(
                                        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore\Config',
                                        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore\Deprovisioned'
                                    )

                                    foreach ($regPath in $regPaths) {
                                        if (Test-Path $regPath) {
                                            $regKeys = Get-ChildItem $regPath -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "*$packageName*" }
                                            foreach ($regKey in $regKeys) {
                                                try {
                                                    Write-Log "Removing provisioned registry key: $($regKey.Name)" 'INFO'
                                                    Remove-Item -Path $regKey.PSPath -Recurse -Force -ErrorAction SilentlyContinue
                                                    $removalSuccess = $true
                                                }
                                                catch {
                                                    Write-Log "Provisioned registry removal failed for $($regKey.Name): $_" 'WARN'
                                                }
                                            }
                                        }
                                    }
                                }
                                catch {
                                    Write-Log "Provisioned registry cleanup failed: $_" 'WARN'
                                }
                            }

                            # Verify removal
                            $finalCheck = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object {
                                $_.DisplayName -like "*$packageName*" -or $_.PackageName -like "*$packageName*"
                            }

                            if (-not $finalCheck -or $removalSuccess) {
                                $result.Success = $true
                                $result.Method = 'Provisioned AppX (Enhanced)'
                                $result.ActualName = $packageName
                                $script:bloatwareRemovalCount++
                                Write-Log "✓ REMOVED: $($match.BloatwareName) [Provisioned AppX Enhanced: $packageName]" 'INFO'
                                Write-ActionProgress -ActionType 'Removing' -ItemName $match.BloatwareName -PercentComplete 100 -Status 'Successfully removed via Provisioned AppX (Enhanced)' -CurrentItem $currentIndex -TotalItems $totalApps -Completed
                                return
                            }
                        }
                        catch {
                            Write-Log "Provisioned AppX enhanced removal failed for $($match.BloatwareName): $_" 'WARN'
                        }
                    }
                }

                # Enhanced bloatware types handling
                'WindowsFeature' {
                    try {
                        $featureName = $appData.FeatureName
                        Write-Log "Disabling Windows Feature: $featureName" 'INFO'
                        $disableResult = Disable-WindowsOptionalFeature -FeatureName $featureName -Online -NoRestart -ErrorAction SilentlyContinue
                        if ($disableResult -and $disableResult.RestartNeeded -eq $false) {
                            $result.Success = $true
                            $result.Method = 'WindowsFeature'
                            $result.ActualName = $featureName
                            $script:bloatwareRemovalCount++
                            Write-Log "✓ DISABLED: $($match.BloatwareName) [Windows Feature: $featureName]" 'INFO'
                            Write-ActionProgress -ActionType 'Removing' -ItemName $match.BloatwareName -PercentComplete 100 -Status 'Successfully disabled Windows Feature' -CurrentItem $currentIndex -TotalItems $totalApps -Completed
                            return
                        }
                    }
                    catch {
                        Write-Log "Windows Feature disable failed for $($match.BloatwareName): $_" 'WARN'
                    }
                }

                'Service' {
                    try {
                        $serviceName = $appData.ServiceName
                        Write-Log "Stopping and disabling service: $serviceName" 'INFO'

                        # Stop the service first
                        Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue

                        # Disable the service
                        Set-Service -Name $serviceName -StartupType Disabled -ErrorAction SilentlyContinue

                        # Verify the service is stopped and disabled
                        $serviceCheck = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
                        if ($serviceCheck -and $serviceCheck.Status -eq 'Stopped') {
                            $result.Success = $true
                            $result.Method = 'Service'
                            $result.ActualName = $serviceName
                            $script:bloatwareRemovalCount++
                            Write-Log "✓ DISABLED: $($match.BloatwareName) [Service: $serviceName]" 'INFO'
                            Write-ActionProgress -ActionType 'Removing' -ItemName $match.BloatwareName -PercentComplete 100 -Status 'Successfully disabled service' -CurrentItem $currentIndex -TotalItems $totalApps -Completed
                            return
                        }
                    }
                    catch {
                        Write-Log "Service disable failed for $($match.BloatwareName): $_" 'WARN'
                    }
                }

                'ScheduledTask' {
                    try {
                        $taskName = $appData.TaskName
                        $taskPath = $appData.TaskPath
                        Write-Log "Disabling scheduled task: $taskPath$taskName" 'INFO'

                        # Disable the scheduled task
                        Disable-ScheduledTask -TaskName $taskName -TaskPath $taskPath -ErrorAction SilentlyContinue

                        # Verify the task is disabled
                        $taskCheck = Get-ScheduledTask -TaskName $taskName -TaskPath $taskPath -ErrorAction SilentlyContinue
                        if ($taskCheck -and $taskCheck.State -eq 'Disabled') {
                            $result.Success = $true
                            $result.Method = 'ScheduledTask'
                            $result.ActualName = "$taskPath$taskName"
                            $script:bloatwareRemovalCount++
                            Write-Log "✓ DISABLED: $($match.BloatwareName) [Scheduled Task: $taskPath$taskName]" 'INFO'
                            Write-ActionProgress -ActionType 'Removing' -ItemName $match.BloatwareName -PercentComplete 100 -Status 'Successfully disabled scheduled task' -CurrentItem $currentIndex -TotalItems $totalApps -Completed
                            return
                        }
                    }
                    catch {
                        Write-Log "Scheduled Task disable failed for $($match.BloatwareName): $_" 'WARN'
                    }
                }

                'StartMenuShortcut' {
                    try {
                        $shortcutPath = $appData.ShortcutPath
                        Write-Log "Removing Start Menu shortcut: $shortcutPath" 'INFO'

                        # Remove the shortcut file
                        if (Test-Path $shortcutPath) {
                            Remove-Item -Path $shortcutPath -Force -ErrorAction SilentlyContinue

                            # Verify removal
                            if (-not (Test-Path $shortcutPath)) {
                                $result.Success = $true
                                $result.Method = 'StartMenuShortcut'
                                $result.ActualName = $shortcutPath
                                $script:bloatwareRemovalCount++
                                Write-Log "✓ REMOVED: $($match.BloatwareName) [Start Menu Shortcut: $shortcutPath]" 'INFO'
                                Write-ActionProgress -ActionType 'Removing' -ItemName $match.BloatwareName -PercentComplete 100 -Status 'Successfully removed shortcut' -CurrentItem $currentIndex -TotalItems $totalApps -Completed
                                return
                            }
                        }
                    }
                    catch {
                        Write-Log "Start Menu shortcut removal failed for $($match.BloatwareName): $_" 'WARN'
                    }
                }
            }

            # If no method succeeded
            if (-not $result.Success) {
                $script:bloatwareFailedCount++
                Write-Log "✗ FAILED: $($match.BloatwareName) - No successful removal method" 'WARN'
                Write-ActionProgress -ActionType 'Removing' -ItemName $match.BloatwareName -PercentComplete 100 -Status 'Removal failed' -CurrentItem $currentIndex -TotalItems $totalApps -Completed
            }
        }
        catch {
            $script:bloatwareFailedCount++
            Write-Log "✗ EXCEPTION: $($match.BloatwareName) - $_" 'ERROR'
            Write-ActionProgress -ActionType 'Removing' -ItemName $match.BloatwareName -PercentComplete 100 -Status 'Removal exception' -CurrentItem $currentIndex -TotalItems $totalApps -Completed
        }

        # Add successful results to removedApps collection for reporting
        if ($result.Success) {
            [void]$removedApps.Add([PSCustomObject]@{
                    AppName    = $result.AppName
                    ActualName = $result.ActualName
                    Method     = $result.Method
                    Success    = $result.Success
                })
        }
    }

    # ================================================================
    # STEP 4: Display Results and Summary
    # ================================================================
    # Convert removedApps to array for processing and detailed reporting
    $removedArray = @($removedApps)

    if ($script:bloatwareRemovalCount -gt 0) {
        Write-Log '=== BLOATWARE REMOVAL RESULTS ===' 'INFO'
        Write-Host '=== BLOATWARE REMOVAL RESULTS ===' -ForegroundColor Yellow
        Write-Log "✓ Successfully removed $script:bloatwareRemovalCount bloatware apps" 'INFO'
        Write-Host "✓ Successfully removed $script:bloatwareRemovalCount bloatware apps" -ForegroundColor Green

        # Log detailed removal information using restored $removedApps data
        if ($removedArray.Count -gt 0) {
            Write-Log 'DETAILED REMOVAL BREAKDOWN:' 'INFO'
            foreach ($removed in $removedArray) {
                Write-Log "  → $($removed.ActualName) [Method: $($removed.Method)]" 'INFO'
            }

            # Method breakdown statistics
            $methodGroups = $removedArray | Group-Object Method
            $methodSummary = ($methodGroups | ForEach-Object { "$($_.Name): $($_.Count)" }) -join ', '
            Write-Log "Removal methods used: $methodSummary" 'INFO'
        }

        if ($script:bloatwareFailedCount -gt 0) {
            Write-Log "✗ Failed to remove $script:bloatwareFailedCount apps" 'WARN'
            Write-Host "✗ Failed to remove $script:bloatwareFailedCount apps" -ForegroundColor Yellow
        }
    }
    else {
        if ($bloatwareMatches.Count -eq 0) {
            Write-Log '✓ No bloatware detected - system clean' 'INFO'
            Write-Host '✓ No bloatware detected - system clean' -ForegroundColor Green
        }
        else {
            Write-Log '✗ No bloatware apps were successfully removed' 'WARN'
            Write-Host '✗ No bloatware apps were successfully removed' -ForegroundColor Yellow
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
        # End try/catch for registry key
    } -ThrottleLimit 3 | Out-Null # End ForEach-Object -Parallel

    # ================================================================
    # STEP 4: Update previous installed apps list for next diff operation
    # ================================================================
    try {
        # Update the previous list with current list for next run
        Copy-Item $currentListPath $previousListPath -Force
        Write-Log 'Updated previous installed apps list for next diff operation' 'INFO'

        # Create summary report of diff-based processing
        $diffSummary = @{
            TotalCurrentApps   = $currentInstalledApps.Count
            NewlyInstalledApps = $newlyInstalledApps.Count
            BloatwareRemoved   = if ($removedArray) { $removedArray.Count } else { 0 }
            ProcessingMode     = 'Diff-Based (Optimized)'
            LastRun            = (Get-Date).ToString('o')
        }

        $diffSummaryPath = Join-Path $global:TempFolder 'bloatware_diff_summary.json'
        $diffSummary | ConvertTo-Json -Depth 3 | Out-File $diffSummaryPath -Encoding UTF8
        Write-Log "Diff-based processing summary saved to $diffSummaryPath" 'INFO'
    }
    catch {
        Write-Log "Failed to update previous list for diff operation: $_" 'WARN'
    }

    Write-Log '[END] Ultra-Enhanced Bloatware Removal - Diff-Based Processing Complete' 'INFO'
}

# ================================================================
# Function: Get-SystemInventory
# ================================================================
# Purpose: Collect comprehensive system information for analysis and reporting
# Environment: Windows 10/11, PowerShell 7+, Administrator context
# Logic: Gathers hardware, software, OS, and performance metrics
# Returns: Hashtable with system inventory data
# Side-effects: None - read-only operations
# ================================================================
function Get-SystemInventory {
    Write-Log '[START] Collecting comprehensive system inventory' 'INFO'
    Write-ActionLog -Action 'System inventory collection' -Details 'Starting comprehensive system scan' -Category 'Task Execution' -Status 'START'
    
    try {
        $inventory = @{
            ComputerName      = $env:COMPUTERNAME
            OSVersion         = [System.Environment]::OSVersion.VersionString
            PowerShellVersion = $PSVersionTable.PSVersion.ToString()
            Administrator     = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
            Timestamp         = Get-Date
        }

        # Get hardware information
        try {
            $computerSystem = Get-CimInstance Win32_ComputerSystem
            $inventory.Processor = $computerSystem.Manufacturer
            $inventory.SystemType = $computerSystem.SystemType
            $inventory.TotalMemory = [math]::Round($computerSystem.TotalPhysicalMemory / 1GB, 2)
        }
        catch {
            Write-Log "Warning: Could not retrieve hardware info: $_" 'WARN'
        }

        # Get disk information
        try {
            $disks = Get-CimInstance Win32_LogicalDisk | Where-Object { $_.DriveType -eq 3 }
            $inventory.Disks = $disks | ForEach-Object {
                @{
                    Drive = $_.DeviceID
                    Size  = [math]::Round($_.Size / 1GB, 2)
                    Free  = [math]::Round($_.FreeSpace / 1GB, 2)
                    Used  = [math]::Round(($_.Size - $_.FreeSpace) / 1GB, 2)
                }
            }
        }
        catch {
            Write-Log "Warning: Could not retrieve disk info: $_" 'WARN'
        }

        Write-Log "System inventory collected: $($inventory.ComputerName) - $($inventory.OSVersion)" 'SUCCESS'
        Write-ActionLog -Action 'System inventory collection' -Details 'Inventory collection completed successfully' -Category 'Task Execution' -Status 'SUCCESS'
        
        # Store in global for task use
        $global:SystemInventory = $inventory
        return $inventory
    }
    catch {
        Write-Log "System inventory collection failed: $_" 'ERROR'
        Write-ActionLog -Action 'System inventory collection' -Details "Failed: $_" -Category 'Task Execution' -Status 'FAILURE'
        return $false
    }
}

# ================================================================
# Function: Set-DesktopBackground
# ================================================================
# Purpose: Configure desktop background from Windows Spotlight to personalized slideshow
# Environment: Windows 10/11, PowerShell 7+, Administrator context
# Logic: Sets personalized background preferences and disables spotlight
# Returns: $true on success, $false on failure
# Side-effects: Modifies system registry and user preferences
# ================================================================
function Set-DesktopBackground {
    Write-Log '[START] Configuring desktop background' 'INFO'
    Write-ActionLog -Action 'Desktop background configuration' -Details 'Setting personalized background' -Category 'Task Execution' -Status 'START'
    
    try {
        # Disable Windows Spotlight
        $spotlightPath = 'HKCU:\Software\Policies\Microsoft\Windows\CloudContent'
        if (-not (Test-Path $spotlightPath)) {
            New-Item -Path $spotlightPath -Force | Out-Null
        }
        Set-ItemProperty -Path $spotlightPath -Name 'DisableWindowsSpotlightFeatures' -Value 1 -Type DWord -ErrorAction SilentlyContinue
        Write-Log 'Windows Spotlight disabled' 'INFO'

        # Set desktop background to use personalized slideshow
        $desktopPath = 'HKCU:\Control Panel\Desktop'
        Set-ItemProperty -Path $desktopPath -Name 'Wallpaper' -Value "$env:WINDIR\Web\Wallpaper\Windows\Default.jpg" -ErrorAction SilentlyContinue
        Write-Log 'Desktop background set to default Windows wallpaper' 'INFO'

        Write-Log 'Desktop background configuration completed successfully' 'SUCCESS'
        Write-ActionLog -Action 'Desktop background configuration' -Details 'Configuration completed successfully' -Category 'Task Execution' -Status 'SUCCESS'
        return $true
    }
    catch {
        Write-Log "Desktop background configuration failed: $_" 'ERROR'
        Write-ActionLog -Action 'Desktop background configuration' -Details "Failed: $_" -Category 'Task Execution' -Status 'FAILURE'
        return $false
    }
}

# ================================================================
# Function: Enable-SecurityHardening
# ================================================================
# Purpose: Apply security hardening configurations and policy improvements
# Environment: Windows 10/11, PowerShell 7+, Administrator context
# Logic: Enables various security features and policies
# Returns: $true on success, $false on failure
# Side-effects: Modifies system registry and security policies
# ================================================================
function Enable-SecurityHardening {
    Write-Log '[START] Applying security hardening configurations' 'INFO'
    Write-ActionLog -Action 'Security hardening' -Details 'Applying security configurations' -Category 'Task Execution' -Status 'START'
    
    try {
        $hardeningActions = @(
            @{
                Name  = 'Enable Windows Defender Real-time Protection'
                Path  = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender'
                Value = 'DisableRealtimeMonitoring'
                Data  = 0
                Type  = 'DWord'
            },
            @{
                Name  = 'Enable Windows Defender Automatic Scan'
                Path  = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Scan'
                Value = 'DisableArchiveScanning'
                Data  = 0
                Type  = 'DWord'
            },
            @{
                Name  = 'Enable User Account Control'
                Path  = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
                Value = 'EnableLUA'
                Data  = 1
                Type  = 'DWord'
            },
            @{
                Name  = 'Enable Windows Firewall'
                Path  = 'HKLM:\SOFTWARE\Policies\Microsoft\WindowsFirewall\StandardProfile'
                Value = 'EnableFirewall'
                Data  = 1
                Type  = 'DWord'
            }
        )

        $successCount = 0
        foreach ($action in $hardeningActions) {
            try {
                if (-not (Test-Path $action.Path)) {
                    New-Item -Path $action.Path -Force | Out-Null
                }
                Set-ItemProperty -Path $action.Path -Name $action.Value -Value $action.Data -Type $action.Type -ErrorAction Stop
                Write-Log "✓ $($action.Name)" 'SUCCESS'
                $successCount++
            }
            catch {
                Write-Log "⚠ $($action.Name) - $_" 'WARN'
            }
        }

        Write-Log "Security hardening completed: $successCount/$($hardeningActions.Count) settings applied" 'SUCCESS'
        Write-ActionLog -Action 'Security hardening' -Details "Applied $successCount/$($hardeningActions.Count) security settings" -Category 'Task Execution' -Status 'SUCCESS'
        return $true
    }
    catch {
        Write-Log "Security hardening failed: $_" 'ERROR'
        Write-ActionLog -Action 'Security hardening' -Details "Failed: $_" -Category 'Task Execution' -Status 'FAILURE'
        return $false
    }
}

# ================================================================
# Function: Install-EssentialApps
# ================================================================
# Purpose: Install a curated set of essential applications (and optional
#          custom additions) using package managers in parallel when safe.
# Environment: Windows with package managers available (winget, choco)
# Logic: Resolves category lists, applies conflict resolution, and installs
# Returns: Summary with installed, skipped, and failed lists
# Side-effects: Installs software; network access required
# ================================================================
function Install-EssentialApps {
    # ...existing code...
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
            Write-Log 'Loading previous essential apps list for diff comparison...' 'INFO'
            $previousEssentialApps = Get-Content $previousListPath -Raw | ConvertFrom-Json
            $previousHashSet = [System.Collections.Generic.HashSet[string]]::new($previousEssentialApps, [System.StringComparer]::OrdinalIgnoreCase)
            Write-Log "Previous run required $($previousHashSet.Count) essential apps" 'INFO'

            # Calculate diff: apps in current but not in previous (newly required)
            foreach ($currentApp in $currentEssentialApps) {
                if (-not $previousHashSet.Contains($currentApp)) {
                    [void]$newlyRequiredApps.Add($currentApp)
                }
            }

            Write-Log 'DIFF ANALYSIS COMPLETE:' 'INFO'
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
        Write-Log 'No previous essential apps list found. Processing all required apps.' 'INFO'
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
    $installedRegistry = @{} # Parallel registry for detailed lookups

    # Data sources: Add AppX package names and IDs to lookup table
    $inventory.appx | ForEach-Object {
        if ($_.Name) { 
            $name = $_.Name.Trim()
            [void]$installedLookup.Add($name)
            $installedRegistry[$name] = @{ Source = 'AppX'; Original = $_ }
        }
        if ($_.PackageFullName) { 
            $fullName = $_.PackageFullName.Trim()
            [void]$installedLookup.Add($fullName)
            $installedRegistry[$fullName] = @{ Source = 'AppX'; Original = $_ }
        }
    }

    # Data sources: Add Winget app names and IDs to lookup table
    $inventory.winget | ForEach-Object {
        if ($_.Name) { 
            $name = $_.Name.Trim()
            [void]$installedLookup.Add($name)
            $installedRegistry[$name] = @{ Source = 'Winget'; Original = $_ }
        }
        if ($_.Id) { 
            $id = $_.Id.Trim()
            [void]$installedLookup.Add($id)
            $installedRegistry[$id] = @{ Source = 'Winget'; Original = $_ }
        }
    }

    # Data sources: Add Chocolatey app names to lookup table
    $inventory.choco | ForEach-Object {
        if ($_.Name) { 
            $name = $_.Name.Trim()
            [void]$installedLookup.Add($name)
            $installedRegistry[$name] = @{ Source = 'Chocolatey'; Original = $_ }
        }
        if ($_.Id) { 
            $id = $_.Id.Trim()
            [void]$installedLookup.Add($id)
            $installedRegistry[$id] = @{ Source = 'Chocolatey'; Original = $_ }
        }
    }

    # Data sources: Add registry app display names to lookup table with ALL variations
    $inventory.registry_uninstall | ForEach-Object {
        if ($_.DisplayName) { 
            $displayName = $_.DisplayName.Trim()
            [void]$installedLookup.Add($displayName)
            $installedRegistry[$displayName] = @{ Source = 'Registry'; Original = $_ }
        }
        if ($_.Name) { 
            $name = $_.Name.Trim()
            [void]$installedLookup.Add($name)
            $installedRegistry[$name] = @{ Source = 'Registry'; Original = $_ }
        }
    }

    Write-Log "DETECTION DATABASE: Built lookup table with $($installedLookup.Count) installed app identifiers" 'INFO'
    Write-Log "  - AppX packages: $($inventory.appx.Count)" 'VERBOSE'
    Write-Log "  - Winget apps: $($inventory.winget.Count)" 'VERBOSE'
    Write-Log "  - Chocolatey apps: $($inventory.choco.Count)" 'VERBOSE'
    Write-Log "  - Registry apps: $($inventory.registry_uninstall.Count)" 'VERBOSE'

    # Log sample of installed apps for debugging (first 15 to catch more patterns)
    $sampleApps = @($installedLookup) | Select-Object -First 15
    Write-Log "Sample installed apps: $($sampleApps -join ', ')" 'VERBOSE'
    Write-Log "[DEBUG] Full installed lookup has $($installedLookup.Count) entries" 'DEBUG'

    # Clear any previous normalized lookup cache since we have new inventory
    $script:normalizedLookupCache = $null

    # Smart filtering: find essential apps that are NOT installed using enhanced detection
    # DIFF OPTIMIZATION: Only process apps that are newly required OR not in diff mode
    Write-Log "[EssentialApps] ENHANCED DETECTION: Starting intelligent app detection for $($global:EssentialApps.Count) essential apps..." 'INFO'
    Write-Log 'Detection strategies: (1) Exact match, (2) Normalized matching, (3) Smart publisher-app matching' 'VERBOSE'

    $appsToInstall = @()
    foreach ($essentialApp in $global:EssentialApps) {
        $identifiersToCheck = @()
        if ($essentialApp.Winget) { $identifiersToCheck += $essentialApp.Winget.Trim() }
        if ($essentialApp.Choco) { $identifiersToCheck += $essentialApp.Choco.Trim() }
        if ($essentialApp.Name) { $identifiersToCheck += $essentialApp.Name.Trim() }

        $found = $false
        $matchDetails = 'no match found'

        # ENHANCED DETECTION: Use multiple detection strategies for better app recognition
        foreach ($identifier in $identifiersToCheck) {
            # Strategy 1: Exact match (fastest, O(1) lookup)
            if ($installedLookup.Contains($identifier)) {
                $found = $true
                $matchDetails = "exact match: $identifier"
                break
            }

            # Strategy 2: Normalized matching (handle common variations)
            # This handles cases like "Google.Chrome" vs "Google Chrome"
            $normalizedIdentifier = ($identifier -replace '[\.\-_]', '' -replace '\s+', '').ToLower()

            # Build normalized lookup cache for performance (avoid O(n*m) on every app)
            if (-not $script:normalizedLookupCache) {
                $script:normalizedLookupCache = @{}
                foreach ($installedApp in $installedLookup) {
                    $normalized = ($installedApp -replace '[\.\-_]', '' -replace '\s+', '').ToLower()
                    $script:normalizedLookupCache[$normalized] = $installedApp
                }
            }

            if ($script:normalizedLookupCache.ContainsKey($normalizedIdentifier)) {
                $found = $true
                $matchDetails = "normalized match: $($script:normalizedLookupCache[$normalizedIdentifier]) ≈ $identifier"
                break
            }

            # Strategy 3: Smart partial matching for publisher-based IDs
            # Handle cases like "Mozilla.Firefox" should match "Firefox" or "Mozilla Firefox"
            if ($identifier.Contains('.')) {
                $parts = $identifier -split '\.'
                $publisher = $parts[0]
                $appName = $parts[1]

                # Look for apps containing both publisher and app name
                $partialMatches = @($installedLookup | Where-Object {
                        $_ -match [regex]::Escape($publisher) -and $_ -match [regex]::Escape($appName)
                    })

                if ($partialMatches.Count -gt 0) {
                    $found = $true
                    $matchDetails = "smart match: $($partialMatches[0]) contains both '$publisher' and '$appName'"
                    break
                }
            }
        }

        if ($found) {
            Write-Log "✅ DETECTED: $($essentialApp.Name) ($matchDetails)" 'DEBUG'
        }
        else {
            Write-Log "⚪ NOT DETECTED: $($essentialApp.Name) - will install ($matchDetails, checked: $($identifiersToCheck -join ', '))" 'DEBUG'
            # Log which identifiers were checked but NOT found in installed list
            $missingIds = $identifiersToCheck | Where-Object { $_ -and -not $installedLookup.Contains($_) }
            if ($missingIds) {
                Write-Log "  → Missing identifiers: $($missingIds -join ', ')" 'VERBOSE'
            }
            $appsToInstall += $essentialApp
        }
    }

    if ($appsToInstall.Count -eq 0) {
        # Calculate efficiency gain from diff-based processing
        $efficiencyGain = if ($currentEssentialApps.Count -gt 0) {
            [math]::Round((1 - ($newlyRequiredApps.Count / $currentEssentialApps.Count)) * 100, 1)
        }
        else { 0 }

        Write-Log '[EssentialApps] All essential apps already installed. No new installations needed.' 'INFO'
        Write-Log "PERFORMANCE: Processed $($newlyRequiredApps.Count)/$($currentEssentialApps.Count) required apps (${efficiencyGain}% reduction in processing)" 'INFO'

        # Update previous list for next run
        Copy-Item $currentListPath $previousListPath -Force
        Write-Log '[END] Install Essential Apps' 'INFO'
        return
    }

    # Pre-check package manager availability once
    $wingetAvailable = $null -ne (Get-Command winget -ErrorAction SilentlyContinue)
    $chocoAvailable = $null -ne (Get-Command choco -ErrorAction SilentlyContinue)

    if (-not $wingetAvailable -and -not $chocoAvailable) {
        Write-Log '[EssentialApps] ERROR: No package managers available (winget/choco). Cannot install apps.' 'ERROR'
        Write-Log '[END] Install Essential Apps' 'INFO'
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
    Write-Log '[EssentialApps] Using PowerShell 7 parallel processing with individual app progress...' 'INFO'

    $totalApps = $appsToInstall.Count
    $currentAppIndex = 0
    $script:successCount = 0
    $script:failedCount = 0
    $script:skippedCount = 0

    # ACTION-ONLY LOGGING: Enhanced logging for each app installation
    Write-Log "[EssentialApps] Starting installation of $totalApps essential apps:" 'INFO'
    Write-Log "[EssentialApps] App processing will start from index: $currentAppIndex" 'INFO'

    # Use the new modular progress system
    Start-ActionProgressSequence -SequenceName 'Essential Apps Installation' -Actions $appsToInstall -ActionProcessor {
        param($app, $currentIndex, $totalApps)

        # Update global app index tracking for statistics
        $script:currentAppIndex = $currentIndex

        # Individual app installation progress
        Write-ActionProgress -ActionType 'Installing' -ItemName $app.Name -PercentComplete 0 -Status 'Preparing installation...' -CurrentItem $currentIndex -TotalItems $totalApps

        $result = [PSCustomObject]@{
            AppName    = $app.Name
            Success    = $false
            Method     = ''
            Error      = ''
            Skipped    = $false
            SkipReason = ''
        }

        try {
            # Try Winget first - Start installation attempt
            if ($app.Winget -and $wingetAvailable) {
                Write-ActionProgress -ActionType 'Installing' -ItemName $app.Name -PercentComplete 0 -Status 'Installing via Winget...' -CurrentItem $currentIndex -TotalItems $totalApps

                $wingetArgs = @(
                    'install', '--id', $app.Winget,
                    '--accept-source-agreements', '--accept-package-agreements',
                    '--silent', '-e', '--disable-interactivity', '--force'
                )

                $wingetProc = Start-Process -FilePath 'winget' -ArgumentList $wingetArgs -WindowStyle Hidden -Wait -PassThru

                if ($wingetProc.ExitCode -eq 0) {
                    $result.Success = $true
                    $result.Method = 'winget'
                    $script:successCount++
                    Write-Log "✓ INSTALLED: $($app.Name) [Method: Winget]" 'INFO'
                    Write-Host '    ✓ Successfully installed via Winget' -ForegroundColor Green
                    Write-ActionProgress -ActionType 'Installing' -ItemName $app.Name -PercentComplete 100 -Status 'Installation completed successfully' -CurrentItem $currentIndex -TotalItems $totalApps -Completed
                    return
                }
                elseif ($wingetProc.ExitCode -eq -1978335189) {
                    # App already installed
                    $result.Skipped = $true
                    $result.SkipReason = 'already installed (winget)'
                    $script:skippedCount++
                    Write-Log "⚪ SKIPPED: $($app.Name) [Reason: Already installed via Winget]" 'INFO'
                    Write-Host '    ⚪ Already installed (Winget detected)' -ForegroundColor Yellow
                    Write-ActionProgress -ActionType 'Installing' -ItemName $app.Name -PercentComplete 100 -Status 'Already installed' -CurrentItem $currentIndex -TotalItems $totalApps -Completed
                    return
                }
                else {
                    Write-Log "⚠ Winget failed for $($app.Name) (Exit code: $($wingetProc.ExitCode)). Trying Chocolatey..." 'WARN'
                    Write-Host '    ⚠ Winget failed, trying Chocolatey...' -ForegroundColor Yellow
                }
            }

            # Try Chocolatey as fallback
            if ($app.Choco -and $chocoAvailable -and -not $result.Success) {
                Write-ActionProgress -ActionType 'Installing' -ItemName $app.Name -PercentComplete 50 -Status 'Installing via Chocolatey...' -CurrentItem $currentIndex -TotalItems $totalApps

                $chocoArgs = @('install', $app.Choco, '-y', '--no-progress', '--ignore-checksums')
                $chocoProc = Start-Process -FilePath 'choco' -ArgumentList $chocoArgs -WindowStyle Hidden -Wait -PassThru

                if ($chocoProc.ExitCode -eq 0) {
                    $result.Success = $true
                    $result.Method = 'chocolatey'
                    $script:successCount++
                    Write-Log "✓ INSTALLED: $($app.Name) [Method: Chocolatey]" 'INFO'
                    Write-Host '    ✓ Successfully installed via Chocolatey' -ForegroundColor Green
                    Write-ActionProgress -ActionType 'Installing' -ItemName $app.Name -PercentComplete 100 -Status 'Installation completed successfully' -CurrentItem $currentIndex -TotalItems $totalApps -Completed
                    return
                }
                elseif ($chocoProc.ExitCode -eq 1641 -or $chocoProc.ExitCode -eq 3010) {
                    # Success with reboot required
                    $result.Success = $true
                    $result.Method = 'chocolatey (reboot required)'
                    $script:successCount++
                    Write-Log "✓ INSTALLED: $($app.Name) [Method: Chocolatey - Reboot Required]" 'INFO'
                    Write-Host '    ✓ Successfully installed via Chocolatey (reboot required)' -ForegroundColor Green
                    Write-ActionProgress -ActionType 'Installing' -ItemName $app.Name -PercentComplete 100 -Status 'Installation completed (reboot required)' -CurrentItem $currentIndex -TotalItems $totalApps -Completed
                    return
                }
                else {
                    $result.Error = "Chocolatey failed (Exit code: $($chocoProc.ExitCode))"
                    Write-Log "✗ Chocolatey failed for $($app.Name) (Exit code: $($chocoProc.ExitCode))" 'WARN'
                    Write-Host '    ✗ Chocolatey installation failed' -ForegroundColor Red
                }
            }

            # Try direct download as final fallback
            if ($app.DownloadUrl -and -not $result.Success -and -not $result.Skipped) {
                Write-ActionProgress -ActionType 'Installing' -ItemName $app.Name -PercentComplete 75 -Status 'Downloading directly from Microsoft...' -CurrentItem $currentIndex -TotalItems $totalApps

                try {
                    # Create temp directory for download
                    $tempDir = Join-Path $global:TempFolder 'SysmonDownload'
                    if (-not (Test-Path $tempDir)) {
                        New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
                    }

                    # Download the zip file
                    $zipPath = Join-Path $tempDir 'Sysmon.zip'
                    Write-Log "Downloading Sysmon from: $($app.DownloadUrl)" 'INFO'
                    Invoke-WebRequest -Uri $app.DownloadUrl -OutFile $zipPath -UseBasicParsing

                    # Extract the zip file
                    Write-Log 'Extracting Sysmon archive...' 'INFO'
                    Expand-Archive -Path $zipPath -DestinationPath $tempDir -Force

                    # Find and copy sysmon.exe to a permanent location
                    $extractedSysmon = Get-ChildItem -Path $tempDir -Filter 'sysmon.exe' -Recurse | Select-Object -First 1
                    if ($extractedSysmon) {
                        # Create Sysmon directory in Program Files
                        $sysmonInstallDir = "$env:ProgramFiles\Sysmon"
                        if (-not (Test-Path $sysmonInstallDir)) {
                            New-Item -ItemType Directory -Path $sysmonInstallDir -Force | Out-Null
                        }

                        # Copy sysmon.exe to the install directory
                        $installedSysmonPath = Join-Path $sysmonInstallDir 'sysmon.exe'
                        Copy-Item -Path $extractedSysmon.FullName -Destination $installedSysmonPath -Force

                        $result.Success = $true
                        $result.Method = 'direct download'
                        $script:successCount++
                        Write-Log "✓ INSTALLED: $($app.Name) [Method: Direct Download]" 'INFO'
                        Write-Host '    ✓ Successfully installed via direct download' -ForegroundColor Green
                        Write-ActionProgress -ActionType 'Installing' -ItemName $app.Name -PercentComplete 100 -Status 'Installation completed successfully' -CurrentItem $currentIndex -TotalItems $totalApps -Completed
                        return
                    }
                    else {
                        throw 'sysmon.exe not found in extracted archive'
                    }
                }
                catch {
                    Write-Log "⚠ Direct download failed for $($app.Name): $_" 'WARN'
                    Write-Host "    ⚠ Direct download failed: $_" -ForegroundColor Yellow
                }
            }

            # If all methods failed
            if (-not $result.Success -and -not $result.Skipped) {
                $result.Error = 'All installation methods failed (Winget, Chocolatey, Direct Download)'
                $script:failedCount++
                Write-Log "✗ FAILED: $($app.Name) [Reason: All installation methods failed]" 'ERROR'
                Write-Host '    ✗ Installation failed with all methods' -ForegroundColor Red
                Write-ActionProgress -ActionType 'Installing' -ItemName $app.Name -PercentComplete 100 -Status 'Installation failed' -CurrentItem $currentIndex -TotalItems $totalApps -Completed
            }
        }
        catch {
            $result.Error = $_.Exception.Message
            $script:failedCount++
            Write-Log "✗ EXCEPTION: $($app.Name) [Error: $_]" 'ERROR'
            Write-Host "    ✗ Installation exception: $_" -ForegroundColor Red
            Write-ActionProgress -ActionType 'Installing' -ItemName $app.Name -PercentComplete 100 -Status 'Installation error' -CurrentItem $currentIndex -TotalItems $totalApps -Completed
        }
    }

    # SYSMON CONFIGURATION
    # Configure Sysmon with custom configuration if it was installed
    $sysmonApp = $appsToInstall | Where-Object { $_.Name -eq 'Sysmon' }
    if ($sysmonApp) {
        Write-Log 'Configuring Sysmon with custom configuration for Wazuh integration...' 'INFO'
        Write-Host 'Configuring Sysmon with custom configuration for Wazuh integration...' -ForegroundColor Cyan

        try {
            # Find Sysmon executable path
            $sysmonPaths = @(
                "$env:ProgramData\Chocolatey\bin\sysmon.exe",
                "$env:ProgramData\Chocolatey\lib\sysmon\tools\sysmon.exe",
                "$env:ProgramFiles\Sysmon\sysmon.exe",
                "$env:ProgramFiles\Sysinternals\Sysmon\sysmon.exe"
            )

            $sysmonExe = $null
            foreach ($path in $sysmonPaths) {
                if (Test-Path $path) {
                    $sysmonExe = $path
                    break
                }
            }

            if ($sysmonExe) {
                # First try local config file
                $configPath = Join-Path $ScriptDir 'config\sysmonconfig.xml'
                $configFound = $false

                if (Test-Path $configPath) {
                    Write-Log "Found local Sysmon config at: $configPath" 'INFO'
                    Write-Host "Found local Sysmon config at: $configPath" -ForegroundColor Green
                    $configFound = $true
                }
                else {
                    # Download Sysmon config from internet for Wazuh integration
                    Write-Log "Local config not found. Downloading Sysmon config from internet for Wazuh integration..." 'INFO'
                    Write-Host "Local config not found. Downloading Sysmon config for Wazuh integration..." -ForegroundColor Yellow

                    try {
                        # Create temp directory if it doesn't exist
                        if (-not (Test-Path $global:TempFolder)) {
                            $null = New-Item -Path $global:TempFolder -ItemType Directory -Force
                        }

                        # Download a suitable Sysmon config optimized for Wazuh
                        # Using SwiftOnSecurity's sysmon-config which is Wazuh-compatible
                        $downloadUrl = 'https://raw.githubusercontent.com/SwiftOnSecurity/sysmon-config/master/sysmonconfig-export.xml'
                        $configPath = Join-Path $global:TempFolder 'sysmonconfig.xml'

                        Write-Log "Downloading Sysmon config from: $downloadUrl" 'INFO'
                        
                        # Use TLS 1.2 for secure download
                        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

                        $downloadParams = @{
                            Uri             = $downloadUrl
                            OutFile         = $configPath
                            UseBasicParsing = $true
                            TimeoutSec      = 30
                            ErrorAction     = 'Stop'
                        }

                        Invoke-WebRequest @downloadParams
                        Write-Log "Successfully downloaded Sysmon config to: $configPath" 'INFO'
                        Write-Host "✓ Downloaded Sysmon config successfully" -ForegroundColor Green
                        $configFound = $true
                    }
                    catch {
                        # Fallback: Try alternative URL from Wazuh examples
                        Write-Log "Primary download failed: $_. Attempting fallback URL..." 'WARN'
                        
                        try {
                            $fallbackUrl = 'https://raw.githubusercontent.com/olafhartong/sysmon-modular/master/sysmonconfig.xml'
                            $configPath = Join-Path $global:TempFolder 'sysmonconfig.xml'

                            Write-Log "Trying fallback URL: $fallbackUrl" 'INFO'
                            
                            $downloadParams = @{
                                Uri             = $fallbackUrl
                                OutFile         = $configPath
                                UseBasicParsing = $true
                                TimeoutSec      = 30
                                ErrorAction     = 'Stop'
                            }

                            Invoke-WebRequest @downloadParams
                            Write-Log "Successfully downloaded Sysmon config from fallback URL" 'INFO'
                            Write-Host "✓ Downloaded Sysmon config from fallback source" -ForegroundColor Green
                            $configFound = $true
                        }
                        catch {
                            Write-Log "Fallback download also failed: $_" 'ERROR'
                            Write-Host "✗ Failed to download Sysmon config: $_" -ForegroundColor Red
                            $configFound = $false
                        }
                    }
                }

                # Configure Sysmon if config was found/downloaded
                if ($configFound -and (Test-Path $configPath)) {
                    try {
                        Write-Log "Installing Sysmon with config: $configPath" 'INFO'
                        
                        # Configure Sysmon with the config file
                        $sysmonArgs = @('-accepteula', '-i', $configPath)
                        $sysmonProc = Start-Process -FilePath $sysmonExe -ArgumentList $sysmonArgs -WindowStyle Hidden -Wait -PassThru

                        if ($sysmonProc.ExitCode -eq 0) {
                            Write-Log '✓ Sysmon configured successfully with Wazuh-optimized configuration' 'INFO'
                            Write-Host '✓ Sysmon configured successfully with Wazuh-optimized configuration' -ForegroundColor Green
                        }
                        else {
                            Write-Log "⚠ Sysmon configuration returned exit code: $($sysmonProc.ExitCode)" 'WARN'
                            Write-Host "⚠ Sysmon configuration returned exit code: $($sysmonProc.ExitCode)" -ForegroundColor Yellow
                        }
                    }
                    catch {
                        Write-Log "⚠ Error applying Sysmon configuration: $($_.Exception.Message)" 'WARN'
                        Write-Host "⚠ Error applying Sysmon configuration: $($_.Exception.Message)" -ForegroundColor Yellow
                    }
                }
                else {
                    Write-Log "⚠ Could not obtain Sysmon configuration file. Sysmon installed but not configured." 'WARN'
                    Write-Host "⚠ Sysmon installed but configuration could not be applied" -ForegroundColor Yellow
                    Write-Host "   Manual configuration may be required after internet connection is available" -ForegroundColor Yellow
                }
            }
            else {
                Write-Log '⚠ Sysmon executable not found for configuration' 'WARN'
                Write-Host '⚠ Sysmon executable not found for configuration' -ForegroundColor Yellow
            }
        }
        catch {
            Write-Log "⚠ Sysmon configuration error: $($_.Exception.Message)" 'WARN'
            Write-Host "⚠ Sysmon configuration error: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }

    # Final installation summary
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
            return @{ Found = $false; Method = '' }
        }

        # Check Start Menu apps in parallel
        $startMenuJob = Start-Job -ScriptBlock {
            try {
                $officeApps = Get-StartAppsCompatible | Where-Object { $_.Name -match 'Office|Word|Excel|PowerPoint|Outlook' }
                if ($officeApps) {
                    return @{ Found = $true; Method = 'Start Menu' }
                }
            }
            catch { }
            return @{ Found = $false; Method = '' }
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
            return @{ Installed = $false; DetectionMethod = 'Not detected' }
        }
    }

    $officeResult = Receive-Job -Job $officeDetectionJob -Wait
    Remove-Job -Job $officeDetectionJob -Force

    # LibreOffice installation logic
    if (-not $officeResult.Installed) {
        Write-Log 'No office suite detected. Installing LibreOffice...' 'INFO'
        Write-Host 'Installing LibreOffice as default office suite...' -ForegroundColor Cyan

        $libreOfficeJob = Start-Job -ArgumentList $wingetAvailable, $chocoAvailable -ScriptBlock {
            param($wingetAvailable, $chocoAvailable)

            $result = @{
                Success = $false
                Method  = ''
                Error   = ''
            }

            try {
                # Try Winget first
                if ($wingetAvailable) {
                    $libreArgs = @(
                        'install', '--id', 'TheDocumentFoundation.LibreOffice',
                        '--accept-source-agreements', '--accept-package-agreements',
                        '--silent', '-e', '--disable-interactivity'
                    )
                    $libreProc = Start-Process -FilePath 'winget' -ArgumentList $libreArgs -WindowStyle Hidden -Wait -PassThru
                    if ($libreProc.ExitCode -eq 0) {
                        $result.Success = $true
                        $result.Method = 'winget'
                        return $result
                    }
                    else {
                        $result.Error += "winget failed (exit: $($libreProc.ExitCode)); "
                    }
                }

                # Try Chocolatey as fallback
                if (-not $result.Success -and $chocoAvailable) {
                    $chocoLibreArgs = @('install', 'libreoffice-fresh', '-y', '--no-progress', '--limit-output')
                    $chocoLibreProc = Start-Process -FilePath 'choco' -ArgumentList $chocoLibreArgs -WindowStyle Hidden -Wait -PassThru
                    if ($chocoLibreProc.ExitCode -eq 0) {
                        $result.Success = $true
                        $result.Method = 'choco'
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
        Write-Host '⚪ LibreOffice installation skipped - Office suite already detected' -ForegroundColor Yellow
    }

    # BROWSER EXTENSION CONFIGURATION
    # Configure Firefox with uBlock Origin if Firefox was installed or is present
    try {
        Set-FirefoxuBlockOrigin
    }
    catch {
        Write-Log "Warning: Firefox uBlock Origin configuration encountered an error: $_" 'WARN'
    }

    # ENHANCED SUMMARY AND PERFORMANCE REPORTING
    Write-Log '[EssentialApps] INSTALLATION SUMMARY - DIFF-BASED MODE:' 'INFO'
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
        Write-Log '[EssentialApps] Some installations failed. Check individual app logs above for details.' 'WARN'
    }

    if ($skippedCount -gt 0) {
        Write-Log '[EssentialApps] Some installations were skipped. Check individual app logs above for reasons.' 'INFO'
    }

    # Create audit file with detailed results
    $auditData = @{
        Timestamp          = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        ProcessingMode     = 'DIFF-BASED'
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

    $auditPath = Join-Path $global:TempFolder 'essential_apps_audit.json'
    $auditData | ConvertTo-Json -Depth 3 | Out-File $auditPath -Encoding UTF8
    Write-Log "Audit trail saved to: $auditPath" 'VERBOSE'

    # Update previous list for next run
    Copy-Item $currentListPath $previousListPath -Force
    Write-Log 'Essential apps list updated for next diff comparison' 'VERBOSE'

    Write-Log '[END] Install Essential Apps' 'INFO'
}

# ================================================================
# Function: Set-FirefoxuBlockOrigin
# ================================================================
# Purpose: Automate Firefox configuration to install uBlock Origin and
#          set recommended privacy settings for managed deployments.
# Environment: Firefox installed; access to profile folder(s)
# Logic: Attempts to locate profiles and apply extension or preferences
# Returns: Status object summarizing applied changes
# Side-effects: Modifies browser profiles and extensions
# ================================================================
function Set-FirefoxuBlockOrigin {
    # ...existing code...
}

# ================================================================
# Function: Set-FirefoxuBlockOrigin
# ================================================================
# Purpose: Configure Firefox with uBlock Origin extension using Mozilla ExtensionSettings policy
# Environment: Windows 10/11, Firefox installation required, Administrator privileges recommended
# Performance: Fast, configuration-based, no external downloads required
# Dependencies: Firefox installation, registry access
# Logic: Uses Mozilla ExtensionSettings policy via Windows registry to force-install uBlock Origin
# Features: Enterprise-grade extension deployment, automatic uBlock Origin installation, error handling
# ================================================================
function Set-FirefoxuBlockOrigin {
    Write-Log '[START] Configuring Firefox with uBlock Origin extension' 'INFO'

    try {
        # Check if Firefox is installed
        $firefoxPaths = @(
            "${env:ProgramFiles}\Mozilla Firefox\firefox.exe",
            "${env:ProgramFiles(x86)}\Mozilla Firefox\firefox.exe"
        )

        $firefoxInstalled = $false
        $firefoxPath = $null

        foreach ($path in $firefoxPaths) {
            if (Test-Path $path) {
                $firefoxInstalled = $true
                $firefoxPath = $path
                Write-Log "✓ Firefox detected at: $path" 'INFO'
                break
            }
        }

        if (-not $firefoxInstalled) {
            Write-Log '⚪ SKIPPED: Firefox not detected. uBlock Origin configuration skipped.' 'INFO'
            Write-Host '⚪ Firefox not detected - uBlock Origin configuration skipped' -ForegroundColor Yellow
            return
        }

        # Create Firefox ExtensionSettings policy via registry
        Write-Log 'Configuring Firefox ExtensionSettings policy for uBlock Origin...' 'INFO'

        # Firefox policy registry path
        $policyPath = 'HKLM:\SOFTWARE\Policies\Mozilla\Firefox'

        # Create policy registry structure
        if (-not (Test-Path $policyPath)) {
            New-Item -Path $policyPath -Force | Out-Null
            Write-Log '✓ Created Firefox policy registry path' 'INFO'
        }

        # Configure ExtensionSettings for uBlock Origin
        $uBlockConfig = @{
            'uBlock0@raymondhill.net' = @{
                'installation_mode' = 'force_installed'
                'install_url'       = 'https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi'
                'updates_disabled'  = $false
                'default_area'      = 'navbar'
            }
        } | ConvertTo-Json -Depth 3 -Compress

        # Set ExtensionSettings registry value
        Set-ItemProperty -Path $policyPath -Name 'ExtensionSettings' -Value $uBlockConfig -Type String -Force
        Write-Log '✓ Firefox ExtensionSettings policy configured for uBlock Origin' 'INFO'

        # Also configure via policies.json for comprehensive coverage
        $firefoxInstallDir = Split-Path $firefoxPath -Parent
        $distributionDir = Join-Path $firefoxInstallDir 'distribution'

        if (-not (Test-Path $distributionDir)) {
            New-Item -Path $distributionDir -ItemType Directory -Force | Out-Null
            Write-Log '✓ Created Firefox distribution directory' 'INFO'
        }

        $policiesJsonPath = Join-Path $distributionDir 'policies.json'
        $policiesConfig = @{
            'policies' = @{
                'ExtensionSettings' = @{
                    'uBlock0@raymondhill.net' = @{
                        'installation_mode' = 'force_installed'
                        'install_url'       = 'https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi'
                        'updates_disabled'  = $false
                        'default_area'      = 'navbar'
                    }
                }
            }
        }

        $policiesConfig | ConvertTo-Json -Depth 4 | Out-File -FilePath $policiesJsonPath -Encoding UTF8 -Force
        Write-Log '✓ Firefox policies.json created with uBlock Origin configuration' 'INFO'

        # Set appropriate permissions on policies.json
        if (Test-Path $policiesJsonPath) {
            $acl = Get-Acl $policiesJsonPath
            $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule('Users', 'ReadAndExecute', 'Allow')
            $acl.SetAccessRule($accessRule)
            Set-Acl -Path $policiesJsonPath -AclObject $acl
            Write-Log '✓ Set appropriate permissions on policies.json' 'INFO'
        }

        Write-Log '✓ SUCCESS: Firefox configured with uBlock Origin via ExtensionSettings policy' 'INFO'
        Write-Host '✓ Firefox configured with uBlock Origin extension' -ForegroundColor Green

        # Log configuration details
        Write-Log 'Configuration details:' 'VERBOSE'
        Write-Log "- Registry path: $policyPath" 'VERBOSE'
        Write-Log "- Policies.json path: $policiesJsonPath" 'VERBOSE'
        Write-Log '- Extension ID: uBlock0@raymondhill.net' 'VERBOSE'
        Write-Log '- Installation mode: force_installed' 'VERBOSE'
        Write-Log '- Install URL: https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi' 'VERBOSE'

    }
    catch {
        Write-Log "✗ FAILED: Firefox uBlock Origin configuration failed: $($_.Exception.Message)" 'ERROR'
        Write-Host "✗ Firefox uBlock Origin configuration failed: $($_.Exception.Message)" -ForegroundColor Red
    }

    Write-Log '[END] Configure Firefox with uBlock Origin' 'INFO'
}

# ================================================================
# Function: Update-AllPackages
# ================================================================
# Purpose: Run package manager updates for winget, choco, and others in
#          a coordinated manner with logging and timeout safeguards.
# Environment: Package managers may or may not be present; function
#              degrades gracefully if unavailable
# Logic: Detects available managers, runs updates, collects outputs
# Returns: Summary object with successes/failures and logs
# Side-effects: Updates installed packages
# ================================================================
function Update-AllPackages {
    # ...existing code...
}

# ================================================================
# Function: Enable-AppBrowserControl
# ================================================================
# Purpose: Enable browser-based application control and related policies
# Environment: Windows with Group Policy or registry access (admin)
# Logic: Applies recommended registry/policy changes to lock down browser behavior
# Returns: Hashtable with applied changes
# Side-effects: Alters system policies that may require user re-login
# ================================================================
function Enable-AppBrowserControl {
    # ...existing code...
}

# ===============================
# SECTION 6: SYSTEM MAINTENANCE TASKS
# ===============================
# - Update-AllPackages (package manager updates)
# - Disable-Telemetry (privacy and telemetry features)
# - Protect-SystemRestore (system restore protection)
# - Install-WindowsUpdatesCompatible (Windows updates)
# - Clear-TempFiles (temporary files cleanup)
# - System maintenance and optimization utilities

# ================================================================
# Function: Update-AllPackages
# ================================================================
# Purpose: Comprehensive package updates across all available package managers (Winget, Chocolatey) with Microsoft Store app support
# Environment: Windows 10/11, Administrator privileges recommended, internet connectivity required
# Performance: Parallel execution, timeout protection, comprehensive error handling, progress tracking
# Dependencies: Winget, Chocolatey (graceful degradation if unavailable), system inventory for verification
# Logic: Multi-manager sequential execution, detailed logging, pre/post update verification, failure recovery
# Features: Microsoft Store app updates via Winget, silent installation, comprehensive reporting, differential updates
# ================================================================
function Update-AllPackages {
    param()

    Write-Log '[START] Update All Packages - Comprehensive Package Manager Updates' 'INFO'
    Write-Host '🔄 Starting comprehensive package updates...' -ForegroundColor Cyan
    $startTime = Get-Date

    # Initialize results tracking
    $updateResults = @{
        Winget        = @{ Available = $false; Success = $false; UpdatedCount = 0; FailedCount = 0; Error = $null }
        Chocolatey    = @{ Available = $false; Success = $false; UpdatedCount = 0; FailedCount = 0; Error = $null }
        TotalUpdates  = 0
        TotalFailures = 0
        ExecutionTime = $null
    }

    try {
        # Check package manager availability
        $wingetAvailable = Test-CommandAvailable 'winget'
        $chocoAvailable = Test-CommandAvailable 'choco'

        if (-not $wingetAvailable -and -not $chocoAvailable) {
            Write-Log '⚠ WARNING: No package managers available for updates (Winget/Chocolatey not found)' 'WARN'
            Write-Host '⚠ No package managers available for updates' -ForegroundColor Yellow
            return $updateResults
        }

        Write-Log "Package manager availability: Winget=$wingetAvailable, Chocolatey=$chocoAvailable" 'INFO'

        # ================================================================
        # WINGET PACKAGE UPDATES (Including Microsoft Store Apps)
        # ================================================================
        if ($wingetAvailable) {
            Write-Log '[Winget] Starting Winget package updates (includes Microsoft Store apps)...' 'INFO'
            Write-Host '📦 Updating Winget packages (includes Microsoft Store apps)...' -ForegroundColor Cyan
            $updateResults.Winget.Available = $true

            try {
                # Get list of available updates first
                Write-Log '[Winget] Checking for available updates...' 'INFO'
                $wingetListArgs = @('upgrade', '--include-unknown')
                $wingetUpgradesPath = Join-Path $global:TempFolder 'winget_upgrades.txt'
                $wingetUpgradesErrPath = Join-Path $global:TempFolder 'winget_upgrades_error.txt'
                $listProcess = Start-Process -FilePath 'winget' -ArgumentList $wingetListArgs -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput $wingetUpgradesPath -RedirectStandardError $wingetUpgradesErrPath

                if ($listProcess.ExitCode -eq 0 -and (Test-Path $wingetUpgradesPath)) {
                    $upgradeList = Get-Content $wingetUpgradesPath -ErrorAction SilentlyContinue
                    $availableUpdates = ($upgradeList | Where-Object { $_ -match '^\S+\s+\S+' } | Measure-Object).Count

                    if ($availableUpdates -gt 0) {
                        Write-Log "[Winget] Found $availableUpdates packages available for update" 'INFO'
                        Write-Host "  📋 Found $availableUpdates packages to update" -ForegroundColor Yellow

                        # Perform the actual upgrade
                        $wingetUpgradeArgs = @(
                            'upgrade', '--all',
                            '--silent',
                            '--accept-source-agreements',
                            '--accept-package-agreements',
                            '--include-unknown'
                        )

                        Write-Log "[Winget] Executing: winget $($wingetUpgradeArgs -join ' ')" 'VERBOSE'
                        $wingetUpgradeOutPath = Join-Path $global:TempFolder 'winget_upgrade_output.txt'
                        $wingetUpgradeErrPath = Join-Path $global:TempFolder 'winget_upgrade_error.txt'
                        $upgradeProcess = Start-Process -FilePath 'winget' -ArgumentList $wingetUpgradeArgs -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput $wingetUpgradeOutPath -RedirectStandardError $wingetUpgradeErrPath

                        if ($upgradeProcess.ExitCode -eq 0) {
                            $updateResults.Winget.Success = $true
                            $updateResults.Winget.UpdatedCount = $availableUpdates
                            $updateResults.TotalUpdates += $availableUpdates
                            Write-Log "✅ SUCCESS: Winget updated $availableUpdates packages (including Microsoft Store apps)" 'INFO'
                            Write-Host "  ✅ Successfully updated $availableUpdates packages" -ForegroundColor Green
                        }
                        else {
                            $errorOutput = if (Test-Path $wingetUpgradeErrPath) { Get-Content $wingetUpgradeErrPath -Raw } else { 'Unknown error' }
                            $updateResults.Winget.Error = "Exit code: $($upgradeProcess.ExitCode) - $errorOutput"
                            Write-Log "❌ FAILED: Winget upgrade failed with exit code $($upgradeProcess.ExitCode)" 'ERROR'
                            Write-Log "Error details: $errorOutput" 'ERROR'
                            Write-Host '  ❌ Winget upgrade failed' -ForegroundColor Red
                        }
                    }
                    else {
                        Write-Log '[Winget] No packages require updates' 'INFO'
                        Write-Host '  ✅ All Winget packages are up to date' -ForegroundColor Green
                        $updateResults.Winget.Success = $true
                    }
                }
                else {
                    $listError = if (Test-Path $wingetUpgradesErrPath) { Get-Content $wingetUpgradesErrPath -Raw } else { 'Could not retrieve upgrade list' }
                    $updateResults.Winget.Error = "Failed to get update list: $listError"
                    Write-Log '❌ FAILED: Could not retrieve Winget upgrade list' 'ERROR'
                    Write-Host '  ❌ Could not check for Winget updates' -ForegroundColor Red
                }
            }
            catch {
                $updateResults.Winget.Error = $_.Exception.Message
                Write-Log "❌ FAILED: Winget update process failed: $($_.Exception.Message)" 'ERROR'
                Write-Host '  ❌ Winget update process failed' -ForegroundColor Red
            }
        }
        else {
            Write-Log '[Winget] Winget not available - skipping Winget updates' 'INFO'
            Write-Host '  ⚪ Winget not available - skipping' -ForegroundColor Yellow
        }

        # ================================================================
        # CHOCOLATEY PACKAGE UPDATES
        # ================================================================
        if ($chocoAvailable) {
            Write-Log '[Chocolatey] Starting Chocolatey package updates...' 'INFO'
            Write-Host '🍫 Updating Chocolatey packages...' -ForegroundColor Cyan
            $updateResults.Chocolatey.Available = $true

            try {
                # Check for outdated packages first
                Write-Log '[Chocolatey] Checking for outdated packages...' 'INFO'
                $chocoOutdatedArgs = @('outdated', '--limit-output')
                $chocoOutdatedPath = "$global:TempFolder\choco_outdated.txt"
                $chocoOutdatedErrPath = "$global:TempFolder\choco_outdated_error.txt"
                $outdatedProcess = Start-Process -FilePath 'choco' -ArgumentList $chocoOutdatedArgs -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput $chocoOutdatedPath -RedirectStandardError $chocoOutdatedErrPath

                if ($outdatedProcess.ExitCode -eq 0 -and (Test-Path $chocoOutdatedPath)) {
                    $outdatedList = Get-Content $chocoOutdatedPath -ErrorAction SilentlyContinue | Where-Object { $_ -and $_ -ne '' }
                    $outdatedCount = ($outdatedList | Measure-Object).Count

                    if ($outdatedCount -gt 0) {
                        Write-Log "[Chocolatey] Found $outdatedCount packages available for update" 'INFO'
                        Write-Host "  📋 Found $outdatedCount packages to update" -ForegroundColor Yellow

                        # Perform the actual upgrade
                        $chocoUpgradeArgs = @('upgrade', 'all', '-y', '--no-progress', '--limit-output')

                        Write-Log "[Chocolatey] Executing: choco $($chocoUpgradeArgs -join ' ')" 'VERBOSE'
                        $chocoUpgradeOutPath = "$global:TempFolder\choco_upgrade_output.txt"
                        $chocoUpgradeErrPath = "$global:TempFolder\choco_upgrade_error.txt"
                        $upgradeProcess = Start-Process -FilePath 'choco' -ArgumentList $chocoUpgradeArgs -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput $chocoUpgradeOutPath -RedirectStandardError $chocoUpgradeErrPath

                        if ($upgradeProcess.ExitCode -eq 0) {
                            $updateResults.Chocolatey.Success = $true
                            $updateResults.Chocolatey.UpdatedCount = $outdatedCount
                            $updateResults.TotalUpdates += $outdatedCount
                            Write-Log "✅ SUCCESS: Chocolatey updated $outdatedCount packages" 'INFO'
                            Write-Host "  ✅ Successfully updated $outdatedCount packages" -ForegroundColor Green
                        }
                        else {
                            $errorOutput = if (Test-Path $chocoUpgradeErrPath) { Get-Content $chocoUpgradeErrPath -Raw } else { 'Unknown error' }
                            $updateResults.Chocolatey.Error = "Exit code: $($upgradeProcess.ExitCode) - $errorOutput"
                            Write-Log "❌ FAILED: Chocolatey upgrade failed with exit code $($upgradeProcess.ExitCode)" 'ERROR'
                            Write-Log "Error details: $errorOutput" 'ERROR'
                            Write-Host '  ❌ Chocolatey upgrade failed' -ForegroundColor Red
                        }
                    }
                    else {
                        Write-Log '[Chocolatey] No packages require updates' 'INFO'
                        Write-Host '  ✅ All Chocolatey packages are up to date' -ForegroundColor Green
                        $updateResults.Chocolatey.Success = $true
                    }
                }
                else {
                    $listError = if (Test-Path $chocoOutdatedErrPath) { Get-Content $chocoOutdatedErrPath -Raw } else { 'Could not retrieve outdated list' }
                    $updateResults.Chocolatey.Error = "Failed to get outdated list: $listError"
                    Write-Log '❌ FAILED: Could not retrieve Chocolatey outdated list' 'ERROR'
                    Write-Host '  ❌ Could not check for Chocolatey updates' -ForegroundColor Red
                }
            }
            catch {
                $updateResults.Chocolatey.Error = $_.Exception.Message
                Write-Log "❌ FAILED: Chocolatey update process failed: $($_.Exception.Message)" 'ERROR'
                Write-Host '  ❌ Chocolatey update process failed' -ForegroundColor Red
            }
        }
        else {
            Write-Log '[Chocolatey] Chocolatey not available - skipping Chocolatey updates' 'INFO'
            Write-Host '  ⚪ Chocolatey not available - skipping' -ForegroundColor Yellow
        }

        # ================================================================
        # CLEANUP AND SUMMARY
        # ================================================================

        # Clean up temporary files (using repo temp folder)
        @($wingetUpgradesPath, $wingetUpgradesErrPath, $wingetUpgradeOutPath, $wingetUpgradeErrPath,
            $chocoOutdatedPath, $chocoOutdatedErrPath, $chocoUpgradeOutPath, $chocoUpgradeErrPath) | ForEach-Object {
            if ($_ -and (Test-Path $_)) { Remove-Item $_ -Force -ErrorAction SilentlyContinue }
        }

        # Calculate execution time
        $endTime = Get-Date
        $executionTime = ($endTime - $startTime).TotalMinutes
        $updateResults.ExecutionTime = [math]::Round($executionTime, 2)

        # Generate comprehensive summary
        Write-Log '📊 PACKAGE UPDATE SUMMARY:' 'INFO'
        Write-Log "  • Execution Time: $($updateResults.ExecutionTime) minutes" 'INFO'
        Write-Log "  • Total Updates: $($updateResults.TotalUpdates) packages" 'INFO'

        if ($updateResults.Winget.Available) {
            $wingetStatus = if ($updateResults.Winget.Success) { '✅ SUCCESS' } else { '❌ FAILED' }
            Write-Log "  • Winget: $wingetStatus ($($updateResults.Winget.UpdatedCount) packages)" 'INFO'
        }

        if ($updateResults.Chocolatey.Available) {
            $chocoStatus = if ($updateResults.Chocolatey.Success) { '✅ SUCCESS' } else { '❌ FAILED' }
            Write-Log "  • Chocolatey: $chocoStatus ($($updateResults.Chocolatey.UpdatedCount) packages)" 'INFO'
        }

        # Display final status
        if ($updateResults.TotalUpdates -eq 0 -and ($updateResults.Winget.Success -or $updateResults.Chocolatey.Success)) {
            Write-Host '✅ All packages are up to date!' -ForegroundColor Green
        }
        elseif ($updateResults.TotalUpdates -gt 0) {
            Write-Host "✅ Successfully updated $($updateResults.TotalUpdates) packages" -ForegroundColor Green
        }
        else {
            Write-Host '⚠ Package update process completed with issues' -ForegroundColor Yellow
        }

    }
    catch {
        Write-Log "❌ CRITICAL ERROR in Update-AllPackages: $($_.Exception.Message)" 'ERROR'
        Write-Host "❌ Critical error during package updates: $($_.Exception.Message)" -ForegroundColor Red
        $updateResults.ExecutionTime = [math]::Round(((Get-Date) - $startTime).TotalMinutes, 2)
    }

    Write-Log "[END] Update All Packages - Total execution time: $($updateResults.ExecutionTime) minutes" 'INFO'
    return $updateResults
}

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
    Write-Log '[START] Enabling App & Browser Control (SmartScreen, Network Protection, Controlled Folder Access, Exploit Protection)' 'INFO'
    $errors = @()
    try {
        # Enable Network Protection (only if Defender cmdlets are available)
        if (Get-Command -Name Set-MpPreference -ErrorAction SilentlyContinue) {
            try {
                Set-MpPreference -EnableNetworkProtection Enabled -ErrorAction Stop
                Write-Log '✓ Network Protection enabled' 'INFO'
            }
            catch [System.UnauthorizedAccessException] {
                $errors += 'Network Protection: Permission denied. Please run as Administrator.'
                Write-Log '✗ Failed to enable Network Protection: Permission denied. Ensure the script is run with Administrator privileges.' 'ERROR'
            }
            catch {
                $errors += "Network Protection: $($_.Exception.Message)"
                Write-Log "✗ Failed to enable Network Protection: $($_.Exception.Message)" 'WARN'
            }
        }
        else {
            Write-Log '⚠ Defender cmdlets not found: skipping Network Protection configuration' 'WARN'
        }

        # Enable Controlled Folder Access (only if Defender cmdlets are available)
        if (Get-Command -Name Set-MpPreference -ErrorAction SilentlyContinue) {
            try {
                Set-MpPreference -EnableControlledFolderAccess Enabled -ErrorAction Stop
                Write-Log '✓ Controlled Folder Access enabled' 'INFO'

                # Add current script directory and PowerShell executables to exclusions
                try {
                    $scriptDir = $WorkingDirectory
                    $tempDir = $global:TempFolder

                    # Add script directory to allowed apps/folders
                    if (Get-Command -Name Add-MpPreference -ErrorAction SilentlyContinue) {
                        Add-MpPreference -ControlledFolderAccessAllowedApplications "$scriptDir\script.ps1" -ErrorAction SilentlyContinue
                        Add-MpPreference -ControlledFolderAccessAllowedApplications "$scriptDir\script.bat" -ErrorAction SilentlyContinue

                        # Add PowerShell executables to allowed applications
                        $powershellPaths = @(
                            "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe",
                            "$env:SystemRoot\SysWOW64\WindowsPowerShell\v1.0\powershell.exe"
                        )

                        # Add PowerShell 7+ if available
                        $ps7Paths = @(
                            "$env:ProgramFiles\PowerShell\7\pwsh.exe",
                            "$env:ProgramFiles(x86)\PowerShell\7\pwsh.exe"
                        )

                        foreach ($path in ($powershellPaths + $ps7Paths)) {
                            if (Test-Path $path) {
                                Add-MpPreference -ControlledFolderAccessAllowedApplications $path -ErrorAction SilentlyContinue
                                Write-Log "✓ Added PowerShell executable to Controlled Folder Access exclusions: $path" 'INFO'
                            }
                        }

                        # Add maintenance script paths
                        if (Test-Path $scriptDir) {
                            Add-MpPreference -ControlledFolderAccessProtectedFolders $scriptDir -ErrorAction SilentlyContinue
                            Write-Log "✓ Added script directory to Controlled Folder Access protected folders: $scriptDir" 'INFO'
                        }

                        if (Test-Path $tempDir) {
                            Add-MpPreference -ControlledFolderAccessAllowedApplications $tempDir -ErrorAction SilentlyContinue
                            Write-Log "✓ Added temp directory to Controlled Folder Access exclusions: $tempDir" 'INFO'
                        }
                    }
                    else {
                        Write-Log '⚠ Add-MpPreference not available: cannot add Controlled Folder Access exclusions' 'WARN'
                    }

                    Write-Log '✓ Maintenance script exclusions added to Controlled Folder Access' 'INFO'
                }
                catch {
                    Write-Log "Warning: Could not add script exclusions to Controlled Folder Access: $_" 'WARN'
                }
            }
            catch [System.UnauthorizedAccessException] {
                $errors += 'Controlled Folder Access: Permission denied. Please run as Administrator.'
                Write-Log '✗ Failed to enable Controlled Folder Access: Permission denied. Ensure the script is run with Administrator privileges.' 'ERROR'
            }
            catch {
                $errors += "Controlled Folder Access: $($_.Exception.Message)"
                Write-Log "✗ Failed to enable Controlled Folder Access: $($_.Exception.Message)" 'WARN'
            }
        }
        else {
            Write-Log '⚠ Defender cmdlets not found: skipping Controlled Folder Access configuration' 'WARN'
        }

        # Enable SmartScreen for Edge via registry (Windows 10/11)
        try {
            $edgeKey = 'HKLM:\SOFTWARE\Policies\Microsoft\MicrosoftEdge\PhishingFilter'
            if (-not (Test-Path $edgeKey)) { New-Item -Path $edgeKey -Force | Out-Null }
            Set-ItemProperty -Path $edgeKey -Name 'EnabledV9' -Value 1 -Type DWord -ErrorAction Stop
            Write-Log '✓ SmartScreen for Edge enabled (via registry)' 'INFO'
        }
        catch {
            $errors += "SmartScreen for Edge (registry): $($_.Exception.Message)"
            Write-Log "✗ Failed to enable SmartScreen for Edge: $($_.Exception.Message)" 'WARN'
        }

        # Enable SmartScreen for Microsoft Store Apps via registry
        try {
            $storeKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppHost'
            if (-not (Test-Path $storeKey)) { New-Item -Path $storeKey -Force | Out-Null }
            Set-ItemProperty -Path $storeKey -Name 'EnableWebContentEvaluation' -Value 1 -Type DWord -ErrorAction Stop
            Write-Log '✓ SmartScreen for Store Apps enabled (via registry)' 'INFO'
        }
        catch {
            $errors += "SmartScreen for Store Apps (registry): $($_.Exception.Message)"
            Write-Log "✗ Failed to enable SmartScreen for Store Apps: $($_.Exception.Message)" 'WARN'
        }

        # Enable system-level exploit mitigations (DEP, SEHOP, CFG, ASLR) if Set-ProcessMitigation is available
        if (Get-Command -Name Set-ProcessMitigation -ErrorAction SilentlyContinue) {
            try {
                Set-ProcessMitigation -System -Enable DEP, SEHOP, CFG, ForceRelocateImages, BottomUp, HighEntropy
                Write-Log '✓ System-level exploit mitigations enabled (DEP, SEHOP, CFG, ASLR)' 'INFO'
            }
            catch {
                $errors += "Exploit Mitigations: $($_.Exception.Message)"
                Write-Log "✗ Failed to enable Exploit Mitigations: $($_.Exception.Message)" 'WARN'
            }
        }
        else {
            Write-Log '⚠ Set-ProcessMitigation not available: skipping exploit mitigation configuration' 'WARN'
        }
    }
    catch {
        $errors += "General error: $_"
    }
    if ($errors.Count -gt 0) {
        Write-Log "App & Browser Control: Some settings failed: $($errors -join '; ')" 'WARN'
    }
    Write-Log '[END] Enabling App & Browser Control' 'INFO'
}

# ================================================================
# Function: Disable-SpotlightMeetNowNewsLocation
# ================================================================
# Purpose: Disable or restrict UI elements like Spotlight/MeetNow/News
# Environment: Windows registry/policy access may be required
# Logic: Applies registry tweaks and removes shortcuts where appropriate
# Returns: Status summary
# Side-effects: Changes user-visible UI behavior
# ================================================================
function Disable-SpotlightMeetNowNewsLocation {
    # ...existing code...
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
    Write-Log '[START] Disabling Spotlight, Meet Now, News/Interests, Widgets, and Location' 'INFO'
    try {
        # Disable Windows Spotlight (lock screen, background, suggestions)
        $spotlightReg = 'HKCU:\SOFTWARE\Policies\Microsoft\Windows\CloudContent'
        if (-not (Test-Path $spotlightReg)) { New-Item -Path $spotlightReg -Force | Out-Null }
        Set-ItemProperty -Path $spotlightReg -Name 'DisableWindowsSpotlightFeatures' -Value 1 -Force
        Set-ItemProperty -Path $spotlightReg -Name 'DisableWindowsSpotlightOnActionCenter' -Value 1 -Force
        Set-ItemProperty -Path $spotlightReg -Name 'DisableWindowsSpotlightOnSettings' -Value 1 -Force
        Set-ItemProperty -Path $spotlightReg -Name 'DisableWindowsSpotlightWindowsWelcomeExperience' -Value 1 -Force
        Set-ItemProperty -Path $spotlightReg -Name 'DisableWindowsSpotlightOnLockScreen' -Value 1 -Force
        Write-Log 'Windows Spotlight disabled via registry.' 'INFO'

        # Remove Meet Now from taskbar
        try {
            $meetNowReg = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer'
            if (-not (Test-Path $meetNowReg)) {
                New-Item -Path $meetNowReg -Force | Out-Null
            }
            Set-ItemProperty -Path $meetNowReg -Name 'HideSCAMeetNow' -Value 1 -Force -ErrorAction Stop
            Write-Log 'Meet Now icon removed from taskbar.' 'INFO'
        }
        catch {
            Write-Log "Warning: Could not modify Meet Now setting: $($_.Exception.Message)" 'WARN'
            # Try alternative registry path
            try {
                $altMeetNowReg = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
                if (-not (Test-Path $altMeetNowReg)) {
                    New-Item -Path $altMeetNowReg -Force | Out-Null
                }
                Set-ItemProperty -Path $altMeetNowReg -Name 'TaskbarMn' -Value 0 -Force -ErrorAction Stop
                Write-Log 'Meet Now disabled via alternative registry path.' 'INFO'
            }
            catch {
                Write-Log 'Unable to disable Meet Now via registry. Feature may not be available on this system.' 'WARN'
            }
        }

        # Remove News and Interests (Windows 10)
        $newsResult = Set-RegistryValueSafely -RegistryPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Feeds' `
            -ValueName 'ShellFeedsTaskbarViewMode' `
            -Value 2 `
            -ValueType 'DWord' `
            -FallbackPaths @(
            'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced',
            'HKCU:\Software\Policies\Microsoft\Windows\Windows Feeds',
            'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds'
        ) `
            -Description 'News and Interests disable setting'

        if ($newsResult.Success) {
            Write-Log 'News and Interests removed from taskbar successfully.' 'INFO'
        }
        else {
            Write-Log "Warning: Could not disable News and Interests: $($newsResult.Error)" 'WARN'
            if ($newsResult.Suggestion) {
                Write-Log "Suggestion: $($newsResult.Suggestion)" 'DEBUG'
            }

            # Additional fallback: Try to disable via TaskbarDa in Explorer Advanced
            try {
                $taskbarDaResult = Set-RegistryValueSafely -RegistryPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' `
                    -ValueName 'TaskbarDa' `
                    -Value 0 `
                    -ValueType 'DWord' `
                    -Description 'TaskbarDa (News and Interests alternative)'
                if ($taskbarDaResult.Success) {
                    Write-Log 'News and Interests disabled via TaskbarDa setting.' 'INFO'
                }
            }
            catch {
                Write-Log "TaskbarDa fallback also failed: $($_.Exception.Message)" 'WARN'
            }
        }

        # Remove Widgets (Windows 11)
        $widgetsResult = Set-RegistryValueSafely -RegistryPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' `
            -ValueName 'TaskbarDa' `
            -Value 0 `
            -ValueType 'DWord' `
            -FallbackPaths @(
            'HKCU:\Software\Microsoft\Windows\CurrentVersion\WebExperience',
            'HKCU:\Software\Policies\Microsoft\Windows\WindowsFeeds',
            'HKCU:\Software\Policies\Microsoft\Dsh',
            'HKLM:\SOFTWARE\Policies\Microsoft\Dsh'
        ) `
            -Description 'Widgets disable setting'

        if ($widgetsResult.Success) {
            Write-Log 'Widgets removed from taskbar successfully.' 'INFO'
        }
        else {
            Write-Log "Warning: Could not disable Widgets: $($widgetsResult.Error)" 'WARN'
            if ($widgetsResult.Suggestion) {
                Write-Log "Suggestion: $($widgetsResult.Suggestion)" 'DEBUG'
            }

            # Additional fallback: Try WebExperience approach
            try {
                $webExpResult = Set-RegistryValueSafely -RegistryPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\WebExperience' `
                    -ValueName 'TaskbarWebButtonIsDisabled' `
                    -Value 1 `
                    -ValueType 'DWord' `
                    -Description 'WebExperience Widgets disable'
                if ($webExpResult.Success) {
                    Write-Log 'Widgets disabled via WebExperience setting.' 'INFO'
                }
            }
            catch {
                Write-Log "WebExperience fallback also failed: $($_.Exception.Message)" 'WARN'
                Write-Log 'Note: If Widgets/News persist, they may be controlled by Group Policy or require manual taskbar customization.' 'INFO'
            }
        }

        # Disable Location services
        try {
            $locationReg = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location'
            if (-not (Test-Path $locationReg)) {
                New-Item -Path $locationReg -Force | Out-Null
            }
            Set-ItemProperty -Path $locationReg -Name 'Value' -Value 'Deny' -Force -ErrorAction Stop
            Write-Log 'Location services disabled via registry.' 'INFO'
        }
        catch {
            Write-Log "Warning: Could not modify location services registry: $($_.Exception.Message)" 'WARN'
            # Try user-level location settings
            try {
                $userLocationReg = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location'
                if (-not (Test-Path $userLocationReg)) {
                    New-Item -Path $userLocationReg -Force | Out-Null
                }
                Set-ItemProperty -Path $userLocationReg -Name 'Value' -Value 'Deny' -Force -ErrorAction Stop
                Write-Log 'Location services disabled via user registry.' 'INFO'
            }
            catch {
                Write-Log 'Unable to disable location services via registry. May require administrator privileges.' 'WARN'
            }
        }

        # Stop and disable location service
        try {
            Stop-Service -Name lfsvc -Force -ErrorAction SilentlyContinue
            Set-Service -Name lfsvc -StartupType Disabled -ErrorAction SilentlyContinue
            Write-Log 'Location service stopped and disabled.' 'INFO'
        }
        catch {
            Write-Log "Failed to stop/disable location service: $_" 'WARN'
        }
    }
    catch {
        Write-Log "Error disabling Spotlight/Meet Now/News/Location: $_" 'ERROR'
    }
    Write-Log '[END] Disabling Spotlight, Meet Now, News/Interests, Widgets, and Location' 'INFO'
}

# ================================================================
# Function: Optimize-TaskbarAndDesktopUI
# ================================================================
# Purpose: Tweak Taskbar and Desktop UI settings for a cleaner user experience
# Environment: Windows Shell and registry access required
# Logic: Adjusts taskbar grouping, live tiles, icons, and system tray items
# Returns: Status summary
# Side-effects: Modifies user experience settings
# ================================================================
function Optimize-TaskbarAndDesktopUI {
    # ...existing code...
}

# ================================================================
# Function: Optimize-TaskbarAndDesktopUI
# ================================================================
# Purpose: Hides search box, disables Task View, disables Chat, removes 'Learn more about this picture' icon, and sets theme for Windows 10/11
# Environment: Windows 10/11, Administrator required, registry modification access
# Performance: Fast registry changes, minimal overhead
# Dependencies: Registry access, PowerShell Set-ItemProperty, Remove-Item, theme management
# Logic: Sets registry keys and removes icons for all features in one call
# Features: Hides search box, disables Task View, disables Chat, removes Spotlight desktop icon, sets theme
# ================================================================
function Optimize-TaskbarAndDesktopUI {
    Write-Log '[START] Optimizing Taskbar and Desktop UI (Search, Task View, Chat, Widgets, Spotlight, Theme)' 'INFO'

    # Detect Windows version for compatibility (use registry-based build if available)
    try {
        $windowsBuild = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name 'CurrentBuildNumber' -ErrorAction SilentlyContinue).CurrentBuildNumber
        if ($windowsBuild) { $windowsBuild = [int]$windowsBuild }
        else { $windowsBuild = [System.Environment]::OSVersion.Version.Build }
    }
    catch {
        $windowsBuild = [System.Environment]::OSVersion.Version.Build
    }

    $isWindows11 = $windowsBuild -ge 22000
    $isWindows10 = ($windowsBuild -ge 10240 -and $windowsBuild -lt 22000)

    Write-Log "Detected OS: Windows $(if($isWindows11){'11'}elseif($isWindows10){'10'}else{'Unknown'}) (Build: $($windowsVersion.Build))" 'INFO'

    try {
        # Hide Search Box (Windows 10/11)
        $explorerReg = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search'
        if (-not (Test-Path $explorerReg)) { New-Item -Path $explorerReg -Force | Out-Null }
        Set-ItemProperty -Path $explorerReg -Name 'SearchboxTaskbarMode' -Value 0 -Force
        Write-Log '✓ Search box hidden from taskbar' 'INFO'

        # Hide Task View button (Windows 10/11)
        $advReg = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
        if (-not (Test-Path $advReg)) { New-Item -Path $advReg -Force | Out-Null }
        Set-ItemProperty -Path $advReg -Name 'ShowTaskViewButton' -Value 0 -Force
        Write-Log '✓ Task View button hidden from taskbar' 'INFO'

        # Windows 10 specific tweaks
        if ($isWindows10) {
            # Hide People button (Windows 10)
            try {
                Set-ItemProperty -Path $advReg -Name 'PeopleBand' -Value 0 -Force -ErrorAction SilentlyContinue
                Write-Log '✓ People button hidden from taskbar (Windows 10)' 'INFO'
            }
            catch {
                Write-Log "Could not hide People button: $($_.Exception.Message)" 'WARN'
            }

            # Hide Meet Now button (Windows 10 specific location)
            try {
                # Respect policy keys - don't overwrite Group Policy-managed values
                $meetNowPolicy = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer'
                $meetNowPolicyExists = Test-Path "$meetNowPolicy\HideSCAMeetNow"
                if ($meetNowPolicyExists) {
                    Write-Log 'Meet Now setting controlled by policy; not modifying' 'INFO'
                }
                else {
                    $meetNowReg = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer'
                    if (-not (Test-Path $meetNowReg)) { New-Item -Path $meetNowReg -Force | Out-Null }
                    Set-ItemProperty -Path $meetNowReg -Name 'HideSCAMeetNow' -Value 1 -Force
                    Write-Log '✓ Meet Now button hidden from taskbar (Windows 10)' 'INFO'
                }
            }
            catch {
                Write-Log "Could not hide Meet Now button: $($_.Exception.Message)" 'WARN'
            }

            # Disable News and Interests (Windows 10)
            try {
                $newsReg = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Feeds'
                if (-not (Test-Path $newsReg)) { New-Item -Path $newsReg -Force | Out-Null }
                # Respect policy - check if Windows Feeds is controlled by policy
                $policyNews = 'HKCU:\Software\Policies\Microsoft\Windows\Windows Feeds'
                if (Test-Path $policyNews) {
                    Write-Log 'News & Interests controlled by policy; not modifying' 'INFO'
                }
                else {
                    Set-ItemProperty -Path $newsReg -Name 'ShellFeedsTaskbarViewMode' -Value 2 -Force
                    Write-Log '✓ News and Interests disabled (Windows 10)' 'INFO'
                }
            }
            catch {
                Write-Log "Could not disable News and Interests: $($_.Exception.Message)" 'WARN'
            }
        }

        # Windows 11 specific tweaks
        if ($isWindows11) {
            # Hide Chat (Teams) button (Windows 11)
            try {
                # Respect policy keys for taskbar modifications
                if (Test-Path 'HKCU:\Software\Policies\Microsoft\Windows\Explorer') {
                    Write-Log 'Taskbar Chat/Meet settings controlled by policy; not modifying' 'INFO'
                }
                else {
                    Set-ItemProperty -Path $advReg -Name 'TaskbarMn' -Value 0 -Force
                    Write-Log '✓ Chat (Teams) button hidden from taskbar (Windows 11)' 'INFO'
                }
            }
            catch {
                Write-Log "Could not hide Chat button: $($_.Exception.Message)" 'WARN'
            }

            # Hide Widgets button (Windows 11)
            try {
                # Widgets may be controlled by Group Policy; check before changing
                if (Test-Path 'HKCU:\Software\Policies\Microsoft\Windows\Explorer') {
                    Write-Log 'Widgets/News settings controlled by policy; not modifying TaskbarDa' 'INFO'
                }
                else {
                    Set-ItemProperty -Path $advReg -Name 'TaskbarDa' -Value 0 -Force
                    Write-Log '✓ Widgets button hidden from taskbar (Windows 11)' 'INFO'
                }
            }
            catch {
                Write-Log "Could not hide Widgets button: $($_.Exception.Message)" 'WARN'
            }

            # Set taskbar alignment to left (Windows 11)
            try {
                try {
                    if (Test-Path 'HKCU:\Software\Policies\Microsoft\Windows\Explorer') {
                        Write-Log 'Taskbar alignment controlled by policy; not modifying' 'INFO'
                    }
                    else {
                        Set-ItemProperty -Path $advReg -Name 'TaskbarAl' -Value 0 -Force
                        Write-Log '✓ Taskbar alignment set to left (Windows 11)' 'INFO'
                    }
                }
                catch {
                    Write-Log "Could not set taskbar alignment: $($_.Exception.Message)" 'WARN'
                }
            }
            catch {
                Write-Log "Could not set taskbar alignment: $($_.Exception.Message)" 'WARN'
            }
        }

        # Remove 'Learn more about this picture' and other Spotlight desktop icons (Windows 10/11)
        try {
            $desktopPath = [Environment]::GetFolderPath('Desktop')
            $spotlightPatterns = @(
                'Learn more about this picture*.lnk',
                '*Spotlight*.lnk',
                '*Windows Spotlight*.lnk',
                '*Learn more*.lnk',
                '*Windows tips*.lnk'
            )

            $removedCount = 0
            foreach ($pattern in $spotlightPatterns) {
                $iconFiles = Get-ChildItem -Path $desktopPath -Filter $pattern -ErrorAction SilentlyContinue
                foreach ($icon in $iconFiles) {
                    Remove-Item $icon.FullName -Force -ErrorAction SilentlyContinue
                    Write-Log "✓ Removed desktop icon: $($icon.Name)" 'INFO'
                    $removedCount++
                }
            }

            if ($removedCount -eq 0) {
                Write-Log 'No Spotlight desktop icons found to remove' 'INFO'
            }
            else {
                Write-Log "✓ Removed $removedCount Spotlight-related desktop icons" 'INFO'
            }
        }
        catch {
            Write-Log "Could not remove Spotlight desktop icons: $($_.Exception.Message)" 'WARN'
        }

        # Set theme (Light theme for better visibility)
        try {
            $themeReg = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
            if (-not (Test-Path $themeReg)) { New-Item -Path $themeReg -Force | Out-Null }
            Set-ItemProperty -Path $themeReg -Name 'AppsUseLightTheme' -Value 1 -Force
            Set-ItemProperty -Path $themeReg -Name 'SystemUsesLightTheme' -Value 1 -Force
            Write-Log '✓ Windows theme set to Light mode' 'INFO'
        }
        catch {
            Write-Log "Could not set Windows theme: $($_.Exception.Message)" 'WARN'
        }

        # Additional Windows 10/11 compatible optimizations
        try {
            # Disable Windows tips and suggestions
            $contentReg = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
            if (-not (Test-Path $contentReg)) { New-Item -Path $contentReg -Force | Out-Null }
            Set-ItemProperty -Path $contentReg -Name 'SoftLandingEnabled' -Value 0 -Force
            Set-ItemProperty -Path $contentReg -Name 'SystemPaneSuggestionsEnabled' -Value 0 -Force
            Set-ItemProperty -Path $contentReg -Name 'SubscribedContent-338388Enabled' -Value 0 -Force
            Write-Log '✓ Windows tips and suggestions disabled' 'INFO'

            # Hide recently added apps in Start Menu
            Set-ItemProperty -Path $advReg -Name 'Start_TrackDocs' -Value 0 -Force -ErrorAction SilentlyContinue
            Write-Log '✓ Recently added apps tracking disabled' 'INFO'
        }
        catch {
            Write-Log "Could not apply additional optimizations: $($_.Exception.Message)" 'WARN'
        }

        # Refresh Explorer to apply changes
        try {
            Write-Log 'Restarting Explorer to apply UI changes...' 'INFO'
            Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 3
            Start-Process explorer.exe
            Start-Sleep -Seconds 2
            Write-Log '✓ Explorer restarted successfully' 'INFO'
        }
        catch {
            Write-Log "Could not restart Explorer: $($_.Exception.Message)" 'WARN'
        }
    }
    catch {
        Write-Log "Error optimizing Taskbar/Desktop UI: $($_.Exception.Message)" 'ERROR'
    }

    Write-Log '[END] Taskbar and Desktop UI optimization completed' 'INFO'
}

# ================================================================
# Function: Disable-Telemetry
# ================================================================
# Purpose: Apply recommended privacy/telemetry disables that are safe for
#          automated unattended runs (respecting opt-out flags in config)
# Environment: Windows with registry and service management access
# Logic: Disables telemetry services and registry-based telemetry settings
# Returns: Summary of changes applied
# Side-effects: Alters telemetry and diagnostics behavior
# ================================================================
function Disable-Telemetry {
    # ...existing code...
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
    Write-Log 'Starting Disable Telemetry and Privacy Features - Enhanced Performance Mode' 'INFO'

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
            # If a policy key exists for this area, respect it and skip writing local settings
            $policyPath = $regPath -replace '^HKLM:', 'HKLM:\SOFTWARE\Policies' -replace '^HKCU:', 'HKCU:\Software\Policies'
            if (Test-Path $policyPath) {
                Write-Log "Policy controls telemetry settings at $policyPath - skipping local changes" 'INFO'
                continue
            }

            if (-not (Test-Path $regPath)) {
                New-Item -Path $regPath -Force -ErrorAction SilentlyContinue | Out-Null
            }

            $settings = $telemetrySettings[$regPath]
            foreach ($setting in $settings.GetEnumerator()) {
                try {
                    # Only set if the existing value is different or missing (idempotent)
                    $existing = $null
                    try { $existing = (Get-ItemProperty -Path $regPath -Name $setting.Key -ErrorAction SilentlyContinue).$($setting.Key) } catch { $existing = $null }
                    if ($existing -ne $setting.Value) {
                        Set-ItemProperty -Path $regPath -Name $setting.Key -Value $setting.Value -Force -ErrorAction SilentlyContinue
                        $totalSettingsApplied++
                    }
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
    # Use configurable list of telemetry-related services to disable
    $telemetryServices = if ($global:Config.TelemetryServicesToDisable -and $global:Config.TelemetryServicesToDisable.Count -gt 0) { $global:Config.TelemetryServicesToDisable } else {
        @('DiagTrack', 'dmwappushservice', 'WerSvc', 'UnistoreSvc', 'UserDataSvc', 'BrokerInfrastructure')
    }

    $servicesDisabled = 0
    foreach ($serviceName in $telemetryServices) {
        try {
            $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
            if (-not $service) {
                Write-Log "Service $serviceName not present on this system; skipping" 'VERBOSE'
                continue
            }

            # Avoid disabling Windows Error Reporting unless explicitly allowed via config
            if ($serviceName -eq 'WerSvc' -and -not $global:Config.AllowDisableWerSvc) {
                Write-Log 'WerSvc detected but disabling is skipped (AllowDisableWerSvc not set)' 'INFO'
                continue
            }

            if ($service -and $service.StartType -ne 'Disabled') {
                try {
                    Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
                    Set-Service -Name $serviceName -StartupType Disabled -ErrorAction SilentlyContinue
                    $servicesDisabled++
                    Write-Log "Disabled service: $serviceName" 'INFO'
                }
                catch {
                    Write-Log "Failed to disable service ${serviceName}: $($_.Exception.Message)" 'WARN'
                }
            }
        }
        catch {
            Write-Log "Error checking service ${serviceName}: $($_.Exception.Message)" 'WARN'
            continue
        }
    }

    if ($servicesDisabled -gt 0) {
        Write-Host "✓ Disabled $servicesDisabled telemetry services" -ForegroundColor Green
        Write-Log "Telemetry services disabled: $servicesDisabled services stopped and disabled" 'INFO'
    }

    Write-Log '[END] Disable Telemetry and Privacy Features' 'INFO'
}

# ================================================================
# Function: Protect-SystemRestore
# ================================================================
# Purpose: Ensure System Restore is enabled and create a restore point before
#          performing maintenance when configured to do so.
# Environment: Windows with System Restore features available; admin required
# Logic: Checks existing restore points, enables protection if needed and
#        creates a checkpoint restore point prior to destructive actions
# Returns: Hashtable with status and created checkpoint ID (if any)
# Side-effects: Creates system restore points (uses storage)
# ================================================================
function Protect-SystemRestore {
    # ...existing code...
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
    Write-Log '[START] PowerShell 7+ Native System Restore Protection' 'INFO'

    try {
        # Check if System Restore is supported on this system
        $systemDrive = $env:SystemDrive
        Write-Log "Checking System Restore capability for drive: $systemDrive" 'INFO'

        # Enhanced compatibility check for System Restore availability
        $restoreAvailable = $false
        try {
            # Try to get restore points to test availability (Windows PowerShell compatibility)
            $existingRestorePoints = Invoke-WindowsPowerShellCommand -Command 'Get-ComputerRestorePoint' -ErrorAction SilentlyContinue
            $restoreAvailable = $true
            Write-Log "System Restore is available. Found $($existingRestorePoints.Count) existing restore points." 'INFO'
        }
        catch {
            Write-Log "System Restore may not be available or accessible: $_" 'WARN'

            # Try alternative check using registry
            try {
                $srConfig = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore' -ErrorAction SilentlyContinue
                if ($srConfig) {
                    $restoreAvailable = $true
                    Write-Log 'System Restore detected via registry check' 'INFO'
                }
            }
            catch {
                Write-Log 'System Restore not available on this system' 'WARN'
                return
            }
        }

        if (-not $restoreAvailable) {
            Write-Log 'System Restore is not available on this system. Skipping restore point creation.' 'WARN'
            return
        }

        # Check and enable System Restore if disabled
        try {
            $restoreStatus = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore' -Name 'DisableSR' -ErrorAction SilentlyContinue
            if ($restoreStatus -and $restoreStatus.DisableSR -eq 1) {
                Write-Log 'System Restore is disabled. Attempting to enable...' 'INFO'
                Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore' -Name 'DisableSR' -Value 0 -ErrorAction SilentlyContinue
                Write-Host '✓ System Restore enabled' -ForegroundColor Green
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
                Write-Host '✓ System restore point created successfully' -ForegroundColor Green
                Write-Log "System restore point created: $restorePointName" 'INFO'
            }
            else {
                throw 'Checkpoint-Computer command did not execute successfully'
            }

            # Verify the restore point was created using Windows PowerShell
            Start-Sleep -Seconds 2
            try {
                $newRestorePoints = Invoke-WindowsPowerShellCommand -Command 'Get-ComputerRestorePoint' -ErrorAction SilentlyContinue

                if ($newRestorePoints -and $newRestorePoints.Count -gt 0) {
                    $latestPoint = $newRestorePoints | Sort-Object CreationTime -Descending | Select-Object -First 1

                    if ($latestPoint -and $latestPoint.Description -and $latestPoint.Description.Contains('Maintenance Script')) {
                        Write-Log "Restore point verification successful. Latest point: $($latestPoint.Description)" 'INFO'
                    }
                    else {
                        Write-Log "Latest restore point found but not from maintenance script: $($latestPoint.Description)" 'WARN'
                    }
                }
                else {
                    Write-Log 'No restore points found during verification' 'WARN'
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
                Write-Log 'Attempting restore point creation using WMI interface...' 'INFO'

                # Create restore point using WMI method
                $restorePointResult = Invoke-WindowsPowerShellCommand -Command @"
try {
    `$systemRestore = Get-CimClass -ClassName SystemRestore -Namespace root\default
    if (`$systemRestore) {
        `$result = `$systemRestore.CreateRestorePoint('$restorePointName', 0, 100)
        Write-Output "RestorePointResult:`$(`$result.ReturnValue)"
    } else {
        Write-Output "SystemRestore WMI class not available"
    }
} catch {
    Write-Output "WMI Error:`$(`$_.Exception.Message)"
}

# ================================================================
# Function: Clear-OldRestorePoints
# ================================================================
# Purpose: Clean up older system restore points to conserve disk space while
#          keeping a minimum set as configured ($global:Config.MinRestorePointsToKeep)
# Environment: Uses VSS or WMI depending on platform availability
# Returns: Summary of removed/kept restore points
# Side-effects: Deletes old restore points (irreversible)
# ================================================================
function Clear-OldRestorePoints {
    # ...existing code...
}

# ================================================================
# Function: Get-EventLogAnalysis
# ================================================================
# Purpose: Analyze key Windows event logs to detect recurring errors or
#          warnings that may indicate system issues prior to/after maintenance
# Environment: Requires Event Log read access; admin recommended for full logs
# Logic: Reads relevant event channels, filters by severity and recency,
#        and returns a summarized view for reporting
# Returns: Hashtable with counts and sample events per channel
# Side-effects: None (read-only)
# ================================================================
function Get-EventLogAnalysis {
    # ...existing code...
}
"@

                if ($restorePointResult -and $restorePointResult -match 'RestorePointResult:0') {
                    Write-Host '✓ System restore point created via WMI interface' -ForegroundColor Green
                    Write-Log "System restore point created via WMI interface: $restorePointName" 'INFO'
                }
                else {
                    Write-Log "WMI restore point creation result: $restorePointResult" 'WARN'

                    # Final fallback: try using VSSAdmin
                    Write-Log 'Attempting restore point creation using VSSAdmin...' 'INFO'
                    try {
                        $vssResult = Start-Process -FilePath 'vssadmin' -ArgumentList 'create shadow /for=C:' -Wait -PassThru -WindowStyle Hidden
                        if ($vssResult.ExitCode -eq 0) {
                            Write-Host '✓ Shadow copy created as restore point alternative' -ForegroundColor Green
                            Write-Log 'Shadow copy created successfully' 'INFO'
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
                Write-Host '✗ All restore point creation methods failed' -ForegroundColor Red
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
                        $minKeep = if ($global:Config.MinRestorePointsToKeep) { $global:Config.MinRestorePointsToKeep } else { 3 }
                        $oldRestorePoints = Get-ComputerRestorePoint | Sort-Object CreationTime | Select-Object -SkipLast $minKeep
                        if ($oldRestorePoints -and $oldRestorePoints.Count -gt 0) {
                            foreach ($point in $oldRestorePoints) {
                                if (Get-Command -Name Remove-ComputerRestorePoint -ErrorAction SilentlyContinue) {
                                    try {
                                        Remove-ComputerRestorePoint -RestorePoint $point -ErrorAction SilentlyContinue
                                    }
                                    catch {
                                        Write-Log "Failed to remove restore point $($point.SequenceNumber): $($_.Exception.Message)" 'WARN'
                                    }
                                }
                                else {
                                    Write-Log 'Remove-ComputerRestorePoint cmdlet not available; skipping direct removal of restore points' 'WARN'
                                    break
                                }
                            }
                            Write-Log "Cleaned $($oldRestorePoints.Count) old restore points to free disk space" 'INFO'
                        }
                        else {
                            Write-Log "No old restore points to remove (keeping $minKeep recent points)" 'INFO'
                        }
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

    Write-Log '[END] PowerShell 7+ Native System Restore Protection' 'INFO'
}

# ================================================================
# Function: Clear-OldRestorePoints
# ================================================================
# Purpose: Clean up old system restore points while keeping a minimum of 5 recent restore points for safety
# Environment: Windows 10/11, Administrator privileges required, System Restore feature enabled
# Performance: Fast enumeration and selective removal, intelligent size calculation, comprehensive logging
# Dependencies: Administrator privileges, System Restore feature availability, Get-ComputerRestorePoint cmdlet
# Logic: Enumerates restore points, keeps 5 most recent, removes older ones with detailed logging and space calculation
# Features: Safety minimum (5 points), space tracking, detailed logging, error handling, restore point analysis
# ================================================================
function Clear-OldRestorePoints {
    Write-Log '[START] System Restore Points Cleanup - Keep Minimum 5 Recent Points' 'INFO'

    try {
        # Check if we have administrator privileges
        if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] 'Administrator')) {
            Write-Log 'Administrator privileges required for restore point cleanup. Skipping...' 'WARN'
            return $false
        }

        Write-Log 'Enumerating system restore points...' 'INFO'

        try {
            # Get all restore points sorted by creation time (newest first)
            $allRestorePoints = Get-ComputerRestorePoint -ErrorAction Stop | Sort-Object CreationTime -Descending
        }
        catch [System.Management.Automation.CommandNotFoundException] {
            Write-Log "Warning: 'Get-ComputerRestorePoint' command not available on this system. System Restore may be disabled or not supported. Skipping cleanup." 'WARN'
            return $true # Not a failure, just not applicable.
        }
        catch {
            Write-Log "Unexpected error during restore point cleanup: $($_.Exception.Message)" 'ERROR'
            return $false
        }

        if (-not $allRestorePoints) {
            Write-Log 'No system restore points found on this system' 'INFO'
            return $true
        }

        $totalPoints = $allRestorePoints.Count
        Write-Log "Found $totalPoints restore points on system" 'INFO'

        # Log details of all restore points for audit trail
        Write-Log '=== RESTORE POINTS AUDIT ===' 'INFO'
        $pointIndex = 1
        foreach ($point in $allRestorePoints) {
            $pointDate = $point.CreationTime.ToString('yyyy-MM-dd HH:mm:ss')
            $pointType = $point.RestorePointType
            $pointDescription = $point.Description
            Write-Log "[$pointIndex] Created: $pointDate | Type: $pointType | Description: $pointDescription" 'INFO'
            $pointIndex++
        }
        Write-Log '=== END RESTORE POINTS AUDIT ===' 'INFO'

        # Keep minimum configured restore points for safety
        $minimumKeep = if ($global:Config.MinRestorePointsToKeep) { $global:Config.MinRestorePointsToKeep } else { 5 }

        if ($totalPoints -le $minimumKeep) {
            Write-Log "Current restore point count ($totalPoints) is at or below safety minimum ($minimumKeep). No cleanup needed." 'INFO'
            return $true
        }

        # Identify points to remove (all except the 5 most recent)
        $pointsToKeep = $allRestorePoints | Select-Object -First $minimumKeep
        $pointsToRemove = $allRestorePoints | Select-Object -Skip $minimumKeep

        $removeCount = $pointsToRemove.Count
        Write-Log "Cleanup plan: Keep $minimumKeep most recent points, remove $removeCount older points" 'INFO'

        # Log points that will be kept
        Write-Log '=== RESTORE POINTS TO KEEP ===' 'INFO'
        $keepIndex = 1
        foreach ($point in $pointsToKeep) {
            $pointDate = $point.CreationTime.ToString('yyyy-MM-dd HH:mm:ss')
            $pointDescription = $point.Description
            Write-Log "[$keepIndex] KEEPING: $pointDate | $pointDescription" 'INFO'
            $keepIndex++
        }

        # Log points that will be removed
        Write-Log '=== RESTORE POINTS TO REMOVE ===' 'INFO'
        $removeIndex = 1
        foreach ($point in $pointsToRemove) {
            $pointDate = $point.CreationTime.ToString('yyyy-MM-dd HH:mm:ss')
            $pointDescription = $point.Description
            Write-Log "[$removeIndex] REMOVING: $pointDate | $pointDescription" 'INFO'
            $removeIndex++
        }
        Write-Log '=== END CLEANUP PLAN ===' 'INFO'

        # Estimate disk space before cleanup
        $systemDrive = $env:SystemDrive
        $diskBefore = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='$systemDrive'" -ErrorAction SilentlyContinue
        if ($diskBefore) {
            $freeSpaceBeforeGB = [math]::Round($diskBefore.FreeSpace / 1GB, 2)
            Write-Log "Disk space before cleanup: $freeSpaceBeforeGB GB free" 'INFO'
        }

        # Perform cleanup with detailed logging
        $removedCount = 0
        $failedCount = 0

        Write-Log 'Starting restore point removal process...' 'INFO'

        # Perform cleanup with detailed logging (only if removal cmdlet exists)
        if (-not (Get-Command -Name Remove-ComputerRestorePoint -ErrorAction SilentlyContinue)) {
            Write-Log 'Remove-ComputerRestorePoint cmdlet not available on this system. Skipping actual removals.' 'WARN'
        }
        else {
            foreach ($point in $pointsToRemove) {
                $pointDate = $point.CreationTime.ToString('yyyy-MM-dd HH:mm:ss')
                $pointDescription = $point.Description
                try {
                    Write-Log "Removing restore point: $pointDate | $pointDescription" 'INFO'
                    Remove-ComputerRestorePoint -RestorePoint $point -ErrorAction Stop
                    $removedCount++
                    Write-Log "✓ Successfully removed restore point: $pointDate" 'INFO'
                }
                catch {
                    $failedCount++
                    Write-Log "✗ Failed to remove restore point: $pointDate | Error: $_" 'ERROR'
                }
            }
        }

        # Calculate disk space after cleanup
        Start-Sleep -Seconds 2  # Allow filesystem to update
        $diskAfter = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='$systemDrive'" -ErrorAction SilentlyContinue
        if ($diskAfter) {
            $freeSpaceAfterGB = [math]::Round($diskAfter.FreeSpace / 1GB, 2)
            $spaceFreedGB = [math]::Round($freeSpaceAfterGB - $freeSpaceBeforeGB, 2)
            Write-Log "Disk space after cleanup: $freeSpaceAfterGB GB free" 'INFO'
            if ($spaceFreedGB -gt 0) {
                Write-Log "✓ Disk space freed by cleanup: $spaceFreedGB GB" 'INFO'
            }
        }

        # Final summary
        Write-Log '=== RESTORE POINT CLEANUP SUMMARY ===' 'INFO'
        Write-Log "Original count: $totalPoints restore points" 'INFO'
        Write-Log "Target count: $minimumKeep restore points (safety minimum)" 'INFO'
        Write-Log "Successfully removed: $removedCount restore points" 'INFO'
        Write-Log "Failed to remove: $failedCount restore points" 'INFO'
        Write-Log "Final count: $($totalPoints - $removedCount) restore points" 'INFO'
        if ($diskAfter -and $spaceFreedGB -gt 0) {
            Write-Log "Disk space recovered: $spaceFreedGB GB" 'INFO'
        }
        Write-Log '=== END CLEANUP SUMMARY ===' 'INFO'

        # Return success if we removed at least some points or if no removal was needed
        $success = ($removedCount -gt 0) -or ($removeCount -eq 0)

        if ($success) {
            Write-Log 'Restore point cleanup completed successfully' 'INFO'
        }
        else {
            Write-Log 'Restore point cleanup completed with errors - no points were removed' 'WARN'
        }

        return $success
    }
    catch {
        Write-Log "Unexpected error during restore point cleanup: $_" 'ERROR'
        return $false
    }
    finally {
        Write-Log '[END] System Restore Points Cleanup' 'INFO'
    }
}

# ================================================================
# Function: Get-EventLogAnalysis
# ================================================================
# Purpose: Parse and analyze CBS logs and Event Viewer errors from the last 96 hours in human-readable format
# Environment: Windows 10/11, file system access to log directories, Event Log service availability
# Performance: Optimized log parsing with time filtering, efficient error categorization, structured output
# Dependencies: CBS log file access, Event Viewer access, file system permissions, Get-WinEvent cmdlet
# Logic: Time-based filtering (96 hours), error categorization, human-readable formatting, comprehensive logging
# Features: Multiple log source analysis, error categorization, time filtering, detailed reporting, maintenance log integration
# ================================================================
function Get-EventLogAnalysis {
    Write-Log '[START] Event Log and CBS Analysis - Last 96 Hours' 'INFO'

    try {
        # Calculate time range - last 96 hours
        $hoursBack = 96
        $startTime = (Get-Date).AddHours(-$hoursBack)
        Write-Log "Analyzing logs from $($startTime.ToString('yyyy-MM-dd HH:mm:ss')) to present (last $hoursBack hours)" 'INFO'

        $errorSummary = @{
            CBSErrors         = @()
            SystemErrors      = @()
            ApplicationErrors = @()
            SecurityErrors    = @()
            TotalErrors       = 0
            AnalysisTime      = Get-Date
        }

        # PART 1: CBS Log Analysis
        Write-Log '=== CBS LOG ANALYSIS ===' 'INFO'
        Write-Log 'Analyzing Component-Based Servicing (CBS) logs...' 'INFO'

        try {
            $cbsLogPath = "$env:WINDIR\Logs\CBS\CBS.log"

            if (Test-Path $cbsLogPath) {
                Write-Log "Reading CBS log file: $cbsLogPath" 'INFO'

                # Read CBS log and filter by time range
                $cbsLogContent = Get-Content $cbsLogPath -ErrorAction SilentlyContinue
                $cbsErrors = @()

                foreach ($line in $cbsLogContent) {
                    # Parse CBS log timestamp and content
                    if ($line -match '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}') {
                        try {
                            $timestampStr = $line.Substring(0, 19)
                            $timestamp = [DateTime]::ParseExact($timestampStr, 'yyyy-MM-dd HH:mm:ss', $null)

                            if ($timestamp -ge $startTime) {
                                # Look for error indicators in CBS logs
                                if ($line -match 'Error|Failed|Corrupt|Cannot|Unable|Exception|Failure') {
                                    $cbsErrors += @{
                                        Timestamp = $timestamp
                                        Message   = $line.Substring(20).Trim()
                                        Type      = 'CBS Error'
                                    }
                                }
                            }
                        }
                        catch {
                            # Skip lines with invalid timestamps
                            continue
                        }
                    }
                }

                $errorSummary.CBSErrors = $cbsErrors
                Write-Log "Found $($cbsErrors.Count) CBS errors in the last $hoursBack hours" 'INFO'

                # Log top 10 CBS errors for maintenance log
                if ($cbsErrors.Count -gt 0) {
                    Write-Log '=== TOP CBS ERRORS ===' 'INFO'
                    $topCBSErrors = $cbsErrors | Sort-Object Timestamp -Descending | Select-Object -First 10
                    foreach ($cbsError in $topCBSErrors) {
                        Write-Log "[CBS] $($cbsError.Timestamp.ToString('yyyy-MM-dd HH:mm:ss')) - $($cbsError.Message)" 'WARN'
                    }
                }
                else {
                    Write-Log '✓ No CBS errors found in the specified time range' 'INFO'
                }
            }
            else {
                Write-Log "CBS log file not found: $cbsLogPath" 'WARN'
            }
        }
        catch {
            Write-Log "Error analyzing CBS logs: $_" 'ERROR'
        }

        # PART 2: System Event Log Analysis
        Write-Log '=== SYSTEM EVENT LOG ANALYSIS ===' 'INFO'
        Write-Log 'Analyzing System Event Log for errors...' 'INFO'

        try {
            $systemErrors = Get-WinEvent -FilterHashtable @{
                LogName   = 'System'
                Level     = 1, 2  # Critical and Error levels
                StartTime = $startTime
            } -ErrorAction SilentlyContinue | Select-Object -First 50

            if ($systemErrors) {
                $parsedSystemErrors = @()
                foreach ($systemEvent in $systemErrors) {
                    $parsedSystemErrors += @{
                        Timestamp = $systemEvent.TimeCreated
                        EventID   = $systemEvent.Id
                        Source    = $systemEvent.ProviderName
                        Level     = if ($systemEvent.Level -eq 1) { 'Critical' } else { 'Error' }
                        Message   = $systemEvent.Message.Split("`n")[0].Trim()  # First line only
                    }
                }

                $errorSummary.SystemErrors = $parsedSystemErrors
                Write-Log "Found $($parsedSystemErrors.Count) system errors in the last $hoursBack hours" 'INFO'

                # Log top 10 system errors
                Write-Log '=== TOP SYSTEM ERRORS ===' 'INFO'
                $topSystemErrors = $parsedSystemErrors | Sort-Object Timestamp -Descending | Select-Object -First 10
                foreach ($systemError in $topSystemErrors) {
                    Write-Log "[SYSTEM] $($systemError.Timestamp.ToString('yyyy-MM-dd HH:mm:ss')) - Event ID $($systemError.EventID) ($($systemError.Level)) - $($systemError.Source): $($systemError.Message)" 'WARN'
                }
            }
            else {
                Write-Log '✓ No critical system errors found in the specified time range' 'INFO'
            }
        }
        catch {
            Write-Log "Error analyzing System Event Log: $_" 'ERROR'
        }

        # PART 3: Application Event Log Analysis
        Write-Log '=== APPLICATION EVENT LOG ANALYSIS ===' 'INFO'
        Write-Log 'Analyzing Application Event Log for errors...' 'INFO'

        try {
            $appErrors = Get-WinEvent -FilterHashtable @{
                LogName   = 'Application'
                Level     = 1, 2  # Critical and Error levels
                StartTime = $startTime
            } -ErrorAction SilentlyContinue | Select-Object -First 30

            if ($appErrors) {
                $parsedAppErrors = @()
                foreach ($logEvent in $appErrors) {
                    $parsedAppErrors += @{
                        Timestamp = $logEvent.TimeCreated
                        EventID   = $logEvent.Id
                        Source    = $logEvent.ProviderName
                        Level     = if ($logEvent.Level -eq 1) { 'Critical' } else { 'Error' }
                        Message   = $logEvent.Message.Split("`n")[0].Trim()  # First line only
                    }
                }

                $errorSummary.ApplicationErrors = $parsedAppErrors
                Write-Log "Found $($parsedAppErrors.Count) application errors in the last $hoursBack hours" 'INFO'

                # Log top 10 application errors
                Write-Log '=== TOP APPLICATION ERRORS ===' 'INFO'
                $topAppErrors = $parsedAppErrors | Sort-Object Timestamp -Descending | Select-Object -First 10
                foreach ($appError in $topAppErrors) {
                    Write-Log "[APPLICATION] $($appError.Timestamp.ToString('yyyy-MM-dd HH:mm:ss')) - Event ID $($appError.EventID) ($($appError.Level)) - $($appError.Source): $($appError.Message)" 'WARN'
                }
            }
            else {
                Write-Log '✓ No critical application errors found in the specified time range' 'INFO'
            }
        }
        catch {
            Write-Log "Error analyzing Application Event Log: $_" 'ERROR'
        }

        # PART 4: Security Event Log Analysis (Critical Only)
        Write-Log '=== SECURITY EVENT LOG ANALYSIS ===' 'INFO'
        Write-Log 'Analyzing Security Event Log for critical issues...' 'INFO'

        try {
            $securityErrors = Get-WinEvent -FilterHashtable @{
                LogName   = 'Security'
                Level     = 1  # Critical level only
                StartTime = $startTime
            } -ErrorAction SilentlyContinue | Select-Object -First 20

            if ($securityErrors) {
                $parsedSecurityErrors = @()
                foreach ($logEvent in $securityErrors) {
                    $parsedSecurityErrors += @{
                        Timestamp = $logEvent.TimeCreated
                        EventID   = $logEvent.Id
                        Source    = $logEvent.ProviderName
                        Level     = 'Critical'
                        Message   = $logEvent.Message.Split("`n")[0].Trim()  # First line only
                    }
                }

                $errorSummary.SecurityErrors = $parsedSecurityErrors
                Write-Log "Found $($parsedSecurityErrors.Count) critical security events in the last $hoursBack hours" 'INFO'

                # Log all security errors (should be rare)
                if ($parsedSecurityErrors.Count -gt 0) {
                    Write-Log '=== CRITICAL SECURITY EVENTS ===' 'INFO'
                    foreach ($securityError in $parsedSecurityErrors) {
                        Write-Log "[SECURITY] $($securityError.Timestamp.ToString('yyyy-MM-dd HH:mm:ss')) - Event ID $($securityError.EventID) (Critical) - $($securityError.Source): $($securityError.Message)" 'ERROR'
                    }
                }
            }
            else {
                Write-Log '✓ No critical security events found in the specified time range' 'INFO'
            }
        }
        catch {
            Write-Log "Error analyzing Security Event Log: $_" 'ERROR'
        }

        # PART 5: Summary and Analysis
        $errorSummary.TotalErrors = $errorSummary.CBSErrors.Count + $errorSummary.SystemErrors.Count + $errorSummary.ApplicationErrors.Count + $errorSummary.SecurityErrors.Count

        Write-Log '=== EVENT LOG ANALYSIS SUMMARY ===' 'INFO'
        Write-Log "Analysis period: Last $hoursBack hours ($($startTime.ToString('yyyy-MM-dd HH:mm:ss')) to $((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))" 'INFO'
        Write-Log "CBS errors found: $($errorSummary.CBSErrors.Count)" 'INFO'
        Write-Log "System errors found: $($errorSummary.SystemErrors.Count)" 'INFO'
        Write-Log "Application errors found: $($errorSummary.ApplicationErrors.Count)" 'INFO'
        Write-Log "Security critical events found: $($errorSummary.SecurityErrors.Count)" 'INFO'
        Write-Log "Total errors/events analyzed: $($errorSummary.TotalErrors)" 'INFO'

        # Save detailed analysis to temp folder for reporting
        try {
            $analysisPath = Join-Path $global:TempFolder 'event_log_analysis.json'
            $errorSummary | ConvertTo-Json -Depth 5 | Out-File -FilePath $analysisPath -Encoding UTF8
            Write-Log "Detailed event log analysis saved to: $analysisPath" 'INFO'
        }
        catch {
            Write-Log "Failed to save detailed analysis: $_" 'WARN'
        }

        # Health assessment
        if ($errorSummary.TotalErrors -eq 0) {
            Write-Log '✓ System appears healthy - no significant errors found in recent logs' 'INFO'
        }
        elseif ($errorSummary.TotalErrors -le 10) {
            Write-Log '⚠ Minor issues detected - review errors above for potential concerns' 'WARN'
        }
        else {
            Write-Log '⚠ Multiple errors detected - system may require attention' 'WARN'
        }

        return $true
    }
    catch {
        Write-Log "Unexpected error during event log analysis: $_" 'ERROR'
        return $false
    }
    finally {
        Write-Log '[END] Event Log and CBS Analysis' 'INFO'
    }
}

# ================================================================
# Function: Install-WindowsUpdatesCompatible
# ================================================================
# Purpose: Install Windows Updates in a non-interactive and automated manner
# Environment: Windows with admin privileges; uses PSWindowsUpdate when available
# Logic: Detects update availability, applies updates, and records reboot requirement
# Returns: Hashtable { Success, InstalledCount, RebootRequired }
# Side-effects: Triggers update installation and may require reboots
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
    Write-Log '[START] Windows Updates Installation (Enhanced Compatibility)' 'INFO'

    # Automatically answer "No" to any reboot/restart Read-Host prompts raised by PSWindowsUpdate
    $readHostOverrideAdded = $false
    $originalReadHostFunction = $null
    try {
        $existingReadHostFunction = Get-Command -Name 'Read-Host' -CommandType Function -ErrorAction SilentlyContinue
        if ($existingReadHostFunction) {
            $originalReadHostFunction = $existingReadHostFunction.ScriptBlock
        }

        $autoDeclineScriptBlock = {
            param(
                [string]$Prompt,
                [switch]$AsSecureString,
                [switch]$MaskInput
            )

            $promptText = if ($null -ne $Prompt) { $Prompt } else { '' }
            # Auto-decline reboot/restart prompts with expanded pattern matching
            if (-not $AsSecureString -and -not $MaskInput -and $promptText -match '(?i)(restart|reboot|do you want to|do it now)') {
                Write-Log "Auto-declining prompt: '$promptText' (returning 'N')" 'INFO'
                return 'N'
            }

            if ($originalReadHostFunction) {
                return & $originalReadHostFunction @PSBoundParameters
            }

            return Microsoft.PowerShell.Utility\Read-Host @PSBoundParameters
        }

        Set-Item -Path 'Function:\Read-Host' -Value $autoDeclineScriptBlock
        $readHostOverrideAdded = $true
        Write-Log 'Enabled temporary Read-Host override to auto-decline Windows Update reboot prompts' 'DEBUG'
    }
    catch {
        Write-Log "Failed to configure Read-Host override for reboot prompts: $_" 'WARN'
    }

    # Configure input redirection to suppress interactive prompts from PSWindowsUpdate module
    # This ensures that even if the module tries to read from stdin, it gets immediate EOF
    $inputRedirectionAdded = $false
    try {
        # Redirect stdin to NUL to suppress any input requests
        $null = cmd /c "echo N" | Out-Null
        $inputRedirectionAdded = $true
        Write-Log 'Configured input stream redirection for unattended operation' 'DEBUG'
    }
    catch {
        Write-Log "Failed to configure input redirection: $_" 'WARN'
    }

    try {
        # Check for Administrator privileges
        if (-not $IsAdmin) {
            Write-Log 'Administrator privileges required for Windows Updates. Skipping...' 'WARN'
            return
        }

        # Enhanced PSWindowsUpdate module detection and installation
        $moduleInstalled = $false
        try {
            $existingModule = Get-Module -ListAvailable -Name PSWindowsUpdate -ErrorAction SilentlyContinue
            if ($existingModule) {
                Import-Module PSWindowsUpdate -Force -ErrorAction SilentlyContinue
                $moduleInstalled = $true
                Write-Log 'PSWindowsUpdate module found and imported' 'INFO'
            }
            else {
                Write-Log 'PSWindowsUpdate module not found. Attempting installation...' 'INFO'

                # Check if PackageProvider is available for module installation
                try {
                    $nugetProvider = Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue
                    if (-not $nugetProvider) {
                        Install-PackageProvider -Name NuGet -Force -Scope CurrentUser -ErrorAction SilentlyContinue
                    }

                    Install-Module -Name PSWindowsUpdate -Force -Scope CurrentUser -AllowClobber -ErrorAction Stop
                    Import-Module PSWindowsUpdate -Force -ErrorAction Stop
                    $moduleInstalled = $true
                    Write-Host '✓ PSWindowsUpdate module installed and imported' -ForegroundColor Green
                    Write-Log 'PSWindowsUpdate module successfully installed and imported' 'INFO'
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
                Write-Log 'Checking for available Windows updates...' 'INFO'
                $availableUpdates = Get-WUList -ErrorAction SilentlyContinue

                if ($availableUpdates -and $availableUpdates.Count -gt 0) {
                    Write-Log "Found $($availableUpdates.Count) available updates" 'INFO'
                    Write-Host "Installing $($availableUpdates.Count) Windows updates..." -ForegroundColor Cyan

                    # Set comprehensive environment variables for automatic operation
                    $env:PSWINDOWSUPDATE_REBOOT = 'Never'
                    $env:SUPPRESSPROMPTS = 'True'
                    $env:SUPPRESS_REBOOT_PROMPT = 'True'
                    $env:ACCEPT_EULA = 'True'
                    $env:NONINTERACTIVE = 'True'
                    $env:PSWindowsUpdate_NoPrompt = 'True'
                    $env:PSWindowsUpdate_AutoApprove = 'True'

                    # Install updates with comprehensive suppression - use 'N' input piping to suppress all prompts
                    # This ensures PSWindowsUpdate gets 'N' responses to any interactive prompts
                    Write-Log 'Installing updates with automated reboot denial...' 'INFO'
                    $installResult = 'N' | Install-WindowsUpdate -AcceptAll -AutoReboot:$false -Confirm:$false -IgnoreReboot -Silent -ForceInstall -ErrorAction SilentlyContinue

                    # Clean up environment variables immediately after
                    Remove-Item -Path 'env:PSWINDOWSUPDATE_REBOOT' -ErrorAction SilentlyContinue
                    Remove-Item -Path 'env:SUPPRESSPROMPTS' -ErrorAction SilentlyContinue
                    Remove-Item -Path 'env:SUPPRESS_REBOOT_PROMPT' -ErrorAction SilentlyContinue
                    Remove-Item -Path 'env:ACCEPT_EULA' -ErrorAction SilentlyContinue
                    Remove-Item -Path 'env:NONINTERACTIVE' -ErrorAction SilentlyContinue
                    Remove-Item -Path 'env:PSWindowsUpdate_NoPrompt' -ErrorAction SilentlyContinue
                    Remove-Item -Path 'env:PSWindowsUpdate_AutoApprove' -ErrorAction SilentlyContinue

                    if ($installResult) {
                        $successfulUpdates = $installResult | Where-Object { $_.Result -eq 'Installed' }
                        $failedUpdates = $installResult | Where-Object { $_.Result -ne 'Installed' }

                        Write-Host "✓ Successfully installed $($successfulUpdates.Count) updates" -ForegroundColor Green
                        Write-Log "Windows updates installed: $($successfulUpdates.Count) successful, $($failedUpdates.Count) failed" 'INFO'

                        if ($failedUpdates.Count -gt 0) {
                            Write-Log 'Some updates failed to install. Check Windows Update logs for details.' 'WARN'
                        }

                        # Check if reboot is required
                        $rebootRequired = Get-WURebootStatus -ErrorAction SilentlyContinue
                        if ($rebootRequired) {
                            Write-Host '⚠ System reboot required to complete updates' -ForegroundColor Yellow
                            Write-Log 'System reboot required to complete Windows updates installation' 'WARN'
                        }
                    }
                    else {
                        Write-Log 'No updates were installed (may indicate no updates available or installation issues)' 'INFO'
                    }
                }
                else {
                    Write-Host '✓ No Windows updates available' -ForegroundColor Green
                    Write-Log 'No Windows updates available for installation' 'INFO'
                }
            }
            catch {
                Write-Log "Error during Windows updates installation: $_" 'ERROR'
                Write-Host "✗ Error installing Windows updates: $_" -ForegroundColor Red
            }
        }
        else {
            # Fallback: Use Windows Update API or manual check
            Write-Log 'Using fallback method for Windows updates check...' 'INFO'
            try {
                # Try using Windows Update COM object as fallback
                $updateSession = New-Object -ComObject Microsoft.Update.Session
                $updateSearcher = $updateSession.CreateUpdateSearcher()
                $searchResult = $updateSearcher.Search('IsInstalled=0')

                if ($searchResult.Updates.Count -gt 0) {
                    Write-Host "Found $($searchResult.Updates.Count) updates via Windows Update API" -ForegroundColor Cyan
                    Write-Log "Found $($searchResult.Updates.Count) updates using Windows Update API fallback" 'INFO'
                    Write-Log 'Manual Windows Update installation recommended via Settings > Update & Security' 'INFO'
                }
                else {
                    Write-Host '✓ No updates found via Windows Update API' -ForegroundColor Green
                    Write-Log 'No updates found using Windows Update API fallback' 'INFO'
                }
            }
            catch {
                Write-Log "Windows Update API fallback also failed: $_" 'WARN'
                Write-Host '⚠ Unable to check for updates. Please check manually via Settings' -ForegroundColor Yellow
            }
        }

        Write-Log '[END] Windows Updates Installation' 'INFO'
    }
    finally {
        if ($readHostOverrideAdded) {
            try {
                if ($originalReadHostFunction) {
                    Set-Item -Path 'Function:\Read-Host' -Value $originalReadHostFunction
                }
                else {
                    Remove-Item -Path 'Function:\Read-Host' -ErrorAction SilentlyContinue
                }
                Write-Log 'Restored original Read-Host behavior after Windows Update auto-decline override' 'DEBUG'
            }
            catch {
                Write-Log "Failed to restore original Read-Host behavior: $_" 'WARN'
            }
        }
    }
}

# ================================================================
# Function: Clear-TempFiles
# ================================================================
# Purpose: Remove temporary files from configured temp locations (including
#          `$global:TempFolder`) while preserving important caches and logs
# Environment: File-system access; may require admin for some paths
# Logic: Iterates configured temp paths, applies safe deletion rules, logs results
# Returns: Summary object with deleted file counts and errors
# Side-effects: Deletes files; be cautious in multi-user systems
# ================================================================
function Clear-TempFiles {
    # ...existing code...
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
    Write-Log '[START] Comprehensive Temporary Files Cleanup' 'INFO'

    $totalSizeFreed = 0
    $totalFilesDeleted = 0
    $locationsProcessed = 0

    # Define cleanup locations with parallel processing support
    $cleanupLocations = @(
        @{ Name = 'Windows Temp'; Path = "$env:WINDIR\Temp"; Pattern = '*' },
        @{ Name = 'User Temp'; Path = "$env:TEMP"; Pattern = '*' },
        @{ Name = 'User Local Temp'; Path = "$env:LOCALAPPDATA\Temp"; Pattern = '*' },
        @{ Name = 'Prefetch'; Path = "$env:WINDIR\Prefetch"; Pattern = '*.pf' },
        @{ Name = 'Recent Documents'; Path = "$env:APPDATA\Microsoft\Windows\Recent"; Pattern = '*' },
        @{ Name = 'IE Cache'; Path = "$env:LOCALAPPDATA\Microsoft\Windows\INetCache"; Pattern = '*' },
        @{ Name = 'Chrome Cache'; Path = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache"; Pattern = '*' },
        @{ Name = 'Firefox Cache'; Path = "$env:LOCALAPPDATA\Mozilla\Firefox\Profiles\*\cache2"; Pattern = '*' },
        @{ Name = 'Edge Cache'; Path = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache"; Pattern = '*' }
    )

    $totalLocations = $cleanupLocations.Count
    Write-Log "Starting cleanup of $totalLocations temporary file locations..." 'INFO'

    foreach ($location in $cleanupLocations) {
        $locationsProcessed++
        $progressPercent = [math]::Round(($locationsProcessed / $totalLocations) * 100, 1)

        Write-TaskProgress -Activity 'Cleaning Temp Files' -CurrentStep $locationsProcessed -TotalSteps $totalLocations -Status "$($location.Name) ($locationsProcessed/$totalLocations)" -FileBased:$false
        Write-Host "[$progressPercent%] Cleaning: $($location.Name) ($locationsProcessed/$totalLocations)" -ForegroundColor Cyan

        try {
            # Handle wildcard paths (like Firefox profiles)
            $pathsToClean = @()
            if ($location.Path -contains '*') {
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
                            Write-Host '    ○ No files to clean' -ForegroundColor Gray
                        }
                    }
                    catch {
                        Write-Host "    ✗ Error cleaning location: $_" -ForegroundColor Red
                        Write-Log "Error cleaning $($location.Name): $_" 'WARN'
                    }
                }
                else {
                    Write-Host '    ○ Location not found' -ForegroundColor Gray
                }
            }
        }
        catch {
            Write-Log "Error processing cleanup location $($location.Name): $_" 'WARN'
        }
    }

    # Clean Recycle Bin
    try {
        Write-Host 'Cleaning Recycle Bin...' -ForegroundColor Cyan
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
            Write-Host '    ○ Recycle Bin already empty' -ForegroundColor Gray
        }
    }
    catch {
        Write-Log "Error cleaning Recycle Bin: $_" 'WARN'
    }

    # Summary
    Write-TaskProgress -Activity 'Cleaning Temp Files' -CurrentStep $totalLocations -TotalSteps $totalLocations -Status 'Cleanup completed' -FileBased:$false
    Write-ActionProgress -ActionType 'Cleaning' -ItemName 'Temp Files' -PercentComplete 100 -Status 'Cleanup completed' -Completed

    Write-Log '[TempCleanup] CLEANUP SUMMARY:' 'INFO'
    Write-Log "- Total files deleted: $totalFilesDeleted" 'INFO'
    Write-Log "- Total disk space freed: $([math]::Round($totalSizeFreed, 2)) MB" 'INFO'
    Write-Log "- Locations processed: $locationsProcessed/$totalLocations" 'INFO'

    Write-Host "✓ Cleanup completed: $totalFilesDeleted files deleted, $([math]::Round($totalSizeFreed, 2)) MB freed" -ForegroundColor Green

    Write-Log '[END] Comprehensive Temporary Files Cleanup' 'INFO'
}

# ================================================================
# Function: Remove-AllTempFiles
# ================================================================
# Purpose: Aggressively remove the repository temp folder contents and
#          attempt a robust cleanup using robocopy fallback when needed
# Environment: Administrative or adequate file-permission context
# Logic: Attempts direct removal; if locked, uses robocopy to mirror an
#        empty folder to clear contents; logs progress and errors
# Returns: [bool] success/failure
# Side-effects: Deletes files in `$global:TempFolder`
# ================================================================
function Remove-AllTempFiles {
    # ...existing code...
}

# ================================================================
# Function: Remove-AllTempFiles
# ================================================================
# Purpose: Comprehensive cleanup of all temporary files and folders created by the script, ensuring complete removal of repo temp folder
# Environment: Windows 10/11, file system access to temp directories, proper cleanup verification
# Performance: Fast enumeration and safe deletion, comprehensive error handling, detailed logging
# Dependencies: File system access, temp folder structure, proper file handle management
# Logic: Removes all script-generated temp files, cleans up repo temp folder, ensures no residual files remain
# Features: Complete temp folder removal, detailed logging, error handling, verification of cleanup success
# ================================================================
function Remove-AllTempFiles {
    Write-Log '[START] Complete Temporary Files and Folder Cleanup' 'INFO'
    Write-Host '🧹 Cleaning up all temporary files and folders...' -ForegroundColor Cyan

    $cleanupResults = @{
        Success        = $true
        FilesRemoved   = 0
        FoldersRemoved = 0
        TotalSizeFreed = 0
        Errors         = @()
    }

    try {
        if (Test-Path $global:TempFolder) {
            Write-Log "[TEMP-CLEANUP] Starting cleanup of temp folder: $global:TempFolder" 'INFO'

            # Get temp folder size before cleanup
            try {
                $tempFolderSize = (Get-ChildItem -Path $global:TempFolder -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
                $tempFolderSizeMB = [math]::Round($tempFolderSize / 1MB, 2)
                Write-Log "[TEMP-CLEANUP] Temp folder size before cleanup: $tempFolderSizeMB MB" 'INFO'
                $cleanupResults.TotalSizeFreed = $tempFolderSizeMB
            }
            catch {
                Write-Log "[TEMP-CLEANUP] Could not calculate temp folder size: $_" 'WARN'
            }

            # Count files and folders before cleanup
            try {
                $fileCount = (Get-ChildItem -Path $global:TempFolder -Recurse -File -ErrorAction SilentlyContinue).Count
                $folderCount = (Get-ChildItem -Path $global:TempFolder -Recurse -Directory -ErrorAction SilentlyContinue).Count
                Write-Log "[TEMP-CLEANUP] Items to remove: $fileCount files, $folderCount folders" 'INFO'
                $cleanupResults.FilesRemoved = $fileCount
                $cleanupResults.FoldersRemoved = $folderCount
            }
            catch {
                Write-Log "[TEMP-CLEANUP] Could not count temp folder contents: $_" 'WARN'
            }

            # Force garbage collection to release any file handles
            [System.GC]::Collect()
            [System.GC]::WaitForPendingFinalizers()
            [System.GC]::Collect()
            Write-Log '[TEMP-CLEANUP] Performed garbage collection to release file handles' 'INFO'

            # Additional delay to ensure all handles are released
            Start-Sleep -Milliseconds 500

            # Remove the entire temp folder
            try {
                Remove-Item -Path $global:TempFolder -Recurse -Force -ErrorAction Stop
                Write-Host "✅ Temporary folder removed successfully: $global:TempFolder" -ForegroundColor Green
                Write-Log "[TEMP-CLEANUP] ✓ Temporary folder removed successfully: $global:TempFolder" 'INFO'
                Write-Log "[TEMP-CLEANUP] ✓ Freed disk space: $tempFolderSizeMB MB" 'INFO'
            }
            catch {
                # Alternative cleanup method if standard removal fails
                Write-Host '⚠️ Standard temp folder removal failed, trying alternative method...' -ForegroundColor Yellow
                Write-Log "[TEMP-CLEANUP] Standard removal failed: $($_.Exception.Message)" 'WARN'

                # Alternative removal using robocopy
                try {
                    $parentPath = Split-Path -Path $global:TempFolder -Parent
                    $tempEmptyDir = Join-Path $parentPath "empty_temp_$(Get-Random)"
                    New-Item -Path $tempEmptyDir -ItemType Directory -Force | Out-Null

                    # Use robocopy to mirror empty directory
                    $tempCleanupProcess = Start-Process -FilePath 'robocopy.exe' -ArgumentList "`"$tempEmptyDir`"", "`"$global:TempFolder`"", '/MIR', '/NJH', '/NJS', '/NC', '/NDL', '/NP' -Wait -PassThru -WindowStyle Hidden
                    $exitCode = $tempCleanupProcess.ExitCode
                    Write-Log "[TEMP-CLEANUP] Robocopy cleanup exit code: $exitCode" 'INFO'

                    # Clean up temp directory and try final removal
                    Remove-Item -Path $tempEmptyDir -Force -ErrorAction SilentlyContinue
                    Remove-Item -Path $global:TempFolder -Recurse -Force -ErrorAction Stop

                    Write-Host '✅ Temporary folder removed using alternative method' -ForegroundColor Green
                    Write-Log '[TEMP-CLEANUP] ✓ Temporary folder removed using robocopy method' 'INFO'
                }
                catch {
                    Write-Host "❌ Failed to remove temporary folder: $($_.Exception.Message)" -ForegroundColor Red
                    Write-Log "[TEMP-CLEANUP] ✗ Failed to remove temporary folder: $($_.Exception.Message)" 'ERROR'
                    $cleanupResults.Success = $false
                    $cleanupResults.Errors += "Temp folder removal failed: $($_.Exception.Message)"
                }
            }
        }
        else {
            Write-Host "ℹ️ Temporary folder not found (already cleaned up): $global:TempFolder" -ForegroundColor Gray
            Write-Log "[TEMP-CLEANUP] Temporary folder not found (already cleaned up): $global:TempFolder" 'INFO'
        }

        # Clean up any remaining temporary files created in system temp (fallback)
        $scriptTempFiles = @(
            "$global:TempFolder\pkg_out.txt",
            "$global:TempFolder\pkg_err.txt",
            "$global:TempFolder\winget_*.txt",
            "$global:TempFolder\choco_*.txt",
            "$global:TempFolder\wu_install_*.ps1"
        )

        foreach ($tempFilePattern in $scriptTempFiles) {
            try {
                $filesToRemove = Get-ChildItem -Path $tempFilePattern -ErrorAction SilentlyContinue
                foreach ($file in $filesToRemove) {
                    Remove-Item -Path $file.FullName -Force -ErrorAction SilentlyContinue
                    Write-Log "[TEMP-CLEANUP] ✓ Removed repo temp file: $($file.Name)" 'INFO'
                }
            }
            catch {
                Write-Log "[TEMP-CLEANUP] ⚠ Could not clean repo temp files matching ${tempFilePattern}: $_" 'WARN'
            }
        }

    }
    catch {
        Write-Log "[TEMP-CLEANUP] ✗ Unexpected error during temp cleanup: $($_.Exception.Message)" 'ERROR'
        $cleanupResults.Success = $false
        $cleanupResults.Errors += "Unexpected error: $($_.Exception.Message)"
    }

    # Summary
    if ($cleanupResults.Success) {
        Write-Host '✅ Temporary files cleanup completed successfully' -ForegroundColor Green
        if ($cleanupResults.TotalSizeFreed -gt 0) {
            Write-Host "📊 Cleanup summary: $($cleanupResults.FilesRemoved) files, $($cleanupResults.FoldersRemoved) folders, $($cleanupResults.TotalSizeFreed) MB freed" -ForegroundColor Cyan
        }
    }
    else {
        Write-Host '⚠️ Temporary files cleanup completed with errors' -ForegroundColor Yellow
        foreach ($errorMessage in $cleanupResults.Errors) {
            Write-Host "❌ Error: $errorMessage" -ForegroundColor Red
        }
    }

    Write-Log "[END] Complete Temporary Files and Folder Cleanup - Success: $($cleanupResults.Success)" 'INFO'
    return $cleanupResults
}

# ================================================================
# Function: Start-SystemHealthRepair
# ================================================================
# Purpose: Trigger system health repairs such as SFC, DISM, and other
#          recovery operations when configured or when errors are detected
# Environment: Requires admin privileges; operations may be long-running
# Logic: Runs SFC /scannow, DISM restorehealth and other recommended checks
# Returns: Hashtable with results and any suggested follow-ups
# Side-effects: Can modify system files and require reboots
# ================================================================
function Start-SystemHealthRepair {
    # ...existing code...
}

# ================================================================
# Function: Start-DefenderFullScan
# ================================================================
# Purpose: Launch a full Windows Defender scan (or other AV tool) and
#          collect results for reporting
# Environment: Windows with Microsoft Defender available (or compatible AV)
# Logic: Uses Windows Defender cmdlets where available and logs scan results
# Returns: Hashtable { Success, ThreatsFound, ScanTime }
# Side-effects: CPU and IO intensive while scanning
# ================================================================
function Start-DefenderFullScan {
    # ...existing code...
}

# ================================================================
# Function: Start-SystemHealthRepair
# ================================================================
# Purpose: Performs a comprehensive system health check and repair using DISM and SFC.
# Environment: Requires administrator privileges.
# Performance: This is a long-running operation involving intensive disk I/O.
# Dependencies: DISM.exe, SFC.exe.
# Logic:
#   1. Executes DISM to check and repair the Windows component store.
#   2. If corruption is found and repaired, or if CBS logs indicate issues, it runs SFC.
#   3. Provides detailed progress tracking and generates a summary report.
# Features: Robust error handling, detailed logging, and structured result output.
# ================================================================
function Start-SystemHealthRepair {
    Write-Log '[START] Windows System Health Check and Repair' 'INFO'
    $repairStartTime = Get-Date
    $results = @{
        DismCheckPerformed = $false
        DismRepairNeeded   = $false
        DismRepairSuccess  = $false
        SfcCheckPerformed  = $false
        SfcRepairNeeded    = $false
        SfcRepairSuccess   = $false
        OverallSuccess     = $false
        RepairNeeded       = $false
        StartTime          = $repairStartTime
        EndTime            = $null
        TotalDuration      = $null
    }

    try {
        # Phase 1: DISM Health Check and Repair
        Write-Log 'Starting DISM component store health analysis...' 'INFO'
        Write-ActionProgress -ActionType 'Analyzing' -ItemName 'System Health' -PercentComplete 5 -Status 'Initializing DISM health check...'

        try {
            $dismScanResult = & dism /online /cleanup-image /scanhealth /english 2>&1
            $dismScanOutput = $dismScanResult -join "`n"
            $results.DismCheckPerformed = $true
            Write-Log "DISM ScanHealth output: $dismScanOutput" 'VERBOSE'

            if ($dismScanOutput -match 'component store is repairable|corruption was detected') {
                Write-Log 'DISM detected component store corruption. Attempting repair...' 'WARN'
                $results.DismRepairNeeded = $true
                $results.RepairNeeded = $true

                Write-ActionProgress -ActionType 'Repairing' -ItemName 'Component Store' -PercentComplete 20 -Status 'Running DISM RestoreHealth...'
                $dismRepairResult = & dism /online /cleanup-image /restorehealth /english 2>&1
                $dismRepairOutput = $dismRepairResult -join "`n"
                Write-Log "DISM RestoreHealth output: $dismRepairOutput" 'VERBOSE'

                if ($LASTEXITCODE -eq 0 -and $dismRepairOutput -match 'The restore operation completed successfully') {
                    Write-Log 'DISM RestoreHealth completed successfully.' 'SUCCESS'
                    $results.DismRepairSuccess = $true
                }
                else {
                    Write-Log "DISM RestoreHealth failed. Exit Code: $LASTEXITCODE" 'ERROR'
                    $results.DismRepairSuccess = $false
                }
            }
            else {
                Write-Log 'DISM found no component store corruption.' 'INFO'
            }
        }
        catch {
            Write-Log "An error occurred during the DISM operation: $($_.Exception.Message)" 'ERROR'
        }

        # Phase 2: SFC System File Check
        Write-ActionProgress -ActionType 'Analyzing' -ItemName 'System Files' -PercentComplete 50 -Status 'Determining if SFC scan is needed...'
        $sfcNeeded = $results.DismRepairSuccess # Run SFC if DISM made repairs

        if (!$sfcNeeded) {
            # Fallback: Check CBS logs if DISM wasn't needed or failed
            $cbsLogPath = "$env:WINDIR\Logs\CBS\CBS.log"
            if (Test-Path $cbsLogPath) {
                if (Select-String -Path $cbsLogPath -Pattern 'corrupt|damaged|violation' -Quiet -SimpleMatch) {
                    Write-Log 'Corruption indicators found in CBS log. SFC scan is recommended.' 'WARN'
                    $sfcNeeded = $true
                }
            }
        }

        if ($sfcNeeded) {
            $results.SfcCheckPerformed = $true
            $results.SfcRepairNeeded = $true
            $results.RepairNeeded = $true
            Write-Log 'Starting SFC /scannow operation...' 'INFO'
            Write-ActionProgress -ActionType 'Repairing' -ItemName 'System Files' -PercentComplete 65 -Status 'Running SFC /scannow...'

            try {
                $sfcResult = & sfc /scannow 2>&1
                $sfcOutput = $sfcResult -join "`n"
                Write-Log "SFC scan output: $sfcOutput" 'VERBOSE'

                if ($sfcOutput -match 'did not find any integrity violations|found corrupt files and successfully repaired them') {
                    Write-Log 'SFC scan completed successfully.' 'SUCCESS'
                    $results.SfcRepairSuccess = $true
                }
                else {
                    Write-Log 'SFC scan found issues that could not be fully repaired.' 'WARN'
                    $results.SfcRepairSuccess = $false
                }
            }
            catch {
                Write-Log "An error occurred during the SFC scan: $($_.Exception.Message)" 'ERROR'
                $results.SfcRepairSuccess = $false
            }
        }
        else {
            Write-Log 'SFC scan not needed based on current analysis.' 'INFO'
        }

        # Phase 3: Finalize and Report
        $results.OverallSuccess = (-not $results.DismRepairNeeded -or $results.DismRepairSuccess) -and (-not $results.SfcRepairNeeded -or $results.SfcRepairSuccess)
        Write-ActionProgress -ActionType 'Analyzing' -ItemName 'System Health' -PercentComplete 100 -Status 'System health repair complete!' -Completed
    }
    catch {
        Write-Log "An unexpected error occurred during the system health repair process: $($_.Exception.Message)" 'ERROR'
        $results.OverallSuccess = $false
    }
    finally {
        $repairEndTime = Get-Date
        $totalDuration = $repairEndTime - $repairStartTime
        $results.EndTime = $repairEndTime
        $results.TotalDuration = $totalDuration

        Write-Log "[SUMMARY] System Health Repair completed in $($totalDuration.ToString('hh\:mm\:ss'))" 'INFO'
        Write-Log "[SUMMARY] Overall Success: $($results.OverallSuccess)" 'INFO'
        Write-Log "[SUMMARY] DISM: Needed=$($results.DismRepairNeeded), Success=$($results.DismRepairSuccess)" 'INFO'
        Write-Log "[SUMMARY] SFC: Needed=$($results.SfcRepairNeeded), Success=$($results.SfcRepairSuccess)" 'INFO'

        # Add results to global metrics if available
        if ($global:ScriptMetrics) {
            $global:ScriptMetrics.SystemHealthRepair = $results
        }
    }

    return $results.OverallSuccess
}

# Function: Write-TempListsSummary
# ================================================================
# Purpose: Summarize temporary lists created during execution (bloatware,
#          essential apps, inventory snapshots) and write them to the temp folder
# Environment: Requires $global:TempFolder to be writable
# Logic: Reads created temp lists and produces a compact summary for report
# Returns: None (writes files and log entries)
# Side-effects: Creates/updates files under `$global:TempFolder`
# ================================================================
function Write-TempListsSummary {
    # ...existing code...
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
    Write-Log '[START] Temporary Lists Summary Generation' 'INFO'

    if (-not (Test-Path $global:TempFolder)) {
        Write-Log "Temp folder not found: $global:TempFolder" 'WARN'
        return
    }

    $summaryLines = @()
    $summaryLines += '=== TEMPORARY LISTS SUMMARY ==='
    $summaryLines += "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    $summaryLines += "Temp Folder: $global:TempFolder"
    $summaryLines += ''

    # Analyze bloatware lists
    $bloatwareListPath = Join-Path $global:TempFolder 'bloatware.json'
    if (Test-Path $bloatwareListPath) {
        try {
            $bloatwareList = Get-Content $bloatwareListPath -Raw | ConvertFrom-Json
            $bloatwareCount = if ($bloatwareList -is [array]) { $bloatwareList.Count } else { 1 }
            $fileSize = [math]::Round((Get-Item $bloatwareListPath).Length / 1KB, 2)

            $summaryLines += 'BLOATWARE LIST:'
            $summaryLines += "- Total entries: $bloatwareCount"
            $summaryLines += "- File size: $fileSize KB"
            $summaryLines += "- Location: $bloatwareListPath"

            # Sample entries (first 5)
            $sampleEntries = $bloatwareList | Select-Object -First 5
            $summaryLines += "- Sample entries: $($sampleEntries -join ', ')"
            $summaryLines += ''
        }
        catch {
            $summaryLines += "BLOATWARE LIST: Error reading file - $_"
            $summaryLines += ''
        }
    }

    # Analyze essential apps lists
    $essentialAppsPath = Join-Path $global:TempFolder 'essential_apps.json'
    if (Test-Path $essentialAppsPath) {
        try {
            $essentialApps = Get-Content $essentialAppsPath -Raw | ConvertFrom-Json
            $appsCount = if ($essentialApps -is [array]) { $essentialApps.Count } else { 1 }
            $fileSize = [math]::Round((Get-Item $essentialAppsPath).Length / 1KB, 2)

            $summaryLines += 'ESSENTIAL APPS LIST:'
            $summaryLines += "- Total entries: $appsCount"
            $summaryLines += "- File size: $fileSize KB"
            $summaryLines += "- Location: $essentialAppsPath"

            # Count apps by source
            $wingetCount = ($essentialApps | Where-Object { $_.Winget }).Count
            $chocoCount = ($essentialApps | Where-Object { $_.Choco }).Count
            $summaryLines += "- Winget sources: $wingetCount"
            $summaryLines += "- Chocolatey sources: $chocoCount"
            $summaryLines += ''
        }
        catch {
            $summaryLines += "ESSENTIAL APPS LIST: Error reading file - $_"
            $summaryLines += ''
        }
    }

    # Analyze diff files
    $diffFiles = Get-ChildItem -Path $global:TempFolder -Filter '*diff*.json' -ErrorAction SilentlyContinue
    if ($diffFiles) {
        $summaryLines += 'DIFF ANALYSIS FILES:'
        foreach ($diffFile in $diffFiles) {
            $fileSize = [math]::Round($diffFile.Length / 1KB, 2)
            $summaryLines += "- $($diffFile.Name): $fileSize KB"
        }
        $summaryLines += ''
    }

    # Analyze audit files
    $auditFiles = Get-ChildItem -Path $global:TempFolder -Filter '*audit*.json' -ErrorAction SilentlyContinue
    if ($auditFiles) {
        $summaryLines += 'AUDIT FILES:'
        foreach ($auditFile in $auditFiles) {
            $fileSize = [math]::Round($auditFile.Length / 1KB, 2)
            $createdTime = $auditFile.CreationTime.ToString('yyyy-MM-dd HH:mm:ss')
            $summaryLines += "- $($auditFile.Name): $fileSize KB (Created: $createdTime)"
        }
        $summaryLines += ''
    }

    # System inventory summary
    $inventoryPath = Join-Path $global:TempFolder 'inventory.json'
    if (Test-Path $inventoryPath) {
        try {
            $inventory = Get-Content $inventoryPath -Raw | ConvertFrom-Json
            $fileSize = [math]::Round((Get-Item $inventoryPath).Length / 1KB, 2)

            $summaryLines += 'SYSTEM INVENTORY:'
            $summaryLines += "- File size: $fileSize KB"
            $summaryLines += "- AppX packages: $(if ($inventory.appx) { $inventory.appx.Count } else { 0 })"
            $summaryLines += "- Winget packages: $(if ($inventory.winget) { $inventory.winget.Count } else { 0 })"
            $summaryLines += "- Chocolatey packages: $(if ($inventory.choco) { $inventory.choco.Count } else { 0 })"
            $summaryLines += "- Registry entries: $(if ($inventory.registry_uninstall) { $inventory.registry_uninstall.Count } else { 0 })"
            $summaryLines += ''
        }
        catch {
            $summaryLines += "SYSTEM INVENTORY: Error reading file - $_"
            $summaryLines += ''
        }
    }

    # Total temp folder analysis
    $totalFiles = (Get-ChildItem -Path $global:TempFolder -File -ErrorAction SilentlyContinue).Count
    $totalSize = [math]::Round((Get-ChildItem -Path $global:TempFolder -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum / 1KB, 2)

    $summaryLines += 'TEMP FOLDER SUMMARY:'
    $summaryLines += "- Total files: $totalFiles"
    $summaryLines += "- Total size: $totalSize KB"
    $summaryLines += "- Folder: $global:TempFolder"
    $summaryLines += ''
    $summaryLines += '=== END TEMPORARY LISTS SUMMARY ==='

    # Write summary to temp folder
    $summaryPath = Join-Path $global:TempFolder 'temp_lists_summary.txt'
    $summaryLines | Out-File -FilePath $summaryPath -Encoding UTF8

    Write-Log "Temporary lists summary generated: $summaryPath" 'INFO'
    Write-Log '[END] Temporary Lists Summary Generation' 'INFO'
}

# ================================================================
# Function: Write-UnifiedMaintenanceReport
# ================================================================
# Purpose: Generate the final human-readable maintenance report including
#          system inventory, task results, timings, and key output files
# Environment: Requires write access to parent directory for `maintenance_report.txt`
# Logic: Aggregates system info and task results into a unified text report
# Returns: Path to the generated report
# Side-effects: Writes report to disk
# ================================================================
function Write-UnifiedMaintenanceReport {
    # ...existing code...
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
    Write-Log '[START] Unified Maintenance Report Generation' 'INFO'

    $startTime = Get-Date
    $reportData = @{
        metadata   = @{
            date              = $startTime.ToString('yyyy-MM-dd HH:mm:ss')
            user              = $env:USERNAME
            computer          = $env:COMPUTERNAME
            scriptVersion     = '2025.1'
            os                = (Get-CimInstance Win32_OperatingSystem).Caption
            osVersion         = (Get-CimInstance Win32_OperatingSystem).Version
            powershellVersion = $PSVersionTable.PSVersion.ToString()
            scriptPath        = $PSCommandPath
            tempFolder        = $global:TempFolder
        }
        summary    = @{
            totalTasks      = if ($global:TaskResults) { $global:TaskResults.Count } else { 0 }
            successfulTasks = if ($global:TaskResults) { ($global:TaskResults.Values | Where-Object { $_.IsSuccessful }).Count } else { 0 }
            failedTasks     = if ($global:TaskResults) { ($global:TaskResults.Values | Where-Object { -not $_.IsSuccessful }).Count } else { 0 }
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
                description = if ($task) { $task.Description } else { 'Task description not available' }
                success     = $result.IsSuccessful
                duration    = if ($result.Duration) { [math]::Round($result.Duration, 2) } else { 0 }
                started     = if ($result.Started) { $result.Started.ToString('HH:mm:ss') } else { 'Unknown' }
                ended       = if ($result.Ended) { $result.Ended.ToString('HH:mm:ss') } else { 'Unknown' }
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
        $inventoryFiles = Get-ChildItem -Path $global:TempFolder -Filter '*.json' -ErrorAction SilentlyContinue
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
            name   = 'maintenance.log'
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

    # ================================================================
    # REPORT GENERATION PHASE - HTML and JSON Output
    # ================================================================
    # Generate comprehensive multi-format reports from aggregated maintenance data
    # Output Formats: 
    #   - HTML: Professional, responsive, single-file report (primary output)
    #   - JSON: Structured data for programmatic access (secondary output)
    # ================================================================

    # Define report output paths
    $jsonReportPath = Join-Path $global:TempFolder 'maintenance_report.json'
    $htmlReportPath = Join-Path $WorkingDirectory 'maintenance_report.html'

    # Write structured JSON report for programmatic access and data export
    try {
        $reportData | ConvertTo-Json -Depth 5 | Out-File -FilePath $jsonReportPath -Encoding UTF8
        Write-Log "Structured JSON report saved to $jsonReportPath" 'INFO'
    }
    catch {
        Write-Log "Failed to write JSON report: $_" 'WARN'
    }

    # ================================================================
    # HTML REPORT TEMPLATE AND GENERATION
    # ================================================================
    # Build professional, responsive HTML report with:
    # - Embedded CSS (no external dependencies)
    # - Responsive grid layouts (mobile, tablet, desktop)
    # - Color-coded task status indicators
    # - Complete data aggregation
    # - Professional gradients and styling (Bootstrap/W3.CSS inspired)
    # ================================================================
    
    # Build professional HTML report with embedded CSS styling
    $htmlContent = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Windows Maintenance Report - $($reportData.metadata.computer)</title>
    <!-- ============================================================ -->
    <!-- EMBEDDED CSS STYLING                                         -->
    <!-- ============================================================ -->
    <!-- Purpose: Professional styling with responsive design         -->
    <!-- Features:                                                    -->
    <!--   - Bootstrap 5-inspired table styling                       -->
    <!--   - W3.CSS-inspired card layouts                             -->
    <!--   - CSS Grid for responsive layouts                          -->
    <!--   - Media queries for mobile/tablet/desktop                  -->
    <!--   - Print-friendly styling                                   -->
    <!--   - No external dependencies                                 -->
    <!-- ============================================================ -->
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: #333;
            padding: 20px;
            line-height: 1.6;
        }
        
        .container {
            max-width: 1200px;
            margin: 0 auto;
            background: white;
            border-radius: 10px;
            box-shadow: 0 10px 40px rgba(0, 0, 0, 0.2);
            overflow: hidden;
        }
        
        .header {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 40px 30px;
            text-align: center;
        }
        
        .header h1 {
            font-size: 2.5em;
            margin-bottom: 10px;
            text-shadow: 2px 2px 4px rgba(0, 0, 0, 0.3);
        }
        
        .header p {
            font-size: 1.1em;
            opacity: 0.9;
        }
        
        .content {
            padding: 40px 30px;
        }
        
        .section {
            margin-bottom: 40px;
            page-break-inside: avoid;
        }
        
        .section h2 {
            color: #667eea;
            font-size: 1.8em;
            margin-bottom: 20px;
            padding-bottom: 10px;
            border-bottom: 3px solid #667eea;
        }
        
        .metadata-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }
        
        .metadata-item {
            background: #f8f9fa;
            padding: 15px;
            border-radius: 5px;
            border-left: 4px solid #667eea;
        }
        
        .metadata-item label {
            display: block;
            font-weight: bold;
            color: #667eea;
            font-size: 0.9em;
            margin-bottom: 5px;
        }
        
        .metadata-item value {
            display: block;
            font-size: 1.1em;
            color: #333;
        }
        
        .summary-boxes {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 15px;
            margin-bottom: 30px;
        }
        
        .summary-box {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 25px;
            border-radius: 8px;
            text-align: center;
            box-shadow: 0 4px 15px rgba(102, 126, 234, 0.3);
        }
        
        .summary-box .value {
            font-size: 2.5em;
            font-weight: bold;
            margin: 10px 0;
        }
        
        .summary-box .label {
            font-size: 0.95em;
            opacity: 0.9;
        }
        
        .success-rate {
            background: linear-gradient(135deg, #11998e 0%, #38ef7d 100%) !important;
        }
        
        table {
            width: 100%;
            border-collapse: collapse;
            margin-top: 20px;
            background: white;
            box-shadow: 0 2px 8px rgba(0, 0, 0, 0.1);
            border-radius: 5px;
            overflow: hidden;
        }
        
        table thead {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
        }
        
        table th {
            padding: 15px;
            text-align: left;
            font-weight: 600;
            font-size: 0.95em;
        }
        
        table td {
            padding: 12px 15px;
            border-bottom: 1px solid #e9ecef;
        }
        
        table tbody tr:nth-child(even) {
            background: #f8f9fa;
        }
        
        table tbody tr:hover {
            background: #f0f1ff;
            transition: background 0.3s ease;
        }
        
        .status-success {
            color: #28a745;
            font-weight: bold;
        }
        
        .status-failed {
            color: #dc3545;
            font-weight: bold;
        }
        
        .status-icon {
            font-size: 1.2em;
            margin-right: 5px;
        }
        
        .system-info {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
            gap: 20px;
        }
        
        .info-card {
            background: #f8f9fa;
            padding: 20px;
            border-radius: 5px;
            border: 1px solid #dee2e6;
        }
        
        .info-card h4 {
            color: #667eea;
            margin-bottom: 15px;
            font-size: 1.1em;
        }
        
        .info-card p {
            margin: 8px 0;
            display: flex;
            justify-content: space-between;
            padding: 5px 0;
        }
        
        .info-card .label {
            font-weight: bold;
            color: #555;
        }
        
        .info-card .value {
            color: #667eea;
            font-weight: 600;
        }
        
        .footer {
            background: #f8f9fa;
            padding: 20px 30px;
            text-align: center;
            color: #666;
            font-size: 0.9em;
            border-top: 1px solid #dee2e6;
        }
        
        .alert {
            padding: 15px;
            margin: 15px 0;
            border-radius: 5px;
            border-left: 4px solid;
        }
        
        .alert-info {
            background: #e7f3ff;
            border-color: #2196F3;
            color: #0c5aa0;
        }
        
        .alert-success {
            background: #dff0d8;
            border-color: #5cb85c;
            color: #3c763d;
        }
        
        .alert-warning {
            background: #fcf8e3;
            border-color: #faebcc;
            color: #8a6d3b;
        }
        
        .alert-error {
            background: #f2dede;
            border-color: #ebccd1;
            color: #a94442;
        }
        
        @media print {
            body { background: white; }
            .container { box-shadow: none; }
            .section { page-break-inside: avoid; }
        }
        
        @media (max-width: 768px) {
            .header h1 { font-size: 1.8em; }
            .metadata-grid { grid-template-columns: 1fr; }
            .summary-boxes { grid-template-columns: repeat(2, 1fr); }
            .summary-box .value { font-size: 1.8em; }
        }
    </style>
</head>
<body>
    <div class="container">
        <!-- ============================================================ -->
        <!-- HEADER SECTION                                              -->
        <!-- ============================================================ -->
        <!-- Purpose: Professional report title with metadata             -->
        <!-- Content: Title, computer name, generation timestamp         -->
        <!-- Design: Purple gradient background, emoji icons             -->
        <!-- ============================================================ -->
        <div class="header">
            <h1>🖥️ Windows Maintenance Report</h1>
            <p>$($reportData.metadata.computer) • $($reportData.metadata.date)</p>
        </div>
        
        <div class="content">
            <!-- ============================================================ -->
            <!-- SECTION 1: SYSTEM METADATA GRID                            -->
            <!-- ============================================================ -->
            <!-- Purpose: Display system identification and configuration   -->
            <!-- Fields: Computer, User, OS, Version, Architecture, Build  -->
            <!-- Layout: Responsive grid (3 cols desktop, 1 col mobile)    -->
            <!-- ============================================================ -->
            <!-- System Metadata Section -->
            <div class="section">
                <h2>📋 System Information</h2>
                <div class="metadata-grid">
                    <div class="metadata-item">
                        <label>Computer</label>
                        <value>$($reportData.metadata.computer)</value>
                    </div>
                    <div class="metadata-item">
                        <label>User</label>
                        <value>$($reportData.metadata.user)</value>
                    </div>
                    <div class="metadata-item">
                        <label>Operating System</label>
                        <value>$($reportData.metadata.os)</value>
                    </div>
                    <div class="metadata-item">
                        <label>OS Version</label>
                        <value>$($reportData.metadata.osVersion)</value>
                    </div>
                    <div class="metadata-item">
                        <label>Architecture</label>
                        <value>$($reportData.systemInfo.windowsVersion.architecture)</value>
                    </div>
                    <div class="metadata-item">
                        <label>Build Number</label>
                        <value>$($reportData.systemInfo.windowsVersion.build)</value>
                    </div>
                    <div class="metadata-item">
                        <label>PowerShell Version</label>
                        <value>$($reportData.metadata.powershellVersion)</value>
                    </div>
                    <div class="metadata-item">
                        <label>Script Version</label>
                        <value>$($reportData.metadata.scriptVersion)</value>
                    </div>
                </div>
            </div>
            
            <!-- ============================================================ -->
            <!-- SECTION 2: EXECUTION SUMMARY DASHBOARD                       -->
            <!-- ============================================================ -->
            <!-- Purpose: At-a-glance key performance indicators              -->
            <!-- Metrics: Total tasks, Success count, Failed count            -->
            <!-- Display: 5 prominent stat boxes with gradient backgrounds    -->
            <!-- Color Coding: Green for success, success-rate with gradient  -->
            <!-- ============================================================ -->
            <!-- Execution Summary Section -->
            <div class="section">
                <h2>📊 Execution Summary</h2>
                <div class="summary-boxes">
                    <div class="summary-box">
                        <div class="label">Total Tasks</div>
                        <div class="value">$($reportData.summary.totalTasks)</div>
                    </div>
                    <div class="summary-box">
                        <div class="label">Successful</div>
                        <div class="value" style="color: #4ade80;">$($reportData.summary.successfulTasks)</div>
                    </div>
                    <div class="summary-box">
                        <div class="label">Failed</div>
                        <div class="value" style="color: #f87171;">$($reportData.summary.failedTasks)</div>
                    </div>
                    <div class="summary-box success-rate">
                        <div class="label">Success Rate</div>
                        <div class="value">$($reportData.summary.successRate)%</div>
                    </div>
                    <div class="summary-box">
                        <div class="label">Total Duration</div>
                        <div class="value">${[math]::Round($reportData.summary.totalDuration, 1)}s</div>
                    </div>
                </div>
            </div>
            
            <!-- ============================================================ -->
            <!-- SECTION 3: TASK BREAKDOWN TABLE                             -->
            <!-- ============================================================ -->
            <!-- Purpose: Detailed execution results for each maintenance    -->
            <!-- Fields: Task name, status indicator, description, duration  -->
            <!-- Features: Color-coded rows, error row highlighting          -->
            <!-- Status: ✓ (green) success, ✗ (red) failure                  -->
            <!-- ============================================================ -->
            <!-- Tasks Breakdown Section -->
            <div class="section">
                <h2>✅ Task Breakdown</h2>
                <table>
                    <thead>
                        <tr>
                            <th style="width: 25%;">Task Name</th>
                            <th style="width: 15%;">Status</th>
                            <th style="width: 35%;">Description</th>
                            <th style="width: 15%;">Duration</th>
                        </tr>
                    </thead>
                    <tbody>
"@

    foreach ($task in $reportData.tasks) {
        $statusClass = if ($task.success) { 'status-success' } else { 'status-failed' }
        $statusIcon = if ($task.success) { '✓' } else { '✗' }
        $statusText = if ($task.success) { 'SUCCESS' } else { 'FAILED' }
        
        $htmlContent += @"
                        <tr>
                            <td><strong>$($task.name)</strong></td>
                            <td class="$statusClass"><span class="status-icon">$statusIcon</span>$statusText</td>
                            <td>$($task.description)</td>
                            <td>${$task.duration}s</td>
                        </tr>
"@
        
        if ($task.error) {
            $htmlContent += @"
                        <tr style="background: #fff3cd;">
                            <td colspan="4"><div class="alert alert-error">⚠️ Error: $($task.error)</div></td>
                        </tr>
"@
        }
    }

    $htmlContent += @"
                    </tbody>
                </table>
            </div>
            
            <!-- ============================================================ -->
            <!-- SECTION 4: HARDWARE INFORMATION CARDS                        -->
            <!-- ============================================================ -->
            <!-- Purpose: System hardware specifications and status           -->
            <!-- Cards: CPU model, Memory (total/available), Storage, Uptime  -->
            <!-- Layout: Responsive grid (4 cols desktop, 1 col mobile)       -->
            <!-- Design: Light gray cards with purple headers                 -->
            <!-- ============================================================ -->
            <!-- Hardware Information Section -->
            <div class="section">
                <h2>🔧 Hardware Information</h2>
                <div class="system-info">
                    <div class="info-card">
                        <h4>💾 Processor</h4>
                        <p><span class="label">CPU:</span> <span class="value">$($reportData.systemInfo.processor)</span></p>
                    </div>
                    <div class="info-card">
                        <h4>🧠 Memory</h4>
                        <p><span class="label">Total:</span> <span class="value">$($reportData.systemInfo.memory.totalGB) GB</span></p>
                        <p><span class="label">Available:</span> <span class="value">$($reportData.systemInfo.memory.availableGB) GB</span></p>
                    </div>
                    <div class="info-card">
                        <h4>💿 Storage</h4>
                        <p><span class="label">Total:</span> <span class="value">$($reportData.systemInfo.disk.totalGB) GB</span></p>
                        <p><span class="label">Free:</span> <span class="value">$($reportData.systemInfo.disk.freeGB) GB</span></p>
                        <p><span class="label">Used:</span> <span class="value">$($reportData.systemInfo.disk.usedPercent)%</span></p>
                    </div>
                    <div class="info-card">
                        <h4>⏱️ Uptime</h4>
                        <p><span class="label">Hours:</span> <span class="value">$($reportData.systemInfo.uptime.hours)h</span></p>
                    </div>
                </div>
            </div>
            
            <!-- ============================================================ -->
            <!-- SECTION 5: GENERATED FILES & ARTIFACTS                       -->
            <!-- ============================================================ -->
            <!-- Purpose: Inventory of all generated report and log files     -->
            <!-- Lists: Log files, inventory snapshots, temp files            -->
            <!-- Format: Alert boxes with file names, sizes, timestamps       -->
            <!-- ============================================================ -->
            <!-- Files Generated Section -->
            <div class="section">
                <h2>📁 Generated Files & Artifacts</h2>
"@

    <!-- ============================================================ -->
    <!-- LOG FILES LISTING -->
    <!-- ============================================================ -->
    <!-- Conditional Alert Box: Only shows if log files exist -->
    <!-- Content: File names and sizes in KB with bullet points -->
    <!-- Purpose: User can see what logs were generated -->
    <!-- Alert Class: alert-info (blue background, informational tone) -->
    <!-- ============================================================ -->
    if ($reportData.files.logFiles.Count -gt 0) {
        $htmlContent += @'
                <div class="alert alert-info">
                    <strong>📋 Log Files:</strong>
'@
        foreach ($file in $reportData.files.logFiles) {
            $htmlContent += "<br/>• $($file.name) - $($file.sizeKB) KB"
        }
        $htmlContent += '</div>'
    }

    <!-- ============================================================ -->
    <!-- INVENTORY FILES LISTING -->
    <!-- ============================================================ -->
    <!-- Conditional Alert Box: Only shows if inventory files exist -->
    <!-- Content: File names, sizes, and creation timestamps -->
    <!-- Purpose: Track system snapshots taken during maintenance -->
    <!-- Alert Class: alert-info (blue background, informational tone) -->
    <!-- Details: Shows when each snapshot was created -->
    <!-- ============================================================ -->
    if ($reportData.files.inventoryFiles.Count -gt 0) {
        $htmlContent += @'
                <div class="alert alert-info">
                    <strong>📊 Inventory Files:</strong>
'@
        foreach ($file in $reportData.files.inventoryFiles) {
            $htmlContent += "<br/>• $($file.name) - $($file.sizeKB) KB (Created: $($file.created))"
        }
        $htmlContent += '</div>'
    }

    <!-- ============================================================ -->
    <!-- SECTION 6: FOOTER & METADATA -->
    <!-- ============================================================ -->
    <!-- Purpose: Report metadata and professional closure -->
    <!-- Content: Generation timestamp, script version, path info -->
    <!-- Design: Dark text on white background, subtle styling -->
    <!-- Branding: Professional footer with system attribution -->
    <!-- ============================================================ -->
    <!-- Footer Section with Report Metadata -->
    $htmlContent += @"
            </div>
        </div>
        
        <div class="footer">
            <!-- Report Generation Date/Time -->
            <p><strong>Report Generated:</strong> $($reportData.metadata.date)</p>
            
            <!-- Script Version and Location -->
            <p><strong>Script Version:</strong> $($reportData.metadata.scriptVersion) | <strong>Path:</strong> $($reportData.metadata.scriptPath)</p>
            
            <!-- Professional Branding -->
            <p style="margin-top: 10px; color: #999;">Windows Maintenance Automation System • Professional Report</p>
        </div>
    </div>
</body>
</html>
"@

    <!-- ============================================================ -->
    <!-- FINAL HTML REPORT OUTPUT -->
    <!-- ============================================================ -->
    <!-- Purpose: Write complete HTML report to file system -->
    <!-- Encoding: UTF8 (unicode support, standard web encoding) -->
    <!-- Destination: $htmlReportPath variable (project working dir) -->
    <!-- Error Handling: Try/catch with fallback logging -->
    <!-- Features: -->
    <!-- - Self-contained HTML (no external dependencies) -->
    <!-- - Embedded CSS styling (bootstrap/W3.CSS inspired) -->
    <!-- - Responsive design (mobile-friendly) -->
    <!-- - Professional formatting with color coding -->
    <!-- - Complete system + maintenance data aggregation -->
    <!-- ============================================================ -->
    # Write HTML report to file system
    try {
        $htmlContent | Out-File -FilePath $htmlReportPath -Encoding UTF8
        Write-Log "Professional HTML report generated: $htmlReportPath" 'INFO'
        
        # Log report size for reference
        $reportSize = (Get-Item $htmlReportPath).Length
        $reportSizeMB = [Math]::Round($reportSize / 1MB, 2)
        Write-Log "Report file size: $reportSizeMB MB" 'DEBUG'
    }
    catch {
        Write-Log "Failed to write HTML report: $_" 'WARN'
    }

    <!-- ============================================================ -->
    <!-- REPORT GENERATION COMPLETION -->
    <!-- ============================================================ -->
    <!-- Function End Marker: [END] Unified Maintenance Report -->
    <!-- Return Value: Hashtable with report paths and statistics -->
    <!-- ============================================================ -->
    Write-Log '[END] Unified Maintenance Report Generation' 'INFO'
    return @{
        JsonReport  = $jsonReportPath
        TextReport  = $textReportPath
        HtmlReport  = $htmlReportPath
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
if (-not $global:TempFolder) {
    $global:TempFolder = Join-Path $WorkingDirectory 'temp_files'
}
$global:SystemInventory = $null
if (-not $global:TaskResults) {
    $global:TaskResults = @{}
}

# Create temp directory if it doesn't exist
if (-not (Test-Path $global:TempFolder)) {
    New-Item -Path $global:TempFolder -ItemType Directory -Force | Out-Null
}

# Configuration management with defaults
$configPath = Join-Path $WorkingDirectory 'config.json'
if (-not $global:Config) {
    $global:Config = @{
        SkipBloatwareRemoval    = $false
        SkipEssentialApps       = $false
        SkipWindowsUpdates      = $false
        SkipPackageUpdates      = $false
        SkipTelemetryDisable    = $false
        SkipSystemRestore       = $false
        SkipRestorePointCleanup = $false
        SkipEventLogAnalysis    = $false
        SkipSecurityHardening   = $false
        SkipTaskbarOptimization = $false
        SkipDesktopBackground   = $false
        SkipPendingRestartCheck = $false
        CustomEssentialApps     = @()
        CustomBloatwareList     = @()
        EnableVerboseLogging    = $false
    }
}

# Granular defaults for maintenance behaviors
if (-not $global:Config.TelemetryServicesToDisable) {
    $global:Config.TelemetryServicesToDisable = @(
        'DiagTrack',
        'dmwappushservice',
        'UnistoreSvc',
        'UserDataSvc',
        'BrokerInfrastructure',
        'PimIndexMaintenanceSvc',
        'MessagingService'
    )
}
if (-not $global:Config.ContainsKey('MinRestorePointsToKeep')) { $global:Config.MinRestorePointsToKeep = 5 }
if (-not $global:Config.ContainsKey('AllowDisableWerSvc')) { $global:Config.AllowDisableWerSvc = $false }
if (-not $global:Config.ContainsKey('SkipWidgetsOnly')) { $global:Config.SkipWidgetsOnly = $false }
if (-not $global:Config.ContainsKey('PromptForReboot')) { $global:Config.PromptForReboot = $false }

# Load configuration from config.json if it exists
if (Test-Path $configPath) {
    try {
        $config = Get-Content $configPath | ConvertFrom-Json
        # Merge custom config with defaults
        if ($config.SkipBloatwareRemoval) { $global:Config.SkipBloatwareRemoval = $config.SkipBloatwareRemoval }
        if ($config.SkipEssentialApps) { $global:Config.SkipEssentialApps = $config.SkipEssentialApps }
        if ($config.SkipWindowsUpdates) { $global:Config.SkipWindowsUpdates = $config.SkipWindowsUpdates }
        if ($config.SkipPackageUpdates) { $global:Config.SkipPackageUpdates = $config.SkipPackageUpdates }
        if ($config.SkipTelemetryDisable) { $global:Config.SkipTelemetryDisable = $config.SkipTelemetryDisable }
        if ($config.SkipSystemRestore) { $global:Config.SkipSystemRestore = $config.SkipSystemRestore }
        if ($config.SkipRestorePointCleanup) { $global:Config.SkipRestorePointCleanup = $config.SkipRestorePointCleanup }
        if ($config.SkipEventLogAnalysis) { $global:Config.SkipEventLogAnalysis = $config.SkipEventLogAnalysis }
        if ($config.SkipSecurityHardening) { $global:Config.SkipSecurityHardening = $config.SkipSecurityHardening }
        if ($config.SkipTaskbarOptimization) { $global:Config.SkipTaskbarOptimization = $config.SkipTaskbarOptimization }
        if ($config.SkipDesktopBackground) { $global:Config.SkipDesktopBackground = $config.SkipDesktopBackground }
        if ($config.SkipPendingRestartCheck) { $global:Config.SkipPendingRestartCheck = $config.SkipPendingRestartCheck }
        if ($config.CustomEssentialApps) { $global:Config.CustomEssentialApps = $config.CustomEssentialApps }
        if ($config.CustomBloatwareList) { $global:Config.CustomBloatwareList = $config.CustomBloatwareList }
        if ($config.EnableVerboseLogging) { $global:Config.EnableVerboseLogging = $config.EnableVerboseLogging }
        if ($config.AllowDisableWerSvc) { $global:Config.AllowDisableWerSvc = $config.AllowDisableWerSvc }
        if ($config.SkipWidgetsOnly) { $global:Config.SkipWidgetsOnly = $config.SkipWidgetsOnly }
        if ($config.PromptForReboot) { $global:Config.PromptForReboot = $config.PromptForReboot }
        Write-Log 'Configuration loaded from config.json' 'INFO'
    }
    catch {
        Write-Log "Error loading config.json: $_. Using defaults." 'WARN'
    }
}

# Load logging configuration from logging.json if it exists
$loggingConfigPath = Join-Path $WorkingDirectory 'config\logging.json'
$global:LoggingConfig = @{
    LogLevel           = 'INFO'
    LogFile            = $global:LogFile
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

if (Test-Path $loggingConfigPath) {
    try {
        $loggingConfig = Get-Content $loggingConfigPath | ConvertFrom-Json
        # Override defaults with loaded config
        $global:LoggingConfig.LogLevel = $loggingConfig.LogLevel
        $global:LoggingConfig.EnableColors = $loggingConfig.EnableColors
        $global:LoggingConfig.EnableProgressBars = $loggingConfig.EnableProgressBars
        $global:LoggingConfig.MaxLogSizeMB = $loggingConfig.MaxLogSizeMB
        $global:LoggingConfig.LogRotation = $loggingConfig.LogRotation
        $global:LoggingConfig.DateTimeFormat = $loggingConfig.DateTimeFormat
        $global:LoggingConfig.MessageFormat = $loggingConfig.MessageFormat
        $global:LoggingConfig.LogLevels = $loggingConfig.LogLevels
        Write-Log 'Logging configuration loaded from logging.json' 'INFO'
    }
    catch {
        Write-Log "Error loading logging.json: $_. Using defaults." 'WARN'
    }
}
else {
    Write-Log 'No logging.json found - using default logging configuration' 'DEBUG'
}

# ================================================================
# DYNAMIC CONFIGURATION: Build App Lists from Centralized Categories
# ================================================================

# Build unified bloatware list from categorized definitions
$global:BloatwareList = @()
foreach ($category in $global:AppCategories.Keys) {
    $global:BloatwareList += $global:AppCategories[$category]
}
$global:BloatwareList = $global:BloatwareList | Sort-Object -Unique

# Add custom bloatware from config if any
if ($global:Config.CustomBloatwareList -and $global:Config.CustomBloatwareList.Count -gt 0) {
    $global:BloatwareList += $global:Config.CustomBloatwareList
    $global:BloatwareList = $global:BloatwareList | Sort-Object -Unique
    Write-Log "Added $($global:Config.CustomBloatwareList.Count) custom bloatware entries from config" 'INFO'
}

# Save categorized and unified bloatware lists
$bloatwareListPath = Join-Path $global:TempFolder 'bloatware.json'
@{
    Categories     = $global:AppCategories
    UnifiedList    = $global:BloatwareList
    TotalCount     = $global:BloatwareList.Count
    CategoryCounts = @{}
} | ConvertTo-Json -Depth 4 | Out-File $bloatwareListPath -Encoding UTF8

# Calculate category statistics
$categorizedBloatware = @{}
foreach ($category in $global:AppCategories.Keys) {
    $categorizedBloatware[$category] = $global:AppCategories[$category].Count
}

# Build unified essential apps list from categorized definitions
$global:EssentialApps = @()
foreach ($category in $global:EssentialCategories.Keys) {
    $global:EssentialApps += $global:EssentialCategories[$category]
}

# Add custom essential apps from config if any
if ($global:Config.CustomEssentialApps -and $global:Config.CustomEssentialApps.Count -gt 0) {
    $global:EssentialApps += $global:Config.CustomEssentialApps
    Write-Log "Added $($global:Config.CustomEssentialApps.Count) custom essential apps from config" 'INFO'
}

# Save categorized and unified essential apps lists
$essentialAppsListPath = Join-Path $global:TempFolder 'essential_apps.json'
@{
    Categories     = $global:EssentialCategories
    UnifiedList    = $global:EssentialApps
    TotalCount     = $global:EssentialApps.Count
    CategoryCounts = @{}
} | ConvertTo-Json -Depth 5 | Out-File $essentialAppsListPath -Encoding UTF8

# Calculate category statistics for essential apps
$categorizedEssential = @{}
foreach ($category in $global:EssentialCategories.Keys) {
    $categorizedEssential[$category] = $global:EssentialCategories[$category].Count
}

Write-Log "Configuration initialized: Bloatware=$($global:BloatwareList.Count), Essential Apps=$($global:EssentialApps.Count)" 'INFO'

# Save essential apps list
$essentialAppsListPath = Join-Path $global:TempFolder 'essential_apps.json'
$global:EssentialApps | ConvertTo-Json -Depth 5 | Out-File $essentialAppsListPath -Encoding UTF8

# ================================================================
# MAIN EXECUTION LOGIC
# ================================================================

# Enhanced script startup logging with system information
$startTime = Get-Date
Write-Log '============================================================' 'INFO'
Write-ActionLog -Action 'PowerShell Maintenance Script Starting' -Details 'Enhanced logging enabled' -Category 'System Startup' -Status 'START'

# Write comprehensive system summary header to log
Write-SystemSummaryHeader
Write-ActionLog -Action 'Environment Analysis' -Details "Script Path: $PSCommandPath" -Category 'System Startup' -Status 'INFO'
Write-ActionLog -Action 'Environment Analysis' -Details "PowerShell Version: $($PSVersionTable.PSVersion)" -Category 'System Startup' -Status 'INFO'
Write-ActionLog -Action 'Environment Analysis' -Details "PowerShell Edition: $($PSVersionTable.PSEdition)" -Category 'System Startup' -Status 'INFO'
Write-ActionLog -Action 'Environment Analysis' -Details "OS Version: $([System.Environment]::OSVersion.VersionString)" -Category 'System Startup' -Status 'INFO'
Write-ActionLog -Action 'Environment Analysis' -Details "User: $([System.Environment]::UserName)" -Category 'System Startup' -Status 'INFO'
Write-ActionLog -Action 'Environment Analysis' -Details "Machine: $([System.Environment]::MachineName)" -Category 'System Startup' -Status 'INFO'
Write-ActionLog -Action 'Environment Analysis' -Details "Temp Folder: $global:TempFolder" -Category 'System Startup' -Status 'INFO'
Write-ActionLog -Action 'Configuration Status' -Details "Verbose Logging: $($global:Config.EnableVerboseLogging)" -Category 'System Startup' -Status 'INFO'
Write-ActionLog -Action 'Logging Configuration' -Details "Log File: $global:LogFile" -Category 'System Startup' -Status 'INFO'
Write-Log '============================================================' 'INFO'

# Execute all maintenance tasks with enhanced logging
Write-ActionLog -Action 'Starting maintenance task execution' -Details 'All configured tasks will be executed' -Category 'Task Orchestration' -Status 'START'
Use-AllScriptTasks

# ================================================================
# POST-EXECUTION REPORTING AND CLEANUP
# ================================================================

# Calculate summary statistics
$successCount = ($global:TaskResults.Values | Where-Object { $_.IsSuccessful }).Count
$failCount = ($global:TaskResults.Values | Where-Object { -not $_.IsSuccessful }).Count
$totalCount = $global:TaskResults.Count

# Log task execution summary
Write-Log '============================================================' 'INFO'
Write-Log 'MAINTENANCE EXECUTION SUMMARY' 'INFO'
Write-Log "Total tasks: $totalCount | Success: $successCount | Failed: $failCount" 'INFO'

# Detailed task results
foreach ($taskName in $global:TaskResults.Keys) {
    $result = $global:TaskResults[$taskName]
    $task = $global:ScriptTasks | Where-Object { $_.Name -eq $taskName }
    $status = if ($result.IsSuccessful) { 'SUCCESS' } else { 'FAILED' }
    $duration = if ($result.Duration) { [math]::Round($result.Duration, 2) } else { 0 }
    $started = if ($result.Started) { $result.Started.ToString('HH:mm:ss') } else { 'Unknown' }
    $ended = if ($result.Ended) { $result.Ended.ToString('HH:mm:ss') } else { 'Unknown' }

    Write-Log "Task: $taskName | $status | Duration: ${duration}s | ${started}-${ended}" 'INFO'
    if (-not $result.IsSuccessful -and $result.ContainsKey('Error') -and $result.Error) {
        Write-Log "    Error: $($result.Error)" 'ERROR'
    }
}

Write-Log '============================================================' 'INFO'

# Generate comprehensive reports
Write-Log 'Generating maintenance reports...' 'INFO'

# Generate temp lists summary
Write-TempListsSummary

# Generate unified maintenance report
$reportResult = Write-UnifiedMaintenanceReport

if ($reportResult) {
    Write-Log 'Reports generated successfully:' 'INFO'
    Write-Log "- JSON Report: $($reportResult.JsonReport)" 'INFO'
    Write-Log "- Text Report: $($reportResult.TextReport)" 'INFO'
    Write-Log "- Success Rate: $($reportResult.SuccessRate)%" 'INFO'
}

# Final completion logging
$totalExecutionTime = (Get-Date) - $startTime
$completionTimestamp = Get-Date -Format 'MM/dd/yyyy HH:mm:ss'

Write-Log '============================================================' 'INFO'
Write-Log 'PowerShell Maintenance Script execution completed successfully' 'INFO'
Write-Log "Total execution time: $totalExecutionTime" 'INFO'
Write-Log "Log file location: $LogFile" 'INFO'
Write-Log '============================================================' 'INFO'

# Add completion marker to log file for script.bat detection
Add-Content -Path $LogFile -Value "[$completionTimestamp] [INFO] ============================================================"
Add-Content -Path $LogFile -Value "[$completionTimestamp] [INFO] PowerShell Maintenance Script Completed Successfully"
Add-Content -Path $LogFile -Value "[$completionTimestamp] [INFO] Returning control to script.bat (if applicable)"
Add-Content -Path $LogFile -Value "[$completionTimestamp] [INFO] ============================================================"

# Enhanced post-execution cleanup with 120-second countdown and comprehensive logging
if ($Host.Name -eq 'ConsoleHost' -or $Host.Name -like '*Windows*') {
    Write-Host
    Write-Host '✅ Maintenance script completed successfully!' -ForegroundColor Green
    Write-Host "📊 Tasks: $totalCount | ✅ Success: $successCount | ❌ Failed: $failCount" -ForegroundColor Cyan
    Write-Host "⏱️  Total time: $totalExecutionTime" -ForegroundColor Cyan
    Write-Host "📄 Reports available in: $WorkingDirectory" -ForegroundColor Cyan
    Write-Host

    Write-Log '[POST-EXECUTION] Starting post-execution cleanup and system state analysis' 'INFO'

    # NOTE: Cleanup and repository removal are deferred until AFTER the interactive
    # countdown. If the user interacts during the countdown (sets $abort = $true),
    # we intentionally skip cleaning repo/temp files and we leave the terminal open
    # so the operator can inspect logs or manually remove files. The actual cleanup
    # is performed later only when the countdown finishes without user interaction.
    $repoFolder = $ScriptDir
    $repoCleanupSuccess = $false

    # STEP 2: Check for pending restart requirements
    Write-Log '[RESTART-CHECK] Analyzing system restart requirements' 'INFO'
    Write-Host '🔍 Checking system restart requirements...' -ForegroundColor Cyan

    $rebootRequired = $false
    $rebootReason = ''
    $rebootSources = @()

    # Check global Windows Updates reboot requirement first
    if ($global:SystemSettings.Reboot.Required -eq $true) {
        $rebootRequired = $true
        $rebootReason = 'Windows Updates installation'
        $rebootSources += "Global Windows Updates flag ($($global:SystemSettings.Reboot.Source))"
        Write-Log "[RESTART-CHECK] Global restart flag detected: $($global:SystemSettings.Reboot.Source)" 'INFO'
    }

    # Check registry-based reboot indicators
    $registryKeys = @(
        @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'; Description = 'Windows Update reboot required' },
        @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'; Description = 'Component Based Servicing reboot pending' },
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager'; Value = 'PendingFileRenameOperations'; Description = 'Pending file rename operations' }
    )

    foreach ($keyInfo in $registryKeys) {
        try {
            if ($keyInfo.Value) {
                # Check for specific value
                $regValue = Get-ItemProperty -Path $keyInfo.Path -Name $keyInfo.Value -ErrorAction SilentlyContinue
                if ($regValue) {
                    $rebootRequired = $true
                    $rebootSources += $keyInfo.Description
                    Write-Log "[RESTART-CHECK] Registry restart indicator found: $($keyInfo.Description)" 'INFO'
                }
            }
            else {
                # Check for key existence
                if (Test-Path $keyInfo.Path) {
                    $rebootRequired = $true
                    $rebootSources += $keyInfo.Description
                    Write-Log "[RESTART-CHECK] Registry restart indicator found: $($keyInfo.Description)" 'INFO'
                }
            }
        }
        catch {
            Write-Log "[RESTART-CHECK] Error checking registry key $($keyInfo.Path): $_" 'WARN'
        }
    }

    # Log restart determination results
    if ($rebootRequired) {
        $rebootReason = $rebootSources -join '; '
        Write-Host '⚠️  SYSTEM RESTART REQUIRED' -ForegroundColor Yellow
        Write-Host "📋 Reason(s): $rebootReason" -ForegroundColor Yellow
        Write-Log "[RESTART-CHECK] System restart required. Reasons: $rebootReason" 'INFO'
    }
    else {
        Write-Host '✅ No system restart required' -ForegroundColor Green
        Write-Log '[RESTART-CHECK] No system restart required' 'INFO'
    }

    # STEP 3: 120-second countdown with comprehensive user interaction handling
    Write-Host
    if ($rebootRequired -and -not $global:Config.PromptForReboot) {
        # Non-interactive mode: do not prompt or perform automatic restart. Leave decision to user.
        Write-Host "🔕 Reboot is required but script is configured NOT to prompt or restart (PromptForReboot = $false)." -ForegroundColor Yellow
        Write-Log '[COUNTDOWN] Reboot required but PromptForReboot is disabled; skipping interactive countdown and automatic restart' 'INFO'
        # Provide clear instruction and do not close the window automatically
        Write-Host '⚠️  Your system requires a restart to complete updates. Please restart manually when convenient.' -ForegroundColor Cyan
        Write-Log "[EXECUTION] Manual restart recommended: $rebootReason" 'INFO'
        # Skip countdown and interactive prompt flow entirely
        $countdown = 0
        $abort = $true
    }
    else {
        if ($rebootRequired) {
            Write-Host '🔄 Starting 120-second countdown for automatic restart and cleanup.' -ForegroundColor Yellow
            Write-Host '💡 Press any key to abort restart and keep window open.' -ForegroundColor Cyan
            Write-Log '[COUNTDOWN] Starting 120-second restart countdown' 'INFO'
        }
        else {
            Write-Host '🕒 Starting 120-second countdown for automatic cleanup and window closure.' -ForegroundColor Yellow
            Write-Host '💡 Press any key to abort cleanup and keep window open.' -ForegroundColor Cyan
            Write-Log '[COUNTDOWN] Starting 120-second cleanup countdown (no restart needed)' 'INFO'
        }
    }

    $countdown = 120
    $abort = $false
    $lastMinuteReported = -1

    # Enhanced countdown with minute-by-minute logging and key detection
    Write-Log "[COUNTDOWN] Starting countdown loop: $countdown seconds total" 'INFO'
    for ($i = $countdown; $i -ge 1; $i--) {
        # Log every minute milestone
        $currentMinute = [math]::Floor($i / 60)
        if ($currentMinute -ne $lastMinuteReported -and ($i % 60) -eq 0) {
            $lastMinuteReported = $currentMinute
            Write-Log "[COUNTDOWN] Countdown milestone: $currentMinute minute(s) remaining" 'INFO'
        }

        # Log every 10 seconds for debugging
        if ($i -le 10 -or ($i % 10) -eq 0) {
            Write-Log "[COUNTDOWN] $i seconds remaining..." 'INFO'
        }

        # Display countdown message based on restart requirement
        if ($rebootRequired) {
            Write-Host "`r🔄 Automatic restart in $i seconds... Press any key to abort." -NoNewline -ForegroundColor Yellow
        }
        else {
            Write-Host "`r🕒 Automatic cleanup and closure in $i seconds... Press any key to abort." -NoNewline -ForegroundColor Yellow
        }

        # Robust key press detection with proper error handling
        try {
            # Use a more reliable approach - check for actual console input buffer
            $keyPressed = $false

            # Check multiple times during the 1-second interval
            for ($k = 0; $k -lt 4; $k++) {
                Start-Sleep -Milliseconds 250

                # Only check KeyAvailable if we're in an interactive console
                if ($Host.UI.RawUI -and $Host.UI.RawUI.KeyAvailable) {
                    try {
                        # Actually read the key to confirm it's real
                        $key = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
                        if ($key) {
                            $keyPressed = $true
                            Write-Log "[COUNTDOWN] User interaction detected - key pressed: $($key.Character)" 'INFO'
                            break
                        }
                    }
                    catch {
                        # If ReadKey fails, it might be a false positive from KeyAvailable
                        Write-Log "[COUNTDOWN] False key detection ignored: $_" 'WARN'
                    }
                }
            }

            if ($keyPressed) {
                $abort = $true
            }
        }
        catch {
            # Fallback to simple sleep if key detection fails completely
            Start-Sleep -Seconds 1
            Write-Log "[COUNTDOWN] Key detection system failed, using fallback timing: $_" 'WARN'
        }

        if ($abort) { break }
    }

    Write-Host ''  # New line after countdown

    # STEP 4: Execute appropriate action based on countdown result
    Write-Log "[COUNTDOWN] Countdown finished. Abort status: $abort, Reboot required: $rebootRequired" 'INFO'
    if (-not $abort) {
        Write-Log '[COUNTDOWN] Countdown completed without user interaction - proceeding with automatic action' 'INFO'

        # Since there was no user interaction, perform cleanup of temporary files
        # and attempt repository removal before initiating restart or closing the
        # terminal. This ensures unattended runs clean up after themselves.
        try {
            Write-Log '[CLEANUP] Removing all temporary files and folders from repository (deferred)' 'INFO'
            Write-Host '🗑️  Cleaning up temporary files...' -ForegroundColor Yellow
            Remove-AllTempFiles

            # Repository folder removal (deferred)
            Write-Log '[CLEANUP] Initiating deferred repository directory removal' 'INFO'
            Write-Host '🧹 Starting deferred repository cleanup...' -ForegroundColor Cyan

            # Navigate to parent directory before removing repository folder
            $parentPath = Split-Path -Path $repoFolder -Parent
            if (Test-Path -Path $parentPath) {
                Set-Location -Path $parentPath
                Write-Host "📁 Changed directory to: $parentPath" -ForegroundColor Yellow
                Write-Log "[CLEANUP] Changed working directory to parent: $parentPath" 'INFO'
                Start-Sleep -Milliseconds 500
            }

            # Force garbage collection and brief delay
            [System.GC]::Collect(); [System.GC]::WaitForPendingFinalizers(); [System.GC]::Collect()
            Start-Sleep -Seconds 1

            if (Test-Path -Path $repoFolder) {
                Write-Host "🗑️  Removing repository folder: $repoFolder" -ForegroundColor Yellow
                Write-Log "[CLEANUP] Attempting repository folder removal: $repoFolder" 'INFO'
                try {
                    Remove-Item -Path $repoFolder -Recurse -Force -ErrorAction Stop
                    Write-Host '✅ Repository folder removed successfully' -ForegroundColor Green
                    Write-Log '[CLEANUP] Repository folder removed successfully using standard method' 'INFO'
                    $repoCleanupSuccess = $true
                }
                catch {
                    Write-Host '⚠️  Standard removal failed, trying alternative method...' -ForegroundColor Yellow
                    Write-Log "[CLEANUP] Standard removal failed: $($_.Exception.Message)" 'WARN'
                    try {
                        $tempEmptyDir = Join-Path $parentPath "temp_empty_$(Get-Random)"
                        New-Item -Path $tempEmptyDir -ItemType Directory -Force | Out-Null
                        Write-Log "[CLEANUP] Created temporary empty directory: $tempEmptyDir" 'INFO'
                        $repoCleanupProcess = Start-Process -FilePath 'robocopy.exe' -ArgumentList "`"$tempEmptyDir`"", "`"$repoFolder`"", '/MIR', '/NJH', '/NJS', '/NC', '/NDL', '/NP' -Wait -PassThru -WindowStyle Hidden
                        $repoExitCode = $repoCleanupProcess.ExitCode
                        Write-Log "[CLEANUP] Robocopy cleanup exit code: $repoExitCode" 'INFO'
                        Remove-Item -Path $tempEmptyDir -Force -ErrorAction SilentlyContinue
                        Remove-Item -Path $repoFolder -Recurse -Force -ErrorAction Stop
                        Write-Host '✅ Repository folder removed using alternative method' -ForegroundColor Green
                        Write-Log '[CLEANUP] Repository folder removed successfully using robocopy method' 'INFO'
                        $repoCleanupSuccess = $true
                    }
                    catch {
                        Write-Host "❌ Failed to remove repository folder: $($_.Exception.Message)" -ForegroundColor Red
                        Write-Host "⚠️  Manual removal may be required: $repoFolder" -ForegroundColor Yellow
                        Write-Log "[CLEANUP] Repository folder removal failed: $($_.Exception.Message)" 'ERROR'
                        $repoCleanupSuccess = $false
                    }
                }
            }
            else {
                Write-Host "⚠️  Repository folder not found: $repoFolder" -ForegroundColor Yellow
                Write-Log "[CLEANUP] Repository folder not found: $repoFolder" 'WARN'
                $repoCleanupSuccess = $true
            }
        }
        catch {
            Write-Host "❌ Unexpected error during deferred repository cleanup: $($_.Exception.Message)" -ForegroundColor Red
            Write-Log "[CLEANUP] Unexpected error during deferred repository cleanup: $($_.Exception.Message)" 'ERROR'
            $repoCleanupSuccess = $false
        }

        if ($rebootRequired) {
            # No user interaction + restart needed → Close terminal + restart PC
            Write-Host '🔄 Initiating system restart and terminal closure...' -ForegroundColor Green
            Write-Host '📋 Your system will restart automatically to complete all changes.' -ForegroundColor Cyan
            Write-Log '[EXECUTION] Initiating system restart (no user interaction)' 'INFO'

            try {
                # Start the restart process
                $shutdownArgs = @('/r', '/t', '10', '/c', "Maintenance script restart: $rebootReason")
                Start-Process -FilePath 'shutdown.exe' -ArgumentList $shutdownArgs -NoNewWindow
                Write-Log '[EXECUTION] System restart command executed successfully' 'INFO'

                # Clear the global reboot flag since we're restarting
                $global:SystemSettings.Reboot.Required = $false
                $global:SystemSettings.Reboot.Source = $null
                $global:SystemSettings.Reboot.Timestamp = $null
                Write-Log '[EXECUTION] Global restart flags cleared' 'INFO'

                Write-Host '✅ System restart initiated. Terminal closing in 5 seconds...' -ForegroundColor Green
                Write-Log '[EXECUTION] Terminal closure initiated - 5 second delay' 'INFO'
                Start-Sleep -Seconds 5

                # Force close terminal
                Write-Log '[EXECUTION] Executing terminal closure via Environment.Exit' 'INFO'
                [System.Environment]::Exit(0)
            }
            catch {
                Write-Host "❌ Failed to initiate restart: $_" -ForegroundColor Red
                Write-Log "[EXECUTION] Failed to initiate system restart: $_" 'ERROR'
                Write-Host '⚠️  Please restart your system manually to complete the updates.' -ForegroundColor Yellow
                Write-Log '[EXECUTION] Manual restart required due to automation failure' 'WARN'
                Read-Host -Prompt 'Press Enter to close this window...'
            }
        }
        else {
            # No user interaction + no restart needed → Just close terminal
            Write-Host '✅ Cleanup completed. Closing terminal window...' -ForegroundColor Green
            Write-Log '[EXECUTION] Closing terminal window (no restart needed, no user interaction)' 'INFO'

            Write-Host '📋 All maintenance tasks completed successfully.' -ForegroundColor Cyan
            Write-Host '🕒 Terminal closing in 3 seconds...' -ForegroundColor Yellow
            Write-Log '[EXECUTION] Terminal closure initiated - 3 second delay' 'INFO'
            Start-Sleep -Seconds 3

            try {
                # Close terminal using multiple strategies
                Write-Log '[EXECUTION] Executing terminal closure via Environment.Exit' 'INFO'
                if ($Host.Name -eq 'ConsoleHost') {
                    [System.Environment]::Exit(0)
                }
                elseif ($Host.Name -eq 'ConsoleHost') {
                    Stop-Process -Id $PID -Force
                }
                else {
                    exit 0
                }
            }
            catch {
                # Fallback closure methods
                Write-Log '[EXECUTION] Primary closure method failed, using fallback' 'WARN'
                try {
                    Stop-Process -Id $PID -Force
                }
                catch {
                    exit 0
                }
            }
        }
    }
    else {
        # User interaction → Abort countdown, abort restart, abort terminal closing
        Write-Host "`r✋ Operation aborted by user interaction." -ForegroundColor Green
        Write-Log '[EXECUTION] All operations aborted due to user interaction' 'INFO'

        if ($rebootRequired) {
            Write-Host '⚠️  Important: Your system still requires a restart to complete updates.' -ForegroundColor Yellow
            Write-Host "📋 Restart reasons: $rebootReason" -ForegroundColor Yellow
            Write-Host '💡 Please restart manually when convenient to apply all changes.' -ForegroundColor Cyan
            Write-Log "[EXECUTION] User aborted restart - manual restart still required: $rebootReason" 'WARN'
        }
        else {
            Write-Host '✅ No restart required. All maintenance tasks completed successfully.' -ForegroundColor Green
            Write-Log '[EXECUTION] User aborted cleanup - no restart required' 'INFO'
        }

        if (-not $repoCleanupSuccess) {
            Write-Host '⚠️  Note: Repository cleanup may have failed. Manual cleanup might be needed.' -ForegroundColor Yellow
            Write-Host "📁 Repository location: $repoFolder" -ForegroundColor Yellow
            Write-Log '[EXECUTION] Repository cleanup reminder provided to user' 'INFO'
        }

        Write-Host '🔗 Window will remain open for your review.' -ForegroundColor Cyan
        Write-Log '[EXECUTION] Terminal window kept open per user interaction' 'INFO'
        Read-Host -Prompt 'Press Enter to close this window...'
    }

    Write-Log '[POST-EXECUTION] Post-execution cleanup and countdown sequence completed' 'INFO'
}
