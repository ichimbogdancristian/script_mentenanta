#Requires -Version 7.0

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

# Module-level cache variables
$script:CachedInventory = $null
$script:CacheTimestamp = $null
$script:DefaultCacheTimeoutMinutes = 30

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
    
    # Check if we can use cached data
    if ($UseCache -and $script:CachedInventory -and $script:CacheTimestamp) {
        $cacheAge = ((Get-Date) - $script:CacheTimestamp).TotalMinutes
        $maxAge = if ($CacheTimeout -gt 0) { $CacheTimeout } else { $script:DefaultCacheTimeoutMinutes }
        
        if ($cacheAge -lt $maxAge) {
            # Check if detailed info requirement matches cache
            $cachedHasDetailed = $script:CachedInventory.Metadata.IncludeDetailed
            if ($IncludeDetailed -eq $cachedHasDetailed) {
                Write-Host "🔄 Using cached system inventory (age: $([math]::Round($cacheAge, 1)) minutes)" -ForegroundColor Yellow
                return $script:CachedInventory
            }
        }
    }
    
    Write-Host "🔍 Starting system inventory collection..." -ForegroundColor Cyan
    
    $startTime = Get-Date
    $inventoryData = @{}
    
    try {
        # Basic system information
        Write-Host "  📊 Collecting basic system information..." -ForegroundColor Gray
        $inventoryData.SystemInfo = Get-BasicSystemInfo
        
        # Hardware information
        Write-Host "  🖥️ Collecting hardware information..." -ForegroundColor Gray
        $inventoryData.Hardware = Get-HardwareInfo
        
        # Operating system details
        Write-Host "  💻 Collecting operating system details..." -ForegroundColor Gray
        $inventoryData.OperatingSystem = Get-OperatingSystemInfo
        
        # Installed software
        Write-Host "  📦 Collecting installed software..." -ForegroundColor Gray
        $inventoryData.InstalledSoftware = Get-InstalledSoftwareInfo
        
        # Running services
        Write-Host "  🔧 Collecting services information..." -ForegroundColor Gray
        $inventoryData.Services = Get-ServicesInfo
        
        # Network configuration
        Write-Host "  🌐 Collecting network configuration..." -ForegroundColor Gray
        $inventoryData.Network = Get-NetworkInfo
        
        if ($IncludeDetailed) {
            # Detailed information (slower to collect)
            Write-Host "  🔎 Collecting detailed information..." -ForegroundColor Gray
            $inventoryData.DetailedInfo = Get-DetailedSystemInfo
        }
        
        # Add metadata
        $inventoryData.Metadata = @{
            CollectionTime = $startTime
            Duration = ((Get-Date) - $startTime).TotalSeconds
            IncludeDetailed = $IncludeDetailed.IsPresent
            ComputerName = $env:COMPUTERNAME
            UserName = $env:USERNAME
            ModuleVersion = '1.0.0'
        }
        
        $duration = [math]::Round($inventoryData.Metadata.Duration, 2)
        Write-Host "  ✅ System inventory completed in $duration seconds" -ForegroundColor Green
        
        # Cache the results for future use
        $script:CachedInventory = $inventoryData
        $script:CacheTimestamp = Get-Date
        
        return $inventoryData
    }
    catch {
        Write-Error "Failed to collect system inventory: $_"
        throw
    }
}

<#
.SYNOPSIS
    Clears the system inventory cache
    
.DESCRIPTION
    Forces clearing of the cached system inventory data to ensure fresh collection
    on the next call to Get-SystemInventory with -UseCache.
    
.EXAMPLE
    Clear-SystemInventoryCache
#>
function Clear-SystemInventoryCache {
    [CmdletBinding()]
    param()
    
    $script:CachedInventory = $null
    $script:CacheTimestamp = $null
    
    Write-Host "🗑️ System inventory cache cleared" -ForegroundColor Yellow
}

<#
.SYNOPSIS
    Gets information about the current system inventory cache
    
.DESCRIPTION
    Returns details about the cached inventory including cache age, 
    whether detailed info is included, and cache validity.
    
.EXAMPLE
    Get-SystemInventoryCacheInfo
