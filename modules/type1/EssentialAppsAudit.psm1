#Requires -Version 7.0
<#
.SYNOPSIS    Essential Apps Audit - Type 1
.DESCRIPTION Scans installed software against the essential apps baseline.
             Diff = apps in baseline that are NOT installed (need to be installed).
.NOTES       Module Type: Type1 | DiffKey: EssentialApps | Version: 5.0
#>

$_corePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'core\Maintenance.psm1'
if (-not (Get-Command 'Write-Log' -ErrorAction SilentlyContinue)) {
    Import-Module $_corePath -Force -Global -WarningAction SilentlyContinue
}

function Invoke-EssentialAppsAudit {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    Write-Log -Level INFO -Component APPS-AUDIT -Message 'Starting essential apps audit'

    try {
        # 1. Load baseline
        $baseline = Get-BaselineList -ModuleFolder 'essential-apps' -FileName 'essential-apps.json'
        if (-not $baseline) {
            return New-ModuleResult -ModuleName 'EssentialAppsAudit' -Status 'Failed' `
                                    -Message 'Essential apps baseline list not found'
        }
        $baselineApps = @($baseline)
        Write-Log -Level INFO -Component APPS-AUDIT -Message "Baseline: $($baselineApps.Count) essential apps"

        # 2. Scan installed software
        $installed = Get-InstalledApp
        $installedNames = $installed | ForEach-Object { $_.Name.ToLowerInvariant() } | Where-Object { $_ }

        # 3. Also check winget list for accurate detection
        $wingetInstalled = @()
        if (Test-CommandAvailable 'winget') {
            try {
                $raw = & winget list --accept-source-agreements 2>&1 | Where-Object { $_ -is [string] -and $_ -match '\S' }
                $wingetInstalled = $raw | Where-Object { $_ -notmatch '^[-=]' -and $_ -notmatch '^Name' } | ForEach-Object { $_.Trim().ToLowerInvariant() }
            }
            catch { Write-Log -Level WARN -Component APPS-AUDIT -Message "winget list failed: $_" }
        }

        # 4. Detect if Microsoft Office is installed (skip LibreOffice if so)
        $hasMsOffice = $installedNames | Where-Object { $_ -match 'microsoft.*(office|word|excel|outlook)' }

        # 5. Build diff: apps NOT installed
        $missing = [System.Collections.Generic.List[object]]::new()
        foreach ($app in $baselineApps) {
            $appNameLow = if ($app.name) { $app.name.ToLowerInvariant() } else { continue }

            # Skip LibreOffice when MS Office is present
            if ($appNameLow -match 'libreoffice' -and $hasMsOffice) {
                Write-Log -Level INFO -Component APPS-AUDIT -Message "LibreOffice skipped - MS Office detected"
                continue
            }

            # Check registry, winget installed list, and AppX
            $foundByName   = $installedNames | Where-Object { $_ -like "*$appNameLow*" }
            $wingetId      = $app.winget
            $foundByWinget = if ($wingetId) { $wingetInstalled | Where-Object { $_ -like "*$($wingetId.ToLowerInvariant())*" } } else { $null }

            if (-not $foundByName -and -not $foundByWinget) {
                $missing.Add($app)
                Write-Log -Level DEBUG -Component APPS-AUDIT -Message "  MISSING: $($app.name)"
            }
            else {
                Write-Log -Level DEBUG -Component APPS-AUDIT -Message "  OK: $($app.name)"
            }
        }

        Write-Log -Level INFO -Component APPS-AUDIT -Message "Missing apps: $($missing.Count)"

        # 6. Save diff
        Save-DiffList -ModuleName 'EssentialApps' -DiffList $missing.ToArray()

        # 7. Persist audit data
        $auditPath = Get-TempPath -Category 'data' -FileName 'essential-apps-audit.json'
        @{ Timestamp = (Get-Date -Format 'o'); Missing = $missing.ToArray(); BaselineCount = $baselineApps.Count } `
            | ConvertTo-Json -Depth 8 | Set-Content -Path $auditPath -Encoding UTF8 -Force

        Write-Log -Level SUCCESS -Component APPS-AUDIT -Message "Essential apps audit complete: $($missing.Count) missing"
        return New-ModuleResult -ModuleName 'EssentialAppsAudit' -Status 'Success' `
                                -ItemsDetected $missing.Count `
                                -Message "$($missing.Count) of $($baselineApps.Count) essential apps missing"
    }
    catch {
        Write-Log -Level ERROR -Component APPS-AUDIT -Message "Audit failed: $_"
        return New-ModuleResult -ModuleName 'EssentialAppsAudit' -Status 'Failed' -Errors @($_.ToString())
    }
}

Export-ModuleMember -Function 'Invoke-EssentialAppsAudit'
