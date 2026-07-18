# Project Analysis v2 — Windows Maintenance Automation

_Re-analysis 2026-07-17. Supersedes v1. Every finding below was **verified by execution or AST/source
extraction**, not inferred — the evidence is quoted with each item. Reported coverage-first: nothing
filtered for severity, each item carries confidence + severity so you can rank._

---

## 0. What changed since v1 (your brief is partly stale)

Your standing brief (`xxx.md`) asks me to consider merging **SecurityEnhancement with TelemetryDisable**
and **DiskCleanup with SystemOptimization**. The first is **already done** — the 6→4 consolidation merged
Security+Telemetry (and SystemOptimization) into `SystemConfiguration`. The logging system was also
rebuilt since that brief was written. Current state:

| Pair | Type1 | Type2 | DiffKey | Discriminator |
|---|---|---|---|---|
| 1 | SoftwareManagementAudit | SoftwareManagement | `SoftwareManagement` | `Action` = remove/install/upgrade |
| 2 | SystemConfigurationAudit | SystemConfiguration | `SystemConfiguration` | `ConfigType` = security/telemetry/optimization |
| 3 | DiskCleanupAudit | DiskCleanup | `DiskCleanup` | `Type` |
| 4 | WindowsUpdatesAudit | WindowsUpdates | `WindowsUpdates` | — |
| 5 | SystemInventory | *(none)* | `SystemInventory` | report-only |

**Structural health is good.** Verified clean: DiffKey contract intact on all 5 pairs; **zero** config
drift (skip flags ↔ `ConfigSkip` match exactly); **all 8** `config/lists/` folders consumed by a module;
only referenced modules exist on disk.

---

## 1. The logic, as built (your "understand this" list)

**PS5 → PS7 relaunch.** `script.bat` runs under cmd/PS5.1. PS7 acquisition is now:
`:FIND_PWSH` (delegates the search to PS5.1, checks PATH + MSI dirs + **AppX/MSIX InstallLocation** +
WindowsApps alias + registry, and *validates each candidate by executing it* and requiring
`PSVersion.Major >= 7`) → install via `winget --source winget --exact` (forces the **MSI**, not the
msstore MSIX) → re-run `:FIND_PWSH` → continue in-process (relaunch only if still unreachable).
The orchestrator is then launched in a dedicated `pwsh` window and the launcher exits.

**Reboot policy — exactly two decision points, as you specified.** (1) `script.bat` startup: authoritative
WU markers only (`Auto Update\RebootRequired`, `Orchestrator\RebootRequired`, `PostRebootReporting`, plus
PSWindowsUpdate if present) → creates an ONLOGON task and reboots. (2) Stage 5: reboots on countdown
expiry unless a key is pressed, or skips entirely when `rebootOnlyWhenRequired` is set and no module
flagged `RebootRequired`. **Modules never reboot** — they only set the flag. This is correctly enforced.

**Diff lists — the contract.** A pair never calls across; they communicate only through
`temp_files/diff/<DiffKey>-diff.json`. Type1 loads a baseline from `config/lists/`, scans live state,
computes the delta, and `Save-DiffList`. Stage 2 reads that file: **non-empty diff ⇒ queue the Type2**;
empty ⇒ Type2 never runs (recorded as `Skipped`). Type2 calls `Get-DiffList`, acts *only* on those items,
returns `New-ModuleResult`. The `DiffKey` is the whole contract — it must match in the Type1's
`Save-DiffList`, the Type2's `Get-DiffList`, and `$ModulePairs`. This is why a run on an
already-compliant machine makes zero changes: every diff is empty.

---

## 2. Verified bugs (ranked)

