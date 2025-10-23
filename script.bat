@echo off
REM ============================================================================
REM  Windows Maintenance Automation Launcher v2.0 (Enhanced Self-Discovery)
REM  Purpose: Universal launcher for modular Windows maintenance system
REM  Features: Self-discovery environment, dependency management, task scheduling
REM  Requirements: Windows 10/11, Administrator privileges
REM  Author: Windows Maintenance Automation Project
REM ============================================================================

SETLOCAL ENABLEDELAYEDEXPANSION

REM -----------------------------------------------------------------------------
REM Enhanced Logging System
REM -----------------------------------------------------------------------------
GOTO :MAIN_SCRIPT

:LOG_SECTION
REM Log a major section header
SET "SECTION_TITLE=%~1"
ECHO.
ECHO ============================================================
ECHO %SECTION_TITLE%
ECHO ============================================================
IF EXIST "%LOG_FILE%" (
    ECHO. >> "%LOG_FILE%"
    ECHO ============================================================ >> "%LOG_FILE%"
    ECHO %SECTION_TITLE% >> "%LOG_FILE%"
    ECHO ============================================================ >> "%LOG_FILE%"
)
EXIT /B

:LOG_MESSAGE
SET "LOG_TIMESTAMP=%TIME:~0,8%"
SET "LEVEL=%~2"
IF "%LEVEL%"=="" SET "LEVEL=INFO"
SET "COMPONENT=%~3"
IF "%COMPONENT%"=="" SET "COMPONENT=LAUNCHER"

REM Create human-readable log entry
SET "MESSAGE=%~1"

REM Format console output with colors/symbols based on level
IF "%LEVEL%"=="INFO" (
    ECHO [i] %MESSAGE%
    SET "LOG_PREFIX=INFO   "
) ELSE IF "%LEVEL%"=="SUCCESS" (
    ECHO [+] SUCCESS: %MESSAGE%
    SET "LOG_PREFIX=SUCCESS"
) ELSE IF "%LEVEL%"=="ERROR" (
    ECHO [X] ERROR: %MESSAGE%
    SET "LOG_PREFIX=ERROR  "
) ELSE IF "%LEVEL%"=="WARN" (
    ECHO [!] WARNING: %MESSAGE%
    SET "LOG_PREFIX=WARNING"
) ELSE IF "%LEVEL%"=="DEBUG" (
    ECHO [D] DEBUG: %MESSAGE%
    SET "LOG_PREFIX=DEBUG  "
) ELSE (
    ECHO %MESSAGE%
    SET "LOG_PREFIX=INFO   "
)

REM Write to log file with timestamp
IF EXIST "%LOG_FILE%" (
    ECHO [%DATE% %LOG_TIMESTAMP%] [!LOG_PREFIX!] %MESSAGE% >> "%LOG_FILE%" 2>nul
)
EXIT /B

:REFRESH_PATH_FROM_REGISTRY
REM Refresh PATH environment variable from system registry
FOR /F "tokens=2*" %%i IN ('REG QUERY "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" /v PATH 2^>nul') DO (
    SET "SYSTEM_PATH=%%j"
)
FOR /F "tokens=2*" %%i IN ('REG QUERY "HKCU\Environment" /v PATH 2^>nul') DO (
    SET "USER_PATH=%%j"
)
REM Combine system and user PATH
IF DEFINED SYSTEM_PATH IF DEFINED USER_PATH (
    SET "PATH=%SYSTEM_PATH%;%USER_PATH%"
) ELSE IF DEFINED SYSTEM_PATH (
    SET "PATH=%SYSTEM_PATH%"
) ELSE IF DEFINED USER_PATH (
    SET "PATH=%USER_PATH%"
)
EXIT /B

:MAIN_SCRIPT

REM -----------------------------------------------------------------------------
REM Self-Discovery Environment Setup
REM -----------------------------------------------------------------------------
REM Enhanced path detection - works from any location
SET "SCRIPT_PATH=%~f0"
SET "SCRIPT_DIR=%~dp0"
SET "SCRIPT_NAME=%~nx0"
SET "WORKING_DIR=%SCRIPT_DIR%"

REM Initialize log file at script location
SET "LOG_FILE=%SCRIPT_DIR%maintenance.log"

REM Create/clear log file with header
ECHO ============================================================================ > "%LOG_FILE%"
ECHO Windows Maintenance Automation Log >> "%LOG_FILE%"
ECHO Started: %DATE% %TIME% >> "%LOG_FILE%"
ECHO User: %USERNAME% @ Computer: %COMPUTERNAME% >> "%LOG_FILE%"
ECHO Script Location: %SCRIPT_PATH% >> "%LOG_FILE%"
ECHO ============================================================================ >> "%LOG_FILE%"
ECHO. >> "%LOG_FILE%"

CALL :LOG_MESSAGE "Starting Windows Maintenance Automation Launcher v2.0" "INFO" "LAUNCHER"
CALL :LOG_MESSAGE "Log file created at: %LOG_FILE%" "INFO" "LAUNCHER"

REM -----------------------------------------------------------------------------
REM Administrator Privilege Verification
REM -----------------------------------------------------------------------------
CALL :LOG_SECTION "STEP 1: Administrator Privilege Check"
CALL :LOG_MESSAGE "Verifying administrator privileges..." "INFO" "LAUNCHER"

REM Multiple methods for admin detection (improved reliability)
NET SESSION >nul 2>&1
SET "NET_ADMIN_CHECK=%ERRORLEVEL%"

FOR /F "tokens=*" %%i IN ('powershell -Command "([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)" 2^>nul') DO SET PS_ADMIN_CHECK=%%i

SET "IS_ADMIN=NO"
IF %NET_ADMIN_CHECK% EQU 0 SET "IS_ADMIN=YES"
IF "%PS_ADMIN_CHECK%"=="True" SET "IS_ADMIN=YES"

CALL :LOG_MESSAGE "Admin check results: NET=%NET_ADMIN_CHECK%, PS=%PS_ADMIN_CHECK%" "DEBUG" "LAUNCHER"

IF "%IS_ADMIN%"=="NO" (
    CALL :LOG_MESSAGE "Administrator privileges required. Attempting elevation..." "WARN" "LAUNCHER"
    powershell -Command "Start-Process cmd -ArgumentList '/c \"%~f0\"' -Verb RunAs -WindowStyle Normal"
    IF !ERRORLEVEL! NEQ 0 (
        CALL :LOG_MESSAGE "Elevation failed or was cancelled by user" "ERROR" "LAUNCHER"
        EXIT /B 1
    )
    exit
)

CALL :LOG_MESSAGE "Administrator privileges confirmed" "SUCCESS" "LAUNCHER"

REM Robust Script Path Detection for Scheduled Tasks (use the exact running script path)
SET "SCHEDULED_TASK_SCRIPT_PATH="
IF EXIST "!SCRIPT_PATH!" (
    SET "SCHEDULED_TASK_SCRIPT_PATH=!SCRIPT_PATH!"
    CALL :LOG_MESSAGE "Scheduled tasks will use current script path: !SCHEDULED_TASK_SCRIPT_PATH!" "DEBUG" "LAUNCHER"
)
IF NOT DEFINED SCHEDULED_TASK_SCRIPT_PATH IF EXIST "!SCRIPT_DIR!script.bat" (
    SET "SCHEDULED_TASK_SCRIPT_PATH=!SCRIPT_DIR!script.bat"
    CALL :LOG_MESSAGE "Scheduled tasks will use directory script path: !SCHEDULED_TASK_SCRIPT_PATH!" "DEBUG" "LAUNCHER"
)
IF NOT DEFINED SCHEDULED_TASK_SCRIPT_PATH (
    SET "SCHEDULED_TASK_SCRIPT_PATH=!SCRIPT_PATH!"
    CALL :LOG_MESSAGE "Using fallback script path for scheduled tasks: !SCHEDULED_TASK_SCRIPT_PATH!" "WARN" "LAUNCHER"
)

REM Initialize essential environment variables
SET "LOG_FILE=%WORKING_DIR%maintenance.log"
SET "SCRIPT_LOG_FILE=%LOG_FILE%"
SET "REPO_URL=https://github.com/ichimbogdancristian/script_mentenanta/archive/refs/heads/main.zip"
SET "EXTRACT_FOLDER=script_mentenanta-main"
SET "ZIP_FILE=%TEMP%\script_mentenanta.zip"

CALL :LOG_MESSAGE "Environment variables initialized" "DEBUG" "LAUNCHER"
CALL :LOG_MESSAGE "  LOG_FILE: %LOG_FILE%" "DEBUG" "LAUNCHER"
CALL :LOG_MESSAGE "  REPO_URL: %REPO_URL%" "DEBUG" "LAUNCHER"
CALL :LOG_MESSAGE "  EXTRACT_FOLDER: %EXTRACT_FOLDER%" "DEBUG" "LAUNCHER"
CALL :LOG_MESSAGE "  ZIP_FILE: %ZIP_FILE%" "DEBUG" "LAUNCHER"

REM Detect if running from a network location
IF "%SCRIPT_PATH:~0,2%"=="\\" (
    SET "IS_NETWORK_LOCATION=YES"
    CALL :LOG_MESSAGE "Running from network location: %SCRIPT_PATH%" "INFO" "LAUNCHER"
    CALL :LOG_MESSAGE "Network locations are supported - continuing with local execution" "INFO" "LAUNCHER"
)

REM -----------------------------------------------------------------------------
REM Startup Task Cleanup and Pending Restart Handling (Always check first)
REM -----------------------------------------------------------------------------
SET "STARTUP_TASK_NAME=WindowsMaintenanceStartup"
CALL :LOG_MESSAGE "Checking existing startup scheduled task..." "INFO" "LAUNCHER"

REM Clean slate: remove existing startup task if present
schtasks /Query /TN "%STARTUP_TASK_NAME%" >nul 2>&1
IF !ERRORLEVEL! EQU 0 (
    CALL :LOG_MESSAGE "Existing startup task found. Removing: %STARTUP_TASK_NAME%" "INFO" "LAUNCHER"
    schtasks /Delete /TN "%STARTUP_TASK_NAME%" /F >nul 2>&1
    IF !ERRORLEVEL! EQU 0 (
        CALL :LOG_MESSAGE "Startup task removed successfully" "SUCCESS" "LAUNCHER"
    ) ELSE (
        CALL :LOG_MESSAGE "Failed to remove startup task (continuing)" "WARN" "LAUNCHER"
    )
)

REM Detect pending restart specifically due to Windows Updates
CALL :LOG_MESSAGE "Checking for pending restart due to Windows Updates..." "INFO" "LAUNCHER"
SET "RESTART_NEEDED=NO"

REM Prefer PSWindowsUpdate if available for accurate detection
powershell -ExecutionPolicy Bypass -Command "try { if (Get-Module -ListAvailable -Name PSWindowsUpdate) { Import-Module PSWindowsUpdate -Force; $updates = Get-WindowsUpdate -MicrosoftUpdate -AcceptAll -IgnoreReboot; $needs = $updates | Where-Object { $_.RebootRequired -eq $true }; if ($needs) { Write-Host 'RESTART_REQUIRED_UPDATES'; exit 1 } else { Write-Host 'NO_RESTART_REQUIRED_UPDATES'; exit 0 } } else { Write-Host 'PSWINDOWSUPDATE_NOT_AVAILABLE'; exit 2 } } catch { Write-Host 'UPDATE_CHECK_FAILED'; exit 3 }" >nul 2>&1
IF !ERRORLEVEL! EQU 1 SET "RESTART_NEEDED=YES"
IF !ERRORLEVEL! EQU 2 (
    CALL :LOG_MESSAGE "PSWindowsUpdate not available. Falling back to registry reboot flags." "INFO" "LAUNCHER"
    REG QUERY "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired" >nul 2>&1
    IF !ERRORLEVEL! EQU 0 SET "RESTART_NEEDED=YES"
    REG QUERY "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending" >nul 2>&1
    IF !ERRORLEVEL! EQU 0 SET "RESTART_NEEDED=YES"
)

