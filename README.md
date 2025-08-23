
# Windows Maintenance Script - Path-Independent Multi-PC Solution

## 🎯 Overview
Advanced Windows maintenance automation script designed for seamless deployment across multiple PCs. Features location-independent execution, comprehensive error handling, and AI-assisted development architecture. Fully automated dependency installation and maintenance operations with robust path detection and permission management.

## 🚀 Key Features & Recent Enhancements (August 2025)

### ✅ **Path Independence & Multi-PC Support**
- **Universal Deployment**: Script works from any folder location (Desktop, Downloads, USB, Network drives)
- **Auto-Path Detection**: Dynamically detects script location at launch time using `%~f0`
- **Cross-Environment Compatibility**: Seamless operation across different Windows 10/11 installations
- **Scheduled Task Automation**: Creates tasks with correct paths regardless of script location

### ✅ **Enhanced Infrastructure & Error Handling**
- **Multi-Method Fallbacks**: Windows version detection, WinGet installation, PowerShell 7 setup
- **Comprehensive Permission Management**: 4-method admin privilege detection and request
- **Robust Task Creation**: 3-method scheduled task creation (SYSTEM, User, PowerShell)
- **Environment Awareness**: `script.bat` (CMD) ↔ `script.ps1` (PS7) environment handling

### ✅ **Core Maintenance Features**
- **60.6% Code Reduction**: Streamlined from 1484 to 584 lines with enhanced functionality
- **Unattended Operations**: NuGet provider auto-install, fully automated Windows Updates
- **Enhanced Restart Detection**: 10+ registry checks for Windows 10/11 compatibility  
- **Auto-Close with Countdown**: 20-second countdown with user abort option
- **Unified Logging**: Single maintenance.log file for comprehensive operation tracking

## 🔧 **Architecture & Components**

### **Environment Requirements**
- **Command Prompt Environment**: `script.bat` runs in CMD on fresh Windows 10/11 installations
- **PowerShell 7 Environment**: `script.ps1` automatically runs in PS7 environment
- **Path Independence**: Must work from any folder location with automatic path detection
- **Multi-PC Deployment**: Seamless operation across different hardware and configurations

### 🚨 **Critical Environment Awareness**
- **script.bat**: Executes in CMD environment ONLY - avoid PowerShell-specific syntax
- **script.ps1**: Executes in PowerShell 7 environment ONLY - full PowerShell capabilities available
- **Syntax Separation**: Keep CMD and PowerShell syntax completely separate - never mix environments
- **Error Handling**: CMD uses `%ERRORLEVEL%` while PowerShell uses `try/catch` blocks

### 🔧 **Current Architecture (v2.0 - Copilot Optimized)**

#### **Script Components**
- **`script.bat`** (584 lines): Optimized launcher with dependency management, enhanced restart detection, 20s auto-close
- **`script.ps1`** (~5400 lines): Modular PowerShell maintenance orchestrator with comprehensive task system
- **`copilot-instructions.md`**: AI development guide with function indexing and editing conventions
- **`config.json`**: Optional JSON configuration for task customization and feature toggles

#### **Task Architecture - 12 Maintenance Operations**
```
[1] SystemRestoreProtection   - Create safety checkpoint before maintenance
[2] SystemInventory          - Comprehensive system documentation  
[3] EventLogAnalysis         - 96-hour error detection and reporting
[4] RemoveBloatware          - Multi-method unwanted app removal
[5] InstallEssentialApps     - Parallel curated app installation
[6] UpdateAllPackages        - Ultra-parallel package updates
[7] WindowsUpdateCheck       - Unattended Windows Update with -IgnoreReboot
[8] DisableTelemetry         - Privacy-focused telemetry disabling
[9] TaskbarOptimization      - Interface cleanup + local search only
[10] SecurityHardening       - Security feature enablement
[11] CleanTempAndDisk        - Comprehensive system cleanup
[12] PendingRestartCheck     - 120s countdown with abort option
```

## 📋 **Execution Environment**

### **System Requirements**
- **OS**: Windows 10/11 (x64, ARM64 supported)
- **PowerShell**: 7+ preferred (auto-installed if missing)
- **Privileges**: Administrator required (auto-elevated by batch script)
- **Dependencies**: Winget, Chocolatey, PSWindowsUpdate (auto-installed)

