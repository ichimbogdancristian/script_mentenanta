#Requires -Version 7.0

<#
.SYNOPSIS
    Report Generator - Self-contained, full-width HTML maintenance report (v6).

.DESCRIPTION
    Generates a single-file HTML report from module results and the maintenance.log.
    Everything (CSS + JS) is inlined - no external dependencies, opens straight from disk.

    v6 redesign:
      - PC "System Overview" surfaced at the TOP (identity, OS, CPU, memory, disk meters,
        network) instead of buried mid-page.
      - Full-viewport-width layout (no 1200px cap); grids reflow across wide monitors.
      - maintenance.log is PARSED into structured entries (ts/level/component/message)
        and rendered as an interactive console: per-level counts + distribution bar,
        clickable level filters, component dropdown, and a live text search. Replaces the
        old opaque <pre> dump.
      - Light/dark theme toggle (persisted to localStorage), refined visual system.

    Output:
      temp_files/reports/MaintenanceReport_[timestamp].html
      [launcher folder]/MaintenanceReport_[timestamp].html  (copy)

.NOTES
    Module Type: Core (Report Generation)
    Version: 6.0.0
    Import: Import-Module ReportGenerator.psm1 -Force
#>

Add-Type -AssemblyName System.Web -ErrorAction SilentlyContinue

#region ─── SHARED HELPERS ─────────────────────────────────────────────────────

<#
.SYNOPSIS
    HTML-escapes a string (ampersand first). $null -> ''.
#>
function ConvertTo-HtmlText {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter()] [AllowNull()] [object]$Text)
    if ($null -eq $Text) { return '' }
    return ([string]$Text) -replace '&', '&amp;' -replace '<', '&lt;' -replace '>', '&gt;' -replace '"', '&quot;'
}

<#
.SYNOPSIS
    Loads system-inventory.json (produced by the SystemInventory module) if present.
.OUTPUTS
    [pscustomobject] or $null.
#>
function Get-InventoryData {
    [CmdletBinding()]
    param()
    $path = Get-TempPath -Category 'data' -FileName 'system-inventory.json' -ErrorAction SilentlyContinue
    if (-not $path -or -not (Test-Path $path)) { return $null }
    try { return (Get-Content -Path $path -Raw -Encoding UTF8 | ConvertFrom-Json) }
    catch { return $null }
}

<#
.SYNOPSIS
    Human-readable uptime from a 'yyyy-MM-dd HH:mm:ss' last-boot string.
#>
function Format-Uptime {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter()] [string]$LastBoot)
    if (-not $LastBoot) { return 'Unknown' }
    try {
        $boot = [datetime]::Parse($LastBoot)
        $span = (Get-Date) - $boot
        $parts = @()
        if ($span.Days -gt 0) { $parts += "$($span.Days)d" }
        $parts += "$($span.Hours)h"
        $parts += "$($span.Minutes)m"
        return ($parts -join ' ')
    }
    catch { return 'Unknown' }
}

#endregion

#region ─── LOG PARSING ────────────────────────────────────────────────────────

<#
.SYNOPSIS
    Parses maintenance.log into structured entries.
.DESCRIPTION
    Each line of the form "[ts] [LEVEL] [COMPONENT] message" becomes an object with
    Ts / Level / Component / Message. Lines without that prefix (launcher banners,
    separators, wrapped text) are emitted as Level='RAW' so nothing is lost.
    Reads through a FileStream with FileShare.ReadWrite so it works even while the
    core logger still holds the file open (live embedding during Stage 4).
.OUTPUTS
    [System.Collections.Generic.List[object]]
