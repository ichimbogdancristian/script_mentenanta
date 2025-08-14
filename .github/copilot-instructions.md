

# Copilot Instructions for Windows Maintenance Automation Project

## Architecture & Execution Environment
- **Entry Point:** Use `script.bat` to launch. It checks/installs dependencies (PowerShell 7, Winget, Chocolatey, NuGet, PSWindowsUpdate, Appx), sets up scheduled tasks, updates the repo, and runs `script.ps1` as admin.
- **Main Logic:** `script.ps1` orchestrates all maintenance tasks via modular functions (inventory, bloatware removal, app install, updates, telemetry, restore, cleanup, reporting).
- **Task Coordination:** Tasks are defined in `$global:ScriptTasks` with metadata for centralized execution and logging.
- **Config:** Optional `config.json` customizes behavior (see `README.md` for format and options).
- **Reporting:** Generates `maintenance_report.txt` and detailed inventory files after each run.

## Developer Workflows
- **Run as Administrator:** Required for most operations. The batch file auto-elevates.
- **Start with `script.bat`:** Handles dependency checks, updates, and launches PowerShell script.
- **Scheduled Tasks:** Auto-creates monthly/startup tasks for recurring runs and post-restart continuation.
- **Repo Updates:** Downloads/extracts latest repo ZIP from GitHub before each run.
- **Logs:** All output is written to `maintenance.log` (PowerShell) and console (batch).

## Patterns & Conventions
- **Dependency Handling:** Robust, multi-method checks for Winget, Chocolatey, NuGet, PowerShell modules. Logs warnings and continues with degraded functionality if missing.
- **Inventory Collection:** Combines AppX, Winget, Chocolatey, Registry, Services, Tasks, Drivers, Updates for a complete system/app list.
- **Bloatware Removal:** Uses AppX, DISM, Winget, Choco, Capabilities, Registry, with enhanced pattern matching for app names.
- **Essential Apps:** Installs curated apps via Winget/Choco, skips already-installed, installs LibreOffice if Office is missing.
- **Browser Management:** Removes non-whitelisted browsers, configures Firefox/Chrome/Edge policies, sets Firefox as default if possible.
- **Windows Updates:** Uses PSWindowsUpdate module (auto-installs if missing).
- **Telemetry & Privacy:** Disables telemetry services, scheduled tasks, and applies registry tweaks for privacy.
- **Logging:** All actions/errors are logged to `maintenance.log` (color-coded output).
- **Reporting:** Generates `maintenance_report.txt` and inventory files for audit and troubleshooting.
- **Graceful Degradation:** Logs warnings and continues if tools/modules are missing.

## Integration Points
- **External Tools:** Winget, Chocolatey, NuGet, AppX, DISM, Windows Capabilities, Registry.
- **PowerShell Modules:** PSWindowsUpdate, Appx (checked/installed at runtime).
- **Windows Task Scheduler:** Used for monthly/startup tasks and post-restart continuation.

## Key Files
- `script.bat`: Batch launcher for dependency setup, repo update, and script execution.
- `script.ps1`: Main PowerShell script with all maintenance logic.
- `maintenance.log`: Log file for all operations.
- `maintenance_report.txt`: Summary report after each run.
- `config.json`: Optional, for custom settings.

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
  Get-Service | ...
  Get-ScheduledTask | ...
  Get-CimInstance Win32_PnPSignedDriver | ...
  Get-HotFix | ...
  ```
- **Bloatware Removal:**
  ```powershell
  Remove-AppxPackage ...
  dism /online /remove-provisionedappxpackage ...
  winget uninstall ...
  choco uninstall ...
  Remove-WindowsCapability ...
  ```
- **Browser Management:**
  ```powershell
  # Remove non-whitelisted browsers
  # Configure Firefox, Chrome, Edge policies
  # Set Firefox as default browser
  ```

---

If any section is unclear or missing, please provide feedback to improve these instructions for future AI agents.
