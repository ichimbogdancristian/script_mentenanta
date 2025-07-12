# Heart & Brain: Centralized Task Coordinator
$ScriptDescription = @(
    # [TASK 1] System Restore Protection
    @{ Name = 'SystemRestoreProtection'; Function = { Protect-SystemRestore }; Description = 'Enable and checkpoint System Restore' },
    # [TASK 2] System Inventory (Legacy)
    @{ Name = 'SystemInventory'; Function = { Get-SystemInventory }; Description = 'Legacy system inventory' },
    # [TASK 3] Remove Bloatware
    @{ Name = 'RemoveBloatware'; Function = { Remove-Bloatware }; Description = 'Remove bloatware applications' },
    # [TASK 4] Install Essential Apps
    @{ Name = 'InstallEssentialApps'; Function = { Install-EssentialApps }; Description = 'Install essential applications' },
    # [TASK 5] Update All Packages
    @{ Name = 'UpdateAllPackages'; Function = {
        Write-Log '[START] Update All Apps and Packages' 'INFO'
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            try {
                Write-Log 'Running: winget upgrade --all --silent --accept-source-agreements --accept-package-agreements' 'INFO'
                winget upgrade --all --silent --accept-source-agreements --accept-package-agreements
                Write-Log 'winget upgrade completed.' 'INFO'
            } catch {
                Write-Log "winget upgrade failed: $_" 'WARN'
            }
        } else {
            Write-Log 'winget not found, skipping winget upgrades.' 'WARN'
        }
        if (Get-Command choco -ErrorAction SilentlyContinue) {
            try {
                Write-Log 'Running: choco upgrade all -y' 'INFO'
                choco upgrade all -y
                Write-Log 'choco upgrade completed.' 'INFO'
            } catch {
                Write-Log "choco upgrade failed: $_" 'WARN'
            }
        } else {
            Write-Log 'choco not found, skipping choco upgrades.' 'WARN'
        }
        Write-Log '[END] Update All Apps and Packages' 'INFO'
    }; Description = 'Update all apps and packages' },
    # [TASK 6] Windows Update Check
    @{ Name = 'WindowsUpdateCheck'; Function = {
        Write-Log 'Checking for Windows Updates...' 'INFO'
        try {
            if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) {
                try {
                    Install-Module -Name PSWindowsUpdate -Force -Scope CurrentUser -ErrorAction Stop
                    Write-Log 'PSWindowsUpdate module installed.' 'INFO'
                } catch {
                    Write-Log "Failed to install PSWindowsUpdate module: $_" 'WARN'
                }
            }
            Import-Module PSWindowsUpdate -ErrorAction SilentlyContinue
            if (Get-Command Get-WindowsUpdate -ErrorAction SilentlyContinue) {
                $updates = Get-WindowsUpdate -AcceptAll -Install -ErrorAction Stop
                if ($updates) {
                    Write-Log ("Installed updates: " + ($updates | Select-Object -ExpandProperty Title -ErrorAction SilentlyContinue -Unique | Out-String)) 'INFO'
                } else {
                    Write-Log 'No new updates were found or installed.' 'INFO'
                }
            } else {
                Write-Log 'Get-WindowsUpdate command not available. Please update PowerShell or install PSWindowsUpdate.' 'WARN'
            }
        } catch {
            Write-Log "Failed to check or install Windows Updates: $_" 'WARN'
        }
    }; Description = 'Check and install Windows Updates' },
    # [TASK 7] Disable Telemetry
    @{ Name = 'DisableTelemetry'; Function = { Disable-Telemetry }; Description = 'Disable telemetry and privacy tweaks' },
    # [TASK 8] Clean Temp and Disk
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
                    } catch {
                        Write-Log "Failed to delete $($item.FullName): $_" 'WARN'
                    }
                }
            }
        }
        Write-Log "Deleted $deletedFiles temp files from temp folders." 'INFO'
        try {
            $cleanmgrArgs = '/AUTOCLEAN'
            $proc = Start-Process -FilePath 'cleanmgr.exe' -ArgumentList $cleanmgrArgs -WindowStyle Hidden -Wait -PassThru
            if ($proc.ExitCode -eq 0) {
                Write-Log 'Disk cleanup completed using cleanmgr.exe (silent AUTOCLEAN).' 'INFO'
            } else {
                Write-Log "Disk cleanup process exited with code $($proc.ExitCode)" 'WARN'
            }
        } catch {
            Write-Log "Disk cleanup failed: $_" 'WARN'
        }
        Write-Log '[END] Clean Temp Files and Disk Cleanup (Unattended)' 'INFO'
    }; Description = 'Clean temp files and run disk cleanup' }
)

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
        } catch {
            Write-Log "[COORDINATION] $taskName failed: $_" 'ERROR'
            $global:TaskResults[$taskName] = @{ Success = $false; Duration = 0; Started = $startTime; Ended = (Get-Date) }
        }
    }
    Write-Log '[COORDINATION] All maintenance tasks completed.' 'INFO'
}

