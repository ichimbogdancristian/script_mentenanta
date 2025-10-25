# Windows Maintenance Automation - AI Coding Agent Instructions

## 🚨 **CRITICAL: VS Code Diagnostics - Primary Problem Discovery Tool**

**MANDATORY REQUIREMENT**: Before making ANY code changes, analyzing ANY files, or providing ANY solutions, you MUST first check the VS Code diagnostics panel to discover existing problems.

### **Why Diagnostics are Critical:**
- **Real-time validation**: VS Code + PSScriptAnalyzer provide immediate syntax and best practice feedback
- **Comprehensive coverage**: Detects syntax errors, deprecated cmdlets, style violations, and security issues
- **Context-aware**: Problems panel shows exact file, line number, and severity
- **Prevents cascading errors**: Fixing diagnostics issues first prevents introducing new problems

### **When to Check Diagnostics (ALWAYS):**
1. ✅ **Before starting any task** - Understand current state of the codebase
2. ✅ **After every file edit** - Validate changes didn't introduce new issues
3. ✅ **When user reports problems** - Check if diagnostics already identified the issue
4. ✅ **Before suggesting solutions** - Ensure your fix addresses real problems
5. ✅ **During code review** - Verify zero critical errors before completion
6. ✅ **When developing new modules** - Continuous validation during development

### **How to Use Diagnostics Effectively:**
```plaintext
1. Use get_errors tool with no filePaths to see ALL workspace problems
2. Analyze errors by severity: Error > Warning > Information
3. Prioritize PSScriptAnalyzer violations (code quality issues)
4. Check specific files after editing using get_errors with filePaths
5. Verify zero critical errors before marking tasks complete
```

### **Diagnostic-Driven Workflow:**
```
Check Diagnostics → Identify Real Problems → Plan Fix → Implement → Verify Diagnostics Clear
```

**DO NOT**: Guess at problems, assume everything works, or skip validation
**DO**: Let diagnostics guide your analysis and solutions

---

## Project Overview

This is a **enterprise-grade PowerShell-based Windows maintenance system** with hierarchical interactive menus, consolidated modular architecture, and comprehensive before/after reporting. The system features **20-second countdown menus**, **self-contained Type2 modules**, **session-based file organization**, and **external template system** for automated Windows 10/11 maintenance.

## 🔄 **Complete Execution Logic & Architecture (v3.0)**

### **🎯 Core Execution Flow Logic**

The system follows a **strict hierarchical flow** where user input triggers a standardized sequence:

```
User Input → Type2 Modules → Type1 Triggered → Type1 Creates Audit Logs → 
Type2 Analyzes Logs → Type2 Executes → Type2 Creates Execution Logs → 
Orchestrator Collects ALL Logs → ReportGeneration Processes All Logs → Final Reports
```

**Key Principles:**
1. **Type2 modules** are the primary execution units triggered by user menu selection
2. **Type1 modules** are audit/detection services that **must be triggered by Type2 modules**
3. **Type1 modules** independently create standardized audit logs that Type2 modules require
4. **Type2 modules** analyze Type1 audit logs and execute actions based on diff analysis
5. **Type2 modules** create detailed execution logs of all actions performed
6. **Orchestrator** collects all logs (Type1 audit + Type2 execution) after task completion
7. **ReportGeneration** processes comprehensive log collection to generate final reports

### **📁 Project Structure & File Locations**
```
script_mentenanta/
├── 🚀 script.bat                           # Bootstrap launcher (admin elevation, dependencies)
├── 🎯 MaintenanceOrchestrator.ps1          # Central orchestration engine (1,126 lines)
├── 📁 config/                              # All configurations & templates
│   ├── 📋 main-config.json                 # Execution settings, module toggles
│   ├── 📊 logging-config.json              # Log levels, destinations
│   ├── 🗑️ bloatware-list.json              # 187 applications to remove
│   ├── 📦 essential-apps.json              # 10 applications to install
│   ├── 🎨 report-template.html             # Main HTML report structure
│   ├── 📄 task-card-template.html          # Module report template
│   ├── 🎨 report-styles.css                # Report styling (no charts)
│   └── ⚙️ report-templates-config.json     # Module icons & metadata
├── 📁 modules/
│   ├── 📁 core/                            # Essential Infrastructure (6 modules)
│   │   ├── 🏗️ CoreInfrastructure.psm1      # Config + Logging + File Org (16 functions)
│   │   ├── 🖥️ UserInterface.psm1           # Hierarchical countdown menus
│   │   ├── 📊 ReportGeneration.psm1        # External template-based reports
│   │   ├── 🛠️ CommonUtilities.psm1         # Shared fallback functions
│   │   ├── 📦 DependencyManager.psm1       # Package management
│   │   └── 🔍 SystemAnalysis.psm1          # System inventory & audit
│   ├── 📁 type1/                           # Detection Modules (5 modules)
│   │   ├── 🗑️ BloatwareDetectionAudit.psm1 # Scan for unwanted apps
│   │   ├── 📦 EssentialAppsAudit.psm1      # Identify missing apps
│   │   ├── ⚡ SystemOptimizationAudit.psm1  # Find optimization opportunities
│   │   ├── 🔒 TelemetryAudit.psm1          # Detect active telemetry
│   │   └── 🔄 WindowsUpdatesAudit.psm1     # Check available updates
│   └── 📁 type2/                           # Action Modules (5 modules)
│       ├── 🗑️ BloatwareRemoval.psm1        # Remove applications
│       ├── 📦 EssentialApps.psm1           # Install applications
│       ├── ⚡ SystemOptimization.psm1      # Apply optimizations
│       ├── 🔒 TelemetryDisable.psm1        # Disable telemetry
│       └── 🔄 WindowsUpdates.psm1          # Install updates
└── 📁 temp_files/                          # Session-based storage (auto-created)
    ├── 📁 data/                            # Type1 detection results (.json)
    ├── 📁 logs/                            # Type2 execution logs (per module)
    ├── 📁 temp/                            # Processing diffs
    └── 📁 reports/                         # Temporary report data
```

### **🔄 Detailed Execution Sequence**

**Phase 1: Bootstrap (script.bat - Lines 1-1075)**

**Logging System (Always Active)**:
- Function: `LOG_MESSAGE` with timestamp, level (INFO/DEBUG/SUCCESS/WARN/ERROR), component
- Output: Console + `maintenance.log` file in working directory
- Logs: Every major step, variable initialization, errors, success confirmations

**Step 1: Administrator Privilege Check**
- Method: NET SESSION command (exit code 0 = admin)
- Action: Exit with error if not administrator
- Log: "Administrator check" with result

**Step 2: Path Discovery & Environment Setup**
- Auto-detect: `SCRIPT_PATH` (full path), `SCRIPT_DIR` (directory), `WORKING_DIR` (execution location)
- Set: `SCHEDULED_TASK_SCRIPT_PATH` (for scheduled task creation)
- Initialize Variables:
  - `LOG_FILE=%WORKING_DIR%maintenance.log`
  - `REPO_URL=https://github.com/ichimbogdancristian/script_mentenanta/archive/refs/heads/main.zip`
  - `EXTRACT_FOLDER=script_mentenanta-main`
- Log: All paths and variables with DEBUG level

**Step 3: Network Location Detection**
- Check: If script path starts with "\\\\" (UNC path)
- Action: Set `IS_NETWORK_LOCATION=YES` flag
- Log: Network location status

**Step 4: Pending Restart Handling**
- Check: Registry key `HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired`
- If restart needed:
  - Create ONLOGON scheduled task: `WindowsMaintenanceStartup`
  - Task runs this script with HIGHEST priority under current user
  - Delay: 1 minute after logon
  - Schedule: `shutdown /r /t 5` with 10-second countdown warning
  - Log: Task creation and restart scheduling

**Step 5: PowerShell 7 Restart Flag Cleanup**
- Check: `restart_flag.tmp` file exists
- Action: Read context, delete file, log restart recovery
- Purpose: Handle script continuation after PowerShell 7 installation restart

**Step 6: Monthly Automation Task Setup**
- Task Name: `WindowsMaintenanceAutomation`
- Schedule: Monthly, 1st day at 01:00
- Account: SYSTEM (highest privileges)
- Priority: HIGHEST
- Action: Run `%SCHEDULED_TASK_SCRIPT_PATH%`
- Verification: Query task details and log next run time

**Step 7: System Requirements Verification**
- Check Windows version: `Get-CimInstance Win32_OperatingSystem`
- Check PowerShell version: `$PSVersionTable.PSVersion.Major`
- Requirement: PowerShell 5.1+ minimum
- Exit with error if requirements not met

**Step 8: Winget Installation (3 Methods with Fallbacks)**
- Initial Check: `winget --version` in PATH and WindowsApps
- Method 1: App Installer registration
  - `Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe`
  - Wait 5 seconds, verify
- Method 2: PowerShell Gallery
  - Install NuGet provider
  - Install `Microsoft.WinGet.Client` module
  - Run `Repair-WinGetPackageManager -AllUsers`
  - Wait 5 seconds, verify
