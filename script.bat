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
REM Unified Logging Function - Logs to both console and maintenance.log
REM Usage: CALL :LOG_MESSAGE "message"
REM -----------------------------------------------------------------------------
GOTO :MAIN_SCRIPT
:LOG_MESSAGE
SET "LOG_TIMESTAMP=%DATE% %TIME%"
ECHO %~1
ECHO %~1 >> "%LOG_FILE%" 2>nul
EXIT /B

:MAIN_SCRIPT
REM -----------------------------------------------------------------------------
REM Robust Timestamp Function for Logging
REM -----------------------------------------------------------------------------
SET "LOG_TIMESTAMP=%DATE% %TIME%"
REM Usage: !LOG_TIMESTAMP! (if delayed expansion) or %LOG_TIMESTAMP% (if not)

REM -----------------------------------------------------------------------------
REM Universal Path Detection & Environment Setup (Location-Agnostic)
REM Works from any directory, any user, any computer - completely portable
REM -----------------------------------------------------------------------------
SET "TASK_NAME=ScriptMentenantaMonthly"
SET "STARTUP_TASK_NAME=ScriptMentenantaStartup"

REM Core path detection - works from anywhere
SET "SCRIPT_PATH=%~f0"
SET "SCRIPT_DIR=%~dp0"
SET "SCRIPT_NAME=%~nx0"

REM Working directory - always use the directory where script.bat is located
SET "WORKING_DIR=%SCRIPT_DIR%"
SET "LOG_FILE=%WORKING_DIR%maintenance.log"

REM Repository settings - optimized for any location execution
SET "REPO_URL=https://github.com/ichimbogdancristian/script_mentenanta/archive/refs/heads/main.zip"
SET "ZIP_FILE=%WORKING_DIR%script_mentenanta-main.zip"
SET "EXTRACT_FOLDER=script_mentenanta-main"
SET "EXTRACTED_PATH=%WORKING_DIR%%EXTRACT_FOLDER%"

REM PowerShell script paths - intelligent detection for any execution context
SET "PS1_PATH="
REM Priority 1: Check if we're already in a repo directory (current directory has script.ps1)
IF EXIST "%WORKING_DIR%script.ps1" (
    SET "PS1_PATH=%WORKING_DIR%script.ps1"
    CALL :LOG_MESSAGE "[%TIME%] [DEBUG] Found script.ps1 in current directory - using local version"
) ELSE (
    REM Priority 2: Will be set after repository extraction
    CALL :LOG_MESSAGE "[%TIME%] [DEBUG] No local script.ps1 found - will download repository"
)

CALL :LOG_MESSAGE "[%TIME%] [DEBUG] Working Directory: %WORKING_DIR%"
CALL :LOG_MESSAGE "[%TIME%] [DEBUG] Script Path: %SCRIPT_PATH%"
CALL :LOG_MESSAGE "[%TIME%] [DEBUG] Log File: %LOG_FILE%"

REM -----------------------------------------------------------------------------
REM Robust Script Path Detection for Scheduled Tasks
REM Determines the best path to use for scheduled task creation
REM -----------------------------------------------------------------------------
SET "SCHEDULED_TASK_SCRIPT_PATH="

REM Priority 1: Use current executing script path (most reliable)
IF EXIST "%SCRIPT_PATH%" (
    SET "SCHEDULED_TASK_SCRIPT_PATH=%SCRIPT_PATH%"
    CALL :LOG_MESSAGE "[%TIME%] [DEBUG] Scheduled task will use current script path: %SCRIPT_PATH%"
) ELSE (
    REM Priority 2: Look for script.bat in current directory
    IF EXIST "%SCRIPT_DIR%script.bat" (
        SET "SCHEDULED_TASK_SCRIPT_PATH=%SCRIPT_DIR%script.bat"
        CALL :LOG_MESSAGE "[%TIME%] [DEBUG] Scheduled task will use directory script: %SCRIPT_DIR%script.bat"
    ) ELSE (
        REM Priority 3: Use script path as fallback (should not happen)
        SET "SCHEDULED_TASK_SCRIPT_PATH=%SCRIPT_PATH%"
        CALL :LOG_MESSAGE "[%TIME%] [WARN] Using fallback script path for scheduled task: %SCRIPT_PATH%"
    )
)

REM Check if this is a restart after PowerShell 7 installation
IF "%1"=="PS7_RESTART" (
    CALL :LOG_MESSAGE "[%TIME%] [INFO] Script restarted after PowerShell 7 installation."
    GOTO :SKIP_PS7_INSTALL
)

REM Check if this is a restart after script.bat self-update
REM (Legacy self-update logic removed)

CALL :LOG_MESSAGE "[%TIME%] [INFO] Starting maintenance script..."
CALL :LOG_MESSAGE "[%TIME%] [INFO] User: %USERNAME%, Computer: %COMPUTERNAME%"

REM -----------------------------------------------------------------------------
REM Enhanced Admin Privilege Check
REM Uses multiple methods to ensure reliable administrator detection and proper elevation.
REM -----------------------------------------------------------------------------
REM Method 1: NET SESSION (traditional approach)
NET SESSION >nul 2>&1
SET "NET_SESSION_RESULT=%ERRORLEVEL%"

REM Method 2: PowerShell admin check (more reliable)
FOR /F "tokens=*" %%i IN ('powershell -Command "([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)" 2^>nul') DO SET PS_ADMIN_CHECK=%%i

CALL :LOG_MESSAGE "[%TIME%] [DEBUG] NET SESSION result: %NET_SESSION_RESULT%"
CALL :LOG_MESSAGE "[%TIME%] [DEBUG] PowerShell admin check: %PS_ADMIN_CHECK%"

