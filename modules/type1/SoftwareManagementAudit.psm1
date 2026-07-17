#Requires -Version 7.0
<#
.SYNOPSIS    Software Management Audit - Type 1 (Consolidated Bloatware + Install + Upgrade)
.DESCRIPTION Single software-lifecycle audit. Produces one diff whose items are tagged
             with an Action discriminator:
               Action = 'remove'   bloatware present that should be uninstalled
               Action = 'install'  essential apps missing that should be installed
               Action = 'upgrade'  installed apps with an available newer version
             Consumes baselines: bloatware, essential-apps, app-upgrade.
.NOTES       Module Type: Type1 | DiffKey: SoftwareManagement | Version: 6.0 (Consolidated)
#>

$_corePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'core\Maintenance.psm1'
if (-not (Get-Command 'Write-Log' -ErrorAction SilentlyContinue)) {
    Import-Module $_corePath -Force -Global -WarningAction SilentlyContinue
}

function Invoke-SoftwareManagementAudit {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    Write-Log -Level INFO -Component SOFTWARE-AUDIT -Message 'Starting software management audit (remove + install + upgrade)'

    try {
        $diff = [System.Collections.Generic.List[hashtable]]::new()
        $removeFound = 0
        $installFound = 0
        $upgradeFound = 0

        $osCtx = (Get-Variable -Name 'OSContext' -Scope Global -ValueOnly -ErrorAction SilentlyContinue)
        if (-not $osCtx) { $osCtx = Get-OSContext }

        # ─── BLOATWARE (REMOVE) AUDIT ────────────────────────────────────────
        Write-Log -Level DEBUG -Component SOFTWARE-AUDIT -Message 'Auditing bloatware to remove...'

        $baseline = Get-BaselineList -ModuleFolder 'bloatware' -FileName 'bloatware-list.json'
        if (-not $baseline -or -not $baseline.common) {
            Write-Log -Level WARN -Component SOFTWARE-AUDIT -Message 'Bloatware baseline missing/invalid - skipping remove audit'
        }
        else {
            $allBaseline = [System.Collections.Generic.List[string]]::new()
            $baseline.common | ForEach-Object { $allBaseline.Add($_) }
            if ($osCtx.IsWindows11 -and $baseline.windows11) {
                $baseline.windows11 | ForEach-Object { $allBaseline.Add($_) }
            }
            elseif (-not $osCtx.IsWindows11 -and $baseline.windows10) {
                $baseline.windows10 | ForEach-Object { $allBaseline.Add($_) }
            }
            Write-Log -Level INFO -Component SOFTWARE-AUDIT -Message "Bloatware baseline entries: $($allBaseline.Count) (OS: $($osCtx.DisplayText))"

            # Scan AppX packages (primary bloatware source)
            $appxInstalled = @()
            try {
                $appxInstalled = @(Get-AppxPackageCompat | ForEach-Object { $_.Name } | Where-Object { $_ })
            }
            catch {
                Write-Log -Level WARN -Component SOFTWARE-AUDIT -Message "AppX query failed: $_ - continuing with registry apps only"
            }

            $appxDiff = $allBaseline | Where-Object {
                $b = $_.ToLowerInvariant()
                $appxInstalled | Where-Object { $_.ToLowerInvariant() -eq $b -or $_.ToLowerInvariant().StartsWith($b) }
            } | Select-Object -Unique

            # Registry-installed programs
            $regApps = @(Get-InstalledApp | ForEach-Object { $_.Name } | Where-Object { $_ })
            $regDiff = $allBaseline | Where-Object {
                $b = $_.ToLowerInvariant()
                $regApps | Where-Object { $_.ToLowerInvariant() -like "*$b*" }
            } | Select-Object -Unique

            $combined = @(@($appxDiff) + @($regDiff)) | Select-Object -Unique
            foreach ($name in $combined) {
                $diff.Add(@{
                        Action      = 'remove'
                        Name        = $name
                        PackageName = $name
                    })
                $removeFound++
            }
            Write-Log -Level INFO -Component SOFTWARE-AUDIT -Message "Bloatware to remove: $removeFound"
        }

        # ─── ESSENTIAL APPS (INSTALL) AUDIT ──────────────────────────────────
        Write-Log -Level DEBUG -Component SOFTWARE-AUDIT -Message 'Auditing essential apps to install...'

        $essential = Get-BaselineList -ModuleFolder 'essential-apps' -FileName 'essential-apps.json'
        if (-not $essential) {
            Write-Log -Level WARN -Component SOFTWARE-AUDIT -Message 'Essential apps baseline not found'
        }
        else {
            $baselineApps = @($essential)
            $installed = Get-InstalledApp
            $installedNames = $installed | ForEach-Object { $_.Name.ToLowerInvariant() } | Where-Object { $_ }
            $hasWinget = Test-CommandAvailable 'winget'
            $hasMsOffice = [bool]($installedNames | Where-Object { $_ -match 'microsoft.*(office|word|excel|outlook)' })

            foreach ($app in $baselineApps) {
                $appNameLow = if ($app.name) { $app.name.ToLowerInvariant() } else { continue }

                if ($appNameLow -match 'libreoffice' -and $hasMsOffice) {
                    Write-Log -Level INFO -Component SOFTWARE-AUDIT -Message 'LibreOffice skipped - MS Office detected'
                    continue
                }

                $foundByName = $installedNames | Where-Object { $_ -like "*$appNameLow*" }
                if ($foundByName) { continue }

                $wingetId = $app.winget
                if ($hasWinget -and $wingetId) {
                    $null = & winget list --id $wingetId --exact --accept-source-agreements --disable-interactivity 2>&1
                    if ($LASTEXITCODE -eq 0) { continue }
                }

                $diff.Add(@{
                        Action      = 'install'
                        Name        = $app.name
                        WingetId    = $app.winget ?? ''
                        ChocoId     = $app.choco ?? ''
                        Scope       = $app.scope ?? 'machine'
                        ExcludeOn   = $app.excludeOn ?? @()
                    })
                $installFound++
                Write-Log -Level DEBUG -Component SOFTWARE-AUDIT -Message "  MISSING: $($app.name)"
            }
        }

        # ─── APP UPGRADE AUDIT ───────────────────────────────────────────────
        Write-Log -Level DEBUG -Component SOFTWARE-AUDIT -Message 'Auditing app upgrades...'

        $upgradeCfg = Get-BaselineList -ModuleFolder 'app-upgrade' -FileName 'app-upgrade-config.json'
        if (-not $upgradeCfg -or $upgradeCfg.ModuleEnabled -eq $false) {
            Write-Log -Level INFO -Component SOFTWARE-AUDIT -Message 'App upgrade disabled in config'
        }
        elseif (-not $upgradeCfg.EnabledSources) {
            Write-Log -Level WARN -Component SOFTWARE-AUDIT -Message 'Invalid app upgrade config (missing EnabledSources)'
        }
        else {
            $excludePatterns = if ($upgradeCfg.ExcludePatterns) { $upgradeCfg.ExcludePatterns } else { @() }

            if ((Test-CommandAvailable 'winget') -and $upgradeCfg.EnabledSources -contains 'Winget') {
                Write-Log -Level INFO -Component SOFTWARE-AUDIT -Message 'Querying winget for upgrades...'
                foreach ($item in (Get-WingetUpgrade)) {
                    if (-not $item.Name) { continue }
                    $excluded = $false
                    foreach ($pattern in $excludePatterns) {
                        if ($item.Name -like $pattern -or $item.Id -like $pattern) { $excluded = $true; break }
                    }
                    if ($excluded) { continue }
                    $diff.Add(@{
                            Action           = 'upgrade'
                            Name             = $item.Name
                            Id               = $item.Id
                            CurrentVersion   = $item.CurrentVersion
                            AvailableVersion = $item.AvailableVersion
                            Source           = 'winget'
                        })
                    $upgradeFound++
                }
            }

            if ((Test-CommandAvailable 'choco') -and $upgradeCfg.EnabledSources -contains 'Chocolatey') {
                Write-Log -Level INFO -Component SOFTWARE-AUDIT -Message 'Querying chocolatey for upgrades...'
                try {
                    $chocoOutput = & choco outdated --no-progress --no-color 2>&1 | Where-Object { $_ -is [string] }
                    foreach ($line in $chocoOutput) {
                        if ($line -match '^(\S+)\|(\S+)\|(\S+)') {
                            $pname = $Matches[1]; $curVer = $Matches[2]; $newVer = $Matches[3]
                            $excluded = $false
                            foreach ($pattern in $excludePatterns) {
                                if ($pname -like $pattern) { $excluded = $true; break }
                            }
                            if ($excluded) { continue }
                            $diff.Add(@{
                                    Action           = 'upgrade'
                                    Name             = $pname
                                    Id               = $pname
                                    CurrentVersion   = $curVer
                                    AvailableVersion = $newVer
                                    Source           = 'choco'
                                })
                            $upgradeFound++
                        }
                    }
                }
                catch { Write-Log -Level WARN -Component SOFTWARE-AUDIT -Message "choco outdated failed: $_" }
            }
        }

        Write-Log -Level INFO -Component SOFTWARE-AUDIT -Message "Software items found: $($diff.Count) (Remove: $removeFound, Install: $installFound, Upgrade: $upgradeFound)"

        Save-DiffList -ModuleName 'SoftwareManagement' -DiffList $diff.ToArray()

        $auditPath = Get-TempPath -Category 'data' -FileName 'software-management-audit.json'
        @{
            Timestamp    = (Get-Date -Format 'o')
            TotalItems   = $diff.Count
            RemoveItems  = $removeFound
            InstallItems = $installFound
            UpgradeItems = $upgradeFound
            OS           = $osCtx.DisplayText
        } | ConvertTo-Json -Depth 8 | Set-Content -Path $auditPath -Encoding UTF8 -Force

        return New-ModuleResult -ModuleName 'SoftwareManagementAudit' -Status 'Success' `
            -ItemsDetected $diff.Count `
            -Message "$($diff.Count) software action(s): $removeFound remove, $installFound install, $upgradeFound upgrade"
    }
    catch {
        Write-Log -Level ERROR -Component SOFTWARE-AUDIT -Message "Audit failed: $_"
        return New-ModuleResult -ModuleName 'SoftwareManagementAudit' -Status 'Failed' -Errors @($_.ToString())
    }
}

Export-ModuleMember -Function 'Invoke-SoftwareManagementAudit'
