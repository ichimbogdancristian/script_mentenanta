# 📊 Complete Logging & Report Generation System Documentation

## 🎯 Overview

This document provides a comprehensive explanation of the **entire logging and report generation process** in the Windows Maintenance Automation project, including all `maintenance.log` occurrences and data flow.

---

## 📁 **Maintenance.log History & Occurrences**

### **All Occurrences Found:**

| File | Line | Context | Purpose |
|------|------|---------|---------|
| `script.bat` | 86 | `SET "LOG_FILE=%WORKING_DIR%maintenance.log"` | **Bootstrap launcher** - Creates initial log file path |
| `MaintenanceOrchestrator.ps1` | 147 | `$MainLogFile = Join-Path $TempRoot 'maintenance.log'` | **Orchestrator** - Main log in temp_files/ |
| `MaintenanceOrchestrator.ps1` | 189 | `Join-Path $ScriptRoot 'maintenance.log'` | **Fallback** - Log in script root if temp unavailable |
| `CoreInfrastructure.psm1` | 526 | `Join-Path (Get-Location) 'maintenance.log'` | **Default path** - If no explicit path provided |
| `LogProcessor.psm1` | 505-620 | Multiple references | **Log processing** - Reads and parses maintenance.log |

### **Storage Locations:**

```
Primary Location (Active):
📂 temp_files/maintenance.log                    ← Main orchestrator log (current session)

Fallback Locations (Historical):
📂 [ScriptRoot]/maintenance.log                  ← Old fallback location
📂 [WorkingDirectory]/maintenance.log            ← Batch script initial log
📂 [CurrentLocation]/maintenance.log             ← CoreInfrastructure default
```

---

## 🔄 **Complete Logging & Reporting Architecture (v3.0)**

### **Phase 1: Bootstrap Logging (script.bat)**

```
┌─────────────────────────────────────────────────────────────────┐
│                   PHASE 1: BATCH LAUNCHER                        │
│                  (script.bat - Lines 1-1075)                     │
└─────────────────────────────────────────────────────────────────┘

Step 1: Initialize Logging Function
├─ Function: LOG_MESSAGE
├─ Format: [TIMESTAMP] [LEVEL] [COMPONENT] MESSAGE
├─ Outputs:
│  ├─ Console (colored by level)
│  └─ File: %WORKING_DIR%maintenance.log
│
├─ Levels: INFO, DEBUG, SUCCESS, WARN, ERROR
└─ Components: LAUNCHER, ADMIN-CHECK, DEPENDENCIES, etc.

Step 2: Initial Bootstrap Logging
├─ Log: Script path discovery
├─ Log: Administrator privilege check
├─ Log: Network location detection
├─ Log: Pending restart handling
├─ Log: Winget installation (3 fallback methods)
├─ Log: Repository download/extraction
├─ Log: PowerShell 7+ detection (5 methods)
└─ Log: Transition to PowerShell 7

Output Location: %WORKING_DIR%maintenance.log
Example: C:\Users\Bogdan\Desktop\Projects\script_mentenanta\maintenance.log
```

**Sample Batch Logging Output:**

```batch
[2024-10-23 14:30:15] [INFO] [LAUNCHER] Starting Windows Maintenance Automation v3.0
[2024-10-23 14:30:15] [DEBUG] [LAUNCHER] Script Path: C:\Users\Bogdan\Desktop\Projects\script_mentenanta\script.bat
[2024-10-23 14:30:16] [SUCCESS] [ADMIN-CHECK] Administrator privileges confirmed
[2024-10-23 14:30:18] [INFO] [DEPENDENCIES] PowerShell 7.4.0 detected at C:\Program Files\PowerShell\7\pwsh.exe
[2024-10-23 14:30:20] [SUCCESS] [LAUNCHER] Transitioning to PowerShell 7 orchestrator
```

---

### **Phase 2: Orchestrator Logging (MaintenanceOrchestrator.ps1)**

