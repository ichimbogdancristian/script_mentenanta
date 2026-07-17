# Project Analysis — Windows Maintenance Automation

_Analysis date: 2026-07-17 · Scope: entire repository (launcher, orchestrator, core, all module pairs, configs, logging, report generation)._

This document captures the logic of each task, bugs and inconsistencies, cross-module
integration, the logging system, report generation, and concrete opportunities to improve.
Findings are tagged **[Sev: High/Med/Low]** and reference `file:line`.

---

## 1. Executive summary

The project is a well-structured, diff-driven Windows maintenance system: a batch launcher
bootstraps the environment and a PowerShell 7 orchestrator runs audit→diff→action→report→cleanup
in five stages. The Type1/Type2 pair model with a single combined diff per pair is clean and
consistent. After the recent 6→4 module consolidation the module layer is coherent.

The most impactful problems are **not** in the module logic itself but at the **integration seams**:

- The **report generator has gone stale** relative to the consolidation — its diff-detail lookup
  still maps deleted module names, so Type1 audit cards and the new merged modules lose their
  per-item detail. **[High]**
- **DiskCleanup's DISM path is dead** — it calls the core process helper with a `-TimeoutSeconds`
  parameter that does not exist, so component-store cleanup always throws. **[High]**
- **Large parts of the security baseline are defined but never applied** (`securityPolicy`,
  `auditPolicy`), and several optimization config sections are marked not-implemented. **[Med]**
- **Scheduled (SYSTEM) runs can't apply the per-user HKCU tweaks** the optimization module writes. **[Med]**

None of these block a normal interactive run, but several silently reduce what the tool actually
accomplishes.

---

## 2. Architecture recap (as-built)

- **`script.bat`** — elevation → pending-WU reboot check → monthly task → **self-update from GitHub**
  → winget/PS7/PSWindowsUpdate install → Defender exclusions → restore point → launches the
  orchestrator in a new `pwsh` window and exits.
- **`MaintenanceOrchestrator.ps1`** — single transcript; Stage 1 (Type1 audits, interactive menu),
  Stage 2 (diff analysis), Stage 3 (Type2 actions on non-empty diffs), Stage 4 (HTML report),
  Stage 5 (countdown → reboot+cleanup or abort).
- **4 pairs + inventory** registered in `$ModulePairs`: SoftwareManagement, SystemConfiguration,
  DiskCleanup, WindowsUpdates, (+ SystemInventory, report-only).
- **`modules/core/Maintenance.psm1`** — logging, OS context, config/baseline loading, diff engine,
  compare/apply helpers, AppX compat layer, shared queries, external-process helper.
- **`modules/core/ReportGenerator.psm1`** — self-contained HTML report.

---

## 3. Bugs & correctness issues

### 3.1 Report diff-detail lookup is stale after consolidation — **[High]**
`ReportGenerator.psm1:356-379` (`Build-ModuleCard`). The per-module "N item(s) detailed" section
loads diff data by `Get-DiffList -ModuleName $Result.ModuleName`, falling back to a hardcoded
`keyMap`. After the 6→4 consolidation:
- The `keyMap` (lines 360-375) still lists **deleted** module names (`BloatwareRemoval`,
  `EssentialApps`, `SecurityEnhancement`, `TelemetryDisable`, `SystemOptimization`, `AppUpgrade`)
  and has **no entries** for the current diff keys.
- **Type2 cards** happen to work because `ModuleName == DiffKey` (`SoftwareManagement`,
  `SystemConfiguration`, `DiskCleanup`, `WindowsUpdates`).
- **Type1 audit cards** break: `ModuleName` is e.g. `SoftwareManagementAudit`, which matches no
  diff file and no keyMap entry → the audit cards silently lose their item detail.

_Fix:_ replace the keyMap with a suffix strip (`$moduleName -replace 'Audit$',''`) or an explicit
map of the 4 audit names → diff keys. Also removes dead references to deleted modules.

### 3.2 DiskCleanup DISM cleanup always fails — **[High]**
`modules/type2/DiskCleanup.psm1:97-98` calls
`Invoke-ExternalPackageCommand -FilePath dism.exe -ArgumentList $dismArgs -TimeoutSeconds 1800`,
but `Invoke-ExternalPackageCommand` (`modules/core/Maintenance.psm1`) only declares `FilePath`
and `ArgumentList`. The extra `-TimeoutSeconds` triggers a parameter-binding error → caught by the
`try/catch` → logged as `DISM component cleanup failed`. **The `update-cleanup` path has never
run successfully.**

_Fix:_ add a `-TimeoutSeconds` parameter to `Invoke-ExternalPackageCommand` with a real
`WaitForExit(ms)` timeout + kill-on-timeout (this is clearly the originally-intended contract),
then the DISM and any long winget calls become bounded.

