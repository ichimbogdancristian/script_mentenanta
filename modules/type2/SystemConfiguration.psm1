#Requires -Version 7.0
<#
.SYNOPSIS    System Configuration - Type 2 (Restore point + Security + Telemetry + Optimization)
.DESCRIPTION Applies all system-state changes identified by SystemConfigurationAudit.
             Dispatches each diff item on its ConfigType then Type:
               restorepoint -> create | remove   (Action discriminator)
               security     -> registry | defender | firewall | sysmon
               telemetry    -> service | registry | scheduledtask
               optimization -> service | powerplan | startup | visualfx | background

             Items are NOT applied in diff order. Get-ConfigItemRank sorts them into the
             order the changes actually have to happen in - restore point creation first
             (it is the rollback safety net for everything after it), restore point pruning
             last (it is destructive and irreversible). See that function for the full
             rationale.

             Sysmon is installed via winget (Microsoft.Sysinternals.Sysmon) and configured
             with config/sysmon/sysmonconfig.xml.
.NOTES       Module Type: Type2 | DiffKey: SystemConfiguration | Version: 7.0 (Consolidated)
#>

$_corePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'core\Maintenance.psm1'
if (-not (Get-Command 'Write-Log' -ErrorAction SilentlyContinue)) {
    Import-Module $_corePath -Force -Global -WarningAction SilentlyContinue
}

<#
.SYNOPSIS
    Backs up the current registry value before applying a change. Used for rollback.
.OUTPUTS
    [hashtable] with backup data: Path, Name, Exists, Value, Backed, Timestamp.
#>
function Backup-RegistryValue {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [string]$Name
    )

    $current = Get-RegistryValue -Path $Path -Name $Name
    $exists = Test-Path -Path "$Path" -ErrorAction SilentlyContinue

    return @{
        Path = $Path
        Name = $Name
        Exists = $exists
        Value = $current
        Backed = $true
        Timestamp = Get-Date -Format 'o'
    }
}

<#
.SYNOPSIS
    Verifies that a registry value was successfully applied to the system.
.OUTPUTS
    [bool] $true if the value matches the expected value.
#>
function Test-RegistryValueApplied {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [string]$Name,
        [Parameter(Mandatory)] [object]$ExpectedValue
    )

    try {
        $actual = Get-RegistryValue -Path $Path -Name $Name
        return $actual -eq $ExpectedValue
    }
    catch {
        Write-Log -Level DEBUG -Component CONFIG -Message "Registry verification failed for $Path\$Name : $_"
        return $false
    }
}

<#
.SYNOPSIS
    Rolls back a registry value to its pre-change state using a backup hashtable.
.OUTPUTS
    [bool] $true if rollback succeeded.
#>
function Restore-RegistryValue {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)] [hashtable]$Backup
    )

    try {
        $path = $Backup.Path
        $name = $Backup.Name
        $value = $Backup.Value
        $existed = $Backup.Exists

        if (-not $existed -and (Test-Path $path)) {
            Remove-ItemProperty -Path $path -Name $name -Force -ErrorAction Stop
            Write-Log -Level INFO -Component CONFIG -Message "Rollback: Removed $path\$name (did not exist before)"
        }
        elseif ($existed -and $null -ne $value) {
            Set-ItemProperty -Path $path -Name $name -Value $value -Force -ErrorAction Stop
            Write-Log -Level INFO -Component CONFIG -Message "Rollback: Restored $path\$name to previous value"
        }
        return $true
    }
    catch {
        Write-Log -Level ERROR -Component CONFIG -Message "Rollback FAILED for $($Backup.Path)\$($Backup.Name): $_"
        return $false
    }
}

<#
.SYNOPSIS
    Installs Sysinternals Sysmon via winget and applies the bundled sysmonconfig.xml.
.DESCRIPTION
    Idempotent: if the Sysmon service already exists the config is re-applied (-c) rather
    than reinstalled (-i). Resolves the Sysmon binary from PATH or the winget install
    location. Config file: config/sysmon/sysmonconfig.xml under the project root.
.OUTPUTS
    [bool] $true on success.
