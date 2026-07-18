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

function Test-UpdateAlreadyInstalled {
    param([string]$KBNumber)

    # Layer 1: Try Get-CimInstance Win32_QuickFixEngineering (installed updates)
    try {
        $installed = Get-CimInstance -ClassName Win32_QuickFixEngineering -ErrorAction SilentlyContinue |
            Where-Object { $_.HotFixID -match $KBNumber }
        if ($installed) {
            return $true
        }
    }
    catch {
        Write-Log -Level DEBUG -Component WINUPDATE -Message "Layer 1 check failed: $_"
    }

    # Layer 2: Try registry HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall
    try {
        $regKey = Get-ChildItem -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall' -ErrorAction SilentlyContinue |
            Where-Object { $_.GetValue('DisplayName') -match $KBNumber }
        if ($regKey) {
            return $true
        }
    }
    catch {
        Write-Log -Level DEBUG -Component WINUPDATE -Message "Layer 2 check failed: $_"
    }

    return $false
}

function Test-UpdateIsInstalled {
    param([string]$KBNumber)

    $waitTime = 5
    Write-Log -Level DEBUG -Component WINUPDATE -Message "Verifying update installation... (waiting ${waitTime}s)"
    Start-Sleep -Seconds $waitTime

    # Try Layer 1: Quick Fix Engineering
    try {
        $installed = Get-CimInstance -ClassName Win32_QuickFixEngineering -ErrorAction SilentlyContinue |
            Where-Object { $_.HotFixID -match $KBNumber }
        if ($installed) {
            Write-Log -Level DEBUG -Component WINUPDATE -Message "✓ Verification Layer 1 success: Found in Quick Fix Engineering"
            return $true
        }
    }
    catch {
        Write-Log -Level DEBUG -Component WINUPDATE -Message "Verification Layer 1 failed: $_"
    }

    # Try Layer 2: Registry
    try {
        $regKey = Get-ChildItem -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall' -ErrorAction SilentlyContinue |
            Where-Object { $_.GetValue('DisplayName') -match $KBNumber }
        if ($regKey) {
            Write-Log -Level DEBUG -Component WINUPDATE -Message "✓ Verification Layer 2 success: Found in registry"
            return $true
        }
    }
    catch {
        Write-Log -Level DEBUG -Component WINUPDATE -Message "Verification Layer 2 failed: $_"
    }

    Write-Log -Level WARN -Component WINUPDATE -Message "⚠ Update not verified in system (may still be installing)"
    return $false
}

function Invoke-WindowsUpdate {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter()][hashtable]$OSContext
    )

    $null = $OSContext  # Type2 interface parameter, may be used by future optimizations
    Write-Log -Level INFO -Component WINUPDATE -Message 'Starting Windows updates installation'

    $diff = Get-DiffList -ModuleName 'WindowsUpdates'
    if (-not $diff -or $diff.Count -eq 0) {
        Write-Log -Level INFO -Component WINUPDATE -Message 'No pending updates found'
        return New-ModuleResult -ModuleName 'WindowsUpdates' -Status 'Skipped' -Message 'System is up to date'
    }

    $processed = 0; $failed = 0; $errors = @(); $rebootRequired = $false

    Write-Log -Level INFO -Component WINUPDATE -Message "Installing $($diff.Count) update(s)"

    # Primary: PSWindowsUpdate — installs by KB ID and confirms result
    $pswuAvailable = $null -ne (Get-Module -ListAvailable -Name 'PSWindowsUpdate' -ErrorAction SilentlyContinue)
    if ($pswuAvailable) {
        try {
            Import-Module PSWindowsUpdate -SkipEditionCheck -ErrorAction Stop
            foreach ($update in $diff) {
                $title = $update.Title ?? $update.Name ?? "$update"
                $kb = if ($title -match 'KB(\d+)') { $Matches[1] } else { $null }
                $updateId = $update.Identity ?? ''

                Write-Log -Level INFO -Component WINUPDATE -Message "Processing: $title"

                # Pre-check: Is it already installed?
                if ($kb -and (Test-UpdateInstalled -KBNumber $kb)) {
                    Write-Log -Level INFO -Component WINUPDATE -Message "Already installed, skipping: $title"
                    $processed++
                    continue
                }

                try {
                    if ($kb) {
                        $result = Install-WindowsUpdate -KBArticleID $kb -AcceptAll -AutoReboot:$false -IgnoreReboot -Confirm:$false -ErrorAction Stop
                    }
                    elseif ($updateId) {
                        $result = Install-WindowsUpdate -UpdateID $updateId -AcceptAll -AutoReboot:$false -IgnoreReboot -Confirm:$false -ErrorAction Stop
                    }
                    else {
                        Write-Log -Level WARN -Component WINUPDATE -Message "No KB number or update ID — skipping: $title"
                        $failed++
                        $errors += "[No ID] $title"
                        continue
                    }

                    if ($result -and ($result | Where-Object { $_.Result -eq 'Failed' })) {
                        Write-Log -Level ERROR -Component WINUPDATE -Message "Install reported failure: $title"
                        $errors += "[Failed] $title"
                        $failed++
                    }
                    else {
                        # Post-check: Verify installation succeeded
                        if ($kb -and (Test-UpdateIsInstalled -KBNumber $kb)) {
                            Write-Log -Level SUCCESS -Component WINUPDATE -Message "Installed and verified: $title"
                            $processed++
                        }
                        else {
                            Write-Log -Level WARN -Component WINUPDATE -Message "Installation not immediately verified (may still be installing): $title"
                            $processed++
                        }
                    }

                    if ($result -and ($result | Where-Object { $_.RebootRequired })) { $rebootRequired = $true }
                }
                catch {
                    Write-Log -Level ERROR -Component WINUPDATE -Message "PSWindowsUpdate failed [$title]: $_"
                    $errors += "[$title] $_"
                    $failed++
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
        Write-Log -Level WARN -Component WINUPDATE -Message "Triggering usoclient to install $($diff.Count) update(s) (async — results unverifiable)"
        $usoClient = Join-Path $env:SystemRoot 'System32\usoclient.exe'
        $null = & $usoClient StartScan 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Log -Level WARN -Component WINUPDATE -Message "usoclient StartScan failed with exit code $LASTEXITCODE"
        }
        Start-Sleep -Seconds 2
        $null = & $usoClient StartInstall 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Log -Level WARN -Component WINUPDATE -Message "usoclient StartInstall failed with exit code $LASTEXITCODE"
        }
        $processed = $diff.Count
        $rebootRequired = $true
        Write-Log -Level INFO -Component WINUPDATE -Message "usoclient triggered $processed update(s) — reboot expected"
    }

    $extraData = @{ RebootRequired = $rebootRequired; UsedUsoclient = (-not $pswuAvailable) }
    if ($rebootRequired) {
        Write-Log -Level WARN -Component WINUPDATE -Message 'One or more updates require a reboot'
    }

    $status = if (-not $pswuAvailable) { 'Warning' } elseif ($failed -eq 0) { 'Success' } elseif ($processed -gt 0) { 'Warning' } else { 'Failed' }
    Write-Log -Level INFO -Component WINUPDATE -Message "Done: $processed triggered/installed, $failed failed"
    return New-ModuleResult -ModuleName 'WindowsUpdates' -Status $status -ItemsDetected $diff.Count `
        -ItemsProcessed $processed -ItemsFailed $failed -RebootRequired $rebootRequired `
        -Errors $errors -ExtraData $extraData
}

Export-ModuleMember -Function 'Invoke-WindowsUpdate'
