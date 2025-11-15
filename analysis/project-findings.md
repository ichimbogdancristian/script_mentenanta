# Project Findings

## Critical Issues

1. **Logging path never initialized in the scope used by logging functions** (`script.ps1`, lines 88-105 vs. 966-1010)
   - `Write-Log`, `Write-CommandLog`, and downstream helpers always write to `$global:LogFile`, but only a script-scoped `$LogFile` is ever set. Because `$global:LogFile` remains `$null`, the very first log call attempts `Add-Content -Path $null`, throwing *"Cannot bind argument to parameter 'Path' because it is null"* and aborting execution. None of the promised logging or diagnostics actually works until the variable scopes are aligned.
   - **Impact:** Entire automation stops before any maintenance task starts; batch launcher receives an error and users lose all observability.

2. **Task orchestration array overwritten mid-script** (`script.ps1`, lines 250-620 vs. 10440-10495)
   - `$global:ScriptTasks` is declared with 13 richly documented tasks near the top (SystemRestoreProtection → GenerateReports). Later, a second assignment replaces the array with a completely different 10-task list (SystemInventory, BloatwareRemoval, EssentialApps, etc.). Only the second array is in effect, so the first set of tasks—including Taskbar/Desktop optimization, DISM repair, restart check, and report generation—never run despite extensive documentation and configuration flags.
   - **Impact:** Huge mismatch between documented capabilities and actual runtime behavior; skip flags such as `SkipTaskbarOptimization`/`SkipDesktopBackground` can never take effect, and troubleshooting becomes extremely difficult because two separate task graphs exist in the same file.

3. **Task success tracking stores raw return objects instead of booleans** (`script.ps1`, lines 868-915 & 10470-10490)
   - The orchestrator records `Success = $result` for each task without casting to `[bool]`. Tasks like `Get-SystemInventory` return rich hashtables, so `$global:TaskResults['SystemInventory'].Success` becomes a hashtable. Later summary logic does `Where-Object { $_.Success -eq $true }`, which evaluates to `$false` for any non-boolean, falsely classifying successful tasks as failures. Additionally the per-task console log always uses log level `SUCCESS` even when `$result` is `$false`.
   - **Impact:** Execution summaries and HTML reports are unreliable, masking real failures while labeling healthy tasks as failed.

4. **`Invoke-LoggedCommand` does not fulfill its contract** (`script.ps1`, lines 1675-1725)
   - Comments promise stdout/stderr capture, timeout enforcement, and structured exit data, but the implementation simply calls `Start-Process` with `-PassThru`. No output streams are collected, no timeout is honored (the `TimeoutSeconds` parameter is unused), and failures rely solely on exit codes. Callers expecting captured output or enforced timeouts silently receive a `System.Diagnostics.Process` object instead.
   - **Impact:** Downstream functions cannot log command output or detect hung installers, leading to stalled maintenance sessions and empty command logs.

5. **Duplicate placeholder definitions shadow real implementations**
   - Examples include `Write-CleanProgress` (lines 1225-1315 & 1320-1369), `Protect-SystemRestore` (lines 8035-8070 & 8074-8150), `Get-OptimizedSystemInventory` (lines 4139 & 4168), `Get-EventLogAnalysis` (lines 8208 & 8462), `Disable-SpotlightMeetNowNewsLocation` (lines 7493 & 7514), and `Optimize-TaskbarAndDesktopUI` (lines 7660 & 7682). Each pair contains an empty stub or duplicated doc-block followed by the real code.
   - **Impact:** Maintainers risk editing the wrong version, PowerShell loads the *last* definition silently overriding earlier changes, and the file size/complexity balloons, making reviews and merges error-prone.

## Major Issues

6. **Skip flags inconsistent or ineffective**
   - The initial task list mixes `$true/$false` returns when skips occur (e.g., `SystemRestoreProtection` returns `$false` when skipped). Even in the active task list, some operations (e.g., `SpotlightMeetNowNewsLocation`, `AppBrowserControl`) ignore the matching `Skip*` flags defined in `$global:Config`. Other config switches such as `SkipTaskbarOptimization`, `SkipDesktopBackground`, `SkipSecurityHardening`, and `SkipPendingRestartCheck` no longer map to any task.
   - **Impact:** Users cannot reliably tailor runs; skips may be reported as failures or the flags simply do nothing, undermining unattended deployments.

7. **Progress + logging APIs defined multiple ways, causing inconsistent usage**
   - `Write-CleanProgress` has two different implementations; `CleanTempAndDisk` still calls `Write-TaskProgress 'Starting disk cleanup' 20` using the old signature, and progress helpers mix emoji/text styles. There's no single, enforced interface, so task authors guess which helper is current, resulting in uneven UX and bloated console output.
   - **Impact:** Hard to standardize telemetry or automate log parsing; users see mismatched progress formats within a single run.

8. **Resource-intensive cleanup routine lacks guardrails** (`script.ps1`, lines 520-570)
   - `CleanTempAndDisk` calculates folder sizes by recursively scanning directories *twice* (before and after deletion) for each cleanup target, which is extremely expensive on large profiles or network paths. It also attempts to remove entire `%LOCALAPPDATA%\Microsoft\Windows\INetCache` and `%USERPROFILE%\AppData\Local\Temp` trees recursively without excluding locked files or whitelisting vendor folders.
   - **Impact:** Long-running cleanup steps can stall the whole maintenance window and risk deleting vendor-specific caches (e.g., Teams/OneDrive) that should survive between runs.

9. **HTML/report generation fed with inconsistent task metadata** (`script.ps1`, lines 9350-10180)
   - Reporting expects every task result to expose `Success`, `Started`, `Ended`, and textual `Description`, but the second `$global:ScriptTasks` set omits the `Importance` metadata and reuses short names (e.g., `BloatwareRemoval`). Combined with the non-boolean success bug, the HTML dashboard cannot render accurate success counts or severity coloring.
   - **Impact:** Generated reports misrepresent the run state, undermining the "professional reporting" requirement cited in the project overview.

## Minor / Maintainability Issues

10. **Configuration loader duplicates essential-app exports** (`script.ps1`, lines 10420-10460)
    - The script writes `%temp%\essential_apps.json` twice in rapid succession (once with category stats and once with only the unified list), overwriting the first artifact and wasting I/O.

11. **Docstrings and section headers repeated verbatim**
    - Nearly every function is preceded by two identical comment blocks, inflating the file by thousands of lines with no new information. This is a relic of earlier tooling and makes diffs unnecessarily noisy.

12. **Emoji & `Write-Host` usage in logging helpers prevents non-interactive runs**
    - `Write-Log` mixes `Write-Host` and `Write-Output`, emitting emoji (⏳, ✓, ✅, 📊). When executed via scheduled tasks or WinRM, these characters clutter event logs and can break legacy parsers expected to read ASCII-only output, conflicting with the "minimal logging overhead" goal in the design guide.
