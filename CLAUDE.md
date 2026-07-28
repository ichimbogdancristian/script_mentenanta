# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A Windows 10/11 maintenance automation system. A `.bat` launcher bootstraps the
environment (elevation, PowerShell 7, winget) and hands off to a PowerShell 7
orchestrator that runs a pipeline of audit + action modules and produces a single
self-contained HTML report. It is designed to run on freshly installed machines
that may only have PowerShell 5.1 available at first.

## THE OPERATING CONTRACT — read this before changing anything

This project has one governing requirement that overrides convenience, tidiness, and
every other design preference: **it must run start-to-finish, unattended, on any
Windows 10/11 machine, with nobody watching.** The intended deployment is exactly this:

1. `script.bat` sits alone in a folder — that is the entire installed footprint.
2. A monthly Task Scheduler job (`WindowsMaintenanceAutomation`, 20th @ 01:00, SYSTEM,
   `/RL HIGHEST`) launches it. `script.bat` also (re)registers that task itself, so the
   system is self-perpetuating from a single file.
3. On launch it verifies its own prerequisites (admin → PS7 → winget) and self-heals what
   it can, so the essential pipeline can run without a human.
4. It downloads the current `master` zip from GitHub and extracts it **next to itself**
   into `script_mentenanta-master\`.
5. It runs the orchestrator (five stages) out of that extracted copy.
6. Stage 5 deletes the extracted folder entirely, leaving **only `script.bat` and the HTML
   report** behind for the next month.

**Anything that can block waiting for a human is a bug**, not a UX choice. Concretely, and
verified in the current code:

- **No `PAUSE`, `SET /P`, or `CHOICE` anywhere in `script.bat`.** Every abort path uses
  `TIMEOUT /T n >nul 2>&1` (which returns immediately when stdin is redirected) and then
  `EXIT /B <code>`. If you add an error path, follow that pattern — a `PAUSE` on a SYSTEM
  task hangs the job forever with no visible window.
- **`TIMEOUT` is not a delay primitive here — it is an abort-path no-op.** With stdin
  redirected (every unattended run) it exits instantly with "Input redirection is not
  supported": measured 0.05s for `TIMEOUT /T 5 /NOBREAK`, versus a correct 5s for
  `ping -n 6 127.0.0.1`. That is *why* it is safe on abort paths, and exactly why it must
  **not** be used where a real wait is required. The 30s pre-orchestrator cooldown therefore
  branches on `IF DEFINED ORCH_EXTRA_ARGS`: `ping -n 31` unattended (really waits),
  `TIMEOUT /T 30` interactive (visible, key-skippable). The cooldown exists because the
  bootstrap may have just installed PS7/winget/PSWindowsUpdate and added Defender
  exclusions, which leave file locks and registry/PATH writes in flight.
- **The one `Read-Host`** (Stage 1 menu) is unreachable unattended: it sits behind a
  `[Console]::KeyAvailable` check, which throws with no console and is caught → treated as
  "no key". Every timed prompt auto-proceeds on timeout; none require input to continue.
- **`-NonInteractive` is passed explicitly by the scheduled tasks**, never derived from
  environment sniffing. See the launcher notes below for why deriving it broke the menu.
- **`-NoExit` is interactive-only.** It is deliberately omitted for unattended runs. Leaving
  it on under Task Scheduler orphans a `pwsh` host at a prompt in session 0 — one more every
  month — and because that host's CWD is the extracted folder, the *next* run's
  `RMDIR /S /Q` of that folder fails and the launcher aborts with `EXIT /B 3`. One stray
  `-NoExit` therefore degrades into "the monthly task silently stops working forever".
- **Package/installer invocations must be silent** (`--silent --disable-interactivity
  --accept-package-agreements --accept-source-agreements`, `msiexec /qn`,
  `Install-WindowsUpdate -Confirm:$false`) and go through the timeout-guarded
  `Invoke-ExternalPackageCommand` so no package manager can hang the run.

**Requirement tiers** (what aborts vs. what degrades):

| Requirement | Missing → | Why |
|---|---|---|
| Administrator | self-elevate via UAC, else `EXIT /B 1` | Already satisfied under the SYSTEM task |
| Network + GitHub reachable | `EXIT /B 3`, run does nothing | Hard: only `script.bat` persists, so there is no local copy to fall back to |
| PowerShell 7 | `EXIT /B 1` | Hard: the orchestrator is `#Requires -Version 7.0` |
| winget | `WARN`, run continues | Soft: only degrades SoftwareManagement/Sysmon |