### 🔴 2.1 The Chocolatey PS7 fallback is **completely dead** — `[HIGH, confirmed]`
`script.bat:791-794`
```bat
IF NOT "!INSTALL_STATUS!"=="SUCCESS" (
    SET "CHOCO_EXE=choco"                              <- set INSIDE the block
    IF EXIST "...\choco.exe" SET "CHOCO_EXE=...choco.exe"
    "%CHOCO_EXE%" --version >nul 2>&1                  <- %-read, SAME block => parse-time
```
`%CHOCO_EXE%` resolves when the block is **parsed** — before line 791 runs — so it expands to **empty**.
The command becomes `"" --version`, which always fails ⇒ the code always concludes *"Chocolatey not
available"* and jumps to installing Chocolatey from scratch. **This matches both of your run logs
verbatim.** Same defect at lines 797 and 823 (`"%CHOCO_EXE%" install powershell-core`), so even the
freshly-installed Chocolatey is never used. Net effect: PS7 has **two** working install paths (winget,
MSI), not three. Fix: `!CHOCO_EXE!`.

### 🔴 2.2 DiskCleanup's DISM path always throws — `[HIGH, confirmed by AST]`
`modules/type2/DiskCleanup.psm1:98` calls `Invoke-ExternalPackageCommand -TimeoutSeconds 1800`, but the
core function declares only `FilePath, ArgumentList`. AST contract check output:
```
Caller           Line  Call                          BadParam         Declares
DiskCleanup.psm1  98   Invoke-ExternalPackageCommand -TimeoutSeconds  FilePath,ArgumentList
```
Parameter-binding error → caught → logged as *"DISM component cleanup failed"*. The `update-cleanup`
path has **never** succeeded. Fix: add a real `-TimeoutSeconds` to the core helper (see 2.8).

### 🟠 2.3 False "All winget installation methods failed" — `[MED, confirmed]`
`script.bat:734` `IF "%WINGET_AVAILABLE%"=="NO" (` sits *inside* the enclosing
`IF "%WINGET_AVAILABLE%"=="NO" (...)` install block, and `WINGET_AVAILABLE=YES` is set at line 728 within
it. The `%`-read is parse-time ⇒ always `"NO"` ⇒ the warning fires **even when winget was just installed
successfully**. Fix: `!WINGET_AVAILABLE!`.

### 🟠 2.4 Report: 3 of 5 audit cards silently lose their detail section — `[MED, confirmed]`
`ReportGenerator.psm1:356-379`. Measured against the `ModuleName` values the modules actually emit:

| ModuleName emitted | direct DiffKey hit | in keyMap | detail renders |
|---|---|---|---|
| `SoftwareManagementAudit` | ✗ | ✗ | **NO — lost** |
| `SystemConfigurationAudit` | ✗ | ✗ | **NO — lost** |
| `DiskCleanupAudit` | ✗ | ✗ | **NO — lost** |
| `WindowsUpdatesAudit` | ✗ | ✓ | yes |
| all four Type2 names | ✓ | ✗ | yes (ModuleName == DiffKey by luck) |

Also: **12 keyMap entries reference deleted modules** (`BloatwareRemoval`, `EssentialApps`,
`SecurityEnhancement`, `TelemetryDisable`, `SystemOptimization`, `AppUpgrade`, + their audits) — pure dead
code. Fix: replace the whole map with `$moduleName -replace 'Audit$',''`.

### 🟠 2.5 Nested `ExtraData` renders as `System.Collections.Hashtable` — `[MED, confirmed by execution]`
`ReportGenerator.psm1:343-349` stringifies each value with `"$($_.Value)"`. Live output:
```
SystemInventory ExtraData:   Memory -> System.Collections.Hashtable
                             OS     -> System.Collections.Hashtable
DiskCleanup     ExtraData:   BreakdownByCategory -> System.Collections.Hashtable
                             ReclaimedMB         -> 1234.5
```
So **the entire System Inventory module's output is invisible in the report** (its whole purpose), and
DiskCleanup's per-category reclaimed-MB breakdown is lost. Fix: recurse nested tables, or add a dedicated
inventory renderer.

### 🟠 2.6 WU severity filter ignores `optional: false` — `[MED, confirmed by execution]`
`WindowsUpdatesAudit.psm1:57` — `$isSecurity = [bool]$severity -or ...`. Measured:
```
MsrcSeverity=Low          -> isSecurity=True  isOptional=False
MsrcSeverity=Moderate     -> isSecurity=True  isOptional=False
MsrcSeverity=Unspecified  -> isSecurity=True  isOptional=False
```
**Any** update carrying **any** severity is classed "security", so `categories.optional:false` never
excludes it, and `isCritical`/`isImportant` are computed but redundant. Fix: classify explicitly
(`security = title -match 'Security'`, `critical = severity -eq 'Critical'`, …).

