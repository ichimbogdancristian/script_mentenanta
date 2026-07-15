# Proposed Execution Timeline (Reorganization Proposal)

**What this is:** a from-scratch proposal for how this project's execution sequence *could* be restructured — not a description of what exists today (see [`timeline.md`](timeline.md) for that). This is a design proposal, not yet implemented. Every change below is justified against something concrete observed while building the current-state timeline: a real wasted spawn, a real serial dependency that isn't actually a dependency, a real redundant computation, or a real design contradiction already flagged in [`docs/Comprehensive-Project-Analysis-2026-07-15.md`](docs/Comprehensive-Project-Analysis-2026-07-15.md).

I have the latitude to move tasks between modules, merge modules, and split modules — I've used that latitude where it produces a real win, not for its own sake. Where the current design is already correct (diff-gated Type2 execution, the Type1/Type2/diff shape itself, config-driven module skipping), I kept it.

---

## Design goals, in priority order

1. **Two reboot decisions, each honored for its own reason, never confused with each other.** The launcher's pre-flight check exists so the orchestrator starts on a clean slate (a machine with an already-pending Windows Update reboot is not a trustworthy audit target); Stage 5's reboot exists to act on *this run's own* changes. Both are legitimate and neither should be collapsed into the other — that was an earlier, incorrect draft of this proposal, corrected below (A'3).
2. **Pay for expensive setup (restore points, Defender exclusions, external process spawns) only when there's something to protect or something to do.** Several expensive steps run unconditionally today, even on a fully clean machine with zero pending actions.
3. **Stop spawning the same external tool multiple times for the same information.** `winget` gets invoked from at least four different, uncoordinated call sites across a single run.
4. **Parallelize the genuinely independent work, serialize the genuinely conflicting work — explicitly, not by accident.** Stage 1 and Stage 3 are pure sequential `foreach` loops today even though most of what's inside them doesn't share state. But `winget` itself does not tolerate concurrent invocations well, so "just parallelize everything" would trade a slow bug for a flaky one — the plan below draws that line deliberately.
5. **Symmetric setup/teardown.** Anything the launcher turns on for the duration of a run (Defender exclusions, restore points) should be turned back off by the same run, not left permanently.
6. **Group functions by what they touch on the OS, not by which feature domain asked for it.** Three separate Type2 modules each contain their own copy of "here's how you write a registry value" and "here's how you toggle a service." That's not three different problems, it's one mechanism implemented three times. Section "Impact-Based Function Grouping" below is the concrete version of this goal — it names exactly which functions, in which files, are duplicates of each other, and where they should live instead.

---

## Part A' — Launcher, reorganized

The current launcher (`script.bat`, ~1430 lines) interleaves four genuinely different concerns in one linear sequence: *identity/elevation*, *acquisition* (download the latest code), *environment preflight* (make sure the tools this run needs exist), and *scheduling* (register recurring/resume tasks). Untangling those into named phases doesn't just read better — it's what makes the concurrency in Phase A'4 below safe to reason about.

### A'1. Bootstrap & Elevate (unchanged from today, this part is already right)
Self-discovery, UAC elevation **with `%*` forwarded this time** (fixes the dropped-arguments bug), admin confirmation.

### A'2. Acquire (unchanged from today, this part is already right)
Download → extract → self-update → structure validation. This is a naturally serial chain (each step depends on the previous succeeding); no reorganization needed.

### A'3. Clean-slate reboot gate (**unchanged from today — this part is already correct, kept as-is**)

An earlier draft of this proposal argued for collapsing this into Stage 5. That was wrong, and worth explaining why, since it's the kind of mistake that looks reasonable on the page and isn't: this check exists specifically so the **orchestrator and its Type1/Type2 modules run on a clean slate**. A machine with a Windows-Update reboot already pending — from something that happened before this tool ever started — is not a trustworthy starting point for an audit: services can be mid-restart, update state is in flux, and anything Stage 1 measures on that machine may already be stale by the time Stage 3 acts on it. This is a *precondition* for the orchestrator to run at all, not a *result* of what the orchestrator does. Deferring it to Stage 5 would mean letting the orchestrator run on the dirty machine first and only rebooting afterward — defeating the entire point of the check.

