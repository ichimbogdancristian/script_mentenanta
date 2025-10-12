# 📋 script.bat - Detailed Execution Timeline & Reorganization Guide

**Generated:** October 12, 2025  
**Updated:** October 13, 2025 (Post-Reorganization)  
**Purpose:** Complete chronological breakdown of script.bat execution for reorganization analysis  
**Script Version:** Windows Maintenance Automation Launcher v2.0 (1163 lines)

## 🔄 **REORGANIZATION COMPLETED**

**Major Changes Implemented:**

- ✅ **Section 11** (Working Directory Discovery) moved **after** Section 13 (Repository Extraction)
- ✅ **Section 16** (PowerShell 7 Detection) moved **after** Section 18 (Winget Installation)  
- ✅ **Section 15** (Windows Defender Exclusions) moved **after** PowerShell Installation
- ✅ **Improved dependency flow:** Winget → PowerShell → Defender Exclusions
- ✅ **Logical sequence:** Repository extraction → Directory discovery → Package management

---

## 🔍 **CURRENT EXECUTION ORDER (Detailed)**

### **PHASE 1: INITIALIZATION & ENVIRONMENT SETUP**

**Lines 1-100 | Duration: ~2-3 seconds**

1. **BATCH_INIT** (Lines 1-10)
   - `@ECHO OFF`
   - `SETLOCAL EnableDelayedExpansion EnableExtensions`
   - Set initial error handling and script variables

2. **CONFIG_LOAD** (Lines 12-65)
   - Load configuration constants (timeouts, URLs, registry paths)
   - Set GitHub repository URL and branch settings
   - Initialize default timeout values (20s menu, 30s operations)

3. **LOG_SYSTEM_INIT** (Lines 66-90)
   - Create `temp_files\` directory structure
   - Initialize session-based logging with timestamp
   - Set up `LOG_MESSAGE` function with multi-level logging
   - Create session log file with script header

4. **ADMIN_PRIVILEGE_CHECK** (Lines 91-120)
   - Test administrator privileges using `net session` command
   - If not admin: Display UAC elevation prompt
   - If not admin: Restart script with `runas` and admin rights
   - If not admin: Exit current instance
   - Log privilege verification results

### **PHASE 2: STARTUP TASK MANAGEMENT & RESTART LOGIC**

**Lines 111-180 | Duration: ~5-15 seconds (conditional restart)**

5. **STARTUP_TASK_CLEANUP** (Lines 111-125)
   - Query existing startup scheduled task: `WindowsMaintenanceStartup`
   - Remove any existing startup task from previous runs
   - Clean up orphaned startup tasks to prevent conflicts
   - Log cleanup results and task removal status

6. **PENDING_RESTART_DETECTION** (Lines 126-150)
   - **Primary Method**: Check PSWindowsUpdate module for pending updates requiring restart
   - **Fallback Method**: Query registry reboot flags:
     - `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired`
     - `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending`
   - Set `RESTART_NEEDED` flag based on detection results
   - Log pending restart status and detection method used

7. **CONDITIONAL_RESTART_HANDLING** (Lines 151-175) *[CONDITIONAL - if restart needed]*
   - **Pre-Restart Task Creation**:
     - Create `WindowsMaintenanceStartup` scheduled task with ONLOGON trigger
     - Configure task to run with HIGHEST privileges under current user
     - Set 1-minute delay after logon to allow system stabilization
     - Use `%SCHEDULED_TASK_SCRIPT_PATH%` for task execution path
   - **System Restart Sequence**:
     - Display 10-second countdown with Ctrl+C cancellation option
     - Execute `shutdown /r /t 5` with maintenance resume message  
     - Exit current script instance with code 0
   - **Error Handling**: Continue without restart if startup task creation fails

8. **POWERSHELL_RESTART_FLAG_HANDLING** (Lines 176-180)
   - Check for PowerShell 7 installation restart flags: `restart_flag.tmp`
   - Read and log restart context information from flag file
   - Clean up restart flags to prevent infinite restart loops
   - Log successful restart after PowerShell 7 installation

### **PHASE 3: MONTHLY TASK MANAGEMENT & SYSTEM REQUIREMENTS**

**Lines 181-250 | Duration: ~5-10 seconds**

9. **MONTHLY_TASK_VERIFICATION** (Lines 181-200)
   - Query existing monthly scheduled task: `WindowsMaintenanceAutomation`
   - Check if monthly maintenance task already exists
   - Log existing task details and next run time if present
   - Set task name variable: `TASK_NAME=WindowsMaintenanceAutomation`

10. **MONTHLY_TASK_CREATION** (Lines 201-235) *[CONDITIONAL - if task missing]*
    - **Task Configuration:**
      - **Name:** `WindowsMaintenanceAutomation`
      - **Trigger:** Monthly on 1st day at 01:00 (not 2:00 AM as previously documented)
      - **Execution:** Uses `%SCHEDULED_TASK_SCRIPT_PATH%` (current script location)
      - **Security:** Run as SYSTEM with highest privileges
      - **Options:** Force overwrite existing task (`/F` flag)
    - **Verification Process:**
      - Verify task creation success via schtasks exit code
      - Query created task details for confirmation
      - Extract and log "Task To Run" and "Next Run Time" information
      - Handle creation failures gracefully (continue without scheduling)

11. **SYSTEM_REQUIREMENTS_VERIFICATION** (Lines 236-250)
    - **Windows Version Detection:**
      - Primary: Use `Get-CimInstance Win32_OperatingSystem`
      - Fallback: Use `Get-WmiObject Win32_OperatingSystem` for older systems
      - Log detected Windows version for compatibility verification
    - **PowerShell Version Check:**
      - Query `$PSVersionTable.PSVersion.Major` for version detection
      - Set minimum requirement: PowerShell 5.1+
      - **Critical Check:** Exit with code 2 if PowerShell < 5.1
      - Log PowerShell version and compatibility status
    - **Requirements Validation:**
      - Ensure system meets minimum requirements before proceeding
      - Log successful system requirements verification

### **PHASE 4: PROJECT STRUCTURE & REPOSITORY MANAGEMENT**

**Lines 251-400 | Duration: ~30-60 seconds (if downloading)**

11. **WORKING_DIRECTORY_DISCOVERY** (Lines 251-280)
    - Determine if script is running from within project directory
    - Check for presence of `MaintenanceOrchestrator.ps1`
    - Set working directory based on detection results

12. **REPOSITORY_DOWNLOAD** (Lines 281-350) *[CONDITIONAL - only if not in project]*
    - Download latest repository ZIP from GitHub
    - **URL:** `https://github.com/ichimbogdancristian/script_mentenanta/archive/refs/heads/main.zip`
    - Progress logging during download
    - Verify download success and file integrity

