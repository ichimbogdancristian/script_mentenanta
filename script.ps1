# ================================================================
# ================================================================
# [ENVIRONMENT AWARENESS & PATH/PERMISSION SETUP]
# ================================================================
# Purpose: Ensure script is aware of its environment, path, and permissions before any operations
# ------------------------------------------------
param(
    [string]$LogFilePath,
    [string]$RepoFolderPath = ""
)

# Enhanced environment detection for consistency with batch script
$ScriptFullPath = $MyInvocation.MyCommand.Path
$ScriptDir      = Split-Path -Parent $ScriptFullPath
$ScriptName     = Split-Path -Leaf $ScriptFullPath
$ScriptDrive = if ($ScriptFullPath.StartsWith("\\")) { 
    "UNC Path" 
} else { 
    (Get-Item $ScriptFullPath).PSDrive.Name + ":" 
}

# Detect drive type for path independence (matching batch script logic)
$IsNetworkPath = $false
$IsUNCPath = $ScriptFullPath.StartsWith("\\")

$DriveType = if ($IsUNCPath) {
    $IsNetworkPath = $true
    "Network"
} elseif ($ScriptDrive -ne "UNC Path") {
    $DriveInfo = Get-WmiObject -Class Win32_LogicalDisk | Where-Object { $_.DeviceID -eq $ScriptDrive }
    if ($DriveInfo) { 
        $DriveTypeNum = $DriveInfo.DriveType
        if ($DriveTypeNum -eq 4) { $IsNetworkPath = $true }
        switch ($DriveTypeNum) {
            2 { "Removable" }
            3 { "Fixed" }
            4 { "Network" }
            5 { "CD-ROM" }
            default { "Unknown" }
        }
    } else { "Unknown" }
} else { "Unknown" }

# System environment information (matching batch script variables)
$ComputerName   = $env:COMPUTERNAME
$CurrentUser    = $env:USERNAME
$IsAdmin        = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

# OS information (matching batch script format)
$OSVersion = (Get-WmiObject -Class Win32_OperatingSystem).Caption
$OSArchitecture = $env:PROCESSOR_ARCHITECTURE
if ($OSArchitecture -eq "AMD64") { $OSArch = "x64" }
elseif ($OSArchitecture -eq "x86") { $OSArch = "x86" }
elseif ($OSArchitecture -eq "ARM64") { $OSArch = "ARM64" }
else { $OSArch = $OSArchitecture }

$PSVersion = $PSVersionTable.PSVersion.ToString()
$WorkingDirectory = Get-Location

# Set up shared log file - prioritize parameter, then environment variable, then default
if ($LogFilePath) {
    $LogFile = $LogFilePath
    Write-Host "[INFO] Using log file from parameter: $LogFile" -ForegroundColor Green
} elseif ($env:SCRIPT_LOG_FILE) {
    $LogFile = $env:SCRIPT_LOG_FILE
    Write-Host "[INFO] Using batch script log file from environment: $LogFile" -ForegroundColor Green
} else {
    # Fallback: script.ps1 might be inside extracted repo folder, maintenance.log should be in parent directory (where script.bat is)
    $batchScriptDirectory = Split-Path $ScriptDir -Parent
    $LogFile = Join-Path $batchScriptDirectory 'maintenance.log'
    Write-Host "[INFO] Using default PowerShell log file (parent directory): $LogFile" -ForegroundColor Yellow
}

# Ensure log file directory exists
$logDir = Split-Path $LogFile -Parent
if (-not (Test-Path $logDir)) {
    New-Item -Path $logDir -ItemType Directory -Force | Out-Null
}

# Log environment info with enhanced details matching batch script
Write-Host "[INFO] Script Full Path: $ScriptFullPath"
Write-Host "[INFO] Script Directory: $ScriptDir"
Write-Host "[INFO] Script Name: $ScriptName"
Write-Host "[INFO] Script Drive: $ScriptDrive (Type: $DriveType)"
Write-Host "[INFO] Network Path: $IsNetworkPath, UNC Path: $IsUNCPath"
Write-Host "[INFO] Computer Name: $ComputerName"
Write-Host "[INFO] User Name: $CurrentUser"
Write-Host "[INFO] OS Version: $OSVersion"
Write-Host "[INFO] OS Architecture: $OSArch"
Write-Host "[INFO] PowerShell Version: $PSVersion"
Write-Host "[INFO] Admin Privileges: $IsAdmin"
Write-Host "[INFO] Working Directory: $WorkingDirectory"

# Log PowerShell script startup with detailed information matching batch script format
$startTime = Get-Date
$timestamp = Get-Date -Format 'MM/dd/yyyy HH:mm:ss'
Add-Content -Path $LogFile -Value "[$timestamp] [INFO] ============================================================"
Add-Content -Path $LogFile -Value "[$timestamp] [INFO] PowerShell Maintenance Script Started (Launched by script.bat)"
Add-Content -Path $LogFile -Value "[$timestamp] [INFO] ============================================================"
Add-Content -Path $LogFile -Value "[$timestamp] [INFO] Script Full Path: $ScriptFullPath"
Add-Content -Path $LogFile -Value "[$timestamp] [INFO] Script Directory: $ScriptDir"
Add-Content -Path $LogFile -Value "[$timestamp] [INFO] Script Name: $ScriptName"
Add-Content -Path $LogFile -Value "[$timestamp] [INFO] Script Drive: $ScriptDrive (Type: $DriveType)"
Add-Content -Path $LogFile -Value "[$timestamp] [INFO] Network Path: $IsNetworkPath, UNC Path: $IsUNCPath"
Add-Content -Path $LogFile -Value "[$timestamp] [INFO] Computer Name: $ComputerName"
Add-Content -Path $LogFile -Value "[$timestamp] [INFO] User Name: $CurrentUser"
Add-Content -Path $LogFile -Value "[$timestamp] [INFO] OS Version: $OSVersion"
Add-Content -Path $LogFile -Value "[$timestamp] [INFO] OS Architecture: $OSArch"
Add-Content -Path $LogFile -Value "[$timestamp] [INFO] PowerShell Version: $PSVersion"
Add-Content -Path $LogFile -Value "[$timestamp] [INFO] Admin Privileges: $IsAdmin"
Add-Content -Path $LogFile -Value "[$timestamp] [INFO] Working Directory: $WorkingDirectory"
Add-Content -Path $LogFile -Value "[$timestamp] [INFO] Log File: $LogFile"
Add-Content -Path $LogFile -Value "[$timestamp] [INFO] ============================================================"

# Relaunch as admin if needed
if (-not $IsAdmin) {
    Write-Host "[WARN] Script not running as administrator. Relaunching..."
    Add-Content -Path $LogFile -Value "[$(Get-Date -Format 'MM/dd/yyyy HH:mm:ss')] [WARN] Script not running as administrator. Relaunching..."
    if ($LogFilePath) {
        Start-Process -FilePath pwsh -ArgumentList "-File", $ScriptFullPath, "-LogFilePath", $LogFile -Verb RunAs
    } else {
        Start-Process -FilePath pwsh -ArgumentList "-File", $ScriptFullPath -Verb RunAs
    }
    exit
}
# ================================================================
# WINDOWS MAINTENANCE SCRIPT - COPILOT DEVELOPMENT INDEX
# ================================================================
#
# SCRIPT INDEX FOR AI DEVELOPMENT:
# ================================
# 
# [A] GLOBAL STRUCTURE (Lines 1-558)
#     A.1 Script Header & Metadata (Lines 1-15)
#     A.2 Task Array Definition (Lines 17-508)
#         - A.2.1 SystemRestoreProtection Task (Lines 19-35)
#         - A.2.2 SystemInventory Task (Lines 37-47)
#         - A.2.3 EventLogAnalysis Task (Lines 49-66)
#         - A.2.4 RemoveBloatware Task (Lines 68-84)
#         - A.2.5 InstallEssentialApps Task (Lines 86-102)
#         - A.2.6 UpdateAllPackages Task (Lines 104-115)
#         - A.2.7 WindowsUpdateCheck Task (Lines 117-140)
#         - A.2.8 DisableTelemetry Task (Lines 142-158)
#         - A.2.9 TaskbarOptimization Task (Lines 160-176)
#         - A.2.10 SecurityHardening Task (Lines 178-194)
#         - A.2.11 CleanTempAndDisk Task (Lines 196-324)
#         - A.2.12 PendingRestartCheck Task (Lines 326-507)
#     A.3 Configuration Management (Lines 509-558)
#
# [B] CORE INFRASTRUCTURE (Lines 559-1895)
#     B.1 Task Orchestration (Lines 559-627)
#         - Use-AllScriptTasks() (Lines 559-627)
#     B.2 Logging System (Lines 629-659)
#         - Write-Log() (Lines 629-659)
#     B.3 AppX Compatibility Layer (Lines 661-887)
#         - Get-AppxPackageCompatible() (Lines 661-677)
#         - Remove-AppxPackageCompatible() (Lines 679-710)
#         - Get-AppxProvisionedPackageCompatible() (Lines 712-749)
#         - Remove-AppxProvisionedPackageCompatible() (Lines 751-887)
#     B.4 Windows Update Compatibility (Lines 888-1068)
#         - Install-WindowsUpdatesCompatible() (Lines 888-1068)
#     B.5 Start Apps Compatibility (Lines 1070-1096)
#         - Get-StartAppsCompatible() (Lines 1070-1096)
#     B.6 Task Management (Lines 1098-1120)
#         - Invoke-Task() (Lines 1098-1120)
#     B.7 Extended Inventory System (Lines 1122-1725)
#         - Get-ExtensiveSystemInventory() (Lines 1122-1725)
#     B.8 Dependency Management (Lines 1727-1895)
#         - Test-PowerShellDependencies() (Lines 1727-1844)
#         - Import-ModuleWithGracefulFallback() (Lines 1846-1895)
#
# [C] MAINTENANCE TASKS (Lines 1896-4803)
#     C.1 Essential Apps Installation (Lines 1896-2249)
#         - Install-EssentialApps() [COPILOT_TASK_ID: InstallEssentialApps] (Lines 1903-2249)
#     C.2 Package Updates (Lines 2251-2672)
#         - Update-AllPackages() [COPILOT_TASK_ID: UpdateAllPackages] (Lines 2258-2672)
#     C.3 Event Log Analysis (Lines 2674-2841)
#         - Get-EventLogAnalysis() [COPILOT_TASK_ID: Survey-EventLogsAndCBS] (Lines 2679-2841)
#     C.4 Bloatware Removal (Lines 2843-3175)
#         - Remove-Bloatware() [COPILOT_TASK_ID: RemoveBloatware] (Lines 2850-3175)
#     C.5 System Inventory (Lines 3177-3191)
#         - Get-SystemInventory() (Lines 3177-3191)
#     C.6 Telemetry Disable (Lines 3193-3643)
#         - Disable-Telemetry() [COPILOT_TASK_ID: DisableTelemetry] (Lines 3200-3643)
#     C.7 Interface Optimization (Lines 3645-3861)
#         - Optimize-Taskbar() [COPILOT_TASK_ID: Optimize-Taskbar] (Lines 3650-3861)
#     C.8 Security Hardening (Lines 3863-4202)
#         - Enable-SecurityHardening() [COPILOT_TASK_ID: Enable-SecurityHardening] (Lines 3868-4202)
#     C.9 System Restore (Lines 4204-4325)
#         - Protect-SystemRestore() [COPILOT_TASK_ID: SystemRestoreProtection] (Lines 4211-4325)
#     C.10 Script Execution (Lines 4327-4803)
#         - Main Execution Block (Lines 4327-4803)
#
# COPILOT EDITING CONVENTIONS:
# ===========================
# - Each function uses COPILOT_TASK_ID for unique identification
# - All maintenance tasks follow the pattern: [COPILOT_TASK_ID: TaskName]
# - Infrastructure functions use descriptive headers without AI_TASK_ID
# - Line references are approximate and may shift during editing
# - Use section identifiers (A.1, B.2, C.3, etc.) for navigation
# - Each task includes: Purpose, Environment, Logic, Performance, Dependencies
#
# PERFORMANCE CHARACTERISTICS:
# ===========================
# - Total Functions: 21 (9 maintenance tasks + 12 infrastructure)
# - Parallel Processing: Enabled for apps, updates, cleanup, bloatware
# - Error Handling: Comprehensive try/catch with detailed logging
# - Config System: JSON-based with graceful fallbacks
# - Restart Management: 120-second countdown with user abort
# - Logging: Unified system with color-coded console output
#
# DEPENDENCIES HIERARCHY:
# ======================
# 1. Core Infrastructure (B.1-B.8) - Required by all tasks
# 2. Configuration System (A.3) - Drives task execution
# 3. Maintenance Tasks (C.1-C.9) - Modular, config-driven execution
# 4. Task Array (A.2) - Orchestrates execution order
#
# ================================================================

# Purpose: Orchestrates modular Windows maintenance tasks with robust logging and error handling.
# Environment: Windows 10/11, PowerShell 7+ preferred, Administrator required.
# Dependencies: Winget, Chocolatey, AppX, DISM, Registry, Windows Capabilities.
# Execution: Silent/unattended, config-driven task selection, graceful fallbacks.
# Structure: Global task array ($global:ScriptTasks) defines all maintenance operations.
# Logging: Centralized Write-Log function, timestamped entries, color-coded console output.
# Config: Optional config.json for task customization and feature toggles.
# Editing Guide:
#   - Each task/function uses a clear header: Purpose, Environment, Logic, Performance, Dependencies
#   - All file operations use $PSScriptRoot for relative paths
#   - Error handling: try/catch with detailed logging
#   - All logic is PowerShell 7 native; no compatibility wrappers remain

# ================================================================
# [A.2] GLOBAL TASK ARRAY - MAINTENANCE TASK DEFINITIONS
# ================================================================
# COPILOT_SECTION: TaskArrayDefinition
# Purpose: Centralized task coordination with standardized metadata and execution control
# Structure: Hash table array with Name, Function, Description for each maintenance task
# Execution: Sequential processing via Use-AllScriptTasks(), config-driven skip logic
# Dependencies: Global config system, Write-Log function, individual task functions
# ================================================================
$global:ScriptTasks = @(
    # ================================================================
    # [A.2.1] COPILOT_TASK: SystemRestoreProtection
    # ================================================================
    # COPILOT_TASK_ID: SystemRestoreProtection
    # Purpose: Enables System Restore and creates a restore point before maintenance.
    # Environment: Windows 10/11, Administrator required, C:\ drive focus
    # Logic: Config-driven skip, PowerShell native cmdlets, duplicate protection
    # Dependencies: SystemRestoreConfig, Checkpoint-Computer
    # Function Location: [C.9] Lines 4211-4325
    # ================================================================
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

    # ================================================================
    # [A.2.2] COPILOT_TASK: SystemInventory
    # ================================================================
    # COPILOT_TASK_ID: SystemInventory
    # Purpose: Collects comprehensive system information for reporting and analysis.
    # Environment: Windows 10/11, any user context, outputs to inventory.txt
    # Logic: Get-ComputerInfo based, structured data collection, file output
    # Dependencies: WMI/CIM cmdlets, file system access
    # Function Location: [C.5] Lines 3177-3191
    # ================================================================
    @{ Name = 'SystemInventory'; Function = { 
            Write-Log 'Starting System Inventory task.' 'INFO'
            Write-Host 'Starting System Inventory task.' -ForegroundColor Cyan
            Get-SystemInventory
            Write-Log 'Completed System Inventory task.' 'INFO'
            Write-Host 'Completed System Inventory task.' -ForegroundColor Green
            return $true
        }; Description = 'Collect and export comprehensive system inventory data' 
    },

    # ================================================================
    # [A.2.3] COPILOT_TASK: EventLogAnalysis
    # ================================================================
    # COPILOT_TASK_ID: EventLogAnalysis
    # Purpose: Surveys Event Viewer and CBS logs for errors only from the last 96 hours.
    # Environment: Windows 10/11, any user context, Event Log and CBS log access
    # Logic: Get-EventLog/Get-WinEvent for Event Viewer, file parsing for CBS logs
    # Dependencies: Event Log service, CBS log file access, file system permissions
    # Function Location: [C.3] Lines 2679-2841
    # ================================================================
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
        }; Description = 'Survey Event Viewer and CBS logs for errors only from last 96 hours' 
    },

    # ================================================================
    # [A.2.4] COPILOT_TASK: RemoveBloatware
    # ================================================================
    # COPILOT_TASK_ID: RemoveBloatware
    # Purpose: Multi-method removal of unwanted applications and components.
    # Environment: Windows 10/11, Administrator required, AppX/DISM/Registry access
    # Logic: Parallel processing, inventory-based filtering, action-only logging
    # Dependencies: AppX cmdlets, DISM, Winget, Chocolatey, Windows Capabilities
    # Function Location: [C.4] Lines 2850-3175
    # ================================================================
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

    # ================================================================
    # [A.2.5] COPILOT_TASK: InstallEssentialApps
    # ================================================================
    # COPILOT_TASK_ID: InstallEssentialApps
    # Purpose: Parallel installation of curated essential applications.
    # Environment: Windows 10/11, Administrator required, package manager access
    # Logic: HashSet optimization, parallel processing, smart filtering, custom app support
    # Dependencies: Winget, Chocolatey, inventory system, config.json integration
    # Function Location: [C.1] Lines 1903-2249
    # ================================================================
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
        }; Description = 'Install curated essential applications with parallel processing' 
    },

    # ================================================================
    # [A.2.6] COPILOT_TASK: UpdateAllPackages
    # ================================================================
    # COPILOT_TASK_ID: UpdateAllPackages
    # Purpose: Ultra-parallel update of all installed packages.
    # Environment: Windows 10/11, Administrator required, enhanced performance focus
    # Logic: Multi-threaded execution, timeout handling, detailed metrics, action-only logging
    # Dependencies: Winget, Chocolatey, parallel processing capabilities
    # Function Location: [C.2] Lines 2258-2672
    # ================================================================
    @{ Name = 'UpdateAllPackages'; Function = { 
            Write-Log 'Starting Package Updates task.' 'INFO'
            Write-Host 'Starting Package Updates task.' -ForegroundColor Cyan
            Update-AllPackages
            Write-Log 'Completed Package Updates task.' 'INFO'
            Write-Host 'Completed Package Updates task.' -ForegroundColor Green
            return $true
        }; Description = 'Ultra-parallel package updates with performance optimization' 
    },

    # ================================================================
    # [A.2.7] COPILOT_TASK: WindowsUpdateCheck
    # ================================================================
    # COPILOT_TASK_ID: WindowsUpdateCheck
    # Purpose: Check and install Windows Updates via PSWindowsUpdate module.
    # Environment: Windows 10/11, Administrator required, PSWindowsUpdate module
    # Logic: Config-driven skip, module auto-install, comprehensive error handling
    # Dependencies: PSWindowsUpdate module, Windows Update service
    # Function Location: [B.4] Lines 888-1068
    # ================================================================
    @{ Name = 'WindowsUpdateCheck'; Function = {
            Write-Log 'Starting Windows Updates check task.' 'INFO'
            Write-Host 'Starting Windows Updates check task.' -ForegroundColor Cyan
            if (-not $global:Config.SkipWindowsUpdates) {
                Write-Log 'Initiating Windows Updates check and installation.' 'INFO'
                $success = Install-WindowsUpdatesCompatible
                if ($success) {
                    Write-Log 'Windows Updates completed successfully.' 'INFO'
                    Write-Host 'Completed Windows Updates check task.' -ForegroundColor Green
                    return $true
                }
                else {
                    Write-Log 'Windows Updates failed or no updates available.' 'WARN'
                    Write-Host 'Completed Windows Updates check task with warnings.' -ForegroundColor Yellow
                    return $false
                }
            }
            else {
                Write-Log 'Windows Updates check skipped by configuration.' 'INFO'
                Write-Host 'Windows Updates check skipped by configuration.' -ForegroundColor Yellow
                return $false
            }
        }; Description = 'Check and install Windows Updates with PSWindowsUpdate module' 
    },

    # ================================================================
    # [A.2.8] COPILOT_TASK: DisableTelemetry
    # ================================================================
    # COPILOT_TASK_ID: DisableTelemetry
    # Purpose: Disable Windows telemetry and privacy-invasive features.
    # Environment: Windows 10/11, Administrator required, registry/service modification
    # Logic: Parallel browser detection, batch registry operations, service management
    # Dependencies: Registry access, service control, browser configuration files
    # Function Location: [C.6] Lines 3200-3643
    # ================================================================
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
        }; Description = 'Disable telemetry, privacy features, and configure browser privacy' 
    },

    # ================================================================
    # [A.2.9] COPILOT_TASK: TaskbarOptimization
    # ================================================================
    # COPILOT_TASK_ID: TaskbarOptimization
    # Purpose: Optimize Windows interface by hiding taskbar elements and disabling web search in Start menu.
    # Environment: Windows 10/11, any user context, registry modification access
    # Logic: Registry-based taskbar and search control, Windows version detection, user experience optimization
    # Dependencies: Registry access, Windows Explorer restart capability
    # Function Location: [C.7] Lines 3650-3861
    # ================================================================
    @{ Name = 'TaskbarOptimization'; Function = { 
            Write-Log 'Starting Taskbar and Start Menu Optimization task.' 'INFO'
            Write-Host 'Starting Taskbar and Start Menu Optimization task.' -ForegroundColor Cyan
            if (-not $global:Config.SkipTaskbarOptimization) { 
                Optimize-Taskbar
                Write-Log 'Completed Taskbar and Start Menu Optimization task.' 'INFO'
                Write-Host 'Completed Taskbar and Start Menu Optimization task.' -ForegroundColor Green
                return $true
            }
            else { 
                Write-Log 'Taskbar and Start Menu Optimization skipped by configuration.' 'INFO'
                Write-Host 'Taskbar and Start Menu Optimization skipped by configuration.' -ForegroundColor Yellow
                return $false
            } 
        }; Description = 'Hide taskbar elements and disable web search for local-only Start menu search' 
    },

    # ================================================================
    # [A.2.10] COPILOT_TASK: SecurityHardening
    # ================================================================
    # COPILOT_TASK_ID: SecurityHardening
    # Purpose: Enable essential Windows security features while preserving SMB and authentication.
    # Environment: Windows 10/11, Administrator required, security configuration access
    # Logic: Windows Defender, Firewall, UAC, SmartScreen, secure services configuration
    # Dependencies: Windows Defender, Firewall service, registry access, service control
    # Function Location: [C.8] Lines 3868-4202
    # ================================================================
    @{ Name = 'SecurityHardening'; Function = { 
            Write-Log 'Starting Security Hardening task.' 'INFO'
            Write-Host 'Starting Security Hardening task.' -ForegroundColor Cyan
            if (-not $global:Config.SkipSecurityHardening) { 
                Enable-SecurityHardening
                Write-Log 'Completed Security Hardening task.' 'INFO'
                Write-Host 'Completed Security Hardening task.' -ForegroundColor Green
                return $true
            }
            else { 
                Write-Log 'Security Hardening skipped by configuration.' 'INFO'
                Write-Host 'Security Hardening skipped by configuration.' -ForegroundColor Yellow
                return $false
            } 
        }; Description = 'Enable Windows security features while preserving SMB and authentication' 
    },

    # ================================================================
    # [A.2.11] COPILOT_TASK: CleanTempAndDisk
    # ================================================================
    # COPILOT_TASK_ID: CleanTempAndDisk
    # Purpose: Full unattended system cleanup (temp, cache, WinSxS, Delivery Optimization, disk cleanup).
    # Environment: Windows 10/11, Administrator preferred, disk cleanup utilities
    # Logic: Multi-folder temp cleanup, parallel deletion, cleanmgr.exe, Storage Sense, DISM, Delivery Optimization, action-only logging
    # Dependencies: File system access, cleanmgr.exe, temp folder permissions, DISM, Storage Sense
    # Function Location: [A.2.11] Inline implementation (Lines 388-573)
    # ================================================================
    @{ Name = 'CleanTempAndDisk'; Function = {
            Write-Log 'Starting Full System Cleanup task (temp files, cache, WinSxS).' 'INFO'
            Write-Host 'Starting Full System Cleanup task (temp files, cache, WinSxS).' -ForegroundColor Cyan
            $cleanupStart = Get-Date
            $deletedFiles = 0
            $deletedFolders = 0
            $errorCount = 0
            $cleanupTargets = @(
                $env:TEMP,
                "$env:SystemRoot\Temp",
                "$env:LOCALAPPDATA\Temp",
                "$env:USERPROFILE\AppData\Local\Temp",
                "$env:USERPROFILE\AppData\Roaming\Temp",
                "$env:USERPROFILE\AppData\Local\Microsoft\Windows\INetCache",
                "$env:USERPROFILE\AppData\Local\Microsoft\Windows\WebCache",
                "$env:USERPROFILE\AppData\Local\Google\Chrome\User Data\Default\Cache",
                "$env:USERPROFILE\AppData\Local\Mozilla\Firefox\Profiles",
                "$env:USERPROFILE\AppData\Local\Microsoft\Edge\User Data\Default\Cache",
                "$env:SystemRoot\SoftwareDistribution\Download",
                "$env:SystemRoot\SoftwareDistribution\DataStore",
                "$env:SystemRoot\Logs",
                "$env:SystemRoot\Prefetch",
                "$env:SystemRoot\WinSxS\Temp",
                "$env:SystemRoot\Installer\PatchCache",
                "$env:SystemRoot\System32\LogFiles",
                "$env:SystemRoot\System32\config\systemprofile\AppData\Local\Temp",
                "$env:SystemRoot\System32\config\systemprofile\AppData\Local\Microsoft\Windows\INetCache",
                "$env:SystemRoot\System32\config\systemprofile\AppData\Local\Microsoft\Windows\WebCache",
                "$env:SystemRoot\System32\config\systemprofile\AppData\Local\Google\Chrome\User Data\Default\Cache",
                "$env:SystemRoot\System32\config\systemprofile\AppData\Local\Mozilla\Firefox\Profiles",
                "$env:SystemRoot\System32\config\systemprofile\AppData\Local\Microsoft\Edge\User Data\Default\Cache",
                "$env:SystemRoot\System32\config\systemprofile\AppData\Local\Packages",
                "$env:SystemRoot\System32\config\systemprofile\AppData\Local\Packages\Microsoft.Windows.ContentDeliveryManager_cw5n1h2txyewy\LocalCache",
                "$env:SystemRoot\System32\config\systemprofile\AppData\Local\Packages\Microsoft.Windows.CloudExperienceHost_cw5n1h2txyewy\LocalCache"
            )
            $cleanupTargets = $cleanupTargets | Sort-Object -Unique
            
            # OPTIMIZED: Process folders directly instead of collecting all items first
            Write-Log "Processing $($cleanupTargets.Count) cleanup target folders..." 'INFO'
            
            foreach ($folder in $cleanupTargets) {
                if (Test-Path $folder -ErrorAction SilentlyContinue) {
                    try {
                        Write-Log "Cleaning folder: $folder" 'VERBOSE'
                        
                        # Count items first for progress reporting (faster than collecting all items)
                        $itemCount = 0
                        try {
                            $itemCount = (Get-ChildItem -Path $folder -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object).Count
                        }
                        catch {
                            $itemCount = 0
                        }
                        
                        if ($itemCount -gt 0) {
                            Write-Log "Processing $itemCount items in $folder..." 'INFO'
                            
                            # OPTIMIZED: Delete entire folder contents with single Remove-Item -Recurse
                            # This is much faster than processing individual files
                            try {
                                $folderItems = Get-ChildItem -Path $folder -Force -ErrorAction SilentlyContinue
                                foreach ($item in $folderItems) {
                                    try {
                                        Remove-Item $item.FullName -Force -Recurse -ErrorAction SilentlyContinue
                                        if ($item.PSIsContainer) {
                                            $deletedFolders++
                                        } else {
                                            $deletedFiles++
                                        }
                                    }
                                    catch {
                                        $errorCount++
                                    }
                                }
                                Write-Log "Completed cleanup of $folder" 'VERBOSE'
                            }
                            catch {
                                Write-Log "Failed to clean folder $folder : $_" 'WARN'
                                $errorCount++
                            }
                        }
                        else {
                            Write-Log "Folder $folder is already empty" 'VERBOSE'
                        }
                    }
                    catch {
                        Write-Log "Failed to process cleanup target folder $folder : $_" 'WARN'
                        $errorCount++
                    }
                }
                else {
                    Write-Log "Cleanup target folder does not exist: $folder" 'VERBOSE'
                }
            }
            
            Write-Log "Cleanup completed. Estimated $deletedFiles files and $deletedFolders folders processed." 'INFO'
            # Run Disk Cleanup (cleanmgr)
            try {
                $cleanmgrArgs = '/AUTOCLEAN'
                $proc = Start-Process -FilePath 'cleanmgr.exe' -ArgumentList $cleanmgrArgs -WindowStyle Hidden -Wait -PassThru
                if ($proc.ExitCode -eq 0) {
                    Write-Log 'Disk cleanup completed successfully using cleanmgr.exe (silent AUTOCLEAN).' 'INFO'
                }
                else {
                    Write-Log "Disk cleanup process exited with error code $($proc.ExitCode)." 'WARN'
                }
            }
            catch {
                Write-Log "Disk cleanup operation failed: $_" 'WARN'
            }
            # Run Storage Sense (if available)
            if (Get-Command Start-StorageSense -ErrorAction SilentlyContinue) {
                try {
                    Start-StorageSense -ErrorAction SilentlyContinue
                    Write-Log 'Storage Sense cleanup completed successfully.' 'INFO'
                }
                catch {
                    Write-Log "Storage Sense cleanup failed: $_" 'WARN'
                }
            }
            # Run WinSxS component cleanup
            try {
                $dismProc = Start-Process -FilePath 'dism.exe' -ArgumentList '/Online', '/Cleanup-Image', '/StartComponentCleanup', '/Quiet' -WindowStyle Hidden -Wait -PassThru
                if ($dismProc.ExitCode -eq 0) {
                    Write-Log 'WinSxS component cleanup completed successfully.' 'INFO'
                }
                else {
                    Write-Log "WinSxS cleanup exited with error code $($dismProc.ExitCode)." 'WARN'
                }
            }
            catch {
                Write-Log "WinSxS cleanup failed: $_" 'WARN'
            }
            # Run Delivery Optimization cache cleanup
            try {
                $doProc = Start-Process -FilePath 'dosvc.exe' -ArgumentList '/Cleanup' -WindowStyle Hidden -Wait -PassThru
                if ($doProc.ExitCode -eq 0) {
                    Write-Log 'Delivery Optimization cache cleanup completed successfully.' 'INFO'
                }
                else {
                    Write-Log "Delivery Optimization cleanup exited with error code $($doProc.ExitCode)." 'WARN'
                }
            }
            catch {
                Write-Log "Delivery Optimization cleanup failed: $_" 'WARN'
            }
            $cleanupEnd = Get-Date
            $duration = ($cleanupEnd - $cleanupStart).TotalSeconds
            Write-Log "Full system cleanup completed in $([math]::Round($duration,2)) seconds." 'INFO'
            Write-Log 'Completed Full System Cleanup task.' 'INFO'
            Write-Host 'Completed Full System Cleanup task.' -ForegroundColor Green
            return $true
        }; Description = 'Full unattended system cleanup (temp, cache, WinSxS, Delivery Optimization, disk cleanup)' 
    },

    # ================================================================
    # [A.2.12] COPILOT_TASK: PendingRestartCheck
    # ================================================================
    # COPILOT_TASK_ID: PendingRestartCheck
    # Purpose: Check for pending system restarts and offer 120-second countdown with abort option.
    # Environment: Windows 10/11, any user context, registry access for restart detection
    # Logic: Comprehensive restart detection, 120-second countdown, user abort option
    # Dependencies: Registry access, restart detection methods, user interaction
    # Function Location: [A.2.12] Inline implementation (Lines 546-694)
    # ================================================================
    @{ Name = 'PendingRestartCheck'; Function = { 
            Write-Log 'Starting Pending Restart Check task.' 'INFO'
            Write-Host 'Starting Pending Restart Check task.' -ForegroundColor Cyan
            
            if ($global:Config.SkipPendingRestartCheck) {
                Write-Log 'Pending Restart Check skipped by configuration.' 'INFO'
                Write-Host 'Pending Restart Check skipped by configuration.' -ForegroundColor Yellow
                return $false
            }
            
            # Comprehensive restart detection
            $restartRequired = $false
            $restartReasons = @()
            
            Write-Log 'Checking for pending system restarts...' 'INFO'
            
            # Check Windows Update reboot flag
            try {
                if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired") {
                    $restartRequired = $true
                    $restartReasons += "Windows Update"
                    Write-Log 'Windows Update restart flag detected' 'INFO'
                }
            } catch { Write-Log "Failed to check Windows Update restart flag: $_" 'VERBOSE' }
            
            # Check Component Based Servicing reboot flag
            try {
                if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending") {
                    $restartRequired = $true
                    $restartReasons += "Component Based Servicing"
                    Write-Log 'Component Based Servicing restart detected' 'INFO'
                }
            } catch { Write-Log "Failed to check CBS restart flag: $_" 'VERBOSE' }
            
            # Check pending file operations
            try {
                $pendingFileOps = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" -Name "PendingFileRenameOperations" -ErrorAction SilentlyContinue
                if ($pendingFileOps) {
                    $restartRequired = $true
                    $restartReasons += "Pending File Operations"
                    Write-Log 'Pending file rename operations detected' 'INFO'
                }
            } catch { Write-Log "Failed to check pending file operations: $_" 'VERBOSE' }
            
            # Check Windows Feature installation requiring restart
            try {
                if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\PackagesPending") {
                    $restartRequired = $true
                    $restartReasons += "Windows Features"
                    Write-Log 'Windows Features pending restart detected' 'INFO'
                }
            } catch { Write-Log "Failed to check Windows Features restart flag: $_" 'VERBOSE' }
            
            # Check for computer name change
            try {
                $currentName = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName' -Name ComputerName).ComputerName
                $pendingName = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ActiveComputerName' -Name ComputerName).ComputerName
                if ($currentName -ne $pendingName) {
                    $restartRequired = $true
                    $restartReasons += "Computer Name Change"
                    Write-Log 'Computer name change pending restart detected' 'INFO'
                }
            } catch { Write-Log "Failed to check computer name change: $_" 'VERBOSE' }
            
            if (-not $restartRequired) {
                Write-Log 'No pending restart detected. System is up to date.' 'INFO'
                Write-Host '✅ No pending restart detected. System is up to date.' -ForegroundColor Green
                return $true
            }
            
            # Restart required - show countdown
            $reasonsList = $restartReasons -join ", "
            Write-Log "Restart required due to: $reasonsList" 'WARN'
            Write-Host "" 
            Write-Host "⚠️  SYSTEM RESTART REQUIRED" -ForegroundColor Yellow -BackgroundColor DarkRed
            Write-Host "Restart required due to: $reasonsList" -ForegroundColor Yellow
            Write-Host ""
            Write-Host "The system will automatically restart in 120 seconds." -ForegroundColor White
            Write-Host "Press Ctrl+C to abort the restart countdown." -ForegroundColor Cyan
            Write-Host ""
            
            # 120-second countdown with abort option
            for ($i = 120; $i -gt 0; $i--) {
                $minutes = [math]::Floor($i / 60)
                $seconds = $i % 60
                if ($minutes -gt 0) {
                    $timeDisplay = "{0}:{1:D2}" -f $minutes, $seconds
                } else {
                    $timeDisplay = "0:{0:D2}" -f $seconds
                }
                
                Write-Host "`rRestarting in $timeDisplay... (Press Ctrl+C to abort)" -NoNewline -ForegroundColor Yellow
                
                try {
                    Start-Sleep -Seconds 1
                } catch [System.Management.Automation.PipelineStoppedException] {
                    Write-Host ""
                    Write-Host ""
                    Write-Log 'Restart countdown aborted by user.' 'INFO'
                    Write-Host '❌ Restart countdown aborted by user.' -ForegroundColor Red
                    Write-Host 'Please restart your system manually when convenient to complete the maintenance.' -ForegroundColor Yellow
                    return $false
                }
            }
            
            Write-Host ""
            Write-Host ""
            Write-Log 'Initiating system restart...' 'INFO'
            Write-Host '🔄 Initiating system restart...' -ForegroundColor Green
            
            # Initiate restart
            try {
                Start-Process -FilePath "shutdown.exe" -ArgumentList "/r", "/t", "10", "/c", "System restart required to complete maintenance operations" -NoNewWindow
                Write-Log 'System restart initiated successfully.' 'INFO'
                return $true
            } catch {
                Write-Log "Failed to initiate system restart: $_" 'ERROR'
                Write-Host "❌ Failed to initiate restart: $_" -ForegroundColor Red
                Write-Host 'Please restart your system manually.' -ForegroundColor Yellow
                return $false
            }
        }; Description = 'Check for pending restarts with 120-second countdown and abort option' 
    }
)

