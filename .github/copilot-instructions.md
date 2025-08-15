

# Copilot Instructions for Windows Maintenance Automation Project

## Project Structure
- `script.bat`: Batch file entry point. Handles dependency checks, auto-elevation, repo update, and launches `script.ps1` as administrator.
- `script.ps1`: Main PowerShell script. Contains all maintenance logic, modular functions, and orchestrates tasks.
- `README.md`: Project documentation, usage, and configuration details.
- `.github/copilot-instructions.md`: AI agent instructions and conventions.
- `maintenance.log`: Log file for all operations (created at runtime).
- `maintenance_report.txt`: Summary report after each run (created at runtime).
- `config.json`: Optional, for custom settings (see README for format).

## Logic & Syntax
- **Batch (`script.bat`)**: Uses Windows batch syntax for dependency checks, elevation, repo update, and PowerShell invocation. Color-coded console output for status.
- **PowerShell (`script.ps1`)**: Written in PowerShell 7 syntax. Modular functions for each maintenance task. Uses advanced error handling, logging, and color-coded output. Centralized task coordination via `$global:ScriptTasks` array.
- **Config (`config.json`)**: JSON format. Allows customization of task execution, exclusions, and reporting.

## Formatting Conventions
- Indentation: 4 spaces for PowerShell, tabs for batch files.
- Function names: PascalCase for PowerShell functions.
- Comments: Descriptive, with region markers for major sections.
- Logging: All actions/errors logged to `maintenance.log` with timestamps and color codes.
- Reports: Human-readable summary in `maintenance_report.txt`, detailed inventory files for audit.

## Environment of Execution
- **OS:** Windows 10/11 (x64, ARM64 supported).
- **Shell:** PowerShell 7 (auto-installed if missing).
- **Dependencies:** Winget, Chocolatey, NuGet, PSWindowsUpdate, Appx (checked/installed at runtime).
- **Execution:** Always run as administrator (auto-elevated by batch file).
- **Scheduled Tasks:** Monthly/startup tasks auto-created for recurring runs and post-restart continuation.
- **Repo Update:** Batch file downloads/extracts latest repo ZIP from GitHub before each run.

## Example Execution Flow
1. User runs `script.bat` (double-click or scheduled task).
2. Batch file checks dependencies, auto-elevates, updates repo, launches `script.ps1` as admin.
3. PowerShell script loads config, defines `$global:ScriptTasks`, and executes each task in order:
  - Inventory collection
  - Bloatware removal
  - Essential app install
  - Browser management
  - Windows updates
  - Telemetry/privacy tweaks
  - Restore/cleanup
  - Reporting
4. All output logged to `maintenance.log` and console.
5. Reports generated after completion.

## Best Practices
- Always start with `script.bat` for full automation.
- Review `README.md` for config options and usage.
- Check `maintenance.log` and `maintenance_report.txt` for troubleshooting.
- Update dependencies and repo regularly for latest features.

---

If any section is unclear or missing, please provide feedback to improve these instructions for future AI agents.
