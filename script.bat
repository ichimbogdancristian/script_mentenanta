@echo off
REM ============================================================================
REM  script_mentenanta - Windows Maintenance Automation Launcher (Refactored)
REM  Purpose: Entry point for all maintenance operations. Handles dependency
REM           installation, scheduled task setup, repo download/update, and
REM           launches PowerShell orchestrator (script.ps1).
REM  Environment: Requires Administrator, Windows 10/11, PowerShell 5.1+.
REM  All actions are logged to console and maintenance.log file.
REM ============================================================================
SETLOCAL ENABLEDELAYEDEXPANSION

REM -----------------------------------------------------------------------------
REM Basic Environment Setup and Logging
REM -----------------------------------------------------------------------------
SET "TASK_NAME=ScriptMentenantaMonthly"
SET "STARTUP_TASK_NAME=ScriptMentenantaStartup"
SET "SCRIPT_PATH=%~f0"
SET "SCRIPT_DIR=%~dp0"
SET "LOG_FILE=%SCRIPT_DIR%maintenance.log"

REM Create or append to maintenance.log
ECHO [%DATE% %TIME%] [INFO] ============================================================ >> "%LOG_FILE%"
ECHO [%DATE% %TIME%] [INFO] Starting Windows Maintenance Automation Script >> "%LOG_FILE%"
ECHO [%DATE% %TIME%] [INFO] Script: %SCRIPT_PATH% >> "%LOG_FILE%"
ECHO [%DATE% %TIME%] [INFO] User: %USERNAME%, Computer: %COMPUTERNAME% >> "%LOG_FILE%"
ECHO [%DATE% %TIME%] [INFO] ============================================================ >> "%LOG_FILE%"

REM Function to log both to console and file
CALL :LOG_ENTRY "INFO" "Starting maintenance script..."
CALL :LOG_ENTRY "INFO" "User: %USERNAME%, Computer: %COMPUTERNAME%"

REM Check if this is a restart after PowerShell 7 installation
IF "%1"=="PS7_RESTART" (
    CALL :LOG_ENTRY "INFO" "Script restarted after PowerShell 7 installation."
    GOTO :SKIP_PS7_INSTALL
)

REM -----------------------------------------------------------------------------
REM Admin Privilege Check
REM Relaunches itself with admin rights if not already running as Administrator.
REM -----------------------------------------------------------------------------
NET SESSION >nul 2>&1
IF %ERRORLEVEL% NEQ 0 (
    CALL :LOG_ENTRY "WARN" "Not running as Administrator. Relaunching with admin rights..."
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    EXIT /B 0
)

REM -----------------------------------------------------------------------------
REM PowerShell Version Check
REM Ensures PowerShell 5.1+ is available for all automation features.
REM -----------------------------------------------------------------------------
FOR /F "tokens=*" %%i IN ('powershell -Command "$PSVersionTable.PSVersion.Major" 2^>nul') DO SET PS_VERSION=%%i
IF "%PS_VERSION%"=="" SET PS_VERSION=0
IF %PS_VERSION% LSS 5 (
    CALL :LOG_ENTRY "ERROR" "PowerShell 5.1 or higher is required. Current version: %PS_VERSION%"
    CALL :LOG_ENTRY "ERROR" "Please install PowerShell 5.1 or newer and try again."
    pause
    EXIT /B 3
)
CALL :LOG_ENTRY "INFO" "PowerShell version: %PS_VERSION%"

REM -----------------------------------------------------------------------------
REM Windows Version Detection
REM -----------------------------------------------------------------------------
FOR /F "tokens=*" %%i IN ('powershell -Command "(Get-CimInstance Win32_OperatingSystem).Version" 2^>nul') DO SET OS_VERSION=%%i
IF "%OS_VERSION%"=="" SET OS_VERSION=Unknown
CALL :LOG_ENTRY "INFO" "Detected Windows version: %OS_VERSION%"

REM -----------------------------------------------------------------------------
REM Enhanced Monthly Scheduled Task Setup
REM Ensures a monthly scheduled task is created to run this script as admin.
REM -----------------------------------------------------------------------------
CALL :LOG_ENTRY "INFO" "Checking for monthly scheduled task '%TASK_NAME%'..."
schtasks /Query /TN "%TASK_NAME%" >nul 2>&1
IF %ERRORLEVEL% EQU 0 (
    CALL :LOG_ENTRY "INFO" "Monthly scheduled task already exists. Skipping creation."
) ELSE (
    CALL :LOG_ENTRY "INFO" "Monthly scheduled task not found. Creating..."
    schtasks /Create ^
        /SC MONTHLY ^
        /MO 1 ^
        /D 1 ^
        /TN "%TASK_NAME%" ^
        /TR "cmd.exe /c \"\"%SCRIPT_DIR%script.bat\"\"" ^
        /ST 01:00 ^
        /RL HIGHEST ^
        /RU SYSTEM ^
        /IT ^
        /Z ^
        /F >nul 2>&1
    IF !ERRORLEVEL! EQU 0 (
        ECHO [%TIME%] [INFO] Monthly scheduled task created successfully.
        schtasks /Query /TN "%TASK_NAME%" /V >nul 2>&1
        IF !ERRORLEVEL! EQU 0 (
            ECHO [%TIME%] [INFO] Task verification successful.
            FOR /F "tokens=2 delims=:" %%i IN ('schtasks /Query /TN "%TASK_NAME%" /FO LIST ^| findstr /C:"Next Run Time"') DO (
                ECHO [%TIME%] [INFO] Next scheduled run: %%i
            )
        )
    ) ELSE (
        ECHO [%TIME%] [ERROR] Failed to create monthly scheduled task.
    )
)

REM -----------------------------------------------------------------------------
REM Startup Task Management - Check and Remove if Exists
REM This task should only exist temporarily after a system restart.
REM -----------------------------------------------------------------------------
ECHO [%TIME%] [INFO] Checking startup task '%STARTUP_TASK_NAME%'...
schtasks /Query /TN "%STARTUP_TASK_NAME%" >nul 2>&1
IF !ERRORLEVEL! EQU 0 (
    ECHO [%TIME%] [INFO] Existing startup task found. Removing...
    schtasks /Delete /TN "%STARTUP_TASK_NAME%" /F >nul 2>&1
    IF !ERRORLEVEL! EQU 0 (
        ECHO [%TIME%] [INFO] Startup task removed successfully.
    ) ELSE (
        ECHO [%TIME%] [WARN] Failed to remove startup task, but continuing...
    )
) ELSE (
    ECHO [%TIME%] [INFO] No existing startup task found.
)

