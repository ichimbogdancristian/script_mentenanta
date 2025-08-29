

# Copilot Instructions for Windows Maintenance Automation Project

## Project Structure
- `script.bat`: Batch file entry point. Handles dependency checks, auto-elevation, repo update, and launches `script.ps1` as administrator.
- `script.ps1`: Main PowerShell script optimized for PowerShell 7.5.2. Contains all maintenance logic, modular functions, and orchestrates tasks with enhanced logging and progress tracking.
- `README.md`: Project documentation, usage, and configuration details.
- `.github/copilot-instructions.md`: AI agent instructions and conventions.
- `maintenance.log`: Detailed timestamped log file for all operations (created at runtime).
- `maintenance_report.txt`: **Unified Enhanced Report** - Comprehensive system maintenance report with execution summary, system info, task results, actions performed, and performance metrics (created at runtime).
- `config.json`: Optional, for custom settings (see README for format).
- `inventory.json`: System inventory in JSON format (created at runtime).
- Temp lists: Standardized JSON temp files for bloatware/essential app operations.

## Logic & Syntax
- **Batch (`script.bat`)**: Uses Windows batch syntax for dependency checks, elevation, repo update, and PowerShell invocation. Color-coded console output for status.
- **PowerShell (`script.ps1`)**: Written in PowerShell 7.5.2 syntax with backward compatibility to PowerShell 5.1. Uses modern features like parallel processing, async operations, enhanced JSON handling, and improved error management. Centralized task coordination via `$global:ScriptTasks` array.
- **Config (`config.json`)**: JSON format. Allows customization of task execution, exclusions, and reporting.

## Enhanced Unified Reporting System (PowerShell 7.5.2 Optimized)
- **Write-Log**: Combined function for both console and file output with enhanced color support
- **Write-LogFile**: File-only logging without console noise, perfect for detailed operations
- **Write-ConsoleMessage**: Console-only messages with enhanced color coding (INFO, WARN, ERROR, SUCCESS, PROGRESS)
- **Write-TaskProgress**: Smart progress bars for console, simple completion messages for file logs
- **Write-UnifiedMaintenanceReport**: Comprehensive unified report generation with system info, task execution details, performance metrics, categorized actions, and file listings
- **Performance Tracking**: Automated collection of execution metrics, inventory timings, and system performance data

## Modern PowerShell 7.5.2 Features
- **Sequential Processing**: Reliable inventory collection and package operations (no hanging)
- **Async Operations**: Modern process management with timeout support
- **Enhanced JSON**: Improved parsing with -AsHashtable and better error handling
- **Modern Package Management**: Invoke-ModernPackageManager wrapper with enhanced reliability
- **Thread-Safe Operations**: Using System.Collections.Concurrent namespaces
- **Improved File I/O**: UTF-8 encoding and async file operations
- **Reduced PS5.1 Dependency**: Native PS7+ implementations for AppX, Windows Updates, and System Restore
- **Fallback Compatibility**: Automatic detection and fallback to Windows PowerShell 5.1 for legacy operations

## Formatting Conventions
- Indentation: 4 spaces for PowerShell, tabs for batch files.
- Function names: PascalCase for PowerShell functions.
- Comments: Descriptive, with region markers for major sections.
- Logging: Separated console progress from file logging - progress bars in console, clean timestamped entries in files.
- Reports: **Unified Enhanced Report** in `maintenance_report.txt` with comprehensive system information, execution metrics, and categorized actions. Detailed inventory files for audit.
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
5. **Unified Enhanced Reporting**: Comprehensive system maintenance report with execution summary, performance metrics, categorized actions, and detailed system information.