The current implementation is already correctly scoped and needs no change: it checks four authoritative Windows-Update signals (`Get-WURebootStatus`, plus three `RebootRequired`/`PostRebootReporting` registry markers), and only reboots if one of them is actually set. On a machine with no pending update reboot, the check costs a few registry reads and one optional PowerShell module call, then falls straight through — no reboot, no delay, no ONLOGON task created.

**What this means for the rest of this document:** there remain **two** legitimate reboot decision points in this design — this pre-flight gate (launcher, "is the machine already dirty") and Stage 5 (orchestrator, "did this run's own changes require a reboot") — and that is correct, not a design flaw to be engineered away. Monthly scheduled-task registration and startup-task cleanup stay here too, as genuinely launcher-lifecycle concerns.

### A'4. Environment Preflight (**reorganized — parallel capability detection, serialized installs where a real dependency exists**)
Today: winget check/install → PS7 check/install (which can itself trigger winget) → Chocolatey (nested inside PS7's fallback) → PSWindowsUpdate module → Defender exclusion → re-verification logging, all strictly sequential (`script.bat:558-928`, ~370 lines).

New structure:
1. **Detect, in parallel** (these four checks share no state and can run as concurrent background jobs): winget present? PS7 present? Chocolatey present? PSWindowsUpdate module present? — a `Start-Job`/`Wait-Job` fan-out (or, since this is still the batch-script phase, four `START /WAIT`-free parallel `powershell -Command` probes) costs roughly the time of the *slowest single check* instead of the sum of all four.
2. **Install only what's missing, respecting the one real dependency that exists:** PS7's preferred install method is winget, so winget-install (if needed) still has to complete before PS7-install is attempted via that path. Everything else — Chocolatey install, PSWindowsUpdate module install — has no ordering dependency on winget or PS7 and runs concurrently with the winget→PS7 chain, not after it.
3. **Defender exclusion moves here, but scoped and paired.** Add it immediately before Stage 1 would start doing AV-sensitive work (AppX enumeration, package installs), scoped to this run's specific working directory and process, and — critically — record the fact that it was added so Stage 5 can remove it. (Concretely: write the exclusion, then have the orchestrator's Stage 5 cleanup call `Remove-MpPreference` for the same path/processes before deleting the project folder. Symmetric setup/teardown, goal #5 above.)
4. PS7-install-triggered self-relaunch behavior is unchanged (still genuinely necessary — you can't keep running batch logic that assumes PS7 exists until PS7 exists).

### A'5. Restore Point — **moved out of the launcher entirely, into the orchestrator, gated on need**
Today this runs unconditionally at the very end of the launcher (`script.bat:1211-1325`), even on a machine where Stage 1 will find nothing to fix. A restore point exists to protect against *changes*; if Stage 2 determines there are zero queued Type2 actions, there is nothing to protect against and the shadow-storage cost (checking/resizing to 10GB, `Checkpoint-Computer`) is pure waste.

New location: **start of Stage 3**, gated on `$actionNeeded.Count -gt 0` (this variable already exists in the current Stage 3 code, per `MaintenanceOrchestrator.ps1:404`). On a clean machine with nothing queued, this step now costs nothing instead of always costing a full restore-point creation.

### A'6. Launch — unchanged
Same handoff to `pwsh.exe` running the orchestrator, same detached-window model. (The dropped `-TaskNumbers` argument bug should be fixed as part of this — it's a one-line fix already documented separately — but that's a bug fix, not a reorganization, so it's not re-litigated here.)

---

## Part B' — Orchestrator, reorganized

### B'0. New: Shared Package-Manager Session (**new — consolidates 4+ redundant winget/choco call sites into 1-2**)

Today, `winget`/`choco` get invoked independently and redundantly by up to seven different places across a single run, each blind to what the others already asked for:
- `EssentialAppsAudit` spawns **one `winget list --id --exact` per missing app** (potentially a dozen+ spawns)
- `AppUpgradeAudit` spawns `Get-WingetUpgrade` (one call) and `choco outdated` (one call)
- `EssentialApps` (Type2) spawns `winget source update` once, then `winget install`/`choco install` per app
- `AppUpgrade` (Type2) spawns `winget upgrade`/`choco upgrade` per app
- `BloatwareRemoval` (Type2) has a `winget uninstall` fallback path

None of these share a cache. `EssentialAppsAudit` in particular pays for a full winget process spawn *per still-missing app* when a single `winget list` (no filter) followed by in-memory matching would return the same information once.

**Proposal:** introduce one new core helper, `Get-PackageManagerSnapshot` (lives in `modules/core/`, called once at the very start of Stage 1), that:
- Runs `winget source update` once (if winget present)
- Runs one unfiltered `winget list` and caches the parsed output to `$env:MAINT_TEMP\data\winget-snapshot.json`
- Runs one `choco list --local-only` and one `choco outdated`, cached the same way

Every consumer (`EssentialAppsAudit`'s missing-app check, `AppUpgradeAudit`'s upgrade check) reads this cache instead of spawning its own process. This alone removes the single worst-flagged performance issue in the current design (`EssentialAppsAudit`'s per-app winget spawn loop) as a side effect of removing redundant work generally, not as a special case.

Install/upgrade/uninstall actions in Stage 3 still have to spawn real per-app processes (you can't batch an *install*), but they now do so against a **single shared "package manager lane"** (below) instead of racing each other.

---

### B'0b. Impact-Based Function Grouping — **new, the core answer to "can functions move next to similar functions"**

This section is the concrete version of Goal #6. I went through every Type1 and Type2 module's internals (full inventory in [`timeline.md`](timeline.md)'s Module Detail section) looking for functions that don't just do *similar-sounding* things, but do **the literal same OS operation**, triggered from different feature domains. There are exactly three places this is true, and they're worth naming precisely rather than gesturing at "some duplication somewhere":

#### Duplication 1 — Registry writes (3 independent copies of the same logic)

| Module | Lines (approx.) | What it does |
|---|---|---|
| `SecurityEnhancement.psm1` | `registry` case in the `Type` switch | `Set-RegistryValue -Path -Name -Value -Type`, sourced from up to 247 baseline entries |
| `TelemetryDisable.psm1` | `registry` case in the `Type` switch | Identical call shape, sourced from 8 baseline entries |
| `SystemOptimization.psm1` | `registry`, `visualfx`, `background` cases | Same call shape (`visualfx`/`background` just batch several calls in a row), plus a `startup` case that calls `Remove-ItemProperty` instead — the one genuine variant in this group |

All three are the same three-line pattern: read `Path`/`Name`/`Value`/`Type` off the diff item, call `Set-RegistryValue`, check the result, increment a counter. The *audit* side has the mirror-image duplication: `SecurityAudit.psm1`, `TelemetryAudit.psm1`, and `SystemOptimizationAudit.psm1` each contain their own "loop over baseline entries, call `Get-RegistryValue`, compare, add to diff if mismatched" block.

**Proposal:** one core module, `modules/core/RegistryImpact.psm1`, exporting:
- `Compare-RegistryBaseline -Entries <array> -SourceModule <name>` — the shared audit-side comparison loop (used by all three Type1 audits, replacing three copies of the same `foreach`)
- `Invoke-RegistryChange -Items <array>` — the shared action-side writer (used by all three Type2 actions), accepting a merged list where each item carries a `SourceModule` tag (`'Security'`/`'Telemetry'`/`'SystemOptimization'`) so results can still be attributed back to the domain that asked for them
- `Remove-RegistryValue -Items <array>` for the `startup`-case variant (delete rather than set)

This is a deliberately narrow, mechanism-specific revival of the idea behind the old (now-deleted) `Compare-ListDiff` — that function failed because it tried to be one generic comparator for every shape in the project at once; `Compare-RegistryBaseline` succeeds because it only has to handle one well-known shape (`Path`/`Name`/`Value`/`Type`), which is all three registry-touching modules already agree on today without realizing it.

#### Duplication 2 — Service state changes (3 independent copies of the same logic)

| Module | What it does |
|---|---|
| `SecurityEnhancement.psm1` | `service` case: `Stop-Service`/`Start-Service` + `Set-Service -StartupType`, sourced from 27 baseline entries (3 ensure-running, 24 ensure-disabled) |
| `TelemetryDisable.psm1` | `service` case: same call shape, sourced from 9 baseline entries (all disable) |
| `SystemOptimization.psm1` | `service` case: same call shape, sourced from 7 baseline entries (all disable) |

**Proposal:** `modules/core/ServiceImpact.psm1`, exporting `Compare-ServiceBaseline` (audit side, replacing the same loop in `SecurityAudit.psm1`/`TelemetryAudit.psm1`/`SystemOptimizationAudit.psm1`) and `Invoke-ServiceChange -Items <array>` (action side, `SourceModule`-tagged like the registry executor). A merged run against all 43 services (27+9+7, deduplicated — `WinDefend` appears in both Security's ensure-running list and is never touched by the other two, so no actual key collisions exist) costs one function's worth of `Get-Service`/`Set-Service` call overhead instead of three.

#### Duplication 3 — Package manager mutations (3 independent copies of the same logic)

| Module | What it does |
|---|---|
| `BloatwareRemoval.psm1` | AppX removal (its own mechanism, no duplication) + a `winget uninstall --id ...` fallback when AppX doesn't match |
| `EssentialApps.psm1` | `winget install --id ... --silent --accept-package-agreements --accept-source-agreements [--scope]`, choco fallback |
| `AppUpgrade.psm1` | `winget upgrade --id ... --silent --accept-package-agreements --accept-source-agreements`, choco fallback |

The AppX-specific removal logic in `BloatwareRemoval.psm1` is genuinely unique (nothing else touches AppX) and stays put. But the **winget/choco invocation pattern itself** — build args, spawn via `Invoke-ExternalPackageCommand`, interpret the same family of exit codes (`0`, `-1978335189`, `-1978335212`), fall back to choco on failure — is written three times with only the verb (`install`/`upgrade`/`uninstall`) changing.

**Proposal:** extend B'0's `Get-PackageManagerSnapshot` idea into a full `modules/core/PackageManagerImpact.psm1`, adding `Invoke-PackageManagerAction -Verb <Install|Upgrade|Uninstall> -Id <id> -Source <winget|choco> -Options <hashtable>` as the one place that knows how to talk to winget/choco, what a success exit code looks like, and how to fall back. All three domain modules call this instead of maintaining their own copy of exit-code handling — which also means the winget exit-code bug already flagged in the bug-fix document (`AppUpgrade.psm1` wrongly accepting `-1978335212` as success) only has to be fixed in **one place** instead of independently in every module that happens to check exit codes.

#### What does *not* get consolidated, and why

- **Scheduled tasks** (`TelemetryDisable.psm1` only, 8 tasks), **Defender preferences** (`SecurityEnhancement.psm1` only), **firewall profiles** (`SecurityEnhancement.psm1` only), **power plan** (`SystemOptimization.psm1` only), and **secedit/auditpol/net-accounts** (`SecurityEnhancement.psm1` only) each have exactly one owning module today — there is no cross-module duplication to remove. I'm still naming them as part of the same family (`modules/core/ScheduledTaskImpact.psm1`, etc., or simply left as private functions inside their one current owner) purely for **consistency and future-proofing**: if a future baseline ever needs, say, telemetry to also disable a scheduled task category outside the current 8, or system-optimization to touch a Defender exclusion, the shared home already exists instead of inviting a fourth copy-paste.
- **Windows Update installs** stay fully isolated, not merged into any shared executor — this matches the reasoning already given in B'3 below (highest reboot-likelihood, most likely to touch shared servicing-stack state, worth keeping conceptually and operationally separate).

#### What this does *not* change about the module layout

The eight Type1/seven Type2 **domain modules stay exactly where they are** — `SecurityAudit.psm1`, `SecurityEnhancement.psm1`, `TelemetryAudit.psm1`, etc. all still exist, are still what the config (`$Config.modules.Skip*`), the report, and the module-pair registry organize around, and each still owns its own `RebootRequired`/`ItemsProcessed`/`ItemsFailed` reporting. What moves is only the **mechanism code inside them**: instead of `SecurityEnhancement.psm1`'s `registry` case containing its own `Set-RegistryValue` call, it calls `Invoke-RegistryChange -Items $mySecurityRegistryItems` from the shared module and folds the returned per-item results into its own `ModuleResult`. The domain boundary (why a user would want to skip "Telemetry" but not "Security") and the mechanism boundary (how a registry value actually gets written) are different axes, and today's code has only ever organized around the first one — this proposal adds the second, it doesn't replace the first.

---

### B'1. Stage 1 — Audit, reorganized into concurrency lanes

The 8 Type1 modules touch almost entirely disjoint system surfaces (bloatware/apps/security/telemetry/optimization/updates/upgrades/inventory) and don't depend on each other's output — the only shared input is `$global:OSContext`, which is read-only after Stage B1 computes it once. That makes Stage 1 a natural candidate for `ForEach-Object -Parallel` (PowerShell 7+), with one deliberate constraint: **don't let two lanes spawn `winget`/`choco` at the same time**, since winget in particular does not reliably support concurrent invocations (single-instance locking behavior in common versions).

Proposed lanes, all started together, joined before Stage 2 begins:

| Lane | Modules | Why grouped |
|---|---|---|
| **Lane 1 — Longest pole, kicked off first** | `WindowsUpdatesAudit` | Its COM-based update search is explicitly the heaviest single call in the entire audit suite ("can take seconds to minutes"). Starting it first and letting every other lane run concurrently in its shadow is the single biggest wall-clock win available in Stage 1 — everything else in this table combined is still very likely faster than this one module alone. |
| **Lane 2 — Fast, local-only, fully parallel-safe** | `SystemInventory`, `TelemetryAudit`, the registry/service portions of `SystemOptimizationAudit` | Pure CIM/registry/service reads, no external process spawns, no shared mutable state. Cheapest possible parallelization — just run them all at once. Under B'0b, the registry/service comparison work in this lane runs through the shared `Compare-RegistryBaseline`/`Compare-ServiceBaseline` helpers rather than three separate hand-rolled loops, which is what makes it safe to treat as one undifferentiated "fast lane" instead of three subtly-different implementations that happen to be similarly fast. |
| **Lane 3 — External-process, non-package-manager** | `SecurityAudit` (secedit/auditpol spawns), the `powercfg` portion of `SystemOptimizationAudit` | These spawn real child processes but not `winget`/`choco`, and don't conflict with each other (different executables, different subsystems) or with Lane 2. Safe to run concurrently with Lanes 1 and 2. |
| **Lane 4 — Package-manager-dependent, serialized internally** | `BloatwareDetectionAudit` (AppX enumeration — technically not winget, grouped here because it's the other "enumerate installed things" audit and benefits from running after Lane 0's snapshot exists), `EssentialAppsAudit`, `AppUpgradeAudit` | These now read from the Stage B'0 snapshot instead of spawning their own winget/choco calls, so they're actually *cheap* under this proposal and could arguably move to Lane 2 — kept as a distinct lane only so that if the snapshot cache ever needs a live top-up mid-audit, that top-up is serialized against itself rather than racing. |

**Implementation note, stated honestly:** `ForEach-Object -Parallel` runspaces do not automatically see the parent scope's functions or `Write-Log`/transcript state. Two things have to be solved for this to be safe, not just fast:
- Each parallel module needs `$using:` to pass in `$global:OSContext`, `$ProjectRoot`, etc., and must `Import-Module` the core module inside its own runspace.
- **Logging must become thread-safe.** Today's `Write-Log` writes directly to a single transcript; if 3-4 lanes write concurrently, output interleaves or corrupts. The fix is a synchronized queue (`[System.Collections.Concurrent.ConcurrentQueue]`) that each runspace pushes to, drained and written to the transcript by the main thread after each lane completes (or on a timer). This is a real implementation cost, not a one-line change — called out explicitly so it isn't discovered halfway through building this.

The Stage 1 circuit breaker (3 consecutive failures → abort) doesn't translate cleanly to a parallel model — "consecutive" stops meaning anything when modules finish out of order. Proposed replacement: a **failure-rate breaker** — if the shared core module itself fails to import (the actual systemic-failure case the breaker was meant to catch), abort *before* dispatching any lane; if 3+ of the 8 modules fail for unrelated reasons, that's page-worthy but each module already ran independently, so there's nothing left to "abort into."

### B'2. Stage 2 — Diff (unchanged)

This stage is already correct and already matches the project's own stated principle ("diff list is mandatory; empty diff list means skip cleanly") — no reorganization proposed. Restore-point creation (moved from the launcher, see A'5) happens at the very start of this stage's Type2 handoff, gated on `$actionNeeded.Count -gt 0`.

### B'3. Stage 3 — Act, reorganized around shared executors (B'0b) running in concurrency lanes

With B'0b's executors in place, Stage 3 stops being "7 modules doing their own thing" and becomes "up to 7 domain modules collecting their own diff items, then a small number of shared executors doing the actual mutation once each." Concretely: `SecurityEnhancement`, `TelemetryDisable`, and `SystemOptimization` each still run (config-gating, per-domain reporting, `RebootRequired` flags stay exactly where they are), but their `registry`- and `service`-typed diff items get handed to `Invoke-RegistryChange`/`Invoke-ServiceChange` as one merged, `SourceModule`-tagged batch instead of three separate loops each calling the same underlying primitive. Domain modules keep the items unique to them (Defender prefs and firewall and secedit/auditpol stay inside `SecurityEnhancement`; power plan stays inside `SystemOptimization`; scheduled tasks stay inside `TelemetryDisable`) — only the genuinely shared mechanisms move.

This collapses cleanly onto the same lane structure proposed for concurrency, because "which executor does this item go through" and "which lane is this safe to run in" turn out to be almost the same question:

| Lane | What runs in it | Why grouped |
|---|---|---|
| **Lane A — Package-manager, serialized** | `Invoke-PackageManagerAction` calls from `BloatwareRemoval` (winget-uninstall fallback), `EssentialApps` (installs), `AppUpgrade` (upgrades), plus `BloatwareRemoval`'s AppX-native removal | All winget/choco mutations funnel through the one shared executor from B'0b, which is what makes "serialize this lane" a single, enforceable rule instead of three modules each having to independently remember not to race winget. Order: bloatware removal → essential installs → upgrades (removing junk before installing/upgrading real apps is the more sensible order anyway). |
| **Lane B — Registry + Service executors, parallel with Lane A** | One `Invoke-RegistryChange` call against the merged ~266-item queue (247 security + 8 telemetry + 11 sys-opt), one `Invoke-ServiceChange` call against the merged 43-service queue (27 security + 9 telemetry + 7 sys-opt) | Because these now run as two single, shared function calls instead of six separate module-owned loops, there's no meaningful sub-lane structure left to draw — the whole point of B'0b is that this *used to be* three parallel lanes worth of near-identical work and is now two function calls. |
| **Lane B2 — Domain-exclusive mechanisms, parallel with Lane A/B** | `SecurityEnhancement`'s Defender/firewall/secedit/auditpol calls, `SystemOptimization`'s powercfg call, `TelemetryDisable`'s scheduled-task calls | These have no cross-module duplicate to consolidate (see B'0b), so they stay inside their one owning domain module and run concurrently with Lanes A and B — nothing here conflicts with the registry/service/package-manager executors. |
| **Lane C — Windows Update installs, isolated** | `WindowsUpdates` | Deliberately kept out of the executor-consolidation exercise entirely — it's the module most likely to touch shared OS components (drivers, servicing stack) and most likely to set `RebootRequired`. Running it concurrently with the other lanes is fine (no observed resource overlap), but keeping it conceptually separate lets Stage 5's reboot messaging call out "this run needed a reboot because of Windows Updates" specifically, instead of a flattened generic flag. |

### B'4. Stage 4 — Report (unchanged structurally)

Same generation/copy logic. One addition made necessary by B'1/B'3: since modules within a lane now finish concurrently rather than in a fixed visual order, the report's per-module timing display should show which lane each module ran in, not just a duration — otherwise "why did module 3 finish before module 1" looks like a bug in the report instead of a feature of the new design.

### B'5. Stage 5 — Cleanup & Reboot (reorganized: symmetric teardown, single reboot condition)

1. **Remove the Defender exclusion added in A'4** (paired setup/teardown — goal #5) before deleting the project folder.
2. Reboot condition unchanged from today: any Type2 `RebootRequired` flag, gated by `rebootOnlyWhenRequired`. This remains a *second, independent* reboot decision from A'3's pre-flight gate — both are legitimate, they answer different questions, and neither should try to subsume the other (see A'3).
3. Cleanup/countdown/abort logic otherwise unchanged from today — it was already correct. It now additionally needs to run the Defender-exclusion removal from step 1 in a `finally`-equivalent so it happens even if the cleanup `Remove-Item` throws.

---

## Summary: what moved, merged, or split, and why

| Change | From → To | Reason |
|---|---|---|
| Clean-slate reboot gate (detection **and** action) | Unchanged — stays in launcher (A'3) | Already correct: it's a precondition for the orchestrator to run at all, so it can't be deferred to a stage that only runs *after* the orchestrator. Kept exactly as-is; an earlier draft of this proposal wrongly tried to merge it into Stage 5 and that idea was retracted. |
| Restore point creation | Launcher (unconditional) → Start of Stage 3 (gated on `$actionNeeded.Count -gt 0`) | Restore points protect against *changes*; don't pay for one when nothing will change. |
| Defender exclusion add | Launcher, mid-dependency-management, never removed → Launcher A'4, paired with an explicit Stage 5 removal | Symmetric setup/teardown; closes a real, permanent security-hygiene regression. |
| Winget/choco capability + inventory queries | Scattered across `EssentialAppsAudit`, `AppUpgradeAudit`, `EssentialApps`, `AppUpgrade` (4+ independent spawns) | Merged into one `Get-PackageManagerSnapshot` core helper, called once, cached, read by all four | Removes the single worst-flagged per-app-spawn inefficiency in the current design; one source of truth instead of four independent, potentially-inconsistent snapshots taken at slightly different times. |
| Registry-write function | Duplicated in `SecurityEnhancement.psm1`, `TelemetryDisable.psm1`, `SystemOptimization.psm1` (3 copies of the same `Set-RegistryValue` call pattern) | One shared `Invoke-RegistryChange` in `modules/core/RegistryImpact.psm1`, called by all three with `SourceModule`-tagged items | Same OS mechanism, three copies; consolidating means the exit-code/error-handling fix only has to happen once (B'0b). |
| Registry-comparison function (audit side) | Duplicated in `SecurityAudit.psm1`, `TelemetryAudit.psm1`, `SystemOptimizationAudit.psm1` | One shared `Compare-RegistryBaseline` in the same core module | Mirror of the above, on the read side; a scoped, mechanism-specific revival of the retired `Compare-ListDiff` idea. |
| Service-toggle function | Duplicated in `SecurityEnhancement.psm1`, `TelemetryDisable.psm1`, `SystemOptimization.psm1` | One shared `Invoke-ServiceChange` in `modules/core/ServiceImpact.psm1`, plus `Compare-ServiceBaseline` for the audit side | Same reasoning as the registry consolidation, applied to `Stop/Start-Service`+`Set-Service -StartupType`. |
| Winget/choco install/upgrade/uninstall function | Duplicated in `BloatwareRemoval.psm1`, `EssentialApps.psm1`, `AppUpgrade.psm1` (3 copies of "spawn winget, check exit code, fall back to choco") | One shared `Invoke-PackageManagerAction -Verb <Install\|Upgrade\|Uninstall>` in `modules/core/PackageManagerImpact.psm1` | Same reasoning again; also means the already-documented wrong-exit-code bug in `AppUpgrade.psm1` gets fixed in one place instead of needing a matching audit of the other two. |
| Stage 1 (8 audits) | Strict sequential `foreach` → 4 concurrency lanes, `WindowsUpdatesAudit` started first as the long pole | Most of Stage 1 is independent, read-only work; the current design pays full sequential cost for zero benefit. |
| Stage 3 (up to 7 actions) | Strict sequential `foreach` → executor-driven lanes (package-manager serialized, registry+service executors run once each instead of per-module, domain-exclusive mechanisms parallel, updates isolated) | Same reasoning as Stage 1, restructured around B'0b's executors so the lane boundaries match the mechanism boundaries instead of being drawn separately from them. |
| Stage 1 circuit breaker | "3 consecutive failures" (meaningless once execution is concurrent) → import-failure fast-abort + post-hoc failure-rate check | The original breaker's actual intent (catch a systemic/core failure early) is preserved; its mechanism (consecutiveness) doesn't survive parallelization and is replaced with one that does. |

## What I deliberately did **not** change

- The Type1 → diff → Type2 shape itself. It's the right architecture; the problems in the current implementation are execution-order and redundancy problems, not architectural ones.
- The "empty diff list → skip cleanly, no action" rule. Already correct, already matches the project's own stated principle, kept exactly as-is.
- `script.bat` being the only file left after cleanup. That's a deliberate, sound design constraint (see [`README.md`](README.md)) and nothing above changes it.
- Config-driven per-module skipping (`$Config.modules.*`). Unchanged — orthogonal to execution ordering.
- **The 8 Type1 / 7 Type2 domain modules themselves.** B'0b moves *mechanism* code (how a registry value gets written, how a service gets toggled, how winget gets invoked) into shared executors, but the domain modules — `SecurityAudit`/`SecurityEnhancement`, `TelemetryAudit`/`TelemetryDisable`, etc. — stay exactly where they are, because that's the axis the config, the report, and the user's mental model ("skip telemetry, keep security") are all organized around. Consolidating by OS-impact and organizing by feature-domain are two different, compatible axes; this proposal adds the first without touching the second.
- **Scheduled tasks, Defender preferences, firewall, power plan, and secedit/auditpol/net-accounts.** Each has exactly one owning module today with no cross-module duplicate, so there's nothing to consolidate — see the "what does *not* get consolidated" callout in B'0b for why they're named as part of the same executor family anyway (future-proofing, not present-day duplication).

## Honest risk assessment of this proposal

- **Parallel execution is a real engineering lift**, not a config flag — thread-safe logging in particular has to be built, not assumed. If that piece is skipped, don't attempt the lane-based Stage 1/3 changes; a corrupted transcript is worse than a slow one.
- **winget's concurrency behavior should be verified against the actual winget version this project targets** before relying on the lane split above — the "don't run two winget calls at once" constraint is based on well-documented common behavior, but Microsoft has changed winget's locking behavior across versions before, and this line item is worth re-confirming empirically rather than trusting this document.
- **B'0b (the executor consolidation) is independent of the concurrency changes and can be done first, on its own, with no parallelism at all.** Extracting `Invoke-RegistryChange`/`Invoke-ServiceChange`/`Invoke-PackageManagerAction` out of the three domain modules that each duplicate them is a pure refactor — same sequential execution order, same results, just one implementation instead of three. This is the safest, most mechanical item in this entire document to implement first, and it's also what makes the later concurrency-lane work in B'1/B'3 simpler once it's done (fewer independent pieces to reason about running in parallel). If the parallel-execution work in B'1/B'3 never happens at all, B'0b is still worth doing on its own.
- **If the goal is "fix the worst currently-shipping problem with the least risk," that's A'4's Defender-exclusion pairing** (add in the launcher, remove in Stage 5) — a small, non-concurrent, data-flow-shaped change that closes a real, permanent AV-exclusion regression left on every client machine today. **If the goal is instead "reduce the codebase's duplication surface before touching concurrency at all," that's B'0b** (previous bullet) — different goal, different "do this first," both valid starting points depending on what's being optimized for.
- **This proposal previously argued for collapsing the launcher's clean-slate reboot gate into Stage 5 (A'3).** That was wrong and has been retracted above after clarification: the two reboot points serve genuinely different purposes and neither can substitute for the other. Left in this document's revision history as a reminder to verify a design "improvement" against the *reason* something exists, not just against how it looks from the outside.
