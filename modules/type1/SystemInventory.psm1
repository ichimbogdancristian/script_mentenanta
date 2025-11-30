#Requires -Version 7.0
# Module Dependencies:
#   - ConfigManager.psm1 (for configuration and paths)
#   - LoggingManager.psm1 (for structured logging)

<#
.SYNOPSIS
    System Inventory Module - Type 1 (Inventory/Reporting)

.DESCRIPTION
    Collects comprehensive system information including hardware, software,
    services, and configuration details for maintenance analysis and reporting.

.NOTES
    Module Type: Type 1 (Inventory/Reporting)
    Dependencies: Windows WMI/CIM, Registry access
    Author: Windows Maintenance Automation Project
    Version: 1.0.0
#>

using namespace System.Collections.Generic

# Import required modules
$ModuleRoot = Split-Path -Parent $PSScriptRoot
$FileOrgPath = Join-Path $ModuleRoot 'core\FileOrganizationManager.psm1'
if (Test-Path $FileOrgPath) {
    Import-Module $FileOrgPath -Force
}

$LoggingPath = Join-Path $ModuleRoot 'core\LoggingManager.psm1'
if (Test-Path $LoggingPath) {
    Import-Module $LoggingPath -Force
}

#region Public Functions

<#
.SYNOPSIS
    Collects comprehensive system inventory information

.DESCRIPTION
    Gathers detailed system information including hardware specs, installed software,
    running services, network configuration, and security settings.

.PARAMETER UseCache
    Use cached results if available and not expired

.PARAMETER CacheTimeout
    Cache timeout in minutes (default: 30)

.PARAMETER IncludeDetailed
    Include detailed information that may take longer to collect

.EXAMPLE
    $inventory = Get-SystemInventory -IncludeDetailed
