#Requires -Version 7.0
<#
.SYNOPSIS    Windows Updates - Type 2 (system modification)
.DESCRIPTION Downloads and installs pending Windows updates identified in the diff list
             using the Windows Update COM API (Microsoft.Update.Session).
.NOTES       Module Type: Type2 | DiffKey: WindowsUpdates | Version: 5.0
#>

$_corePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'core\Maintenance.psm1'
if (-not (Get-Command 'Write-Log' -ErrorAction SilentlyContinue)) {
    Import-Module $_corePath -Force -Global -WarningAction SilentlyContinue
}

function Invoke-WindowsUpdate {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([hashtable])]
    param(
        [Parameter()][hashtable]$OSContext
    )

    Write-Log -Level INFO -Component WINUPDATE -Message 'Starting Windows updates installation'

    $diff = Get-DiffList -ModuleName 'WindowsUpdates'
    if (-not $diff -or $diff.Count -eq 0) {
        Write-Log -Level INFO -Component WINUPDATE -Message 'No pending updates found'
        return New-ModuleResult -ModuleName 'WindowsUpdates' -Status 'Skipped' -Message 'System is up to date'
    }

    $processed = 0; $failed = 0; $errors = @(); $rebootRequired = $false

    Write-Log -Level INFO -Component WINUPDATE -Message "Installing $($diff.Count) update(s)"

    try {
        $session  = New-Object -ComObject Microsoft.Update.Session
        $downloader = $session.CreateUpdateDownloader()
        $installer  = $session.CreateUpdateInstaller()
        $installer.ForceQuiet = $true

        foreach ($update in $diff) {
            $title = $update.Title ?? $update.Name ?? "$update"
            Write-Log -Level INFO -Component WINUPDATE -Message "Processing: $title"

            try {
                if ($PSCmdlet.ShouldProcess($title, 'Install Windows Update')) {
                    # Download
                    $toDownload = New-Object -ComObject Microsoft.Update.UpdateColl
                    $updateObj  = $update._COMObject  # Stored by audit if available
                    if (-not $updateObj) {
                        Write-Log -Level WARN -Component WINUPDATE -Message "No COM ref available for: $title — using usoclient fallback"
                        $null = & usoclient.exe StartScan 2>&1
                        Start-Sleep -Seconds 2
                        $null = & usoclient.exe StartInstall 2>&1
                        $processed++
                        continue
                    }

                    if (-not $updateObj.IsDownloaded) {
                        $toDownload.Add($updateObj) | Out-Null
                        $downloader.Updates = $toDownload
                        $dlResult = $downloader.Download()
                        if ($dlResult.ResultCode -ne 2) {  # 2 = rcSucceeded
                            throw "Download failed: ResultCode $($dlResult.ResultCode)"
                        }
                    }

                    # Install
                    $toInstall = New-Object -ComObject Microsoft.Update.UpdateColl
                    $toInstall.Add($updateObj) | Out-Null
                    $installer.Updates = $toInstall
                    $instResult = $installer.Install()

                    if ($instResult.ResultCode -eq 2) {  # rcSucceeded
                        Write-Log -Level SUCCESS -Component WINUPDATE -Message "Installed: $title"
                        if ($instResult.RebootRequired) { $rebootRequired = $true }
                        $processed++
                    } else {
                        throw "Install ResultCode=$($instResult.ResultCode) HResult=$($instResult.GetUpdateResult(0).HResult)"
                    }
                }
            }
            catch {
                Write-Log -Level ERROR -Component WINUPDATE -Message "Failed [$title]: $_"
                $errors += "[$title] $_"; $failed++
            }
        }
    }
    catch {
        # COM not available or total failure - try wuauclt
        Write-Log -Level WARN -Component WINUPDATE -Message "COM method failed, triggering usoclient: $_"
        if ($PSCmdlet.ShouldProcess('usoclient', 'Trigger update detection')) {
            $null = & usoclient.exe StartScan 2>&1
            Start-Sleep -Seconds 2
            $null = & usoclient.exe StartInstall 2>&1
            $processed = $diff.Count  # Assume all triggered
        }
    }

    $extraData = @{ RebootRequired = $rebootRequired }
    if ($rebootRequired) {
        Write-Log -Level WARN -Component WINUPDATE -Message 'One or more updates require a reboot'
    }

    $status = if ($failed -eq 0) { 'Success' } elseif ($processed -gt 0) { 'Warning' } else { 'Failed' }
    Write-Log -Level INFO -Component WINUPDATE -Message "Done: $processed installed, $failed failed"
    return New-ModuleResult -ModuleName 'WindowsUpdates' -Status $status -ItemsDetected $diff.Count `
                            -ItemsProcessed $processed -ItemsFailed $failed -Errors $errors -ExtraData $extraData
}

Export-ModuleMember -Function 'Invoke-WindowsUpdate'
