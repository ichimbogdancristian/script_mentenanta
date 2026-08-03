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

<#
.SYNOPSIS
    Advances Windows 11 past an out-of-service feature version using Microsoft's documented
    TargetReleaseVersion policy - Windows Update itself then offers and installs the newer
    version through the same COM API this module already uses, so no separate download or
    install code is needed here.
.OUTPUTS
    [hashtable] Success, Message.
#>
function Invoke-FeatureVersionAdvance {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([Parameter(Mandatory)] [hashtable]$DiffItem)

    $targetVersion = $DiffItem.DesiredState
    if (-not $targetVersion) {
        return @{ Success = $false; Message = 'No target version supplied - skipping' }
    }

    try {
        $wuPolicyPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
        if (-not (Test-Path $wuPolicyPath)) {
            New-Item -Path $wuPolicyPath -Force | Out-Null
        }
        Set-ItemProperty -Path $wuPolicyPath -Name 'TargetReleaseVersion' -Value 1 -Type DWord -Force
        Set-ItemProperty -Path $wuPolicyPath -Name 'TargetReleaseVersionInfo' -Value $targetVersion -Type String -Force
        Set-ItemProperty -Path $wuPolicyPath -Name 'ProductVersion' -Value 'Windows 11' -Type String -Force

        Write-Log -Level SUCCESS -Component WINUPDATE -Message "Set TargetReleaseVersion policy to $targetVersion - Windows Update will offer this version on its next scan (may take one or more maintenance runs / reboots to fully land)"
        return @{ Success = $true; Message = "Target feature version set to $targetVersion" }
    }
    catch {
        Write-Log -Level ERROR -Component WINUPDATE -Message "Failed to set TargetReleaseVersion policy: $_"
        return @{ Success = $false; Message = "Failed to set policy: $_" }
    }
}

<#
.SYNOPSIS
    Best-effort, opt-in attempt to enroll an out-of-service Windows 10 device in the free
    Consumer Extended Security Updates program via the built-in ClipESUConsumer.exe tool.
.DESCRIPTION
    This is deliberately NOT reported as a guaranteed fix. Consumer ESU enrollment is
    designed around an interactively signed-in user (Microsoft Account, Microsoft Store
    account, or - since Nov 2025 - a local account), and this task normally runs as SYSTEM
    with no such session. The FeatureManagement override used here only unlocks the
    eligibility evaluation; it cannot fabricate a signed-in session. Success is only ever
    reported when the ConsumerESU eligibility registry key confirms it afterward - otherwise
    this returns Success = $false with a message explaining why, never a false positive.
.OUTPUTS
    [hashtable] Success, Message.
#>
function Invoke-ConsumerEsuEnrollmentAttempt {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    try {
        $overridePath = 'HKLM:\SYSTEM\CurrentControlSet\Policies\Microsoft\FeatureManagement\Overrides'
        if (-not (Test-Path $overridePath)) {
            New-Item -Path $overridePath -Force | Out-Null
        }
        Set-ItemProperty -Path $overridePath -Name '4011992206' -Value 2 -Type DWord -Force

        $toolCandidates = @(
            (Join-Path $env:SystemRoot 'System32\ClipSVC\ClipESUConsumer.exe')
            (Join-Path $env:SystemRoot 'System32\ClipESUConsumer.exe')
        )
        $tool = $toolCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
        if (-not $tool) {
            Write-Log -Level WARN -Component WINUPDATE -Message 'ClipESUConsumer.exe not found on this system - ESU enrollment eligibility flag was set, but nothing was triggered'
            return @{ Success = $false; Message = 'ClipESUConsumer.exe not present on this OS build - cannot attempt enrollment' }
        }

        Write-Log -Level INFO -Component WINUPDATE -Message "Running: $tool -evaluateEligibility"
        & $tool -evaluateEligibility 2>&1 | Out-Null

        Start-Sleep -Seconds 5
        $eligKey = 'HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Windows\ConsumerESU'
        $eligibility = (Get-ItemProperty -Path $eligKey -ErrorAction SilentlyContinue).ESUEligibility

        if ($eligibility) {
            Write-Log -Level SUCCESS -Component WINUPDATE -Message "Consumer ESU eligibility confirmed (ESUEligibility=$eligibility)"
            return @{ Success = $true; Message = "ESU eligibility confirmed (ESUEligibility=$eligibility)" }
        }

        Write-Log -Level WARN -Component WINUPDATE -Message 'Consumer ESU enrollment could not be confirmed - this almost always means the signed-in-user requirement was not met under this unattended SYSTEM context. Enroll manually via Settings > Windows Update while logged in interactively if you want ESU on this device.'
        return @{ Success = $false; Message = 'Enrollment not confirmed - likely needs an interactive session; see main-config.json modules.windowsUpdates comment' }
    }
    catch {
        Write-Log -Level ERROR -Component WINUPDATE -Message "ESU enrollment attempt failed: $_"
        return @{ Success = $false; Message = "Attempt failed: $_" }
    }
}

<#
.SYNOPSIS
    Dispatches every 'lifecycle' diff item to its handler and aggregates outcomes.