REM Consider admin if either method confirms admin privileges
SET "IS_ADMIN=false"
IF %NET_SESSION_RESULT% EQU 0 SET "IS_ADMIN=true"
IF "%PS_ADMIN_CHECK%"=="True" SET "IS_ADMIN=true"

CALL :LOG_MESSAGE "[%TIME%] [DEBUG] Final admin status: %IS_ADMIN%"

IF "%IS_ADMIN%"=="false" (
    CALL :LOG_MESSAGE "[%TIME%] [WARN] Not running as Administrator. Relaunching with admin rights..."
    CALL :LOG_MESSAGE "[%TIME%] [DEBUG] Attempting elevation using PowerShell Start-Process..."
    powershell -Command "Start-Process cmd -ArgumentList '/c \"%~f0\"' -Verb RunAs"
    EXIT /B 0
)

CALL :LOG_MESSAGE "[%TIME%] [INFO] Administrator privileges confirmed"

REM -----------------------------------------------------------------------------
REM PowerShell Version Check
REM Ensures PowerShell 5.1+ is available for all automation features.
REM -----------------------------------------------------------------------------
FOR /F "tokens=*" %%i IN ('powershell -Command "$PSVersionTable.PSVersion.Major" 2^>nul') DO SET PS_VERSION=%%i
IF "%PS_VERSION%"=="" SET PS_VERSION=0
IF %PS_VERSION% LSS 5 (
    CALL :LOG_MESSAGE "[%TIME%] [ERROR] PowerShell 5.1 or higher is required. Current version: %PS_VERSION%"
    CALL :LOG_MESSAGE "[%TIME%] [ERROR] Please install PowerShell 5.1 or newer and try again."
    pause
    EXIT /B 3
)
CALL :LOG_MESSAGE "[%TIME%] [INFO] PowerShell version: %PS_VERSION%"

REM -----------------------------------------------------------------------------
REM Windows Version Detection - PowerShell 5.1 Compatible
REM -----------------------------------------------------------------------------
FOR /F "tokens=*" %%i IN ('powershell -Command "try { (Get-CimInstance Win32_OperatingSystem).Version } catch { (Get-WmiObject Win32_OperatingSystem).Version }" 2^>nul') DO SET OS_VERSION=%%i
IF "%OS_VERSION%"=="" SET OS_VERSION=Unknown
CALL :LOG_MESSAGE "[%TIME%] [INFO] Detected Windows version: %OS_VERSION%"

REM -----------------------------------------------------------------------------
REM Enhanced Monthly Scheduled Task Setup
REM Ensures a monthly scheduled task is created to run this script as admin.
REM -----------------------------------------------------------------------------
SET "LOG_TIMESTAMP=%DATE% %TIME%"
CALL :LOG_MESSAGE "[%LOG_TIMESTAMP%] [INFO] Checking for monthly scheduled task '%TASK_NAME%'..."
schtasks /Query /TN "%TASK_NAME%" >nul 2>&1
IF %ERRORLEVEL% EQU 0 (
    SET "LOG_TIMESTAMP=%DATE% %TIME%"
    CALL :LOG_MESSAGE "[%LOG_TIMESTAMP%] [INFO] Monthly scheduled task already exists. Skipping creation."
) ELSE (
    SET "LOG_TIMESTAMP=%DATE% %TIME%"
    CALL :LOG_MESSAGE "[%LOG_TIMESTAMP%] [INFO] Monthly scheduled task not found. Creating..."
    CALL :LOG_MESSAGE "[%LOG_TIMESTAMP%] [DEBUG] Using script path for task: %SCHEDULED_TASK_SCRIPT_PATH%"
    REM Create scheduled task with proper escaping
    schtasks /Create ^
        /SC MONTHLY ^
        /MO 1 ^
        /TN "%TASK_NAME%" ^
        /TR "%SCHEDULED_TASK_SCRIPT_PATH%" ^
        /ST 01:00 ^
        /RL HIGHEST ^
        /RU SYSTEM ^
        /F >schtasks_create.log 2>&1
    IF !ERRORLEVEL! EQU 0 (
        SET "LOG_TIMESTAMP=%DATE% %TIME%"
        CALL :LOG_MESSAGE "[%LOG_TIMESTAMP%] [INFO] Monthly scheduled task created successfully."
        schtasks /Query /TN "%TASK_NAME%" /V >nul 2>&1
        IF !ERRORLEVEL! EQU 0 (
            SET "LOG_TIMESTAMP=%DATE% %TIME%"
            CALL :LOG_MESSAGE "[%LOG_TIMESTAMP%] [INFO] Task verification successful."
            FOR /F "tokens=2 delims=:" %%i IN ('schtasks /Query /TN "%TASK_NAME%" /FO LIST ^| findstr /C:"Next Run Time"') DO (
                SET "LOG_TIMESTAMP=%DATE% %TIME%"
                CALL :LOG_MESSAGE "[%LOG_TIMESTAMP%] [INFO] Next scheduled run: %%i"
            )
        )
    ) ELSE (
        SET "LOG_TIMESTAMP=%DATE% %TIME%"
        CALL :LOG_MESSAGE "[%LOG_TIMESTAMP%] [ERROR] Failed to create monthly scheduled task. See schtasks_create.log for details."
        REM Display the actual error for debugging
        IF EXIST schtasks_create.log (
            CALL :LOG_MESSAGE "[%LOG_TIMESTAMP%] [ERROR] Scheduled task creation error details:"
            TYPE schtasks_create.log
        ) ELSE (
            CALL :LOG_MESSAGE "[%LOG_TIMESTAMP%] [ERROR] No error log file created."
        )
        
        REM Try alternative approach with current user instead of SYSTEM
        SET "LOG_TIMESTAMP=%DATE% %TIME%"
        CALL :LOG_MESSAGE "[%LOG_TIMESTAMP%] [INFO] Attempting to create task under current user account..."
        CALL :LOG_MESSAGE "[%LOG_TIMESTAMP%] [DEBUG] Using script path for user task: %SCHEDULED_TASK_SCRIPT_PATH%"
        schtasks /Create ^
            /SC MONTHLY ^
            /MO 1 ^
            /TN "%TASK_NAME%" ^
            /TR "%SCHEDULED_TASK_SCRIPT_PATH%" ^
            /ST 01:00 ^
            /RL HIGHEST ^
            /F >schtasks_create_user.log 2>&1
        IF !ERRORLEVEL! EQU 0 (
            SET "LOG_TIMESTAMP=%DATE% %TIME%"
            CALL :LOG_MESSAGE "[%LOG_TIMESTAMP%] [INFO] Monthly scheduled task created successfully under current user."
        ) ELSE (
            SET "LOG_TIMESTAMP=%DATE% %TIME%"
            CALL :LOG_MESSAGE "[%LOG_TIMESTAMP%] [WARN] Failed to create scheduled task under current user as well."
            IF EXIST schtasks_create_user.log TYPE schtasks_create_user.log
        )
    )
)

