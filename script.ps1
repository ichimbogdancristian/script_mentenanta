# =============================================
# Windows Maintenance Script - Task Coordinator
# =============================================
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
    # Purpose: Updates all installed packages via Winget and Chocolatey using parallel processing.
    # Environment: Windows 10/11, admin required, silent/non-interactive, enhanced performance.
    # Logic: Parallel execution, smart filtering, detailed update tracking, action-only logging.
    @{ Name = 'UpdateAllPackages'; Function = { Update-AllPackages }; Description = 'Enhanced parallel package updates (Winget + Chocolatey)' },
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



### [TASK 2] Install Essential Apps - Optimized Parallel Approach
function Install-EssentialApps {
    # ===============================
    # Task: InstallEssentialApps (Enhanced Performance & Reliability)
    # ===============================
    # Purpose: Installs essential applications using parallel processing and smart filtering.
    # Environment: Windows 10/11, must run as Administrator, supports config-driven custom app lists.
    # Logic: O(1) hashtable lookups, parallel installation, comprehensive validation, action-only logging.
    # Performance: Uses HashSet for O(1) lookups, parallel jobs for batch installations, smart pre-filtering.
    Write-Log "[START] Install Essential Apps (Optimized Parallel Approach)" 'INFO'

    # Use global inventory if available, otherwise build a quick one
    if (-not $global:SystemInventory) {
        Write-Log "[EssentialApps] Building system inventory..." 'INFO'
        Get-ExtensiveSystemInventory
    }
    
    $inventory = $global:SystemInventory

    # Build comprehensive hashtable of all installed app identifiers (normalized) for O(1) lookups
    $installedLookup = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    
    # Add AppX package names and IDs
    $inventory.appx | ForEach-Object {
        if ($_.Name) { [void]$installedLookup.Add($_.Name.Trim()) }
        if ($_.PackageFullName) { [void]$installedLookup.Add($_.PackageFullName.Trim()) }
    }
    
    # Add Winget app names and IDs
    $inventory.winget | ForEach-Object {
        if ($_.Name) { [void]$installedLookup.Add($_.Name.Trim()) }
        if ($_.Id) { [void]$installedLookup.Add($_.Id.Trim()) }
    }
    
    # Add Chocolatey app names
    $inventory.choco | ForEach-Object {
        if ($_.Name) { [void]$installedLookup.Add($_.Name.Trim()) }
    }
    
    # Add registry app display names
    $inventory.registry_uninstall | ForEach-Object {
        if ($_.DisplayName) { [void]$installedLookup.Add($_.DisplayName.Trim()) }
    }

    # Smart filtering: find essential apps that are NOT installed using O(1) lookups
    $appsToInstall = @()
    foreach ($essentialApp in $global:EssentialApps) {
        $found = $false
        
        # Check all possible identifiers for the essential app
        $identifiersToCheck = @()
        if ($essentialApp.Winget) { $identifiersToCheck += $essentialApp.Winget.Trim() }
        if ($essentialApp.Choco) { $identifiersToCheck += $essentialApp.Choco.Trim() }
        if ($essentialApp.Name) { $identifiersToCheck += $essentialApp.Name.Trim() }
        
        # Use HashSet.Contains for O(1) lookup performance
        foreach ($identifier in $identifiersToCheck) {
            if ($installedLookup.Contains($identifier)) {
                $found = $true
                break
            }
        }
        
        if (-not $found) {
            $appsToInstall += $essentialApp
        }
    }

    if ($appsToInstall.Count -eq 0) {
        Write-Log "[EssentialApps] All essential apps already installed. Skipping installation process." 'INFO'
        Write-Log "[END] Install Essential Apps" 'INFO'
        return
    }

    # Pre-check package manager availability once
    $wingetAvailable = $null -ne (Get-Command winget -ErrorAction SilentlyContinue)
    $chocoAvailable = $null -ne (Get-Command choco -ErrorAction SilentlyContinue)
    
    if (-not $wingetAvailable -and -not $chocoAvailable) {
        Write-Log "[EssentialApps] ERROR: No package managers available (winget/choco). Cannot install apps." 'ERROR'
        Write-Log "[END] Install Essential Apps" 'INFO'
        return
    }

    Write-Log "[EssentialApps] Processing $($appsToInstall.Count) apps for installation..." 'INFO'

    # Initialize counters and results collection
    $successfulInstalls = [System.Collections.Concurrent.ConcurrentBag[PSCustomObject]]::new()
    $failedInstalls = [System.Collections.Concurrent.ConcurrentBag[PSCustomObject]]::new()
    $skippedInstalls = [System.Collections.Concurrent.ConcurrentBag[PSCustomObject]]::new()

    # Create installation jobs for parallel processing
    $installJobs = @()
    
    foreach ($app in $appsToInstall) {
        $job = Start-Job -ArgumentList $app, $wingetAvailable, $chocoAvailable -ScriptBlock {
            param($app, $wingetAvailable, $chocoAvailable)
            
            $result = @{
                AppName = $app.Name
                Success = $false
                Method = ""
                Error = ""
                Skipped = $false
                SkipReason = ""
            }
            
            try {
                # Try Winget first (preferred method)
                if ($app.Winget -and $wingetAvailable) {
                    $wingetArgs = @(
                        "install", "--id", $app.Winget,
                        "--accept-source-agreements", "--accept-package-agreements", 
                        "--silent", "-e", "--disable-interactivity"
                    )
                    $wingetProc = Start-Process -FilePath "winget" -ArgumentList $wingetArgs -WindowStyle Hidden -Wait -PassThru -NoNewWindow
                    if ($wingetProc.ExitCode -eq 0) {
                        $result.Success = $true
                        $result.Method = "winget"
                        return $result
                    }
                    elseif ($wingetProc.ExitCode -eq -1978335189) {
                        # App already installed
                        $result.Skipped = $true
                        $result.SkipReason = "already installed (winget)"
                        return $result
                    }
                    else {
                        $result.Error += "winget failed (exit: $($wingetProc.ExitCode)); "
                    }
                }
                
                # Try Chocolatey as fallback
                if (-not $result.Success -and $app.Choco -and $chocoAvailable) {
                    $chocoArgs = @("install", $app.Choco, "-y", "--no-progress", "--limit-output")
                    $chocoProc = Start-Process -FilePath "choco" -ArgumentList $chocoArgs -WindowStyle Hidden -Wait -PassThru -NoNewWindow
                    if ($chocoProc.ExitCode -eq 0) {
                        $result.Success = $true
                        $result.Method = "choco"
                        return $result
                    }
                    elseif ($chocoProc.ExitCode -eq 1641 -or $chocoProc.ExitCode -eq 3010) {
                        # Success with reboot required
                        $result.Success = $true
                        $result.Method = "choco (reboot required)"
                        return $result
                    }
                    else {
                        $result.Error += "choco failed (exit: $($chocoProc.ExitCode))"
                    }
                }
                
                # No installation method succeeded
                if (-not $wingetAvailable -and -not $chocoAvailable) {
                    $result.Skipped = $true
                    $result.SkipReason = "no package manager available"
                }
                elseif (-not $app.Winget -and -not $app.Choco) {
                    $result.Skipped = $true
                    $result.SkipReason = "no installer defined"
                }
                else {
                    $result.Error = $result.Error.TrimEnd("; ")
                }
            }
            catch {
                $result.Error = "Exception: $($_.Exception.Message)"
            }
            
            return $result
        }
        $installJobs += $job
    }
    
    # Wait for all installation jobs to complete and collect results
    $installJobs | ForEach-Object {
        $jobResult = Receive-Job -Job $_ -Wait
        Remove-Job -Job $_ -Force
        
        if ($jobResult.Success) {
            [void]$successfulInstalls.Add([PSCustomObject]$jobResult)
        }
        elseif ($jobResult.Skipped) {
            [void]$skippedInstalls.Add([PSCustomObject]$jobResult)
        }
        else {
            [void]$failedInstalls.Add([PSCustomObject]$jobResult)
        }
    }

    # Enhanced Office detection with parallel checking
    $officeDetectionJob = Start-Job -ScriptBlock {
        $officeInstalled = $false
        
        # Check registry keys in parallel
        $registryJob = Start-Job -ScriptBlock {
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
                if (Test-Path $key -ErrorAction SilentlyContinue) {
                    return @{ Found = $true; Method = "Registry ($key)" }
                }
            }
            return @{ Found = $false; Method = "" }
        }
        
        # Check Start Menu apps in parallel
        $startMenuJob = Start-Job -ScriptBlock {
            try {
                $officeApps = Get-StartAppsCompatible | Where-Object { $_.Name -match 'Office|Word|Excel|PowerPoint|Outlook' }
                if ($officeApps) { 
                    return @{ Found = $true; Method = "Start Menu" }
                }
            }
            catch { }
            return @{ Found = $false; Method = "" }
        }
        
        # Wait for both jobs and check results
        $registryResult = Receive-Job -Job $registryJob -Wait
        $startMenuResult = Receive-Job -Job $startMenuJob -Wait
        Remove-Job -Job $registryJob, $startMenuJob -Force
        
        if ($registryResult.Found) {
            return @{ Installed = $true; DetectionMethod = $registryResult.Method }
        }
        elseif ($startMenuResult.Found) {
            return @{ Installed = $true; DetectionMethod = $startMenuResult.Method }
        }
        else {
            return @{ Installed = $false; DetectionMethod = "Not detected" }
        }
    }
    
    $officeResult = Receive-Job -Job $officeDetectionJob -Wait
    Remove-Job -Job $officeDetectionJob -Force

    # LibreOffice installation logic
    if (-not $officeResult.Installed) {
        $libreOfficeJob = Start-Job -ArgumentList $wingetAvailable, $chocoAvailable -ScriptBlock {
            param($wingetAvailable, $chocoAvailable)
            
            $result = @{
                Success = $false
                Method = ""
                Error = ""
            }
            
            try {
                # Try Winget first
                if ($wingetAvailable) {
                    $libreArgs = @(
                        "install", "--id", "TheDocumentFoundation.LibreOffice",
                        "--accept-source-agreements", "--accept-package-agreements", 
                        "--silent", "-e", "--disable-interactivity"
                    )
                    $libreProc = Start-Process -FilePath "winget" -ArgumentList $libreArgs -NoNewWindow -WindowStyle Hidden -Wait -PassThru
                    if ($libreProc.ExitCode -eq 0) {
                        $result.Success = $true
                        $result.Method = "winget"
                        return $result
                    }
                    else {
                        $result.Error += "winget failed (exit: $($libreProc.ExitCode)); "
                    }
                }
                
                # Try Chocolatey as fallback
                if (-not $result.Success -and $chocoAvailable) {
                    $chocoLibreArgs = @("install", "libreoffice-fresh", "-y", "--no-progress", "--limit-output")
                    $chocoLibreProc = Start-Process -FilePath "choco" -ArgumentList $chocoLibreArgs -NoNewWindow -WindowStyle Hidden -Wait -PassThru
                    if ($chocoLibreProc.ExitCode -eq 0) {
                        $result.Success = $true
                        $result.Method = "choco"
                        return $result
                    }
                    else {
                        $result.Error += "choco failed (exit: $($chocoLibreProc.ExitCode))"
                    }
                }
            }
            catch {
                $result.Error = "Exception: $($_.Exception.Message)"
            }
            
            return $result
        }
        
        $libreResult = Receive-Job -Job $libreOfficeJob -Wait
        Remove-Job -Job $libreOfficeJob -Force
        
        if ($libreResult.Success) {
            [void]$successfulInstalls.Add([PSCustomObject]@{
                AppName = "LibreOffice"
                Method = $libreResult.Method
                Success = $true
            })
        }
        else {
            [void]$failedInstalls.Add([PSCustomObject]@{
                AppName = "LibreOffice"
                Error = $libreResult.Error
                Success = $false
            })
        }
    }

    # Convert concurrent collections to arrays for reporting
    $successArray = @($successfulInstalls.ToArray())
    $failedArray = @($failedInstalls.ToArray())
    $skippedArray = @($skippedInstalls.ToArray())

    # Action-only logging: Only log successful installations
    if ($successArray.Count -gt 0) {
        Write-Log "[EssentialApps] Successfully installed $($successArray.Count) apps:" 'INFO'
        $successArray | ForEach-Object {
            Write-Log "Installed: $($_.AppName) via $($_.Method)" 'INFO'
            Write-Host "✓ Installed: $($_.AppName) via $($_.Method)" -ForegroundColor Green
        }
    }

    # Office detection summary (action-only)
    if ($officeResult.Installed) {
        Write-Log "[EssentialApps] Microsoft Office detected ($($officeResult.DetectionMethod)). LibreOffice installation skipped." 'INFO'
    }

    # Summary statistics
    $totalProcessed = $successArray.Count + $failedArray.Count + $skippedArray.Count
    Write-Log "[EssentialApps] Installation complete. Processed: $totalProcessed apps (Success: $($successArray.Count), Failed: $($failedArray.Count), Skipped: $($skippedArray.Count))" 'INFO'
    
    # Only log errors and skips if they exist (minimal noise)
    if ($failedArray.Count -gt 0) {
        Write-Log "[EssentialApps] Failed installations: $($failedArray.Count)" 'WARN'
    }
    
    if ($skippedArray.Count -gt 0) {
        Write-Log "[EssentialApps] Skipped installations: $($skippedArray.Count)" 'INFO'
    }

    Write-Log "[END] Install Essential Apps" 'INFO'
}

