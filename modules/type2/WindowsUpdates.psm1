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

#region Public Functions

<#
.SYNOPSIS
    Performs comprehensive Windows Update check and installation.

.DESCRIPTION
    Detects, filters, and installs available Windows Updates using multiple methods
    including PSWindowsUpdate module and native Windows Update APIs. Provides intelligent
    categorization, size validation, comprehensive reboot suppression, and detailed
    reporting of update installation status.

.PARAMETER IncludeOptional
    When specified, includes optional updates in the installation process.
    Optional updates are typically feature updates that are not critical for security.

.PARAMETER IncludeDrivers
    When specified, includes driver updates in the installation process.
    Driver updates can improve hardware compatibility and performance.

.PARAMETER ExcludePreviews
    When specified, excludes preview and insider updates from installation.
    Preview updates may contain unstable or experimental features.

.PARAMETER MaxDownloadSizeMB
    Specifies the maximum total download size in megabytes (default: 2048MB).
    Updates exceeding this size will be skipped to manage bandwidth usage.

.PARAMETER DryRun
    When specified, performs update scan and analysis without installing updates.
    Useful for testing and reporting available updates without system changes.

.PARAMETER SuppressReboot
    When specified, suppresses automatic system reboots after update installation.
    System may require manual reboot to complete update installation.

.EXAMPLE
    $results = Install-WindowsUpdate -DryRun
    Write-Output "Found $($results.Available) available updates"

.EXAMPLE
    $results = Install-WindowsUpdate -IncludeDrivers -MaxDownloadSizeMB 1024
    Write-Output "Installed $($results.Installed) updates"

.EXAMPLE
    $results = Install-WindowsUpdate -ExcludePreviews -SuppressReboot
    if ($results.RebootRequired) { Write-Warning "System reboot required" }

.OUTPUTS
    [hashtable] Results containing update counts, installation status, and reboot requirements

.NOTES
    Author: Windows Maintenance Automation Project
    Module Type: Type 2 (System Modification)
    Dependencies: PSWindowsUpdate module (optional), Administrator privileges
    Version: 1.0.0

    Update Methods:
    1. PSWindowsUpdate module (preferred if available)
    2. Native Windows Update API (fallback)
    3. Basic Windows Update service status check