REM -----------------------------------------------------------------------------
REM Startup Task Management - Check and Remove if Exists
REM This task should only exist temporarily after a system restart.
REM -----------------------------------------------------------------------------
SET "LOG_TIMESTAMP=%DATE% %TIME%"
CALL :LOG_MESSAGE "[%LOG_TIMESTAMP%] [INFO] Checking startup task '%STARTUP_TASK_NAME%'..."
schtasks /Query /TN "%STARTUP_TASK_NAME%" >nul 2>&1
IF !ERRORLEVEL! EQU 0 (
    SET "LOG_TIMESTAMP=%DATE% %TIME%"
    CALL :LOG_MESSAGE "[%LOG_TIMESTAMP%] [INFO] Existing startup task found. Removing..."
    schtasks /Delete /TN "%STARTUP_TASK_NAME%" /F >nul 2>&1
    IF !ERRORLEVEL! EQU 0 (
    SET "LOG_TIMESTAMP=%DATE% %TIME%"
    CALL :LOG_MESSAGE "[%LOG_TIMESTAMP%] [INFO] Startup task removed successfully."
    ) ELSE (
    SET "LOG_TIMESTAMP=%DATE% %TIME%"
    CALL :LOG_MESSAGE "[%LOG_TIMESTAMP%] [WARN] Failed to remove startup task, but continuing..."
    )
) ELSE (
    SET "LOG_TIMESTAMP=%DATE% %TIME%"
    CALL :LOG_MESSAGE "[%LOG_TIMESTAMP%] [INFO] No existing startup task found."
)

REM -----------------------------------------------------------------------------
REM Smart Restart Detection - Only restart for pending updates requiring restart
REM Check if Windows requires a restart for PENDING UPDATES, not general maintenance
REM -----------------------------------------------------------------------------
CALL :LOG_MESSAGE "[%TIME%] [INFO] Checking for pending updates requiring restart..."
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
    CALL :LOG_MESSAGE "[%TIME%] [WARN] System restart is required for pending updates."
    CALL :LOG_MESSAGE "[%TIME%] [INFO] Reason: %RESTART_REASON%"
    CALL :LOG_MESSAGE "[%TIME%] [INFO] Creating startup task and restarting to complete update installation..."
    
    REM Delete any existing startup task first
    schtasks /Delete /TN "%STARTUP_TASK_NAME%" /F >nul 2>&1
    
    REM Create startup task to run 1 minute after user login with admin rights
    CALL :LOG_MESSAGE "[%TIME%] [DEBUG] Creating startup task with script path: %SCHEDULED_TASK_SCRIPT_PATH%"
    schtasks /Create /SC ONLOGON /TN "%STARTUP_TASK_NAME%" /TR "%SCHEDULED_TASK_SCRIPT_PATH%" /RL HIGHEST /RU "%USERNAME%" /DELAY 0001:00 /F
    IF !ERRORLEVEL! EQU 0 (
        CALL :LOG_MESSAGE "[%TIME%] [INFO] Startup task created successfully. Will run 1 minute after user login."
        CALL :LOG_MESSAGE "[%TIME%] [INFO] Restarting system to complete pending updates..."
        shutdown /r /t 10 /c "System restart required to complete pending Windows Updates"
        CALL :LOG_MESSAGE "[%TIME%] [INFO] System will restart in 10 seconds to complete updates..."
        timeout /t 12 /nobreak >nul
        EXIT /B 0
    ) ELSE (
        CALL :LOG_MESSAGE "[%TIME%] [ERROR] Failed to create startup task. Continuing without restart..."
        CALL :LOG_MESSAGE "[%TIME%] [WARN] Updates may require manual restart after installation."
    )
) ELSE (
    CALL :LOG_MESSAGE "[%TIME%] [INFO] No pending updates require restart. Continuing with maintenance script..."
)


REM -----------------------------------------------------------------------------
REM Dependency Management - Direct Downloads from Official Sources
REM Installation Order: Winget -> PowerShell 7 -> NuGet -> PSGallery -> PSWindowsUpdate -> Chocolatey
REM -----------------------------------------------------------------------------
CALL :LOG_MESSAGE "[%TIME%] [INFO] Starting dependency installation with optimized order..."

