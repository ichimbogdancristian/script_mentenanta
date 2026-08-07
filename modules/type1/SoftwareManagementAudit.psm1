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

<#
.SYNOPSIS
    Silent predicate: is this identifier covered by a protected=true entry in
    protected-packages.json?
.DESCRIPTION
    Split out of Test-CanRemovePackage so the cascade-safety pass can ask the same question
    WITHOUT emitting a WARN per check (it evaluates every declared dependent, so logging
    there would bury the real findings).

    The configs are hashtables (Get-BaselineList uses -AsHashtable), so they MUST be walked
    via .Values / .GetEnumerator(). Iterating .PSObject.Properties on a hashtable yields the
    CLR members (Count/Keys/Values/...) instead of the package keys, which silently made this
    entire protection check a no-op (a protected app like Microsoft.WindowsStore was reported
    removable). The key may itself contain a wildcard (e.g. 'Microsoft.VCLibs.*'), so use
    -like with the key AS the pattern.
.OUTPUTS
    [bool] $true when the identifier is protected.
#>
function Test-PackageProtected {
    [CmdletBinding()]
    [OutputType([bool])]
    param([string]$PackageName, $Protected)

    if (-not $PackageName) { return $false }
    if ($Protected -isnot [System.Collections.IDictionary]) { return $false }

    $lowerName = $PackageName.ToLowerInvariant()
    foreach ($section in $Protected.Values) {
        if ($section -isnot [System.Collections.IDictionary]) { continue }
        foreach ($entry in $section.GetEnumerator()) {
            if ($entry.Value.protected -eq $true -and $lowerName -like $entry.Key.ToLowerInvariant()) {
                return $true
            }
        }
    }
    return $false
}

