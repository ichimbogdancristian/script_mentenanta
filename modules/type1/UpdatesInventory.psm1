<#
.MODULEINFO
Type = "Type1"
Category = "Updates"
MenuText = "Scan Windows Updates Status"
Description = "Scans for available Windows updates, pending updates, and update history"
DataFile = "updates-inventory.json"
ScanInterval = 3600
DependsOn = @("Infrastructure")
#>

<#
.SYNOPSIS
    Updates Inventory Module v3.0 - Type 1 (Read-Only)

.DESCRIPTION
    Comprehensive Windows Update inventory scanner that collects:
    - Available updates from Windows Update
    - Pending updates waiting for installation
    - Update history (installed, failed)
    - WSUS/Windows Update configuration
    - Update service status

.NOTES
    Author: Windows Maintenance Automation Project
    Version: 3.0.0
    Module Type: Type1 (Read-Only)
    Requires: PowerShell 7.0+, PSWindowsUpdate module
    Dependencies: Infrastructure.psm1
#>

#Requires -Version 7.0

<#
.SYNOPSIS
    Gets comprehensive Windows Update inventory.

.DESCRIPTION
    Scans Windows Update status including available, pending, and installed updates.
    Checks update service configuration and health.

.PARAMETER UseCache
    Use cached data if available and not expired (default: true).

.PARAMETER ForceRefresh
    Force a fresh scan even if cached data exists.

.OUTPUTS
    PSCustomObject containing complete updates inventory.

.EXAMPLE
    Get-UpdatesInventory
    
.EXAMPLE
    Get-UpdatesInventory -ForceRefresh
