# Implementation Timeline (Proposed)

See full plan: [docs/analysis/full-plan.md](docs/analysis/full-plan.md)

This timeline focuses on fixes for data loss, report completeness, and the post-execution countdown behavior.

## Phase 1: Critical Fixes (1-2 days)

- Move LogAggregator initialization to after core module imports, or re-run Start-ResultCollection after import.
- Fix undefined variable in ReportGenerator EXECUTION_MODE replacement.
- Fix asset copy guard ($UseEnhanced -> $UseEnhancedReports).
- Adjust countdown abort behavior to skip cleanup and reboot by default when any key is pressed.

## Phase 2: Data Completion (2-4 days)

- Add diff list ingestion into LogProcessor.
- Add diff summary rendering into ReportGenerator module cards.
- Ensure each Type2 module writes execution.log consistently.

## Phase 3: Report Enhancements (3-5 days)

- Expand executive summary with module rollups from aggregated-results.json.
- Add a clear per-module resume section (key findings and actions).
- Add references to full log paths and diff evidence for audit.

## Phase 4: Hardening and Validation (2-3 days)

- Add Pester tests for LogProcessor diff ingestion and ReportGenerator output.
- Add integration tests for end-to-end execution in TestFolder.

## Deliverables

- Updated modules: MaintenanceOrchestrator, LogProcessor, ReportGenerator, CoreInfrastructure.
- Updated templates in config/templates as needed.
- Updated documentation: critical-path-audit.md, reporting-enhancements.md, implementation-timeline.md.
