# ===============================
# Windows Maintenance Script - Task Coordinator (PowerShell 7.5.2 Optimized)
# ===============================
# This script is designed to automate and orchestrate a full suite of Windows maintenance tasks.
# It is intended to run as Administrator on Windows 10/11, with all actions logged and reported.
# Each task is modular, robust, and designed for unattended execution in enterprise or home environments.
#
# MODERNIZED FOR POWERSHELL 7.5.2:
# - Enhanced async operations and improved process management
# - Parallel processing for inventory collection and package operations
# - Modern JSON parsing with better error handling and performance
# - Improved file I/O operations with UTF-8 encoding
# - Enhanced error handling with detailed exception information
# - Modern package manager wrapper with timeout support
# - Optimized logging with better console color support
# - Thread-safe operations using System.Collections.Concurrent
#
# ENHANCED LOGGING SYSTEM:
# - Separated console progress bars from file logging for cleaner log files
# - Write-Log: Combined function for both console and file output
# - Write-LogFile: File-only logging without console noise
# - Write-ConsoleMessage: Console-only messages with enhanced colors
# - Write-TaskProgress: Progress bars for console, simple messages for file
# - Progress tracking for all major operations (tasks, bloatware removal, app installation, inventory)
#
# Key Environment Details:
# - Optimized for PowerShell 7.5.2+ with fallback compatibility for Windows PowerShell 5.1
# - Must be run as Administrator
# - Uses $PSScriptRoot for all temp and log files
# - Integrates with Winget, Chocolatey, AppX (via Windows PowerShell), DISM, Registry, and Windows Capabilities
# - All actions are silent/non-interactive
# - Graceful degradation if dependencies are missing
# - Automatically switches to Windows PowerShell for legacy module operations
# - Leverages PowerShell 7.5.2 features: parallel execution, improved error handling, and enhanced JSON support
#
# Task Array: $global:ScriptTasks
# Each entry defines a maintenance task with its logic, description, and config-driven enable/disable.

#Requires -Version 5.1
#Requires -RunAsAdministrator

using namespace System.Collections.Concurrent
using namespace System.Threading.Tasks

# Define all tasks in a single array with metadata
$global:ScriptTasks = @(
    # --- Task: SystemRestoreProtection ---
    # Purpose: Ensures System Restore is enabled and creates a restore point before maintenance.
    # Environment: Requires admin, runs on C:\, uses PowerShell's SystemRestoreConfig and Checkpoint-Computer.
    # Logic: Skips if disabled in config. Logs all actions and errors.
    @{ Name = 'SystemRestoreProtection'; Function = { if (-not $global:Config.SkipSystemRestore) { Protect-SystemRestore } else { Write-Log 'System Restore Protection skipped by config' 'INFO' } }; Description = 'Enable and checkpoint System Restore' },
    # --- Task: SystemInventory ---
    # Purpose: Collects basic system info for reporting and troubleshooting.
    # Environment: Runs on any Windows, outputs to inventory.txt in repo folder.
    # Logic: Uses Get-ComputerInfo, logs results.
    @{ Name = 'SystemInventory'; Function = { Get-SystemInventory }; Description = 'Legacy system inventory' },
    # --- Task: RemoveBloatware ---
    # Purpose: Removes unwanted apps using multiple methods (AppX, DISM, Winget, Choco, Registry, Capabilities).
    # Environment: Windows 10/11, admin required, supports OEM, Microsoft, and third-party bloatware.
    # Logic: Inventory-based filtering, robust error handling, logs every removal attempt and result.
    @{ Name = 'RemoveBloatware'; Function = { if (-not $global:Config.SkipBloatwareRemoval) { Remove-Bloatware } else { Write-Log 'Bloatware removal skipped by config' 'INFO' } }; Description = 'Enhanced multi-method bloatware removal (AppX, DISM, Registry, Capabilities)' },
    # --- Task: InstallEssentialApps ---
    # Purpose: Installs a curated list of essential apps using Winget and Chocolatey.
    # Environment: Windows 10/11, admin required, supports custom app lists via config.
    # Logic: Inventory-based filtering, skips already installed apps, logs every install attempt and result.
    @{ Name = 'InstallEssentialApps'; Function = { if (-not $global:Config.SkipEssentialApps) { Install-EssentialApps } else { Write-Log 'Essential apps installation skipped by config' 'INFO' } }; Description = 'Install essential applications' },
    # --- Task: TempListsSummary ---
    # Purpose: Generates comprehensive summary of all temp lists and diff operations for debugging and reporting.
    # Environment: Windows 10/11, outputs to temp folder, reads all temp list files.
    # Logic: Consolidates all list data into human-readable summary report.
    @{ Name = 'TempListsSummary'; Function = { Write-TempListsSummary }; Description = 'Generate temp lists summary report' },
    # --- Task: UpdateAllPackages ---
    # Purpose: Updates all installed packages via Winget and Chocolatey using modern process management.
    # Environment: Windows 10/11, admin required, silent/non-interactive, enhanced with PowerShell 7.5.2 features.
    # Logic: Uses modern package manager wrapper for better reliability and error handling.
    @{ Name = 'UpdateAllPackages'; Function = {
            Write-Log '[START] Update All Apps and Packages (Modern)' 'INFO'
            
            # Update using Winget if available with modern package manager
            if ($global:HasWinget) {
                try {
                    Write-Log 'Running winget upgrade for all packages...' 'INFO'
                    $wingetArgs = @("upgrade", "--all", "--silent", "--accept-source-agreements", "--accept-package-agreements")
                    $result = Invoke-ModernPackageManager -PackageManager 'winget' -Arguments $wingetArgs -Description "Upgrade all winget packages" -TimeoutSeconds 600
                    
                    if ($result.Success) {
                        Write-Log 'Winget upgrade completed successfully.' 'INFO'
                    }
                    else {
                        Write-Log "Winget upgrade failed with exit code $($result.ExitCode): $($result.Error)" 'WARN'
                    }
                }
                catch {
                    Write-Log "Winget upgrade failed: $_" 'WARN'
                }
            }
            else {
                Write-Log 'Winget not available, skipping winget upgrades.' 'WARN'
            }
            
            # Update using Chocolatey if available with modern package manager
            if ($global:HasChocolatey) {
                try {
                    Write-Log 'Running chocolatey upgrade for all packages...' 'INFO'
                    $chocoArgs = @("upgrade", "all", "-y", "--limit-output")
                    $result = Invoke-ModernPackageManager -PackageManager 'choco' -Arguments $chocoArgs -Description "Upgrade all choco packages" -TimeoutSeconds 600
                    
                    if ($result.Success) {
                        Write-Log 'Chocolatey upgrade completed successfully.' 'INFO'
                    }
                    else {
                        Write-Log "Chocolatey upgrade failed with exit code $($result.ExitCode): $($result.Error)" 'WARN'
                    }
                }
                catch {
                    Write-Log "Chocolatey upgrade failed: $_" 'WARN'
                }
            }
            else {
                Write-Log 'Chocolatey not available, skipping chocolatey upgrades.' 'WARN'
            }
            
            if (-not $global:HasWinget -and -not $global:HasChocolatey) {
                Write-Log 'No package managers available for updates. Consider installing Winget or Chocolatey.' 'WARN'
            }
            
            Write-Log '[END] Update All Apps and Packages (Modern)' 'INFO'
        }; Description = 'Update all apps and packages using modern process management' 
    },
    # --- Task: WindowsUpdateCheck ---
    # Purpose: Checks for and installs Windows Updates using PSWindowsUpdate module.
    # Environment: Windows 10/11, admin required, installs module if missing.
    # Logic: Skips if disabled in config, logs all update actions and errors.
    @{ Name = 'WindowsUpdateCheck'; Function = {
            if (-not $global:Config.SkipWindowsUpdates) {
                Write-Log 'Checking for Windows Updates...' 'INFO'
                
                $success = Install-WindowsUpdatesCompatible
                if ($success) {
                    Write-Log 'Windows Updates check and installation completed.' 'INFO'
                }
                else {
                    Write-Log 'Windows Updates check failed or no updates available.' 'WARN'
                }
            }
            else {
                Write-Log 'Windows Updates check skipped by config' 'INFO'
            }
        }; Description = 'Check and install Windows Updates' 
    },
    # --- Task: DisableTelemetry ---
    # Purpose: Disables Windows telemetry, privacy-invading features, and unwanted browsers.
    # Environment: Windows 10/11, admin required, modifies registry, disables services/tasks, configures browsers.
    # Logic: Skips if disabled in config, logs all actions and errors.
    @{ Name = 'DisableTelemetry'; Function = { if (-not $global:Config.SkipTelemetryDisable) { Disable-Telemetry } else { Write-Log 'Telemetry disable skipped by config' 'INFO' } }; Description = 'Disable telemetry and privacy tweaks' },
    # --- Task: CleanTempAndDisk ---
    # Purpose: Cleans temp files and runs disk cleanup for free space and hygiene.
    # Environment: Windows 10/11, admin required, uses cleanmgr.exe and removes temp folders.
    # Logic: Silent, logs all deletions and cleanup results.
    @{ Name = 'CleanTempAndDisk'; Function = {
            Write-Log '[START] Clean Temp Files and Disk Cleanup (Unattended)' 'INFO'
            $tempFolders = @($env:TEMP, "$env:SystemRoot\Temp", "$env:LOCALAPPDATA\Temp", "$env:USERPROFILE\AppData\Local\Temp")
            $deletedFiles = 0
            $currentFolder = 0
            $totalFolders = ($tempFolders | Sort-Object -Unique).Count
            
            foreach ($folder in $tempFolders | Sort-Object -Unique) {
                $currentFolder++
                $percentComplete = [math]::Round(($currentFolder / $totalFolders) * 80) # Reserve 20% for disk cleanup
                
                if (Test-Path $folder) {
                    Write-TaskProgress -Activity "Cleaning Temporary Files" -Status "Processing folder: $folder" -PercentComplete $percentComplete
                    Write-LogFile "Processing temp folder: $folder" 'VERBOSE'
                    
                    $items = Get-ChildItem -Path $folder -Recurse -ErrorAction SilentlyContinue
                    $totalItems = $items.Count
                    $currentItem = 0
                    
                    foreach ($item in $items) {
                        $currentItem++
                        if ($currentItem % 50 -eq 0 -or $currentItem -eq $totalItems) {
                            $itemPercent = [math]::Round((($currentFolder - 1) / $totalFolders * 80) + ($currentItem / $totalItems * 80 / $totalFolders))
                            Write-TaskProgress -Activity "Cleaning Temporary Files" -Status "Processing folder: $folder" -PercentComplete $itemPercent -CurrentOperation "Deleting $currentItem of $totalItems items"
                        }
                        
                        try {
                            Remove-Item $item.FullName -Force -Recurse -ErrorAction Stop
                            $deletedFiles++
                        }
                        catch {
                            Write-LogFile "Failed to delete $($item.FullName): $_" 'WARN'
                        }
                    }
                }
                else {
                    Write-TaskProgress -Activity "Cleaning Temporary Files" -Status "Skipping non-existent folder: $folder" -PercentComplete $percentComplete
                    Write-LogFile "Temp folder does not exist: $folder" 'VERBOSE'
                }
            }
            
            Write-Log "Deleted $deletedFiles temp files from temp folders." 'INFO'
            
            # Disk cleanup phase
            Write-TaskProgress -Activity "Cleaning Temporary Files" -Status "Running system disk cleanup..." -PercentComplete 85
            try {
                $cleanmgrArgs = '/AUTOCLEAN'
                $proc = Start-Process -FilePath 'cleanmgr.exe' -ArgumentList $cleanmgrArgs -WindowStyle Hidden -NoNewWindow -Wait -PassThru
                if ($proc.ExitCode -eq 0) {
                    Write-Log 'Disk cleanup completed using cleanmgr.exe (silent AUTOCLEAN).' 'SUCCESS'
                }
                else {
                    Write-Log "Disk cleanup process exited with code $($proc.ExitCode)" 'WARN'
                }
            }
            catch {
                Write-Log "Disk cleanup failed: $_" 'WARN'
            }
            Write-Log '[END] Clean Temp Files and Disk Cleanup (Unattended)' 'INFO'
        }; Description = 'Clean temp files and run disk cleanup' 
    }
)

# Main Coordinator Function
function Use-AllScriptTasks {
    Write-Log '[COORDINATION] Starting all maintenance tasks...' 'INFO'
    $global:TaskResults = @{}
    
    $totalTasks = $global:ScriptTasks.Count
    $currentTask = 0
    
    foreach ($task in $global:ScriptTasks) {
        $currentTask++
        $taskName = $task.Name
        $desc = $task.Description
        
        # Show progress bar for console, simple log for file
        $percentComplete = [math]::Round(($currentTask / $totalTasks) * 100)
        Write-TaskProgress -Activity "Windows Maintenance Tasks" -Status "Executing: $taskName" -PercentComplete $percentComplete -CurrentOperation $desc
        
        Write-Log "[COORDINATION] Executing: $taskName - $desc" 'INFO'
        $startTime = Get-Date
        try {
            $result = Invoke-Task $taskName $task.Function
            $endTime = Get-Date
            $duration = ($endTime - $startTime).TotalSeconds
            Write-Log "[COORDINATION] $taskName completed in $duration seconds. Result: $result" 'SUCCESS'
            $global:TaskResults[$taskName] = @{ Success = $result; Duration = $duration; Started = $startTime; Ended = $endTime }
        }
        catch {
            Write-Log "[COORDINATION] $taskName failed: $_" 'ERROR'
            $global:TaskResults[$taskName] = @{ Success = $false; Duration = 0; Started = $startTime; Ended = (Get-Date) }
        }
    }
    
    # Complete the progress bar
    Write-TaskProgress -Activity "Windows Maintenance Tasks" -Status "All tasks completed" -PercentComplete 100 -Completed
    Write-Log '[COORDINATION] All maintenance tasks completed.' 'SUCCESS'
}

# [PRE-TASK 0] Set up log file in the repo folder
$logPath = Join-Path $PSScriptRoot "maintenance.log"

### Modern PowerShell 7.5.2 Compatibility and Performance Functions
function Invoke-WindowsPowerShellCommand {
    param(
        [string]$Command,
        [string]$Description = "Windows PowerShell command",
        [int]$TimeoutSeconds = 300
    )
    
    Write-Log "[PS5.1] Executing via Windows PowerShell: $Description" 'INFO'
    
    try {
        # Use PowerShell 7.5.2's improved process management with timeout
        $processInfo = [System.Diagnostics.ProcessStartInfo]::new()
        $processInfo.FileName = "powershell.exe"
        $processInfo.Arguments = "-NoProfile -ExecutionPolicy Bypass -Command `"$Command`""
        $processInfo.UseShellExecute = $false
        $processInfo.RedirectStandardOutput = $true
        $processInfo.RedirectStandardError = $true
        $processInfo.CreateNoWindow = $true
        
        $process = [System.Diagnostics.Process]::Start($processInfo)
        
        # Use modern async pattern available in PowerShell 7.5.2
        $outputTask = $process.StandardOutput.ReadToEndAsync()
        $errorTask = $process.StandardError.ReadToEndAsync()
        
        $completed = $process.WaitForExit($TimeoutSeconds * 1000)
        
        if (-not $completed) {
            $process.Kill()
            Write-Log "[PS5.1] Command timed out after $TimeoutSeconds seconds: $Description" 'WARN'
            return $null
        }
        
        $output = $outputTask.Result
        $errorOutput = $errorTask.Result
        
        if ($process.ExitCode -eq 0) {
            Write-Log "[PS5.1] Successfully executed: $Description" 'INFO'
            return $output
        }
        else {
            Write-Log "[PS5.1] Command failed with exit code $($process.ExitCode): $Description" 'WARN'
            if ($errorOutput) {
                Write-Log "[PS5.1] Error output: $errorOutput" 'VERBOSE'
            }
            return $null
        }
    }
    catch {
        Write-Log "[PS5.1] Exception executing command: $_" 'ERROR'
        return $null
    }
    finally {
        if ($null -ne $process -and -not $process.HasExited) {
            try { $process.Kill() } catch { }
        }
        if ($null -ne $process) {
            $process.Dispose()
        }
    }
}

function Get-AppxPackageCompatible {
    param(
        [string]$Name = "*",
        [switch]$AllUsers
    )
    
    if ($PSVersionTable.PSVersion.Major -ge 7) {
        # Use Windows PowerShell for Appx operations with enhanced JSON parsing
        $command = @"
Import-Module Appx -ErrorAction SilentlyContinue
`$packages = Get-AppxPackage $(if ($AllUsers) { '-AllUsers' }) $(if ($Name -ne '*') { "-Name '$Name'" })
`$packages | Select-Object Name, PackageFullName, Publisher, Architecture, Version | ConvertTo-Json -Depth 3 -Compress
"@
        
        $result = Invoke-WindowsPowerShellCommand -Command $command -Description "Get AppX packages"
        if ($result) {
            try {
                # Use PowerShell 7.5.2's improved ConvertFrom-Json with better error handling
                return ($result | ConvertFrom-Json -AsHashtable:$false -ErrorAction Stop)
            }
            catch {
                Write-Log "Failed to parse AppX package JSON: $_" 'WARN'
                return @()
            }
        }
        return @()
    }
    else {
        # Native PowerShell 5.1
        if ($AllUsers) {
            return Get-AppxPackage -Name $Name -AllUsers -ErrorAction SilentlyContinue
        }
        else {
            return Get-AppxPackage -Name $Name -ErrorAction SilentlyContinue
        }
    }
}

function Remove-AppxPackageCompatible {
    param(
        [string]$PackageFullName,
        [switch]$AllUsers
    )
    
    if ($PSVersionTable.PSVersion.Major -ge 7) {
        # Use Windows PowerShell for Appx operations with better error reporting
        $command = @"
Import-Module Appx -ErrorAction SilentlyContinue
try {
    Remove-AppxPackage -Package '$PackageFullName' $(if ($AllUsers) { '-AllUsers' }) -ErrorAction Stop
    Write-Output 'SUCCESS'
} catch {
    Write-Output "ERROR: `$(`$_.Exception.Message)"
}
"@
        
        $result = Invoke-WindowsPowerShellCommand -Command $command -Description "Remove AppX package $PackageFullName"
        return $result -eq 'SUCCESS'
    }
    else {
        # Native PowerShell 5.1
        try {
            if ($AllUsers) {
                Remove-AppxPackage -Package $PackageFullName -AllUsers -ErrorAction Stop
            }
            else {
                Remove-AppxPackage -Package $PackageFullName -ErrorAction Stop
            }
            return $true
        }
        catch {
            return $false
        }
    }
}

function Get-AppxProvisionedPackageCompatible {
    param(
        [switch]$Online
    )
    
    if ($PSVersionTable.PSVersion.Major -ge 7) {
        # Use Windows PowerShell for Appx operations
        $command = "Import-Module Dism -ErrorAction SilentlyContinue; Get-AppxProvisionedPackage"
        if ($Online) { $command += " -Online" }
        $command += " | Select-Object DisplayName, PackageName | ConvertTo-Json -Depth 3"
        
        $result = Invoke-WindowsPowerShellCommand -Command $command -Description "Get provisioned AppX packages"
        if ($result) {
            try {
                return ($result | ConvertFrom-Json)
            }
            catch {
                Write-Log "Failed to parse provisioned AppX package JSON: $_" 'WARN'
                return @()
            }
        }
        return @()
    }
    else {
        # Native PowerShell 5.1
        if ($Online) {
            return Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue
        }
        else {
            return Get-AppxProvisionedPackage -ErrorAction SilentlyContinue
        }
    }
}

function Remove-AppxProvisionedPackageCompatible {
    param(
        [string]$PackageName,
        [switch]$Online
    )
    
    if ($PSVersionTable.PSVersion.Major -ge 7) {
        # Use Windows PowerShell for Appx operations
        $command = "Import-Module Dism -ErrorAction SilentlyContinue; Remove-AppxProvisionedPackage -PackageName '$PackageName'"
        if ($Online) { $command += " -Online" }
        $command += " -ErrorAction Stop"
        
        $result = Invoke-WindowsPowerShellCommand -Command $command -Description "Remove provisioned AppX package $PackageName"
        return $null -ne $result
    }
    else {
        # Native PowerShell 5.1
        try {
            if ($Online) {
                Remove-AppxProvisionedPackage -Online -PackageName $PackageName -ErrorAction Stop
            }
            else {
                Remove-AppxProvisionedPackage -PackageName $PackageName -ErrorAction Stop
            }
            return $true
        }
        catch {
            return $false
        }
    }
}

function Enable-ComputerRestoreCompatible {
    param(
        [string]$Drive
    )
    
    if ($PSVersionTable.PSVersion.Major -ge 7) {
        # Use Windows PowerShell for System Restore operations
        $command = "Enable-ComputerRestore -Drive '$Drive' -ErrorAction Stop"
        
        $result = Invoke-WindowsPowerShellCommand -Command $command -Description "Enable System Restore on $Drive"
        return $null -ne $result
    }
    else {
        # Native PowerShell 5.1
        try {
            Enable-ComputerRestore -Drive $Drive -ErrorAction Stop
            return $true
        }
        catch {
            return $false
        }
    }
}

function Checkpoint-ComputerCompatible {
    param(
        [string]$Description,
        [string]$RestorePointType = 'MODIFY_SETTINGS'
    )
    
    if ($PSVersionTable.PSVersion.Major -ge 7) {
        # Use Windows PowerShell for System Restore operations
        $command = "Checkpoint-Computer -Description '$Description' -RestorePointType '$RestorePointType' -ErrorAction Stop"
        
        $result = Invoke-WindowsPowerShellCommand -Command $command -Description "Create restore point: $Description"
        return $null -ne $result
    }
    else {
        # Native PowerShell 5.1
        try {
            Checkpoint-Computer -Description $Description -RestorePointType $RestorePointType -ErrorAction Stop
            return $true
        }
        catch {
            return $false
        }
    }
}

function Install-WindowsUpdatesCompatible {
    param()
    
    if ($PSVersionTable.PSVersion.Major -ge 7) {
        # Use Windows PowerShell for PSWindowsUpdate
        $command = @"
# Check if PSWindowsUpdate is installed
if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate -ErrorAction SilentlyContinue)) {
    try {
        Install-Module -Name PSWindowsUpdate -Force -Scope CurrentUser -Confirm:`$false -ErrorAction Stop
        Write-Host 'PSWindowsUpdate module installed successfully.'
    }
    catch {
        Write-Host "Failed to install PSWindowsUpdate module: `$_"
        exit 1
    }
}

Import-Module PSWindowsUpdate -ErrorAction Stop

# Get and install updates
try {
    `$updates = Get-WindowsUpdate -AcceptAll -Install -ErrorAction Stop
    if (`$updates) {
        `$updateTitles = `$updates | Select-Object -ExpandProperty Title -ErrorAction SilentlyContinue -Unique
        Write-Host "Installed updates: `$(`$updateTitles -join ', ')"
    }
    else {
        Write-Host 'No new updates were found or installed.'
    }
}
catch {
    Write-Host "Failed to check or install Windows Updates: `$_"
    exit 1
}
"@
        
        $result = Invoke-WindowsPowerShellCommand -Command $command -Description "Install Windows Updates"
        return $null -ne $result
    }
    else {
        # Native PowerShell 5.1
        try {
            if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate -ErrorAction SilentlyContinue)) {
                Install-Module -Name PSWindowsUpdate -Force -Scope CurrentUser -Confirm:$false -ErrorAction Stop
                Write-Log 'PSWindowsUpdate module installed successfully.' 'INFO'
            }
            
            Import-Module PSWindowsUpdate -ErrorAction Stop
            
            $updates = Get-WindowsUpdate -AcceptAll -Install -ErrorAction Stop
            if ($updates) {
                $updateTitles = $updates | Select-Object -ExpandProperty Title -ErrorAction SilentlyContinue -Unique
                Write-Log "Installed updates: $($updateTitles -join ', ')" 'INFO'
            }
            else {
                Write-Log 'No new updates were found or installed.' 'INFO'
            }
            return $true
        }
        catch {
            Write-Log "Failed to check or install Windows Updates: $_" 'WARN'
            return $false
        }
    }
}

