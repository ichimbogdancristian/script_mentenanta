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

# Resolved once per run and cached. $null means "not available" - every caller degrades.
$script:MoveFileExe = $null
$script:MoveFileResolved = $false

<#
.SYNOPSIS
    Lazily acquires Sysinternals MoveFile, or returns $null.
.DESCRIPTION
    Only downloaded when a locked file is actually encountered, so a run that cleans up
    perfectly costs no network at all. Gated by main-config.json -> tools.
.OUTPUTS
    [string] path to movefile.exe, or $null when unavailable/disabled.
#>
function Get-MoveFileTool {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    if ($script:MoveFileResolved) { return $script:MoveFileExe }
    $script:MoveFileResolved = $true

    try {
        $cfg = Get-MainConfig
        if (-not $cfg.tools -or -not $cfg.tools.enabled) { return $null }
        $mf = $cfg.tools.sysinternals.movefile
        if (-not $mf -or -not $mf.enabled -or -not $mf.url) { return $null }

        $null = Initialize-SysinternalsEula
        $script:MoveFileExe = Get-ExternalTool -Name 'movefile' -Url $mf.url
    }
    catch {
        Write-Log -Level WARN -Component DISKCLEAN -Message "MoveFile unavailable (continuing without boot-time deletes): $_"
        $script:MoveFileExe = $null
    }
    return $script:MoveFileExe
}

<#
.SYNOPSIS
    Queues files that could not be deleted for removal at the next boot.
.DESCRIPTION
    Windows exposes MoveFileEx(..., MOVEFILE_DELAY_UNTIL_REBOOT) so an in-use file can be
    replaced or deleted before anything references it. Session Manager executes the queue from
    HKLM\System\CurrentControlSet\Control\Session Manager\PendingFileRenameOperations at next
    boot. Sysinternals MoveFile is the supported CLI for that; an empty destination means
    delete. PowerShell has no equivalent without P/Invoking MoveFileEx.

    This pairs exactly with the Stage 5 reboot: a file queued in Stage 3 is gone minutes later
    in the SAME run, instead of failing again every month forever.

    SAFETY - PendingFileRenameOperations executes as Session Manager with nothing watching and
    no undo, so this refuses anything outside the caller's already-validated cleanup root:
      - the file must currently exist,
      - it must resolve to a path INSIDE $UnderRoot,
      - and that root must not be a system-critical directory.
.OUTPUTS
    [int] number of files successfully queued.