```
┌─────────────────────────────────────────────────────────────────┐
│              PHASE 2: POWERSHELL 7 ORCHESTRATOR                  │
│          (MaintenanceOrchestrator.ps1 - Lines 1-1400)            │
└─────────────────────────────────────────────────────────────────┘

Step 1: Global Path Discovery & Session Initialization
├─ Initialize: $Global:ProjectPaths (all directory references)
├─ Create: Session ID (GUID) + Timestamp (yyyyMMdd-HHmmss)
├─ Create: temp_files/ directory structure
│  ├─ temp_files/data/           ← Type1 detection results
│  ├─ temp_files/logs/           ← Type2 execution logs
│  ├─ temp_files/temp/           ← Processing diffs
│  ├─ temp_files/reports/        ← Generated reports
│  └─ temp_files/maintenance.log ← MAIN LOG FILE (Primary)
│
└─ Set: $MainLogFile = Join-Path $TempRoot 'maintenance.log'

Step 2: Load Core Modules (with logging)
├─ Import: CoreInfrastructure.psm1 (-Global flag)
│  └─ Initializes: Logging system functions
├─ Import: UserInterface.psm1
├─ Import: LogProcessor.psm1
├─ Import: ReportGenerator.psm1
└─ Log: Each module load success/failure

Step 3: Initialize Logging System (CoreInfrastructure)
├─ Call: Initialize-LoggingSystem
├─ Load: logging-config.json
├─ Configure:
│  ├─ Log levels (DEBUG, INFO, WARN, ERROR, FATAL, SUCCESS, TRACE)
│  ├─ Verbosity settings (Minimal, Detailed, Verbose)
│  ├─ Console output (enabled)
│  ├─ File output (enabled)
│  ├─ Performance tracking (enabled)
│  └─ Log buffer size (1000 entries)
│
└─ Set: Main log path → temp_files/maintenance.log

Output Location: temp_files/maintenance.log
```

**Logging Configuration (logging-config.json):**

```json
{
  "logging": {
    "logLevel": "INFO",
    "enableConsoleLog": true,
    "enableFileLog": true,
    "enablePerformanceTracking": true,
    "logBufferSize": 1000,
    "operationVerbosity": "Detailed"
  },
  "verbosity": {
    "currentLevel": "Detailed",
    "levels": {
      "Minimal": {
        "logOperationStart": false,
        "logOperationSuccess": false,
        "logOperationFailure": true,
        "logOperationSkipped": false,
        "logDetectionResults": false,
        "logPreChecks": false,
        "logVerification": false,
        "logMetrics": false,
        "logAdditionalInfo": false,
        "logCommands": false
      },
      "Detailed": {
        "logOperationStart": true,
        "logOperationSuccess": true,
        "logOperationFailure": true,
        "logOperationSkipped": true,
        "logDetectionResults": true,
        "logPreChecks": true,
        "logVerification": true,
        "logMetrics": true,
        "logAdditionalInfo": false,
        "logCommands": false
      },
      "Verbose": {
        "logOperationStart": true,
        "logOperationSuccess": true,
        "logOperationFailure": true,
        "logOperationSkipped": true,
        "logDetectionResults": true,
        "logPreChecks": true,
        "logVerification": true,
        "logMetrics": true,
        "logAdditionalInfo": true,
        "logCommands": true
      }
    }
  }
}
```

---

### **Phase 3: Module Execution Logging (Type1 + Type2)**

