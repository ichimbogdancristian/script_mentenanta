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

.NOTES
    Author:  Windows Maintenance Automation Project
    Version: 5.0.0
    Requires: PowerShell 7+, Administrator
#>
[CmdletBinding()]
param(
    [switch]$NonInteractive
)

Set-StrictMode -Off
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'Continue'

#region ─── SCRIPT ROOT & PATHS ───────────────────────────────────────────────

$ProjectRoot = $PSScriptRoot
if (-not $ProjectRoot) { $ProjectRoot = (Get-Location).Path }

$TempDir = Join-Path $ProjectRoot 'temp_files'
$TranscriptPath = Join-Path $TempDir 'logs\maintenance.log'

# Create temp_files structure before transcript starts
foreach ($sub in 'logs', 'data', 'reports', 'diff') {
    $d = Join-Path $TempDir $sub
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
}

#endregion

#region ─── START TRANSCRIPT ──────────────────────────────────────────────────

# maintenance.log = PowerShell transcript of the ENTIRE project run
Start-Transcript -Path $TranscriptPath -Append -Force | Out-Null

# Inject bootstrap log from script.bat launcher if present
if ($env:BOOTSTRAP_LOG -and (Test-Path $env:BOOTSTRAP_LOG)) {
    Write-Host ""
    Write-Host ('=' * 70) -ForegroundColor DarkGray
    Write-Host '  LAUNCHER LOG  (script.bat — pre-orchestrator phase)' -ForegroundColor DarkGray
    Write-Host ('=' * 70) -ForegroundColor DarkGray
    Get-Content $env:BOOTSTRAP_LOG | ForEach-Object { Write-Host $_ -ForegroundColor DarkGray }
    Write-Host ('=' * 70) -ForegroundColor DarkGray
    Write-Host '  END LAUNCHER LOG' -ForegroundColor DarkGray
    Write-Host ('=' * 70) -ForegroundColor DarkGray
    Remove-Item $env:BOOTSTRAP_LOG -Force -ErrorAction SilentlyContinue
    [System.Environment]::SetEnvironmentVariable('BOOTSTRAP_LOG', $null, 'Process')
}

Write-Host ""
Write-Host "======================================================================" -ForegroundColor Magenta
Write-Host "  WINDOWS MAINTENANCE AUTOMATION  v5.0" -ForegroundColor White
Write-Host "  Session start: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Cyan
Write-Host "  Project root:  $ProjectRoot" -ForegroundColor Cyan
Write-Host "  Transcript:    $TranscriptPath" -ForegroundColor Cyan
Write-Host "======================================================================" -ForegroundColor Magenta
Write-Host ""

#endregion

#region ─── LOAD CORE MODULE ──────────────────────────────────────────────────

$CorePath = Join-Path $ProjectRoot 'modules\core\Maintenance.psm1'
if (-not (Test-Path $CorePath)) {
    Write-Host "[ERROR] Core module not found: $CorePath" -ForegroundColor Red
    Stop-Transcript | Out-Null
    exit 1
}
Import-Module $CorePath -Force -Global

# Initialise (sets env vars, creates temp dirs)
Initialize-Maintenance -ProjectRoot $ProjectRoot

#endregion

#region ─── OS & CONFIG ───────────────────────────────────────────────────────

$global:OSContext = Get-OSContext
$Config = Get-MainConfig

Write-Log -Level SUCCESS -Component ORCH -Message "OS: $($global:OSContext.DisplayText)"
Write-Log -Level INFO    -Component ORCH -Message "Config loaded. DryRun: $($Config.execution.enableDryRun)"

#endregion

#region ─── MODULE PAIR REGISTRY ──────────────────────────────────────────────
# Each entry maps a Type1 audit module to its Type2 action counterpart.
# DiffKey must match the -ModuleName used in Save-DiffList / Get-DiffList.

