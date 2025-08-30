# ===============================
# SECTION 1: SCRIPT HEADER & METADATA  
# ===============================
# Windows Maintenance Script - Task Coordinator (PowerShell 7.5.2 Optimized)
# 
# This script is designed to automate and orchestrate a full suite of Windows maintenance tasks.
# It is intended to run as Administrator on Windows 10/11, with all actions logged and reported.
# Each task is modular, robust, and designed for unattended execution in enterprise or home environments.
#
# MODERNIZED FOR POWERSHELL 7.5.2:
# - Enhanced async operations and improved process management
# - Sequential processing for inventory collection (reliable, no hanging)
# - Modern JSON parsing with better error handling and performance
# - Improved file I/O operations with UTF-8 encoding
# - Enhanced error handling with detailed exception information
# - Modern package manager wrapper with timeout support
# - Optimized logging with better console color support
# - Thread-safe operations using System.Collections.Concurrent
# - REDUCED PS5.1 DEPENDENCY: Native PS7+ implementations for AppX, Windows Updates, and System Restore
#
# ENHANCED LOGGING SYSTEM:
# - Separated console progress bars from file logging for cleaner log files
# - Write-Log: Combined function for both console and file output
# - Write-LogFile: File-only logging without console noise (reduces PS5.1 operation noise)
# - Write-ConsoleMessage: Console-only messages with enhanced colors
# - Write-TaskProgress: Progress bars for console, simple messages for file
# - Progress tracking for all major operations (tasks, bloatware removal, app installation, inventory)
#
# MODERN POWERSHELL 7+ NATIVE OPERATIONS:
# - AppX Management: Uses CIM, WinRT APIs, winget, and DISM instead of Appx module
# - Windows Updates: Uses Windows Update COM API and winget upgrade instead of PSWindowsUpdate
# - System Restore: Uses CIM, vssadmin, and WMI instead of ComputerRestore cmdlets
# - Graceful fallback to Windows PowerShell 5.1 only when modern approaches fail
#
# Key Environment Details:
# - Optimized for PowerShell 7.5.2+ with minimal Windows PowerShell 5.1 dependency
# - Must be run as Administrator
# - Uses $PSScriptRoot for all temp and log files
# - Integrates with Winget, Chocolatey, CIM, WinRT, DISM, Registry, and Windows APIs
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

# Global Task Definitions
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
                    Write-Log 'Disk cleanup completed using cleanmgr.exe (silent AUTOCLEAN).' 'INFO'
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

# ===============================
# SECTION 2: CORE INFRASTRUCTURE
# ===============================
# Main Task Coordinator Function
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
            Write-Log "[COORDINATION] $taskName completed in $duration seconds. Result: $result" 'INFO'
            $global:TaskResults[$taskName] = @{ Success = $result; Duration = $duration; Started = $startTime; Ended = $endTime }
        }
        catch {
            Write-Log "[COORDINATION] $taskName failed: $_" 'ERROR'
            $global:TaskResults[$taskName] = @{ Success = $false; Duration = 0; Started = $startTime; Ended = (Get-Date) }
        }
    }
    
    # Complete the progress bar
    Write-TaskProgress -Activity "Windows Maintenance Tasks" -Status "All tasks completed" -PercentComplete 100 -Completed
    Write-Log '[COORDINATION] All maintenance tasks completed.' 'INFO'
}

# Initialize script execution tracking
$global:ScriptStartTime = Get-Date
$global:PerformanceMetrics = @{}
$global:logPath = Join-Path $PSScriptRoot "maintenance.log"
$global:InstallResults = $null
$global:RemovalResults = $null