```
┌─────────────────────────────────────────────────────────────────┐
│                PHASE 3: MODULE EXECUTION LOGGING                 │
│                   (Type1 → Type2 Flow)                          │
└─────────────────────────────────────────────────────────────────┘

For each module (BloatwareRemoval, EssentialApps, SystemOptimization, TelemetryDisable, WindowsUpdates):

┌──────────────────────────────────────────────────────────────┐
│ TYPE2 MODULE: Invoke-ModuleName                              │
└──────────────────────────────────────────────────────────────┘
   ↓
   STEP 1: Trigger Type1 Detection
   ├─ Call: Get-ModuleNameAnalysis -Config $Config
   ├─ Type1: Scans system (no modifications)
   ├─ Type1: Creates detection results
   ├─ Save: temp_files/data/modulename-results.json
   └─ Log to: temp_files/maintenance.log (via Write-LogEntry)
      ├─ [INFO] [MODULENAME-AUDIT] Starting detection analysis
      ├─ [DEBUG] [MODULENAME-AUDIT] Scanning AppX packages
      ├─ [DEBUG] [MODULENAME-AUDIT] Found 15 bloatware items
      └─ [SUCCESS] [MODULENAME-AUDIT] Detection complete: 15 items
   
   ↓
   STEP 2: Compare Detection vs Config (Create Diff)
   ├─ Load: config/modulename-config.json
   ├─ Compare: Detected items vs Config patterns
   ├─ Create: Diff list (items to process)
   ├─ Save: temp_files/temp/modulename-diff.json
   └─ Log to: temp_files/maintenance.log
      └─ [INFO] [MODULENAME] Created diff list: 12/15 items match config
   
   ↓
   STEP 3: Initialize Module-Specific Execution Logging
   ├─ Create: temp_files/logs/modulename/ directory
   ├─ Create: temp_files/logs/modulename/execution.log
   └─ Log Header:
      ┌────────────────────────────────────────────┐
      │ ModuleName Execution Log                    │
      │ Session: {GUID}                             │
      │ Timestamp: 2024-10-23 14:35:22             │
      │ Mode: LIVE / DRY-RUN                       │
      │ Detected Items: 15                          │
      │ Items to Process: 12                        │
      └────────────────────────────────────────────┘
   
   ↓
   STEP 4: Process Items (Real or DryRun)
   ├─ For each item in diff list:
   │  ├─ DryRun Mode:
   │  │  ├─ Log to: temp_files/logs/modulename/execution.log
   │  │  │  └─ [DRY-RUN] Would remove Microsoft.BingWeather (12.5MB)
   │  │  └─ Log to: temp_files/maintenance.log
   │  │     └─ [INFO] [MODULENAME] DRY-RUN: Simulated removal of Microsoft.BingWeather
   │  │
   │  └─ Live Mode:
   │     ├─ Execute: Actual system modification (Remove-AppxPackage, etc.)
   │     ├─ Log to: temp_files/logs/modulename/execution.log
   │     │  ├─ [INFO] Processing 'Microsoft.BingWeather'...
   │     │  ├─ [SUCCESS] Removed Microsoft.BingWeather (12.5MB freed)
   │     │  └─ [ERROR] Failed: Access denied (if error)
   │     └─ Log to: temp_files/maintenance.log
   │        ├─ [INFO] [MODULENAME] [Remove] [Microsoft.BingWeather] Starting operation
   │        ├─ [SUCCESS] [MODULENAME] [Remove] [Microsoft.BingWeather] Completed - Result: Success, Metrics: Duration=1.2s, Size=12.5MB
   │        └─ [ERROR] [MODULENAME] [Remove] [Microsoft.Office] Failed - Error: Access denied
   
   ↓
   STEP 5: Log Summary
   ├─ Log to: temp_files/logs/modulename/execution.log
   │  └─ Execution Summary:
   │     ├─ Total Detected: 15
   │     ├─ Successfully Processed: 11
   │     ├─ Failed: 1
   │     └─ Duration: 15.3 seconds
   │
   └─ Log to: temp_files/maintenance.log
      └─ [SUCCESS] [MODULENAME] Module execution complete: 11/12 processed, 1 failed

Output Locations:
- temp_files/maintenance.log                     ← Main orchestrator log (all modules)
- temp_files/logs/bloatware-removal/execution.log ← Module-specific execution
- temp_files/logs/essential-apps/execution.log
- temp_files/logs/system-optimization/execution.log
- temp_files/logs/telemetry-disable/execution.log
- temp_files/logs/windows-updates/execution.log
```

---

### **Phase 4: Log Processing (LogProcessor.psm1)**

```
┌─────────────────────────────────────────────────────────────────┐
│              PHASE 4: LOG PROCESSING & AGGREGATION               │
│              (LogProcessor.psm1 - Lines 1-2193)                  │
└─────────────────────────────────────────────────────────────────┘

Step 1: Collect All Logs
├─ Get-MaintenanceLog (Function)
│  ├─ Read: temp_files/maintenance.log
│  ├─ Parse: Log entries by level (INFO, WARN, ERROR, SUCCESS, DEBUG)
│  ├─ Count: Total entries, entries by level
│  └─ Return: Structured data with parsed content
│
├─ Get-ModuleExecutionData (Function)
│  ├─ For each module:
│  │  ├─ Load: temp_files/data/modulename-results.json (Type1 detection)
│  │  ├─ Load: temp_files/logs/modulename/execution.log (Type2 execution)
│  │  ├─ Parse: Operation logs (Start, Success, Failure, Metrics)
│  │  └─ Aggregate: Statistics, counts, durations
│  │
│  └─ Return: Module-by-module execution data
│
└─ Process and Export to: temp_files/processed/
   ├─ metrics-summary.json           ← Dashboard metrics, KPIs
   ├─ module-results.json            ← Per-module execution summaries
   ├─ errors-analysis.json           ← All errors categorized
   ├─ health-scores.json             ← System health calculations
   ├─ maintenance-log.json           ← Structured maintenance.log data
   └─ module-specific/
      ├─ bloatware-removal.json      ← Detailed module data
      ├─ essential-apps.json
      ├─ system-optimization.json
      ├─ telemetry-disable.json
      └─ windows-updates.json

Step 2: Parse Operation Logs (Enhanced Structured Format)
├─ Parse each log line for:
│  ├─ Timestamp: 2024-10-23 14:35:22.123
│  ├─ Level: INFO, WARN, ERROR, SUCCESS, DEBUG
│  ├─ Component: BLOATWARE-REMOVAL, ESSENTIAL-APPS, etc.
│  ├─ Operation: Remove, Install, Modify, Disable, Enable, Update
│  ├─ Target: Application name, registry key, service, etc.
│  ├─ Result: Success, Failed, Skipped, Pending, InProgress
│  └─ Metrics: Duration, Size, Count, etc.
│
└─ Example parsed entry:
   {
     "Timestamp": "2024-10-23T14:35:22.123",
     "Level": "SUCCESS",
     "Component": "BLOATWARE-REMOVAL",
     "Operation": "Remove",
     "Target": "Microsoft.BingWeather",
     "Result": "Success",
     "Metrics": {
       "Duration": "1.2s",
       "SpaceFreed": "12.5MB"
     },
     "Message": "Completed Remove operation successfully"
   }

Step 3: Generate Aggregated Metrics
├─ Calculate:
│  ├─ Success Rate: (Successful Tasks / Total Tasks) × 100
│  ├─ Total Duration: Sum of all task execution times
│  ├─ System Health Score: 0-100 based on optimizations applied
│  ├─ Security Score: 0-100 based on telemetry disabled
│  ├─ Error Count: Total errors across all modules
│  └─ Performance Metrics: Average task duration, peak memory usage
│
└─ Save to: temp_files/processed/metrics-summary.json

Step 4: Error Analysis
├─ Categorize errors:
│  ├─ Critical: System failures, missing dependencies
│  ├─ Warnings: Non-critical issues, skipped operations
│  └─ Info: Informational messages
│
├─ Group by:
│  ├─ Module: Which module generated the error
│  ├─ Error Type: Access denied, file not found, etc.
│  └─ Frequency: How many times each error occurred
│
└─ Save to: temp_files/processed/errors-analysis.json

Output: Structured JSON files in temp_files/processed/ for report generation
```