REM -----------------------------------------------------------------------------
REM 1. Windows Package Manager (Winget) - Foundation package manager
REM -----------------------------------------------------------------------------
CALL :LOG_MESSAGE "[%TIME%] [INFO] Installing Windows Package Manager (winget)..."
REM Improved Winget detection: check both version and path
winget --version >nul 2>&1
SET "WINGET_FOUND=0"
IF !ERRORLEVEL! EQU 0 (
    SET "WINGET_FOUND=1"
    CALL :LOG_MESSAGE "[%TIME%] [DEBUG] Winget detected via version check."
) ELSE (
    where winget >nul 2>&1
    IF !ERRORLEVEL! EQU 0 (
        SET "WINGET_FOUND=1"
        CALL :LOG_MESSAGE "[%TIME%] [DEBUG] Winget detected via PATH (where command)."
    )
)

IF !WINGET_FOUND! EQU 0 (
    CALL :LOG_MESSAGE "[%TIME%] [INFO] Winget not found, downloading from official Microsoft source..."
    REM Download latest App Installer from Microsoft Store
    SET "WINGET_URL=https://github.com/microsoft/winget-cli/releases/latest/download/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"
    SET "WINGET_FILE=!TEMP!\Microsoft.DesktopAppInstaller.msixbundle"
    powershell -ExecutionPolicy Bypass -Command "try { $ProgressPreference = 'SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri '!WINGET_URL!' -OutFile '!WINGET_FILE!' -UseBasicParsing; Write-Host '[INFO] Winget downloaded successfully' } catch { Write-Host '[WARN] Winget download failed:' $_.Exception.Message; exit 1 }"
    IF !ERRORLEVEL! EQU 0 (
        CALL :LOG_MESSAGE "[%TIME%] [INFO] Installing Winget package..."
        powershell -ExecutionPolicy Bypass -Command "try { if (Get-Command Add-AppxPackage -ErrorAction SilentlyContinue) { Add-AppxPackage -Path '!WINGET_FILE!' -ErrorAction Stop; Write-Host '[INFO] Winget installed successfully' } else { Write-Host '[WARN] Add-AppxPackage not available in this PowerShell version' } } catch { Write-Host '[WARN] Winget installation failed:' $_.Exception.Message; exit 1 }"
        IF !ERRORLEVEL! EQU 0 (
            CALL :LOG_MESSAGE "[%TIME%] [INFO] Winget installation completed successfully."
        ) ELSE (
            CALL :LOG_MESSAGE "[%TIME%] [WARN] Winget installation failed, but continuing..."
        )
        DEL /F /Q "!WINGET_FILE!" >nul 2>&1
    ) ELSE (
        CALL :LOG_MESSAGE "[%TIME%] [WARN] Winget download failed, but continuing..."
    )
) ELSE (
    CALL :LOG_MESSAGE "[%TIME%] [INFO] Winget is already available."
)

REM -----------------------------------------------------------------------------
REM 2. PowerShell 7 - Modern PowerShell environment
REM -----------------------------------------------------------------------------
CALL :LOG_MESSAGE "[%TIME%] [INFO] Installing PowerShell 7..."
pwsh.exe -Version >nul 2>&1
IF !ERRORLEVEL! NEQ 0 (
    CALL :LOG_MESSAGE "[%TIME%] [INFO] PowerShell 7 not found, downloading from official Microsoft source..."
    
    REM Set download URL for PowerShell 7.5.2 (no fallback)
    SET "PS7_INSTALLER=%TEMP%\PowerShell-7.5.2.msi"
    
    REM Detect architecture and set appropriate download URL
    IF "%PROCESSOR_ARCHITECTURE%"=="AMD64" (
        SET "PS7_URL=https://github.com/PowerShell/PowerShell/releases/download/v7.5.2/PowerShell-7.5.2-win-x64.msi"
    ) ELSE (
        SET "PS7_URL=https://github.com/PowerShell/PowerShell/releases/download/v7.5.2/PowerShell-7.5.2-win-x86.msi"
    )
    
    REM Download PowerShell 7.5.2
    CALL :LOG_MESSAGE "[%TIME%] [INFO] Downloading PowerShell 7.5.2..."
    powershell -ExecutionPolicy Bypass -Command "try { $ProgressPreference = 'SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri '!PS7_URL!' -OutFile '!PS7_INSTALLER!' -UseBasicParsing; Write-Host '[INFO] PowerShell 7.5.2 downloaded successfully' } catch { Write-Host '[ERROR] PowerShell 7.5.2 download failed:' $_.Exception.Message; exit 1 }"
    
    IF !ERRORLEVEL! EQU 0 (
        CALL :LOG_MESSAGE "[%TIME%] [INFO] Installing PowerShell 7..."
        msiexec /i "!PS7_INSTALLER!" /quiet /norestart
        IF !ERRORLEVEL! EQU 0 (
            CALL :LOG_MESSAGE "[%TIME%] [INFO] PowerShell 7 installed successfully."
            REM Refresh PATH environment variable for current session
            FOR /F "tokens=2*" %%A IN ('REG QUERY "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" /v PATH') DO SET "PATH=%%B"
            REM Add common PowerShell 7 installation paths to current session
            IF EXIST "%ProgramFiles%\PowerShell\7" SET "PATH=%PATH%;%ProgramFiles%\PowerShell\7"
            IF EXIST "%ProgramFiles(x86)%\PowerShell\7" SET "PATH=%PATH%;%ProgramFiles(x86)%\PowerShell\7"
            CALL :LOG_MESSAGE "[%TIME%] [INFO] PowerShell 7 installation completed. Restarting script to use new PowerShell..."
            REM Restart the script to use newly installed PowerShell 7
            START "" "%~f0" PS7_RESTART
            EXIT /B 0
        ) ELSE (
            CALL :LOG_MESSAGE "[%TIME%] [WARN] PowerShell 7 installation failed."
        )
        DEL /F /Q "!PS7_INSTALLER!" >nul 2>&1
    )
) ELSE (
    FOR /F "tokens=*" %%i IN ('pwsh.exe -Command "$PSVersionTable.PSVersion.ToString()" 2^>nul') DO SET PS7_VERSION=%%i
    CALL :LOG_MESSAGE "[%TIME%] [INFO] PowerShell 7 already available: %PS7_VERSION%"
)

