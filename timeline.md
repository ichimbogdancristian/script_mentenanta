# Current Execution Timeline

**What this is:** the exact, as-coded sequence of everything that runs, in order, from double-clicking `script.bat` to the process ending — every stage, every task, every subtask. Extracted directly from the current source (`script.bat`, `MaintenanceOrchestrator.ps1`, all 15 `modules/type1|type2/*.psm1` files), not from design intent. File:line citations throughout so any step can be verified against the code. Branch points and early-exit paths are called out explicitly.

For a companion proposal on how this could be restructured for speed and clarity, see [`newtimeline.md`](newtimeline.md). For known bugs in the steps below, see [`docs/Comprehensive-Project-Analysis-2026-07-15.md`](docs/Comprehensive-Project-Analysis-2026-07-15.md).

---

## PART A — `script.bat` (the launcher)

Everything in Part A runs as a Windows batch process, before any PowerShell orchestrator code exists.

### A1. Bootstrap & self-discovery (`script.bat:10-136`)
1. Enable delayed variable expansion; jump past subroutine definitions to `:MAIN_SCRIPT` (`:10-16`)
2. Log launcher start, `%USERNAME%@%COMPUTERNAME%` (`:57-63`)
3. Resolve `SCRIPT_PATH` / `SCRIPT_DIR` / `SCRIPT_NAME` / `WORKING_DIR` / `ORIGINAL_SCRIPT_DIR` (`:66-73`)
4. Resolve `SCHEDULED_TASK_SCRIPT_PATH` (3-way fallback) (`:76-88`)
5. Detect UNC/network location (`:91-97`)
6. Create bootstrap log at `%TEMP%\maintenance_bootstrap_*.log`, write banner (`:103-125`)
7. Export env vars for the eventual PowerShell process: `WORKING_DIRECTORY`, `SCRIPT_LOG_FILE`, `REPO_URL`, `ZIP_FILE`, `EXTRACT_FOLDER` (`:128-134`)

### A2. Administrator check + UAC elevation (`script.bat:141-166`)
1. Check admin via `NET SESSION` **and** PowerShell `WindowsPrincipal.IsInRole` (`:144-147`)
2. **If not admin:** relaunch via `Start-Process cmd -Verb RunAs` — **only the script path is forwarded, not `%*`** — then `exit` the non-elevated instance (`:157,163`). The elevated child restarts this entire sequence from A1.
3. **If admin:** continue.