- Method 3: Manual MSIX Download
  - URL 1: `https://aka.ms/getwinget`
  - URL 2: `https://github.com/microsoft/winget-cli/releases/download/v1.6.3482/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle`
  - URL 3: Latest from GitHub API
  - Download to temp, install with `Add-AppxPackage`, verify
- Log: Method used, success/failure, final winget availability

**Step 9: Repository Download & Extraction** (if not already present locally)
- Download: `%REPO_URL%` to `%TEMP%\script_mentenanta.zip`
- Extract: To `%WORKING_DIR%%EXTRACT_FOLDER%\`
- Update: `WORKING_DIR` to extracted location
- Optional: Update local `script.bat` from extracted version if different
- Log: Download progress, extraction success, path updates

**Step 10: Project Structure Validation**
- Verify orchestrator: `MaintenanceOrchestrator.ps1` or `script.ps1`
- Verify config directory: `config\main-config.json`, `config\bloatware-list.json`
- Verify modules: `modules\core\CoreInfrastructure.psm1`, `modules\type1`, `modules\type2`
- Count: Major components (expect 3: orchestrator, config, modules)
- Exit with detailed error if structure invalid

**Step 11: PowerShell 7+ Detection (5 Methods)**
- Method 1: Direct command - `pwsh.exe -Version`
- Method 2: Default path - `%ProgramFiles%\PowerShell\7\pwsh.exe`
- Method 3: WindowsApps alias - `%LocalAppData%\Microsoft\WindowsApps\pwsh.exe`
- Method 4: Registry - `HKLM:\SOFTWARE\Microsoft\PowerShellCore\InstalledVersions`
- Method 5: 'where' command - `where pwsh.exe`
- Set: `PS_EXECUTABLE` variable with found path
- Install if not found: Via winget, Chocolatey, or direct MSI download
- Log: Detection method used, version found

**Step 12: Transition to PowerShell 7** (Critical Architecture Change)
- Generate inline PowerShell 7 bootstrap script: `%TEMP%\maintenance_bootstrap_%RANDOM%.ps1`
- Script contents:
  ```powershell
  #Requires -Version 7.0
  #Requires -RunAsAdministrator
  
  param(
      [string]$WorkingDir,
      [string]$LogFile,
      [string]$ScriptPath,
      [string]$ScheduledTaskScriptPath,
      [string]$OrchestratorPath,
      [string]$RepoUrl,
      [string]$ExtractFolder
  )
  
  # Parse command-line arguments from $args automatic variable
  $BatchArgs = if ($args) { $args } else { @() }
  
  # Logging function (mirrors batch LOG_MESSAGE)
  function Write-Log { ... }
  
  # Operations:
  # 1. Windows Defender Exclusions (working dir, powershell.exe, pwsh.exe)
  # 2. Package Manager Verification (winget, chocolatey versions)
  # 3. Scheduled Task Management (verify monthly, cleanup startup)
  # 4. System Restore Point Creation:
  #    - Enable-ComputerRestore -Drive $env:SystemDrive
  #    - Checkpoint-Computer -Description "WindowsMaintenance-{GUID}"
  #    - Verify with Get-ComputerRestorePoint
  # 5. Parse orchestrator arguments (-NonInteractive, -DryRun, -TaskNumbers)
  # 6. Set-Location to working directory
  # 7. Execute orchestrator: & $OrchestratorPath @orchestratorArgs
  # 8. Capture exit code: $exitCode = $LASTEXITCODE
  # 9. Return: exit $exitCode
  ```
- Execute: `"%PS_EXECUTABLE%" -ExecutionPolicy Bypass -NoProfile -File "%PS7_SCRIPT%" %ALL_ARGS%`
- Capture: `FINAL_EXIT_CODE=%ERRORLEVEL%`
- Cleanup: Delete temporary PS7 script
- Log: PS7 script creation, execution start, final exit code
- Exit: `EXIT /B %FINAL_EXIT_CODE%`

**Exit Code Propagation Chain**:
```
MaintenanceOrchestrator.ps1 (exit code)
    ↓ $LASTEXITCODE
PowerShell 7 Bootstrap Script (exit $exitCode)
    ↓ %ERRORLEVEL%
script.bat (EXIT /B %FINAL_EXIT_CODE%)
    ↓ Caller environment
```

**Phase 2: Orchestrator Initialization (MaintenanceOrchestrator.ps1:60-172)**
1. **Global Path Discovery** (lines 73-95):
   ```powershell
   $env:MAINTENANCE_PROJECT_ROOT = $ScriptRoot
   $env:MAINTENANCE_CONFIG_ROOT = Join-Path $ScriptRoot 'config'
   $env:MAINTENANCE_MODULES_ROOT = Join-Path $ScriptRoot 'modules'
   $env:MAINTENANCE_TEMP_ROOT = Join-Path $ScriptRoot 'temp_files'
   ```
2. **Session Management** (lines 106-129):
   - Generate unique session ID (GUID)
   - Create timestamp (yyyyMMdd-HHmmss)
   - Initialize temp directories: data/, logs/, temp/, reports/
3. **Module Loading** (lines 173-280):
   - Load 4 core modules: CoreInfrastructure, UserInterface, LogProcessor, ReportGeneration
   - Load 7 Type2 modules: SystemInventory, BloatwareRemoval, EssentialApps, SystemOptimization, TelemetryDisable, WindowsUpdates, AppUpgrade
   - Each Type2 module internally imports its Type1 counterpart

**Phase 3: Configuration Loading (MaintenanceOrchestrator.ps1:281-503)**
1. **Configuration System** (lines 302-350):
   ```powershell
   Initialize-ConfigSystem -ConfigRootPath $ConfigPath
   $MainConfig = Get-MainConfig
   $LoggingConfig = Get-LoggingConfiguration
   ```
2. **Application Definitions** (lines 378-420):
   - Load bloatware-list.json (187 applications)
   - Load essential-apps.json (10 applications)
   - Validate configuration integrity

**Phase 4: Interactive Interface (MaintenanceOrchestrator.ps1:674-737)**
1. **Hierarchical Menu System** (20-second countdowns):
   ```
   Main Menu → [1] Execute normally (DEFAULT) | [2] Dry-run mode
   Sub Menu → [1] Execute all tasks (DEFAULT) | [2] Execute specific numbers
   ```
2. **Task Registration** (lines 599-673):
   - Register 5 available tasks with standardized functions
   - Verify all Invoke-[ModuleName] functions are available

**Phase 5: Task Execution Engine (MaintenanceOrchestrator.ps1:738-944)**
**Fixed execution sequence** for each task following the standardized flow:
```
For each task in [BloatwareRemoval, EssentialApps, SystemOptimization, TelemetryDisable, WindowsUpdates]:
  1. Start performance tracking
  2. Execute Type2 function: Invoke-[ModuleName] -Config $MainConfig [-DryRun]
     → Type2 triggers Type1: Get-[ModuleName]Analysis -Config $Config
     → Type1 creates audit logs: temp_files/data/[module]-results.json
     → Type2 analyzes Type1 logs against config to create diff
     → Type2 executes actions based on diff analysis
     → Type2 creates execution logs: temp_files/logs/[module]/execution.log
  3. Validate return structure: {Success, ItemsDetected, ItemsProcessed, Duration}
  4. Log results and continue
```

**Phase 6: Log Collection & Report Generation (MaintenanceOrchestrator.ps1:945-995)**
1. **Log Aggregation**: Collect ALL files from temp_files/data/ and temp_files/logs/
2. **Data Processing**: Aggregate Type1 audit data + Type2 execution logs
3. **Template Loading**: Load external templates from config/
4. **Report Generation**: Create comprehensive reports from all collected logs
5. **Output**: Save to parent directory (Documents/Desktop/USB root)

### **🎯 Type1 → Type2 Module Pattern (Self-Contained Architecture)**

**Critical Flow Logic (v3.0):**
The orchestrator runs Type2 modules as requested by user input from the menu. Type2 modules should trigger Type1 to provide the necessary logs for execution. Type1 modules should independently create the kind of logs that Type2 modules require. Type1 modules save their findings as structured JSON data in temp_files/data/. Type2 modules consume this Type1 data, compare it against configuration to create diff lists, then execute actions only on items in the diff list while logging all execution to temp_files/logs/[module]/. The orchestrator collects ALL logs after task completion for ReportGeneration to process into comprehensive reports.

**Every Type2 module follows this exact pattern:**

```powershell
# Requires -Version 7.0
# Type2 Module: [ModuleName].psm1

# 1. Import corresponding Type1 module (MANDATORY)
$Type1ModulePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'type1\[ModuleName]Audit.psm1'
Import-Module $Type1ModulePath -Force

# 2. Import core infrastructure (MANDATORY)
$CoreInfraPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'core\CoreInfrastructure.psm1'
Import-Module $CoreInfraPath -Force

