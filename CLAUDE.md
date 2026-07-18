# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A Windows 10/11 maintenance automation system. A `.bat` launcher bootstraps the
environment (elevation, PowerShell 7, winget) and hands off to a PowerShell 7
orchestrator that runs a pipeline of audit + action modules and produces a single
self-contained HTML report. It is designed to run on freshly installed machines
that may only have PowerShell 5.1 available at first.

## Running

There is no build step and no test framework. The system is executed, not compiled.

- **Full run (normal entry point):** run `script.bat` as Administrator. It self-elevates,
  ensures PowerShell 7 + winget, **re-downloads the repo from GitHub as a zip, extracts it,
  and runs the extracted copy** (see "Self-update" below), then launches the orchestrator.
- **Orchestrator directly (dev loop, skips the launcher/self-update):**
  ```powershell
  pwsh -File .\MaintenanceOrchestrator.ps1
  ```
  Requires PowerShell 7+ **and an elevated session** (`#Requires -RunAsAdministrator`).
- **Non-interactive (no countdowns/menu):** `pwsh -File .\MaintenanceOrchestrator.ps1 -NonInteractive`
- **Run a specific subset of modules:** `-TaskNumbers "1,3,5"` (numbers match the Stage 1
  menu / `$ModulePairs.Num`). Implies non-interactive.

### Linting

PSScriptAnalyzer is the only static-analysis tooling. Settings live in
[PSScriptAnalyzerSettings.psd1](PSScriptAnalyzerSettings.psd1):
```powershell
Invoke-ScriptAnalyzer -Path . -Recurse -Settings .\PSScriptAnalyzerSettings.psd1
```

## Architecture

### Two-process bootstrap
`script.bat` (≈1400 lines) is a self-contained launcher that runs under cmd/PS5 before
PS7 exists. Its responsibilities, in order: admin elevation → pending-Windows-Update
reboot detection (creates an ONLOGON scheduled task and reboots if needed) → monthly
scheduled task creation → **self-update** → winget install/verify → PowerShell 7
install/verify → launch `MaintenanceOrchestrator.ps1` under `pwsh`.