### 3.3 `Invoke-ExternalPackageCommand` has no timeout and a deadlock risk — **[Med]**
`modules/core/Maintenance.psm1` (`Invoke-ExternalPackageCommand`). It calls
`StandardOutput.ReadToEnd()` then `StandardError.ReadToEnd()` then `WaitForExit()`. If a child
process fills the stderr pipe buffer (~4KB) while we are blocked reading stdout, both sides block —
a classic redirect deadlock. Verbose winget/choco/DISM output makes this reachable. There is also
no timeout, so a hung package manager hangs the whole run. _Fix:_ use async reads
(`BeginOutputReadLine`) or `Task`-based reads, plus a `WaitForExit(timeoutMs)` (ties into 3.2).

### 3.4 Windows Update severity classification is muddled — **[Med]**
`modules/type1/WindowsUpdatesAudit.psm1:57`
`$isSecurity = [bool]$severity -or ($title -match 'Security|Cumulative')`. `[bool]$severity` is
`$true` for **any** non-empty `MsrcSeverity` (`Low`, `Moderate`, `Unspecified`, …), so any update
carrying a severity is classed "security" and pulled in even when `optional:false`. `isCritical` /
`isImportant` are then computed but redundant (already swallowed by `isSecurity`). Net effect:
category filtering is coarser than the config implies. _Fix:_ classify explicitly, e.g.
`security = title -match 'Security'`, `critical = severity -eq 'Critical'`, etc., and only treat a
real security classification as security.

### 3.5 System Inventory is collected but not usefully shown — **[Med]**
`modules/type1/SystemInventory.psm1:114-116` returns the whole nested inventory as
`-ExtraData $inv`. In the report, `ReportGenerator.psm1:343-349` renders ExtraData with
`"$($_.Value)"`, which stringifies nested hashtables (OS, CPU, Disks, …) to
`System.Collections.Hashtable`. So the inventory card shows keys with useless values — the module's
entire output is effectively invisible in the report. Secondary: `$inv` is `[ordered]`
(`OrderedDictionary`) passed to a `[hashtable]$ExtraData` parameter — it coerces but loses ordering.
_Fix:_ give the report a dedicated inventory renderer (recurse nested tables), or have the module
flatten to display strings.

### 3.6 Dead double-render of module cards — **[Low]**
`ReportGenerator.psm1:101` computes `$moduleCards = ... Build-ModuleCard ...` for every result, but
the variable is never emitted; lines 130-131 recompute `type1Cards`/`type2Cards` which are what the
HTML uses. `Build-ModuleCard` (which also does a diff-file read each call) runs twice per module.
_Fix:_ delete line 101.

### 3.7 Batch log timestamp is locale-fragile — **[Low]**
`script.bat:19-25` builds `LOG_DATE`/`LOG_TIME` by tokenizing `%DATE%`/`%TIME%` with fixed token
order and `delims=/. `. This depends on the OS locale's date format and will produce wrong/garbled
timestamps on many non-US locales. The PowerShell logger (`Write-Log`) is fine. _Fix:_ derive the
timestamp via `pwsh -Command "Get-Date -Format o"` or `wmic os get localdatetime`.

### 3.8 Loose bloatware registry matching — **[Low]**
`modules/type1/SoftwareManagementAudit.psm1` (bloatware section) builds `regDiff` by
`registryName -like "*$b*"` where `$b` is an AppX family id like `2414FC7A.Viber` — which never
appears in a registry DisplayName, so the registry pass rarely contributes. Harmless (the AppX
pass is authoritative) but the registry pass is close to a no-op. Pre-existing; carried over.

---

## 4. Unimplemented / dead configuration (promises the code doesn't keep)

### 4.1 CIS security baseline: `securityPolicy` and `auditPolicy` never applied — **[Med]**
`config/lists/security/security-baseline.json` defines `securityPolicy` (password/lockout policy,
account renames — normally via `secedit`) and a large `auditPolicy` array (normally via `auditpol`).
Neither `SystemConfigurationAudit` nor `SystemConfiguration` reads these sections — only `registry`,
`windowsDefender`, `services`, and `firewall.enabled` are handled. The file's `_comment` advertises
"CIS … full coverage", but coverage is partial. _Opportunity:_ add a `secedit`-based policy applier
and an `auditpol`-based audit applier, or trim the JSON to what's implemented so it isn't misleading.

