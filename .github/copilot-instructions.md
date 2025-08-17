# Copilot Instructions for script_mentenanta

## Project Overview
This project automates the setup and execution of a Windows maintenance script designed for seamless deployment across multiple PCs. It uses a batch file (`script.bat`) as the entry point to:
- Check for and install dependencies: WinGet, PowerShell 7, Microsoft.VCLibs, and Microsoft.UI.Xaml
- Download the latest maintenance script repository from GitHub
- Run a PowerShell script (`script.ps1`) for actual maintenance tasks

## Key Files
- `script.bat`: Main orchestrator. Handles admin checks, dependency installation, repo download, and script execution.
- `script.ps1`: The PowerShell maintenance script (must be present in the downloaded repo).
- `instructions.md`: Project-specific PowerShell and scripting guidelines.

## Essential Patterns & Conventions
- **Admin Privileges**: All setup must run as administrator. The batch script checks and prompts if not.
- **Environment Awareness**: `script.bat` runs in Command Prompt environment, `script.ps1` runs in PowerShell 7 environment on fresh Windows 10/11 installations.
- **Path Independence**: The script must be able to run from any folder location and automatically detect its current path at launch time using `%~f0`.
- **Multi-PC Compatibility**: Script must work flawlessly across multiple PCs with different configurations, hardware, and Windows versions.
- **Dynamic Path Detection**: All scheduled tasks and operations must use dynamically detected script paths, never hardcoded locations.
- **Environment Isolation**: Be aware that batch files run in CMD environment while PowerShell scripts run in PS7 environment - handle path variables and execution contexts accordingly.
- **Dependency Checks**: Uses PowerShell and batch logic to verify/install WinGet, PowerShell 7, and required AppX packages. Installs missing components automatically.
- **Repository Handling**: Always downloads and extracts the latest repo version to a clean directory before running scripts.
- **Script Execution**: Prefers PowerShell 7 (`pwsh`), falls back to Windows PowerShell if needed.
- **Cleanup**: Temporary files and directories are removed at the end of execution.

## Developer Workflows
- **Run the project**: Right-click `script.bat` and select "Run as administrator".
- **Debugging**: Use `echo` statements in the batch file and `Write-Host` in PowerShell for step tracing. Check `%errorLevel%` after each critical step.
- **Update maintenance logic**: Edit `script.ps1` in the repo. The batch script will always fetch the latest version.

## Project-Specific Guidelines
- Follow PowerShell style and safety rules from `instructions.md` (e.g., use approved verbs, robust parameter validation, modular functions, secure credential handling).
- Keep all logic for dependency installation and repo management in `script.bat`.
- Do not hardcode paths; use environment variables and relative paths as in the batch script.
- Ensure all scripts are idempotent and safe to re-run.
- Always use `%~f0` for current script path detection in batch files.
- Use delayed expansion `!SCRIPT_PATH!` when referencing paths inside conditional blocks.
- Test script operation from multiple locations (Desktop, Downloads, USB drives, network paths).

## Multi-PC Deployment Considerations
- Script location independence: Must work from Desktop, Downloads, USB drives, network locations
- Windows version compatibility: Support Windows 10 (all builds) and Windows 11
- Hardware agnostic: Works on x64, ARM64, different manufacturers
- Network environment flexibility: Handle online/offline scenarios and restricted connectivity
- User account compatibility: Works with standard users (with UAC), administrators, and domain accounts
- Scheduled task reliability: Tasks must point to correct script location regardless of where script is stored

## Example: Adding a New Dependency
To add a new tool to the setup:
1. Add a check and install logic in `script.bat` (following the VCLibs/XAML/WinGet pattern).
2. Document the change in `instructions.md` if it affects PowerShell code style or workflow.

## External Integrations
- Downloads from GitHub and NuGet for dependencies and scripts.
- Uses PowerShell and WinGet for package management.

## Testing & Validation
- Manual: Run `script.bat` as admin and verify all steps complete without errors.
- Multi-location testing: Test from Desktop, Downloads, USB drive, and network locations.
- Cross-PC validation: Verify operation on different Windows 10/11 systems.
- Automated: (Not present, but recommended) Add sample test cases for PowerShell functions as described in `instructions.md`.

---
For more details on PowerShell best practices, see `instructions.md`.