#>
function Get-SystemInventory {
    [CmdletBinding()]
    param(
        [Parameter()]
        [switch]$UseCache,

        [Parameter()]
        [int]$CacheTimeout = 30,

        [Parameter()]
        [switch]$IncludeDetailed
    )

    Write-Information "🔍 Starting system inventory collection..." -InformationAction Continue
    
    # Use centralized logging if available
    try {
        Write-LogEntry -Level 'INFO' -Component 'SYSTEM-INVENTORY' -Message 'Starting comprehensive system inventory collection' -Data @{
            UseCache = $UseCache
            CacheTimeout = $CacheTimeout
            IncludeDetailed = $IncludeDetailed
        }
    } catch {
        # LoggingManager not available, continue with standard output
    }

    # Check for cached inventory data if UseCache is enabled
    if ($UseCache) {
        $scriptRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
        # Use ConfigManager for path resolution if available
        try {
            $ConfigManagerPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'core\ConfigManager.psm1'
            if (Test-Path $ConfigManagerPath) {
                Import-Module $ConfigManagerPath -Force
                $inventoryDir = Get-InventoryPath
            } else {
                $inventoryDir = Join-Path $scriptRoot 'temp_files\inventory'
            }
        } catch {
            $inventoryDir = Join-Path $scriptRoot 'temp_files\inventory'
        }

        if (Test-Path $inventoryDir) {
            # Find the most recent inventory file
            $recentInventory = Get-ChildItem -Path $inventoryDir -Filter "system-inventory-*.json" |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1

            if ($recentInventory) {
                $cacheAge = (Get-Date) - $recentInventory.LastWriteTime
                if ($cacheAge.TotalMinutes -le $CacheTimeout) {
                    try {
                        Write-Information "  🗂️  Using cached inventory data (age: $([math]::Round($cacheAge.TotalMinutes, 1)) minutes)" -InformationAction Continue
                        $cachedData = Get-Content -Path $recentInventory.FullName -Raw | ConvertFrom-Json -AsHashtable
                        return $cachedData
                    }
                    catch {
                        Write-Warning "Failed to load cached inventory data: $_. Collecting fresh data."
                    }
                }
                else {
                    Write-Warning "  ⏰ Cached inventory data expired (age: $([math]::Round($cacheAge.TotalMinutes, 1)) minutes > $CacheTimeout minutes)"
                }
            }
        }
    }

    $startTime = Get-Date
    $inventoryData = @{}
    
    # Start performance tracking if LoggingManager is available
    $perfContext = $null
    try {
        $perfContext = Start-PerformanceTracking -OperationName 'SystemInventoryCollection' -Component 'SYSTEM-INVENTORY'
    } catch {
        # LoggingManager not available, continue without performance tracking
    }

    try {
        # Basic system information
        Write-Information "  📊 Collecting basic system information..." -InformationAction Continue
        $inventoryData.SystemInfo = Get-BasicSystemInfo

        # Hardware information
        Write-Information "  🖥️ Collecting hardware information..." -InformationAction Continue
        $inventoryData.Hardware = Get-HardwareInfo

        # Operating system details
        Write-Information "  💻 Collecting operating system details..." -InformationAction Continue
        $inventoryData.OperatingSystem = Get-OperatingSystemInfo

        # Installed software
        Write-Information "  📦 Collecting installed software..." -InformationAction Continue
        $inventoryData.InstalledSoftware = Get-InstalledSoftwareInfo

        # Running services
        Write-Information "  🔧 Collecting services information..." -InformationAction Continue
        $inventoryData.Services = Get-ServiceInfo

        # Network configuration
        Write-Information "  🌐 Collecting network configuration..." -InformationAction Continue
        $inventoryData.Network = Get-NetworkInfo

        if ($IncludeDetailed) {
            # Detailed information (slower to collect)
            Write-Information "  🔎 Collecting detailed information..." -InformationAction Continue
            $inventoryData.DetailedInfo = Get-DetailedSystemInfo
        }

        # Add metadata
        $inventoryData.Metadata = @{
            CollectionTime  = $startTime
            Duration        = ((Get-Date) - $startTime).TotalSeconds
            IncludeDetailed = $IncludeDetailed.IsPresent
            ComputerName    = $env:COMPUTERNAME
            UserName        = $env:USERNAME
            ModuleVersion   = '1.0.0'
        }

        $duration = [math]::Round($inventoryData.Metadata.Duration, 2)
        Write-Information "  ✅ System inventory completed in $duration seconds" -InformationAction Continue

        # Auto-save inventory data using organized file system
        try {
            # Save main inventory data
            $inventoryPath = Save-OrganizedFile -Data $inventoryData -FileType 'Data' -Category 'inventory' -FileName 'system-inventory' -Format 'JSON'
            if ($inventoryPath) {
                Write-Information "  💾 System inventory saved to: $inventoryPath" -InformationAction Continue
            }

            # Also save installed software as a separate list for easier comparison
            $installedSoftwarePath = Save-OrganizedFile -Data $inventoryData.InstalledSoftware -FileType 'Data' -Category 'inventory' -FileName 'installed-software' -Format 'JSON'
            if ($installedSoftwarePath) {
                Write-Information "  📦 Installed software list saved to: $installedSoftwarePath" -InformationAction Continue
            }
        }
        catch {
            Write-Warning "Failed to save inventory data: $_"
        }

        # Complete performance tracking and log final results
        try {
            if ($perfContext) {
                Complete-PerformanceTracking -PerformanceContext $perfContext -Success $true
            }
            
            Write-LogEntry -Level 'INFO' -Component 'SYSTEM-INVENTORY' -Message 'System inventory collection completed successfully' -Data @{
                CollectionTime = [math]::Round((Get-Date - $startTime).TotalSeconds, 2)
                ComponentsCollected = $inventoryData.Keys -join ', '
                SoftwareItemsFound = if ($inventoryData.InstalledSoftware) { $inventoryData.InstalledSoftware.Count } else { 0 }
                ServicesFound = if ($inventoryData.Services) { $inventoryData.Services.Count } else { 0 }
            }
        } catch {
            # LoggingManager not available, continue
        }

        return $inventoryData
    }
    catch {
        # Complete performance tracking with failure
        try {
            if ($perfContext) {
                Complete-PerformanceTracking -PerformanceContext $perfContext -Success $false
            }
            
            Write-LogEntry -Level 'ERROR' -Component 'SYSTEM-INVENTORY' -Message 'System inventory collection failed' -Data @{
                Error = $_.Exception.Message
                CollectionTime = [math]::Round((Get-Date - $startTime).TotalSeconds, 2)
            }
        } catch {
            # LoggingManager not available, continue
        }
        
        Write-Error "Failed to collect system inventory: $_"
        throw
    }
}

<#
.SYNOPSIS
    Exports system inventory to various formats