IF /I "%RESTART_NEEDED%"=="YES" (
    CALL :LOG_MESSAGE "Pending restart detected for updates. Creating startup task and restarting..." "WARN" "LAUNCHER"

    REM Ensure any previous startup task is removed
    schtasks /Delete /TN "%STARTUP_TASK_NAME%" /F >nul 2>&1

    REM Create startup task to resume after user logon with admin rights
    CALL :LOG_MESSAGE "Creating ONLOGON startup task with script: !SCHEDULED_TASK_SCRIPT_PATH!" "DEBUG" "LAUNCHER"
    schtasks /Create ^
        /SC ONLOGON ^
        /TN "%STARTUP_TASK_NAME%" ^
        /TR "\"!SCHEDULED_TASK_SCRIPT_PATH!\"" ^
        /RL HIGHEST ^
        /RU "%USERNAME%" ^
        /DELAY 0001:00 ^
        /F >nul 2>&1

    IF !ERRORLEVEL! EQU 0 (
        CALL :LOG_MESSAGE "Startup task created successfully. Restarting system in 10 seconds..." "SUCCESS" "LAUNCHER"
        CALL :LOG_MESSAGE "Press Ctrl+C to cancel restart." "INFO" "LAUNCHER"
        timeout /t 10 >nul 2>&1
        shutdown /r /t 5 /c "System restart required to complete Windows Updates. Maintenance will resume automatically." >nul 2>&1
        EXIT /B 0
    ) ELSE (
        CALL :LOG_MESSAGE "Failed to create startup task. Continuing without automatic restart." "ERROR" "LAUNCHER"
    )
)

REM No pending restart; continue normal execution

REM Check for PowerShell restart flag
IF EXIST "%WORKING_DIR%restart_flag.tmp" (
    CALL :LOG_MESSAGE "Detected PowerShell 7 installation restart flag - cleaning up..." "INFO" "LAUNCHER"
    FOR /F "tokens=*" %%i IN ('TYPE "%WORKING_DIR%restart_flag.tmp" 2^>nul') DO (
        CALL :LOG_MESSAGE "Restart context: %%i" "DEBUG" "LAUNCHER"
    )
    DEL "%WORKING_DIR%restart_flag.tmp" >nul 2>&1
    CALL :LOG_MESSAGE "Script restarted after PowerShell 7 installation - continuing with fresh environment" "SUCCESS" "LAUNCHER"
)

REM Create/Verify monthly maintenance scheduled task before continuing
SET "TASK_NAME=WindowsMaintenanceAutomation"
CALL :LOG_SECTION "STEP 2: Monthly Maintenance Task Setup"
CALL :LOG_MESSAGE "Ensuring monthly maintenance task exists (1st day 01:00)..." "INFO" "LAUNCHER"

schtasks /Query /TN "%TASK_NAME%" >nul 2>&1
IF !ERRORLEVEL! EQU 0 (
    CALL :LOG_MESSAGE "Monthly scheduled task exists: %TASK_NAME%" "SUCCESS" "LAUNCHER"
    FOR /F "tokens=*" %%i IN ('schtasks /Query /TN "%TASK_NAME%" /FO LIST ^| findstr /R /C:"Task To Run" /C:"Next Run Time"') DO (
        CALL :LOG_MESSAGE "Monthly task detail: %%i" "INFO" "LAUNCHER"
    )
) ELSE (
    CALL :LOG_MESSAGE "Creating monthly scheduled task: %TASK_NAME%" "INFO" "LAUNCHER"
    schtasks /Create ^
        /SC MONTHLY ^
        /MO 1 ^
        /D 1 ^
        /TN "%TASK_NAME%" ^
        /TR "\"!SCHEDULED_TASK_SCRIPT_PATH!\"" ^
        /ST 01:00 ^
        /RL HIGHEST ^
        /RU SYSTEM ^
        /F >nul 2>&1
    IF !ERRORLEVEL! EQU 0 (
        CALL :LOG_MESSAGE "Monthly scheduled task created successfully" "SUCCESS" "LAUNCHER"
        FOR /F "tokens=*" %%i IN ('schtasks /Query /TN "%TASK_NAME%" /FO LIST ^| findstr /R /C:"Task To Run" /C:"Next Run Time"') DO (
            CALL :LOG_MESSAGE "Monthly task detail: %%i" "INFO" "LAUNCHER"
        )
    ) ELSE (
        CALL :LOG_MESSAGE "Monthly scheduled task creation failed - continuing without scheduling" "WARN" "LAUNCHER"
    )
)

REM -----------------------------------------------------------------------------
REM System Requirements Verification
REM -----------------------------------------------------------------------------
:SYSTEM_REQUIREMENTS
CALL :LOG_MESSAGE "Verifying system requirements..." "INFO" "LAUNCHER"

REM -----------------------------------------------------------------------------
REM System Requirements Verification (Windows version and PowerShell)
REM -----------------------------------------------------------------------------
CALL :LOG_SECTION "STEP 3: System Requirements Verification"

REM Windows version detection
FOR /F "tokens=*" %%i IN ('powershell -Command "try { (Get-CimInstance Win32_OperatingSystem).Version } catch { (Get-WmiObject Win32_OperatingSystem).Version }"') DO SET OS_VERSION=%%i
CALL :LOG_MESSAGE "Windows version: %OS_VERSION%" "INFO" "LAUNCHER"

REM PowerShell version check
FOR /F "tokens=*" %%i IN ('powershell -Command "$PSVersionTable.PSVersion.Major" 2^>nul') DO SET PS_VERSION=%%i
    IF "%PS_VERSION%"=="" SET PS_VERSION=0
CALL :LOG_MESSAGE "PowerShell version: %PS_VERSION%" "INFO" "LAUNCHER"

IF %PS_VERSION% LSS 5 (
    CALL :LOG_MESSAGE "PowerShell 5.1 or higher required. Current: %PS_VERSION%" "ERROR" "LAUNCHER"
    CALL :LOG_MESSAGE "Please install Windows PowerShell 5.1 or PowerShell 7+" "ERROR" "LAUNCHER"
    EXIT /B 2
)

CALL :LOG_MESSAGE "System requirements verified successfully" "SUCCESS" "LAUNCHER"

REM -----------------------------------------------------------------------------
REM Winget Installation and Verification (Critical for PowerShell 7 installation)
REM -----------------------------------------------------------------------------
:WINGET_INSTALLATION
CALL :LOG_SECTION "STEP 4: Winget Package Manager Setup"
CALL :LOG_MESSAGE "Checking winget availability..." "INFO" "LAUNCHER"
    
SET "WINGET_AVAILABLE=NO"
SET "WINGET_EXE="

REM Initial winget check (PATH and WindowsApps)
winget --version >nul 2>&1
IF !ERRORLEVEL! EQU 0 (
    SET "WINGET_EXE=winget"
    SET "WINGET_AVAILABLE=YES"
    CALL :LOG_MESSAGE "Winget found via PATH" "DEBUG" "LAUNCHER"
) ELSE (
    IF EXIST "%LocalAppData%\Microsoft\WindowsApps\winget.exe" (
        "%LocalAppData%\Microsoft\WindowsApps\winget.exe" --version >nul 2>&1
        IF !ERRORLEVEL! EQU 0 (
            SET "WINGET_EXE=%LocalAppData%\Microsoft\WindowsApps\winget.exe"
            SET "WINGET_AVAILABLE=YES"
            CALL :LOG_MESSAGE "Winget found via WindowsApps alias" "DEBUG" "LAUNCHER"
        )
    )
)