function Get-StartAppsCompatible {
    if ($PSVersionTable.PSVersion.Major -ge 7) {
        # Use Windows PowerShell for Get-StartApps
        $command = "Get-StartApps | Select-Object Name, AppId | ConvertTo-Json -Depth 2"
        $result = Invoke-WindowsPowerShellCommand -Command $command -Description "Get Start menu apps"
        if ($result) {
            try {
                return ($result | ConvertFrom-Json)
            }
            catch {
                Write-Log "Failed to parse Start apps JSON: $_" 'WARN'
                return @()
            }
        }
        return @()
    }
    else {
        # Native PowerShell 5.1
        return Get-StartApps -ErrorAction SilentlyContinue
    }
}

### [PRE-TASK 1] Modern Logging & Task Functions with PowerShell 7.5.2 Optimizations
# ===============================
# Enhanced Logging System for PowerShell 7.5.2
# ===============================
# Separates file logging from console display, with progress bar support

function Write-LogFile {
    <#
    .SYNOPSIS
    Writes log entries to file only, without console output or progress bars.
    #>
    param(
        [string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR', 'VERBOSE')][string]$Level = 'INFO'
    )
    
    # Skip verbose messages if verbose logging is disabled
    if ($Level -eq 'VERBOSE' -and -not $global:Config.EnableVerboseLogging) {
        return
    }
    
    # Use PowerShell 7.5.2's optimized date formatting
    $timestamp = [DateTime]::Now.ToString('yyyy-MM-dd HH:mm:ss')
    $entry = "[$timestamp] [$Level] $Message"
    
    # Use PowerShell 7.5.2's improved file I/O with better encoding handling
    try {
        if ($PSVersionTable.PSVersion.Major -ge 7) {
            # Use modern async file operations for better performance
            [System.IO.File]::AppendAllText($logPath, "$entry`n", [System.Text.Encoding]::UTF8)
        }
        else {
            # Fallback for PowerShell 5.1
            $entry | Out-File -FilePath $logPath -Append -Encoding UTF8
        }
    }
    catch {
        # If file logging fails, show warning but don't interrupt execution
        Write-Warning "Failed to write to log file: $_"
    }
}

function Write-ConsoleMessage {
    <#
    .SYNOPSIS
    Writes colored messages to console only, without file logging.
    #>
    param(
        [string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR', 'VERBOSE', 'SUCCESS', 'PROGRESS')][string]$Level = 'INFO',
        [switch]$NoNewline
    )
    
    # Enhanced color-coding with PowerShell 7.5.2's improved console support
    $consoleColors = @{
        'ERROR'    = @{ ForegroundColor = 'Red'; BackgroundColor = $null }
        'WARN'     = @{ ForegroundColor = 'Yellow'; BackgroundColor = $null }
        'VERBOSE'  = @{ ForegroundColor = 'Gray'; BackgroundColor = $null }
        'INFO'     = @{ ForegroundColor = 'White'; BackgroundColor = $null }
        'SUCCESS'  = @{ ForegroundColor = 'Green'; BackgroundColor = $null }
        'PROGRESS' = @{ ForegroundColor = 'Cyan'; BackgroundColor = $null }
    }
    
    $colorParams = $consoleColors[$Level]
    $writeParams = @{
        Object = $Message
        ForegroundColor = $colorParams.ForegroundColor
    }
    
    if ($colorParams.BackgroundColor) {
        $writeParams.BackgroundColor = $colorParams.BackgroundColor
    }
    
    if ($NoNewline) {
        $writeParams.NoNewline = $true
    }
    
    Write-Host @writeParams
}

function Write-TaskProgress {
    <#
    .SYNOPSIS
    Displays progress bar for console, logs simple message to file.
    #>
    param(
        [string]$Activity,
        [string]$Status,
        [int]$PercentComplete,
        [string]$CurrentOperation = $null,
        [switch]$Completed
    )
    
    # Log simple message to file (no progress bar noise)
    if ($Completed) {
        Write-LogFile "$Activity completed" 'INFO'
    }
    else {
        Write-LogFile "$Activity - $Status" 'VERBOSE'
    }
    
    # Show progress bar in console
    if ($Completed) {
        Write-Progress -Activity $Activity -Completed
    }
    else {
        $progressParams = @{
            Activity = $Activity
            Status = $Status
            PercentComplete = $PercentComplete
        }
        
        if ($CurrentOperation) {
            $progressParams.CurrentOperation = $CurrentOperation
        }
        
        Write-Progress @progressParams
    }
}

function Write-Log {
    <#
    .SYNOPSIS
    Combined logging function - writes to both file and console.
    #>
    param(
        [string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR', 'VERBOSE', 'SUCCESS')][string]$Level = 'INFO'
    )
    
    # Write to log file
    Write-LogFile -Message $Message -Level $Level
    
    # Write to console (skip verbose if disabled)
    if ($Level -ne 'VERBOSE' -or $global:Config.EnableVerboseLogging) {
        $timestamp = [DateTime]::Now.ToString('HH:mm:ss')
        $consoleMessage = "[$timestamp] [$Level] $Message"
        Write-ConsoleMessage -Message $consoleMessage -Level $Level
    }
}

function Invoke-Task {
    param(
        [string]$TaskName,
        [scriptblock]$Action
    )
    
    Write-Log "Starting task: $TaskName" 'INFO'
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    
    try {
        # Use PowerShell 7.5.2's enhanced error handling with more detailed error records
        $ErrorActionPreference = 'Stop'
        $result = & $Action
        
        $stopwatch.Stop()
        Write-Log "Task succeeded: $TaskName (Duration: $($stopwatch.Elapsed.TotalSeconds.ToString('F2'))s)" 'INFO'
        return $true
    }
    catch {
        $stopwatch.Stop()
        # Use PowerShell 7.5.2's improved exception details
        $errorDetails = @{
            Message = $_.Exception.Message
            Type = $_.Exception.GetType().Name
            Line = $_.InvocationInfo.ScriptLineNumber
            Position = $_.InvocationInfo.OffsetInLine
        }
        
        $errorMessage = "Task failed: $TaskName (Duration: $($stopwatch.Elapsed.TotalSeconds.ToString('F2'))s). " +
                       "Error: $($errorDetails.Type) - $($errorDetails.Message) " +
                       "(Line: $($errorDetails.Line), Position: $($errorDetails.Position))"
        
        Write-Log $errorMessage 'ERROR'
        return $false
    }
    finally {
        if ($stopwatch.IsRunning) {
            $stopwatch.Stop()
        }
    }
}

### [PRE-TASK 2] Extensive System Inventory (Initial)
function Get-ExtensiveSystemInventory {
    Write-Log "[START] Extensive System Inventory (JSON Format)" 'INFO'
    Write-TaskProgress -Activity "Building System Inventory" -Status "Initializing..." -PercentComplete 5
    
    $inventoryFolder = $PSScriptRoot
    if (-not (Test-Path $inventoryFolder)) { New-Item -ItemType Directory -Path $inventoryFolder -Force | Out-Null }

    # Build structured inventory object
    $inventory = [ordered]@{
        metadata           = [ordered]@{
            generatedOn   = (Get-Date).ToString('o')
            scriptVersion = '1.0.0'
            hostname      = $env:COMPUTERNAME
            user          = $env:USERNAME
            powershell    = $PSVersionTable.PSVersion.ToString()
        }
        system             = @{}
        appx               = @()
        winget             = @()
        choco              = @()
        registry_uninstall = @()
        services           = @()
        scheduled_tasks    = @()
        drivers            = @()
        updates            = @()
    }

    Write-TaskProgress -Activity "Building System Inventory" -Status "Collecting system info..." -PercentComplete 10
    Write-LogFile "[Inventory] Collecting system info..." 'INFO'
    try {
        $systemInfo = Get-ComputerInfo
        $inventory.system = $systemInfo
        Write-LogFile "[Inventory] System info collected." 'INFO'
    }
    catch { 
        Write-LogFile "[Inventory] System info failed: $_" 'WARN'
        $inventory.system = @{ error = $_.ToString() }
    }

    Write-TaskProgress -Activity "Building System Inventory" -Status "Collecting Appx apps..." -PercentComplete 20
    Write-LogFile "[Inventory] Collecting installed Appx apps..." 'INFO'
    try {
        $appxPackages = Get-AppxPackageCompatible -AllUsers
        if ($appxPackages -and $appxPackages.Count -gt 0) {
            $inventory.appx = @($appxPackages | Select-Object Name, PackageFullName, Publisher)
            Write-LogFile "[Inventory] Collected $($inventory.appx.Count) Appx apps." 'INFO'
        }
        else {
            Write-LogFile "[Inventory] No Appx apps found or module not available." 'WARN'
            $inventory.appx = @()
        }
    }
    catch { 
        Write-LogFile "[Inventory] Appx apps failed: $_" 'WARN'
        $inventory.appx = @()
    }

    Write-TaskProgress -Activity "Building System Inventory" -Status "Collecting winget apps..." -PercentComplete 35
    Write-LogFile "[Inventory] Collecting installed winget apps..." 'INFO'
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        try {
            # Try JSON output first (modern winget versions)
            $wingetJsonRaw = winget list --accept-source-agreements --output json 2>$null | Out-String
            if ($wingetJsonRaw -and $wingetJsonRaw.Trim() -ne '') {
                # Clean the JSON output - sometimes winget returns warnings before JSON
                $jsonStartIndex = $wingetJsonRaw.IndexOf('{')
                if ($jsonStartIndex -ge 0) {
                    $cleanJson = $wingetJsonRaw.Substring($jsonStartIndex)
                    try {
                        $wingetData = $cleanJson | ConvertFrom-Json -ErrorAction Stop
                        if ($wingetData.Sources) {
                            $inventory.winget = @($wingetData.Sources | ForEach-Object { $_.Packages } | ForEach-Object {
                                    [PSCustomObject]@{
                                        Name    = $_.Name
                                        Id      = $_.Id
                                        Version = $_.InstalledVersion
                                        Source  = $_.Source
                                    }
                                })
                            Write-Log "[Inventory] Collected $($inventory.winget.Count) winget apps via JSON." 'INFO'
                        }
                        else {
                            Write-Log "[Inventory] Winget JSON output has no Sources property. Using fallback." 'WARN'
                            throw "No Sources in JSON"
                        }
                    }
                    catch {
                        Write-Log "[Inventory] Failed to parse winget JSON output: $_. Using fallback text parsing." 'WARN'
                        throw "JSON parsing failed"
                    }
                }
                else {
                    Write-Log "[Inventory] No JSON found in winget output. Using fallback text parsing." 'WARN'
                    throw "No JSON found"
                }
            }
            else {
                Write-Log "[Inventory] No winget output received. Using fallback text parsing." 'WARN'
                throw "No output"
            }
        }
        catch {
            # Fallback to text parsing when JSON fails
            try {
                Write-Log "[Inventory] Using winget text parsing fallback..." 'INFO'
                $wingetOutput = winget list --accept-source-agreements 2>$null
                if ($wingetOutput) {
                    $inventory.winget = @($wingetOutput | Where-Object { $_ -match '\S' -and $_ -notmatch '^Name|^-+|^$' } | 
                        ForEach-Object { 
                            $parts = $_ -split '\s+', 3
                            [PSCustomObject]@{
                                Name    = if ($parts.Count -gt 0) { $parts[0] } else { $_ }
                                Id      = if ($parts.Count -gt 1) { $parts[1] } else { $null }
                                Version = if ($parts.Count -gt 2) { $parts[2] } else { $null }
                                Source  = 'text-parsed'
                            }
                        })
                    Write-Log "[Inventory] Collected $($inventory.winget.Count) winget apps via text parsing." 'INFO'
                }
                else {
                    Write-Log "[Inventory] No winget output in text mode either." 'WARN'
                    $inventory.winget = @()
                }
            }
            catch {
                Write-Log "[Inventory] Winget text parsing also failed: $_" 'WARN'
                $inventory.winget = @()
            }
        }
    }
    else {
        Write-Log "[Inventory] Winget not available." 'WARN'
        $inventory.winget = @()
    }

    # Use PowerShell 7.5.2's parallel processing for better performance on multiple inventory collections
    if ($PSVersionTable.PSVersion.Major -ge 7) {
        Write-Log "[Inventory] Using parallel processing for remaining inventory collections..." 'INFO'
        
        # Define inventory collection jobs
        $inventoryJobs = @(
            @{ Name = 'choco'; Script = {
                if (Get-Command choco -ErrorAction SilentlyContinue) {
                    try {
                        $chocoOutput = choco list --local-only 2>$null
                        if ($chocoOutput) {
                            return @($chocoOutput | Where-Object { $_ -match '\S' -and $_ -notmatch '^Chocolatey|packages installed|^$' } | 
                                ForEach-Object { 
                                    $parts = $_ -split '\s+', 2
                                    [PSCustomObject]@{
                                        Name    = if ($parts.Count -gt 0) { $parts[0] } else { $_ }
                                        Version = if ($parts.Count -gt 1) { $parts[1] } else { $null }
                                    }
                                })
                        }
                    }
                    catch { return @() }
                }
                return @()
            }},
            @{ Name = 'registry'; Script = {
                $uninstallKeys = @(
                    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
                    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
                    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
                )
                try {
                    return @(foreach ($key in $uninstallKeys) {
                        Get-ChildItem $key -ErrorAction SilentlyContinue | ForEach-Object {
                            $props = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
                            if ($props.DisplayName) {
                                [PSCustomObject]@{ 
                                    DisplayName     = $props.DisplayName
                                    UninstallString = $props.UninstallString
                                    Publisher       = $props.Publisher
                                    Version         = $props.DisplayVersion
                                }
                            }
                        }
                    })
                }
                catch { return @() }
            }},
            @{ Name = 'services'; Script = {
                try {
                    return @(Get-Service -ErrorAction SilentlyContinue | Where-Object { $null -ne $_ } | 
                        Select-Object Name, Status, StartType)
                }
                catch { return @() }
            }},
            @{ Name = 'tasks'; Script = {
                try {
                    return @(Get-ScheduledTask -ErrorAction SilentlyContinue | 
                        Select-Object TaskName, TaskPath, State)
                }
                catch { return @() }
            }},
            @{ Name = 'drivers'; Script = {
                try {
                    return @(Get-CimInstance Win32_PnPSignedDriver -ErrorAction SilentlyContinue | 
                        Select-Object DeviceName, DriverVersion, Manufacturer)
                }
                catch { return @() }
            }},
            @{ Name = 'updates'; Script = {
                try {
                    return @(Get-HotFix -ErrorAction SilentlyContinue | 
                        Select-Object Description, HotFixID, InstalledOn)
                }
                catch { return @() }
            }}
        )
        
        # Execute inventory jobs in parallel using PowerShell 7.5.2's ForEach-Object -Parallel
        Write-TaskProgress -Activity "Building System Inventory" -Status "Collecting remaining data (parallel)..." -PercentComplete 50
        Write-LogFile "[Inventory] Starting parallel collection for: choco, registry, services, tasks, drivers, updates" 'INFO'
        
        $results = $inventoryJobs | ForEach-Object -Parallel {
            $job = $_
            try {
                $result = & $job.Script
                return @{ Name = $job.Name; Data = $result; Success = $true }
            }
            catch {
                return @{ Name = $job.Name; Data = @(); Success = $false; Error = $_.Exception.Message }
            }
        } -ThrottleLimit 6
        
        # Process parallel results
        Write-TaskProgress -Activity "Building System Inventory" -Status "Processing parallel results..." -PercentComplete 70
        foreach ($result in $results) {
            switch ($result.Name) {
                'choco' { 
                    $inventory.choco = $result.Data
                    if ($result.Success) { 
                        Write-LogFile "[Inventory] Collected $($inventory.choco.Count) choco apps via parallel processing." 'INFO' 
                    } else { 
                        Write-LogFile "[Inventory] Choco collection failed: $($result.Error)" 'WARN' 
                    }
                }
                'registry' { 
                    $inventory.registry_uninstall = $result.Data
                    if ($result.Success) { 
                        Write-Log "[Inventory] Collected $($inventory.registry_uninstall.Count) registry entries via parallel processing." 'INFO' 
                    } else { 
                        Write-Log "[Inventory] Registry collection failed: $($result.Error)" 'WARN' 
                    }
                }
                'services' { 
                    $inventory.services = $result.Data
                    if ($result.Success) { 
                        Write-Log "[Inventory] Collected $($inventory.services.Count) services via parallel processing." 'INFO' 
                    } else { 
                        Write-Log "[Inventory] Services collection failed: $($result.Error)" 'WARN' 
                    }
                }
                'tasks' { 
                    $inventory.scheduled_tasks = $result.Data
                    if ($result.Success) { 
                        Write-Log "[Inventory] Collected $($inventory.scheduled_tasks.Count) scheduled tasks via parallel processing." 'INFO' 
                    } else { 
                        Write-Log "[Inventory] Scheduled tasks collection failed: $($result.Error)" 'WARN' 
                    }
                }
                'drivers' { 
                    $inventory.drivers = $result.Data
                    if ($result.Success) { 
                        Write-Log "[Inventory] Collected $($inventory.drivers.Count) drivers via parallel processing." 'INFO' 
                    } else { 
                        Write-Log "[Inventory] Drivers collection failed: $($result.Error)" 'WARN' 
                    }
                }
                'updates' { 
                    $inventory.updates = $result.Data
                    if ($result.Success) { 
                        Write-Log "[Inventory] Collected $($inventory.updates.Count) updates via parallel processing." 'INFO' 
                    } else { 
                        Write-Log "[Inventory] Updates collection failed: $($result.Error)" 'WARN' 
                    }
                }
            }
        }
    }
    else {
        # Fallback sequential processing for PowerShell 5.1
        Write-Log "[Inventory] Using sequential processing (PowerShell 5.1 mode)..." 'INFO'
        
        Write-Log "[Inventory] Collecting installed choco apps..." 'INFO'
        if (Get-Command choco -ErrorAction SilentlyContinue) {
            try {
                $chocoOutput = choco list --local-only 2>$null
                if ($chocoOutput) {
                    $inventory.choco = @($chocoOutput | Where-Object { $_ -match '\S' -and $_ -notmatch '^Chocolatey|packages installed|^$' } | 
                        ForEach-Object { 
                            $parts = $_ -split '\s+', 2
                            [PSCustomObject]@{
                                Name    = if ($parts.Count -gt 0) { $parts[0] } else { $_ }
                                Version = if ($parts.Count -gt 1) { $parts[1] } else { $null }
                            }
                        })
                    Write-Log "[Inventory] Collected $($inventory.choco.Count) choco apps." 'INFO'
                }
            }
            catch { 
                Write-Log "[Inventory] Choco apps failed: $_" 'WARN'
                $inventory.choco = @()
            }
        }
        else {
            Write-Log "[Inventory] Chocolatey not available." 'WARN'
            $inventory.choco = @()
        }

        Write-Log "[Inventory] Collecting registry uninstall keys..." 'INFO'
        $uninstallKeys = @(
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
            'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
        )
        try {
            $inventory.registry_uninstall = @(foreach ($key in $uninstallKeys) {
                    Get-ChildItem $key -ErrorAction SilentlyContinue | ForEach-Object {
                        $props = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
                        if ($props.DisplayName) {
                            [PSCustomObject]@{ 
                                DisplayName     = $props.DisplayName
                                UninstallString = $props.UninstallString
                                Publisher       = $props.Publisher
                                Version         = $props.DisplayVersion
                            }
                        }
                    }
                })
            Write-Log "[Inventory] Collected $($inventory.registry_uninstall.Count) registry uninstall entries." 'INFO'
        }
        catch { 
            Write-Log "[Inventory] Registry uninstall keys failed: $_" 'WARN'
            $inventory.registry_uninstall = @()
        }

        Write-Log "[Inventory] Collecting services..." 'INFO'
        try {
            $inventory.services = @(Get-Service -ErrorAction SilentlyContinue | Where-Object { $null -ne $_ } | 
                Select-Object Name, Status, StartType)
            Write-Log "[Inventory] Collected $($inventory.services.Count) services." 'INFO'
        }
        catch { 
            Write-Log "[Inventory] Services failed: $_" 'WARN'
            $inventory.services = @()
        }

        Write-Log "[Inventory] Collecting scheduled tasks..." 'INFO'
        try {
            $inventory.scheduled_tasks = @(Get-ScheduledTask -ErrorAction SilentlyContinue | 
                Select-Object TaskName, TaskPath, State)
            Write-Log "[Inventory] Collected $($inventory.scheduled_tasks.Count) scheduled tasks." 'INFO'
        }
        catch { 
            Write-Log "[Inventory] Scheduled tasks failed: $_" 'WARN'
            $inventory.scheduled_tasks = @()
        }

        Write-Log "[Inventory] Collecting drivers..." 'INFO'
        try {
            $inventory.drivers = @(Get-CimInstance Win32_PnPSignedDriver -ErrorAction SilentlyContinue | 
                Select-Object DeviceName, DriverVersion, Manufacturer)
            Write-Log "[Inventory] Collected $($inventory.drivers.Count) drivers." 'INFO'
        }
        catch { 
            Write-Log "[Inventory] Drivers failed: $_" 'WARN'
            $inventory.drivers = @()
        }

        Write-Log "[Inventory] Collecting Windows updates..." 'INFO'
        try {
            $inventory.updates = @(Get-HotFix -ErrorAction SilentlyContinue | 
                Select-Object Description, HotFixID, InstalledOn)
            Write-Log "[Inventory] Collected $($inventory.updates.Count) Windows updates." 'INFO'
        }
        catch { 
            Write-Log "[Inventory] Windows updates failed: $_" 'WARN'
            $inventory.updates = @()
        }
    }

    Write-Log "[Inventory] Collecting registry uninstall keys..." 'INFO'
    $uninstallKeys = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
    )
    try {
        $inventory.registry_uninstall = @(foreach ($key in $uninstallKeys) {
                Get-ChildItem $key -ErrorAction SilentlyContinue | ForEach-Object {
                    $props = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
                    if ($props.DisplayName) {
                        [PSCustomObject]@{ 
                            DisplayName     = $props.DisplayName
                            UninstallString = $props.UninstallString
                            Publisher       = $props.Publisher
                            Version         = $props.DisplayVersion
                        }
                    }
                }
            })
        Write-Log "[Inventory] Collected $($inventory.registry_uninstall.Count) registry uninstall entries." 'INFO'
    }
    catch { 
        Write-Log "[Inventory] Registry uninstall keys failed: $_" 'WARN'
        $inventory.registry_uninstall = @()
    }

    Write-Log "[Inventory] Collecting services..." 'INFO'
    try {
        $inventory.services = @(Get-Service -ErrorAction SilentlyContinue | Where-Object { $null -ne $_ } | 
            Select-Object Name, Status, StartType)
        Write-Log "[Inventory] Collected $($inventory.services.Count) services." 'INFO'
    }
    catch { 
        Write-Log "[Inventory] Services failed: $_" 'WARN'
        $inventory.services = @()
    }

    Write-Log "[Inventory] Collecting scheduled tasks..." 'INFO'
    try {
        $inventory.scheduled_tasks = @(Get-ScheduledTask -ErrorAction SilentlyContinue | 
            Select-Object TaskName, TaskPath, State)
        Write-Log "[Inventory] Collected $($inventory.scheduled_tasks.Count) scheduled tasks." 'INFO'
    }
    catch { 
        Write-Log "[Inventory] Scheduled tasks failed: $_" 'WARN'
        $inventory.scheduled_tasks = @()
    }

    Write-Log "[Inventory] Collecting drivers..." 'INFO'
    try {
        $inventory.drivers = @(Get-CimInstance Win32_PnPSignedDriver -ErrorAction SilentlyContinue | 
            Select-Object DeviceName, DriverVersion, Manufacturer)
        Write-Log "[Inventory] Collected $($inventory.drivers.Count) drivers." 'INFO'
    }
    catch { 
        Write-Log "[Inventory] Drivers failed: $_" 'WARN'
        $inventory.drivers = @()
    }

    Write-Log "[Inventory] Collecting Windows updates..." 'INFO'
    try {
        $inventory.updates = @(Get-HotFix -ErrorAction SilentlyContinue | 
            Select-Object Description, HotFixID, InstalledOn)
        Write-Log "[Inventory] Collected $($inventory.updates.Count) Windows updates." 'INFO'
    }
    catch { 
        Write-Log "[Inventory] Windows updates failed: $_" 'WARN'
        $inventory.updates = @()
    }

    # Write structured inventory.json
    Write-TaskProgress -Activity "Building System Inventory" -Status "Saving inventory to file..." -PercentComplete 95
    $inventoryPath = Join-Path $inventoryFolder 'inventory.json'
    try {
        $inventory | ConvertTo-Json -Depth 6 | Out-File -FilePath $inventoryPath -Encoding UTF8
        Write-LogFile "[Inventory] Structured inventory saved to inventory.json" 'INFO'
        
        # Store global reference for diff operations
        $global:SystemInventory = $inventory
    }
    catch {
        Write-LogFile "[Inventory] Failed to write inventory.json: $_" 'WARN'
    }

    Write-TaskProgress -Activity "Building System Inventory" -Status "Inventory completed" -PercentComplete 100 -Completed
    Write-Log "[END] Extensive System Inventory (JSON Format)" 'SUCCESS'
}

### Modern Standardized Temp List Management with PowerShell 7.5.2 Optimizations
function New-StandardizedTempList {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ListType,
        
        [Parameter(Mandatory = $true)]
        [string]$Operation,
        
        [Parameter(Mandatory = $true)]
        $Data,
        
        [Parameter(Mandatory = $false)]
        [string]$Description = ""
    )
    
    # Generate standardized filename with enhanced naming
    $fileName = "temp_${ListType}_${Operation}.json"
    $filePath = Join-Path $global:TempFolder $fileName
    
    # Create enhanced metadata object with PowerShell 7.5.2 features
    $tempListData = [ordered]@{
        Metadata = [ordered]@{
            ListType = $ListType
            Operation = $Operation
            Description = $Description
            Created = [DateTime]::Now.ToString('o')
            ScriptVersion = "2.0.0"
            PowerShellVersion = $PSVersionTable.PSVersion.ToString()
            DataCount = if ($Data -is [array]) { $Data.Count } elseif ($null -eq $Data) { 0 } else { 1 }
            DataType = $Data.GetType().Name
            FileSize = 0  # Will be updated after save
        }
        Data = $Data
    }
    
    try {
        # Use PowerShell 7.5.2's enhanced JSON serialization with better performance
        if ($PSVersionTable.PSVersion.Major -ge 7) {
            $jsonContent = $tempListData | ConvertTo-Json -Depth 10 -Compress:$false -EscapeHandling EscapeNonAscii
            [System.IO.File]::WriteAllText($filePath, $jsonContent, [System.Text.Encoding]::UTF8)
        }
        else {
            # Fallback for PowerShell 5.1
            $tempListData | ConvertTo-Json -Depth 10 | Out-File $filePath -Encoding UTF8
        }
        
        # Update file size in metadata
        $fileInfo = Get-Item $filePath -ErrorAction SilentlyContinue
        if ($fileInfo) {
            $tempListData.Metadata.FileSize = $fileInfo.Length
            # Re-save with updated metadata if using modern PowerShell
            if ($PSVersionTable.PSVersion.Major -ge 7) {
                $jsonContent = $tempListData | ConvertTo-Json -Depth 10 -Compress:$false -EscapeHandling EscapeNonAscii
                [System.IO.File]::WriteAllText($filePath, $jsonContent, [System.Text.Encoding]::UTF8)
            }
        }
        
        Write-Log "Modern temp list created: $fileName (Count: $($tempListData.Metadata.DataCount), Size: $([math]::Round($tempListData.Metadata.FileSize / 1KB, 2)) KB)" 'VERBOSE'
        return $filePath
    }
    catch {
        Write-Log "Failed to create standardized temp list $fileName`: $_" 'ERROR'
        return $null
    }
}