REM -----------------------------------------------------------------------------
REM System Restart Detection and Handling
REM Check if Windows requires a restart, create startup task if needed, restart immediately
REM -----------------------------------------------------------------------------
ECHO [%TIME%] [INFO] Checking for pending system restarts...
SET "RESTART_NEEDED=NO"

REM Check Windows Update reboot flag
REG QUERY "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired" >nul 2>&1
IF !ERRORLEVEL! EQU 0 (
    ECHO [%TIME%] [INFO] Windows Update restart required.
    SET "RESTART_NEEDED=YES"
)

REM Check Component Based Servicing reboot flag
REG QUERY "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending" >nul 2>&1
IF !ERRORLEVEL! EQU 0 (
    ECHO [%TIME%] [INFO] Component Based Servicing restart pending.
    SET "RESTART_NEEDED=YES"
)

REM Check pending file operations
REG QUERY "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager" /v PendingFileRenameOperations >nul 2>&1
IF !ERRORLEVEL! EQU 0 (
    ECHO [%TIME%] [INFO] Pending file rename operations detected.
    SET "RESTART_NEEDED=YES"
)

IF "%RESTART_NEEDED%"=="YES" (
    ECHO [%TIME%] [WARN] System restart is required. Creating startup task and restarting...
    REM Delete any existing startup task first
    schtasks /Delete /TN "%STARTUP_TASK_NAME%" /F >nul 2>&1
    REM Create startup task to run 1 minute after user login with admin rights
    schtasks /Create /SC ONLOGON /TN "%STARTUP_TASK_NAME%" /TR "%SCRIPT_PATH%" /RL HIGHEST /RU "%USERNAME%" /DELAY 0001:00 /F
    IF !ERRORLEVEL! EQU 0 (
        ECHO [%TIME%] [INFO] Startup task created successfully. Will run 1 minute after user login.
        ECHO [%TIME%] [INFO] Restarting system immediately...
        shutdown /r /t 5 /c "System restart required for maintenance continuation"
        ECHO [%TIME%] [INFO] System will restart in 5 seconds...
        timeout /t 10 /nobreak >nul
        EXIT /B 0
    ) ELSE (
        ECHO [%TIME%] [ERROR] Failed to create startup task. Continuing without restart...
        ECHO [%TIME%] [DEBUG] Task name: %STARTUP_TASK_NAME%
        ECHO [%TIME%] [DEBUG] Script path: %SCRIPT_PATH%
        ECHO [%TIME%] [DEBUG] Username: %USERNAME%
        ECHO [%TIME%] [DEBUG] Error level: !ERRORLEVEL!
    )
) ELSE (
    ECHO [%TIME%] [INFO] No pending restart detected. No startup task needed. Continuing with script...
)

REM -----------------------------------------------------------------------------
REM Dependency Management - Direct Downloads from Official Sources
REM Installation Order: Winget -> PowerShell 7 -> NuGet -> PSGallery -> PSWindowsUpdate -> Chocolatey
REM -----------------------------------------------------------------------------
CALL :LOG_ENTRY "INFO" "Starting dependency installation with optimized order..."