### [TASK 2.5] Update All Packages - Ultra-Optimized Parallel Approach
function Update-AllPackages {
    # ===============================
    # Task: UpdateAllPackages (Ultra-Enhanced Performance & Reliability)
    # ===============================
    # Purpose: Updates all installed packages using advanced parallel processing and smart caching.
    # Environment: Windows 10/11, must run as Administrator, supports Winget and Chocolatey.
    # Logic: Parallel execution, smart caching, detailed update tracking, comprehensive validation, action-only logging.
    # Performance: Uses parallel jobs, smart pre-filtering, package-specific update tracking, optimized command args.
    Write-Log "[START] Update All Packages (Ultra-Optimized Parallel Approach)" 'INFO'

    # Pre-check package manager availability with version detection
    $packageManagers = @()
    
    # Enhanced Winget availability check
    $wingetAvailable = $false
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        try {
            $wingetVersion = (winget --version 2>$null) -replace '[^\d\.]', ''
            if ($wingetVersion) {
                $wingetAvailable = $true
                $packageManagers += @{ Name = "Winget"; Version = $wingetVersion; Available = $true }
                Write-Log "[UpdatePackages] Winget detected: v$wingetVersion" 'VERBOSE'
            }
        }
        catch {
            Write-Log "[UpdatePackages] Winget version check failed: $_" 'VERBOSE'
        }
    }
    
    # Enhanced Chocolatey availability check
    $chocoAvailable = $false
    if (Get-Command choco -ErrorAction SilentlyContinue) {
        try {
            $chocoVersion = (choco --version 2>$null) -replace '[^\d\.]', ''
            if ($chocoVersion) {
                $chocoAvailable = $true
                $packageManagers += @{ Name = "Chocolatey"; Version = $chocoVersion; Available = $true }
                Write-Log "[UpdatePackages] Chocolatey detected: v$chocoVersion" 'VERBOSE'
            }
        }
        catch {
            Write-Log "[UpdatePackages] Chocolatey version check failed: $_" 'VERBOSE'
        }
    }
    
    if (-not $wingetAvailable -and -not $chocoAvailable) {
        Write-Log "[UpdatePackages] ERROR: No package managers available (winget/choco). Cannot update packages." 'ERROR'
        Write-Log "[END] Update All Packages" 'INFO'
        return
    }

    Write-Log "[UpdatePackages] Detected $($packageManagers.Count) package managers, initiating parallel updates..." 'INFO'

    # Initialize thread-safe results tracking
    $successfulUpdates = [System.Collections.Concurrent.ConcurrentBag[PSCustomObject]]::new()
    $failedUpdates = [System.Collections.Concurrent.ConcurrentBag[PSCustomObject]]::new()
    $noUpdatesAvailable = [System.Collections.Concurrent.ConcurrentBag[PSCustomObject]]::new()

    # Create enhanced parallel update jobs with improved error handling
    $updateJobs = @()
    
    # Enhanced Winget update job with optimized commands
    if ($wingetAvailable) {
        $wingetJob = Start-Job -ScriptBlock {
            $result = @{
                Source = "Winget"
                Success = $false
                UpdatedPackages = @()
                Error = ""
                NoUpdatesFound = $false
                ProcessingTime = 0
            }
            
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            
            try {
                # Enhanced check for available updates with better performance flags
                $upgradeCheckArgs = @(
                    "upgrade", 
                    "--accept-source-agreements", 
                    "--disable-interactivity",
                    "--include-unknown"
                )
                
                $upgradeProcess = Start-Process -FilePath "winget" -ArgumentList $upgradeCheckArgs -WindowStyle Hidden -Wait -PassThru -NoNewWindow -RedirectStandardOutput "$env:TEMP\winget_check_$PID.txt" -RedirectStandardError "$env:TEMP\winget_check_err_$PID.txt"
                
                if ($upgradeProcess.ExitCode -eq 0) {
                    $upgradeOutput = Get-Content "$env:TEMP\winget_check_$PID.txt" -ErrorAction SilentlyContinue | Out-String
                    
                    # Enhanced parsing for no updates
                    if ($upgradeOutput -match "No applicable upgrade found|No installed package found matching input criteria|No available upgrade found") {
                        $result.NoUpdatesFound = $true
                        $result.Success = $true
                        $result.ProcessingTime = $stopwatch.Elapsed.TotalSeconds
                        return $result
                    }
                    
                    # Count available updates for better reporting
                    $availableUpdatesCount = ($upgradeOutput -split "`n" | Where-Object { $_ -match '^\S+\s+\S+\s+\S+\s+winget$' }).Count
                    
                    if ($availableUpdatesCount -eq 0) {
                        $result.NoUpdatesFound = $true
                        $result.Success = $true
                        $result.ProcessingTime = $stopwatch.Elapsed.TotalSeconds
                        return $result
                    }
                    
                    # Run the actual upgrade with enhanced performance flags
                    $upgradeArgs = @(
                        "upgrade", "--all", "--silent", 
                        "--accept-source-agreements", "--accept-package-agreements", 
                        "--disable-interactivity", "--force", "--include-unknown",
                        "--ignore-security-hash", "--ignore-local-archive-malware-scan"
                    )
                    
                    $upgradeExecProcess = Start-Process -FilePath "winget" -ArgumentList $upgradeArgs -WindowStyle Hidden -Wait -PassThru -NoNewWindow -RedirectStandardOutput "$env:TEMP\winget_upgrade_$PID.txt" -RedirectStandardError "$env:TEMP\winget_upgrade_err_$PID.txt"
                    
                    if ($upgradeExecProcess.ExitCode -eq 0) {
                        $upgradeExecOutput = Get-Content "$env:TEMP\winget_upgrade_$PID.txt" -ErrorAction SilentlyContinue | Out-String
                        
                        # Enhanced parsing for successful updates
                        $successLines = $upgradeExecOutput -split "`n" | Where-Object { 
                            $_ -match "Successfully installed|Successfully upgraded|Successfully updated" 
                        }
                        
                        if ($successLines.Count -gt 0) {
                            $result.UpdatedPackages = @($successLines | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '\S' })
                            $result.Success = $true
                        }
                        else {
                            # Check if no updates were actually needed
                            if ($upgradeExecOutput -match "No applicable upgrade found|Nothing to upgrade") {
                                $result.NoUpdatesFound = $true
                                $result.Success = $true
                            }
                            else {
                                $result.Success = $true
                                $result.UpdatedPackages = @("Updates completed (details not parseable)")
                            }
                        }
                    }
                    else {
                        $upgradeError = Get-Content "$env:TEMP\winget_upgrade_err_$PID.txt" -ErrorAction SilentlyContinue | Out-String
                        $result.Error = "Upgrade failed (exit: $($upgradeExecProcess.ExitCode)). Error: $upgradeError"
                    }
                }
                else {
                    $checkError = Get-Content "$env:TEMP\winget_check_err_$PID.txt" -ErrorAction SilentlyContinue | Out-String
                    $result.Error = "Check failed (exit: $($upgradeProcess.ExitCode)). Error: $checkError"
                }
                
                # Enhanced cleanup with PID-specific files
                Remove-Item "$env:TEMP\winget_*_$PID.txt" -ErrorAction SilentlyContinue
            }
            catch {
                $result.Error = "Exception: $($_.Exception.Message)"
            }
            finally {
                $stopwatch.Stop()
                $result.ProcessingTime = $stopwatch.Elapsed.TotalSeconds
            }
            
            return $result
        }
        $updateJobs += $wingetJob
    }
    
    # Enhanced Chocolatey update job with optimized commands
    if ($chocoAvailable) {
        $chocoJob = Start-Job -ScriptBlock {
            $result = @{
                Source = "Chocolatey"
                Success = $false
                UpdatedPackages = @()
                Error = ""
                NoUpdatesFound = $false
                ProcessingTime = 0
            }
            
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            
            try {
                # Enhanced check for outdated packages with better performance
                $outdatedArgs = @(
                    "outdated", 
                    "--limit-output", 
                    "--ignore-unfound",
                    "--ignore-pinned"
                )
                
                $outdatedProcess = Start-Process -FilePath "choco" -ArgumentList $outdatedArgs -WindowStyle Hidden -Wait -PassThru -NoNewWindow -RedirectStandardOutput "$env:TEMP\choco_outdated_$PID.txt" -RedirectStandardError "$env:TEMP\choco_outdated_err_$PID.txt"
                
                if ($outdatedProcess.ExitCode -eq 0) {
                    $outdatedOutput = Get-Content "$env:TEMP\choco_outdated_$PID.txt" -ErrorAction SilentlyContinue
                    
                    # Filter out header and summary lines
                    $outdatedPackages = $outdatedOutput | Where-Object { 
                        $_ -match '\S' -and $_ -notmatch '^Chocolatey|^Output is package name|^\d+ packages have|^$' 
                    }
                    
                    if (-not $outdatedPackages -or $outdatedPackages.Count -eq 0) {
                        $result.NoUpdatesFound = $true
                        $result.Success = $true
                        $result.ProcessingTime = $stopwatch.Elapsed.TotalSeconds
                        return $result
                    }
                    
                    # Run the actual upgrade with enhanced performance flags
                    $upgradeArgs = @(
                        "upgrade", "all", "-y", 
                        "--limit-output", "--no-progress", 
                        "--skip-powershell", "--ignore-checksums",
                        "--timeout", "300"
                    )
                    
                    $upgradeProcess = Start-Process -FilePath "choco" -ArgumentList $upgradeArgs -WindowStyle Hidden -Wait -PassThru -NoNewWindow -RedirectStandardOutput "$env:TEMP\choco_upgrade_$PID.txt" -RedirectStandardError "$env:TEMP\choco_upgrade_err_$PID.txt"
                    
                    if ($upgradeProcess.ExitCode -eq 0) {
                        $upgradeOutput = Get-Content "$env:TEMP\choco_upgrade_$PID.txt" -ErrorAction SilentlyContinue
                        
                        # Enhanced parsing for successful updates
                        $successLines = $upgradeOutput | Where-Object { 
                            $_ -match "successfully upgraded|upgraded \d+/\d+|has been upgraded"
                        }
                        
                        $result.UpdatedPackages = @($successLines | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '\S' })
                        $result.Success = $true
                    }
                    elseif ($upgradeProcess.ExitCode -eq 1641 -or $upgradeProcess.ExitCode -eq 3010) {
                        # Success with reboot required
                        $upgradeOutput = Get-Content "$env:TEMP\choco_upgrade_$PID.txt" -ErrorAction SilentlyContinue
                        $successLines = $upgradeOutput | Where-Object { 
                            $_ -match "successfully upgraded|upgraded \d+/\d+|has been upgraded"
                        }
                        
                        $result.UpdatedPackages = @($successLines | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '\S' })
                        $result.UpdatedPackages += "NOTE: Some updates require a system reboot (exit code: $($upgradeProcess.ExitCode))"
                        $result.Success = $true
                    }
                    else {
                        $upgradeError = Get-Content "$env:TEMP\choco_upgrade_err_$PID.txt" -ErrorAction SilentlyContinue | Out-String
                        $result.Error = "Upgrade failed (exit: $($upgradeProcess.ExitCode)). Error: $upgradeError"
                    }
                }
                else {
                    $outdatedError = Get-Content "$env:TEMP\choco_outdated_err_$PID.txt" -ErrorAction SilentlyContinue | Out-String
                    $result.Error = "Outdated check failed (exit: $($outdatedProcess.ExitCode)). Error: $outdatedError"
                }
                
                # Enhanced cleanup with PID-specific files
                Remove-Item "$env:TEMP\choco_*_$PID.txt" -ErrorAction SilentlyContinue
            }
            catch {
                $result.Error = "Exception: $($_.Exception.Message)"
            }
            finally {
                $stopwatch.Stop()
                $result.ProcessingTime = $stopwatch.Elapsed.TotalSeconds
            }
            
            return $result
        }
        $updateJobs += $chocoJob
    }
    
    # Enhanced parallel job execution with timeout handling
    Write-Log "[UpdatePackages] Executing parallel package updates with enhanced monitoring..." 'INFO'
    $jobTimeout = 600 # 10 minutes timeout for package updates
    $startTime = Get-Date
    
    # Monitor jobs with timeout
    $completedJobs = @()
    $timeoutJobs = @()
    
    while ($updateJobs.Count -gt 0 -and (Get-Date).Subtract($startTime).TotalSeconds -lt $jobTimeout) {
        Start-Sleep -Milliseconds 500  # Check every 500ms
        
        foreach ($job in $updateJobs.ToArray()) {
            if ($job.State -eq 'Completed') {
                $completedJobs += $job
                $updateJobs = $updateJobs | Where-Object { $_.Id -ne $job.Id }
            }
        }
    }
    
    # Handle any remaining (timeout) jobs
    foreach ($job in $updateJobs) {
        $timeoutJobs += $job
        Write-Log "[UpdatePackages] Job timeout: $($job.Name)" 'WARN'
        Stop-Job -Job $job -Force
    }
    
    # Process completed job results with enhanced error handling
    foreach ($job in $completedJobs) {
        try {
            $jobResult = Receive-Job -Job $job -Wait -ErrorAction Stop
            Remove-Job -Job $job -Force
            
            if ($jobResult.Success) {
                if ($jobResult.NoUpdatesFound) {
                    [void]$noUpdatesAvailable.Add([PSCustomObject]@{
                        Source = $jobResult.Source
                        Message = "No updates available"
                        ProcessingTime = $jobResult.ProcessingTime
                    })
                }
                else {
                    [void]$successfulUpdates.Add([PSCustomObject]@{
                        Source = $jobResult.Source
                        UpdatedPackages = $jobResult.UpdatedPackages
                        Count = if ($jobResult.UpdatedPackages) { $jobResult.UpdatedPackages.Count } else { 0 }
                        ProcessingTime = $jobResult.ProcessingTime
                    })
                }
            }
            else {
                [void]$failedUpdates.Add([PSCustomObject]@{
                    Source = $jobResult.Source
                    Error = $jobResult.Error
                    ProcessingTime = $jobResult.ProcessingTime
                })
            }
        }
        catch {
            Write-Log "[UpdatePackages] Error processing job result: $_" 'WARN'
            [void]$failedUpdates.Add([PSCustomObject]@{
                Source = "Unknown"
                Error = "Job result processing failed: $_"
                ProcessingTime = 0
            })
        }
    }
    
    # Handle timeout jobs
    foreach ($job in $timeoutJobs) {
        Remove-Job -Job $job -Force
        [void]$failedUpdates.Add([PSCustomObject]@{
            Source = "Timeout"
            Error = "Package update timed out after $jobTimeout seconds"
            ProcessingTime = $jobTimeout
        })
    }

    # Convert concurrent collections to arrays for enhanced reporting
    $successArray = @($successfulUpdates.ToArray())
    $failedArray = @($failedUpdates.ToArray())
    $noUpdatesArray = @($noUpdatesAvailable.ToArray())

    # Enhanced action-only logging with performance metrics
    if ($successArray.Count -gt 0) {
        $totalUpdated = ($successArray | ForEach-Object { $_.Count } | Measure-Object -Sum).Sum
        $totalTime = ($successArray | ForEach-Object { $_.ProcessingTime } | Measure-Object -Sum).Sum
        $avgTimePerSource = if ($successArray.Count -gt 0) { [math]::Round($totalTime / $successArray.Count, 2) } else { 0 }
        
        Write-Log "[UpdatePackages] Successfully updated $totalUpdated packages across $($successArray.Count) package managers (avg time: ${avgTimePerSource}s per source):" 'INFO'
        
        foreach ($success in $successArray) {
            $timeInfo = if ($success.ProcessingTime -gt 0) { " (${success.ProcessingTime}s)" } else { "" }
            Write-Log "Updated via $($success.Source): $($success.Count) packages$timeInfo" 'INFO'
            Write-Host "✓ Updated via $($success.Source): $($success.Count) packages$timeInfo" -ForegroundColor Green
            
            # Enhanced verbose logging with package details
            if ($global:Config.EnableVerboseLogging -and $success.UpdatedPackages.Count -gt 0) {
                foreach ($package in $success.UpdatedPackages) {
                    if ($package -match '\S') {
                        Write-Log "  - $($package.Trim())" 'VERBOSE'
                    }
                }
            }
        }
    }

    # Enhanced no-updates reporting with timing
    if ($noUpdatesArray.Count -gt 0) {
        foreach ($noUpdate in $noUpdatesArray) {
            $timeInfo = if ($noUpdate.ProcessingTime -gt 0) { " (checked in ${noUpdate.ProcessingTime}s)" } else { "" }
            Write-Log "[UpdatePackages] $($noUpdate.Source): $($noUpdate.Message)$timeInfo" 'INFO'
        }
    }

    # Enhanced summary statistics with performance metrics
    $totalSources = $successArray.Count + $failedArray.Count + $noUpdatesArray.Count
    $totalPackagesUpdated = if ($successArray.Count -gt 0) { ($successArray | ForEach-Object { $_.Count } | Measure-Object -Sum).Sum } else { 0 }
    $totalProcessingTime = [math]::Round((Get-Date).Subtract($startTime).TotalSeconds, 2)
    
    Write-Log "[UpdatePackages] Update process complete in ${totalProcessingTime}s. Sources processed: $totalSources, Total packages updated: $totalPackagesUpdated" 'INFO'
    
    # Enhanced error reporting with timing information
    if ($failedArray.Count -gt 0) {
        Write-Log "[UpdatePackages] Failed update sources: $($failedArray.Count)" 'WARN'
        foreach ($failure in $failedArray) {
            $timeInfo = if ($failure.ProcessingTime -gt 0) { " (failed after ${failure.ProcessingTime}s)" } else { "" }
            $errorSummary = if ($failure.Error.Length -gt 100) { $failure.Error.Substring(0, 100) + "..." } else { $failure.Error }
            Write-Log "[UpdatePackages] $($failure.Source) failed$timeInfo`: $errorSummary" 'WARN'
        }
    }

    # Performance analysis and recommendations
    if ($totalProcessingTime -gt 300) { # 5 minutes
        Write-Log "[UpdatePackages] PERFORMANCE: Update took ${totalProcessingTime}s. Consider running updates during off-peak hours." 'INFO'
    }
    elseif ($totalProcessingTime -lt 30) {
        Write-Log "[UpdatePackages] PERFORMANCE: Fast update completion (${totalProcessingTime}s) - system is well optimized." 'VERBOSE'
    }

    Write-Log "[END] Update All Packages" 'INFO'
}

