### Repo overview

This repository contains a Windows maintenance automation system built on a **modular architecture** with the following components:
- `script.bat` — Enhanced launcher/installer wrapper that ensures elevation, installs dependencies (winget, pwsh, choco, PSWindowsUpdate), manages scheduled tasks, downloads repos, and launches the orchestrator.
- `MaintenanceOrchestrator.ps1` — Central coordination script (PowerShell 7+ required) that loads modules, handles configuration, presents interactive menus, and orchestrates task execution.
- **Modular System**: Specialized PowerShell modules organized by function:
  - `modules/type1/` — Inventory & Reporting modules (read-only operations)
  - `modules/type2/` — System Modification modules (changes system state)
  - `modules/core/` — Core infrastructure (config, menus, dependencies, scheduling)
- **Configuration System**: JSON-based configuration files for all settings and data
- **Interactive Execution**: Menu-driven interface with dry-run capabilities and task selection

Targets: Windows 10/11. Many operations require Administrator privileges and network access. The launcher is location-agnostic and uses self-discovery to work from any folder.

### Core concepts an AI should know (why the structure exists)

- **Modular Architecture**: The system is built from specialized PowerShell modules, each with a single responsibility. Type 1 modules handle inventory/reporting (read-only), Type 2 modules perform system modifications, and Core modules provide infrastructure.
- **Launcher → Orchestrator Design**: `script.bat` prepares environment (elevation, dependency bootstrap, scheduled tasks, downloads) and delegates to `MaintenanceOrchestrator.ps1`. Avoid editing elevation logic in PowerShell — it's centralized in the batch launcher.
- **Configuration-Driven**: All settings, app lists, and behaviors are controlled through JSON configuration files in the `config/` directory. Never hardcode data that should be configurable.
- **Interactive + Non-Interactive Modes**: The system supports both menu-driven interactive use and unattended automation. All interactive prompts must have timeout fallbacks and non-interactive bypass options.
- **Task Registry Pattern**: Tasks are defined as module function calls in `MaintenanceOrchestrator.ps1` rather than a global array. Each task specifies its module path, function name, type, and category.
- **Dry-Run Architecture**: All system-modifying operations must support dry-run mode through `-DryRun` parameters or `-WhatIf` cmdlet binding.

### Files and key places to read first

- `script.bat` — Read top-to-bottom to understand environment setup: admin checks, PowerShell detection, dependency install order (winget → pwsh → NuGet → PSGallery → PSWindowsUpdate → chocolatey), scheduled task creation, repository download/extract, and how it invokes `MaintenanceOrchestrator.ps1`.
- `MaintenanceOrchestrator.ps1` — Start at the header and initialization sections. The task registry array defines all available tasks with their module paths and function names. Key functions: `Invoke-Task`, `Show-TaskMenu`, parameter parsing.
- `modules/core/ConfigManager.psm1` — Configuration loading and management. Functions: `Initialize-ConfigSystem`, `Get-MainConfiguration`, `Get-LoggingConfiguration`.
- `modules/core/MenuSystem.psm1` — Interactive menu system with countdown timers. Functions: `Show-MainMenu`, `Show-TaskSelectionMenu`.
- Module architecture: Each `.psm1` file exports specific functions. Type 1 modules return data objects, Type 2 modules return success/failure booleans.

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

- **Task registry entries**: Add tasks to the `$Tasks` array in `MaintenanceOrchestrator.ps1` as hashtables with Name, Description, ModulePath, Function, Type, and Category.
- **Module structure**: Each module exports specific functions using `Export-ModuleMember`. Type 1 modules return data objects, Type 2 modules return success/failure booleans.
- **Configuration access**: Use `Get-MainConfiguration` and configuration-specific functions from ConfigManager module. Load settings from JSON files in `config/` directory.
- **Progress reporting**: Use `Write-Host` with consistent formatting and color coding. Include operation status indicators (✓, ❌, ⚠️, 🔄).
- **Dry-run support**: All Type 2 modules must support `-DryRun` parameter and use `ShouldProcess` for destructive operations.
- **Error handling**: Use try/catch blocks with proper error messages. Return structured results with Success/Error properties.
- **Dependency management**: Use `DependencyManager` module for package manager operations instead of direct winget/choco calls.

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

- **Run the orchestrator locally (developer)**:
  - Open elevated PowerShell 7+ console: `.\MaintenanceOrchestrator.ps1`
  - With parameters: `.\MaintenanceOrchestrator.ps1 -DryRun -TaskNumbers "1,3,5"`

- **Create a new module**:
  - Follow existing module structure with `Export-ModuleMember` at end
  - Type 1 modules return data objects, Type 2 modules return success/failure booleans
  - Include proper error handling and progress reporting with colored output

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

### Project Evolution and Archive

This project underwent a **complete architectural transformation** from a monolithic script to a modular system:
- **Original monolithic files** are preserved in `archive/` directory for reference
- **Current architecture** is fully modular with specialized PowerShell modules
- **Migration complete**: All functionality extracted from the original 11,353-line `script.ps1`
- **Production ready**: New system is the current active implementation

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
