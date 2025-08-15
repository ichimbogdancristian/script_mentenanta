# ===============================
# Windows Maintenance Script - Task Coordinator
# ===============================
# This script is designed to automate and orchestrate a full suite of Windows maintenance tasks.
# It is intended to run as Administrator on Windows 10/11, with all actions logged and reported.
# Each task is modular, robust, and designed for unattended execution in enterprise or home environments.
#
# Key Environment Details:
# - Compatible with PowerShell 7+ and Windows PowerShell 5.1
# - Must be run as Administrator
# - Uses $PSScriptRoot for all temp and log files
# - Integrates with Winget, Chocolatey, AppX (via Windows PowerShell), DISM, Registry, and Windows Capabilities
# - All actions are silent/non-interactive
# - Graceful degradation if dependencies are missing
# - Automatically switches to Windows PowerShell for legacy module operations
#
# Task Array: $global:ScriptTasks
# Each entry defines a maintenance task with its logic, description, and config-driven enable/disable.

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
    # --- Task: UpdateAllPackages ---
    # Purpose: Updates all installed packages via Winget and Chocolatey.
    # Environment: Windows 10/11, admin required, silent/non-interactive.
    # Logic: Tries both package managers, logs all actions and errors.
    @{ Name = 'UpdateAllPackages'; Function = {
            Write-Log '[START] Update All Apps and Packages' 'INFO'
            # Dependency installation is handled by script.bat. If Winget or Chocolatey is missing, log and exit.
            if (-not $global:HasWinget) {
                Write-Log 'Winget not available. Please run the script via script.bat to ensure all dependencies are installed.' 'ERROR'
                exit 1
            }
            if (-not $global:HasChocolatey) {
                Write-Log 'Chocolatey not available. Please run the script via script.bat to ensure all dependencies are installed.' 'ERROR'
                exit 1
            }
            try {
                Write-Log 'Running winget upgrade for all packages...' 'INFO'
                winget upgrade --all --silent --accept-source-agreements --accept-package-agreements
                Write-Log 'Winget upgrade completed successfully.' 'INFO'
            }
            catch {
                Write-Log "Winget upgrade failed: $_" 'WARN'
            }
            try {
                Write-Log 'Running chocolatey upgrade for all packages...' 'INFO'
                choco upgrade all -y --limit-output
                Write-Log 'Chocolatey upgrade completed successfully.' 'INFO'
            }
            catch {
                Write-Log "Chocolatey upgrade failed: $_" 'WARN'
            }
            Write-Log '[END] Update All Apps and Packages' 'INFO'
        }; Description = 'Update all apps and packages' 
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
            foreach ($folder in $tempFolders | Sort-Object -Unique) {
                if (Test-Path $folder) {
                    $items = Get-ChildItem -Path $folder -Recurse -ErrorAction SilentlyContinue
                    foreach ($item in $items) {
                        try {
                            Remove-Item $item.FullName -Force -Recurse -ErrorAction Stop
                            $deletedFiles++
                        }
                        catch {
                            Write-Log "Failed to delete $($item.FullName): $_" 'WARN'
                        }
                    }
                }
            }
            Write-Log "Deleted $deletedFiles temp files from temp folders." 'INFO'
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

### Load configuration (if exists) - MUST BE EARLY TO SUPPORT TASK DEFINITIONS
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
    }
    catch {
        # Note: Write-Log not available yet, this will be logged later
    }
}

