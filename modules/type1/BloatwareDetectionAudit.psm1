#Requires -Version 7.0
<#
.SYNOPSIS    Bloatware Detection Audit - Type 1
.DESCRIPTION Scans installed apps against the bloatware baseline list.
             Saves diff (items to remove) to temp_files/diff/BloatwareRemoval-diff.json.
.NOTES       Module Type: Type1 | DiffKey: BloatwareRemoval | Version: 5.0
#>

$_corePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'core\Maintenance.psm1'
if (-not (Get-Command 'Write-Log' -ErrorAction SilentlyContinue)) {
    Import-Module $_corePath -Force -Global -WarningAction SilentlyContinue
}

function Invoke-BloatwareAudit {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    Write-Log -Level INFO -Component BLOAT-AUDIT -Message 'Starting bloatware detection'

    try {
        # 1. Load baseline
        $baseline = Get-BaselineList -ModuleFolder 'bloatware' -FileName 'bloatware-list.json'
        if (-not $baseline) {
            return New-ModuleResult -ModuleName 'BloatwareDetectionAudit' -Status 'Failed' `
                                    -Message 'Bloatware baseline list not found'
        }

        # 2. OS-aware baseline (common + OS-specific entries)
        $osCtx  = if ($global:OSContext) { $global:OSContext } else { Get-OSContext }
        $allBaseline = [System.Collections.Generic.List[string]]::new()
        if ($baseline.common) { $baseline.common | ForEach-Object { $allBaseline.Add($_) } }
        if ($osCtx.IsWindows11 -and $baseline.windows11) {
            $baseline.windows11 | ForEach-Object { $allBaseline.Add($_) }
        }
        elseif (-not $osCtx.IsWindows11 -and $baseline.windows10) {
            $baseline.windows10 | ForEach-Object { $allBaseline.Add($_) }
        }
        Write-Log -Level INFO -Component BLOAT-AUDIT -Message "Baseline entries: $($allBaseline.Count) (OS: $($osCtx.DisplayText))"

        # 3. Scan AppX packages (primary source for bloatware)
        $appxInstalled = @(Get-AppxPackage -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name)

        # 4. Diff: baseline apps that ARE installed (need removal)
        $diff = $allBaseline | Where-Object {
            $b = $_.ToLowerInvariant()
            $appxInstalled | Where-Object { $_.ToLowerInvariant() -eq $b -or
                                            $_.ToLowerInvariant().StartsWith($b) }
        } | Select-Object -Unique

        # 5. Also check registry-installed programs
        $regApps = Get-InstalledApp | ForEach-Object { $_.Name }
        $regDiff = $allBaseline | Where-Object {
            $b = $_.ToLowerInvariant()
            $regApps | Where-Object { $_ -and $_.ToLowerInvariant() -like "*$b*" }
        } | Select-Object -Unique

        $combined = @(@($diff) + @($regDiff)) | Select-Object -Unique
        Write-Log -Level INFO -Component BLOAT-AUDIT -Message "Bloatware found: $($combined.Count)"

        # 6. Save diff
        Save-DiffList -ModuleName 'BloatwareRemoval' -DiffList @($combined)

        # 7. Persist audit data
        $auditPath = Get-TempPath -Category 'data' -FileName 'bloatware-audit.json'
        @{ Timestamp = (Get-Date -Format 'o'); Found = @($combined); BaselineCount = $allBaseline.Count } `
            | ConvertTo-Json -Depth 5 | Set-Content -Path $auditPath -Encoding UTF8 -Force

        Write-Log -Level SUCCESS -Component BLOAT-AUDIT -Message "Bloatware detection complete: $($combined.Count) found"
        return New-ModuleResult -ModuleName 'BloatwareDetectionAudit' -Status 'Success' `
                                -ItemsDetected $combined.Count `
                                -Message "Found $($combined.Count) bloatware items on $($osCtx.DisplayText)"
    }
    catch {
        Write-Log -Level ERROR -Component BLOAT-AUDIT -Message "Audit failed: $_"
        return New-ModuleResult -ModuleName 'BloatwareDetectionAudit' -Status 'Failed' -Errors @($_.ToString())
    }
}

Export-ModuleMember -Function 'Invoke-BloatwareAudit'