REM -----------------------------------------------------------------------------
REM 1. Windows Package Manager (Winget) - Foundation package manager
REM -----------------------------------------------------------------------------
CALL :LOG_ENTRY "INFO" "Installing Windows Package Manager (winget) with dependencies..."
winget --version >nul 2>&1
IF !ERRORLEVEL! NEQ 0 (
    CALL :LOG_ENTRY "INFO" "Winget not found, installing dependencies and Winget..."
    
    REM Step 1: Check and install Visual C++ Redistributables (required for Winget)
    CALL :LOG_ENTRY "INFO" "Checking Visual C++ Redistributable 2015-2022 x64..."
    powershell -ExecutionPolicy Bypass -WindowStyle Hidden -Command "try { if (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Classes\Installer\Dependencies\{*}' -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like '*Microsoft Visual C++ 2015-2022 Redistributable*x64*' }) { Write-Host '[INFO] Visual C++ Redistributable x64 is already installed'; exit 0 } else { Write-Host '[INFO] Visual C++ Redistributable x64 not found, installing...'; exit 1 } } catch { Write-Host '[WARN] Registry check failed'; exit 1 }"
    IF !ERRORLEVEL! NEQ 0 (
        SET "VCREDIST_URL=https://aka.ms/vs/17/release/vc_redist.x64.exe"
        SET "VCREDIST_FILE=%TEMP%\vc_redist_x64.exe"
        
        CALL :LOG_ENTRY "INFO" "Downloading Visual C++ Redistributable..."
        powershell -ExecutionPolicy Bypass -WindowStyle Hidden -Command "try { $ProgressPreference = 'SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri '%VCREDIST_URL%' -OutFile '%VCREDIST_FILE%' -UseBasicParsing -TimeoutSec 60; Write-Host '[INFO] VC++ Redistributable downloaded successfully'; exit 0 } catch { Write-Host '[ERROR] VC++ download failed:' $_.Exception.Message; exit 1 }"
        
        IF !ERRORLEVEL! EQU 0 (
            IF EXIST "%VCREDIST_FILE%" (
                CALL :LOG_ENTRY "INFO" "Installing Visual C++ Redistributable silently..."
                START /WAIT "" "%VCREDIST_FILE%" /quiet /norestart
                SET "VCREDIST_EXIT=!ERRORLEVEL!"
                IF !VCREDIST_EXIT! EQU 0 (
                    CALL :LOG_ENTRY "INFO" "Visual C++ Redistributable installation completed successfully."
                ) ELSE (
                    CALL :LOG_ENTRY "WARN" "Visual C++ Redistributable installation returned exit code !VCREDIST_EXIT!, but continuing..."
                )
                DEL /F /Q "%VCREDIST_FILE%" >nul 2>&1
            ) ELSE (
                CALL :LOG_ENTRY "ERROR" "Visual C++ Redistributable file not found after download."
            )
        ) ELSE (
            CALL :LOG_ENTRY "WARN" "Visual C++ Redistributable download failed, but continuing..."
        )
    )
    
    REM Step 2: Check and install Microsoft.UI.Xaml.2.8 framework (required for Winget)
    CALL :LOG_ENTRY "INFO" "Checking Microsoft.UI.Xaml.2.8 framework..."
    powershell -ExecutionPolicy Bypass -WindowStyle Hidden -Command "try { if (Get-AppxPackage -Name '*Microsoft.UI.Xaml*' -ErrorAction SilentlyContinue | Where-Object { $_.Version -ge '2.8' }) { Write-Host '[INFO] Microsoft.UI.Xaml framework is already installed'; exit 0 } else { Write-Host '[INFO] Microsoft.UI.Xaml framework not found, installing...'; exit 1 } } catch { Write-Host '[WARN] AppxPackage check failed'; exit 1 }"
    IF !ERRORLEVEL! NEQ 0 (
        SET "XAML_URL=https://www.nuget.org/api/v2/package/Microsoft.UI.Xaml/2.8.6"
        SET "XAML_FILE=%TEMP%\Microsoft.UI.Xaml.2.8.nupkg"
        
        CALL :LOG_ENTRY "INFO" "Downloading Microsoft.UI.Xaml framework..."
        powershell -ExecutionPolicy Bypass -WindowStyle Hidden -Command "try { $ProgressPreference = 'SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri '%XAML_URL%' -OutFile '%XAML_FILE%' -UseBasicParsing -TimeoutSec 60; Write-Host '[INFO] Microsoft.UI.Xaml framework downloaded successfully'; exit 0 } catch { Write-Host '[ERROR] Microsoft.UI.Xaml download failed:' $_.Exception.Message; exit 1 }"
        
        IF !ERRORLEVEL! EQU 0 (
            IF EXIST "%XAML_FILE%" (
                CALL :LOG_ENTRY "INFO" "Installing Microsoft.UI.Xaml framework..."
                powershell -ExecutionPolicy Bypass -WindowStyle Hidden -Command "try { $tempDir = '%TEMP%\xaml_extract'; if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force }; New-Item -ItemType Directory -Path $tempDir -Force | Out-Null; Expand-Archive -Path '%XAML_FILE%' -DestinationPath $tempDir -Force; $appxPath = Get-ChildItem -Path $tempDir -Recurse -Filter '*.appx' | Where-Object { $_.Name -like '*x64*' } | Select-Object -First 1; if ($appxPath) { Add-AppxPackage -Path $appxPath.FullName -ErrorAction Stop; Write-Host '[INFO] Microsoft.UI.Xaml framework installed successfully'; exit 0 } else { Write-Host '[WARN] Could not find x64 appx package in framework'; exit 1 } } catch { Write-Host '[WARN] Microsoft.UI.Xaml installation failed:' $_.Exception.Message; exit 1 }"
                SET "XAML_EXIT=!ERRORLEVEL!"
                IF !XAML_EXIT! EQU 0 (
                    CALL :LOG_ENTRY "INFO" "Microsoft.UI.Xaml framework installed successfully."
                ) ELSE (
                    CALL :LOG_ENTRY "WARN" "Microsoft.UI.Xaml framework installation had issues, but continuing..."
                )
                DEL /F /Q "%XAML_FILE%" >nul 2>&1
            ) ELSE (
                CALL :LOG_ENTRY "ERROR" "Microsoft.UI.Xaml framework file not found after download."
            )
        ) ELSE (
            CALL :LOG_ENTRY "WARN" "Microsoft.UI.Xaml framework download failed, but continuing..."
        )
    )
    
    REM Step 3: Install Winget (App Installer)
    CALL :LOG_ENTRY "INFO" "Installing Winget (Desktop App Installer)..."
    SET "WINGET_URL=https://github.com/microsoft/winget-cli/releases/latest/download/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"
    SET "WINGET_FILE=%TEMP%\Microsoft.DesktopAppInstaller.msixbundle"
    
    CALL :LOG_ENTRY "INFO" "Downloading Winget installer..."
    powershell -ExecutionPolicy Bypass -WindowStyle Hidden -Command "try { $ProgressPreference = 'SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri '%WINGET_URL%' -OutFile '%WINGET_FILE%' -UseBasicParsing -TimeoutSec 60; Write-Host '[INFO] Winget downloaded successfully'; exit 0 } catch { Write-Host '[ERROR] Winget download failed:' $_.Exception.Message; exit 1 }"
    
    IF !ERRORLEVEL! EQU 0 (
        IF EXIST "%WINGET_FILE%" (
            CALL :LOG_ENTRY "INFO" "Installing Winget package..."
            powershell -ExecutionPolicy Bypass -WindowStyle Hidden -Command "try { Add-AppxPackage -Path '%WINGET_FILE%' -ErrorAction Stop; Write-Host '[INFO] Winget installation completed successfully'; exit 0 } catch { Write-Host '[ERROR] Winget installation failed:' $_.Exception.Message; exit 1 }"
            SET "WINGET_EXIT=!ERRORLEVEL!"
            IF !WINGET_EXIT! EQU 0 (
                CALL :LOG_ENTRY "INFO" "Winget installation completed successfully."
            ) ELSE (
                CALL :LOG_ENTRY "ERROR" "Winget installation failed with exit code !WINGET_EXIT!"
            )
            DEL /F /Q "%WINGET_FILE%" >nul 2>&1
        ) ELSE (
            CALL :LOG_ENTRY "ERROR" "Winget installer file not found after download."
        )
    ) ELSE (
        CALL :LOG_ENTRY "ERROR" "Winget download failed."
    )
    
    REM Refresh PATH and verify Winget installation
    CALL :LOG_ENTRY "INFO" "Refreshing PATH environment and verifying Winget installation..."
    SET "PATH=%PATH%;%ProgramFiles%\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe"
    timeout /t 3 /nobreak >nul
    winget --version >nul 2>&1
    IF !ERRORLEVEL! EQU 0 (
        CALL :LOG_ENTRY "INFO" "Winget is now available and functional."
    ) ELSE (
        CALL :LOG_ENTRY "WARN" "Winget may require system restart to be fully functional."
    )
) ELSE (
    CALL :LOG_ENTRY "INFO" "Winget is already installed and functional."
)