function Get-StandardizedTempList {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath
    )
    
    if (Test-Path $FilePath) {
        try {
            # Use PowerShell 7.5.2's enhanced JSON parsing
            if ($PSVersionTable.PSVersion.Major -ge 7) {
                $jsonContent = [System.IO.File]::ReadAllText($FilePath, [System.Text.Encoding]::UTF8)
                return ($jsonContent | ConvertFrom-Json -AsHashtable:$false -ErrorAction Stop)
            }
            else {
                # Fallback for PowerShell 5.1
                $content = Get-Content $FilePath -Encoding UTF8 | Out-String
                return ($content | ConvertFrom-Json -ErrorAction Stop)
            }
        }
        catch {
            Write-Log "Failed to read standardized temp list: $FilePath - $_" 'WARN'
            return $null
        }
    }
    else {
        Write-Log "Standardized temp list not found: $FilePath" 'WARN'
        return $null
    }
}

# [PRE-TASK 3] Run inventory before anything else
Get-ExtensiveSystemInventory

### [MAIN SCRIPT STARTS HERE]

# Check if script is running as Administrator early
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Warning "This script must be run as Administrator. Exiting."
    Read-Host -Prompt 'Press Enter to exit...'
    exit 1
}

Write-Log "Script started. User: $env:USERNAME, Computer: $env:COMPUTERNAME, Script Version: 1.0.0" 'INFO'

### Load configuration FIRST (before creating lists)
$configPath = Join-Path $PSScriptRoot "config.json"
$global:Config = @{
    SkipBloatwareRemoval = $false
    SkipEssentialApps    = $false
    SkipWindowsUpdates   = $false
    SkipTelemetryDisable = $false
    SkipSystemRestore    = $false
    CustomEssentialApps  = @()
    CustomBloatwareList  = @()
    EnableVerboseLogging = $false
}

if (Test-Path $configPath) {
    try {
        $config = Get-Content $configPath | ConvertFrom-Json
        # Merge custom config with defaults
        if ($config.SkipBloatwareRemoval) { $global:Config.SkipBloatwareRemoval = $config.SkipBloatwareRemoval }
        if ($config.SkipEssentialApps) { $global:Config.SkipEssentialApps = $config.SkipEssentialApps }
        if ($config.SkipWindowsUpdates) { $global:Config.SkipWindowsUpdates = $config.SkipWindowsUpdates }
        if ($config.SkipTelemetryDisable) { $global:Config.SkipTelemetryDisable = $config.SkipTelemetryDisable }
        if ($config.SkipSystemRestore) { $global:Config.SkipSystemRestore = $config.SkipSystemRestore }
        if ($config.CustomEssentialApps) { $global:Config.CustomEssentialApps = $config.CustomEssentialApps }
        if ($config.CustomBloatwareList) { $global:Config.CustomBloatwareList = $config.CustomBloatwareList }
        if ($config.EnableVerboseLogging) { $global:Config.EnableVerboseLogging = $config.EnableVerboseLogging }
        
        Write-Log "Loaded configuration from config.json" 'INFO'
        Write-Log "Config: SkipBloatware=$($global:Config.SkipBloatwareRemoval), SkipEssential=$($global:Config.SkipEssentialApps), SkipUpdates=$($global:Config.SkipWindowsUpdates)" 'INFO'
    }
    catch {
        Write-Log "Failed to load configuration: $_" 'WARN'
    }
}
else {
    Write-Log "No config.json found. Using defaults." 'INFO'
}

### Centralized temp folder and essential/bloatware lists
# Use repo folder as temp folder for better organization
$global:TempFolder = $PSScriptRoot
if (-not (Test-Path $global:TempFolder)) {
    New-Item -ItemType Directory -Path $global:TempFolder -Force | Out-Null
}

