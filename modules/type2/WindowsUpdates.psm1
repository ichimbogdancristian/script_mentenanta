#Requires -Version 7.0
# Module Dependencies:
#   - CoreInfrastructure.psm1 (configuration, logging, path management)
#   - WindowsUpdatesAudit.psm1 (Type1 - detection/analysis)
#
# External Tools (optional, auto-installed if needed):
#   - PSWindowsUpdate module (PowerShell Gallery)

<#
.SYNOPSIS
    Windows Updates Module - Type 2 (System Modification)

.DESCRIPTION
    Comprehensive Windows Update management with automated detection, installation,
    and reboot suppression. Supports both PSWindowsUpdate module and native Windows Update APIs.

.NOTES
    Module Type: Type 2 (System Modification)
    Dependencies: WindowsUpdatesAudit.psm1, CoreInfrastructure.psm1
    Requires: Administrator privileges, internet connectivity
    Author: Windows Maintenance Automation Project
    Version: 1.0.0
#>

using namespace System.Collections.Generic

# v3.0 Self-contained Type 2 module with internal Type 1 dependency

# Step 1: Import core infrastructure FIRST (REQUIRED) - Global scope for Type1 access
$ModuleRoot = if ($PSScriptRoot) { Split-Path -Parent $PSScriptRoot } else { Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path) }
$CoreInfraPath = Join-Path $ModuleRoot 'core\CoreInfrastructure.psm1'
if (Test-Path $CoreInfraPath) {
    Import-Module $CoreInfraPath -Force -Global -WarningAction SilentlyContinue
}
else {
    Write-Warning "CoreInfrastructure module not found at: $CoreInfraPath"
}

# Step 2: Import corresponding Type 1 module AFTER CoreInfrastructure (REQUIRED)
$Type1ModulePath = Join-Path $ModuleRoot 'type1\WindowsUpdatesAudit.psm1'
if (Test-Path $Type1ModulePath) {
    Import-Module $Type1ModulePath -Force
}
else {
    throw "Required Type 1 module not found: $Type1ModulePath"
}

# Note: PSWindowsUpdate PowerShell module is installed automatically if needed
# Windows Update operations use native Windows Update Agent APIs

# Validate Type1 module loaded correctly
if (-not (Get-Command -Name 'Get-WindowsUpdatesAnalysis' -ErrorAction SilentlyContinue)) {
    throw "Type 1 module functions not available - ensure WindowsUpdatesAudit.psm1 is properly imported"
}

#region v3.0 Standardized Execution Function

