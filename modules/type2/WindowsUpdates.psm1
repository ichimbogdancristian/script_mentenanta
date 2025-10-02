#Requires -Version 7.0

<#
.SYNOPSIS
    Windows Updates Module - Type 2 (System Modification)

.DESCRIPTION
    Comprehensive Windows Update management with automated detection, installation,
    and reboot suppression. Supports both PSWindowsUpdate module and native Windows Update APIs.

.NOTES
    Module Type: Type 2 (System Modification)
    Dependencies: PSWindowsUpdate module (optional), Administrator privileges
    Requires: Administrator privileges, internet connectivity
    Author: Windows Maintenance Automation Project
    Version: 1.0.0
#>

using namespace System.Collections.Generic

#region Privilege Validation
function Test-IsAdministrator {
    <#
    .SYNOPSIS
        Tests if the current PowerShell session is running with Administrator privileges
    .DESCRIPTION  
        Checks Windows identity and role to determine if current session has admin privileges.
        Required for Type2 modules that modify system settings, registry, or services.
    .RETURNS
        Boolean - True if running as administrator, False otherwise
    #>
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        Write-Warning "Failed to check administrator privileges: $_"
        return $false
    }
}

function Assert-AdministratorPrivileges {
    <#
    .SYNOPSIS
        Validates administrator privileges and throws descriptive error if not elevated
    .DESCRIPTION
        Checks for admin privileges and provides clear error message if missing.
        Should be called at the beginning of functions requiring elevation.
    .PARAMETER OperationName
        Name of the operation requiring admin privileges (for error message)
    #>
    param(
        [Parameter(Mandatory)]
        [string]$OperationName
    )
    
    if (-not (Test-IsAdministrator)) {
        $errorMessage = @"
$OperationName requires Administrator privileges.

SOLUTION:
1. Close this PowerShell session
2. Right-click script.bat and select "Run as administrator" 
3. Accept the UAC prompt when it appears
4. Re-run the maintenance script

The script launcher (script.bat) handles privilege elevation automatically,
but the PowerShell session must maintain elevated context.
"@
        throw $errorMessage
    }
}
#endregion


#region Public Functions

<#
.SYNOPSIS
    Performs comprehensive Windows Update check and installation
    
.DESCRIPTION
    Detects, filters, and installs available Windows Updates with intelligent
    categorization, size validation, and comprehensive reboot suppression.
    
.PARAMETER IncludeOptional
    Include optional updates in the installation
    
.PARAMETER IncludeDrivers
    Include driver updates in the installation
    
.PARAMETER ExcludePreviews
    Exclude preview and insider updates (default: true)
    
.PARAMETER MaxDownloadSizeMB
    Maximum total download size in MB (default: 2048MB)
    
.PARAMETER DryRun
    Scan for updates without installing them
    
.PARAMETER SuppressReboot
    Suppress automatic reboots after installation (default: true)
    
.EXAMPLE
    $results = Install-WindowsUpdates -DryRun
    
.EXAMPLE
    $results = Install-WindowsUpdates -IncludeDrivers -MaxDownloadSizeMB 1024
