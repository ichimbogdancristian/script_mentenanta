# 🏗️ **Project Architecture Visualization**

**Generated**: October 24, 2025  
**Purpose**: Visual reference for project structure and data flow

---

## 📁 **Complete Project Structure**

```
script_mentenanta/
│
├── 🚀 ENTRY POINTS
│   ├── script.bat (1394 lines) ..................... Launcher + Bootstrap
│   └── MaintenanceOrchestrator.ps1 (1416 lines) .... Central Orchestrator
│
├── 📋 DOCUMENTATION
│   ├── README.md .................................... Main documentation
│   ├── ADDING_NEW_MODULES.md ........................ Module development guide (883 lines)
│   ├── COMPREHENSIVE_ANALYSIS_AND_TODOS.md .......... Full analysis (THIS SESSION)
│   └── ANALYSIS_SUMMARY.md .......................... Quick summary (THIS SESSION)
│
├── ⚙️ CONFIG/ - All Configurations
│   ├── main-config.json ............................. Execution settings
│   ├── logging-config.json .......................... Log verbosity, levels
│   ├── bloatware-list.json .......................... 187 apps to remove
│   ├── essential-apps.json .......................... 10 apps to install
│   ├── app-upgrade-config.json ...................... App upgrade settings
│   ├── report-templates-config.json ................. Report metadata
│   ├── report-template.html ......................... Main report structure
│   ├── task-card-template.html ...................... Module section template
│   └── report-styles.css ............................ Report styling
│
├── 🧩 MODULES/
│   │
│   ├── 📦 core/ - Infrastructure (6 modules)
│   │   ├── CoreInfrastructure.psm1 (2025 lines)
│   │   │   ├── Global Path Discovery (Initialize-GlobalPathDiscovery)
│   │   │   ├── Configuration Management (Get-MainConfig, Get-BloatwareList, etc.)
│   │   │   ├── Logging System (Write-LogEntry, Start-PerformanceTracking)
│   │   │   └── File Organization (session-based temp_files management)
│   │   │
│   │   ├── UserInterface.psm1
│   │   │   ├── Hierarchical Menus (20-second countdowns)
│   │   │   ├── Progress Bars
│   │   │   └── Result Summaries
│   │   │
│   │   ├── LogProcessor.psm1 (2313 lines)
│   │   │   ├── Raw Log Collection (from temp_files/data and /logs)
│   │   │   ├── Data Processing (standardization, parsing)
│   │   │   ├── Cache Management (performance optimization)
│   │   │   └── Output: temp_files/processed/*.json
│   │   │
│   │   ├── ReportGenerator.psm1 (2384 lines)
│   │   │   ├── Template Loading (from config/)
│   │   │   ├── Processed Data Loading (from temp_files/processed/)
│   │   │   ├── HTML Report Generation
│   │   │   └── Output: Reports in parent directory
│   │   │
│   │   ├── SystemAnalysis.psm1
│   │   │   └── System inventory and diagnostics
│   │   │
│   │   └── CommonUtilities.psm1
│   │       └── Shared helper functions
│   │
│   ├── 🔍 type1/ - Detection Modules (7 modules)
│   │   ├── BloatwareDetectionAudit.psm1
│   │   │   ├── Exports: Find-InstalledBloatware ⚠️ (Should be Get-BloatwareAnalysis)
│   │   │   ├── Scans: AppX, Winget, Chocolatey, Registry
│   │   │   └── Output: temp_files/data/bloatware-results.json
│   │   │
│   │   ├── EssentialAppsAudit.psm1
│   │   │   ├── Exports: (Likely similar naming issue)
│   │   │   └── Output: temp_files/data/essential-apps-results.json
│   │   │
│   │   ├── SystemOptimizationAudit.psm1
│   │   │   └── Output: temp_files/data/system-optimization-results.json
│   │   │
│   │   ├── TelemetryAudit.psm1
│   │   │   └── Output: temp_files/data/telemetry-results.json
│   │   │
│   │   ├── WindowsUpdatesAudit.psm1
│   │   │   └── Output: temp_files/data/windows-updates-results.json
│   │   │
│   │   ├── SystemInventoryAudit.psm1
│   │   │   └── Output: temp_files/data/system-inventory-results.json
│   │   │
│   │   └── AppUpgradeAudit.psm1
│   │       └── Output: temp_files/data/app-upgrade-results.json
│   │
│   └── ⚡ type2/ - Action Modules (7 modules)
│       ├── BloatwareRemoval.psm1 (1197 lines) ✓ ANALYZED
│       │   ├── Imports: CoreInfrastructure (-Global), BloatwareDetectionAudit
│       │   ├── Exports: Invoke-BloatwareRemoval
│       │   ├── Calls: Get-BloatwareAnalysis (Type1) ⚠️ MISMATCH
│       │   ├── Creates: temp_files/temp/bloatware-diff.json
│       │   ├── Logs to: temp_files/logs/bloatware-removal/execution.log
│       │   └── Returns: {Success, ItemsDetected, ItemsProcessed, Duration}
│       │
│       ├── EssentialApps.psm1
│       │   ├── Pattern: Same as BloatwareRemoval (likely same issues)
│       │   └── Logs to: temp_files/logs/essential-apps/
│       │
│       ├── SystemOptimization.psm1
│       │   └── Logs to: temp_files/logs/system-optimization/
│       │
│       ├── TelemetryDisable.psm1
│       │   └── Logs to: temp_files/logs/telemetry-disable/
│       │
│       ├── WindowsUpdates.psm1
│       │   └── Logs to: temp_files/logs/windows-updates/
│       │
│       ├── SystemInventory.psm1
│       │   └── Logs to: temp_files/logs/system-inventory/
│       │
│       └── AppUpgrade.psm1
│           └── Logs to: temp_files/logs/app-upgrade/
│
├── 📂 temp_files/ - Session Data (Auto-created)
│   ├── data/ .............................. Type1 detection results (JSON)
│   │   ├── bloatware-results.json
│   │   ├── essential-apps-results.json
│   │   ├── system-optimization-results.json
│   │   ├── telemetry-results.json
│   │   ├── windows-updates-results.json
│   │   ├── system-inventory-results.json
│   │   └── app-upgrade-results.json
│   │
│   ├── logs/ ............................. Type2 execution logs
│   │   ├── maintenance.log ............... Launcher bootstrap log (MOVED HERE)
│   │   ├── bloatware-removal/
│   │   │   ├── execution.log ............. Human-readable text log
│   │   │   ├── execution-data.json ....... Structured log data (v3.1+)
│   │   │   └── execution-summary.json .... Module summary (v3.1+)
│   │   ├── essential-apps/
│   │   ├── system-optimization/
│   │   ├── telemetry-disable/
│   │   ├── windows-updates/
│   │   ├── system-inventory/
│   │   └── app-upgrade/
│   │
│   ├── temp/ ............................. Processing diffs
│   │   ├── bloatware-diff.json ........... Items to process (config ∩ detected)
│   │   ├── essential-apps-diff.json
│   │   └── [other]-diff.json
│   │
│   ├── processed/ ........................ LogProcessor output (NOT IN DOCS)
│   │   ├── metrics-summary.json
│   │   ├── module-results.json
│   │   ├── errors-analysis.json
│   │   ├── health-scores.json
│   │   ├── maintenance-log.json
│   │   ├── module-specific/
│   │   │   └── [module-name].json
│   │   ├── charts-data/
│   │   └── analytics/
│   │
│   └── reports/ .......................... All generated reports
│       ├── MaintenanceReport_YYYYMMDD-HHMMSS.html (ALSO COPIED TO PARENT DIR)
│       ├── MaintenanceReport_YYYYMMDD-HHMMSS.json
│       ├── MaintenanceReport_YYYYMMDD-HHMMSS.txt
│       └── ExecutiveSummary.txt
│
└── 📁 .github/ - Development Resources
    ├── copilot-instructions.md ................ AI agent guidelines
    └── MODULE_DEVELOPMENT_GUIDE.md ............ Quick reference for new modules
```

