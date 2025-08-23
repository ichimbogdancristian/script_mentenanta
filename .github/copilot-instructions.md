# Copilot Instructions for script_mentenanta

## ⚠️ CRITICAL ENVIRONMENT AWARENESS ⚠️
**NEVER FORGET**: 
- **`script.bat` = COMMAND PROMPT (CMD) ENVIRONMENT ONLY**
- **`script.ps1` = POWERSHELL 7 (PS7) ENVIRONMENT ONLY**
- **Environment Separation Must Be Strictly Maintained**

### 🚫 FORBIDDEN in script.bat (CMD Environment):
- Complex PowerShell commands with multiple cmdlets
- PowerShell object manipulation ($_.Property syntax)
- PowerShell try-catch blocks
- PowerShell pipeline operations beyond simple commands
- PowerShell-specific operators like -eq, -ne, -match
- Delayed expansion `!ERRORLEVEL!` for immediate error checks (use `%ERRORLEVEL%`)

### ✅ ALLOWED in script.bat (CMD Environment):
- Simple PowerShell one-liners with `-Command` for basic tasks
- CMD native commands: IF, FOR, SET, CALL, ECHO, etc.
- Registry operations: REG QUERY, REG ADD, REG DELETE
- Basic system commands: NET SESSION, WHOAMI, WHERE
- File operations: COPY, DEL, MKDIR, RMDIR
- Immediate expansion `%ERRORLEVEL%` for error checking

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
- **Dependency Checks**: Uses CMD-native commands and simple PowerShell calls only. Complex operations go in script.ps1.
- **Repository Handling**: Always downloads and extracts the latest repo version to a clean directory before running scripts.
- **Script Execution**: Prefers PowerShell 7 (`pwsh`), falls back to Windows PowerShell if needed.
- **Cleanup**: Temporary files and directories are removed at the end of execution.

## Developer Workflows
- **Run the project**: Right-click `script.bat` and select "Run as administrator".
- **Debugging**: Use `echo` statements in the batch file and `Write-Host` in PowerShell for step tracing. Check `%ERRORLEVEL%` after each critical step.
- **Update maintenance logic**: Edit `script.ps1` in the repo. The batch script will always fetch the latest version.

## 🎯 CMD vs PowerShell Environment Rules
### script.bat (CMD Environment) - KEEP IT SIMPLE:
- Use only CMD-native commands and simple PowerShell one-liners
- For complex operations, defer to script.ps1
- Use `%ERRORLEVEL%` for immediate error checking
- Use `!variable!` only when inside loops or conditionals with delayed expansion
- Prefer registry operations over WMI/CIM queries
- Use WHERE, NET, REG, WHOAMI for system detection

### script.ps1 (PowerShell Environment) - FULL POWER:
- Use full PowerShell capabilities
- Complex object manipulation, pipelines, try-catch blocks
- CIM/WMI operations, advanced cmdlets
- Module imports and package management
- **CRITICAL SYNTAX REQUIREMENTS**:
  - Always put $null on the LEFT side of equality comparisons: `$null -eq $variable` (NOT `$variable -eq $null`)
  - Every try statement MUST have either a catch or finally block
  - Use ScriptBlock approach for complex operations that need error handling
  - Properly define paths with fallback mechanisms for cross-environment compatibility

## Project-Specific Guidelines
- Follow PowerShell style and safety rules from `instructions.md` (e.g., use approved verbs, robust parameter validation, modular functions, secure credential handling).
- Keep all logic for dependency installation and repo management in `script.bat` using CMD-appropriate methods.
- Do not hardcode paths; use environment variables and relative paths as in the batch script.
- Ensure all scripts are idempotent and safe to re-run.
- Always use `%~f0` for current script path detection in batch files.
- Use delayed expansion `!SCRIPT_PATH!` when referencing paths inside conditional blocks.
- Test script operation from multiple locations (Desktop, Downloads, USB drives, network paths).

## 🚨 Common Mistakes to Avoid:
1. **Complex PowerShell in script.bat** - Move complex logic to script.ps1
2. **Wrong variable expansion** - Use `%VAR%` for immediate, `!VAR!` for delayed
3. **PowerShell syntax in CMD** - No $variables, no -operators in CMD environment
4. **Hardcoded paths** - Always use dynamic path detection
5. **Missing admin checks** - Always verify privileges before system operations
6. **PowerShell null comparisons on wrong side** - Always use `$null -eq $variable` (not `$variable -eq $null`)
7. **Missing catch blocks in try statements** - Every try MUST have a catch or finally block
8. **Improper repo folder path detection** - Use multiple fallback methods for reliability
9. **Mixed environment variable access** - Use environment-appropriate syntax for each script

## Multi-PC Deployment Considerations
- Script location independence: Must work from Desktop, Downloads, USB drives, network locations
- Windows version compatibility: Support Windows 10 (all builds) and Windows 11
- Hardware agnostic: Works on x64, ARM64, different manufacturers
- Network environment flexibility: Handle online/offline scenarios and restricted connectivity
- User account compatibility: Works with standard users (with UAC), administrators, and domain accounts
- Scheduled task reliability: Tasks must point to correct script location regardless of where script is stored

## 💡 When Modifying script.bat - Remember:
1. **Environment Check**: Am I in CMD or PowerShell environment? (script.bat = CMD!)
2. **Simplicity First**: Can this be done with CMD commands instead of PowerShell?
3. **Defer Complexity**: Should this complex logic go in script.ps1 instead?
4. **Variable Expansion**: Do I need immediate (`%VAR%`) or delayed (`!VAR!`) expansion?
5. **Error Handling**: Am I using `%ERRORLEVEL%` correctly for immediate checks?

## 🛠️ Environment-Specific Debugging
### CMD Environment (script.bat)
- Use `echo DEBUG: Variable=%VARIABLE%` for tracing
- Add `pause` statements to freeze execution for review
- Check `if %ERRORLEVEL% NEQ 0` after critical operations
- Enable delayed expansion with `setlocal EnableDelayedExpansion` when needed
- Redirect output with `> debug_output.log 2>&1` for logging

### PowerShell Environment (script.ps1)
- Use `Write-Host "DEBUG: $variable" -ForegroundColor Cyan` for tracing
- Add `$VerbosePreference = 'Continue'` and use `Write-Verbose` statements
- Use `try/catch` blocks with specific error handling
- Implement `Set-PSDebug -Trace 1` for line-by-line tracing
- Use structured logging with `Write-Log` function instead of console output

## Example: Adding a New Dependency
To add a new tool to the setup:
1. Add a check and install logic in `script.bat` using CMD-appropriate methods (REG, WHERE, simple PowerShell calls)
2. For complex operations, add the logic to `script.ps1` and call it from `script.bat`
3. Document the change in `instructions.md` if it affects PowerShell code style or workflow.
2. Document the change in `instructions.md` if it affects PowerShell code style or workflow.

## External Integrations
- Downloads from GitHub and NuGet for dependencies and scripts.
- Uses PowerShell and WinGet for package management.

## Testing & Validation
- Manual: Run `script.bat` as admin and verify all steps complete without errors.
- Multi-location testing: Test from Desktop, Downloads, USB drive, and network locations.
- Cross-PC validation: Verify operation on different Windows 10/11 systems.
- Syntax validation: Run PSScriptAnalyzer to check PowerShell best practices.
- Environment testing: Verify script.bat works in CMD and script.ps1 works in PowerShell 7.
- Automated: (Not present, but recommended) Add sample test cases for PowerShell functions as described in `instructions.md`.

---
For more details on PowerShell best practices, see `instructions.md`.