#>
function Install-WindowsUpdates {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact='High')]
    param(
        [Parameter()]
        [switch]$IncludeOptional,
        
        [Parameter()]
        [switch]$IncludeDrivers,
        
        [Parameter()]
        [switch]$ExcludePreviews = $true,
        
        [Parameter()]
        [ValidateRange(100, 10240)]
        [int]$MaxDownloadSizeMB = 2048,
        
        [Parameter()]
        [switch]$DryRun,
        
        [Parameter()]
        [switch]$SuppressReboot = $true
    )
    
    Write-Host "🔄 Starting Windows Updates check and installation..." -ForegroundColor Cyan
    $startTime = Get-Date
    
    # Initialize results tracking
    $results = @{
        UpdatesFound = 0
        UpdatesInstalled = 0
        UpdatesFailed = 0
        TotalSizeMB = 0
        RebootRequired = $false
        Details = [List[PSCustomObject]]::new()
        Method = 'Unknown'
        DryRun = $DryRun.IsPresent
    }
    
    try {
        # Validate administrator privileges before attempting Windows Updates
        Assert-AdministratorPrivileges -OperationName "Windows Updates"
        
        # Try PSWindowsUpdate module first with privilege validation
        if (Test-PSWindowsUpdateAvailable) {
            Write-Host "  📦 Using PSWindowsUpdate module..." -ForegroundColor Gray
            try {
                $results = Install-UpdatesViaPSWindowsUpdate @PSBoundParameters
            }
            catch {
                if ($_.Exception.Message -like "*elevated*PowerShell*console*") {
                    Write-Host "  ⚠️  PSWindowsUpdate requires elevated console context - using fallback method" -ForegroundColor Yellow
                    $results = Install-UpdatesViaNativeAPI @PSBoundParameters
                } else {
                    throw
                }
            }
        }
        # Fallback to native Windows Update API
        elseif (Test-NativeWindowsUpdateAvailable) {
            Write-Host "  🪟 Using native Windows Update API..." -ForegroundColor Gray
            $results = Install-UpdatesViaNativeAPI @PSBoundParameters
        }
        # Final fallback to basic checks
        else {
            Write-Host "  ⚠️  Limited Windows Update capability available" -ForegroundColor Yellow
            $results = Get-WindowsUpdateBasicStatus
        }
        
        $duration = ((Get-Date) - $startTime).TotalSeconds
        
        # Summary output
        if ($results.UpdatesFound -eq 0) {
            Write-Host "  ✅ No updates available - system is up to date" -ForegroundColor Green
        }
        elseif ($DryRun) {
            Write-Host "  📋 Found $($results.UpdatesFound) available updates ($($results.TotalSizeMB) MB total)" -ForegroundColor Blue
        }
        else {
            $statusIcon = if ($results.UpdatesFailed -eq 0) { "✅" } else { "⚠️" }
            Write-Host "  $statusIcon Updates completed in $([math]::Round($duration, 2))s" -ForegroundColor Green
            Write-Host "    📊 Found: $($results.UpdatesFound), Installed: $($results.UpdatesInstalled), Failed: $($results.UpdatesFailed)" -ForegroundColor Gray
            
            if ($results.RebootRequired) {
                Write-Host "    🔄 System restart required to complete installation" -ForegroundColor Yellow
            }
        }
        
        return $results
    }
    catch {
        Write-Error "Windows Updates operation failed: $_"
        $results.UpdatesFailed = $results.UpdatesFound
        return $results
    }
}

<#
.SYNOPSIS
    Gets Windows Update status and pending reboot information
    
.DESCRIPTION
    Checks for pending updates, installation status, and reboot requirements
    without performing any installations.
    
.EXAMPLE
    $status = Get-WindowsUpdateStatus
#>
function Get-WindowsUpdateStatus {
    [CmdletBinding()]
    param()
    
    Write-Host "📊 Checking Windows Update status..." -ForegroundColor Cyan
    
    $status = @{
        UpdatesAvailable = 0
        PendingReboot = $false
        RebootReason = @()
        LastUpdateCheck = $null
        LastInstallDate = $null
        AutoUpdateEnabled = $false
    }
    
    try {
        # Check for pending reboot from Windows Updates
        $status.PendingReboot = Test-PendingReboot
        if ($status.PendingReboot) {
            $status.RebootReason += "Windows Updates"
        }
        
        # Get Windows Update settings
        $auSettings = Get-WindowsUpdateSettings
        $status.AutoUpdateEnabled = $auSettings.AutoUpdateEnabled
        $status.LastUpdateCheck = $auSettings.LastUpdateCheck
        
        # Try to get available updates count
        if (Test-PSWindowsUpdateAvailable) {
            $availableUpdates = Get-WindowsUpdate -MicrosoftUpdate -ErrorAction SilentlyContinue
            $status.UpdatesAvailable = ($availableUpdates | Measure-Object).Count
        }
        
        Write-Host "  📋 Status: $($status.UpdatesAvailable) updates available" -ForegroundColor Gray
        Write-Host "  🔄 Pending reboot: $($status.PendingReboot)" -ForegroundColor Gray
        Write-Host "  ⚙️ Auto-update: $($status.AutoUpdateEnabled)" -ForegroundColor Gray
        
        return $status
    }
    catch {
        Write-Warning "Failed to get complete Windows Update status: $_"
        return $status
    }
}