.DESCRIPTION
    Saves the system inventory data to JSON, XML, or CSV formats for reporting and analysis.

.PARAMETER InventoryData
    The inventory data object to export

.PARAMETER OutputPath
    Base path for output files (without extension)

.PARAMETER Format
    Export format(s): JSON, XML, CSV, or All

.EXAMPLE
    Export-SystemInventory -InventoryData $inventory -OutputPath (Get-ReportsPath) -Format All
#>
function Export-SystemInventory {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [hashtable]$InventoryData,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$OutputPath,

        [Parameter()]
        [ValidateSet('JSON', 'XML', 'CSV', 'All')]
        [string]$Format = 'JSON'
    )

    $baseDir = Split-Path $OutputPath -Parent
    if (-not (Test-Path $baseDir)) {
        New-Item -Path $baseDir -ItemType Directory -Force | Out-Null
    }

    $exports = @()

    if ($Format -eq 'All' -or $Format -eq 'JSON') {
        $jsonPath = "$OutputPath.json"
        if ($PSCmdlet.ShouldProcess($jsonPath, "Export to JSON")) {
            $InventoryData | ConvertTo-Json -Depth 10 | Out-File -FilePath $jsonPath -Encoding UTF8
            $exports += $jsonPath
            Write-Verbose "Exported to JSON: $jsonPath"
        }
    }

    if ($Format -eq 'All' -or $Format -eq 'XML') {
        $xmlPath = "$OutputPath.xml"
        if ($PSCmdlet.ShouldProcess($xmlPath, "Export to XML")) {
            $InventoryData | Export-Clixml -Path $xmlPath -Depth 10
            $exports += $xmlPath
            Write-Verbose "Exported to XML: $xmlPath"
        }
    }

    if ($Format -eq 'All' -or $Format -eq 'CSV') {
        $csvDir = "$OutputPath-CSV"
        if ($PSCmdlet.ShouldProcess($csvDir, "Export to CSV")) {
            if (-not (Test-Path $csvDir)) {
                New-Item -Path $csvDir -ItemType Directory -Force | Out-Null
            }

            # Export each section to separate CSV files
            foreach ($section in $InventoryData.Keys) {
                if ($section -ne 'Metadata' -and $InventoryData[$section] -is [Array]) {
                    $csvPath = Join-Path $csvDir "$section.csv"
                    $InventoryData[$section] | Export-Csv -Path $csvPath -NoTypeInformation
                    $exports += $csvPath
                }
            }
            Write-Verbose "Exported to CSV directory: $csvDir"
        }
    }

    return $exports
}

#endregion

#region Private Functions

<#
.SYNOPSIS
    Collects basic system information
#>
<#
.SYNOPSIS
    Retrieves basic system information using WMI/CIM

.DESCRIPTION
    Collects fundamental system details including computer name, domain membership,
    hardware manufacturer and model, memory capacity, processor count, and BIOS information.
    Uses CIM instances for optimal performance and compatibility.

.OUTPUTS
    [hashtable] Basic system information including ComputerName, Domain, Manufacturer,
    Model, TotalPhysicalMemory, NumberOfProcessors, BIOSVersion, BIOSManufacturer, SerialNumber

.NOTES
    Private function used internally by Get-SystemInventory.
    Handles WMI/CIM query failures gracefully by returning empty hashtable.
#>
function Get-BasicSystemInfo {
    try {
        $computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        $bios = Get-CimInstance -ClassName Win32_BIOS -ErrorAction Stop

        return @{
            ComputerName        = $computerSystem.Name
            Domain              = $computerSystem.Domain
            Manufacturer        = $computerSystem.Manufacturer
            Model               = $computerSystem.Model
            TotalPhysicalMemory = $computerSystem.TotalPhysicalMemory
            NumberOfProcessors  = $computerSystem.NumberOfProcessors
            BIOSVersion         = $bios.SMBIOSBIOSVersion
            BIOSManufacturer    = $bios.Manufacturer
            SerialNumber        = $bios.SerialNumber
        }
    }
    catch {
        Write-Warning "Failed to collect basic system info: $_"
        return @{}
    }
}

<#
.SYNOPSIS
    Collects hardware information
