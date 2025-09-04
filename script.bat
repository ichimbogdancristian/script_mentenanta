@echo off
REM ============================================================================
REM  script_mentenanta - Windows Maintenance Automation Launcher (Refactored)
REM  Purpose: Entry point for all maintenance operations. Handles dependency
REM           installation, scheduled task setup, repo download/update, and
REM           launches PowerShell orchestrator (script.ps1).
REM  Environment: Requires Administrator, Windows 10/11, PowerShell 5.1+.
REM  All actions are logged to console; PowerShell script handles file logging.
REM ============================================================================
SETLOCAL ENABLEDELAYEDEXPANSION

REM -----------------------------------------------------------------------------
REM Basic Environment Setup
REM -----------------------------------------------------------------------------
SET "TASK_NAME=ScriptMentenantaMonthly"
SET "STARTUP_TASK_NAME=ScriptMentenantaStartup"
SET "SCRIPT_PATH=%~f0"
SET "SCRIPT_DIR=%~dp0"

REM Check if this is a restart after PowerShell 7 installation
IF "%1"=="PS7_RESTART" (
    ECHO [%TIME%] [INFO] Script restarted after PowerShell 7 installation.
    GOTO :SKIP_PS7_INSTALL
)

REM Check if this is a restart after script.bat self-update
IF "%1"=="UPDATED" (
    ECHO [%TIME%] [INFO] Script restarted after script.bat self-update.
    ECHO [%TIME%] [INFO] Skipping update check to prevent loops.
    GOTO :SKIP_SELF_UPDATE
)

ECHO [%TIME%] [INFO] Starting maintenance script...
ECHO [%TIME%] [INFO] User: %USERNAME%, Computer: %COMPUTERNAME%

REM -----------------------------------------------------------------------------
REM Admin Privilege Check
REM Relaunches itself with admin rights if not already running as Administrator.
REM -----------------------------------------------------------------------------
NET SESSION >nul 2>&1
IF %ERRORLEVEL% NEQ 0 (
    ECHO [%TIME%] [WARN] Not running as Administrator. Relaunching with admin rights...
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
    ECHO [%TIME%] [ERROR] PowerShell 5.1 or higher is required. Current version: %PS_VERSION%
    ECHO [%TIME%] [ERROR] Please install PowerShell 5.1 or newer and try again.
    pause
    EXIT /B 3
)
ECHO [%TIME%] [INFO] PowerShell version: %PS_VERSION%

REM -----------------------------------------------------------------------------
REM Windows Version Detection - PowerShell 5.1 Compatible
REM -----------------------------------------------------------------------------
FOR /F "tokens=*" %%i IN ('powershell -Command "try { (Get-CimInstance Win32_OperatingSystem).Version } catch { (Get-WmiObject Win32_OperatingSystem).Version }" 2^>nul') DO SET OS_VERSION=%%i
IF "%OS_VERSION%"=="" SET OS_VERSION=Unknown
ECHO [%TIME%] [INFO] Detected Windows version: %OS_VERSION%