### 🟡 2.7 `WORKING_DIRECTORY` — stale value **and** dead — `[LOW, confirmed]`
`script.bat:460` `SET "WORKING_DIRECTORY=%WORKING_DIR%"` reads `%WORKING_DIR%` in the same block it was
just assigned (line 459) ⇒ captures the **pre-extraction** path. But a full-tree search shows it is
**assigned twice and never read by anything** (`script.bat:164`, `:460` — no consumer in any `.ps1`/`.psm1`).
The bug is real but inert. Fix: delete both lines.

### 🟡 2.8 `Invoke-ExternalPackageCommand`: no timeout + deadlock risk — `[MED, by inspection]`
Reads `StandardOutput.ReadToEnd()` then `StandardError.ReadToEnd()` then `WaitForExit()`. If a child fills
the stderr pipe buffer (~4KB) while we block on stdout, both sides wedge — reachable with verbose
winget/DISM output. No timeout either, so a hung package manager hangs the run forever. Fix: async reads
+ `WaitForExit(ms)` + kill-on-timeout. **This also unblocks 2.2.**

### 🟡 2.9 Empty log values on two scheduled-task branches — `[LOW, confirmed]`
`script.bat:147, :151` still use `%SCHEDULED_TASK_SCRIPT_PATH%` inside the block that sets it (line 143
was already fixed to `!...!`). Log-cosmetic only.

---

## 3. Config that the code never honours

### 3.1 CIS baseline is **half-applied** — `[MED]`
`config/lists/security/security-baseline.json` defines `securityPolicy` (password/lockout policy, account
renames — normally `secedit`) and a **19-entry `auditPolicy`** array (normally `auditpol`). **No code path
reads either.** `SystemConfigurationAudit` handles only `registry`, `windowsDefender`, `services`, and
`firewall.enabled`. The file's `_comment` advertises *"CIS … v4.0.0"* coverage that doesn't exist.

### 3.2 Optimization tweaks explicitly marked not-implemented — `[LOW]`
`system-optimization-config.json` carries `registryTweaks` and `uiOptimizations` blocks tagged
`"_status": "not-implemented — no audit/apply path exists yet"` (classic context menu, show file
extensions, disable widgets/chat, taskbar tweaks). Real Win10/11 value, zero code — all are plain
registry values that would drop straight into the `optimization` ConfigType.

---

## 4. Module-by-module: what actually touches the OS

| Module | OS surface | Primitives | Reboot | Risk |
|---|---|---|---|---|
| **SoftwareManagement** | AppX/MSIX store, winget, choco | `Remove-AppxPackageCompat` (+ provisioned), `winget install/upgrade/uninstall`, `choco` | No | Reversible |
| **SystemConfiguration** | Defender, firewall, registry (HKLM+**HKCU**), services, scheduled tasks, powercfg, Sysmon | `Set-MpPreference`, `Set-NetFirewallProfile`, `Set-RegistryValue`, `Set-Service`, `Disable-ScheduledTask`, `powercfg`, winget+`sysmon -i` | **Yes** (Defender AV enable) | Reversible; backs up pre-state |
| **DiskCleanup** | Filesystem, DISM, recycle bin | `Remove-Item`, `dism /StartComponentCleanup`, `Clear-RecycleBin` | No | **Destructive** |
| **WindowsUpdates** | Windows Update (COM / PSWindowsUpdate / usoclient) | `Install-WindowsUpdate` | **Yes** | High-impact |
| **SystemInventory** | read-only CIM queries | `Get-CimInstance` | No | None |

**Cross-cutting: scheduled SYSTEM runs can't apply HKCU settings — `[MED]`.** The monthly task is created
`RU SYSTEM` (`script.bat:324`), but `visualfx`, `background`, startup-entry cleanup, and the telemetry
`advertising`/`privacy`/`cortana` keys all write **HKCU** — under SYSTEM that's SYSTEM's own hive, not the
logged-in user's. An unattended monthly run silently no-ops all of them. (The reboot-resume ONLOGON task
correctly runs as `%USERNAME%`.) Options: run the monthly task as the user, or split machine-scope from
user-scope and apply HKCU per loaded profile.