### Enhanced comprehensive bloatware list for Windows 10/11 (2025)
$global:BloatwareList = @(
    # OEM Bloatware (Acer, ASUS, Dell, HP, Lenovo)
    'Acer.AcerPowerManagement', 'Acer.AcerQuickAccess', 'Acer.AcerUEIPFramework', 'Acer.AcerUserExperienceImprovementProgram',
    'ASUS.ASUSGiftBox', 'ASUS.ASUSLiveUpdate', 'ASUS.ASUSSplendidVideoEnhancementTechnology', 'ASUS.ASUSWebStorage',
    'ASUS.ASUSZenAnywhere', 'ASUS.ASUSZenLink', 'ASUS.MyASUS', 'ASUS.GlideX', 'ASUS.ASUSDisplayControl',
    'Dell.CustomerConnect', 'Dell.DellDigitalDelivery', 'Dell.DellFoundationServices', 'Dell.DellHelpAndSupport', 
    'Dell.DellMobileConnect', 'Dell.DellPowerManager', 'Dell.DellProductRegistration', 'Dell.DellSupportAssist', 
    'Dell.DellUpdate', 'Dell.MyDell', 'Dell.DellOptimizer', 'Dell.CommandUpdate',
    'HP.HP3DDriveGuard', 'HP.HPAudioSwitch', 'HP.HPClientSecurityManager', 'HP.HPConnectionOptimizer',
    'HP.HPDocumentation', 'HP.HPDropboxPlugin', 'HP.HPePrintSW', 'HP.HPJumpStart', 'HP.HPJumpStartApps',
    'HP.HPJumpStartLaunch', 'HP.HPRegistrationService', 'HP.HPSupportSolutionsFramework', 'HP.HPSureConnect',
    'HP.HPSystemEventUtility', 'HP.HPWelcome', 'HP.HPSmart', 'HP.HPQuickActions', 'HewlettPackard.SupportAssistant',
    'Lenovo.AppExplorer', 'Lenovo.LenovoCompanion', 'Lenovo.LenovoExperienceImprovement', 'Lenovo.LenovoFamilyCloud',
    'Lenovo.LenovoHotkeys', 'Lenovo.LenovoMigrationAssistant', 'Lenovo.LenovoModernIMController',
    'Lenovo.LenovoServiceBridge', 'Lenovo.LenovoSolutionCenter', 'Lenovo.LenovoUtility', 'Lenovo.LenovoVantage',
    'Lenovo.LenovoVoice', 'Lenovo.LenovoWiFiSecurity', 'Lenovo.LenovoNow', 'Lenovo.ImController.PluginHost',

    # Gaming and Social Apps
    'king.com.BubbleWitch', 'king.com.BubbleWitch3Saga', 'king.com.CandyCrush', 'king.com.CandyCrushFriends', 
    'king.com.CandyCrushSaga', 'king.com.CandyCrushSodaSaga', 'king.com.FarmHeroes', 'king.com.FarmHeroesSaga',
    'Gameloft.MarchofEmpires', 'G5Entertainment.HiddenCity', 'RandomSaladGamesLLC.SimpleSolitaire',
    'RoyalRevolt2.RoyalRevolt2', 'WildTangent.WildTangentGamesApp', 'WildTangent.WildTangentHelper',
    'Facebook.Facebook', 'Instagram.Instagram', 'LinkedIn.LinkedIn', 'TikTok.TikTok', 'Twitter.Twitter',
    'Discord.Discord', 'Snapchat.Snapchat', 'Telegram.TelegramDesktop',

    # Microsoft Built-in Bloatware
    'Microsoft.3DBuilder', 'Microsoft.Microsoft3DViewer', 'Microsoft.Print3D', 'Microsoft.Paint3D',
    'Microsoft.BingFinance', 'Microsoft.BingFoodAndDrink', 'Microsoft.BingHealthAndFitness', 'Microsoft.BingNews', 
    'Microsoft.BingSports', 'Microsoft.BingTravel', 'Microsoft.BingWeather', 'Microsoft.MSN',
    'Microsoft.GetHelp', 'Microsoft.Getstarted', 'Microsoft.HelpAndTips', 'Microsoft.WindowsTips',
    'Microsoft.MicrosoftOfficeHub', 'Microsoft.MicrosoftPowerBIForWindows', 'Microsoft.Office.OneNote', 
    'Microsoft.Office.Sway', 'Microsoft.OneConnect', 'Microsoft.People', 'Microsoft.ScreenSketch',
    'Microsoft.StickyNotes', 'Microsoft.Whiteboard', 'Microsoft.MicrosoftSolitaireCollection',
    'Microsoft.WindowsFeedback', 'Microsoft.WindowsFeedbackHub', 'Microsoft.WindowsMaps', 'Microsoft.WindowsReadingList',
    'Microsoft.WindowsSoundRecorder', 'Microsoft.SoundRecorder', 'Microsoft.NetworkSpeedTest', 'Microsoft.News',
    'Microsoft.PowerAutomateDesktop', 'Microsoft.ToDo', 'Microsoft.Wallet', 'Microsoft.MinecraftUWP', 
    'Microsoft.MixedReality.Portal', 'Microsoft.MinecraftEducationEdition',
    
    # Xbox and Gaming
    'Microsoft.Xbox.TCUI', 'Microsoft.XboxApp', 'Microsoft.XboxGameOverlay', 'Microsoft.XboxGamingOverlay', 
    'Microsoft.XboxIdentityProvider', 'Microsoft.XboxSpeechToTextOverlay', 'Microsoft.GamingApp', 
    'Microsoft.GamingServices', 'Microsoft.XboxGameCallableUI',
    
    # Media Apps
    'Microsoft.ZuneMusic', 'Microsoft.ZuneVideo', 'Microsoft.Groove', 'Microsoft.Movies', 'Microsoft.Music',
    'Spotify.Spotify', 'Amazon.AmazonPrimeVideo', 'Netflix.Netflix', 'Hulu.Hulu', 'Disney.DisneyPlus',
    'SlingTV.Sling', 'Pandora.Pandora', 'iHeartRadio.iHeartRadio',
    
    # Communication Apps (Skype variants)
    'Microsoft.SkypeApp', 'Microsoft.Skype', 'Skype.Skype',
    
    # Office and Productivity (Bloatware versions)
    'Microsoft.Office.Desktop', 'Microsoft.OfficeHub',
    
    # Windows 11 Specific Bloatware
    'Microsoft.WindowsAlarms', 'Microsoft.Clipchamp',
    'Microsoft.PowerToys', 'Microsoft.WidgetsPlatformRuntime', 'Microsoft.Widgets', 
    
    # Security and Antivirus Bloatware
    'Avast.AvastFreeAntivirus', 'AVG.AVGAntiVirusFree', 'Avira.Avira', 
    'ESET.ESETNOD32Antivirus', 'Kaspersky.Kaspersky', 'McAfee.LiveSafe', 'McAfee.Livesafe', 
    'McAfee.SafeConnect', 'McAfee.Security', 'McAfee.WebAdvisor', 'Norton.OnlineBackup', 'Norton.Security',
    'Norton.NortonSecurity', 'Malwarebytes.Malwarebytes', 'IOBit.AdvancedSystemCare', 'IOBit.DriverBooster',
    'Piriform.CCleaner', 'PCAccelerate.PCAcceleratePro', 'PCOptimizer.PCOptimizerPro', 'Reimage.ReimageRepair',
    
    # Browsers (Alternative/Bloatware)
    'Opera.Opera', 'Opera.OperaGX', 'BraveSoftware.BraveBrowser', 'VivaldiTechnologies.Vivaldi',
    'Mozilla.SeaMonkey', 'TheTorProject.TorBrowser', 'Yandex.YandexBrowser', 'UCWeb.UCBrowser',
    'Baidu.BaiduBrowser', 'Sogou.SogouExplorer', 'SRWare.Iron', 'Maxthon.Maxthon', 'Lunascape.Lunascape',
    'AvantBrowser.AvantBrowser', 'CentBrowser.CentBrowser', 'Cliqz.Cliqz', 'Coowon.Coowon', 'CoolNovo.CoolNovo',
    'Dooble.Dooble', 'GhostBrowser.GhostBrowser', 'OtterBrowser.OtterBrowser', 'PaleMoon.PaleMoon',
    'Polarity.Polarity', 'QupZilla.QupZilla', 'QuteBrowser.QuteBrowser', 'Sleipnir.Sleipnir',
    'Sputnik.Sputnik', 'Superbird.Superbird', 'TorchMediaInc.Torch', 'Waterfox.Waterfox',
    'Blisk.Blisk', 'FenrirInc.Sleipnir', 'FlashPeak.SlimBrowser', 'FlashPeak.Slimjet',
    'Astian.Midori', 'Basilisk.Basilisk', 'DigitalPersona.EpicPrivacyBrowser', 'KDE.Falkon', 'Orbitum.Orbitum',
    
    # Adobe Bloatware
    'Adobe.AdobeCreativeCloud', 'Adobe.AdobeExpress', 'Adobe.AdobeGenuineService', 'Adobe.PhotoshopExpress',
    
    # E-commerce and Shopping
    'Amazon.Amazon', 'Amazon.Kindle', 'eBay.eBay', 'Booking.com.Booking', 'TripAdvisor.TripAdvisor',
    'Alibaba.AliExpress', 'Wish.Wish', 'Groupon.Groupon',
    
    # VPN and Privacy
    'ExpressVPN.ExpressVPN', 'NordVPN.NordVPN', 'CyberGhost.CyberGhost', 'Surfshark.Surfshark',
    'ProtonVPN.ProtonVPN', 'HotspotShield.HotspotShield', 'TunnelBear.TunnelBear',
    
    # Cloud Storage and Sync (Bloatware versions)
    'Dropbox.Dropbox', 'Google.GoogleDrive', 'Box.Box', 'pCloud.pCloud', 'Mega.Mega',
    
    # Multimedia and Photo
    'Foxit.FoxitPDFReader', 'CyberLink.MediaSuite', 'CyberLink.Power2Go', 'CyberLink.PowerDirector', 
    'CyberLink.PowerDVD', 'CyberLink.YouCam', 'Power2Go.Power2Go', 'PowerDirector.PowerDirector',
    'PicsArt.PicsartPhotoStudio', 'ThumbmunkeysLtd.PhototasticCollage', 'Adobe.PhotoshopElements',
    
    # Note-taking and Organization
    'Evernote.Evernote', 'Notion.Notion', 'Obsidian.Obsidian', 'Joplin.Joplin',
    
    # Office Alternatives (Bloatware)
    'WPSOffice.WPSOffice', 'Kingsoft.WPSOffice', 'Kingsoft.Writer', 'Kingsoft.Presentation', 
    'Kingsoft.Spreadsheets', 'Apache.OpenOffice', 'SoftMaker.FreeOffice',
    
    # Driver and System Tools (Bloatware)
    'DriverPack.DriverPackSolution', 'DriverEasy.DriverEasy', 'SlimWare.DriverUpdate',
    'Advanced.SystemCare', 'IObit.Uninstaller', 'Glary.Utilities', 'Wise.WiseCleanerPro',
    
    # Password Managers (Bloatware versions)
    'KeeperSecurity.Keeper', 'NortonLifeLock.NortonPasswordManager', 'McAfee.TrueKey',
    
    # System Utilities (Bloatware)
    'WinZip.WinZip', 'PeaZip.PeaZip', 'Bandizip.Bandizip',
    
    # Financial and Trading
    'Robinhood.Robinhood', 'Coinbase.Coinbase', 'Binance.Binance', 'PayPal.PayPal', 
    
    # News and Information
    'Microsoft.BingNews', 'CNN.CNN', 'BBC.BBC', 'Reuters.Reuters', 'Associated.Press', 
    
    # Weather Apps
    'Weather.Weather', 'AccuWeather.AccuWeather', 'WeatherChannel.WeatherChannel', 
    
    # Travel and Navigation
    'Uber.Uber', 'Lyft.Lyft', 'Maps.Maps', 'Waze.Waze', 'Google.Maps',
    
    # Fitness and Health
    'Fitbit.Fitbit', 'MyFitnessPal.MyFitnessPal', 'Strava.Strava', 'Nike.Nike',
    
    # Windows Store and Xbox related
    'Microsoft.StorePurchaseApp', 'Microsoft.DesktopAppInstaller',
    
    # Telemetry and Data Collection
    'Microsoft.Advertising.Xaml', 'Microsoft.Services.Store.Engagement'
    
    
) | Sort-Object -Unique

# Add custom bloatware from config if any
if ($global:Config.CustomBloatwareList -and $global:Config.CustomBloatwareList.Count -gt 0) {
    $global:BloatwareList += $global:Config.CustomBloatwareList
    $global:BloatwareList = $global:BloatwareList | Sort-Object -Unique
    Write-Log "Added $($global:Config.CustomBloatwareList.Count) custom bloatware entries from config" 'INFO'
}

# Create standardized temp lists with consistent naming and metadata
New-StandardizedTempList -ListType "bloatware" -Operation "main_list" -Data $global:BloatwareList -Description "Complete bloatware list including custom entries from config"

### Essential Apps List
$global:EssentialApps = @(
    @{ Name = 'Adobe Acrobat Reader'; Winget = 'Adobe.Acrobat.Reader.64-bit'; Choco = 'adobereader' },
    @{ Name = 'Google Chrome'; Winget = 'Google.Chrome'; Choco = 'googlechrome' },
    @{ Name = 'Mozilla Firefox'; Winget = 'Mozilla.Firefox'; Choco = 'firefox' },
    @{ Name = 'Mozilla Thunderbird'; Winget = 'Mozilla.Thunderbird'; Choco = 'thunderbird' },
    @{ Name = 'Microsoft Edge'; Winget = 'Microsoft.Edge'; Choco = 'microsoft-edge' },
    @{ Name = 'Total Commander'; Winget = 'Ghisler.TotalCommander'; Choco = 'totalcommander' },
    @{ Name = 'PowerShell 7'; Winget = 'Microsoft.Powershell'; Choco = 'powershell' },
    @{ Name = 'Windows Terminal'; Winget = 'Microsoft.WindowsTerminal'; Choco = 'microsoft-windows-terminal' },
    @{ Name = 'WinRAR'; Winget = 'RARLab.WinRAR'; Choco = 'winrar' },
    @{ Name = '7-Zip'; Winget = '7zip.7zip'; Choco = '7zip' },
    @{ Name = 'Notepad++'; Winget = 'Notepad++.Notepad++'; Choco = 'notepadplusplus' },
    @{ Name = 'PDF24 Creator'; Winget = 'PDF24.PDF24Creator'; Choco = 'pdf24' },
    @{ Name = 'Java 8 Update'; Winget = 'Oracle.JavaRuntimeEnvironment'; Choco = 'javaruntime' }
)

# Add custom essential apps from config if any
if ($global:Config.CustomEssentialApps -and $global:Config.CustomEssentialApps.Count -gt 0) {
    $global:EssentialApps += $global:Config.CustomEssentialApps
    Write-Log "Added $($global:Config.CustomEssentialApps.Count) custom essential apps from config" 'INFO'
}

# Save main essential apps list using standardized temp list function
New-StandardizedTempList -ListType "essential" -Operation "main_list" -Data $global:EssentialApps -Description "Complete essential apps list including custom entries from config"

### Load configuration (if exists)
# Configuration is now loaded at the top of the script before list creation

### Check Windows version and compatibility
$os = Get-CimInstance Win32_OperatingSystem
$osVersion = $os.Version
$osCaption = $os.Caption
Write-Log "Detected Windows version: $osCaption ($osVersion)" 'INFO'
if ($osVersion -lt '10.0') {
    Write-Log "Unsupported Windows version. Exiting." 'ERROR'
    exit 2
}

### PowerShell-specific Dependency Management
function Test-PowerShellDependencies {
    param()
    
    Write-Log '[DEPENDENCIES] Verifying PowerShell-specific dependencies...' 'INFO'
    Write-Log "[DEPENDENCIES] Running PowerShell version: $($PSVersionTable.PSVersion.ToString())" 'INFO'
    $dependencyStatus = @{}
    
    # Test Module Availability (with PowerShell 7 compatibility notes)
    $modules = @(
        @{ Name = 'Appx'; Critical = $false; Description = 'UWP/Store app management (via Windows PowerShell)' },
        @{ Name = 'PSWindowsUpdate'; Critical = $false; Description = 'Windows Update management (via Windows PowerShell)' },
        @{ Name = 'DISM'; Critical = $false; Description = 'Windows image servicing' }
    )
    
    foreach ($module in $modules) {
        $moduleName = $module.Name
        
        if ($PSVersionTable.PSVersion.Major -ge 7) {
            # For PowerShell 7, check if Windows PowerShell can access these modules
            if ($moduleName -in @('Appx', 'PSWindowsUpdate')) {
                try {
                    $testCommand = "Get-Module -ListAvailable -Name $moduleName -ErrorAction SilentlyContinue | Select-Object Name"
                    $result = Invoke-WindowsPowerShellCommand -Command $testCommand -Description "Test $moduleName availability"
                    $available = $null -ne $result
                }
                catch {
                    $available = $false
                }
                $dependencyStatus[$moduleName] = $available
                
                if ($available) {
                    Write-Log "[DEPENDENCIES] Module '$moduleName' is available via Windows PowerShell" 'VERBOSE'
                }
                else {
                    $level = if ($module.Critical) { 'ERROR' } else { 'WARN' }
                    Write-Log "[DEPENDENCIES] Module '$moduleName' is not available ($($module.Description))" $level
                }
            }
            else {
                # Regular module check for PowerShell 7 compatible modules
                $available = $null -ne (Get-Module -ListAvailable -Name $moduleName -ErrorAction SilentlyContinue)
                $dependencyStatus[$moduleName] = $available
                
                if ($available) {
                    Write-Log "[DEPENDENCIES] Module '$moduleName' is available" 'VERBOSE'
                }
                else {
                    $level = if ($module.Critical) { 'ERROR' } else { 'WARN' }
                    Write-Log "[DEPENDENCIES] Module '$moduleName' is not available ($($module.Description))" $level
                }
            }
        }
        else {
            # Windows PowerShell 5.1 - native check
            $available = $null -ne (Get-Module -ListAvailable -Name $moduleName -ErrorAction SilentlyContinue)
            $dependencyStatus[$moduleName] = $available
            
            if ($available) {
                Write-Log "[DEPENDENCIES] Module '$moduleName' is available" 'VERBOSE'
            }
            else {
                $level = if ($module.Critical) { 'ERROR' } else { 'WARN' }
                Write-Log "[DEPENDENCIES] Module '$moduleName' is not available ($($module.Description))" $level
            }
        }
    }
    
    # Test Command Availability
    $commands = @(
        @{ Name = 'winget'; Critical = $false; Description = 'Windows Package Manager' },
        @{ Name = 'choco'; Critical = $false; Description = 'Chocolatey Package Manager' },
        @{ Name = 'dism'; Critical = $true; Description = 'Windows Image Servicing' }
    )
    
    foreach ($command in $commands) {
        $commandName = $command.Name
        $available = $null -ne (Get-Command $commandName -ErrorAction SilentlyContinue)
        $dependencyStatus[$commandName] = $available
        
        if ($available) {
            Write-Log "[DEPENDENCIES] Command '$commandName' is available" 'VERBOSE'
        }
        else {
            $level = if ($command.Critical) { 'ERROR' } else { 'WARN' }
            Write-Log "[DEPENDENCIES] Command '$commandName' is not available ($($command.Description))" $level
        }
    }
    
    # Set global dependency flags for graceful degradation
    $global:HasWinget = $dependencyStatus['winget']
    $global:HasChocolatey = $dependencyStatus['choco']
    $global:HasAppxModule = $dependencyStatus['Appx']
    $global:HasPSWindowsUpdate = $dependencyStatus['PSWindowsUpdate']
    $global:HasDISM = $dependencyStatus['DISM'] -and $dependencyStatus['dism']
    
    # Summary report
    $working = ($dependencyStatus.GetEnumerator() | Where-Object { $_.Value } | Measure-Object).Count
    $total = $dependencyStatus.Count
    $missing = $total - $working
    
    Write-Log "[DEPENDENCIES] Status: $working/$total dependencies available" 'INFO'
    if ($missing -gt 0) {
        $missingList = ($dependencyStatus.GetEnumerator() | Where-Object { -not $_.Value } | ForEach-Object { $_.Key }) -join ', '
        Write-Log "[DEPENDENCIES] Missing: $missingList" 'WARN'
        Write-Log "[DEPENDENCIES] Some features will use graceful degradation" 'INFO'
    }
    else {
        Write-Log "[DEPENDENCIES] All dependencies are available" 'INFO'
    }
    
    return $dependencyStatus
}

function Import-ModuleWithGracefulFallback {
    param(
        [string]$ModuleName,
        [string]$FallbackMessage = "Module not available, skipping operations"
    )
    
    if (Get-Module -ListAvailable -Name $ModuleName -ErrorAction SilentlyContinue) {
        try {
            Import-Module $ModuleName -ErrorAction Stop
            Write-Log "[MODULE] Successfully imported $ModuleName" 'VERBOSE'
            return $true
        }
        catch {
            Write-Log "[MODULE] Failed to import $ModuleName : $_" 'WARN'
            return $false
        }
    }
    else {
        Write-Log "[MODULE] $ModuleName not available. $FallbackMessage" 'WARN'
        return $false
    }
}

# Initialize dependency status
$global:DependencyStatus = Test-PowerShellDependencies

### Check for required PowerShell version

if ($PSVersionTable.PSVersion.Major -lt 5) {
    Write-Log "PowerShell 5.1 or higher is required. Exiting." 'ERROR'
    exit 3
}

# Log PowerShell version and compatibility mode
if ($PSVersionTable.PSVersion.Major -ge 7) {
    Write-Log "Running in PowerShell 7+ compatibility mode. Legacy operations will use Windows PowerShell 5.1." 'INFO'
}
else {
    Write-Log "Running in Windows PowerShell 5.1 native mode." 'INFO'
}