---

## 🔄 **Complete Execution Flow**

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     PHASE 1: BOOTSTRAP & INITIALIZATION                 │
└─────────────────────────────────────────────────────────────────────────┘

script.bat (CMD)
  │
  ├─► 1. Create maintenance.log in ORIGINAL SCRIPT DIRECTORY ⚠️ BUG HERE
  │      Location: Where script.bat is actually located (Desktop, USB, etc.)
  │
  ├─► 2. Check Administrator Privileges (NET SESSION)
  │
  ├─► 3. Download Repository from GitHub
  │      URL: github.com/ichimbogdancristian/script_mentenanta/archive/main.zip
  │      Extract to: script_mentenanta-main/
  │
  ├─► 4. Update WORKING_DIR to extracted folder
  │      WORKING_DIR changes from original location to extracted folder
  │
  ├─► 5. Attempt to Move maintenance.log ⚠️ FAILS
  │      Looks in: %WORKING_DIR%maintenance.log (extracted folder)
  │      But log is in: ORIGINAL_SCRIPT_DIR\maintenance.log
  │      Result: Log NOT moved, orphaned in original location
  │
  ├─► 6. Install Dependencies
  │      • Winget (3 fallback methods)
  │      • PowerShell 7+ (5 detection methods + 3 install methods)
  │      • PSWindowsUpdate module
  │
  ├─► 7. Create Monthly Scheduled Task (WindowsMaintenanceAutomation)
  │      Schedule: 1st day of month, 01:00, SYSTEM account
  │
  └─► 8. Generate PowerShell 7 Bootstrap Script (inline, temp file)
         Execute: pwsh.exe -ExecutionPolicy Bypass -File bootstrap.ps1
         
         PowerShell 7 Bootstrap:
         ├─► Add Windows Defender Exclusions (working dir, pwsh.exe)
         ├─► Verify Package Managers (winget, choco)
         ├─► Cleanup Startup Tasks (if any)
         ├─► Create System Restore Point (WindowsMaintenance-{GUID})
         └─► Execute MaintenanceOrchestrator.ps1