:SKIP_PS7_INSTALL

REM -----------------------------------------------------------------------------
REM 3. NuGet PackageProvider - Automatic installation with multiple methods
REM -----------------------------------------------------------------------------
CALL :LOG_MESSAGE "[%TIME%] [INFO] Installing NuGet PackageProvider with automatic confirmation..."

REM Method 1: Direct bootstrap with automatic Y response
ECHO Y | powershell -ExecutionPolicy Bypass -Command "& { $env:PACKAGEMANAGEMENT_BOOTSTRAP_LOGLEVEL='None'; if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) { try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope AllUsers -ErrorAction Stop; Write-Host '[INFO] NuGet PackageProvider installed successfully' } catch { Write-Host '[WARN] Method 1 failed, trying direct download...' } } else { Write-Host '[INFO] NuGet PackageProvider already available' } }"

IF !ERRORLEVEL! NEQ 0 (
    CALL :LOG_MESSAGE "[%TIME%] [INFO] Trying alternative NuGet installation method..."
    REM Method 2: Direct download and install (fallback)
    powershell -ExecutionPolicy Bypass -Command "& { try { $nugetUrl = 'https://onegetcdn.azureedge.net/providers/Microsoft.PackageManagement.NuGetProvider-2.8.5.208.dll'; $nugetPath = Join-Path $env:ProgramFiles 'PackageManagement\ProviderAssemblies\nuget\2.8.5.208\Microsoft.PackageManagement.NuGetProvider.dll'; $nugetDir = Split-Path $nugetPath; if (-not (Test-Path $nugetDir)) { New-Item -ItemType Directory -Path $nugetDir -Force | Out-Null }; [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri $nugetUrl -OutFile $nugetPath -UseBasicParsing; Write-Host '[INFO] NuGet PackageProvider downloaded and installed manually' } catch { Write-Host '[WARN] Direct download also failed:' $_.Exception.Message } }"
)

IF !ERRORLEVEL! NEQ 0 (
    CALL :LOG_MESSAGE "[%TIME%] [WARN] NuGet PackageProvider installation failed, but continuing..."
)

REM -----------------------------------------------------------------------------
REM 4. PowerShell Gallery Configuration - Fully Unattended
REM -----------------------------------------------------------------------------
CALL :LOG_MESSAGE "[%TIME%] [INFO] Configuring PowerShell Gallery as trusted repository..."
ECHO Y | powershell -ExecutionPolicy Bypass -Command "& { try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) { Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope AllUsers -Confirm:`$false -ErrorAction SilentlyContinue }; Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted -ErrorAction Stop; Write-Host '[INFO] PowerShell Gallery configured as trusted' } catch { Write-Host '[WARN] Failed to configure PowerShell Gallery:' `$_.Exception.Message } }"

REM -----------------------------------------------------------------------------
REM 5. PSWindowsUpdate Module - Download from PowerShell Gallery with auto-confirmation
REM -----------------------------------------------------------------------------
CALL :LOG_MESSAGE "[%TIME%] [INFO] Installing PSWindowsUpdate module with automatic confirmation..."
ECHO Y | powershell -ExecutionPolicy Bypass -Command "& { if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) { try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) { Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope AllUsers -Confirm:`$false -ErrorAction SilentlyContinue }; Install-Module -Name PSWindowsUpdate -Force -Scope AllUsers -AllowClobber -Repository PSGallery -Confirm:`$false; Write-Host '[INFO] PSWindowsUpdate module installed successfully' } catch { Write-Host '[WARN] Failed to install PSWindowsUpdate module:' `$_.Exception.Message } } else { Write-Host '[INFO] PSWindowsUpdate module already available' } }"

IF !ERRORLEVEL! NEQ 0 (
    CALL :LOG_MESSAGE "[%TIME%] [WARN] PSWindowsUpdate module installation failed."
)

REM -----------------------------------------------------------------------------
REM 6. Chocolatey Package Manager - Direct download from official source
REM -----------------------------------------------------------------------------
CALL :LOG_MESSAGE "[%TIME%] [INFO] Installing Chocolatey package manager..."
choco --version >nul 2>&1
IF !ERRORLEVEL! NEQ 0 (
    CALL :LOG_MESSAGE "[%TIME%] [INFO] Chocolatey not found, downloading from official source..."
    
    REM Download and install Chocolatey from official source
    powershell -ExecutionPolicy Bypass -Command "& { try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Set-ExecutionPolicy Bypass -Scope Process -Force; $chocoInstallScript = (New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'); Invoke-Expression $chocoInstallScript; Write-Host '[INFO] Chocolatey installed successfully' } catch { Write-Host '[WARN] Chocolatey installation failed:' $_.Exception.Message } }"
    
    REM Refresh PATH to include Chocolatey
    IF EXIST "%ProgramData%\chocolatey\bin" (
        SET "PATH=%PATH%;%ProgramData%\chocolatey\bin"
        CALL :LOG_MESSAGE "[%TIME%] [INFO] Chocolatey PATH updated."
    )
) ELSE (
    CALL :LOG_MESSAGE "[%TIME%] [INFO] Chocolatey is already installed."
)

