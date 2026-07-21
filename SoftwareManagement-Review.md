# SoftwareManagement (Type1/Type2) — Deep Review & Enhancement Proposals

**Scope:** `modules/type1/SoftwareManagementAudit.psm1`, `modules/type2/SoftwareManagement.psm1`,
every config file they consume (`config/lists/bloatware/*`, `config/lists/essential-apps/*`,
`config/lists/app-upgrade/*`), the shared diff engine and AppX/winget helpers in
`modules/core/Maintenance.psm1`, and the orchestrator wiring that determines when this pair runs
relative to the rest of Stage 3.

**Method:** full read-through of both modules and all six config files line by line, cross-checked
against the core helpers they call (`Compare-ListDiff`, `Save-DiffList`/`Get-DiffList`,
`Get-AppxPackageCompat`/`Get-AppxProvisionedPackageCompat`, `Resolve-WingetPath`,
`Invoke-ExternalPackageCommand`), plus external research into comparable open-source debloat
tooling and current WinGet CLI capabilities (July 2026) to sanity-check design choices that looked
unusual in isolation.

**Note on document history:** CLAUDE.md references a `SoftwareManagement-Evaluation.md` that
catalogued "open follow-ups (WinGet.Client module, essential-app matching, unused cascade
config)" — that file no longer exists in the repo. This review re-derives those same three items
independently from the code (see Findings 2, 6, 7) and confirms they're all still open, plus adds
several more.

---

## 1. How the pair actually works today

### 1.1 Detection (Type1 — `Invoke-SoftwareManagementAudit`)

One audit produces **one combined diff** (`DiffKey = SoftwareManagement`) tagged with an `Action`
discriminator (`remove` / `install` / `upgrade`) that Type2 switches on. Three independent
sub-audits run in sequence and append to the same list:

1. **Remove (bloatware).** `Get-BloatwareFromAllSources` scans four independent sources — AppX
   (`Get-AppxPackageCompat -AllUsers`), provisioned packages
   (`Get-AppxProvisionedPackageCompat`), the uninstall registry keys (`Get-InstalledApp`), and
   `winget list` (parsed from its fixed-width table, matched on the split-out Name/Id columns,
   never the raw line) — against every pattern in `bloatware-detection.json`. Each match is run
   through `Test-CanRemovePackage`, deduplicated into one hashtable keyed by lowercase name, and
   the surviving items become `Action = 'remove'` diff entries carrying a `Sources` string (e.g.
   `"AppX,Provisioned"`) and, when available, a `WingetId`.
2. **Install (essential apps).** For each entry in `essential-apps.json`, checks
   `Get-InstalledApp` output for a name substring match, then (only if that fails) an exact
   `winget list --id <id> --exact` check. Anything not found becomes `Action = 'install'`.
3. **Upgrade.** Queries `winget upgrade --include-unknown` (via `Get-WingetUpgrade`) and, if
   enabled, `choco outdated`, filtering both against `ExcludePatterns` in
   `app-upgrade-config.json`.

### 1.2 Safety gate — `Test-CanRemovePackage`

Every bloatware candidate, from every source, is checked against two config files before it's
allowed into the diff:

- `protected-packages.json` — three sections (`critical_dependencies`, `essential_system`,
  `optional_but_safe`), each a map of package-id-or-wildcard → `{ protected, reason, severity }`.
  Only entries with `protected: true` block removal.
- `dependency-matrix.json` — a `dependencies` map with the same shape, plus a `cascade_safety`
  block.

The `.Values`/`.GetEnumerator()` iteration pattern here is deliberate and well-commented — it's
the fix for a real historical bug (iterating `.PSObject.Properties` on a hashtable silently
returns CLR members instead of JSON keys, making protection checks a no-op). That fix is correct
and doesn't need to change.

### 1.3 Removal (Type2 — `Remove-BloatwareLayered`)

