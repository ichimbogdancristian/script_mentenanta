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
    $detectionMethod = $null

    # Layer 1: COM (Windows Update API) - Primary method
    Write-Log -Level DEBUG -Component WU-AUDIT -Message 'Attempting Layer 1: COM (Windows Update API)'
    try {
        $updateSession = New-Object -ComObject Microsoft.Update.Session -ErrorAction Stop
        $updateSearcher = $updateSession.CreateUpdateSearcher()
        $searchResult = $updateSearcher.Search('IsInstalled=0 and IsHidden=0')

        foreach ($update in $searchResult.Updates) {
            $title = $update.Title

            $excluded = $false
            foreach ($pattern in $config.excludePatterns) {
                if ($title -like $pattern) { $excluded = $true; break }
            }
            if ($excluded) { continue }

            $severity = $update.MsrcSeverity
            $isSecurity = [bool]$severity -or ($title -match 'Security|Cumulative')
            $isCritical = $severity -eq 'Critical'
            $isImportant = $severity -eq 'Important'
            $isOptional = -not $isSecurity -and -not $isCritical -and -not $isImportant

            $include = ($config.categories.security -and $isSecurity) `
                -or ($config.categories.critical -and $isCritical) `
                -or ($config.categories.important -and $isImportant) `
                -or ($config.categories.optional -and $isOptional)

            if ($include) {
                $pendingUpdates.Add(@{
                    Title = $title
                    Identity = $update.Identity.UpdateID
                    Severity = $severity
                    SizeMB = [math]::Round($update.MaxDownloadSize / 1MB, 1)
                    IsMandatory = $update.IsMandatory
                })
            }
        }

        if ($pendingUpdates.Count -gt 0) {
            $detectionMethod = 'COM (Windows Update API)'
            Write-Log -Level DEBUG -Component WU-AUDIT -Message "✓ Layer 1 successful: Found $($pendingUpdates.Count) updates"
            return @{ Updates = $pendingUpdates; Method = $detectionMethod }
        }
        else {
            Write-Log -Level DEBUG -Component WU-AUDIT -Message "Layer 1 found no updates, trying Layer 2"
        }
    }
    catch {
        Write-Log -Level DEBUG -Component WU-AUDIT -Message "Layer 1 failed: $_. Trying Layer 2..."
    }

    # Layer 2: Registry Fallback - Check Windows Update registry for pending updates
    Write-Log -Level DEBUG -Component WU-AUDIT -Message 'Attempting Layer 2: Registry (pending updates)'
    try {
        $updateKeys = Get-ChildItem -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending' -ErrorAction SilentlyContinue
        if ($updateKeys) {
            $pendingUpdates.Add(@{
                Title = 'Component-based servicing updates'
                Identity = 'CBS'
                Severity = 'Unknown'
                SizeMB = 0
                IsMandatory = $false
            })
        }

        # Also check Windows Update registry for pending updates
        $regPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate'
        $setupInProgress = Get-ItemProperty -Path $regPath -Name 'SetupInProgress' -ErrorAction SilentlyContinue
        if ($setupInProgress -and $setupInProgress.SetupInProgress -eq 1) {
            $pendingUpdates.Add(@{
                Title = 'Windows Update setup in progress'
                Identity = 'WindowsUpdate'
                Severity = 'Unknown'
                SizeMB = 0
                IsMandatory = $false
            })
        }

        if ($pendingUpdates.Count -gt 0) {
            $detectionMethod = 'Registry (Windows Update pending)'
            Write-Log -Level DEBUG -Component WU-AUDIT -Message "✓ Layer 2 successful: Found $($pendingUpdates.Count) pending updates via registry"
            return @{ Updates = $pendingUpdates; Method = $detectionMethod }
        }
        else {
            Write-Log -Level DEBUG -Component WU-AUDIT -Message "Layer 2 found no pending updates, trying Layer 3"
        }
    }
    catch {
        Write-Log -Level DEBUG -Component WU-AUDIT -Message "Layer 2 failed: $_. Trying Layer 3..."
    }

    # Layer 3: Event Log Fallback - Check System event log for update events
    Write-Log -Level DEBUG -Component WU-AUDIT -Message 'Attempting Layer 3: Event Log (System events)'
    try {
        $events = Get-WinEvent -LogName System -FilterXPath "*[System[EventID=19]]" -MaxEvents 10 -ErrorAction Stop |
            Sort-Object -Property TimeCreated -Descending

        foreach ($evt in $events) {
            $message = $evt.Message
            if ($message -match 'KB\d+') {
                $matchResults = [regex]::Matches($message, 'KB(\d+)')
                foreach ($match in $matchResults) {
                    $kbid = "KB$($match.Groups[1].Value)"
                    $pendingUpdates.Add(@{
                        Title       = $kbid
                        Identity    = $kbid
                        Severity    = 'Unknown'
                        SizeMB      = 0
                        IsMandatory = $false
                    })
                }
            }
        }

        if ($pendingUpdates.Count -gt 0) {
            $detectionMethod = 'Event Log (System events - Historical)'
            Write-Log -Level DEBUG -Component WU-AUDIT -Message "✓ Layer 3 successful: Found $($pendingUpdates.Count) from event log"
            return @{ Updates = $pendingUpdates; Method = $detectionMethod }
        }
        else {
            Write-Log -Level DEBUG -Component WU-AUDIT -Message "Layer 3 found no events"
        }
    }
    catch {
        Write-Log -Level WARN -Component WU-AUDIT -Message "Layer 3 failed: $_"
    }

    # All layers failed
    Write-Log -Level WARN -Component WU-AUDIT -Message 'All update detection methods failed'
    return @{ Updates = [System.Collections.Generic.List[hashtable]]::new(); Method = 'None (All methods failed)' }
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

        if ($detectionMethod -eq 'None (All methods failed)') {
            Write-Log -Level ERROR -Component WU-AUDIT -Message 'All update detection methods failed'
            return New-ModuleResult -ModuleName 'WindowsUpdatesAudit' -Status 'Failed' `
                -Message 'All update detection methods failed' `
                -Errors @('COM, WMI, and Event Log queries all failed')
        }

        if ($detectionMethod -notlike 'COM*') {
            Write-Log -Level WARN -Component WU-AUDIT -Message "Audit completed using fallback: $detectionMethod"
            return New-ModuleResult -ModuleName 'WindowsUpdatesAudit' -Status 'Warning' `
                -ItemsDetected $pendingUpdates.Count `
                -Message "Primary detection failed, used fallback: $detectionMethod" `
                -Errors @("COM detection failed, used: $detectionMethod")
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
