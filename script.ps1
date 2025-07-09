
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

# Full bloatware list
$global:BloatwareList = @(
    'Acer.AcerPowerManagement', 'Acer.AcerQuickAccess', 'Acer.AcerUEIPFramework', 'Acer.AcerUserExperienceImprovementProgram',
    'Adobe.AdobeCreativeCloud', 'Adobe.AdobeExpress', 'Adobe.AdobeGenuineService', 'Amazon.AmazonPrimeVideo',
    'ASUS.ASUSGiftBox', 'ASUS.ASUSLiveUpdate', 'ASUS.ASUSSplendidVideoEnhancementTechnology', 'ASUS.ASUSWebStorage',
    'ASUS.ASUSZenAnywhere', 'ASUS.ASUSZenLink', 'Astian.Midori', 'AvantBrowser.AvantBrowser', 'Avast.AvastFreeAntivirus',
    'AVG.AVGAntiVirusFree', 'Avira.Avira', 'Baidu.BaiduBrowser', 'Baidu.PCAppStore', 'Basilisk.Basilisk',
    'Bitdefender.Bitdefender', 'Blisk.Blisk', 'Booking.com.Booking', 'BraveSoftware.BraveBrowser',
    'CentBrowser.CentBrowser', 'Cliqz.Cliqz', 'Coowon.Coowon', 'CoolNovo.CoolNovo', 'CyberLink.MediaSuite',
    'CyberLink.Power2Go', 'CyberLink.PowerDirector', 'CyberLink.PowerDVD', 'CyberLink.YouCam', 'Dell.CustomerConnect',
    'Dell.DellDigitalDelivery', 'Dell.DellFoundationServices', 'Dell.DellHelpAndSupport', 'Dell.DellMobileConnect',
    'Dell.DellPowerManager', 'Dell.DellProductRegistration', 'Dell.DellSupportAssist', 'Dell.DellUpdate',
    'DigitalPersona.EpicPrivacyBrowser', 'Disney.DisneyPlus', 'Dooble.Dooble', 'DriverPack.DriverPackSolution',
    'ESET.ESETNOD32Antivirus', 'Evernote.Evernote', 'ExpressVPN.ExpressVPN', 'Facebook.Facebook',
    'FenrirInc.Sleipnir', 'FlashPeak.SlimBrowser', 'FlashPeak.Slimjet', 'Foxit.FoxitPDFReader',
    'Gameloft.MarchofEmpires', 'G5Entertainment.HiddenCity', 'GhostBrowser.GhostBrowser', 'Google.YouTube',
    'HP.HP3DDriveGuard', 'HP.HPAudioSwitch', 'HP.HPClientSecurityManager', 'HP.HPConnectionOptimizer',
    'HP.HPDocumentation', 'HP.HPDropboxPlugin', 'HP.HPePrintSW', 'HP.HPJumpStart', 'HP.HPJumpStartApps',
    'HP.HPJumpStartLaunch', 'HP.HPRegistrationService', 'HP.HPSupportSolutionsFramework', 'HP.HPSureConnect',
    'HP.HPSystemEventUtility', 'HP.HPWelcome', 'HewlettPackard.SupportAssistant', 'Hulu.Hulu', 'Instagram.Instagram',
    'IOBit.AdvancedSystemCare', 'IOBit.DriverBooster', 'KDE.Falkon', 'Kaspersky.Kaspersky', 'KeeperSecurity.Keeper',
    'king.com.BubbleWitch', 'king.com.CandyCrush', 'king.com.CandyCrushFriends', 'king.com.CandyCrushSaga',
    'king.com.CandyCrushSodaSaga', 'king.com.FarmHeroes', 'king.com.FarmHeroesSaga', 'Lenovo.AppExplorer',
    'Lenovo.LenovoCompanion', 'Lenovo.LenovoExperienceImprovement', 'Lenovo.LenovoFamilyCloud',
    'Lenovo.LenovoHotkeys', 'Lenovo.LenovoMigrationAssistant', 'Lenovo.LenovoModernIMController',
    'Lenovo.LenovoServiceBridge', 'Lenovo.LenovoSolutionCenter', 'Lenovo.LenovoUtility', 'Lenovo.LenovoVantage',
    'Lenovo.LenovoVoice', 'Lenovo.LenovoWiFiSecurity', 'LinkedIn.LinkedIn', 'Lunascape.Lunascape',
    'Maxthon.Maxthon', 'McAfee.LiveSafe', 'McAfee.Livesafe', 'McAfee.SafeConnect', 'McAfee.Security',
    'McAfee.WebAdvisor', 'Microsoft.3DBuilder', 'Microsoft.Advertising.Xaml', 'Microsoft.BingFinance',
    'Microsoft.BingFoodAndDrink', 'Microsoft.BingHealthAndFitness', 'Microsoft.BingNews', 'Microsoft.BingSports',
    'Microsoft.BingTravel', 'Microsoft.BingWeather', 'Microsoft.GetHelp', 'Microsoft.Getstarted',
    'Microsoft.Microsoft3DViewer', 'Microsoft.MicrosoftOfficeHub', 'Microsoft.MicrosoftPowerBIForWindows',
    'Microsoft.MicrosoftSolitaireCollection', 'Microsoft.MinecraftUWP', 'Microsoft.MixedReality.Portal',
    'Microsoft.NetworkSpeedTest', 'Microsoft.News', 'Microsoft.Office.OneNote', 'Microsoft.Office.Sway',
    'Microsoft.OneConnect', 'Microsoft.OneDrive', 'Microsoft.People', 'Microsoft.Print3D', 'Microsoft.ScreenSketch',
    'Microsoft.SkypeApp', 'Microsoft.SoundRecorder', 'Microsoft.StickyNotes', 'Microsoft.Wallet',
    'Microsoft.Whiteboard', 'Microsoft.WindowsFeedback', 'Microsoft.WindowsFeedbackHub', 'Microsoft.WindowsMaps',
    'Microsoft.WindowsReadingList', 'Microsoft.WindowsSoundRecorder', 'Microsoft.Xbox.TCUI', 'Microsoft.XboxApp',
    'Microsoft.XboxGameOverlay', 'Microsoft.XboxGamingOverlay', 'Microsoft.XboxIdentityProvider',
    'Microsoft.XboxSpeechToTextOverlay', 'Microsoft.ZuneMusic', 'Microsoft.ZuneVideo', 'Mozilla.SeaMonkey',
    'Norton.OnlineBackup', 'Norton.Security', 'Opera.Opera', 'Opera.OperaGX', 'Orbitum.Orbitum',
    'OtterBrowser.OtterBrowser', 'PaleMoon.PaleMoon', 'PCAccelerate.PCAcceleratePro', 'PCOptimizer.PCOptimizerPro',
    'PicsArt.PicsartPhotoStudio', 'Piriform.CCleaner', 'Polarity.Polarity', 'Power2Go.Power2Go',
    'PowerDirector.PowerDirector', 'QupZilla.QupZilla', 'QuteBrowser.QuteBrowser', 'RandomSaladGamesLLC.SimpleSolitaire',
    'Reimage.ReimageRepair', 'RoyalRevolt2.RoyalRevolt2', 'Sleipnir.Sleipnir', 'SlingTV.Sling',
    'Sogou.SogouExplorer', 'Spotify.Spotify', 'SRWare.Iron', 'Sputnik.Sputnik', 'Superbird.Superbird',
    'TheTorProject.TorBrowser', 'ThumbmunkeysLtd.PhototasticCollage', 'TikTok.TikTok', 'TorchMediaInc.Torch',
    'TripAdvisor.TripAdvisor', 'Twitter.Twitter', 'UCWeb.UCBrowser', 'VivaldiTechnologies.Vivaldi',
    'Waterfox.Waterfox', 'WildTangent.WildTangentGamesApp', 'WildTangent.WildTangentHelper', 'WPSOffice.WPSOffice',
    'Yandex.YandexBrowser'
) | Sort-Object -Unique
$bloatwareListPath = Join-Path $global:TempFolder 'Bloatware_list.txt'
$global:BloatwareList | ForEach-Object { $_ | ConvertTo-Json -Compress } | Out-File $bloatwareListPath -Encoding UTF8

