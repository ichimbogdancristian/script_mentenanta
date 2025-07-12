
# Heart & Brain: Centralized Task Coordinator
# Remove unused $taskIndex

# Define all tasks in a single array with metadata
$global:ScriptTasks = @(
    @{ Name = 'SystemRestoreProtection'; Function = { Protect-SystemRestore }; Description = 'Enable and checkpoint System Restore' },
    @{ Name = 'SystemInventory'; Function = { Get-SystemInventory }; Description = 'Legacy system inventory' },
    @{ Name = 'RemoveBloatware'; Function = { Remove-Bloatware }; Description = 'Remove bloatware applications' },
    @{ Name = 'InstallEssentialApps'; Function = { Install-EssentialApps }; Description = 'Install essential applications' },
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
    @{ Name = 'DisableTelemetry'; Function = { Disable-Telemetry }; Description = 'Disable telemetry and privacy tweaks' },
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
            $proc = Start-Process -FilePath 'cleanmgr.exe' -ArgumentList $cleanmgrArgs -WindowStyle Hidden -NoNewWindow -Wait -PassThru
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
        $wingetArgs = @('list', '--source', 'winget', '--accept-source-agreements')
        try {
            $proc = Start-Process -FilePath 'winget' -ArgumentList $wingetArgs -WindowStyle Hidden -RedirectStandardOutput $wingetOutput -PassThru
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
            choco list --local-only > (Join-Path $inventoryFolder 'inventory_choco.txt')
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
function Install-EssentialApps {
    Test-AndInstall-Dependencies

    $success = 0
    $fail = 0
    $skipped = 0
    $detailedResults = @()

    foreach ($app in $global:EssentialApps) {
        $installSuccess = $false
        $installMethod = ""
        try {
            # Check if app is already installed (basic check via winget)
            $isInstalled = $false
            if ($app.Winget -and (Get-Command winget -ErrorAction SilentlyContinue)) {
                $wingetList = winget list --id $app.Winget 2>$null
                if ($wingetList -and $wingetList -match $app.Winget) {
                    $isInstalled = $true
                }
            }
            if (-not $isInstalled -and $app.Choco -and (Get-Command choco -ErrorAction SilentlyContinue)) {
                $chocoList = choco list --local-only $app.Choco 2>$null
                if ($chocoList -and $chocoList -match $app.Choco) {
                    $isInstalled = $true
                }
            }
            if (-not $isInstalled) {
                if ($app.Winget -and (Get-Command winget -ErrorAction SilentlyContinue)) {
                    Write-Log "Installing $($app.Name) via winget..." 'INFO'
                    $wingetArgs = @("install", "--id", $app.Winget, "--accept-source-agreements", "--accept-package-agreements", "--silent", "-e")
                    $wingetProc = Start-Process -FilePath "winget" -ArgumentList $wingetArgs -WindowStyle Hidden -Wait -PassThru
                    if ($wingetProc.ExitCode -eq 0) {
                        $installSuccess = $true
                        $installMethod = "winget"
                    } else {
                        Write-Log "$($app.Name) winget install failed with exit code $($wingetProc.ExitCode)" 'WARN'
                    }
                }
                if (-not $installSuccess -and $app.Choco -and (Get-Command choco -ErrorAction SilentlyContinue)) {
                    Write-Log "Installing $($app.Name) via choco..." 'INFO'
                    $chocoArgs = @("install", $app.Choco, "-y", "--no-progress")
                    $chocoProc = Start-Process -FilePath "choco" -ArgumentList $chocoArgs -WindowStyle Hidden -Wait -PassThru
                    if ($chocoProc.ExitCode -eq 0) {
                        $installSuccess = $true
                        $installMethod = "choco"
                    } else {
                        Write-Log "$($app.Name) choco install failed with exit code $($chocoProc.ExitCode)" 'WARN'
                    }
                }
                if ($installSuccess) {
                    Write-Log "Installed: $($app.Name) via $installMethod" 'INFO'
                    $success++
                    $detailedResults += "SUCCESS: $($app.Name) via $installMethod"
                } else {
                    Write-Log "Failed to install $($app.Name) (no available installer succeeded)" 'WARN'
                    $fail++
                    $detailedResults += "FAIL: $($app.Name) (installer failed)"
                }
            } else {
                Write-Log "$($app.Name) already installed." 'INFO'
                $skipped++
                $detailedResults += "SKIP: $($app.Name) already installed"
            }
        } catch {
            Write-Log "Exception during install of $($app.Name): $_" 'ERROR'
            $fail++
            $detailedResults += "FAIL: $($app.Name) (exception)"
        }
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
    }
    catch {
        Write-Log "Error checking for Microsoft Office: $_" 'WARN'
    }
    if (-not $officeInstalled) {
        Write-Log "Microsoft Office not detected. Installing LibreOffice as alternative..." 'INFO'
        $libreSuccess = $false
        try {
            if (Get-Command winget -ErrorAction SilentlyContinue) {
                $libreArgs = @("install", "--id", "TheDocumentFoundation.LibreOffice", "--accept-source-agreements", "--accept-package-agreements", "--silent", "-e")
                $libreProc = Start-Process -FilePath "winget" -ArgumentList $libreArgs -NoNewWindow -WindowStyle Hidden -Wait -PassThru
                if ($libreProc.ExitCode -eq 0) {
                    Write-Log "LibreOffice installed via winget." 'INFO'
                    $libreSuccess = $true
                } else {
                    Write-Log "LibreOffice winget install failed with exit code $($libreProc.ExitCode)" 'WARN'
                }
            }
            if (-not $libreSuccess -and (Get-Command choco -ErrorAction SilentlyContinue)) {
                $chocoLibreArgs = @("install", "libreoffice-fresh", "-y", "--no-progress")
                $chocoLibreProc = Start-Process -FilePath "choco" -ArgumentList $chocoLibreArgs -NoNewWindow -WindowStyle Hidden -Wait -PassThru
                if ($chocoLibreProc.ExitCode -eq 0) {
                    Write-Log "LibreOffice installed via choco." 'INFO'
                    $libreSuccess = $true
                } else {
                    Write-Log "LibreOffice choco install failed with exit code $($chocoLibreProc.ExitCode)" 'WARN'
                }
            }
            if (-not $libreSuccess) {
                Write-Log "No installer found or succeeded for LibreOffice." 'WARN'
            }
        } catch {
            Write-Log "Failed to install LibreOffice: $_" 'WARN'
        }
    } else {
        Write-Log "Microsoft Office detected. Skipping LibreOffice installation." 'INFO'
    }
    Write-Log ("Install Essential Apps summary: Installed: {0}, Failed: {1}, Skipped: {2}" -f $success, $fail, $skipped) 'INFO'
    foreach ($result in $detailedResults) {
        Write-Log $result 'INFO'
    }
    Write-Log "[END] Install Essential Apps" 'INFO'



### [TASK 3] System Inventory (Legacy)
function Get-SystemInventory {
    Write-Log "[START] System Inventory (legacy)" 'INFO'
    $inventoryPath = Join-Path $global:TempFolder 'inventory.txt'
    Get-ComputerInfo | Out-File $inventoryPath
    Write-Log "System inventory saved to $inventoryPath" 'INFO'
    Write-Log "[END] System Inventory (legacy)" 'INFO'
}


### [TASK 4] Disable Telemetry
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

    # Deploy Firefox policies.json for telemetry, homepage, uBlock Origin, default browser (from external file if present)
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
            $externalPolicyPath = Join-Path $PSScriptRoot 'firefox_policies.json'
            if (Test-Path $externalPolicyPath) {
                Copy-Item -Path $externalPolicyPath -Destination (Join-Path $distPath 'policies.json') -Force
                Write-Log "Firefox policies.json copied from firefox_policies.json and deployed." 'INFO'
                Remove-Item -Path $externalPolicyPath -Force
                Write-Log "firefox_policies.json removed from script folder." 'INFO'
            } else {
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


### [TASK 5] System Restore Protection
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


### [MAIN TASK EXECUTION IN TIMELINE ORDER]

# Run all tasks using the coordinator
Use-AllScriptTasks




### [POST-TASK 1] Ensure script is running as Administrator
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Warning "This script must be run as Administrator. Exiting."
    exit 1
}




### [POST-TASK 2] Built-in Maintenance Tasks
### (All tasks are now executed above in the desired order)

### [POST-TASK 3] Enhanced Task Results Summary
    $successCount = ($taskResults.Values | Where-Object { $_ }).Count
    $failCount = ($taskResults.Values | Where-Object { -not $_ }).Count
    $totalCount = $taskResults.Count
    $taskDetails = $taskResults.GetEnumerator() | ForEach-Object {
        $status = if ($_.Value) { 'SUCCESS' } else { 'FAIL' }
        "- $($_.Key): $status"
    }
Write-Log ("All tasks completed. Total: {0}, Success: {1}, Failed: {2}" -f $totalCount, $successCount, $failCount) 'INFO'
foreach ($detail in $taskDetails) { Write-Log $detail 'INFO' }

### [POST-TASK 4] Enhanced Reporting Section
# Save summary report in the same folder as script.bat (repo parent folder)
$batPath = Join-Path $PSScriptRoot "script.bat"
if (Test-Path $batPath) {
    $batDir = Split-Path $batPath -Parent
    $summaryPath = Join-Path $batDir "maintenance_report.txt"
} else {
    $summaryPath = Join-Path $PSScriptRoot "maintenance_report.txt"
}
$summaryLines = @()
$summaryLines += "Maintenance completed at $(Get-Date -Format 'dd-MM-yyyy HH:mm:ss') on $env:COMPUTERNAME by $env:USERNAME."
$summaryLines += "Total tasks: $totalCount, Success: $successCount, Failed: $failCount"
$summaryLines += "Task breakdown:"
$summaryLines += $taskDetails
$summaryLines += "---"
$summaryLines | Out-File -FilePath $summaryPath -Append
Write-Log "Summary report written to $summaryPath" 'INFO'

### [POST-TASK 5] Remove the repo folder (script_mentenanta) after report creation
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

### [POST-TASK 6] Example: Optionally send report via email or webhook (not implemented)
### ...

Write-Log "Script ended." 'INFO'

### [POST-TASK 7] Prompt to close the window if running interactively
if ($Host.Name -eq 'ConsoleHost' -or $Host.Name -like '*Windows*') {
    Write-Host
    Read-Host -Prompt 'Press Enter to close this window...'
}