function Invoke-WindowsUpdates {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Config,

        [Parameter()]
        [switch]$DryRun
    )

    $perfContext = Start-PerformanceTrackingSafe -OperationName 'WindowsUpdates' -Component 'WINDOWS-UPDATES'

    try {
        # Track execution duration for v3.0 compliance
        $executionStartTime = Get-Date

        # Initialize module execution environment
        Initialize-ModuleExecution -ModuleName 'WindowsUpdates'

        Write-LogEntry -Level 'INFO' -Component 'WINDOWS-UPDATES' -Message 'Starting Windows updates analysis'
        $analysisResults = Get-WindowsUpdatesAnalysis

        $updatesCount = 0
        if ($analysisResults) {
            if ($analysisResults.PSObject.Properties.Name -contains 'PendingUpdatesCount') {
                $updatesCount = [int]$analysisResults.PendingUpdatesCount
            }
            elseif ($analysisResults.PendingAudit -and ($analysisResults.PendingAudit.PendingCount -ne $null)) {
                $updatesCount = [int]$analysisResults.PendingAudit.PendingCount
            }
        }

        if (-not $analysisResults -or $updatesCount -eq 0) {
            Write-LogEntry -Level 'INFO' -Component 'WINDOWS-UPDATES' -Message 'No pending Windows updates detected'
            if ($perfContext) { Complete-PerformanceTracking -Context $perfContext -Status 'Success' }
            $executionTime = (Get-Date) - $executionStartTime
            return New-ModuleExecutionResult `
                -Success $true `
                -ItemsDetected 0 `
                -ItemsProcessed 0 `
                -DurationMilliseconds $executionTime.TotalMilliseconds `
                -LogPath "" `
                -ModuleName 'WindowsUpdates' `
                -DryRun $DryRun.IsPresent
        }

        # Display module banner
        Write-Host "`n" -NoNewline
        Write-Host "=================================================" -ForegroundColor Cyan
        Write-Host "  WINDOWS UPDATES MODULE v3.0" -ForegroundColor White
        Write-Host "=================================================" -ForegroundColor Cyan
        Write-Host "  Type: " -NoNewline -ForegroundColor Gray
        Write-Host "Type 2 (System Modification)" -ForegroundColor Yellow
        Write-Host "  Mode: " -NoNewline -ForegroundColor Gray
        Write-Host "$(if ($DryRun) { 'DRY-RUN (Simulation)' } else { 'LIVE EXECUTION' })" -ForegroundColor $(if ($DryRun) { 'Cyan' } else { 'Green' })
        Write-Host "=================================================" -ForegroundColor Cyan
        Write-Host ""

        # STEP 3: Setup execution logging directory
        $executionLogDir = Join-Path (Get-MaintenancePath 'TempRoot') "logs\windows-updates"
        New-Item -Path $executionLogDir -ItemType Directory -Force | Out-Null
        # Removed redundant self-assignment

        $updatesCount = $updatesCount
        Write-StructuredLogEntry -Level 'INFO' -Component 'WINDOWS-UPDATES' -Message "Detected $updatesCount pending Windows updates" -LogPath $executionLogPath -Operation 'Detect' -Metadata @{ UpdateCount = $updatesCount }

        if ($DryRun) {
            Write-StructuredLogEntry -Level 'INFO' -Component 'WINDOWS-UPDATES' -Message ' DRY-RUN: Simulating Windows updates installation' -LogPath $executionLogPath -Operation 'Simulate' -Metadata @{ DryRun = $true; UpdateCount = $updatesCount }
            $results = @{ ProcessedCount = $updatesCount; Simulated = $true }; $processedCount = $updatesCount
        }
        else {
            Write-StructuredLogEntry -Level 'INFO' -Component 'WINDOWS-UPDATES' -Message 'Executing Windows updates installation' -LogPath $executionLogPath -Operation 'Install' -Metadata @{ UpdateCount = $updatesCount }
            $results = Install-WindowsUpdate -ExecutionLogPath $executionLogPath
            $processedCount = if ($results.InstalledCount) { $results.InstalledCount } else { 0 }
        }

        Write-StructuredLogEntry -Level 'SUCCESS' -Component 'WINDOWS-UPDATES' -Message "Windows updates completed. Processed: $processedCount/$updatesCount" -LogPath $executionLogPath -Operation 'Complete' -Result 'Success' -Metadata @{ ProcessedCount = $processedCount; TotalUpdates = $updatesCount }

        # Create execution summary JSON
        $summaryPath = Join-Path $executionLogDir "execution-summary.json"
        $executionTime = (Get-Date) - $executionStartTime
        $executionSummary = @{
            ModuleName    = 'WindowsUpdates'
            ExecutionTime = @{
                Start      = $executionStartTime.ToString('o')
                End        = (Get-Date).ToString('o')
                DurationMs = $executionTime.TotalMilliseconds
            }
            Results       = @{
                Success        = $true
                ItemsDetected  = $updatesCount
                ItemsProcessed = $processedCount
                ItemsFailed    = 0
                ItemsSkipped   = ($updatesCount - $processedCount)
            }
            ExecutionMode = if ($DryRun) { 'DryRun' } else { 'Live' }
            LogFiles      = @{
                TextLog = $executionLogPath
                JsonLog = $executionLogPath -replace '\.log$', '-data.json'
                Summary = $summaryPath
            }
            SessionInfo   = @{
                SessionId    = $env:MAINTENANCE_SESSION_ID
                ComputerName = $env:COMPUTERNAME
                UserName     = $env:USERNAME
                PSVersion    = $PSVersionTable.PSVersion.ToString()
            }
        }

        try {
            $executionSummary | ConvertTo-Json -Depth 10 | Set-Content $summaryPath -Force
            Write-Verbose "Execution summary saved to: $summaryPath"
        }
        catch {
            Write-Warning "Failed to create execution summary: $($_.Exception.Message)"
        }

        $returnData = New-ModuleExecutionResult `
            -Success $true `
            -ItemsDetected $updatesCount `
            -ItemsProcessed $processedCount `
            -DurationMilliseconds $executionTime.TotalMilliseconds `
            -LogPath $executionLogPath `
            -ModuleName 'WindowsUpdates' `
            -DryRun $DryRun.IsPresent
        if ($perfContext) { Complete-PerformanceTracking -Context $perfContext -Status 'Success' | Out-Null }
        return $returnData

    }
    catch {
        $errorMsg = "Failed to execute Windows updates: $($_.Exception.Message)"
        Write-LogEntry -Level 'ERROR' -Component 'WINDOWS-UPDATES' -Message $errorMsg -Data @{ Error = $_.Exception }
        if ($perfContext) { Complete-PerformanceTracking -Context $perfContext -Status 'Failed' -ErrorMessage $errorMsg | Out-Null }
        $executionTime = if ($executionStartTime) { (Get-Date) - $executionStartTime } else { New-TimeSpan }
        return New-ModuleExecutionResult `
            -Success $false `
            -ItemsDetected $updatesCount `
            -ItemsProcessed 0 `
            -DurationMilliseconds $executionTime.TotalMilliseconds `
            -LogPath $executionLogPath `
            -ModuleName 'WindowsUpdates' `
            -ErrorMessage $errorMsg
    }
}