CALL :LOG_MESSAGE "[%TIME%] [INFO] Dependency installation phase completed with optimized order."

REM -----------------------------------------------------------------------------
REM System Restart Detection - Simplified
REM -----------------------------------------------------------------------------
CALL :LOG_MESSAGE "[%TIME%] [INFO] Checking for pending system restarts..."
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
    CALL :LOG_MESSAGE "[%TIME%] [WARN] System restart is pending. Creating startup task..."
    schtasks /Query /TN "%STARTUP_TASK_NAME%" >nul 2>&1
    IF %ERRORLEVEL% EQU 0 (
        schtasks /Delete /TN "%STARTUP_TASK_NAME%" /F >nul 2>&1
    )
    schtasks /Create /SC ONLOGON /TN "%STARTUP_TASK_NAME%" /TR "%SCRIPT_PATH%" /RL HIGHEST /RU "%USERNAME%" /DELAY 0001:00 /F
    IF !ERRORLEVEL! EQU 0 (
        CALL :LOG_MESSAGE "[%TIME%] [INFO] Startup task created. Restarting system in 15 seconds..."
        CALL :LOG_MESSAGE "[%TIME%] [INFO] Press Ctrl+C to cancel restart."
        timeout /t 15
        shutdown /r /t 5 /c "System restart required for maintenance continuation"
        EXIT /B 0
    ) ELSE (
        CALL :LOG_MESSAGE "[%TIME%] [WARN] Failed to create startup task. Continuing without restart..."
        CALL :LOG_MESSAGE "[%TIME%] [DEBUG] Task name: %STARTUP_TASK_NAME%"
        CALL :LOG_MESSAGE "[%TIME%] [DEBUG] Script path: %SCRIPT_PATH%"
        CALL :LOG_MESSAGE "[%TIME%] [DEBUG] Username: %USERNAME%"
        CALL :LOG_MESSAGE "[%TIME%] [DEBUG] Error level: !ERRORLEVEL!"
    )
) ELSE (
    CALL :LOG_MESSAGE "[%TIME%] [INFO] No pending restart detected. Continuing..."
)

REM -----------------------------------------------------------------------------
REM Universal Repository Management - Location-Agnostic Download & Update
REM Works from any directory, downloads to current script location
REM -----------------------------------------------------------------------------
:SKIP_SELF_UPDATE

REM Check if we need to download repository or use local files
IF DEFINED PS1_PATH (
    IF EXIST "%PS1_PATH%" (
        CALL :LOG_MESSAGE "[%TIME%] [INFO] Using local script.ps1 file: %PS1_PATH%"
        CALL :LOG_MESSAGE "[%TIME%] [INFO] Skipping repository download - local files available"
        GOTO :PS1_DETECTION_COMPLETE
    )
)

CALL :LOG_MESSAGE "[%TIME%] [INFO] Downloading latest repository from GitHub to current location..."
CALL :LOG_MESSAGE "[%TIME%] [INFO] Working directory: %WORKING_DIR%"

REM Clean up existing files
IF EXIST "%ZIP_FILE%" (
    DEL "%ZIP_FILE%" >nul 2>&1
    CALL :LOG_MESSAGE "[%TIME%] [INFO] Removed existing ZIP file"
)

IF EXIST "%EXTRACTED_PATH%" (
    CALL :LOG_MESSAGE "[%TIME%] [INFO] Removing existing repository folder..."
    RMDIR /S /Q "%EXTRACTED_PATH%" >nul 2>&1
    IF EXIST "%EXTRACTED_PATH%" (
        powershell -ExecutionPolicy Bypass -Command "try { if(Test-Path '%EXTRACTED_PATH%') { Remove-Item -Path '%EXTRACTED_PATH%' -Recurse -Force } } catch { Write-Warning 'Could not remove existing folder' }"
    )
)

REM Download repository
CALL :LOG_MESSAGE "[%TIME%] [INFO] Downloading from: %REPO_URL%"
CALL :LOG_MESSAGE "[%TIME%] [INFO] Saving to: %ZIP_FILE%"

powershell -ExecutionPolicy Bypass -Command "try { $ProgressPreference = 'SilentlyContinue'; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12; $webClient = New-Object System.Net.WebClient; $webClient.DownloadFile('%REPO_URL%', '%ZIP_FILE%'); Write-Host '[INFO] Repository downloaded successfully' } catch { Write-Host '[ERROR] Download failed:' $_.Exception.Message; exit 1 }"

IF !ERRORLEVEL! NEQ 0 (
    CALL :LOG_MESSAGE "[%TIME%] [ERROR] Failed to download repository. Check internet connection."
    pause
    EXIT /B 3
)

IF NOT EXIST "%ZIP_FILE%" (
    CALL :LOG_MESSAGE "[%TIME%] [ERROR] Download failed - ZIP file not created at: %ZIP_FILE%"
    pause
    EXIT /B 3
)
REM -----------------------------------------------------------------------------
REM Universal Repository Extraction - Extract to working directory
REM -----------------------------------------------------------------------------
CALL :LOG_MESSAGE "[%TIME%] [INFO] Extracting repository to: %WORKING_DIR%"