**Sample Processed Data Structure:**

```json
{
  "MetricsSummary": {
    "DashboardMetrics": {
      "SuccessRate": 92,
      "TotalTasks": 5,
      "SystemHealthScore": 85,
      "SecurityScore": 90
    },
    "ExecutionSummary": {
      "TotalDuration": 45.3,
      "SuccessfulTasks": 4,
      "FailedTasks": 1,
      "StartTime": "2024-10-23T14:30:00",
      "EndTime": "2024-10-23T14:30:45"
    }
  },
  "ModuleResults": {
    "BloatwareRemoval": {
      "ItemsDetected": 15,
      "ItemsProcessed": 12,
      "ItemsFailed": 1,
      "Duration": 15.3,
      "Success": true
    },
    "EssentialApps": {
      "ItemsDetected": 5,
      "ItemsProcessed": 5,
      "ItemsFailed": 0,
      "Duration": 10.2,
      "Success": true
    }
  }
}
```

---

### **Phase 5: Report Generation (ReportGenerator.psm1)**

```
┌─────────────────────────────────────────────────────────────────┐
│            PHASE 5: REPORT GENERATION & VISUALIZATION            │
│            (ReportGenerator.psm1 - Lines 1-2378)                 │
└─────────────────────────────────────────────────────────────────┘

Step 1: Load Templates from config/
├─ Load: config/report-template.html        ← Main HTML structure
├─ Load: config/task-card-template.html     ← Module sections template
├─ Load: config/report-styles.css           ← Visual styling
└─ Load: config/report-templates-config.json ← Module metadata (icons, descriptions)

Step 2: Load Processed Data
├─ Read: temp_files/processed/metrics-summary.json
├─ Read: temp_files/processed/module-results.json
├─ Read: temp_files/processed/errors-analysis.json
├─ Read: temp_files/processed/health-scores.json
├─ Read: temp_files/processed/maintenance-log.json
└─ Read: temp_files/processed/module-specific/*.json

Step 3: Generate Report Sections
├─ Dashboard Section (New-DashboardSection)
│  ├─ Success Rate Card: 92% ✅ (Green if ≥90%, Yellow if ≥70%, Red if <70%)
│  ├─ Total Tasks Card: 5 tasks
│  ├─ System Health Card: 85/100 ❤️
│  └─ Security Score Card: 90/100 🔒
│
├─ Module Sections (New-ModuleSections)
│  ├─ For each module:
│  │  ├─ Module Icon + Display Name (from config)
│  │  ├─ Before/After Statistics:
│  │  │  ├─ Items Detected: 15
│  │  │  ├─ Items Processed: 12
│  │  │  ├─ Items Failed: 1
│  │  │  └─ Duration: 15.3s
│  │  │
│  │  ├─ Detailed Operation Log Table:
│  │  │  ┌────────────────────────────────────────────────┐
│  │  │  │ Timestamp  │ Operation │ Target       │ Result  │
│  │  │  ├────────────────────────────────────────────────┤
│  │  │  │ 14:35:22   │ Remove    │ BingWeather  │ Success │
│  │  │  │ 14:35:24   │ Remove    │ CandyCrush   │ Success │
│  │  │  │ 14:35:26   │ Remove    │ Office       │ Failed  │
│  │  │  └────────────────────────────────────────────────┘
│  │  │
│  │  └─ Visual Progress Bars (CSS-based, no Chart.js)
│  │
│  └─ Render using task-card-template.html with placeholders:
│     ├─ {{MODULE_NAME}} → "Bloatware Removal"
│     ├─ {{MODULE_ICON}} → "🗑️"
│     ├─ {{ITEMS_DETECTED}} → "15"
│     ├─ {{ITEMS_PROCESSED}} → "12"
│     ├─ {{OPERATION_LOG_TABLE}} → HTML table content
│     └─ {{SUCCESS_RATE}} → "92%"
│
├─ Maintenance Log Section (New-MaintenanceLogSection)
│  ├─ Tabbed Log Viewer:
│  │  ├─ Tab: All Logs (complete maintenance.log)
│  │  ├─ Tab: Errors Only (ERROR level entries)
│  │  ├─ Tab: Warnings Only (WARN level entries)
│  │  └─ Tab: Success Only (SUCCESS level entries)
│  │
│  └─ Searchable/Filterable log viewer
│
└─ Summary Section (New-SummarySection)
   ├─ Total Execution Time: 45.3 seconds
   ├─ System Changes Summary:
   │  ├─ Applications Removed: 12
   │  ├─ Applications Installed: 5
   │  ├─ Services Disabled: 8
   │  ├─ Registry Keys Modified: 24
   │  └─ Telemetry Endpoints Blocked: 15
   │
   └─ Recommendations:
      ├─ Restart Required: Yes/No
      └─ Next Maintenance: 30 days

Step 4: Generate Multiple Report Formats
├─ HTML Report (New-MaintenanceReport)
│  ├─ File: temp_files/reports/MaintenanceReport_YYYY-MM-DD_HH-mm-ss.html
│  ├─ Content: Full interactive dashboard with CSS styling
│  └─ Copy to: Parent Directory (Desktop/Documents/USB root)
│
├─ Text Report (New-TextReportContent)
│  ├─ File: temp_files/reports/MaintenanceReport_YYYY-MM-DD_HH-mm-ss.txt
│  └─ Content: Plain text summary for quick review
│
├─ JSON Export (New-JsonExportContent)
│  ├─ File: temp_files/reports/MaintenanceReport_YYYY-MM-DD_HH-mm-ss.json
│  └─ Content: Complete structured data for automation
│
└─ Summary Report (New-SummaryReportContent)
   ├─ File: temp_files/reports/MaintenanceReport_YYYY-MM-DD_HH-mm-ss_summary.txt
   └─ Content: Executive summary (1-2 pages)

Step 5: Copy HTML Report to Parent Directory
├─ Source: temp_files/reports/MaintenanceReport_*.html
└─ Destination: Parent Directory (one level up from script_mentenanta/)
   ├─ If in Documents/script_mentenanta/ → Copy to Documents/
   ├─ If in Desktop/script_mentenanta/ → Copy to Desktop/
   └─ If on USB/script_mentenanta/ → Copy to USB root

Final Output Locations:
- temp_files/reports/*.html, *.txt, *.json    ← All reports in temp
- [ParentDir]/MaintenanceReport_*.html         ← HTML copy for easy access
```

