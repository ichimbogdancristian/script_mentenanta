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
.SYNOPSIS  Generates the full HTML maintenance report.
.PARAMETER SessionResults  Array of hashtables from New-ModuleResult
.PARAMETER OSContext       Hashtable from Get-OSContext
.PARAMETER TranscriptPath  Path to maintenance.log (Start-Transcript file)
.PARAMETER ReportTitle     Optional report title override
.OUTPUTS   [string] Full path of created HTML file
#>
function New-MaintenanceReport {
    [CmdletBinding(SupportsShouldProcess)]
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

function Build-ReportHtml {
    [CmdletBinding()]
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

    $moduleCards = ($SessionResults | ForEach-Object { Build-ModuleCard -Result $_ }) -join "`n"

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
/* TRANSCRIPT */
details summary{cursor:pointer;font-size:15px;font-weight:600;padding:10px 14px;background:var(--surface);border:1px solid var(--border);border-radius:8px;list-style:none;display:flex;align-items:center;gap:8px}
details summary::-webkit-details-marker{display:none}
details summary::before{content:'▶';font-size:10px;transition:transform .2s}
details[open] summary::before{transform:rotate(90deg)}
details[open] summary{border-radius:8px 8px 0 0;border-bottom:none}
.tx{background:#0a0c14;border:1px solid var(--border);border-top:none;border-radius:0 0 8px 8px;padding:14px;overflow-x:auto;max-height:500px;overflow-y:auto}
.tx pre{font-family:'Cascadia Code',Consolas,monospace;font-size:11px;color:#a0b0c8;white-space:pre-wrap;word-break:break-all}
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

<div class="sec">Module Results</div>
<div class="mod-grid">$moduleCards</div>

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

function Build-ModuleCard {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [hashtable]$Result)

    $badgeClass = switch ($Result.Status) {
        'Success' { 'bs' }
        'Skipped' { 'bm' }
        'Failed' { 'bd' }
        'Warning' { 'bw' }
        default { 'bm' }
    }

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

    return @"
<div class="mod">
  <div class="mod-hd"><span class="nm">$($Result.ModuleName)</span><span class="badge $badgeClass">$($Result.Status)</span></div>
  <div class="mod-bd">
    <div class="r"><span class="k">Timestamp</span><span>$($Result.Timestamp)</span></div>
    <div class="r"><span class="k">Detected</span><span>$($Result.ItemsDetected)</span></div>
    <div class="r"><span class="k">Processed</span><span>$($Result.ItemsProcessed)</span></div>
    <div class="r"><span class="k">Skipped</span><span>$($Result.ItemsSkipped)</span></div>
    <div class="r"><span class="k">Failed</span><span>$($Result.ItemsFailed)</span></div>
    $msgRow
    $errHtml
  </div>
</div>
"@
}

#endregion

#region ─── EXPORTS ───────────────────────────────────────────────────────────

Export-ModuleMember -Function @(
    'New-MaintenanceReport',
    'Build-ReportHtml',
    'Build-ModuleCard'
)

#endregion