┌─────────────────────────────────────────────────────────────────────────┐
│              PHASE 2: ORCHESTRATOR INITIALIZATION (PowerShell 7)        │
└─────────────────────────────────────────────────────────────────────────┘

MaintenanceOrchestrator.ps1
  │
  ├─► 1. Verify Administrator Privileges (PowerShell check)
  │
  ├─► 2. Set Global Environment Variables
  │      $env:MAINTENANCE_PROJECT_ROOT = script_mentenanta/
  │      $env:MAINTENANCE_CONFIG_ROOT = script_mentenanta/config/
  │      $env:MAINTENANCE_MODULES_ROOT = script_mentenanta/modules/
  │      $env:MAINTENANCE_TEMP_ROOT = script_mentenanta/temp_files/
  │      $env:MAINTENANCE_SESSION_ID = {GUID}
  │      $env:MAINTENANCE_SESSION_TIMESTAMP = yyyyMMdd-HHmmss
  │
  ├─► 3. Create temp_files/ Directory Structure
  │      • temp_files/data/
  │      • temp_files/logs/
  │      • temp_files/temp/
  │      • temp_files/reports/
  │      • temp_files/processed/ (for LogProcessor)
  │
  ├─► 4. Load Core Modules (with -Global flag)
  │      Import-Module CoreInfrastructure.psm1 -Global
  │         ├─► Initialize-GlobalPathDiscovery (creates $Global:ProjectPaths)
  │         ├─► Initialize-ConfigSystem (loads all JSON configs)
  │         └─► Initialize-LoggingSystem
  │      Import-Module UserInterface.psm1 -Global
  │      Import-Module LogProcessor.psm1 -Global
  │      Import-Module ReportGenerator.psm1 -Global
  │
  └─► 5. Load Type2 Modules (self-contained, with -Global)
         Each Type2 module internally:
         ├─► Import-Module CoreInfrastructure.psm1 -Global ⚠️ Race condition
         └─► Import-Module [ModuleName]Audit.psm1 (Type1)


┌─────────────────────────────────────────────────────────────────────────┐
│                     PHASE 3: USER INTERACTION                           │
└─────────────────────────────────────────────────────────────────────────┘

