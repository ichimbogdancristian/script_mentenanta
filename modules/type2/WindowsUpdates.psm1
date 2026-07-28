#Requires -Version 7.0
<#
.SYNOPSIS    Windows Updates - Type 2 (system modification)
.DESCRIPTION Downloads and installs the pending Windows updates listed in the diff, via two
             verifiable paths:
               1. PSWindowsUpdate (preferred) - installs by KB and confirms the result.
               2. Windows Update COM API (Microsoft.Update.Session) - the fallback, built
                  into Windows, so it works with no PSGallery access and no module install.
             Both report real per-update outcomes; neither can prompt, so both are safe
             unattended. The old `usoclient` fallback was removed - see
             Install-WindowsUpdateViaCom for why.
.NOTES       Module Type: Type2 | DiffKey: WindowsUpdates | Version: 6.0
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

<#
.SYNOPSIS
    Downloads and installs the queued updates through the built-in Windows Update COM API.
.DESCRIPTION
    The fallback path, used when PSWindowsUpdate is not available. It replaces the old
    `usoclient StartScan/StartInstall` trigger, which is dead on current Windows 10/11:
    the USO client CLI was neutered by Microsoft, returns exit code 1, and installs
    nothing - and because it was fire-and-forget, the module reported those 0 installs
    as successes ("results unverifiable").

    Microsoft.Update.Session is part of Windows itself, so it needs no PSGallery access,
    no NuGet provider and no module install. It is also SYNCHRONOUS and returns a real
    per-update result code, so what this reports actually happened.

    The diff only carries update IDs, not live COM objects, so the searcher is re-run and
    the results are matched back to the queued IDs (the audit stores Identity =
    IUpdate.Identity.UpdateID for exactly this purpose).

    NOTE: Install() blocks until Windows finishes. That is intentional - an unverifiable
    async trigger is what caused the previous reboot-loop bug - and it is safe unattended
    because it cannot prompt.
.OUTPUTS
    [hashtable] Installed / Failed / RebootRequired / Errors / Attempted.
