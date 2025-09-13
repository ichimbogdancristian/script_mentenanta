## 📈 Function Call Map (2025 Edition)

Below is a detailed map of all major functions in `script.ps1` and how they are called or referenced within the project. This helps with maintainability, debugging, and onboarding new contributors.

### 🗺️ Function Call Relationships

```
script.ps1
│
├─ Main Execution Flow
│   ├─ Use-AllScriptTasks
│   │   └─ (Iterates $global:ScriptTasks array)
│   │       └─ Each Task: Calls its Function (e.g. RemoveBloatware, InstallEssentialApps, etc.)
│   ├─ Write-Log, Write-ActionLog, Write-CommandLog, Write-TaskProgress, Write-ActionProgress (used throughout)
│   ├─ Write-TempListsSummary
│   └─ Write-UnifiedMaintenanceReport
│
├─ RemoveBloatware
│   ├─ Get-RegistryUninstallBloatware
│   ├─ Get-AppxPackageCompatible
│   ├─ Remove-AppxPackageCompatible
│   ├─ Get-AppxProvisionedPackageCompatible
│   ├─ Remove-AppxProvisionedPackageCompatible
│   ├─ Get-WingetBloatware
│   ├─ Get-ChocolateyBloatware
│   ├─ Get-RegistryBloatware
│   ├─ Get-BrowserExtensionsBloatware
│   ├─ Get-ContextMenuBloatware
│   ├─ Get-StartupProgramsBloatware
│   ├─ Get-ProvisionedAppxBloatware
│   ├─ Remove-AppsByPattern
│   └─ Compare-InstallationDiff
│
├─ InstallEssentialApps
│   ├─ Install-AppsByCategory
│   ├─ Invoke-PackageManagerCommand
│   ├─ Test-CommandAvailable
│   └─ Find-AppInstallations
│
├─ Install-WindowsUpdatesCompatible
│   ├─ Invoke-WindowsPowerShellCommand
│   └─ Start-ProgressTrackedOperation
│
├─ Disable-Telemetry
│   └─ Set-RegistryValueSafely
│
├─ Protect-SystemRestore
│   └─ Clear-OldRestorePoints
│
├─ System Inventory/Reporting
│   ├─ Get-StandardizedAppInventory
│   ├─ Get-ExtensiveSystemInventory
│   ├─ Get-OptimizedSystemInventory
│   └─ Write-UnifiedMaintenanceReport
│
├─ Utility Functions (used throughout)
│   ├─ Test-CommandAvailable
│   ├─ Compare-InstallationDiff
│   ├─ Invoke-PackageManagerCommand
│   ├─ Start-ProgressTrackedOperation
│   ├─ Find-AppInstallations
│   ├─ Remove-AppsByPattern
│   └─ Install-AppsByCategory
│
├─ Logging/Progress
│   ├─ Write-Log
│   ├─ Write-ActionLog
│   ├─ Write-CommandLog
│   ├─ Write-TaskProgress
│   └─ Write-ActionProgress
│
├─ Reporting
│   ├─ Write-TempListsSummary
│   └─ Write-UnifiedMaintenanceReport
│
└─ Other Maintenance/Helper Functions
  ├─ Clear-TempFiles
  ├─ Start-DefenderFullScan
  ├─ Enable-AppBrowserControl
  ├─ Disable-SpotlightMeetNowNewsLocation
  ├─ Optimize-TaskbarAndDesktopUI
  └─ etc.
```

**Legend:**
- Functions indented under another are called by that parent function.
- Utility and logging functions are used throughout the script by many features.
- The `$global:ScriptTasks` array is the main entry point for all core maintenance tasks.

For a full list of functions and their documentation, see the rest of this file.
## Project Structure & Refactoring (2025 Edition)

### Key Updates (2025)
- **Code Defragmentation Completed**: Implemented modular architecture with reusable utility functions
- **Section 1.5 Added**: Centralized configuration and constants management
- **Reusable Utilities**: 8+ new utility functions for common patterns (diff processing, package management, app detection)
- **Categorized App Lists**: Organized bloatware and essential apps into logical categories for better maintainability
- **Standardized Package Management**: Unified wrapper functions for Winget/Chocolatey operations with timeout protection
- **Universal Path Portability**: Complete location-agnostic architecture for running from any directory/user/computer
- **Orphaned Code Cleanup**: All legacy, unused, and fragmented code blocks systematically identified and resolved
- **Structural Integrity**: All IF/ELSE blocks properly closed, complete error handling throughout
- All logging now uses robust timestamping (LOG_TIMESTAMP)
- script.bat: Only handles environment, dependencies, repo update, and launching
- script.ps1: Only handles maintenance, reporting, and analytics with enhanced modular architecture
- No redundant admin, version, or dependency checks in script.ps1
- All status messages are current and relevant; no legacy or comparison messages



# Copilot Instructions for Windows Maintenance Automation Project

## Project Architecture (2025 Edition)

### 🏗️ **Two-Tier Architecture Overview**
This project implements a **launcher → orchestrator** architecture with clear separation of concerns:

#### **🚀 Tier 1: Environment Launcher (script.bat)**
- **Responsibility**: Environment preparation, dependency management, system validation
- **Key Functions**: Admin elevation, dependency installation, repository updates, scheduled tasks
- **Dependencies Handled**: Winget, PowerShell 7, Chocolatey, NuGet, PSWindowsUpdate, PowerShell Gallery
- **Validations Performed**: Windows 10/11 compatibility, PowerShell availability, administrator privileges
- **Output**: Launches script.ps1 in fully prepared environment

#### **⚙️ Tier 2: Maintenance Orchestrator (script.ps1)**
- **Responsibility**: System maintenance execution, task coordination, reporting
- **Key Functions**: Bloatware removal, essential apps, updates, cleanup, security hardening
- **Architecture**: Task-based modular design using `$global:ScriptTasks` array
- **Assumptions**: All dependencies pre-installed, admin privileges guaranteed, environment validated
- **Output**: Comprehensive maintenance reports and system improvements

### 📂 **File Structure & Responsibilities**
```
script_mentenanta/
├── script.bat                    # 🚀 LAUNCHER: Environment & Dependencies
├── script.ps1                    # ⚙️ ORCHESTRATOR: Maintenance Execution
├── README.md                     # 📖 User Documentation
├── .github/copilot-instructions.md # 🤖 AI Development Guidelines
├── maintenance.log               # 📝 Runtime Execution Log
├── maintenance_report.txt        # 📊 Comprehensive Results Report
├── config.json                   # ⚙️ Optional User Configuration
├── inventory.json                # 📋 System Analysis Export
└── temp_files/                   # 📁 Analysis & Processing Files
    ├── bloatware.json            # 🗑️ Bloatware Detection Results
    └── essential_apps.json       # 📦 Essential Apps Analysis
```

## Critical Architecture Principles

### 🚫 **WHAT script.ps1 SHOULD NOT DO** 
Since these are handled by script.bat launcher:
- ❌ **NO administrator privilege checks** (guaranteed by launcher)
- ❌ **NO PowerShell version validation** (PS7+ guaranteed by launcher)  
- ❌ **NO Windows version compatibility checks** (validated by launcher)
- ❌ **NO dependency installation attempts** (all dependencies pre-installed)
- ❌ **NO package manager installation** (Winget/Chocolatey guaranteed available)
- ❌ **NO module installation logic** (PSWindowsUpdate/NuGet pre-installed)
- ❌ **NO scheduled task management** (handled by launcher)
- ❌ **NO repository update logic** (latest version guaranteed by launcher)

