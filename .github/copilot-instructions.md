# Windows Maintenance Automation - Comprehensive AI Agent Guide

## Table of Contents
1. [Overview](#overview)
2. [Architecture Deep Dive](#architecture-deep-dive)
3. [Core Systems](#core-systems)
4. [Development Patterns](#development-patterns)
5. [Component Reference](#component-reference)
6. [Workflows & Procedures](#workflows--procedures)
7. [Testing & Debugging](#testing--debugging)
8. [Troubleshooting Guide](#troubleshooting-guide)
9. [Best Practices](#best-practices)
10. [Reference Tables](#reference-tables)

---

## Overview

### System Purpose
**Two-tier Windows maintenance automation** for Windows 10/11 systems providing:
- Automated bloatware removal (5 detection methods)
- Essential application installation (6 categories)
- Windows Update management with restart handling
- System health monitoring and repair
- Privacy/telemetry optimization
- Security hardening
- Unattended scheduled execution
- **Professional HTML reporting** with data aggregation and responsive design
- Multi-format output (HTML, JSON, Text logs)

### Design Philosophy
1. **Separation of Concerns**: Infrastructure (batch) vs maintenance logic (PowerShell)
2. **Defensive Programming**: Test-before-execute, graceful fallbacks, comprehensive error handling
3. **Minimal Logging Overhead**: Visual progress bars over verbose percentage logging
4. **Location Agnostic**: Works from any directory (network, removable, fixed drives)
5. **Self-Healing**: Auto-installs dependencies, downloads updates, handles missing components

### Execution Model
```
script.bat (Launcher)
├── Admin Privilege Elevation (dual-method verification)
├── Dependency Installation (Winget → PS7 → NuGet → PSGallery → Chocolatey)
├── Scheduled Task Creation (monthly at 1:00 AM)
├── Repository Update/Download (from GitHub)
├── Restart Detection (Windows Update-specific)
└── Launch script.ps1 (Orchestrator)
    ├── Environment Detection
    ├── System Inventory Collection
    ├── Task Array Execution (sequential with comprehensive logging)
    └── Final Restart Handling
```

---

## Architecture Deep Dive

### Two-Tier Design Rationale

#### Tier 1: Batch Launcher (`script.bat`)
**Responsibility**: System-level infrastructure and bootstrap operations

**Key Functions**:
- **Admin Elevation** (Lines 30-80): Dual-method verification using NET SESSION + PowerShell privilege check
- **Dependency Management** (Lines 200-550): Sequential installation of required tooling
- **Path Detection** (Lines 50-120): Universal path resolution for network/local/removable drives
- **Scheduled Task Setup** (Lines 350-450): Monthly automation with SYSTEM account
- **Repository Management** (Lines 700-850): GitHub download, extraction, self-update
- **Pre-Maintenance Restart** (Lines 450-550): Windows Update-triggered restarts only

**Why Batch?**: 
- Native Windows execution without PowerShell execution policy barriers
- Reliable admin elevation via Start-Process with RunAs verb
- Universal compatibility across all Windows versions (XP through 11)
- Simple scheduled task integration without script signing requirements

#### Tier 2: PowerShell Orchestrator (`script.ps1`)
**Responsibility**: Maintenance task execution with advanced logic

**Key Functions**:
- **Task Coordination** (Lines 250-550): Modular task array with sequential execution
- **Logging System** (Lines 114-180+): 3-tier logging with console/file dual output
- **Progress Tracking** (Lines 1400-1700): Minimal-log visual progress system
- **Bloatware Detection** (Lines 850-1200): Multi-source app discovery (5 methods)
- **Registry Operations** (Lines 2000-2200): Safe registry modification with fallbacks
- **Package Management** (Lines 2500-3000): Winget/Chocolatey abstraction layer
- **System Repair** (Lines 4000-4500): DISM/SFC health checks
- **Professional Report Generation** (Lines 9467-9930): HTML report with embedded CSS, responsive design, data aggregation

**Why PowerShell 7?**:
- Modern language features (using namespace, parallel processing, modern cmdlets)
- Comprehensive error handling (try/catch/finally with detailed exceptions)
- Native Windows API access (CIM/WMI, Registry, AppX, WMI classes)
- Rich object pipeline for complex data transformations
- Cross-platform compatibility (future Linux/macOS support)
- Superior performance with native implementations

### Task Coordination System

#### Task Array Architecture
Tasks are defined in `$global:ScriptTasks` array (lines 250-550 in script.ps1):

```powershell
$global:ScriptTasks = @(
    @{ 
        Name = 'SystemRestoreProtection'
        Function = { Protect-SystemRestore }
        Description = 'Enable System Restore and create pre-maintenance checkpoint'
    },
    @{ 
        Name = 'SystemInventory'
        Function = { Get-SystemInventory }
        Description = 'Collect comprehensive system information'
    },
    @{ 
        Name = 'RemoveBloatware'
        Function = { Remove-Bloatware }
        Description = 'Remove unwanted apps via AppX, DISM, Registry, Windows Capabilities'
    }
    # ... additional tasks
)
```

#### Execution Flow
```
Use-AllScriptTasks (Main Orchestrator)
│
├── Read $global:ScriptTasks array
├── For each task:
│   ├── Check $global:Config for skip flags
│   ├── Write-ActionLog (START)
│   ├── Invoke-Task
│   │   ├── Measure execution time
│   │   ├── Execute task.Function scriptblock
│   │   ├── Capture result/errors
│   │   └── Write-ActionLog (SUCCESS/FAILURE)
│   └── Store result in $global:TaskResults
└── Generate execution summary
```

#### Task Execution Context
Each task receives:
- **Global variables**: `$global:Config`, `$global:TempFolder`, `$global:SystemInventory`
- **Logging functions**: `Write-Log`, `Write-ActionLog`, `Write-CommandLog`
- **Progress functions**: `Write-TaskProgress`, `Write-ActionProgress`
- **Utilities**: `Test-CommandAvailable`, `Test-RegistryAccess`, `Invoke-LoggedCommand`

#### Task Result Tracking
Results stored in `$global:TaskResults`:
```powershell
$global:TaskResults['RemoveBloatware'] = @{
    Success = $true/$false
    Duration = 45.23  # seconds
    Started = DateTime
    Ended = DateTime
    Description = "Task description"
    Error = "Exception message if failed"
}
```

**Pattern**: All new maintenance features MUST be added as task entries, not standalone functions.

---

## Core Systems

### 1. Logging System (3-Tier Architecture)

#### Tier 1: `Write-Log` - Standard Logging
**Purpose**: Foundation logging function for all script output

**Signature**:
```powershell
Write-Log -Message "text" -Level 'INFO' -Component 'PS1'
```

**Log Levels**:
- `DEBUG`: Verbose diagnostic information
- `INFO`: Normal operational messages
- `WARN`: Warning conditions that don't prevent execution
- `ERROR`: Error conditions requiring attention
- `SUCCESS`: Successful completion indicators
- `PROGRESS`: Progress update markers
- `ACTION`: High-level action boundaries
- `COMMAND`: External command execution logs
- `VERBOSE`: Detailed execution traces

**Output Format**:
```
[HH:mm:ss] [LEVEL] [COMPONENT] Message text
```

**Dual Output**:
- Console: Color-coded based on level
- Log file: `maintenance.log` (inherited from `$env:SCRIPT_LOG_FILE`)

**Example**:
```powershell
Write-Log "Starting bloatware scan" 'INFO'
Write-Log "Registry access denied" 'WARN'
Write-Log "Task completed successfully" 'SUCCESS'
```

#### Tier 2: `Write-ActionLog` - Structured Action Tracking
**Purpose**: Track high-level operations with categorization and lifecycle status

**Signature**:
```powershell
Write-ActionLog -Action "Operation name" -Details "context" -Category "category" -Status 'START'|'SUCCESS'|'FAILURE'|'INFO'
```

**Categories**:
- `Task Orchestration`: Main task coordination
- `Task Execution`: Individual task operations
- `Task Management`: Task lifecycle management
- `Command Execution`: External process management
- `Package Management`: Winget/Chocolatey operations
- `Registry Operations`: Registry modifications
- `System Configuration`: System setting changes
- `Bloatware Detection`: App discovery operations
- `System Repair`: DISM/SFC operations

**Status Flow**:
```
START → execution → SUCCESS/FAILURE
```

**Example**:
```powershell
Write-ActionLog -Action "Installing applications" -Details "Processing 5 apps" -Category "Package Management" -Status 'START'
# ... execution ...
Write-ActionLog -Action "Applications installed" -Details "5/5 successful" -Category "Package Management" -Status 'SUCCESS'
```

#### Tier 3: `Write-CommandLog` - External Command Tracking
**Purpose**: Log external process execution with full command context

**Signature**:
```powershell
Write-CommandLog -Command "executable" -Arguments @('arg1', 'arg2') -Context "description" -Status 'START'|'SUCCESS'|'FAILURE'
```

**Captures**:
- Full command line
- Execution context
- Exit codes
- Timing information
- Success/failure status

**Example**:
```powershell
Write-CommandLog -Command 'winget' -Arguments @('install', 'Google.Chrome') -Context "Installing Chrome" -Status 'START'
$result = Start-Process winget -ArgumentList 'install', 'Google.Chrome' -Wait -PassThru
if ($result.ExitCode -eq 0) {
    Write-CommandLog -Command 'winget' -Arguments @('install', 'Google.Chrome') -Context "Chrome installed" -Status 'SUCCESS'
}
```

**Always use**: 
- `Write-ActionLog` for task boundaries and major operations
- `Write-CommandLog` for ALL external process invocations

---

## Development Patterns

### 2. Progress Tracking System (Minimal Logging Design)

#### Philosophy: Visual Over Verbose
**Core Principle**: Use progress bars for real-time feedback, log only meaningful state changes

**Anti-Pattern** ❌:
```powershell
# DON'T DO THIS - Pollutes logs
for ($i = 0; $i -lt 100; $i++) {
    Write-Log "Progress: $i%" 'INFO'  # Creates 100 log entries!
}
```

**Correct Pattern** ✅:
```powershell
# DO THIS - Clean visual feedback, minimal logging
Write-Log "Starting operation" 'INFO'  # Log start
for ($i = 0; $i -lt 100; $i++) {
    Write-Progress -Activity "Operation" -PercentComplete $i  # Visual only
}
Write-Log "Operation completed" 'SUCCESS'  # Log completion
```

#### `Write-TaskProgress` - Task-Level Progress
**Purpose**: High-level task progress with milestone logging only

**Signature**:
```powershell
Write-TaskProgress -Activity "Task name" -PercentComplete 0..100 -Status "Current status"
```

**Logging Behavior**:
- Logs at 0% (start)
- Shows visual progress bar for 1-99%
- Logs at 100% (completion)
- Auto-cleans progress bar on completion

**Example**:
```powershell
Write-TaskProgress -Activity "Scanning for bloatware" -PercentComplete 0 -Status "Starting scan"
# Visual progress bar shown
Write-TaskProgress -Activity "Scanning for bloatware" -PercentComplete 50 -Status "Processing registry"
# Visual progress bar updated, NO log entry
Write-TaskProgress -Activity "Scanning for bloatware" -PercentComplete 100 -Status "Scan complete"
# Logs completion and cleans up
```

#### `Write-ActionProgress` - Action-Level Progress
**Purpose**: Granular operation tracking with modular progress bars

**Signature**:
```powershell
Write-ActionProgress -ActionType "Installing|Removing|Updating|Scanning" `
                     -ItemName "item" `
                     -PercentComplete 0..100 `
                     -Status "status" `
                     -CurrentItem 1 `
                     -TotalItems 10 `
                     -Completed  # Switch to mark as done
```

**Features**:
- Unique progress bar per action type + item (parallel tracking)
- Auto-cleanup on completion
- Logs only start and finish
- Shows item counts (X/Y format)

**Example**:
```powershell
# Start installation
Write-ActionProgress -ActionType "Installing" -ItemName "Google Chrome" `
                     -PercentComplete 0 -CurrentItem 1 -TotalItems 5
# Progress updates (visual only, no logs)
Write-ActionProgress -ActionType "Installing" -ItemName "Google Chrome" `
                     -PercentComplete 50 -CurrentItem 1 -TotalItems 5
# Complete installation
Write-ActionProgress -ActionType "Installing" -ItemName "Google Chrome" `
                     -CurrentItem 1 -TotalItems 5 -Completed
```

#### `Write-CleanProgress` - Batch Operation Progress
**Purpose**: Clean progress for bulk operations with smart milestone logging

**Signature**:
```powershell
Write-CleanProgress -Activity "Operation" `
                    -CurrentItem "item name" `
                    -CurrentIndex 5 `
                    -TotalItems 100 `
                    -Status "Processing" `
                    -Completed  # Switch to finalize
```

**Smart Logging**:
- Logs at start (index 1)
- Logs every 10th item
- Logs at completion
- Visual progress bar for all updates

**Example**:
```powershell
$items = Get-ChildItem
$total = $items.Count
for ($i = 0; $i -lt $total; $i++) {
    Write-CleanProgress -Activity "Cleaning temp files" `
                        -CurrentItem $items[$i].Name `
                        -CurrentIndex ($i + 1) `
                        -TotalItems $total `
                        -Status "Removing"
}
Write-CleanProgress -Activity "Cleaning temp files" `
                    -CurrentItem "Complete" `
                    -CurrentIndex $total `
                    -TotalItems $total `
                    -Completed
```

#### `Format-ProgressBar` & `Write-VisualProgressBar` - High-Visibility Summaries
**Purpose**: Provide boxed, multi-line progress summaries with counts/success metrics without duplicating markup logic.

**Usage Rules**:
- `Format-ProgressBar` returns a hashtable containing the ASCII bar, percent complete, and descriptive summary. Do **not** reimplement bar math—call it wherever you need consistent visuals.
- `Write-VisualProgressBar` logs the formatted output with the purple box-drawing frame used throughout bloatware removal, essential app installs, and temp cleanup. Call it sparingly (start, end, every N items) to avoid log noise.

**Example**:
```powershell
if ($itemsProcessed -eq 1 -or $itemsProcessed -eq $totalItems -or $itemsProcessed % 5 -eq 0) {
    Write-VisualProgressBar -Current $itemsProcessed `
                            -Total $totalItems `
                            -Title "INSTALLING ESSENTIAL APPS" `
                            -Details "→ $($currentApp.Name)"
}
```

**Guidance**:
- Always pass integers for `-Current`/`-Total`; the helper handles percentage math internally.
- Provide a short `-Title` (uppercase verbs work well) and a concise `-Details` string (e.g., `→ AppName`).
- Reuse these helpers for any new iterative workflow so reports and consoles maintain a consistent visual language.

**Design Principle**: Visual feedback via progress bars, minimal log file pollution. Never log intermediate percentages.

### 3. Error Handling Strategy

#### Standard Pattern: Try-Catch with Action Logging
**All functions MUST follow this pattern**:

```powershell
function Do-Something {
    param([string]$Parameter)
    
    try {
        Write-ActionLog -Action "Starting operation" -Details $Parameter -Category "Category" -Status 'START'
        
        # Validate preconditions
        if (-not (Test-Precondition)) {
            throw "Precondition failed"
        }
        
        # Perform operation
        $result = Invoke-Operation -Param $Parameter
        
        # Validate result
        if (-not $result) {
            throw "Operation returned null"
        }
        
        Write-ActionLog -Action "Operation completed" -Details "Result: $result" -Category "Category" -Status 'SUCCESS'
        return $result
    }
    catch {
        Write-ActionLog -Action "Operation failed" -Details $_.Exception.Message -Category "Category" -Status 'FAILURE'
        Write-Log "Full error: $($_.Exception | Format-List * | Out-String)" 'ERROR'
        return $false
    }
}
```

#### Error Handling Levels

**Level 1: Non-Critical Warnings**
```powershell
# Operation can continue with degraded functionality
try {
    Enable-OptionalFeature -Name "Feature"
} catch {
    Write-Log "Optional feature not available: $_" 'WARN'
    # Continue without failing
}
```

**Level 2: Recoverable Errors with Fallback**
```powershell
# Try primary method, fall back to alternative
try {
    $result = Invoke-PrimaryMethod
} catch {
    Write-Log "Primary method failed, trying fallback: $_" 'WARN'
    try {
        $result = Invoke-FallbackMethod
    } catch {
        Write-Log "All methods failed: $_" 'ERROR'
        return $false
    }
}
```

**Level 3: Critical Errors**
```powershell
# Operation cannot proceed without this
try {
    $criticalResource = Get-CriticalResource
    if (-not $criticalResource) {
        throw "Critical resource unavailable"
    }
} catch {
    Write-ActionLog -Action "Critical failure" -Details $_.Exception.Message -Status 'FAILURE'
    Write-Log "Cannot continue: $_" 'ERROR'
    throw  # Re-throw to stop execution
}
```

#### External Command Error Handling
**Use `Invoke-LoggedCommand` for all external processes**:

```powershell
try {
    $process = Invoke-LoggedCommand -FilePath "winget.exe" `
                                     -ArgumentList @('install', 'AppID') `
                                     -Context "Installing application" `
                                     -TimeoutSeconds 300
    
    if ($process.ExitCode -ne 0) {
        Write-Log "Command failed with exit code: $($process.ExitCode)" 'ERROR'
        return $false
    }
} catch {
    Write-Log "Command execution exception: $_" 'ERROR'
    return $false
}
```

#### Graceful Degradation Pattern
**For optional features that may not be available**:

```powershell
# Check if module/feature is available
if (Get-Module -ListAvailable -Name 'PSWindowsUpdate') {
    try {
        Import-Module PSWindowsUpdate -Force
        Install-WindowsUpdate -AcceptAll
    } catch {
        Write-Log "Windows Update via PSWindowsUpdate failed: $_" 'WARN'
        # Fall back to native method
        Start-Process "ms-settings:windowsupdate" -ErrorAction SilentlyContinue
    }
} else {
    Write-Log "PSWindowsUpdate module not available, skipping enhanced update features" 'WARN'
    # Use basic update check instead
}
```

#### Error Context Enrichment
**Always provide context in error messages**:

```powershell
catch {
    $errorDetails = @{
        Message = $_.Exception.Message
        StackTrace = $_.ScriptStackTrace
        Line = $_.InvocationInfo.ScriptLineNumber
        Command = $_.InvocationInfo.MyCommand
        Category = $_.CategoryInfo.Category
    }
    
    Write-ActionLog -Action "Detailed error context" `
                    -Details ($errorDetails | ConvertTo-Json -Compress) `
                    -Status 'FAILURE'
}
```

---

## Component Reference

### 1. Bloatware Detection System (Multi-Source)

#### Overview
The bloatware detection system combines **5 independent detection methods** to ensure comprehensive coverage across different app installation types.

**Location**: Lines 850-1200 in script.ps1

#### Detection Methods

**Method 1: AppX Packages (Windows Store Apps)**
```powershell
# Detects UWP/Store apps installed for current user or all users
$appxPackages = Get-AppxPackage -AllUsers | Where-Object {
    $_.Name -in $BloatwarePatterns
}

# Also checks provisioned packages (pre-installed for new users)
$provisionedPackages = Get-AppxProvisionedPackage -Online | Where-Object {
    $_.DisplayName -in $BloatwarePatterns
}
```

**Use Cases**:
- Modern Microsoft Store apps (3DBuilder, Xbox, etc.)
- OEM pre-installed Store apps
- Gaming apps (Candy Crush, etc.)

**Removal Method**: `Remove-AppxPackage`, `Remove-AppxProvisionedPackage`

---

**Method 2: DISM Provisioned Packages**
```powershell
# Detects packages staged for installation on new user profiles
Get-AppxProvisionedPackage -Online | Where-Object {
    $_.DisplayName -match $BloatwarePattern
}
```

**Use Cases**:
- Apps that auto-install for new user accounts
- OEM provisioned software
- System-integrated bloatware

**Removal Method**: `Remove-AppxProvisionedPackage -Online`

---

**Method 3: Registry Uninstall Keys (Win32 Apps)**
```powershell
# Function: Get-RegistryUninstallBloatware
# Scans: HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall
#        HKLM:\SOFTWARE\WOW6432Node\...\Uninstall (32-bit on 64-bit)
```

**Registry Paths Checked**:
- `HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall` (64-bit apps)
- `HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall` (32-bit apps)
- `HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall` (per-user installs)

**Data Extracted**:
```powershell
@{
    DisplayName = "Application Name"
    DisplayVersion = "1.0.0"
    Publisher = "Company Name"
    UninstallString = "Path to uninstaller"
    InstallLocation = "C:\Program Files\..."
}
```

**Use Cases**:
- Traditional desktop applications
- OEM utility software
- Pre-installed antivirus trials
- Manufacturer tools (HP, Dell, Lenovo utilities)

**Removal Method**: Execute UninstallString or use package manager

---

**Method 4: Windows Capabilities**
```powershell
# Detects optional Windows features that can be removed
Get-WindowsCapability -Online | Where-Object {
    $_.Name -match $Pattern -and $_.State -eq 'Installed'
}
```

**Use Cases**:
- Windows Media Player
- Internet Explorer
- XPS Viewer
- Math Recognizer
- Optional handwriting features

**Removal Method**: `Remove-WindowsCapability -Online`

---

**Method 5: Package Manager Lists (Winget/Chocolatey)**
```powershell
# Cross-reference installed apps with package manager databases
winget list | Where-Object { $_.Id -in $BloatwareList }
choco list --local-only | Where-Object { $_.Name -in $BloatwareList }
```

**Use Cases**:
- Validation of detected bloatware
- Discovery of apps installed via package managers
- Version tracking and update management

**Removal Method**: `winget uninstall`, `choco uninstall`

---

#### Bloatware Categories

**Defined in** `$global:AppCategories`:

```powershell
$global:AppCategories = @{
    OEMBloatware       = @(
        'Acer.*', 'ASUS.*', 'Dell.*', 'HP.*', 'Lenovo.*'
        # Manufacturer-specific utilities and bloatware
    )
    GamingSocial       = @(
        'king.com.*', 'CandyCrush*', 'Facebook.*', 'Twitter.*'
        # Casual games and social media apps
    )
    MicrosoftBloatware = @(
        'Microsoft.3DBuilder', 'Microsoft.BingNews', 'Microsoft.OneConnect'
        # Microsoft's optional pre-installed apps
    )
    XboxGaming         = @(
        'Microsoft.Xbox*', 'Microsoft.GamingApp'
        # Xbox integration and gaming features
    )
    SecurityBloatware  = @(
        'McAfee.*', 'Norton.*', 'Avast.*', 'AVG.*'
        # Antivirus trials and security software
    )
}
```

#### Detection Workflow

```
Remove-Bloatware (Main Function)
│
├── Initialize Bloatware List (merge categories)
│   ├── Load $global:AppCategories
│   ├── Add $global:Config.CustomBloatwareList
│   └── Create unified detection patterns
│
├── Method 1: Scan AppX Packages
│   ├── Get-AppxPackage -AllUsers
│   ├── Match against patterns
│   └── Store results with source tag
│
├── Method 2: Scan DISM Provisioned
│   ├── Get-AppxProvisionedPackage -Online
│   ├── Match against patterns
│   └── Store results with source tag
│
├── Method 3: Scan Registry Keys
│   ├── Call Get-RegistryUninstallBloatware
│   ├── Scan both 32/64-bit registry
│   └── Store results with source tag
│
├── Method 4: Scan Windows Capabilities
│   ├── Get-WindowsCapability -Online
│   ├── Match against patterns
│   └── Store results with source tag
│
├── Method 5: Cross-Reference Package Managers
│   ├── winget list (if available)
│   ├── choco list (if available)
│   └── Validate detected apps
│
├── Deduplicate Results (merge by app name)
│
└── Remove Bloatware (by detection method)
    ├── Remove-AppxPackage (UWP apps)
    ├── Remove-AppxProvisionedPackage (provisioned)
    ├── Execute UninstallString (Win32)
    ├── Remove-WindowsCapability (features)
    └── Package manager uninstall (fallback)
```

#### Usage Patterns

**Pattern 1: Add Custom Bloatware**
```powershell
# In configuration section or before calling Remove-Bloatware
$global:Config.CustomBloatwareList += @(
    'CustomApp.Name',
    'AnotherApp.*',
    'Specific.Pattern'
)
```

**Pattern 2: Detect Specific App Type**
```powershell
# Detect only registry-based (Win32) bloatware
$win32Bloatware = Get-RegistryUninstallBloatware -BloatwarePatterns $patterns -Context "Custom Scan"
```

**Pattern 3: Safe Removal with Confirmation**
```powershell
# Get detected bloatware list
$detected = Get-DetectedBloatware

# Review before removal
$detected | Format-Table Name, Source, Version

# Remove with progress tracking
foreach ($app in $detected) {
    Write-ActionProgress -ActionType "Removing" -ItemName $app.Name -PercentComplete 0
    Remove-BloatwareApp -App $app
    Write-ActionProgress -ActionType "Removing" -ItemName $app.Name -Completed
}
```

#### Testing Bloatware Detection

```powershell
# Test detection without removal
function Test-BloatwareDetection {
    Write-Log "Testing bloatware detection (no removal)" 'INFO'
    
    # Method 1: AppX
    $appx = Get-AppxPackage -AllUsers | Where-Object { $_.Name -like '*Xbox*' }
    Write-Log "AppX found: $($appx.Count)" 'INFO'
    
    # Method 2: Registry
    $registry = Get-RegistryUninstallBloatware -BloatwarePatterns @('Dell', 'HP', 'Lenovo')
    Write-Log "Registry found: $($registry.Count)" 'INFO'
    
    # Method 3: Capabilities
    $caps = Get-WindowsCapability -Online | Where-Object { $_.State -eq 'Installed' }
    Write-Log "Capabilities found: $($caps.Count)" 'INFO'
}
```

### 2. Package Manager Abstraction Layer

#### Overview
Unified abstraction layer for Winget and Chocolatey with automatic fallback handling.

**Location**: `$global:PackageManagers` configuration (line ~580 in script.ps1)

#### Package Manager Definitions

```powershell
$global:PackageManagers = @{
    Winget     = @{
        Command       = 'winget.exe'
        InstallArgs   = @('install', '--id', '{0}', '--silent', '--accept-package-agreements', '--accept-source-agreements')
        UninstallArgs = @('uninstall', '--id', '{0}', '--silent')
        ListArgs      = @('list')
        SearchArgs    = @('search', '{0}')
        UpdateArgs    = @('upgrade', '--all', '--silent', '--accept-package-agreements', '--accept-source-agreements')
    }
    Chocolatey = @{
        Command       = 'choco.exe'
        InstallArgs   = @('install', '{0}', '-y', '--no-progress', '--limit-output')
        UninstallArgs = @('uninstall', '{0}', '-y', '--remove-dependencies')
        ListArgs      = @('list', '--local-only')
        SearchArgs    = @('search', '{0}')
        UpdateArgs    = @('upgrade', 'all', '-y')
    }
}
```

#### Usage Patterns

**Pattern 1: Check Availability Before Use**
```powershell
# ALWAYS check before invoking package managers
if (Test-CommandAvailable 'winget') {
    Write-Log "Using Winget for installation" 'INFO'
    $process = Invoke-LoggedCommand -FilePath 'winget.exe' -ArgumentList @('install', '--id', $appId, '--silent')
} elseif (Test-CommandAvailable 'choco') {
    Write-Log "Winget unavailable, using Chocolatey" 'WARN'
    $process = Invoke-LoggedCommand -FilePath 'choco.exe' -ArgumentList @('install', $chocoId, '-y')
} else {
    Write-Log "No package manager available" 'ERROR'
    return $false
}
```

**Pattern 2: Install with Fallback**
```powershell
function Install-ApplicationSafely {
    param(
        [string]$WingetId,
        [string]$ChocoId
    )
    
    # Try Winget first (preferred)
    if (Test-CommandAvailable 'winget') {
        try {
            Write-ActionLog -Action "Installing via Winget" -Details $WingetId -Category "Package Management" -Status 'START'
            $result = Invoke-LoggedCommand -FilePath 'winget.exe' -ArgumentList @('install', '--id', $WingetId, '--silent', '--accept-package-agreements')
            
            if ($result.ExitCode -eq 0) {
                Write-ActionLog -Action "Installation successful" -Details $WingetId -Category "Package Management" -Status 'SUCCESS'
                return $true
            }
        } catch {
            Write-Log "Winget installation failed: $_" 'WARN'
        }
    }
    
    # Fallback to Chocolatey
    if (Test-CommandAvailable 'choco') {
        try {
            Write-ActionLog -Action "Installing via Chocolatey" -Details $ChocoId -Category "Package Management" -Status 'START'
            $result = Invoke-LoggedCommand -FilePath 'choco.exe' -ArgumentList @('install', $ChocoId, '-y')
            
            if ($result.ExitCode -eq 0) {
                Write-ActionLog -Action "Installation successful" -Details $ChocoId -Category "Package Management" -Status 'SUCCESS'
                return $true
            }
        } catch {
            Write-Log "Chocolatey installation failed: $_" 'ERROR'
        }
    }
    
    return $false
}
```

**Pattern 3: Bulk Update All Packages**
```powershell
function Update-AllPackages {
    $updateCount = 0
    
    # Update via Winget
    if (Test-CommandAvailable 'winget') {
        Write-Log "Updating all Winget packages" 'INFO'
        $result = Invoke-LoggedCommand -FilePath 'winget.exe' -ArgumentList @('upgrade', '--all', '--silent', '--accept-package-agreements')
        if ($result.ExitCode -eq 0) { $updateCount++ }
    }
    
    # Update via Chocolatey
    if (Test-CommandAvailable 'choco') {
        Write-Log "Updating all Chocolatey packages" 'INFO'
        $result = Invoke-LoggedCommand -FilePath 'choco.exe' -ArgumentList @('upgrade', 'all', '-y')
        if ($result.ExitCode -eq 0) { $updateCount++ }
    }
    
    return $updateCount -gt 0
}
```

#### Application Installation Configuration

**Essential Apps** (defined in `$global:EssentialCategories`):

```powershell
$global:EssentialCategories = @{
    WebBrowsers   = @(
        @{ Name = 'Google Chrome'; Winget = 'Google.Chrome'; Choco = 'googlechrome' },
        @{ Name = 'Mozilla Firefox'; Winget = 'Mozilla.Firefox'; Choco = 'firefox' },
        @{ Name = 'Microsoft Edge'; Winget = 'Microsoft.Edge'; Choco = 'microsoft-edge' }
    )
    DocumentTools = @(
        @{ Name = 'Adobe Acrobat Reader'; Winget = 'Adobe.Acrobat.Reader.64-bit'; Choco = 'adobereader' },
        @{ Name = 'Notepad++'; Winget = 'Notepad++.Notepad++'; Choco = 'notepadplusplus' }
    )
    SystemTools   = @(
        @{ Name = 'PowerShell 7'; Winget = 'Microsoft.Powershell'; Choco = 'powershell' },
        @{ Name = '7-Zip'; Winget = '7zip.7zip'; Choco = '7zip' }
    )
}
```

**Add Custom Apps**:
```powershell
$global:Config.CustomEssentialApps += @(
    @{ Name = 'VS Code'; Winget = 'Microsoft.VisualStudioCode'; Choco = 'vscode' },
    @{ Name = 'Git'; Winget = 'Git.Git'; Choco = 'git' }
)
```

---

### 3. Registry Operations (Safe Access Pattern)

#### Overview
Safe registry modification system with permission validation and fallback paths.

**Location**: Lines 2000-2200 in script.ps1

#### Core Functions

**Function 1: `Test-RegistryAccess`**
**Purpose**: Validate read/write permissions before attempting modifications

**Signature**:
```powershell
Test-RegistryAccess -RegistryPath "HKLM:\Path" -CreatePath
```

**Returns**:
```powershell
@{
    Success = $true/$false
    Error = "Error message"
    Suggestion = "Remediation advice"
    ErrorType = "UnauthorizedAccess|SecurityException|GeneralError"
}
```

**Example**:
```powershell
$accessTest = Test-RegistryAccess -RegistryPath "HKLM:\SOFTWARE\Policies\Microsoft\Windows" -CreatePath

if ($accessTest.Success) {
    Write-Log "Registry access confirmed" 'SUCCESS'
    # Proceed with modifications
} else {
    Write-Log "Registry access denied: $($accessTest.Error)" 'ERROR'
    Write-Log "Suggestion: $($accessTest.Suggestion)" 'WARN'
    # Try fallback or skip
}
```

---

**Function 2: `Set-RegistryValueSafely`**
**Purpose**: Set registry values with comprehensive error handling and fallback options

**Signature**:
```powershell
Set-RegistryValueSafely -RegistryPath "HKLM:\Path" `
                        -ValueName "Name" `
                        -Value 1 `
                        -ValueType "DWord" `
                        -FallbackPaths @("HKCU:\Path") `
                        -Description "Setting description"
```

**Supported Value Types**:
- `String`: Text values
- `DWord`: 32-bit integer (0-4294967295)
- `QWord`: 64-bit integer
- `Binary`: Binary data
- `MultiString`: Array of strings
- `ExpandString`: Expandable string with environment variables

**Example - Disable Telemetry**:
```powershell
# Primary path with fallback
$result = Set-RegistryValueSafely `
    -RegistryPath "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" `
    -ValueName "AllowTelemetry" `
    -Value 0 `
    -ValueType "DWord" `
    -FallbackPaths @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection",
        "HKCU:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"
    ) `
    -Description "Telemetry setting"

if ($result.Success) {
    Write-Log "Telemetry disabled via $($result.Path) ($($result.Method))" 'SUCCESS'
} else {
    Write-Log "Failed to disable telemetry: $($result.Error)" 'ERROR'
}
```

#### Common Registry Patterns

**Pattern 1: Disable Windows Feature via Registry**
```powershell
function Disable-WindowsFeatureViaRegistry {
    param([string]$FeatureName, [string]$RegistryPath)
    
    # Test access first
    $access = Test-RegistryAccess -RegistryPath $RegistryPath -CreatePath
    if (-not $access.Success) {
        Write-Log "Cannot access registry path: $RegistryPath" 'ERROR'
        return $false
    }
    
    # Set value safely
    $result = Set-RegistryValueSafely `
        -RegistryPath $RegistryPath `
        -ValueName $FeatureName `
        -Value 0 `
        -ValueType "DWord" `
        -Description "Disable $FeatureName"
    
    return $result.Success
}
```

**Pattern 2: Batch Registry Modifications**
```powershell
function Set-MultipleRegistryValues {
    param([array]$RegistrySettings)
    
    $successCount = 0
    $totalCount = $RegistrySettings.Count
    
    foreach ($setting in $RegistrySettings) {
        Write-ActionProgress -ActionType "Configuring" -ItemName $setting.Description `
                             -PercentComplete 0 -CurrentItem $successCount -TotalItems $totalCount
        
        $result = Set-RegistryValueSafely @setting
        
        if ($result.Success) {
            $successCount++
            Write-ActionProgress -ActionType "Configuring" -ItemName $setting.Description -Completed
        } else {
            Write-Log "Failed to set $($setting.Description): $($result.Error)" 'WARN'
        }
    }
    
    Write-Log "Registry modifications: $successCount/$totalCount successful" 'INFO'
    return $successCount -eq $totalCount
}

# Usage
$telemetrySettings = @(
    @{ RegistryPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"; ValueName = "AllowTelemetry"; Value = 0; ValueType = "DWord"; Description = "Telemetry" },
    @{ RegistryPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy"; ValueName = "LetAppsAccessLocation"; Value = 2; ValueType = "DWord"; Description = "Location access" }
)

Set-MultipleRegistryValues -RegistrySettings $telemetrySettings
```

**Pattern 3: Read Registry Values Safely**
```powershell
function Get-RegistryValueSafely {
    param(
        [string]$RegistryPath,
        [string]$ValueName
    )
    
    try {
        if (Test-Path $RegistryPath) {
            $value = Get-ItemProperty -Path $RegistryPath -Name $ValueName -ErrorAction Stop
            return $value.$ValueName
        } else {
            Write-Log "Registry path does not exist: $RegistryPath" 'WARN'
            return $null
        }
    } catch {
        Write-Log "Failed to read registry value: $_" 'WARN'
        return $null
    }
}
```

#### Registry Safety Rules

1. **Always test access before modification** using `Test-RegistryAccess`
2. **Never assume write permissions** - check even with admin rights (Group Policy may block)
3. **Provide fallback paths** for critical settings (HKLM → HKCU fallback)
4. **Use descriptive names** in error messages for troubleshooting
5. **Log all registry operations** with full path and value details
6. **Handle exceptions gracefully** - registry access can fail for many reasons
7. **Validate value types** - mismatched types cause silent failures

---

### 4. Professional HTML Report Generation

#### Overview
Advanced reporting system generating professional, responsive HTML reports with complete data aggregation from the entire maintenance execution.

**Location**: `Write-UnifiedMaintenanceReport` function (Lines 9302-9930 in script.ps1)

**Report Output**: `$WorkingDirectory\maintenance_report.html` with embedded CSS, no external dependencies

#### Report Architecture

The HTML report aggregates data from multiple sources:

```
Data Collection Phase:
├── System Metadata (Computer name, user, OS info, versions)
├── Task Execution Results ($global:TaskResults)
├── System Inventory (CPU, memory, disk, uptime)
├── File Artifacts (logs, snapshots, temp files)
└── Action Logs (parsed from maintenance.log)

Template Rendering Phase:
├── Header Section (Professional gradient, title, date)
├── System Information Grid (8 metadata fields)
├── Execution Summary Dashboard (5 stat boxes with metrics)
├── Task Breakdown Table (Color-coded status, details, duration)
├── Hardware Information Cards (4 responsive cards)
├── Files Generated Section (Alert boxes with listings)
└── Footer (Report metadata, copyright)

Output Phase:
└── Single HTML file with embedded CSS (150-200 KB)
    ├── No external dependencies
    ├── Responsive design (mobile, tablet, desktop)
    ├── Print-friendly styling
    └── Works offline in any modern browser
```

#### Data Integration Points

**Metadata Collection** (Lines 9320-9350):
- Computer name, user account, OS information
- PowerShell version, script path, architecture
- Report generation timestamp

**Summary Calculation** (Lines 9350-9370):
- Total tasks, successful/failed counts
- Success rate percentage (calculated)
- Total execution duration (aggregated)

**Task Details** (Lines 9370-9390):
- Individual task execution results from `$global:TaskResults`
- Task name, description, status (success/failure)
- Duration for each task, error messages if failed
- **Serialization requirement**: Append tasks as `[pscustomobject]` instances with `success` explicitly cast to `[bool]` and `duration` stored as `[double]`. Hashtable entries default to `$false` when accessed via dot notation, which forces every row in the Task Breakdown to render as `✗ FAILED`.

**System Information** (Lines 9390-9420):
- WMI queries via `Get-CimInstance` for hardware specs
- Processor model, total/available memory in GB
- Disk space (total, free, used percentage)
- System uptime in hours

**File Inventory** (Lines 9420-9455):
- Log files from `$LogFile` directory
- JSON inventory files from `$global:TempFolder`
- File sizes and creation timestamps

#### HTML Template Structure

**CSS Features**:
- Bootstrap 5 inspired table styling (striped rows, hover effects)
- W3.CSS-inspired card layouts and color system
- Responsive CSS Grid with media queries (768px breakpoint)
- Professional gradients, shadows, and spacing
- Print-friendly stylesheet for professional printing

**Design Palette**:
- Primary: Purple gradients (#667eea → #764ba2)
- Success: Green (#28a745) for task success indicators
- Failure: Red (#dc3545) for failed tasks
- Info: Blue (#2196F3) for information alerts
- Warning: Orange (#ffc107) for error messages

**Responsive Breakpoints**:
- Desktop (>768px): 3+ column grids, full layout
- Tablet (768px): 2 column layouts, adjusted fonts
- Mobile (<768px): 1 column stacked, touch-friendly

**Color-Coded Status Indicators**:
```html
Success Row: <span class="status-success">✓ SUCCESS</span>  (Green text)
Failure Row: <span class="status-failed">✗ FAILED</span>    (Red text)
Error Row:   <div class="alert alert-error">⚠️ Error message</div> (Yellow bg)
```

#### Usage Example

```powershell
# Report automatically generated after maintenance execution
# Output file location:
$htmlReportPath = "$WorkingDirectory\maintenance_report.html"

# Open in default browser:
Invoke-Item $htmlReportPath

# Or programmatically:
Start-Process $htmlReportPath

# Report includes:
# - Professional header with gradient background
# - System metadata and execution summary
# - Color-coded task status table
# - Hardware information cards
# - List of generated files and artifacts
# - Print-optimized layout
```

#### Report Sections

1. **Header Section**
   - Title: "🖥️ Windows Maintenance Report"
   - Computer name and generation timestamp
   - Purple gradient background

2. **System Information Grid**
   - 8 fields in responsive grid layout
   - Computer, User, OS, Version, Architecture, Build, PowerShell, Script

3. **Execution Summary Dashboard**
   - 5 prominent stat boxes
   - Total tasks, Successful, Failed, Success Rate (green gradient), Duration

4. **Task Breakdown Table**
   - Sortable table with hover effects
   - Columns: Task Name, Status (✓/✗), Description, Duration
   - Color-coded rows (green for success, yellow for errors)

5. **Hardware Information Cards**
   - 4 responsive cards: CPU, Memory, Storage, Uptime
   - Key-value pairs with professional styling

6. **Generated Files Section**
   - Log files listing with sizes
   - Inventory files with creation timestamps
   - Alert-style boxes for organization

7. **Footer**
   - Report generation details
   - Script version and execution info
   - Professional branding

#### Performance Characteristics

- **Generation Time**: <1 second
- **File Size**: 150-200 KB (embedded CSS, no external assets)
- **Browser Load**: <2 seconds on typical hardware
- **Memory Usage**: <10 MB
- **Print Quality**: High-quality professional output
- **Browser Compatibility**: All modern browsers (Chrome, Edge, Firefox, Safari)

#### Best Practices for HTML Report Usage

1. **Archive Reports**: Keep HTML files for historical comparison
2. **Share Professionally**: Email reports or embed in larger documents
3. **Print for Records**: Professional print layout included
4. **Mobile Viewing**: Fully responsive design works on phones/tablets
5. **Offline Access**: View anytime without internet connection
6. **No Dependencies**: No external fonts, frameworks, or scripts required

#### Extending HTML Report

To add new sections to the report:

1. Add data collection to `$reportData` hashtable (lines 9320-9455)
2. Add HTML section to template (lines 9480-9920)
3. Add CSS styling to `<style>` section (lines 9515-9700)
4. Use PowerShell string interpolation: `$($variable)`

Example:
```powershell
# In data collection phase:
$reportData.customSection = @{ field1 = "value1"; field2 = "value2" }

# In HTML template:
<div class="section">
    <h2>📌 Custom Section</h2>
    <p>Field 1: $($reportData.customSection.field1)</p>
    <p>Field 2: $($reportData.customSection.field2)</p>
</div>
```

---

## Workflows & Procedures

### Workflow 1: Adding New Maintenance Task

**Step 1: Create Task Function**

Create a new function following the standardized pattern:

```powershell
function Invoke-MyCustomTask {
    <#
    .SYNOPSIS
        Brief description of what the task does
    
    .DESCRIPTION
        Detailed description of task functionality, requirements, and behavior
    
    .EXAMPLE
        Invoke-MyCustomTask
    #>
    
    [CmdletBinding()]
    param()
    
    try {
        Write-ActionLog -Action "Starting custom task" -Details "Task initialization" -Category "Task Execution" -Status 'START'
        Write-Log "Custom task execution beginning" 'INFO'
        
        # Task-specific logic with progress tracking
        Write-TaskProgress -Activity "Custom Task" -PercentComplete 0 -Status "Initializing"
        
        # Step 1: Validation
        if (-not (Test-Preconditions)) {
            throw "Preconditions not met"
        }
        
        Write-TaskProgress -Activity "Custom Task" -PercentComplete 30 -Status "Executing main logic"
        
        # Step 2: Main task logic
        $result = Invoke-TaskLogic
        
        Write-TaskProgress -Activity "Custom Task" -PercentComplete 80 -Status "Finalizing"
        
        # Step 3: Verification
        if (Test-TaskSuccess -Result $result) {
            Write-TaskProgress -Activity "Custom Task" -PercentComplete 100 -Status "Complete"
            Write-ActionLog -Action "Custom task completed" -Details "Success" -Category "Task Execution" -Status 'SUCCESS'
            return $true
        } else {
            throw "Task verification failed"
        }
    }
    catch {
        Write-ActionLog -Action "Custom task failed" -Details $_.Exception.Message -Category "Task Execution" -Status 'FAILURE'
        Write-Log "Custom task error: $($_.Exception | Format-List * | Out-String)" 'ERROR'
        return $false
    }
}
```

**Step 2: Add to Task Array**

Add entry to `$global:ScriptTasks` array (around line 250-550 in script.ps1):

```powershell
$global:ScriptTasks = @(
    # ... existing tasks ...
    
    @{ 
        Name = 'MyCustomTask'
        Function = { Invoke-MyCustomTask }
        Description = 'Performs custom maintenance operation on system components'
    }
)
```

**Step 3: Add Configuration Option (if optional)**

Add skip flag to `$global:Config` (around line 150):

```powershell
$global:Config = @{
    # ... existing config ...
    SkipMyCustomTask = $false  # Set to $true to skip this task
}
```

Update task function to check config:

```powershell
@{ 
    Name = 'MyCustomTask'
    Function = {
        if (-not $global:Config.SkipMyCustomTask) {
            Invoke-MyCustomTask
        } else {
            Write-Log "MyCustomTask skipped by configuration" 'INFO'
            return $true  # Return success even when skipped
        }
    }
    Description = 'Performs custom maintenance operation on system components'
}
```

**Step 4: Test Independently**

```powershell
# Test the task function directly
Invoke-MyCustomTask

# Test via task array (find index first)
$taskIndex = $global:ScriptTasks.FindIndex({ $args[0].Name -eq 'MyCustomTask' })
& $global:ScriptTasks[$taskIndex].Function

# Check results
$global:TaskResults['MyCustomTask']
```

**Step 5: Integration Testing**

Run full script with new task:
```powershell
# From PowerShell
.\script.ps1

# Or via batch launcher
.\script.bat
```

---

### Workflow 2: Modifying Batch Launcher (Critical Sections)

**Critical Sections** in `script.bat`:

| Lines | Component | Purpose | Modification Risk |
|-------|-----------|---------|-------------------|
| 30-80 | Admin Elevation | Dual-method privilege check (NET SESSION + PowerShell) | ⚠️ **HIGH** - May break elevation |
| 200-550 | Dependency Installation | Sequential tooling setup (Winget → PS7 → NuGet → PSGallery → Choco) | ⚠️ **CRITICAL** - Order matters |
| 350-450 | Scheduled Task Setup | Monthly automation with SYSTEM account | ⚠️ **MEDIUM** - Task path detection |
| 450-550 | Restart Detection | Windows Update-triggered restart handling | ⚠️ **MEDIUM** - Pre-maintenance restart only |
| 600-700 | PowerShell Script Path | Intelligent script.ps1 detection (local/extracted/network) | ⚠️ **HIGH** - Path resolution |
| 700-850 | Repository Management | GitHub download, extraction, self-update | ⚠️ **MEDIUM** - Network paths |

**Admin Elevation Logic** (Lines 30-80):
```batch
REM Method 1: NET SESSION (traditional approach)
NET SESSION >nul 2>&1
SET "NET_SESSION_RESULT=%ERRORLEVEL%"

REM Method 2: PowerShell admin check (more reliable)
FOR /F "tokens=*" %%i IN ('powershell -Command "([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)"') DO SET PS_ADMIN_CHECK=%%i

REM Consider admin if either method confirms privileges
SET "IS_ADMIN=false"
IF %NET_SESSION_RESULT% EQU 0 SET "IS_ADMIN=true"
IF "%PS_ADMIN_CHECK%"=="True" SET "IS_ADMIN=true"
```

**Dependency Installation Order** (Lines 200-550):
```
1. Winget (Windows Package Manager) → Foundation package manager
2. PowerShell 7 → Modern PowerShell runtime
3. NuGet Provider → PowerShell package management
4. PSGallery Configuration → Trusted repository setup
5. PSWindowsUpdate Module → Windows Update automation
6. Chocolatey → Secondary package manager
```

**⚠️ NEVER CHANGE**:
- Admin check logic without testing both interactive and scheduled task scenarios
- Dependency installation order (dependencies have interdependencies)
- Self-update mechanism without accounting for running processes
- Path detection logic without testing network/UNC/removable drive scenarios

**Testing Checklist for Batch Modifications**:
1. ✅ Interactive execution (double-click script.bat)
2. ✅ Elevated command prompt execution
3. ✅ Scheduled task execution (SYSTEM account)
4. ✅ Network path execution (UNC path)
5. ✅ Removable drive execution
6. ✅ After PowerShell 7 installation (restart scenario)
7. ✅ After Windows Update restart
8. ✅ Repository download/update scenario

---

### Workflow 3: Windows Update Integration

**Architecture**:
- **Batch Launcher**: Handles pre-maintenance restarts (Windows Update pending)
- **PowerShell Orchestrator**: Installs updates, defers post-maintenance restart

**PSWindowsUpdate Module Integration**:

```powershell
function Install-WindowsUpdatesCompatible {
    try {
        # Check if PSWindowsUpdate module is available
        if (Get-Module -ListAvailable -Name 'PSWindowsUpdate') {
            Write-Log "Using PSWindowsUpdate module for enhanced update management" 'INFO'
            Import-Module PSWindowsUpdate -Force
            
            # Install updates with acceptance and reboot detection
            $updates = Get-WindowsUpdate -AcceptAll -IgnoreReboot
            
            if ($updates) {
                Write-Log "Found $($updates.Count) available updates" 'INFO'
                Install-WindowsUpdate -AcceptAll -IgnoreReboot
                
                # Check if reboot is required
                $rebootRequired = Get-WURebootStatus -Silent
                if ($rebootRequired) {
                    $global:SystemSettings.Reboot.Required = $true
                    $global:SystemSettings.Reboot.Source = "PSWindowsUpdate"
                    $global:SystemSettings.Reboot.Timestamp = Get-Date
                }
            }
        } else {
            # Fallback: Native Windows Update via COM
            Write-Log "PSWindowsUpdate unavailable, using native Windows Update" 'WARN'
            $updateSession = New-Object -ComObject Microsoft.Update.Session
            $updateSearcher = $updateSession.CreateUpdateSearcher()
            $searchResult = $updateSearcher.Search("IsInstalled=0")
            
            if ($searchResult.Updates.Count -gt 0) {
                Write-Log "Found $($searchResult.Updates.Count) updates via COM" 'INFO'
                # Trigger update UI or use settings
                Start-Process "ms-settings:windowsupdate" -ErrorAction SilentlyContinue
            }
        }
    }
    catch {
        Write-Log "Windows Update check failed: $_" 'ERROR'
        return $false
    }
}
```

**Restart Tracking**:

```powershell
# Detect restart requirement
$global:SystemSettings.Reboot = @{
    Required = $false
    Source = $null      # "PSWindowsUpdate" | "Registry" | "Manual"
    Timestamp = $null
}

# Check multiple restart indicators
$restartChecks = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired",
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending"
)

foreach ($key in $restartChecks) {
    if (Test-Path $key) {
        $global:SystemSettings.Reboot.Required = $true
        $global:SystemSettings.Reboot.Source = "Registry"
        break
    }
}
```

**Restart Handling at Script End**:

```powershell
# After all tasks complete
if ($global:SystemSettings.Reboot.Required) {
    Write-Log "System restart required by $($global:SystemSettings.Reboot.Source)" 'WARN'
    
    # Option 1: Immediate restart (unattended mode)
    if ($global:Config.AutoRestart) {
        Write-Log "Initiating automatic restart in 60 seconds..." 'WARN'
        shutdown /r /t 60 /c "Windows maintenance completed. System restart required."
    }
    
    # Option 2: Defer restart (interactive mode)
    else {
        Write-Log "Please restart system when convenient to complete updates" 'INFO'
    }
}

---

## Testing & Debugging

### Comprehensive Testing Framework

#### Testing Levels Hierarchy

```
Level 1: Unit Testing (Individual Functions)
    ├── Test-LoggingFunctions
    ├── Test-RegistryOperations
    ├── Test-PackageManagerAbstraction
    └── Test-BloatwareDetection

Level 2: Integration Testing (Task Coordination)
    ├── Test-TaskArrayExecution
    ├── Test-TaskResultTracking
    └── Test-ErrorPropagation

Level 3: System Testing (Full Script Execution)
    ├── Test-InteractiveExecution
    ├── Test-ScheduledTaskExecution
    └── Test-NetworkPathExecution

Level 4: Performance Testing (Benchmarking)
    ├── Test-ExecutionTiming
    ├── Test-MemoryUsage
    └── Test-ResourceConsumption

Level 5: Regression Testing (Change Validation)
    ├── Test-BeforeAfterComparison
    ├── Test-ConfigurationChanges
    └── Test-DependencyUpdates
```

---

### Level 1: Unit Testing

#### Test Suite 1: Logging Functions

```powershell
function Test-LoggingFunctions {
    <#
    .SYNOPSIS
        Comprehensive test suite for all logging functions
    .DESCRIPTION
        Tests Write-Log, Write-ActionLog, Write-CommandLog for proper
        output formatting, file creation, error handling
    #>
    
    Write-Host "`n=== Testing Logging Functions ===" -ForegroundColor Cyan
    
    # Test 1: Write-Log basic functionality
    Write-Host "`nTest 1: Write-Log basic functionality" -ForegroundColor Yellow
    $testLogPath = Join-Path $env:TEMP "test_maintenance.log"
    $global:LogFile = $testLogPath
    
    try {
        # Test all log levels
        $logLevels = @('DEBUG', 'INFO', 'WARN', 'ERROR', 'SUCCESS', 'PROGRESS', 'ACTION', 'COMMAND')
        foreach ($level in $logLevels) {
            Write-Log "Test message for level: $level" $level
        }
        
        # Verify log file exists and contains entries
        if (Test-Path $testLogPath) {
            $logContent = Get-Content $testLogPath
            $levelCount = ($logContent | Where-Object { $_ -match '\[(DEBUG|INFO|WARN|ERROR|SUCCESS|PROGRESS|ACTION|COMMAND)\]' }).Count
            
            if ($levelCount -eq $logLevels.Count) {
                Write-Host "✓ PASS: All log levels written correctly ($levelCount entries)" -ForegroundColor Green
            } else {
                Write-Host "✗ FAIL: Expected $($logLevels.Count) entries, found $levelCount" -ForegroundColor Red
            }
        } else {
            Write-Host "✗ FAIL: Log file not created at $testLogPath" -ForegroundColor Red
        }
    }
    catch {
        Write-Host "✗ FAIL: Exception during Write-Log test: $_" -ForegroundColor Red
    }
    finally {
        # Cleanup
        if (Test-Path $testLogPath) { Remove-Item $testLogPath -Force -ErrorAction SilentlyContinue }
    }
    
    # Test 2: Write-ActionLog categorization
    Write-Host "`nTest 2: Write-ActionLog categorization" -ForegroundColor Yellow
    $testLogPath = Join-Path $env:TEMP "test_action.log"
    $global:LogFile = $testLogPath
    
    try {
        $categories = @('Task Orchestration', 'Package Management', 'Registry Operations', 'System Configuration')
        $statuses = @('START', 'SUCCESS', 'FAILURE', 'INFO')
        
        foreach ($category in $categories) {
            foreach ($status in $statuses) {
                Write-ActionLog -Action "Test Action" -Details "Category: $category" -Category $category -Status $status
            }
        }
        
        $logContent = Get-Content $testLogPath
        $categoryCount = ($logContent | Where-Object { $_ -match '\[(Task Orchestration|Package Management|Registry Operations|System Configuration)\]' }).Count
        
        if ($categoryCount -eq ($categories.Count * $statuses.Count)) {
            Write-Host "✓ PASS: All categories and statuses logged correctly" -ForegroundColor Green
        } else {
            Write-Host "✗ FAIL: Expected $($categories.Count * $statuses.Count) entries, found $categoryCount" -ForegroundColor Red
        }
    }
    catch {
        Write-Host "✗ FAIL: Exception during Write-ActionLog test: $_" -ForegroundColor Red
    }
    finally {
        if (Test-Path $testLogPath) { Remove-Item $testLogPath -Force -ErrorAction SilentlyContinue }
    }
    
    # Test 3: Write-CommandLog external process tracking
    Write-Host "`nTest 3: Write-CommandLog process tracking" -ForegroundColor Yellow
    $testLogPath = Join-Path $env:TEMP "test_command.log"
    $global:LogFile = $testLogPath
    
    try {
        Write-CommandLog -Command "powershell.exe" -Arguments @('-Command', 'Get-Date') -Context "Test command" -Status 'START'
        Write-CommandLog -Command "powershell.exe" -Arguments @('-Command', 'Get-Date') -Context "Test command completed" -Status 'SUCCESS'
        
        $logContent = Get-Content $testLogPath
        $commandEntries = ($logContent | Where-Object { $_ -match 'COMMAND: powershell\.exe' }).Count
        
        if ($commandEntries -ge 1) {
            Write-Host "✓ PASS: Command logging functional ($commandEntries entries)" -ForegroundColor Green
        } else {
            Write-Host "✗ FAIL: Command not logged properly" -ForegroundColor Red
        }
    }
    catch {
        Write-Host "✗ FAIL: Exception during Write-CommandLog test: $_" -ForegroundColor Red
    }
    finally {
        if (Test-Path $testLogPath) { Remove-Item $testLogPath -Force -ErrorAction SilentlyContinue }
    }
    
    Write-Host "`n=== Logging Functions Test Complete ===" -ForegroundColor Cyan
}
```

#### Test Suite 2: Registry Operations

```powershell
function Test-RegistryOperations {
    <#
    .SYNOPSIS
        Test registry access validation and safe modification patterns
    .DESCRIPTION
        Validates Test-RegistryAccess and Set-RegistryValueSafely functions
        with various permission scenarios and fallback mechanisms
    #>
    
    Write-Host "`n=== Testing Registry Operations ===" -ForegroundColor Cyan
    
    # Test 1: Test-RegistryAccess with valid path
    Write-Host "`nTest 1: Registry access validation (valid path)" -ForegroundColor Yellow
    $testPath = "HKCU:\Software\TestMaintenance_$(Get-Random)"
    
    try {
        # Test with CreatePath flag
        $result = Test-RegistryAccess -RegistryPath $testPath -CreatePath
        
        if ($result.Success) {
            Write-Host "✓ PASS: Registry path created and access validated" -ForegroundColor Green
            
            # Verify path exists
            if (Test-Path $testPath) {
                Write-Host "✓ PASS: Registry path physically exists" -ForegroundColor Green
            } else {
                Write-Host "✗ FAIL: Path reported success but doesn't exist" -ForegroundColor Red
            }
        } else {
            Write-Host "✗ FAIL: Registry access validation failed: $($result.Error)" -ForegroundColor Red
        }
    }
    catch {
        Write-Host "✗ FAIL: Exception during registry access test: $_" -ForegroundColor Red
    }
    finally {
        # Cleanup
        if (Test-Path $testPath) {
            Remove-Item $testPath -Force -Recurse -ErrorAction SilentlyContinue
        }
    }
    
    # Test 2: Set-RegistryValueSafely with various types
    Write-Host "`nTest 2: Safe registry value setting (all types)" -ForegroundColor Yellow
    $testPath = "HKCU:\Software\TestMaintenance_$(Get-Random)"
    
    try {
        $valueTests = @(
            @{ Name = 'TestString'; Value = 'TestValue'; Type = 'String'; Expected = 'TestValue' },
            @{ Name = 'TestDWord'; Value = 12345; Type = 'DWord'; Expected = 12345 },
            @{ Name = 'TestQWord'; Value = [int64]123456789; Type = 'QWord'; Expected = [int64]123456789 },
            @{ Name = 'TestBinary'; Value = [byte[]]@(1,2,3,4); Type = 'Binary'; Expected = @(1,2,3,4) }
        )
        
        $successCount = 0
        foreach ($test in $valueTests) {
            $result = Set-RegistryValueSafely -RegistryPath $testPath `
                                               -ValueName $test.Name `
                                               -Value $test.Value `
                                               -ValueType $test.Type `
                                               -Description "Test $($test.Type) value"
            
            if ($result.Success) {
                # Verify value was set correctly
                $readValue = Get-ItemPropertyValue -Path $testPath -Name $test.Name -ErrorAction SilentlyContinue
                
                if ($test.Type -eq 'Binary') {
                    $match = Compare-Object $readValue $test.Expected -SyncWindow 0
                    if (-not $match) {
                        $successCount++
                        Write-Host "  ✓ $($test.Type) value set and verified" -ForegroundColor Green
                    }
                } else {
                    if ($readValue -eq $test.Expected) {
                        $successCount++
                        Write-Host "  ✓ $($test.Type) value set and verified" -ForegroundColor Green
                    } else {
                        Write-Host "  ✗ $($test.Type) value mismatch: Expected $($test.Expected), Got $readValue" -ForegroundColor Red
                    }
                }
            } else {
                Write-Host "  ✗ Failed to set $($test.Type) value: $($result.Error)" -ForegroundColor Red
            }
        }
        
        if ($successCount -eq $valueTests.Count) {
            Write-Host "✓ PASS: All registry value types handled correctly ($successCount/$($valueTests.Count))" -ForegroundColor Green
        } else {
            Write-Host "✗ PARTIAL: $successCount/$($valueTests.Count) value types successful" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "✗ FAIL: Exception during registry value test: $_" -ForegroundColor Red
    }
    finally {
        if (Test-Path $testPath) {
            Remove-Item $testPath -Force -Recurse -ErrorAction SilentlyContinue
        }
    }
    
    # Test 3: Fallback path mechanism
    Write-Host "`nTest 3: Registry fallback path mechanism" -ForegroundColor Yellow
    $primaryPath = "HKLM:\Software\TestMaintenance_Invalid_$(Get-Random)"  # Will fail without admin
    $fallbackPath = "HKCU:\Software\TestMaintenance_Fallback_$(Get-Random)"
    
    try {
        $result = Set-RegistryValueSafely -RegistryPath $primaryPath `
                                           -ValueName "TestValue" `
                                           -Value "Fallback Test" `
                                           -ValueType "String" `
                                           -FallbackPaths @($fallbackPath) `
                                           -Description "Fallback test"
        
        if ($result.Success -and $result.Method -eq 'Fallback') {
            Write-Host "✓ PASS: Fallback mechanism worked correctly" -ForegroundColor Green
            
            # Verify value in fallback location
            if (Test-Path $fallbackPath) {
                $value = Get-ItemPropertyValue -Path $fallbackPath -Name "TestValue" -ErrorAction SilentlyContinue
                if ($value -eq "Fallback Test") {
                    Write-Host "✓ PASS: Value correctly written to fallback path" -ForegroundColor Green
                }
            }
        } elseif ($result.Success -and $result.Method -eq 'Primary') {
            Write-Host "⚠ WARN: Primary path succeeded (running as admin?), fallback not tested" -ForegroundColor Yellow
        } else {
            Write-Host "✗ FAIL: Fallback mechanism failed: $($result.Error)" -ForegroundColor Red
        }
    }
    catch {
        Write-Host "✗ FAIL: Exception during fallback test: $_" -ForegroundColor Red
    }
    finally {
        if (Test-Path $fallbackPath) {
            Remove-Item $fallbackPath -Force -Recurse -ErrorAction SilentlyContinue
        }
    }
    
    Write-Host "`n=== Registry Operations Test Complete ===" -ForegroundColor Cyan
}
```

#### Test Suite 3: Package Manager Abstraction

```powershell
function Test-PackageManagerAbstraction {
    <#
    .SYNOPSIS
        Test package manager detection and command availability
    .DESCRIPTION
        Validates Test-CommandAvailable and package manager abstraction layer
        without actually installing/removing packages
    #>
    
    Write-Host "`n=== Testing Package Manager Abstraction ===" -ForegroundColor Cyan
    
    # Test 1: Command availability detection
    Write-Host "`nTest 1: Command availability detection" -ForegroundColor Yellow
    
    $testCommands = @(
        @{ Command = 'powershell.exe'; ShouldExist = $true },
        @{ Command = 'cmd.exe'; ShouldExist = $true },
        @{ Command = 'winget'; ShouldExist = $null },  # May or may not exist
        @{ Command = 'choco'; ShouldExist = $null },   # May or may not exist
        @{ Command = 'nonexistent_command_12345'; ShouldExist = $false }
    )
    
    $passCount = 0
    foreach ($test in $testCommands) {
        $result = Test-CommandAvailable $test.Command
        
        if ($test.ShouldExist -eq $null) {
            # Optional command - just report status
            $status = if ($result) { "Available" } else { "Not Available" }
            Write-Host "  ℹ $($test.Command): $status" -ForegroundColor Cyan
            $passCount++
        } elseif ($result -eq $test.ShouldExist) {
            Write-Host "  ✓ $($test.Command): Correctly detected as $(if($result){'available'}else{'unavailable'})" -ForegroundColor Green
            $passCount++
        } else {
            Write-Host "  ✗ $($test.Command): Expected $($test.ShouldExist), Got $result" -ForegroundColor Red
        }
    }
    
    Write-Host "✓ Command detection: $passCount/$($testCommands.Count) tests passed" -ForegroundColor $(if($passCount -eq $testCommands.Count){'Green'}else{'Yellow'})
    
    # Test 2: Package manager configuration structure
    Write-Host "`nTest 2: Package manager configuration validation" -ForegroundColor Yellow
    
    $requiredKeys = @('Command', 'InstallArgs', 'UninstallArgs', 'ListArgs', 'SearchArgs', 'UpdateArgs')
    $passCount = 0
    
    foreach ($pm in $global:PackageManagers.Keys) {
        $config = $global:PackageManagers[$pm]
        $missingKeys = $requiredKeys | Where-Object { -not $config.ContainsKey($_) }
        
        if ($missingKeys.Count -eq 0) {
            Write-Host "  ✓ $pm configuration: All required keys present" -ForegroundColor Green
            $passCount++
            
            # Validate argument arrays
            $validArgs = $true
            foreach ($key in @('InstallArgs', 'UninstallArgs', 'ListArgs', 'SearchArgs', 'UpdateArgs')) {
                if ($config[$key] -isnot [array]) {
                    Write-Host "    ✗ $key is not an array" -ForegroundColor Red
                    $validArgs = $false
                }
            }
            
            if ($validArgs) {
                Write-Host "    ✓ All argument lists are properly formatted arrays" -ForegroundColor Green
            }
        } else {
            Write-Host "  ✗ $pm configuration: Missing keys: $($missingKeys -join ', ')" -ForegroundColor Red
        }
    }
    
    if ($passCount -eq $global:PackageManagers.Count) {
        Write-Host "✓ PASS: All package manager configurations valid" -ForegroundColor Green
    } else {
        Write-Host "✗ FAIL: Some package manager configurations invalid" -ForegroundColor Red
    }
    
    # Test 3: Winget/Chocolatey availability and version
    Write-Host "`nTest 3: Package manager availability and version check" -ForegroundColor Yellow
    
    if (Test-CommandAvailable 'winget') {
        try {
            $wingetVersion = winget --version 2>&1
            Write-Host "  ✓ Winget available: Version $wingetVersion" -ForegroundColor Green
            
            # Test simple winget command
            $testResult = winget list --name "Microsoft" --accept-source-agreements 2>&1
            if ($LASTEXITCODE -eq 0 -or $testResult -like "*Microsoft*") {
                Write-Host "    ✓ Winget list command functional" -ForegroundColor Green
            } else {
                Write-Host "    ⚠ Winget list command returned unexpected result" -ForegroundColor Yellow
            }
        }
        catch {
            Write-Host "  ⚠ Winget available but version check failed: $_" -ForegroundColor Yellow
        }
    } else {
        Write-Host "  ℹ Winget not available on this system" -ForegroundColor Cyan
    }
    
    if (Test-CommandAvailable 'choco') {
        try {
            $chocoVersion = choco --version 2>&1
            Write-Host "  ✓ Chocolatey available: Version $chocoVersion" -ForegroundColor Green
            
            # Test simple choco command
            $testResult = choco list --local-only --limit-output 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Host "    ✓ Chocolatey list command functional" -ForegroundColor Green
            } else {
                Write-Host "    ⚠ Chocolatey list command returned unexpected result" -ForegroundColor Yellow
            }
        }
        catch {
            Write-Host "  ⚠ Chocolatey available but version check failed: $_" -ForegroundColor Yellow
        }
    } else {
        Write-Host "  ℹ Chocolatey not available on this system" -ForegroundColor Cyan
    }
    
    Write-Host "`n=== Package Manager Abstraction Test Complete ===" -ForegroundColor Cyan
}
```

#### Test Suite 4: Bloatware Detection

```powershell
function Test-BloatwareDetection {
    <#
    .SYNOPSIS
        Test bloatware detection across all 5 methods
    .DESCRIPTION
        Non-destructive test of bloatware detection mechanisms:
        1. AppX packages
        2. DISM provisioned packages
        3. Registry uninstall keys
        4. Windows Capabilities
        5. Package manager lists
    #>
    
    Write-Host "`n=== Testing Bloatware Detection System ===" -ForegroundColor Cyan
    
    # Test 1: AppX Package Detection
    Write-Host "`nTest 1: AppX Package Detection" -ForegroundColor Yellow
    
    try {
        $testPatterns = @('Microsoft.Windows*', 'Microsoft.Xbox*')
        $appxPackages = Get-AppxPackage -AllUsers -ErrorAction Stop | Where-Object {
            $appName = $_.Name
            $testPatterns | Where-Object { $appName -like $_ }
        }
        
        if ($appxPackages) {
            Write-Host "✓ PASS: AppX detection functional - Found $($appxPackages.Count) matching packages" -ForegroundColor Green
            Write-Host "  Sample: $($appxPackages[0].Name)" -ForegroundColor Gray
        } else {
            Write-Host "⚠ WARN: AppX detection ran but found no matching packages" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "✗ FAIL: AppX detection failed: $_" -ForegroundColor Red
    }
    
    # Test 2: DISM Provisioned Package Detection
    Write-Host "`nTest 2: DISM Provisioned Package Detection" -ForegroundColor Yellow
    
    try {
        $provisionedPackages = Get-AppxProvisionedPackage -Online -ErrorAction Stop | Where-Object {
            $_.DisplayName -like '*Microsoft*'
        }
        
        if ($provisionedPackages) {
            Write-Host "✓ PASS: DISM detection functional - Found $($provisionedPackages.Count) provisioned packages" -ForegroundColor Green
            Write-Host "  Sample: $($provisionedPackages[0].DisplayName)" -ForegroundColor Gray
        } else {
            Write-Host "⚠ WARN: DISM detection ran but found no matching packages" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "✗ FAIL: DISM detection failed: $_" -ForegroundColor Red
    }
    
    # Test 3: Registry Uninstall Key Detection
    Write-Host "`nTest 3: Registry Uninstall Key Detection" -ForegroundColor Yellow
    
    try {
        $registryApps = Get-RegistryUninstallBloatware -BloatwarePatterns @('Microsoft', 'Windows') -Context "Detection Test"
        
        if ($registryApps) {
            Write-Host "✓ PASS: Registry detection functional - Found $($registryApps.Count) registry entries" -ForegroundColor Green
            Write-Host "  Sample: $($registryApps[0].DisplayName)" -ForegroundColor Gray
        } else {
            Write-Host "⚠ WARN: Registry detection ran but found no matching entries" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "✗ FAIL: Registry detection failed: $_" -ForegroundColor Red
    }
    
    # Test 4: Windows Capabilities Detection
    Write-Host "`nTest 4: Windows Capabilities Detection" -ForegroundColor Yellow
    
    try {
        $capabilities = Get-WindowsCapability -Online -ErrorAction Stop | Where-Object {
            $_.State -eq 'Installed' -and $_.Name -like '*Media*'
        }
        
        if ($capabilities) {
            Write-Host "✓ PASS: Capabilities detection functional - Found $($capabilities.Count) installed capabilities" -ForegroundColor Green
            Write-Host "  Sample: $($capabilities[0].Name)" -ForegroundColor Gray
        } else {
            Write-Host "⚠ WARN: Capabilities detection ran but found no matching features" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "✗ FAIL: Capabilities detection failed: $_" -ForegroundColor Red
    }
    
    # Test 5: Package Manager Cross-Reference
    Write-Host "`nTest 5: Package Manager Cross-Reference" -ForegroundColor Yellow
    
    $pmDetected = 0
    
    if (Test-CommandAvailable 'winget') {
        try {
            $wingetList = winget list --accept-source-agreements 2>&1 | Out-String
            if ($wingetList -and $wingetList.Length -gt 100) {
                Write-Host "  ✓ Winget list retrieved successfully" -ForegroundColor Green
                $pmDetected++
            }
        }
        catch {
            Write-Host "  ⚠ Winget detection failed: $_" -ForegroundColor Yellow
        }
    } else {
        Write-Host "  ℹ Winget not available" -ForegroundColor Cyan
    }
    
    if (Test-CommandAvailable 'choco') {
        try {
            $chocoList = choco list --local-only --limit-output 2>&1 | Out-String
            if ($chocoList -and $chocoList.Length -gt 10) {
                Write-Host "  ✓ Chocolatey list retrieved successfully" -ForegroundColor Green
                $pmDetected++
            }
        }
        catch {
            Write-Host "  ⚠ Chocolatey detection failed: $_" -ForegroundColor Yellow
        }
    } else {
        Write-Host "  ℹ Chocolatey not available" -ForegroundColor Cyan
    }
    
    if ($pmDetected -gt 0) {
        Write-Host "✓ PASS: Package manager detection functional ($pmDetected managers)" -ForegroundColor Green
    } else {
        Write-Host "⚠ WARN: No package managers available for testing" -ForegroundColor Yellow
    }
    
    # Test 6: Category Structure Validation
    Write-Host "`nTest 6: Bloatware Category Structure Validation" -ForegroundColor Yellow
    
    $requiredCategories = @('OEMBloatware', 'GamingSocial', 'MicrosoftBloatware', 'XboxGaming', 'SecurityBloatware')
    $passCount = 0
    
    foreach ($category in $requiredCategories) {
        if ($global:AppCategories.ContainsKey($category)) {
            $patterns = $global:AppCategories[$category]
            if ($patterns -is [array] -and $patterns.Count -gt 0) {
                Write-Host "  ✓ $category: $($patterns.Count) patterns defined" -ForegroundColor Green
                $passCount++
            } else {
                Write-Host "  ✗ $category: Invalid or empty pattern list" -ForegroundColor Red
            }
        } else {
            Write-Host "  ✗ $category: Category not found" -ForegroundColor Red
        }
    }
    
    if ($passCount -eq $requiredCategories.Count) {
        Write-Host "✓ PASS: All bloatware categories properly configured" -ForegroundColor Green
    } else {
        Write-Host "✗ FAIL: Some bloatware categories missing or misconfigured" -ForegroundColor Red
    }
    
    Write-Host "`n=== Bloatware Detection Test Complete ===" -ForegroundColor Cyan
}
```

### Manual Task Testing

**Test Individual Task Function**:
```powershell
# Direct function invocation
Invoke-MyCustomTask

# Via task array (recommended - tests integration)
$task = $global:ScriptTasks | Where-Object { $_.Name -eq 'MyCustomTask' }
& $task.Function

# Check execution results
$global:TaskResults['MyCustomTask']
# Output: @{ Success = $true; Duration = 12.34; Started = DateTime; ... }
```

**Test Specific Task by Index**:
```powershell
# Execute RemoveBloatware task (index 2)
& $global:ScriptTasks[2].Function

# View all available tasks
$global:ScriptTasks | Format-Table Name, Description
```

---

### Level 2: Integration Testing

#### Test Suite 5: Task Array Execution

```powershell
function Test-TaskArrayExecution {
    <#
    .SYNOPSIS
        Test task orchestration and execution flow
    .DESCRIPTION
        Validates that task array properly coordinates execution,
        respects skip flags, tracks results, and handles errors
    #>
    
    Write-Host "`n=== Testing Task Array Execution ===" -ForegroundColor Cyan
    
    # Test 1: Task array structure validation
    Write-Host "`nTest 1: Task array structure validation" -ForegroundColor Yellow
    
    $requiredProperties = @('Name', 'Function', 'Description')
    $validTasks = 0
    $invalidTasks = @()
    
    foreach ($task in $global:ScriptTasks) {
        $missingProps = $requiredProperties | Where-Object { -not $task.ContainsKey($_) }
        
        if ($missingProps.Count -eq 0) {
            # Validate property types
            if ($task.Name -is [string] -and 
                $task.Function -is [scriptblock] -and 
                $task.Description -is [string]) {
                $validTasks++
            } else {
                $invalidTasks += "Task '$($task.Name)' has invalid property types"
            }
        } else {
            $invalidTasks += "Task missing properties: $($missingProps -join ', ')"
        }
    }
    
    if ($invalidTasks.Count -eq 0) {
        Write-Host "✓ PASS: All $validTasks tasks properly structured" -ForegroundColor Green
    } else {
        Write-Host "✗ FAIL: Found $($invalidTasks.Count) structural issues:" -ForegroundColor Red
        $invalidTasks | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    }
    
    # Test 2: Task skip flag handling
    Write-Host "`nTest 2: Task skip flag handling" -ForegroundColor Yellow
    
    # Create a test task with skip flag
    $testTaskName = "TestSkippableTask_$(Get-Random)"
    $global:Config["Skip$testTaskName"] = $true
    
    $testTask = @{
        Name = $testTaskName
        Function = {
            if ($global:Config["Skip$testTaskName"]) {
                Write-Log "Task skipped by configuration" 'INFO'
                return $true
            }
            Write-Log "Task executed" 'INFO'
            return $true
        }
        Description = "Test task for skip flag validation"
    }
    
    # Execute test task
    $result = & $testTask.Function
    
    if ($result -eq $true) {
        Write-Host "✓ PASS: Skip flag respected, task returned success" -ForegroundColor Green
    } else {
        Write-Host "✗ FAIL: Skip flag not handled correctly" -ForegroundColor Red
    }
    
    # Test 3: Task result tracking
    Write-Host "`nTest 3: Task result tracking" -ForegroundColor Yellow
    
    # Clear existing results
    $global:TaskResults = @{}
    
    # Execute a simple test task
    $testTaskName = "TestResultTracking_$(Get-Random)"
    $taskStartTime = Get-Date
    
    $testTask = @{
        Name = $testTaskName
        Function = {
            Start-Sleep -Milliseconds 100
            return $true
        }
        Description = "Test task for result tracking"
    }
    
    # Simulate task execution with result tracking
    $executionStart = Get-Date
    $taskResult = & $testTask.Function
    $executionEnd = Get-Date
    $duration = ($executionEnd - $executionStart).TotalSeconds
    
    $global:TaskResults[$testTaskName] = @{
        Success = $taskResult
        Duration = $duration
        Started = $executionStart
        Ended = $executionEnd
        Description = $testTask.Description
    }
    
    # Validate result structure
    $result = $global:TaskResults[$testTaskName]
    
    if ($result.Success -eq $true -and 
        $result.Duration -gt 0 -and 
        $result.Started -is [DateTime] -and 
        $result.Ended -is [DateTime]) {
        Write-Host "✓ PASS: Task result properly tracked with all required fields" -ForegroundColor Green
        Write-Host "  Duration: $($result.Duration)s, Success: $($result.Success)" -ForegroundColor Gray
    } else {
        Write-Host "✗ FAIL: Task result tracking incomplete or invalid" -ForegroundColor Red
    }
    
    # Test 4: Error propagation
    Write-Host "`nTest 4: Error propagation in task execution" -ForegroundColor Yellow
    
    $testTaskName = "TestErrorPropagation_$(Get-Random)"
    
    $testTask = @{
        Name = $testTaskName
        Function = {
            try {
                throw "Simulated task error"
            }
            catch {
                Write-Log "Task error caught: $_" 'ERROR'
                return $false
            }
        }
        Description = "Test task for error handling"
    }
    
    $taskResult = & $testTask.Function
    
    if ($taskResult -eq $false) {
        Write-Host "✓ PASS: Error properly caught and propagated" -ForegroundColor Green
    } else {
        Write-Host "✗ FAIL: Error not handled correctly" -ForegroundColor Red
    }
    
    Write-Host "`n=== Task Array Execution Test Complete ===" -ForegroundColor Cyan
}
```

#### Test Suite 6: Dependency Chain Validation

```powershell
function Test-DependencyChain {
    <#
    .SYNOPSIS
        Validate task dependencies and execution order
    .DESCRIPTION
        Tests that tasks execute in correct order and that
        dependent tasks have access to required resources
    #>
    
    Write-Host "`n=== Testing Dependency Chain ===" -ForegroundColor Cyan
    
    # Test 1: Global variable initialization order
    Write-Host "`nTest 1: Global variable initialization" -ForegroundColor Yellow
    
    $requiredGlobals = @(
        @{ Name = 'Config'; Type = [hashtable] },
        @{ Name = 'ScriptTasks'; Type = [array] },
        @{ Name = 'TaskResults'; Type = [hashtable] },
        @{ Name = 'TempFolder'; Type = [string] },
        @{ Name = 'AppCategories'; Type = [hashtable] },
        @{ Name = 'PackageManagers'; Type = [hashtable] }
    )
    
    $passCount = 0
    foreach ($global in $requiredGlobals) {
        $varName = "global:$($global.Name)"
        $value = Get-Variable -Name $global.Name -Scope Global -ValueOnly -ErrorAction SilentlyContinue
        
        if ($value) {
            if ($value.GetType() -eq $global.Type -or $value -is $global.Type) {
                Write-Host "  ✓ `$global:$($global.Name) initialized correctly" -ForegroundColor Green
                $passCount++
            } else {
                Write-Host "  ✗ `$global:$($global.Name) has wrong type: Expected $($global.Type), Got $($value.GetType())" -ForegroundColor Red
            }
        } else {
            Write-Host "  ✗ `$global:$($global.Name) not initialized" -ForegroundColor Red
        }
    }
    
    if ($passCount -eq $requiredGlobals.Count) {
        Write-Host "✓ PASS: All global variables properly initialized" -ForegroundColor Green
    } else {
        Write-Host "✗ PARTIAL: $passCount/$($requiredGlobals.Count) globals initialized correctly" -ForegroundColor Yellow
    }
    
    # Test 2: Logging infrastructure availability
    Write-Host "`nTest 2: Logging infrastructure" -ForegroundColor Yellow
    
    $loggingFunctions = @('Write-Log', 'Write-ActionLog', 'Write-CommandLog', 'Write-TaskProgress', 'Write-ActionProgress')
    $availableFunctions = 0
    
    foreach ($func in $loggingFunctions) {
        if (Get-Command $func -ErrorAction SilentlyContinue) {
            $availableFunctions++
        } else {
            Write-Host "  ✗ Function '$func' not available" -ForegroundColor Red
        }
    }
    
    if ($availableFunctions -eq $loggingFunctions.Count) {
        Write-Host "✓ PASS: All logging functions available ($availableFunctions/$($loggingFunctions.Count))" -ForegroundColor Green
    } else {
        Write-Host "✗ FAIL: Some logging functions missing ($availableFunctions/$($loggingFunctions.Count))" -ForegroundColor Red
    }
    
    # Test 3: Package manager availability check
    Write-Host "`nTest 3: Package manager availability" -ForegroundColor Yellow
    
    $pmCount = 0
    if (Test-CommandAvailable 'winget') {
        Write-Host "  ✓ Winget available" -ForegroundColor Green
        $pmCount++
    } else {
        Write-Host "  ⚠ Winget not available" -ForegroundColor Yellow
    }
    
    if (Test-CommandAvailable 'choco') {
        Write-Host "  ✓ Chocolatey available" -ForegroundColor Green
        $pmCount++
    } else {
        Write-Host "  ⚠ Chocolatey not available" -ForegroundColor Yellow
    }
    
    if ($pmCount -gt 0) {
        Write-Host "✓ PASS: At least one package manager available" -ForegroundColor Green
    } else {
        Write-Host "⚠ WARN: No package managers available (some features will be limited)" -ForegroundColor Yellow
    }
    
    Write-Host "`n=== Dependency Chain Test Complete ===" -ForegroundColor Cyan
}
```

---

### Level 3: System Testing

#### Test Suite 7: Full Script Execution

```powershell
function Test-FullScriptExecution {
    <#
    .SYNOPSIS
        Test complete script execution in various scenarios
    .DESCRIPTION
        Simulates full script runs with different configurations
        and validates end-to-end functionality
    #>
    
    Write-Host "`n=== Testing Full Script Execution ===" -ForegroundColor Cyan
    
    # Test 1: Dry-run mode (all tasks skipped)
    Write-Host "`nTest 1: Dry-run mode execution" -ForegroundColor Yellow
    
    # Backup original config
    $originalConfig = $global:Config.Clone()
    
    # Enable all skip flags
    $global:Config.SkipBloatwareRemoval = $true
    $global:Config.SkipEssentialApps = $true
    $global:Config.SkipWindowsUpdates = $true
    $global:Config.SkipTelemetryDisable = $true
    $global:Config.SkipSystemRestore = $true
    
    # Simulate task execution
    $tasksExecuted = 0
    $tasksSkipped = 0
    
    foreach ($task in $global:ScriptTasks) {
        $taskName = $task.Name
        $skipFlag = "Skip$taskName"
        
        if ($global:Config.ContainsKey($skipFlag) -and $global:Config[$skipFlag]) {
            $tasksSkipped++
        } else {
            $tasksExecuted++
        }
    }
    
    Write-Host "✓ Dry-run complete: $tasksExecuted executed, $tasksSkipped skipped" -ForegroundColor $(if($tasksSkipped -gt 0){'Green'}else{'Yellow'})
    
    # Restore original config
    $global:Config = $originalConfig
    
    # Test 2: Execution timing analysis
    Write-Host "`nTest 2: Execution timing analysis" -ForegroundColor Yellow
    
    $timingTests = @(
        @{ Name = 'Fast Task'; Duration = 0.1 },
        @{ Name = 'Medium Task'; Duration = 1.0 },
        @{ Name = 'Slow Task'; Duration = 3.0 }
    )
    
    foreach ($test in $timingTests) {
        $start = Get-Date
        Start-Sleep -Seconds $test.Duration
        $end = Get-Date
        $actualDuration = ($end - $start).TotalSeconds
        
        $tolerance = 0.5  # 500ms tolerance
        if ([Math]::Abs($actualDuration - $test.Duration) -lt $tolerance) {
            Write-Host "  ✓ $($test.Name): $actualDuration s (expected $($test.Duration)s)" -ForegroundColor Green
        } else {
            Write-Host "  ⚠ $($test.Name): $actualDuration s (expected $($test.Duration)s, outside tolerance)" -ForegroundColor Yellow
        }
    }
    
    # Test 3: Log file creation and rotation
    Write-Host "`nTest 3: Log file handling" -ForegroundColor Yellow
    
    $testLogPath = Join-Path $env:TEMP "test_execution_$(Get-Random).log"
    $global:LogFile = $testLogPath
    
    try {
        # Write test entries
        Write-Log "Test execution start" 'INFO'
        Write-ActionLog -Action "Test Action" -Details "Test" -Category "Task Execution" -Status 'START'
        Write-Log "Test execution end" 'SUCCESS'
        
        # Verify log file
        if (Test-Path $testLogPath) {
            $logSize = (Get-Item $testLogPath).Length
            $logLines = (Get-Content $testLogPath).Count
            
            if ($logSize -gt 0 -and $logLines -ge 3) {
                Write-Host "✓ PASS: Log file created successfully ($logSize bytes, $logLines lines)" -ForegroundColor Green
            } else {
                Write-Host "✗ FAIL: Log file invalid (Size: $logSize, Lines: $logLines)" -ForegroundColor Red
            }
        } else {
            Write-Host "✗ FAIL: Log file not created" -ForegroundColor Red
        }
    }
    finally {
        if (Test-Path $testLogPath) {
            Remove-Item $testLogPath -Force -ErrorAction SilentlyContinue
        }
    }
    
    Write-Host "`n=== Full Script Execution Test Complete ===" -ForegroundColor Cyan
}
```

---

### Level 4: Performance Testing

#### Test Suite 8: Performance Benchmarking

```powershell
function Test-PerformanceBenchmarks {
    <#
    .SYNOPSIS
        Benchmark critical operations for performance analysis
    .DESCRIPTION
        Measures execution time and resource usage for key operations
    #>
    
    Write-Host "`n=== Performance Benchmarking ===" -ForegroundColor Cyan
    
    # Test 1: Bloatware detection speed
    Write-Host "`nTest 1: Bloatware detection performance" -ForegroundColor Yellow
    
    $detectionMethods = @(
        @{ Name = 'AppX Packages'; Code = { Get-AppxPackage -AllUsers | Select-Object -First 10 } },
        @{ Name = 'Registry Scan'; Code = { Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*" | Select-Object -First 10 } },
        @{ Name = 'DISM Provisioned'; Code = { Get-AppxProvisionedPackage -Online | Select-Object -First 10 } }
    )
    
    foreach ($method in $detectionMethods) {
        try {
            $measurement = Measure-Command { & $method.Code }
            $duration = $measurement.TotalMilliseconds
            
            $performanceRating = if ($duration -lt 1000) { "Excellent" }
                               elseif ($duration -lt 3000) { "Good" }
                               elseif ($duration -lt 5000) { "Acceptable" }
                               else { "Slow" }
            
            $color = if ($performanceRating -eq "Excellent" -or $performanceRating -eq "Good") { "Green" }
                    elseif ($performanceRating -eq "Acceptable") { "Yellow" }
                    else { "Red" }
            
            Write-Host "  $($method.Name): $([Math]::Round($duration, 2))ms - $performanceRating" -ForegroundColor $color
        }
        catch {
            Write-Host "  $($method.Name): Failed - $_" -ForegroundColor Red
        }
    }
    
    # Test 2: Logging performance
    Write-Host "`nTest 2: Logging system performance" -ForegroundColor Yellow
    
    $testLogPath = Join-Path $env:TEMP "perf_test_$(Get-Random).log"
    $global:LogFile = $testLogPath
    
    try {
        $logCount = 100
        $measurement = Measure-Command {
            for ($i = 0; $i -lt $logCount; $i++) {
                Write-Log "Performance test log entry $i" 'INFO'
            }
        }
        
        $avgTimePerLog = $measurement.TotalMilliseconds / $logCount
        
        if ($avgTimePerLog -lt 5) {
            Write-Host "  ✓ Excellent: $([Math]::Round($avgTimePerLog, 2))ms per log entry" -ForegroundColor Green
        } elseif ($avgTimePerLog -lt 10) {
            Write-Host "  ✓ Good: $([Math]::Round($avgTimePerLog, 2))ms per log entry" -ForegroundColor Yellow
        } else {
            Write-Host "  ⚠ Slow: $([Math]::Round($avgTimePerLog, 2))ms per log entry" -ForegroundColor Red
        }
    }
    finally {
        if (Test-Path $testLogPath) {
            Remove-Item $testLogPath -Force -ErrorAction SilentlyContinue
        }
    }
    
    # Test 3: Memory usage monitoring
    Write-Host "`nTest 3: Memory usage analysis" -ForegroundColor Yellow
    
    $process = Get-Process -Id $PID
    $memoryMB = [Math]::Round($process.WorkingSet64 / 1MB, 2)
    $peakMemoryMB = [Math]::Round($process.PeakWorkingSet64 / 1MB, 2)
    
    Write-Host "  Current Memory: $memoryMB MB" -ForegroundColor Cyan
    Write-Host "  Peak Memory: $peakMemoryMB MB" -ForegroundColor Cyan
    
    if ($memoryMB -lt 200) {
        Write-Host "  ✓ Memory usage: Excellent (< 200 MB)" -ForegroundColor Green
    } elseif ($memoryMB -lt 500) {
        Write-Host "  ✓ Memory usage: Good (< 500 MB)" -ForegroundColor Yellow
    } else {
        Write-Host "  ⚠ Memory usage: High (> 500 MB)" -ForegroundColor Red
    }
    
    Write-Host "`n=== Performance Benchmarking Complete ===" -ForegroundColor Cyan
}
```

---

### Level 5: Regression Testing

#### Test Suite 9: Configuration Change Validation

```powershell
function Test-ConfigurationChanges {
    <#
    .SYNOPSIS
        Validate configuration changes don't break functionality
    .DESCRIPTION
        Tests that modifying configuration values works as expected
    #>
    
    Write-Host "`n=== Testing Configuration Changes ===" -ForegroundColor Cyan
    
    # Test 1: Custom bloatware list addition
    Write-Host "`nTest 1: Custom bloatware list modification" -ForegroundColor Yellow
    
    $originalList = $global:Config.CustomBloatwareList
    $testPattern = "TestApp_$(Get-Random).*"
    
    $global:Config.CustomBloatwareList += @($testPattern)
    
    if ($global:Config.CustomBloatwareList -contains $testPattern) {
        Write-Host "✓ PASS: Custom bloatware pattern added successfully" -ForegroundColor Green
    } else {
        Write-Host "✗ FAIL: Custom bloatware pattern not added" -ForegroundColor Red
    }
    
    # Restore original list
    $global:Config.CustomBloatwareList = $originalList
    
    # Test 2: Skip flag toggling
    Write-Host "`nTest 2: Skip flag configuration" -ForegroundColor Yellow
    
    $skipFlags = @(
        'SkipBloatwareRemoval',
        'SkipEssentialApps',
        'SkipWindowsUpdates',
        'SkipTelemetryDisable'
    )
    
    $flagsWorking = 0
    foreach ($flag in $skipFlags) {
        if ($global:Config.ContainsKey($flag)) {
            $originalValue = $global:Config[$flag]
            
            # Toggle flag
            $global:Config[$flag] = -not $originalValue
            
            # Verify change
            if ($global:Config[$flag] -ne $originalValue) {
                $flagsWorking++
            }
            
            # Restore original
            $global:Config[$flag] = $originalValue
        }
    }
    
    if ($flagsWorking -eq $skipFlags.Count) {
        Write-Host "✓ PASS: All skip flags configurable ($flagsWorking/$($skipFlags.Count))" -ForegroundColor Green
    } else {
        Write-Host "✗ PARTIAL: $flagsWorking/$($skipFlags.Count) skip flags working" -ForegroundColor Yellow
    }
    
    Write-Host "`n=== Configuration Changes Test Complete ===" -ForegroundColor Cyan
}
```

---

### Test Automation Framework

#### Master Test Runner

```powershell
function Invoke-AllTests {
    <#
    .SYNOPSIS
        Execute all test suites and generate comprehensive report
    .DESCRIPTION
        Runs all unit, integration, system, performance, and regression tests
        and produces a detailed test report with pass/fail statistics
    #>
    
    Write-Host "`n╔═══════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║     Windows Maintenance Script - Test Suite Runner       ║" -ForegroundColor Cyan
    Write-Host "╚═══════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan
    
    $testStartTime = Get-Date
    $testResults = @{}
    
    # Level 1: Unit Tests
    Write-Host "`n┌─────────────────────────────────────────────────────────┐" -ForegroundColor Yellow
    Write-Host "│ LEVEL 1: UNIT TESTING                                   │" -ForegroundColor Yellow
    Write-Host "└─────────────────────────────────────────────────────────┘" -ForegroundColor Yellow
    
    $testSuites = @(
        @{ Name = 'Logging Functions'; Function = 'Test-LoggingFunctions' },
        @{ Name = 'Registry Operations'; Function = 'Test-RegistryOperations' },
        @{ Name = 'Package Manager Abstraction'; Function = 'Test-PackageManagerAbstraction' },
        @{ Name = 'Bloatware Detection'; Function = 'Test-BloatwareDetection' }
    )
    
    foreach ($suite in $testSuites) {
        try {
            $suiteStart = Get-Date
            & $suite.Function
            $suiteEnd = Get-Date
            $duration = ($suiteEnd - $suiteStart).TotalSeconds
            
            $testResults[$suite.Name] = @{
                Status = 'PASS'
                Duration = $duration
            }
        }
        catch {
            $testResults[$suite.Name] = @{
                Status = 'FAIL'
                Error = $_.Exception.Message
            }
            Write-Host "`n✗ $($suite.Name) FAILED: $_" -ForegroundColor Red
        }
    }
    
    # Level 2: Integration Tests
    Write-Host "`n┌─────────────────────────────────────────────────────────┐" -ForegroundColor Yellow
    Write-Host "│ LEVEL 2: INTEGRATION TESTING                            │" -ForegroundColor Yellow
    Write-Host "└─────────────────────────────────────────────────────────┘" -ForegroundColor Yellow
    
    try {
        Test-TaskArrayExecution
        Test-DependencyChain
    }
    catch {
        Write-Host "✗ Integration tests failed: $_" -ForegroundColor Red
    }
    
    # Level 3: System Tests
    Write-Host "`n┌─────────────────────────────────────────────────────────┐" -ForegroundColor Yellow
    Write-Host "│ LEVEL 3: SYSTEM TESTING                                 │" -ForegroundColor Yellow
    Write-Host "└─────────────────────────────────────────────────────────┘" -ForegroundColor Yellow
    
    try {
        Test-FullScriptExecution
    }
    catch {
        Write-Host "✗ System tests failed: $_" -ForegroundColor Red
    }
    
    # Level 4: Performance Tests
    Write-Host "`n┌─────────────────────────────────────────────────────────┐" -ForegroundColor Yellow
    Write-Host "│ LEVEL 4: PERFORMANCE TESTING                            │" -ForegroundColor Yellow
    Write-Host "└─────────────────────────────────────────────────────────┘" -ForegroundColor Yellow
    
    try {
        Test-PerformanceBenchmarks
    }
    catch {
        Write-Host "✗ Performance tests failed: $_" -ForegroundColor Red
    }
    
    # Level 5: Regression Tests
    Write-Host "`n┌─────────────────────────────────────────────────────────┐" -ForegroundColor Yellow
    Write-Host "│ LEVEL 5: REGRESSION TESTING                             │" -ForegroundColor Yellow
    Write-Host "└─────────────────────────────────────────────────────────┘" -ForegroundColor Yellow
    
    try {
        Test-ConfigurationChanges
    }
    catch {
        Write-Host "✗ Regression tests failed: $_" -ForegroundColor Red
    }
    
    # Generate final report
    $testEndTime = Get-Date
    $totalDuration = ($testEndTime - $testStartTime).TotalSeconds
    
    Write-Host "`n╔═══════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║                    TEST SUMMARY REPORT                    ║" -ForegroundColor Cyan
    Write-Host "╚═══════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan
    
    $passCount = ($testResults.Values | Where-Object { $_.Status -eq 'PASS' }).Count
    $failCount = ($testResults.Values | Where-Object { $_.Status -eq 'FAIL' }).Count
    $totalTests = $testResults.Count
    
    Write-Host "Total Tests: $totalTests" -ForegroundColor Cyan
    Write-Host "Passed: $passCount" -ForegroundColor Green
    Write-Host "Failed: $failCount" -ForegroundColor $(if($failCount -eq 0){'Green'}else{'Red'})
    Write-Host "Total Duration: $([Math]::Round($totalDuration, 2))s`n" -ForegroundColor Cyan
    
    # Detailed results
    Write-Host "Detailed Results:" -ForegroundColor Yellow
    foreach ($test in $testResults.Keys | Sort-Object) {
        $result = $testResults[$test]
        $symbol = if ($result.Status -eq 'PASS') { '✓' } else { '✗' }
        $color = if ($result.Status -eq 'PASS') { 'Green' } else { 'Red' }
        
        if ($result.Duration) {
            Write-Host "  $symbol $test - $($result.Status) ($([Math]::Round($result.Duration, 2))s)" -ForegroundColor $color
        } else {
            Write-Host "  $symbol $test - $($result.Status)" -ForegroundColor $color
            if ($result.Error) {
                Write-Host "    Error: $($result.Error)" -ForegroundColor Red
            }
        }
    }
    
    Write-Host "`n╚═══════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan
    
    return $testResults
}
```

**Dry-Run Mode** (Test detection without changes):
```powershell
# Test bloatware detection only
function Test-BloatwareDetectionOnly {
    $global:Config.SkipBloatwareRemoval = $true  # Skip removal
    
    # Run detection
    $detected = Get-DetectedBloatware
    
    # Display results
    $detected | Format-Table Name, Source, Version | Out-String | Write-Log 'INFO'
    
    Write-Log "Detected $($detected.Count) bloatware apps (no removal performed)" 'INFO'
}
```

### Log Analysis

**Primary Log Location**:
```
maintenance.log (script directory)
```

**Log Inheritance**: PowerShell script inherits log path from batch launcher via `$env:SCRIPT_LOG_FILE`

**Search Patterns for Common Issues**:

| Pattern | Purpose | Command |
|---------|---------|---------|
| `[ERROR]` | Critical failures | `Select-String -Path maintenance.log -Pattern '\[ERROR\]'` |
| `[WARN]` | Warning conditions | `Select-String -Path maintenance.log -Pattern '\[WARN\]'` |
| `[ACTION]` | Task boundaries | `Select-String -Path maintenance.log -Pattern '\[ACTION\]'` |
| `[COMMAND]` | External processes | `Select-String -Path maintenance.log -Pattern '\[COMMAND\]'` |
| `Duration:` | Timing information | `Select-String -Path maintenance.log -Pattern 'Duration:'` |
| `ExitCode:` | Process exit codes | `Select-String -Path maintenance.log -Pattern 'ExitCode:'` |

**Analyze Task Performance**:
```powershell
# Extract task durations from log
$logContent = Get-Content maintenance.log
$taskDurations = $logContent | Select-String -Pattern 'Duration: ([\d.]+)s' | ForEach-Object {
    [PSCustomObject]@{
        Line = $_.Line
        Duration = [decimal]$_.Matches[0].Groups[1].Value
    }
}

$taskDurations | Sort-Object Duration -Descending | Format-Table -AutoSize
```

**Error Context Extraction**:
```powershell
# Find errors with surrounding context
Select-String -Path maintenance.log -Pattern '\[ERROR\]' -Context 3,3
# Shows 3 lines before and after each error
```

### Debug Mode Execution

**Enable Verbose Logging**:
```powershell
$global:Config.EnableVerboseLogging = $true

# Or set environment variable before launching
$env:VERBOSE_LOGGING = "true"
.\script.ps1
```

**Trace Specific Component**:
```powershell
# Add debug output to specific function
function Invoke-MyTask {
    $DebugPreference = 'Continue'  # Enable debug output
    
    Write-Debug "Starting task with params: $params"
    # ... task logic ...
    Write-Debug "Task completed with result: $result"
}
```

**PowerShell Transcript**:
```powershell
# Capture all console output
Start-Transcript -Path "C:\Logs\maintenance_transcript.txt"
.\script.ps1
Stop-Transcript
```

### Common Issues & Solutions

#### Issue 1: "PowerShell script not found"

**Symptom**: Batch launcher cannot locate script.ps1

**Diagnosis**:
```batch
REM Check PS1_PATH variable
ECHO PS1_PATH: %PS1_PATH%

REM Check working directory
ECHO WORKING_DIR: %WORKING_DIR%

REM List directory contents
DIR "%WORKING_DIR%" /B
```

**Common Causes**:
- Repository extraction failed
- Script running from unexpected location
- Network path access issues

**Solution**:
```batch
REM Lines 600-700 in script.bat - Path detection logic
REM Ensure WORKING_DIR is correctly set
REM Check for script.ps1 in both current directory and extracted folder
```

---

#### Issue 2: Registry Access Failures

**Symptom**: Registry modifications fail despite admin privileges

**Diagnosis**:
```powershell
# Test specific registry path access
$path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"
$access = Test-RegistryAccess -RegistryPath $path -CreatePath

if (-not $access.Success) {
    Write-Log "Access denied: $($access.Error)" 'ERROR'
    Write-Log "Suggestion: $($access.Suggestion)" 'WARN'
    Write-Log "Error type: $($access.ErrorType)" 'INFO'
}
```

**Common Causes**:
- Group Policy restrictions
- Insufficient privileges (not running as admin)
- Registry path does not exist and CreatePath not used
- Registry key ownership issues

**Solutions**:
1. Verify admin elevation: `([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)`
2. Use fallback paths (HKCU instead of HKLM)
3. Check Group Policy settings: `gpedit.msc`
4. Take ownership of registry key (advanced)

---

#### Issue 3: Package Manager Timeouts

**Symptom**: Winget/Chocolatey installations timeout or hang

**Diagnosis**:
```powershell
# Check package manager availability
Test-CommandAvailable 'winget'  # Should return $true
Test-CommandAvailable 'choco'   # Should return $true

# Test package manager directly
winget --version
choco --version

# Check network connectivity
Test-NetConnection -ComputerName "winget.azureedge.net" -Port 443
```

**Common Causes**:
- Network connectivity issues
- Package manager not properly installed
- Corrupted package cache
- Antivirus blocking
- Default timeout too short

**Solutions**:
```powershell
# Increase timeout in $global:SystemSettings
$global:SystemSettings.Timeouts.PackageManager = 600  # 10 minutes

# Clear package caches
winget source reset --force
choco cache clean

# Bypass proxy if needed
$env:HTTP_PROXY = ""
$env:HTTPS_PROXY = ""
```

---

#### Issue 4: Scheduled Task Not Running

**Symptom**: Monthly scheduled task doesn't execute

**Diagnosis**:
```batch
REM Check if task exists
schtasks /Query /TN "ScriptMentenantaMonthly"

REM View detailed task info
schtasks /Query /TN "ScriptMentenantaMonthly" /V /FO LIST

REM Check task history
REM Open Task Scheduler GUI → View → Show Hidden Tasks → Microsoft → Windows → ScriptMentenanta
```

**Common Causes**:
- Task created with wrong account (not SYSTEM)
- Script path incorrect
- Task disabled
- System was off/sleeping during scheduled time

**Solutions**:
```batch
REM Recreate task with correct settings (lines 350-450 in script.bat)
schtasks /Delete /TN "ScriptMentenantaMonthly" /F
schtasks /Create /SC MONTHLY /MO 1 /TN "ScriptMentenantaMonthly" ^
    /TR "%SCHEDULED_TASK_SCRIPT_PATH%" /ST 01:00 /RL HIGHEST /RU SYSTEM /F

REM Test task manually
schtasks /Run /TN "ScriptMentenantaMonthly"
```

---

#### Issue 5: Bloatware Detection Misses Apps

**Symptom**: Known bloatware not detected or removed

**Diagnosis**:
```powershell
# Check all detection methods
Write-Log "=== AppX Detection ===" 'INFO'
Get-AppxPackage -AllUsers | Where-Object { $_.Name -like '*Xbox*' } | Format-Table Name, Version

Write-Log "=== Registry Detection ===" 'INFO'
$registry = Get-RegistryUninstallBloatware -BloatwarePatterns @('Xbox')
$registry | Format-Table DisplayName, Version

Write-Log "=== Winget Detection ===" 'INFO'
winget list | Select-String 'Xbox'

Write-Log "=== Windows Capabilities ===" 'INFO'
Get-WindowsCapability -Online | Where-Object { $_.Name -like '*Xbox*' }
```

**Common Causes**:
- App installed via method not covered by patterns
- Pattern doesn't match actual app name
- App protected by system policy
- Different app version/name variant

**Solutions**:
```powershell
# Add custom detection pattern
$global:Config.CustomBloatwareList += @(
    'Exact.App.Name',
    'WildCard.*Pattern',
    '*Partial*Match*'
)

# Test specific app removal
Remove-AppxPackage -Package "ExactPackageName" -AllUsers
```

---

## Best Practices

### Code Organization

**Function Structure**:
```powershell
function Verb-Noun {
    <#
    .SYNOPSIS
        One-line description
    
    .DESCRIPTION
        Detailed explanation
    
    .PARAMETER ParamName
        Parameter description
    
    .EXAMPLE
        Verb-Noun -ParamName "Value"
    #>
    
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ParamName
    )
    
    try {
        Write-ActionLog -Action "Operation" -Status 'START'
        # Logic here
        Write-ActionLog -Action "Operation" -Status 'SUCCESS'
        return $result
    }
    catch {
        Write-ActionLog -Action "Operation" -Status 'FAILURE'
        return $false
    }
}
```

**Variable Naming**:
- **Local variables**: `$camelCase`
- **Parameters**: `$PascalCase`
- **Global variables**: `$global:PascalCase`
- **Constants**: `$ALL_CAPS` (if truly constant)

**Comments**:
```powershell
# Single-line comment for simple explanations

<#
Multi-line comment block for complex logic:
- Purpose: What this block does
- Dependencies: Required resources
- Side-effects: State changes
#>
```

### Performance Optimization

**Use HashSets for Lookups**:
```powershell
# Slow - O(n) for each lookup
$apps | Where-Object { $bloatwareList -contains $_.Name }

# Fast - O(1) for each lookup
$bloatwareSet = [System.Collections.Generic.HashSet[string]]::new($bloatwareList)
$apps | Where-Object { $bloatwareSet.Contains($_.Name) }
```

**Batch Operations**:
```powershell
# Slow - individual operations
foreach ($app in $apps) {
    Remove-AppxPackage -Package $app
}

# Faster - batch where possible
$apps | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
```

**Cache Expensive Operations**:
```powershell
# Cache system inventory (called once)
if ($null -eq $global:SystemInventory) {
    $global:SystemInventory = Get-SystemInventory
}

# Reuse cached data
$osVersion = $global:SystemInventory.OSVersion
```

**Use Int64 for File Sizes**:
```powershell
$sizeBytes = (Get-ChildItem $path -Recurse -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
if ($null -eq $sizeBytes) { $sizeBytes = 0 }
$sizeMB = [math]::Round([int64]$sizeBytes / 1MB, 2)
```
- Always cast to `[int64]` before arithmetic to prevent `System.Int32` overflow when folders exceed ~2 GB.
- Apply the same pattern when computing deltas:
```powershell
$deltaBytes = [System.Math]::Max(
    [System.Convert]::ToInt64(0),
    [System.Convert]::ToInt64($beforeBytes - $afterBytes)
)
```

### Security Considerations

**Validate User Input**:
```powershell
function Install-Application {
    param(
        [ValidatePattern('^[a-zA-Z0-9\._-]+$')]
        [string]$AppId
    )
    
    # AppId validated before use
}
```

**Secure Command Execution**:
```powershell
# Use Invoke-LoggedCommand instead of direct Start-Process
$result = Invoke-LoggedCommand -FilePath "executable" -ArgumentList @('arg1', 'arg2')

# Never use Invoke-Expression with user input
# BAD: Invoke-Expression "winget install $userInput"
# GOOD: Invoke-LoggedCommand -FilePath 'winget' -ArgumentList @('install', $userInput)
```

**Registry Safety**:
```powershell
# Always test before modify
$access = Test-RegistryAccess -RegistryPath $path
if ($access.Success) {
    Set-RegistryValueSafely -RegistryPath $path -ValueName $name -Value $value
}
```

### Logging Best Practices

**DO**:
- ✅ Log task start/completion with timing
- ✅ Log errors with full context
- ✅ Use appropriate log levels (INFO, WARN, ERROR)
- ✅ Include relevant details (paths, values, exit codes)
- ✅ Log external command execution

**DON'T**:
- ❌ Log every percentage update (use progress bars)
- ❌ Log sensitive information (passwords, keys)
- ❌ Use Write-Host without Write-Log
- ❌ Create excessive log entries (>1000 per task)
- ❌ Log in tight loops without throttling

### Error Handling Patterns

**Recoverable Errors**:
```powershell
try {
    $result = Invoke-Operation
} catch {
    Write-Log "Operation failed, using fallback: $_" 'WARN'
    $result = Invoke-FallbackOperation
}
```

**Critical Errors**:
```powershell
try {
    $resource = Get-CriticalResource
    if (-not $resource) { throw "Critical resource unavailable" }
} catch {
    Write-ActionLog -Action "FATAL" -Status 'FAILURE'
    throw  # Re-throw to stop execution
}
```

**Silent Failures** (for optional features):
```powershell
try {
    Enable-OptionalFeature -ErrorAction Stop
} catch {
    Write-Log "Optional feature unavailable: $_" 'DEBUG'
    # Continue without feature
}
```

---

## Reference Tables

### Global Variables Reference

| Variable | Type | Purpose | Scope |
|----------|------|---------|-------|
| `$global:Config` | Hashtable | Configuration flags and lists | Script-wide |
| `$global:ScriptTasks` | Array | Task definitions | Task orchestrator |
| `$global:TaskResults` | Hashtable | Task execution results | Reporting |
| `$global:SystemInventory` | Hashtable | Cached system information | Multiple tasks |
| `$global:TempFolder` | String | Temporary file location | File operations |
| `$global:AppCategories` | Hashtable | Bloatware definitions | Bloatware detection |
| `$global:EssentialCategories` | Hashtable | Essential app definitions | App installation |
| `$global:PackageManagers` | Hashtable | Package manager configs | Package operations |
| `$global:SystemSettings` | Hashtable | Timeouts, paths, reboot tracking | System operations |
| `$global:BloatwareList` | Array | Compiled bloatware patterns | Detection engine |
| `$global:EssentialApps` | Array | Compiled essential apps | Installation engine |

### File Locations

| File | Path | Purpose |
|------|------|---------|
| `script.bat` | Repository root | Batch launcher |
| `script.ps1` | Repository root | PowerShell orchestrator |
| `maintenance.log` | Repository root (or `$env:SCRIPT_LOG_FILE`) | Primary log file |
| `temp_files/` | Repository root | Temporary downloads |
| `.github/copilot-instructions.md` | `.github` folder | This documentation |

### Exit Codes

| Code | Meaning | Source |
|------|---------|--------|
| 0 | Success | Both scripts |
| 1 | General error | Both scripts |
| 3 | Missing dependencies | script.bat |
| 5 | PowerShell unavailable | script.bat |
| 6 | script.ps1 not found | script.bat |
| 7 | Admin privileges required | script.bat |

### Package Manager Comparison

| Feature | Winget | Chocolatey |
|---------|--------|-----------|
| **Installation** | Built-in (Windows 11) or auto-installed | Requires manual install |
| **Speed** | Fast (native) | Moderate (PowerShell) |
| **App Coverage** | Modern apps | Legacy + Modern |
| **Silent Install** | `--silent` | `-y` |
| **Upgrade All** | `upgrade --all` | `upgrade all` |
| **Source** | Microsoft Store + Community | Community packages |
| **Preference** | Primary | Fallback |

### Task Execution Order

| Order | Task Name | Purpose | Can Skip? |
|-------|-----------|---------|-----------|
| 1 | SystemRestoreProtection | Create restore point | Yes |
| 2 | SystemInventory | Collect system info | No |
| 3 | RemoveBloatware | Remove unwanted apps | Yes |
| 4 | InstallEssentialApps | Install required apps | Yes |
| 5 | UpdateAllPackages | Update installed packages | Yes |
| 6 | WindowsUpdateCheck | Install Windows updates | Yes |
| 7 | DisableTelemetry | Privacy optimization | Yes |
| 8 | TaskbarOptimization | UI cleanup | Yes |
| 9 | DesktopBackground | Wallpaper change | Yes |
| 10 | SecurityHardening | Security improvements | Yes |
| 11 | CleanTempAndDisk | Disk cleanup | No |
| 12 | SystemHealthRepair | DISM/SFC repair | Yes |
| 13 | PendingRestartCheck | Detect restart needs | Yes |

### Configuration Flags

| Flag | Default | Purpose |
|------|---------|---------|
| `SkipBloatwareRemoval` | `$false` | Skip bloatware removal |
| `SkipEssentialApps` | `$false` | Skip app installation |
| `SkipWindowsUpdates` | `$false` | Skip Windows Update |
| `SkipTelemetryDisable` | `$false` | Skip telemetry disable |
| `SkipSystemRestore` | `$false` | Skip restore point |
| `SkipSystemHealthRepair` | `$false` | Skip DISM/SFC |
| `SkipPendingRestartCheck` | `$false` | Skip restart check |
| `EnableVerboseLogging` | `$false` | Enable debug output |

---

---

## Code Analysis Methods

### Static Code Analysis

#### PowerShell Script Analyzer (PSScriptAnalyzer)

```powershell
# Install PSScriptAnalyzer if not present
if (-not (Get-Module -ListAvailable -Name PSScriptAnalyzer)) {
    Install-Module -Name PSScriptAnalyzer -Scope CurrentUser -Force
}

# Analyze script.ps1
$analysisResults = Invoke-ScriptAnalyzer -Path ".\script.ps1" -Recurse

# Display results by severity
$analysisResults | Group-Object Severity | Format-Table Count, Name

# Show detailed violations
$analysisResults | Format-Table Severity, RuleName, Line, Message -AutoSize

# Filter critical issues only
$criticalIssues = $analysisResults | Where-Object { $_.Severity -eq 'Error' -or $_.Severity -eq 'Warning' }
$criticalIssues | Format-List *

# Generate HTML report
$analysisResults | ConvertTo-Html -Property Severity, RuleName, Line, Message | 
    Out-File "analysis_report.html"
```

**Common Issues to Check**:
- Unapproved verbs in function names
- Missing parameter validation
- Hardcoded credentials
- Use of Invoke-Expression
- Missing error handling
- Performance anti-patterns

---

### Complexity Analysis

```powershell
function Get-FunctionComplexity {
    <#
    .SYNOPSIS
        Analyze function complexity metrics
    .DESCRIPTION
        Calculates cyclomatic complexity, parameter count, line count
        for all functions in script.ps1
    #>
    
    param([string]$ScriptPath = ".\script.ps1")
    
    $scriptContent = Get-Content $ScriptPath -Raw
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($scriptContent, [ref]$null, [ref]$null)
    
    $functions = $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    
    $complexityReport = foreach ($func in $functions) {
        $funcBody = $func.Body.Extent.Text
        
        # Count decision points (if, while, for, foreach, switch, case, catch)
        $ifCount = ([regex]::Matches($funcBody, '\bif\s*\(')).Count
        $whileCount = ([regex]::Matches($funcBody, '\bwhile\s*\(')).Count
        $forCount = ([regex]::Matches($funcBody, '\bfor\s*\(')).Count
        $foreachCount = ([regex]::Matches($funcBody, '\bforeach\s*\(')).Count
        $switchCount = ([regex]::Matches($funcBody, '\bswitch\s*\(')).Count
        $catchCount = ([regex]::Matches($funcBody, '\bcatch\s*\{')).Count
        
        $cyclomaticComplexity = 1 + $ifCount + $whileCount + $forCount + $foreachCount + $switchCount + $catchCount
        
        $lineCount = ($funcBody -split "`n").Count
        $paramCount = $func.Parameters.Count
        
        [PSCustomObject]@{
            Function = $func.Name
            Lines = $lineCount
            Parameters = $paramCount
            CyclomaticComplexity = $cyclomaticComplexity
            ComplexityRating = if ($cyclomaticComplexity -le 10) { 'Simple' }
                              elseif ($cyclomaticComplexity -le 20) { 'Moderate' }
                              elseif ($cyclomaticComplexity -le 50) { 'Complex' }
                              else { 'Very Complex' }
        }
    }
    
    # Display summary
    Write-Host "`n=== Function Complexity Analysis ===" -ForegroundColor Cyan
    $complexityReport | Sort-Object CyclomaticComplexity -Descending | Format-Table -AutoSize
    
    # Identify high-complexity functions
    $highComplexity = $complexityReport | Where-Object { $_.CyclomaticComplexity -gt 20 }
    if ($highComplexity) {
        Write-Host "`n⚠ High Complexity Functions (Consider Refactoring):" -ForegroundColor Yellow
        $highComplexity | Format-Table Function, CyclomaticComplexity, Lines
    }
    
    return $complexityReport
}
```

---

### Code Coverage Analysis

```powershell
function Get-CodeCoverage {
    <#
    .SYNOPSIS
        Analyze code coverage from test execution
    .DESCRIPTION
        Uses Pester's code coverage feature to identify untested code paths
    #>
    
    param(
        [string]$ScriptPath = ".\script.ps1",
        [string]$TestPath = ".\tests\"
    )
    
    # Install Pester if needed
    if (-not (Get-Module -ListAvailable -Name Pester)) {
        Install-Module -Name Pester -Scope CurrentUser -Force -SkipPublisherCheck
    }
    
    Import-Module Pester -MinimumVersion 5.0
    
    # Configure code coverage
    $configuration = New-PesterConfiguration
    $configuration.Run.Path = $TestPath
    $configuration.CodeCoverage.Enabled = $true
    $configuration.CodeCoverage.Path = $ScriptPath
    $configuration.CodeCoverage.OutputFormat = 'JaCoCo'
    $configuration.CodeCoverage.OutputPath = 'coverage.xml'
    
    # Run tests with coverage
    $results = Invoke-Pester -Configuration $configuration
    
    # Display coverage summary
    Write-Host "`n=== Code Coverage Summary ===" -ForegroundColor Cyan
    Write-Host "Total Lines: $($results.CodeCoverage.NumberOfCommandsAnalyzed)" -ForegroundColor Cyan
    Write-Host "Covered Lines: $($results.CodeCoverage.NumberOfCommandsExecuted)" -ForegroundColor Green
    Write-Host "Missed Lines: $($results.CodeCoverage.NumberOfCommandsMissed)" -ForegroundColor Red
    
    $coveragePercent = ($results.CodeCoverage.NumberOfCommandsExecuted / $results.CodeCoverage.NumberOfCommandsAnalyzed) * 100
    Write-Host "Coverage: $([Math]::Round($coveragePercent, 2))%" -ForegroundColor $(if($coveragePercent -ge 80){'Green'}elseif($coveragePercent -ge 60){'Yellow'}else{'Red'})
    
    # Show missed commands
    if ($results.CodeCoverage.MissedCommands) {
        Write-Host "`n⚠ Uncovered Code Paths:" -ForegroundColor Yellow
        $results.CodeCoverage.MissedCommands | Select-Object File, Line, Function | Format-Table -AutoSize
    }
    
    return $results.CodeCoverage
}
```

---

### Dependency Analysis

```powershell
function Get-DependencyGraph {
    <#
    .SYNOPSIS
        Analyze function dependencies and call chains
    .DESCRIPTION
        Maps which functions call which other functions
    #>
    
    param([string]$ScriptPath = ".\script.ps1")
    
    $scriptContent = Get-Content $ScriptPath -Raw
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($scriptContent, [ref]$null, [ref]$null)
    
    $functions = $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    $functionNames = $functions | ForEach-Object { $_.Name }
    
    $dependencies = @{}
    
    foreach ($func in $functions) {
        $funcName = $func.Name
        $funcBody = $func.Body.Extent.Text
        
        $calledFunctions = $functionNames | Where-Object {
            $funcBody -match "\b$_\b"
        } | Where-Object { $_ -ne $funcName }
        
        $dependencies[$funcName] = $calledFunctions
    }
    
    # Display dependency tree
    Write-Host "`n=== Function Dependency Graph ===" -ForegroundColor Cyan
    foreach ($func in $dependencies.Keys | Sort-Object) {
        $calls = $dependencies[$func]
        if ($calls) {
            Write-Host "`n$func calls:" -ForegroundColor Yellow
            $calls | ForEach-Object { Write-Host "  → $_" -ForegroundColor Gray }
        }
    }
    
    # Identify orphaned functions (never called)
    $calledFunctions = $dependencies.Values | ForEach-Object { $_ } | Select-Object -Unique
    $orphans = $functionNames | Where-Object { $_ -notin $calledFunctions }
    
    if ($orphans) {
        Write-Host "`n⚠ Orphaned Functions (Never Called):" -ForegroundColor Yellow
        $orphans | ForEach-Object { Write-Host "  • $_" -ForegroundColor Red }
    }
    
    return $dependencies
}
```

---

### Security Analysis

```powershell
function Get-SecurityVulnerabilities {
    <#
    .SYNOPSIS
        Scan for common security vulnerabilities
    .DESCRIPTION
        Checks for hardcoded credentials, unsafe commands,
        SQL injection risks, etc.
    #>
    
    param([string]$ScriptPath = ".\script.ps1")
    
    $scriptContent = Get-Content $ScriptPath
    $vulnerabilities = @()
    
    # Check 1: Hardcoded credentials
    $credentialPatterns = @(
        @{ Pattern = 'password\s*=\s*["\'][^"\']+["\']'; Risk = 'HIGH'; Description = 'Hardcoded password' },
        @{ Pattern = 'apikey\s*=\s*["\'][^"\']+["\']'; Risk = 'HIGH'; Description = 'Hardcoded API key' },
        @{ Pattern = 'secret\s*=\s*["\'][^"\']+["\']'; Risk = 'HIGH'; Description = 'Hardcoded secret' }
    )
    
    foreach ($pattern in $credentialPatterns) {
        $lineNum = 0
        foreach ($line in $scriptContent) {
            $lineNum++
            if ($line -match $pattern.Pattern) {
                $vulnerabilities += [PSCustomObject]@{
                    Line = $lineNum
                    Risk = $pattern.Risk
                    Type = $pattern.Description
                    Code = $line.Trim()
                }
            }
        }
    }
    
    # Check 2: Unsafe commands
    $unsafeCommands = @(
        @{ Command = 'Invoke-Expression'; Risk = 'CRITICAL'; Description = 'Code injection risk' },
        @{ Command = 'iex '; Risk = 'CRITICAL'; Description = 'Code injection risk (alias)' },
        @{ Command = 'DownloadString'; Risk = 'HIGH'; Description = 'Unvalidated download' },
        @{ Command = '-ExecutionPolicy Bypass'; Risk = 'MEDIUM'; Description = 'Execution policy bypass' }
    )
    
    foreach ($cmd in $unsafeCommands) {
        $lineNum = 0
        foreach ($line in $scriptContent) {
            $lineNum++
            if ($line -match [regex]::Escape($cmd.Command)) {
                $vulnerabilities += [PSCustomObject]@{
                    Line = $lineNum
                    Risk = $cmd.Risk
                    Type = $cmd.Description
                    Code = $line.Trim()
                }
            }
        }
    }
    
    # Display results
    Write-Host "`n=== Security Vulnerability Scan ===" -ForegroundColor Cyan
    
    if ($vulnerabilities) {
        $vulnerabilities | Sort-Object Risk -Descending | Format-Table Line, Risk, Type, Code -Wrap
        
        $criticalCount = ($vulnerabilities | Where-Object { $_.Risk -eq 'CRITICAL' }).Count
        $highCount = ($vulnerabilities | Where-Object { $_.Risk -eq 'HIGH' }).Count
        
        Write-Host "`n⚠ Found $($vulnerabilities.Count) potential vulnerabilities:" -ForegroundColor Red
        if ($criticalCount -gt 0) { Write-Host "  • $criticalCount CRITICAL" -ForegroundColor Red }
        if ($highCount -gt 0) { Write-Host "  • $highCount HIGH" -ForegroundColor Yellow }
    } else {
        Write-Host "✓ No obvious vulnerabilities detected" -ForegroundColor Green
    }
    
    return $vulnerabilities
}
```

---

### Performance Profiling

```powershell
function Get-PerformanceProfile {
    <#
    .SYNOPSIS
        Profile script execution to identify bottlenecks
    .DESCRIPTION
        Measures time spent in each function during execution
    #>
    
    param([scriptblock]$ScriptBlock)
    
    $profiler = @{}
    
    # Wrap each function with timing
    $global:ProfilingEnabled = $true
    $global:ProfilingData = @{}
    
    # Execute script
    $totalStart = Get-Date
    try {
        & $ScriptBlock
    }
    finally {
        $totalEnd = Get-Date
    }
    
    $totalDuration = ($totalEnd - $totalStart).TotalSeconds
    
    # Analyze profiling data
    Write-Host "`n=== Performance Profile ===" -ForegroundColor Cyan
    Write-Host "Total Execution Time: $([Math]::Round($totalDuration, 2))s`n" -ForegroundColor Cyan
    
    if ($global:ProfilingData.Count -gt 0) {
        $sortedProfile = $global:ProfilingData.GetEnumerator() | 
            Sort-Object { $_.Value.TotalTime } -Descending |
            Select-Object -First 20
        
        Write-Host "Top 20 Time Consumers:" -ForegroundColor Yellow
        foreach ($entry in $sortedProfile) {
            $name = $entry.Key
            $data = $entry.Value
            $percent = ($data.TotalTime / $totalDuration) * 100
            
            Write-Host ("{0,-40} {1,8:N2}s ({2,5:N1}%) - {3} calls" -f $name, $data.TotalTime, $percent, $data.CallCount) -ForegroundColor Gray
        }
    }
    
    $global:ProfilingEnabled = $false
    return $global:ProfilingData
}
```

---

## Continuous Testing & Monitoring

### Automated Testing Pipeline

```powershell
function Start-ContinuousTesting {
    <#
    .SYNOPSIS
        Set up continuous testing with file watching
    .DESCRIPTION
        Monitors script files for changes and automatically runs tests
    #>
    
    param(
        [string]$WatchPath = ".",
        [string[]]$FileFilter = @("*.ps1", "*.psm1")
    )
    
    Write-Host "Starting continuous testing..." -ForegroundColor Cyan
    Write-Host "Watching: $WatchPath" -ForegroundColor Gray
    Write-Host "Press Ctrl+C to stop`n" -ForegroundColor Gray
    
    $watcher = New-Object System.IO.FileSystemWatcher
    $watcher.Path = $WatchPath
    $watcher.Filter = "*.ps1"
    $watcher.IncludeSubdirectories = $true
    $watcher.EnableRaisingEvents = $true
    
    $action = {
        $path = $Event.SourceEventArgs.FullPath
        $changeType = $Event.SourceEventArgs.ChangeType
        
        Write-Host "`n[$(Get-Date -Format 'HH:mm:ss')] File changed: $path" -ForegroundColor Yellow
        Write-Host "Running tests..." -ForegroundColor Cyan
        
        # Run relevant tests
        try {
            Invoke-AllTests
        }
        catch {
            Write-Host "✗ Test execution failed: $_" -ForegroundColor Red
        }
    }
    
    $handlers = @(
        Register-ObjectEvent -InputObject $watcher -EventName Changed -Action $action
        Register-ObjectEvent -InputObject $watcher -EventName Created -Action $action
    )
    
    try {
        while ($true) {
            Start-Sleep -Seconds 1
        }
    }
    finally {
        $handlers | ForEach-Object { Unregister-Event -SourceIdentifier $_.Name }
        $watcher.Dispose()
    }
}
```

---

### Test Report Generation

```powershell
function Export-TestReport {
    <#
    .SYNOPSIS
        Generate comprehensive test report in multiple formats
    .DESCRIPTION
        Exports test results to HTML, XML, and JSON formats
    #>
    
    param(
        [hashtable]$TestResults,
        [string]$OutputPath = ".\test_reports"
    )
    
    if (-not (Test-Path $OutputPath)) {
        New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
    }
    
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    
    # HTML Report
    $htmlReport = @"
<!DOCTYPE html>
<html>
<head>
    <title>Test Report - $timestamp</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        h1 { color: #333; }
        .pass { color: green; font-weight: bold; }
        .fail { color: red; font-weight: bold; }
        table { border-collapse: collapse; width: 100%; margin-top: 20px; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #4CAF50; color: white; }
        tr:nth-child(even) { background-color: #f2f2f2; }
    </style>
</head>
<body>
    <h1>Windows Maintenance Script - Test Report</h1>
    <p>Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>
    
    <h2>Summary</h2>
    <p>Total Tests: $($TestResults.Count)</p>
    <p>Passed: <span class='pass'>$(($TestResults.Values | Where-Object { $_.Status -eq 'PASS' }).Count)</span></p>
    <p>Failed: <span class='fail'>$(($TestResults.Values | Where-Object { $_.Status -eq 'FAIL' }).Count)</span></p>
    
    <h2>Detailed Results</h2>
    <table>
        <tr>
            <th>Test Name</th>
            <th>Status</th>
            <th>Duration (s)</th>
            <th>Details</th>
        </tr>
"@
    
    foreach ($test in $TestResults.Keys | Sort-Object) {
        $result = $TestResults[$test]
        $statusClass = if ($result.Status -eq 'PASS') { 'pass' } else { 'fail' }
        $duration = if ($result.Duration) { [Math]::Round($result.Duration, 2) } else { 'N/A' }
        $details = if ($result.Error) { $result.Error } else { '-' }
        
        $htmlReport += @"
        <tr>
            <td>$test</td>
            <td class='$statusClass'>$($result.Status)</td>
            <td>$duration</td>
            <td>$details</td>
        </tr>
"@
    }
    
    $htmlReport += @"
    </table>
</body>
</html>
"@
    
    $htmlPath = Join-Path $OutputPath "test_report_$timestamp.html"
    $htmlReport | Out-File $htmlPath -Encoding UTF8
    Write-Host "✓ HTML report: $htmlPath" -ForegroundColor Green
    
    # JSON Report
    $jsonPath = Join-Path $OutputPath "test_report_$timestamp.json"
    $TestResults | ConvertTo-Json -Depth 10 | Out-File $jsonPath -Encoding UTF8
    Write-Host "✓ JSON report: $jsonPath" -ForegroundColor Green
    
    # Open HTML report
    Start-Process $htmlPath
}
```

---

## Quick Reference Commands

```powershell
# ========== TESTING COMMANDS ==========

# Run all test suites
Invoke-AllTests

# Run specific test level
Test-LoggingFunctions          # Level 1: Unit tests
Test-TaskArrayExecution        # Level 2: Integration tests
Test-FullScriptExecution       # Level 3: System tests
Test-PerformanceBenchmarks     # Level 4: Performance tests

# ========== ANALYSIS COMMANDS ==========

# Static code analysis
Invoke-ScriptAnalyzer -Path ".\script.ps1" -Recurse

# Complexity analysis
Get-FunctionComplexity -ScriptPath ".\script.ps1"

# Code coverage
Get-CodeCoverage -ScriptPath ".\script.ps1" -TestPath ".\tests\"

# Dependency analysis
Get-DependencyGraph -ScriptPath ".\script.ps1"

# Security scan
Get-SecurityVulnerabilities -ScriptPath ".\script.ps1"

# Performance profiling
Get-PerformanceProfile -ScriptBlock { .\script.ps1 }

# ========== CONTINUOUS TESTING ==========

# Start file watcher for auto-testing
Start-ContinuousTesting -WatchPath "."

# Generate test reports
Export-TestReport -TestResults $testResults -OutputPath ".\test_reports"

# ========== MAINTENANCE COMMANDS ==========

# Run full maintenance
.\script.bat

# Run PowerShell script directly (requires dependencies)
.\script.ps1

# Test specific task
& $global:ScriptTasks[2].Function

# View task results
$global:TaskResults | Format-Table

# Enable verbose logging
$global:Config.EnableVerboseLogging = $true

# Add custom bloatware pattern
$global:Config.CustomBloatwareList += @('AppName.*')

# Test registry access
Test-RegistryAccess -RegistryPath "HKLM:\Path" -CreatePath

# Check command availability
Test-CommandAvailable 'winget'

# View log in real-time
Get-Content maintenance.log -Wait -Tail 50

# Search for errors
Select-String -Path maintenance.log -Pattern '\[ERROR\]' -Context 2,2

# Analyze task performance
Select-String -Path maintenance.log -Pattern 'Duration: ([\d.]+)s'
```

---

## Support & Troubleshooting

### GitHub Repository
**Location**: `https://github.com/ichimbogdancristian/script_mentenanta`

### Common Questions

**Q: Can I run this on Windows Server?**
A: Yes, but some features (Store apps, Xbox) may not apply. Test thoroughly.

**Q: Does this work on domain-joined computers?**
A: Yes, but Group Policy may restrict some registry modifications.

**Q: Can I customize the bloatware list?**
A: Yes, use `$global:Config.CustomBloatwareList` to add patterns.

**Q: How do I disable automatic restart?**
A: Currently handled by batch launcher. Modify restart detection logic (lines 450-550).

**Q: Can I run individual tasks?**
A: Yes, use `& $global:ScriptTasks[index].Function` or call task functions directly.

**Q: How do I add a new essential application?**
A: Add to `$global:Config.CustomEssentialApps` with Winget/Choco IDs.

### Getting Help

1. **Check logs**: `maintenance.log` contains detailed execution traces
2. **Enable verbose logging**: `$global:Config.EnableVerboseLogging = $true`
3. **Test components**: Use manual task testing commands
4. **Review errors**: `Select-String -Path maintenance.log -Pattern '\[ERROR\]'`
5. **Check GitHub Issues**: Search for similar problems

---

## Appendix: Advanced Scenarios

### Running from Network Share

```batch
REM script.bat automatically handles UNC paths
\\SERVER\Share\script_mentenanta\script.bat

REM Logs and temp files created in network location
```

### Custom Task Exclusion

```powershell
# Exclude specific tasks from execution
$global:Config.ExcludeTasks = @('DesktopBackground', 'TaskbarOptimization')

# Tasks will be skipped during orchestration
```

### Parallel Package Installation

```powershell
# Install multiple apps in parallel
$apps = @('Google.Chrome', 'Mozilla.Firefox', '7zip.7zip')
$apps | ForEach-Object -Parallel {
    winget install --id $_ --silent
} -ThrottleLimit 3
```

### Custom Bloatware Detection

```powershell
# Add custom detection source
function Get-CustomBloatware {
    # Custom detection logic
    $customApps = Get-ItemProperty "HKLM:\SOFTWARE\CustomPath\*"
    return $customApps | Where-Object { $_.Type -eq 'Bloatware' }
}

# Integrate into main detection
$allBloatware += Get-CustomBloatware
```

## Testing & Debugging

### Manual Task Testing
```powershell
# Test individual task function directly
& $global:ScriptTasks[2].Function  # Execute RemoveBloatware task
```

### Log Analysis
Primary log: `maintenance.log` in script directory (inherited from batch launcher via `$env:SCRIPT_LOG_FILE`)

**Search patterns**:
- `[ERROR]` - Critical failures
- `[ACTION]` - Task boundaries and major operations
- `[COMMAND]` - External process invocations

### Common Issues
1. **"PowerShell script not found"**: Check `$PS1_PATH` detection logic in batch launcher (lines 600-700)
2. **Registry access failures**: Use `Test-RegistryAccess` diagnostics, check admin elevation
3. **Package manager timeouts**: Adjust `$global:SystemSettings.Timeouts` values

## Code Style Conventions

- **Function naming**: Verb-Noun pattern (Remove-Bloatware, Install-EssentialApps)
- **Parameters**: Explicit types, Mandatory attribute for required params
- **Comments**: Structured headers with Purpose/Environment/Logic/Dependencies sections
- **Variables**: Descriptive names, camelCase for locals, PascalCase for parameters
- **Progress tracking**: Minimal logging, visual progress bars preferred

## DO NOT

- ❌ Add `Write-Host` without corresponding `Write-Log` call
- ❌ Use hardcoded paths (always use `$global:TempFolder`, `$WorkingDirectory`, etc.)
- ❌ Skip error handling in external command invocations
- ❌ Log every percentage update (pollutes logs - use progress bars)
- ❌ Move infrastructure logic (admin checks, package manager installation) from batch to PowerShell
- ❌ Create scheduled tasks without using `$SCHEDULED_TASK_SCRIPT_PATH` variable (batch script)
- ❌ Assume AppX/DISM modules available - always check with graceful fallback

## Performance Considerations

- Use `.ToLower()` comparisons for case-insensitive matching (performance optimization)
- Prefer `Get-CimInstance` over `Get-WmiObject` (PowerShell 7 compatibility)
- Batch operations where possible (parallel app installation/removal)
- Cache system inventory in `$global:SystemInventory` to avoid repeated scans

## External Dependencies

Required for full functionality:
- PowerShell 7.0+ (installed by launcher if missing)
- Winget (Windows Package Manager)
- Chocolatey package manager
- PSWindowsUpdate module (optional, graceful degradation)
- DISM module (Windows built-in)
- Administrator privileges (enforced by launcher)

### Environment-Specific Configuration

**Corporate/Domain Environment**:
```powershell
# Disable features that conflict with Group Policy
$global:Config.SkipTelemetryDisable = $true  # Let GPO handle
$global:Config.SkipSystemRestore = $true     # Managed centrally
$global:Config.CustomBloatwareList = @(
    # Company-specific apps to remove
)
```

**Home/Personal Environment**:
```powershell
# Aggressive optimization
$global:Config.SkipBloatwareRemoval = $false
$global:Config.SkipTelemetryDisable = $false
$global:Config.CustomBloatwareList += @(
    '*OneDrive*', '*Cortana*', '*Copilot*'
)
```

**Server Environment**:
```powershell
# Minimal maintenance
$global:Config.SkipEssentialApps = $true          # No GUI apps
$global:Config.SkipBloatwareRemoval = $true       # No Store apps
$global:Config.SkipTaskbarOptimization = $true    # Server Core
```

---

## Contribution Guidelines

### Code Style

1. **Follow PowerShell best practices**: Use approved verbs, proper indentation
2. **Comprehensive logging**: Every function must log start, completion, errors
3. **Error handling**: Always use try/catch with meaningful error messages
4. **Progress tracking**: Use provided progress functions, not percentage logging
5. **Documentation**: Update this file when adding new components

### Testing Requirements

Before submitting changes:
1. ✅ Test on Windows 10 and Windows 11
2. ✅ Test with admin and non-admin (where applicable)
3. ✅ Test from network path and local drive
4. ✅ Test scheduled task execution
5. ✅ Verify logs are clean and informative
6. ✅ Check for errors in maintenance.log
7. ✅ Test fallback mechanisms

### Pull Request Template

```markdown
## Description
[Brief description of changes]

## Type of Change
- [ ] Bug fix
- [ ] New feature
- [ ] Breaking change
- [ ] Documentation update

## Testing Performed
- [ ] Windows 10 (Build: ____)
- [ ] Windows 11 (Build: ____)
- [ ] Network path execution
- [ ] Scheduled task execution
- [ ] Error handling verified

## Checklist
- [ ] Code follows style guidelines
- [ ] Comprehensive logging added
- [ ] Error handling implemented
- [ ] Documentation updated
- [ ] No hardcoded paths
- [ ] Progress tracking uses approved functions
```

---

## Frequently Asked Questions

**Q: Why separate batch and PowerShell scripts?**
A: Batch handles infrastructure (elevation, dependencies, scheduling) that requires native Windows compatibility. PowerShell handles complex maintenance logic with modern language features.

**Q: Can I disable specific bloatware categories?**
A: Yes, modify `$global:AppCategories` or use `$global:Config.CustomBloatwareList` to override.

**Q: How do I add support for a new OEM?**
A: Add patterns to `$global:AppCategories.OEMBloatware` array:
```powershell
$global:AppCategories.OEMBloatware += @('NewOEM.*', 'NewOEM.SpecificApp')
```

**Q: Can I run this on Windows ARM devices?**
A: Partially. Package managers may have limited ARM support. Test thoroughly before deploying.

**Q: How do I change the scheduled task time?**
A: Modify line ~375 in script.bat:
```batch
/ST 01:00  REM Change to desired time (24-hour format)
```

**Q: Does this work with Windows Sandbox?**
A: Yes, but changes are not persistent. Suitable for testing only.

**Q: Can I run this from PowerShell ISE?**
A: Not recommended. Use PowerShell 7 console or Windows Terminal for best compatibility.

**Q: How do I rollback changes?**
A: Use System Restore point created at start of maintenance (if enabled). Registry changes may require manual rollback.

**Q: Is this compatible with Windows Insider builds?**
A: Generally yes, but test thoroughly as insider builds may have breaking changes.

**Q: Can I schedule this to run at system startup?**
A: Yes, but not recommended due to potential conflicts with system initialization. Use scheduled task instead.

---

## Version History & Changelog

### Key Architectural Changes

**2025 Edition**:
- Modular task array architecture
- 3-tier logging system
- Minimal logging approach for progress
- Multi-source bloatware detection (5 methods)
- Package manager abstraction layer
- Safe registry operations pattern
- Comprehensive error handling

**Previous Versions**:
- Monolithic script structure
- Basic logging
- Single-source bloatware detection
- Direct package manager calls
- Limited error handling

---

## Performance Benchmarks

**Typical Execution Times** (Windows 11, i7 processor, 16GB RAM, SSD):

| Task | Duration | Notes |
|------|----------|-------|
| System Inventory | 5-10s | One-time scan |
| Bloatware Detection | 30-60s | All 5 methods |
| Bloatware Removal | 2-5 min | Depends on app count |
| Essential Apps Install | 5-15 min | Depends on app count & network |
| Windows Updates | 10-60 min | Varies greatly |
| Telemetry Disable | 10-20s | Registry modifications |
| System Health Repair | 10-30 min | DISM/SFC operations |
| **Total** | **20-90 min** | **Full maintenance** |

**Optimization Opportunities**:
- Parallel app installation (reduce 50% time)
- Cached bloatware detection (reduce 70% time on repeat runs)
- Incremental updates (skip unchanged items)

---

## Security Considerations

### Privilege Requirements

**Administrator**: Required for:
- Registry modifications (HKLM)
- AppX package removal (system-wide)
- DISM operations
- Windows Update installation
- Service management
- Scheduled task creation

**SYSTEM**: Used for scheduled tasks to ensure:
- Unattended execution
- Full system access
- No user session dependency

### Attack Surface

**Mitigations**:
1. ✅ No user input accepted without validation
2. ✅ External commands logged comprehensively
3. ✅ Registry access validated before modification
4. ✅ Package managers verified before use
5. ✅ Temp files cleaned after use
6. ✅ No credentials stored or transmitted

**Risks**:
1. ⚠️ Running with elevated privileges
2. ⚠️ Downloading from GitHub (use trusted repository)
3. ⚠️ Modifying system registry
4. ⚠️ Removing system components
5. ⚠️ Installing third-party applications

### Recommendations

**For Production**:
1. Review code before deployment
2. Test on non-production systems first
3. Create full system backup
4. Document all changes
5. Monitor execution logs
6. Use digital signatures for scripts

**For Development**:
1. Use separate test environment
2. Enable verbose logging
3. Test rollback procedures
4. Validate all external sources
5. Code review all changes

---

## Glossary

| Term | Definition |
|------|------------|
| **AppX** | Universal Windows Platform (UWP) app format |
| **Bloatware** | Pre-installed unnecessary software |
| **DISM** | Deployment Image Servicing and Management |
| **OEM** | Original Equipment Manufacturer (Dell, HP, etc.) |
| **Orchestrator** | Main script coordinator (script.ps1) |
| **Provisioned Package** | AppX package installed for all future users |
| **PSWindowsUpdate** | PowerShell module for Windows Update management |
| **SFC** | System File Checker |
| **UNC Path** | Universal Naming Convention (network path) |
| **Winget** | Windows Package Manager |

---

## Additional Resources

### Documentation
- [PowerShell Documentation](https://docs.microsoft.com/en-us/powershell/)
- [Windows Package Manager](https://docs.microsoft.com/en-us/windows/package-manager/)
- [DISM Reference](https://docs.microsoft.com/en-us/windows-hardware/manufacture/desktop/dism-reference)
- [Scheduled Tasks](https://docs.microsoft.com/en-us/windows/win32/taskschd/task-scheduler-start-page)

### Tools
- [PowerShell 7](https://github.com/PowerShell/PowerShell)
- [Winget](https://github.com/microsoft/winget-cli)
- [Chocolatey](https://chocolatey.org/)
- [PSWindowsUpdate](https://www.powershellgallery.com/packages/PSWindowsUpdate)

### Community
- GitHub Issues: Report bugs and request features
- GitHub Discussions: Ask questions and share tips
- Pull Requests: Contribute improvements

---

## License & Credits

**Author**: Bogdan Christian Ichim
**Repository**: https://github.com/ichimbogdancristian/script_mentenanta
**License**: [Specify license]
**Last Updated**: November 12, 2025

### Acknowledgments
- PowerShell team for PowerShell 7
- Windows Package Manager team
- Chocolatey community
- PSWindowsUpdate module authors
- Contributors and testers

---

## Summary for AI Agents

**When working with this codebase**:

1. 🔴 **NEVER** modify batch launcher infrastructure without extensive testing
2. 🟡 **ALWAYS** use standardized logging (Write-Log, Write-ActionLog, Write-CommandLog)
3. 🟢 **PREFER** visual progress bars over verbose percentage logging
4. 🔵 **IMPLEMENT** comprehensive error handling with try/catch
5. 🟣 **TEST** registry access before modification
6. 🟠 **CHECK** command availability before invocation
7. ⚫ **ADD** new features as modular task entries
8. ⚪ **DOCUMENT** all changes in this file

**Key Files**:
- `script.bat` - Infrastructure (DO NOT MODIFY WITHOUT EXTREME CARE)
- `script.ps1` - Maintenance logic (SAFE TO EXTEND)
- `maintenance.log` - Primary diagnostic resource
- `.github/copilot-instructions.md` - This comprehensive guide

**Contact**: Open GitHub issue for questions, bugs, or feature requests.
