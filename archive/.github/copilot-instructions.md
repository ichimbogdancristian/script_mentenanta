### Repo overview

This repository contains a **streamlined** Windows maintenance automation system v2.1 built on a **modular architecture**. After comprehensive cleanup (October 2025), only actively used files remain in the main directory:

**Active Components:**
- `script.bat` — Enhanced launcher with dependency management, scheduled tasks, and orchestrator invocation
- `MaintenanceOrchestrator.ps1` — Central coordination script (PowerShell 7+ required) with enhanced module execution protocol
- **Modular System**: 14 specialized PowerShell modules organized by function:
  - `modules/core/` (5 modules) — Core infrastructure: ConfigManager, MenuSystem, DependencyManager, TaskScheduler, ModuleExecutionProtocol
  - `modules/type1/` (4 modules) — Inventory & Reporting: SystemInventory, BloatwareDetection, SecurityAudit, ReportGeneration
  - `modules/type2/` (5 modules) — System Modification: BloatwareRemoval, EssentialApps, WindowsUpdates, TelemetryDisable, SystemOptimization
- **Configuration System**: Complete JSON-based configuration in `config/` directory
  - `config/main-config.json` + `config/logging-config.json` (main configuration files)
  - `config/bloatware-lists/` (4 JSON files: gaming, oem, security, windows)
  - `config/essential-apps/` (4 JSON files: development, media, productivity, web-browsers)
- **Archive System**: `archive/` directory contains reference implementations and unused files

**Project Structure (Post-Cleanup):**
```
script_mentenanta/
├── script.bat                     # Main launcher (ACTIVE)
├── MaintenanceOrchestrator.ps1    # Core orchestrator (ACTIVE)
├── README.md                      # Main documentation (ACTIVE)
├── modules/                       # All 14 modules (ACTIVE)
├── config/                        # All JSON configurations (ACTIVE)
└── archive/                       # Historical files & unused components
    ├── script-original.ps1        # Original monolithic script (REFERENCE)
    ├── script-original.bat        # Original batch launcher (REFERENCE)
    ├── MaintenanceOrchestrator-v2.0.ps1  # Previous version (REFERENCE)
    ├── MaintenanceCompatibilityWrapper.ps1  # Unused (MOVED)
    ├── .psscriptanalyzer.psd1     # Development tool (MOVED)
    ├── .github/                   # CI/CD configs (MOVED)
    ├── docs/                      # Documentation files (MOVED)
    └── script-new-folder-copy.bat # Duplicate file (MOVED)
```

**Current State**: Production-ready v2.1 with 100% active file usage. All unused components archived for reference.

Targets: Windows 10/11. Requires Administrator privileges for Type2 modules. Location-agnostic with self-discovery.

### Core concepts an AI should know (why the structure exists)

- **Modular Architecture**: The system is built from specialized PowerShell modules, each with a single responsibility. Type 1 modules handle inventory/reporting (read-only), Type 2 modules perform system modifications, and Core modules provide infrastructure.
- **Launcher → Orchestrator Design**: `script.bat` prepares environment (elevation, dependency bootstrap, scheduled tasks, downloads) and delegates to `MaintenanceOrchestrator.ps1`. Avoid editing elevation logic in PowerShell — it's centralized in the batch launcher.
- **Configuration-Driven**: All settings, app lists, and behaviors are controlled through JSON configuration files in the `config/` directory. Never hardcode data that should be configurable.
- **Interactive + Non-Interactive Modes**: The system supports both menu-driven interactive use and unattended automation. All interactive prompts must have timeout fallbacks and non-interactive bypass options.
- **Task Registry Pattern**: Tasks are defined as module function calls in `MaintenanceOrchestrator.ps1` rather than a global array. Each task specifies its module path, function name, type, and category.
- **Enhanced Module Execution Protocol**: Advanced dependency resolution with proper execution ordering, configuration validation, and comprehensive result tracking through `ModuleExecutionProtocol.psm1`.
- **Dry-Run Architecture**: All system-modifying operations must support dry-run mode through `-DryRun` parameters or `-WhatIf` cmdlet binding.

### Files and key places to read first

**Core Entry Points:**
- `script.bat` — Main launcher (750+ lines): Admin elevation, dependency management (winget → PowerShell 7 → NuGet → PSGallery → PSWindowsUpdate → Chocolatey), pending restart detection, scheduled task creation, orchestrator invocation
- `MaintenanceOrchestrator.ps1` — Central orchestrator (900+ lines): Enhanced module registration with `ModuleManifests` array (10 tasks), dependency validation, interactive menus, execution engine coordination

