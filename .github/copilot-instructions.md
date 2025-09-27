<!-- .github/copilot-instructions.md
Generated guidance for AI coding agents working on the script_mentenanta repo.
Keep this short, concrete, and tied to existing files and patterns.
-->

# Quick orientation

- This repository is a Windows maintenance automation toolkit. Primary artifacts:
  - `script.bat` — launcher and environment preparer (elevation, scheduled tasks, defender exclusions, repo updates).
  - `script.ps1` — PowerShell orchestrator (task definitions, configuration, modular task functions like `Remove-Bloatware`, `Install-EssentialApps`, `Get-SystemInventory`).
  - `logging.json` — runtime logging configuration consumed by the launcher.
  - `sysmonconfig.xml` — Sysmon rules used by monitoring/telemetry integrations.

# Big-picture architecture (what to know)

- Two-tier design: `script.bat` is a resilient, permission-aware launcher. It ensures environment, installs prerequisites, schedules tasks, then invokes `script.ps1`.
- `script.ps1` is the orchestrator. It exposes a global `$global:Config` hash and a `$global:ScriptTasks` array of task metadata. Task execution is configuration-driven (Skip* flags, `ExcludeTasks`, and custom lists).
- Logging: both launcher and orchestrator write to a `maintenance.log` in the working directory by default. `logging.json` contains log-level defaults and formatting.

# Developer workflows & useful commands

- Run locally (interactive, admin): open an elevated PowerShell (pwsh) and run `.\\script.ps1` from repository folder.
- Use the batch launcher to get full prechecks and scheduled-task behavior: run `.\script.bat` from an elevated Command Prompt or PowerShell.
- To test only specific tasks inside `script.ps1`, set `$global:Config.Skip* = $true` for unrelated tasks or call individual functions (e.g., `Remove-Bloatware`) interactively.

# Project-specific conventions

- Configuration surface: modify `$global:Config` at top of `script.ps1` rather than editing individual task functions. Boolean flags named `SkipSomething` default to `$false`.
- Task definitions: tasks live in `$global:ScriptTasks` as hash tables with keys `Name`, `Function`, `Description`. Use these names when adding/removing `ExcludeTasks` entries.
- Logging: prefer `Write-Log "message" 'LEVEL'` for consistent timestamped entries used throughout the scripts.

# Integration points & external dependencies

- Requires Administrator privileges and PowerShell 7+ (launcher checks and attempts elevation). Many features rely on `winget`, `choco`, `DISM`, and `PSWindowsUpdate` when available.
- `sysmonconfig.xml` is provided for security monitoring; changes here will affect downstream SIEM (Wazuh) ingest rules.
- The launcher can create scheduled tasks (`schtasks`) and Windows Defender exclusions (`Add-MpPreference`). These are potential failure points when running under enterprise policies.

# Common edit patterns and examples

- Add a new maintenance task:
  1. Implement the helper function (e.g., `function Do-MyTask { ... }`) near other task functions in `script.ps1`.
  2. Append a hash to `$global:ScriptTasks` with `Name = 'MyTask'`, `Function = { Do-MyTask }`, and a short `Description`.
  3. Honor config flags by checking `$global:Config.Skip*` inside the wrapper function.

- Change default logging location: update `$LogFile` selection near the top of `script.ps1` (it prefers a parameter, then env var `SCRIPT_LOG_FILE`, then parent directory `maintenance.log`).

# Edge cases & pitfalls for automation

- Launcher elevation can fail in restricted environments; prefer testing edits inside an elevated PowerShell session first.
- Scheduled task creation may be blocked by group policy — the launcher already falls back from SYSTEM to user tasks; follow that pattern if adding other task creation logic.
- Many operations mutate system state (Defender exclusions, registry, uninstalling packages). Keep changes minimal and document intent in commit messages.

# Where to look for examples

- Task coordination & config: top of `script.ps1` (global `$global:Config` and `$global:ScriptTasks`).
- Environment & elevation logic: `script.bat` sections near `ADMIN CHECK NOTES` and `POWERSHELL VERSION NOTES`.
- Logging contract: `Write-Log` shim in `script.ps1` + `logging.json` for formats.

# When unsure, ask the repo owner

- If an action touches Defender, scheduled tasks, or Sysmon, request explicit confirmation from the repo owner before changing defaults.

---
If you'd like, I can shorten this to exactly 20 lines or expand with copyable code snippets for common edits. Any unclear areas I should expand? 