A four-layer waterfall, each layer only attempted if the previous one didn't report success:
**AppX** → **Provisioned** → **Registry** (silent-uninstall only — `QuietUninstallString`, or an
MSI GUID via `msiexec /x /qn`; anything else is skipped rather than risking an unattended hang)
→ **WinGet** (only if a `WingetId` was resolved during audit). Install and Upgrade phases follow,
each with a winget-then-choco fallback chain and specific exit-code handling (e.g.
`-1978335212`/`NO_APPLICATIONS_FOUND` is correctly treated as "not winget-managed, skip" rather
than a failure — this is a good, non-obvious piece of exit-code knowledge already encoded).

### 1.4 What the diff engine is *not* used for here

`Compare-ListDiff` (the generic `Present`/`Missing`/`Changed` engine documented in CLAUDE.md as
"the diff engine") is **not called anywhere in this pair**. Both modules hand-roll their own
comparison logic instead. That's a reasonable choice given the multi-source nature of bloatware
detection (there's no single "baseline vs scanned" list — it's four heterogeneous sources merged
and deduplicated), but it means the generic engine's guarantees (case-insensitive matching,
consistent `Present`/`Missing` semantics) don't apply here, and any future change to
`Compare-ListDiff` won't be visible to this pair either way. Worth knowing so nobody assumes
`Compare-ListDiff`'s behavior when reading this module.

---

## 2. Findings, ranked by impact

### Finding 1 — HIGH — Restore point is created *after* bloatware removal and system hardening, not before

This is outside the two SoftwareManagement files but is the single highest-leverage safety issue
for bloatware removal specifically, so it leads the list.

`MaintenanceOrchestrator.ps1:486` fixes Stage 3's execution order:

```powershell
$Stage3Order = @('SystemConfiguration', 'SoftwareManagement', 'WindowsUpdates', 'RestorePoint', 'DiskCleanup')
```

`RestorePointAudit.psm1` **unconditionally** queues a `create` action every single run
(`modules/type1/RestorePointAudit.psm1:74-79` — there's no condition around it, unlike the
`remove` items which only appear past the 5-point threshold). So a restore point is always going
to be created if the pair isn't skipped — but it happens **fourth**, after `SystemConfiguration`
(registry/security/Sysmon changes) and `SoftwareManagement` (bloatware removal, installs,
upgrades) have already mutated the system. The restore point that gets created this run captures
*post-change* state, not the pre-change state it's meant to protect. If a bloatware removal goes
wrong (e.g. a Layer 3 registry uninstall silently breaks a shared dependency the pattern didn't
account for), there is no fresh rollback point from before that run — only whatever a *prior*
run left behind, if one exists.

**Fix:** move `'RestorePoint'` to the front of `$Stage3Order`. This is a one-line, low-risk change
with a real safety payoff, and it benefits every Type2 module, not just SoftwareManagement.

One caveat worth knowing: `RestorePointManagement.psm1` creates the point via
`Checkpoint-Computer` (`modules/type2/RestorePointManagement.psm1:55`), which is subject to
Windows' built-in System Restore throttle (effectively one new restore point per calendar day
under default policy). So the ordering fix matters most for the *first* run of a given day —
which, given CLAUDE.md's description of a monthly scheduled task, is the common case anyway.

### Finding 2 — HIGH — `dependency-matrix.json`'s cascade/dependents logic is entirely unused

`Test-CanRemovePackage` (`SoftwareManagementAudit.psm1:18-55`) only ever reads
`$Dependencies['dependencies']` and checks `entry.Value.protected -eq $true` — exactly the same
shape of check as `protected-packages.json`. It never reads `dependents`, `cascadeRisk`, or the
top-level `cascade_safety.safe_to_cascade` block. Concretely:

- `Microsoft.Xbox*` in `dependency-matrix.json` is marked `"protected": false` but
  `"cascadeRisk": "High"` with three named `dependents` — none of that risk annotation ever stops
  anything, because the code only checks `protected`.