# [PRE-TASK 0] Set up log file one folder up from the script's folder
$parentFolder = Split-Path $PSScriptRoot -Parent
$logPath = Join-Path $parentFolder "maintenance.log"
# [PRE-TASK 1] Logging & Task Functions
function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('INFO','WARN','ERROR')][string]$Level = 'INFO',
        [string]$CustomLogPath
    )
    $timestamp = Get-Date -Format 'HH:mm:ss'
    $entry = "[$timestamp] [$Level] $Message"
    $entry | Out-File -FilePath $logPath -Append
    if ($CustomLogPath) {
        $entry | Out-File -FilePath $CustomLogPath -Append
    }
    Write-Host $entry
}

function Invoke-Task {
    param(
        [string]$TaskName,
        [scriptblock]$Action
    )
    $taskLogPath = Join-Path $PSScriptRoot ("task_${TaskName}.log")
    Write-Log "Starting task: $TaskName" 'INFO' $taskLogPath
    try {
        & $Action $taskLogPath
        Write-Log "Task succeeded: $TaskName" 'INFO' $taskLogPath
        return $true
    } catch {
        Write-Log "Task failed: $TaskName. Error: $_" 'ERROR' $taskLogPath
        return $false
    }
}

### [PRE-TASK 2] Extensive System Inventory (Initial)
function Get-ExtensiveSystemInventory {
    param($TaskLogPath)
    Write-Log "[START] Extensive System Inventory" 'INFO' $TaskLogPath
    $inventoryFolder = $PSScriptRoot
    if (-not (Test-Path $inventoryFolder)) { New-Item -ItemType Directory -Path $inventoryFolder -Force | Out-Null }

    Write-Log "[Inventory] Collecting system info..." 'INFO' $TaskLogPath
    try {
        Get-ComputerInfo | Out-File (Join-Path $inventoryFolder 'inventory_system.txt')
        Write-Log "[Inventory] System info collected." 'INFO' $TaskLogPath
    } catch { Write-Log "[Inventory] System info failed: $_" 'WARN' $TaskLogPath }

    Write-Log "[Inventory] Collecting installed Appx apps..." 'INFO' $TaskLogPath
    try {
        Get-AppxPackage -AllUsers | Select-Object Name, PackageFullName | Out-File (Join-Path $inventoryFolder 'inventory_appx.txt')
        Write-Log "[Inventory] Appx apps collected." 'INFO' $TaskLogPath
    } catch { Write-Log "[Inventory] Appx apps failed: $_" 'WARN' $TaskLogPath }

    Write-Log "[Inventory] Collecting installed winget apps (source: winget, timeout: 2min)..." 'INFO' $TaskLogPath
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        $wingetOutput = Join-Path $inventoryFolder 'inventory_winget.txt'
        $wingetArgs = @('list', '--source', 'winget', '--accept-source-agreements', '--silent')
        try {
            $proc = Start-Process -FilePath 'winget' -ArgumentList $wingetArgs -WindowStyle Hidden -RedirectStandardOutput $wingetOutput -Wait -PassThru
            $timeout = 120 # seconds
            $interval = 30 # seconds
            $elapsed = 0
            while (!$proc.HasExited -and $elapsed -lt $timeout) {
                Start-Sleep -Seconds $interval
                $elapsed += $interval
                if (!$proc.HasExited) {
                    Write-Log "[Inventory] Winget list still running... ($elapsed sec elapsed)" 'INFO' $TaskLogPath
                }
            }
            if (!$proc.HasExited) {
                Write-Log "[Inventory] Winget list timed out after $timeout seconds. Attempting to stop process." 'WARN' $TaskLogPath
                try { $proc | Stop-Process -Force } catch {}
            }
            if (Test-Path $wingetOutput -and (Get-Content $wingetOutput | Measure-Object -Line).Lines -gt 0) {
                Write-Log "[Inventory] Winget apps collected." 'INFO' $TaskLogPath
            } else {
                Write-Log "[Inventory] Winget apps output is empty or failed." 'WARN' $TaskLogPath
            }
        } catch {
            Write-Log "[Inventory] Winget apps failed: $_" 'WARN' $TaskLogPath
        }
    }

    Write-Log "[Inventory] Collecting installed choco apps..." 'INFO' $TaskLogPath
    if (Get-Command choco -ErrorAction SilentlyContinue) {
        try {
            choco list --local-only --no-progress -y > (Join-Path $inventoryFolder 'inventory_choco.txt')
            Write-Log "[Inventory] Choco apps collected." 'INFO' $TaskLogPath
        } catch { Write-Log "[Inventory] Choco apps failed: $_" 'WARN' $TaskLogPath }
    }

    Write-Log "[Inventory] Collecting registry uninstall keys..." 'INFO' $TaskLogPath
    $regApps = @()
    $uninstallKeys = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
    )
    try {
        foreach ($key in $uninstallKeys) {
            $regApps += Get-ChildItem $key -ErrorAction SilentlyContinue | ForEach-Object {
                (Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue).DisplayName
            }
        }
        $regApps | Sort-Object -Unique | Out-File (Join-Path $inventoryFolder 'inventory_registry.txt')
        Write-Log "[Inventory] Registry uninstall keys collected." 'INFO' $TaskLogPath
    } catch { Write-Log "[Inventory] Registry uninstall keys failed: $_" 'WARN' $TaskLogPath }

    Write-Log "[Inventory] Collecting services..." 'INFO' $TaskLogPath
    try {
        Get-Service | Select-Object Name, Status, StartType | Out-File (Join-Path $inventoryFolder 'inventory_services.txt')
        Write-Log "[Inventory] Services collected." 'INFO' $TaskLogPath
    } catch { Write-Log "[Inventory] Services failed: $_" 'WARN' $TaskLogPath }

    Write-Log "[Inventory] Collecting scheduled tasks..." 'INFO' $TaskLogPath
    try {
        Get-ScheduledTask | Select-Object TaskName, TaskPath, State | Out-File (Join-Path $inventoryFolder 'inventory_tasks.txt')
        Write-Log "[Inventory] Scheduled tasks collected." 'INFO' $TaskLogPath
    } catch { Write-Log "[Inventory] Scheduled tasks failed: $_" 'WARN' $TaskLogPath }

    Write-Log "[Inventory] Collecting drivers..." 'INFO' $TaskLogPath
    try {
        Get-CimInstance Win32_PnPSignedDriver | Select-Object DeviceName, DriverVersion, Manufacturer | Out-File (Join-Path $inventoryFolder 'inventory_drivers.txt')
        Write-Log "[Inventory] Drivers collected." 'INFO' $TaskLogPath
    } catch { Write-Log "[Inventory] Drivers failed: $_" 'WARN' $TaskLogPath }

    Write-Log "[Inventory] Collecting Windows updates..." 'INFO' $TaskLogPath
    try {
        Get-HotFix | Select-Object Description, HotFixID, InstalledOn | Out-File (Join-Path $inventoryFolder 'inventory_updates.txt')
        Write-Log "[Inventory] Windows updates collected." 'INFO' $TaskLogPath
    } catch { Write-Log "[Inventory] Windows updates failed: $_" 'WARN' $TaskLogPath }

    Write-Log "Extensive system inventory files created in $inventoryFolder" 'INFO' $TaskLogPath
    Write-Log "[END] Extensive System Inventory" 'INFO' $TaskLogPath
}