#>
function Get-UpdatesInventory {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $false)]
        [switch]$ForceRefresh
    )
    
    $perf = Start-PerformanceTracking -OperationName 'UpdatesInventoryScan' -Component 'Updates'
    
    try {
        Write-DetailedLog -Level 'INFO' -Component 'Updates' -Message 'Starting Windows Update inventory scan'
        
        # Check for cached data (default behavior unless ForceRefresh is specified)
        if (-not $ForceRefresh) {
            Write-DetailedLog -Level 'INFO' -Component 'Updates' -Message 'Checking for cached updates inventory'
            
            $cachedData = Import-InventoryFile -Category 'Updates'
            
            if ($cachedData -and $cachedData.metadata -and $cachedData.metadata.scanDate) {
                $scanDate = [datetime]::Parse($cachedData.metadata.scanDate)
                $age = (Get-Date) - $scanDate
                $cacheExpiration = Get-ConfigValue -Path 'inventory.cacheExpirationMinutes' -Default 60
                
                if ($age.TotalMinutes -lt $cacheExpiration) {
                    Write-DetailedLog -Level 'INFO' -Component 'Updates' -Message "Using cached data (age: $([math]::Round($age.TotalMinutes, 1)) minutes)"
                    Write-Information "ℹ️  Using cached updates data (scanned $([math]::Round($age.TotalMinutes, 1)) minutes ago)" -InformationAction Continue
                    Complete-PerformanceTracking -PerformanceContext $perf -Success $true
                    return $cachedData
                }
            }
        }
        
        Write-Information "🔍 Scanning Windows Update status..." -InformationAction Continue
        
        # Initialize inventory structure
        $inventory = @{
            metadata         = @{
                scanDate      = (Get-Date).ToString('o')
                computerName  = $env:COMPUTERNAME
                scanDuration  = 0
                moduleVersion = '3.0.0'
            }
            
            availableUpdates = @()
            pendingUpdates   = @()
            updateHistory    = @()
            
            serviceStatus    = @{
                windowsUpdate      = $null
                updateOrchestrator = $null
                bits               = $null
                cryptographic      = $null
            }
            
            configuration    = @{
                wsusServer              = $null
                automaticUpdatesEnabled = $null
                updateSource            = 'Unknown'
                lastCheckTime           = $null
            }
            
            statistics       = @{
                totalAvailable    = 0
                criticalAvailable = 0
                securityAvailable = 0
                totalPending      = 0
                rebootRequired    = $false
                lastInstallDate   = $null
                installedCount    = 0
                failedCount       = 0
            }
        }
        
        # Step 1: Check Windows Update services
        Write-DetailedLog -Level 'INFO' -Component 'Updates' -Message 'Checking Windows Update service status'
        $inventory.serviceStatus = Get-UpdateServiceStatus
        
        # Step 2: Check Windows Update configuration
        Write-DetailedLog -Level 'INFO' -Component 'Updates' -Message 'Reading Windows Update configuration'
        $inventory.configuration = Get-UpdateConfiguration
        
        # Step 3: Scan for available updates
        Write-DetailedLog -Level 'INFO' -Component 'Updates' -Message 'Scanning for available updates'
        Write-Information "  📦 Checking for available updates..." -InformationAction Continue
        
        $availableUpdates = Get-AvailableWindowsUpdate
        $inventory.availableUpdates = $availableUpdates
        $inventory.statistics.totalAvailable = $availableUpdates.Count
        
        # Categorize by importance
        $inventory.statistics.criticalAvailable = ($availableUpdates | Where-Object { $_.MsrcSeverity -eq 'Critical' }).Count
        $inventory.statistics.securityAvailable = ($availableUpdates | Where-Object { $_.Categories -contains 'Security' }).Count
        
        Write-Information "    Found $($availableUpdates.Count) available updates" -InformationAction Continue
        
        # Step 4: Check for pending updates
        Write-DetailedLog -Level 'INFO' -Component 'Updates' -Message 'Checking for pending updates'
        $pendingUpdates = Get-PendingWindowsUpdate
        $inventory.pendingUpdates = $pendingUpdates
        $inventory.statistics.totalPending = $pendingUpdates.Count
        
        # Step 5: Check reboot requirement
        Write-DetailedLog -Level 'INFO' -Component 'Updates' -Message 'Checking reboot requirement'
        $inventory.statistics.rebootRequired = Test-RebootRequired
        
        # Step 6: Get update history
        Write-DetailedLog -Level 'INFO' -Component 'Updates' -Message 'Reading update history'
        Write-Information "  📜 Reading update history..." -InformationAction Continue
        
        $updateHistory = Get-WindowsUpdateHistory -MaxRecords 50
        $inventory.updateHistory = $updateHistory
        
        # Calculate history statistics
        $installedUpdates = $updateHistory | Where-Object { $_.Status -eq 'Installed' }
        $failedUpdates = $updateHistory | Where-Object { $_.Status -eq 'Failed' }
        
        $inventory.statistics.installedCount = $installedUpdates.Count
        $inventory.statistics.failedCount = $failedUpdates.Count
        
        if ($installedUpdates.Count -gt 0) {
            $latestInstall = ($installedUpdates | Sort-Object Date -Descending | Select-Object -First 1).Date
            $inventory.statistics.lastInstallDate = $latestInstall
        }
        
        # Update scan duration
        $inventory.metadata.scanDuration = $perf.StartTime ? ((Get-Date) - $perf.StartTime).TotalSeconds : 0
        
        # Save inventory
        Write-DetailedLog -Level 'INFO' -Component 'Updates' -Message 'Saving updates inventory'
        Save-InventoryFile -Category 'Updates' -Data $inventory
        
        # Display summary
        Write-Information "`n  📊 Updates Inventory Summary:" -InformationAction Continue
        Write-Information "    Available Updates: $($inventory.statistics.totalAvailable) (Critical: $($inventory.statistics.criticalAvailable), Security: $($inventory.statistics.securityAvailable))" -InformationAction Continue
        Write-Information "    Pending Updates: $($inventory.statistics.totalPending)" -InformationAction Continue
        Write-Information "    Reboot Required: $(if ($inventory.statistics.rebootRequired) { 'Yes' } else { 'No' })" -InformationAction Continue
        Write-Information "    Update History: $($inventory.statistics.installedCount) installed, $($inventory.statistics.failedCount) failed" -InformationAction Continue
        Write-Information "" -InformationAction Continue
        
        Write-DetailedLog -Level 'SUCCESS' -Component 'Updates' -Message "Updates inventory scan completed: $($inventory.statistics.totalAvailable) available updates"
        
        Complete-PerformanceTracking -PerformanceContext $perf -Success $true -ResultData @{
            TotalAvailable    = $inventory.statistics.totalAvailable
            CriticalAvailable = $inventory.statistics.criticalAvailable
            RebootRequired    = $inventory.statistics.rebootRequired
        }
        
        return $inventory
    }
    catch {
        Write-DetailedLog -Level 'ERROR' -Component 'Updates' -Message "Updates inventory scan failed: $_" -Exception $_
        Write-Information "`n❌ Updates inventory scan failed: $_" -InformationAction Continue
        Complete-PerformanceTracking -PerformanceContext $perf -Success $false
        return $null
    }
}

