# Critical Path and Data Flow Audit

Date: 2026-02-05
Scope: Execution chain, log collection, report data flow, and data-loss points.

## Execution Chain (Expected)

1. script.bat runs from arbitrary folder, schedules monthly task, downloads latest repo, sets WORKING_DIR to extracted repo.
2. MaintenanceOrchestrator.ps1 runs from extracted repo and loads core modules.
3. Type1 audits produce JSON into temp_files/data via Get-AuditResultsPath.
4. Type2 modules execute and log into temp_files/logs/<module>/execution.log.
5. LogAggregator aggregates results and exports aggregated-results.json.
6. LogProcessor loads raw logs + aggregated results and writes processed outputs.
7. ReportGenerator reads processed outputs and writes HTML/TXT/JSON reports.
8. Reports copied back to original script.bat folder.
9. Countdown cleanup and reboot policy executed.

## Data Flow Map

- Type1 audits -> temp_files/data/_-results.json -> LogProcessor Get-Type1AuditData -> processed/module-specific/_.json -> ReportGenerator.
- Type2 execution logs -> temp_files/logs/<module>/execution.log -> LogProcessor Get-Type2ExecutionLog -> processed/module-specific/\*.json -> ReportGenerator.
- Aggregated results -> temp_files/processed/aggregated-results.json -> LogProcessor -> ReportGenerator.
- Bootstrap maintenance.log -> moved to temp_files/logs/maintenance.log -> LogProcessor Get-MaintenanceLog -> processed/maintenance-log.json.

## Findings (Ordered by Severity)

### Critical

1. Result aggregation is initialized before LogAggregator is imported, so Start-ResultCollection is never called and aggregated-results.json is not produced. This blocks report sections that depend on aggregated results and reduces traceability.

- Evidence: [MaintenanceOrchestrator.ps1](MaintenanceOrchestrator.ps1#L149-L167)
- Impact: report summaries and module rollups can be missing or empty.
- Fix: move Start-ResultCollection after core module import or re-run it after LogAggregator loads.

### High

2. Undefined variable used when rendering EXECUTION_MODE in enhanced report path. This can throw or silently render incorrect status.

- Evidence: [modules/core/ReportGenerator.psm1](modules/core/ReportGenerator.psm1#L897)
- Impact: report generation can fail or show wrong execution mode.
- Fix: replace $config with a verified source (e.g., MainConfig or processed data).

3. Enhanced report JavaScript assets are gated by an undefined variable, so dashboard scripts never copy.

- Evidence: [modules/core/ReportGenerator.psm1](modules/core/ReportGenerator.psm1#L948)
- Impact: interactive charts/scripts do not load.
- Fix: change $UseEnhanced to $UseEnhancedReports in the asset-copy block.

### Medium

4. Diff lists are saved but excluded from processing, so diff evidence is absent in reports.

- Evidence: [modules/core/CoreInfrastructure.psm1](modules/core/CoreInfrastructure.psm1#L2600-L2661), [modules/core/LogProcessor.psm1](modules/core/LogProcessor.psm1#L360-L368)
- Impact: compliance and proof-of-action data is not visible in reports.
- Fix: add diff ingestion in LogProcessor and surface diff stats in ReportGenerator.

5. LogProcessor builds dashboard metrics from mock TaskResults when aggregated results are not supplied.

- Evidence: [modules/core/LogProcessor.psm1](modules/core/LogProcessor.psm1#L1758)
- Impact: dashboard KPIs can be inaccurate or misleading.
- Fix: feed actual TaskResults or aggregated results from LogAggregator.

6. Type2 logs are only collected from temp_files/logs/<module>/execution.log. If a module logs only to maintenance.log or another location, it will be omitted from the report data.

- Evidence: [modules/core/LogProcessor.psm1](modules/core/LogProcessor.psm1#L424-L476)
- Impact: missing module execution details in reports.
- Fix: enforce execution.log writes in each Type2 module or expand LogProcessor to search additional log paths.

### Requirement Gaps

7. Countdown behavior does not match the requirement "any key aborts and leaves everything as-is." Current behavior opens a menu with cleanup as default.

- Evidence: [modules/core/CoreInfrastructure.psm1](modules/core/CoreInfrastructure.psm1#L4047-L4166)
- Impact: potential unintended cleanup when a user tries to abort shutdown.
- Fix: on keypress, abort and skip cleanup and reboot without prompting.

## Notes

- script.bat already moves bootstrap maintenance.log into temp_files/logs after execution, which aligns with LogProcessor search paths.
- Execution reports are copied back to the script.bat folder in orchestrator; verify final report copy path when running from network shares.

## External References

- schtasks command reference (Task Scheduler CLI): https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/schtasks
- PowerShell automatic variables (for startup/host behavior and exit codes): https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_automatic_variables