REM -----------------------------------------------------------------------------
REM Enhanced Monthly Scheduled Task Setup
REM Ensures a monthly scheduled task is created to run this script as admin.
REM -----------------------------------------------------------------------------
ECHO [%TIME%] [INFO] Checking for monthly scheduled task '%TASK_NAME%'...
schtasks /Query /TN "%TASK_NAME%" >nul 2>&1
IF %ERRORLEVEL% EQU 0 (
    ECHO [%TIME%] [INFO] Monthly scheduled task already exists. Skipping creation.
) ELSE (
    ECHO [%TIME%] [INFO] Monthly scheduled task not found. Creating...
    schtasks /Create ^
        /SC MONTHLY ^
        /MO 1 ^
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
REM Smart Restart Detection - Only restart for pending updates requiring restart
REM Check if Windows requires a restart for PENDING UPDATES, not general maintenance
REM -----------------------------------------------------------------------------
ECHO [%TIME%] [INFO] Checking for pending updates requiring restart...
SET "RESTART_NEEDED=NO"
SET "RESTART_REASON="

REM Check if there are pending updates that require restart (more specific)
powershell -ExecutionPolicy Bypass -Command "try { if (Get-Module -ListAvailable -Name PSWindowsUpdate) { Import-Module PSWindowsUpdate -Force; $updates = Get-WindowsUpdate -MicrosoftUpdate -AcceptAll -IgnoreReboot; $restartRequired = $updates | Where-Object { $_.RebootRequired -eq $true }; if ($restartRequired) { Write-Host 'RESTART_REQUIRED_UPDATES'; exit 1 } else { Write-Host 'NO_RESTART_REQUIRED_UPDATES'; exit 0 } } else { Write-Host 'PSWINDOWSUPDATE_NOT_AVAILABLE'; exit 2 } } catch { Write-Host 'UPDATE_CHECK_FAILED'; exit 3 }"

IF !ERRORLEVEL! EQU 1 (
    ECHO [%TIME%] [INFO] Pending updates require restart for installation.
    SET "RESTART_NEEDED=YES"
    SET "RESTART_REASON=Pending updates require restart"
) ELSE IF !ERRORLEVEL! EQU 0 (
    ECHO [%TIME%] [INFO] No pending updates require restart.
) ELSE IF !ERRORLEVEL! EQU 2 (
    ECHO [%TIME%] [WARN] PSWindowsUpdate module not available. Checking system restart flags...
    
    REM Fallback: Check Windows Update reboot flag only
    REG QUERY "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired" >nul 2>&1
    IF !ERRORLEVEL! EQU 0 (
        ECHO [%TIME%] [INFO] Windows Update restart flag detected.
        SET "RESTART_NEEDED=YES"
        SET "RESTART_REASON=Windows Update restart flag detected"
    )
    
    REM Check Component Based Servicing reboot flag (only for update-related restarts)
    REG QUERY "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending" >nul 2>&1
    IF !ERRORLEVEL! EQU 0 (
        ECHO [%TIME%] [INFO] Component Based Servicing restart pending.
        SET "RESTART_NEEDED=YES"
        SET "RESTART_REASON=Component Based Servicing restart pending"
    )
) ELSE (
    ECHO [%TIME%] [WARN] Update check failed. Skipping restart check.
)

REM Only restart if there are actual updates requiring restart
IF "%RESTART_NEEDED%"=="YES" (
    ECHO [%TIME%] [WARN] System restart is required for pending updates.
    ECHO [%TIME%] [INFO] Reason: %RESTART_REASON%
    ECHO [%TIME%] [INFO] Creating startup task and restarting to complete update installation...
    
    REM Delete any existing startup task first
    schtasks /Delete /TN "%STARTUP_TASK_NAME%" /F >nul 2>&1
    
    REM Create startup task to run 1 minute after user login with admin rights
    schtasks /Create /SC ONLOGON /TN "%STARTUP_TASK_NAME%" /TR "%SCRIPT_PATH%" /RL HIGHEST /RU "%USERNAME%" /DELAY 0001:00 /F
    IF !ERRORLEVEL! EQU 0 (
        ECHO [%TIME%] [INFO] Startup task created successfully. Will run 1 minute after user login.
        ECHO [%TIME%] [INFO] Restarting system to complete pending updates...
        shutdown /r /t 10 /c "System restart required to complete pending Windows Updates"
        ECHO [%TIME%] [INFO] System will restart in 10 seconds to complete updates...
        timeout /t 12 /nobreak >nul
        EXIT /B 0
    ) ELSE (
        ECHO [%TIME%] [ERROR] Failed to create startup task. Continuing without restart...
        ECHO [%TIME%] [WARN] Updates may require manual restart after installation.
    )
) ELSE (
    ECHO [%TIME%] [INFO] No pending updates require restart. Continuing with maintenance script...
)
)

