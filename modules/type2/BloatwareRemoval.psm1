#Requires -Version 7.0
<#
.SYNOPSIS    Bloatware Removal - Type 2 (system modification)
.DESCRIPTION Removes AppX packages and legacy-installed apps found in the diff list.
             Removes provisioned packages to prevent re-install on new user profiles.
.NOTES       Module Type: Type2 | DiffKey: BloatwareRemoval | Version: 5.0
#>

$_corePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'core\Maintenance.psm1'
if (-not (Get-Command 'Write-Log' -ErrorAction SilentlyContinue)) {
    Import-Module $_corePath -Force -Global -WarningAction SilentlyContinue
}

function Invoke-BloatwareRemoval {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([hashtable])]
    param(
        [Parameter()][hashtable]$OSContext
    )

    Write-Log -Level INFO -Component BLOATWARE -Message 'Starting bloatware removal'

    $diff = Get-DiffList -ModuleName 'BloatwareRemoval'
    if (-not $diff -or $diff.Count -eq 0) {
        Write-Log -Level INFO -Component BLOATWARE -Message 'No bloatware in diff list - system is clean'
        return New-ModuleResult -ModuleName 'BloatwareRemoval' -Status 'Skipped' -Message 'No bloatware found by audit'
    }

    $osCtx = if ($OSContext) { $OSContext } elseif ($global:OSContext) { $global:OSContext } else { Get-OSContext }
    $processed = 0; $failed = 0; $errors = @()

    # PS7 Core requires UseWindowsPowerShell to load the Appx module
    if ($PSVersionTable.PSEdition -eq 'Core') {
        Import-Module -Name Appx -UseWindowsPowerShell -ErrorAction SilentlyContinue
    }

    Write-Log -Level INFO -Component BLOATWARE -Message "Processing $($diff.Count) item(s) on $($osCtx.DisplayText)"

    foreach ($item in $diff) {
        $name = $item.Name ?? $item.PackageName ?? "$item"
        $pkgName = $item.PackageName ?? $item.AppxName ?? ''
        $wingetId = $item.WingetId ?? ''

        try {
            $removed = $false

            # 1. AppX removal
            if ($pkgName) {
                $pkg = Get-AppxPackage -AllUsers -Name "*$pkgName*" -ErrorAction SilentlyContinue
                if (-not $pkg) { $pkg = Get-AppxPackage -Name "*$pkgName*" -ErrorAction SilentlyContinue }
                if ($pkg) {
                    if ($PSCmdlet.ShouldProcess($pkgName, 'Remove-AppxPackage')) {
                        $pkg | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
                        $pkg | Remove-AppxPackage -ErrorAction SilentlyContinue
                        Write-Log -Level SUCCESS -Component BLOATWARE -Message "Removed AppX: $pkgName"
                    }
                    $removed = $true
                }
                # Remove provisioned to prevent re-install
                $prov = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
                Where-Object { $_.PackageName -like "*$pkgName*" }
                if ($prov -and $PSCmdlet.ShouldProcess($pkgName, 'Remove provisioned')) {
                    $prov | ForEach-Object { Remove-AppxProvisionedPackage -Online -PackageName $_.PackageName -ErrorAction SilentlyContinue }
                }
            }

            # 2. Winget fallback
            if (-not $removed -and $wingetId -and (Test-CommandAvailable 'winget')) {
                if ($PSCmdlet.ShouldProcess($wingetId, 'winget uninstall')) {
                    $null = & winget uninstall --id $wingetId --silent --accept-source-agreements 2>&1
                    if ($LASTEXITCODE -eq 0) {
                        Write-Log -Level SUCCESS -Component BLOATWARE -Message "Winget removed: $wingetId"
                        $removed = $true
                    }
                }
            }

            if (-not $removed) { Write-Log -Level WARN -Component BLOATWARE -Message "Not found to remove: $name" }
            $processed++
        }
        catch {
            Write-Log -Level ERROR -Component BLOATWARE -Message "Failed [$name]: $_"
            $errors += "[$name] $_"; $failed++
        }
    }

    $status = if ($failed -eq 0) { 'Success' } elseif ($processed -gt 0) { 'Warning' } else { 'Failed' }
    Write-Log -Level INFO -Component BLOATWARE -Message "Done: $processed processed, $failed failed"
    return New-ModuleResult -ModuleName 'BloatwareRemoval' -Status $status -ItemsDetected $diff.Count `
        -ItemsProcessed $processed -ItemsFailed $failed -Errors $errors
}

Export-ModuleMember -Function 'Invoke-BloatwareRemoval'