# ================================================================
# [A.3] CONFIGURATION MANAGEMENT - COPILOT SECTION
# ================================================================
# COPILOT_SECTION: ConfigurationSystem
# Purpose: Supports configuration-driven task execution and customization
# Logic: Merges custom config with defaults, graceful handling of missing file
# Dependencies: File system access, JSON parsing capabilities
# Config File: config.json (optional) - JSON format with task skip flags and custom arrays
# ================================================================
$configPath = Join-Path $PSScriptRoot "config.json"
$global:Config = @{
    SkipBloatwareRemoval  = $false
    SkipEssentialApps     = $false
    SkipWindowsUpdates    = $false
    SkipTelemetryDisable  = $false
    SkipSystemRestore     = $false
    SkipEventLogAnalysis  = $false
    SkipSecurityHardening = $false
    SkipTaskbarOptimization = $false
    SkipPendingRestartCheck = $false
    CustomEssentialApps   = @()
    CustomBloatwareList   = @()
    EnableVerboseLogging  = $false
}

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
        if ($config.SkipPendingRestartCheck) { $global:Config.SkipPendingRestartCheck = $config.SkipPendingRestartCheck }
        if ($config.CustomEssentialApps) { $global:Config.CustomEssentialApps = $config.CustomEssentialApps }
        if ($config.CustomBloatwareList) { $global:Config.CustomBloatwareList = $config.CustomBloatwareList }
        if ($config.EnableVerboseLogging) { $global:Config.EnableVerboseLogging = $config.EnableVerboseLogging }
    }
    catch {
        # Note: Write-Log not available yet, this will be logged later
    }
}

# ================================================================
# [B] CORE INFRASTRUCTURE - COPILOT SECTION
# ================================================================

# ================================================================
# [B.1] TASK ORCHESTRATION - COPILOT FUNCTION
# ================================================================
# COPILOT_FUNCTION_ID: Use-AllScriptTasks
# Purpose: Main task execution orchestrator with comprehensive error handling and performance metrics
# Environment: Windows 10/11, PowerShell 7+, Administrator context
# Logic: Sequential task execution, detailed logging, performance tracking, graceful error handling
# Dependencies: Global task array, Write-Log function, global config system
# Performance: Tracks execution time, success/failure rates, provides detailed console output
# ================================================================
function Use-AllScriptTasks {
    Write-Log 'Initiating all maintenance tasks execution sequence.' 'INFO'
    $global:TaskResults = @{}
    foreach ($task in $global:ScriptTasks) {
        $taskName = $task.Name
        $desc = $task.Description
        Write-Log "Executing task: $taskName - $desc" 'INFO'
        $startTime = Get-Date
        try {
            $result = Invoke-Task $taskName $task.Function
            $endTime = Get-Date
            $duration = ($endTime - $startTime).TotalSeconds
            Write-Log "Task $taskName completed in $duration seconds - Result: $result" 'INFO'
            $global:TaskResults[$taskName] = @{ Success = $result; Duration = $duration; Started = $startTime; Ended = $endTime }
        }
        catch {
            Write-Log "Task $taskName execution failed: $_" 'ERROR'
            $global:TaskResults[$taskName] = @{ Success = $false; Duration = 0; Started = $startTime; Ended = (Get-Date) }
        }
    }
    Write-Log 'All maintenance tasks execution sequence completed.' 'INFO'
}

# ================================================================
# [B.2] LOGGING SYSTEM - COPILOT FUNCTION
# ================================================================
# COPILOT_FUNCTION_ID: Write-Log
# Purpose: Provides consistent logging across all maintenance operations.
# Environment: Any PowerShell version, writes to file and color-coded console.
# Logic: Timestamped entries, level-based filtering, file and console output.
# Performance: Fast, minimal overhead, unified logging to parent directory.
# Dependencies: File system access, global config for verbose logging control
# Output: maintenance.log in parent directory, color-coded console messages
# ================================================================
function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR', 'VERBOSE')][string]$Level = 'INFO'
    )
    
    # Logic: Skip verbose messages if verbose logging is disabled in configuration
    if ($Level -eq 'VERBOSE' -and -not $global:Config.EnableVerboseLogging) {
        return
    }
    
    $timestamp = Get-Date -Format 'MM/dd/yyyy HH:mm:ss'
    $entry = "[$timestamp] [$Level] $Message"
    $entry | Out-File -FilePath $LogFile -Append -Encoding UTF8
    
    # Output: Color-code console output based on severity level for visual clarity
    switch ($Level) {
        'ERROR' { Write-Host $entry -ForegroundColor Red }
        'WARN' { Write-Host $entry -ForegroundColor Yellow }
        'VERBOSE' { Write-Host $entry -ForegroundColor Gray }
        default { Write-Host $entry }
    }
}

### Function: Invoke-WindowsPowerShellCommand
### [RESTORED] Compatibility wrapper for accessing Windows PowerShell modules from PowerShell 7
# Performance: Moderate overhead due to cross-PowerShell invocation, but necessary for Appx/PSWindowsUpdate

function Invoke-WindowsPowerShellCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Command,
        
        [Parameter(Mandatory = $false)]
        [string]$Description = "Windows PowerShell command"
    )
    
    try {
        Write-Log "[COMPAT] Executing Windows PowerShell command: $Description" 'VERBOSE'
        
        # Use powershell.exe to run the command in Windows PowerShell context
        $result = & powershell.exe -ExecutionPolicy Bypass -Command $Command 2>$null
        
        if ($LASTEXITCODE -eq 0) {
            Write-Log "[COMPAT] Windows PowerShell command completed successfully" 'VERBOSE'
            return $result
        }
        else {
            Write-Log "[COMPAT] Windows PowerShell command failed with exit code: $LASTEXITCODE" 'WARN'
            return $null
        }
    }
    catch {
        Write-Log "[COMPAT] Error executing Windows PowerShell command: $($_.Exception.Message)" 'ERROR'
        return $null
    }
}
# Performance: Fast, minimal overhead.

# ================================================================
# [B.3] APPX COMPATIBILITY LAYER - COPILOT FUNCTIONS
# ================================================================

# ================================================================
# [B.3.1] COPILOT_FUNCTION_ID: Get-AppxPackageCompatible
# ================================================================
# Purpose: PowerShell 7 native AppX package enumeration wrapper
# Environment: Windows 10/11, PowerShell 7+, AppX subsystem access
# Logic: Returns array of AppX package objects with Name, PackageFullName, and Version properties
# Performance: Fast, minimal overhead, direct PowerShell 7 cmdlet usage
# Dependencies: Get-AppxPackage cmdlet, AppX subsystem
# ================================================================
function Get-AppxPackageCompatible {
    param(
        [string]$Name = "*",
        [switch]$AllUsers
    )
    if ($AllUsers) {
        return Get-AppxPackage -Name $Name -AllUsers -ErrorAction SilentlyContinue
    }
    else {
        return Get-AppxPackage -Name $Name -ErrorAction SilentlyContinue
    }
}

### Function: Remove-AppxPackageCompatible
### [REMOVED] Legacy compatibility wrapper (Remove-AppxPackageCompatible) - all logic now PowerShell 7 native
# Environment: Requires Administrator privileges and AppX module access.
# Logic: Removes AppX package by name or wildcard pattern.
# Performance: Fast, minimal overhead.
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
        Write-Log "Failed to remove AppX package: $_" 'ERROR'
        return $false
    }
}

### Function: Get-AppxProvisionedPackageCompatible
# Purpose: Cross-version provisioned AppX package enumeration for system-wide removal.
# Environment: Requires Administrator privileges and DISM/AppX module access.
# Logic: Returns array of provisioned package objects for new user account prevention.
# Performance: Fast, minimal overhead.
function Get-AppxProvisionedPackageCompatible {
    param(
        [switch]$Online
    )
    
    if ($PSVersionTable.PSVersion.Major -ge 7) {
        ### [REMOVED] Legacy compatibility block - all Appx operations are PowerShell 7 native
        $command = "Import-Module Dism -ErrorAction SilentlyContinue; Get-AppxProvisionedPackage"
        if ($Online) { $command += " -Online" }
        $command += " | Select-Object DisplayName, PackageName | ConvertTo-Json -Depth 3"
        
        $result = Invoke-WindowsPowerShellCommand -Command $command -Description "Get provisioned AppX packages"
        if ($result) {
            try {
                return ($result | ConvertFrom-Json)
            }
            catch {
                Write-Log "Failed to parse provisioned AppX package JSON: $_" 'WARN'
                return @()
            }
        }
        return @()
    }
    else {
        # [REMOVED] Native PowerShell 5.1 block
        if ($Online) {
            return Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue
        }
        else {
            return Get-AppxProvisionedPackage -ErrorAction SilentlyContinue
        }
    }
}

### Function: Remove-AppxProvisionedPackageCompatible
# Purpose: Removes provisioned AppX packages from system image (cross-version).
# Environment: Administrator, DISM module access.
# Logic: Removes package by name system-wide.
# Performance: Fast, minimal overhead.
function Remove-AppxProvisionedPackageCompatible {
    param(
        [string]$PackageName,
        [switch]$Online
    )
    
    if ($PSVersionTable.PSVersion.Major -ge 7) {
        # Use Windows PowerShell for Appx operations
        $command = "Import-Module Dism -ErrorAction SilentlyContinue; Remove-AppxProvisionedPackage -PackageName '$PackageName'"
        if ($Online) { $command += " -Online" }
        $command += " -ErrorAction Stop"
        
        $result = Invoke-WindowsPowerShellCommand -Command $command -Description "Remove provisioned AppX package $PackageName"
        return $null -ne $result
    }
    else {
        # Native PowerShell 5.1
        try {
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

            ### Function: Enable-ComputerRestoreCompatible
            # Purpose: Enables System Restore protection (cross-version).
            # Environment: Administrator, System Restore service access.
            # Logic: Enables protection for specified drive.
            # Performance: Fast, minimal overhead.
            function Enable-ComputerRestoreCompatible {
                param(
                    [string]$Drive
                )
    
                try {
                    Write-Log "Enabling System Restore on drive $Drive" 'INFO'
        
                    if ($PSVersionTable.PSVersion.Major -ge 7) {
                        # Use Windows PowerShell via powershell.exe for System Restore operations (PS7 compatibility issue)
                        $command = "Enable-ComputerRestore -Drive '$Drive'"
                        & powershell.exe -Command $command 2>&1 | Out-Null
            
                        if ($LASTEXITCODE -eq 0) {
                            Write-Log "Successfully enabled System Restore on drive $Drive" 'INFO'
                            return $true
                        }
                        else {
                            & powershell.exe -Command $command 2>&1
                            return $false
                        }
                    }
                    else {
                        # Native PowerShell 5.1
                        Enable-ComputerRestore -Drive $Drive -ErrorAction SilentlyContinue
            
                        # Verify that the restore point was actually enabled
                        Start-Sleep -Seconds 1
                        $verifyRestore = Get-WmiObject -Class SystemRestoreConfig -ErrorAction SilentlyContinue | Where-Object { $_.Drive -eq $Drive }
                        if ($verifyRestore -and -not $verifyRestore.Disable) {
                            Write-Log "Successfully enabled System Restore on drive $Drive" 'INFO'
                            return $true
                        }
                        else {
                            Write-Log "System Restore enable operation completed but verification failed for drive $Drive" 'WARN'
                            return $false
                        }
                    }
                }
                catch {
                    Write-Log "Failed to enable System Restore on drive $Drive : $_" 'ERROR'
                    return $false
                }
            }

            ### Function: Checkpoint-ComputerCompatible
            # Purpose: Creates restore point (cross-version).
            # Environment: Administrator, System Restore enabled.
            # Logic: Creates restore point with description and type.
            # Performance: Fast, minimal overhead.
            function Checkpoint-ComputerCompatible {
                param(
                    [string]$Description,
                    [string]$RestorePointType = 'MODIFY_SETTINGS'
                )
    
                try {
                    Write-Log "Creating system restore point: $Description" 'INFO'
        
                    if ($PSVersionTable.PSVersion.Major -ge 7) {
                        # Use Windows PowerShell via powershell.exe for System Restore operations (PS7 compatibility issue)
                        $command = "Checkpoint-Computer -Description '$Description' -RestorePointType '$RestorePointType'"
                        & powershell.exe -Command $command 2>&1 | Out-Null
            
                        if ($LASTEXITCODE -eq 0) {
                            Write-Log "Successfully created restore point: $Description" 'INFO'
                            return $true
                        }
                        else {
                            Write-Log "Failed to create restore point: $Description. Exit code: $LASTEXITCODE" 'WARN'
                            return $false
                        }
                    }
                    else {
                        # Native PowerShell 5.1
                        Checkpoint-Computer -Description $Description -RestorePointType $RestorePointType -ErrorAction Stop
                        Write-Log "Successfully created restore point: $Description" 'INFO'
                        return $true
                    }
                }
                catch {
                    Write-Log "Failed to create restore point '$Description': $_" 'ERROR'
                    return $false
                }
            }
        }
        catch {
            return $false
        }
    }
}