### ✅ **WHAT script.ps1 SHOULD DO**
Focus purely on maintenance orchestration:
- ✅ **Graceful degradation** if dependencies somehow missing
- ✅ **Availability detection** for fallback strategies
- ✅ **Core maintenance tasks** (bloatware, apps, updates, cleanup)
- ✅ **Task coordination** via `$global:ScriptTasks` architecture
- ✅ **Comprehensive reporting** and analytics
- ✅ **Performance optimization** using PowerShell 7+ features

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
- **Indentation**: 4 spaces for PowerShell, tabs for batch files.
- **Function Names**: PascalCase for all PowerShell functions (e.g., `Install-EssentialApps`).
- **Comments**: Standardized function header block before each function.
- **Function Documentation**: All function documentation should be placed BEFORE the function declaration, not inside the function.
- **Comment Format**:
  ```powershell
  # ================================================================
  # Function: FunctionName
  # ================================================================
  # Purpose: Clear description of what the function does
  # Environment: Required environment (Windows version, privileges, etc.)
  # Performance: Performance characteristics and optimization notes
  # Dependencies: Required dependencies, external tools, or configurations
  # Logic: Brief explanation of the function's internal logic/algorithm
  # Features: Special features or capabilities
  # ================================================================
  function FunctionName {
      # Function code here
  }
  ```
- **Logging**: Separated console progress from file logging with progress bars in console and clean timestamped entries in log files.
- **Reports**: Comprehensive unified reports in `maintenance_report.txt` with system info, execution metrics, and categorized actions.
- **Temp Files**: Standardized JSON format for bloatware and essential app operations.

## 📋 Structured Code Organization Standards (MANDATORY)

### **Code Block Architecture (ENFORCED)**
The PowerShell script (`script.ps1`) MUST be organized into clearly defined, logical sections with specific purposes. This structure enhances maintainability, readability, debugging, and professional development standards.

#### **🏗️ MANDATORY Section Structure:**

```powershell
# ===============================
# SECTION 1: SCRIPT HEADER & METADATA  
# ===============================
# - Script documentation and purpose
# - PowerShell requirements (#Requires statements)
# - Using namespace declarations
# - Global configuration definitions
# - Task array definitions ($global:ScriptTasks)

# ===============================
# SECTION 1.5: CONFIGURATION & CONSTANTS
# ===============================
# - Centralized app lists (categorized bloatware and essential apps)
# - System settings and timeouts ($global:SystemSettings)
# - Package manager definitions ($global:PackageManagers)
# - Path configurations and default values
# - Organized into logical categories for maintainability

# ===============================
# SECTION 2: CORE INFRASTRUCTURE
# ===============================
# - Compatibility functions (Invoke-WindowsPowerShellCommand, etc.)
# - Logging system (Write-Log, Write-LogFile, Write-ConsoleMessage)
# - Progress tracking (Write-TaskProgress)
# - Task coordination (Invoke-Task, Use-AllScriptTasks)
# - Error handling utilities

# ===============================
# SECTION 3: SYSTEM UTILITIES
# ===============================
# - REUSABLE UTILITY FUNCTIONS (new defragmented utilities):
#   * Test-CommandAvailable (command detection)
#   * Compare-InstallationDiff (generic diff-based comparison)
#   * Get-StandardizedAppInventory (unified app inventory)
#   * Invoke-PackageManagerCommand (package manager wrapper)
#   * Start-ProgressTrackedOperation (progress tracking template)
#   * Find-AppInstallations (universal app detection)
#   * Remove-AppsByPattern (batch app removal)
#   * Install-AppsByCategory (category-based installation)
# - System inventory functions (Get-ExtensiveSystemInventory)
# - App detection utilities (Test-AppInstalled, Test-EnhancedAppInstallation)
# - System compatibility functions (AppX, Windows Updates, etc.)

# ===============================
# SECTION 4: BLOATWARE MANAGEMENT
# ===============================
# - Remove-Bloatware (main function)
# - Bloatware detection and removal utilities
# - Bloatware categories and classification logic
# - Supporting bloatware functions

# ===============================
# SECTION 5: ESSENTIAL APPS MANAGEMENT
# ===============================
# - Install-EssentialApps (main function)
# - Test-EnhancedAppInstallation
# - Invoke-EnhancedAppInstallation
# - Optimize-OfficeInstallation
# - Essential apps categories and installation logic

# ===============================
# SECTION 6: SYSTEM MAINTENANCE TASKS
# ===============================
# - Windows Updates (Install-WindowsUpdatesCompatible)
# - System Restore (Enable-ComputerRestoreCompatible, Checkpoint-ComputerCompatible)
# - Telemetry/Privacy (Disable-Telemetry)
# - Temp cleanup and disk maintenance functions

# ===============================
# SECTION 7: REPORTING & ANALYTICS
# ===============================
# - Write-UnifiedMaintenanceReport (comprehensive reporting)
# - Write-TempListsSummary (temp files analysis)
# - Performance tracking functions
# - Report generation utilities and analytics

# ===============================
# SECTION 8: SCRIPT EXECUTION & INITIALIZATION
# ===============================
# - Configuration loading and validation
# - Global variables initialization
# - Main execution logic and task orchestration
# - Cleanup and finalization processes
```

#### **🔧 Enhanced Reusable Architecture (2025)**

**New Defragmented Utilities provide:**
- **Compare-InstallationDiff**: Generic diff-based comparison for app installations with standardized processing logic
- **Get-StandardizedAppInventory**: Unified app inventory collection across multiple sources (AppX, Winget, Chocolatey)
- **Invoke-PackageManagerCommand**: Unified package manager command wrapper with timeout protection and error handling
- **Start-ProgressTrackedOperation**: Standardized progress tracking wrapper for long-running operations
- **Find-AppInstallations**: Universal app detection across multiple sources with pattern matching
- **Remove-AppsByPattern**: Batch app removal with pattern matching and safety checks
- **Install-AppsByCategory**: Category-based app installation with conflict resolution

**Centralized Configuration System:**
- **$global:AppCategories**: Categorized bloatware lists (OEMBloatware, GamingSocial, MicrosoftBloatware, XboxGaming, SecurityBloatware)
- **$global:EssentialCategories**: Categorized essential apps (WebBrowsers, DocumentTools, FileManagers, SystemTools, Communication)
- **$global:SystemSettings**: Centralized timeouts, paths, and performance settings
- **$global:PackageManagers**: Standardized package manager command definitions

# ===============================
# SECTION 7: REPORTING & ANALYTICS
# ===============================
# - Write-TempListsSummary
# - Write-UnifiedMaintenanceReport
# - Performance tracking functions
# - Report generation utilities
# - Analytics and metrics collection

