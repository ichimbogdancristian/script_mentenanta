
# Windows Maintenance Automation Project

## Big Picture & Architecture
- **Entry Point:** `script.bat` (batch file) is the main launcher. It checks/installs dependencies (PowerShell 7, Winget, Chocolatey, NuGet, PSWindowsUpdate, Appx), sets up scheduled tasks, downloads/updates the repo, and launches `script.ps1` with admin rights.
- **Orchestration:** `script.ps1` (PowerShell) coordinates all maintenance logic via modular functions for inventory, bloatware removal, essential app install, updates, telemetry, restore, and cleanup. All actions are logged.
- **Task Coordination:** Tasks are defined in `$global:ScriptTasks` with metadata for centralized execution and reporting.
- **Config:** Optional `config.json` customizes behavior (see below for format).
- **Reporting:** Generates `maintenance_report.txt` and detailed inventory files after each run.

## Environment & Prerequisites
- Windows 10/11
- PowerShell 5.1+ (PowerShell 7 preferred, auto-installed if missing)
- Administrator privileges (auto-elevated by batch)
- Internet connection for package managers

## Workflow
1. **Run as Administrator:** Always start with `script.bat` (auto-elevates if needed).
2. **Dependency Checks:** Batch script ensures all required tools/modules are installed or logs warnings and continues with degraded functionality.
3. **Scheduled Tasks:** Monthly and startup scheduled tasks are auto-created for recurring and post-restart runs.
4. **Repo Updates:** Batch script downloads and extracts the latest repo ZIP from GitHub before each run.
5. **PowerShell Orchestration:** `script.ps1` runs all tasks in order, logs actions/errors, and generates reports.

## Configuration
Place a custom `config.json` in the script directory to override defaults. Example options:
```json
{
  "SkipBloatwareRemoval": false,
  "SkipEssentialApps": false,
  "SkipWindowsUpdates": false,
  "SkipTelemetryDisable": false,
  "SkipSystemRestore": false,
  "EnableVerboseLogging": false,
  "CustomEssentialApps": [ { "Name": "App", "Winget": "Publisher.AppId", "Choco": "choco-name" } ],
  "CustomBloatwareList": [ "AppName1", "AppName2" ]
}
```

## Features & Patterns
- **Inventory Collection:** Combines AppX, Winget, Chocolatey, Registry, Services, Tasks, Drivers, Updates for a complete system/app list.
- **Bloatware Removal:** Uses AppX, DISM, Winget, Choco, Capabilities, Registry, with enhanced pattern matching for app names.
- **Essential Apps:** Installs curated apps via Winget/Choco, skips already-installed, installs LibreOffice if Office is missing.
- **Browser Management:** Removes non-whitelisted browsers, configures Firefox/Chrome/Edge policies, sets Firefox as default if possible.
- **Windows Updates:** Uses PSWindowsUpdate module (auto-installs if missing).
- **Telemetry & Privacy:** Disables telemetry services, scheduled tasks, and applies registry tweaks for privacy.
- **Logging:** All actions/errors are logged to `maintenance.log` (color-coded output).
- **Reporting:** Generates `maintenance_report.txt` and inventory files for audit and troubleshooting.
- **Graceful Degradation:** Logs warnings and continues if tools/modules are missing.

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
