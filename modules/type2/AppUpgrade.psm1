#Requires -Version 7.0
<#
.SYNOPSIS    App Upgrade - Type 2 (system modification)
.DESCRIPTION Upgrades outdated apps listed in the diff list using winget or chocolatey.
             Skips pinned versions and packages matching exclude patterns.
.NOTES       Module Type: Type2 | DiffKey: AppUpgrade | Version: 5.0
#>

$_corePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'core\Maintenance.psm1'
if (-not (Get-Command 'Write-Log' -ErrorAction SilentlyContinue)) {
    Import-Module $_corePath -Force -Global -WarningAction SilentlyContinue
}

function Invoke-AppUpgrade {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter()][hashtable]$OSContext
    )

    Write-Log -Level INFO -Component APPUPGR -Message 'Starting app upgrades'

    $diff = Get-DiffList -ModuleName 'AppUpgrade'
    if (-not $diff -or $diff.Count -eq 0) {
        Write-Log -Level INFO -Component APPUPGR -Message 'All apps are up to date'
        return New-ModuleResult -ModuleName 'AppUpgrade' -Status 'Skipped' -Message 'No upgrades available'
    }

    $hasWinget = Test-CommandAvailable 'winget'
    $hasChoco = Test-CommandAvailable 'choco'
    $processed = 0; $failed = 0; $errors = @()

    Write-Log -Level INFO -Component APPUPGR -Message "Upgrading $($diff.Count) app(s)"

    foreach ($item in $diff) {
        $name = $item.Name ?? "$item"
        $id = $item.Id ?? $item.WingetId ?? ''
        $source = $item.Source ?? 'winget'
        $current = $item.CurrentVersion ?? $item.Current ?? 'unknown'
        $available = $item.AvailableVersion ?? $item.Available ?? 'latest'

        Write-Log -Level INFO -Component APPUPGR -Message "Upgrading $name ($current -> $available)"

        try {
            $upgraded = $false

            # 1. winget — disable-interactivity prevents interactive prompts
            if ($source -eq 'winget' -and $id -and $hasWinget) {
                $wingetArgs = @('upgrade', '--id', $id, '--silent',
                    '--accept-package-agreements', '--accept-source-agreements',
                    '--disable-interactivity')
                $exitCode = Invoke-ExternalPackageCommand -FilePath 'winget' -ArgumentList $wingetArgs
                if ($exitCode -in 0, -1978335189) {
                    Write-Log -Level SUCCESS -Component APPUPGR -Message "Upgraded (winget): $name"
                    $upgraded = $true
                }
                else {
                    Write-Log -Level WARN -Component APPUPGR -Message "winget exit $exitCode for $name"
                }
            }

            # 2. chocolatey
            if (-not $upgraded -and $source -eq 'choco' -and $id -and $hasChoco) {
                $chocoArgs = @('upgrade', $id, '--yes', '--no-progress')
                $exitCode = Invoke-ExternalPackageCommand -FilePath 'choco' -ArgumentList $chocoArgs
                if ($exitCode -eq 0) {
                    Write-Log -Level SUCCESS -Component APPUPGR -Message "Upgraded (choco): $name"
                    $upgraded = $true
                }
            }

            if (-not $upgraded) {
                Write-Log -Level WARN -Component APPUPGR -Message "Could not upgrade: $name"
                $errors += "No upgrade method succeeded: $name"; $failed++
            }
            else {
                $processed++
            }
        }
        catch {
            Write-Log -Level ERROR -Component APPUPGR -Message "Error upgrading $name`: $_"
            $errors += "[$name] $_"; $failed++
        }
    }

    $status = if ($failed -eq 0) { 'Success' } elseif ($processed -gt 0) { 'Warning' } else { 'Failed' }
    Write-Log -Level INFO -Component APPUPGR -Message "Done: $processed upgraded, $failed failed"
    return New-ModuleResult -ModuleName 'AppUpgrade' -Status $status -ItemsDetected $diff.Count `
        -ItemsProcessed $processed -ItemsFailed $failed -Errors $errors
}

Export-ModuleMember -Function 'Invoke-AppUpgrade'
