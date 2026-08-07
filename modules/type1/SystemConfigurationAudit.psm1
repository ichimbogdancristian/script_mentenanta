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

<#
.SYNOPSIS
    Phase A2 of the configuration audit: security baseline -> diff items.
.DESCRIPTION
    Extracted verbatim from Invoke-SystemConfigurationAudit. Covers all three CIS
    enforcement mechanisms, which are NOT interchangeable - a rule in the wrong baseline
    block is silently never enforced:
      registry       -> Compare-RegistryBaselineWithFallback  (CIS 2.3.x / 18.x)
      securityPolicy -> Compare-SecurityPolicyBaseline (secedit, CIS 1.1 / 1.2)
      auditPolicy    -> Compare-AuditPolicyBaseline    (auditpol, CIS 17.x)
    plus Defender feature state, firewall profiles, services and Sysmon presence.
.OUTPUTS
    [hashtable[]] diff items, every one tagged ConfigType = 'security'.
#>
function Get-SecurityConfigurationDiff {
    [CmdletBinding()]
    [OutputType([hashtable[]])]
    param(
        [Parameter(Mandatory)] [AllowNull()] $Baseline,
        [Parameter()] [bool]$SkipPasswordPolicy,
        [Parameter()] [bool]$SkipAuditPolicy
    )
    $items = [System.Collections.Generic.List[hashtable]]::new()
    if ($Baseline) {
        Write-Log -Level DEBUG -Component CONFIG-AUDIT -Message 'Auditing security settings...'

        # Security registry (with fallback detection)
        if ($Baseline.registry) {
            Compare-RegistryBaselineWithFallback -Entries @($Baseline.registry) | ForEach-Object {
                $_.ConfigType = 'security'
                $items.Add($_)
            }
        }

        # Services that must be running / disabled for a hardened baseline
        if ($Baseline.services.ensureDisabled) {
            Compare-ServiceBaseline -ServiceNames @($Baseline.services.ensureDisabled) -Action 'EnsureDisabled' | ForEach-Object {
                $_.ConfigType = 'security'
                $items.Add($_)
            }
        }
        if ($Baseline.services.ensureRunning) {
            Compare-ServiceBaseline -ServiceNames @($Baseline.services.ensureRunning) -Action 'EnsureRunning' | ForEach-Object {
                $_.ConfigType = 'security'
                $items.Add($_)
            }
        }

        # Windows Defender feature checks
        if ($Baseline.windowsDefender) {
            $wd = $Baseline.windowsDefender
            try {
                $mpStatus = Get-MpComputerStatus -ErrorAction Stop
                if ($wd.realTimeProtection -and -not $mpStatus.RealTimeProtectionEnabled) {
                    $items.Add(@{ ConfigType = 'security'; Type = 'defender'; Name = 'RealTimeProtection'; Feature = 'RealTimeProtection'; ShouldEnable = $true; CurrentState = $false; DesiredState = $true })
                    Write-Log -Level WARN -Component CONFIG-AUDIT -Message 'Defender: Real-time protection DISABLED'
                }
                if (-not $mpStatus.AntivirusEnabled) {
                    $items.Add(@{ ConfigType = 'security'; Type = 'defender'; Name = 'AntivirusEnabled'; Feature = 'AntivirusEnabled'; ShouldEnable = $true; CurrentState = $false; DesiredState = $true })
                }
            }
            catch {
                Write-Log -Level WARN -Component CONFIG-AUDIT -Message "Defender status query failed: $_"
            }
            try {
                $mpPrefs = Get-MpPreference -ErrorAction Stop
                if ($wd.cloudProtection -and $mpPrefs.MAPSReporting -eq 0) {
                    $items.Add(@{ ConfigType = 'security'; Type = 'defender'; Name = 'CloudProtection'; Feature = 'CloudProtection'; ShouldEnable = $true; CurrentState = $false; DesiredState = $true })
                }
                if ($wd.networkProtection -and $mpPrefs.EnableNetworkProtection -eq 0) {
                    $items.Add(@{ ConfigType = 'security'; Type = 'defender'; Name = 'NetworkProtection'; Feature = 'NetworkProtection'; ShouldEnable = $true; CurrentState = $false; DesiredState = $true })
                }
                if ($wd.pua -and $mpPrefs.PUAProtection -eq 0) {
                    $items.Add(@{ ConfigType = 'security'; Type = 'defender'; Name = 'PUAProtection'; Feature = 'PUAProtection'; ShouldEnable = $true; CurrentState = $false; DesiredState = $true })
                }
            }
            catch {
                Write-Log -Level WARN -Component CONFIG-AUDIT -Message "Defender preference query failed: $_"
            }
        }

        # Firewall profiles
        if ($Baseline.firewall.enabled) {
            try {
                $fwProfiles = Get-NetFirewallProfile -ErrorAction Stop
                foreach ($profileName in @('Domain', 'Private', 'Public')) {
                    $key = $profileName.ToLowerInvariant()
                    if ($Baseline.firewall.enabled.$key) {
                        $prof = $fwProfiles | Where-Object { $_.Name -eq $profileName }
                        if ($prof -and -not $prof.Enabled) {
                            $items.Add(@{ ConfigType = 'security'; Type = 'firewall'; Name = "Firewall.$profileName"; Profile = $profileName; CurrentState = $false; DesiredState = $true })
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
        if ($Baseline.securityPolicy -and -not $SkipPasswordPolicy) {
            Compare-SecurityPolicyBaseline -Baseline $Baseline.securityPolicy | ForEach-Object {
                $_.ConfigType = 'security'
                $items.Add($_)
            }
        }
        elseif ($SkipPasswordPolicy) {
            Write-Log -Level INFO -Component CONFIG-AUDIT -Message 'Password/lockout policy skipped (config: skipPasswordPolicy)'
        }

        # ── Advanced audit policy: CIS 17.x ──────────────────────────────────
        # Same story: auditpol-only, declared in the baseline, never consumed.
        if ($Baseline.auditPolicy -and -not $SkipAuditPolicy) {
            Compare-AuditPolicyBaseline -Baseline $Baseline.auditPolicy | ForEach-Object {
                $_.ConfigType = 'security'
                $items.Add($_)
            }
        }
        elseif ($SkipAuditPolicy) {
            Write-Log -Level INFO -Component CONFIG-AUDIT -Message 'Advanced audit policy skipped (config: skipAuditPolicy)'
        }

        # Sysmon presence check (installed via SystemConfiguration Type2 with sysmonconfig.xml)
        $sysmonSvc = Get-Service -Name 'Sysmon', 'Sysmon64' -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $sysmonSvc) {
            $items.Add(@{ ConfigType = 'security'; Type = 'sysmon'; Name = 'Sysmon'; CurrentState = 'NotInstalled'; DesiredState = 'Installed' })
            Write-Log -Level INFO -Component CONFIG-AUDIT -Message 'Sysmon not installed - queued for install'
        }
    }
    # NO comma-wrap. `return , $arr` emits the array as ONE pipeline element, so a caller
    # writing @(Get-...) gets a 1-element array CONTAINING the array instead of the items -
    # and the callers below do exactly that. Returning it plainly lets the pipeline unroll,
    # and the caller's @() then normalises 0/1/N uniformly. (Get-DiffList uses the comma
    # because ITS callers use plain assignment, not @(). The two idioms must not be mixed.)
    return $items.ToArray()
}

<#
.SYNOPSIS
    Phase A3 of the configuration audit: telemetry/privacy baseline -> diff items.
.OUTPUTS
    [hashtable[]] diff items, every one tagged ConfigType = 'telemetry'.
#>
function Get-TelemetryConfigurationDiff {
    [CmdletBinding()]
    [OutputType([hashtable[]])]
    param(
        [Parameter(Mandatory)] [AllowNull()] $Baseline
    )
    $items = [System.Collections.Generic.List[hashtable]]::new()
    if ($Baseline) {
        Write-Log -Level DEBUG -Component CONFIG-AUDIT -Message 'Auditing telemetry/privacy settings...'

        if ($Baseline.services.disable) {
            Compare-ServiceBaseline -ServiceNames @($Baseline.services.disable) -Action 'EnsureDisabled' | ForEach-Object {
                $_.ConfigType = 'telemetry'
                $items.Add($_)
            }
        }

        if ($Baseline.registry) {
            foreach ($grp in @('telemetry', 'advertising', 'cortana', 'privacy')) {
                if (-not $Baseline.registry.$grp) { continue }
                Compare-RegistryBaselineWithFallback -Entries @($Baseline.registry.$grp) | ForEach-Object {
                    $_.ConfigType = 'telemetry'
                    $items.Add($_)
                }
            }
        }

        if ($Baseline.scheduledTasks.disable) {
            foreach ($taskPath in $Baseline.scheduledTasks.disable) {
                try {
                    $taskName = Split-Path $taskPath -Leaf
                    $taskFolder = Split-Path $taskPath -Parent
                    $task = Get-ScheduledTask -TaskName $taskName -TaskPath "$taskFolder\" -ErrorAction SilentlyContinue
                    if ($task -and $task.State -ne 'Disabled') {
                        $items.Add(@{ ConfigType = 'telemetry'; Type = 'scheduledtask'; Name = $taskPath; TaskPath = "$taskFolder\"; TaskName = $taskName; CurrentState = $task.State.ToString(); DesiredState = 'Disabled' })
                    }
                }
                catch { Write-Log -Level WARN -Component CONFIG-AUDIT -Message "Task query failed '$taskPath': $_" }
            }
        }
    }
    # NO comma-wrap. `return , $arr` emits the array as ONE pipeline element, so a caller
    # writing @(Get-...) gets a 1-element array CONTAINING the array instead of the items -
    # and the callers below do exactly that. Returning it plainly lets the pipeline unroll,
    # and the caller's @() then normalises 0/1/N uniformly. (Get-DiffList uses the comma
    # because ITS callers use plain assignment, not @(). The two idioms must not be mixed.)
    return $items.ToArray()
}

<#
.SYNOPSIS
    Phase A4 of the configuration audit: optimization baseline -> diff items.
.DESCRIPTION
    Extracted verbatim from Invoke-SystemConfigurationAudit. Covers services, power plan,
    startup entries, visual effects and desktop background. Merges the common block with the
    OS-specific (windows10 / windows11) block via OSContext.
.OUTPUTS
    [hashtable[]] diff items, every one tagged ConfigType = 'optimization'.
#>
function Get-OptimizationConfigurationDiff {
    [CmdletBinding()]
    [OutputType([hashtable[]])]
    param(
        [Parameter(Mandatory)] [AllowNull()] $Baseline,
        [Parameter(Mandatory)] [hashtable]$OSContext
    )
    $items = [System.Collections.Generic.List[hashtable]]::new()
    if ($Baseline -and $Baseline.common) {
        Write-Log -Level DEBUG -Component CONFIG-AUDIT -Message 'Auditing optimization settings...'

        # Services to disable
        $svcsToDisable = [System.Collections.Generic.List[string]]::new()
        if ($Baseline.common.services.safeToDisable) { $Baseline.common.services.safeToDisable | ForEach-Object { $svcsToDisable.Add($_) } }
        if ($OSContext.IsWindows11 -and $Baseline.windows11.services.safeToDisable) {
            $Baseline.windows11.services.safeToDisable | ForEach-Object { $svcsToDisable.Add($_) }
        }
        elseif (-not $OSContext.IsWindows11 -and $Baseline.windows10.services.safeToDisable) {
            $Baseline.windows10.services.safeToDisable | ForEach-Object { $svcsToDisable.Add($_) }
        }
        Compare-ServiceBaseline -ServiceNames @($svcsToDisable) -Action 'EnsureDisabled' | ForEach-Object {
            $_.ConfigType = 'optimization'
            $items.Add($_)
        }

        # Power plan
        if ($Baseline.common.powerPlan.defaultPlan) {
            $desiredPlan = $Baseline.common.powerPlan.defaultPlan
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
                    $items.Add(@{ ConfigType = 'optimization'; Type = 'powerplan'; Name = 'ActivePlan'; GUID = $planGuid ?? '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'; CurrentState = "$currentPlan"; DesiredState = $desiredPlan })
                }
            }
            catch { Write-Log -Level WARN -Component CONFIG-AUDIT -Message "Power plan query failed: $_" }
        }

        # Startup programs
        if ($Baseline.common.startupPrograms) {
            $safePatterns = $Baseline.common.startupPrograms.safeToDisablePatterns ?? @()
            $neverDisable = $Baseline.common.startupPrograms.neverDisable ?? @()
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
                        $items.Add(@{ ConfigType = 'optimization'; Type = 'startup'; Name = $entryName; RegistryPath = $runPath; CurrentState = 'Enabled'; DesiredState = 'Disabled' })
                    }
                }
                catch { Write-Log -Level WARN -Component CONFIG-AUDIT -Message "Failed to read $runPath : $_" }
            }
        }

        # Visual effects.
        #
        # The baseline's visualEffects block used to be DECORATIVE: the audit hardcoded
        # DesiredState = 3 and the Type2 arm hardcoded all six registry writes. Every value
        # happened to match the JSON, so the behaviour was correct - but editing the JSON
        # changed nothing, which is the more dangerous kind of wrong. The declared values are
        # now threaded through the diff item and read by the apply arm.
        #
        # 'preset' maps to Windows' VisualFXSetting: 0 = let Windows choose, 1 = best
        # appearance, 2 = best performance, 3 = custom. 'balanced' is this project's own word
        # for "custom mix of the five toggles below", hence 3.
        if ($Baseline.common.visualEffects) {
            $vfx = $Baseline.common.visualEffects
            $desiredFx = switch ("$($vfx.preset)".ToLowerInvariant()) {
                'auto' { 0 }
                'appearance' { 1 }
                'performance' { 2 }
                'balanced' { 3 }
                default { 3 }
            }
            $visualPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects'
            $currentVisual = Get-RegistryValue -Path $visualPath -Name 'VisualFXSetting'
            if ($null -eq $currentVisual -or $currentVisual -ne $desiredFx) {
                $items.Add(@{
                        ConfigType   = 'optimization'
                        Type         = 'visualfx'
                        Name         = 'VisualFXSetting'
                        CurrentState = $currentVisual
                        DesiredState = $desiredFx
                        # Individual toggles, read by the Type2 arm instead of being hardcoded
                        # there. Defaults preserve the previous behaviour when a key is absent.
                        DisableAnimations        = [bool]($vfx.disableAnimations ?? $true)
                        DisableShadows           = [bool]($vfx.disableShadows ?? $true)
                        EnableSmoothEdges        = [bool]($vfx.enableSmoothEdges ?? $true)
                        ShowWindowContents       = [bool]($vfx.enableShowWindowContents ?? $true)
                        DisableTransparency      = [bool]($vfx.disableTransparency ?? $true)
                    })
            }
        }

        # Desktop background (Spotlight -> Picture)
        if ($Baseline.common.background.type -eq 'Picture') {
            $cdmPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
            $spotlightEnabled = Get-RegistryValue -Path $cdmPath -Name 'RotatingLockScreenEnabled'
            $cdmSubscriptions = Get-RegistryValue -Path $cdmPath -Name 'SubscribedContent-338387Enabled'
            if ($spotlightEnabled -eq 1 -or $cdmSubscriptions -eq 1) {
                $items.Add(@{ ConfigType = 'optimization'; Type = 'background'; Name = 'DesktopBackground'; CurrentState = 'Spotlight'; DesiredState = 'Picture' })
            }
        }
    }
    # Plain return, no comma-wrap - the caller uses @(). See Get-SecurityConfigurationDiff.
    return $items.ToArray()
}

<#
.SYNOPSIS
    Phase A1 of the configuration audit: restore point create + prune -> diff items.
.DESCRIPTION
    Extracted verbatim from Invoke-SystemConfigurationAudit.

    The 'create' item is queued UNCONDITIONALLY (unless skipped by config). It is the rollback
    safety net for every other change in the run, AND it is what guarantees this pair's diff is
    never empty - so Stage 2 always schedules the Type2 module. Get-ConfigItemRank then sorts
    create to rank 0 and prune to rank 4, so creation precedes every mutation and the
    destructive prune happens only after everything else succeeded.

    Unlike the other phase helpers this returns a RESULT OBJECT, not a bare item array: the
    caller also needs the enumerated restore points and the prune count for the report JSON
    and ExtraData. A hashtable return also sidesteps pipeline unrolling entirely.
.OUTPUTS
    [hashtable] @{ Items = [hashtable[]]; RestorePoints = [object[]]; ToRemove = [int] }
#>
function Get-RestorePointConfigurationDiff {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter()] [bool]$SkipRestorePoint,
        [Parameter()] [int]$MinimumToKeep = 5,
        [Parameter()] [int]$AllocationGB = 10
    )
    $items = [System.Collections.Generic.List[hashtable]]::new()
    $restorePoints = @()
    $toRemove = 0

    # Queued FIRST so the create item is the first thing Type2 sees. The 'create'
    # item is queued UNCONDITIONALLY (unless skipped by config): it is the rollback
    # safety net for every other change in this run, and it also guarantees this
    # pair's diff is never empty, so Stage 2 always schedules Type2.
    if ($SkipRestorePoint) {
        Write-Log -Level INFO -Component CONFIG-AUDIT -Message 'Restore point management skipped (config: skipRestorePointManagement)'
    }
    else {
        try {
            $restorePoints = Get-SystemRestorePointList
            Write-Log -Level INFO -Component CONFIG-AUDIT -Message "Current restore points: $($restorePoints.Count)"

            # Create a fresh one every run.
            $items.Add(@{
                    ConfigType   = 'restorepoint'
                    Type         = 'restorepoint'
                    Action       = 'create'
                    Name         = 'CreateRestorePoint'
                    Description  = "Maintenance: $([datetime]::Now.ToString('yyyy-MM-dd HH:mm'))"
                    AllocationGB = $AllocationGB
                })

            # Prune anything beyond the newest $MinimumToKeep.
            if ($restorePoints.Count -gt $MinimumToKeep) {
                foreach ($point in $restorePoints[$MinimumToKeep..($restorePoints.Count - 1)]) {
                    $items.Add(@{
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
                    $toRemove++
                    Write-Log -Level DEBUG -Component CONFIG-AUDIT -Message "Marked for removal: $($point.Description) (seq: $($point.SequenceNumber), created: $($point.CreationTimeText))"
                }
            }
            Write-Log -Level INFO -Component CONFIG-AUDIT -Message "Restore points: $($restorePoints.Count) current, $toRemove to prune, 1 to create"
        }
        catch {
            # A failed restore point QUERY must not cost us the create action - that is
            # the safety net. Queue the create anyway and carry on with the rest.
            Write-Log -Level WARN -Component CONFIG-AUDIT -Message "Could not enumerate restore points: $_ - queuing create only"
            $items.Add(@{
                    ConfigType   = 'restorepoint'
                    Type         = 'restorepoint'
                    Action       = 'create'
                    Name         = 'CreateRestorePoint'
                    Description  = "Maintenance: $([datetime]::Now.ToString('yyyy-MM-dd HH:mm'))"
                    AllocationGB = $AllocationGB
                })
        }
    }

    return @{
        Items         = $items.ToArray()
        RestorePoints = $restorePoints
        ToRemove      = $toRemove
    }
}

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
        # ═══ A1. RESTORE POINTS ══════════════════════════════════════════════
        $rpAudit = Get-RestorePointConfigurationDiff -SkipRestorePoint $skipRestorePoint `
            -MinimumToKeep $minToKeep -AllocationGB $allocationGB
        foreach ($item in @($rpAudit.Items)) { $diff.Add($item) }
        $restorePoints = @($rpAudit.RestorePoints)
        $rpToRemove = $rpAudit.ToRemove

        # ═══ A2. SECURITY ════════════════════════════════════════════════════
        $securityBaseline = Get-BaselineList -ModuleFolder 'security' -FileName 'security-baseline.json'
        foreach ($item in @(Get-SecurityConfigurationDiff -Baseline $securityBaseline `
                    -SkipPasswordPolicy $skipPasswordPolicy -SkipAuditPolicy $skipAuditPolicy)) { $diff.Add($item) }

        # ═══ A3. TELEMETRY / PRIVACY ═════════════════════════════════════════
        $telemetryBaseline = Get-BaselineList -ModuleFolder 'telemetry' -FileName 'telemetry-list.json'
        foreach ($item in @(Get-TelemetryConfigurationDiff -Baseline $telemetryBaseline)) { $diff.Add($item) }

        # ═══ A4. OPTIMIZATION ════════════════════════════════════════════════
        $optBaseline = Get-BaselineList -ModuleFolder 'system-optimization' -FileName 'system-optimization-config.json'
        foreach ($item in @(Get-OptimizationConfigurationDiff -Baseline $optBaseline -OSContext $osCtx)) { $diff.Add($item) }

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
