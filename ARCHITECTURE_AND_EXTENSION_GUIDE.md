# Architecture & Extension Guide

**How to keep `script_mentenanta` maintainable, and how to add functionality to it safely.**

Written 7 August 2026, from a full read of the codebase (10,907 lines of code across 14 files,
~4,000 lines of config, 261 commits since 30 November 2025).

This is the *strategy* document. [CLAUDE.md](CLAUDE.md) is the *contract* document — it says what
the system does and why each decision was made. This one says how to change it without breaking it.

---

## Contents

- [Part 0 — The conclusion, up front](#part-0--the-conclusion-up-front)
- [Part 1 — The invariants: what must never change](#part-1--the-invariants-what-must-never-change)
- [Part 2 — The current shape, measured](#part-2--the-current-shape-measured)
- [Part 3 — Target structure](#part-3--target-structure)
- [Part 4 — The roadmap](#part-4--the-roadmap-six-phases-in-dependency-order)
- [Part 5 — Cookbook: how to add things](#part-5--cookbook-how-to-add-things)
- [Part 6 — The review checklist](#part-6--the-review-checklist)
- [Part 7 — Named anti-patterns](#part-7--named-anti-patterns-the-bug-taxonomy)

---

## Part 0 — The conclusion, up front

**Do not restructure this project. The architecture is already right.**

The Type1/Type2 pair model — an audit module that only reads, an action module that only writes,
communicating exclusively through a diff list on disk, registered in one array — is a genuinely
good design. It gives you:

- a natural unit of work (the pair) that maps 1:1 to a user-visible feature,
- a hard read/write separation that makes the audit side trivially safe to run and test,
- a serialization boundary (`temp_files/diff/<DiffKey>-diff.json`) that you can inspect by hand
  after a run to see exactly what one half told the other,
- and a single registration point (`$ModulePairs`) so adding a feature is additive, not invasive.

Most Windows maintenance tooling never gets this far. **The extension mechanism you need already
exists.** The work ahead is not redesigning it — it is making it *safe to use* and *cheap to
extend*, in that order.

Concretely, that means five things, in strict priority order:

| # | Work | Why it's ranked here |
|---|---|---|
| 1 | **Pester tests for pure functions** | 10,907 lines mutating system state unattended, zero tests. Nearly every historical bug was a pure-function bug. |
| 2 | **CI running Analyzer + Pester** | `.github/` exists and is empty. PSScriptAnalyzer is configured but nothing runs it. |
| 3 | **Move PowerShell work out of `script.bat`** | 29 embedded one-liners, longest 807 chars, none of them linted or tested. |
| 4 | **Extract the four >300-line functions** | Four functions, not fourteen files. Extract *inside* the file. |
| 5 | **Then, and only then, add features** | Tool-acquisition layer, new modules, new report sections. |

Items 1 and 2 are worth more than 3, 4 and 5 combined. Everything in Part 4 is sequenced on that
basis.

---

## Part 1 — The invariants: what must never change

These are not preferences. Violating any of them breaks the deployment model, and most of them
break it *silently* — the monthly task keeps existing, keeps being scheduled, and quietly stops
doing anything. Print this list.

### I1. `script.bat` is one file, and it is the entire installed footprint

It cannot be split into multiple files. Fragments would have to already be on disk, which defeats
the bootstrap. Anything you want to remove from `script.bat` must move *into the orchestrator*, not
into a sibling `.bat`.

### I2. Nothing may block waiting for a human

No `PAUSE`, `SET /P`, `CHOICE`, `Read-Host`, `-Confirm`, or GUI installer, anywhere in any code
path that an unattended run can reach. Every timed prompt must auto-proceed on timeout. Every
external process goes through the timeout-guarded `Invoke-ExternalPackageCommand`.

### I3. A module failing must not fail the run

Modules return `Failed`/`Warning` in their `New-ModuleResult`; they do not throw out to the
orchestrator. Best-effort work degrades to `Warning`.

### I4. Nothing persists between runs except the HTML report

`script.bat`'s self-update `RMDIR /S /Q`s the extracted tree before every run. There is no
per-machine config override, no cross-run state, no install journal. Every run re-derives
everything from the shipped baselines and the live system. **Do not design a feature that needs
memory of the previous run.**

### I5. `DiffKey` is the contract

It must match on the Type1 side, the Type2 side, and in `$ModulePairs`. It is the filename stem
under `temp_files/diff/`. Get it wrong and Stage 2 silently finds an empty diff and skips the pair.

### I6. Type1 never writes; Type2 never reads the live system to decide *what* to do

Type1 audits and emits a diff. Type2 consumes the diff and acts. Type2 may re-query the system to
*execute* an item (e.g. `Remove-BloatwareLayered` re-queries the live provisioned list to match a
stem) but must not invent work that isn't in the diff.

### I7. Reboot is decided in exactly two places

`script.bat` (pending-update check at startup) and Stage 5. Modules signal via `RebootRequired`;
they never reboot.

### I8. Config is read-only shipped data

`config/lists/*.json` and `main-config.json` are loaded as-is by `Get-BaselineList` /
`Get-MainConfig`. There is no override layer. To change behaviour on every machine, edit the file
and push to `master`.

---

## Part 2 — The current shape, measured

### Code

| File | Lines | Longest function | Assessment |
|---|---:|---|---|
| `script.bat` | 1760 | — | 396 REM + 201 blank + 290 log calls ⇒ **~870 lines of logic**. Cannot split (I1). |
| `modules/core/Maintenance.psm1` | 1872 | `Invoke-ExternalPackageCommand` (117) | Healthy. 11 cohesive regions, ~50 functions. |
| `modules/core/ReportGenerator.psm1` | 1198 | `Get-ReportCss` (234) | Healthy, but 300+ lines are CSS/JS in strings. |
| `modules/type1/SystemConfigurationAudit.psm1` | 970 | **`Invoke-SystemConfigurationAudit` (446)** | File fine; one oversized function. |
| `MaintenanceOrchestrator.ps1` | 839 | — | Healthy. 18% comments. |
| `modules/type1/SoftwareManagementAudit.psm1` | 828 | **`Get-BloatwareFromAllSources` (338)** | File fine; one oversized function. |
| `modules/type2/SystemConfiguration.psm1` | 689 | **`Invoke-SystemConfiguration` (338)** | File fine; one oversized function. |
| `modules/type2/SoftwareManagement.psm1` | 592 | **`Remove-BloatwareLayered` (300)** | File fine; one oversized function. |
| `modules/type2/WindowsUpdates.psm1` | 540 | `Install-WindowsUpdateViaCom` (157) | Healthy. |
| `modules/core/ConsoleUI.psm1` | 497 | — | Healthy. |
| `modules/type1/DiskCleanupAudit.psm1` | 325 | `Invoke-DiskCleanupAudit` (156) | Healthy. |
| `modules/type1/WindowsUpdatesAudit.psm1` | 304 | `Invoke-WindowsUpdatesAudit` (110) | Healthy. |
| `modules/type2/DiskCleanup.psm1` | 166 | `Invoke-DiskCleanup` (152) | Healthy. |

Comment density runs 5–18%, and the comments explain *why*, not *what*. This is well-written code.

### Gaps

- **No tests.** No Pester, no `*.Tests.ps1`, nothing.
- **No CI.** `.github/` exists and is empty.
- **29 embedded PowerShell one-liners in `script.bat`**, longest 807 characters — unlinted,
  untestable, double-escaped.
- **Defender exclusions are added in batch (`script.bat:1188`) and removed in PowerShell
  (Stage 5).** One lifecycle, two languages, two files.
- **`security-baseline.json` is 2,528 lines** — the largest single file in the project.

---

## Part 3 — Target structure

The directory layout barely changes. What changes is that four things get homes they don't have
today: tests, CI, report assets, and downloaded tools.

```
script_mentenanta/
├── script.bat                       # I1: one file. Shrinks by ~200 lines (Phase 1), never splits.
├── MaintenanceOrchestrator.ps1      # five stages + $ModulePairs
├── PSScriptAnalyzerSettings.psd1
│
├── modules/
│   ├── core/
│   │   ├── Maintenance.psm1         # shared infra, imported -Global
│   │   ├── ReportGenerator.psm1     # Stage 4 only
│   │   ├── ConsoleUI.psm1           # orchestrator only
│   │   └── assets/                  # NEW (Phase 3)
│   │       ├── report.css           #   was Get-ReportCss  (234 lines of CSS)
│   │       └── report.js            #   was Get-ReportJs   (55 lines of JS)
│   ├── type1/                       # audits — READ ONLY
│   └── type2/                       # actions — WRITE
│
├── config/
│   ├── settings/main-config.json
│   ├── lists/<area>/*.json
│   └── sysmon/sysmonconfig.xml
│
├── tests/                           # NEW (Phase 0) — never shipped to the target machine
│   ├── unit/                        #   pure functions, no system access, run anywhere
│   │   ├── Winget.Tests.ps1
│   │   ├── DiffEngine.Tests.ps1
│   │   ├── SecurityPolicy.Tests.ps1
│   │   └── LogParsing.Tests.ps1
│   ├── contract/                    #   shape checks: $ModulePairs ↔ files ↔ config keys
│   │   └── ModulePairs.Tests.ps1
│   ├── fixtures/                    #   captured real-world tool output
│   │   ├── winget-list.txt
│   │   ├── secedit-export.inf
│   │   ├── auditpol-r.csv
│   │   └── dism-provisioned.txt
│   └── README.md
│
├── .github/workflows/               # NEW (Phase 0)
│   └── ci.yml                       #   PSScriptAnalyzer + Pester on push/PR
│
└── temp_files/                      # git-ignored, wiped every run
    ├── logs/  diff/  data/  reports/
    └── tools/                       # NEW (Phase 4) — downloaded Sysinternals binaries
```

Two notes on this tree:

**`tests/` ships in the zip and that's fine.** The extracted tree is deleted by Stage 5 anyway, and
excluding it would mean maintaining an exclusion list in the extraction step. A few hundred KB of
test files costs nothing. Do *not* let the orchestrator ever import from `tests/`.

**`modules/core/assets/` must be read-and-inlined, not linked.** The report is a single
self-contained HTML file copied to `$env:ORIGINAL_SCRIPT_DIR`; it must survive with no sibling
files. `Get-ReportCss` becomes a one-line `Get-Content -Raw` of `report.css`.

---

## Part 4 — The roadmap: six phases, in dependency order

Each phase is independently shippable and leaves the system working. Do them in order — later
phases assume the safety net from earlier ones.

---

### Phase 0 — Build the safety net ✅ DONE (commit `cb081fe`)

> **Outcome: 137 tests, ~7s, green.** It found a real bug on the first test file —
> `ConvertFrom-WingetListTable` unrolled a single-row result to a bare hashtable, so
> `Resolve-WingetIdForCandidate`'s `Count -eq 1` success condition could never be true and Pass B
> of the bloatware Id resolution had never resolved a single Id. Same class as the defect
> `Get-DiffList` already guarded against. See [tests/README.md](tests/README.md).
>
> Also worth recording: three of the first four *contract*-test failures were bugs in the **tests**,
> not the config. `protected-packages.json` has a documented `optional_but_safe` section that is
> explicitly documentation-only. Read the config's own comments before calling something a defect.

**Why this is first:** read the bug history in CLAUDE.md. Counter increments inside
`ForEach-Object` that silently stayed at zero. `.PSObject.Properties` on a hashtable enumerating
CLR members instead of JSON keys, making the bloatware protection list a no-op. The inverted
`TIMEOUT` ERRORLEVEL that meant a keypress could *never* select the Testing branch. The DISM
parser that latched fields in the wrong order and paired every `DisplayName` with the *previous*
record's `PackageName`. `Remove-AppxPackageCompat` returning nothing so Layer 1 always claimed
success.

**Every single one of those is a pure-function bug in parsing or comparison logic.** None needed a
live Windows machine to catch. All of them shipped, and several ran wrong on every machine for
months. This is not a hypothetical risk profile — it is the observed one.

#### Step 0.1 — Stand up Pester

```powershell
Install-Module Pester -Scope CurrentUser -Force   # dev machine only, never on the target
```

Create `tests/unit/` and write tests for the **pure functions first** — the ones that take a string
or an object and return a value, with no system access:

| Function | Location | What to test |
|---|---|---|
| `ConvertFrom-WingetListTable` | `SoftwareManagementAudit.psm1` | Header-driven column-count validation; rows with spaces in names; the no-JSON-output reality |
| `ConvertFrom-WingetPackageId` | `SoftwareManagementAudit.psm1` | `MSIX\…_2.0.24.0_x64__8wekyb3d8bbwe` → stem; `ARP\Machine\X64\BabyWare` → stem; plain `angryziber.AngryIPScanner` |
| `Compare-ListDiff` | `Maintenance.psm1` | All three strategies: `Present`, `Missing`, `Changed` |
| `Compare-SecurityPolicyBaseline` | `Maintenance.psm1` | **`LockoutBadCount = 0` must be non-compliant**, not "very compliant" |
| `Compare-AuditPolicyBaseline` | `Maintenance.psm1` | Localised `auditpol /r` output must queue the item, not skip it |
| `ConvertFrom-MaintenanceLog` | `ReportGenerator.psm1` | Malformed lines, multi-line messages, level parsing |
| `Get-ConfigItemRank` | `SystemConfiguration.psm1` | create(0) → security(1) → telemetry(2) → optimization(3) → remove(4) |
| DISM fallback parser | `Maintenance.psm1` | `DisplayName` arrives **before** `PackageName` |
| `Get-WindowsLifecycleStatus` | `WindowsUpdatesAudit.psm1` | LTSC/IoT skip; date comparison at the boundary |

**Use captured real output as fixtures.** Run `winget list`, `secedit /export`, `auditpol /get /r`,
and `dism /Get-ProvisionedAppxPackages` on a real machine once, save the output under
`tests/fixtures/`, and test the parsers against those files. This is the highest-value hour in the
whole roadmap: it turns "I hope the parser still works after the refactor" into a fact.

#### Step 0.2 — Contract tests

These are cheap and catch a whole bug class — the "silently does nothing" class that I5 warns
about:

```powershell
Describe '$ModulePairs integrity' {
    It 'every Type1File and Type2File exists on disk' { ... }
    It 'every Type1Func/Type2Func is exported by its module' { ... }
    It 'every ConfigSkip key exists in main-config.json' { ... }
    It 'Num values are unique' { ... }
    It 'DiffKey values are unique' { ... }
    It 'every DiffKey in $Stage3Order matches a pair' { ... }
}

Describe 'Baseline JSON integrity' {
    It 'every config/lists/**/*.json parses' { ... }
    It 'dependency-matrix dependents are package-shaped, not prose' {
        # catches "Many UWP apps" — a value that -like matches nothing
    }
    It 'no dependency-matrix dependent is also in protected-packages.json' {
        # the Xbox bug: a protected dependent makes the rule unsatisfiable
    }
    It 'no app-upgrade ExcludePattern matches an essential-apps entry' {
        # the Adobe* bug: pinning Acrobat Reader forever
    }
}
```

That last block is three tests that would each have caught a real shipped bug.

#### Step 0.3 — CI

`.github/workflows/ci.yml`, on push and PR, on `windows-latest`:

1. `Invoke-ScriptAnalyzer -Path . -Recurse -Settings .\PSScriptAnalyzerSettings.psd1` — fail on
   Error, report Warning.
2. `Invoke-Pester ./tests/unit ./tests/contract -CI`
3. A syntax-only parse of every `.psm1`/`.ps1`:
   `[System.Management.Automation.Language.Parser]::ParseFile(...)` — catches a typo that would
   otherwise only surface as "module failed to import" on a customer's machine at 01:00.

**Exit criteria for Phase 0:** green CI on `master`, and at least the nine parsers above under test.

---

### Phase 1 — Shrink the batch surface ✅ DONE (commit `fa7c587`)

`:PS7_COMPLETE` is at `script.bat:1147`. **Everything after that line runs with PowerShell 7
confirmed present** — which means it does not have to be batch. As batch it was the worst code in
the project: 616- and 807-character `pwsh -Command` strings with batch escaping, no linting, no
error handling beyond `ERRORLEVEL`.

**Result: 1761 → 1674 lines; embedded PowerShell one-liners 39 → 30.**

| Change | Outcome |
|---|---|
| PSWindowsUpdate install → orchestrator **Stage 0 (Preflight)** | ✅ Moved. Keeps `-Scope AllUsers` — SYSTEM cannot see a CurrentUser module. Best-effort: WindowsUpdates' primary path is the COM API. |
| Duplicate restore-point block (~119 lines, 7 one-liners) | ✅ **Deleted.** See below. |
| Defender exclusion add | ❌ **Deliberately NOT moved.** See below. |
| Scheduled-task verification | ➖ Left in batch — it is `schtasks` shelling, not PowerShell, so moving it wins nothing. |

**Correction to this guide's original plan — the Defender exclusion must stay in batch.** The
first draft proposed moving the extracted-tree exclusion into Stage 0 to reunite it with the
Stage 5 remove. That is wrong. The exclusions must be in place **before `pwsh.exe` starts** and
**before the orchestrator imports its modules out of the extracted tree** — both of which happen
before any Stage 0 code can run. Moving the add would leave the process launch and the module load
unprotected: strictly worse than the asymmetry it was meant to fix. What *did* improve is that its
result is now captured into `maintenance.log` rather than `Write-Host`'d to a console nobody reads
on an unattended run.

**The restore-point block was the real prize, and it was not in the original plan.** `script.bat`
created a *second* restore point before launching the orchestrator, in ~119 lines and 7 embedded
one-liners. `New-SystemRestorePoint` already did everything it did — and did it better:

- the launcher block never cleared `SystemRestorePointCreationFrequency`, so Windows silently
  reduced its `Checkpoint-Computer` to a **no-op** whenever a restore point already existed from
  the past 24h. It reported "created" and only half-noticed via "verification inconclusive";
- `Checkpoint-Computer` / `Enable-ComputerRestore` / `Get-ComputerRestorePoint` are **not native
  to PS7**. They resolve only as implicit-remoting proxy functions through the Windows PowerShell
  compatibility layer (verified: `CommandType: Function` from a `remoteIpMoProxy_…` path), backed
  by a background WinPS 5.1 session — slow, and not something to rely on under SYSTEM in session 0.

Only its shadow-storage sizing (`vssadmin resize shadowstorage /MaxSize=10GB`) was worth keeping,
and moved into `New-SystemRestorePoint`. Net: **one restore point per run instead of two**, taken
by the better path.

**What must stay in batch, permanently:** admin elevation, pending-reboot detection, the monthly
task creation/convergence, the branch prompt, download + extract, winget bootstrap, PS7 install,
the Defender exclusion add, and the orchestrator handoff. That's the irreducible bootstrap — it
all runs before PS7 exists, or must precede the orchestrator's own startup.

**Lesson for later phases:** the biggest win here was a block the plan never mentioned, found by
reading the code rather than the roadmap. Re-read before executing a phase.

---

### Phase 2 — Break up the four oversized functions

Four functions, all in files that are otherwise fine. **Extract helpers into the same file.** Do not
create new module files; that adds `Import-Module` ceremony and load-order concerns for no benefit.

| Function | Lines | Split into | Natural seam |
|---|---:|---|---|
| `Invoke-SystemConfigurationAudit` | 446 | 6 helpers + a ~60-line orchestrating body | Already has `A1`/`A2`/`A3`… banners in comments — the map is drawn for you |
| `Get-BloatwareFromAllSources` | 338 | 4 source functions + merge + cascade-safety | The four detection sources are already conceptually separate |
| `Invoke-SystemConfiguration` | 338 | Keep the `switch`; extract each `ConfigType` arm | The discriminator arms |
| `Remove-BloatwareLayered` | 300 | 5 layer functions returning a small result object | The five layers |

**Do Phase 2 after Phase 0, never before.** These four functions contain the most intricate logic
in the project — the layered-removal suppression rules, the cascade-safety pass, the
`Get-ConfigItemRank` ordering guarantee. Refactoring them without tests is exactly how you
reintroduce the "only a layer that verifiably uninstalls may suppress later layers" bug.

Two rules while extracting:

- **Preserve the comments.** The `Why:` comments in these functions are the accumulated bug
  history. Move them with the code they explain; do not summarise them away.
- **Preserve ordering guarantees explicitly.** `Get-ConfigItemRank` and the Phase A/Phase B
  `Save-DiffList` boundary are correctness, not style. Add a test for each before you touch them.

---

### Phase 3 — Extract the report assets

`Get-ReportCss` is 234 lines of CSS in a PowerShell string; `Get-ReportJs` is another ~55 of
JavaScript. Move to `modules/core/assets/report.css` and `report.js`, then:

```powershell
function Get-ReportCss {
    $p = Join-Path $PSScriptRoot 'assets\report.css'
    if (Test-Path $p) { return Get-Content -LiteralPath $p -Raw }
    Write-Log -Level WARN -Component REPORT -Message 'report.css missing - report will be unstyled'
    return ''
}
```

You keep the single-file self-contained report (the content is inlined at render time), and you get
syntax highlighting, formatting, and linting on 300 lines of frontend code currently trapped in
here-strings. Note the graceful degradation: a missing asset produces an ugly report, not a failed
run — I3 applies to the report generator too.

---

### Phase 4 — Add the tool-acquisition layer

Prerequisite for any external-binary feature, including the Sysinternals work in
[Sysinternals_Suite_Reference.md](Sysinternals_Suite_Reference.md).

Add to `Maintenance.psm1`:

- `Get-ExternalTool -Name <n> -Url <u>` — download → extract to `temp_files/tools/` → resolve
  64-bit-first → **verify Authenticode signature** → return path or `$null`.
- `Invoke-CapturedCommand` — the stdout-capturing sibling of `Invoke-ExternalPackageCommand`
  (which returns only an exit code). Same drain-then-wait deadlock-safe shape.
- A `tools` block in `main-config.json`: master `enabled` flag plus per-tool toggles.

**Every caller must tolerate `$null`** and degrade to `Warning` (I3). No external tool may ever be
a hard dependency — the same rule winget already lives under.

---

### Phase 5 — Add capability

Only now. See Part 5 for the recipes, and §9 of the Sysinternals guide for a concrete worked
backlog (MoveFile in DiskCleanup → Handle diagnostics → PendMoves → Autorunsc → Sigcheck → du).

---

## Part 5 — Cookbook: how to add things

### First: decide *which* extension point you need

This decision is the difference between a 20-line change and a 600-line one. Work down the list and
stop at the first match:

```
Do you want to change WHAT gets removed/installed/enforced,
using logic that already exists?
        └── YES → Recipe C: edit a baseline JSON. No code. ★ cheapest
        └── NO ↓

Does an existing pair already own this concern?
  (software / system config / disk / updates)
        └── YES → Recipe B: add a discriminator value to that pair. ★ preferred
        └── NO ↓

Is it a genuinely new concern with its own risk profile and tooling?
        └── YES → Recipe A: a new Type1/Type2 pair.
```

**Default to Recipe B.** The module surface was deliberately consolidated *twice* — six Type2
modules became four, then the odd-shaped pairs were folded into `SystemConfiguration`. That
consolidation is the project's stated direction. A fifth pair needs to justify itself against it.

---

### Recipe A — A new Type1/Type2 module pair

Use when the concern has its own risk profile, its own tooling, and its own failure modes.
`DiskCleanup` and `WindowsUpdates` stay standalone for exactly this reason.

**Worked example: a "Driver Management" pair.**

**A1. Create the baseline.** `config/lists/drivers/driver-config.json`, with `common` /
`windows10` / `windows11` sections if OS-specific:

```json
{
  "common": { "skipVendors": ["*Realtek*"], "maxAgeDays": 365 },
  "windows11": { "allowFeatureDrivers": true }
}
```

**A2. Write the Type1 audit.** `modules/type1/DriverManagementAudit.psm1`:

```powershell
#Requires -Version 7.0
Set-StrictMode -Version Latest

function Invoke-DriverManagementAudit {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    Write-Log -Level INFO -Component DRIVER-AUDIT -Message 'Starting driver audit'
    try {
        $osCtx    = (Get-Variable OSContext -Scope Global -ValueOnly -EA SilentlyContinue) ?? (Get-OSContext)
        $baseline = Get-BaselineList -ModuleFolder 'drivers' -FileName 'driver-config.json'
        if (-not $baseline) {
            return New-ModuleResult -ModuleName 'DriverManagementAudit' -ModuleType Type1 `
                -Status 'Skipped' -Message 'Baseline not found'
        }

        $diff = [System.Collections.Generic.List[hashtable]]::new()
        # ... scan; every item carries a discriminator so Type2 can switch on it ...
        $diff.Add(@{ Type = 'outdated'; Name = 'nvlddmkm'; CurrentVersion = '31.0.15'; DesiredVersion = 'latest' })

        Save-DiffList -ModuleName 'DriverManagement' -DiffList $diff.ToArray()   # ← DiffKey (I5)

        return New-ModuleResult -ModuleName 'DriverManagementAudit' -ModuleType Type1 `
            -Status 'Success' -ItemsDetected $diff.Count `
            -Message "$($diff.Count) driver item(s) queued" `
            -ExtraData @{ OSBuild = $osCtx.Build }
    }
    catch {
        Write-LogException -Exception $_ -Component DRIVER-AUDIT
        return New-ModuleResult -ModuleName 'DriverManagementAudit' -ModuleType Type1 `
            -Status 'Failed' -Message $_.Exception.Message -Errors @($_)
    }
}

Export-ModuleMember -Function 'Invoke-DriverManagementAudit'
```

Note: `Save-DiffList` takes `[array]`, and `Get-DiffList` returns `[hashtable[]]` — the
`, @(...)` array-wrapping inside `Get-DiffList` exists specifically so a **single-item** diff does
not unroll into a bare hashtable. Don't reintroduce that by unwrapping it at the call site.

**A3. Write the Type2 action.** `modules/type2/DriverManagement.psm1`:

```powershell
function Invoke-DriverManagement {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([Parameter()] [hashtable]$OSContext)

    $diff = Get-DiffList -ModuleName 'DriverManagement'      # ← same DiffKey (I5)
    if ($diff.Count -eq 0) {
        return New-ModuleResult -ModuleName 'DriverManagement' -ModuleType Type2 `
            -Status 'Skipped' -Message 'No items in diff'
    }

    $processed = 0; $failed = 0; $rebootNeeded = $false
    foreach ($item in $diff) {
        try {
            switch ($item.Type) {                             # ← the discriminator
                'outdated' { <# ... #>; $processed++ }
                'rollback' { <# ... #>; $processed++; $rebootNeeded = $true }
                default {
                    Write-Log -Level WARN -Component DRIVER -Message "Unknown Type: $($item.Type)"
                }
            }
        }
        catch {
            $failed++
            Write-Log -Level ERROR -Component DRIVER -Message "Failed $($item.Name): $_"
        }
    }

    $status = if ($failed -eq 0) { 'Success' } elseif ($processed -gt 0) { 'Warning' } else { 'Failed' }
    return New-ModuleResult -ModuleName 'DriverManagement' -ModuleType Type2 -Status $status `
        -ItemsDetected $diff.Count -ItemsProcessed $processed -ItemsFailed $failed `
        -RebootRequired $rebootNeeded
}

Export-ModuleMember -Function 'Invoke-DriverManagement'
```

**A4. Register the pair** in `MaintenanceOrchestrator.ps1`'s `$ModulePairs` (array **order** is the
Stage 1 menu order; `Num` is the stable id used by `-TaskNumbers`, matched on `Num`, not index):

```powershell
@{
    Num        = 5
    Label      = 'Driver Management'
    DiffKey    = 'DriverManagement'
    Type1File  = 'modules\type1\DriverManagementAudit.psm1'
    Type1Func  = 'Invoke-DriverManagementAudit'
    Type2File  = 'modules\type2\DriverManagement.psm1'
    Type2Func  = 'Invoke-DriverManagement'
    ConfigSkip = 'skipDriverManagement'
}
```

**A5. Add the skip flag** to `main-config.json` under `modules`, with a `_comment` explaining what
turning it off costs — every existing flag has one, and they're genuinely useful.

**A6. Decide the Stage 3 position.** `$Stage3Order` (orchestrator, ~line 496) is independent of
`$ModulePairs` order. Current order and its reasoning: `SystemConfiguration` first (it takes the
restore point, so the rollback net precedes every other mutation), then `SoftwareManagement`, then
`WindowsUpdates`, then `DiskCleanup` last (it sweeps residue the earlier stages created). Anything
not in `$Stage3Order` sorts to position 999. **Driver work belongs after the restore point and
before DiskCleanup.**

**A7. Tests.** A contract test asserting the pair resolves (Step 0.2 covers this automatically once
written generically), plus unit tests for any parser the audit introduces.

**A8. Update `CLAUDE.md`** — the pair table, and the `$Stage3Order` reasoning if you changed it.

---

### Recipe B — A new discriminator inside an existing pair ★ preferred

Much cheaper: no new files, no `$ModulePairs` entry, no new skip flag, no Stage 3 ordering
decision.

Each pair already writes **one combined diff whose items carry a discriminator tag**:

| Pair | Discriminator | Existing values |
|---|---|---|
| SoftwareManagement | `Action` | `remove` / `install` / `upgrade` |
| SystemConfiguration | `ConfigType` | `restorepoint` / `security` / `telemetry` / `optimization` |
| DiskCleanup | `Type` | `temp` / `browser` / `update` / `bin` |
| WindowsUpdates | `Type` | *(blank)* / `lifecycle` |

To add, say, scheduled-task cleanup to `SystemConfiguration`:

1. In the Type1 audit, emit items with `ConfigType = 'scheduledtasks'`.
2. In the Type2 module, add a `'scheduledtasks'` arm to the existing `switch`.
3. **Add it to `Get-ConfigItemRank`** so it sorts deterministically. This is the step people forget.
   The current ranking is load-bearing: restore-point `create` (0) must precede every mutation, and
   restore-point `remove` (4) must follow everything, because pruning first would discard the very
   rollback targets a failed run would need. Slot new work at 1–3.
4. Optionally add a sub-feature flag under `modules.systemConfiguration` in `main-config.json`,
   following `skipPasswordPolicy` / `skipAuditPolicy`.

That's it. Four edits, two files, one config key.

---

### Recipe C — A new baseline entry (no code) ★ cheapest

Edit the JSON under `config/lists/` and push to `master`. Per-area gotchas, all of them
learned the hard way:

| File | Gotcha |
|---|---|
| `bloatware-detection.json` | The per-entry `detection` array is honoured — each source only tests patterns that name it. An entry with **no** `detection` array is permissive (all four sources). Whole-vendor wildcards need `"tier": "broad"` or they'll match software the user chose (`*ASUS*` also matches `Pegasus Mail`). |
| `bloatware/dependency-matrix.json` | `dependents` values are `-like`-matched against **live package names** — prose like `"Many UWP apps"` matches nothing. Never list a **protected** package as a dependent: it can never be queued for removal, so the rule becomes unsatisfiable and permanently blocks the parent. |
| `essential-apps.json` | The per-app `timeout` is threaded through the diff as `TimeoutSeconds`. Set it for anything slow — LibreOffice needs 900. |
| `app-upgrade-config.json` | `ExcludePatterns` are matched against **both** Name and winget Id. Never write a blanket vendor pattern that also covers something `essential-apps.json` installs. |
| `security-baseline.json` | **Three sibling blocks, three different mechanisms.** `registry` → `Set-RegistryValue`; `securityPolicy` → `secedit`; `auditPolicy` → `auditpol`. **A rule in the wrong block is silently never enforced.** |
| `os-lifecycle.json` | Hand-maintained, a few entries a year. Not a CVE map — see the CLAUDE.md note on why per-CVE mapping is the wrong shape. |

Add a contract test alongside any new entry class (Step 0.2).

---

### Recipe D — A new external tool

1. Add the download URL to the Phase 4 tool registry.
2. Acquire via `Get-ExternalTool`; **handle `$null`** and degrade to `Warning`.
3. Invoke **only** through `Invoke-ExternalPackageCommand` (exit code) or `Invoke-CapturedCommand`
   (stdout). Never `Start-Process`, never bare `&`.
4. Pass every silence flag the tool has: `--silent`, `/qn`, `-Confirm:$false`, `-accepteula`,
   `-nobanner` (I2).
5. Set a **short** timeout. Audit tools: 60–180 s. Only installers get the 600 s default.
6. **Beware app-execution-alias shims.** Resolve the real binary, not the winget `Links\*.exe`
   reparse point — it fail-fast crashes with `0xC0000409` under redirected stdio.
   `Install-SysmonWithConfig` has the reference implementation.
7. **Parse defensively.** Find the header row; validate column counts against it. Never assume line 1
   is data. `ConvertFrom-WingetListTable` is the model.
8. Write a unit test against **captured real output** in `tests/fixtures/`.

### Recipe E — A new report section

1. Have the Type1 audit persist JSON to `temp_files/data/<name>.json` via
   `Get-TempPath -Category 'data' -FileName '<name>.json'`.
2. Add a `Build-<Name>Section` function in `ReportGenerator.psm1`, following
   `Build-SystemInventorySection`.
3. **Gate it on the file's existence**, matching how `system-inventory.json`,
   `restore-point-audit.json` and `system-health-report.json` are handled — a section skipped by
   config then simply doesn't render.
4. Call it from `Build-ReportHtml`.
5. Style in `assets/report.css` (Phase 3), not in a here-string.
6. If the data is slow to gather, put the gathering in **Phase B**, after `Save-DiffList` — so a
   failure can never cost the run the diff Stage 3 depends on.

### Recipe F — A new config flag

1. Add to `main-config.json` **with a `_comment`** explaining what turning it off costs.
2. Read via `Get-MainConfig`; remember it's a **hashtable** — iterate with `.Values` /
   `.GetEnumerator()` / `.Keys`, **never** `.PSObject.Properties`.
3. Default to the safe/current behaviour so an old config file keeps working.
4. Add a contract test asserting the key exists.

---

## Part 6 — The review checklist

Run this against every change before pushing to `master`. It is derived entirely from bugs this
project has actually shipped.

**Unattended safety (I2)**
- [ ] No `Read-Host`, `PAUSE`, `SET /P`, `CHOICE`, `-Confirm`, or GUI installer on any reachable path
- [ ] Every external process goes through a timeout-guarded helper
- [ ] Every timed prompt auto-proceeds; no path requires input to continue
- [ ] Batch abort paths use `TIMEOUT /T n >nul 2>&1` + `EXIT /B <code>`, never `PAUSE`
- [ ] Real waits use `ping -n`, **never** `TIMEOUT` (which returns instantly with redirected stdin)

**Contract**
- [ ] `DiffKey` matches in all three places (I5)
- [ ] Type1 doesn't write; Type2 doesn't invent work absent from the diff (I6)
- [ ] Every path returns a `New-ModuleResult`; nothing throws to the orchestrator (I3)
- [ ] `RebootRequired` set whenever the change needs a reboot to take effect — **including
      exit code 3010, and including anything queued via `PendingFileRenameOperations`**
- [ ] Feature needs no memory of a previous run (I4)

**PowerShell traps**
- [ ] No counter incremented inside `| ForEach-Object { }` — the scriptblock has its own scope, so
      `$n++` updates a throwaway copy. Use `foreach`, or derive from the finished collection.
      (`.Add()` on a `List[T]` from inside `ForEach-Object` is fine.)
- [ ] Config/baseline hashtables iterated with `.Values`/`.GetEnumerator()`/`.Keys`, never
      `.PSObject.Properties`
- [ ] No PS5.1-only cmdlets (`Checkpoint-Computer`, `Get-ComputerRestorePoint`, `Get-WmiObject`) —
      use CIM / `Invoke-CimMethod`
- [ ] AppX work goes through the `*Compat` wrappers
- [ ] Single-element arrays not accidentally unrolled on return (the `, @(...)` pattern)

**Verification honesty**
- [ ] A "success" flag is set only on **verified** success. `Invoke-AppxInWinPS` shells out with
      `2>$null`, so a failing child raises no exception in the caller — absence of an error is not
      evidence of success.
- [ ] A step that only partially achieves the goal (e.g. deprovision ≠ uninstall) does **not**
      suppress later fallback layers

**Hygiene**
- [ ] PSScriptAnalyzer clean
- [ ] Unit test added for any new parser or comparison function
- [ ] `Export-ModuleMember` lists only the public `Invoke-*` function(s)
- [ ] Logged via `Write-Log` with an uppercase `Component`, not `Write-Host`
- [ ] `CLAUDE.md` updated if you changed behaviour, ordering, or the pair table

---

## Part 7 — Named anti-patterns (the bug taxonomy)

Every one of these has shipped in this project. Give them names so they're easy to spot in review.

| Name | What it looks like | Where it bit |
|---|---|---|
| **Phantom counter** | `$n++` inside `\| ForEach-Object { }` | Per-section item counts; power-plan GUID lookup always fell through to its hard-coded default |
| **CLR member enumeration** | `.PSObject.Properties` on a hashtable enumerates `Count`/`Keys`/`Values`, not JSON keys | Bloatware protection list was a **complete no-op** |
| **Unverified success** | A helper returns nothing, so the caller treats "no exception" as success | `Remove-AppxPackageCompat`; Layer 1 always claimed removal, so Layers 3/4/5 never ran |
| **Partial-progress suppression** | A step that achieves *part* of the goal stops later fallbacks | Layer 2 deprovision set the `$removed` flag; the winget removal that actually works never ran |
| **Unsatisfiable guard** | A safety rule whose condition can never be met becomes an unconditional block | A **protected** package listed as a dependent silently blocked *every* Xbox removal, forever |
| **Wrong-block config** | A rule placed in a baseline block no code reads | CIS sections 1 and 17 were never enforced despite being in `security-baseline.json` |
| **Prose as pattern** | A config value that's English, `-like`-matched against real identifiers | `"Many UWP apps"` in `dependency-matrix.json` — matched nothing |
| **Inverted exit code** | Assuming a tool distinguishes cases it doesn't | `TIMEOUT` returns 0 for *both* keypress and expiry; only redirected stdin gives 1. The branch prompt never worked |
| **Field-order assumption** | A parser requiring fields in an order the tool doesn't emit | DISM prints `DisplayName` first; the parser required the reverse and paired every name with the *previous* record |
| **Identifier-shape mismatch** | Matching a pattern against the wrong representation | Patterns written as AppX short names matched neither winget's display Name nor its versioned Id — the whole winget source was blind to ~100 entries |
| **Default-timeout truncation** | A per-item timeout that never reaches the helper | LibreOffice's 900 s was ignored, the 600 s default killed it mid-install, reported as failure |
| **Dead-flag derivation** | Deriving a mode from a variable that means something else | `AUTO_NONINTERACTIVE` means "pwsh found", not "run non-interactively" — it silently suppressed the Stage 1 menu on every run |

**Nine of these twelve are pure-function bugs catchable by a unit test with no Windows machine
involved.** That is the entire argument for Phase 0, stated as data.

---

## Quick reference

**Adding a feature — cheapest first:**
`Recipe C (JSON only)` → `Recipe B (new discriminator)` → `Recipe A (new pair)`

**Key extension points:**

| Thing | Location |
|---|---|
| Pair registration | `MaintenanceOrchestrator.ps1` → `$ModulePairs` (~line 157) |
| Stage 3 execution order | `MaintenanceOrchestrator.ps1` → `$Stage3Order` (~line 496) |
| Intra-module ordering | `SystemConfiguration.psm1` → `Get-ConfigItemRank` |
| Shared infrastructure | `modules/core/Maintenance.psm1` (imported `-Global`) |
| Report rendering | `modules/core/ReportGenerator.psm1` |
| Behaviour flags | `config/settings/main-config.json` |
| Baseline data | `config/lists/<area>/*.json` |
| Diff handoff | `temp_files/diff/<DiffKey>-diff.json` |
| Report data | `temp_files/data/<name>.json` |

**Related documents:**
[CLAUDE.md](CLAUDE.md) · [Sysinternals_Suite_Reference.md](Sysinternals_Suite_Reference.md) ·
[SystemConfiguration_OS_Settings_Reference.md](SystemConfiguration_OS_Settings_Reference.md)
