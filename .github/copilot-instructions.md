### Repo overview

This repository contains a Windows maintenance automation launcher written as a two-file entrypoint:
- `script.bat` — launcher/installer wrapper that ensures elevation, installs dependencies (winget, pwsh, choco, PSWindowsUpdate), manages scheduled tasks/startup tasks, downloads the repo ZIP and launches `script.ps1`.
- `script.ps1` — the PowerShell orchestrator (PowerShell 7+ required). Implements the maintenance task framework (task list, logging, app/package management, Windows Update handling, bloatware detection/removal).

Targets: Windows 10/11. Many operations require Administrator privileges and network access. The batch launcher is designed to be location-agnostic and to run from any folder.

### Core concepts an AI should know (why the structure exists)

- Two-tier launcher → orchestrator design: `script.bat` prepares environment (elevation, dependency bootstrap, scheduled task management, downloads) and delegates the work to `script.ps1`. Avoid editing elevation logic in the PS1 file — it is intentionally centralized in the batch launcher.
- Idempotent, non-interactive automation: the scripts aim to run unattended (suppressed prompts, environment variables to avoid reboots/prompts). When adding new commands, preserve non-interactive flags and the avoidance of interactive prompts.
- Centralized task registry: `script.ps1` exposes a single global array `$global:ScriptTasks` — add, disable or reorder features by editing this array or by adding new task entries that follow the Name/Function/Description pattern.
- Feature flags via `$global:Config`: use the existing Skip* flags (e.g. SkipBloatwareRemoval, SkipEssentialApps) and collections (CustomEssentialApps, CustomBloatwareList) for configuration rather than editing task bodies.

### Files and key places to read first

- `script.bat` — read top-to-bottom to understand environment setup: admin checks, PowerShell detection, dependency install order (winget → pwsh → NuGet → PSGallery → PSWindowsUpdate → chocolatey), scheduled task creation, repository download/extract, and how it invokes `script.ps1`.
- `script.ps1` — start at the header and global sections (metadata, $global:Config, $global:ScriptTasks, logging functions). The orchestrator functions `Use-AllScriptTasks`, `Invoke-Task`, `Invoke-LoggedCommand`, `Invoke-PackageManagerCommand` are core abstractions used throughout.

### Common workflows & exact commands

- Run locally (developer): open an elevated PowerShell 7+ console and run `.\\script.ps1` from the repository folder; the batch file is only necessary when you want the full bootstrap behavior. The PS1 expects `$env:WORKING_DIRECTORY` or will use its own folder.
- Launch via launcher (production/operator): run `script.bat` (double-click or elevated command prompt). The batch file will ensure elevation and dependencies before launching the PS1.
- Non-interactive package installs: use `Invoke-PackageManagerCommand` for calls to winget/choco. Preserve `--silent`, `--accept-package-agreements`, `--accept-source-agreements`, and `-y` flags used by the project.
- Windows Updates: functions `Install-WindowsUpdatesCompatible` and `Invoke-WindowsUpdateWithSuppressionHelpers` set environment variables to suppress prompts and reboots. When modifying update flows, preserve suppression env vars (PSWINDOWSUPDATE_REBOOT, SUPPRESSPROMPTS, etc.) and never re-enable interactive reboots by default.

### Patterns and conventions to follow

- Task entries: add tasks to `$global:ScriptTasks` as a hashtable with Name, Function (scriptblock), and Description. Example found in `script.ps1`:
  @{ Name = 'RemoveBloatware'; Function = { Remove-Bloatware }; Description = 'Remove unwanted apps' }
- Logging: always use Write-Log, Write-ActionLog, or Write-CommandLog for messages instead of Write-Host alone. These functions centralize log file writing, levels, console coloring and backups.
- Progress UX: use Write-TaskProgress / Write-ActionProgress to display user-friendly progress; avoid printing raw progress loops that spam the console/log.
- Feature flags: prefer `$global:Config.Skip*` toggles and `$global:Config.Custom*` lists rather than changing core task logic.
- Package manager wrappers: call Invoke-PackageManagerCommand instead of spawning winget/choco directly to get normalized output and timeout handling.

### Integration & external dependencies

- External tools: winget, pwsh (PowerShell 7), chocolatey, PSWindowsUpdate, NuGet provider. The batch script tries to install these if missing; do not assume they exist in all environments.
- Remote repo fetching: `script.bat` downloads a repo ZIP from GitHub (see REPO_URL inside `script.bat`). If you change download/update behavior, update the self-update extraction and copy logic in the batch file.
- Windows APIs: registry keys are used extensively (bloatware detection, restart checks). Use provided Test-RegistryAccess / Set-RegistryValueSafely helpers for safe registry writes.

### Small actionable examples (copy/paste friendly guidance for agents)

- Add a new maintenance task:
  - Create a new function in `script.ps1` that performs the work and returns $true/$false.
  - Add an entry to `$global:ScriptTasks` with Name, Function = { <your-call> }, Description.
  - Respect `$global:Config` switches: check for a Skip* flag if your task should be optionally disabled.

- Run the orchestrator locally (developer):
  - Open an elevated PowerShell 7 console in the repository folder and run `pwsh -ExecutionPolicy Bypass -File .\script.ps1` (or pass -LogFilePath if needed).

- Inspect package installation code paths: search for `Invoke-PackageManagerCommand` in `script.ps1` to see how installs/uninstalls are normalized.

### What not to change without careful review

- Elevation and scheduled-task logic in `script.bat` — this is sensitive and relies on multiple Windows behaviors and admin rights.
- Default silent/reboot suppression around Windows Update flows — these were intentionally added to avoid unattended reboots.
- The contract of task functions: they should return $true/$false (or otherwise behave like the existing tasks) so the orchestrator can record success/failure.

### Quick map to notable symbols & files

- `script.bat` — launcher and bootstrapper: admin checks, dependency installation order, scheduled tasks, repo download/extract, invocation of PS1.
- `script.ps1` — orchestrator: $global:ScriptTasks, $global:Config, Write-Log, Use-AllScriptTasks, Invoke-Task, Invoke-PackageManagerCommand, Install-WindowsUpdatesCompatible.

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
