# Windows Maintenance Automation - AI Coding Agent Instructions

## Project Overview

This is a **enterprise-grade PowerShell-based Windows maintenance system** with a modular architecture designed for automated system cleanup, optimization, and monitoring. The codebase follows a strict **Type 1** (inventory/reporting) and **Type 2** (system modification) module classification with session-based file organization.

## Core Architecture Patterns

### **NEW ARCHITECTURE (v3.0)**: Orchestrator → Type2 → Type1 Flow

The system now follows a **simplified, efficient architecture** where:

1. **Orchestrator loads minimal modules**: Only `CoreInfrastructure`, `UserInterface`, `ReportGeneration`
2. **Type2 modules are self-contained**: Each Type2 module internally imports its corresponding Type1 module
3. **Automatic validation**: Type2 modules MUST call Type1 detection before taking any action

**Execution Flow:**
```
MaintenanceOrchestrator.ps1
    ↓ (loads core services)
CoreInfrastructure + UserInterface + ReportGeneration
    ↓ (executes)
Type2 Modules (BloatwareRemoval, EssentialApps, etc.)
    ↓ (internally imports and calls)
Type1 Modules (BloatwareDetectionAudit, EssentialAppsAudit, etc.)
    ↓ (uses)
Config/*.json + Session Data + Logging
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

### Session-Based File Organization
All temporary data uses **organized directories** under `temp_files/`:
- `logs/` - Individual module log files and performance tracking
  - `logs/bloatware-removal/` - BloatwareRemoval Type2 execution logs
  - `logs/bloatware-detection-audit/` - BloatwareDetectionAudit Type1 analysis logs
  - `logs/essential-apps/` - EssentialApps Type2 execution logs
  - `logs/essential-apps-audit/` - EssentialAppsAudit Type1 analysis logs
  - `logs/[module-name]/` - Each module has dedicated log directory
- `data/` - Categorized inventory and audit files (by module/function)
  - `data/bloatware-results.json` - Detection results for ReportGeneration
  - `data/system-optimization-results.json` - Optimization analysis results
  - `data/[module-name]-results.json` - Module-specific audit data
- `temp/` - Other generated files and processing data
- `reports/` - Final outputs (HTML, JSON, TXT)

**Key Pattern**: Always use `Get-SessionPath` with module-specific paths that work from any launch directory:
```powershell
# Type1 modules: Generate audit logs in dedicated directories
$auditLogPath = Get-SessionPath -Category 'logs' -SubCategory 'bloatware-detection-audit' -FileName 'detection-analysis.log'
$auditDataPath = Get-SessionPath -Category 'data' -FileName 'bloatware-results.json'

# Type2 modules: Generate execution logs in dedicated directories  
$executionLogPath = Get-SessionPath -Category 'logs' -SubCategory 'bloatware-removal' -FileName 'removal-execution.log'

# ReportGeneration: Knows exactly where to find all module data
$reportDataSources = @{
    'BloatwareResults' = Get-SessionPath -Category 'data' -FileName 'bloatware-results.json'
    'BloatwareLogs' = Get-SessionPath -Category 'logs' -SubCategory 'bloatware-removal' -FileName 'removal-execution.log'
}
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
   #Requires -Version 7.0
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

## Key Files to Reference

- **`MaintenanceOrchestrator.ps1`** - Central coordination, parameter handling, session management
- **`modules/core/CoreInfrastructure.psm1`** - Configuration, logging, and file organization (consolidated)
- **`modules/core/SystemAnalysis.psm1`** - System inventory and security audit (consolidated)
- **`modules/core/UserInterface.psm1`** - Interactive menus and user input (consolidated)
- **`modules/core/DependencyManager.psm1`** - External package management
- **`modules/core/ReportGeneration.psm1`** - Dashboard and report generation
- **`config/main-config.json`** - Default settings, module toggles, execution modes
- **`script.bat`** - Bootstrap sequence, environment setup, scheduled task management

## Development Conventions

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