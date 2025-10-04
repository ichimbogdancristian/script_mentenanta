Purpose
=======
This file provides concise, machine-friendly instructions for automated assistants (Copilot-style) interacting with the repository. It describes the project's entry points, core modules, exported functions, execution sequence, and common invariants.

Top-level intent
-----------------
- Maintain and run a modular Windows maintenance automation system.
- Launcher (`script.bat`) bootstraps environment, ensures dependencies, and invokes the PowerShell orchestrator.
- Orchestrator (`MaintenanceOrchestrator.ps1`) loads core modules and executes module tasks with dependency resolution.

Entry points
-------------
- `script.bat` - primary launcher. Handles UAC elevation, scheduled tasks, dependency bootstrap (winget, PS7), and calls orchestrator.
- `MaintenanceOrchestrator.ps1` - central orchestrator. Parameters: `-LogFilePath`, `-ConfigPath`, `-NonInteractive`, `-DryRun`, `-TaskNumbers`, `-ModuleName`, `-EnableDetailedLogging`, `-ForceAllModules`.

Core modules (modules/core)
---------------------------
- `ConfigManager.psm1`
  - Exports: `Initialize-ConfigSystem`, `Get-MainConfiguration`, `Get-LoggingConfiguration`, `Get-BloatwareConfiguration`, `Get-EssentialAppsConfiguration`, `Get-InventoryFolder`, `Get-StandardInventoryPath`, `Get-ModuleLogPath` (if present)
  - Purpose: Read/validate JSON config files, provide canonical paths, supply defaults.

- `ModuleExecutionProtocol.psm1`
  - Exports: module registration and execution functions (e.g., `Register-Module`, `Invoke-ModuleExecutionEngine`)
  - Purpose: Dependency resolution, execution ordering, capture results and statuses.

- `MenuSystem.psm1`
  - Exports: interactive menu functions
  - Purpose: present user options; supports timed fallback and non-interactive mode.

Key task modules (modules/type1 and modules/type2)
--------------------------------------------------
- `SystemInventory.psm1` (Type1)
  - Exports: `Get-SystemInventory`, `Export-SystemInventory`, `Get-SystemInventoryCacheInfo`, `Clear-SystemInventoryCache`
  - Purpose: Collect hardware/OS/software/network/service information and expose cache/exports.

- `BloatwareDetection.psm1` (Type1)
  - Purpose: Scan installed apps (AppX, registry, winget/choco) against bloatware lists.

- `ReportGeneration.psm1` (Type1)
  - Purpose: Render HTML/text/JSON reports from TaskResults. Prefer the orchestrator to pass `SystemInventory` results into report input to avoid re-collection.

- Type2 modules (BloatwareRemoval, EssentialApps, WindowsUpdates, TelemetryDisable, SystemOptimization)
  - These modify system state. Implement `SupportsShouldProcess` and honor `-DryRun`.

Execution sequence (high-level)
-------------------------------
1. `script.bat` (launcher)
   - Create/append `maintenance.log` in script directory
   - Ensure elevation (relaunch if needed)
   - Manage scheduled tasks (startup/monthly); uses `startup-wrapper.bat` to ensure correct working directory
   - Ensure dependencies (winget, PowerShell 7, NuGet, PSWindowsUpdate). Falls back to PowerShell 5.1 where necessary.
   - Invoke orchestrator with appropriate parameters

2. `MaintenanceOrchestrator.ps1` (orchestrator)
   - Determine working directory and create `temp_files` (logs/reports/inventory)
   - Move launcher `maintenance.log` into orchestrator-managed logs
   - Load core modules (`ConfigManager`, `MenuSystem`, `ModuleExecutionProtocol`)
   - Initialize configuration (`Initialize-ConfigSystem`)
   - Register modules and resolve dependencies
   - Execute selected modules according to dependency order and capture results
   - Optionally pass `SystemInventory` result into `ReportGeneration` to avoid duplicate collection

3. Module execution
   - Type1 modules return structured data objects
   - Type2 modules return standardized result objects or boolean success values and must support `-DryRun`

Important invariants & helpers
------------------------------
- All modules should use the central `Write-Log` or `Write-Log` equivalent exported by core logging utilities.
- `Get-InventoryFolder` returns an absolute, created directory under `temp_files/inventory` unless overridden in config.
- `Get-StandardInventoryPath -ModuleName <name> -Format <JSON|XML|CSV>` returns canonical output paths. Use these for exports.
- Cache management: `Get-SystemInventoryCacheInfo` and `Clear-SystemInventoryCache` allow explicit cache inspections and refreshes.

Testing
-------
- `Test-MaintenanceScript.ps1` provides a smoke-test harness. Use `-TestMode All` to run full validation.
- Prefer `-DryRun` while developing to avoid modifying the host system.

Notes for automated assistants
------------------------------
- When updating code, always run `Test-MaintenanceScript.ps1 -TestMode Basic` then `-TestMode All` to validate changes.
- Respect `SupportsShouldProcess` and `-DryRun` behavior for Type2 modules in tests.
- When editing PowerShell files, preserve exported function names. Update `Export-ModuleMember` lists when adding new public functions.

Contact
-------
Repository owner: `ichimbogdancristian`
*** End Patch