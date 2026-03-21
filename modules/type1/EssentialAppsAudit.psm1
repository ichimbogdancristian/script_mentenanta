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

        # 2. Scan installed software from registry + AppX
        $installed = Get-InstalledApp
        $installedNames = $installed | ForEach-Object { $_.Name.ToLowerInvariant() } | Where-Object { $_ }

        $hasWinget = Test-CommandAvailable 'winget'

        # 3. Detect if Microsoft Office is installed (skip LibreOffice if so)
        $hasMsOffice = [bool]($installedNames | Where-Object { $_ -match 'microsoft.*(office|word|excel|outlook)' })

        # 4. Build diff: apps NOT installed
        $missing = [System.Collections.Generic.List[object]]::new()
        foreach ($app in $baselineApps) {
            $appNameLow = if ($app.name) { $app.name.ToLowerInvariant() } else { continue }

            # Skip LibreOffice when MS Office is present
            if ($appNameLow -match 'libreoffice' -and $hasMsOffice) {
                Write-Log -Level INFO -Component APPS-AUDIT -Message "LibreOffice skipped - MS Office detected"
                continue
            }

            # Fast check: registry + AppX display name match
            $foundByName = $installedNames | Where-Object { $_ -like "*$appNameLow*" }
            if ($foundByName) {
                Write-Log -Level DEBUG -Component APPS-AUDIT -Message "  OK (registry): $($app.name)"
                continue
            }

            # Definitive check: winget list --id (exact match, covers Win32 + AppX + MSIX)
            $wingetId = $app.winget
            if ($hasWinget -and $wingetId) {
                $null = & winget list --id $wingetId --exact --accept-source-agreements --disable-interactivity 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Write-Log -Level DEBUG -Component APPS-AUDIT -Message "  OK (winget): $($app.name)"
                    continue
                }
            }

            $missing.Add($app)
            Write-Log -Level DEBUG -Component APPS-AUDIT -Message "  MISSING: $($app.name)"
        }

        Write-Log -Level INFO -Component APPS-AUDIT -Message "Missing apps: $($missing.Count)"

        # 5. Save diff
        Save-DiffList -ModuleName 'EssentialApps' -DiffList $missing.ToArray()

        # 6. Persist audit data
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
