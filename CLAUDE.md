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
`script.bat` (~1400 lines) is a self-contained launcher that runs under cmd/PS5 before
PS7 exists. Its responsibilities, in order: admin elevation → pending-Windows-Update
reboot detection (creates an ONLOGON scheduled task and reboots if needed) → monthly
scheduled task creation → **self-update** → winget install/verify → PowerShell 7
install/verify → launch `MaintenanceOrchestrator.ps1` under `pwsh`.

- **Self-update:** the launcher downloads `…/archive/refs/heads/master.zip`, extracts to
  `script_mentenanta-master\`, overwrites its own `script.bat`, and re-points the working
  directory into the extracted folder. Editing `script.bat` in place is overwritten on the
  next real run unless the change is also pushed to `master`. Because `cmd.exe` streams the
  running `.bat` from disk, the launcher cannot overwrite itself mid-run; it hands the fresh
  copy to the orchestrator via `PENDING_SCRIPT_UPDATE`, which applies it after the launcher exits.
- **Single unified `maintenance.log`:** the launcher creates `maintenance.log` next to
  `script.bat` at the very top of `:MAIN_SCRIPT`, before the first log line (append mode so
  elevation/PS7 relaunches continue it), so the whole bootstrap phase is captured. After
  extraction it `MOVE`s the file into `<extracted>\temp_files\logs\maintenance.log`, repoints
  `LOG_FILE` so writing continues in the same file, and exports the path via the
  `MAINTENANCE_LOG` env var (that migration block uses delayed expansion — the vars are set
  inside the extraction `IF` block). The orchestrator reads `$env:MAINTENANCE_LOG` and opens the
  SAME file in append mode (`Initialize-Maintenance -LogPath`), so ONE file captures the whole
  run from launch through the five stages. There is no separate transcript sidecar. Before
  handing off it clears `LOG_FILE` so the launcher stops writing once the orchestrator owns the
  file. `ORIGINAL_SCRIPT_DIR` tells the orchestrator where to copy the final HTML report (the
  folder the user launched from, e.g. a USB drive).

### Orchestrator: five stages
[MaintenanceOrchestrator.ps1](MaintenanceOrchestrator.ps1) appends to the single unified
`maintenance.log` (via the core logger — the launcher already created and migrated the file and
passed its path in `$env:MAINTENANCE_LOG`). It is the sole log: a direct-write, auto-flushed
stream, **not** a PowerShell `Start-Transcript` (a transcript handle would block the report from
reading the file mid-run). The orchestrator wraps the whole body in a fatal-capture
`try/catch/finally` (any uncaught error is written to `maintenance.log` with a stack trace; the
log is always closed via `Close-LogFile` in `finally`), then:

1. **Stage 1 – Inventory (Type1):** interactive menu with a 10s auto-run countdown; runs
   audit modules. A circuit breaker aborts the stage after 3 consecutive module failures.
   Buffered keystrokes are drained (`Clear-PendingConsoleInput`) before each timed prompt so a
   stray key from an earlier unattended stage can't trigger a phantom selection/abort.
2. **Stage 2 – Diff analysis:** for each pair, reads the diff list the Type1 module saved;
   only pairs with a non-empty diff (and not skipped by config) are queued. Each pair is
   wrapped so one bad diff/config entry can't abort the stage.
3. **Stage 3 – Maintenance (Type2):** runs only the queued action modules, in a deliberate
   order (`$Stage3Order`: SystemConfiguration → SoftwareManagement → WindowsUpdates →
   RestorePoint → **DiskCleanup last**, so it sweeps up residue the earlier actions created).
   If no diffs, no changes are made.
4. **Stage 4 – Report:** generates the HTML report embedding `maintenance.log` (read live — the
   log is a direct-write, auto-flushed stream opened with `FileShare.ReadWrite`, so the report
   reads it while it is still being written), then copies it to the launcher folder.
   `Publish-MaintenanceReport` is called again right before cleanup so the surviving copy embeds
   the complete log (incl. Stage 5).
5. **Stage 5 – Cleanup + reboot:** removes the session's Defender exclusions unconditionally, then
   a 120s countdown (configurable). Reboots and deletes the project folder unless a key is pressed,
   or skips reboot entirely when `rebootOnlyWhenRequired` is set and no module flagged `RebootRequired`.

### `$ModulePairs`: the source of truth
`$ModulePairs` in the orchestrator declares what actually runs — array **order** is the Stage 1
audit/menu order; `Num` is the stable selection id used by `-TaskNumbers` and the menu (they match
on `Num`, not array index). Actionable pairs (1–4, 7) are ordered before the report-only audits
(5, 6) so gating decisions are made first and, if a run is cut short, it's report-only work that's
sacrificed. Stage 3's execution order is separate (`$Stage3Order`, above).

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
| 4 | WindowsUpdates | `WindowsUpdates` | ✅ | — | Windows Update detection (3-layer: COM/Registry/EventLog) and installation |
| 5 | SystemInventory | `SystemInventory` | — | — | OS/CPU/Memory/Disk/Network inventory (report only, no actions) |
| 6 | SystemHealth | `SystemHealth` | — | — | Event log analysis, Defender incidents, exclusions (report only, no actions) |
| 7 | RestorePoint | `RestorePoint` | ✅ | `Action` = create/remove | System restore point management and consolidation |

**Notable implementations:**
- `SystemConfiguration` installs **Sysinternals Sysmon** via winget (`Microsoft.Sysinternals.Sysmon`)
  and applies `config/sysmon/sysmonconfig.xml` (with `-accepteula`) when the Sysmon service is
  absent. It resolves the **real** `Sysmon64.exe` (from `%windir%` or the winget `Packages`
  folder), deliberately **avoiding the winget `Links\sysmon.exe` shim** — launching that
  App-Execution-Alias with redirected stdio fail-fast crashes with `0xC0000409` (-1073740791).
- `SoftwareManagement` detects bloatware from **four sources** — AppX (PS5.1 compat layer) →
  provisioned packages → registry → winget `list` (parsed into Name/Id columns, never matched
  against the raw formatted line). Every candidate is gated by `bloatware/protected-packages.json`
  + `bloatware/dependency-matrix.json` via `Test-CanRemovePackage`: a package matching a
  protected/depended-on entry is never queued for removal. Type2 removes each item with a layered
  strategy (AppX → Provisioned → registry **silent-uninstall only** → winget), then installs
  essentials and applies upgrades. Open follow-ups (WinGet.Client module, essential-app matching,
  unused cascade config) are catalogued in [SoftwareManagement-Evaluation.md](SoftwareManagement-Evaluation.md).
- `WindowsUpdates` detects pending updates via three layers: Layer 1 COM API
  (`Windows.Update.Session`) → Layer 2 registry pending/setup-in-progress flags → Layer 3
  event-log analysis.

- **Type1** (`modules/type1/*Audit.psm1`): loads a baseline JSON from `config/lists/`, scans
  the live system, computes what needs to change, and calls `Save-DiffList -ModuleName <DiffKey>`.
  Returns a `New-ModuleResult` hashtable. Must not modify the system.
- **Type2** (`modules/type2/*.psm1`): calls `Get-DiffList -ModuleName <DiffKey>`, acts only on
  those items, returns a `New-ModuleResult`. Receives `-OSContext`. Sets `RebootRequired` in
  its result to influence Stage 5.
- **`DiffKey` is the contract** between a pair and must match on both sides and in `$ModulePairs`;
  it is the filename stem under `temp_files/diff/<DiffKey>-diff.json`.

### Core modules
There are two modules under `modules/core/`. [Maintenance.psm1](modules/core/Maintenance.psm1)
is imported `-Global` and provides all shared infrastructure — do not duplicate these elsewhere:
`Write-Log` (structured `[ts] [LEVEL] [COMPONENT] msg`, written **directly** to the single
`maintenance.log` via an auto-flushed `StreamWriter` opened with `FileShare.ReadWrite` so the
report can read it live, with per-sink level gating: console defaults to INFO, file to DEBUG,
both overridable via the `logging` block in `main-config.json` / `Set-LogLevel`; plus
`Write-LogException`/`Close-LogFile`/`Add-LogRaw`),
`Get-OSContext` (Win10 vs 11 by build ≥22000, feature flags), `Get-MainConfig` / `Get-BaselineList`
(JSON loaded with `-AsHashtable` — everything is a case-insensitive hashtable, so **iterate config
entries with `.Values` / `.GetEnumerator()` / `.Keys`, never `.PSObject.Properties`**: on a hashtable
the latter enumerates CLR members (`Count`/`Keys`/`Values`/…), not the JSON keys, which silently
produces empty or garbage results — this bug had made the bloatware protection list a no-op), the diff engine
(`Compare-ListDiff` with `Present`/`Missing`/`Changed` strategies, `Save-DiffList`, `Get-DiffList`),
`New-ModuleResult` (the standard return schema), and shared system queries.

[ReportGenerator.psm1](modules/core/ReportGenerator.psm1) is imported only in Stage 4 and owns
all HTML report rendering. Public entry point is `New-MaintenanceReport`; internal `Build-*`
helpers render per-module cards, the system overview, the SystemInventory/RestorePoint/SystemHealth
sections, and the embedded log console (`ConvertFrom-MaintenanceLog` / `Build-LogConsole` parse the
structured `maintenance.log` into the collapsible in-report console). Report markup/styling changes
belong here, not in the orchestrator.

- **AppX compatibility layer:** PS7 Core's Appx cmdlets are unreliable, so `*Compat` functions
  (`Get-AppxPackageCompat`, `Remove-AppxPackageCompat`, etc.) delegate AppX operations to
  `powershell.exe` (Windows PowerShell 5.1) via `Invoke-AppxInWinPS`. Always use the `*Compat`
  wrappers for AppX work rather than calling `Get-AppxPackage` directly.
- **Baseline compare/apply helpers:** `Compare-RegistryBaseline` / `Compare-ServiceBaseline`
  (audit side, emit diff items) and `Invoke-RegistryChangeItem` / `Invoke-ServiceChangeItem`
  (action side, apply one item). Registry/service audit and action modules should route through
  these rather than reimplementing the compare/set logic inline.
- **Registry safety pattern:** high-risk Type2 modules that modify the registry (e.g.
  `SystemConfiguration`) wrap changes with backup → apply → verify → rollback: capture current
  state, apply via `Set-RegistryValue` / `Invoke-RegistryChangeItem`, verify with
  `Test-RegistryValueApplied`, and roll back automatically if verification fails.

### Config and generated files
- `config/settings/main-config.json` — execution/shutdown behavior and per-module `skip*` flags.
- `config/lists/<area>/*.json` — the baseline data each Type1 module diffs against (bloatware
  names, essential apps, security baseline, etc.). Baseline JSON commonly has `common` /
  `windows10` / `windows11` sections that Type1 modules merge based on `OSContext`. One merged
  audit may consume several list folders (e.g. SoftwareManagement reads `bloatware`,
  `essential-apps`, `app-upgrade`).
- `config/sysmon/sysmonconfig.xml` — Sysmon configuration applied by SystemConfiguration.
- `temp_files/` (git-ignored) — `logs/maintenance.log` (the single unified log; the launcher
  migrates its startup log here after extraction), `diff/*-diff.json`, `reports/*.html`, `data/`.
  Created at startup by the launcher/orchestrator and core module.

## Conventions

- **PowerShell 7 required** for all `.ps1`/`.psm1` (`#Requires -Version 7.0`); the launcher and
  the AppX layer are the only parts that interoperate with PS5.1.
- Modules end with `Export-ModuleMember` listing only their public `Invoke-*` function(s).
- Every module returns a `New-ModuleResult` hashtable so the orchestrator and report generator
  can treat all modules uniformly (`Status`, `ItemsDetected/Processed/Skipped/Failed`,
  `RebootRequired`, `ExtraData`).
- Log through `Write-Log` (never `Write-Host` for status), using an uppercase `Component` tag.
  `Write-Host` in the orchestrator is reserved for the user-facing stage banners / menus.
- Reboot is only ever decided in two places: `script.bat` (pending Windows Update at startup)
  and Stage 5 cleanup. Individual modules signal a need via `RebootRequired`; they must not reboot.

## Consolidation note

The Type2 surface was consolidated from six modules to four: `SoftwareManagement` merged
BloatwareRemoval + AppManagement (itself EssentialApps + AppUpgrade); `SystemConfiguration`
merged SystemHardening (Security + Telemetry) + SystemOptimization. `DiskCleanup` and
`WindowsUpdates` stay standalone (distinct risk/tooling). Superseded `.psm1` files were deleted,
so any module on disk is live. When merging modules, keep the one-combined-diff-plus-discriminator
pattern and register the pair in `$ModulePairs`.
