

# =====================[ CENTRALIZED LOGGING FUNCTION ]====================
function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('INFO','WARN','ERROR')][string]$Level = 'INFO'
    )
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $entry = "[$timestamp] [$Level] $Message"
    if (-not $script:logPath) {
        # Try to set logPath to a default if not already set
        if ($PSScriptRoot) {
            $script:logPath = Join-Path $PSScriptRoot 'maintenance.log'
        } else {
            $script:logPath = Join-Path (Get-Location) 'maintenance.log'
        }
    }
    $entry | Out-File -FilePath $script:logPath -Append
    Write-Host $entry
}

# === Central Coordination Policy for Task Execution ===
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
    } catch {
        Write-Log "Task failed: $TaskName. Error: $_" 'ERROR'
        return $false
    }
}

# =====================[ MAIN SCRIPT STARTS HERE ]========================


# =====================[ ENSURE WINGET, CHOCO & NUGET INSTALLED/UPDATED ]==================
function Test-Winget {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Log "winget not found. Attempting to install winget..." 'WARN'
        # Try to install App Installer from Microsoft Store (winget is part of it)
        try {
            Invoke-WebRequest -Uri "https://aka.ms/getwinget" -OutFile "$env:TEMP\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle" -UseBasicParsing
            Add-AppxPackage -Path "$env:TEMP\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"
            Write-Log "winget installed via App Installer." 'INFO'
        } catch {
            Write-Log "Failed to install winget: $_" 'ERROR'
        }
    } else {
        Write-Log "winget found. Checking for updates..." 'INFO'
        try {
            winget upgrade --id Microsoft.DesktopAppInstaller --accept-source-agreements --accept-package-agreements --silent
            Write-Log "winget updated." 'INFO'
        } catch {
            Write-Log "Failed to update winget: $_" 'WARN'
        }
    }
}

function Test-Choco {
    if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
        Write-Log "choco not found. Attempting to install Chocolatey..." 'WARN'
        try {
            Set-ExecutionPolicy Bypass -Scope Process -Force
            [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
            Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
            Write-Log "choco installed." 'INFO'
        } catch {
            Write-Log "Failed to install choco: $_" 'ERROR'
        }
    } else {
        Write-Log "choco found. Checking for updates..." 'INFO'
        try {
            choco upgrade chocolatey -y
            Write-Log "choco updated." 'INFO'
        } catch {
            Write-Log "Failed to update choco: $_" 'WARN'
        }
    }
}

# Ensure NuGet is installed/updated and NuGet provider is available (unattended)
function Test-NuGet {
    $nugetInstalled = $false
    if (Get-Command nuget -ErrorAction SilentlyContinue) {
        $nugetInstalled = $true
        Write-Log "NuGet found. Checking for updates..." 'INFO'
        try {
            if (Get-Command winget -ErrorAction SilentlyContinue) {
                Start-Process -FilePath "winget" -ArgumentList @("upgrade", "--id", "NuGet.NuGet", "--accept-source-agreements", "--accept-package-agreements", "--silent", "-e") -NoNewWindow -WindowStyle Hidden -Wait
                Write-Log "NuGet updated via winget." 'INFO'
            } elseif (Get-Command choco -ErrorAction SilentlyContinue) {
                Start-Process -FilePath "choco" -ArgumentList @("upgrade", "nuget.commandline", "-y", "--no-progress") -NoNewWindow -WindowStyle Hidden -Wait
                Write-Log "NuGet updated via choco." 'INFO'
            }
        } catch {
            Write-Log "Failed to update NuGet: $_" 'WARN'
        }
    } else {
        Write-Log "NuGet not found. Attempting to install NuGet..." 'WARN'
        try {
            if (Get-Command winget -ErrorAction SilentlyContinue) {
                Start-Process -FilePath "winget" -ArgumentList @("install", "--id", "NuGet.NuGet", "--accept-source-agreements", "--accept-package-agreements", "--silent", "-e") -NoNewWindow -WindowStyle Hidden -Wait
                Write-Log "NuGet installed via winget." 'INFO'
            } elseif (Get-Command choco -ErrorAction SilentlyContinue) {
                Start-Process -FilePath "choco" -ArgumentList @("install", "nuget.commandline", "-y", "--no-progress") -NoNewWindow -WindowStyle Hidden -Wait
                Write-Log "NuGet installed via choco." 'INFO'
            } else {
                Write-Log "No installer found for NuGet." 'WARN'
            }
        } catch {
            Write-Log "Failed to install NuGet: $_" 'ERROR'
        }
    }
    # Ensure NuGet provider for PowerShell is installed (unattended)
    try {
        $provider = Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue
        if (-not $provider -or $provider.Version -lt [version]'2.8.5.201') {
            Write-Log "Installing or updating NuGet provider for PowerShell (unattended)..." 'INFO'
            Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser | Out-Null
            Write-Log "NuGet provider for PowerShell installed/updated." 'INFO'
        } else {
            Write-Log "NuGet provider for PowerShell is present and up to date." 'INFO'
        }
    } catch {
        Write-Log "Failed to install or update NuGet provider for PowerShell: $_" 'WARN'
    }
}