REM Install winget if not available
IF "%WINGET_AVAILABLE%"=="NO" (
    CALL :LOG_MESSAGE "Winget not found. Attempting to install winget..." "INFO" "LAUNCHER"
    
    REM Method 1: Try installing App Installer via PowerShell
    powershell -NoProfile -ExecutionPolicy Bypass -Command "try { if (Get-Command Get-AppxPackage -ErrorAction SilentlyContinue) { $appInstaller = Get-AppxPackage -Name 'Microsoft.DesktopAppInstaller' -ErrorAction SilentlyContinue; if (-not $appInstaller) { Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe -ErrorAction Stop; Write-Host 'APPINSTALLER_REGISTERED' } else { Write-Host 'APPINSTALLER_EXISTS' } } else { Write-Host 'APPX_NOT_SUPPORTED' } } catch { Write-Host 'APPINSTALLER_FAILED'; exit 1 }" >nul 2>&1
    IF !ERRORLEVEL! EQU 0 (
        CALL :LOG_MESSAGE "App Installer registration attempted" "INFO" "LAUNCHER"
        TIMEOUT /T 5 >nul 2>&1
    ) ELSE (
        CALL :LOG_MESSAGE "App Installer registration failed" "WARN" "LAUNCHER"
    )
    
    REM Check if Method 1 succeeded
    winget --version >nul 2>&1
    IF !ERRORLEVEL! NEQ 0 (
        REM Method 2: PowerShell Gallery Microsoft.WinGet.Client module
        CALL :LOG_MESSAGE "Attempting winget installation via PowerShell Gallery (Microsoft.WinGet.Client)..." "INFO" "LAUNCHER"
        powershell -NoProfile -ExecutionPolicy Bypass -Command "try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; $ProgressPreference='SilentlyContinue'; Install-PackageProvider -Name NuGet -Force -Scope CurrentUser | Out-Null; Install-Module -Name Microsoft.WinGet.Client -Force -Repository PSGallery -Scope CurrentUser | Out-Null; Import-Module Microsoft.WinGet.Client -Force; Repair-WinGetPackageManager -AllUsers; Write-Host 'WINGET_PSMODULE_SUCCESS' } catch { Write-Host 'WINGET_PSMODULE_FAILED'; exit 1 }"
        IF !ERRORLEVEL! EQU 0 (
            CALL :LOG_MESSAGE "PowerShell Gallery method completed - verifying..." "INFO" "LAUNCHER"
            TIMEOUT /T 5 >nul 2>&1
            
            winget --version >nul 2>&1
            IF !ERRORLEVEL! EQU 0 (
                SET "WINGET_EXE=winget"
                SET "WINGET_AVAILABLE=YES"
                CALL :LOG_MESSAGE "Winget verified working after PowerShell Gallery installation" "SUCCESS" "LAUNCHER"
            ) ELSE IF EXIST "%LocalAppData%\Microsoft\WindowsApps\winget.exe" (
                "%LocalAppData%\Microsoft\WindowsApps\winget.exe" --version >nul 2>&1
                IF !ERRORLEVEL! EQU 0 (
                    SET "WINGET_EXE=%LocalAppData%\Microsoft\WindowsApps\winget.exe"
                    SET "WINGET_AVAILABLE=YES"
                    CALL :LOG_MESSAGE "Winget working via WindowsApps after PowerShell Gallery" "SUCCESS" "LAUNCHER"
                )
            )
        )
    ) ELSE (
        CALL :LOG_MESSAGE "Method 1 succeeded - winget now available" "SUCCESS" "LAUNCHER"
        SET "WINGET_EXE=winget"
        SET "WINGET_AVAILABLE=YES"
    )
    
    REM Check if Methods 1 and 2 succeeded
    IF "%WINGET_AVAILABLE%"=="NO" (
        winget --version >nul 2>&1
        IF !ERRORLEVEL! NEQ 0 (
            REM Method 3: Manual MSIX download with multiple fallback URLs
            CALL :LOG_MESSAGE "Attempting manual App Installer MSIX download with fallback URLs..." "INFO" "LAUNCHER"
            DEL /Q "%WORKING_DIR%AppInstaller.msixbundle" >nul 2>&1
            SET "MSIX_DOWNLOADED=NO"
            
            REM Try URL 1: aka.ms shortlink (Microsoft official redirect)
            CALL :LOG_MESSAGE "Trying URL 1: aka.ms/getwinget (Microsoft official redirect)..." "DEBUG" "LAUNCHER"
            powershell -NoProfile -ExecutionPolicy Bypass -Command "try { $ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri 'https://aka.ms/getwinget' -OutFile '%WORKING_DIR%AppInstaller.msixbundle' -UseBasicParsing -TimeoutSec 30; Write-Host 'PRIMARY_DOWNLOADED' } catch { Write-Host 'PRIMARY_FAILED'; exit 1 }" >nul 2>&1
            IF !ERRORLEVEL! EQU 0 IF EXIST "%WORKING_DIR%AppInstaller.msixbundle" (
                SET "MSIX_DOWNLOADED=YES"
                CALL :LOG_MESSAGE "MSIX downloaded successfully from aka.ms/getwinget" "SUCCESS" "LAUNCHER"
            ) ELSE (
                CALL :LOG_MESSAGE "URL 1 failed - aka.ms/getwinget unreachable" "WARN" "LAUNCHER"
                DEL /Q "%WORKING_DIR%AppInstaller.msixbundle" >nul 2>&1
            )
            
            REM Try URL 2: GitHub latest release (if URL 1 failed)
            IF "%MSIX_DOWNLOADED%"=="NO" (
                CALL :LOG_MESSAGE "Trying URL 2: GitHub latest release..." "DEBUG" "LAUNCHER"
                powershell -NoProfile -ExecutionPolicy Bypass -Command "try { $ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri 'https://github.com/microsoft/winget-cli/releases/latest/download/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle' -OutFile '%WORKING_DIR%AppInstaller.msixbundle' -UseBasicParsing -TimeoutSec 30; Write-Host 'GITHUB_DOWNLOADED' } catch { Write-Host 'GITHUB_FAILED'; exit 1 }" >nul 2>&1
                IF !ERRORLEVEL! EQU 0 IF EXIST "%WORKING_DIR%AppInstaller.msixbundle" (
                    SET "MSIX_DOWNLOADED=YES"
                    CALL :LOG_MESSAGE "MSIX downloaded successfully from GitHub latest" "SUCCESS" "LAUNCHER"
                ) ELSE (
                    CALL :LOG_MESSAGE "URL 2 failed - GitHub latest release unreachable" "WARN" "LAUNCHER"
                    DEL /Q "%WORKING_DIR%AppInstaller.msixbundle" >nul 2>&1
                )
            )
            
            REM Try URL 3: GitHub v1.11.510 (stable known version)
            IF "%MSIX_DOWNLOADED%"=="NO" (
                CALL :LOG_MESSAGE "Trying URL 3: GitHub v1.11.510 (stable known version)..." "DEBUG" "LAUNCHER"
                powershell -NoProfile -ExecutionPolicy Bypass -Command "try { $ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri 'https://github.com/microsoft/winget-cli/releases/download/v1.11.510/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle' -OutFile '%WORKING_DIR%AppInstaller.msixbundle' -UseBasicParsing -TimeoutSec 30; Write-Host 'V1_11_DOWNLOADED' } catch { Write-Host 'V1_11_FAILED'; exit 1 }" >nul 2>&1
                IF !ERRORLEVEL! EQU 0 IF EXIST "%WORKING_DIR%AppInstaller.msixbundle" (
                    SET "MSIX_DOWNLOADED=YES"
                    CALL :LOG_MESSAGE "MSIX downloaded successfully from GitHub v1.11.510" "SUCCESS" "LAUNCHER"
                ) ELSE (
                    CALL :LOG_MESSAGE "URL 3 failed - GitHub v1.11.510 unreachable" "WARN" "LAUNCHER"
                    DEL /Q "%WORKING_DIR%AppInstaller.msixbundle" >nul 2>&1
                )
            )
            
            REM Try URL 4: GitHub v1.10.1921 (older stable fallback)
            IF "%MSIX_DOWNLOADED%"=="NO" (
                CALL :LOG_MESSAGE "Trying URL 4: GitHub v1.10.1921 (older stable)..." "DEBUG" "LAUNCHER"
                powershell -NoProfile -ExecutionPolicy Bypass -Command "try { $ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri 'https://github.com/microsoft/winget-cli/releases/download/v1.10.1921/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle' -OutFile '%WORKING_DIR%AppInstaller.msixbundle' -UseBasicParsing -TimeoutSec 30; Write-Host 'V1_10_DOWNLOADED' } catch { Write-Host 'V1_10_FAILED'; exit 1 }" >nul 2>&1
                IF !ERRORLEVEL! EQU 0 IF EXIST "%WORKING_DIR%AppInstaller.msixbundle" (
                    SET "MSIX_DOWNLOADED=YES"
                    CALL :LOG_MESSAGE "MSIX downloaded successfully from GitHub v1.10.1921" "SUCCESS" "LAUNCHER"
                ) ELSE (
                    CALL :LOG_MESSAGE "URL 4 failed - GitHub v1.10.1921 unreachable" "WARN" "LAUNCHER"
                    DEL /Q "%WORKING_DIR%AppInstaller.msixbundle" >nul 2>&1
                )
            )
            
            REM Try URL 5: GitHub v1.9.1901 (maximum compatibility fallback)
            IF "%MSIX_DOWNLOADED%"=="NO" (
                CALL :LOG_MESSAGE "Trying URL 5: GitHub v1.9.1901 (max compatibility)..." "DEBUG" "LAUNCHER"
                powershell -NoProfile -ExecutionPolicy Bypass -Command "try { $ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri 'https://github.com/microsoft/winget-cli/releases/download/v1.9.1901/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle' -OutFile '%WORKING_DIR%AppInstaller.msixbundle' -UseBasicParsing -TimeoutSec 30; Write-Host 'V1_9_DOWNLOADED' } catch { Write-Host 'V1_9_FAILED'; exit 1 }" >nul 2>&1
                IF !ERRORLEVEL! EQU 0 IF EXIST "%WORKING_DIR%AppInstaller.msixbundle" (
                    SET "MSIX_DOWNLOADED=YES"
                    CALL :LOG_MESSAGE "MSIX downloaded successfully from GitHub v1.9.1901" "SUCCESS" "LAUNCHER"
                ) ELSE (
                    CALL :LOG_MESSAGE "URL 5 failed - All winget download URLs exhausted" "ERROR" "LAUNCHER"
                    DEL /Q "%WORKING_DIR%AppInstaller.msixbundle" >nul 2>&1
                )
            )
            
            REM Install MSIX if downloaded from any URL
            IF EXIST "%WORKING_DIR%AppInstaller.msixbundle" (
                powershell -NoProfile -ExecutionPolicy Bypass -Command "try { Add-AppxPackage -Path '%WORKING_DIR%AppInstaller.msixbundle' -ErrorAction Stop; Write-Host 'MSIX_INSTALLED' } catch { Write-Host 'MSIX_FAILED'; exit 1 }" >nul 2>&1
                IF !ERRORLEVEL! EQU 0 (
                    CALL :LOG_MESSAGE "App Installer MSIX installed successfully" "SUCCESS" "LAUNCHER"
                    DEL /Q "%WORKING_DIR%AppInstaller.msixbundle" >nul 2>&1
                    TIMEOUT /T 3 >nul 2>&1
                    
                    winget --version >nul 2>&1
                    IF !ERRORLEVEL! EQU 0 (
                        SET "WINGET_EXE=winget"
                        SET "WINGET_AVAILABLE=YES"
                    )
                ) ELSE (
                    CALL :LOG_MESSAGE "MSIX installation failed" "WARN" "LAUNCHER"
                )
            )
        ) ELSE (
            SET "WINGET_EXE=winget"
            SET "WINGET_AVAILABLE=YES"
        )
    )
)

REM Final winget status with functionality verification
IF "%WINGET_AVAILABLE%"=="YES" (
    REM Verify winget is actually functional, not just present
    "%WINGET_EXE%" --version >nul 2>&1
    IF !ERRORLEVEL! EQU 0 (
        FOR /F "tokens=*" %%i IN ('"%WINGET_EXE%" --version 2^>nul') DO SET WINGET_VERSION=%%i
        CALL :LOG_MESSAGE "Winget ready and functional: %WINGET_VERSION%" "SUCCESS" "LAUNCHER"
    ) ELSE (
        CALL :LOG_MESSAGE "Winget executable found but not functional - marking as unavailable" "WARN" "LAUNCHER"
        SET "WINGET_AVAILABLE=NO"
        SET "WINGET_EXE="
    )
) ELSE (
    CALL :LOG_MESSAGE "Winget not available - will use alternative methods for PowerShell 7" "WARN" "LAUNCHER"
)

REM -----------------------------------------------------------------------------
REM Repository Download and Extraction (Moved before structure discovery)
REM -----------------------------------------------------------------------------
:DOWNLOAD_REPOSITORY
CALL :LOG_MESSAGE "Downloading latest repository from GitHub..." "INFO" "LAUNCHER"

REM Clean up existing files
IF EXIST "%ZIP_FILE%" DEL /Q "%ZIP_FILE%" >nul 2>&1
IF EXIST "%WORKING_DIR%%EXTRACT_FOLDER%" RMDIR /S /Q "%WORKING_DIR%%EXTRACT_FOLDER%" >nul 2>&1

REM Download repository
CALL :LOG_MESSAGE "Downloading from: %REPO_URL%" "DEBUG" "LAUNCHER"
powershell -ExecutionPolicy Bypass -Command "try { $ProgressPreference = 'SilentlyContinue'; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri '%REPO_URL%' -OutFile '%ZIP_FILE%' -UseBasicParsing; Write-Host 'DOWNLOAD_SUCCESS' } catch { Write-Host 'DOWNLOAD_FAILED'; Write-Error $_.Exception.Message; exit 1 }"

IF !ERRORLEVEL! NEQ 0 (
    CALL :LOG_MESSAGE "Repository download failed. Check internet connection." "ERROR" "LAUNCHER"
    EXIT /B 3
)

IF NOT EXIST "%ZIP_FILE%" (
    CALL :LOG_MESSAGE "Download verification failed - ZIP file not found" "ERROR" "LAUNCHER"
    EXIT /B 3
)

CALL :LOG_MESSAGE "Repository downloaded successfully" "SUCCESS" "LAUNCHER"

REM Extract repository
CALL :LOG_MESSAGE "Extracting repository..." "INFO" "LAUNCHER"
powershell -ExecutionPolicy Bypass -Command "try { Add-Type -AssemblyName System.IO.Compression.FileSystem; [System.IO.Compression.ZipFile]::ExtractToDirectory('%ZIP_FILE%', '%WORKING_DIR%'); Write-Host 'EXTRACTION_SUCCESS' } catch { Write-Host 'EXTRACTION_FAILED'; Write-Error $_.Exception.Message; exit 1 }"

IF !ERRORLEVEL! NEQ 0 (
    CALL :LOG_MESSAGE "Repository extraction failed" "ERROR" "LAUNCHER"
    EXIT /B 3
)