# 3. Main execution function (MANDATORY naming pattern)
function Invoke-[ModuleName] {
    param([hashtable]$Config, [switch]$DryRun)
    
    # STEP 1: Always run Type1 detection first
    $detectionResults = Get-[ModuleName]Analysis -Config $Config
    $detectionDataPath = Join-Path $Global:ProjectPaths.TempFiles "data\[module-name]-results.json"
    $detectionResults | ConvertTo-Json -Depth 10 | Set-Content $detectionDataPath
    
    # STEP 2: Compare detection with config to create diff
    $configDataPath = Join-Path $Global:ProjectPaths.Config "[config-file].json"
    $configData = Get-Content $configDataPath | ConvertFrom-Json
    $diffList = Compare-DetectedVsConfig -Detected $detectionResults -Config $configData
    $diffPath = Join-Path $Global:ProjectPaths.TempFiles "temp\[module-name]-diff.json"
    
    # STEP 3: Process ONLY items in diff and log execution
    $executionLogDir = Join-Path $Global:ProjectPaths.TempFiles "logs\[module-name]"
    New-Item -Path $executionLogDir -ItemType Directory -Force
    $executionLogPath = Join-Path $executionLogDir "execution.log"
    
    if (-not $DryRun) {
        foreach ($item in $diffList) {
            Invoke-[ModuleName]Action -Item $item -LogPath $executionLogPath
        }
    }
    
    # STEP 4: Return standardized result
    return @{
        Success = $true
        ItemsDetected = $detectionResults.Count
        ItemsProcessed = $diffList.Count
        Duration = $executionTime.TotalMilliseconds
    }
}
```

### **🛠️ Type2 Execution Modes & Operating System Modifications (v3.0)**

**CRITICAL UNDERSTANDING**: Type2 modules operate in two distinct modes that determine whether **REAL OPERATING SYSTEM MODIFICATIONS** occur:

#### **🧪 DryRun Mode (Simulation Only)**
```powershell
# When $DryRun switch is enabled:
if ($DryRun) {
    Write-LogEntry -Level 'INFO' -Message "DRY-RUN: Would remove $($item.Name)" -LogPath $executionLogPath
    # ⚠️ NO ACTUAL CHANGES MADE TO OPERATING SYSTEM
    # ✅ All logging occurs normally for simulation analysis
    # 📊 Return counts reflect what WOULD be processed
}
```

**DryRun Characteristics:**
- **Full Detection**: Type1 modules scan and detect normally
- **Complete Analysis**: Diff lists generated with all processing logic
- **Simulation Logging**: All actions logged with "DRY-RUN: Would..." prefixes  
- **Zero OS Impact**: Absolutely no modifications to Windows system
- **Perfect Testing**: Validates configurations without system changes

#### **🚀 Live Execution Mode (REAL OS MODIFICATIONS)**
```powershell
# When $DryRun is NOT enabled - PERMANENT SYSTEM CHANGES OCCUR:
if (-not $DryRun) {
    foreach ($item in $diffList) {
        # ⚠️ ACTUAL OPERATING SYSTEM MODIFICATIONS HAPPEN HERE
        $result = Invoke-[ModuleName]Action -Item $item -LogPath $executionLogPath
        Write-LogEntry -Level 'INFO' -Message "SUCCESS: Processed $($item.Name)" -LogPath $executionLogPath
    }
}
```

**Live Mode - ACTUAL Operating System Changes Per Module:**

**🗑️ BloatwareRemoval Module - Real OS Impact:**
```powershell
# PERMANENT REMOVAL OPERATIONS:
Remove-AppxPackage -Package $item.PackageFullName  # Deletes UWP apps completely
Remove-AppxProvisionedPackage -PackageName $item.PackageName  # Prevents reinstall
& winget uninstall --id $item.Id --silent  # Removes via Package Manager
& choco uninstall $item.Name --force  # Chocolatey package removal
Start-Process -FilePath $item.UninstallString -Wait  # Registry-based uninstaller execution
```
**Actual Windows Changes:**
- **File System**: Application files, folders, and user data permanently deleted
- **Registry**: Uninstall keys, file associations, and app registrations removed
- **Start Menu**: Application shortcuts and tiles removed  
- **AppX Database**: Package entries completely purged from system
- **Disk Space**: Immediate freeing of storage space used by applications

**📦 EssentialApps Module - Real OS Impact:**
```powershell
# PERMANENT INSTALLATION OPERATIONS:
& winget install --id $item.Id --silent --accept-package-agreements  # Installs applications
& choco install $item.Name --force  # Chocolatey installation
Invoke-WebRequest -Uri $item.DownloadUrl -OutFile $installerPath; Start-Process $installerPath  # Direct downloads
```
**Actual Windows Changes:**
- **File System**: New application files installed to Program Files or AppData
- **Registry**: Application registrations, file associations, and uninstall entries created
- **Start Menu**: New application shortcuts and Start Menu entries added
- **Services**: Application-related Windows services may be installed and started
- **System PATH**: Environment variables potentially modified for command-line tools

**⚡ SystemOptimization Module - Real OS Impact:**
```powershell
# PERMANENT SYSTEM CONFIGURATION CHANGES:
Set-ItemProperty -Path $regPath -Name $valueName -Value $newValue  # Direct registry modifications
Set-Service -Name $serviceName -StartupType Disabled  # Windows service configuration changes
Disable-ScheduledTask -TaskName $taskName  # Scheduled task modifications
powercfg /setactive $powerSchemeGuid  # Power plan changes
```
**Actual Windows Changes:**
- **Registry**: Direct modification of system configuration keys and values
- **Services**: Windows service startup types and running states permanently changed
- **Scheduled Tasks**: System maintenance and background tasks disabled or modified
- **Power Management**: Power schemes and energy settings reconfigured
- **Visual Effects**: Windows animation and visual effect settings changed
- **Network Configuration**: Network adapter settings and protocol optimizations applied

**🔒 TelemetryDisable Module - Real OS Impact:**
```powershell
# PERMANENT PRIVACY CONFIGURATION CHANGES:
Set-Service -Name $telemetryService -StartupType Disabled -Status Stopped  # Service disabling
Disable-ScheduledTask -TaskName $dataCollectionTask  # Background data collection stopped
Set-ItemProperty -Path $privacyRegPath -Name $setting -Value 0  # Privacy registry settings
New-NetFirewallRule -DisplayName "Block $endpoint" -Direction Outbound -Action Block  # Firewall rules
```
**Actual Windows Changes:**
- **Services**: Telemetry and data collection services permanently disabled
- **Scheduled Tasks**: Microsoft data collection tasks stopped and disabled  
- **Registry**: Privacy-related system settings permanently modified
- **Firewall**: Outbound rules created to block telemetry endpoints
- **Group Policy**: Local policy settings applied for privacy configuration
- **Windows Features**: Optional features related to data collection disabled

**🔄 WindowsUpdates Module - Real OS Impact:**
```powershell
# PERMANENT SYSTEM UPDATES AND MODIFICATIONS:
Install-WindowsUpdate -AcceptAll -AutoReboot  # System update installation
Install-Module PSWindowsUpdate; Get-WindowsUpdate | Install-WindowsUpdate  # Update processing
```
**Actual Windows Changes:**
- **System Files**: Core Windows files, drivers, and components permanently updated
- **Security Patches**: Critical security vulnerabilities patched at system level
- **Feature Updates**: New Windows features and functionality installed
- **Driver Updates**: Hardware drivers updated for improved compatibility and performance
- **Registry**: System registry updated with new configuration and version information
- **Reboot Requirements**: System may require restart to complete update installation

#### **🛡️ Safety Mechanisms & Data Processing**

**Pre-Execution Validation:**
```powershell
# Mandatory safety checks before ANY OS modifications:
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "Administrator privileges required for system modifications"
}

# Diff-based execution ensures only config-matched items are processed:
$diffList = $detectionResults | Where-Object { 
    $configData.BloatwareList -contains $_.Name -or 
    $configData.BloatwareList | Where-Object { $_.Name -like $_ }
}
```

**Data Types Processed:**
```powershell
# Type1 Detection Data Structure (from temp_files/data/):
@{
    Name = "king.com.CandyCrushSaga"
    Source = "AppX" 
    DisplayName = "Candy Crush Saga"
    Publisher = "King"
    Version = "1.2.3.4"
    InstallPath = "C:\Program Files\WindowsApps\..."
    Size = "125MB"
    MatchedPattern = "king.com.CandyCrush*"
    Category = "Gaming"
}