REM -----------------------------------------------------------------------------
REM Dependency Management - Direct Downloads from Official Sources
REM Installation Order: Winget -> PowerShell 7 -> NuGet -> PSGallery -> PSWindowsUpdate -> Chocolatey
REM -----------------------------------------------------------------------------
ECHO [%TIME%] [INFO] Starting dependency installation with optimized order...

REM -----------------------------------------------------------------------------
REM 1. Windows Package Manager (Winget) - Foundation package manager
REM -----------------------------------------------------------------------------
ECHO [%TIME%] [INFO] Installing Windows Package Manager (winget)...
winget --version >nul 2>&1
IF !ERRORLEVEL! NEQ 0 (
    ECHO [%TIME%] [INFO] Winget not found, downloading from official Microsoft source...
    
    REM Download latest App Installer from Microsoft Store
    SET "WINGET_URL=https://github.com/microsoft/winget-cli/releases/latest/download/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"
    SET "WINGET_FILE=!TEMP!\Microsoft.DesktopAppInstaller.msixbundle"
    
    powershell -ExecutionPolicy Bypass -Command "try { $ProgressPreference = 'SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri '!WINGET_URL!' -OutFile '!WINGET_FILE!' -UseBasicParsing; Write-Host '[INFO] Winget downloaded successfully' } catch { Write-Host '[WARN] Winget download failed:' $_.Exception.Message; exit 1 }"
    
    IF !ERRORLEVEL! EQU 0 (
        ECHO [%TIME%] [INFO] Installing Winget package...
        powershell -ExecutionPolicy Bypass -Command "try { if (Get-Command Add-AppxPackage -ErrorAction SilentlyContinue) { Add-AppxPackage -Path '!WINGET_FILE!' -ErrorAction Stop; Write-Host '[INFO] Winget installed successfully' } else { Write-Host '[WARN] Add-AppxPackage not available in this PowerShell version' } } catch { Write-Host '[WARN] Winget installation failed:' $_.Exception.Message; exit 1 }"
        IF !ERRORLEVEL! EQU 0 (
            ECHO [%TIME%] [INFO] Winget installation completed successfully.
        ) ELSE (
            ECHO [%TIME%] [WARN] Winget installation failed, but continuing...
        )
        DEL /F /Q "!WINGET_FILE!" >nul 2>&1
    ) ELSE (
        ECHO [%TIME%] [WARN] Winget download failed, but continuing...
    )
) ELSE (
    ECHO [%TIME%] [INFO] Winget is already available.
)

REM -----------------------------------------------------------------------------
REM 2. PowerShell 7 - Modern PowerShell environment
REM -----------------------------------------------------------------------------
ECHO [%TIME%] [INFO] Installing PowerShell 7...
pwsh.exe -Version >nul 2>&1
IF !ERRORLEVEL! NEQ 0 (
    ECHO [%TIME%] [INFO] PowerShell 7 not found, downloading from official Microsoft source...
    
    REM Set download URL for PowerShell 7.5.2 (no fallback)
    SET "PS7_INSTALLER=%TEMP%\PowerShell-7.5.2.msi"
    
    REM Detect architecture and set appropriate download URL
    IF "%PROCESSOR_ARCHITECTURE%"=="AMD64" (
        SET "PS7_URL=https://github.com/PowerShell/PowerShell/releases/download/v7.5.2/PowerShell-7.5.2-win-x64.msi"
    ) ELSE (
        SET "PS7_URL=https://github.com/PowerShell/PowerShell/releases/download/v7.5.2/PowerShell-7.5.2-win-x86.msi"
    )
    
    REM Download PowerShell 7.5.2
    ECHO [%TIME%] [INFO] Downloading PowerShell 7.5.2...
    powershell -ExecutionPolicy Bypass -Command "try { $ProgressPreference = 'SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri '!PS7_URL!' -OutFile '!PS7_INSTALLER!' -UseBasicParsing; Write-Host '[INFO] PowerShell 7.5.2 downloaded successfully' } catch { Write-Host '[ERROR] PowerShell 7.5.2 download failed:' $_.Exception.Message; exit 1 }"
    
    IF !ERRORLEVEL! EQU 0 (
        ECHO [%TIME%] [INFO] Installing PowerShell 7...
        msiexec /i "!PS7_INSTALLER!" /quiet /norestart
        IF !ERRORLEVEL! EQU 0 (
            ECHO [%TIME%] [INFO] PowerShell 7 installed successfully.
            REM Refresh PATH environment variable for current session
            FOR /F "tokens=2*" %%A IN ('REG QUERY "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" /v PATH') DO SET "PATH=%%B"
            REM Add common PowerShell 7 installation paths to current session
            IF EXIST "%ProgramFiles%\PowerShell\7" SET "PATH=%PATH%;%ProgramFiles%\PowerShell\7"
            IF EXIST "%ProgramFiles(x86)%\PowerShell\7" SET "PATH=%PATH%;%ProgramFiles(x86)%\PowerShell\7"
            ECHO [%TIME%] [INFO] PowerShell 7 installation completed. Restarting script to use new PowerShell...
            REM Restart the script to use newly installed PowerShell 7
            START "" "%~f0" PS7_RESTART
            EXIT /B 0
        ) ELSE (
            ECHO [%TIME%] [WARN] PowerShell 7 installation failed.
        )
        DEL /F /Q "!PS7_INSTALLER!" >nul 2>&1
    )
) ELSE (
    FOR /F "tokens=*" %%i IN ('pwsh.exe -Command "$PSVersionTable.PSVersion.ToString()" 2^>nul') DO SET PS7_VERSION=%%i
    ECHO [%TIME%] [INFO] PowerShell 7 already available: %PS7_VERSION%
)