### **Performance Characteristics**  
- **Parallel Processing**: Essential apps, package updates, bloatware removal, file cleanup
- **Unattended Operation**: No user interaction required after launch
- **Smart Filtering**: HashSet optimization, inventory-based duplicate detection
- **Error Resilience**: Comprehensive try/catch with graceful fallbacks
- **Resource Management**: Throttled parallel operations, timeout protection

## 🛠️ **Usage Instructions**

### **Basic Execution (Location Independent)**
The script works from any location - simply right-click and run as administrator:

```batch
# From Desktop
C:\Users\%USERNAME%\Desktop\script.bat

# From Downloads  
C:\Users\%USERNAME%\Downloads\script.bat

# From USB Drive
E:\MaintenanceTools\script.bat

# From Network Location
\\server\shared\scripts\script.bat
```

### **Multi-PC Deployment**
1. **Copy script.bat to any location** on target PC
2. **Right-click → Run as administrator**
3. **Script automatically detects its location** and creates scheduled tasks pointing to correct path
4. **No configuration required** - works immediately on any Windows 10/11 system

### **Scheduled Task Behavior**
- Monthly tasks created with path: `{actual-script-location}\script.bat`
- Startup tasks created with path: `{actual-script-location}\script.bat`  
- Tasks update automatically if script is moved to different location

### **Path Detection Verification**
Check the maintenance.log file to verify correct path detection:
```
[INFO] Script Full Path: C:\Users\jjimmy\Desktop\script.bat
[INFO] Script Directory: C:\Users\jjimmy\Desktop
[INFO] Monthly task will use: C:\Users\jjimmy\Desktop\script.bat
[INFO] Startup task will use: C:\Users\jjimmy\Desktop\script.bat
```

### **Configuration Options (config.json)**
```json
{
  "SkipBloatwareRemoval": false,
  "SkipEssentialApps": false,
  "SkipWindowsUpdates": false,
  "SkipTelemetryDisable": false,
  "SkipSystemRestore": false,
  "SkipEventLogAnalysis": false,
  "SkipSecurityHardening": false,
  "SkipTaskbarOptimization": false,
  "SkipPendingRestartCheck": false,
  "CustomEssentialApps": ["AppName1", "AppName2"],
  "CustomBloatwareList": ["UnwantedApp1", "UnwantedApp2"],
  "EnableVerboseLogging": false
}
```

## 📊 **Logging & Output**

### **Log Files Generated**
- **`maintenance.log`**: Unified timestamped log with all operations and errors
- **`inventory.txt`**: Comprehensive system inventory and hardware details
- **Console Output**: Color-coded real-time progress with success/warning/error indicators

### **Task Status Indicators**
- **🟢 Green**: Successful task completion
- **🟡 Yellow**: Task skipped by configuration or warnings encountered  
- **🔴 Red**: Task failed with errors (execution continues)
- **🔵 Cyan**: Task starting/in progress

## 🔄 **Version History & Changelog**

### **v2.1 - Syntax & Environment Awareness (August 2025)**
- Enhanced environment awareness documentation for CMD vs PowerShell execution
- Fixed PowerShell null comparison issues ($null on left side of comparisons)
- Improved try/catch structure in repo folder cleanup operations
- Enhanced ScriptDir parameter handling for cross-environment consistency

### **v2.0 - Copilot Optimized (August 2025)**
- Complete comment refactoring with COPILOT_TASK_ID indexing system
- Enhanced function headers with Purpose, Environment, Logic, Performance, Dependencies
- Comprehensive AI development documentation (copilot-instructions.md)
- Taskbar optimization with Start menu local search configuration
- Unified logging system across all components

### **v1.9 - Interface Optimization (August 2025)**  
- Added taskbar optimization (search bar, task view, widgets hiding)
- Windows 10/11 version detection with targeted registry modifications
- Enhanced Explorer restart functionality for immediate interface changes

### **v1.8 - Restart Management (August 2025)**
- Added PendingRestartCheck task with 120-second countdown
- Comprehensive restart detection (10+ registry checks)
- User abort option with Ctrl+C during countdown
- Windows Update unattended configuration with -IgnoreReboot -Force

### **v1.7 - Unified Logging (August 2025)**
- Implemented unified logging to single maintenance.log file
- Enhanced log formatting with timestamps and severity levels
- Coordinated logging between batch and PowerShell components

### **v1.6 - Auto-Close Enhancement (August 2025)**
- Added 20-second auto-close countdown with abort option  
- Enhanced user experience with countdown display
- Graceful script termination with maintenance completion summary

