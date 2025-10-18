# Windows Maintenance Automation - AI Coding Agent Instructions

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

**Phase 1: Bootstrap (script.bat)**
1. Check/Request Administrator privileges
2. Handle pending system restart (auto-resume via scheduled task)
3. Create System Restore Point + Enable System Protection
4. Bootstrap dependencies: PowerShell 7, winget, Chocolatey, PowerShellGet
5. Setup monthly automation task (SYSTEM account, highest priority)
6. Launch MaintenanceOrchestrator.ps1

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
   - Load 3 core modules: CoreInfrastructure, UserInterface, ReportGeneration
   - Load 5 Type2 modules: BloatwareRemoval, EssentialApps, SystemOptimization, TelemetryDisable, WindowsUpdates
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

### **🗂️ Session-Based File Organization**

**Critical Data Flow** (temp_files/ structure):
```
📁 temp_files/
├── 📁 data/                    # Type1 Detection Results
│   ├── bloatware-results.json          # BloatwareDetectionAudit findings
│   ├── essential-apps-results.json     # EssentialAppsAudit findings
│   ├── system-optimization-results.json # SystemOptimizationAudit findings
│   ├── telemetry-results.json          # TelemetryAudit findings
│   └── windows-updates-results.json    # WindowsUpdatesAudit findings
├── 📁 logs/                    # Type2 Execution Logs
│   ├── bloatware-removal/execution.log     # BloatwareRemoval actions
│   ├── essential-apps/execution.log        # EssentialApps actions
│   ├── system-optimization/execution.log   # SystemOptimization actions
│   ├── telemetry-disable/execution.log     # TelemetryDisable actions
│   └── windows-updates/execution.log       # WindowsUpdates actions
├── 📁 temp/                    # Processing Diffs
│   ├── bloatware-diff.json             # Items from config found on system
│   ├── essential-apps-diff.json        # Missing apps ready for installation
│   ├── system-optimization-diff.json   # Optimizations ready for execution
│   ├── telemetry-diff.json             # Active telemetry ready for disable
│   └── windows-updates-diff.json       # Available updates ready for install
└── 📁 reports/                 # Temporary Report Data
    └── (consolidated before moving to parent directory)
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
  - `logs/bloatware-removal/execution.log` - BloatwareRemoval execution tracking
  - `logs/essential-apps/execution.log` - EssentialApps execution tracking
  - `logs/system-optimization/execution.log` - SystemOptimization execution tracking
  - `logs/telemetry-disable/execution.log` - TelemetryDisable execution tracking
  - `logs/windows-updates/execution.log` - WindowsUpdates execution tracking
- `temp_files/temp/` - **Processing diffs and intermediate data**
  - `bloatware-diff.json` - Config items found on system (ready for removal)
  - `essential-apps-diff.json` - Missing apps from config (ready for installation)
  - `system-optimization-diff.json` - Optimization opportunities (ready for execution)
  - `telemetry-diff.json` - Active telemetry items (ready for disable)
  - `windows-updates-diff.json` - Available updates (ready for installation)
- `temp_files/reports/` - **Temporary report data** (consolidated before moving to parent)

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
The system generates **one comprehensive HTML report** in the **parent directory** of script location:

**Universal Report Placement**:
- **Script extracted to Documents\script_mentenanta**: Report → Documents\MaintenanceReport_*.html
- **Script extracted to Desktop\script_mentenanta**: Report → Desktop\MaintenanceReport_*.html  
- **Script on USB\script_mentenanta**: Report → USB_Root\MaintenanceReport_*.html
- **Filename format**: `MaintenanceReport_YYYY-MM-DD_HH-mm-ss.html` (single report only)

**ReportGeneration Data Collection (v3.0)**:
```powershell
# Collect Type1 detection results from temp_files/data/
$detectionSources = @{
    'BloatwareResults' = Join-Path $Global:ProjectPaths.TempFiles "data\bloatware-results.json"
    'EssentialAppsResults' = Join-Path $Global:ProjectPaths.TempFiles "data\essential-apps-results.json"
    'SystemOptResults' = Join-Path $Global:ProjectPaths.TempFiles "data\system-optimization-results.json"
    'TelemetryResults' = Join-Path $Global:ProjectPaths.TempFiles "data\telemetry-results.json"
    'UpdatesResults' = Join-Path $Global:ProjectPaths.TempFiles "data\windows-updates-results.json"
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
The system generates **one comprehensive HTML report** in the **parent directory** of script location:

**Universal Report Placement**:
- **Script extracted to Documents\script_mentenanta**: Report → Documents\MaintenanceReport_*.html
- **Script extracted to Desktop\script_mentenanta**: Report → Desktop\MaintenanceReport_*.html  
- **Script on USB\script_mentenanta**: Report → USB_Root\MaintenanceReport_*.html
- **Filename format**: `MaintenanceReport_YYYY-MM-DD_HH-mm-ss.html` (single report only)

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

1. **BloatwareRemoval** (Cleanup before installation)
2. **EssentialApps** (Install missing software)  
3. **SystemOptimization** (Performance tuning)
4. **TelemetryDisable** (Privacy configuration)
5. **WindowsUpdates** (System updates last)

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
- **`modules/core/CoreInfrastructure.psm1`** - Configuration, logging, session management (consolidated)
- **`modules/core/UserInterface.psm1`** - Hierarchical countdown menus with auto-fallback
- **`modules/core/ReportGeneration.psm1`** - External template-based HTML dashboard generation
- **`modules/type2/[ModuleName].psm1`** - Self-contained execution modules (v3.0 pattern)
- **`modules/type1/[ModuleName]Audit.psm1`** - Detection modules (imported by Type2)
- **`config/main-config.json`** - Execution settings, countdown timers, module toggles
- **`config/report-template.html`** - External HTML report template structure
- **`config/report-styles.css`** - Report styling without chart dependencies
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