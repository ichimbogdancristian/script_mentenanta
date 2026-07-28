#Requires -Version 7.0
<#
.SYNOPSIS    System Configuration Audit - Type 1 (Consolidated system-state audit)
.DESCRIPTION Single read-only pass over the whole machine. Produces one diff whose items are
             tagged with a ConfigType discriminator that SystemConfiguration (Type2) switches on:
               ConfigType = 'restorepoint'  restore point create / prune   (Action = create|remove)
               ConfigType = 'security'      Defender, firewall, security registry, Sysmon
               ConfigType = 'telemetry'     privacy services/registry/scheduled tasks
               ConfigType = 'optimization'  services, power plan, startup, visual fx, background

             It also gathers the two REPORT-ONLY datasets that used to live in the standalone
             SystemInventory / SystemHealthAudit modules (merged here in v7.0):
               temp_files/data/system-inventory.json      OS/CPU/memory/disk/network/users
               temp_files/data/system-health-report.json  event log, Defender incidents/exclusions
               temp_files/data/restore-point-audit.json   restore point detail for the report

             ORDER MATTERS (see Invoke-SystemConfigurationAudit): every actionable check runs and
             the diff is SAVED before the slow, report-only gathering starts, so a failure while
             collecting inventory/health can never cost us the diff Stage 3 depends on.

             Consumes baselines: security, telemetry, system-optimization.
.NOTES       Module Type: Type1 | DiffKey: SystemConfiguration | Version: 7.0 (Consolidated)
#>

$_corePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'core\Maintenance.psm1'
if (-not (Get-Command 'Write-Log' -ErrorAction SilentlyContinue)) {
    Import-Module $_corePath -Force -Global -WarningAction SilentlyContinue
}

#region ─── REGISTRY COMPARE (with fallback) ──────────────────────────────────

function Compare-RegistryBaselineWithFallback {
    param([Parameter(Mandatory)] $Entries)

    $results = @()

    # Layer 1: Try PowerShell native (fastest)
    try {
        $results = @(Compare-RegistryBaseline -Entries $Entries -ErrorAction Stop)
        Write-Log -Level DEBUG -Component CONFIG-AUDIT -Message "Registry baseline comparison via PowerShell succeeded (Layer 1)"
        return $results
    }
    catch {
        Write-Log -Level DEBUG -Component CONFIG-AUDIT -Message "PowerShell registry comparison failed: $_. Trying Layer 2 (registry.exe fallback)"
    }

    # Layer 2: Fallback to registry.exe queries
    try {
        foreach ($entry in $Entries) {
            if (-not $entry.path -or -not $entry.name) { continue }

            $regPath = $entry.path -replace 'HKEY_LOCAL_MACHINE\\', 'HKLM\'
            $regPath = $regPath -replace 'HKEY_CURRENT_USER\\', 'HKCU\'

            $regQuery = & reg query $regPath /v $entry.name 2>&1
            if ($regQuery -match 'REG_\w+\s+(.+?)(?:\s|$)') {
                $currentValue = $Matches[1].Trim()
                if ($currentValue -ne $entry.desiredValue.ToString()) {
                    $results += @{
                        path            = $entry.path
                        name            = $entry.name
                        currentValue    = $currentValue
                        desiredValue    = $entry.desiredValue
                        DetectionMethod = 'registry.exe'
                    }
                }
            }
        }
        if ($results) {
            Write-Log -Level DEBUG -Component CONFIG-AUDIT -Message "Registry baseline comparison via registry.exe succeeded (Layer 2)"
        }
        return $results
    }
    catch {
        Write-Log -Level WARN -Component CONFIG-AUDIT -Message "Registry fallback also failed: $_"
        return @()
    }
}

#endregion

#region ─── RESTORE POINTS ────────────────────────────────────────────────────

<#
.SYNOPSIS
    Queries the machine's system restore points ONCE, newest first.
.DESCRIPTION
    Both the restore-point diff and the inventory report used to run this same
    Win32_ShadowCopy query independently (two separate modules, two identical CIM calls).
    Consolidated into one query whose result feeds both consumers.
    Uses CIM rather than Get-ComputerRestorePoint, which is Windows PowerShell 5.1 only.
.OUTPUTS
    [array] of PSCustomObject: SequenceNumber, Description, CreationTime (DateTime),
    CreationTimeText, EventType, RestorePointType.
#>
function Get-SystemRestorePointList {
    [CmdletBinding()]
    [OutputType([array])]
    param()

    return @(Get-CimInstance -ClassName Win32_ShadowCopy -ErrorAction Stop |
        Sort-Object -Property InstallDate -Descending |
        ForEach-Object {
            $created = if ($_.InstallDate) { $_.InstallDate } else { [datetime]::Now }
            [PSCustomObject]@{
                # Raw Win32_ShadowCopy.ID ("{GUID}") - the only value that reliably
                # identifies the shadow copy again when Type2 goes to delete it.
                ShadowId         = $_.ID
                SequenceNumber   = $_.ID -replace '.*{|}', ''
                Description      = $_.Description ?? 'System Restore Point'
                CreationTime     = $created
                CreationTimeText = $created.ToString('yyyy-MM-dd HH:mm:ss')
                EventType        = 'ShadowCopy'
                RestorePointType = 'System'
            }
        })
}

#endregion

