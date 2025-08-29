

# Copilot Instructions for Windows Maintenance Automation Project

## Project Structure
- `script.bat`: Batch file entry point. Handles dependency checks, auto-elevation, repo update, and launches `script.ps1` as administrator.
- `script.ps1`: Main PowerShell script optimized for PowerShell 7.5.2. Contains all maintenance logic, modular functions, and orchestrates tasks with enhanced logging and progress tracking.
- `README.md`: Project documentation, usage, and configuration details.
- `.github/copilot-instructions.md`: AI agent instructions and conventions.
- `maintenance.log`: Log file for all operations (created at runtime).
- `maintenance_report.txt`: Summary report after each run (created at runtime).
- `config.json`: Optional, for custom settings (see README for format).
- `inventory.json`: System inventory in JSON format (created at runtime).
- Temp lists: Standardized JSON temp files for bloatware/essential app operations.

## Logic & Syntax
- **Batch (`script.bat`)**: Uses Windows batch syntax for dependency checks, elevation, repo update, and PowerShell invocation. Color-coded console output for status.
- **PowerShell (`script.ps1`)**: Written in PowerShell 7.5.2 syntax with backward compatibility to PowerShell 5.1. Uses modern features like parallel processing, async operations, enhanced JSON handling, and improved error management. Centralized task coordination via `$global:ScriptTasks` array.
- **Config (`config.json`)**: JSON format. Allows customization of task execution, exclusions, and reporting.

## Enhanced Logging System (PowerShell 7.5.2 Optimized)
- **Write-Log**: Combined function for both console and file output with enhanced color support
- **Write-LogFile**: File-only logging without console noise, perfect for detailed operations
- **Write-ConsoleMessage**: Console-only messages with enhanced color coding (INFO, WARN, ERROR, SUCCESS, PROGRESS)
- **Write-TaskProgress**: Smart progress bars for console, simple completion messages for file logs
- **Progress Tracking**: Visual progress bars for major operations (task execution, bloatware removal, app installation, inventory collection, cleanup)

## Modern PowerShell 7.5.2 Features
- **Parallel Processing**: ForEach-Object -Parallel for inventory collection and package operations
- **Async Operations**: Modern process management with timeout support
- **Enhanced JSON**: Improved parsing with -AsHashtable and better error handling
- **Modern Package Management**: Invoke-ModernPackageManager wrapper with enhanced reliability
- **Thread-Safe Operations**: Using System.Collections.Concurrent namespaces
- **Improved File I/O**: UTF-8 encoding and async file operations
- **Fallback Compatibility**: Automatic detection and fallback to Windows PowerShell 5.1 for legacy operations

## Formatting Conventions
- Indentation: 4 spaces for PowerShell, tabs for batch files.
- Function names: PascalCase for PowerShell functions.
- Comments: Descriptive, with region markers for major sections.
- Logging: Separated console progress from file logging - progress bars in console, clean timestamped entries in files.
- Reports: Human-readable summary in `maintenance_report.txt`, detailed inventory files for audit.
- Temp Lists: Standardized JSON format with metadata for bloatware and essential app operations.

## Environment of Execution
- **OS:** Windows 10/11 (x64, ARM64 supported).
- **Shell:** PowerShell 7.5.2+ preferred, with automatic fallback to PowerShell 5.1 for compatibility.
- **Dependencies:** Winget, Chocolatey, NuGet, PSWindowsUpdate, Appx (checked/installed at runtime).
- **Execution:** Always run as administrator (auto-elevated by batch file).
- **Scheduled Tasks:** Monthly/startup tasks auto-created for recurring runs and post-restart continuation.
- **Repo Update:** Batch file downloads/extracts latest repo ZIP from GitHub before each run.
- **Modern Process Management:** Enhanced timeout handling, async operations, and improved error reporting.

## Example Execution Flow
1. User runs `script.bat` (double-click or scheduled task).
2. Batch file checks dependencies, auto-elevates, updates repo, launches `script.ps1` as admin.
3. PowerShell script loads config, defines `$global:ScriptTasks`, and executes each task with progress tracking:
   - System inventory collection (with parallel processing)
   - Bloatware removal (diff-based with progress bars)
   - Essential app installation (modern package managers with progress)
   - Package updates (winget/chocolatey with enhanced reliability)
   - Windows updates (with progress tracking)
   - Telemetry/privacy tweaks
   - Temp file cleanup (with detailed progress)
   - System restore and cleanup
   - Final reporting and temp list generation
4. Enhanced logging: Progress bars in console, clean entries in `maintenance.log`.
5. Structured reports generated with detailed inventory and operation results.

## Key Modernizations
- **Standardized Temp Lists**: JSON format with metadata for bloatware/essential app diff operations
- **Enhanced Error Handling**: Detailed exception information and graceful degradation
- **Modern Package Management**: Unified wrapper for winget/chocolatey with timeout and retry logic
- **Parallel Inventory Collection**: Significantly improved performance using PowerShell 7.5.2 parallel processing
- **Smart Progress Tracking**: Visual feedback without cluttering log files
- **Compatibility Layer**: Automatic PowerShell version detection and appropriate command execution

## Best Practices
- Always start with `script.bat` for full automation.
- Review `README.md` for config options and usage.
- Check `maintenance.log` for clean, timestamped operational logs.
- Review `maintenance_report.txt` for summary and `inventory.json` for detailed system state.
- Use temp list files for debugging bloatware/essential app operations.
- Leverage PowerShell 7.5.2 features while maintaining backward compatibility.
- Progress bars provide user feedback without affecting log file quality.

---

If any section is unclear or missing, please provide feedback to improve these instructions for future AI agents.