# Set up log file in the extracted folder (always use the script's folder)
$logPath = Join-Path $PSScriptRoot "maintenance.log"
Write-Log "Script started. User: $env:USERNAME, Computer: $env:COMPUTERNAME, Script Version: 1.0.0" 'INFO'

# Ensure dependencies before anything else
Test-Winget
Test-Choco
Test-NuGet

# Centralized temp folder and essential/bloatware lists (inspired by system_maintenance)
$global:TempFolder = Join-Path $env:TEMP "ScriptMentenanta_$(Get-Random)"
if (-not (Test-Path $global:TempFolder)) {
    New-Item -ItemType Directory -Path $global:TempFolder -Force | Out-Null
}

# Example: Unified bloatware and essential apps lists (customize as needed)
$global:BloatwareList = @(
    'Microsoft.Microsoft3DViewer', 'king.com.CandyCrushSaga', 'Microsoft.XboxApp', 'Microsoft.ZuneMusic',
    'Microsoft.SkypeApp', 'Microsoft.MicrosoftSolitaireCollection', 'Microsoft.BingWeather', 'Spotify', 'Netflix'
) | Sort-Object -Unique
$bloatwareListPath = Join-Path $global:TempFolder 'Bloatware_list.txt'
$global:BloatwareList | ForEach-Object { $_ | ConvertTo-Json -Compress } | Out-File $bloatwareListPath -Encoding UTF8

$global:EssentialApps = @(
    @{ Name = 'Google Chrome'; Winget = 'Google.Chrome'; Choco = 'googlechrome' },
    @{ Name = '7-Zip'; Winget = '7zip.7zip'; Choco = '7zip' },
    @{ Name = 'Notepad++'; Winget = 'Notepad++.Notepad++'; Choco = 'notepadplusplus' }
)
$essentialAppsListPath = Join-Path $global:TempFolder 'EssentialApps_list.txt'
$global:EssentialApps | ForEach-Object { $_ | ConvertTo-Json -Compress } | Out-File $essentialAppsListPath -Encoding UTF8


# =====================[ TASK 1: REMOVE BLOATWARE ]==========================
function Remove-Bloatware {
    Write-Log "[START] Task 1: Remove Bloatware" 'INFO'
    $bloatwareList = Get-Content $bloatwareListPath | ForEach-Object { $_ | ConvertFrom-Json }
    $installedApps = Get-AppxPackage -AllUsers | Select-Object -ExpandProperty Name
    $toRemove = $bloatwareList | Where-Object { $installedApps -contains $_ }
    foreach ($bloat in $toRemove) {
        try {
            Write-Log "Removing bloatware: $bloat" 'INFO'
            Get-AppxPackage -AllUsers -Name $bloat | Remove-AppxPackage -AllUsers -ErrorAction Stop
            Write-Log "Removed: $bloat" 'INFO'
        } catch {
            Write-Log "Failed to remove $bloat $_" 'WARN'
        }
    }
    Write-Log "[END] Task 1: Remove Bloatware" 'INFO'
}


