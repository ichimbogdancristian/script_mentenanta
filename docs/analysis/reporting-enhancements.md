# Reporting Enhancements Plan

See full plan: [docs/analysis/full-plan.md](docs/analysis/full-plan.md)

Goal: Ensure the final HTML report always includes a project-wide summary and per-module cards/boxes, then copy the HTML report to the script.bat location.

## Target Report Structure

1. Executive Summary (project resume)
   - Session ID, host, user, execution mode, duration
   - Module counts (success, failed, skipped)
   - Total items detected/processed

2. Module Cards (one per module)
   - Module name, status, duration
   - Items detected/processed/failed
   - Key findings summary
   - Link to module execution log path

3. Detailed Sections
   - Type1 audit details per module
   - Type2 action details per module
   - Diff list summary per module (what was configured vs detected)
   - Error and warning analysis

4. Appendices
   - Maintenance log summary
   - Version and configuration snapshot

## Data Sources and Required Inputs

- Type1 audit data: temp_files/data/\*-results.json
- Type2 execution logs: temp_files/logs/<module>/execution.log
- Aggregated results: temp_files/processed/aggregated-results.json
- Diff lists: temp_files/temp/\*-diff.json
- Maintenance log: temp_files/logs/maintenance.log

## Gaps To Close

- Feed aggregated results into LogProcessor to avoid mock metrics.
- Add diff list ingestion and report rendering (currently excluded from LogProcessor).
- Normalize execution mode source for report header (avoid undefined variables).

## Proposed Enhancements (Minimal Change Set)

1. LogProcessor
   - Add Load-DiffLists to pull temp_files/temp/\*-diff.json into processed/module-specific/diffs.json.
   - Add to metrics-summary.json a diff coverage section per module.

2. ReportGenerator
   - Use a single source for execution mode (MainConfig or processed metrics summary).
   - Render diff coverage in each module card.
   - Ensure JS asset copy uses the correct variable (UseEnhancedReports).

3. Orchestrator
   - Initialize LogAggregator after module imports so aggregated-results.json is always present.

## Success Criteria

- Reports always contain a project summary and one module card per module.
- Diff lists appear in module details when available.
- HTML report is copied to the original script.bat folder on every successful run.