---

## 📊 **Complete Data Flow Diagram**

```
┌──────────────────────────────────────────────────────────────────────────┐
│                      COMPLETE LOGGING & REPORTING FLOW                    │
└──────────────────────────────────────────────────────────────────────────┘

script.bat (Bootstrap)
  │
  ├─ Creates: %WORKING_DIR%maintenance.log (Initial bootstrap log)
  ├─ Logs: Admin check, dependencies, PS7 detection
  └─ Transitions to: PowerShell 7 Orchestrator
      ↓
MaintenanceOrchestrator.ps1
  │
  ├─ Creates: temp_files/maintenance.log (Primary log)
  ├─ Loads: CoreInfrastructure, UserInterface, LogProcessor, ReportGenerator
  ├─ Initializes: Logging system (Write-LogEntry function)
  │
  ├─ Executes: Type2 Modules in sequence
  │   └─ For each module:
  │       │
  │       ├─ Type2: Invoke-ModuleName
  │       │   │
  │       │   ├─ Calls: Type1 Get-ModuleNameAnalysis
  │       │   │   ├─ Scans: System for detection
  │       │   │   ├─ Saves: temp_files/data/modulename-results.json
  │       │   │   └─ Logs to: temp_files/maintenance.log [INFO/DEBUG/SUCCESS]
  │       │   │
  │       │   ├─ Compares: Detection vs Config
  │       │   │   ├─ Creates: Diff list
  │       │   │   └─ Saves: temp_files/temp/modulename-diff.json
  │       │   │
  │       │   ├─ Processes: Items in diff list
  │       │   │   ├─ Logs to: temp_files/logs/modulename/execution.log
  │       │   │   │   ├─ [INFO] Processing 'ItemName'...
  │       │   │   │   ├─ [SUCCESS] Removed 'ItemName'
  │       │   │   │   └─ [ERROR] Failed 'ItemName'
  │       │   │   │
  │       │   │   └─ Logs to: temp_files/maintenance.log
  │       │   │       ├─ [INFO] [COMPONENT] [Operation] [Target] Starting
  │       │   │       ├─ [SUCCESS] [COMPONENT] [Operation] [Target] Complete
  │       │   │       └─ [ERROR] [COMPONENT] [Operation] [Target] Failed
  │       │   │
  │       │   └─ Returns: Standardized result @{Success, ItemsDetected, ItemsProcessed, Duration}
  │       │
  │       └─ Logs to: temp_files/maintenance.log [Module execution summary]
  │
  ├─ Calls: LogProcessor to aggregate all data
  │   │
  │   ├─ Reads: temp_files/maintenance.log (orchestrator log)
  │   ├─ Reads: temp_files/data/*.json (Type1 detection results)
  │   ├─ Reads: temp_files/logs/*/execution.log (Type2 execution logs)
  │   ├─ Parses: Log entries by level, operation, component
  │   ├─ Calculates: Metrics, health scores, success rates
  │   │
  │   └─ Saves to: temp_files/processed/
  │       ├─ metrics-summary.json
  │       ├─ module-results.json
  │       ├─ errors-analysis.json
  │       ├─ health-scores.json
  │       ├─ maintenance-log.json
  │       └─ module-specific/*.json
  │
  └─ Calls: ReportGenerator to create final reports
      │
      ├─ Loads: config/report-template.html, task-card-template.html, report-styles.css
      ├─ Loads: temp_files/processed/*.json (all processed data)
      ├─ Generates: HTML dashboard with sections:
      │   ├─ Dashboard metrics (success rate, health scores)
      │   ├─ Module execution details (operation logs, statistics)
      │   ├─ Maintenance log viewer (tabbed, searchable)
      │   └─ Summary section (recommendations, next steps)
      │
      └─ Saves to:
          ├─ temp_files/reports/MaintenanceReport_*.html (full report)
          ├─ temp_files/reports/MaintenanceReport_*.txt (text summary)
          ├─ temp_files/reports/MaintenanceReport_*.json (JSON export)
          ├─ temp_files/reports/MaintenanceReport_*_summary.txt (executive summary)
          └─ [ParentDir]/MaintenanceReport_*.html (HTML copy for easy access)
```