# =====================[ TASK 2: INSTALL ESSENTIAL APPS ]====================
function Install-EssentialApps {
    Write-Log "[START] Task 2: Install Essential Apps" 'INFO'
    $essentialApps = Get-Content $essentialAppsListPath | ForEach-Object { $_ | ConvertFrom-Json }
    foreach ($app in $essentialApps) {
        $installed = Get-StartApps | Where-Object { $_.Name -like "*$($app.Name)*" }
        if (-not $installed) {
            try {
                if ($app.Winget -and (Get-Command winget -ErrorAction SilentlyContinue)) {
                    Write-Log "Installing $($app.Name) via winget..." 'INFO'
                    winget install --id $($app.Winget) --accept-source-agreements --accept-package-agreements --silent -e
                } elseif ($app.Choco -and (Get-Command choco -ErrorAction SilentlyContinue)) {
                    Write-Log "Installing $($app.Name) via choco..." 'INFO'
                    choco install $($app.Choco) -y
                } else {
                    Write-Log "No installer found for $($app.Name)" 'WARN'
                }
                $name = $app.Name
                Write-Log "Installed: $name" 'INFO'
            } catch {
                Write-Log "Failed to install $($app.Name): $_" 'WARN'
            }
        } else {
            Write-Log "$($app.Name) already installed." 'INFO'
        }
    }
    Write-Log "[END] Task 2: Install Essential Apps" 'INFO'
}


# =====================[ TASK 3: SYSTEM INVENTORY ]==========================
function Get-SystemInventory {
    Write-Log "[START] Task 3: System Inventory" 'INFO'
    $inventoryPath = Join-Path $global:TempFolder 'inventory.txt'
    Get-ComputerInfo | Out-File $inventoryPath
    Write-Log "System inventory saved to $inventoryPath" 'INFO'
    Write-Log "[END] Task 3: System Inventory" 'INFO'
}


# =====================[ TASK 4: DISABLE TELEMETRY ]=========================
function Disable-Telemetry {
    Write-Log "[START] Task 4: Disable Telemetry" 'INFO'
    # Example: Set registry keys to disable telemetry (minimal demo)
    $regPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'
    if (-not (Test-Path $regPath)) { New-Item -Path $regPath -Force | Out-Null }
    Set-ItemProperty -Path $regPath -Name 'AllowTelemetry' -Value 0 -Force
    Write-Log "Set AllowTelemetry=0 in $regPath" 'INFO'
    Write-Log "[END] Task 4: Disable Telemetry" 'INFO'
}


# =====================[ CENTRAL TASK EXECUTION ]==========================

# Ensure script is running as Administrator
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Warning "This script must be run as Administrator. Exiting."
    return 1
}

# Use Invoke-Task for each new function
Write-Log "[COORDINATION] Starting inspired tasks from system_maintenance..." 'INFO'
$script:taskResults = @{}
$script:taskResults['RemoveBloatware'] = Invoke-Task 'RemoveBloatware' { Remove-Bloatware }
$script:taskResults['InstallEssentialApps'] = Invoke-Task 'InstallEssentialApps' { Install-EssentialApps }
$script:taskResults['SystemInventory'] = Invoke-Task 'SystemInventory' { Get-SystemInventory }
$script:taskResults['DisableTelemetry'] = Invoke-Task 'DisableTelemetry' { Disable-Telemetry }
Write-Log "[COORDINATION] All inspired tasks completed." 'INFO'



# Set up log file in the extracted folder (always use the script's folder)
$script:logPath = Join-Path $PSScriptRoot "maintenance.log"
Write-Log "Script started. User: $env:USERNAME, Computer: $env:COMPUTERNAME, Script Version: 1.0.0" 'INFO'

# Load configuration (if exists)
$configPath = Join-Path $PSScriptRoot "config.json"
if (Test-Path $configPath) {
    try {
        # $config = Get-Content $configPath | ConvertFrom-Json
        Write-Log "Loaded configuration from config.json" 'INFO'
    } catch {
        Write-Log "Failed to load configuration: $_" 'WARN'
    }
} else {
    Write-Log "No config.json found. Using defaults." 'INFO'
}

