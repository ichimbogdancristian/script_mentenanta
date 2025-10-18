# Windows Maintenance Automation - AI Coding Agent Instructions

## Project Overview

This is a **enterprise-grade PowerShell-based Windows maintenance system** with a hierarchical interactive menu system and consolidated modular architecture. The system features **20-second countdown menus**, **self-contained Type2 modules**, and **session-based file organization** for automated Windows 10/11 maintenance.

## Core Architecture Patterns (v3.0)

### **🎯 Hierarchical Menu System**
The system features a **two-level countdown menu** with intelligent defaults:

1. **Main Menu** (20s countdown): Execute normally vs Dry-run mode
2. **Sub Menu** (20s countdown): All tasks vs Specific task numbers  
3. **Auto-fallback**: When no user input, automatically selects recommended defaults
4. **Task Selection**: Comma-separated input (e.g., "1,3,5") for specific tasks

### **🏗️ Simplified Architecture**: Orchestrator → Type2 → Type1 Flow

The system follows a **streamlined, efficient architecture**:

1. **Orchestrator loads minimal modules**: Only `CoreInfrastructure`, `UserInterface`, `ReportGeneration`
2. **Type2 modules are self-contained**: Each Type2 module internally imports its corresponding Type1 module
3. **Automatic validation**: Type2 modules MUST call Type1 detection before taking any action
4. **50% faster startup**: Lazy loading with on-demand Type1 imports

**Execution Flow:**
```
script.bat (Bootstrap + Admin Elevation)
    ↓
MaintenanceOrchestrator.ps1
    ↓ (loads core services)
CoreInfrastructure + UserInterface + ReportGeneration
    ↓ (interactive menu system)
Hierarchical Menu: Main Menu (20s) → Sub Menu (20s) → Task Selection
    ↓ (executes selected modules)
Type2 Modules (BloatwareRemoval, EssentialApps, etc.)
    ↓ (internally imports and calls)
Type1 Modules (BloatwareDetectionAudit, EssentialAppsAudit, etc.)
    ↓ (uses)
Config/*.json + Session Data + Logging
    ↓ (generates)
Interactive HTML Dashboard + JSON Reports
```

### Type 1/Type 2 Module Pairing (Self-Contained)
**Every Type 2 module internally manages its Type 1 dependency**:
- Type 1: Detection/auditing modules in `modules/type1/` (imported by Type 2)
- Type 2: Action/modification modules in `modules/type2/` (self-contained units)
- Core: Infrastructure modules in `modules/core/` (minimal set loaded by orchestrator)

**Current pairings (internally managed):**
- ✅ `BloatwareRemoval` → `BloatwareDetectionAudit` (internal)
- ✅ `EssentialApps` → `EssentialAppsAudit` (internal)
- ✅ `SystemOptimization` → `SystemOptimizationAudit` (internal)
- ✅ `TelemetryDisable` → `TelemetryAudit` (internal)
- ✅ `WindowsUpdates` → `WindowsUpdatesAudit` (internal)

**Core infrastructure modules (orchestrator-loaded):**
- `CoreInfrastructure` - Configuration, logging, and file organization
- `UserInterface` - Interactive menus and user input (preserved)
- `ReportGeneration` - Dashboard and report generation (preserved)

### Simplified Module Loading Order (v3.0)
**Orchestrator loads only essential modules:**
```powershell
# NEW: Minimal orchestrator loading
$CoreModules = @('CoreInfrastructure', 'UserInterface', 'ReportGeneration')
$Type2Modules = @('BloatwareRemoval', 'EssentialApps', 'SystemOptimization', 'TelemetryDisable', 'WindowsUpdates')

# Load core services
foreach ($moduleName in $CoreModules) {
    Import-Module (Join-Path $CoreModulesPath "$moduleName.psm1") -Force -Global
}

# Execute Type2 modules (they handle their own Type1 dependencies)
foreach ($moduleName in $Type2Modules) {
    $result = & "Invoke-$moduleName" -Config $MainConfig -DryRun:$DryRun
}
```

### **🌐 Global Path Discovery System (v3.0 Critical)**
The system implements **robust portable path discovery** for universal deployment:

**Project Root Detection**:
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
}

# Collect Type2 execution logs from temp_files/logs/
$executionSources = @{
    'BloatwareExecution' = Join-Path $Global:ProjectPaths.TempFiles "logs\bloatware-removal\execution.log"
    'EssentialAppsExecution' = Join-Path $Global:ProjectPaths.TempFiles "logs\essential-apps\execution.log"
    'SystemOptExecution' = Join-Path $Global:ProjectPaths.TempFiles "logs\system-optimization\execution.log"
    'TelemetryExecution' = Join-Path $Global:ProjectPaths.TempFiles "logs\telemetry-disable\execution.log"
    'UpdatesExecution' = Join-Path $Global:ProjectPaths.TempFiles "logs\windows-updates\execution.log"
}