# [PRE-TASK 3] Run inventory before anything else
Get-ExtensiveSystemInventory

### [MAIN SCRIPT STARTS HERE]


### [TASK 1] Ensure Winget, Choco & NuGet Installed/Updated
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

### Ensure NuGet is installed/updated and NuGet provider is available (unattended)
function Test-NuGet {
    $nugetPath = Join-Path $env:ProgramData "nuget"
    if (-not (Test-Path $nugetPath)) { New-Item -Path $nugetPath -ItemType Directory -Force | Out-Null }
    $nugetExe = Join-Path $nugetPath "nuget.exe"
    $nugetUrl = "https://dist.nuget.org/win-x86-commandline/latest/nuget.exe"
    if (Get-Command nuget -ErrorAction SilentlyContinue) {
        Write-Log "NuGet found. Updating unattended..." 'INFO'
        try {
            Invoke-WebRequest -Uri $nugetUrl -OutFile $nugetExe -UseBasicParsing
            Write-Log "NuGet updated to latest version at $nugetExe." 'INFO'
        } catch {
            Write-Log "Failed to update NuGet: $_" 'ERROR'
        }
        # Add to PATH for current session if not already
        if (-not ($env:PATH -split ';' | Where-Object { $_ -eq $nugetPath })) {
            $env:PATH = "$nugetPath;" + $env:PATH
            Write-Log "NuGet path added to PATH." 'INFO'
        }
    } else {
        Write-Log "NuGet not found. Installing unattended..." 'WARN'
        try {
            Invoke-WebRequest -Uri $nugetUrl -OutFile $nugetExe -UseBasicParsing
            $env:PATH = "$nugetPath;" + $env:PATH
            Write-Log "NuGet installed to $nugetExe and added to PATH." 'INFO'
        } catch {
            Write-Log "Failed to install NuGet: $_" 'ERROR'
        }
    }
    # Ensure NuGet provider for PowerShell is installed (unattended)
    try {
        # Trust PSGallery to suppress prompts
        if (Get-PSRepository -Name 'PSGallery' -ErrorAction SilentlyContinue) {
            Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted
        }
        # Try to install NuGet provider via winget first (avoids interactive prompt)
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            Write-Log "Attempting to install NuGet provider via winget (Microsoft.NuGet)..." 'INFO'
            try {
                $wingetArgs = @("install", "--id", "Microsoft.NuGet", "--accept-source-agreements", "--accept-package-agreements", "--silent", "-e")
                $wingetProc = Start-Process -FilePath "winget" -ArgumentList $wingetArgs -WindowStyle Hidden -Wait -PassThru
                if ($wingetProc.ExitCode -eq 0) {
                    Write-Log "NuGet provider installed via winget." 'INFO'
                } else {
                    Write-Log "NuGet provider winget install failed with exit code $($wingetProc.ExitCode)" 'WARN'
                }
            } catch {
                Write-Log "Exception during NuGet provider install via winget: $_" 'WARN'
            }
        }
        $ProgressPreference = 'SilentlyContinue'
        $provider = Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue
        if (-not $provider -or $provider.Version -lt [version]'2.8.5.201') {
            Write-Log "Installing or updating NuGet provider for PowerShell (unattended)..." 'INFO'
            $null = Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -ForceBootstrap -Scope CurrentUser -Confirm:$false
            Write-Log "NuGet provider for PowerShell installed/updated." 'INFO'
        } else {
            Write-Log "NuGet provider for PowerShell is present and up to date." 'INFO'
        }
    } catch {
        Write-Log "Failed to install or update NuGet provider for PowerShell: $_" 'WARN'
    }
}


