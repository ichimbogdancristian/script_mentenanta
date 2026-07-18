# Project Evaluation — Windows Maintenance Automation

**Date:** 2026-07-18
**Scope:** Every file in the repository was read end-to-end: `script.bat` (1,262 lines), `MaintenanceOrchestrator.ps1`, both core modules, all 7 Type1 and 5 Type2 modules, every JSON config, and all standing docs (~10,500 lines total).
**Method:** Claims marked **[VERIFIED]** were reproduced in PowerShell 7.6.3 on this machine (not just read from source). Everything else is from careful source analysis.

---

## Executive summary

The architecture (Type1 audit → diff list → Type2 action, one registry in `$ModulePairs`) is sound and the logging/report pipeline is well built. However, **the flagship feature — bloatware detection/removal — is completely non-functional due to two independent verified bugs**, the Windows Update installer path is dead on first use due to a misspelled function name, and the Windows Update *audit* invents phantom pending updates on fully-patched machines, which (combined with the reboot logic) can reboot a healthy machine for no reason.

| Category | Count |
|---|---|
| Critical bugs (feature doesn't work / wrong behavior) | 7 |
| Logic & flow faults | 11 |
| Dead / unused code and config | 12 |
| Optimization opportunities | 9 |
| Files moved to `archive/` | 10 |

---

## A. CRITICAL BUGS

### A1. AppX compatibility layer parses formatted text as objects — every AppX operation is a silent no-op **[VERIFIED]**
`modules/core/Maintenance.psm1` — `Invoke-AppxInWinPS` (line 899), `Get-AppxPackageCompat` (925), `Get-AppxProvisionedPackageCompat` (981).

`Invoke-AppxInWinPS` runs `powershell.exe -NoProfile -Command "<cmd>"` and returns the result. External process output is **an array of plain strings** (the formatted table), not objects. Verified:

```
winps output element type => String
winps .Name of first element => ||||||   (all $null)
```

`Get-AppxPackageCompat` then builds hashtables from `$_.Name` / `$_.PackageFullName` of those strings — every field is `$null`. Downstream:
- `SoftwareManagementAudit` Source 1 (AppX) finds **nothing** (`Where-Object { $_ }` filters out all nulls).
- `SoftwareManagement` removal Layers 1–2 never remove anything (null `PackageFullName`).
- `Get-InstalledApp` never includes AppX/MSIX apps, so essential-app detection and inventory app counts are wrong.

**Fix:** serialize across the boundary — in the WinPS command append `| ConvertTo-Json -Depth 4`, and `ConvertFrom-Json` the joined string output in PS7. Additionally, `Get-AppxProvisionedPackage` is invoked **without `-Online`** (lines 990, 1039), which fails even in PS 5.1 (verified: returns nothing), so Layer 1 of provisioned detection always falls to the DISM text parser.

### A2. `.PSObject.Properties` used to iterate JSON hashtables — bloatware audit produces ZERO patterns and the protected-package safety net is inert **[VERIFIED]**
`Get-BaselineList` returns **hashtables** (`ConvertFrom-Json -AsHashtable`). On a hashtable, `.PSObject.Properties` enumerates the .NET properties of the Hashtable object, verified:

```
hashtable PSObject.Properties names => Count,IsFixedSize,IsReadOnly,IsSynchronized,Keys,Values,SyncRoot
```

Three call sites in `modules/type1/SoftwareManagementAudit.psm1` are broken by this:
1. **Line 245** `foreach ($category in $bloatConfig.categories.PSObject.Properties)` — iterates `Count`, `Keys`, `Values`… so **zero patterns** are extracted from `bloatware-detection.json`. An empty `List[string]` is falsy (verified), so `if ($bloatConfig -and $bloatConfig.patterns)` skips the entire remove-audit. Because `bloatware-detection.json` exists, the legacy `bloatware-list.json` fallback never triggers either. **Net effect: bloatware detection detects nothing, ever.** This is almost certainly the real root cause of the original complaint "bloatware discovery and removal does not work at all" — the v7 redesign documented in the archived docs did not fix it, it re-introduced it in a new shape.
2. **Lines 24–37** `Test-CanRemovePackage` iterates `$Protected.PSObject.Properties` — the protected-packages check never matches, so **nothing is ever protected**. (Currently masked by bug #1, but the moment #1 is fixed, the safety net must be fixed too or wildcard patterns like `Dell.*` run unguarded.)
3. **Lines 41–51** — same for the dependency matrix.

**Fix:** iterate hashtables with `.GetEnumerator()` (or `.Keys`), e.g. `foreach ($category in $bloatConfig.categories.GetEnumerator()) { $category.Value.apps … }`.

### A3. `Test-UpdateInstalled` doesn't exist — the PSWindowsUpdate install path dies on the first update **[VERIFIED name mismatch]**
`modules/type2/WindowsUpdates.psm1:114` calls `Test-UpdateInstalled`, but the function is named `Test-UpdateAlreadyInstalled` (line 14). The call sits **outside** the inner try (line 120), so the `CommandNotFoundException` is caught by the *outer* catch (line 160), which logs "PSWindowsUpdate module error … Falling back to usoclient" and abandons the whole PSWindowsUpdate path. Since almost every update title contains a KB number, this fires on the first item **every run**: updates are never installed via the controlled, verifiable path; instead `usoclient` is fired blind, `$processed` is faked to `$diff.Count`, and **`RebootRequired` is forced `$true`**. Side effect: `Test-UpdateAlreadyInstalled` is dead code.

### A4. `| default 'none'` — nonexistent command crashes the failure-logging path **[VERIFIED — `default` is not a command]**
`modules/type2/SoftwareManagement.psm1:115`:
```powershell
Write-Log ... "  Not found (attempted: $($attempts -join ', ' | default 'none'))"
```
`default` is not a cmdlet/alias/function. This line executes exactly when a removal found nothing (`$removed -eq $false`), throwing `CommandNotFoundException` out of `Remove-BloatwareLayered` into the caller's catch — so every "not removed" item is misreported as a hard error. Fix: `$(if ($attempts) { $attempts -join ', ' } else { 'none' })`.

### A5. Windows Update audit falls through to weaker layers after a *successful* COM scan — phantom pending updates on healthy machines
`modules/type1/WindowsUpdatesAudit.psm1` — the layering confuses "layer failed" with "layer found nothing":
- **Line 58–65:** If Layer 1 (COM) succeeds and correctly finds **0 pending updates** (a fully-patched machine), the code *continues to Layer 2/3* instead of returning "0 pending".
- **Layer 2 (line 74):** `CBS\RebootPending` means *a reboot is pending*, not *updates need installing* — yet it enqueues a pseudo-update `Identity='CBS'` that Type2 then tries to feed to `Install-WindowsUpdate -UpdateID 'CBS'`.
- **Layer 3 (line 114):** Event ID 19 is **"Installation Successful"** — it harvests KBs of *already-installed* updates and queues them as pending.

Combined effect on a healthy, fully-patched machine: audit reports pending updates → Stage 3 runs WindowsUpdates → (via bug A3) usoclient is triggered and `RebootRequired=$true` → **Stage 5 reboots a machine that needed nothing**, even with `rebootOnlyWhenRequired: true`. Fix: `return` "0 pending" when Layer 1 *succeeds*; use fallback layers only when Layer 1 *throws*; drop Event-ID-19 harvesting entirely (or use it only to *exclude* installed KBs).

### A6. Restore point removal cannot work
`modules/type2/RestorePointManagement.psm1:85` builds `\\.\GLOBALROOT\Device\HarddiskVolumeShadowCopy$seqNum`, but `$seqNum` is a **GUID** extracted from `Win32_ShadowCopy.ID` while those device names use small **integer indices** (`…ShadowCopy1`, `…ShadowCopy2`) — the path is never valid. The fallback (line 95) pipes `Get-WmiObject` output into `Remove-WmiObject`; in PS7 both only exist as WinPS-compat remoting proxies (verified: resolved as `Function` from proxy module v1.0), and piping deserialized CIM objects between two remoting proxies does not bind reliably. Conceptual issue on top: **`Win32_ShadowCopy` enumerates all VSS shadow copies (incl. backup snapshots), not restore points** — "consolidating restore points" by deleting shadow copies can delete backup history. Use `vssadmin delete shadows /Shadow={GUID}` (still shadow-copy-scoped) or better, `srremove`/`SRRemoveRestorePoint` P/Invoke, and enumerate restore points via `SystemRestore` WMI class in the WinPS session instead of `Win32_ShadowCopy`.

### A7. Registry fallback comparison uses stale `$Matches`
`modules/type1/SystemConfigurationAudit.psm1:41-44` — `$regQuery` is an **array** of output lines; `-match` on an array returns matching *elements* and does **not** populate `$Matches`, so `$Matches[1]` reads whatever a previous `-match` left behind. The regex `'REG_\w+\s+(.+?)(?:\s|$)'` would also capture only the first token of multi-word values. Low blast radius (Layer 2 only runs if `Compare-RegistryBaseline` throws, which is rare) but the fallback produces garbage when it does run. Fix: `$line = $regQuery | Where-Object { $_ -match '…' } | Select-Object -First 1` then re-match on the single string.

---

## B. LOGIC & FLOW FAULTS

### B1. RestorePointAudit always queues a `create` action — breaks the "empty diff ⇒ no changes" contract
`RestorePointAudit.psm1:75` unconditionally adds `Action='create'`, so the diff is never empty and Stage 3 always runs Type2 — the audit/diff discipline the whole design is built on is bypassed for this pair. It also **duplicates the launcher**, which already creates a restore point pre-run (script.bat:1130-1164), and Windows throttles restore-point creation to one per 24h by default, so the module's `Checkpoint-Computer` is usually a silent no-op anyway. Recommendation: only queue `create` if no restore point exists from the last N hours, or drop creation from the pair entirely (launcher already covers it) and keep only consolidation.

### B2. Disk cleanup audit: config paths expand to the *admin's* profile inside the per-user loop
`DiskCleanupAudit.psm1:129-149` — when `config.browsers.paths.chrome.root` is set (it is, `%UserProfile%\AppData\Local\Google\Chrome\User Data`), `ExpandEnvironmentVariables` resolves it to the **running (elevated) user's** profile, and the surrounding `foreach ($profileDir in $userProfiles)` then adds that *same* path once **per user on the machine**: (a) duplicate diff items → the same cache is "cleaned" N times and its size counted N times; (b) other users' browsers are **never** audited, contradicting the config's own description. Same story for temp: the config's "Per-User Temp" (`%UserProfile%\...\Temp`) plus the explicit per-user loop double-counts the admin's temp. Fix: ignore `browsers.paths.*.root` in the per-user loop (build from `$profileDir` as the `else` branches already do) or treat the config value as a *relative* path under each profile.

### B3. Power-plan audit is never idempotent on localized Windows
`SystemConfigurationAudit.psm1:236-245` — `powercfg /getactivescheme` prints the plan name **localized** (e.g. "Performanță înaltă" on Romanian Windows). `"High Performance"` never matches, so the diff flags the power plan **every single run** and Type2 re-applies it forever. Also `$currentPlan` is an array of lines; `-notmatch` on an array filters elements rather than testing a string. Fix: compare **GUIDs**, not names (`/getactivescheme` output contains the GUID; the desired plan should be configured as a GUID).

### B4. Stage 5 cleanup deletes the folder that is the process's current directory
The launcher starts pwsh with `Set-Location '<extracted folder>'` (script.bat:1209) and `-NoExit`. Stage 5 then does `Remove-Item -Path $ProjectRoot -Recurse -Force` (orchestrator:644/721) — Windows will not remove the current working directory of a live process, so the root folder always survives ("Could not fully remove project folder" every time). Fix: `Set-Location $env:TEMP` (or `$env:SystemRoot`) before `Remove-Item`, and drop `-NoExit` from the launcher for unattended runs.

### B5. Stale diff files can drive Stage 3 with outdated data
Diffs live in `temp_files/diff/` and are only overwritten when the Type1 module reaches `Save-DiffList`. If an audit **fails before saving** (or a subset is selected via the menu on a dev machine where `temp_files` persists), Stage 2 happily reads the *previous run's* diff and Stage 3 acts on it. In deployed runs the folder is fresh (re-extracted), but the dev loop (`pwsh -File .\MaintenanceOrchestrator.ps1`) is exposed. Fix: delete `temp_files/diff/*` at orchestrator startup, and in Stage 2 skip a pair whose Type1 result was `Failed`.

### B6. SystemHealth "Defender incidents" counts every operational event, and severity is always Unknown
`SystemHealthAudit.psm1:124-145` — the Defender query has **no Event ID filter**, so routine operational events (signature updates, scans) are all counted as "incidents"; combined with line 59 this makes the module report `Warning` on virtually every machine. Additionally `switch ($eventData[3])` matches against the `EventProperty` **object** (its type name), not `.Value` — severity is always `'Unknown'`. Fix: filter IDs 1116/1117/1118/1119/5001/5007-ish, and use `$eventData[3].Value`.

### B7. WinGet bloatware source treats whole output lines as package names
`SoftwareManagementAudit.psm1:153-172` — Source 4 matches patterns against **entire `winget list` output lines** and stores the full line (name+id+version columns) as `Name`/`PackageName`. Type2 then wildcard-searches registry DisplayNames with that garbage string. Either parse winget columns properly (or use `winget list --exact --id` per configured id) or drop Source 4 — Sources 1–3 already cover its ground.

### B8. Executing raw `UninstallString`s, with a stray `-ErrorAction`
`SoftwareManagement.psm1:80` — `& cmd /c $uninstallString -ErrorAction Continue` passes the literal text `-ErrorAction Continue` **as arguments to the uninstaller**, and runs arbitrary uninstall strings that are frequently *interactive* (GUI installers) — under a scheduled SYSTEM run this can hang the pipeline indefinitely (no timeout here, unlike `Invoke-ExternalPackageCommand`). At minimum: strip the bogus argument, add `/quiet`-style handling for msiexec strings, and route through `Invoke-ExternalPackageCommand` with a timeout.

### B9. Registry rollback logic can't restore the most common case
`SystemConfiguration.psm1` — `Backup-RegistryValue.Exists` records whether the **key path** exists, not whether the *value* existed. Consequences: if the key existed but the value didn't (the most common hardening case), `$Backup.Value` is `$null` and `Restore-RegistryValue` hits neither branch — rollback silently does nothing; if the key didn't exist, rollback removes only the value, leaving the newly created key behind. Fix: record value-existence (`$null -ne (Get-ItemProperty … -Name $n -EA SilentlyContinue)`), and on rollback remove the value when it didn't exist / restore it when it did.

### B10. `usoclient` fallback is a fiction of progress
`WindowsUpdates.psm1:166-182` — `usoclient StartScan/StartInstall` is undocumented, deprecated on recent builds (does nothing on many 22H2+/Win11 systems), its exit code is meaningless, yet the module sets `$processed = $diff.Count` and `RebootRequired = $true`. Report `ItemsProcessed 0` + `Warning` and don't force a reboot from a fire-and-forget trigger.

### B11. Launcher timestamp parsing is locale-dependent
`script.bat:19-25` — `%DATE%` on a Romanian locale (`18.07.2026`) yields `LOG_DATE=-07-2026` (token `%%d` is empty), so every launcher log line gets a malformed timestamp. Use one `powershell Get-Date -Format` call at startup, or `wmic os get localdatetime`.

Minor flow notes: the launcher's System-Protection section (script.bat:1052-1164) uses `Get-ComputerRestorePoint`/`Checkpoint-Computer`/`Enable-ComputerRestore` under **pwsh** — these resolve only through the WinPS-compat remoting layer (verified), which works but is slow and breaks if compat is disabled by policy; calling `powershell.exe` directly would be robust. Stage-2 pairs skipped via config get no visibility in the report about *why*. `Publish-MaintenanceReport` after Stage 5 abort is correctly skipped (files kept), fine.

---

## C. DEAD / UNUSED CODE AND CONFIG

| # | Item | Location | Evidence |
|---|---|---|---|
| C1 | `Compare-ListDiff` — the documented "diff engine" centerpiece | Maintenance.psm1:538 | Exported, **called by nothing** (grep across repo). Its `Changed` strategy also uses `.PSObject.Properties` on hashtables (bug A2 class) so it couldn't work anyway. |
| C2 | `Get-ExceptionCategory` | Maintenance.psm1:283 | Exported, never called. |
| C3 | `Test-UpdateAlreadyInstalled` | WindowsUpdates.psm1:14 | Never called (see A3 — its call site is misspelled). |
| C4 | `securityPolicy` + `auditPolicy` sections | security-baseline.json:19-130 | Claim "applied via secedit" — no `secedit`/`auditpol` code exists anywhere. Dead config. |
| C5 | `registryTweaks` / `uiOptimizations` sections | system-optimization-config.json | Self-labeled `"_status": "not-implemented"`. |
| C6 | `microsoft-store-bloatware.json` | config/lists/bloatware/ | Referenced by no code — moved to `archive/`. |
| C7 | `skipSystemHealth` flag | main-config.json:15 | Pair 6 has `ConfigSkip=''` and no Type2; the flag gates nothing. Wire it in Stage 1 or remove it. |
| C8 | `categories.drivers` / `categories.featureUpdates` | updates-config.json | Never read by the audit. |
| C9 | Duplicate launcher sections | script.bat:932-989 | Second winget verification + second scheduled-task management block repeat work done at lines 341-371/596-740 verbatim. |
| C10 | Unused launcher variables | script.bat | `WINGET_LOG` (767), `SCRIPT_LOG_FILE` (166/468 — orchestrator reads only `MAINTENANCE_LOG`), `IS_NETWORK_LOCATION`, `SR_STATUS`/`SR_VERIFY_STATUS`, and the parallel `RESTART_NEEDED`/`RESTART_SIGNALS` vs `RESTART_NEEDED_WU`/`RESTART_SIGNALS_WU` pairs maintained identically (only the `_WU` pair is consumed). |
| C11 | Legacy `script.ps1` probes | script.bat:476-478, 508-511 | The repo has never shipped `script.ps1`; both fallback branches are dead. |
| C12 | `Build-*` helper exports | ReportGenerator.psm1:850-857 | Only `New-MaintenanceReport` is consumed externally; exporting the five HTML builders just widens the surface. |

Also: **CLAUDE.md is out of date on its own claims** — it states the registry rollback pattern was "consolidated" (it is copy-pasted three times in SystemConfiguration.psm1:229-388) and that "all critical bugs [are] eliminated" (see section A). Worth a docs pass after the fixes land.

---

## D. OPTIMIZATION OPPORTUNITIES

1. **Per-app `winget list --id …` in the essential-apps audit** (SoftwareManagementAudit.psm1:304) — one winget invocation (~2-5 s each) per configured app, ~20 apps ⇒ minutes. Run **one** `winget list` (or reuse `Get-WingetUpgrade`'s parse) and match in memory.
2. **`Get-InstalledApp` runs 3× per full run** (bloatware audit, essential audit, inventory) — each is a full registry + AppX enumeration. Cache the result in a script/module-scoped variable for the session.
3. **`Remove-BloatwareLayered` re-queries all provisioned packages per item** (SoftwareManagement.psm1:50) — hoist `Get-AppxProvisionedPackageCompat` out of the loop (one call, filter in memory). Same for the AppX package list.
4. **DISM `/AnalyzeComponentStore` in the audit** (DiskCleanupAudit.psm1:163) — can take minutes and has no timeout (called with `&`, unlike the Type2 side which correctly uses `Invoke-ExternalPackageCommand -TimeoutSeconds 1800`). Route it through the same helper with a timeout.
5. **`$events += @{…}` accumulation** in `Get-CriticalErrorEvents` (SystemHealthAudit.psm1:91) — array `+=` is O(n²); with up to 3,000 events this is seconds of pure copying. Use `[List[object]]`.
6. **Registry backup/verify/rollback block is copy-pasted three times** (SystemConfiguration.psm1 security/telemetry/optimization registry cases are byte-identical) — extract one `Invoke-RegistryChangeWithRollback` helper (~90 lines saved, one place to fix B9).
7. **Restore-point/shadow-copy enumeration duplicated** in SystemInventory.psm1:180-191 and RestorePointAudit.psm1:29-39 (identical query + projection) — move to a core `Get-ShadowCopyInventory`.
8. **Double OS logging** — `Get-OSContext` logs "OS detected…" and the orchestrator immediately logs "OS: …" again; the menu/`Show-Stage1Menu` box art has drifted column widths (cosmetic).
9. **`Set-RegistryValue` comparison** (`$current -eq $Value`) is type-naive — a REG_SZ "1" vs int 1 compares unequal each run causing a rewrite (harmless but noisy); coerce both sides to string as `Compare-RegistryBaseline` already does.

---

## E. PRIORITIZED FIX LIST

| Priority | Fix | Files |
|---|---|---|
| 🔴 P0 | A2 — replace `.PSObject.Properties` with `.GetEnumerator()` (3 sites) | SoftwareManagementAudit.psm1 |
| 🔴 P0 | A1 — JSON-serialize across the `Invoke-AppxInWinPS` boundary; add `-Online` | Maintenance.psm1 |
| 🔴 P0 | A3 — rename call to `Test-UpdateAlreadyInstalled` | WindowsUpdates.psm1:114 |
| 🔴 P0 | A5 — return on successful COM scan; drop Event-19 layer; CBS ⇒ RebootRequired not pending | WindowsUpdatesAudit.psm1 |
| 🔴 P0 | A4 — remove `| default 'none'` | SoftwareManagement.psm1:115 |
| 🟠 P1 | B1, A6 — restore point pair: gate the `create`, rework removal (vssadmin by GUID) | RestorePoint*.psm1 |
| 🟠 P1 | B2 — per-user browser/temp path derivation | DiskCleanupAudit.psm1 |
| 🟠 P1 | B4 — `Set-Location` out before folder deletion | MaintenanceOrchestrator.ps1 |
| 🟠 P1 | B9 — value-level backup/rollback semantics | SystemConfiguration.psm1 |
| 🟡 P2 | B3 (GUID compare), B5 (purge stale diffs), B6 (Defender event IDs), B7/B8 (winget line names / uninstall strings), B10 (usoclient honesty), B11 (locale timestamps) | various |
| 🟢 P3 | Section C removals + Section D refactors | various |

---

## F. FILES MOVED TO `archive/`

Historical process documents and one-off dev artifacts — nothing in the runtime references them (verified by grep before moving):

- `xxx.md` (old analysis prompt notes)
- `PROJECT_ANALYSIS.md`, `PROJECT_AUDIT_REPORT.md` (previous analysis rounds; superseded by this document)
- `REFACTORING_PLAN.md`, `WAVE1_COMPLETE.md`, `SESSION_2_SUMMARY.md` (completed-work session logs)
- `BLOATWARE_REDESIGN.md`, `QUICK_START.md` (v7 bloatware redesign design docs)
- `test-bloatware-detection.ps1` (one-off dev test harness; validates config file shapes only)
- `config/lists/bloatware/microsoft-store-bloatware.json` (referenced by no code path)

Kept in place: `CLAUDE.md` (its `PROJECT_AUDIT_REPORT.md` link updated to the archive path), `PSScriptAnalyzerSettings.psd1`, all live configs including the legacy `bloatware-list.json` (still the coded fallback).

---

# G. FLOW ANALYSIS — what actually happens to the OS, in what order, and what should change

**End goal (as stated by the project):** on a possibly-fresh Win10/11 machine, bootstrap itself, audit the system, apply only the changes the audit justifies, leave one HTML report behind, clean up after itself, and reboot only when genuinely required.

## G.1 The run as it exists today (timeline with OS impact)

| # | Step | Where | Typical cost | OS impact | Verdict |
|---|---|---|---|---|---|
| 1 | Log init + admin check (NET SESSION **and** a spawned powershell.exe) | script.bat 131-203 | ~2 s | none | Redundant double-check — NET SESSION alone suffices |
| 2 | Pending-WU-reboot detection via **PSWindowsUpdate** then registry | 234-282 | 2-15 s | none | **Wrong order**: PSWindowsUpdate is installed at step 10 — on a fresh machine (the design target!) this check always fails and falls to registry anyway. The registry markers are the ones the script itself calls "authoritative". Drop the PSWindowsUpdate probe |
| 3 | Possible ONLOGON task + **reboot #1** | 299-325 | reboot | scheduled task + restart | Correct and necessary |
| 4 | Monthly scheduled task creation (`/RU SYSTEM`) | 341-371 | 1 s | permanent scheduled task | Needed, but the task runs `script.bat` **with no `-NonInteractive` arg** — a SYSTEM session then burns the 10 s menu countdown and the full 120 s Stage-5 countdown with nobody watching, and winget is unreliable under SYSTEM |
| 5 | **Repo download + extraction — every run, unconditionally** | 400-491 | 10-40 s + network | writes whole repo next to script.bat | Biggest fixed cost of every run; no version check (see G.3-1). Extraction target is the *launch folder* — on this machine that is **OneDrive Desktop**, so OneDrive immediately starts syncing the extracted tree, logs, and reports, and later fights the Stage-5 delete with sync locks (see G.3-2) |
| 6 | Structure validation (~25 IF EXIST probes + log lines) | 496-585 | <1 s | none | Fine, verbose |
| 7 | Winget verify/install (3 methods) | 596-740 | 0-60 s | may install App Installer | Needed on fresh machines |
| 8 | **Hard-coded 5-second countdown** before checking PS7 | 747-751 | 5 s | none | **Pure waste** — sleeps for nothing |
| 9 | `:FIND_PWSH` (spawns PS5.1, which test-**executes** every pwsh candidate) | 758 | 3-8 s | none | Necessary once |
| 10 | PS7 install if missing; PSWindowsUpdate install | 764-924 | 0-3 min | installs software | Needed |
| 11 | Defender exclusions: working dir **+ process-wide `powershell.exe` and `pwsh.exe`** | 929-930 | 1 s | **All PowerShell on the machine unscanned by AV** for the run — and **forever** if Stage-5 cleanup doesn't run (user aborts reboot: exclusions are NOT removed on that path) | Overbroad + leak on abort path (G.3-3) |
| 12 | **Second** winget verification + **second** scheduled-task pass | 932-989 | 2-4 s | none | Duplicates of steps 4/7 — delete |
| 13 | `:FIND_PWSH` **again** for PS_EXECUTABLE (and a 3rd time in the retry branch) | 1003-1012 | 3-8 s | none | Cache the step-9 result |
| 14 | System Protection: vssadmin sizing, Enable-ComputerRestore, **restore point #1** | 1052-1164 | 30-120 s | VSS storage resize + restore point | Runs via slow WinPS-compat remoting; **created even when the run will change nothing** (see G.2-1) |
| 15 | Launch orchestrator (`-NoExit`, `Set-Location` into extracted dir); launcher exits | 1203-1242 | — | — | `-NoExit` + CWD-in-project cause the Stage-5 delete failure (B4) |
| 16 | **Stage 1** — 7 audits, sequential | orchestrator | see G.2-2 | read-only | The two multi-minute offenders: per-app `winget list --id` (~minutes) and DISM `/AnalyzeComponentStore` (minutes, no timeout) |
| 17 | **Stage 2** — diff gate | | <1 s | none | Sound; needs stale-diff purge (B5) |
| 18 | **Stage 3** — Type2 in `$ModulePairs` order: Software → SysConfig → DiskCleanup → WindowsUpdates → RestorePoint | | minutes-hours | the actual changes | **Order is wrong** — see G.2-3 |
| 19 | **Stage 4** — report + deferred script.bat self-update | | seconds | overwrites launcher | Correct placement (launcher has exited) |
| 20 | **Stage 5** — 120 s countdown → remove exclusions → delete folder → **reboot #2** | | 2+ min | reboot, folder delete | Countdown runs even in `-NonInteractive` (nobody can press a key); delete fails on CWD (B4) and will also fight OneDrive |

## G.2 Ordering faults (things that execute in the wrong sequence)

**G.2-1. The safety restore point is disconnected from the changes it protects.**
Today: the *launcher* creates a restore point on **every** run — before it even knows whether anything will change — and the RestorePoint *module* queues a **second** `create` that runs **last** in Stage 3, i.e. *after* all system modifications are already applied (and is usually swallowed by Windows' 24 h restore-point throttle anyway). Both placements are wrong.
**Target:** create exactly **one** restore point, in the orchestrator, at the *entry of Stage 3, only when `$actionNeeded.Count -gt 0`*. Remove creation from the launcher and from the RestorePoint pair (keep the pair for consolidation only). A no-change run then touches VSS not at all — currently the "audit says nothing to do" run still costs a restore point, VSS resize, and two reboo… countdowns.

**G.2-2. Stage 1 audit order should be "diff-producers first, report-only last".**
Current menu order runs report-only modules (5 Inventory, 6 Health) *before* the RestorePoint audit (7). Reorder to 1-4, 7 (actionable) then 5, 6 (report-only): if the circuit-breaker trips or the user is watching, the decisions that gate Stage 3 are already made, and the report-only work is the part that gets sacrificed.

**G.2-3. Stage 3 order works against itself.**
Current: Software → SystemConfig → **DiskCleanup → WindowsUpdates** → RestorePoint.
- DiskCleanup (incl. DISM `/StartComponentCleanup`, up to 30 min) runs **before** WindowsUpdates installs updates — which immediately re-dirties the component store, temp folders, and the WU download cache. The clean-up is partially undone minutes later.
- SoftwareManagement's winget installs/upgrades also litter `%TEMP%` and installer caches *after* their sizes were audited.
**Target order:** *(restore point)* → **SystemConfiguration** (hardening first, incl. Defender back on) → **SoftwareManagement** → **WindowsUpdates** → **RestorePoint consolidation** → **DiskCleanup last** (sweeps up everything the run itself produced). This is a 5-line change — reorder `$ModulePairs` / iterate `$actionNeeded` in an explicit order — and makes the machine end its run genuinely clean.

**G.2-4. The reboot decision executes before the information it needs is trustworthy.**
`rebootOnlyWhenRequired` is a good gate, but it consumes `RebootRequired` flags that today are polluted upstream: WU audit phantom-pendings (A5) → usoclient fallback force-sets `RebootRequired` (A3/B10). Flow-wise the gate is in the right *place*; fixing A3/A5/B10 is what makes it *mean* something. Until then the practical behavior is "reboot almost every run", which defeats the config option.

**G.2-5. Countdown logic runs where no human exists.**
Stage-5's 120 s countdown (and Stage-1's 10 s menu) execute in `-NonInteractive`/scheduled runs where key-polling is deliberately disabled — 130 s of guaranteed dead time at 01:00 under SYSTEM. When `$NonInteractive`, skip both countdowns outright (log the decision instead). Also pass `-NonInteractive` in the monthly task's `/TR` so scheduled runs actually take that path.

## G.3 Actions that aren't needed (or need to move) — beyond ordering

1. **Unconditional repo re-download.** Store the downloaded zip's `ETag`/`Last-Modified` (or the commit SHA from the GitHub API) next to script.bat; skip download+extract when unchanged and the previous extraction still validates. Saves 10-40 s + bandwidth on every scheduled run, and removes the hard internet dependency for repeat runs.
2. **Extraction into the launch folder.** Extract to `%ProgramData%\WindowsMaintenance\` (or `%LOCALAPPDATA%`) instead of next to script.bat. This (a) takes OneDrive/Desktop sync out of the loop — no sync churn, no locked-file fights during Stage-5 deletion, (b) keeps USB-stick launches working (`ORIGINAL_SCRIPT_DIR` already handles the report copy-back), (c) makes the Stage-5 delete target unambiguous.
3. **Process-wide Defender exclusions.** Drop `powershell.exe`/`pwsh.exe` process exclusions entirely (the folder exclusion covers the actual need), and move exclusion removal into the orchestrator's `finally` block so *every* exit path — including "user aborted reboot" and crashes — restores AV coverage. Today an aborted run leaves all PowerShell on the machine permanently excluded from Defender.
4. **The 5-second pre-PS7 countdown, the duplicate winget/task sections, the second and third `:FIND_PWSH`, the PSWindowsUpdate-based reboot probe, the powershell-spawning admin check** — ~20-30 s of pure overhead per run, all deletable with no behavior change.
5. **Per-app `winget list --id` probes in the essential-apps audit** (Section D1) — the single biggest Stage-1 cost after DISM; one `winget list` parse replaces ~20 winget launches.
6. **External-IP web call in SystemInventory** — network dependency + writes the machine's public IP into a report that gets copied around; make it opt-in via config.
7. **DISM `/AnalyzeComponentStore` on every audit** — cache the answer (it changes only when updates/servicing occur) or at least gate it to runs where the WindowsUpdates diff is non-empty, and give it a timeout like its Stage-3 counterpart.
8. **Sysmon installation inside "maintenance".** Installing a permanent kernel-level monitoring service (plus its event volume) is a policy decision, not a maintenance action — it's also the only Stage-3 action that *adds* a persistent workload to the OS. Keep it, but it deserves its own skip-flag surfaced in `main-config.json` documentation so an operator consciously opts in. *(It currently rides `skipSystemConfiguration`, all-or-nothing with security hardening.)*

## G.4 Target flow (one page)

```
script.bat (elevated)
  ├─ admin gate (NET SESSION only)
  ├─ WU reboot markers (registry only) ──► reboot #1 + ONLOGON task if pending
  ├─ ensure monthly task (with -NonInteractive in /TR)
  ├─ download repo IF changed ──► extract to %ProgramData%\WindowsMaintenance
  ├─ ensure winget ─ ensure PS7 (ONE FIND_PWSH, cached) ─ ensure PSWindowsUpdate
  ├─ Defender FOLDER exclusion only
  └─ START pwsh (no -NoExit) MaintenanceOrchestrator.ps1   [launcher exits]

orchestrator
  ├─ purge temp_files\diff\*                      (kills stale-diff hazard B5)
  ├─ STAGE 1  audits: 1..4, 7 (diff-producing) → 5, 6 (report-only)
  ├─ STAGE 2  diff gate (skip pairs whose audit Failed)
  ├─ STAGE 3  only if work queued:
  │     create ONE restore point                  (was: launcher + module #7)
  │     SystemConfiguration → SoftwareManagement → WindowsUpdates
  │     → RestorePoint consolidation → DiskCleanup (last, sweeps the run's own mess)
  ├─ STAGE 4  report + deferred script.bat self-update
  └─ STAGE 5  countdown ONLY if interactive; reboot only if RebootRequired;
        finally { remove Defender exclusions; Set-Location out; delete folder }
```

**Net effect:** a no-change run drops from ~5-10 min (download, restore point, DISM analyze, winget probes, 130 s of countdowns) to ~1-2 min with zero writes to the OS; a full run ends with the cleanup actually cleaning the run's own residue; AV coverage is never left degraded; and the reboot gate only fires on real reboot conditions once A3/A5 are fixed.

---

# H. FLOW ADJUSTMENTS IMPLEMENTED (2026-07-18, same session)

The following ordering/flow changes from Section G were implemented in `script.bat` and `MaintenanceOrchestrator.ps1`, per direct request. None of the Section A-F bugs were touched in this pass — those remain open.

| # | Change | File | Detail |
|---|---|---|---|
| H1 | Dropped the PSWindowsUpdate-based pending-reboot probe | script.bat ~226-240 | Registry markers (`WU-AutoUpdate-RebootRequired`, `WU-Orchestrator-RebootRequired`, `WU-Orchestrator-PostRebootReporting`) are now the sole detection path, matching G row 2 — the probe always failed on a fresh machine anyway since PSWindowsUpdate isn't installed until Dependency Management, later in the same run. |
| H2 | Removed the hard-coded 5-second pre-PS7-check countdown | script.bat ~745 | Pure sleep, no functional purpose (G row 8). |
| H3 | Removed the duplicated winget/Chocolatey re-verification + duplicated scheduled-task status block | script.bat ~930-989 | Both were exact repeats of checks already performed earlier in the same run (G row 12 / C9). |
| H4 | `:FIND_PWSH` result is now reused instead of re-probed a third time | script.bat ~991-1005 | `PS_EXECUTABLE` selection now trusts the `PWSH_PATH` already resolved by the initial check or the post-install verification, only re-probing (with a `REFRESH_TOOL_PATHS` retry) if it's genuinely still unset (G row 13). |
| H5 | Restore point creation gated on the age of the most recent existing restore point | script.bat ~1069-1090 | Queries `Get-ComputerRestorePoint`, skips `Checkpoint-Computer` if the latest is < 96h old (configurable via `MIN_RESTORE_AGE_HOURS`); creates one if none exist, the query fails, or the latest is stale. Supersedes the earlier recommendation (G.2-1) to move creation into Stage 3 only — the user's chosen design keeps it in the launcher but makes it age-aware instead of unconditional. |
| H6 | Repo extraction relocated from the launch folder to `%ProgramData%\WindowsMaintenance` | script.bat ~168-180, ~403-439 | `EXTRACT_ROOT` is now a stable per-machine path; `ZIP_FILE`/`EXTRACTED_PATH`/`WORKING_DIR` all derive from it. Takes OneDrive/Desktop sync out of the loop (no sync-lock fights on Stage-5 delete) while `ORIGINAL_SCRIPT_DIR` still points at the actual launch folder, so the report copy-back and USB-stick launches are unaffected (G item 2). |
| H7 | Stage 1 audit/menu order changed to actionable-first | MaintenanceOrchestrator.ps1 `$ModulePairs` | Array order is now 1 (Software), 2 (SystemConfig), 3 (DiskCleanup), 4 (WindowsUpdates), 7 (RestorePoint), 5 (Inventory), 6 (Health) — `Num` values unchanged, so `-TaskNumbers`/menu selection is unaffected (G.2-2). |
| H8 | Stage 3 execution order changed to SystemConfiguration → SoftwareManagement → WindowsUpdates → RestorePoint → DiskCleanup | MaintenanceOrchestrator.ps1, start of Stage 3 region | `$actionNeeded` is explicitly re-sorted by a `$Stage3Order` priority list right before the Stage 3 loop, independent of Stage 1/2 order — DiskCleanup now runs last so it sweeps up the temp/cache/component-store residue produced by the other Type2 actions instead of running before them (G.2-3). |
| H9 | Stage 5 reordered to: remove Defender exclusions → countdown (abort point) → delete project folder → reboot | MaintenanceOrchestrator.ps1, Stage 5 region | `Remove-DefenderSessionExclusions` now runs once, unconditionally, immediately on Stage 5 entry — before the countdown — instead of being duplicated inside each of the two post-countdown cleanup branches. Side effect (not separately requested, but a direct consequence of the reorder): an **aborted** reboot no longer leaves the machine's PowerShell permanently excluded from Defender, since exclusion removal no longer depends on which branch executes after the countdown. Also added a `Set-Location` out of `$ProjectRoot` immediately before both `Remove-Item $ProjectRoot` calls, since Windows refuses to delete a directory that is a live process's current working directory (bug B4) — without it, "delete Repo folder" would not reliably happen as its own step. |

**Not changed in this pass** (still open, tracked in Sections A-F): the A1/A2 bloatware-detection bugs, A3 WU-install misspelling, A5 phantom-pending-updates audit, A4 `default` crash, A6 restore-point-removal path bug, B2 per-user path duplication, B3 localized power-plan comparison, B6 Defender-incident overcounting, B9 registry rollback semantics, and the Section D performance items (per-app winget probes, DISM timeout, etc.). The reboot-gate now fires in the right *place* (H9) but still isn't fully *trustworthy* until A3/A5/B10 are fixed — WindowsUpdates can still force `RebootRequired=$true` via the usoclient fallback on a healthy machine.
