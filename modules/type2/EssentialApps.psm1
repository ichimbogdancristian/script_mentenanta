#Requires -Version 7.0
<#
.SYNOPSIS    Essential Apps Installation - Type 2 (system modification)
.DESCRIPTION Installs apps listed in the diff list using winget or chocolatey.
             Skips apps already installed or marked with a platform exclusion.
.NOTES       Module Type: Type2 | DiffKey: EssentialApps | Version: 5.0
#>

$_corePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'core\Maintenance.psm1'
if (-not (Get-Command 'Write-Log' -ErrorAction SilentlyContinue)) {
    Import-Module $_corePath -Force -Global -WarningAction SilentlyContinue
}

function Invoke-EssentialApp {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([hashtable])]
    param(
        [Parameter()][hashtable]$OSContext
    )

    Write-Log -Level INFO -Component ESSAPPS -Message 'Starting essential apps installation'

    $diff = Get-DiffList -ModuleName 'EssentialApps'
    if (-not $diff -or $diff.Count -eq 0) {
        Write-Log -Level INFO -Component ESSAPPS -Message 'All essential apps already installed'
        return New-ModuleResult -ModuleName 'EssentialApps' -Status 'Skipped' -Message 'All apps present'
    }

    $osCtx     = if ($OSContext) { $OSContext } elseif ($global:OSContext) { $global:OSContext } else { Get-OSContext }
    $hasWinget = Test-CommandAvailable 'winget'
    $hasChoco  = Test-CommandAvailable 'choco'
    $processed = 0; $failed = 0; $errors = @()

    Write-Log -Level INFO -Component ESSAPPS -Message "Installing $($diff.Count) missing app(s) - winget:$hasWinget choco:$hasChoco"

    foreach ($item in $diff) {
        $name      = $item.Name ?? "$item"
        $wingetId  = $item.WingetId ?? ''
        $chocoId   = $item.ChocoId  ?? ''
        $scope     = $item.Scope    ?? 'machine'
        $installed = $false

        # OS-platform exclusion
        $excl = $item.ExcludeOn ?? @()
        if ($osCtx.IsWindows11 -and $excl -contains 'windows11') {
            Write-Log -Level DEBUG -Component ESSAPPS -Message "Skipping (Win11 excluded): $name"; $processed++; continue
        }
        if (-not $osCtx.IsWindows11 -and $excl -contains 'windows10') {
            Write-Log -Level DEBUG -Component ESSAPPS -Message "Skipping (Win10 excluded): $name"; $processed++; continue
        }

        try {
            # 1. winget
            if (-not $installed -and $wingetId -and $hasWinget) {
                if ($PSCmdlet.ShouldProcess($wingetId, 'winget install')) {
                    $scopeArgs = if ($scope -eq 'user') { @('--scope', 'user') } else { @('--scope', 'machine') }
                    $null = & winget install --id $wingetId --silent --accept-package-agreements --accept-source-agreements @scopeArgs 2>&1
                    if ($LASTEXITCODE -in 0, -1978335189) {  # 0=success, -1978335189=already installed
                        Write-Log -Level SUCCESS -Component ESSAPPS -Message "winget installed: $name"
                        $installed = $true
                    } else {
                        Write-Log -Level WARN -Component ESSAPPS -Message "winget exit $LASTEXITCODE for $name"
                    }
                }
            }

            # 2. chocolatey fallback
            if (-not $installed -and $chocoId -and $hasChoco) {
                if ($PSCmdlet.ShouldProcess($chocoId, 'choco install')) {
                    $null = & choco install $chocoId --yes --no-progress 2>&1
                    if ($LASTEXITCODE -eq 0) {
                        Write-Log -Level SUCCESS -Component ESSAPPS -Message "choco installed: $name"
                        $installed = $true
                    }
                }
            }

            if (-not $installed) {
                Write-Log -Level WARN -Component ESSAPPS -Message "Could not install (no suitable method): $name"
                $errors += "No installer available: $name"; $failed++
            } else {
                $processed++
            }
        }
        catch {
            Write-Log -Level ERROR -Component ESSAPPS -Message "Error installing $name`: $_"
            $errors += "[$name] $_"; $failed++
        }
    }

    $status = if ($failed -eq 0) { 'Success' } elseif ($processed -gt 0) { 'Warning' } else { 'Failed' }
    Write-Log -Level INFO -Component ESSAPPS -Message "Done: $processed installed, $failed failed"
    return New-ModuleResult -ModuleName 'EssentialApps' -Status $status -ItemsDetected $diff.Count `
                            -ItemsProcessed $processed -ItemsFailed $failed -Errors $errors
}

Export-ModuleMember -Function 'Invoke-EssentialApp'
