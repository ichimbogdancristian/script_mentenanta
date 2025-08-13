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
REM Windows Version Detection
REM -----------------------------------------------------------------------------
FOR /F "tokens=*" %%i IN ('powershell -Command "(Get-CimInstance Win32_OperatingSystem).Version" 2^>nul') DO SET OS_VERSION=%%i
IF "%OS_VERSION%"=="" SET OS_VERSION=Unknown
ECHO [%TIME%] [INFO] Detected Windows version: %OS_VERSION%

REM -----------------------------------------------------------------------------
REM Enhanced Monthly Scheduled Task Setup
REM Ensures a monthly scheduled task is created to run this script as admin.
REM -----------------------------------------------------------------------------
ECHO [%TIME%] [INFO] Setting up enhanced monthly scheduled task '%TASK_NAME%'...

REM Check if task already exists
schtasks /Query /TN "%TASK_NAME%" >nul 2>&1
IF %ERRORLEVEL% EQU 0 (
    ECHO [%TIME%] [INFO] Existing monthly task found. Deleting for recreation...
    schtasks /Delete /TN "%TASK_NAME%" /F >nul 2>&1
    IF %ERRORLEVEL% NEQ 0 (
        ECHO [%TIME%] [WARN] Failed to delete existing task, but continuing...
    )
)

REM Create enhanced monthly task with robust parameters
schtasks /Create ^
    /SC MONTHLY ^
    /MO 1 ^
    /D 1 ^
    /TN "%TASK_NAME%" ^
    /TR "cmd.exe /c \"\"%SCRIPT_PATH%\"\"" ^
    /ST 01:00 ^
    /RL HIGHEST ^
    /RU SYSTEM ^
    /IT ^
    /Z ^
    /F >nul 2>&1

IF %ERRORLEVEL% EQU 0 (
    ECHO [%TIME%] [INFO] Monthly scheduled task created successfully.
    
    REM Verify task was created and get details
    schtasks /Query /TN "%TASK_NAME%" /V >nul 2>&1
    IF %ERRORLEVEL% EQU 0 (
        ECHO [%TIME%] [INFO] Task verification successful.
        FOR /F "tokens=2 delims=:" %%i IN ('schtasks /Query /TN "%TASK_NAME%" /FO LIST ^| findstr /C:"Next Run Time"') DO (
            ECHO [%TIME%] [INFO] Next scheduled run: %%i
        )
    )
) ELSE (
    ECHO [%TIME%] [ERROR] Failed to create monthly scheduled task.
    ECHO [%TIME%] [ERROR] Attempting alternative creation method...
    
    REM Alternative creation method without some parameters
    schtasks /Create /SC MONTHLY /D 1 /TN "%TASK_NAME%" /TR "cmd.exe /c \"%SCRIPT_PATH%\"" /ST 01:00 /RL HIGHEST /F >nul 2>&1
    IF %ERRORLEVEL% EQU 0 (
        ECHO [%TIME%] [INFO] Monthly task created with basic parameters.
    ) ELSE (
        ECHO [%TIME%] [ERROR] Both creation methods failed. Monthly scheduling not available.
    )
)