#endregion

#region Legacy Public Functions (Preserved for Internal Use)

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
    [OutputType([bool])]
    param(
        [Parameter()]
        [switch]$ExcludePreviews,

        [Parameter()]
        [switch]$IncludeOptional,

        [Parameter()]
        [switch]$IncludeDrivers,

        [Parameter()]
        [ValidateRange(100, 10240)]
        [int]$MaxDownloadSizeMB = 2048,

        [Parameter()]
        [switch]$DryRun,

        [Parameter()]
        [switch]$SuppressReboot,

        [Parameter()]
        [string]$ExecutionLogPath
    )

    Write-Information " Starting Windows Updates check and installation..." -InformationAction Continue
    $startTime = Get-Date

    # Initialize structured logging and performance tracking
    try {
        Write-LogEntry -Level 'INFO' -Component 'WINDOWS-UPDATES' -Message 'Starting Windows Updates installation' -Data @{
            ExcludePreviews   = $ExcludePreviews.IsPresent
            IncludeOptional   = $IncludeOptional.IsPresent
            IncludeDrivers    = $IncludeDrivers.IsPresent
            MaxDownloadSizeMB = $MaxDownloadSizeMB
            DryRun            = $DryRun.IsPresent
            SuppressReboot    = $SuppressReboot.IsPresent
        }
        $perfContext = Start-PerformanceTracking -OperationName 'WindowsUpdatesInstallation' -Component 'WINDOWS-UPDATES'
    }
    catch {
        Write-Verbose "WINDOWS-UPDATES: Logging initialization failed - $_"
        # LoggingManager not available, continue with standard logging
    }

    # Check for administrator privileges before proceeding
    try {
        Assert-AdminPrivilege -Operation "Windows Updates installation"
    }
    catch {
        Write-Error "Administrator privileges are required for Windows Updates operations: $_"
        return $false
    }

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
            Write-Information "   Using PSWindowsUpdate module..." -InformationAction Continue
            try { Write-LogEntry -Level 'INFO' -Component 'WINDOWS-UPDATES' -Message 'Using PSWindowsUpdate module for update installation' } catch { Write-Verbose "Logging failed: $($_.Exception.Message)" }

            # Create parameters for PSWindowsUpdate (remove ExecutionLogPath since it doesn't support it)
            $psWindowsUpdateParams = @{}
            foreach ($key in $PSBoundParameters.Keys) {
                if ($key -ne 'ExecutionLogPath') {
                    $psWindowsUpdateParams[$key] = $PSBoundParameters[$key]
                }
            }
            $results = Install-UpdatesViaPSWindowsUpdate @psWindowsUpdateParams
        }
        # Fallback to native Windows Update API
        elseif (Test-NativeWindowsUpdateAvailable) {
            Write-Information "   Using native Windows Update API..." -InformationAction Continue
            try { Write-LogEntry -Level 'INFO' -Component 'WINDOWS-UPDATES' -Message 'Using native Windows Update API for update installation' } catch { Write-Verbose "Logging failed: $($_.Exception.Message)" }
            # Remove ExecutionLogPath from parameters as native API doesn't support it
            $nativeApiParams = @{}
            foreach ($key in $PSBoundParameters.Keys) {
                if ($key -notin @('ExecutionLogPath', 'IncludeOptional', 'IncludeDrivers')) {
                    $nativeApiParams[$key] = $PSBoundParameters[$key]
                }
            }
            $results = Install-UpdatesViaNativeAPI @nativeApiParams
        }
        # Final fallback to basic checks
        else {
            Write-Warning "    Limited Windows Update capability available"
            $results = Get-WindowsUpdateBasicStatus
        }

        $duration = ((Get-Date) - $startTime).TotalSeconds

        # Summary output
        if ($results.UpdatesFound -eq 0) {
            Write-Information "   No updates available - system is up to date" -InformationAction Continue
            try { Write-LogEntry -Level 'INFO' -Component 'WINDOWS-UPDATES' -Message 'No updates available - system is up to date' } catch { Write-Verbose "Failed to write log entry: $_" }
        }
        elseif ($DryRun) {
            Write-Information "   Found $($results.UpdatesFound) available updates ($($results.TotalSizeMB) MB total)" -InformationAction Continue
            try { Write-LogEntry -Level 'INFO' -Component 'WINDOWS-UPDATES' -Message 'Dry-run completed - updates would be installed' -Data @{ UpdatesFound = $results.UpdatesFound; TotalSizeMB = $results.TotalSizeMB } } catch { Write-Verbose "Failed to write log entry: $_" }
        }
        else {
            $statusIcon = if ($results.UpdatesFailed -eq 0) { "" } else { "" }
            Write-Information "  $statusIcon Updates completed in $([math]::Round($duration, 2))s" -InformationAction Continue
            Write-Information "     Found: $($results.UpdatesFound), Installed: $($results.UpdatesInstalled), Failed: $($results.UpdatesFailed)" -InformationAction Continue

            if ($results.RebootRequired) {
                Write-Warning "     System restart required to complete installation"
            }
        }

        $success = $results.UpdatesFailed -eq 0 -and ($results.UpdatesInstalled -gt 0 -or $results.UpdatesFound -eq 0)

        # Complete performance tracking and structured logging
        try {
            Complete-PerformanceTracking -PerformanceContext $perfContext -Success $success -ResultData @{
                UpdatesFound     = $results.UpdatesFound
                UpdatesInstalled = $results.UpdatesInstalled
                UpdatesFailed    = $results.UpdatesFailed
                TotalSizeMB      = $results.TotalSizeMB
                RebootRequired   = $results.RebootRequired
                Method           = $results.Method
            }
            Write-LogEntry -Level $(if ($success) { 'SUCCESS' } else { 'WARNING' }) -Component 'WINDOWS-UPDATES' -Message 'Windows Updates operation completed' -Data $results
        }
        catch {
            Write-Verbose "WINDOWS-UPDATES: Logging completion failed - $_"
            # LoggingManager not available, continue with standard logging
        }

        # Log detailed results for audit trails
        Write-Verbose "Windows Updates operation details: $(ConvertTo-Json $results -Depth 3)"
        Write-Verbose "Windows Updates operation completed successfully"

        return $success
    }
    catch {
        $errorMessage = " Windows Updates operation failed: $($_.Exception.Message)"
        Write-Error $errorMessage
        Write-Verbose "Error details: $($_.Exception.ToString())"

        # Complete performance tracking for failed operation
        try {
            Complete-PerformanceTracking -PerformanceContext $perfContext -Success $false -ResultData @{ Error = $_.Exception.Message }
            Write-LogEntry -Level 'ERROR' -Component 'WINDOWS-UPDATES' -Message 'Windows Updates operation failed' -Data @{ Error = $_.Exception.Message; ErrorType = $_.Exception.GetType().Name }
        }
        catch {
            Write-Verbose "WINDOWS-UPDATES: Error logging failed - $_"
            # LoggingManager not available, continue with standard logging
        }

        # Type 2 module returns boolean for failure
        return $false
    }
    finally {
        $duration = ((Get-Date) - $startTime).TotalSeconds
        Write-Verbose "Windows Updates operation completed in $([math]::Round($duration, 2)) seconds"
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

    Write-Information " Checking Windows Update status..." -InformationAction Continue

    # Start structured logging for status check
    try {
        Write-LogEntry -Level 'INFO' -Component 'WINDOWS-UPDATES' -Message 'Starting Windows Update status check'
        $perfContext = Start-PerformanceTracking -OperationName 'WindowsUpdateStatusCheck' -Component 'WINDOWS-UPDATES'
    }
    catch {
        Write-Verbose "WINDOWS-UPDATES: Status check logging failed - $_"
        # LoggingManager not available, continue with standard logging
    }

    $status = @{
        UpdatesAvailable  = 0
        PendingReboot     = $false
        RebootReason      = @()
        LastUpdateCheck   = $null
        LastInstallDate   = $null
        AutoUpdateEnabled = $false
    }

    try {
        # Check for pending reboot from Windows Updates (using Type1 function)
        $status.PendingReboot = Test-PendingReboot
        if ($status.PendingReboot) {
            $status.RebootReason += "Windows Updates"
        }

        # Get Windows Update auto-update setting directly
        try {
            $auKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update"
            if (Test-Path $auKey) {
                $auValue = Get-ItemProperty $auKey -Name AUOptions -ErrorAction SilentlyContinue
                $status.AutoUpdateEnabled = $null -ne $auValue -and $auValue.AUOptions -gt 1
            }
        }
        catch {
            Write-Verbose "Could not read Windows Update auto-update setting: $_"
        }

        # Try to get available updates count
        if (Test-PSWindowsUpdateAvailable) {
            $availableUpdates = Get-WindowsUpdate -MicrosoftUpdate -ErrorAction SilentlyContinue
            $status.UpdatesAvailable = ($availableUpdates | Measure-Object).Count
        }

        Write-Information "   Status: $($status.UpdatesAvailable) updates available" -InformationAction Continue
        Write-Information "   Pending reboot: $($status.PendingReboot)" -InformationAction Continue
        Write-Information "   Auto-update: $($status.AutoUpdateEnabled)" -InformationAction Continue

        # Complete structured logging
        try {
            Complete-PerformanceTracking -PerformanceContext $perfContext -Success $true -ResultData $status
            Write-LogEntry -Level 'SUCCESS' -Component 'WINDOWS-UPDATES' -Message 'Windows Update status check completed' -Data $status
        }
        catch {
            Write-Verbose "WINDOWS-UPDATES: Status check completion logging failed - $_"
            # LoggingManager not available, continue with standard logging
        }

        return $status
    }
    catch {
        Write-Warning "Failed to get complete Windows Update status: $_"

        # Complete performance tracking for failed operation
        try {
            Complete-PerformanceTracking -PerformanceContext $perfContext -Success $false -ResultData @{ Error = $_.Exception.Message }
            Write-LogEntry -Level 'ERROR' -Component 'WINDOWS-UPDATES' -Message 'Windows Update status check failed' -Data @{ Error = $_.Exception.Message; ErrorType = $_.Exception.GetType().Name }
        }
        catch {
            Write-Verbose "WINDOWS-UPDATES: Status check error logging failed - $_"
            # LoggingManager not available, continue with standard logging
        }

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
        [switch]$IncludeOptional,
        [switch]$IncludeDrivers,
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
        Write-Information "     Scanning for available updates..." -InformationAction Continue

        $scanParams = @{
            MicrosoftUpdate = $true
            ErrorAction     = 'SilentlyContinue'
        }

        $availableUpdates = Get-WindowsUpdate @scanParams

        if (-not $availableUpdates) {
            Write-Information "     No updates found" -InformationAction Continue
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
            Write-Information "     [DRY RUN] Would install $($results.UpdatesFound) updates ($($results.TotalSizeMB) MB)" -InformationAction Continue

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
            Write-Information "     Installing $($filteredUpdates.Count) updates ($($results.TotalSizeMB) MB)..." -InformationAction Continue

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
                    $operationStart = Get-Date
                    $status = if ($result.Result -eq 'Installed') { 'Installed' } else { 'Failed' }
                    $kbNumber = if ($result.KB) { "KB$($result.KB)" } else { 'N/A' }

                    # Enhanced logging for each update
                    if ($status -eq 'Installed') {
                        $operationDuration = ((Get-Date) - $operationStart).TotalSeconds
                        Write-OperationSuccess -Component 'WINDOWS-UPDATES' -Operation 'Install' -Target $kbNumber -Metrics @{
                            Duration = $operationDuration
                            SizeMB   = [math]::Round($result.Size / 1MB, 2)
                            Title    = $result.Title
                            Category = ($result.Categories -join ', ')
                        }
                        Write-Information "       Installed: $kbNumber - $($result.Title) ($([math]::Round($result.Size / 1MB, 2)) MB)" -InformationAction Continue
                    }
                    else {
                        Write-OperationFailure -Component 'WINDOWS-UPDATES' -Operation 'Install' -Target $kbNumber -Error ([System.Management.Automation.ErrorRecord]::new(
                                [Exception]::new("Installation failed: $($result.Result)"),
                                "UpdateInstallationFailed",
                                [System.Management.Automation.ErrorCategory]::NotSpecified,
                                $result
                            ))
                        Write-Warning "       Failed: $kbNumber - $($result.Title)"
                    }

                    $results.Details.Add([PSCustomObject]@{
                            Title    = $result.Title
                            KB       = $kbNumber
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
                if ($results.RebootRequired) {
                    Write-LogEntry -Level 'WARNING' -Component 'WINDOWS-UPDATES' -Message 'System reboot required to complete installation'
                }

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
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    [OutputType([hashtable])]
    param(
        [switch]$DryRun
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
        Write-Information "     Using Windows Update COM API..." -InformationAction Continue

        # Create Windows Update session
        $updateSession = New-Object -ComObject Microsoft.Update.Session
        $updateSearcher = $updateSession.CreateUpdateSearcher()

        # Search for updates
        Write-Information "     Searching for available updates..." -InformationAction Continue
        $searchResult = $updateSearcher.Search("IsInstalled=0 and Type='Software'")

        $availableUpdates = @($searchResult.Updates)
        $results.UpdatesFound = $availableUpdates.Count

        if ($results.UpdatesFound -eq 0) {
            Write-Information "     No updates found via native API" -InformationAction Continue
            return $results
        }

        # Calculate total size
        $totalSize = ($availableUpdates | ForEach-Object { $_.MaxDownloadSize } | Measure-Object -Sum).Sum
        $results.TotalSizeMB = [math]::Round($totalSize / 1MB, 2)

        if ($DryRun) {
            Write-Information "     [DRY RUN] Found $($results.UpdatesFound) updates ($($results.TotalSizeMB) MB)" -InformationAction Continue

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
        Write-Information "     Downloading and installing updates..." -InformationAction Continue

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

#endregion

# Export module functions
Export-ModuleMember -Function @(
    # v3.0 Standardized execution function (Primary)
    'Invoke-WindowsUpdates',

    # Legacy functions (Preserved for internal use)
    'Install-WindowsUpdate',
    'Get-WindowsUpdateStatus'
)



