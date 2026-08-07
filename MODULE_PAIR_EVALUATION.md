# Module Pair Evaluation — Findings

**Date:** 7 August 2026
**Scope:** each Type1/Type2 pair examined individually — how the two halves interact with each
other, with `main-config.json`, and with the baseline lists under `config/lists/`.
**Method:** static analysis only. No conclusions drawn from the dev PC's machine state
(see CLAUDE.md → *Rule 3: the dev PC is not the test machine*).

**Result: 5 findings.** One can silently discard a completed audit; two are unenforced security
controls; two are dead config. Two of the five are defects I introduced in Phase 4.

---

## Summary

| # | Finding | Severity | Origin | Area |
|---|---|---|---|---|
| [1](#1-softwaremanagement-can-silently-lose-its-entire-diff) | `SoftwareManagement` can silently lose its entire diff | **High** | Pre-existing | Pair contract |
| [2](#2-configskip-flags-do-not-do-what-the-config-says) | `ConfigSkip` flags don't gate Type1, only Type2 | **Medium** | Pre-existing | Orchestrator ↔ config |
| [3](#3-two-defender-protections-are-declared-but-never-enforced) | Two Defender protections declared, never enforced | **Medium** (security) | Pre-existing | Baseline ↔ audit |
| [4](#4-visualeffects-baseline-is-ignored-in-favour-of-a-hardcoded-value) | `visualEffects` baseline ignored; value hardcoded | **Low** | Pre-existing | Baseline ↔ audit |
| [5](#5-three-dead-config-keys) | Three dead config keys | **Low** | 2 of 3 mine | Config |

**Recommended fix order: 1 → 3 → 2 → 4 → 5.** The diff-loss risk first, then the unenforced
security controls, then the misleading skip flags, then cosmetics.

---

## 1. `SoftwareManagement` can silently lose its entire diff

**Severity: High** · `modules/type1/SoftwareManagementAudit.psm1`

### What is wrong

`Invoke-SoftwareManagementAudit` (starts line 663) calls `Save-DiffList` exactly **once, at
line 918** — at the very end of the function, with the whole body wrapped in a single
`try/catch` (catch at line 934).

Execution order inside that one try block:

```
bloatware detection   4 sources, bulk `winget list`, AppX via the PS5.1 compat layer,
                      up to 40 targeted winget lookups, dedup, cascade-safety, Id resolution
essential-apps scan   per-app `winget list --id --exact`
upgrade scan          shells out to `winget upgrade` AND `choco outdated`
--------------------- ^ anything above throws -> catch at 934 -> NOTHING is saved
Save-DiffList         line 918
```

If any step in that tail throws, the catch fires, **no diff file is written at all**, Stage 2
sees zero items, and Stage 3 skips `Invoke-SoftwareManagement` entirely. Every completed
bloatware detection result is discarded.

### Why this matters

The tail depends on **two external package managers**. `winget upgrade` and `choco outdated`
are exactly the kind of call that fails in novel ways — and one of them failing throws away
work that had already succeeded and is the most valuable output of the module.

### This contradicts an established project principle

The sibling pair already solves this, and CLAUDE.md documents why:

> **Type1 `SystemConfigurationAudit`** runs *Phase A* … and **calls `Save-DiffList` at the end
> of Phase A**, then runs *Phase B*, the slow report-only gathering … Persisting the diff before
> Phase B means a failure while collecting report data can never cost the run the diff Stage 3
> depends on.

`SoftwareManagementAudit` does not follow this. The asymmetry looks accidental rather than
chosen — there is no comment defending it.

### Suggested fix

Split the save, mirroring the Phase A/Phase B shape:

1. `Save-DiffList` immediately after bloatware detection + cascade-safety + Id resolution.
2. Run the essential-apps and upgrade scans inside their own `try/catch`, each degrading to a
   `Warning` on the module result rather than propagating.
3. `Save-DiffList` again with the full set.

Saving twice is cheap — it is one `ConvertTo-Json` to a file under `temp_files/diff/`.

---

## 2. `ConfigSkip` flags do not do what the config says

**Severity: Medium** · `MaintenanceOrchestrator.ps1:524` · `config/settings/main-config.json`

### What is wrong

`main-config.json` states:

> `skipSoftwareManagement`/`skipSystemConfiguration`/`skipDiskCleanup`/`skipWindowsUpdates`
> **gate a whole Type1+Type2 pair** (checked by the orchestrator in Stage 2).

They do not. The check exists **only in Stage 2**:

```powershell
# MaintenanceOrchestrator.ps1:524
$configSkip = if ($pair.ConfigSkip -and $Config.modules.$($pair.ConfigSkip)) { $true } else { $false }
```

Stage 1 iterates `$pairsToAudit` and invokes `Type1Func` with **no `ConfigSkip` check at all**.
The two clauses in that sentence contradict each other: if it is checked in Stage 2, Type1 has
already run.

### Impact

Setting `skipSoftwareManagement = true` still performs the entire audit — four detection
sources, a bulk `winget list`, AppX enumeration through the PS5.1 compat layer, up to 40
targeted winget lookups, plus the essential-app and upgrade scans. It writes its diff JSON and
data JSON. Only then is the result discarded.

Minutes of work per skipped pair, and files written for a pair the operator explicitly turned
off. Not incorrect behaviour, but wasteful and actively contradicted by the documentation.

### Suggested fix

Gate Stage 1 as well — this is clearly the intent. Add the same check before
`Invoke-ModuleFunction` runs `Type1Func`, and emit a `Skipped` Type1 result so the report still
accounts for the pair. Failing that, correct the `_comment` to say the flags gate the **action**
half only.

> Note: a **missing** `ConfigSkip` key defaults safely to "do not skip" (`$null -and …` → false),
> and `tests/contract/ModulePairs.Tests.ps1` already asserts every declared key exists and is a
> boolean. That part is sound.

---

## 3. Two Defender protections are declared but never enforced

**Severity: Medium (security)** · `config/lists/security/security-baseline.json` ·
`modules/type1/SystemConfigurationAudit.psm1`

### What is wrong

The `windowsDefender` block declares **six** settings. The audit compares **four**.

| Baseline setting | Compared? | Audit line |
|---|---|---|
| `realTimeProtection` | ✅ | 575 |
| `cloudProtection` | ✅ | 588 |
| `networkProtection` | ✅ | 591 |
| `pua` | ✅ | 594 |
| **`automaticSampleSubmission`** | ❌ **never** | — |
| **`controlledFolderAccess`** | ❌ **never** | — |

No diff item is ever emitted for those two, so no Type2 code path can apply them. They are
inert config: the run reports success while the settings stay whatever the machine had.

### Why this matters

This is precisely the failure class CLAUDE.md already records for the non-registry CIS areas:

> `securityPolicy` and `auditPolicy` were declared in the baseline but **no module read them**,
> so every CIS section 1 and 17 rule stayed non-compliant no matter how many times the run
> succeeded.

Same shape, two settings later. **Controlled Folder Access is ransomware protection** — the most
consequential of the six on a machine this project is meant to harden.

### The data is already being read

`modules/type2/SystemConfiguration.psm1` (pre-change state backup, ~line 440) already selects
both values from `Get-MpPreference`:

```powershell
Select-Object DisableRealtimeMonitoring, MAPSReporting, EnableNetworkProtection,
              PUAProtection, EnableControlledFolderAccess, SubmitSamplesConsent
```

So the properties are known and reachable. Only the comparison and the apply arm are missing.

### Suggested fix

In `Get-SecurityConfigurationDiff`, extend the existing `Get-MpPreference` block:

- `automaticSampleSubmission` → compare `$mpPrefs.SubmitSamplesConsent`
- `controlledFolderAccess` → compare `$mpPrefs.EnableControlledFolderAccess`

emitting the same `ConfigType='security'; Type='defender'` item shape as the other four, and add
the matching `$feature` arms in `Invoke-ConfigurationItem`'s Defender switch.

⚠️ **Controlled Folder Access needs care before enabling by default.** It blocks unrecognised
apps from writing to protected folders and generates support friction. It also has to be
compatible with this project's own file operations — DiskCleanup writes and deletes under user
profile paths. Consider gating it behind a `main-config.json` flag defaulting to off, in the same
spirit as `skipPasswordPolicy`.

---

## 4. `visualEffects` baseline is ignored in favour of a hardcoded value

**Severity: Low** · `config/lists/system-optimization/system-optimization-config.json` ·
`modules/type1/SystemConfigurationAudit.psm1:807-812`

### What is wrong

The baseline declares six visual settings:

```json
"visualEffects": {
  "preset": "balanced",
  "disableAnimations": true,
  "disableShadows": true,
  "enableSmoothEdges": true,
  "enableShowWindowContents": true,
  "disableTransparency": true
}
```

The audit reads **none** of them:

```powershell
# SystemConfigurationAudit.psm1:807-812
$visualPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects'
$currentVisual = Get-RegistryValue -Path $visualPath -Name 'VisualFXSetting'
if ($null -eq $currentVisual -or $currentVisual -ne 3) {
    $items.Add(@{ ConfigType = 'optimization'; Type = 'visualfx'; Name = 'VisualFXSetting'
                  CurrentState = $currentVisual; DesiredState = 3 })
}
```

`VisualFXSetting = 3` is Windows' **Custom** preset — not `balanced`, which is what the baseline
asks for. The five boolean sub-settings are never applied at all.

### Credit where due — the neighbouring blocks get this right

In the same file, `registryTweaks` (windows10 and windows11) and `uiOptimizations` carry:

```json
"_status": "not-implemented — no audit/apply path exists yet"
```

Those are **honestly labelled placeholders and are not bugs.** `visualEffects` carries no such
marker, so it reads as implemented when it is not. That inconsistency is the actual defect.

### Suggested fix

Cheapest honest option: add the same `_status` marker to `visualEffects` and leave the hardcoded
behaviour, documenting that only the master preset is applied.

Fuller option: read `preset` and map it to the correct `VisualFXSetting` value
(`0` = let Windows choose, `1` = best appearance, `2` = best performance, `3` = custom), and
apply the five booleans to their `UserPreferencesMask` / individual registry values.

---

## 5. Three dead config keys

**Severity: Low** · declared in `main-config.json`, read by nothing.

| Key | Origin | Detail |
|---|---|---|
| `tools.verifySignature` | **Mine (Phase 4)** | Never read. `Get-ExternalTool` has a `-SkipSignatureCheck` switch, but nothing wires the config flag to it. Setting it `false` does nothing; verification is always on. |
| `tools.sysinternals.handle.*` | **Mine (Phase 4)** | Declared `enabled` + `url` for the Handle lock-diagnostic, but Phase 5 only implemented MoveFile. The config advertises a feature that does not exist. |
| `reporting.enableHtmlReport` | Pre-existing | Its **only** occurrence is inside `Get-MainConfig`'s built-in defaults fallback (`Maintenance.psm1:440`). Stage 4 never checks it, so setting it `false` does not suppress the report. |

### Suggested fix

- `tools.verifySignature` — wire it: pass `-SkipSignatureCheck:(-not $cfg.tools.verifySignature)`.
  Given the value of that gate, consider removing the key instead and keeping verification
  mandatory.
- `tools.sysinternals.handle` — either implement the Handle diagnostic (it turns a silent
  `RMDIR` failure into a named process, see `Sysinternals_Suite_Reference.md` §5.2) or remove the
  block until it exists.
- `reporting.enableHtmlReport` — either honour it in Stage 4 or delete it. Note the report is the
  only artifact that survives Stage 5, so an operator who disables it gets **no record of the run
  at all**; if honoured, that consequence deserves a `_comment`.

---

## What came back clean

Most of the surface held up. Worth recording so it is not re-checked needlessly.

**Diff-field contracts — no orphans in any pair.** Every field a Type2 reads off `$item` is
produced either by its Type1 or by a shared `Compare-*` helper in `Maintenance.psm1`. All 17
`SystemConfiguration` fields traced to a producer:

| Produced in the audit | Produced in a core helper | Both |
|---|---|---|
| `Action`, `ConfigType`, `Feature`, `GUID`, `Profile`, `RegistryPath`, `ShadowId`, `ShouldEnable`, `TaskName`, `TaskPath` | `DesiredValue`, `Path`, `ValueName` | `Description`, `DesiredState`, `Name`, `Type` |

**`WindowsUpdates` lifecycle discriminator is correct.** Type2 splits properly at lines 407–408
(`$_.Type -ne 'lifecycle'` / `-eq 'lifecycle'`) and dispatches lifecycle items to their own
handler with an unknown-action guard. An earlier grep suggested Type2 only read `Action` and
`Name`; that was a false alarm from the `$_` vs `$item` form.

**`DiskCleanup` pair is tight.** All six fields (`Type`, `Name`, `Path`, `SizeMB`, `Drive`,
`ResetBase`) are both produced and consumed, with no drift.

**`$scope` is genuinely used.** `SoftwareManagement.psm1:553` assigns it and line 575 consumes it
into `--scope user|machine` — not an assigned-and-forgotten variable.

**Missing `ConfigSkip` keys fail safe.** `$Config.modules.$absent` → `$null` → not skipped, and
the contract tests already assert every declared key exists and is boolean.

**winget "already installed" exit codes are handled.** `SoftwareManagement.psm1:579` treats
`0`, `-1978335135` and `-1978335189` as success, so an already-present package is not counted as
a failure.

---

## Method and limits

**How this was done:** mechanical producer/consumer extraction across all four pairs (diff fields
written by Type1 vs read by Type2), a declared-vs-read sweep of every key in `main-config.json`
and every top-level key in `config/lists/**/*.json`, then targeted reading of the call sites that
sweep flagged.

The automated sweeps produce false positives on **data** keys — package names in
`protected-packages.json`, category names in `bloatware-detection.json`, version keys in
`os-lifecycle.json` — because those are iterated generically rather than referenced by name.
Every finding above was confirmed by reading the actual code path; nothing here rests on the
sweep alone.

**Not examined — candidates for a follow-up pass:**

- `DiskCleanupAudit`'s size-estimation maths against Type2's reclaim reporting (the `freedMB =
  SizeMB - remainingMB` calculation and its category breakdown).
- The Stage 1 circuit breaker's interaction with Stage 2. If it trips after 3 consecutive Type1
  failures, later pairs' audits never run, so their diffs never exist and their Type2s are
  silently skipped with a "no changes needed" message that is not strictly true. Plausible but
  unverified.
- Ordering *within* `SoftwareManagement`'s Type2 (remove → install → upgrade) against the diff
  order it receives.
- `telemetry-list.json`'s `scheduledTasks.disable` entries against live task paths — that needs
  the VM, not this PC.

**Environment note:** every finding is static-analysis based, per CLAUDE.md Rule 3. None of it
depends on the dev PC's installed software or Windows state. Anything requiring live state is
listed above as unverified rather than guessed at.
