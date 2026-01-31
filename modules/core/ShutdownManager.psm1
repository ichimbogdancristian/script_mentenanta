#Requires -Version 7.0

<#
.SYNOPSIS
    ShutdownManager - Post-execution countdown and system shutdown orchestration

.DESCRIPTION
    Manages the post-execution lifecycle of maintenance operations:
    - 120-second countdown timer with visual feedback
    - Non-blocking keypress detection
    - Interactive abort menu with multiple action options
    - Automatic cleanup of temporary files
    - Safe system reboot with notification

    This module bridges the gap between maintenance task completion and system state
    management, ensuring proper cleanup and graceful reboot when configured.

.NOTES
    Module Type: Core Infrastructure
    Version: 1.0.0
    Architecture: v3.0+ compatible
    Requires: PowerShell 7.0+, Administrator privileges for reboot

    Integration:
    - Called from MaintenanceOrchestrator.ps1 after all tasks complete
    - Requires ShutdownManager in $CoreModules list
    - Reads configuration from $MainConfig.execution.shutdown*

.AUTHOR
    Windows Maintenance Automation Project

.EXAMPLE
    PS> Import-Module .\modules\core\ShutdownManager.psm1 -Global
    PS> Start-MaintenanceCountdown -CountdownSeconds 120 -WorkingDirectory $wd -TempRoot $tr
#>

#region Module Configuration & Initialization

Write-Verbose "ShutdownManager: Initializing module..."

# Ensure Write-LogEntry is available from CoreInfrastructure
if (-not (Get-Command 'Write-LogEntry' -ErrorAction SilentlyContinue)) {
    <#
    .SYNOPSIS
        Log entry helper for shutdown manager
    #>
    function Write-LogEntry {
        param(
            [string]$Level,
            [string]$Component,
            [string]$Message,
            [hashtable]$Data
        )
        $timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ss.fffZ"
        $logMessage = "[$timestamp] [$Level] [$Component] $Message"
        if ($Data) {
            $logMessage += " | $(ConvertTo-Json -InputObject $Data -Compress)"
        }
        Write-Information $logMessage -InformationAction Continue
    }
}

#endregion

#region Main Functions

<#
.SYNOPSIS
    Start post-execution countdown with interactive abort option

.DESCRIPTION
    Displays a 120-second (configurable) countdown timer. During countdown:
    - User can press any key to abort and show action menu
    - Timer continues if no key pressed
    - On timeout: Executes default action (cleanup, reboot, or both)

    Handles Windows-specific challenges:
    - Non-blocking keypress detection via $Host.UI.RawUI
    - Graceful fallback if console not available
    - Safe reboot using shutdown.exe (built-in)

.PARAMETER CountdownSeconds
    Duration of countdown in seconds. Default: 120

.PARAMETER WorkingDirectory
    Path to extracted repository (will be deleted on cleanup)

.PARAMETER TempRoot
    Path to temp_files directory (partial cleanup)

.PARAMETER CleanupOnTimeout
    If true, remove temporary files when timeout completes

.PARAMETER RebootOnTimeout
    If true, initiate system reboot when timeout completes

.PARAMETER SessionId
    Optional GUID for logging association

.OUTPUTS
    Hashtable with shutdown action details:
    @{
        Action = "CleanupOnly"|"SkipCleanup"|"CleanupAndReboot"|"RebootInitiated"
        RebootRequired = $true|$false
        RebootDelay = seconds
    }

.EXAMPLE
    $result = Start-MaintenanceCountdown -CountdownSeconds 120 `
        -WorkingDirectory "C:\maintenance_repo" `
        -TempRoot "C:\maintenance_repo\temp_files" `
        -CleanupOnTimeout `
        -RebootOnTimeout

.NOTES
    Called by MaintenanceOrchestrator.ps1 after module execution