13. **REPOSITORY_EXTRACTION** (Lines 351-380) *[CONDITIONAL]*
    - Extract ZIP file to working directory
    - Handle directory structure (remove nested folder)
    - Verify extraction success and file presence
    - Clean up temporary ZIP file

14. **ORCHESTRATOR_PATH_VALIDATION** (Lines 381-400)
    - Locate `MaintenanceOrchestrator.ps1` in project structure
    - Verify file exists and is accessible
    - Set `ORCHESTRATOR_PATH` variable for later execution

### **PHASE 5: DEPENDENCY MANAGEMENT (REORGANIZED) 🔄**

**Lines 401-650 | Duration: ~60-300 seconds (if installing)**

15. **WINGET_AVAILABILITY_CHECK** (Lines 401-430) *[🔄 MOVED BEFORE PS7 DETECTION]*
    - Test winget via PATH environment variable
    - Test winget via WindowsApps location
    - Set `WINGET_AVAILABLE` flag and executable path

16. **WINGET_INSTALLATION** (Lines 431-490) *[CONDITIONAL - if winget missing]*
    - **Method 1:** Register App Installer via PowerShell
    - **Method 2:** Install winget via Chocolatey (if available)
    - **Method 3:** Download and install App Installer MSIX manually
    - Re-verify winget availability after installation attempts

17. **POWERSHELL7_DETECTION** (Lines 491-530) *[🔄 MOVED AFTER WINGET SETUP]*
    - **Method 1:** Direct `pwsh.exe` command test
    - **Method 2:** Check default installation path: `%ProgramFiles%\PowerShell\7\pwsh.exe`
    - **Method 3:** Check WindowsApps alias: `%LocalAppData%\Microsoft\WindowsApps\pwsh.exe`
    - Set `PS7_FOUND` flag based on detection results
    - **✨ Benefits:** Winget guaranteed available for PS7 installation

18. **POWERSHELL7_INSTALLATION** (Lines 531-590) *[CONDITIONAL - if PS7 missing]*
    - **Primary Method:** Install via winget (`Microsoft.PowerShell`) - now guaranteed available
    - **Fallback 1:** Install Chocolatey, then install PS7 via Chocolatey
    - **Fallback 2:** Download MSI from GitHub releases API, silent install
    - Log installation attempts and results