### 4.2 Optimization config sections marked not-implemented — **[Low]**
`config/lists/system-optimization/system-optimization-config.json` has `registryTweaks`,
`uiOptimizations` (Win10/Win11) explicitly `"_status":"not-implemented — no audit/apply path exists
yet"` (classic context menu, show extensions, disable widgets/chat, taskbar tweaks). These are
genuinely useful Win10/11 tweaks with no code path. _Opportunity:_ wire them into the
`optimization` ConfigType as `registry` items (they're all HKCU/HKLM registry values).

---

## 5. Cross-module integration analysis

**Flow is sound.** Stage 1 runs Type1 audits (each persists a `<DiffKey>-diff.json`), Stage 2 reads
those diffs and queues only non-empty, non-skipped pairs, Stage 3 runs the queued Type2 actions,
Stage 4 reports, Stage 5 reboots/cleans. `RebootRequired` flows through the result schema into
Stage 5 correctly. Observations:

### 5.1 Scheduled SYSTEM runs can't apply per-user (HKCU) settings — **[Med]**
The monthly task is created `RU SYSTEM` (`script.bat:316-325`). But the optimization actions
`visualfx`, `background`, and startup-entry cleanup, plus telemetry `advertising`/`privacy`/`cortana`
HKCU keys, all write to **HKCU** — under SYSTEM that's SYSTEM's own hive, not the logged-in user's.
So an unattended monthly run silently no-ops those user-scoped changes. The reboot-resume startup
task (`RU %USERNAME%`) does run as the user. _Consider:_ run the monthly task as the user (or
`INTERACTIVE`), or split machine-scope vs user-scope work and apply HKCU changes per loaded profile.

### 5.2 `-NoExit` interactive window under Task Scheduler — **[Low/Med]**
`script.bat:1374-1406` always launches the orchestrator in a `-NoExit` interactive `pwsh` window and
only passes `-NonInteractive` when `%1==-NonInteractive`. The scheduled tasks invoke `script.bat`
with **no args**, so a scheduled run tries to open an interactive window with 10s/120s countdowns.
The orchestrator guards `[Console]::KeyAvailable`, so it won't crash, but a `-NoExit` window spawned
by a SYSTEM task is odd and may linger. _Consider:_ detect non-interactive sessions in the launcher
and pass `-NonInteractive` automatically for scheduled runs.

### 5.3 Redundant installed-apps enumeration — **[Low]** (perf)
`Get-InstalledApp` (registry + AppX-via-powershell.exe) is invoked multiple times per run:
twice inside `SoftwareManagementAudit` (bloatware `regApps`, essential `installed`) and again in
`SystemInventory`. Each AppX enumeration spawns a Windows PowerShell 5.1 child. _Opportunity:_ cache
the installed-app list for the session (e.g. a script-scoped memo in the core module).

### 5.4 Sysmon integration (new) — verify behavior — **[Low]**
`SystemConfiguration` installs Sysmon via winget and applies `config/sysmon/sysmonconfig.xml`. The
audit queues it only when the `Sysmon`/`Sysmon64` service is absent, so config drift on an existing
install isn't re-applied. Acceptable for now; a future enhancement could compare the running config
hash (`sysmon -c` dumps current config) and re-apply on drift.

---

## 6. Logging system analysis

> **Status (2026-07-17): redesigned.** `maintenance.log` is now written directly by the core
> logger through an auto-flushed `StreamWriter` (`FileShare.ReadWrite`), decoupled from the
> transcript, which was demoted to a `transcript.log` sidecar. Added per-sink level gating
> (console INFO / file DEBUG, config-driven via a `logging` block), a top-level
> `try/catch/finally` fatal-capture guard in the orchestrator (`Write-LogException` dumps message
> + `ScriptStackTrace` + position + recent `$Error`), guards on the previously-naked crash paths
> (core import, `Get-MainConfig`, Stage 2 per-pair, menu key-read), and `Close-LogFile` before
> project-folder deletion. The Stage-4 transcript stop/restart blind spot is gone. The points
> below describe the pre-redesign state and the rationale.


- **Two loggers, one format goal.** Batch `:LOG_MESSAGE` emits `[ts] [LEVEL] [COMPONENT] msg`;
  PowerShell `Write-Log` emits the same shape. Good consistency of intent.
- **Handoff is clean.** The launcher writes a bootstrap log to `%TEMP%`, passes it via
  `$env:BOOTSTRAP_LOG`, and the orchestrator injects+deletes it into the transcript
  (`MaintenanceOrchestrator.ps1:64-76`). Nicely done.
- **Single transcript** captures everything Write-Log prints (it uses `Write-Host`), which is the
  intended design.
- **Gaps / opportunities:**
  - No level filtering — `DEBUG` always prints. A `MAINT_LOG_LEVEL` env/config knob would cut noise
    in the report transcript. **[Low]**
  - `Write-Log` writes only to the console/transcript; there is no independent structured log file
    (e.g. JSON lines) for machine parsing. **[Low, opportunity]**
  - Stage 5 events (reboot/cleanup) occur **after** Stage 4 builds the report, so they never appear
    in the embedded transcript. Acceptable, but worth a note in the report. **[Low]**
  - Batch timestamp locale bug (3.7).

---

## 7. Report generation analysis

- **Strengths:** self-contained single-file HTML, no external deps, inline CSS, light/dark-agnostic
  dark theme, per-module cards grouped by Type1/Type2, error aggregation, embedded transcript,
  copy to the launcher folder. HTML-encoding is done defensively with a manual fallback when
  `System.Web` is unavailable in PS7 Core (`ReportGenerator.psm1:21,144-151,328-336`).
- **Issues:** stale diff keyMap (3.1), inventory rendering (3.5), dead double-render (3.6).
- **Opportunities:**
  - Render `DiskCleanup`'s `ExtraData.BreakdownByCategory` (reclaimed MB per category) as a small
    table — the data is produced (`DiskCleanup.psm1:142-145`) but shows as `System.Collections.Hashtable`
    (same root cause as 3.5). **[Med]**
  - Add a dedicated **System Inventory** section (OS/CPU/RAM/disk/network) rather than dumping it as
    ExtraData. **[Med]**
  - Show the Stage-2 decision (which Type2 modules were skipped because the diff was empty) as an
    explicit section. **[Low]**
  - Consider emitting a machine-readable `report.json` alongside the HTML for trend tracking. **[Low]**

---

## 8. Optimization opportunities (performance)

1. **Parallelize independent Type1 audits** — DiskCleanup's `DISM /AnalyzeComponentStore` and the WU
   COM search are the slow ones and are independent. PS7 `ForEach-Object -Parallel` (or runspaces)
   could overlap them; needs care because modules import into the global scope and share `$env:MAINT_*`.
   Alternatively just reorder so the slow audits overlap with user think-time in the Stage 1 menu. **[Med]**
2. **Batch/cache AppX enumeration** — the `*Compat` layer spawns `powershell.exe` per call; the
   bloatware audit + removal issue many. Enumerate once, filter in-memory. **[Med]**
3. **Cache `Get-InstalledApp`** per session (see 5.3). **[Low]**
4. **Skip DISM analyze when free space is ample** or cache its result between the audit and any future
   re-run. **[Low]**

---

## 9. Enhancement opportunities (features)

- **Bounded external commands** (3.2/3.3): a single robust `Invoke-ExternalPackageCommand` with
  timeout + async capture unlocks safe DISM/winget/choco calls project-wide.
- **secedit/auditpol appliers** (4.1) to actually deliver the advertised CIS baseline.
- **Optimization registry tweaks** (4.2) — quick wins already described in config.
- **Sysmon drift re-apply** (5.4).
- **Rollback command** — `SystemConfiguration` already backs up pre-change Defender/firewall state
  (`SystemConfiguration.psm1`); a companion "restore last backup" entry point would make hardening
  reversible without a full system-restore.
- **Dry-run / WhatIf mode** — Type2 modules could accept a `-WhatIf`/report-only switch to preview the
  diff application (the diff already exists; only the apply loop needs gating).
- **Per-module config `skip*` parity** — `main-config.json` now has exactly the 4 keys the
  orchestrator reads; keep a test that asserts `$ModulePairs.ConfigSkip` ⊆ config keys so they can't
  drift again.

---

## 10. Prioritized recommendations

| Priority | Item | Why |
|---|---|---|
| P1 | Fix report diff keyMap (3.1) | Report is the primary deliverable; audit detail is currently missing |
| P1 | Add timeout to `Invoke-ExternalPackageCommand` + fix DiskCleanup call (3.2/3.3) | Dead DISM path + hang/deadlock risk across all package ops |
| P2 | Render inventory + cleanup breakdown in report (3.5/3.6, §7) | Collected data is invisible; low effort |
| P2 | Decide SYSTEM vs user for scheduled runs (5.1/5.2) | Unattended runs silently skip user-scoped tweaks |
| P2 | WU severity classification (3.4) | Category filtering doesn't match config intent |
| P3 | Implement or trim securityPolicy/auditPolicy + optimization tweaks (4.1/4.2) | Align code with config promises |
| P3 | Parallelize/cache audits & AppX (8.1-8.3) | Runtime on slow machines |
| P3 | Batch timestamp locale fix (3.7) | Correct launcher logs everywhere |

---

_Notes: line references reflect the tree at analysis time. Items 3.1 and 3.2 are the two that most
directly interact with the recent module consolidation and should be addressed first; neither was
introduced by the consolidation (3.2 predates it; 3.1 is the report failing to keep pace with it)._
