# Copilot Instructions for script_mentenanta

## Project Overview
This project automates the setup and execution of a Windows maintenance script. It uses a batch file (`script.bat`) as the entry point to:
- Check for and install dependencies: WinGet, PowerShell 7, Microsoft.VCLibs, and Microsoft.UI.Xaml
- Download the latest maintenance script repository from GitHub
- Run a PowerShell script (`script.ps1`) for actual maintenance tasks

## Key Files
- `script.bat`: Main orchestrator. Handles admin checks, dependency installation, repo download, and script execution.
- `script.ps1`: The PowerShell maintenance script (must be present in the downloaded repo).
- `instructions.md`: Project-specific PowerShell and scripting guidelines.

## Essential Patterns & Conventions
- **Admin Privileges**: All setup must run as administrator. The batch script checks and prompts if not.
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

## Example: Adding a New Dependency
To add a new tool to the setup:
1. Add a check and install logic in `script.bat` (following the VCLibs/XAML/WinGet pattern).
2. Document the change in `instructions.md` if it affects PowerShell code style or workflow.

## External Integrations
- Downloads from GitHub and NuGet for dependencies and scripts.
- Uses PowerShell and WinGet for package management.

## Testing & Validation
- Manual: Run `script.bat` as admin and verify all steps complete without errors.
- Automated: (Not present, but recommended) Add sample test cases for PowerShell functions as described in `instructions.md`.

---
For more details on PowerShell best practices, see `instructions.md`.