#endregion

#region PSWindowsUpdate Implementation

<#
.SYNOPSIS
    Installs updates using PSWindowsUpdate module
#>
function Install-UpdatesViaPSWindowsUpdate {
    [CmdletBinding()]
    param(
        [switch]$IncludeOptional,
        [switch]$IncludeDrivers,
        [switch]$ExcludePreviews = $true,
        [int]$MaxDownloadSizeMB = 2048,
        [switch]$DryRun,
        [switch]$SuppressReboot = $true
    )
    
    $results = @{
        UpdatesFound = 0
        UpdatesInstalled = 0
        UpdatesFailed = 0
        TotalSizeMB = 0
        RebootRequired = $false
        Details = [List[PSCustomObject]]::new()
        Method = 'PSWindowsUpdate'
        DryRun = $DryRun.IsPresent
    }
    
    try {
        # Import the module
        Import-Module PSWindowsUpdate -Force -ErrorAction Stop
        
        # Configure environment for non-interactive operation
        if ($SuppressReboot) {
            $env:PSWINDOWSUPDATE_REBOOT = "Never"
            $env:SUPPRESSPROMPTS = "True"
            $env:SUPPRESS_REBOOT_PROMPT = "True"
        }
        
        # Get available updates
        Write-Host "    🔍 Scanning for available updates..." -ForegroundColor Gray
        
        $scanParams = @{
            MicrosoftUpdate = $true
            ErrorAction = 'SilentlyContinue'
        }
        
        $availableUpdates = Get-WindowsUpdate @scanParams
        
        if (-not $availableUpdates) {
            Write-Host "    ✅ No updates found" -ForegroundColor Green
            return $results
        }
        
        # Filter updates based on parameters
        $filteredUpdates = $availableUpdates | Where-Object {
            $include = $true
            
            # Exclude previews if specified
            if ($ExcludePreviews -and ($_.Title -like "*Preview*" -or $_.Title -like "*Insider*")) {
                $include = $false
            }
            
            # Include only drivers if specified
            if (-not $IncludeDrivers -and $_.Categories -contains "Drivers") {
                $include = $false
            }
            
            # Exclude optional if not specified
            if (-not $IncludeOptional -and $_.Categories -contains "Optional") {
                $include = $false
            }
            
            return $include
        }
        
        $results.UpdatesFound = ($filteredUpdates | Measure-Object).Count
        $results.TotalSizeMB = [math]::Round(($filteredUpdates | Measure-Object -Property Size -Sum).Sum / 1MB, 2)
        
        # Check size limit
        if ($results.TotalSizeMB -gt $MaxDownloadSizeMB) {
            Write-Warning "Total download size ($($results.TotalSizeMB) MB) exceeds limit ($MaxDownloadSizeMB MB)"
            
            # Sort by importance and select updates within limit
            $sortedUpdates = $filteredUpdates | Sort-Object @{
                Expression = { 
                    if ($_.Categories -contains "Critical Updates") { 1 }
                    elseif ($_.Categories -contains "Security Updates") { 2 }
                    elseif ($_.Categories -contains "Important Updates") { 3 }
                    else { 4 }
                }
            }
            
            $selectedUpdates = @()
            $currentSize = 0
            
            foreach ($update in $sortedUpdates) {
                $updateSizeMB = [math]::Round($update.Size / 1MB, 2)
                if (($currentSize + $updateSizeMB) -le $MaxDownloadSizeMB) {
                    $selectedUpdates += $update
                    $currentSize += $updateSizeMB
                }
            }
            
            $filteredUpdates = $selectedUpdates
            $results.UpdatesFound = $filteredUpdates.Count
            $results.TotalSizeMB = $currentSize
        }
        
        if ($DryRun) {
            Write-Host "    📋 [DRY RUN] Would install $($results.UpdatesFound) updates ($($results.TotalSizeMB) MB)" -ForegroundColor DarkYellow
            
            foreach ($update in $filteredUpdates) {
                $results.Details.Add([PSCustomObject]@{
                    Title = $update.Title
                    SizeMB = [math]::Round($update.Size / 1MB, 2)
                    Category = $update.Categories -join ', '
                    Status = 'Simulated'
                })
            }
            
            $results.UpdatesInstalled = $results.UpdatesFound
            return $results
        }
        
        # Install updates
        if ($filteredUpdates.Count -gt 0) {
            Write-Host "    📥 Installing $($filteredUpdates.Count) updates ($($results.TotalSizeMB) MB)..." -ForegroundColor Blue
            
            $installParams = @{
                MicrosoftUpdate = $true
                AcceptAll = $true
                AutoReboot = -not $SuppressReboot
                Confirm = $false
                IgnoreReboot = $SuppressReboot
                Silent = $true
                ForceInstall = $true
                ErrorAction = 'SilentlyContinue'
            }
            
            try {
                $installResults = Install-WindowsUpdate @installParams
                
                foreach ($result in $installResults) {
                    $status = if ($result.Result -eq 'Installed') { 'Installed' } else { 'Failed' }
                    
                    $results.Details.Add([PSCustomObject]@{
                        Title = $result.Title
                        SizeMB = [math]::Round($result.Size / 1MB, 2)
                        Category = $result.Categories -join ', '
                        Status = $status
                        Result = $result.Result
                    })
                    
                    if ($status -eq 'Installed') {
                        $results.UpdatesInstalled++
                    } else {
                        $results.UpdatesFailed++
                    }
                }
                
                # Check if reboot is required
                $results.RebootRequired = Test-PendingReboot
                
            }
            catch {
                Write-Warning "Installation encountered errors: $_"
                $results.UpdatesFailed = $results.UpdatesFound
            }
        }
        
        return $results
    }
    catch {
        Write-Warning "PSWindowsUpdate operation failed: $_"
        throw
    }
}