Write-Log "Script started. User: $env:USERNAME, Computer: $env:COMPUTERNAME, Script Version: 1.0.0" 'INFO'

# Ensure dependencies before anything else
Test-Winget
Test-Choco
Test-NuGet

### Centralized temp folder and essential/bloatware lists
$global:TempFolder = Join-Path $env:TEMP "ScriptMentenanta_$(Get-Random)"
if (-not (Test-Path $global:TempFolder)) {
    New-Item -ItemType Directory -Path $global:TempFolder -Force | Out-Null
}

### Full bloatware list
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
$essentialAppsListPath = Join-Path $global:TempFolder 'EssentialApps_list.txt'
    $global:EssentialApps | ForEach-Object { $_ | ConvertTo-Json -Compress } | Out-File $essentialAppsListPath -Encoding UTF8

### Load configuration (if exists)
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

### Check Windows version and compatibility
$os = Get-CimInstance Win32_OperatingSystem
$osVersion = $os.Version
$osCaption = $os.Caption
Write-Log "Detected Windows version: $osCaption ($osVersion)" 'INFO'
if ($osVersion -lt '10.0') {
    Write-Log "Unsupported Windows version. Exiting." 'ERROR'
    exit 2
}

### Check for required PowerShell version

if ($PSVersionTable.PSVersion.Major -lt 5) {
    Write-Log "PowerShell 5.1 or higher is required. Exiting." 'ERROR'
    exit 3
}



