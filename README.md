# Windows Maintenance Automation

A modular Windows 10/11 maintenance system with an elevated launcher, interactive/dry-run execution, configuration-driven behavior, and comprehensive reporting.

For full details (architecture, modules, usage, testing, contributor guide), see sections below.

## Highlights
- Modular architecture: Type 1 (inventory/reporting) and Type 2 (system modification)
- Robust launcher: elevation, reboot-resume, monthly task, System Protection + restore point, dependency bootstrap
- Interactive and unattended modes with countdown menus and safe defaults
- JSON configuration and HTML/text reporting
- Mandatory TestFolder workflow for end-to-end testing

## Project structure

```
script_mentenanta/
├── script.bat
├── MaintenanceOrchestrator.ps1
├── modules/
│   ├── type1/
│   │   ├── SystemInventory.psm1
│   │   ├── BloatwareDetection.psm1
│   │   ├── SecurityAudit.psm1
│   │   └── ReportGeneration.psm1
│   ├── type2/
│   │   ├── BloatwareRemoval.psm1
│   │   ├── EssentialApps.psm1
│   │   ├── WindowsUpdates.psm1
│   │   ├── TelemetryDisable.psm1
│   │   └── SystemOptimization.psm1
│   └── core/
│       ├── ConfigManager.psm1
│       ├── MenuSystem.psm1
│       ├── DependencyManager.psm1
│       └── TaskScheduler.psm1
├── config/
│   ├── bloatware-list.json
│   ├── essential-apps.json
│   ├── main-config.json
│   └── logging-config.json
└── archive/
    └── script-original.ps1 (legacy, reference only)
```

## Launcher sequence (pre-orchestrator)
- Check admin; auto-elevate via UAC if needed
- Remove leftover startup task `WindowsMaintenanceStartup`
- Detect pending restart; if pending, create `WindowsMaintenanceStartup` (SYSTEM, Highest) and restart; resume and clean up after boot
- Ensure monthly task `WindowsMaintenanceAutomation` exists (1st, 01:00, SYSTEM, Highest) targeting `script.bat -NonInteractive`
- Ensure System Protection is enabled on system drive; create and verify a System Restore Point
- Bootstrap dependencies: PowerShell 7, winget, NuGet, PowerShellGet, PSWindowsUpdate, Chocolatey
- Launch `MaintenanceOrchestrator.ps1`

## Usage

Interactive (default):
- Countdown menus for execution mode and task selection; safe defaults after timeout

Non-interactive and dry-run examples:
```powershell
./MaintenanceOrchestrator.ps1 -NonInteractive
./MaintenanceOrchestrator.ps1 -DryRun -TaskNumbers "1,3,5"
```

Via launcher:
```powershell
./script.bat
./script.bat -NonInteractive
./script.bat -DryRun
./script.bat -TaskNumbers 1,3,5
```

## Tasks and modules

Type 1 (read-only):
- SystemInventory: Get-SystemInventory, Export-SystemInventory
- BloatwareDetection: Find-InstalledBloatware, Get-BloatwareStatistics, Test-BloatwareDetection
- SecurityAudit: Start-SecurityAudit, Get-WindowsDefenderStatus
- ReportGeneration: New-MaintenanceReport

Type 2 (system changes):
- BloatwareRemoval: Remove-DetectedBloatware, Test-BloatwareRemoval
- EssentialApps: Install-EssentialApplications, Get-AppsNotInstalled, Get-InstallationStatistics
- WindowsUpdates: Install-WindowsUpdates, Get-WindowsUpdateStatus
- TelemetryDisable: Disable-WindowsTelemetry, Test-PrivacySettings
- SystemOptimization: Optimize-SystemPerformance, Get-SystemPerformanceMetrics

Conventions for Type 2 modules:
- [CmdletBinding(SupportsShouldProcess=$true)], respect -WhatIf/-Confirm and repo-wide -DryRun
- Return $true on success, $false on failure

## Configuration

- bloatware-list.json: detection/removal patterns
- essential-apps.json: curated app list for installation
- main-config.json: execution defaults and toggles
- logging-config.json: log levels and formats

Example main-config.json snippet:
```json
{
  "execution": {"defaultMode": "unattended", "countdownSeconds": 20, "enableDryRun": true},
  "modules": {"skipBloatwareRemoval": false, "skipEssentialApps": false, "skipWindowsUpdates": false}
}
```

## Mandatory TestFolder workflow
Run end-to-end tests in a sibling `TestFolder` to simulate a fresh deployment.