#region ─── SYSTEM HEALTH HELPERS ─────────────────────────────────────────────

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
                            Timestamp = $_.TimeCreated
                            LogName   = $logName
                            Level     = if ($_.Level -eq 1) { 'Critical' } else { 'Error' }
                            EventID   = $_.Id
                            Source    = $_.ProviderName
                            Message   = $_.Message -replace "`r`n", " " -replace "`n", " " | ForEach-Object { if ($_.Length -gt 200) { $_.Substring(0, 197) + "..." } else { $_ } }
                        }
                    }
                }
            }
            catch {
                Write-Log -Level WARN -Component CONFIG-AUDIT -Message "Failed to query $logName log: $_"
            }
        }
    }
    catch {
        Write-Log -Level WARN -Component CONFIG-AUDIT -Message "Error retrieving events: $_"
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
                    Timestamp     = $_.TimeCreated
                    EventID       = $_.Id
                    ThreatName    = if ($eventData[2]) { $eventData[2].Value } else { 'Unknown' }
                    Severity      = switch ($eventData[3]) {
                        { $_ -match 'Critical|High' } { 'High' }
                        { $_ -match 'Medium' } { 'Medium' }
                        { $_ -match 'Low|Informational' } { 'Low' }
                        default { 'Unknown' }
                    }
                    DetectionPath = if ($eventData[7]) { $eventData[7].Value } else { 'N/A' }
                    Action        = if ($eventData[4]) { $eventData[4].Value } else { 'Unknown' }
                }
            }
        }
    }
    catch {
        Write-Log -Level WARN -Component CONFIG-AUDIT -Message "Error retrieving Windows Defender incidents: $_"
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

                Write-Log -Level DEBUG -Component CONFIG-AUDIT -Message "Retrieved Defender exclusions via Get-MpPreference"
            }
            catch {
                Write-Log -Level WARN -Component CONFIG-AUDIT -Message "Get-MpPreference failed: $_"
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
                Write-Log -Level DEBUG -Component CONFIG-AUDIT -Message "Registry folder exclusions unavailable: $_"
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
                Write-Log -Level DEBUG -Component CONFIG-AUDIT -Message "Registry extension exclusions unavailable: $_"
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
                Write-Log -Level DEBUG -Component CONFIG-AUDIT -Message "Registry process exclusions unavailable: $_"
            }
        }

        Write-Log -Level DEBUG -Component CONFIG-AUDIT -Message "Exclusions retrieved: Paths=$($exclusions.FolderExclusions.Count), Extensions=$($exclusions.ExtensionExclusions.Count), Processes=$($exclusions.ProcessExclusions.Count)"
    }
    catch {
        Write-Log -Level WARN -Component CONFIG-AUDIT -Message "Error retrieving Windows Defender exclusions: $_"
    }

    return $exclusions
}

#endregion

#region ─── REPORT-ONLY GATHERERS ─────────────────────────────────────────────

<#
.SYNOPSIS
    Gathers the OS/hardware/network/user inventory and writes system-inventory.json.
.DESCRIPTION
    Report-only: contributes NO diff items. Every sub-query is individually guarded so a
    single failing CIM class degrades that one field rather than the whole inventory.
.PARAMETER RestorePoints
    The already-queried restore point list, reused here instead of re-running the CIM query.
.OUTPUTS
    [hashtable] the inventory (also written to temp_files/data/system-inventory.json).
