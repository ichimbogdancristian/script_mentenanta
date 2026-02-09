# Code Reduction and Consolidation Plan

Date: 2026-02-09
Scope: All phases (1-7), with emphasis on reducing code volume, excessive debug output, and consolidating modules.

## Goals

- Cut duplicate logic in Type1/Type2 modules by extracting shared helpers.
- Reduce noisy startup logging and debug output without losing operational visibility.
- Consolidate overlapping modules and remove unused/dead code paths.
- Keep backward compatibility where feasible (wrapper functions, thin shims).

## Phase 0 - Critical Quick Wins (1-2 days)

### 0.1 Remove dead or unreachable code

- LogProcessor: Remove the unreachable legacy block inside Move-MaintenanceLogToOrganized (function returns early, leaving dead code).
- Outcome: Smaller file, clearer behavior.

### 0.2 Resolve missing or unused module imports

- BloatwareDetectionAudit: remove the SystemAnalysis.psm1 import if it does not exist, or replace with SystemInventory/CommonUtilities functions.
- Outcome: Remove noise and startup warnings.

### 0.3 Reduce startup verbosity

- MaintenanceOrchestrator: gate high-volume Write-Information messages behind configured verbosity.
- Keep only high-value, user-facing Write-Host output for interactive mode.
- Outcome: shorter console output, faster operator comprehension.

## Phase 1 - Core Helpers (1 week)

### 1.1 Shared Type2 execution wrapper

Create a shared helper in CoreInfrastructure or CommonUtilities:

- New-ModuleExecutionContext (name, log path, banner, perf tracking)
- Invoke-Type2Module (call Type1, diff processing, common error handling)
- Finalize-ModuleExecutionResult (summary json, standardized result)

Replace repeated setup logic in:

- BloatwareRemoval, EssentialApps, AppUpgrade, SystemOptimization, TelemetryDisable, WindowsUpdates, SecurityEnhancement

Expected reduction:

- 60-120 lines per Type2 module.

### 1.2 Shared audit cache helpers

Create in CommonUtilities:

- Get-CachedAuditResult
- Set-CachedAuditResult

Replace repeated cache sections in:

- SystemOptimizationAudit, TelemetryAudit, WindowsUpdatesAudit, EssentialAppsAudit

Expected reduction:

- 25-40 lines per Type1 audit.

### 1.3 Standardize diff generation

Create a helper:

- New-DiffListFromDetection (input detection + config + match field)

Replace duplicated diff list logic in:

- BloatwareRemoval, EssentialApps, AppUpgrade

Expected reduction:

- 30-60 lines per module.

## Phase 2 - Module Consolidation (2-3 weeks)

### 2.1 Merge TelemetryDisable into SystemOptimization

- Fold telemetry/privacy operations into SystemOptimization under a "Privacy" category.
- Keep Invoke-TelemetryDisable as a thin wrapper for backward compatibility.

Expected reduction:

- Remove standalone module plumbing and duplicated initialization.

### 2.2 Unify installed software inventory usage

- Route bloatware and essential-apps audits through SystemInventory results.
- Move shared installed software detection into a single provider in CoreInfrastructure/CommonUtilities.

Expected reduction:

- 150-300 lines by removing duplicate registry/AppX scans.

### 2.3 Reporting consolidation

- If HTMLBuilder is unused in ReportGenerator, either:
  - Wire it in fully and delete redundant HTML building in ReportGenerator, or
  - Remove HTMLBuilder entirely and simplify ReportGenerator docs.

Expected reduction:

- 500-1200 lines depending on chosen direction.

## Phase 3 - Orchestrator Simplification (1-2 weeks)

### 3.1 Replace manual module discovery

- Use ModuleRegistry for Type1 discovery in staged execution.
- Remove manual scanning logic and hardcoded descriptions.

### 3.2 Consolidate fallback logging logic

- Keep a single Write-LogEntry fallback block in orchestrator.
- Remove duplicate fallback section.

Expected reduction:

- 80-150 lines from MaintenanceOrchestrator.

## Phase 4 - Logging and Debug Reduction (1 week)

### 4.1 Log levels and noise filtering

- Standardize log level usage (INFO for state transitions, DEBUG for verbose details).
- Move repeated "starting"/"loaded" messages to DEBUG or remove if redundant.

### 4.2 Reduce Write-Host banners

- Centralize module banner output behind a config flag.
- Use a shared banner helper; disable by default for non-interactive runs.

Expected reduction:

- 10-20 lines per module.

## Phase 5 - Documentation and Validation (1 week)

### 5.1 Update architecture docs

- Reflect consolidated modules and shared helpers.
- Document wrapper functions and compatibility shims.

### 5.2 Verify with PSScriptAnalyzer

- Run analyzer on modules and orchestrator after each change set.

## Implementation Checklist

- [ ] Create helper functions (Type2 wrapper, cache helpers, diff helper).
- [ ] Refactor one Type2 module end-to-end as a template.
- [ ] Apply pattern to remaining Type2 modules.
- [ ] Refactor Type1 caching.
- [ ] Consolidate telemetry into SystemOptimization.
- [ ] Unify installed software detection.
- [ ] Decide HTMLBuilder vs ReportGenerator consolidation path.
- [ ] Replace manual module discovery with ModuleRegistry.
- [ ] Reduce startup logging noise.
- [ ] Run PSScriptAnalyzer and fix new warnings.

## Immediate Next Step Recommendation

Start with Phase 1.1 (Type2 execution wrapper) and refactor one module (AppUpgrade or WindowsUpdates) to validate the pattern before broad adoption.