# Main Coordinator Function
function Use-AllScriptTasks {
    Write-Log '[COORDINATION] Starting all maintenance tasks...' 'INFO'
    $global:TaskResults = @{}
    foreach ($task in $global:ScriptTasks) {
        $taskName = $task.Name
        $desc = $task.Description
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
    Write-Log '[COORDINATION] All maintenance tasks completed.' 'INFO'
}

# [PRE-TASK 0] Set up log file in the repo folder
$logPath = Join-Path $PSScriptRoot "maintenance.log"

# [PRE-TASK 1] Essential Logging Function - MUST BE DEFINED EARLY
function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR', 'VERBOSE')][string]$Level = 'INFO'
    )
    
    # Skip verbose messages if verbose logging is disabled
    if ($Level -eq 'VERBOSE' -and -not $global:Config.EnableVerboseLogging) {
        return
    }
    
    $timestamp = Get-Date -Format 'HH:mm:ss'
    $entry = "[$timestamp] [$Level] $Message"
    $entry | Out-File -FilePath $logPath -Append
    
    # Color-code output based on level
    switch ($Level) {
        'ERROR' { Write-Host $entry -ForegroundColor Red }
        'WARN' { Write-Host $entry -ForegroundColor Yellow }
        'VERBOSE' { Write-Host $entry -ForegroundColor Gray }
        default { Write-Host $entry }
    }
}

### PowerShell 7 Compatibility Functions
function Invoke-WindowsPowerShellCommand {
    param(
        [string]$Command,
        [string]$Description = "Windows PowerShell command"
    )
    
    Write-Log "[PS5.1] Executing via Windows PowerShell: $Description" 'INFO'
    
    try {
        # Create a script block to execute in Windows PowerShell
        $encodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($Command))
        
        $result = & powershell.exe -EncodedCommand $encodedCommand
        
        if ($LASTEXITCODE -eq 0) {
            Write-Log "[PS5.1] Successfully executed: $Description" 'INFO'
            return $result
        }
        else {
            Write-Log "[PS5.1] Command failed with exit code $LASTEXITCODE`: $Description" 'WARN'
            return $null
        }
    }
    catch {
        Write-Log "[PS5.1] Exception executing command: $_" 'ERROR'
        return $null
    }
}

