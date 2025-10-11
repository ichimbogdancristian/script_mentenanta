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
SET "LOG_TIMESTAMP=%TIME:~0,8%"
SET "LEVEL=%~2"
IF "%LEVEL%"=="" SET "LEVEL=INFO"
SET "COMPONENT=%~3"
IF "%COMPONENT%"=="" SET "COMPONENT=LAUNCHER"

SET "LOG_ENTRY=[%DATE% %LOG_TIMESTAMP%] [%LEVEL%] [%COMPONENT%] %~1"

ECHO %LOG_ENTRY%
IF EXIST "%LOG_FILE%" ECHO %LOG_ENTRY% >> "%LOG_FILE%" 2>nul
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

REM Setup logging
SET "LOG_FILE=%WORKING_DIR%maintenance.log"
CALL :LOG_MESSAGE "Log file: %LOG_FILE%" "DEBUG" "LAUNCHER"

REM Environment variables for PowerShell orchestrator
SET "WORKING_DIRECTORY=%WORKING_DIR%"
SET "SCRIPT_LOG_FILE=%LOG_FILE%"

REM Repository configuration for auto-updates
SET "REPO_URL=https://github.com/ichimbogdancristian/script_mentenanta/archive/refs/heads/main.zip"
SET "ZIP_FILE=%WORKING_DIR%update.zip"
SET "EXTRACT_FOLDER=script_mentenanta-main"

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

REM Create/Verify monthly maintenance scheduled task before continuing
SET "TASK_NAME=WindowsMaintenanceAutomation"
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
REM Project Structure Discovery and Validation
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