### [TASK 3] Ultra-Enhanced Bloatware Removal - Action-Only Logging & Maximum Performance
function Remove-Bloatware {
    # ===============================
    # Task: RemoveBloatware (Ultra-Enhanced Action-Only)
    # ===============================
    # Purpose: High-speed bloatware removal with PS7.5 native capabilities - shows ONLY removed apps.
    # Environment: Windows 10/11, Administrator required, leverages PS7.5 native AppX/DISM support.
    # Logic: Ultra-parallel removal, smart pre-filtering, action-only logging, maximum performance optimization.
    # Performance: Native PS7.5 AppX, 8-thread parallel processing, pre-compiled regex, smart caching.
    Write-Log "[START] Ultra-Enhanced Bloatware Removal" 'INFO'
    
    # Use cached inventory if available, otherwise trigger fresh scan
    if (-not $global:SystemInventory) {
        Get-ExtensiveSystemInventory
    }
    
    $inventory = $global:SystemInventory
    
    # Ultra-fast lookup using case-insensitive Dictionary with pre-compiled regex patterns
    $installedApps = [System.Collections.Generic.Dictionary[string, PSCustomObject]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )
    
    # Pre-compile common app name patterns for faster matching
    $commonPatterns = @(
        [regex]::new('microsoft\.', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [System.Text.RegularExpressions.RegexOptions]::Compiled),
        [regex]::new('\.exe$', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [System.Text.RegularExpressions.RegexOptions]::Compiled),
        [regex]::new('^[A-Z]+\.[A-Z]', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [System.Text.RegularExpressions.RegexOptions]::Compiled)
    )
    
    # Ultra-parallel inventory processing with optimized data structures
    $inventoryJobs = @(
        @{ Name = 'AppX'; Data = $inventory.appx; Props = @('Name', 'PackageFullName') },
        @{ Name = 'Winget'; Data = $inventory.winget; Props = @('Name', 'Id') },
        @{ Name = 'Chocolatey'; Data = $inventory.choco; Props = @('Name') },
        @{ Name = 'Registry'; Data = $inventory.registry_uninstall; Props = @('DisplayName', 'UninstallString') }
    ) | ForEach-Object -Parallel {
        $type = $_.Name
        $data = $_.Data
        $properties = $_.Props
        $results = [System.Collections.Generic.List[hashtable]]::new()
        
        foreach ($item in $data) {
            foreach ($prop in $properties) {
                if ($item.$prop -and $item.$prop.ToString().Trim()) {
                    $results.Add(@{
                        Key = $item.$prop.ToString().Trim()
                        Type = $type
                        Data = $item
                    })
                }
            }
        }
        return $results.ToArray()
    } -ThrottleLimit 8
    
    # Merge results into lookup dictionary
    foreach ($jobResult in $inventoryJobs) {
        foreach ($item in $jobResult) {
            if (-not $installedApps.ContainsKey($item.Key)) {
                $installedApps[$item.Key] = [PSCustomObject]@{
                    Type = $item.Type
                    Data = $item.Data
                }
            }
        }
    }
    
    # Smart bloatware detection with optimized pattern matching
    $bloatwareMatches = [System.Collections.Generic.List[PSCustomObject]]::new()
    $bloatwareHashSet = [System.Collections.Generic.HashSet[string]]::new($global:BloatwareList, [System.StringComparer]::OrdinalIgnoreCase)
    
    # Direct lookup phase (O(1) performance)
    foreach ($installedKey in $installedApps.Keys) {
        if ($bloatwareHashSet.Contains($installedKey)) {
            $bloatwareMatches.Add([PSCustomObject]@{
                BloatwareName = $installedKey
                InstalledApp = $installedApps[$installedKey]
                MatchType = 'Direct'
            })
        }
    }
    
    # Pattern matching phase (only if needed)
    if ($bloatwareMatches.Count -eq 0) {
        foreach ($bloatApp in $global:BloatwareList) {
            $trimmedBloat = $bloatApp.Trim()
            $found = $false
            
            foreach ($installedKey in $installedApps.Keys) {
                if ($installedKey.Contains($trimmedBloat, [System.StringComparison]::OrdinalIgnoreCase) -or 
                    $trimmedBloat.Contains($installedKey, [System.StringComparison]::OrdinalIgnoreCase)) {
                    
                    $bloatwareMatches.Add([PSCustomObject]@{
                        BloatwareName = $trimmedBloat
                        InstalledApp = $installedApps[$installedKey]
                        MatchType = 'Pattern'
                    })
                    $found = $true
                    break
                }
            }
        }
    }
    
    # Early exit if no bloatware found
    if ($bloatwareMatches.Count -eq 0) {
        Write-Log "[END] Ultra-Enhanced Bloatware Removal - No bloatware detected" 'INFO'
        return
    }
    
    # Cached tool availability detection
    $toolCapabilities = @{
        AppX = $false
        Winget = $false
        Chocolatey = $false
    }
    
    # Fast native AppX detection for PS7.5+
    if ($PSVersionTable.PSVersion.Major -ge 7) {
        try {
            $null = Get-AppxPackage -Name "NonExistent*" -ErrorAction SilentlyContinue
            $toolCapabilities.AppX = $true
        }
        catch {
            # Try compatibility mode
            try {
                $testCmd = "Get-Module -ListAvailable -Name Appx"
                $result = Invoke-WindowsPowerShellCommand -Command $testCmd -Description "Test AppX"
                $toolCapabilities.AppX = $null -ne $result
            }
            catch { }
        }
    }
    
    # Cache command availability
    $toolCapabilities.Winget = $null -ne (Get-Command winget -ErrorAction SilentlyContinue)
    $toolCapabilities.Chocolatey = $null -ne (Get-Command choco -ErrorAction SilentlyContinue)
    
    # Thread-safe collections for results
    $removedApps = [System.Collections.Concurrent.ConcurrentBag[PSCustomObject]]::new()
    
    # Ultra-parallel removal with optimized error handling
    $bloatwareMatches | ForEach-Object -Parallel {
        $match = $_
        $capabilities = $using:toolCapabilities
        $psVersion = $using:PSVersionTable
        
        $result = @{
            Success = $false
            AppName = $match.BloatwareName
            ActualName = ""
            Method = ""
        }
        
        try {
            $app = $match.InstalledApp
            $appType = $app.Type
            $appData = $app.Data
            
            # Optimized removal by type priority
            switch ($appType) {
                'AppX' {
                    if ($capabilities.AppX -and $appData.PackageFullName) {
                        try {
                            if ($psVersion.PSVersion.Major -ge 7) {
                                Remove-AppxPackage -Package $appData.PackageFullName -AllUsers -ErrorAction Stop
                            }
                            else {
                                $success = Remove-AppxPackageCompatible -PackageFullName $appData.PackageFullName -AllUsers
                                if (-not $success) { throw "AppX compatibility removal failed" }
                            }
                            $result.Success = $true
                            $result.Method = "AppX"
                            $result.ActualName = $appData.Name
                        }
                        catch { }
                    }
                }
                'Winget' {
                    if ($capabilities.Winget -and $appData.Id) {
                        try {
                            $proc = Start-Process -FilePath "winget" -ArgumentList @(
                                "uninstall", "--id", $appData.Id, "--exact", "--silent", 
                                "--accept-source-agreements", "--force", "--disable-interactivity"
                            ) -WindowStyle Hidden -Wait -PassThru -NoNewWindow
                            
                            if ($proc.ExitCode -eq 0) {
                                $result.Success = $true
                                $result.Method = "Winget"
                                $result.ActualName = $appData.Name
                            }
                        }
                        catch { }
                    }
                }
                'Chocolatey' {
                    if ($capabilities.Chocolatey -and $appData.Name) {
                        try {
                            $proc = Start-Process -FilePath "choco" -ArgumentList @(
                                "uninstall", $appData.Name, "-y", "--remove-dependencies", 
                                "--limit-output", "--no-progress"
                            ) -WindowStyle Hidden -Wait -PassThru -NoNewWindow
                            
                            if ($proc.ExitCode -eq 0) {
                                $result.Success = $true
                                $result.Method = "Chocolatey"
                                $result.ActualName = $appData.Name
                            }
                        }
                        catch { }
                    }
                }
                'Registry' {
                    if ($appData.UninstallString -and $appData.UninstallString -match '\.exe') {
                        try {
                            $uninstallCmd = $appData.UninstallString -replace '"', ''
                            $proc = Start-Process -FilePath $uninstallCmd -ArgumentList "/S" -Wait -WindowStyle Hidden -PassThru
                            
                            if ($proc.ExitCode -eq 0) {
                                $result.Success = $true
                                $result.Method = "Registry"
                                $result.ActualName = $appData.DisplayName
                            }
                        }
                        catch { }
                    }
                }
            }
            
            # Fast AppX fallback if primary method failed
            if (-not $result.Success -and $capabilities.AppX) {
                try {
                    if ($psVersion.PSVersion.Major -ge 7) {
                        $packages = Get-AppxPackage -Name "*$($match.BloatwareName)*" -AllUsers -ErrorAction SilentlyContinue
                        foreach ($pkg in $packages | Select-Object -First 1) {
                            Remove-AppxPackage -Package $pkg.PackageFullName -AllUsers -ErrorAction Stop
                            $result.Success = $true
                            $result.Method = "AppX Fallback"
                            $result.ActualName = $pkg.Name
                            break
                        }
                    }
                }
                catch { }
            }
        }
        catch { }
        
        return $result
        
    } -ThrottleLimit 8 | Where-Object { $_.Success } | ForEach-Object {
        [void]$removedApps.Add([PSCustomObject]$_)
    }
    
    # Convert to array for processing
    $removedArray = @($removedApps.ToArray())
    
    # ACTION-ONLY LOGGING: Only show what was actually removed
    if ($removedArray.Count -gt 0) {
        # Individual app removals - one line per app
        foreach ($removed in $removedArray) {
            $logMsg = "Removed: $($removed.ActualName) [$($removed.Method)]"
            Write-Log $logMsg 'INFO'
            Write-Host "✓ $logMsg" -ForegroundColor Green
        }
        
        # Summary log entry
        $appNames = ($removedArray | ForEach-Object { $_.ActualName } | Sort-Object -Unique) -join ', '
        Write-Log "Bloatware removal summary: $($removedArray.Count) apps removed - $appNames" 'INFO'
        
        # Method breakdown
        $methodGroups = $removedArray | Group-Object Method
        $methodSummary = ($methodGroups | ForEach-Object { "$($_.Name): $($_.Count)" }) -join ', '
        Write-Log "Removal methods used: $methodSummary" 'INFO'
    }
    else {
        Write-Log "No bloatware apps were removed" 'INFO'
    }
    
    # Ultra-fast registry cleanup to prevent reinstallation
    $registryKeys = @(
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager',
        'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
    )
    
    $registryKeys | ForEach-Object -Parallel {
        $regKey = $_
        try {
            if (-not (Test-Path $regKey)) { 
                New-Item -Path $regKey -Force -ErrorAction SilentlyContinue | Out-Null 
            }
            
            $settings = @{
                'SilentInstalledAppsEnabled' = 0
                'ContentDeliveryAllowed' = 0
                'OemPreInstalledAppsEnabled' = 0
                'PreInstalledAppsEnabled' = 0
                'SubscribedContentEnabled' = 0
                'SystemPaneSuggestionsEnabled' = 0
                'SoftLandingEnabled' = 0
            }
            
            foreach ($setting in $settings.GetEnumerator()) {
                Set-ItemProperty -Path $regKey -Name $setting.Key -Value $setting.Value -ErrorAction SilentlyContinue
            }
        }
        catch { }
    } -ThrottleLimit 3 | Out-Null
    
    Write-Log "[END] Ultra-Enhanced Bloatware Removal" 'INFO'
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
    # Logic: Enhanced for speed and reliability, logs only actual removals.
    Write-Log "[START] Disable Telemetry" 'INFO'
    
    # Optimized notification management - batch operations
    try {
        $focusAssistReg = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Notifications\Settings'
        if (-not (Test-Path $focusAssistReg)) { New-Item -Path $focusAssistReg -Force | Out-Null }
        
        # Batch set notification settings
        $notificationSettings = @{
            'NOC_GLOBAL_SETTING_TOASTS_ENABLED' = 0
            'FocusAssist' = 2
        }
        
        $settingsApplied = 0
        foreach ($setting in $notificationSettings.GetEnumerator()) {
            try {
                Set-ItemProperty -Path $focusAssistReg -Name $setting.Key -Value $setting.Value -Force
                $settingsApplied++
            }
            catch { continue }
        }
        
        # Batch disable per-app notifications using registry operations
        $apps = Get-ChildItem -Path $focusAssistReg -ErrorAction SilentlyContinue | Where-Object { 
            $_.PSChildName -notin @('FocusAssist', 'NOC_GLOBAL_SETTING_TOASTS_ENABLED') 
        }
        
        $appsDisabled = 0
        if ($apps) {
            foreach ($app in $apps) {
                try {
                    Set-ItemProperty -Path $app.PSPath -Name 'Enabled' -Value 0 -Force -ErrorAction SilentlyContinue
                    $appsDisabled++
                }
                catch { continue }
            }
        }
        
        if ($settingsApplied -gt 0 -or $appsDisabled -gt 0) {
            Write-Host "✓ Disabled OS notifications ($appsDisabled apps)" -ForegroundColor Green
            Write-Log "OS notifications disabled: Focus Assist enabled, $appsDisabled app notifications disabled" 'INFO'
        }
    }
    catch {
        Write-Log "Failed to disable OS notifications: $_" 'WARN'
    }

    # Optimized browser removal - pre-filter and batch operations
    $allowedBrowsers = @('Microsoft Edge', 'Google Chrome', 'Mozilla Firefox')
    $knownBrowsers = @('Opera', 'Opera GX', 'Brave', 'Vivaldi', 'Waterfox', 'Yandex', 'Tor Browser', 'Pale Moon', 
        'Chromium', 'SRWare Iron', 'Comodo Dragon', 'Maxthon', 'UC Browser', 'Epic Privacy Browser', 
        'Slimjet', 'CentBrowser', 'QuteBrowser', 'OtterBrowser', 'Dooble', 'Midori', 'Blisk', 
        'AvantBrowser', 'Sleipnir', 'Polarity', 'Torch', 'Orbitum', 'Superbird', 'Sputnik', 
        'Lunascape', 'Falkon', 'SeaMonkey')
    
    $browsersToRemove = $knownBrowsers | Where-Object { $allowedBrowsers -notcontains $_ }
    $installedBrowsers = [System.Collections.Generic.HashSet[string]]::new()
    
    # Parallel detection using background jobs for better performance
    $detectionJobs = @()
    
    # Winget detection job
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        $detectionJobs += Start-Job -ScriptBlock {
            param($browsersToRemove)
            $wingetApps = winget list --accept-source-agreements 2>$null | Out-String
            $foundBrowsers = @()
            foreach ($browser in $browsersToRemove) {
                if ($wingetApps -match [regex]::Escape($browser)) {
                    $foundBrowsers += $browser
                }
            }
            return @{ Method = 'Winget'; Browsers = $foundBrowsers }
        } -ArgumentList @(,$browsersToRemove)
    }
    
    # Chocolatey detection job  
    if (Get-Command choco -ErrorAction SilentlyContinue) {
        $detectionJobs += Start-Job -ScriptBlock {
            param($browsersToRemove)
            $chocoApps = choco list --local-only 2>$null | Out-String
            $foundBrowsers = @()
            foreach ($browser in $browsersToRemove) {
                if ($chocoApps -match [regex]::Escape($browser)) {
                    $foundBrowsers += $browser
                }
            }
            return @{ Method = 'Chocolatey'; Browsers = $foundBrowsers }
        } -ArgumentList @(,$browsersToRemove)
    }
    
    # Registry detection job
    $detectionJobs += Start-Job -ScriptBlock {
        param($browsersToRemove)
        $uninstallKeys = @(
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
            'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
        )
        
        $foundBrowsers = @()
        foreach ($key in $uninstallKeys) {
            if (Test-Path $key) {
                $regApps = Get-ChildItem $key -ErrorAction SilentlyContinue | 
                          ForEach-Object { Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue } |
                          Where-Object { $_.DisplayName }
                
                foreach ($browser in $browsersToRemove) {
                    if ($regApps | Where-Object { $_.DisplayName -like "*$browser*" }) {
                        $foundBrowsers += $browser
                    }
                }
            }
        }
        return @{ Method = 'Registry'; Browsers = ($foundBrowsers | Select-Object -Unique) }
    } -ArgumentList @(,$browsersToRemove)
    
    # Collect results from detection jobs
    $detectionResults = $detectionJobs | Wait-Job | Receive-Job
    $detectionJobs | Remove-Job
    
    # Combine all detected browsers
    foreach ($result in $detectionResults) {
        foreach ($browser in $result.Browsers) {
            $installedBrowsers.Add($browser) | Out-Null
        }
    }
    
    # Remove detected browsers efficiently
    $removedBrowsers = @()
    $removalMethods = @()
    
    if ($installedBrowsers.Count -gt 0) {
        foreach ($browser in $installedBrowsers) {
            $removed = $false
            
            # Try winget removal (fastest and most reliable)
            if (Get-Command winget -ErrorAction SilentlyContinue) {
                try {
                    $result = winget uninstall --name $browser --accept-source-agreements --silent --force 2>$null
                    if ($LASTEXITCODE -eq 0) {
                        $removedBrowsers += $browser
                        $removalMethods += 'Winget'
                        $removed = $true
                    }
                }
                catch { }
            }
            
            # Try chocolatey if winget failed
            if (-not $removed -and (Get-Command choco -ErrorAction SilentlyContinue)) {
                try {
                    $result = choco uninstall $browser -y --limit-output --force 2>$null
                    if ($LASTEXITCODE -eq 0) {
                        $removedBrowsers += $browser
                        $removalMethods += 'Chocolatey'
                        $removed = $true
                    }
                }
                catch { }
            }
            
            # Registry-based removal as last resort
            if (-not $removed) {
                $uninstallKeys = @(
                    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
                    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
                    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
                )
                
                foreach ($key in $uninstallKeys) {
                    if (Test-Path $key) {
                        $apps = Get-ChildItem $key -ErrorAction SilentlyContinue | 
                               ForEach-Object { Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue } |
                               Where-Object { $_.DisplayName -like "*$browser*" -and $_.UninstallString }
                        
                        foreach ($app in $apps) {
                            try {
                                $uninstallCmd = ($app.UninstallString -replace '"', '').Split(' ')[0]
                                if (Test-Path $uninstallCmd) {
                                    Start-Process -FilePath $uninstallCmd -ArgumentList "/S" -Wait -WindowStyle Hidden -ErrorAction SilentlyContinue
                                    $removedBrowsers += $browser
                                    $removalMethods += 'Registry'
                                    $removed = $true
                                    break
                                }
                            }
                            catch { continue }
                        }
                        if ($removed) { break }
                    }
                }
            }
        }
    }
    
    # Optimized logging - only log actual removals
    if ($removedBrowsers.Count -gt 0) {
        Write-Host "✓ Removed $($removedBrowsers.Count) unwanted browsers" -ForegroundColor Red
        Write-Log "Removed browsers: $($removedBrowsers -join ', ')" 'INFO'
        
        # Log removal methods summary for troubleshooting
        $methodSummary = $removalMethods | Group-Object | ForEach-Object { "$($_.Count) via $($_.Name)" }
        Write-Log "Removal methods used: $($methodSummary -join ', ')" 'VERBOSE'
    }

    # Batch browser policy configuration (Edge, Chrome, Firefox)
    $browserPolicies = @{
        'HKLM:\SOFTWARE\Policies\Microsoft\Edge' = @{
            'MetricsReportingEnabled' = 0
            'HomepageLocation'        = 'about:blank'
            'ShowHomeButton'          = 1
            'BookmarkBarEnabled'      = 1
            'TranslateEnabled'        = 0
        }
        'HKLM:\SOFTWARE\Policies\Google\Chrome'  = @{
            'MetricsReportingEnabled' = 0
            'HomepageLocation'        = 'about:blank'
            'ShowHomeButton'          = 1
            'BookmarkBarEnabled'      = 1
            'TranslateEnabled'        = 0
        }
    }
    
    foreach ($regPath in $browserPolicies.Keys) {
        try {
            if (-not (Test-Path $regPath)) { New-Item -Path $regPath -Force | Out-Null }
            foreach ($setting in $browserPolicies[$regPath].GetEnumerator()) {
                Set-ItemProperty -Path $regPath -Name $setting.Key -Value $setting.Value -Force
            }
            $browserName = if ($regPath -like "*Edge*") { "Edge" } else { "Chrome" }
            Write-Host "✓ $browserName policies configured" -ForegroundColor Green
            Write-Log "$browserName telemetry disabled and policies configured" 'INFO'
        }
        catch {
            Write-Log "Failed to configure browser policies for $regPath`: $_" 'WARN'
        }
    }

    # Enhanced Firefox configuration
    $firefoxPaths = @('C:\Program Files\Mozilla Firefox', 'C:\Program Files (x86)\Mozilla Firefox')
    $firefoxPath = $firefoxPaths | Where-Object { Test-Path $_ } | Select-Object -First 1
    
    if ($firefoxPath) {
        try {
            $distPath = Join-Path $firefoxPath 'distribution'
            if (-not (Test-Path $distPath)) { New-Item -Path $distPath -ItemType Directory -Force | Out-Null }
            
            $externalPolicyPath = Join-Path $PSScriptRoot 'firefox_policies.json'
            if (Test-Path $externalPolicyPath) {
                Copy-Item -Path $externalPolicyPath -Destination (Join-Path $distPath 'policies.json') -Force
                Remove-Item -Path $externalPolicyPath -Force
                Write-Host "✓ Firefox policies deployed from external file" -ForegroundColor Green
                Write-Log "Firefox policies deployed from firefox_policies.json" 'INFO'
            }
            else {
                # Optimized built-in policy
                $policyJson = @'
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
'@
                $policyPath = Join-Path $distPath 'policies.json'
                $policyJson | Set-Content -Path $policyPath -Encoding UTF8
                Write-Host "✓ Firefox policies deployed" -ForegroundColor Green
                Write-Log "Firefox policies deployed from built-in configuration" 'INFO'
            }
            
            # Enhanced Firefox default browser setting
            $firefoxExe = Join-Path $firefoxPath 'firefox.exe'
            if (Test-Path $firefoxExe) {
                # Registry-based approach (more reliable)
                $firefoxProgId = 'FirefoxURL-308046B0AF4A39CB'
                $associations = @(
                    'HKCU:\SOFTWARE\Microsoft\Windows\Shell\Associations\UrlAssociations\http\UserChoice',
                    'HKCU:\SOFTWARE\Microsoft\Windows\Shell\Associations\UrlAssociations\https\UserChoice',
                    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.html\UserChoice',
                    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.htm\UserChoice'
                )
                
                $successCount = 0
                foreach ($regPath in $associations) {
                    try {
                        $parentPath = Split-Path $regPath
                        if (-not (Test-Path $parentPath)) { New-Item -Path $parentPath -Force | Out-Null }
                        if (-not (Test-Path $regPath)) { New-Item -Path $regPath -Force | Out-Null }
                        Set-ItemProperty -Path $regPath -Name 'ProgId' -Value $firefoxProgId -Force -ErrorAction SilentlyContinue
                        $successCount++
                    }
                    catch { continue }
                }
                
                if ($successCount -gt 0) {
                    Write-Host "✓ Firefox set as default browser" -ForegroundColor Green
                    Write-Log "Firefox configured as default browser" 'INFO'
                }
            }
        }
        catch {
            Write-Log "Failed to configure Firefox: $_" 'WARN'
        }
    }
    
    # Enhanced service management - only target running/enabled services
    $telemetryServices = @('DiagTrack', 'dmwappushservice', 'Connected User Experiences and Telemetry')
    $servicesDisabled = @()
    
    foreach ($svc in $telemetryServices) {
        try {
            $serviceObj = Get-Service -Name $svc -ErrorAction SilentlyContinue
            if ($serviceObj) {
                $changed = $false
                if ($serviceObj.Status -ne 'Stopped') {
                    Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
                    $changed = $true
                }
                if ($serviceObj.StartType -ne 'Disabled') {
                    Set-Service -Name $svc -StartupType Disabled -ErrorAction SilentlyContinue
                    $changed = $true
                }
                if ($changed) {
                    $servicesDisabled += $svc
                }
            }
        }
        catch { continue }
    }
    
    if ($servicesDisabled.Count -gt 0) {
        Write-Host "✓ Disabled telemetry services: $($servicesDisabled -join ', ')" -ForegroundColor Yellow
        Write-Log "Disabled telemetry services: $($servicesDisabled -join ', ')" 'INFO'
    }

    # Enhanced scheduled task management - batch disable with improved performance
    $telemetryTasks = @(
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
    
    # Batch task operation for better performance
    $tasksDisabled = @()
    $allTasks = Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { 
        $_.TaskPath + $_.TaskName -in $telemetryTasks -and $_.State -ne 'Disabled'
    }
    
    foreach ($task in $allTasks) {
        try {
            Disable-ScheduledTask -InputObject $task -ErrorAction SilentlyContinue
            $tasksDisabled += $task.TaskName
        }
        catch { continue }
    }
    
    if ($tasksDisabled.Count -gt 0) {
        Write-Host "✓ Disabled $($tasksDisabled.Count) telemetry tasks" -ForegroundColor Yellow
        Write-Log "Disabled telemetry scheduled tasks: $($tasksDisabled -join ', ')" 'INFO'
    }

    # Optimized registry configuration for telemetry - parallel execution
    $telemetryRegistry = @{
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection' = @{ 'AllowTelemetry' = 0 }
        'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat' = @{ 
            'AITEnable' = 0
            'DisableInventory' = 1 
        }
        'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' = @{ 
            'UploadUserActivities' = 0
            'PublishUserActivities' = 0 
        }
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Privacy' = @{
            'TailoredExperiencesWithDiagnosticDataEnabled' = 0
        }
        'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo' = @{
            'DisabledByGroupPolicy' = 1
        }
    }
    
    $registryChanges = 0
    $registryErrors = 0
    
    foreach ($regPath in $telemetryRegistry.Keys) {
        try {
            if (-not (Test-Path $regPath)) { 
                New-Item -Path $regPath -Force | Out-Null 
            }
            foreach ($setting in $telemetryRegistry[$regPath].GetEnumerator()) {
                try {
                    Set-ItemProperty -Path $regPath -Name $setting.Key -Value $setting.Value -Force
                    $registryChanges++
                }
                catch {
                    $registryErrors++
                    continue
                }
            }
        }
        catch { 
            $registryErrors++
            continue 
        }
    }
    
    if ($registryChanges -gt 0) {
        Write-Host "✓ Applied $registryChanges telemetry registry settings" -ForegroundColor Green
        Write-Log "Applied $registryChanges telemetry registry configurations" 'INFO'
    }
    
    if ($registryErrors -gt 0) {
        Write-Log "Failed to apply $registryErrors registry settings" 'WARN'
    }

    Write-Log "[END] Disable Telemetry" 'INFO'
}