#>
function Install-SysmonWithConfig {
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    $configPath = Join-Path $env:MAINT_CONFIG 'sysmon\sysmonconfig.xml'
    if (-not (Test-Path $configPath)) {
        Write-Log -Level WARN -Component CONFIG -Message "Sysmon config not found: $configPath - skipping Sysmon"
        return $false
    }

    # Install the package if the service is not already present
    $sysmonSvc = Get-Service -Name 'Sysmon', 'Sysmon64' -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $sysmonSvc) {
        if (-not (Test-CommandAvailable 'winget')) {
            Write-Log -Level WARN -Component CONFIG -Message 'winget unavailable - cannot install Sysmon'
            return $false
        }
        Write-Log -Level INFO -Component CONFIG -Message 'Installing Sysmon via winget (Microsoft.Sysinternals.Sysmon)'
        $exit = Invoke-ExternalPackageCommand -FilePath (Resolve-WingetPath) -ArgumentList @(
            'install', '--id', 'Microsoft.Sysinternals.Sysmon', '--source', 'winget', '--silent',
            '--disable-interactivity', '--accept-package-agreements', '--accept-source-agreements', '--scope', 'machine')
        if ($exit -notin 0, -1978335135, -1978335189) {
            Write-Log -Level WARN -Component CONFIG -Message "winget Sysmon install returned exit $exit"
        }
    }

    # Resolve the REAL Sysmon binary (prefer the 64-bit build). We MUST avoid the winget
    # "Links" shim (…\WinGet\Links\sysmon.exe): it is a 32-bit App-Execution-Alias reparse
    # point, and launching it with redirected stdio fail-fast crashes with 0xC0000409
    # (-1073740791) - exactly the failure seen before. Get-Command is skipped for the same
    # reason (the Links dir is on PATH, so it resolves to the crashing shim).
    $sysmonExe = $null
    # 1) If Sysmon is already installed as a service, its binary lives directly in %windir%.
    foreach ($name in 'Sysmon64.exe', 'Sysmon.exe') {
        $p = Join-Path $env:windir $name
        if (Test-Path $p) { $sysmonExe = $p; break }
    }
    # 2) Otherwise use the real winget package binary (NOT the Links shim). winget portable
    #    packages extract the actual executables under WinGet\Packages\...; prefer Sysmon64.exe.
    if (-not $sysmonExe) {
        $pkgRoots = @(
            (Join-Path $env:ProgramFiles 'WinGet\Packages'),
            (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages')
        ) | Where-Object { $_ -and (Test-Path $_) }
        foreach ($name in 'Sysmon64.exe', 'Sysmon.exe') {
            foreach ($root in $pkgRoots) {
                $found = Get-ChildItem -Path $root -Filter $name -Recurse -ErrorAction SilentlyContinue |
                    Where-Object { $_.FullName -notmatch '\\Links\\' } | Select-Object -First 1
                if ($found) { $sysmonExe = $found.FullName; break }
            }
            if ($sysmonExe) { break }
        }
    }
    if (-not $sysmonExe) {
        Write-Log -Level WARN -Component CONFIG -Message 'Sysmon executable not found after install (real binary, not the Links shim)'
        return $false
    }
    Write-Log -Level INFO -Component CONFIG -Message "Using Sysmon binary: $sysmonExe"

    # Apply config: -i installs+configures a fresh Sysmon; -c updates config on an existing
    # install. -accepteula on both is harmless if already accepted and stops a first-run EULA
    # prompt blocking an unattended run. The config path is quoted in case it contains spaces
    # (Invoke-ExternalPackageCommand joins args with a bare space and does not quote them).
    $sysmonSvc = Get-Service -Name 'Sysmon', 'Sysmon64' -ErrorAction SilentlyContinue | Select-Object -First 1
    $quotedConfig = '"' + $configPath + '"'
    $applyArgs = if ($sysmonSvc) { @('-accepteula', '-c', $quotedConfig) } else { @('-accepteula', '-i', $quotedConfig) }
    $exit = Invoke-ExternalPackageCommand -FilePath $sysmonExe -ArgumentList $applyArgs
    if ($exit -eq 0) {
        Write-Log -Level SUCCESS -Component CONFIG -Message "Sysmon configured with $configPath"
        return $true
    }
    Write-Log -Level WARN -Component CONFIG -Message "Sysmon config apply returned exit $exit"
    return $false
}

<#
.SYNOPSIS
    Creates a system restore point (PowerShell 7 compatible).
.DESCRIPTION
    Deliberately does NOT use Checkpoint-Computer / Enable-ComputerRestore: those
    *-Computer restore cmdlets ship only with Windows PowerShell 5.1 and do not exist in
    PowerShell 7, which is the only shell this project runs modules under. Everything here
    goes through the root/default:SystemRestore WMI class via Invoke-CimMethod instead.

    Windows also rate-limits restore point creation to one per 24h by default, which would
    silently turn "create a restore point every run" into "create one the first run this
    day". SystemRestorePointCreationFrequency=0 lifts that limit so the safety net is
    actually taken on every run.
.OUTPUTS
    [bool] $true when a restore point was created.