# Collect processing diffs from temp_files/temp/
$processingDiffs = @{
    'BloatwareDiff' = Join-Path $Global:ProjectPaths.TempFiles "temp\bloatware-diff.json"
    'EssentialAppsDiff' = Join-Path $Global:ProjectPaths.TempFiles "temp\essential-apps-diff.json"
    'SystemOptDiff' = Join-Path $Global:ProjectPaths.TempFiles "temp\system-optimization-diff.json"
    'TelemetryDiff' = Join-Path $Global:ProjectPaths.TempFiles "temp\telemetry-diff.json"
    'UpdatesDiff' = Join-Path $Global:ProjectPaths.TempFiles "temp\windows-updates-diff.json"
}

# Generate single comprehensive report in parent directory
$reportPath = Join-Path $Global:ProjectPaths.ParentDir "MaintenanceReport_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').html"
New-MaintenanceReport -DetectionData $detectionSources -ExecutionLogs $executionSources -ProcessingDiffs $processingDiffs -OutputPath $reportPath
```

# Generate report in parent directory (portable logic)
$reportDestination = Split-Path -Parent $PSScriptRoot
$reportPath = Join-Path $reportDestination "MaintenanceReport_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').html"
```

### Configuration Management
JSON configs in `config/` follow strict validation patterns:
- `main-config.json` - Execution modes, module toggles, paths
- `logging-config.json` - Log levels, destinations, performance tracking  
- `bloatware-list.json` & `essential-apps.json` - Application definitions

**Always validate JSON syntax** before processing and use `ConfigManager` functions:
```powershell
Initialize-ConfigSystem -ConfigRootPath $ConfigPath
$config = Get-MainConfig
$bloatwareList = Get-BloatwareList -Category 'OEM'
```

## Critical Developer Workflows

### Adding New Modules (v3.0 Self-Contained Pattern)
1. **Create paired modules**: Always create both Type 1 (detection/audit) and Type 2 (action/modification)
2. **Naming convention**: `[Feature]Audit.psm1` (Type 1) + `[Feature]Management.psm1` (Type 2)
   - Example: `TelemetryAudit.psm1` + `TelemetryDisable.psm1`
3. **Type 2 self-contained**: Type 2 module must internally import and use its Type 1 module
4. **Required Type 2 structure**:
   ```powershell
   # Requires -Version 7.0
   # Self-contained Type 2 module with internal Type 1 dependency

   # Import corresponding Type 1 module (required)
   $Type1ModulePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'type1\[Feature]Audit.psm1'
   Import-Module $Type1ModulePath -Force
   
   # Import core infrastructure
   $CoreInfraPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'core\CoreInfrastructure.psm1'
   Import-Module $CoreInfraPath -Force

   # Main execution function (required pattern)
   function Invoke-[FeatureName] {
       param($Config, [switch]$DryRun)
       
       # Step 1: Always detect first (Type 1)
       $detectionResults = Get-[Feature]Analysis -Config $Config
       
       # Step 2: Validate and log
       Write-LogEntry -Level 'INFO' -Message "Detected $($detectionResults.Count) items"
       
       # Step 3: Take action (Type 2)
       if (-not $DryRun) {
           Invoke-[Feature]Action -Items $detectionResults
       }
       
       return $detectionResults
   }
   ```

### Launcher Bootstrap Sequence
The `script.bat` launcher performs **critical pre-orchestrator setup**:
1. **Admin elevation check** with UAC auto-elevation
2. **Pending restart handling** with auto-resume via scheduled task
3. **System Protection + Restore Point** creation and verification
4. **Dependency bootstrapping**: PowerShell 7, winget, Chocolatey, PowerShellGet
5. **Monthly automation task** setup (SYSTEM account, highest priority)

**Never bypass the launcher** - it handles environment setup that PowerShell alone cannot.

### Testing Workflow 
**Mandatory TestFolder pattern** for validation:
```bat
# Always test with TestFolder first
script.bat -DryRun -TaskNumbers 1,2,3
# Then run on real system
script.bat -NonInteractive
```

## Module Integration Patterns

