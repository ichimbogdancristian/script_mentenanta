
# Windows Maintenance Automation Script

## Overview
Automates essential Windows maintenance tasks for IT, sysadmins, and power users. Combines inventory, bloatware removal, app installation, updates, telemetry/privacy tweaks, cleanup, and reporting into a single, repeatable workflow.

## Project Structure
- `script.bat`: Batch file entry point. Handles dependency checks, auto-elevation, repo update, and launches `script.ps1` as administrator.
- `script.ps1`: Main PowerShell script. Contains all maintenance logic, modular functions, and orchestrates tasks.
- `README.md`: Project documentation, usage, and configuration details.
- `.github/copilot-instructions.md`: AI agent instructions and conventions.
- `maintenance.log`: Log file for all operations (created at runtime).
- `maintenance_report.txt`: Summary report after each run (created at runtime).
- `config.json`: Optional, for custom settings (see below).

## Logic & Syntax
- **Batch (`script.bat`)**: Windows batch syntax for dependency checks, elevation, repo update, and PowerShell invocation. Color-coded console output for status.
- **PowerShell (`script.ps1`)**: PowerShell 7 syntax. Modular functions for each maintenance task. Advanced error handling, logging, and color-coded output. Centralized task coordination via `$global:ScriptTasks` array.
- **Config (`config.json`)**: JSON format. Customizes task execution, exclusions, and reporting.

## Formatting Conventions
- Indentation: 4 spaces for PowerShell, tabs for batch files.
- Function names: PascalCase for PowerShell functions.
- Comments: Descriptive, with region markers for major sections.
- Logging: All actions/errors logged to `maintenance.log` with timestamps and color codes.
- Reports: Human-readable summary in `maintenance_report.txt`, detailed inventory files for audit.

## Environment of Execution
- **OS:** Windows 10/11 (x64, ARM64 supported)
- **Shell:** PowerShell 7 (auto-installed if missing)
- **Dependencies:** Winget, Chocolatey, NuGet, PSWindowsUpdate, Appx (checked/installed at runtime)
- **Execution:** Always run as administrator (auto-elevated by batch file)
- **Scheduled Tasks:** Monthly/startup tasks auto-created for recurring runs and post-restart continuation
- **Repo Update:** Batch file downloads/extracts latest repo ZIP from GitHub before each run

## Usage
1. Double-click `script.bat` or run it from an elevated command prompt.
2. Optionally edit `config.json` to customize tasks, exclusions, or reporting.
3. Review `maintenance.log` and `maintenance_report.txt` after each run.

## Configuration (`config.json`)
See example below. All keys are optional.
```json
{
  "ExcludeTasks": ["RemoveBloatware", "InstallApps"],
  "AppWhitelist": ["Firefox", "LibreOffice"],
  "ReportLevel": "detailed"
}
```

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

## Troubleshooting
- Check `maintenance.log` for errors and warnings.
- Review `maintenance_report.txt` for summary and details.
- Ensure all dependencies are installed and up to date.

## Contributing
Pull requests and feedback are welcome! See `.github/copilot-instructions.md` for AI agent conventions and best practices.

## License
[MIT](LICENSE)
  ```powershell
  # Remove non-whitelisted browsers
  # Configure Firefox, Chrome, Edge policies
  # Set Firefox as default browser
  ```

---