**What may be left behind.** On a clean run: `script.bat` + the HTML report, nothing else
(`update.zip` is deleted after extraction, and `maintenance.log` is *moved into* the
extracted tree so it dies with it). If the orchestrator crashes, its fatal handler exits
without cleanup and the extracted tree survives — that is self-healing, because the next
run's `:DOWNLOAD_REPOSITORY` step `RMDIR /S /Q`s it before extracting. Do not "fix" that by
adding cleanup to the crash path at the cost of losing the crash evidence.

When a change would trade unattended reliability for interactivity, polish, or a nicer
console experience, unattended reliability wins.

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
- **Interactive by default:** the launcher passes `-NonInteractive` to the orchestrator **only**
  when the user passed `-NonInteractive`/`-TaskNumbers` to `script.bat` itself. It must never
  derive that flag from `AUTO_NONINTERACTIVE`: despite the name, that variable is set at every
  PowerShell-7 *detection* site and just means "a usable `pwsh.exe` was found". Since the
  launcher refuses to run at all without PS7, keying off it made `-NonInteractive` unconditional
  and silently suppressed the Stage 1 module menu on every run. The scheduled tasks
  (monthly-as-SYSTEM, ONLOGON resume) therefore pass `-NonInteractive` **explicitly** in their
  `/TR` command line. Interactivity is safe here precisely because the menu auto-runs on a 10s
  timeout — see the operating contract above.
- **Scheduled-task convergence:** the monthly task is the only unattended entry point, so the
  launcher does not just check *whether* it exists — it checks whether the registered
  `Task To Run` actually contains `-NonInteractive` and **re-creates it (`/F`) when it does
  not**. Without that, any machine whose task was registered by an older `script.bat` (whose
  `/TR` had no arguments) would keep running interactively as SYSTEM forever, since the
  "task already exists" branch would never update it.
- **`ORCH_EXTRA_ARGS` doubles as the interactive/unattended switch** for building `PS_ARGS`
  (`IF DEFINED ORCH_EXTRA_ARGS`). `SET "VAR="` undefines a batch variable, so "no extra args"
  is exactly "interactive". That is what gates `-NoExit`.

### Orchestrator: five stages
[MaintenanceOrchestrator.ps1](MaintenanceOrchestrator.ps1) appends to the single unified
`maintenance.log` (via the core logger — the launcher already created and migrated the file and
passed its path in `$env:MAINTENANCE_LOG`). It is the sole log: a direct-write, auto-flushed
stream, **not** a PowerShell `Start-Transcript` (a transcript handle would block the report from
reading the file mid-run). The orchestrator wraps the whole body in a fatal-capture
`try/catch/finally` (any uncaught error is written to `maintenance.log` with a stack trace; the
log is always closed via `Close-LogFile` in `finally`), then:

1. **Stage 1 – Audit (Type1):** interactive menu with a 10s auto-run countdown; runs
   audit modules. A circuit breaker aborts the stage after 3 consecutive module failures.
   Buffered keystrokes are drained (`Clear-PendingConsoleInput`) before each timed prompt so a
   stray key from an earlier unattended stage can't trigger a phantom selection/abort.
   The menu is only shown when `-NonInteractive` is absent — see the "interactive by default"
   note under the launcher, above. Its box width is derived from the longest label rather than
   hard-coded, and `Clear-Host` is guarded so a console-less host can't kill the run.
2. **Stage 2 – Diff analysis:** for each pair, reads the diff list the Type1 module saved;
   only pairs with a non-empty diff (and not skipped by config) are queued. Each pair is
   wrapped so one bad diff/config entry can't abort the stage.
3. **Stage 3 – Maintenance (Type2):** runs only the queued action modules, in a deliberate
   order (`$Stage3Order`: **SystemConfiguration first** — it owns the restore point and takes it
   as its own first action, keeping the rollback safety net ahead of every other module's
   changes, and it then re-hardens Defender/firewall before the rest of the run — then
   SoftwareManagement → WindowsUpdates → **DiskCleanup last**, so it sweeps up residue the
   earlier actions created). If no diffs, no changes are made. Note SystemConfiguration's diff
   is never empty in practice (it always queues a restore point), so it effectively runs every
   time.
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
on `Num`, not array index). All four pairs are actionable; there is no report-only tail to order
around since the former report-only audits were folded into `SystemConfiguration` (see
"Consolidation note"). Stage 3's execution order is separate (`$Stage3Order`, above).

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
| 2 | SystemConfiguration | `SystemConfiguration` | ✅ | `ConfigType` = restorepoint/security/telemetry/optimization | restore point create+prune, Defender/firewall/security registry + **Sysmon** + **password/lockout policy (secedit)** + **advanced audit policy (auditpol)**, privacy services/registry/tasks, services/power/startup/visual-fx, **plus the report-only inventory + health datasets** |
| 3 | DiskCleanup | `DiskCleanup` | ✅ | `Type` = temp/browser/update/bin | temp/browser cache/cookies, DISM component store, recycle-bin cleanup |
| 4 | WindowsUpdates | `WindowsUpdates` | ✅ | — | Windows Update detection (3-layer: COM/Registry/EventLog) and installation |

