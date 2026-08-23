#Requires -Version 7.0
<#
.SYNOPSIS    Software Management - Type 2 (Enhanced Layered Removal + Install + Upgrade)
.DESCRIPTION Enhanced software-lifecycle action with layered removal strategy:
             1. Pre-flight checks (verify not protected, verify exists)
             2. Layered removal: AppX → Provisioned → Registry → WinGet
             3. Post-removal validation
             4. Install/Upgrade with fallbacks
.NOTES       Module Type: Type2 | DiffKey: SoftwareManagement | Version: 7.0 (Enhanced Multi-Strategy)
#>

$_corePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'core\Maintenance.psm1'
if (-not (Get-Command 'Write-Log' -ErrorAction SilentlyContinue)) {
    Import-Module $_corePath -Force -Global -WarningAction SilentlyContinue
}

# winget exit codes that mean "this selector did not resolve to exactly one installed
# package" - a MATCHING failure, not an installation failure. Phase 3's fallback ladder
# (--id -> --name -> positional query) continues only on these, because they are the only
# codes for which trying a different match path can produce a different outcome. Any other
# non-zero code means winget resolved the package and the operation itself failed; retrying
# there re-runs the same installer and, on an unattended run, spends the whole per-item
# timeout again for each remaining form.
$script:WingetMatchFailureCodes = @(
    -1978335212,   # NO_APPLICATIONS_FOUND  - nothing matched the selector
    -1978335129    # MULTIPLE_APPLICATIONS_FOUND - ambiguous; winget refuses to guess
)

<#
.SYNOPSIS
    Reduces any package identifier to the bare AppX package Name.
.DESCRIPTION
    The audit emits two different identifier shapes for the same logical package:
      * Source 1 (AppX)        -> the Name only, e.g. Microsoft.XboxGamingOverlay
      * Source 2 (Provisioned) -> the full PackageName, e.g.
                                  Microsoft.XboxGamingOverlay_7.325.11061.0_neutral_~_8wekyb3d8bbwe
    `Get-AppxPackage -Name` filters on the Name property ONLY, so handing it the second
    shape matches nothing - not even wrapped in wildcards, because Name is the SHORTER
    string. That is why provisioned-sourced bloatware was only ever deprovisioned and
    stayed installed for existing users while the module logged "Removal succeeded".

    MSIX package names cannot contain '_' (allowed set is [A-Za-z0-9.-]) and the segment
    after the first '_' is the version, so splitting at the first '_' that precedes a digit
    is unambiguous.
.OUTPUTS
    [string] the Name segment, or the input unchanged when it is already a bare Name.
#>
function Get-AppxNameStem {
    [CmdletBinding()]
    [OutputType([string])]
    param([string]$Identifier)

    if (-not $Identifier) { return $Identifier }
    if ($Identifier -match '^([A-Za-z0-9.\-]+?)_\d') { return $Matches[1] }
    return $Identifier
}

<#
.SYNOPSIS
    Removes one bloatware package using the layered AppX -> Provisioned -> Registry -> WinGet
    strategy, and reports what actually happened.
.OUTPUTS
    [hashtable] Removed (bool), RebootRequired (bool), Attempts (string[]), Verified (bool).
    Verified is $true only when live AppX state confirmed the removal - see the post-removal
    validation block for why it cannot mean anything for a Win32/winget-only package.
#>
<#
.SYNOPSIS
    Layer 1: uninstall the installed AppX package for every user profile.
.DESCRIPTION
    Extracted verbatim from Remove-BloatwareLayered. State is a hashtable - a reference
    type - so Done / AppxFound / Attempts / RebootRequired are mutated in place and stay
    shared across the layers, exactly as the original inline code relied on.

    Done means "stop trying later layers" and may be set ONLY by a layer that verifiably
    UNINSTALLS the package. Deprovisioning must never set it - see Remove-BloatwareLayered.
.OUTPUTS
    None. Results are accumulated into State.
