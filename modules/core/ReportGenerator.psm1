#Requires -Version 7.0

<#
.SYNOPSIS
    Report Generator - Self-contained HTML maintenance report

.DESCRIPTION
    Generates a single-file HTML report from module results and the maintenance.log transcript.
    All CSS is embedded inline. No external dependencies.

    Output:
      temp_files/reports/MaintenanceReport_[timestamp].html
      [script.bat folder]/MaintenanceReport_[timestamp].html  (copy)

.NOTES
    Module Type: Core (Report Generation)
    Version: 5.0.0
    Import: Import-Module ReportGenerator.psm1 -Force
#>

Add-Type -AssemblyName System.Web -ErrorAction SilentlyContinue

#region ─── ENTRY POINT ───────────────────────────────────────────────────────

<#
.SYNOPSIS
    Generates the full HTML maintenance report.
.PARAMETER SessionResults
    Array of hashtables from New-ModuleResult.
.PARAMETER OSContext
    Hashtable from Get-OSContext.
.PARAMETER TranscriptPath
    Path to maintenance.log (Start-Transcript file).
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

#region ─── HTML BUILDER ──────────────────────────────────────────────────────

<#
.SYNOPSIS
    Builds the full HTML string for the maintenance report.
.PARAMETER SessionResults  Array of hashtables from New-ModuleResult.
.PARAMETER OSContext       Hashtable from Get-OSContext.
.PARAMETER TranscriptPath  Path to maintenance.log for inline transcript embedding.
.PARAMETER Title           Report title string.
.PARAMETER Timestamp       Session timestamp used in filenames.
.OUTPUTS
    [string] Complete HTML document as a single string.
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

    $totalModules = $SessionResults.Count
    $succeeded = @($SessionResults | Where-Object { $_.Status -eq 'Success' }).Count
    $failed = @($SessionResults | Where-Object { $_.Status -eq 'Failed' }).Count
    $skipped = @($SessionResults | Where-Object { $_.Status -eq 'Skipped' }).Count
    $totalItems = ($SessionResults | ForEach-Object { [int]$_.ItemsProcessed } | Measure-Object -Sum).Sum
    $overallStatus = if ($failed -gt 0) { 'danger' } elseif ($skipped -gt 0) { 'warning' } else { 'success' }
    $overallLabel = if ($failed -gt 0) { 'Completed with Errors' } `
        elseif ($skipped -gt 0) { 'Completed with Skips' } `
        else { 'All tasks completed successfully' }

    # NOTE: cards are built once, below, grouped into $type1Cards / $type2Cards. Do not add an
    # ungrouped "build every card" pass here - it is never emitted and doubles the work (each
    # Build-ModuleCard call re-reads the module's diff file).

    # Error aggregation across all modules
    $allErrors = [System.Collections.Generic.List[string]]::new()
    foreach ($r in $SessionResults) {
        if ($r.Errors -and @($r.Errors).Count -gt 0) {
            foreach ($e in $r.Errors) {
                $allErrors.Add("[" + $r.ModuleName + "] " + $e)
            }
        }
    }

    $errorSummaryHtml = ''
    if ($allErrors.Count -gt 0) {
        $errItems = ($allErrors | ForEach-Object {
                $escaped = $_ -replace '<', '&lt;' -replace '>', '&gt;'
                "<div class='err-mod'><span class='err-msg'>$escaped</span></div>"
            }) -join "`n"
        $errorSummaryHtml = @"
<div class="err-summary">
  <h3>&#9888; $($allErrors.Count) Error(s) Across All Modules</h3>
  $errItems
</div>
"@
    }

    # Group module cards by Type1 (Audits) and Type2 (Actions)
    $type1Results = @($SessionResults | Where-Object { $_.ModuleType -eq 'Type1' })
    $type2Results = @($SessionResults | Where-Object { $_.ModuleType -eq 'Type2' })
    $type1Cards = ($type1Results | ForEach-Object { Build-ModuleCard -Result $_ }) -join "`n"
    $type2Cards = ($type2Results | ForEach-Object { Build-ModuleCard -Result $_ }) -join "`n"

    # Build System Inventory section (if SystemInventory ran)
    $systemInventoryHtml = ''
    $inventoryResult = $SessionResults | Where-Object { $_.ModuleName -eq 'SystemInventory' }
    if ($inventoryResult) {
        $systemInventoryHtml = Build-SystemInventorySection -Result $inventoryResult
    }

    # Build Restore Point Management section (if RestorePointAudit ran)
    $restorePointHtml = ''
    $restoreResult = $SessionResults | Where-Object { $_.ModuleName -eq 'RestorePointAudit' }
    if ($restoreResult) {
        $restorePointHtml = Build-RestorePointSection -Result $restoreResult
    }

    # Build System Health section (if SystemHealthAudit ran)
    $systemHealthHtml = ''
    $healthResult = $SessionResults | Where-Object { $_.ModuleName -eq 'SystemHealthAudit' }
    if ($healthResult) {
        $systemHealthHtml = Build-SystemHealthSection -Result $healthResult
    }

    # Reboot status
    $rebootNeeded = [bool]($SessionResults | Where-Object { $_.RebootRequired -eq $true })
    $rebootBanner = if ($rebootNeeded) {
        '<div class="banner danger">&#9888; One or more modules require a system reboot</div>'
    }
    else { '' }

    $rawTranscript = '(transcript not available)'
    if ($TranscriptPath -and (Test-Path $TranscriptPath)) {
        $rawContent = Get-Content -Path $TranscriptPath -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
        if ($rawContent) {
            try {
                $rawTranscript = [System.Web.HttpUtility]::HtmlEncode($rawContent)
            }
            catch {
                # Fallback if System.Web not available
                $rawTranscript = $rawContent -replace '&', '&amp;' -replace '<', '&lt;' -replace '>', '&gt;'
            }
        }
    }

    $genTime = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $hostname = $env:COMPUTERNAME
    $osText = $OSContext.DisplayText
    $psVer = $PSVersionTable.PSVersion.ToString()
    $runAs = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

    return @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1.0">