#endregion

#region Native Windows Update API Implementation

<#
.SYNOPSIS
    Installs updates using native Windows Update API
#>
function Install-UpdatesViaNativeAPI {
    [CmdletBinding()]
    param(
        [switch]$IncludeOptional,
        [switch]$IncludeDrivers,
        [switch]$ExcludePreviews = $true,
        [int]$MaxDownloadSizeMB = 2048,
        [switch]$DryRun,
        [switch]$SuppressReboot = $true
    )
    
    $results = @{
        UpdatesFound = 0
        UpdatesInstalled = 0
        UpdatesFailed = 0
        TotalSizeMB = 0
        RebootRequired = $false
        Details = [List[PSCustomObject]]::new()
        Method = 'Native API'
        DryRun = $DryRun.IsPresent
    }
    
    try {
        Write-Host "    🔍 Using Windows Update COM API..." -ForegroundColor Gray
        
        # Create Windows Update session
        $updateSession = New-Object -ComObject Microsoft.Update.Session
        $updateSearcher = $updateSession.CreateUpdateSearcher()
        
        # Search for updates
        Write-Host "    🔎 Searching for available updates..." -ForegroundColor Gray
        $searchResult = $updateSearcher.Search("IsInstalled=0 and Type='Software'")
        
        $availableUpdates = @($searchResult.Updates)
        $results.UpdatesFound = $availableUpdates.Count
        
        if ($results.UpdatesFound -eq 0) {
            Write-Host "    ✅ No updates found via native API" -ForegroundColor Green
            return $results
        }
        
        # Calculate total size
        $totalSize = ($availableUpdates | ForEach-Object { $_.MaxDownloadSize } | Measure-Object -Sum).Sum
        $results.TotalSizeMB = [math]::Round($totalSize / 1MB, 2)
        
        if ($DryRun) {
            Write-Host "    📋 [DRY RUN] Found $($results.UpdatesFound) updates ($($results.TotalSizeMB) MB)" -ForegroundColor DarkYellow
            
            foreach ($update in $availableUpdates) {
                $results.Details.Add([PSCustomObject]@{
                    Title = $update.Title
                    SizeMB = [math]::Round($update.MaxDownloadSize / 1MB, 2)
                    Category = 'Windows Update'
                    Status = 'Available'
                })
            }
            
            return $results
        }
        
        # Download and install updates
        Write-Host "    📥 Downloading and installing updates..." -ForegroundColor Blue
        
        $updatesToInstall = New-Object -ComObject Microsoft.Update.UpdateColl
        foreach ($update in $availableUpdates) {
            $updatesToInstall.Add($update) | Out-Null
        }
        
        # Download updates
        $downloader = $updateSession.CreateUpdateDownloader()
        $downloader.Updates = $updatesToInstall
        $downloadResult = $downloader.Download()
        
        if ($downloadResult.ResultCode -eq 2) {  # SuccessfullyDownloaded
            # Install updates
            $installer = $updateSession.CreateUpdateInstaller()
            $installer.Updates = $updatesToInstall
            $installResult = $installer.Install()
            
            $results.UpdatesInstalled = $installResult.ResultCode -eq 2 ? $results.UpdatesFound : 0
            $results.UpdatesFailed = $results.UpdatesFound - $results.UpdatesInstalled
            $results.RebootRequired = $installResult.RebootRequired
        }
        else {
            Write-Warning "Failed to download updates"
            $results.UpdatesFailed = $results.UpdatesFound
        }
        
        return $results
    }
    catch {
        Write-Warning "Native Windows Update API failed: $_"
        throw
    }
}