#>
function Invoke-BloatwareLayerAppx {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$NameStem,
        [Parameter(Mandatory)] [hashtable]$State
    )

    # Layer 1: AppX removal for every user profile. -AllUsers is essential: without it the
    # removal only affects the calling profile (SYSTEM under the monthly task), leaving the real
    # user's copy installed. Remove-AppxPackageCompat now VERIFIES and returns a bool, so a
    # failure here falls through to the later layers instead of masking them.
    try {
        # Match on the Name stem - see Get-AppxNameStem for why the raw diff identifier fails.
        $pkg = Get-AppxPackageCompat -Name $NameStem -AllUsers -ErrorAction SilentlyContinue
        if (-not $pkg) {
            $pkg = Get-AppxPackageCompat -Name "*$NameStem*" -AllUsers -ErrorAction SilentlyContinue
        }
        if ($pkg) {
            $State.AppxFound = $true
            $gone = 0
            $left = 0
            foreach ($p in @($pkg)) {
                if (Remove-AppxPackageCompat -PackageFullName $p.PackageFullName -AllUsers) { $gone++ }
                else { $left++ }
            }
            if ($left -eq 0) {
                Write-Log -Level SUCCESS -Component SOFTWARE -Message "    [OK]Layer 1: AppX removal verified ($NameStem, $gone package(s))"
                $State.Attempts += 'AppX'
                $State.Done = $true
            }
            else {
                Write-Log -Level WARN -Component SOFTWARE `
                    -Message "    Layer 1: AppX removal did NOT take effect for $left of $($gone + $left) package(s) ($NameStem) - continuing to later layers"
                $State.Attempts += 'AppX(failed)'
            }
        }
        else {
            Write-Log -Level DEBUG -Component SOFTWARE -Message "    Layer 1: no installed AppX package matching '$NameStem'"
        }
    }
    catch {
        Write-Log -Level DEBUG -Component SOFTWARE -Message "    Layer 1 (AppX) skipped: $_"
    }
}

<#
.SYNOPSIS
    Layer 2: deprovision so the app does not return for NEW user profiles.
.DESCRIPTION
    Extracted verbatim from Remove-BloatwareLayered. State is a hashtable - a reference
    type - so Done / AppxFound / Attempts / RebootRequired are mutated in place and stay
    shared across the layers, exactly as the original inline code relied on.

    Done means "stop trying later layers" and may be set ONLY by a layer that verifiably
    UNINSTALLS the package. Deprovisioning must never set it - see Remove-BloatwareLayered.
.OUTPUTS
    None. Results are accumulated into State.
#>
function Invoke-BloatwareLayerProvisioned {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$NameStem,
        [Parameter(Mandatory)] [hashtable]$State
    )

    # Layer 2: Provisioned package removal (stops it coming back for NEW user profiles).
    # NOTE: deprovisioning does NOT uninstall the package for existing users - that is
    # Layer 1's job. Reporting overall success off this layer alone is what made the module
    # claim Xbox apps were removed while `winget list` still showed them installed.
    try {
        $prov = @(Get-AppxProvisionedPackageCompat -ErrorAction SilentlyContinue |
            Where-Object { $_.PackageName -like "*$NameStem*" })
        if ($prov.Count -gt 0) {
            $deprovisioned = 0
            foreach ($p in $prov) {
                # The wrapper now verifies against the live provisioned list and returns the
                # real outcome (it used to hard-code $true).
                if (Remove-AppxProvisionedPackageCompat -PackageName $p.PackageName) { $deprovisioned++ }
                else { Write-Log -Level WARN -Component SOFTWARE -Message "    Layer 2: deprovision FAILED for $($p.PackageName)" }
            }
            if ($deprovisioned -gt 0) {
                Write-Log -Level SUCCESS -Component SOFTWARE -Message "    [OK]Layer 2: Deprovisioned $deprovisioned package(s)"
                $State.Attempts += 'Provisioned'
                # Deliberately does NOT set $State.Done: deprovisioning only stops the app returning
                # for NEW profiles, it does not uninstall it for existing users. Treating it as
                # "removed" is what suppressed Layers 3/4/5.
            }
        }
        else {
            Write-Log -Level DEBUG -Component SOFTWARE -Message "    Layer 2: no provisioned package matching '$NameStem'"
        }
    }
    catch {
        Write-Log -Level DEBUG -Component SOFTWARE -Message "    Layer 2 (Provisioned) skipped: $_"
    }
}

<#
.SYNOPSIS
    Layer 3: registry (Win32) SILENT uninstall only.
.DESCRIPTION
    Extracted verbatim from Remove-BloatwareLayered. State is a hashtable - a reference
    type - so Done / AppxFound / Attempts / RebootRequired are mutated in place and stay
    shared across the layers, exactly as the original inline code relied on.

    Done means "stop trying later layers" and may be set ONLY by a layer that verifiably
    UNINSTALLS the package. Deprovisioning must never set it - see Remove-BloatwareLayered.
.OUTPUTS
    None. Results are accumulated into State.
#>
function Invoke-BloatwareLayerRegistry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$NameStem,
        [Parameter(Mandatory)] [hashtable]$State
        ,[Parameter()] [string]$PackageName
    )

    # Layer 3: Registry (Win32) uninstall - ONLY if no earlier layer has verifiably uninstalled it,
    # and ONLY when the uninstaller can be run SILENTLY. An interactive UninstallString
    # (e.g. a setup EXE, or MSI without /qn) would hang an unattended run forever. The old code
    # ran unconditionally, matched a broad DisplayName wildcard (could hit an unrelated program),
    # launched a possibly-interactive uninstaller, and leaked '-ErrorAction Continue' to cmd.exe.
    if (-not $State.Done) {
        try {
            $regPaths = @(
                'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
                'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
                'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
            )
            $regItem = @(foreach ($path in $regPaths) {
                    Get-ChildItem $path -ErrorAction SilentlyContinue |
                        Where-Object { $_.GetValue('DisplayName') -like "*$PackageName*" }
                }) | Select-Object -First 1

            if ($regItem) {
                $quiet = $regItem.GetValue('QuietUninstallString')
                $normal = $regItem.GetValue('UninstallString')
                $proc = $null
                try {
                    if ($quiet) {
                        # Vendor-provided silent command line - run it as-is via the shell.
                        $proc = Start-Process -FilePath $env:ComSpec -ArgumentList '/c', $quiet `
                            -Wait -PassThru -WindowStyle Hidden -ErrorAction Stop
                    }
                    elseif ($normal -match '\{[0-9A-Fa-f\-]{36}\}') {
                        # MSI product code - force a silent, non-restarting uninstall.
                        $guid = $Matches[0]
                        $proc = Start-Process -FilePath 'msiexec.exe' -ArgumentList "/x$guid", '/qn', '/norestart' `
                            -Wait -PassThru -WindowStyle Hidden -ErrorAction Stop
                    }
                    else {
                        Write-Log -Level DEBUG -Component SOFTWARE -Message "    Layer 3: no silent uninstall for '$PackageName' - skipping (would hang unattended)"
                    }

                    if ($proc -and $proc.ExitCode -in 0, 1605, 3010) {   # 1605 = not installed; 3010 = reboot required
                        Write-Log -Level SUCCESS -Component SOFTWARE -Message "    Layer 3: Registry uninstall (exit $($proc.ExitCode))"
                        $State.Attempts += 'Registry'
                        $State.Done = $true
                        # 3010 = ERROR_SUCCESS_REBOOT_REQUIRED. The uninstall succeeded but is
                        # only fully applied after a restart, so this has to surface in the
                        # module result - Stage 5 skips the reboot entirely when
                        # rebootOnlyWhenRequired is set and nothing flagged RebootRequired.
                        if ($proc.ExitCode -eq 3010) {
                            Write-Log -Level INFO -Component SOFTWARE -Message "    Layer 3: uninstaller requests a reboot to finish"
                            $State.RebootRequired = $true
                        }
                    }
                    elseif ($proc) {
                        Write-Log -Level DEBUG -Component SOFTWARE -Message "    Layer 3: uninstaller exit $($proc.ExitCode)"
                    }
                }
                catch {
                    Write-Log -Level DEBUG -Component SOFTWARE -Message "    Layer 3 (Registry) failed: $_"
                }
            }
        }
        catch {
            Write-Log -Level DEBUG -Component SOFTWARE -Message "    Layer 3 (Registry) skipped: $_"
        }
    }
}

<#
.SYNOPSIS
    Layer 4: winget uninstall by the exact Id the audit resolved.
.DESCRIPTION
    Extracted verbatim from Remove-BloatwareLayered. State is a hashtable - a reference
    type - so Done / AppxFound / Attempts / RebootRequired are mutated in place and stay
    shared across the layers, exactly as the original inline code relied on.

    Done means "stop trying later layers" and may be set ONLY by a layer that verifiably
    UNINSTALLS the package. Deprovisioning must never set it - see Remove-BloatwareLayered.
.OUTPUTS
    None. Results are accumulated into State.
#>
function Invoke-BloatwareLayerWingetById {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$NameStem,
        [Parameter(Mandatory)] [hashtable]$State
        ,[Parameter()] [string]$WingetId
        ,[Parameter()] [bool]$HasWinget
    )

    # Layer 4: WinGet removal by the exact Id the audit resolved. Routed through
    # Invoke-ExternalPackageCommand (timeout-guarded, kills a hung process tree) rather than a
    # bare '&' call - this must never be able to hang an unattended run.
    #
    # Two forms are tried, in this order, because they are NOT interchangeable:
    #   1. positional query  ->  winget uninstall MSIX\Microsoft.WindowsMaps_5.1906....
    #      The audit's Id is globally unique (it came straight out of `winget list`), so the
    #      positional query resolves to exactly one package. This is the form verified by hand to
    #      actually uninstall a source-prefixed MSIX package.
    #   2. --id --exact      ->  winget uninstall --id <Id> --exact
    #      Kept as a second attempt for plain 'Publisher.Package' ARP ids, where --id is the
    #      documented selector. --exact is mandatory here: without it winget substring-matches and
    #      can bail with -1978335129 (multiple matches) instead of removing anything.
    if (-not $State.Done -and $WingetId -and $HasWinget) {
        $wingetCommon = @('--silent', '--accept-source-agreements', '--disable-interactivity')
        $wingetForms = @(
            @{ Label = 'exact id'; Args = @('uninstall', $WingetId) + $wingetCommon }
            @{ Label = '--id --exact'; Args = @('uninstall', '--id', $WingetId, '--exact') + $wingetCommon }
        )
        foreach ($form in $wingetForms) {
            if ($State.Done) { break }
            try {
                $exitCode = Invoke-ExternalPackageCommand -FilePath (Resolve-WingetPath) -ArgumentList $form.Args
                if ($exitCode -eq 0) {
                    Write-Log -Level SUCCESS -Component SOFTWARE -Message "    [OK]Layer 4: WinGet uninstall ($($form.Label)) succeeded: $WingetId"
                    $State.Attempts += 'WinGet'
                    $State.Done = $true
                }
                else {
                    Write-Log -Level DEBUG -Component SOFTWARE -Message "    Layer 4 (WinGet $($form.Label)) exit $exitCode for '$WingetId'"
                }
            }
            catch {
                Write-Log -Level DEBUG -Component SOFTWARE -Message "    Layer 4 (WinGet $($form.Label)) failed: $_"
            }
        }
    }
}

<#
.SYNOPSIS
    Layer 5: winget uninstall by name - last resort.
.DESCRIPTION
    Extracted verbatim from Remove-BloatwareLayered. State is a hashtable - a reference
    type - so Done / AppxFound / Attempts / RebootRequired are mutated in place and stay
    shared across the layers, exactly as the original inline code relied on.

    Done means "stop trying later layers" and may be set ONLY by a layer that verifiably
    UNINSTALLS the package. Deprovisioning must never set it - see Remove-BloatwareLayered.
.OUTPUTS
    None. Results are accumulated into State.
#>
function Invoke-BloatwareLayerWingetByName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$NameStem,
        [Parameter(Mandatory)] [hashtable]$State
        ,[Parameter()] [string]$PackageName
        ,[Parameter()] [bool]$HasWinget
    )

    # Layer 5: WinGet removal by name - the last resort. Reached either when the audit resolved no
    # WingetId (a package known only via the Registry source) or when Layer 4 had an Id but both
    # of its forms failed. Layer 4 always runs first when an Id exists, so the precise form is
    # still preferred; this only ever adds an attempt that would otherwise not have happened.
    # No --exact here on purpose: $PackageName is the package STEM (Microsoft.WindowsMaps), not
    # winget's display Name ("Windows Maps"), so an exact match would never bind. winget refuses
    # to act on an ambiguous query (-1978335129) rather than picking one, so the substring form
    # cannot silently uninstall a different package.
    if (-not $State.Done -and $HasWinget -and $PackageName) {
        try {
            $exitCode = Invoke-ExternalPackageCommand -FilePath (Resolve-WingetPath) `
                -ArgumentList @('uninstall', '--name', $PackageName, '--silent', '--accept-source-agreements', '--disable-interactivity')
            if ($exitCode -eq 0) {
                Write-Log -Level SUCCESS -Component SOFTWARE -Message "    [OK]Layer 5: WinGet uninstall (by name) succeeded"
                $State.Attempts += 'WinGet-byname'
                $State.Done = $true
            }
            else {
                Write-Log -Level DEBUG -Component SOFTWARE -Message "    Layer 5 (WinGet by name) exit $exitCode - no match or already absent"
            }
        }
        catch {
            Write-Log -Level DEBUG -Component SOFTWARE -Message "    Layer 5 (WinGet by name) failed: $_"
        }
    }
}