# ===============================
# SECTION 8: SCRIPT EXECUTION & INITIALIZATION
# ===============================
# - Configuration loading and validation
# - Global variables initialization
# - Main execution logic and task orchestration
# - Cleanup and finalization processes
```

#### **🔧 Code Organization Enforcement Rules:**

1. **Logical Grouping**: All related functions MUST be grouped in their appropriate section
2. **Clear Section Headers**: Each section MUST have a standardized header with description
3. **Function Proximity**: Supporting functions MUST be placed immediately after their main function
4. **No Function Scatter**: Functions belonging to the same feature MUST NOT be scattered across the file
5. **Section Boundaries**: Clear separation between sections with standardized dividers
6. **Consistent Structure**: All AI agents MUST maintain this structure when making changes

#### **📍 Section Placement Guidelines:**

- **Infrastructure Functions**: Place in Section 2 (logging, progress, task coordination)
- **Utility Functions**: Place in Section 3 (inventory, package management, detection)
- **Feature-Specific Functions**: Place in appropriate feature section (4, 5, or 6)
- **Helper Functions**: Place immediately after the main function they support
- **Reporting Functions**: Place in Section 7 (reports, analytics, metrics)


#### **�️ Control Flow Preservation Rule (NEW):**

**Before removing any `if` or `try` statements, the agent MUST:**
1. **Analyze the intended logic and context of the block.**
2. **Attempt to restore or complete the block (e.g., add missing `catch`/`finally` for `try`, or close/open `if` as needed).**
3. **Preserve the original error handling and control flow whenever possible.**
4. **Only remove a block if it is truly orphaned, irrecoverable, and cannot be restored to meaningful logic.**
5. **Document the reasoning for any removal of such blocks.**

This applies to all structural/diagnostic fixes and is MANDATORY for all code changes.

### **Benefits of Structured Organization:**
✅ **Enhanced Maintainability**: Easy to locate and update related functionality  
✅ **Improved Debugging**: Related code co-located for efficient troubleshooting  
✅ **Professional Standards**: Industry-standard code organization  
✅ **Better Collaboration**: Clear structure for multiple developers  
✅ **Reduced Errors**: Logical grouping prevents function scatter and confusion  
✅ **Faster Development**: Quick navigation to relevant sections  

## Environment of Execution (Launcher → Orchestrator Architecture)

### 🚀 **script.bat Environment (Launcher Tier)**
- **OS:** Windows 10/11 (x64, x86, ARM64 supported)
- **Privileges:** Automatic administrator detection and elevation
- **Dependencies:** Handles all dependency installation and validation
- **Repository:** Downloads latest version from GitHub before each execution
- **Scheduled Tasks:** Creates and manages monthly maintenance and post-restart tasks
- **Validation:** Windows version compatibility, PowerShell availability
- **Output:** Launches script.ps1 in fully prepared environment

### ⚙️ **script.ps1 Environment (Orchestrator Tier)**
- **PowerShell:** 7.5.2+ native mode (guaranteed by launcher)
- **Privileges:** Administrator access (guaranteed by launcher)
- **Dependencies:** Pre-installed and validated (Winget, Chocolatey, NuGet, PSWindowsUpdate, Appx)
- **Architecture:** Task-based modular design using `$global:ScriptTasks` array
- **Execution:** Pure maintenance focus without environment setup overhead
- **Fallback:** Graceful degradation if dependencies somehow unavailable

### 🔄 **Simplified Execution Flow (Post-Refactoring)**
1. **🚀 script.bat** - Complete environment preparation
   - Auto-elevation and privilege validation
   - Windows 10/11 compatibility verification  
   - Dependency installation: Winget → PS7 → NuGet → PSWindowsUpdate → Chocolatey
   - Latest repository download and extraction
   - Scheduled task management
   - Launch script.ps1 with guaranteed environment

2. **⚙️ script.ps1** - Pure maintenance orchestration
   - ~~NO admin checks~~ (guaranteed by launcher)
   - ~~NO PowerShell version validation~~ (guaranteed by launcher)
   - ~~NO Windows version checks~~ (guaranteed by launcher)
   - ~~NO dependency installation~~ (handled by launcher)
   - ✅ Core maintenance tasks via `$global:ScriptTasks`
   - ✅ Graceful degradation for missing dependencies
   - ✅ Comprehensive reporting and analytics

### 📈 **Architecture Benefits**
- **⚡ Faster Startup**: No redundant validation in script.ps1
- **🛡️ Reliability**: Environment guaranteed before maintenance starts
- **🔧 Maintainability**: Clear separation between setup and execution
- **📊 Performance**: script.ps1 focuses purely on maintenance optimization
- **🔄 Scalability**: Easy to extend either tier independently

## Key Refactoring Improvements (2025 Edition)
- **🚫 Removed Redundant Validations**: Admin, PowerShell version, Windows version checks
- **🔧 Simplified Dependency Management**: Installation removed, availability detection retained
- **⚡ Enhanced Performance**: Reduced startup overhead in script.ps1
- **🏗️ Cleaner Architecture**: Launcher handles environment, orchestrator handles maintenance
- **📋 Better Documentation**: Clear responsibilities and architectural boundaries

## 🚨 MANDATORY VSCode Development and Quality Assurance Protocol

### **AUTOMATIC DIAGNOSTICS CHECKING (OBLIGATORY)**
**⚠️ CRITICAL REQUIREMENT**: Every AI agent MUST automatically check and resolve ALL VSCode diagnostics before completing any code changes. This is NOT optional.

### **⚠️ UNUSED VARIABLE RESTORATION PROTOCOL (MANDATORY)**
**🔧 CRITICAL REQUIREMENT**: AI agents MUST NEVER leave unused variables in the script. Instead, determine their intended meaning and restore their functionality.

#### **Unused Variable Detection and Restoration Process:**
1. **DETECTION**: Before any code changes, scan for variables that are assigned but never used
2. **ANALYSIS**: Determine the intended purpose of each unused variable based on:
   - Variable name and context
   - Surrounding code logic
   - Function purpose and expected outputs
   - Similar patterns elsewhere in the script
3. **RESTORATION**: Restore the variable's intended functionality by:
   - Adding proper logging/reporting usage
   - Including in return values or output objects
   - Using in conditional logic where appropriate
   - Adding to system inventory or reports
4. **DOCUMENTATION**: Document the restoration reasoning

#### **Common Unused Variable Patterns and Restorations:**
- **System Information Variables**: Add to reporting/logging functions
- **Timing Variables**: Use for performance metrics and logging  
- **Status Variables**: Include in return objects and conditional logic
- **Configuration Variables**: Apply to script behavior and report in logs
- **Calculation Results**: Use in reports, logs, or decision making
- **File/Path Variables**: Use for validation, reporting, or cleanup operations

#### **Examples of Variable Restoration:**
```powershell
# ❌ WRONG - Unused variable
$installationResult = Install-SomeApp
# Variable never used again

