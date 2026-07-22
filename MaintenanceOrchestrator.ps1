#Requires -Version 7.0
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Windows Maintenance Automation - Central Orchestrator v5.0

.DESCRIPTION
    Coordinates all maintenance tasks in five stages:

    Stage 1 – System Inventory (Type1 modules, interactive menu, 10 s countdown)
    Stage 2 – Diff Analysis   (determine which Type2 modules have work to do)
    Stage 3 – Maintenance     (Type2 modules; skipped automatically if diff is empty)
    Stage 4 – Report          (HTML report generated, copied to script.bat folder)
    Stage 5 – Cleanup         (120 s countdown; reboot + cleanup OR abort on keypress)

    maintenance.log = full PowerShell transcript of the entire run.

.PARAMETER NonInteractive
    Skip all interactive countdowns; run all Type1 then all Type2 automatically.

.PARAMETER TaskNumbers
    Comma-separated module numbers to run (e.g. "1,3,5"), matching the Stage 1
    menu numbering. Implies -NonInteractive (no interactive menu is shown when
    a selection is supplied on the command line). Unrecognized numbers are
    ignored; if none match, all modules run.

.NOTES
    Author:  Windows Maintenance Automation Project
    Version: 5.0.0
    Requires: PowerShell 7+, Administrator
#>
[CmdletBinding()]
param(
    [switch]$NonInteractive,
    [string]$TaskNumbers
)

Set-StrictMode -Version 1.0
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'Continue'

#region ─── SCRIPT ROOT & PATHS ───────────────────────────────────────────────

$ProjectRoot = $PSScriptRoot
if (-not $ProjectRoot) { $ProjectRoot = (Get-Location).Path }

$TempDir = Join-Path $ProjectRoot 'temp_files'
# maintenance.log is the SINGLE unified log for the whole run. script.bat creates it at launch
# next to the launcher, migrates it into temp_files\logs after extraction, and passes the path
# via $env:MAINTENANCE_LOG. The core logger opens that SAME file (append, auto-flushed, with
# FileShare.ReadWrite) so the launcher's bootstrap phase and all five stages accumulate in one
# file that the report can also read live. There is no separate transcript sidecar - a
# Start-Transcript handle would block the report from reading the file mid-run.
$LogPath = if ($env:MAINTENANCE_LOG) { $env:MAINTENANCE_LOG } else { Join-Path $TempDir 'logs\maintenance.log' }

# Create temp_files structure before the logger opens the file
foreach ($sub in 'logs', 'data', 'reports', 'diff') {
    $d = Join-Path $TempDir $sub
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
}

#endregion

#region ─── SESSION BANNER ────────────────────────────────────────────────────

Write-Host ""
Write-Host "======================================================================" -ForegroundColor Magenta
Write-Host "  WINDOWS MAINTENANCE AUTOMATION  v5.0" -ForegroundColor White
Write-Host "  Session start: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Cyan
Write-Host "  Project root:  $ProjectRoot" -ForegroundColor Cyan
Write-Host "  Log file:      $LogPath" -ForegroundColor Cyan
Write-Host "======================================================================" -ForegroundColor Magenta
Write-Host ""

#endregion

#region ─── LOAD CORE MODULES ────────────────────────────────────────────────

$CorePath = Join-Path $ProjectRoot 'modules\core\Maintenance.psm1'
$UIPath = Join-Path $ProjectRoot 'modules\core\ConsoleUI.psm1'

if (-not (Test-Path $CorePath)) {
    Write-Host "[ERROR] Core module not found: $CorePath" -ForegroundColor Red
    exit 1
}

# The core logger lives inside this module, so a load failure can't be logged through
# it — capture it directly to maintenance.log and the console before bailing out.
try {
    Import-Module $CorePath -Force -Global -ErrorAction Stop
}
catch {
    Write-Host "[FATAL] Failed to import core module: $_" -ForegroundColor Red
    try {
        "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [FATAL] [ORCH] Core import failed: $_" |
        Add-Content -Path $LogPath -Encoding UTF8
    }
    catch {
        Write-Host "[WARN] Could not write to log file: $_" -ForegroundColor Yellow
    }
    exit 1
}

# Load UI module for enhanced console output (optional - provides visual enhancements)
if (Test-Path $UIPath) {
    try {
        Import-Module $UIPath -Force -Global -WarningAction SilentlyContinue
    }
    catch {
        Write-Log -Level WARN -Component ORCH -Message "UI module import failed (continuing with basic output): $_"
    }
}

# Initialise (sets env vars, creates temp dirs, opens/append maintenance.log). The
# launcher already wrote its phase into this same file, so we just continue appending.
Initialize-Maintenance -ProjectRoot $ProjectRoot -LogPath $LogPath

Add-LogRaw ('=' * 70)
Add-LogRaw "  ORCHESTRATOR SESSION START  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Add-LogRaw ('=' * 70)