# Type2 Execution Result (temp_files/logs/[module]/execution.log):
"2024-01-15 14:30:22 [INFO] Starting BloatwareRemoval processing"
"2024-01-15 14:30:23 [INFO] SUCCESS: Removed king.com.CandyCrushSaga (125MB freed)"
"2024-01-15 14:30:24 [ERROR] FAILED: Could not remove Microsoft.Office.Desktop (Access denied)"
"2024-01-15 14:30:25 [INFO] Processing complete: 15 detected, 12 successfully processed, 3 failed"
```

**⚠️ CRITICAL WARNING**: When executed without the `-DryRun` flag, Type2 modules perform **IRREVERSIBLE CHANGES** to the Windows operating system. This includes permanent software removal, system configuration changes, registry modifications, service alterations, and Windows Update installations. These modifications directly impact the running Windows environment and may require system restarts to complete.

### **🗂️ Session-Based File Organization**

**Critical Data Flow** (temp_files/ structure):
```
📁 temp_files/
├── 📁 data/                    # Type1 Detection Results
│   ├── bloatware-results.json          # BloatwareDetectionAudit findings
│   ├── essential-apps-results.json     # EssentialAppsAudit findings
│   ├── system-optimization-results.json # SystemOptimizationAudit findings
│   ├── system-inventory-results.json   # SystemInventoryAudit findings
│   ├── telemetry-results.json          # TelemetryAudit findings
│   ├── windows-updates-results.json    # WindowsUpdatesAudit findings
│   └── app-upgrade-results.json        # AppUpgradeAudit findings
├── 📁 logs/                    # Type2 Execution Logs
│   ├── system-inventory/
│   │   ├── execution.log
│   │   ├── execution-data.json (v3.1+)
│   │   └── execution-summary.json (v3.1+)
│   ├── bloatware-removal/
│   │   ├── execution.log               # Human-readable log
│   │   ├── execution-data.json         # Structured log entries (v3.1+)
│   │   └── execution-summary.json      # Module summary (v3.1+)
│   ├── essential-apps/
│   │   ├── execution.log
│   │   ├── execution-data.json (v3.1+)
│   │   └── execution-summary.json (v3.1+)
│   ├── system-optimization/
│   │   ├── execution.log
│   │   ├── execution-data.json (v3.1+)
│   │   └── execution-summary.json (v3.1+)
│   ├── telemetry-disable/
│   │   ├── execution.log
│   │   ├── execution-data.json (v3.1+)
│   │   └── execution-summary.json (v3.1+)
│   ├── windows-updates/
│   │   ├── execution.log
│   │   ├── execution-data.json (v3.1+)
│   │   └── execution-summary.json (v3.1+)
│   └── app-upgrade/
│       ├── execution.log
│       ├── execution-data.json (v3.1+)
│       └── execution-summary.json (v3.1+)
├── 📁 temp/                    # In-memory processing (not persisted)
│   └── (Diff lists created in-memory only, not saved to disk)
└── 📁 reports/                 # Generated Reports
    └── MaintenanceReport_YYYYMMDD-HHMMSS.html
```

### **📊 External Template System (config/ directory)**

**Template Files & Purposes:**
- `report-template.html` → Main HTML structure with placeholders
- `task-card-template.html` → Individual module before/after sections
- `report-styles.css` → Clean styling without chart dependencies
- `report-templates-config.json` → Module metadata, icons, descriptions

**Template Loading Process:**
```powershell
# ReportGeneration.psm1
function Get-HtmlTemplates {
    $configPath = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'config'
    $templates = @{
        Main = Get-Content (Join-Path $configPath 'report-template.html') -Raw
        TaskCard = Get-Content (Join-Path $configPath 'task-card-template.html') -Raw
        CSS = Get-Content (Join-Path $configPath 'report-styles.css') -Raw
        Config = Get-Content (Join-Path $configPath 'report-templates-config.json') | ConvertFrom-Json
    }
    return $templates
}
```
    throw "Cannot locate project root directory"
}

# Initialize global paths available to all modules
$Global:ProjectPaths = @{
    'Root' = Get-ProjectRoot
    'Config' = Join-Path $Global:ProjectPaths.Root 'config'
    'Modules' = Join-Path $Global:ProjectPaths.Root 'modules'
    'TempFiles' = Join-Path $Global:ProjectPaths.Root 'temp_files'
    'ParentDir' = Split-Path -Parent $Global:ProjectPaths.Root  # Report destination
}
```

### **📁 Session-Based File Organization (v3.0 Corrected)**
All temporary data uses **organized directories** under `temp_files/` with proper path management:

**Directory Structure**:
- `temp_files/data/` - **Type1 module detection results** (JSON structured data)
  - `bloatware-results.json` - BloatwareDetectionAudit findings
  - `essential-apps-results.json` - EssentialAppsAudit findings
  - `system-optimization-results.json` - SystemOptimizationAudit findings
  - `telemetry-results.json` - TelemetryAudit findings
  - `windows-updates-results.json` - WindowsUpdatesAudit findings
- `temp_files/logs/` - **Type2 module execution logs** (dedicated subdirectories)
  - `logs/bloatware-removal/`
    - `execution.log` - Human-readable execution log
    - `execution-data.json` - Structured log entries (v3.1+)
    - `execution-summary.json` - Module execution summary (v3.1+)
  - `logs/essential-apps/`
    - `execution.log`
    - `execution-data.json` (v3.1+)
    - `execution-summary.json` (v3.1+)
  - `logs/system-optimization/`
    - `execution.log`
    - `execution-data.json` (v3.1+)
    - `execution-summary.json` (v3.1+)
  - `logs/telemetry-disable/`
    - `execution.log`
    - `execution-data.json` (v3.1+)
    - `execution-summary.json` (v3.1+)
  - `logs/windows-updates/`
    - `execution.log`
    - `execution-data.json` (v3.1+)
    - `execution-summary.json` (v3.1+)
- `temp_files/temp/` - **In-memory processing (not persisted to disk)**
  - Note: Diff lists (items from config matched on system) are created in-memory during Type2 execution but NOT saved to disk. This is intentional for performance and security.
- `temp_files/reports/` - **All generated reports** (HTML, JSON, TXT, Summary - HTML copied to parent)

**Critical Data Flow Pattern (v3.0 Corrected with Global Paths)**:
```powershell
# Type1 modules: Save detection results to temp_files/data/
$auditDataPath = Join-Path $Global:ProjectPaths.TempFiles "data\bloatware-results.json"
$detectionResults | ConvertTo-Json -Depth 10 | Set-Content $auditDataPath

# Type2 modules: Read Type1 data, compare with config, create diff, process, log execution
$detectionDataPath = Join-Path $Global:ProjectPaths.TempFiles "data\bloatware-results.json"
$configDataPath = Join-Path $Global:ProjectPaths.Config "bloatware-list.json"

$detectionData = Get-Content $detectionDataPath | ConvertFrom-Json
$configData = Get-Content $configDataPath | ConvertFrom-Json

# Create diff: Only items from config that are actually found on system
$diffList = Compare-DetectedVsConfig -Detected $detectionData -Config $configData
$diffPath = Join-Path $Global:ProjectPaths.TempFiles "temp\bloatware-diff.json"
$diffList | ConvertTo-Json | Set-Content $diffPath

# Process ONLY items in diff list and log execution to Type2-specific directory
$executionLogDir = Join-Path $Global:ProjectPaths.TempFiles "logs\bloatware-removal"
New-Item -Path $executionLogDir -ItemType Directory -Force
$executionLogPath = Join-Path $executionLogDir "execution.log"
Write-LogEntry -Level 'INFO' -Message "Processing $($diffList.Count) items" -LogPath $executionLogPath

# ReportGeneration: Collect all data for single comprehensive report in parent directory
$reportDestination = $Global:ProjectPaths.ParentDir  # Documents/Desktop/USB root
$reportPath = Join-Path $reportDestination "MaintenanceReport_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').html"
```

### **📊 Portable Report Generation Logic (v3.0)**
The system generates **comprehensive reports** with organized storage:

**Report Organization**:
- **All Reports Generated**: `temp_files/reports/` (HTML, JSON, TXT, Summary)
- **HTML Copy Location**: Parent directory of script location
- **Script extracted to Documents\script_mentenanta**: HTML Copy → Documents\MaintenanceReport_*.html
- **Script extracted to Desktop\script_mentenanta**: HTML Copy → Desktop\MaintenanceReport_*.html  
- **Script on USB\script_mentenanta**: HTML Copy → USB_Root\MaintenanceReport_*.html
- **Filename format**: `MaintenanceReport_YYYY-MM-DD_HH-mm-ss.html`

**ReportGeneration Data Collection (v3.0)**:
```powershell
# Collect Type1 detection results from temp_files/data/
$detectionSources = @{
    'SystemInventoryResults' = Join-Path $Global:ProjectPaths.TempFiles "data\system-inventory-results.json"
    'BloatwareResults' = Join-Path $Global:ProjectPaths.TempFiles "data\bloatware-results.json"
    'EssentialAppsResults' = Join-Path $Global:ProjectPaths.TempFiles "data\essential-apps-results.json"
    'SystemOptResults' = Join-Path $Global:ProjectPaths.TempFiles "data\system-optimization-results.json"
    'TelemetryResults' = Join-Path $Global:ProjectPaths.TempFiles "data\telemetry-results.json"
    'UpdatesResults' = Join-Path $Global:ProjectPaths.TempFiles "data\windows-updates-results.json"
    'AppUpgradeResults' = Join-Path $Global:ProjectPaths.TempFiles "data\app-upgrade-results.json"
}
## 🌐 **Global Path Discovery System**

The system implements **robust portable path discovery** for universal deployment across different environments:

**Project Root Detection Pattern:**
```powershell
# CoreInfrastructure.psm1 - Global path discovery
function Get-ProjectRoot {
    # Auto-detect project root regardless of execution context
    $candidatePaths = @(
        $PSScriptRoot,                                    # Direct script execution
        (Split-Path -Parent $PSScriptRoot),              # Module execution
        $MyInvocation.PSScriptRoot,                      # Alternative context
        (Get-Location).Path                               # Current directory fallback
    )
    
    foreach ($path in $candidatePaths) {
        if (Test-Path (Join-Path $path 'MaintenanceOrchestrator.ps1')) {
            return $path
        }
    }
    
    throw "Cannot locate project root directory"
}

