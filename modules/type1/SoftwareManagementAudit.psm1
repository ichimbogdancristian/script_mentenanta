#Requires -Version 7.0
<#
.SYNOPSIS    Software Management Audit - Type 1 (Enhanced Multi-Source Detection)
.DESCRIPTION Enhanced audit with multi-source detection (AppX, Provisioned, WinGet, Registry).
             Uses protected packages and dependency matrix for safety.
             Produces diff tagged with Action discriminator:
               Action = 'remove'   bloatware detected from any source
               Action = 'install'  essential apps missing
               Action = 'upgrade'  installed apps with newer version
.NOTES       Module Type: Type1 | DiffKey: SoftwareManagement | Version: 7.0 (Enhanced Multi-Source)
#>

$_corePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'core\Maintenance.psm1'
if (-not (Get-Command 'Write-Log' -ErrorAction SilentlyContinue)) {
    Import-Module $_corePath -Force -Global -WarningAction SilentlyContinue
}

function Test-CanRemovePackage {
    param([string]$PackageName, $Protected, $Dependencies)

    $lowerName = $PackageName.ToLowerInvariant()

    # The configs are hashtables (Get-BaselineList uses -AsHashtable), so they MUST be walked
    # via .Values / .GetEnumerator(). Iterating .PSObject.Properties on a hashtable yields the
    # CLR members (Count/Keys/Values/...) instead of the package keys, which silently made this
    # entire protection check a no-op (a protected app like Microsoft.WindowsStore was reported
    # removable). The key may itself contain a wildcard (e.g. 'Microsoft.Xbox*'), so use -like
    # with the key AS the pattern.
    if ($Protected -is [System.Collections.IDictionary]) {
        foreach ($section in $Protected.Values) {
            if ($section -isnot [System.Collections.IDictionary]) { continue }
            foreach ($entry in $section.GetEnumerator()) {
                if ($entry.Value.protected -eq $true -and $lowerName -like $entry.Key.ToLowerInvariant()) {
                    Write-Log -Level WARN -Component SOFTWARE-AUDIT `
                        -Message "Package '$PackageName' is protected - will NOT remove"
                    return $false
                }
            }
        }
    }

    # Packages that other packages depend on.
    $depRoot = if ($Dependencies -is [System.Collections.IDictionary]) { $Dependencies['dependencies'] } else { $null }
    if ($depRoot -is [System.Collections.IDictionary]) {
        foreach ($entry in $depRoot.GetEnumerator()) {
            if ($entry.Value.protected -eq $true -and $lowerName -like $entry.Key.ToLowerInvariant()) {
                Write-Log -Level WARN -Component SOFTWARE-AUDIT `
                    -Message "Package '$PackageName' has dependents - will NOT remove"
                return $false
            }
        }
    }

    return $true
}

function Get-BloatwareFromAllSources {
    param([hashtable]$BloatwareConfig, [hashtable]$Protected, [hashtable]$Dependencies)

    $detected = @{}  # hashtable for deduplication

    # Source 1: AppX packages (modern UWP apps)
    Write-Log -Level DEBUG -Component SOFTWARE-AUDIT -Message 'Scanning AppX packages...'
    try {
        $appxPackages = Get-AppxPackageCompat -AllUsers -ErrorAction Stop |
            Select-Object -ExpandProperty Name | Where-Object { $_ }

        foreach ($pattern in $BloatwareConfig.patterns) {
            foreach ($app in $appxPackages) {
                if ($app -like $pattern) {
                    if ((Test-CanRemovePackage -PackageName $app -Protected $Protected -Dependencies $Dependencies)) {
                        $key = $app.ToLowerInvariant()
                        if (-not $detected.ContainsKey($key)) {
                            $detected[$key] = @{
                                Name = $app
                                Sources = @('AppX')
                                Patterns = @($pattern)
                            }
                        }
                    }
                }
            }
        }
        Write-Log -Level DEBUG -Component SOFTWARE-AUDIT -Message "AppX detection found: $($detected.Count)"
    }
    catch {
        Write-Log -Level WARN -Component SOFTWARE-AUDIT -Message "AppX query failed: $_"
    }

    # Source 2: Provisioned packages (pre-installed for new users)
    Write-Log -Level DEBUG -Component SOFTWARE-AUDIT -Message 'Scanning provisioned packages...'
    try {
        $provisionedPackages = Get-AppxProvisionedPackageCompat -ErrorAction Stop |
            Select-Object -ExpandProperty PackageName | Where-Object { $_ }

        foreach ($pattern in $BloatwareConfig.patterns) {
            foreach ($pkg in $provisionedPackages) {
                if ($pkg -like $pattern) {
                    if ((Test-CanRemovePackage -PackageName $pkg -Protected $Protected -Dependencies $Dependencies)) {
                        $key = $pkg.ToLowerInvariant()
                        if ($detected.ContainsKey($key)) {
                            $detected[$key].Sources += 'Provisioned'
                        } else {
                            $detected[$key] = @{
                                Name = $pkg
                                Sources = @('Provisioned')
                                Patterns = @($pattern)
                            }
                        }
                    }
                }
            }
        }
        Write-Log -Level DEBUG -Component SOFTWARE-AUDIT -Message "Provisioned packages found: $(($detected.Count))"
    }
    catch {
        Write-Log -Level WARN -Component SOFTWARE-AUDIT -Message "Provisioned packages query failed: $_"
    }

    # Source 3: Registry (Win32 programs)
    Write-Log -Level DEBUG -Component SOFTWARE-AUDIT -Message 'Scanning registry for Win32 programs...'
    try {
        $regApps = Get-InstalledApp -ErrorAction Stop | Select-Object -ExpandProperty Name | Where-Object { $_ }

        foreach ($pattern in $BloatwareConfig.patterns) {
            foreach ($app in $regApps) {
                if ($app -like $pattern) {
                    if ((Test-CanRemovePackage -PackageName $app -Protected $Protected -Dependencies $Dependencies)) {
                        $key = $app.ToLowerInvariant()
                        if ($detected.ContainsKey($key)) {
                            $detected[$key].Sources += 'Registry'
                        } else {
                            $detected[$key] = @{
                                Name = $app
                                Sources = @('Registry')
                                Patterns = @($pattern)
                            }
                        }
                    }
                }
            }
        }
        Write-Log -Level DEBUG -Component SOFTWARE-AUDIT -Message "Registry programs found: $($detected.Count)"
    }
    catch {
        Write-Log -Level WARN -Component SOFTWARE-AUDIT -Message "Registry query failed: $_"
    }

    # Source 4: WinGet (if available). Parse the fixed-width table into Name/Id columns and match
    # the pattern against those - NEVER against the raw formatted line (the old code stored the
    # whole "Name  Id  Version  Source" line as the package name, producing junk detections that
    # Type2 could not act on). The winget Id is captured so Type2's winget-uninstall fallback works.
    if ((Test-CommandAvailable 'winget')) {
        Write-Log -Level DEBUG -Component SOFTWARE-AUDIT -Message 'Scanning WinGet packages...'
        try {
            $wingetExe = Resolve-WingetPath
            $wingetRaw = & $wingetExe list --accept-source-agreements --disable-interactivity 2>&1 |
                Where-Object { $_ -is [string] }

            $wingetApps = [System.Collections.Generic.List[hashtable]]::new()
            $inTable = $false
            foreach ($line in $wingetRaw) {
                if ($line -match '^-{3,}') { $inTable = $true; continue }
                if (-not $inTable -or $line -match '^\s*$') { continue }
                $cols = $line -split '\s{2,}'
                if ($cols.Count -ge 2 -and $cols[0].Trim()) {
                    $wingetApps.Add(@{ Name = $cols[0].Trim(); Id = $cols[1].Trim() })
                }
            }

            foreach ($pattern in $BloatwareConfig.patterns) {
                foreach ($wa in $wingetApps) {
                    if ($wa.Name -like $pattern -or $wa.Id -like $pattern) {
                        $target = if ($wa.Name) { $wa.Name } else { $wa.Id }
                        if ((Test-CanRemovePackage -PackageName $target -Protected $Protected -Dependencies $Dependencies)) {
                            $key = $target.ToLowerInvariant()
                            if ($detected.ContainsKey($key)) {
                                $detected[$key].Sources += 'WinGet'
                                if (-not $detected[$key].WingetId) { $detected[$key].WingetId = $wa.Id }
                            }
                            else {
                                $detected[$key] = @{
                                    Name     = $target
                                    Sources  = @('WinGet')
                                    Patterns = @($pattern)
                                    WingetId = $wa.Id
                                }
                            }
                        }
                    }
                }
            }
            Write-Log -Level DEBUG -Component SOFTWARE-AUDIT -Message "WinGet packages found: $($detected.Count)"
        }
        catch {
            Write-Log -Level DEBUG -Component SOFTWARE-AUDIT -Message "WinGet query failed (non-critical): $_"
        }
    }

    return $detected.Values
}

function Invoke-SoftwareManagementAudit {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    Write-Log -Level INFO -Component SOFTWARE-AUDIT -Message 'Starting enhanced software management audit (multi-source detection)'

    try {
        $diff = [System.Collections.Generic.List[hashtable]]::new()
        $removeFound = 0
        $installFound = 0
        $upgradeFound = 0

        $osCtx = (Get-Variable -Name 'OSContext' -Scope Global -ValueOnly -ErrorAction SilentlyContinue)
        if (-not $osCtx) { $osCtx = Get-OSContext }

        # ─── BLOATWARE (REMOVE) AUDIT ────────────────────────────────────────
        Write-Log -Level DEBUG -Component SOFTWARE-AUDIT -Message 'Auditing bloatware to remove (multi-source)...'

        # Load configuration files
        $protected = Get-BaselineList -ModuleFolder 'bloatware' -FileName 'protected-packages.json'
        if (-not $protected) {
            Write-Log -Level WARN -Component SOFTWARE-AUDIT -Message 'Protected packages config not found - using minimal safe list'
            $protected = @{
                critical_dependencies = @{
                    'Microsoft.Advertising.Xaml' = @{ protected = $true }
                    'Microsoft.WindowsStore' = @{ protected = $true }
                }
            }
        }

        $dependencies = Get-BaselineList -ModuleFolder 'bloatware' -FileName 'dependency-matrix.json'
        if (-not $dependencies) {
            Write-Log -Level WARN -Component SOFTWARE-AUDIT -Message 'Dependency matrix not found - continuing without dependency checks'
            $dependencies = @{ dependencies = @{} }
        }

        # Load bloatware patterns
        $bloatConfig = Get-BaselineList -ModuleFolder 'bloatware' -FileName 'bloatware-detection.json'
        if (-not $bloatConfig -or -not $bloatConfig.categories) {
            # Fallback to old format
            Write-Log -Level WARN -Component SOFTWARE-AUDIT -Message 'New bloatware detection config not found, using legacy format'
            $legacyBaseline = Get-BaselineList -ModuleFolder 'bloatware' -FileName 'bloatware-list.json'
            if (-not $legacyBaseline -or -not $legacyBaseline.common) {
                Write-Log -Level WARN -Component SOFTWARE-AUDIT -Message 'No bloatware configuration available - skipping remove audit'
            }
            else {
                $allPatterns = [System.Collections.Generic.List[string]]::new()
                $legacyBaseline.common | ForEach-Object { $allPatterns.Add($_) }
                if ($osCtx.IsWindows11 -and $legacyBaseline.windows11) {
                    $legacyBaseline.windows11 | ForEach-Object { $allPatterns.Add($_) }
                }
                elseif (-not $osCtx.IsWindows11 -and $legacyBaseline.windows10) {
                    $legacyBaseline.windows10 | ForEach-Object { $allPatterns.Add($_) }
                }
                $bloatConfig = @{ patterns = $allPatterns }
            }
        }
        else {
            # Extract all patterns from the new config. Walk the categories hashtable via
            # .Values (NOT .PSObject.Properties, which yields CLR members on a hashtable and
            # only produced patterns before by accident through the 'Values' member).
            $patterns = [System.Collections.Generic.List[string]]::new()
            foreach ($category in $bloatConfig.categories.Values) {
                if (-not ($category -is [System.Collections.IDictionary]) -or -not $category.apps) { continue }
                foreach ($app in $category.apps) {
                    if ($app.removable -eq $false) { continue }
                    if ($app.appx_pattern) { $patterns.Add($app.appx_pattern) }
                    elseif ($app.name) { $patterns.Add($app.name) }
                }
            }
            $bloatConfig = @{ patterns = $patterns }
        }

        if ($bloatConfig -and $bloatConfig.patterns) {
            Write-Log -Level INFO -Component SOFTWARE-AUDIT -Message "Bloatware patterns: $($bloatConfig.patterns.Count)"

            $detected = Get-BloatwareFromAllSources -BloatwareConfig $bloatConfig -Protected $protected -Dependencies $dependencies

            foreach ($item in $detected) {
                $diff.Add(@{
                    Action      = 'remove'
                    Name        = $item.Name
                    PackageName = $item.Name
                    Sources     = $item.Sources -join ','
                    WingetId    = ($item.WingetId ?? '')
                })
                $removeFound++
            }
            Write-Log -Level INFO -Component SOFTWARE-AUDIT -Message "Bloatware to remove: $removeFound (from $($detected.Count) detection(s))"
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
                    $null = & (Resolve-WingetPath) list --id $wingetId --exact --accept-source-agreements --disable-interactivity 2>&1
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
