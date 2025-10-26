#Requires -Version 7.0

<#
.SYNOPSIS
    System Inventory Audit - Type 1 (Detection/Analysis)

.DESCRIPTION
    Collects comprehensive system inventory including hardware, OS, network, and software information.
    Part of the v3.0 architecture where Type1 modules provide detection capabilities.

.NOTES
    Module Type: Type 1 (Detection/Analysis)
    Dependencies: CoreInfrastructure.psm1
    Architecture: v3.0 - Imported by Type2 module
    Author: Windows Maintenance Automation Project
    Version: 1.0.0
#>

using namespace System.Collections.Generic

# v3.0 Type 1 module - imported by Type 2 modules
# Check if CoreInfrastructure functions are available (loaded by Type2 module)
if (Get-Command 'Write-LogEntry' -ErrorAction SilentlyContinue) {
    Write-Verbose "CoreInfrastructure functions detected - using configuration-based functions"
}
else {
    Write-Verbose "CoreInfrastructure global import in progress - Write-LogEntry will be available momentarily"
}

#region Public Functions

<#
.SYNOPSIS
    Performs comprehensive system inventory audit

.DESCRIPTION
    Collects detailed information about the system including:
    - Operating System details
    - Hardware specifications (CPU, RAM, Disk)
    - Network configuration
    - Installed software summary
    - Security status

.PARAMETER Config
    Main configuration object containing module settings

.OUTPUTS
    PSCustomObject with complete system inventory

.EXAMPLE
    $inventory = Get-SystemInventoryAnalysis -Config $mainConfig
#>
function Get-SystemInventoryAnalysis {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Config
    )
    
    Write-Verbose "Starting system inventory analysis..."
    
    try {
        $inventory = [PSCustomObject]@{
            CollectionTimestamp = Get-Date -Format 'yyyy-MM-ddTHH:mm:ss'
            ComputerName        = $env:COMPUTERNAME
            OperatingSystem     = Get-OperatingSystemInfo
            Hardware            = Get-HardwareInfo
            Network             = Get-NetworkInfo
            Storage             = Get-StorageInfo
            Software            = Get-SoftwareSummary
            Security            = Get-SecurityStatus
            Performance         = Get-PerformanceMetrics
        }
        
        Write-Verbose "System inventory analysis complete"
        return $inventory
    }
    catch {
        Write-Error "System inventory analysis failed: $($_.Exception.Message)"
        return [PSCustomObject]@{
            CollectionTimestamp = Get-Date -Format 'yyyy-MM-ddTHH:mm:ss'
            Error               = $_.Exception.Message
        }
    }
}

#endregion

#region Helper Functions

function Get-OperatingSystemInfo {
    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem
        $cs = Get-CimInstance -ClassName Win32_ComputerSystem
        
        return [PSCustomObject]@{
            Name             = $os.Caption
            Version          = $os.Version
            Build            = $os.BuildNumber
            Architecture     = $os.OSArchitecture
            InstallDate      = $os.InstallDate
            LastBootTime     = $os.LastBootUpTime
            Manufacturer     = $cs.Manufacturer
            Model            = $cs.Model
            Domain           = $cs.Domain
            Workgroup        = $cs.Workgroup
            WindowsDirectory = $os.WindowsDirectory
            SystemDirectory  = $os.SystemDirectory
            Locale           = $os.Locale
            TimeZone         = $os.CurrentTimeZone
        }
    }
    catch {
        Write-Warning "Failed to collect OS info: $($_.Exception.Message)"
        return [PSCustomObject]@{ Error = $_.Exception.Message }
    }
}