#>
function Get-SystemInventoryData {
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param([Parameter()] [array]$RestorePoints = @())

    $inv = [ordered]@{ Timestamp = (Get-Date -Format 'o') }

    Write-Log -Level DEBUG -Component INVENTORY -Message 'Running hardware queries (OS, CPU, Memory, Disks)...'

    $os = $null; $cpu = $null; $cs = $null; $disks = $null

    try { $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop }
    catch { Write-Log -Level DEBUG -Component INVENTORY -Message "OS query failed: $_" }

    try { $cpu = Get-CimInstance Win32_Processor -ErrorAction Stop | Select-Object -First 1 }
    catch { Write-Log -Level DEBUG -Component INVENTORY -Message "CPU query failed: $_" }

    try { $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop }
    catch { Write-Log -Level DEBUG -Component INVENTORY -Message "ComputerSystem query failed: $_" }

    try { $disks = Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' -ErrorAction Stop }
    catch { Write-Log -Level DEBUG -Component INVENTORY -Message "Disk query failed: $_" }

    # OS
    try {
        if ($os) {
            $inv.OS = @{
                Caption        = $os.Caption
                Version        = $os.Version
                BuildNumber    = $os.BuildNumber
                Architecture   = $os.OSArchitecture
                InstallDate    = $os.InstallDate.ToString('yyyy-MM-dd')
                LastBootUpTime = $os.LastBootUpTime.ToString('yyyy-MM-dd HH:mm:ss')
                Locale         = $os.Locale
            }
            Write-Log -Level DEBUG -Component INVENTORY -Message "OS: $($os.Caption) build $($os.BuildNumber)"
        }
        else { Write-Log -Level WARN -Component INVENTORY -Message 'OS query failed' }
    }
    catch { Write-Log -Level WARN -Component INVENTORY -Message "OS processing failed: $_" }

    # CPU
    try {
        if ($cpu) {
            $inv.CPU = @{
                Name         = $cpu.Name
                Cores        = $cpu.NumberOfCores
                LogicalProcs = $cpu.NumberOfLogicalProcessors
                MaxClockMHz  = $cpu.MaxClockSpeed
            }
            Write-Log -Level DEBUG -Component INVENTORY -Message "CPU: $($cpu.Name) ($($cpu.NumberOfCores) cores)"
        }
        else { Write-Log -Level WARN -Component INVENTORY -Message 'CPU query failed' }
    }
    catch { Write-Log -Level WARN -Component INVENTORY -Message "CPU processing failed: $_" }

    # Memory
    try {
        if ($cs) {
            $inv.Memory = @{
                TotalGB      = [math]::Round($cs.TotalPhysicalMemory / 1GB, 2)
                Manufacturer = $cs.Manufacturer
                Model        = $cs.Model
            }
            Write-Log -Level DEBUG -Component INVENTORY -Message "Memory: $($inv.Memory.TotalGB) GB"
        }
        else { Write-Log -Level WARN -Component INVENTORY -Message 'Memory query failed' }
    }
    catch { Write-Log -Level WARN -Component INVENTORY -Message "Memory processing failed: $_" }

    # Disks
    try {
        if ($disks) {
            $inv.Disks = @($disks | ForEach-Object {
                    @{
                        Drive   = $_.DeviceID
                        SizeGB  = [math]::Round($_.Size / 1GB, 1)
                        FreeGB  = [math]::Round($_.FreeSpace / 1GB, 1)
                        UsedPct = if ($_.Size -gt 0) { [math]::Round((($_.Size - $_.FreeSpace) / $_.Size) * 100, 1) } else { 0 }
                        FS      = $_.FileSystem
                    }
                })
            Write-Log -Level DEBUG -Component INVENTORY -Message "Disks: $($inv.Disks.Count) found"
        }
        else { Write-Log -Level WARN -Component INVENTORY -Message 'Disk query failed' }
    }
    catch { Write-Log -Level WARN -Component INVENTORY -Message "Disk processing failed: $_" }

    # Network adapters & DNS
    try {
        $nics = Get-CimInstance Win32_NetworkAdapterConfiguration -Filter 'IPEnabled=True' -ErrorAction Stop
        $inv.Network = @($nics | ForEach-Object {
                @{
                    Description = $_.Description
                    MAC         = $_.MACAddress
                    IPs         = @($_.IPAddress | Where-Object { $_ })
                    DNSServers  = @($_.DNSServerSearchOrder | Where-Object { $_ })
                }
            })
    }
    catch { Write-Log -Level WARN -Component INVENTORY -Message "Network query failed: $_" }

    # External IP address
    try {
        $externalIP = $null
        $result = Invoke-RestMethod -Uri 'https://api.ipify.org?format=json' -TimeoutSec 5 -ErrorAction Stop
        if ($result.ip) { $externalIP = $result.ip }
        $inv.ExternalIP = @{ Address = $externalIP ?? 'Unable to determine' }
        Write-Log -Level DEBUG -Component INVENTORY -Message "External IP: $($inv.ExternalIP.Address)"
    }
    catch {
        Write-Log -Level WARN -Component INVENTORY -Message "External IP query failed (non-critical): $_"
        $inv.ExternalIP = @{ Address = 'Unable to determine' }
    }

    # OS Users (exclude system accounts)
    try {
        $systemAccounts = @('Administrator', 'Guest', 'DefaultAccount', 'WDAGUtilityAccount', 'SYSTEM', 'LOCAL SERVICE', 'NETWORK SERVICE')
        $inv.LocalUsers = @(Get-LocalUser -ErrorAction Stop |
            Where-Object { $_.Enabled -and $_.Name -notin $systemAccounts } |
            ForEach-Object {
                @{
                    Name      = $_.Name
                    FullName  = $_.FullName
                    Enabled   = $_.Enabled
                    LastLogon = if ($_.LastLogon) { $_.LastLogon.ToString('yyyy-MM-dd HH:mm:ss') } else { 'Never' }
                }
            })
        Write-Log -Level DEBUG -Component INVENTORY -Message "Local users found: $($inv.LocalUsers.Count)"
    }
    catch { Write-Log -Level WARN -Component INVENTORY -Message "Local users query failed: $_"; $inv.LocalUsers = @() }

    # Restore points - reuse the list already queried for the diff (no second CIM call).
    $inv.RestorePoints = @($RestorePoints | ForEach-Object {
            @{
                SequenceNumber   = $_.SequenceNumber
                Description      = $_.Description
                CreationTime     = $_.CreationTimeText
                EventType        = $_.EventType
                RestorePointType = $_.RestorePointType
            }
        })

    # Installed apps count
    try {
        $inv.Software = @{ InstalledAppCount = @(Get-InstalledApp).Count }
    }
    catch { Write-Log -Level WARN -Component INVENTORY -Message "Installed apps count failed: $_" }

    # Session info
    $inv.Session = @{
        ComputerName = $env:COMPUTERNAME
        UserName     = $env:USERNAME
        Domain       = $env:USERDOMAIN
        IsAdmin      = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }

    $invPath = Get-TempPath -Category 'data' -FileName 'system-inventory.json'
    $inv | ConvertTo-Json -Depth 8 | Set-Content -Path $invPath -Encoding UTF8 -Force
    Write-Log -Level SUCCESS -Component INVENTORY -Message "System inventory saved: $invPath"

    return $inv
}

<#
.SYNOPSIS
    Gathers event-log / Defender health data and writes system-health-report.json.
.DESCRIPTION
    Report-only: contributes NO diff items. This is the slowest part of the audit
    (Get-WinEvent across System/Application/Security for 30 days), which is why it runs
    last, after the diff has already been persisted.
.OUTPUTS
    [hashtable] the health report's Summary block.
#>
function Get-SystemHealthData {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    $healthReport = @{
        Timestamp          = (Get-Date -Format 'o')
        EventViewerEvents  = $null
        DefenderIncidents  = $null
        DefenderExclusions = $null
        Summary            = @{}
    }

    Write-Log -Level DEBUG -Component HEALTH -Message 'Gathering critical and error events from Event Viewer...'
    $events = Get-CriticalErrorEvents
    $healthReport.EventViewerEvents = $events
    $healthReport.Summary.TotalCriticalErrorEvents = $events.Count
    Write-Log -Level INFO -Component HEALTH -Message "Event Viewer: $($events.Count) critical/error events in last 30 days"

    Write-Log -Level DEBUG -Component HEALTH -Message 'Gathering Windows Defender incidents...'
    $incidents = Get-WindowsDefenderIncidents
    $healthReport.DefenderIncidents = $incidents
    $healthReport.Summary.TotalDefenderIncidents = $incidents.Count
    Write-Log -Level INFO -Component HEALTH -Message "Windows Defender: $($incidents.Count) incidents in last 30 days"

    Write-Log -Level DEBUG -Component HEALTH -Message 'Gathering Windows Defender exclusions...'
    $exclusions = Get-WindowsDefenderExclusions
    $healthReport.DefenderExclusions = $exclusions
    $healthReport.Summary.TotalDefenderExclusions = $exclusions.FileExclusions.Count + $exclusions.FolderExclusions.Count +
    $exclusions.ProcessExclusions.Count + $exclusions.ExtensionExclusions.Count
    Write-Log -Level INFO -Component HEALTH -Message "Defender exclusions: Files=$($exclusions.FileExclusions.Count), Folders=$($exclusions.FolderExclusions.Count), Processes=$($exclusions.ProcessExclusions.Count), Extensions=$($exclusions.ExtensionExclusions.Count)"

    $reportPath = Get-TempPath -Category 'data' -FileName 'system-health-report.json'
    $healthReport | ConvertTo-Json -Depth 10 | Set-Content -Path $reportPath -Encoding UTF8 -Force
    Write-Log -Level SUCCESS -Component HEALTH -Message "Health report saved: $reportPath"

    return $healthReport.Summary
}

#endregion

#region ─── MAIN AUDIT ────────────────────────────────────────────────────────

function Invoke-SystemConfigurationAudit {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    Write-Log -Level INFO -Component CONFIG-AUDIT -Message 'Starting system configuration audit (restore point + security + telemetry + optimization + inventory + health)'

    try {
        $osCtx = (Get-Variable -Name 'OSContext' -Scope Global -ValueOnly -ErrorAction SilentlyContinue)
        if (-not $osCtx) { $osCtx = Get-OSContext }

        $config = Get-MainConfig
        $skipRestorePoint = [bool]($config.modules.skipRestorePointManagement)
        $skipHealth = [bool]($config.modules.skipSystemHealth)
        # Sub-feature switches for the two policy areas that change how users log in.
        $skipPasswordPolicy = [bool]($config.modules.systemConfiguration.skipPasswordPolicy)
        $skipAuditPolicy = [bool]($config.modules.systemConfiguration.skipAuditPolicy)

        $diff = [System.Collections.Generic.List[hashtable]]::new()
        $restorePoints = @()
        $rpToRemove = 0
        $minToKeep = 5
        $allocationGB = 10

        # ══════════════════════════════════════════════════════════════════════
        # PHASE A - ACTIONABLE AUDIT. Everything Stage 2/3 depends on is computed
        # here and the diff is saved at the end of the phase, BEFORE the slow
        # report-only gathering in Phase B.
        # ══════════════════════════════════════════════════════════════════════

        # ═══ A1. RESTORE POINTS ══════════════════════════════════════════════
        # Queued FIRST so the create item is the first thing Type2 sees. The 'create'
        # item is queued UNCONDITIONALLY (unless skipped by config): it is the rollback
        # safety net for every other change in this run, and it also guarantees this
        # pair's diff is never empty, so Stage 2 always schedules Type2.
        if ($skipRestorePoint) {
            Write-Log -Level INFO -Component CONFIG-AUDIT -Message 'Restore point management skipped (config: skipRestorePointManagement)'
        }
        else {
            try {
                $restorePoints = Get-SystemRestorePointList
                Write-Log -Level INFO -Component CONFIG-AUDIT -Message "Current restore points: $($restorePoints.Count)"

                # Create a fresh one every run.
                $diff.Add(@{
                        ConfigType   = 'restorepoint'
                        Type         = 'restorepoint'
                        Action       = 'create'
                        Name         = 'CreateRestorePoint'
                        Description  = "Maintenance: $([datetime]::Now.ToString('yyyy-MM-dd HH:mm'))"
                        AllocationGB = $allocationGB
                    })

                # Prune anything beyond the newest $minToKeep.
                if ($restorePoints.Count -gt $minToKeep) {
                    foreach ($point in $restorePoints[$minToKeep..($restorePoints.Count - 1)]) {
                        $diff.Add(@{
                                ConfigType       = 'restorepoint'
                                Type             = 'restorepoint'
                                Action           = 'remove'
                                Name             = "RestorePoint-$($point.SequenceNumber)"
                                ShadowId         = $point.ShadowId
                                SequenceNumber   = $point.SequenceNumber
                                Description      = $point.Description
                                CreationTime     = $point.CreationTimeText
                                EventType        = $point.EventType
                                RestorePointType = $point.RestorePointType
                            })
                        $rpToRemove++
                        Write-Log -Level DEBUG -Component CONFIG-AUDIT -Message "Marked for removal: $($point.Description) (seq: $($point.SequenceNumber), created: $($point.CreationTimeText))"
                    }
                }
                Write-Log -Level INFO -Component CONFIG-AUDIT -Message "Restore points: $($restorePoints.Count) current, $rpToRemove to prune, 1 to create"
            }
            catch {
                # A failed restore point QUERY must not cost us the create action - that is
                # the safety net. Queue the create anyway and carry on with the rest.
                Write-Log -Level WARN -Component CONFIG-AUDIT -Message "Could not enumerate restore points: $_ - queuing create only"
                $diff.Add(@{
                        ConfigType   = 'restorepoint'
                        Type         = 'restorepoint'
                        Action       = 'create'
                        Name         = 'CreateRestorePoint'
                        Description  = "Maintenance: $([datetime]::Now.ToString('yyyy-MM-dd HH:mm'))"
                        AllocationGB = $allocationGB
                    })
            }
        }

        # ═══ A2. SECURITY ════════════════════════════════════════════════════
        $securityBaseline = Get-BaselineList -ModuleFolder 'security' -FileName 'security-baseline.json'
        if ($securityBaseline) {
            Write-Log -Level DEBUG -Component CONFIG-AUDIT -Message 'Auditing security settings...'

            # Security registry (with fallback detection)
            if ($securityBaseline.registry) {
                Compare-RegistryBaselineWithFallback -Entries @($securityBaseline.registry) | ForEach-Object {
                    $_.ConfigType = 'security'
                    $diff.Add($_)
                }
            }

            # Services that must be running / disabled for a hardened baseline
            if ($securityBaseline.services.ensureDisabled) {
                Compare-ServiceBaseline -ServiceNames @($securityBaseline.services.ensureDisabled) -Action 'EnsureDisabled' | ForEach-Object {
                    $_.ConfigType = 'security'
                    $diff.Add($_)
                }
            }
            if ($securityBaseline.services.ensureRunning) {
                Compare-ServiceBaseline -ServiceNames @($securityBaseline.services.ensureRunning) -Action 'EnsureRunning' | ForEach-Object {
                    $_.ConfigType = 'security'
                    $diff.Add($_)
                }
            }

            # Windows Defender feature checks
            if ($securityBaseline.windowsDefender) {
                $wd = $securityBaseline.windowsDefender
                try {
                    $mpStatus = Get-MpComputerStatus -ErrorAction Stop
                    if ($wd.realTimeProtection -and -not $mpStatus.RealTimeProtectionEnabled) {
                        $diff.Add(@{ ConfigType = 'security'; Type = 'defender'; Name = 'RealTimeProtection'; Feature = 'RealTimeProtection'; ShouldEnable = $true; CurrentState = $false; DesiredState = $true })
                        Write-Log -Level WARN -Component CONFIG-AUDIT -Message 'Defender: Real-time protection DISABLED'
                    }
                    if (-not $mpStatus.AntivirusEnabled) {
                        $diff.Add(@{ ConfigType = 'security'; Type = 'defender'; Name = 'AntivirusEnabled'; Feature = 'AntivirusEnabled'; ShouldEnable = $true; CurrentState = $false; DesiredState = $true })
                    }
                }
                catch {
                    Write-Log -Level WARN -Component CONFIG-AUDIT -Message "Defender status query failed: $_"
                }
                try {
                    $mpPrefs = Get-MpPreference -ErrorAction Stop
                    if ($wd.cloudProtection -and $mpPrefs.MAPSReporting -eq 0) {
                        $diff.Add(@{ ConfigType = 'security'; Type = 'defender'; Name = 'CloudProtection'; Feature = 'CloudProtection'; ShouldEnable = $true; CurrentState = $false; DesiredState = $true })
                    }
                    if ($wd.networkProtection -and $mpPrefs.EnableNetworkProtection -eq 0) {
                        $diff.Add(@{ ConfigType = 'security'; Type = 'defender'; Name = 'NetworkProtection'; Feature = 'NetworkProtection'; ShouldEnable = $true; CurrentState = $false; DesiredState = $true })
                    }
                    if ($wd.pua -and $mpPrefs.PUAProtection -eq 0) {
                        $diff.Add(@{ ConfigType = 'security'; Type = 'defender'; Name = 'PUAProtection'; Feature = 'PUAProtection'; ShouldEnable = $true; CurrentState = $false; DesiredState = $true })
                    }
                }
                catch {
                    Write-Log -Level WARN -Component CONFIG-AUDIT -Message "Defender preference query failed: $_"
                }
            }

            # Firewall profiles
            if ($securityBaseline.firewall.enabled) {
                try {
                    $fwProfiles = Get-NetFirewallProfile -ErrorAction Stop
                    foreach ($profileName in @('Domain', 'Private', 'Public')) {
                        $key = $profileName.ToLowerInvariant()
                        if ($securityBaseline.firewall.enabled.$key) {
                            $prof = $fwProfiles | Where-Object { $_.Name -eq $profileName }
                            if ($prof -and -not $prof.Enabled) {
                                $diff.Add(@{ ConfigType = 'security'; Type = 'firewall'; Name = "Firewall.$profileName"; Profile = $profileName; CurrentState = $false; DesiredState = $true })
                            }
                        }
                    }
                }
                catch { Write-Log -Level WARN -Component CONFIG-AUDIT -Message "Firewall query failed: $_" }
            }

            # ── Local security policy: CIS 1.1 password + 1.2 account lockout ────
            # These are NOT registry values - they live in the Local Security Policy
            # database and are only reachable via secedit. The baseline has declared a
            # securityPolicy block for a long time but NOTHING read it, so every one of
            # these CIS rules stayed non-compliant no matter how often the run completed.
            if ($securityBaseline.securityPolicy -and -not $skipPasswordPolicy) {
                Compare-SecurityPolicyBaseline -Baseline $securityBaseline.securityPolicy | ForEach-Object {
                    $_.ConfigType = 'security'
                    $diff.Add($_)
                }
            }
            elseif ($skipPasswordPolicy) {
                Write-Log -Level INFO -Component CONFIG-AUDIT -Message 'Password/lockout policy skipped (config: skipPasswordPolicy)'
            }

            # ── Advanced audit policy: CIS 17.x ──────────────────────────────────
            # Same story: auditpol-only, declared in the baseline, never consumed.
            if ($securityBaseline.auditPolicy -and -not $skipAuditPolicy) {
                Compare-AuditPolicyBaseline -Baseline $securityBaseline.auditPolicy | ForEach-Object {
                    $_.ConfigType = 'security'
                    $diff.Add($_)
                }
            }
            elseif ($skipAuditPolicy) {
                Write-Log -Level INFO -Component CONFIG-AUDIT -Message 'Advanced audit policy skipped (config: skipAuditPolicy)'
            }

            # Sysmon presence check (installed via SystemConfiguration Type2 with sysmonconfig.xml)
            $sysmonSvc = Get-Service -Name 'Sysmon', 'Sysmon64' -ErrorAction SilentlyContinue | Select-Object -First 1
            if (-not $sysmonSvc) {
                $diff.Add(@{ ConfigType = 'security'; Type = 'sysmon'; Name = 'Sysmon'; CurrentState = 'NotInstalled'; DesiredState = 'Installed' })
                Write-Log -Level INFO -Component CONFIG-AUDIT -Message 'Sysmon not installed - queued for install'
            }
        }

        # ═══ A3. TELEMETRY / PRIVACY ═════════════════════════════════════════
        $telemetryBaseline = Get-BaselineList -ModuleFolder 'telemetry' -FileName 'telemetry-list.json'
        if ($telemetryBaseline) {
            Write-Log -Level DEBUG -Component CONFIG-AUDIT -Message 'Auditing telemetry/privacy settings...'

            if ($telemetryBaseline.services.disable) {
                Compare-ServiceBaseline -ServiceNames @($telemetryBaseline.services.disable) -Action 'EnsureDisabled' | ForEach-Object {
                    $_.ConfigType = 'telemetry'
                    $diff.Add($_)
                }
            }

            if ($telemetryBaseline.registry) {
                foreach ($grp in @('telemetry', 'advertising', 'cortana', 'privacy')) {
                    if (-not $telemetryBaseline.registry.$grp) { continue }
                    Compare-RegistryBaselineWithFallback -Entries @($telemetryBaseline.registry.$grp) | ForEach-Object {
                        $_.ConfigType = 'telemetry'
                        $diff.Add($_)
                    }
                }
            }

            if ($telemetryBaseline.scheduledTasks.disable) {
                foreach ($taskPath in $telemetryBaseline.scheduledTasks.disable) {
                    try {
                        $taskName = Split-Path $taskPath -Leaf
                        $taskFolder = Split-Path $taskPath -Parent
                        $task = Get-ScheduledTask -TaskName $taskName -TaskPath "$taskFolder\" -ErrorAction SilentlyContinue
                        if ($task -and $task.State -ne 'Disabled') {
                            $diff.Add(@{ ConfigType = 'telemetry'; Type = 'scheduledtask'; Name = $taskPath; TaskPath = "$taskFolder\"; TaskName = $taskName; CurrentState = $task.State.ToString(); DesiredState = 'Disabled' })
                        }
                    }
                    catch { Write-Log -Level WARN -Component CONFIG-AUDIT -Message "Task query failed '$taskPath': $_" }
                }
            }
        }

        # ═══ A4. OPTIMIZATION ════════════════════════════════════════════════
        $optBaseline = Get-BaselineList -ModuleFolder 'system-optimization' -FileName 'system-optimization-config.json'
        if ($optBaseline -and $optBaseline.common) {
            Write-Log -Level DEBUG -Component CONFIG-AUDIT -Message 'Auditing optimization settings...'

            # Services to disable
            $svcsToDisable = [System.Collections.Generic.List[string]]::new()
            if ($optBaseline.common.services.safeToDisable) { $optBaseline.common.services.safeToDisable | ForEach-Object { $svcsToDisable.Add($_) } }
            if ($osCtx.IsWindows11 -and $optBaseline.windows11.services.safeToDisable) {
                $optBaseline.windows11.services.safeToDisable | ForEach-Object { $svcsToDisable.Add($_) }
            }
            elseif (-not $osCtx.IsWindows11 -and $optBaseline.windows10.services.safeToDisable) {
                $optBaseline.windows10.services.safeToDisable | ForEach-Object { $svcsToDisable.Add($_) }
            }
            Compare-ServiceBaseline -ServiceNames @($svcsToDisable) -Action 'EnsureDisabled' | ForEach-Object {
                $_.ConfigType = 'optimization'
                $diff.Add($_)
            }

            # Power plan
            if ($optBaseline.common.powerPlan.defaultPlan) {
                $desiredPlan = $optBaseline.common.powerPlan.defaultPlan
                try {
                    $powercfg = Join-Path $env:SystemRoot 'System32\powercfg.exe'
                    $currentPlan = & $powercfg /getactivescheme 2>&1
                    if ($currentPlan -notmatch [regex]::Escape($desiredPlan)) {
                        # foreach, NOT `| ForEach-Object`: the pipeline scriptblock gets its own
                        # scope, so assigning $planGuid in there only updated a copy and the
                        # lookup ALWAYS fell through to the hard-coded GUID below - i.e. the
                        # baseline's defaultPlan name was effectively ignored. Same scope trap
                        # as the old per-section counters.
                        $planGuid = $null
                        foreach ($line in (& $powercfg /list 2>&1)) {
                            if ($line -match 'GUID:\s+([0-9a-f-]{36})\s+\(([^)]+)\)' -and $Matches[2] -like "*$desiredPlan*") {
                                $planGuid = $Matches[1]
                                break
                            }
                        }
                        if (-not $planGuid) {
                            Write-Log -Level WARN -Component CONFIG-AUDIT -Message "Power plan '$desiredPlan' not found in powercfg /list - falling back to the High Performance GUID"
                        }
                        $diff.Add(@{ ConfigType = 'optimization'; Type = 'powerplan'; Name = 'ActivePlan'; GUID = $planGuid ?? '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'; CurrentState = "$currentPlan"; DesiredState = $desiredPlan })
                    }
                }
                catch { Write-Log -Level WARN -Component CONFIG-AUDIT -Message "Power plan query failed: $_" }
            }

            # Startup programs
            if ($optBaseline.common.startupPrograms) {
                $safePatterns = $optBaseline.common.startupPrograms.safeToDisablePatterns ?? @()
                $neverDisable = $optBaseline.common.startupPrograms.neverDisable ?? @()
                $runPaths = @(
                    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
                    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
                )
                foreach ($runPath in $runPaths) {
                    try {
                        $props = Get-ItemProperty -Path $runPath -ErrorAction SilentlyContinue
                        if (-not $props) { continue }
                        $props.PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' } | ForEach-Object {
                            $entryName = $_.Name
                            $isSafe = $false
                            foreach ($pattern in $safePatterns) { if ($entryName -like $pattern) { $isSafe = $true; break } }
                            if (-not $isSafe) { continue }
                            $isProtected = $false
                            foreach ($pattern in $neverDisable) { if ($entryName -like $pattern) { $isProtected = $true; break } }
                            if ($isProtected) { continue }
                            $diff.Add(@{ ConfigType = 'optimization'; Type = 'startup'; Name = $entryName; RegistryPath = $runPath; CurrentState = 'Enabled'; DesiredState = 'Disabled' })
                        }
                    }
                    catch { Write-Log -Level WARN -Component CONFIG-AUDIT -Message "Failed to read $runPath : $_" }
                }
            }

            # Visual effects
            $visualPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects'
            $currentVisual = Get-RegistryValue -Path $visualPath -Name 'VisualFXSetting'
            if ($null -eq $currentVisual -or $currentVisual -ne 3) {
                $diff.Add(@{ ConfigType = 'optimization'; Type = 'visualfx'; Name = 'VisualFXSetting'; CurrentState = $currentVisual; DesiredState = 3 })
            }

            # Desktop background (Spotlight -> Picture)
            if ($optBaseline.common.background.type -eq 'Picture') {
                $cdmPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
                $spotlightEnabled = Get-RegistryValue -Path $cdmPath -Name 'RotatingLockScreenEnabled'
                $cdmSubscriptions = Get-RegistryValue -Path $cdmPath -Name 'SubscribedContent-338387Enabled'
                if ($spotlightEnabled -eq 1 -or $cdmSubscriptions -eq 1) {
                    $diff.Add(@{ ConfigType = 'optimization'; Type = 'background'; Name = 'DesktopBackground'; CurrentState = 'Spotlight'; DesiredState = 'Picture' })
                }
            }
        }

        # ── Counts are derived from the finished diff, never incremented inside a
        #    ForEach-Object: that scriptblock gets its own scope, so `$n++` in there
        #    updates a throwaway copy and the outer counter stays at 0 (the old
        #    per-section counters silently under-reported for exactly this reason).
        $restorePointFound = @($diff | Where-Object { $_.ConfigType -eq 'restorepoint' }).Count
        $securityFound = @($diff | Where-Object { $_.ConfigType -eq 'security' }).Count
        $telemetryFound = @($diff | Where-Object { $_.ConfigType -eq 'telemetry' }).Count
        $optimizationFound = @($diff | Where-Object { $_.ConfigType -eq 'optimization' }).Count

        Write-Log -Level INFO -Component CONFIG-AUDIT -Message "Configuration items found: $($diff.Count) (RestorePoint: $restorePointFound, Security: $securityFound, Telemetry: $telemetryFound, Optimization: $optimizationFound)"

        # ── SAVE THE DIFF NOW ────────────────────────────────────────────────
        # Phase B below is slow and report-only. Persisting the diff here means a
        # failure while gathering inventory/health cannot lose the work Stage 3 runs on.
        Save-DiffList -ModuleName 'SystemConfiguration' -DiffList $diff.ToArray()

        $auditPath = Get-TempPath -Category 'data' -FileName 'system-configuration-audit.json'
        @{
            Timestamp         = (Get-Date -Format 'o')
            TotalItems        = $diff.Count
            RestorePointItems = $restorePointFound
            SecurityItems     = $securityFound
            TelemetryItems    = $telemetryFound
            OptimizationItems = $optimizationFound
            OS                = $osCtx.DisplayText
        } | ConvertTo-Json -Depth 6 | Set-Content -Path $auditPath -Encoding UTF8 -Force

        # Restore point detail for the report section.
        if (-not $skipRestorePoint) {
            try {
                $rpPath = Get-TempPath -Category 'data' -FileName 'restore-point-audit.json'
                @{
                    Timestamp         = Get-Date -Format 'o'
                    CurrentCount      = $restorePoints.Count
                    MinimumToKeep     = $minToKeep
                    ToRemove          = $rpToRemove
                    ToCreate          = 1
                    AllocationGB      = $allocationGB
                    RestorePointsList = @($restorePoints | ForEach-Object {
                            @{
                                SequenceNumber   = $_.SequenceNumber
                                Description      = $_.Description
                                CreationTime     = $_.CreationTimeText
                                EventType        = $_.EventType
                                RestorePointType = $_.RestorePointType
                            }
                        })
                } | ConvertTo-Json -Depth 8 | Set-Content -Path $rpPath -Encoding UTF8 -Force
            }
            catch { Write-Log -Level WARN -Component CONFIG-AUDIT -Message "Could not write restore point audit data: $_" }
        }

        # ══════════════════════════════════════════════════════════════════════
        # PHASE B - REPORT-ONLY GATHERING. Contributes no diff items. Each block is
        # isolated: a failure here degrades the report, never the maintenance run.
        # ══════════════════════════════════════════════════════════════════════

        $reportOnlyWarnings = @()

        # ═══ B1. INVENTORY ═══════════════════════════════════════════════════
        $inventory = $null
        try {
            $inventory = Get-SystemInventoryData -RestorePoints $restorePoints
        }
        catch {
            Write-Log -Level WARN -Component CONFIG-AUDIT -Message "System inventory gathering failed (report-only): $_"
            $reportOnlyWarnings += "Inventory: $_"
        }

        # ═══ B2. HEALTH ══════════════════════════════════════════════════════
        $healthSummary = @{}
        if ($skipHealth) {
            Write-Log -Level INFO -Component CONFIG-AUDIT -Message 'System health gathering skipped (config: skipSystemHealth)'
        }
        else {
            try {
                $healthSummary = Get-SystemHealthData
            }
            catch {
                Write-Log -Level WARN -Component CONFIG-AUDIT -Message "System health gathering failed (report-only): $_"
                $reportOnlyWarnings += "Health: $_"
            }
        }

        # ── Result ───────────────────────────────────────────────────────────
        $extra = @{
            RestorePointItems = $restorePointFound
            SecurityItems     = $securityFound
            TelemetryItems    = $telemetryFound
            OptimizationItems = $optimizationFound
            RestorePoints     = @{
                CurrentCount = $restorePoints.Count
                ToRemove     = $rpToRemove
                ToCreate     = if ($skipRestorePoint) { 0 } else { 1 }
            }
            HasInventory      = ($null -ne $inventory)
        }
        foreach ($k in $healthSummary.Keys) { $extra[$k] = $healthSummary[$k] }

        # Report-only trouble is a Warning, never a Failure: the diff (the actual
        # contract with Stage 2/3) was computed and saved successfully.
        $status = if ($reportOnlyWarnings.Count -gt 0) { 'Warning' } else { 'Success' }

        return New-ModuleResult -ModuleName 'SystemConfigurationAudit' -Status $status -ModuleType 'Type1' `
            -ItemsDetected $diff.Count -Errors $reportOnlyWarnings `
            -Message "$($diff.Count) config item(s): $restorePointFound restore point, $securityFound security, $telemetryFound telemetry, $optimizationFound optimization" `
            -ExtraData $extra
    }
    catch {
        Write-Log -Level ERROR -Component CONFIG-AUDIT -Message "Audit failed: $_"
        return New-ModuleResult -ModuleName 'SystemConfigurationAudit' -Status 'Failed' -ModuleType 'Type1' -Errors @($_.ToString())
    }
}

#endregion

Export-ModuleMember -Function 'Invoke-SystemConfigurationAudit'