# ✅ CORRECT - Restored functionality
$installationResult = Install-SomeApp
Write-Log "Installation result: $installationResult" 'INFO'
return @{ Success = $installationResult.Success; Details = $installationResult }
```

#### **Pre-Code Change Protocol (MANDATORY STEPS)**
1. **BEFORE making ANY code changes**: Run `get_errors` tool on target files
2. **CONTEXT ANALYSIS**: When syntax/structural errors are found, examine the ENTIRE function or code block for complete understanding
3. **DURING code editing**: Monitor for new diagnostic issues  
4. **AFTER each code change**: Run `get_errors` tool again to verify no new issues
5. **BEFORE completion**: Final `get_errors` check on ALL modified files


#### **Enhanced Context Analysis for Complex Issues (MANDATORY)**
When diagnostic errors involve structural problems (missing brackets, orphaned code, function boundaries, or broken `if`/`try` blocks):

**🔍 REQUIRED CONTEXT INVESTIGATION:**
1. **Function and Block Scope Analysis**: Use `read_file` to examine the COMPLETE function and any enclosing `if`/`try`/loop blocks from start to end
2. **Structural Mapping**: Identify function boundaries, nested blocks, and proper indentation
3. **Orphaned Code Detection**: Look for code floating outside proper function/block contexts
4. **Control Flow Restoration**: Attempt to restore or complete any broken `if`/`try`/loop blocks before considering removal
5. **Variable Analysis**: Check for unused variables and understand their intended purpose before removal
6. **Cross-Reference Checking**: Verify that variables, parameters, and return values are properly scoped
7. **Integration Verification**: Ensure orphaned code segments are properly integrated or removed

#### **⚠️ Control Flow Preservation Rule (NEW):**

**Before removing any `if` or `try` statements, the agent MUST:**
1. **Analyze the intended logic and context of the block.**
2. **Attempt to restore or complete the block (e.g., add missing `catch`/`finally` for `try`, or close/open `if` as needed).**
3. **Preserve the original error handling and control flow whenever possible.**
4. **Only remove a block if it is truly orphaned, irrecoverable, and cannot be restored to meaningful logic.**
5. **Document the reasoning for any removal of such blocks.**

This applies to all structural/diagnostic fixes and is MANDATORY for all code changes.

**🔧 SYSTEMATIC RESOLUTION WORKFLOW:**

**Step 1: Structural Analysis and Restoration**
- Identify missing `catch`/`finally` blocks for orphaned `try` statements
- Complete broken `if`/`else`/`elseif` conditional logic
- Restore function boundaries and proper brace matching
- Fix control flow interruptions

**Step 2: Variable and Usage Analysis**  
- Identify unused variables and understand their original intent
- Check variable scoping and accessibility
- Restore proper variable integration or remove if truly redundant
- Ensure consistent indentation and code structure

**Step 3: Syntax and Technical Fixes**
- Address parsing errors and syntax issues
- Resolve type conflicts and parameter mismatches
- Apply PSScriptAnalyzer recommendations
- Final validation and testing

#### **🚨 CRITICAL: Orphaned Code Prevention Protocol (MANDATORY)**
**⚠️ ABSOLUTE REQUIREMENT**: AI agents MUST NEVER leave orphaned code blocks floating outside proper function/context boundaries.

**🔍 ORPHANED CODE DETECTION REQUIREMENTS:**
1. **Before Any Code Changes**: Scan for existing orphaned code using structural analysis
2. **During Replacements**: Verify that ALL code being replaced is properly scoped within functions
3. **After Modifications**: Ensure no code fragments are left floating outside function boundaries
4. **Before Completion**: Final scan for any orphaned code segments

**📋 ORPHANED CODE IDENTIFICATION:**
- **Function Fragments**: Code outside `function Name { ... }` boundaries
- **Floating Variables**: Variable assignments outside proper scopes
- **Incomplete Blocks**: Code missing opening or closing braces
- **Disconnected Logic**: Code that doesn't belong to any parent function or block
- **Remnant Code**: Left-over fragments from previous edits


**🔧 ORPHANED/BROKEN BLOCK RESOLUTION STEPS:**
1. **Identify Origin**: Determine what function or control block (`if`, `try`, etc.) the orphaned or broken code should belong to
2. **Restoration**: Attempt to restore the block by adding missing braces, `catch`/`finally`, or completing the logic
3. **Integration**: Move code into the appropriate context if possible
4. **Validation**: Verify the code makes sense in its new or restored location
5. **Testing**: Ensure integration doesn't break functionality
6. **Cleanup**: Only remove blocks if truly irrecoverable, and document the reason

**🚫 ZERO TOLERANCE POLICY:**
- **NO orphaned code is EVER acceptable**
- **ALL floating code MUST be properly integrated or removed**
- **EVERY replacement operation MUST account for context boundaries**
- **NO "temporary" orphaned code - fix immediately**

**📊 TOOLS FOR ORPHANED CODE DETECTION:**
```powershell
# Scan for function boundaries
grep_search -query "^function|^}$" -isRegexp true -includePattern "script.ps1"

# Look for floating code outside functions
grep_search -query "^\s*\$[^=]*=|^\s*[A-Z][a-zA-Z]+-" -isRegexp true -includePattern "script.ps1"

# Verify structural integrity
semantic_search -query "orphaned code floating outside functions incomplete blocks"
```

**📈 PREVENTION EXAMPLES:**
```powershell
# ❌ WRONG - Creates orphaned code
function MyFunction {
    # function content
}
$orphanedVariable = "value"  # ❌ This is orphaned!

# ✅ CORRECT - All code properly scoped
function MyFunction {
    $properVariable = "value"  # ✅ Properly scoped
    # function content
}
```

**📍 COMMON ORPHANED CODE SCENARIOS:**
1. **Incomplete Function Replacements**: Not including complete function boundaries
2. **Variable Assignments**: Variables defined outside any function scope
3. **Import/Configuration Code**: Module imports or settings outside proper initialization
4. **Error Handling**: Try/catch blocks not properly enclosed in functions
5. **Temporary Variables**: Variables created during edits but left floating

**📊 TOOLS FOR COMPREHENSIVE ANALYSIS:**
```powershell
# Get complete function context (not just error lines)
read_file -filePath "script.ps1" -startLine [function_start] -endLine [function_end]

# Search for function boundaries and structure
grep_search -query "function.*FunctionName" -includePattern "script.ps1"

# Find orphaned code blocks
grep_search -query "^\s*[{}]\s*$" -isRegexp true -includePattern "script.ps1"

# Check for structural completeness
semantic_search -query "function boundaries missing brackets orphaned code"
```

#### **MANDATORY Diagnostic Resolution Priority Order**

**Phase 1: Structural and Logic Issues (HIGHEST PRIORITY)**
1. **Try/Catch/Finally Blocks**: Analyze orphaned `try` statements and restore missing `catch`/`finally` blocks - understand the intended error handling logic and restore complete functionality
2. **If/Else/ElseIf Blocks**: Complete broken conditional logic by analyzing the intended flow and restoring missing `else`/`elseif` clauses with proper braces
3. **Function Boundaries**: Ensure all functions have proper opening/closing braces and complete structure
4. **Control Flow Restoration**: Understand and restore the intended program flow and error handling logic rather than removing incomplete blocks

**Phase 2: Code Quality and Usage Issues (MEDIUM PRIORITY)**
5. **Unused Variables**: Identify variables that are declared but never used, understand their intended purpose, and either integrate them properly or remove if truly redundant
6. **Variable Scope**: Ensure variables are properly scoped within functions and blocks
7. **Indentation**: Fix inconsistent indentation that affects readability and structure - ensure proper nesting and visual code organization

**Phase 3: Syntax and Technical Issues (LOWER PRIORITY)**
8. **Syntax Errors**: Address parsing errors, missing semicolons, incorrect operators
9. **Type Mismatches**: Resolve parameter type conflicts and casting issues
10. **Best Practices**: PSScriptAnalyzer warnings and code style improvements

#### **MANDATORY Tools Usage**
```powershell
# REQUIRED: Check for errors before ANY changes
get_errors -filePaths ["path/to/file.ps1"]