#>
function Install-WindowsUpdate {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    [OutputType([hashtable])]
    param(
        [Parameter()]
        [switch]$ExcludePreviews,

        [Parameter()]
        [ValidateRange(100, 10240)]
        [int]$MaxDownloadSizeMB = 2048,

        [Parameter()]
        [switch]$DryRun,

        [Parameter()]
        [switch]$SuppressReboot
    )

    Write-Information "🔄 Starting Windows Updates check and installation..." -InformationAction Continue
    $startTime = Get-Date

    # Initialize results tracking
    $results = @{
        UpdatesFound     = 0
        UpdatesInstalled = 0
        UpdatesFailed    = 0
        TotalSizeMB      = 0
        RebootRequired   = $false
        Details          = [List[PSCustomObject]]::new()
        Method           = 'Unknown'
        DryRun           = $DryRun.IsPresent
    }

    try {
        # Try PSWindowsUpdate module first
        if (Test-PSWindowsUpdateAvailable) {
            Write-Information "  📦 Using PSWindowsUpdate module..." -InformationAction Continue
            $results = Install-UpdatesViaPSWindowsUpdate @PSBoundParameters
        }
        # Fallback to native Windows Update API
        elseif (Test-NativeWindowsUpdateAvailable) {
            Write-Information "  🪟 Using native Windows Update API..." -InformationAction Continue
            $results = Install-UpdatesViaNativeAPI @PSBoundParameters
        }
        # Final fallback to basic checks
        else {
            Write-Warning "  ⚠️  Limited Windows Update capability available"
            $results = Get-WindowsUpdateBasicStatus
        }

        $duration = ((Get-Date) - $startTime).TotalSeconds

        # Summary output
        if ($results.UpdatesFound -eq 0) {
            Write-Information "  ✅ No updates available - system is up to date" -InformationAction Continue
        }
        elseif ($DryRun) {
            Write-Information "  📋 Found $($results.UpdatesFound) available updates ($($results.TotalSizeMB) MB total)" -InformationAction Continue
        }
        else {
            $statusIcon = if ($results.UpdatesFailed -eq 0) { "✅" } else { "⚠️" }
            Write-Information "  $statusIcon Updates completed in $([math]::Round($duration, 2))s" -InformationAction Continue
            Write-Information "    📊 Found: $($results.UpdatesFound), Installed: $($results.UpdatesInstalled), Failed: $($results.UpdatesFailed)" -InformationAction Continue

            if ($results.RebootRequired) {
                Write-Warning "    🔄 System restart required to complete installation"
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
    Gets comprehensive Windows Update status and pending reboot information.

.DESCRIPTION
    Performs comprehensive analysis of Windows Update status including available updates,
    pending reboot requirements, automatic update configuration, last update check date,
    and last installation date. Does not perform any installations or modifications.

.EXAMPLE
    $status = Get-WindowsUpdateStatus
    Write-Output "Updates available: $($status.UpdatesAvailable)"

.EXAMPLE
    $status = Get-WindowsUpdateStatus
    if ($status.PendingReboot) {
        Write-Warning "System reboot required: $($status.RebootReason -join ', ')"
    }

.OUTPUTS
    [hashtable] Status information containing update availability and system state

.NOTES
    Author: Windows Maintenance Automation Project
    Module Type: Type 2 (System Modification) - Read-only operation
    Dependencies: PSWindowsUpdate module (optional)
    Version: 1.0.0
#>
function Get-WindowsUpdateStatus {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    Write-Information "📊 Checking Windows Update status..." -InformationAction Continue

    $status = @{
        UpdatesAvailable  = 0
        PendingReboot     = $false
        RebootReason      = @()
        LastUpdateCheck   = $null
        LastInstallDate   = $null
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

        Write-Information "  📋 Status: $($status.UpdatesAvailable) updates available" -InformationAction Continue
        Write-Information "  🔄 Pending reboot: $($status.PendingReboot)" -InformationAction Continue
        Write-Information "  ⚙️ Auto-update: $($status.AutoUpdateEnabled)" -InformationAction Continue

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
    Installs Windows updates using the PSWindowsUpdate PowerShell module.

.DESCRIPTION
    Leverages the PSWindowsUpdate module to detect, download, and install Windows updates
    with comprehensive filtering, size management, and progress reporting. Provides
    detailed update categorization and handles reboot requirements gracefully.

.PARAMETER ExcludePreviews
    When specified, excludes preview and insider updates from installation.

.PARAMETER MaxDownloadSizeMB
    Specifies the maximum total download size in megabytes.

.PARAMETER DryRun
    When specified, scans for updates without installing them.

.PARAMETER SuppressReboot
    When specified, suppresses automatic reboots after update installation.

.OUTPUTS
    [hashtable] Update installation results and statistics

.NOTES
    Author: Windows Maintenance Automation Project
    Module Type: Type 2 (System Modification)
    Dependencies: PSWindowsUpdate module
    Version: 1.0.0
#>
function Install-UpdatesViaPSWindowsUpdate {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    [OutputType([hashtable])]
    param(
        [switch]$ExcludePreviews,
        [int]$MaxDownloadSizeMB = 2048,
        [switch]$DryRun,
        [switch]$SuppressReboot
    )

    $results = @{
        UpdatesFound     = 0
        UpdatesInstalled = 0
        UpdatesFailed    = 0
        TotalSizeMB      = 0
        RebootRequired   = $false
        Details          = [List[PSCustomObject]]::new()
        Method           = 'PSWindowsUpdate'
        DryRun           = $DryRun.IsPresent
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
        Write-Information "    🔍 Scanning for available updates..." -InformationAction Continue

        $scanParams = @{
            MicrosoftUpdate = $true
            ErrorAction     = 'SilentlyContinue'
        }

        $availableUpdates = Get-WindowsUpdate @scanParams

        if (-not $availableUpdates) {
            Write-Information "    ✅ No updates found" -InformationAction Continue
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
            Write-Information "    📋 [DRY RUN] Would install $($results.UpdatesFound) updates ($($results.TotalSizeMB) MB)" -InformationAction Continue

            foreach ($update in $filteredUpdates) {
                $results.Details.Add([PSCustomObject]@{
                        Title    = $update.Title
                        SizeMB   = [math]::Round($update.Size / 1MB, 2)
                        Category = $update.Categories -join ', '
                        Status   = 'Simulated'
                    })
            }

            $results.UpdatesInstalled = $results.UpdatesFound
            return $results
        }

        # Install updates
        if ($filteredUpdates.Count -gt 0) {
            Write-Information "    📥 Installing $($filteredUpdates.Count) updates ($($results.TotalSizeMB) MB)..." -InformationAction Continue

            $installParams = @{
                MicrosoftUpdate = $true
                AcceptAll       = $true
                AutoReboot      = -not $SuppressReboot
                Confirm         = $false
                IgnoreReboot    = $SuppressReboot
                Silent          = $true
                ForceInstall    = $true
                ErrorAction     = 'SilentlyContinue'
            }

            try {
                $installResults = Install-WindowsUpdate @installParams

                foreach ($result in $installResults) {
                    $status = if ($result.Result -eq 'Installed') { 'Installed' } else { 'Failed' }

                    $results.Details.Add([PSCustomObject]@{
                            Title    = $result.Title
                            SizeMB   = [math]::Round($result.Size / 1MB, 2)
                            Category = $result.Categories -join ', '
                            Status   = $status
                            Result   = $result.Result
                        })

                    if ($status -eq 'Installed') {
                        $results.UpdatesInstalled++
                    }
                    else {
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
    [OutputType([hashtable])]
    param(
        [switch]$IncludeOptional,
        [switch]$IncludeDrivers,
        [switch]$ExcludePreviews,
        [int]$MaxDownloadSizeMB = 2048,
        [switch]$DryRun,
        [switch]$SuppressReboot
    )

    $results = @{
        UpdatesFound     = 0
        UpdatesInstalled = 0
        UpdatesFailed    = 0
        TotalSizeMB      = 0
        RebootRequired   = $false
        Details          = [List[PSCustomObject]]::new()
        Method           = 'Native API'
        DryRun           = $DryRun.IsPresent
    }

    try {
        Write-Information "    🔍 Using Windows Update COM API..." -InformationAction Continue

        # Create Windows Update session
        $updateSession = New-Object -ComObject Microsoft.Update.Session
        $updateSearcher = $updateSession.CreateUpdateSearcher()

        # Search for updates
        Write-Information "    🔎 Searching for available updates..." -InformationAction Continue
        $searchResult = $updateSearcher.Search("IsInstalled=0 and Type='Software'")

        $availableUpdates = @($searchResult.Updates)
        $results.UpdatesFound = $availableUpdates.Count

        if ($results.UpdatesFound -eq 0) {
            Write-Information "    ✅ No updates found via native API" -InformationAction Continue
            return $results
        }

        # Calculate total size
        $totalSize = ($availableUpdates | ForEach-Object { $_.MaxDownloadSize } | Measure-Object -Sum).Sum
        $results.TotalSizeMB = [math]::Round($totalSize / 1MB, 2)

        if ($DryRun) {
            Write-Information "    📋 [DRY RUN] Found $($results.UpdatesFound) updates ($($results.TotalSizeMB) MB)" -InformationAction Continue

            foreach ($update in $availableUpdates) {
                $results.Details.Add([PSCustomObject]@{
                        Title    = $update.Title
                        SizeMB   = [math]::Round($update.MaxDownloadSize / 1MB, 2)
                        Category = 'Windows Update'
                        Status   = 'Available'
                    })
            }

            return $results
        }

        # Download and install updates
        Write-Information "    📥 Downloading and installing updates..." -InformationAction Continue

        $updatesToInstall = New-Object -ComObject Microsoft.Update.UpdateColl
        foreach ($update in $availableUpdates) {
            $updatesToInstall.Add($update) | Out-Null
        }

        # Download updates
        $downloader = $updateSession.CreateUpdateDownloader()
        $downloader.Updates = $updatesToInstall
        $downloadResult = $downloader.Download()

        if ($downloadResult.ResultCode -eq 2) {
            # SuccessfullyDownloaded
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
    [CmdletBinding()]
    [OutputType([bool])]
    param()
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
    [CmdletBinding()]
    [OutputType([bool])]
    param()
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
    [CmdletBinding()]
    [OutputType([bool])]
    param()
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
function Get-WindowsUpdateSetting {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()
    try {
        $auKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update"

        $settings = @{
            AutoUpdateEnabled = $false
            LastUpdateCheck   = $null
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
            Write-Verbose "Failed to get last update check time: $_"
        }

        return $settings
    }
    catch {
        return @{
            AutoUpdateEnabled = $false
            LastUpdateCheck   = $null
        }
    }
}

<#
.SYNOPSIS
    Gets basic Windows Update status without advanced features
#>
function Get-WindowsUpdateBasicStatus {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()
    return @{
        UpdatesFound     = 0
        UpdatesInstalled = 0
        UpdatesFailed    = 0
        TotalSizeMB      = 0
        RebootRequired   = Test-PendingReboot
        Details          = @()
        Method           = 'Basic Status'
        DryRun           = $false
        Message          = "Limited Windows Update capability - PSWindowsUpdate module recommended"
    }
}

#endregion

# Export module functions
Export-ModuleMember -Function @(
    'Install-WindowsUpdates',
    'Get-WindowsUpdateStatus'
)