**`SystemConfiguration` internal ordering (the important part).** Both halves of this pair run
their work in a deliberate order, not the order items happen to appear:

- **Type1 `SystemConfigurationAudit`** runs *Phase A* (restore point → security → telemetry →
  optimization) and **calls `Save-DiffList` at the end of Phase A**, then runs *Phase B*, the
  slow report-only gathering (inventory, then health — `Get-WinEvent` over 30 days of
  System/Application/Security). Persisting the diff before Phase B means a failure while
  collecting report data can never cost the run the diff Stage 3 depends on; Phase B failures
  downgrade the result to `Warning` instead of `Failed`.
- **Type2 `SystemConfiguration`** sorts the diff through `Get-ConfigItemRank` before applying
  anything: **restore point `create` (0) → security (1) → telemetry (2) → optimization (3) →
  restore point `remove` (4)**. Creation must precede every other mutation or the snapshot is
  of an already-modified system and useless for rollback; pruning is destructive and
  irreversible so it happens only after everything else has succeeded — pruning first would
  discard the very rollback targets a failed run would need. `Sort-Object -Stable` keeps the
  audit's within-phase ordering.
- The audit queues the restore point `create` item **unconditionally** (unless
  `skipRestorePointManagement`), which is also what guarantees this pair's diff is never empty,
  so Stage 2 always schedules its Type2 and the safety net is taken every run.

**CIS coverage: three different mechanisms, not one.** `security-baseline.json` is a CIS
benchmark baseline, and CIS rules do **not** all live in the registry. The file has three
sibling blocks and each needs its own compare/apply pair — a rule in the wrong block is
silently never enforced:

| Baseline block | CIS sections | Read via | Applied via | Diff `Type` |
|---|---|---|---|---|
| `registry` (300 entries) | 2.3.x, 18.x | registry | `Set-RegistryValue` | `registry` |
| `securityPolicy` | 1.1 password, 1.2 lockout | `secedit /export` | `secedit /configure` (minimal UTF-16LE INF) | `secpolicy` |
| `auditPolicy` (18 subcategories) | 17.x | `auditpol /get /r` | `auditpol /set` | `auditpolicy` |

`securityPolicy` and `auditPolicy` were declared in the baseline but **no module read
them**, so every CIS section 1 and 17 rule stayed non-compliant no matter how many times
the run succeeded. `Compare-SecurityPolicyBaseline` / `Compare-AuditPolicyBaseline` and
their `Invoke-*ChangeItem` partners live in `Maintenance.psm1` alongside the registry and
service equivalents. Gotchas worth keeping:

- **`SCENoApplyLegacyAuditPolicy = 1` is load-bearing.** Without it, legacy category-level
  audit policy overrides the section-17 subcategory settings and they silently do nothing.
  It is a registry entry precisely so it is applied in the same pass.
- **`LockoutBadCount` is "N or fewer **but not 0**"** — 0 disables lockout entirely and
  fails the benchmark, so the compare treats 0 as non-compliant, not as "very compliant".
- **`auditpol /r` output is localised.** The parser matches the English inclusion strings
  and, when it cannot, queues the item anyway — `auditpol /set` is idempotent, so a
  needless re-apply is harmless while a missed one would not be.
- Account **renaming** (`NewAdministratorName` / `NewGuestName`) is deliberately not
  applied; none of the tracked CIS checks test it and it is hard to undo unattended.

**Deliberate CIS deviations** (do not "fix" these — they are chosen):

| CIS rule | Baseline value | Why |
|---|---|---|
| 18.10.17.1/18.1 `EnableAppInstaller = 0` | **`1`** | That rule disables **winget**, which SoftwareManagement and the Sysmon install depend on. Complying would break the project. |
| 18.10.9.2.15–18 BitLocker TPM+PIN | not applied | A pre-boot PIN halts the machine after the Stage 5 reboot — it ends unattended operation and can strand a headless box. |
| LAPS, Hardened UNC Paths | not applied | Domain-only; no-ops or harmful on the standalone machines this targets. |
| `RequirePrivateStoreOnly`, `legalnoticetext`, `DenyDeviceIDs` (Thunderbolt) | not applied | Organisation-specific; break the Store, add a logon banner, or kill USB-C docks. |

