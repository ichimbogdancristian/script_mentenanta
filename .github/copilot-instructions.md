
# Copilot Instructions for Windows Maintenance Automation Project

## Project Architecture
- **Entry Point:** `script.bat` (batch file) is the main launcher. It ensures all dependencies (PowerShell 7, Winget, Chocolatey, NuGet, PSWindowsUpdate, Appx) are installed and up to date, sets up scheduled tasks, downloads/updates the repo, and launches `script.ps1` with admin rights.
- **Orchestration:** `script.ps1` (PowerShell) contains all maintenance logic, organized as modular functions for inventory, bloatware removal, app install, updates, telemetry, and restore.
- **Task Coordination:** Tasks are defined in a global array (e.g., `$global:ScriptTasks`) with metadata for centralized execution and logging.
- **Configuration:** Optional `config.json` in the script directory customizes behavior (see `README.md` for format).
- **Logging:** All actions/errors are logged to `maintenance.log` via a color-coded `Write-Log` function.

## Developer Workflows
- **Run as Administrator:** Required for nearly all operations. The batch file auto-elevates if needed.
- **Start with `script.bat`:** Handles all dependency checks, updates, and launches the PowerShell script in a new admin window.
- **Scheduled Tasks:** The batch file auto-creates monthly and startup scheduled tasks for recurring and post-restart runs.
- **Repo Updates:** The batch file downloads and extracts the latest repo ZIP from GitHub before each run, ensuring up-to-date scripts.
- **Logs:** All output is written to `maintenance.log` (PowerShell) and the console (batch).

## Patterns and Conventions
- **Dependency Handling:** The batch file uses robust, multi-method checks and installs for Winget, Chocolatey, NuGet, and PowerShell modules. If a dependency is missing, it logs a warning and continues with degraded functionality.
- **Inventory Collection:** Combines AppX, Winget, Chocolatey, and Registry sources for a complete app list.
- **Bloatware Removal:** Uses AppX, DISM, Winget, Choco, Capabilities, and Registry, with enhanced pattern matching for app names.
- **Essential Apps:** Skips already-installed apps by cross-referencing inventory. Installs LibreOffice if Microsoft Office is missing.
- **Browser Management:** Removes non-whitelisted browsers and configures policies for Firefox, Chrome, and Edge.
- **Verbose Logging:** Controlled by config; verbose output is off by default.
- **Graceful Degradation:** If a tool/module is missing, the script logs a warning and continues.

## Integration Points
- **External Tools:** Winget, Chocolatey, NuGet, AppX, DISM, Windows Capabilities, Registry.
- **PowerShell Modules:** PSWindowsUpdate, Appx (checked/installed at runtime).
- **Windows Task Scheduler:** Used for monthly and startup tasks.

## Key Files
- `script.ps1`: Main PowerShell script with all maintenance logic.
- `script.bat`: Batch launcher for dependency setup, repo update, and script execution.
- `maintenance.log`: Log file for all operations.
- `README.md`: Project overview and configuration instructions.
- `config.json`: Optional, for custom settings (not always present).

## Example Patterns
- **Task Definition:**
  ```powershell
  $global:ScriptTasks = @(
    @{ Name = 'RemoveBloatware'; Function = { Remove-Bloatware }; Description = '...' },
    # ...
  )
  ```
- **Inventory Collection:**
  ```powershell
  Get-ComputerInfo | Out-File ...
  Get-AppxPackage -AllUsers | ...
  winget list ...
  choco list --local-only ...
  ```
- **Bloatware Removal:**
  ```powershell
  Remove-AppxPackage ...
  dism /online /remove-provisionedappxpackage ...
  winget uninstall ...
  choco uninstall ...
  Remove-WindowsCapability ...
  ```

---

If any section is unclear or missing, please provide feedback to improve these instructions for future AI agents.
