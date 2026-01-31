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
:LOG_MESSAGE
REM ISO 8601 timestamp format for consistency with PowerShell modules
REM Format: YYYY-MM-DDTHH:MM:SS+TZ (simplified for batch - no milliseconds)
FOR /F "tokens=1-4 delims=/. " %%a IN ("%DATE%") DO (
    SET "LOG_DATE=%%d-%%b-%%c"
)
FOR /F "tokens=1-3 delims=:. " %%a IN ("%TIME%") DO (
    SET "LOG_TIME=%%a:%%b:%%c"
)
SET "LOG_TIMESTAMP=%LOG_DATE%T%LOG_TIME%"

SET "LEVEL=%~2"
IF "%LEVEL%"=="" SET "LEVEL=INFO"
SET "COMPONENT=%~3"
IF "%COMPONENT%"=="" SET "COMPONENT=LAUNCHER"

REM Unified format: [TIMESTAMP] [LEVEL] [COMPONENT] MESSAGE
SET "LOG_ENTRY=[%LOG_TIMESTAMP%] [%LEVEL%] [%COMPONENT%] %~1"

ECHO %LOG_ENTRY%
IF EXIST "%LOG_FILE%" ECHO %LOG_ENTRY% >> "%LOG_FILE%" 2>nul
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
CALL :LOG_MESSAGE "Starting Windows Maintenance Automation Launcher v2.0" "INFO" "LAUNCHER"
CALL :LOG_MESSAGE "Environment: %USERNAME%@%COMPUTERNAME%" "INFO" "LAUNCHER"

REM Enhanced path detection - works from any location
SET "SCRIPT_PATH=%~f0"
SET "SCRIPT_DIR=%~dp0"
SET "SCRIPT_NAME=%~nx0"
SET "WORKING_DIR=%SCRIPT_DIR%"

REM v3.1 FIX: Store original script directory BEFORE any updates (used for log file location)
SET "ORIGINAL_SCRIPT_DIR=%SCRIPT_DIR%"
CALL :LOG_MESSAGE "Original script directory stored: %ORIGINAL_SCRIPT_DIR%" "DEBUG" "LAUNCHER"

REM Robust Script Path Detection for Scheduled Tasks (use the exact running script path)
SET "SCHEDULED_TASK_SCRIPT_PATH="
IF EXIST "%SCRIPT_PATH%" (
    SET "SCHEDULED_TASK_SCRIPT_PATH=%SCRIPT_PATH%"
    CALL :LOG_MESSAGE "Scheduled tasks will use current script path: %SCHEDULED_TASK_SCRIPT_PATH%" "DEBUG" "LAUNCHER"
)
IF NOT DEFINED SCHEDULED_TASK_SCRIPT_PATH IF EXIST "%SCRIPT_DIR%script.bat" (
    SET "SCHEDULED_TASK_SCRIPT_PATH=%SCRIPT_DIR%script.bat"
    CALL :LOG_MESSAGE "Scheduled tasks will use directory script path: %SCHEDULED_TASK_SCRIPT_PATH%" "DEBUG" "LAUNCHER"
)
IF NOT DEFINED SCHEDULED_TASK_SCRIPT_PATH (
    SET "SCHEDULED_TASK_SCRIPT_PATH=%SCRIPT_PATH%"
    CALL :LOG_MESSAGE "Using fallback script path for scheduled tasks: %SCHEDULED_TASK_SCRIPT_PATH%" "WARN" "LAUNCHER"
)

REM Detect if running from a network location
IF "%SCRIPT_PATH:~0,2%"=="\\" (
    SET "IS_NETWORK_LOCATION=YES"
    CALL :LOG_MESSAGE "Running from network location: %SCRIPT_PATH%" "INFO" "LAUNCHER"
) ELSE (
    SET "IS_NETWORK_LOCATION=NO"
    CALL :LOG_MESSAGE "Running from local location: %SCRIPT_PATH%" "INFO" "LAUNCHER"
)

REM Setup logging - Create maintenance.log at repository root initially
REM v3.1 FIX: Use ORIGINAL_SCRIPT_DIR to ensure log is created in correct location
SET "LOG_FILE=%ORIGINAL_SCRIPT_DIR%maintenance.log"

REM FIX #1: Initialize the log file immediately on startup (don't wait for first LOG_MESSAGE call)
REM Get current date/time for banner using more reliable methods (ALWAYS, not just on first run)
FOR /F "tokens=1-4 delims=/ " %%A IN ('DATE /T') DO SET "BANNER_DATE=%%A %%B %%C %%D"
FOR /F "tokens=1-2 delims=/:" %%A IN ('TIME /T') DO SET "BANNER_TIME=%%A:%%B"

IF NOT EXIST "%LOG_FILE%" (
    (
        ECHO ================================================
        ECHO  Windows Maintenance Automation Launcher v2.0
        ECHO ================================================
        ECHO.
        ECHO  Computer: %COMPUTERNAME%
        ECHO  User: %USERNAME%
        ECHO  Date: %BANNER_DATE%
        ECHO  Time: %BANNER_TIME%
        ECHO.
        ECHO ================================================
        ECHO.
    ) > "%LOG_FILE%"
)

CALL :LOG_MESSAGE "Maintenance log file initialized at repository root: %LOG_FILE%" "DEBUG" "LAUNCHER"

REM Environment variables for PowerShell orchestrator
SET "WORKING_DIRECTORY=%WORKING_DIR%"
SET "SCRIPT_LOG_FILE=%LOG_FILE%"

REM Repository configuration for auto-updates
SET "REPO_URL=https://github.com/ichimbogdancristian/script_mentenanta/archive/refs/heads/master.zip"
SET "ZIP_FILE=%WORKING_DIR%update.zip"
SET "EXTRACT_FOLDER=script_mentenanta-master"

CALL :LOG_MESSAGE "Self-discovery environment initialized" "SUCCESS" "LAUNCHER"

REM -----------------------------------------------------------------------------
REM Administrator Privilege Verification
REM -----------------------------------------------------------------------------
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
        PAUSE
        EXIT /B 1
    )
    exit
)

CALL :LOG_MESSAGE "Administrator privileges confirmed" "SUCCESS" "LAUNCHER"

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
    CALL :LOG_MESSAGE "Creating ONLOGON startup task with script: %SCHEDULED_TASK_SCRIPT_PATH%" "DEBUG" "LAUNCHER"
    schtasks /Create ^
        /SC ONLOGON ^
        /TN "%STARTUP_TASK_NAME%" ^
        /TR "\"%SCHEDULED_TASK_SCRIPT_PATH%\"" ^
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
CALL :LOG_MESSAGE "Ensuring monthly maintenance task exists (20th day 01:00)..." "INFO" "LAUNCHER"

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
        /D 20 ^
        /TN "%TASK_NAME%" ^
        /TR "\"%SCHEDULED_TASK_SCRIPT_PATH%\"" ^
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
    PAUSE
    EXIT /B 2
)

CALL :LOG_MESSAGE "System requirements verified" "SUCCESS" "LAUNCHER"

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
    PAUSE
    EXIT /B 3
)

IF NOT EXIST "%ZIP_FILE%" (
    CALL :LOG_MESSAGE "Download verification failed - ZIP file not found" "ERROR" "LAUNCHER"
    PAUSE
    EXIT /B 3
)

CALL :LOG_MESSAGE "Repository downloaded successfully" "SUCCESS" "LAUNCHER"

REM Extract repository
CALL :LOG_MESSAGE "Extracting repository..." "INFO" "LAUNCHER"
powershell -ExecutionPolicy Bypass -Command "try { Add-Type -AssemblyName System.IO.Compression.FileSystem; [System.IO.Compression.ZipFile]::ExtractToDirectory('%ZIP_FILE%', '%WORKING_DIR%'); Write-Host 'EXTRACTION_SUCCESS' } catch { Write-Host 'EXTRACTION_FAILED'; Write-Error $_.Exception.Message; exit 1 }"

IF !ERRORLEVEL! NEQ 0 (
    CALL :LOG_MESSAGE "Repository extraction failed" "ERROR" "LAUNCHER"
    PAUSE
    EXIT /B 3
)

REM Verify extraction
SET "EXTRACTED_PATH=%WORKING_DIR%%EXTRACT_FOLDER%"
IF EXIST "%EXTRACTED_PATH%" (
    CALL :LOG_MESSAGE "Repository extracted to: %EXTRACTED_PATH%" "SUCCESS" "LAUNCHER"
    
    REM Replace script.bat with the one from extracted folder
    IF EXIST "%EXTRACTED_PATH%\script.bat" (
        CALL :LOG_MESSAGE "Updating script.bat from extracted repository" "INFO" "LAUNCHER"
        
        REM Use ORIGINAL_SCRIPT_DIR to ensure we overwrite the correct script.bat location
        SET "ORIGINAL_SCRIPT_BAT=%ORIGINAL_SCRIPT_DIR%script.bat"
        SET "BACKUP_SCRIPT=%ORIGINAL_SCRIPT_DIR:~0,-1%.bat.backup"
        
        IF EXIST "%ORIGINAL_SCRIPT_BAT%" (
            COPY /Y "%ORIGINAL_SCRIPT_BAT%" "%BACKUP_SCRIPT%" >nul 2>&1
            CALL :LOG_MESSAGE "Original script.bat backed up to: %BACKUP_SCRIPT%" "DEBUG" "LAUNCHER"
        )
        
        REM Copy extracted script.bat to original location
        COPY /Y "%EXTRACTED_PATH%\script.bat" "%ORIGINAL_SCRIPT_BAT%" >nul 2>&1
        IF !ERRORLEVEL! EQU 0 (
            CALL :LOG_MESSAGE "Successfully replaced script.bat with version from repository at: %ORIGINAL_SCRIPT_BAT%" "SUCCESS" "LAUNCHER"
        ) ELSE (
            CALL :LOG_MESSAGE "Failed to replace script.bat at %ORIGINAL_SCRIPT_BAT% - continuing with current version" "WARN" "LAUNCHER"
        )
    ) ELSE (
        CALL :LOG_MESSAGE "No script.bat found in extracted repository" "WARN" "LAUNCHER"
    )
    
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
        PAUSE
        EXIT /B 3
    )
) ELSE (
    CALL :LOG_MESSAGE "Repository extraction verification failed" "ERROR" "LAUNCHER"
    PAUSE
    EXIT /B 3
)