# Initialize global paths available to all modules
$Global:ProjectPaths = @{
    'Root' = Get-ProjectRoot
    'Config' = Join-Path $Global:ProjectPaths.Root 'config'
    'Modules' = Join-Path $Global:ProjectPaths.Root 'modules'
    'TempFiles' = Join-Path $Global:ProjectPaths.Root 'temp_files'
    'ParentDir' = Split-Path -Parent $Global:ProjectPaths.Root  # Report destination
}
```

### **📊 Portable Report Generation Logic**
The system generates **comprehensive reports** with organized storage:

**Report Organization**:
- **All Reports Generated**: `temp_files/reports/` (HTML, JSON, TXT, Summary)
- **HTML Copy Location**: Parent directory of script location
- **Script extracted to Documents\script_mentenanta**: HTML Copy → Documents\MaintenanceReport_*.html
- **Script extracted to Desktop\script_mentenanta**: HTML Copy → Desktop\MaintenanceReport_*.html  
- **Script on USB\script_mentenanta**: HTML Copy → USB_Root\MaintenanceReport_*.html
- **Filename format**: `MaintenanceReport_YYYY-MM-DD_HH-mm-ss.html`

**ReportGeneration Data Collection Pattern:**
```powershell
# Collect Type1 detection results from temp_files/data/
$detectionSources = @{
    'BloatwareResults' = Join-Path $Global:ProjectPaths.TempFiles "data\bloatware-results.json"
    'EssentialAppsResults' = Join-Path $Global:ProjectPaths.TempFiles "data\essential-apps-results.json"
    'SystemOptResults' = Join-Path $Global:ProjectPaths.TempFiles "data\system-optimization-results.json"
    'TelemetryResults' = Join-Path $Global:ProjectPaths.TempFiles "data\telemetry-results.json"
    'UpdatesResults' = Join-Path $Global:ProjectPaths.TempFiles "data\windows-updates-results.json"
}

### **Module Execution Order (Fixed Sequence)**
The orchestrator executes Type2 modules in this specific order:

1. **SystemInventory** (Always first - enables caching for other modules)
2. **BloatwareRemoval** (Cleanup before installation)
3. **EssentialApps** (Install missing software)  
4. **SystemOptimization** (Performance tuning)
5. **TelemetryDisable** (Privacy configuration)
6. **WindowsUpdates** (System updates)
7. **AppUpgrade** (Application upgrades - always last)

### **Session Data Organization Patterns**
All modules use global path variables for consistent file organization:

```powershell
# Type1 modules store detection results in temp_files/data/
$auditDataPath = Join-Path $Global:ProjectPaths.TempFiles "data\[module-name]-results.json"
$auditData | ConvertTo-Json -Depth 10 | Set-Content $auditDataPath

# Type2 modules create diff lists in temp_files/temp/
$diffPath = Join-Path $Global:ProjectPaths.TempFiles "temp\[module-name]-diff.json"
$diffList | ConvertTo-Json | Set-Content $diffPath

# Type2 modules store execution logs in temp_files/logs/[module-name]/
$executionLogDir = Join-Path $Global:ProjectPaths.TempFiles "logs\[module-name]"
New-Item -Path $executionLogDir -ItemType Directory -Force
$executionLogPath = Join-Path $executionLogDir "execution.log"
Write-LogEntry -Level 'INFO' -Message "Processing complete" -LogPath $executionLogPath

# ReportGeneration consolidates all data for single report in parent directory
$reportPath = Join-Path $Global:ProjectPaths.ParentDir "MaintenanceReport_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').html"
```

## Key Files to Reference

- **`MaintenanceOrchestrator.ps1`** - Central coordination with hierarchical menu integration (1,126 lines)
- **`modules/core/CoreInfrastructure.psm1`** - Configuration, logging, session management (29 functions)
- **`modules/core/UserInterface.psm1`** - Hierarchical countdown menus (7 functions)
- **`modules/core/ReportGenerator.psm1`** - External template-based HTML reports (6+ functions)
- **`modules/type2/[ModuleName].psm1`** - Self-contained execution modules (v3.0 pattern)
- **`modules/type1/[ModuleName]Audit.psm1`** - Detection modules (imported by Type2)
- **`config/main-config.json`** - Execution settings, countdown timers, module toggles
- **`config/report-template.html`** - External HTML report template structure
- **`config/report-styles.css`** - Report styling without chart dependencies
- **`script.bat`** - Bootstrap with admin elevation and dependency management

## 📦 **Module Import/Export Complete Reference**

### **CoreInfrastructure.psm1 - Base Module (29 Functions)**

**Purpose**: Consolidated infrastructure providing configuration management, structured logging, performance tracking, and organized file storage for all modules.

**Imports**: None (base module, no dependencies)

**Exports (29 functions organized in 5 categories)**:

#### **1. Path Discovery (3 functions)**
```powershell
Initialize-GlobalPathDiscovery()  # Auto-detect project root, set $Global:ProjectPaths
Get-MaintenanceProjectPath()      # Return project root directory path
Get-MaintenanceModulePath()       # Return specific module directory path
```

#### **2. Configuration Management (5 functions)**
```powershell
Initialize-ConfigSystem($ConfigRootPath)  # Load all JSON configurations
Get-MainConfig()                          # Return main-config.json (execution settings)
Get-BloatwareList()                       # Return bloatware-list.json (187 apps)
Get-UnifiedEssentialAppsList()            # Return essential-apps.json (10 apps)
Get-LoggingConfiguration()                # Return logging-config.json (log settings)
```

#### **3. Logging System (9 functions)**
```powershell
Initialize-LoggingSystem()                # Setup structured logging with levels
Get-VerbositySettings()                   # Get current logging verbosity
Test-ShouldLogOperation($operation)       # Check if operation should be logged
Write-LogEntry($Level, $Message, $Component, $LogPath)  # Main structured logging
Write-OperationStart($operation, $component)            # Log operation beginning
Write-OperationSuccess($operation, $result, $component) # Log successful completion
Write-OperationFailure($operation, $error, $component)  # Log error with stack trace
Write-OperationSkipped($operation, $reason, $component) # Log skipped operations
Write-DetectionLog($items, $category, $component)       # Log Type1 detection results
```

#### **4. Performance Tracking (2 functions)**
```powershell
Start-PerformanceTracking($OperationName, $Component)  # Begin timing with context
Complete-PerformanceTracking($Context)                 # End timing, calculate duration
```

#### **5. File Organization (10 functions)**
```powershell
Initialize-FileOrganization()                          # Create session directory structure
Get-SessionPath($Category, $SubCategory, $FileName)    # Get organized file path
Initialize-TempFilesStructure()                        # Create temp_files/ subdirectories
Initialize-ProcessedDataStructure()                    # Initialize processed data storage
Save-SessionData($Data, $FilePath)                     # Save data to organized location
Get-SessionData($FilePath)                             # Retrieve stored session data
Get-BloatwareConfiguration()                           # Load bloatware config with validation
Get-EssentialAppsConfiguration()                       # Load essential apps config
Save-OrganizedFile($Content, $Path)                    # Save file to organized structure
Get-ProcessedDataPath($Category, $FileName)            # Get path for processed data
```

**Global Variables Created**:
```powershell
$Global:ProjectPaths = @{
    Root      = "C:\...\script_mentenanta"
    Config    = "C:\...\script_mentenanta\config"
    Modules   = "C:\...\script_mentenanta\modules"
    TempFiles = "C:\...\script_mentenanta\temp_files"
    ParentDir = "C:\...\Documents"  # or Desktop, USB root
}

$Global:MaintenanceSession = @{
    SessionId   = "GUID"
    Timestamp   = "yyyyMMdd-HHmmss"
    Directories = @{ Data, Logs, Temp, Reports }
}
```

**Imported By**: 
- MaintenanceOrchestrator.ps1 (with `-Global` flag)
- All Type2 modules (with `-Global` flag)
- UserInterface.psm1
- ReportGenerator.psm1

**Critical Requirement**: MUST be imported with `-Global` flag for Type1 modules to access functions via scope inheritance.

---

### **UserInterface.psm1 - Interactive Menus (7 Functions)**

**Purpose**: Hierarchical countdown menus with 20-second auto-selection for both attended and unattended execution.

**Imports**: CoreInfrastructure.psm1 (for logging and configuration)

**Exports (7 functions)**:
```powershell
Show-MainMenu()                  # Hierarchical main menu (Normal/DryRun selection)
Show-TaskSelectionMenu()         # Sub-menu (All Tasks / Specific Numbers)
Show-ConfirmationDialog()        # Final confirmation before execution
Show-Progress($Current, $Total)  # Real-time progress bar updates
Show-ResultSummary($Results)     # Post-execution summary display
Start-CountdownMenu($Options)    # 20-second countdown with auto-selection
ConvertFrom-TaskNumbers($Input)  # Parse "1,3,5" to task array
```

**Used By**: MaintenanceOrchestrator.ps1 (for user interaction)