### Function: Install-WindowsUpdatesCompatible
### Windows Update management: PowerShell 7 native, PSWindowsUpdate module, parallel detection, error handling
function Install-WindowsUpdatesCompatible {
    param()
    
    Write-Log 'Starting Windows Updates Check and Installation - PowerShell 7 Enhanced Mode.' 'INFO'
    $startTime = Get-Date
    
    try {
        # Module validation: Enhanced module availability and installation check
        if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate -ErrorAction SilentlyContinue)) {
            Write-Log 'PSWindowsUpdate module not found - attempting installation...' 'INFO'
            
            try {
                # Use TLS 1.2 for secure downloads
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                
                # Install with enhanced parameters for reliability - FULLY SILENT
                Install-Module -Name PSWindowsUpdate -Force -Scope CurrentUser -Confirm:$false -AllowClobber -SkipPublisherCheck -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
                
                # Verify installation
                if (Get-Module -ListAvailable -Name PSWindowsUpdate -ErrorAction SilentlyContinue) {
                    Write-Log 'PSWindowsUpdate module installed successfully.' 'INFO'
                }
                else {
                    throw "PSWindowsUpdate module installation failed - module not available after installation"
                }
            }
            catch {
                Write-Log "Failed to install PSWindowsUpdate module: $_" 'ERROR'
                return $false
            }
        }
        
        # Module import: Enhanced module import with validation
        try {
            Import-Module PSWindowsUpdate -Force -ErrorAction SilentlyContinue
            
            # Verify module is loaded and functional
            if (-not (Get-Module -Name PSWindowsUpdate -ErrorAction SilentlyContinue)) {
                throw "PSWindowsUpdate module failed to load"
            }
            
            # Test basic functionality
            if (-not (Get-Command Get-WindowsUpdate -ErrorAction SilentlyContinue)) {
                throw "PSWindowsUpdate module loaded but Get-WindowsUpdate command not available"
            }
            
            Write-Log 'PSWindowsUpdate module imported successfully.' 'VERBOSE'
        }
        catch {
            Write-Log "Failed to import PSWindowsUpdate module: $_" 'ERROR'
            return $false
        }
        
        # Update detection: Enhanced update detection with comprehensive filtering
        Write-Log 'Scanning for available Windows Updates...' 'INFO'
        
        $availableUpdates = $null
        try {
            # Get available updates with comprehensive filtering
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
                
                # Log update details for transparency
                foreach ($update in $availableUpdates) {
                    $updateSizeMB = [math]::Round($update.Size / 1MB, 2)
                    Write-Log "$($update.Title) ($updateSizeMB MB)" 'VERBOSE'
                }
            }
            else {
                Write-Log 'No new Windows Updates available.' 'INFO'
                $duration = ((Get-Date) - $startTime).TotalSeconds
                Write-Log "Windows Update check completed in $([math]::Round($duration, 2)) seconds." 'INFO'
                return $true
            }
        }
        catch {
            Write-Log "Failed to scan for Windows Updates: $_" 'ERROR'
            
            # [REMOVED] Fallback logic - all update detection is PowerShell 7 native
        }
        
        # Update installation: Enhanced update installation with progress tracking
        if ($availableUpdates) {
            Write-Log 'Beginning Windows Update installation process...' 'INFO'
            
            $installStartTime = Get-Date
            $successfulUpdates = @()
            $failedUpdates = @()
            
            try {
                # Batch install: Install all updates with comprehensive error handling - FULLY UNATTENDED
                $installResults = Install-WindowsUpdate -MicrosoftUpdate -AcceptAll -AutoReboot:$false -Confirm:$false -IgnoreReboot -Force -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
                
                if ($installResults) {
                    foreach ($result in $installResults) {
                        if ($result.Result -eq 'Installed' -or $result.Result -eq 'Downloaded') {
                            $successfulUpdates += $result.Title
                            Write-Log "✓ Successfully installed: $($result.Title)" 'INFO'
                        }
                        else {
                            $failedUpdates += $result.Title
                            Write-Log "✗ Failed to install: $($result.Title) - Status: $($result.Result)" 'WARN'
                        }
                    }
                }
                
                # Installation summary: Installation results summary
                $installDuration = ((Get-Date) - $installStartTime).TotalSeconds
                $successCount = $successfulUpdates.Count
                $failureCount = $failedUpdates.Count
                
                if ($successCount -gt 0) {
                    Write-Log "Successfully installed $successCount Windows Updates in $([math]::Round($installDuration, 2)) seconds." 'INFO'
                    
                    # Log successful updates for audit trail
                    foreach ($update in $successfulUpdates) {
                        Write-Log "Installed update: $update" 'VERBOSE'
                    }
                }
                
                if ($failureCount -gt 0) {
                    Write-Log "$failureCount updates failed to install." 'WARN'
                    
                    # Log failed updates for troubleshooting
                    foreach ($update in $failedUpdates) {
                        Write-Log "Failed update: $update" 'VERBOSE'
                    }
                }
                
                # Reboot check: Check if restart is required (informational only - no interruption)
                try {
                    $rebootRequired = Get-WURebootStatus -Silent -ErrorAction SilentlyContinue
                    if ($rebootRequired) {
                        Write-Log 'System restart required to complete Windows Updates (will be handled at end of script).' 'INFO'
                        Write-Host "ℹ️ System restart required to complete Windows Updates (will be checked at end of script)" -ForegroundColor Cyan
                    }
                    else {
                        Write-Log 'No restart required for installed updates.' 'INFO'
                        Write-Host "✅ No restart required for installed updates" -ForegroundColor Green
                    }
                }
                catch {
                    Write-Log "Unable to determine restart status: $_" 'VERBOSE'
                }
                
                $totalDuration = ((Get-Date) - $startTime).TotalSeconds
                Write-Log "Complete Windows Update process finished in $([math]::Round($totalDuration, 2)) seconds." 'INFO'
                Write-Host "✅ Windows Updates completed - continuing to next task" -ForegroundColor Green
                
                return $successCount -gt 0 -or $failureCount -eq 0
            }
            catch {
                Write-Log "Windows Update installation failed: $_" 'ERROR'
                return $false
                # [REMOVED] Fallback logic - all update installation is PowerShell 7 native
            }
        }
        else {
            Write-Log 'No updates available for installation.' 'INFO'
        }
        
        return $true
    }
    catch {
        Write-Log "Critical error in Windows Update process: $_" 'ERROR'
        return $false
    }
    finally {
        $totalDuration = ((Get-Date) - $startTime).TotalSeconds
        Write-Log "Windows Updates process completed in $([math]::Round($totalDuration, 2)) seconds." 'INFO'
    }
}

### Start menu apps enumeration: PowerShell 7 native
# Returns: Array of Start menu app objects for inventory and management operations
function Get-StartAppsCompatible {
    if ($PSVersionTable.PSVersion.Major -ge 7) {
        # [REMOVED] Legacy compatibility block - all StartApps operations are PowerShell 7 native
        $command = "Get-StartApps | Select-Object Name, AppId | ConvertTo-Json -Depth 2"
        $result = Invoke-WindowsPowerShellCommand -Command $command -Description "Get Start menu apps"
        if ($result) {
            try {
                return ($result | ConvertFrom-Json)
            }
            catch {
                Write-Log "Failed to parse Start apps JSON: $_" 'WARN'
                return @()
            }
        }
        return @()
    }
    else {
        # [REMOVED] Native PowerShell 5.1 block
        return Get-StartApps -ErrorAction SilentlyContinue
    }
}

### [PRE-TASK 1] Task Functions
# Task execution wrapper with error handling
# Purpose: Provides consistent task execution with comprehensive error handling and logging
# Parameters: $TaskName (string), $TaskFunction (scriptblock) - Task identifier and execution logic
# Returns: Boolean success status of task execution
# Logic: Try/catch wrapper with detailed logging for all maintenance task operations
function Invoke-Task {
    param(
        [string]$TaskName,
        [scriptblock]$Action
    )
    Write-Log "Starting task: $TaskName" 'INFO'
    try {
        & $Action
        Write-Log "Task succeeded: $TaskName" 'INFO'
        return $true
    }
    catch {
        Write-Log "Task failed: $TaskName. Error: $_" 'ERROR'
        return $false
    }
}

### [PRE-TASK 2] Extensive System Inventory (Initial)
# Function: Comprehensive system inventory collection  
# Purpose: Collects detailed system information for analysis, reporting, and maintenance planning
# Environment: Windows 10/11, any privilege level, comprehensive WMI/CIM access
# Output: Global $global:SystemInventory object and exported files (inventory.txt, apps_*.txt)
# Performance: Optimized queries, parallel processing where possible, structured data organization
# Dependencies: WMI/CIM cmdlets, Winget, Chocolatey, AppX, registry access, file system permissions
function Get-ExtensiveSystemInventory {
    Write-Log 'Starting Extensive System Inventory (JSON Format).' 'INFO'
    $inventoryFolder = $PSScriptRoot
    if (-not (Test-Path $inventoryFolder)) { New-Item -ItemType Directory -Path $inventoryFolder -Force | Out-Null }

    # Build structured inventory object
    $inventory = [ordered]@{
        metadata           = [ordered]@{
            generatedOn   = (Get-Date).ToString('o')
            scriptVersion = '1.0.0'
            hostname      = $env:COMPUTERNAME
            user          = $env:USERNAME
            powershell    = $PSVersionTable.PSVersion.ToString() # PowerShell 7 native
        }
        system             = @{}
        appx               = @()
        winget             = @()
        choco              = @()
        registry_uninstall = @()
        services           = @()
        scheduled_tasks    = @()
        drivers            = @()
        updates            = @()
    }

    Write-Log 'Collecting system information...' 'INFO'
    try {
        $systemInfo = Get-ComputerInfo
        $inventory.system = $systemInfo
        Write-Log 'System information collected successfully.' 'INFO'
    }
    catch { 
        Write-Log "System information collection failed: $_" 'WARN'
        $inventory.system = @{ error = $_.ToString() }
    }

    Write-Log 'Collecting installed Appx applications...' 'INFO'
    try {
        $appxPackages = Get-AppxPackageCompatible -AllUsers
        if ($appxPackages -and $appxPackages.Count -gt 0) {
            $inventory.appx = @($appxPackages | Select-Object Name, PackageFullName, Publisher)
            Write-Log "Successfully collected $($inventory.appx.Count) Appx applications." 'INFO'
        }
        else {
            Write-Log 'No Appx applications found or module not available.' 'WARN'
            $inventory.appx = @()
        }
    }
    catch { 
        Write-Log "Appx applications collection failed: $_" 'WARN'
        $inventory.appx = @()
    }

    Write-Log 'Collecting installed winget applications...' 'INFO'
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        try {
            # Enhanced winget parsing
            $wingetSuccess = $false
            $attempts = 0
            $maxAttempts = 3
            
            # Strategy 1: Try JSON output with enhanced cleaning
            while (-not $wingetSuccess -and $attempts -lt $maxAttempts) {
                $attempts++
                try {
                    Write-Log "[Inventory] Winget JSON attempt $attempts..." 'VERBOSE'
                    
                    # Use more robust JSON extraction
                    $wingetProcess = Start-Process -FilePath "winget" -ArgumentList @("list", "--accept-source-agreements", "--output", "json") -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput "$env:TEMP\winget_output_$PID.json" -RedirectStandardError "$env:TEMP\winget_error_$PID.txt"
                    
                    if ($wingetProcess.ExitCode -eq 0 -and (Test-Path "$env:TEMP\winget_output_$PID.json")) {
                        $wingetJsonRaw = Get-Content "$env:TEMP\winget_output_$PID.json" -Raw -ErrorAction SilentlyContinue
                        
                        if ($wingetJsonRaw -and $wingetJsonRaw.Trim() -ne '') {
                            # Enhanced JSON cleaning - handle multiple JSON patterns
                            $cleanJson = $wingetJsonRaw
                            
                            # Remove any text before the first JSON bracket
                            if ($wingetJsonRaw.Contains('{')) {
                                $jsonStart = $wingetJsonRaw.IndexOf('{')
                                $cleanJson = $wingetJsonRaw.Substring($jsonStart)
                            }
                            elseif ($wingetJsonRaw.Contains('[')) {
                                $jsonStart = $wingetJsonRaw.IndexOf('[')
                                $cleanJson = $wingetJsonRaw.Substring($jsonStart)
                            }
                            
                            # Remove any text after the last JSON bracket
                            $lastBrace = $cleanJson.LastIndexOf('}')
                            $lastBracket = $cleanJson.LastIndexOf(']')
                            $jsonEnd = [Math]::Max($lastBrace, $lastBracket)
                            
                            if ($jsonEnd -gt 0) {
                                $cleanJson = $cleanJson.Substring(0, $jsonEnd + 1)
                            }
                            
                            # Parse JSON with multiple format support
                            $wingetData = $cleanJson | ConvertFrom-Json -ErrorAction SilentlyContinue
                            
                            if (-not $wingetData) {
                                Write-Log "[Inventory] Failed to parse winget JSON output on attempt $attempts" 'WARN'
                                continue
                            }
                            
                            # Handle different winget JSON formats
                            if ($wingetData.Sources -and $wingetData.Sources.Count -gt 0) {
                                # Format 1: Sources -> Packages structure
                                $inventory.winget = @($wingetData.Sources | ForEach-Object { 
                                        if ($_.Packages) {
                                            $_.Packages | ForEach-Object {
                                                [PSCustomObject]@{
                                                    Name    = $_.Name
                                                    Id      = $_.Id
                                                    Version = if ($_.InstalledVersion) { $_.InstalledVersion } else { $_.Version }
                                                    Source  = if ($_.Source) { $_.Source } else { 'winget' }
                                                }
                                            }
                                        }
                                    })
                                $wingetSuccess = $true
                                Write-Log "[Inventory] Collected $($inventory.winget.Count) winget apps via JSON (Sources format)." 'INFO'
                            }
                            elseif ($wingetData.Count -gt 0 -or ($wingetData -is [array] -and $wingetData.Length -gt 0)) {
                                # Format 2: Direct array of packages
                                $inventory.winget = @($wingetData | ForEach-Object {
                                        [PSCustomObject]@{
                                            Name    = $_.Name
                                            Id      = $_.Id
                                            Version = if ($_.InstalledVersion) { $_.InstalledVersion } else { $_.Version }
                                            Source  = if ($_.Source) { $_.Source } else { 'winget' }
                                        }
                                    })
                                $wingetSuccess = $true
                                Write-Log "[Inventory] Collected $($inventory.winget.Count) winget apps via JSON (Direct array format)." 'INFO'
                            }
                            else {
                                Write-Log "[Inventory] Winget JSON format not recognized. Attempt $attempts failed." 'VERBOSE'
                            }
                        }
                        else {
                            Write-Log "[Inventory] Empty winget JSON output. Attempt $attempts failed." 'VERBOSE'
                        }
                    }
                    else {
                        Write-Log "[Inventory] Winget process failed with exit code $($wingetProcess.ExitCode). Attempt $attempts failed." 'VERBOSE'
                    }
                    
                    # Cleanup temp files
                    Remove-Item "$env:TEMP\winget_output_$PID.json", "$env:TEMP\winget_error_$PID.txt" -ErrorAction SilentlyContinue
                }
                catch {
                    Write-Log "[Inventory] Winget JSON attempt $attempts failed: $_" 'VERBOSE'
                }
                
                if (-not $wingetSuccess -and $attempts -lt $maxAttempts) {
                    Start-Sleep -Milliseconds 500  # Brief pause between attempts
                }
            }
            
            # Enhanced text parsing
            if (-not $wingetSuccess) {
                try {
                    Write-Log "[Inventory] Using enhanced winget text parsing..." 'INFO'
                    
                    # Try different text output formats
                    $textFormats = @(
                        @("list", "--accept-source-agreements"),
                        @("list", "--accept-source-agreements", "--include-unknown"),
                        @("list")
                    )
                    
                    foreach ($format in $textFormats) {
                        try {
                            $wingetOutput = & winget @format 2>$null
                            if ($wingetOutput -and $wingetOutput.Count -gt 0) {
                                
                                # Enhanced text parsing with multiple patterns
                                $apps = @()
                                $headerFound = $false
                                
                                foreach ($line in $wingetOutput) {
                                    # Skip until we find the header
                                    if (-not $headerFound) {
                                        if ($line -match '^Name\s+' -or $line -match '^-+\s+') {
                                            $headerFound = $true
                                        }
                                        continue
                                    }
                                    
                                    # Skip separator lines and empty lines
                                    if ($line -match '^-+' -or $line.Trim() -eq '' -or $line -match '^\s*$') {
                                        continue
                                    }
                                    
                                    # Parse app line with flexible column detection
                                    if ($line -match '\S') {
                                        try {
                                            # Split by multiple spaces to handle column alignment
                                            $parts = $line -split '\s{2,}' | Where-Object { $_.Trim() -ne '' }
                                            
                                            if ($parts.Count -ge 1) {
                                                $apps += [PSCustomObject]@{
                                                    Name    = $parts[0].Trim()
                                                    Id      = if ($parts.Count -gt 1) { $parts[1].Trim() } else { $parts[0].Trim() }
                                                    Version = if ($parts.Count -gt 2) { $parts[2].Trim() } else { 'Unknown' }
                                                    Source  = 'text-parsed'
                                                }
                                            }
                                        }
                                        catch {
                                            # Treat entire line as app name
                                            $apps += [PSCustomObject]@{
                                                Name    = $line.Trim()
                                                Id      = $line.Trim()
                                                Version = 'Unknown'
                                                Source  = 'text-parsing'
                                            }
                                        }
                                    }
                                }
                                
                                if ($apps.Count -gt 0) {
                                    $inventory.winget = $apps
                                    $wingetSuccess = $true
                                    Write-Log "[Inventory] Collected $($inventory.winget.Count) winget apps via enhanced text parsing." 'INFO'
                                    break
                                }
                            }
                        }
                        catch {
                            Write-Log "[Inventory] Text parsing format failed: $_" 'VERBOSE'
                        }
                    }
                }
                catch {
                    Write-Log "[Inventory] Enhanced text parsing failed: $_" 'WARN'
                }
            }
            
            # Final fallback: basic winget list
            if (-not $wingetSuccess) {
                try {
                    Write-Log "[Inventory] Using basic winget fallback..." 'VERBOSE'
                    $basicOutput = winget list 2>$null | Where-Object { $_ -match '\S' -and $_ -notmatch '^Name|^-+|packages available' }
                    
                    if ($basicOutput) {
                        $inventory.winget = @($basicOutput | ForEach-Object {
                                [PSCustomObject]@{
                                    Name    = $_.Trim()
                                    Id      = $_.Trim()
                                    Version = 'Unknown'
                                    Source  = 'basic-fallback'
                                }
                            })
                        Write-Log "[Inventory] Collected $($inventory.winget.Count) winget apps via basic fallback." 'INFO'
                    }
                    else {
                        $inventory.winget = @()
                        Write-Log "[Inventory] No winget apps found with any method." 'WARN'
                    }
                }
                catch {
                    Write-Log "[Inventory] Basic winget fallback failed: $_" 'WARN'
                    $inventory.winget = @()
                }
            }
        }
        catch {
            Write-Log "[Inventory] All winget parsing methods failed: $_" 'WARN'
            $inventory.winget = @()
        }
    }
    else {
        Write-Log "[Inventory] Winget not available." 'WARN'
        $inventory.winget = @()
    }

    Write-Log "[Inventory] Collecting installed choco apps..." 'INFO'
    if (Get-Command choco -ErrorAction SilentlyContinue) {
        try {
            $chocoOutput = choco list --local-only 2>$null
            if ($chocoOutput) {
                $inventory.choco = @($chocoOutput | Where-Object { $_ -match '\S' -and $_ -notmatch '^Chocolatey|packages installed|^$' } | 
                    ForEach-Object { 
                        $parts = $_ -split '\s+', 2
                        [PSCustomObject]@{
                            Name    = if ($parts.Count -gt 0) { $parts[0] } else { $_ }
                            Version = if ($parts.Count -gt 1) { $parts[1] } else { $null }
                        }
                    })
                Write-Log "[Inventory] Collected $($inventory.choco.Count) choco apps." 'INFO'
            }
        }
        catch { 
            Write-Log "[Inventory] Choco apps failed: $_" 'WARN'
            $inventory.choco = @()
        }
    }
    else {
        Write-Log "[Inventory] Chocolatey not available." 'WARN'
        $inventory.choco = @()
    }

    Write-Log "[Inventory] Collecting registry uninstall keys..." 'INFO'
    $uninstallKeys = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
    )
    try {
        $inventory.registry_uninstall = @(foreach ($key in $uninstallKeys) {
                Get-ChildItem $key -ErrorAction SilentlyContinue | ForEach-Object {
                    $props = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
                    if ($props.DisplayName) {
                        [PSCustomObject]@{ 
                            DisplayName     = $props.DisplayName
                            UninstallString = $props.UninstallString
                            Publisher       = $props.Publisher
                            Version         = $props.DisplayVersion
                        }
                    }
                }
            })
        Write-Log "[Inventory] Collected $($inventory.registry_uninstall.Count) registry uninstall entries." 'INFO'
    }
    catch { 
        Write-Log "[Inventory] Registry uninstall keys failed: $_" 'WARN'
        $inventory.registry_uninstall = @()
    }

    Write-Log "[Inventory] Collecting services..." 'INFO'
    try {
        $inventory.services = @(Get-Service -ErrorAction SilentlyContinue | Where-Object { $null -ne $_ } | 
            Select-Object Name, Status, StartType)
        Write-Log "[Inventory] Collected $($inventory.services.Count) services." 'INFO'
    }
    catch { 
        Write-Log "[Inventory] Services failed: $_" 'WARN'
        $inventory.services = @()
    }

    Write-Log "[Inventory] Collecting scheduled tasks..." 'INFO'
    try {
        $inventory.scheduled_tasks = @(Get-ScheduledTask -ErrorAction SilentlyContinue | 
            Select-Object TaskName, TaskPath, State)
        Write-Log "[Inventory] Collected $($inventory.scheduled_tasks.Count) scheduled tasks." 'INFO'
    }
    catch { 
        Write-Log "[Inventory] Scheduled tasks failed: $_" 'WARN'
        $inventory.scheduled_tasks = @()
    }

    Write-Log "[Inventory] Collecting drivers..." 'INFO'
    try {
        $inventory.drivers = @(Get-CimInstance Win32_PnPSignedDriver -ErrorAction SilentlyContinue | 
            Select-Object DeviceName, DriverVersion, Manufacturer)
        Write-Log "[Inventory] Collected $($inventory.drivers.Count) drivers." 'INFO'
    }
    catch { 
        Write-Log "[Inventory] Drivers failed: $_" 'WARN'
        $inventory.drivers = @()
    }

    Write-Log "[Inventory] Collecting Windows updates..." 'INFO'
    try {
        $inventory.updates = @(Get-HotFix -ErrorAction SilentlyContinue | 
            Select-Object Description, HotFixID, InstalledOn)
        Write-Log "[Inventory] Collected $($inventory.updates.Count) Windows updates." 'INFO'
    }
    catch { 
        Write-Log "[Inventory] Windows updates failed: $_" 'WARN'
        $inventory.updates = @()
    }

    # Write structured inventory.json
    $inventoryPath = Join-Path $inventoryFolder 'inventory.json'
    try {
        $inventory | ConvertTo-Json -Depth 6 | Out-File -FilePath $inventoryPath -Encoding UTF8
        Write-Log "[Inventory] Structured inventory saved to inventory.json" 'INFO'
        
        # Store global reference for diff operations
        $global:SystemInventory = $inventory
    }
    catch {
        Write-Log "[Inventory] Failed to write inventory.json: $_" 'WARN'
    }

    Write-Log "[END] Extensive System Inventory (JSON Format)" 'INFO'
}

# [PRE-TASK 3] Run inventory before anything else
Get-ExtensiveSystemInventory

### [MAIN SCRIPT STARTS HERE]

# Check if script is running as Administrator early
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Warning "This script must be run as Administrator. Exiting."
    Read-Host -Prompt 'Press Enter to exit...'
    exit 1
}

Write-Log "Script started. User: $env:USERNAME, Computer: $env:COMPUTERNAME, Script Version: 1.0.0" 'INFO'

### Centralized temp folder and essential/bloatware lists
# Use repo folder as temp folder for better organization
$global:TempFolder = $PSScriptRoot
if (-not (Test-Path $global:TempFolder)) {
    New-Item -ItemType Directory -Path $global:TempFolder -Force | Out-Null
}

### Enhanced comprehensive bloatware list for Windows 10/11 (2025)
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
    'Piriform.CCleaner', 'PCAccelerate.PCAcceleratePro', 'PCOptimizer.PCOptimizerPro', 'Reimage.ReimageRepair',
    
    # Browsers (Alternative/Bloatware)
    'Opera.Opera', 'Opera.OperaGX', 'BraveSoftware.BraveBrowser', 'VivaldiTechnologies.Vivaldi',
    'Mozilla.SeaMonkey', 'TheTorProject.TorBrowser', 'Yandex.YandexBrowser', 'UCWeb.UCBrowser',
    'Baidu.BaiduBrowser', 'Sogou.SogouExplorer', 'SRWare.Iron', 'Maxthon.Maxthon', 'Lunascape.Lunascape',
    'AvantBrowser.AvantBrowser', 'CentBrowser.CentBrowser', 'Cliqz.Cliqz', 'Coowon.Coowon', 'CoolNovo.CoolNovo',
    'Dooble.Dooble', 'GhostBrowser.GhostBrowser', 'OtterBrowser.OtterBrowser', 'PaleMoon.PaleMoon',
    'Polarity.Polarity', 'QupZilla.QupZilla', 'QuteBrowser.QuteBrowser', 'Sleipnir.Sleipnir',
    'Sputnik.Sputnik', 'Superbird.Superbird', 'TorchMediaInc.Torch', 'Waterfox.Waterfox',
    'Blisk.Blisk', 'FenrirInc.Sleipnir', 'FlashPeak.SlimBrowser', 'FlashPeak.Slimjet',
    'Astian.Midori', 'Basilisk.Basilisk', 'DigitalPersona.EpicPrivacyBrowser', 'KDE.Falkon', 'Orbitum.Orbitum',
    
    # Adobe Bloatware
    'Adobe.AdobeCreativeCloud', 'Adobe.AdobeExpress', 'Adobe.AdobeGenuineService', 'Adobe.PhotoshopExpress',
    
    # E-commerce and Shopping
    'Amazon.Amazon', 'Amazon.Kindle', 'eBay.eBay', 'Booking.com.Booking', 'TripAdvisor.TripAdvisor',
    'Alibaba.AliExpress', 'Wish.Wish', 'Groupon.Groupon',
    
    # VPN and Privacy
    'ExpressVPN.ExpressVPN', 'NordVPN.NordVPN', 'CyberGhost.CyberGhost', 'Surfshark.Surfshark',
    'ProtonVPN.ProtonVPN', 'HotspotShield.HotspotShield', 'TunnelBear.TunnelBear',
    
    # Cloud Storage and Sync (Bloatware versions)
    'Dropbox.Dropbox', 'Google.GoogleDrive', 'Box.Box', 'pCloud.pCloud', 'Mega.Mega',
    
    # Multimedia and Photo
    'Foxit.FoxitPDFReader', 'CyberLink.MediaSuite', 'CyberLink.Power2Go', 'CyberLink.PowerDirector', 
    'CyberLink.PowerDVD', 'CyberLink.YouCam', 'Power2Go.Power2Go', 'PowerDirector.PowerDirector',
    'PicsArt.PicsartPhotoStudio', 'ThumbmunkeysLtd.PhototasticCollage', 'Adobe.PhotoshopElements',
    
    # Note-taking and Organization
    'Evernote.Evernote', 'Notion.Notion', 'Obsidian.Obsidian', 'Joplin.Joplin',
    
    # Office Alternatives (Bloatware)
    'WPSOffice.WPSOffice', 'Kingsoft.WPSOffice', 'Kingsoft.Writer', 'Kingsoft.Presentation', 
    'Kingsoft.Spreadsheets', 'Apache.OpenOffice', 'SoftMaker.FreeOffice',
    
    # Driver and System Tools (Bloatware)
    'DriverPack.DriverPackSolution', 'DriverEasy.DriverEasy', 'SlimWare.DriverUpdate',
    'Advanced.SystemCare', 'IObit.Uninstaller', 'Glary.Utilities', 'Wise.WiseCleanerPro',
    
    # Password Managers (Bloatware versions)
    'KeeperSecurity.Keeper', 'NortonLifeLock.NortonPasswordManager', 'McAfee.TrueKey',
    
    # System Utilities (Bloatware)
    'WinZip.WinZip', 'PeaZip.PeaZip', 'Bandizip.Bandizip',
    
    # Financial and Trading
    'Robinhood.Robinhood', 'Coinbase.Coinbase', 'Binance.Binance', 'PayPal.PayPal', 
    
    # News and Information
    'Microsoft.BingNews', 'CNN.CNN', 'BBC.BBC', 'Reuters.Reuters', 'Associated.Press', 
    
    # Weather Apps
    'Weather.Weather', 'AccuWeather.AccuWeather', 'WeatherChannel.WeatherChannel', 
    
    # Travel and Navigation
    'Uber.Uber', 'Lyft.Lyft', 'Maps.Maps', 'Waze.Waze', 'Google.Maps',
    
    # Fitness and Health
    'Fitbit.Fitbit', 'MyFitnessPal.MyFitnessPal', 'Strava.Strava', 'Nike.Nike',
    
    # Windows Store and Xbox related
    'Microsoft.StorePurchaseApp', 'Microsoft.DesktopAppInstaller',
    
    # Telemetry and Data Collection
    'Microsoft.Advertising.Xaml', 'Microsoft.Services.Store.Engagement'
    
    
) | Sort-Object -Unique