REM Verify extraction
SET "EXTRACTED_PATH=%WORKING_DIR%%EXTRACT_FOLDER%"
IF EXIST "%EXTRACTED_PATH%" (
    CALL :LOG_MESSAGE "Repository extracted to: %EXTRACTED_PATH%" "SUCCESS" "LAUNCHER"
    
    REM Update working directory to extracted folder for proper module loading
    SET "WORKING_DIR=%EXTRACTED_PATH%\"
    SET "WORKING_DIRECTORY=%WORKING_DIR%"
    CALL :LOG_MESSAGE "Updated working directory to: %WORKING_DIR%" "INFO" "LAUNCHER"
    
    REM Set orchestrator path within the extracted folder
    IF EXIST "%EXTRACTED_PATH%\MaintenanceOrchestrator.ps1" (
        SET "ORCHESTRATOR_PATH=%EXTRACTED_PATH%\MaintenanceOrchestrator.ps1"
        CALL :LOG_MESSAGE "Using extracted orchestrator" "INFO" "LAUNCHER"
    ) ELSE IF EXIST "%EXTRACTED_PATH%\script.ps1" (
        SET "ORCHESTRATOR_PATH=%EXTRACTED_PATH%\script.ps1"
        CALL :LOG_MESSAGE "Using extracted legacy orchestrator" "INFO" "LAUNCHER"
    ) ELSE (
        CALL :LOG_MESSAGE "No valid orchestrator found in extracted files" "ERROR" "LAUNCHER"
        EXIT /B 3
    )
) ELSE (
    CALL :LOG_MESSAGE "Repository extraction verification failed" "ERROR" "LAUNCHER"
    EXIT /B 3
)

REM Clean up
DEL /Q "%ZIP_FILE%" >nul 2>&1

REM Priority 1: Use local files if available (faster, no internet dependency)
IF EXIST "%SCRIPT_DIR%MaintenanceOrchestrator.ps1" (
    SET "WORKING_DIR=%SCRIPT_DIR%"
    SET "WORKING_DIRECTORY=%WORKING_DIR%"
    CALL :LOG_MESSAGE "Using local repository files for execution: %WORKING_DIR%" "SUCCESS" "LAUNCHER"
) ELSE (
    REM Priority 2: Use extracted repository as fallback
    SET "WORKING_DIR=%EXTRACTED_PATH%\"
    SET "WORKING_DIRECTORY=%WORKING_DIR%"
    CALL :LOG_MESSAGE "Using extracted repository for execution: %WORKING_DIR%" "INFO" "LAUNCHER"
    
    REM Optional: Update script.bat from extracted repo for next run (if different)
    IF EXIST "%EXTRACTED_PATH%\script.bat" (
        FC /B "%SCRIPT_DIR%script.bat" "%EXTRACTED_PATH%\script.bat" >nul 2>&1
        IF !ERRORLEVEL! NEQ 0 (
            CALL :LOG_MESSAGE "Updating script.bat from repository for next run..." "INFO" "LAUNCHER"
            COPY /Y "%EXTRACTED_PATH%\script.bat" "%SCRIPT_DIR%script.bat" >nul 2>&1
            IF !ERRORLEVEL! EQU 0 (
                CALL :LOG_MESSAGE "script.bat updated successfully (will be used on next execution)" "SUCCESS" "LAUNCHER"
            ) ELSE (
                CALL :LOG_MESSAGE "Failed to update script.bat - continuing with current version" "WARN" "LAUNCHER"
            )
        )
    )
)

REM -----------------------------------------------------------------------------
REM Project Structure Validation (Extracted Repository)
REM -----------------------------------------------------------------------------
CALL :LOG_MESSAGE "Validating extracted repository structure..." "INFO" "LAUNCHER"

SET "STRUCTURE_VALID=YES"
SET "COMPONENTS_FOUND=0"

REM Validate orchestrator exists
IF EXIST "%WORKING_DIR%MaintenanceOrchestrator.ps1" (
    SET "ORCHESTRATOR_PATH=%WORKING_DIR%MaintenanceOrchestrator.ps1"
    CALL :LOG_MESSAGE "✓ Found orchestrator: MaintenanceOrchestrator.ps1" "SUCCESS" "LAUNCHER"
    SET /A COMPONENTS_FOUND+=1
) ELSE IF EXIST "%WORKING_DIR%script.ps1" (
    SET "ORCHESTRATOR_PATH=%WORKING_DIR%script.ps1"
    CALL :LOG_MESSAGE "✓ Found legacy orchestrator: script.ps1" "INFO" "LAUNCHER"
    SET /A COMPONENTS_FOUND+=1
) ELSE (
    CALL :LOG_MESSAGE "✗ No PowerShell orchestrator found in extracted repository" "ERROR" "LAUNCHER"
    SET "STRUCTURE_VALID=NO"
)

REM Validate config directory and critical files
IF EXIST "%WORKING_DIR%config" (
    CALL :LOG_MESSAGE "✓ Found configuration directory" "SUCCESS" "LAUNCHER"
    SET /A COMPONENTS_FOUND+=1
    
    IF EXIST "%WORKING_DIR%config\main-config.json" (
        CALL :LOG_MESSAGE "  ✓ main-config.json present" "SUCCESS" "LAUNCHER"
    ) ELSE (
        CALL :LOG_MESSAGE "  ✗ main-config.json missing" "ERROR" "LAUNCHER"
        SET "STRUCTURE_VALID=NO"
    )
    
    IF EXIST "%WORKING_DIR%config\bloatware-list.json" (
        CALL :LOG_MESSAGE "  ✓ bloatware-list.json present" "SUCCESS" "LAUNCHER"
    ) ELSE (
        CALL :LOG_MESSAGE "  ✗ bloatware-list.json missing" "WARN" "LAUNCHER"
    )
) ELSE (
    CALL :LOG_MESSAGE "✗ Configuration directory not found" "ERROR" "LAUNCHER"
    SET "STRUCTURE_VALID=NO"
)

REM Validate modules directory and core modules
IF EXIST "%WORKING_DIR%modules" (
    CALL :LOG_MESSAGE "✓ Found modules directory" "SUCCESS" "LAUNCHER"
    SET /A COMPONENTS_FOUND+=1
    
    IF EXIST "%WORKING_DIR%modules\core" (
        CALL :LOG_MESSAGE "  ✓ Core modules directory present" "SUCCESS" "LAUNCHER"
        
        IF EXIST "%WORKING_DIR%modules\core\CoreInfrastructure.psm1" (
            CALL :LOG_MESSAGE "    ✓ CoreInfrastructure.psm1 present" "SUCCESS" "LAUNCHER"
        ) ELSE (
            CALL :LOG_MESSAGE "    ✗ CoreInfrastructure.psm1 missing" "ERROR" "LAUNCHER"
            SET "STRUCTURE_VALID=NO"
        )
        
        IF EXIST "%WORKING_DIR%modules\core\UserInterface.psm1" (
            CALL :LOG_MESSAGE "    ✓ UserInterface.psm1 present" "SUCCESS" "LAUNCHER"
        ) ELSE (
            CALL :LOG_MESSAGE "    ✗ UserInterface.psm1 missing" "WARN" "LAUNCHER"
        )
        
        IF EXIST "%WORKING_DIR%modules\core\ReportGenerator.psm1" (
            CALL :LOG_MESSAGE "    ✓ ReportGenerator.psm1 present" "SUCCESS" "LAUNCHER"
        ) ELSE (
            CALL :LOG_MESSAGE "    ✗ ReportGenerator.psm1 missing" "WARN" "LAUNCHER"
        )
    ) ELSE (
        CALL :LOG_MESSAGE "  ✗ Core modules directory missing" "ERROR" "LAUNCHER"
        SET "STRUCTURE_VALID=NO"
    )
    
    IF EXIST "%WORKING_DIR%modules\type1" (
        CALL :LOG_MESSAGE "  ✓ Type1 modules directory present" "SUCCESS" "LAUNCHER"
    ) ELSE (
        CALL :LOG_MESSAGE "  ✗ Type1 modules directory missing" "WARN" "LAUNCHER"
    )
    
    IF EXIST "%WORKING_DIR%modules\type2" (
        CALL :LOG_MESSAGE "  ✓ Type2 modules directory present" "SUCCESS" "LAUNCHER"
    ) ELSE (
        CALL :LOG_MESSAGE "  ✗ Type2 modules directory missing" "WARN" "LAUNCHER"
    )
) ELSE (
    CALL :LOG_MESSAGE "✗ Modules directory not found" "ERROR" "LAUNCHER"
    SET "STRUCTURE_VALID=NO"
)

REM Final validation check
CALL :LOG_MESSAGE "Project structure verification: %COMPONENTS_FOUND%/3 major components found" "INFO" "LAUNCHER"

IF "%STRUCTURE_VALID%"=="NO" (
    CALL :LOG_MESSAGE "CRITICAL: Extracted repository structure is incomplete or corrupted" "ERROR" "LAUNCHER"
    CALL :LOG_MESSAGE "Required components missing from downloaded repository" "ERROR" "LAUNCHER"
    CALL :LOG_MESSAGE "This script requires a complete project structure with:" "ERROR" "LAUNCHER"
    CALL :LOG_MESSAGE "  - MaintenanceOrchestrator.ps1 (orchestrator)" "ERROR" "LAUNCHER"
    CALL :LOG_MESSAGE "  - config/ directory with main-config.json" "ERROR" "LAUNCHER"
    CALL :LOG_MESSAGE "  - modules/core/ with CoreInfrastructure.psm1" "ERROR" "LAUNCHER"
    CALL :LOG_MESSAGE "" "ERROR" "LAUNCHER"
    CALL :LOG_MESSAGE "The script cannot continue without these components." "ERROR" "LAUNCHER"
    EXIT /B 4
) ELSE (
    CALL :LOG_MESSAGE "Repository structure validated successfully - ready for execution" "SUCCESS" "LAUNCHER"
)

REM -----------------------------------------------------------------------------
REM Enhanced Dependency Management
REM -----------------------------------------------------------------------------
:DEPENDENCY_MANAGEMENT
CALL :LOG_SECTION "STEP 5: Dependency Management"
CALL :LOG_MESSAGE "Starting dependency management..." "INFO" "LAUNCHER"

REM -----------------------------------------------------------------------------
REM PowerShell 7+ Installation and Detection (Critical for Orchestrator)
REM -----------------------------------------------------------------------------
CALL :LOG_MESSAGE "Checking PowerShell 7+ availability..." "INFO" "LAUNCHER"

SET "PS7_FOUND=NO"
REM Note: WINGET_AVAILABLE and WINGET_EXE are already set from earlier winget installation section
REM DO NOT reset these variables here - they contain the winget status from lines 250-441

REM Method 1: Direct PowerShell 7 check
pwsh.exe -Version >nul 2>&1
IF !ERRORLEVEL! EQU 0 (
    FOR /F "tokens=*" %%i IN ('pwsh.exe -Command "$PSVersionTable.PSVersion.Major" 2^>nul') DO SET PS_MAJOR=%%i
    IF DEFINED PS_MAJOR IF !PS_MAJOR! GEQ 7 (
        SET "PS7_FOUND=YES"
        CALL :LOG_MESSAGE "PowerShell 7+ detected via direct command" "DEBUG" "LAUNCHER"
    )
)

REM Method 2: Check default installation path
IF "%PS7_FOUND%"=="NO" (
    IF EXIST "%ProgramFiles%\PowerShell\7\pwsh.exe" (
        "%ProgramFiles%\PowerShell\7\pwsh.exe" -Version >nul 2>&1
        IF !ERRORLEVEL! EQU 0 (
            SET "PS7_FOUND=YES"
            CALL :LOG_MESSAGE "PowerShell 7 detected at default path" "DEBUG" "LAUNCHER"
        )
    )
)

REM Method 3: Check WindowsApps for App Execution Alias
IF "%PS7_FOUND%"=="NO" (
    IF EXIST "%LocalAppData%\Microsoft\WindowsApps\pwsh.exe" (
        "%LocalAppData%\Microsoft\WindowsApps\pwsh.exe" -Version >nul 2>&1
        IF !ERRORLEVEL! EQU 0 (
            SET "PS7_FOUND=YES"
            CALL :LOG_MESSAGE "PowerShell 7 detected via WindowsApps alias" "DEBUG" "LAUNCHER"
        )
    )
)

