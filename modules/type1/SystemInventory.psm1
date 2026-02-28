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

        # Network adapters
        try {
            $nics = Get-CimInstance Win32_NetworkAdapterConfiguration -Filter 'IPEnabled=True' -ErrorAction Stop
            $inv.Network = @($nics | ForEach-Object {
                @{
                    Description = $_.Description
                    MAC         = $_.MACAddress
                    IPs         = $_.IPAddress
                }
            })
        }
        catch { Write-Log -Level WARN -Component INVENTORY -Message "Network query failed: $_" }

        # Installed apps count
        try {
            $appCount      = @(Get-InstalledApp).Count
            $inv.Software  = @{ InstalledAppCount = $appCount }
        }
        catch { }

        # User info
        $inv.Session = @{
            ComputerName = $env:COMPUTERNAME
            UserName     = $env:USERNAME
            Domain       = $env:USERDOMAIN
            IsAdmin      = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        }

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