### [TASK 2] Check and Install Dependencies (called by Install-EssentialApps)
function Test-AndInstall-Dependencies {
    Write-Log "[START] Check And Install Dependencies" 'INFO'
    # Check and install/update winget
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Log "winget not found. Attempting to install winget..." 'WARN'
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

    # Check and install/update choco
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

    # Check and install/update NuGet and provider
    $nugetPath = Join-Path $env:ProgramData "nuget"
    if (-not (Test-Path $nugetPath)) { New-Item -Path $nugetPath -ItemType Directory -Force | Out-Null }
    $nugetExe = Join-Path $nugetPath "nuget.exe"
    $nugetUrl = "https://dist.nuget.org/win-x86-commandline/latest/nuget.exe"
    if (Get-Command nuget -ErrorAction SilentlyContinue) {
        Write-Log "NuGet found. Updating unattended..." 'INFO'
        try {
            Invoke-WebRequest -Uri $nugetUrl -OutFile $nugetExe -UseBasicParsing
            Write-Log "NuGet updated to latest version at $nugetExe." 'INFO'
        } catch {
            Write-Log "Failed to update NuGet: $_" 'ERROR'
        }
        if (-not ($env:PATH -split ';' | Where-Object { $_ -eq $nugetPath })) {
            $env:PATH = "$nugetPath;" + $env:PATH
            Write-Log "NuGet path added to PATH." 'INFO'
        }
    } else {
        Write-Log "NuGet not found. Installing unattended..." 'WARN'
        try {
            Invoke-WebRequest -Uri $nugetUrl -OutFile $nugetExe -UseBasicParsing
            $env:PATH = "$nugetPath;" + $env:PATH
            Write-Log "NuGet installed to $nugetExe and added to PATH." 'INFO'
        } catch {
            Write-Log "Failed to install NuGet: $_" 'ERROR'
        }
    }
    try {
        if (Get-PSRepository -Name 'PSGallery' -ErrorAction SilentlyContinue) {
            Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted
        }
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            Write-Log "Attempting to install NuGet provider via winget (Microsoft.NuGet)..." 'INFO'
            try {
                $wingetArgs = @("install", "--id", "Microsoft.NuGet", "--accept-source-agreements", "--accept-package-agreements", "--silent", "-e")
                $wingetProc = Start-Process -FilePath "winget" -ArgumentList $wingetArgs -WindowStyle Hidden -Wait -PassThru
                if ($wingetProc.ExitCode -eq 0) {
                    Write-Log "NuGet provider installed via winget." 'INFO'
                } else {
                    Write-Log "NuGet provider winget install failed with exit code $($wingetProc.ExitCode)" 'WARN'
                }
            } catch {
                Write-Log "Exception during NuGet provider install via winget: $_" 'WARN'
            }
        }
        $ProgressPreference = 'SilentlyContinue'
        $provider = Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue
        if (-not $provider -or $provider.Version -lt [version]'2.8.5.201') {
            Write-Log "Installing or updating NuGet provider for PowerShell (unattended)..." 'INFO'
            $null = Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -ForceBootstrap -Scope CurrentUser -Confirm:$false
            Write-Log "NuGet provider for PowerShell installed/updated." 'INFO'
        } else {
            Write-Log "NuGet provider for PowerShell is present and up to date." 'INFO'
        }
    } catch {
        Write-Log "Failed to install or update NuGet provider for PowerShell: $_" 'WARN'
    }
    Write-Log "[END] Check And Install Dependencies" 'INFO'
}

### Set up log file one folder up from the script's folder
$parentFolder = Split-Path $PSScriptRoot -Parent
$logPath = Join-Path $parentFolder "maintenance.log"
Write-Log "Script started. User: $env:USERNAME, Computer: $env:COMPUTERNAME, Script Version: 1.0.0" 'INFO'

### Ensure dependencies before anything else
# (Removed incomplete Install-EssentialApps function declaration)
# The duplicate/incomplete Install-EssentialApps function and stray code have been removed.

# [PRE-TASK 3] Run inventory before anything else
Get-ExtensiveSystemInventory