REM Clean up
DEL /Q "%ZIP_FILE%" >nul 2>&1

REM Ensure orchestrator temp_files location exists
IF NOT EXIST "%WORKING_DIR%temp_files" (
    MKDIR "%WORKING_DIR%temp_files" >nul 2>&1
    CALL :LOG_MESSAGE "Created temp_files directory at %WORKING_DIR%temp_files" "DEBUG" "LAUNCHER"
)

REM Create logs subdirectory if it doesn't exist
IF NOT EXIST "%WORKING_DIR%temp_files\logs" (
    MKDIR "%WORKING_DIR%temp_files\logs" >nul 2>&1
)

REM NOTE: maintenance.log will be organized by LogProcessor module
REM The module will handle moving logs from root to temp_files/logs/ when it initializes
CALL :LOG_MESSAGE "Log organization will be handled by LogProcessor module" "DEBUG" "LAUNCHER"

REM Set environment variables so PowerShell can access bootstrap paths
SET "ORIGINAL_LOG_FILE=%LOG_FILE%"
CALL :LOG_MESSAGE "Original log file path (if exists): %ORIGINAL_LOG_FILE%" "DEBUG" "LAUNCHER"

REM Continue with orchestrator invocation
REM LogProcessor will organize logs when it runs

REM -----------------------------------------------------------------------------
REM Project Structure Discovery and Validation (Moved after extraction)
REM -----------------------------------------------------------------------------
CALL :LOG_MESSAGE "Discovering project structure..." "INFO" "LAUNCHER"

REM Check for required components with detailed verification
SET "STRUCTURE_VALID=YES"
SET "ORCHESTRATOR_PATH="
SET "COMPONENTS_FOUND=0"

REM Look for MaintenanceOrchestrator.ps1
IF EXIST "%WORKING_DIR%MaintenanceOrchestrator.ps1" (
    SET "ORCHESTRATOR_PATH=%WORKING_DIR%MaintenanceOrchestrator.ps1"
    CALL :LOG_MESSAGE "✓ Found orchestrator: MaintenanceOrchestrator.ps1" "SUCCESS" "LAUNCHER"
    SET /A COMPONENTS_FOUND+=1
) ELSE IF EXIST "%WORKING_DIR%script.ps1" (
    SET "ORCHESTRATOR_PATH=%WORKING_DIR%script.ps1"
    CALL :LOG_MESSAGE "✓ Found legacy orchestrator: script.ps1" "INFO" "LAUNCHER"
    SET /A COMPONENTS_FOUND+=1
) ELSE (
    CALL :LOG_MESSAGE "✗ No PowerShell orchestrator found in current directory" "WARN" "LAUNCHER"
    SET "STRUCTURE_VALID=NO"
)