# REQUIRED: After each significant change  
get_errors -filePaths ["path/to/modified/file.ps1"]

# REQUIRED: Final validation before completion
get_errors -filePaths ["all", "modified", "files.ps1"]
```

#### **🔍 AUTOMATIC DIAGNOSTIC SEARCH AND RESOLUTION PROTOCOLS (MANDATORY)**

**⚠️ CRITICAL REQUIREMENT**: AI agents MUST automatically detect and resolve specific diagnostic patterns using proactive search strategies.

##### **1. PSScriptAnalyzer Violations - Automatic Detection and Resolution**

**🔧 PSAvoidDefaultValueSwitchParameter (AUTOMATIC FIX)**
- **Search Pattern**: `grep_search -query "\[switch\][^=]*= *\$true|\[switch\][^=]*= *\$false" -isRegexp true`
- **Detection**: Switch parameters with default boolean values
- **Auto-Resolution Process**:
  1. Remove default value from parameter declaration
  2. Add conditional logic inside function: `if (-not $PSBoundParameters.ContainsKey('ParameterName')) { $ParameterName = $defaultValue }`
  3. Preserve exact original behavior through internal logic
- **Validation**: Confirm `get_errors` shows no PSAvoidDefaultValueSwitchParameter warnings

**Example Auto-Fix Pattern**:
```powershell
# ❌ DETECTED VIOLATION
[switch]$UseCache = $true,
[switch]$IncludeDetection = $true

# ✅ AUTOMATIC RESOLUTION
[switch]$UseCache,
[switch]$IncludeDetection,
# Inside function body:
if (-not $PSBoundParameters.ContainsKey('UseCache')) { $UseCache = $true }
if (-not $PSBoundParameters.ContainsKey('IncludeDetection')) { $IncludeDetection = $true }
```

**🔧 Variable Delimiter Issues (AUTOMATIC FIX)**
- **Search Pattern**: `grep_search -query "\"[^\"]*\$[a-zA-Z_][a-zA-Z0-9_]*:[^$\"{}]*\"" -isRegexp true`
- **Detection**: Variables followed by colons in string interpolation without proper delimitation
- **Auto-Resolution Process**:
  1. Identify variable references like `$variable:` in double-quoted strings
  2. Replace with `${variable}:` for proper delimitation
  3. Verify parser can correctly interpret the string expansion
- **Validation**: Confirm no "Variable reference is not valid" PowerShell errors

**Example Auto-Fix Pattern**:
```powershell
# ❌ DETECTED VIOLATION
-Context "$Context - $source"

# ✅ AUTOMATIC RESOLUTION  
-Context "${Context} - ${source}"
```

##### **2. Proactive Diagnostic Scanning (MANDATORY WORKFLOW)**

**🔍 Pre-Code Change Scanning Protocol**:
```powershell
# REQUIRED: Comprehensive diagnostic scan before ANY changes
get_errors -filePaths ["target_file.ps1"]
grep_search -query "PSAvoidDefaultValueSwitchParameter|Variable reference is not valid" -isRegexp false
grep_search -query "\[switch\][^=]*= *\$" -isRegexp true  # Detect switch defaults
grep_search -query "\$[a-zA-Z_][a-zA-Z0-9_]*:" -isRegexp true  # Variable delimiter issues
```

**� Automatic Resolution Execution**:
1. **DETECT**: Run diagnostic search patterns automatically
2. **CLASSIFY**: Identify specific violation types (switch defaults, variable delimiters, etc.)
3. **RESOLVE**: Apply appropriate auto-fix patterns
4. **VERIFY**: Run `get_errors` to confirm resolution
5. **DOCUMENT**: Log what was fixed and why

##### **3. Common Diagnostic Patterns - Auto-Detection Matrix**

| Diagnostic Code | Search Pattern | Auto-Fix Strategy |
|----------------|---------------|-------------------|
| **PSAvoidDefaultValueSwitchParameter** | `\[switch\][^=]*= *\$` | Remove defaults, add internal conditionals |
| **Variable Delimiter Error** | `\$[a-zA-Z_][a-zA-Z0-9_]*:` in strings | Replace with `${variable}:` syntax |
| **PSAvoidUsingPositionalParameters** | Function calls with multiple unnamed params | Add parameter names explicitly |
| **PSUseDeclaredVarsMoreThanAssignments** | Variables assigned but never used | Restore functionality via logging/reporting |

**🚨 Mandatory Auto-Detection Triggers**:
- **BEFORE**: Every code modification session
- **DURING**: After each significant change 
- **AFTER**: Final validation before completion
- **ON ERROR**: Immediate automatic scanning when `get_errors` shows issues

##### **4. Advanced Diagnostic Resolution (CRITICAL PATTERNS)**

**🔍 Structural Issue Detection**:
```powershell
# Detect orphaned code outside functions
grep_search -query "^\s*\$[^=]*=|^\s*[A-Z][a-zA-Z]+-" -isRegexp true
# Detect incomplete blocks
grep_search -query "^\s*try\s*{|^\s*if\s*\(" -isRegexp true
# Detect function boundaries
grep_search -query "^function|^}$" -isRegexp true
```

**🛠️ Resolution Priorities (ENFORCED ORDER)**:
1. **Syntax Errors** (highest priority - blocks execution)
2. **PSScriptAnalyzer Violations** (code quality and best practices)
3. **Unused Variables** (restore functionality, never delete)
4. **Structural Issues** (orphaned code, incomplete blocks)
5. **Style Warnings** (consistency and maintainability)

#### **Zero-Tolerance Policy**
- �🚫 **NO code changes are complete until ALL diagnostics are resolved**
- 🚫 **NO "TODO: fix later" - fix immediately**  
- 🚫 **NO ignoring warnings - address or document why they're acceptable**
- 🚫 **NO completion without final diagnostic verification**
- 🚫 **NO unused variables allowed - ALL must have functionality restored**
- 🚫 **NO assumptions about "false positives" - verify and fix every unused variable diagnostic**
- 🚫 **NO manual diagnostic checking - use AUTOMATIC search patterns**
- 🚫 **NO EDITS WITHOUT POST-VERIFICATION**: MANDATORY `get_errors` check after EVERY code modification
- 🚫 **NO EXCEPTION TO POST-EDIT CHECKING**: Even single-line changes require diagnostics verification
- 🚫 **NO WORK COMPLETION**: Until post-edit `get_errors` returns completely clean results

#### **🔧 MANDATORY UNUSED VARIABLE RESOLUTION PROCESS**
When VSCode diagnostics show "The variable 'X' is assigned but never used":

**STEP 1: IMMEDIATE ANALYSIS (REQUIRED)**
- Determine variable's intended purpose from name and context
- Check surrounding code logic and function purpose
- Identify where the variable SHOULD be used

**STEP 2: FUNCTIONALITY RESTORATION (MANDATORY)**
- **Performance Variables** → Add to timing logs and metrics reporting
- **Status/Result Variables** → Include in return objects and conditional logic  
- **Configuration Variables** → Apply to script behavior and log in reports
- **System Information Variables** → Add to system inventory and reporting functions
- **Calculation Results** → Use in reports, logs, or decision-making logic
- **File/Path Variables** → Use for validation, cleanup, or reporting operations

**STEP 3: VERIFICATION (REQUIRED)**
- Run `get_errors` again to confirm variable is now used
- Ensure restored functionality makes logical sense
- Verify integration doesn't break existing code

**EXAMPLE RESTORATION PATTERNS:**
```powershell
# ❌ WRONG - Unused variable
$processResult = Start-Process "app.exe"
# Variable never referenced again