REM Final check - re-verify PowerShell 7 availability before installation attempts
pwsh.exe -Version >nul 2>&1
IF !ERRORLEVEL! EQU 0 (
    SET "PS7_FOUND=YES"
    CALL :LOG_MESSAGE "PowerShell 7 detected - skipping installation" "SUCCESS" "LAUNCHER"
)

IF "%PS7_FOUND%"=="NO" (
    CALL :LOG_MESSAGE "PowerShell 7 not found. Attempting installation..." "INFO" "LAUNCHER"
    SET "INSTALL_STATUS=FAILED"
    SET "WINGET_LOG=%WORKING_DIR%winget-pwsh-install.log"

    REM 1) Try installing PowerShell via winget (if available)
    IF "%WINGET_AVAILABLE%"=="YES" (
        CALL :LOG_MESSAGE "Installing PowerShell 7 via winget..." "INFO" "LAUNCHER"
        "%WINGET_EXE%" install Microsoft.PowerShell --silent --accept-package-agreements --accept-source-agreements >nul 2>&1
        IF !ERRORLEVEL! EQU 0 (
            CALL :LOG_MESSAGE "PowerShell 7 installed successfully via winget" "SUCCESS" "LAUNCHER"
            SET "INSTALL_STATUS=SUCCESS"
            SET "PS7_FOUND=YES"
            
            REM Refresh PATH environment to pick up newly installed PowerShell
            CALL :LOG_MESSAGE "Refreshing PATH environment after PowerShell 7 installation..." "DEBUG" "LAUNCHER"
            CALL :REFRESH_PATH_FROM_REGISTRY
        ) ELSE (
            CALL :LOG_MESSAGE "PowerShell 7 installation via winget failed (exit code: !ERRORLEVEL!)" "WARN" "LAUNCHER"
        )
    ) ELSE (
        CALL :LOG_MESSAGE "Winget not available for PowerShell 7 installation" "WARN" "LAUNCHER"
    )

    REM 2) Try Chocolatey (prioritize existing installation or install it first)
    IF NOT "%INSTALL_STATUS%"=="SUCCESS" (
        REM Check if Chocolatey is available
        SET "CHOCO_EXE=choco"
        IF EXIST "%ProgramData%\chocolatey\bin\choco.exe" SET "CHOCO_EXE=%ProgramData%\chocolatey\bin\choco.exe"
        
        "%CHOCO_EXE%" --version >nul 2>&1
        IF !ERRORLEVEL! EQU 0 (
            CALL :LOG_MESSAGE "Chocolatey found - installing PowerShell 7..." "INFO" "LAUNCHER"
            "%CHOCO_EXE%" install powershell-core -y --no-progress
            IF !ERRORLEVEL! EQU 0 (
                CALL :LOG_MESSAGE "PowerShell 7 installed successfully via Chocolatey" "SUCCESS" "LAUNCHER"
                SET "INSTALL_STATUS=SUCCESS"
                SET "PS7_FOUND=YES"
                
                REM Refresh PATH after installation
                CALL :LOG_MESSAGE "Refreshing PATH after PowerShell 7 installation..." "DEBUG" "LAUNCHER"
                CALL :REFRESH_PATH_FROM_REGISTRY
            ) ELSE (
                CALL :LOG_MESSAGE "Chocolatey failed to install PowerShell 7" "WARN" "LAUNCHER"
            )
        ) ELSE (
            CALL :LOG_MESSAGE "Chocolatey not available - installing Chocolatey first..." "INFO" "LAUNCHER"
            
            REM Try primary Chocolatey installation URL
            CALL :LOG_MESSAGE "Attempting Chocolatey installation from community.chocolatey.org..." "DEBUG" "LAUNCHER"
            powershell -NoProfile -ExecutionPolicy Bypass -Command "try { Set-ExecutionPolicy Bypass -Scope Process -Force; [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; iex ((New-Object Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1')); Write-Host 'CHOCO_INSTALLED' } catch { Write-Host 'CHOCO_INSTALL_FAILED'; exit 1 }"
            
            REM If primary URL failed, try GitHub mirror fallback
            IF !ERRORLEVEL! NEQ 0 (
                CALL :LOG_MESSAGE "Primary Chocolatey URL failed - trying GitHub mirror..." "WARN" "LAUNCHER"
                powershell -NoProfile -ExecutionPolicy Bypass -Command "try { Set-ExecutionPolicy Bypass -Scope Process -Force; [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; iex ((New-Object Net.WebClient).DownloadString('https://raw.githubusercontent.com/chocolatey/choco/master/setup.ps1')); Write-Host 'CHOCO_INSTALLED' } catch { Write-Host 'CHOCO_INSTALL_GITHUB_FAILED'; exit 1 }"
            )
            
            IF !ERRORLEVEL! EQU 0 (
                CALL :LOG_MESSAGE "Chocolatey installed successfully - now installing PowerShell 7..." "SUCCESS" "LAUNCHER"
                TIMEOUT /T 5 >nul 2>&1
                
                REM Update Chocolatey path after installation and refresh environment
                SET "CHOCO_EXE=%ProgramData%\chocolatey\bin\choco.exe"
                IF NOT EXIST "!CHOCO_EXE!" (
                    CALL :LOG_MESSAGE "Chocolatey executable not found after installation" "ERROR" "LAUNCHER"
                    GOTO :SKIP_CHOCO_PS7_INSTALL
                )
                
                "!CHOCO_EXE!" install powershell-core -y --no-progress
                IF !ERRORLEVEL! EQU 0 (
                    CALL :LOG_MESSAGE "PowerShell 7 installed successfully via newly installed Chocolatey" "SUCCESS" "LAUNCHER"
                    SET "INSTALL_STATUS=SUCCESS"
                    SET "PS7_FOUND=YES"
                    
                    REM Refresh PATH after installation
                    CALL :LOG_MESSAGE "Refreshing PATH after PowerShell 7 installation..." "DEBUG" "LAUNCHER"
                    CALL :REFRESH_PATH_FROM_REGISTRY
                ) ELSE (
                    CALL :LOG_MESSAGE "PowerShell 7 installation failed even with fresh Chocolatey" "WARN" "LAUNCHER"
                )
                
                :SKIP_CHOCO_PS7_INSTALL
            ) ELSE (
                CALL :LOG_MESSAGE "Chocolatey installation failed - proceeding to MSI fallback" "WARN" "LAUNCHER"
            )
        )
    )

    REM 3) MSI fallback from GitHub Releases with multiple version fallbacks
    IF NOT "%INSTALL_STATUS%"=="SUCCESS" (
        CALL :LOG_MESSAGE "Attempting MSI installation with multiple version fallbacks..." "INFO" "LAUNCHER"
        DEL /Q "%WORKING_DIR%pwsh.msi" >nul 2>&1
        SET "MSI_DOWNLOADED=NO"
        
        REM Try Method 1: GitHub API (latest stable release)
        CALL :LOG_MESSAGE "MSI Method 1: GitHub API latest stable release..." "DEBUG" "LAUNCHER"
        powershell -NoProfile -ExecutionPolicy Bypass -Command "try { $ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; $headers=@{ 'User-Agent'='WinMaintLauncher' }; $arch = if([Environment]::Is64BitOperatingSystem){ 'x64' } else { 'x86' }; $rel = Invoke-RestMethod -Headers $headers -Uri 'https://api.github.com/repos/PowerShell/PowerShell/releases/latest' -TimeoutSec 30; $asset = $rel.assets | Where-Object { $_.name -match ('win-' + $arch + '\\.msi$') } | Select-Object -First 1; if(-not $asset){ Write-Host 'ASSET_NOT_FOUND'; exit 2 }; $url = $asset.browser_download_url; Invoke-WebRequest -Headers $headers -Uri $url -OutFile '%WORKING_DIR%pwsh.msi' -TimeoutSec 60; Write-Host 'MSI_API_DOWNLOADED' } catch { Write-Host 'MSI_API_FAILED'; exit 1 }" >nul 2>&1
        IF !ERRORLEVEL! EQU 0 IF EXIST "%WORKING_DIR%pwsh.msi" (
            SET "MSI_DOWNLOADED=YES"
            CALL :LOG_MESSAGE "MSI downloaded successfully via GitHub API (latest)" "SUCCESS" "LAUNCHER"
        ) ELSE (
            CALL :LOG_MESSAGE "GitHub API method failed - trying direct version URLs..." "WARN" "LAUNCHER"
            DEL /Q "%WORKING_DIR%pwsh.msi" >nul 2>&1
        )
        
        REM Try Method 2: PowerShell 7.4.6 (LTS - Long-Term Support)
        IF "%MSI_DOWNLOADED%"=="NO" (
            CALL :LOG_MESSAGE "MSI Method 2: PowerShell 7.4.6 LTS (x64)..." "DEBUG" "LAUNCHER"
            powershell -NoProfile -ExecutionPolicy Bypass -Command "try { $ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; $arch = if([Environment]::Is64BitOperatingSystem){ 'x64' } else { 'x86' }; $url = 'https://github.com/PowerShell/PowerShell/releases/download/v7.4.6/PowerShell-7.4.6-win-' + $arch + '.msi'; Invoke-WebRequest -Uri $url -OutFile '%WORKING_DIR%pwsh.msi' -UseBasicParsing -TimeoutSec 60; Write-Host 'MSI_7_4_6_DOWNLOADED' } catch { Write-Host 'MSI_7_4_6_FAILED'; exit 1 }" >nul 2>&1
            IF !ERRORLEVEL! EQU 0 IF EXIST "%WORKING_DIR%pwsh.msi" (
                SET "MSI_DOWNLOADED=YES"
                CALL :LOG_MESSAGE "MSI downloaded successfully - PowerShell 7.4.6 LTS" "SUCCESS" "LAUNCHER"
            ) ELSE (
                CALL :LOG_MESSAGE "PowerShell 7.4.6 LTS download failed" "WARN" "LAUNCHER"
                DEL /Q "%WORKING_DIR%pwsh.msi" >nul 2>&1
            )
        )
        
        REM Try Method 3: PowerShell 7.4.0 (stable)
        IF "%MSI_DOWNLOADED%"=="NO" (
            CALL :LOG_MESSAGE "MSI Method 3: PowerShell 7.4.0 stable (x64)..." "DEBUG" "LAUNCHER"
            powershell -NoProfile -ExecutionPolicy Bypass -Command "try { $ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; $arch = if([Environment]::Is64BitOperatingSystem){ 'x64' } else { 'x86' }; $url = 'https://github.com/PowerShell/PowerShell/releases/download/v7.4.0/PowerShell-7.4.0-win-' + $arch + '.msi'; Invoke-WebRequest -Uri $url -OutFile '%WORKING_DIR%pwsh.msi' -UseBasicParsing -TimeoutSec 60; Write-Host 'MSI_7_4_0_DOWNLOADED' } catch { Write-Host 'MSI_7_4_0_FAILED'; exit 1 }" >nul 2>&1
            IF !ERRORLEVEL! EQU 0 IF EXIST "%WORKING_DIR%pwsh.msi" (
                SET "MSI_DOWNLOADED=YES"
                CALL :LOG_MESSAGE "MSI downloaded successfully - PowerShell 7.4.0" "SUCCESS" "LAUNCHER"
            ) ELSE (
                CALL :LOG_MESSAGE "PowerShell 7.4.0 download failed" "WARN" "LAUNCHER"
                DEL /Q "%WORKING_DIR%pwsh.msi" >nul 2>&1
            )
        )
        
        REM Try Method 4: PowerShell 7.3.12 (older stable)
        IF "%MSI_DOWNLOADED%"=="NO" (
            CALL :LOG_MESSAGE "MSI Method 4: PowerShell 7.3.12 older stable (x64)..." "DEBUG" "LAUNCHER"
            powershell -NoProfile -ExecutionPolicy Bypass -Command "try { $ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; $arch = if([Environment]::Is64BitOperatingSystem){ 'x64' } else { 'x86' }; $url = 'https://github.com/PowerShell/PowerShell/releases/download/v7.3.12/PowerShell-7.3.12-win-' + $arch + '.msi'; Invoke-WebRequest -Uri $url -OutFile '%WORKING_DIR%pwsh.msi' -UseBasicParsing -TimeoutSec 60; Write-Host 'MSI_7_3_12_DOWNLOADED' } catch { Write-Host 'MSI_7_3_12_FAILED'; exit 1 }" >nul 2>&1
            IF !ERRORLEVEL! EQU 0 IF EXIST "%WORKING_DIR%pwsh.msi" (
                SET "MSI_DOWNLOADED=YES"
                CALL :LOG_MESSAGE "MSI downloaded successfully - PowerShell 7.3.12" "SUCCESS" "LAUNCHER"
            ) ELSE (
                CALL :LOG_MESSAGE "PowerShell 7.3.12 download failed" "WARN" "LAUNCHER"
                DEL /Q "%WORKING_DIR%pwsh.msi" >nul 2>&1
            )
        )
        
        REM Try Method 5: PowerShell 7.2.23 (maximum compatibility)
        IF "%MSI_DOWNLOADED%"=="NO" (
            CALL :LOG_MESSAGE "MSI Method 5: PowerShell 7.2.23 max compatibility (x64)..." "DEBUG" "LAUNCHER"
            powershell -NoProfile -ExecutionPolicy Bypass -Command "try { $ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; $arch = if([Environment]::Is64BitOperatingSystem){ 'x64' } else { 'x86' }; $url = 'https://github.com/PowerShell/PowerShell/releases/download/v7.2.23/PowerShell-7.2.23-win-' + $arch + '.msi'; Invoke-WebRequest -Uri $url -OutFile '%WORKING_DIR%pwsh.msi' -UseBasicParsing -TimeoutSec 60; Write-Host 'MSI_7_2_23_DOWNLOADED' } catch { Write-Host 'MSI_7_2_23_FAILED'; exit 1 }" >nul 2>&1
            IF !ERRORLEVEL! EQU 0 IF EXIST "%WORKING_DIR%pwsh.msi" (
                SET "MSI_DOWNLOADED=YES"
                CALL :LOG_MESSAGE "MSI downloaded successfully - PowerShell 7.2.23" "SUCCESS" "LAUNCHER"
            ) ELSE (
                CALL :LOG_MESSAGE "PowerShell 7.2.23 download failed - trying Microsoft CDN fallback..." "WARN" "LAUNCHER"
                DEL /Q "%WORKING_DIR%pwsh.msi" >nul 2>&1
            )
        )
        
        REM Try Method 6: Microsoft CDN (aka.ms redirect - final fallback)
        IF "%MSI_DOWNLOADED%"=="NO" (
            CALL :LOG_MESSAGE "MSI Method 6: Microsoft CDN via aka.ms (final fallback)..." "DEBUG" "LAUNCHER"
            powershell -NoProfile -ExecutionPolicy Bypass -Command "try { $ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; $arch = if([Environment]::Is64BitOperatingSystem){ 'x64' } else { 'x86' }; $cdnUrl = 'https://aka.ms/powershell-release?tag=stable'; Invoke-WebRequest -Uri $cdnUrl -OutFile '%WORKING_DIR%pwsh.msi' -UseBasicParsing -TimeoutSec 60 -MaximumRedirection 5; Write-Host 'MSI_CDN_DOWNLOADED' } catch { Write-Host 'MSI_CDN_FAILED'; exit 1 }" >nul 2>&1
            IF !ERRORLEVEL! EQU 0 IF EXIST "%WORKING_DIR%pwsh.msi" (
                SET "MSI_DOWNLOADED=YES"
                CALL :LOG_MESSAGE "MSI downloaded successfully from Microsoft CDN" "SUCCESS" "LAUNCHER"
            ) ELSE (
                CALL :LOG_MESSAGE "Microsoft CDN download failed - All 6 MSI methods exhausted" "ERROR" "LAUNCHER"
                DEL /Q "%WORKING_DIR%pwsh.msi" >nul 2>&1
            )
        )
        
        REM Install MSI if downloaded from any method
        IF "%MSI_DOWNLOADED%"=="YES" (
            CALL :LOG_MESSAGE "PowerShell MSI downloaded. Installing silently..." "INFO" "LAUNCHER"
            
            REM Attempt MSI installation with detailed error capture
            SET "MSI_INSTALL_EXIT_CODE=0"
            msiexec /i "%WORKING_DIR%pwsh.msi" /qn ADD_EXPLORER_CONTEXT_MENU_OPENPOWERSHELL=1 ENABLE_PSREMOTING=1 REGISTER_MANIFEST=1 /log "%WORKING_DIR%pwsh_install.log" >nul 2>&1
            SET "MSI_INSTALL_EXIT_CODE=!ERRORLEVEL!"
            
            IF !MSI_INSTALL_EXIT_CODE! EQU 0 (
                CALL :LOG_MESSAGE "PowerShell 7 installed successfully via MSI" "SUCCESS" "LAUNCHER"
                SET "INSTALL_STATUS=SUCCESS"
                SET "PS7_FOUND=YES"
            ) ELSE IF !MSI_INSTALL_EXIT_CODE! EQU 1603 (
                CALL :LOG_MESSAGE "MSI installation failed with error 1603 (Fatal error during installation)" "ERROR" "LAUNCHER"
                CALL :LOG_MESSAGE "Check %WORKING_DIR%pwsh_install.log for details" "ERROR" "LAUNCHER"
            ) ELSE IF !MSI_INSTALL_EXIT_CODE! EQU 1602 (
                CALL :LOG_MESSAGE "MSI installation cancelled by user (error 1602)" "ERROR" "LAUNCHER"
            ) ELSE IF !MSI_INSTALL_EXIT_CODE! EQU 1618 (
                CALL :LOG_MESSAGE "MSI installation failed (error 1618 - Another installation in progress)" "ERROR" "LAUNCHER"
            ) ELSE IF !MSI_INSTALL_EXIT_CODE! EQU 3010 (
                CALL :LOG_MESSAGE "PowerShell 7 installed successfully - reboot required (exit code 3010)" "SUCCESS" "LAUNCHER"
                SET "INSTALL_STATUS=SUCCESS"
                SET "PS7_FOUND=YES"
            ) ELSE (
                CALL :LOG_MESSAGE "MSI installation failed with exit code: !MSI_INSTALL_EXIT_CODE!" "ERROR" "LAUNCHER"
                CALL :LOG_MESSAGE "Check %WORKING_DIR%pwsh_install.log for details" "ERROR" "LAUNCHER"
            )
            DEL /Q "%WORKING_DIR%pwsh.msi" >nul 2>&1
        ) ELSE (
            CALL :LOG_MESSAGE "Failed to download PowerShell MSI - all 6 fallback methods exhausted" "ERROR" "LAUNCHER"
        )
    )

    REM Post-install verification and restart logic
    IF "%INSTALL_STATUS%"=="SUCCESS" (
        REM Check for restart loop prevention
        SET "RESTART_COUNT=0"
        IF EXIST "%WORKING_DIR%restart_flag.tmp" (
            FOR /F "tokens=*" %%i IN ('type "%WORKING_DIR%restart_flag.tmp" 2^>nul ^| find /C "POWERSHELL_RESTART"') DO SET RESTART_COUNT=%%i
            CALL :LOG_MESSAGE "Detected previous restart attempts: !RESTART_COUNT!" "DEBUG" "LAUNCHER"
        )
        
        IF !RESTART_COUNT! GEQ 3 (
            CALL :LOG_MESSAGE "Maximum restart attempts (3) reached - installation succeeded but verification failed" "ERROR" "LAUNCHER"
            CALL :LOG_MESSAGE "PowerShell 7 may be installed but not in PATH. Try manual verification." "ERROR" "LAUNCHER"
            DEL /Q "%WORKING_DIR%restart_flag.tmp" >nul 2>&1
            EXIT /B 1
        )
        
        CALL :LOG_MESSAGE "Restarting script with fresh environment to detect PowerShell 7 (attempt !RESTART_COUNT! of 3)..." "INFO" "LAUNCHER"
        
        REM Append restart entry to flag file for loop tracking
        ECHO POWERSHELL_RESTART_%DATE:~-4,4%%DATE:~-10,2%%DATE:~-7,2%_%TIME:~0,2%%TIME:~3,2%%TIME:~6,2% >> "%WORKING_DIR%restart_flag.tmp"
        
        REM Restart the script with a fresh environment (give Windows a moment to update PATH)
        TIMEOUT /T 3 /NOBREAK >nul 2>&1
        START "" /WAIT cmd.exe /C ""%SCRIPT_PATH%" %*"
        
        REM Exit current instance after new instance completes
        EXIT /B !ERRORLEVEL!
    ) ELSE (
        CALL :LOG_MESSAGE "All automated installation methods for PowerShell 7 failed." "ERROR" "LAUNCHER"
        CALL :LOG_MESSAGE "Attempted installation methods:" "ERROR" "LAUNCHER"
        CALL :LOG_MESSAGE " 1. Winget (Microsoft.PowerShell)" "ERROR" "LAUNCHER"
        CALL :LOG_MESSAGE " 2. Chocolatey (powershell-core)" "ERROR" "LAUNCHER"
        CALL :LOG_MESSAGE " 3. MSI via GitHub API (latest)" "ERROR" "LAUNCHER"
        CALL :LOG_MESSAGE " 4. MSI Direct: v7.4.6 LTS, v7.4.0, v7.3.12, v7.2.23" "ERROR" "LAUNCHER"
        CALL :LOG_MESSAGE " 5. MSI via Microsoft CDN (aka.ms/powershell-release)" "ERROR" "LAUNCHER"
        CALL :LOG_MESSAGE "" "ERROR" "LAUNCHER"
        CALL :LOG_MESSAGE "Troubleshooting tips:" "ERROR" "LAUNCHER"
        CALL :LOG_MESSAGE " - Ensure winget can access sources: winget source list / reset --force / update" "ERROR" "LAUNCHER"
        CALL :LOG_MESSAGE " - Update App Installer from Microsoft Store (for winget updates)" "ERROR" "LAUNCHER"
        CALL :LOG_MESSAGE " - Check corporate proxy/firewall settings for GitHub and CDN access" "ERROR" "LAUNCHER"
        CALL :LOG_MESSAGE " - Verify TLS 1.2 is enabled: [Net.ServicePointManager]::SecurityProtocol" "ERROR" "LAUNCHER"
        CALL :LOG_MESSAGE " - Manually install from https://github.com/PowerShell/PowerShell/releases" "ERROR" "LAUNCHER"
    )
) ELSE (
    FOR /F "tokens=*" %%i IN ('pwsh.exe -Command "$PSVersionTable.PSVersion.ToString()" 2^>nul') DO SET PS7_VERSION=%%i
    CALL :LOG_MESSAGE "PowerShell 7 available: %PS7_VERSION%" "SUCCESS" "LAUNCHER"
)

