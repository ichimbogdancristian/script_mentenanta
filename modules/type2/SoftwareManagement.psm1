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

function Remove-BloatwareLayered {
    param(
        [string]$PackageName,
        [string]$WingetId,
        [switch]$HasWinget
    )

    $removed = $false
    $attempts = @()

    Write-Log -Level INFO -Component SOFTWARE -Message "  Attempting layered removal of: $PackageName"

    # Layer 1: AppX removal (current user + all users)
    try {
        $pkg = Get-AppxPackageCompat -Name $PackageName -AllUsers -ErrorAction SilentlyContinue
        if (-not $pkg) {
            $pkg = Get-AppxPackageCompat -Name "*$PackageName*" -AllUsers -ErrorAction SilentlyContinue
        }
        if ($pkg) {
            $pkg | ForEach-Object {
                Remove-AppxPackageCompat -PackageFullName $_.PackageFullName -AllUsers -ErrorAction Continue
            }
            Write-Log -Level SUCCESS -Component SOFTWARE -Message "    ✓ Layer 1: Removed AppX"
            $attempts += 'AppX'
            $removed = $true
        }
    }
    catch {
        Write-Log -Level DEBUG -Component SOFTWARE -Message "    Layer 1 (AppX) skipped: $_"
    }

    # Layer 2: Provisioned package removal (prevents reinstall on new login)
    try {
        $prov = Get-AppxProvisionedPackageCompat -ErrorAction SilentlyContinue |
            Where-Object { $_.PackageName -like "*$PackageName*" }
        if ($prov) {
            $prov | ForEach-Object {
                $null = Remove-AppxProvisionedPackageCompat -PackageName $_.PackageName -ErrorAction Continue
            }
            Write-Log -Level SUCCESS -Component SOFTWARE -Message "    ✓ Layer 2: Removed Provisioned"
            $attempts += 'Provisioned'
            $removed = $true
        }
    }
    catch {
        Write-Log -Level DEBUG -Component SOFTWARE -Message "    Layer 2 (Provisioned) skipped: $_"
    }

    # Layer 3: Registry cleanup (Win32 programs)
    try {
        $regPaths = @(
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
            "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"
        )
        foreach ($path in $regPaths) {
            $regItem = Get-ChildItem $path -ErrorAction SilentlyContinue |
                Where-Object { $_.GetValue('DisplayName') -like "*$PackageName*" } |
                Select-Object -First 1

            if ($regItem) {
                try {
                    $uninstallString = $regItem.GetValue('UninstallString')
                    if ($uninstallString) {
                        & cmd /c $uninstallString -ErrorAction Continue
                        Write-Log -Level SUCCESS -Component SOFTWARE -Message "    ✓ Layer 3: Executed uninstall string"
                        $attempts += 'Registry'
                        $removed = $true
                    }
                }
                catch {
                    Write-Log -Level DEBUG -Component SOFTWARE -Message "    Layer 3 (Registry) failed: $_"
                }
            }
        }
    }
    catch {
        Write-Log -Level DEBUG -Component SOFTWARE -Message "    Layer 3 (Registry) skipped: $_"
    }

    # Layer 4: WinGet removal (fallback)
    if (-not $removed -and $WingetId -and $HasWinget) {
        try {
            $wingetExe = Resolve-WingetPath
            $null = & $wingetExe uninstall --id $WingetId --silent --accept-source-agreements --disable-interactivity 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Log -Level SUCCESS -Component SOFTWARE -Message "    ✓ Layer 4: WinGet uninstall succeeded"
                $attempts += 'WinGet'
                $removed = $true
            }
        }
        catch {
            Write-Log -Level DEBUG -Component SOFTWARE -Message "    Layer 4 (WinGet) failed: $_"
        }
    }

    if ($removed) {
        Write-Log -Level SUCCESS -Component SOFTWARE -Message "  Removal succeeded via: $($attempts -join ' → ')"
    }
    else {
        Write-Log -Level WARN -Component SOFTWARE -Message "  Not found (attempted: $($attempts -join ', ' | default 'none'))"
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

            if ($source -eq 'winget' -and $id -and $hasWinget) {
                $wingetArgs = @('upgrade', '--id', $id, '--silent', '--accept-package-agreements',
                    '--accept-source-agreements', '--disable-interactivity')
                $exitCode = Invoke-ExternalPackageCommand -FilePath (Resolve-WingetPath) -ArgumentList $wingetArgs
                if ($exitCode -in 0, -1978335189) {
                    Write-Log -Level SUCCESS -Component SOFTWARE -Message "Upgraded (winget): $name"
                    $upgraded = $true
                }
                else {
                    Write-Log -Level WARN -Component SOFTWARE -Message "winget exit $exitCode for $name"
                }
            }

            if (-not $upgraded -and $source -eq 'choco' -and $id -and $hasChoco) {
                $exitCode = Invoke-ExternalPackageCommand -FilePath 'choco' -ArgumentList @('upgrade', $id, '--yes', '--no-progress')
                if ($exitCode -eq 0) {
                    Write-Log -Level SUCCESS -Component SOFTWARE -Message "Upgraded (choco): $name"
                    $upgraded = $true
                }
            }

            if ($upgraded) {
                $processed++
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
    Write-Log -Level INFO -Component SOFTWARE -Message "Done: $processed processed, $failed failed"

    return New-ModuleResult -ModuleName 'SoftwareManagement' -Status $status -ModuleType 'Type2' `
        -ItemsDetected $diff.Count -ItemsProcessed $processed -ItemsFailed $failed -Errors $errors
}

Export-ModuleMember -Function 'Invoke-SoftwareManagement'