function Get-AppxPackageCompatible {
    param(
        [string]$Name = "*",
        [switch]$AllUsers
    )
    
    if ($PSVersionTable.PSVersion.Major -ge 7) {
        # Use Windows PowerShell for Appx operations
        $command = "Import-Module Appx -ErrorAction SilentlyContinue; Get-AppxPackage"
        if ($AllUsers) { $command += " -AllUsers" }
        if ($Name -ne "*") { $command += " -Name '$Name'" }
        $command += " | Select-Object Name, PackageFullName, Publisher | ConvertTo-Json -Depth 3"
        
        $result = Invoke-WindowsPowerShellCommand -Command $command -Description "Get AppX packages"
        if ($result) {
            try {
                return ($result | ConvertFrom-Json)
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
        # Use Windows PowerShell for Appx operations
        $command = "Import-Module Appx -ErrorAction SilentlyContinue; Remove-AppxPackage -Package '$PackageFullName'"
        if ($AllUsers) { $command += " -AllUsers" }
        $command += " -ErrorAction Stop"
        
        $result = Invoke-WindowsPowerShellCommand -Command $command -Description "Remove AppX package $PackageFullName"
        return $null -ne $result
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
        # Dependency installation is handled by script.bat. If PSWindowsUpdate is missing, log and exit.
        if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate -ErrorAction SilentlyContinue)) {
            Write-Log 'PSWindowsUpdate module missing. Please run the script via script.bat to ensure all dependencies are installed.' 'ERROR'
            exit 1
        }

        Import-Module PSWindowsUpdate -ErrorAction Stop

        # Get and install updates
        $command = @"
    try {
        \$updates = Get-WindowsUpdate -AcceptAll -Install -ErrorAction Stop
        if (\$updates) {
            \$updateTitles = \$updates | Select-Object -ExpandProperty Title -ErrorAction SilentlyContinue -Unique
            Write-Host "Installed updates: \$(`\$updateTitles -join ', ')"
        }
        else {
            Write-Host 'No new updates were found or installed.'
        }
    }
    catch {
        Write-Host "Failed to check or install Windows Updates: \$_"
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

### [PRE-TASK 1] Task Functions
function Invoke-Task {
    param(
        [string]$TaskName,
        [scriptblock]$Action
    )
    Write-Log "Starting task: $TaskName" 'INFO'
    try {
        & $Action
        Write-Log "Task succeeded: $TaskName" 'INFO'
        return $true
    }
    catch {
        Write-Log "Task failed: $TaskName. Error: $_" 'ERROR'
        return $false
    }
}

### [PRE-TASK 2] Extensive System Inventory (Initial)
function Get-ExtensiveSystemInventory {
    Write-Log "[START] Extensive System Inventory (JSON Format)" 'INFO'
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

    Write-Log "[Inventory] Collecting system info..." 'INFO'
    try {
        $systemInfo = Get-ComputerInfo
        $inventory.system = $systemInfo
        Write-Log "[Inventory] System info collected." 'INFO'
    }
    catch { 
        Write-Log "[Inventory] System info failed: $_" 'WARN'
        $inventory.system = @{ error = $_.ToString() }
    }

    Write-Log "[Inventory] Collecting installed Appx apps..." 'INFO'
    try {
        $appxPackages = Get-AppxPackageCompatible -AllUsers
        if ($appxPackages -and $appxPackages.Count -gt 0) {
            $inventory.appx = @($appxPackages | Select-Object Name, PackageFullName, Publisher)
            Write-Log "[Inventory] Collected $($inventory.appx.Count) Appx apps." 'INFO'
        }
        else {
            Write-Log "[Inventory] No Appx apps found or module not available." 'WARN'
            $inventory.appx = @()
        }
    }
    catch { 
        Write-Log "[Inventory] Appx apps failed: $_" 'WARN'
        $inventory.appx = @()
    }

    Write-Log "[Inventory] Collecting installed winget apps..." 'INFO'
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

    # Write structured inventory.json
    $inventoryPath = Join-Path $inventoryFolder 'inventory.json'
    try {
        $inventory | ConvertTo-Json -Depth 6 | Out-File -FilePath $inventoryPath -Encoding UTF8
        Write-Log "[Inventory] Structured inventory saved to inventory.json" 'INFO'
        
        # Store global reference for diff operations
        $global:SystemInventory = $inventory
    }
    catch {
        Write-Log "[Inventory] Failed to write inventory.json: $_" 'WARN'
    }

    Write-Log "[END] Extensive System Inventory (JSON Format)" 'INFO'
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

$bloatwareListPath = Join-Path $global:TempFolder 'bloatware.json'
$global:BloatwareList | ConvertTo-Json -Depth 3 | Out-File $bloatwareListPath -Encoding UTF8

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

$essentialAppsListPath = Join-Path $global:TempFolder 'essential_apps.json'
$global:EssentialApps | ConvertTo-Json -Depth 5 | Out-File $essentialAppsListPath -Encoding UTF8

### Config is already loaded early in the script, add logging here
Write-Log "Loaded configuration from config.json" 'INFO'
Write-Log "Config: SkipBloatware=$($global:Config.SkipBloatwareRemoval), SkipEssential=$($global:Config.SkipEssentialApps), SkipUpdates=$($global:Config.SkipWindowsUpdates)" 'INFO'

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



### [TASK 2] Install Essential Apps - Diff-Based Approach
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

        # Build comprehensive list of all installed app identifiers for matching (normalized)
        $installedIdentifiers = @()
        # Add AppX package names
        $inventory.appx | ForEach-Object {
            if ($_.Name) { $installedIdentifiers += $_.Name.ToLower().Trim() }
        }
        # Add Winget app names and IDs
        $inventory.winget | ForEach-Object {
            if ($_.Name) { $installedIdentifiers += $_.Name.ToLower().Trim() }
            if ($_.Id) { $installedIdentifiers += $_.Id.ToLower().Trim() }
        }
        # Add Chocolatey app names
        $inventory.choco | ForEach-Object {
            if ($_.Name) { $installedIdentifiers += $_.Name.ToLower().Trim() }
        }
        # Add registry app display names
        $inventory.registry_uninstall | ForEach-Object {
            if ($_.DisplayName) { $installedIdentifiers += $_.DisplayName.ToLower().Trim() }
        }
        # Remove duplicates and create lookup for faster matching
        $installedIdentifiers = $installedIdentifiers | Where-Object { $null -ne $_ -and $_ -ne '' } | Sort-Object -Unique
        Write-Log "[EssentialApps] Total unique installed identifiers: $($installedIdentifiers.Count)" 'INFO'

        # Find essential apps that are NOT installed (diff operation, normalized)
        $appsToInstall = @()
        foreach ($essentialApp in $global:EssentialApps) {
            $found = $false
            # Normalize all possible identifiers for the essential app
            $essentialIdentifiers = @()
            if ($essentialApp.Winget) { $essentialIdentifiers += $essentialApp.Winget.ToLower().Trim() }
            if ($essentialApp.Choco) { $essentialIdentifiers += $essentialApp.Choco.ToLower().Trim() }
            if ($essentialApp.Name) { $essentialIdentifiers += $essentialApp.Name.ToLower().Trim() }
            $essentialIdentifiers = $essentialIdentifiers | Where-Object { $null -ne $_ -and $_ -ne '' } | Sort-Object -Unique

            foreach ($installed in $installedIdentifiers) {
                foreach ($essId in $essentialIdentifiers) {
                    if ($installed -eq $essId) {
                        $found = $true
                        break
                    }
                }
                if ($found) { break }
            }
            if (-not $found) {
                $appsToInstall += $essentialApp
            }
        }

    Write-Log "[EssentialApps] Diff analysis: $($appsToInstall.Count) essential apps need installation (out of $($global:EssentialApps.Count) total in list)" 'INFO'

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

    foreach ($app in $appsToInstall) {
        $installSuccess = $false
        $installMethod = ""
        $wingetAvailable = Get-Command winget -ErrorAction SilentlyContinue
        $chocoAvailable = Get-Command choco -ErrorAction SilentlyContinue
        
        try {
            # Try Winget first (preferred)
            if ($app.Winget -and $wingetAvailable) {
                Write-Log "Installing $($app.Name) via winget..." 'INFO'
                $wingetArgs = @(
                    "install", "--id", $app.Winget,
                    "--accept-source-agreements", "--accept-package-agreements", "--silent", "-e"
                )
                $wingetProc = Start-Process -FilePath "winget" -ArgumentList $wingetArgs -WindowStyle Hidden -Wait -PassThru
                if ($wingetProc.ExitCode -eq 0) {
                    $installSuccess = $true
                    $installMethod = "winget"
                }
                else {
                    Write-Log "$($app.Name) winget install failed with exit code $($wingetProc.ExitCode)" 'WARN'
                }
            }
            
            # Try Chocolatey as fallback
            if (-not $installSuccess -and $app.Choco -and $chocoAvailable) {
                Write-Log "Installing $($app.Name) via choco..." 'INFO'
                $chocoArgs = @("install", $app.Choco, "-y", "--no-progress")
                $chocoProc = Start-Process -FilePath "choco" -ArgumentList $chocoArgs -WindowStyle Hidden -Wait -PassThru
                if ($chocoProc.ExitCode -eq 0) {
                    $installSuccess = $true
                    $installMethod = "choco"
                }
                else {
                    Write-Log "$($app.Name) choco install failed with exit code $($chocoProc.ExitCode)" 'WARN'
                }
            }
            
            # Log results
            if ($installSuccess) {
                Write-Log "Installed: $($app.Name) via $installMethod" 'INFO'
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
                $libreArgs = @(
                    "install", "--id", "TheDocumentFoundation.LibreOffice",
                    "--accept-source-agreements", "--accept-package-agreements", "--silent", "-e"
                )
                $libreProc = Start-Process -FilePath "winget" -ArgumentList $libreArgs -NoNewWindow -WindowStyle Hidden -Wait -PassThru
                if ($libreProc.ExitCode -eq 0) {
                    Write-Log "LibreOffice installed via winget." 'INFO'
                    $libreSuccess = $true
                    $success++
                    $detailedResults += "SUCCESS: LibreOffice via winget"
                }
                else {
                    Write-Log "LibreOffice winget install failed with exit code $($libreProc.ExitCode)" 'WARN'
                }
            }
            if (-not $libreSuccess -and (Get-Command choco -ErrorAction SilentlyContinue)) {
                $chocoLibreArgs = @("install", "libreoffice-fresh", "-y", "--no-progress")
                $chocoLibreProc = Start-Process -FilePath "choco" -ArgumentList $chocoLibreArgs -NoNewWindow -WindowStyle Hidden -Wait -PassThru
                if ($chocoLibreProc.ExitCode -eq 0) {
                    Write-Log "LibreOffice installed via choco." 'INFO'
                    $libreSuccess = $true
                    $success++
                    $detailedResults += "SUCCESS: LibreOffice via choco"
                }
                else {
                    Write-Log "LibreOffice choco install failed with exit code $($chocoLibreProc.ExitCode)" 'WARN'
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

    Write-Log "Install Essential Apps summary: Installed: $success, Failed: $fail, Skipped: $skipped" 'INFO'
    foreach ($result in $detailedResults) {
        Write-Log $result 'INFO'
    }
    Write-Log "[END] Install Essential Apps" 'INFO'
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
    
    # Build comprehensive list of all installed app identifiers (normalized)
    $installedIdentifiers = @()
    # Add AppX package names and IDs
    $inventory.appx | ForEach-Object {
        if ($_.Name) { $installedIdentifiers += $_.Name.ToLower().Trim() }
        if ($_.PackageFullName) { $installedIdentifiers += $_.PackageFullName.ToLower().Trim() }
    }
    # Add Winget app names and IDs
    $inventory.winget | ForEach-Object {
        if ($_.Name) { $installedIdentifiers += $_.Name.ToLower().Trim() }
        if ($_.Id) { $installedIdentifiers += $_.Id.ToLower().Trim() }
    }
    # Add Chocolatey app names
    $inventory.choco | ForEach-Object {
        if ($_.Name) { $installedIdentifiers += $_.Name.ToLower().Trim() }
    }
    # Add registry app display names
    $inventory.registry_uninstall | ForEach-Object {
        if ($_.DisplayName) { $installedIdentifiers += $_.DisplayName.ToLower().Trim() }
    }
    # Remove duplicates and create lookup for faster matching
    $installedIdentifiers = $installedIdentifiers | Where-Object { $null -ne $_ -and $_ -ne '' } | Sort-Object -Unique
    Write-Log "[Bloatware] Total unique installed identifiers: $($installedIdentifiers.Count)" 'INFO'
    
    # Normalize bloatware list for matching
    $normalizedBloatwareList = $global:BloatwareList | ForEach-Object { $_.ToLower().Trim() }
    $bloatwareToRemove = @()
    foreach ($bloatApp in $normalizedBloatwareList) {
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
    
    # Save the diff list to temporary file for debugging
    $diffListPath = Join-Path $global:TempFolder 'bloatware_diff_to_remove.json'
    $bloatwareToRemove | ConvertTo-Json -Depth 3 | Out-File $diffListPath -Encoding UTF8
    Write-Log "[Bloatware] Diff list saved to: $diffListPath" 'VERBOSE'
    
    # Save the apps NOT found (for debugging purposes)
    $appsNotFound = $global:BloatwareList | Where-Object { $_ -notin $bloatwareToRemove }
    $notFoundPath = Join-Path $global:TempFolder 'bloatware_not_found.json'
    $appsNotFound | ConvertTo-Json -Depth 3 | Out-File $notFoundPath -Encoding UTF8
    Write-Log "[Bloatware] Apps not found on system saved to: $notFoundPath" 'VERBOSE'
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

    # Check module availability
    $appxAvailable = $false
    if ($PSVersionTable.PSVersion.Major -ge 7) {
        try {
            $testCommand = "Get-Module -ListAvailable -Name Appx -ErrorAction SilentlyContinue | Select-Object Name"
            $result = Invoke-WindowsPowerShellCommand -Command $testCommand -Description "Test Appx module"
            $appxAvailable = $null -ne $result
        }
        catch {
            Write-Log "Failed to test Appx module: $_" 'WARN'
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
            Write-Log "Failed to load Appx module: $_" 'WARN'
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
        # Validation: Ensure this app is indeed in our diff list
        if ($app -notin $bloatwareToRemove) {
            Write-Log "[ERROR] App '$app' is not in the diff list but is being processed. This should not happen!" 'ERROR'
            continue
        }
        
        Write-Log "[Bloatware] Processing app from diff list: $app" 'VERBOSE'
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
                                    Write-Log "Removed AppX package: $($pkg.Name) ($($pkg.PackageFullName))" 'INFO'
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
                                Write-Log "Removed provisioned package: $($pkg.DisplayName) ($($pkg.PackageName))" 'INFO'
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
                                    Write-Log "DISM removed provisioned package: $packageName" 'INFO'
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
                                        $uninstallCmd = $props.UninstallString -replace '"', ''
                                        if ($uninstallCmd -like "*.exe*") {
                                            Start-Process -FilePath $uninstallCmd -ArgumentList "/S" -Wait -WindowStyle Hidden -ErrorAction SilentlyContinue
                                            Write-Log "Attempted registry-based removal: $browser" 'INFO'
                                            $appRemoved = $true
                                            $removalMethods += 'Registry-EXE'
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
                Write-Log "Bloatware removal failed or not found: $app" 'WARN'
                $failed++
            }
        }
        catch {
            Write-Log "Exception during removal of $app`: $_" 'ERROR'
            $failed++
        }
        
        Start-Sleep -Milliseconds 100
    }

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
    Write-Log "[END] Enhanced Remove Bloatware" 'INFO'
}

### [TASK 4] System Inventory (Legacy)
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
    # Environment: Windows 10/11, admin required, modifies registry, disables services/tasks, configures browsers.
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
                $removalMethods = @()
                # Try winget removal first
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
                                        $appRemoved = $true
                                        $removalMethods += 'Registry-EXE'
                                    }
                                }
                                catch {
                                    Write-Log "Registry uninstall failed for $browser`: $_" 'VERBOSE'
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

                # Ensure registry paths exist before setting properties
                foreach ($regPath in @($httpReg, $httpsReg, $htmlReg, $htmReg)) {
                    if (-not (Test-Path $regPath)) {
                        try {
                            $parentPath = Split-Path $regPath
                            if (-not (Test-Path $parentPath)) {
                                New-Item -Path $parentPath -Force | Out-Null
                            }
                            New-Item -Path $regPath -Force | Out-Null
                        }
                        catch {}
                    }
                }

                # Set Firefox as default for HTTP/HTTPS protocols
                if (Test-Path $httpReg) { Set-ItemProperty -Path $httpReg -Name 'ProgId' -Value $firefoxProgId -Force -ErrorAction SilentlyContinue }
                if (Test-Path $httpsReg) { Set-ItemProperty -Path $httpsReg -Name 'ProgId' -Value $firefoxProgId -Force -ErrorAction SilentlyContinue }
                if (Test-Path $htmlReg) { Set-ItemProperty -Path $htmlReg -Name 'ProgId' -Value $firefoxProgId -Force -ErrorAction SilentlyContinue }
                if (Test-Path $htmReg) { Set-ItemProperty -Path $htmReg -Name 'ProgId' -Value $firefoxProgId -Force -ErrorAction SilentlyContinue }

                Write-Log "Firefox set as default browser via registry." 'INFO'
            }
            catch {
                # Fallback to Firefox command line method
                try {
                    Start-Process -FilePath $firefoxPath -ArgumentList "-setDefaultBrowser" -Wait -WindowStyle Hidden -ErrorAction SilentlyContinue
                    Write-Log "Attempted to set Firefox as default browser via command line." 'INFO'
                }
                catch {
                    Write-Log "Failed to set Firefox as default browser via command line: $_" 'WARN'
                }
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
            $serviceObj = Get-Service -Name $svc -ErrorAction SilentlyContinue
            if ($serviceObj -and $serviceObj.Status -ne 'Stopped') {
                Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
                Write-Log "Stopped service: $svc" 'INFO'
            }
            if ($serviceObj) {
                Set-Service -Name $svc -StartupType Disabled -ErrorAction SilentlyContinue
                Write-Log "Disabled service: $svc" 'INFO'
            }
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