<title>$Title</title>
<style>
:root{--bg:#0f1117;--surface:#1a1d27;--card:#22263a;--border:#2e3348;--text:#e2e6f0;--muted:#8892a4;--success:#22c55e;--warning:#f59e0b;--danger:#ef4444;--info:#3b82f6;--accent:#7c3aed}
*,*::before,*::after{box-sizing:border-box;margin:0;padding:0}
body{background:var(--bg);color:var(--text);font-family:'Segoe UI',system-ui,sans-serif;font-size:14px;line-height:1.6}
.container{max-width:1200px;margin:0 auto;padding:24px}
/* HEADER */
.rpt-header{background:linear-gradient(135deg,#1e1b4b 0%,#312e81 50%,#1e1b4b 100%);border-radius:16px;padding:32px;margin-bottom:24px;border:1px solid var(--accent)}
.rpt-header h1{font-size:26px;font-weight:700}
.rpt-header .meta{color:var(--muted);font-size:13px;display:flex;gap:20px;flex-wrap:wrap;margin-top:10px}
.os-badge{display:inline-flex;align-items:center;gap:8px;background:rgba(124,58,237,.2);border:1px solid var(--accent);border-radius:20px;padding:5px 14px;font-size:13px;margin-top:10px}
/* SUMMARY */
.summary-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(160px,1fr));gap:14px;margin-bottom:24px}
.stat{background:var(--surface);border:1px solid var(--border);border-radius:12px;padding:18px;text-align:center}
.stat .val{font-size:34px;font-weight:700;line-height:1}
.stat .lbl{color:var(--muted);font-size:11px;margin-top:5px;text-transform:uppercase;letter-spacing:.5px}
.stat.s .val{color:var(--success)}.stat.w .val{color:var(--warning)}.stat.d .val{color:var(--danger)}.stat.i .val{color:var(--info)}
/* BANNER */
.banner{border-radius:10px;padding:12px 18px;margin-bottom:22px;font-weight:600;font-size:14px}
.banner.success{background:rgba(34,197,94,.1);border:1px solid var(--success);color:var(--success)}
.banner.warning{background:rgba(245,158,11,.1);border:1px solid var(--warning);color:var(--warning)}
.banner.danger {background:rgba(239,68,68,.1) ;border:1px solid var(--danger) ;color:var(--danger)}
/* SECTION TITLE */
.sec{font-size:17px;font-weight:600;margin:24px 0 12px;padding-bottom:7px;border-bottom:2px solid var(--border)}
/* INFO ROW */
.info-row{display:flex;gap:12px;flex-wrap:wrap;margin-bottom:22px}
.inf{background:var(--surface);border:1px solid var(--border);border-radius:8px;padding:8px 14px;font-size:12px}
.inf .k{color:var(--muted);font-size:11px;text-transform:uppercase;letter-spacing:.4px}
.inf .v{font-weight:600;margin-top:2px}
/* MODULE CARDS */
.mod-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(320px,1fr));gap:14px;margin-bottom:22px}
.mod{background:var(--card);border:1px solid var(--border);border-radius:12px;overflow:hidden}
.mod-hd{padding:12px 16px;display:flex;align-items:center;justify-content:space-between;border-bottom:1px solid var(--border)}
.mod-hd .nm{font-weight:600;font-size:14px}
.mod-bd{padding:12px 16px}
.mod-bd .r{display:flex;justify-content:space-between;padding:5px 0;border-bottom:1px solid var(--border);font-size:12px}
.mod-bd .r:last-child{border-bottom:none}
.mod-bd .r .k{color:var(--muted)}
.mod-type{font-size:10px;color:var(--muted);margin-left:6px;text-transform:uppercase;letter-spacing:.5px}
.reboot-tag{display:inline-block;padding:1px 7px;border-radius:8px;font-size:10px;font-weight:600;background:rgba(239,68,68,.15);color:var(--danger);border:1px solid rgba(239,68,68,.3);margin-left:6px}
/* BADGES */
.badge{display:inline-block;padding:2px 9px;border-radius:12px;font-size:11px;font-weight:600}
.bs{background:rgba(34,197,94,.15);color:var(--success);border:1px solid rgba(34,197,94,.3)}
.bw{background:rgba(245,158,11,.15);color:var(--warning);border:1px solid rgba(245,158,11,.3)}
.bd{background:rgba(239,68,68,.15);color:var(--danger);border:1px solid rgba(239,68,68,.3)}
.bm{background:rgba(136,146,164,.15);color:var(--muted);border:1px solid rgba(136,146,164,.3)}
/* ERRORS */
.errs{margin-top:6px;list-style:none}
.errs li{font-size:11px;color:var(--danger);padding:2px 0 2px 12px;position:relative}
.errs li::before{content:'✕';position:absolute;left:0}
/* ERROR AGGREGATION */
.err-summary{background:rgba(239,68,68,.05);border:1px solid rgba(239,68,68,.2);border-radius:10px;padding:14px 18px;margin-bottom:22px}
.err-summary h3{font-size:14px;color:var(--danger);margin-bottom:8px}
.err-summary .err-mod{font-size:12px;margin-bottom:6px}
.err-summary .err-mod .mod-name{font-weight:600;color:var(--text)}
.err-summary .err-mod .err-msg{color:var(--muted);font-size:11px;padding-left:12px}
/* DETAIL ITEMS */
.mod-details{margin-top:8px}
.mod-details summary{font-size:12px;font-weight:600;padding:6px 10px;background:rgba(124,58,237,.08);border:1px solid rgba(124,58,237,.2);border-radius:6px;cursor:pointer;list-style:none;display:flex;align-items:center;gap:6px}
.mod-details summary::-webkit-details-marker{display:none}
.mod-details summary::before{content:'▶';font-size:8px;transition:transform .2s}
.mod-details[open] summary::before{transform:rotate(90deg)}
.item-list{margin-top:6px;font-size:11px}
.item-list .item{padding:4px 8px;border-left:2px solid var(--accent);margin-bottom:3px;background:rgba(124,58,237,.04);border-radius:0 4px 4px 0}
.item-list .item .item-name{font-weight:600;color:var(--text)}
.item-list .item .item-detail{color:var(--muted)}
/* EXTRA DATA */
.extra{margin-top:6px}
.extra .ex-row{display:flex;justify-content:space-between;padding:3px 0;font-size:11px;border-bottom:1px solid rgba(46,51,72,.5)}
.extra .ex-row .k{color:var(--muted)}
.extra .ex-row .v{color:var(--info)}
/* TRANSCRIPT */
details summary{cursor:pointer;font-size:15px;font-weight:600;padding:10px 14px;background:var(--surface);border:1px solid var(--border);border-radius:8px;list-style:none;display:flex;align-items:center;gap:8px}
details summary::-webkit-details-marker{display:none}
details summary::before{content:'▶';font-size:10px;transition:transform .2s}
details[open] summary::before{transform:rotate(90deg)}
details[open] summary{border-radius:8px 8px 0 0;border-bottom:none}
.tx{background:#0a0c14;border:1px solid var(--border);border-top:none;border-radius:0 0 8px 8px;padding:14px;overflow-x:auto;max-height:500px;overflow-y:auto}
.tx pre{font-family:'Cascadia Code',Consolas,monospace;font-size:11px;color:#a0b0c8;white-space:pre-wrap;word-break:break-all}
/* INVENTORY SECTION - NETWORK */
.nic-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(280px,1fr));gap:12px;margin-bottom:22px}
.nic-card{background:var(--surface);border:1px solid var(--border);border-radius:8px;padding:12px;overflow:hidden}
.nic-card.extip{background:linear-gradient(135deg,rgba(124,58,237,.1) 0%,rgba(59,130,246,.1) 100%);border:1px solid rgba(124,58,237,.3)}
.nic-desc{font-weight:600;color:var(--text);margin-bottom:8px;font-size:12px}
.nic-info{display:flex;justify-content:space-between;font-size:11px;padding:3px 0;border-bottom:1px solid rgba(46,51,72,.3)}
.nic-info:last-child{border-bottom:none}
.nic-label{color:var(--muted);font-weight:500}
.nic-value{color:var(--text);font-family:monospace;word-break:break-all}
/* INVENTORY SECTION - USERS */
.user-container{background:var(--surface);border:1px solid var(--border);border-radius:8px;overflow:hidden;margin-bottom:22px}
.user-header{display:grid;grid-template-columns:120px 1fr 140px;gap:12px;padding:10px 14px;background:var(--card);border-bottom:1px solid var(--border);font-weight:600;font-size:11px;color:var(--muted);text-transform:uppercase}
.user-list{max-height:300px;overflow-y:auto}
.user-row{display:grid;grid-template-columns:120px 1fr 140px;gap:12px;padding:8px 14px;border-bottom:1px solid rgba(46,51,72,.3);font-size:11px;align-items:center}
.user-row:last-child{border-bottom:none}
.user-name{font-weight:600;color:var(--text)}
.user-info{color:var(--muted);white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.user-logon{color:var(--muted);font-size:10px;white-space:nowrap}
/* INVENTORY SECTION - RESTORE POINTS */
.rp-container{background:var(--surface);border:1px solid var(--border);border-radius:8px;overflow:hidden;margin-bottom:22px}
.rp-header{display:grid;grid-template-columns:1fr 120px 150px;gap:12px;padding:10px 14px;background:var(--card);border-bottom:1px solid var(--border);font-weight:600;font-size:11px;color:var(--muted);text-transform:uppercase}
.rp-list{max-height:350px;overflow-y:auto}
.rp-row{display:grid;grid-template-columns:1fr 120px 150px;gap:12px;padding:8px 14px;border-bottom:1px solid rgba(46,51,72,.3);font-size:11px;align-items:center}
.rp-row:last-child{border-bottom:none}
.rp-desc{color:var(--text);font-weight:500;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.rp-type{color:var(--info);font-size:10px;background:rgba(59,130,246,.1);padding:2px 6px;border-radius:3px;text-align:center}
.rp-time{color:var(--muted);font-size:10px;white-space:nowrap}
.rp-more{padding:8px 14px;color:var(--muted);font-size:10px;text-align:center;background:rgba(124,58,237,.04)}
/* AUDIT SECTION - RESTORE POINT AUDIT */
.audit-rp-summary{display:grid;grid-template-columns:repeat(auto-fit,minmax(120px,1fr));gap:12px;margin-bottom:22px}
.audit-rp-stat{background:var(--surface);border:1px solid var(--border);border-radius:8px;padding:12px;text-align:center}
.audit-rp-val{font-size:24px;font-weight:700;color:var(--accent);line-height:1}
.audit-rp-lbl{color:var(--muted);font-size:10px;margin-top:4px;text-transform:uppercase;letter-spacing:.5px}
.audit-rp-container{background:var(--surface);border:1px solid var(--border);border-radius:8px;overflow:hidden;margin-bottom:22px}
.audit-rp-header{display:grid;grid-template-columns:50px 1fr 100px 140px;gap:12px;padding:10px 14px;background:var(--card);border-bottom:1px solid var(--border);font-weight:600;font-size:11px;color:var(--muted);text-transform:uppercase}
.audit-rp-list{max-height:400px;overflow-y:auto}
.audit-rp-row{display:grid;grid-template-columns:50px 1fr 100px 140px;gap:12px;padding:8px 14px;border-bottom:1px solid rgba(46,51,72,.3);font-size:11px;align-items:center}
.audit-rp-row:last-child{border-bottom:none}
.audit-rp-seq{color:var(--muted);font-weight:600;font-family:monospace}
.audit-rp-desc{color:var(--text);white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.audit-rp-type{color:var(--info);background:rgba(59,130,246,.1);padding:2px 6px;border-radius:3px;text-align:center;font-size:10px}
.audit-rp-time{color:var(--muted);font-size:10px;white-space:nowrap}
.audit-rp-more{padding:8px 14px;color:var(--muted);font-size:10px;text-align:center;background:rgba(124,58,237,.04)}
/* SYSTEM HEALTH SECTION */
.evt-container,.def-container{background:var(--surface);border:1px solid var(--border);border-radius:8px;overflow:hidden;margin-bottom:22px}
.evt-header,.def-header{display:grid;grid-template-columns:70px 1fr 2fr 140px;gap:12px;padding:10px 14px;background:var(--card);border-bottom:1px solid var(--border);font-weight:600;font-size:11px;color:var(--muted);text-transform:uppercase}
.evt-list,.def-list{max-height:400px;overflow-y:auto}
.evt-row,.def-row{display:grid;grid-template-columns:70px 1fr 2fr 140px;gap:12px;padding:8px 14px;border-bottom:1px solid rgba(46,51,72,.3);font-size:11px;align-items:center}
.evt-row:last-child,.def-row:last-child{border-bottom:none}
.evt-level{font-weight:600;padding:2px 6px;border-radius:4px;text-align:center}
.evt-level.evt-error{background:rgba(239,68,68,.15);color:var(--danger)}
.evt-level.evt-critical{background:rgba(239,68,68,.25);color:#ff6b6b}
.evt-src,.def-threat{font-weight:600;color:var(--text);white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.evt-msg,.def-path{color:var(--muted);white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.evt-ts,.def-ts{color:var(--muted);font-size:10px;white-space:nowrap}
.def-sev{font-weight:600;padding:2px 8px;border-radius:4px;text-align:center;font-size:10px}
.def-sev.sev-high{background:rgba(239,68,68,.15);color:var(--danger)}
.def-sev.sev-med{background:rgba(245,158,11,.15);color:var(--warning)}
.def-sev.sev-low{background:rgba(34,197,94,.15);color:var(--success)}
.evt-more,.def-more{padding:8px 14px;color:var(--muted);font-size:10px;text-align:center;background:rgba(124,58,237,.04)}
.excl-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(300px,1fr));gap:14px;margin-bottom:22px}
.excl-card{background:var(--surface);border:1px solid var(--border);border-radius:8px;padding:12px;overflow:hidden}
.excl-title{font-weight:600;color:var(--text);margin-bottom:8px;font-size:12px}
.excl-list{max-height:300px;overflow-y:auto}
.excl-item{padding:4px 6px;font-size:11px;color:var(--muted);border-left:2px solid var(--accent);padding-left:8px;margin-bottom:3px;background:rgba(124,58,237,.04);border-radius:0 4px 4px 0;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.excl-more{padding:4px 6px;font-size:10px;color:var(--info);text-align:center}
/* FOOTER */
.footer{text-align:center;color:var(--muted);font-size:12px;padding:18px 0;border-top:1px solid var(--border);margin-top:22px}
</style>
</head>
<body>
<div class="container">

<div class="rpt-header">
  <h1>$Title</h1>
  <div class="meta">
    <span>&#128421; $hostname</span>
    <span>&#128336; $genTime</span>
    <span>&#128196; Session $Timestamp</span>
  </div>
  <div class="os-badge">&#129695; $osText</div>
</div>

<div class="banner $overallStatus">$overallLabel</div>
$rebootBanner
$errorSummaryHtml

<div class="summary-grid">
  <div class="stat">   <div class="val">$totalModules</div><div class="lbl">Modules Run</div></div>
  <div class="stat s"> <div class="val">$succeeded</div>   <div class="lbl">Succeeded</div></div>
  <div class="stat w"> <div class="val">$skipped</div>     <div class="lbl">Skipped</div></div>
  <div class="stat d"> <div class="val">$failed</div>      <div class="lbl">Failed</div></div>
  <div class="stat i"> <div class="val">$totalItems</div>  <div class="lbl">Items Changed</div></div>
</div>

<div class="info-row">
  <div class="inf"><div class="k">Hostname</div><div class="v">$hostname</div></div>
  <div class="inf"><div class="k">OS</div><div class="v">$osText</div></div>
  <div class="inf"><div class="k">PowerShell</div><div class="v">$psVer</div></div>
  <div class="inf"><div class="k">Run As</div><div class="v">$runAs</div></div>
  <div class="inf"><div class="k">Generated</div><div class="v">$genTime</div></div>
</div>

<div class="sec">Stage 1 &mdash; System Audit Results</div>
<div class="mod-grid">$type1Cards</div>

$systemInventoryHtml

$restorePointHtml

$systemHealthHtml

<div class="sec">Stage 3 &mdash; Maintenance Action Results</div>
<div class="mod-grid">$type2Cards</div>

<div class="sec">Maintenance Log (Full Transcript)</div>
<details>
  <summary>&#128196; maintenance.log - click to expand</summary>
  <div class="tx"><pre>$rawTranscript</pre></div>
</details>

<div class="footer">Windows Maintenance Automation v5.0 &bull; $genTime &bull; $hostname</div>
</div>
</body>
</html>
"@
}

<#
.SYNOPSIS
    Builds an HTML card snippet for a single module result.
.PARAMETER Result
    Hashtable produced by New-ModuleResult.
.OUTPUTS
    [string] HTML fragment for the module card.
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
    $rebootTag = if ($Result.RebootRequired) { "<span class='reboot-tag'>Reboot Required</span>" } else { '' }

    $errHtml = ''
    if ($Result.Errors -and @($Result.Errors).Count -gt 0) {
        $items = ($Result.Errors | ForEach-Object {
                try { "<li>$([System.Web.HttpUtility]::HtmlEncode($_))</li>" }
                catch { "<li>$($_ -replace '<','&lt;' -replace '>','&gt;')</li>" }
            }) -join ''
        $errHtml = "<ul class='errs'>$items</ul>"
    }

    $msg = if ($Result.Message) {
        try { [System.Web.HttpUtility]::HtmlEncode($Result.Message) }
        catch { $Result.Message -replace '<', '&lt;' -replace '>', '&gt;' }
    }
    else { '' }
    $msgRow = if ($msg) { "<div class='r'><span class='k'>Note</span><span>$msg</span></div>" } else { '' }

    # ExtraData rendering
    $extraHtml = ''
    if ($Result.ExtraData -and $Result.ExtraData.Count -gt 0) {
        $exRows = ($Result.ExtraData.GetEnumerator() | ForEach-Object {
                $ek = $_.Key -replace '<', '&lt;' -replace '>', '&gt;'
                $ev = "$($_.Value)" -replace '<', '&lt;' -replace '>', '&gt;'
                "<div class='ex-row'><span class='k'>$ek</span><span class='v'>$ev</span></div>"
            }) -join ''
        $extraHtml = "<div class='extra'>$exRows</div>"
    }

    # Detailed items from the diff list (what was audited/changed).
    #
    # A Type2 result's ModuleName already equals its DiffKey (e.g. 'SoftwareManagement'); a Type1
    # result's is the audit function name ('SoftwareManagementAudit'). Stripping the 'Audit' suffix
    # maps an audit back to the diff its pair shares. This replaces a hardcoded lookup table that
    # still listed only pre-consolidation module names (BloatwareRemoval, EssentialApps,
    # SecurityEnhancement, TelemetryDisable, SystemOptimization, AppUpgrade) and therefore silently
    # dropped the detail section for every current audit card except WindowsUpdatesAudit.
    $detailHtml = ''
    $moduleName = $Result.ModuleName
    try {
        $diffData = Get-DiffList -ModuleName $moduleName
        if (-not $diffData -or $diffData.Count -eq 0) {
            $pairKey = $moduleName -replace 'Audit$', ''
            if ($pairKey -ne $moduleName) {
                $diffData = Get-DiffList -ModuleName $pairKey
            }
        }
        if ($diffData -and $diffData.Count -gt 0) {
            $maxItems = [Math]::Min($diffData.Count, 20)  # Cap at 20 items to keep report readable
            $itemRows = ($diffData[0..($maxItems - 1)] | ForEach-Object {
                    $itemName = ($_.Name ?? $_.name ?? 'Unknown') -replace '<', '&lt;' -replace '>', '&gt;'
                    $itemType = ($_.Type ?? $_.type ?? '') -replace '<', '&lt;' -replace '>', '&gt;'
                    $currentSt = ($_.CurrentState ?? '') -replace '<', '&lt;' -replace '>', '&gt;'
                    $desiredSt = ($_.DesiredState ?? '') -replace '<', '&lt;' -replace '>', '&gt;'
                    $desc = ($_.Description ?? '') -replace '<', '&lt;' -replace '>', '&gt;'
                    $detailText = if ($desc) { $desc }
                    elseif ($currentSt -and $desiredSt) { "$currentSt &#8594; $desiredSt" }
                    else { $itemType }
                    "<div class='item'><span class='item-name'>$itemName</span> <span class='item-detail'>$detailText</span></div>"
                }) -join ''
            $moreText = if ($diffData.Count -gt 20) { " <span style='color:var(--muted);font-size:10px'>(+$($diffData.Count - 20) more)</span>" } else { '' }
            $detailHtml = @"
<details class="mod-details">
  <summary>$($diffData.Count) item(s) detailed$moreText</summary>
  <div class="item-list">$itemRows</div>
</details>
"@
        }
    }
    catch {
        # Diff data not available — that's fine, skip detail section
    }

    return @"
<div class="mod">
  <div class="mod-hd"><span class="nm">$($Result.ModuleName)$typeLabel$rebootTag</span><span class="badge $badgeClass">$($Result.Status)</span></div>
  <div class="mod-bd">
    <div class="r"><span class="k">Timestamp</span><span>$($Result.Timestamp)</span></div>
    <div class="r"><span class="k">Detected</span><span>$($Result.ItemsDetected)</span></div>
    <div class="r"><span class="k">Processed</span><span>$($Result.ItemsProcessed)</span></div>
    <div class="r"><span class="k">Skipped</span><span>$($Result.ItemsSkipped)</span></div>
    <div class="r"><span class="k">Failed</span><span>$($Result.ItemsFailed)</span></div>
    $msgRow
    $extraHtml
    $errHtml
    $detailHtml
  </div>
</div>
"@
}

<#
.SYNOPSIS
    Builds the System Inventory section with network, users, and restore points.
.PARAMETER Result
    Hashtable from SystemInventory module result.
.OUTPUTS
    [string] HTML fragment for the system inventory section.
#>
function Build-SystemInventorySection {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [hashtable]$Result)

    $dataPath = Get-TempPath -Category 'data' -FileName 'system-inventory.json' -ErrorAction SilentlyContinue
    if (-not $dataPath -or -not (Test-Path $dataPath)) {
        return ''
    }

    try {
        $invData = Get-Content -Path $dataPath -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        return ''
    }

    $networkHtml = ''
    if ($invData.Network -and @($invData.Network).Count -gt 0) {
        $nicRows = ($invData.Network | ForEach-Object {
                $desc = $_.Description -replace '<', '&lt;' -replace '>', '&gt;'
                $mac = $_.MAC -replace '<', '&lt;' -replace '>', '&gt;'
                $ips = ($_.IPs | ForEach-Object { $_ -replace '<', '&lt;' -replace '>', '&gt;' }) -join ', '
                $dns = ($_.DNSServers | ForEach-Object { $_ -replace '<', '&lt;' -replace '>', '&gt;' }) -join ', '
                "<div class='nic-card'>
                    <div class='nic-desc'>$desc</div>
                    <div class='nic-info'><span class='nic-label'>MAC:</span> <span class='nic-value'>$mac</span></div>
                    <div class='nic-info'><span class='nic-label'>IP(s):</span> <span class='nic-value'>$ips</span></div>
                    <div class='nic-info'><span class='nic-label'>DNS:</span> <span class='nic-value'>$(if($dns) { $dns } else { 'Not configured' })</span></div>
                </div>"
            }) -join ''

        $extIP = if ($invData.ExternalIP.Address -and $invData.ExternalIP.Address -ne 'Unable to determine') {
            "<div class='nic-card extip'>
                <div class='nic-desc'>🌐 External IP Address</div>
                <div class='nic-info'><span class='nic-value' style='font-size:14px;font-weight:600'>$($invData.ExternalIP.Address)</span></div>
            </div>"
        } else { '' }

        $networkHtml = @"
<div class="sec">Network Configuration</div>
<div class="nic-grid">
    $nicRows
    $extIP
</div>
"@
    }

    $usersHtml = ''
    if ($invData.LocalUsers -and @($invData.LocalUsers).Count -gt 0) {
        $userRows = ($invData.LocalUsers | ForEach-Object {
                $name = $_.Name -replace '<', '&lt;' -replace '>', '&gt;'
                $fullName = if ($_.FullName) { $_.FullName -replace '<', '&lt;' -replace '>', '&gt;' } else { '(no display name)' }
                $lastLogon = $_.LastLogon -replace '<', '&lt;' -replace '>', '&gt;'
                "<div class='user-row'>
                    <span class='user-name'>👤 $name</span>
                    <span class='user-info'>$fullName</span>
                    <span class='user-logon'>$lastLogon</span>
                </div>"
            }) -join ''

        $usersHtml = @"
<div class="sec">Local Users (Custom)</div>
<div class="user-container">
    <div class="user-header">
        <span class="user-name">User</span>
        <span class="user-info">Full Name</span>
        <span class="user-logon">Last Logon</span>
    </div>
    <div class="user-list">
        $userRows
    </div>
</div>
"@
    }

    $restorePointsHtml = ''
    if ($invData.RestorePoints -and @($invData.RestorePoints).Count -gt 0) {
        $rpRows = ($invData.RestorePoints[0..([Math]::Min(15, $invData.RestorePoints.Count - 1))] | ForEach-Object {
                $desc = $_.Description -replace '<', '&lt;' -replace '>', '&gt;'
                $created = $_.CreationTime -replace '<', '&lt;' -replace '>', '&gt;'
                $type = $_.RestorePointType -replace '<', '&lt;' -replace '>', '&gt;'
                "<div class='rp-row'>
                    <span class='rp-desc'>$desc</span>
                    <span class='rp-type'>$type</span>
                    <span class='rp-time'>$created</span>
                </div>"
            }) -join ''

        $rpMore = if ($invData.RestorePoints.Count -gt 15) { "<div class='rp-more'>+$($invData.RestorePoints.Count - 15) more restore points</div>" } else { '' }

        $restorePointsHtml = @"
<div class="sec">System Restore Points</div>
<div class="rp-container">
    <div class="rp-header">
        <span class="rp-desc">Description</span>
        <span class="rp-type">Type</span>
        <span class="rp-time">Created</span>
    </div>
    <div class="rp-list">
        $rpRows
    </div>
    $rpMore
</div>
"@
    }

    return @"
$networkHtml
$usersHtml
$restorePointsHtml
"@
}

<#
.SYNOPSIS
    Builds the Restore Point Management section.
.PARAMETER Result
    Hashtable from RestorePointAudit module result.
.OUTPUTS
    [string] HTML fragment for the restore point management section.
#>
function Build-RestorePointSection {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [hashtable]$Result)

    $dataPath = Get-TempPath -Category 'data' -FileName 'restore-point-audit.json' -ErrorAction SilentlyContinue
    if (-not $dataPath -or -not (Test-Path $dataPath)) {
        return ''
    }

    try {
        $rpData = Get-Content -Path $dataPath -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        return ''
    }

    if (-not $rpData.RestorePointsList -or $rpData.RestorePointsList.Count -eq 0) {
        return ''
    }

    $rpRows = ($rpData.RestorePointsList[0..([Math]::Min(20, $rpData.RestorePointsList.Count - 1))] | ForEach-Object {
            $desc = $_.Description -replace '<', '&lt;' -replace '>', '&gt;'
            $created = $_.CreationTime -replace '<', '&lt;' -replace '>', '&gt;'
            $type = $_.RestorePointType -replace '<', '&lt;' -replace '>', '&gt;'
            $seq = $_.SequenceNumber
            "<div class='audit-rp-row'>
                <span class='audit-rp-seq'>#$seq</span>
                <span class='audit-rp-desc'>$desc</span>
                <span class='audit-rp-type'>$type</span>
                <span class='audit-rp-time'>$created</span>
            </div>"
        }) -join ''

    $rpMore = if ($rpData.RestorePointsList.Count -gt 20) { "<div class='audit-rp-more'>+$($rpData.RestorePointsList.Count - 20) more restore points</div>" } else { '' }

    $statusColor = if ($rpData.ToRemove -gt 0) { 'warning' } else { 'success' }
    $statusText = "Current: $($rpData.CurrentCount) | Keep minimum: $($rpData.MinimumToKeep) | Allocation: $($rpData.AllocationGB)GB"

    return @"
<div class="sec">Restore Point Audit Details</div>
<div class="audit-rp-summary">
    <div class="audit-rp-stat">
        <div class="audit-rp-val">$($rpData.CurrentCount)</div>
        <div class="audit-rp-lbl">Current Points</div>
    </div>
    <div class="audit-rp-stat">
        <div class="audit-rp-val">$($rpData.ToRemove)</div>
        <div class="audit-rp-lbl">To Remove</div>
    </div>
    <div class="audit-rp-stat">
        <div class="audit-rp-val">$($rpData.MinimumToKeep)</div>
        <div class="audit-rp-lbl">Minimum to Keep</div>
    </div>
    <div class="audit-rp-stat">
        <div class="audit-rp-val">$($rpData.AllocationGB)GB</div>
        <div class="audit-rp-lbl">Allocation</div>
    </div>
</div>
<div class="audit-rp-container">
    <div class="audit-rp-header">
        <span class="audit-rp-seq">Seq</span>
        <span class="audit-rp-desc">Description</span>
        <span class="audit-rp-type">Type</span>
        <span class="audit-rp-time">Created</span>
    </div>
    <div class="audit-rp-list">
        $rpRows
    </div>
    $rpMore
</div>
"@
}

<#
.SYNOPSIS
    Builds the System Health section with Event Viewer events, Defender incidents, and exclusions.
.PARAMETER Result
    Hashtable from SystemHealthAudit module result.
.OUTPUTS
    [string] HTML fragment for the system health section.
#>
function Build-SystemHealthSection {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [hashtable]$Result)

    if (-not $Result.ExtraData) {
        return ''
    }

    $dataPath = Get-TempPath -Category 'data' -FileName 'system-health-report.json' -ErrorAction SilentlyContinue
    if (-not $dataPath -or -not (Test-Path $dataPath)) {
        return ''
    }

    try {
        $healthData = Get-Content -Path $dataPath -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        return ''
    }

    $eventHtml = ''
    if ($healthData.EventViewerEvents -and @($healthData.EventViewerEvents).Count -gt 0) {
        $eventRows = ($healthData.EventViewerEvents[0..([Math]::Min(20, $healthData.EventViewerEvents.Count - 1))] | ForEach-Object {
                $level = $_.Level -replace '<', '&lt;' -replace '>', '&gt;'
                $src = $_.Source -replace '<', '&lt;' -replace '>', '&gt;'
                $msg = ($_.Message -replace '<', '&lt;' -replace '>', '&gt;')[0..100] -join ''
                $ts = $_.Timestamp
                "<div class='evt-row'><span class='evt-level evt-$($level.ToLower())'>$level</span><span class='evt-src'>$src</span><span class='evt-msg'>$msg...</span><span class='evt-ts'>$ts</span></div>"
            }) -join ''
        $moreEvents = if ($healthData.EventViewerEvents.Count -gt 20) { "<div class='evt-more'>+$($healthData.EventViewerEvents.Count - 20) more events</div>" } else { '' }
        $eventHtml = @"
<div class="sec">Event Viewer &mdash; Critical & Error Events (Last 30 Days)</div>
<div class="evt-container">
  <div class="evt-header">
    <span class="evt-level">Level</span>
    <span class="evt-src">Source</span>
    <span class="evt-msg">Message</span>
    <span class="evt-ts">Timestamp</span>
  </div>
  <div class="evt-list">
    $eventRows
  </div>
  $moreEvents
</div>
"@
    }

    $defenderHtml = ''
    if ($healthData.DefenderIncidents -and @($healthData.DefenderIncidents).Count -gt 0) {
        $incRows = ($healthData.DefenderIncidents[0..([Math]::Min(20, $healthData.DefenderIncidents.Count - 1))] | ForEach-Object {
                $threat = $_.ThreatName -replace '<', '&lt;' -replace '>', '&gt;'
                $sev = $_.Severity -replace '<', '&lt;' -replace '>', '&gt;'
                $path = ($_.DetectionPath -replace '<', '&lt;' -replace '>', '&gt;')[0..60] -join ''
                $ts = $_.Timestamp
                $sevClass = if ($sev -eq 'High') { 'sev-high' } elseif ($sev -eq 'Medium') { 'sev-med' } else { 'sev-low' }
                "<div class='def-row'><span class='def-threat'>$threat</span><span class='def-sev $sevClass'>$sev</span><span class='def-path'>$path...</span><span class='def-ts'>$ts</span></div>"
            }) -join ''
        $moreInc = if ($healthData.DefenderIncidents.Count -gt 20) { "<div class='def-more'>+$($healthData.DefenderIncidents.Count - 20) more incidents</div>" } else { '' }
        $defenderHtml = @"
<div class="sec">Windows Defender &mdash; Incidents (Last 30 Days)</div>
<div class="def-container">
  <div class="def-header">
    <span class="def-threat">Threat Name</span>
    <span class="def-sev">Severity</span>
    <span class="def-path">Detection Path</span>
    <span class="def-ts">Timestamp</span>
  </div>
  <div class="def-list">
    $incRows
  </div>
  $moreInc
</div>
"@
    }

    $exclusionsHtml = ''
    if ($healthData.DefenderExclusions) {
        $exclData = $healthData.DefenderExclusions
        $folderRows = ($exclData.FolderExclusions[0..([Math]::Min(10, ($exclData.FolderExclusions.Count ?? 0) - 1))] | ForEach-Object {
                $p = $_ -replace '<', '&lt;' -replace '>', '&gt;'
                "<div class='excl-item'>📁 $p</div>"
            }) -join ''
        $extRows = ($exclData.ExtensionExclusions[0..([Math]::Min(10, ($exclData.ExtensionExclusions.Count ?? 0) - 1))] | ForEach-Object {
                $e = $_ -replace '<', '&lt;' -replace '>', '&gt;'
                "<div class='excl-item'>📄 $e</div>"
            }) -join ''
        $procRows = ($exclData.ProcessExclusions[0..([Math]::Min(10, ($exclData.ProcessExclusions.Count ?? 0) - 1))] | ForEach-Object {
                $pr = $_ -replace '<', '&lt;' -replace '>', '&gt;'
                "<div class='excl-item'>⚙️ $pr</div>"
            }) -join ''

        $folderMore = if ($exclData.FolderExclusions.Count -gt 10) { "<div class='excl-more'>+$($exclData.FolderExclusions.Count - 10) more</div>" } else { '' }
        $extMore = if ($exclData.ExtensionExclusions.Count -gt 10) { "<div class='excl-more'>+$($exclData.ExtensionExclusions.Count - 10) more</div>" } else { '' }
        $procMore = if ($exclData.ProcessExclusions.Count -gt 10) { "<div class='excl-more'>+$($exclData.ProcessExclusions.Count - 10) more</div>" } else { '' }

        $exclusionsHtml = @"
<div class="sec">Windows Defender &mdash; Exclusions</div>
<div class="excl-grid">
  <div class="excl-card">
    <div class="excl-title">Folder Exclusions ($($exclData.FolderExclusions.Count))</div>
    <div class="excl-list">$folderRows</div>
    $folderMore
  </div>
  <div class="excl-card">
    <div class="excl-title">Extension Exclusions ($($exclData.ExtensionExclusions.Count))</div>
    <div class="excl-list">$extRows</div>
    $extMore
  </div>
  <div class="excl-card">
    <div class="excl-title">Process Exclusions ($($exclData.ProcessExclusions.Count))</div>
    <div class="excl-list">$procRows</div>
    $procMore
  </div>
</div>
"@
    }

    return @"
$eventHtml
$defenderHtml
$exclusionsHtml
"@
}

#endregion

#region ─── EXPORTS ───────────────────────────────────────────────────────────

Export-ModuleMember -Function @(
    'New-MaintenanceReport',
    'Build-ReportHtml',
    'Build-ModuleCard',
    'Build-SystemInventorySection',
    'Build-RestorePointSection',
    'Build-SystemHealthSection'
)

#endregion