#>
function Get-HardwareInfo {
    try {
        $processor = Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop | Select-Object -First 1
        $memory = Get-CimInstance -ClassName Win32_PhysicalMemory -ErrorAction Stop
        $diskDrives = Get-CimInstance -ClassName Win32_DiskDrive -ErrorAction Stop
        $videoController = Get-CimInstance -ClassName Win32_VideoController -ErrorAction Stop |
        Where-Object { $_.Name -notlike "*Basic*" } | Select-Object -First 1

        return @{
            Processor = @{
                Name                      = $processor.Name
                Architecture              = $processor.Architecture
                NumberOfCores             = $processor.NumberOfCores
                NumberOfLogicalProcessors = $processor.NumberOfLogicalProcessors
                MaxClockSpeed             = $processor.MaxClockSpeed
            }
            Memory    = @{
                TotalModules  = $memory.Count
                TotalCapacity = ($memory | Measure-Object Capacity -Sum).Sum
                Modules       = $memory | ForEach-Object {
                    @{
                        Capacity     = $_.Capacity
                        Speed        = $_.Speed
                        Manufacturer = $_.Manufacturer
                        PartNumber   = $_.PartNumber
                    }
                }
            }
            Storage   = $diskDrives | ForEach-Object {
                @{
                    Model         = $_.Model
                    Size          = $_.Size
                    InterfaceType = $_.InterfaceType
                    MediaType     = $_.MediaType
                }
            }
            Graphics  = if ($videoController) {
                @{
                    Name          = $videoController.Name
                    DriverVersion = $videoController.DriverVersion
                    DriverDate    = $videoController.DriverDate
                    AdapterRAM    = $videoController.AdapterRAM
                }
            }
            else { $null }
        }
    }
    catch {
        Write-Warning "Failed to collect hardware info: $_"
        return @{}
    }
}

<#
.SYNOPSIS
    Collects operating system information
#>
function Get-OperatingSystemInfo {
    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        $timeZone = Get-TimeZone -ErrorAction Stop

        return @{
            Caption                = $os.Caption
            Version                = $os.Version
            BuildNumber            = $os.BuildNumber
            Architecture           = $os.OSArchitecture
            InstallDate            = $os.InstallDate
            LastBootUpTime         = $os.LastBootUpTime
            FreePhysicalMemory     = $os.FreePhysicalMemory
            TotalVirtualMemorySize = $os.TotalVirtualMemorySize
            TimeZone               = $timeZone.DisplayName
            PowerShellVersion      = $PSVersionTable.PSVersion.ToString()
            DotNetVersion          = [System.Environment]::Version.ToString()
        }
    }
    catch {
        Write-Warning "Failed to collect OS info: $_"
        return @{}
    }
}

<#
.SYNOPSIS
    Collects comprehensive installed software information from multiple sources

.DESCRIPTION
    Gathers installed software data from Registry (32-bit and 64-bit locations),
    AppX packages, Winget packages, and Chocolatey installations. Provides unified
    view of all installed software across different installation methods and architectures.

.OUTPUTS
    [hashtable] Software inventory containing Programs (registry-based), AppxPackages,
    WingetPackages, and ChocolateyPackages arrays with detailed information

.NOTES
    Private function used internally by Get-SystemInventory.
    Handles multiple software sources and provides fallback for unavailable package managers.
    Performance-optimized with parallel enumeration where possible.