# ✅ CORRECT - Restored functionality  
$processResult = Start-Process "app.exe"
Write-Log "Process execution result: $($processResult.ExitCode)" 'INFO'
$global:SystemMetrics.ProcessExecutions += @{
    Name = "app.exe"
    ExitCode = $processResult.ExitCode
    Timestamp = Get-Date
}
return @{ Success = ($processResult.ExitCode -eq 0); Details = $processResult }
```

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
- 🚨 **NEVER use PowerShell automatic variables (e.g., `$error`, `$input`, `$host`, `$args`, `$PSItem`, `$null`, `$true`, `$false`, `$LASTEXITCODE`, `$PID`, `$PSVersionTable`, etc.) for custom logic, assignments, or error handling.**
- ✅ Avoid automatic variables (`$error` → `$errorOutput`)
- ✅ Function naming: PascalCase with approved verbs
- ✅ **Variable Delimitation**: When a variable inside a double-quoted string is immediately followed by a colon (`:`), it MUST be enclosed in curly braces (`${...}`). This prevents parser errors.
  - **❌ WRONG**: `"Log entry for $item: processed"`
  - **✅ CORRECT**: `"Log entry for ${item}: processed"`
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
2. � AUTO-DIAGNOSTIC-SCAN: Run automatic detection patterns for known violations
   - grep_search for PSAvoidDefaultValueSwitchParameter patterns
   - grep_search for variable delimiter issues  
   - grep_search for common PSScriptAnalyzer violations
3. �📋 CONTEXT-ANALYSIS: If errors found, read COMPLETE function/block contexts
4. 🗺️ STRUCTURAL-MAPPING: Map function boundaries, nested blocks, orphaned code
5. 🛡️ ORPHANED-CODE-SCAN: Identify any floating code outside proper contexts
6. 🔧 UNUSED-VARIABLE-SCAN: Identify all unused variables and plan restoration
7. 🤖 AUTO-FIX-EXECUTION: Apply automatic resolution patterns where applicable
8. ✏️ EDIT: Make code changes with full structural understanding
9. 🔍 MID-CHECK: get_errors on modified files
10. 🔧 FIX: Resolve any new issues immediately with context awareness
11. 🔨 UNUSED-VARIABLE-RESTORATION: Restore functionality for ALL unused variables
12. 🧹 ORPHANED-CODE-CLEANUP: Ensure no floating code fragments remain
13. 🔎 AUTO-VERIFY: Re-run diagnostic search patterns to confirm resolution
14. 🔍 FINAL-CHECK: get_errors on all modified files
15. 🚨 MANDATORY POST-EDIT DIAGNOSTICS VERIFICATION: MUST run get_errors after ANY edit completion
16. 🔄 ITERATIVE COMPLIANCE CHECK: If diagnostics show ANY issues, immediately return to step 9-15
17. ✅ COMPLETE: Only when zero errors/warnings remain AND no orphaned code AND no unused variables AND post-edit diagnostics are clean
```

#### **🚨 CRITICAL: Unused Variable Resolution is BLOCKING**
- **MANDATORY**: Every unused variable MUST have its functionality restored
- **NO EXCEPTIONS**: Variables cannot be deleted unless proven redundant
- **ANALYSIS REQUIRED**: Understand variable's intended purpose before action
- **INTEGRATION MANDATORY**: Variables must be integrated into logging, reporting, or conditional logic
- **VERIFICATION REQUIRED**: Confirm variable usage resolves diagnostic warnings

#### **Enhanced Contextual Analysis Workflow (MANDATORY FOR STRUCTURAL ISSUES)**
When dealing with complex syntax or structural errors:

**Phase 1 - Complete Context Gathering:**
```
1. Identify error location from get_errors
2. Use read_file to examine ENTIRE affected function (start to end)
3. Use grep_search to find function boundaries and related code
4. Use semantic_search for structural pattern analysis
```

**Phase 2 - Structural Understanding:**
```
1. Map complete function scope and nesting levels
2. Identify orphaned code segments outside proper contexts
3. Verify variable scoping and parameter flow
4. Check for incomplete blocks, missing brackets, or malformed structures
```

**Phase 3 - Comprehensive Resolution:**
```
1. Fix structural issues with complete context understanding
2. Integrate orphaned code properly or remove if redundant
3. Ensure proper indentation and function boundaries
4. Validate that all code is within appropriate scopes
5. Remove any floating code fragments outside function contexts
```

### **🚨 MANDATORY POST-EDIT DIAGNOSTICS VERIFICATION PROTOCOL**

**⚠️ ABSOLUTE REQUIREMENT**: After EVERY code edit, modification, or file change, AI agents MUST perform comprehensive diagnostics verification. This is NON-NEGOTIABLE.

#### **Required Post-Edit Verification Steps (BLOCKING):**

1. **🔍 IMMEDIATE POST-EDIT CHECK**: Run `get_errors` on all modified files within 30 seconds of completing any edit
2. **🚫 ZERO TOLERANCE POLICY**: ANY diagnostic error or warning MUST be resolved before declaring work complete
3. **🔄 ITERATIVE RESOLUTION**: If diagnostics show issues, immediately fix and re-check until clean
4. **📋 COMPREHENSIVE COVERAGE**: Check ALL files that were modified, not just the primary target file
5. **🚨 BLOCKING COMPLETION**: NO work session can be marked complete until diagnostics are 100% clean

#### **Mandatory Diagnostic Check Points:**
- **After each `replace_string_in_file` operation**: Immediate `get_errors` verification
- **After adding new functions**: Full file diagnostics check
- **After structural changes**: Complete syntax and logic validation
- **Before final completion**: Comprehensive `get_errors` on ALL modified files
- **During iterative fixes**: Continuous diagnostic monitoring

#### **Required Actions When Diagnostics Show Issues:**
1. **IMMEDIATE HALT**: Stop all other work and focus solely on diagnostic resolution
2. **ROOT CAUSE ANALYSIS**: Understand WHY the diagnostic appeared
3. **COMPREHENSIVE FIX**: Resolve the issue with proper context understanding
4. **RE-VERIFICATION**: Run `get_errors` again to confirm resolution
5. **ITERATIVE PROCESS**: Repeat until zero diagnostics remain

#### **Documentation Requirements:**
- **Log every diagnostic found**: Issue type, line number, root cause
- **Document resolution approach**: How each diagnostic was resolved
- **Verify resolution success**: Confirm `get_errors` shows clean results
- **Report completion status**: Only declare complete when diagnostics are clean