REM -----------------------------------------------------------------------------
REM PowerShell Module Dependencies (PSWindowsUpdate for Windows Update management)
REM -----------------------------------------------------------------------------
CALL :LOG_SECTION "STEP 6: PowerShell Module Dependencies"
CALL :LOG_MESSAGE "Checking PSWindowsUpdate module availability..." "INFO" "LAUNCHER"
pwsh.exe -NoProfile -Command "if (Get-Module -ListAvailable -Name PSWindowsUpdate) { Write-Host 'PSWINDOWSUPDATE_AVAILABLE' } else { Write-Host 'PSWINDOWSUPDATE_MISSING' }" >nul 2>&1
IF !ERRORLEVEL! EQU 0 (
    CALL :LOG_MESSAGE "PSWindowsUpdate module is already installed" "SUCCESS" "LAUNCHER"
) ELSE (
    CALL :LOG_MESSAGE "PSWindowsUpdate module not found. Installing..." "INFO" "LAUNCHER"
    pwsh.exe -NoProfile -ExecutionPolicy Bypass -Command "try { $ProgressPreference='SilentlyContinue'; Install-PackageProvider -Name NuGet -Force -Scope CurrentUser | Out-Null; Set-PSRepository -Name PSGallery -InstallationPolicy Trusted; Install-Module -Name PSWindowsUpdate -Force -Scope CurrentUser -Repository PSGallery; Write-Host 'PSWINDOWSUPDATE_INSTALLED' } catch { Write-Host 'PSWINDOWSUPDATE_INSTALL_FAILED'; Write-Host $_.Exception.Message; exit 1 }"
    IF !ERRORLEVEL! EQU 0 (
        CALL :LOG_MESSAGE "PSWindowsUpdate module installed successfully" "SUCCESS" "LAUNCHER"
    ) ELSE (
        CALL :LOG_MESSAGE "PSWindowsUpdate module installation failed - Windows Updates task will not be available" "WARN" "LAUNCHER"
    )
)