function Get-HardwareInfo {
    try {
        $cpu = Get-CimInstance -ClassName Win32_Processor | Select-Object -First 1
        $ram = Get-CimInstance -ClassName Win32_PhysicalMemory
        $totalRAM = ($ram | Measure-Object -Property Capacity -Sum).Sum
        $bios = Get-CimInstance -ClassName Win32_BIOS
        
        return [PSCustomObject]@{
            Processor = [PSCustomObject]@{
                Name              = $cpu.Name
                Manufacturer      = $cpu.Manufacturer
                Cores             = $cpu.NumberOfCores
                LogicalProcessors = $cpu.NumberOfLogicalProcessors
                MaxClockSpeed     = "$($cpu.MaxClockSpeed) MHz"
                Architecture      = $cpu.Architecture
                L2CacheSize       = "$($cpu.L2CacheSize) KB"
                L3CacheSize       = "$($cpu.L3CacheSize) KB"
            }
            Memory    = [PSCustomObject]@{
                TotalPhysicalGB  = [math]::Round($totalRAM / 1GB, 2)
                ModulesInstalled = $ram.Count
                Speed            = "$($ram[0].Speed) MHz"
                FormFactor       = $ram[0].FormFactor
            }
            BIOS      = [PSCustomObject]@{
                Manufacturer = $bios.Manufacturer
                Version      = $bios.SMBIOSBIOSVersion
                ReleaseDate  = $bios.ReleaseDate
            }
        }
    }
    catch {
        Write-Warning "Failed to collect hardware info: $($_.Exception.Message)"
        return [PSCustomObject]@{ Error = $_.Exception.Message }
    }
}

function Get-NetworkInfo {
    try {
        $adapters = Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration | Where-Object { $_.IPEnabled -eq $true }
        
        $networkAdapters = foreach ($adapter in $adapters) {
            [PSCustomObject]@{
                Description    = $adapter.Description
                MACAddress     = $adapter.MACAddress
                IPAddresses    = $adapter.IPAddress -join ', '
                SubnetMasks    = $adapter.IPSubnet -join ', '
                DefaultGateway = $adapter.DefaultIPGateway -join ', '
                DNSServers     = $adapter.DNSServerSearchOrder -join ', '
                DHCPEnabled    = $adapter.DHCPEnabled
                DHCPServer     = $adapter.DHCPServer
            }
        }
        
        return [PSCustomObject]@{
            Adapters   = $networkAdapters
            HostName   = $env:COMPUTERNAME
            DomainName = (Get-CimInstance Win32_ComputerSystem).Domain
        }
    }
    catch {
        Write-Warning "Failed to collect network info: $($_.Exception.Message)"
        return [PSCustomObject]@{ Error = $_.Exception.Message }
    }
}

function Get-StorageInfo {
    try {
        $disks = Get-CimInstance -ClassName Win32_LogicalDisk | Where-Object { $_.DriveType -eq 3 }
        
        $diskInfo = foreach ($disk in $disks) {
            $freePercent = if ($disk.Size -gt 0) { 
                [math]::Round(($disk.FreeSpace / $disk.Size) * 100, 2) 
            }
            else { 0 }
            
            [PSCustomObject]@{
                Drive       = $disk.DeviceID
                Label       = $disk.VolumeName
                FileSystem  = $disk.FileSystem
                TotalSizeGB = [math]::Round($disk.Size / 1GB, 2)
                FreeSpaceGB = [math]::Round($disk.FreeSpace / 1GB, 2)
                UsedSpaceGB = [math]::Round(($disk.Size - $disk.FreeSpace) / 1GB, 2)
                FreePercent = $freePercent
                Status      = if ($freePercent -lt 10) { 'Critical' } 
                elseif ($freePercent -lt 20) { 'Warning' } 
                else { 'Healthy' }
            }
        }
        
        return [PSCustomObject]@{
            Drives          = $diskInfo
            TotalCapacityGB = [math]::Round(($disks | Measure-Object -Property Size -Sum).Sum / 1GB, 2)
            TotalFreeGB     = [math]::Round(($disks | Measure-Object -Property FreeSpace -Sum).Sum / 1GB, 2)
        }
    }
    catch {
        Write-Warning "Failed to collect storage info: $($_.Exception.Message)"
        return [PSCustomObject]@{ Error = $_.Exception.Message }
    }
}

