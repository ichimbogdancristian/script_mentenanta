#Requires -Version 7.0
<#
.SYNOPSIS    System Inventory - Type 1 (report-only, no Type2 pair)
.DESCRIPTION Gathers OS, hardware, disk, network, and installed software summary.
             Saves inventory to temp_files/data/ for inclusion in the HTML report.
.NOTES       Module Type: Type1 | DiffKey: SystemInventory (always empty) | Version: 5.0
#>

$_corePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'core\Maintenance.psm1'
if (-not (Get-Command 'Write-Log' -ErrorAction SilentlyContinue)) {
    Import-Module $_corePath -Force -Global -WarningAction SilentlyContinue
}

function Invoke-SystemInventory {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    Write-Log -Level INFO -Component INVENTORY -Message 'Starting system inventory'

    try {
        $inv = [ordered]@{ Timestamp = (Get-Date -Format 'o') }

        # OS
        try {
            $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
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
        catch { Write-Log -Level WARN -Component INVENTORY -Message "OS query failed: $_" }

        # CPU
        try {
            $cpu = Get-CimInstance Win32_Processor -ErrorAction Stop | Select-Object -First 1
            $inv.CPU = @{
                Name          = $cpu.Name
                Cores         = $cpu.NumberOfCores
                LogicalProcs  = $cpu.NumberOfLogicalProcessors
                MaxClockMHz   = $cpu.MaxClockSpeed
            }
        }
        catch { Write-Log -Level WARN -Component INVENTORY -Message "CPU query failed: $_" }

        # Memory
        try {
            $cs    = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
            $inv.Memory = @{
                TotalGB      = [math]::Round($cs.TotalPhysicalMemory / 1GB, 2)
                Manufacturer = $cs.Manufacturer
                Model        = $cs.Model
            }
        }
        catch { Write-Log -Level WARN -Component INVENTORY -Message "Memory query failed: $_" }

        # Disks
        try {
            $disks = Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' -ErrorAction Stop
            $inv.Disks = @($disks | ForEach-Object {
                @{
                    Drive   = $_.DeviceID
                    SizeGB  = [math]::Round($_.Size / 1GB, 1)
                    FreeGB  = [math]::Round($_.FreeSpace / 1GB, 1)
                    UsedPct = if ($_.Size -gt 0) { [math]::Round((($_.Size - $_.FreeSpace) / $_.Size) * 100, 1) } else { 0 }
                    FS      = $_.FileSystem
                }
            })
        }
        catch { Write-Log -Level WARN -Component INVENTORY -Message "Disk query failed: $_" }

        # Network adapters + internal/external IP (for the "what machine/network was
        # this run on" record the HTML report keeps for later review)
        try {
            $nics = Get-CimInstance Win32_NetworkAdapterConfiguration -Filter 'IPEnabled=True' -ErrorAction Stop
            $adapters = @($nics | ForEach-Object {
                    @{
                        Description = $_.Description
                        MAC         = $_.MACAddress
                        IPs         = $_.IPAddress
                        Gateway     = $_.DefaultIPGateway
                    }
                })
            # Primary internal IPv4 = first adapter's first IPv4-looking address
            $primaryIPv4 = $null
            $primaryGateway = $null
            foreach ($nic in $nics) {
                $ipv4 = @($nic.IPAddress) | Where-Object { $_ -match '^\d{1,3}(\.\d{1,3}){3}$' } | Select-Object -First 1
                if ($ipv4) {
                    $primaryIPv4 = $ipv4
                    $primaryGateway = @($nic.DefaultIPGateway) | Select-Object -First 1
                    break
                }
            }
            $inv.Network = @{
                Adapters       = $adapters
                InternalIP     = $primaryIPv4 ?? 'Unknown'
                DefaultGateway = $primaryGateway ?? 'Unknown'
            }
        }
        catch {
            Write-Log -Level WARN -Component INVENTORY -Message "Network query failed: $_"
            $inv.Network = @{ Adapters = @(); InternalIP = 'Unknown'; DefaultGateway = 'Unknown' }
        }

        # External (public-facing) IP — best-effort, short timeout, never blocks or
        # fails the audit if there's no internet access or the call is firewalled.
        # NOTE: this makes one outbound HTTPS call to a third-party IP-echo service
        # (api.ipify.org) purely to read back the response; nothing is sent besides
        # the request itself.
        try {
            $extIp = Invoke-RestMethod -Uri 'https://api.ipify.org?format=text' -TimeoutSec 5 -ErrorAction Stop
            $inv.Network.ExternalIP = "$extIp".Trim()
        }
        catch {
            Write-Log -Level DEBUG -Component INVENTORY -Message "External IP lookup unavailable (no internet or blocked): $_"
            $inv.Network.ExternalIP = 'Unavailable'
        }

        # Installed apps count
        try {
            $appCount      = @(Get-InstalledApp).Count
            $inv.Software  = @{ InstalledAppCount = $appCount }
        }
        catch { Write-Log -Level WARN -Component INVENTORY -Message "Installed apps count failed: $_" }

        # User info
        $inv.Session = @{
            ComputerName = $env:COMPUTERNAME
            UserName     = $env:USERNAME
            Domain       = $env:USERDOMAIN
            IsAdmin      = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        }

        # Local user accounts — flagged separately from the small set of accounts
        # present on any fresh Windows install (Administrator/Guest/DefaultAccount/
        # WDAGUtilityAccount/defaultuser0), so anything left over — extra admin
        # accounts, unexpected logins, accounts nobody remembers creating — stands
        # out for manual review in the report instead of being buried among normal
        # Windows plumbing accounts.
        $defaultAccountNames = @('Administrator', 'Guest', 'DefaultAccount', 'WDAGUtilityAccount', 'defaultuser0')
        try {
            $localUsers = Get-LocalUser -ErrorAction Stop
            $inv.LocalUsers = @($localUsers | ForEach-Object {
                    @{
                        Name            = $_.Name
                        Enabled         = $_.Enabled
                        IsDefaultOnAnyWindowsInstall = $_.Name -in $defaultAccountNames
                        Description     = $_.Description
                        LastLogon       = if ($_.LastLogon) { $_.LastLogon.ToString('yyyy-MM-dd HH:mm:ss') } else { 'Never' }
                        PasswordLastSet = if ($_.PasswordLastSet) { $_.PasswordLastSet.ToString('yyyy-MM-dd') } else { 'N/A' }
                    }
                })
            Write-Log -Level DEBUG -Component INVENTORY -Message "Local users enumerated: $($inv.LocalUsers.Count) total"
        }
        catch {
            # Get-LocalUser needs the Microsoft.PowerShell.LocalAccounts module; fall
            # back to the WMI/CIM equivalent, which is present on every Windows version.
            try {
                $localUsers = Get-CimInstance Win32_UserAccount -Filter 'LocalAccount=True' -ErrorAction Stop
                $inv.LocalUsers = @($localUsers | ForEach-Object {
                        @{
                            Name                         = $_.Name
                            Enabled                      = -not $_.Disabled
                            IsDefaultOnAnyWindowsInstall = $_.Name -in $defaultAccountNames
                            Description                  = $_.Description
                            LastLogon                    = 'Unknown (WMI fallback)'
                            PasswordLastSet               = 'Unknown (WMI fallback)'
                        }
                    })
                Write-Log -Level DEBUG -Component INVENTORY -Message "Local users enumerated via WMI fallback: $($inv.LocalUsers.Count) total"
            }
            catch {
                Write-Log -Level WARN -Component INVENTORY -Message "Local user enumeration failed: $_"
                $inv.LocalUsers = @()
            }
        }

        # Misc system details useful for later asset/security review
        try {
            $cs2 = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
            $bios = Get-CimInstance Win32_BIOS -ErrorAction SilentlyContinue
            $inv.SystemDetails = @{
                DomainOrWorkgroup = if ($cs2.PartOfDomain) { "$($cs2.Domain) (domain)" } else { "$($cs2.Workgroup) (workgroup)" }
                TimeZone          = (Get-TimeZone -ErrorAction SilentlyContinue).Id ?? [System.TimeZoneInfo]::Local.Id
                BIOSSerialNumber  = if ($bios) { $bios.SerialNumber } else { 'Unknown' }
            }
        }
        catch { Write-Log -Level WARN -Component INVENTORY -Message "System details query failed: $_" }

        # 2. No diff needed (inventory-only) — save empty diff
        Save-DiffList -ModuleName 'SystemInventory' -DiffList @()

        # 3. Save inventory data
        $invPath = Get-TempPath -Category 'data' -FileName 'system-inventory.json'
        $inv | ConvertTo-Json -Depth 8 | Set-Content -Path $invPath -Encoding UTF8 -Force

        Write-Log -Level SUCCESS -Component INVENTORY -Message 'System inventory complete'
        return New-ModuleResult -ModuleName 'SystemInventory' -Status 'Success' `
                                -Message "Inventory saved to $invPath" `
                                -ExtraData $inv
    }
    catch {
        Write-Log -Level ERROR -Component INVENTORY -Message "Inventory failed: $_"
        return New-ModuleResult -ModuleName 'SystemInventory' -Status 'Failed' -Errors @($_.ToString())
    }
}

Export-ModuleMember -Function 'Invoke-SystemInventory'