REM -----------------------------------------------------------------------------
REM Windows Defender Exclusions (Moved after PowerShell installation)
REM -----------------------------------------------------------------------------
CALL :LOG_SECTION "STEP 7: Windows Defender Exclusions"
CALL :LOG_MESSAGE "Setting up Windows Defender exclusions..." "INFO" "LAUNCHER"
powershell -ExecutionPolicy Bypass -Command "try { Add-MpPreference -ExclusionPath '%WORKING_DIR%' -ErrorAction SilentlyContinue; Add-MpPreference -ExclusionProcess 'powershell.exe' -ErrorAction SilentlyContinue; Add-MpPreference -ExclusionProcess 'pwsh.exe' -ErrorAction SilentlyContinue; Write-Host 'EXCLUSIONS_ADDED' } catch { Write-Host 'EXCLUSIONS_FAILED' }"

REM Package Manager Dependencies
CALL :LOG_MESSAGE "Verifying package managers..." "INFO" "LAUNCHER"

REM Winget
winget --version >nul 2>&1
IF !ERRORLEVEL! EQU 0 (
    FOR /F "tokens=*" %%i IN ('winget --version 2^>nul') DO SET WINGET_VERSION=%%i
    CALL :LOG_MESSAGE "Winget available: %WINGET_VERSION%" "SUCCESS" "LAUNCHER"
) ELSE (
    REM Check typical location for App Execution Aliases
    IF EXIST "%LocalAppData%\Microsoft\WindowsApps\winget.exe" (
        FOR /F "tokens=*" %%i IN ('"%LocalAppData%\Microsoft\WindowsApps\winget.exe" --version 2^>nul') DO SET WINGET_VERSION=%%i
        IF DEFINED WINGET_VERSION (
            CALL :LOG_MESSAGE "Winget available via WindowsApps path: %WINGET_VERSION%" "SUCCESS" "LAUNCHER"
        ) ELSE (
            CALL :LOG_MESSAGE "Winget appears installed but not yet ready (App Execution Alias may require session refresh)" "INFO" "LAUNCHER"
        )
    ) ELSE (
        CALL :LOG_MESSAGE "Winget not available - some features may be limited" "INFO" "LAUNCHER"
    )
)

REM Chocolatey  
choco --version >nul 2>&1
IF !ERRORLEVEL! EQU 0 (
    FOR /F "tokens=*" %%i IN ('choco --version 2^>nul') DO SET CHOCO_VERSION=%%i
    CALL :LOG_MESSAGE "Chocolatey available: %CHOCO_VERSION%" "SUCCESS" "LAUNCHER"
) ELSE (
    CALL :LOG_MESSAGE "Chocolatey not available - will be installed if needed" "INFO" "LAUNCHER"
)

CALL :LOG_MESSAGE "Dependency verification completed" "SUCCESS" "LAUNCHER"

REM =============================================================================
REM Enhanced PowerShell 7+ Executable Detection (Comprehensive Methods)
REM =============================================================================
CALL :LOG_MESSAGE "Detecting PowerShell 7+ executable for orchestrator..." "INFO" "LAUNCHER"

SET "PS_EXECUTABLE="
SET "PS_VERSION_STRING="
SET "AUTO_NONINTERACTIVE=NO"

REM Method 1: Direct pwsh.exe command test
CALL :LOG_MESSAGE "Method 1: Testing pwsh.exe command..." "DEBUG" "LAUNCHER"
pwsh.exe -Command "if($PSVersionTable.PSVersion.Major -ge 7){exit 0}else{exit 1}" >nul 2>&1
IF !ERRORLEVEL! EQU 0 (
    SET "PS_EXECUTABLE=pwsh.exe"
    SET "AUTO_NONINTERACTIVE=YES"
    FOR /F "tokens=*" %%V IN ('pwsh.exe -Command "$PSVersionTable.PSVersion.ToString()" 2^>nul') DO SET "PS_VERSION_STRING=%%V"
    CALL :LOG_MESSAGE "PowerShell !PS_VERSION_STRING! detected via PATH command" "SUCCESS" "LAUNCHER"
)

REM Method 2: Check default installation path
IF "%PS_EXECUTABLE%"=="" (
    CALL :LOG_MESSAGE "Method 2: Testing default installation path..." "DEBUG" "LAUNCHER"
    SET "PS7_DEFAULT=%ProgramFiles%\PowerShell\7\pwsh.exe"
    IF EXIST "!PS7_DEFAULT!" (
        "!PS7_DEFAULT!" -Command "if($PSVersionTable.PSVersion.Major -ge 7){exit 0}else{exit 1}" >nul 2>&1
        IF !ERRORLEVEL! EQU 0 (
            SET "PS_EXECUTABLE=!PS7_DEFAULT!"
            SET "AUTO_NONINTERACTIVE=YES"
            FOR /F "tokens=*" %%V IN ('"!PS7_DEFAULT!" -Command "$PSVersionTable.PSVersion.ToString()" 2^>nul') DO SET "PS_VERSION_STRING=%%V"
            CALL :LOG_MESSAGE "PowerShell !PS_VERSION_STRING! detected at default installation path" "SUCCESS" "LAUNCHER"
        )
    )
)

REM Method 3: Check WindowsApps alias
IF "%PS_EXECUTABLE%"=="" (
    CALL :LOG_MESSAGE "Method 3: Testing WindowsApps alias..." "DEBUG" "LAUNCHER"
    SET "PS7_ALIAS=%LocalAppData%\Microsoft\WindowsApps\pwsh.exe"
    IF EXIST "!PS7_ALIAS!" (
        "!PS7_ALIAS!" -Command "if($PSVersionTable.PSVersion.Major -ge 7){exit 0}else{exit 1}" >nul 2>&1
        IF !ERRORLEVEL! EQU 0 (
            SET "PS_EXECUTABLE=!PS7_ALIAS!"
            SET "AUTO_NONINTERACTIVE=YES"
            FOR /F "tokens=*" %%V IN ('"!PS7_ALIAS!" -Command "$PSVersionTable.PSVersion.ToString()" 2^>nul') DO SET "PS_VERSION_STRING=%%V"
            CALL :LOG_MESSAGE "PowerShell !PS_VERSION_STRING! detected via WindowsApps alias" "SUCCESS" "LAUNCHER"
        )
    )
)

REM Method 4: Registry-based detection
IF "%PS_EXECUTABLE%"=="" (
    CALL :LOG_MESSAGE "Method 4: Registry-based detection..." "DEBUG" "LAUNCHER"
    REG QUERY "HKLM\SOFTWARE\Microsoft\PowerShell\7" /v "InstallLocation" >nul 2>&1
    IF !ERRORLEVEL! EQU 0 (
        FOR /F "tokens=3*" %%a IN ('REG QUERY "HKLM\SOFTWARE\Microsoft\PowerShell\7" /v "InstallLocation" 2^>nul ^| findstr InstallLocation') DO (
            SET "REG_PS7_PATH=%%b\pwsh.exe"
            IF EXIST "!REG_PS7_PATH!" (
                "!REG_PS7_PATH!" -Command "if($PSVersionTable.PSVersion.Major -ge 7){exit 0}else{exit 1}" >nul 2>&1
                IF !ERRORLEVEL! EQU 0 (
                    SET "PS_EXECUTABLE=!REG_PS7_PATH!"
                    SET "AUTO_NONINTERACTIVE=YES"
                    FOR /F "tokens=*" %%V IN ('"!REG_PS7_PATH!" -Command "$PSVersionTable.PSVersion.ToString()" 2^>nul') DO SET "PS_VERSION_STRING=%%V"
                    CALL :LOG_MESSAGE "PowerShell !PS_VERSION_STRING! detected via registry" "SUCCESS" "LAUNCHER"
                )
            )
        )
    )
)

REM Method 5: 'where' command search
IF "%PS_EXECUTABLE%"=="" (
    CALL :LOG_MESSAGE "Method 5: Using 'where' command..." "DEBUG" "LAUNCHER"
    FOR /F "tokens=*" %%i IN ('where pwsh.exe 2^>nul') DO (
        IF "%PS_EXECUTABLE%"=="" (
            SET "TEST_PATH=%%i"
            IF EXIST "!TEST_PATH!" (
                "!TEST_PATH!" -Command "if($PSVersionTable.PSVersion.Major -ge 7){exit 0}else{exit 1}" >nul 2>&1
                IF !ERRORLEVEL! EQU 0 (
                    SET "PS_EXECUTABLE=!TEST_PATH!"
                    SET "AUTO_NONINTERACTIVE=YES"
                    FOR /F "tokens=*" %%V IN ('"!TEST_PATH!" -Command "$PSVersionTable.PSVersion.ToString()" 2^>nul') DO SET "PS_VERSION_STRING=%%V"
                    CALL :LOG_MESSAGE "PowerShell !PS_VERSION_STRING! located via 'where' command" "SUCCESS" "LAUNCHER"
                )
            )
        )
    )
)

REM Final check: Ensure we have PowerShell 7+
IF "%PS_EXECUTABLE%"=="" (
    CALL :LOG_MESSAGE "CRITICAL: PowerShell 7+ not found after comprehensive detection" "ERROR" "LAUNCHER"
    CALL :LOG_MESSAGE "Detection methods attempted:" "ERROR" "LAUNCHER"
    CALL :LOG_MESSAGE "  1. PATH environment variable lookup for pwsh.exe" "ERROR" "LAUNCHER"
    CALL :LOG_MESSAGE "  2. Default installation path: %ProgramFiles%\PowerShell\7\pwsh.exe" "ERROR" "LAUNCHER"
    CALL :LOG_MESSAGE "  3. WindowsApps alias: %LocalAppData%\Microsoft\WindowsApps\pwsh.exe" "ERROR" "LAUNCHER"
    CALL :LOG_MESSAGE "  4. Registry-based PowerShell 7 detection" "ERROR" "LAUNCHER"
    CALL :LOG_MESSAGE "  5. Windows 'where' command search" "ERROR" "LAUNCHER"
    CALL :LOG_MESSAGE "" "ERROR" "LAUNCHER"
    CALL :LOG_MESSAGE "PowerShell 7+ is required for this maintenance system." "ERROR" "LAUNCHER"
    CALL :LOG_MESSAGE "Please install PowerShell 7+ from: https://github.com/PowerShell/PowerShell/releases" "ERROR" "LAUNCHER"
    CALL :LOG_MESSAGE "Or install via winget: winget install Microsoft.PowerShell" "ERROR" "LAUNCHER"
    EXIT /B 1
)

CALL :LOG_MESSAGE "PowerShell 7+ ready for orchestrator execution: %PS_VERSION_STRING%" "SUCCESS" "LAUNCHER"