:SKIP_PS7_INSTALL

REM -----------------------------------------------------------------------------
REM 3. NuGet PackageProvider - Direct download and installation
REM -----------------------------------------------------------------------------
ECHO [%TIME%] [INFO] Installing NuGet PackageProvider...
powershell -ExecutionPolicy Bypass -Command "& { $env:PACKAGEMANAGEMENT_BOOTSTRAP_LOGLEVEL='None'; if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) { try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope AllUsers -Confirm:$false -ErrorAction Stop; Write-Host '[INFO] NuGet PackageProvider installed successfully' } catch { Write-Host '[WARN] Failed to install NuGet PackageProvider:' $_.Exception.Message } } else { Write-Host '[INFO] NuGet PackageProvider already available' } }"

IF !ERRORLEVEL! NEQ 0 (
    ECHO [%TIME%] [WARN] NuGet PackageProvider installation failed, but continuing...
)

REM -----------------------------------------------------------------------------
REM 4. PowerShell Gallery Configuration
REM -----------------------------------------------------------------------------
ECHO [%TIME%] [INFO] Configuring PowerShell Gallery as trusted repository...
powershell -ExecutionPolicy Bypass -Command "try { Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted -ErrorAction Stop; Write-Host '[INFO] PowerShell Gallery configured as trusted' } catch { Write-Host '[WARN] Failed to configure PowerShell Gallery:' $_.Exception.Message }"

REM -----------------------------------------------------------------------------
REM 5. PSWindowsUpdate Module - Download from PowerShell Gallery
REM -----------------------------------------------------------------------------
ECHO [%TIME%] [INFO] Installing PSWindowsUpdate module...
powershell -ExecutionPolicy Bypass -Command "& { if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) { try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Install-Module -Name PSWindowsUpdate -Force -Scope AllUsers -AllowClobber -Confirm:$false -Repository PSGallery; Write-Host '[INFO] PSWindowsUpdate module installed successfully' } catch { Write-Host '[WARN] Failed to install PSWindowsUpdate module:' $_.Exception.Message } } else { Write-Host '[INFO] PSWindowsUpdate module already available' } }"

IF !ERRORLEVEL! NEQ 0 (
    ECHO [%TIME%] [WARN] PSWindowsUpdate module installation failed.
)