REM -----------------------------------------------------------------------------
REM 2. PowerShell 7 - Modern PowerShell environment
REM -----------------------------------------------------------------------------
CALL :LOG_ENTRY "INFO" "Installing PowerShell 7..."
pwsh.exe -Version >nul 2>&1
IF !ERRORLEVEL! NEQ 0 (
    CALL :LOG_ENTRY "INFO" "PowerShell 7 not found, downloading from official Microsoft source..."
    
    REM Set download URL for PowerShell 7.5.2 (no fallback)
    SET "PS7_INSTALLER=%TEMP%\PowerShell-7.5.2.msi"
    
    REM Detect architecture and set appropriate download URL
    IF "%PROCESSOR_ARCHITECTURE%"=="AMD64" (
        SET "PS7_URL=https://github.com/PowerShell/PowerShell/releases/download/v7.5.2/PowerShell-7.5.2-win-x64.msi"
    ) ELSE (
        SET "PS7_URL=https://github.com/PowerShell/PowerShell/releases/download/v7.5.2/PowerShell-7.5.2-win-x86.msi"
    )
    
    REM Download PowerShell 7.5.2
    CALL :LOG_ENTRY "INFO" "Downloading PowerShell 7.5.2..."
    powershell -ExecutionPolicy Bypass -WindowStyle Hidden -Command "try { $ProgressPreference = 'SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri '%PS7_URL%' -OutFile '%PS7_INSTALLER%' -UseBasicParsing -TimeoutSec 120; Write-Host '[INFO] PowerShell 7.5.2 downloaded successfully'; exit 0 } catch { Write-Host '[ERROR] PowerShell 7.5.2 download failed:' $_.Exception.Message; exit 1 }"
    
    IF !ERRORLEVEL! EQU 0 (
        IF EXIST "%PS7_INSTALLER%" (
            CALL :LOG_ENTRY "INFO" "Installing PowerShell 7 silently..."
            START /WAIT "" msiexec /i "%PS7_INSTALLER%" /quiet /norestart /l*v "%TEMP%\ps7_install.log"
            SET "PS7_EXIT=!ERRORLEVEL!"
            IF !PS7_EXIT! EQU 0 (
                CALL :LOG_ENTRY "INFO" "PowerShell 7 installed successfully."
                REM Refresh PATH environment variable for current session
                FOR /F "tokens=2*" %%A IN ('REG QUERY "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" /v PATH') DO SET "PATH=%%B"
                REM Add common PowerShell 7 installation paths to current session
                IF EXIST "%ProgramFiles%\PowerShell\7" SET "PATH=%PATH%;%ProgramFiles%\PowerShell\7"
                IF EXIST "%ProgramFiles(x86)%\PowerShell\7" SET "PATH=%PATH%;%ProgramFiles(x86)%\PowerShell\7"
                CALL :LOG_ENTRY "INFO" "PowerShell 7 installation completed. Restarting script to use new PowerShell..."
                REM Restart the script to use newly installed PowerShell 7
                START "" "%~f0" PS7_RESTART
                EXIT /B 0
            ) ELSE (
                CALL :LOG_ENTRY "WARN" "PowerShell 7 installation failed with exit code !PS7_EXIT!."
            )
            DEL /F /Q "%PS7_INSTALLER%" >nul 2>&1
        ) ELSE (
            CALL :LOG_ENTRY "ERROR" "PowerShell 7 installer file not found after download."
        )
    ) ELSE (
        CALL :LOG_ENTRY "WARN" "PowerShell 7 download failed, but continuing..."
    )
) ELSE (
    FOR /F "tokens=*" %%i IN ('pwsh.exe -Command "$PSVersionTable.PSVersion.ToString()" 2^>nul') DO SET PS7_VERSION=%%i
    CALL :LOG_ENTRY "INFO" "PowerShell 7 already available: !PS7_VERSION!"
)

:SKIP_PS7_INSTALL

REM -----------------------------------------------------------------------------
REM 3. NuGet PackageProvider - Direct download and installation
REM -----------------------------------------------------------------------------
CALL :LOG_ENTRY "INFO" "Checking NuGet PackageProvider..."
powershell -ExecutionPolicy Bypass -WindowStyle Hidden -Command "$env:PACKAGEMANAGEMENT_BOOTSTRAP_LOGLEVEL='None'; $ProgressPreference = 'SilentlyContinue'; $nugetProvider = Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue; if ($nugetProvider -and $nugetProvider.Version -ge '2.8.5.201') { Write-Host '[INFO] NuGet PackageProvider already available (version: ' + $nugetProvider.Version + ')'; exit 0 } else { try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope AllUsers -Confirm:\$false -ErrorAction Stop | Out-Null; Write-Host '[INFO] NuGet PackageProvider installed successfully'; exit 0 } catch { Write-Host '[WARN] Failed to install NuGet PackageProvider:' \$_.Exception.Message; exit 1 } }"

IF !ERRORLEVEL! NEQ 0 (
    CALL :LOG_ENTRY "WARN" "NuGet PackageProvider installation failed, but continuing..."
) ELSE (
    CALL :LOG_ENTRY "INFO" "NuGet PackageProvider is ready."
)

REM -----------------------------------------------------------------------------
REM 4. PowerShell Gallery Configuration
REM -----------------------------------------------------------------------------
CALL :LOG_ENTRY "INFO" "Checking PowerShell Gallery configuration..."
powershell -ExecutionPolicy Bypass -WindowStyle Hidden -Command "try { $ProgressPreference = 'SilentlyContinue'; $psGallery = Get-PSRepository -Name 'PSGallery' -ErrorAction SilentlyContinue; if ($psGallery -and $psGallery.InstallationPolicy -eq 'Trusted') { Write-Host '[INFO] PowerShell Gallery already configured as trusted'; exit 0 } else { Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted -ErrorAction Stop; Write-Host '[INFO] PowerShell Gallery configured as trusted'; exit 0 } } catch { Write-Host '[WARN] Failed to configure PowerShell Gallery:' $_.Exception.Message; exit 1 }"
IF !ERRORLEVEL! NEQ 0 (
    CALL :LOG_ENTRY "WARN" "PowerShell Gallery configuration failed, but continuing..."
) ELSE (
    CALL :LOG_ENTRY "INFO" "PowerShell Gallery is ready."
)