### A3. Startup-task cleanup + pending-reboot pre-check (`script.bat:171-302`)
1. Delete any leftover `WindowsMaintenanceStartup` scheduled task (`:171-184`)
2. Check 4 signals for a pre-existing pending reboot, in order: PSWindowsUpdate `Get-WURebootStatus` → `WindowsUpdate\Auto Update\RebootRequired` → `WindowsUpdate\Orchestrator\RebootRequired` → `...\PostRebootReporting` (`:197-245`)
3. **If reboot needed:** create an ONLOGON resume task, `shutdown /r /t 5`, **`EXIT /B 0`** — script terminates, machine reboots, resumes here on next logon (`:262-284`). *(This is deliberate: the orchestrator needs a clean slate — a machine with an already-pending Windows Update reboot is not a trustworthy starting point for an audit. This check only fires on a genuine pending-reboot signal, not unconditionally, and is a separate, valid reboot decision from Stage 5's "did this run's own changes require a reboot" — not a duplicate of it.)*
4. **If reboot not needed / task creation failed:** continue; clean up any stray `restart_flag.tmp` from a prior PS7-install self-restart (`:290-302`)

### A4. Monthly scheduled-task registration (`script.bat:304-334`)
1. If `WindowsMaintenanceAutomation` task exists, log its schedule; else create it (`/SC MONTHLY /MO 1 /D 20 /ST 01:00 /RL HIGHEST /RU SYSTEM`) (`:308-333`)

### A5. System requirements check (`script.bat:339-358`)
1. Detect OS version + PowerShell major version (`:343-349`)
2. **If PS major < 5:** log error, pause, **`EXIT /B 2`** (`:351-356`)

### A6. Repository download & extraction (`script.bat:363-459`)
1. Delete any stale zip/extract folder (`:367-368`)
2. `Invoke-WebRequest` download → **exit 3 on failure** (`:372-378`)
3. `ZipFile::ExtractToDirectory` → **exit 3 on failure** (`:390-396`)
4. Verify extracted folder exists → **exit 3 if not** (`:452-456`)
5. Self-update: back up and overwrite the on-disk `script.bat` with the freshly-extracted copy (`:404-425`)
6. Repoint `WORKING_DIR`, `SCRIPT_LOG_FILE`, resolve `ORCHESTRATOR_PATH` (prefers `MaintenanceOrchestrator.ps1`, legacy fallback `script.ps1`, else **exit 3**) (`:428-451`)
7. Delete the downloaded zip (`:459`)

### A7. Project structure validation (`script.bat:464-553`)
1. Re-check orchestrator file, `config/` (+ `main-config.json`, `config\lists\bloatware\bloatware-list.json`), `modules/` (+ `core`/`type1`/`type2`) — WARN per missing piece (`:472-543`)
2. **If any major component missing:** log error, pause, **`EXIT /B 4`** (`:547-550`)

### A8. Dependency management (`script.bat:558-928`)
1. **Winget** — check PATH, then `LocalAppData\...\winget.exe`; if missing, try in order until one works: (a) register the AppX package, (b) PowerShell-Gallery `Repair-WinGetPackageManager`, (c) manual MSIX download with 3-tier URL fallback (`:564-705`)
2. **PowerShell 7** — check PATH → `Program Files` → WindowsApps alias; if missing, try in order until one works: (a) `winget install Microsoft.PowerShell`, (b) Chocolatey (installing Chocolatey itself first if absent), (c) MSI download from GitHub Releases. **On success:** write `restart_flag.tmp`, then `START /WAIT` a fresh child copy of `script.bat` with the same args, and exit once the child finishes (`:710-872`) — i.e. the entire launcher sequence (A1-A8) runs a second time inside that child process.
3. **PSWindowsUpdate module** — install via NuGet provider + trusted PSGallery if missing (`:877-889`)
4. **Windows Defender exclusions** — add permanent, unscoped `-ExclusionPath` for the working dir and `-ExclusionProcess` for `powershell.exe`/`pwsh.exe`. **Nothing ever removes these** (`:894-895`)
5. Re-verify and log winget/Chocolatey versions (`:898-927`)

### A9. Scheduled-task recap + startup-task cleanup (`script.bat:933-954`)
1. Re-query monthly task for logging; delete any leftover resume task (`:939-954`)

### A10. Locate the PowerShell 7 executable for launch (`script.bat:959-1205`)
1. Primary path check (`Program Files\PowerShell\7\pwsh.exe`), then up to 5 cascading fallbacks (PATH, candidate path array, `where`, registry `InstallLocation`, manual PATH enumeration) (`:965-1167`)
2. **If still not found:** log critical error, pause, **`EXIT /B 1`** (`:1170-1205`)

### A11. System Restore Point creation (`script.bat:1211-1325`)
1. Check System Protection availability (`:1219`)
2. **If available:** check/resize shadow storage to ≥10GB if needed (`:1226-1261`), `Enable-ComputerRestore` (`:1268-1279`), `Checkpoint-Computer -RestorePointType MODIFY_SETTINGS`, verify it was created (`:1289-1315`)
3. **If not available or check fails:** skip, log, continue — does not exit (`:1281-1287`)
4. This runs **unconditionally**, even if the eventual audit finds nothing to change.

### A12. Launch the orchestrator (`script.bat:1330-1422`)
1. Validate `ORCHESTRATOR_PATH` exists → else **exit 4** (`:1336-1349`)
2. Build `PS_ARGS` (`-NonInteractive` if passed or auto-detected as non-interactive; `-TaskNumbers` forwarding is computed here but **discarded — never reaches the actual launch command**) (`:1358-1366`)
3. **If PS7 detected as v7+:** build a `pwsh.exe -Command "& { ...; & '<orchestrator>' [-NonInteractive]; ... }"` string, clear the bootstrap `LOG_FILE` var, `START` a **new detached console window** running it, then **`EXIT /B 0`** immediately — the batch process does not wait for the orchestrator (`:1375-1411`)
4. **Else:** log critical error, pause, **`EXIT /B 1`** (`:1412-1422`)

**End of Part A.** `script.bat` has no further involvement in the run from this point forward — everything below happens in the separate, detached `pwsh.exe` process it spawned.

---

## PART B — `MaintenanceOrchestrator.ps1`

### B1. Script-level init (`MaintenanceOrchestrator.ps1:1-104`)
1. `#Requires -Version 7.0 -RunAsAdministrator` — hard stop before any code runs if unmet (`:1-2`)
2. `Set-StrictMode -Version 1.0`, UTF8 console encoding (`:32-34`)
3. Resolve `$ProjectRoot`, `$TempDir`, `$TranscriptPath`; create `temp_files/{logs,data,reports,diff}` (`:38-48`)
4. `Start-Transcript -Append -Force` (`:55`)
5. If `$env:BOOTSTRAP_LOG` exists: inject its contents into the transcript, delete it (`:58-69`) — this is how the launcher's log becomes part of the final report
6. Import `modules\core\Maintenance.psm1` → **exit 1 on failure** (`:85-90`)
7. `Initialize-Maintenance`, `$global:OSContext = Get-OSContext`, `$Config = Get-MainConfig` (`:93-100`)

### B2. Module-pair registry (`MaintenanceOrchestrator.ps1:110-191`) — fixed order, 8 pairs

| # | Pair | Type1 (audit) | Type2 (action) |
|---|---|---|---|
| 1 | Bloatware | `Invoke-BloatwareAudit` | `Invoke-BloatwareRemoval` |
| 2 | Essential Apps | `Invoke-EssentialAppsAudit` | `Invoke-EssentialApp` |
| 3 | Security | `Invoke-SecurityAudit` | `Invoke-SecurityEnhancement` |
| 4 | Telemetry | `Invoke-TelemetryAudit` | `Invoke-TelemetryDisable` |
| 5 | System Optimization | `Invoke-SystemOptimizationAudit` | `Invoke-SystemOptimization` |
| 6 | Windows Updates | `Invoke-WindowsUpdatesAudit` | `Invoke-WindowsUpdate` |
| 7 | App Upgrades | `Invoke-AppUpgradeAudit` | `Invoke-AppUpgrade` |
| 8 | System Inventory | `Invoke-SystemInventory` | *(none — audit only)* |

### B3. Stage 1 — Audit (`:241-359`)
1. **If interactive:** show menu (0=all + 8 module choices), 10s countdown, defaults to "all" on timeout (`:243-311`)
2. `foreach` module pair **in table order** (filtered to selection if one was made):
   - Run its Type1 function; normalize result to a `ModuleResult` (`:319-341`)
   - **Circuit breaker:** 3 consecutive `Failed` results → log, **`break`** the loop early, remaining modules never audited this run (`:344-350`)
3. See **Module Detail — Type1** below for what each function does internally.

### B4. Stage 2 — Diff (`:361-396`)
1. `foreach` module pair from the same (possibly truncated) set, in the same order:
   - Skip pair 8 (no Type2) (`:370`)
   - Skip if config disables this module (`:372-376`)
   - `Get-DiffList`; **if non-empty** → queue for Stage 3; **if empty** → log "Skipped", record a `Skipped` result directly (`:378-391`)

### B5. Stage 3 — Act (`:398-439`)
1. **If nothing queued:** log "already in desired state", run nothing (`:404-407`)
2. **Else** `foreach` queued pair, in queue order (a subset of table order, modules 1-7 only):
   - Run its Type2 function with `@{ OSContext = $global:OSContext }`; normalize result (`:409-433`)
   - No circuit breaker here — a systemic failure runs through every remaining module uncontested.
3. See **Module Detail — Type2** below for what each function does internally.

### B6. Stage 4 — Report (`:441-482`)
1. `Stop-Transcript` (flush log for embedding) (`:449`)
2. Import `ReportGenerator.psm1`, call `New-MaintenanceReport` (`:451-464`)
3. Copy the report to `$env:ORIGINAL_SCRIPT_DIR` (falls back to `$ProjectRoot` if unset) (`:468-473`)
4. `Start-Transcript -Append -Force` — resume logging for Stage 5 (`:480`)

### B7. Stage 5 — Cleanup & reboot (`:484-605`)
1. Read config: `$rebootSeconds` (120), `$doReboot`, `$doCleanup`, `$rebootOnlyWhenRequired` (`:492-496`)
2. **If `rebootOnlyWhenRequired`:** scan `$SessionResults` for any `RebootRequired` flag; if none, force `$doReboot = $false` (`:500-512`)
3. **Branch — no reboot needed:** print summary; **if cleanup enabled:** `Stop-Transcript`, `Remove-Item -Recurse -Force $ProjectRoot` (deletes the entire project folder, including the just-written report if it landed under `$ProjectRoot`); **`exit 0`** (`:515-538`)
4. **Branch — reboot needed:** print countdown warning; 120s loop watching for a keypress to abort (`:541-564`)
   - **If aborted:** log it, **`exit 0`** — no cleanup, no reboot (`:568-575`)
   - **If countdown completes:** cleanup (same as above) → `Restart-Computer -Force` → `exit 0`/`exit 1` depending on whether the restart call itself threw (`:579-603`)

---

## Module Detail — Type1 (Stage 1, run in this exact order, strictly sequential)

What each audit actually checks against, by name and count — not just "loads a baseline."

### 1. BloatwareDetectionAudit
Loads `bloatware-list.json`: **236 name patterns** in `common` (e.g. `Microsoft.MicrosoftSolitaireCollection`, `king.com.CandyCrushSaga`, `SpotifyAB.SpotifyMusic`, `Facebook.Facebook`, `TikTok.TikTok`, `Dell.SupportAssist`, `AD2F1837.HPJumpStart`), **0** in `windows10`, **9** in `windows11` (e.g. `MicrosoftTeams`, `Clipchamp.Clipchamp`, `Microsoft.YourPhone`, `Microsoft.GamingServices`) — 3 of the win11-only entries (`Microsoft.Todos`, `Microsoft.PowerAutomateDesktop`, `Microsoft.GetHelp`) already duplicate `common`, so the real distinct total is ~242, not 245. Enumerates installed AppX packages (`Get-AppxPackageCompat`, no `-AllUsers`) and matches by name; separately enumerates registry `Uninstall` key `DisplayName` values and substring-matches the same patterns (largely ineffective — see known-bugs doc). **Heaviest step:** AppX enumeration.

### 2. EssentialAppsAudit
Loads `essential-apps.json`: **12 target apps** — PowerShell 7, Windows Terminal, Java Runtime Environment, 7-Zip, WinRAR, Total Commander, LibreOffice (skipped if MS Office detected), Adobe Acrobat Reader, PDF24 Creator, Notepad++, Google Chrome, Mozilla Firefox — each checked by fast local name-match first, then **one `winget list --id --exact` spawn per still-missing app** (up to 12 serial spawns on a bare machine). **Heaviest step:** N serial winget.exe spawns.

### 3. SecurityAudit
Loads `security-baseline.json` (2149 lines, CIS Windows 10 Enterprise Benchmark v4.0.0) and checks, in order:
- **247 registry policy entries** (e.g. `EnableLUA=1` for UAC, `LmCompatibilityLevel=5` for NTLMv2-only, `HypervisorEnforcedCodeIntegrity=1`, ~20 BitLocker/FVE values, an ASR rule GUID blocking Office child-process spawning, per-firewall-profile logging paths, the legal logon banner text)
- **6 Windows Defender preference flags** via `Get-MpComputerStatus`/`Get-MpPreference` (realTimeProtection, cloudProtection, networkProtection, PUA, controlledFolderAccess, automaticSampleSubmission)
- **3 firewall profiles** (Domain/Private/Public) via `Get-NetFirewallProfile`
- **27 services** — 3 that must be running (`WinDefend`, `MpsSvc`, `EventLog`) and 24 that must be disabled (`RemoteRegistry`, `Telnet`, `Spooler`, `TermService`, `WinRM`, `SSDPSRV`, etc.)
- **8 secedit policy fields** via a `secedit /export` spawn, parse, compare (`MinimumPasswordLength=14`, `LockoutBadCount=5`, `NewAdministratorName="CISAdmin"`, etc.)
- **17 auditpol subcategories** via an `auditpol /get /category:*` spawn, parse, compare (`Credential Validation`, `Process Creation`, `Removable Storage`, etc.)

**Heaviest step:** secedit + auditpol spawns (full-category text parsing).

### 4. TelemetryAudit
Loads `telemetry-list.json`: **9 services** to disable (`DiagTrack`, `dmwappushservice`, `PcaSvc`, `WerSvc`, `WMPNetworkSvc`, `MapsBroker`, `lfsvc`, `NetTcpPortSharing`, `Fax`), **8 registry entries** across telemetry/advertising/cortana/privacy groups (`AllowTelemetry=0`, `AllowCortana=0`, `TailoredExperiencesWithDiagnosticDataEnabled=0`, etc.), **8 scheduled tasks** (Application Experience appraiser/updater, CEIP consolidator, disk diagnostic collector, feedback DmClient ×2). **Heaviest step:** none — all fast local reads (fastest audit module in the suite).

### 5. SystemOptimizationAudit
Loads `system-optimization-config.json`: **7 services** to disable (common: `RetailDemo`, `XblAuthManager`, `XblGameSave`, `XboxGipSvc`, `XboxNetApiSvc`; +2 Windows-11-only: `WidgetService`, `DevHomeService`), current power plan via a **`powercfg /getactivescheme` spawn** (+ `/list` if it doesn't match "High Performance"), startup-program `Run`-key registry scan against glob patterns (`safeToDisablePatterns`: `*Updater*`, `*Google*Update*`, `*Java*Update*`; `neverDisable`: `*Security*`, `*Defender*`, `*VPN*`), a single `VisualFXSetting` registry read, and 3 Spotlight-related registry reads for the desktop-background check. **Heaviest step:** powercfg spawns.

### 6. WindowsUpdatesAudit
Loads `updates-config.json`: only **3 of 6 possible categories enabled** (`security`, `critical`, `important` — `optional`, `drivers`, `featureUpdates` are off), **3 exclude patterns** (`*Preview*`, `*Insider*`, `*Beta*`). Runs a **COM `Microsoft.Update.Session` search** (`IsInstalled=0 and IsHidden=0`) against Microsoft's live update catalog for this machine. **Heaviest step:** the COM search — "typically the heaviest call in the whole audit suite, can take seconds to minutes."

### 7. AppUpgradeAudit
Loads `app-upgrade-config.json`: **22 exclude patterns** exempted from auto-upgrade (`Visual Studio*`, `Microsoft SQL Server*`, `Docker*`, `Python*`, `Git*`, `.NET Core*`, `Microsoft Office*`, `Adobe*`, `JetBrains*`, `Android Studio*`, etc.) — deliberately excludes anything a developer would want to version-pin by hand. Runs `Get-WingetUpgrade` (one winget spawn enumerating all upgradeable packages) and a **`choco outdated` spawn**. **Heaviest step:** winget/choco spawns.

### 8. SystemInventory
Pure `Get-CimInstance` reads — OS caption/version/build, CPU name/cores, total RAM, per-disk size/free/filesystem, network adapter IPs/MACs — plus an installed-app count via `Get-InstalledApp`. No baseline, no diff concept, no Type2 pair; saves an empty diff and a descriptive data snapshot only. **Heaviest step:** `Get-InstalledApp` (registry+AppX enumeration).

---

## Module Detail — Type2 (Stage 3, run only for pairs with a non-empty diff, in the same relative order)

What each action module actually installs, removes, or changes on the OS — concrete mechanism and named examples, not category labels.

### 1. BloatwareRemoval
For each matched package from the ~242 distinct bloatware patterns: `Get-AppxPackageCompat -AllUsers` → `Remove-AppxPackageCompat` (removes it for every user profile on the machine), then `Remove-AppxProvisionedPackageCompat` against the online Windows image so the package doesn't silently reinstall for any *new* user profile created later. If AppX removal found no match but the item carries a winget ID, falls back to `winget uninstall --id <id> --silent`. **Heaviest step:** per-item winget.exe spawn (fallback path only).

### 2. EssentialApps
Runs `winget source update --disable-interactivity` once, then for each of the up to 12 missing apps: OS-exclusion check, then `winget install --id <PackageId> --silent --accept-package-agreements --accept-source-agreements [--scope machine|user]` (e.g. `Microsoft.Powershell`, `7zip.7zip`, `Google.Chrome`, `Mozilla.Firefox`), falling back to `choco install <id> --yes --no-progress` if winget fails or is absent. Two apps carry non-default timeouts: LibreOffice (900s) and Adobe Acrobat Reader (600s). **Heaviest step:** per-app winget install (real download + install, not a query).

### 3. SecurityEnhancement — the widest-reaching Type2 module
Dispatches each diff item by `Type`, against up to 6 different OS mechanisms in one module:
- **`registry`** (up to 247 possible entries): `Set-RegistryValue` — e.g. forces `EnableLUA=1`, `LmCompatibilityLevel=5`, writes ~20 BitLocker policy values, sets the ASR rule GUID, per-firewall-profile logging paths.
- **`defender`**: `Set-MpPreference` calls for real-time protection, cloud protection (MAPS reporting level 2 = Advanced), network protection, PUA protection; the `AntivirusEnabled` case additionally clears the `DisableAntiSpyware` registry policy and force-starts the `WinDefend` service, **setting `RebootRequired=true`**.
- **`firewall`**: `Set-NetFirewallProfile -Enabled True` for all 3 profiles (Domain/Private/Public).
- **`service`**: forces `WinDefend`/`MpsSvc`/`EventLog` running+automatic; stops and disables 24 services including `RemoteRegistry`, `Telnet`, `Spooler`, `TermService`, `WinRM`.
- **`passwordpolicy`**: spawns `net accounts /maxpwage:` / `/minpwlen:` — **currently dead code**, since `SecurityAudit.psm1` never emits this diff type (password policy is actually enforced via the `securitypolicy`/secedit path below instead).
- **`auditpolicy`**: spawns `auditpol /set /subcategory:"<name>" /success:.. /failure:..` per matched subcategory, up to 17 possible (`Credential Validation`, `Process Creation`, `Removable Storage`, etc.).
- **`securitypolicy`**: exports current policy via `secedit /export`, regex-patches the target field (up to 8 possible: `MinimumPasswordLength=14`, `LockoutBadCount=5`, `NewAdministratorName="CISAdmin"`, etc.), re-imports via `secedit /configure`, deletes the temp export/db files.

**Heaviest step:** secedit export+patch+import, per matched item.

### 4. TelemetryDisable
Dispatches by `Type`: **`service`** — stops (best-effort) then disables up to 9 services (`DiagTrack`, `dmwappushservice`, `WerSvc`, `MapsBroker`, `Fax`, etc.); **`registry`** — writes up to 8 values (`AllowTelemetry=0`, `AllowCortana=0`, `BingSearchEnabled=0`, `TailoredExperiencesWithDiagnosticDataEnabled=0`); **`scheduledtask`** — `Disable-ScheduledTask` against up to 8 task paths (never deletes them, only disables). **Heaviest step:** none — all fast local writes, no external process spawns anywhere in this module.

### 5. SystemOptimization
Dispatches by `Type`: **`service`** — disables up to 7 gaming/Xbox-related services (`XblAuthManager`, `XblGameSave`, `RetailDemo`, +2 Windows-11-only); **`powerplan`** — `powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c` (the well-known Windows "High performance" scheme GUID); **`registry`** — misc single writes; **`visualfx`** — one batch of 7 registry writes (`VisualFXSetting=3`, `MinAnimate="0"`, `TaskbarAnimations=0`, `EnableTransparency=0`, etc.) implementing "Best Performance" visual effects; **`background`** — one batch of 5 registry writes disabling Windows Spotlight (`RotatingLockScreenEnabled=0`, etc.) and switching wallpaper style to a static picture (`WallpaperStyle="10"`); **`startup`** — `Remove-ItemProperty` deleting the matched Run-key value entirely (not disabling — the entry is gone). **Heaviest step:** powercfg spawn.

### 6. WindowsUpdates
If `PSWindowsUpdate` is installed: per matched update (category-filtered to security/critical/important only, per the audit), `Install-WindowsUpdate -KBArticleID <kb>` (or `-UpdateID <guid>`) `-AcceptAll -AutoReboot:$false -IgnoreReboot`. If the module is missing: fallback spawns `usoclient.exe StartScan`, sleeps 2s, spawns `usoclient.exe StartInstall` — fire-and-forget, can't verify individual results, unconditionally marks every diff item "processed" and **sets `RebootRequired=true`**. **Heaviest step:** per-update install via the WU API — "likely the single heaviest step in the whole pipeline."

### 7. AppUpgrade
For each out-of-date app not matching one of the 22 exclude patterns: `winget upgrade --id <id> --silent --accept-package-agreements --accept-source-agreements`, falling back to `choco upgrade <id> --yes --no-progress`. **Heaviest step:** per-app winget upgrade (real download + install).

---

**Total distinct OS-mutation surface across a full run where everything needs action:** ~266 registry writes, 46 services touched, 8 scheduled tasks disabled, ~242 AppX packages removed (+ their provisioned-package counterparts), 12 app installs + N upgrades via winget/choco, 8 secedit fields + 17 auditpol subcategories, 6 Defender preference flags, 3 firewall profiles, 1 power plan, and a category-filtered subset of pending Windows Updates. **Total external-process spawn points:** roughly 20-30+ separate child-process launches (winget × up to 4 call sites, choco × 3, secedit × 3, auditpol × 2, powercfg × 2, usoclient × 2, net accounts × N — the last currently dead code), essentially all sequential, none sharing state or caching between call sites.

*(Full source-of-truth breakdown, including every registry path/service name/AppX pattern grouped by OS mechanism rather than by module, is in [`newtimeline.md`](newtimeline.md)'s impact-based reorganization section — that's also where the case for consolidating this duplication is made.)*