### **v1.5 - Windows 10/11 Compatibility (August 2025)**
- Enhanced pending restart detection for Windows 10/11
- Added 10+ registry check methods for comprehensive restart detection
- Improved restart detection reliability across Windows versions

### **v1.4 - Unattended Operations (August 2025)**
- Made NuGet provider installation fully unattended with environment variables
- Enhanced Windows Update automation with unattended parameters
- Eliminated all user interaction prompts during execution

### **v1.3 - Git Removal (August 2025)**
- Completely removed Git installation and dependency
- Streamlined script focus on core Windows maintenance
- Reduced complexity and execution time

### **v1.2 - Major Refactoring (August 2025)**
- Reduced script size by 60.6% (1484→584 lines) while preserving functionality
- Eliminated temporary script generation and redundant code
- Enhanced error handling and performance optimization

## 🔧 **AI Development & Copilot Integration**

### **For AI Assistants (GitHub Copilot, etc.)**
This script includes comprehensive AI development support:

- **Function Indexing**: Each function tagged with COPILOT_TASK_ID for easy reference
- **Structured Comments**: Standardized headers with Purpose, Environment, Logic, Performance, Dependencies  
- **Section Navigation**: Clear [A.1], [B.2], [C.3] section identifiers for quick location
- **Development Guide**: Detailed copilot-instructions.md with editing conventions and architectural overview

### **Environment-Specific Syntax Rules**
```
# script.bat (CMD Environment)
- Use %ERRORLEVEL% for immediate error checking (not !ERRORLEVEL!)
- Use %variables% for variable access
- Avoid PowerShell syntax like -eq, -ne, -match
- Use simple IF statements with EQU, NEQ
- Use FOR loops with tokens for iteration

# script.ps1 (PowerShell Environment)
- Place $null on LEFT side of comparisons ($null -eq $variable)
- Always use try/catch blocks for error handling
- Use [bool], [int], [string] type accelerators for clarity
- Prefer foreach over For-Each-Object for better performance
- Always include catch blocks with try statements
```

### **Editing Conventions for AI**
```powershell
# ================================================================
# [SECTION] FUNCTION_NAME - COPILOT MAINTENANCE TASK  
# ================================================================
# COPILOT_TASK_ID: TaskName
# Purpose: Brief description
# Environment: Requirements and context
# Logic: Implementation approach  
# Performance: Optimization details
# Dependencies: Required components
# ================================================================
```

## 📞 **Support & Troubleshooting**

### **Common Issues**
- **Admin Rights**: Script auto-elevates, but manual elevation may be needed in some environments
- **PowerShell Execution Policy**: Script handles this automatically with bypass parameters
- **Network Dependencies**: Winget and Chocolatey require internet access for package management
- **Restart Requirements**: Some operations may require restart - handled by PendingRestartCheck task

### **Log Analysis**
Check `maintenance.log` for detailed operation logs with timestamps and error details. Each task logs start/completion status with color-coded console output for real-time monitoring.

---

**Current Version**: v2.1 - Syntax & Environment Awareness  
**Last Updated**: August 23, 2025  
**Total Lines**: ~5400+ (varies with ongoing development)  
**Compatibility**: Windows 10/11, PowerShell 7+, x64/ARM64

## Example Execution Flow
1. User runs `script.bat` (double-click or scheduled task).
2. Batch file checks dependencies, auto-elevates, updates repo, launches `script.ps1` as admin.
3. PowerShell script loads config, defines `$global:ScriptTasks`, and executes each task in order:
   - Inventory collection
   - Bloatware removal
   - Essential app install
   - Browser management
   - Windows updates
   - Telemetry/privacy tweaks
   - Restore/cleanup
   - Reporting
4. All output logged to `maintenance.log` and console.
5. Reports generated after completion.

## Troubleshooting
- Check `maintenance.log` for errors and warnings.
- Review `maintenance_report.txt` for summary and details.
- Ensure all dependencies are installed and up to date.
- Verify script.bat is using CMD syntax and script.ps1 is using PowerShell syntax.

## Contributing
Pull requests and feedback are welcome! See `.github/copilot-instructions.md` for AI agent conventions and best practices.

## License
[MIT](LICENSE)
  ```powershell
  # Remove non-whitelisted browsers
  # Configure Firefox, Chrome, Edge policies
  # Set Firefox as default browser
  ```

---