#>
function New-SystemRestorePoint {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)] [string]$Description,
        [Parameter()] [int]$MinShadowStorageGB = 10
    )

    # Make sure protection is on for the system drive; a disabled System Restore makes
    # CreateRestorePoint fail with an unhelpful generic error.
    $sysDrive = "$($env:SystemDrive)\"
    try {
        $null = Invoke-CimMethod -Namespace 'root/default' -ClassName 'SystemRestore' `
            -MethodName 'Enable' -Arguments @{ Drive = $sysDrive } -ErrorAction Stop
        Write-Log -Level DEBUG -Component CONFIG -Message "System Restore enabled for $sysDrive"
    }
    catch {
        Write-Log -Level DEBUG -Component CONFIG -Message "Could not enable System Restore for $sysDrive (may already be on): $_"
    }

    # Lift the once-per-24h throttle (see function help).
    try {
        $null = Set-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore' `
            -Name 'SystemRestorePointCreationFrequency' -Value 0 -Type DWord
    }
    catch {
        Write-Log -Level DEBUG -Component CONFIG -Message "Could not clear restore point creation frequency limit: $_"
    }

    # Make sure shadow storage is actually allocated. Enabling System Restore does not by
    # itself guarantee usable space: on a machine where shadow storage is unconfigured or
    # sized at 0, CreateRestorePoint can report success while the point is immediately
    # discarded, leaving the run with no real rollback target.
    #
    # This moved here from script.bat, which used to size shadow storage as part of a
    # ~127-line restore-point block that otherwise duplicated this function (and did so via
    # Checkpoint-Computer WITHOUT clearing the 24h throttle above, so it was silently a no-op
    # whenever a restore point already existed from the last day). Only the sizing was worth
    # keeping, and it belongs next to the code that depends on it.
    #
    # vssadmin is used rather than WMI because Win32_ShadowStorage's MaxSpace is read-only in
    # practice; 'vssadmin resize shadowstorage' is the supported way to change it.
    try {
        $listed = & vssadmin list shadowstorage 2>&1 | Out-String
        $needsResize = $true
        if ($listed -match 'UNBOUNDED') {
            $needsResize = $false
            Write-Log -Level DEBUG -Component CONFIG -Message 'Shadow storage is unbounded - no resize needed'
        }
        elseif ($listed -match 'Maximum Shadow Copy Storage space[^\r\n]*?([0-9.,]+)\s*(GB|MB|TB)') {
            $size = [decimal]($Matches[1] -replace ',', '')
            $currentGB = switch ($Matches[2]) {
                'TB' { $size * 1024 }
                'GB' { $size }
                'MB' { $size / 1024 }
                default { 0 }
            }
            if ($currentGB -ge $MinShadowStorageGB) {
                $needsResize = $false
                Write-Log -Level DEBUG -Component CONFIG -Message "Shadow storage allocation is $([math]::Round($currentGB,2)) GB (>= $MinShadowStorageGB GB)"
            }
            else {
                Write-Log -Level INFO -Component CONFIG -Message "Shadow storage is $([math]::Round($currentGB,2)) GB - raising to $MinShadowStorageGB GB"
            }
        }

        if ($needsResize) {
            $resized = & vssadmin resize shadowstorage /For=$sysDrive /On=$sysDrive /MaxSize=${MinShadowStorageGB}GB 2>&1 | Out-String
            if ($resized -match 'successfully') {
                Write-Log -Level SUCCESS -Component CONFIG -Message "Shadow storage allocation set to $MinShadowStorageGB GB"
            }
            else {
                Write-Log -Level WARN -Component CONFIG -Message 'Could not resize shadow storage - restore point may not persist'
            }
        }
    }
    catch {
        Write-Log -Level WARN -Component CONFIG -Message "Shadow storage check failed (continuing): $_"
    }

    try {
        # RestorePointType 12 = MODIFY_SETTINGS, EventType 100 = BEGIN_SYSTEM_CHANGE.
        $res = Invoke-CimMethod -Namespace 'root/default' -ClassName 'SystemRestore' `
            -MethodName 'CreateRestorePoint' `
            -Arguments @{ Description = $Description; RestorePointType = [uint32]12; EventType = [uint32]100 } `
            -ErrorAction Stop

        if ($res.ReturnValue -eq 0) {
            Write-Log -Level SUCCESS -Component CONFIG -Message "Restore point created: $Description"
            return $true
        }
        Write-Log -Level WARN -Component CONFIG -Message "CreateRestorePoint returned $($res.ReturnValue) - no restore point created"
        return $false
    }
    catch {
        Write-Log -Level ERROR -Component CONFIG -Message "Failed to create restore point: $_"
        return $false
    }
}

<#
.SYNOPSIS
    Deletes one shadow copy / restore point by its Win32_ShadowCopy ID.
.DESCRIPTION
    PowerShell 7 compatible. Remove-CimInstance replaces the PS5.1-only
    Get-WmiObject | Remove-WmiObject pairing; vssadmin is the fallback for the cases
    where the CIM delete is refused.
.OUTPUTS
    [bool] $true when the shadow copy is gone.
#>
function Remove-SystemRestorePoint {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)] [string]$ShadowId
    )

    try {
        $shadow = Get-CimInstance -ClassName Win32_ShadowCopy -ErrorAction Stop |
        Where-Object { $_.ID -eq $ShadowId } | Select-Object -First 1
        if (-not $shadow) {
            Write-Log -Level DEBUG -Component CONFIG -Message "Shadow copy $ShadowId already gone"
            return $true
        }
        Remove-CimInstance -InputObject $shadow -ErrorAction Stop
        Write-Log -Level SUCCESS -Component CONFIG -Message "Removed restore point $ShadowId"
        return $true
    }
    catch {
        Write-Log -Level DEBUG -Component CONFIG -Message "CIM delete failed for $ShadowId ($_) - trying vssadmin"
    }

    try {
        $vssadmin = Join-Path $env:SystemRoot 'System32\vssadmin.exe'
        $exit = Invoke-ExternalPackageCommand -FilePath $vssadmin `
            -ArgumentList @('delete', 'shadows', "/Shadow=$ShadowId", '/Quiet')
        if ($exit -eq 0) {
            Write-Log -Level SUCCESS -Component CONFIG -Message "Removed restore point $ShadowId (vssadmin)"
            return $true
        }
        Write-Log -Level WARN -Component CONFIG -Message "vssadmin delete returned exit $exit for $ShadowId"
        return $false
    }
    catch {
        Write-Log -Level WARN -Component CONFIG -Message "Could not remove restore point ${ShadowId}: $_"
        return $false
    }
}

