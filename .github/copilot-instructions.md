# Copilot Instructions for Windows Maintenance Script

## Project Architecture
- **Single PowerShell script (`script.ps1`)** orchestrates all maintenance tasks.
- **Major tasks** are modular functions: system inventory, bloatware removal, essential app installation, Windows updates, telemetry disabling, and system restore.
- **Task array (`$global:ScriptTasks`)** defines all available tasks and their metadata for centralized coordination.
- **Configuration** is loaded from `config.json` (see README for options and format).
- **Logging** is centralized to `maintenance.log` using the `Write-Log` function with color-coded output.

## Developer Workflows
- **Run as Administrator**: Required for most operations.
- **Start with `script.bat` or run `script.ps1` directly**.
- **Custom configuration**: Place `config.json` in the script directory to override defaults.
- **Logs**: All actions and errors are written to `maintenance.log`.

## Patterns and Conventions
- **Inventory collection**: Uses multiple sources (AppX, Winget, Chocolatey, Registry) for completeness.
- **Bloatware removal**: Multi-method approach (AppX, DISM, Winget, Choco, Capabilities, Registry). Uses enhanced pattern matching for app names.
- **Essential apps**: Skips already installed apps by cross-referencing inventory before install.
- **Office fallback**: If Microsoft Office is not detected, installs LibreOffice automatically.
- **Verbose logging**: Controlled by config, disables verbose output unless enabled.
- **Graceful degradation**: If a dependency (e.g., Winget, Choco, AppX) is missing, the script logs a warning and continues.

## Integration Points
- **External dependencies**: Winget, Chocolatey, AppX, DISM, Registry, Windows Capabilities.
- **Browser management**: Removes non-whitelisted browsers and configures policies for Firefox, Chrome, and Edge.

## Key Files
- `script.ps1`: Main script with all logic and functions.
- `script.bat`: Batch wrapper for launching the PowerShell script.
- `config.json`: Optional configuration file for customizing behavior.
- `maintenance.log`: Log file for all operations.
- `README.md`: Project overview and configuration instructions.

## Example Patterns
- **Task definition**:
  ```powershell
  $global:ScriptTasks = @(
    @{ Name = 'RemoveBloatware'; Function = { Remove-Bloatware }; Description = '...' },
    ...
  )
  ```
- **Inventory collection**:
  ```powershell
  Get-ComputerInfo | Out-File ...
  Get-AppxPackage -AllUsers | ...
  winget list ...
  choco list --local-only ...
  ```
- **Bloatware removal**:
  ```powershell
  Remove-AppxPackage ...
  dism /online /remove-provisionedappxpackage ...
  winget uninstall ...
  choco uninstall ...
  Remove-WindowsCapability ...
  ```

---

If any section is unclear or missing, please provide feedback to improve these instructions for future AI agents.
