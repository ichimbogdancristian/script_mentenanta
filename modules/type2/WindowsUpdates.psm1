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

    if ($PSCmdlet.ShouldProcess('Windows Updates', 'Install pending updates')) {
        # Primary: PSWindowsUpdate — installs by KB ID and confirms result
        $pswuAvailable = $null -ne (Get-Module -ListAvailable -Name 'PSWindowsUpdate' -ErrorAction SilentlyContinue)
        if ($pswuAvailable) {
            try {
                Import-Module PSWindowsUpdate -SkipEditionCheck -ErrorAction Stop
                foreach ($update in $diff) {
                    $title = $update.Title ?? $update.Name ?? "$update"
                    Write-Log -Level INFO -Component WINUPDATE -Message "Processing: $title"
                    try {
                        $kb = if ($title -match 'KB(\d+)') { $Matches[1] } else { $null }
                        if (-not $kb) {
                            Write-Log -Level WARN -Component WINUPDATE -Message "No KB number in title — skipping: $title"
                            $failed++; $errors += "[No KB] $title"; continue
                        }
                        $result = Install-WindowsUpdate -KBArticleID $kb -AcceptAll -AutoReboot:$false -IgnoreReboot -Confirm:$false -ErrorAction Stop
                        Write-Log -Level SUCCESS -Component WINUPDATE -Message "Installed: $title"
                        if ($result | Where-Object { $_.RebootRequired }) { $rebootRequired = $true }
                        $processed++
                    }
                    catch {
                        Write-Log -Level ERROR -Component WINUPDATE -Message "PSWindowsUpdate failed [$title]: $_"
                        $errors += "[$title] $_"; $failed++
                    }
                }
            }
            catch {
                Write-Log -Level WARN -Component WINUPDATE -Message "PSWindowsUpdate module error: $_. Falling back to usoclient."
                $pswuAvailable = $false
            }
        }

        if (-not $pswuAvailable) {
            # Fallback: usoclient — async, triggers WU service to scan+install all pending at once
            Write-Log -Level INFO -Component WINUPDATE -Message "Triggering usoclient to install $($diff.Count) update(s) (async — reboot may be required)"
            $usoClient = Join-Path $env:SystemRoot 'System32\usoclient.exe'
            $null = & $usoClient StartScan 2>&1
            Start-Sleep -Seconds 2
            $null = & $usoClient StartInstall 2>&1
            $processed = $diff.Count
        }
    }

    $extraData = @{ RebootRequired = $rebootRequired }
    if ($rebootRequired) {
        Write-Log -Level WARN -Component WINUPDATE -Message 'One or more updates require a reboot'
    }

    $status = if ($failed -eq 0) { 'Success' } elseif ($processed -gt 0) { 'Warning' } else { 'Failed' }
    Write-Log -Level INFO -Component WINUPDATE -Message "Done: $processed triggered/installed, $failed failed"
    return New-ModuleResult -ModuleName 'WindowsUpdates' -Status $status -ItemsDetected $diff.Count `
        -ItemsProcessed $processed -ItemsFailed $failed -Errors $errors -ExtraData $extraData
}

Export-ModuleMember -Function 'Invoke-WindowsUpdate'