### [MAIN SCRIPT STARTS HERE]


### [TASK 1] Ensure Winget, Choco & NuGet Installed/Updated
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

### Ensure NuGet is installed/updated and NuGet provider is available (unattended)
function Test-NuGet {
    $nugetPath = Join-Path $env:ProgramData "nuget"
    if (-not (Test-Path $nugetPath)) { New-Item -Path $nugetPath -ItemType Directory -Force | Out-Null }
    $nugetExe = Join-Path $nugetPath "nuget.exe"
    $nugetUrl = "https://dist.nuget.org/win-x86-commandline/latest/nuget.exe"
    if (Get-Command nuget -ErrorAction SilentlyContinue) {
        Write-Log "NuGet found. Updating unattended..." 'INFO'
        try {
            Invoke-WebRequest -Uri $nugetUrl -OutFile $nugetExe -UseBasicParsing
            Write-Log "NuGet updated to latest version at $nugetExe." 'INFO'
        } catch {
            Write-Log "Failed to update NuGet: $_" 'ERROR'
        }
        # Add to PATH for current session if not already
        if (-not ($env:PATH -split ';' | Where-Object { $_ -eq $nugetPath })) {
            $env:PATH = "$nugetPath;" + $env:PATH
            Write-Log "NuGet path added to PATH." 'INFO'
        }
    } else {
        Write-Log "NuGet not found. Installing unattended..." 'WARN'
        try {
            Invoke-WebRequest -Uri $nugetUrl -OutFile $nugetExe -UseBasicParsing
            $env:PATH = "$nugetPath;" + $env:PATH
            Write-Log "NuGet installed to $nugetExe and added to PATH." 'INFO'
        } catch {
            Write-Log "Failed to install NuGet: $_" 'ERROR'
        }
    }
    # Ensure NuGet provider for PowerShell is installed (unattended)
    try {
        # Trust PSGallery to suppress prompts
        if (Get-PSRepository -Name 'PSGallery' -ErrorAction SilentlyContinue) {
            Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted
        }
        # Try to install NuGet provider via winget first (avoids interactive prompt)
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            Write-Log "Attempting to install NuGet provider via winget (Microsoft.NuGet)..." 'INFO'
            try {
                $wingetArgs = @("install", "--id", "Microsoft.NuGet", "--accept-source-agreements", "--accept-package-agreements", "--silent", "-e")
                $wingetProc = Start-Process -FilePath "winget" -ArgumentList $wingetArgs -WindowStyle Hidden -Wait -PassThru
                if ($wingetProc.ExitCode -eq 0) {
                    Write-Log "NuGet provider installed via winget." 'INFO'
                } else {
                    Write-Log "NuGet provider winget install failed with exit code $($wingetProc.ExitCode)" 'WARN'
                }
            } catch {
                Write-Log "Exception during NuGet provider install via winget: $_" 'WARN'
            }
        }
        $ProgressPreference = 'SilentlyContinue'
        $provider = Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue
        if (-not $provider -or $provider.Version -lt [version]'2.8.5.201') {
            Write-Log "Installing or updating NuGet provider for PowerShell (unattended)..." 'INFO'
            $null = Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -ForceBootstrap -Scope CurrentUser -Confirm:$false
            Write-Log "NuGet provider for PowerShell installed/updated." 'INFO'
        } else {
            Write-Log "NuGet provider for PowerShell is present and up to date." 'INFO'
        }
    } catch {
        Write-Log "Failed to install or update NuGet provider for PowerShell: $_" 'WARN'
    }
}


Write-Log "Script started. User: $env:USERNAME, Computer: $env:COMPUTERNAME, Script Version: 1.0.0" 'INFO'

# Ensure dependencies before anything else
Test-Winget
Test-Choco
Test-NuGet

### Centralized temp folder and essential/bloatware lists
$global:TempFolder = Join-Path $env:TEMP "ScriptMentenanta_$(Get-Random)"
if (-not (Test-Path $global:TempFolder)) {
    New-Item -ItemType Directory -Path $global:TempFolder -Force | Out-Null
}

### Full bloatware list
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
$essentialAppsListPath = Join-Path $global:TempFolder 'EssentialApps_list.txt'
    $global:EssentialApps | ForEach-Object { $_ | ConvertTo-Json -Compress } | Out-File $essentialAppsListPath -Encoding UTF8

