#Requires -Version 7.0
<#
.SYNOPSIS    Disk Cleanup - Type 2 (system modification)
.DESCRIPTION Clears temp files, browser cache/cookies, Windows Update component store,
             and Recycle Bin contents identified as cleanup candidates by the audit diff.
.NOTES       Module Type: Type2 | DiffKey: DiskCleanup | Version: 5.0
#>

$_corePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'core\Maintenance.psm1'
if (-not (Get-Command 'Write-Log' -ErrorAction SilentlyContinue)) {
    Import-Module $_corePath -Force -Global -WarningAction SilentlyContinue
}

function Invoke-DiskCleanup {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter()][hashtable]$OSContext
    )

    Write-Log -Level INFO -Component DISKCLEAN -Message 'Starting disk cleanup'

    $diff = Get-DiffList -ModuleName 'DiskCleanup'
    if (-not $diff -or $diff.Count -eq 0) {
        Write-Log -Level INFO -Component DISKCLEAN -Message 'Nothing to clean up'
        return New-ModuleResult -ModuleName 'DiskCleanup' -Status 'Skipped' -ModuleType 'Type2' -Message 'No cleanup candidates found'
    }

    $processed = 0; $failed = 0; $errors = @(); $reclaimedMB = 0.0
    $reclaimedByCategory = @{
        'temp' = 0
        'browser-cache' = 0
        'browser-cookies' = 0
        'update-cleanup' = 0
        'recyclebin' = 0
    }

    Write-Log -Level INFO -Component DISKCLEAN -Message "Processing $($diff.Count) cleanup item(s)"

    foreach ($item in $diff) {
        $name = $item.Name ?? "$item"
        $type = $item.Type ?? 'temp'
        try {
            $changed = $false
            switch ($type) {
                { $_ -in 'temp', 'browser-cache' } {
                    $path = $item.Path
                    if ($path -and (Test-Path $path -ErrorAction SilentlyContinue)) {
                        # Delete contents, not the folder itself — recreating a temp/cache
                        # folder with the right permissions is the browser/OS's job, not ours.
                        # Locked files (in-use by a running browser/process) are expected and
                        # non-fatal: partial cleanup of an active cache is still a success.
                        @(Get-ChildItem -Path $path -Force -ErrorAction SilentlyContinue) | ForEach-Object {
                            Remove-Item -Path $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
                        }
                        $remainingMB = 0
                        try {
                            $remainingBytes = (Get-ChildItem -Path $path -Recurse -Force -File -ErrorAction SilentlyContinue |
                                Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
                            if ($remainingBytes) { $remainingMB = [math]::Round($remainingBytes / 1MB, 1) }
                        }
                        catch { }
                        $freedMB = [double]($item.SizeMB ?? 0) - $remainingMB
                        if ($freedMB -lt 0) { $freedMB = 0 }
                        $reclaimedMB += $freedMB
                        if ($type -eq 'temp') { $reclaimedByCategory['temp'] += $freedMB }
                        else { $reclaimedByCategory['browser-cache'] += $freedMB }
                        if ($remainingMB -gt 0) {
                            Write-Log -Level WARN -Component DISKCLEAN -Message "$name`: partially cleared ($freedMB MB freed, $remainingMB MB still locked/in-use)"
                        }
                        else {
                            Write-Log -Level SUCCESS -Component DISKCLEAN -Message "$name`: cleared ($freedMB MB freed)"
                        }
                        $changed = $true
                    }
                }
                'browser-cookies' {
                    $path = $item.Path
                    if ($path -and (Test-Path $path -ErrorAction SilentlyContinue)) {
                        try {
                            Remove-Item -Path $path -Force -ErrorAction Stop
                            $freedMB = [double]($item.SizeMB ?? 0)
                            $reclaimedMB += $freedMB
                            $reclaimedByCategory['browser-cookies'] += $freedMB
                            Write-Log -Level SUCCESS -Component DISKCLEAN -Message "$name`: cookies cleared"
                            $changed = $true
                        }
                        catch {
                            # Locked (browser open) is the common, expected failure mode here.
                            Write-Log -Level WARN -Component DISKCLEAN -Message "$name`: could not remove (likely locked by a running browser): $_"
                        }
                    }
                }
                'update-cleanup' {
                    $dismArgs = @('/Online', '/Cleanup-Image', '/StartComponentCleanup')
                    if ($item.ResetBase) { $dismArgs += '/ResetBase' }
                    $exitCode = Invoke-ExternalPackageCommand -FilePath (Join-Path $env:SystemRoot 'System32\dism.exe') `
                        -ArgumentList $dismArgs -TimeoutSeconds 1800
                    if ($exitCode -eq 0) {
                        $freedMB = [double]($item.SizeMB ?? 0)
                        $reclaimedMB += $freedMB
                        $reclaimedByCategory['update-cleanup'] += $freedMB
                        Write-Log -Level SUCCESS -Component DISKCLEAN -Message 'Windows Update component cleanup completed'
                        $changed = $true
                    }
                    else {
                        Write-Log -Level ERROR -Component DISKCLEAN -Message "DISM component cleanup failed (exit $exitCode)"
                        $errors += "[$name] DISM exit $exitCode"; $failed++
                    }
                }
                'recyclebin' {
                    $drive = $item.Drive
                    if ($drive) {
                        Clear-RecycleBin -DriveLetter $drive.Substring(0, 1) -Force -ErrorAction Stop
                        $freedMB = [double]($item.SizeMB ?? 0)
                        $reclaimedMB += $freedMB
                        $reclaimedByCategory['recyclebin'] += $freedMB
                        Write-Log -Level SUCCESS -Component DISKCLEAN -Message "Recycle Bin cleared: $drive"
                        $changed = $true
                    }
                }
                default {
                    Write-Log -Level WARN -Component DISKCLEAN -Message "Unknown cleanup type '$type' for $name"
                    $errors += "[Unknown type] $name"; $failed++
                }
            }
            if ($changed) { $processed++ }
        }
        catch {
            Write-Log -Level ERROR -Component DISKCLEAN -Message "Failed [$name]: $_"
            $errors += "[$name] $_"; $failed++
        }
    }

    $reclaimedMB = [math]::Round($reclaimedMB, 1)
    @($reclaimedByCategory.Keys) | ForEach-Object { $reclaimedByCategory[$_] = [math]::Round($reclaimedByCategory[$_], 1) }

    $status = if ($failed -eq 0) { 'Success' } elseif ($processed -gt 0) { 'Warning' } else { 'Failed' }
    Write-Log -Level INFO -Component DISKCLEAN -Message "Done: $processed cleaned, $failed failed, ~$reclaimedMB MB reclaimed"
    return New-ModuleResult -ModuleName 'DiskCleanup' -Status $status -ModuleType 'Type2' -ItemsDetected $diff.Count `
        -ItemsProcessed $processed -ItemsFailed $failed -Errors $errors `
        -ExtraData @{
            ReclaimedMB = $reclaimedMB
            BreakdownByCategory = $reclaimedByCategory
        }
}

Export-ModuleMember -Function 'Invoke-DiskCleanup'