`modules.systemConfiguration.skipPasswordPolicy` / `skipAuditPolicy` in `main-config.json`
turn the two non-registry areas off. Both default to enforcing.

**Notable implementations:**
- `SystemConfiguration` creates/deletes restore points through the **`root/default:SystemRestore`
  WMI class via `Invoke-CimMethod`**, never `Checkpoint-Computer` / `Get-ComputerRestorePoint` /
  `Get-WmiObject`: those are Windows PowerShell 5.1-only and simply do not exist in PS7, which is
  the only shell modules run under (the pre-consolidation `RestorePointManagement.psm1` used all
  three and failed at runtime). It also clears
  `SystemRestorePointCreationFrequency`, or Windows' default one-per-24h throttle would silently
  turn "a restore point every run" into "one per day".
- `SystemConfiguration` installs **Sysinternals Sysmon** via winget (`Microsoft.Sysinternals.Sysmon`)
  and applies `config/sysmon/sysmonconfig.xml` (with `-accepteula`) when the Sysmon service is
  absent. It resolves the **real** `Sysmon64.exe` (from `%windir%` or the winget `Packages`
  folder), deliberately **avoiding the winget `Links\sysmon.exe` shim** — launching that
  App-Execution-Alias with redirected stdio fail-fast crashes with `0xC0000409` (-1073740791).
- `SoftwareManagement` detects bloatware from **four sources** — AppX (PS5.1 compat layer) →
  provisioned packages → registry → winget `list` (parsed into Name/Id columns, never matched
  against the raw formatted line; the winget table has no JSON/CSV output option, so parsing
  validates each row's column count against the header row rather than trusting a blanket
  minimum). Every candidate is gated by `bloatware/protected-packages.json` (hard block) +
  `bloatware/dependency-matrix.json` via `Test-CanRemovePackage`, **plus a cascade-safety pass**
  after all sources are merged: a package is dropped from the removal set if
  `dependency-matrix.json` declares a dependent that's actually installed but not itself queued
  for removal this run (protects, never removes — the safe default for an unattended run).
  Bloatware patterns tagged `"tier": "broad"` in `bloatware-detection.json` (whole-vendor
  wildcards like `*Razer*`/`*ASUS*`/`Dell.*` that can also match software the user deliberately
  installed) are excluded unless `modules.softwareManagement.aggressiveOemRemoval` is `true` in
  `main-config.json`. Type2 removes each item with a layered strategy (AppX → Provisioned →
  registry **silent-uninstall only** → winget-by-id → winget-by-name), then installs essentials
  and applies upgrades, all through `Invoke-ExternalPackageCommand` (timeout-guarded — no package
  manager call can hang an unattended run). Essential-app "already installed" detection tries the
  precise `winget list --id --exact` check before falling back to a name-substring match (not the
  other way around — registry `DisplayName` often doesn't literally contain the baseline's `name`
  string). Nothing survives between runs except the final HTML report (copied to
  `$env:ORIGINAL_SCRIPT_DIR`, see below), so a missing essential app is queued for install on
  every run regardless of whether a prior run installed it and the user removed it since.
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
- **Never increment a counter inside `| ForEach-Object { }`.** The pipeline scriptblock gets its
  own scope, so `$n++` there updates a throwaway copy and the outer variable stays at 0. This has
  already caused two silent bugs (the audit's per-section item counts, and the power-plan GUID
  lookup that always fell through to its hard-coded default). Use a `foreach` loop when you must
  assign outward, or derive the value from the finished collection afterwards. Mutating a
  `List[T]` with `.Add()` from inside `ForEach-Object` is fine — that mutates the same object.