function Remove-BloatwareLayered {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [string]$PackageName,
        [string]$WingetId,
        [switch]$HasWinget
    )

    # $done means "stop trying later layers" and is set ONLY by a layer that actually uninstalls
    # the package for existing users - never by deprovisioning. Keeping these separate is the
    # whole point: an in-box app is normally installed AND provisioned, so when Layer 1's removal
    # silently failed but Layer 2's deprovision succeeded, the old single $removed flag went
    # $true and Layers 3/4/5 were all skipped. The winget-by-exact-Id removal (which does work on
    # these packages) therefore never ran, and the post-removal check at the bottom correctly
    # reported failure for a package the module had never really tried to uninstall.
    $done = $false
    $appxFound = $false
    $rebootRequired = $false
    $attempts = @()

    Write-Log -Level INFO -Component SOFTWARE -Message "  Attempting layered removal of: $PackageName"

    # Both the installed copy AND the provisioning must go: Layer 1 uninstalls it for existing
    # users, Layer 2 stops it returning for new ones. They are NOT alternatives, so neither is
    # gated on the other's result.
    $nameStem = Get-AppxNameStem -Identifier $PackageName

    $state = @{ Done = $false; AppxFound = $false; RebootRequired = $false; Attempts = @() }

    Invoke-BloatwareLayerAppx        -NameStem $nameStem -State $state
    Invoke-BloatwareLayerProvisioned -NameStem $nameStem -State $state
    Invoke-BloatwareLayerRegistry    -NameStem $nameStem -State $state -PackageName $PackageName
    Invoke-BloatwareLayerWingetById  -NameStem $nameStem -State $state -WingetId $WingetId -HasWinget:([bool]$HasWinget)
    Invoke-BloatwareLayerWingetByName -NameStem $nameStem -State $state -PackageName $PackageName -HasWinget:([bool]$HasWinget)

    $done = $state.Done; $appxFound = $state.AppxFound
    $rebootRequired = $state.RebootRequired; $attempts = $state.Attempts

    # ── Post-removal validation ──────────────────────────────────────────────────
    # Confirm against live system state instead of trusting the layers' own reports. A
    # package that is merely DEPROVISIONED is still installed for every existing user, so
    # it has not actually been removed - saying otherwise is how this module reported five
    # Xbox apps as removed while they were all still listed by `winget list`.
    #
    # This check is only MEANINGFUL for AppX-shaped packages. Get-AppxPackageCompat returns
    # nothing for a Win32/registry program or a winget-Name-keyed entry whether or not the
    # removal worked, so treating "no AppX package found" as proof would print "Removal
    # verified" for every such package unconditionally. Only claim verification when an
    # AppX/Provisioned layer was actually involved; otherwise report the uninstaller's own
    # result honestly as unverified.
    # Verification is keyed on $appxFound - whether Layer 1 actually saw an installed AppX package
    # - NOT on which layer claimed the removal. That matters now that winget (Layer 4/5) is
    # reachable for AppX packages: a winget uninstall of an MSIX package IS checkable against the
    # live AppX list, and the old '$attempts contains AppX/Provisioned' condition skipped exactly
    # that case, reporting an unverified success for the one path most likely to be doing the work.
    # For a genuine Win32/registry program Get-AppxPackageCompat returns nothing whether or not
    # the uninstall worked, so those still report the uninstaller's own exit code honestly rather
    # than claiming verification.
    $verified = $false
    if ($done) {
        if ($appxFound) {
            $stillInstalled = $null
            try {
                # Mirror Layer 1's two-step lookup exactly. Querying only the exact stem here
                # while Layer 1 may have matched via the '*stem*' wildcard would report "verified"
                # for a wildcard-matched package that is still installed.
                $stillInstalled = @(Get-AppxPackageCompat -Name $nameStem -AllUsers -ErrorAction SilentlyContinue)
                if (-not $stillInstalled -or $stillInstalled.Count -eq 0) {
                    $stillInstalled = @(Get-AppxPackageCompat -Name "*$nameStem*" -AllUsers -ErrorAction SilentlyContinue)
                }
            }
            catch {
                Write-Log -Level DEBUG -Component SOFTWARE -Message "    Post-removal check failed: $_"
            }

            if ($stillInstalled -and $stillInstalled.Count -gt 0) {
                $done = $false
                Write-Log -Level WARN -Component SOFTWARE `
                    -Message "  Still installed after $($attempts -join ' -> '): $nameStem"
            }
            else {
                $verified = $true
                Write-Log -Level SUCCESS -Component SOFTWARE -Message "  Removal verified via: $($attempts -join ' -> ')"
            }
        }
        else {
            Write-Log -Level SUCCESS -Component SOFTWARE `
                -Message "  Removal reported by: $($attempts -join ' -> ') (uninstaller exit code; not AppX-verifiable for this package type)"
        }
    }

    # Deprovisioning is real progress worth reporting even when the app is still installed for
    # existing users - it stops the app returning on new profiles - but it is NOT removal, so it
    # does not make $done true and the caller still counts this item as failed.
    $deprovisionedOnly = (-not $done) -and ($attempts -contains 'Provisioned')
    if ($deprovisionedOnly) {
        Write-Log -Level WARN -Component SOFTWARE `
            -Message "  Deprovisioned only - still installed for existing users: $nameStem"
    }

    if (-not $done -and $attempts.Count -eq 0) {
        # NOTE: 'default' is not a PowerShell command - the old '| default ''none''' threw inside
        # the string interpolation on every not-found package, turning a clean WARN into an ERROR.
        Write-Log -Level WARN -Component SOFTWARE -Message "  Not found (attempted: none)"
    }

    return @{
        Removed = $done
        Deprovisioned = ($attempts -contains 'Provisioned')
        RebootRequired = $rebootRequired
        Attempts = $attempts
        Verified = $verified
    }
}

function Invoke-SoftwareManagement {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter()][hashtable]$OSContext
    )

    Write-Log -Level INFO -Component SOFTWARE -Message 'Starting enhanced software management (layered removal + install + upgrade)'

    $diff = Get-DiffList -ModuleName 'SoftwareManagement'
    if (-not $diff -or $diff.Count -eq 0) {
        Write-Log -Level INFO -Component SOFTWARE -Message 'No software actions needed'
        return New-ModuleResult -ModuleName 'SoftwareManagement' -Status 'Skipped' -ModuleType 'Type2' -Message 'Software already in desired state'
    }

    $osCtx = if ($OSContext) { $OSContext } elseif ($global:OSContext) { $global:OSContext } else { Get-OSContext }
    $hasWinget = Test-CommandAvailable 'winget'
    $hasChoco = Test-CommandAvailable 'choco'
    $processed = 0
    $failed = 0
    $skipped = 0
    $errors = @()
    $rebootRequired = $false

    # Deterministic phase ordering: remove junk, then install wanted, then upgrade.
    $removeItems = @($diff | Where-Object { $_.Action -eq 'remove' })
    $installItems = @($diff | Where-Object { $_.Action -eq 'install' })
    $upgradeItems = @($diff | Where-Object { $_.Action -eq 'upgrade' })

    Write-Log -Level INFO -Component SOFTWARE -Message "Processing $($diff.Count) item(s): $($removeItems.Count) remove, $($installItems.Count) install, $($upgradeItems.Count) upgrade"

    if ($hasWinget) {
        Write-Log -Level INFO -Component SOFTWARE -Message 'Updating winget sources'
        try {
            $sourceUpdateCode = Invoke-ExternalPackageCommand -FilePath (Resolve-WingetPath) -ArgumentList @('source', 'update', '--disable-interactivity')
            if ($sourceUpdateCode -ne 0) {
                Write-Log -Level WARN -Component SOFTWARE -Message "winget source update returned exit code $sourceUpdateCode (continuing anyway)"
            }
        }
        catch {
            Write-Log -Level WARN -Component SOFTWARE -Message "Exception updating winget sources: $_. Continuing with actions..."
        }
    }

    # ─── PHASE 1: REMOVE (Layered Strategy) ──────────────────────────────────
    foreach ($item in $removeItems) {
        $name = $item.Name ?? $item.PackageName ?? "$item"
        $pkgName = $item.PackageName ?? $item.Name ?? ''
        $wingetId = $item.WingetId ?? ''
        try {
            $outcome = Remove-BloatwareLayered -PackageName $pkgName -WingetId $wingetId -HasWinget:$hasWinget
            if ($outcome.RebootRequired) { $rebootRequired = $true }

            if ($outcome.Removed) {
                $processed++
            }
            else {
                $detail = if ($outcome.Deprovisioned) { ' (deprovisioned only - still installed for existing users)' } else { '' }
                $tried = if ($outcome.Attempts.Count -gt 0) { " [tried: $($outcome.Attempts -join ' -> ')]" } else { '' }
                Write-Log -Level WARN -Component SOFTWARE -Message "Could not remove: $name$detail$tried"
                $failed++
                $errors += "Removal failed: $name$detail"
            }
        }
        catch {
            Write-Log -Level ERROR -Component SOFTWARE -Message "Remove error [$name]: $_"
            $errors += "[remove:$name] $_"
            $failed++
        }
    }

    # ─── PHASE 2: INSTALL ────────────────────────────────────────────────────
    foreach ($item in $installItems) {
        $name = $item.Name ?? "$item"
        $wingetId = $item.WingetId ?? ''
        $chocoId = $item.ChocoId ?? ''
        $scope = $item.Scope ?? 'machine'
        try {
            $excl = $item.ExcludeOn ?? @()
            if ($osCtx.IsWindows11 -and $excl -contains 'windows11') {
                Write-Log -Level DEBUG -Component SOFTWARE -Message "Skipping install (Win11 excluded): $name"
                continue
            }
            if (-not $osCtx.IsWindows11 -and $excl -contains 'windows10') {
                Write-Log -Level DEBUG -Component SOFTWARE -Message "Skipping install (Win10 excluded): $name"
                continue
            }

            # Honour essential-apps.json's per-app "timeout" (threaded through the diff as
            # TimeoutSeconds). Without it every install used Invoke-ExternalPackageCommand's
            # 600s default, so LibreOffice - which declares 900 precisely because it is a slow
            # install - had its process tree killed at 600s and was reported as a failure.
            $timeoutArgs = @{}
            $declaredTimeout = [int]($item.TimeoutSeconds ?? 0)
            if ($declaredTimeout -gt 0) { $timeoutArgs['TimeoutSeconds'] = $declaredTimeout }

            $installed = $false
            if ($wingetId -and $hasWinget) {
                $scopeArgs = if ($scope -eq 'user') { @('--scope', 'user') } else { @('--scope', 'machine') }
                $wingetArgs = @('install', '--id', $wingetId, '--source', 'winget', '--silent',
                    '--disable-interactivity', '--accept-package-agreements', '--accept-source-agreements') + $scopeArgs
                $exitCode = Invoke-ExternalPackageCommand -FilePath (Resolve-WingetPath) -ArgumentList $wingetArgs @timeoutArgs
                if ($exitCode -in 0, -1978335135, -1978335189) {
                    Write-Log -Level SUCCESS -Component SOFTWARE -Message "Installed (winget): $name"
                    $installed = $true
                }
                # -1978335215 = INSTALLER_HASH_MISMATCH. The manifest's SHA256 no longer matches
                # the bytes at the vendor's download URL. This is an UPSTREAM problem, not a
                # machine problem: vendors that republish each new build at a STABLE url age the
                # community manifest out on every release (Google.Chrome does exactly this, at
                # …/googlechromestandaloneenterprise64.msi). It is called out separately because
                # it is not retryable here - '--ignore-security-hash' is refused for elevated
                # processes, and this project is ALWAYS elevated (SYSTEM under the monthly task),
                # so winget has no path to success until the manifest is refreshed upstream.
                # The chocolatey fallback below is the only remaining option.
                elseif ($exitCode -eq -1978335215) {
                    Write-Log -Level WARN -Component SOFTWARE -Message "winget installer hash mismatch for $name - stale upstream manifest; not overridable while elevated"
                }
                else {
                    Write-Log -Level WARN -Component SOFTWARE -Message "winget exit $exitCode for $name"
                }
            }

            if (-not $installed -and $chocoId -and $hasChoco) {
                Write-Log -Level INFO -Component SOFTWARE -Message "Falling back to chocolatey for ${name}: choco install $chocoId"
                $exitCode = Invoke-ExternalPackageCommand -FilePath 'choco' -ArgumentList @('install', $chocoId, '--yes', '--no-progress') @timeoutArgs
                if ($exitCode -eq 0) {
                    Write-Log -Level SUCCESS -Component SOFTWARE -Message "Installed (choco): $name"
                    $installed = $true
                }
                else {
                    Write-Log -Level WARN -Component SOFTWARE -Message "choco exit $exitCode for $name"
                }
            }
            elseif (-not $installed) {
                # State WHY no fallback ran. Without this the log is identical whether a fallback
                # was attempted and failed, was never configured, or was skipped because choco
                # was not found - which is exactly the ambiguity that hid the Chrome failure.
                $why = if (-not $chocoId) { 'no "choco" id in essential-apps.json' }
                elseif (-not $hasChoco) { 'chocolatey not available on this machine' }
                else { 'unknown' }
                Write-Log -Level WARN -Component SOFTWARE -Message "No chocolatey fallback for ${name}: $why"
            }

            if ($installed) {
                $processed++
            }
            else {
                Write-Log -Level WARN -Component SOFTWARE -Message "Could not install: $name"
                $errors += "No installer available: $name"
                $failed++
            }
        }
        catch {
            Write-Log -Level ERROR -Component SOFTWARE -Message "Install failed [$name]: $_"
            $errors += "[install:$name] $_"
            $failed++
        }
    }

    # ─── PHASE 3: UPGRADE ────────────────────────────────────────────────────
    # Two mechanisms, in order of reliability.
    #
    # WHY THE BULK PATH EXISTS AND COMES FIRST. The per-package ladder further down re-selects
    # each package by Id or Name, which means it depends on identifiers recovered from winget's
    # RENDERED TABLE. That table is width-fitted: a long Id comes back truncated with an
    # ellipsis, and a row whose columns collapse into fewer fields is rejected by the parser
    # outright. Neither is repairable downstream - a truncated Id cannot be handed back to
    # `winget upgrade --id`, and a dropped row was never queued in the first place.
    #
    # `winget upgrade --all` never leaves winget. It upgrades the package objects winget
    # already resolved internally, so no identifier is ever serialised through text and none of
    # the above can happen. That is precisely why running it by hand upgrades everything on a
    # machine where this module reported nothing to do.
    #
    # It cannot exempt a package, so it runs only when the audit confirmed that nothing
    # upgradable matched ExcludePatterns (BulkUpgradeEligible on every winget item). Its result
    # is VERIFIED by re-enumerating rather than trusted, and anything still listed afterwards
    # falls through to the per-package ladder.
    #
    # Outcome classification for both paths:
    #   processed - something actually upgraded it
    #   skipped   - nothing that ran ever matched the package (the package manager that
    #               reported it genuinely cannot act on it), which is not a failure of this run
    #   failed    - an attempt bound to the package and the operation errored

    # Keys of packages the bulk pass already upgraded. A key, not an object reference: the diff
    # items come back from JSON as OrderedHashtable and any cast would break reference identity.
    $bulkDone = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    $wingetUpgradeItems = @($upgradeItems | Where-Object { ($_.Source ?? 'winget') -eq 'winget' })
    $bulkBlocked = @($wingetUpgradeItems | Where-Object { -not $_.BulkUpgradeEligible }).Count

    if ($hasWinget -and $wingetUpgradeItems.Count -gt 0 -and $bulkBlocked -eq 0) {
        $bulkTimeout = [int]($wingetUpgradeItems[0].BulkTimeoutSeconds ?? 7200)
        if ($bulkTimeout -le 0) { $bulkTimeout = 7200 }

        Write-Log -Level INFO -Component SOFTWARE `
            -Message "Bulk upgrade: 'winget upgrade --all' for $($wingetUpgradeItems.Count) package(s) (timeout ${bulkTimeout}s)"

        $bulkExit = Invoke-ExternalPackageCommand -FilePath (Resolve-WingetPath) -TimeoutSeconds $bulkTimeout `
            -ArgumentList @('upgrade', '--all', '--include-unknown', '--silent',
            '--accept-package-agreements', '--accept-source-agreements', '--disable-interactivity')
        Write-Log -Level INFO -Component SOFTWARE -Message "Bulk upgrade exit code: $bulkExit"

        # VERIFY BY RE-ENUMERATING, NOT BY THE EXIT CODE. `--all` returns non-zero if ANY single
        # package failed, so the code says nothing about the other twenty - and returns 0 in
        # cases where individual packages were skipped. Re-querying is the only honest check.
        #
        # This deliberately calls Invoke-CapturedCommand rather than Get-WingetUpgrade: it has
        # to distinguish "the query ran and nothing is left" from "the query itself failed".
        # Get-WingetUpgrade returns an empty array for both, and reading a failed query as
        # "everything upgraded" would report success for work that never happened.
        $verify = Invoke-CapturedCommand -FilePath (Resolve-WingetPath) -TimeoutSeconds 300 `
            -ArgumentList @('upgrade', '--include-unknown', '--accept-source-agreements', '--disable-interactivity')

        $remaining = if ($verify.TimedOut) { @() }
        else { ConvertFrom-WingetUpgradeTable -Lines @($verify.StdOut -split '\r?\n') }

        $verifyUsable = (-not $verify.TimedOut) -and ($verify.ExitCode -eq 0 -or $remaining.Count -gt 0)

        if (-not $verifyUsable) {
            # Claim nothing. Every item stays pending and the ladder re-attempts it, which is
            # safe because a package that IS already current returns UPDATE_NOT_APPLICABLE and
            # is counted as success there.
            Write-Log -Level WARN -Component SOFTWARE `
                -Message 'Could not verify the bulk upgrade (re-query failed) - re-attempting every queued package individually'
        }
        else {
            # Compare on the same rendered identifiers BOTH lists were built from. Truncation is
            # deterministic, so two truncated forms of one package still compare equal: a lossy
            # value is still a valid comparison key even when it is not a valid selector to hand
            # back to winget.
            $stillListed = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($r in $remaining) {
                if ($r.Id) { $null = $stillListed.Add("id:$($r.Id)") }
                if ($r.Name) { $null = $stillListed.Add("name:$($r.Name)") }
            }

            foreach ($item in $wingetUpgradeItems) {
                $bid = [string]($item.Id ?? '')
                $bnm = [string]($item.Name ?? '')
                $stillThere = ($bid -and $stillListed.Contains("id:$bid")) -or
                              ($bnm -and $stillListed.Contains("name:$bnm"))
                if ($stillThere) { continue }   # not upgraded - leave it to the ladder
                Write-Log -Level SUCCESS -Component SOFTWARE `
                    -Message "Upgraded (winget --all): $(if ($bnm) { $bnm } else { $bid })"
                $processed++
                $null = $bulkDone.Add("$bid|$bnm")
            }

            $stragglers = $wingetUpgradeItems.Count - $bulkDone.Count
            if ($stragglers -gt 0) {
                Write-Log -Level INFO -Component SOFTWARE `
                    -Message "$stragglers package(s) still listed after --all - retrying those individually"
            }
        }
    }

    foreach ($item in $upgradeItems) {
        # Already confirmed upgraded by the bulk pass - do not re-attempt or double-count.
        if ($bulkDone.Contains("$([string]($item.Id ?? ''))|$([string]($item.Name ?? ''))")) { continue }
        $name = [string]($item.Name ?? '')
        $id = [string]($item.Id ?? $item.WingetId ?? '')
        $source = $item.Source ?? 'winget'
        $current = $item.CurrentVersion ?? 'unknown'
        $available = $item.AvailableVersion ?? 'latest'
        $label = if ($name) { $name } else { $id }

        # Same per-item timeout treatment Phase 2 already gives installs (see the LibreOffice
        # note there). Phase 3 never had it, so every upgrade silently used
        # Invoke-ExternalPackageCommand's 600s default - and an upgrade is an uninstall +
        # reinstall, i.e. strictly slower than the install that already needed 900s.
        $timeoutArgs = @{}
        $declaredTimeout = [int]($item.TimeoutSeconds ?? 0)
        if ($declaredTimeout -gt 0) { $timeoutArgs['TimeoutSeconds'] = $declaredTimeout }

        try {
            Write-Log -Level INFO -Component SOFTWARE -Message "Upgrading $label ($current -> $available)"
            $upgraded = $false
            $boundToPackage = $false
            $attempts = [System.Collections.Generic.List[string]]::new()

            if ($source -eq 'winget' -and $hasWinget -and ($id -or $name)) {
                $wingetCommon = @('--silent', '--accept-package-agreements',
                    '--accept-source-agreements', '--disable-interactivity')

                # ARGUMENTS CONTAINING SPACES MUST BE QUOTED HERE. Invoke-ExternalPackageCommand
                # builds its command line with `$ArgumentList -join ' '`, so an unquoted display
                # Name is torn into separate arguments - verified directly: 'Mozilla Firefox'
                # arrives at the child process as '--name Mozilla' plus a stray positional
                # 'Firefox'. winget display Names are usually multi-word, so before this the
                # --name and positional fallbacks below could essentially never bind, and the
                # whole fallback ladder was decorative for exactly the packages that needed it.
                # Ids are quoted too - ARP ids such as 'ARP\Machine\X64\Some App' contain spaces.
                $quoteArg = { param($v) if ($v -match '\s') { '"' + $v + '"' } else { $v } }

                $forms = [System.Collections.Generic.List[hashtable]]::new()
                if ($id) {
                    $forms.Add(@{ Label = '--id'; Args = @('upgrade', '--id', (& $quoteArg $id)) })
                }
                if ($name) {
                    $forms.Add(@{ Label = '--name'; Args = @('upgrade', '--name', (& $quoteArg $name)) })
                    $forms.Add(@{ Label = 'query'; Args = @('upgrade', (& $quoteArg $name)) })
                }

                foreach ($form in $forms) {
                    $exitCode = Invoke-ExternalPackageCommand -FilePath (Resolve-WingetPath) `
                        -ArgumentList ($form.Args + $wingetCommon) @timeoutArgs

                    # 0 = upgraded; -1978335189 (UPDATE_NOT_APPLICABLE) = already current.
                    if ($exitCode -in 0, -1978335189) {
                        Write-Log -Level SUCCESS -Component SOFTWARE `
                            -Message "Upgraded (winget $($form.Label)): $label"
                        $upgraded = $true
                        break
                    }

                    $attempts.Add("$($form.Label)=$exitCode")

                    # THE LADDER CONTINUES ONLY ON A *MATCHING* FAILURE. The three forms are
                    # genuinely different match paths - --id uses winget's strict
                    # ARP-correlation index and is a documented source of false misses
                    # (microsoft/winget-cli#5688, #2686; Wazuh Agent is a known example),
                    # --name uses the looser match the bulk `winget upgrade --all` path relies
                    # on, and the positional query uses the name/moniker/tag search behind
                    # `list`/`search` - so when one fails to RESOLVE the package another
                    # genuinely may succeed.
                    #
                    # Any other non-zero code means winget DID resolve the package and the
                    # operation itself failed. Re-running the ladder there would re-invoke the
                    # SAME installer through a different selector: no new information, and on
                    # an unattended run it burns the full per-item timeout again for each
                    # remaining form (up to 3 x 1800s for one package). So that stops the
                    # ladder and is reported as the real failure it is.
                    if ($exitCode -in $script:WingetMatchFailureCodes) { continue }
                    $boundToPackage = $true
                    break
                }
            }

            # Chocolatey. Deliberately only for items chocolatey itself reported as outdated:
            # `choco upgrade` INSTALLS a package that is not present ("... is not installed.
            # Installing..."), so reusing it as a cross-source fallback for a winget item would
            # silently ADD software instead of upgrading it. That is why Phase 3 has no
            # cross-source fallback even though Phase 2's install path does.
            if (-not $upgraded -and $source -eq 'choco' -and $id -and $hasChoco) {
                $exitCode = Invoke-ExternalPackageCommand -FilePath 'choco' `
                    -ArgumentList @('upgrade', $id, '--yes', '--no-progress') @timeoutArgs
                if ($exitCode -eq 0) {
                    Write-Log -Level SUCCESS -Component SOFTWARE -Message "Upgraded (choco): $label"
                    $upgraded = $true
                }
                else {
                    $attempts.Add("choco=$exitCode")
                    $boundToPackage = $true
                }
            }

            if ($upgraded) {
                $processed++
            }
            elseif ($attempts.Count -eq 0) {
                # No mechanism was even available to try - e.g. the diff names a winget source
                # on a machine where winget is missing. Not a failure of this package.
                Write-Log -Level WARN -Component SOFTWARE `
                    -Message "No available upgrade mechanism for $label (source: $source) - skipping"
                $skipped++
            }
            elseif (-not $boundToPackage) {
                # Every form that ran failed to RESOLVE the package (no match, or an ambiguous
                # one winget refuses to guess at), so the reporting package manager cannot act
                # on it at all. Counting this as a failure is what produced phantom errors and
                # a Warning/Failed status on runs where nothing was actually wrong. The attempt
                # codes are logged so an ambiguous match is still diagnosable rather than
                # disappearing into a generic "skipped".
                $detail = if ($item.VersionUnknown) {
                    'installed version undeterminable'
                }
                else {
                    'installed outside the package manager'
                }
                Write-Log -Level INFO -Component SOFTWARE `
                    -Message "Not upgradable by ${source} ($detail; attempts: $($attempts -join ', ')) - skipping: $label"
                $skipped++
            }
            else {
                Write-Log -Level WARN -Component SOFTWARE `
                    -Message "Could not upgrade $label (attempts: $($attempts -join ', '))"
                $errors += "No upgrade method succeeded: $label"
                $failed++
            }
        }
        catch {
            Write-Log -Level ERROR -Component SOFTWARE -Message "Upgrade failed [$label]: $_"
            $errors += "[upgrade:$label] $_"
            $failed++
        }
    }

    $status = if ($failed -eq 0) { 'Success' } elseif ($processed -gt 0) { 'Warning' } else { 'Failed' }
    Write-Log -Level INFO -Component SOFTWARE -Message "Done: $processed processed, $skipped skipped, $failed failed"
    if ($rebootRequired) {
        Write-Log -Level WARN -Component SOFTWARE -Message 'One or more uninstallers require a reboot to finish'
    }

    return New-ModuleResult -ModuleName 'SoftwareManagement' -Status $status -ModuleType 'Type2' `
        -ItemsDetected $diff.Count -ItemsProcessed $processed -ItemsSkipped $skipped -ItemsFailed $failed `
        -RebootRequired $rebootRequired -Errors $errors
}

Export-ModuleMember -Function 'Invoke-SoftwareManagement'