#>
function ConvertFrom-MaintenanceLog {
    [CmdletBinding()]
    [OutputType([System.Collections.Generic.List[object]])]
    param([Parameter()] [string]$Path)

    $entries = [System.Collections.Generic.List[object]]::new()
    if (-not $Path -or -not (Test-Path $Path)) { return $entries }

    $rx = [regex]'^\[(?<ts>[^\]]+)\]\s\[(?<lvl>[^\]]+)\]\s\[(?<cmp>[^\]]+)\]\s?(?<msg>.*)$'
    $fs = $null; $sr = $null
    try {
        $fs = [System.IO.FileStream]::new($Path, [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        $sr = [System.IO.StreamReader]::new($fs, [System.Text.Encoding]::UTF8)
        while ($null -ne ($line = $sr.ReadLine())) {
            $m = $rx.Match($line)
            if ($m.Success) {
                $ts = $m.Groups['ts'].Value
                # Short time portion (HH:mm:ss) for the compact console column.
                $short = if ($ts -match '(\d{2}:\d{2}:\d{2})') { $Matches[1] } else { $ts }
                $entries.Add([pscustomobject]@{
                        Ts        = $ts
                        ShortTs   = $short
                        Level     = $m.Groups['lvl'].Value.ToUpper()
                        Component = $m.Groups['cmp'].Value
                        Message   = $m.Groups['msg'].Value
                    })
            }
            elseif ($line.Trim()) {
                $entries.Add([pscustomobject]@{
                        Ts = ''; ShortTs = ''; Level = 'RAW'; Component = ''; Message = $line
                    })
            }
        }
    }
    catch { Write-Log -Level DEBUG -Component REPORT -Message "Log parse failed: $_" }
    finally {
        if ($sr) { $sr.Dispose() }
        if ($fs) { $fs.Dispose() }
    }
    return $entries
}

<#
.SYNOPSIS
    Builds the interactive, filterable log-console HTML section from parsed entries.
#>
function Build-LogConsole {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [AllowEmptyCollection()] [System.Collections.Generic.List[object]]$Entries)

    if ($Entries.Count -eq 0) {
        return '<section class="card logs"><div class="card-hd"><span class="card-ttl">&#128220; Maintenance Log</span></div><div class="card-bd"><p class="muted">No log entries available.</p></div></section>'
    }

    # ── Order + counts ───────────────────────────────────────────────────────
    $levelOrder = 'FATAL', 'ERROR', 'WARN', 'SUCCESS', 'INFO', 'DEBUG', 'RAW'
    $counts = [ordered]@{}
    foreach ($lv in $levelOrder) { $counts[$lv] = 0 }
    $components = [System.Collections.Generic.SortedSet[string]]::new()
    foreach ($e in $Entries) {
        if (-not $counts.Contains($e.Level)) { $counts[$e.Level] = 0 }
        $counts[$e.Level]++
        if ($e.Component) { [void]$components.Add($e.Component) }
    }
    $total = $Entries.Count

    # ── Distribution bar (stacked proportion of levels) ──────────────────────
    # ${lv} is brace-delimited so the ':' in the title text isn't parsed as a scope ref.
    $barSegs = foreach ($lv in $levelOrder) {
        $c = $counts[$lv]
        if ($c -le 0) { continue }
        $pct = [math]::Round(($c / $total) * 100, 2)
        "<span class='seg lvl-bg-$lv' style='width:$pct%' title='${lv}: $c'></span>"
    }
    $barHtml = ($barSegs -join '')

    # ── Level filter chips (DEBUG + RAW start OFF to cut noise) ───────────────
    $defaultOff = @('DEBUG', 'RAW')
    $chipHtml = foreach ($lv in $levelOrder) {
        $c = $counts[$lv]
        if ($c -le 0) { continue }
        $active = if ($lv -in $defaultOff) { '' } else { ' active' }
        "<button type='button' class='lvl-chip lvl-$lv$active' data-level='$lv'><span class='dot'></span>$lv<span class='cnt'>$c</span></button>"
    }
    $chipHtml = ($chipHtml -join '')

    # ── Component dropdown ───────────────────────────────────────────────────
    $compOpts = "<option value='ALL'>All components</option>"
    foreach ($cmp in $components) {
        $ce = ConvertTo-HtmlText $cmp
        $compOpts += "<option value='$ce'>$ce</option>"
    }

    # ── Rows ─────────────────────────────────────────────────────────────────
    $rowSb = [System.Text.StringBuilder]::new()
    foreach ($e in $Entries) {
        $msgEnc = ConvertTo-HtmlText $e.Message
        $cmpEnc = ConvertTo-HtmlText $e.Component
        # data-text: lowercased haystack for the search box (component + message).
        $hay = (ConvertTo-HtmlText (("$($e.Component) $($e.Message)").ToLowerInvariant()))
        if ($e.Level -eq 'RAW') {
            $isSep = $e.Message -match '^\s*[=\-]{3,}\s*$'
            $cls = if ($isSep) { 'log-row raw sep' } else { 'log-row raw' }
            [void]$rowSb.Append("<div class='$cls' data-level='RAW' data-comp='' data-text='$hay'><span class='lr-msg'>$msgEnc</span></div>")
        }
        else {
            [void]$rowSb.Append("<div class='log-row' data-level='$($e.Level)' data-comp='$cmpEnc' data-text='$hay'><span class='lr-ts'>$($e.ShortTs)</span><span class='lr-lvl lvl-$($e.Level)'>$($e.Level)</span><span class='lr-cmp'>$cmpEnc</span><span class='lr-msg'>$msgEnc</span></div>")
        }
    }

    return @"
<section class="card logs">
  <div class="card-hd">
    <span class="card-ttl">&#128220; Maintenance Log</span>
    <span class="card-sub"><b id="logShown">$total</b> of $total lines</span>
  </div>
  <div class="log-dist">$barHtml</div>
  <div class="log-toolbar">
    <div class="lvl-chips">$chipHtml</div>
    <div class="log-controls">
      <select id="logComp" class="log-select">$compOpts</select>
      <input id="logSearch" class="log-search" type="search" placeholder="&#128269;  Filter log text..." autocomplete="off" />
    </div>
  </div>
  <div class="log-body">
    $($rowSb.ToString())
  </div>
</section>
"@
}

#endregion

#region ─── SYSTEM OVERVIEW (top of report) ────────────────────────────────────

<#
.SYNOPSIS
    Builds the top-of-report PC overview: identity, OS, CPU, memory, disk meters,
    network. Degrades gracefully to OSContext/env facts when inventory is absent.
#>
function Build-SystemOverview {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()] [AllowNull()] $Inv,
        [Parameter(Mandatory)] [hashtable]$OSContext,
        [Parameter()] [string]$PSVer,
        [Parameter()] [string]$RunAs
    )

    $hostname = ConvertTo-HtmlText $env:COMPUTERNAME

    # ── Identity ─────────────────────────────────────────────────────────────
    $userName = ConvertTo-HtmlText ($Inv.Session.UserName ?? $env:USERNAME)
    $domain = ConvertTo-HtmlText ($Inv.Session.Domain ?? $env:USERDOMAIN)
    $isAdmin = if ($null -ne $Inv.Session.IsAdmin) { [bool]$Inv.Session.IsAdmin } else { $true }
    $adminPill = if ($isAdmin) { "<span class='pill ok'>Administrator</span>" } else { "<span class='pill warn'>Standard</span>" }

    # ── OS ───────────────────────────────────────────────────────────────────
    $osCaption = ConvertTo-HtmlText ($Inv.OS.Caption ?? $OSContext.Caption)
    $osBuild = ConvertTo-HtmlText ($Inv.OS.BuildNumber ?? $OSContext.BuildNumber)
    $osArch = ConvertTo-HtmlText ($Inv.OS.Architecture ?? '')
    $osInstall = ConvertTo-HtmlText ($Inv.OS.InstallDate ?? '')
    $uptime = ConvertTo-HtmlText (Format-Uptime -LastBoot ([string]$Inv.OS.LastBootUpTime))

    # ── CPU / Memory ─────────────────────────────────────────────────────────
    $cpuName = ConvertTo-HtmlText ($Inv.CPU.Name ?? 'Unknown CPU')
    $cpuCores = ConvertTo-HtmlText ($Inv.CPU.Cores ?? '?')
    $cpuLogical = ConvertTo-HtmlText ($Inv.CPU.LogicalProcs ?? '?')
    $cpuClock = if ($Inv.CPU.MaxClockMHz) { "$([math]::Round($Inv.CPU.MaxClockMHz / 1000, 2)) GHz" } else { '' }
    $memGB = ConvertTo-HtmlText ($Inv.Memory.TotalGB ?? '?')
    $memModel = ConvertTo-HtmlText (@($Inv.Memory.Manufacturer, $Inv.Memory.Model | Where-Object { $_ }) -join ' ')

    # ── Quick facts ──────────────────────────────────────────────────────────
    $appCount = $Inv.Software.InstalledAppCount ?? $null
    $rpCount = if ($Inv.RestorePoints) { @($Inv.RestorePoints).Count } else { $null }
    $extIP = if ($Inv.ExternalIP.Address -and $Inv.ExternalIP.Address -ne 'Unable to determine') { ConvertTo-HtmlText $Inv.ExternalIP.Address } else { $null }

    $factChips = [System.Collections.Generic.List[string]]::new()
    $factChips.Add("<span class='fact'><span class='fk'>PowerShell</span><span class='fv'>$([System.Web.HttpUtility]::HtmlEncode($PSVer))</span></span>")
    $factChips.Add("<span class='fact'><span class='fk'>Run as</span><span class='fv'>$([System.Web.HttpUtility]::HtmlEncode($RunAs))</span></span>")
    if ($null -ne $appCount) { $factChips.Add("<span class='fact'><span class='fk'>Installed apps</span><span class='fv'>$appCount</span></span>") }
    if ($null -ne $rpCount) { $factChips.Add("<span class='fact'><span class='fk'>Restore points</span><span class='fv'>$rpCount</span></span>") }
    if ($extIP) { $factChips.Add("<span class='fact'><span class='fk'>External IP</span><span class='fv mono'>$extIP</span></span>") }
    $factsHtml = ($factChips -join '')

    # ── Disk meters ──────────────────────────────────────────────────────────
    $diskHtml = ''
    if ($Inv.Disks -and @($Inv.Disks).Count -gt 0) {
        $meters = foreach ($d in $Inv.Disks) {
            $drive = ConvertTo-HtmlText $d.Drive
            $size = [double]($d.SizeGB ?? 0)
            $free = [double]($d.FreeGB ?? 0)
            $used = [math]::Round($size - $free, 1)
            $pct = [double]($d.UsedPct ?? 0)
            $cls = if ($pct -ge 90) { 'crit' } elseif ($pct -ge 70) { 'warn' } else { 'ok' }
            @"
<div class="disk">
  <div class="disk-hd"><span class="disk-drive">&#128190; $drive</span><span class="disk-pct $cls">$pct%</span></div>
  <div class="meter"><span class="meter-fill $cls" style="width:$pct%"></span></div>
  <div class="disk-ft"><span>$used GB used</span><span>$free GB free of $size GB</span></div>
</div>
"@
        }
        $diskHtml = @"
<div class="ov-card wide">
  <div class="ov-card-ttl">&#128190; Storage</div>
  <div class="disks">$($meters -join '')</div>
</div>
"@
    }

    # ── Network ──────────────────────────────────────────────────────────────
    $netHtml = ''
    if ($Inv.Network -and @($Inv.Network).Count -gt 0) {
        $nics = foreach ($n in $Inv.Network) {
            $desc = ConvertTo-HtmlText $n.Description
            $ips = ($n.IPs | ForEach-Object { ConvertTo-HtmlText $_ }) -join ', '
            $dns = ($n.DNSServers | ForEach-Object { ConvertTo-HtmlText $_ }) -join ', '
            $mac = ConvertTo-HtmlText $n.MAC
            @"
<div class="nic">
  <div class="nic-desc">$desc</div>
  <div class="nic-kv"><span>IP</span><span class="mono">$(if($ips){$ips}else{'&mdash;'})</span></div>
  <div class="nic-kv"><span>DNS</span><span class="mono">$(if($dns){$dns}else{'&mdash;'})</span></div>
  <div class="nic-kv"><span>MAC</span><span class="mono">$(if($mac){$mac}else{'&mdash;'})</span></div>
</div>
"@
        }
        $netHtml = @"
<div class="ov-card wide">
  <div class="ov-card-ttl">&#127760; Network</div>
  <div class="nics">$($nics -join '')</div>
</div>
"@
    }

    $cpuClockHtml = if ($cpuClock) { " &middot; $cpuClock" } else { '' }
    $memModelHtml = if ($memModel) { "<div class='ov-sub'>$memModel</div>" } else { '' }
    $osArchHtml = if ($osArch) { " &middot; $osArch" } else { '' }

    return @"