UserInterface.psm1
  │
  ├─► Main Menu (20-second countdown, auto-select [1])
  │      [1] Execute normally (DEFAULT)
  │      [2] Dry-run mode (simulation)
  │
  └─► Sub Menu (20-second countdown, auto-select [1])
         [1] Execute all tasks (DEFAULT)
         [2] Execute specific numbers (comma-separated: 1,3,5)


┌─────────────────────────────────────────────────────────────────────────┐
│                    PHASE 4: TASK EXECUTION (Fixed Sequence)             │
└─────────────────────────────────────────────────────────────────────────┘

FOR EACH TASK in [SystemInventory, BloatwareRemoval, EssentialApps, 
                   SystemOptimization, TelemetryDisable, WindowsUpdates, AppUpgrade]:

  ┌─────────────────────────────────────────────────────────────────────┐
  │  TYPE2 MODULE EXECUTION (e.g., BloatwareRemoval.psm1)              │
  └─────────────────────────────────────────────────────────────────────┘
  
  Invoke-BloatwareRemoval -Config $MainConfig [-DryRun]
    │
    ├─► STEP 1: Call Type1 Detection
    │      $detectionResults = Get-BloatwareAnalysis -Config $Config ⚠️ MISMATCH
    │      (Actually calls: Find-InstalledBloatware)
    │      
    │      Type1 Module (BloatwareDetectionAudit.psm1):
    │      ├─► Scan AppX packages (Get-AppxPackage)
    │      ├─► Scan Winget packages (winget list)
    │      ├─► Scan Chocolatey packages (choco list)
    │      ├─► Scan Registry (Uninstall keys)
    │      └─► Return: Array of detected items
    │
    ├─► STEP 2: Save Detection Results
    │      $detectionResults | ConvertTo-Json | 
    │         Set-Content temp_files/data/bloatware-results.json
    │
    ├─► STEP 3: Load Configuration & Create Diff
    │      $configData = Get-Content config/bloatware-list.json | ConvertFrom-Json
    │      $diffList = Compare-DetectedVsConfig ⚠️ INCONSISTENT LOGIC
    │         • Diff = Items in config that were found on system
    │         • Different comparison logic across modules
    │
    ├─► STEP 4: Save Diff List
    │      $diffList | ConvertTo-Json | 
    │         Set-Content temp_files/temp/bloatware-diff.json
    │      ⚠️ CONTRADICTS DOCS: "Diff lists not saved to disk"
    │
    ├─► STEP 5: Setup Execution Logging
    │      $logDir = temp_files/logs/bloatware-removal/
    │      $logPath = temp_files/logs/bloatware-removal/execution.log
    │
    ├─► STEP 6: Process Items (DryRun vs Live)
    │      IF $DryRun:
    │         Write-StructuredLogEntry "DRY-RUN: Would remove..." ⚠️ UNDEFINED FUNCTION
    │         $processedCount = 0
    │      ELSE:
    │         FOREACH $item in $diffList:
    │            ├─► Remove-AppxBloatware (for AppX packages)
    │            ├─► Remove-Win32Bloatware (for Win32 apps)
    │            ├─► Remove-WingetPackage (for Winget apps)
    │            └─► Remove-ChocolateyPackage (for Chocolatey apps)
    │            
    │            Write-ExecutionLog "SUCCESS: Removed $item"
    │            $processedCount++
    │
    ├─► STEP 7: Create Execution Summary
    │      $summaryPath = temp_files/logs/bloatware-removal/execution-summary.json
    │      Save summary with: ModuleName, ExecutionTime, Results, SessionInfo
    │
    └─► STEP 8: Return Standardized Result
           return @{
               Success        = $true
               ItemsDetected  = $detectionResults.Count
               ItemsProcessed = $processedCount
               Duration       = $executionTime.TotalMilliseconds
           }


┌─────────────────────────────────────────────────────────────────────────┐
│              PHASE 5: LOG PROCESSING & REPORT GENERATION                │
└─────────────────────────────────────────────────────────────────────────┘

⚠️ ISSUE: LogProcessor and ReportGenerator NOT orchestrated properly