19. **POST_INSTALL_RESTART** (Lines 591-620) *[CONDITIONAL - if installation occurred]*
    - Create restart flag with timestamp to prevent loops
    - Restart script with fresh environment (PATH updates)
    - Exit current instance and wait for new instance completion

20. **WINDOWS_DEFENDER_EXCLUSIONS** (Lines 621-630) *[🔄 MOVED AFTER PS INSTALLATION]*
    - Add working directory to Windows Defender exclusions
    - Add PowerShell processes to exclusions (only after confirming PS installation):
      - `powershell.exe`
      - `pwsh.exe`
    - Log exclusion setup results
    - **✨ Benefits:** Only create exclusions for confirmed PowerShell installations

21. **PACKAGE_MANAGER_VERIFICATION** (Lines 631-650)
    - Verify winget availability and capture version
    - Verify Chocolatey availability and capture version
    - Log status of all package managers

### **PHASE 6: COMPREHENSIVE POWERSHELL DETECTION**

**Lines 651-900 | Duration: ~10-15 seconds**

22. **POWERSHELL_EXECUTABLE_DETECTION** (Lines 651-720)
    - **Method 1:** Default PS7 installation path with functionality test
    - **Method 2:** PATH environment variable lookup with version validation
    - Set `PS_EXECUTABLE` and `AUTO_NONINTERACTIVE` flags

23. **ALTERNATIVE_PATH_DETECTION** (Lines 721-760)
    - **Method 3:** Check alternative installation paths:
      - `%ProgramFiles(x86)%\PowerShell\7\pwsh.exe`
      - `%LocalAppData%\Microsoft\powershell\7\pwsh.exe`
      - `%ProgramData%\chocolatey\lib\powershell-core\tools\pwsh.exe`
    - Test each path for functionality and version compatibility

24. **SYSTEM_SEARCH_METHODS** (Lines 761-820)
    - **Method 4:** Windows `where` command to locate pwsh.exe
    - **Method 5:** Registry-based PowerShell 7 detection
    - **Method 6:** Manual PATH directory analysis
    - Comprehensive search across all system locations

25. **WINDOWS_POWERSHELL_FALLBACK** (Lines 821-860)
    - If PS7+ not found, attempt Windows PowerShell 5.1+ detection
    - Test absolute path: `%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe`
    - Test PATH-based `powershell.exe`
    - Log compatibility warnings for PS5.1 usage

26. **CRITICAL_ERROR_HANDLING** (Lines 861-900)
    - If no suitable PowerShell found, display comprehensive troubleshooting
    - List all 6 attempted detection methods
    - Provide installation instructions and requirements
    - Exit with error code if PowerShell unavailable

### **PHASE 7: SYSTEM PROTECTION & BACKUP**

**Lines 901-1000 | Duration: ~30-60 seconds**

27. **SYSTEM_PROTECTION_ENABLEMENT** (Lines 901-940)
    - Check if System Restore is enabled on system drive
    - Enable System Protection if currently disabled
    - Use both PowerShell cmdlets and CIM methods for compatibility
    - Verify enablement success and log results

28. **SYSTEM_RESTORE_POINT_CREATION** (Lines 941-1000)
    - Generate unique GUID for restore point identification
    - Create restore point with name: `MaintenanceRP-{GUID}`
    - Use `Checkpoint-Computer` with fallback to CIM methods
    - Verify restore point creation and capture metadata:
      - Sequence number
      - Creation timestamp
      - Restore point description

### **PHASE 8: ORCHESTRATOR PREPARATION & LAUNCH**

**Lines 1001-1050 | Duration: ~2-5 seconds**

29. **PRE_LAUNCH_VALIDATION** (Lines 1001-1020)
    - Verify orchestrator file exists at determined path
    - Confirm PowerShell 7+ availability (required for orchestrator)
    - Display error if PS7+ not available for orchestrator execution

30. **COMMAND_LINE_PARSING** (Lines 1021-1040)
    - Parse script arguments for orchestrator:
      - `-NonInteractive` flag
      - `-DryRun` flag  
      - `-TaskNumbers` with specific task list
    - Set automatic non-interactive mode if PS7+ detected

31. **INITIAL_ORCHESTRATOR_RUN** (Lines 1041-1050)
    - Execute orchestrator in initialization mode (no arguments)
    - Capture initialization exit code
    - Set working directory to project root

