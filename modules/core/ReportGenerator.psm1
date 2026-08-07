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
    Loads system-inventory.json (produced by SystemConfigurationAudit) if present.
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
    Each line of the form "[ts] [COMPONENT] [LEVEL] message" becomes an object with
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
    # `,` is REQUIRED on every return path - see the note at the end of this function.
    if (-not $Path -or -not (Test-Path $Path)) { return , $entries }

    $rx = [regex]'^\[(?<ts>[^\]]+)\]\s\[(?<cmp>[^\]]+)\]\s\[(?<lvl>[^\]]+)\]\s?(?<msg>.*)$'
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

    # `,` (array-wrap) is REQUIRED. PowerShell ENUMERATES a collection on return, and an EMPTY
    # List enumerates to nothing - so a log with no parseable entries handed the caller $null
    # instead of an empty list. Build-LogConsole declares
    # [Parameter(Mandatory)][AllowEmptyCollection()], which permits an empty collection but NOT
    # null, so binding failed and Stage 4 threw:
    #     Build-ReportHtml: Cannot bind argument to parameter 'Entries' because it is null.
    # That killed the HTML report - the ONE artifact that survives Stage 5 cleanup - for any
    # run whose log could not be read or parsed. Build-LogConsole already handles Count -eq 0
    # gracefully; the producer simply never delivered an empty collection for it to handle.
    #
    # Note this bug survived the unit tests: $null.Count is 0 in PowerShell, so every
    # `.Count | Should -Be 0` assertion passed against the broken behaviour. The tests now
    # assert the return is non-null and enumerable, not merely that it counts zero.
    #
    # NOT the same as the ConvertFrom-WingetListTable case, where the comma was WRONG: callers
    # there use @(...), which would see the wrapper. This function's caller binds it straight
    # to a typed parameter, so the collection must arrive whole.
    return , $entries
}

<#
.SYNOPSIS
    Builds the interactive, filterable log-console HTML section from parsed entries.
#>
function Build-LogConsole {
    [CmdletBinding()]
    [OutputType([string])]
    # AllowNull as well as AllowEmptyCollection, deliberately. AllowEmptyCollection permits an
    # empty list but still REJECTS null, and a Mandatory null is a hard binding error that
    # propagates out of Build-ReportHtml and kills Stage 4 - losing the HTML report, the one
    # artifact that survives Stage 5 cleanup. The producer is fixed to always return a real
    # collection; this is the second line of defence, because an unstyled or log-less report
    # beats no report at all. $null.Count is 0 in PowerShell, so the guard below covers it.
    param(
        [Parameter(Mandatory)] [AllowNull()] [AllowEmptyCollection()]
        [System.Collections.Generic.List[object]]$Entries
    )

    if ($null -eq $Entries -or $Entries.Count -eq 0) {
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
        # AllowEmptyCollection: a run that produced no module results must still yield a
        # report - it is the only artifact that survives cleanup. Without this, Mandatory
        # rejects the empty array outright ("Cannot bind argument ... empty collection")
        # and Stage 4 fails instead of rendering an empty run.
        [Parameter(Mandatory)] [AllowEmptyCollection()] [array]$SessionResults,
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

    # Inventory, restore points and health all come from SystemConfigurationAudit since the
    # v7.0 consolidation (they used to be the separate SystemInventory / RestorePointAudit /
    # SystemHealthAudit modules). Each Build-* helper reads its own JSON under temp_files/data
    # and returns '' when that file is absent, so a section that was skipped by config simply
    # does not render.
    $configAuditRan = [bool]($SessionResults | Where-Object { $_.ModuleName -eq 'SystemConfigurationAudit' })

    $systemInventoryHtml = ''
    $restorePointHtml = ''
    $systemHealthHtml = ''
    if ($configAuditRan) {
        $systemInventoryHtml = Build-SystemInventorySection -Inv $inv
        $restorePointHtml = Build-RestorePointSection
        $systemHealthHtml = Build-SystemHealthSection
    }

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
    param()

    # Presence of the JSON is the only gate: the health block is optional (config
    # skipSystemHealth) and is written by SystemConfigurationAudit when it runs.
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

# CSS and JS live in modules/core/assets/ as real .css/.js files rather than here-strings, so
# they get syntax highlighting, formatting and linting instead of being 280 lines of opaque
# string literal. They are READ AND INLINED at render time, not linked: the report is a single
# self-contained HTML file copied to $env:ORIGINAL_SCRIPT_DIR, and it has to survive there with
# no sibling files after Stage 5 deletes the extracted tree.
#
# A missing asset degrades to an unstyled (or non-interactive) report - never a failed run.

<#
.SYNOPSIS
    Reads an inline asset from modules/core/assets.
.OUTPUTS
    [string] file contents, or empty string when the asset is missing/unreadable.
#>
function Get-ReportAsset {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [string]$FileName)

    $path = Join-Path $PSScriptRoot "assets\$FileName"
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Write-Log -Level WARN -Component REPORT -Message "Report asset missing: $FileName (report will render without it)"
        return ''
    }
    try {
        return (Get-Content -LiteralPath $path -Raw -Encoding UTF8)
    }
    catch {
        Write-Log -Level WARN -Component REPORT -Message "Could not read report asset ${FileName}: $_"
        return ''
    }
}

function Get-ReportCss { return Get-ReportAsset -FileName 'report.css' }

function Get-ReportJs { return Get-ReportAsset -FileName 'report.js' }

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