### Modern Package Manager Wrapper with PowerShell 7.5.2 Process Improvements
function Invoke-ModernPackageManager {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('winget', 'choco')]
        [string]$PackageManager,
        
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,
        
        [Parameter(Mandatory = $false)]
        [string]$Description = "Package manager operation",
        
        [Parameter(Mandatory = $false)]
        [int]$TimeoutSeconds = 300,
        
        [Parameter(Mandatory = $false)]
        [switch]$ReturnOutput
    )
    
    $executable = switch ($PackageManager) {
        'winget' { 'winget.exe' }
        'choco' { 'choco.exe' }
    }
    
    if (-not (Get-Command $executable -ErrorAction SilentlyContinue)) {
        Write-Log "Package manager '$PackageManager' not available" 'WARN'
        return @{ Success = $false; ExitCode = -1; Output = ''; Error = "Package manager not found" }
    }
    
    try {
        if ($PSVersionTable.PSVersion.Major -ge 7) {
            # Use PowerShell 7.5.2's improved process management
            $processInfo = [System.Diagnostics.ProcessStartInfo]::new()
            $processInfo.FileName = $executable
            $processInfo.Arguments = $Arguments -join ' '
            $processInfo.UseShellExecute = $false
            $processInfo.RedirectStandardOutput = $true
            $processInfo.RedirectStandardError = $true
            $processInfo.CreateNoWindow = $true
            $processInfo.WorkingDirectory = $env:TEMP
            
            Write-Log "[$PackageManager] Executing: $executable $($processInfo.Arguments)" 'VERBOSE'
            
            $process = [System.Diagnostics.Process]::Start($processInfo)
            
            # Use async operations for better performance
            $outputTask = $process.StandardOutput.ReadToEndAsync()
            $errorTask = $process.StandardError.ReadToEndAsync()
            
            $completed = $process.WaitForExit($TimeoutSeconds * 1000)
            
            if (-not $completed) {
                $process.Kill()
                Write-Log "[$PackageManager] Operation timed out after $TimeoutSeconds seconds: $Description" 'WARN'
                return @{ Success = $false; ExitCode = -2; Output = ''; Error = "Operation timed out" }
            }
            
            $output = $outputTask.Result
            $errorOutput = $errorTask.Result
            $exitCode = $process.ExitCode
            
            Write-Log "[$PackageManager] Completed with exit code: $exitCode" 'VERBOSE'
            
            $result = @{
                Success = ($exitCode -eq 0)
                ExitCode = $exitCode
                Output = if ($ReturnOutput) { $output } else { '' }
                Error = $errorOutput
            }
            
            if ($exitCode -ne 0) {
                Write-Log "[$PackageManager] Failed with exit code $exitCode. Error: $errorOutput" 'WARN'
            }
            
            return $result
        }
        else {
            # Fallback for PowerShell 5.1
            Write-Log "[$PackageManager] Using legacy process execution (PS 5.1)" 'VERBOSE'
            $process = Start-Process -FilePath $executable -ArgumentList $Arguments -NoNewWindow -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput "$env:TEMP\pkg_out.txt" -RedirectStandardError "$env:TEMP\pkg_err.txt"
            
            $output = if (Test-Path "$env:TEMP\pkg_out.txt") { Get-Content "$env:TEMP\pkg_out.txt" -Raw } else { '' }
            $errorOutput = if (Test-Path "$env:TEMP\pkg_err.txt") { Get-Content "$env:TEMP\pkg_err.txt" -Raw } else { '' }
            
            # Cleanup temp files
            Remove-Item "$env:TEMP\pkg_out.txt", "$env:TEMP\pkg_err.txt" -ErrorAction SilentlyContinue
            
            return @{
                Success = ($process.ExitCode -eq 0)
                ExitCode = $process.ExitCode
                Output = if ($ReturnOutput) { $output } else { '' }
                Error = $errorOutput
            }
        }
    }
    catch {
        Write-Log "[$PackageManager] Exception during execution: $_" 'ERROR'
        return @{ Success = $false; ExitCode = -3; Output = ''; Error = $_.Exception.Message }
    }
    finally {
        if ($null -ne $process -and -not $process.HasExited) {
            try { $process.Kill() } catch { }
        }
        if ($null -ne $process) {
            $process.Dispose()
        }
    }
}

### [TASK 2] Install Essential Apps - Enhanced with Modern Package Management
function Install-EssentialApps {
    # ===============================
    # Task: InstallEssentialApps
    # ===============================
    # Purpose: Installs essential applications using diff-based comparison with inventory.
    # Environment: Windows 10/11, must run as Administrator, supports config-driven custom app lists.
    # Logic: Compare essential apps list against inventory, only install what's missing.
    Write-Log "[START] Install Essential Apps (Diff-Based Approach)" 'INFO'

    # Use global inventory if available, otherwise build a quick one
    if (-not $global:SystemInventory) {
        Write-Log "[EssentialApps] No system inventory available, building quick inventory..." 'WARN'
        Get-ExtensiveSystemInventory
    }
    
    $inventory = $global:SystemInventory
    Write-Log "[EssentialApps] Using inventory with $($inventory.appx.Count) AppX, $($inventory.winget.Count) Winget, $($inventory.choco.Count) Choco, $($inventory.registry_uninstall.Count) registry apps" 'INFO'

    # Build comprehensive list of all installed app identifiers for matching
    $installedIdentifiers = @()
    
    # Add AppX package names
    $inventory.appx | ForEach-Object {
        if ($_.Name) { $installedIdentifiers += $_.Name }
    }
    
    # Add Winget app names and IDs
    $inventory.winget | ForEach-Object {
        if ($_.Name) { $installedIdentifiers += $_.Name }
        if ($_.Id) { $installedIdentifiers += $_.Id }
    }
    
    # Add Chocolatey app names
    $inventory.choco | ForEach-Object {
        if ($_.Name) { $installedIdentifiers += $_.Name }
    }
    
    # Add registry app display names
    $inventory.registry_uninstall | ForEach-Object {
        if ($_.DisplayName) { $installedIdentifiers += $_.DisplayName }
    }
    
    # Remove duplicates and create lookup for faster matching
    $installedIdentifiers = $installedIdentifiers | Where-Object { $null -ne $_ -and $_ -ne '' } | Sort-Object -Unique
    Write-Log "[EssentialApps] Total unique installed identifiers: $($installedIdentifiers.Count)" 'INFO'

    # Find essential apps that are NOT installed (diff operation)
    $appsToInstall = @()
    foreach ($essentialApp in $global:EssentialApps) {
        $found = $false
        foreach ($installed in $installedIdentifiers) {
            # Enhanced matching: check Name, Winget ID, Choco ID, and partial matches
            if (
                ($essentialApp.Name -and ($installed -like "*$($essentialApp.Name)*" -or $installed -eq $essentialApp.Name)) -or
                ($essentialApp.Winget -and ($installed -eq $essentialApp.Winget -or $installed -like "*$($essentialApp.Winget)*")) -or
                ($essentialApp.Choco -and ($installed -eq $essentialApp.Choco -or $installed -like "*$($essentialApp.Choco)*")) -or
                ($essentialApp.Name -and $installed -like "*$($essentialApp.Name.Split(' ')[0])*")
            ) {
                $found = $true
                break
            }
        }
        if (-not $found) {
            $appsToInstall += $essentialApp
        }
    }

    Write-Log "[EssentialApps] Diff analysis: $($appsToInstall.Count) essential apps need installation (out of $($global:EssentialApps.Count) total in list)" 'INFO'

    # Save diff lists using standardized temp list functions
    New-StandardizedTempList -ListType "essential" -Operation "to_install" -Data $appsToInstall -Description "Essential apps that need to be installed"
    
    # Save already installed apps list
    $appsAlreadyInstalled = $global:EssentialApps | Where-Object { 
        $currentApp = $_
        $found = $false
        foreach ($toInstall in $appsToInstall) {
            if ($toInstall.Name -eq $currentApp.Name) {
                $found = $true
                break
            }
        }
        return -not $found
    }
    New-StandardizedTempList -ListType "essential" -Operation "already_installed" -Data $appsAlreadyInstalled -Description "Essential apps already installed on system"

    if ($appsToInstall.Count -eq 0) {
        Write-Log "[EssentialApps] All essential apps already installed. Skipping installation process." 'INFO'
        Write-Log "[END] Install Essential Apps" 'INFO'
        return
    }

    # Log the apps that will be installed
    Write-Log "[EssentialApps] Apps targeted for installation:" 'INFO'
    $appsToInstall | ForEach-Object { Write-Log "  - $($_.Name)" 'VERBOSE' }

    $success = 0
    $fail = 0
    $skipped = 0
    $detailedResults = @()
    $totalApps = $appsToInstall.Count
    $currentApp = 0

    foreach ($app in $appsToInstall) {
        $currentApp++
        $percentComplete = [math]::Round(($currentApp / $totalApps) * 100)
        Write-TaskProgress -Activity "Installing Essential Apps" -Status "Installing: $($app.Name)" -PercentComplete $percentComplete -CurrentOperation "$currentApp of $totalApps apps"
        
        $installSuccess = $false
        $installMethod = ""
        $wingetAvailable = Get-Command winget -ErrorAction SilentlyContinue
        $chocoAvailable = Get-Command choco -ErrorAction SilentlyContinue
        
        try {
            # Try Winget first (preferred) using modern package manager
            if ($app.Winget -and $wingetAvailable) {
                Write-LogFile "Installing $($app.Name) via winget..." 'INFO'
                $wingetArgs = @("install", "--id", $app.Winget, "--accept-source-agreements", "--accept-package-agreements", "--silent", "-e")
                $result = Invoke-ModernPackageManager -PackageManager 'winget' -Arguments $wingetArgs -Description "Install $($app.Name)"
                
                if ($result.Success) {
                    $installSuccess = $true
                    $installMethod = "winget"
                    Write-LogFile "Successfully installed $($app.Name) via winget" 'INFO'
                }
                else {
                    Write-LogFile "$($app.Name) winget install failed with exit code $($result.ExitCode): $($result.Error)" 'WARN'
                }
            }
            
            # Try Chocolatey as fallback using modern package manager
            if (-not $installSuccess -and $app.Choco -and $chocoAvailable) {
                Write-LogFile "Installing $($app.Name) via choco..." 'INFO'
                $chocoArgs = @("install", $app.Choco, "-y", "--no-progress", "--limit-output")
                $result = Invoke-ModernPackageManager -PackageManager 'choco' -Arguments $chocoArgs -Description "Install $($app.Name)"
                
                if ($result.Success) {
                    $installSuccess = $true
                    $installMethod = "choco"
                    Write-LogFile "Successfully installed $($app.Name) via choco" 'INFO'
                }
                else {
                    Write-LogFile "$($app.Name) choco install failed with exit code $($result.ExitCode): $($result.Error)" 'WARN'
                }
            }
            
            # Log results
            if ($installSuccess) {
                Write-Log "Installed: $($app.Name) via $installMethod" 'SUCCESS'
                $success++
                $detailedResults += "SUCCESS: $($app.Name) via $installMethod"
            }
            elseif (-not $wingetAvailable -and -not $chocoAvailable) {
                Write-Log "Skipped installation of $($app.Name): No package manager available (winget/choco missing)" 'WARN'
                $skipped++
                $detailedResults += "SKIPPED: $($app.Name) (no package manager available)"
            }
            else {
                Write-Log "Failed to install $($app.Name) (no available installer succeeded)" 'WARN'
                $fail++
                $detailedResults += "FAIL: $($app.Name) (installer failed)"
            }
        }
        catch {
            Write-Log "Exception during install of $($app.Name): $_" 'ERROR'
            $fail++
            $detailedResults += "FAIL: $($app.Name) (exception: $_)"
        }
    }

    # Office check and LibreOffice fallback
    $officeInstalled = $false
    try {
        # Check for Office in inventory first
        $officeKeywords = @('Office', 'Word', 'Excel', 'PowerPoint', 'Outlook', 'Microsoft Office')
        foreach ($keyword in $officeKeywords) {
            $foundInRegistry = $inventory.registry_uninstall | Where-Object { $_.DisplayName -like "*$keyword*" }
            $foundInWinget = $inventory.winget | Where-Object { $_.Name -like "*$keyword*" -or $_.Id -like "*$keyword*" }
            $foundInAppx = $inventory.appx | Where-Object { $_.Name -like "*$keyword*" }
            
            if ($foundInRegistry -or $foundInWinget -or $foundInAppx) {
                $officeInstalled = $true
                Write-Log "Office detected in inventory: $keyword" 'INFO'
                break
            }
        }
        
        # Fallback: check registry keys directly
        if (-not $officeInstalled) {
            $officeKeys = @(
                'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration',
                'HKLM:\SOFTWARE\Microsoft\Office\16.0\Common\InstallRoot',
                'HKLM:\SOFTWARE\Microsoft\Office\15.0\Common\InstallRoot',
                'HKLM:\SOFTWARE\Microsoft\Office\14.0\Common\InstallRoot',
                'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Office\16.0\Common\InstallRoot',
                'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Office\15.0\Common\InstallRoot',
                'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Office\14.0\Common\InstallRoot'
            )
            foreach ($key in $officeKeys) {
                if (Test-Path $key) {
                    $officeInstalled = $true
                    Write-Log "Office detected via registry key: $key" 'INFO'
                    break
                }
            }
        }
        
        # Last resort: check Start Menu apps
        if (-not $officeInstalled) {
            $officeApps = Get-StartAppsCompatible | Where-Object { $_.Name -match 'Office|Word|Excel|PowerPoint|Outlook' }
            if ($officeApps) { 
                $officeInstalled = $true 
                Write-Log "Office detected via Start Menu apps" 'INFO'
            }
        }
    }
    catch {
        Write-Log "Error checking for Microsoft Office: $_" 'WARN'
    }

    if (-not $officeInstalled) {
        Write-Log "Microsoft Office not detected. Installing LibreOffice as alternative..." 'INFO'
        $libreSuccess = $false
        try {
            if (Get-Command winget -ErrorAction SilentlyContinue) {
                $wingetArgs = @("install", "--id", "TheDocumentFoundation.LibreOffice", "--accept-source-agreements", "--accept-package-agreements", "--silent", "-e")
                $result = Invoke-ModernPackageManager -PackageManager 'winget' -Arguments $wingetArgs -Description "Install LibreOffice"
                
                if ($result.Success) {
                    Write-Log "LibreOffice installed via winget." 'INFO'
                    $libreSuccess = $true
                    $success++
                    $detailedResults += "SUCCESS: LibreOffice via winget"
                }
                else {
                    Write-Log "LibreOffice winget install failed with exit code $($result.ExitCode): $($result.Error)" 'WARN'
                }
            }
            if (-not $libreSuccess -and (Get-Command choco -ErrorAction SilentlyContinue)) {
                $chocoArgs = @("install", "libreoffice-fresh", "-y", "--no-progress", "--limit-output")
                $result = Invoke-ModernPackageManager -PackageManager 'choco' -Arguments $chocoArgs -Description "Install LibreOffice"
                
                if ($result.Success) {
                    Write-Log "LibreOffice installed via choco." 'INFO'
                    $libreSuccess = $true
                    $success++
                    $detailedResults += "SUCCESS: LibreOffice via choco"
                }
                else {
                    Write-Log "LibreOffice choco install failed with exit code $($result.ExitCode): $($result.Error)" 'WARN'
                }
            }
            if (-not $libreSuccess) {
                Write-Log "No installer found or succeeded for LibreOffice." 'WARN'
                $fail++
                $detailedResults += "FAIL: LibreOffice (no installer succeeded)"
            }
        }
        catch {
            Write-Log "Failed to install LibreOffice: $_" 'WARN'
            $fail++
            $detailedResults += "FAIL: LibreOffice (exception: $_)"
        }
    }
    else {
        Write-Log "Microsoft Office detected. Skipping LibreOffice installation." 'INFO'
        $detailedResults += "SKIPPED: LibreOffice (Office already installed)"
    }

    Write-TaskProgress -Activity "Installing Essential Apps" -Status "Installation completed" -PercentComplete 100 -Completed
    Write-Log "Install Essential Apps summary: Installed: $success, Failed: $fail, Skipped: $skipped" 'SUCCESS'
    foreach ($result in $detailedResults) {
        Write-LogFile $result 'INFO'
    }
    
    # Create final installation results temp list
    $installResults = @{
        Summary = @{
            Installed = $success
            Failed = $fail
            Skipped = $skipped
            Total = $success + $fail + $skipped
        }
        Details = $detailedResults
    }
    New-StandardizedTempList -ListType "essential" -Operation "install_results" -Data $installResults -Description "Final results of essential apps installation process"
    
    Write-Log "[END] Install Essential Apps" 'SUCCESS'
}