### Load configuration (if exists)
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

### Check Windows version and compatibility
$os = Get-CimInstance Win32_OperatingSystem
$osVersion = $os.Version
$osCaption = $os.Caption
Write-Log "Detected Windows version: $osCaption ($osVersion)" 'INFO'
if ($osVersion -lt '10.0') {
    Write-Log "Unsupported Windows version. Exiting." 'ERROR'
    exit 2
}

### Check for required PowerShell version

if ($PSVersionTable.PSVersion.Major -lt 5) {
    Write-Log "PowerShell 5.1 or higher is required. Exiting." 'ERROR'
    exit 3
}



### [TASK 2] Check and Install Dependencies (called by Install-EssentialApps)
function Test-AndInstall-Dependencies {
    <#
        .SYNOPSIS
        Checks and installs dependencies: winget, choco, NuGet.
        .DESCRIPTION
        Ensures all required package managers are present and updated.
    #>
    Write-Log "[START] Check And Install Dependencies" 'INFO'
    # Check and install/update winget
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Log "winget not found. Attempting to install winget..." 'WARN'
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

    # Check and install/update choco
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

    # Check and install/update NuGet and provider
    $nugetPath = Join-Path $env:ProgramData "nuget"
    if (-not (Test-Path $nugetPath)) { New-Item -Path $nugetPath -ItemType Directory -Force | Out-Null }
    $nugetExe = Join-Path $nugetPath "nuget.exe"
    $nugetUrl = "https://dist.nuget.org/win-x86-commandline/latest/nuget.exe"
    if (Get-Command nuget -ErrorAction SilentlyContinue) {
        Write-Log "NuGet found. Updating unattended..." 'INFO'
        try {
            Invoke-WebRequest -Uri $nugetUrl -OutFile $nugetExe -UseBasicParsing
            Write-Log "NuGet updated to latest version at $nugetExe." 'INFO'
        } catch {
            Write-Log "Failed to update NuGet: $_" 'ERROR'
        }
        if (-not ($env:PATH -split ';' | Where-Object { $_ -eq $nugetPath })) {
            $env:PATH = "$nugetPath;" + $env:PATH
            Write-Log "NuGet path added to PATH." 'INFO'
        }
    } else {
        Write-Log "NuGet not found. Installing unattended..." 'WARN'
        try {
            Invoke-WebRequest -Uri $nugetUrl -OutFile $nugetExe -UseBasicParsing
            $env:PATH = "$nugetPath;" + $env:PATH
            Write-Log "NuGet installed to $nugetExe and added to PATH." 'INFO'
        } catch {
            Write-Log "Failed to install NuGet: $_" 'ERROR'
        }
    }
    try {
        if (Get-PSRepository -Name 'PSGallery' -ErrorAction SilentlyContinue) {
            Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted
        }
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            Write-Log "Attempting to install NuGet provider via winget (Microsoft.NuGet)..." 'INFO'
            try {
                $wingetArgs = @("install", "--id", "Microsoft.NuGet", "--accept-source-agreements", "--accept-package-agreements", "--silent", "-e")
                $wingetProc = Start-Process -FilePath "winget" -ArgumentList $wingetArgs -WindowStyle Hidden -Wait -PassThru
                if ($wingetProc.ExitCode -eq 0) {
                    Write-Log "NuGet provider installed via winget." 'INFO'
                } else {
                    Write-Log "NuGet provider winget install failed with exit code $($wingetProc.ExitCode)" 'WARN'
                }
            } catch {
                Write-Log "Exception during NuGet provider install via winget: $_" 'WARN'
            }
        }
        $ProgressPreference = 'SilentlyContinue'
        $provider = Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue
        if (-not $provider -or $provider.Version -lt [version]'2.8.5.201') {
            Write-Log "Installing or updating NuGet provider for PowerShell (unattended)..." 'INFO'
            $null = Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -ForceBootstrap -Scope CurrentUser -Confirm:$false
            Write-Log "NuGet provider for PowerShell installed/updated." 'INFO'
        } else {
            Write-Log "NuGet provider for PowerShell is present and up to date." 'INFO'
        }
    } catch {
        Write-Log "Failed to install or update NuGet provider for PowerShell: $_" 'WARN'
    }
    Write-Log "[END] Check And Install Dependencies" 'INFO'
}