REM -----------------------------------------------------------------------------
REM 5. PSWindowsUpdate Module - Download from PowerShell Gallery
REM -----------------------------------------------------------------------------
CALL :LOG_ENTRY "INFO" "Checking PSWindowsUpdate module..."
powershell -ExecutionPolicy Bypass -WindowStyle Hidden -Command "$ProgressPreference = 'SilentlyContinue'; $psWindowsUpdate = Get-Module -ListAvailable -Name PSWindowsUpdate -ErrorAction SilentlyContinue; if ($psWindowsUpdate) { Write-Host '[INFO] PSWindowsUpdate module already available (version: ' + $psWindowsUpdate.Version + ')'; exit 0 } else { try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Install-Module -Name PSWindowsUpdate -Force -Scope AllUsers -AllowClobber -Confirm:\$false -Repository PSGallery | Out-Null; Write-Host '[INFO] PSWindowsUpdate module installed successfully'; exit 0 } catch { Write-Host '[WARN] Failed to install PSWindowsUpdate module:' \$_.Exception.Message; exit 1 } }"

IF !ERRORLEVEL! NEQ 0 (
    CALL :LOG_ENTRY "WARN" "PSWindowsUpdate module installation failed, but continuing..."
) ELSE (
    CALL :LOG_ENTRY "INFO" "PSWindowsUpdate module is ready."
)

REM -----------------------------------------------------------------------------
REM 6. Chocolatey Package Manager - Direct download from official source
REM -----------------------------------------------------------------------------
CALL :LOG_ENTRY "INFO" "Installing Chocolatey package manager..."
choco --version >nul 2>&1
IF !ERRORLEVEL! NEQ 0 (
    CALL :LOG_ENTRY "INFO" "Chocolatey not found, downloading from official source..."
    
    REM Download and install Chocolatey from official source (completely silent)
    powershell -ExecutionPolicy Bypass -WindowStyle Hidden -Command "try { $ProgressPreference = 'SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Set-ExecutionPolicy Bypass -Scope Process -Force; $env:ChocolateyInstall = '$env:ProgramData\chocolatey'; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1')); Write-Host '[INFO] Chocolatey installed successfully'; exit 0 } catch { Write-Host '[WARN] Chocolatey installation failed:' \$_.Exception.Message; exit 1 }"
    
    IF !ERRORLEVEL! EQU 0 (
        REM Refresh PATH to include Chocolatey
        IF EXIST "%ProgramData%\chocolatey\bin" (
            SET "PATH=%PATH%;%ProgramData%\chocolatey\bin"
            CALL :LOG_ENTRY "INFO" "Chocolatey PATH updated and installation completed."
        )
    ) ELSE (
        CALL :LOG_ENTRY "WARN" "Chocolatey installation failed, but continuing..."
    )
) ELSE (
    CALL :LOG_ENTRY "INFO" "Chocolatey is already installed."
)

REM -----------------------------------------------------------------------------
REM 7. PowerShellGet and PackageManagement - Latest Versions
REM -----------------------------------------------------------------------------
CALL :LOG_ENTRY "INFO" "Checking PowerShellGet and PackageManagement modules..."
powershell -ExecutionPolicy Bypass -WindowStyle Hidden -Command "try { $ProgressPreference = 'SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; $psGet = Get-Module -ListAvailable PowerShellGet | Sort-Object Version -Descending | Select-Object -First 1; if ($psGet -and $psGet.Version -ge '2.2.5') { Write-Host '[INFO] PowerShellGet is up to date (version: ' + $psGet.Version + ')' } else { Write-Host '[INFO] Updating PowerShellGet module...'; Install-Module -Name PowerShellGet -Force -Scope AllUsers -AllowClobber -Confirm:\$false -Repository PSGallery | Out-Null; Write-Host '[INFO] PowerShellGet updated successfully' } } catch { Write-Host '[WARN] PowerShellGet update failed:' \$_.Exception.Message }"

powershell -ExecutionPolicy Bypass -WindowStyle Hidden -Command "try { $ProgressPreference = 'SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; $pkgMgmt = Get-Module -ListAvailable PackageManagement | Sort-Object Version -Descending | Select-Object -First 1; if ($pkgMgmt -and $pkgMgmt.Version -ge '1.4.8') { Write-Host '[INFO] PackageManagement is up to date (version: ' + $pkgMgmt.Version + ')' } else { Write-Host '[INFO] Updating PackageManagement module...'; Install-Module -Name PackageManagement -Force -Scope AllUsers -AllowClobber -Confirm:\$false -Repository PSGallery | Out-Null; Write-Host '[INFO] PackageManagement updated successfully' } } catch { Write-Host '[WARN] PackageManagement update failed:' \$_.Exception.Message }"

REM -----------------------------------------------------------------------------
REM 8. Microsoft Visual C++ Redistributables - Essential for many applications
REM -----------------------------------------------------------------------------
CALL :LOG_ENTRY "INFO" "Checking Microsoft Visual C++ Redistributables..."
powershell -ExecutionPolicy Bypass -WindowStyle Hidden -Command "try { $ProgressPreference = 'SilentlyContinue'; $vcInstalled = @(); $regPaths = @('HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64', 'HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x86', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\VisualStudio\14.0\VC\Runtimes\x64', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\VisualStudio\14.0\VC\Runtimes\x86'); foreach ($path in $regPaths) { if (Test-Path $path) { $vcInstalled += $path } }; if ($vcInstalled.Count -ge 2) { Write-Host '[INFO] Microsoft Visual C++ Redistributables already installed' } else { Write-Host '[INFO] Installing Microsoft Visual C++ Redistributables...'; if (Get-Command winget -ErrorAction SilentlyContinue) { Start-Process winget -ArgumentList 'install --id Microsoft.VCRedist.2015+.x64 --silent --accept-package-agreements --accept-source-agreements' -WindowStyle Hidden -Wait 2>$null; Start-Process winget -ArgumentList 'install --id Microsoft.VCRedist.2015+.x86 --silent --accept-package-agreements --accept-source-agreements' -WindowStyle Hidden -Wait 2>$null; Write-Host '[INFO] Visual C++ Redistributables installed via winget' } else { Write-Host '[WARN] Winget not available for VC++ Redistributables installation' } } } catch { Write-Host '[WARN] VC++ Redistributables check failed:' \$_.Exception.Message }"