<#
.SYNOPSIS
    Execution rank for a diff item - defines the order Type2 applies changes in.
.DESCRIPTION
    The diff arrives in audit order, which is NOT the order these changes should be
    applied in. Ranking:

      0  restore point CREATE  - the rollback safety net. Must be taken before ANY other
                                 change in this run, otherwise it is a snapshot of an
                                 already-modified system and useless for rollback.
      1  security             - Defender/firewall/hardening. Runs early so protection is
                                 back on (and Sysmon is logging) while the rest of the run
                                 and the later Type2 modules mutate the machine.
      2  telemetry            - privacy services/registry/tasks. Pure policy, no dependants.
      3  optimization         - services, power plan, startup, visual fx. Last of the
                                 mutations: disabling services here must not race the
                                 security phase re-enabling one of them.
      4  restore point REMOVE - pruning old restore points is destructive and irreversible,
                                 so it happens only after every change above has succeeded.
                                 Pruning first would throw away the very rollback targets
                                 we would need if this run went wrong.
.OUTPUTS
    [int] sort rank.
#>
function Get-ConfigItemRank {
    [CmdletBinding()]
    [OutputType([int])]
    param([Parameter(Mandatory)] $Item)

    switch ($Item.ConfigType) {
        'restorepoint' { if ($Item.Action -eq 'create') { return 0 } else { return 4 } }
        'security' { return 1 }
        'telemetry' { return 2 }
        'optimization' { return 3 }
        default { return 3 }
    }
}

<#
.SYNOPSIS
    Applies ONE configuration diff item and reports what it did.
.DESCRIPTION
    Extracted from Invoke-SystemConfiguration. The dispatch switch used to sit inline in the
    apply loop and mutate six enclosing variables ($changed, $errors, $failed, $rpCreated,
    $rpRemoved, $rebootNeeded). It now returns those as a result object the loop merges, so the
    dispatch is independently testable and the loop is a loop again.

    ORDERING IS NOT DECIDED HERE. The caller sorts the diff through Get-ConfigItemRank first;
    see that function for why restore point create must precede every mutation and prune must
    follow all of them.

    Never throws: every failure is captured into Errors/Failed, because a module failing must
    not fail the run.
.OUTPUTS
    [hashtable] @{ Changed = [bool]; Errors = [string[]]; Failed = [int]
                   RpCreated = [int]; RpRemoved = [int]; RebootRequired = [bool] }