#>
function Get-InstalledSoftwareInfo {
    try {
        # Use List for better memory management instead of array concatenation
        $installedPrograms = [System.Collections.Generic.List[hashtable]]::new(500)  # Pre-allocate capacity
        
        # Variables for cleanup tracking
        $appxPackages = $null
        $wingetOutput = $null
        
        try {
            # Get AppX packages
            try {
                $appxPackages = Get-AppxPackage -ErrorAction SilentlyContinue | Where-Object { $_.Name -notlike "*Microsoft*" -or $_.Name -like "*Microsoft.Office*" }
                foreach ($package in $appxPackages) {
                    $installedPrograms.Add(@{
                        Name            = $package.Name
                        DisplayName     = $package.PackageFullName
                        Version         = $package.Version
                        Publisher       = $package.Publisher
                        InstallLocation = $package.InstallLocation
                        Source          = 'AppX'
                    })
                }
                
                # Clear appx packages from memory after processing
                $appxPackages = $null
            }
            catch {
                Write-Verbose "Failed to collect AppX packages: $_"
            }

            # Get Winget packages
            try {
                $wingetOutput = winget list --accept-source-agreements 2>$null
                if ($wingetOutput) {
                    $wingetLines = $wingetOutput | Select-Object -Skip 2 | Where-Object { $_ -and $_ -notmatch "^-+" }
                    foreach ($line in $wingetLines) {
                        if ($line -match '^(.+?)\s+(.+?)\s+(.+?)\s+(.+?)$') {
                            $installedPrograms.Add(@{
                                Name      = $matches[1].Trim()
                                Version   = $matches[2].Trim()
                                Publisher = $matches[4].Trim()
                                Source    = 'Winget'
                            })
                        }
                    }
                    
                    # Clear winget output from memory
                    $wingetOutput = $null
                }
            }
            catch {
                Write-Verbose "Failed to collect Winget packages: $_"
            }

            # Get Chocolatey packages
            try {
                if (Get-Command choco -ErrorAction SilentlyContinue) {
                    $chocoOutput = choco list --local-only --no-progress 2>$null
                    foreach ($line in $chocoOutput) {
                        if ($line -match '^(.+?)\s+(.+?)$') {
                            $installedPrograms.Add(@{
                                Name      = $matches[1].Trim()
                                Version   = $matches[2].Trim()
                                Publisher = 'Chocolatey'
                                Source    = 'Chocolatey'
                            })
                        }
                    }
                    
                    # Clear choco output from memory
                    $chocoOutput = $null
                }
            }
            catch {
                Write-Verbose "Failed to collect Chocolatey packages: $_"
            }

            # Get programs from registry (both 32-bit and 64-bit)
            $registryPaths = @(
                'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
                'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
            )

            foreach ($path in $registryPaths) {
                $programs = Get-ItemProperty $path -ErrorAction SilentlyContinue |
                Where-Object { $_.DisplayName -and $_.DisplayName -notmatch '^KB[0-9]+' }

                foreach ($program in $programs) {
                    $installedPrograms.Add(@{
                        Name            = $program.DisplayName
                        DisplayName     = $program.DisplayName
                        Version         = $program.DisplayVersion
                        Publisher       = $program.Publisher
                        InstallDate     = $program.InstallDate
                        InstallLocation = $program.InstallLocation
                        UninstallString = $program.UninstallString
                        Size            = $program.EstimatedSize
                        Source          = 'Registry'
                    })
                }
                
                # Clear programs variable after processing each path
                $programs = $null
            }

            # Create result with sorted programs
            Write-Verbose "Creating final software inventory result with $($installedPrograms.Count) programs"
            $sortedPrograms = $installedPrograms.ToArray() | Sort-Object Name
            
            # Clear the list to free memory
            $installedPrograms.Clear()
            $installedPrograms = $null
            
            # Force garbage collection if we processed many programs
            if ($sortedPrograms.Count -gt 100) {
                Write-Verbose "Large program inventory detected, triggering garbage collection"
                [System.GC]::Collect()
                [System.GC]::WaitForPendingFinalizers()
            }

            return @{
                TotalCount = $sortedPrograms.Count
                Programs   = $sortedPrograms
            }
        }
        catch {
            # Cleanup on error
            if ($null -ne $installedPrograms) {
                $installedPrograms.Clear()
                $installedPrograms = $null
            }
            $appxPackages = $null
            $wingetOutput = $null
            
            Write-Verbose "Memory cleanup completed after error in software inventory"
            return @{ TotalCount = 0; Programs = @() }
        }
    }
    catch {
        Write-Warning "Failed to collect installed software info: $_"
        
        # Final cleanup on outer catch
        if ($null -ne $installedPrograms) {
            $installedPrograms.Clear()
            $installedPrograms = $null
        }
        
        return @{ TotalCount = 0; Programs = @() }
    }
}

<#
.SYNOPSIS
    Collects services information