$ModulePairs = @(
    @{
        Num        = 1
        Label      = 'Bloatware Detection & Removal'
        DiffKey    = 'BloatwareRemoval'
        Type1File  = 'modules\type1\BloatwareDetectionAudit.psm1'
        Type1Func  = 'Invoke-BloatwareAudit'
        Type2File  = 'modules\type2\BloatwareRemoval.psm1'
        Type2Func  = 'Invoke-BloatwareRemoval'
        ConfigSkip = 'skipBloatwareRemoval'
    },
    @{
        Num        = 2
        Label      = 'Essential Applications'
        DiffKey    = 'EssentialApps'
        Type1File  = 'modules\type1\EssentialAppsAudit.psm1'
        Type1Func  = 'Invoke-EssentialAppsAudit'
        Type2File  = 'modules\type2\EssentialApps.psm1'
        Type2Func  = 'Invoke-EssentialApp'
        ConfigSkip = 'skipEssentialApps'
    },
    @{
        Num        = 3
        Label      = 'System Optimization'
        DiffKey    = 'SystemOptimization'
        Type1File  = 'modules\type1\SystemOptimizationAudit.psm1'
        Type1Func  = 'Invoke-SystemOptimizationAudit'
        Type2File  = 'modules\type2\SystemOptimization.psm1'
        Type2Func  = 'Invoke-SystemOptimization'
        ConfigSkip = 'skipSystemOptimization'
    },
    @{
        Num        = 4
        Label      = 'Telemetry & Privacy'
        DiffKey    = 'TelemetryDisable'
        Type1File  = 'modules\type1\TelemetryAudit.psm1'
        Type1Func  = 'Invoke-TelemetryAudit'
        Type2File  = 'modules\type2\TelemetryDisable.psm1'
        Type2Func  = 'Invoke-TelemetryDisable'
        ConfigSkip = 'skipTelemetryDisable'
    },
    @{
        Num        = 5
        Label      = 'Security Enhancement'
        DiffKey    = 'SecurityEnhancement'
        Type1File  = 'modules\type1\SecurityAudit.psm1'
        Type1Func  = 'Invoke-SecurityAudit'
        Type2File  = 'modules\type2\SecurityEnhancement.psm1'
        Type2Func  = 'Invoke-SecurityEnhancement'
        ConfigSkip = 'skipSecurityAudit'
    },
    @{
        Num        = 6
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
        Label      = 'Application Upgrades'
        DiffKey    = 'AppUpgrade'
        Type1File  = 'modules\type1\AppUpgradeAudit.psm1'
        Type1Func  = 'Invoke-AppUpgradeAudit'
        Type2File  = 'modules\type2\AppUpgrade.psm1'
        Type2Func  = 'Invoke-AppUpgrade'
        ConfigSkip = 'skipAppUpgrade'
    },
    @{
        Num        = 8
        Label      = 'System Inventory (report only)'
        DiffKey    = 'SystemInventory'
        Type1File  = 'modules\type1\SystemInventory.psm1'
        Type1Func  = 'Invoke-SystemInventory'
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
    Write-Host "  └─────────────────────────────────────────────────────────┘" -ForegroundColor DarkCyan
    Write-Host ""
}

function Get-MenuSelection {
    [CmdletBinding()]
    param([int]$Countdown = 10)

    $selected = $null
    $deadline = (Get-Date).AddSeconds($Countdown)

    while ((Get-Date) -lt $deadline) {
        $remaining = [int]($deadline - (Get-Date)).TotalSeconds
        Write-Host "`r  Auto-running option 0 in $remaining second(s)... [enter number to select]  " `
            -NoNewline -ForegroundColor Yellow

        if ([Console]::KeyAvailable) {
            $null = [Console]::ReadLine()   # consume CR
            $key = Read-Host "`n  Your choice"
            if ($key -match '^\d+$') { $selected = [int]$key }
            break
        }
        Start-Sleep -Milliseconds 500
    }

    Write-Host ""
    return $selected   # $null = timeout (run all)
}