### Core modules
There are three modules under `modules/core/`. [Maintenance.psm1](modules/core/Maintenance.psm1)
is imported `-Global` and provides all shared infrastructure — do not duplicate these elsewhere:
`Write-Log` (structured `[ts] [COMPONENT] [LEVEL] msg`, written **directly** to the single
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
helpers render per-module cards, the system overview, the inventory/restore-point/health
sections, and the embedded log console (`ConvertFrom-MaintenanceLog` / `Build-LogConsole` parse the
structured `maintenance.log` into the collapsible in-report console). Report markup/styling changes
belong here, not in the orchestrator. The three data sections are gated on the
`SystemConfigurationAudit` result having run and otherwise key off the presence of their own JSON
under `temp_files/data/` (`system-inventory.json`, `restore-point-audit.json`,
`system-health-report.json`), so a section skipped by config simply doesn't render.

[ConsoleUI.psm1](modules/core/ConsoleUI.psm1) is imported only by the orchestrator and owns
interactive console formatting (section headers, status symbols, progress bars, spinners,
countdowns). Used for the Stage 1 menu and stage banners; not used by Type1/Type2 modules.

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
- **Nothing persists between runs except the final HTML report.** `script.bat`'s self-update
  `RMDIR /S /Q`'s the extracted tree before every real run, so nothing under `$env:MAINT_ROOT`
  (including `temp_files/`) survives to the next run — and that's intentional, not a gap to work
  around. There is no per-machine config-override mechanism and no cross-run state/install
  journal; every run re-derives everything from the shipped `config/lists/` baseline and the
  live system. The only things that outlive a run are copied to `$env:ORIGINAL_SCRIPT_DIR` (the
  stable folder `script.bat` was launched from): the HTML report, and the self-updated
  `script.bat` itself (via `$env:PENDING_SCRIPT_UPDATE`, applied by the orchestrator after the
  launcher exits — see the self-update note above).

### Config and generated files
- `config/settings/main-config.json` — execution/shutdown behavior and per-module `skip*` flags,
  plus per-module option blocks (e.g. `modules.softwareManagement.aggressiveOemRemoval`).
- `config/lists/<area>/*.json` — the baseline data each Type1 module diffs against (bloatware
  names, essential apps, security baseline, etc.). Baseline JSON commonly has `common` /
  `windows10` / `windows11` sections that Type1 modules merge based on `OSContext`. One merged
  audit may consume several list folders (e.g. SoftwareManagement reads `bloatware`,
  `essential-apps`, `app-upgrade`). Loaded as-is by `Get-BaselineList` — there is no per-machine
  override layer; edit these files (and push to `master`) to change behavior on every machine.
- `config/sysmon/sysmonconfig.xml` — Sysmon configuration applied by SystemConfiguration.
- `temp_files/` (git-ignored) — `logs/maintenance.log` (the single unified log; the launcher
  migrates its startup log here after extraction), `diff/*-diff.json`, `reports/*.html`, `data/`.
  Created at startup by the launcher/orchestrator and core module. **Wiped every run** by
  `script.bat`'s self-update — nothing here (or anywhere under the extracted tree) is meant to
  survive to the next run.

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
- **Modules must never prompt or block.** No `Read-Host`, no `-Confirm`, no `PAUSE`, no GUI
  installer. Pass `-Confirm:$false`/`--silent`/`/qn` explicitly rather than relying on a
  preference variable, and route every external process through the timeout-guarded
  `Invoke-ExternalPackageCommand`. A module that waits for input hangs the monthly SYSTEM task
  with no window to close — see the operating contract at the top.
- **A module failing must not fail the run.** Modules return `Failed`/`Warning` in their
  `New-ModuleResult`; they don't throw out to the orchestrator. Best-effort work (opportunistic
  space reclamation, report-only gathering) should degrade to `Warning` and let the pipeline
  continue rather than being counted as a hard failure.

## Consolidation note

The module surface has been consolidated twice. First, Type2 went from six modules to four:
`SoftwareManagement` merged BloatwareRemoval + AppManagement (itself EssentialApps + AppUpgrade);
`SystemConfiguration` merged SystemHardening (Security + Telemetry) + SystemOptimization.

Then (**v7.0**) the remaining odd-shaped pairs were folded into the `SystemConfiguration` pair,
leaving a clean **4 Type1 + 4 Type2**, one Type2 per Type1, no report-only modules:

- `RestorePointAudit.psm1` → `SystemConfigurationAudit.psm1` (as `ConfigType = 'restorepoint'`)
- `SystemInventory.psm1` → `SystemConfigurationAudit.psm1` (report-only Phase B)
- `SystemHealthAudit.psm1` → `SystemConfigurationAudit.psm1` (report-only Phase B)
- `RestorePointManagement.psm1` → `SystemConfiguration.psm1` (Type2)

That merge is why `SystemConfiguration` needs the explicit intra-module ordering documented
above (`Get-ConfigItemRank`): folding the restore point into the same module removed the
orchestrator's ability to sequence it via `$Stage3Order`, so the ordering guarantee moved
*inside* the module. It also let the two duplicate `Win32_ShadowCopy` queries (one for the diff,
one for the inventory) collapse into one.

`DiskCleanup` and `WindowsUpdates` stay standalone (distinct risk/tooling). Superseded `.psm1`
files were deleted, so any module on disk is live. When merging modules, keep the
one-combined-diff-plus-discriminator pattern and register the pair in `$ModulePairs`.