#### **Quality Metrics (MANDATORY TRACKING):**
- **Pre-Edit Diagnostic Count**: Number of issues before starting work
- **Post-Edit Diagnostic Count**: MUST be zero for completion
- **Resolution Time**: Time taken to resolve each diagnostic
- **Verification Attempts**: Number of `get_errors` calls needed

#### **Completion Criteria (ALL REQUIRED)**
- [ ] `get_errors` returns zero errors on all modified files
- [ ] All warnings addressed or explicitly justified  
- [ ] PSScriptAnalyzer compliance verified
- [ ] Code follows project formatting conventions
- [ ] Security standards met
- [ ] Performance considerations addressed
- [ ] **NO ORPHANED CODE**: All code fragments properly scoped within functions
- [ ] **CLEAN BOUNDARIES**: All function and block boundaries intact and complete
- [ ] **NO UNUSED VARIABLES**: All assigned variables have functionality restored and integrated
- [ ] **VARIABLE USAGE VERIFIED**: Confirmed through `get_errors` that all unused variable warnings resolved
- [ ] **FUNCTIONALITY RESTORED**: All variables integrated into logging, reporting, conditional logic, or return objects
- [ ] **POST-EDIT DIAGNOSTICS CLEAN**: MANDATORY `get_errors` verification completed after ALL edits
- [ ] **DIAGNOSTIC RESOLUTION COMPLETE**: All PSScriptAnalyzer warnings and errors resolved via iterative checking
- [ ] **ZERO TOLERANCE COMPLIANCE**: Final `get_errors` check returns completely clean results

#### **Documentation of Fixes**
When resolving diagnostics, document:
- **What was the issue**: Specific error/warning message
- **Why it occurred**: Root cause analysis
- **How it was fixed**: Specific changes made
- **Prevention**: How to avoid similar issues

#### **🔧 MANDATORY POST-EDIT VERIFICATION EXAMPLES**

**✅ CORRECT Post-Edit Workflow:**
```
Agent: "I need to modify a function"
1. get_errors -filePaths ["script.ps1"]  # PRE-CHECK
2. replace_string_in_file [makes changes]
3. get_errors -filePaths ["script.ps1"]  # IMMEDIATE POST-EDIT CHECK (MANDATORY)
4. [If issues found] Fix immediately and re-check
5. get_errors -filePaths ["script.ps1"]  # FINAL VERIFICATION (MANDATORY)
6. "Changes complete - zero diagnostics remaining"
```

**✅ CORRECT Workflow for Multiple Files:**
```
Agent: "I need to update several files"
1. get_errors -filePaths ["file1.ps1", "file2.ps1"]  # PRE-CHECK
2. replace_string_in_file [modifies file1.ps1]
3. get_errors -filePaths ["file1.ps1"]  # POST-EDIT CHECK FOR FILE1 (MANDATORY)
4. replace_string_in_file [modifies file2.ps1] 
5. get_errors -filePaths ["file2.ps1"]  # POST-EDIT CHECK FOR FILE2 (MANDATORY)
6. get_errors -filePaths ["file1.ps1", "file2.ps1"]  # FINAL ALL-FILES CHECK (MANDATORY)
7. "All changes complete - zero diagnostics on all files"
```

**❌ INCORRECT Workflow:**
```
Agent: "I'll modify the function and check later"
[Makes changes without diagnostic checking]
"Changes complete" # ❌ NO - Must check diagnostics immediately after each edit

Agent: "I made several changes, let me check at the end"
[Multiple edits without intermediate checks]
get_errors [...] # ❌ NO - Must check after EACH individual edit
```

### **Examples of Enhanced Diagnostic Checking with Automatic Resolution**

#### **✅ CORRECT Workflow with Automatic PSScriptAnalyzer Fixes:**
```
Agent: "I need to resolve PSAvoidDefaultValueSwitchParameter violations"
1. get_errors -filePaths ["script.ps1"]  # PRE-CHECK
2. grep_search -query "\[switch\][^=]*= *\$true|\[switch\][^=]*= *\$false" -isRegexp true  # AUTO-DETECT
3. [Identifies switch parameters with default values at lines 2800-2803]
4. [Automatically applies fix pattern: remove defaults, add internal conditionals]
5. get_errors -filePaths ["script.ps1"]  # VERIFY-FIX
6. "PSScriptAnalyzer violations resolved - zero diagnostics remaining"
```

#### **✅ CORRECT Workflow with Variable Delimiter Auto-Fix:**
```
Agent: "I need to fix variable reference delimiter issues"
1. get_errors -filePaths ["script.ps1"]  # PRE-CHECK
2. grep_search -query "\"[^\"]*\$[a-zA-Z_][a-zA-Z0-9_]*:[^$\"{}]*\"" -isRegexp true  # AUTO-DETECT
3. [Identifies variable delimiter issue: "$Context - $source" at line 3640]
4. [Automatically applies fix: replace with "${Context} - ${source}"]
5. get_errors -filePaths ["script.ps1"]  # VERIFY-FIX
6. "Variable delimiter issue resolved - zero diagnostics remaining"
```

#### **✅ CORRECT Workflow for Simple Changes:**
```
Agent: "I need to modify a variable assignment"
1. get_errors -filePaths ["script.ps1"]  # PRE-CHECK
2. [Makes simple code changes]
3. get_errors -filePaths ["script.ps1"]  # POST-CHECK  
4. [Resolves any new issues]
5. get_errors -filePaths ["script.ps1"]  # FINAL-CHECK
6. "Changes complete - zero diagnostics remaining"
```

#### **✅ CORRECT Workflow for Structural Issues:**
```
Agent: "I need to fix function boundary errors"
1. get_errors -filePaths ["script.ps1"]  # PRE-CHECK - identifies structural problems
2. read_file -filePath "script.ps1" -startLine [func_start] -endLine [func_end]  # CONTEXT
3. grep_search -query "function.*FunctionName" -includePattern "script.ps1"  # BOUNDARIES
4. semantic_search -query "orphaned code missing brackets function scope"  # PATTERNS
5. [Analyzes complete function structure and identifies orphaned code]
6. [Makes comprehensive structural fixes with full context understanding]
7. get_errors -filePaths ["script.ps1"]  # POST-CHECK
8. [Addresses any remaining issues with context awareness]
9. get_errors -filePaths ["script.ps1"]  # FINAL-CHECK
10. "Structural issues resolved - zero diagnostics remaining"
```

#### **❌ INCORRECT Workflow:**
```
Agent: "I'll modify the function and check later"
[Makes changes without diagnostic checking]
"Changes complete" # ❌ NO - Must check diagnostics first

Agent: "I see a syntax error at line 50"
[Fixes only line 50 without examining function context]
# ❌ NO - Must analyze complete function scope for structural issues
```

#### **🔧 REAL-WORLD EXAMPLE: Fixing Orphaned Code**
```
1. get_errors shows "Unexpected token '}'" at line 2437
2. read_file -startLine 2400 -endLine 2500  # Get broader context
3. grep_search -query "function.*Install.*Essential" # Find function boundaries  
4. Discovery: Code at 2437 is orphaned outside function scope
5. read_file -startLine 2200 -endLine 2450  # Read COMPLETE function
6. Integration: Move orphaned code into proper function context
7. get_errors confirms all structural issues resolved
```