powershell -ExecutionPolicy Bypass -Command "try { Add-Type -AssemblyName System.IO.Compression.FileSystem; if(Test-Path '%ZIP_FILE%') { [System.IO.Compression.ZipFile]::ExtractToDirectory('%ZIP_FILE%', '%WORKING_DIR%'); Write-Host '[INFO] Repository extracted successfully.' } else { Write-Host '[ERROR] ZIP file not found at %ZIP_FILE%'; exit 1 } } catch { Write-Host '[ERROR] Extraction failed:' $_.Exception.Message; exit 1 }"

IF !ERRORLEVEL! NEQ 0 (
    CALL :LOG_MESSAGE "[%TIME%] [ERROR] Repository extraction failed."
    pause
    EXIT /B 3
)

REM Clean up ZIP file
DEL /F /Q "%ZIP_FILE%" >nul 2>&1

REM Verify extraction and update PowerShell script path
CALL :LOG_MESSAGE "[%TIME%] [INFO] Verifying repository extraction..."
CALL :LOG_MESSAGE "[%TIME%] [INFO] Looking for extracted folder: %EXTRACTED_PATH%"

IF EXIST "%EXTRACTED_PATH%" (
    CALL :LOG_MESSAGE "[%TIME%] [INFO] ✓ Repository extraction successful"
    
    REM Update PowerShell script path to extracted version
    IF EXIST "%EXTRACTED_PATH%\script.ps1" (
        SET "PS1_PATH=%EXTRACTED_PATH%\script.ps1"
        CALL :LOG_MESSAGE "[%TIME%] [INFO] ✓ Found script.ps1 in extracted folder"
    ) ELSE (
        CALL :LOG_MESSAGE "[%TIME%] [ERROR] ✗ script.ps1 not found in extracted folder"
        pause
        EXIT /B 3
    )
    
) ELSE (
    CALL :LOG_MESSAGE "[%TIME%] [ERROR] ✗ Extraction failed - expected folder not found"
    CALL :LOG_MESSAGE "[%TIME%] [INFO] Available folders in working directory:"
    DIR "%WORKING_DIR%" /AD /B
    
    REM Try alternative folder names
    IF EXIST "%WORKING_DIR%script_mentenanta-master" (
        SET "EXTRACT_FOLDER=script_mentenanta-master"
        SET "EXTRACTED_PATH=%WORKING_DIR%script_mentenanta-master"
        SET "PS1_PATH=%EXTRACTED_PATH%\script.ps1"
        CALL :LOG_MESSAGE "[%TIME%] [INFO] ✓ Found alternative folder: script_mentenanta-master"
    ) ELSE (
        CALL :LOG_MESSAGE "[%TIME%] [ERROR] Could not find any valid extracted folder"
        pause
        EXIT /B 3
    )
)
REM -----------------------------------------------------------------------------
REM Self-Update Mechanism - Using dynamic paths
REM -----------------------------------------------------------------------------
SET "NEW_SCRIPT_BAT=%EXTRACTED_PATH%\script.bat"
SET "CURRENT_SCRIPT_BAT=%SCRIPT_PATH%"
SET "SELF_UPDATE_NEEDED=NO"

IF EXIST "%NEW_SCRIPT_BAT%" (
    CALL :LOG_MESSAGE "[%TIME%] [INFO] Found new script.bat in extracted repository."
    CALL :LOG_MESSAGE "[%TIME%] [INFO] Self-update will be performed AFTER PowerShell script execution."
    CALL :LOG_MESSAGE "[%TIME%] [INFO] This prevents execution conflicts during script update."
    SET "SELF_UPDATE_NEEDED=YES"
)
REM -----------------------------------------------------------------------------
REM PowerShell 7 Detection and Final Verification
REM -----------------------------------------------------------------------------
CALL :LOG_MESSAGE "[%TIME%] [INFO] Checking PowerShell 7 availability for script execution..."
SET "PS7_AVAILABLE=NO"

pwsh.exe -Version >nul 2>&1
IF !ERRORLEVEL! EQU 0 (
    SET "PS7_AVAILABLE=YES"
    FOR /F "tokens=*" %%i IN ('pwsh.exe -Command "$PSVersionTable.PSVersion.ToString()" 2^>nul') DO SET PS7_VERSION=%%i
    CALL :LOG_MESSAGE "[%TIME%] [INFO] PowerShell 7 found: !PS7_VERSION!"
) ELSE (
    CALL :LOG_MESSAGE "[%TIME%] [WARN] PowerShell 7 not available. Will use Windows PowerShell."
)

REM -----------------------------------------------------------------------------
REM Smart PowerShell Script Path Detection (Location-Agnostic)
REM -----------------------------------------------------------------------------
CALL :LOG_MESSAGE "[%TIME%] [INFO] Starting PowerShell script path detection..."
CALL :LOG_MESSAGE "[%TIME%] [DEBUG] Working directory: %WORKING_DIR%"
CALL :LOG_MESSAGE "[%TIME%] [DEBUG] Extracted path: %EXTRACTED_PATH%"

REM Priority 1: Use the path already set during extraction
IF DEFINED PS1_PATH (
    IF EXIST "%PS1_PATH%" (
        CALL :LOG_MESSAGE "[%TIME%] [INFO] ✓ Using PowerShell script: %PS1_PATH%"
        GOTO :PS1_DETECTION_COMPLETE
    )
)

REM Priority 2: Check current directory (if script.ps1 exists locally)
CALL :LOG_MESSAGE "[%TIME%] [DEBUG] Checking current directory: %WORKING_DIR%script.ps1"
IF EXIST "%WORKING_DIR%script.ps1" (
    SET "PS1_PATH=%WORKING_DIR%script.ps1"
    CALL :LOG_MESSAGE "[%TIME%] [INFO] ✓ Found script.ps1 in current directory"
    GOTO :PS1_DETECTION_COMPLETE
)

)