REM -----------------------------------------------------------------------------
REM Startup Task Management - Check and Remove if Exists
REM This task should only exist temporarily after a system restart.
REM -----------------------------------------------------------------------------
ECHO [%TIME%] [INFO] Checking startup task '%STARTUP_TASK_NAME%'...
schtasks /Query /TN "%STARTUP_TASK_NAME%" >nul 2>&1
IF %ERRORLEVEL% EQU 0 (
    ECHO [%TIME%] [INFO] Existing startup task found. Removing...
    schtasks /Delete /TN "%STARTUP_TASK_NAME%" /F >nul 2>&1
    IF %ERRORLEVEL% EQU 0 (
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
IF %ERRORLEVEL% EQU 0 (
    ECHO [%TIME%] [INFO] Windows Update restart required.
    SET "RESTART_NEEDED=YES"
)

REM Check Component Based Servicing reboot flag
REG QUERY "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending" >nul 2>&1
IF %ERRORLEVEL% EQU 0 (
    ECHO [%TIME%] [INFO] Component Based Servicing restart pending.
    SET "RESTART_NEEDED=YES"
)

REM Check pending file operations
REG QUERY "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager" /v PendingFileRenameOperations >nul 2>&1
IF %ERRORLEVEL% EQU 0 (
    ECHO [%TIME%] [INFO] Pending file rename operations detected.
    SET "RESTART_NEEDED=YES"
)

IF "%RESTART_NEEDED%"=="YES" (
    ECHO [%TIME%] [WARN] System restart is required. Creating startup task and restarting...
    REM Create startup task to run 120 seconds (2 minutes) after system boot with admin rights
    schtasks /Create /SC ONSTART /TN "%STARTUP_TASK_NAME%" /TR "cmd /c \"timeout /t 120 /nobreak >nul && \"%SCRIPT_PATH%\"\"" /RL HIGHEST /F >nul 2>&1
    IF %ERRORLEVEL% EQU 0 (
        ECHO [%TIME%] [INFO] Startup task created successfully. Will run 120 seconds after system boot.
        ECHO [%TIME%] [INFO] Restarting system immediately...
        shutdown /r /t 5 /c "System restart required for maintenance continuation"
        ECHO [%TIME%] [INFO] System will restart in 5 seconds...
        timeout /t 10 /nobreak >nul
        EXIT /B 0
    ) ELSE (
        ECHO [%TIME%] [ERROR] Failed to create startup task. Continuing without restart...
    )
) ELSE (
    ECHO [%TIME%] [INFO] No pending restart detected. No startup task needed. Continuing with script...
)

REM -----------------------------------------------------------------------------
REM Dependency Management - Fixed for Unattended Installation
REM -----------------------------------------------------------------------------
ECHO [%TIME%] [INFO] Starting dependency installation...

REM Check and install NuGet PackageProvider first (fully unattended)
ECHO [%TIME%] [INFO] Checking NuGet PackageProvider...
powershell -ExecutionPolicy Bypass -Command "if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) { try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope AllUsers -Confirm:$false; Write-Host '[INFO] NuGet PackageProvider installed successfully' } catch { Write-Host '[WARN] Failed to install NuGet PackageProvider:' $_.Exception.Message; exit 1 } } else { Write-Host '[INFO] NuGet PackageProvider already available' }"
IF %ERRORLEVEL% NEQ 0 (
    ECHO [%TIME%] [WARN] NuGet PackageProvider installation failed, but continuing...
)

REM Set PowerShell Gallery as trusted (required for module installations)
ECHO [%TIME%] [INFO] Configuring PowerShell Gallery...
powershell -ExecutionPolicy Bypass -Command "try { Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted -ErrorAction Stop; Write-Host '[INFO] PowerShell Gallery configured as trusted' } catch { Write-Host '[WARN] Failed to configure PowerShell Gallery:' $_.Exception.Message }"

REM Install PSWindowsUpdate module (most important for maintenance)
ECHO [%TIME%] [INFO] Installing PSWindowsUpdate module...
powershell -ExecutionPolicy Bypass -Command "if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) { try { Install-Module -Name PSWindowsUpdate -Force -Scope AllUsers -AllowClobber -Confirm:$false; Write-Host '[INFO] PSWindowsUpdate module installed successfully' } catch { Write-Host '[WARN] Failed to install PSWindowsUpdate module:' $_.Exception.Message; exit 1 } } else { Write-Host '[INFO] PSWindowsUpdate module already available' }"
IF %ERRORLEVEL% NEQ 0 (
    ECHO [%TIME%] [WARN] PSWindowsUpdate module installation failed.
)

REM Try to install Chocolatey (optional but useful)
ECHO [%TIME%] [INFO] Checking Chocolatey installation...
choco --version >nul 2>&1
IF %ERRORLEVEL% NEQ 0 (
    ECHO [%TIME%] [INFO] Installing Chocolatey...
    powershell -ExecutionPolicy Bypass -Command "try { Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1')); Write-Host '[INFO] Chocolatey installed successfully' } catch { Write-Host '[WARN] Chocolatey installation failed, but this is optional:' $_.Exception.Message }"
    REM Refresh PATH to include Chocolatey
    IF EXIST "%ProgramData%\chocolatey\bin" (
        SET "PATH=%PATH%;%ProgramData%\chocolatey\bin"
    )
) ELSE (
    ECHO [%TIME%] [INFO] Chocolatey is already installed.
)

REM Try to install Winget if not available (Windows 11 usually has it, Windows 10 might not)
ECHO [%TIME%] [INFO] Checking Windows Package Manager (winget)...
winget --version >nul 2>&1
IF %ERRORLEVEL% NEQ 0 (
    ECHO [%TIME%] [INFO] Winget not found, attempting installation...
    powershell -ExecutionPolicy Bypass -Command "try { $progressPreference = 'silentlyContinue'; Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe; Write-Host '[INFO] Winget installation attempted' } catch { Write-Host '[WARN] Winget installation failed, but this is optional for Windows 10:' $_.Exception.Message }"
) ELSE (
    ECHO [%TIME%] [INFO] Winget is already available.
)

ECHO [%TIME%] [INFO] Dependency installation phase completed.

REM -----------------------------------------------------------------------------
REM System Restart Detection - Simplified
REM -----------------------------------------------------------------------------
ECHO [%TIME%] [INFO] Checking for pending system restarts...
SET "RESTART_NEEDED=NO"

REM Check Windows Update reboot flag
REG QUERY "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired" >nul 2>&1
IF %ERRORLEVEL% EQU 0 SET "RESTART_NEEDED=YES"

REM Check Component Based Servicing reboot flag
REG QUERY "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending" >nul 2>&1
IF %ERRORLEVEL% EQU 0 SET "RESTART_NEEDED=YES"

REM Check pending file operations
REG QUERY "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager" /v PendingFileRenameOperations >nul 2>&1
IF %ERRORLEVEL% EQU 0 SET "RESTART_NEEDED=YES"

IF "%RESTART_NEEDED%"=="YES" (
    ECHO [%TIME%] [WARN] System restart is pending. Creating startup task...
    schtasks /Query /TN "%STARTUP_TASK_NAME%" >nul 2>&1
    IF %ERRORLEVEL% EQU 0 (
        schtasks /Delete /TN "%STARTUP_TASK_NAME%" /F >nul 2>&1
    )
    schtasks /Create /SC ONSTART /TN "%STARTUP_TASK_NAME%" /TR "cmd /c \"timeout /t 60 /nobreak >nul && \"%SCRIPT_PATH%\"\"" /RL HIGHEST /DELAY 00:01 /F >nul 2>&1
    IF %ERRORLEVEL% EQU 0 (
        ECHO [%TIME%] [INFO] Startup task created. Restarting system in 15 seconds...
        ECHO [%TIME%] [INFO] Press Ctrl+C to cancel restart.
        timeout /t 15
        shutdown /r /t 5 /c "System restart required for maintenance continuation"
        EXIT /B 0
    ) ELSE (
        ECHO [%TIME%] [WARN] Failed to create startup task. Continuing without restart...
    )
) ELSE (
    ECHO [%TIME%] [INFO] No pending restart detected. Continuing...
)

REM -----------------------------------------------------------------------------
REM Repository Download - Simplified
REM -----------------------------------------------------------------------------
SET "REPO_URL=https://github.com/ichimbogdancristian/script_mentenanta/archive/refs/heads/main.zip"
SET "ZIP_FILE=%TEMP%\script_mentenanta.zip"
SET "EXTRACT_FOLDER=script_mentenanta-main"

ECHO [%TIME%] [INFO] Downloading latest repository...
powershell -ExecutionPolicy Bypass -Command "try { $ProgressPreference = 'SilentlyContinue'; Invoke-WebRequest -Uri '%REPO_URL%' -OutFile '%ZIP_FILE%' -UseBasicParsing; Write-Host '[INFO] Repository downloaded successfully' } catch { Write-Host '[ERROR] Download failed:' $_.Exception.Message; exit 1 }"

IF %ERRORLEVEL% NEQ 0 (
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
        powershell -ExecutionPolicy Bypass -Command "try { Remove-Item -Path '%SCRIPT_DIR%%EXTRACT_FOLDER%' -Recurse -Force -ErrorAction Stop; Write-Host '[INFO] Existing folder removed successfully' } catch { Write-Host '[WARN] Failed to remove existing folder:' $_.Exception.Message }"
    ) ELSE (
        ECHO [%TIME%] [INFO] Existing repository folder removed successfully.
    )
) ELSE (
    ECHO [%TIME%] [INFO] No existing repository folder found. Proceeding with clean extraction.
)

REM -----------------------------------------------------------------------------
REM Repository Extraction - Using PowerShell (More Reliable)
REM -----------------------------------------------------------------------------
ECHO [%TIME%] [INFO] Extracting repository to clean folder...
powershell -ExecutionPolicy Bypass -Command "try { Add-Type -AssemblyName System.IO.Compression.FileSystem; [System.IO.Compression.ZipFile]::ExtractToDirectory('%ZIP_FILE%', '%SCRIPT_DIR%'); Write-Host '[INFO] Repository extracted successfully' } catch { Write-Host '[ERROR] Extraction failed:' $_.Exception.Message; exit 1 }"

IF %ERRORLEVEL% NEQ 0 (
    ECHO [%TIME%] [ERROR] Failed to extract repository.
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

ECHO [%TIME%] [INFO] Repository extracted to clean folder: %SCRIPT_DIR%%EXTRACT_FOLDER%

REM -----------------------------------------------------------------------------
REM PowerShell 7 Detection and Installation (if needed)
REM -----------------------------------------------------------------------------
ECHO [%TIME%] [INFO] Checking PowerShell 7 availability...
SET "PS7_AVAILABLE=NO"

pwsh.exe -Version >nul 2>&1
IF %ERRORLEVEL% EQU 0 (
    SET "PS7_AVAILABLE=YES"
    FOR /F "tokens=*" %%i IN ('pwsh.exe -Command "$PSVersionTable.PSVersion.ToString()" 2^>nul') DO SET PS7_VERSION=%%i
    ECHO [%TIME%] [INFO] PowerShell 7 found: %PS7_VERSION%
) ELSE (
    ECHO [%TIME%] [WARN] PowerShell 7 not found. Attempting installation via winget...
    winget install --id Microsoft.Powershell --source winget --silent --accept-package-agreements --accept-source-agreements >nul 2>&1
    IF %ERRORLEVEL% EQU 0 (
        ECHO [%TIME%] [INFO] PowerShell 7 installation completed. Refreshing PATH...
        REM Refresh PATH environment variable
        FOR /F "tokens=2*" %%A IN ('REG QUERY "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" /v PATH') DO SET "NEW_PATH=%%B"
        SET "PATH=%NEW_PATH%"
        
        REM Check again after installation
        pwsh.exe -Version >nul 2>&1
        IF %ERRORLEVEL% EQU 0 (
            SET "PS7_AVAILABLE=YES"
            FOR /F "tokens=*" %%i IN ('pwsh.exe -Command "$PSVersionTable.PSVersion.ToString()" 2^>nul') DO SET PS7_VERSION=%%i
            ECHO [%TIME%] [INFO] PowerShell 7 successfully installed: %PS7_VERSION%
        ) ELSE (
            ECHO [%TIME%] [WARN] PowerShell 7 installation may require system restart to be available.
        )
    ) ELSE (
        ECHO [%TIME%] [WARN] PowerShell 7 installation failed. Will use Windows PowerShell instead.
    )
)

REM -----------------------------------------------------------------------------
REM Launch PowerShell Script with Priority for PowerShell 7
REM -----------------------------------------------------------------------------
SET "PS1_PATH=%SCRIPT_DIR%%EXTRACT_FOLDER%\script.ps1"

IF NOT EXIST "%PS1_PATH%" (
    ECHO [%TIME%] [ERROR] PowerShell script not found: %PS1_PATH%
    ECHO [%TIME%] [INFO] Contents of extracted folder:
    DIR "%SCRIPT_DIR%%EXTRACT_FOLDER%" /B
    pause
    EXIT /B 4
)

ECHO [%TIME%] [INFO] Launching PowerShell maintenance script...

IF "%PS7_AVAILABLE%"=="YES" (
    ECHO [%TIME%] [INFO] Using PowerShell 7 environment...
    START "Maintenance Script - PowerShell 7" pwsh.exe -ExecutionPolicy Bypass -File "%PS1_PATH%"
) ELSE (
    ECHO [%TIME%] [INFO] Using Windows PowerShell environment...
    START "Maintenance Script - Windows PowerShell" powershell.exe -ExecutionPolicy Bypass -File "%PS1_PATH%"
)

IF %ERRORLEVEL% EQU 0 (
    ECHO [%TIME%] [INFO] PowerShell script launched successfully in new window.
    ECHO [%TIME%] [INFO] Maintenance operations are now running in the background.
    ECHO.
    ECHO [%TIME%] [INFO] This launcher will close automatically in 120 seconds...
    ECHO [%TIME%] [INFO] Press any key to close immediately, or wait for automatic closure.
    
    REM 120-second countdown with visual feedback
    FOR /L %%i IN (120,-10,10) DO (
        ECHO [%TIME%] [INFO] Closing in %%i seconds...
        timeout /t 10 /nobreak >nul
    )
    
    ECHO [%TIME%] [INFO] Final countdown: 10 seconds...
    timeout /t 10 /nobreak >nul
    
    ECHO [%TIME%] [INFO] Batch launcher completed successfully.
) ELSE (
    ECHO [%TIME%] [ERROR] Failed to launch PowerShell script.
    ECHO [%TIME%] [ERROR] Please check the PowerShell script path and permissions.
    pause
)

ENDLOCAL
EXIT /B 0