$SessionResults = [System.Collections.Generic.List[hashtable]]::new()
$selectedPairs = $null   # $null = all

Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━  STAGE 1 : SYSTEM INVENTORY  ━━━━━━━━━━━━━━━━━━" -ForegroundColor Magenta
Write-Log -Level INFO -Component ORCH -Message "Stage 1 started"

if (-not $NonInteractive) {
    Show-Stage1Menu
    $choice = Get-MenuSelection -Countdown 10

    if ($null -ne $choice -and $choice -ne 0) {
        $selectedPairs = $ModulePairs | Where-Object { $_.Num -eq $choice }
        if (-not $selectedPairs) {
            Write-Host "  [WARN] Invalid selection '$choice' - running all modules." -ForegroundColor Yellow
            $selectedPairs = $null
        }
    }
}

$pairsToAudit = if ($null -eq $selectedPairs) { $ModulePairs } else { @($selectedPairs) }

foreach ($pair in $pairsToAudit) {
    Write-Host ""
    Write-Host "  ▶  $($pair.Label) [Type1]" -ForegroundColor Cyan
    Write-Log -Level INFO -Component ORCH -Message "Running Type1: $($pair.Type1Func)"

    $start = Get-Date
    $result = Invoke-ModuleFunction -ModuleFile $pair.Type1File -FunctionName $pair.Type1Func

    $duration = [int]((Get-Date) - $start).TotalSeconds

    if ($null -eq $result) {
        $r = New-ModuleResult -ModuleName $pair.Type1Func -Status 'Failed' -Message 'Module returned null'
    }
    elseif ($result -is [hashtable]) {
        $r = $result
    }
    else {
        $r = New-ModuleResult -ModuleName $pair.Type1Func -Status 'Success' -Message "Completed in ${duration}s"
    }

    $SessionResults.Add($r)
    Write-Log -Level INFO -Component ORCH -Message "$($pair.Type1Func) → $($r.Status) | Detected:$($r.ItemsDetected)"
}

Write-Log -Level SUCCESS -Component ORCH -Message "Stage 1 complete: $($pairsToAudit.Count) modules run"

#endregion

#region ─── STAGE 2: DIFF ANALYSIS ───────────────────────────────────────────

Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━  STAGE 2 : DIFF ANALYSIS  ━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Magenta
Write-Log -Level INFO -Component ORCH -Message "Stage 2: analysing diffs"

$actionNeeded = [System.Collections.Generic.List[hashtable]]::new()

foreach ($pair in $ModulePairs) {
    if (-not $pair.Type2Func) { continue }   # inventory-only modules skip

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
                    -Status 'Skipped' `
                    -Message 'No diff items — system already in desired state'))
    }
}

Write-Log -Level SUCCESS -Component ORCH -Message "Stage 2 complete: $($actionNeeded.Count) Type2 module(s) will execute"

#endregion

#region ─── STAGE 3: MAINTENANCE (Type2) ──────────────────────────────────────

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
            $r = New-ModuleResult -ModuleName $pair.Type2Func -Status 'Failed' -Message 'Module returned null'
        }
        elseif ($result -is [hashtable] -and $result.ContainsKey('Status')) {
            $r = $result
        }
        else {
            $r = New-ModuleResult -ModuleName $pair.Type2Func -Status 'Success' -Message "Completed in ${duration}s"
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

# Stop transcript NOW so the log file is flushed before we embed it in the report
Write-Log -Level INFO -Component ORCH -Message "Stopping transcript for report inclusion"
Stop-Transcript | Out-Null

$ReportGenPath = Join-Path $ProjectRoot 'modules\core\ReportGenerator.psm1'
if (Test-Path $ReportGenPath) {
    Import-Module $ReportGenPath -Force
}
else {
    Write-Host "[ERROR] ReportGenerator module not found: $ReportGenPath" -ForegroundColor Red
}

$reportFile = $null
try {
    $reportFile = New-MaintenanceReport -SessionResults $SessionResults.ToArray() `
        -OSContext      $global:OSContext `
        -TranscriptPath $TranscriptPath `
        -ReportTitle    'Windows Maintenance Report'

    Write-Host "  ✔  Report: $reportFile" -ForegroundColor Green

    # Copy report to the folder where script.bat was launched from (e.g. USB drive / Desktop)
    $launcherDir = $env:ORIGINAL_SCRIPT_DIR
    $copyTarget  = if ($launcherDir -and (Test-Path $launcherDir)) { $launcherDir } else { $ProjectRoot }
    $destReport  = Join-Path $copyTarget (Split-Path $reportFile -Leaf)
    Copy-Item -Path $reportFile -Destination $destReport -Force
    Write-Host "  ✔  Report also saved to: $destReport" -ForegroundColor Green
}
catch {
    Write-Host "  [ERROR] Report generation failed: $_" -ForegroundColor Red
}

