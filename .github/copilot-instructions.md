<!-- .github/copilot-instructions.md
Generated guidance for AI coding agents working on the script_mentenanta repo.
Keep this short, concrete, and tied to existing files and patterns.
-->

# Quick orientation

- This repository is a modular Windows maintenance automation toolkit. Primary artifacts:
  - `MaintenanceLauncher.ps1` — unified PowerShell launcher coordinating all modules and environment setup.
  - `modules/` — directory containing all specialized modules organized by function.
  - `config.psd1` — user-customizable configuration file with skip flags, thresholds, and scheduled task settings.
  - `logging.json` — runtime logging configuration consumed by the logging module.
  - `sysmonconfig.xml` — Sysmon rules used by monitoring/telemetry integrations.

# Big-picture architecture (what to know)

- Modular design: `MaintenanceLauncher.ps1` is the unified entry point that imports and coordinates specialized modules.
- Core modules handle environment setup, logging, inventory, and task coordination.
- Specialized task modules handle specific maintenance categories (system, applications, updates, monitoring, scheduled tasks).
- Configuration-driven: All behavior controlled by `config.psd1` with skip flags, thresholds, and feature toggles.
- Logging: Centralized logging system writes to `maintenance.log` by default, configurable via `logging.json`.

# Developer workflows & useful commands

- Run locally (interactive, admin): open an elevated PowerShell (pwsh) and run `.\MaintenanceLauncher.ps1` from repository folder.
- Test specific modules: Import individual modules and call their functions directly (e.g., `Import-Module .\modules\tasks\system\SystemTasks.psm1; Get-SystemHealth`).
- Debug configuration: Modify `config.psd1` to enable/disable features or change thresholds.

# Project-specific conventions

- Configuration surface: modify `config.psd1` rather than editing individual module functions. Boolean flags named `SkipSomething` default to `$false`.
- Task definitions: tasks live in the Coordinator module's `$global:ScriptTasks` array as hash tables with keys `Name`, `Function`, `Description`.
- Logging: prefer `Write-Log "message" 'LEVEL'` for consistent timestamped entries used throughout modules.
- Module structure: Each module is a `.psm1` file with exported functions, placed in appropriate subdirectories under `modules/`.

# Integration points & external dependencies

- Requires Administrator privileges and PowerShell 7+ (bootstrap module handles installation if missing).
- Many features rely on `winget`, `choco`, `DISM`, and `PSWindowsUpdate` when available (dependencies module handles installation).
- `sysmonconfig.xml` is provided for security monitoring; changes here will affect downstream SIEM (Wazuh) ingest rules.
- Scheduled task management uses native Windows Task Scheduler (`schtasks.exe`) with fallback handling.

# Common edit patterns and examples

- Add a new maintenance task:
  1. Implement the helper function in the appropriate task module (e.g., `function Do-MyTask { ... }` in `modules/tasks/system/SystemTasks.psm1`).
  2. Add the task to the Coordinator module's `$global:ScriptTasks` array with `Name = 'MyTask'`, `Function = { Do-MyTask }`, and a short `Description`.
  3. Honor config flags by checking `$global:Config.Skip*` inside the wrapper function.
  4. Export the function in the module manifest.

- Add a new module:
  1. Create a new `.psm1` file in the appropriate subdirectory under `modules/`.
  2. Implement functions following established patterns with proper error handling.
  3. Update `MaintenanceLauncher.ps1` to import the new module.
  4. Add configuration options to `config.psd1` if needed.

- Change default logging location: update the logging module or modify `config.psd1` settings.

# Edge cases & pitfalls for automation

- PowerShell 7 installation can fail in restricted environments; bootstrap module handles this gracefully.
- Scheduled task creation may be blocked by group policy — scheduled tasks module includes fallback to user-level tasks.
- Many operations mutate system state (Defender exclusions, registry, uninstalling packages). Keep changes minimal and document intent in commit messages.
- Module loading order matters — core modules must load before specialized task modules.

# Where to look for examples

- Task coordination & config: `modules/core/Coordinator.psm1` (ScriptTasks array and module imports).
- Environment & elevation logic: `modules/environment/Environment.psm1` and `modules/bootstrap/Bootstrap.psm1`.
- Logging contract: `modules/logging/Logging.psm1` + `logging.json` for formats.
- Scheduled task patterns: `modules/tasks/ScheduledTasks.psm1` for Windows Task Scheduler integration.

# When unsure, ask the repo owner

- If an action touches Defender, scheduled tasks, or Sysmon, request explicit confirmation from the repo owner before changing defaults.
- When adding new external dependencies or system modifications, verify compatibility across Windows versions.

---
If you'd like, I can shorten this to exactly 20 lines or expand with copyable code snippets for common edits. Any unclear areas I should expand? 
