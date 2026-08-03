#Requires -Version 7.0
<#
.SYNOPSIS    Windows Updates Audit - Type 1
.DESCRIPTION Queries Windows Update for pending updates in configured categories.
             Diff = list of pending updates to install.
.NOTES       Module Type: Type1 | DiffKey: WindowsUpdates | Version: 5.0
#>

$_corePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'core\Maintenance.psm1'
if (-not (Get-Command 'Write-Log' -ErrorAction SilentlyContinue)) {
    Import-Module $_corePath -Force -Global -WarningAction SilentlyContinue
}

function Get-PendingUpdatesMultiSource {
    param([hashtable]$Config)

    $pendingUpdates = [System.Collections.Generic.List[hashtable]]::new()

    # The Windows Update COM API (Microsoft.Update.Session) is the ONE authoritative source
    # for what is genuinely PENDING installation. Its result is returned as-is — including
    # when that result is ZERO. A 0-result COM scan means "nothing to install", NOT "fall
    # back to a weaker source".
    #
    # The old registry + event-log "fallback layers" were REMOVED because they were the
    # cause of an endless reboot loop:
    #   * Layer 2 reported CBS 'RebootPending' / 'SetupInProgress' — those are reboot flags,
    #     not installable updates, yet they were enqueued as pending items.
    #   * Layer 3 harvested System event ID 19 ("installation SUCCESSFUL") and enqueued the
    #     already-installed KBs AS pending.
    # On a fully-patched machine the COM scan correctly returns 0, the code fell through to
    # Layer 3, "found" the KBs it had just installed, and WindowsUpdates (Type2) tried to
    # reinstall them via usoclient — which triggered another reboot, and the cycle repeated
    # forever. Trusting the COM result (even when empty) breaks that loop.
    Write-Log -Level DEBUG -Component WU-AUDIT -Message 'Querying Windows Update COM API (authoritative)'
    try {
        $updateSession = New-Object -ComObject Microsoft.Update.Session -ErrorAction Stop
        $updateSearcher = $updateSession.CreateUpdateSearcher()
        $searchResult = $updateSearcher.Search('IsInstalled=0 and IsHidden=0')

        foreach ($update in $searchResult.Updates) {
            $title = $update.Title

            $excluded = $false
            foreach ($pattern in $Config.excludePatterns) {
                if ($title -like $pattern) { $excluded = $true; break }
            }
            if ($excluded) { continue }

            $severity = $update.MsrcSeverity
            $isSecurity = [bool]$severity -or ($title -match 'Security|Cumulative')
            $isCritical = $severity -eq 'Critical'
            $isImportant = $severity -eq 'Important'
            $isOptional = -not $isSecurity -and -not $isCritical -and -not $isImportant

            $include = ($Config.categories.security -and $isSecurity) `
                -or ($Config.categories.critical -and $isCritical) `
                -or ($Config.categories.important -and $isImportant) `
                -or ($Config.categories.optional -and $isOptional)

            if ($include) {
                $pendingUpdates.Add(@{
                        Title       = $title
                        Identity    = $update.Identity.UpdateID
                        Severity    = $severity
                        SizeMB      = [math]::Round($update.MaxDownloadSize / 1MB, 1)
                        IsMandatory = $update.IsMandatory
                    })
            }
        }

        Write-Log -Level DEBUG -Component WU-AUDIT -Message "COM query authoritative: $($pendingUpdates.Count) pending update(s)"
        return @{ Updates = $pendingUpdates; Method = 'COM (Windows Update API)' }
    }
    catch {
        # Genuine COM failure (rare) — report it as such rather than inventing updates.
        Write-Log -Level WARN -Component WU-AUDIT -Message "Windows Update COM query failed: $_"
        return @{ Updates = $pendingUpdates; Method = 'None (COM query failed)' }
    }
}

<#
.SYNOPSIS
    Determines whether the running Windows feature version is still within free servicing,
    and (Windows 11 only) what the latest known supported version is to advance toward.
.DESCRIPTION
    Deliberately NOT a CVE-to-KB map. Windows Update's own COM API is already the
    authoritative source for which specific updates are missing on an in-support machine
    (see Get-PendingUpdatesMultiSource above) - duplicating that with a hand-maintained
    per-CVE list would be redundant, would go stale every Patch Tuesday, and risks
    contradicting the COM result. This function answers a narrower, much more stable
    question instead: "has this feature version itself fallen out of servicing," which
    only changes a handful of times a year (config/lists/windows-updates/os-lifecycle.json).

    LTSC / IoT Enterprise LTSC editions follow a completely different multi-year servicing
    model and are intentionally excluded (Applicable = $false) rather than guessed at.
.OUTPUTS
    [hashtable] Applicable, MajorVersion, DisplayVersion, EditionTier, IsSupported,
    EndOfServiceDate, EsuAvailable, EsuEndDate, EsuNote, LatestSupportedVersion,
    NeedsFeatureAdvance, Guidance.
#>
function Get-WindowsLifecycleStatus {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([Parameter(Mandatory)] [hashtable]$OSContext)

    $result = @{
        Applicable = $false
        MajorVersion = $OSContext.MajorVersion
        DisplayVersion = $null
        EditionTier = $null
        IsSupported = $true
        EndOfServiceDate = $null
        EsuAvailable = $false
        EsuEndDate = $null
        EsuNote = $null
        LatestSupportedVersion = $null
        NeedsFeatureAdvance = $false
        Guidance = $null
    }

    try {
        $cvKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
        $displayVersion = (Get-ItemProperty -Path $cvKey -Name 'DisplayVersion' -ErrorAction SilentlyContinue).DisplayVersion
        $editionId = (Get-ItemProperty -Path $cvKey -Name 'EditionID' -ErrorAction SilentlyContinue).EditionID
        $result.DisplayVersion = $displayVersion

        if (-not $displayVersion -or -not $editionId) {
            Write-Log -Level DEBUG -Component WU-AUDIT -Message 'Could not read DisplayVersion/EditionID - skipping lifecycle check'
            return $result
        }

        # LTSC / IoT Enterprise LTSC: different multi-year servicing model, not covered here.
        if ($editionId -match 'EnterpriseS|IoTEnterpriseS') {
            Write-Log -Level DEBUG -Component WU-AUDIT -Message "LTSC edition detected ($editionId) - lifecycle check not applicable"
            return $result
        }

        $editionTier = if ($editionId -match 'Enterprise|Education|IoTEnterprise') { 'enterprise' } else { 'consumer' }
        $result.EditionTier = $editionTier

        $lifecycle = Get-BaselineList -ModuleFolder 'windows-updates' -FileName 'os-lifecycle.json'
        if (-not $lifecycle) {
            Write-Log -Level DEBUG -Component WU-AUDIT -Message 'os-lifecycle.json not available - skipping lifecycle check'
            return $result
        }

        $branch = if ($OSContext.IsWindows11) { $lifecycle.windows11 } else { $lifecycle.windows10 }
        $versionEntry = if ($OSContext.IsWindows11) { $branch.versions[$displayVersion] } else { $branch[$displayVersion] }
        if (-not $versionEntry) {
            Write-Log -Level DEBUG -Component WU-AUDIT -Message "No lifecycle entry for $displayVersion - unreleased/unknown version, assuming supported"
            return $result
        }

        $result.Applicable = $true
        $editionInfo = $versionEntry.editions[$editionTier]
        if ($editionInfo -and $editionInfo.endOfService) {
            $eos = [datetime]::ParseExact($editionInfo.endOfService, 'yyyy-MM-dd', $null)
            $result.EndOfServiceDate = $editionInfo.endOfService
            $result.IsSupported = (Get-Date) -lt $eos
        }

        $eosSuffix = if ($result.EndOfServiceDate) { " ($($result.EndOfServiceDate))" } else { '' }

        if ($OSContext.IsWindows11) {
            $result.LatestSupportedVersion = $branch.latestSupportedVersion
            if (-not $result.IsSupported -and $result.LatestSupportedVersion -and $result.LatestSupportedVersion -ne $displayVersion) {
                $result.NeedsFeatureAdvance = $true
            }
            if (-not $result.IsSupported) {
                $result.Guidance = "Windows 11 $displayVersion ($editionTier) is past end of service$eosSuffix. Latest supported feature version: $($result.LatestSupportedVersion)."
            }
        }
        else {
            $result.EsuAvailable = [bool]$branch[$displayVersion].esuAvailable
            $result.EsuEndDate = $branch[$displayVersion].esuEndDate
            $result.EsuNote = $branch[$displayVersion].esuNote
            if (-not $result.IsSupported) {
                $esuSuffix = if ($result.EsuAvailable) {
                    " Extended Security Updates are available through $($result.EsuEndDate) via enrollment at https://www.microsoft.com/en-us/windows/extended-security-updates - this requires action on the device (Microsoft Account sign-in, Rewards points, or purchase) that this unattended task cannot reliably complete on your behalf."
                }
                else { '' }
                $result.Guidance = "Windows 10 $displayVersion ($editionTier) is past end of service$eosSuffix. This was the final Windows 10 feature version - there is no newer version to move to.$esuSuffix"
            }
        }

        return $result
    }
    catch {
        Write-Log -Level WARN -Component WU-AUDIT -Message "Lifecycle status check failed (non-fatal, report-only): $_"
        return $result
    }
}

function Invoke-WindowsUpdatesAudit {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    Write-Log -Level INFO -Component WU-AUDIT -Message 'Starting Windows Updates audit'

    try {
        # 1. Load config
        $config = Get-BaselineList -ModuleFolder 'windows-updates' -FileName 'updates-config.json'
        if (-not $config -or $config.enabled -eq $false) {
            Write-Log -Level INFO -Component WU-AUDIT -Message 'Windows Updates disabled in config - skipping'
            Save-DiffList -ModuleName 'WindowsUpdates' -DiffList @()
            return New-ModuleResult -ModuleName 'WindowsUpdatesAudit' -Status 'Skipped' `
                -Message 'Disabled in configuration'
        }

        if (-not $config.categories) {
            return New-ModuleResult -ModuleName 'WindowsUpdatesAudit' -Status 'Failed' `
                -Message 'Invalid updates config structure (missing categories)'
        }

        # 2. Query Windows Update via multi-source detection (COM + fallback)
        Write-Log -Level INFO -Component WU-AUDIT -Message 'Querying Windows Update using multi-source detection...'
        $detectionResult = Get-PendingUpdatesMultiSource -Config $config
        $pendingUpdates = $detectionResult.Updates
        $detectionMethod = $detectionResult.Method

        Write-Log -Level INFO -Component WU-AUDIT -Message "Detection method used: $detectionMethod"
        Write-Log -Level INFO -Component WU-AUDIT -Message "Pending updates: $($pendingUpdates.Count)"

        # 2b. Lifecycle check - independent of the COM query above (registry-based), so it
        # still runs, and its diff items still get queued, even on a COM failure. See
        # Get-WindowsLifecycleStatus for why this is deliberately NOT a CVE-to-KB map.
        $osCtx = (Get-Variable -Name 'OSContext' -Scope Global -ValueOnly -ErrorAction SilentlyContinue)
        if (-not $osCtx) { $osCtx = Get-OSContext }
        $lifecycle = Get-WindowsLifecycleStatus -OSContext $osCtx
        $mainConfig = Get-MainConfig
        $wuOptions = $mainConfig.modules.windowsUpdates

        $lifecycleDiff = [System.Collections.Generic.List[hashtable]]::new()
        if ($lifecycle.Applicable -and -not $lifecycle.IsSupported) {
            Write-Log -Level WARN -Component WU-AUDIT -Message $lifecycle.Guidance

            if ($osCtx.IsWindows11 -and $lifecycle.NeedsFeatureAdvance -and $wuOptions.autoAdvanceEolFeatureVersion) {
                $lifecycleDiff.Add(@{
                        Type = 'lifecycle'
                        Action = 'advance-feature-version'
                        Name = 'FeatureVersionAdvance'
                        CurrentState = $lifecycle.DisplayVersion
                        DesiredState = $lifecycle.LatestSupportedVersion
                        Description = "Set Windows Update's TargetReleaseVersion policy so Windows Update offers and installs $($lifecycle.LatestSupportedVersion) (current: $($lifecycle.DisplayVersion), out of service since $($lifecycle.EndOfServiceDate))."
                    })
            }
            elseif ((-not $osCtx.IsWindows11) -and $lifecycle.EsuAvailable -and $wuOptions.attemptConsumerEsuEnrollment) {
                $lifecycleDiff.Add(@{
                        Type = 'lifecycle'
                        Action = 'attempt-esu-enrollment'
                        Name = 'ConsumerEsuEnrollment'
                        CurrentState = 'Unknown'
                        DesiredState = 'Enrolled'
                        Description = "Best-effort attempt to enroll in free Consumer ESU (covers through $($lifecycle.EsuEndDate)) via ClipESUConsumer.exe. Not guaranteed to complete unattended - see main-config.json modules.windowsUpdates comment."
                    })
            }
        }

        # 3. Save diff (pending updates + any lifecycle actions this run should take)
        $combinedDiff = @($pendingUpdates.ToArray()) + @($lifecycleDiff.ToArray())
        Save-DiffList -ModuleName 'WindowsUpdates' -DiffList $combinedDiff

        # 4. Persist audit data
        $auditPath = Get-TempPath -Category 'data' -FileName 'wu-audit.json'
        @{
            Timestamp = (Get-Date -Format 'o')
            Pending = $pendingUpdates.ToArray()
            DetectionMethod = $detectionMethod
            Lifecycle = $lifecycle
        } | ConvertTo-Json -Depth 8 | Set-Content -Path $auditPath -Encoding UTF8 -Force

        $extra = @{}
        if ($lifecycle.Applicable) {
            $extra.OSSupportStatus = if ($lifecycle.IsSupported) { 'Supported' } else { 'Past end of service' }
            if ($lifecycle.EndOfServiceDate) { $extra.EndOfServiceDate = $lifecycle.EndOfServiceDate }
            if ($lifecycle.Guidance) { $extra.Guidance = $lifecycle.Guidance }
        }

        if ($detectionMethod -ne 'COM (Windows Update API)') {
            # Only outcome other than COM success is a genuine COM failure. The diff saved
            # above still carries only real, non-guessed items (pending updates from a
            # failed search are correctly absent; lifecycle items, if any, are independent
            # of the COM query) so Stage 3 does not act on invented updates.
            Write-Log -Level ERROR -Component WU-AUDIT -Message 'Windows Update COM query failed - cannot determine pending updates'
            return New-ModuleResult -ModuleName 'WindowsUpdatesAudit' -Status 'Failed' `
                -Message 'Windows Update COM query failed' `
                -Errors @('COM (Microsoft.Update.Session) query failed') `
                -ExtraData $extra
        }

        Write-Log -Level SUCCESS -Component WU-AUDIT -Message "Windows Updates audit complete: $($pendingUpdates.Count) pending"
        return New-ModuleResult -ModuleName 'WindowsUpdatesAudit' -Status 'Success' `
            -ItemsDetected $combinedDiff.Count `
            -Message "$($pendingUpdates.Count) updates pending" `
            -ExtraData $extra
    }
    catch {
        Write-Log -Level ERROR -Component WU-AUDIT -Message "Audit failed: $_"
        return New-ModuleResult -ModuleName 'WindowsUpdatesAudit' -Status 'Failed' -Errors @($_.ToString())
    }
}

Export-ModuleMember -Function 'Invoke-WindowsUpdatesAudit'
