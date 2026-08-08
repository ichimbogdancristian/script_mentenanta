# Project Evaluation — Pass 2 (diff engine, logging engine, report generator)

Companion to `PROJECT-EVALUATION-2026-08.md`. That pass covered `script.bat`, the
orchestrator, config integrity and repeated work. **This pass covers what that one did not**:
the logging engine end to end, the diff engine end to end, `ReportGenerator.psm1`, and a
sweep for the project's own documented recurring bug classes.

Evaluated at branch `Testing` @ `da0f8ef`, tree clean apart from the two evaluation docs.

Every finding here was produced twice: once by reading, once by **executing** the code —
running the real functions, generating a real report, testing PowerShell scope semantics
directly. Section 4 lists the things that looked broken and provably are not; three of my own
initial suspicions died there, and one of them killed a rule in CLAUDE.md.

---

## 1. New confirmed defects

### 1.1 `Get-ExceptionCategory`: the `Network` category is unreachable, and the function is dead

**Severity: low-medium (dead code today, wrong if revived).**

[`Maintenance.psm1:307`](modules/core/Maintenance.psm1#L307) captures the type as
**`.GetType().Name`** — unqualified:

```powershell
$exceptionType = $exception.GetType().Name        # 'WebException', not 'System.Net.WebException'
```

but [`:320`](modules/core/Maintenance.psm1#L320) then tests namespace-qualified patterns:

```powershell
elseif ($exceptionType -match 'Net.Http|Net.WebException|TimeoutException') { 'Network' }
```

`'WebException'` cannot match `'Net.WebException'`. The only alternative that *can* match is
`TimeoutException` — which the preceding branch at `:314` already claimed for `'Timeout'`. So
**no input can ever reach `Network`.**

Verified by executing the real function:

| Thrown | `.Name` | Category | Severity |
|---|---|---|---|
| `System.Net.WebException` | `WebException` | **Unknown** | Medium |
| `System.Net.Http.HttpRequestException` | `HttpRequestException` | **Unknown** | Medium |
| `System.UnauthorizedAccessException` | `UnauthorizedAccessException` | Permission | High |

A network failure — on a system whose whole first stage depends on reaching GitHub — is
classified `Unknown`/`Medium` instead of `Network`/`High`, and gets the generic suggestion
"Check error details and logs" instead of "Check network connectivity and retry".

**It is also never called.** Zero call sites anywhere outside its own definition and the
export list.

**Fix:** either use `.FullName` (and drop the duplicate `TimeoutException` alternative), or
match on bare names (`'WebException|HttpRequestException|SocketException'`). Then either wire
it into `Write-LogException` or delete it.

### 1.2 The KB substring-match defect is at **four** sites, not two

Pass 1 reported `-match` instead of `-eq` for KB numbers at `WindowsUpdates.psm1:26` and `:60`.
The sweep found two more, in the registry fallback layers:

| Line | Code |
|---|---|
| [26](modules/type2/WindowsUpdates.psm1#L26) | `Where-Object { $_.HotFixID -match $KBNumber }` |
| [38](modules/type2/WindowsUpdates.psm1#L38) | `Where-Object { $_.GetValue('DisplayName') -match $KBNumber }` |
| [60](modules/type2/WindowsUpdates.psm1#L60) | `Where-Object { $_.HotFixID -match $KBNumber }` |
| [73](modules/type2/WindowsUpdates.psm1#L73) | `Where-Object { $_.GetValue('DisplayName') -match $KBNumber }` |

Lines 38 and 73 are worse than 26/60: a registry `DisplayName` is free text like
*"Security Update for Microsoft Windows (KB5001234)"*, so a bare-digit `-match` against it
will match **any** update whose display name happens to contain that digit run anywhere.

Same fix, applied four times: compare `-eq "KB$KBNumber"`, or for `DisplayName` use a
bounded pattern such as `-match "\bKB$KBNumber\b"`.

### 1.3 `Set-LogLevel` silently ignores an invalid level name

[`Maintenance.psm1:127-136`](modules/core/Maintenance.psm1#L127-L136):

```powershell
if ($Console -and $script:LevelRank.ContainsKey($Console.ToString().ToUpper())) { ... }
```

A value not in the rank table is dropped with no warning and no fallback. The orchestrator
feeds this straight from config
([`MaintenanceOrchestrator.ps1:173`](MaintenanceOrchestrator.ps1#L173)):

```powershell
Set-LogLevel -Console $Config.logging.consoleLevel -File $Config.logging.fileLevel
```

So a typo in `main-config.json` (`"TRACE"`, `"Verbose"`, `"warn "` with a trailing space) is a
silent no-op — the operator believes they changed log verbosity and nothing happened. Given
the log is the primary diagnostic for unattended runs, a silently ignored logging setting is
worth a `WARN`.

**Fix:** log a `WARN` naming the rejected value and the accepted set.

### 1.4 `INFO` and `SUCCESS` share a rank, so they cannot be gated apart

[`Maintenance.psm1:81`](modules/core/Maintenance.psm1#L81):

```powershell
$script:LevelRank = @{ DEBUG = 10; INFO = 20; SUCCESS = 20; WARN = 30; ERROR = 40; FATAL = 50 }
```

Not a bug — but it means `consoleLevel: "SUCCESS"` behaves identically to `"INFO"`, which is
not obvious from the config. Worth a comment in `main-config.json` or distinct ranks.

### 1.5 Ten of 45 core exports have no production consumer

Traced programmatically across all non-test, non-core files:

| Export | Consumed by |
|---|---|
| `Get-ExceptionCategory` | **nothing at all** (and defective — §1.1) |
| `Compare-ListDiff` | tests only (and defective for hashtables — pass 1 §1.1) |
| `Initialize-LogFile` | core-internal only |
| `Invoke-AppxInWinPS` | core-internal only (correct — CLAUDE.md says always use the `*Compat` wrappers) |
| `Get-SecurityPolicyExport`, `Get-PerUserRegistryRoot`, `Resolve-UserRegistryPath`, `Invoke-CapturedCommand`, `Resolve-ExternalToolPath`, `Test-MicrosoftSignedBinary` | core-internal + tests |

Most are harmless over-exporting of internal helpers. The two that matter are the two that
are **dead and defective at the same time** — nothing exercises them, so nothing reveals that
they do not work.

### 1.6 `script.bat` diverged between `Testing` and `master` again, immediately

`git diff origin/master -- script.bat` is non-empty right now. `master` carries a six-line
verbose form of the leftover-folder removal (with `DEBUG` log lines); `Testing` has the terse
two-line form.

Functionally equivalent, so nothing is broken — but it is the exact pattern CLAUDE.md warns
about on `master` ("`Testing` is a manual push target, not an auto-synced mirror … this has
already bitten once"), reproducing within a day of the merge that fixed it. It also means
every line number in pass 1 (taken on `master`) is off by 6 relative to `Testing`; the
re-anchored numbers are in §5.

**Fix:** after any `Testing → master` merge, immediately merge `master` back into `Testing`.

---

## 2. The diff engine — verified sound

This was a primary target of this pass. I checked it at three levels; **it holds at all three.**

### 2.1 Discriminator contract: every value produced is consumed

| Pair | Type1 emits | Type2 dispatch |
|---|---|---|
| SoftwareManagement | `Action` = remove / install / upgrade | all three, via `-eq` |
| SystemConfiguration | `ConfigType` = restorepoint / security / telemetry / optimization; `Type` = restorepoint / visualfx / defender / firewall / service / registry / scheduledtask / powerplan / startup / sysmon / secpolicy / auditpolicy; `Action` = create / remove | all handled |
| DiskCleanup | `Type` = temp / browser-cache / browser-cookies / update-cleanup / recyclebin | all five |
| WindowsUpdates | `Type` = lifecycle; `Action` = advance-feature-version / attempt-esu-enrollment | both |

No orphaned producer value, no unreachable consumer branch.

### 2.2 Unknown discriminators are loud, not silent

Every Type2 has a `default` branch that logs a `WARN` **and increments the failure count** —
[`DiskCleanup.psm1:268`](modules/type2/DiskCleanup.psm1#L268),
[`SystemConfiguration.psm1:476/562/612/719/726`](modules/type2/SystemConfiguration.psm1#L726),
[`WindowsUpdates.psm1:371`](modules/type2/WindowsUpdates.psm1#L371). A future producer/consumer
mismatch would surface in the report as a failure rather than as a silently skipped item.
This is the single most important property of the design and it is correctly implemented.

### 2.3 Field contract: every field Type2 reads is written by Type1

Cross-checked per pair. All fields resolve, including the ones written inline inside
single-line `$items.Add(@{ ... })` calls (`Feature`, `ShouldEnable`, `Profile`, `GUID`,
`RegistryPath`, `TaskName`, `TaskPath`) and the ones produced by the shared core helpers
`Compare-RegistryBaseline` / `Compare-SecurityPolicyBaseline` (`Path`, `ValueName`,
`DesiredValue`). **No contract gaps in any of the four pairs.**

### 2.4 Persistence round-trip

Re-confirmed from pass 1: `ConvertTo-Json` collapses a one-item array to a bare JSON object,
and `Get-DiffList`'s `, @($items)` correctly restores `.Count = 1`. Empty diffs write no file
and read back as an empty array.

The one blemish is cosmetic: [`Save-DiffList:1121`](modules/core/Maintenance.psm1#L1121) logs
`"Diff saved: <path> (0 items)"` for an empty list even though no file was written.

---

## 3. The logging engine — verified sound

The other primary target. Also holds.

### 3.1 Format agreement across all three layers

| Layer | Format |
|---|---|
| `script.bat` `:LOG_MESSAGE` | `[%LOG_TIME%] [%COMPONENT%] [%LEVEL%] msg` |
| `Write-Log` (file sink) | `[$ts] [$Component] [$Level] $Message` |
| `ConvertFrom-MaintenanceLog` regex | `^\[(?<ts>[^\]]+)\]\s\[(?<cmp>[^\]]+)\]\s\[(?<lvl>[^\]]+)\]\s?(?<msg>.*)$` |

The launcher and the orchestrator write the **same** format into the **same** file, and the
parser accepts both. The console sink deliberately differs (symbol instead of `[LEVEL]`) and
is never parsed.

Level vocabularies also agree: `script.bat` emits `DEBUG, ERROR, INFO, SUCCESS, WARN`;
`Write-Log` accepts those plus `FATAL`; `Build-LogConsole` orders
`FATAL, ERROR, WARN, SUCCESS, INFO, DEBUG, RAW`. **No launcher level is unknown to the report.**

### 3.2 Live round-trip

Wrote through the real logger and parsed with the real parser. 6/6 entries recovered:

| Input | Parsed |
|---|---|
| `DEBUG` / `CORE` / normal text | ✅ |
| message containing `[with] brackets` | ✅ not truncated |
| message containing `:` and a stray `]` | ✅ |
| **empty** message | ✅ `Message = ''` |
| launcher banner `====…` | ✅ `Level = RAW`, preserved |
| launcher-style short timestamp `[9:05:03]` | ✅ parsed; `ShortTs` falls back to the full stamp |

That last row matters: `script.bat` derives its timestamp from `%TIME%`, which has **no
leading zero** for single-digit hours, so launcher lines carry `9:05:03` while orchestrator
lines carry `09:05:03`. The parser's `ts` group is `[^\]]+`, so both parse; only the
fixed-width `ShortTs` regex (`\d{2}:\d{2}:\d{2}`) declines to shorten the launcher form. Purely
cosmetic — worth knowing before someone "tightens" that regex and breaks every launcher line.

### 3.3 Lifecycle

`Initialize-LogFile` calls `Close-LogFile` first (safe re-open); `Close-LogFile` is idempotent
and null-guards; the writer is `AutoFlush = $true` over a `FileShare.ReadWrite` stream, which
is what lets the report embed the log live. Stage 5 closes the handle before deleting the
folder, and the `finally` block closes it again on every crash path. **Correct.**

---

## 4. ReportGenerator — verified sound (previously unaudited)

Generated a **real report end to end** from deliberately hostile input: module names, messages
and error strings containing `<script>`, `<img src=x>`, `<b>`, `&` and `"`, plus log lines with
the same.

| Check | Result |
|---|---|
| raw `<script>alert` in output | **0** |
| raw `<img src=x>` in output | **0** |
| raw `<script>bad` (module name) | **0** |
| raw `<i>err</i>` (error string) | **0** |
| escaped `&lt;script&gt;` | 4 |
| escaped `&lt;img src=x&gt;` | 5 |
| CSS / JS inlined | 1 `<style>`, 1 `<script>` block |
| report produced | 26,298 bytes, self-contained |

`ConvertTo-HtmlText` escapes `&` first (correct order) and is applied at **56** call sites,
including both `Message` and `Component` in the log console. `Get-ReportAsset` degrades to an
empty string with a `WARN` when `assets/report.css|js` is missing, so a missing asset produces
an unstyled report rather than no report — consistent with the "the HTML report is the only
surviving artifact" priority.

---

## 5. Suspicions that did not survive verification

These are the highest-value part of this pass: three things that look like bugs, are not, and
one **documented mandatory rule that is itself wrong**.

### 5.1 CLAUDE.md's `ForEach-Object` scope rule is factually incorrect

CLAUDE.md, "Conventions", states as a hard rule:

> **Never increment a counter inside `| ForEach-Object { }`.** The pipeline scriptblock gets
> its own scope, so `$n++` there updates a throwaway copy and the outer variable stays at 0.

**That is not how PowerShell behaves.** Verified directly:

| Construct | Result |
|---|---|
| `$n = 0; 1..3 \| ForEach-Object { $n++ }` | `$n` = **3** ✅ outer updated |
| `$a = @(); 1..3 \| ForEach-Object { $a += $_ }` | `Count` = **3** ✅ |
| same, inside a function | `events=3 cnt=3` ✅ |
| `ForEach-Object` nested inside `foreach` inside a function (the exact shape at `SystemConfigurationAudit.psm1:134-149`) | **4** ✅ |
| **`ForEach-Object -Parallel`** | `$p` = **0** ❌ — *this* is the real failure mode |

A plain `ForEach-Object` script block does **not** get an isolated scope for writes; only
`-Parallel` (separate runspaces), `Start-Job`, and `Invoke-Command` do. This codebase uses
**none** of those — searched, zero matches.

Consequences:

- `SystemConfigurationAudit.psm1:141` (`$events += @{...}`) and `:181` (`$incidents += @{...}`)
  are flagged by the rule but are **correct**. Do not "fix" them.
- The rule will send future contributors on pointless refactors, and — worse — will make them
  stop looking when they hit a real bug in a `ForEach-Object` block, having "found" the cause.
- CLAUDE.md attributes two past silent bugs to this mechanism. I cannot say what actually
  caused those two (that history is not recoverable from the current tree), only that the
  mechanism as described is not real for the non-parallel form. The likely true culprits in
  that shape are `$_` shadowing in a nested pipeline, or a value being read before the
  pipeline that produces it has run.

**Fix:** rewrite the rule to name the actual boundary (`-Parallel` / jobs / remoting, which
need `$using:`), or delete it. Leaving it as a "not negotiable" rule that is wrong is the
worst of the three options.

### 5.2 `.PSObject.Properties` at `SystemConfigurationAudit.psm1:792` is correct

The sweep flagged it as the documented hashtable bug class. It is not:

```powershell
$props.PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' }
```

`$props` here comes from `Get-ItemProperty` on a registry key, which returns a
**`PSCustomObject`**, not a hashtable. Enumerating `.PSObject.Properties` and filtering the
`PS*` housekeeping members (`PSPath`, `PSParentPath`, `PSChildName`, `PSDrive`, `PSProvider`)
is the standard, correct way to list registry values. The genuine instances of that bug class
remain only the two in `Compare-ListDiff` (pass 1 §1.1).

### 5.3 DiskCleanup Type2 does handle all five cleanup types

An initial extraction suggested Type2 dispatched only on `recyclebin`. It does not — the other
branch uses a set form my pattern missed:

```powershell
switch ($type) {
    { $_ -in 'temp', 'browser-cache' } { ... }
    'browser-cookies' { ... }
    'update-cleanup'  { ... }
    'recyclebin'      { ... }
    default           { <WARN + failure> }
}
```

All five producer values are covered. **No gap.**

### 5.4 SystemConfiguration diff fields are not missing

An initial cross-check reported seven fields (`Feature`, `GUID`, `Profile`, `RegistryPath`,
`ShouldEnable`, `TaskName`, `TaskPath`) as read-but-never-written. All seven **are** written —
inline inside single-line `$items.Add(@{ ... })` calls that my line-anchored pattern skipped.
No contract gap.

---

## 6. Consolidated priority across both passes

| # | Finding | Pass | Severity |
|---|---|---|---|
| 1 | KB matched with `-match` (substring) at **4** sites — can skip a real security update | 1 §1.2 + 2 §1.2 | **High** |
| 2 | `Compare-ListDiff -Strategy 'Changed'` returns nothing for hashtables; dead + advertised in 3 docs | 1 §1.1 | **High** (latent) |
| 3 | CLAUDE.md `ForEach-Object` rule is factually wrong | 2 §5.1 | **High** (misleads all future work) |
| 4 | Stage 2 reports "already in desired state" for pairs that were never audited | 1 §1.3 | Medium |
| 5 | Password-policy coverage narrower than documented (`MaximumPasswordAge`, `PasswordComplexity`, `ClearTextPassword`) | 1 §1.7 | Medium |
| 6 | `Get-ExceptionCategory` `Network` unreachable + dead | 2 §1.1 | Low-medium |
| 7 | `Set-LogLevel` silently ignores invalid levels | 2 §1.3 | Low-medium |
| 8 | Repeated work: 2× PS7 detection, 2× `Get-InstalledApp`, 2N× QFE, 18× `auditpol` | 1 §2 | Low-medium (time) |
| 9 | `script.bat` expansion bugs + dead code | 1 §1.4-1.6 | Low |
| 10 | `Testing`/`master` divergence recurring | 2 §1.6 | Low (process) |

### Re-anchored `script.bat` line numbers for the `Testing` branch

Pass 1's numbers were taken on `master`, which is 6 lines longer. On `Testing` @ `da0f8ef`:

| Finding | master | **Testing** |
|---|---|---|
| Stale `%WINGET_VERSION%` / `%CHOCO_VERSION%` | 1229, 1235, 1248 | **1223, 1229, 1242** |
| `%PS_EXECUTABLE%` inside `FOR` | 1402, 1422, 1473 | **1396, 1416, 1467** |
| Unreachable duplicate guard | 1509 | **1503** |

---

## 7. Coverage of this pass

| Area | Depth |
|---|---|
| Logging engine (write + parse + lifecycle) | **Full**, with live round-trip |
| Diff engine (produce → persist → consume → discriminate) | **Full**, all 4 pairs, contract-checked |
| `ReportGenerator.psm1` | **Full** on escaping/assets/end-to-end; individual `Build-*` section builders read but not exhaustively |
| Recurring bug-class sweep | **Full** across all non-test `.ps1`/`.psm1` |
| Core export surface | **Full** (45 exports traced) |
| `ConsoleUI.psm1` | **Still not audited** — it is orchestrator-only console formatting, no system side effects, so it remains the lowest-risk gap |
| `SystemConfiguration.psm1` / `SystemConfigurationAudit.psm1` interiors | Contract- and pattern-level, still not line-by-line |

`ConsoleUI.psm1` and the deep interiors of the SystemConfiguration pair remain the only
material gaps across both passes.