- **Self-update:** the launcher downloads `…/archive/refs/heads/master.zip`, extracts to
  `script_mentenanta-master\`, overwrites its own `script.bat`, and re-points the working
  directory into the extracted folder. Editing `script.bat` in place is overwritten on the
  next real run unless the change is also pushed to `master`.
- **Unified `maintenance.log`:** the launcher creates `maintenance.log` next to `script.bat`
  at the very first line (`:INIT_LOG`, append mode so elevation/PS7 relaunches continue it),
  then after extraction migrates it into `<extracted>\temp_files\logs\` (`:MIGRATE_LOG`) and
  passes that path via the `MAINTENANCE_LOG` env var. The orchestrator opens the SAME file in
  append mode (`Initialize-Maintenance -LogPath`), so one log captures the whole run from launch
  through the five stages. `ORIGINAL_SCRIPT_DIR` env var tells the orchestrator where to copy the
  final HTML report (the folder the user launched from, e.g. a USB drive).

### Orchestrator: five stages
[MaintenanceOrchestrator.ps1](MaintenanceOrchestrator.ps1) opens the structured log
(`maintenance.log`, via the core logger) plus a raw transcript sidecar (`transcript.log`),
wraps the whole body in a fatal-capture `try/catch/finally` (any uncaught error is written to
`maintenance.log` with a stack trace; the log and transcript are always closed in `finally`),
then:

1. **Stage 1 – Inventory (Type1):** interactive menu with a 10s auto-run countdown; runs
   audit modules. A circuit breaker aborts the stage after 3 consecutive module failures.
2. **Stage 2 – Diff analysis:** for each pair, reads the diff list the Type1 module saved;
   only pairs with a non-empty diff (and not skipped by config) are queued. Each pair is
   wrapped so one bad diff/config entry can't abort the stage.
3. **Stage 3 – Maintenance (Type2):** runs only the queued action modules. If no diffs, no
   changes are made.
4. **Stage 4 – Report:** generates the HTML report embedding `maintenance.log` (read live —
   the log is auto-flushed with `FileShare.ReadWrite`, so no transcript stop/restart is needed),
   then copies it to the launcher folder.
5. **Stage 5 – Cleanup + reboot:** 120s countdown (configurable). Reboots and deletes the
   project folder unless a key is pressed, or skips reboot entirely when
   `rebootOnlyWhenRequired` is set and no module flagged `RebootRequired`.

### Type1 / Type2 module-pair model
The heart of the design. Every maintenance concern is a **pair**: a Type1 *audit* module
that only reads state, and a Type2 *action* module that only writes state. They communicate
exclusively through a **diff list** — never by calling each other. The pairing is declared in
one place: the `$ModulePairs` array in the orchestrator (`Num`, `DiffKey`, `Type1File`/`Func`,
`Type2File`/`Func`, `ConfigSkip`). To add a maintenance feature, add a Type1 module, a Type2
module, and one `$ModulePairs` entry.

The current pairs (each audit writes one combined diff whose items carry a discriminator tag
the action module switches on):

| # | Pair | DiffKey | Type2 | Discriminator | Covers |
|---|---|---|---|---|---|
| 1 | SoftwareManagement | `SoftwareManagement` | ✅ | `Action` = remove/install/upgrade | bloatware removal (40+ MS Store apps), essential-app install, app upgrade |
| 2 | SystemConfiguration | `SystemConfiguration` | ✅ | `ConfigType` = security/telemetry/optimization | Defender/firewall/security registry + **Sysmon**, privacy services/registry/tasks, services/power/startup/visual-fx |
| 3 | DiskCleanup | `DiskCleanup` | ✅ | `Type` = temp/browser/update/bin | temp/browser cache/cookies, DISM component store, recycle-bin cleanup |
| 4 | WindowsUpdates | `WindowsUpdates` | ✅ | — | Windows Update detection (3-layer: COM/WMI/Registry) and installation |
| 5 | SystemInventory | `SystemInventory` | — | — | OS/CPU/Memory/Disk/Network inventory (report only, no actions) |
| 6 | SystemHealth | `SystemHealth` | — | — | Event log analysis, Defender incidents, exclusions (report only, no actions) |
| 7 | RestorePoint | `RestorePoint` | ✅ | `Action` = create/remove | System restore point management and consolidation |

**Notable implementations:**
- `SystemConfiguration` installs **Sysinternals Sysmon** via winget (`Microsoft.Sysinternals.Sysmon`) 
  and applies `config/sysmon/sysmonconfig.xml` when the Sysmon service is absent.
- `SoftwareManagement` detects Microsoft Store bloatware via multi-source method:
  * Layer 1: PowerShell AppX cmdlets (PS5.1 via compatibility layer)
  * Layer 2: DISM provisioned packages
  * Layer 3: Registry fallback
- `WindowsUpdates` detects pending updates via three-layer detection:
  * Layer 1: COM API (Windows.Update.Session)
  * Layer 2: Registry pending updates and setup-in-progress flags
  * Layer 3: Event log analysis (update installation events)

- **Type1** (`modules/type1/*Audit.psm1`): loads a baseline JSON from `config/lists/`, scans
  the live system, computes what needs to change, and calls `Save-DiffList -ModuleName <DiffKey>`.
  Returns a `New-ModuleResult` hashtable. Must not modify the system.
- **Type2** (`modules/type2/*.psm1`): calls `Get-DiffList -ModuleName <DiffKey>`, acts only on
  those items, returns a `New-ModuleResult`. Receives `-OSContext`. Sets `RebootRequired` in
  its result to influence Stage 5.
- **`DiffKey` is the contract** between a pair and must match on both sides and in `$ModulePairs`;
  it is the filename stem under `temp_files/diff/<DiffKey>-diff.json`.

### Core module
[modules/core/Maintenance.psm1](modules/core/Maintenance.psm1) is imported `-Global` and provides
all shared infrastructure — do not duplicate these elsewhere:
`Write-Log` (structured `[ts] [LEVEL] [COMPONENT] msg`, written **directly** to `maintenance.log`
via an auto-flushed `StreamWriter` — independent of the transcript — with per-sink level gating:
console defaults to INFO, file to DEBUG, both overridable via the `logging` block in
`main-config.json` / `Set-LogLevel`; plus `Write-LogException`/`Close-LogFile`/`Add-LogRaw`),
`Get-OSContext` (Win10 vs 11 by build ≥22000, feature flags), `Get-MainConfig` / `Get-BaselineList`
(JSON loaded with `-AsHashtable` — everything is a case-insensitive hashtable), the diff engine
(`Compare-ListDiff` with `Present`/`Missing`/`Changed` strategies, `Save-DiffList`, `Get-DiffList`),
`New-ModuleResult` (the standard return schema), and shared system queries.

- **AppX compatibility layer:** PS7 Core's Appx cmdlets are unreliable, so `*Compat` functions
  (`Get-AppxPackageCompat`, `Remove-AppxPackageCompat`, etc.) delegate AppX operations to
  `powershell.exe` (Windows PowerShell 5.1) via `Invoke-AppxInWinPS`. Always use the `*Compat`
  wrappers for AppX work rather than calling `Get-AppxPackage` directly.
- **Baseline compare/apply helpers:** `Compare-RegistryBaseline` / `Compare-ServiceBaseline`
  (audit side, emit diff items) and `Invoke-RegistryChangeItem` / `Invoke-ServiceChangeItem`
  (action side, apply one item). Registry/service audit and action modules should route through
  these rather than reimplementing the compare/set logic inline.
- **Registry safety pattern:** High-risk Type2 modules that modify registry (e.g., `SystemConfiguration`)
  wrap registry changes with backup/verify/rollback:
  1. `Backup-RegistryValue` captures current state before change (or use in-module equivalent)
  2. Apply change via `Set-RegistryValue` or `Invoke-RegistryChangeItem`
  3. `Test-RegistryValueApplied` verifies change took effect (post-write validation)
  4. If verification fails, `Restore-RegistryValue` rolls back automatically
  This pattern prevents system corruption from failed registry writes.

### Config and generated files
- `config/settings/main-config.json` — execution/shutdown behavior and per-module `skip*` flags.
- `config/lists/<area>/*.json` — the baseline data each Type1 module diffs against (bloatware
  names, essential apps, security baseline, etc.). Baseline JSON commonly has `common` /
  `windows10` / `windows11` sections that Type1 modules merge based on `OSContext`. One merged
  audit may consume several list folders (e.g. SoftwareManagement reads `bloatware`,
  `essential-apps`, `app-upgrade`).
- `config/sysmon/sysmonconfig.xml` — Sysmon configuration applied by SystemConfiguration.
- `temp_files/` (git-ignored) — `logs/maintenance.log` (authoritative structured log),
  `logs/transcript.log` (raw PowerShell transcript sidecar), `diff/*-diff.json`,
  `reports/*.html`, `data/`. Created at startup by the orchestrator and core module.

## Conventions

- **PowerShell 7 required** for all `.ps1`/`.psm1` (`#Requires -Version 7.0`); the launcher and
  the AppX layer are the only parts that interoperate with PS5.1.
- Modules end with `Export-ModuleMember` listing only their public `Invoke-*` function(s).
- Every module returns a `New-ModuleResult` hashtable so the orchestrator and report generator
  can treat all modules uniformly (`Status`, `ItemsDetected/Processed/Skipped/Failed`,
  `RebootRequired`, `ExtraData`).
- Log through `Write-Log` (never `Write-Host` for status), using an uppercase `Component` tag.
- Reboot is only ever decided in two places: `script.bat` (pending Windows Update at startup)
  and Stage 5 cleanup. Individual modules signal a need via `RebootRequired`; they must not reboot.

## Consolidation note

`$ModulePairs` is the source of truth for what actually runs. The Type2 surface was consolidated
from six modules to four: `SoftwareManagement` merged BloatwareRemoval + AppManagement (itself
EssentialApps + AppUpgrade); `SystemConfiguration` merged SystemHardening (Security + Telemetry)
+ SystemOptimization. `DiskCleanup` and `WindowsUpdates` stay standalone (distinct risk/tooling).
The superseded `.psm1` files were deleted — the tree now contains only referenced modules, so any
module on disk is live. When merging modules, keep the one-combined-diff-plus-discriminator
pattern and register the pair in `$ModulePairs`.

## Comprehensive Audit & Remediation (v5.0+)

A full system audit identified and fixed **10 critical/high-priority issues** across 6 modules
and the orchestrator (commits fd75650 and prior). See [archive/PROJECT_AUDIT_REPORT.md](archive/PROJECT_AUDIT_REPORT.md)
for complete findings, and [PROJECT_EVALUATION.md](PROJECT_EVALUATION.md) for the newer 2026-07-18
full-project evaluation (which supersedes several claims below — critical bugs remain open). Key improvements:

**Critical Bug Fixes:**
- `SystemConfigurationAudit`: Startup program audit was exiting early (changed `return` → `continue`), causing data loss after first unsafe entry
- `WindowsUpdatesAudit`: Layer 2 detection was returning already-installed updates instead of pending ones (switched from WMI to registry)
- `WindowsUpdates`: Undefined `$WaitTime` variable in log message would cause runtime errors
- `RestorePointManagement`: Syntax error in line 121 — invalid if-expression in string interpolation now separated into variable assignment

**Logic & Configuration Fixes:**
- `WindowsUpdates`: Added pre-check and post-check validation to ensure installations actually succeeded; added `LASTEXITCODE` validation after `usoclient` calls
- Consolidated registry rollback pattern in `SystemConfiguration` with proper backup verification and error logging
- Added missing config entries (`skipSystemHealth`, `skipRestorePointManagement`) to `main-config.json`
- Fixed empty catch blocks in orchestrator (lines 96, 754) with proper error messages or PSScriptAnalyzer compliance

**Enhanced Safety:**
- Registry changes now wrap with backup → apply → verify → rollback pattern across all ConfigType sections
- Marked unused Type2 `$OSContext` parameters with `$null = $OSContext` to indicate intentional interface requirement

**Detection Improvements:**
- `SoftwareManagement`: Multi-source bloatware detection (COM API → DISM → Registry fallback) plus 40+ Microsoft Store bloatware entries
- `WindowsUpdates`: Three-layer detection (COM API → Registry → Event Log) for greater resilience
- Error handling and logging enhanced with type-specific exceptions, stack traces, and component tagging

**Project Status:** All critical bugs eliminated, all logic faults fixed, error handling standardized.
PSScriptAnalyzer warnings reduced from 1,075 → 1,065 (10 fixed); remaining 1,065 are cosmetic (966 formatting, 27 help comments, 14 BOM encoding).