---

## 🛠️ **Key Logging Functions**

### **1. Write-LogEntry (Primary Logging Function)**

**Location:** `CoreInfrastructure.psm1` (Lines 650-750)

**Purpose:** Centralized structured logging with component tracking and performance metrics

**Signature:**

```powershell
function Write-LogEntry {
    param(
        [string]$Level,              # DEBUG, INFO, WARN, ERROR, FATAL, SUCCESS, TRACE
        [string]$Component,          # Module/component name
        [string]$Message,            # Log message
        [hashtable]$Data = @{},      # Additional structured data
        [string]$LogPath,            # Optional specific log file
        [string]$Operation,          # Detect, Remove, Install, etc.
        [string]$Target,             # Item being operated on
        [string]$Result,             # Success, Failed, Skipped, etc.
        [hashtable]$Metrics          # Duration, Size, Count, etc.
    )
}
```

**Outputs:**

1. **Console:** Colored output based on level
2. **Main Log:** `temp_files/maintenance.log` (if no specific path)
3. **Module Log:** `temp_files/logs/[module]/execution.log` (if LogPath specified)

**Example Usage:**

```powershell
# Simple logging
Write-LogEntry -Level 'INFO' -Component 'ORCHESTRATOR' -Message 'Starting maintenance'

# Enhanced logging with operation context
Write-LogEntry -Level 'SUCCESS' -Component 'BLOATWARE-REMOVAL' `
    -Message 'Removed bloatware application' `
    -Operation 'Remove' -Target 'Microsoft.BingWeather' -Result 'Success' `
    -Metrics @{ Duration = '1.2s'; SpaceFreed = '12.5MB' } `
    -LogPath $executionLogPath
```

### **2. Write-OperationStart / Write-OperationSuccess / Write-OperationFailure**