#endregion

#region Helper Functions

<#
.SYNOPSIS
    Tests if PSWindowsUpdate module is available and functional
#>
function Test-PSWindowsUpdateAvailable {
    try {
        $module = Get-Module -ListAvailable -Name PSWindowsUpdate -ErrorAction SilentlyContinue
        if (-not $module) {
            return $false
        }
        
        Import-Module PSWindowsUpdate -Force -ErrorAction SilentlyContinue
        return $null -ne (Get-Command Get-WindowsUpdate -ErrorAction SilentlyContinue)
    }
    catch {
        return $false
    }
}

<#
.SYNOPSIS
    Tests if native Windows Update API is available
#>
function Test-NativeWindowsUpdateAvailable {
    try {
        $updateSession = New-Object -ComObject Microsoft.Update.Session -ErrorAction SilentlyContinue
        return $null -ne $updateSession
    }
    catch {
        return $false
    }
}

<#
.SYNOPSIS
    Tests if a system reboot is pending
#>
function Test-PendingReboot {
    $registryKeys = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending",
        "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\PendingFileRenameOperations"
    )
    
    foreach ($key in $registryKeys) {
        if (Test-Path $key) {
            return $true
        }
    }
    
    return $false
}

<#
.SYNOPSIS
    Gets Windows Update settings and configuration
#>
function Get-WindowsUpdateSettings {
    try {
        $auKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update"
        
        $settings = @{
            AutoUpdateEnabled = $false
            LastUpdateCheck = $null
        }
        
        if (Test-Path $auKey) {
            $auValue = Get-ItemProperty $auKey -Name AUOptions -ErrorAction SilentlyContinue
            $settings.AutoUpdateEnabled = $null -ne $auValue -and $auValue.AUOptions -gt 1
        }
        
        # Try to get last update check time
        try {
            $wuService = New-Object -ComObject Microsoft.Update.ServiceManager
            $settings.LastUpdateCheck = $wuService.Services | 
                Where-Object { $_.Name -eq "Microsoft Update" } | 
                Select-Object -ExpandProperty LastUpdateTime -ErrorAction SilentlyContinue
        }
        catch {
            # Ignore COM errors
        }
        
        return $settings
    }
    catch {
        return @{
            AutoUpdateEnabled = $false
            LastUpdateCheck = $null
        }
    }
}

<#
.SYNOPSIS
    Gets basic Windows Update status without advanced features
#>
function Get-WindowsUpdateBasicStatus {
    return @{
        UpdatesFound = 0
        UpdatesInstalled = 0
        UpdatesFailed = 0
        TotalSizeMB = 0
        RebootRequired = Test-PendingReboot
        Details = @()
        Method = 'Basic Status'
        DryRun = $false
        Message = "Limited Windows Update capability - PSWindowsUpdate module recommended"
    }
}

#endregion

# Export module functions
Export-ModuleMember -Function @(
    'Install-WindowsUpdates',
    'Get-WindowsUpdateStatus'
)