<section class="overview">
  <div class="ov-grid">

    <div class="ov-card identity">
      <div class="ov-card-ttl">&#128421; Machine</div>
      <div class="ov-host">$hostname</div>
      <div class="ov-sub">$userName@$domain</div>
      <div class="ov-pills">$adminPill</div>
    </div>

    <div class="ov-card">
      <div class="ov-card-ttl">&#129513; Operating System</div>
      <div class="ov-big">$osCaption</div>
      <div class="ov-sub">Build $osBuild$osArchHtml</div>
      <div class="ov-mini">
        <span><span class="mk">Installed</span>$(if($osInstall){$osInstall}else{'&mdash;'})</span>
        <span><span class="mk">Uptime</span>$uptime</span>
      </div>
    </div>

    <div class="ov-card">
      <div class="ov-card-ttl">&#9889; Processor</div>
      <div class="ov-big small">$cpuName</div>
      <div class="ov-sub">$cpuCores cores / $cpuLogical threads$cpuClockHtml</div>
    </div>

    <div class="ov-card">
      <div class="ov-card-ttl">&#128190; Memory</div>
      <div class="ov-big">$memGB <span class="unit">GB</span></div>
      $memModelHtml
    </div>

    $diskHtml
    $netHtml
  </div>

  <div class="facts">$factsHtml</div>
</section>
"@
}

#endregion

#region ─── ENTRY POINT ────────────────────────────────────────────────────────

<#
.SYNOPSIS
    Generates the full HTML maintenance report.
.PARAMETER SessionResults
    Array of hashtables from New-ModuleResult.
.PARAMETER OSContext
    Hashtable from Get-OSContext.
.PARAMETER TranscriptPath
    Path to maintenance.log (parsed into the interactive console).
.PARAMETER ReportTitle
    Optional report title override.
.OUTPUTS
    [string] Full path of the created HTML file.
#>
function New-MaintenanceReport {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [array]$SessionResults,
        [Parameter(Mandatory)] [hashtable]$OSContext,
        [Parameter()] [string]$TranscriptPath = '',
        [Parameter()] [string]$ReportTitle = 'Windows Maintenance Report'
    )

    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $reportName = "MaintenanceReport_$timestamp.html"
    $reportsDir = Get-TempPath -Category 'reports'
    $reportPath = Join-Path $reportsDir $reportName

    $html = Build-ReportHtml -SessionResults $SessionResults `
        -OSContext      $OSContext `
        -TranscriptPath $TranscriptPath `
        -Title          $ReportTitle `
        -Timestamp      $timestamp

    $html | Set-Content -Path $reportPath -Encoding UTF8 -Force
    Write-Log -Level SUCCESS -Component REPORT -Message "Report saved: $reportPath"
    return $reportPath
}

#endregion

#region ─── HTML BUILDER ───────────────────────────────────────────────────────

<#
.SYNOPSIS
    Builds the full HTML string for the maintenance report.
#>
function Build-ReportHtml {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [array]     $SessionResults,
        [hashtable] $OSContext,
        [string]    $TranscriptPath,
        [string]    $Title,
        [string]    $Timestamp
    )

    # ── Run stats ────────────────────────────────────────────────────────────
    $totalModules = $SessionResults.Count
    $succeeded = @($SessionResults | Where-Object { $_.Status -eq 'Success' }).Count
    $warned = @($SessionResults | Where-Object { $_.Status -eq 'Warning' }).Count
    $failed = @($SessionResults | Where-Object { $_.Status -eq 'Failed' }).Count
    $skipped = @($SessionResults | Where-Object { $_.Status -eq 'Skipped' }).Count
    $totalItems = ($SessionResults | ForEach-Object { [int]$_.ItemsProcessed } | Measure-Object -Sum).Sum
    $reclaimed = ($SessionResults | ForEach-Object { [double]($_.ExtraData.ReclaimedMB ?? 0) } | Measure-Object -Sum).Sum
    $reclaimed = [math]::Round($reclaimed, 1)

    $overallStatus = if ($failed -gt 0) { 'danger' } elseif ($warned -gt 0 -or $skipped -gt 0) { 'warning' } else { 'success' }
    $overallLabel = if ($failed -gt 0) { 'Completed with errors' }
    elseif ($warned -gt 0) { 'Completed with warnings' }
    elseif ($skipped -gt 0) { 'Completed with skips' }
    else { 'All tasks completed successfully' }

    # ── Error aggregation ────────────────────────────────────────────────────
    $allErrors = [System.Collections.Generic.List[string]]::new()
    foreach ($r in $SessionResults) {
        if ($r.Errors -and @($r.Errors).Count -gt 0) {
            foreach ($e in $r.Errors) { $allErrors.Add("[$($r.ModuleName)] $e") }
        }
    }
    $errorSummaryHtml = ''
    if ($allErrors.Count -gt 0) {
        $errItems = ($allErrors | ForEach-Object { "<div class='err-mod'>$(ConvertTo-HtmlText $_)</div>" }) -join "`n"
        $errorSummaryHtml = @"
<section class="card err-summary">
  <div class="card-hd"><span class="card-ttl">&#9888; $($allErrors.Count) error(s) across all modules</span></div>
  <div class="card-bd">$errItems</div>
</section>
"@
    }

    # ── Module cards, grouped ────────────────────────────────────────────────
    $type1Results = @($SessionResults | Where-Object { $_.ModuleType -eq 'Type1' })
    $type2Results = @($SessionResults | Where-Object { $_.ModuleType -eq 'Type2' })
    $type1Cards = ($type1Results | ForEach-Object { Build-ModuleCard -Result $_ }) -join "`n"
    $type2Cards = ($type2Results | ForEach-Object { Build-ModuleCard -Result $_ }) -join "`n"
    if (-not $type1Cards) { $type1Cards = "<p class='muted'>No audit modules ran.</p>" }
    if (-not $type2Cards) { $type2Cards = "<p class='muted'>No maintenance actions were required.</p>" }

    # ── Inventory-driven sections (read the JSON once, share it) ──────────────
    $inv = Get-InventoryData

    $overviewHtml = Build-SystemOverview -Inv $inv -OSContext $OSContext `
        -PSVer $PSVersionTable.PSVersion.ToString() `
        -RunAs ([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)

    $systemInventoryHtml = ''
    if ($SessionResults | Where-Object { $_.ModuleName -eq 'SystemInventory' }) {
        $systemInventoryHtml = Build-SystemInventorySection -Inv $inv
    }

    $restorePointHtml = ''
    if ($SessionResults | Where-Object { $_.ModuleName -eq 'RestorePointAudit' }) {
        $restorePointHtml = Build-RestorePointSection
    }

    $systemHealthHtml = ''
    $healthResult = $SessionResults | Where-Object { $_.ModuleName -eq 'SystemHealthAudit' }
    if ($healthResult) { $systemHealthHtml = Build-SystemHealthSection -Result $healthResult }

    # ── Reboot banner ────────────────────────────────────────────────────────
    $rebootNeeded = [bool]($SessionResults | Where-Object { $_.RebootRequired -eq $true })
    $rebootBanner = if ($rebootNeeded) {
        '<div class="banner danger">&#9888; One or more modules require a system reboot to finish.</div>'
    }
    else { '' }

    # ── Parsed log console ───────────────────────────────────────────────────
    $logEntries = ConvertFrom-MaintenanceLog -Path $TranscriptPath
    $logConsoleHtml = Build-LogConsole -Entries $logEntries

    # ── Header facts ─────────────────────────────────────────────────────────
    $genTime = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $hostname = ConvertTo-HtmlText $env:COMPUTERNAME
    $osText = ConvertTo-HtmlText $OSContext.DisplayText

    return @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1.0">
<title>$Title</title>
<style>
$(Get-ReportCss)
</style>
</head>
<body data-theme="dark">
<div class="wrap">

  <header class="hero">
    <div class="hero-l">
      <div class="hero-eyebrow">Windows Maintenance Automation</div>
      <h1 class="hero-title">$Title</h1>
      <div class="hero-meta">
        <span>&#128421; $hostname</span>
        <span class="sep">&bull;</span>
        <span>&#129695; $osText</span>
        <span class="sep">&bull;</span>
        <span>&#128336; $genTime</span>
        <span class="sep">&bull;</span>
        <span>Session $Timestamp</span>
      </div>
    </div>
    <div class="hero-r">
      <div class="status-pill $overallStatus">$overallLabel</div>
      <button id="themeToggle" class="theme-btn" type="button">&#9788; Light</button>
    </div>
  </header>

  $rebootBanner
  $overviewHtml

  <section class="stats">
    <div class="stat"><div class="stat-v">$totalModules</div><div class="stat-l">Modules run</div></div>
    <div class="stat s"><div class="stat-v">$succeeded</div><div class="stat-l">Succeeded</div></div>
    <div class="stat w"><div class="stat-v">$warned</div><div class="stat-l">Warnings</div></div>
    <div class="stat m"><div class="stat-v">$skipped</div><div class="stat-l">Skipped</div></div>
    <div class="stat d"><div class="stat-v">$failed</div><div class="stat-l">Failed</div></div>
    <div class="stat i"><div class="stat-v">$totalItems</div><div class="stat-l">Items changed</div></div>
    <div class="stat a"><div class="stat-v">$reclaimed<span class="unit">MB</span></div><div class="stat-l">Disk reclaimed</div></div>
  </section>

  $errorSummaryHtml

  <h2 class="sec">&#128269; Stage 1 &mdash; System Audit</h2>
  <div class="mod-grid">$type1Cards</div>

  $systemInventoryHtml
  $restorePointHtml
  $systemHealthHtml

  <h2 class="sec">&#128295; Stage 3 &mdash; Maintenance Actions</h2>
  <div class="mod-grid">$type2Cards</div>

  $logConsoleHtml

  <footer class="footer">
    Windows Maintenance Automation v6 &bull; report generated $genTime &bull; $hostname
  </footer>
</div>

<script>
$(Get-ReportJs)
</script>
</body>
</html>
"@
}

