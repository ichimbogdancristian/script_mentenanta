# Windows Maintenance Automation System - AI Assistant Instructions

## 📋 Table of Contents

1. [Repository Overview](./copilot-instructions.md#repository-overview)
2. [Architecture & Core Concepts](./copilot-instructions.md#architecture--core-concepts)
3. [Getting Started](./copilot-instructions.md#getting-started)
4. [Development Workflows](./copilot-instructions.md#development-workflows)
5. [PowerShell Best Practices](./copilot-instructions.md#powershell-best-practices)
6. [Testing Guidelines](./copilot-instructions.md#testing-guidelines)
7. [Integration & Dependencies](./copilot-instructions.md#integration--dependencies)
8. [Reference Guide](./copilot-instructions.md#reference-guide)

---

## 🏗️ Repository Overview

This repository contains a **Windows maintenance automation system** built on a modular PowerShell architecture.

### System Components

| Component | Purpose | Key Features |
|-----------|---------|--------------|
| `script.bat` | Launcher & Bootstrapper | Elevation, dependency installation (winget, pwsh, choco, PSWindowsUpdate), scheduled tasks, repo download |
| `MaintenanceOrchestrator.ps1` | Central Orchestrator | Module loading, configuration, interactive menus, task execution coordination (PowerShell 7+ required) |
| `modules/type1/` | Inventory & Reporting | Read-only operations for system analysis |
| `modules/type2/` | System Modification | Write operations that change system state |
| `modules/core/` | Infrastructure | Configuration, menus, dependencies, scheduling |
| `config/*.json` | Configuration System | JSON-based settings and data |

### Target Environment

- **Platforms**: Windows 10/11
- **Requirements**: Administrator privileges, network access
- **Design**: Location-agnostic launcher with self-discovery

### Project Evolution

This project underwent a **complete architectural transformation** from a monolithic script to a modular system:
- **Original monolithic files** preserved in `archive/` directory for reference
- **Current architecture** fully modular with specialized PowerShell modules
- **Migration complete**: All functionality extracted from the original 11,353-line `script.ps1`
- **Production ready**: New system is the current active implementation

---

## 🎯 Architecture & Core Concepts

### Why This Structure Exists

#### 🔧 Modular Architecture
The system is built from specialized PowerShell modules, each with a single responsibility:
- **Type 1 modules**: Inventory/reporting (read-only operations)
- **Type 2 modules**: System modifications (write operations)
- **Core modules**: Infrastructure (configuration, menus, dependencies, scheduling)

#### 🚀 Launcher → Orchestrator Design
- `script.bat` prepares environment (elevation, dependency bootstrap, scheduled tasks, downloads)
- Delegates to `MaintenanceOrchestrator.ps1` for actual task execution
- **Important**: Avoid editing elevation logic in PowerShell — it's centralized in the batch launcher

#### ⚙️ Configuration-Driven
- All settings, app lists, and behaviors controlled through JSON configuration files in `config/` directory
- **Never hardcode** data that should be configurable
- Use `ConfigManager` module for all configuration access

#### 🎮 Interactive + Non-Interactive Modes
- Supports both menu-driven interactive use and unattended automation
- All interactive prompts must have timeout fallbacks
- Non-interactive bypass options required for automation scenarios

#### 📋 Task Registry Pattern
- Tasks defined as module function calls in `MaintenanceOrchestrator.ps1`
- Each task specifies: module path, function name, type, and category
- Enables dynamic task loading and execution tracking

#### 🧪 Dry-Run Architecture
- All system-modifying operations must support dry-run mode
- Implement through `-DryRun` parameters or `-WhatIf` cmdlet binding
- Essential for safe testing and validation

### Critical Files to Read First

When onboarding or making changes, read these files in order:

1. **`script.bat`** — Environment setup foundation
   - Admin checks and elevation logic
   - PowerShell detection and version handling
   - Dependency install order: winget → pwsh → NuGet → PSGallery → PSWindowsUpdate → chocolatey
   - Scheduled task creation
   - Repository download/extract process
   - How it invokes `MaintenanceOrchestrator.ps1`

2. **`MaintenanceOrchestrator.ps1`** — Central coordination
   - Header and initialization sections
   - Task registry array (`$Tasks`) with all available tasks
   - Key functions: `Invoke-Task`, `Show-TaskMenu`
   - Parameter parsing and validation

3. **`modules/core/ConfigManager.psm1`** — Configuration system
   - `Initialize-ConfigSystem`, `Get-MainConfiguration`, `Get-LoggingConfiguration`
   - JSON loading and validation
   - Configuration schema definitions

4. **`modules/core/MenuSystem.psm1`** — Interactive UI
   - `Show-MainMenu`, `Show-TaskSelectionMenu`
   - Countdown timers and user input handling

5. **Module architecture** — Understanding `.psm1` structure
   - Type 1 modules: Return data objects
   - Type 2 modules: Return success/failure booleans
   - All modules: Use `Export-ModuleMember` for public functions

---

## 🚀 Getting Started

### Development Environment Setup

#### Prerequisites
- Windows 10/11
- Administrator privileges
- PowerShell 7+ (installed automatically by `script.bat` if missing)
- Network access for dependency downloads

#### Quick Start for Developers

```powershell
# Clone the repository
git clone https://github.com/ichimbogdancristian/script_mentenanta.git
cd script_mentenanta

# Run locally (developer mode)
# Open elevated PowerShell 7+ console
.\MaintenanceOrchestrator.ps1
```

#### Quick Start for Production/Operators

```cmd
# Simply run the launcher (handles all dependencies)
script.bat
```

---

## 💻 Development Workflows

### Common Commands & Patterns

#### 🔧 Developer Mode (Local Testing)
```powershell
# Basic execution
.\MaintenanceOrchestrator.ps1

# Dry-run mode (simulate without changes)
.\MaintenanceOrchestrator.ps1 -DryRun

# Run specific tasks only
.\MaintenanceOrchestrator.ps1 -TaskNumbers "1,3,5"

# Non-interactive with specific tasks
.\MaintenanceOrchestrator.ps1 -NonInteractive -TaskNumbers "2,4"
```

#### 🚀 Production Mode (Full Bootstrap)
```cmd
REM Interactive with menus
script.bat

REM Non-interactive automation
script.bat -NonInteractive

REM Full bootstrap with dry-run
script.bat -DryRun
```

#### 📝 Configuration Management
```powershell
# Edit configuration (use appropriate JSON file)
code config/main-config.json
code config/bloatware-list.json
code config/essential-apps.json

# Never hardcode values in modules - always use config files
```

#### 🔍 Module Development
```powershell
# Create new Type 1 module (read-only operations)
New-Item "modules/type1/MyNewModule.psm1"

# Create new Type 2 module (system modifications)
New-Item "modules/type2/MyNewModule.psm1"

# Test individual module
Import-Module "./modules/type1/MyNewModule.psm1" -Force
Test-MyNewFunction
```

### Adding New Tasks

Follow this workflow when adding new maintenance tasks:

1. **Create the module file**
   ```powershell
   # Choose appropriate type directory
   $modulePath = "modules/type2/MyNewTask.psm1"  # or type1 for read-only
   New-Item $modulePath
   ```

2. **Implement the module function**
   - Follow PowerShell best practices (see section below)
   - Include proper error handling
   - Support `-DryRun` parameter for Type 2 modules
   - Return appropriate data structure (object for Type 1, boolean for Type 2)

3. **Register the task**
   - Add entry to `$Tasks` array in `MaintenanceOrchestrator.ps1`
   - Specify: Name, Description, ModulePath, Function, Type, Category

4. **Test the task**
   - Use TestFolder workflow (see Testing Guidelines section)
   - Verify dry-run mode works correctly
   - Test both interactive and non-interactive modes

---

## 📚 PowerShell Best Practices

This section contains **project-specific** PowerShell coding standards. All code must follow these conventions.

### Function Naming & Structure

#### ✅ Use Approved Verbs Only

PowerShell has an [approved verb list](https://learn.microsoft.com/en-us/powershell/scripting/developer/cmdlet/approved-verbs-for-windows-powershell-commands). **Always use approved verbs**.

| ❌ Bad | ✅ Good | Verb Category |
|--------|---------|---------------|
| `Invoke-FetchData` | `Get-Data` | Common |
| `Do-Cleanup` | `Clear-Cache` or `Remove-TempFiles` | Common |
| `Handle-Error` | `Resolve-Error` or `Write-ErrorLog` | Diagnostic |
| `Process-Items` | `Update-Items` or `Convert-Items` | Data |

**Common approved verbs for this project:**
- **Common**: Get, Set, New, Remove, Add, Clear, Copy, Move, Invoke
- **Lifecycle**: Enable, Disable, Start, Stop, Install, Uninstall
- **Diagnostic**: Test, Trace, Measure, Debug, Repair
- **Data**: Import, Export, Backup, Restore, Publish

```powershell
# ❌ BAD: Non-approved verb
function Fetch-SystemInfo { ... }

# ✅ GOOD: Approved verb
function Get-SystemInfo { ... }
```

#### 📋 Advanced Functions with CmdletBinding

**All functions** in this project must be advanced functions with `[CmdletBinding()]` and comment-based help.

```powershell
<#
.SYNOPSIS
    Gets system information and returns a structured object.

.DESCRIPTION
    Collects detailed system information including hardware specs, OS version,
    installed updates, and disk usage. Returns a structured PSCustomObject.

.PARAMETER IncludeHardware
    Include detailed hardware information in the output.

.PARAMETER ComputerName
    Target computer name. Defaults to local computer.

.EXAMPLE
    Get-SystemInfo
    Gets system information for the local computer.

.EXAMPLE
    Get-SystemInfo -IncludeHardware -ComputerName "SERVER01"
    Gets detailed system information including hardware for remote computer.

.OUTPUTS
    PSCustomObject with system information properties.

.NOTES
    Author: Maintenance Team
    Type: Type1 (Read-only)
    Requires: Administrator privileges for complete information
#>
function Get-SystemInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [switch]$IncludeHardware,
        
        [Parameter(Mandatory=$false)]
        [ValidateNotNullOrEmpty()]
        [string]$ComputerName = $env:COMPUTERNAME
    )
    
    begin {
        Write-Verbose "Starting system information collection for $ComputerName"
    }
    
    process {
        try {
            # Implementation here
            $result = [PSCustomObject]@{
                ComputerName = $ComputerName
                OSVersion = (Get-CimInstance Win32_OperatingSystem).Version
                # ... more properties
            }
            return $result
        }
        catch {
            Write-Error "Failed to get system info: $_"
            return $null
        }
    }
    
    end {
        Write-Verbose "System information collection completed"
    }
}
```

### Parameter Best Practices

#### 🎯 Parameter Attributes

Always use explicit parameter attributes for clarity and validation:

```powershell
param(
    # Mandatory parameter with position
    [Parameter(Mandatory=$true, Position=0)]
    [ValidateNotNullOrEmpty()]
    [string]$ComputerName,
    
    # Pipeline input
    [Parameter(ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
    [string[]]$Services,
    
    # Validated set of options
    [Parameter(Mandatory=$false)]
    [ValidateSet('Low', 'Medium', 'High', 'Critical')]
    [string]$Priority = 'Medium',
    
    # Numeric range validation
    [Parameter(Mandatory=$false)]
    [ValidateRange(1, 100)]
    [int]$Timeout = 30,
    
    # Path validation
    [Parameter(Mandatory=$true)]
    [ValidateScript({Test-Path $_ -PathType Container})]
    [string]$OutputPath,
    
    # Switch parameter
    [Parameter(Mandatory=$false)]
    [switch]$Force
)
```

#### 🚫 Avoid Positional Parameters in Public Functions

```powershell
# ❌ BAD: Relies on position
Remove-Service "MyService" $true

# ✅ GOOD: Named parameters
Remove-Service -ServiceName "MyService" -Force
```

### Destructive Operations & ShouldProcess

**All Type 2 modules** must support `-WhatIf` and `-Confirm` using `SupportsShouldProcess`.

```powershell
function Remove-BloatwareApp {
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='High')]
    param(
        [Parameter(Mandatory=$true)]
        [string]$AppName,
        
        [Parameter(Mandatory=$false)]
        [switch]$Force
    )
    
    # Check if we should proceed
    if ($PSCmdlet.ShouldProcess($AppName, 'Remove application')) {
        try {
            Write-Host "🔄 Removing $AppName..." -ForegroundColor Yellow
            
            # Actual removal logic here
            $result = Get-AppxPackage -Name $AppName -AllUsers -ErrorAction SilentlyContinue
            if ($result) {
                $result | Remove-AppxPackage -AllUsers -ErrorAction Stop
                Write-Host "✓ Successfully removed $AppName" -ForegroundColor Green
                return $true
            }
            else {
                Write-Host "⚠️ $AppName not found" -ForegroundColor Yellow
                return $false
            }
        }
        catch {
            Write-Host "❌ Failed to remove $AppName`: $_" -ForegroundColor Red
            return $false
        }
    }
    else {
        Write-Host "⏭️ Skipped removal of $AppName (WhatIf mode)" -ForegroundColor Cyan
        return $false
    }
}

# Usage examples:
# Remove-BloatwareApp -AppName "Microsoft.BingWeather" -WhatIf  # Simulates
# Remove-BloatwareApp -AppName "Microsoft.BingWeather" -Confirm  # Prompts
# Remove-BloatwareApp -AppName "Microsoft.BingWeather" -Force    # No prompt
```

### Error Handling & Logging

#### 🛡️ Comprehensive Error Handling

```powershell
function Install-RequiredApplication {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$AppId
    )
    
    try {
        Write-Host "🔄 Installing $AppId..." -ForegroundColor Yellow
        
        # Set error action to stop for try/catch
        $ErrorActionPreference = 'Stop'
        
        # Execute installation
        $result = winget install --id $AppId --silent --accept-package-agreements --accept-source-agreements
        
        # Check exit code
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✓ Successfully installed $AppId" -ForegroundColor Green
            Write-Log "Installed application: $AppId" -Level 'INFO'
            return $true
        }
        else {
            Write-Host "❌ Installation failed with exit code: $LASTEXITCODE" -ForegroundColor Red
            Write-Log "Installation failed for $AppId - Exit code: $LASTEXITCODE" -Level 'ERROR'
            return $false
        }
    }
    catch {
        Write-Host "❌ Installation error: $_" -ForegroundColor Red
        Write-Log "Installation exception for $AppId`: $_" -Level 'ERROR'
        return $false
    }
    finally {
        # Cleanup code here
        $ErrorActionPreference = 'Continue'
    }
}
```

#### 📊 Return Value Contracts

**Critical**: Respect module type return contracts:

- **Type 1 modules**: Return data objects (`PSCustomObject`, hashtables, arrays)
- **Type 2 modules**: Return boolean (`$true` for success, `$false` for failure)

```powershell
# Type 1 Module (Read-only) - Return data object
function Get-InstalledBloatware {
    [CmdletBinding()]
    param()
    
    try {
        $bloatwareList = Get-AppxPackage | Where-Object { $_.Name -like "*Xbox*" }
        
        $results = $bloatwareList | ForEach-Object {
            [PSCustomObject]@{
                Name = $_.Name
                Version = $_.Version
                InstallLocation = $_.InstallLocation
                IsProvisioned = $_.IsResourcePackage
            }
        }
        
        return $results  # Return data object
    }
    catch {
        Write-Error "Failed to get bloatware list: $_"
        return $null
    }
}

# Type 2 Module (System modification) - Return boolean
function Remove-AllBloatware {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param()
    
    try {
        $bloatware = Get-InstalledBloatware
        
        foreach ($app in $bloatware) {
            if ($PSCmdlet.ShouldProcess($app.Name, 'Remove')) {
                Remove-AppxPackage -Package $app.Name -ErrorAction Stop
            }
        }
        
        return $true  # Return boolean for success
    }
    catch {
        Write-Error "Failed to remove bloatware: $_"
        return $false  # Return boolean for failure
    }
}
```

### Code Quality & Style

#### 🚫 No Aliases in Scripts

```powershell
# ❌ BAD: Uses aliases
gci C:\Windows | ? { $_.Length -gt 1MB } | % { rm $_ -Force }

# ✅ GOOD: Full cmdlet names
Get-ChildItem -Path C:\Windows | 
    Where-Object { $_.Length -gt 1MB } | 
    ForEach-Object { Remove-Item -Path $_.FullName -Force }
```

#### 📦 Splatting for Complex Commands

```powershell
# ❌ BAD: Long command line
Invoke-Command -ComputerName "SERVER01" -ScriptBlock { Get-Service } -Credential $cred -Authentication Kerberos -ErrorAction Stop

# ✅ GOOD: Use splatting
$invokeParams = @{
    ComputerName = "SERVER01"
    ScriptBlock = { Get-Service }
    Credential = $cred
    Authentication = 'Kerberos'
    ErrorAction = 'Stop'
}
Invoke-Command @invokeParams
```

#### 🔧 External Command Invocation

```powershell
# For external executables, use explicit argument arrays
$wingetArgs = @(
    'install'
    '--id', 'Microsoft.PowerShell'
    '--silent'
    '--accept-package-agreements'
    '--accept-source-agreements'
)

# Use Start-Process or custom wrapper
$process = Start-Process -FilePath 'winget.exe' -ArgumentList $wingetArgs -Wait -PassThru -NoNewWindow

if ($process.ExitCode -eq 0) {
    Write-Host "✓ Installation successful" -ForegroundColor Green
}
else {
    Write-Host "❌ Installation failed with exit code: $($process.ExitCode)" -ForegroundColor Red
}
```

### Static Analysis with PSScriptAnalyzer

#### 📐 Required Practice

All code must pass PSScriptAnalyzer checks before commit:

```powershell
# Install PSScriptAnalyzer
Install-Module -Name PSScriptAnalyzer -Scope CurrentUser -Force

# Analyze entire project
Invoke-ScriptAnalyzer -Path . -Recurse -ReportSummary

# Analyze specific file
Invoke-ScriptAnalyzer -Path ".\modules\type2\MyModule.psm1" -Severity Error,Warning

# Analyze with specific rules
Invoke-ScriptAnalyzer -Path . -Recurse -IncludeRule PSUseApprovedVerbs,PSAvoidUsingCmdletAliases
```

#### 🎯 Key Rules to Follow

| Rule | Description | Example |
|------|-------------|---------|
| `PSUseApprovedVerbs` | Use only approved PowerShell verbs | `Get-Data` not `Fetch-Data` |
| `PSAvoidUsingCmdletAliases` | No aliases in scripts | `Get-ChildItem` not `gci` |
| `PSUseShouldProcessForStateChangingFunctions` | Use `-WhatIf` support | `[CmdletBinding(SupportsShouldProcess)]` |
| `PSProvideCommentHelp` | Include comment-based help | `.SYNOPSIS`, `.DESCRIPTION`, etc. |
| `PSAvoidUsingPositionalParameters` | Use named parameters | `-Path $file` not just `$file` |
| `PSUseDeclaredVarsMoreThanAssignments` | Remove unused variables | Clean up unused declarations |

### Code Review Checklist

Use this checklist before committing PowerShell code:

- [ ] **Verb usage**: Function uses an approved PowerShell verb
- [ ] **CmdletBinding**: Function has `[CmdletBinding()]` attribute
- [ ] **Comment help**: Includes `.SYNOPSIS`, `.DESCRIPTION`, `.PARAMETER`, `.EXAMPLE`
- [ ] **Parameters**: All parameters have explicit attributes and validation
- [ ] **Error handling**: Try/catch blocks with proper error logging
- [ ] **Return values**: Type 1 returns objects, Type 2 returns boolean
- [ ] **ShouldProcess**: Destructive operations support `-WhatIf` and `-Confirm`
- [ ] **No aliases**: Full cmdlet names used (no `gci`, `ls`, `rm`, etc.)
- [ ] **Splatting**: Complex commands use splatting for readability
- [ ] **Exit codes**: External commands checked for success/failure
- [ ] **PSScriptAnalyzer**: All high-severity issues resolved
- [ ] **Consistent style**: Indentation and formatting match project standards
- [ ] **Module exports**: Function added to `Export-ModuleMember`

---

## 🧪 Testing Guidelines

### MANDATORY Testing Procedures

**⚠️ CRITICAL: All testing must be conducted in the TestFolder**

When you need to create test scripts, run tests, or verify functionality, you **MUST** use the TestFolder located at the same path level as script_mentenanta:

```
Desktop\Projects\
├── script_mentenanta\     (main project)
└── TestFolder\            (testing environment - USE THIS)
```

**Mandatory Testing Workflow:**
1. **Clean TestFolder**: Always start by cleaning the TestFolder from any previous contents
2. **Copy launcher**: Copy the latest version of `script.bat` from script_mentenanta to TestFolder
3. **Execute from TestFolder**: Run `script.bat` from within the TestFolder directory
4. **Observe project unfolding**: Watch the complete project download, setup, and execution process

**Commands for testing workflow:**
```powershell
# 1. Clean the TestFolder
Remove-Item "C:\Users\Bogdan\OneDrive\Desktop\Projects\TestFolder\*" -Recurse -Force -ErrorAction SilentlyContinue

# 2. Copy the latest script.bat
Copy-Item "C:\Users\Bogdan\OneDrive\Desktop\Projects\script_mentenanta\script.bat" "C:\Users\Bogdan\OneDrive\Desktop\Projects\TestFolder\"

# 3. Execute from TestFolder
cd "C:\Users\Bogdan\OneDrive\Desktop\Projects\TestFolder"
.\script.bat

# 4. Watch the complete bootstrap and execution process
```

**Why this is mandatory:**
- Tests the complete deployment workflow (download, extract, setup)
- Verifies script.bat launcher functionality in isolated environment
- Ensures system works correctly from fresh deployment
- Prevents test artifacts from contaminating main development folder
- Simulates real-world user experience

**Never:**
- Run tests directly in the script_mentenanta folder unless specifically testing local development
- Create test files in the main project directory
- Skip the TestFolder workflow when verifying functionality

### Unit Testing Best Practices

```powershell
# Install Pester (testing framework)
Install-Module -Name Pester -Scope CurrentUser -Force

# Run tests for specific module
Invoke-Pester -Path ".\tests\BloatwareRemoval.Tests.ps1"

# Run all tests with coverage
Invoke-Pester -Path ".\tests\" -CodeCoverage ".\modules\**\*.psm1" -OutputFormat NUnitXml
```

---

## 🔗 Integration & Dependencies

### External Tools & Package Managers

The system relies on several external tools managed by the `DependencyManager` module:

| Tool | Purpose | Installation Order |
|------|---------|-------------------|
| **winget** | Windows Package Manager | 1st (bootstrapped by script.bat) |
| **pwsh** | PowerShell 7+ | 2nd (required for orchestrator) |
| **NuGet** | PowerShell package provider | 3rd (for PSGallery) |
| **PSGallery** | PowerShell module repository | 4th (for PSWindowsUpdate) |
| **PSWindowsUpdate** | Windows Update management | 5th (module dependency) |
| **chocolatey** | Alternative package manager | 6th (fallback option) |

#### Using Dependencies in Modules

```powershell
# Check dependency status
$wingetStatus = Get-DependencyStatus -DependencyName 'winget'
if (-not $wingetStatus.IsInstalled) {
    Write-Host "❌ winget is not installed" -ForegroundColor Red
    return $false
}

# Use DependencyManager for installations
Install-PackageWithWinget -PackageId 'Microsoft.PowerShell' -Silent
```

### Configuration System

All configuration is JSON-based and accessed through `ConfigManager`:

```powershell
# Load main configuration
$config = Get-MainConfiguration

# Access specific settings
$logPath = $config.LogPath
$timeout = $config.MenuTimeout

# Load specialized configurations
$bloatware = Get-BloatwareList  # From config/bloatware-list.json
$essentialApps = Get-EssentialApps  # From config/essential-apps.json
```

### Module Dependencies & Load Order

**Critical**: Core modules must load before Type 1/Type 2 modules:

1. **Core modules** (infrastructure):
   - `ConfigManager.psm1` — Configuration loading
   - `MenuSystem.psm1` — Interactive menus
   - `DependencyManager.psm1` — Package management
   - `TaskScheduler.psm1` — Scheduled tasks

2. **Type 1 modules** (read-only operations):
   - Can depend on Core modules only
   - No dependencies on Type 2 modules

3. **Type 2 modules** (system modifications):
   - Can depend on Core and Type 1 modules
   - May query Type 1 modules for data before modifications

### Registry & Windows APIs

Many operations interact with Windows Registry:

```powershell
# Always use error handling for registry access
try {
    $regPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
    
    # Check if path exists before accessing
    if (Test-Path $regPath) {
        $value = Get-ItemProperty -Path $regPath -Name "DisableOSUpgrade" -ErrorAction Stop
    }
    else {
        # Create path if it doesn't exist
        New-Item -Path $regPath -Force | Out-Null
        New-ItemProperty -Path $regPath -Name "DisableOSUpgrade" -Value 1 -PropertyType DWORD
    }
}
catch {
    Write-Error "Registry operation failed: $_"
}
```

### Remote Repository Updates

- `script.bat` handles downloading the repository ZIP from GitHub
- Self-update logic is in the batch file launcher
- Coordinate any repo structure changes with batch script updates
- Repository URL: `https://github.com/ichimbogdancristian/script_mentenanta`

---

## 📖 Reference Guide

### Critical Rules (Do Not Change Without Review)

| Component | Why It's Critical | Impact of Changes |
|-----------|-------------------|-------------------|
| **Elevation logic in `script.bat`** | Relies on Windows UAC behavior and admin rights | Can break entire system launch |
| **Module load order** | Core modules provide functions for other modules | Breaks module dependencies |
| **Configuration schemas** | Affects all modules reading config | System-wide breaking changes |
| **Return value contracts** | Orchestrator tracks task success/failure | Breaks execution tracking |
| **DryRun parameter** | Safety mechanism for testing | Removes test safety net |

### Key Files & Symbols Quick Reference

```
📁 Project Structure
├── script.bat ...................... Launcher & bootstrapper
├── MaintenanceOrchestrator.ps1 ..... Central coordinator
├── 📁 config/
│   ├── main-config.json ............ System settings
│   ├── bloatware-list.json ......... Apps to remove
│   ├── essential-apps.json ......... Apps to install
│   └── logging-config.json ......... Log settings
├── 📁 modules/
│   ├── 📁 core/
│   │   ├── ConfigManager.psm1 ...... Configuration system
│   │   ├── MenuSystem.psm1 ......... Interactive UI
│   │   ├── DependencyManager.psm1 .. Package management
│   │   └── TaskScheduler.psm1 ...... Task automation
│   ├── 📁 type1/ ................... Read-only operations
│   └── 📁 type2/ ................... System modifications
└── 📁 archive/ ..................... Original monolithic files
```

### Common Patterns & Conventions

| Pattern | Description | Example |
|---------|-------------|---------|
| **Task registry entries** | Hashtable in `$Tasks` array | `@{Name='Task'; ModulePath='path'; Function='Func'}` |
| **Module exports** | Explicit function exports | `Export-ModuleMember -Function Get-*, Set-*, Remove-*` |
| **Progress reporting** | Colored console output with icons | `Write-Host "✓ Success" -ForegroundColor Green` |
| **Configuration access** | Via ConfigManager functions | `Get-MainConfiguration`, `Get-BloatwareList` |
| **Dependency checks** | Via DependencyManager | `Get-DependencyStatus -DependencyName 'winget'` |

### Status Icons Standard

Use consistent icons for output messages:

| Icon | Meaning | Color | Usage |
|------|---------|-------|-------|
| ✓ | Success | Green | Operation completed successfully |
| ❌ | Error/Failure | Red | Operation failed |
| ⚠️ | Warning | Yellow | Non-critical issue or notice |
| 🔄 | In Progress | Yellow | Operation is running |
| ℹ️ | Information | Cyan | General information |
| ⏭️ | Skipped | Cyan | Operation skipped (WhatIf, already done) |
| 🔍 | Scanning/Detecting | Blue | Search or detection operation |

### Troubleshooting Common Issues

<details>
<summary><b>Module import failures</b></summary>

```powershell
# Check module path
$env:PSModulePath -split ';'

# Import with verbose to see details
Import-Module ".\modules\core\ConfigManager.psm1" -Force -Verbose

# Check for syntax errors
Test-ModuleManifest ".\modules\core\ConfigManager.psm1"
```
</details>

<details>
<summary><b>Configuration not loading</b></summary>

```powershell
# Verify JSON syntax
Get-Content ".\config\main-config.json" | ConvertFrom-Json

# Check file permissions
Get-Acl ".\config\main-config.json"

# Verify ConfigManager is loaded
Get-Module ConfigManager
```
</details>

<details>
<summary><b>Dependency installation failures</b></summary>

```powershell
# Check winget availability
winget --version

# Test package manager access
winget search Microsoft.PowerShell

# Check execution policy
Get-ExecutionPolicy -List

# Set execution policy if needed
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```
</details>

### Quick Action Reference

| Task | Command |
|------|---------|
| **Run full maintenance** | `.\script.bat` |
| **Test without changes** | `.\MaintenanceOrchestrator.ps1 -DryRun` |
| **Run specific tasks** | `.\MaintenanceOrchestrator.ps1 -TaskNumbers "1,3,5"` |
| **Non-interactive mode** | `.\MaintenanceOrchestrator.ps1 -NonInteractive` |
| **Check script quality** | `Invoke-ScriptAnalyzer -Path . -Recurse` |
| **Edit main config** | `code .\config\main-config.json` |
| **View task registry** | `Get-Content .\MaintenanceOrchestrator.ps1 \| Select-String '\$Tasks'` |
| **Test in isolation** | Copy script.bat to TestFolder and run |

### When to Ask for Clarification

If you're unsure about:
1. **Environment constraints**: Local dev vs managed enterprise endpoint vs air-gapped system
2. **Permissions**: Whether modifying scheduled task behavior or restart policy is permitted
3. **Feature toggles**: Whether new features should be enabled by default or opt-in
4. **Breaking changes**: Impact of modifying configuration schemas or return value contracts
5. **Security implications**: Changes affecting elevation, registry access, or system modifications

---

## 📝 Document Maintenance

**Last Updated**: October 10, 2025  
**Document Version**: 2.0  
**Project Version**: Modular Architecture (Post-Migration)

### Changelog

- **v2.0 (Oct 2025)**: Complete restructure with TOC, expanded PowerShell best practices, added comprehensive code examples
- **v1.0 (Initial)**: Basic structure with core concepts and workflows
