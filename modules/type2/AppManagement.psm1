#Requires -Version 7.0
<#
.SYNOPSIS    App Management - Type 2 (Consolidated Install + Upgrade)
.DESCRIPTION Manages application lifecycle across install and upgrade scenarios.
             Processes install items (missing essential apps) and upgrade items
             (outdated apps) identified by AppManagementAudit.
.NOTES       Module Type: Type2 | DiffKey: AppManagement | Version: 5.1 (Consolidated)
#>

$_corePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'core\Maintenance.psm1'
if (-not (Get-Command 'Write-Log' -ErrorAction SilentlyContinue)) {
    Import-Module $_corePath -Force -Global -WarningAction SilentlyContinue
}

function Invoke-AppManagement {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter()][hashtable]$OSContext
    )

    Write-Log -Level INFO -Component APP-MGMT -Message 'Starting app management (install + upgrade)'

    $diff = Get-DiffList -ModuleName 'AppManagement'
    if (-not $diff -or $diff.Count -eq 0) {
        Write-Log -Level INFO -Component APP-MGMT -Message 'No app management actions needed'
        return New-ModuleResult -ModuleName 'AppManagement' -Status 'Skipped' -ModuleType 'Type2' -Message 'All apps managed'
    }

    $osCtx = if ($OSContext) { $OSContext } elseif ($global:OSContext) { $global:OSContext } else { Get-OSContext }
    $hasWinget = Test-CommandAvailable 'winget'
    $hasChoco = Test-CommandAvailable 'choco'
    $processed = 0; $failed = 0; $errors = @()

    # Split diff into install and upgrade for logging
    $installItems = @($diff | Where-Object { $_.AppType -eq 'install' })
    $upgradeItems = @($diff | Where-Object { $_.AppType -eq 'upgrade' })

    Write-Log -Level INFO -Component APP-MGMT -Message "Processing $($diff.Count) app management action(s): $($installItems.Count) install, $($upgradeItems.Count) upgrade - winget:$hasWinget choco:$hasChoco"

    # Pre-update winget sources once for both installs and upgrades
    if ($hasWinget) {
        Write-Log -Level INFO -Component APP-MGMT -Message 'Updating winget sources'
        $null = Invoke-ExternalPackageCommand -FilePath 'winget' -ArgumentList @('source', 'update', '--disable-interactivity')
    }

    foreach ($item in $diff) {
        $name = $item.Name ?? $item.name ?? "$item"
        $appType = $item.AppType ?? 'unknown'

        try {
            # ─── INSTALL ITEMS ───────────────────────────────────────────
            if ($appType -eq 'install') {
                $wingetId = $item.WingetId ?? $item.winget ?? ''
                $chocoId = $item.ChocoId ?? $item.choco ?? ''
                $scope = $item.Scope ?? $item.scope ?? 'machine'
                $installed = $false

                # OS-platform exclusion
                $excl = $item.ExcludeOn ?? @()
                if ($osCtx.IsWindows11 -and $excl -contains 'windows11') {
                    Write-Log -Level DEBUG -Component APP-MGMT -Message "Skipping install (Win11 excluded): $name"; continue
                }
                if (-not $osCtx.IsWindows11 -and $excl -contains 'windows10') {
                    Write-Log -Level DEBUG -Component APP-MGMT -Message "Skipping install (Win10 excluded): $name"; continue
                }

                # 1. winget
                if (-not $installed -and $wingetId -and $hasWinget) {
                    $scopeArgs = if ($scope -eq 'user') { @('--scope', 'user') } else { @('--scope', 'machine') }
                    $wingetArgs = @(
                        'install',
                        '--id', $wingetId,
                        '--source', 'winget',
                        '--silent',
                        '--disable-interactivity',
                        '--accept-package-agreements',
                        '--accept-source-agreements'
                    ) + $scopeArgs
                    $exitCode = Invoke-ExternalPackageCommand -FilePath 'winget' -ArgumentList $wingetArgs
                    if ($exitCode -in 0, -1978335135, -1978335189) {
                        Write-Log -Level SUCCESS -Component APP-MGMT -Message "Installed (winget): $name"
                        $installed = $true
                    }
                    else {
                        Write-Log -Level WARN -Component APP-MGMT -Message "winget exit $exitCode for $name"
                    }
                }

                # 2. chocolatey fallback
                if (-not $installed -and $chocoId -and $hasChoco) {
                    $exitCode = Invoke-ExternalPackageCommand -FilePath 'choco' `
                        -ArgumentList @('install', $chocoId, '--yes', '--no-progress')
                    if ($exitCode -eq 0) {
                        Write-Log -Level SUCCESS -Component APP-MGMT -Message "Installed (choco): $name"
                        $installed = $true
                    }
                }

                if (-not $installed) {
                    Write-Log -Level WARN -Component APP-MGMT -Message "Could not install: $name"
                    $errors += "No installer available: $name"; $failed++
                }
                else {
                    $processed++
                }
            }

            # ─── UPGRADE ITEMS ───────────────────────────────────────────
            elseif ($appType -eq 'upgrade') {
                $id = $item.Id ?? $item.WingetId ?? ''
                $source = $item.Source ?? 'winget'
                $current = $item.CurrentVersion ?? $item.Current ?? 'unknown'
                $available = $item.AvailableVersion ?? $item.Available ?? 'latest'

                Write-Log -Level INFO -Component APP-MGMT -Message "Upgrading $name ($current -> $available)"

                $upgraded = $false

                # 1. winget
                if ($source -eq 'winget' -and $id -and $hasWinget) {
                    $wingetArgs = @('upgrade', '--id', $id, '--silent',
                        '--accept-package-agreements', '--accept-source-agreements',
                        '--disable-interactivity')
                    $exitCode = Invoke-ExternalPackageCommand -FilePath 'winget' -ArgumentList $wingetArgs
                    if ($exitCode -in 0, -1978335189) {
                        Write-Log -Level SUCCESS -Component APP-MGMT -Message "Upgraded (winget): $name"
                        $upgraded = $true
                    }
                    else {
                        Write-Log -Level WARN -Component APP-MGMT -Message "winget exit $exitCode for $name"
                    }
                }

                # 2. chocolatey
                if (-not $upgraded -and $source -eq 'choco' -and $id -and $hasChoco) {
                    $chocoArgs = @('upgrade', $id, '--yes', '--no-progress')
                    $exitCode = Invoke-ExternalPackageCommand -FilePath 'choco' -ArgumentList $chocoArgs
                    if ($exitCode -eq 0) {
                        Write-Log -Level SUCCESS -Component APP-MGMT -Message "Upgraded (choco): $name"
                        $upgraded = $true
                    }
                }

                if (-not $upgraded) {
                    Write-Log -Level WARN -Component APP-MGMT -Message "Could not upgrade: $name"
                    $errors += "No upgrade method succeeded: $name"; $failed++
                }
                else {
                    $processed++
                }
            }
        }
        catch {
            Write-Log -Level ERROR -Component APP-MGMT -Message "Error [$appType] $name`: $_"
            $errors += "[$name] $_"; $failed++
        }
    }

    $status = if ($failed -eq 0) { 'Success' } elseif ($processed -gt 0) { 'Warning' } else { 'Failed' }
    Write-Log -Level INFO -Component APP-MGMT -Message "Done: $processed processed, $failed failed"

    return New-ModuleResult -ModuleName 'AppManagement' -Status $status -ModuleType 'Type2' `
        -ItemsDetected $diff.Count -ItemsProcessed $processed -ItemsFailed $failed -Errors $errors
}

Export-ModuleMember -Function 'Invoke-AppManagement'