:PS1_DETECTION_COMPLETE

REM Final check: If still not found, show detailed diagnostics
IF NOT DEFINED PS1_PATH (
    CALL :LOG_MESSAGE "[%TIME%] [ERROR] PowerShell script (script.ps1) not found in any location!"
    CALL :LOG_MESSAGE "[%TIME%] [INFO] Searched locations:"
    CALL :LOG_MESSAGE "[%TIME%] [INFO] 1. Extracted folder: %EXTRACTED_PATH%\script.ps1"
    CALL :LOG_MESSAGE "[%TIME%] [INFO] 2. Current directory: %WORKING_DIR%script.ps1"
    CALL :LOG_MESSAGE "[%TIME%] [INFO] Contents of working directory:"
    DIR "%WORKING_DIR%" /B
    IF EXIST "%EXTRACTED_PATH%" (
        CALL :LOG_MESSAGE "[%TIME%] [INFO] Contents of extracted folder:"
        DIR "%EXTRACTED_PATH%" /B
    )
CALL :LOG_MESSAGE "[%TIME%] [SUCCESS] PowerShell script found successfully!"
REM -----------------------------------------------------------------------------
REM Launch PowerShell Script
REM -----------------------------------------------------------------------------
CALL :LOG_MESSAGE "[%TIME%] [INFO] Final PowerShell script path: %PS1_PATH%"
CALL :LOG_MESSAGE "[%TIME%] [INFO] Launching PowerShell maintenance script..."

REM Test PowerShell availability before launching
powershell.exe -Command "Write-Host 'PowerShell test successful'" >nul 2>&1
IF !ERRORLEVEL! NEQ 0 (
    CALL :LOG_MESSAGE "[%TIME%] [ERROR] Windows PowerShell is not available or functioning properly."
    pause
    EXIT /B 5
)

REM Final check that PS1_PATH is not empty before execution
IF NOT DEFINED PS1_PATH (
    CALL :LOG_MESSAGE "[%TIME%] [FATAL] PS1_PATH is empty before execution!"
    CALL :LOG_MESSAGE "[%TIME%] [FATAL] Cannot proceed without PowerShell script!"
    pause
    EXIT /B 5
)

CALL :LOG_MESSAGE "[%TIME%] [INFO] About to execute: %PS1_PATH%"
CALL :LOG_MESSAGE "[%TIME%] [INFO] Verifying file exists: %PS1_PATH%"
IF NOT EXIST "%PS1_PATH%" (
    CALL :LOG_MESSAGE "[%TIME%] [FATAL] PowerShell script file does not exist: %PS1_PATH%"
    pause
    EXIT /B 6
)
IF "%PS7_AVAILABLE%"=="YES" (
    CALL :LOG_MESSAGE "[%TIME%] [INFO] Using PowerShell 7 environment..."
    CALL :LOG_MESSAGE "[%TIME%] [DEBUG] Launching with admin privileges: pwsh.exe"
    pwsh.exe -ExecutionPolicy Bypass -File "%PS1_PATH%"
    SET "LAUNCH_RESULT=%ERRORLEVEL%"
) ELSE (
    CALL :LOG_MESSAGE "[%TIME%] [INFO] Using Windows PowerShell environment..."
    CALL :LOG_MESSAGE "[%TIME%] [DEBUG] Launching with admin privileges: powershell.exe"
    powershell.exe -ExecutionPolicy Bypass -File "%PS1_PATH%"
    SET "LAUNCH_RESULT=%ERRORLEVEL%"
)

IF %LAUNCH_RESULT% EQU 0 (
    CALL :LOG_MESSAGE "[%TIME%] [INFO] PowerShell script execution completed successfully."
    
    REM -----------------------------------------------------------------------------
    REM Deferred Self-Update - Perform after PowerShell execution completes
    REM -----------------------------------------------------------------------------
    IF "%SELF_UPDATE_NEEDED%"=="YES" (
        CALL :LOG_MESSAGE "[%TIME%] [INFO] Performing deferred self-update..."
        CALL :LOG_MESSAGE "[%TIME%] [INFO] Copying ONLY script.bat (not script.ps1) as requested."
        COPY /Y "%NEW_SCRIPT_BAT%" "%CURRENT_SCRIPT_BAT%" >nul 2>&1
        IF %ERRORLEVEL% EQU 0 (
            CALL :LOG_MESSAGE "[%TIME%] [INFO] script.bat updated successfully."
        ) ELSE (
            CALL :LOG_MESSAGE "[%TIME%] [WARN] Failed to update script.bat, but continuing..."
        )
    )
    
    CALL :LOG_MESSAGE "[%TIME%] [INFO] This launcher will close automatically in 10 seconds..."
    FOR /L %%i IN (10,-1,1) DO (
        CALL :LOG_MESSAGE "[%TIME%] [INFO] Closing in %%i seconds..."
        timeout /t 1 /nobreak >nul
    )
    CALL :LOG_MESSAGE "[%TIME%] [INFO] Batch launcher completed successfully. Window will now close."
    
) ELSE (
    CALL :LOG_MESSAGE "[%TIME%] [ERROR] PowerShell script execution failed with error code: %LAUNCH_RESULT%"
    CALL :LOG_MESSAGE "[%TIME%] [ERROR] Please check the PowerShell script path and permissions."
    pause
)

REM -----------------------------------------------------------------------------
REM Script completed successfully
REM -----------------------------------------------------------------------------

ENDLOCAL
EXIT /B 0