# === EssentialApps ===
$global:EssentialApps = @(
    @{ Name = 'Adobe Acrobat Reader'; Winget = 'Adobe.Acrobat.Reader.64-bit'; Choco = 'adobereader' },
    @{ Name = 'Google Chrome'; Winget = 'Google.Chrome'; Choco = 'googlechrome' },
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

function Protect-SystemRestore {
    Write-Log "[START] System Restore Protection" 'INFO'
    $drive = "C:\\"
    $restoreEnabled = $false
    try {
        $sr = Get-CimInstance -Namespace root/default -ClassName SystemRestoreConfig -ErrorAction Stop
        if ($sr.Enable == $true) {
            $restoreEnabled = $true
            Write-Log "System Restore is already enabled on $drive" 'INFO'
        } else {
            Write-Log "System Restore is not enabled. Enabling..." 'INFO'
            Enable-ComputerRestore -Drive $drive
            $restoreEnabled = $true
            Write-Log "System Restore enabled on $drive" 'INFO'
        }
    } catch {
        Write-Log "Could not determine or enable System Restore: $_" 'WARN'
    }
    if ($restoreEnabled) {
        try {
            Write-Log "Creating a system restore point..." 'INFO'
            Checkpoint-Computer -Description "Pre-maintenance restore point" -RestorePointType 'MODIFY_SETTINGS'
            Write-Log "System restore point created." 'INFO'
        } catch {
            Write-Log "Failed to create restore point: $_" 'WARN'
        }
    }
    Write-Log "[END] System Restore Protection" 'INFO'
}

Write-Log "[COORDINATION] Starting inspired tasks from system_maintenance..." 'INFO'
$taskResults = @{}
$taskResults['SystemRestoreProtection'] = Invoke-Task 'SystemRestoreProtection' { Protect-SystemRestore }
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

# Task 4: Update all apps and packages
$taskResults['UpdateAllPackages'] = Invoke-Task 'UpdateAllPackages' {
    Write-Log "[START] Update All Apps and Packages" 'INFO'
    # Update with winget
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        try {
            Write-Log "Running: winget upgrade --all --silent --accept-source-agreements --accept-package-agreements" 'INFO'
            winget upgrade --all --silent --accept-source-agreements --accept-package-agreements
            Write-Log "winget upgrade completed." 'INFO'
        } catch {
            Write-Log "winget upgrade failed: $_" 'WARN'
        }
    } else {
        Write-Log "winget not found, skipping winget upgrades." 'WARN'
    }
    # Update with Chocolatey
    if (Get-Command choco -ErrorAction SilentlyContinue) {
        try {
            Write-Log "Running: choco upgrade all -y" 'INFO'
            choco upgrade all -y
            Write-Log "choco upgrade completed." 'INFO'
        } catch {
            Write-Log "choco upgrade failed: $_" 'WARN'
        }
    } else {
        Write-Log "choco not found, skipping choco upgrades." 'WARN'
    }
    Write-Log "[END] Update All Apps and Packages" 'INFO'
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