#>
function Install-WindowsUpdateViaCom {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([Parameter(Mandatory)] [AllowEmptyCollection()] [object[]]$DiffItems)

    $outcome = @{
        Installed      = 0
        Failed         = 0
        RebootRequired = $false
        Errors         = [System.Collections.Generic.List[string]]::new()
        Attempted      = 0
    }

    try {
        $session = New-Object -ComObject Microsoft.Update.Session -ErrorAction Stop
        $session.ClientApplicationID = 'WindowsMaintenanceAutomation'
    }
    catch {
        Write-Log -Level ERROR -Component WINUPDATE -Message "Could not create Microsoft.Update.Session: $_"
        $outcome.Errors.Add("COM session creation failed: $_")
        return $outcome
    }

    # Refuse to start on top of another servicing operation, and honour Windows' own
    # "reboot first" signal - installing into either state is how you get partial installs.
    try {
        $installer = $session.CreateUpdateInstaller()
        if ($installer.IsBusy) {
            Write-Log -Level WARN -Component WINUPDATE -Message 'Windows Update installer is busy with another operation - deferring to the next run'
            $outcome.Errors.Add('Windows Update installer busy')
            return $outcome
        }
        if ($installer.RebootRequiredBeforeInstallation) {
            Write-Log -Level WARN -Component WINUPDATE -Message 'Windows requires a reboot BEFORE more updates can install - deferring installation'
            $outcome.RebootRequired = $true
            return $outcome
        }
    }
    catch {
        Write-Log -Level ERROR -Component WINUPDATE -Message "Could not create update installer: $_"
        $outcome.Errors.Add("COM installer creation failed: $_")
        return $outcome
    }

    # Re-run the search to get live IUpdate objects for the IDs the audit queued.
    try {
        $searchResult = $session.CreateUpdateSearcher().Search('IsInstalled=0 and IsHidden=0')
    }
    catch {
        Write-Log -Level ERROR -Component WINUPDATE -Message "Windows Update COM search failed: $_"
        $outcome.Errors.Add("COM search failed: $_")
        return $outcome
    }

    $wantedIds = @{}
    foreach ($d in $DiffItems) {
        if ($d.Identity) { $wantedIds[[string]$d.Identity] = $true }
    }

    $toInstall = New-Object -ComObject Microsoft.Update.UpdateColl
    for ($i = 0; $i -lt $searchResult.Updates.Count; $i++) {
        $u = $searchResult.Updates.Item($i)
        # If the audit supplied IDs, install exactly those (diff-list discipline). If it
        # supplied none, fall back to everything the search found.
        if ($wantedIds.Count -gt 0 -and -not $wantedIds.ContainsKey([string]$u.Identity.UpdateID)) { continue }
        if (-not $u.EulaAccepted) {
            try { $u.AcceptEula() }
            catch { Write-Log -Level DEBUG -Component WINUPDATE -Message "Could not accept EULA for $($u.Title): $_" }
        }
        [void]$toInstall.Add($u)
    }

    $outcome.Attempted = $toInstall.Count
    if ($toInstall.Count -eq 0) {
        Write-Log -Level INFO -Component WINUPDATE -Message 'COM search returned none of the queued updates - nothing left to install'
        return $outcome
    }

    # ── Download ─────────────────────────────────────────────────────────────
    Write-Log -Level INFO -Component WINUPDATE -Message "Downloading $($toInstall.Count) update(s) via Windows Update COM API"
    try {
        $downloader = $session.CreateUpdateDownloader()
        $downloader.Updates = $toInstall
        $dl = $downloader.Download()
        # 2 = Succeeded, 3 = SucceededWithErrors
        if ($dl.ResultCode -notin 2, 3) {
            Write-Log -Level WARN -Component WINUPDATE -Message "Download finished with result code $($dl.ResultCode)"
        }
    }
    catch {
        Write-Log -Level ERROR -Component WINUPDATE -Message "Update download failed: $_"
        $outcome.Errors.Add("Download failed: $_")
        return $outcome
    }

    # Only downloaded updates can be installed.
    $ready = New-Object -ComObject Microsoft.Update.UpdateColl
    for ($i = 0; $i -lt $toInstall.Count; $i++) {
        $u = $toInstall.Item($i)
        if ($u.IsDownloaded) { [void]$ready.Add($u) }
        else {
            Write-Log -Level WARN -Component WINUPDATE -Message "Not downloaded, skipping: $($u.Title)"
            $outcome.Errors.Add("[Not downloaded] $($u.Title)")
            $outcome.Failed++
        }
    }

    if ($ready.Count -eq 0) {
        Write-Log -Level WARN -Component WINUPDATE -Message 'No updates were successfully downloaded - nothing to install'
        return $outcome
    }

    # ── Install ──────────────────────────────────────────────────────────────
    Write-Log -Level INFO -Component WINUPDATE -Message "Installing $($ready.Count) update(s) via Windows Update COM API"
    try {
        $installer.Updates = $ready
        $ir = $installer.Install()
        $outcome.RebootRequired = [bool]$ir.RebootRequired

        for ($i = 0; $i -lt $ready.Count; $i++) {
            $title = $ready.Item($i).Title
            $code = 4
            try { $code = $ir.GetUpdateResult($i).ResultCode } catch { $code = $ir.ResultCode }
            switch ($code) {
                2 {
                    Write-Log -Level SUCCESS -Component WINUPDATE -Message "Installed: $title"
                    $outcome.Installed++
                }
                3 {
                    Write-Log -Level WARN -Component WINUPDATE -Message "Installed with errors: $title"
                    $outcome.Installed++
                }
                default {
                    Write-Log -Level ERROR -Component WINUPDATE -Message "Install failed (result code $code): $title"
                    $outcome.Errors.Add("[Result $code] $title")
                    $outcome.Failed++
                }
            }
        }
    }
    catch {
        Write-Log -Level ERROR -Component WINUPDATE -Message "Update installation failed: $_"
        $outcome.Errors.Add("Install failed: $_")
        $outcome.Failed += $ready.Count
    }

    return $outcome
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

                # Pre-check: Is it already installed? (Function is Test-UpdateAlreadyInstalled;
                # the old misspelled call threw CommandNotFoundException on the FIRST update,
                # which the outer catch turned into "PSWindowsUpdate module error - falling back
                # to usoclient" every run — abandoning the controlled path and forcing a reboot.)
                if ($kb -and (Test-UpdateAlreadyInstalled -KBNumber $kb)) {
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
            Write-Log -Level WARN -Component WINUPDATE -Message "PSWindowsUpdate module error: $_. Falling back to the Windows Update COM API."
            $pswuAvailable = $false
        }
    }

    $usedCom = $false
    if (-not $pswuAvailable) {
        # Fallback: the built-in Windows Update COM API. See Install-WindowsUpdateViaCom for
        # why usoclient was removed (dead CLI on current Windows: exit 1, installs nothing,
        # and its results were reported as successes because they could not be verified).
        $usedCom = $true
        Write-Log -Level INFO -Component WINUPDATE -Message "PSWindowsUpdate unavailable - installing $($diff.Count) update(s) via the Windows Update COM API"

        $comResult = Install-WindowsUpdateViaCom -DiffItems @($diff)
        $processed = $comResult.Installed
        $failed = $comResult.Failed
        $errors += @($comResult.Errors)
        if ($comResult.RebootRequired) { $rebootRequired = $true }

        Write-Log -Level INFO -Component WINUPDATE -Message "COM install: $($comResult.Installed) installed, $($comResult.Failed) failed (of $($comResult.Attempted) attempted)"
    }

    $extraData = @{ RebootRequired = $rebootRequired; UsedComApi = $usedCom }
    if ($rebootRequired) {
        Write-Log -Level WARN -Component WINUPDATE -Message 'One or more updates require a reboot'
    }

    # Status now reflects what actually happened on BOTH paths. The old version hard-coded
    # 'Warning' for the fallback because usoclient results were unknowable; COM results are
    # verified, so the fallback is judged by the same rule as the primary path.
    $status = if ($failed -eq 0 -and $processed -gt 0) { 'Success' }
    elseif ($failed -eq 0) { 'Skipped' }
    elseif ($processed -gt 0) { 'Warning' }
    else { 'Failed' }

    Write-Log -Level INFO -Component WINUPDATE -Message "Done: $processed installed, $failed failed"
    return New-ModuleResult -ModuleName 'WindowsUpdates' -Status $status -ModuleType 'Type2' -ItemsDetected $diff.Count `
        -ItemsProcessed $processed -ItemsFailed $failed -RebootRequired $rebootRequired `
        -Errors $errors -ExtraData $extraData
}

Export-ModuleMember -Function 'Invoke-WindowsUpdate'