REM -----------------------------------------------------------------------------
REM 9. Git - For better repository management and version control
REM -----------------------------------------------------------------------------
CALL :LOG_ENTRY "INFO" "Installing Git..."
git --version >nul 2>&1
IF !ERRORLEVEL! NEQ 0 (
    powershell -ExecutionPolicy Bypass -WindowStyle Hidden -Command "try { $ProgressPreference = 'SilentlyContinue'; if (Get-Command winget -ErrorAction SilentlyContinue) { Start-Process winget -ArgumentList 'install --id Git.Git --silent --accept-package-agreements --accept-source-agreements' -WindowStyle Hidden -Wait; Write-Host '[INFO] Git installed successfully via winget' } elseif (Get-Command choco -ErrorAction SilentlyContinue) { Start-Process choco -ArgumentList 'install git -y --no-progress' -WindowStyle Hidden -Wait; Write-Host '[INFO] Git installed successfully via chocolatey' } else { Write-Host '[WARN] No package manager available for Git installation' } } catch { Write-Host '[WARN] Git installation failed:' \$_.Exception.Message }"
    
    REM Update PATH for Git
    IF EXIST "%ProgramFiles%\Git\bin" SET "PATH=%PATH%;%ProgramFiles%\Git\bin"
    IF EXIST "%ProgramFiles(x86)%\Git\bin" SET "PATH=%PATH%;%ProgramFiles(x86)%\Git\bin"
) ELSE (
    CALL :LOG_ENTRY "INFO" "Git is already installed."
)

REM -----------------------------------------------------------------------------
REM 10. .NET Framework 4.8 - Required for many PowerShell modules and applications
REM -----------------------------------------------------------------------------
CALL :LOG_ENTRY "INFO" "Checking .NET Framework 4.8..."
powershell -ExecutionPolicy Bypass -WindowStyle Hidden -Command "try { $ProgressPreference = 'SilentlyContinue'; $netVersion = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full\' -Name Release -ErrorAction SilentlyContinue).Release; if ($netVersion -ge 528040) { Write-Host '[INFO] .NET Framework 4.8 or higher already installed' } else { if (Get-Command winget -ErrorAction SilentlyContinue) { Start-Process winget -ArgumentList 'install --id Microsoft.DotNet.Framework.DeveloperPack_4 --silent --accept-package-agreements --accept-source-agreements' -WindowStyle Hidden -Wait; Write-Host '[INFO] .NET Framework 4.8 installed via winget' } else { Write-Host '[WARN] .NET Framework 4.8 may need manual installation' } } } catch { Write-Host '[WARN] .NET Framework check failed:' \$_.Exception.Message }"

REM -----------------------------------------------------------------------------
REM 11. Additional PowerShell Modules for Enhanced Functionality
REM -----------------------------------------------------------------------------
CALL :LOG_ENTRY "INFO" "Checking additional PowerShell modules..."
powershell -ExecutionPolicy Bypass -WindowStyle Hidden -Command "try { $ProgressPreference = 'SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; $modules = @('DISM', 'PnpDevice', 'WindowsSearch'); foreach ($module in $modules) { if (-not (Get-Module -ListAvailable -Name $module -ErrorAction SilentlyContinue)) { try { Import-Module $module -ErrorAction Stop | Out-Null; Write-Host \"[INFO] Module $module verified and available\" } catch { Write-Host \"[INFO] Module $module not available - will be loaded when needed\" } } else { Write-Host \"[INFO] Module $module already available\" } } } catch { Write-Host '[WARN] Module check failed:' \$_.Exception.Message }"

REM -----------------------------------------------------------------------------
REM 12. Windows Features - Enable required features
REM -----------------------------------------------------------------------------
CALL :LOG_ENTRY "INFO" "Checking Windows features..."
powershell -ExecutionPolicy Bypass -WindowStyle Hidden -Command "try { $ProgressPreference = 'SilentlyContinue'; $features = @('NetFx3', 'MSMQ-Container', 'IIS-ManagementConsole'); foreach ($feature in $features) { $featureState = Get-WindowsOptionalFeature -Online -FeatureName $feature -ErrorAction SilentlyContinue; if ($featureState) { if ($featureState.State -eq 'Enabled') { Write-Host \"[INFO] Windows feature $feature already enabled\" } elseif ($featureState.State -eq 'Disabled') { Write-Host \"[INFO] Enabling Windows feature: $feature\"; Enable-WindowsOptionalFeature -Online -FeatureName $feature -All -NoRestart -ErrorAction SilentlyContinue | Out-Null; Write-Host \"[INFO] Windows feature $feature enabled successfully\" } } else { Write-Host \"[INFO] Windows feature $feature not available on this system\" } } } catch { Write-Host '[INFO] Windows features check completed' }"

REM -----------------------------------------------------------------------------
REM 13. System Performance Optimizations
REM -----------------------------------------------------------------------------
CALL :LOG_ENTRY "INFO" "Checking system performance settings..."
powershell -ExecutionPolicy Bypass -WindowStyle Hidden -Command "try { $ProgressPreference = 'SilentlyContinue'; $services = @('Themes', 'UxSms'); foreach ($service in $services) { $svc = Get-Service -Name $service -ErrorAction SilentlyContinue; if ($svc) { if ($svc.StartType -eq 'Automatic') { Write-Host \"[INFO] Service $service already set to Automatic\" } else { Set-Service -Name $service -StartupType Automatic -ErrorAction SilentlyContinue | Out-Null; Write-Host \"[INFO] Service $service set to Automatic startup\" } } else { Write-Host \"[INFO] Service $service not found on this system\" } }; Write-Host '[INFO] System services optimization completed' } catch { Write-Host '[INFO] Service optimization completed with some warnings' }"

CALL :LOG_ENTRY "INFO" "Dependency installation phase completed with comprehensive coverage."

REM -----------------------------------------------------------------------------
REM System Restart Detection - Simplified
REM -----------------------------------------------------------------------------
CALL :LOG_ENTRY "INFO" "Checking for pending system restarts..."
SET "RESTART_NEEDED=NO"

REM Check Windows Update reboot flag
REG QUERY "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired" >nul 2>&1
IF !ERRORLEVEL! EQU 0 SET "RESTART_NEEDED=YES"

REM Check Component Based Servicing reboot flag
REG QUERY "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending" >nul 2>&1
IF !ERRORLEVEL! EQU 0 SET "RESTART_NEEDED=YES"

REM Check pending file operations
REG QUERY "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager" /v PendingFileRenameOperations >nul 2>&1
IF !ERRORLEVEL! EQU 0 SET "RESTART_NEEDED=YES"