#>
function Invoke-LifecycleDiffItem {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([Parameter(Mandatory)] [AllowEmptyCollection()] [object[]]$Items)

    $outcome = @{ Processed = 0; Failed = 0; Errors = [System.Collections.Generic.List[string]]::new() }

    foreach ($item in $Items) {
        $label = $item.Name ?? $item.Action ?? 'lifecycle item'
        $result = switch ($item.Action) {
            'advance-feature-version' { Invoke-FeatureVersionAdvance -DiffItem $item }
            'attempt-esu-enrollment' { Invoke-ConsumerEsuEnrollmentAttempt }
            default {
                Write-Log -Level WARN -Component WINUPDATE -Message "Unknown lifecycle action '$($item.Action)' - skipping"
                @{ Success = $false; Message = "Unknown action: $($item.Action)" }
            }
        }

        if ($result.Success) {
            $outcome.Processed++
        }
        else {
            $outcome.Failed++
            $outcome.Errors.Add("[$label] $($result.Message)")
        }
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

    # 'lifecycle' items (feature-version advance / ESU attempt) are handled separately below -
    # they carry no Title/Identity, so they must never reach the KB-install loops.
    $normalUpdates = @($diff | Where-Object { $_.Type -ne 'lifecycle' })
    $lifecycleItems = @($diff | Where-Object { $_.Type -eq 'lifecycle' })

    $processed = 0; $failed = 0; $errors = @(); $rebootRequired = $false

    # Primary: PSWindowsUpdate — installs by KB ID and confirms result
    $pswuAvailable = $normalUpdates.Count -gt 0 -and $null -ne (Get-Module -ListAvailable -Name 'PSWindowsUpdate' -ErrorAction SilentlyContinue)
    if ($normalUpdates.Count -eq 0) {
        Write-Log -Level INFO -Component WINUPDATE -Message 'No pending update packages to install (lifecycle-only diff)'
    }
    elseif ($pswuAvailable) {
        Write-Log -Level INFO -Component WINUPDATE -Message "Installing $($normalUpdates.Count) update(s)"
        try {
            Import-Module PSWindowsUpdate -SkipEditionCheck -ErrorAction Stop
            foreach ($update in $normalUpdates) {
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
    if ($normalUpdates.Count -gt 0 -and -not $pswuAvailable) {
        # Fallback: the built-in Windows Update COM API. See Install-WindowsUpdateViaCom for
        # why usoclient was removed (dead CLI on current Windows: exit 1, installs nothing,
        # and its results were reported as successes because they could not be verified).
        $usedCom = $true
        Write-Log -Level INFO -Component WINUPDATE -Message "PSWindowsUpdate unavailable - installing $($normalUpdates.Count) update(s) via the Windows Update COM API"

        $comResult = Install-WindowsUpdateViaCom -DiffItems @($normalUpdates)
        $processed = $comResult.Installed
        $failed = $comResult.Failed
        $errors += @($comResult.Errors)
        if ($comResult.RebootRequired) { $rebootRequired = $true }

        Write-Log -Level INFO -Component WINUPDATE -Message "COM install: $($comResult.Installed) installed, $($comResult.Failed) failed (of $($comResult.Attempted) attempted)"
    }

    # Lifecycle items (feature-version advance / ESU attempt) are independent of the update
    # packages above - process them regardless of whether there were any pending updates.
    $lifecycleProcessed = 0; $lifecycleFailed = 0
    if ($lifecycleItems.Count -gt 0) {
        Write-Log -Level INFO -Component WINUPDATE -Message "Processing $($lifecycleItems.Count) lifecycle action(s)"
        $lifecycleOutcome = Invoke-LifecycleDiffItem -Items $lifecycleItems
        $lifecycleProcessed = $lifecycleOutcome.Processed
        $lifecycleFailed = $lifecycleOutcome.Failed
        $processed += $lifecycleProcessed
        $failed += $lifecycleFailed
        $errors += @($lifecycleOutcome.Errors)
    }

    $extraData = @{ RebootRequired = $rebootRequired; UsedComApi = $usedCom }
    if ($lifecycleItems.Count -gt 0) {
        $extraData.LifecycleActionsProcessed = $lifecycleProcessed
        $extraData.LifecycleActionsFailed = $lifecycleFailed
    }
    if ($rebootRequired) {
        Write-Log -Level WARN -Component WINUPDATE -Message 'One or more updates require a reboot'
    }

    # Status now reflects what actually happened on BOTH paths. The old version hard-coded
    # 'Warning' for the fallback because usoclient results were unknowable; COM results are
    # verified, so the fallback is judged by the same rule as the primary path. Lifecycle
    # items are folded into the same processed/failed counters so a lifecycle-only diff
    # (no pending update packages) still reports an accurate Success/Warning/Failed status
    # instead of the default Skipped.
    $status = if ($failed -eq 0 -and $processed -gt 0) { 'Success' }
    elseif ($failed -eq 0) { 'Skipped' }
    elseif ($processed -gt 0) { 'Warning' }
    else { 'Failed' }

    Write-Log -Level INFO -Component WINUPDATE -Message "Done: $processed installed/applied, $failed failed"
    return New-ModuleResult -ModuleName 'WindowsUpdates' -Status $status -ModuleType 'Type2' -ItemsDetected $diff.Count `
        -ItemsProcessed $processed -ItemsFailed $failed -RebootRequired $rebootRequired `
        -Errors $errors -ExtraData $extraData
}

Export-ModuleMember -Function 'Invoke-WindowsUpdate'
