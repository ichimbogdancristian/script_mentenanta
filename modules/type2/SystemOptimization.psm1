#Requires -Version 7.0
<#
.SYNOPSIS    System Optimization - Type 2 (system modification)
.DESCRIPTION Applies service startup changes, power plan, and visual effects settings
             identified as non-compliant during the audit diff.
.NOTES       Module Type: Type2 | DiffKey: SystemOptimization | Version: 5.0
#>

$_corePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'core\Maintenance.psm1'
if (-not (Get-Command 'Write-Log' -ErrorAction SilentlyContinue)) {
    Import-Module $_corePath -Force -Global -WarningAction SilentlyContinue
}

function Invoke-SystemOptimization {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([hashtable])]
    param(
        [Parameter()][hashtable]$OSContext
    )

    Write-Log -Level INFO -Component SYSOPT -Message 'Starting system optimization'

    $diff = Get-DiffList -ModuleName 'SystemOptimization'
    if (-not $diff -or $diff.Count -eq 0) {
        Write-Log -Level INFO -Component SYSOPT -Message 'System already optimized'
        return New-ModuleResult -ModuleName 'SystemOptimization' -Status 'Skipped' -Message 'No changes needed'
    }

    $osCtx     = if ($OSContext) { $OSContext } elseif ($global:OSContext) { $global:OSContext } else { Get-OSContext }
    $processed = 0; $failed = 0; $errors = @()

    Write-Log -Level INFO -Component SYSOPT -Message "Applying $($diff.Count) optimization(s) on $($osCtx.DisplayText)"

    foreach ($item in $diff) {
        $name = $item.Name ?? "$item"
        $type = $item.Type ?? 'registry'
        try {
            switch ($type) {
                'service' {
                    $svc   = $item.ServiceName ?? $item.Name
                    $start = $item.DesiredStartType ?? 'Disabled'
                    if ($PSCmdlet.ShouldProcess($svc, "Set-Service -StartupType $start")) {
                        Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
                        Set-Service -Name $svc -StartupType $start -ErrorAction Stop
                        Write-Log -Level SUCCESS -Component SYSOPT -Message "Service '$svc' -> $start"
                    }
                }
                'powerplan' {
                    $planGuid = $item.GUID ?? '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'  # High performance
                    if ($PSCmdlet.ShouldProcess("Power plan $planGuid", 'powercfg')) {
                        $null = & powercfg /setactive $planGuid 2>&1
                        Write-Log -Level SUCCESS -Component SYSOPT -Message "Power plan set to GUID $planGuid"
                    }
                }
                'registry' {
                    $path  = $item.Path ?? $item.RegistryPath
                    $vname = $item.ValueName ?? $item.Name
                    $val   = $item.DesiredValue
                    $vtype = $item.ValueType ?? 'DWord'
                    if ($path -and $null -ne $val) {
                        if ($PSCmdlet.ShouldProcess("$path\$vname", "Set $val")) {
                            Set-RegistryValue -Path $path -Name $vname -Value $val -Type $vtype
                            Write-Log -Level SUCCESS -Component SYSOPT -Message "Registry set: $path\$vname = $val"
                        }
                    }
                }
                'visualfx' {
                    # Set to best performance visual effects (UserPreferencesMask)
                    if ($PSCmdlet.ShouldProcess('VisualFX', 'Set best performance')) {
                        $regPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects'
                        Set-RegistryValue -Path $regPath -Name 'VisualFXSetting' -Value 2 -Type DWord
                        Write-Log -Level SUCCESS -Component SYSOPT -Message 'Visual effects set to best performance'
                    }
                }
                default {
                    Write-Log -Level WARN -Component SYSOPT -Message "Unknown optimization type '$type' for $name"
                }
            }
            $processed++
        }
        catch {
            Write-Log -Level ERROR -Component SYSOPT -Message "Failed [$name / $type]: $_"
            $errors += "[$name] $_"; $failed++
        }
    }

    $status = if ($failed -eq 0) { 'Success' } elseif ($processed -gt 0) { 'Warning' } else { 'Failed' }
    Write-Log -Level INFO -Component SYSOPT -Message "Done: $processed applied, $failed failed"
    return New-ModuleResult -ModuleName 'SystemOptimization' -Status $status -ItemsDetected $diff.Count `
                            -ItemsProcessed $processed -ItemsFailed $failed -Errors $errors
}

Export-ModuleMember -Function 'Invoke-SystemOptimization'
