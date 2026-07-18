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