---

### **ReportGenerator.psm1 - HTML Report Generation (6+ Functions)**

**Purpose**: Generate comprehensive HTML reports using external templates from config/ directory.

**Imports**: CoreInfrastructure.psm1 (for session data and file organization)

**Exports (6+ functions)**:
```powershell
Get-HtmlTemplates()                          # Load external HTML/CSS from config/
New-MaintenanceReport($Data, $Templates)     # Generate comprehensive HTML report
Get-ModuleExecutionData()                    # Collect all temp_files/ data
Convert-ModuleDataToTaskResults($RawData)    # Transform data for reporting
New-ExecutiveSummary($ModuleResults)         # Create summary statistics section
New-ModuleReportCard($ModuleData, $Template) # Generate before/after module cards
```

**Reads From**:
- `config/report-template.html` - Main report HTML structure
- `config/task-card-template.html` - Individual module report template
- `config/report-styles.css` - Visual styling (simplified, no charts)
- `config/report-templates-config.json` - Module metadata (icons, descriptions)
- `temp_files/data/*.json` - Type1 detection results
- `temp_files/logs/*/execution.log` - Type2 execution logs
- `temp_files/temp/*-diff.json` - Processing diffs

**Outputs To**:
- `temp_files/reports/*.html` - All report formats (HTML, JSON, TXT, Summary)
- Parent Directory - MaintenanceReport_YYYY-MM-DD_HH-mm-ss.html (HTML copy)

**Used By**: MaintenanceOrchestrator.ps1 (after task execution completion)

---

### **Type1 Modules (Detection/Audit) - Standard Pattern**

**Purpose**: System scanning and detection WITHOUT modifications. Create structured JSON data for Type2 processing.

**Example: BloatwareDetectionAudit.psm1**

**Imports**: CoreInfrastructure.psm1 (available via global scope from Type2 import)

**Exports (1 main function + 4 helpers)**:
```powershell
Find-InstalledBloatware()  # Main detection function - orchestrates all scans
  ├─ Get-AppxBloatware()            # Scan UWP/Modern apps (Get-AppxPackage)
  ├─ Get-Win32Bloatware()           # Scan traditional programs (Registry)
  ├─ Get-WingetBloatware()          # Scan winget-managed apps (winget list)
  └─ Get-ChocolateyBloatware()      # Scan Chocolatey packages (choco list)
```

**Execution Flow**:
1. Load bloatware-list.json via `Get-BloatwareList()` (from CoreInfrastructure)
2. Scan system across 4 package managers
3. Match detected apps against config patterns (wildcards supported)
4. Return array of hashtables with detection metadata
5. Save results to `temp_files/data/bloatware-results.json`

**Imported By**: BloatwareRemoval.psm1 (Type2 module - internal import)

**Similar Pattern For**:
- **EssentialAppsAudit.psm1** → Exports: `Get-MissingEssentialApps()`
- **SystemOptimizationAudit.psm1** → Exports: `Get-OptimizationOpportunities()`
- **TelemetryAudit.psm1** → Exports: `Get-ActiveTelemetry()`
- **WindowsUpdatesAudit.psm1** → Exports: `Get-AvailableUpdates()`

---

### **Type2 Modules (Action/Modification) - Self-Contained Pattern**

**Purpose**: Execute system modifications based on Type1 detection results and configuration. Support DryRun simulation mode.

**Example: BloatwareRemoval.psm1**

**Imports (Self-Contained - CRITICAL ORDER)**:
```powershell
# STEP 1: Import CoreInfrastructure with -Global flag (MANDATORY)
$ModuleRoot = Split-Path -Parent $PSScriptRoot
$CoreInfraPath = Join-Path $ModuleRoot 'core\CoreInfrastructure.psm1'
Import-Module $CoreInfraPath -Force -Global -WarningAction SilentlyContinue

# STEP 2: Import Type1 module AFTER CoreInfrastructure
$Type1Path = Join-Path $ModuleRoot 'type1\BloatwareDetectionAudit.psm1'
Import-Module $Type1Path -Force -WarningAction SilentlyContinue
```

**Why `-Global` Flag is CRITICAL**:
- CoreInfrastructure exports 29 functions needed by Type1 modules
- `-Global` makes these functions available in global scope
- Type1 modules access them via scope inheritance
- WITHOUT `-Global`: Type1 fails with "command not found" errors

**Exports (1 main function + 4 action helpers)**:
```powershell
Invoke-BloatwareRemoval($Config, -DryRun)  # Main execution (v3.0 standardized)
  ├─ Remove-AppxBloatware($app)            # Remove UWP apps (Remove-AppxPackage)
  ├─ Remove-Win32Bloatware($app)           # Uninstall Win32 (UninstallString)
  ├─ Remove-WingetPackage($app)            # Remove via winget (winget uninstall)
  └─ Remove-ChocolateyPackage($app)        # Remove via Chocolatey (choco uninstall)
```

**Execution Flow (Standardized v3.0)**:
```powershell
function Invoke-BloatwareRemoval {
    param([PSCustomObject]$Config, [switch]$DryRun)
    
    # 1. Start performance tracking
    $perfContext = Start-PerformanceTracking -OperationName 'BloatwareRemoval'
    
    # 2. Call Type1 detection
    $detectionResults = Find-InstalledBloatware()  # Type1 function
    $detectionPath = Join-Path $Global:ProjectPaths.TempFiles "data\bloatware-results.json"
    $detectionResults | ConvertTo-Json -Depth 10 | Set-Content $detectionPath
    
    # 3. Load configuration and create diff
    $configData = Get-BloatwareList()  # From CoreInfrastructure
    $diffList = $detectionResults | Where-Object { 
        $configData | Where-Object { $_.Name -like $detectedItem.Name }
    }
    $diffPath = Join-Path $Global:ProjectPaths.TempFiles "temp\bloatware-diff.json"
    $diffList | ConvertTo-Json | Set-Content $diffPath
    
    # 4. Setup execution logging
    $logDir = Join-Path $Global:ProjectPaths.TempFiles "logs\bloatware-removal"
    New-Item -Path $logDir -ItemType Directory -Force | Out-Null
    $logPath = Join-Path $logDir "execution.log"
    
    # 5. Process items (with DryRun check)
    $processedCount = 0
    if (-not $DryRun) {
        foreach ($item in $diffList) {
            # Actual OS modification here
            Remove-AppxBloatware -App $item
            Write-LogEntry -Level 'INFO' -Message "SUCCESS: Removed $($item.Name)" -LogPath $logPath
            $processedCount++
        }
    } else {
        foreach ($item in $diffList) {
            Write-LogEntry -Level 'INFO' -Message "DRY-RUN: Would remove $($item.Name)" -LogPath $logPath
        }
    }
    
    # 6. Complete performance tracking
    Complete-PerformanceTracking -Context $perfContext
    
    # 7. Return standardized result object (MANDATORY)
    return @{
        Success = $true
        ItemsDetected = $detectionResults.Count
        ItemsProcessed = $processedCount
        ItemsFailed = 0
        Duration = $perfContext.ElapsedMilliseconds
        DryRun = $DryRun.IsPresent
        LogPath = $logPath
    }
}
```

**Imported By**: MaintenanceOrchestrator.ps1 (direct import for task execution)

**Similar Pattern For**:
- **EssentialApps.psm1** → Imports EssentialAppsAudit.psm1 → Exports `Invoke-EssentialApps()`
- **SystemOptimization.psm1** → Imports SystemOptimizationAudit.psm1 → Exports `Invoke-SystemOptimization()`
- **TelemetryDisable.psm1** → Imports TelemetryAudit.psm1 → Exports `Invoke-TelemetryDisable()`
- **WindowsUpdates.psm1** → Imports WindowsUpdatesAudit.psm1 → Exports `Invoke-WindowsUpdates()`

---

### **� Type2 Module Return Object Standard (v3.0)**

**MANDATORY REQUIREMENT**: All Type2 modules MUST return a standardized hashtable with the following structure:

```powershell
@{
    Success         = $true/$false          # Overall success status
    ItemsDetected   = <count>              # Total items found by Type1 audit
    ItemsProcessed  = <count>              # Items successfully processed
    ItemsFailed     = <count>              # Items that failed (optional, default 0)
    Duration        = <milliseconds>       # Execution time in milliseconds
    DryRun          = $true/$false         # Whether this was a dry-run
    LogPath         = <string>             # Path to execution log file
}
```

**Implementation Pattern**:
```powershell
function Invoke-YourModule {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Config,
        [switch]$DryRun
    )
    
    $startTime = Get-Date
    
    # Module implementation...
    $detectedCount = $detectionResults.Count
    $processedCount = 0
    $failedCount = 0
    
    # Processing logic...
    
    # Calculate duration
    $executionTime = (Get-Date) - $startTime
    
    # Return standardized result
    return @{
        Success         = ($failedCount -eq 0)
        ItemsDetected   = $detectedCount
        ItemsProcessed  = $processedCount
        ItemsFailed     = $failedCount
        Duration        = $executionTime.TotalMilliseconds
        DryRun          = $DryRun.IsPresent
        LogPath         = $executionLogPath
    }
}
```