```powershell
Remove-Item "C:\Users\Bogdan\OneDrive\Desktop\Projects\TestFolder\*" -Recurse -Force -ErrorAction SilentlyContinue
Copy-Item "C:\Users\Bogdan\OneDrive\Desktop\Projects\script_mentenanta\script.bat" "C:\Users\Bogdan\OneDrive\Desktop\Projects\TestFolder\" -Force
Set-Location "C:\Users\Bogdan\OneDrive\Desktop\Projects\TestFolder"
./script.bat
```

## Developer guide (quick)

- Task registry entries in `MaintenanceOrchestrator.ps1`: Name, Description, ModulePath, Function, Type, Category
- Approved verbs only; advanced functions with comment-based help
- Validate parameters; avoid aliases; use ShouldProcess for destructive actions
- Use `Get-MainConfiguration` and JSON files for settings; don’t hardcode
- Wrap external tools safely; check exit codes; log errors
- Run `Invoke-ScriptAnalyzer -Path . -Recurse` before commits

## Support and license

- Issues: open on GitHub with `maintenance.log` attached when relevant
- License: MIT (see LICENSE)

---

Made for reliable Windows maintenance and easy extensibility.

## Quick instructions (AI assistants)

Use this README as the single source of truth. When editing code:

- Follow module contracts: Type 1 returns data; Type 2 changes state and uses ShouldProcess, returns $true/$false
- Don’t duplicate launcher logic (elevation, scheduled tasks, System Protection, restore point, dependencies)
- Load config via ConfigManager from `config/*.json` (no hardcoding)
- Respect `-DryRun`, `-WhatIf`, `-Confirm` everywhere destructive
- Keep functions small, use approved verbs, add comment-based help
- Wrap external commands safely and check ExitCode
- Run `Invoke-ScriptAnalyzer -Path . -Recurse` before committing

Required testing workflow (always):
1) Clean TestFolder
2) Copy latest `script.bat` there
3) Run from TestFolder and observe bootstrap, tasks, restore point, orchestrator

Implementation checklist:
- Add new tasks in `MaintenanceOrchestrator.ps1` (Name, Description, ModulePath, Function, Type, Category)
- Export functions in modules and respect return contracts
- Use JSON config, log clearly, and guard all destructive actions with ShouldProcess

## Architecture diagrams

### System Architecture Overview