#endregion

#region ─── STAGE 5: COUNTDOWN + CLEANUP + REBOOT ─────────────────────────────

Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━  STAGE 5 : CLEANUP & REBOOT  ━━━━━━━━━━━━━━━━━" -ForegroundColor Magenta
Write-Host ""

$reportDisplay = if ($reportFile) { Split-Path $reportFile -Leaf } else { 'N/A' }

Write-Host "  ┌───────────────────────────────────────────────────────────┐" -ForegroundColor DarkCyan
Write-Host "  │                 MAINTENANCE COMPLETE                      │" -ForegroundColor White
Write-Host "  │                                                           │" -ForegroundColor DarkCyan
Write-Host "  │  HTML report:  $($reportDisplay.PadRight(43))│" -ForegroundColor Cyan
Write-Host "  │                                                           │" -ForegroundColor DarkCyan
Write-Host "  │  System will reboot AND temp files will be removed.      │" -ForegroundColor Yellow
Write-Host "  │  Press ANY KEY to abort reboot and keep all files.       │" -ForegroundColor Yellow
Write-Host "  └───────────────────────────────────────────────────────────┘" -ForegroundColor DarkCyan
Write-Host ""

$rebootSeconds = [int]($Config.execution.shutdown.countdownSeconds ?? 120)
$doReboot = [bool]($Config.execution.shutdown.rebootOnTimeout ?? $true)
$doCleanup = [bool]($Config.execution.shutdown.cleanupOnTimeout ?? $true)
$aborted = $false
$deadline = (Get-Date).AddSeconds($rebootSeconds)

if ($NonInteractive -and -not $doReboot) {
    Write-Host "  [NonInteractive + reboot disabled] Exiting without reboot." -ForegroundColor DarkGray
    $aborted = $true
}

while (-not $aborted -and (Get-Date) -lt $deadline) {
    $remaining = [int]($deadline - (Get-Date)).TotalSeconds
    Write-Host "`r  Rebooting in $remaining second(s)...  " -NoNewline -ForegroundColor Red

    if ([Console]::KeyAvailable) {
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
    Write-Host "     Temp files kept at: $TempDir" -ForegroundColor Cyan
    if ($reportFile) { Write-Host "     Report saved at:   $reportFile" -ForegroundColor Cyan }
    Write-Host ""
    exit 0
}

# ── Cleanup then Reboot ──────────────────────────────────────────────────────

Write-Host ""
Write-Host "  Countdown complete. Proceeding with cleanup and reboot..." -ForegroundColor Yellow

if ($doCleanup) {
    Write-Host "  Removing temp_files..." -ForegroundColor DarkGray
    try {
        Remove-Item -Path $TempDir -Recurse -Force -ErrorAction Stop
        Write-Host "  ✔  temp_files removed." -ForegroundColor Green
    }
    catch {
        Write-Host "  [WARN] Could not fully remove temp_files: $_" -ForegroundColor Yellow
    }
}

if ($doReboot) {
    Write-Host "  Initiating system reboot..." -ForegroundColor Yellow
    try {
        Restart-Computer -Force
    }
    catch {
        Write-Host "  [ERROR] Restart-Computer failed: $_" -ForegroundColor Red
        exit 1
    }
}

exit 0

#endregion