IF "%RESTART_NEEDED%"=="YES" (
    ECHO [%TIME%] [WARN] System restart is pending. Creating startup task...
    schtasks /Query /TN "%STARTUP_TASK_NAME%" >nul 2>&1
    IF %ERRORLEVEL% EQU 0 (
        schtasks /Delete /TN "%STARTUP_TASK_NAME%" /F >nul 2>&1
    )
    schtasks /Create /SC ONLOGON /TN "%STARTUP_TASK_NAME%" /TR "%SCRIPT_PATH%" /RL HIGHEST /RU "%USERNAME%" /DELAY 0001:00 /F
    IF !ERRORLEVEL! EQU 0 (
        ECHO [%TIME%] [INFO] Startup task created. Restarting system in 15 seconds...
        ECHO [%TIME%] [INFO] Press Ctrl+C to cancel restart.
        timeout /t 15
        shutdown /r /t 5 /c "System restart required for maintenance continuation"
        EXIT /B 0
    ) ELSE (
        ECHO [%TIME%] [WARN] Failed to create startup task. Continuing without restart...
REM Check pending file operations
REG QUERY "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager" /v PendingFileRenameOperations >nul 2>&1
IF !ERRORLEVEL! EQU 0 SET "RESTART_NEEDED=YES"

IF "%RESTART_NEEDED%"=="YES" (
    CALL :LOG_ENTRY "WARN" "System restart is pending. Creating startup task..."
    schtasks /Query /TN "%STARTUP_TASK_NAME%" >nul 2>&1
    IF %ERRORLEVEL% EQU 0 (
        schtasks /Delete /TN "%STARTUP_TASK_NAME%" /F >nul 2>&1
    )
    schtasks /Create /SC ONLOGON /TN "%STARTUP_TASK_NAME%" /TR "%SCRIPT_PATH%" /RL HIGHEST /RU "%USERNAME%" /DELAY 0001:00 /F
    IF !ERRORLEVEL! EQU 0 (
        CALL :LOG_ENTRY "INFO" "Startup task created. Restarting system in 15 seconds..."
        CALL :LOG_ENTRY "INFO" "Press Ctrl+C to cancel restart."
        timeout /t 15
        shutdown /r /t 5 /c "System restart required for maintenance continuation"
        EXIT /B 0
    ) ELSE (
        CALL :LOG_ENTRY "WARN" "Failed to create startup task. Continuing without restart..."
        CALL :LOG_ENTRY "DEBUG" "Task name: %STARTUP_TASK_NAME%"
        CALL :LOG_ENTRY "DEBUG" "Script path: %SCRIPT_PATH%"
        CALL :LOG_ENTRY "DEBUG" "Username: %USERNAME%"
        CALL :LOG_ENTRY "DEBUG" "Error level: !ERRORLEVEL!"
    )
) ELSE (
    CALL :LOG_ENTRY "INFO" "No pending restart detected. Continuing..."
)

REM -----------------------------------------------------------------------------
REM Repository Download - Simplified
REM -----------------------------------------------------------------------------
SET "REPO_URL=https://github.com/ichimbogdancristian/script_mentenanta/archive/refs/heads/main.zip"
SET "ZIP_FILE=%TEMP%\script_mentenanta.zip"
SET "EXTRACT_FOLDER=script_mentenanta-main"

CALL :LOG_ENTRY "INFO" "Downloading latest repository..."
powershell -ExecutionPolicy Bypass -WindowStyle Hidden -Command "try { $ProgressPreference = 'SilentlyContinue'; Invoke-WebRequest -Uri '%REPO_URL%' -OutFile '%ZIP_FILE%' -UseBasicParsing -TimeoutSec 60; Write-Host '[INFO] Repository downloaded successfully'; exit 0 } catch { Write-Host '[ERROR] Download failed:' $_.Exception.Message; exit 1 }"

IF !ERRORLEVEL! NEQ 0 (
    CALL :LOG_ENTRY "ERROR" "Failed to download repository. Check internet connection."
    pause
    EXIT /B 2
)

IF NOT EXIST "%ZIP_FILE%" (
    CALL :LOG_ENTRY "ERROR" "Download failed - ZIP file not created."
    pause
    EXIT /B 2
)

REM -----------------------------------------------------------------------------
REM Repository Cleanup - Remove existing folder if it exists
REM -----------------------------------------------------------------------------
CALL :LOG_ENTRY "INFO" "Checking for existing repository folder..."
IF EXIST "%SCRIPT_DIR%%EXTRACT_FOLDER%" (
    CALL :LOG_ENTRY "INFO" "Existing repository folder found. Removing for clean extraction..."
    RMDIR /S /Q "%SCRIPT_DIR%%EXTRACT_FOLDER%" >nul 2>&1
    IF EXIST "%SCRIPT_DIR%%EXTRACT_FOLDER%" (
        CALL :LOG_ENTRY "WARN" "Could not remove existing folder completely. Attempting forced removal..."
        powershell -ExecutionPolicy Bypass -WindowStyle Hidden -Command "try { Remove-Item -Path '%SCRIPT_DIR%%EXTRACT_FOLDER%' -Recurse -Force -ErrorAction Stop; Write-Host '[INFO] Existing folder removed successfully'; exit 0 } catch { Write-Host '[WARN] Failed to remove existing folder:' $_.Exception.Message; exit 1 }"
    ) ELSE (
        CALL :LOG_ENTRY "INFO" "Existing repository folder removed successfully."
    )
) ELSE (
    CALL :LOG_ENTRY "INFO" "No existing repository folder found. Proceeding with clean extraction."
)

REM -----------------------------------------------------------------------------
REM Repository Extraction - Using PowerShell (More Reliable)
REM -----------------------------------------------------------------------------
CALL :LOG_ENTRY "INFO" "Extracting repository to clean folder..."
powershell -ExecutionPolicy Bypass -WindowStyle Hidden -Command "try { Add-Type -AssemblyName System.IO.Compression.FileSystem; [System.IO.Compression.ZipFile]::ExtractToDirectory('%ZIP_FILE%', '%SCRIPT_DIR%'); Write-Host '[INFO] Repository extracted successfully'; exit 0 } catch { Write-Host '[ERROR] Extraction failed:' $_.Exception.Message; exit 1 }"

IF !ERRORLEVEL! NEQ 0 (
    CALL :LOG_ENTRY "ERROR" "Failed to extract repository."
    pause
    EXIT /B 3
)

REM Clean up ZIP file
DEL /F /Q "%ZIP_FILE%" >nul 2>&1

REM Check if extraction worked
IF NOT EXIST "%SCRIPT_DIR%%EXTRACT_FOLDER%" (
    ECHO [%TIME%] [ERROR] Extraction failed - folder not found: %SCRIPT_DIR%%EXTRACT_FOLDER%
    ECHO [%TIME%] [INFO] Available folders:
    DIR "%SCRIPT_DIR%" /AD /B
    pause
    EXIT /B 3
)

CALL :LOG_ENTRY "INFO" "Repository extracted to clean folder: %SCRIPT_DIR%%EXTRACT_FOLDER%"

REM -----------------------------------------------------------------------------
REM PowerShell 7 Detection and Final Verification
REM -----------------------------------------------------------------------------
CALL :LOG_ENTRY "INFO" "Performing comprehensive dependency validation..."

REM Check PowerShell 7 availability
CALL :LOG_ENTRY "INFO" "Checking PowerShell 7 availability for script execution..."
SET "PS7_AVAILABLE=NO"

pwsh.exe -Version >nul 2>&1
IF !ERRORLEVEL! EQU 0 (
    SET "PS7_AVAILABLE=YES"
    FOR /F "tokens=*" %%i IN ('pwsh.exe -Command "$PSVersionTable.PSVersion.ToString()" 2^>nul') DO SET PS7_VERSION=%%i
    CALL :LOG_ENTRY "INFO" "PowerShell 7 found: !PS7_VERSION!"
) ELSE (
    CALL :LOG_ENTRY "WARN" "PowerShell 7 not available. Will use Windows PowerShell."
)

REM Check critical dependencies
CALL :LOG_ENTRY "INFO" "Validating critical dependencies..."
SET "DEPENDENCY_WARNINGS=0"

REM Validate Winget
winget --version >nul 2>&1
IF !ERRORLEVEL! EQU 0 (
    CALL :LOG_ENTRY "INFO" "✓ Winget is available"
) ELSE (
    CALL :LOG_ENTRY "WARN" "✗ Winget not available - some installations may fail"
    SET /A DEPENDENCY_WARNINGS+=1
)

REM Validate Chocolatey
choco --version >nul 2>&1
IF !ERRORLEVEL! EQU 0 (
    CALL :LOG_ENTRY "INFO" "✓ Chocolatey is available"
) ELSE (
    CALL :LOG_ENTRY "WARN" "✗ Chocolatey not available - some installations may fail"
    SET /A DEPENDENCY_WARNINGS+=1
)

REM Validate Git
git --version >nul 2>&1
IF !ERRORLEVEL! EQU 0 (
    ECHO [%TIME%] [INFO] ✓ Git is available
) ELSE (
    ECHO [%TIME%] [WARN] ✗ Git not available - repository management limited
    SET /A DEPENDENCY_WARNINGS+=1
)

REM Validate PowerShell modules
powershell -ExecutionPolicy Bypass -Command "try { $modules = @('PSWindowsUpdate', 'PackageManagement', 'PowerShellGet'); $moduleStatus = @(); foreach ($module in $modules) { if (Get-Module -ListAvailable -Name $module -ErrorAction SilentlyContinue) { $moduleStatus += \"[INFO] ✓ Module $module is available\" } else { $moduleStatus += \"[WARN] ✗ Module $module not available\" } }; $moduleStatus | ForEach-Object { Write-Host $_ } } catch { Write-Host '[WARN] Module validation failed' }"

REM Show dependency summary
IF !DEPENDENCY_WARNINGS! GTR 0 (
    ECHO [%TIME%] [WARN] Found !DEPENDENCY_WARNINGS! dependency warnings. Script will use graceful degradation.
) ELSE (
    ECHO [%TIME%] [INFO] ✓ All critical dependencies verified successfully.
)

CALL :LOG_ENTRY "INFO" "Dependency validation completed."

REM -----------------------------------------------------------------------------
REM Launch PowerShell Script with Priority for PowerShell 7
REM -----------------------------------------------------------------------------
SET "PS1_PATH=%SCRIPT_DIR%%EXTRACT_FOLDER%\script.ps1"

IF NOT EXIST "%PS1_PATH%" (
    CALL :LOG_ENTRY "ERROR" "PowerShell script not found: %PS1_PATH%"
    CALL :LOG_ENTRY "INFO" "Contents of extracted folder:"
    DIR "%SCRIPT_DIR%%EXTRACT_FOLDER%" /B
    pause
    EXIT /B 4
)

CALL :LOG_ENTRY "INFO" "Launching PowerShell maintenance script..."

IF "%PS7_AVAILABLE%"=="YES" (
    CALL :LOG_ENTRY "INFO" "Using PowerShell 7 environment..."
    START "Maintenance Script - PowerShell 7" pwsh.exe -ExecutionPolicy Bypass -File "%PS1_PATH%"
    SET "LAUNCH_EXIT=!ERRORLEVEL!"
    IF !LAUNCH_EXIT! NEQ 0 (
        CALL :LOG_ENTRY "ERROR" "PowerShell script failed with error code !LAUNCH_EXIT!"
        pause
        exit /b !LAUNCH_EXIT!
    )
) ELSE (
    CALL :LOG_ENTRY "INFO" "Using Windows PowerShell environment..."
    START "Maintenance Script - Windows PowerShell" powershell.exe -ExecutionPolicy Bypass -File "%PS1_PATH%"
    SET "LAUNCH_EXIT=!ERRORLEVEL!"
    IF !LAUNCH_EXIT! NEQ 0 (
        CALL :LOG_ENTRY "ERROR" "PowerShell script failed with error code !LAUNCH_EXIT!"
        pause
        exit /b !LAUNCH_EXIT!
    )
)

CALL :LOG_ENTRY "INFO" "PowerShell script launched successfully in new window."
CALL :LOG_ENTRY "INFO" "Maintenance operations are now running in the background."
CALL :LOG_ENTRY "INFO" "This launcher will close automatically in 30 seconds..."
FOR /L %%i IN (30,-1,1) DO (
    CALL :LOG_ENTRY "INFO" "Closing in %%i seconds..."
    timeout /t 1 /nobreak >nul
)
CALL :LOG_ENTRY "INFO" "Batch launcher completed successfully. Window will now close."
EXIT /B 0

REM -----------------------------------------------------------------------------
REM Logging Function - Logs to both console and maintenance.log file
REM -----------------------------------------------------------------------------
:LOG_ENTRY
SET "LEVEL=%~1"
SET "MESSAGE=%~2"
ECHO [%TIME%] [%LEVEL%] %MESSAGE%
ECHO [%DATE% %TIME%] [%LEVEL%] %MESSAGE% >> "%LOG_FILE%"
GOTO :EOF

ENDLOCAL
EXIT /B 0