#### **🧹 ORPHANED CODE CLEANUP EXAMPLE:**
```
BEFORE (❌ Orphaned Code):
function MyFunction {
    # function content
}
$orphanedVariable = "leftover"  # ❌ Floating outside function!
Write-Log "orphaned log" 'INFO'  # ❌ Disconnected code!

AFTER (✅ Properly Integrated):
function MyFunction {
    $properVariable = "integrated"  # ✅ Moved inside function
    Write-Log "integrated log" 'INFO'  # ✅ Now properly scoped
    # function content
}
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

### **🔍 Quick Reference: Automatic Diagnostic Resolution Commands**

#### **Mandatory Pre-Code Analysis (Run EVERY TIME):**
```powershell
# Check current diagnostics
get_errors -filePaths ["script.ps1"]

# Scan for switch parameter violations  
grep_search -query "\[switch\][^=]*= *\$true|\[switch\][^=]*= *\$false" -isRegexp true

# Scan for variable delimiter issues
grep_search -query "\"[^\"]*\$[a-zA-Z_][a-zA-Z0-9_]*:[^$\"{}]*\"" -isRegexp true

# Scan for unused variables pattern
grep_search -query "PSUseDeclaredVarsMoreThanAssignments|assigned but never used" -isRegexp false

# Scan for orphaned code
grep_search -query "^\s*\$[^=]*=|^\s*[A-Z][a-zA-Z]+-" -isRegexp true
```

#### **Common Auto-Fix Patterns:**
```powershell
# PSAvoidDefaultValueSwitchParameter Fix:
# BEFORE: [switch]$Param = $true
# AFTER:  [switch]$Param + internal: if (-not $PSBoundParameters.ContainsKey('Param')) { $Param = $true }

# Variable Delimiter Fix:  
# BEFORE: "$variable: text"
# AFTER:  "${variable}: text"

# Unused Variable Fix:
# BEFORE: $result = Get-Something  # Never used
# AFTER:  $result = Get-Something; Write-Log "Result: $result" 'INFO'
```

#### **Verification Commands (Run After Fixes):**
```powershell
# Verify all diagnostics resolved
get_errors -filePaths ["script.ps1"]

# Re-scan for any remaining patterns
grep_search -query "PSAvoidDefaultValueSwitchParameter|Variable reference is not valid" -isRegexp false
```

### **Success Criteria for Code Changes**
1. ✅ All syntax errors resolved (`get_errors` returns clean)
2. ✅ All PSScriptAnalyzer warnings addressed
3. ✅ Security issues resolved or documented  
4. ✅ Performance optimizations applied
5. ✅ Code follows project formatting conventions
6. ✅ **Structured organization maintained**: Functions placed in appropriate sections
7. ✅ **Section boundaries preserved**: Clear separation between logical code blocks
8. ✅ Final `get_errors` check passes with zero issues

### **Code Organization Compliance Checklist**
Before completing any code changes, verify:
- [ ] New functions placed in appropriate section (1-8)
- [ ] Related functions grouped together  
- [ ] Helper functions placed immediately after main functions
- [ ] Section headers maintained and updated as needed
- [ ] No function scatter across multiple unrelated sections
- [ ] Clear logical separation between sections maintained

## 🎯 **Key Defragmentation Improvements (2025 Edition)**

### **✅ Completed Architecture Enhancements:**

#### **1. 📂 Centralized Configuration (Section 1.5)**
- **Added comprehensive configuration section** with categorized app lists
- **Centralized settings and timeouts** in `$global:SystemSettings`
- **Package manager definitions** in `$global:PackageManagers`
- **Eliminated scattered configuration** throughout the script

#### **2. 🔄 Reusable Diff Processing Utilities**
- **`Compare-InstallationDiff`** - Generic diff-based comparison for app installations
- **`Get-StandardizedAppInventory`** - Unified app inventory collection across multiple sources
- **Standardized format** for inventory data with source identification

#### **3. 📦 Package Manager Wrapper Utilities**
- **`Invoke-PackageManagerCommand`** - Unified package manager command wrapper
- **Multi-manager support** (Winget, Chocolatey) with auto-detection
- **Timeout protection** and standardized error handling
- **Consistent result format** across all package operations

#### **4. 📊 Progress Tracking Templates**
- **`Start-ProgressTrackedOperation`** - Standardized progress tracking wrapper
- **Auto-cleanup progress bars** with error handling
- **Timing metrics** and operation identification
- **Consistent UX** across all long-running operations

#### **5. 🔍 App Detection and Management Utilities**
- **`Find-AppInstallations`** - Universal app detection with pattern matching
- **`Remove-AppsByPattern`** - Batch app removal with safety checks
- **`Install-AppsByCategory`** - Category-based app installation with conflict resolution
- **Multi-source search** capabilities with exact and pattern matching

### **📈 Quantified Benefits:**

#### **Code Reusability:**
- **+8 new reusable utility functions** extracted from common patterns
- **-200+ lines of duplicated code** eliminated through centralization
- **+90% consistency** in package manager interactions

#### **Maintainability:**
- **Centralized configuration** reduces update points from 15+ to 1
- **Standardized error handling** across all package operations
- **Consistent logging patterns** and progress tracking

#### **Performance:**
- **Cached command availability** checks reduce redundant PATH searches
- **Parallel app detection** across multiple sources
- **Optimized inventory collection** with standardized format

#### **Flexibility:**
- **Category-based app management** allows granular control
- **Configurable timeouts** and settings via centralized config
- **Multi-source app detection** with flexible pattern matching

### **🔧 Technical Compliance:**
- **Zero diagnostic errors** maintained throughout refactoring
- **Proper variable naming** (avoided automatic variables like `$args`)
- **Consistent code formatting** and documentation standards
- **Error handling** improvements with proper exception messages
- **Backward compatibility** preserved for existing function interfaces

### **🧹 Code Cleanup & Structural Integrity (September 2025)**

#### **✅ Completed Orphaned Code Cleanup:**
- **Fixed Missing Closing Blocks**: All incomplete IF/ELSE statements properly closed
- **Completed Self-Update Logic**: Added proper ELSE clauses for self-update mechanism  
- **Fixed Path Detection**: Completed missing exit conditions and error handling
- **Removed Orphaned Labels**: Cleaned up unused `:SKIP_SELF_UPDATE` label
- **Updated Legacy Comments**: Replaced outdated references with current descriptions

#### **✅ Structural Integrity Restored:**
- **All IF/ELSE blocks now properly closed**
- **All ERROR/EXIT paths properly handled** 
- **No orphaned code fragments remain**
- **Consistent error code progression** (EXIT /B 3,4,5,6,7)
- **Complete logical flow integrity** maintained

#### **📊 Code Quality Metrics Achieved:**
- **Syntax Errors**: 0 (all resolved)
- **Orphaned Code Blocks**: 0 (all integrated or removed)
- **Fragmented Logic**: 0 (all completed)
- **Legacy References**: 0 (all updated)
- **Unused Variables**: 0 (all variables serve reporting/system detection purposes)

---

If any section is unclear or missing, please provide feedback to improve these instructions for future AI agents.