REM -----------------------------------------------------------------------------
REM 6. Chocolatey Package Manager - Direct download from official source
REM -----------------------------------------------------------------------------
ECHO [%TIME%] [INFO] Installing Chocolatey package manager...
choco --version >nul 2>&1
IF !ERRORLEVEL! NEQ 0 (
    ECHO [%TIME%] [INFO] Chocolatey not found, downloading from official source...
    
    REM Download and install Chocolatey from official source
    powershell -ExecutionPolicy Bypass -Command "& { try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Set-ExecutionPolicy Bypass -Scope Process -Force; $chocoInstallScript = (New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'); Invoke-Expression $chocoInstallScript; Write-Host '[INFO] Chocolatey installed successfully' } catch { Write-Host '[WARN] Chocolatey installation failed:' $_.Exception.Message } }"
    
    REM Refresh PATH to include Chocolatey
    IF EXIST "%ProgramData%\chocolatey\bin" (
        SET "PATH=%PATH%;%ProgramData%\chocolatey\bin"
        ECHO [%TIME%] [INFO] Chocolatey PATH updated.
    )
) ELSE (
    ECHO [%TIME%] [INFO] Chocolatey is already installed.
)

ECHO [%TIME%] [INFO] Dependency installation phase completed with optimized order.

REM -----------------------------------------------------------------------------
REM System Restart Detection - Simplified
REM -----------------------------------------------------------------------------
ECHO [%TIME%] [INFO] Checking for pending system restarts...
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
        ECHO [%TIME%] [DEBUG] Task name: %STARTUP_TASK_NAME%
        ECHO [%TIME%] [DEBUG] Script path: %SCRIPT_PATH%
        ECHO [%TIME%] [DEBUG] Username: %USERNAME%
        ECHO [%TIME%] [DEBUG] Error level: !ERRORLEVEL!
    )
) ELSE (
    ECHO [%TIME%] [INFO] No pending restart detected. Continuing...
)

REM -----------------------------------------------------------------------------
REM Repository Download - Simplified
REM -----------------------------------------------------------------------------
:SKIP_SELF_UPDATE
SET "REPO_URL=https://github.com/ichimbogdancristian/script_mentenanta/archive/refs/heads/main.zip"
SET "ZIP_FILE=%TEMP%\script_mentenanta.zip"
SET "EXTRACT_FOLDER=script_mentenanta-main"

ECHO [%TIME%] [INFO] Downloading latest repository...
powershell -ExecutionPolicy Bypass -Command "try { $ProgressPreference = 'SilentlyContinue'; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12; $webClient = New-Object System.Net.WebClient; $webClient.DownloadFile('%REPO_URL%', '%ZIP_FILE%'); Write-Host '[INFO] Repository downloaded successfully' } catch { Write-Host '[ERROR] Download failed:' $_.Exception.Message; exit 1 }"

IF !ERRORLEVEL! NEQ 0 (
    ECHO [%TIME%] [ERROR] Failed to download repository. Check internet connection.
    pause
    EXIT /B 2
)

IF NOT EXIST "%ZIP_FILE%" (
    ECHO [%TIME%] [ERROR] Download failed - ZIP file not created.
    pause
    EXIT /B 2
)

REM -----------------------------------------------------------------------------
REM Repository Cleanup - Remove existing folder if it exists
REM -----------------------------------------------------------------------------
ECHO [%TIME%] [INFO] Checking for existing repository folder...
IF EXIST "%SCRIPT_DIR%%EXTRACT_FOLDER%" (
    ECHO [%TIME%] [INFO] Existing repository folder found. Removing for clean extraction...
    RMDIR /S /Q "%SCRIPT_DIR%%EXTRACT_FOLDER%" >nul 2>&1
    IF EXIST "%SCRIPT_DIR%%EXTRACT_FOLDER%" (
        ECHO [%TIME%] [WARN] Could not remove existing folder completely. Attempting forced removal...
        powershell -ExecutionPolicy Bypass -Command "try { if(Test-Path '%SCRIPT_DIR%%EXTRACT_FOLDER%') { Remove-Item -Path '%SCRIPT_DIR%%EXTRACT_FOLDER%' -Recurse -Force; Write-Host '[INFO] Existing folder removed successfully' } } catch { Write-Host '[WARN] Failed to remove existing folder:' $_.Exception.Message }"
    ) ELSE (
        ECHO [%TIME%] [INFO] Existing repository folder removed successfully.
    )
) ELSE (
    ECHO [%TIME%] [INFO] No existing repository folder found. Proceeding with clean extraction.
)