EXPECTED FLOW (from docs):
  LogProcessor → temp_files/processed/ → ReportGenerator

ACTUAL FLOW (from code):
  ├─► LogProcessor.psm1
  │      ├─► Get-Type1AuditData (scans temp_files/data/*.json)
  │      ├─► Get-Type2ExecutionLogs (scans temp_files/logs/*/execution.log)
  │      ├─► Process-RawLogs (parse, standardize, aggregate)
  │      ├─► Generate-MetricsSummary
  │      ├─► Generate-HealthScores
  │      └─► Save-ProcessedData → temp_files/processed/*.json
  │
  └─► ReportGenerator.psm1
         ├─► Get-HtmlTemplates (load from config/)
         │      ├─► report-template.html
         │      ├─► task-card-template.html
         │      ├─► report-styles.css
         │      └─► report-templates-config.json
         │
         ├─► Get-ProcessedLogData ⚠️ SHOULD CALL LogProcessor FIRST
         │      Read from: temp_files/processed/*.json
         │      If missing: Fallback to raw logs OR throw error
         │
         ├─► New-MaintenanceReport
         │      ├─► Render HTML from templates
         │      ├─► Populate data from processed logs
         │      └─► Generate multiple formats (HTML, JSON, TXT)
         │
         └─► Save Reports
                ├─► temp_files/reports/MaintenanceReport_*.html
                ├─► temp_files/reports/MaintenanceReport_*.json
                ├─► temp_files/reports/MaintenanceReport_*.txt
                └─► COPY HTML to parent directory (Desktop/Documents/USB root)


┌─────────────────────────────────────────────────────────────────────────┐
│                        PHASE 6: CLEANUP & EXIT                          │
└─────────────────────────────────────────────────────────────────────────┘

MaintenanceOrchestrator.ps1
  │
  ├─► Collect final statistics
  ├─► Display execution summary
  ├─► Show report location
  └─► Return exit code to script.bat → caller environment
```

---

## 🔍 **Critical Data Flow Paths**

### **Path 1: Configuration Loading**

```
config/main-config.json ─────────┐
config/logging-config.json ──────┤
config/bloatware-list.json ──────┤
config/essential-apps.json ──────├─► CoreInfrastructure.Initialize-ConfigSystem()
config/app-upgrade-config.json ──┤      │
config/report-templates-config.json ┘   │
                                        ▼
                                  $script:ConfigData (hashtable)
                                        │
                    ┌───────────────────┼───────────────────┐
                    ▼                   ▼                   ▼
            Get-MainConfig()    Get-BloatwareList()   Get-LoggingConfiguration()
                    │                   │                   │
                    └───────────────────┴───────────────────┘
                                        │
                                        ▼
                          Used by all Type2 modules
```

### **Path 2: Type1 Detection → Type2 Action**

```
User selects task → Orchestrator calls Invoke-[ModuleName]
                            │
                            ▼
          ┌─────────────────────────────────────────┐
          │  Type2 Module: Invoke-BloatwareRemoval  │
          └─────────────────────────────────────────┘
                            │
          ┌─────────────────┴─────────────────┐
          ▼                                   ▼
    Get-BloatwareAnalysis              Load bloatware-list.json
    (Type1 Module)                     (Configuration)
          │                                   │
          └─────────────────┬─────────────────┘
                            ▼
                    Create Diff List
                (Detected ∩ Configured)
                            │
            ┌───────────────┴───────────────┐
            ▼                               ▼
    Save to temp_files/         Execute actions on diff
    temp/bloatware-diff.json    (if not DryRun)
                                        │
                        ┌───────────────┴───────────────┐
                        ▼                               ▼
            Log to temp_files/logs/         Return standardized result
            bloatware-removal/execution.log  to Orchestrator
```

### **Path 3: Logging Pipeline**

```
Type2 Module Execution
    │
    ├─► Write-ExecutionLog ⚠️ SHOULD BE STANDARDIZED
    │      │
    │      └─► temp_files/logs/[module]/execution.log
    │
    ├─► Save-ExecutionSummary (if implemented)
    │      │
    │      └─► temp_files/logs/[module]/execution-summary.json
    │
    └─► Type1 Detection Results
           │
           └─► temp_files/data/[module]-results.json

                    ↓ ↓ ↓ (After all tasks complete)

⚠️ MISSING: Explicit orchestrator call to LogProcessor

LogProcessor.psm1 (SHOULD BE CALLED HERE)
    │
    ├─► Collect all temp_files/data/*.json
    ├─► Collect all temp_files/logs/*/execution.log
    ├─► Parse, standardize, aggregate
    │
    └─► Save to temp_files/processed/
           ├─► metrics-summary.json
           ├─► module-results.json
           ├─► errors-analysis.json
           ├─► health-scores.json
           └─► module-specific/*.json

                    ↓ ↓ ↓

ReportGenerator.psm1
    │
    ├─► Load templates from config/
    ├─► Load processed data from temp_files/processed/
    ├─► Render HTML report
    │
    └─► Save reports
           ├─► temp_files/reports/MaintenanceReport_*.html
           └─► COPY to parent directory
```

### **Path 4: Global Path Discovery**

```
script.bat sets:
  WORKING_DIR=%EXTRACTED_PATH%\

MaintenanceOrchestrator.ps1 sets:
  $env:MAINTENANCE_PROJECT_ROOT = $ScriptRoot
  $env:MAINTENANCE_CONFIG_ROOT = $ScriptRoot\config
  $env:MAINTENANCE_MODULES_ROOT = $ScriptRoot\modules
  $env:MAINTENANCE_TEMP_ROOT = $ScriptRoot\temp_files

CoreInfrastructure.Initialize-GlobalPathDiscovery():
  ├─► Check environment variables (FAST PATH)
  │      If already set by orchestrator, use them
  │
  ├─► Auto-detect from PSScriptRoot (FALLBACK)
  │      Walk up directory tree looking for:
  │      • config/ directory
  │      • modules/ directory
  │      • MaintenanceOrchestrator.ps1
  │
  └─► Create $Global:ProjectPaths
         ├─► $Global:ProjectPaths.Root
         ├─► $Global:ProjectPaths.Config
         ├─► $Global:ProjectPaths.Modules
         ├─► $Global:ProjectPaths.TempFiles
         └─► $Global:ProjectPaths.ParentDir (for reports)

⚠️ ISSUE: Each Type2 module imports CoreInfrastructure with -Global
          This triggers Initialize-GlobalPathDiscovery multiple times
          Simple flag-based locking is unreliable (race condition)

ALL MODULES use:
  $Global:ProjectPaths.TempFiles
  $Global:ProjectPaths.Config
  (Never hardcoded paths)
```

---

## ⚠️ **Critical Issues Visualized**

### **Issue #1: maintenance.log Path Problem**

```
Initial State:
  Desktop/
    script.bat ───► Creates maintenance.log here
    maintenance.log (CREATED)

After Repository Download:
  Desktop/
    script.bat
    maintenance.log (ORPHANED - stays here)
    script_mentenanta-main/ (EXTRACTED)
      ├── WORKING_DIR points here now
      ├── temp_files/
      │   └── logs/ (EMPTY - log not moved)
      └── MaintenanceOrchestrator.ps1

Expected Behavior:
  Desktop/
    script.bat
    script_mentenanta-main/
      └── temp_files/
          └── logs/
              └── maintenance.log (SHOULD BE HERE)
```

### **Issue #2: Function Name Mismatch**

```
BloatwareDetectionAudit.psm1 (Type1):
  function Find-InstalledBloatware { ... }  ◄── ACTUAL NAME
  Export-ModuleMember -Function 'Find-InstalledBloatware'

BloatwareRemoval.psm1 (Type2):
  $results = Get-BloatwareAnalysis -Config $Config  ◄── CALLED NAME
  
  ❌ RUNTIME ERROR: Get-BloatwareAnalysis not found

Documentation Says:
  Type1 should export: Get-[ModuleName]Analysis
  ✓ Get-BloatwareAnalysis
  ✓ Get-EssentialAppsAnalysis
  ✓ Get-SystemOptimizationAnalysis
```

### **Issue #3: Inconsistent Diff Logic**

```
BloatwareRemoval.psm1:
  $diffList = $detectionResults | Where-Object {
      $configData.bloatware | Where-Object { 
          $_.name -eq $item.Name -or 
          $_.packageName -eq $item.PackageName -or
          $_.path -contains $item.InstallPath  ◄── BUG: should be -like
      }
  }

EssentialApps.psm1 (likely different):
  $diffList = Compare-Items -Detected $detectionResults -Config $configData

SystemOptimization.psm1 (likely different):
  $diffList = Get-ItemsToProcess -From $detectionResults -Using $configData

⚠️ NO STANDARDIZATION - each module does it differently
```

---

## 📊 **Module Dependency Graph**

```
                         MaintenanceOrchestrator.ps1
                                    │
            ┌───────────────────────┼───────────────────────┐
            ▼                       ▼                       ▼
    CoreInfrastructure.psm1  UserInterface.psm1   ReportGenerator.psm1
         (2025 lines)                                      │
            │                                              ├─► LogProcessor.psm1
            │                                              │   (2313 lines)
            │                                              │
            └──────────────────┬───────────────────────────┘
                               │
        ┌──────────────────────┼──────────────────────┐
        ▼                      ▼                      ▼
    Type2 Modules         Type2 Modules         Type2 Modules
    (7 total)             (7 total)             (7 total)
        │                      │                      │
        │ Import -Global       │ Import -Global       │ Import -Global
        │                      │                      │
        ▼                      ▼                      ▼
    CoreInfrastructure    CoreInfrastructure    CoreInfrastructure
    (Re-imported 7x)      (Re-imported 7x)      (Re-imported 7x)
        │                      │                      │
        ▼                      ▼                      ▼
    Type1 Module          Type1 Module          Type1 Module
    BloatwareAudit        EssentialAppsAudit    SystemOptAudit
        │                      │                      │
        │ Uses global scope    │ Uses global scope    │ Uses global scope
        │                      │                      │
        └──────────────────────┴──────────────────────┘
                               │
                               ▼
                    CoreInfrastructure Functions
                    (Available via -Global import)

⚠️ Issue: CoreInfrastructure imported 1x by orchestrator + 7x by Type2 modules
          = 8 total imports with -Global flag
          = Potential race conditions in path discovery
```

---

## 📈 **File Size Analysis**

```
LARGEST FILES (by line count):

1. ReportGenerator.psm1 ............ 2,384 lines (complex HTML generation)
2. LogProcessor.psm1 ............... 2,313 lines (data processing + caching)
3. CoreInfrastructure.psm1 ......... 2,025 lines (config + logging + paths)
4. MaintenanceOrchestrator.ps1 ..... 1,416 lines (central coordination)
5. script.bat ...................... 1,394 lines (bootstrap + dependency mgmt)
6. BloatwareRemoval.psm1 ........... 1,197 lines (removal orchestration)
7. BloatwareDetectionAudit.psm1 .... 876 lines (multi-source detection)

TOTAL PROJECT: ~15,000+ lines (estimated across all modules)

SIZE RECOMMENDATIONS:
  ✓ Modules under 1,000 lines are good
  ⚠️ Modules over 2,000 lines should consider refactoring
  ⚠️ CoreInfrastructure, LogProcessor, ReportGenerator are large but cohesive
```

---

## 🎯 **Next Steps Reference**

1. **Read COMPREHENSIVE_ANALYSIS_AND_TODOS.md** for detailed issue explanations
2. **Review ANALYSIS_SUMMARY.md** for quick overview
3. **Start with Week 1 Critical Fixes**:
   - TODO-001: Fix maintenance.log path
   - TODO-002: Rename Type1 functions
   - TODO-003: Add Write-StructuredLogEntry
   - TODO-004: Fix path discovery race conditions
   - TODO-005: Centralize diff logic

**Estimated Time**: 13 hours to resolve all critical issues

---

**Document Purpose**: Visual reference for understanding project structure, data flow, and architectural relationships. Use alongside detailed analysis documents for implementation.