### **PHASE 9: EXECUTION MODE DETERMINATION**

**Lines 1051-1080 | Duration: Variable (0-60 seconds)**

32. **MODE_DETERMINATION** (Lines 1051-1070)
    - **Non-Interactive Mode:** Direct execution if `-NonInteractive` flag
    - **Auto-Non-Interactive:** Automatic if PowerShell 7+ detected
    - **Interactive Mode:** Present menu system if neither above

33. **INTERACTIVE_MENU_SYSTEM** (Lines 1071-1080) *[CONDITIONAL - interactive mode only]*
    - Display execution mode selection (20 second timeout)
    - Handle user input or default selection

### **PHASE 10: MENU NAVIGATION & USER INTERACTION**

**Lines 1081-1130 | Duration: 0-60 seconds (user dependent)**

34. **MAIN_MENU_PROCESSING** (Lines 1081-1100)
    - **Option 1:** Normal execution path
    - **Option 2:** Dry-run execution path
    - Route to appropriate sub-menu based on selection

35. **SUB_MENU_PROCESSING** (Lines 1101-1130)
    - **Normal Sub-Menu:** All tasks vs specific task numbers
    - **Dry-Run Sub-Menu:** All tasks vs specific task numbers (dry-run mode)
    - Handle task number input and validation
    - Set execution parameters based on selections

### **PHASE 11: FINAL ORCHESTRATOR EXECUTION**

**Lines 1131-1145 | Duration: Variable (minutes to hours)**

36. **FINAL_EXECUTION_ROUTING** (Lines 1131-1145)
    - Execute orchestrator with determined parameters:
      - **Mode:** `-NonInteractive` (always for final execution)
      - **Options:** `-DryRun` if selected
      - **Tasks:** `-TaskNumbers "1,3,5"` if specific tasks chosen
    - Capture final exit code for reporting

### **PHASE 12: POST-EXECUTION CLEANUP & REPORTING**

**Lines 1146-1166 | Duration: ~5-10 seconds**

37. **EXECUTION_RESULTS_ANALYSIS** (Lines 1146-1155)
    - Log final exit code (success/failure)
    - Determine overall maintenance execution status
    - Generate execution summary

38. **REPORT_DISCOVERY** (Lines 1156-1160)
    - Scan `temp_files\reports\` directory for generated reports
    - Log discovered HTML report filenames
    - Provide report location information

39. **SESSION_COMPLETION** (Lines 1161-1166)
    - Log final completion status with summary
    - In interactive mode: Display "press any key" prompt
    - Exit with final exit code (propagate orchestrator results)

---

## 🔧 **REORGANIZATION ANALYSIS**

### **CURRENT DEPENDENCIES (Cannot Be Moved)**

- **#4 (Repository Management)** → **Required before** → **#29 (Orchestrator Launch)**
- **#16-20 (PowerShell Installation)** → **Required before** → **#29 (Orchestrator Launch)**
- **#1-2 (Admin & Logging)** → **Required before** → **All other operations**

### **MOVEABLE PHASES (Safe to Reorganize)**

- **#3 (Scheduled Tasks)** → Could move after orchestrator execution
- **#5 (Dependency Management)** → Some parts could move later
- **#7 (System Protection)** → Could move after orchestrator execution
- **#6 (PowerShell Detection)** → Could move earlier for fail-fast approach

### **SUGGESTED REORGANIZATION ZONES**

**🚀 ZONE A: Critical Prerequisites (Must Stay Early)**

- Environment Setup (#1)
- Admin Verification (#2)
- Repository Management (#4)
- PowerShell Detection & Installation (#6)

**🔄 ZONE B: System Preparation (Flexible Timing)**

- Dependency Management (#5)
- System Protection (#7)
- Scheduled Tasks (#3)

**⚡ ZONE C: Execution (Fixed Order)**

- Orchestrator Launch (#8-12)

---

## 📝 **REORGANIZATION INSTRUCTIONS**

To reorganize phases, you can:

1. **Move entire phases** by cutting/pasting line ranges
2. **Split phases** into sub-components for more granular control  
3. **Reorder within zones** while respecting dependencies

**Example Reorganization:**

```
Current: 1→2→3→4→5→6→7→8→9→10→11→12
Proposed: 1→2→4→6→5→7→3→8→9→10→11→12
```

This moves Scheduled Tasks (#3) after System Protection (#7) as requested, while maintaining all critical dependencies.