---

## 5. Consolidation assessment (your explicit ask)

**Already done:** SecurityEnhancement + TelemetryDisable + SystemOptimization → `SystemConfiguration`.
Bloatware + EssentialApps + AppUpgrade → `SoftwareManagement`.

**On merging DiskCleanup into SystemConfiguration — I recommend against.** Consolidation pays off when
modules share *both* tooling and risk profile. SystemConfiguration is pure registry/service/policy state
(idempotent, reversible, backed up). DiskCleanup is irreversible filesystem deletion plus DISM. They share
neither primitive nor risk, and merging would mix a destructive failure class into a config-state module's
status reporting.

**The one merge with a real argument: DiskCleanup + WindowsUpdates → `SystemServicing`.** DISM
`/StartComponentCleanup` *is* Windows-Update servicing cleanup, and correct ordering falls out naturally
(install updates → then clean the component store; never `/ResetBase` before updates land). Cost: mixes a
reboot-generating operation with destructive deletion behind one diff. **My call: keep 4.** The current
split is at the right seams; further merging trades clarity for a smaller module count you don't need.

**Better fluency win than merging — move one action.** DiskCleanup's `update-cleanup` item is the only
thing in DiskCleanup that is really WU servicing. If you ever *do* want fluency, move that single item to
the WindowsUpdates pair (post-install) rather than merging whole modules.

---

## 6. Logging & report