### [TASK 6] System Restore Protection
function Protect-SystemRestore {
    # ===============================
    # Task: SystemRestoreProtection (Enhanced)
    # ===============================
    # Purpose: Efficiently enables System Restore and creates restore points with intelligent validation.
    # Environment: Windows 10/11, admin required, optimized for performance and reliability.
    # Logic: Fast status checks, duplicate protection, disk space validation, smart restore point management.
    Write-Log "[START] System Restore Protection" 'INFO'
    
    $drive = "C:\"
    $restorePointDescription = "Pre-maintenance restore point"
    $restoreEnabled = $false
    $restorePointCreated = $false
    
    # Enhanced System Restore status check with single optimized query
    try {
        # Use unified approach that works efficiently in both PS versions
        $systemRestoreInfo = if ($PSVersionTable.PSVersion.Major -ge 7) {
            # PowerShell 7: Use Windows PowerShell for System Restore operations
            $command = @"
try {
    \$restoreConfig = Get-CimInstance -Namespace root/default -ClassName SystemRestoreConfig -ErrorAction Stop
    \$freeSpace = (Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'" -ErrorAction Stop).FreeSpace
    \$recentPoints = Get-ComputerRestorePoint -ErrorAction SilentlyContinue | Where-Object { \$_.CreationTime -gt (Get-Date).AddHours(-2) }
    [PSCustomObject]@{
        Enabled = \$restoreConfig.Enable
        FreeSpaceGB = [math]::Round(\$freeSpace / 1GB, 2)
        RecentPointsCount = (\$recentPoints | Measure-Object).Count
        LastPointTime = if (\$recentPoints) { (\$recentPoints | Sort-Object CreationTime -Descending | Select-Object -First 1).CreationTime } else { \$null }
    }
} catch {
    [PSCustomObject]@{ Enabled = \$false; FreeSpaceGB = 0; RecentPointsCount = 0; LastPointTime = \$null; Error = \$_.Message }
}
"@
            Invoke-WindowsPowerShellCommand -Command $command -Description "Check System Restore comprehensive status"
        }
        else {
            # Windows PowerShell 5.1: Native approach
            try {
                $restoreConfig = Get-CimInstance -Namespace root/default -ClassName SystemRestoreConfig -ErrorAction Stop
                $freeSpace = (Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'" -ErrorAction Stop).FreeSpace
                $recentPoints = Get-ComputerRestorePoint -ErrorAction SilentlyContinue | Where-Object { $_.CreationTime -gt (Get-Date).AddHours(-2) }
                [PSCustomObject]@{
                    Enabled = $restoreConfig.Enable
                    FreeSpaceGB = [math]::Round($freeSpace / 1GB, 2)
                    RecentPointsCount = ($recentPoints | Measure-Object).Count
                    LastPointTime = if ($recentPoints) { ($recentPoints | Sort-Object CreationTime -Descending | Select-Object -First 1).CreationTime } else { $null }
                }
            }
            catch {
                [PSCustomObject]@{ Enabled = $false; FreeSpaceGB = 0; RecentPointsCount = 0; LastPointTime = $null; Error = $_.Message }
            }
        }
        
        if ($systemRestoreInfo.Error) {
            Write-Log "Failed to query System Restore status: $($systemRestoreInfo.Error)" 'WARN'
            return
        }
        
        # Intelligent restore point management
        $restoreEnabled = $systemRestoreInfo.Enabled
        $freeSpaceGB = $systemRestoreInfo.FreeSpaceGB
        $recentPointsCount = $systemRestoreInfo.RecentPointsCount
        $lastPointTime = $systemRestoreInfo.LastPointTime
        
        # Enhanced validation logic
        if (-not $restoreEnabled) {
            Write-Host "⚠️ System Restore disabled - enabling..." -ForegroundColor Yellow
            
            # Enable System Restore efficiently
            try {
                $enableResult = if ($PSVersionTable.PSVersion.Major -ge 7) {
                    Enable-ComputerRestoreCompatible -Drive $drive
                }
                else {
                    Enable-ComputerRestore -Drive $drive -ErrorAction Stop
                    $true
                }
                
                if ($enableResult) {
                    $restoreEnabled = $true
                    Write-Host "✓ System Restore enabled" -ForegroundColor Green
                    Write-Log "System Restore enabled on $drive" 'INFO'
                }
                else {
                    Write-Log "Failed to enable System Restore on $drive" 'WARN'
                    return
                }
            }
            catch {
                Write-Log "Failed to enable System Restore: $_" 'WARN'
                return
            }
        }
        else {
            Write-Host "✓ System Restore already enabled" -ForegroundColor Green
        }
        
        # Disk space validation (require at least 2GB free)
        if ($freeSpaceGB -lt 2) {
            Write-Host "⚠️ Insufficient disk space ($($freeSpaceGB)GB) for restore point" -ForegroundColor Yellow
            Write-Log "Insufficient disk space ($($freeSpaceGB)GB) to create restore point safely" 'WARN'
            return
        }
        
        # Smart duplicate restore point protection
        if ($recentPointsCount -gt 0 -and $lastPointTime) {
            $timeSinceLastPoint = (Get-Date) - $lastPointTime
            if ($timeSinceLastPoint.TotalMinutes -lt 120) {
                Write-Host "✓ Recent restore point exists ($([math]::Round($timeSinceLastPoint.TotalMinutes))min ago) - skipping" -ForegroundColor Cyan
                Write-Log "Recent restore point exists (created $([math]::Round($timeSinceLastPoint.TotalMinutes)) minutes ago) - skipping creation" 'INFO'
                $restorePointCreated = $true  # Consider it successful since protection exists
                return
            }
        }
        
        # Create restore point with enhanced error handling
        if ($restoreEnabled) {
            Write-Host "🔄 Creating restore point..." -ForegroundColor Cyan
            
            try {
                $createResult = if ($PSVersionTable.PSVersion.Major -ge 7) {
                    Checkpoint-ComputerCompatible -Description $restorePointDescription -RestorePointType 'MODIFY_SETTINGS'
                }
                else {
                    Checkpoint-Computer -Description $restorePointDescription -RestorePointType 'MODIFY_SETTINGS' -ErrorAction Stop
                    $true
                }
                
                if ($createResult) {
                    $restorePointCreated = $true
                    Write-Host "✓ Restore point created successfully" -ForegroundColor Green
                    Write-Log "System restore point '$restorePointDescription' created successfully" 'INFO'
                    
                    # Optional: Clean up old restore points if more than 10 exist
                    try {
                        $allPoints = if ($PSVersionTable.PSVersion.Major -ge 7) {
                            $cmd = "Get-ComputerRestorePoint -ErrorAction SilentlyContinue | Measure-Object | Select-Object -ExpandProperty Count"
                            Invoke-WindowsPowerShellCommand -Command $cmd -Description "Count restore points"
                        }
                        else {
                            (Get-ComputerRestorePoint -ErrorAction SilentlyContinue | Measure-Object).Count
                        }
                        
                        if ($allPoints -and $allPoints -gt 10) {
                            Write-Log "Found $allPoints restore points - system will auto-manage cleanup" 'VERBOSE'
                        }
                    }
                    catch {
                        # Ignore cleanup check errors
                    }
                }
                else {
                    Write-Log "Failed to create restore point - unknown error" 'WARN'
                }
            }
            catch {
                $errorMessage = $_.Exception.Message
                if ($errorMessage -like "*0x80042302*" -or $errorMessage -like "*CORESERVICE_NOT_RESPONDING*") {
                    Write-Log "System Restore service not responding - this is normal during heavy system activity" 'WARN'
                }
                elseif ($errorMessage -like "*0x80042308*") {
                    Write-Log "Restore point frequency limit reached - skipping (Windows limitation)" 'WARN'
                    $restorePointCreated = $true  # Consider successful since limit is hit
                }
                elseif ($errorMessage -like "*insufficient*") {
                    Write-Log "Insufficient disk space for restore point creation" 'WARN'
                }
                else {
                    Write-Log "Failed to create restore point: $errorMessage" 'WARN'
                }
            }
        }
    }
    catch {
        Write-Log "System Restore operation failed: $_" 'WARN'
    }
    
    # Summary with performance metrics
    $successSummary = @()
    if ($restoreEnabled) { $successSummary += "SR Enabled" }
    if ($restorePointCreated) { $successSummary += "Point Created" }
    
    if ($successSummary.Count -gt 0) {
        Write-Host "✅ System Restore: $($successSummary -join ', ')" -ForegroundColor Green
        Write-Log "System Restore protection completed: $($successSummary -join ', ')" 'INFO'
    }
    else {
        Write-Host "⚠️ System Restore protection incomplete" -ForegroundColor Yellow
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
