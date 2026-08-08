# Project Evaluation — August 2026

Evaluated at `master` @ `0efa8a0`, working tree clean.
Gate at time of evaluation: **Pester 247/247 passed, PSScriptAnalyzer Errors 0**, repo-wide `Parser::ParseFile` clean.

Every finding below was reached twice: once by reading the code, once by an independent
check (executing the function, running the regex, tracing call sites programmatically).
Where the second check **disproved** an initial suspicion, that is recorded in
[Section 5](#5-suspicions-that-did-not-survive-verification) rather than dropped — those are
as useful as the confirmed ones, because they are the things that *look* broken and are not.

## Coverage and honesty about scope

| Area | Depth |
|---|---|
| `script.bat` | Full read, all 1555 lines |
| `MaintenanceOrchestrator.ps1` | Full read, all 5 stages + `$ModulePairs` |
| `modules/core/Maintenance.psm1` | Full function map; close read of config loading, diff engine, diff persistence, AppX/DISM/winget/auditpol/secedit parsers, `Get-InstalledApp`, `Get-OSContext` |
| Config tree (`config/**`) | Programmatic: every file parsed, every key traced to a consumer, every referenced file checked to exist |
| Four Type1/Type2 pairs | **Targeted**, not line-by-line. Traced contracts, call sites, repeated operations and the specific parsers. `SystemConfigurationAudit.psm1` (1007 lines) and `SystemConfiguration.psm1` (749) were not exhaustively read |
| `ReportGenerator.psm1`, `ConsoleUI.psm1` | **Not audited.** Out of budget for this pass |

So: treat Sections 1–3 as solid, and understand that the two report/UI modules and the deep
interiors of the SystemConfiguration pair have **not** been cleared — absence of findings
there is absence of evidence.

---

## 1. Confirmed defects

### 1.1 `Compare-ListDiff -Strategy 'Changed'` silently returns nothing for the data type the project actually uses

**Severity: high (latent) — the documented "diff engine" does not work on real config data, and has no production callers.**

[`Maintenance.psm1:604`](modules/core/Maintenance.psm1#L604) and `:616`:

```powershell
if ($found -and $found.PSObject.Properties['CurrentState'] -and $baseItem.PSObject.Properties['desiredValue'])
```

`Get-BaselineList` returns `OrderedHashtable` (verified). On a hashtable,
`.PSObject.Properties` enumerates **CLR members** — `IsReadOnly, IsFixedSize,
IsSynchronized, Keys, Values, SyncRoot, Count` — never the JSON keys. So both guards are
`$null`, both branches are skipped, and the function returns an empty diff.

This is precisely the failure mode CLAUDE.md already documents ("never `.PSObject.Properties`
… this bug had made the bloatware protection list a no-op") — still present in the shared
diff engine itself.

Verified by execution against the real module:

| Input type | Items emitted | Expected |
|---|---|---|
| `[pscustomobject]` (what the tests use) | 1 | 1 |
| `hashtable` (what `Get-BaselineList` returns) | **0** | 1 |
| `hashtable`, item absent from scan | **0** | 1 |

**Why it is not currently causing damage:** `Compare-ListDiff` has **zero production
callers**. A case-insensitive search across the repo finds it only in
`tests/unit/DiffEngine.Tests.ps1` and in three documents (`CLAUDE.md`,
`ARCHITECTURE_AND_EXTENSION_GUIDE.md`, `tests/README.md`). Every Type1 module builds its
diff by hand.

**Why that is still a problem:** all three documents present it as the central diff engine
and the extension guide tells a future contributor to use it. The first person who follows
that advice with a real baseline gets a silently empty diff — the whole pair skipped by
Stage 2, reported as "system already in desired state".

The tests do not catch it because every `Changed` test constructs `[pscustomobject]` inputs,
while `tests/README.md:43` claims the file covers "hashtable vs PSCustomObject inputs" — true
for `Present`/`Missing`, not for `Changed`.

**Fix:** replace both guards with hashtable-safe checks (`$baseItem.Contains('desiredValue')`
or a `$null -ne $baseItem.desiredValue` test that works for both shapes), and add a `Changed`
test using hashtables. Then either wire the engine into a Type1 module or mark it explicitly
as unused in the docs.

### 1.2 Windows Update KB matching uses substring/regex, not equality

**Severity: high — can silently skip a genuinely missing security update.**

[`WindowsUpdates.psm1:423`](modules/type2/WindowsUpdates.psm1#L423) extracts a **bare digit
string**:

```powershell
$kb = if ($title -match 'KB(\d+)') { $Matches[1] } else { $null }    # -> "5001234", no "KB"
```

and both [`Test-UpdateAlreadyInstalled:25`](modules/type2/WindowsUpdates.psm1#L25) and
[`Test-UpdateIsInstalled:59`](modules/type2/WindowsUpdates.psm1#L59) then do:

```powershell
Where-Object { $_.HotFixID -match $KBNumber }
```

`-match` is a **regex substring** test, not equality. Verified:

```
'KB5001234' -match 'KB5001'  ->  True      # substring
'KB5001234' -eq    'KB5001'  ->  False
```

With bare digits the collision window is wider still: an installed `KB15001234` matches a
pending `5001234`. The pre-check at line 432 then logs *"Already installed, skipping"* and
counts it as processed — a missing patch reported as applied.

Secondary: `$KBNumber` is interpolated straight into a regex, so any metacharacter would be
interpreted rather than matched literally.

**Fix:** `Where-Object { $_.HotFixID -eq "KB$KBNumber" }`, or keep the `KB` prefix at
extraction and compare with `-eq`.

### 1.3 Stage 2 reports "system already in desired state" for pairs that were never audited

**Severity: medium — the report actively misleads about the failure it should surface.**

Stage 1 has a circuit breaker that `break`s the loop after 3 consecutive Type1 failures
([`MaintenanceOrchestrator.ps1:565-569`](MaintenanceOrchestrator.ps1#L565-L569)). Stage 2
then iterates **`$pairsToAudit`** — the full list — and never consults `$SessionResults` to
learn whether the audit for a pair actually ran or succeeded
([`:591-620`](MaintenanceOrchestrator.ps1#L591-L620)).

For any pair whose Type1 failed or never ran, no diff file exists, so `Get-DiffList` returns
empty and Stage 2 emits:

```
─  <label>: no changes needed — SKIPPED
```

plus a `New-ModuleResult -Status 'Skipped' -Message 'No diff items — system already in desired state'`.

"We could not audit this" and "this is already correct" are opposite facts being reported
with the same words. On an unattended run the HTML report is the only artifact, so this is
the difference between noticing a broken audit and never knowing.

**Fix:** index `$SessionResults` by module name and, when the pair's Type1 result is
`Failed`/absent, emit `Status 'Failed'` (or `Warning`) with "Type2 not run: audit did not
produce a diff".

### 1.4 `script.bat` — stale `%VAR%` expansion inside `IF` blocks

**Severity: low (log text only), but it is a genuine expansion bug.**

Three sites set a variable with `FOR /F` and read it with `%VAR%` **in the same parenthesised
block**, so the read is expanded at parse time — before the `FOR` runs:

| Line | Code | Logs |
|---|---|---|
| [1229](script.bat#L1229) | `FOR /F ... DO SET WINGET_VERSION=%%i` then `"Winget available: %WINGET_VERSION%"` | previous/empty value |
| [1235](script.bat#L1235) | same pattern | previous/empty value |
| [1248](script.bat#L1248) | `%CHOCO_VERSION%` | previous/empty value |

**Fix:** `!WINGET_VERSION!` / `!CHOCO_VERSION!` (delayed expansion is already enabled at line 10).

### 1.5 `script.bat` — `%PS_EXECUTABLE%` inside `FOR` loops defeats the short-circuit

**Severity: low-medium — turns "first match wins" into "last match wins" and wastes process launches.**

[1402](script.bat#L1402), [1422](script.bat#L1422), [1473](script.bat#L1473) all guard loop
bodies with `IF "%PS_EXECUTABLE%"==""` **inside** a `FOR ... DO ( ... )`. The whole `FOR` is
one command, so `%PS_EXECUTABLE%` is expanded once, at parse time. Once the loop sets it in
iteration 0, iterations 1..n still execute and **overwrite** it.

Consequence: the ordered preference list (`Program Files` → `x86` → `LocalAppData` →
`chocolatey`) does not hold — the *last* existing path wins — and each surplus iteration
launches `pwsh.exe` twice more to read the version.

The equivalent top-level guards ([1356](script.bat#L1356), 1392, 1419, 1439, 1468, 1495) are
correct; only the three inside `FOR` are affected.

**Fix:** `IF "!PS_EXECUTABLE!"==""`.

### 1.6 `script.bat` — unreachable dead code

[1509-1530](script.bat#L1509-L1530) is a 22-line error block guarded by
`IF "%PS_EXECUTABLE%"==""`. The identical condition at [1495](script.bat#L1495) already
`EXIT /B 1`s, so line 1509 can never be true.

Related: the `ELSE` at [1682-1692](script.bat#L1682-L1692) is also effectively unreachable —
every `SET "PS_EXECUTABLE=..."` site is paired with `SET "AUTO_NONINTERACTIVE=YES"` (verified
at 1322/23, 1345/46, 1366/67, 1382/83, 1408/09, 1428/29, 1455/56, 1483/84), and 1495 exits
when `PS_EXECUTABLE` is empty, so the `IF "%AUTO_NONINTERACTIVE%"=="YES"` at
[1612](script.bat#L1612) is always true.

That coupling is fragile in a specific way: adding a new `PS_EXECUTABLE` assignment without
also setting `AUTO_NONINTERACTIVE` would make the launcher silently take the error branch and
never start the orchestrator. `AUTO_NONINTERACTIVE` is also a misnomer — CLAUDE.md documents
that it means "pwsh was found", yet it is named for interactivity and is doing duty as the
launch gate. This is the same naming confusion that previously suppressed the Stage 1 menu.

### 1.7 Password-policy coverage is narrower than the docs claim

**Severity: medium — CIS rules the documentation says are enforced are silently not enforced.**

[`Compare-SecurityPolicyBaseline:880-887`](modules/core/Maintenance.psm1#L880-L887) supports
exactly six settings:

```
PasswordHistorySize, MinimumPasswordAge, MinimumPasswordLength,
LockoutDuration, ResetLockoutCount, LockoutBadCount
```

`security-baseline.json` → `securityPolicy` declares those same six (plus
`NewAdministratorName`/`NewGuestName`, which CLAUDE.md documents as deliberately not applied,
and a `_comment`). So there is no declared-but-unsupported gap — good.

But three standard `[System Access]` policies in the same CIS section are **absent from both**
the rules table and the baseline:

| Setting | Typical CIS requirement |
|---|---|
| `MaximumPasswordAge` | 365 or fewer days, **and not 0** |
| `PasswordComplexity` | Enabled |
| `ClearTextPassword` | Disabled |

CLAUDE.md's coverage table says the `securityPolicy` block covers "1.1 password, 1.2 lockout".
`MaximumPasswordAge` in particular has the same "not 0" trap already handled for
`LockoutBadCount` (0 means *never expires*, which fails the benchmark while looking like a
large compliant number is unnecessary) — so it needs a comparison direction of its own, not
just a new key.

**Fix:** add the three keys to the baseline and to `$rules`, giving `MaximumPasswordAge` an
`AtMostNonZero`-style rule and the two booleans an exact-match rule. Until then, either narrow
the claim in CLAUDE.md or close the gap.

---

## 2. Actions executed more than once

These are all confirmed by tracing real call sites (comments and string literals excluded).

### 2.1 PowerShell 7 is fully detected twice, and the first result is discarded

- **Block 1** — [954-1153](script.bat#L954-L1153), "4-tier verification" + three install methods → sets `PS7_EXECUTABLE`.
- **Block 2** — [1281-1530](script.bat#L1281-L1530), six further fallback methods → sets `PS_EXECUTABLE`.

`PS7_EXECUTABLE` is referenced **only** at [1137](script.bat#L1137) and
[1149](script.bat#L1149), both purely to emit a log line. The actual launch at
[1678](script.bat#L1678) uses `PS_EXECUTABLE`.

So block 1's detection result is thrown away and block 2 re-derives it from scratch, costing
up to ~12 additional `pwsh.exe -Command "$PSVersionTable..."` process launches on a cold run.
Only block 1's *install* side effects matter.

### 2.2 The orchestrator path is resolved twice, with two different failure exit codes

- [628-638](script.bat#L628-L638) sets `ORCHESTRATOR_PATH`, `EXIT /B 3` if missing.
- [655](script.bat#L655) — `SET "ORCHESTRATOR_PATH="` wipes it.
- [659-670](script.bat#L659-L670) re-resolves from `%WORKING_DIR%` (same directory), failing via `STRUCTURE_VALID=NO` → `EXIT /B 4`.

Same condition, two code paths, two exit codes. The first block is dead work.

### 2.3 `Get-InstalledApp` runs twice per run; the second call is used only for a count

`Get-InstalledApp` enumerates three registry uninstall hives **and** the full AppX package
list (which spawns a `powershell.exe` 5.1 child via `Invoke-AppxInWinPS`).

Two real call sites:
- [`SoftwareManagementAudit.psm1:738`](modules/type1/SoftwareManagementAudit.psm1#L738) — the legitimate one; the result is threaded into the detection sources.
- [`SystemConfigurationAudit.psm1:452`](modules/type1/SystemConfigurationAudit.psm1#L452) — `$inv.Software = @{ InstalledAppCount = @(Get-InstalledApp).Count }`.

The second pays the entire cost (6 hive enumerations total across the run, 2 child processes)
to produce a single integer for the report's inventory section.

**Fix:** have `SoftwareManagementAudit` publish the count (or the array) to
`temp_files/data/`, or cache `Get-InstalledApp` per session.

### 2.4 `Win32_QuickFixEngineering` is enumerated twice per pending update

[`WindowsUpdates.psm1:432`](modules/type2/WindowsUpdates.psm1#L432) (pre-check) and
[`:459`](modules/type2/WindowsUpdates.psm1#L459) (post-verify) are both inside
`foreach ($update in $normalUpdates)`, and each calls a helper that does a full
`Get-CimInstance -ClassName Win32_QuickFixEngineering`.

With N pending updates that is up to **2N** enumerations of one of the slowest WMI classes on
Windows. The two helpers (`Test-UpdateAlreadyInstalled` at line 20, `Test-UpdateIsInstalled`
at line 50) are also near-duplicates of each other.

**Fix:** enumerate the hotfix list once before the loop and test against the in-memory set;
collapse the two helpers into one.

### 2.5 `auditpol.exe` is launched once per subcategory

[`Compare-AuditPolicyBaseline:1023`](modules/core/Maintenance.psm1#L1023) runs
`auditpol.exe /get /subcategory:"$sub" /r` **inside** the `foreach ($entry in @($Baseline))`
loop. With the 18 subcategories the baseline declares, that is 18 process launches per audit.
`auditpol /get /category:* /r` returns all of them in one call.

### 2.6 winget is probed 8+ times; one whole detection pass is unused

`winget --version` is executed at [759](script.bat#L759), 789, 799, 827, 875, 882, 1226 and
1232. The re-probes inside the install section are justified (verify after each method), but
the "Verifying package managers" block at [1225-1251](script.bat#L1225-L1251) is an entirely
separate detection pass whose only output is the (mis-expanded, see §1.4) log line.

`Repair-WinGetPackageManager -AllUsers -Force -Latest` also runs on **every** invocation
([933](script.bat#L933)), plus an `Install-Module Microsoft.WinGet.Client` when absent —
documented as best-effort, but it is a heavy unconditional monthly operation.

### 2.7 Smaller repeats

| What | Where | Note |
|---|---|---|
| Scheduled-task query + "Task To Run" log | [395-408](script.bat#L395-L408) and [1264-1269](script.bat#L1264-L1269) | Same `schtasks /Query` twice |
| `TASK_NAME` / `STARTUP_TASK_NAME` assigned | [274](script.bat#L274)+[1261](script.bat#L1261), [386](script.bat#L386)+[1260](script.bat#L1260) | Harmless redundancy |
| `Get-MainConfig` | 5 runtime sites (orchestrator + 3 audits + DiskCleanup) | No caching — `main-config.json` re-read and re-parsed each time |
| `Win32_OperatingSystem` | `Get-OSContext:383` and `SystemConfigurationAudit:318` | Two CIM queries; different fields needed, so defensible |
| `Get-OSContext` logging | Emits `"OS detected: …"` on every call | Guarded by `$global:OSContext` fallbacks, so normally once — but it is a logging side effect in a getter |

---

## 3. Inconsistencies and format/parsing observations

### 3.1 Two independent winget-table parsers with divergent rules

| | `Get-WingetUpgrade` (core) | `ConvertFrom-WingetListTable` (audit) |
|---|---|---|
| Divider regex | `'^-+'` (1+ dash) | `'^-{3,}'` (3+ dashes) |
| Column floor | `-ge 4` | `-ge 2` |
| Carries `Stem` | no | yes |

Both solve the same problem (winget has no machine-readable list output) with the same
technique, in two places, with different tolerances. Not a bug today, but a change to winget's
table format needs fixing twice, and the looser `'^-+'` would treat a data row beginning with
a hyphen as a divider.

### 3.2 `Save-DiffList` writes no file for an empty diff, but logs that it saved one

[`Maintenance.psm1:1120-1121`](modules/core/Maintenance.psm1#L1120-L1121). Piping an empty
array into `ConvertTo-Json` produces no output, so `Set-Content` creates nothing — verified.
The next line unconditionally logs `"Diff saved: <path> (0 items)"`. Harmless (nothing
survives between runs, and `Get-DiffList` handles the missing file correctly) but the log
asserts something that did not happen.

### 3.3 `auditpol` CSV parsing is positional and locale-dependent

[`Maintenance.psm1:1027-1037`](modules/core/Maintenance.psm1#L1027-L1037) splits on `,` and
takes `$cols[4]`, matching English inclusion strings. This is *documented* as deliberate
(unmatched → item queued anyway, and `auditpol /set` is idempotent), and the fallback is
sound. Noting it only because a naive "fix" that trusted the parse would break it.

### 3.4 Launcher exit-code map has a collision

`EXIT /B 3` is used for network/download failure, extraction failure, *and* "no orchestrator
found in extracted files" ([637](script.bat#L637)); `EXIT /B 4` is used for the same
"orchestrator missing" condition detected 20 lines later. A caller cannot distinguish
"GitHub unreachable" from "zip extracted but incomplete".

### 3.5 The monthly task's result never reflects the run

[1678-1681](script.bat#L1678-L1681) uses `START` then `EXIT /B 0` immediately, so the
scheduled task reports success the moment the launcher detaches — regardless of what the
orchestrator subsequently does. Deliberate (it is what lets the launcher exit so the
orchestrator can overwrite `script.bat`), but it means Task Scheduler's "Last Run Result" is
not a health signal for this system.

---

## 4. What is in good shape

Worth stating explicitly, because these are the parts that would be easy to "fix" and break:

- **Config integrity is clean.** All 13 JSON files parse; all 12 baseline files under
  `config/lists/` are referenced by code; no orphaned files; and **all 21 leaf keys** in
  `main-config.json` are consumed somewhere in non-test code. `bloatware-list.json` is a
  documented legacy fallback, not dead weight.
- **No duplicate function definitions** anywhere across `modules/`.
- **The `DiffKey` contract holds** across `$ModulePairs`, `Save-DiffList` and `Get-DiffList`.
- **The 1-element JSON collapse is genuinely handled.** `ConvertTo-Json` serialises a
  single-item array as a bare object, and `Get-DiffList`'s `, @($items)` correctly restores
  `.Count = 1` — verified by round-tripping 1, 2 and 3 item diffs.
- **The DISM provisioned-package parser is correct** — `DisplayName` is latched and the record
  emitted when `PackageName` arrives, matching DISM's actual field order.
- **Stage 5's Defender-exclusion teardown is well designed** — defined outside the `try` so
  `finally` can always reach it, idempotent via `$script:DefenderExclusionsRemoved`, and run
  before the reboot countdown so an aborted reboot cannot leave the exclusion behind.

---

## 5. Suspicions that did not survive verification

Recorded so nobody re-opens them.

| Suspicion | Verdict |
|---|---|
| `Save-DiffList`/`Get-DiffList` mangle a 0-item diff (first test showed `.Count = 2`) | **False.** My test used `1..0`, which in PowerShell counts *down* and yields 2 elements. Re-tested in isolation: empty diff → no file → `Get-DiffList` returns 0. Correct. |
| `Publish-MaintenanceReport` writes `$script:reportFile` but Stage 5 reads `$reportFile` — scope mismatch | **False.** `try` does not create a scope in PowerShell; the script-level `$reportFile` *is* `$script:reportFile`. |
| `main-config.json` has declared-but-unread keys | **False.** All 21 leaf keys traced to a consumer. |
| Some baseline JSON is orphaned | **False.** All 12 referenced. |
| Duplicate function definitions across modules | **False.** None. |

---

## 6. Suggested order of work

1. **§1.2 KB matching** — smallest change, highest consequence (a skipped security update is silent and permanent until the next run).
2. **§1.3 Stage 2 mislabelling** — cheap, and it is what makes every other failure visible.
3. **§1.1 `Compare-ListDiff`** — either fix the hashtable guards *and* add a hashtable `Changed` test, or delete it and correct the three documents that advertise it. Leaving it as-is is the trap.
4. **§2.4 / §2.5 / §2.3** — the repeated-work items, in that order; each is a contained change with a measurable win on slow machines.
5. **§1.4 / §1.5 / §1.6** — the `script.bat` expansion bugs and dead code. Low individual impact, but this is the one file with no test coverage and the largest blast radius, so it benefits most from being tidy.
6. **§2.1 / §2.2** — collapsing the duplicated detection blocks in the launcher. Highest line-count reduction, but touch it last and with the six-check discipline; it is the file where a mistake ends unattended operation everywhere.

Not covered by this pass and worth a follow-up: `ReportGenerator.psm1`, `ConsoleUI.psm1`, and
a line-by-line read of the `SystemConfiguration` pair.