### [TASK 3] Enhanced Remove Bloatware - Diff-Based Approach
function Remove-Bloatware {
    # ===============================
    # Task: RemoveBloatware
    # ===============================
    # Purpose: Removes unwanted apps using diff-based comparison with inventory.
    # Environment: Windows 10/11, must run as Administrator, supports OEM, Microsoft, and third-party bloatware.
    # Logic: Compare bloatware list against inventory, only attempt removal of actually installed apps.
    Write-Log "[START] Enhanced Remove Bloatware (Diff-Based Approach)" 'INFO'
    
    # Use global inventory if available, otherwise build a quick one
    if (-not $global:SystemInventory) {
        Write-Log "[Bloatware] No system inventory available, building quick inventory..." 'WARN'
        Get-ExtensiveSystemInventory
    }
    
    $inventory = $global:SystemInventory
    Write-Log "[Bloatware] Using inventory with $($inventory.appx.Count) AppX, $($inventory.winget.Count) Winget, $($inventory.choco.Count) Choco, $($inventory.registry_uninstall.Count) registry apps" 'INFO'
    
    # Build comprehensive list of all installed app identifiers
    $installedIdentifiers = @()
    
    # Add AppX package names and IDs
    $inventory.appx | ForEach-Object {
        if ($_.Name) { $installedIdentifiers += $_.Name }
        if ($_.PackageFullName) { $installedIdentifiers += $_.PackageFullName }
    }
    
    # Add Winget app names and IDs
    $inventory.winget | ForEach-Object {
        if ($_.Name) { $installedIdentifiers += $_.Name }
        if ($_.Id) { $installedIdentifiers += $_.Id }
    }
    
    # Add Chocolatey app names
    $inventory.choco | ForEach-Object {
        if ($_.Name) { $installedIdentifiers += $_.Name }
    }
    
    # Add registry app display names
    $inventory.registry_uninstall | ForEach-Object {
        if ($_.DisplayName) { $installedIdentifiers += $_.DisplayName }
    }
    
    # Remove duplicates and create lookup for faster matching
    $installedIdentifiers = $installedIdentifiers | Where-Object { $null -ne $_ -and $_ -ne '' } | Sort-Object -Unique
    Write-Log "[Bloatware] Total unique installed identifiers: $($installedIdentifiers.Count)" 'INFO'
    
    # Find bloatware that is actually installed (diff operation)
    $bloatwareToRemove = @()
    foreach ($bloatApp in $global:BloatwareList) {
        $found = $false
        foreach ($installed in $installedIdentifiers) {
            # Enhanced matching: exact, partial, and pattern-based
            if ($installed -eq $bloatApp -or 
                $installed -like "*$bloatApp*" -or 
                $bloatApp -like "*$installed*" -or
                ($bloatApp.Contains('.') -and $installed -like "*$($bloatApp.Split('.')[1])*") -or
                ($bloatApp.Contains('.') -and $installed -like "*$($bloatApp.Split('.')[0])*")) {
                $found = $true
                Write-Log "[Bloatware] Match found: '$bloatApp' matches installed app '$installed'" 'VERBOSE'
                break
            }
        }
        if ($found) {
            $bloatwareToRemove += $bloatApp
        }
    }
    
    Write-Log "[Bloatware] Diff analysis: $($bloatwareToRemove.Count) bloatware apps found installed (out of $($global:BloatwareList.Count) total in list)" 'INFO'
    
    # Save diff lists using standardized temp list functions
    New-StandardizedTempList -ListType "bloatware" -Operation "to_remove" -Data $bloatwareToRemove -Description "Bloatware apps found on system and targeted for removal"
    
    # Save the apps NOT found (for debugging purposes)
    $appsNotFound = $global:BloatwareList | Where-Object { $_ -notin $bloatwareToRemove }
    New-StandardizedTempList -ListType "bloatware" -Operation "not_found" -Data $appsNotFound -Description "Bloatware apps not found on system"
    Write-Log "[Bloatware] Apps not found on system: $($appsNotFound.Count)" 'INFO'
    
    if ($bloatwareToRemove.Count -eq 0) {
        Write-Log "[Bloatware] No bloatware found on system. Skipping removal process." 'INFO'
        Write-Log "[END] Enhanced Remove Bloatware" 'INFO'
        return
    }
    
    # Log the bloatware that will be removed
    Write-Log "[Bloatware] Apps targeted for removal (diff list):" 'INFO'
    $bloatwareToRemove | ForEach-Object { Write-Log "  - $_" 'VERBOSE' }
    
    $removed = 0
    $failed = 0
    $totalApps = $bloatwareToRemove.Count
    
    Write-Log "[Bloatware] Starting removal process for $totalApps apps from diff list only..." 'INFO'
    
    $currentApp = 0

    # Check module availability
    Write-TaskProgress -Activity "Removing Bloatware" -Status "Checking module availability..." -PercentComplete 5
    $appxAvailable = $false
    if ($PSVersionTable.PSVersion.Major -ge 7) {
        try {
            $testCommand = "Get-Module -ListAvailable -Name Appx -ErrorAction SilentlyContinue | Select-Object Name"
            $result = Invoke-WindowsPowerShellCommand -Command $testCommand -Description "Test Appx module"
            $appxAvailable = $null -ne $result
        }
        catch {
            Write-LogFile "Failed to test Appx module: $_" 'WARN'
        }
    }
    else {
        try {
            if (Get-Module -ListAvailable -Name Appx -ErrorAction SilentlyContinue) {
                Import-Module Appx -ErrorAction Stop
                $appxAvailable = $true
            }
        }
        catch {
            Write-LogFile "Failed to load Appx module: $_" 'WARN'
        }
    }

    $dismCmd = Get-Command dism -ErrorAction SilentlyContinue
    $dismAvailable = $dismCmd -and (Test-Path $dismCmd.Source)
    
    # Enhanced pattern matching for better app identification
    $enhancedPatterns = @{
        'Microsoft.3DBuilder'                    = @('3DBuilder', '*3DBuilder*')
        'Microsoft.BingWeather'                  = @('BingWeather', '*Weather*', '*MSN Weather*')
        'Microsoft.GetHelp'                      = @('GetHelp', '*Get Help*')
        'Microsoft.Getstarted'                   = @('Getstarted', '*Get Started*', '*Tips*')
        'Microsoft.MicrosoftSolitaireCollection' = @('MicrosoftSolitaireCollection', '*Solitaire*')
        'Microsoft.WindowsFeedbackHub'           = @('WindowsFeedbackHub', '*Feedback*')
        'Microsoft.XboxApp'                      = @('XboxApp', '*Xbox*', 'Microsoft.GamingApp')
        'Microsoft.ZuneMusic'                    = @('ZuneMusic', '*Groove*', '*Music*')
        'Microsoft.ZuneVideo'                    = @('ZuneVideo', '*Movies*', '*Video*')
        'Microsoft.People'                       = @('People', '*People*')
        'Microsoft.Office.OneNote'               = @('Office.OneNote', '*OneNote*')
        'Microsoft.SkypeApp'                     = @('SkypeApp', '*Skype*')
        'Microsoft.Wallet'                       = @('Wallet', '*Wallet*')
        'king.com.CandyCrushSaga'                = @('*CandyCrush*', '*king.com*')
        'Microsoft.Paint'                        = @('Paint', '*Paint 3D*', 'Microsoft.MSPaint')
        'Microsoft.YourPhone'                    = @('YourPhone', '*Your Phone*', '*Phone Link*')
        'Microsoft.PowerAutomateDesktop'         = @('PowerAutomateDesktop', '*Power Automate*')
        'MicrosoftTeams'                         = @('MicrosoftTeams', '*Teams*', '*Microsoft Teams*')
    }

    # Process ONLY the diff list (apps that are confirmed to be installed)
    foreach ($app in $bloatwareToRemove) {
        $currentApp++
        $percentComplete = [math]::Round(10 + ($currentApp / $totalApps) * 80) # 10-90% for removal process
        Write-TaskProgress -Activity "Removing Bloatware" -Status "Processing app: $app" -PercentComplete $percentComplete -CurrentOperation "$currentApp of $totalApps apps"
        
        # Validation: Ensure this app is indeed in our diff list
        if ($app -notin $bloatwareToRemove) {
            Write-LogFile "[ERROR] App '$app' is not in the diff list but is being processed. This should not happen!" 'ERROR'
            continue
        }
        
        Write-LogFile "[Bloatware] Processing app from diff list: $app" 'VERBOSE'
        $appRemoved = $false
        $removalMethods = @()
        
        try {
            # AppX removal
            if ($appxAvailable) {
                $patterns = if ($enhancedPatterns.ContainsKey($app)) { $enhancedPatterns[$app] } else { @($app, "*$app*") }
                foreach ($pattern in $patterns) {
                    $appxPackages = Get-AppxPackageCompatible -Name $pattern -AllUsers
                    foreach ($pkg in $appxPackages) {
                        if ($pkg.PackageFullName) {
                            try {
                                $success = Remove-AppxPackageCompatible -PackageFullName $pkg.PackageFullName -AllUsers
                                if ($success) {
                                    Write-LogFile "Removed AppX package: $($pkg.Name) ($($pkg.PackageFullName))" 'INFO'
                                    $appRemoved = $true
                                    $removalMethods += 'AppX'
                                }
                            }
                            catch {}
                        }
                    }
                    $provisionedPackages = Get-AppxProvisionedPackageCompatible -Online |
                    Where-Object { $_.DisplayName -like $pattern }
                    foreach ($pkg in $provisionedPackages) {
                        try {
                            $success = Remove-AppxProvisionedPackageCompatible -Online -PackageName $pkg.PackageName
                            if ($success) {
                                Write-LogFile "Removed provisioned package: $($pkg.DisplayName) ($($pkg.PackageName))" 'INFO'
                                $appRemoved = $true
                                $removalMethods += 'DISM-Provisioned'
                            }
                        }
                        catch {}
                    }
                }
            }
            
            # DISM removal
            if ($dismAvailable) {
                $patterns = if ($enhancedPatterns.ContainsKey($app)) { $enhancedPatterns[$app] } else { @($app) }
                foreach ($pattern in $patterns) {
                    $dismResult = dism /online /get-provisionedappxpackages | Select-String $pattern
                    if ($dismResult) {
                        foreach ($result in $dismResult) {
                            $packageName = ($result -split ':')[1].Trim()
                            if ($packageName) {
                                try {
                                    dism /online /remove-provisionedappxpackage /packagename:"$packageName" /NoRestart
                                    Write-LogFile "DISM removed provisioned package: $packageName" 'INFO'
                                    $appRemoved = $true
                                    $removalMethods += 'DISM'
                                }
                                catch {}
                            }
                        }
                    }
                }
            }
            
            # Winget removal - Enhanced with better error handling and logging
            if ((Get-Command winget -ErrorAction SilentlyContinue)) {
                $wingetIds = @($app)
                if ($app.StartsWith('Microsoft.')) { $wingetIds += $app.Replace('Microsoft.', '') }
                if ($enhancedPatterns.ContainsKey($app)) { $wingetIds += $enhancedPatterns[$app] }
                
                foreach ($wingetId in $wingetIds) {
                    try {
                        Write-Log "Checking winget for: $wingetId" 'VERBOSE'
                        
                        # Use winget list with JSON output for better parsing
                        $wingetListResult = winget list --id $wingetId --exact --accept-source-agreements --output json 2>$null
                        if ($LASTEXITCODE -eq 0) {
                            try {
                                $wingetJson = $wingetListResult | ConvertFrom-Json -ErrorAction SilentlyContinue
                                if ($wingetJson -and $wingetJson.Data -and $wingetJson.Data.Count -gt 0) {
                                    Write-Log "Winget found app: $wingetId, attempting removal..." 'VERBOSE'
                                    
                                    # Attempt removal with detailed logging
                                    $uninstallResult = winget uninstall --id $wingetId --exact --silent --accept-source-agreements --force 2>&1
                                    if ($LASTEXITCODE -eq 0) {
                                        Write-Log "Winget successfully removed: $wingetId" 'INFO'
                                        $appRemoved = $true
                                        $removalMethods += 'Winget'
                                        break
                                    }
                                    else {
                                        Write-Log "Winget uninstall failed for $wingetId (Exit code: $LASTEXITCODE)" 'VERBOSE'
                                        if ($uninstallResult) {
                                            Write-Log "Winget uninstall output for ${wingetId}: $uninstallResult" 'VERBOSE'
                                        }
                                    }
                                }
                            }
                            catch {
                                # Fallback to text-based parsing if JSON fails
                                if ($wingetListResult -match $wingetId) {
                                    Write-Log "Winget found app (text match): $wingetId, attempting removal..." 'VERBOSE'
                                    winget uninstall --id $wingetId --exact --silent --accept-source-agreements --force 2>$null
                                    if ($LASTEXITCODE -eq 0) {
                                        Write-Log "Winget successfully removed: $wingetId" 'INFO'
                                        $appRemoved = $true
                                        $removalMethods += 'Winget'
                                        break
                                    }
                                }
                            }
                        }
                        else {
                            Write-Log "Winget list failed for $wingetId (Exit code: $LASTEXITCODE)" 'VERBOSE'
                        }
                    }
                    catch {
                        Write-Log "Exception during winget processing for $wingetId`: $_" 'VERBOSE'
                    }
                }
            }
            else {
                Write-Log "Winget not available for app removal" 'VERBOSE'
            }
            
            # Chocolatey removal
            if ((Get-Command choco -ErrorAction SilentlyContinue)) {
                $chocoNames = @($app.ToLower(), $app.Replace('Microsoft.', '').ToLower())
                foreach ($chocoName in $chocoNames) {
                    try {
                        $chocoList = choco list --local-only $chocoName 2>$null
                        if ($LASTEXITCODE -eq 0 -and $chocoList -match $chocoName) {
                            choco uninstall $chocoName -y --remove-dependencies 2>$null
                            if ($LASTEXITCODE -eq 0) {
                                Write-Log "Chocolatey removed: $chocoName" 'INFO'
                                $appRemoved = $true
                                $removalMethods += 'Chocolatey'
                                break
                            }
                        }
                    }
                    catch {}
                }
            }
            
            # Windows Capabilities removal
            try {
                $capabilities = Get-WindowsCapability -Online -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -like "*$app*" -or $_.Name -like "*$($app.Replace('Microsoft.', ''))*" }
                foreach ($capability in $capabilities) {
                    if ($capability.State -eq 'Installed') {
                        try {
                            Remove-WindowsCapability -Online -Name $capability.Name -ErrorAction Stop
                            Write-Log "Removed Windows Capability: $($capability.Name)" 'INFO'
                            $appRemoved = $true
                            $removalMethods += 'Capability'
                        }
                        catch {}
                    }
                }
            }
            catch {}
            
            # Windows Features removal (Optional Features)
            try {
                $features = Get-WindowsOptionalFeature -Online -ErrorAction SilentlyContinue |
                Where-Object { $_.FeatureName -like "*$app*" -or $_.DisplayName -like "*$app*" -or 
                    $_.FeatureName -like "*$($app.Replace('Microsoft.', ''))*" }
                foreach ($feature in $features) {
                    if ($feature.State -eq 'Enabled') {
                        try {
                            Disable-WindowsOptionalFeature -Online -FeatureName $feature.FeatureName -NoRestart -ErrorAction Stop
                            Write-Log "Disabled Windows Feature: $($feature.FeatureName)" 'INFO'
                            $appRemoved = $true
                            $removalMethods += 'WindowsFeature'
                        }
                        catch {}
                    }
                }
            }
            catch {}
            
            # Registry-based uninstall (using uninstall strings)
            try {
                $uninstallKeys = @(
                    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
                    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
                    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
                )
                foreach ($regKey in $uninstallKeys) {
                    if (Test-Path $regKey) {
                        $subKeys = Get-ChildItem $regKey -ErrorAction SilentlyContinue
                        foreach ($subKey in $subKeys) {
                            $props = Get-ItemProperty $subKey.PSPath -ErrorAction SilentlyContinue
                            if ($props.DisplayName -like "*$app*" -or $props.DisplayName -like "*$($app.Replace('Microsoft.', ''))*") {
                                if ($props.UninstallString) {
                                    try {
                                        Write-Log "Found registry uninstaller for: $($props.DisplayName)" 'VERBOSE'
                                        $uninstallCmd = $props.UninstallString
                                        
                                        # Handle different uninstall string formats
                                        if ($uninstallCmd -match 'msiexec') {
                                            # MSI uninstall
                                            $productCode = if ($uninstallCmd -match '/[IX]\{([^}]+)\}') { $matches[1] } else { $null }
                                            if ($productCode) {
                                                $msiArgs = "/x{$productCode} /quiet /norestart"
                                                Start-Process -FilePath "msiexec.exe" -ArgumentList $msiArgs -Wait -WindowStyle Hidden -ErrorAction Stop
                                                Write-Log "MSI uninstalled via registry: $($props.DisplayName)" 'INFO'
                                                $appRemoved = $true
                                                $removalMethods += 'Registry-MSI'
                                            }
                                        }
                                        elseif ($uninstallCmd -notmatch 'rundll32.*appwiz') {
                                            # Standard exe uninstaller (but not appwiz.cpl)
                                            if ($uninstallCmd -match '^"([^"]+)"(.*)$') {
                                                $exePath = $matches[1]
                                                $exeArgs = $matches[2].Trim()
                                                if (Test-Path $exePath) {
                                                    # Add silent flags if not present
                                                    if ($exeArgs -notmatch '/[Ss]ilent|/[Qq]uiet|/[Ss]|/[Qq]') {
                                                        $exeArgs += " /S /silent /quiet"
                                                    }
                                                    Start-Process -FilePath $exePath -ArgumentList $exeArgs -Wait -WindowStyle Hidden -ErrorAction Stop
                                                    Write-Log "EXE uninstalled via registry: $($props.DisplayName)" 'INFO'
                                                    $appRemoved = $true
                                                    $removalMethods += 'Registry-EXE'
                                                }
                                            }
                                        }
                                    }
                                    catch {
                                        Write-Log "Registry uninstall failed for $($props.DisplayName): $_" 'VERBOSE'
                                    }
                                }
                            }
                        }
                    }
                }
            }
            catch {}
            
            # PowerShell Get-Package / Uninstall-Package removal
            try {
                $packages = Get-Package -ErrorAction SilentlyContinue | 
                Where-Object { $_.Name -like "*$app*" -or $_.Name -like "*$($app.Replace('Microsoft.', ''))*" }
                foreach ($package in $packages) {
                    try {
                        Uninstall-Package -Name $package.Name -Force -ErrorAction Stop
                        Write-Log "PowerShell Package removed: $($package.Name)" 'INFO'
                        $appRemoved = $true
                        $removalMethods += 'PS-Package'
                    }
                    catch {}
                }
            }
            catch {}
            
            # WMI Win32_Product removal (use sparingly as it's slow)
            if (-not $appRemoved) {
                try {
                    $wmiProducts = Get-WmiObject -Class Win32_Product -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -like "*$app*" -or $_.Name -like "*$($app.Replace('Microsoft.', ''))*" }
                    foreach ($product in $wmiProducts) {
                        try {
                            Write-Log "Attempting WMI uninstall for: $($product.Name)" 'VERBOSE'
                            $result = $product.Uninstall()
                            if ($result.ReturnValue -eq 0) {
                                Write-Log "WMI uninstalled: $($product.Name)" 'INFO'
                                $appRemoved = $true
                                $removalMethods += 'WMI'
                                break
                            }
                        }
                        catch {}
                    }
                }
                catch {}
            }
            
            # Windows Package Manager (legacy) removal
            try {
                if (Get-Command pkgmgr -ErrorAction SilentlyContinue) {
                    # This is for older Windows versions or specific package types
                    $packageName = $app.Replace('Microsoft.', '')
                    pkgmgr /up:$packageName /quiet /norestart 2>$null
                    if ($LASTEXITCODE -eq 0) {
                        Write-Log "Package Manager removed: $packageName" 'INFO'
                        $appRemoved = $true
                        $removalMethods += 'PkgMgr'
                    }
                }
            }
            catch {}
            
            # Remove Start Menu shortcuts and program folders
            try {
                $shortcutPaths = @(
                    "$env:ALLUSERSPROFILE\Microsoft\Windows\Start Menu\Programs",
                    "$env:USERPROFILE\AppData\Roaming\Microsoft\Windows\Start Menu\Programs"
                )
                foreach ($shortcutPath in $shortcutPaths) {
                    if (Test-Path $shortcutPath) {
                        $shortcuts = Get-ChildItem -Path $shortcutPath -Recurse -Include "*.lnk" -ErrorAction SilentlyContinue |
                        Where-Object { $_.Name -like "*$app*" -or $_.Name -like "*$($app.Replace('Microsoft.', ''))*" }
                        foreach ($shortcut in $shortcuts) {
                            try {
                                Remove-Item $shortcut.FullName -Force -ErrorAction Stop
                                Write-Log "Removed shortcut: $($shortcut.Name)" 'VERBOSE'
                            }
                            catch {}
                        }
                        
                        # Remove empty folders related to the app
                        $folders = Get-ChildItem -Path $shortcutPath -Directory -Recurse -ErrorAction SilentlyContinue |
                        Where-Object { $_.Name -like "*$app*" -or $_.Name -like "*$($app.Replace('Microsoft.', ''))*" }
                        foreach ($folder in $folders) {
                            try {
                                if ((Get-ChildItem $folder.FullName -ErrorAction SilentlyContinue).Count -eq 0) {
                                    Remove-Item $folder.FullName -Force -ErrorAction Stop
                                    Write-Log "Removed empty program folder: $($folder.Name)" 'VERBOSE'
                                }
                            }
                            catch {}
                        }
                    }
                }
            }
            catch {}
            
            # Remove registry entries and leftover keys
            try {
                $cleanupKeys = @(
                    "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run",
                    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run",
                    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run",
                    "HKCU:\SOFTWARE\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\Repository\Families",
                    "HKLM:\SOFTWARE\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\Repository\Families"
                )
                foreach ($regKey in $cleanupKeys) {
                    if (Test-Path $regKey) {
                        $entries = Get-ItemProperty $regKey -ErrorAction SilentlyContinue
                        $entries.PSObject.Properties | ForEach-Object {
                            if ($_.Name -like "*$app*" -or $_.Value -like "*$app*") {
                                try {
                                    Remove-ItemProperty -Path $regKey -Name $_.Name -ErrorAction Stop
                                    Write-Log "Removed registry startup entry: $($_.Name)" 'VERBOSE'
                                }
                                catch {}
                            }
                        }
                    }
                }
                
                # Remove app-specific registry trees
                $appRegPaths = @(
                    "HKCU:\SOFTWARE\$app",
                    "HKLM:\SOFTWARE\$app",
                    "HKLM:\SOFTWARE\WOW6432Node\$app",
                    "HKCU:\SOFTWARE\$($app.Replace('Microsoft.', ''))",
                    "HKLM:\SOFTWARE\$($app.Replace('Microsoft.', ''))",
                    "HKLM:\SOFTWARE\WOW6432Node\$($app.Replace('Microsoft.', ''))"
                )
                foreach ($regPath in $appRegPaths) {
                    if (Test-Path $regPath) {
                        try {
                            Remove-Item $regPath -Recurse -Force -ErrorAction Stop
                            Write-Log "Removed registry tree: $regPath" 'VERBOSE'
                        }
                        catch {}
                    }
                }
            }
            catch {}
            
            # File system cleanup - remove program files and app data
            try {
                $cleanupPaths = @(
                    "$env:ProgramFiles\$app",
                    "$env:ProgramFiles\$($app.Replace('Microsoft.', ''))",
                    "${env:ProgramFiles(x86)}\$app",
                    "${env:ProgramFiles(x86)}\$($app.Replace('Microsoft.', ''))",
                    "$env:LOCALAPPDATA\$app",
                    "$env:LOCALAPPDATA\$($app.Replace('Microsoft.', ''))",
                    "$env:APPDATA\$app",
                    "$env:APPDATA\$($app.Replace('Microsoft.', ''))",
                    "$env:LOCALAPPDATA\Packages\$app*",
                    "$env:USERPROFILE\AppData\Local\Packages\$app*"
                )
                
                foreach ($cleanupPath in $cleanupPaths) {
                    $expandedPaths = if ($cleanupPath -like "*`**") {
                        Get-ChildItem (Split-Path $cleanupPath) -Directory -ErrorAction SilentlyContinue |
                        Where-Object { $_.Name -like (Split-Path $cleanupPath -Leaf) }
                    }
                    else {
                        if (Test-Path $cleanupPath) { Get-Item $cleanupPath }
                    }
                    
                    foreach ($path in $expandedPaths) {
                        try {
                            if (Test-Path $path.FullName) {
                                Remove-Item $path.FullName -Recurse -Force -ErrorAction Stop
                                Write-Log "Removed app folder: $($path.FullName)" 'VERBOSE'
                            }
                        }
                        catch {}
                    }
                }
            }
            catch {}
            
            # CIM Win32_InstalledWin32Program removal (Windows 10+)
            try {
                $cimPrograms = Get-CimInstance -ClassName Win32_InstalledWin32Program -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -like "*$app*" -or $_.Name -like "*$($app.Replace('Microsoft.', ''))*" }
                foreach ($program in $cimPrograms) {
                    try {
                        # Try to find and execute uninstall command
                        if ($program.UninstallString) {
                            Write-Log "CIM found uninstaller for: $($program.Name)" 'VERBOSE'
                            # This would need careful parsing similar to registry method
                            # Implemented as a reference - actual execution would need the same logic as registry method
                        }
                    }
                    catch {}
                }
            }
            catch {}
            
            # Scoop removal (if Scoop is available)
            try {
                if (Get-Command scoop -ErrorAction SilentlyContinue) {
                    $scoopApps = scoop list 2>$null | Where-Object { $_ -like "*$app*" }
                    foreach ($scoopApp in $scoopApps) {
                        if ($scoopApp -match '^(\S+)') {
                            $appName = $matches[1]
                            try {
                                scoop uninstall $appName 2>$null
                                if ($LASTEXITCODE -eq 0) {
                                    Write-Log "Scoop removed: $appName" 'INFO'
                                    $appRemoved = $true
                                    $removalMethods += 'Scoop'
                                }
                            }
                            catch {}
                        }
                    }
                }
            }
            catch {}
            
            # Windows Store removal via PowerShell (modern method)
            if ($app -like "Microsoft.*" -or $app -like "*Store*") {
                try {
                    $storeApps = Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue | 
                    Where-Object { $_.Name -like "*$app*" -and $_.SignatureKind -eq 'Store' }
                    foreach ($storeApp in $storeApps) {
                        try {
                            Remove-AppxPackage -Package $storeApp.PackageFullName -AllUsers -ErrorAction Stop
                            Write-Log "Store app removed: $($storeApp.Name)" 'INFO'
                            $appRemoved = $true
                            $removalMethods += 'StoreApp'
                        }
                        catch {}
                    }
                }
                catch {}
            }
            
            # Update counters and log results
            if ($appRemoved) {
                $removed++
                $methodStr = ($removalMethods | Sort-Object -Unique) -join ', '
                Write-Log "Successfully removed bloatware: $app via [$methodStr]" 'INFO'
            }
            else {
                Write-LogFile "Bloatware removal failed or not found: $app" 'WARN'
                $failed++
            }
        }
        catch {
            Write-LogFile "Exception during removal of $app`: $_" 'ERROR'
            $failed++
        }
        
        Start-Sleep -Milliseconds 100
    }
    
    # Complete the progress bar
    Write-TaskProgress -Activity "Removing Bloatware" -Status "Bloatware removal completed" -PercentComplete 100 -Completed

    # Final cleanup: Disable app reinstallation
    $bloatwareRegKeys = @(
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager',
        'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent'
    )
    foreach ($regKey in $bloatwareRegKeys) {
        if (Test-Path $regKey) {
            try {
                Set-ItemProperty -Path $regKey -Name 'SilentInstalledAppsEnabled' -Value 0 -ErrorAction SilentlyContinue
                Set-ItemProperty -Path $regKey -Name 'ContentDeliveryAllowed' -Value 0 -ErrorAction SilentlyContinue
                Set-ItemProperty -Path $regKey -Name 'OemPreInstalledAppsEnabled' -Value 0 -ErrorAction SilentlyContinue
                Set-ItemProperty -Path $regKey -Name 'PreInstalledAppsEnabled' -Value 0 -ErrorAction SilentlyContinue
                Set-ItemProperty -Path $regKey -Name 'SubscribedContentEnabled' -Value 0 -ErrorAction SilentlyContinue
                Write-Log "Disabled app reinstallation via Content Delivery Manager" 'INFO'
            }
            catch {}
        }
    }

    Write-Log "Enhanced bloatware removal completed (diff-based approach):" 'INFO'
    Write-Log "  - Processed from diff list: $totalApps apps" 'INFO'
    Write-Log "  - Successfully removed: $removed apps" 'INFO'
    Write-Log "  - Failed to remove: $failed apps" 'INFO'
    Write-Log "  - Total in bloatware list: $($global:BloatwareList.Count) apps" 'INFO'
    Write-Log "  - Only apps from diff list were processed for removal" 'INFO'
    
    # Create final removal results temp list
    $removalResults = @{
        Summary = @{
            Processed = $totalApps
            Removed = $removed
            Failed = $failed
            TotalInMainList = $global:BloatwareList.Count
        }
        ProcessedApps = $bloatwareToRemove
    }
    New-StandardizedTempList -ListType "bloatware" -Operation "removal_results" -Data $removalResults -Description "Final results of bloatware removal process"
    
    Write-Log "[END] Enhanced Remove Bloatware" 'INFO'
}

