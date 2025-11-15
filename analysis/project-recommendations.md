# Recommendations & Enhancements

## Stabilize Core Infrastructure

1. **Normalize log-file scope and bootstrap logging up front.**
   - After resolving the working directory, assign `Set-Variable -Scope Script -Name LogFile -Value ...` *and* `Set-Variable -Scope Global` (or change every logging helper to reference `$script:LogFile`). Add a startup self-test (`Test-Path $LogFile`) so the script aborts gracefully if the path cannot be created.

2. **Harden `Invoke-LoggedCommand`.**
   - Replace `Start-Process` with `Start-Process -NoNewWindow -RedirectStandardOutput/-RedirectStandardError` or `System.Diagnostics.Process` so you can capture streams. Respect the `TimeoutSeconds` parameter via `WaitForExit(timeout)` and surface a non-zero exit code + captured output in the returned hashtable. Update `Write-CommandLog` calls with truncated stdout/stderr for traceability.

3. **Guarantee boolean success semantics.**
   - Wrap every task result with `[bool]$result` before storing it (e.g., `IsSuccessful = [bool]$result`, `ResultPayload = $result`). Update summaries and HTML to rely on `IsSuccessful`. Fix the per-task console log to emit `'ERROR'` when a task fails.

## Simplify & Standardize Task Orchestration

4. **Choose a single `$global:ScriptTasks` definition.**
   - Decide which task graph is authoritative, delete the other, and ensure every documented feature has a corresponding task entry. If you need different presets, expose them through config files instead of redefining the array inline.

5. **Align skip flags with the active task list.**
   - For every Boolean in `$global:Config`, either (a) wire it into a task/function, or (b) remove it from the config to prevent false expectations. When a task is skipped, return an object like `@{ IsSuccessful = $true; Status = 'Skipped' }` so reports can distinguish "Skipped" from "Completed".

6. **Deduplicate helper/function definitions.**
   - Keep a single implementation per helper (e.g., `Write-CleanProgress`, `Protect-SystemRestore`, `Get-OptimizedSystemInventory`). Remove the placeholder `# ...existing code...` blocks and the duplicate doc comments. Consider splitting the script into modules (e.g., `logging.psm1`, `tasks.psm1`) to make duplication harder.

## Improve Maintainability & Performance

7. **Refactor progress/logging helpers into one cohesive API.**
   - Publish a tiny interface contract (e.g., `Show-TaskProgress -Activity -PercentComplete -Stage`) plus a formatter shared by all tasks. Enforce ASCII-only output (or gate emoji behind a config flag) so scheduled tasks remain log-friendly.

8. **Optimize cleanup routines.**
   - Instead of rescanning entire trees to measure freed space, record `Get-ChildItem` results once per directory or rely on `Get-ChildItem | Measure-Object` without recursion. Add allowlists/denylists so caches for Teams/OneDrive/Edge can be preserved if required.

9. **Regenerate reports from normalized task metadata.**
   - Once each task exposes `Name`, `Description`, `Importance`, `IsSuccessful`, `Duration`, and optional payload, feed that structured data into both the console summary and the HTML template. This guarantees consistent dashboards regardless of future task changes.

## Documentation & Config Hygiene

10. **Consolidate documentation blocks.**
    - Keep one concise comment header per function. Move the deep-dives (currently duplicated before every function) into `.github/copilot-instructions.md` or an external Markdown reference to shrink `script.ps1` and make diffs cleaner.

11. **Version control generated artifacts.**
    - Instead of writing `essential_apps.json` twice during startup, generate it once, store it in `temp_files`, and reference it in the report. If multiple views are required (e.g., categories vs. unified list), build them in-memory and emit a single JSON file with multiple sections.

12. **Add automated linting/tests.**
    - Introduce a `tests` folder with Pester suites that validate: (a) logging initialization, (b) uniqueness of function names, (c) task array consistency, and (d) config-to-task mapping. Run `Invoke-ScriptAnalyzer` in CI to catch future scope and duplication mistakes automatically.
