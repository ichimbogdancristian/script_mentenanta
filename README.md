
# Windows Maintenance Automation Script (PowerShell 7.5.2 Optimized)

## Overview
Automates essential Windows maintenance tasks for IT, sysadmins, and power users. Combines inventory, bloatware removal, app installation, updates, telemetry/privacy tweaks, cleanup, and reporting into a single, repeatable workflow. **Now optimized for PowerShell 7.5.2** with enhanced performance, modern async operations, and intelligent progress tracking.

## 🆕 **What's New in PowerShell 7.5.2 Edition**
- **Enhanced Performance**: Parallel processing for inventory collection and package operations
- **Smart Progress Tracking**: Visual progress bars in console, clean logs in files
- **Modern Package Management**: Unified wrapper for winget/chocolatey with improved reliability
- **Advanced Error Handling**: Detailed exception information and graceful degradation
- **Async Operations**: Modern process management with timeout support
- **Backward Compatibility**: Automatic fallback to PowerShell 5.1 for legacy operations
- **Standardized Temp Lists**: JSON format with metadata for better diff operations
- **Thread-Safe Operations**: Using modern concurrent collections for reliability

## Project Structure
- `script.bat`: Batch file entry point. Handles dependency checks, auto-elevation, repo update, and launches `script.ps1` as administrator.
- `script.ps1`: Main PowerShell script optimized for PowerShell 7.5.2. Contains all maintenance logic with enhanced logging and progress tracking.
- `README.md`: Project documentation, usage, and configuration details.
- `.github/copilot-instructions.md`: AI agent instructions and conventions.
- `maintenance.log`: Clean, timestamped log file for all operations (created at runtime).
- `maintenance_report.txt`: Summary report after each run (created at runtime).
- `config.json`: Optional, for custom settings (see below).
- `inventory.json`: Comprehensive system inventory in structured JSON format (created at runtime).
- **Temp Lists**: Standardized JSON files for bloatware/essential app diff operations with metadata.

## Enhanced Logging System
The script now features a sophisticated logging system that separates console progress from file logging:

### **Logging Functions**
- **`Write-Log`**: Combined function for both console and file output
- **`Write-LogFile`**: File-only logging without console noise
- **`Write-ConsoleMessage`**: Console-only messages with enhanced colors
- **`Write-TaskProgress`**: Progress bars for console, simple messages for files

### **Progress Tracking**
Visual progress bars are displayed for major operations:
- Overall task execution progress
- Bloatware removal with current app status
- Essential app installation progress
- System inventory collection phases
- Temp file cleanup with folder/item counts

### **Clean Log Files**
Log files now contain only relevant operational data without progress bar noise, making troubleshooting and analysis much more effective.

## Logic & Syntax
- **Batch (`script.bat`)**: Windows batch syntax for dependency checks, elevation, repo update, and PowerShell invocation. Color-coded console output for status.
- **PowerShell (`script.ps1`)**: **PowerShell 7.5.2 syntax** with fallback compatibility to PowerShell 5.1. Features parallel processing, async operations, enhanced JSON handling, and modern error management. Centralized task coordination via `$global:ScriptTasks` array.
- **Config (`config.json`)**: JSON format. Customizes task execution, exclusions, and reporting.

## Modern PowerShell 7.5.2 Features
- **Parallel Processing**: `ForEach-Object -Parallel` for significantly faster inventory collection
- **Enhanced JSON Operations**: Improved parsing with `-AsHashtable` and better error handling
- **Modern Process Management**: `Invoke-ModernPackageManager` with timeout and retry logic
- **Async File I/O**: UTF-8 encoding and improved file operations
- **Thread-Safe Collections**: Using `System.Collections.Concurrent` for reliability
- **Smart Compatibility**: Automatic detection and fallback to Windows PowerShell for legacy modules