#>
function Get-ServiceInfo {
    try {
        # Use WMI/CIM first as it has better permission handling than Get-Service
        try {
            Write-Verbose "Querying services using CIM (WMI) for better permission handling"
            $wmiServices = Get-CimInstance -ClassName Win32_Service -ErrorAction Stop
            $services = $wmiServices | ForEach-Object {
                [PSCustomObject]@{
                    Name        = $_.Name
                    DisplayName = $_.DisplayName
                    Status      = if ($_.State -eq 'Running') { 'Running' } else { 'Stopped' }
                    StartType   = $_.StartMode
                }
            }
        }
        catch {
            Write-Verbose "CIM approach failed, trying selective Get-Service: $_"
            # Fallback to Get-Service but with error handling for individual services
            $services = @()
            $allServiceNames = (Get-Service -ErrorAction SilentlyContinue).Name

            foreach ($serviceName in $allServiceNames) {
                try {
                    $service = Get-Service -Name $serviceName -ErrorAction Stop
                    $services += [PSCustomObject]@{
                        Name        = $service.Name
                        DisplayName = $service.DisplayName
                        Status      = $service.Status
                        StartType   = $service.StartType
                    }
                }
                catch {
                    # Skip services that can't be queried (like WaaSMedicSvc)
                    Write-Verbose "Skipping service '$serviceName' due to permission restriction"
                    continue
                }
            }
        }

        if ($services.Count -eq 0) {
            Write-Warning "No services could be queried. This may indicate permission restrictions."
            return @{
                TotalCount       = 0
                RunningCount     = 0
                StoppedCount     = 0
                RunningServices  = @()
                CriticalServices = @()
                Note             = "Limited permissions - service details unavailable"
            }
        }

        $runningServices = $services | Where-Object { $_.Status -eq 'Running' }
        $stoppedServices = $services | Where-Object { $_.Status -eq 'Stopped' }

        return @{
            TotalCount       = $services.Count
            RunningCount     = $runningServices.Count
            StoppedCount     = $stoppedServices.Count
            RunningServices  = $runningServices | ForEach-Object {
                @{
                    Name        = $_.Name
                    DisplayName = $_.DisplayName
                    Status      = $_.Status
                    StartType   = $_.StartType
                }
            }
            CriticalServices = $runningServices | Where-Object {
                $_.Name -in @('Winlogon', 'CSRSS', 'Wininit', 'Services', 'Lsass', 'Spooler')
            } | ForEach-Object {
                @{
                    Name        = $_.Name
                    DisplayName = $_.DisplayName
                    Status      = $_.Status
                }
            }
        }
    }
    catch {
        Write-Warning "Failed to collect services info: $_"
        return @{
            TotalCount       = 0
            RunningCount     = 0
            StoppedCount     = 0
            RunningServices  = @()
            CriticalServices = @()
            Error            = $_.Exception.Message
        }
    }
}

<#
.SYNOPSIS
    Collects network configuration information
#>
function Get-NetworkInfo {
    try {
        $adapters = Get-NetAdapter -Physical -ErrorAction Stop | Where-Object { $_.Status -eq 'Up' }
        $ipConfig = Get-NetIPConfiguration -ErrorAction Stop | Where-Object { $_.NetAdapter.Status -eq 'Up' }

        return @{
            Adapters             = $adapters | ForEach-Object {
                $config = $ipConfig | Where-Object { $_.InterfaceAlias -eq $_.Name }
                @{
                    Name           = $_.Name
                    Description    = $_.InterfaceDescription
                    LinkSpeed      = $_.LinkSpeed
                    MediaType      = $_.MediaType
                    MacAddress     = $_.MacAddress
                    IPAddress      = $config.IPv4Address.IPAddress -join ', '
                    SubnetMask     = $config.IPv4Address.PrefixLength -join ', '
                    DefaultGateway = $config.IPv4DefaultGateway.NextHop -join ', '
                    DNSServers     = $config.DNSServer.ServerAddresses -join ', '
                }
            }
            InternetConnectivity = Test-InternetConnectivity
        }
    }
    catch {
        Write-Warning "Failed to collect network info: $_"
        return @{}
    }
}

<#
.SYNOPSIS
    Collects detailed system information (slower operations)
#>
function Get-DetailedSystemInfo {
    try {
        return @{
            InstalledUpdates = Get-InstalledUpdateInfo
            StartupPrograms  = Get-StartupProgramsInfo
            ScheduledTasks   = Get-ScheduledTasksInfo
            EventLogSummary  = Get-EventLogSummary
        }
    }
    catch {
        Write-Warning "Failed to collect detailed info: $_"
        return @{}
    }
}

<#
.SYNOPSIS
    Gets installed Windows updates information