### [TASK 4] Generate Temp Lists Summary Report
function Write-TempListsSummary {
    # ===============================
    # Task: TempListsSummary
    # ===============================
    # Purpose: Creates a comprehensive summary of all temp lists and diff operations
    # Environment: Windows 10/11, outputs standardized report to temp folder
    # Logic: Reads all temp list files and creates human-readable summary
    Write-Log "[START] Generate Temp Lists Summary Report" 'INFO'
    
    $summaryPath = Join-Path $global:TempFolder 'temp_lists_summary_report.txt'
    $summaryContent = @()
    
    $summaryContent += "=============================================="
    $summaryContent += "Windows Maintenance Script - Temp Lists Summary"
    $summaryContent += "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    $summaryContent += "=============================================="
    $summaryContent += ""
    
    # Find all standardized temp list files
    $tempFiles = Get-ChildItem -Path $global:TempFolder -Filter "temp_*.json" | Sort-Object Name
    
    if ($tempFiles.Count -eq 0) {
        $summaryContent += "No standardized temp list files found in: $global:TempFolder"
        $summaryContent | Out-File $summaryPath -Encoding UTF8
        Write-Log "Temp lists summary report generated (no files found): $summaryPath" 'WARN'
        return
    }
    
    # Group files by list type
    $bloatwareFiles = $tempFiles | Where-Object { $_.Name -like "temp_bloatware_*" }
    $essentialFiles = $tempFiles | Where-Object { $_.Name -like "temp_essential_*" }
    $otherFiles = $tempFiles | Where-Object { $_.Name -notlike "temp_bloatware_*" -and $_.Name -notlike "temp_essential_*" }
    
    # Bloatware Lists Summary
    $summaryContent += "BLOATWARE MANAGEMENT:"
    $summaryContent += "====================="
    
    foreach ($file in $bloatwareFiles) {
        $listData = Get-StandardizedTempList -FilePath $file.FullName
        if ($listData) {
            $summaryContent += "File: $($file.Name)"
            $summaryContent += "  Operation: $($listData.Metadata.Operation)"
            $summaryContent += "  Description: $($listData.Metadata.Description)"
            $summaryContent += "  Count: $($listData.Metadata.DataCount)"
            $summaryContent += "  Created: $($listData.Metadata.Created)"
            
            # Show first few items if count is reasonable
            if ($listData.Metadata.DataCount -gt 0 -and $listData.Metadata.DataCount -le 10) {
                $summaryContent += "  Items:"
                if ($listData.Data -is [array]) {
                    $listData.Data | ForEach-Object { $summaryContent += "    - $_" }
                }
                else {
                    $summaryContent += "    - $($listData.Data)"
                }
            }
            elseif ($listData.Metadata.DataCount -gt 10) {
                $summaryContent += "  Items: (Too many to display, see file for details)"
            }
            $summaryContent += ""
        }
    }
    
    # Essential Apps Lists Summary
    $summaryContent += "ESSENTIAL APPS MANAGEMENT:"
    $summaryContent += "=========================="
    
    foreach ($file in $essentialFiles) {
        $listData = Get-StandardizedTempList -FilePath $file.FullName
        if ($listData) {
            $summaryContent += "File: $($file.Name)"
            $summaryContent += "  Operation: $($listData.Metadata.Operation)"
            $summaryContent += "  Description: $($listData.Metadata.Description)"
            $summaryContent += "  Count: $($listData.Metadata.DataCount)"
            $summaryContent += "  Created: $($listData.Metadata.Created)"
            
            # Show apps with details if count is reasonable
            if ($listData.Metadata.DataCount -gt 0 -and $listData.Metadata.DataCount -le 10) {
                $summaryContent += "  Apps:"
                if ($listData.Data -is [array]) {
                    $listData.Data | ForEach-Object { 
                        if ($_.Name) {
                            $summaryContent += "    - $($_.Name) (Winget: $($_.Winget), Choco: $($_.Choco))"
                        }
                        else {
                            $summaryContent += "    - $_"
                        }
                    }
                }
                else {
                    if ($listData.Data.Name) {
                        $summaryContent += "    - $($listData.Data.Name) (Winget: $($listData.Data.Winget), Choco: $($listData.Data.Choco))"
                    }
                    else {
                        $summaryContent += "    - $($listData.Data)"
                    }
                }
            }
            elseif ($listData.Metadata.DataCount -gt 10) {
                $summaryContent += "  Apps: (Too many to display, see file for details)"
            }
            $summaryContent += ""
        }
    }
    
    # Other Files Summary
    if ($otherFiles.Count -gt 0) {
        $summaryContent += "OTHER TEMP FILES:"
        $summaryContent += "================="
        
        foreach ($file in $otherFiles) {
            $listData = Get-StandardizedTempList -FilePath $file.FullName
            if ($listData) {
                $summaryContent += "File: $($file.Name)"
                $summaryContent += "  Operation: $($listData.Metadata.Operation)"
                $summaryContent += "  Description: $($listData.Metadata.Description)"
                $summaryContent += "  Count: $($listData.Metadata.DataCount)"
                $summaryContent += "  Created: $($listData.Metadata.Created)"
                $summaryContent += ""
            }
        }
    }
    
    $summaryContent += "TEMP FILES LOCATIONS:"
    $summaryContent += "===================="
    foreach ($file in $tempFiles) {
        $summaryContent += "$($file.Name): EXISTS"
        $summaryContent += "  Path: $($file.FullName)"
        $summaryContent += "  Size: $([math]::Round($file.Length / 1KB, 2)) KB"
    }
    
    $summaryContent += ""
    $summaryContent += "=============================================="
    $summaryContent += "End of Temp Lists Summary Report"
    $summaryContent += "Total Files: $($tempFiles.Count)"
    $summaryContent += "=============================================="
    
    # Write summary to file
    $summaryContent | Out-File $summaryPath -Encoding UTF8
    Write-Log "Temp lists summary report generated: $summaryPath" 'INFO'
    Write-Log "[END] Generate Temp Lists Summary Report" 'INFO'
}

### [TASK 5] System Inventory (Legacy)
function Get-SystemInventory {
    # ===============================
    # Task: SystemInventory
    # ===============================
    # Purpose: Collects basic system info for reporting and troubleshooting.
    # Environment: Runs on any Windows, outputs to inventory.txt in repo folder.
    # Logic: Uses Get-ComputerInfo, logs results.
    Write-Log "[START] System Inventory (legacy)" 'INFO'
    $inventoryPath = Join-Path $global:TempFolder 'inventory.txt'
    Get-ComputerInfo | Out-File $inventoryPath
    Write-Log "System inventory saved to $inventoryPath" 'INFO'
    Write-Log "[END] System Inventory (legacy)" 'INFO'
}