## Environment of Execution
- **OS:** Windows 10/11 (x64, ARM64 supported)
- **Shell:** **PowerShell 7.5.2+ preferred**, with automatic fallback to PowerShell 5.1 for compatibility
- **Dependencies:** Winget, Chocolatey, NuGet, PSWindowsUpdate, Appx (checked/installed at runtime)
- **Execution:** Always run as administrator (auto-elevated by batch file)
- **Scheduled Tasks:** Monthly/startup tasks auto-created for recurring runs and post-restart continuation
- **Repo Update:** Batch file downloads/extracts latest repo ZIP from GitHub before each run

## Usage
1. **Double-click `script.bat`** or run it from an elevated command prompt.
2. **Watch the progress bars** in the console for real-time feedback.
3. Optionally edit `config.json` to customize tasks, exclusions, or reporting.
4. Review `maintenance.log` (clean, timestamped entries) and `maintenance_report.txt` after each run.
5. Check `inventory.json` for comprehensive system state information.

## Configuration (`config.json`)
All keys are optional. The script intelligently handles missing configurations.

```json
{
  "SkipBloatwareRemoval": false,
  "SkipEssentialApps": false,
  "SkipWindowsUpdates": false,
  "SkipTelemetryDisable": false,
  "SkipSystemRestore": false,
  "EnableVerboseLogging": false,
  "ExcludeTasks": ["TaskName1", "TaskName2"],
  "AppWhitelist": ["Firefox", "LibreOffice"],
  "ReportLevel": "detailed"
}
```

## Enhanced Execution Flow
1. User runs `script.bat` (double-click or scheduled task).
2. Batch file checks dependencies, auto-elevates, updates repo, launches `script.ps1` as admin.
3. **PowerShell 7.5.2 script** executes with enhanced progress tracking:
   - **System inventory collection** (parallel processing for speed)
   - **Bloatware removal** (diff-based analysis with progress bars)
   - **Essential app installation** (modern package managers with status)
   - **Package updates** (winget/chocolatey with enhanced reliability)
   - **Windows updates** (with progress indication)
   - **Telemetry/privacy tweaks**
   - **Temp file cleanup** (detailed progress with folder/item counts)
   - **System restore and cleanup**
   - **Final reporting** with structured output
4. **Enhanced logging**: Progress bars in console, clean timestamped entries in log files.
5. **Comprehensive reports**: Detailed inventory, operation results, and temp list files for analysis.

## Key Improvements
### **Performance**
- **Parallel inventory collection** reduces execution time significantly
- **Async package operations** with proper timeout handling
- **Modern process management** for better reliability

### **User Experience**
- **Real-time progress bars** for visual feedback
- **Enhanced color coding** for different message types
- **Clean separation** between console display and file logging

### **Reliability**
- **Enhanced error handling** with detailed exception information
- **Graceful degradation** when dependencies are missing
- **Automatic compatibility detection** and fallback mechanisms

### **Maintainability**
- **Standardized temp lists** with JSON metadata for debugging
- **Modular logging functions** for different output needs
- **Comprehensive documentation** and clear code structure

## Troubleshooting
- **Check `maintenance.log`** for clean, timestamped operational logs without progress noise.
- **Review `maintenance_report.txt`** for summary and detailed results.
- **Examine `inventory.json`** for comprehensive system state information.
- **Check temp list files** (JSON format) for bloatware/essential app operation details.
- **Ensure PowerShell 7.5.2+** is installed for optimal performance (script will auto-fallback if needed).
- **Verify all dependencies** are installed and up to date.

## Performance Notes
- **Significantly faster** inventory collection using parallel processing
- **Improved package management** with modern timeout and retry logic
- **Better memory usage** with thread-safe concurrent collections
- **Enhanced file I/O** with UTF-8 encoding and async operations

## Contributing
Pull requests and feedback are welcome! See `.github/copilot-instructions.md` for AI agent conventions and PowerShell 7.5.2 best practices.

## License
[MIT](LICENSE)
  ```powershell
  # Remove non-whitelisted browsers
  # Configure Firefox, Chrome, Edge policies
  # Set Firefox as default browser
  ```

---
