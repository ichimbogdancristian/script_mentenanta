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
    param(
        [hashtable]$BloatwareConfig,
        [hashtable]$Protected,
        [hashtable]$Dependencies,
        # Pre-scanned registry+AppX inventory (Get-InstalledApp), passed in so the caller's
        # essential-apps sub-audit can reuse the same scan instead of each side rescanning the
        # registry/AppX independently within the same run.
        [object[]]$InstalledApps
    )

    $detected = @{}  # hashtable for deduplication
    # Flat set of every identifier seen across all four sources this run, used by the
    # cascade-safety pass below to tell "not installed" apart from "installed but not queued
    # for removal" when checking a dependency-matrix entry's declared dependents.
    $allInstalledNames = [System.Collections.Generic.HashSet[string]]::new()

    # Source 1: AppX packages (modern UWP apps)
    Write-Log -Level DEBUG -Component SOFTWARE-AUDIT -Message 'Scanning AppX packages...'
    try {
        $appxPackages = Get-AppxPackageCompat -AllUsers -ErrorAction Stop |
            Select-Object -ExpandProperty Name | Where-Object { $_ }
        foreach ($n in $appxPackages) { $null = $allInstalledNames.Add($n.ToLowerInvariant()) }

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
        foreach ($n in $provisionedPackages) { $null = $allInstalledNames.Add($n.ToLowerInvariant()) }

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

    # Source 3: Registry (Win32 programs). Reuses the caller's single Get-InstalledApp scan
    # (passed in as $InstalledApps) rather than rescanning the registry+AppX a second time in
    # the same run.
    Write-Log -Level DEBUG -Component SOFTWARE-AUDIT -Message 'Scanning registry for Win32 programs...'
    try {
        $regApps = @($InstalledApps) | Select-Object -ExpandProperty Name | Where-Object { $_ }
        foreach ($n in $regApps) { $null = $allInstalledNames.Add($n.ToLowerInvariant()) }

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

            # winget has no machine-readable output for 'list' (confirmed against current winget
            # CLI docs - no --output/-o option exists), so the fixed-width table has to be
            # parsed. Capture the header row's column count (the line right before the '----'
            # divider) and require each data row to split into no more columns than the header
            # declared - catches the case where a double-space inside a Name field would
            # otherwise be mistaken for a column boundary and shift Id into the wrong slot.
            $wingetApps = [System.Collections.Generic.List[hashtable]]::new()
            $inTable = $false
            $headerCols = 0
            $prevLine = $null
            foreach ($line in $wingetRaw) {
                if ($line -match '^-{3,}') {
                    $inTable = $true
                    if ($prevLine) { $headerCols = @($prevLine -split '\s{2,}').Count }
                    continue
                }
                if (-not $inTable) { $prevLine = $line; continue }
                if ($line -match '^\s*$') { continue }
                $cols = @($line -split '\s{2,}')
                if ($cols.Count -ge 2 -and ($headerCols -eq 0 -or $cols.Count -le $headerCols) -and $cols[0].Trim()) {
                    $wingetApps.Add(@{ Name = $cols[0].Trim(); Id = $cols[1].Trim() })
                }
            }
            foreach ($wa in $wingetApps) {
                if ($wa.Name) { $null = $allInstalledNames.Add($wa.Name.ToLowerInvariant()) }
                if ($wa.Id) { $null = $allInstalledNames.Add($wa.Id.ToLowerInvariant()) }
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

    # Cascade-safety pass: dependency-matrix.json's "dependents" lists which packages break if
    # their parent is removed. Test-CanRemovePackage already blocked anything with
    # protected=true; this catches the remaining case - a parent that ISN'T individually
    # protected, but has a dependent that IS actually installed on this machine and ISN'T
    # itself queued for removal in this same run. Removing the parent alone would orphan that
    # dependent, so the parent is dropped from $detected (protected for this run, not removed)
    # rather than proceeding - correct behavior for an unattended run, since there's no one to
    # ask and "leave it alone" is always the safe default.
    $depRoot = if ($Dependencies -is [System.Collections.IDictionary]) { $Dependencies['dependencies'] } else { $null }
    if ($depRoot -is [System.Collections.IDictionary]) {
        foreach ($entry in $depRoot.GetEnumerator()) {
            $parentPattern = $entry.Key.ToLowerInvariant()
            $dependents = @($entry.Value.dependents)
            if ($dependents.Count -eq 0) { continue }

            $parentKeys = @($detected.Keys | Where-Object { $_ -like $parentPattern })
            foreach ($parentKey in $parentKeys) {
                foreach ($dependent in $dependents) {
                    $depLower = "$dependent".ToLowerInvariant()
                    $dependentQueued = $detected.Keys | Where-Object { $_ -like $depLower -or $depLower -like $_ }
                    $dependentInstalled = $allInstalledNames | Where-Object { $_ -like $depLower -or $depLower -like $_ }
                    if ($dependentInstalled -and -not $dependentQueued) {
                        Write-Log -Level WARN -Component SOFTWARE-AUDIT -Message `
                            "Cascade safety: keeping '$($detected[$parentKey].Name)' - dependent '$dependent' is installed but not queued for removal this run"
                        $detected.Remove($parentKey)
                        break
                    }
                }
            }
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

        $mainConfig = Get-MainConfig
        $aggressiveOemRemoval = [bool]($mainConfig.modules.softwareManagement.aggressiveOemRemoval -eq $true)

        # Single registry+AppX scan reused by both the bloatware (Source 3) and essential-apps
        # sub-audits below, instead of each independently rescanning the same unchanged system
        # state within this one run.
        $installedApps = Get-InstalledApp

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
            # Legacy v4.0 fallback format (bloatware-list.json), superseded by
            # bloatware-detection.json's categorized v6.0 format. Only reachable here if
            # bloatware-detection.json is missing or corrupt - kept deliberately as a
            # config-corruption safety net so a bad deploy of the primary config file doesn't
            # silently disable bloatware detection entirely on an unattended run.
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
            $broadSkipped = 0
            foreach ($category in $bloatConfig.categories.Values) {
                if (-not ($category -is [System.Collections.IDictionary]) -or -not $category.apps) { continue }
                foreach ($app in $category.apps) {
                    if ($app.removable -eq $false) { continue }
                    # "tier": "broad" marks whole-vendor wildcards that can also match software
                    # the user deliberately installed (e.g. *Razer* also matches Razer Synapse,
                    # the peripheral config app, not just OEM bloat). Only included when the
                    # operator has explicitly opted in via main-config.json.
                    if ($app.tier -eq 'broad' -and -not $aggressiveOemRemoval) { $broadSkipped++; continue }
                    if ($app.appx_pattern) { $patterns.Add($app.appx_pattern) }
                    elseif ($app.name) { $patterns.Add($app.name) }
                }
            }
            if ($broadSkipped -gt 0) {
                Write-Log -Level DEBUG -Component SOFTWARE-AUDIT -Message "Skipped $broadSkipped broad-tier OEM pattern(s) (aggressiveOemRemoval is off)"
            }
            $bloatConfig = @{ patterns = $patterns }
        }

        if ($bloatConfig -and $bloatConfig.patterns) {
            Write-Log -Level INFO -Component SOFTWARE-AUDIT -Message "Bloatware patterns: $($bloatConfig.patterns.Count)"

            $detected = Get-BloatwareFromAllSources -BloatwareConfig $bloatConfig -Protected $protected -Dependencies $dependencies -InstalledApps $installedApps

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
            $installedNames = $installedApps | ForEach-Object { $_.Name.ToLowerInvariant() } | Where-Object { $_ }
            $hasWinget = Test-CommandAvailable 'winget'
            $hasMsOffice = [bool]($installedNames | Where-Object { $_ -match 'microsoft.*(office|word|excel|outlook)' })

            foreach ($app in $baselineApps) {
                $appNameLow = if ($app.name) { $app.name.ToLowerInvariant() } else { continue }

                if ($appNameLow -match 'libreoffice' -and $hasMsOffice) {
                    Write-Log -Level INFO -Component SOFTWARE-AUDIT -Message 'LibreOffice skipped - MS Office detected'
                    continue
                }

                # Precise check first: an exact winget --id match is authoritative when
                # available. Name-substring is only a fallback (winget unavailable, or this app
                # has no winget id) - registry DisplayName often doesn't literally contain the
                # baseline's "name" string (e.g. "Java Runtime Environment" vs. an installed
                # "Java(TM) SE Runtime Environment 8u401"), so trying substring FIRST used to
                # both miss real installs and mask the more precise check below.
                $wingetId = $app.winget
                $alreadyInstalled = $false
                if ($hasWinget -and $wingetId) {
                    $null = & (Resolve-WingetPath) list --id $wingetId --exact --accept-source-agreements --disable-interactivity 2>&1
                    if ($LASTEXITCODE -eq 0) { $alreadyInstalled = $true }
                }
                if (-not $alreadyInstalled) {
                    $foundByName = $installedNames | Where-Object { $_ -like "*$appNameLow*" }
                    if ($foundByName) { $alreadyInstalled = $true }
                }
                if ($alreadyInstalled) { continue }

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
                    # --limit-output forces the pipe-delimited "name|current|available|pinned"
                    # format explicitly, rather than relying on it being the default across
                    # every Chocolatey version/locale.
                    $chocoOutput = & choco outdated --no-progress --no-color --limit-output 2>&1 | Where-Object { $_ -is [string] }
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
