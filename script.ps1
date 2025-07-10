# =====================[ LOGGING & TASK FUNCTIONS FIRST ]==================
function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('INFO','WARN','ERROR')][string]$Level = 'INFO'
    )
    $timestamp = Get-Date -Format 'HH:mm:ss'
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
    'Waterfox.Waterfox', 'WildTangent.WildTangentGamesApp', 'WildTangent.WildTangentHelper',
    'WPSOffice.WPSOffice', 'Kingsoft.WPSOffice', 'Kingsoft.Writer', 'Kingsoft.Presentation', 'Kingsoft.Spreadsheets',
    'Apache.OpenOffice', 'Microsoft.Outlook', 'Yandex.YandexBrowser'
) | Sort-Object -Unique
$bloatwareListPath = Join-Path $global:TempFolder 'Bloatware_list.txt'
$global:BloatwareList | ForEach-Object { $_ | ConvertTo-Json -Compress } | Out-File $bloatwareListPath -Encoding UTF8

# === EssentialApps ===
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


# =====================[ TASK 3: REMOVE BLOATWARE ]==========================
function Remove-Bloatware {
    # [TASK 3] Remove Bloatware
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


# =====================[ TASK 4: INSTALL ESSENTIAL APPS ]====================
function Install-EssentialApps {
    # [TASK 4] Install Essential Apps
    Write-Log "[START] Install Essential Apps" 'INFO'
    $essentialApps = Get-Content $essentialAppsListPath | ForEach-Object { $_ | ConvertFrom-Json }
    foreach ($app in $essentialApps) {
        $installed = Get-StartApps | Where-Object { $_.Name -like "*$($app.Name)*" }
        if (-not $installed) {
            try {
                if ($app.Winget -and (Get-Command winget -ErrorAction SilentlyContinue)) {
                    Write-Log "Installing $($app.Name) via winget..." 'INFO'
                    Start-Process -FilePath "winget" -ArgumentList @("install", "--id", $app.Winget, "--accept-source-agreements", "--accept-package-agreements", "--silent", "-e") -NoNewWindow -WindowStyle Hidden -Wait
                } elseif ($app.Choco -and (Get-Command choco -ErrorAction SilentlyContinue)) {
                    Write-Log "Installing $($app.Name) via choco..." 'INFO'
                    Start-Process -FilePath "choco" -ArgumentList @("install", $app.Choco, "-y", "--no-progress") -NoNewWindow -WindowStyle Hidden -Wait
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
    # Check for Microsoft Office, install LibreOffice if not present
    $officeInstalled = $false
    try {
        # Check for Office via registry (common for Office 2016/2019/2021/365)
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
                break
            }
        }
        # Also check for Office apps in Start Menu
        if (-not $officeInstalled) {
            $officeApps = Get-StartApps | Where-Object { $_.Name -match 'Office|Word|Excel|PowerPoint|Outlook' }
            if ($officeApps) { $officeInstalled = $true }
        }
    } catch {
        Write-Log "Error checking for Microsoft Office: $_" 'WARN'
    }
    if (-not $officeInstalled) {
        Write-Log "Microsoft Office not detected. Installing LibreOffice as alternative..." 'INFO'
        try {
            if (Get-Command winget -ErrorAction SilentlyContinue) {
                winget install --id TheDocumentFoundation.LibreOffice --accept-source-agreements --accept-package-agreements --silent -e
                Write-Log "LibreOffice installed via winget." 'INFO'
            } elseif (Get-Command choco -ErrorAction SilentlyContinue) {
                choco install libreoffice-fresh -y
                Write-Log "LibreOffice installed via choco." 'INFO'
            } else {
                Write-Log "No installer found for LibreOffice." 'WARN'
            }
        } catch {
            Write-Log "Failed to install LibreOffice: $_" 'WARN'
        }
    } else {
        Write-Log "Microsoft Office detected. Skipping LibreOffice installation." 'INFO'
    }
    Write-Log "[END] Install Essential Apps" 'INFO'
}


# =====================[ TASK 6: SYSTEM INVENTORY ]==========================
function Get-SystemInventory {
    # [TASK 6] System Inventory
    Write-Log "[START] System Inventory" 'INFO'
    $inventoryPath = Join-Path $global:TempFolder 'inventory.txt'
    Get-ComputerInfo | Out-File $inventoryPath
    Write-Log "System inventory saved to $inventoryPath" 'INFO'
    Write-Log "[END] System Inventory" 'INFO'
}


# =====================[ TASK 2: DISABLE TELEMETRY ]=========================
function Disable-Telemetry {
    # [TASK 2] Disable Telemetry
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
    } catch {
        Write-Log "Failed to disable all OS notifications: $_" 'WARN'
    }

    # Remove all browsers except Edge, Chrome, and Firefox
    $allowedBrowsers = @('Microsoft Edge', 'Google Chrome', 'Mozilla Firefox')
    $knownBrowsers = @('Opera', 'Opera GX', 'Brave', 'Vivaldi', 'Waterfox', 'Yandex', 'Tor Browser', 'Pale Moon', 'Chromium', 'SRWare Iron', 'Comodo Dragon', 'Maxthon', 'UC Browser', 'Epic Privacy Browser', 'Slimjet', 'CentBrowser', 'QuteBrowser', 'OtterBrowser', 'Dooble', 'Midori', 'Blisk', 'AvantBrowser', 'Sleipnir', 'Polarity', 'Torch', 'Orbitum', 'Superbird', 'Sputnik', 'Lunascape', 'Falkon', 'SeaMonkey')
    foreach ($browser in $knownBrowsers) {
        if ($allowedBrowsers -notcontains $browser) {
            try {
                if (Get-Command winget -ErrorAction SilentlyContinue) {
                    winget uninstall --id $browser --accept-source-agreements --accept-package-agreements --silent -e
                }
                if (Get-Command choco -ErrorAction SilentlyContinue) {
                    choco uninstall $browser -y
                }
            } catch {}
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
    } catch {
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
    } catch {
        Write-Log "Failed to set Chrome browser policies: $_" 'WARN'
    }

    # Deploy Firefox policies.json for telemetry, homepage, uBlock Origin, default browser, bookmarks bar, and translation
    try {
        $ffPath = $null
        if (Test-Path 'C:\Program Files\Mozilla Firefox') {
            $ffPath = 'C:\Program Files\Mozilla Firefox'
        } elseif (Test-Path 'C:\Program Files (x86)\Mozilla Firefox') {
            $ffPath = 'C:\Program Files (x86)\Mozilla Firefox'
        }
        if ($ffPath) {
            $distPath = Join-Path $ffPath 'distribution'
            if (-not (Test-Path $distPath)) { New-Item -Path $distPath -ItemType Directory -Force | Out-Null }
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
    "DefaultBrowser": true,
    "BookmarksToolbar": true,
    "OfferToTranslate": false
  }
}
"@
            $policyPath = Join-Path $distPath 'policies.json'
            $policyJson | Set-Content -Path $policyPath -Encoding UTF8
            Write-Log "Firefox policies.json deployed for telemetry, homepage, uBlock Origin, default browser, bookmarks bar, and translation." 'INFO'
        } else {
            Write-Log "Could not find Firefox installation path for policies.json deployment." 'WARN'
        }
    } catch {
        Write-Log "Failed to deploy Firefox policies.json: $_" 'WARN'
    }

    # Attempt to set Firefox as default browser (Windows 10 only, Windows 11 requires user interaction)
    try {
        if (Test-Path 'C:\Program Files\Mozilla Firefox\firefox.exe') {
            Start-Process -FilePath "C:\Program Files\Mozilla Firefox\firefox.exe" -ArgumentList "-setDefaultBrowser" -Wait -ErrorAction SilentlyContinue
            Write-Log "Attempted to set Firefox as default browser." 'INFO'
        }
    } catch {
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
        } catch {
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
            $taskPath = $task.Substring(0, $task.LastIndexOf('\')+1)
            $taskName = $task.Split('\')[-1]
            if (Get-ScheduledTask -TaskPath $taskPath -TaskName $taskName -ErrorAction SilentlyContinue) {
                Disable-ScheduledTask -TaskPath $taskPath -TaskName $taskName
                Write-Log "Disabled scheduled task: $task" 'INFO'
            }
        } catch {
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
        } catch {
            Write-Log "Failed to set $($item.Name) in $($item.Path): $_" 'WARN'
        }
    }

    Write-Log "[END] Disable Telemetry" 'INFO'
}


# =====================[ TASK 1: SYSTEM RESTORE PROTECTION ]==========================
function Protect-SystemRestore {
    # [TASK 1] System Restore Protection
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


# =====================[ TASK EXECUTION IN DESIRED ORDER ]==========================
Write-Log "[COORDINATION] Starting inspired tasks from system_maintenance..." 'INFO'
 $taskResults = @{}

# 1. System Restore Protection
$taskResults['Task1_SystemRestoreProtection'] = Invoke-Task 'SystemRestoreProtection' { Protect-SystemRestore }

# 2. Remove Bloatware
$taskResults['Task2_RemoveBloatware'] = Invoke-Task 'RemoveBloatware' { Remove-Bloatware }

# 3. Install Essential Apps
$taskResults['Task3_InstallEssentialApps'] = Invoke-Task 'InstallEssentialApps' { Install-EssentialApps }

# 4. Update All Apps and Packages
$taskResults['Task4_UpdateAllPackages'] = Invoke-Task 'UpdateAllPackages' {
    # [TASK 5] Update all apps and packages
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

# 5. System Inventory
$taskResults['Task5_SystemInventory'] = Invoke-Task 'SystemInventory' { Get-SystemInventory }

# 6. Windows Update Check
$taskResults['Task6_WindowsUpdateCheck'] = Invoke-Task 'WindowsUpdateCheck' {
    # [TASK 7] Windows Update check
    Write-Log "Checking for Windows Updates..." 'INFO'
    try {
        # Try to use PSWindowsUpdate module if available
        if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) {
            try {
                Install-Module -Name PSWindowsUpdate -Force -Scope CurrentUser -ErrorAction Stop
                Write-Log "PSWindowsUpdate module installed." 'INFO'
            } catch {
                Write-Log "Failed to install PSWindowsUpdate module: $_" 'WARN'
            }
        }
        Import-Module PSWindowsUpdate -ErrorAction SilentlyContinue
        if (Get-Command Get-WindowsUpdate -ErrorAction SilentlyContinue) {
            $updates = Get-WindowsUpdate -AcceptAll -Install -AutoReboot -ErrorAction Stop
            if ($updates) {
                Write-Log ("Installed updates: " + ($updates | Select-Object -ExpandProperty Title -ErrorAction SilentlyContinue -Unique | Out-String)) 'INFO'
            } else {
                Write-Log "No new updates were found or installed." 'INFO'
            }
        } else {
            Write-Log "Get-WindowsUpdate command not available. Please update PowerShell or install PSWindowsUpdate." 'WARN'
        }
    } catch {
        Write-Log "Failed to check or install Windows Updates: $_" 'WARN'
    }
}

# 7. Disable Telemetry
$taskResults['Task7_DisableTelemetry'] = Invoke-Task 'DisableTelemetry' { Disable-Telemetry }

# 8. Clean Temp Files
$taskResults['Task8_CleanTempFiles'] = Invoke-Task 'CleanTempFiles' {
    # [TASK 8] Clean temp files
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

# 9. Disk Cleanup
$taskResults['Task9_DiskCleanup'] = Invoke-Task 'DiskCleanup' {
    # [TASK 9] Disk cleanup
    Write-Log "Running disk cleanup..." 'INFO'
    try {
        # Set up the sagerun profile (run once to configure options)
        $cleanmgrSetup = "/sageset:1"
        Start-Process -FilePath "cleanmgr.exe" -ArgumentList $cleanmgrSetup -Wait
        # Run cleanmgr.exe with all options silently
        $cleanmgrArgs = "/sagerun:1"
        Start-Process -FilePath "cleanmgr.exe" -ArgumentList $cleanmgrArgs -Wait
        Write-Log "Disk cleanup completed using cleanmgr.exe." 'INFO'
    } catch {
        Write-Log "Disk cleanup failed: $_" 'WARN'
    }
}

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
# (All tasks are now executed above in the desired order)

# Summary of all tasks
$successCount = ($taskResults.Values | Where-Object { $_ }).Count
$failCount = ($taskResults.Values | Where-Object { -not $_ }).Count
Write-Log "All tasks completed. Success: $successCount, Failed: $failCount" 'INFO'


# === Reporting Section ===
# Save summary report in the same folder as script.bat (repo parent folder)
$batPath = Join-Path $PSScriptRoot "script.bat"
if (Test-Path $batPath) {
    $batDir = Split-Path $batPath -Parent
    $summaryPath = Join-Path $batDir "maintenance_report.txt"
} else {
    $summaryPath = Join-Path $PSScriptRoot "maintenance_report.txt"
}
"Maintenance completed at $(Get-Date -Format 'dd-MM-yyyy HH:mm:ss') on $env:COMPUTERNAME by $env:USERNAME" | Out-File -FilePath $summaryPath -Append
Write-Log "Summary report written to $summaryPath" 'INFO'

# Remove the repo folder (script_mentenanta) after report creation
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
} catch {
    Write-Log "Failed to remove repo folder: $_" 'WARN'
}

# Example: Optionally send report via email or webhook (not implemented)
# ...

Write-Log "Script ended." 'INFO'

# Prompt to close the window if running interactively
if ($Host.Name -eq 'ConsoleHost' -or $Host.Name -like '*Windows*') {
    Write-Host
    Read-Host -Prompt 'Press Enter to close this window...'
}