## Key Modernizations
- **Standardized Temp Lists**: JSON format with metadata for bloatware/essential app diff operations
- **Enhanced Error Handling**: Detailed exception information and graceful degradation
- **Modern Package Management**: Unified wrapper for winget/chocolatey with timeout and retry logic
- **Sequential Inventory Collection**: Reliable performance using sequential processing (no hanging issues)
- **Smart Progress Tracking**: Visual feedback without cluttering log files
- **Reduced PS5.1 Dependency**: Native PowerShell 7+ implementations for most operations
- **Compatibility Layer**: Automatic PowerShell version detection and appropriate command execution

## 🚨 MANDATORY VSCode Development and Quality Assurance Protocol

### **AUTOMATIC DIAGNOSTICS CHECKING (OBLIGATORY)**
**⚠️ CRITICAL REQUIREMENT**: Every AI agent MUST automatically check and resolve ALL VSCode diagnostics before completing any code changes. This is NOT optional.

#### **Pre-Code Change Protocol (MANDATORY STEPS)**
1. **BEFORE making ANY code changes**: Run `get_errors` tool on target files
2. **DURING code editing**: Monitor for new diagnostic issues  
3. **AFTER each code change**: Run `get_errors` tool again to verify no new issues
4. **BEFORE completion**: Final `get_errors` check on ALL modified files

#### **Diagnostic Categories to Address (ALL REQUIRED)**
- ✅ **PowerShell Script Analysis**: PSScriptAnalyzer warnings and errors
- ✅ **Syntax Errors**: Parsing issues, missing brackets, unmatched quotes
- ✅ **Best Practice Violations**: Code quality, security, performance issues
- ✅ **Variable Conflicts**: Automatic variables like `$error`, `$input`, `$host`
- ✅ **Function Standards**: Approved verbs, parameter validation, error handling
- ✅ **Security Concerns**: Execution policies, credential handling, unsafe operations

#### **MANDATORY Tools Usage**
```powershell
# REQUIRED: Check for errors before ANY changes
get_errors -filePaths ["path/to/file.ps1"]

# REQUIRED: After each significant change  
get_errors -filePaths ["path/to/modified/file.ps1"]

# REQUIRED: Final validation before completion
get_errors -filePaths ["all", "modified", "files.ps1"]
```

#### **Zero-Tolerance Policy**
- 🚫 **NO code changes are complete until ALL diagnostics are resolved**
- 🚫 **NO "TODO: fix later" - fix immediately**  
- 🚫 **NO ignoring warnings - address or document why they're acceptable**
- 🚫 **NO completion without final diagnostic verification**

#### **Diagnostic Panel Access (For Reference)**
- **Primary**: Use `get_errors` tool (automated)
- **Manual**: View → Problems (Ctrl+Shift+M) 
- **Panel**: Check bottom panel's "Problems" tab

#### **Resolution Standards**
- **Errors**: MUST be fixed immediately (zero tolerance)
- **Warnings**: MUST be addressed or explicitly justified
- **Information**: Should be reviewed and improved when possible
- **Hints**: Consider implementing for better code quality

### **Code Quality Enforcement (AUTOMATIC)**
Every code change MUST include:

#### **1. PSScriptAnalyzer Compliance**
- ✅ Use approved PowerShell verbs only
- ✅ Proper parameter validation and types
- ✅ Comprehensive error handling with try/catch
- ✅ Avoid automatic variables (`$error` → `$errorOutput`)
- ✅ Function naming: PascalCase with approved verbs
- ✅ Variable naming: Descriptive, avoiding conflicts

#### **2. Security Standards**
- ✅ Safe execution policy handling
- ✅ Credential protection (no plain text passwords)
- ✅ Input validation and sanitization
- ✅ Administrator privilege verification
- ✅ Safe file operations with error handling

#### **3. Performance Standards**  
- ✅ Efficient loops and conditionals
- ✅ Proper resource disposal
- ✅ Timeout handling for external processes
- ✅ Memory-conscious operations
- ✅ Background process management

### **WORKFLOW ENFORCEMENT**