REM =============================================================================
REM TRANSITION TO POWERSHELL 7 FOR REMAINING STEPS
REM =============================================================================
CALL :LOG_MESSAGE "Transitioning to PowerShell 7 environment for system-level operations..." "INFO" "LAUNCHER"
CALL :LOG_MESSAGE "Remaining steps will execute using PowerShell 7 native cmdlets and syntax" "INFO" "LAUNCHER"

REM Create inline PowerShell 7 script for remaining bootstrap steps
SET "PS7_SCRIPT=%TEMP%\maintenance_bootstrap_%RANDOM%.ps1"

REM Capture all command-line arguments for passthrough to orchestrator
SET "ALL_ARGS=%*"

REM Write PowerShell 7 script content
(
echo # Windows Maintenance Bootstrap - PowerShell 7 Native Script
echo # Auto-generated by script.bat at %DATE% %TIME%
echo.
echo #Requires -Version 7.0
echo #Requires -RunAsAdministrator
echo.
echo param(
echo     [string]$WorkingDir = '%WORKING_DIR%',
echo     [string]$LogFile = '%LOG_FILE%',
echo     [string]$ScriptPath = '%SCRIPT_PATH%',
echo     [string]$ScheduledTaskScriptPath = '%SCHEDULED_TASK_SCRIPT_PATH%',
echo     [string]$OrchestratorPath = '%ORCHESTRATOR_PATH%',
echo     [string]$RepoUrl = '%REPO_URL%',
echo     [string]$ExtractFolder = '%EXTRACT_FOLDER%'
echo ^)
echo.
echo # Parse command-line arguments from batch (passed via $args automatic variable)
echo $BatchArgs = if ($args) { $args } else { @() }
echo.
echo # Logging function
echo function Write-Log {
echo     param([string]$Message, [string]$Level = 'INFO', [string]$Component = 'PS7-BOOTSTRAP'^)
echo     $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
echo     $logEntry = "[$timestamp] [$Level] [$Component] $Message"
echo     Write-Host $logEntry
echo     if (Test-Path $LogFile^) { Add-Content -Path $LogFile -Value $logEntry -ErrorAction SilentlyContinue }
echo }
echo.
echo Write-Log "PowerShell 7 bootstrap script started" "INFO"
echo Write-Log "PSVersion: $($PSVersionTable.PSVersion.ToString(^)^)" "DEBUG"
echo.
echo # Windows Defender Exclusions
echo Write-Log "Setting up Windows Defender exclusions..." "INFO"
echo try {
echo     Add-MpPreference -ExclusionPath $WorkingDir -ErrorAction SilentlyContinue
echo     Add-MpPreference -ExclusionProcess 'powershell.exe' -ErrorAction SilentlyContinue
echo     Add-MpPreference -ExclusionProcess 'pwsh.exe' -ErrorAction SilentlyContinue
echo     Write-Log "Defender exclusions added" "SUCCESS"
echo } catch {
echo     Write-Log "Defender exclusions failed: $_" "WARN"
echo }
echo.
echo # Package Manager Verification
echo Write-Log "Verifying package managers..." "INFO"
echo try {
echo     $wingetVersion = ^& winget --version 2^>$null
echo     if ($wingetVersion^) { Write-Log "Winget available: $wingetVersion" "SUCCESS" }
echo     else { Write-Log "Winget not available" "WARN" }
echo } catch { Write-Log "Winget check failed" "WARN" }
echo.
echo try {
echo     $chocoVersion = ^& choco --version 2^>$null
echo     if ($chocoVersion^) { Write-Log "Chocolatey available: $chocoVersion" "SUCCESS" }
echo     else { Write-Log "Chocolatey not available" "INFO" }
echo } catch { Write-Log "Chocolatey check failed" "INFO" }
echo.
echo # Scheduled Task Management
echo Write-Log "Managing scheduled tasks..." "INFO"
echo $taskName = "WindowsMaintenanceAutomation"
echo $startupTaskName = "WindowsMaintenanceStartup"
echo.
echo if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue^) {
echo     Write-Log "Monthly scheduled task exists: $taskName" "SUCCESS"
echo } else {
echo     Write-Log "Monthly task not found" "WARN"
echo }
echo.
echo if (Get-ScheduledTask -TaskName $startupTaskName -ErrorAction SilentlyContinue^) {
echo     Write-Log "Cleaning up startup task: $startupTaskName" "INFO"
echo     Unregister-ScheduledTask -TaskName $startupTaskName -Confirm:$false -ErrorAction SilentlyContinue
echo }
echo.
echo # System Restore Point Creation
echo Write-Log "Checking System Protection status..." "INFO"
echo $srAvailable = $false
echo try {
echo     if (Get-Command 'Get-ComputerRestorePoint' -ErrorAction SilentlyContinue^) {
echo         $testRP = Get-ComputerRestorePoint -ErrorAction SilentlyContinue
echo         $srAvailable = $true
echo         Write-Log "System Protection is available" "SUCCESS"
echo.
echo         # Enable System Protection
echo         try {
echo             Enable-ComputerRestore -Drive $env:SystemDrive -ErrorAction Stop
echo             Write-Log "System Protection enabled" "SUCCESS"
echo         } catch {
echo             if ($_.Exception.Message -like '*already enabled*'^) {
echo                 Write-Log "System Protection already enabled" "SUCCESS"
echo             } else {
echo                 Write-Log "Could not enable System Protection: $_" "WARN"
echo             }
echo         }
echo     } else {
echo         Write-Log "System Protection commands not available" "WARN"
echo     }
echo } catch {
echo     Write-Log "System Protection check failed: $_" "WARN"
echo }
echo.
echo if ($srAvailable^) {
echo     Write-Log "Creating system restore point..." "INFO"
echo     $restoreGuid = [guid]::NewGuid(^).ToString(^).Substring(0,8^)
echo     $restoreDesc = "WindowsMaintenance-$restoreGuid"
echo.
echo     try {
echo         Checkpoint-Computer -Description $restoreDesc -RestorePointType 'MODIFY_SETTINGS' -ErrorAction Stop
echo         Write-Log "System restore point created: $restoreDesc" "SUCCESS"
echo.
echo         # Verify restore point
echo         $rp = Get-ComputerRestorePoint ^| Where-Object Description -eq $restoreDesc ^| Select-Object -First 1
echo         if ($rp^) {
echo             Write-Log "Restore point verified (Sequence: $($rp.SequenceNumber^)^)" "SUCCESS"
echo         } else {
echo             Write-Log "Restore point created but verification inconclusive" "WARN"
echo         }
echo     } catch {
echo         Write-Log "Failed to create restore point: $_" "WARN"
echo         Write-Log "Continuing without restore point" "WARN"
echo     }
echo }
echo.
echo # Launch Orchestrator
echo Write-Log "Preparing to launch orchestrator..." "INFO"
echo Write-Log "Orchestrator path: $OrchestratorPath" "DEBUG"
echo.
echo if (-not (Test-Path $OrchestratorPath^)^) {
echo     Write-Log "Orchestrator file not found: $OrchestratorPath" "ERROR"
echo     exit 4
echo }
echo.
echo # Parse arguments for orchestrator
echo $orchestratorArgs = @(^)
echo if ($BatchArgs -contains '-NonInteractive'^) { $orchestratorArgs += '-NonInteractive' }
echo if ($BatchArgs -contains '-DryRun'^) { $orchestratorArgs += '-DryRun' }
echo if ($BatchArgs -contains '-TaskNumbers'^) {
echo     $taskNumIndex = $BatchArgs.IndexOf('-TaskNumbers'^) + 1
echo     if ($taskNumIndex -lt $BatchArgs.Count^) {
echo         $orchestratorArgs += '-TaskNumbers', $BatchArgs[$taskNumIndex]
echo     }
echo }
echo.
echo Write-Log "Orchestrator arguments: $orchestratorArgs" "DEBUG"
echo Write-Log "Launching PowerShell 7+ orchestrator..." "SUCCESS"
echo.
echo # Execute orchestrator
echo Set-Location -Path $WorkingDir
echo $exitCode = 0
echo.
echo if ($BatchArgs -contains '-NonInteractive'^) {
echo     Write-Log "Executing in non-interactive mode..." "INFO"
echo     ^& $OrchestratorPath @orchestratorArgs
echo     $exitCode = $LASTEXITCODE
echo } else {
echo     Write-Host ""
echo     Write-Host "🚀 Windows Maintenance Automation - PowerShell 7+ Mode" -ForegroundColor Green
echo     Write-Host "📁 Working Directory: $WorkingDir" -ForegroundColor Cyan
echo     Write-Host "🔧 Launching MaintenanceOrchestrator..." -ForegroundColor Yellow
echo     Write-Host ""
echo.
echo     try {
echo         ^& $OrchestratorPath @orchestratorArgs
echo         $exitCode = $LASTEXITCODE
echo     } catch {
echo         $exitCode = 1
echo         Write-Log "Orchestrator execution failed: $_" "ERROR"
echo     }
echo.
echo     Write-Host ""
echo     if ($exitCode -eq 0^) {
echo         Write-Host "✅ Maintenance session completed successfully." -ForegroundColor Green
echo     } else {
echo         Write-Host "⚠️ Maintenance session completed with errors (exit code: $exitCode^)" -ForegroundColor Yellow
echo     }
echo }
echo.
echo if ($exitCode -eq 0^) {
echo     Write-Log "Orchestrator completed successfully (exit code: $exitCode^)" "SUCCESS"
echo } else {
echo     Write-Log "Orchestrator completed with errors (exit code: $exitCode^)" "WARN"
echo }
echo.
echo Write-Log "PowerShell 7 bootstrap script completed" "INFO"
echo exit $exitCode
) > "%PS7_SCRIPT%"

CALL :LOG_SECTION "STEP 8: Launching Maintenance Orchestrator"
CALL :LOG_MESSAGE "PowerShell 7 bootstrap script created: %PS7_SCRIPT%" "DEBUG" "LAUNCHER"
CALL :LOG_MESSAGE "Executing PowerShell 7 bootstrap with full system access..." "INFO" "LAUNCHER"
CALL :LOG_MESSAGE "Passing arguments to PS7 script: %ALL_ARGS%" "DEBUG" "LAUNCHER"

REM Execute the PowerShell 7 script and capture exit code, passing all arguments
"%PS_EXECUTABLE%" -ExecutionPolicy Bypass -NoProfile -File "%PS7_SCRIPT%" %ALL_ARGS%
SET "FINAL_EXIT_CODE=%ERRORLEVEL%"

REM Clean up temporary script
IF EXIST "%PS7_SCRIPT%" DEL /Q "%PS7_SCRIPT%" >nul 2>&1

REM Log final result
IF %FINAL_EXIT_CODE% EQU 0 (
    CALL :LOG_MESSAGE "All operations completed successfully (exit code: %FINAL_EXIT_CODE%)" "SUCCESS" "LAUNCHER"
) ELSE (
    CALL :LOG_MESSAGE "Operations completed with errors (exit code: %FINAL_EXIT_CODE%)" "WARN" "LAUNCHER"
)

REM Log file closure
ECHO. >> "%LOG_FILE%"
ECHO ============================================================================ >> "%LOG_FILE%"
ECHO Session Completed: %DATE% %TIME% >> "%LOG_FILE%"
ECHO Exit Code: %FINAL_EXIT_CODE% >> "%LOG_FILE%"
ECHO Log file location: %LOG_FILE% >> "%LOG_FILE%"
ECHO ============================================================================ >> "%LOG_FILE%"

CALL :LOG_MESSAGE "Complete log available at: %LOG_FILE%" "INFO" "LAUNCHER"

CALL :LOG_MESSAGE "Batch launcher phase completed - exiting" "INFO" "LAUNCHER"
EXIT /B %FINAL_EXIT_CODE%

REM -----------------------------------------------------------------------------
REM End of Script
REM -----------------------------------------------------------------------------
ENDLOCAL