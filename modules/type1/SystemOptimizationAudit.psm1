#Requires -Version 7.0
<#
.SYNOPSIS    System Optimization Audit - Type 1
.DESCRIPTION Audits services, startup programs, and power plan against the optimization baseline.
             Diff = settings that differ from desired state.
.NOTES       Module Type: Type1 | DiffKey: SystemOptimization | Version: 5.0
#>

$_corePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'core\Maintenance.psm1'
if (-not (Get-Command 'Write-Log' -ErrorAction SilentlyContinue)) {
    Import-Module $_corePath -Force -Global -WarningAction SilentlyContinue
}

function Invoke-SystemOptimizationAudit {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    Write-Log -Level INFO -Component SYSOPT-AUDIT -Message 'Starting system optimization audit'

    try {
        # 1. Load baseline
        $baseline = Get-BaselineList -ModuleFolder 'system-optimization' -FileName 'system-optimization-config.json'
        if (-not $baseline) {
            return New-ModuleResult -ModuleName 'SystemOptimizationAudit' -Status 'Failed' `
                                    -Message 'System optimization baseline not found'
        }

        $osCtx  = if ($global:OSContext) { $global:OSContext } else { Get-OSContext }
        $diff   = [System.Collections.Generic.List[hashtable]]::new()

        # 2. Audit services that should be disabled
        $svcsToDisable = [System.Collections.Generic.List[string]]::new()
        if ($baseline.common.services.safeToDisable) { $baseline.common.services.safeToDisable | ForEach-Object { $svcsToDisable.Add($_) } }
        if ($osCtx.IsWindows11 -and $baseline.windows11.services.safeToDisable) {
            $baseline.windows11.services.safeToDisable | ForEach-Object { $svcsToDisable.Add($_) }
        }
        elseif (-not $osCtx.IsWindows11 -and $baseline.windows10.services.safeToDisable) {
            $baseline.windows10.services.safeToDisable | ForEach-Object { $svcsToDisable.Add($_) }
        }

        foreach ($svcName in $svcsToDisable) {
            try {
                $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
                if ($svc -and $svc.StartType -ne 'Disabled') {
                    $diff.Add(@{ Type = 'Service'; Name = $svcName; CurrentState = $svc.StartType.ToString(); DesiredState = 'Disabled' })
                    Write-Log -Level DEBUG -Component SYSOPT-AUDIT -Message "Service needs disable: $svcName ($($svc.StartType))"
                }
            }
            catch { Write-Log -Level WARN -Component SYSOPT-AUDIT -Message "Service query failed for $svcName" }
        }

        # 3. Audit power plan
        if ($baseline.common.powerPlan.defaultPlan) {
            $desiredPlan = $baseline.common.powerPlan.defaultPlan
            try {
                $currentPlan = & powercfg /getactivescheme 2>&1
                if ($currentPlan -notmatch [regex]::Escape($desiredPlan)) {
                    $diff.Add(@{ Type = 'PowerPlan'; Name = 'ActivePlan'; CurrentState = $currentPlan; DesiredState = $desiredPlan })
                    Write-Log -Level DEBUG -Component SYSOPT-AUDIT -Message "Power plan mismatch: desired '$desiredPlan'"
                }
            }
            catch { Write-Log -Level WARN -Component SYSOPT-AUDIT -Message "Power plan query failed: $_" }
        }

        # 4. Audit visual effects (check registry)
        $visualAudioPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects'
        $currentVisual   = Get-RegistryValue -Path $visualAudioPath -Name 'VisualFXSetting'
        if ($null -ne $currentVisual -and $currentVisual -ne 2) {
            # 2 = custom / performance; anything else means potentially max effects
            $diff.Add(@{ Type = 'VisualFX'; Name = 'VisualFXSetting'; CurrentState = $currentVisual; DesiredState = 2 })
        }

        Write-Log -Level INFO -Component SYSOPT-AUDIT -Message "Optimization gaps: $($diff.Count)"

        # 5. Save diff
        Save-DiffList -ModuleName 'SystemOptimization' -DiffList $diff.ToArray()

        # 6. Persist audit data
        $auditPath = Get-TempPath -Category 'data' -FileName 'sysopt-audit.json'
        @{ Timestamp = (Get-Date -Format 'o'); Gaps = $diff.ToArray(); OS = $osCtx.DisplayText } `
            | ConvertTo-Json -Depth 6 | Set-Content -Path $auditPath -Encoding UTF8 -Force

        Write-Log -Level SUCCESS -Component SYSOPT-AUDIT -Message "System optimization audit complete: $($diff.Count) gaps"
        return New-ModuleResult -ModuleName 'SystemOptimizationAudit' -Status 'Success' `
                                -ItemsDetected $diff.Count `
                                -Message "$($diff.Count) optimization settings need adjustment"
    }
    catch {
        Write-Log -Level ERROR -Component SYSOPT-AUDIT -Message "Audit failed: $_"
        return New-ModuleResult -ModuleName 'SystemOptimizationAudit' -Status 'Failed' -Errors @($_.ToString())
    }
}

Export-ModuleMember -Function 'Invoke-SystemOptimizationAudit'