### [TASK 5] Disable Telemetry
function Disable-Telemetry {
    # ===============================
    # Task: DisableTelemetry
    # ===============================
    # Purpose: Disables Windows telemetry, privacy-invading features, and unwanted browsers.
    # Environment: Windows 10/11, must run as Administrator, modifies registry, disables services/tasks, configures browsers.
    # Logic: Skips if disabled in config, logs all actions and errors.
    Write-Log "[START] Disable Telemetry" 'INFO'

    # Disable all OS notifications (Focus Assist: Alarms Only, and notification banners)
    try {
        # Set Focus Assist to Alarms Only (2)
        $focusAssistReg = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Notifications\Settings'
        if (-not (Test-Path $focusAssistReg)) { New-Item -Path $focusAssistReg -Force | Out-Null }
        Set-ItemProperty -Path $focusAssistReg -Name 'NOC_GLOBAL_SETTING_TOASTS_ENABLED' -Value 0 -Force
        Set-ItemProperty -Path $focusAssistReg -Name 'FocusAssist' -Value 2 -Force
        # Disable notification banners for all apps
        $apps = Get-ChildItem -Path $focusAssistReg -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -ne 'FocusAssist' -and $_.PSChildName -ne 'NOC_GLOBAL_SETTING_TOASTS_ENABLED' }
        foreach ($app in $apps) {
            Set-ItemProperty -Path $app.PSPath -Name 'Enabled' -Value 0 -Force -ErrorAction SilentlyContinue
        }
        Write-Log "All OS notifications disabled (Focus Assist and banners)." 'INFO'
    }
    catch {
        Write-Log "Failed to disable all OS notifications: $_" 'WARN'
    }

    # Remove all browsers except Edge, Chrome, and Firefox
    $allowedBrowsers = @('Microsoft Edge', 'Google Chrome', 'Mozilla Firefox')
    $knownBrowsers = @('Opera', 'Opera GX', 'Brave', 'Vivaldi', 'Waterfox', 'Yandex', 'Tor Browser', 'Pale Moon', 'Chromium', 'SRWare Iron', 'Comodo Dragon', 'Maxthon', 'UC Browser', 'Epic Privacy Browser', 'Slimjet', 'CentBrowser', 'QuteBrowser', 'OtterBrowser', 'Dooble', 'Midori', 'Blisk', 'AvantBrowser', 'Sleipnir', 'Polarity', 'Torch', 'Orbitum', 'Superbird', 'Sputnik', 'Lunascape', 'Falkon', 'SeaMonkey')
    foreach ($browser in $knownBrowsers) {
        if ($allowedBrowsers -notcontains $browser) {
            try {
                $removed = $false
                # Try winget removal first
                if (Get-Command winget -ErrorAction SilentlyContinue) {
                    $wingetSearch = winget list --id $browser --exact --accept-source-agreements 2>$null
                    if ($LASTEXITCODE -eq 0 -and $wingetSearch -match $browser) {
                        winget uninstall --id $browser --accept-source-agreements --accept-package-agreements --silent -e 2>$null
                        if ($LASTEXITCODE -eq 0) {
                            Write-Log "Removed browser via winget: $browser" 'INFO'
                            $removed = $true
                        }
                    }
                }
                # Try chocolatey removal if winget failed
                if (-not $removed -and (Get-Command choco -ErrorAction SilentlyContinue)) {
                    $chocoList = choco list --local-only $browser 2>$null
                    if ($LASTEXITCODE -eq 0 -and $chocoList -match $browser) {
                        choco uninstall $browser -y --remove-dependencies 2>$null
                        if ($LASTEXITCODE -eq 0) {
                            Write-Log "Removed browser via chocolatey: $browser" 'INFO'
                            $removed = $true
                        }
                    }
                }
                # Try registry-based uninstall as last resort
                if (-not $removed) {
                    $uninstallKeys = @(
                        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
                        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
                        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
                    )
                    foreach ($key in $uninstallKeys) {
                        $apps = Get-ChildItem $key -ErrorAction SilentlyContinue | ForEach-Object {
                            $app = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
                            if ($app.DisplayName -like "*$browser*") {
                                return $app
                            }
                        }
                        foreach ($app in $apps) {
                            if ($app.UninstallString) {
                                try {
                                    $uninstallCmd = $app.UninstallString -replace '"', ''
                                    if ($uninstallCmd -like "*.exe*") {
                                        Start-Process -FilePath $uninstallCmd -ArgumentList "/S" -Wait -WindowStyle Hidden -ErrorAction SilentlyContinue
                                        Write-Log "Attempted registry-based removal: $browser" 'INFO'
                                        $removed = $true
                                    }
                                }
                                catch {
                                    Write-Log "Registry-based uninstall failed for $browser`: $_" 'WARN'
                                }
                            }
                        }
                    }
                }
            }
            catch {
                Write-Log "Failed to remove browser $browser`: $_" 'WARN'
            }
        }
    }

    # Disable telemetry, set homepage, disable translation, enable bookmarks bar in Edge
    try {
        $edgeReg = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
        if (-not (Test-Path $edgeReg)) { New-Item -Path $edgeReg -Force | Out-Null }
        Set-ItemProperty -Path $edgeReg -Name 'MetricsReportingEnabled' -Value 0 -Force
        Set-ItemProperty -Path $edgeReg -Name 'HomepageLocation' -Value 'about:blank' -Force
        Set-ItemProperty -Path $edgeReg -Name 'ShowHomeButton' -Value 1 -Force
        Set-ItemProperty -Path $edgeReg -Name 'BookmarkBarEnabled' -Value 1 -Force
        Set-ItemProperty -Path $edgeReg -Name 'TranslateEnabled' -Value 0 -Force
        Write-Log "Edge telemetry, homepage, bookmarks bar, and translation policy set via registry." 'INFO'
    }
    catch {
        Write-Log "Failed to set Edge browser policies: $_" 'WARN'
    }

    # Disable telemetry, set homepage, disable translation, enable bookmarks bar in Chrome
    try {
        $chromeReg = 'HKLM:\SOFTWARE\Policies\Google\Chrome'
        if (-not (Test-Path $chromeReg)) { New-Item -Path $chromeReg -Force | Out-Null }
        Set-ItemProperty -Path $chromeReg -Name 'MetricsReportingEnabled' -Value 0 -Force
        Set-ItemProperty -Path $chromeReg -Name 'HomepageLocation' -Value 'about:blank' -Force
        Set-ItemProperty -Path $chromeReg -Name 'ShowHomeButton' -Value 1 -Force
        Set-ItemProperty -Path $chromeReg -Name 'BookmarkBarEnabled' -Value 1 -Force
        Set-ItemProperty -Path $chromeReg -Name 'TranslateEnabled' -Value 0 -Force
        Write-Log "Chrome telemetry, homepage, bookmarks bar, and translation policy set via registry." 'INFO'
    }
    catch {
        Write-Log "Failed to set Chrome browser policies: $_" 'WARN'
    }

    # Deploy Firefox policies.json for telemetry, homepage, uBlock Origin, default browser (from external file if present)
    try {
        $ffPath = $null
        if (Test-Path 'C:\Program Files\Mozilla Firefox') {
            $ffPath = 'C:\Program Files\Mozilla Firefox'
        }
        elseif (Test-Path 'C:\Program Files (x86)\Mozilla Firefox') {
            $ffPath = 'C:\Program Files (x86)\Mozilla Firefox'
        }
        if ($ffPath) {
            $distPath = Join-Path $ffPath 'distribution'
            if (-not (Test-Path $distPath)) { New-Item -Path $distPath -ItemType Directory -Force | Out-Null }
            $externalPolicyPath = Join-Path $PSScriptRoot 'firefox_policies.json'
            if (Test-Path $externalPolicyPath) {
                Copy-Item -Path $externalPolicyPath -Destination (Join-Path $distPath 'policies.json') -Force
                Write-Log "Firefox policies.json copied from firefox_policies.json and deployed." 'INFO'
                Remove-Item -Path $externalPolicyPath -Force
                Write-Log "firefox_policies.json removed from script folder." 'INFO'
            }
            else {
                # fallback: use built-in policy if external file not found
                $policyJson = @"
{
  "policies": {
    "DisableTelemetry": true,
    "DisableFirefoxStudies": true,
    "DisablePocket": true,
    "Homepage": {
      "StartPage": "homepage",
      "URL": "about:blank"
    },
    "Extensions": {
      "Install": [
        "https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi"
      ]
    },
    "DefaultBrowser": true
  }
}
"@
                $policyPath = Join-Path $distPath 'policies.json'
                $policyJson | Set-Content -Path $policyPath -Encoding UTF8
                Write-Log "Firefox policies.json deployed from built-in policy." 'INFO'
            }
        }
        else {
            Write-Log "Could not find Firefox installation path for policies.json deployment." 'WARN'
        }
    }
    catch {
        Write-Log "Failed to deploy Firefox policies.json: $_" 'WARN'
    }

    # Attempt to set Firefox as default browser (Windows 10 only, Windows 11 requires user interaction)
    try {
        $firefoxPaths = @(
            'C:\Program Files\Mozilla Firefox\firefox.exe',
            'C:\Program Files (x86)\Mozilla Firefox\firefox.exe'
        )
        $firefoxPath = $firefoxPaths | Where-Object { Test-Path $_ } | Select-Object -First 1
        
        if ($firefoxPath) {
            # Try to set Firefox as default browser using registry (more reliable)
            try {
                $httpReg = 'HKCU:\SOFTWARE\Microsoft\Windows\Shell\Associations\UrlAssociations\http\UserChoice'
                $httpsReg = 'HKCU:\SOFTWARE\Microsoft\Windows\Shell\Associations\UrlAssociations\https\UserChoice'
                $htmlReg = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.html\UserChoice'
                $htmReg = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.htm\UserChoice'
                
                # Check if Firefox is registered
                $firefoxProgId = 'FirefoxURL-308046B0AF4A39CB'
                
                # Set Firefox as default for HTTP/HTTPS protocols
                if (Test-Path $httpReg) { Set-ItemProperty -Path $httpReg -Name 'ProgId' -Value $firefoxProgId -Force -ErrorAction SilentlyContinue }
                if (Test-Path $httpsReg) { Set-ItemProperty -Path $httpsReg -Name 'ProgId' -Value $firefoxProgId -Force -ErrorAction SilentlyContinue }
                if (Test-Path $htmlReg) { Set-ItemProperty -Path $htmlReg -Name 'ProgId' -Value $firefoxProgId -Force -ErrorAction SilentlyContinue }
                if (Test-Path $htmReg) { Set-ItemProperty -Path $htmReg -Name 'ProgId' -Value $firefoxProgId -Force -ErrorAction SilentlyContinue }
                
                Write-Log "Firefox set as default browser via registry." 'INFO'
            }
            catch {
                # Fallback to Firefox command line method
                Start-Process -FilePath $firefoxPath -ArgumentList "-setDefaultBrowser" -Wait -WindowStyle Hidden -ErrorAction SilentlyContinue
                Write-Log "Attempted to set Firefox as default browser via command line." 'INFO'
            }
        }
        else {
            Write-Log "Firefox not found for default browser setting." 'WARN'
        }
    }
    catch {
        Write-Log "Failed to set Firefox as default browser: $_" 'WARN'
    }

    # Disable telemetry-related services
    $services = @('DiagTrack', 'dmwappushservice', 'Connected User Experiences and Telemetry')
    foreach ($svc in $services) {
        try {
            $serviceObj = Get-Service -Name $svc -ErrorAction Stop
            if ($serviceObj.Status -ne 'Stopped') {
                Stop-Service -Name $svc -Force -ErrorAction Stop
                Write-Log "Stopped service: $svc" 'INFO'
            }
            Set-Service -Name $svc -StartupType Disabled -ErrorAction Stop
            Write-Log "Disabled service: $svc" 'INFO'
        }
        catch {
            Write-Log "Service $svc not found or could not be disabled: $_" 'WARN'
        }
    }

    # Disable telemetry-related scheduled tasks
    $scheduledTasks = @(
        '\Microsoft\Windows\Application Experience\ProgramDataUpdater',
        '\Microsoft\Windows\Autochk\Proxy',
        '\Microsoft\Windows\Customer Experience Improvement Program\Consolidator',
        '\Microsoft\Windows\Customer Experience Improvement Program\KernelCeipTask',
        '\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip',
        '\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector',
        '\Microsoft\Windows\Feedback\Siuf\DmClient',
        '\Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload',
        '\Microsoft\Windows\Windows Error Reporting\QueueReporting'
    )
    foreach ($task in $scheduledTasks) {
        try {
            $taskPath = $task.Substring(0, $task.LastIndexOf('\') + 1)
            $taskName = $task.Split('\')[-1]
            $scheduledTaskObj = Get-ScheduledTask -TaskPath $taskPath -TaskName $taskName -ErrorAction SilentlyContinue
            if ($scheduledTaskObj) {
                Disable-ScheduledTask -TaskPath $taskPath -TaskName $taskName -ErrorAction SilentlyContinue
                Write-Log "Disabled scheduled task: $task" 'INFO'
            }
            else {
                Write-Log "Scheduled task not found: $task" 'WARN'
            }
        }
        catch {
            Write-Log ("Failed to disable scheduled task {0}: {1}" -f $task, $_) 'WARN'
        }
    }

    # Additional registry tweaks for telemetry (as per best practices)
    $extraReg = @(
        @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection'; Name = 'AllowTelemetry'; Value = 0 },
        @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat'; Name = 'AITEnable'; Value = 0 },
        @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat'; Name = 'DisableInventory'; Value = 1 },
        @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'; Name = 'UploadUserActivities'; Value = 0 },
        @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'; Name = 'PublishUserActivities'; Value = 0 }
    )
    foreach ($item in $extraReg) {
        try {
            if (-not (Test-Path $item.Path)) { New-Item -Path $item.Path -Force | Out-Null }
            Set-ItemProperty -Path $item.Path -Name $item.Name -Value $item.Value -Force
            Write-Log "Set $($item.Name)=$($item.Value) in $($item.Path)" 'INFO'
        }
        catch {
            Write-Log "Failed to set $($item.Name) in $($item.Path): $_" 'WARN'
        }
    }

    Write-Log "[END] Disable Telemetry" 'INFO'
}


### [TASK 6] System Restore Protection
function Protect-SystemRestore {
    Write-Log "[START] System Restore Protection" 'INFO'
    $drive = "C:\\"
    $restoreEnabled = $false
    try {
        if ($PSVersionTable.PSVersion.Major -ge 7) {
            # Use Windows PowerShell for System Restore operations
            $checkCommand = "Get-CimInstance -Namespace root/default -ClassName SystemRestoreConfig -ErrorAction Stop | Select-Object Enable"
            $result = Invoke-WindowsPowerShellCommand -Command $checkCommand -Description "Check System Restore status"
            
            if ($result -and $result.Enable -eq $true) {
                $restoreEnabled = $true
                Write-Log "System Restore is already enabled on $drive" 'INFO'
            }
            else {
                Write-Log "System Restore is not enabled. Enabling..." 'INFO'
                $enableSuccess = Enable-ComputerRestoreCompatible -Drive $drive
                if ($enableSuccess) {
                    $restoreEnabled = $true
                    Write-Log "System Restore enabled on $drive" 'INFO'
                }
                else {
                    Write-Log "Failed to enable System Restore on $drive" 'WARN'
                }
            }
        }
        else {
            # Windows PowerShell 5.1 native
            $sr = Get-CimInstance -Namespace root/default -ClassName SystemRestoreConfig -ErrorAction Stop
            if ($sr.Enable -eq $true) {
                $restoreEnabled = $true
                Write-Log "System Restore is already enabled on $drive" 'INFO'
            }
            else {
                Write-Log "System Restore is not enabled. Enabling..." 'INFO'
                Enable-ComputerRestore -Drive $drive
                $restoreEnabled = $true
                Write-Log "System Restore enabled on $drive" 'INFO'
            }
        }
    }
    catch {
        Write-Log "Could not determine or enable System Restore: $_" 'WARN'
    }
    
    if ($restoreEnabled) {
        try {
            Write-Log "Creating a system restore point..." 'INFO'
            $checkpointSuccess = Checkpoint-ComputerCompatible -Description "Pre-maintenance restore point" -RestorePointType 'MODIFY_SETTINGS'
            if ($checkpointSuccess) {
                Write-Log "System restore point created." 'INFO'
            }
            else {
                Write-Log "Failed to create restore point." 'WARN'
            }
        }
        catch {
            Write-Log "Failed to create restore point: $_" 'WARN'
        }
    }
    Write-Log "[END] System Restore Protection" 'INFO'
}


### [MAIN TASK EXECUTION IN TIMELINE ORDER]

# Run all tasks using the coordinator
Use-AllScriptTasks




### [POST-TASK 1] Script completion cleanup




### [POST-TASK 2] Built-in Maintenance Tasks

$successCount = ($global:TaskResults.Values | Where-Object { $_.Success }).Count
$failCount = ($global:TaskResults.Values | Where-Object { -not $_.Success }).Count
$totalCount = $global:TaskResults.Count
$taskDetails = @()
foreach ($key in $global:TaskResults.Keys) {
    $result = $global:TaskResults[$key]
    $desc = ($global:ScriptTasks | Where-Object { $_.Name -eq $key }).Description
    $status = if ($result.Success) { 'SUCCESS' } else { 'FAIL' }
    $duration = [math]::Round($result.Duration, 2)
    $started = $result.Started.ToString('HH:mm:ss')
    $ended = $result.Ended.ToString('HH:mm:ss')
    $taskDetails += "- $key $status | $desc | Started: $started | Ended: $ended | Duration: ${duration}s"
    if ($result.ContainsKey('Error') -and $result.Error) {
        $taskDetails += "    Error: $($result.Error)"
    }
}
Write-Log ("All tasks completed. Total: {0}, Success: {1}, Failed: {2}" -f $totalCount, $successCount, $failCount) 'INFO'
foreach ($detail in $taskDetails) { Write-Log $detail 'INFO' }

### [POST-TASK 4] Enhanced Reporting Section (JSON + Text)

# Save summary report in the same folder as script.bat (repo parent folder)
$batPath = Join-Path $PSScriptRoot "script.bat"
if (Test-Path $batPath) {
    $batDir = Split-Path $batPath -Parent
    $summaryPath = Join-Path $batDir "maintenance_report.txt"
    $jsonSummaryPath = Join-Path $batDir "maintenance_report.json"
}
else {
    $summaryPath = Join-Path $PSScriptRoot "maintenance_report.txt"
    $jsonSummaryPath = Join-Path $PSScriptRoot "maintenance_report.json"
}

# Gather system info for report
$osInfo = Get-CimInstance Win32_OperatingSystem
$osVersion = $osInfo.Version
$osCaption = $osInfo.Caption
$psVer = $PSVersionTable.PSVersion.ToString()
$scriptVer = '1.0.0'

# Build structured report object
$reportData = [ordered]@{
    metadata = [ordered]@{
        generatedOn       = (Get-Date).ToString('o')
        date              = Get-Date -Format 'dd-MM-yyyy HH:mm:ss'
        user              = $env:USERNAME
        computer          = $env:COMPUTERNAME
        scriptVersion     = $scriptVer
        os                = $osCaption
        osVersion         = $osVersion
        powershellVersion = $psVer
    }
    summary  = [ordered]@{
        totalTasks      = $totalCount
        successfulTasks = $successCount
        failedTasks     = $failCount
        successRate     = if ($totalCount -gt 0) { [math]::Round(($successCount / $totalCount) * 100, 2) } else { 0 }
    }
    tasks    = @()
    files    = [ordered]@{
        inventoryFiles = @()
        listFiles      = @()
        logFiles       = @()
    }
    actions  = @()
}

# Add task details
foreach ($key in $global:TaskResults.Keys) {
    $result = $global:TaskResults[$key]
    $desc = ($global:ScriptTasks | Where-Object { $_.Name -eq $key }).Description
    $taskObj = [ordered]@{
        name        = $key
        description = $desc
        success     = $result.Success
        duration    = [math]::Round($result.Duration, 2)
        started     = $result.Started.ToString('o')
        ended       = $result.Ended.ToString('o')
    }
    if ($result.ContainsKey('Error') -and $result.Error) {
        $taskObj.error = $result.Error
    }
    $reportData.tasks += $taskObj
}

# Reference files created
$inventoryFiles = @('inventory.json', 'bloatware.json', 'essential_apps.json')
$legacyFiles = @('inventory.txt')  # Keep legacy reference
$logFiles = @('maintenance.log')

foreach ($file in $inventoryFiles) {
    $path = Join-Path $PSScriptRoot $file
    if (Test-Path $path) {
        $reportData.files.inventoryFiles += $file
    }
}

foreach ($file in $legacyFiles) {
    $path = Join-Path $PSScriptRoot $file
    if (Test-Path $path) {
        $reportData.files.inventoryFiles += $file
    }
}

foreach ($file in $logFiles) {
    $path = Join-Path $PSScriptRoot $file
    if (Test-Path $path) {
        $reportData.files.logFiles += $file
    }
}

# Extract detailed actions from maintenance.log
$logActions = @('Installed', 'Uninstalled', 'Updated', 'Removed', 'Deleted', 'Upgraded', 'Cleaned')
$logPath = Join-Path $PSScriptRoot "maintenance.log"
if (Test-Path $logPath) {
    $logContent = Get-Content $logPath
    $actionLines = $logContent | Where-Object {
        $line = $_
        $logActions | Where-Object { $line -match $_ }
    }
    $reportData.actions = @($actionLines)
}

# Write structured JSON report
try {
    $reportData | ConvertTo-Json -Depth 5 | Out-File -FilePath $jsonSummaryPath -Encoding UTF8
    Write-Log "Structured report saved to $jsonSummaryPath" 'INFO'
}
catch {
    Write-Log "Failed to write JSON report: $_" 'WARN'
}

# Build human-readable text report
$summaryLines = @()
$summaryLines += "==== Maintenance Report ===="
$summaryLines += "Date: $($reportData.metadata.date)"
$summaryLines += "User: $($reportData.metadata.user)"
$summaryLines += "Computer: $($reportData.metadata.computer)"
$summaryLines += "Script Version: $($reportData.metadata.scriptVersion)"
$summaryLines += "OS: $($reportData.metadata.os) ($($reportData.metadata.osVersion))"
$summaryLines += "PowerShell Version: $($reportData.metadata.powershellVersion)"
$summaryLines += "---"
$summaryLines += "Total tasks: $($reportData.summary.totalTasks) | Success: $($reportData.summary.successfulTasks) | Failed: $($reportData.summary.failedTasks) | Success Rate: $($reportData.summary.successRate)%"
$summaryLines += "---"
$summaryLines += "Task Breakdown:"
foreach ($task in $reportData.tasks) {
    $status = if ($task.success) { 'SUCCESS' } else { 'FAIL' }
    $summaryLines += "- $($task.name) $status | $($task.description) | Duration: $($task.duration)s"
    if ($task.error) {
        $summaryLines += "    Error: $($task.error)"
    }
}
$summaryLines += "---"

$summaryLines += "Files generated:"
if ($reportData.files.inventoryFiles.Count -gt 0) {
    $summaryLines += "Inventory files:"
    $reportData.files.inventoryFiles | ForEach-Object { $summaryLines += "- $_" }
}
if ($reportData.files.logFiles.Count -gt 0) {
    $summaryLines += "Log files:"
    $reportData.files.logFiles | ForEach-Object { $summaryLines += "- $_" }
}
$summaryLines += "---"

if ($reportData.actions.Count -gt 0) {
    $summaryLines += "Detailed actions performed during maintenance:"
    $summaryLines += $reportData.actions
    $summaryLines += "---"
}
else {
    $summaryLines += "No detailed action logs found in maintenance.log."
    $summaryLines += "---"
}

$summaryLines | Out-File -FilePath $summaryPath -Append
Write-Log "Summary report written to $summaryPath" 'INFO'

# Ensure repo folder is deleted only after report creation
try {
    $repoFolder = $PSScriptRoot
    $parentFolder = Split-Path $repoFolder -Parent
    $repoName = Split-Path $repoFolder -Leaf
    if ($repoName -eq 'script_mentenanta') {
        Write-Log "Attempting to remove repo folder: $repoFolder" 'INFO'
        Set-Location $parentFolder
        Remove-Item -Path $repoFolder -Recurse -Force
        Write-Log "Repo folder $repoFolder removed." 'INFO'
    }
}
catch {
    Write-Log "Failed to remove repo folder: $_" 'WARN'
}

### [POST-TASK 6] Example: Optionally send report via email or webhook (not implemented)
### ...

Write-Log "Script ended." 'INFO'

### [POST-TASK 7] Prompt to close the window if running interactively
if ($Host.Name -eq 'ConsoleHost' -or $Host.Name -like '*Windows*') {
    Write-Host
    Read-Host -Prompt 'Press Enter to close this window...'
}