#### **Every Code Edit Session MUST Follow This Pattern:**
```
1. 🔍 PRE-CHECK: get_errors on target files
2. ✏️ EDIT: Make code changes  
3. 🔍 MID-CHECK: get_errors on modified files
4. 🔧 FIX: Resolve any new issues immediately
5. 🔍 FINAL-CHECK: get_errors on all modified files
6. ✅ COMPLETE: Only when zero errors/warnings remain
```

#### **Completion Criteria (ALL REQUIRED)**
- [ ] `get_errors` returns zero errors on all modified files
- [ ] All warnings addressed or explicitly justified  
- [ ] PSScriptAnalyzer compliance verified
- [ ] Code follows project formatting conventions
- [ ] Security standards met
- [ ] Performance considerations addressed

#### **Documentation of Fixes**
When resolving diagnostics, document:
- **What was the issue**: Specific error/warning message
- **Why it occurred**: Root cause analysis
- **How it was fixed**: Specific changes made
- **Prevention**: How to avoid similar issues

### **Examples of Automatic Diagnostic Checking**

#### **✅ CORRECT Workflow:**
```
Agent: "I need to modify the Remove-Bloatware function"
1. get_errors -filePaths ["script.ps1"]  # PRE-CHECK
2. [Makes code changes]
3. get_errors -filePaths ["script.ps1"]  # POST-CHECK  
4. [Resolves any new issues]
5. get_errors -filePaths ["script.ps1"]  # FINAL-CHECK
6. "Changes complete - zero diagnostics remaining"
```

#### **❌ INCORRECT Workflow:**
```
Agent: "I'll modify the function and check later"
[Makes changes without diagnostic checking]
"Changes complete" # ❌ NO - Must check diagnostics first
```

## Best Practices (WITH MANDATORY DIAGNOSTICS)

### **🚨 PRIMARY RULE: DIAGNOSTICS FIRST**
- **AUTOMATIC CHECKING**: Every code change REQUIRES `get_errors` verification
- **ZERO TOLERANCE**: No completion without resolving ALL diagnostics  
- **IMMEDIATE FIXES**: Address issues as they appear, not later
- **COMPREHENSIVE VALIDATION**: Check all modified files before declaring completion

### **Development Workflow Standards**
- **Quality First**: MANDATORY VSCode Problems/Diagnostics checking via `get_errors` tool
- Always start with `script.bat` for full automation.
- Review `README.md` for config options and usage.
- Check `maintenance.log` for clean, timestamped operational logs.
- Review `maintenance_report.txt` for summary and `inventory.json` for detailed system state.
- Use temp list files for debugging bloatware/essential app operations.
- Leverage PowerShell 7.5.2 features while maintaining backward compatibility.
- Progress bars provide user feedback without affecting log file quality.

### **Code Quality Requirements (ENFORCED)**
- **Code Validation**: MANDATORY PSScriptAnalyzer compliance via `get_errors` tool
- **Error Handling**: Implement comprehensive try/catch blocks with meaningful error messages
- **Performance**: Use sequential processing for external commands to avoid hanging issues
- **Security**: Follow security best practices with automatic validation
- **Documentation**: Comment complex logic and provide function documentation

### **Diagnostic Integration Examples**
```powershell
# REQUIRED before any PowerShell editing:
get_errors -filePaths ["c:\\path\\to\\script.ps1"]

# REQUIRED after making changes:
get_errors -filePaths ["c:\\path\\to\\script.ps1"]

# REQUIRED before completing work:
get_errors -filePaths ["all_modified_files.ps1"]
```

### **Success Criteria for Code Changes**
1. ✅ All syntax errors resolved (`get_errors` returns clean)
2. ✅ All PSScriptAnalyzer warnings addressed
3. ✅ Security issues resolved or documented  
4. ✅ Performance optimizations applied
5. ✅ Code follows project formatting conventions
6. ✅ Final `get_errors` check passes with zero issues

---

If any section is unclear or missing, please provide feedback to improve these instructions for future AI agents.
