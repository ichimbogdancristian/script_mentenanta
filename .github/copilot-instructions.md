# Windows Maintenance Automation System v2.1 - AI Assistant Instructions

## 📋 Table of Contents

1. [Repository Overview](./copilot-instructions.md#repository-overview)
2. [🆕 Enhanced Logging & Reporting System](./copilot-instructions.md#enhanced-logging--reporting-system)
3. [Architecture & Core Concepts](./copilot-instructions.md#architecture--core-concepts)
4. [Getting Started](./copilot-instructions.md#getting-started)
5. [Development Workflows](./copilot-instructions.md#development-workflows)
6. [PowerShell Best Practices](./copilot-instructions.md#powershell-best-practices)
7. [Testing Guidelines](./copilot-instructions.md#testing-guidelines)
8. [Integration & Dependencies](./copilot-instructions.md#integration--dependencies)
9. [Reference Guide](./copilot-instructions.md#reference-guide)

-- -

## 🏗️ Repository Overview

This repository contains a **Windows maintenance automation system** built on a modular PowerShell architecture.

### System Components (v2.1 Enhanced)

| Component | Purpose | Key Features |
| ---------- - | -------- - | -------------- |
| `script.bat`  | Launcher & Bootstrapper | Elevation, dependency installation (winget, pwsh, choco, PSWindowsUpdate), scheduled tasks, repo download |
| `MaintenanceOrchestrator.ps1`  | Central Orchestrator | Module loading, configuration, interactive menus, task execution coordination (PowerShell 7+ required) |
| `modules/type1/`  | Inventory & Reporting | Read-only operations for system analysis, 🆕 **enhanced with dashboard analytics** |
| `modules/type2/`  | System Modification | Write operations that change system state |
| `modules/core/`  | Infrastructure | Configuration, menus, dependencies, scheduling, 🆕 **centralized logging & file organization** |
| `config/*.json`  | Configuration System | JSON-based settings and data, 🆕 **enhanced with performance tracking** |
| `temp_files/`  | 🆕 **Organized Data Storage** | Session-based file organization with automated cleanup and structured directories |

### Target Environment

- * * Platforms**: Windows 10/11
- * * Requirements**: Administrator privileges, network access
- * * Design**: Location-agnostic launcher with self-discovery

### Project Evolution

This project underwent a **complete architectural transformation** from a monolithic script to a modular system:
- * * Original monolithic files** preserved in `archive/` directory for reference
- * * Current architecture** fully modular with specialized PowerShell modules
- * * Migration complete**: All functionality extracted from the original 11, 353-line `script.ps1`
- * * Production ready**: New system is the current active implementation
- 🆕 **v2.0 Enhancement**: Added comprehensive logging infrastructure and interactive dashboard reporting
- 🆕 **v2.1 Enhancement**: Implemented FileOrganizationManager with session-based file organization, eliminated file proliferation, and added automated cleanup

-- -

## 🆕 Enhanced Logging & Reporting System

### Major v2.0 Enhancements

The system now includes **enterprise-grade logging and reporting capabilities**:

#### **LoggingManager Module** (`modules/core/LoggingManager.psm1`)
- **Centralized logging infrastructure** with structured data collection
- **Multi-destination output**: console, file, and structured buffer
- **Performance tracking** with operation timing and success metrics
- **Session management** with unique session IDs and thread safety
- **Data export capabilities**: JSON, CSV, XML formats for integration
- **Automatic log rotation** with configurable retention

#### **Enhanced ReportGeneration** (Completely Rewritten)
- **Interactive dashboard reports** with Chart.js analytics
- **Modern responsive design** following Microsoft Fluent principles
- **Real-time charts**: Task distribution, system resources, execution timeline, security radar
- **Health scoring system** with visual indicators and recommendations
- **Performance analytics** with operation timing and trend analysis
- **Actionable insights** with priority-based recommendation engine

#### **Advanced Configuration** (`config/logging-config.json`)
```json
{
  "logging": {
    "enablePerformanceTracking": true,
    "enableStructuredLogging": true,
    "logBufferSize": 1000
  },
  "reporting": {
    "enableDashboardReports": true,
    "autoGenerateReports": true,
    "includePerformanceMetrics": true
  },
  "performance": {
    "trackOperationTiming": true,
    "slowOperationThreshold": 30.0
  }
}
```

#### **Key Functions Added**
- `Initialize-LoggingSystem` - Sets up logging infrastructure
- `Write-LogEntry` - Structured logging with levels and components
- `Start/Complete-PerformanceTracking` - Operation timing
- `Get-LogData` / `Export-LogData` - Data retrieval and export
- Enhanced `New-MaintenanceReport` - Interactive dashboard generation

#### **Usage Examples**
```powershell
# Initialize enhanced logging
Initialize-LoggingSystem -LoggingConfig $config

# Structured logging throughout operations
Write-LogEntry -Level 'INFO' -Component 'ORCHESTRATOR' -Message 'Starting maintenance'

# Performance tracking
$perf = Start-PerformanceTracking -OperationName 'BloatwareRemoval'
Complete-PerformanceTracking -PerformanceContext $perf -Success $true

# Generate comprehensive reports with analytics
New-MaintenanceReport -SystemInventory $inventory -TaskResults $results
```

#### **Professional Benefits**
- **Executive dashboards** with health scoring and visual analytics
- **Complete audit trails** with structured logging and exports
- **Performance optimization** through detailed timing analysis
- **Compliance reporting** with multi-format data exports
- **Actionable insights** with automated recommendation generation

## 🆕 Enhanced File Organization System (v2.1)

### Major v2.1 Enhancements

The system now includes **enterprise-grade file organization and management capabilities**:

#### **FileOrganizationManager Module** (`modules/core/FileOrganizationManager.psm1`)
- **Session-based organization** with unique session directories for each maintenance run
- **Structured directory hierarchy**: logs/, data/, reports/, temp/ with logical subcategories
- **Standardized file operations**: `Get-OrganizedFilePath()`, `Save-OrganizedFile()` for consistent file handling
- **Automatic cleanup**: Configurable retention policies prevent disk space issues
- **Multi-format support**: JSON, Text, CSV, XML with proper encoding and formatting

#### **Enhanced temp_files Structure**
```
temp_files/
├── session-YYYYMMDD-HHMMSS/          # Current session directory
│   ├── logs/                         # All logging files
│   │   ├── session.log              # Main session log
│   │   ├── orchestrator.log         # MaintenanceOrchestrator logs
│   │   └── modules/                 # Module-specific logs
│   ├── data/                        # Structured data files
│   │   ├── inventory/               # System inventory data
│   │   ├── apps/                    # Application-related data
│   │   └── security/                # Security audit data
│   ├── reports/                     # Final reports and summaries
│   └── temp/                        # Temporary processing files
├── cleanup-policy.json               # Retention settings
└── (previous sessions per policy)
```

#### **Key Benefits Achieved**
- **🔄 Eliminated File Proliferation**: No more multiple timestamped files from different runs
- **📋 Populated Logs Directory**: LoggingManager now properly creates structured logs
- **🗂️ Professional Organization**: Clear directory structure like enterprise systems
- **🧹 Automatic Cleanup**: Old sessions cleaned up automatically per configurable policies
- **⚡ Better Performance**: Reduced file system clutter improves I/O performance
- **🔍 Easy Debugging**: Clear separation between logs, data, and reports

#### **Integration with All Modules**
- **EssentialApps**: Uses organized storage, eliminated redundant .ps1 script generation
- **BloatwareRemoval**: Organized bloatware analysis with proper categorization
- **SystemInventory**: Structured inventory data placement in dedicated directories
- **SecurityAudit**: Organized security audit data and reports
- **ReportGeneration**: Enhanced to work seamlessly with organized file system
- **LoggingManager**: Integrated with FileOrganizationManager for structured log placement

#### **Usage Examples**
```powershell
# Initialize file organization (done automatically in MaintenanceOrchestrator)
Initialize-FileOrganization -BaseDir $ScriptRoot -SessionId $sessionId

# Save data using organized file system
$analysisData = @{ /* your data */ }
$filePath = Save-OrganizedFile -Data $analysisData -FileType 'Data' -Category 'apps' -FileName 'analysis' -Format 'JSON'

# Get organized file path
$logPath = Get-OrganizedFilePath -FileType 'Log' -Category 'modules' -FileName 'my-module.log'

# Retrieve files from previous sessions
$oldReports = Get-SessionFiles -MaxAge 7 -FileType 'Report'
```

-- -

## 🎯 Architecture & Core Concepts

### Why This Structure Exists

#### 🔧 Modular Architecture
The system is built from specialized PowerShell modules, each with a single responsibility:
- * * Type 1 modules**: Inventory/reporting (read-only operations)
- * * Type 2 modules**: System modifications (write operations)
- * * Core modules**: Infrastructure (configuration, menus, dependencies, scheduling)

#### 🚀 Launcher → Orchestrator Design
- `script.bat` prepares environment (elevation, dependency bootstrap, scheduled tasks, downloads)
- Delegates to `MaintenanceOrchestrator.ps1` for actual task execution
- * * Important**: Avoid editing elevation logic in PowerShell — it's centralized in the batch launcher

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

4. **`modules/core/LoggingManager.psm1`** — 🆕 Enhanced logging system
   - `Initialize-LoggingSystem`, `Write-LogEntry`, `Start/Complete-PerformanceTracking`
   - Structured logging with session tracking and performance metrics
   - Multi-destination output and data export capabilities

5. **`modules/core/FileOrganizationManager.psm1`** — 🆕 File organization system 
   - `Initialize-FileOrganization`, `Get-OrganizedFilePath`, `Save-OrganizedFile`
   - Session-based directory management with automatic cleanup
   - Standardized file operations across all modules

6. **`modules/type1/ReportGeneration.psm1`** — 🆕 Enhanced dashboard reporting
   - `New-MaintenanceReport` with interactive dashboard analytics
   - Chart.js integration for real-time visualizations
   - Health scoring and recommendation engine

7. **`Enhanced-MaintenanceOrchestrator-Example.ps1`** — 🆕 Integration example
   - Shows how to use the new logging and reporting features
   - Performance tracking throughout task execution
   - Comprehensive analytics integration

8. **`config/logging-config.json`** — 🆕 Enhanced logging configuration
   - Configuration settings for logging system and file organization
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
# Basic execution with enhanced logging
.\MaintenanceOrchestrator.ps1

# Enhanced execution with detailed logging
.\Enhanced-MaintenanceOrchestrator-Example.ps1 -EnableDetailedLogging

# Dry-run mode (simulate without changes)
.\MaintenanceOrchestrator.ps1 -DryRun

# Run specific tasks only
.\MaintenanceOrchestrator.ps1 -TaskNumbers "1,3,5"

# Non-interactive with specific tasks and reporting
.\Enhanced-MaintenanceOrchestrator-Example.ps1 -NonInteractive -TaskNumbers "2,4" -GenerateReport
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
code config/logging-config.json  # 🆕 Enhanced logging configuration

# Never hardcode values in modules - always use config files
```

#### 🆕 Enhanced Logging Integration
```powershell
# Initialize logging in modules
Import-Module "modules/core/LoggingManager.psm1"
$loggingConfig = Get-LoggingConfiguration
Initialize-LoggingSystem -LoggingConfig $loggingConfig

# Use structured logging instead of Write-Host
Write-LogEntry -Level 'INFO' -Component 'TYPE2' -Message 'Starting operation'

# Track performance for operations
$perf = Start-PerformanceTracking -OperationName 'BloatwareRemoval'
# ... perform operation ...
Complete-PerformanceTracking -PerformanceContext $perf -Success $true

# Export comprehensive logs and reports
Export-LogData -OutputPath 'temp_files/logs/session-log' -Format 'All'
```

#### 🆕 File Organization Integration
```powershell
# Initialize file organization (done automatically in MaintenanceOrchestrator)
Initialize-FileOrganization -BaseDir $ScriptRoot -SessionId $sessionId

# Save data using organized file system
$analysisData = @{ /* your data */ }
$filePath = Save-OrganizedFile -Data $analysisData -FileType 'Data' -Category 'apps' -FileName 'analysis' -Format 'JSON'

# Get organized file path for any module
$logPath = Get-OrganizedFilePath -FileType 'Log' -Category 'modules' -FileName 'my-module.log'

# Retrieve files from previous sessions for analysis
$oldReports = Get-SessionFiles -MaxAge 7 -FileType 'Report'
$recentLogs = Get-SessionFiles -MaxAge 1 -FileType 'Log' -Category 'modules'

# Work with session-based organization
# All files are automatically organized into: temp_files/session-YYYYMMDD-HHMMSS/
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

#### 🚨 **CRITICAL: Current Code Quality Status (Oct 2025)**

**As of October 11, 2025, the project has 3,080 PSScriptAnalyzer violations:**
- **926 Warnings** (high priority fixes needed)
- **2,154 Information** (style and consistency improvements)
- **0 Errors** (good - no syntax or critical issues)

**Priority 1 - Critical Warnings to Fix:**

1. **PSAvoidUsingWriteHost (67 violations in TelemetryDisable.psm1, 25 in WindowsUpdates.psm1)**
   ```powershell
   # ❌ WRONG: Write-Host is not PowerShell best practice
   Write-Host "✓ Success" -ForegroundColor Green
   Write-Host "❌ Failed" -ForegroundColor Red
   
   # ✅ CORRECT: Use appropriate PowerShell streams
   Write-Information "✓ Success" -InformationAction Continue
   Write-Warning "⚠️ Warning message"
   Write-Error "❌ Error message"
   Write-Verbose "🔍 Debug information"
   
   # For user-facing output in functions
   Write-Output "Operation completed successfully"
   ```

2. **PSUseSingularNouns (7 violations)**
   ```powershell
   # ❌ WRONG: Plural nouns in function names
   function Test-PrivacySettings { }
   function Set-TelemetryRegistrySettings { }
   function Disable-TelemetryServices { }
   
   # ✅ CORRECT: Singular nouns
   function Test-PrivacySetting { }
   function Set-TelemetryRegistrySetting { }
   function Disable-TelemetryService { }
   ```

3. **PSUseShouldProcessForStateChangingFunctions (1 violation)**
   ```powershell
   # ❌ WRONG: Missing ShouldProcess for state changes
   function Set-TelemetryRegistrySetting {
       [CmdletBinding()]
       param($Setting, $Value)
       Set-ItemProperty -Path $Path -Name $Setting -Value $Value
   }
   
   # ✅ CORRECT: Include ShouldProcess support
   function Set-TelemetryRegistrySetting {
       [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='Medium')]
       param($Setting, $Value)
       
       if ($PSCmdlet.ShouldProcess($Setting, 'Set registry value')) {
           Set-ItemProperty -Path $Path -Name $Setting -Value $Value
           return $true
       }
       return $false
   }
   ```

4. **PSUseOutputTypeCorrectly (9 violations)**
   ```powershell
   # ❌ WRONG: Missing OutputType attribute
   function Get-SystemInfo {
       [CmdletBinding()]
       param()
       return @{ Status = 'Success'; Data = $data }
   }
   
   # ✅ CORRECT: Explicit OutputType declaration
   function Get-SystemInfo {
       [CmdletBinding()]
       [OutputType([hashtable])]
       param()
       return @{ Status = 'Success'; Data = $data }
   }
   ```

**Priority 2 - Style and Consistency Issues:**

1. **PSAvoidTrailingWhitespace (2,154 violations)**
   - Remove all trailing spaces and tabs from line endings
   - Configure VS Code to show and auto-remove trailing whitespace

2. **PSUseBOMForUnicodeEncodedFile (2 violations)**
   ```powershell
   # Fix encoding for TelemetryDisable.psm1 and WindowsUpdates.psm1
   # Save files with UTF-8 BOM encoding
   ```

3. **PSAvoidDefaultValueSwitchParameter (6 violations in WindowsUpdates.psm1)**
   ```powershell
   # ❌ WRONG: Switch parameters should not default to $true
   [Parameter()]
   [switch]$EnableFeature = $true
   
   # ✅ CORRECT: Let switches default to $false naturally
   [Parameter()]
   [switch]$EnableFeature
   ```

#### 🛠️ **Immediate Action Required**

**Before any new development, address these violations in this order:**

1. **TelemetryDisable.psm1** - 67 Write-Host + trailing whitespace + plural nouns
2. **WindowsUpdates.psm1** - 25 Write-Host + switch parameter defaults + unused parameters
3. **All modules** - Add OutputType attributes to functions
4. **All modules** - Remove trailing whitespace (can be automated)
5. **All modules** - Add comprehensive comment-based help

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
- [ ] **No Write-Host**: Use Write-Information, Write-Output, Write-Verbose instead
- [ ] **OutputType**: All functions have proper `[OutputType()]` attributes
- [ ] **No trailing whitespace**: Lines are clean and properly formatted

### 🔔 Mandatory Assistant Actions

- Regularly monitor and act on VS Code diagnostics (Problems panel) during editing. Treat parser errors and warnings as blockers to resolve immediately.
- When you encounter unused variables:
    - First, try to understand the original intent and restore the functionality that depended on them.
    - If the variable is truly redundant, remove it cleanly along with any dead code paths tied to it.
- When VS Code diagnostics surface errors or warnings, immediately add a concise "Notes to self — Diagnostics" entry in this document capturing: the rule/code or message, root cause, a prevention rule, and a quick fix example. Keep this list current to prevent repeats.

### 🏗️ **Standardized Patterns & Templates**

#### **Standard Function Template**

All new functions must follow this template:

```powershell
<#
.SYNOPSIS
    Brief one-line description of what the function does.

.DESCRIPTION
    Detailed description explaining the function's purpose, behavior, and any
important implementation details.

.PARAMETER ParameterName
Description of what this parameter does and expected values.

.EXAMPLE
FunctionName -Parameter "Value"
Description of what this example does.

.EXAMPLE
FunctionName -Parameter "Value" -WhatIf
Description of dry-run example.

.OUTPUTS
[PSCustomObject] for Type 1 modules (data objects)
[bool] for Type 2 modules (success/failure)

.NOTES
Author: Windows Maintenance Automation Project
Module Type: Core/Type1/Type2
Dependencies: List any module dependencies
Version: 1.0.0
#>
function Verb-SingularNoun {
    [CmdletBinding(SupportsShouldProcess = $true)]  # For Type 2 modules only
    [OutputType([PSCustomObject])]  # Adjust type as appropriate
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$RequiredParameter,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet('Option1', 'Option2', 'Option3')]
        [string]$OptionalParameter = 'Option1',
        
        [Parameter(Mandatory = $false)]
        [switch]$Force
    )
    
    begin {
        Write-Verbose "Starting $($MyInvocation.MyCommand.Name)"
        
        # Initialize variables
        $results = @()
    }
    
    process {
        try {
            $ErrorActionPreference = 'Stop'
            
            # Type 2 modules: Check ShouldProcess
            if ($PSCmdlet.ShouldProcess($RequiredParameter, 'Perform operation')) {
                Write-Verbose "Processing: $RequiredParameter"
                
                # Main logic here
                $operationResult = Invoke-SomeOperation -Parameter $RequiredParameter
                
                Write-Verbose "Operation completed successfully"
                
                # Type 1: Return data object
                return [PSCustomObject]@{
                    Status    = 'Success'
                    Data      = $operationResult
                    Timestamp = Get-Date
                }
                
                # Type 2: Return boolean
                # return $true
            }
            else {
                Write-Information "⏭️ Skipped operation (WhatIf mode)" -InformationAction Continue
                return $false  # Type 2 modules
            }
        }
        catch {
            Write-Error "Operation failed: $_"
            Write-Verbose $_.Exception.Message
            
            # Type 1: Return null or error object
            return $null
            
            # Type 2: Return false
            # return $false
        }
    }
    
    end {
        Write-Verbose "Completed $($MyInvocation.MyCommand.Name)"
    }
}
```

#### **Standard Error Handling Pattern**

```powershell
# Consistent error handling across all modules
try {
    $ErrorActionPreference = 'Stop'
    Write-Verbose "Starting operation: $operationName"
    
    # Perform operation
    $result = Invoke-Operation -Parameters $params
    
    # Log success
    Write-Verbose "✓ Operation succeeded: $operationName"
    Write-Information "✓ $successMessage" -InformationAction Continue
    
    return $result  # or $true for Type 2
}
catch {
    # Comprehensive error logging
    $errorMessage = "❌ Operation failed: $operationName - $($_.Exception.Message)"
    Write-Error $errorMessage
    Write-Verbose "Error details: $($_.Exception.ToString())"
    
    # Optional: Add to error collection for reporting
    if ($ErrorCollection) {
        $ErrorCollection.Add(@{
                Operation = $operationName
                Error     = $_.Exception.Message
                Timestamp = Get-Date
            })
    }
    
    return $null  # or $false for Type 2
}
finally {
    # Cleanup code here
    $ErrorActionPreference = 'Continue'
}
```

#### **Standard Output Patterns**

```powershell
# ✅ CORRECT: User-facing messages
Write-Information "🔄 Starting system analysis..." -InformationAction Continue
Write-Information "✓ Analysis completed successfully" -InformationAction Continue
Write-Information "⚠️ Some items require attention" -InformationAction Continue

# ✅ CORRECT: Debug and verbose logging
Write-Verbose "Processing item: $itemName"
Write-Debug "Variable state: $($variable | ConvertTo-Json)"

# ✅ CORRECT: Warnings and errors
Write-Warning "⚠️ Configuration file not found, using defaults"
Write-Error "❌ Critical operation failed: $errorDetails"

# ✅ CORRECT: Function return values
Write-Output $resultObject  # For pipeline compatibility
return $resultObject        # For direct function calls
```

### 🧪 **Testing Framework Requirements**

#### **Pester Test Structure**

Create comprehensive tests following this structure:

```
tests/
├── Core.Tests.ps1              # Core module tests
├── Type1Modules.Tests.ps1      # Read-only module tests
├── Type2Modules.Tests.ps1      # System modification tests
├── Integration.Tests.ps1       # End-to-end workflow tests
└── Helpers/
├── MockData.ps1           # Test data and mock objects
└── TestUtilities.ps1      # Shared test functions
```

#### **Test Template Example**

```powershell
# Example: ConfigManager.Tests.ps1
Describe "ConfigManager Module Tests" {
    BeforeAll {
        Import-Module "$PSScriptRoot\..\modules\core\ConfigManager.psm1" -Force
        $testConfigPath = "$PSScriptRoot\TestData\config"
    }
    
    Describe "Initialize-ConfigSystem" {
        It "Should initialize with valid config path" {
            { Initialize-ConfigSystem -ConfigRootPath $testConfigPath } | Should -Not -Throw
        }
        
        It "Should throw for invalid path" {
            { Initialize-ConfigSystem -ConfigRootPath "C:\NonExistent" } | Should -Throw
        }
    }
    
    Describe "Get-MainConfiguration" {
        It "Should return configuration object" {
            $config = Get-MainConfiguration
            $config | Should -Not -BeNullOrEmpty
            $config.execution | Should -Not -BeNullOrEmpty
        }
    }
}
```

#### **Mock Strategy for System Operations**

```powershell
# Mock external dependencies in Type 2 tests
BeforeAll {
    Mock Get-AppxPackage { return @{ Name = "TestApp"; Version = "1.0" } }
    Mock Remove-AppxPackage { return $true }
    Mock Set-ItemProperty { return $true }
}
```

-- -

## 🧪 Testing Guidelines

### MANDATORY Testing Procedures

* * ⚠️ CRITICAL: All testing must be conducted in the TestFolder**

When you need to create test scripts, run tests, or verify functionality, you **MUST** use the TestFolder located at the same path level as script_mentenanta:

```
Desktop\Projects\
├── script_mentenanta\     (main project)
└── TestFolder\            (testing environment - USE THIS)
```

**Mandatory Testing Workflow:**
1. * * Clean TestFolder**: Always start by cleaning the TestFolder from any previous contents
2. * * Copy launcher**: Copy the latest version of `script.bat` from script_mentenanta to TestFolder
3. * * Execute from TestFolder**: Run `script.bat` from within the TestFolder directory
4. * * Observe project unfolding**: Watch the complete project download, setup, and execution process

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

-- -

## 🔗 Integration & Dependencies

### External Tools & Package Managers

The system relies on several external tools managed by the `DependencyManager` module:

| Tool | Purpose | Installation Order |
| ------ | -------- - | ------------------ - |
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

1. * * Core modules** (infrastructure):
- `ConfigManager.psm1` — Configuration loading
- `MenuSystem.psm1` — Interactive menus
- `DependencyManager.psm1` — Package management
- `LoggingManager.psm1` — Centralized logging system

2. * * Type 1 modules** (read-only operations):
- Can depend on Core modules only
- No dependencies on Type 2 modules

3. * * Type 2 modules** (system modifications):
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

-- -

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
│   │   └── LoggingManager.psm1 ..... Centralized logging system
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
$env:PSModulePath -split '; '

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

## Notes to self — Diagnostics

Maintain a running list of recurring VS Code diagnostics and analyzer findings. For each item, capture:

- Rule/Message: Identifier or message text
- Root cause: Why it happens in this repo
- Prevention: Guardrail to avoid reintroducing
- Quick fix: Minimal corrective example

Seed entries

1) Rule/Message: PSAvoidUsingWriteHost
- Root cause: Legacy modules use Write-Host for status output
- Prevention: Use Write-Information/Write-Warning/Write-Error and return values instead of host output
- Quick fix: Replace Write-Host "✓ Success" with Write-Information "✓ Success" -InformationAction Continue

2) Rule/Message: PSAvoidDefaultValueSwitchParameter
- Root cause: Some switch parameters default to $true
- Prevention: Do not assign default values to [switch] parameters; use explicit boolean if needed
- Quick fix: Change [switch]$EnableFeature = $true to [switch]$EnableFeature

3) Rule/Message: PSUseShouldProcessForStateChangingFunctions
- Root cause: Missing SupportsShouldProcess on functions that modify system state
- Prevention: Decorate with [CmdletBinding(SupportsShouldProcess = $true)] and gate actions with $PSCmdlet.ShouldProcess()
- Quick fix: Add attribute and wrap Set-ItemProperty calls in ShouldProcess check

### When to Ask for Clarification

If you're unsure about:
1. * * Environment constraints**: Local dev vs managed enterprise endpoint vs air-gapped system
2. * * Permissions**: Whether modifying scheduled task behavior or restart policy is permitted
3. * * Feature toggles**: Whether new features should be enabled by default or opt-in
4. * * Breaking changes**: Impact of modifying configuration schemas or return value contracts
5. * * Security implications**: Changes affecting elevation, registry access, or system modifications

-- -

## 📝 Document Maintenance

**Last Updated**: October 12, 2025  
**Document Version**: 2.3.1  
**Project Version**: Enhanced File Organization v2.1

### Changelog

- **v2.3.1 (Oct 12, 2025)**: Policy update — added mandatory requirement to record diagnostics "Notes to self" and introduced the dedicated section with seed entries.
- **v2.3 (Oct 12, 2025)**: 🆕 **MAJOR ENHANCEMENT** - Added FileOrganizationManager.psm1 with session-based file organization, eliminated file proliferation, implemented automatic cleanup, and created comprehensive testing suite. Complete temp_files restructuring with enterprise-grade organization.
- **v2.2 (Oct 11, 2025)**: 🆕 **MAJOR ENHANCEMENT** - Added comprehensive logging infrastructure (LoggingManager.psm1), interactive dashboard reporting with Chart.js analytics, health scoring system, performance tracking, and multi-format data exports. Complete system transformation to enterprise-grade capabilities.
- **v2.1 (Oct 11, 2025)**: Added comprehensive code quality guidelines, PSScriptAnalyzer violation fixes, standardized templates, testing framework requirements
- **v2.0 (Oct 2025)**: Complete restructure with TOC, expanded PowerShell best practices, added comprehensive code examples
- **v1.0 (Initial)**: Basic structure with core concepts and workflows

### 🆕 v2.1 Enhancement Summary

**Revolutionary Upgrades Completed:**
- **FileOrganizationManager Module** - Session-based file organization with structured directory hierarchies, automatic cleanup, and standardized file operations
- **Enhanced LoggingManager Module** - Centralized structured logging with session tracking, performance metrics, and multi-format exports
- **Eliminated File Proliferation** - No more multiple timestamped files; clean session-based organization prevents file duplication
- **Professional temp_files Structure** - Enterprise-grade directory organization with logs/, data/, reports/, temp/ categorization
- **Enhanced ReportGeneration** - Interactive dashboard with Chart.js, health scoring, recommendations, and modern responsive design
- **Comprehensive Testing Suite** - Full integration testing with Test-ComprehensiveFileOrganization.ps1 and documentation
- **Advanced Configuration** - Extended logging-config.json with file organization settings and cleanup policies
- **Integration Examples** - Complete Enhanced-MaintenanceOrchestrator-Example.ps1 showing new capabilities
- **Professional Documentation** - Comprehensive analysis, usage guides, and troubleshooting instructions

This represents the most significant architectural enhancement in the project's history, transforming it from a basic maintenance script into a professional, enterprise-grade system management solution with clean, organized file management.
