# Tests

Phase 0 of [ARCHITECTURE_AND_EXTENSION_GUIDE.md](../ARCHITECTURE_AND_EXTENSION_GUIDE.md): the
safety net that makes every later change safe to make.

## Running them

```powershell
Install-Module Pester -MinimumVersion 5.0 -Scope CurrentUser -Force -SkipPublisherCheck

Invoke-Pester -Path .\tests -Output Detailed          # everything (~10s)
Invoke-Pester -Path .\tests\unit                      # pure functions only
Invoke-Pester -Path .\tests\contract                  # wiring + baseline data only
```

**No elevation. No system mutation. No network.** Every external dependency
(`secedit`, `auditpol`, the registry, `Get-BaselineList`) is either mocked or replaced with a
fixture, so the suite runs anywhere — including an unelevated GitHub Actions runner.

> Windows ships Pester **3.4.0** in `C:\Program Files\WindowsPowerShell\Modules`. Its syntax is
> incompatible with these tests. `Import-Module Pester -MinimumVersion 5.0` picks the right one.

## Layout

```
tests/
├── unit/         pure parse/compare functions - no I/O, no system state
├── contract/     wiring and shipped data: $ModulePairs, config/**.json
├── fixtures/     captured real-world tool output
└── PSScriptAnalyzerSettings.psd1
```

## What is covered, and why those things

The bug taxonomy in the extension guide lists twelve anti-patterns that have actually shipped in
this project. **Nine of the twelve are pure-function bugs** — parsing or comparison logic that
needed no Windows machine to catch and that silently produced wrong results for an unknown number
of monthly runs. The suite targets those first.

| File | Covers | The bug it guards |
|---|---|---|
| `unit/WingetParsing.Tests.ps1` | `ConvertFrom-WingetPackageId`, `ConvertFrom-WingetListTable` | Identifier-shape mismatch (patterns matched neither Name nor raw Id) **and single-element array unrolling — found by this suite, see below** |
| `unit/DiffEngine.Tests.ps1` | `Compare-ListDiff` | All three strategies; hashtable vs PSCustomObject inputs |
| `unit/ConfigItemRank.Tests.ps1` | `Get-ConfigItemRank` | The restore-point ordering guarantee: create first, prune last |
| `unit/LogParsing.Tests.ps1` | `ConvertFrom-MaintenanceLog` | Losslessness (launcher banners must survive as `RAW`); live read while the logger holds the file |
| `unit/SecurityPolicy.Tests.ps1` | `Compare-SecurityPolicyBaseline` | `LockoutBadCount = 0` must be **non-compliant** — 0 disables lockout entirely |
| `unit/AuditPolicy.Tests.ps1` | `Compare-AuditPolicyBaseline` | Fail-open on localised `auditpol` output — queue the item rather than skip it |
| `contract/ModulePairs.Tests.ps1` | `$ModulePairs`, `$Stage3Order`, `ConfigSkip` | The "silently does nothing" class: a broken `DiffKey` makes Stage 2 skip a pair while the run still reports success |
| `contract/BaselineJson.Tests.ps1` | everything under `config/` | Prose-as-pattern, protected-package-as-dependent, upgrade exclusions pinning an essential app |

### A bug this suite found on day one

`ConvertFrom-WingetListTable` returned `$rows.ToArray()`. PowerShell unrolls a single-element
array on return, so a one-row table handed the caller a **bare hashtable** — and `.Count` on a
hashtable reports its *key* count (3: `Name`/`Id`/`Stem`), not 1.

`Resolve-WingetIdForCandidate` keys on exactly `$rows.Count -eq 1` as its success condition. That
could never be true. Every targeted `winget list <name>` lookup instead took the `-gt 1` branch,
logged a bogus *"3 ambiguous match(es)"*, and returned `$null` — so **Pass B of the bloatware Id
resolution never resolved a single Id**, and Type2's winget-by-exact-Id removal layer never
received one.

Same bug class as the one `Get-DiffList` already carried a documented `, @()` guard for. Fixed in
`SoftwareManagementAudit.psm1`; pinned by
`Context 'REGRESSION: single-element array must not unroll'`.

## Conventions

- **Never assert against a hand-invented tool format.** Capture real output into `fixtures/`.
  `winget-list.txt` is genuine `winget list` output, curated to representative rows with the
  original column spacing byte-for-byte intact — the parser's column-count validation keys on
  `-split '\s{2,}'`, so **the spacing is the test**. Do not reformat it.
- **Reach private functions with `InModuleScope`.** Modules export only their public `Invoke-*`
  functions; the parsers under test are internal by design. Pass fixture data in with
  `InModuleScope <Module> -Parameters @{ X = $x } { param($X) ... }`.
- **Never dot-source `MaintenanceOrchestrator.ps1`.** It carries `#Requires -RunAsAdministrator`
  and executing it runs the entire five-stage pipeline against the machine. `$ModulePairs` and
  `$Stage3Order` are extracted from the AST instead — safe and side-effect free.
- **Avoid `<angle brackets>` in test names.** Pester 5+ treats `<name>` as a data placeholder and
  expands it to `$null` in the output.
- **Test what the code does, then decide if it is right.** Three of the first four contract-test
  failures were bugs in the *tests*, not the config — `protected-packages.json` has a documented
  `optional_but_safe` section that is explicitly documentation-only, and
  `Test-PackageProtected` correctly acts on `protected -eq $true` alone. Read the config's own
  comments before calling something a defect.
- **Do not mechanise a judgement call.** An early test tried to infer which bloatware patterns
  "should" be `tier: broad` from the string shape and flagged `*Minecraft*`, `*Roblox*` and
  `*Netflix*` — all legitimately-targeted single apps. Distinguishing a whole-vendor wildcard from
  a specific app is a fact about the software, not the string. That check was removed.

## Adding tests

New parser or comparison function → add a unit test in the same commit. New `$ModulePairs` entry,
config key, or baseline entry class → the contract tests mostly cover it generically already;
extend them when a new *kind* of invariant appears.

The review checklist in
[ARCHITECTURE_AND_EXTENSION_GUIDE.md](../ARCHITECTURE_AND_EXTENSION_GUIDE.md#part-6--the-review-checklist)
lists what a change should satisfy before it reaches `master`.

## CI

[`.github/workflows/ci.yml`](../.github/workflows/ci.yml) runs on push to `master`/`Testing` and
on PRs to `master`:

1. **Parse** every `.ps1`/`.psm1`/`.psd1` — parse errors fail the build.
2. **PSScriptAnalyzer** — **Errors fail** (there are none today, so the gate is real); warnings are
   reported only. ~500 pre-existing style warnings would make CI permanently red, and a
   permanently red CI is worse than no CI. Tidy them incrementally, then tighten the gate.
3. **Pester** — any failure fails the build; results upload as an NUnit XML artifact.