#endregion

#region ─── MODULE CARD ────────────────────────────────────────────────────────

<#
.SYNOPSIS
    Builds an HTML card for a single module result.
#>
function Build-ModuleCard {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [hashtable]$Result)

    $badgeClass = switch ($Result.Status) {
        'Success' { 'bs' }
        'Skipped' { 'bm' }
        'Failed' { 'bd' }
        'Warning' { 'bw' }
        default { 'bm' }
    }
    $typeLabel = if ($Result.ModuleType) { "<span class='mod-type'>$($Result.ModuleType)</span>" } else { '' }
    $rebootTag = if ($Result.RebootRequired) { "<span class='reboot-tag'>Reboot</span>" } else { '' }

    $errHtml = ''
    if ($Result.Errors -and @($Result.Errors).Count -gt 0) {
        $items = ($Result.Errors | ForEach-Object { "<li>$(ConvertTo-HtmlText $_)</li>" }) -join ''
        $errHtml = "<ul class='errs'>$items</ul>"
    }

    $msg = ConvertTo-HtmlText $Result.Message
    $msgRow = if ($msg) { "<div class='r'><span class='k'>Note</span><span class='v'>$msg</span></div>" } else { '' }

    $extraHtml = ''
    if ($Result.ExtraData -and $Result.ExtraData.Count -gt 0) {
        $exRows = ($Result.ExtraData.GetEnumerator() | Where-Object { $_.Value -isnot [hashtable] } | ForEach-Object {
                "<div class='ex-row'><span class='k'>$(ConvertTo-HtmlText $_.Key)</span><span class='v'>$(ConvertTo-HtmlText $_.Value)</span></div>"
            }) -join ''
        if ($exRows) { $extraHtml = "<div class='extra'>$exRows</div>" }
    }

    # Detail items from the diff (Type2 ModuleName == DiffKey; Type1 strips 'Audit').
    $detailHtml = ''
    try {
        $moduleName = $Result.ModuleName
        $diffData = Get-DiffList -ModuleName $moduleName
        if (-not $diffData -or $diffData.Count -eq 0) {
            $pairKey = $moduleName -replace 'Audit$', ''
            if ($pairKey -ne $moduleName) { $diffData = Get-DiffList -ModuleName $pairKey }
        }
        if ($diffData -and $diffData.Count -gt 0) {
            $maxItems = [Math]::Min($diffData.Count, 25)
            $itemRows = ($diffData[0..($maxItems - 1)] | ForEach-Object {
                    $itemName = ConvertTo-HtmlText ($_.Name ?? $_.name ?? 'Item')
                    $curSt = ConvertTo-HtmlText ($_.CurrentState ?? '')
                    $desSt = ConvertTo-HtmlText ($_.DesiredState ?? '')
                    $desc = ConvertTo-HtmlText ($_.Description ?? '')
                    $itemType = ConvertTo-HtmlText ($_.Type ?? $_.type ?? '')
                    $detailText = if ($desc) { $desc } elseif ($curSt -and $desSt) { "$curSt &#8594; $desSt" } else { $itemType }
                    "<div class='item'><span class='item-name'>$itemName</span><span class='item-detail'>$detailText</span></div>"
                }) -join ''
            $moreText = if ($diffData.Count -gt 25) { " <span class='more'>(+$($diffData.Count - 25) more)</span>" } else { '' }
            $detailHtml = @"
<details class="mod-details">
  <summary>$($diffData.Count) item(s) detailed$moreText</summary>
  <div class="item-list">$itemRows</div>
</details>
"@
        }
    }
    catch { $detailHtml = '' }

    return @"
<div class="mod">
  <div class="mod-hd">
    <span class="nm">$(ConvertTo-HtmlText $Result.ModuleName)$typeLabel$rebootTag</span>
    <span class="badge $badgeClass">$($Result.Status)</span>
  </div>
  <div class="mod-bd">
    <div class="metrics">
      <div class="metric"><span class="mv">$($Result.ItemsDetected)</span><span class="ml">Detected</span></div>
      <div class="metric"><span class="mv">$($Result.ItemsProcessed)</span><span class="ml">Processed</span></div>
      <div class="metric"><span class="mv">$($Result.ItemsSkipped)</span><span class="ml">Skipped</span></div>
      <div class="metric"><span class="mv">$($Result.ItemsFailed)</span><span class="ml">Failed</span></div>
    </div>
    $msgRow
    $extraHtml
    $errHtml
    $detailHtml
  </div>
</div>
"@
}

#endregion

#region ─── INVENTORY / RESTORE / HEALTH SECTIONS ──────────────────────────────

<#
.SYNOPSIS
    Local users + restore-point list (network + hardware now live in the top overview).
