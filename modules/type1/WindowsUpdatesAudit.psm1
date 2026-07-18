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

        # 3. Save diff
        Save-DiffList -ModuleName 'WindowsUpdates' -DiffList $pendingUpdates.ToArray()

        # 4. Persist audit data
        $auditPath = Get-TempPath -Category 'data' -FileName 'wu-audit.json'
        @{
            Timestamp = (Get-Date -Format 'o')
            Pending = $pendingUpdates.ToArray()
            DetectionMethod = $detectionMethod
        } | ConvertTo-Json -Depth 8 | Set-Content -Path $auditPath -Encoding UTF8 -Force

        if ($detectionMethod -ne 'COM (Windows Update API)') {
            # Only outcome other than COM success is a genuine COM failure. Report it as
            # Failed with an EMPTY diff (already saved above) so Stage 3 does not act on
            # guesses — never invent updates to "install".
            Write-Log -Level ERROR -Component WU-AUDIT -Message 'Windows Update COM query failed - cannot determine pending updates'
            return New-ModuleResult -ModuleName 'WindowsUpdatesAudit' -Status 'Failed' `
                -Message 'Windows Update COM query failed' `
                -Errors @('COM (Microsoft.Update.Session) query failed')
        }

        Write-Log -Level SUCCESS -Component WU-AUDIT -Message "Windows Updates audit complete: $($pendingUpdates.Count) pending"
        return New-ModuleResult -ModuleName 'WindowsUpdatesAudit' -Status 'Success' `
            -ItemsDetected $pendingUpdates.Count `
            -Message "$($pendingUpdates.Count) updates pending"
    }
    catch {
        Write-Log -Level ERROR -Component WU-AUDIT -Message "Audit failed: $_"
        return New-ModuleResult -ModuleName 'WindowsUpdatesAudit' -Status 'Failed' -Errors @($_.ToString())
    }
}

Export-ModuleMember -Function 'Invoke-WindowsUpdatesAudit'
