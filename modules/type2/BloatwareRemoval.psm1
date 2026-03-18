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

<#
.SYNOPSIS
    Removes bloatware applications identified by the Type1 audit.
.DESCRIPTION
    Reads the BloatwareRemoval diff list, removes matching AppX packages (all users
    and provisioned), and falls back to winget uninstall for legacy apps.
.PARAMETER OSContext
    OS context hashtable from Get-OSContext. Falls back to the session global if omitted.
.OUTPUTS
    [hashtable] Standard module result from New-ModuleResult.
#>
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

    $osCtx = if ($OSContext) { $OSContext } elseif (Test-Path variable:global:OSContext) { $global:OSContext } else { Get-OSContext }
    $processed = 0; $failed = 0; $errors = @()

    # PS7: Try loading Appx module; detect if AppX cmdlets actually work on this platform
    $appxAvailable = $false
    try {
        if ($PSVersionTable.PSEdition -eq 'Core') {
            Import-Module -Name Appx -SkipEditionCheck -ErrorAction Stop
        }
        $null = Get-AppxPackage -Name 'NonExistentProbePackage' -ErrorAction Stop
        $appxAvailable = $true
    }
    catch {
        Write-Log -Level WARN -Component BLOATWARE -Message "Appx module not usable in PS7 — will fall back to powershell.exe for AppX operations"
    }

    Write-Log -Level INFO -Component BLOATWARE -Message "Processing $($diff.Count) item(s) on $($osCtx.DisplayText)"

    foreach ($item in $diff) {
        # Diff items may be plain strings (package names) or hashtables
        $isString = $item -is [string]
        $name = if ($isString) { $item } else { $item.Name ?? $item.PackageName ?? "$item" }
        $pkgName = if ($isString) { $item } else { $item.PackageName ?? $item.AppxName ?? $item.Name ?? '' }
        $wingetId = if ($isString) { '' }    else { $item.WingetId ?? '' }

        try {
            $removed = $false

            # 1. AppX removal
            if ($pkgName) {
                if ($appxAvailable) {
                    # Direct AppX cmdlets work on this platform
                    $pkg = Get-AppxPackage -AllUsers -Name "*$pkgName*" -ErrorAction SilentlyContinue
                    if (-not $pkg) { $pkg = Get-AppxPackage -Name "*$pkgName*" -ErrorAction SilentlyContinue }
                    if ($pkg) {
                        if ($PSCmdlet.ShouldProcess($pkgName, 'Remove-AppxPackage')) {
                            $pkg | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
                            $pkg | Remove-AppxPackage -ErrorAction SilentlyContinue
                            Write-Log -Level SUCCESS -Component BLOATWARE -Message "Removed AppX: $pkgName"
                            $removed = $true
                        }
                    }
                    try {
                        $prov = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
                        Where-Object { $_.PackageName -like "*$pkgName*" }
                        if ($prov -and $PSCmdlet.ShouldProcess($pkgName, 'Remove provisioned')) {
                            $prov | ForEach-Object {
                                $null = Remove-AppxProvisionedPackage -Online -PackageName $_.PackageName -ErrorAction SilentlyContinue
                            }
                        }
                    }
                    catch { Write-Log -Level WARN -Component BLOATWARE -Message "Provisioned package removal skipped for '$pkgName': $_" }
                }
                else {
                    # Fallback: delegate AppX removal to Windows PowerShell 5.1
                    if ($PSCmdlet.ShouldProcess($pkgName, 'Remove-AppxPackage (WinPS fallback)')) {
                        $fallbackScript = @"
`$pkg = Get-AppxPackage -AllUsers -Name '*$pkgName*' -ErrorAction SilentlyContinue
if (-not `$pkg) { `$pkg = Get-AppxPackage -Name '*$pkgName*' -ErrorAction SilentlyContinue }
if (`$pkg) {
    `$pkg | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
    `$pkg | Remove-AppxPackage -ErrorAction SilentlyContinue
    Write-Output 'REMOVED'
}
Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
    Where-Object { `$_.PackageName -like '*$pkgName*' } |
    ForEach-Object { Remove-AppxProvisionedPackage -Online -PackageName `$_.PackageName -ErrorAction SilentlyContinue }
"@
                        $result = & powershell.exe -NoProfile -Command $fallbackScript 2>$null
                        if ($result -contains 'REMOVED') {
                            Write-Log -Level SUCCESS -Component BLOATWARE -Message "Removed AppX (WinPS fallback): $pkgName"
                            $removed = $true
                        }
                    }
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

            if ($removed) { $processed++ }
            else { Write-Log -Level WARN -Component BLOATWARE -Message "Not found to remove: $name" }
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






