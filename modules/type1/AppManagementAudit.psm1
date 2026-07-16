#Requires -Version 7.0
<#
.SYNOPSIS    App Management Audit - Type 1 (Consolidated Essential Apps + Upgrade)
.DESCRIPTION Audits app management across install and upgrade scenarios.
             Combines essential apps auditing (find missing apps) with app upgrade
             auditing (find outdated apps available for upgrade).
             Diff = items needing action (missing installs or available upgrades).
.NOTES       Module Type: Type1 | DiffKey: AppManagement | Version: 5.1 (Consolidated)
#>

$_corePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'core\Maintenance.psm1'
if (-not (Get-Command 'Write-Log' -ErrorAction SilentlyContinue)) {
    Import-Module $_corePath -Force -Global -WarningAction SilentlyContinue
}

function Invoke-AppManagementAudit {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    Write-Log -Level INFO -Component APP-MGMT-AUDIT -Message 'Starting app management audit (install + upgrade)'

    try {
        $diff = [System.Collections.Generic.List[hashtable]]::new()
        $installItemsFound = 0
        $upgradeItemsFound = 0

        # ─── ESSENTIAL APPS (INSTALL) AUDIT ──────────────────────────────────
        Write-Log -Level DEBUG -Component APP-MGMT-AUDIT -Message 'Auditing essential apps installation...'

        $baseline = Get-BaselineList -ModuleFolder 'essential-apps' -FileName 'essential-apps.json'
        if (-not $baseline) {
            Write-Log -Level WARN -Component APP-MGMT-AUDIT -Message 'Essential apps baseline not found'
        }
        else {
            $baselineApps = @($baseline)
            Write-Log -Level INFO -Component APP-MGMT-AUDIT -Message "Baseline: $($baselineApps.Count) essential apps"

            # Scan installed software from registry + AppX
            $installed = Get-InstalledApp
            $installedNames = $installed | ForEach-Object { $_.Name.ToLowerInvariant() } | Where-Object { $_ }
            $hasWinget = Test-CommandAvailable 'winget'
            $hasMsOffice = [bool]($installedNames | Where-Object { $_ -match 'microsoft.*(office|word|excel|outlook)' })

            # Build install diff: apps NOT installed
            foreach ($app in $baselineApps) {
                $appNameLow = if ($app.name) { $app.name.ToLowerInvariant() } else { continue }

                # Skip LibreOffice when MS Office is present
                if ($appNameLow -match 'libreoffice' -and $hasMsOffice) {
                    Write-Log -Level INFO -Component APP-MGMT-AUDIT -Message "LibreOffice skipped - MS Office detected"
                    continue
                }

                # Fast check: registry + AppX display name match
                $foundByName = $installedNames | Where-Object { $_ -like "*$appNameLow*" }
                if ($foundByName) {
                    Write-Log -Level DEBUG -Component APP-MGMT-AUDIT -Message "  OK (registry): $($app.name)"
                    continue
                }

                # Definitive check: winget list --id (exact match, covers Win32 + AppX + MSIX)
                $wingetId = $app.winget
                if ($hasWinget -and $wingetId) {
                    $null = & winget list --id $wingetId --exact --accept-source-agreements --disable-interactivity 2>&1
                    if ($LASTEXITCODE -eq 0) {
                        Write-Log -Level DEBUG -Component APP-MGMT-AUDIT -Message "  OK (winget): $($app.name)"
                        continue
                    }
                }

                # Missing - add to diff with AppType='install'
                $app | Add-Member -NotePropertyName 'AppType' -NotePropertyValue 'install' -Force
                $diff.Add($app)
                $installItemsFound++
                Write-Log -Level DEBUG -Component APP-MGMT-AUDIT -Message "  MISSING: $($app.name)"
            }
        }

        # ─── APP UPGRADE AUDIT ────────────────────────────────────────────────
        Write-Log -Level DEBUG -Component APP-MGMT-AUDIT -Message 'Auditing app upgrades...'

        $config = Get-BaselineList -ModuleFolder 'app-upgrade' -FileName 'app-upgrade-config.json'
        if (-not $config -or $config.ModuleEnabled -eq $false) {
            Write-Log -Level INFO -Component APP-MGMT-AUDIT -Message 'App upgrade disabled in config'
        }
        elseif (-not $config.EnabledSources) {
            Write-Log -Level WARN -Component APP-MGMT-AUDIT -Message 'Invalid app upgrade config (missing EnabledSources)'
        }
        else {
            $excludePatterns = if ($config.ExcludePatterns) { $config.ExcludePatterns } else { @() }

            # Winget upgrades
            if ((Test-CommandAvailable 'winget') -and $config.EnabledSources -contains 'Winget') {
                Write-Log -Level INFO -Component APP-MGMT-AUDIT -Message 'Querying winget for upgrades...'
                $wingetItems = Get-WingetUpgrade
                foreach ($item in $wingetItems) {
                    if (-not $item.Name) { continue }
                    $excluded = $false
                    foreach ($pattern in $excludePatterns) {
                        if ($item.Name -like $pattern -or $item.Id -like $pattern) {
                            $excluded = $true; break
                        }
                    }
                    if (-not $excluded) {
                        $upgradeItem = @{
                            AppType          = 'upgrade'
                            Name             = $item.Name
                            Id               = $item.Id
                            CurrentVersion   = $item.CurrentVersion
                            AvailableVersion = $item.AvailableVersion
                            Source           = 'Winget'
                        }
                        $diff.Add($upgradeItem)
                        $upgradeItemsFound++
                        Write-Log -Level DEBUG -Component APP-MGMT-AUDIT -Message "Upgrade available: $($item.Name) $($item.CurrentVersion)->$($item.AvailableVersion)"
                    }
                }
            }

            # Chocolatey upgrades
            if ((Test-CommandAvailable 'choco') -and $config.EnabledSources -contains 'Chocolatey') {
                Write-Log -Level INFO -Component APP-MGMT-AUDIT -Message 'Querying chocolatey for upgrades...'
                try {
                    $chocoOutput = & choco outdated --no-progress --no-color 2>&1 | Where-Object { $_ -is [string] }
                    foreach ($line in $chocoOutput) {
                        if ($line -match '^(\S+)\|(\S+)\|(\S+)') {
                            $pname = $Matches[1]; $curVer = $Matches[2]; $newVer = $Matches[3]
                            $excluded = $false
                            foreach ($pattern in $excludePatterns) {
                                if ($pname -like $pattern) { $excluded = $true; break }
                            }
                            if (-not $excluded) {
                                $upgradeItem = @{
                                    AppType          = 'upgrade'
                                    Name             = $pname
                                    Id               = $pname
                                    CurrentVersion   = $curVer
                                    AvailableVersion = $newVer
                                    Source           = 'Chocolatey'
                                }
                                $diff.Add($upgradeItem)
                                $upgradeItemsFound++
                                Write-Log -Level DEBUG -Component APP-MGMT-AUDIT -Message "Upgrade available: $pname ($curVer->$newVer)"
                            }
                        }
                    }
                }
                catch { Write-Log -Level WARN -Component APP-MGMT-AUDIT -Message "choco outdated failed: $_" }
            }
        }

        Write-Log -Level INFO -Component APP-MGMT-AUDIT -Message "App management items found: $($diff.Count) (Install: $installItemsFound, Upgrade: $upgradeItemsFound)"

        # Save consolidated diff
        Save-DiffList -ModuleName 'AppManagement' -DiffList $diff.ToArray()

        # Persist audit data
        $auditPath = Get-TempPath -Category 'data' -FileName 'app-management-audit.json'
        @{
            Timestamp = (Get-Date -Format 'o')
            TotalItems = $diff.Count
            InstallItems = $installItemsFound
            UpgradeItems = $upgradeItemsFound
        } | ConvertTo-Json -Depth 8 | Set-Content -Path $auditPath -Encoding UTF8 -Force

        return New-ModuleResult -ModuleName 'AppManagementAudit' -Status 'Success' `
            -ItemsDetected $diff.Count `
            -Message "$($diff.Count) app management action(s): $installItemsFound install, $upgradeItemsFound upgrade"
    }
    catch {
        Write-Log -Level ERROR -Component APP-MGMT-AUDIT -Message "Audit failed: $_"
        return New-ModuleResult -ModuleName 'AppManagementAudit' -Status 'Failed' -Errors @($_.ToString())
    }
}

Export-ModuleMember -Function 'Invoke-AppManagementAudit'