**Logging is now sound.** `maintenance.log` is created next to `script.bat` at the first line
(`:INIT_LOG`, append so elevation/PS7 relaunches continue it), migrated into `temp_files\logs\` after
extraction (`:MIGRATE_LOG`), and the orchestrator appends to the **same file** via `MAINTENANCE_LOG` →
`Initialize-Maintenance -LogPath`. Direct auto-flushed `StreamWriter` (`FileShare.ReadWrite`), so it
survives crashes; `transcript.log` is a raw sidecar. Per-sink levels (console INFO, file DEBUG);
`[FATAL]` + `ScriptStackTrace` on any uncaught error; log always closed in `finally`. Format
`[ts] [LEVEL] [COMPONENT] msg` is greppable and consistent between batch and PowerShell. script.bat is
now 100% ASCII → the `Γ£ô` mojibake class is gone.

**Report.** Strengths: single self-contained HTML, inline CSS, Type1/Type2 grouping, error aggregation,
embedded log, refreshed immediately before cleanup so the surviving copy holds the **complete** log.
Defects: 2.4 (audit detail lost), 2.5 (inventory + cleanup breakdown invisible), and a dead
double-render — `Build-ReportHtml:101` computes `$moduleCards` for every result and **never uses it**
(lines 130-131 recompute `type1Cards`/`type2Cards`), so every card is built twice, each doing a diff-file
read. `[LOW]`

---

## 7. Dead code / reduction

| Item | Where | Action |
|---|---|---|
| 12 keyMap entries for deleted modules | `ReportGenerator.psm1:360-375` | delete; use `-replace 'Audit$',''` |
| `$moduleCards` computed, never emitted | `ReportGenerator.psm1:101` | delete (halves card rendering) |
| `WORKING_DIRECTORY` assigned ×2, read 0× | `script.bat:164, :460` | delete both |
| `SR_VERIFY_STATUS` set, never read | `script.bat` restore-point block | delete |
| Two identical `IF "%PS_EXECUTABLE%"==""` error blocks | `script.bat` (2nd unreachable) | already collapsed by the `:FIND_PWSH` rewrite — verify none remain |
| `xxx.md` | repo root | it's your brief, not code — fold into CLAUDE.md or delete |

---

## 8. Type2 feature proposals

**SoftwareManagement**
- `winget export` / `import` — snapshot the machine's app set; makes re-provisioning a first-class feature.
- Version **pinning / hold list** (`winget pin`) so an upgrade can't move a business-critical app.
- Retry-with-backoff on transient winget exit codes (network/source failures) instead of one-shot fail.
- Detect and repair **broken installs** (`winget repair`, or reinstall on `--force`).
- Report per-app *before → after* versions in `ExtraData` (drives a proper report table).

**SystemConfiguration** *(highest-value additions — closes the §3.1 gap)*
- **`secedit` applier** for `securityPolicy`, **`auditpol` applier** for the 19 `auditPolicy` entries. This is the single biggest promise-vs-reality gap in the project.
- **Defender ASR rules** (`Add-MpPreference -AttackSurfaceReductionRules_Ids`) — high security value, pure `Set-MpPreference` family, fits the existing `defender` Type.
- **BitLocker** status audit + optional enable; **SmartScreen**; **Controlled Folder Access** (baseline already has the flag, no code path).
- **Sysmon config drift** — re-apply when the running config hash differs, not only when the service is absent.
- **Rollback entry point** — you already write `config-pre-state-*.json`; a `-Rollback` switch that replays it would make hardening reversible without System Restore.

**DiskCleanup**
- `Windows.old`, Delivery Optimization cache, Windows Error Reporting queues, thumbnail/icon cache, memory dumps, `$Recycle.Bin` per-user, Teams/Slack/Discord caches.
- Report **free space before/after** per drive (verifiable outcome, not an estimate).
- Honour a `dryRun` flag to list-only — pairs naturally with the diff model.

**WindowsUpdates**
- Decode WU error codes (`0x8024xxxx`) into actionable messages instead of surfacing raw HRESULTs.
- Optional **driver updates** (`categories.drivers` exists in config, unused) and feature-update deferral.
- Auto-install PSWindowsUpdate when missing (the launcher tries; the module should too) so the reliable path is used instead of the unverifiable `usoclient` fallback.
- Emit installed-KB list into `ExtraData` for the report.

**Cross-cutting**
- `-WhatIf`/dry-run on every Type2 — the diff already exists; only the apply loop needs gating.
- A `docs`/schema test asserting `$ModulePairs.ConfigSkip` ⊆ config keys, so §D drift can't return.

---

## 9. Prioritized

| P | Item | Why |
|---|---|---|
| **P1** | 2.1 Chocolatey `!CHOCO_EXE!` | An entire PS7 install path is dead; matches your logs |
| **P1** | 2.8 + 2.2 timeout on `Invoke-ExternalPackageCommand` | Unblocks DISM cleanup *and* removes a hang/deadlock class |
| **P1** | 2.4 report keyMap | Report is the deliverable; audit detail is missing today |
| **P2** | 2.5 render nested ExtraData | SystemInventory is 100% invisible right now |
| **P2** | 2.3 / 2.9 `!VAR!` fixes | Misleading logs; same class that caused the outages |
| **P2** | §4 SYSTEM vs user for the monthly task | Unattended runs silently skip all HKCU work |
| **P2** | 2.6 WU severity | `optional:false` doesn't do what the config says |
| **P3** | §3.1 secedit/auditpol | Delivers the advertised CIS baseline |
| **P3** | §7 dead-code sweep | ~40 lines, zero risk |
| **P3** | §3.2 optimization registry tweaks | Cheap, already specified in config |

---

## 10. Extensibility (for the modules you'll add)

The pair model holds up well. To add a feature: one Type1 (`Save-DiffList -ModuleName <Key>`), one Type2
(`Get-DiffList -ModuleName <Key>`), one `$ModulePairs` entry, one `skip*` flag. The combined-diff +
discriminator pattern (`Action` / `ConfigType`) is the right way to grow *within* a pair without adding
modules. Route registry/service work through `Compare-RegistryBaseline` / `Compare-ServiceBaseline` and
`Invoke-RegistryChangeItem` / `Invoke-ServiceChangeItem` rather than reimplementing inline — that's what
kept SystemConfiguration small despite absorbing three former modules.

_The automated checks used here (AST function/param contract, DiffKey contract, config drift,
batch delayed-expansion audit) are worth re-running as a pre-commit gate — they found 5 of the 9 bugs above._
