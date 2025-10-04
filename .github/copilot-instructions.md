# Windows Maintenance Automation - AI Coding Instructions

## Project Overview

This is a **modular Windows maintenance automation system** built on PowerShell 7+ with a sophisticated three-tier architecture. The system orchestrates system maintenance, bloatware removal, essential app installation, and comprehensive reporting through a unified execution protocol.

## Architecture & Key Concepts

### Module Classification System
- **Core Modules** (`modules/core/`): Infrastructure services (ConfigManager, MenuSystem, ModuleExecutionProtocol, etc.)
- **Type1 Modules** (`modules/type1/`): Read-only inventory/reporting (SystemInventory, BloatwareDetection, SecurityAudit, ReportGeneration)
- **Type2 Modules** (`modules/type2/`): System modification (BloatwareRemoval, EssentialApps, WindowsUpdates, SystemOptimization, TelemetryDisable)

### Execution Flow
Entry point: `script.bat` → `MaintenanceOrchestrator.ps1` → Module Loading → Dependency Resolution → Task Execution → Report Generation

### Critical Design Patterns

1. **Universal Path Discovery**: All scripts use `Get-ScriptEnvironment` function to work from any location. Never assume working directory.

2. **Module Manifest System**: Each module is registered in `MaintenanceOrchestrator.ps1` with metadata:
   ```powershell
   @{
       Name = 'ModuleName'; Type = 'Type1/Type2/Core'; EntryFunction = 'Get-/Invoke-Function'
       Dependencies = @('ConfigManager', 'OtherModule'); RequiresElevation = $true/$false
   }
   ```

3. **Privilege Elevation Pattern**: Type2 modules must include `Assert-AdministratorPrivileges` checks and implement `[CmdletBinding(SupportsShouldProcess)]` for dry-run support.

## Development Workflows

### Adding New Modules
1. Create `.psm1` file in appropriate `modules/type1/`, `modules/type2/`, or `modules/core/`
2. Follow naming convention: `Get-*` for Type1, `Invoke-*` for Type2, `*-*` for Core
3. Add entry to `$ModuleManifests` array in `MaintenanceOrchestrator.ps1`
4. Export single main function: `Export-ModuleMember -Function 'Your-Function'`

### Configuration Management
- All config in JSON format under `config/` directory
- Use `ConfigManager.psm1` functions: `Get-MainConfiguration`, `Get-BloatwareConfiguration`, `Get-EssentialAppsConfiguration`
- Configuration is auto-discovered relative to script location, never hardcoded paths

### Testing & Debugging
```powershell
# Test individual modules
.\MaintenanceOrchestrator.ps1 -ModuleName "SystemInventory" -EnableDetailedLogging

# Safe testing with dry-run
.\MaintenanceOrchestrator.ps1 -DryRun -NonInteractive

# Specific task execution
.\MaintenanceOrchestrator.ps1 -TaskNumbers "1,3,5"
```

## Project-Specific Conventions

### Error Handling
- Use `Write-Error` for actionable errors, `Write-Warning` for degraded functionality
- Type2 modules must gracefully handle privilege failures with descriptive messages
- All functions should include try-catch with module context

### Logging Integration
```powershell
# Standard logging pattern used throughout
Write-Host "🔍 Starting operation..." -ForegroundColor Cyan
Write-Host "  📊 Processing item..." -ForegroundColor Gray  
Write-Host "✅ Operation completed" -ForegroundColor Green
```

### Data Structure Patterns
- Type1 modules return structured hashtables/PSCustomObjects
- Type2 modules return boolean success/failure or standardized result objects
- Always include metadata in returned objects: `@{ Metadata = @{ ModuleName = '...'; Timestamp = Get-Date } }`

## Integration Points

### Module Dependencies
- Dependencies resolved automatically by `ModuleExecutionProtocol.psm1`
- Configuration dependencies handled through `ConfigurationDependencies` property
- Cross-module data sharing through execution context's `SharedData` hashtable

### External Dependencies
- PowerShell 7+ automatically installed by `script.bat`
- Package managers (Chocolatey, Winget) handled by `DependencyManager.psm1`
- Administrator privileges required for Type2 modules only

### Report Generation
- HTML reports use embedded CSS/JS in `ReportGeneration.psm1`
- All modules contribute data to centralized reporting system
- Report data structure: `@{ SystemInfo = @{}; ExecutionResults = @{}; TaskResults = @{} }`

## Critical Implementation Notes

### Self-Discovery Pattern
Always use relative paths from script location:
```powershell
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$configPath = Join-Path $scriptRoot "config"
```

### Dry-Run Implementation
Type2 modules must support `$PSCmdlet.ShouldProcess()` pattern:
```powershell
if ($PSCmdlet.ShouldProcess($target, $action)) {
    # Actual modification code
}
```

### JSON Configuration Schema
- `main-config.json`: Execution behavior, module toggles, system settings
- `bloatware.json`: Categorized software removal lists 
- `essential-apps.json`: Curated installation applications
- All configs have fallback defaults in respective manager modules

### Module Execution Context
Each module receives standardized execution context with:
- `SharedData`: Cross-module communication
- `Configuration`: Merged configuration settings
- `DryRun`: Boolean flag for simulation mode
- `CancellationToken`: Timeout and cancellation support

When modifying core execution logic, always maintain backward compatibility with existing module interface patterns.