# Check Windows version and compatibility
$os = Get-CimInstance Win32_OperatingSystem
$osVersion = $os.Version
$osCaption = $os.Caption
Write-Log "Detected Windows version: $osCaption ($osVersion)" 'INFO'
if ($osVersion -lt '10.0') {
    Write-Log "Unsupported Windows version. Exiting." 'ERROR'
    exit 2
}

# Check for required PowerShell version
if ($PSVersionTable.PSVersion.Major -lt 5) {
    Write-Log "PowerShell 5.1 or higher is required. Exiting." 'ERROR'
    exit 3
}

# Example: Self-update check (hash validation)
$expectedHash = $null # Set to known-good hash if desired
if ($expectedHash) {
    $actualHash = (Get-FileHash -Path $MyInvocation.MyCommand.Path -Algorithm SHA256).Hash
    if ($actualHash -ne $expectedHash) {
        Write-Log "Script hash mismatch! Possible tampering. Exiting." 'ERROR'
        exit 4
    }
}


# === Central Coordination Policy for Task Execution ===
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
    } catch {
        Write-Log "Task failed: $TaskName. Error: $_" 'ERROR'
        return $false
    }
}

$taskResults = @{}

Write-Log "Starting maintenance tasks..." 'INFO'


# =====================[ TASK 5: CLEAN TEMP FILES ]==========================
$taskResults['CleanTempFiles'] = Invoke-Task 'Task 5: CleanTempFiles' {
    Write-Log "[START] Task 5: Clean Temp Files" 'INFO'
    $temp = $env:TEMP
    $tempFiles = Get-ChildItem -Path $temp -Recurse -ErrorAction SilentlyContinue
    $deleted = 0
    foreach ($file in $tempFiles) {
        try {
            Remove-Item $file.FullName -Force -Recurse -ErrorAction Stop
            $deleted++
        } catch {}
    }
    Write-Log "Deleted $deleted temp files from $temp" 'INFO'
    Write-Log "[END] Task 5: Clean Temp Files" 'INFO'
}

# =====================[ TASK 6: DISK CLEANUP (PLACEHOLDER) ]================
$taskResults['DiskCleanup'] = Invoke-Task 'Task 6: DiskCleanup' {
    Write-Log "[START] Task 6: Disk Cleanup (Placeholder)" 'INFO'
    # Write-Log "Running disk cleanup..." 'INFO'
    # ...
    Write-Log "[END] Task 6: Disk Cleanup (Placeholder)" 'INFO'
}

# =====================[ TASK 7: WINDOWS UPDATE CHECK (PLACEHOLDER) ]========
$taskResults['WindowsUpdateCheck'] = Invoke-Task 'Task 7: WindowsUpdateCheck' {
    Write-Log "[START] Task 7: Windows Update Check (Placeholder)" 'INFO'
    # Write-Log "Checking for Windows Updates..." 'INFO'
    # ...
    Write-Log "[END] Task 7: Windows Update Check (Placeholder)" 'INFO'
}

# Add more tasks as needed, using Invoke-Task for each

# Summary of all tasks
$successCount = ($taskResults.Values | Where-Object { $_ }).Count
$failCount = ($taskResults.Values | Where-Object { -not $_ }).Count
Write-Log "All tasks completed. Success: $successCount, Failed: $failCount" 'INFO'

# === Reporting Section ===
# Example: Export summary report
$summaryPath = Join-Path $PSScriptRoot "maintenance_summary.txt"
"Maintenance completed at $(Get-Date) on $env:COMPUTERNAME by $env:USERNAME" | Out-File -FilePath $summaryPath -Append
Write-Log "Summary report written to $summaryPath" 'INFO'

# Example: Optionally send report via email or webhook (not implemented)
# ...

Write-Log "Script ended." 'INFO'

# Prompt to close the window if running interactively
if ($Host.Name -eq 'ConsoleHost' -or $Host.Name -like '*Windows*') {
    Write-Host
    Read-Host -Prompt 'Press Enter to close this window...'
}