#>
function Start-MaintenanceCountdown {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([hashtable])]
    param(
        [ValidateRange(10, 600)]
        [int]$CountdownSeconds = 120,

        [Parameter(Mandatory = $true)]
        [string]$WorkingDirectory,

        [Parameter(Mandatory = $true)]
        [string]$TempRoot,

        [switch]$CleanupOnTimeout,
        [switch]$RebootOnTimeout
    )

    if ($PSCmdlet.ShouldProcess("System", "Execute maintenance shutdown sequence")) {
        Write-LogEntry -Level 'INFO' -Component 'SHUTDOWN-MANAGER' `
            -Message "Initiating post-execution shutdown sequence" `
            -Data @{ CountdownSeconds = $CountdownSeconds; CleanupOnTimeout = $CleanupOnTimeout.IsPresent; RebootOnTimeout = $RebootOnTimeout.IsPresent }
    }

    try {
        # Display countdown banner
        Write-Host "`n" -NoNewline
        Write-Host "╔════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
        Write-Host "║   POST-EXECUTION MAINTENANCE SEQUENCE                  ║" -ForegroundColor Cyan
        Write-Host "╚════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "System will perform cleanup and shutdown in:" -ForegroundColor Yellow
        Write-Host ""

        $remainingSeconds = $CountdownSeconds
        $countdownStartTime = Get-Date

        # Determine whether keypress detection is supported (avoid repeated errors)
        $keyPressSupported = $false
        try {
            if ($Host -and $Host.UI -and $Host.UI.RawUI) {
                $null = $Host.UI.RawUI.KeyAvailable
                $keyPressSupported = $true
            }
        }
        catch {
            Write-LogEntry -Level 'DEBUG' -Component 'SHUTDOWN-MANAGER' `
                -Message "Keypress detection unavailable (non-interactive mode): $_"
            $keyPressSupported = $false
        }

        # Main countdown loop
        while ($remainingSeconds -gt 0) {
            # Format display
            $minutes = [math]::Floor($remainingSeconds / 60)
            $seconds = $remainingSeconds % 60
            $display = "$($minutes):$($seconds.ToString('00')) remaining"

            # Show countdown (overwrite previous line)
            Write-Host "`r  ⏱  $display  " -ForegroundColor Yellow -NoNewline

            # Check for keypress (non-blocking)
            try {
                if ($keyPressSupported -and $Host.UI.RawUI.KeyAvailable) {
                    [void]$Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

                    # Key pressed - abort countdown
                    Write-Host "`n" -NoNewline
                    Write-Host "`n⏸ Countdown aborted - user requested action" -ForegroundColor Yellow

                    Write-LogEntry -Level 'INFO' -Component 'SHUTDOWN-MANAGER' `
                        -Message "Countdown interrupted by user keypress after $([math]::Floor((Get-Date - $countdownStartTime).TotalSeconds))s"

                    # Show abort menu and handle user choice
                    $abortChoice = Show-ShutdownAbortMenu
                    $abortResult = Invoke-MaintenanceShutdownChoice -Choice $abortChoice `
                        -WorkingDirectory $WorkingDirectory `
                        -TempRoot $TempRoot

                    Write-LogEntry -Level 'INFO' -Component 'SHUTDOWN-MANAGER' `
                        -Message "User selected action: $($abortResult.Action)" `
                        -Data $abortResult

                    return $abortResult
                }
            }
            catch {
                # Continue countdown without interactivity
                Write-Verbose "Continuing countdown in non-interactive mode"
            }

            # Decrement and wait
            $remainingSeconds--
            Start-Sleep -Seconds 1
        }

        # Countdown complete - execute timeout action
        Write-Host "`n" -NoNewline
        Write-Host "`n✓ Countdown complete. Executing maintenance shutdown..." -ForegroundColor Green

        Write-LogEntry -Level 'INFO' -Component 'SHUTDOWN-MANAGER' `
            -Message "Countdown expired - executing timeout actions"

        $timeoutResult = @{
            Action         = "CleanupAndContinue"
            RebootRequired = $false
            RebootDelay    = 0
        }

        if ($CleanupOnTimeout) {
            Write-Host "  • Cleaning up temporary files..." -ForegroundColor Cyan
            $cleanupSuccess = Invoke-MaintenanceCleanup -WorkingDirectory $WorkingDirectory `
                -TempRoot $TempRoot `
                -KeepReports

            if ($cleanupSuccess) {
                $timeoutResult.Action = "CleanupCompleted"
                Write-LogEntry -Level 'SUCCESS' -Component 'SHUTDOWN-MANAGER' -Message "Cleanup completed successfully"
            }
            else {
                Write-Host "  ⚠️  Cleanup encountered errors (see logs)" -ForegroundColor Yellow
                Write-LogEntry -Level 'WARNING' -Component 'SHUTDOWN-MANAGER' -Message "Cleanup failed or partially completed"
            }
        }

        if ($RebootOnTimeout) {
            Write-Host "  • Preparing system reboot in 10 seconds..." -ForegroundColor Cyan
            Write-Host "`n  Press Ctrl+C to cancel restart (cleanup already completed)" -ForegroundColor Yellow

            Start-Sleep -Seconds 3

            Write-LogEntry -Level 'INFO' -Component 'SHUTDOWN-MANAGER' -Message "Initiating system reboot"

            try {
                Write-EventLog -LogName System -Source "Windows Maintenance" `
                    -EventId 1000 -EntryType Information `
                    -Message "Maintenance completed. System restarting."
            }
            catch {
                Write-LogEntry -Level 'WARNING' -Component 'SHUTDOWN-MANAGER' `
                    -Message "Could not write to Windows Event Log: $_"
            }

            # Use shutdown.exe for reliable reboot
            & shutdown.exe /r /t 10 /c "Windows Maintenance completed. System restarting..."

            $timeoutResult.Action = "RebootInitiated"
            $timeoutResult.RebootRequired = $true
            $timeoutResult.RebootDelay = 10

            Write-LogEntry -Level 'SUCCESS' -Component 'SHUTDOWN-MANAGER' -Message "System reboot initiated"
        }

        return $timeoutResult
    }
    catch {
        Write-LogEntry -Level 'ERROR' -Component 'SHUTDOWN-MANAGER' `
            -Message "Shutdown sequence failed: $_" `
            -Data @{ ErrorType = $_.Exception.GetType().Name; StackTrace = $_.ScriptStackTrace }

        return @{
            Action         = "Error"
            RebootRequired = $false
            Error          = $_.Exception.Message
        }
    }
}

<#
.SYNOPSIS
    Display interactive abort menu when user interrupts countdown

.DESCRIPTION
    Shows user three options:
    1. Cleanup now (remove temp files, keep reports, no reboot)
    2. Skip cleanup (preserve all files for review)
    3. Cleanup AND reboot

    Returns user selection (1-3)

.OUTPUTS
    Integer 1, 2, or 3 representing user choice

.NOTES
    Called by Start-MaintenanceCountdown
#>
function Show-ShutdownAbortMenu {
    [CmdletBinding()]
    [OutputType([int])]
    param()

    Write-Host ""
    Write-Host "╔════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║   SHUTDOWN SEQUENCE ABORTED - SELECT ACTION           ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  1. " -NoNewline -ForegroundColor White
    Write-Host "Cleanup now (remove temporary files, keep reports)" -ForegroundColor Gray
    Write-Host "     └─ System will remain on for review" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  2. " -NoNewline -ForegroundColor White
    Write-Host "Skip cleanup (preserve all files for review)" -ForegroundColor Gray
    Write-Host "     └─ All temporary and processing files kept intact" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  3. " -NoNewline -ForegroundColor White
    Write-Host "Cleanup AND reboot" -ForegroundColor Gray
    Write-Host "     └─ Clean up then restart system" -ForegroundColor DarkGray
    Write-Host ""

    $choice = Read-Host "Select option (1-3, default=1)"

    # Validate input
    if ([string]::IsNullOrWhiteSpace($choice)) {
        return 1
    }

    try {
        $choiceInt = [int]$choice.Trim()
        if ($choiceInt -ge 1 -and $choiceInt -le 3) {
            return $choiceInt
        }
    }
    catch {
        # Invalid input - return default
        Write-Verbose "Invalid choice entered: $choice"
    }

    Write-Host "Invalid selection. Using default (1)..." -ForegroundColor Yellow
    return 1
}

<#
.SYNOPSIS
    Handle user selection from abort menu

.DESCRIPTION
    Executes the action corresponding to user menu choice:
    1: Cleanup, keep system on
    2: Skip cleanup
    3: Cleanup and reboot

.PARAMETER Choice
    User's menu selection (1-3)

.PARAMETER WorkingDirectory
    Repository extraction directory

.PARAMETER TempRoot
    Temporary files root directory

.OUTPUTS
    Hashtable with action details (same format as Start-MaintenanceCountdown)
#>
function Invoke-MaintenanceShutdownChoice {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [ValidateRange(1, 3)]
        [int]$Choice,
        [string]$WorkingDirectory,
        [string]$TempRoot
    )

    switch ($Choice) {
        1 {
            # Cleanup now
            Write-Host "`nCleaning up temporary files..." -ForegroundColor Cyan
            $success = Invoke-MaintenanceCleanup -WorkingDirectory $WorkingDirectory `
                -TempRoot $TempRoot `
                -KeepReports

            if ($success) {
                Write-Host "`n✓ Cleanup completed successfully" -ForegroundColor Green
                Write-Host "`nReports available at: temp_files/reports/" -ForegroundColor Cyan
            }
            else {
                Write-Host "`n⚠️  Cleanup encountered some errors (see logs)" -ForegroundColor Yellow
            }

            return @{ Action = "CleanupOnly"; RebootRequired = $false }
        }

        2 {
            # Skip cleanup
            Write-Host "`n✓ Cleanup skipped. All files preserved for review." -ForegroundColor Green
            Write-Host "`nAll files available at: $WorkingDirectory" -ForegroundColor Cyan
            Write-Host "Reports: $WorkingDirectory/temp_files/reports/" -ForegroundColor Cyan
            Write-Host "Logs: $WorkingDirectory/temp_files/logs/" -ForegroundColor Cyan

            return @{ Action = "SkipCleanup"; RebootRequired = $false }
        }

        3 {
            # Cleanup AND reboot
            Write-Host "`nCleaning up and preparing reboot..." -ForegroundColor Cyan
            $success = Invoke-MaintenanceCleanup -WorkingDirectory $WorkingDirectory `
                -TempRoot $TempRoot `
                -KeepReports

            Write-Host "`n✓ Cleanup completed. System will restart in 10 seconds..." -ForegroundColor Cyan
            Write-Host "Press Ctrl+C to cancel" -ForegroundColor Yellow

            Start-Sleep -Seconds 3

            & shutdown.exe /r /t 10 /c "Windows Maintenance cleanup complete. Restarting..."

            return @{ Action = "CleanupAndReboot"; RebootRequired = $true; RebootDelay = 10 }
        }

        default {
            return @{ Action = "Unknown"; RebootRequired = $false; Error = "Invalid choice" }
        }
    }
}

<#
.SYNOPSIS
    Execute cleanup of maintenance temporary files and extracted repository

.DESCRIPTION
    Removes the following with proper error handling:
    - Extracted repository folder ($WorkingDirectory)
    - Temporary processing files (temp_files/temp, data, logs, processed)
    - Optionally keeps reports directory for user review

    Uses -Force to handle locked files and non-interactive cleanup

.PARAMETER WorkingDirectory
    Path to extracted maintenance repository

.PARAMETER TempRoot
    Root of temp_files directory structure

.PARAMETER KeepReports
    If true, preserve reports directory for review

.OUTPUTS
    Boolean: $true if cleanup successful, $false if errors occurred

.NOTES
    Uses try-catch with SilentlyContinue to handle locked files gracefully
#>
function Invoke-MaintenanceCleanup {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [string]$WorkingDirectory,
        [string]$TempRoot,
        [switch]$KeepReports
    )

    Write-LogEntry -Level 'INFO' -Component 'SHUTDOWN-MANAGER' `
        -Message "Starting maintenance cleanup" `
        -Data @{ WorkingDirectory = $WorkingDirectory; KeepReports = $KeepReports.IsPresent }

    $cleanupErrors = @()
    $cleanupSuccess = @()

    try {
        # Define paths to cleanup
        $cleanupPaths = @(
            (Join-Path $TempRoot "temp"),       # Temporary files during processing
            (Join-Path $TempRoot "logs"),       # Execution logs
            (Join-Path $TempRoot "data"),       # Type1 audit results
            (Join-Path $TempRoot "processed"),  # Processed data cache
            $WorkingDirectory                    # Entire extracted repository
        )

        # Optionally keep reports for user review
        if ($KeepReports) {
            $cleanupPaths = $cleanupPaths | Where-Object { $_ -notlike "*reports*" }
            Write-LogEntry -Level 'DEBUG' -Component 'SHUTDOWN-MANAGER' -Message "Preserving reports directory"
        }

        # Attempt cleanup of each path
        foreach ($path in $cleanupPaths) {
            if ([string]::IsNullOrWhiteSpace($path)) { continue }

            if (Test-Path $path) {
                try {
                    $item = Get-Item $path -ErrorAction SilentlyContinue
                    $size = if ($item -is [System.IO.DirectoryInfo]) {
                        "{0:N0}" -f ((Get-ChildItem -Path $path -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum / 1MB)
                    }
                    else {
                        $item.Length / 1MB
                    }

                    Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue

                    if (-not (Test-Path $path)) {
                        $message = "Removed: $path (${size}MB)"
                        Write-LogEntry -Level 'SUCCESS' -Component 'SHUTDOWN-MANAGER' -Message $message
                        $cleanupSuccess += $path
                    }
                    else {
                        $message = "Failed to remove: $path (file still exists after Remove-Item)"
                        Write-LogEntry -Level 'WARNING' -Component 'SHUTDOWN-MANAGER' -Message $message
                        $cleanupErrors += $path
                    }
                }
                catch {
                    $message = "Error removing $path`: $_"
                    Write-LogEntry -Level 'ERROR' -Component 'SHUTDOWN-MANAGER' -Message $message
                    $cleanupErrors += $path
                }
            }
            else {
                Write-LogEntry -Level 'DEBUG' -Component 'SHUTDOWN-MANAGER' -Message "Path does not exist (skipped): $path"
            }
        }

        # Summary
        Write-LogEntry -Level 'INFO' -Component 'SHUTDOWN-MANAGER' `
            -Message "Cleanup completed" `
            -Data @{ SuccessfulPaths = $cleanupSuccess.Count; FailedPaths = $cleanupErrors.Count }

        if ($cleanupErrors.Count -gt 0) {
            Write-LogEntry -Level 'WARNING' -Component 'SHUTDOWN-MANAGER' `
                -Message "Cleanup had errors for paths: $($cleanupErrors -join '; ')"
            return $false
        }

        Write-LogEntry -Level 'SUCCESS' -Component 'SHUTDOWN-MANAGER' -Message "All cleanup operations completed successfully"
        return $true
    }
    catch {
        Write-LogEntry -Level 'ERROR' -Component 'SHUTDOWN-MANAGER' `
            -Message "Cleanup operation failed: $_" `
            -Data @{ ErrorType = $_.Exception.GetType().Name }
        return $false
    }
}

#endregion

#region Module Exports

Export-ModuleMember -Function @(
    'Start-MaintenanceCountdown',
    'Show-ShutdownAbortMenu',
    'Invoke-MaintenanceShutdownChoice',
    'Invoke-MaintenanceCleanup'
)

#endregion

Write-Verbose "ShutdownManager: Module initialization complete"