#endregion

# ── Everything below runs inside a fatal-capture guard so any uncaught terminating
#    error is written to maintenance.log with a stack trace, and the log/transcript
#    are always closed cleanly (finally). ──────────────────────────────────────────
try {

    #region ─── OS & CONFIG ───────────────────────────────────────────────────────

    $global:OSContext = Get-OSContext
    $Config = Get-MainConfig

    # Apply configured log levels (falls back to the logger's INFO/DEBUG defaults).
    if ($Config.logging) {
        Set-LogLevel -Console $Config.logging.consoleLevel -File $Config.logging.fileLevel
    }

    Write-Log -Level SUCCESS -Component ORCH -Message "OS: $($global:OSContext.DisplayText)"

    #endregion

    #region ─── MODULE PAIR REGISTRY ──────────────────────────────────────────────
    # Each entry maps a Type1 audit module to its Type2 action counterpart.
    # DiffKey must match the -ModuleName used in Save-DiffList / Get-DiffList.
    #
    # Array ORDER = Stage 1 audit/menu order (Num is unrelated to position - selection via
    # -TaskNumbers/the menu matches on Num, not array index). Actionable pairs (1-4, 7) run
    # first so the decisions that gate Stage 3 are made before any time is spent on the
    # report-only audits (5, 6) - if the circuit breaker trips or a run is cut short, it's
    # the report-only work that gets sacrificed, not the audits Stage 3 depends on.
    # Stage 3's own execution order is independent of this array - see the explicit
    # $Stage3Order sort applied to $actionNeeded in Stage 3, below.

    $ModulePairs = @(
        @{
            Num        = 1
            Label      = 'Software Management (Remove/Install/Upgrade)'
            DiffKey    = 'SoftwareManagement'
            Type1File  = 'modules\type1\SoftwareManagementAudit.psm1'
            Type1Func  = 'Invoke-SoftwareManagementAudit'
            Type2File  = 'modules\type2\SoftwareManagement.psm1'
            Type2Func  = 'Invoke-SoftwareManagement'
            ConfigSkip = 'skipSoftwareManagement'
        },
        @{
            Num        = 2
            Label      = 'System Configuration (Security/Privacy/Optimization)'
            DiffKey    = 'SystemConfiguration'
            Type1File  = 'modules\type1\SystemConfigurationAudit.psm1'
            Type1Func  = 'Invoke-SystemConfigurationAudit'
            Type2File  = 'modules\type2\SystemConfiguration.psm1'
            Type2Func  = 'Invoke-SystemConfiguration'
            ConfigSkip = 'skipSystemConfiguration'
        },
        @{
            Num        = 3
            Label      = 'Disk Cleanup (Temp/Browser/Updates)'
            DiffKey    = 'DiskCleanup'
            Type1File  = 'modules\type1\DiskCleanupAudit.psm1'
            Type1Func  = 'Invoke-DiskCleanupAudit'
            Type2File  = 'modules\type2\DiskCleanup.psm1'
            Type2Func  = 'Invoke-DiskCleanup'
            ConfigSkip = 'skipDiskCleanup'
        },
        @{
            Num        = 4
            Label      = 'Windows Updates'
            DiffKey    = 'WindowsUpdates'
            Type1File  = 'modules\type1\WindowsUpdatesAudit.psm1'
            Type1Func  = 'Invoke-WindowsUpdatesAudit'
            Type2File  = 'modules\type2\WindowsUpdates.psm1'
            Type2Func  = 'Invoke-WindowsUpdate'
            ConfigSkip = 'skipWindowsUpdates'
        },
        @{
            Num        = 7
            Label      = 'Restore Point Management (Create/Consolidate)'
            DiffKey    = 'RestorePoint'
            Type1File  = 'modules\type1\RestorePointAudit.psm1'
            Type1Func  = 'Invoke-RestorePointAudit'
            Type2File  = 'modules\type2\RestorePointManagement.psm1'
            Type2Func  = 'Invoke-RestorePointManagement'
            ConfigSkip = 'skipRestorePointManagement'
        },
        @{
            Num        = 5
            Label      = 'System Inventory (report only)'
            DiffKey    = 'SystemInventory'
            Type1File  = 'modules\type1\SystemInventory.psm1'
            Type1Func  = 'Invoke-SystemInventory'
            Type2File  = ''   # No Type2 pair
            Type2Func  = ''
            ConfigSkip = ''
        },
        @{
            Num        = 6
            Label      = 'System Health (Events, Defender, Exclusions - report only)'
            DiffKey    = 'SystemHealth'
            Type1File  = 'modules\type1\SystemHealthAudit.psm1'
            Type1Func  = 'Invoke-SystemHealthAudit'
            Type2File  = ''   # No Type2 pair
            Type2Func  = ''
            ConfigSkip = ''
        }
    )

    #endregion

    #region ─── HELPER: IMPORT & RUN MODULE ───────────────────────────────────────

    function Invoke-ModuleFunction {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)] [string]$ModuleFile,
            [Parameter(Mandatory)] [string]$FunctionName,
            [Parameter()]          [hashtable]$FuncParams = @{}
        )

        $fullPath = Join-Path $ProjectRoot $ModuleFile
        if (-not (Test-Path $fullPath)) {
            Write-Log -Level WARN -Component ORCH -Message "Module file not found: $ModuleFile - skipping"
            return $null
        }

        try {
            Import-Module $fullPath -Force -Global -WarningAction SilentlyContinue
        }
        catch {
            Write-Log -Level ERROR -Component ORCH -Message "Failed to import $ModuleFile : $_"
            return $null
        }

        $fn = Get-Command -Name $FunctionName -ErrorAction SilentlyContinue
        if (-not $fn) {
            Write-Log -Level ERROR -Component ORCH -Message "Function $FunctionName not found after importing $ModuleFile"
            return $null
        }

        try {
            if ($FuncParams.Count -gt 0) {
                return & $FunctionName @FuncParams
            }
            else {
                return & $FunctionName
            }
        }
        catch {
            Write-Log -Level ERROR -Component ORCH -Message "$FunctionName threw: $_"
            return $null
        }
    }

    #endregion

    #region ─── STAGE 1: SYSTEM INVENTORY (Type1) ─────────────────────────────────

    function Show-Stage1Menu {
        [CmdletBinding()]
        param()

        Clear-Host
        Write-Host ""
        Write-Host "  ┌─────────────────────────────────────────────────────────┐" -ForegroundColor DarkCyan
        Write-Host "  │         STAGE 1 — SYSTEM INVENTORY                     │" -ForegroundColor White
        Write-Host "  ├─────────────────────────────────────────────────────────┤" -ForegroundColor DarkCyan
        Write-Host "  │  0  - Run ALL modules (default)                         │" -ForegroundColor Green
        foreach ($pair in $ModulePairs) {
            $line = "  │  $($pair.Num)  - $($pair.Label)"
            Write-Host ($line.PadRight(60) + '│') -ForegroundColor Cyan
        }
        Write-Host "  ├─────────────────────────────────────────────────────────┤" -ForegroundColor DarkCyan
        Write-Host "  │  Comma-separated for multiple: e.g. 1,3,5              │" -ForegroundColor DarkGray
        Write-Host "  └─────────────────────────────────────────────────────────┘" -ForegroundColor DarkCyan
        Write-Host ""
    }

    function Clear-PendingConsoleInput {
        # Drains any keystrokes already sitting in the console's input buffer before a
        # timed "press a key to..." loop starts polling. Without this, a key pressed
        # ages ago - an accidental Enter while scrolling, a stray keystroke during a
        # long unattended Stage 1-4 run - stays buffered and is picked up on the very
        # FIRST KeyAvailable check of the next countdown, causing an immediate, silent
        # "abort"/"selection" nobody actually intended right now. Only keys pressed
        # AFTER this point (i.e. during the countdown the user can actually see) should
        # count.
        [CmdletBinding()]
        param()
        try {
            while ([Console]::KeyAvailable) { $null = [Console]::ReadKey($true) }
        }
        catch {
            # No real console attached / input redirected - nothing to drain.
            $null = $_
        }
    }

    function Get-MenuSelection {
        [CmdletBinding()]
        param([int]$Countdown = 10)

        $selected = $null
        Clear-PendingConsoleInput
        $deadline = (Get-Date).AddSeconds($Countdown)

        while ((Get-Date) -lt $deadline) {
            $remaining = [int]($deadline - (Get-Date)).TotalSeconds
            Write-Host "`r  Auto-running option 0 in $remaining second(s)... [enter number(s) to select]  " `
                -NoNewline -ForegroundColor Yellow

            # Defensive: [Console]::KeyAvailable throws if stdin has no real console
            # attached (e.g. launched in a context without one). Treat that the same
            # as "no key pressed" rather than letting it crash the run.
            $keyAvailable = $false
            try { $keyAvailable = [Console]::KeyAvailable }
            catch { $keyAvailable = $false }

            if ($keyAvailable) {
                # ReadKey/Read-Host can throw if stdin is redirected or the console is not
                # truly interactive — treat that as "no selection" (fall through to run-all)
                # rather than letting it crash Stage 1.
                try {
                    $null = [Console]::ReadKey($true)   # consume the trigger key-press only
                    $key = Read-Host "`n  Your choice (comma-separated)"
                    # Parse comma-separated input: "1,3,5" → @(1, 3, 5)
                    $parsed = @($key -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ })
                    if ($parsed.Count -gt 0) { $selected = $parsed }
                }
                catch {
                    Write-Log -Level WARN -Component ORCH -Message "Menu input unavailable ($_) — defaulting to run-all"
                }
                break
            }
            Start-Sleep -Milliseconds 500
        }

        Write-Host ""
        return $selected   # $null = timeout (run all); array of ints otherwise
    }

    $SessionResults = [System.Collections.Generic.List[hashtable]]::new()
    $selectedPairs = $null   # $null = all

    Write-Host ""
    Write-Host "━━━━━━━━━━━━━━━━━━  STAGE 1 : SYSTEM INVENTORY  ━━━━━━━━━━━━━━━━━━" -ForegroundColor Magenta
    Write-Log -Level INFO -Component ORCH -Message "Stage 1 started"

    if ($TaskNumbers) {
        # Non-interactive equivalent of the Stage 1 menu selection, for Task Scheduler /
        # script.bat -TaskNumbers callers that want to run a specific subset unattended.
        $parsed = @($TaskNumbers -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ })
        if ($parsed.Count -gt 0 -and (0 -notin $parsed)) {
            $selectedPairs = $ModulePairs | Where-Object { $_.Num -in $parsed }
            if (-not $selectedPairs) {
                Write-Log -Level WARN -Component ORCH -Message "TaskNumbers '$TaskNumbers' matched no modules - running all"
                $selectedPairs = $null
            }
            else {
                $names = ($selectedPairs | ForEach-Object { $_.Label }) -join ', '
                Write-Log -Level INFO -Component ORCH -Message "TaskNumbers filter applied: $names"
            }
        }
    }
    elseif (-not $NonInteractive) {
        Show-Stage1Menu
        $choice = Get-MenuSelection -Countdown 10

        if ($null -ne $choice -and @($choice) -notcontains 0) {
            $selectedPairs = $ModulePairs | Where-Object { $_.Num -in $choice }
            if (-not $selectedPairs) {
                Write-Host "  [WARN] Invalid selection '$($choice -join ',')' - running all modules." -ForegroundColor Yellow
                $selectedPairs = $null
            }
            else {
                $names = ($selectedPairs | ForEach-Object { $_.Label }) -join ', '
                Write-Host "  Selected: $names" -ForegroundColor Green
            }
        }
    }

    $pairsToAudit = if ($null -eq $selectedPairs) { $ModulePairs } else { @($selectedPairs) }

    $consecutiveFailures = 0
    $maxConsecutiveFailures = 3   # Circuit-breaker: abort stage after N consecutive failures

    foreach ($pair in $pairsToAudit) {
        Write-Host ""
        Write-Host "  ▶  $($pair.Label) [Type1]" -ForegroundColor Cyan
        Write-Log -Level INFO -Component ORCH -Message "Running Type1: $($pair.Type1Func)"

        $start = Get-Date
        $result = Invoke-ModuleFunction -ModuleFile $pair.Type1File -FunctionName $pair.Type1Func

        $duration = [int]((Get-Date) - $start).TotalSeconds

        if ($null -eq $result) {
            $r = New-ModuleResult -ModuleName $pair.Type1Func -Status 'Failed' -ModuleType 'Type1' -Message 'Module returned null'
        }
        elseif ($result -is [hashtable]) {
            $r = $result
            if (-not $r.ContainsKey('ModuleType')) { $r.ModuleType = 'Type1' }
        }
        else {
            $r = New-ModuleResult -ModuleName $pair.Type1Func -Status 'Success' -ModuleType 'Type1' -Message "Completed in ${duration}s"
        }

        $SessionResults.Add($r)
        Write-Log -Level INFO -Component ORCH -Message "$($pair.Type1Func) → $($r.Status) | Detected:$($r.ItemsDetected)"

        # Circuit-breaker: if too many consecutive failures, likely a systemic issue
        if ($r.Status -eq 'Failed') {
            $consecutiveFailures++
            if ($consecutiveFailures -ge $maxConsecutiveFailures) {
                Write-Log -Level ERROR -Component ORCH -Message "CIRCUIT BREAKER: $consecutiveFailures consecutive failures — aborting Stage 1"
                Write-Host "  [ERROR] $consecutiveFailures consecutive module failures. Possible systemic issue — aborting Stage 1." -ForegroundColor Red
                break
            }
        }
        else {
            $consecutiveFailures = 0
        }
    }

    Write-Log -Level SUCCESS -Component ORCH -Message "Stage 1 complete: $($pairsToAudit.Count) modules run"

    #endregion

    #region ─── STAGE 2: DIFF ANALYSIS ───────────────────────────────────────────

    Write-Host ""
    Write-Host "━━━━━━━━━━━━━━━━━━  STAGE 2 : DIFF ANALYSIS  ━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Magenta
    Write-Log -Level INFO -Component ORCH -Message "Stage 2: analysing diffs"

    $actionNeeded = [System.Collections.Generic.List[hashtable]]::new()

    foreach ($pair in $pairsToAudit) {
        if (-not $pair.Type2Func) { continue }   # inventory-only modules skip

        try {
            $configSkip = if ($pair.ConfigSkip -and $Config.modules.$($pair.ConfigSkip)) { $true } else { $false }
            if ($configSkip) {
                Write-Log -Level INFO -Component ORCH -Message "Skipped (config): $($pair.Type2Func)"
                continue
            }

            $diff = Get-DiffList -ModuleName $pair.DiffKey
            if ($diff -and $diff.Count -gt 0) {
                Write-Host "  ✔  $($pair.Label): $($diff.Count) item(s) queued for action" -ForegroundColor Green
                Write-Log -Level INFO -Component ORCH -Message "$($pair.DiffKey): $($diff.Count) diff items - Type2 will run"
                $actionNeeded.Add($pair)
            }
            else {
                Write-Host "  ─  $($pair.Label): no changes needed — SKIPPED" -ForegroundColor DarkGray
                Write-Log -Level INFO -Component ORCH -Message "$($pair.DiffKey): 0 diff items - Type2 SKIPPED"

                $SessionResults.Add((New-ModuleResult -ModuleName $pair.Type2Func `
                            -Status 'Skipped' -ModuleType 'Type2' `
                            -Message 'No diff items — system already in desired state'))
            }
        }
        catch {
            # One malformed diff/config entry must not abort Stage 2 for the other pairs.
            Write-Log -Level ERROR -Component ORCH -Message "Stage 2 error for $($pair.DiffKey): $_"
        }
    }

    Write-Log -Level SUCCESS -Component ORCH -Message "Stage 2 complete: $($actionNeeded.Count) Type2 module(s) will execute"

    #endregion

    #region ─── STAGE 3: MAINTENANCE (Type2) ──────────────────────────────────────

    # Execute in a deliberate order, independent of Stage 1/2 order:
    #   1. RestorePoint FIRST - RestorePointAudit unconditionally queues a 'create' action every
    #      run, and it's only a useful rollback safety net if taken BEFORE the other Type2
    #      modules start mutating the system, not after.
    #   2. SystemConfiguration - hardening (incl. re-enabling Defender if found off).
    #   3. SoftwareManagement - bloatware removal, essential-app installs, upgrades.
    #   4. WindowsUpdates.
    #   5. DiskCleanup LAST so it sweeps up the temp/cache/component-store residue this run's
    #      own actions just produced (installer downloads, WU download cache, etc.) instead of
    #      running before them and being immediately re-dirtied.
    $Stage3Order = @('RestorePoint', 'SystemConfiguration', 'SoftwareManagement', 'WindowsUpdates', 'DiskCleanup')
    $actionNeeded = @($actionNeeded | Sort-Object { $i = $Stage3Order.IndexOf($_.DiffKey); if ($i -lt 0) { 999 } else { $i } })

    Write-Host ""
    Write-Host "━━━━━━━━━━━━━━━━━━  STAGE 3 : MAINTENANCE  ━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Magenta
    Write-Log -Level INFO -Component ORCH -Message "Stage 3 started: $($actionNeeded.Count) module(s)"

    if ($actionNeeded.Count -eq 0) {
        Write-Host "  ✔  System is already in the desired state. No changes required." -ForegroundColor Green
        Write-Log -Level SUCCESS -Component ORCH -Message "No Type2 actions required"
    }
    else {
        foreach ($pair in $actionNeeded) {
            Write-Host ""
            Write-Host "  ▶  $($pair.Label) [Type2]" -ForegroundColor Yellow
            Write-Log -Level INFO -Component ORCH -Message "Running Type2: $($pair.Type2Func)"

            $start = Get-Date
            $result = Invoke-ModuleFunction -ModuleFile $pair.Type2File `
                -FunctionName $pair.Type2Func `
                -FuncParams @{ OSContext = $global:OSContext }

            $duration = [int]((Get-Date) - $start).TotalSeconds

            if ($null -eq $result) {
                $r = New-ModuleResult -ModuleName $pair.Type2Func -Status 'Failed' -ModuleType 'Type2' -Message 'Module returned null'
            }
            elseif ($result -is [hashtable] -and $result.ContainsKey('Status')) {
                $r = $result
                if (-not $r.ContainsKey('ModuleType')) { $r.ModuleType = 'Type2' }
            }
            else {
                $r = New-ModuleResult -ModuleName $pair.Type2Func -Status 'Success' -ModuleType 'Type2' -Message "Completed in ${duration}s"
            }

            $SessionResults.Add($r)
            Write-Log -Level INFO -Component ORCH -Message "$($pair.Type2Func) → $($r.Status) | Processed:$($r.ItemsProcessed)"
        }
    }

    Write-Log -Level SUCCESS -Component ORCH -Message "Stage 3 complete"

    #endregion

    #region ─── STAGE 4: REPORT GENERATION ───────────────────────────────────────

    Write-Host ""
    Write-Host "━━━━━━━━━━━━━━━━━━  STAGE 4 : REPORT GENERATION  ━━━━━━━━━━━━━━━━" -ForegroundColor Magenta
    Write-Log -Level INFO -Component ORCH -Message "Stage 4: generating HTML report"

    # maintenance.log is auto-flushed (FileShare.ReadWrite), so the report can embed it
    # live — no transcript stop/restart gymnastics, and no Stage-4 logging blind spot.
    $ReportGenPath = Join-Path $ProjectRoot 'modules\core\ReportGenerator.psm1'
    if (Test-Path $ReportGenPath) {
        try { Import-Module $ReportGenPath -Force -ErrorAction Stop }
        catch { Write-Log -Level ERROR -Component ORCH -Message "ReportGenerator import failed: $_" }
    }
    else {
        Write-Log -Level ERROR -Component ORCH -Message "ReportGenerator module not found: $ReportGenPath"
    }

    $reportFile = $null
    $destReport = $null

    # (Re)generate the HTML report embedding the CURRENT maintenance.log and copy it to the
    # launcher folder. Called here in Stage 4 (so a report survives a later crash) and again
    # right before cleanup deletes the project folder — that second call captures the full log
    # (incl. Stage 5) into the copy that survives, since the on-disk maintenance.log is deleted.
    function Publish-MaintenanceReport {
        [CmdletBinding()]
        param()
        try {
            $rf = New-MaintenanceReport -SessionResults $SessionResults.ToArray() `
                -OSContext      $global:OSContext `
                -TranscriptPath $LogPath `
                -ReportTitle    'Windows Maintenance Report'

            $launcherDir = $env:ORIGINAL_SCRIPT_DIR
            $copyTarget = if ($launcherDir -and (Test-Path $launcherDir)) { $launcherDir } else { $ProjectRoot }
            $dest = Join-Path $copyTarget (Split-Path $rf -Leaf)
            # Avoid leaving two copies in the launcher folder if the filename changed.
            if ($script:destReport -and $script:destReport -ne $dest -and (Test-Path $script:destReport)) {
                Remove-Item $script:destReport -Force -ErrorAction SilentlyContinue
            }
            Copy-Item -Path $rf -Destination $dest -Force
            $script:reportFile = $rf
            $script:destReport = $dest
            Write-Log -Level SUCCESS -Component ORCH -Message "Report published to: $dest"
        }
        catch {
            Write-Log -Level ERROR -Component ORCH -Message "Report generation failed: $_"
        }
    }

    Publish-MaintenanceReport

    # ── Deferred self-update ───────────────────────────────────────────────────────────
    # script.bat cannot overwrite itself while cmd.exe is streaming it from disk (doing so
    # makes execution resume at the same byte offset inside the new content and jump into
    # unrelated code). The launcher therefore hands the freshly-extracted copy to us via
    # $env:PENDING_SCRIPT_UPDATE, and we copy it into the launcher folder from this separate
    # process, after the launcher has exited.
    if ($env:PENDING_SCRIPT_UPDATE -and (Test-Path $env:PENDING_SCRIPT_UPDATE)) {
        try {
            $launcherDir = $env:ORIGINAL_SCRIPT_DIR
            if ($launcherDir -and (Test-Path $launcherDir)) {
                $destBat = Join-Path $launcherDir 'script.bat'
                Copy-Item -Path $env:PENDING_SCRIPT_UPDATE -Destination $destBat -Force -ErrorAction Stop
                Write-Log -Level SUCCESS -Component ORCH -Message "script.bat self-update applied: $destBat"
            }
        }
        catch {
            Write-Log -Level WARN -Component ORCH -Message "script.bat self-update failed: $_"
        }
    }

    #endregion

    #region ─── STAGE 5: COUNTDOWN + CLEANUP + REBOOT ─────────────────────────────

    Write-Host ""
    Write-Host "━━━━━━━━━━━━━━━━━━  STAGE 5 : CLEANUP & REBOOT  ━━━━━━━━━━━━━━━━━" -ForegroundColor Magenta
    Write-Host ""

    # Removes the Windows Defender exclusions script.bat adds before dependency
    # installation (working dir + powershell.exe/pwsh.exe), so this run's
    # maintenance session doesn't leave a permanent, unscoped AV exclusion behind
    # on the machine after cleanup. Paired setup/teardown for the same paths/processes
    # script.bat's dependency-management phase excludes.
    function Remove-DefenderSessionExclusions {
        [CmdletBinding()]
        param([Parameter(Mandatory)] [string]$WorkingDir)
        try {
            Remove-MpPreference -ExclusionPath $WorkingDir -ErrorAction SilentlyContinue
            Remove-MpPreference -ExclusionProcess 'powershell.exe' -ErrorAction SilentlyContinue
            Remove-MpPreference -ExclusionProcess 'pwsh.exe' -ErrorAction SilentlyContinue
            Write-Log -Level INFO -Component ORCH -Message "Removed Defender exclusions for $WorkingDir"
        }
        catch {
            Write-Log -Level WARN -Component ORCH -Message "Could not remove Defender exclusions: $_"
        }
    }

    # Remove the exclusions FIRST, unconditionally - Stage 3/4 work (the only reason the
    # exclusions exist) is already finished by this point. Doing this before the countdown
    # below - rather than nested inside each cleanup branch - means an ABORTED reboot no
    # longer leaves the machine's PowerShell permanently unscanned by Defender: previously
    # this only ran on the two cleanup paths, so pressing a key to keep files also silently
    # kept the AV exclusion forever.
    Write-Log -Level INFO -Component ORCH -Message "Stage 5: removing session Defender exclusions"
    Remove-DefenderSessionExclusions -WorkingDir $ProjectRoot

    $reportDisplay = if ($reportFile) { Split-Path $reportFile -Leaf } else { 'N/A' }

    $rebootSeconds = [int]($Config.execution.shutdown.countdownSeconds ?? 120)
    $doReboot = [bool]($Config.execution.shutdown.rebootOnTimeout ?? $true)
    $doCleanup = [bool]($Config.execution.shutdown.cleanupOnTimeout ?? $true)
    $rebootOnlyWhenRequired = [bool]($Config.execution.shutdown.rebootOnlyWhenRequired ??
        $Config.execution.shutdown.rebootOnlyForWindowsUpdates ?? $false)
    $aborted = $false

    # If reboot is conditional, check ALL module results for a RebootRequired flag
    if ($doReboot -and $rebootOnlyWhenRequired) {
        $needsReboot = $SessionResults | Where-Object {
            $_.RebootRequired -eq $true -or $_.ExtraData.RebootRequired -eq $true
        }
        if (-not $needsReboot) {
            Write-Host "  [INFO] Reboot skipped — no module flagged a reboot requirement." -ForegroundColor Cyan
            Write-Log -Level INFO -Component ORCH -Message "Stage 5: reboot skipped — no module flagged a reboot requirement."
            $doReboot = $false
        }
        else {
            $rebootModules = ($needsReboot | ForEach-Object { $_.ModuleName }) -join ', '
            Write-Host "  [INFO] Reboot required by: $rebootModules" -ForegroundColor Yellow
            Write-Log -Level WARN -Component ORCH -Message "Stage 5: reboot required by: $rebootModules"
        }
    }

    # ── When no reboot is needed, skip the countdown entirely ─────────────────
    if (-not $doReboot) {
        Write-Host ""
        Write-Host "  ┌───────────────────────────────────────────────────────────┐" -ForegroundColor DarkCyan
        Write-Host "  │                 MAINTENANCE COMPLETE                      │" -ForegroundColor White
        Write-Host "  │                                                           │" -ForegroundColor DarkCyan
        Write-Host "  │  HTML report:  $($reportDisplay.PadRight(43))│" -ForegroundColor Cyan
        Write-Host "  │                                                           │" -ForegroundColor DarkCyan
        Write-Host "  │  No reboot required.                                     │" -ForegroundColor Green
        Write-Host "  └───────────────────────────────────────────────────────────┘" -ForegroundColor DarkCyan
        Write-Host ""

        if ($doCleanup) {
            Write-Log -Level INFO -Component ORCH -Message "No reboot required; cleaning up. Refreshing report so the full log is embedded before deletion."
            # Regenerate so the surviving report copy embeds the complete maintenance.log
            # (the on-disk log is deleted with the folder below).
            Publish-MaintenanceReport
            Write-Host "  Removing project folder..." -ForegroundColor DarkGray
            try {
                Close-LogFile   # release the maintenance.log handle so the folder can be deleted
                # Windows won't remove a directory that is a live process's current working
                # directory - move out of $ProjectRoot first so the delete below can't fail
                # on that account.
                Set-Location -Path ([System.IO.Path]::GetTempPath()) -ErrorAction SilentlyContinue
                Remove-Item -Path $ProjectRoot -Recurse -Force -ErrorAction Stop
                Write-Host "  ✔  Project folder removed." -ForegroundColor Green
            }
            catch {
                Write-Host "  [WARN] Could not fully remove project folder: $_" -ForegroundColor Yellow
            }
        }
        exit 0
    }

    # ── Reboot IS needed — show countdown with abort option ───────────────────
    Write-Host "  ┌───────────────────────────────────────────────────────────┐" -ForegroundColor DarkCyan
    Write-Host "  │                 MAINTENANCE COMPLETE                      │" -ForegroundColor White
    Write-Host "  │                                                           │" -ForegroundColor DarkCyan
    Write-Host "  │  HTML report:  $($reportDisplay.PadRight(43))│" -ForegroundColor Cyan
    Write-Host "  │                                                           │" -ForegroundColor DarkCyan
    Write-Host "  │  System will reboot AND project files will be removed.   │" -ForegroundColor Yellow
    Write-Host "  │  Press ANY KEY to abort reboot and keep all files.       │" -ForegroundColor Yellow
    Write-Host "  └───────────────────────────────────────────────────────────┘" -ForegroundColor DarkCyan
    Write-Host ""

    # Same stale-keystroke hazard as Get-MenuSelection above, and far more likely to bite
    # here: Stage 5 starts after potentially hours of unattended Stage 1-4 work, during
    # which any accidental keystroke into this console window (scrolling, a stray Enter)
    # sits buffered and would otherwise be read as an immediate "abort" the instant this
    # loop's first KeyAvailable check runs - before the user has even seen the countdown.
    Clear-PendingConsoleInput
    $deadline = (Get-Date).AddSeconds($rebootSeconds)

    while (-not $aborted -and (Get-Date) -lt $deadline) {
        $remaining = [int]($deadline - (Get-Date)).TotalSeconds
        Write-Host "`r  Rebooting in $remaining second(s)...  " -NoNewline -ForegroundColor Red

        # In -NonInteractive mode (e.g. Task Scheduler with no attached console),
        # never poll the console — [Console]::KeyAvailable throws
        # InvalidOperationException when stdin is redirected or no console exists,
        # which would otherwise crash the run at the very last stage. Interactive
        # mode still defensively catches the same exception rather than trusting
        # a console is genuinely available.
        $keyAvailable = $false
        if (-not $NonInteractive) {
            try { $keyAvailable = [Console]::KeyAvailable }
            catch { $keyAvailable = $false }
        }

        if ($keyAvailable) {
            $null = [Console]::ReadKey($true)
            $aborted = $true
        }
        else {
            Start-Sleep -Milliseconds 1000
        }
    }

    Write-Host ""

    if ($aborted) {
        Write-Host ""
        Write-Host "  ✔  Reboot ABORTED by user." -ForegroundColor Green
        Write-Host "     Project files kept at: $ProjectRoot" -ForegroundColor Cyan
        if ($reportFile) { Write-Host "     Report saved at:   $reportFile" -ForegroundColor Cyan }
        Write-Host ""
        # Files are kept, so maintenance.log survives on disk; no republish needed.
        # Defender exclusions were already removed above (before the countdown), so
        # aborting here does not leave them behind either.
        Write-Log -Level INFO -Component ORCH -Message "Stage 5: reboot aborted by user — project files (and maintenance.log) kept."
        exit 0
    }

    # ── Cleanup entire project folder then Reboot ────────────────────────────────

    Write-Host ""
    Write-Host "  Countdown complete. Proceeding with cleanup and reboot..." -ForegroundColor Yellow
    Write-Log -Level INFO -Component ORCH -Message "Countdown elapsed; proceeding with cleanup and reboot."

    if ($doCleanup) {
        Write-Log -Level INFO -Component ORCH -Message "Cleaning up. Refreshing report so the full log is embedded before deletion."
        # Regenerate so the surviving report copy embeds the complete maintenance.log
        # (the on-disk log is deleted with the folder below, before the reboot).
        Publish-MaintenanceReport
        Write-Host "  Removing project folder: $ProjectRoot ..." -ForegroundColor DarkGray
        try {
            Close-LogFile   # release the maintenance.log handle so the folder can be deleted
            # Windows won't remove a directory that is a live process's current working
            # directory - move out of $ProjectRoot first so the delete below can't fail
            # on that account.
            Set-Location -Path ([System.IO.Path]::GetTempPath()) -ErrorAction SilentlyContinue
            Remove-Item -Path $ProjectRoot -Recurse -Force -ErrorAction Stop
            Write-Host "  ✔  Project folder removed." -ForegroundColor Green
        }
        catch {
            Write-Host "  [WARN] Could not fully remove project folder: $_" -ForegroundColor Yellow
        }
    }

    Write-Host "  Initiating system reboot..." -ForegroundColor Yellow
    try {
        Restart-Computer -Force
    }
    catch {
        Write-Host "  [ERROR] Restart-Computer failed: $_" -ForegroundColor Red
        exit 1
    }

    exit 0

    #endregion

}
# ── Fatal-capture guard: any uncaught terminating error from the body lands here.
#    'exit 1' still runs the finally block before the process terminates.
catch {
    Write-LogException -Component ORCH -Message 'FATAL: unhandled orchestrator error' -ErrorRecord $_
    Write-Host ""
    Write-Host "  [FATAL] Maintenance aborted by an unhandled error — see maintenance.log:" -ForegroundColor Red
    Write-Host "          $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
finally {
    # Always flush/close the unified maintenance.log, even on crash or exit.
    Close-LogFile
}