REM Check for config directory and its contents
IF EXIST "%WORKING_DIR%config" (
    CALL :LOG_MESSAGE "✓ Found configuration directory" "SUCCESS" "LAUNCHER"
    SET /A COMPONENTS_FOUND+=1
    
    IF EXIST "%WORKING_DIR%config\main-config.json" (
        CALL :LOG_MESSAGE "  ✓ main-config.json present" "SUCCESS" "LAUNCHER"
    ) ELSE (
        CALL :LOG_MESSAGE "  ✗ main-config.json missing" "WARN" "LAUNCHER"
    )
    
    IF EXIST "%WORKING_DIR%config\bloatware-lists" (
        CALL :LOG_MESSAGE "  ✓ bloatware-lists directory present" "SUCCESS" "LAUNCHER"
    ) ELSE (
        CALL :LOG_MESSAGE "  ✗ bloatware-lists directory missing" "WARN" "LAUNCHER"
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
        
        IF EXIST "%WORKING_DIR%modules\core\ConfigManager.psm1" (
            CALL :LOG_MESSAGE "    ✓ ConfigManager.psm1 present" "SUCCESS" "LAUNCHER"
        ) ELSE (
            CALL :LOG_MESSAGE "    ✗ ConfigManager.psm1 missing" "WARN" "LAUNCHER"
        )
        
        IF EXIST "%WORKING_DIR%modules\core\MenuSystem.psm1" (
            CALL :LOG_MESSAGE "    ✓ MenuSystem.psm1 present" "SUCCESS" "LAUNCHER"
        ) ELSE (
            CALL :LOG_MESSAGE "    ✗ MenuSystem.psm1 missing" "WARN" "LAUNCHER"
        )
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
    CALL :LOG_MESSAGE "Project structure incomplete. Attempting repository download..." "INFO" "LAUNCHER"
    GOTO :DOWNLOAD_REPOSITORY
) ELSE (
    CALL :LOG_MESSAGE "Project structure validated" "SUCCESS" "LAUNCHER"
    GOTO :DEPENDENCY_MANAGEMENT
)

REM -----------------------------------------------------------------------------
REM Repository Download and Extraction
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

REM -----------------------------------------------------------------------------
REM Enhanced Dependency Management
REM -----------------------------------------------------------------------------
:DEPENDENCY_MANAGEMENT
CALL :LOG_MESSAGE "Starting dependency management..." "INFO" "LAUNCHER"

REM Windows Defender Exclusions (Enhanced)
CALL :LOG_MESSAGE "Setting up Windows Defender exclusions..." "INFO" "LAUNCHER"
powershell -ExecutionPolicy Bypass -Command "try { Add-MpPreference -ExclusionPath '%WORKING_DIR%' -ErrorAction SilentlyContinue; Add-MpPreference -ExclusionProcess 'powershell.exe' -ErrorAction SilentlyContinue; Add-MpPreference -ExclusionProcess 'pwsh.exe' -ErrorAction SilentlyContinue; Write-Host 'EXCLUSIONS_ADDED' } catch { Write-Host 'EXCLUSIONS_FAILED' }"

REM PowerShell 7 Detection and Installation
CALL :LOG_MESSAGE "Checking PowerShell 7 availability..." "INFO" "LAUNCHER"
pwsh.exe -Version >nul 2>&1
IF !ERRORLEVEL! NEQ 0 (
    CALL :LOG_MESSAGE "PowerShell 7 not found. Attempting installation..." "INFO" "LAUNCHER"
    
    REM Check if winget is available for PS7 installation
    winget --version >nul 2>&1
    IF !ERRORLEVEL! EQU 0 (
        CALL :LOG_MESSAGE "Installing PowerShell 7 via winget..." "INFO" "LAUNCHER"
        winget install Microsoft.PowerShell --silent --accept-package-agreements --accept-source-agreements
        IF !ERRORLEVEL! EQU 0 (
            CALL :LOG_MESSAGE "PowerShell 7 installed successfully via winget" "SUCCESS" "LAUNCHER"
            
            REM Refresh environment variables to pick up new PATH (preserve critical paths and add fallbacks)
            CALL :LOG_MESSAGE "Refreshing environment variables..." "INFO" "LAUNCHER"
            SET "SYSTEM_PATH="
            SET "USER_PATH="
            FOR /F "usebackq tokens=2*" %%A IN (`REG QUERY "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" /v PATH 2^>nul`) DO SET "SYSTEM_PATH=%%B"
            FOR /F "usebackq tokens=2*" %%A IN (`REG QUERY "HKCU\Environment" /v PATH 2^>nul`) DO SET "USER_PATH=%%B"

            SET "NEW_PATH="
            IF DEFINED SYSTEM_PATH SET "NEW_PATH=%SYSTEM_PATH%"
            IF DEFINED USER_PATH SET "NEW_PATH=%NEW_PATH%;%USER_PATH%"

            REM Ensure WindowsApps (App Execution Aliases like winget, pwsh) is present in PATH
            IF NOT DEFINED USER_PATH (
                IF EXIST "%LocalAppData%\Microsoft\WindowsApps" SET "NEW_PATH=%NEW_PATH%;%LocalAppData%\Microsoft\WindowsApps"
            )

            REM If PowerShell 7 default install exists, ensure its folder is included for this session
            IF EXIST "%ProgramFiles%\PowerShell\7\pwsh.exe" SET "NEW_PATH=%NEW_PATH%;%ProgramFiles%\PowerShell\7"

            REM Only overwrite PATH if we actually built a path
            IF DEFINED NEW_PATH (
                SET "PATH=%NEW_PATH%"
            ) ELSE (
                CALL :LOG_MESSAGE "PATH refresh skipped (registry values unavailable); continuing with current PATH" "WARN" "LAUNCHER"
            )

            REM Verify installation worked (prefer absolute path first)
            SET "PS7_ABSOLUTE="
            IF EXIST "%ProgramFiles%\PowerShell\7\pwsh.exe" SET "PS7_ABSOLUTE=%ProgramFiles%\PowerShell\7\pwsh.exe"
            IF DEFINED PS7_ABSOLUTE (
                CALL :LOG_MESSAGE "PowerShell 7 discovered at: %PS7_ABSOLUTE%" "SUCCESS" "LAUNCHER"
            ) ELSE (
                pwsh.exe -Version >nul 2>&1
                IF !ERRORLEVEL! EQU 0 (
                    CALL :LOG_MESSAGE "PowerShell 7 is now available after installation" "SUCCESS" "LAUNCHER"
                ) ELSE (
                    CALL :LOG_MESSAGE "PowerShell 7 installation completed but pwsh.exe still not found in PATH" "WARN" "LAUNCHER"
                    CALL :LOG_MESSAGE "You may need to restart your command prompt or add PowerShell to PATH manually" "WARN" "LAUNCHER"
                )
            )
        ) ELSE (
            CALL :LOG_MESSAGE "PowerShell 7 installation via winget failed" "WARN" "LAUNCHER"
        )
    ) ELSE (
        CALL :LOG_MESSAGE "Winget not available for PowerShell 7 installation" "WARN" "LAUNCHER"
        CALL :LOG_MESSAGE "Please install PowerShell 7 manually from: https://github.com/PowerShell/PowerShell/releases" "INFO" "LAUNCHER"
    )
) ELSE (
    FOR /F "tokens=*" %%i IN ('pwsh.exe -Command "$PSVersionTable.PSVersion.ToString()" 2^>nul') DO SET PS7_VERSION=%%i
    CALL :LOG_MESSAGE "PowerShell 7 available: %PS7_VERSION%" "SUCCESS" "LAUNCHER"
)

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
IF EXIST "%PS7_ABSOLUTE%" (
    CALL :LOG_MESSAGE "PowerShell 7 found at default installation path: %PS7_ABSOLUTE%" "DEBUG" "LAUNCHER"
    
    REM Test if the executable actually works
    "%PS7_ABSOLUTE%" -Command "exit 0" >nul 2>&1
    IF !ERRORLEVEL! EQU 0 (
        FOR /F "tokens=*" %%i IN ('"%PS7_ABSOLUTE%" -Command "$PSVersionTable.PSVersion.Major" 2^>nul') DO SET PS_MAJOR_VERSION=%%i
        IF DEFINED PS_MAJOR_VERSION IF !PS_MAJOR_VERSION! GEQ 7 (
            SET "PS_EXECUTABLE=%PS7_ABSOLUTE%"
            SET "AUTO_NONINTERACTIVE=YES"
            FOR /F "tokens=*" %%i IN ('"%PS7_ABSOLUTE%" -Command "$PSVersionTable.PSVersion.ToString()" 2^>nul') DO SET PS_VERSION_STRING=%%i
            CALL :LOG_MESSAGE "PowerShell !PS_VERSION_STRING! detected at default path - will use for system operations" "SUCCESS" "LAUNCHER"
        ) ELSE (
            CALL :LOG_MESSAGE "PowerShell found at default path but version !PS_MAJOR_VERSION! < 7" "WARN" "LAUNCHER"
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

IF "%PS_EXECUTABLE%"=="" (
    CALL :LOG_MESSAGE "PowerShell 7+ (pwsh.exe) not found after exhaustive search, checking Windows PowerShell..." "INFO" "LAUNCHER"
    REM Fallback to Windows PowerShell for system operations only (absolute path, then PATH)
    SET "PS51_ABSOLUTE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
    IF EXIST "%PS51_ABSOLUTE%" (
        FOR /F "tokens=*" %%i IN ('"%PS51_ABSOLUTE%" -Command "$PSVersionTable.PSVersion.Major" 2^>nul') DO SET PS_MAJOR_VERSION=%%i
        IF !PS_MAJOR_VERSION! GEQ 5 (
            SET "PS_EXECUTABLE=%PS51_ABSOLUTE%"
            CALL :LOG_MESSAGE "Windows PowerShell !PS_MAJOR_VERSION! will be used for system operations only (absolute path)" "INFO" "LAUNCHER"
        ) ELSE (
            CALL :LOG_MESSAGE "Windows PowerShell version !PS_MAJOR_VERSION! too old at absolute path" "WARN" "LAUNCHER"
        )
    ) ELSE (
        powershell.exe -Command "$PSVersionTable.PSVersion.Major" >nul 2>&1
        IF !ERRORLEVEL! EQU 0 (
            FOR /F "tokens=*" %%i IN ('powershell.exe -Command "$PSVersionTable.PSVersion.Major" 2^>nul') DO SET PS_MAJOR_VERSION=%%i
            IF !PS_MAJOR_VERSION! GEQ 5 (
                SET "PS_EXECUTABLE=powershell.exe"
                CALL :LOG_MESSAGE "Windows PowerShell !PS_MAJOR_VERSION! will be used for system operations only" "INFO" "LAUNCHER"
            ) ELSE (
                CALL :LOG_MESSAGE "Windows PowerShell version !PS_MAJOR_VERSION! too old" "WARN" "LAUNCHER"
            )
        )
    )
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
REM -----------------------------------------------------------------------------
CALL :LOG_MESSAGE "Ensuring System Protection is enabled on the system drive..." "INFO" "LAUNCHER"

SET "SYS_DRIVE=%SystemDrive%"
FOR /F "usebackq tokens=* delims=" %%i IN (`%PS_EXECUTABLE% -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; $drive=$env:SystemDrive.TrimEnd('\\'); $reg=Get-ItemProperty -Path 'HKLM:\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\SystemRestore' -ErrorAction SilentlyContinue; $disabled = $reg -and ($reg.DisableSR -ne 0); if ($disabled) { try { Enable-ComputerRestore -Drive \"$drive\\\" -ErrorAction Stop; Write-Host 'SR_ENABLED' } catch { try { $sr = Get-CimInstance -Namespace root/default -ClassName SystemRestore -ErrorAction Stop; $res = Invoke-CimMethod -InputObject $sr -MethodName Enable -Arguments @{ Drive = \"$drive\\\" }; if ($res.ReturnValue -eq 0) { Write-Host 'SR_ENABLED' } else { Write-Host ('SR_ENABLE_FAILED_CODE ' + $res.ReturnValue); exit 1 } } catch { Write-Host 'SR_ENABLE_FAILED'; exit 1 } } } else { Write-Host 'SR_ALREADY_ENABLED' }"`) DO SET "SR_STATUS=%%i"

IF /I "!SR_STATUS!"=="SR_ENABLED" (
    CALL :LOG_MESSAGE "System Protection was disabled and is now enabled on %SYS_DRIVE%" "SUCCESS" "LAUNCHER"
) ELSE IF /I "!SR_STATUS!"=="SR_ALREADY_ENABLED" (
    CALL :LOG_MESSAGE "System Protection already enabled on %SYS_DRIVE%" "SUCCESS" "LAUNCHER"
) ELSE (
    CALL :LOG_MESSAGE "Unable to confirm System Protection enablement (marker: !SR_STATUS!). Proceeding." "WARN" "LAUNCHER"
)

CALL :LOG_MESSAGE "Creating system restore point before execution..." "INFO" "LAUNCHER"

FOR /F "usebackq tokens=*" %%i IN (`%PS_EXECUTABLE% -NoProfile -Command "[guid]::NewGuid().ToString()" 2^>nul`) DO SET "RESTORE_GUID=%%i"
SET "RESTORE_DESC=MaintenanceRP-!RESTORE_GUID!"

REM Try creating via Checkpoint-Computer, fallback to CIM if needed
%PS_EXECUTABLE% -NoProfile -ExecutionPolicy Bypass -Command "try { Checkpoint-Computer -Description '!RESTORE_DESC!' -RestorePointType 'MODIFY_SETTINGS' -ErrorAction Stop; Write-Host 'RESTORE_CREATED' } catch { try { $sr = Get-CimInstance -Namespace root/default -ClassName SystemRestore -ErrorAction Stop; $result = Invoke-CimMethod -InputObject $sr -MethodName CreateRestorePoint -Arguments @{ Description='!RESTORE_DESC!'; RestorePointType=10; EventType=100 }; if ($result.ReturnValue -eq 0) { Write-Host 'RESTORE_CREATED' } else { Write-Host ('RESTORE_FAILED_CODE ' + $result.ReturnValue); exit 1 } } catch { Write-Host 'RESTORE_FAILED'; Write-Error $_; exit 1 } }"

IF !ERRORLEVEL! EQU 0 (
    CALL :LOG_MESSAGE "System restore point created: !RESTORE_DESC!" "SUCCESS" "LAUNCHER"

    REM Verify restore point exists and capture details
    SET "VERIFY_MARK="
    SET "RESTORE_SEQ="
    SET "RESTORE_TIME="
    FOR /F "usebackq tokens=1,2,* delims=|" %%A IN (`%PS_EXECUTABLE% -NoProfile -ExecutionPolicy Bypass -Command "$d='!RESTORE_DESC!'; $rp = Get-ComputerRestorePoint | Where-Object Description -eq $d | Sort-Object SequenceNumber -Descending | Select-Object -First 1; if ($rp) { Write-Host ('RESTORE_VERIFIED|' + $rp.SequenceNumber + '|' + $rp.CreationTime) } else { Write-Host 'RESTORE_NOT_FOUND' }" 2^>nul`) DO (
        SET "VERIFY_MARK=%%A"
        SET "RESTORE_SEQ=%%B"
        SET "RESTORE_TIME=%%C"
    )

    IF /I "!VERIFY_MARK!"=="RESTORE_VERIFIED" (
        CALL :LOG_MESSAGE "Restore point verified (Seq=!RESTORE_SEQ!, Time=!RESTORE_TIME!)" "SUCCESS" "LAUNCHER"
    ) ELSE (
        CALL :LOG_MESSAGE "Restore point verification could not locate the entry (proceeding)" "WARN" "LAUNCHER"
    )
) ELSE (
    CALL :LOG_MESSAGE "Failed to create system restore point (System Protection may be disabled). Continuing." "WARN" "LAUNCHER"
)

REM -----------------------------------------------------------------------------
REM PowerShell Orchestrator Launch
REM -----------------------------------------------------------------------------
CALL :LOG_MESSAGE "Preparing to launch PowerShell orchestrator..." "INFO" "LAUNCHER"

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
IF NOT "%PS_EXECUTABLE%"=="pwsh.exe" (
    CALL :LOG_MESSAGE "PowerShell 7+ is required for the orchestrator but not available" "ERROR" "LAUNCHER"
    CALL :LOG_MESSAGE "The MaintenanceOrchestrator.ps1 requires PowerShell Core 7.0 or higher" "ERROR" "LAUNCHER"
    CALL :LOG_MESSAGE "Please ensure PowerShell 7 is properly installed and available in PATH" "ERROR" "LAUNCHER"
    
    REM Only show interactive error if not in unattended mode
    IF NOT "%1"=="-NonInteractive" (
        ECHO.
        ECHO ===============================================
        ECHO   ERROR: PowerShell 7 Required
        ECHO ===============================================
        ECHO The maintenance orchestrator requires PowerShell 7.0 or higher.
        ECHO Please install PowerShell 7 and ensure pwsh.exe is in your PATH.
        ECHO.
        ECHO Download: https://github.com/PowerShell/PowerShell/releases
        ECHO.
        PAUSE
    )
    EXIT /B 1
)

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

REM First run the orchestrator to initialize
CALL :LOG_MESSAGE "Executing: %PS_EXECUTABLE% -ExecutionPolicy Bypass -File \"%ORCHESTRATOR_PATH%\"" "DEBUG" "LAUNCHER"
CALL :LOG_MESSAGE "Working directory: %WORKING_DIR%" "DEBUG" "LAUNCHER"

CD /D "%WORKING_DIR%"
%PS_EXECUTABLE% -ExecutionPolicy Bypass -WindowStyle Normal -File "%ORCHESTRATOR_PATH%"
SET "ORCHESTRATOR_EXIT_CODE=!ERRORLEVEL!"

CALL :LOG_MESSAGE "PowerShell orchestrator initialization completed with exit code: %ORCHESTRATOR_EXIT_CODE%" "INFO" "LAUNCHER"

REM Check if running in non-interactive mode from command line OR auto-enabling due to PS7+
IF "%1"=="-NonInteractive" (
    CALL :LOG_MESSAGE "Non-interactive mode - executing all tasks unattended" "INFO" "LAUNCHER"
    CD /D "%WORKING_DIR%"
    %PS_EXECUTABLE% -ExecutionPolicy Bypass -WindowStyle Normal -File "%ORCHESTRATOR_PATH%" -NonInteractive
    SET "FINAL_EXIT_CODE=!ERRORLEVEL!"
    GOTO :FINAL_CLEANUP
) ELSE IF "%AUTO_NONINTERACTIVE%"=="YES" (
    CALL :LOG_MESSAGE "PowerShell 7+ detected - enabling automatic unattended execution" "INFO" "LAUNCHER"
    CD /D "%WORKING_DIR%"
    %PS_EXECUTABLE% -ExecutionPolicy Bypass -WindowStyle Normal -File "%ORCHESTRATOR_PATH%" -NonInteractive
    SET "FINAL_EXIT_CODE=!ERRORLEVEL!"
    GOTO :FINAL_CLEANUP
)

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
%PS_EXECUTABLE% -ExecutionPolicy Bypass -WindowStyle Normal -File "%ORCHESTRATOR_PATH%" -NonInteractive
SET "FINAL_EXIT_CODE=!ERRORLEVEL!"
GOTO :FINAL_CLEANUP

:EXECUTE_INSERTED
CALL :LOG_MESSAGE "Executing selected tasks: %TASKNUMS%..." "INFO" "LAUNCHER"
CD /D "%WORKING_DIR%"
%PS_EXECUTABLE% -ExecutionPolicy Bypass -WindowStyle Normal -File "%ORCHESTRATOR_PATH%" -NonInteractive -TaskNumbers "%TASKNUMS%"
SET "FINAL_EXIT_CODE=!ERRORLEVEL!"
GOTO :FINAL_CLEANUP

:EXECUTE_ALL_DRYRUN
CALL :LOG_MESSAGE "Executing all tasks in dry-run unattended..." "INFO" "LAUNCHER"
CD /D "%WORKING_DIR%"
%PS_EXECUTABLE% -ExecutionPolicy Bypass -WindowStyle Normal -File "%ORCHESTRATOR_PATH%" -NonInteractive -DryRun
SET "FINAL_EXIT_CODE=!ERRORLEVEL!"
GOTO :FINAL_CLEANUP

:EXECUTE_INSERTED_DRYRUN
CALL :LOG_MESSAGE "Executing selected tasks in dry-run: %TASKNUMS%..." "INFO" "LAUNCHER"
CD /D "%WORKING_DIR%"
%PS_EXECUTABLE% -ExecutionPolicy Bypass -WindowStyle Normal -File "%ORCHESTRATOR_PATH%" -NonInteractive -DryRun -TaskNumbers "%TASKNUMS%"
SET "FINAL_EXIT_CODE=!ERRORLEVEL!"
GOTO :FINAL_CLEANUP

:FINAL_CLEANUP
REM -----------------------------------------------------------------------------
REM Post-Execution Cleanup and Reporting
REM -----------------------------------------------------------------------------
CALL :LOG_MESSAGE "PowerShell orchestrator final execution completed with exit code: %FINAL_EXIT_CODE%" "INFO" "LAUNCHER"

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