REM Check for config directory and its contents (FIX #7: Check new subdirectory structure)
IF EXIST "%WORKING_DIR%config" (
    CALL :LOG_MESSAGE "✓ Found configuration directory" "SUCCESS" "LAUNCHER"
    SET /A COMPONENTS_FOUND+=1
    
    REM Check for settings subdirectory (execution configs)
    IF EXIST "%WORKING_DIR%config\settings" (
        CALL :LOG_MESSAGE "  ✓ config\settings directory present" "SUCCESS" "LAUNCHER"
        IF EXIST "%WORKING_DIR%config\settings\main-config.json" (
            CALL :LOG_MESSAGE "    ✓ main-config.json present" "SUCCESS" "LAUNCHER"
        ) ELSE (
            CALL :LOG_MESSAGE "    ✗ main-config.json missing" "WARN" "LAUNCHER"
        )
    ) ELSE (
        CALL :LOG_MESSAGE "  ✗ config\settings directory not found" "WARN" "LAUNCHER"
    )
    
    REM Check for lists subdirectory (data lists)
    IF EXIST "%WORKING_DIR%config\lists" (
        CALL :LOG_MESSAGE "  ✓ config\lists directory present" "SUCCESS" "LAUNCHER"
        IF EXIST "%WORKING_DIR%config\lists\bloatware-list.json" (
            CALL :LOG_MESSAGE "    ✓ bloatware-list.json present" "SUCCESS" "LAUNCHER"
        ) ELSE (
            CALL :LOG_MESSAGE "    ✗ bloatware-list.json missing" "WARN" "LAUNCHER"
        )
    ) ELSE (
        CALL :LOG_MESSAGE "  ✗ config\lists directory not found" "WARN" "LAUNCHER"
    )
) ELSE (
    CALL :LOG_MESSAGE "✗ Configuration directory not found" "WARN" "LAUNCHER"
    SET "STRUCTURE_VALID=NO"
)

REM Check for modules directory and core modules
IF EXIST "%WORKING_DIR%modules" (
    CALL :LOG_MESSAGE "✓ Found modules directory" "SUCCESS" "LAUNCHER"
    SET /A COMPONENTS_FOUND+=1
    
    IF EXIST "%WORKING_DIR%modules\core" (
        CALL :LOG_MESSAGE "  ✓ Core modules directory present" "SUCCESS" "LAUNCHER"
    ) ELSE (
        CALL :LOG_MESSAGE "  ✗ Core modules directory missing" "WARN" "LAUNCHER"
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
    CALL :LOG_MESSAGE "✗ Modules directory not found" "WARN" "LAUNCHER"
    SET "STRUCTURE_VALID=NO"
)

CALL :LOG_MESSAGE "Project structure verification: %COMPONENTS_FOUND%/3 major components found" "INFO" "LAUNCHER"

IF "%STRUCTURE_VALID%"=="NO" (
    CALL :LOG_MESSAGE "Project structure incomplete but repository already downloaded. Check extraction." "ERROR" "LAUNCHER"
    PAUSE
    EXIT /B 4
) ELSE (
    CALL :LOG_MESSAGE "Project structure validated" "SUCCESS" "LAUNCHER"
)

REM -----------------------------------------------------------------------------
REM Enhanced Dependency Management
REM -----------------------------------------------------------------------------
:DEPENDENCY_MANAGEMENT
CALL :LOG_MESSAGE "Starting dependency management..." "INFO" "LAUNCHER"

REM -----------------------------------------------------------------------------
REM Winget Installation and Verification Section (Moved before PowerShell detection)
REM -----------------------------------------------------------------------------
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
        
        REM Method 1: Try installing App Installer via PowerShell (if allowed)
        powershell -NoProfile -ExecutionPolicy Bypass -Command "try { if (Get-Command Get-AppxPackage -ErrorAction SilentlyContinue) { $appInstaller = Get-AppxPackage -Name 'Microsoft.DesktopAppInstaller' -ErrorAction SilentlyContinue; if (-not $appInstaller) { Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe -ErrorAction Stop; Write-Host 'APPINSTALLER_REGISTERED' } else { Write-Host 'APPINSTALLER_EXISTS' } } else { Write-Host 'APPX_NOT_SUPPORTED' } } catch { Write-Host 'APPINSTALLER_FAILED'; exit 1 }" >nul 2>&1
        IF !ERRORLEVEL! EQU 0 (
            CALL :LOG_MESSAGE "App Installer registration attempted" "INFO" "LAUNCHER"
            TIMEOUT /T 5 >nul 2>&1
        ) ELSE (
            CALL :LOG_MESSAGE "App Installer registration failed" "WARN" "LAUNCHER"
        )
        
        REM Check if Method 1 succeeded before trying Method 2
        winget --version >nul 2>&1
        IF !ERRORLEVEL! NEQ 0 (
            REM Method 2: Try PowerShell Gallery Microsoft.WinGet.Client module (official method)
            CALL :LOG_MESSAGE "Attempting winget installation via PowerShell Gallery (Microsoft.WinGet.Client)..." "INFO" "LAUNCHER"
            powershell -NoProfile -ExecutionPolicy Bypass -Command "try { $ProgressPreference='SilentlyContinue'; Write-Host 'Installing NuGet provider...'; Install-PackageProvider -Name NuGet -Force -Scope CurrentUser | Out-Null; Write-Host 'Installing Microsoft.WinGet.Client module...'; Install-Module -Name Microsoft.WinGet.Client -Force -Repository PSGallery -Scope CurrentUser | Out-Null; Write-Host 'Running Repair-WinGetPackageManager...'; Import-Module Microsoft.WinGet.Client -Force; Repair-WinGetPackageManager -AllUsers; Write-Host 'WINGET_PSMODULE_SUCCESS' } catch { Write-Host 'WINGET_PSMODULE_FAILED'; Write-Host $_.Exception.Message; exit 1 }"
            IF !ERRORLEVEL! EQU 0 (
                CALL :LOG_MESSAGE "PowerShell Gallery method completed - verifying winget availability..." "INFO" "LAUNCHER"
                TIMEOUT /T 5 >nul 2>&1
                
                REM Verify winget actually works after PowerShell Gallery installation
                winget --version >nul 2>&1
                IF !ERRORLEVEL! EQU 0 (
                    SET "WINGET_EXE=winget"
                    SET "WINGET_AVAILABLE=YES"
                    CALL :LOG_MESSAGE "Winget verified working after PowerShell Gallery installation" "SUCCESS" "LAUNCHER"
                ) ELSE (
                    REM Try WindowsApps path after PowerShell Gallery installation
                    IF EXIST "%LocalAppData%\Microsoft\WindowsApps\winget.exe" (
                        "%LocalAppData%\Microsoft\WindowsApps\winget.exe" --version >nul 2>&1
                        IF !ERRORLEVEL! EQU 0 (
                            SET "WINGET_EXE=%LocalAppData%\Microsoft\WindowsApps\winget.exe"
                            SET "WINGET_AVAILABLE=YES"
                            CALL :LOG_MESSAGE "Winget working via WindowsApps after PowerShell Gallery installation" "SUCCESS" "LAUNCHER"
                        ) ELSE (
                            CALL :LOG_MESSAGE "PowerShell Gallery installed winget but it's not functional" "WARN" "LAUNCHER"
                        )
                    ) ELSE (
                        CALL :LOG_MESSAGE "PowerShell Gallery method completed but winget not accessible" "WARN" "LAUNCHER"
                    )
                )
            ) ELSE (
                CALL :LOG_MESSAGE "PowerShell Gallery winget installation failed" "WARN" "LAUNCHER"
            )
        ) ELSE (
            CALL :LOG_MESSAGE "Method 1 succeeded - skipping PowerShell Gallery installation" "DEBUG" "LAUNCHER"
        )
        
        REM Check if Methods 1 and 2 succeeded before trying Method 3
        winget --version >nul 2>&1
        IF !ERRORLEVEL! NEQ 0 (
            REM Method 3: Download and install App Installer MSIX manually with fallback URLs
            CALL :LOG_MESSAGE "Attempting manual App Installer download with fallback URLs..." "INFO" "LAUNCHER"
            DEL /Q "%WORKING_DIR%AppInstaller.msixbundle" >nul 2>&1
            
            REM Try primary URL (Microsoft official shortlink)
            powershell -NoProfile -ExecutionPolicy Bypass -Command "try { $ProgressPreference='SilentlyContinue'; Write-Host 'Trying primary URL (Microsoft official)...'; $url='https://aka.ms/getwinget'; Invoke-WebRequest -Uri $url -OutFile '%WORKING_DIR%AppInstaller.msixbundle' -UseBasicParsing -TimeoutSec 30; Write-Host 'PRIMARY_MSIX_DOWNLOADED' } catch { Write-Host 'PRIMARY_MSIX_FAILED'; Write-Host $_.Exception.Message; exit 1 }" >nul 2>&1
            IF !ERRORLEVEL! NEQ 0 (
                CALL :LOG_MESSAGE "Primary URL failed, trying fallback URL 1 (GitHub direct)..." "INFO" "LAUNCHER"
                DEL /Q "%WORKING_DIR%AppInstaller.msixbundle" >nul 2>&1
                powershell -NoProfile -ExecutionPolicy Bypass -Command "try { $ProgressPreference='SilentlyContinue'; Write-Host 'Trying fallback URL 1 (GitHub direct)...'; $url='https://github.com/microsoft/winget-cli/releases/latest/download/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle'; Invoke-WebRequest -Uri $url -OutFile '%WORKING_DIR%AppInstaller.msixbundle' -UseBasicParsing -TimeoutSec 30; Write-Host 'FALLBACK1_MSIX_DOWNLOADED' } catch { Write-Host 'FALLBACK1_MSIX_FAILED'; Write-Host $_.Exception.Message; exit 1 }" >nul 2>&1
                IF !ERRORLEVEL! NEQ 0 (
                    CALL :LOG_MESSAGE "Fallback URL 1 failed, trying fallback URL 2 (GitHub versioned)..." "INFO" "LAUNCHER"
                    DEL /Q "%WORKING_DIR%AppInstaller.msixbundle" >nul 2>&1
                    powershell -NoProfile -ExecutionPolicy Bypass -Command "try { $ProgressPreference='SilentlyContinue'; Write-Host 'Trying fallback URL 2 (GitHub versioned)...'; $url='https://github.com/microsoft/winget-cli/releases/download/v1.11.510/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle'; Invoke-WebRequest -Uri $url -OutFile '%WORKING_DIR%AppInstaller.msixbundle' -UseBasicParsing -TimeoutSec 30; Write-Host 'FALLBACK2_MSIX_DOWNLOADED' } catch { Write-Host 'FALLBACK2_MSIX_FAILED'; Write-Host $_.Exception.Message; exit 1 }" >nul 2>&1
                    IF !ERRORLEVEL! EQU 0 (
                        CALL :LOG_MESSAGE "App Installer MSIX downloaded via fallback URL 2. Installing..." "INFO" "LAUNCHER"
                    ) ELSE (
                        CALL :LOG_MESSAGE "All download URLs failed (primary + 2 fallbacks) for App Installer MSIX" "ERROR" "LAUNCHER"
                    )
                ) ELSE (
                    CALL :LOG_MESSAGE "App Installer MSIX downloaded via fallback URL 1. Installing..." "INFO" "LAUNCHER"
                )
            ) ELSE (
                CALL :LOG_MESSAGE "App Installer MSIX downloaded via primary URL. Installing..." "INFO" "LAUNCHER"
            )
            
            REM Install the MSIX if download succeeded
            IF EXIST "%WORKING_DIR%AppInstaller.msixbundle" (
                powershell -NoProfile -ExecutionPolicy Bypass -Command "try { Add-AppxPackage -Path '%WORKING_DIR%AppInstaller.msixbundle' -ErrorAction Stop; Write-Host 'MSIX_INSTALLED' } catch { Write-Host 'MSIX_INSTALL_FAILED'; exit 1 }" >nul 2>&1
                IF !ERRORLEVEL! EQU 0 (
                    CALL :LOG_MESSAGE "App Installer MSIX installed successfully" "SUCCESS" "LAUNCHER"
                    DEL /Q "%WORKING_DIR%AppInstaller.msixbundle" >nul 2>&1
                ) ELSE (
                    CALL :LOG_MESSAGE "App Installer MSIX installation failed" "WARN" "LAUNCHER"
                )
            ) ELSE (
                CALL :LOG_MESSAGE "Failed to download App Installer MSIX" "WARN" "LAUNCHER"
            )
        ) ELSE (
            CALL :LOG_MESSAGE "Methods 1 or 2 succeeded - skipping manual MSIX installation" "DEBUG" "LAUNCHER"
        )
        
        REM Re-check winget availability after installation attempts
        CALL :LOG_MESSAGE "Re-checking winget availability after installation attempts..." "INFO" "LAUNCHER"
        TIMEOUT /T 3 >nul 2>&1
        
        winget --version >nul 2>&1
        IF !ERRORLEVEL! EQU 0 (
            SET "WINGET_EXE=winget"
            SET "WINGET_AVAILABLE=YES"
            CALL :LOG_MESSAGE "Winget now available via PATH" "SUCCESS" "LAUNCHER"
        ) ELSE (
            IF EXIST "%LocalAppData%\Microsoft\WindowsApps\winget.exe" (
                "%LocalAppData%\Microsoft\WindowsApps\winget.exe" --version >nul 2>&1
                IF !ERRORLEVEL! EQU 0 (
                    SET "WINGET_EXE=%LocalAppData%\Microsoft\WindowsApps\winget.exe"
                    SET "WINGET_AVAILABLE=YES"
                    CALL :LOG_MESSAGE "Winget now available via WindowsApps alias" "SUCCESS" "LAUNCHER"
                )
            )
        )
        
        IF "%WINGET_AVAILABLE%"=="NO" (
            CALL :LOG_MESSAGE "All winget installation methods failed" "WARN" "LAUNCHER"
        )
    )

REM -----------------------------------------------------------------------------
REM PowerShell 7 Detection and Installation (Moved after winget setup)
REM -----------------------------------------------------------------------------
CALL :LOG_MESSAGE "Checking PowerShell 7 availability..." "INFO" "LAUNCHER"

REM Try multiple detection methods before deciding to install
SET "PS7_FOUND=NO"

REM Method 1: Direct pwsh.exe command
pwsh.exe -Version >nul 2>&1
IF !ERRORLEVEL! EQU 0 (
    SET "PS7_FOUND=YES"
    CALL :LOG_MESSAGE "PowerShell 7 detected via pwsh.exe command" "DEBUG" "LAUNCHER"
)

REM Method 2: Check default installation path
IF "%PS7_FOUND%"=="NO" (
    IF EXIST "%ProgramFiles%\PowerShell\7\pwsh.exe" (
        "%ProgramFiles%\PowerShell\7\pwsh.exe" -Version >nul 2>&1
        IF !ERRORLEVEL! EQU 0 (
            SET "PS7_FOUND=YES"
            CALL :LOG_MESSAGE "PowerShell 7 detected at default installation path" "DEBUG" "LAUNCHER"
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
        "%WINGET_EXE%" install Microsoft.PowerShell --silent --accept-package-agreements --accept-source-agreements
        IF !ERRORLEVEL! EQU 0 (
            CALL :LOG_MESSAGE "PowerShell 7 installed successfully via winget" "SUCCESS" "LAUNCHER"
            SET "INSTALL_STATUS=SUCCESS"
            SET "PS7_FOUND=YES"
            
            REM Refresh PATH environment to pick up newly installed PowerShell
            CALL :LOG_MESSAGE "Refreshing PATH environment after PowerShell 7 installation..." "DEBUG" "LAUNCHER"
            CALL :REFRESH_PATH_FROM_REGISTRY
        ) ELSE (
            CALL :LOG_MESSAGE "PowerShell 7 installation via winget failed" "WARN" "LAUNCHER"
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
            CALL :LOG_MESSAGE "Chocolatey not available - attempting Chocolatey installation..." "INFO" "LAUNCHER"
            
            REM Try installing Chocolatey from official installer
            powershell -NoProfile -ExecutionPolicy Bypass -Command "try { $ProgressPreference='SilentlyContinue'; Set-ExecutionPolicy Bypass -Scope Process -Force; [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; iex ((New-Object Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1')); Write-Host 'CHOCO_INSTALLED' } catch { Write-Host 'CHOCO_INSTALL_FAILED'; exit 1 }" >nul 2>&1
            
            IF !ERRORLEVEL! EQU 0 (
                CALL :LOG_MESSAGE "Chocolatey installed successfully" "SUCCESS" "LAUNCHER"
                TIMEOUT /T 2 >nul 2>&1
                
                REM Update Chocolatey path after installation
                IF EXIST "%ProgramData%\chocolatey\bin\choco.exe" SET "CHOCO_EXE=%ProgramData%\chocolatey\bin\choco.exe"
                
                CALL :LOG_MESSAGE "Installing PowerShell 7 via newly installed Chocolatey..." "INFO" "LAUNCHER"
                "%CHOCO_EXE%" install powershell-core -y --no-progress
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
            ) ELSE (
                CALL :LOG_MESSAGE "Chocolatey installation failed - proceeding to MSI fallback for PowerShell 7" "WARN" "LAUNCHER"
            )
        )
    )

    REM 3) MSI fallback from GitHub Releases (latest stable PowerShell)
    IF NOT "%INSTALL_STATUS%"=="SUCCESS" (
        CALL :LOG_MESSAGE "Attempting PowerShell 7 MSI fallback from GitHub Releases..." "INFO" "LAUNCHER"
        DEL /Q "%WORKING_DIR%pwsh.msi" >nul 2>&1
        powershell -NoProfile -ExecutionPolicy Bypass -Command "try { $ProgressPreference='SilentlyContinue'; $headers=@{ 'User-Agent'='WinMaintLauncher' }; $arch = if([Environment]::Is64BitOperatingSystem){ 'x64' } else { 'x86' }; $rel = Invoke-RestMethod -Headers $headers -Uri 'https://api.github.com/repos/PowerShell/PowerShell/releases/latest'; $asset = $rel.assets | Where-Object { $_.name -match ('win-' + $arch + '\\.msi$') } | Select-Object -First 1; if(-not $asset){ Write-Host 'ASSET_NOT_FOUND'; exit 2 }; $url = $asset.browser_download_url; Invoke-WebRequest -Headers $headers -Uri $url -OutFile '%WORKING_DIR%pwsh.msi'; Write-Host 'MSI_DOWNLOADED' } catch { Write-Host 'MSI_DOWNLOAD_FAILED'; exit 1 }" >nul 2>&1
        IF !ERRORLEVEL! EQU 0 (
            CALL :LOG_MESSAGE "PowerShell 7 MSI downloaded. Installing silently..." "INFO" "LAUNCHER"
            msiexec /i "%WORKING_DIR%pwsh.msi" /qn ADD_EXPLORER_CONTEXT_MENU_OPENPOWERSHELL=1 ENABLE_PSREMOTING=1 REGISTER_MANIFEST=1 >nul 2>&1
            IF !ERRORLEVEL! EQU 0 (
                CALL :LOG_MESSAGE "PowerShell 7 installed successfully via MSI" "SUCCESS" "LAUNCHER"
                SET "INSTALL_STATUS=SUCCESS"
                SET "PS7_FOUND=YES"
            ) ELSE (
                CALL :LOG_MESSAGE "PowerShell 7 MSI installation failed" "ERROR" "LAUNCHER"
            )
        ) ELSE (
            CALL :LOG_MESSAGE "Failed to download PowerShell 7 MSI from GitHub (network or API blocked)" "WARN" "LAUNCHER"
        )
    )

    REM Post-install verification and restart logic
    IF "%INSTALL_STATUS%"=="SUCCESS" (
        CALL :LOG_MESSAGE "Restarting script with fresh environment to detect PowerShell 7..." "INFO" "LAUNCHER"
        
        REM Create restart flag with timestamp to prevent infinite loops
        ECHO POWERSHELL_RESTART_%DATE:~-4,4%%DATE:~-10,2%%DATE:~-7,2%_%TIME:~0,2%%TIME:~3,2%%TIME:~6,2% > "%WORKING_DIR%restart_flag.tmp"
        
        REM Restart the script with a fresh environment (give Windows a moment to update PATH)
        TIMEOUT /T 3 /NOBREAK >nul 2>&1
        START "" /WAIT cmd.exe /C ""%SCRIPT_PATH%" %*"
        
        REM Exit current instance after new instance completes
        EXIT /B !ERRORLEVEL!
    ) ELSE (
        CALL :LOG_MESSAGE "All automated installation methods for PowerShell 7 failed." "ERROR" "LAUNCHER"
        CALL :LOG_MESSAGE "Troubleshooting tips:" "ERROR" "LAUNCHER"
        CALL :LOG_MESSAGE " - Ensure winget can access sources: winget source list / reset --force / update" "ERROR" "LAUNCHER"
        CALL :LOG_MESSAGE " - Update App Installer from Microsoft Store (for winget updates)" "ERROR" "LAUNCHER"
        CALL :LOG_MESSAGE " - Check corporate proxy/firewall settings for GitHub and CDN access" "ERROR" "LAUNCHER"
        CALL :LOG_MESSAGE " - Manually install from https://github.com/PowerShell/PowerShell/releases" "ERROR" "LAUNCHER"
    )
) ELSE (
    FOR /F "tokens=*" %%i IN ('pwsh.exe -Command "$PSVersionTable.PSVersion.ToString()" 2^>nul') DO SET PS7_VERSION=%%i
    CALL :LOG_MESSAGE "PowerShell 7 available: %PS7_VERSION%" "SUCCESS" "LAUNCHER"
)

REM -----------------------------------------------------------------------------
REM PowerShell Module Dependencies (PSWindowsUpdate for Windows Update management)
REM -----------------------------------------------------------------------------
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

REM -----------------------------------------------------------------------------
REM Modular Task Scheduler Management
REM -----------------------------------------------------------------------------
CALL :LOG_MESSAGE "Managing scheduled tasks..." "INFO" "LAUNCHER"

SET "TASK_NAME=WindowsMaintenanceAutomation"
SET "STARTUP_TASK_NAME=WindowsMaintenanceStartup"

REM Report monthly task status only (creation handled earlier)
schtasks /Query /TN "%TASK_NAME%" >nul 2>&1
IF !ERRORLEVEL! EQU 0 (
    CALL :LOG_MESSAGE "Monthly scheduled task present: %TASK_NAME%" "SUCCESS" "LAUNCHER"
    FOR /F "tokens=*" %%i IN ('schtasks /Query /TN "%TASK_NAME%" /FO LIST ^| findstr /R /C:"Task To Run" /C:"Next Run Time"') DO (
        CALL :LOG_MESSAGE "Monthly task detail: %%i" "INFO" "LAUNCHER"
    )
) ELSE (
    CALL :LOG_MESSAGE "Monthly scheduled task not found (was expected to exist)." "WARN" "LAUNCHER"
)

REM Clean up startup task if it still exists (e.g., after reboot resume)
schtasks /Query /TN "%STARTUP_TASK_NAME%" >nul 2>&1
IF !ERRORLEVEL! EQU 0 (
    CALL :LOG_MESSAGE "Cleaning up startup task: %STARTUP_TASK_NAME%" "INFO" "LAUNCHER"
    schtasks /Delete /TN "%STARTUP_TASK_NAME%" /F >nul 2>&1
)

REM -----------------------------------------------------------------------------
REM PowerShell Executable Detection (before system operations)
REM -----------------------------------------------------------------------------
CALL :LOG_MESSAGE "Detecting PowerShell executable for system operations..." "INFO" "LAUNCHER"

SET "PS_EXECUTABLE="
SET "AUTO_NONINTERACTIVE=NO"

REM Check PowerShell 7+ first (primary installation path)
SET "PS7_ABSOLUTE=%ProgramFiles%\PowerShell\7\pwsh.exe"
CALL :LOG_MESSAGE "Checking for PowerShell 7+ at: %PS7_ABSOLUTE%" "DEBUG" "LAUNCHER"
IF EXIST "%PS7_ABSOLUTE%" (
    CALL :LOG_MESSAGE "PowerShell 7 found at default installation path: %PS7_ABSOLUTE%" "DEBUG" "LAUNCHER"
    
    REM Test if the executable actually works with multiple methods
    "%PS7_ABSOLUTE%" -Command "exit 0" >nul 2>&1
    IF !ERRORLEVEL! EQU 0 (
        REM Method 1: Try version table using temp file to avoid quoting issues
        "%PS7_ABSOLUTE%" -Command "$PSVersionTable.PSVersion.Major" 2>nul > "%TEMP%\ps_major.tmp"
        FOR /F "tokens=*" %%i IN ('TYPE "%TEMP%\ps_major.tmp" 2^>nul') DO SET PS_MAJOR_VERSION=%%i
        DEL "%TEMP%\ps_major.tmp" 2>nul
        
        REM Method 2: Fallback to simpler version check if first method fails
        IF "!PS_MAJOR_VERSION!"=="" (
            "%PS7_ABSOLUTE%" -Command "$Host.Version.Major" 2>nul > "%TEMP%\ps_major2.tmp"
            FOR /F "tokens=1 delims=." %%i IN ('TYPE "%TEMP%\ps_major2.tmp" 2^>nul') DO SET PS_MAJOR_VERSION=%%i
            DEL "%TEMP%\ps_major2.tmp" 2>nul
        )
        
        REM Method 3: Last resort - parse pwsh.exe -Version output
        IF "!PS_MAJOR_VERSION!"=="" (
            FOR /F "tokens=2 delims= " %%i IN ('"%PS7_ABSOLUTE%" -Version 2^>nul ^| findstr "PowerShell"') DO (
                FOR /F "tokens=1 delims=." %%j IN ("%%i") DO SET PS_MAJOR_VERSION=%%j
            )
        )
        
        CALL :LOG_MESSAGE "PowerShell version test result: !PS_MAJOR_VERSION!" "DEBUG" "LAUNCHER"
        
        REM Accept version 7 or higher, with extra validation
        IF DEFINED PS_MAJOR_VERSION (
            IF !PS_MAJOR_VERSION! GEQ 7 (
                SET "PS_EXECUTABLE=%PS7_ABSOLUTE%"
                SET "AUTO_NONINTERACTIVE=YES"
                
                REM Get full version string for logging (robust method for paths with spaces)
                SET PS_VERSION_STRING=
                "%PS7_ABSOLUTE%" -Command "$PSVersionTable.PSVersion.ToString()" 2>nul > "%TEMP%\ps_version.tmp"
                FOR /F "tokens=*" %%i IN ('TYPE "%TEMP%\ps_version.tmp" 2^>nul') DO SET PS_VERSION_STRING=%%i
                DEL "%TEMP%\ps_version.tmp" 2>nul
                
                IF "!PS_VERSION_STRING!"=="" (
                    "%PS7_ABSOLUTE%" -Version 2>nul > "%TEMP%\ps_version.tmp"
                    FOR /F "tokens=2" %%i IN ('TYPE "%TEMP%\ps_version.tmp" 2^>nul') DO SET PS_VERSION_STRING=%%i
                    DEL "%TEMP%\ps_version.tmp" 2>nul
                )
                IF "!PS_VERSION_STRING!"=="" SET "PS_VERSION_STRING=7.x.x"
                
                CALL :LOG_MESSAGE "PowerShell !PS_VERSION_STRING! detected at default path - will use for system operations" "SUCCESS" "LAUNCHER"
            ) ELSE (
                CALL :LOG_MESSAGE "PowerShell found at default path but version !PS_MAJOR_VERSION! < 7" "WARN" "LAUNCHER"
            )
        ) ELSE (
            CALL :LOG_MESSAGE "Could not determine PowerShell version, but executable exists and responds" "WARN" "LAUNCHER"
            REM If we can't determine version but executable works, assume it's PS7+ since it's in the PS7 directory
            SET "PS_EXECUTABLE=%PS7_ABSOLUTE%"
            SET "AUTO_NONINTERACTIVE=YES"
            SET "PS_VERSION_STRING=7.x.x (version detection failed)"
            CALL :LOG_MESSAGE "PowerShell !PS_VERSION_STRING! detected - assuming PS7+ since found in PS7 directory" "SUCCESS" "LAUNCHER"
        )
    ) ELSE (
        CALL :LOG_MESSAGE "PowerShell executable at default path is not functional" "WARN" "LAUNCHER"
    )
) ELSE (
    CALL :LOG_MESSAGE "PowerShell 7 not found at default installation path: %PS7_ABSOLUTE%" "DEBUG" "LAUNCHER"
)
IF "%PS_EXECUTABLE%"=="" (
    REM Fallback Method 1: Try pwsh.exe from PATH with multiple validation approaches
    CALL :LOG_MESSAGE "Trying pwsh.exe from PATH..." "DEBUG" "LAUNCHER"
    
    REM Test 1: Simple version check
    pwsh.exe -Version >nul 2>&1
    IF !ERRORLEVEL! EQU 0 (
        CALL :LOG_MESSAGE "pwsh.exe responds to -Version command" "DEBUG" "LAUNCHER"
        FOR /F "tokens=*" %%i IN ('pwsh.exe -Command "$PSVersionTable.PSVersion.Major" 2^>nul') DO SET PS_MAJOR_VERSION=%%i
        IF DEFINED PS_MAJOR_VERSION IF !PS_MAJOR_VERSION! GEQ 7 (
            SET "PS_EXECUTABLE=pwsh.exe"
            SET "AUTO_NONINTERACTIVE=YES"
            FOR /F "tokens=*" %%i IN ('pwsh.exe -Command "$PSVersionTable.PSVersion.ToString()" 2^>nul') DO SET PS_VERSION_STRING=%%i
            CALL :LOG_MESSAGE "PowerShell !PS_VERSION_STRING! detected via PATH - will use for system operations" "SUCCESS" "LAUNCHER"
        ) ELSE (
            CALL :LOG_MESSAGE "PowerShell version !PS_MAJOR_VERSION! detected but version 7+ required" "WARN" "LAUNCHER"
        )
    ) ELSE (
        CALL :LOG_MESSAGE "pwsh.exe -Version failed, trying alternative detection..." "DEBUG" "LAUNCHER"
        
        REM Test 2: Alternative command test
        pwsh.exe -Command "exit 0" >nul 2>&1
        IF !ERRORLEVEL! EQU 0 (
            CALL :LOG_MESSAGE "pwsh.exe responds to basic command" "DEBUG" "LAUNCHER"
            FOR /F "tokens=*" %%i IN ('pwsh.exe -Command "$PSVersionTable.PSVersion.Major" 2^>nul') DO SET PS_MAJOR_VERSION=%%i
            IF DEFINED PS_MAJOR_VERSION IF !PS_MAJOR_VERSION! GEQ 7 (
                SET "PS_EXECUTABLE=pwsh.exe"
                SET "AUTO_NONINTERACTIVE=YES"
                FOR /F "tokens=*" %%i IN ('pwsh.exe -Command "$PSVersionTable.PSVersion.ToString()" 2^>nul') DO SET PS_VERSION_STRING=%%i
                CALL :LOG_MESSAGE "PowerShell !PS_VERSION_STRING! detected via alternative method - will use for system operations" "SUCCESS" "LAUNCHER"
            )
        )
    )
)

REM Fallback Method 2: Check additional common installation paths
IF "%PS_EXECUTABLE%"=="" (
    CALL :LOG_MESSAGE "Checking additional PowerShell 7 installation paths..." "DEBUG" "LAUNCHER"
    
    REM Check common installation paths
    SET "PS7_PATHS[0]=%ProgramFiles%\PowerShell\7\pwsh.exe"
    SET "PS7_PATHS[1]=%ProgramFiles(x86)%\PowerShell\7\pwsh.exe"
    SET "PS7_PATHS[2]=%LocalAppData%\Microsoft\powershell\7\pwsh.exe"
    SET "PS7_PATHS[3]=%ProgramData%\chocolatey\lib\powershell-core\tools\pwsh.exe"
    
    FOR %%P IN (0 1 2 3) DO (
        IF "%PS_EXECUTABLE%"=="" (
            CALL SET "TEST_PATH=%%PS7_PATHS[%%P]%%"
            IF EXIST "!TEST_PATH!" (
                CALL :LOG_MESSAGE "Testing PowerShell at: !TEST_PATH!" "DEBUG" "LAUNCHER"
                FOR /F "tokens=*" %%i IN ('"!TEST_PATH!" -Command "$PSVersionTable.PSVersion.Major" 2^>nul') DO SET PS_MAJOR_VERSION=%%i
                IF DEFINED PS_MAJOR_VERSION IF !PS_MAJOR_VERSION! GEQ 7 (
                    SET "PS_EXECUTABLE=!TEST_PATH!"
                    SET "AUTO_NONINTERACTIVE=YES"
                    FOR /F "tokens=*" %%i IN ('"!TEST_PATH!" -Command "$PSVersionTable.PSVersion.ToString()" 2^>nul') DO SET PS_VERSION_STRING=%%i
                    CALL :LOG_MESSAGE "PowerShell !PS_VERSION_STRING! found at: !TEST_PATH!" "SUCCESS" "LAUNCHER"
                )
            )
        )
    )
)

REM Fallback Method 3: Use Windows 'where' command to locate pwsh.exe
IF "%PS_EXECUTABLE%"=="" (
    CALL :LOG_MESSAGE "Using 'where' command to locate pwsh.exe..." "DEBUG" "LAUNCHER"
    FOR /F "tokens=*" %%i IN ('where pwsh.exe 2^>nul') DO (
        IF "%PS_EXECUTABLE%"=="" (
            SET "TEST_PATH=%%i"
            IF EXIST "!TEST_PATH!" (
                CALL :LOG_MESSAGE "Testing PowerShell found by 'where': !TEST_PATH!" "DEBUG" "LAUNCHER"
                FOR /F "tokens=*" %%j IN ('"!TEST_PATH!" -Command "$PSVersionTable.PSVersion.Major" 2^>nul') DO SET PS_MAJOR_VERSION=%%j
                IF DEFINED PS_MAJOR_VERSION IF !PS_MAJOR_VERSION! GEQ 7 (
                    SET "PS_EXECUTABLE=!TEST_PATH!"
                    SET "AUTO_NONINTERACTIVE=YES"
                    FOR /F "tokens=*" %%k IN ('"!TEST_PATH!" -Command "$PSVersionTable.PSVersion.ToString()" 2^>nul') DO SET PS_VERSION_STRING=%%k
                    CALL :LOG_MESSAGE "PowerShell !PS_VERSION_STRING! located via 'where' command" "SUCCESS" "LAUNCHER"
                )
            )
        )
    )
)

REM Fallback Method 4: Registry-based PowerShell 7 detection
IF "%PS_EXECUTABLE%"=="" (
    CALL :LOG_MESSAGE "Attempting registry-based PowerShell 7 detection..." "DEBUG" "LAUNCHER"
    
    REM Check for PowerShell 7 installation via registry
    REG QUERY "HKLM\SOFTWARE\Microsoft\PowerShell\7" /v "InstallLocation" >nul 2>&1
    IF !ERRORLEVEL! EQU 0 (
        FOR /F "tokens=3*" %%a IN ('REG QUERY "HKLM\SOFTWARE\Microsoft\PowerShell\7" /v "InstallLocation" 2^>nul ^| findstr InstallLocation') DO (
            SET "REG_PS7_PATH=%%b"
            IF DEFINED REG_PS7_PATH (
                SET "TEST_PATH=!REG_PS7_PATH!\pwsh.exe"
                IF EXIST "!TEST_PATH!" (
                    CALL :LOG_MESSAGE "Testing PowerShell from registry: !TEST_PATH!" "DEBUG" "LAUNCHER"
                    "!TEST_PATH!" -Command "exit 0" >nul 2>&1
                    IF !ERRORLEVEL! EQU 0 (
                        FOR /F "tokens=*" %%i IN ('"!TEST_PATH!" -Command "$PSVersionTable.PSVersion.Major" 2^>nul') DO SET PS_MAJOR_VERSION=%%i
                        IF DEFINED PS_MAJOR_VERSION IF !PS_MAJOR_VERSION! GEQ 7 (
                            SET "PS_EXECUTABLE=!TEST_PATH!"
                            SET "AUTO_NONINTERACTIVE=YES"
                            FOR /F "tokens=*" %%j IN ('"!TEST_PATH!" -Command "$PSVersionTable.PSVersion.ToString()" 2^>nul') DO SET PS_VERSION_STRING=%%j
                            CALL :LOG_MESSAGE "PowerShell !PS_VERSION_STRING! found via registry detection" "SUCCESS" "LAUNCHER"
                        )
                    )
                )
            )
        )
    )
)

REM Fallback Method 5: Environment PATH analysis for pwsh
IF "%PS_EXECUTABLE%"=="" (
    CALL :LOG_MESSAGE "Analyzing PATH environment for PowerShell executables..." "DEBUG" "LAUNCHER"
    
    REM Split PATH and check each directory for pwsh.exe
    FOR %%P IN ("%PATH:;=" "%") DO (
        IF "%PS_EXECUTABLE%"=="" (
            SET "TEST_PATH=%%~P\pwsh.exe"
            REM Remove quotes if present
            SET "TEST_PATH=!TEST_PATH:"=!"
            IF EXIST "!TEST_PATH!" (
                CALL :LOG_MESSAGE "Testing PowerShell in PATH: !TEST_PATH!" "DEBUG" "LAUNCHER"
                "!TEST_PATH!" -Command "exit 0" >nul 2>&1
                IF !ERRORLEVEL! EQU 0 (
                    FOR /F "tokens=*" %%i IN ('"!TEST_PATH!" -Command "$PSVersionTable.PSVersion.Major" 2^>nul') DO SET PS_MAJOR_VERSION=%%i
                    IF DEFINED PS_MAJOR_VERSION IF !PS_MAJOR_VERSION! GEQ 7 (
                        SET "PS_EXECUTABLE=!TEST_PATH!"
                        SET "AUTO_NONINTERACTIVE=YES"
                        FOR /F "tokens=*" %%j IN ('"!TEST_PATH!" -Command "$PSVersionTable.PSVersion.ToString()" 2^>nul') DO SET PS_VERSION_STRING=%%j
                        CALL :LOG_MESSAGE "PowerShell !PS_VERSION_STRING! found in PATH analysis" "SUCCESS" "LAUNCHER"
                    )
                )
            )
        )
    )
)

REM CRITICAL: The orchestrator requires PowerShell 7+ (pwsh.exe). Do NOT fall back to Windows PowerShell 5.1.
IF "%PS_EXECUTABLE%"=="" (
    CALL :LOG_MESSAGE "CRITICAL: PowerShell 7+ (pwsh.exe) not found - a compatible pwsh.exe is required for the orchestrator" "ERROR" "LAUNCHER"
    CALL :LOG_MESSAGE "Windows PowerShell 5.1 cannot be used for full orchestrator execution" "ERROR" "LAUNCHER"
    CALL :LOG_MESSAGE "" "ERROR" "LAUNCHER"
    CALL :LOG_MESSAGE "Please install PowerShell 7+ using one of these methods:" "ERROR" "LAUNCHER"
    CALL :LOG_MESSAGE "  1. winget: winget install Microsoft.PowerShell" "ERROR" "LAUNCHER"
    CALL :LOG_MESSAGE "  2. Manual: https://github.com/PowerShell/PowerShell/releases" "ERROR" "LAUNCHER"
    CALL :LOG_MESSAGE "  3. Chocolatey: choco install powershell-core" "ERROR" "LAUNCHER"
    CALL :LOG_MESSAGE "" "ERROR" "LAUNCHER"
    CALL :LOG_MESSAGE "After installation, restart this script to continue." "ERROR" "LAUNCHER"
    PAUSE
    EXIT /B 1
)

IF "%PS_EXECUTABLE%"=="" (
    CALL :LOG_MESSAGE "CRITICAL: No suitable PowerShell found after exhaustive detection attempts" "ERROR" "LAUNCHER"
    CALL :LOG_MESSAGE "Detection methods attempted:" "ERROR" "LAUNCHER"
    CALL :LOG_MESSAGE "  1. Default installation path: %ProgramFiles%\PowerShell\7\pwsh.exe" "ERROR" "LAUNCHER"
    CALL :LOG_MESSAGE "  2. PATH environment variable lookup for pwsh.exe" "ERROR" "LAUNCHER"
    CALL :LOG_MESSAGE "  3. Alternative installation paths (x86, LocalAppData, Chocolatey)" "ERROR" "LAUNCHER"
    CALL :LOG_MESSAGE "  4. Windows 'where' command search" "ERROR" "LAUNCHER"
    CALL :LOG_MESSAGE "  5. Registry-based PowerShell 7 detection" "ERROR" "LAUNCHER"
    CALL :LOG_MESSAGE "  6. Manual PATH directory analysis" "ERROR" "LAUNCHER"
    CALL :LOG_MESSAGE "" "ERROR" "LAUNCHER"
    CALL :LOG_MESSAGE "PowerShell 7+ is required for this maintenance system." "ERROR" "LAUNCHER"
    CALL :LOG_MESSAGE "Please install PowerShell 7+ from: https://github.com/PowerShell/PowerShell/releases" "ERROR" "LAUNCHER"
    CALL :LOG_MESSAGE "Or install via winget: winget install Microsoft.PowerShell" "ERROR" "LAUNCHER"
    CALL :LOG_MESSAGE "" "ERROR" "LAUNCHER"
    CALL :LOG_MESSAGE "If PowerShell 7+ is installed, please check:" "ERROR" "LAUNCHER"
    CALL :LOG_MESSAGE "  - Installation completed successfully" "ERROR" "LAUNCHER"
    CALL :LOG_MESSAGE "  - pwsh.exe is in PATH or default location" "ERROR" "LAUNCHER"
    CALL :LOG_MESSAGE "  - No execution policy restrictions" "ERROR" "LAUNCHER"
    CALL :LOG_MESSAGE "  - Antivirus/security software not blocking execution" "ERROR" "LAUNCHER"
    PAUSE
    EXIT /B 1
)

REM -----------------------------------------------------------------------------
REM System Restore Point Creation (before orchestrator execution)
REM Includes: Availability check, space allocation (minimum 10GB), and creation
REM -----------------------------------------------------------------------------
CALL :LOG_MESSAGE "Checking System Protection status..." "INFO" "LAUNCHER"

SET "SYS_DRIVE=%SystemDrive%"
SET "SR_STATUS=UNKNOWN"
SET "SR_VERIFY_STATUS=UNKNOWN"
SET "MIN_RESTORE_SPACE_GB=10"

REM Simple check for System Protection availability
FOR /F "usebackq tokens=* delims=" %%i IN (`%PS_EXECUTABLE% -NoProfile -ExecutionPolicy Bypass -Command "try { $ErrorActionPreference='Stop'; if (Get-Command 'Get-ComputerRestorePoint' -ErrorAction SilentlyContinue) { try { $rp = Get-ComputerRestorePoint -ErrorAction SilentlyContinue; Write-Host 'SR_AVAILABLE' } catch { Write-Host 'SR_ERROR' } } else { Write-Host 'SR_NOT_SUPPORTED' } } catch { Write-Host 'SR_FAILED' }" 2^>nul`) DO SET "SR_CHECK=%%i"

REM Check and allocate System Restore Point space (minimum 10GB)
IF /I "!SR_CHECK!"=="SR_AVAILABLE" (
    CALL :LOG_MESSAGE "Checking System Protection disk space allocation..." "INFO" "LAUNCHER"
    
    REM Use vssadmin to check current shadow storage allocation (modern method)
    FOR /F "usebackq tokens=* delims=" %%i IN (`%PS_EXECUTABLE% -NoProfile -ExecutionPolicy Bypass -Command "try { $vssOutput = & vssadmin list shadowstorage 2>&1 | Out-String; if ($vssOutput -match 'Maximum Shadow Copy Storage space.*?([0-9.]+)\s*(GB|MB|TB)') { $size = [decimal]$matches[1]; $unit = $matches[2]; $sizeGB = switch ($unit) { 'TB' { $size * 1024 } 'GB' { $size } 'MB' { $size / 1024 } default { 0 } }; Write-Host ('CURRENT:' + [math]::Round($sizeGB, 2)) } elseif ($vssOutput -match 'UNBOUNDED|No.*found') { Write-Host 'UNBOUNDED' } else { Write-Host 'NO_CONFIG' } } catch { Write-Host 'ERROR' }" 2^>nul`) DO SET "SR_SPACE_CHECK=%%i"
    
    REM Parse current allocation
    IF "!SR_SPACE_CHECK:~0,8!"=="CURRENT:" (
        SET "SR_CURRENT_GB=!SR_SPACE_CHECK:~8!"
        FOR /F "tokens=1 delims=." %%a IN ("!SR_CURRENT_GB!") DO SET "SR_CURRENT_GB_INT=%%a"
        
        REM Check if allocation is less than 10GB
        IF !SR_CURRENT_GB_INT! LSS !MIN_RESTORE_SPACE_GB! (
            CALL :LOG_MESSAGE "Current allocation is !SR_CURRENT_GB! GB (minimum required: !MIN_RESTORE_SPACE_GB! GB). Allocating..." "WARN" "LAUNCHER"
            
            REM Use vssadmin resize shadowstorage (correct modern method)
            FOR /F "usebackq tokens=* delims=" %%i IN (`%PS_EXECUTABLE% -NoProfile -ExecutionPolicy Bypass -Command "try { $result = & vssadmin resize shadowstorage /For=%SYS_DRIVE%\ /On=%SYS_DRIVE%\ /MaxSize=10GB 2>&1 | Out-String; if ($result -match 'successfully') { Write-Host 'ALLOCATED' } else { Write-Host 'FAILED' } } catch { Write-Host 'ERROR' }" 2^>nul`) DO SET "SR_ALLOCATE_RESULT=%%i"
            
            IF /I "!SR_ALLOCATE_RESULT!"=="ALLOCATED" (
                CALL :LOG_MESSAGE "System Restore Point allocation set to !MIN_RESTORE_SPACE_GB! GB successfully" "SUCCESS" "LAUNCHER"
            ) ELSE (
                CALL :LOG_MESSAGE "Failed to allocate System Restore Point space (may require administrator elevation or storage not yet configured)" "WARN" "LAUNCHER"
            )
        ) ELSE (
            CALL :LOG_MESSAGE "System Protection allocation is sufficient (!SR_CURRENT_GB! GB >= !MIN_RESTORE_SPACE_GB! GB)" "SUCCESS" "LAUNCHER"
        )
    ) ELSE IF /I "!SR_SPACE_CHECK!"=="UNBOUNDED" (
        CALL :LOG_MESSAGE "System Protection storage is unbounded (will use available space)" "SUCCESS" "LAUNCHER"
    ) ELSE IF /I "!SR_SPACE_CHECK!"=="NO_CONFIG" (
        CALL :LOG_MESSAGE "No shadow storage configured yet. Attempting to configure 10GB allocation..." "INFO" "LAUNCHER"
        
        REM Initialize shadow storage with vssadmin
        FOR /F "usebackq tokens=* delims=" %%i IN (`%PS_EXECUTABLE% -NoProfile -ExecutionPolicy Bypass -Command "try { $result = & vssadmin resize shadowstorage /For=%SYS_DRIVE%\ /On=%SYS_DRIVE%\ /MaxSize=10GB 2>&1 | Out-String; if ($result -match 'successfully') { Write-Host 'ALLOCATED' } else { Write-Host 'FAILED' } } catch { Write-Host 'ERROR' }" 2^>nul`) DO SET "SR_ALLOCATE_RESULT=%%i"
        
        IF /I "!SR_ALLOCATE_RESULT!"=="ALLOCATED" (
            CALL :LOG_MESSAGE "Shadow storage initialized with 10GB allocation" "SUCCESS" "LAUNCHER"
        ) ELSE (
            CALL :LOG_MESSAGE "Failed to initialize shadow storage - System Protection may need manual configuration" "WARN" "LAUNCHER"
        )
    )
)

IF /I "!SR_CHECK!"=="SR_AVAILABLE" (
    CALL :LOG_MESSAGE "System Protection is available and functional" "SUCCESS" "LAUNCHER"
    
    REM Try to enable System Protection if not already enabled
    FOR /F "usebackq tokens=* delims=" %%i IN (`%PS_EXECUTABLE% -NoProfile -ExecutionPolicy Bypass -Command "try { $ErrorActionPreference='Continue'; $drive = $env:SystemDrive; try { Enable-ComputerRestore -Drive $drive -ErrorAction Stop; Write-Host 'SR_ENABLED' } catch { if ($_.Exception.Message -like '*already enabled*' -or $_.Exception.Message -like '*System Protection*already*') { Write-Host 'SR_ALREADY_ENABLED' } else { Write-Host 'SR_ENABLE_FAILED' } } } catch { Write-Host 'SR_ENABLE_ERROR' }" 2^>nul`) DO SET "SR_ENABLE_STATUS=%%i"
    
    IF /I "!SR_ENABLE_STATUS!"=="SR_ENABLED" (
        CALL :LOG_MESSAGE "System Protection enabled successfully" "SUCCESS" "LAUNCHER"
        SET "SR_STATUS=ENABLED"
    ) ELSE IF /I "!SR_ENABLE_STATUS!"=="SR_ALREADY_ENABLED" (
        CALL :LOG_MESSAGE "System Protection already enabled" "SUCCESS" "LAUNCHER"
        SET "SR_STATUS=ENABLED"
    ) ELSE (
        CALL :LOG_MESSAGE "Could not enable System Protection (!SR_ENABLE_STATUS!) - will try restore point anyway" "WARN" "LAUNCHER"
        SET "SR_STATUS=UNKNOWN"
    )
    
) ELSE IF /I "!SR_CHECK!"=="SR_NOT_SUPPORTED" (
    CALL :LOG_MESSAGE "System Protection commands not available on this system" "WARN" "LAUNCHER"
    GOTO :SKIP_RESTORE_POINT
) ELSE (
    CALL :LOG_MESSAGE "System Protection check failed (!SR_CHECK!) - skipping restore point" "WARN" "LAUNCHER"
    GOTO :SKIP_RESTORE_POINT
)

CALL :LOG_MESSAGE "Creating system restore point before execution..." "INFO" "LAUNCHER"

FOR /F "usebackq tokens=*" %%i IN (`%PS_EXECUTABLE% -NoProfile -Command "[guid]::NewGuid().ToString().Substring(0,8)" 2^>nul`) DO SET "RESTORE_GUID=%%i"
SET "RESTORE_DESC=WindowsMaintenance-!RESTORE_GUID!"

REM Simple restore point creation using Checkpoint-Computer
FOR /F "usebackq tokens=* delims=" %%i IN (`%PS_EXECUTABLE% -NoProfile -ExecutionPolicy Bypass -Command "try { $ErrorActionPreference='Stop'; Checkpoint-Computer -Description '!RESTORE_DESC!' -RestorePointType 'MODIFY_SETTINGS'; Write-Host 'RESTORE_CREATED' } catch { Write-Host 'RESTORE_FAILED'; Write-Host $_.Exception.Message }" 2^>nul`) DO (
    IF /I "%%i"=="RESTORE_CREATED" (
        SET "RESTORE_RESULT=SUCCESS"
    ) ELSE (
        SET "RESTORE_RESULT=FAILED"
        SET "RESTORE_ERROR=%%i"
    )
)

IF /I "!RESTORE_RESULT!"=="SUCCESS" (
    CALL :LOG_MESSAGE "System restore point created successfully: !RESTORE_DESC!" "SUCCESS" "LAUNCHER"
    
    REM Quick verification that restore point exists
    FOR /F "usebackq tokens=* delims=" %%i IN (`%PS_EXECUTABLE% -NoProfile -ExecutionPolicy Bypass -Command "try { $rp = Get-ComputerRestorePoint | Where-Object Description -eq '!RESTORE_DESC!' | Select-Object -First 1; if ($rp) { Write-Host ('VERIFIED:' + $rp.SequenceNumber) } else { Write-Host 'NOT_FOUND' } } catch { Write-Host 'VERIFY_ERROR' }" 2^>nul`) DO SET "RESTORE_VERIFY=%%i"
    
    IF "!RESTORE_VERIFY:~0,8!"=="VERIFIED" (
        SET "RESTORE_SEQ=!RESTORE_VERIFY:~9!"
        CALL :LOG_MESSAGE "Restore point verified (Sequence: !RESTORE_SEQ!)" "SUCCESS" "LAUNCHER"
    ) ELSE (
        CALL :LOG_MESSAGE "Restore point created but verification inconclusive (!RESTORE_VERIFY!)" "WARN" "LAUNCHER"
    )
) ELSE (
    IF DEFINED RESTORE_ERROR (
        CALL :LOG_MESSAGE "Failed to create restore point: !RESTORE_ERROR!" "WARN" "LAUNCHER"
    ) ELSE (
        CALL :LOG_MESSAGE "Failed to create system restore point (System Protection may be disabled)" "WARN" "LAUNCHER"
    )
    CALL :LOG_MESSAGE "Continuing without restore point - you may want to create one manually" "WARN" "LAUNCHER"
)

:SKIP_RESTORE_POINT

REM -----------------------------------------------------------------------------
REM PowerShell Orchestrator Launch
REM -----------------------------------------------------------------------------
CALL :LOG_MESSAGE "Preparing to launch PowerShell orchestrator..." "INFO" "LAUNCHER"

REM Debug: Show what PowerShell executable was detected
CALL :LOG_MESSAGE "Detected PowerShell executable: %PS_EXECUTABLE%" "DEBUG" "LAUNCHER"
CALL :LOG_MESSAGE "AUTO_NONINTERACTIVE flag: %AUTO_NONINTERACTIVE%" "DEBUG" "LAUNCHER"

IF "%ORCHESTRATOR_PATH%"=="" (
    CALL :LOG_MESSAGE "No valid PowerShell orchestrator found" "ERROR" "LAUNCHER"
    PAUSE
    EXIT /B 4
)

CALL :LOG_MESSAGE "Orchestrator path: %ORCHESTRATOR_PATH%" "DEBUG" "LAUNCHER"

REM Verify orchestrator file exists
IF NOT EXIST "%ORCHESTRATOR_PATH%" (
    CALL :LOG_MESSAGE "Orchestrator file not found: %ORCHESTRATOR_PATH%" "ERROR" "LAUNCHER"
    PAUSE
    EXIT /B 4
)

REM Check if we have PowerShell 7+ for the orchestrator (required)
REM Use AUTO_NONINTERACTIVE as a reliable marker that PS 7+ was detected above
REM [REMOVED: Legacy PowerShell 7+ orchestrator check. Now handled by consolidated detection above.]

CALL :LOG_MESSAGE "Using PowerShell 7+ for orchestrator execution" "SUCCESS" "LAUNCHER"

REM Parse command line arguments for the orchestrator
SET "PS_ARGS="
IF "%1"=="-NonInteractive" SET "PS_ARGS=%PS_ARGS% -NonInteractive"
IF "%1"=="-DryRun" SET "PS_ARGS=%PS_ARGS% -DryRun"
IF "%AUTO_NONINTERACTIVE%"=="YES" (
    IF NOT "%1"=="-NonInteractive" (
        SET "PS_ARGS=%PS_ARGS% -NonInteractive"
        CALL :LOG_MESSAGE "Auto-enabling non-interactive mode due to PowerShell 7+ availability" "INFO" "LAUNCHER"
    )
)
IF "%2"=="-DryRun" SET "PS_ARGS=%PS_ARGS% -DryRun"
IF "%1"=="-TaskNumbers" SET "PS_ARGS=%PS_ARGS% -TaskNumbers %2"

CALL :LOG_MESSAGE "Launching orchestrator with arguments: %PS_ARGS%" "INFO" "LAUNCHER"

REM Setup complete - transitioning to dedicated PowerShell 7 window for better performance and UI
CALL :LOG_MESSAGE "Setup phase completed - launching dedicated PowerShell 7+ window" "INFO" "LAUNCHER"
CALL :LOG_MESSAGE "This will provide better performance and eliminate visual glitches" "INFO" "LAUNCHER"

REM Critical: Use PowerShell 7+ (pwsh.exe) for MaintenanceOrchestrator.ps1 due to #Requires directive
IF "%AUTO_NONINTERACTIVE%"=="YES" (
    CALL :LOG_MESSAGE "Launching PowerShell 7+ in dedicated window for optimal experience" "SUCCESS" "LAUNCHER"
    
    REM Prepare arguments for the new PowerShell window
    SET "PS_ARGS=-ExecutionPolicy Bypass -NoExit -Command "
    SET "PS_ARGS=!PS_ARGS!& { "
    SET "PS_ARGS=!PS_ARGS!Set-Location '%WORKING_DIR%'; "
    SET "PS_ARGS=!PS_ARGS!Write-Host '🚀 Windows Maintenance Automation - PowerShell 7+ Mode' -ForegroundColor Green; "
    SET "PS_ARGS=!PS_ARGS!Write-Host '📁 Working Directory: %WORKING_DIR%' -ForegroundColor Cyan; "
    SET "PS_ARGS=!PS_ARGS!Write-Host '🔧 Launching MaintenanceOrchestrator...' -ForegroundColor Yellow; "
    SET "PS_ARGS=!PS_ARGS!Write-Host ''; "
    
    REM Check for command line arguments to pass through
    IF "%1"=="-NonInteractive" (
        SET "PS_ARGS=!PS_ARGS!& '%ORCHESTRATOR_PATH%' -NonInteractive; "
    ) ELSE (
        SET "PS_ARGS=!PS_ARGS!& '%ORCHESTRATOR_PATH%'; "
    )
    
    SET "PS_ARGS=!PS_ARGS!Write-Host ''; "
    SET "PS_ARGS=!PS_ARGS!Write-Host '✅ Maintenance session completed. You can close this window or run additional commands.' -ForegroundColor Green; "
    SET "PS_ARGS=!PS_ARGS!}"
    
    REM Launch new PowerShell 7 window and exit batch script
    CALL :LOG_MESSAGE "Launching: \"%PS_EXECUTABLE%\" !PS_ARGS!" "DEBUG" "LAUNCHER"
    START "Windows Maintenance Automation - PowerShell 7" "%PS_EXECUTABLE%" !PS_ARGS!
    
    REM Give the new window a moment to start
    TIMEOUT /T 2 /NOBREAK >NUL 2>&1
    
    CALL :LOG_MESSAGE "PowerShell 7+ window launched successfully - batch launcher exiting" "SUCCESS" "LAUNCHER"
    CALL :LOG_MESSAGE "All further operations will run in the dedicated PowerShell window" "INFO" "LAUNCHER"
    
    REM Exit batch script cleanly - PowerShell 7 window takes over
    EXIT /B 0
) ELSE (
    CALL :LOG_MESSAGE "CRITICAL: PowerShell 7+ not detected - cannot run orchestrator" "ERROR" "LAUNCHER"
    CALL :LOG_MESSAGE "The launcher requires a compatible pwsh.exe (PowerShell 7+) to execute the orchestrator" "ERROR" "LAUNCHER"
    CALL :LOG_MESSAGE "Windows PowerShell 5.1 is not suitable for full orchestrator execution" "ERROR" "LAUNCHER"
    CALL :LOG_MESSAGE "" "ERROR" "LAUNCHER"
    CALL :LOG_MESSAGE "Please install PowerShell 7+ and restart this script:" "ERROR" "LAUNCHER"
    CALL :LOG_MESSAGE "  winget install Microsoft.PowerShell" "ERROR" "LAUNCHER"
    CALL :LOG_MESSAGE "  https://github.com/PowerShell/PowerShell/releases" "ERROR" "LAUNCHER"
    PAUSE
    EXIT /B 1
)

REM Batch script execution completed - PowerShell 7+ window is now handling all operations
CALL :LOG_MESSAGE "Batch launcher phase completed successfully" "SUCCESS" "LAUNCHER"
GOTO :FINAL_CLEANUP

REM -----------------------------------------------------------------------------
REM Post-Orchestrator Execution Logic: Interactive Menu with Countdown
REM -----------------------------------------------------------------------------
:POST_ORCHESTRATOR_MENU
ECHO.
ECHO ===============================
ECHO  Select Execution Mode (20s):
ECHO ===============================
ECHO 1. Execute script normally (unattended)
ECHO 2. Execute script in dry-run mode (unattended)
ECHO.
ECHO Waiting for selection... (defaults to option 1 after 20 seconds)
CHOICE /C 12 /N /T 20 /D 1 /M "Select option (1-2): "
SET "MAIN_CHOICE=%ERRORLEVEL%"
IF "%MAIN_CHOICE%"=="2" GOTO :DRYRUN_MENU
REM Default or Option 1 selected
GOTO :NORMAL_MENU

:NORMAL_MENU
ECHO.
ECHO ===============================
ECHO  Select Task Execution (20s):
ECHO ===============================
ECHO 1. Execute all tasks unattended
ECHO 2. Execute only specific task numbers
ECHO.
ECHO Waiting for selection... (defaults to option 1 after 20 seconds)
CHOICE /C 12 /N /T 20 /D 1 /M "Select option (1-2): "
SET "NORMAL_CHOICE=%ERRORLEVEL%"
IF "%NORMAL_CHOICE%"=="2" GOTO :NORMAL_INSERTED
REM Default or Sub-option 1 selected
GOTO :EXECUTE_ALL

:NORMAL_INSERTED
ECHO.
SET /P TASKNUMS="Enter task numbers (comma-separated, e.g., 1,3,5): "
IF "%TASKNUMS%"=="" (
    ECHO No task numbers entered. Executing all tasks...
    GOTO :EXECUTE_ALL
)
GOTO :EXECUTE_INSERTED

:DRYRUN_MENU
ECHO.
ECHO ===============================
ECHO  Select Dry-Run Execution (20s):
ECHO ===============================
ECHO 1. Execute all tasks in dry-run unattended
ECHO 2. Execute only specific task numbers in dry-run
ECHO.
ECHO Waiting for selection... (defaults to option 1 after 20 seconds)
CHOICE /C 12 /N /T 20 /D 1 /M "Select option (1-2): "
SET "DRYRUN_CHOICE=%ERRORLEVEL%"
IF "%DRYRUN_CHOICE%"=="2" GOTO :DRYRUN_INSERTED
REM Default or Sub-option 1 selected
GOTO :EXECUTE_ALL_DRYRUN

:DRYRUN_INSERTED
ECHO.
SET /P TASKNUMS="Enter task numbers (comma-separated, e.g., 1,3,5): "
IF "%TASKNUMS%"=="" (
    ECHO No task numbers entered. Executing all tasks in dry-run...
    GOTO :EXECUTE_ALL_DRYRUN
)
GOTO :EXECUTE_INSERTED_DRYRUN

:EXECUTE_ALL
CALL :LOG_MESSAGE "Executing all tasks unattended..." "INFO" "LAUNCHER"
CD /D "%WORKING_DIR%"
"%PS_EXECUTABLE%" -ExecutionPolicy Bypass -WindowStyle Normal -File "%ORCHESTRATOR_PATH%" -NonInteractive
SET "FINAL_EXIT_CODE=!ERRORLEVEL!"
GOTO :FINAL_CLEANUP

:EXECUTE_INSERTED
CALL :LOG_MESSAGE "Executing selected tasks: %TASKNUMS%..." "INFO" "LAUNCHER"
CD /D "%WORKING_DIR%"
"%PS_EXECUTABLE%" -ExecutionPolicy Bypass -WindowStyle Normal -File "%ORCHESTRATOR_PATH%" -NonInteractive -TaskNumbers "%TASKNUMS%"
SET "FINAL_EXIT_CODE=!ERRORLEVEL!"
GOTO :FINAL_CLEANUP

:EXECUTE_ALL_DRYRUN
CALL :LOG_MESSAGE "Executing all tasks in dry-run unattended..." "INFO" "LAUNCHER"
CD /D "%WORKING_DIR%"
"%PS_EXECUTABLE%" -ExecutionPolicy Bypass -WindowStyle Normal -File "%ORCHESTRATOR_PATH%" -NonInteractive -DryRun
SET "FINAL_EXIT_CODE=!ERRORLEVEL!"
GOTO :FINAL_CLEANUP

:EXECUTE_INSERTED_DRYRUN
CALL :LOG_MESSAGE "Executing selected tasks in dry-run: %TASKNUMS%..." "INFO" "LAUNCHER"
CD /D "%WORKING_DIR%"
"%PS_EXECUTABLE%" -ExecutionPolicy Bypass -WindowStyle Normal -File "%ORCHESTRATOR_PATH%" -NonInteractive -DryRun -TaskNumbers "%TASKNUMS%"
SET "FINAL_EXIT_CODE=!ERRORLEVEL!"
GOTO :FINAL_CLEANUP

:FINAL_CLEANUP
REM -----------------------------------------------------------------------------
REM Post-Execution Cleanup and Reporting
REM -----------------------------------------------------------------------------
CALL :LOG_MESSAGE "PowerShell orchestrator final execution completed with exit code: %FINAL_EXIT_CODE%" "INFO" "LAUNCHER"

REM v3.1: Ensure bootstrap maintenance.log is organized to temp_files/logs/
REM This is a safety fallback in case PowerShell organization failed
SET "BOOTSTRAP_LOG=%ORIGINAL_SCRIPT_DIR%maintenance.log"
SET "ORGANIZED_LOG=%WORKING_DIR%temp_files\logs\maintenance.log"

IF EXIST "%BOOTSTRAP_LOG%" (
    IF EXIST "%ORGANIZED_LOG%" (
        REM Log already organized by PowerShell, append bootstrap content and delete source
        CALL :LOG_MESSAGE "Appending remaining bootstrap logs to organized location" "DEBUG" "LAUNCHER"
        TYPE "%BOOTSTRAP_LOG%" >> "%ORGANIZED_LOG%" 2>nul
        DEL /Q "%BOOTSTRAP_LOG%" >nul 2>&1
    ) ELSE (
        REM Log not yet organized, move it now
        CALL :LOG_MESSAGE "Organizing bootstrap maintenance.log to temp_files/logs/" "INFO" "LAUNCHER"
        IF NOT EXIST "%WORKING_DIR%temp_files\logs" MKDIR "%WORKING_DIR%temp_files\logs" >nul 2>&1
        MOVE /Y "%BOOTSTRAP_LOG%" "%ORGANIZED_LOG%" >nul 2>&1
        IF !ERRORLEVEL! EQU 0 (
            CALL :LOG_MESSAGE "Bootstrap log organized successfully" "SUCCESS" "LAUNCHER"
        ) ELSE (
            CALL :LOG_MESSAGE "Failed to organize bootstrap log (non-critical)" "WARN" "LAUNCHER"
        )
    )
)

IF %FINAL_EXIT_CODE% EQU 0 (
    CALL :LOG_MESSAGE "Maintenance execution completed successfully" "SUCCESS" "LAUNCHER"
) ELSE (
    CALL :LOG_MESSAGE "Maintenance execution completed with errors (exit code: %FINAL_EXIT_CODE%)" "WARN" "LAUNCHER"
)

REM Check for generated reports
IF EXIST "%WORKING_DIR%temp_files\reports" (
    FOR %%F IN ("%WORKING_DIR%temp_files\reports\*.html") DO (
        CALL :LOG_MESSAGE "Generated report: %%~nxF" "INFO" "LAUNCHER"
    )
)

CALL :LOG_MESSAGE "Interactive mode - press any key to close" "INFO" "LAUNCHER"
PAUSE >nul
EXIT /B %FINAL_EXIT_CODE%

REM -----------------------------------------------------------------------------
REM End of Script
REM -----------------------------------------------------------------------------
ENDLOCAL