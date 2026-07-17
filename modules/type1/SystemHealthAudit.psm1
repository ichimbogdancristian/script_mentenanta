#Requires -Version 7.0
<#
.SYNOPSIS    System Health Audit - Type 1 (Report-only, no actions)
.DESCRIPTION Gathers critical system health information for reporting:
             - Event Viewer: Critical and Error events from last 30 days
             - Windows Defender: Incidents and detections from last 30 days
             - Windows Defender: Current exclusions (files, folders, processes, extensions)
.NOTES       Module Type: Type1 | DiffKey: SystemHealth | Version: 1.0 (Report-only)
#>

$_corePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'core\Maintenance.psm1'
if (-not (Get-Command 'Write-Log' -ErrorAction SilentlyContinue)) {
    Import-Module $_corePath -Force -Global -WarningAction SilentlyContinue
}

function Invoke-SystemHealthAudit {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    Write-Log -Level INFO -Component HEALTH-AUDIT -Message 'Starting system health audit'

    try {
        $healthReport = @{
            Timestamp           = (Get-Date -Format 'o')
            EventViewerEvents   = $null
            DefenderIncidents   = $null
            DefenderExclusions  = $null
            Summary             = @{}
        }

        # ─── EVENT VIEWER: Critical & Error Events (Last 30 Days) ──────────────
        Write-Log -Level DEBUG -Component HEALTH-AUDIT -Message 'Gathering critical and error events from Event Viewer...'
        $events = Get-CriticalErrorEvents
        $healthReport.EventViewerEvents = $events
        $healthReport.Summary.TotalCriticalErrorEvents = $events.Count
        Write-Log -Level INFO -Component HEALTH-AUDIT -Message "Event Viewer: Found $($events.Count) critical/error events in last 30 days"

        # ─── WINDOWS DEFENDER: Incidents (Last 30 Days) ───────────────────────
        Write-Log -Level DEBUG -Component HEALTH-AUDIT -Message 'Gathering Windows Defender incidents...'
        $incidents = Get-WindowsDefenderIncidents
        $healthReport.DefenderIncidents = $incidents
        $healthReport.Summary.TotalDefenderIncidents = $incidents.Count
        Write-Log -Level INFO -Component HEALTH-AUDIT -Message "Windows Defender: Found $($incidents.Count) incidents in last 30 days"

        # ─── WINDOWS DEFENDER: Exclusions ────────────────────────────────────
        Write-Log -Level DEBUG -Component HEALTH-AUDIT -Message 'Gathering Windows Defender exclusions...'
        $exclusions = Get-WindowsDefenderExclusions
        $healthReport.DefenderExclusions = $exclusions
        $healthReport.Summary.TotalDefenderExclusions = $exclusions.FileExclusions.Count + $exclusions.FolderExclusions.Count + `
                                                         $exclusions.ProcessExclusions.Count + $exclusions.ExtensionExclusions.Count
        Write-Log -Level INFO -Component HEALTH-AUDIT -Message "Windows Defender Exclusions: Files=$($exclusions.FileExclusions.Count), Folders=$($exclusions.FolderExclusions.Count), Processes=$($exclusions.ProcessExclusions.Count), Extensions=$($exclusions.ExtensionExclusions.Count)"

        # ─── SAVE HEALTH REPORT ──────────────────────────────────────────────
        $reportPath = Get-TempPath -Category 'data' -FileName 'system-health-report.json'
        $healthReport | ConvertTo-Json -Depth 10 | Set-Content -Path $reportPath -Encoding UTF8 -Force
        Write-Log -Level DEBUG -Component HEALTH-AUDIT -Message "Health report saved to: $reportPath"

        $status = if ($healthReport.Summary.TotalCriticalErrorEvents -gt 0 -or $healthReport.Summary.TotalDefenderIncidents -gt 0) { 'Warning' } else { 'Success' }
        $message = "Health audit complete: $($events.Count) events, $($incidents.Count) defender incidents, $($healthReport.Summary.TotalDefenderExclusions) exclusions"

        Write-Log -Level INFO -Component HEALTH-AUDIT -Message $message
        return New-ModuleResult -ModuleName 'SystemHealthAudit' -Status $status -ModuleType 'Type1' -Message $message -ExtraData $healthReport.Summary
    }
    catch {
        Write-Log -Level ERROR -Component HEALTH-AUDIT -Message "Audit failed: $_"
        return New-ModuleResult -ModuleName 'SystemHealthAudit' -Status 'Failed' -Errors @($_.ToString())
    }
}

#region ─── EVENT VIEWER HELPER FUNCTIONS ─────────────────────────────────────

function Get-CriticalErrorEvents {
    [CmdletBinding()]
    [OutputType([array])]
    param()

    $events = @()
    $thirtyDaysAgo = (Get-Date).AddDays(-30)

    try {
        $logNames = @('System', 'Application', 'Security')

        foreach ($logName in $logNames) {
            try {
                $logEvents = Get-WinEvent -LogName $logName -FilterXPath "*[System[Level=1 or Level=2] and System[TimeCreated[@SystemTime >= '$($thirtyDaysAgo.ToUniversalTime().ToString('o'))']]]" `
                    -ErrorAction SilentlyContinue -MaxEvents 1000

                if ($logEvents) {
                    $logEvents | ForEach-Object {
                        $events += @{
                            Timestamp   = $_.TimeCreated
                            LogName     = $logName
                            Level       = if ($_.Level -eq 1) { 'Critical' } else { 'Error' }
                            EventID     = $_.Id
                            Source      = $_.ProviderName
                            Message     = $_.Message -replace "`r`n", " " -replace "`n", " " | ForEach-Object { if ($_.Length -gt 200) { $_.Substring(0, 197) + "..." } else { $_ } }
                        }
                    }
                }
            }
            catch {
                Write-Log -Level WARN -Component HEALTH-AUDIT -Message "Failed to query $logName log: $_"
            }
        }
    }
    catch {
        Write-Log -Level WARN -Component HEALTH-AUDIT -Message "Error retrieving events: $_"
    }

    return @($events | Sort-Object -Property Timestamp -Descending)
}

