# Full Plan: Data Integrity, Reporting, and Cleanup

Date: 2026-02-05
Scope: End-to-end execution reliability, data flow completeness, and post-run cleanup behavior.

## Objectives

- Ensure all data (Type1, Type2, diffs, maintenance.log) is captured and reported.
- Produce a single, detailed HTML report with a project summary and per-module cards.
- Copy final HTML report to the script.bat location reliably.
- Align countdown and reboot behavior with requirement: any key aborts and leaves everything as-is.

## Phase 1: Critical Fixes (1-2 days)

### 1. Result aggregation initialization order

- Issue: Start-ResultCollection is called before LogAggregator import.
- Change:
  - Move Start-ResultCollection after core module imports in orchestrator.
  - Alternatively, re-run Start-ResultCollection after LogAggregator import.
- Files:
  - MaintenanceOrchestrator.ps1
- Acceptance:
  - temp_files/processed/aggregated-results.json exists after run.

### 2. Execution mode rendering in enhanced report

- Issue: $config is undefined in ReportGenerator when replacing EXECUTION_MODE.
- Change:
  - Use MainConfig or processed data to determine execution mode.
- Files:
  - modules/core/ReportGenerator.psm1
- Acceptance:
  - Report renders EXECUTION_MODE correctly in enhanced path.

### 3. Enhanced report asset copy guard

- Issue: Asset copy uses $UseEnhanced (undefined).
- Change:
  - Replace $UseEnhanced with $UseEnhancedReports.
- Files:
  - modules/core/ReportGenerator.psm1
- Acceptance:
  - dashboard.js copied to report assets for enhanced reports.

### 4. Countdown abort behavior

- Issue: any key triggers a menu that defaults to cleanup.
- Change:
  - On keypress, abort countdown and skip cleanup/reboot without prompting.
- Files:
  - modules/core/CoreInfrastructure.psm1
- Acceptance:
  - Keypress results in no cleanup, no reboot, no window close.

## Phase 2: Data Completion (2-4 days)

### 5. Diff list ingestion

- Issue: diff lists are saved but excluded from LogProcessor.
- Change:
  - Add Load-DiffLists in LogProcessor to ingest temp_files/temp/\*-diff.json.
  - Store diff summary into processed/module-specific/\*.json or metrics-summary.json.
- Files:
  - modules/core/LogProcessor.psm1
- Acceptance:
  - Report shows diff evidence for modules that generate it.

### 6. Type2 execution log consistency

- Issue: some Type2 modules may not write execution.log consistently.
- Change:
  - Standardize execution.log writes using Get-SessionPath in each Type2 module.
- Files:
  - modules/type2/\*.psm1
- Acceptance:
  - temp_files/logs/<module>/execution.log exists for all Type2 modules.

## Phase 3: Report Enhancements (3-5 days)

### 7. Executive summary rollups

- Issue: summary metrics are incomplete when aggregated results are missing.
- Change:
  - Populate summary from aggregated-results.json when present.
  - Provide fallback calculation from processed module-specific files.
- Files:
  - modules/core/LogProcessor.psm1
  - modules/core/ReportGenerator.psm1
- Acceptance:
  - Executive summary always lists module counts and totals.

### 8. Per-module resume section

- Issue: module cards do not always show key findings and actions.
- Change:
  - Add fields for top findings, actions taken, and warnings/errors.
  - Render in module cards and expanded details.
- Files:
  - modules/core/ReportGenerator.psm1
  - config/templates/\*.html
- Acceptance:
  - Each module card includes a short resume section.

### 9. Log and diff references

- Issue: reports lack audit references to log and diff paths.
- Change:
  - Add log path and diff path references in module details.
- Files:
  - modules/core/ReportGenerator.psm1
- Acceptance:
  - Report shows log and diff path references.

## Phase 4: Hardening and Validation (2-3 days)

### 10. Pester tests

- Add tests for:
  - Diff ingestion in LogProcessor.
  - Enhanced report path handling in ReportGenerator.
- Files:
  - tests/\* (new)
- Acceptance:
  - Tests pass locally.

### 11. Integration validation

- Run in TestFolder and verify:
  - aggregated-results.json produced
  - HTML report generated and copied to script.bat folder
  - countdown behavior matches requirement
- Acceptance:
  - End-to-end validation checklist is green.

## Risk and Mitigation

- Risk: log processing changes may alter report output structure.
  - Mitigation: keep backward-compatible fields, add new fields under new keys.
- Risk: cleanup sequence could remove reports if copy fails.
  - Mitigation: verify report copy before cleanup and log confirmation.

## Dependencies

- LogAggregator must be loaded before Start-ResultCollection.
- TemplateEngine must be present for enhanced templates.

## Exit Criteria

- No missing data in reports for Type1, Type2, diff lists, or maintenance.log.
- HTML report copied to script.bat location on every successful run.
- Countdown abort behavior matches requirement exactly.