#>
function Get-SystemInventoryCacheInfo {
    [CmdletBinding()]
    param()
    
    if (-not $script:CachedInventory -or -not $script:CacheTimestamp) {
        return @{
            IsCached = $false
            CacheAge = $null
            CacheTimestamp = $null
            IncludesDetailed = $false
            IsExpired = $true
            DefaultTimeoutMinutes = $script:DefaultCacheTimeoutMinutes
        }
    }
    
    $cacheAge = (Get-Date) - $script:CacheTimestamp
    $isExpired = $cacheAge.TotalMinutes -gt $script:DefaultCacheTimeoutMinutes
    
    return @{
        IsCached = $true
        CacheAge = $cacheAge
        CacheAgeMinutes = [math]::Round($cacheAge.TotalMinutes, 1)
        CacheTimestamp = $script:CacheTimestamp
        IncludesDetailed = $script:CachedInventory.Metadata.IncludeDetailed
        IsExpired = $isExpired
        DefaultTimeoutMinutes = $script:DefaultCacheTimeoutMinutes
        ComputerName = $script:CachedInventory.Metadata.ComputerName
        CollectionDuration = $script:CachedInventory.Metadata.Duration
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
    Export-SystemInventory -InventoryData $inventory -OutputPath "C:\Reports\SystemInventory" -Format All
#>
function Export-SystemInventory {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [hashtable]$InventoryData,
        
        [Parameter()]
        [string]$OutputPath,
        
        [Parameter()]
        [ValidateSet('JSON', 'XML', 'CSV', 'All')]
        [string]$Format = 'JSON',
        
        [Parameter()]
        [string]$ModuleName = 'SystemInventory',
        
        [Parameter()]
        [switch]$UseStandardPath
    )
    
    # Determine output paths
    if ($UseStandardPath -or -not $OutputPath) {
        # Use standardized paths from ConfigManager
        try {
            Import-Module (Join-Path $PSScriptRoot '..\core\ConfigManager.psm1') -Force -ErrorAction Stop
            $paths = Get-StandardInventoryPath -ModuleName $ModuleName -Format $Format
        } catch {
            Write-Warning "Could not load ConfigManager for standardized paths, falling back to default"
            $defaultFolder = Join-Path $PSScriptRoot '..\..\temp_files\inventory'
            if (-not (Test-Path $defaultFolder)) {
                New-Item -Path $defaultFolder -ItemType Directory -Force | Out-Null
            }
            $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
            $hostname = $env:COMPUTERNAME
            $baseFileName = "$ModuleName-inventory-$hostname-$timestamp"
            $OutputPath = Join-Path $defaultFolder $baseFileName
            $paths = @{}
            if ($Format -eq 'All') {
                $paths.JSON = "$OutputPath.json"
                $paths.XML = "$OutputPath.xml"
                $paths.CSV = "$OutputPath-csv"
            } else {
                $paths[$Format] = if ($Format -eq 'CSV') { "$OutputPath-csv" } else { "$OutputPath.$($Format.ToLower())" }
            }
        }
    } else {
        # Use provided OutputPath (backward compatibility)
        $baseDir = Split-Path $OutputPath -Parent
        if (-not (Test-Path $baseDir)) {
            New-Item -Path $baseDir -ItemType Directory -Force | Out-Null
        }
        $paths = @{}
        if ($Format -eq 'All') {
            $paths.JSON = "$OutputPath.json"
            $paths.XML = "$OutputPath.xml"
            $paths.CSV = "$OutputPath-CSV"
        } else {
            $paths[$Format] = if ($Format -eq 'CSV') { "$OutputPath-CSV" } else { "$OutputPath.$($Format.ToLower())" }
        }
    }
    
    # Enhance metadata with export provenance information
    $enhancedInventoryData = $InventoryData.Clone()
    if (-not $enhancedInventoryData.Metadata) {
        $enhancedInventoryData.Metadata = @{}
    }
    
    $enhancedInventoryData.Metadata.ExportInfo = @{
        ExportTime = Get-Date
        ExportFormat = $Format
        ExportModule = $ModuleName
        ExportedBy = $env:USERNAME
        ExportHostname = $env:COMPUTERNAME
        ExportVersion = '1.1.0'  # Updated version for enhanced exports
        StandardizedPaths = $UseStandardPath -or (-not $OutputPath)
    }
    
    $exports = @()
    
    # Export to JSON
    if ($paths.ContainsKey('JSON')) {
        $jsonPath = $paths.JSON
        if ($PSCmdlet.ShouldProcess($jsonPath, "Export to JSON")) {
            $parentDir = Split-Path $jsonPath -Parent
            if (-not (Test-Path $parentDir)) {
                New-Item -Path $parentDir -ItemType Directory -Force | Out-Null
            }
            
            $enhancedInventoryData | ConvertTo-Json -Depth 10 | Out-File -FilePath $jsonPath -Encoding UTF8
            $exports += $jsonPath
            Write-Verbose "Exported to JSON: $jsonPath"
        }
    }
    
    # Export to XML
    if ($paths.ContainsKey('XML')) {
        $xmlPath = $paths.XML
        if ($PSCmdlet.ShouldProcess($xmlPath, "Export to XML")) {
            $parentDir = Split-Path $xmlPath -Parent
            if (-not (Test-Path $parentDir)) {
                New-Item -Path $parentDir -ItemType Directory -Force | Out-Null
            }
            
            $enhancedInventoryData | Export-Clixml -Path $xmlPath -Depth 10
            $exports += $xmlPath
            Write-Verbose "Exported to XML: $xmlPath"
        }
    }
    
    # Export to CSV
    if ($paths.ContainsKey('CSV')) {
        $csvDir = $paths.CSV
        if ($PSCmdlet.ShouldProcess($csvDir, "Export to CSV")) {
            if (-not (Test-Path $csvDir)) {
                New-Item -Path $csvDir -ItemType Directory -Force | Out-Null
            }
            
            # Export metadata as a summary file
            $metadataPath = Join-Path $csvDir "00-metadata.csv"
            $metadataFlattened = @()
            
            function Flatten-Object {
                param($Object, $Prefix = "")
                if ($Object -is [hashtable] -or $Object -is [PSCustomObject]) {
                    foreach ($key in $Object.PSObject.Properties.Name -or $Object.Keys) {
                        $newPrefix = if ($Prefix) { "$Prefix.$key" } else { $key }
                        $value = if ($Object -is [hashtable]) { $Object[$key] } else { $Object.$key }
                        if ($value -is [hashtable] -or $value -is [PSCustomObject]) {
                            Flatten-Object -Object $value -Prefix $newPrefix
                        } else {
                            $metadataFlattened += [PSCustomObject]@{ Property = $newPrefix; Value = $value }
                        }
                    }
                }
            }
            
            Flatten-Object -Object $enhancedInventoryData.Metadata
            $metadataFlattened | Export-Csv -Path $metadataPath -NoTypeInformation
            $exports += $metadataPath
            
            # Export each section to separate CSV files
            foreach ($section in $enhancedInventoryData.Keys) {
                if ($section -ne 'Metadata' -and $enhancedInventoryData[$section] -is [Array]) {
                    $csvPath = Join-Path $csvDir "$section.csv"
                    $enhancedInventoryData[$section] | Export-Csv -Path $csvPath -NoTypeInformation
                    $exports += $csvPath
                } elseif ($section -ne 'Metadata' -and $enhancedInventoryData[$section]) {
                    # Handle non-array objects by converting to single-row CSV
                    $csvPath = Join-Path $csvDir "$section.csv"
                    @($enhancedInventoryData[$section]) | Export-Csv -Path $csvPath -NoTypeInformation
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
function Get-BasicSystemInfo {
    try {
        $computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        $bios = Get-CimInstance -ClassName Win32_BIOS -ErrorAction Stop
        
        return @{
            ComputerName = $computerSystem.Name
            Domain = $computerSystem.Domain
            Manufacturer = $computerSystem.Manufacturer
            Model = $computerSystem.Model
            TotalPhysicalMemory = $computerSystem.TotalPhysicalMemory
            NumberOfProcessors = $computerSystem.NumberOfProcessors
            BIOSVersion = $bios.SMBIOSBIOSVersion
            BIOSManufacturer = $bios.Manufacturer
            SerialNumber = $bios.SerialNumber
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
                Name = $processor.Name
                Architecture = $processor.Architecture
                NumberOfCores = $processor.NumberOfCores
                NumberOfLogicalProcessors = $processor.NumberOfLogicalProcessors
                MaxClockSpeed = $processor.MaxClockSpeed
            }
            Memory = @{
                TotalModules = $memory.Count
                TotalCapacity = ($memory | Measure-Object Capacity -Sum).Sum
                Modules = $memory | ForEach-Object {
                    @{
                        Capacity = $_.Capacity
                        Speed = $_.Speed
                        Manufacturer = $_.Manufacturer
                        PartNumber = $_.PartNumber
                    }
                }
            }
            Storage = $diskDrives | ForEach-Object {
                @{
                    Model = $_.Model
                    Size = $_.Size
                    InterfaceType = $_.InterfaceType
                    MediaType = $_.MediaType
                }
            }
            Graphics = if ($videoController) {
                @{
                    Name = $videoController.Name
                    DriverVersion = $videoController.DriverVersion
                    DriverDate = $videoController.DriverDate
                    AdapterRAM = $videoController.AdapterRAM
                }
            } else { $null }
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
            Caption = $os.Caption
            Version = $os.Version
            BuildNumber = $os.BuildNumber
            Architecture = $os.OSArchitecture
            InstallDate = $os.InstallDate
            LastBootUpTime = $os.LastBootUpTime
            FreePhysicalMemory = $os.FreePhysicalMemory
            TotalVirtualMemorySize = $os.TotalVirtualMemorySize
            TimeZone = $timeZone.DisplayName
            PowerShellVersion = $PSVersionTable.PSVersion.ToString()
            DotNetVersion = [System.Environment]::Version.ToString()
        }
    }
    catch {
        Write-Warning "Failed to collect OS info: $_"
        return @{}
    }
}

<#
.SYNOPSIS
    Collects installed software information
#>
function Get-InstalledSoftwareInfo {
    try {
        $installedPrograms = @()
        
        # Get programs from registry (both 32-bit and 64-bit)
        $registryPaths = @(
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
        )
        
        foreach ($path in $registryPaths) {
            $programs = Get-ItemProperty $path -ErrorAction SilentlyContinue |
                       Where-Object { $_.DisplayName -and $_.DisplayName -notmatch '^KB[0-9]+' }
            
            foreach ($program in $programs) {
                $installedPrograms += @{
                    Name = $program.DisplayName
                    Version = $program.DisplayVersion
                    Publisher = $program.Publisher
                    InstallDate = $program.InstallDate
                    InstallLocation = $program.InstallLocation
                    UninstallString = $program.UninstallString
                    Size = $program.EstimatedSize
                }
            }
        }
        
        return @{
            TotalCount = $installedPrograms.Count
            Programs = $installedPrograms | Sort-Object Name
        }
    }
    catch {
        Write-Warning "Failed to collect installed software info: $_"
        return @{ TotalCount = 0; Programs = @() }
    }
}

<#
.SYNOPSIS
    Collects services information
#>
function Get-ServicesInfo {
    try {
        $services = Get-Service -ErrorAction SilentlyContinue
        $runningServices = $services | Where-Object { $_.Status -eq 'Running' }
        $stoppedServices = $services | Where-Object { $_.Status -eq 'Stopped' }
        
        return @{
            TotalCount = $services.Count
            RunningCount = $runningServices.Count
            StoppedCount = $stoppedServices.Count
            RunningServices = $runningServices | ForEach-Object {
                @{
                    Name = $_.Name
                    DisplayName = $_.DisplayName
                    Status = $_.Status
                    StartType = $_.StartType
                }
            }
            CriticalServices = $runningServices | Where-Object { 
                $_.Name -in @('Winlogon', 'CSRSS', 'Wininit', 'Services', 'Lsass', 'Spooler') 
            } | ForEach-Object {
                @{
                    Name = $_.Name
                    DisplayName = $_.DisplayName
                    Status = $_.Status
                }
            }
        }
    }
    catch {
        Write-Warning "Failed to collect services info: $_"
        return @{}
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
            Adapters = $adapters | ForEach-Object {
                $config = $ipConfig | Where-Object { $_.InterfaceAlias -eq $_.Name }
                @{
                    Name = $_.Name
                    Description = $_.InterfaceDescription
                    LinkSpeed = $_.LinkSpeed
                    MediaType = $_.MediaType
                    MacAddress = $_.MacAddress
                    IPAddress = $config.IPv4Address.IPAddress -join ', '
                    SubnetMask = $config.IPv4Address.PrefixLength -join ', '
                    DefaultGateway = $config.IPv4DefaultGateway.NextHop -join ', '
                    DNSServers = $config.DNSServer.ServerAddresses -join ', '
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
            InstalledUpdates = Get-InstalledUpdatesInfo
            StartupPrograms = Get-StartupProgramsInfo
            ScheduledTasks = Get-ScheduledTasksInfo
            EventLogSummary = Get-EventLogSummary
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
function Get-InstalledUpdatesInfo {
    try {
        $updates = Get-CimInstance -ClassName Win32_QuickFixEngineering -ErrorAction Stop |
                   Sort-Object InstalledOn -Descending |
                   Select-Object -First 20
        
        return @{
            RecentCount = $updates.Count
            RecentUpdates = $updates | ForEach-Object {
                @{
                    HotFixID = $_.HotFixID
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
                                Name = $property.Name
                                Command = $property.Value
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
            Items = $startupItems
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
            TotalCount = $tasks.Count
            RunningCount = $runningTasks.Count
            EnabledCount = $enabledTasks.Count
            RunningTasks = $runningTasks | Select-Object -First 10 | ForEach-Object {
                @{
                    TaskName = $_.TaskName
                    TaskPath = $_.TaskPath
                    State = $_.State
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
                    TotalEvents = $events.Count
                    ErrorCount = $errors.Count
                    WarningCount = $warnings.Count
                    RecentErrors = $errors | Select-Object -First 5 | ForEach-Object {
                        @{
                            TimeCreated = $_.TimeCreated
                            Id = $_.Id
                            LevelDisplayName = $_.LevelDisplayName
                            Message = $_.Message.Substring(0, [Math]::Min(200, $_.Message.Length))
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
    'Export-SystemInventory',
    'Clear-SystemInventoryCache',
    'Get-SystemInventoryCacheInfo'
)