REM -----------------------------------------------------------------------------
REM Repository Extraction - Simplified with PowerShell 5 compatible code
REM -----------------------------------------------------------------------------
ECHO [%TIME%] [INFO] Extracting repository to clean folder...

REM Simple, reliable extraction with PowerShell 5 compatible code
powershell -ExecutionPolicy Bypass -Command "try { Add-Type -AssemblyName System.IO.Compression.FileSystem; if(Test-Path '%ZIP_FILE%') { [System.IO.Compression.ZipFile]::ExtractToDirectory('%ZIP_FILE%', '%~dp0'); Write-Host '[INFO] Repository extracted successfully.' } else { Write-Host '[ERROR] ZIP file not found at %ZIP_FILE%'; exit 1 } } catch { Write-Host '[ERROR] Extraction failed:' $_.Exception.Message; exit 1 }"

IF !ERRORLEVEL! NEQ 0 (
    ECHO [%TIME%] [ERROR] Repository extraction failed.
    ECHO [%TIME%] [ERROR] Please check if the ZIP file is valid and not corrupted.
    pause
    EXIT /B 3
)

REM Clean up ZIP file after extraction
DEL /F /Q "%ZIP_FILE%" >nul 2>&1

REM Verify extraction success
ECHO [%TIME%] [INFO] Verifying repository extraction...
ECHO [%TIME%] [INFO] Looking for folder: %SCRIPT_DIR%%EXTRACT_FOLDER%

REM List all folders in current directory for debugging
DIR "%~dp0" /AD /B

IF EXIST "%SCRIPT_DIR%%EXTRACT_FOLDER%" (
    ECHO [%TIME%] [INFO] ✓ Extraction successful - folder exists.
    DIR "%SCRIPT_DIR%%EXTRACT_FOLDER%" /B
) ELSE (
    ECHO [%TIME%] [ERROR] ✗ Extraction failed - expected folder not found.
    ECHO [%TIME%] [ERROR] Checking for alternative folder names...
    
    REM Check for common GitHub zip extraction patterns
    IF EXIST "%~dp0script_mentenanta-main" (
        ECHO [%TIME%] [INFO] Found: script_mentenanta-main folder
        SET "EXTRACT_FOLDER=script_mentenanta-main"
    ) ELSE IF EXIST "%~dp0script_mentenanta-master" (
        ECHO [%TIME%] [INFO] Found: script_mentenanta-master folder  
        SET "EXTRACT_FOLDER=script_mentenanta-master"
    ) ELSE (
        ECHO [%TIME%] [ERROR] No valid extraction folder found.
        pause
        EXIT /B 3
    )
)

REM -----------------------------------------------------------------------------
REM Self-Update Mechanism - Update script.bat if a newer version is available
REM -----------------------------------------------------------------------------
REM -----------------------------------------------------------------------------
REM Overwrite script.bat if a new version is found
REM -----------------------------------------------------------------------------
SET "NEW_SCRIPT_BAT=%SCRIPT_DIR%%EXTRACT_FOLDER%\script.bat"
SET "CURRENT_SCRIPT_BAT=%SCRIPT_PATH%"

IF EXIST "%NEW_SCRIPT_BAT%" (
    ECHO [%TIME%] [INFO] Found new script.bat in extracted repository. Overwriting current script...
    COPY /Y "%NEW_SCRIPT_BAT%" "%CURRENT_SCRIPT_BAT%" >nul 2>&1
    IF %ERRORLEVEL% EQU 0 (
        ECHO [%TIME%] [INFO] script.bat overwritten successfully.
    ) ELSE (
        ECHO [%TIME%] [ERROR] Failed to overwrite script.bat!
        pause
        EXIT /B 6
    )
) ELSE (
    ECHO [%TIME%] [INFO] No new script.bat found in extracted repository.
)