**Core Infrastructure Modules (modules/core/):**
- `ConfigManager.psm1` — Configuration system: `Initialize-ConfigSystem`, `Get-MainConfiguration`, `Get-BloatwareConfiguration`, `Get-EssentialAppsConfiguration`, JSON loading/validation
- `MenuSystem.psm1` — Interactive menus: `Show-MainMenu`, `Show-TaskSelectionMenu`, `Show-DryRunExecutionSubmenu`, countdown timers (20s default)
- `ModuleExecutionProtocol.psm1` — Advanced execution engine: `New-ModuleExecutor`, dependency resolution, timeout handling (5min default), comprehensive result tracking
- `DependencyManager.psm1` — Package management: `Install-AllDependencies`, `Get-DependencyStatus`, winget/chocolatey detection
- `TaskScheduler.psm1` — Windows scheduled tasks: `New-MaintenanceTask`, `Get-MaintenanceTasks`, `Remove-MaintenanceTask`

**Task Execution Modules:**
- Type1 (modules/type1/): SystemInventory, BloatwareDetection, SecurityAudit, ReportGeneration — return data objects
- Type2 (modules/type2/): BloatwareRemoval, EssentialApps, WindowsUpdates, TelemetryDisable, SystemOptimization — return success/failure booleans

**Configuration System (config/):**
- JSON files: main-config.json, logging-config.json, bloatware-lists/*.json, essential-apps/*.json
- All settings configurable, no hardcoded values in modules

### Common workflows & exact commands

- **Run locally (developer)**: Open an elevated PowerShell 7+ console and run `.\MaintenanceOrchestrator.ps1` from the repository folder. The batch file is only necessary for full bootstrap behavior.
- **Launch via launcher (production/operator)**: Run `script.bat` (double-click or elevated command prompt). The batch file ensures elevation and dependencies before launching the orchestrator.
- **Interactive mode**: Default behavior shows countdown menus for execution mode and task selection.
- **Non-interactive automation**: Use `script.bat -NonInteractive` or `MaintenanceOrchestrator.ps1 -NonInteractive` for unattended execution.
- **Dry-run testing**: Use `-DryRun` parameter to simulate changes without system modification.
- **Specific task execution**: Use `-TaskNumbers "1,3,5"` to run only specified tasks from the registry.
- **Package manager calls**: Modules should use their own package manager abstractions. WindowsUpdates module handles update suppression automatically.
- **Configuration changes**: Edit JSON files in `config/` directory rather than hardcoding values in modules.

### Patterns and conventions to follow

- **Module Registration**: Add tasks to the `$ModuleManifests` array in `MaintenanceOrchestrator.ps1` with complete metadata:
  ```powershell
  @{
      Name = 'TaskName'
      Version = '1.0.0' 
      Description = 'Task description'
      Type = 'Type1' # or 'Type2'
      Category = 'Category'
      ModulePath = Join-Path $ModulesPath 'type1\ModuleName.psm1'
      EntryFunction = 'Get-TaskData' # or 'Invoke-TaskAction'
      Dependencies = @('RequiredTask1', 'RequiredTask2')
      RequiresElevation = $false # or $true for Type2
      TimeoutSeconds = 300
      ConfigurationDependencies = @('config-folder-name')
  }
  ```
- **Module Structure**: Each `.psm1` exports functions via `Export-ModuleMember`. Type1 modules return data objects, Type2 return $true/$false
- **Configuration Access**: Use ConfigManager functions: `Get-MainConfiguration`, `Get-BloatwareConfiguration`, `Get-EssentialAppsConfiguration`
- **Progress Reporting**: Use `Write-Host` with color coding and status indicators (✓, ❌, ⚠️, 🔄, 📊, 🔍, 🛠️)
- **Dry-Run Support**: All Type2 modules MUST support `-DryRun` parameter with `[CmdletBinding(SupportsShouldProcess)]`
- **Error Handling**: Use try/catch with `Write-Log` for consistent logging. Return structured results for orchestrator tracking
- **Dependency Management**: Use `DependencyManager` module functions instead of direct package manager calls
- **File Organization**: Keep all active files in main directory, move unused items to `archive/` for reference

### Integration & external dependencies

- **External tools**: winget, pwsh (PowerShell 7), chocolatey, PSWindowsUpdate, NuGet provider. The `DependencyManager` module handles installation; modules should check dependencies using `Get-DependencyStatus`.
- **Remote repo fetching**: `script.bat` downloads repo ZIP from GitHub. Self-update logic is in the batch file; coordinate changes with batch script updates.
- **Windows APIs**: Registry keys used extensively for system configuration. Use appropriate error handling and validation when accessing registry.
- **Module dependencies**: Core modules (ConfigManager, MenuSystem) are loaded first. Type 1/Type 2 modules are loaded on-demand by the orchestrator.
- **Configuration system**: All configuration through JSON files. Use `ConfigManager` module functions for loading and validation.

### Small actionable examples (copy/paste friendly guidance for agents)

- **Add a new maintenance task**:
  1. Create a PowerShell module (.psm1) in appropriate `modules/type1/` or `modules/type2/` directory
  2. Add task entry to `$Tasks` array in `MaintenanceOrchestrator.ps1` with ModulePath, Function, Type, Category
  3. Use configuration from JSON files in `config/` directory instead of hardcoded values
  4. Support `-DryRun` parameter for Type 2 modules using `[CmdletBinding(SupportsShouldProcess)]`
  5. Include Write-Log calls for comprehensive logging to maintenance.log

- **Run the orchestrator locally (developer)**:
  - Open elevated PowerShell 7+ console: `.\MaintenanceOrchestrator.ps1`
  - With parameters: `.\MaintenanceOrchestrator.ps1 -DryRun -TaskNumbers "1,3,5"`

- **Create a new module**:
  - Follow existing module structure with `Export-ModuleMember` at end
  - Type 1 modules return data objects, Type 2 modules return success/failure booleans
  - Include proper error handling and progress reporting with colored output
  - Use Write-Log function from ConfigManager for consistent logging

- **Create test scripts**:
  - Place all test scripts in `Test/` directory for proper organization
  - Use descriptive names like `Test-ModuleName.ps1` or `Test-SpecificFeature.ps1`
  - Include dry-run testing and error validation in test scripts

### What not to change without careful review

- **Elevation and scheduled-task logic in `script.bat`** — This is sensitive and relies on multiple Windows behaviors and admin rights.
- **Module loading order in `MaintenanceOrchestrator.ps1`** — Core modules must load before Type 1/Type 2 modules due to dependencies.
- **Configuration schema in JSON files** — Changes affect all modules; coordinate updates across the system.
- **Task return value contracts** — Type 1 modules return data objects, Type 2 modules return success/failure booleans for orchestrator tracking.
- **DryRun parameter handling** — All Type 2 modules must respect the `-DryRun` parameter for safe testing.

### Quick map to notable symbols & files

- `script.bat` — Launcher and bootstrapper: admin checks, dependency installation order, scheduled tasks, repo download/extract, invocation of orchestrator.
- `MaintenanceOrchestrator.ps1` — Central orchestrator: `$Tasks` registry, module loading, `Invoke-Task`, menu coordination, parameter parsing.
- `modules/core/ConfigManager.psm1` — Configuration system: `Initialize-ConfigSystem`, `Get-MainConfiguration`, JSON loading/validation.
- `modules/core/MenuSystem.psm1` — Interactive menus: `Show-MainMenu`, `Show-TaskSelectionMenu`, countdown timers.
- `modules/core/DependencyManager.psm1` — Dependency management: `Install-AllDependencies`, `Get-DependencyStatus`, package manager detection.
- `modules/core/TaskScheduler.psm1` — Task scheduling: `New-MaintenanceTask`, `Get-MaintenanceTasks`, Windows scheduled task automation.
- `modules/core/ModuleExecutionProtocol.psm1` — Advanced execution engine: dependency resolution, timeout handling, comprehensive result tracking.

### Project Evolution and Current Status

This project evolved from monolithic script to streamlined modular system:

**Evolution Timeline:**
- **Phase 1**: Original 11,353-line monolithic `script.ps1` (archived as `script-original.ps1`)
- **Phase 2**: Modular architecture with 14 specialized PowerShell modules  
- **Phase 3**: Project cleanup (October 2025) - streamlined to active files only

**Current Status (v2.1 - Production Ready):**
- **Active Components**: 22 files total (2 main + 14 modules + 6 configs)
- **100% File Usage**: All files in main directory are actively referenced and used
- **Archive System**: 9 items preserved in `archive/` for reference (includes original files, documentation, CI/CD configs, unused components)
- **Comprehensive Testing**: All 14 modules validated and working (100% success rate)

**Latest Improvements (v2.1):**
- **Streamlined Structure**: Moved unused files to archive (MaintenanceCompatibilityWrapper.ps1, docs/, .github/, .psscriptanalyzer.psd1, Test/ folder)
- **Enhanced Module Registration**: ModuleManifests array with dependency management and configuration validation
- **Improved Dependency Chain**: Winget → PowerShell 7 → NuGet → PSGallery → PSWindowsUpdate → Chocolatey
- **Advanced Execution Protocol**: Timeout handling, dependency resolution, comprehensive result tracking
- **Configuration Validation**: All JSON configs verified and actively loaded
- **Pending Restart Detection**: Smart restart handling with startup task management
- **Latest Version Support**: Automatic winget latest release usage (v1.11.510)

**Reference Materials in Archive:**
- Original working implementations for troubleshooting
- Development tools and documentation
- CI/CD configurations and workflows
- Previous version components

### If something is missing or unclear

- Ask for: (1) which environment you'll run in (local dev vs managed enterprise endpoint), (2) whether modifying scheduled task behavior or restart policy is permitted, and (3) whether new features should be toggled by default.

Please review this draft and tell me any areas you want expanded (examples, command snippets, or additional file references). I'll iterate quickly.

## PowerShell best practices (project-specific)

The following are concrete, discoverable conventions and snippets an AI agent should follow when editing or adding PowerShell code in this repository.

- Use approved verbs only. Prefer the PowerShell approved verb list (Get, Set, New, Remove, Add, Install, Uninstall, Test, Start, Stop, Enable, Disable, Invoke, Export, Import). Avoid inventing verbs like Fetch, Do, Handle, Process. Example mapping:
  - Bad: function Invoke-FetchUserData { ... }
  - Good: function Get-UserData { ... }

- Always author advanced functions with CmdletBinding and comment-based help. This repository treats task functions as reusable building blocks.

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
              Write-Log "Get-Example failed: $_" 'ERROR'
              return $false
          }
      }
  }
  ```

- Parameter best practices
  - Use explicit parameter attributes: [Parameter(Mandatory=$true, Position=0, ValueFromPipeline=$true)].
  - Validate input with attributes: [ValidateNotNullOrEmpty()], [ValidateSet()], [ValidateRange()].
  - Avoid relying on positional parameters in public functions; prefer named parameters for clarity.

- Error handling and logging
  - Catch terminating errors with try/catch and write problems using `Write-Log` / `Write-ActionLog` instead of `Write-Host` or suppressing exceptions.
  - Normalize return values: tasks should return $true on success and $false on failure so the orchestrator can record results.

- Use ShouldProcess for destructive operations
  - For actions which change system state (remove/uninstall/modify), use `SupportsShouldProcess=$true` and call `$PSCmdlet.ShouldProcess()` to respect WhatIf/Confirm semantics.

- Avoid aliases and magic variables in scripts
  - Do not use short aliases (e.g., `gci`, `ls`, `rm`, `sc`) inside committed scripts — use full cmdlet names (Get-ChildItem, Remove-Item). This improves readability and PSScriptAnalyzer compliance.

- Prefer splatting and explicit argument arrays for external commands
  - Example:

  ```powershell
  $args = @('--silent','--accept-package-agreements','--accept-source-agreements')
  Invoke-LoggedCommand -FilePath 'winget.exe' -ArgumentList $args -Context 'Install App'
  ```

- Use PSScriptAnalyzer (static analysis)
  - Add it to dev workflow and run `Invoke-ScriptAnalyzer -Path . -Recurse` before committing. Recommend installing with `Install-Module -Name PSScriptAnalyzer`.
  - Common rules to enable: use-approved-verbs, avoid-using-aliases, use-shouldprocess-for-destructive-actions, provide-comment-based-help.

- Command invocation safety
  - Wrap external invocations with `Invoke-LoggedCommand` (exists in `script.ps1`) to capture stdout/stderr and normalize errors.
  - Never assume success; check ExitCode or returned result and log failures.

- Formatting and style
  - Keep functions small and single-responsibility. Return structured objects or booleans (don't print raw output and rely on parsing later).
  - Use consistent indentation (2 spaces or keep existing file style). Prefer explicit `return` for clarity.

### Quick checklist for PRs that change PowerShell code

1. Does every function use an approved verb and follow the Name-Verb noun pattern?
2. Is there comment-based help for non-trivial functions?
3. Are parameters validated and not relying on positional-only usage?
4. Are destructive actions using ShouldProcess/WhatIf?
5. Are external commands wrapped with `Invoke-LoggedCommand` or similar and their results checked?
6. Did you run `Invoke-ScriptAnalyzer` and address high-severity findings?

If you'd like, I can add a sample `.psscriptanalyzer.psd1` configuration and a small CI job example (PowerShell script) that runs `Invoke-ScriptAnalyzer` on PRs — tell me if you want that added.