#>
function Build-SystemInventorySection {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter()] [AllowNull()] $Inv)

    if (-not $Inv) { $Inv = Get-InventoryData }
    if (-not $Inv) { return '' }

    $usersHtml = ''
    if ($Inv.LocalUsers -and @($Inv.LocalUsers).Count -gt 0) {
        $userRows = ($Inv.LocalUsers | ForEach-Object {
                $name = ConvertTo-HtmlText $_.Name
                $fullName = if ($_.FullName) { ConvertTo-HtmlText $_.FullName } else { '<span class="muted">(no display name)</span>' }
                $lastLogon = ConvertTo-HtmlText $_.LastLogon
                "<div class='trow'><span class='user-name'>&#128100; $name</span><span>$fullName</span><span class='muted'>$lastLogon</span></div>"
            }) -join ''
        $usersHtml = @"
<div class="card half">
  <div class="card-hd"><span class="card-ttl">&#128101; Local Users</span><span class="card-sub">$(@($Inv.LocalUsers).Count)</span></div>
  <div class="thead u3"><span>User</span><span>Full name</span><span>Last logon</span></div>
  <div class="tbody u3">$userRows</div>
</div>
"@
    }

    $rpHtml = ''
    if ($Inv.RestorePoints -and @($Inv.RestorePoints).Count -gt 0) {
        $max = [Math]::Min(15, @($Inv.RestorePoints).Count)
        $rpRows = ($Inv.RestorePoints[0..($max - 1)] | ForEach-Object {
                $desc = ConvertTo-HtmlText $_.Description
                $created = ConvertTo-HtmlText $_.CreationTime
                $type = ConvertTo-HtmlText $_.RestorePointType
                "<div class='trow'><span>$desc</span><span class='tag'>$type</span><span class='muted'>$created</span></div>"
            }) -join ''
        $more = if (@($Inv.RestorePoints).Count -gt 15) { "<div class='tmore'>+$(@($Inv.RestorePoints).Count - 15) more</div>" } else { '' }
        $rpHtml = @"
<div class="card half">
  <div class="card-hd"><span class="card-ttl">&#128257; Restore Points</span><span class="card-sub">$(@($Inv.RestorePoints).Count)</span></div>
  <div class="thead u3"><span>Description</span><span>Type</span><span>Created</span></div>
  <div class="tbody u3">$rpRows</div>
  $more
</div>
"@
    }

    if (-not $usersHtml -and -not $rpHtml) { return '' }
    return @"
<h2 class="sec">&#128193; System Details</h2>
<div class="half-grid">
  $usersHtml
  $rpHtml
</div>
"@
}

<#
.SYNOPSIS
    Restore-point audit detail (from restore-point-audit.json).
#>
function Build-RestorePointSection {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $dataPath = Get-TempPath -Category 'data' -FileName 'restore-point-audit.json' -ErrorAction SilentlyContinue
    if (-not $dataPath -or -not (Test-Path $dataPath)) { return '' }
    try { $rpData = Get-Content -Path $dataPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { return '' }
    if (-not $rpData.RestorePointsList -or @($rpData.RestorePointsList).Count -eq 0) { return '' }

    $max = [Math]::Min(20, @($rpData.RestorePointsList).Count)
    $rpRows = ($rpData.RestorePointsList[0..($max - 1)] | ForEach-Object {
            $desc = ConvertTo-HtmlText $_.Description
            $created = ConvertTo-HtmlText $_.CreationTime
            $type = ConvertTo-HtmlText $_.RestorePointType
            $seq = ConvertTo-HtmlText $_.SequenceNumber
            "<div class='trow u4'><span class='mono muted'>#$seq</span><span>$desc</span><span class='tag'>$type</span><span class='muted'>$created</span></div>"
        }) -join ''
    $more = if (@($rpData.RestorePointsList).Count -gt 20) { "<div class='tmore'>+$(@($rpData.RestorePointsList).Count - 20) more</div>" } else { '' }

    return @"
<h2 class="sec">&#128257; Restore Point Audit</h2>
<div class="mini-stats">
  <div class="mini"><div class="mini-v">$($rpData.CurrentCount)</div><div class="mini-l">Current</div></div>
  <div class="mini"><div class="mini-v">$($rpData.ToRemove)</div><div class="mini-l">To remove</div></div>
  <div class="mini"><div class="mini-v">$($rpData.MinimumToKeep)</div><div class="mini-l">Keep min</div></div>
  <div class="mini"><div class="mini-v">$($rpData.AllocationGB)<span class="unit">GB</span></div><div class="mini-l">Allocation</div></div>
</div>
<div class="card">
  <div class="thead u4"><span>Seq</span><span>Description</span><span>Type</span><span>Created</span></div>
  <div class="tbody u4">$rpRows</div>
  $more
</div>
"@
}

<#
.SYNOPSIS
    System health: event log, Defender incidents, Defender exclusions.
#>
function Build-SystemHealthSection {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [hashtable]$Result)

    if (-not $Result.ExtraData) { return '' }
    $dataPath = Get-TempPath -Category 'data' -FileName 'system-health-report.json' -ErrorAction SilentlyContinue
    if (-not $dataPath -or -not (Test-Path $dataPath)) { return '' }
    try { $healthData = Get-Content -Path $dataPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { return '' }

    $eventHtml = ''
    if ($healthData.EventViewerEvents -and @($healthData.EventViewerEvents).Count -gt 0) {
        $max = [Math]::Min(20, @($healthData.EventViewerEvents).Count)
        $rows = ($healthData.EventViewerEvents[0..($max - 1)] | ForEach-Object {
                $level = ConvertTo-HtmlText $_.Level
                $src = ConvertTo-HtmlText $_.Source
                $msg = ConvertTo-HtmlText ("$($_.Message)")
                if ($msg.Length -gt 140) { $msg = $msg.Substring(0, 140) + '&hellip;' }
                $ts = ConvertTo-HtmlText $_.Timestamp
                $lc = $level.ToLower()
                "<div class='trow u4'><span class='evt-level evt-$lc'>$level</span><span>$src</span><span class='muted'>$msg</span><span class='muted'>$ts</span></div>"
            }) -join ''
        $more = if (@($healthData.EventViewerEvents).Count -gt 20) { "<div class='tmore'>+$(@($healthData.EventViewerEvents).Count - 20) more</div>" } else { '' }
        $eventHtml = @"
<div class="card">
  <div class="card-hd"><span class="card-ttl">&#128220; Critical &amp; Error Events (30 days)</span><span class="card-sub">$(@($healthData.EventViewerEvents).Count)</span></div>
  <div class="thead u4"><span>Level</span><span>Source</span><span>Message</span><span>Time</span></div>
  <div class="tbody u4">$rows</div>
  $more
</div>
"@
    }

    $defHtml = ''
    if ($healthData.DefenderIncidents -and @($healthData.DefenderIncidents).Count -gt 0) {
        $max = [Math]::Min(20, @($healthData.DefenderIncidents).Count)
        $rows = ($healthData.DefenderIncidents[0..($max - 1)] | ForEach-Object {
                $threat = ConvertTo-HtmlText $_.ThreatName
                $sev = ConvertTo-HtmlText $_.Severity
                $path = ConvertTo-HtmlText $_.DetectionPath
                $ts = ConvertTo-HtmlText $_.Timestamp
                $sc = if ($sev -eq 'High') { 'sev-high' } elseif ($sev -eq 'Medium') { 'sev-med' } else { 'sev-low' }
                "<div class='trow u4'><span>$threat</span><span class='sev $sc'>$sev</span><span class='muted'>$path</span><span class='muted'>$ts</span></div>"
            }) -join ''
        $defHtml = @"
<div class="card">
  <div class="card-hd"><span class="card-ttl">&#128737; Defender Incidents (30 days)</span><span class="card-sub">$(@($healthData.DefenderIncidents).Count)</span></div>
  <div class="thead u4"><span>Threat</span><span>Severity</span><span>Path</span><span>Time</span></div>
  <div class="tbody u4">$rows</div>
</div>
"@
    }

    $exHtml = ''
    if ($healthData.DefenderExclusions) {
        $ex = $healthData.DefenderExclusions
        $mk = {
            param($items, $glyph)
            if (-not $items -or @($items).Count -eq 0) { return '<div class="excl-item muted">none</div>' }
            $m = [Math]::Min(12, @($items).Count)
            $rows = ($items[0..($m - 1)] | ForEach-Object { "<div class='excl-item'>$glyph $(ConvertTo-HtmlText $_)</div>" }) -join ''
            $more = if (@($items).Count -gt 12) { "<div class='excl-more'>+$(@($items).Count - 12) more</div>" } else { '' }
            return "$rows$more"
        }
        $exHtml = @"
<div class="excl-grid">
  <div class="card"><div class="card-hd"><span class="card-ttl">&#128193; Folder exclusions</span><span class="card-sub">$(@($ex.FolderExclusions).Count)</span></div><div class="card-bd">$(& $mk $ex.FolderExclusions '&#128193;')</div></div>
  <div class="card"><div class="card-hd"><span class="card-ttl">&#128196; Extension exclusions</span><span class="card-sub">$(@($ex.ExtensionExclusions).Count)</span></div><div class="card-bd">$(& $mk $ex.ExtensionExclusions '&#128196;')</div></div>
  <div class="card"><div class="card-hd"><span class="card-ttl">&#9881; Process exclusions</span><span class="card-sub">$(@($ex.ProcessExclusions).Count)</span></div><div class="card-bd">$(& $mk $ex.ProcessExclusions '&#9881;')</div></div>
</div>
"@
    }

    if (-not $eventHtml -and -not $defHtml -and -not $exHtml) { return '' }
    return @"
<h2 class="sec">&#127973; System Health</h2>
$eventHtml
$defHtml
$exHtml
"@
}

#endregion

#region ─── CSS / JS ───────────────────────────────────────────────────────────

function Get-ReportCss {
    return @'
*,*::before,*::after{box-sizing:border-box;margin:0;padding:0}
:root{
  --bg:#0b0e14;--bg2:#12151f;--card:#161a26;--card2:#1c2130;--border:#262c3d;
  --text:#e6e9f2;--muted:#8b93a7;--faint:#5a6273;
  --accent:#7c5cff;--accent2:#22d3ee;
  --success:#34d399;--warn:#fbbf24;--danger:#f87171;--info:#60a5fa;--debug:#7a8291;--fatal:#fb7185;
  --shadow:0 10px 30px rgba(0,0,0,.35);--radius:16px;
}
body[data-theme="light"]{
  --bg:#eef1f7;--bg2:#ffffff;--card:#ffffff;--card2:#f3f6fb;--border:#e1e7f0;
  --text:#141a26;--muted:#5b6472;--faint:#98a2b3;
  --accent:#6d28d9;--accent2:#0891b2;
  --success:#059669;--warn:#d97706;--danger:#dc2626;--info:#2563eb;--debug:#6b7280;--fatal:#e11d48;
  --shadow:0 8px 24px rgba(30,40,80,.10);
}
body{background:var(--bg);color:var(--text);font-family:'Segoe UI',system-ui,-apple-system,sans-serif;font-size:14px;line-height:1.55;transition:background .25s,color .25s}
.wrap{width:100%;max-width:100%;padding:clamp(16px,2.6vw,40px);margin:0 auto}
.mono{font-family:'Cascadia Code',Consolas,ui-monospace,monospace}
.muted{color:var(--muted)}
.unit{font-size:.5em;color:var(--muted);font-weight:600;margin-left:2px}

/* HERO */
.hero{display:flex;justify-content:space-between;align-items:flex-start;gap:24px;flex-wrap:wrap;
  background:radial-gradient(1200px 300px at 0% 0%,rgba(124,92,255,.18),transparent 60%),
             radial-gradient(1000px 300px at 100% 0%,rgba(34,211,238,.14),transparent 55%),var(--bg2);
  border:1px solid var(--border);border-radius:var(--radius);padding:28px 30px;margin-bottom:22px;box-shadow:var(--shadow)}
.hero-eyebrow{color:var(--accent2);font-size:12px;font-weight:700;letter-spacing:1.4px;text-transform:uppercase}
.hero-title{font-size:clamp(22px,2.4vw,32px);font-weight:800;margin-top:4px;letter-spacing:-.4px}
.hero-meta{display:flex;gap:10px;flex-wrap:wrap;color:var(--muted);font-size:13px;margin-top:10px;align-items:center}
.hero-meta .sep{color:var(--faint)}
.hero-r{display:flex;flex-direction:column;align-items:flex-end;gap:12px}
.status-pill{padding:9px 18px;border-radius:999px;font-weight:700;font-size:13px;white-space:nowrap}
.status-pill.success{background:rgba(52,211,153,.14);color:var(--success);border:1px solid rgba(52,211,153,.35)}
.status-pill.warning{background:rgba(251,191,36,.14);color:var(--warn);border:1px solid rgba(251,191,36,.35)}
.status-pill.danger{background:rgba(248,113,113,.14);color:var(--danger);border:1px solid rgba(248,113,113,.35)}
.theme-btn{background:var(--card2);color:var(--text);border:1px solid var(--border);border-radius:999px;padding:7px 14px;font-size:12px;font-weight:600;cursor:pointer;transition:.15s}
.theme-btn:hover{border-color:var(--accent)}

/* BANNER */
.banner{border-radius:12px;padding:13px 18px;margin-bottom:20px;font-weight:600}
.banner.danger{background:rgba(248,113,113,.1);border:1px solid rgba(248,113,113,.4);color:var(--danger)}

/* OVERVIEW */
.overview{margin-bottom:22px}
.ov-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(240px,1fr));gap:14px}
.ov-card{background:var(--card);border:1px solid var(--border);border-radius:var(--radius);padding:18px 20px;position:relative;overflow:hidden}
.ov-card.wide{grid-column:1/-1}
.ov-card.identity{background:linear-gradient(135deg,rgba(124,92,255,.16),rgba(34,211,238,.08)),var(--card);border-color:rgba(124,92,255,.35)}
.ov-card-ttl{font-size:11px;font-weight:700;letter-spacing:.8px;text-transform:uppercase;color:var(--muted);margin-bottom:10px}
.ov-host{font-size:26px;font-weight:800;letter-spacing:-.4px}
.ov-big{font-size:22px;font-weight:700;line-height:1.15}
.ov-big.small{font-size:15px;font-weight:600}
.ov-sub{color:var(--muted);font-size:13px;margin-top:4px}
.ov-pills{margin-top:12px}
.ov-mini{display:flex;gap:22px;margin-top:12px;flex-wrap:wrap}
.ov-mini>span{display:flex;flex-direction:column;font-size:13px;font-weight:600}
.ov-mini .mk{font-size:10px;text-transform:uppercase;letter-spacing:.6px;color:var(--faint);font-weight:700;margin-bottom:1px}
.pill{display:inline-block;padding:4px 12px;border-radius:999px;font-size:12px;font-weight:700}
.pill.ok{background:rgba(52,211,153,.15);color:var(--success);border:1px solid rgba(52,211,153,.35)}
.pill.warn{background:rgba(251,191,36,.15);color:var(--warn);border:1px solid rgba(251,191,36,.35)}

