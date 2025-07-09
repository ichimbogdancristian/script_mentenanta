
# =====================[ LOGGING & TASK FUNCTIONS FIRST ]==================
function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('INFO','WARN','ERROR')][string]$Level = 'INFO'
    )
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $entry = "[$timestamp] [$Level] $Message"
    $entry | Out-File -FilePath $logPath -Append
    Write-Host $entry
}

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

# Set up log file in the extracted folder (always use the script's folder)
$logPath = Join-Path $PSScriptRoot "maintenance.log"
Write-Log "Script started. User: $env:USERNAME, Computer: $env:COMPUTERNAME, Script Version: 1.0.0" 'INFO'

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

# =====================[ TASK: REMOVE BLOATWARE ]==========================
function Remove-Bloatware {
    Write-Log "[START] Remove Bloatware" 'INFO'
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
    Write-Log "[END] Remove Bloatware" 'INFO'
}

# =====================[ TASK: INSTALL ESSENTIAL APPS ]====================
function Install-EssentialApps {
    Write-Log "[START] Install Essential Apps" 'INFO'
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
    Write-Log "[END] Install Essential Apps" 'INFO'
}

# =====================[ TASK: SYSTEM INVENTORY ]==========================
function Get-SystemInventory {
    Write-Log "[START] System Inventory" 'INFO'
    $inventoryPath = Join-Path $global:TempFolder 'inventory.txt'
    Get-ComputerInfo | Out-File $inventoryPath
    Write-Log "System inventory saved to $inventoryPath" 'INFO'
    Write-Log "[END] System Inventory" 'INFO'
}

# =====================[ TASK: DISABLE TELEMETRY ]=========================
function Disable-Telemetry {
    Write-Log "[START] Disable Telemetry" 'INFO'
    # Example: Set registry keys to disable telemetry (minimal demo)
    $regPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'
    if (-not (Test-Path $regPath)) { New-Item -Path $regPath -Force | Out-Null }
    Set-ItemProperty -Path $regPath -Name 'AllowTelemetry' -Value 0 -Force
    Write-Log "Set AllowTelemetry=0 in $regPath" 'INFO'
    Write-Log "[END] Disable Telemetry" 'INFO'
}

# =====================[ CENTRAL TASK EXECUTION ]==========================
# Use Invoke-Task for each new function
Write-Log "[COORDINATION] Starting inspired tasks from system_maintenance..." 'INFO'
$taskResults = @{}
$taskResults['RemoveBloatware'] = Invoke-Task 'RemoveBloatware' { Remove-Bloatware }
$taskResults['InstallEssentialApps'] = Invoke-Task 'InstallEssentialApps' { Install-EssentialApps }
$taskResults['SystemInventory'] = Invoke-Task 'SystemInventory' { Get-SystemInventory }
$taskResults['DisableTelemetry'] = Invoke-Task 'DisableTelemetry' { Disable-Telemetry }
Write-Log "[COORDINATION] All inspired tasks completed." 'INFO'

# Maintenance Script Boilerplate for Windows 10/11
# This script is intended to be downloaded and executed by script.bat
# Add your maintenance tasks below

# Ensure script is running as Administrator
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Warning "This script must be run as Administrator. Exiting."
    exit 1
}

# === Built-in Maintenance Tasks ===
Write-Log "Starting maintenance tasks..." 'INFO'

# Task 1: Clean temp files
$taskResults['CleanTempFiles'] = Invoke-Task 'CleanTempFiles' {
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
}

# Task 2: Disk cleanup (placeholder)
$taskResults['DiskCleanup'] = Invoke-Task 'DiskCleanup' {
    # Write-Log "Running disk cleanup..." 'INFO'
    # ...
}

# Task 3: Windows Update check (placeholder)
$taskResults['WindowsUpdateCheck'] = Invoke-Task 'WindowsUpdateCheck' {
    # Write-Log "Checking for Windows Updates..." 'INFO'
    # ...
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