#>
function Add-BootTimeDelete {
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [string[]]$Path,
        [Parameter(Mandatory)] [string]$UnderRoot,
        [Parameter(Mandatory)] [string]$MoveFileExe
    )

    $queued = 0
    try { $rootFull = [System.IO.Path]::GetFullPath($UnderRoot).TrimEnd('\') } catch { return 0 }

    # Never queue deletes under a system-critical root, whatever the diff claims.
    $forbidden = @(
        [System.IO.Path]::GetFullPath($env:SystemRoot).TrimEnd('\')
        [System.IO.Path]::GetFullPath((Join-Path $env:SystemRoot 'System32')).TrimEnd('\')
        [System.IO.Path]::GetFullPath($env:ProgramFiles).TrimEnd('\')
    )
    foreach ($bad in $forbidden) {
        if ($rootFull -eq $bad) {
            Write-Log -Level WARN -Component DISKCLEAN -Message "Refusing boot-time deletes under a system root: $rootFull"
            return 0
        }
    }

    foreach ($p in $Path) {
        if (-not $p) { continue }
        try {
            if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { continue }
            $full = [System.IO.Path]::GetFullPath($p)
            if (-not $full.StartsWith($rootFull + '\', [StringComparison]::OrdinalIgnoreCase)) {
                Write-Log -Level DEBUG -Component DISKCLEAN -Message "Skipped (outside cleanup root): $full"
                continue
            }
            # Empty destination = delete at boot. Both arguments are quoted for spaces.
            $exit = Invoke-ExternalPackageCommand -FilePath $MoveFileExe `
                -ArgumentList @('-accepteula', "`"$full`"", '""') -TimeoutSeconds 30
            if ($exit -eq 0) { $queued++ }
            else { Write-Log -Level DEBUG -Component DISKCLEAN -Message "MoveFile exit $exit for $full" }
        }
        catch {
            Write-Log -Level DEBUG -Component DISKCLEAN -Message "Could not queue '$p': $_"
        }
    }
    return $queued
}

function Invoke-DiskCleanup {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter()][hashtable]$OSContext
    )

    $null = $OSContext  # Type2 interface parameter, may be used by future optimizations
    Write-Log -Level INFO -Component DISKCLEAN -Message 'Starting disk cleanup'

    $diff = Get-DiffList -ModuleName 'DiskCleanup'
    if (-not $diff -or $diff.Count -eq 0) {
        Write-Log -Level INFO -Component DISKCLEAN -Message 'Nothing to clean up'
        return New-ModuleResult -ModuleName 'DiskCleanup' -Status 'Skipped' -ModuleType 'Type2' -Message 'No cleanup candidates found'
    }

    $processed = 0; $failed = 0; $errors = @(); $reclaimedMB = 0.0; $rebootRequired = $false
    $bootQueued = 0   # files handed to MoveFile for deletion at next boot
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

                            # Whatever survived the delete pass is locked by a running process.
                            # Queue it for boot-time deletion so it actually goes away in THIS
                            # run (Stage 5 reboots), instead of failing identically every month.
                            $mfExe = Get-MoveFileTool
                            if ($mfExe) {
                                $stuck = @(Get-ChildItem -Path $path -Recurse -Force -File -ErrorAction SilentlyContinue |
                                        Select-Object -ExpandProperty FullName)
                                if ($stuck.Count -gt 0) {
                                    $queued = Add-BootTimeDelete -Path $stuck -UnderRoot $path -MoveFileExe $mfExe
                                    if ($queued -gt 0) {
                                        # MUST set RebootRequired: the queued deletes only happen
                                        # on reboot, and with rebootOnlyWhenRequired set Stage 5
                                        # would otherwise skip the reboot and leave them pending
                                        # for a month. Same class as the 3010 exit-code fix.
                                        $rebootRequired = $true
                                        $bootQueued += $queued
                                        Write-Log -Level INFO -Component DISKCLEAN `
                                            -Message "$name`: queued $queued locked file(s) for deletion at next boot"
                                    }
                                }
                            }
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
                    # DISM /StartComponentCleanup hard-fails with 0x800F0806 whenever a prior
                    # servicing operation (most commonly a .NET update) is waiting on a reboot
                    # to finish - retrying without rebooting just repeats the same failure
                    # every run. Check up front and defer to Stage 5's reboot instead of
                    # logging a hard error for a condition only a reboot can resolve.
                    if (Test-CbsRebootPending) {
                        Write-Log -Level INFO -Component DISKCLEAN -Message "$name`: skipped - a reboot is already pending from a prior servicing operation; component cleanup will retry after Stage 5 reboots"
                        $rebootRequired = $true
                    }
                    else {
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
                        elseif ($exitCode -eq -2146498554) {
                            # 0x800F0806 slipped past the upfront check (a servicing operation
                            # started mid-run) - same non-fatal defer, not a real failure.
                            Write-Log -Level WARN -Component DISKCLEAN -Message "$name`: DISM reported pending operations (0x800F0806) - will retry after a reboot"
                            $rebootRequired = $true
                        }
                        else {
                            Write-Log -Level ERROR -Component DISKCLEAN -Message "DISM component cleanup failed (exit $exitCode)"
                            $errors += "[$name] DISM exit $exitCode"; $failed++
                        }
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
    Write-Log -Level INFO -Component DISKCLEAN -Message "Done: $processed cleaned, $failed failed, ~$reclaimedMB MB reclaimed$(if ($rebootRequired) { ' (component cleanup deferred - reboot pending)' })"
    return New-ModuleResult -ModuleName 'DiskCleanup' -Status $status -ModuleType 'Type2' -ItemsDetected $diff.Count `
        -ItemsProcessed $processed -ItemsFailed $failed -Errors $errors -RebootRequired $rebootRequired `
        -ExtraData @{
            ReclaimedMB = $reclaimedMB
            BreakdownByCategory = $reclaimedByCategory
            BootTimeDeletesQueued = $bootQueued
        }
}

Export-ModuleMember -Function 'Invoke-DiskCleanup'