**Verification Status**: ✅ **ALL TYPE2 MODULES COMPLIANT** (verified October 2025)
- All 7 Type2 modules use standardized return object pattern
- Orchestrator depends on this structure for report generation
- ReportGenerator expects these exact property names

**DO NOT**: Return arrays, strings, or custom objects
**DO**: Always return hashtable with exact property names shown above

---

### **�📊 Complete Module Dependency Graph**

```
MaintenanceOrchestrator.ps1
├─ Import: CoreInfrastructure.psm1 -Global
│  └─ Exports: 29 functions (config, logging, file org)
│     └─ Creates: $Global:ProjectPaths, $Global:MaintenanceSession
│
├─ Import: UserInterface.psm1
│  ├─ Imports: CoreInfrastructure.psm1
│  └─ Exports: 7 functions (menus, progress, results)
│
├─ Import: ReportGenerator.psm1
│  ├─ Imports: CoreInfrastructure.psm1
│  └─ Exports: 6+ functions (HTML report generation)
│
├─ Import: BloatwareRemoval.psm1
│  ├─ Imports: CoreInfrastructure.psm1 -Global (29 functions available)
│  ├─ Imports: BloatwareDetectionAudit.psm1
│  │  └─ Uses CoreInfrastructure via global scope inheritance
│  └─ Exports: Invoke-BloatwareRemoval()
│
├─ Import: EssentialApps.psm1
│  ├─ Imports: CoreInfrastructure.psm1 -Global
│  ├─ Imports: EssentialAppsAudit.psm1
│  └─ Exports: Invoke-EssentialApps()
│
├─ Import: SystemOptimization.psm1
│  ├─ Imports: CoreInfrastructure.psm1 -Global
│  ├─ Imports: SystemOptimizationAudit.psm1
│  └─ Exports: Invoke-SystemOptimization()
│
├─ Import: TelemetryDisable.psm1
│  ├─ Imports: CoreInfrastructure.psm1 -Global
│  ├─ Imports: TelemetryAudit.psm1
│  └─ Exports: Invoke-TelemetryDisable()
│
└─ Import: WindowsUpdates.psm1
   ├─ Imports: CoreInfrastructure.psm1 -Global
   ├─ Imports: WindowsUpdatesAudit.psm1
   └─ Exports: Invoke-WindowsUpdates()
```

## Development Conventions

### **🚨 MANDATORY: VS Code Diagnostics Monitoring (ALWAYS FIRST)**

**ABSOLUTE REQUIREMENT**: The `get_errors` tool is your PRIMARY problem discovery mechanism. Use it FIRST, use it OFTEN.

#### **Diagnostic Check Requirements:**
1. **Before ANY code analysis**: Check diagnostics to understand current problems
2. **After EVERY file edit**: Validate using `get_errors` with specific filePath
3. **When user reports issues**: Check if diagnostics already identified the problem
4. **Before suggesting solutions**: Ensure fix targets actual diagnostic errors
5. **Before completing tasks**: Verify zero critical errors in Problems panel
6. **During module development**: Continuous validation after each function addition

#### **Mandatory Diagnostic Actions:**
- ✅ **Use get_errors tool immediately** when starting any task
- ✅ **Address PSScriptAnalyzer violations first** - Fix syntax errors, use approved verbs, avoid automatic variables
- ✅ **Validate incrementally** - Check diagnostics after each file modification
- ✅ **Zero tolerance for critical errors** - Never complete tasks with unresolved errors
- ✅ **Prioritize by severity** - Error > Warning > Information > Hint
- ✅ **Document resolutions** - When fixing diagnostics issues, explain what was wrong

#### **Common Diagnostic Issues to Watch For:**
- **PSScriptAnalyzer Rules**: 
  - PSAvoidUsingWriteHost (use Write-Output or logging functions)
  - PSUseApprovedVerbs (Get-, Set-, Invoke-, Remove-, etc.)
  - PSAvoidUsingPositionalParameters
  - PSAvoidGlobalVars (use $Global:ProjectPaths correctly)
- **Syntax Errors**: Missing brackets, quotes, semicolons
- **Type Errors**: Incorrect parameter types, missing type constraints
- **Scope Issues**: Variable visibility, module import problems
- **Path Errors**: Invalid file references, broken relative paths

#### **Diagnostic-Driven Development Process:**
```
1. Run get_errors (no parameters) → See all problems
2. Analyze by file and severity → Prioritize fixes
3. Make targeted changes → Fix specific issues
4. Run get_errors (with filePath) → Verify fix worked
5. Repeat until zero critical errors → Task complete
```

#### **Tools for Diagnostic Validation:**
- `get_errors` - Primary tool for discovering problems
- `get_errors` with `filePaths` array - Check specific files after edits
- Look for PSScriptAnalyzer output in terminal if running manually
- Monitor VS Code Problems panel through diagnostic feedback

**REMEMBER**: Diagnostics are not optional - they are your PRIMARY quality assurance mechanism!

### **Code Quality Standards**
- **PowerShell 7+ required** - Use modern syntax, `using namespace`, proper error handling
- **Absolute paths always** - Never rely on relative paths due to launcher working directory changes  
- **Session-scoped operations** - All temp data must use organized temp_files directories for cleanup
- **Graceful degradation** - Modules must work even if optional dependencies fail to load
- **Structured data exchange** - Use JSON for inter-module communication, avoid global variables
- **Component-based logging** - Each module uses distinct component names for log tracking

This architecture enables **safe automation** with comprehensive rollback capabilities and detailed audit trails for enterprise Windows maintenance scenarios.

## 🎯 **v3.0 Architecture Benefits**

### **Performance Improvements:**
- **50% faster startup** - Orchestrator only loads 3 core modules instead of 8+
- **Lazy loading** - Type1 modules only loaded when Type2 needs them
- **Memory efficiency** - Unused detection modules aren't loaded unless needed
- **Simplified debugging** - Each Type2 module is self-contained with clear dependencies

### **Enhanced Reliability:**
- **Impossible to skip validation** - Type2 modules cannot act without Type1 detection
- **Self-contained modules** - Each Type2+Type1 pair operates independently
- **Atomic operations** - Detect → Validate → Act within single module scope
- **Clear error boundaries** - Failures are contained within module pairs

### **Improved Maintainability:**
- **Clear ownership** - Each Type2 module owns its Type1 dependency
- **Simplified orchestrator** - Reduced complexity to core coordination functions
- **Module coupling** - Type1/Type2 pairs are versioned together
- **Preserved UI/Reporting** - UserInterface and ReportGeneration remain orchestrator-loaded

### **Transition Requirements:**
1. **CoreInfrastructure updates** - Add missing wrapper functions for config access
2. **Type2 module refactoring** - Each must internally import its Type1 module
3. **Orchestrator simplification** - Remove complex Type1 loading, focus on Type2 execution
4. **Result collection** - Ensure Type2 modules return data for ReportGeneration
5. **Error handling standardization** - Consistent patterns across all Type2 modules

## 🎯 **Simplified Core Structure (v3.0)**

The orchestrator now loads only essential services:

```
Orchestrator loads (3 modules):
├── CoreInfrastructure.psm1  # Config + Logging + File Organization  
├── UserInterface.psm1       # Interactive Menus (preserved)
└── ReportGeneration.psm1    # Dashboard Generation (preserved)

Type2 modules (self-contained):
├── BloatwareRemoval.psm1    # → imports BloatwareDetection.psm1
├── EssentialApps.psm1       # → imports EssentialAppsAudit.psm1  
├── SystemOptimization.psm1  # → imports SystemOptimizationAudit.psm1
├── TelemetryDisable.psm1    # → imports TelemetryAudit.psm1
└── WindowsUpdates.psm1      # → imports WindowsUpdatesAudit.psm1
```

### **Module Execution Order (Fixed Sequence)**
The orchestrator executes Type2 modules in this specific order:

1. **BloatwareRemoval** (Cleanup before installation)
2. **EssentialApps** (Install missing software)  
3. **SystemOptimization** (Performance tuning)
4. **TelemetryDisable** (Privacy configuration)
5. **WindowsUpdates** (System updates last)

### **Session Data Organization Patterns (v3.0 Global Paths)**
All modules use global path variables for consistent file organization:

```powershell
# Type1 modules store detection results in temp_files/data/
$auditDataPath = Join-Path $Global:ProjectPaths.TempFiles "data\[module-name]-results.json"
$auditData | ConvertTo-Json -Depth 10 | Set-Content $auditDataPath

# Type2 modules create diff lists in temp_files/temp/
$diffPath = Join-Path $Global:ProjectPaths.TempFiles "temp\[module-name]-diff.json"
$diffList | ConvertTo-Json | Set-Content $diffPath

# Type2 modules store execution logs in temp_files/logs/[module-name]/
$executionLogDir = Join-Path $Global:ProjectPaths.TempFiles "logs\[module-name]"
New-Item -Path $executionLogDir -ItemType Directory -Force
$executionLogPath = Join-Path $executionLogDir "execution.log"
Write-LogEntry -Level 'INFO' -Message "Processing complete" -LogPath $executionLogPath

# ReportGeneration consolidates all data for single report in parent directory
$reportPath = Join-Path $Global:ProjectPaths.ParentDir "MaintenanceReport_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').html"
```
$auditData | ConvertTo-Json -Depth 10 | Set-Content $auditDataPath