#>
function Invoke-ConfigurationItem {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)] $Item
    )

    $item = $Item
    $result = @{
        Changed        = $false
        Errors         = @()
        Failed         = 0
        RpCreated      = 0
        RpRemoved      = 0
        RebootRequired = $false
    }

    $name = $item.Name ?? "$item"
    $configType = $item.ConfigType ?? 'unknown'
    $type = $item.Type ?? 'registry'

    try {
        $result.Changed = $false
        $backup = $null

        switch ($configType) {
            # ─── RESTORE POINT ───────────────────────────────────────────
            # 'create' is ranked first and 'remove' last (Get-ConfigItemRank), so by the
            # time a delete runs every other change in this run has already been applied.
            'restorepoint' {
                switch ($item.Action) {
                    'create' {
                        $desc = $item.Description ?? "Maintenance: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
                        $result.Changed = New-SystemRestorePoint -Description $desc
                        if ($result.Changed) { $result.RpCreated++ }
                        else {
                            # The safety net failing is worth surfacing, but it must not
                            # stop the maintenance run the user asked for.
                            $result.Errors += "[RestorePoint] Could not create restore point '$desc'"
                            $result.Failed++
                        }
                    }
                    'remove' {
                        $shadowId = $item.ShadowId
                        if (-not $shadowId) {
                            Write-Log -Level WARN -Component CONFIG -Message "Restore point item has no ShadowId: $name"
                            $result.Errors += "[No ShadowId] $name"; $result.Failed++
                        }
                        else {
                            $result.Changed = Remove-SystemRestorePoint -ShadowId $shadowId
                            if ($result.Changed) { $result.RpRemoved++ }
                            else { $result.Errors += "[RestorePoint] Could not remove $shadowId"; $result.Failed++ }
                        }
                    }
                    default {
                        Write-Log -Level WARN -Component CONFIG -Message "Unknown restore point action '$($item.Action)': $name"
                        $result.Errors += "[Unknown action] $name"; $result.Failed++
                    }
                }
            }

            # ─── SECURITY ────────────────────────────────────────────────
            'security' {
                switch ($type) {
                    'registry' {
                        $vname = $item.ValueName ?? $item.Name
                        if ($vname) {
                            $backup = $null
                            try {
                                $backup = Backup-RegistryValue -Path $item.Path -Name $vname
                            }
                            catch {
                                Write-Log -Level WARN -Component CONFIG -Message "Registry backup failed: $_"
                            }
                            $result.Changed = Invoke-RegistryChangeItem -Item $item -Component 'CONFIG'
                            if ($result.Changed) {
                                $verified = Test-RegistryValueApplied -Path $item.Path -Name $vname -ExpectedValue $item.DesiredValue
                                if (-not $verified) {
                                    Write-Log -Level WARN -Component CONFIG -Message "Registry verification FAILED: $($item.Path)\$vname"
                                    if ($backup) {
                                        $restored = Restore-RegistryValue -Backup $backup
                                        if ($restored) {
                                            Write-Log -Level SUCCESS -Component CONFIG -Message "Rollback successful"
                                        }
                                        else {
                                            Write-Log -Level ERROR -Component CONFIG -Message "Rollback FAILED - manual intervention required"
                                        }
                                    }
                                    else {
                                        Write-Log -Level ERROR -Component CONFIG -Message "No backup available - manual remediation required"
                                    }
                                    $result.Errors += "[Verification Failed] $name"; $result.Failed++; $result.Changed = $false
                                }
                            }
                        }
                    }
                    'service' { $result.Changed = Invoke-ServiceChangeItem -Item $item -Component 'CONFIG' }
                    'defender' {
                        $feature = $item.Feature ?? $item.Name
                        $enable = $item.ShouldEnable ?? $true
                        $result.Changed = $true
                        switch ($feature) {
                            'RealTimeProtection' { Set-MpPreference -DisableRealtimeMonitoring (-not $enable) -ErrorAction Stop }
                            'CloudProtection' { Set-MpPreference -MAPSReporting $(if ($enable) { 2 } else { 0 }) -ErrorAction Stop }
                            'NetworkProtection' { Set-MpPreference -EnableNetworkProtection $(if ($enable) { 1 } else { 0 }) -ErrorAction Stop }
                            'PUAProtection' { Set-MpPreference -PUAProtection $(if ($enable) { 1 } else { 0 }) -ErrorAction Stop }
                            'ControlledFolderAccess' { Set-MpPreference -EnableControlledFolderAccess $(if ($enable) { 1 } else { 0 }) -ErrorAction Stop }
                            'AutomaticSampleSubmission' { Set-MpPreference -SubmitSamplesConsent $(if ($enable) { 1 } else { 0 }) -ErrorAction Stop }
                            'AntivirusEnabled' {
                                $null = Set-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender' -Name 'DisableAntiSpyware' -Value 0 -Type DWord
                                Set-Service -Name WinDefend -StartupType Automatic -ErrorAction Stop
                                Start-Service -Name WinDefend -ErrorAction Stop
                                $result.RebootRequired = $true
                            }
                            default { Write-Log -Level WARN -Component CONFIG -Message "Unknown Defender feature: $feature"; $result.Changed = $false }
                        }
                        if ($result.Changed) { Write-Log -Level SUCCESS -Component CONFIG -Message "Defender.$feature -> $enable" }
                    }
                    'firewall' {
                        $fwProfile = $item.Profile
                        if (-not $fwProfile) {
                            Write-Log -Level WARN -Component CONFIG -Message "Firewall missing Profile: $name"
                            $result.Errors += "[No Profile] $name"; $result.Failed++; return $result
                        }
                        $enabled = if ($item.DesiredState -eq $false) { 'False' } else { 'True' }
                        Set-NetFirewallProfile -Profile $fwProfile.Split(',') -Enabled $enabled -ErrorAction Stop
                        Write-Log -Level SUCCESS -Component CONFIG -Message "Firewall.$fwProfile -> Enabled=$enabled"
                        $result.Changed = $true
                    }
                    'sysmon' { $result.Changed = Install-SysmonWithConfig }
                    # CIS 1.1/1.2 - local password & account-lockout policy via secedit.
                    'secpolicy' {
                        $result.Changed = Invoke-SecurityPolicyChangeItem -Item $item -Component 'CONFIG'
                        if (-not $result.Changed) { $result.Errors += "[SecPolicy] $name"; $result.Failed++ }
                    }
                    # CIS 17.x - advanced audit policy subcategories via auditpol.
                    'auditpolicy' {
                        $result.Changed = Invoke-AuditPolicyChangeItem -Item $item -Component 'CONFIG'
                        if (-not $result.Changed) { $result.Errors += "[AuditPolicy] $name"; $result.Failed++ }
                    }
                    default {
                        Write-Log -Level WARN -Component CONFIG -Message "Unknown security type '$type': $name"
                        $result.Errors += "[Unknown type] $name"; $result.Failed++
                    }
                }
            }

            # ─── TELEMETRY ───────────────────────────────────────────────
            'telemetry' {
                switch ($type) {
                    'service' { $result.Changed = Invoke-ServiceChangeItem -Item $item -Component 'CONFIG' }
                    'registry' {
                        $vname = $item.ValueName ?? $item.Name
                        if ($vname) {
                            $backup = $null
                            try {
                                $backup = Backup-RegistryValue -Path $item.Path -Name $vname
                            }
                            catch {
                                Write-Log -Level WARN -Component CONFIG -Message "Registry backup failed: $_"
                            }
                            $result.Changed = Invoke-RegistryChangeItem -Item $item -Component 'CONFIG'
                            if ($result.Changed) {
                                $verified = Test-RegistryValueApplied -Path $item.Path -Name $vname -ExpectedValue $item.DesiredValue
                                if (-not $verified) {
                                    Write-Log -Level WARN -Component CONFIG -Message "Registry verification FAILED: $($item.Path)\$vname"
                                    if ($backup) {
                                        $restored = Restore-RegistryValue -Backup $backup
                                        if ($restored) {
                                            Write-Log -Level SUCCESS -Component CONFIG -Message "Rollback successful"
                                        }
                                        else {
                                            Write-Log -Level ERROR -Component CONFIG -Message "Rollback FAILED - manual intervention required"
                                        }
                                    }
                                    else {
                                        Write-Log -Level ERROR -Component CONFIG -Message "No backup available - manual remediation required"
                                    }
                                    $result.Errors += "[Verification Failed] $name"; $result.Failed++; $result.Changed = $false
                                }
                            }
                        }
                    }
                    'scheduledtask' {
                        $taskPath = $item.TaskPath ?? '\Microsoft\Windows\'
                        $taskName = $item.TaskName ?? $item.Name
                        $null = Disable-ScheduledTask -TaskPath $taskPath -TaskName $taskName -ErrorAction Stop
                        Write-Log -Level SUCCESS -Component CONFIG -Message "Disabled task: $taskPath$taskName"
                        $result.Changed = $true
                    }
                    default {
                        Write-Log -Level WARN -Component CONFIG -Message "Unknown telemetry type '$type': $name"
                        $result.Errors += "[Unknown type] $name"; $result.Failed++
                    }
                }
            }

            # ─── OPTIMIZATION ────────────────────────────────────────────
            'optimization' {
                switch ($type) {
                    'service' { $result.Changed = Invoke-ServiceChangeItem -Item $item -Component 'CONFIG' }
                    'registry' {
                        $vname = $item.ValueName ?? $item.Name
                        if ($vname) {
                            $backup = $null
                            try {
                                $backup = Backup-RegistryValue -Path $item.Path -Name $vname
                            }
                            catch {
                                Write-Log -Level WARN -Component CONFIG -Message "Registry backup failed: $_"
                            }
                            $result.Changed = Invoke-RegistryChangeItem -Item $item -Component 'CONFIG'
                            if ($result.Changed) {
                                $verified = Test-RegistryValueApplied -Path $item.Path -Name $vname -ExpectedValue $item.DesiredValue
                                if (-not $verified) {
                                    Write-Log -Level WARN -Component CONFIG -Message "Registry verification FAILED: $($item.Path)\$vname"
                                    if ($backup) {
                                        $restored = Restore-RegistryValue -Backup $backup
                                        if ($restored) {
                                            Write-Log -Level SUCCESS -Component CONFIG -Message "Rollback successful"
                                        }
                                        else {
                                            Write-Log -Level ERROR -Component CONFIG -Message "Rollback FAILED - manual intervention required"
                                        }
                                    }
                                    else {
                                        Write-Log -Level ERROR -Component CONFIG -Message "No backup available - manual remediation required"
                                    }
                                    $result.Errors += "[Verification Failed] $name"; $result.Failed++; $result.Changed = $false
                                }
                            }
                        }
                    }
                    'powerplan' {
                        $planGuid = $item.GUID ?? '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
                        $powercfg = Join-Path $env:SystemRoot 'System32\powercfg.exe'
                        $null = & $powercfg /setactive $planGuid 2>&1
                        Write-Log -Level SUCCESS -Component CONFIG -Message "Power plan set to GUID $planGuid"
                        $result.Changed = $true
                    }
                    'visualfx' {
                        $null = Set-RegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' -Name 'VisualFXSetting' -Value 3 -Type DWord
                        $desktop = 'HKCU:\Control Panel\Desktop'
                        $null = Set-RegistryValue -Path $desktop -Name 'MinAnimate' -Value '0' -Type String
                        $null = Set-RegistryValue -Path $desktop -Name 'FontSmoothing' -Value '2' -Type String
                        $null = Set-RegistryValue -Path $desktop -Name 'DragFullWindows' -Value '1' -Type String
                        $adv = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
                        $null = Set-RegistryValue -Path $adv -Name 'TaskbarAnimations' -Value 0 -Type DWord
                        $null = Set-RegistryValue -Path $adv -Name 'ListviewShadow' -Value 0 -Type DWord
                        $null = Set-RegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name 'EnableTransparency' -Value 0 -Type DWord
                        Write-Log -Level SUCCESS -Component CONFIG -Message 'Visual effects set to balanced (custom)'
                        $result.Changed = $true
                    }
                    'background' {
                        $cdm = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
                        $null = Set-RegistryValue -Path $cdm -Name 'RotatingLockScreenEnabled' -Value 0 -Type DWord
                        $null = Set-RegistryValue -Path $cdm -Name 'RotatingLockScreenOverlayEnabled' -Value 0 -Type DWord
                        $null = Set-RegistryValue -Path $cdm -Name 'SubscribedContent-338387Enabled' -Value 0 -Type DWord
                        $wp = 'HKCU:\Control Panel\Desktop'
                        $null = Set-RegistryValue -Path $wp -Name 'WallpaperStyle' -Value '10' -Type String
                        $null = Set-RegistryValue -Path $wp -Name 'TileWallpaper' -Value '0' -Type String
                        Write-Log -Level SUCCESS -Component CONFIG -Message 'Desktop background changed from Spotlight to Picture'
                        $result.Changed = $true
                    }
                    'startup' {
                        $regPath = $item.RegistryPath
                        $entryName = $item.Name
                        if ($regPath -and $entryName) {
                            Remove-ItemProperty -Path $regPath -Name $entryName -Force -ErrorAction Stop
                            Write-Log -Level SUCCESS -Component CONFIG -Message "Startup program disabled: $entryName"
                            $result.Changed = $true
                        }
                    }
                    default {
                        Write-Log -Level WARN -Component CONFIG -Message "Unknown optimization type '$type': $name"
                        $result.Errors += "[Unknown type] $name"; $result.Failed++
                    }
                }
            }

            default {
                Write-Log -Level WARN -Component CONFIG -Message "Unknown ConfigType '$configType': $name"
                $result.Errors += "[Unknown ConfigType] $name"; $result.Failed++
            }
        }

    }
    catch {
        Write-Log -Level ERROR -Component CONFIG -Message "Failed [$configType/$type $name]: $_"
        $result.Errors += "[$name] $_"; $result.Failed++
    }

    return $result
}