function Get-SoftwareSummary {
    try {
        # Count installed applications from registry
        $x64Apps = Get-ItemProperty 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName } | Measure-Object | Select-Object -ExpandProperty Count
        
        $x86Apps = Get-ItemProperty 'HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName } | Measure-Object | Select-Object -ExpandProperty Count
        
        # Get Windows features count
        $features = Get-WindowsOptionalFeature -Online -ErrorAction SilentlyContinue | Where-Object { $_.State -eq 'Enabled' }
        
        return [PSCustomObject]@{
            InstalledApplications = $x64Apps + $x86Apps
            X64Applications       = $x64Apps
            X86Applications       = $x86Apps
            WindowsFeatures       = $features.Count
            PowerShellVersion     = $PSVersionTable.PSVersion.ToString()
            DotNetVersions        = (Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP' -Recurse -ErrorAction SilentlyContinue | 
                Get-ItemProperty -Name Version -ErrorAction SilentlyContinue | 
                Select-Object -ExpandProperty Version -Unique) -join ', '
        }
    }
    catch {
        Write-Warning "Failed to collect software summary: $($_.Exception.Message)"
        return [PSCustomObject]@{ Error = $_.Exception.Message }
    }
}

function Get-SecurityStatus {
    try {
        $defender = Get-MpComputerStatus -ErrorAction SilentlyContinue
        $uac = (Get-ItemProperty 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\System' -ErrorAction SilentlyContinue).EnableLUA
        $firewall = Get-NetFirewallProfile -ErrorAction SilentlyContinue
        
        return [PSCustomObject]@{
            WindowsDefender = [PSCustomObject]@{
                Enabled             = $defender.AntivirusEnabled
                DefinitionsUpToDate = $defender.AntivirusSignatureAge -le 7
                SignatureVersion    = $defender.AntivirusSignatureVersion
                LastScan            = $defender.AntivirusScanEndTime
                RealTimeProtection  = $defender.RealTimeProtectionEnabled
            }
            UAC             = [PSCustomObject]@{
                Enabled = ($uac -eq 1)
            }
            Firewall        = [PSCustomObject]@{
                DomainProfile  = ($firewall | Where-Object { $_.Name -eq 'Domain' }).Enabled
                PrivateProfile = ($firewall | Where-Object { $_.Name -eq 'Private' }).Enabled
                PublicProfile  = ($firewall | Where-Object { $_.Name -eq 'Public' }).Enabled
            }
            BitLocker       = [PSCustomObject]@{
                Status = (Get-BitLockerVolume -ErrorAction SilentlyContinue | Select-Object -First 1).ProtectionStatus
            }
        }
    }
    catch {
        Write-Warning "Failed to collect security status: $($_.Exception.Message)"
        return [PSCustomObject]@{ Error = $_.Exception.Message }
    }
}

function Get-PerformanceMetrics {
    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem
        $cpu = Get-CimInstance -ClassName Win32_Processor | Select-Object -First 1
        
        # Get process count
        $processes = (Get-Process).Count
        
        # Get uptime
        $bootTime = $os.LastBootUpTime
        $uptime = (Get-Date) - $bootTime
        
        return [PSCustomObject]@{
            CPUUsage           = "$([math]::Round($cpu.LoadPercentage, 2))%"
            MemoryUsageGB      = [math]::Round(($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / 1MB, 2)
            MemoryFreeGB       = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
            MemoryUsagePercent = [math]::Round((($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / $os.TotalVisibleMemorySize) * 100, 2)
            ProcessCount       = $processes
            Uptime             = "$($uptime.Days)d $($uptime.Hours)h $($uptime.Minutes)m"
            UptimeDays         = $uptime.Days
        }
    }
    catch {
        Write-Warning "Failed to collect performance metrics: $($_.Exception.Message)"
        return [PSCustomObject]@{ Error = $_.Exception.Message }
    }
}

#endregion

# Export public functions
Export-ModuleMember -Function @(
    'Get-SystemInventoryAnalysis'
)