<#
.SYNOPSIS
    Gets Windows Update service status.

.DESCRIPTION
    Checks status of critical Windows Update services.

.OUTPUTS
    Hashtable with service status information.
#>
function Get-UpdateServiceStatus {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()
    
    $services = @{
        windowsUpdate      = 'wuauserv'
        updateOrchestrator = 'UsoSvc'
        bits               = 'BITS'
        cryptographic      = 'CryptSvc'
    }
    
    $status = @{}
    
    foreach ($key in $services.Keys) {
        try {
            $service = Get-Service -Name $services[$key] -ErrorAction Stop
            $status[$key] = @{
                Name        = $service.Name
                DisplayName = $service.DisplayName
                Status      = $service.Status.ToString()
                StartType   = $service.StartType.ToString()
            }
        }
        catch {
            $status[$key] = @{
                Name   = $services[$key]
                Status = 'NotFound'
                Error  = $_.Exception.Message
            }
        }
    }
    
    return $status
}

<#
.SYNOPSIS
    Gets Windows Update configuration.

.DESCRIPTION
    Reads Windows Update settings from registry and configuration.

.OUTPUTS
    Hashtable with configuration information.
#>
function Get-UpdateConfiguration {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()
    
    $config = @{
        wsusServer              = $null
        automaticUpdatesEnabled = $null
        updateSource            = 'Unknown'
        lastCheckTime           = $null
    }
    
    try {
        # Check WSUS configuration
        $wsusPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
        if (Test-Path $wsusPath) {
            $wsusServer = (Get-ItemProperty -Path $wsusPath -Name 'WUServer' -ErrorAction SilentlyContinue).WUServer
            if ($wsusServer) {
                $config.wsusServer = $wsusServer
                $config.updateSource = 'WSUS'
            }
        }
        
        # Check automatic updates setting
        $auPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'
        if (Test-Path $auPath) {
            $noAutoUpdate = (Get-ItemProperty -Path $auPath -Name 'NoAutoUpdate' -ErrorAction SilentlyContinue).NoAutoUpdate
            $config.automaticUpdatesEnabled = ($noAutoUpdate -ne 1)
        }
        
        # If not WSUS, assume Windows Update
        if (-not $config.wsusServer) {
            $config.updateSource = 'WindowsUpdate'
        }
        
        # Get last check time
        $lastCheckPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\Results\Detect'
        if (Test-Path $lastCheckPath) {
            $lastCheck = (Get-ItemProperty -Path $lastCheckPath -Name 'LastSuccessTime' -ErrorAction SilentlyContinue).LastSuccessTime
            if ($lastCheck) {
                $config.lastCheckTime = $lastCheck
            }
        }
    }
    catch {
        Write-Verbose "Error reading update configuration: $_"
    }
    
    return $config
}

<#
.SYNOPSIS
    Gets available Windows updates.

.DESCRIPTION
    Queries Windows Update for available updates using PSWindowsUpdate module or COM API.

.OUTPUTS
    Array of available updates.
#>
function Get-AvailableWindowsUpdate {
    [CmdletBinding()]
    [OutputType([array])]
    param()
    
    $updates = @()
    
    try {
        # Try PSWindowsUpdate module first
        if (Get-Module -ListAvailable -Name PSWindowsUpdate) {
            Import-Module PSWindowsUpdate -ErrorAction Stop
            
            $wuUpdates = Get-WindowsUpdate -MicrosoftUpdate -ErrorAction Stop
            
            foreach ($update in $wuUpdates) {
                $updates += @{
                    Title        = $update.Title
                    KB           = $update.KB
                    Size         = $update.Size
                    Categories   = $update.Categories -join ', '
                    MsrcSeverity = $update.MsrcSeverity
                    IsDownloaded = $update.IsDownloaded
                    IsInstalled  = $update.IsInstalled
                }
            }
        }
        else {
            # Fallback to COM API
            $updateSession = New-Object -ComObject Microsoft.Update.Session
            $updateSearcher = $updateSession.CreateUpdateSearcher()
            
            $searchResult = $updateSearcher.Search("IsInstalled=0 and Type='Software'")
            
            foreach ($update in $searchResult.Updates) {
                $kb = 'N/A'
                if ($update.KBArticleIDs.Count -gt 0) {
                    $kb = "KB$($update.KBArticleIDs[0])"
                }
                
                $updates += @{
                    Title        = $update.Title
                    KB           = $kb
                    Size         = $update.MaxDownloadSize
                    Categories   = ($update.Categories | ForEach-Object { $_.Name }) -join ', '
                    MsrcSeverity = $update.MsrcSeverity
                    IsDownloaded = $update.IsDownloaded
                    IsInstalled  = $false
                }
            }
        }
    }
    catch {
        Write-Verbose "Error getting available updates: $_"
    }
    
    return $updates
}