REM Check if extraction worked
IF NOT EXIST "%SCRIPT_DIR%%EXTRACT_FOLDER%" (
    ECHO [%TIME%] [ERROR] Extraction failed - folder not found: %SCRIPT_DIR%%EXTRACT_FOLDER%
    ECHO [%TIME%] [INFO] Available folders:
    DIR "%SCRIPT_DIR%" /AD /B
    pause
    EXIT /B 3
)

ECHO [%TIME%] [INFO] Repository extracted to clean folder: %SCRIPT_DIR%%EXTRACT_FOLDER%

REM -----------------------------------------------------------------------------
REM PowerShell 7 Detection and Final Verification
REM -----------------------------------------------------------------------------
ECHO [%TIME%] [INFO] Checking PowerShell 7 availability for script execution...
SET "PS7_AVAILABLE=NO"

pwsh.exe -Version >nul 2>&1
IF !ERRORLEVEL! EQU 0 (
    SET "PS7_AVAILABLE=YES"
    FOR /F "tokens=*" %%i IN ('pwsh.exe -Command "$PSVersionTable.PSVersion.ToString()" 2^>nul') DO SET PS7_VERSION=%%i
    ECHO [%TIME%] [INFO] PowerShell 7 found: !PS7_VERSION!
) ELSE (
    ECHO [%TIME%] [WARN] PowerShell 7 not available. Will use Windows PowerShell.
)

REM -----------------------------------------------------------------------------
REM Launch PowerShell Script with Priority for PowerShell 7
REM -----------------------------------------------------------------------------
SET "PS1_PATH=!SCRIPT_DIR!!EXTRACT_FOLDER!\script.ps1"

IF NOT EXIST "!PS1_PATH!" (
    ECHO [%TIME%] [ERROR] PowerShell script not found: !PS1_PATH!
    ECHO [%TIME%] [INFO] Contents of extracted folder:
    DIR "!SCRIPT_DIR!!EXTRACT_FOLDER!" /B
    pause
    EXIT /B 4
)

ECHO [%TIME%] [INFO] Launching PowerShell maintenance script...

REM Test PowerShell availability before launching
powershell.exe -Command "Write-Host 'PowerShell test successful'" >nul 2>&1
IF !ERRORLEVEL! NEQ 0 (
    ECHO [%TIME%] [ERROR] Windows PowerShell is not available or functioning properly.
    pause
    EXIT /B 5
)

IF "!PS7_AVAILABLE!"=="YES" (
    ECHO [%TIME%] [INFO] Using PowerShell 7 environment...
    pwsh.exe -ExecutionPolicy Bypass -File "!PS1_PATH!"
    SET "LAUNCH_RESULT=!ERRORLEVEL!"
) ELSE (
    ECHO [%TIME%] [INFO] Using Windows PowerShell environment...
    powershell.exe -ExecutionPolicy Bypass -File "!PS1_PATH!"
    SET "LAUNCH_RESULT=!ERRORLEVEL!"
)

IF !LAUNCH_RESULT! EQU 0 (
    ECHO [%TIME%] [INFO] PowerShell script execution completed successfully.
) ELSE (
    ECHO [%TIME%] [ERROR] PowerShell script execution failed with error code: !LAUNCH_RESULT!
    pause
)
    ECHO [%TIME%] [INFO] This launcher will close automatically in 10 seconds...
    FOR /L %%i IN (10,-1,1) DO (
        ECHO [%TIME%] [INFO] Closing in %%i seconds...
        timeout /t 1 /nobreak >nul
    )
    ECHO [%TIME%] [INFO] Batch launcher completed successfully. Window will now close.
    EXIT
) ELSE (
    ECHO [%TIME%] [ERROR] Failed to launch PowerShell script.
    ECHO [%TIME%] [ERROR] Please check the PowerShell script path and permissions.
    pause
)

ENDLOCAL
EXIT /B 0