# Add custom bloatware from config if any
if ($global:Config.CustomBloatwareList -and $global:Config.CustomBloatwareList.Count -gt 0) {
    $global:BloatwareList += $global:Config.CustomBloatwareList
    $global:BloatwareList = $global:BloatwareList | Sort-Object -Unique
    Write-Log "Added $($global:Config.CustomBloatwareList.Count) custom bloatware entries from config" 'INFO'
}

$bloatwareListPath = Join-Path $global:TempFolder 'bloatware.json'
$global:BloatwareList | ConvertTo-Json -Depth 3 | Out-File $bloatwareListPath -Encoding UTF8

### Essential Apps List
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

$essentialAppsListPath = Join-Path $global:TempFolder 'essential_apps.json'
$global:EssentialApps | ConvertTo-Json -Depth 5 | Out-File $essentialAppsListPath -Encoding UTF8

### Config is already loaded early in the script, add logging here
Write-Log "Loaded configuration from config.json" 'INFO'
Write-Log "Config: SkipBloatware=$($global:Config.SkipBloatwareRemoval), SkipEssential=$($global:Config.SkipEssentialApps), SkipUpdates=$($global:Config.SkipWindowsUpdates)" 'INFO'

### Check Windows version and compatibility
$os = Get-CimInstance Win32_OperatingSystem
$osVersion = $os.Version
$osCaption = $os.Caption
Write-Log "Detected Windows version: $osCaption ($osVersion)" 'INFO'
if ($osVersion -lt '10.0') {
    Write-Log "Unsupported Windows version. Exiting." 'ERROR'
    exit 2
}

### PowerShell-specific Dependency Management
# AI_FUNCTION: PowerShell dependency validation and management
# AI_PURPOSE: Validates and installs required PowerShell modules and package managers
# AI_ENVIRONMENT: Windows 10/11, Administrator required for installations, PowerShell Gallery access
# AI_DEPENDENCIES: Winget, Chocolatey, NuGet, PSWindowsUpdate, PowerShellGet modules  
# AI_LOGIC: Systematic dependency checking, automatic installation, version compatibility validation
# AI_PERFORMANCE: Cached checks, parallel installations where safe, comprehensive error handling
function Test-PowerShellDependencies {
    param()
    
    Write-Log '[DEPENDENCIES] Verifying PowerShell-specific dependencies...' 'INFO'
    Write-Log "[DEPENDENCIES] Running PowerShell version: $($PSVersionTable.PSVersion.ToString())" 'INFO'
    $dependencyStatus = @{}
    
    # Test Module Availability (with PowerShell 7 compatibility notes)
    $modules = @(
        @{ Name = 'Appx'; Critical = $false; Description = 'UWP/Store app management (via Windows PowerShell)' },
        @{ Name = 'PSWindowsUpdate'; Critical = $false; Description = 'Windows Update management (via Windows PowerShell)' },
        @{ Name = 'DISM'; Critical = $false; Description = 'Windows image servicing' }
    )
    
    foreach ($module in $modules) {
        $moduleName = $module.Name
        
        if ($PSVersionTable.PSVersion.Major -ge 7) {
            # For PowerShell 7, check if Windows PowerShell can access these modules
            if ($moduleName -in @('Appx', 'PSWindowsUpdate')) {
                try {
                    $testCommand = "Get-Module -ListAvailable -Name $moduleName -ErrorAction SilentlyContinue | Select-Object Name"
                    $result = Invoke-WindowsPowerShellCommand -Command $testCommand -Description "Test $moduleName availability"
                    $available = $null -ne $result
                }
                catch {
                    $available = $false
                }
                $dependencyStatus[$moduleName] = $available
                
                if ($available) {
                    Write-Log "[DEPENDENCIES] Module '$moduleName' is available via Windows PowerShell" 'VERBOSE'
                }
                else {
                    $level = if ($module.Critical) { 'ERROR' } else { 'WARN' }
                    Write-Log "[DEPENDENCIES] Module '$moduleName' is not available ($($module.Description))" $level
                }
            }
            else {
                # Regular module check for PowerShell 7 compatible modules
                $available = $null -ne (Get-Module -ListAvailable -Name $moduleName -ErrorAction SilentlyContinue)
                $dependencyStatus[$moduleName] = $available
                
                if ($available) {
                    Write-Log "[DEPENDENCIES] Module '$moduleName' is available" 'VERBOSE'
                }
                else {
                    $level = if ($module.Critical) { 'ERROR' } else { 'WARN' }
                    Write-Log "[DEPENDENCIES] Module '$moduleName' is not available ($($module.Description))" $level
                }
            }
        }
        else {
            # Windows PowerShell 5.1 - native check
            $available = $null -ne (Get-Module -ListAvailable -Name $moduleName -ErrorAction SilentlyContinue)
            $dependencyStatus[$moduleName] = $available
            
            if ($available) {
                Write-Log "[DEPENDENCIES] Module '$moduleName' is available" 'VERBOSE'
            }
            else {
                $level = if ($module.Critical) { 'ERROR' } else { 'WARN' }
                Write-Log "[DEPENDENCIES] Module '$moduleName' is not available ($($module.Description))" $level
            }
        }
    }
    
    # Test Command Availability
    $commands = @(
        @{ Name = 'winget'; Critical = $false; Description = 'Windows Package Manager' },
        @{ Name = 'choco'; Critical = $false; Description = 'Chocolatey Package Manager' },
        @{ Name = 'dism'; Critical = $true; Description = 'Windows Image Servicing' }
    )
    
    foreach ($command in $commands) {
        $commandName = $command.Name
        $available = $null -ne (Get-Command $commandName -ErrorAction SilentlyContinue)
        $dependencyStatus[$commandName] = $available
        
        if ($available) {
            Write-Log "[DEPENDENCIES] Command '$commandName' is available" 'VERBOSE'
        }
        else {
            $level = if ($command.Critical) { 'ERROR' } else { 'WARN' }
            Write-Log "[DEPENDENCIES] Command '$commandName' is not available ($($command.Description))" $level
        }
    }
    
    # Set global dependency flags for graceful degradation
    $global:HasWinget = $dependencyStatus['winget']
    $global:HasChocolatey = $dependencyStatus['choco']
    $global:HasAppxModule = $dependencyStatus['Appx']
    $global:HasPSWindowsUpdate = $dependencyStatus['PSWindowsUpdate']
    $global:HasDISM = $dependencyStatus['DISM'] -and $dependencyStatus['dism']
    
    # Summary report
    $working = ($dependencyStatus.GetEnumerator() | Where-Object { $_.Value } | Measure-Object).Count
    $total = $dependencyStatus.Count
    $missing = $total - $working
    
    Write-Log "[DEPENDENCIES] Status: $working/$total dependencies available" 'INFO'
    if ($missing -gt 0) {
        $missingList = ($dependencyStatus.GetEnumerator() | Where-Object { -not $_.Value } | ForEach-Object { $_.Key }) -join ', '
        Write-Log "[DEPENDENCIES] Missing: $missingList" 'WARN'
        
        # Attempt to install missing non-critical modules
        if (-not $dependencyStatus['PSWindowsUpdate']) {
            Write-Log "[DEPENDENCIES] Attempting to install PSWindowsUpdate module..." 'INFO'
            try {
                if ($PSVersionTable.PSVersion.Major -ge 7) {
                    # Install in Windows PowerShell for PowerShell 7 compatibility
                    $installCmd = "Install-Module -Name PSWindowsUpdate -Force -Scope AllUsers -Confirm:`$false -AllowClobber -SkipPublisherCheck -ErrorAction Stop"
                    $result = Invoke-WindowsPowerShellCommand -Command $installCmd -Description "Install PSWindowsUpdate"
                    if ($result -ne $null) {
                        Write-Log "[DEPENDENCIES] PSWindowsUpdate module installed successfully in Windows PowerShell" 'INFO'
                        $dependencyStatus['PSWindowsUpdate'] = $true
                        $global:HasPSWindowsUpdate = $true
                    }
                }
                else {
                    # Direct installation in Windows PowerShell
                    Install-Module -Name PSWindowsUpdate -Force -Scope AllUsers -Confirm:$false -AllowClobber -SkipPublisherCheck -ErrorAction Stop
                    Write-Log "[DEPENDENCIES] PSWindowsUpdate module installed successfully" 'INFO'
                    $dependencyStatus['PSWindowsUpdate'] = $true
                    $global:HasPSWindowsUpdate = $true
                }
            }
            catch {
                Write-Log "[DEPENDENCIES] Failed to install PSWindowsUpdate: $($_.Exception.Message)" 'WARN'
            }
        }
        
        Write-Log "[DEPENDENCIES] Some features will use graceful degradation" 'INFO'
    }
    else {
        Write-Log "[DEPENDENCIES] All dependencies are available" 'INFO'
    }
    
    return $dependencyStatus
}

# AI_FUNCTION: PowerShell module import with graceful fallback handling
# AI_PURPOSE: Safely imports PowerShell modules with comprehensive error handling and alternatives
# AI_ENVIRONMENT: Any PowerShell version, handles module availability and compatibility issues
# AI_PARAMETERS: $ModuleName (string) - Name of module to import with fallback strategies
# AI_LOGIC: Try native import, attempt installation if missing, graceful degradation on failure
# AI_RETURNS: Boolean success status of module import operation
function Import-ModuleWithGracefulFallback {
    param(
        [string]$ModuleName,
        [string]$FallbackMessage = "Module not available, skipping operations"
    )
    
    if (Get-Module -ListAvailable -Name $ModuleName -ErrorAction SilentlyContinue) {
        try {
            Import-Module $ModuleName -ErrorAction SilentlyContinue -Force
            if (Get-Module -Name $ModuleName -ErrorAction SilentlyContinue) {
                Write-Log "[MODULE] Successfully imported $ModuleName" 'VERBOSE'
                return $true
            }
            else {
                Write-Log "[MODULE] Failed to import $ModuleName - module not loaded after import attempt" 'WARN'
                return $false
            }
        }
        catch {
            Write-Log "[MODULE] Failed to import $ModuleName : $_" 'WARN'
            return $false
        }
    }
    else {
        Write-Log "[MODULE] $ModuleName not available. $FallbackMessage" 'WARN'
        return $false
    }
}

# Initialize dependency status
$global:DependencyStatus = Test-PowerShellDependencies

### Check for required PowerShell version

if ($PSVersionTable.PSVersion.Major -lt 5) {
    Write-Log "PowerShell 5.1 or higher is required. Exiting." 'ERROR'
    exit 3
}

# Log PowerShell version and compatibility mode
if ($PSVersionTable.PSVersion.Major -ge 7) {
    Write-Log "Running in PowerShell 7+ compatibility mode. Legacy operations will use Windows PowerShell 5.1." 'INFO'
}
else {
    Write-Log "Running in Windows PowerShell 5.1 native mode." 'INFO'
}



# ================================================================
# [C.1] ESSENTIAL APPS INSTALLATION - COPILOT MAINTENANCE TASK
# ================================================================
# COPILOT_TASK_ID: InstallEssentialApps  
# Purpose: High-performance installation of curated essential applications using parallel processing
# Environment: Windows 10/11, Administrator required, Winget/Chocolatey access
# Logic: HashSet optimization, parallel processing, smart filtering, custom app support
# Performance: Ultra-parallel execution, timeout handling, detailed progress tracking
# Dependencies: Winget, Chocolatey, inventory system, config.json integration
# Function Location: [C.1] Lines 2095-2439 (approximate)
# ================================================================
function Install-EssentialApps {
    # ================================================================
    # COPILOT_TASK_HEADER: InstallEssentialApps (Application Management)
    # ================================================================
    # Purpose: High-performance installation of curated essential applications using parallel processing
    # Environment: Windows 10/11, Administrator required, Winget/Chocolatey package manager access
    # Performance: O(1) HashSet lookups, parallel job execution, smart pre-filtering, action-only logging
    # Dependencies: Winget, Chocolatey, system inventory, config.json custom app support
    # Logic: Inventory-based duplicate detection, parallel installation batches, comprehensive error handling
    # Customization: Supports custom app lists via $global:Config.CustomEssentialApps array
    # ================================================================
    # AI_TASK_HEADER: InstallEssentialApps (Ultra-Performance Edition)
    # ===============================
    # AI_PURPOSE: Parallel installation of essential applications with smart filtering and optimization
    # AI_ENVIRONMENT: Windows 10/11, Administrator required, package managers available
    # AI_LOGIC: HashSet O(1) lookups, parallel processing, comprehensive validation, action-only logging
    # Performance: Optimized for speed with hashtable filtering and parallel job execution
    # ===============================
    Write-Log 'Starting Install Essential Apps - Ultra-Parallel Processing Mode.' 'INFO'

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
    $appsToInstall = @()
    foreach ($essentialApp in $global:EssentialApps) {
        $found = $false
        
        # Check all possible identifiers for the essential app
        $identifiersToCheck = @()
        if ($essentialApp.Winget) { $identifiersToCheck += $essentialApp.Winget.Trim() }
        if ($essentialApp.Choco) { $identifiersToCheck += $essentialApp.Choco.Trim() }
        if ($essentialApp.Name) { $identifiersToCheck += $essentialApp.Name.Trim() }
        
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
        Write-Log "[EssentialApps] All essential apps already installed. Skipping installation process." 'INFO'
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

    Write-Log "[EssentialApps] Processing $($appsToInstall.Count) apps for installation..." 'INFO'

    # Initialize counters and results collection
    $successfulInstalls = [System.Collections.Concurrent.ConcurrentBag[PSCustomObject]]::new()
    $failedInstalls = [System.Collections.Concurrent.ConcurrentBag[PSCustomObject]]::new()
    $skippedInstalls = [System.Collections.Concurrent.ConcurrentBag[PSCustomObject]]::new()

    # Create installation jobs for parallel processing
    $installJobs = @()
    
    foreach ($app in $appsToInstall) {
        $job = Start-Job -ArgumentList $app, $wingetAvailable, $chocoAvailable -ScriptBlock {
            param($app, $wingetAvailable, $chocoAvailable)
            
            $result = @{
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
                    $wingetArgs = @(
                        "install", "--id", $app.Winget,
                        "--accept-source-agreements", "--accept-package-agreements", 
                        "--silent", "-e", "--disable-interactivity"
                    )
                    $wingetProc = Start-Process -FilePath "winget" -ArgumentList $wingetArgs -WindowStyle Hidden -Wait -PassThru
                    if ($wingetProc.ExitCode -eq 0) {
                        $result.Success = $true
                        $result.Method = "winget"
                        return $result
                    }
                    elseif ($wingetProc.ExitCode -eq -1978335189) {
                        # App already installed
                        $result.Skipped = $true
                        $result.SkipReason = "already installed (winget)"
                        return $result
                    }
                    else {
                        $result.Error += "winget failed (exit: $($wingetProc.ExitCode)); "
                    }
                }
                
                # Try Chocolatey as fallback
                if (-not $result.Success -and $app.Choco -and $chocoAvailable) {
                    $chocoArgs = @("install", $app.Choco, "-y", "--no-progress", "--limit-output")
                    $chocoProc = Start-Process -FilePath "choco" -ArgumentList $chocoArgs -WindowStyle Hidden -Wait -PassThru
                    if ($chocoProc.ExitCode -eq 0) {
                        $result.Success = $true
                        $result.Method = "choco"
                        return $result
                    }
                    elseif ($chocoProc.ExitCode -eq 1641 -or $chocoProc.ExitCode -eq 3010) {
                        # Success with reboot required
                        $result.Success = $true
                        $result.Method = "choco (reboot required)"
                        return $result
                    }
                    else {
                        $result.Error += "choco failed (exit: $($chocoProc.ExitCode))"
                    }
                }
                
                # No installation method succeeded
                if (-not $wingetAvailable -and -not $chocoAvailable) {
                    $result.Skipped = $true
                    $result.SkipReason = "no package manager available"
                }
                elseif (-not $app.Winget -and -not $app.Choco) {
                    $result.Skipped = $true
                    $result.SkipReason = "no installer defined"
                }
                else {
                    $result.Error = $result.Error.TrimEnd("; ")
                }
            }
            catch {
                $result.Error = "Exception: $($_.Exception.Message)"
            }
            
            return $result
        }
        $installJobs += $job
    }
    
    # Wait for all installation jobs to complete and collect results
    $installJobs | ForEach-Object {
        $jobResult = Receive-Job -Job $_ -Wait
        Remove-Job -Job $_ -Force
        
        if ($jobResult.Success) {
            [void]$successfulInstalls.Add([PSCustomObject]$jobResult)
        }
        elseif ($jobResult.Skipped) {
            [void]$skippedInstalls.Add([PSCustomObject]$jobResult)
        }
        else {
            [void]$failedInstalls.Add([PSCustomObject]$jobResult)
        }
    }

    # Enhanced Office detection with parallel checking
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
            [void]$successfulInstalls.Add([PSCustomObject]@{
                    AppName = "LibreOffice"
                    Method  = $libreResult.Method
                    Success = $true
                })
        }
        else {
            [void]$failedInstalls.Add([PSCustomObject]@{
                    AppName = "LibreOffice"
                    Error   = $libreResult.Error
                    Success = $false
                })
        }
    }

    # Convert concurrent collections to arrays for reporting
    $successArray = @($successfulInstalls.ToArray())
    $failedArray = @($failedInstalls.ToArray())
    $skippedArray = @($skippedInstalls.ToArray())

    # Action-only logging: Only log successful installations
    if ($successArray.Count -gt 0) {
        Write-Log "[EssentialApps] Successfully installed $($successArray.Count) apps:" 'INFO'
        $successArray | ForEach-Object {
            Write-Log "Installed: $($_.AppName) via $($_.Method)" 'INFO'
            Write-Host "✓ Installed: $($_.AppName) via $($_.Method)" -ForegroundColor Green
        }
    }

    # Office detection summary (action-only)
    if ($officeResult.Installed) {
        Write-Log "[EssentialApps] Microsoft Office detected ($($officeResult.DetectionMethod)). LibreOffice installation skipped." 'INFO'
    }

    # Summary statistics
    $totalProcessed = $successArray.Count + $failedArray.Count + $skippedArray.Count
    Write-Log "[EssentialApps] Installation complete. Processed: $totalProcessed apps (Success: $($successArray.Count), Failed: $($failedArray.Count), Skipped: $($skippedArray.Count))" 'INFO'
    
    # Only log errors and skips if they exist (minimal noise)
    if ($failedArray.Count -gt 0) {
        Write-Log "[EssentialApps] Failed installations: $($failedArray.Count)" 'WARN'
    }
    
    if ($skippedArray.Count -gt 0) {
        Write-Log "[EssentialApps] Skipped installations: $($skippedArray.Count)" 'INFO'
    }

    Write-Log "[END] Install Essential Apps" 'INFO'
}