```mermaid
graph TB
  %% Entry Points
  User[👤 User] --> Launcher[script.bat<br/>Enhanced Launcher]
  User --> Direct[MaintenanceOrchestrator.ps1<br/>Direct Execution]
    
  %% Launcher Flow
  Launcher --> ElevCheck{Administrator<br/>Check}
  ElevCheck -->|Not Elevated| UAC[Request UAC<br/>Elevation]
  ElevCheck -->|Elevated| DepMgr[Dependency<br/>Bootstrap]
  UAC --> DepMgr
    
  %% Dependency Bootstrap
  DepMgr --> PS7{PowerShell 7<br/>Available?}
  PS7 -->|No| InstallPS7[Install PowerShell 7<br/>via winget/GitHub]
  PS7 -->|Yes| WinGet{winget<br/>Available?}
  InstallPS7 --> WinGet
  WinGet -->|No| InstallWinGet[Install App Installer<br/>Microsoft Store/GitHub]
  WinGet -->|Yes| NuGet{NuGet Provider<br/>Available?}
  InstallWinGet --> NuGet
  NuGet -->|No| InstallNuGet[Install NuGet Provider<br/>PowerShell Gallery]
  NuGet -->|Yes| PSWinUpdate{PSWindowsUpdate<br/>Available?}
  InstallNuGet --> PSWinUpdate
  PSWinUpdate -->|No| InstallPSWU[Install PSWindowsUpdate<br/>PowerShell Gallery]
  PSWinUpdate -->|Yes| Choco{Chocolatey<br/>Available?}
  InstallPSWU --> Choco
  Choco -->|No| InstallChoco[Install Chocolatey<br/>chocolatey.org]
  Choco -->|Yes| LaunchOrch[Launch Orchestrator]
  InstallChoco --> LaunchOrch
    
  %% Direct execution joins here
  Direct --> LaunchOrch
    
  %% Orchestrator Flow
  LaunchOrch --> Orchestrator[MaintenanceOrchestrator.ps1<br/>Central Coordinator]
  Orchestrator --> LoadCore[Load Core Modules]
  LoadCore --> LoadConfig[Initialize Configuration]
  LoadConfig --> ParseArgs[Parse Command Line<br/>Arguments]
    
  %% Menu System
  ParseArgs --> Interactive{Interactive<br/>Mode?}
  Interactive -->|Yes| MainMenu[Show Main Menu<br/>20s Countdown]
  Interactive -->|No| NonInt[Non-Interactive<br/>Execution]
  MainMenu --> ExecMode{Execution<br/>Mode?}
  ExecMode -->|Execute| TaskMenu[Show Task Menu<br/>All/Specific Tasks]
  ExecMode -->|DryRun| TaskMenuDR[Show Task Menu<br/>Dry-Run Mode]
  TaskMenu --> TaskExec[Task Execution]
  TaskMenuDR --> TaskExecDR[Task Execution<br/>Dry-Run Mode]
  NonInt --> TaskExec
    
  %% Core Modules
  subgraph CoreMods[Core Infrastructure Modules]
    ConfigMgr[ConfigManager.psm1<br/>Configuration Management]
    MenuSys[MenuSystem.psm1<br/>Interactive Menus]
    DepMgrMod[DependencyManager.psm1<br/>Package Management]
    TaskSched[TaskScheduler.psm1<br/>Windows Task Scheduling]
  end
    
  LoadCore --> CoreMods
    
  %% Task Execution Engine
  TaskExec --> TaskRegistry[Task Registry<br/>$Tasks Array]
  TaskExecDR --> TaskRegistry
  TaskRegistry --> LoadMod[Load Task Module<br/>On-Demand]
    
  %% Module Types
  LoadMod --> ModType{Module<br/>Type?}
  ModType -->|Type 1| Type1Mods[Type 1: Inventory & Reporting]
  ModType -->|Type 2| Type2Mods[Type 2: System Modification]
    
  %% Type 1 Modules (Inventory & Reporting)
  subgraph Type1[Type 1 Modules - Read-Only Operations]
    SysInv[SystemInventory.psm1<br/>System Information]
    BloatDet[BloatwareDetection.psm1<br/>Bloatware Scanning]
    SecAudit[SecurityAudit.psm1<br/>Security Analysis]
    RepGen[ReportGeneration.psm1<br/>HTML/Text Reports]
  end
    
  Type1Mods --> Type1
    
  %% Type 2 Modules (System Modification)
  subgraph Type2[Type 2 Modules - System Changing Operations]
    BloatRem[BloatwareRemoval.psm1<br/>Application Removal]
    EssApps[EssentialApps.psm1<br/>Application Installation]
    WinUpd[WindowsUpdates.psm1<br/>Update Management]
    TelDis[TelemetryDisable.psm1<br/>Privacy Hardening]
    SysOpt[SystemOptimization.psm1<br/>Performance Tuning]
  end
    
  Type2Mods --> Type2
    
  %% Configuration System
  subgraph ConfigSys[Configuration System - JSON Files]
    MainConf[main-config.json<br/>Global Settings]
    LogConf[logging-config.json<br/>Logging Configuration]
    BloatConf[bloatware-list.json<br/>Definitions]
    AppConf[essential-apps.json<br/>Application Lists]
  end
    
  ConfigMgr --> ConfigSys
    
  %% Output and Reporting
  Type1 --> DataOut[Data Objects<br/>System Information]
  Type2 --> BoolOut[Success/Failure<br/>Boolean Results]
  DataOut --> Reports[Generated Reports<br/>temp_files/reports/]
  BoolOut --> Logging[Operation Logs<br/>temp_files/logs/]
    
  %% Task Results
  Reports --> Results[Task Results<br/>Summary & Details]
  Logging --> Results
  Results --> Complete[Maintenance<br/>Complete]
```

### Module Interaction Flow

```mermaid
sequenceDiagram
  participant User
  participant Launcher as script.bat
  participant Orch as MaintenanceOrchestrator.ps1
  participant Core as Core Modules
  participant T1 as Type 1 Module
  participant T2 as Type 2 Module
  participant Config as Configuration
    
  User->>Launcher: Execute script.bat
  Launcher->>Launcher: Check elevation & dependencies
  Launcher->>Orch: Launch orchestrator
    
  Orch->>Core: Load ConfigManager & MenuSystem
  Core->>Config: Load JSON configurations
  Config-->>Core: Return settings
  Core-->>Orch: Modules ready
    
  Orch->>Orch: Parse command line arguments
    
  alt Interactive Mode
    Orch->>Core: Show main menu (20s countdown)
    Core-->>User: Display options
    User->>Core: Select execution mode
    Core-->>Orch: Return selection
        
    Orch->>Core: Show task selection menu
    Core-->>User: Display task options
    User->>Core: Select tasks
    Core-->>Orch: Return task selection
  else Non-Interactive Mode
    Orch->>Orch: Use default settings
  end
    
  loop For each selected task
    Orch->>Orch: Load task module
        
    alt Type 1 Task (Inventory/Reporting)
      Orch->>T1: Execute inventory function
      T1->>T1: Collect system information
      T1-->>Orch: Return data objects
    else Type 2 Task (System Modification)
      alt Dry-Run Mode
        Orch->>T2: Execute with -DryRun
        T2->>T2: Simulate changes
        T2-->>Orch: Return simulation results
      else Normal Mode
        Orch->>T2: Execute modification function
        T2->>T2: Apply system changes
        T2-->>Orch: Return success/failure
      end
    end
        
    Orch->>Orch: Record task results
  end
    
  Orch->>Orch: Generate execution summary
  Orch-->>User: Display results and completion
```