- The entire `cascade_safety.safe_to_cascade` array (5 entries asserting "no dependents, safe to
  remove alongside its parent") is pure documentation with no code path reading it.

This means the file currently does exactly what `protected-packages.json` does, at roughly a third
the coverage, and the richer metadata it carries (dependents, cascade risk tiers) is decorative.
This is the exact "unused cascade config" item CLAUDE.md's now-deleted evaluation doc flagged —
confirmed still true.

**Fix — pick one:**
1. Wire it up: before removing a package, check whether any of its declared `dependents` are
   *also* present on the system and *not* independently queued for removal — if so, downgrade to
   a warning or require the dependent to be removed in the same pass. This is the actual value
   the file promises.
2. Or, if that's more complexity than the project wants, delete the unused fields
   (`dependents`, `cascadeRisk`, `cascade_safety`) so the config stops documenting protection
   that doesn't exist — a reader currently has no way to tell this is inert without reading the
   PowerShell.

### Finding 3 — MEDIUM — No local-override layer survives `script.bat`'s self-update

Per CLAUDE.md's own architecture section, every real run re-downloads the entire repo from
GitHub's `master` branch as a zip and runs the extracted copy. That means `config/lists/bloatware/
protected-packages.json`, `dependency-matrix.json`, and `essential-apps.json` are **all
overwritten on every run** unless the customization was pushed to `master`. For a tool whose
config is explicitly meant to be tuned per-machine (a technician might reasonably want to protect
one extra vendor tool on a specific client's PC, or add a site-specific essential app), there is
currently no way to do that without either forking the repo or losing the change on the next run.

**Fix:** support an optional override layer outside the self-updated tree — e.g. a
`local-overrides/` folder next to `script.bat` (in `ORIGINAL_SCRIPT_DIR`, which the launcher
already threads through and which survives re-extraction since it's the *launch* location, not
the extracted copy) that `Get-BaselineList` merges on top of the shipped baseline when present.
Even a minimal version — one `protected-packages-local.json` that just adds more `protected: true`
entries — would close the gap for the highest-risk case (a technician's config being silently
discarded).



### Finding 5 — MEDIUM — Essential-apps "already installed" check is substring-first, exact-match-second, and the substring check is fragile

`SoftwareManagementAudit.psm1:317-324`:

```powershell
$foundByName = $installedNames | Where-Object { $_ -like "*$appNameLow*" }
if ($foundByName) { continue }

$wingetId = $app.winget
if ($hasWinget -and $wingetId) {
    $null = & (Resolve-WingetPath) list --id $wingetId --exact ...
    if ($LASTEXITCODE -eq 0) { continue }
}
```

The **less precise check runs first** and short-circuits the more precise one. Registry
`DisplayName` values frequently don't literally contain the config's `name` string as a substring
even when the app clearly is installed — e.g. `essential-apps.json`'s `"Java Runtime Environment"`
versus a real-world registry entry like `"Java(TM) SE Runtime Environment 8u401"` or
`"Java 8 Update 401"`. Neither contains the substring `"java runtime environment"` (the `"SE"` and
reordering break it), so the exact winget check — which *would* correctly recognize it as
installed — is never reached because... actually in this specific failure mode the substring
check fails too, so it falls through to the winget check, which is fine *if* winget is available
and the app was originally installed via winget. If it wasn't (pre-installed by the OEM, or
installed via the vendor's own installer), neither check recognizes it and the audit queues a
redundant `install`. The practical impact is low-severity (winget install/upgrade against an
already-present app usually just no-ops or updates it) but it's wasted work and log noise every
run, and it's the kind of bug that erodes trust in the report's "N items to install" count.

**Fix:** flip the order — try the precise `winget list --id --exact` check first when a
`winget` id is known, and use the name-substring match only as a fallback when winget is
unavailable or the app has no winget id.


### Finding 8 — LOW — WinGet fallback (Layer 4) can never fire for Registry-only detections

`Remove-BloatwareLayered`'s Layer 4 requires a pre-resolved `$WingetId`
(`SoftwareManagement.psm1:122`), but `WingetId` is only ever populated when the *audit's* WinGet
source independently matched the same package (`SoftwareManagementAudit.psm1:171-188`). A package
detected **only** via the Registry source (no WinGet correlation) and whose Layer 3 silent
uninstall attempt fails (e.g. an interactive-only installer) has no path to Layer 4 even though
`winget uninstall --name "<PackageName>"` might well succeed against the same package under a
different but discoverable ID.

**Fix:** add a name-based fallback attempt (`winget uninstall --name "$PackageName" --silent
--disable-interactivity`, treating a "no package found" exit code as a clean skip) when
`$WingetId` wasn't resolved, rather than skipping Layer 4 outright.

### Finding 9 — LOW — Redundant `Get-InstalledApp` scans within one audit run

`Get-InstalledApp` (full registry + AppX rescan) is called once inside
`Get-BloatwareFromAllSources`'s Source 3, and called **again** independently in the essential-apps
section (`SoftwareManagementAudit.psm1:304`). Both scans happen within the same
`Invoke-SoftwareManagementAudit` call, seconds apart, against a system that hasn't changed
in between.

**Fix:** scan once at the top of `Invoke-SoftwareManagementAudit` and pass the result into both
sub-audits. Minor performance win, but free and simple.

### Finding 10 — LOW — `winget list`/`winget upgrade` text-table parsing is fragile by necessity, not by choice — worth hardening, not replacing

I checked this against current Microsoft documentation rather than assuming: as of the
[official `winget list` docs (dated July 2026)](https://learn.microsoft.com/en-us/windows/package-manager/winget/list),
`winget list` still has **no JSON/CSV output option** — there is no `--output`/`-o` flag in the
current option table, confirming a
[long-standing feature request (winget-cli#3051)](https://github.com/microsoft/winget-cli/issues/3051)
for machine-readable list output is still unresolved. `winget export` does produce JSON, but per
[Microsoft's own docs](https://learn.microsoft.com/en-us/windows/package-manager/winget/export)
it only includes packages winget can match to a known source catalog — it silently excludes
Store apps and anything winget can't correlate, which is precisely the "unknown" software this
audit most needs to see. So the project's current double-space-split parsing of `winget list`'s
table
(`SoftwareManagementAudit.psm1:160-169`, `Maintenance.psm1:1130-1146`) is **the correct approach
given the tooling**, not a shortcut that should be replaced outright.

Two things are worth doing anyway:
1. Harden the split: a package with no available `Source` column (common for non-winget-sourced
   entries `winget list` still displays) shifts the column count, and the code's
   `$cols.Count -ge 2` guard is loose enough that a shifted `Id` column could silently be read
   into the wrong field. Validate column count against the header row's column boundaries rather
   than a blanket `-ge 2`.
2. Longer-term, evaluate the official **`Microsoft.WinGet.Client`** PowerShell module
   (`Get-WinGetPackage`/`Install-WinGetPackage`/`Uninstall-WinGetPackage`), which returns
   structured objects instead of parsed text. It's a genuine option, but it has a documented
   history of failing under the exact same elevated/non-interactive execution context this
   orchestrator always runs in (`#Requires -RunAsAdministrator`) — the module's cmdlets go through
   COM activation of the packaged WinGet app, which is the same class of App-Execution-Alias
   problem `Resolve-WingetPath`'s doc comment already describes working around for the raw CLI.
   Don't adopt it without testing specifically under an elevated, non-interactive PS7 session
   first — it could reintroduce the exact failure mode `Resolve-WingetPath` was written to avoid.

### Finding 11 — LOW — `choco outdated` parsing should force `--limit-output`

`SoftwareManagementAudit.psm1:376` calls `choco outdated --no-progress --no-color` and parses
lines matching `^(\S+)\|(\S+)\|(\S+)`, which assumes Chocolatey's pipe-delimited format. Chocolatey
is a secondary/optional path here (gated behind `Test-CommandAvailable 'choco'`, and most
consumer/small-business Windows machines this project targets won't have it installed at all), so
this is low priority — but explicitly passing `--limit-output` (or `-r`) guarantees the
pipe-delimited format regardless of Chocolatey version or locale, rather than relying on
default-format assumptions holding across versions.

### Finding 12 — LOW — `protected-packages.json`'s `essential_system`/`optional_but_safe` sections protect packages that are never proposed for removal anyway

`Microsoft.WindowsCalculator`, `Microsoft.WindowsNotepad`, `Microsoft.WindowsTerminal`,
`Microsoft.ScreenSketch` (all `essential_system`), and `Microsoft.Paint`, `Microsoft.People`,
`Microsoft.WindowsAlarms` (`optional_but_safe`) don't appear as removable patterns anywhere in
`bloatware-detection.json`. The protection is real defense-in-depth (it'd catch a future config
edit that carelessly adds one of these), but as it stands today it's guarding against a scenario
that can't currently occur — worth knowing so nobody mistakes "it's in protected-packages.json"
for "it's reachable by the current pattern set." No action needed beyond awareness; this is exactly
the kind of protective redundancy that's cheap to keep.

### Finding 13 — LOW — `bloatware-list.json` (legacy v4.0 format) is dead weight

`bloatware-list.json`'s ~250 entries are only consulted as a fallback when
`bloatware-detection.json` is missing or has no `categories` key
(`SoftwareManagementAudit.psm1:242-260`). Since `bloatware-detection.json` v6.0 ships in the repo
and supersedes it (denser categorization, per-app `detection` source hints, notes), the legacy
file is unreachable in normal operation. Either document it explicitly as an intentional
"config corrupted/missing" safety net, or retire it — as-is, a reader has to trace the fallback
logic to learn which of the two ~250-entry files is actually live.

### Finding 14 — LOW — `toolbars_extensions` category targets extinct 2010s-era PUPs

`Ask.AskToolbar`, `Babylon.BabylonToolbar`, `*Conduit*` were common browser-toolbar bundleware
circa 2012–2016 and are essentially extinct on any machine that could run current Windows 10/11.
Not harmful to keep (matching is cheap and dependent-free), but if this category is ever revisited,
today's equivalent PUP landscape (bundled "PC cleaner" installers, ad-injecting browser
extensions bundled with cracked-software installers, etc.) would be higher-value additions than
maintaining decade-old toolbar signatures.

---

## 3. Prioritized action list

| # | Finding | Effort | Impact |
|---|---|---|---|
| 1 | Reorder `$Stage3Order` — RestorePoint first | Trivial (1 line) | High — safety net for every Type2 module |
| 2 | Wire up `dependency-matrix.json` cascade logic | Small–Medium | High — closes a documented-but-fake safety guarantee |
| 5 | Try winget-exact before name-substring in essential-apps audit | Small | Medium — removes false "missing" noise |
| 4 | Tier/gate broad OEM wildcard patterns behind an opt-in flag | Medium | Medium — prevents removing software the user wants |
| 3 | Local-override layer for config surviving self-update | Medium | Medium — makes per-machine tuning viable at all |
| 7 | Post-run removal/install/upgrade manifest | Small | Medium — audit trail, groundwork for dry-run |
| 6 | "Declined app" memory for essential-apps | Medium | Low–Medium — stops fighting deliberate uninstalls |
| 9 | Reuse one `Get-InstalledApp` scan per audit run | Trivial | Low (perf only) |
| 8 | Name-based WinGet fallback (Layer 5) | Small | Low |
| 10 | Harden winget table column-count validation | Small | Low |
| 11 | Add `--limit-output` to `choco outdated` | Trivial | Low |
| 13 | Retire or explicitly document `bloatware-list.json` fallback | Trivial | Low (clarity only) |

Items 1 and 2 are the two I'd actually schedule first: #1 is a one-line orchestrator change with
an outsized safety improvement, and #2 closes a gap this project's own prior documentation had
already flagged but left unresolved.

---

## 4. Sources consulted

- [Win11Debloat — App Removal wiki](https://github.com/Raphire/Win11Debloat/wiki/App-Removal) —
  comparison point for exact-match-only removal design vs. this project's broader wildcard
  patterns.
- [`winget list` command reference (Microsoft Learn)](https://learn.microsoft.com/en-us/windows/package-manager/winget/list) —
  confirmed no structured-output option exists as of July 2026.
- [`winget export` command reference (Microsoft Learn)](https://learn.microsoft.com/en-us/windows/package-manager/winget/export) —
  confirmed its catalog-matching limitation rules it out as a `winget list` replacement for this
  use case.
- [winget-cli issue #3051 — machine-readable `winget list` output](https://github.com/microsoft/winget-cli/issues/3051) —
  status of the long-standing feature request.