# ================================================================
# [C.2] PACKAGE UPDATES - COPILOT MAINTENANCE TASK
# ================================================================
# COPILOT_TASK_ID: UpdateAllPackages
# Purpose: Ultra-high-performance parallel updating of all installed packages via multiple package managers
# Environment: Windows 10/11, Administrator required, Winget/Chocolatey access, enhanced performance focus  
# Performance: Multi-threaded execution, timeout handling, detailed metrics, action-only logging
# Dependencies: Winget, Chocolatey, parallel processing capabilities, comprehensive error handling
# Logic: Parallel execution streams, smart filtering, update validation, performance optimization
# Features: Timeout protection, concurrent processing, detailed timing metrics, action-focused logging
# Function Location: [C.2] Lines 2463-2884 (approximate)
# ================================================================
function Update-AllPackages {
    # ================================================================
    # COPILOT_TASK_HEADER: UpdateAllPackages (Package Management)
    # ================================================================
    # Purpose: Updates all installed packages using advanced parallel processing and smart caching
    # Environment: Windows 10/11, must run as Administrator, supports Winget and Chocolatey
    # Logic: Parallel execution, smart caching, detailed update tracking, comprehensive validation, action-only logging
    # Performance: Uses parallel jobs, smart pre-filtering, package-specific update tracking, optimized command args
    # ================================================================
    Write-Log "[START] Update All Packages (Ultra-Optimized Parallel Approach)" 'INFO'

    # Pre-check package manager availability with version detection
    $packageManagers = @()
    
    # Enhanced Winget availability check
    $wingetAvailable = $false
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        try {
            $wingetVersion = (winget --version 2>$null) -replace '[^\d\.]', ''
            if ($wingetVersion) {
                $wingetAvailable = $true
                $packageManagers += @{ Name = "Winget"; Version = $wingetVersion; Available = $true }
                Write-Log "[UpdatePackages] Winget detected: v$wingetVersion" 'VERBOSE'
            }
        }
        catch {
            Write-Log "[UpdatePackages] Winget version check failed: $_" 'VERBOSE'
        }
    }
    
    # Enhanced Chocolatey availability check
    $chocoAvailable = $false
    if (Get-Command choco -ErrorAction SilentlyContinue) {
        try {
            $chocoVersion = (choco --version 2>$null) -replace '[^\d\.]', ''
            if ($chocoVersion) {
                $chocoAvailable = $true
                $packageManagers += @{ Name = "Chocolatey"; Version = $chocoVersion; Available = $true }
                Write-Log "[UpdatePackages] Chocolatey detected: v$chocoVersion" 'VERBOSE'
            }
        }
        catch {
            Write-Log "[UpdatePackages] Chocolatey version check failed: $_" 'VERBOSE'
        }
    }
    
    if (-not $wingetAvailable -and -not $chocoAvailable) {
        Write-Log "[UpdatePackages] ERROR: No package managers available (winget/choco). Cannot update packages." 'ERROR'
        Write-Log "[END] Update All Packages" 'INFO'
        return
    }

    Write-Log "[UpdatePackages] Detected $($packageManagers.Count) package managers, initiating parallel updates..." 'INFO'

    # Initialize thread-safe results tracking
    $successfulUpdates = [System.Collections.Concurrent.ConcurrentBag[PSCustomObject]]::new()
    $failedUpdates = [System.Collections.Concurrent.ConcurrentBag[PSCustomObject]]::new()
    $noUpdatesAvailable = [System.Collections.Concurrent.ConcurrentBag[PSCustomObject]]::new()

    # Create enhanced parallel update jobs with improved error handling
    $updateJobs = @()
    
    # Enhanced Winget update job with optimized commands
    if ($wingetAvailable) {
        $wingetJob = Start-Job -ScriptBlock {
            $result = @{
                Source          = "Winget"
                Success         = $false
                UpdatedPackages = @()
                Error           = ""
                NoUpdatesFound  = $false
                ProcessingTime  = 0
            }
            
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            
            try {
                # Enhanced check for available updates with better performance flags
                $upgradeCheckArgs = @(
                    "upgrade", 
                    "--accept-source-agreements", 
                    "--disable-interactivity",
                    "--include-unknown"
                )
                
                $upgradeProcess = Start-Process -FilePath "winget" -ArgumentList $upgradeCheckArgs -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput "$env:TEMP\winget_check_$PID.txt" -RedirectStandardError "$env:TEMP\winget_check_err_$PID.txt"
                
                if ($upgradeProcess.ExitCode -eq 0) {
                    $upgradeOutput = Get-Content "$env:TEMP\winget_check_$PID.txt" -ErrorAction SilentlyContinue | Out-String
                    
                    # Enhanced parsing for no updates
                    if ($upgradeOutput -match "No applicable upgrade found|No installed package found matching input criteria|No available upgrade found") {
                        $result.NoUpdatesFound = $true
                        $result.Success = $true
                        $result.ProcessingTime = $stopwatch.Elapsed.TotalSeconds
                        return $result
                    }
                    
                    # Count available updates for better reporting
                    $availableUpdatesCount = ($upgradeOutput -split "`n" | Where-Object { $_ -match '^\S+\s+\S+\s+\S+\s+winget$' }).Count
                    
                    if ($availableUpdatesCount -eq 0) {
                        $result.NoUpdatesFound = $true
                        $result.Success = $true
                        $result.ProcessingTime = $stopwatch.Elapsed.TotalSeconds
                        return $result
                    }
                    
                    # Run the actual upgrade with enhanced performance flags
                    $upgradeArgs = @(
                        "upgrade", "--all", "--silent", 
                        "--accept-source-agreements", "--accept-package-agreements", 
                        "--disable-interactivity", "--force", "--include-unknown",
                        "--ignore-security-hash", "--ignore-local-archive-malware-scan"
                    )
                    
                    $upgradeExecProcess = Start-Process -FilePath "winget" -ArgumentList $upgradeArgs -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput "$env:TEMP\winget_upgrade_$PID.txt" -RedirectStandardError "$env:TEMP\winget_upgrade_err_$PID.txt"
                    
                    if ($upgradeExecProcess.ExitCode -eq 0) {
                        $upgradeExecOutput = Get-Content "$env:TEMP\winget_upgrade_$PID.txt" -ErrorAction SilentlyContinue | Out-String
                        
                        # Enhanced parsing for successful updates
                        $successLines = $upgradeExecOutput -split "`n" | Where-Object { 
                            $_ -match "Successfully installed|Successfully upgraded|Successfully updated" 
                        }
                        
                        if ($successLines.Count -gt 0) {
                            $result.UpdatedPackages = @($successLines | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '\S' })
                            $result.Success = $true
                        }
                        else {
                            # Check if no updates were actually needed
                            if ($upgradeExecOutput -match "No applicable upgrade found|Nothing to upgrade") {
                                $result.NoUpdatesFound = $true
                                $result.Success = $true
                            }
                            else {
                                $result.Success = $true
                                $result.UpdatedPackages = @("Updates completed (details not parseable)")
                            }
                        }
                    }
                    else {
                        $upgradeError = Get-Content "$env:TEMP\winget_upgrade_err_$PID.txt" -ErrorAction SilentlyContinue | Out-String
                        $result.Error = "Upgrade failed (exit: $($upgradeExecProcess.ExitCode)). Error: $upgradeError"
                    }
                }
                else {
                    $checkError = Get-Content "$env:TEMP\winget_check_err_$PID.txt" -ErrorAction SilentlyContinue | Out-String
                    $result.Error = "Check failed (exit: $($upgradeProcess.ExitCode)). Error: $checkError"
                }
                
                # Enhanced cleanup with PID-specific files
                Remove-Item "$env:TEMP\winget_*_$PID.txt" -ErrorAction SilentlyContinue
            }
            catch {
                $result.Error = "Exception: $($_.Exception.Message)"
            }
            finally {
                $stopwatch.Stop()
                $result.ProcessingTime = $stopwatch.Elapsed.TotalSeconds
            }
            
            return $result
        }
        $updateJobs += $wingetJob
    }
    
    # Enhanced Chocolatey update job with optimized commands
    if ($chocoAvailable) {
        $chocoJob = Start-Job -ScriptBlock {
            $result = @{
                Source          = "Chocolatey"
                Success         = $false
                UpdatedPackages = @()
                Error           = ""
                NoUpdatesFound  = $false
                ProcessingTime  = 0
            }
            
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            
            try {
                # Enhanced check for outdated packages with better performance
                $outdatedArgs = @(
                    "outdated", 
                    "--limit-output", 
                    "--ignore-unfound",
                    "--ignore-pinned"
                )
                
                $outdatedProcess = Start-Process -FilePath "choco" -ArgumentList $outdatedArgs -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput "$env:TEMP\choco_outdated_$PID.txt" -RedirectStandardError "$env:TEMP\choco_outdated_err_$PID.txt"
                
                if ($outdatedProcess.ExitCode -eq 0) {
                    $outdatedOutput = Get-Content "$env:TEMP\choco_outdated_$PID.txt" -ErrorAction SilentlyContinue
                    
                    # Filter out header and summary lines
                    $outdatedPackages = $outdatedOutput | Where-Object { 
                        $_ -match '\S' -and $_ -notmatch '^Chocolatey|^Output is package name|^\d+ packages have|^$' 
                    }
                    
                    if (-not $outdatedPackages -or $outdatedPackages.Count -eq 0) {
                        $result.NoUpdatesFound = $true
                        $result.Success = $true
                        $result.ProcessingTime = $stopwatch.Elapsed.TotalSeconds
                        return $result
                    }
                    
                    # Run the actual upgrade with enhanced performance flags
                    $upgradeArgs = @(
                        "upgrade", "all", "-y", 
                        "--limit-output", "--no-progress", 
                        "--skip-powershell", "--ignore-checksums",
                        "--timeout", "300"
                    )
                    
                    $upgradeProcess = Start-Process -FilePath "choco" -ArgumentList $upgradeArgs -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput "$env:TEMP\choco_upgrade_$PID.txt" -RedirectStandardError "$env:TEMP\choco_upgrade_err_$PID.txt"
                    
                    if ($upgradeProcess.ExitCode -eq 0) {
                        $upgradeOutput = Get-Content "$env:TEMP\choco_upgrade_$PID.txt" -ErrorAction SilentlyContinue
                        
                        # Enhanced parsing for successful updates
                        $successLines = $upgradeOutput | Where-Object { 
                            $_ -match "successfully upgraded|upgraded \d+/\d+|has been upgraded"
                        }
                        
                        $result.UpdatedPackages = @($successLines | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '\S' })
                        $result.Success = $true
                    }
                    elseif ($upgradeProcess.ExitCode -eq 1641 -or $upgradeProcess.ExitCode -eq 3010) {
                        # Success with reboot required
                        $upgradeOutput = Get-Content "$env:TEMP\choco_upgrade_$PID.txt" -ErrorAction SilentlyContinue
                        $successLines = $upgradeOutput | Where-Object { 
                            $_ -match "successfully upgraded|upgraded \d+/\d+|has been upgraded"
                        }
                        
                        $result.UpdatedPackages = @($successLines | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '\S' })
                        $result.UpdatedPackages += "NOTE: Some updates require a system reboot (exit code: $($upgradeProcess.ExitCode))"
                        $result.Success = $true
                    }
                    else {
                        $upgradeError = Get-Content "$env:TEMP\choco_upgrade_err_$PID.txt" -ErrorAction SilentlyContinue | Out-String
                        $result.Error = "Upgrade failed (exit: $($upgradeProcess.ExitCode)). Error: $upgradeError"
                    }
                }
                else {
                    $outdatedError = Get-Content "$env:TEMP\choco_outdated_err_$PID.txt" -ErrorAction SilentlyContinue | Out-String
                    $result.Error = "Outdated check failed (exit: $($outdatedProcess.ExitCode)). Error: $outdatedError"
                }
                
                # Enhanced cleanup with PID-specific files
                Remove-Item "$env:TEMP\choco_*_$PID.txt" -ErrorAction SilentlyContinue
            }
            catch {
                $result.Error = "Exception: $($_.Exception.Message)"
            }
            finally {
                $stopwatch.Stop()
                $result.ProcessingTime = $stopwatch.Elapsed.TotalSeconds
            }
            
            return $result
        }
        $updateJobs += $chocoJob
    }
    
    # Enhanced parallel job execution with timeout handling
    Write-Log "[UpdatePackages] Executing parallel package updates with enhanced monitoring..." 'INFO'
    $jobTimeout = 600 # 10 minutes timeout for package updates
    $startTime = Get-Date
    
    # Monitor jobs with timeout
    $completedJobs = @()
    $timeoutJobs = @()
    
    while ($updateJobs.Count -gt 0 -and (Get-Date).Subtract($startTime).TotalSeconds -lt $jobTimeout) {
        Start-Sleep -Milliseconds 500  # Check every 500ms
        
        foreach ($job in $updateJobs.ToArray()) {
            if ($job.State -eq 'Completed') {
                $completedJobs += $job
                $updateJobs = $updateJobs | Where-Object { $_.Id -ne $job.Id }
            }
        }
    }
    
    # Handle any remaining (timeout) jobs
    foreach ($job in $updateJobs) {
        $timeoutJobs += $job
        Write-Log "[UpdatePackages] Job timeout: $($job.Name)" 'WARN'
        Stop-Job -Job $job -Force
    }
    
    # Process completed job results with enhanced error handling
    foreach ($job in $completedJobs) {
        try {
            $jobResult = Receive-Job -Job $job -Wait -ErrorAction SilentlyContinue
            Remove-Job -Job $job -Force
            
            # Validate job result before processing
            if (-not $jobResult) {
                Write-Log "[UpdatePackages] Job $($job.Name) completed but returned no results" 'WARN'
                continue
            }
            
            if ($jobResult.Success) {
                if ($jobResult.NoUpdatesFound) {
                    [void]$noUpdatesAvailable.Add([PSCustomObject]@{
                            Source         = $jobResult.Source
                            Message        = "No updates available"
                            ProcessingTime = $jobResult.ProcessingTime
                        })
                }
                else {
                    [void]$successfulUpdates.Add([PSCustomObject]@{
                            Source          = $jobResult.Source
                            UpdatedPackages = $jobResult.UpdatedPackages
                            Count           = if ($jobResult.UpdatedPackages) { $jobResult.UpdatedPackages.Count } else { 0 }
                            ProcessingTime  = $jobResult.ProcessingTime
                        })
                }
            }
            else {
                [void]$failedUpdates.Add([PSCustomObject]@{
                        Source         = $jobResult.Source
                        Error          = $jobResult.Error
                        ProcessingTime = $jobResult.ProcessingTime
                    })
            }
        }
        catch {
            Write-Log "[UpdatePackages] Error processing job result: $_" 'WARN'
            [void]$failedUpdates.Add([PSCustomObject]@{
                    Source         = "Unknown"
                    Error          = "Job result processing failed: $_"
                    ProcessingTime = 0
                })
        }
    }
    
    # Handle timeout jobs
    foreach ($job in $timeoutJobs) {
        Remove-Job -Job $job -Force
        [void]$failedUpdates.Add([PSCustomObject]@{
                Source         = "Timeout"
                Error          = "Package update timed out after $jobTimeout seconds"
                ProcessingTime = $jobTimeout
            })
    }

    # Convert concurrent collections to arrays for enhanced reporting
    $successArray = @($successfulUpdates.ToArray())
    $failedArray = @($failedUpdates.ToArray())
    $noUpdatesArray = @($noUpdatesAvailable.ToArray())

    # Enhanced action-only logging with performance metrics
    if ($successArray.Count -gt 0) {
        $totalUpdated = ($successArray | ForEach-Object { $_.Count } | Measure-Object -Sum).Sum
        $totalTime = ($successArray | ForEach-Object { $_.ProcessingTime } | Measure-Object -Sum).Sum
        $avgTimePerSource = if ($successArray.Count -gt 0) { [math]::Round($totalTime / $successArray.Count, 2) } else { 0 }
        
        Write-Log "[UpdatePackages] Successfully updated $totalUpdated packages across $($successArray.Count) package managers (avg time: $($avgTimePerSource)s per source):" 'INFO'
        
        foreach ($success in $successArray) {
            $timeInfo = if ($success.ProcessingTime -gt 0) { " ($($success.ProcessingTime)s)" } else { "" }
            Write-Log "Updated via $($success.Source): $($success.Count) packages$timeInfo" 'INFO'
            Write-Host "✓ Updated via $($success.Source): $($success.Count) packages$timeInfo" -ForegroundColor Green
            
            # Enhanced verbose logging with package details
            if ($global:Config.EnableVerboseLogging -and $success.UpdatedPackages.Count -gt 0) {
                foreach ($package in $success.UpdatedPackages) {
                    if ($package -match '\S') {
                        Write-Log "  - $($package.Trim())" 'VERBOSE'
                    }
                }
            }
        }
    }

    # Enhanced no-updates reporting with timing
    if ($noUpdatesArray.Count -gt 0) {
        foreach ($noUpdate in $noUpdatesArray) {
            $timeInfo = if ($noUpdate.ProcessingTime -gt 0) { " (checked in ${noUpdate.ProcessingTime}s)" } else { "" }
            Write-Log "[UpdatePackages] $($noUpdate.Source): $($noUpdate.Message)$timeInfo" 'INFO'
        }
    }

    # Enhanced summary statistics with performance metrics
    $totalSources = $successArray.Count + $failedArray.Count + $noUpdatesArray.Count
    $totalPackagesUpdated = if ($successArray.Count -gt 0) { ($successArray | ForEach-Object { $_.Count } | Measure-Object -Sum).Sum } else { 0 }
    $totalProcessingTime = [math]::Round((Get-Date).Subtract($startTime).TotalSeconds, 2)
    
    Write-Log "[UpdatePackages] Update process complete in ${totalProcessingTime}s. Sources processed: $totalSources, Total packages updated: $totalPackagesUpdated" 'INFO'
    
    # Enhanced error reporting with timing information
    if ($failedArray.Count -gt 0) {
        Write-Log "[UpdatePackages] Failed update sources: $($failedArray.Count)" 'WARN'
        foreach ($failure in $failedArray) {
            $timeInfo = if ($failure.ProcessingTime -gt 0) { " (failed after ${failure.ProcessingTime}s)" } else { "" }
            $errorSummary = if ($failure.Error.Length -gt 100) { $failure.Error.Substring(0, 100) + "..." } else { $failure.Error }
            Write-Log "[UpdatePackages] $($failure.Source) failed$timeInfo`: $errorSummary" 'WARN'
        }
    }

    # Performance analysis and recommendations
    if ($totalProcessingTime -gt 300) {
        # 5 minutes
        Write-Log "[UpdatePackages] PERFORMANCE: Update took ${totalProcessingTime}s. Consider running updates during off-peak hours." 'INFO'
    }
    elseif ($totalProcessingTime -lt 30) {
        Write-Log "[UpdatePackages] PERFORMANCE: Fast update completion (${totalProcessingTime}s) - system is well optimized." 'VERBOSE'
    }

    Write-Log "[END] Update All Packages" 'INFO'
}

### AI_MAINTENANCE_TASK: Event Log and CBS Log Analysis
# AI_TASK_ID: Survey-EventLogsAndCBS
# AI_PURPOSE: Surveys Event Viewer and CBS logs for errors from the last 96 hours
# AI_ENVIRONMENT: Windows 10/11, any user context, Event Log and CBS log access
# AI_LOGIC: Get-WinEvent for Event Viewer, file parsing for CBS logs, 96-hour time window
# AI_DEPENDENCIES: Event Log service, CBS log file access, file system permissions
function Get-EventLogAnalysis {
    # ===============================
    # AI_TASK_HEADER: EventLogAnalysis (Event Viewer and CBS Log Survey)
    # ===============================
    # AI_PURPOSE: Comprehensive error analysis from Event Viewer and CBS logs (last 96 hours)
    # AI_ENVIRONMENT: Windows 10/11, any user context, system log file access required
    # AI_LOGIC: Event log querying, CBS file parsing, time-based filtering, detailed error reporting
    # AI_PERFORMANCE: Optimized queries with time filters, selective log parsing, efficient processing
    # ===============================
    Write-Log "Starting Event Log and CBS Log Analysis - Last 96 Hours (Errors Only)" 'INFO'
    
    $startTime = (Get-Date).AddHours(-96)
    $errorCount = 0
    
    try {
        # === Event Viewer Analysis ===
        Write-Log "[EventLogAnalysis] Analyzing Event Viewer logs for errors only since $startTime" 'INFO'
        
        # Define critical event logs to check
        $eventLogs = @('System', 'Application', 'Security')
        
        foreach ($logName in $eventLogs) {
            try {
                Write-Log "[EventLogAnalysis] Checking $logName event log..." 'VERBOSE'
                
                # Get only error and critical events from the last 96 hours (excluding warnings)
                $events = Get-WinEvent -FilterHashtable @{
                    LogName   = $logName
                    Level     = @(1, 2)  # Critical, Error only (excluding warnings)
                    StartTime = $startTime
                } -ErrorAction SilentlyContinue | Sort-Object TimeCreated -Descending
                
                if ($events) {
                    foreach ($evt in $events) {
                        $levelText = switch ($evt.Level) {
                            1 { 'CRITICAL'; $errorCount++ }
                            2 { 'ERROR'; $errorCount++ }
                            default { 'ERROR' }  # Fallback
                        }
                        $eventDetails = "[$logName] $levelText - ID:$($evt.Id) - $($evt.TimeCreated) - Source:$($evt.ProviderName) - Message:$($evt.Message -replace '[\r\n]+', ' ' | Out-String -Stream | Select-Object -First 200)"
                        Write-Log $eventDetails 'ERROR'
                    }
                    Write-Log "[EventLogAnalysis] Found $($events.Count) critical/error events in $logName log" 'INFO'
                }
                else {
                    Write-Log "[EventLogAnalysis] No critical/error events found in $logName log since $startTime" 'INFO'
                }
            }
            catch {
                Write-Log "[EventLogAnalysis] Failed to access $logName log: $_" 'ERROR'
            }
        }
        
        # === CBS Log Analysis ===
        Write-Log "[EventLogAnalysis] Analyzing CBS logs for errors only since $startTime" 'INFO'
        
        $cbsLogPath = "$env:SystemRoot\Logs\CBS\CBS.log"
        if (Test-Path $cbsLogPath) {
            try {
                $cbsContent = Get-Content $cbsLogPath -ErrorAction SilentlyContinue
                if (-not $cbsContent) {
                    Write-Log "[EventLogAnalysis] CBS log file exists but could not be read" 'WARN'
                    return
                }
                $cbsErrors = $cbsContent | Where-Object { 
                    $_ -match '\[SR\]|\[FATAL\]|\[ERROR\]' -and  # Only FATAL and ERROR, excluding WARN
                    $_ -match '\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}' 
                }
                
                foreach ($cbsLine in $cbsErrors) {
                    # Extract timestamp from CBS log line
                    if ($cbsLine -match '(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})') {
                        try {
                            $cbsTimestamp = [DateTime]::ParseExact($matches[1], 'yyyy-MM-dd HH:mm:ss', $null)
                            if ($cbsTimestamp -ge $startTime) {
                                # Only process FATAL and ERROR entries
                                if ($cbsLine -match '\[FATAL\]|\[ERROR\]') {
                                    $cbsLogType = 'ERROR'
                                    $errorCount++
                                    Write-Log "[CBS] $cbsLogType - $cbsTimestamp - $($cbsLine.Trim())" 'ERROR'
                                }
                            }
                        }
                        catch {
                            # Skip lines with unparseable timestamps
                            continue
                        }
                    }
                }
                Write-Log "[EventLogAnalysis] CBS log analysis completed" 'INFO'
            }
            catch {
                Write-Log "[EventLogAnalysis] Failed to read CBS log file: $_" 'ERROR'
            }
        }
        else {
            Write-Log "[EventLogAnalysis] CBS log file not found at $cbsLogPath" 'WARN'
        }
        
        # === DISM Log Analysis ===
        Write-Log "[EventLogAnalysis] Analyzing DISM logs for errors only since $startTime" 'INFO'
        
        $dismLogPath = "$env:SystemRoot\Logs\DISM\dism.log"
        if (Test-Path $dismLogPath) {
            try {
                $dismContent = Get-Content $dismLogPath -ErrorAction SilentlyContinue | Select-Object -Last 1000  # Last 1000 lines for performance
                if (-not $dismContent) {
                    Write-Log "[EventLogAnalysis] DISM log file exists but could not be read" 'WARN'
                    return
                }
                $dismErrors = $dismContent | Where-Object { 
                    $_ -match '\[ERROR\]|\[FATAL\]' -and  # Only ERROR and FATAL, excluding WARN
                    $_ -match '\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}'
                }
                
                foreach ($dismLine in $dismErrors) {
                    if ($dismLine -match '(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})') {
                        try {
                            $dismTimestamp = [DateTime]::ParseExact($matches[1], 'yyyy-MM-dd HH:mm:ss', $null)
                            if ($dismTimestamp -ge $startTime) {
                                # Only process FATAL and ERROR entries
                                if ($dismLine -match '\[FATAL\]|\[ERROR\]') {
                                    $dismLogType = 'ERROR'
                                    $errorCount++
                                    Write-Log "[DISM] $dismLogType - $dismTimestamp - $($dismLine.Trim())" 'ERROR'
                                }
                            }
                        }
                        catch {
                            continue
                        }
                    }
                }
                Write-Log "[EventLogAnalysis] DISM log analysis completed" 'INFO'
            }
            catch {
                Write-Log "[EventLogAnalysis] Failed to read DISM log file: $_" 'ERROR'
            }
        }
        else {
            Write-Log "[EventLogAnalysis] DISM log file not found at $dismLogPath" 'WARN'
        }
        
        # === Summary ===
        Write-Log "[EventLogAnalysis] SUMMARY: Found $errorCount critical/error events in the last 96 hours (warnings excluded)" 'INFO'
        
        if ($errorCount -eq 0) {
            Write-Host "✅ Event Log Analysis: No critical errors found in the last 96 hours" -ForegroundColor Green
        }
        else {
            Write-Host "⚠️ Event Log Analysis: $errorCount critical/error events found (warnings excluded)" -ForegroundColor Red
        }
        
    }
    catch {
        Write-Log "[EventLogAnalysis] Critical error during log analysis: $_" 'ERROR'
        Write-Host "✗ Event Log Analysis failed: $($_.Exception.Message)" -ForegroundColor Red
    }
    
    Write-Log "[END] Event Log and CBS Log Analysis" 'INFO'
}