### Configuration Flow

```mermaid
graph LR
  %% Configuration Sources
  JSONFiles[JSON Configuration Files] --> ConfigMgr[ConfigManager.psm1]
    
  subgraph ConfigFiles[Configuration Files]
    MainConfig[main-config.json<br/>Global Settings]
    LogConfig[logging-config.json<br/>Logging Configuration]
    BloatLists[bloatware-list.json<br/>App Definitions]
    EssentialLists[essential-apps.json<br/>Software Lists]
  end
    
  JSONFiles --> ConfigFiles
    
  %% Configuration Loading
  ConfigMgr --> Validation[Schema Validation<br/>& Defaults]
  Validation --> ConfigCache[Configuration Cache<br/>In Memory]
    
  %% Configuration Consumption
  ConfigCache --> Orchestrator[MaintenanceOrchestrator.ps1<br/>Task Execution]
  ConfigCache --> Type1Modules[Type 1 Modules<br/>Inventory & Reporting]
  ConfigCache --> Type2Modules[Type 2 Modules<br/>System Modification]
  ConfigCache --> CoreModules[Core Modules<br/>Infrastructure]
    
  %% Runtime Configuration Access
  Orchestrator --> GetMainConfig[Get-MainConfiguration]
  Type1Modules --> GetConfig[Module-Specific<br/>Get-*Configuration]
  Type2Modules --> GetConfig
  CoreModules --> GetConfig
```

## Module Guide (full)

- Core modules: ConfigManager (Initialize-ConfigSystem, Get/Save-*Configuration), MenuSystem (Show-*Menu, Start-CountdownSelection), DependencyManager (Install-AllDependencies, Get-DependencyStatus), TaskScheduler (New/Get/Remove/Start-MaintenanceTask)
- Type 1 modules (read-only):
  - SystemInventory: Get-SystemInventory, Export-SystemInventory
  - BloatwareDetection: Find-InstalledBloatware, Get-BloatwareStatistics, Test-BloatwareDetection
  - ReportGeneration: New-MaintenanceReport
  - SecurityAudit: Start-SecurityAudit, Get-WindowsDefenderStatus
- Type 2 modules (system-changing):
  - BloatwareRemoval: Remove-DetectedBloatware, Test-BloatwareRemoval
  - EssentialApps: Install-EssentialApplications, Get-AppsNotInstalled, Get-InstallationStatistics
  - WindowsUpdates: Install-WindowsUpdates, Get-WindowsUpdateStatus
  - TelemetryDisable: Disable-WindowsTelemetry, Test-PrivacySettings
  - SystemOptimization: Optimize-SystemPerformance, Get-SystemPerformanceMetrics

Contracts:
- Type 1: return data objects
- Type 2: [CmdletBinding(SupportsShouldProcess=$true)], respect -WhatIf/-Confirm and repo-wide -DryRun, return $true/$false

## PowerShell best practices (project-specific)

- Use approved verbs: Get, Set, New, Remove, Add, Install, Uninstall, Test, Start, Stop, Enable, Disable, Invoke, Export, Import
- Advanced functions with CmdletBinding and comment-based help
- Parameter validation; avoid aliases; prefer named parameters
- Destructive actions: ShouldProcess with WhatIf/Confirm
- Wrap external commands; check ExitCode; log errors
- Keep functions small and single-responsibility
- Run `Invoke-ScriptAnalyzer -Path . -Recurse` before committing

Example header template:

```powershell
function Get-Example {
  [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='Medium')]
  param(
    [Parameter(Mandatory=$true, Position=0)]
    [string]$Name,

    [Parameter()]
    [switch]$WhatIf
  )

  <#
  .SYNOPSIS
  Short description.

  .DESCRIPTION
  Longer description.

  .PARAMETER Name
  The target name.

  .EXAMPLE
  Get-Example -Name 'foo'
  #>

  if ($PSCmdlet.ShouldProcess($Name, 'Read')) {
    try {
      # Implementation here
      return $true
    }
    catch {
      Write-Error "Get-Example failed: $_"
      return $false
    }
  }
}
```

Splatting example:

```powershell
$args = @('--silent','--accept-package-agreements','--accept-source-agreements')
Start-Process -FilePath 'winget.exe' -ArgumentList $args -Wait -NoNewWindow
```