**Location:** `CoreInfrastructure.psm1` (Lines 770-850)

**Purpose:** Standardized operation lifecycle logging

**Example:**

```powershell
# Start operation
Write-OperationStart -Component 'BLOATWARE-REMOVAL' `
    -Operation 'Remove' -Target 'Microsoft.BingWeather' `
    -LogPath $logPath -AdditionalInfo @{ Version = '4.25' }

# Success
Write-OperationSuccess -Component 'BLOATWARE-REMOVAL' `
    -Operation 'Remove' -Target 'Microsoft.BingWeather' `
    -LogPath $logPath -Metrics @{ Duration = 1.2; SpaceFreed = '12.5MB' }

# Failure
Write-OperationFailure -Component 'BLOATWARE-REMOVAL' `
    -Operation 'Remove' -Target 'Microsoft.Office' `
    -LogPath $logPath -Error 'Access denied'
```

---

## 📁 **File Structure After Execution**

```
script_mentenanta/
├─ temp_files/
│  ├─ maintenance.log                           ← MAIN ORCHESTRATOR LOG (all modules)
│  │
│  ├─ data/                                      ← Type1 Detection Results
│  │  ├─ bloatware-results.json                 ← Apps detected on system
│  │  ├─ essential-apps-results.json            ← Missing apps identified
│  │  ├─ system-optimization-results.json       ← Optimization opportunities
│  │  ├─ telemetry-results.json                 ← Active telemetry items
│  │  └─ windows-updates-results.json           ← Available updates
│  │
│  ├─ logs/                                      ← Type2 Execution Logs
│  │  ├─ bloatware-removal/execution.log        ← Detailed removal operations
│  │  ├─ essential-apps/execution.log           ← Installation operations
│  │  ├─ system-optimization/execution.log      ← Optimization operations
│  │  ├─ telemetry-disable/execution.log        ← Telemetry disable operations
│  │  └─ windows-updates/execution.log          ← Update installation operations
│  │
│  ├─ temp/                                      ← Processing Diffs
│  │  ├─ bloatware-diff.json                    ← Items to remove (config match)
│  │  ├─ essential-apps-diff.json               ← Apps to install
│  │  ├─ system-optimization-diff.json          ← Optimizations to apply
│  │  ├─ telemetry-diff.json                    ← Telemetry to disable
│  │  └─ windows-updates-diff.json              ← Updates to install
│  │
│  ├─ processed/                                 ← LogProcessor Output
│  │  ├─ metrics-summary.json                   ← Dashboard metrics
│  │  ├─ module-results.json                    ← Per-module summaries
│  │  ├─ errors-analysis.json                   ← Error categorization
│  │  ├─ health-scores.json                     ← Health calculations
│  │  ├─ maintenance-log.json                   ← Structured log data
│  │  └─ module-specific/
│  │     ├─ bloatware-removal.json
│  │     ├─ essential-apps.json
│  │     ├─ system-optimization.json
│  │     ├─ telemetry-disable.json
│  │     └─ windows-updates.json
│  │
│  └─ reports/                                   ← Final Generated Reports
│     ├─ MaintenanceReport_2024-10-23_14-30-00.html    ← Interactive dashboard
│     ├─ MaintenanceReport_2024-10-23_14-30-00.txt     ← Text summary
│     ├─ MaintenanceReport_2024-10-23_14-30-00.json    ← JSON export
│     └─ MaintenanceReport_2024-10-23_14-30-00_summary.txt ← Executive summary
│
└─ [ParentDir]/                                  ← Reports Copied to Parent
   └─ MaintenanceReport_2024-10-23_14-30-00.html ← Easy-access HTML report
      (Desktop, Documents, or USB root depending on script location)
```

---

## 🎯 **How to Modify the Logging System**

### **Change Log Verbosity:**

Edit `config/logging-config.json`:

```json
{
  "verbosity": {
    "currentLevel": "Minimal"  // Change to: Minimal, Detailed, or Verbose
  }
}
```

**Effect:**

- **Minimal:** Only errors logged
- **Detailed:** Errors + successes + operation starts (default)
- **Verbose:** Everything including debug info, metrics, commands

### **Change Log File Location:**

Edit `MaintenanceOrchestrator.ps1` (Line 147):

```powershell
# Current:
$MainLogFile = Join-Path $TempRoot 'maintenance.log'

# Change to custom location:
$MainLogFile = 'C:\CustomPath\maintenance.log'
```

### **Add Custom Log Levels:**

Edit `CoreInfrastructure.psm1` (Line 652):

```powershell
[ValidateSet('DEBUG', 'INFO', 'WARN', 'ERROR', 'FATAL', 'SUCCESS', 'TRACE', 'CUSTOM')]
[string]$Level
```