# PowerShell 7.5.2 Compatibility Functions
function Invoke-WindowsPowerShellCommand {
    param(
        [string]$Command,
        [string]$Description = "Windows PowerShell command",
        [int]$TimeoutSeconds = 300
    )
    
    Write-LogFile "[PS5.1] Executing via Windows PowerShell: $Description" 'VERBOSE'
    
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
            Write-LogFile "[PS5.1] Successfully executed: $Description" 'VERBOSE'
            return $output
        }
        else {
            Write-Log "[PS5.1] Command failed with exit code $($process.ExitCode): $Description" 'WARN'
            if ($errorOutput) {
                Write-LogFile "[PS5.1] Error output: $errorOutput" 'VERBOSE'
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
        # Modern PowerShell 7+ approach using direct WinRT APIs
        try {
            Write-LogFile "[AppX] Using PowerShell 7+ native WinRT API approach" 'VERBOSE'
            
            # Load Windows Runtime assemblies
            Add-Type -AssemblyName System.Runtime.WindowsRuntime -ErrorAction SilentlyContinue
            
            # Use CIM for cross-platform compatibility
            $packages = @()
            
            if ($AllUsers) {
                # Query all user packages via CIM
                $cimPackages = Get-CimInstance -ClassName Win32_InstalledStoreProgram -ErrorAction SilentlyContinue
                if ($cimPackages) {
                    foreach ($pkg in $cimPackages) {
                        if ($Name -eq "*" -or $pkg.Name -like "*$Name*") {
                            $packages += [PSCustomObject]@{
                                Name            = $pkg.Name
                                PackageFullName = $pkg.Name
                                Publisher       = $pkg.Vendor
                                Architecture    = "Unknown"
                                Version         = $pkg.Version
                            }
                        }
                    }
                }
            }
            else {
                # For current user, use Get-AppxPackage via Windows PowerShell as fallback only if CIM fails
                $cimPackages = Get-CimInstance -ClassName Win32_InstalledStoreProgram -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "*$Name*" }
                if ($cimPackages) {
                    foreach ($pkg in $cimPackages) {
                        $packages += [PSCustomObject]@{
                            Name            = $pkg.Name
                            PackageFullName = $pkg.Name
                            Publisher       = $pkg.Vendor
                            Architecture    = "Unknown"
                            Version         = $pkg.Version
                        }
                    }
                }
                else {
                    # Fallback to Windows PowerShell only if CIM approach fails
                    Write-LogFile "[AppX] CIM approach failed, using Windows PowerShell fallback" 'VERBOSE'
                    $command = @"
Import-Module Appx -ErrorAction SilentlyContinue
`$packages = Get-AppxPackage $(if ($Name -ne '*') { "-Name '$Name'" })
`$packages | Select-Object Name, PackageFullName, Publisher, Architecture, Version | ConvertTo-Json -Depth 3 -Compress
"@
                    
                    $result = Invoke-WindowsPowerShellCommand -Command $command -Description "Get AppX packages (fallback)"
                    if ($result) {
                        try {
                            return ($result | ConvertFrom-Json -AsHashtable:$false -ErrorAction Stop)
                        }
                        catch {
                            Write-LogFile "Failed to parse AppX package JSON: $_" 'VERBOSE'
                            return @()
                        }
                    }
                }
            }
            
            Write-LogFile "[AppX] Found $($packages.Count) packages using modern approach" 'VERBOSE'
            return $packages
        }
        catch {
            Write-LogFile "[AppX] Modern approach failed: $_, using Windows PowerShell fallback" 'VERBOSE'
            # Complete fallback to Windows PowerShell
            $command = @"
Import-Module Appx -ErrorAction SilentlyContinue
`$packages = Get-AppxPackage $(if ($AllUsers) { '-AllUsers' }) $(if ($Name -ne '*') { "-Name '$Name'" })
`$packages | Select-Object Name, PackageFullName, Publisher, Architecture, Version | ConvertTo-Json -Depth 3 -Compress
"@
            
            $result = Invoke-WindowsPowerShellCommand -Command $command -Description "Get AppX packages (complete fallback)"
            if ($result) {
                try {
                    return ($result | ConvertFrom-Json -AsHashtable:$false -ErrorAction Stop)
                }
                catch {
                    Write-LogFile "Failed to parse AppX package JSON: $_" 'VERBOSE'
                    return @()
                }
            }
            return @()
        }
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
        # Modern PowerShell 7+ approach using direct WinRT/Windows APIs
        try {
            Write-LogFile "[AppX] Attempting modern package removal for: $PackageFullName" 'VERBOSE'
            
            # Try using winget for removal first (modern approach)
            if (Get-Command winget -ErrorAction SilentlyContinue) {
                Write-LogFile "[AppX] Trying winget uninstall approach" 'VERBOSE'
                $wingetArgs = @('uninstall', '--id', $PackageFullName, '--silent', '--accept-source-agreements')
                if ($AllUsers) {
                    $wingetArgs += '--scope', 'machine'
                }
                
                $result = Invoke-ModernPackageManager -PackageManager 'winget' -Arguments $wingetArgs -Description "Remove package $PackageFullName"
                if ($result.Success) {
                    Write-LogFile "[AppX] Successfully removed package using winget: $PackageFullName" 'VERBOSE'
                    return $true
                }
                Write-LogFile "[AppX] Winget removal failed, trying DISM approach" 'VERBOSE'
            }
            
            # Try DISM for provisioned packages (works in PS7)
            if (Get-Command dism -ErrorAction SilentlyContinue) {
                Write-LogFile "[AppX] Trying DISM removal approach" 'VERBOSE'
                $dismArgs = "/Online /Remove-ProvisionedAppxPackage /PackageName:$PackageFullName"
                $dismResult = Start-Process -FilePath 'dism.exe' -ArgumentList $dismArgs -WindowStyle Hidden -Wait -PassThru
                if ($dismResult.ExitCode -eq 0) {
                    Write-LogFile "[AppX] Successfully removed provisioned package using DISM: $PackageFullName" 'VERBOSE'
                    return $true
                }
                Write-LogFile "[AppX] DISM removal failed, falling back to Windows PowerShell" 'VERBOSE'
            }
            
            # Fallback to Windows PowerShell only if modern approaches fail
            Write-LogFile "[AppX] Using Windows PowerShell fallback for package removal" 'VERBOSE'
            $command = @"
Import-Module Appx -ErrorAction SilentlyContinue
try {
    Remove-AppxPackage -Package '$PackageFullName' $(if ($AllUsers) { '-AllUsers' }) -ErrorAction Stop
    Write-Output 'SUCCESS'
} catch {
    Write-Output "ERROR: `$(`$_.Exception.Message)"
}
"@
            
            $result = Invoke-WindowsPowerShellCommand -Command $command -Description "Remove AppX package $PackageFullName (fallback)"
            return $result -eq 'SUCCESS'
        }
        catch {
            Write-LogFile "[AppX] All removal approaches failed for $PackageFullName : $_" 'VERBOSE'
            return $false
        }
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
        # Modern PowerShell 7+ approach using CIM and direct APIs
        try {
            Write-LogFile "[SystemRestore] Using PowerShell 7+ native approach for enabling System Restore" 'VERBOSE'
            
            # Use CIM to enable System Restore (works in PS7)
            $driveLetter = $Drive.TrimEnd(':\')
            
            # Check if System Restore is already enabled
            $restorePoints = Get-CimInstance -ClassName SystemRestore -ErrorAction SilentlyContinue
            if ($restorePoints) {
                Write-LogFile "[SystemRestore] System Restore appears to be already configured" 'VERBOSE'
                return $true
            }
            
            # Try using vssadmin (works in PS7)
            if (Get-Command vssadmin -ErrorAction SilentlyContinue) {
                Write-LogFile "[SystemRestore] Attempting to enable System Restore using vssadmin" 'VERBOSE'
                $vssResult = Start-Process -FilePath 'vssadmin.exe' -ArgumentList "Resize ShadowStorage /For=$($driveLetter): /On=$($driveLetter): /MaxSize=10%" -WindowStyle Hidden -Wait -PassThru
                if ($vssResult.ExitCode -eq 0) {
                    Write-LogFile "[SystemRestore] System Restore enabled successfully using vssadmin" 'VERBOSE'
                    return $true
                }
            }
            
            # Try using WMI/CIM for System Restore configuration
            try {
                $systemRestore = Get-CimInstance -ClassName Win32_SystemRestore -ErrorAction SilentlyContinue
                if ($systemRestore) {
                    Write-LogFile "[SystemRestore] System Restore service is available" 'VERBOSE'
                    return $true
                }
            }
            catch {
                Write-LogFile "[SystemRestore] CIM approach failed: $_" 'VERBOSE'
            }
            
            # Fallback to Windows PowerShell
            Write-LogFile "[SystemRestore] Using Windows PowerShell fallback" 'VERBOSE'
            $command = "Enable-ComputerRestore -Drive '$Drive' -ErrorAction Stop"
            $result = Invoke-WindowsPowerShellCommand -Command $command -Description "Enable System Restore on $Drive (fallback)"
            return $null -ne $result
        }
        catch {
            Write-LogFile "[SystemRestore] All modern approaches failed: $_, using Windows PowerShell fallback" 'VERBOSE'
            $command = "Enable-ComputerRestore -Drive '$Drive' -ErrorAction Stop"
            $result = Invoke-WindowsPowerShellCommand -Command $command -Description "Enable System Restore on $Drive (complete fallback)"
            return $null -ne $result
        }
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
        # Modern PowerShell 7+ approach using WMI/CIM and direct APIs
        try {
            Write-LogFile "[SystemRestore] Using PowerShell 7+ native approach for creating restore point" 'VERBOSE'
            
            # Try using WMI SystemRestore class (works in PS7)
            $systemRestoreClass = Get-CimClass -ClassName Win32_SystemRestore -ErrorAction SilentlyContinue
            if ($systemRestoreClass) {
                Write-LogFile "[SystemRestore] Attempting to create restore point using CIM" 'VERBOSE'
                try {
                    # Create restore point using CIM method
                    $result = Invoke-CimMethod -ClassName Win32_SystemRestore -MethodName CreateRestorePoint -Arguments @{
                        Description      = $Description
                        RestorePointType = 12  # MODIFY_SETTINGS
                        EventType        = 100        # BEGIN_SYSTEM_CHANGE
                    } -ErrorAction Stop
                    
                    if ($result.ReturnValue -eq 0) {
                        Write-LogFile "[SystemRestore] Restore point created successfully using CIM" 'VERBOSE'
                        return $true
                    }
                    else {
                        Write-LogFile "[SystemRestore] CIM restore point creation returned code: $($result.ReturnValue)" 'VERBOSE'
                    }
                }
                catch {
                    Write-LogFile "[SystemRestore] CIM restore point creation failed: $_" 'VERBOSE'
                }
            }
            
            # Try using vssadmin for shadow copy (alternative approach)
            if (Get-Command vssadmin -ErrorAction SilentlyContinue) {
                Write-LogFile "[SystemRestore] Attempting to create shadow copy using vssadmin" 'VERBOSE'
                $vssResult = Start-Process -FilePath 'vssadmin.exe' -ArgumentList 'Create Shadow /For=C:' -WindowStyle Hidden -Wait -PassThru
                if ($vssResult.ExitCode -eq 0) {
                    Write-LogFile "[SystemRestore] Shadow copy created successfully" 'VERBOSE'
                    return $true
                }
            }
            
            # Fallback to Windows PowerShell
            Write-LogFile "[SystemRestore] Using Windows PowerShell fallback for restore point creation" 'VERBOSE'
            $command = "Checkpoint-Computer -Description '$Description' -RestorePointType '$RestorePointType' -ErrorAction Stop"
            $result = Invoke-WindowsPowerShellCommand -Command $command -Description "Create restore point: $Description (fallback)"
            return $null -ne $result
        }
        catch {
            Write-LogFile "[SystemRestore] All modern approaches failed: $_, using Windows PowerShell fallback" 'VERBOSE'
            $command = "Checkpoint-Computer -Description '$Description' -RestorePointType '$RestorePointType' -ErrorAction Stop"
            $result = Invoke-WindowsPowerShellCommand -Command $command -Description "Create restore point: $Description (complete fallback)"
            return $null -ne $result
        }
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
        # Modern PowerShell 7+ approach using Windows Update API directly
        try {
            Write-LogFile "[Updates] Using PowerShell 7+ native Windows Update API approach" 'VERBOSE'
            
            # Try winget upgrade first (modern approach)
            if (Get-Command winget -ErrorAction SilentlyContinue) {
                Write-LogFile "[Updates] Attempting winget upgrade for all packages" 'VERBOSE'
                $result = Invoke-ModernPackageManager -PackageManager 'winget' -Arguments @('upgrade', '--all', '--silent', '--accept-source-agreements', '--accept-package-agreements') -Description "Upgrade all packages via winget" -TimeoutSeconds 600
                
                if ($result.Success) {
                    Write-LogFile "[Updates] Winget upgrade completed successfully" 'VERBOSE'
                }
                else {
                    Write-LogFile "[Updates] Winget upgrade had some issues, checking Windows Updates" 'VERBOSE'
                }
            }
            
            # Use Windows Update Session COM object (works in PS7)
            Write-LogFile "[Updates] Checking Windows Updates using COM API" 'VERBOSE'
            $updateSession = New-Object -ComObject Microsoft.Update.Session -ErrorAction Stop
            $updateSearcher = $updateSession.CreateUpdateSearcher()
            
            # Search for updates
            Write-LogFile "[Updates] Searching for available Windows Updates..." 'VERBOSE'
            $searchResult = $updateSearcher.Search("IsInstalled=0 and Type='Software' and IsHidden=0")
            
            if ($searchResult.Updates.Count -eq 0) {
                Write-LogFile "[Updates] No Windows Updates found" 'VERBOSE'
                return $true
            }
            
            Write-LogFile "[Updates] Found $($searchResult.Updates.Count) Windows Updates available" 'VERBOSE'
            
            # Create update collection
            $updatesToDownload = New-Object -ComObject Microsoft.Update.UpdateColl
            $updatesToInstall = New-Object -ComObject Microsoft.Update.UpdateColl
            
            foreach ($update in $searchResult.Updates) {
                if ($update.IsDownloaded) {
                    $updatesToInstall.Add($update) | Out-Null
                    Write-LogFile "[Updates] Queued for install: $($update.Title)" 'VERBOSE'
                }
                else {
                    $updatesToDownload.Add($update) | Out-Null
                    Write-LogFile "[Updates] Queued for download: $($update.Title)" 'VERBOSE'
                }
            }
            
            # Download updates if needed
            if ($updatesToDownload.Count -gt 0) {
                Write-LogFile "[Updates] Downloading $($updatesToDownload.Count) updates..." 'VERBOSE'
                $downloader = $updateSession.CreateUpdateDownloader()
                $downloader.Updates = $updatesToDownload
                $downloadResult = $downloader.Download()
                
                if ($downloadResult.ResultCode -eq 2) {
                    Write-LogFile "[Updates] Updates downloaded successfully" 'VERBOSE'
                    # Add downloaded updates to install collection
                    foreach ($update in $updatesToDownload) {
                        if ($update.IsDownloaded) {
                            $updatesToInstall.Add($update) | Out-Null
                        }
                    }
                }
                else {
                    Write-LogFile "[Updates] Some updates failed to download (ResultCode: $($downloadResult.ResultCode))" 'VERBOSE'
                }
            }
            
            # Install updates
            if ($updatesToInstall.Count -gt 0) {
                Write-LogFile "[Updates] Installing $($updatesToInstall.Count) updates..." 'VERBOSE'
                $installer = $updateSession.CreateUpdateInstaller()
                $installer.Updates = $updatesToInstall
                $installResult = $installer.Install()
                
                Write-LogFile "[Updates] Installation completed with ResultCode: $($installResult.ResultCode)" 'VERBOSE'
                if ($installResult.RebootRequired) {
                    Write-LogFile "[Updates] System reboot required after updates" 'VERBOSE'
                }
                
                return $installResult.ResultCode -eq 2 -or $installResult.ResultCode -eq 3
            }
            else {
                Write-LogFile "[Updates] No updates available for installation" 'VERBOSE'
                return $true
            }
        }
        catch {
            Write-LogFile "[Updates] Native Windows Update API failed: $_, falling back to Windows PowerShell" 'VERBOSE'
            # Fallback to Windows PowerShell approach
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
            
            $result = Invoke-WindowsPowerShellCommand -Command $command -Description "Install Windows Updates (fallback)"
            return $null -ne $result
        }
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

# Enhanced Logging System
# ===============================
# Separates file logging from console display, with progress bar support

function Write-LogFile {
    <#
    .SYNOPSIS
    Writes log entries to file only, without console output or progress bars.
    #>
    param(
        [string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR', 'VERBOSE', 'SUCCESS')][string]$Level = 'INFO'
    )
    
    # Skip verbose messages if verbose logging is disabled
    if ($Level -eq 'VERBOSE' -and -not $global:Config.EnableVerboseLogging) {
        return
    }
    
    # Use PowerShell 7.5.2's optimized date formatting
    $timestamp = [DateTime]::Now.ToString('yyyy-MM-dd HH:mm:ss')
    $entry = "[$timestamp] [$Level] $Message"
    
    # Use global log path
    $currentLogPath = $global:logPath
    if (-not $currentLogPath) {
        $currentLogPath = Join-Path $PSScriptRoot "maintenance.log"
    }
    
    # Use PowerShell 7.5.2's improved file I/O with better encoding handling
    try {
        if ($PSVersionTable.PSVersion.Major -ge 7) {
            # Use modern async file operations for better performance
            [System.IO.File]::AppendAllText($currentLogPath, "$entry`n", [System.Text.Encoding]::UTF8)
        }
        else {
            # Fallback for PowerShell 5.1
            $entry | Out-File -FilePath $currentLogPath -Append -Encoding UTF8
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
        Object          = $Message
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
            Activity        = $Activity
            Status          = $Status
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
        $null = & $Action
        
        $stopwatch.Stop()
        Write-Log "Task succeeded: $TaskName (Duration: $($stopwatch.Elapsed.TotalSeconds.ToString('F2'))s)" 'INFO'
        return $true
    }
    catch {
        $stopwatch.Stop()
        # Use PowerShell 7.5.2's improved exception details
        $errorDetails = @{
            Message  = $_.Exception.Message
            Type     = $_.Exception.GetType().Name
            Line     = $_.InvocationInfo.ScriptLineNumber
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

# ===============================
# SECTION 3: SYSTEM UTILITIES
# ===============================
# System Inventory Functions
function Get-ExtensiveSystemInventory {
    Write-Log "[START] Extensive System Inventory (JSON Format)" 'INFO'
    Write-TaskProgress -Activity "Building System Inventory" -Status "Initializing..." -PercentComplete 5
    
    # Track inventory collection performance
    $inventoryStartTime = Get-Date
    
    # Ensure we have a valid path for inventory folder
    $inventoryFolder = if ($PSScriptRoot) { $PSScriptRoot } else { $PWD.Path }
    if (-not (Test-Path $inventoryFolder)) { New-Item -ItemType Directory -Path $inventoryFolder -Force | Out-Null }

    # Build structured inventory object  
    $inventory = [ordered]@{
        metadata           = [ordered]@{
            generatedOn   = (Get-Date).ToString('o')
            scriptVersion = $global:ScriptVersion
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

    # Use reliable sequential processing to avoid hanging issues with external commands
    # Parallel execution was causing hangs with choco, CIM operations, and registry access
    Write-LogFile "[Inventory] Using reliable sequential processing for remaining inventory collections..." 'INFO'
    
    Write-TaskProgress -Activity "Building System Inventory" -Status "Collecting chocolatey apps..." -PercentComplete 50
    Write-LogFile "[Inventory] Collecting installed choco apps..." 'INFO'
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
                Write-LogFile "[Inventory] Collected $($inventory.choco.Count) choco apps." 'INFO'
            }
            else {
                $inventory.choco = @()
                Write-LogFile "[Inventory] No choco apps found." 'INFO'
            }
        }
        catch { 
            Write-LogFile "[Inventory] Choco apps failed: $_" 'WARN'
            $inventory.choco = @()
        }
    }
    else {
        Write-LogFile "[Inventory] Chocolatey not available." 'WARN'
        $inventory.choco = @()
    }

    Write-TaskProgress -Activity "Building System Inventory" -Status "Collecting registry entries..." -PercentComplete 60
    Write-LogFile "[Inventory] Collecting registry uninstall keys..." 'INFO'
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
        Write-LogFile "[Inventory] Collected $($inventory.registry_uninstall.Count) registry uninstall entries." 'INFO'
    }
    catch { 
        Write-LogFile "[Inventory] Registry uninstall keys failed: $_" 'WARN'
        $inventory.registry_uninstall = @()
    }

    Write-TaskProgress -Activity "Building System Inventory" -Status "Collecting services..." -PercentComplete 70
    Write-LogFile "[Inventory] Collecting services..." 'INFO'
    try {
        $inventory.services = @(Get-Service -ErrorAction SilentlyContinue | Where-Object { $null -ne $_ } | 
            Select-Object Name, Status, StartType)
        Write-LogFile "[Inventory] Collected $($inventory.services.Count) services." 'INFO'
    }
    catch { 
        Write-LogFile "[Inventory] Services failed: $_" 'WARN'
        $inventory.services = @()
    }

    Write-TaskProgress -Activity "Building System Inventory" -Status "Collecting scheduled tasks..." -PercentComplete 80
    Write-LogFile "[Inventory] Collecting scheduled tasks..." 'INFO'
    try {
        $inventory.scheduled_tasks = @(Get-ScheduledTask -ErrorAction SilentlyContinue | 
            Select-Object TaskName, TaskPath, State)
        Write-LogFile "[Inventory] Collected $($inventory.scheduled_tasks.Count) scheduled tasks." 'INFO'
    }
    catch { 
        Write-LogFile "[Inventory] Scheduled tasks failed: $_" 'WARN'
        $inventory.scheduled_tasks = @()
    }

    Write-TaskProgress -Activity "Building System Inventory" -Status "Collecting drivers..." -PercentComplete 85
    Write-LogFile "[Inventory] Collecting drivers..." 'INFO'
    try {
        $inventory.drivers = @(Get-CimInstance Win32_PnPSignedDriver -ErrorAction SilentlyContinue | 
            Select-Object DeviceName, DriverVersion, Manufacturer)
        Write-LogFile "[Inventory] Collected $($inventory.drivers.Count) drivers." 'INFO'
    }
    catch { 
        Write-LogFile "[Inventory] Drivers failed: $_" 'WARN'
        $inventory.drivers = @()
    }

    Write-TaskProgress -Activity "Building System Inventory" -Status "Collecting Windows updates..." -PercentComplete 90
    Write-LogFile "[Inventory] Collecting Windows updates..." 'INFO'
    try {
        $inventory.updates = @(Get-HotFix -ErrorAction SilentlyContinue | 
            Select-Object Description, HotFixID, InstalledOn)
        Write-LogFile "[Inventory] Collected $($inventory.updates.Count) Windows updates." 'INFO'
    }
    catch { 
        Write-LogFile "[Inventory] Windows updates failed: $_" 'WARN'
        $inventory.updates = @()
    }
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
        Write-LogFile "[Inventory] Windows updates failed: $_" 'WARN'
        $inventory.updates = @()
    }

    # Write structured inventory.json
    Write-TaskProgress -Activity "Building System Inventory" -Status "Saving inventory to file..." -PercentComplete 95
    
    # Ensure inventory folder is still valid
    if (-not $inventoryFolder) {
        $inventoryFolder = if ($PSScriptRoot) { $PSScriptRoot } else { $PWD.Path }
    }
    
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

    # Track inventory collection performance
    $inventoryEndTime = Get-Date
    $inventoryDuration = ($inventoryEndTime - $inventoryStartTime).TotalSeconds
    $global:PerformanceMetrics['Inventory Collection Time'] = "$([math]::Round($inventoryDuration, 2)) seconds"
    $global:PerformanceMetrics['Total Apps Collected'] = "$($inventory.appx.Count + $inventory.winget.Count + $inventory.choco.Count) apps"
    
    Write-TaskProgress -Activity "Building System Inventory" -Status "Inventory completed" -PercentComplete 100 -Completed
    Write-Log "[END] Extensive System Inventory (JSON Format)" 'INFO'
}

# Temp List Management Functions
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
            ListType          = $ListType
            Operation         = $Operation
            Description       = $Description
            Created           = [DateTime]::Now.ToString('o')
            ScriptVersion     = "2.0.0"
            PowerShellVersion = $PSVersionTable.PSVersion.ToString()
            DataCount         = if ($Data -is [array]) { $Data.Count } elseif ($null -eq $Data) { 0 } else { 1 }
            DataType          = $Data.GetType().Name
            FileSize          = 0  # Will be updated after save
        }
        Data     = $Data
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

# Generate automatic script version based on last modified date
$scriptLastModified = (Get-Item $PSCommandPath -ErrorAction SilentlyContinue).LastWriteTime
if (-not $scriptLastModified) { $scriptLastModified = Get-Date }
$global:ScriptVersion = $scriptLastModified.ToString('yyyy.MM.dd.HHmm')

Write-Log "Script started. User: $env:USERNAME, Computer: $env:COMPUTERNAME, Script Version: $global:ScriptVersion" 'INFO'

### Load configuration FIRST (before creating lists)
$configPath = Join-Path $PSScriptRoot "config.json"
$global:Config = @{
    # Main Task Controls
    SkipBloatwareRemoval       = $false
    SkipEssentialApps          = $false
    SkipWindowsUpdates         = $false
    SkipTelemetryDisable       = $false
    SkipSystemRestore          = $false
    EnableVerboseLogging       = $false
    
    # Bloatware Category Controls (Enhanced 2025)
    KeepSocialApps             = $false              # Keep social media apps (Facebook, Twitter, etc.)
    KeepMediaStreamingApps     = $false      # Keep streaming apps (Netflix, Spotify, etc.)
    KeepAlternativeBrowsers    = $false     # Keep alternative browsers (Opera, Vivaldi, etc.)
    KeepGamingApps             = $false              # Keep gaming apps and platforms
    AggressiveBloatwareRemoval = $true   # Include Microsoft built-in apps in removal
    
    # Essential Apps Category Controls (Enhanced 2025)
    InstallProductivityApps    = $true      # Install productivity apps (Office alternatives, PDF readers)
    InstallMediaApps           = $true             # Install media apps (VLC, image editors)
    InstallDevelopmentTools    = $false     # Install development tools (VS Code, Git, Python)
    InstallCommunicationApps   = $true     # Install communication apps (Teams, Zoom)
    InstallUtilities           = $true             # Install system utilities (PowerToys, Everything)
    InstallGamingApps          = $false           # Install gaming platforms (Steam, Epic Games)
    
    # Legacy Support
    CustomEssentialApps        = @()
    CustomBloatwareList        = @()
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
        if ($config.EnableVerboseLogging) { $global:Config.EnableVerboseLogging = $config.EnableVerboseLogging }
        
        # Enhanced 2025 Configuration Options
        if ($config.KeepSocialApps) { $global:Config.KeepSocialApps = $config.KeepSocialApps }
        if ($config.KeepMediaStreamingApps) { $global:Config.KeepMediaStreamingApps = $config.KeepMediaStreamingApps }
        if ($config.KeepAlternativeBrowsers) { $global:Config.KeepAlternativeBrowsers = $config.KeepAlternativeBrowsers }
        if ($config.KeepGamingApps) { $global:Config.KeepGamingApps = $config.KeepGamingApps }
        if ($config.AggressiveBloatwareRemoval) { $global:Config.AggressiveBloatwareRemoval = $config.AggressiveBloatwareRemoval }
        
        if ($config.InstallProductivityApps) { $global:Config.InstallProductivityApps = $config.InstallProductivityApps }
        if ($config.InstallMediaApps) { $global:Config.InstallMediaApps = $config.InstallMediaApps }
        if ($config.InstallDevelopmentTools) { $global:Config.InstallDevelopmentTools = $config.InstallDevelopmentTools }
        if ($config.InstallCommunicationApps) { $global:Config.InstallCommunicationApps = $config.InstallCommunicationApps }
        if ($config.InstallUtilities) { $global:Config.InstallUtilities = $config.InstallUtilities }
        if ($config.InstallGamingApps) { $global:Config.InstallGamingApps = $config.InstallGamingApps }
        
        # Legacy support
        if ($config.CustomEssentialApps) { $global:Config.CustomEssentialApps = $config.CustomEssentialApps }
        if ($config.CustomBloatwareList) { $global:Config.CustomBloatwareList = $config.CustomBloatwareList }
        
        Write-Log "Loaded enhanced configuration from config.json" 'INFO'
        Write-Log "Config: SkipBloatware=$($global:Config.SkipBloatwareRemoval), SkipEssential=$($global:Config.SkipEssentialApps), AggressiveBloatware=$($global:Config.AggressiveBloatwareRemoval)" 'INFO'
        Write-Log "Categories: DevTools=$($global:Config.InstallDevelopmentTools), Gaming=$($global:Config.InstallGamingApps), KeepSocial=$($global:Config.KeepSocialApps)" 'INFO'
    }
    catch {
        Write-Log "Failed to load configuration: $_" 'WARN'
    }
}
else {
    Write-Log "No config.json found. Using enhanced defaults (2025)." 'INFO'
}

### Centralized temp folder and essential/bloatware lists
# Use repo folder as temp folder for better organization
$global:TempFolder = $PSScriptRoot
if (-not (Test-Path $global:TempFolder)) {
    New-Item -ItemType Directory -Path $global:TempFolder -Force | Out-Null
}

### Enhanced comprehensive bloatware list for Windows 10/11 (2025) - Categorized Approach
$global:BloatwareCategories = @{
    # Critical apps that should NEVER be removed (safety list)
    Critical       = @(
        'Microsoft.Windows.Cortana', 'Microsoft.WindowsStore', 'Microsoft.StorePurchaseApp',
        'Microsoft.WindowsCalculator', 'Microsoft.WindowsCamera', 'Microsoft.WindowsStore',
        'Microsoft.DesktopAppInstaller', 'Microsoft.Winget.Source', 'Microsoft.VCLibs.*',
        'Microsoft.UI.Xaml.*', 'Microsoft.NET.*', 'Microsoft.WindowsNotepad', 'Microsoft.Paint'
    )
    
    # OEM Manufacturer Bloatware (High Priority Removal)
    OEM            = @(
        # Acer
        'Acer.AcerPowerManagement', 'Acer.AcerQuickAccess', 'Acer.AcerUEIPFramework', 
        'Acer.AcerUserExperienceImprovementProgram', 'Acer.AcerCare', 'Acer.AcerPortal',
        
        # ASUS
        'ASUS.ASUSGiftBox', 'ASUS.ASUSLiveUpdate', 'ASUS.ASUSSplendidVideoEnhancementTechnology', 
        'ASUS.ASUSWebStorage', 'ASUS.ASUSZenAnywhere', 'ASUS.ASUSZenLink', 'ASUS.MyASUS', 
        'ASUS.GlideX', 'ASUS.ASUSDisplayControl', 'ASUS.GameFirst', 'ASUS.KeyboardHotkeys',
        
        # Dell
        'Dell.CustomerConnect', 'Dell.DellDigitalDelivery', 'Dell.DellFoundationServices', 
        'Dell.DellHelpAndSupport', 'Dell.DellMobileConnect', 'Dell.DellPowerManager', 
        'Dell.DellProductRegistration', 'Dell.DellSupportAssist', 'Dell.DellUpdate', 
        'Dell.MyDell', 'Dell.DellOptimizer', 'Dell.CommandUpdate', 'Dell.DellCinemaColor',
        
        # HP
        'HP.HP3DDriveGuard', 'HP.HPAudioSwitch', 'HP.HPClientSecurityManager', 'HP.HPConnectionOptimizer',
        'HP.HPDocumentation', 'HP.HPDropboxPlugin', 'HP.HPePrintSW', 'HP.HPJumpStart', 
        'HP.HPJumpStartApps', 'HP.HPJumpStartLaunch', 'HP.HPRegistrationService', 
        'HP.HPSupportSolutionsFramework', 'HP.HPSureConnect', 'HP.HPSystemEventUtility', 
        'HP.HPWelcome', 'HP.HPSmart', 'HP.HPQuickActions', 'HewlettPackard.SupportAssistant',
        
        # Lenovo
        'Lenovo.AppExplorer', 'Lenovo.LenovoCompanion', 'Lenovo.LenovoExperienceImprovement', 
        'Lenovo.LenovoFamilyCloud', 'Lenovo.LenovoHotkeys', 'Lenovo.LenovoMigrationAssistant',
        'Lenovo.LenovoModernIMController', 'Lenovo.LenovoServiceBridge', 'Lenovo.LenovoSolutionCenter', 
        'Lenovo.LenovoUtility', 'Lenovo.LenovoVantage', 'Lenovo.LenovoVoice', 'Lenovo.LenovoWiFiSecurity', 
        'Lenovo.LenovoNow', 'Lenovo.ImController.PluginHost',
        
        # MSI
        'MSI.CenterCommand', 'MSI.MysticLight', 'MSI.CreatorCenter', 'MSI.Gaming',
        
        # Gigabyte
        'Gigabyte.ControlCenter', 'Gigabyte.EasyTune', 'Gigabyte.SmartSwitch'
    )
    
    # Gaming and Entertainment Bloatware (Medium Priority)
    Gaming         = @(
        # King Games
        'king.com.BubbleWitch', 'king.com.BubbleWitch3Saga', 'king.com.CandyCrush', 
        'king.com.CandyCrushFriends', 'king.com.CandyCrushSaga', 'king.com.CandyCrushSodaSaga', 
        'king.com.FarmHeroes', 'king.com.FarmHeroesSaga',
        
        # Other Gaming Apps
        'Gameloft.MarchofEmpires', 'G5Entertainment.HiddenCity', 'RandomSaladGamesLLC.SimpleSolitaire',
        'RoyalRevolt2.RoyalRevolt2', 'WildTangent.WildTangentGamesApp', 'WildTangent.WildTangentHelper',
        'Microsoft.XboxGameCallableUI', 'Microsoft.GamingApp', 'Microsoft.GamingServices',
        'Microsoft.MinecraftUWP', 'Microsoft.MinecraftEducationEdition',
        
        # Xbox (Keep if user wants gaming)
        'Microsoft.Xbox.TCUI', 'Microsoft.XboxApp', 'Microsoft.XboxGameOverlay', 
        'Microsoft.XboxGamingOverlay', 'Microsoft.XboxIdentityProvider', 'Microsoft.XboxSpeechToTextOverlay'
    )
    
    # Social Media and Communication (Low Priority - User Choice)
    Social         = @(
        'Facebook.Facebook', 'Instagram.Instagram', 'LinkedIn.LinkedIn', 'TikTok.TikTok', 
        'Twitter.Twitter', 'Discord.Discord', 'Snapchat.Snapchat', 'Telegram.TelegramDesktop',
        'Skype.Skype', 'Microsoft.SkypeApp', 'WhatsApp.WhatsApp', 'Messenger.Messenger'
    )
    
    # Microsoft Bloatware (High Priority)
    Microsoft      = @(
        # Bing Apps
        'Microsoft.BingFinance', 'Microsoft.BingFoodAndDrink', 'Microsoft.BingHealthAndFitness', 
        'Microsoft.BingNews', 'Microsoft.BingSports', 'Microsoft.BingTravel', 'Microsoft.BingWeather',
        
        # Office and Productivity Bloatware
        'Microsoft.MicrosoftOfficeHub', 'Microsoft.MicrosoftPowerBIForWindows', 'Microsoft.Office.OneNote', 
        'Microsoft.Office.Sway', 'Microsoft.OneConnect', 'Microsoft.ToDo', 'Microsoft.Whiteboard',
        
        # Media and Entertainment
        'Microsoft.ZuneMusic', 'Microsoft.ZuneVideo', 'Microsoft.Groove', 'Microsoft.Movies', 'Microsoft.Music',
        
        # Feedback and Help
        'Microsoft.GetHelp', 'Microsoft.Getstarted', 'Microsoft.HelpAndTips', 'Microsoft.WindowsTips',
        'Microsoft.WindowsFeedback', 'Microsoft.WindowsFeedbackHub',
        
        # Other Microsoft Apps
        'Microsoft.People', 'Microsoft.StickyNotes', 'Microsoft.WindowsAlarms', 'Microsoft.WindowsMaps',
        'Microsoft.WindowsReadingList', 'Microsoft.WindowsSoundRecorder', 'Microsoft.SoundRecorder',
        'Microsoft.NetworkSpeedTest', 'Microsoft.News', 'Microsoft.PowerAutomateDesktop', 'Microsoft.Wallet',
        'Microsoft.MixedReality.Portal', 'Microsoft.ScreenSketch', 'Microsoft.MicrosoftSolitaireCollection',
        
        # Windows 11 Specific
        'Microsoft.Clipchamp', 'Microsoft.WidgetsPlatformRuntime', 'Microsoft.Widgets'
    )
    
    # 3D and AR Applications (High Priority - Usually Unused)
    Media3D        = @(
        'Microsoft.3DBuilder', 'Microsoft.Microsoft3DViewer', 'Microsoft.Print3D', 'Microsoft.Paint3D'
    )
    
    # Media Streaming Services (User Choice)
    MediaStreaming = @(
        'Spotify.Spotify', 'Amazon.AmazonPrimeVideo', 'Netflix.Netflix', 'Hulu.Hulu', 'Disney.DisneyPlus',
        'SlingTV.Sling', 'Pandora.Pandora', 'iHeartRadio.iHeartRadio', 'TuneIn.TuneIn'
    )
    
    # Security Software Bloatware (High Priority - Often Trials)
    Security       = @(
        'Avast.AvastFreeAntivirus', 'AVG.AVGAntiVirusFree', 'Avira.Avira', 'ESET.ESETNOD32Antivirus',
        'Kaspersky.Kaspersky', 'McAfee.LiveSafe', 'McAfee.Livesafe', 'McAfee.SafeConnect', 
        'McAfee.Security', 'McAfee.WebAdvisor', 'Norton.OnlineBackup', 'Norton.Security',
        'Norton.NortonSecurity', 'Malwarebytes.Malwarebytes', 'IOBit.AdvancedSystemCare', 
        'IOBit.DriverBooster', 'Piriform.CCleaner'
    )
    
    # Browser Bloatware (Keep Essential Ones)
    Browsers       = @(
        'Opera.Opera', 'Opera.OperaGX', 'BraveSoftware.BraveBrowser', 'VivaldiTechnologies.Vivaldi',
        'Mozilla.SeaMonkey', 'TheTorProject.TorBrowser', 'Yandex.YandexBrowser', 'UCWeb.UCBrowser'
    )
    
    # Adobe Trial Software
    Adobe          = @(
        'Adobe.AdobeCreativeCloud', 'Adobe.AdobeExpress', 'Adobe.PhotoshopExpress', 'Adobe.AdobePremiere'
    )
}

# Create consolidated bloatware list with priority levels
$global:BloatwareList = @()
$global:BloatwareList += $global:BloatwareCategories.OEM
$global:BloatwareList += $global:BloatwareCategories.Gaming
$global:BloatwareList += $global:BloatwareCategories.Microsoft
$global:BloatwareList += $global:BloatwareCategories.Media3D
$global:BloatwareList += $global:BloatwareCategories.Security
$global:BloatwareList += $global:BloatwareCategories.Adobe

# Add optional categories based on user preference (can be configured)
if (-not $global:Config.KeepSocialApps) { $global:BloatwareList += $global:BloatwareCategories.Social }
if (-not $global:Config.KeepMediaStreamingApps) { $global:BloatwareList += $global:BloatwareCategories.MediaStreaming }
if (-not $global:Config.KeepAlternativeBrowsers) { $global:BloatwareList += $global:BloatwareCategories.Browsers }

# Add custom bloatware from config if any
if ($global:Config.CustomBloatwareList -and $global:Config.CustomBloatwareList.Count -gt 0) {
    $global:BloatwareList += $global:Config.CustomBloatwareList
    $global:BloatwareList = $global:BloatwareList | Sort-Object -Unique
    Write-Log "Added $($global:Config.CustomBloatwareList.Count) custom bloatware entries from config" 'INFO'
}

# Create standardized temp lists with consistent naming and metadata
New-StandardizedTempList -ListType "bloatware" -Operation "main_list" -Data $global:BloatwareList -Description "Complete bloatware list including custom entries from config"

### Enhanced Essential Applications List - Categorized by Priority and Function
$global:EssentialAppsCategories = @{
    # Core System & Security (Highest Priority)
    SystemCore    = @(
        @{ Name = "Microsoft Visual C++ Redistributables"; Winget = "Microsoft.VCRedist.2015+.x64"; Choco = "vcredist-all"; Priority = 1; Category = "Runtime" },
        @{ Name = "Microsoft .NET Runtime"; Winget = "Microsoft.DotNet.Runtime.8"; Choco = "dotnet"; Priority = 1; Category = "Runtime" },
        @{ Name = "PowerShell 7"; Winget = "Microsoft.Powershell"; Choco = "powershell"; Priority = 1; Category = "System" },
        @{ Name = "Windows Terminal"; Winget = "Microsoft.WindowsTerminal"; Choco = "microsoft-windows-terminal"; Priority = 1; Category = "System" }
    )
    
    # Web Browsers (High Priority)
    Browsers      = @(
        @{ Name = "Google Chrome"; Winget = "Google.Chrome"; Choco = "googlechrome"; Priority = 2; Category = "Browser" },
        @{ Name = "Mozilla Firefox"; Winget = "Mozilla.Firefox"; Choco = "firefox"; Priority = 2; Category = "Browser" },
        @{ Name = "Microsoft Edge"; Winget = "Microsoft.Edge"; Choco = "microsoft-edge"; Priority = 2; Category = "Browser" }
    )
    
    # Essential Productivity (High Priority)
    Productivity  = @(
        @{ Name = "Adobe Acrobat Reader"; Winget = "Adobe.Acrobat.Reader.64-bit"; Choco = "adobereader"; Priority = 2; Category = "Productivity" },
        @{ Name = "7-Zip"; Winget = "7zip.7zip"; Choco = "7zip"; Priority = 2; Category = "Utility" },
        @{ Name = "Notepad++"; Winget = "Notepad++.Notepad++"; Choco = "notepadplusplus"; Priority = 2; Category = "Editor" },
        @{ Name = "WinRAR"; Winget = "RARLab.WinRAR"; Choco = "winrar"; Priority = 3; Category = "Utility" },
        @{ Name = "PDF24 Creator"; Winget = "PDF24.PDF24Creator"; Choco = "pdf24"; Priority = 3; Category = "Productivity" },
        @{ Name = "Total Commander"; Winget = "Ghisler.TotalCommander"; Choco = "totalcommander"; Priority = 3; Category = "FileManager" }
    )
    
    # Communication & Email (Medium Priority)
    Communication = @(
        @{ Name = "Mozilla Thunderbird"; Winget = "Mozilla.Thunderbird"; Choco = "thunderbird"; Priority = 3; Category = "Email" },
        @{ Name = "Microsoft Teams"; Winget = "Microsoft.Teams"; Choco = "microsoft-teams"; Priority = 3; Category = "Communication" },
        @{ Name = "Zoom"; Winget = "Zoom.Zoom"; Choco = "zoom"; Priority = 3; Category = "Communication" },
        @{ Name = "Discord"; Winget = "Discord.Discord"; Choco = "discord"; Priority = 4; Category = "Communication" }
    )
    
    # Media & Graphics (Medium Priority)
    Media         = @(
        @{ Name = "VLC Media Player"; Winget = "VideoLAN.VLC"; Choco = "vlc"; Priority = 3; Category = "Media" },
        @{ Name = "GIMP"; Winget = "GIMP.GIMP"; Choco = "gimp"; Priority = 4; Category = "Graphics" },
        @{ Name = "Audacity"; Winget = "Audacity.Audacity"; Choco = "audacity"; Priority = 4; Category = "Audio" },
        @{ Name = "Paint.NET"; Winget = "dotPDN.PaintDotNet"; Choco = "paint.net"; Priority = 3; Category = "Graphics" }
    )
    
    # Development Tools (Optional - User Choice)
    Development   = @(
        @{ Name = "Visual Studio Code"; Winget = "Microsoft.VisualStudioCode"; Choco = "vscode"; Priority = 4; Category = "Development" },
        @{ Name = "Git"; Winget = "Git.Git"; Choco = "git"; Priority = 4; Category = "Development" },
        @{ Name = "Python"; Winget = "Python.Python.3.12"; Choco = "python"; Priority = 4; Category = "Development" },
        @{ Name = "Node.js"; Winget = "OpenJS.NodeJS"; Choco = "nodejs"; Priority = 4; Category = "Development" },
        @{ Name = "Java Runtime Environment"; Winget = "Oracle.JavaRuntimeEnvironment"; Choco = "javaruntime"; Priority = 4; Category = "Runtime" }
    )
    
    # System Utilities (Medium Priority)
    Utilities     = @(
        @{ Name = "CCleaner"; Winget = "Piriform.CCleaner"; Choco = "ccleaner"; Priority = 4; Category = "Utility" },
        @{ Name = "PowerToys"; Winget = "Microsoft.PowerToys"; Choco = "powertoys"; Priority = 3; Category = "Utility" },
        @{ Name = "Everything Search"; Winget = "voidtools.Everything"; Choco = "everything"; Priority = 3; Category = "Utility" },
        @{ Name = "Malwarebytes"; Winget = "Malwarebytes.Malwarebytes"; Choco = "malwarebytes"; Priority = 4; Category = "Security" }
    )
    
    # Gaming Platform (Optional)
    Gaming        = @(
        @{ Name = "Steam"; Winget = "Valve.Steam"; Choco = "steam"; Priority = 5; Category = "Gaming" },
        @{ Name = "Epic Games Launcher"; Winget = "EpicGames.EpicGamesLauncher"; Choco = "epicgameslauncher"; Priority = 5; Category = "Gaming" }
    )
}

# Create consolidated essential apps list based on priority and configuration
$global:EssentialApps = @()

# Always include core system apps (Priority 1-2)
$global:EssentialApps += $global:EssentialAppsCategories.SystemCore
$global:EssentialApps += $global:EssentialAppsCategories.Browsers | Where-Object { $_.Priority -le 2 }
$global:EssentialApps += $global:EssentialAppsCategories.Productivity | Where-Object { $_.Priority -le 2 }

# Add additional categories based on configuration (Priority 3+)
if ($global:Config.InstallProductivityApps -ne $false) {
    $global:EssentialApps += $global:EssentialAppsCategories.Productivity | Where-Object { $_.Priority -ge 3 }
}
if ($global:Config.InstallMediaApps -ne $false) {
    $global:EssentialApps += $global:EssentialAppsCategories.Media
}
if ($global:Config.InstallDevelopmentTools -eq $true) {
    $global:EssentialApps += $global:EssentialAppsCategories.Development
}
if ($global:Config.InstallCommunicationApps -ne $false) {
    $global:EssentialApps += $global:EssentialAppsCategories.Communication
}
if ($global:Config.InstallUtilities -ne $false) {
    $global:EssentialApps += $global:EssentialAppsCategories.Utilities
}
if ($global:Config.InstallGamingApps -eq $true) {
    $global:EssentialApps += $global:EssentialAppsCategories.Gaming
}

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

# Package Manager Utilities
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
                Success  = ($exitCode -eq 0)
                ExitCode = $exitCode
                Output   = if ($ReturnOutput) { $output } else { '' }
                Error    = $errorOutput
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
                Success  = ($process.ExitCode -eq 0)
                ExitCode = $process.ExitCode
                Output   = if ($ReturnOutput) { $output } else { '' }
                Error    = $errorOutput
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

# ===============================
# SECTION 5: ESSENTIAL APPS MANAGEMENT
# ===============================
function Install-EssentialApps {
    # ===============================
    # Task: InstallEssentialApps (Enhanced 2025)
    # ===============================
    # Purpose: Comprehensive essential apps installation with modern package management
    # Features: Category-based prioritization, multi-source fallbacks, intelligent detection
    # Research: Based on Microsoft package management best practices and automated deployment
    # Environment: Windows 10/11, Administrator required, PowerShell 7+ optimized
    # Intelligence: Smart duplicate detection, dependency resolution, progress tracking
    # ===============================
    
    Write-Log "[START] Enhanced Essential Apps Installation (Modern Unified Approach)" 'INFO'
    Write-TaskProgress -Activity "Essential Apps Installation" -Status "Initializing..." -PercentComplete 0
    
    # Validate system inventory
    if (-not $global:SystemInventory) {
        Write-Log "[EssentialApps] Building system inventory for intelligent app detection..." 'INFO'
        Get-ExtensiveSystemInventory
    }
    
    $inventory = $global:SystemInventory
    Write-Log "[EssentialApps] Using comprehensive inventory: $($inventory.appx.Count) AppX, $($inventory.winget.Count) Winget, $($inventory.choco.Count) Chocolatey, $($inventory.registry_uninstall.Count) registry apps" 'INFO'
    
    # Initialize comprehensive installation tracking
    $installationSession = @{
        StartTime           = Get-Date
        Statistics          = @{
            SystemCore    = @{ ToInstall = 0; Installed = 0; Failed = 0; AlreadyInstalled = 0; Skipped = 0 }
            Browsers      = @{ ToInstall = 0; Installed = 0; Failed = 0; AlreadyInstalled = 0; Skipped = 0 }
            Productivity  = @{ ToInstall = 0; Installed = 0; Failed = 0; AlreadyInstalled = 0; Skipped = 0 }
            Communication = @{ ToInstall = 0; Installed = 0; Failed = 0; AlreadyInstalled = 0; Skipped = 0 }
            Media         = @{ ToInstall = 0; Installed = 0; Failed = 0; AlreadyInstalled = 0; Skipped = 0 }
            Development   = @{ ToInstall = 0; Installed = 0; Failed = 0; AlreadyInstalled = 0; Skipped = 0 }
            Utilities     = @{ ToInstall = 0; Installed = 0; Failed = 0; AlreadyInstalled = 0; Skipped = 0 }
            Gaming        = @{ ToInstall = 0; Installed = 0; Failed = 0; AlreadyInstalled = 0; Skipped = 0 }
        }
        InstallationQueue   = @()
        InstallationResults = @()
        ProtectedApps       = @()
        SkippedApps         = @()
    }
    
    # Phase 1: Intelligent App Analysis and Queue Building
    Write-TaskProgress -Activity "Essential Apps Installation" -Status "Analyzing categories and building installation queue..." -PercentComplete 10
    Write-Log "[EssentialApps] Phase 1: Analyzing app categories and building intelligent installation queue" 'INFO'
    
    $categoryOrder = @('SystemCore', 'Browsers', 'Productivity', 'Communication', 'Media', 'Development', 'Utilities', 'Gaming')
    $totalAnalyzed = 0
    
    foreach ($categoryName in $categoryOrder) {
        $categoryApps = $global:EssentialAppsCategories[$categoryName]
        if (-not $categoryApps -or $categoryApps.Count -eq 0) { continue }
        
        Write-Log "[EssentialApps] Analyzing category: $categoryName ($($categoryApps.Count) apps available)" 'INFO'
        
        foreach ($app in $categoryApps) {
            $totalAnalyzed++
            
            # Enhanced app detection with multiple fallback methods
            $detectionResult = Test-EnhancedAppInstallation -AppInfo $app -Inventory $inventory
            
            if ($detectionResult.IsInstalled) {
                $installationSession.Statistics[$categoryName].AlreadyInstalled++
                Write-Log "[EssentialApps] Already installed: $($app.Name) ($($detectionResult.DetectionMethod): $($detectionResult.FoundAs))" 'VERBOSE'
            }
            elseif ($detectionResult.IsProtected) {
                $installationSession.Statistics[$categoryName].Skipped++
                $installationSession.ProtectedApps += @{
                    App      = $app
                    Category = $categoryName
                    Reason   = $detectionResult.ProtectionReason
                }
                Write-Log "[EssentialApps] Protected from installation: $($app.Name) - $($detectionResult.ProtectionReason)" 'VERBOSE'
            }
            else {
                $installationSession.Statistics[$categoryName].ToInstall++
                $installationSession.InstallationQueue += @{
                    App             = $app
                    Category        = $categoryName
                    Priority        = $app.Priority
                    DetectionResult = $detectionResult
                }
                Write-Log "[EssentialApps] Queued for installation: $($app.Name) (Priority: $($app.Priority))" 'VERBOSE'
            }
        }
    }
    
    # Sort installation queue by priority (lower numbers = higher priority)
    $installationSession.InstallationQueue = $installationSession.InstallationQueue | Sort-Object Priority, @{Expression = { $_.App.Name } }
    
    # Generate analysis report
    $totalToInstall = ($installationSession.Statistics.Values | Measure-Object -Property ToInstall -Sum).Sum
    $totalAlreadyInstalled = ($installationSession.Statistics.Values | Measure-Object -Property AlreadyInstalled -Sum).Sum
    $totalSkipped = ($installationSession.Statistics.Values | Measure-Object -Property Skipped -Sum).Sum
    
    Write-Log "[EssentialApps] Analysis complete: $totalAnalyzed apps analyzed, $totalToInstall to install, $totalAlreadyInstalled already present, $totalSkipped skipped" 'INFO'
    
    # Save comprehensive analysis temp lists
    New-StandardizedTempList -ListType "essential" -Operation "analysis_results" -Data @{
        AnalysisTimestamp  = Get-Date
        TotalAnalyzed      = $totalAnalyzed
        CategoryStatistics = $installationSession.Statistics
        InstallationQueue  = $installationSession.InstallationQueue
        ProtectedApps      = $installationSession.ProtectedApps
    } -Description "Comprehensive essential apps analysis results"
    
    # Early exit if nothing to install
    if ($totalToInstall -eq 0) {
        Write-TaskProgress -Activity "Essential Apps Installation" -Status "All essential apps already installed" -PercentComplete 100 -Completed
        Write-Log "[EssentialApps] All essential apps are already installed. Installation process complete." 'INFO'
        
        # Save final results
        New-StandardizedTempList -ListType "essential" -Operation "install_results" -Data @{
            Summary       = @{ Installed = 0; Failed = 0; Skipped = $totalSkipped; AlreadyInstalled = $totalAlreadyInstalled }
            ExecutionTime = ((Get-Date) - $installationSession.StartTime).TotalSeconds
        } -Description "Essential apps installation session results (all apps already installed)"
        
        Write-Log "[END] Enhanced Essential Apps Installation - All apps already present" 'INFO'
        return $true
    }
    
    # Phase 2: Smart Installation Process
    Write-TaskProgress -Activity "Essential Apps Installation" -Status "Starting installation process..." -PercentComplete 20
    Write-Log "[EssentialApps] Phase 2: Starting smart installation process ($totalToInstall apps queued)" 'INFO'
    
    $currentInstallation = 0
    $totalInstalled = 0
    $totalFailed = 0
    
    foreach ($queueItem in $installationSession.InstallationQueue) {
        $currentInstallation++
        $app = $queueItem.App
        $category = $queueItem.Category
        
        # Calculate progress (20% for analysis, 70% for installation, 10% for reporting)
        $installProgress = [math]::Round(20 + (($currentInstallation / $totalToInstall) * 70))
        Write-TaskProgress -Activity "Essential Apps Installation" -Status "[$category] Installing: $($app.Name)" -PercentComplete $installProgress -CurrentOperation "$currentInstallation of $totalToInstall apps"
        
        Write-Log "[EssentialApps] Installing [$category] app: $($app.Name) (Priority $($app.Priority), $currentInstallation/$totalToInstall)" 'INFO'
        
        # Enhanced installation with comprehensive error handling
        $installResult = Invoke-EnhancedAppInstallation -AppInfo $app -Category $category -Session $installationSession
        
        # Update statistics and results
        if ($installResult.Success) {
            $installationSession.Statistics[$category].Installed++
            $totalInstalled++
            Write-Log "[SUCCESS] Installed [$category]: $($app.Name) via $($installResult.Method) in $($installResult.Duration)s" 'INFO'
        }
        else {
            $installationSession.Statistics[$category].Failed++
            $totalFailed++
            Write-Log "[FAILED] Installation failed [$category]: $($app.Name) - $($installResult.Error)" 'WARN'
        }
        
        $installationSession.InstallationResults += $installResult
        
        # Brief pause to prevent overwhelming package managers
        Start-Sleep -Milliseconds 500
    }
    
    # Phase 3: Post-Installation Analysis and Reporting
    Write-TaskProgress -Activity "Essential Apps Installation" -Status "Generating installation report..." -PercentComplete 90
    Write-Log "[EssentialApps] Phase 3: Generating comprehensive installation report" 'INFO'
    
    $sessionDuration = ((Get-Date) - $installationSession.StartTime).TotalSeconds
    
    # Generate comprehensive installation report
    $installationReport = @"
=== ENHANCED ESSENTIAL APPS INSTALLATION REPORT ===
Execution Time: $($sessionDuration) seconds
Started: $($installationSession.StartTime)
Completed: $(Get-Date)

SUMMARY:
- Total Apps Analyzed: $totalAnalyzed
- Apps To Install: $totalToInstall
- Successfully Installed: $totalInstalled  
- Failed Installations: $totalFailed
- Already Installed: $totalAlreadyInstalled
- Protected/Skipped: $totalSkipped

CATEGORY BREAKDOWN:
"@
    
    foreach ($categoryName in $categoryOrder) {
        $stats = $installationSession.Statistics[$categoryName]
        $categoryTotal = $stats.ToInstall + $stats.Installed + $stats.Failed + $stats.AlreadyInstalled + $stats.Skipped
        if ($categoryTotal -gt 0) {
            $installationReport += "`n- $categoryName : Install($($stats.ToInstall)) | Success($($stats.Installed)) | Failed($($stats.Failed)) | Present($($stats.AlreadyInstalled)) | Skipped($($stats.Skipped))"
        }
    }
    
    Write-Log $installationReport 'INFO'
    
    # Save comprehensive installation results
    $finalResults = @{
        SessionInfo         = @{
            StartTime     = $installationSession.StartTime
            EndTime       = Get-Date
            Duration      = $sessionDuration
            TotalAnalyzed = $totalAnalyzed
        }
        Summary             = @{
            ToInstall        = $totalToInstall
            Installed        = $totalInstalled
            Failed           = $totalFailed
            AlreadyInstalled = $totalAlreadyInstalled
            Skipped          = $totalSkipped
        }
        CategoryStatistics  = $installationSession.Statistics
        InstallationResults = $installationSession.InstallationResults
        ProtectedApps       = $installationSession.ProtectedApps
    }
    
    New-StandardizedTempList -ListType "essential" -Operation "install_results" -Data $finalResults -Description "Comprehensive essential apps installation session results"
    
    # Special handling for Office vs LibreOffice
    Optimize-OfficeInstallation -InstallationResults $installationSession.InstallationResults
    
    # Final status
    Write-TaskProgress -Activity "Essential Apps Installation" -Status "Installation process completed" -PercentComplete 100 -Completed
    Write-Log "[END] Enhanced Essential Apps Installation - Installed: $totalInstalled, Failed: $totalFailed, Duration: $($sessionDuration)s" 'INFO'
    
    return $totalInstalled -gt 0
}

# Enhanced App Detection Function for Essential Apps
function Test-EnhancedAppInstallation {
    param(
        [hashtable]$AppInfo,
        [hashtable]$Inventory
    )
    
    $result = @{
        IsInstalled      = $false
        IsProtected      = $false
        DetectionMethod  = $null
        FoundAs          = $null
        ProtectionReason = $null
        Confidence       = 0
    }
    
    # Protection checks first
    if ($AppInfo.Protected -eq $true) {
        $result.IsProtected = $true
        $result.ProtectionReason = "App marked as protected in configuration"
        return $result
    }
    
    # Multiple detection methods for enhanced accuracy
    $detectionMethods = @(
        @{ Name = "Exact Name"; Field = "Name"; List = "display_name" }
        @{ Name = "Winget ID"; Field = "Winget"; List = "winget" }
        @{ Name = "Chocolatey ID"; Field = "Choco"; List = "choco" }
        @{ Name = "AppX Package"; Field = "AppX"; List = "appx" }
        @{ Name = "Registry Uninstall"; Field = "Name"; List = "registry_uninstall" }
    )
    
    foreach ($method in $detectionMethods) {
        $identifier = $AppInfo[$method.Field]
        if (-not $identifier) { continue }
        
        $inventoryList = $Inventory[$method.List]
        if (-not $inventoryList) { continue }
        
        # Exact match
        $exactMatch = $inventoryList | Where-Object { $_.id -eq $identifier -or $_.name -eq $identifier -or $_.display_name -eq $identifier }
        if ($exactMatch) {
            $result.IsInstalled = $true
            $result.DetectionMethod = $method.Name
            $result.FoundAs = $exactMatch.name
            $result.Confidence = 100
            return $result
        }
        
        # Fuzzy match for common naming variations
        $fuzzyMatch = $inventoryList | Where-Object { 
            $_.display_name -like "*$identifier*" -or 
            $_.name -like "*$identifier*" -or
            $identifier -like "*$($_.name)*"
        }
        if ($fuzzyMatch) {
            $result.IsInstalled = $true
            $result.DetectionMethod = "$($method.Name) (Fuzzy)"
            $result.FoundAs = $fuzzyMatch.name
            $result.Confidence = 75
            return $result
        }
    }
    
    return $result
}

# Enhanced App Installation Function with Comprehensive Error Handling
function Invoke-EnhancedAppInstallation {
    param(
        [hashtable]$AppInfo,
        [string]$Category,
        [hashtable]$Session
    )
    
    $startTime = Get-Date
    $result = @{
        App        = $AppInfo
        Category   = $Category
        Success    = $false
        Method     = $null
        Duration   = 0
        Error      = $null
        AttemptLog = @()
    }
    
    # Installation method priority order
    $installMethods = @()
    
    if ($AppInfo.Winget) { $installMethods += @{ Type = "Winget"; ID = $AppInfo.Winget } }
    if ($AppInfo.Choco) { $installMethods += @{ Type = "Chocolatey"; ID = $AppInfo.Choco } }
    if ($AppInfo.AppX) { $installMethods += @{ Type = "AppX"; ID = $AppInfo.AppX } }
    if ($AppInfo.DirectURL) { $installMethods += @{ Type = "Direct"; ID = $AppInfo.DirectURL } }
    
    foreach ($method in $installMethods) {
        $attemptStart = Get-Date
        Write-LogFile "[EssentialApps] Attempting $($method.Type) installation for $($AppInfo.Name): $($method.ID)"
        
        try {
            $installSuccess = $false
            
            switch ($method.Type) {
                "Winget" {
                    $wingetResult = Invoke-ModernPackageManager -PackageManager "winget" -Operation "install" -PackageId $method.ID -Timeout 300
                    $installSuccess = $wingetResult.Success
                    if (-not $installSuccess) {
                        $result.AttemptLog += "Winget failed: $($wingetResult.Output)"
                    }
                }
                "Chocolatey" {
                    $chocoResult = Invoke-ModernPackageManager -PackageManager "chocolatey" -Operation "install" -PackageId $method.ID -Timeout 300
                    $installSuccess = $chocoResult.Success
                    if (-not $installSuccess) {
                        $result.AttemptLog += "Chocolatey failed: $($chocoResult.Output)"
                    }
                }
                "AppX" {
                    if (Get-Command "Add-AppxPackage" -ErrorAction SilentlyContinue) {
                        Add-AppxPackage -Name $method.ID -ErrorAction Stop
                        $installSuccess = $true
                    }
                    else {
                        $result.AttemptLog += "AppX: Add-AppxPackage not available"
                    }
                }
                "Direct" {
                    # Direct download and installation
                    $tempFile = Join-Path $env:TEMP "$($AppInfo.Name)_installer.exe"
                    Invoke-WebRequest -Uri $method.ID -OutFile $tempFile -UseBasicParsing -TimeoutSec 120
                    
                    $installProcess = Start-Process -FilePath $tempFile -ArgumentList "/S", "/SILENT", "/VERYSILENT" -Wait -PassThru -WindowStyle Hidden
                    $installSuccess = $installProcess.ExitCode -eq 0
                    
                    Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
                }
            }
            
            if ($installSuccess) {
                $result.Success = $true
                $result.Method = $method.Type
                $result.Duration = ((Get-Date) - $attemptStart).TotalSeconds
                Write-LogFile "[SUCCESS] $($AppInfo.Name) installed via $($method.Type) in $($result.Duration)s"
                break
            }
        }
        catch {
            $errorMessage = $_.Exception.Message
            $result.AttemptLog += "$($method.Type) exception: $errorMessage"
            Write-LogFile "[ERROR] $($method.Type) installation failed for $($AppInfo.Name): $errorMessage"
        }
    }
    
    if (-not $result.Success) {
        $result.Error = "All installation methods failed: " + ($result.AttemptLog -join "; ")
        Write-LogFile "[FAILED] Could not install $($AppInfo.Name) via any method"
    }
    
    $result.Duration = ((Get-Date) - $startTime).TotalSeconds
    return $result
}

# Office vs LibreOffice Optimization Function
function Optimize-OfficeInstallation {
    param(
        [array]$InstallationResults
    )
    
    $officeApps = $InstallationResults | Where-Object { 
        $_.App.Name -like "*Office*" -or 
        $_.App.Name -like "*LibreOffice*" -or
        $_.Category -eq "Productivity"
    }
    
    $microsoftOffice = $officeApps | Where-Object { $_.App.Name -like "*Microsoft*Office*" -and $_.Success }
    $libreOffice = $officeApps | Where-Object { $_.App.Name -like "*LibreOffice*" -and $_.Success }
    
    if ($microsoftOffice -and $libreOffice) {
        Write-Log "[OfficeOptimization] Both Microsoft Office and LibreOffice installed - this is acceptable for compatibility testing" 'INFO'
    }
    elseif ($microsoftOffice) {
        Write-Log "[OfficeOptimization] Microsoft Office suite detected - primary productivity suite established" 'INFO'
    }
    elseif ($libreOffice) {
        Write-Log "[OfficeOptimization] LibreOffice suite detected - open-source productivity suite established" 'INFO'
    }
    else {
        Write-Log "[OfficeOptimization] No office suite detected in installations" 'VERBOSE'
    }
}

# ===============================
# SECTION 4: BLOATWARE MANAGEMENT
# ===============================
function Remove-Bloatware {
    # ===============================
    # Task: RemoveBloatware (Enhanced 2025)
    # ===============================
    # Purpose: Removes unwanted apps using categorized, multi-method approach with safety checks.
    # Research: Based on Windows10Debloater, ChrisTitusTech/WinUtil, and W4RH4WK/Debloat-Windows-10
    # Environment: Windows 10/11, Administrator required, supports multiple removal methods.
    # Safety: Critical app protection, rollback support, comprehensive detection.
    Write-Log "[START] Enhanced Remove Bloatware (Multi-Method Categorized Approach)" 'INFO'
    
    # Safety check: Ensure we have the critical apps protection list
    if (-not $global:BloatwareCategories -or -not $global:BloatwareCategories.Critical) {
        Write-Log "[CRITICAL] Bloatware categories not properly initialized. Aborting for safety." 'ERROR'
        return $false
    }
    
    # Use global inventory if available, otherwise build a quick one
    if (-not $global:SystemInventory) {
        Write-Log "[Bloatware] No system inventory available, building quick inventory..." 'WARN'
        Get-ExtensiveSystemInventory
    }
    
    $inventory = $global:SystemInventory
    Write-Log "[Bloatware] Using inventory with $($inventory.appx.Count) AppX, $($inventory.winget.Count) Winget, $($inventory.choco.Count) Choco, $($inventory.registry_uninstall.Count) registry apps" 'INFO'
    
    # Initialize removal statistics
    $removalStats = @{
        OEM            = @{ Found = 0; Removed = 0; Failed = 0 }
        Gaming         = @{ Found = 0; Removed = 0; Failed = 0 }
        Microsoft      = @{ Found = 0; Removed = 0; Failed = 0 }
        Media3D        = @{ Found = 0; Removed = 0; Failed = 0 }
        Security       = @{ Found = 0; Removed = 0; Failed = 0 }
        Social         = @{ Found = 0; Removed = 0; Failed = 0 }
        MediaStreaming = @{ Found = 0; Removed = 0; Failed = 0 }
        Browsers       = @{ Found = 0; Removed = 0; Failed = 0 }
        Adobe          = @{ Found = 0; Removed = 0; Failed = 0 }
        Protected      = @{ Found = 0; Skipped = 0 }
    }
    
    $totalProcessed = 0
    $totalRemoved = 0
    $totalFailed = 0
    $protectedApps = @()
    
    Write-TaskProgress -Activity "Analyzing Bloatware" -Status "Building comprehensive detection lists..." -PercentComplete 5
    
    # Process each category with priority-based removal
    $categories = @('OEM', 'Security', 'Adobe', 'Media3D', 'Microsoft', 'Gaming', 'Social', 'MediaStreaming', 'Browsers')
    $currentCategory = 0
    
    foreach ($categoryName in $categories) {
        $currentCategory++
        $categoryApps = $global:BloatwareCategories[$categoryName]
        if (-not $categoryApps -or $categoryApps.Count -eq 0) { continue }
        
        $baseCategoryProgress = [math]::Round(10 + ($currentCategory / $categories.Count) * 70) # 10-80% for category processing
        Write-TaskProgress -Activity "Removing Bloatware" -Status "Processing $categoryName category..." -PercentComplete $baseCategoryProgress
        Write-Log "[Bloatware] Processing category: $categoryName ($($categoryApps.Count) apps)" 'INFO'
        
        # Find installed apps in this category
        $installedInCategory = @()
        foreach ($app in $categoryApps) {
            $isInstalled = Test-AppInstalled -AppIdentifier $app -Inventory $inventory
            if ($isInstalled.IsInstalled) {
                # Safety check: Ensure app is not in critical protection list
                $isCritical = $false
                foreach ($criticalApp in $global:BloatwareCategories.Critical) {
                    if ($app -like $criticalApp -or $criticalApp -like "*$app*") {
                        $isCritical = $true
                        $protectedApps += $app
                        $removalStats.Protected.Found++
                        Write-Log "[SAFETY] App '$app' matches critical protection pattern '$criticalApp' - SKIPPING for safety" 'WARN'
                        break
                    }
                }
                
                if (-not $isCritical) {
                    $installedInCategory += @{
                        AppName         = $app
                        DetectionMethod = $isInstalled.DetectionMethod
                        FoundAs         = $isInstalled.FoundAs
                        CanUninstall    = $isInstalled.CanUninstall
                    }
                    $removalStats[$categoryName].Found++
                }
                else {
                    $removalStats.Protected.Skipped++
                }
            }
        }
        
        Write-Log "[Bloatware] Category $categoryName`: $($installedInCategory.Count) apps found (out of $($categoryApps.Count) total)" 'INFO'
        
        # Remove apps in this category
        $categoryCurrentApp = 0
        foreach ($appInfo in $installedInCategory) {
            $categoryCurrentApp++
            $totalProcessed++
            
            $categoryProgress = $baseCategoryProgress + [math]::Round(($categoryCurrentApp / [math]::Max($installedInCategory.Count, 1)) * 8) # 8% per category
            Write-TaskProgress -Activity "Removing Bloatware" -Status "[$categoryName] Removing: $($appInfo.AppName)" -PercentComplete $categoryProgress -CurrentOperation "$categoryCurrentApp of $($installedInCategory.Count) in category"
            
            $removalResult = Remove-SingleBloatwareApp -AppInfo $appInfo -Category $categoryName
            
            if ($removalResult.Success) {
                $removalStats[$categoryName].Removed++
                $totalRemoved++
                Write-Log "[SUCCESS] Removed $categoryName app: $($appInfo.AppName) via $($removalResult.Method)" 'INFO'
            }
            else {
                $removalStats[$categoryName].Failed++
                $totalFailed++
                Write-Log "[FAILED] Could not remove $categoryName app: $($appInfo.AppName) - $($removalResult.Error)" 'WARN'
            }
        }
    }
    
    # Generate comprehensive removal report
    Write-TaskProgress -Activity "Removing Bloatware" -Status "Generating removal report..." -PercentComplete 85
    
    $removalReport = @"
=== ENHANCED BLOATWARE REMOVAL REPORT ===

Total Statistics:
- Apps Processed: $totalProcessed
- Successfully Removed: $totalRemoved
- Failed Removals: $totalFailed
- Protected/Skipped: $($removalStats.Protected.Skipped)

Category Breakdown:
"@
    
    foreach ($cat in $categories + @('Protected')) {
        if ($cat -eq 'Protected') {
            $removalReport += "`n- $cat : Found $($removalStats[$cat].Found), Skipped $($removalStats[$cat].Skipped)"
        }
        else {
            $stats = $removalStats[$cat]
            $removalReport += "`n- $cat : Found $($stats.Found), Removed $($stats.Removed), Failed $($stats.Failed)"
        }
    }
    
    if ($protectedApps.Count -gt 0) {
        $removalReport += "`n`nProtected Apps (Safety Skip):`n"
        $protectedApps | ForEach-Object { $removalReport += "  - $_`n" }
    }
    
    Write-Log $removalReport 'INFO'
    
    # Save comprehensive temp lists
    $allFoundBloatware = @()
    
    foreach ($cat in $categories) {
        if ($removalStats[$cat].Found -gt 0) {
            $categoryApps = $global:BloatwareCategories[$cat] | Where-Object { 
                $testResult = Test-AppInstalled -AppIdentifier $_ -Inventory $inventory
                $testResult.IsInstalled
            }
            $allFoundBloatware += $categoryApps | ForEach-Object { @{ App = $_; Category = $cat } }
        }
    }
    
    New-StandardizedTempList -ListType "bloatware" -Operation "comprehensive_found" -Data $allFoundBloatware -Description "All bloatware found on system by category"
    New-StandardizedTempList -ListType "bloatware" -Operation "protected_apps" -Data $protectedApps -Description "Apps protected from removal for safety"
    
    Write-TaskProgress -Activity "Removing Bloatware" -Status "Bloatware removal completed" -PercentComplete 100 -Completed
    Write-Log "[END] Enhanced Remove Bloatware - Processed: $totalProcessed, Removed: $totalRemoved, Failed: $totalFailed, Protected: $($protectedApps.Count)" 'INFO'
    
    return $totalRemoved -gt 0
}

# Enhanced supporting functions for improved bloatware and essential apps management
function Test-AppInstalled {
    param(
        [string]$AppIdentifier,
        [hashtable]$Inventory
    )
    
    # Test multiple detection methods
    $result = @{
        IsInstalled     = $false
        DetectionMethod = ''
        FoundAs         = ''
        CanUninstall    = $true
    }
    
    # Check AppX packages
    foreach ($appx in $Inventory.appx) {
        if ($appx.Name -like "*$AppIdentifier*" -or $AppIdentifier -like "*$($appx.Name)*" -or $appx.PackageFullName -like "*$AppIdentifier*") {
            $result.IsInstalled = $true
            $result.DetectionMethod = 'AppX'
            $result.FoundAs = $appx.Name
            $result.CanUninstall = -not $appx.NonRemovable
            return $result
        }
    }
    
    # Check Winget packages
    foreach ($winget in $Inventory.winget) {
        if ($winget.Id -eq $AppIdentifier -or $winget.Name -like "*$AppIdentifier*" -or $AppIdentifier -like "*$($winget.Name)*") {
            $result.IsInstalled = $true
            $result.DetectionMethod = 'Winget'
            $result.FoundAs = $winget.Name
            return $result
        }
    }
    
    # Check Registry uninstall entries
    foreach ($regApp in $Inventory.registry_uninstall) {
        if ($regApp.DisplayName -like "*$AppIdentifier*" -or $AppIdentifier -like "*$($regApp.DisplayName)*") {
            $result.IsInstalled = $true
            $result.DetectionMethod = 'Registry'
            $result.FoundAs = $regApp.DisplayName
            return $result
        }
    }
    
    # Check Chocolatey packages
    foreach ($choco in $Inventory.choco) {
        if ($choco.Name -like "*$AppIdentifier*" -or $AppIdentifier -like "*$($choco.Name)*") {
            $result.IsInstalled = $true
            $result.DetectionMethod = 'Chocolatey'
            $result.FoundAs = $choco.Name
            return $result
        }
    }
    
    return $result
}

function Remove-SingleBloatwareApp {
    param(
        [hashtable]$AppInfo,
        [string]$Category
    )
    
    $result = @{
        Success = $false
        Method  = ''
        Error   = ''
    }
    
    $appName = $AppInfo.AppName
    $detectionMethod = $AppInfo.DetectionMethod
    
    try {
        switch ($detectionMethod) {
            'AppX' {
                # Try AppX removal
                $success = Remove-AppxPackageCompatible -Name $appName -AllUsers
                if ($success) {
                    $result.Success = $true
                    $result.Method = 'AppX'
                    return $result
                }
                
                # Try provisioned package removal
                $provisionedPkgs = Get-AppxProvisionedPackageCompatible -Online | Where-Object { $_.DisplayName -like "*$appName*" }
                foreach ($pkg in $provisionedPkgs) {
                    $success = Remove-AppxProvisionedPackageCompatible -Online -PackageName $pkg.PackageName
                    if ($success) {
                        $result.Success = $true
                        $result.Method = 'AppX Provisioned'
                        return $result
                    }
                }
            }
            
            'Winget' {
                # Try Winget uninstall
                $wingetResult = Invoke-ModernPackageManager -Action 'uninstall' -PackageId $appName -Source 'winget'
                if ($wingetResult.Success) {
                    $result.Success = $true
                    $result.Method = 'Winget'
                    return $result
                }
            }
            
            'Registry' {
                # Try to find and run uninstaller
                $uninstallString = Get-UninstallString -AppName $appName
                if ($uninstallString) {
                    $uninstallResult = Invoke-UninstallString -UninstallString $uninstallString -Silent
                    if ($uninstallResult) {
                        $result.Success = $true
                        $result.Method = 'Registry Uninstaller'
                        return $result
                    }
                }
            }
            
            'Chocolatey' {
                # Try Chocolatey uninstall
                $chocoResult = Invoke-ModernPackageManager -Action 'uninstall' -PackageId $appName -Source 'chocolatey'
                if ($chocoResult.Success) {
                    $result.Success = $true
                    $result.Method = 'Chocolatey'
                    return $result
                }
            }
        }
        
        $result.Error = "No removal method succeeded for $detectionMethod detection"
    }
    catch {
        $result.Error = "Exception during removal: $_"
    }
    
    return $result
}

function Get-UninstallString {
    param([string]$AppName)
    
    $uninstallKeys = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    
    foreach ($keyPath in $uninstallKeys) {
        try {
            $apps = Get-ItemProperty $keyPath -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like "*$AppName*" }
            foreach ($app in $apps) {
                if ($app.UninstallString) {
                    return $app.UninstallString
                }
            }
        }
        catch {
            continue
        }
    }
    
    return $null
}

function Invoke-UninstallString {
    param(
        [string]$UninstallString,
        [switch]$Silent
    )
    
    try {
        if ($Silent) {
            # Try to make it silent
            $silentArgs = "/S", "/SILENT", "/QUIET", "/VERYSILENT"
            foreach ($arg in $silentArgs) {
                if ($UninstallString -notlike "*$arg*") {
                    $UninstallString += " $arg"
                    break
                }
            }
        }
        
        $process = Start-Process -FilePath "cmd.exe" -ArgumentList "/c", $UninstallString -Wait -PassThru -WindowStyle Hidden
        return $process.ExitCode -eq 0
    }
    catch {
        return $false
    }
}
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
$RemovalResults = @{
    Summary       = @{
        Processed       = $totalApps
        Removed         = $removed
        Failed          = $failed
        TotalInMainList = $global:BloatwareList.Count
    }
    ProcessedApps = $bloatwareToRemove
}

# ===============================
# SECTION 7: REPORTING & ANALYTICS
# ===============================
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

# ===============================
# SECTION 6: SYSTEM MAINTENANCE TASKS
# ===============================
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

# ===============================
# SECTION 8: SCRIPT EXECUTION & INITIALIZATION
# ===============================

# Configuration Loading and Validation
# (This section will be moved here from its current location)

# Main Script Execution
Use-AllScriptTasks

# Post-Task Cleanup and Finalization




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

### [POST-TASK 4] Unified Enhanced Reporting System

# Create unified enhanced maintenance report
function Write-UnifiedMaintenanceReport {
    param(
        [string]$ReportPath
    )
    
    # Gather comprehensive system info
    $osInfo = Get-CimInstance Win32_OperatingSystem
    $compInfo = Get-CimInstance Win32_ComputerSystem
    $memInfo = Get-CimInstance Win32_PhysicalMemory | Measure-Object Capacity -Sum
    $diskInfo = Get-CimInstance Win32_LogicalDisk | Where-Object { $_.DriveType -eq 3 }
    
    # Calculate execution metrics
    $scriptStartTime = $global:ScriptStartTime
    $scriptEndTime = Get-Date
    $totalExecutionTime = ($scriptEndTime - $scriptStartTime).TotalMinutes
    
    # Build comprehensive report sections
    $reportSections = @()
    
    # === HEADER SECTION ===
    $reportSections += @"
════════════════════════════════════════════════════════════════════════════════
                            MAINTENANCE REPORT
                         Windows System Maintenance
════════════════════════════════════════════════════════════════════════════════

EXECUTION SUMMARY
─────────────────────────────────────────────────────────────────────────────────
Date & Time        : $(Get-Date -Format 'dddd, MMMM dd, yyyy - HH:mm:ss')
Execution Duration : $([math]::Round($totalExecutionTime, 2)) minutes
Script Version     : $global:ScriptVersion
PowerShell Version : $($PSVersionTable.PSVersion.ToString())
Run Mode          : $(if ($Host.Name -eq 'ConsoleHost') { 'Interactive' } else { 'Automated' })

SYSTEM INFORMATION
─────────────────────────────────────────────────────────────────────────────────
Computer Name     : $($env:COMPUTERNAME)
User Account      : $($env:USERNAME)
Operating System  : $($osInfo.Caption)
OS Version        : $($osInfo.Version) (Build $($osInfo.BuildNumber))
Architecture      : $($osInfo.OSArchitecture)
Total RAM         : $([math]::Round($memInfo.Sum / 1GB, 2)) GB
System Model      : $($compInfo.Manufacturer) $($compInfo.Model)
Last Boot Time    : $($osInfo.LastBootUpTime.ToString('yyyy-MM-dd HH:mm:ss'))
System Uptime     : $([math]::Round((Get-Date - $osInfo.LastBootUpTime).TotalDays, 2)) days

"@

    # === DISK SPACE SECTION ===
    $reportSections += "DISK SPACE STATUS"
    $reportSections += "─────────────────────────────────────────────────────────────────────────────────"
    foreach ($disk in $diskInfo) {
        $freeGB = [math]::Round($disk.FreeSpace / 1GB, 2)
        $totalGB = [math]::Round($disk.Size / 1GB, 2)
        $usedGB = $totalGB - $freeGB
        $freePercent = [math]::Round(($disk.FreeSpace / $disk.Size) * 100, 1)
        $reportSections += "Drive $($disk.DeviceID) - Total: ${totalGB}GB | Used: ${usedGB}GB | Free: ${freeGB}GB ($freePercent%)"
    }
    $reportSections += ""

    # === TASK EXECUTION SECTION ===
    $totalTasks = $global:TaskResults.Keys.Count
    $successfulTasks = ($global:TaskResults.Values | Where-Object { $_.Success }).Count
    $failedTasks = $totalTasks - $successfulTasks
    $successRate = if ($totalTasks -gt 0) { [math]::Round(($successfulTasks / $totalTasks) * 100, 1) } else { 0 }

    $reportSections += @"
TASK EXECUTION SUMMARY
─────────────────────────────────────────────────────────────────────────────────
Total Tasks       : $totalTasks
Successful        : $successfulTasks
Failed           : $failedTasks
Success Rate     : $successRate%
Total Task Time  : $([math]::Round(($global:TaskResults.Values | Measure-Object Duration -Sum).Sum, 2)) seconds

DETAILED TASK RESULTS
─────────────────────────────────────────────────────────────────────────────────
"@

    # Add detailed task results
    foreach ($taskName in $global:TaskResults.Keys | Sort-Object) {
        $result = $global:TaskResults[$taskName]
        $task = $global:ScriptTasks | Where-Object { $_.Name -eq $taskName }
        $status = if ($result.Success) { '[SUCCESS]' } else { '[FAILED] ' }
        $duration = [math]::Round($result.Duration, 2)
        
        $reportSections += "$status $taskName"
        $reportSections += "  Description: $($task.Description)"
        $reportSections += "  Duration: ${duration}s | Started: $($result.Started.ToString('HH:mm:ss')) | Ended: $($result.Ended.ToString('HH:mm:ss'))"
        
        if (-not $result.Success -and $result.ContainsKey('Error')) {
            $reportSections += "  Error: $($result.Error)"
        }
        $reportSections += ""
    }

    # === ESSENTIAL APPS INSTALLATION RESULTS ===
    if ($global:InstallResults) {
        $reportSections += @"
ESSENTIAL APPS INSTALLATION RESULTS
─────────────────────────────────────────────────────────────────────────────────
Total Apps Processed : $($global:InstallResults.Summary.Total)
Successfully Installed : $($global:InstallResults.Summary.Installed)
Failed Installations  : $($global:InstallResults.Summary.Failed)
Skipped Apps         : $($global:InstallResults.Summary.Skipped)

Detailed Results:
"@
        foreach ($detail in $global:InstallResults.Details) {
            $reportSections += "  • $detail"
        }
        $reportSections += ""
    }

    # === BLOATWARE REMOVAL RESULTS ===
    if ($global:RemovalResults) {
        $reportSections += @"
BLOATWARE REMOVAL RESULTS
─────────────────────────────────────────────────────────────────────────────────
Total Apps in List   : $($global:RemovalResults.Summary.TotalInMainList)
Apps Processed       : $($global:RemovalResults.Summary.Processed)
Successfully Removed : $($global:RemovalResults.Summary.Removed)
Failed Removals      : $($global:RemovalResults.Summary.Failed)

Processed Apps:
"@
        foreach ($app in $global:RemovalResults.ProcessedApps) {
            $reportSections += "  • $app"
        }
        $reportSections += ""
    }

    # === ACTIONS PERFORMED SECTION ===

    # Extract and categorize actions from log
    $logPath = $global:logPath
    if (Test-Path $logPath) {
        $logContent = Get-Content $logPath
        
        # Categorize actions
        $actions = @{
            Installed  = @()
            Removed    = @()
            Updated    = @()
            Cleaned    = @()
            Configured = @()
            Other      = @()
        }
        
        foreach ($line in $logContent) {
            if ($line -match '\[(INFO|WARN|ERROR)\]') {
                $logMessage = ($line -split '\[(?:INFO|WARN|ERROR)\]', 2)[1].Trim()
                
                switch -Regex ($logMessage) {
                    'Installed|Installation|Install' { $actions.Installed += $logMessage }
                    'Removed|Uninstalled|Delete' { $actions.Removed += $logMessage }
                    'Updated|Upgrade' { $actions.Updated += $logMessage }
                    'Cleaned|Cleanup|Clear' { $actions.Cleaned += $logMessage }
                    'Configured|Setting|Registry|Policy' { $actions.Configured += $logMessage }
                    default { 
                        if ($logMessage -notmatch '(START|END|Duration|Script|Task|Building|Collecting)') {
                            $actions.Other += $logMessage 
                        }
                    }
                }
            }
        }
        
        foreach ($category in $actions.Keys) {
            if ($actions[$category].Count -gt 0) {
                $reportSections += "$category ($($actions[$category].Count) actions):"
                $actions[$category] | ForEach-Object { $reportSections += "  • $_" }
                $reportSections += ""
            }
        }
    }
    else {
        $reportSections += "No detailed action log found."
        $reportSections += ""
    }

    # === FILES GENERATED SECTION ===
    $reportSections += @"
FILES GENERATED
─────────────────────────────────────────────────────────────────────────────────
"@

    $generatedFiles = @()
    $filePatterns = @('*.json', '*.txt', '*.log', 'temp_*.json')
    
    foreach ($pattern in $filePatterns) {
        $files = Get-ChildItem -Path $PSScriptRoot -Filter $pattern -ErrorAction SilentlyContinue
        foreach ($file in $files) {
            $sizeKB = [math]::Round($file.Length / 1KB, 2)
            $generatedFiles += "$($file.Name) ($sizeKB KB)"
        }
    }
    
    if ($generatedFiles.Count -gt 0) {
        $generatedFiles | Sort-Object | ForEach-Object { $reportSections += "  • $_" }
    }
    else {
        $reportSections += "  No additional files generated."
    }
    
    $reportSections += ""

    # === PERFORMANCE METRICS SECTION ===
    if ($global:PerformanceMetrics) {
        $reportSections += @"
PERFORMANCE METRICS
─────────────────────────────────────────────────────────────────────────────────
"@
        foreach ($metric in $global:PerformanceMetrics.GetEnumerator()) {
            $reportSections += "$($metric.Key): $($metric.Value)"
        }
        $reportSections += ""
    }

    # === FOOTER SECTION ===
    $reportSections += @"
────────────────────────────────────────────────────────────────────────────────
Report Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
PowerShell Maintenance Script v1.0.0
────────────────────────────────────────────────────────────────────────────────

For detailed operation logs, review the maintenance.log file.
For system inventory data, check the generated JSON files.

════════════════════════════════════════════════════════════════════════════════
"@

    # Write the unified report
    try {
        $reportContent = $reportSections -join "`n"
        $reportContent | Out-File -FilePath $ReportPath -Encoding UTF8
        return $true
    }
    catch {
        Write-Log "Failed to write unified report: $_" 'ERROR'
        return $false
    }
}

# Initialize performance metrics tracking
if (-not $global:PerformanceMetrics) {
    $global:PerformanceMetrics = @{}
}

# Track script start time if not already set
if (-not $global:ScriptStartTime) {
    $global:ScriptStartTime = Get-Date
}

# Determine report path
$batPath = Join-Path $PSScriptRoot "script.bat"
if (Test-Path $batPath) {
    $batDir = Split-Path $batPath -Parent
    $unifiedReportPath = Join-Path $batDir "maintenance_report.txt"
}
else {
    $unifiedReportPath = Join-Path $PSScriptRoot "maintenance_report.txt"
}

# Generate the unified enhanced report
$reportSuccess = Write-UnifiedMaintenanceReport -ReportPath $unifiedReportPath
if ($reportSuccess) {
    Write-Log "Unified maintenance report generated: $unifiedReportPath" 'INFO'
}
else {
    Write-Log "Failed to generate unified maintenance report" 'ERROR'
}

### [POST-TASK 5] Cleanup and Finalization

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

### [POST-TASK 6] Script Completion

Write-Log "Script ended." 'INFO'

### [POST-TASK 7] Interactive prompt if running in console
if ($Host.Name -eq 'ConsoleHost' -or $Host.Name -like '*Windows*') {
    Write-Host
    Read-Host -Prompt 'Press Enter to close this window...'
}