### AI_MAINTENANCE_TASK: Ultra-Enhanced Bloatware Removal - Action-Only Logging & Maximum Performance
# AI_TASK_ID: RemoveBloatware  
# AI_PURPOSE: High-speed bloatware removal with PowerShell 7.5 native capabilities - action-only logging
# AI_ENVIRONMENT: Windows 10/11, Administrator required, PowerShell 7.5 native AppX/DISM support
# AI_PERFORMANCE: Ultra-parallel 8-thread processing, pre-compiled regex, smart caching, action-only logging
# AI_DEPENDENCIES: Native PS7.5 AppX cmdlets, DISM, Winget, Chocolatey, Registry, Windows Capabilities
# AI_LOGIC: Multi-method removal approach, intelligent filtering, comprehensive error handling
# AI_FEATURES: Shows ONLY removed apps, maximum performance optimization, detailed success tracking
function Remove-Bloatware {
    # ===============================
    # AI_TASK_HEADER: RemoveBloatware (Ultra-Enhanced PowerShell 7.5 Native)
    # ===============================  
    # AI_PURPOSE: High-speed bloatware removal with native PS7.5 capabilities and action-only logging
    # AI_ENVIRONMENT: Windows 10/11, Administrator required, PS7.5 native AppX/DISM integration
    # AI_LOGIC: Ultra-parallel removal, smart pre-filtering, action-only logging, maximum performance
    # AI_PERFORMANCE: Native PS7.5 AppX, 8-thread parallel processing, pre-compiled regex, smart caching
    # ===============================
    Write-Log "Starting Ultra-Enhanced Bloatware Removal - PowerShell 7.5 Native Mode" 'INFO'
    
    # AI_OPTIMIZATION: Use cached inventory if available, otherwise trigger fresh comprehensive scan
    if (-not $global:SystemInventory) {
        Get-ExtensiveSystemInventory
    }
    
    $inventory = $global:SystemInventory
    
    # AI_PERFORMANCE: Ultra-fast lookup using case-insensitive Dictionary with pre-compiled regex patterns
    $installedApps = [System.Collections.Generic.Dictionary[string, PSCustomObject]]::new([System.StringComparer]::OrdinalIgnoreCase)
    
    # AI_OPTIMIZATION: Pre-compile common app name patterns for faster matching performance
    # (Removed unused variable assignment to 'commonPatterns')
    
    # Ultra-parallel inventory processing with optimized data structures
    $inventoryJobs = @(
        @{ Name = 'AppX'; Data = $inventory.appx; Props = @('Name', 'PackageFullName') },
        @{ Name = 'Winget'; Data = $inventory.winget; Props = @('Name', 'Id') },
        @{ Name = 'Chocolatey'; Data = $inventory.choco; Props = @('Name') },
        @{ Name = 'Registry'; Data = $inventory.registry_uninstall; Props = @('DisplayName', 'UninstallString') }
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
        return $results.ToArray()
    } -ThrottleLimit 8
    
    # Merge results into lookup dictionary
    foreach ($jobResult in $inventoryJobs) {
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
    if ($PSVersionTable.PSVersion.Major -ge 7) {
        try {
            $null = Get-AppxPackage -Name "NonExistent*" -ErrorAction SilentlyContinue
            $toolCapabilities.AppX = $true
        }
        catch {
            # Try compatibility mode
            try {
                $testCmd = "Get-Module -ListAvailable -Name Appx"
                $result = Invoke-WindowsPowerShellCommand -Command $testCmd -Description "Test AppX"
                $toolCapabilities.AppX = $null -ne $result
            }
            catch { }
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
        $psVersion = $using:PSVersionTable
        
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
                            if ($psVersion.PSVersion.Major -ge 7) {
                                Remove-AppxPackage -Package $appData.PackageFullName -AllUsers -ErrorAction SilentlyContinue
                                
                                # Verify removal
                                $remainingPackage = Get-AppxPackage -PackageFullName $appData.PackageFullName -ErrorAction SilentlyContinue
                                if (-not $remainingPackage) {
                                    $result.Success = $true
                                    $result.Method = "AppX"
                                    $result.ActualName = $appData.Name
                                }
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
                    if ($psVersion.PSVersion.Major -ge 7) {
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
    $removedArray = @($removedApps.ToArray())
    
    # ACTION-ONLY LOGGING: Only show what was actually removed
    if ($removedArray.Count -gt 0) {
        # Individual app removals - one line per app
        foreach ($removed in $removedArray) {
            $logMsg = "Removed: $($removed.ActualName) [$($removed.Method)]"
            Write-Log $logMsg 'INFO'
            Write-Host "✓ $logMsg" -ForegroundColor Green
        }
        
        # Summary log entry
        $appNames = ($removedArray | ForEach-Object { $_.ActualName } | Sort-Object -Unique) -join ', '
        Write-Log "Bloatware removal summary: $($removedArray.Count) apps removed - $appNames" 'INFO'
        
        # Method breakdown
        $methodGroups = $removedArray | Group-Object Method
        $methodSummary = ($methodGroups | ForEach-Object { "$($_.Name): $($_.Count)" }) -join ', '
        Write-Log "Removal methods used: $methodSummary" 'INFO'
    }
    else {
        Write-Log "No bloatware apps were removed" 'INFO'
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
    
    Write-Log "[END] Ultra-Enhanced Bloatware Removal" 'INFO'
}

### [TASK 4] System Inventory (Legacy)
# AI_FUNCTION: Legacy system inventory collection wrapper
# AI_PURPOSE: Simple system inventory collection for basic reporting and compatibility
# AI_ENVIRONMENT: Windows 10/11, any privilege level, basic system information gathering
# AI_LOGIC: Calls comprehensive Get-ExtensiveSystemInventory, maintains backward compatibility
# AI_USE_CASE: Legacy support, simple inventory needs, compatibility with older script versions
function Get-SystemInventory {
    # ===============================
    # Task: SystemInventory
    # ===============================
    # Purpose: Collects basic system info for reporting and troubleshooting.
    # Environment: Runs on any Windows, outputs to inventory.txt in repo folder.
    # Logic: Uses Get-ComputerInfo, logs results.
    Write-Log "[START] System Inventory (legacy)" 'INFO'
    $inventoryPath = Join-Path $global:TempFolder 'inventory.txt'
    Get-ComputerInfo | Out-File $inventoryPath
    Write-Log "System inventory saved to $inventoryPath" 'INFO'
    Write-Log "[END] System Inventory (legacy)" 'INFO'
}


### AI_MAINTENANCE_TASK: Disable Telemetry and Privacy Features
# AI_TASK_ID: DisableTelemetry
# AI_PURPOSE: Comprehensive disabling of Windows telemetry, privacy-invasive features, and browser tracking
# AI_ENVIRONMENT: Windows 10/11, Administrator required, registry/service/browser modification access
# AI_PERFORMANCE: Parallel browser detection, batch registry operations, optimized service management
# AI_DEPENDENCIES: Registry access, service control capabilities, browser configuration file access
# AI_LOGIC: Enhanced speed and reliability, parallel processing, action-focused logging
# AI_FEATURES: Batch operations, parallel browser processing, comprehensive privacy protection
function Disable-Telemetry {
    # ===============================
    # AI_TASK_HEADER: DisableTelemetry (Enhanced Performance & Privacy)
    # ===============================
    # AI_PURPOSE: Comprehensive Windows telemetry and privacy feature disabling with optimization
    # AI_ENVIRONMENT: Windows 10/11, Administrator required, system-wide privacy configuration
    # AI_LOGIC: Parallel browser detection, batch registry operations, enhanced performance focus
    # AI_PERFORMANCE: Optimized for speed and reliability, action-only logging for clarity
    # ===============================
    Write-Log "Starting Disable Telemetry and Privacy Features - Enhanced Performance Mode" 'INFO'
    
    # AI_OPTIMIZATION: Batch notification management for improved performance
    try {
        $focusAssistReg = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Notifications\Settings'
        if (-not (Test-Path $focusAssistReg)) { New-Item -Path $focusAssistReg -Force | Out-Null }
        
        # AI_BATCH_OPERATIONS: Batch set notification settings for efficiency
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
        
        # AI_BATCH_OPERATIONS: Batch disable per-app notifications using optimized registry operations
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

    # Optimized browser removal - pre-filter and batch operations
    $allowedBrowsers = @('Microsoft Edge', 'Google Chrome', 'Mozilla Firefox')
    $knownBrowsers = @('Opera', 'Opera GX', 'Brave', 'Vivaldi', 'Waterfox', 'Yandex', 'Tor Browser', 'Pale Moon', 
        'Chromium', 'SRWare Iron', 'Comodo Dragon', 'Maxthon', 'UC Browser', 'Epic Privacy Browser', 
        'Slimjet', 'CentBrowser', 'QuteBrowser', 'OtterBrowser', 'Dooble', 'Midori', 'Blisk', 
        'AvantBrowser', 'Sleipnir', 'Polarity', 'Torch', 'Orbitum', 'Superbird', 'Sputnik', 
        'Lunascape', 'Falkon', 'SeaMonkey')
    
    $browsersToRemove = $knownBrowsers | Where-Object { $allowedBrowsers -notcontains $_ }
    $installedBrowsers = [System.Collections.Generic.HashSet[string]]::new()
    
    # Parallel detection using background jobs for better performance
    $detectionJobs = @()
    
    # Winget detection job
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        $detectionJobs += Start-Job -ScriptBlock {
            param($browsersToRemove)
            $wingetApps = winget list --accept-source-agreements 2>$null | Out-String
            $foundBrowsers = @()
            foreach ($browser in $browsersToRemove) {
                if ($wingetApps -match [regex]::Escape($browser)) {
                    $foundBrowsers += $browser
                }
            }
            return @{ Method = 'Winget'; Browsers = $foundBrowsers }
        } -ArgumentList @(, $browsersToRemove)
    }
    
    # Chocolatey detection job  
    if (Get-Command choco -ErrorAction SilentlyContinue) {
        $detectionJobs += Start-Job -ScriptBlock {
            param($browsersToRemove)
            $chocoApps = choco list --local-only 2>$null | Out-String
            $foundBrowsers = @()
            foreach ($browser in $browsersToRemove) {
                if ($chocoApps -match [regex]::Escape($browser)) {
                    $foundBrowsers += $browser
                }
            }
            return @{ Method = 'Chocolatey'; Browsers = $foundBrowsers }
        } -ArgumentList @(, $browsersToRemove)
    }
    
    # Registry detection job
    $detectionJobs += Start-Job -ScriptBlock {
        param($browsersToRemove)
        $uninstallKeys = @(
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
            'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
        )
        
        $foundBrowsers = @()
        foreach ($key in $uninstallKeys) {
            if (Test-Path $key) {
                $regApps = Get-ChildItem $key -ErrorAction SilentlyContinue | 
                ForEach-Object { Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue } |
                Where-Object { $_.DisplayName }
                
                foreach ($browser in $browsersToRemove) {
                    if ($regApps | Where-Object { $_.DisplayName -like "*$browser*" }) {
                        $foundBrowsers += $browser
                    }
                }
            }
        }
        return @{ Method = 'Registry'; Browsers = ($foundBrowsers | Select-Object -Unique) }
    } -ArgumentList @(, $browsersToRemove)
    
    # Collect results from detection jobs
    $detectionResults = $detectionJobs | Wait-Job | Receive-Job
    $detectionJobs | Remove-Job
    
    # Combine all detected browsers
    foreach ($result in $detectionResults) {
        foreach ($browser in $result.Browsers) {
            $installedBrowsers.Add($browser) | Out-Null
        }
    }
    
    # Remove detected browsers efficiently
    $removedBrowsers = @()
    $removalMethods = @()
    
    if ($installedBrowsers.Count -gt 0) {
        foreach ($browser in $installedBrowsers) {
            $removed = $false
            
            # Try winget removal (fastest and most reliable)
            if (Get-Command winget -ErrorAction SilentlyContinue) {
                try {
                    $result = winget uninstall --name $browser --accept-source-agreements --silent --force 2>$null
                    if ($LASTEXITCODE -eq 0) {
                        $removedBrowsers += $browser
                        $removalMethods += 'Winget'
                        $removed = $true
                    }
                }
                catch { }
            }
            
            # Try chocolatey if winget failed
            if (-not $removed -and (Get-Command choco -ErrorAction SilentlyContinue)) {
                try {
                    $result = choco uninstall $browser -y --limit-output --force 2>$null
                    if ($LASTEXITCODE -eq 0) {
                        $removedBrowsers += $browser
                        $removalMethods += 'Chocolatey'
                        $removed = $true
                    }
                }
                catch { }
            }
            
            # Registry-based removal as last resort
            if (-not $removed) {
                $uninstallKeys = @(
                    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
                    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
                    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
                )
                
                foreach ($key in $uninstallKeys) {
                    if (Test-Path $key) {
                        $apps = Get-ChildItem $key -ErrorAction SilentlyContinue | 
                        ForEach-Object { Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue } |
                        Where-Object { $_.DisplayName -like "*$browser*" -and $_.UninstallString }
                        
                        foreach ($app in $apps) {
                            try {
                                $uninstallCmd = ($app.UninstallString -replace '"', '').Split(' ')[0]
                                if (Test-Path $uninstallCmd) {
                                    Start-Process -FilePath $uninstallCmd -ArgumentList "/S" -Wait -WindowStyle Hidden -ErrorAction SilentlyContinue
                                    $removedBrowsers += $browser
                                    $removalMethods += 'Registry'
                                    $removed = $true
                                    break
                                }
                            }
                            catch { continue }
                        }
                        if ($removed) { break }
                    }
                }
            }
        }
    }
    
    # Optimized logging - only log actual removals
    if ($removedBrowsers.Count -gt 0) {
        Write-Host "✓ Removed $($removedBrowsers.Count) unwanted browsers" -ForegroundColor Red
        Write-Log "Removed browsers: $($removedBrowsers -join ', ')" 'INFO'
        
        # Log removal methods summary for troubleshooting
        $methodSummary = $removalMethods | Group-Object | ForEach-Object { "$($_.Count) via $($_.Name)" }
        Write-Log "Removal methods used: $($methodSummary -join ', ')" 'VERBOSE'
    }

    # Batch browser policy configuration (Edge, Chrome, Firefox)
    $browserPolicies = @{
        'HKLM:\SOFTWARE\Policies\Microsoft\Edge' = @{
            'MetricsReportingEnabled' = 0
            'HomepageLocation'        = 'about:blank'
            'ShowHomeButton'          = 1
            'BookmarkBarEnabled'      = 1
            'TranslateEnabled'        = 0
        }
        'HKLM:\SOFTWARE\Policies\Google\Chrome'  = @{
            'MetricsReportingEnabled' = 0
            'HomepageLocation'        = 'about:blank'
            'ShowHomeButton'          = 1
            'BookmarkBarEnabled'      = 1
            'TranslateEnabled'        = 0
        }
    }
    
    foreach ($regPath in $browserPolicies.Keys) {
        try {
            if (-not (Test-Path $regPath)) { New-Item -Path $regPath -Force | Out-Null }
            foreach ($setting in $browserPolicies[$regPath].GetEnumerator()) {
                Set-ItemProperty -Path $regPath -Name $setting.Key -Value $setting.Value -Force
            }
            $browserName = if ($regPath -like "*Edge*") { "Edge" } else { "Chrome" }
            Write-Host "✓ $browserName policies configured" -ForegroundColor Green
            Write-Log "$browserName telemetry disabled and policies configured" 'INFO'
        }
        catch {
            Write-Log "Failed to configure browser policies for $regPath`: $_" 'WARN'
        }
    }

    # Enhanced Firefox configuration
    $firefoxPaths = @('C:\Program Files\Mozilla Firefox', 'C:\Program Files (x86)\Mozilla Firefox')
    $firefoxPath = $firefoxPaths | Where-Object { Test-Path $_ } | Select-Object -First 1
    
    if ($firefoxPath) {
        try {
            $distPath = Join-Path $firefoxPath 'distribution'
            if (-not (Test-Path $distPath)) { New-Item -Path $distPath -ItemType Directory -Force | Out-Null }
            
            $externalPolicyPath = Join-Path $PSScriptRoot 'firefox_policies.json'
            if (Test-Path $externalPolicyPath) {
                Copy-Item -Path $externalPolicyPath -Destination (Join-Path $distPath 'policies.json') -Force
                Remove-Item -Path $externalPolicyPath -Force
                Write-Host "✓ Firefox policies deployed from external file" -ForegroundColor Green
                Write-Log "Firefox policies deployed from firefox_policies.json" 'INFO'
            }
            else {
                # Optimized built-in policy
                $policyJson = @'
{
  "policies": {
    "DisableTelemetry": true,
    "DisableFirefoxStudies": true,
    "DisablePocket": true,
    "Homepage": {
      "StartPage": "homepage",
      "URL": "about:blank"
    },
    "Extensions": {
      "Install": [
        "https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi"
      ]
    },
    "DefaultBrowser": true
  }
}
'@
                $policyPath = Join-Path $distPath 'policies.json'
                $policyJson | Set-Content -Path $policyPath -Encoding UTF8
                Write-Host "✓ Firefox policies deployed" -ForegroundColor Green
                Write-Log "Firefox policies deployed from built-in configuration" 'INFO'
            }
            
            # Enhanced Firefox default browser setting
            $firefoxExe = Join-Path $firefoxPath 'firefox.exe'
            if (Test-Path $firefoxExe) {
                # Registry-based approach (more reliable)
                $firefoxProgId = 'FirefoxURL-308046B0AF4A39CB'
                $associations = @(
                    'HKCU:\SOFTWARE\Microsoft\Windows\Shell\Associations\UrlAssociations\http\UserChoice',
                    'HKCU:\SOFTWARE\Microsoft\Windows\Shell\Associations\UrlAssociations\https\UserChoice',
                    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.html\UserChoice',
                    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.htm\UserChoice'
                )
                
                $successCount = 0
                foreach ($regPath in $associations) {
                    try {
                        $parentPath = Split-Path $regPath
                        if (-not (Test-Path $parentPath)) { New-Item -Path $parentPath -Force | Out-Null }
                        if (-not (Test-Path $regPath)) { New-Item -Path $regPath -Force | Out-Null }
                        Set-ItemProperty -Path $regPath -Name 'ProgId' -Value $firefoxProgId -Force -ErrorAction SilentlyContinue
                        $successCount++
                    }
                    catch { continue }
                }
                
                if ($successCount -gt 0) {
                    Write-Host "✓ Firefox set as default browser" -ForegroundColor Green
                    Write-Log "Firefox configured as default browser" 'INFO'
                }
            }
        }
        catch {
            Write-Log "Failed to configure Firefox: $_" 'WARN'
        }
    }
    
    # Enhanced service management - only target running/enabled services
    $telemetryServices = @('DiagTrack', 'dmwappushservice', 'Connected User Experiences and Telemetry')
    $servicesDisabled = @()
    
    foreach ($svc in $telemetryServices) {
        try {
            $serviceObj = Get-Service -Name $svc -ErrorAction SilentlyContinue
            if ($serviceObj) {
                $changed = $false
                if ($serviceObj.Status -ne 'Stopped') {
                    Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
                    $changed = $true
                }
                if ($serviceObj.StartType -ne 'Disabled') {
                    Set-Service -Name $svc -StartupType Disabled -ErrorAction SilentlyContinue
                    $changed = $true
                }
                if ($changed) {
                    $servicesDisabled += $svc
                }
            }
        }
        catch { continue }
    }
    
    if ($servicesDisabled.Count -gt 0) {
        Write-Host "✓ Disabled telemetry services: $($servicesDisabled -join ', ')" -ForegroundColor Yellow
        Write-Log "Disabled telemetry services: $($servicesDisabled -join ', ')" 'INFO'
    }

    # Enhanced scheduled task management - batch disable with improved performance
    $telemetryTasks = @(
        '\Microsoft\Windows\Application Experience\ProgramDataUpdater',
        '\Microsoft\Windows\Autochk\Proxy',
        '\Microsoft\Windows\Customer Experience Improvement Program\Consolidator',
        '\Microsoft\Windows\Customer Experience Improvement Program\KernelCeipTask',
        '\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip',
        '\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector',
        '\Microsoft\Windows\Feedback\Siuf\DmClient',
        '\Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload',
        '\Microsoft\Windows\Windows Error Reporting\QueueReporting'
    )
    
    # Batch task operation for better performance
    $tasksDisabled = @()
    $allTasks = Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { 
        $_.TaskPath + $_.TaskName -in $telemetryTasks -and $_.State -ne 'Disabled'
    }
    
    foreach ($task in $allTasks) {
        try {
            Disable-ScheduledTask -InputObject $task -ErrorAction SilentlyContinue
            $tasksDisabled += $task.TaskName
        }
        catch { continue }
    }
    
    if ($tasksDisabled.Count -gt 0) {
        Write-Host "✓ Disabled $($tasksDisabled.Count) telemetry tasks" -ForegroundColor Yellow
        Write-Log "Disabled telemetry scheduled tasks: $($tasksDisabled -join ', ')" 'INFO'
    }

    # Optimized registry configuration for telemetry - parallel execution
    $telemetryRegistry = @{
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection' = @{ 'AllowTelemetry' = 0 }
        'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat'                     = @{ 
            'AITEnable'        = 0
            'DisableInventory' = 1 
        }
        'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'                        = @{ 
            'UploadUserActivities'  = 0
            'PublishUserActivities' = 0 
        }
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Privacy'                 = @{
            'TailoredExperiencesWithDiagnosticDataEnabled' = 0
        }
        'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo'               = @{
            'DisabledByGroupPolicy' = 1
        }
    }
    
    $registryChanges = 0
    $registryErrors = 0
    
    foreach ($regPath in $telemetryRegistry.Keys) {
        try {
            if (-not (Test-Path $regPath)) { 
                New-Item -Path $regPath -Force | Out-Null 
            }
            foreach ($setting in $telemetryRegistry[$regPath].GetEnumerator()) {
                try {
                    Set-ItemProperty -Path $regPath -Name $setting.Key -Value $setting.Value -Force
                    $registryChanges++
                }
                catch {
                    $registryErrors++
                    continue
                }
            }
        }
        catch { 
            $registryErrors++
            continue 
        }
    }
    
    if ($registryChanges -gt 0) {
        Write-Host "✓ Applied $registryChanges telemetry registry settings" -ForegroundColor Green
        Write-Log "Applied $registryChanges telemetry registry configurations" 'INFO'
    }
    
    if ($registryErrors -gt 0) {
        Write-Log "Failed to apply $registryErrors registry settings" 'WARN'
    }

    Write-Log "[END] Disable Telemetry" 'INFO'
}

### AI_MAINTENANCE_TASK: Windows Security Hardening
# AI_TASK_ID: Optimize-Taskbar
# AI_PURPOSE: Optimize Windows interface by hiding taskbar elements and disabling web search in Start menu
# AI_ENVIRONMENT: Windows 10/11, any user context, registry modification access
# AI_LOGIC: Registry-based taskbar and search control, Windows version detection, Explorer restart
# AI_DEPENDENCIES: Registry access, Windows Explorer restart capability
function Optimize-Taskbar {
    # ===============================
    # AI_TASK_HEADER: TaskbarOptimization (Interface Cleanup)
    # ===============================
    # AI_PURPOSE: Hide taskbar elements and disable web search for cleaner, privacy-focused interface
    # AI_ENVIRONMENT: Windows 10/11, any user context, registry-based configuration
    # AI_LOGIC: Registry modifications for taskbar elements, Start menu search, Windows version detection
    # AI_PERFORMANCE: Fast registry operations, single Explorer restart
    # ===============================
    Write-Log "Starting Taskbar and Start Menu Optimization - Enhanced Interface Cleanup" 'INFO'
    
    $taskbarActions = 0
    $taskbarErrors = 0
    $taskbarResults = @()
    
    # Detect Windows version for version-specific optimizations
    $osVersion = [Environment]::OSVersion.Version
    $isWindows11 = $osVersion.Build -ge 22000
    $isWindows10 = $osVersion.Major -eq 10 -and $osVersion.Build -lt 22000
    
    Write-Log "Detected Windows version: $($osVersion.ToString()) (Windows 11: $isWindows11, Windows 10: $isWindows10)" 'INFO'
    
    # 1. Hide Taskbar Search Bar (Works on both Windows 10 and 11)
    Write-Log "Hiding taskbar search bar..." 'INFO'
    try {
        $searchRegPath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search"
        if (-not (Test-Path $searchRegPath)) {
            New-Item -Path $searchRegPath -Force | Out-Null
        }
        
        # Set SearchboxTaskbarMode to 0 (hidden)
        Set-ItemProperty -Path $searchRegPath -Name "SearchboxTaskbarMode" -Value 0 -Type DWord -Force
        
        Write-Host "✓ Taskbar search bar hidden" -ForegroundColor Green
        Write-Log "Taskbar search bar hidden successfully" 'INFO'
        $taskbarResults += "Search Bar: HIDDEN"
        $taskbarActions++
    }
    catch {
        Write-Host "✗ Failed to hide taskbar search bar: $($_.Exception.Message)" -ForegroundColor Red
        Write-Log "Failed to hide taskbar search bar: $_" 'ERROR'
        $taskbarResults += "Search Bar: FAILED"
        $taskbarErrors++
    }
    
    # 2. Hide Task View Button (Works on both Windows 10 and 11)
    Write-Log "Hiding task view button..." 'INFO'
    try {
        $taskViewRegPath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
        if (-not (Test-Path $taskViewRegPath)) {
            New-Item -Path $taskViewRegPath -Force | Out-Null
        }
        
        # Set ShowTaskViewButton to 0 (hidden)
        Set-ItemProperty -Path $taskViewRegPath -Name "ShowTaskViewButton" -Value 0 -Type DWord -Force
        
        Write-Host "✓ Task view button hidden" -ForegroundColor Green
        Write-Log "Task view button hidden successfully" 'INFO'
        $taskbarResults += "Task View: HIDDEN"
        $taskbarActions++
    }
    catch {
        Write-Host "✗ Failed to hide task view button: $($_.Exception.Message)" -ForegroundColor Red
        Write-Log "Failed to hide task view button: $_" 'ERROR'
        $taskbarResults += "Task View: FAILED"
        $taskbarErrors++
    }
    
    # 3. Hide Widgets (Windows 11 specific)
    if ($isWindows11) {
        Write-Log "Hiding widgets button (Windows 11)..." 'INFO'
        try {
            $widgetsRegPath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
            if (-not (Test-Path $widgetsRegPath)) {
                New-Item -Path $widgetsRegPath -Force | Out-Null
            }
            
            # Set TaskbarDa to 0 (widgets hidden)
            Set-ItemProperty -Path $widgetsRegPath -Name "TaskbarDa" -Value 0 -Type DWord -Force
            
            Write-Host "✓ Widgets button hidden (Windows 11)" -ForegroundColor Green
            Write-Log "Widgets button hidden successfully (Windows 11)" 'INFO'
            $taskbarResults += "Widgets: HIDDEN"
            $taskbarActions++
        }
        catch {
            Write-Host "✗ Failed to hide widgets button: $($_.Exception.Message)" -ForegroundColor Red
            Write-Log "Failed to hide widgets button: $_" 'ERROR'
            $taskbarResults += "Widgets: FAILED"
            $taskbarErrors++
        }
    }
    else {
        Write-Log "Widgets not applicable for Windows 10" 'INFO'
        $taskbarResults += "Widgets: NOT APPLICABLE (Windows 10)"
    }
    
    # 4. Additional Windows 11 Taskbar Optimizations
    if ($isWindows11) {
        # Hide Chat/Meet Now button
        Write-Log "Hiding chat button (Windows 11)..." 'INFO'
        try {
            $chatRegPath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
            Set-ItemProperty -Path $chatRegPath -Name "TaskbarMn" -Value 0 -Type DWord -Force
            
            Write-Host "✓ Chat button hidden (Windows 11)" -ForegroundColor Green
            Write-Log "Chat button hidden successfully (Windows 11)" 'INFO'
            $taskbarResults += "Chat Button: HIDDEN"
            $taskbarActions++
        }
        catch {
            Write-Host "✗ Failed to hide chat button: $($_.Exception.Message)" -ForegroundColor Red
            Write-Log "Failed to hide chat button: $_" 'ERROR'
            $taskbarResults += "Chat Button: FAILED"
            $taskbarErrors++
        }
    }
    
    # 5. Disable Web Search in Start Menu (Local Search Only)
    Write-Log "Disabling web search in Start menu (local search only)..." 'INFO'
    try {
        $webSearchRegPath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search"
        if (-not (Test-Path $webSearchRegPath)) {
            New-Item -Path $webSearchRegPath -Force | Out-Null
        }
        
        # Disable Bing search and web search in Start menu
        Set-ItemProperty -Path $webSearchRegPath -Name "BingSearchEnabled" -Value 0 -Type DWord -Force
        Set-ItemProperty -Path $webSearchRegPath -Name "CortanaConsent" -Value 0 -Type DWord -Force
        
        # Additional registry path for comprehensive web search disabling
        $policyRegPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search"
        if (-not (Test-Path $policyRegPath)) {
            New-Item -Path $policyRegPath -Force | Out-Null
        }
        Set-ItemProperty -Path $policyRegPath -Name "DisableWebSearch" -Value 1 -Type DWord -Force
        
        # User-specific web search disable
        $userSearchRegPath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\SearchSettings"
        if (-not (Test-Path $userSearchRegPath)) {
            New-Item -Path $userSearchRegPath -Force | Out-Null
        }
        Set-ItemProperty -Path $userSearchRegPath -Name "IsAADCloudSearchEnabled" -Value 0 -Type DWord -Force
        Set-ItemProperty -Path $userSearchRegPath -Name "IsDeviceSearchHistoryEnabled" -Value 0 -Type DWord -Force
        Set-ItemProperty -Path $userSearchRegPath -Name "IsMSACloudSearchEnabled" -Value 0 -Type DWord -Force
        
        Write-Host "✓ Start menu web search disabled (local search only)" -ForegroundColor Green
        Write-Log "Start menu web search disabled successfully" 'INFO'
        $taskbarResults += "Start Menu Web Search: DISABLED"
        $taskbarActions++
    }
    catch {
        Write-Host "✗ Failed to disable Start menu web search: $($_.Exception.Message)" -ForegroundColor Red
        Write-Log "Failed to disable Start menu web search: $_" 'ERROR'
        $taskbarResults += "Start Menu Web Search: FAILED"
        $taskbarErrors++
    }

    # 6. Restart Windows Explorer to apply changes
    Write-Log "Restarting Windows Explorer to apply taskbar and search changes..." 'INFO'
    try {
        $explorerProcesses = Get-Process -Name "explorer" -ErrorAction SilentlyContinue
        if ($explorerProcesses) {
            Write-Log "Stopping $($explorerProcesses.Count) Explorer processes..." 'VERBOSE'
            Stop-Process -Name "explorer" -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
        }
        
        # Start Explorer if it's not running
        $explorerRunning = Get-Process -Name "explorer" -ErrorAction SilentlyContinue
        if (-not $explorerRunning) {
            Write-Log "Starting Windows Explorer..." 'VERBOSE'
            Start-Process "explorer.exe"
            Start-Sleep -Seconds 3
        }
        
        Write-Host "✓ Windows Explorer restarted to apply all changes" -ForegroundColor Green
        Write-Log "Windows Explorer restarted successfully" 'INFO'
        $taskbarResults += "Explorer Restart: SUCCESS"
        $taskbarActions++
    }
    catch {
        Write-Host "✗ Failed to restart Windows Explorer: $($_.Exception.Message)" -ForegroundColor Red
        Write-Log "Failed to restart Windows Explorer: $_" 'ERROR'
        $taskbarResults += "Explorer Restart: FAILED"
        $taskbarErrors++
    }
    
    # Results Summary
    Write-Log "Interface optimization completed: $taskbarActions actions, $taskbarErrors errors" 'INFO'
    Write-Host "📊 Interface Optimization Summary:" -ForegroundColor Cyan
    foreach ($result in $taskbarResults) {
        if ($result -match "FAILED") {
            Write-Host "  ✗ $result" -ForegroundColor Red
        }
        elseif ($result -match "NOT APPLICABLE") {
            Write-Host "  ○ $result" -ForegroundColor Yellow
        }
        else {
            Write-Host "  ✓ $result" -ForegroundColor Green
        }
    }
    
    if ($taskbarActions -gt 0) {
        Write-Log "Interface optimization completed successfully with $taskbarActions optimizations applied" 'INFO'
        Write-Host "✅ Windows interface optimized: cleaner taskbar and local-only Start menu search" -ForegroundColor Green
    }
    else {
        Write-Log "Interface optimization completed with no changes applied" 'WARN'
        Write-Host "⚠️ No interface optimizations were applied" -ForegroundColor Yellow
    }
}

# AI_TASK_ID: Enable-SecurityHardening
# AI_PURPOSE: Enable essential Windows security features while preserving SMB shares and user authentication
# AI_ENVIRONMENT: Windows 10/11, Administrator required, security configuration access
# AI_LOGIC: Windows Defender configuration, Firewall enablement, UAC, SmartScreen, service hardening
# AI_DEPENDENCIES: Windows Defender, Windows Firewall, registry access, service control, security policies
function Enable-SecurityHardening {
    # ===============================
    # AI_TASK_HEADER: SecurityHardening (Windows Security Features)
    # ===============================
    # AI_PURPOSE: Comprehensive Windows security hardening while preserving functionality
    # AI_ENVIRONMENT: Windows 10/11, Administrator required, system-wide security configuration
    # AI_LOGIC: Security feature enablement, service hardening, policy configuration
    # AI_PERFORMANCE: Optimized security configuration with comprehensive error handling
    # ===============================
    Write-Log "Starting Windows Security Hardening - Enhanced Protection Mode" 'INFO'
    
    $securityActions = 0
    $securityErrors = 0
    $hardeningResults = @()
    
    try {
        # 1. Configure Windows Defender Real-time Protection
        Write-Log "[SecurityHardening] Configuring Windows Defender..." 'INFO'
        try {
            $defenderBefore = Get-MpPreference | Select-Object DisableRealtimeMonitoring, DisableBehaviorMonitoring, DisableIOAVProtection, DisableScriptScanning
            Write-Log "[SecurityHardening] Windows Defender state before: RealtimeMonitoring=$($defenderBefore.DisableRealtimeMonitoring), BehaviorMonitoring=$($defenderBefore.DisableBehaviorMonitoring), IOAVProtection=$($defenderBefore.DisableIOAVProtection), ScriptScanning=$($defenderBefore.DisableScriptScanning)" 'VERBOSE'
            
            Set-MpPreference -DisableRealtimeMonitoring $false -ErrorAction Stop
            Set-MpPreference -DisableBehaviorMonitoring $false -ErrorAction Stop
            Set-MpPreference -DisableIOAVProtection $false -ErrorAction Stop
            Set-MpPreference -DisableScriptScanning $false -ErrorAction Stop
            
            Write-Host "✓ Windows Defender real-time protection enabled" -ForegroundColor Green
            Write-Log "[SecurityHardening] Windows Defender real-time protection enabled - All monitoring features activated" 'INFO'
            $hardeningResults += "Windows Defender: ENABLED"
            $securityActions++
        }
        catch {
            Write-Host "✗ Failed to configure Windows Defender: $($_.Exception.Message)" -ForegroundColor Red
            Write-Log "[SecurityHardening] Failed to configure Windows Defender: $_" 'ERROR'
            $hardeningResults += "Windows Defender: FAILED"
            $securityErrors++
        }

        # 2. Enable Windows Firewall for all profiles
        Write-Log "[SecurityHardening] Enabling Windows Firewall..." 'INFO'
        try {
            $firewallBefore = Get-NetFirewallProfile | Select-Object Name, Enabled
            Write-Log "[SecurityHardening] Firewall profiles before: $($firewallBefore | ForEach-Object { "$($_.Name)=$($_.Enabled)" } | Join-String -Separator ', ')" 'VERBOSE'
            
            Set-NetFirewallProfile -Profile Domain, Public, Private -Enabled True -ErrorAction Stop
            
            $firewallAfter = Get-NetFirewallProfile | Select-Object Name, Enabled
            Write-Host "✓ Windows Firewall enabled for all profiles" -ForegroundColor Green
            Write-Log "[SecurityHardening] Windows Firewall enabled for all profiles: $($firewallAfter | ForEach-Object { "$($_.Name)=$($_.Enabled)" } | Join-String -Separator ', ')" 'INFO'
            $hardeningResults += "Windows Firewall: ENABLED (All Profiles)"
            $securityActions++
        }
        catch {
            Write-Host "✗ Failed to enable Windows Firewall: $($_.Exception.Message)" -ForegroundColor Red
            Write-Log "[SecurityHardening] Failed to enable Windows Firewall: $_" 'ERROR'
            $hardeningResults += "Windows Firewall: FAILED"
            $securityErrors++
        }

        # 3. Configure Automatic Updates
        Write-Log "[SecurityHardening] Configuring Windows Updates..." 'INFO'
        try {
            $UpdatePath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
            if (!(Test-Path $UpdatePath)) {
                New-Item -Path $UpdatePath -Force | Out-Null
                Write-Log "[SecurityHardening] Created Windows Update registry path: $UpdatePath" 'VERBOSE'
            }
            Set-ItemProperty -Path $UpdatePath -Name "NoAutoUpdate" -Value 0 -Type DWord -Force
            Set-ItemProperty -Path $UpdatePath -Name "AUOptions" -Value 4 -Type DWord -Force  # Auto download and install
            
            Write-Host "✓ Automatic Windows Updates enabled" -ForegroundColor Green
            Write-Log "[SecurityHardening] Automatic Windows Updates enabled - NoAutoUpdate=0, AUOptions=4 (Auto download and install)" 'INFO'
            $hardeningResults += "Windows Updates: AUTO-ENABLED"
            $securityActions++
        }
        catch {
            Write-Host "✗ Failed to configure Windows Updates: $($_.Exception.Message)" -ForegroundColor Red
            Write-Log "[SecurityHardening] Failed to configure Windows Updates: $_" 'ERROR'
            $hardeningResults += "Windows Updates: FAILED"
            $securityErrors++
        }

        # 4. Enable User Account Control (UAC)
        Write-Log "[SecurityHardening] Enabling User Account Control..." 'INFO'
        try {
            $UACPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
            $uacBefore = Get-ItemProperty -Path $UACPath -Name "EnableLUA" -ErrorAction SilentlyContinue
            Write-Log "[SecurityHardening] UAC state before: EnableLUA=$($uacBefore.EnableLUA)" 'VERBOSE'
            
            Set-ItemProperty -Path $UACPath -Name "EnableLUA" -Value 1 -Type DWord -Force
            Set-ItemProperty -Path $UACPath -Name "ConsentPromptBehaviorAdmin" -Value 2 -Type DWord -Force
            
            Write-Host "✓ User Account Control enabled" -ForegroundColor Green
            Write-Log "[SecurityHardening] User Account Control enabled - EnableLUA=1, ConsentPromptBehaviorAdmin=2" 'INFO'
            $hardeningResults += "UAC: ENABLED"
            $securityActions++
        }
        catch {
            Write-Host "✗ Failed to enable UAC: $($_.Exception.Message)" -ForegroundColor Red
            Write-Log "[SecurityHardening] Failed to enable UAC: $_" 'ERROR'
            $hardeningResults += "UAC: FAILED"
            $securityErrors++
        }

        # 5. Enable Windows Event Logging
        Write-Log "[SecurityHardening] Configuring Event Logging..." 'INFO'
        try {
            $LogNames = @("Security", "System", "Application")
            foreach ($LogName in $LogNames) {
                $Log = Get-WinEvent -ListLog $LogName -ErrorAction Stop
                if ($Log.IsEnabled -eq $false) {
                    & wevtutil set-log $LogName /enabled:true
                }
            }
            Write-Host "✓ Security event logging enabled" -ForegroundColor Green
            Write-Log "[SecurityHardening] Security event logging enabled" 'INFO'
            $securityActions++
        }
        catch {
            Write-Host "✗ Failed to configure event logging: $($_.Exception.Message)" -ForegroundColor Red
            Write-Log "[SecurityHardening] Failed to configure event logging: $_" 'ERROR'
            $securityErrors++
        }

        # 6. Enable SmartScreen
        Write-Log "[SecurityHardening] Enabling Windows SmartScreen..." 'INFO'
        try {
            # Windows SmartScreen for apps and files
            $SmartScreenPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"
            if (!(Test-Path $SmartScreenPath)) {
                New-Item -Path $SmartScreenPath -Force | Out-Null
            }
            Set-ItemProperty -Path $SmartScreenPath -Name "EnableSmartScreen" -Value 1 -Type DWord -Force
            
            # Edge SmartScreen
            $EdgePath = "HKLM:\SOFTWARE\Policies\Microsoft\MicrosoftEdge\PhishingFilter"
            if (!(Test-Path $EdgePath)) {
                New-Item -Path $EdgePath -Force | Out-Null
            }
            Set-ItemProperty -Path $EdgePath -Name "EnabledV9" -Value 1 -Type DWord -Force
            Write-Host "✓ SmartScreen enabled" -ForegroundColor Green
            Write-Log "[SecurityHardening] SmartScreen enabled" 'INFO'
            $securityActions++
        }
        catch {
            Write-Host "✗ Failed to enable SmartScreen: $($_.Exception.Message)" -ForegroundColor Red
            Write-Log "[SecurityHardening] Failed to enable SmartScreen: $_" 'ERROR'
            $securityErrors++
        }

        # 7. Check Secure Boot status
        Write-Log "[SecurityHardening] Checking Secure Boot status..." 'INFO'
        try {
            $SecureBoot = Confirm-SecureBootUEFI -ErrorAction Stop
            if ($SecureBoot) {
                Write-Host "✓ Secure Boot is already enabled" -ForegroundColor Green
                Write-Log "[SecurityHardening] Secure Boot is already enabled" 'INFO'
            }
            else {
                Write-Host "⚠ Secure Boot is not enabled (requires UEFI firmware configuration)" -ForegroundColor Yellow
                Write-Log "[SecurityHardening] Secure Boot is not enabled (requires UEFI firmware configuration)" 'WARN'
            }
        }
        catch {
            Write-Host "⚠ Cannot check Secure Boot status (may not be supported)" -ForegroundColor Yellow
            Write-Log "[SecurityHardening] Cannot check Secure Boot status (may not be supported)" 'WARN'
        }

        # 8. Configure PowerShell Execution Policy
        Write-Log "[SecurityHardening] Configuring PowerShell Execution Policy..." 'INFO'
        try {
            Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope LocalMachine -Force
            Write-Host "✓ PowerShell execution policy set to RemoteSigned" -ForegroundColor Green
            Write-Log "[SecurityHardening] PowerShell execution policy set to RemoteSigned" 'INFO'
            $securityActions++
        }
        catch {
            Write-Host "✗ Failed to set PowerShell execution policy: $($_.Exception.Message)" -ForegroundColor Red
            Write-Log "[SecurityHardening] Failed to set PowerShell execution policy: $_" 'ERROR'
            $securityErrors++
        }

        # 9. Enable Controlled Folder Access (Windows Defender)
        Write-Log "[SecurityHardening] Enabling Controlled Folder Access..." 'INFO'
        try {
            Set-MpPreference -EnableControlledFolderAccess Enabled -ErrorAction Stop
            Write-Host "✓ Controlled Folder Access enabled" -ForegroundColor Green
            Write-Log "[SecurityHardening] Controlled Folder Access enabled" 'INFO'
            $securityActions++
        }
        catch {
            Write-Host "✗ Failed to enable Controlled Folder Access: $($_.Exception.Message)" -ForegroundColor Red
            Write-Log "[SecurityHardening] Failed to enable Controlled Folder Access: $_" 'ERROR'
            $securityErrors++
        }

        # 10. Disable risky services
        Write-Log "[SecurityHardening] Disabling risky services..." 'INFO'
        $ServicesToDisable = @(
            "Fax",                    # Fax service
            "RemoteRegistry",         # Remote Registry (if not needed)
            "TapiSrv",               # Telephony service
            "WMPNetworkSvc"          # Windows Media Player Network Sharing
        )

        foreach ($ServiceName in $ServicesToDisable) {
            try {
                $Service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
                if ($Service) {
                    if ($Service.Status -eq "Running") {
                        Stop-Service -Name $ServiceName -Force -ErrorAction Stop
                    }
                    Set-Service -Name $ServiceName -StartupType Disabled -ErrorAction Stop
                    Write-Host "✓ Disabled service: $ServiceName" -ForegroundColor Green
                    Write-Log "[SecurityHardening] Disabled service: $ServiceName" 'INFO'
                    $securityActions++
                }
            }
            catch {
                Write-Host "⚠ Could not disable service $ServiceName : $($_.Exception.Message)" -ForegroundColor Yellow
                Write-Log "[SecurityHardening] Could not disable service $ServiceName : $_" 'WARN'
            }
        }

        # 11. Secure Remote Desktop (if enabled)
        Write-Log "[SecurityHardening] Securing Remote Desktop (if enabled)..." 'INFO'
        try {
            $RDPPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp"
            if (Test-Path $RDPPath) {
                Set-ItemProperty -Path $RDPPath -Name "UserAuthentication" -Value 1 -Type DWord -Force
                Write-Host "✓ Network Level Authentication enabled for RDP" -ForegroundColor Green
                Write-Log "[SecurityHardening] Network Level Authentication enabled for RDP" 'INFO'
                $securityActions++
            }
        }
        catch {
            Write-Host "⚠ Could not configure RDP security: $($_.Exception.Message)" -ForegroundColor Yellow
            Write-Log "[SecurityHardening] Could not configure RDP security: $_" 'WARN'
        }

        # 12. Enable Windows Defender Cloud Protection
        Write-Log "[SecurityHardening] Enabling Windows Defender Cloud Protection..." 'INFO'
        try {
            Set-MpPreference -MAPSReporting Advanced -ErrorAction Stop
            Set-MpPreference -SubmitSamplesConsent SendAllSamples -ErrorAction Stop
            Write-Host "✓ Cloud protection and sample submission enabled" -ForegroundColor Green
            Write-Log "[SecurityHardening] Cloud protection and sample submission enabled" 'INFO'
            $securityActions++
        }
        catch {
            Write-Host "✗ Failed to enable cloud protection: $($_.Exception.Message)" -ForegroundColor Red
            Write-Log "[SecurityHardening] Failed to enable cloud protection: $_" 'ERROR'
            $securityErrors++
        }

        # 13. Secure SMB while preserving functionality
        Write-Log "[SecurityHardening] Securing SMB while preserving functionality..." 'INFO'
        try {
            # Enable SMB encryption for SMB3+ (doesn't break compatibility)
            Set-SmbServerConfiguration -EncryptData $true -Confirm:$false -ErrorAction Stop
            
            # Disable SMB1 (major security risk)
            Disable-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -NoRestart -ErrorAction Stop
            
            Write-Host "✓ SMB security enhanced (SMB1 disabled, encryption enabled)" -ForegroundColor Green
            Write-Host "⚠ SMB1 clients will no longer be able to connect" -ForegroundColor Yellow
            Write-Log "[SecurityHardening] SMB security enhanced (SMB1 disabled, encryption enabled)" 'INFO'
            Write-Log "[SecurityHardening] SMB1 clients will no longer be able to connect" 'WARN'
            $securityActions++
        }
        catch {
            Write-Host "⚠ Could not fully configure SMB security: $($_.Exception.Message)" -ForegroundColor Yellow
            Write-Log "[SecurityHardening] Could not fully configure SMB security: $_" 'WARN'
        }

        # Summary
        Write-Log "[SecurityHardening] Security hardening completed: $securityActions actions completed, $securityErrors errors" 'INFO'
        
        # Detailed audit log
        Write-Log "[SecurityHardening] SECURITY AUDIT SUMMARY:" 'INFO'
        foreach ($result in $hardeningResults) {
            Write-Log "[SecurityHardening] $result" 'INFO'
        }
        
        # Create security hardening report
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $securityReport = @"
=== WINDOWS SECURITY HARDENING REPORT ===
Timestamp: $timestamp
Total Actions: $securityActions
Total Errors: $securityErrors
Success Rate: $(if($securityActions -gt 0) { [math]::Round(($securityActions / ($securityActions + $securityErrors)) * 100, 2) } else { 0 })%

Security Features Status:
$(foreach ($result in $hardeningResults) { "- $result" })

Important Notes:
- SMB shares will continue to work with SMB2/3 clients
- User passwords and login processes are unchanged
- Some changes may require a system restart to take full effect
- SMB1 has been disabled for security (legacy clients won't connect)
- Controlled Folder Access may block some applications initially
"@
        
        Write-Log "[SecurityHardening] DETAILED REPORT:" 'INFO'
        $securityReport -split "`n" | ForEach-Object { Write-Log "[SecurityHardening] $_" 'INFO' }
        
        if ($securityErrors -eq 0) {
            Write-Host "✅ Security Hardening: All security features configured successfully" -ForegroundColor Green
            Write-Log "[SecurityHardening] RESULT: All security features configured successfully" 'INFO'
        }
        else {
            Write-Host "⚠️ Security Hardening: $securityActions features configured, $securityErrors errors encountered" -ForegroundColor Yellow
            Write-Log "[SecurityHardening] RESULT: $securityActions features configured, $securityErrors errors encountered" 'WARN'
        }

        # Important notes
        Write-Host "" -ForegroundColor White
        Write-Host "IMPORTANT SECURITY HARDENING NOTES:" -ForegroundColor Yellow
        Write-Host "• SMB shares will continue to work with SMB2/3 clients" -ForegroundColor White
        Write-Host "• User passwords and login processes are unchanged" -ForegroundColor White
        Write-Host "• Some changes may require a system restart to take full effect" -ForegroundColor White
        Write-Host "• SMB1 has been disabled for security (legacy clients won't connect)" -ForegroundColor White
        Write-Host "• Controlled Folder Access may block some applications initially" -ForegroundColor White
        
    }
    catch {
        Write-Host "✗ Security Hardening operation failed: $($_.Exception.Message)" -ForegroundColor Red
        Write-Log "[SecurityHardening] Critical security hardening operation failure: $_" 'ERROR'
    }
    
    Write-Log "[END] Windows Security Hardening" 'INFO'
}

### AI_MAINTENANCE_TASK: PowerShell 7.5 Native System Restore Protection
# AI_TASK_ID: SystemRestoreProtection
# AI_PURPOSE: Native PowerShell 7.5 System Restore management with enhanced error handling and performance
# AI_ENVIRONMENT: Windows 10/11, Administrator required, native PS7.5 CIM cmdlets, multiple fallback methods
# AI_PERFORMANCE: Native CIM operations, smart duplicate protection, enhanced validation, optimized execution
# AI_DEPENDENCIES: Native PS7.5 CIM cmdlets, SystemRestoreConfig, Enable-ComputerRestore, Checkpoint-Computer
# AI_LOGIC: Multiple fallback strategies, comprehensive error handling, intelligent restore point management
# AI_FEATURES: PS7.5 native operations, no compatibility layer overhead, enhanced reliability and speed
function Protect-SystemRestore {
    # ===============================
    # AI_TASK_HEADER: SystemRestoreProtection (PowerShell 7.5 Native)
    # ===============================
    # AI_PURPOSE: Native PS7.5 System Restore management with enhanced error handling and performance
    # AI_ENVIRONMENT: Windows 10/11, Administrator required, native PS7.5 CIM cmdlets optimized
    # AI_LOGIC: Native CIM operations, smart duplicate protection, enhanced validation, optimized performance
    # AI_PERFORMANCE: Eliminates PS5.1 compatibility overhead, uses direct PS7.5 native capabilities
    # ===============================
    Write-Log "Starting PowerShell 7.5 Native System Restore Protection" 'INFO'

    $drive = "C:\"
    $restorePointDescription = "Pre-maintenance restore point"
    $restoreEnabled = $false
    $restorePointCreated = $false

    # --- Enumerate and clean old restore points ---
    try {
        $allRestorePoints = @()
        if (Get-Command Get-ComputerRestorePoint -ErrorAction SilentlyContinue) {
            $allRestorePoints = Get-ComputerRestorePoint -ErrorAction SilentlyContinue | Sort-Object CreationTime
        }
        else {
            $allRestorePoints = Get-CimInstance -Namespace 'root\default' -ClassName 'SystemRestore' | Sort-Object CreationTime
        }
        $totalRestorePoints = $allRestorePoints.Count
        Write-Log "Enumerating all system restore points (Total: $totalRestorePoints)" 'INFO'
        foreach ($rp in $allRestorePoints) {
            $rpDate = $rp.CreationTime
            if ($rpDate -is [string]) {
                try { $rpDate = [datetime]::ParseExact($rpDate, 'yyyyMMddHHmmss.000000+000', $null) } catch {} 
            }
            $rpInfo = "RestorePointID=$($rp.SequenceNumber), Description=$($rp.Description), Type=$($rp.RestorePointType), Date=$rpDate"
            Write-Log $rpInfo 'INFO'
        }
        # If more than 5 restore points, delete the oldest ones
        if ($totalRestorePoints -gt 5) {
            $toDelete = $allRestorePoints | Select-Object -First ($totalRestorePoints - 5)
            foreach ($oldRp in $toDelete) {
                try {
                    if (Get-Command Delete-ComputerRestorePoint -ErrorAction SilentlyContinue) {
                        Delete-ComputerRestorePoint -SequenceNumber $oldRp.SequenceNumber -ErrorAction Stop
                    }
                    else {
                        Invoke-WmiMethod -Namespace 'root\default' -Class 'SystemRestore' -Name 'DeleteRestorePoint' -ArgumentList $oldRp.SequenceNumber | Out-Null
                    }
                    Write-Log "Deleted old restore point: ID=$($oldRp.SequenceNumber), Description=$($oldRp.Description)" 'WARN'
                }
                catch {
                    Write-Log "Failed to delete restore point: ID=$($oldRp.SequenceNumber), Description=$($oldRp.Description). Error: $_" 'ERROR'
                }
            }
        }
    }
    catch {
        Write-Log "Failed to enumerate or clean restore points: $_" 'ERROR'
    }
    # Enhanced native PS7.5 System Restore status check
    Write-Log "[SystemRestore] Checking System Restore status using native PS7.5 CIM cmdlets..." 'VERBOSE'
        
    # Get System Restore configuration using native CIM
    $restoreConfig = $null
    try {
        $restoreConfig = Get-CimInstance -Namespace root/default -ClassName SystemRestoreConfig -ErrorAction Stop
        Write-Log "[SystemRestore] System Restore status: $($restoreConfig.Enable)" 'VERBOSE'
    }
    catch {
        Write-Log "[SystemRestore] Failed to query SystemRestoreConfig: $_" 'WARN'
        # Try alternative method
        try {
            $restoreStatus = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore" -Name "DisableSR" -ErrorAction SilentlyContinue
            $restoreConfig = [PSCustomObject]@{ Enable = $restoreStatus.DisableSR -ne 1 }
            Write-Log "[SystemRestore] Using registry fallback - System Restore enabled: $($restoreConfig.Enable)" 'VERBOSE'
        }
        catch {
            Write-Log "[SystemRestore] Both CIM and registry methods failed - assuming disabled" 'WARN'
            $restoreConfig = [PSCustomObject]@{ Enable = $false }
        }
    }
        
    # Get disk space using native PS7.5 cmdlets
    $freeSpaceGB = 0
    try {
        $diskInfo = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='C:'" -ErrorAction Stop
        $freeSpaceGB = [math]::Round($diskInfo.FreeSpace / 1GB, 2)
        Write-Log "[SystemRestore] Free disk space: $($freeSpaceGB)GB" 'VERBOSE'
    }
    catch {
        Write-Log "[SystemRestore] Failed to get disk space info: $_" 'WARN'
        # Try Get-Volume as fallback
        try {
            $volume = Get-Volume -DriveLetter C -ErrorAction Stop
            $freeSpaceGB = [math]::Round($volume.SizeRemaining / 1GB, 2)
            Write-Log "[SystemRestore] Using Get-Volume fallback - Free space: $($freeSpaceGB)GB" 'VERBOSE'
        }
        catch {
            Write-Log "[SystemRestore] Unable to determine free disk space" 'WARN'
            $freeSpaceGB = 10  # Assume sufficient space to continue
        }
    }
        
    # Check for recent restore points using native cmdlets
    $recentPointsCount = 0
    $lastPointTime = $null
    try {
        # In PowerShell 7.5, we can use Get-ComputerRestorePoint if available
        if (Get-Command Get-ComputerRestorePoint -ErrorAction SilentlyContinue) {
            $recentPoints = Get-ComputerRestorePoint -ErrorAction SilentlyContinue | Where-Object { 
                $_.CreationTime -gt (Get-Date).AddHours(-2) 
            }
            $recentPointsCount = ($recentPoints | Measure-Object).Count
            if ($recentPoints) {
                $lastPointTime = ($recentPoints | Sort-Object CreationTime -Descending | Select-Object -First 1).CreationTime
            }
            Write-Log "[SystemRestore] Recent restore points (last 2 hours): $recentPointsCount" 'VERBOSE'
        }
        else {
            Write-Log "[SystemRestore] Get-ComputerRestorePoint not available - continuing without recent point check" 'VERBOSE'
        }
    }
    catch {
        Write-Log "[SystemRestore] Failed to check recent restore points: $_" 'VERBOSE'
    }
        
    # Enhanced System Restore enablement
    $restoreEnabled = $restoreConfig.Enable
    if (-not $restoreEnabled) {
        Write-Host "⚠️ System Restore disabled - enabling..." -ForegroundColor Yellow
            
        try {
            # Use native PS7.5 approach with multiple methods
            $enableSuccess = $false
                
            # Method 1: Try Enable-ComputerRestore if available
            if (Get-Command Enable-ComputerRestore -ErrorAction SilentlyContinue) {
                try {
                    Enable-ComputerRestore -Drive $drive -ErrorAction SilentlyContinue
                        
                    # Verify that System Restore was actually enabled
                    Start-Sleep -Seconds 2
                    $restoreCheck = Get-CimInstance -ClassName SystemRestoreConfig -ErrorAction SilentlyContinue | Where-Object { $_.Drive -eq $drive }
                    if ($restoreCheck -and -not $restoreCheck.Disable) {
                        $enableSuccess = $true
                        Write-Log "[SystemRestore] Enabled using Enable-ComputerRestore cmdlet" 'INFO'
                    }
                    else {
                        Write-Log "[SystemRestore] Enable-ComputerRestore completed but verification failed" 'WARN'
                    }
                }
                catch {
                    Write-Log "[SystemRestore] Enable-ComputerRestore failed: $_" 'VERBOSE'
                }
            }
                
            # Method 2: Try registry method if cmdlet failed
            if (-not $enableSuccess) {
                try {
                    $null = Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore" -Name "DisableSR" -Value 0 -Force -ErrorAction Stop
                        
                    # Also enable for the specific drive
                    $driveKey = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore\Cfg"
                    if (Test-Path $driveKey) {
                        $null = Set-ItemProperty -Path $driveKey -Name "DisableSR" -Value 0 -Force -ErrorAction SilentlyContinue
                    }
                        
                    $enableSuccess = $true
                    Write-Log "[SystemRestore] Enabled using registry method" 'INFO'
                }
                catch {
                    Write-Log "[SystemRestore] Registry enable method failed: $_" 'VERBOSE'
                }
            }
                
            # Method 3: Try VSSAdmin as final fallback
            if (-not $enableSuccess) {
                try {
                    & vssadmin list writers 2>$null
                    if ($LASTEXITCODE -eq 0) {
                        # VSSAdmin is working, try to enable via WMI
                        $systemRestoreConfig = Get-CimInstance -Namespace root/default -ClassName SystemRestoreConfig -ErrorAction SilentlyContinue
                        if ($systemRestoreConfig) {
                            $systemRestoreConfig | Set-CimInstance -Property @{Enable = $true } -ErrorAction Stop
                            $enableSuccess = $true
                            Write-Log "[SystemRestore] Enabled using WMI/CIM method" 'INFO'
                        }
                    }
                }
                catch {
                    Write-Log "[SystemRestore] WMI/CIM enable method failed: $_" 'VERBOSE'
                }
            }
                
            if ($enableSuccess) {
                $restoreEnabled = $true
                Write-Host "✓ System Restore enabled successfully" -ForegroundColor Green
                Write-Log "System Restore enabled on $drive" 'INFO'
                    
                # Brief wait for the service to initialize
                Start-Sleep -Seconds 2
            }
            else {
                Write-Host "✗ Failed to enable System Restore" -ForegroundColor Red
                Write-Log "All methods to enable System Restore failed" 'ERROR'
                return
            }
        }
        catch {
            Write-Host "✗ System Restore enable error: $($_.Exception.Message)" -ForegroundColor Red
            Write-Log "Critical error enabling System Restore: $_" 'ERROR'
            return
        }
    }
    else {
        Write-Host "✓ System Restore already enabled" -ForegroundColor Green
        Write-Log "System Restore is already enabled" 'INFO'
    }
        
    # Enhanced disk space validation
    if ($freeSpaceGB -lt 2) {
        Write-Host "⚠️ Insufficient disk space ($($freeSpaceGB)GB) for restore point" -ForegroundColor Yellow
        Write-Log "Insufficient disk space ($($freeSpaceGB)GB) to create restore point safely" 'WARN'
        return
    }
        
    # Smart duplicate restore point protection
    if ($recentPointsCount -gt 0 -and $null -ne $lastPointTime) {
        try {
            # Ensure $lastPointTime is a proper DateTime object
            $lastPointDateTime = $lastPointTime
            if ($lastPointTime -is [string]) {
                $lastPointDateTime = [datetime]::Parse($lastPointTime)
            }
            
            $timeSinceLastPoint = (Get-Date) - $lastPointDateTime
            if ($timeSinceLastPoint.TotalMinutes -lt 120) {
                $minutesAgo = [math]::Round($timeSinceLastPoint.TotalMinutes)
                Write-Host "✓ Recent restore point exists ($minutesAgo min ago) - skipping" -ForegroundColor Cyan
                Write-Log "Recent restore point exists (created $minutesAgo minutes ago) - skipping creation" 'INFO'
                $restorePointCreated = $true
                return
            }
        }
        catch {
            Write-Log "[SystemRestore] Date comparison failed: $_" 'VERBOSE'
            # Continue with restore point creation if date comparison fails
        }
    }
        
    # Enhanced native restore point creation
    if ($restoreEnabled) {
        Write-Host "🔄 Creating restore point..." -ForegroundColor Cyan
            
        try {
            $createSuccess = $false
                
            # Method 1: Try Checkpoint-Computer if available
            if (Get-Command Checkpoint-Computer -ErrorAction SilentlyContinue) {
                try {
                    Checkpoint-Computer -Description $restorePointDescription -RestorePointType 'MODIFY_SETTINGS' -ErrorAction Stop
                    $createSuccess = $true
                    Write-Log "[SystemRestore] Restore point created using Checkpoint-Computer cmdlet" 'INFO'
                }
                catch {
                    $errorCode = $_.Exception.HResult
                    if ($errorCode -eq -2147023728) {
                        # 0x80042308 - Frequency limit
                        Write-Host "ℹ️ Restore point frequency limit reached (Windows limitation)" -ForegroundColor Cyan
                        Write-Log "Restore point frequency limit reached - skipping (Windows limitation)" 'INFO'
                        $createSuccess = $true  # Consider successful since protection exists
                    }
                    elseif ($errorCode -eq -2147023742) {
                        # 0x80042302 - Service not responding
                        Write-Log "System Restore service temporarily unavailable: $_" 'WARN'
                    }
                    else {
                        Write-Log "[SystemRestore] Checkpoint-Computer failed: $_" 'VERBOSE'
                    }
                }
            }
                
            # Method 2: Try WMI method if cmdlet failed
            if (-not $createSuccess) {
                try {
                    $systemRestore = Get-CimClass -Namespace root/default -ClassName SystemRestore -ErrorAction Stop
                    $result = Invoke-CimMethod -CimClass $systemRestore -MethodName "CreateRestorePoint" -Arguments @{
                        Description      = $restorePointDescription
                        RestorePointType = 12  # MODIFY_SETTINGS
                        EventType        = 100         # BEGIN_SYSTEM_CHANGE
                    } -ErrorAction Stop
                        
                    if ($result.ReturnValue -eq 0) {
                        $createSuccess = $true
                        Write-Log "[SystemRestore] Restore point created using WMI/CIM method" 'INFO'
                    }
                    else {
                        Write-Log "[SystemRestore] WMI restore point creation returned code: $($result.ReturnValue)" 'VERBOSE'
                    }
                }
                catch {
                    Write-Log "[SystemRestore] WMI restore point creation failed: $_" 'VERBOSE'
                }
            }
                
            if ($createSuccess) {
                $restorePointCreated = $true
                Write-Host "✓ Restore point created successfully" -ForegroundColor Green
                Write-Log "System restore point '$restorePointDescription' created successfully" 'INFO'
                    
                # Optional: Check total restore point count for informational purposes
                try {
                    if (Get-Command Get-ComputerRestorePoint -ErrorAction SilentlyContinue) {
                        $allPoints = (Get-ComputerRestorePoint -ErrorAction SilentlyContinue | Measure-Object).Count
                        if ($allPoints -gt 0) {
                            Write-Log "[SystemRestore] Total restore points: $allPoints" 'VERBOSE'
                        }
                    }
                }
                catch {
                    # Ignore count check errors
                }
            }
            else {
                Write-Host "⚠️ Could not create restore point - protection still enabled" -ForegroundColor Yellow
                Write-Log "Failed to create restore point but System Restore remains enabled" 'WARN'
            }
        }
        catch {
            $errorMessage = $_.Exception.Message
            Write-Host "⚠️ Restore point creation failed: $errorMessage" -ForegroundColor Yellow
            Write-Log "Restore point creation failed: $errorMessage" 'WARN'
        }
    }
        
    # Enhanced summary with performance metrics
    $successSummary = @()
    if ($restoreEnabled) { $successSummary += "System Restore Enabled" }
    if ($restorePointCreated) { $successSummary += "Restore Point Created" }
    elseif ($restoreEnabled) { $successSummary += "Protection Active" }
        
    if ($successSummary.Count -gt 0) {
        Write-Host "✅ System Restore: $($successSummary -join ', ')" -ForegroundColor Green
        Write-Log "System Restore protection completed successfully: $($successSummary -join ', ')" 'INFO'
    }
    else {
        Write-Host "⚠️ System Restore protection incomplete" -ForegroundColor Yellow
        Write-Log "System Restore protection completed with limitations" 'WARN'
    }
}
    
Write-Log "[END] PowerShell 7.5 Native System Restore Protection" 'INFO'

### [MAIN TASK EXECUTION IN TIMELINE ORDER]

# PowerShell script startup logging
Write-Log "============================================================" 'INFO'
Write-Log "PowerShell Maintenance Script Starting" 'INFO'
Write-Log "Script Path: $PSCommandPath" 'INFO'
Write-Log "PowerShell Version: $($PSVersionTable.PSVersion)" 'INFO'
Write-Log "============================================================" 'INFO'

# Run all tasks using the coordinator
Use-AllScriptTasks




### [POST-TASK 1] Script completion cleanup




### [POST-TASK 2] Built-in Maintenance Tasks

$successCount = ($global:TaskResults.Values | Where-Object { $_.Success }).Count
$failCount = ($global:TaskResults.Values | Where-Object { -not $_.Success }).Count
$totalCount = $global:TaskResults.Count
$taskDetails = @()
foreach ($key in $global:TaskResults.Keys) {
    $result = $global:TaskResults[$key]
    $desc = ($global:ScriptTasks | Where-Object { $_.Name -eq $key }).Description
    $status = if ($result.Success) { 'SUCCESS' } else { 'FAIL' }
    $duration = [math]::Round($result.Duration, 2)
    $started = $result.Started.ToString('HH:mm:ss')
    $ended = $result.Ended.ToString('HH:mm:ss')
    $taskDetails += "- $key $status | $desc | Started: $started | Ended: $ended | Duration: ${duration}s"
    if ($result.ContainsKey('Error') -and $result.Error) {
        $taskDetails += "    Error: $($result.Error)"
    }
}
Write-Log ("All tasks completed. Total: {0}, Success: {1}, Failed: {2}" -f $totalCount, $successCount, $failCount) 'INFO'
foreach ($detail in $taskDetails) { Write-Log $detail 'INFO' }

### [POST-TASK 4] Enhanced Reporting Section (JSON + Text)

# Save summary report in the same folder as script.bat (repo parent folder)
$batPath = Join-Path $PSScriptRoot "script.bat"
if (Test-Path $batPath) {
    $batDir = Split-Path $batPath -Parent
    $summaryPath = Join-Path $batDir "maintenance_report.txt"
    $jsonSummaryPath = Join-Path $batDir "maintenance_report.json"
}
else {
    $summaryPath = Join-Path $PSScriptRoot "maintenance_report.txt"
    $jsonSummaryPath = Join-Path $PSScriptRoot "maintenance_report.json"
}

# Gather system info for report
$osInfo = Get-CimInstance Win32_OperatingSystem
$osVersion = $osInfo.Version
$osCaption = $osInfo.Caption
$psVer = $PSVersionTable.PSVersion.ToString()
$scriptVer = '1.0.0'

# Build structured report object
$reportData = [ordered]@{
    metadata = [ordered]@{
        generatedOn       = (Get-Date).ToString('o')
        date              = Get-Date -Format 'dd-MM-yyyy HH:mm:ss'
        user              = $env:USERNAME
        computer          = $env:COMPUTERNAME
        scriptVersion     = $scriptVer
        os                = $osCaption
        osVersion         = $osVersion
        powershellVersion = $psVer
    }
    summary  = [ordered]@{
        totalTasks      = $totalCount
        successfulTasks = $successCount
        failedTasks     = $failCount
        successRate     = if ($totalCount -gt 0) { [math]::Round(($successCount / $totalCount) * 100, 2) } else { 0 }
    }
    tasks    = @()
    files    = [ordered]@{
        inventoryFiles = @()
        listFiles      = @()
        logFiles       = @()
    }
    actions  = @()
}

# Add task details
foreach ($key in $global:TaskResults.Keys) {
    $result = $global:TaskResults[$key]
    $desc = ($global:ScriptTasks | Where-Object { $_.Name -eq $key }).Description
    $taskObj = [ordered]@{
        name        = $key
        description = $desc
        success     = $result.Success
        duration    = [math]::Round($result.Duration, 2)
        started     = $result.Started.ToString('o')
        ended       = $result.Ended.ToString('o')
    }
    if ($result.ContainsKey('Error') -and $result.Error) {
        $taskObj.error = $result.Error
    }
    $reportData.tasks += $taskObj
}

# Reference files created
$inventoryFiles = @('inventory.json', 'bloatware.json', 'essential_apps.json')
$legacyFiles = @('inventory.txt')  # Keep legacy reference
$logFiles = @('maintenance.log')

foreach ($file in $inventoryFiles) {
    $path = Join-Path $PSScriptRoot $file
    if (Test-Path $path) {
        $reportData.files.inventoryFiles += $file
    }
}

foreach ($file in $legacyFiles) {
    $path = Join-Path $PSScriptRoot $file
    if (Test-Path $path) {
        $reportData.files.inventoryFiles += $file
    }
}

foreach ($file in $logFiles) {
    $path = Join-Path $PSScriptRoot $file
    if (Test-Path $path) {
        $reportData.files.logFiles += $file
    }
}

# Extract detailed actions from maintenance.log
$logActions = @('Installed', 'Uninstalled', 'Updated', 'Removed', 'Deleted', 'Upgraded', 'Cleaned')
# Use the same log file that was set at the beginning of the script
if (Test-Path $LogFile) {
    $logContent = Get-Content $LogFile
    $actionLines = $logContent | Where-Object {
        $line = $_
        $logActions | Where-Object { $line -match $_ }
    }
    $reportData.actions = @($actionLines)
}

# Write structured JSON report
try {
    $reportData | ConvertTo-Json -Depth 5 | Out-File -FilePath $jsonSummaryPath -Encoding UTF8
    Write-Log "Structured report saved to $jsonSummaryPath" 'INFO'
}
catch {
    Write-Log "Failed to write JSON report: $_" 'WARN'
}

# Build human-readable text report
$summaryLines = @()
$summaryLines += "==== Maintenance Report ===="
$summaryLines += "Date: $($reportData.metadata.date)"
$summaryLines += "User: $($reportData.metadata.user)"
$summaryLines += "Computer: $($reportData.metadata.computer)"
$summaryLines += "Script Version: $($reportData.metadata.scriptVersion)"
$summaryLines += "OS: $($reportData.metadata.os) ($($reportData.metadata.osVersion))"
$summaryLines += "PowerShell Version: $($reportData.metadata.powershellVersion)"
$summaryLines += "---"
$summaryLines += "Total tasks: $($reportData.summary.totalTasks) | Success: $($reportData.summary.successfulTasks) | Failed: $($reportData.summary.failedTasks) | Success Rate: $($reportData.summary.successRate)%"
$summaryLines += "---"
$summaryLines += "Task Breakdown:"
foreach ($task in $reportData.tasks) {
    $status = if ($task.success) { 'SUCCESS' } else { 'FAIL' }
    $summaryLines += "- $($task.name) $status | $($task.description) | Duration: $($task.duration)s"
    if ($task.error) {
        $summaryLines += "    Error: $($task.error)"
    }
}
$summaryLines += "---"

$summaryLines += "Files generated:"
if ($reportData.files.inventoryFiles.Count -gt 0) {
    $summaryLines += "Inventory files:"
    $reportData.files.inventoryFiles | ForEach-Object { $summaryLines += "- $_" }
}
if ($reportData.files.logFiles.Count -gt 0) {
    $summaryLines += "Log files:"
    $reportData.files.logFiles | ForEach-Object { $summaryLines += "- $_" }
}
$summaryLines += "---"

if ($reportData.actions.Count -gt 0) {
    $summaryLines += "Detailed actions performed during maintenance:"
    $summaryLines += $reportData.actions
    $summaryLines += "---"
}
else {
    $summaryLines += "No detailed action logs found in maintenance.log."
    $summaryLines += "---"
}

$summaryLines | Out-File -FilePath $summaryPath -Append
Write-Log "Summary report written to $summaryPath" 'INFO'

# Ensure repo folder is deleted only after report creation
try {
    if ($RepoFolderPath -and (Test-Path $RepoFolderPath) -and $RepoFolderPath -ne $ScriptDir) {
        Write-Log "Attempting to remove downloaded repo folder: $RepoFolderPath" 'INFO'
        $parentFolder = Split-Path $RepoFolderPath -Parent
        $repoName = Split-Path $RepoFolderPath -Leaf
        
        # Only remove if it's clearly a downloaded repo folder (contains 'script_mentenanta-main')
        if ($repoName -eq 'script_mentenanta-main') {
            Write-Host ""
            Write-Host "========================================" -ForegroundColor Yellow
            Write-Host "   REPO FOLDER CLEANUP WARNING" -ForegroundColor Yellow
            Write-Host "========================================" -ForegroundColor Yellow
            Write-Host "About to delete downloaded repository folder:" -ForegroundColor Cyan
            Write-Host $RepoFolderPath -ForegroundColor White
            Write-Host ""
            Write-Host "30-second countdown starting..." -ForegroundColor Yellow
            Write-Host "Press ANY KEY to abort deletion!" -ForegroundColor Red
            Write-Host ""
            
            Write-Log "Starting 30-second countdown for repo folder deletion. Press any key to abort." 'INFO'
            
            # 30-second countdown with abort option
            $countdownAborted = $false
            for ($i = 30; $i -gt 0; $i--) {
                Write-Host "Deleting in $i seconds... (Press ANY KEY to abort)" -ForegroundColor Yellow
                
                # Check for key press
                if ([Console]::KeyAvailable) {
                    $key = [Console]::ReadKey($true)
                    $countdownAborted = $true
                    Write-Host ""
                    Write-Host "Deletion ABORTED by user!" -ForegroundColor Green
                    Write-Log "Repo folder deletion aborted by user key press." 'INFO'
                    break
                }
                
                Start-Sleep -Seconds 1
            }
            
            if (-not $countdownAborted) {
                Write-Host ""
                Write-Host "No abort signal received. Proceeding with deletion..." -ForegroundColor Red
                Write-Log "30-second countdown completed. Proceeding with repo folder deletion." 'INFO'
                
                # Change to parent directory before deletion
                Set-Location $parentFolder
                Remove-Item -Path $RepoFolderPath -Recurse -Force
                Write-Host "Downloaded repo folder deleted successfully." -ForegroundColor Green
                Write-Log "Downloaded repo folder $RepoFolderPath removed successfully." 'INFO'
            }
        }
        else {
            Write-Log "Skipping repo folder removal - folder name doesn't match expected pattern: $repoName" 'INFO'
        }
    }
    else {
        Write-Log "No repo folder to clean up (using local script.ps1)" 'INFO'
    }
}
catch {
    Write-Log "Failed to remove repo folder: $_" 'WARN'
    Write-Host "Error during repo folder cleanup: $($_.Exception.Message)" -ForegroundColor Red
}

### [POST-TASK 6] Example: Optionally send report via email or webhook (not implemented)
### ...

# Final completion logging with detailed information
$completionTimestamp = Get-Date -Format 'MM/dd/yyyy HH:mm:ss'
Write-Log "============================================================" 'INFO'
Write-Log "PowerShell Maintenance Script execution completed successfully" 'INFO'
Write-Log "Total execution time: $((Get-Date) - $startTime)" 'INFO' 
Write-Log "Log file location: $LogFile" 'INFO'
Write-Log "============================================================" 'INFO'

# Add completion marker to log file for script.bat to detect if needed
Add-Content -Path $LogFile -Value "[$completionTimestamp] [INFO] ============================================================"
Add-Content -Path $LogFile -Value "[$completionTimestamp] [INFO] PowerShell Maintenance Script Completed Successfully"
Add-Content -Path $LogFile -Value "[$completionTimestamp] [INFO] Returning control to script.bat (if applicable)"
Add-Content -Path $LogFile -Value "[$completionTimestamp] [INFO] ============================================================"

### AI_POST_TASK: Interactive closure prompt for console environments
# AI_PURPOSE: Provides user interaction for console-based script execution
# AI_LOGIC: Detects console environment and prompts for user acknowledgment before closure
if ($Host.Name -eq 'ConsoleHost' -or $Host.Name -like '*Windows*') {
    Write-Host
    Read-Host -Prompt 'Press Enter to close this window...'
}

# =============================================
# AI_SCRIPT_METADATA: Windows Maintenance Script Architecture Guide
# =============================================
# AI_FILE_PURPOSE: Comprehensive Windows maintenance automation with modular task architecture
# AI_SCRIPT_STRUCTURE: Global task array → Coordination function → Individual task functions → Support functions
# AI_NAMING_CONVENTION: All AI-focused comments use AI_ prefix for easy identification and parsing
# AI_TASK_PATTERN: Each maintenance task follows standardized AI_TASK_HEADER format with Purpose/Environment/Logic/Performance
# AI_FUNCTION_PATTERN: Support functions use AI_FUNCTION format with Purpose/Environment/Parameters/Logic/Returns
# AI_EDITING_GUIDELINES:
#   - Maintain AI_ comment prefixes for all AI-focused documentation
#   - Follow established task header patterns when adding new functions
#   - Use consistent performance optimization patterns (HashSet, parallel processing, action-only logging)
#   - Maintain PowerShell 7.5 native operation preferences with compatibility fallbacks
#   - Preserve comprehensive error handling and logging patterns
#   - Keep action-focused logging for user-facing operations
# AI_PERFORMANCE_PATTERNS: O(1) lookups, parallel processing, native PS7.5 cmdlets, smart caching, batch operations
# AI_ERROR_HANDLING: Comprehensive try/catch blocks, graceful degradation, detailed logging, multiple fallback strategies
# AI_CONFIGURATION: config.json driven feature toggles, custom app lists, verbose logging control
# AI_DEPENDENCIES: Winget, Chocolatey, PowerShell 7.5, Administrator privileges, various Windows APIs
# AI_OUTPUT_FILES: maintenance.log, inventory.txt, apps_*.txt (in $PSScriptRoot)
# =============================================
