# Windows Maintenance Automation - AI Coding Agent Instructions

## Project Overview

This is a **enterprise-grade PowerShell-based Windows maintenance system** with a modular architecture designed for automated system cleanup, optimization, and monitoring. The codebase follows a strict **Type 1** (inventory/reporting) and **Type 2** (system modification) module classification with session-based file organization.

## Core Architecture Patterns

### Type 1/Type 2 Module Pairing (Critical)
**Every Type 2 module MUST have a corresponding Type 1 module** for safe operation:
- Type 1: Detection/auditing modules in `modules/type1/` (paired with Type 2)
- Type 2: Action/modification modules in `modules/type2/` (system-changing)
- Core: Infrastructure modules in `modules/core/` (shared services)

**Current pairings:**
- ✅ `BloatwareDetection` ↔ `BloatwareRemoval`
- ✅ `EssentialAppsAudit` ↔ `EssentialApps`
- ✅ `SystemOptimizationAudit` ↔ `SystemOptimization`
- ✅ `TelemetryAudit` ↔ `TelemetryDisable`
- ✅ `WindowsUpdatesAudit` ↔ `WindowsUpdates`

**Core infrastructure modules:**
- `SystemInventory`, `SecurityAudit`, `ReportGeneration` (shared services)

### Module Loading Order (Critical)
Always maintain this exact loading sequence in `MaintenanceOrchestrator.ps1`:
1. **Core modules**: `ConfigManager` → `LoggingManager` → `FileOrganizationManager` → `MenuSystem` → `SystemInventory` → `SecurityAudit` → `ReportGeneration`
2. **Type 1 modules**: Detection/audit modules (safe operations, paired with Type 2)
3. **Type 2 modules**: Action/modification modules (system-changing operations)

```powershell
# Example: Core module loading pattern with error handling
foreach ($moduleName in $CoreModules) {
    $modulePath = Join-Path $CoreModulesPath "$moduleName.psm1"
    Import-Module $modulePath -Force -Global -ErrorAction Stop
    # Always verify successful loading
    if (-not (Get-Module -Name $moduleName)) {
        throw "Module $moduleName failed to load properly"
    }
}
```

### Session-Based File Organization
All temporary data uses **organized directories** under `temp_files/`:
- `logs/` - Individual module log files and performance tracking
- `data/` - Categorized inventory and audit files (by module/function)
- `temp/` - Other generated files and processing data
- `reports/` - Final outputs (HTML, JSON, TXT)

**Key Pattern**: Always use `FileOrganizationManager` functions instead of direct file operations:
```powershell
# Correct: Use centralized file operations
$logPath = Get-SessionPath -Category 'logs' -FileName 'module-specific.log'
$dataPath = Get-SessionPath -Category 'data' -FileName 'audit-results.json'
$reportPath = Get-SessionPath -Category 'reports' -FileName 'system-report.html'
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

### Adding New Modules
1. **Create paired modules**: Always create both Type 1 (detection/audit) and Type 2 (action/modification)
2. **Naming convention**: `[Feature]Detection.psm1` (Type 1) + `[Feature]Removal.psm1` (Type 2)
   - Example: `TelemetryAudit.psm1` + `TelemetryDisable.psm1`
3. **Type 1 module first**: Must detect/validate before Type 2 can act
4. **Include required headers**:
   ```powershell
   # Requires -Version 7.0
   # Module Dependencies: ConfigManager.psm1, LoggingManager.psm1
   ```
5. **Use dependency imports** at module start:
   ```powershell
   $ModuleRoot = Split-Path -Parent $PSScriptRoot
   Import-Module (Join-Path $ModuleRoot 'core\LoggingManager.psm1') -Force
   ```
6. **Type 2 dependencies**: Always import corresponding Type 1 module:
   ```powershell
   Import-Module (Join-Path $ModuleRoot 'type1\BloatwareDetection.psm1') -Force
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
- **`modules/core/ConfigManager.psm1`** - Configuration patterns, JSON validation, path resolution  
- **`modules/core/LoggingManager.psm1`** - Structured logging, performance tracking, session context
- **`modules/core/FileOrganizationManager.psm1`** - Session-based file operations, cleanup policies
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