### Cross-Module Communication
Modules communicate via **structured session data** and **centralized logging**:
```powershell
# Store data for other modules
$inventoryData = Get-SystemInventory
Save-SessionData -Category 'inventory' -Data $inventoryData -FileName 'system-inventory.json'

# Retrieve data from other modules  
$bloatwareResults = Get-SessionData -Category 'data' -FileName 'detected-bloatware.json'
```

### Performance Tracking
Use `LoggingManager` performance tracking for all operations:
```powershell
$perfContext = Start-PerformanceTracking -OperationName 'BloatwareRemoval' -Component 'BLOATWARE-REMOVAL'
try {
    # ... operation code ...
    Complete-PerformanceTracking -Context $perfContext -Status 'Success'
} catch {
    Complete-PerformanceTracking -Context $perfContext -Status 'Failed' -ErrorMessage $_.Exception.Message
}
```

### Error Handling Pattern
Always use **graceful degradation** with logging fallbacks:
```powershell
try {
    Write-LogEntry -Level 'INFO' -Component 'MODULE-NAME' -Message 'Operation starting'
} catch {
    # LoggingManager not available, continue with standard output
    Write-Information "Operation starting" -InformationAction Continue
}
```

## 🎯 **Critical Execution Patterns**

### **Hierarchical Menu System** - UserInterface.psm1
The system uses a **two-level countdown menu** that always provides defaults:

**Level 1 - Main Menu** (20-second countdown):
- `[1] Execute normally` (DEFAULT - auto-selected if no input)
- `[2] Dry-run mode`

**Level 2 - Sub Menu** (20-second countdown for each main option):
- `[1] Execute all tasks` (DEFAULT - auto-selected if no input)  
- `[2] Execute specific task numbers` (prompts for comma-separated input)

**Auto-Fallback Logic:**
- No user interaction → Automatically selects Option 1 → Sub-option 1
- Result: Normal execution of all maintenance tasks
- User can interrupt countdown by pressing number keys

### **Type2 Module Self-Contained Pattern (v3.0 Corrected)**
Every Type2 module MUST follow this exact pattern for v3.0 compatibility:

```powershell
# Self-contained Type 2 module with internal Type 1 dependency

# 1. Import corresponding Type 1 module (MANDATORY)
$Type1ModulePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'type1\[ModuleName]Audit.psm1'
Import-Module $Type1ModulePath -Force

# 2. Import core infrastructure with global paths (MANDATORY)  
$CoreInfraPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'core\CoreInfrastructure.psm1'
Import-Module $CoreInfraPath -Force

# 3. Main execution function (MANDATORY naming: Invoke-[ModuleName])
function Invoke-[ModuleName] {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config,
        
        [Parameter()]
        [switch]$DryRun
    )
    
    # STEP 1: Always run Type1 detection first and save to temp_files/data/
    $detectionResults = Get-[ModuleName]Analysis -Config $Config
    $detectionDataPath = Join-Path $Global:ProjectPaths.TempFiles "data\[module-name]-results.json"
    $detectionResults | ConvertTo-Json -Depth 10 | Set-Content $detectionDataPath
    
    # STEP 2: Compare detection with config to create diff list
    $configDataPath = Join-Path $Global:ProjectPaths.Config "[config-file].json"
    $configData = Get-Content $configDataPath | ConvertFrom-Json
    $diffList = Compare-DetectedVsConfig -Detected $detectionResults -Config $configData
    $diffPath = Join-Path $Global:ProjectPaths.TempFiles "temp\[module-name]-diff.json"
    $diffList | ConvertTo-Json | Set-Content $diffPath
    
    # STEP 3: Process ONLY items in diff list and log to dedicated directory
    $executionLogDir = Join-Path $Global:ProjectPaths.TempFiles "logs\[module-name]"
    New-Item -Path $executionLogDir -ItemType Directory -Force
    $executionLogPath = Join-Path $executionLogDir "execution.log"
    
    Write-LogEntry -Level 'INFO' -Component '[MODULE-NAME]' -Message "Processing $($diffList.Count) items from diff" -LogPath $executionLogPath
    
    if (-not $DryRun) {
        foreach ($item in $diffList) {
            # Process only items found in diff comparison
            Invoke-[ModuleName]Action -Item $item -Config $Config -LogPath $executionLogPath
        }
    } else {
        Write-LogEntry -Level 'INFO' -Component '[MODULE-NAME]' -Message "DRY-RUN: Would process $($diffList.Count) items" -LogPath $executionLogPath
    }
    
    return @{
        'Success' = $true
        'ItemsDetected' = $detectionResults.Count
        'ItemsProcessed' = $diffList.Count
        'DiffPath' = $diffPath
        'ExecutionLogPath' = $executionLogPath
    }
}
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