function Get-WindowsDefenderIncidents {
    [CmdletBinding()]
    [OutputType([array])]
    param()

    $incidents = @()
    $thirtyDaysAgo = (Get-Date).AddDays(-30)

    try {
        # Query Windows Defender detection events from Event Viewer
        $defenderEvents = Get-WinEvent -LogName 'Microsoft-Windows-Windows Defender/Operational' `
            -FilterXPath "*[System[TimeCreated[@SystemTime >= '$($thirtyDaysAgo.ToUniversalTime().ToString('o'))']]]" `
            -ErrorAction SilentlyContinue -MaxEvents 500

        if ($defenderEvents) {
            $defenderEvents | ForEach-Object {
                $eventData = $_.Properties
                $incidents += @{
                    Timestamp       = $_.TimeCreated
                    EventID         = $_.Id
                    ThreatName      = if ($eventData[2]) { $eventData[2].Value } else { 'Unknown' }
                    Severity        = switch ($eventData[3]) {
                        { $_ -match 'Critical|High' } { 'High' }
                        { $_ -match 'Medium' } { 'Medium' }
                        { $_ -match 'Low|Informational' } { 'Low' }
                        default { 'Unknown' }
                    }
                    DetectionPath   = if ($eventData[7]) { $eventData[7].Value } else { 'N/A' }
                    Action          = if ($eventData[4]) { $eventData[4].Value } else { 'Unknown' }
                }
            }
        }
    }
    catch {
        Write-Log -Level WARN -Component HEALTH-AUDIT -Message "Error retrieving Windows Defender incidents: $_"
    }

    return @($incidents | Sort-Object -Property Timestamp -Descending)
}

function Get-WindowsDefenderExclusions {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    $exclusions = @{
        FileExclusions      = @()
        FolderExclusions    = @()
        ProcessExclusions   = @()
        ExtensionExclusions = @()
        QueryTime           = Get-Date -Format 'o'
    }

    try {
        # Try PowerShell cmdlet first (most reliable)
        if (Test-CommandAvailable 'Get-MpPreference') {
            try {
                $prefs = Get-MpPreference -ErrorAction SilentlyContinue

                if ($prefs.ExclusionPath) {
                    $exclusions.FolderExclusions = @($prefs.ExclusionPath | Select-Object -Unique)
                }
                if ($prefs.ExclusionExtension) {
                    $exclusions.ExtensionExclusions = @($prefs.ExclusionExtension | Select-Object -Unique)
                }
                if ($prefs.ExclusionProcess) {
                    $exclusions.ProcessExclusions = @($prefs.ExclusionProcess | Select-Object -Unique)
                }
                if ($prefs.ExclusionIpAddress) {
                    # Could also add network exclusions if needed
                }

                Write-Log -Level DEBUG -Component HEALTH-AUDIT -Message "Retrieved Defender exclusions via Get-MpPreference"
            }
            catch {
                Write-Log -Level WARN -Component HEALTH-AUDIT -Message "Get-MpPreference failed: $_"
            }
        }

        # Fallback: Query registry for exclusions
        if ($exclusions.FolderExclusions.Count -eq 0) {
            try {
                $regPath = 'HKLM:\Software\Microsoft\Windows Defender\Exclusions\Paths'
                if (Test-Path $regPath) {
                    Get-Item -Path $regPath | Select-Object -ExpandProperty Property | ForEach-Object {
                        $exclusions.FolderExclusions += $_
                    }
                }
            }
            catch {
                Write-Log -Level DEBUG -Component HEALTH-AUDIT -Message "Registry folder exclusions unavailable: $_"
            }
        }

        if ($exclusions.ExtensionExclusions.Count -eq 0) {
            try {
                $regPath = 'HKLM:\Software\Microsoft\Windows Defender\Exclusions\Extensions'
                if (Test-Path $regPath) {
                    Get-Item -Path $regPath | Select-Object -ExpandProperty Property | ForEach-Object {
                        $exclusions.ExtensionExclusions += $_
                    }
                }
            }
            catch {
                Write-Log -Level DEBUG -Component HEALTH-AUDIT -Message "Registry extension exclusions unavailable: $_"
            }
        }

        if ($exclusions.ProcessExclusions.Count -eq 0) {
            try {
                $regPath = 'HKLM:\Software\Microsoft\Windows Defender\Exclusions\Processes'
                if (Test-Path $regPath) {
                    Get-Item -Path $regPath | Select-Object -ExpandProperty Property | ForEach-Object {
                        $exclusions.ProcessExclusions += $_
                    }
                }
            }
            catch {
                Write-Log -Level DEBUG -Component HEALTH-AUDIT -Message "Registry process exclusions unavailable: $_"
            }
        }

        Write-Log -Level DEBUG -Component HEALTH-AUDIT -Message "Exclusions retrieved: Paths=$($exclusions.FolderExclusions.Count), Extensions=$($exclusions.ExtensionExclusions.Count), Processes=$($exclusions.ProcessExclusions.Count)"
    }
    catch {
        Write-Log -Level WARN -Component HEALTH-AUDIT -Message "Error retrieving Windows Defender exclusions: $_"
    }

    return $exclusions
}

#endregion

Export-ModuleMember -Function 'Invoke-SystemHealthAudit'