function Invoke-SystemConfiguration {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter()][hashtable]$OSContext
    )

    $null = $OSContext  # Type2 interface parameter, may be used by future optimizations
    Write-Log -Level INFO -Component CONFIG -Message 'Starting system configuration (restore point + security + telemetry + optimization)'

    $diff = Get-DiffList -ModuleName 'SystemConfiguration'
    if (-not $diff -or $diff.Count -eq 0) {
        Write-Log -Level INFO -Component CONFIG -Message 'System already in desired configuration'
        return New-ModuleResult -ModuleName 'SystemConfiguration' -Status 'Skipped' -ModuleType 'Type2' -Message 'Already compliant'
    }

    $processed = 0; $failed = 0; $errors = @(); $rebootNeeded = $false
    $rpCreated = 0; $rpRemoved = 0

    $restorePointItems = @($diff | Where-Object { $_.ConfigType -eq 'restorepoint' })
    $securityItems = @($diff | Where-Object { $_.ConfigType -eq 'security' })
    $telemetryItems = @($diff | Where-Object { $_.ConfigType -eq 'telemetry' })
    $optimizationItems = @($diff | Where-Object { $_.ConfigType -eq 'optimization' })

    Write-Log -Level INFO -Component CONFIG -Message "Applying $($diff.Count) change(s): $($restorePointItems.Count) restore point, $($securityItems.Count) security, $($telemetryItems.Count) telemetry, $($optimizationItems.Count) optimization"

    # Apply in deliberate phase order rather than the order the audit happened to emit
    # items in - see Get-ConfigItemRank for why each phase sits where it does. -Stable keeps
    # the audit's within-phase ordering intact (Sort-Object is otherwise unstable and would
    # shuffle, for example, registry items relative to each other).
    $orderedDiff = @($diff | Sort-Object -Stable -Property @{ Expression = { Get-ConfigItemRank -Item $_ } })

    # Backup pre-change security state for audit/rollback
    if ($securityItems.Count -gt 0) {
        try {
            $preState = @{
                Timestamp           = Get-Date -Format 'o'
                DefenderPreferences = Get-MpPreference -ErrorAction SilentlyContinue |
                    Select-Object DisableRealtimeMonitoring, MAPSReporting, EnableNetworkProtection, PUAProtection, EnableControlledFolderAccess, SubmitSamplesConsent
                FirewallProfiles    = Get-NetFirewallProfile -ErrorAction SilentlyContinue | Select-Object Name, Enabled
            }
            $backupPath = Get-TempPath -Category 'data' -FileName "config-pre-state-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
            $preState | ConvertTo-Json -Depth 10 | Set-Content -Path $backupPath -Encoding UTF8 -Force
            Write-Log -Level INFO -Component CONFIG -Message "Pre-change state backed up: $backupPath"
        }
        catch { Write-Log -Level WARN -Component CONFIG -Message "Could not back up pre-change state: $_" }
    }

    foreach ($item in $orderedDiff) {
        $r = Invoke-ConfigurationItem -Item $item
        if ($r.Changed) { $processed++ }
        $failed += $r.Failed
        $errors += $r.Errors
        $rpCreated += $r.RpCreated
        $rpRemoved += $r.RpRemoved
        if ($r.RebootRequired) { $rebootNeeded = $true }
    }

    $status = if ($failed -eq 0) { 'Success' } elseif ($processed -gt 0) { 'Warning' } else { 'Failed' }
    Write-Log -Level INFO -Component CONFIG -Message "Done: $processed applied, $failed failed, restore points +$rpCreated/-$rpRemoved, Reboot: $(if ($rebootNeeded) { 'Yes' } else { 'No' })"

    return New-ModuleResult -ModuleName 'SystemConfiguration' -Status $status -ModuleType 'Type2' `
        -ItemsDetected $diff.Count -ItemsProcessed $processed -ItemsFailed $failed -Errors $errors `
        -Message "$processed change(s) applied: restore points +$rpCreated/-$rpRemoved, $($securityItems.Count) security, $($telemetryItems.Count) telemetry, $($optimizationItems.Count) optimization" `
        -RebootRequired $rebootNeeded -ExtraData @{
        RestorePointsCreated = $rpCreated
        RestorePointsRemoved = $rpRemoved
    }
}

Export-ModuleMember -Function 'Invoke-SystemConfiguration'