function Test-CanRemovePackage {
    param([string]$PackageName, $Protected, $Dependencies)

    $lowerName = $PackageName.ToLowerInvariant()

    if (Test-PackageProtected -PackageName $PackageName -Protected $Protected) {
        Write-Log -Level WARN -Component SOFTWARE-AUDIT `
            -Message "Package '$PackageName' is protected - will NOT remove"
        return $false
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

<#
.SYNOPSIS
    Parses winget's fixed-width 'list'/'upgrade' table output into Name/Id rows.
.DESCRIPTION
    winget has no machine-readable output for 'list' (confirmed against current winget CLI
    docs - no --output/-o option exists), so the table has to be parsed. Captures the
    HEADER row's column count (the line right before the '----' divider) and requires each
    data row to split into no more columns than the header declared - catches the case where
    a double-space inside a Name field would otherwise be mistaken for a column boundary and
    shift Id into the wrong slot.
#>
function ConvertFrom-WingetListTable {
    [CmdletBinding()]
    [OutputType([hashtable[]])]
    param([Parameter()] [AllowEmptyCollection()] [string[]]$Lines = @())

    $rows = [System.Collections.Generic.List[hashtable]]::new()
    $inTable = $false
    $headerCols = 0
    $prevLine = $null
    foreach ($line in $Lines) {
        if ($line -match '^-{3,}') {
            $inTable = $true
            if ($prevLine) { $headerCols = @($prevLine -split '\s{2,}').Count }
            continue
        }
        if (-not $inTable) { $prevLine = $line; continue }
        if ($line -match '^\s*$') { continue }
        $cols = @($line -split '\s{2,}')
        if ($cols.Count -ge 2 -and ($headerCols -eq 0 -or $cols.Count -le $headerCols) -and $cols[0].Trim()) {
            $id = $cols[1].Trim()
            # Stem is carried on every row so callers never have to re-derive it. See
            # ConvertFrom-WingetPackageId for why matching needs it as well as Name/Id.
            $rows.Add(@{ Name = $cols[0].Trim(); Id = $id; Stem = (ConvertFrom-WingetPackageId -PackageId $id) })
        }
    }
    # `,` (array-wrap) is REQUIRED - same reason as Get-DiffList in Maintenance.psm1.
    # PowerShell unrolls a single-element array on return, so a one-row table handed the
    # caller a BARE HASHTABLE. `$rows.Count` then reported the hashtable's KEY count (3:
    # Name/Id/Stem) instead of 1. That silently broke Resolve-WingetIdForCandidate, whose
    # success condition is EXACTLY "the query returned one row": the -eq 1 test could never
    # be true, the -gt 1 branch always fired, and every targeted lookup logged a bogus
    # "3 ambiguous match(es)" and returned $null - so Pass B never resolved an Id at all,
    # and Type2's winget-by-exact-Id removal layer never received one.
    return , $rows.ToArray()
}

<#
.SYNOPSIS
    Reduces a winget package Id to the bare package stem that bloatware patterns are
    written against.
.DESCRIPTION
    winget's Id column is NOT the AppX package name - it is source-prefixed, and for
    MSIX/ARP packages it also carries version/architecture/publisher detail. Verified live
    against `winget list` on a real machine:

        Name                   Id
        ----                   --
        AV1 Video Extension    MSIX\Microsoft.AV1VideoExtension_2.0.24.0_x64__8wekyb3d8bbwe
        BabyWare               ARP\Machine\X64\BabyWare
        Angry IP Scanner       angryziber.AngryIPScanner

    bloatware-detection.json writes patterns as AppX short names (`Microsoft.AV1VideoExtension`),
    and the display Name is "AV1 Video Extension". So for the ~100 entries that use an exact
    identifier with no wildcard, NEITHER the Name column nor the raw Id column can ever
    -like-match, which silently made the whole winget source blind to every Microsoft in-box
    app - only wildcard patterns such as `*Netflix*` ever worked there. Normalising the Id to
    its stem recovers exactly the string the patterns target.
.OUTPUTS
    [string] the stem (e.g. 'Microsoft.AV1VideoExtension'), or the input unchanged when it
    carries no recognised prefix/suffix.
#>
function ConvertFrom-WingetPackageId {
    [CmdletBinding()]
    [OutputType([string])]
    param([string]$PackageId)

    if (-not $PackageId) { return $PackageId }

    # Strip the source prefix: MSIX\ , ARP\Machine\X64\ , ARP\User\X86\ , ...
    $stem = $PackageId -replace '^(MSIX|ARP)\\(Machine\\|User\\)?(X64\\|X86\\|ARM64\\)?', ''

    # Strip the _<version>_<arch>__<publisherHash> tail that MSIX ids carry. MSIX package
    # names cannot contain '_' (allowed set is [A-Za-z0-9.-]) and the segment after the first
    # '_' is the version, so splitting at the first '_' that precedes a digit is unambiguous -
    # same rule as Get-AppxNameStem in the Type2 module.
    if ($stem -match '^([A-Za-z0-9.\-]+?)_\d') { $stem = $Matches[1] }

    return $stem
}

<#
.SYNOPSIS
    Resolves an exact, unambiguous winget package Id for a single detected bloatware
    candidate via a targeted 'winget list <query>' - the same lookup a human would run by
    hand (e.g. `winget list maps` -> Windows Maps [MSIX\Microsoft.WindowsMaps_...]).
.DESCRIPTION
    The bulk winget-list scan in Get-BloatwareFromAllSources only correlates a candidate
    with winget when the BLOATWARE PATTERN ITSELF happens to match winget's Name/Id text.
    Most AppX/Provisioned/Registry-only detections never satisfy that, even though winget
    can resolve them fine once queried directly by the candidate's own detected name - this
    closes exactly that gap so Type2's existing WinGet-by-id removal layer has a real Id to
    act on instead of falling back to less reliable layers.

    Deliberately conservative: only returns an Id when the query returns EXACTLY ONE row, so
    an ambiguous/multi-match query (a short or generic name) is left unresolved rather than
    risking an uninstall of the wrong package. A failed or ambiguous lookup is silently
    treated as "not resolved" - this is best-effort enrichment on top of the four existing
    sources, never a hard requirement for the candidate to still be queued for removal.
.OUTPUTS
    [string] the exact winget Id, or $null if no unambiguous match was found.
#>
function Resolve-WingetIdForCandidate {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [string]$WingetExe,
        [Parameter(Mandatory)] [string]$Query
    )

    if (-not $Query) { return $null }
    try {
        $raw = & $WingetExe list $Query --accept-source-agreements --disable-interactivity 2>&1 |
            Where-Object { $_ -is [string] }
        # @() is belt-and-braces: ConvertFrom-WingetListTable now array-wraps its return,
        # but this call site is the one that BREAKS on unrolling (it keys on Count -eq 1),
        # so it does not rely on the callee alone.
        $rows = @(ConvertFrom-WingetListTable -Lines $raw)
        if ($rows.Count -eq 1 -and $rows[0].Id) {
            return $rows[0].Id
        }
        if ($rows.Count -gt 1) {
            Write-Log -Level DEBUG -Component SOFTWARE-AUDIT -Message "winget list '$Query' returned $($rows.Count) ambiguous match(es) - not resolving an Id"
        }
    }
    catch {
        Write-Log -Level DEBUG -Component SOFTWARE-AUDIT -Message "winget list '$Query' failed: $_"
    }
    return $null
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
    $hasWinget = Test-CommandAvailable 'winget'
    $wingetExe = if ($hasWinget) { Resolve-WingetPath } else { $null }
    # Every row of the single bulk `winget list` (Name/Id/Version/Source + a derived Id Stem),
    # hoisted here so the Id-correlation pass after cascade-safety can reuse it instead of
    # re-shelling out. Stays empty when winget is unavailable.
    $wingetApps = @()
    # Flat set of every identifier seen across all four sources this run, used by the
    # cascade-safety pass below to tell "not installed" apart from "installed but not queued
    # for removal" when checking a dependency-matrix entry's declared dependents.
    $allInstalledNames = [System.Collections.Generic.HashSet[string]]::new()

    # $BloatwareConfig.patterns is a list of @{ Pattern; Sources } - see the pattern-extraction
    # block in Invoke-SoftwareManagementAudit. Each entry declares which detection sources it is
    # valid for (bloatware-detection.json's "detection" array), so a pattern only ever runs
    # against the surfaces it was written for. Matching every pattern against every source (the
    # old behaviour, which ignored "detection" entirely) turned AppX-shaped wildcards into
    # registry false positives: '*Plex*' is declared AppX/Provisioned-only but was also tested
    # against registry DisplayName, where it matches any "Duplex ..." scanner/printer utility.
    $allPatterns = @($BloatwareConfig.patterns)
    $appxPatterns = @($allPatterns | Where-Object { $_.Sources -contains 'AppX' })
    $provPatterns = @($allPatterns | Where-Object { $_.Sources -contains 'Provisioned' })
    $regPatterns = @($allPatterns | Where-Object { $_.Sources -contains 'Registry' })
    $wingetPatterns = @($allPatterns | Where-Object { $_.Sources -contains 'WinGet' })
    Write-Log -Level DEBUG -Component SOFTWARE-AUDIT -Message "Patterns per source - AppX: $($appxPatterns.Count), Provisioned: $($provPatterns.Count), Registry: $($regPatterns.Count), WinGet: $($wingetPatterns.Count)"

    # Source 1: AppX packages (modern UWP apps). Matched on the SHORT package Name.
    #
    # PackageFullName is captured here (it was previously discarded) purely so the exact winget
    # Id can be DERIVED without spending a winget invocation: for an MSIX package the winget Id
    # is literally 'MSIX\' + PackageFullName. Verified live against `winget list` - three of
    # three sampled MSIX rows matched Get-AppxPackage's PackageFullName exactly, e.g.
    #     MSIX\Microsoft.AV1VideoExtension_2.0.24.0_x64__8wekyb3d8bbwe
    # That is the precise Id form `winget uninstall <id>` accepts, so Type2 gets a targeted,
    # unambiguous uninstall for every AppX-detected package at zero extra cost - no per-entry
    # `winget list` probing, no table parsing, and nothing that can be truncated or mis-parsed.
    Write-Log -Level DEBUG -Component SOFTWARE-AUDIT -Message 'Scanning AppX packages...'
    try {
        $appxPackages = @(Get-AppxPackageCompat -AllUsers -ErrorAction Stop | Where-Object { $_.Name })
        foreach ($p in $appxPackages) { $null = $allInstalledNames.Add($p.Name.ToLowerInvariant()) }

        foreach ($pat in $appxPatterns) {
            foreach ($appPkg in $appxPackages) {
                $app = $appPkg.Name
                if ($app -like $pat.Pattern) {
                    if ((Test-CanRemovePackage -PackageName $app -Protected $Protected -Dependencies $Dependencies)) {
                        $key = $app.ToLowerInvariant()
                        if (-not $detected.ContainsKey($key)) {
                            $entry = @{
                                Name = $app
                                Sources = @('AppX')
                                Patterns = @($pat.Pattern)
                            }
                            if ($appPkg.PackageFullName) {
                                $entry.WingetId = "MSIX\$($appPkg.PackageFullName)"
                                $entry.PackageFullName = $appPkg.PackageFullName
                            }
                            $detected[$key] = $entry
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

    # Source 2: Provisioned packages (staged for NEW user profiles).
    #
    # Matched and keyed on DisplayName (the short package name, e.g. Microsoft.BingNews), NOT
    # PackageName (the versioned full name, e.g. Microsoft.BingNews_2019.616.2027.0_neutral_~_
    # 8wekyb3d8bbwe). Using PackageName - as this did - broke three things at once:
    #   1. Every bare-identifier pattern (~100 entries that use "name" with no wildcard) could
    #      never match, so those apps were only ever detectable when already installed for a
    #      user, never when merely provisioned.
    #   2. protected-packages.json keys without a trailing wildcard could never match either,
    #      so the ONLY hard block on removal silently did not apply to this source.
    #   3. The dedup key differed from Source 1's short name, so an app found by BOTH sources
    #      was queued TWICE; Type2 removed it on the first item and reported the second as a
    #      failure, degrading a clean run to Warning with a phantom error in the report.
    # Type2 does not need PackageName from the diff - Remove-BloatwareLayered re-queries the
    # live provisioned list and matches on the name stem.
    Write-Log -Level DEBUG -Component SOFTWARE-AUDIT -Message 'Scanning provisioned packages...'
    try {
        $provisioned = @(Get-AppxProvisionedPackageCompat -ErrorAction Stop)
        # Fall back to the stem of PackageName when DisplayName is absent (older DISM output).
        $provNames = @($provisioned | ForEach-Object {
                if ($_.DisplayName) { $_.DisplayName }
                elseif ($_.PackageName -match '^([A-Za-z0-9.\-]+?)_\d') { $Matches[1] }
            } | Where-Object { $_ })
        foreach ($n in $provNames) { $null = $allInstalledNames.Add($n.ToLowerInvariant()) }

        foreach ($pat in $provPatterns) {
            foreach ($pkg in $provNames) {
                if ($pkg -like $pat.Pattern) {
                    if ((Test-CanRemovePackage -PackageName $pkg -Protected $Protected -Dependencies $Dependencies)) {
                        $key = $pkg.ToLowerInvariant()
                        if ($detected.ContainsKey($key)) {
                            if ($detected[$key].Sources -notcontains 'Provisioned') {
                                $detected[$key].Sources += 'Provisioned'
                            }
                        }
                        else {
                            $detected[$key] = @{
                                Name = $pkg
                                Sources = @('Provisioned')
                                Patterns = @($pat.Pattern)
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

        foreach ($pat in $regPatterns) {
            foreach ($app in $regApps) {
                if ($app -like $pat.Pattern) {
                    if ((Test-CanRemovePackage -PackageName $app -Protected $Protected -Dependencies $Dependencies)) {
                        $key = $app.ToLowerInvariant()
                        if ($detected.ContainsKey($key)) {
                            if ($detected[$key].Sources -notcontains 'Registry') {
                                $detected[$key].Sources += 'Registry'
                            }
                        }
                        else {
                            $detected[$key] = @{
                                Name = $app
                                Sources = @('Registry')
                                Patterns = @($pat.Pattern)
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
    #
    # Patterns are tested against the Name, the raw Id AND the Id's normalised STEM. The stem is
    # what makes this source work at all for Microsoft in-box apps: winget reports
    #   Name = 'AV1 Video Extension'   Id = 'MSIX\Microsoft.AV1VideoExtension_2.0.24.0_x64__...'
    # while bloatware-detection.json writes the pattern as 'Microsoft.AV1VideoExtension'. Neither
    # column -like-matches that, so before this every exact-identifier pattern (~100 of the 166
    # entries) was invisible to the winget source and only wildcards like '*Netflix*' ever hit.
    # See ConvertFrom-WingetPackageId for the verified Id shapes.
    if ($hasWinget) {
        Write-Log -Level DEBUG -Component SOFTWARE-AUDIT -Message 'Scanning WinGet packages...'
        try {
            $wingetRaw = & $wingetExe list --accept-source-agreements --disable-interactivity 2>&1 |
                Where-Object { $_ -is [string] }
            $wingetApps = @(ConvertFrom-WingetListTable -Lines $wingetRaw)
            foreach ($wa in $wingetApps) {
                if ($wa.Name) { $null = $allInstalledNames.Add($wa.Name.ToLowerInvariant()) }
                if ($wa.Id) { $null = $allInstalledNames.Add($wa.Id.ToLowerInvariant()) }
                if ($wa.Stem) { $null = $allInstalledNames.Add($wa.Stem.ToLowerInvariant()) }
            }

            foreach ($pat in $wingetPatterns) {
                foreach ($wa in $wingetApps) {
                    if ($wa.Name -like $pat.Pattern -or $wa.Id -like $pat.Pattern -or ($wa.Stem -and $wa.Stem -like $pat.Pattern)) {
                        # Prefer the stem as the identity: it is the AppX/package short name, so
                        # it dedups against Source 1/2/3 keys instead of creating a second entry
                        # under winget's human-readable display Name.
                        $target = if ($wa.Stem) { $wa.Stem } elseif ($wa.Name) { $wa.Name } else { $wa.Id }
                        if ((Test-CanRemovePackage -PackageName $target -Protected $Protected -Dependencies $Dependencies)) {
                            $key = $target.ToLowerInvariant()
                            if ($detected.ContainsKey($key)) {
                                if ($detected[$key].Sources -notcontains 'WinGet') {
                                    $detected[$key].Sources += 'WinGet'
                                }
                                if (-not $detected[$key].WingetId) { $detected[$key].WingetId = $wa.Id }
                            }
                            else {
                                $detected[$key] = @{
                                    Name = $target
                                    Sources = @('WinGet')
                                    Patterns = @($pat.Pattern)
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

                    # A PROTECTED dependent can never be queued for removal, so it is always
                    # "installed but not queued" - which made this rule unsatisfiable and turned
                    # it into a permanent block on the parent. dependency-matrix.json listed the
                    # protected system component Microsoft.XboxGameCallableUI as a dependent of
                    # Microsoft.Xbox*, so EVERY Xbox overlay/Game Bar detection was silently
                    # dropped on every run, forever. A protected dependent is not evidence that
                    # the parent is needed - it is simply a package this tool never touches, so
                    # it cannot inform the parent's fate. Skip it.
                    if (Test-PackageProtected -PackageName $dependent -Protected $Protected) {
                        Write-Log -Level DEBUG -Component SOFTWARE-AUDIT -Message `
                            "Cascade safety: ignoring protected dependent '$dependent' (never removable, so it cannot block '$($detected[$parentKey].Name)')"
                        continue
                    }

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

    # ------------------------------------------------------------------------------------------
    # WinGet Id resolution for every SURVIVING candidate (run after cascade-safety, so no lookup
    # is wasted on an item that just got protected). The goal is the one Type2 actually needs: an
    # exact, unambiguous Id that `winget uninstall <Id>` can act on, e.g.
    #   winget list maps  ->  Windows Maps  MSIX\Microsoft.WindowsMaps_5.1906.1972.0_x64__8wek...
    #
    # Done in two passes, cheapest first:
    #
    #   Pass A - correlate against $wingetApps, the SINGLE bulk `winget list` already run above.
    #            Free (no new process). Matches the candidate's own name against a row's Id stem,
    #            raw Id or display Name, and - for AppX/Provisioned detections - against the
    #            PackageFullName embedded in the row's MSIX Id. This resolves the large majority.
    #
    #   Pass B - only for what Pass A could not place: one targeted `winget list <name>`, the
    #            lookup a human would type. Capped by $maxTargetedLookups because each one is a
    #            process launch (~1-2s); querying all ~166 baseline entries unconditionally would
    #            add minutes to every unattended run for no gain over the bulk table.
    #
    # Deliberately NOT restructured so winget becomes the PRIMARY removal path: winget is
    # officially unsupported under NT AUTHORITY\SYSTEM (MSIX packages register per-user and
    # SYSTEM has no such registration), and SYSTEM is exactly the context of the monthly
    # scheduled task. AppX-via-PS5.1 stays Layer 1-3; the Id resolved here feeds Layer 4.
    # ------------------------------------------------------------------------------------------
    if ($hasWinget) {
        $unresolved = @($detected.Values | Where-Object { -not $_.WingetId })
        if ($unresolved.Count -gt 0 -and $wingetApps.Count -gt 0) {
            foreach ($item in $unresolved) {
                $needle = $item.Name.ToLowerInvariant()
                $fullName = if ($item.PackageFullName) { $item.PackageFullName.ToLowerInvariant() } else { $null }
                $row = $wingetApps | Where-Object {
                    ($_.Stem -and $_.Stem.ToLowerInvariant() -eq $needle) -or
                    ($_.Id -and $_.Id.ToLowerInvariant() -eq $needle) -or
                    ($_.Name -and $_.Name.ToLowerInvariant() -eq $needle) -or
                    ($fullName -and $_.Id -and $_.Id.ToLowerInvariant() -eq "msix\$fullName")
                } | Select-Object -First 1
                if ($row -and $row.Id) {
                    $item.WingetId = $row.Id
                    if ($item.Sources -notcontains 'WinGet(correlated)') { $item.Sources += 'WinGet(correlated)' }
                    Write-Log -Level DEBUG -Component SOFTWARE-AUDIT -Message "  Correlated '$($item.Name)' -> $($row.Id)"
                }
            }
        }

        $toResolve = @($detected.Values | Where-Object { -not $_.WingetId })
        if ($toResolve.Count -gt 0) {
            $maxTargetedLookups = 40
            $lookups = @($toResolve | Select-Object -First $maxTargetedLookups)
            Write-Log -Level DEBUG -Component SOFTWARE-AUDIT -Message `
                "Targeted winget lookup for $($lookups.Count) of $($toResolve.Count) candidate(s) still without an Id..."
            foreach ($item in $lookups) {
                $resolvedId = Resolve-WingetIdForCandidate -WingetExe $wingetExe -Query $item.Name
                if ($resolvedId) {
                    $item.WingetId = $resolvedId
                    $item.Sources += 'WinGet(verified)'
                    Write-Log -Level DEBUG -Component SOFTWARE-AUDIT -Message "  Resolved '$($item.Name)' -> $resolvedId"
                }
            }
        }

        $withId = @($detected.Values | Where-Object { $_.WingetId }).Count
        Write-Log -Level INFO -Component SOFTWARE-AUDIT -Message `
            "WinGet Id resolved for $withId of $($detected.Count) removal candidate(s)"
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
                # The legacy format carries no per-entry source information, so every legacy
                # pattern is valid for all four sources (the pre-existing behaviour).
                $allSources = @('AppX', 'Provisioned', 'Registry', 'WinGet')
                $allPatterns = [System.Collections.Generic.List[hashtable]]::new()
                $legacyBaseline.common | ForEach-Object { $allPatterns.Add(@{ Pattern = $_; Sources = $allSources }) }
                if ($osCtx.IsWindows11 -and $legacyBaseline.windows11) {
                    $legacyBaseline.windows11 | ForEach-Object { $allPatterns.Add(@{ Pattern = $_; Sources = $allSources }) }
                }
                elseif (-not $osCtx.IsWindows11 -and $legacyBaseline.windows10) {
                    $legacyBaseline.windows10 | ForEach-Object { $allPatterns.Add(@{ Pattern = $_; Sources = $allSources }) }
                }
                $bloatConfig = @{ patterns = $allPatterns }
            }
        }
        else {
            # Extract all patterns from the new config. Walk the categories hashtable via
            # .Values (NOT .PSObject.Properties, which yields CLR members on a hashtable and
            # only produced patterns before by accident through the 'Values' member).
            #
            # Each pattern now carries the entry's "detection" array, which the audit HONOURS
            # (Get-BloatwareFromAllSources filters per source). It used to be dropped here and
            # every pattern was tested against all four surfaces - that is what let AppX-shaped
            # wildcards like '*Plex*' hit registry DisplayNames such as "Duplex Scanning
            # Utility". Entries with no "detection" array keep the permissive all-sources
            # behaviour so an incomplete config never silently stops detecting.
            $validSources = @('AppX', 'Provisioned', 'Registry', 'WinGet')
            $patterns = [System.Collections.Generic.List[hashtable]]::new()
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

                    $pattern = if ($app.appx_pattern) { $app.appx_pattern } elseif ($app.name) { $app.name } else { $null }
                    if (-not $pattern) { continue }

                    # Keep only recognised source names so a typo in the config cannot silently
                    # disable a pattern for every source.
                    $declared = @(@($app.detection) | Where-Object { $_ -and $validSources -contains $_ })
                    $sources = if ($declared.Count -gt 0) { $declared } else { $validSources }
                    $patterns.Add(@{ Pattern = $pattern; Sources = $sources })
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

                # TimeoutSeconds carries essential-apps.json's per-app "timeout" through to
                # Type2. It used to be dropped here, so every install fell back to
                # Invoke-ExternalPackageCommand's 600s default - LibreOffice declares 900 and
                # was being killed mid-install at 600 and reported as a failure.
                $diff.Add(@{
                        Action = 'install'
                        Name = $app.name
                        WingetId = $app.winget ?? ''
                        ChocoId = $app.choco ?? ''
                        Scope = $app.scope ?? 'machine'
                        ExcludeOn = $app.excludeOn ?? @()
                        TimeoutSeconds = $app.timeout ?? 0
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