#>
function Get-InstalledUpdateInfo {
    try {
        $updates = Get-CimInstance -ClassName Win32_QuickFixEngineering -ErrorAction Stop |
        Sort-Object InstalledOn -Descending |
        Select-Object -First 20

        return @{
            RecentCount   = $updates.Count
            RecentUpdates = $updates | ForEach-Object {
                @{
                    HotFixID    = $_.HotFixID
                    Description = $_.Description
                    InstalledOn = $_.InstalledOn
                    InstalledBy = $_.InstalledBy
                }
            }
        }
    }
    catch {
        Write-Warning "Failed to get updates info: $_"
        return @{}
    }
}

<#
.SYNOPSIS
    Gets startup programs information
#>
function Get-StartupProgramsInfo {
    try {
        $startupItems = @()

        # Registry startup locations
        $startupPaths = @(
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
            'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce',
            'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce'
        )

        foreach ($path in $startupPaths) {
            try {
                $items = Get-ItemProperty $path -ErrorAction SilentlyContinue
                if ($items) {
                    foreach ($property in $items.PSObject.Properties) {
                        if ($property.Name -notin @('PSPath', 'PSParentPath', 'PSChildName', 'PSDrive', 'PSProvider')) {
                            $startupItems += @{
                                Name     = $property.Name
                                Command  = $property.Value
                                Location = $path
                            }
                        }
                    }
                }
            }
            catch {
                # Skip inaccessible registry paths
            }
        }

        return @{
            TotalCount = $startupItems.Count
            Items      = $startupItems
        }
    }
    catch {
        Write-Warning "Failed to get startup programs: $_"
        return @{}
    }
}

<#
.SYNOPSIS
    Gets scheduled tasks summary
#>
function Get-ScheduledTasksInfo {
    try {
        $tasks = Get-ScheduledTask -ErrorAction Stop
        $runningTasks = $tasks | Where-Object { $_.State -eq 'Running' }
        $enabledTasks = $tasks | Where-Object { $_.State -eq 'Ready' }

        return @{
            TotalCount   = $tasks.Count
            RunningCount = $runningTasks.Count
            EnabledCount = $enabledTasks.Count
            RunningTasks = $runningTasks | Select-Object -First 10 | ForEach-Object {
                @{
                    TaskName = $_.TaskName
                    TaskPath = $_.TaskPath
                    State    = $_.State
                }
            }
        }
    }
    catch {
        Write-Warning "Failed to get scheduled tasks: $_"
        return @{}
    }
}

<#
.SYNOPSIS
    Gets event log summary
#>
function Get-EventLogSummary {
    try {
        $logs = @('System', 'Application', 'Security')
        $summary = @{}

        foreach ($logName in $logs) {
            try {
                $events = Get-WinEvent -LogName $logName -MaxEvents 1000 -ErrorAction Stop
                $errors = $events | Where-Object { $_.LevelDisplayName -eq 'Error' }
                $warnings = $events | Where-Object { $_.LevelDisplayName -eq 'Warning' }

                $summary[$logName] = @{
                    TotalEvents  = $events.Count
                    ErrorCount   = $errors.Count
                    WarningCount = $warnings.Count
                    RecentErrors = $errors | Select-Object -First 5 | ForEach-Object {
                        @{
                            TimeCreated      = $_.TimeCreated
                            Id               = $_.Id
                            LevelDisplayName = $_.LevelDisplayName
                            Message          = $_.Message.Substring(0, [Math]::Min(200, $_.Message.Length))
                        }
                    }
                }
            }
            catch {
                $summary[$logName] = @{ Error = "Access denied or log not available" }
            }
        }

        return $summary
    }
    catch {
        Write-Warning "Failed to get event log summary: $_"
        return @{}
    }
}

<#
.SYNOPSIS
    Tests internet connectivity
#>
function Test-InternetConnectivity {
    try {
        $testSites = @('8.8.8.8', 'google.com', 'microsoft.com')
        $results = @{}

        foreach ($site in $testSites) {
            try {
                $result = Test-Connection -ComputerName $site -Count 1 -Quiet -TimeoutSeconds 5
                $results[$site] = $result
            }
            catch {
                $results[$site] = $false
            }
        }

        return $results
    }
    catch {
        return @{ Error = "Connectivity test failed" }
    }
}

#endregion

# Export module functions
Export-ModuleMember -Function @(
    'Get-SystemInventory',
    'Export-SystemInventory'
)