### **Disable Console Logging:**

Edit `config/logging-config.json`:

```json
{
  "logging": {
    "enableConsoleLog": false
  }
}
```

### **Change Log Format:**

Edit `CoreInfrastructure.psm1` (Lines 700-730):

```powershell
# Current format:
$formattedMessage = "[$timestamp] [$Level] [$Component] $Message"

# Change to:
$formattedMessage = "$timestamp | $Level | $Component | $Message"
```

---

## 📊 **Sample Log Outputs**

### **maintenance.log (Main Orchestrator)**

```log
[2024-10-23 14:30:00.123] [INFO] [ORCHESTRATOR] Starting Windows Maintenance Automation v3.0
[2024-10-23 14:30:01.456] [INFO] [ORCHESTRATOR] Session ID: a1b2c3d4-e5f6-7890-abcd-ef1234567890
[2024-10-23 14:30:02.789] [INFO] [ORCHESTRATOR] Execution mode: LIVE
[2024-10-23 14:30:05.123] [INFO] [BLOATWARE-REMOVAL] [Detect] [System] Starting operation - Result: InProgress
[2024-10-23 14:30:10.456] [SUCCESS] [BLOATWARE-REMOVAL] [Detect] [System] Completed operation successfully - Result: Success, Metrics: Duration=5.3s, ItemsFound=15
[2024-10-23 14:30:12.789] [INFO] [BLOATWARE-REMOVAL] Created diff list: 12/15 items match config
[2024-10-23 14:30:15.123] [INFO] [BLOATWARE-REMOVAL] [Remove] [Microsoft.BingWeather] Starting operation - Result: InProgress
[2024-10-23 14:30:16.456] [SUCCESS] [BLOATWARE-REMOVAL] [Remove] [Microsoft.BingWeather] Completed operation successfully - Result: Success, Metrics: Duration=1.2s, SpaceFreed=12.5MB
[2024-10-23 14:30:18.789] [ERROR] [BLOATWARE-REMOVAL] [Remove] [Microsoft.Office] Failed - Error: Access denied
[2024-10-23 14:30:45.123] [SUCCESS] [BLOATWARE-REMOVAL] Module execution complete: 11/12 processed, 1 failed
```

### **execution.log (Module-Specific)**

```log
========================================
Bloatware Removal Execution Log
Session: a1b2c3d4-e5f6-7890-abcd-ef1234567890
Timestamp: 2024-10-23 14:30:00
Mode: LIVE (Real Modifications)
Detected Items: 15
Items to Process: 12
========================================

[2024-10-23 14:30:15] [INFO] Processing 'Microsoft.BingWeather'...
[2024-10-23 14:30:16] [SUCCESS] Removed Microsoft.BingWeather (12.5MB freed)
[2024-10-23 14:30:17] [INFO] Processing 'king.com.CandyCrushSaga'...
[2024-10-23 14:30:18] [SUCCESS] Removed king.com.CandyCrushSaga (8.2MB freed)
[2024-10-23 14:30:19] [INFO] Processing 'Microsoft.Office.Desktop'...
[2024-10-23 14:30:20] [ERROR] FAILED: Could not remove Microsoft.Office.Desktop - Access denied

========================================
Execution Summary
========================================
Total Detected: 15
Successfully Processed: 11
Failed: 1
Duration: 15.3 seconds
========================================
```

---

## 🔍 **Summary**

The logging and reporting system uses a **multi-layered approach**:

1. **Bootstrap (script.bat):** Initial logging to working directory
2. **Orchestrator (MaintenanceOrchestrator.ps1):** Main log in temp_files/
3. **Modules (Type1+Type2):** Module-specific execution logs
4. **LogProcessor:** Aggregates and structures all logs
5. **ReportGenerator:** Creates interactive reports from processed data

**Key Files:**

- **Main Log:** `temp_files/maintenance.log` (all orchestrator + module operations)
- **Module Logs:** `temp_files/logs/[module]/execution.log` (detailed per-module)
- **Processed Data:** `temp_files/processed/*.json` (structured for reporting)
- **Final Reports:** `temp_files/reports/*.html` + Parent directory copy

**Modification Points:**

- **Verbosity:** `config/logging-config.json` → `verbosity.currentLevel`
- **Log Path:** `MaintenanceOrchestrator.ps1` → `$MainLogFile`
- **Log Format:** `CoreInfrastructure.psm1` → `Write-LogEntry` function
- **Report Templates:** `config/report-template.html`, `task-card-template.html`

This system provides **comprehensive audit trails** with **flexible reporting** for enterprise Windows maintenance automation.