/* disks */
.disks{display:grid;grid-template-columns:repeat(auto-fit,minmax(300px,1fr));gap:16px}
.disk-hd{display:flex;justify-content:space-between;align-items:center;margin-bottom:6px;font-size:13px}
.disk-drive{font-weight:700}
.disk-pct{font-weight:800}
.disk-pct.ok{color:var(--success)}.disk-pct.warn{color:var(--warn)}.disk-pct.crit{color:var(--danger)}
.meter{height:9px;border-radius:999px;background:var(--card2);overflow:hidden;border:1px solid var(--border)}
.meter-fill{display:block;height:100%;border-radius:999px}
.meter-fill.ok{background:linear-gradient(90deg,var(--success),#10b981)}
.meter-fill.warn{background:linear-gradient(90deg,var(--warn),#f59e0b)}
.meter-fill.crit{background:linear-gradient(90deg,var(--danger),#ef4444)}
.disk-ft{display:flex;justify-content:space-between;color:var(--muted);font-size:11px;margin-top:5px}

/* nics */
.nics{display:grid;grid-template-columns:repeat(auto-fit,minmax(280px,1fr));gap:14px}
.nic{background:var(--card2);border:1px solid var(--border);border-radius:12px;padding:12px 14px}
.nic-desc{font-weight:700;font-size:13px;margin-bottom:8px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.nic-kv{display:flex;justify-content:space-between;gap:10px;font-size:12px;padding:3px 0;border-bottom:1px solid rgba(255,255,255,.03)}
.nic-kv:last-child{border-bottom:none}
.nic-kv>span:first-child{color:var(--faint);text-transform:uppercase;font-size:10px;letter-spacing:.5px;font-weight:700;padding-top:2px}
.nic-kv>span:last-child{text-align:right;word-break:break-all}

/* facts strip */
.facts{display:flex;flex-wrap:wrap;gap:10px;margin-top:14px}
.fact{display:flex;flex-direction:column;background:var(--card);border:1px solid var(--border);border-radius:10px;padding:8px 14px}
.fact .fk{font-size:10px;text-transform:uppercase;letter-spacing:.5px;color:var(--faint);font-weight:700}
.fact .fv{font-weight:700;font-size:13px;margin-top:1px}

/* STATS */
.stats{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:14px;margin-bottom:22px}
.stat{background:var(--card);border:1px solid var(--border);border-radius:14px;padding:18px;text-align:center;position:relative;overflow:hidden}
.stat::before{content:'';position:absolute;inset:0 0 auto 0;height:3px;background:var(--faint);opacity:.6}
.stat.s::before{background:var(--success)}.stat.w::before{background:var(--warn)}.stat.m::before{background:var(--debug)}
.stat.d::before{background:var(--danger)}.stat.i::before{background:var(--info)}.stat.a::before{background:var(--accent2)}
.stat-v{font-size:32px;font-weight:800;line-height:1}
.stat.s .stat-v{color:var(--success)}.stat.w .stat-v{color:var(--warn)}.stat.d .stat-v{color:var(--danger)}
.stat.i .stat-v{color:var(--info)}.stat.a .stat-v{color:var(--accent2)}.stat.m .stat-v{color:var(--muted)}
.stat-l{color:var(--muted);font-size:11px;margin-top:6px;text-transform:uppercase;letter-spacing:.5px;font-weight:600}

/* SECTION TITLE */
.sec{font-size:17px;font-weight:800;margin:28px 0 14px;letter-spacing:-.2px;display:flex;align-items:center;gap:8px}

/* CARDS */
.card{background:var(--card);border:1px solid var(--border);border-radius:var(--radius);overflow:hidden;margin-bottom:16px}
.card-hd{display:flex;justify-content:space-between;align-items:center;padding:14px 18px;border-bottom:1px solid var(--border)}
.card-ttl{font-weight:700;font-size:14px}
.card-sub{color:var(--muted);font-size:12px;font-weight:600}
.card-bd{padding:14px 18px}
.half-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(340px,1fr));gap:16px}

/* MODULE CARDS */
.mod-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(340px,1fr));gap:16px;margin-bottom:6px}
.mod{background:var(--card);border:1px solid var(--border);border-radius:var(--radius);overflow:hidden;transition:transform .12s,border-color .12s}
.mod:hover{border-color:var(--accent);transform:translateY(-2px)}
.mod-hd{padding:14px 18px;display:flex;align-items:center;justify-content:space-between;border-bottom:1px solid var(--border);gap:8px}
.mod-hd .nm{font-weight:700;font-size:14px;display:flex;align-items:center;gap:7px;flex-wrap:wrap}
.mod-type{font-size:9px;color:var(--muted);text-transform:uppercase;letter-spacing:.6px;font-weight:700;background:var(--card2);padding:2px 6px;border-radius:5px}
.reboot-tag{font-size:9px;font-weight:700;background:rgba(248,113,113,.15);color:var(--danger);border:1px solid rgba(248,113,113,.35);padding:2px 7px;border-radius:6px;text-transform:uppercase}
.mod-bd{padding:14px 18px}
.metrics{display:grid;grid-template-columns:repeat(4,1fr);gap:8px;margin-bottom:8px}
.metric{background:var(--card2);border-radius:10px;padding:9px 4px;text-align:center}
.metric .mv{display:block;font-size:18px;font-weight:800}
.metric .ml{display:block;font-size:9px;color:var(--muted);text-transform:uppercase;letter-spacing:.4px;margin-top:2px;font-weight:600}
.mod-bd .r{display:flex;justify-content:space-between;gap:10px;padding:6px 0;border-top:1px solid var(--border);font-size:12px}
.mod-bd .r .k{color:var(--muted)}
.mod-bd .r .v{text-align:right}
.badge{padding:4px 11px;border-radius:999px;font-size:11px;font-weight:700;white-space:nowrap}
.bs{background:rgba(52,211,153,.15);color:var(--success);border:1px solid rgba(52,211,153,.3)}
.bw{background:rgba(251,191,36,.15);color:var(--warn);border:1px solid rgba(251,191,36,.3)}
.bd{background:rgba(248,113,113,.15);color:var(--danger);border:1px solid rgba(248,113,113,.3)}
.bm{background:rgba(139,147,167,.15);color:var(--muted);border:1px solid rgba(139,147,167,.3)}
.errs{margin-top:8px;list-style:none}
.errs li{font-size:11px;color:var(--danger);padding:3px 0 3px 14px;position:relative}
.errs li::before{content:'\2715';position:absolute;left:0}
.extra{margin-top:8px}
.ex-row{display:flex;justify-content:space-between;gap:10px;padding:4px 0;font-size:11px;border-top:1px dashed var(--border)}
.ex-row .k{color:var(--muted)}.ex-row .v{color:var(--info);font-weight:600;text-align:right}
.mod-details{margin-top:10px}
.mod-details summary{font-size:12px;font-weight:600;padding:7px 11px;background:var(--card2);border:1px solid var(--border);border-radius:8px;cursor:pointer;list-style:none;display:flex;align-items:center;gap:6px}
.mod-details summary::-webkit-details-marker{display:none}
.mod-details summary::before{content:'\25B6';font-size:8px;transition:transform .2s;color:var(--accent)}
.mod-details[open] summary::before{transform:rotate(90deg)}
.mod-details .more{color:var(--muted);font-size:10px}
.item-list{margin-top:8px;display:flex;flex-direction:column;gap:4px;max-height:340px;overflow-y:auto}
.item{display:flex;justify-content:space-between;gap:12px;padding:6px 10px;border-left:2px solid var(--accent);background:var(--card2);border-radius:0 8px 8px 0;font-size:11px}
.item-name{font-weight:600}
.item-detail{color:var(--muted);text-align:right;word-break:break-word}

/* ERROR SUMMARY */
.err-summary .card-bd{display:flex;flex-direction:column;gap:6px}
.err-mod{font-size:12px;color:var(--muted);font-family:'Cascadia Code',Consolas,monospace;padding:5px 10px;background:var(--card2);border-radius:8px;border-left:2px solid var(--danger)}

/* TABLES (rows) */
.thead,.trow{display:grid;gap:12px;padding:9px 16px;align-items:center}
.thead{background:var(--card2);font-size:10px;text-transform:uppercase;letter-spacing:.5px;color:var(--muted);font-weight:700;border-bottom:1px solid var(--border)}
.trow{border-bottom:1px solid rgba(255,255,255,.03);font-size:12px}
.trow:last-child{border-bottom:none}
.u3,.thead.u3{grid-template-columns:1.2fr 1.6fr 1fr}
.u4,.thead.u4{grid-template-columns:.5fr 1.6fr .7fr 1fr}
.tbody{max-height:380px;overflow-y:auto}
.tmore{padding:8px 16px;text-align:center;color:var(--muted);font-size:11px;background:var(--card2)}
.user-name{font-weight:700}
.tag{background:rgba(96,165,250,.14);color:var(--info);padding:2px 8px;border-radius:6px;font-size:10px;text-align:center;font-weight:600}
.evt-level{font-weight:700;padding:2px 8px;border-radius:6px;text-align:center;font-size:10px}
.evt-error{background:rgba(248,113,113,.15);color:var(--danger)}
.evt-critical{background:rgba(248,113,113,.28);color:#ff8f8f}
.sev{font-weight:700;padding:2px 8px;border-radius:6px;text-align:center;font-size:10px}
.sev-high{background:rgba(248,113,113,.15);color:var(--danger)}
.sev-med{background:rgba(251,191,36,.15);color:var(--warn)}
.sev-low{background:rgba(52,211,153,.15);color:var(--success)}

/* EXCLUSIONS */
.excl-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(280px,1fr));gap:16px}
.excl-item{padding:5px 8px;font-size:11px;color:var(--muted);border-left:2px solid var(--accent);background:var(--card2);border-radius:0 6px 6px 0;margin-bottom:4px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.excl-more{font-size:10px;color:var(--info);text-align:center;padding:4px}

/* MINI STATS */
.mini-stats{display:grid;grid-template-columns:repeat(auto-fit,minmax(120px,1fr));gap:12px;margin-bottom:14px}
.mini{background:var(--card);border:1px solid var(--border);border-radius:12px;padding:14px;text-align:center}
.mini-v{font-size:24px;font-weight:800;color:var(--accent)}
.mini-l{font-size:10px;color:var(--muted);text-transform:uppercase;letter-spacing:.5px;margin-top:4px;font-weight:600}

/* LOG CONSOLE */
.logs .log-dist{display:flex;height:6px;margin:0}
.log-dist .seg{height:100%}
.lvl-bg-FATAL{background:var(--fatal)}.lvl-bg-ERROR{background:var(--danger)}.lvl-bg-WARN{background:var(--warn)}
.lvl-bg-SUCCESS{background:var(--success)}.lvl-bg-INFO{background:var(--info)}.lvl-bg-DEBUG{background:var(--debug)}.lvl-bg-RAW{background:var(--faint)}
.log-toolbar{display:flex;justify-content:space-between;gap:14px;flex-wrap:wrap;padding:14px 18px;border-bottom:1px solid var(--border);align-items:center}
.lvl-chips{display:flex;gap:7px;flex-wrap:wrap}
.lvl-chip{display:inline-flex;align-items:center;gap:6px;background:var(--card2);border:1px solid var(--border);color:var(--muted);border-radius:999px;padding:5px 11px;font-size:11px;font-weight:700;cursor:pointer;opacity:.5;transition:.15s}
.lvl-chip.active{opacity:1}
.lvl-chip .dot{width:8px;height:8px;border-radius:50%;background:currentColor}
.lvl-chip .cnt{background:rgba(0,0,0,.25);border-radius:999px;padding:0 6px;font-size:10px}
body[data-theme="light"] .lvl-chip .cnt{background:rgba(0,0,0,.08)}
.lvl-chip.lvl-FATAL{color:var(--fatal)}.lvl-chip.lvl-ERROR{color:var(--danger)}.lvl-chip.lvl-WARN{color:var(--warn)}
.lvl-chip.lvl-SUCCESS{color:var(--success)}.lvl-chip.lvl-INFO{color:var(--info)}.lvl-chip.lvl-DEBUG{color:var(--debug)}.lvl-chip.lvl-RAW{color:var(--faint)}
.lvl-chip.active.lvl-FATAL{background:rgba(251,113,133,.14);border-color:rgba(251,113,133,.4)}
.lvl-chip.active.lvl-ERROR{background:rgba(248,113,113,.14);border-color:rgba(248,113,113,.4)}
.lvl-chip.active.lvl-WARN{background:rgba(251,191,36,.14);border-color:rgba(251,191,36,.4)}
.lvl-chip.active.lvl-SUCCESS{background:rgba(52,211,153,.14);border-color:rgba(52,211,153,.4)}
.lvl-chip.active.lvl-INFO{background:rgba(96,165,250,.14);border-color:rgba(96,165,250,.4)}
.lvl-chip.active.lvl-DEBUG{background:rgba(122,130,145,.14);border-color:rgba(122,130,145,.4)}
.log-controls{display:flex;gap:8px;flex-wrap:wrap}
.log-select,.log-search{background:var(--card2);border:1px solid var(--border);color:var(--text);border-radius:9px;padding:7px 11px;font-size:12px;font-family:inherit}
.log-search{min-width:220px}
.log-select:focus,.log-search:focus{outline:none;border-color:var(--accent)}
.log-body{max-height:560px;overflow:auto;padding:6px 0;font-family:'Cascadia Code',Consolas,ui-monospace,monospace}
.log-row{display:grid;grid-template-columns:74px 66px 118px 1fr;gap:12px;padding:2px 18px;font-size:11.5px;align-items:baseline}
.log-row:hover{background:var(--card2)}
.lr-ts{color:var(--faint)}
.lr-lvl{font-weight:700;font-size:10px;text-align:center;border-radius:5px;padding:1px 0}
.lr-cmp{color:var(--accent2);font-weight:600;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.lr-msg{color:var(--text);word-break:break-word;white-space:pre-wrap}
.lvl-FATAL{background:rgba(251,113,133,.18);color:var(--fatal)}
.lvl-ERROR{background:rgba(248,113,113,.16);color:var(--danger)}
.lvl-WARN{background:rgba(251,191,36,.16);color:var(--warn)}
.lvl-SUCCESS{background:rgba(52,211,153,.16);color:var(--success)}
.lvl-INFO{background:rgba(96,165,250,.14);color:var(--info)}
.lvl-DEBUG{background:rgba(122,130,145,.14);color:var(--debug)}
.log-row.raw{grid-template-columns:1fr;padding:2px 18px}
.log-row.raw .lr-msg{color:var(--faint)}
.log-row.raw.sep .lr-msg{color:var(--accent);opacity:.5}

/* FOOTER */
.footer{text-align:center;color:var(--muted);font-size:12px;padding:24px 0 8px;border-top:1px solid var(--border);margin-top:26px}

::-webkit-scrollbar{width:10px;height:10px}
::-webkit-scrollbar-thumb{background:var(--border);border-radius:999px}
::-webkit-scrollbar-thumb:hover{background:var(--faint)}
'@
}

function Get-ReportJs {
    return @'
(function(){
  var rows = Array.prototype.slice.call(document.querySelectorAll('.log-row'));
  var chips = Array.prototype.slice.call(document.querySelectorAll('.lvl-chip'));
  var search = document.getElementById('logSearch');
  var comp = document.getElementById('logComp');
  var shownEl = document.getElementById('logShown');

  function activeLevels(){
    var s = {};
    chips.forEach(function(c){ if(c.classList.contains('active')){ s[c.getAttribute('data-level')] = true; } });
    return s;
  }
  function apply(){
    if(!rows.length) return;
    var lv = activeLevels();
    var q = (search && search.value ? search.value : '').toLowerCase();
    var cp = comp ? comp.value : 'ALL';
    var shown = 0, i, r, vis;
    for(i=0;i<rows.length;i++){
      r = rows[i];
      vis = !!lv[r.getAttribute('data-level')]
        && (cp === 'ALL' || r.getAttribute('data-comp') === cp)
        && (q === '' || (r.getAttribute('data-text') || '').indexOf(q) >= 0);
      r.style.display = vis ? '' : 'none';
      if(vis) shown++;
    }
    if(shownEl) shownEl.textContent = shown;
  }
  chips.forEach(function(c){ c.addEventListener('click', function(){ c.classList.toggle('active'); apply(); }); });
  if(search) search.addEventListener('input', apply);
  if(comp) comp.addEventListener('change', apply);
  apply();

  var tt = document.getElementById('themeToggle');
  function setToggleLabel(theme){ if(tt) tt.innerHTML = (theme === 'light') ? '☾ Dark' : '☀ Light'; }
  if(tt){
    tt.addEventListener('click', function(){
      var cur = (document.body.getAttribute('data-theme') === 'light') ? 'dark' : 'light';
      document.body.setAttribute('data-theme', cur);
      setToggleLabel(cur);
      try{ localStorage.setItem('wmreport-theme', cur); }catch(e){}
    });
    try{
      var saved = localStorage.getItem('wmreport-theme');
      if(saved){ document.body.setAttribute('data-theme', saved); setToggleLabel(saved); }
    }catch(e){}
  }
})();
'@
}

#endregion

#region ─── EXPORTS ────────────────────────────────────────────────────────────

Export-ModuleMember -Function @(
    'New-MaintenanceReport',
    'Build-ReportHtml',
    'Build-ModuleCard',
    'Build-SystemOverview',
    'Build-SystemInventorySection',
    'Build-RestorePointSection',
    'Build-SystemHealthSection',
    'ConvertFrom-MaintenanceLog',
    'Build-LogConsole',
    'ConvertTo-HtmlText'
)

#endregion