<#
.SYNOPSIS
    Gets pending Windows updates.

.DESCRIPTION
    Checks for updates that are downloaded but not yet installed.

.OUTPUTS
    Array of pending updates.
#>
function Get-PendingWindowsUpdate {
    [CmdletBinding()]
    [OutputType([array])]
    param()
    
    $pendingUpdates = @()
    
    try {
        $updateSession = New-Object -ComObject Microsoft.Update.Session
        $updateSearcher = $updateSession.CreateUpdateSearcher()
        
        $searchResult = $updateSearcher.Search("IsInstalled=0 and IsDownloaded=1")
        
        foreach ($update in $searchResult.Updates) {
            $kb = 'N/A'
            if ($update.KBArticleIDs.Count -gt 0) {
                $kb = "KB$($update.KBArticleIDs[0])"
            }
            
            $pendingUpdates += @{
                Title      = $update.Title
                KB         = $kb
                Size       = $update.MaxDownloadSize
                Categories = ($update.Categories | ForEach-Object { $_.Name }) -join ', '
            }
        }
    }
    catch {
        Write-Verbose "Error getting pending updates: $_"
    }
    
    return $pendingUpdates
}

<#
.SYNOPSIS
    Tests if system reboot is required.

.DESCRIPTION
    Checks multiple registry locations for pending reboot indicators.

.OUTPUTS
    Boolean indicating if reboot is required.
#>
function Test-RebootRequired {
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    
    $rebootRequired = $false
    
    # Check Component Based Servicing
    $cbsPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
    if (Test-Path $cbsPath) {
        $rebootRequired = $true
    }
    
    # Check Windows Update
    $wuPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
    if (Test-Path $wuPath) {
        $rebootRequired = $true
    }
    
    # Check pending file rename operations
    $pendingFileRenameOperations = Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name 'PendingFileRenameOperations' -ErrorAction SilentlyContinue
    if ($pendingFileRenameOperations) {
        $rebootRequired = $true
    }
    
    return $rebootRequired
}

<#
.SYNOPSIS
    Gets Windows Update history.

.DESCRIPTION
    Retrieves recent update installation history.

.PARAMETER MaxRecords
    Maximum number of history records to retrieve (default: 50).

.OUTPUTS
    Array of update history records.
#>
function Get-WindowsUpdateHistory {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $false)]
        [int]$MaxRecords = 50
    )
    
    $history = @()
    
    try {
        $updateSession = New-Object -ComObject Microsoft.Update.Session
        $updateSearcher = $updateSession.CreateUpdateSearcher()
        
        $historyCount = $updateSearcher.GetTotalHistoryCount()
        $recordsToGet = [Math]::Min($historyCount, $MaxRecords)
        
        $updateHistory = $updateSearcher.QueryHistory(0, $recordsToGet)
        
        foreach ($entry in $updateHistory) {
            $status = switch ($entry.ResultCode) {
                2 { 'Installed' }
                3 { 'InstalledWithErrors' }
                4 { 'Failed' }
                5 { 'Aborted' }
                default { 'Unknown' }
            }
            
            $history += @{
                Title  = $entry.Title
                Date   = $entry.Date
                Status = $status
                KB     = if ($entry.Title -match 'KB(\d+)') { "KB$($matches[1])" } else { 'N/A' }
            }
        }
    }
    catch {
        Write-Verbose "Error getting update history: $_"
    }
    
    return $history
}

# Export public functions
Export-ModuleMember -Function @(
    'Get-UpdatesInventory'
)