# Type2 modules store execution logs
$executionLogPath = Get-SessionPath -Category 'logs' -SubCategory '[module-name]' -FileName 'execution.log'
Write-LogEntry -Level 'INFO' -Message "Processing complete" -LogPath $executionLogPath

# ReportGeneration consolidates all data
$reportPath = Get-SessionPath -Category 'reports' -FileName 'maintenance-report.html'
```

## Key Files to Reference

- **`MaintenanceOrchestrator.ps1`** - Central coordination with hierarchical menu integration
- **`modules/core/CoreInfrastructure.psm1`** - Configuration, logging, session management (consolidated)
- **`modules/core/UserInterface.psm1`** - Hierarchical countdown menus with auto-fallback (NEW)
- **`modules/core/ReportGeneration.psm1`** - Interactive HTML dashboard generation (enhanced)
- **`modules/type2/[ModuleName].psm1`** - Self-contained execution modules (v3.0 pattern)
- **`modules/type1/[ModuleName]Audit.psm1`** - Detection modules (imported by Type2)
- **`config/main-config.json`** - Execution settings, countdown timers, module toggles
- **`script.bat`** - Bootstrap with admin elevation and dependency management

## Development Conventions

### **🚨 MANDATORY: VS Code Diagnostics Monitoring**
- **Check VS Code diagnostics panel regularly** - Monitor Problems panel for errors and warnings
- **Address PSScriptAnalyzer violations immediately** - Fix syntax errors, use approved verbs, avoid automatic variables
- **Validate before commits** - Ensure zero critical errors before code changes  
- **Use diagnostic feedback proactively** - Leverage real-time error detection to maintain code quality
- **Document resolution steps** - When fixing diagnostics issues, update relevant documentation

### **Code Quality Standards**
- **PowerShell 7+ required** - Use modern syntax, `using namespace`, proper error handling
- **Absolute paths always** - Never rely on relative paths due to launcher working directory changes  
- **Session-scoped operations** - All temp data must use organized temp_files directories for cleanup
- **Graceful degradation** - Modules must work even if optional dependencies fail to load
- **Structured data exchange** - Use JSON for inter-module communication, avoid global variables
- **Component-based logging** - Each module uses distinct component names for log tracking

This architecture enables **safe automation** with comprehensive rollback capabilities and detailed audit trails for enterprise Windows maintenance scenarios.

## 🎯 **v3.0 Architecture Benefits**

### **Performance Improvements:**
- **50% faster startup** - Orchestrator only loads 3 core modules instead of 8+
- **Lazy loading** - Type1 modules only loaded when Type2 needs them
- **Memory efficiency** - Unused detection modules aren't loaded unless needed
- **Simplified debugging** - Each Type2 module is self-contained with clear dependencies

### **Enhanced Reliability:**
- **Impossible to skip validation** - Type2 modules cannot act without Type1 detection
- **Self-contained modules** - Each Type2+Type1 pair operates independently
- **Atomic operations** - Detect → Validate → Act within single module scope
- **Clear error boundaries** - Failures are contained within module pairs

### **Improved Maintainability:**
- **Clear ownership** - Each Type2 module owns its Type1 dependency
- **Simplified orchestrator** - Reduced from 1000+ lines to ~400 lines
- **Module coupling** - Type1/Type2 pairs are versioned together
- **Preserved UI/Reporting** - UserInterface and ReportGeneration remain orchestrator-loaded

### **Transition Requirements:**
1. **CoreInfrastructure updates** - Add missing wrapper functions for config access
2. **Type2 module refactoring** - Each must internally import its Type1 module
3. **Orchestrator simplification** - Remove complex Type1 loading, focus on Type2 execution
4. **Result collection** - Ensure Type2 modules return data for ReportGeneration
5. **Error handling standardization** - Consistent patterns across all Type2 modules

## 🎯 **Simplified Core Structure (v3.0)**

The orchestrator now loads only essential services:

```
Orchestrator loads (3 modules):
├── CoreInfrastructure.psm1  # Config + Logging + File Organization  
├── UserInterface.psm1       # Interactive Menus (preserved)
└── ReportGeneration.psm1    # Dashboard Generation (preserved)

Type2 modules (self-contained):
├── BloatwareRemoval.psm1    # → imports BloatwareDetection.psm1
├── EssentialApps.psm1       # → imports EssentialAppsAudit.psm1  
├── SystemOptimization.psm1  # → imports SystemOptimizationAudit.psm1
├── TelemetryDisable.psm1    # → imports TelemetryAudit.psm1
└── WindowsUpdates.psm1      # → imports WindowsUpdatesAudit.psm1
```
---

## 🚀 **Adding New Type2 Modules**

When asked to create a new maintenance module, follow the standardized v3.0 architecture pattern.

### **Quick Reference**
See **[MODULE_DEVELOPMENT_GUIDE.md](./MODULE_DEVELOPMENT_GUIDE.md)** for the condensed 10-step procedure.
See **[ADDING_NEW_MODULES.md](../ADDING_NEW_MODULES.md)** for the complete 883-line guide with full code templates.

### **Critical Requirements (AI Agent Checklist)**
When generating new module code, ensure:

1. ✅ **Type1 Module** (modules/type1/[Name]Audit.psm1):
   - Exports Get-[ModuleName]Analysis function
   - Uses Write-Verbose not 	hrow for CoreInfrastructure availability
   - Returns array of hashtables with detection results
   - Saves results to `temp_files/data/[module]-results.json`

2. ✅ **Type2 Module** (modules/type2/[Name].psm1):
   - Imports CoreInfrastructure with `-Global` flag (CRITICAL)
   - Internally imports Type1 module (self-contained pattern)
   - Exports Invoke-[ModuleName] function
   - Uses `System.Collections.Hashtable` for all file operations
   - Returns @{Success, ItemsDetected, ItemsProcessed, Duration}
   - Creates execution logs in `temp_files/logs/[module]/execution.log`

3. ✅ **Configuration** (config/[module]-config.json):
   - JSON structure with module metadata
   - Items array with patterns for detection matching
   - Enabled/settings flags

4. ✅ **Orchestrator Registration** (MaintenanceOrchestrator.ps1):
   - Add to $type2Modules array (~line 280)
   - Add to $registeredTasks hashtable (~line 800)
   - Add to $taskSequence array (~line 900)

5. ✅ **Configuration Integration**:
   - Add toggle to config/main-config.json under Execution.Modules
   - Add metadata to config/report-templates-config.json

6. ✅ **Testing**:
   - Test module import standalone
   - Test with orchestrator DryRun mode
   - Verify zero VS Code diagnostics errors
   - Test full execution with proper logging

### **Code Pattern Template (Type2 Module Essentials)**
`powershell
#Requires -Version 7.0

# CRITICAL: Import CoreInfrastructure with -Global
 = Join-Path (Split-Path -Parent ) 'core\CoreInfrastructure.psm1'
Import-Module  -Force -Global -WarningAction SilentlyContinue

# Import Type1 (self-contained)
 = Join-Path (Split-Path -Parent ) 'type1\[Name]Audit.psm1'
Import-Module  -Force -WarningAction SilentlyContinue

function Invoke-[ModuleName] {
    param([hashtable], [switch])
     = Get-Date
    
    # 1. Run Type1 detection
     = Get-[ModuleName]Analysis -Config 
     | ConvertTo-Json | Set-Content (Join-Path System.Collections.Hashtable.TempFiles "data\[module]-results.json")
    
    # 2. Load config and create diff
     = Get-Content (Join-Path System.Collections.Hashtable.Config "[module]-config.json") | ConvertFrom-Json
     =  | Where-Object { .Items.Pattern -contains .Name }
    
    # 3. Setup logging
     = Join-Path System.Collections.Hashtable.TempFiles "logs\[module]"
    New-Item -Path  -ItemType Directory -Force | Out-Null
    
    # 4. Process items (with DryRun check)
     = 0
    if (-not ) {
        foreach ( in ) {
            # YOUR ACTION LOGIC
            ++
        }
    }
    
    # 5. Return standardized result
    return @{
        Success = True
        ItemsDetected = .Count
        ItemsProcessed = 
        Duration = ((Get-Date) - ).TotalMilliseconds
    }
}

Export-ModuleMember -Function Invoke-[ModuleName]
`

### **Common Mistakes to Avoid**
- ❌ Missing -Global flag on CoreInfrastructure import
- ❌ Using relative paths instead of $Global:ProjectPaths
- ❌ Throwing errors in Type1 during initialization
- ❌ Forgetting to register in all 3 orchestrator locations
- ❌ Not handling DryRun mode correctly
- ❌ Missing standardized return object structure

### **Validation Before Completion**
Before marking module development complete, verify:
- Module loads without errors in orchestrator logs
- Function appears in Get-Command Invoke-[ModuleName]
- DryRun mode creates logs without OS modifications
- Full run creates proper temp_files structure
- Reports include new module section
- Zero critical errors in VS Code diagnostics
