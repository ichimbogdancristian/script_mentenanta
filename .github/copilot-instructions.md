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

Launcher Modes and Path Discovery
- `script.bat` discovers its own directory using `%~dp0` and derives:
    - `WORKING_DIR` (script folder), `ORCHESTRATOR_PATH`, `CONFIG_DIR`, `MODULES_DIR`, `LOG_FILE`
- Pre-launch checks are non-fatal (to support pre-extraction deployments). The orchestrator is launched if present; otherwise the launcher logs and exits cleanly.
- Final validation occurs via `POST_EXTRACT` (or `POST_DEPLOY`) invoked by the extraction process:
    - `script.bat POST_EXTRACT [RepoRoot]`
    - Ensures elevation, validates `MaintenanceOrchestrator.ps1`, `config`, `modules` under RepoRoot (or `WORKING_DIR` if omitted), then launches orchestrator.

Environment Variables (Path Override System)
- `MAINTENANCE_ROOT`: override base repo directory for orchestrator
- `MAINTENANCE_CONFIG`: override config directory path
- `MAINTENANCE_MODULES`: override modules directory path
- `MAINTENANCE_LOGS`: override logs directory path
- `MAINTENANCE_INVENTORY`: override inventory directory path
- `MAINTENANCE_TEMP`: override temp files directory path
- `MAINTENANCE_REPORTS`: override reports directory path

Notes
- Use standardized `Get-ModuleEnvironment` function from ConfigManager.psm1 for all path discovery
- Avoid hard-coded absolute paths. Always use relative path discovery from module location
- Keep destructive operations gated by repo presence or use orchestrator-driven validation

### Critical Design Patterns

1. **Standardized Path Discovery**: All modules use `Get-ModuleEnvironment` function from ConfigManager.psm1. Never assume working directory or hardcode paths.

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
- Use `Get-ModuleEnvironment` for standardized path discovery with fallback strategies
- Configuration paths auto-discovered using universal path discovery system

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

### Standardized Path Discovery Pattern
Always use the universal path discovery system:
```powershell
# Import ConfigManager and use standardized discovery
Import-Module (Join-Path $PSScriptRoot '..\core\ConfigManager.psm1') -Force
$env = Get-ModuleEnvironment -ModuleType 'Type1'  # Core/Type1/Type2

# Use discovered paths
$configPath = $env.ConfigPath
$logsPath = $env.LogsPath
$inventoryPath = $env.InventoryPath
$repositoryRoot = $env.RepositoryRoot

# Environment variables automatically override paths
# SET MAINTENANCE_LOGS=C:\CustomLogs applies automatically
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

## Standardized Path Discovery System

### Universal Path Discovery
All modules now use the standardized `Get-ModuleEnvironment` function for consistent path discovery:

```powershell
# Standard pattern for all modules
Import-Module (Join-Path $PSScriptRoot '..\core\ConfigManager.psm1') -Force
$moduleEnv = Get-ModuleEnvironment -ModuleType 'Type1'  # Core/Type1/Type2

# Access standardized paths
$repositoryRoot = $moduleEnv.RepositoryRoot
$configPath = $moduleEnv.ConfigPath
$modulesPath = $moduleEnv.ModulesPath
$logsPath = $moduleEnv.LogsPath
$inventoryPath = $moduleEnv.InventoryPath
$tempPath = $moduleEnv.TempPath
$isValidStructure = $moduleEnv.IsValidStructure
```

### Environment Variable Overrides
Users can override any path using environment variables:
- `MAINTENANCE_ROOT` - Base repository directory
- `MAINTENANCE_CONFIG` - Config directory path
- `MAINTENANCE_MODULES` - Modules directory path
- `MAINTENANCE_LOGS` - Logs directory path
- `MAINTENANCE_INVENTORY` - Inventory directory path
- `MAINTENANCE_TEMP` - Temp files directory path
- `MAINTENANCE_REPORTS` - Reports directory path

### Enhanced Fallback Strategies
The system includes robust fallback mechanisms for:
- Network paths (`\\server\share`)
- Missing directories (auto-creation)
- Permission issues (fallback to accessible locations)
- Repository structure validation (recursive search)
- Cross-platform path handling

### Module Implementation Requirements
1. **Import Pattern**: Always import ConfigManager from relative path
2. **Path Discovery**: Use `Get-ModuleEnvironment` instead of hardcoded paths
3. **Fallback Handling**: Wrap path discovery in try-catch with graceful degradation
4. **Module Type**: Specify correct module type (Core/Type1/Type2) for proper path calculation

### Testing and Validation
Use TestFolder for isolated testing to observe file behaviors:
- Copy `script.bat` to TestFolder for clean environment testing
- Use `FileObserver.ps1` to monitor file creation/deletion during execution
- Validate path discovery across different scenarios
- Test environment variable overrides
- Generate comprehensive reports of file system changes
- Ensure reproducible testing conditions with clean state each run

### TestFolder Environment Setup
1. Clean TestFolder: Remove all existing files
2. Copy fresh `script.bat` from main repository
3. Run `FileObserver.ps1` to start monitoring
4. Execute `script.bat` in separate terminal
5. Review file behavior analysis and logs