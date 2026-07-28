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

function Remove-BloatwareLayered {
    param(
        [string]$PackageName,
        [string]$WingetId,
        [switch]$HasWinget
    )

    $removed = $false
    $attempts = @()

    Write-Log -Level INFO -Component SOFTWARE -Message "  Attempting layered removal of: $PackageName"

    # Both the installed copy AND the provisioning must go: Layer 1 uninstalls it for existing
    # users, Layer 2 stops it returning for new ones. They are NOT alternatives, so neither is
    # gated on $removed.
    $nameStem = Get-AppxNameStem -Identifier $PackageName

    # Layer 1: AppX removal (current user + all users)
    try {
        # Match on the Name stem - see Get-AppxNameStem for why the raw diff identifier fails.
        $pkg = Get-AppxPackageCompat -Name $nameStem -AllUsers -ErrorAction SilentlyContinue
        if (-not $pkg) {
            $pkg = Get-AppxPackageCompat -Name "*$nameStem*" -AllUsers -ErrorAction SilentlyContinue
        }
        if ($pkg) {
            $pkg | ForEach-Object {
                Remove-AppxPackageCompat -PackageFullName $_.PackageFullName -AllUsers -ErrorAction Continue
            }
            Write-Log -Level SUCCESS -Component SOFTWARE -Message "    [OK]Layer 1: Removed AppX ($nameStem)"
            $attempts += 'AppX'
            $removed = $true
        }
        else {
            Write-Log -Level DEBUG -Component SOFTWARE -Message "    Layer 1: no installed AppX package matching '$nameStem'"
        }
    }
    catch {
        Write-Log -Level DEBUG -Component SOFTWARE -Message "    Layer 1 (AppX) skipped: $_"
    }

    # Layer 2: Provisioned package removal (stops it coming back for NEW user profiles).
    # NOTE: deprovisioning does NOT uninstall the package for existing users - that is
    # Layer 1's job. Reporting overall success off this layer alone is what made the module
    # claim Xbox apps were removed while `winget list` still showed them installed.
    try {
        $prov = @(Get-AppxProvisionedPackageCompat -ErrorAction SilentlyContinue |
            Where-Object { $_.PackageName -like "*$nameStem*" })
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
                $attempts += 'Provisioned'
                $removed = $true
            }
        }
        else {
            Write-Log -Level DEBUG -Component SOFTWARE -Message "    Layer 2: no provisioned package matching '$nameStem'"
        }
    }
    catch {
        Write-Log -Level DEBUG -Component SOFTWARE -Message "    Layer 2 (Provisioned) skipped: $_"
    }

    # Layer 3: Registry (Win32) uninstall - ONLY if the AppX/Provisioned layers did not already
    # remove it, and ONLY when the uninstaller can be run SILENTLY. An interactive UninstallString
    # (e.g. a setup EXE, or MSI without /qn) would hang an unattended run forever. The old code
    # ran unconditionally, matched a broad DisplayName wildcard (could hit an unrelated program),
    # launched a possibly-interactive uninstaller, and leaked '-ErrorAction Continue' to cmd.exe.
    if (-not $removed) {
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
                        $attempts += 'Registry'
                        $removed = $true
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

    # Layer 4: WinGet removal by resolved Id (fallback). Routed through
    # Invoke-ExternalPackageCommand (timeout-guarded, kills a hung process tree) rather than a
    # bare '&' call - this must never be able to hang an unattended run.
    if (-not $removed -and $WingetId -and $HasWinget) {
        try {
            $exitCode = Invoke-ExternalPackageCommand -FilePath (Resolve-WingetPath) `
                -ArgumentList @('uninstall', '--id', $WingetId, '--silent', '--accept-source-agreements', '--disable-interactivity')
            if ($exitCode -eq 0) {
                Write-Log -Level SUCCESS -Component SOFTWARE -Message "    [OK]Layer 4: WinGet uninstall (by id) succeeded"
                $attempts += 'WinGet'
                $removed = $true
            }
            else {
                Write-Log -Level DEBUG -Component SOFTWARE -Message "    Layer 4 (WinGet by id) exit $exitCode"
            }
        }
        catch {
            Write-Log -Level DEBUG -Component SOFTWARE -Message "    Layer 4 (WinGet) failed: $_"
        }
    }

    # Layer 5: WinGet removal by name (fallback). Only tried when no WingetId was resolved
    # during audit - a package detected solely via the Registry source has no correlated
    # winget id, but winget may still be able to remove it once queried by name. Only attempted
    # when Layer 4 didn't already run (WingetId known) so the more precise --id form is always
    # preferred when available.
    if (-not $removed -and -not $WingetId -and $HasWinget -and $PackageName) {
        try {
            $exitCode = Invoke-ExternalPackageCommand -FilePath (Resolve-WingetPath) `
                -ArgumentList @('uninstall', '--name', $PackageName, '--silent', '--accept-source-agreements', '--disable-interactivity')
            if ($exitCode -eq 0) {
                Write-Log -Level SUCCESS -Component SOFTWARE -Message "    [OK]Layer 5: WinGet uninstall (by name) succeeded"
                $attempts += 'WinGet-byname'
                $removed = $true
            }
            else {
                Write-Log -Level DEBUG -Component SOFTWARE -Message "    Layer 5 (WinGet by name) exit $exitCode - no match or already absent"
            }
        }
        catch {
            Write-Log -Level DEBUG -Component SOFTWARE -Message "    Layer 5 (WinGet by name) failed: $_"
        }
    }

    # ── Post-removal validation ──────────────────────────────────────────────────
    # Confirm against live system state instead of trusting the layers' own reports. A
    # package that is merely DEPROVISIONED is still installed for every existing user, so
    # it has not actually been removed - saying otherwise is how this module reported five
    # Xbox apps as removed while they were all still listed by `winget list`.
    if ($removed) {
        $stillInstalled = $null
        try {
            $stillInstalled = @(Get-AppxPackageCompat -Name $nameStem -AllUsers -ErrorAction SilentlyContinue)
        }
        catch {
            Write-Log -Level DEBUG -Component SOFTWARE -Message "    Post-removal check failed: $_"
        }

        if ($stillInstalled -and $stillInstalled.Count -gt 0) {
            $removed = $false
            Write-Log -Level WARN -Component SOFTWARE `
                -Message "  Still installed after $($attempts -join ' -> ') - deprovisioning alone does not uninstall it for existing users: $nameStem"
        }
        else {
            Write-Log -Level SUCCESS -Component SOFTWARE -Message "  Removal verified via: $($attempts -join ' -> ')"
        }
    }

    if (-not $removed -and $attempts.Count -eq 0) {
        # NOTE: 'default' is not a PowerShell command - the old '| default ''none''' threw inside
        # the string interpolation on every not-found package, turning a clean WARN into an ERROR.
        Write-Log -Level WARN -Component SOFTWARE -Message "  Not found (attempted: none)"
    }

    return $removed
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
            $removed = Remove-BloatwareLayered -PackageName $pkgName -WingetId $wingetId -HasWinget:$hasWinget

            if ($removed) {
                $processed++
            }
            else {
                Write-Log -Level WARN -Component SOFTWARE -Message "Could not remove: $name"
                $failed++
                $errors += "Removal failed: $name"
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

            $installed = $false
            if ($wingetId -and $hasWinget) {
                $scopeArgs = if ($scope -eq 'user') { @('--scope', 'user') } else { @('--scope', 'machine') }
                $wingetArgs = @('install', '--id', $wingetId, '--source', 'winget', '--silent',
                    '--disable-interactivity', '--accept-package-agreements', '--accept-source-agreements') + $scopeArgs
                $exitCode = Invoke-ExternalPackageCommand -FilePath (Resolve-WingetPath) -ArgumentList $wingetArgs
                if ($exitCode -in 0, -1978335135, -1978335189) {
                    Write-Log -Level SUCCESS -Component SOFTWARE -Message "Installed (winget): $name"
                    $installed = $true
                }
                else {
                    Write-Log -Level WARN -Component SOFTWARE -Message "winget exit $exitCode for $name"
                }
            }

            if (-not $installed -and $chocoId -and $hasChoco) {
                $exitCode = Invoke-ExternalPackageCommand -FilePath 'choco' -ArgumentList @('install', $chocoId, '--yes', '--no-progress')
                if ($exitCode -eq 0) {
                    Write-Log -Level SUCCESS -Component SOFTWARE -Message "Installed (choco): $name"
                    $installed = $true
                }
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
    foreach ($item in $upgradeItems) {
        $name = $item.Name ?? "$item"
        $id = $item.Id ?? $item.WingetId ?? ''
        $source = $item.Source ?? 'winget'
        $current = $item.CurrentVersion ?? 'unknown'
        $available = $item.AvailableVersion ?? 'latest'
        try {
            Write-Log -Level INFO -Component SOFTWARE -Message "Upgrading $name ($current -> $available)"
            $upgraded = $false
            $notWingetManaged = $false

            if ($source -eq 'winget' -and $id -and $hasWinget) {
                $wingetArgs = @('upgrade', '--id', $id, '--silent', '--accept-package-agreements',
                    '--accept-source-agreements', '--disable-interactivity')
                $exitCode = Invoke-ExternalPackageCommand -FilePath (Resolve-WingetPath) -ArgumentList $wingetArgs
                # 0 = upgraded; -1978335189 (UPDATE_NOT_APPLICABLE) = already current, nothing to do.
                if ($exitCode -in 0, -1978335189) {
                    Write-Log -Level SUCCESS -Component SOFTWARE -Message "Upgraded (winget): $name"
                    $upgraded = $true
                }
                # -1978335212 (NO_APPLICATIONS_FOUND) for '--id' does NOT reliably mean "not
                # managed by winget" - it's a documented winget-cli matching bug where '--id'
                # uses stricter ARP-correlation logic than the bulk upgrade path, and fails for
                # some MSI/vendor-installed-but-ARP-correlated packages (Wazuh Agent is a known
                # example) even though 'winget upgrade' (bare/--all) finds and upgrades the same
                # package fine (see microsoft/winget-cli#5688, #2686). Retry once with '--name'
                # before concluding it's genuinely unmanaged - '--name' uses the same looser
                # match the bulk path relies on, so it succeeds where '--id' incorrectly fails.
                elseif ($exitCode -eq -1978335212) {
                    $retryArgs = @('upgrade', '--name', $name, '--silent', '--accept-package-agreements',
                        '--accept-source-agreements', '--disable-interactivity')
                    $retryExitCode = Invoke-ExternalPackageCommand -FilePath (Resolve-WingetPath) -ArgumentList $retryArgs
                    if ($retryExitCode -in 0, -1978335189) {
                        Write-Log -Level SUCCESS -Component SOFTWARE -Message "Upgraded (winget, by name after --id matching bug): $name"
                        $upgraded = $true
                    }
                    else {
                        # Both --id and --name apply winget's strict ARP-correlation match, which
                        # can fail for the same package that the bare/positional query resolves
                        # fine (that's how it was found in `winget upgrade --include-unknown` in
                        # the first place - see Get-WingetUpgrade). The positional query argument
                        # uses the looser name/moniker/tag search winget uses for `list`/`search`,
                        # not the correlation index, so it's a genuinely different match path -
                        # try it before concluding the package is unmanaged.
                        $queryArgs = @('upgrade', $name, '--silent', '--accept-package-agreements',
                            '--accept-source-agreements', '--disable-interactivity')
                        $queryExitCode = Invoke-ExternalPackageCommand -FilePath (Resolve-WingetPath) -ArgumentList $queryArgs
                        if ($queryExitCode -in 0, -1978335189) {
                            Write-Log -Level SUCCESS -Component SOFTWARE -Message "Upgraded (winget, by query after --id/--name matching bug): $name"
                            $upgraded = $true
                        }
                        else {
                            Write-Log -Level INFO -Component SOFTWARE -Message "Not managed by winget (installed outside winget) — skipping upgrade: $name"
                            $notWingetManaged = $true
                        }
                    }
                }
                else {
                    Write-Log -Level WARN -Component SOFTWARE -Message "winget exit $exitCode for $name"
                }
            }

            if (-not $upgraded -and -not $notWingetManaged -and $source -eq 'choco' -and $id -and $hasChoco) {
                $exitCode = Invoke-ExternalPackageCommand -FilePath 'choco' -ArgumentList @('upgrade', $id, '--yes', '--no-progress')
                if ($exitCode -eq 0) {
                    Write-Log -Level SUCCESS -Component SOFTWARE -Message "Upgraded (choco): $name"
                    $upgraded = $true
                }
            }

            if ($upgraded) {
                $processed++
            }
            elseif ($notWingetManaged) {
                $skipped++
            }
            else {
                Write-Log -Level WARN -Component SOFTWARE -Message "Could not upgrade: $name"
                $errors += "No upgrade method succeeded: $name"
                $failed++
            }
        }
        catch {
            Write-Log -Level ERROR -Component SOFTWARE -Message "Upgrade failed [$name]: $_"
            $errors += "[upgrade:$name] $_"
            $failed++
        }
    }

    $status = if ($failed -eq 0) { 'Success' } elseif ($processed -gt 0) { 'Warning' } else { 'Failed' }
    Write-Log -Level INFO -Component SOFTWARE -Message "Done: $processed processed, $skipped skipped, $failed failed"

    return New-ModuleResult -ModuleName 'SoftwareManagement' -Status $status -ModuleType 'Type2' `
        -ItemsDetected $diff.Count -ItemsProcessed $processed -ItemsSkipped $skipped -ItemsFailed $failed -Errors $errors
}

Export-ModuleMember -Function 'Invoke-SoftwareManagement'
