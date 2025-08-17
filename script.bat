@echo off
REM ============================================================================
REM  script_mentenanta - Windows Maintenance Automation Launcher (Refactored)
REM  Purpose: Entry point for all maintenance operations. Handles dependency
REM           installation, scheduled task setup, repo download/update
REM           and launches PowerShell orchestrator (script.ps1).
REM  Environment: Requires Administrator, Windows 10/11, PowerShell 5.1+.
REM  All actions are logged to console and maintenance.log file.
REM ============================================================================
SETLOCAL ENABLEDELAYEDEXPANSION

REM -----------------------------------------------------------------------------
REM Enhanced Path and Permission Management
REM -----------------------------------------------------------------------------
REM Normalize script paths to ensure consistent operation regardless of launch location
SET "SCRIPT_PATH=%~f0"
SET "SCRIPT_DIR=%~dp0"
SET "SCRIPT_NAME=%~nx0"
SET "CURRENT_DIR=%CD%"

REM Remove trailing backslash from script directory if present
IF "!SCRIPT_DIR:~-1!"=="\" SET "SCRIPT_DIR=!SCRIPT_DIR:~0,-1!"

REM Validate critical paths exist BEFORE any operations
IF NOT EXIST "!SCRIPT_PATH!" (
    ECHO ERROR: Script file not accessible: !SCRIPT_PATH!
    PAUSE
    EXIT /B 1
)

IF NOT EXIST "!SCRIPT_DIR!" (
    ECHO ERROR: Script directory not accessible: !SCRIPT_DIR!
    PAUSE
    EXIT /B 1
)

REM Ensure we're working from the script's directory
CD /D "!SCRIPT_DIR!" >nul 2>&1
IF %ERRORLEVEL% NEQ 0 (
    ECHO ERROR: Cannot change to script directory: !SCRIPT_DIR!
    PAUSE
    EXIT /B 1
)

REM Initialize LOG_FILE early for logging functions
SET "LOG_FILE=!SCRIPT_DIR!\maintenance.log"

REM Enhanced path detection and validation (now with early logging)
CALL :LOG_ENTRY "INFO" "Script Full Path: !SCRIPT_PATH!"
CALL :LOG_ENTRY "INFO" "Script Directory: !SCRIPT_DIR!"
CALL :LOG_ENTRY "INFO" "Script Name: !SCRIPT_NAME!"
CALL :LOG_ENTRY "INFO" "Original Working Directory: !CURRENT_DIR!"
CALL :LOG_ENTRY "INFO" "Current Working Directory: %CD%"

REM EARLY Admin privilege detection (before any operations)
CALL :DETECT_ADMIN_PRIVILEGES
IF "!IS_ADMIN!"=="NO" (
    CALL :LOG_ENTRY "WARN" "Script not running with administrator privileges"
    CALL :LOG_ENTRY "INFO" "Attempting to relaunch with administrator privileges..."
    REM Capture all arguments properly
    SET "ALL_ARGS=%*"
    IF DEFINED ALL_ARGS (
        CALL :REQUEST_ADMIN_PRIVILEGES "!SCRIPT_PATH!" "!ALL_ARGS!"
    ) ELSE (
        CALL :REQUEST_ADMIN_PRIVILEGES "!SCRIPT_PATH!" ""
    )
    REM If we reach here, elevation attempt was made but may have failed
    CALL :LOG_ENTRY "INFO" "Elevation attempt completed. Current window will exit."
    timeout /t 2 /nobreak >nul
    EXIT /B 0
) ELSE (
    CALL :LOG_ENTRY "INFO" "✓ Running with administrator privileges"
)

REM -----------------------------------------------------------------------------
REM Basic Environment Setup and Logging
REM -----------------------------------------------------------------------------
SET "TASK_NAME=ScriptMentenantaMonthly"
SET "STARTUP_TASK_NAME=ScriptMentenantaStartup"
REM Note: SCRIPT_PATH and LOG_FILE already set in path management section above

REM Create or append to maintenance.log
ECHO [%DATE% %TIME%] [INFO] ============================================================ >> "!LOG_FILE!"
ECHO [%DATE% %TIME%] [INFO] Starting Windows Maintenance Automation Script >> "!LOG_FILE!"
ECHO [%DATE% %TIME%] [INFO] Batch Script: !SCRIPT_PATH! >> "!LOG_FILE!"
ECHO [%DATE% %TIME%] [INFO] Batch Script Directory: !SCRIPT_DIR! >> "!LOG_FILE!"
ECHO [%DATE% %TIME%] [INFO] Log File: !LOG_FILE! >> "!LOG_FILE!"
ECHO [%DATE% %TIME%] [INFO] User: %USERNAME%, Computer: %COMPUTERNAME% >> "!LOG_FILE!"
ECHO [%DATE% %TIME%] [INFO] ============================================================ >> "!LOG_FILE!"

REM Function to log both to console and file
ECHO.
ECHO ============================================================
ECHO    Windows Maintenance Automation Script - STARTING
ECHO ============================================================
ECHO.
CALL :LOG_ENTRY "INFO" "Starting maintenance script..."
CALL :LOG_ENTRY "INFO" "User: %USERNAME%, Computer: %COMPUTERNAME%"

REM Check if this is a restart after PowerShell 7 installation
IF "%1"=="PS7_RESTART" (
    CALL :LOG_ENTRY "INFO" "Script restarted after PowerShell 7 installation."
    GOTO :SKIP_PS7_INSTALL
)

REM -----------------------------------------------------------------------------
REM Admin Privilege Verification (Enhanced detection already performed)
REM -----------------------------------------------------------------------------
ECHO.
ECHO [INFO] Verifying Administrator privileges...
REM Admin privileges already verified during startup - this is just a confirmation
IF "!IS_ADMIN!"=="YES" (
    CALL :LOG_ENTRY "INFO" "✓ Administrator privileges confirmed"
) ELSE (
    CALL :LOG_ENTRY "ERROR" "Administrator privileges verification failed"
    ECHO.
    ECHO ERROR: This script requires administrator privileges to function properly.
    ECHO Please restart the script as an administrator.
    ECHO.
    PAUSE
    EXIT /B 1
)

REM -----------------------------------------------------------------------------
REM PowerShell Path Detection and Version Check
REM Ensures PowerShell 5.1+ is available and sets proper paths.
REM -----------------------------------------------------------------------------

REM Detect PowerShell executable path with multiple fallbacks
SET "POWERSHELL_EXE="

REM Method 1: Check standard 64-bit location
IF EXIST "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" (
    SET "POWERSHELL_EXE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
    CALL :LOG_ENTRY "INFO" "Found PowerShell at standard 64-bit location"
    GOTO :found_ps
)

REM Method 2: Check 32-bit location
IF EXIST "%SystemRoot%\SysWOW64\WindowsPowerShell\v1.0\powershell.exe" (
    SET "POWERSHELL_EXE=%SystemRoot%\SysWOW64\WindowsPowerShell\v1.0\powershell.exe"
    CALL :LOG_ENTRY "INFO" "Found PowerShell at 32-bit location"
    GOTO :found_ps
)

REM Method 3: Use WHERE command to find in PATH
WHERE powershell.exe >nul 2>&1
IF %ERRORLEVEL% EQU 0 (
    FOR /F "tokens=*" %%i IN ('WHERE powershell.exe 2^>nul') DO (
        SET "POWERSHELL_EXE=%%i"
        CALL :LOG_ENTRY "INFO" "Found PowerShell via PATH: %%i"
        GOTO :found_ps
    )
)

REM Method 4: Check Program Files locations
IF EXIST "%ProgramFiles%\PowerShell\pwsh.exe" (
    SET "POWERSHELL_EXE=%ProgramFiles%\PowerShell\pwsh.exe"
    CALL :LOG_ENTRY "INFO" "Found PowerShell 7 at Program Files"
    GOTO :found_ps
)

REM All methods failed
CALL :LOG_ENTRY "ERROR" "PowerShell executable not found. Please install Windows PowerShell."
ECHO.
ECHO ERROR: PowerShell is required for this script to function.
ECHO Please install Windows PowerShell 5.1 or newer and try again.
ECHO.
PAUSE
EXIT /B 3
:found_ps

CALL :LOG_ENTRY "INFO" "Using PowerShell: %POWERSHELL_EXE%"

REM Test PowerShell functionality first
"%POWERSHELL_EXE%" -ExecutionPolicy Bypass -Command "Write-Host 'PowerShell is functional'" >nul 2>&1
IF %ERRORLEVEL% NEQ 0 (
    CALL :LOG_ENTRY "ERROR" "PowerShell executable found but not functional."
    pause
    EXIT /B 3
)

REM Get PowerShell version with execution policy bypass and error handling
SET "PS_VERSION="
FOR /F "tokens=*" %%i IN ('"%POWERSHELL_EXE%" -ExecutionPolicy Bypass -Command "try { $PSVersionTable.PSVersion.Major } catch { 5 }" 2^>nul') DO SET PS_VERSION=%%i
IF "%PS_VERSION%"=="" (
    CALL :LOG_ENTRY "WARN" "Could not determine PowerShell version, assuming version 5"
    SET PS_VERSION=5
)
REM Validate PS_VERSION is numeric
ECHO %PS_VERSION%| findstr /r "^[0-9][0-9]*$" >nul
IF %ERRORLEVEL% NEQ 0 (
    CALL :LOG_ENTRY "WARN" "Invalid PowerShell version detected, defaulting to 5"
    SET PS_VERSION=5
)
IF %PS_VERSION% LSS 5 (
    CALL :LOG_ENTRY "ERROR" "PowerShell 5.1 or higher is required. Current version: %PS_VERSION%"
    CALL :LOG_ENTRY "ERROR" "Please install PowerShell 5.1 or newer and try again."
    pause
    EXIT /B 3
)
CALL :LOG_ENTRY "INFO" "PowerShell version: %PS_VERSION%"

REM -----------------------------------------------------------------------------
REM Windows Version Detection - Simplified for CMD Environment
REM -----------------------------------------------------------------------------
REM Simple Windows Version Detection (avoid complex PowerShell early)
SET "WINVER=Unknown"
SET "WINVER_MAJOR="
SET "WINVER_MINOR="
SET "WINVER_BUILD="
SET "WINVER_NAME=Unknown"

REM Method 1: Registry (most reliable in CMD)
FOR /F "tokens=3" %%v IN ('REG QUERY "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion" /v CurrentVersion 2^>nul') DO SET WINVER=%%v
IF NOT "%WINVER%"=="" IF NOT "%WINVER%"=="Unknown" (
    FOR /F "tokens=1,2 delims=." %%a IN ("%WINVER%") DO (
        SET WINVER_MAJOR=%%a
        SET WINVER_MINOR=%%b
    )
    REM Get build number from registry
    FOR /F "tokens=3" %%v IN ('REG QUERY "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion" /v CurrentBuildNumber 2^>nul') DO SET WINVER_BUILD=%%v
) ELSE (
    REM Method 2: VER command fallback
    FOR /F "tokens=2 delims=[]" %%v IN ('VER') DO (
        FOR /F "tokens=2 delims= " %%w IN ("%%v") DO SET WINVER=%%w
    )
)
        FOR /F "tokens=1-3 delims=." %%a IN ("%WINVER%") DO (
            SET WINVER_MAJOR=%%a
            SET WINVER_MINOR=%%b
            SET WINVER_BUILD=%%c
        )
    ) ELSE (
        REM Method 3: systeminfo
        FOR /F "tokens=2 delims=: " %%v IN ('systeminfo | findstr /C:"OS Version"') DO SET WINVER=%%v
        IF NOT "%WINVER%"=="" IF NOT "%WINVER%"=="Unknown" (
            FOR /F "tokens=1-3 delims=." %%a IN ("%WINVER%") DO (
                SET WINVER_MAJOR=%%a
                SET WINVER_MINOR=%%b
                SET WINVER_BUILD=%%c
            )
        )
    )
)

REM Improved normalization for Windows 10/11
IF "%WINVER_MAJOR%"=="10" SET WINVER_NAME=Windows 10
IF "%WINVER_MAJOR%"=="11" SET WINVER_NAME=Windows 11
REM If build number is 22000 or higher, it's Windows 11
IF NOT "%WINVER_BUILD%"=="" IF %WINVER_BUILD% GEQ 22000 SET WINVER_NAME=Windows 11
REM If build number is 10240 or higher, it's Windows 10+
IF NOT "%WINVER_BUILD%"=="" IF %WINVER_BUILD% GEQ 10240 IF %WINVER_BUILD% LSS 22000 SET WINVER_NAME=Windows 10
REM If still unknown, fallback to version string
IF "%WINVER_NAME%"=="Unknown" IF "%WINVER_MAJOR%"=="6" IF "%WINVER_MINOR%"=="3" SET WINVER_NAME=Windows 8.1
CALL :LOG_ENTRY "INFO" "Detected Windows version: %WINVER_MAJOR%.%WINVER_MINOR%.%WINVER_BUILD% (%WINVER_NAME%)"

REM -----------------------------------------------------------------------------
REM Enhanced Monthly Scheduled Task Setup
REM Ensures a monthly scheduled task is created to run this script as admin.
REM -----------------------------------------------------------------------------
CALL :LOG_ENTRY "INFO" "Checking for monthly scheduled task '%TASK_NAME%'..."
schtasks /Query /TN "%TASK_NAME%" >nul 2>&1
IF %ERRORLEVEL% EQU 0 (
    CALL :LOG_ENTRY "INFO" "Monthly scheduled task already exists. Skipping creation."
) ELSE (
    CALL :LOG_ENTRY "INFO" "Monthly scheduled task not found. Creating with multiple methods..."
    
    REM METHOD 1: Try with SYSTEM account
    schtasks /Create ^
        /SC MONTHLY ^
        /MO 1 ^
        /D 1 ^
        /TN "%TASK_NAME%" ^
        /TR "\"!SCRIPT_PATH!\"" ^
        /ST 01:00 ^
        /RL HIGHEST ^
        /RU SYSTEM ^
        /F >nul 2>&1
    
    IF %ERRORLEVEL% EQU 0 (
        CALL :LOG_ENTRY "INFO" "Monthly scheduled task created successfully with SYSTEM account."
    ) ELSE (
        CALL :LOG_ENTRY "WARN" "SYSTEM account method failed (Error: %ERRORLEVEL%). Trying with current user..."
        
        REM METHOD 2: Try with current user account
        schtasks /Create ^
            /SC MONTHLY ^
            /MO 1 ^
            /D 1 ^
            /TN "%TASK_NAME%" ^
            /TR "\"!SCRIPT_PATH!\"" ^
            /ST 01:00 ^
            /RL HIGHEST ^
            /RU "%USERNAME%" ^
            /F >nul 2>&1
        
        IF %ERRORLEVEL% EQU 0 (
            CALL :LOG_ENTRY "INFO" "Monthly scheduled task created successfully with user account."
        ) ELSE (
            CALL :LOG_ENTRY "WARN" "User account method failed (Error: %ERRORLEVEL%). Trying PowerShell method..."
            
            REM METHOD 3: Try with simple PowerShell command
            "%POWERSHELL_EXE%" -ExecutionPolicy Bypass -Command "Register-ScheduledTask -TaskName '%TASK_NAME%' -Action (New-ScheduledTaskAction -Execute 'cmd.exe' -Argument '/c \"!SCRIPT_PATH!\"') -Trigger (New-ScheduledTaskTrigger -Monthly -At '01:00' -DaysOfMonth 1) -RunLevel Highest -Force" >nul 2>&1
            
            REM Verify any method worked
            schtasks /Query /TN "%TASK_NAME%" >nul 2>&1
            IF %ERRORLEVEL% EQU 0 (
                CALL :LOG_ENTRY "INFO" "Monthly scheduled task created successfully via PowerShell."
            ) ELSE (
                CALL :LOG_ENTRY "ERROR" "All scheduled task creation methods failed. Continuing without scheduled task."
            )
        )
    )
    
    REM Final verification
    schtasks /Query /TN "%TASK_NAME%" >nul 2>&1
    IF %ERRORLEVEL% EQU 0 (
        CALL :LOG_ENTRY "INFO" "Task verification successful."
    )
)

REM -----------------------------------------------------------------------------
REM Startup Task Management and Restart Detection Logic
REM Step 1: Check if startup task exists - if yes, delete it
REM Step 2: Check for pending restarts using comprehensive detection
REM Step 3: If pending restarts found, create startup task with 1-minute delay
REM Step 4: Restart the system
REM -----------------------------------------------------------------------------

REM Step 1: Check and remove existing startup task if it exists
CALL :LOG_ENTRY "INFO" "Step 1: Checking startup task '%STARTUP_TASK_NAME%'..."
schtasks /Query /TN "%STARTUP_TASK_NAME%" >nul 2>&1
IF %ERRORLEVEL% EQU 0 (
    CALL :LOG_ENTRY "INFO" "Existing startup task found. Removing..."
    schtasks /Delete /TN "%STARTUP_TASK_NAME%" /F >nul 2>&1
    IF %ERRORLEVEL% EQU 0 (
        CALL :LOG_ENTRY "INFO" "Startup task removed successfully."
    ) ELSE (
        CALL :LOG_ENTRY "WARN" "Failed to remove startup task, but continuing..."
    )
) ELSE (
    CALL :LOG_ENTRY "INFO" "No existing startup task found."
)

REM Step 2: Comprehensive restart detection - Using individual checks
CALL :LOG_ENTRY "INFO" "Step 2: Checking for pending system restarts..."
SET "RESTART_NEEDED=NO"
SET "RESTART_COUNT=0"

REM Check Windows Update reboot flag
REG QUERY "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired" >nul 2>&1
IF %ERRORLEVEL% EQU 0 (
    SET "RESTART_NEEDED=YES"
    SET /A RESTART_COUNT+=1
    CALL :LOG_ENTRY "INFO" "Windows Update reboot flag detected"
)

REM Check Component Based Servicing reboot flag
REG QUERY "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending" >nul 2>&1
IF %ERRORLEVEL% EQU 0 (
    SET "RESTART_NEEDED=YES"
    SET /A RESTART_COUNT+=1
    CALL :LOG_ENTRY "INFO" "Component Based Servicing reboot detected"
)

REM Check pending file operations
REG QUERY "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager" /v PendingFileRenameOperations >nul 2>&1
IF %ERRORLEVEL% EQU 0 (
    SET "RESTART_NEEDED=YES"
    SET /A RESTART_COUNT+=1
    CALL :LOG_ENTRY "INFO" "Pending file operations detected"
)

REM Check Windows Feature installation requiring restart
REG QUERY "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\PackagesPending" >nul 2>&1
IF %ERRORLEVEL% EQU 0 (
    SET "RESTART_NEEDED=YES"
    SET /A RESTART_COUNT+=1
    CALL :LOG_ENTRY "INFO" "Windows Features pending restart detected"
)

REM Check for computer name change using simple approach
FOR /F "tokens=3" %%A IN ('REG QUERY "HKLM\SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName" /v ComputerName 2^>nul') DO SET "CURRENT_NAME=%%A"
FOR /F "tokens=3" %%B IN ('REG QUERY "HKLM\SYSTEM\CurrentControlSet\Control\ComputerName\ActiveComputerName" /v ComputerName 2^>nul') DO SET "ACTIVE_NAME=%%B"
IF NOT "%CURRENT_NAME%"=="%ACTIVE_NAME%" (
    SET "RESTART_NEEDED=YES"
    SET /A RESTART_COUNT+=1
    CALL :LOG_ENTRY "INFO" "Computer name change pending restart detected"
)

REM Debug and proceed with restart logic
CALL :LOG_ENTRY "DEBUG" "RESTART_NEEDED=%RESTART_NEEDED%, RESTART_COUNT=%RESTART_COUNT%"

REM Step 3 & 4: Handle restart using simple conditional logic
IF "%RESTART_NEEDED%"=="YES" (
    CALL :LOG_ENTRY "WARN" "System restart required - %RESTART_COUNT% conditions detected"
    CALL :LOG_ENTRY "INFO" "Step 3: Creating startup task for post-restart continuation..."
    
    REM Show task creation parameters
    CALL :LOG_ENTRY "DEBUG" "Task name: %STARTUP_TASK_NAME%"
    CALL :LOG_ENTRY "DEBUG" "Script path: !SCRIPT_PATH!"
    CALL :LOG_ENTRY "DEBUG" "User: %USERNAME%"
    
    REM Create startup task with multiple methods
    REM METHOD 1: Try with current user
    schtasks /Create /SC ONLOGON /TN "%STARTUP_TASK_NAME%" /TR "\"!SCRIPT_PATH!\"" /RL HIGHEST /RU "%USERNAME%" /DELAY 0001:00 /F >nul 2>&1
    IF %ERRORLEVEL% EQU 0 (
        CALL :LOG_ENTRY "INFO" "Startup task created successfully with user account"
    ) ELSE (
        CALL :LOG_ENTRY "WARN" "User account startup task failed (Error: %ERRORLEVEL%). Trying SYSTEM account..."
        
        REM METHOD 2: Try with SYSTEM account
        schtasks /Create /SC ONLOGON /TN "%STARTUP_TASK_NAME%" /TR "\"!SCRIPT_PATH!\"" /RL HIGHEST /RU "SYSTEM" /DELAY 0001:00 /F >nul 2>&1
        IF %ERRORLEVEL% EQU 0 (
            CALL :LOG_ENTRY "INFO" "Startup task created successfully with SYSTEM account"
        ) ELSE (
            CALL :LOG_ENTRY "WARN" "SYSTEM account startup task failed (Error: %ERRORLEVEL%). Trying PowerShell method..."
            
            REM METHOD 3: Try with simple PowerShell command
            "%POWERSHELL_EXE%" -ExecutionPolicy Bypass -Command "Register-ScheduledTask -TaskName '%STARTUP_TASK_NAME%' -Action (New-ScheduledTaskAction -Execute 'cmd.exe' -Argument '/c \"!SCRIPT_PATH!\"') -Trigger (New-ScheduledTaskTrigger -AtLogOn) -RunLevel Highest -Force" >nul 2>&1
            IF %ERRORLEVEL% EQU 0 (
                CALL :LOG_ENTRY "INFO" "Startup task created successfully with PowerShell method"
            ) ELSE (
                CALL :LOG_ENTRY "ERROR" "All startup task creation methods failed. Continuing without restart..."
            )
        )
    )
    
    REM Verify startup task creation
    schtasks /Query /TN "%STARTUP_TASK_NAME%" >nul 2>&1
    IF %ERRORLEVEL% EQU 0 (
        CALL :LOG_ENTRY "INFO" "Startup task verification successful"
        CALL :LOG_ENTRY "INFO" "Step 4: Initiating system restart in 20 seconds..."
        ECHO.
        ECHO =====================================================
        ECHO   SYSTEM RESTART REQUIRED
        ECHO   %RESTART_COUNT% restart conditions detected
        ECHO   Restarting in 20 seconds...
        ECHO   Press Ctrl+C to abort restart
        ECHO =====================================================
        ECHO.
        timeout /t 20
        shutdown /r /t 5 /c "System restart required for maintenance"
        EXIT /B 0
    ) ELSE (
        CALL :LOG_ENTRY "ERROR" "All startup task creation methods failed. Continuing without restart..."
        CALL :LOG_ENTRY "INFO" "Continuing without restart..."
    )
) ELSE (
    CALL :LOG_ENTRY "INFO" "No pending restart detected. Continuing with maintenance..."
)
    CALL :LOG_ENTRY "INFO" "No pending restart detected. Continuing with maintenance..."
)

REM -----------------------------------------------------------------------------
REM Dependency Management - Hierarchical Installation Order
REM PHASE 1: Core System Dependencies (required for package managers)
REM PHASE 2: Package Managers (Winget)  
REM PHASE 3: Development Tools (using package managers)
REM PHASE 4: PowerShell Environment (modules and package managers)
REM -----------------------------------------------------------------------------
ECHO.
ECHO ========================================
ECHO     Installing Required Dependencies
ECHO     (Hierarchical Dependency Order)
ECHO ========================================
ECHO.
CALL :LOG_ENTRY "INFO" "Starting dependency installation with proper hierarchical order..."

REM =============================================================================
REM PHASE 1: CORE SYSTEM DEPENDENCIES (Required for Winget and other tools)
REM =============================================================================
ECHO.
ECHO ----------------------------------------
ECHO   PHASE 1: Core System Dependencies
ECHO ----------------------------------------

REM -----------------------------------------------------------------------------
REM 1A. Visual C++ Redistributables - Required for Winget and many applications
REM -----------------------------------------------------------------------------
CALL :LOG_ENTRY "INFO" "PHASE 1A: Installing Visual C++ Redistributables (Winget dependency)..."
CALL :LOG_ENTRY "INFO" "Checking Visual C++ Redistributable 2015-2022 x64..."

REM Simple check using registry
REG QUERY "HKLM\SOFTWARE\Classes\Installer\Dependencies" /s | FIND "Microsoft Visual C++ 2015-2022 Redistributable" >nul 2>&1
IF %ERRORLEVEL% EQU 0 (
    CALL :LOG_ENTRY "INFO" "Visual C++ Redistributable is already installed, skipping installation."
) ELSE (
    CALL :LOG_ENTRY "INFO" "Installing Visual C++ Redistributable..."
    
    REM Simple download and install approach
    SET "VC_URL=https://aka.ms/vs/17/release/vc_redist.x64.exe"
    SET "VC_FILE=%TEMP%\vc_redist.exe"
    
    REM Download using PowerShell (simple command)
    "%POWERSHELL_EXE%" -ExecutionPolicy Bypass -Command "Invoke-WebRequest -Uri '%VC_URL%' -OutFile '%VC_FILE%'" >nul 2>&1
    IF %ERRORLEVEL% EQU 0 (
        REM Install silently
        "%VC_FILE%" /quiet /norestart
        DEL "%VC_FILE%" >nul 2>&1
        CALL :LOG_ENTRY "INFO" "Visual C++ Redistributable installation completed."
    ) ELSE (
        CALL :LOG_ENTRY "WARN" "Visual C++ download failed, skipping installation."
    )
)

REM -----------------------------------------------------------------------------
REM 1B. Microsoft.UI.Xaml Framework - Skipped (handled by Winget installer)
CALL :LOG_ENTRY "INFO" "PHASE 1B: Skipping Microsoft.UI.Xaml; Winget installer will handle dependencies if required."

REM =============================================================================
REM PHASE 2: PACKAGE MANAGERS (Now that core dependencies are installed)
REM =============================================================================
ECHO.
ECHO ----------------------------------------
ECHO   PHASE 2: Package Managers
ECHO ----------------------------------------

REM -----------------------------------------------------------------------------
REM 2A. Windows Package Manager (Winget) - Primary package manager with 5 fallback methods
REM METHOD 1: Register existing installation (fastest)
REM METHOD 2: GitHub direct download with API fallback (most reliable)  
REM METHOD 3: Microsoft Store API with multiple endpoints (official)
REM METHOD 4: Chocolatey emergency bootstrap (alternative ecosystem)
REM METHOD 5: Windows features + DISM approach (system-level)
REM -----------------------------------------------------------------------------
CALL :LOG_ENTRY "INFO" "PHASE 2A: Installing Windows Package Manager (Winget)..."

REM Simple Winget check and install
winget --version >nul 2>&1
IF %ERRORLEVEL% EQU 0 (
    CALL :LOG_ENTRY "INFO" "Winget is already installed and functional."
    SET "WINGET_AVAILABLE=YES"
) ELSE (
    CALL :LOG_ENTRY "INFO" "Installing Winget with multiple fallback methods..."
    
    REM METHOD 1: Try to register existing Winget installation (multiple approaches)
    CALL :LOG_ENTRY "INFO" "Method 1: Attempting to register existing Winget..."
    
    REM Try standard registration first
    "%POWERSHELL_EXE%" -ExecutionPolicy Bypass -Command "Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe" >nul 2>&1
    
    REM Try alternative registration methods
    "%POWERSHELL_EXE%" -ExecutionPolicy Bypass -Command "Get-AppxPackage -AllUsers | Where-Object {$_.Name -like '*DesktopAppInstaller*'} | ForEach-Object { Add-AppxPackage -Register ($_.InstallLocation + '\AppxManifest.xml') -DisableDevelopmentMode }" >nul 2>&1
    
    REM Try reset/repair method
    "%POWERSHELL_EXE%" -ExecutionPolicy Bypass -Command "Get-AppxPackage Microsoft.DesktopAppInstaller -AllUsers | Reset-AppxPackage" >nul 2>&1
    
    REM Check if Method 1 worked
    timeout /t 2 /nobreak >nul
    winget --version >nul 2>&1
    IF %ERRORLEVEL% EQU 0 (
        CALL :LOG_ENTRY "INFO" "Method 1 SUCCESS: Winget is now functional via registration."
        SET "WINGET_AVAILABLE=YES"
        GOTO :WINGET_VALIDATION
    )
    
    REM METHOD 2: Download latest MSIX bundle from GitHub (with mirror URLs)
    REM METHOD 2: Simple GitHub download approach
    CALL :LOG_ENTRY "INFO" "Method 2: Downloading Winget from GitHub..."
    SET "WINGET_URL=https://github.com/microsoft/winget-cli/releases/latest/download/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"
    SET "WINGET_FILE=%TEMP%\winget_latest.msixbundle"
    
    REM Download using simple PowerShell command
    "%POWERSHELL_EXE%" -ExecutionPolicy Bypass -Command "Invoke-WebRequest -Uri '%WINGET_URL%' -OutFile '%WINGET_FILE%'" >nul 2>&1
    IF %ERRORLEVEL% EQU 0 (
        REM Install the package
        "%POWERSHELL_EXE%" -ExecutionPolicy Bypass -Command "Add-AppxPackage -Path '%WINGET_FILE%'" >nul 2>&1
        DEL "%WINGET_FILE%" >nul 2>&1
    )
    
    REM Check if Method 2 worked
    timeout /t 3 /nobreak >nul
    winget --version >nul 2>&1
    IF %ERRORLEVEL% EQU 0 (
        CALL :LOG_ENTRY "INFO" "Method 2 SUCCESS: Winget is now functional via GitHub download."
        SET "WINGET_AVAILABLE=YES"
        GOTO :WINGET_VALIDATION
    )
    
    REM METHOD 3: Skip Store API (too complex for CMD environment)
    CALL :LOG_ENTRY "INFO" "Method 3: Skipping Store API method (complex operation deferred to script.ps1)"
        SET "WINGET_AVAILABLE=YES"
        GOTO :WINGET_VALIDATION
    )
    
    REM METHOD 4: Chocolatey bootstrap (if all else fails, we can use choco to install winget)
    CALL :LOG_ENTRY "INFO" "Method 4: Emergency Chocolatey bootstrap for Winget..."
    REM METHOD 4: Simple Chocolatey approach
    CALL :LOG_ENTRY "INFO" "Method 4: Attempting Chocolatey installation..."
    
    REM Install Chocolatey first (simple approach)
    "%POWERSHELL_EXE%" -ExecutionPolicy Bypass -Command "Set-ExecutionPolicy Bypass -Scope Process -Force; iex ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))" >nul 2>&1
    
    REM Check if choco is available and install winget
    WHERE choco >nul 2>&1
    IF %ERRORLEVEL% EQU 0 (
        choco install winget --yes --no-progress --limit-output >nul 2>&1
        CALL :LOG_ENTRY "INFO" "Winget installation via Chocolatey attempted"
    ) ELSE (
        CALL :LOG_ENTRY "WARN" "Chocolatey installation failed"
    )
    
    REM Check if Method 4 worked
    timeout /t 5 /nobreak >nul
    CALL :REFRESH_ENV
    winget --version >nul 2>&1
    IF %ERRORLEVEL% EQU 0 (
        CALL :LOG_ENTRY "INFO" "Method 4 SUCCESS: Winget is now functional via Chocolatey emergency install."
        SET "WINGET_AVAILABLE=YES"
        GOTO :WINGET_VALIDATION
    )
    
    REM METHOD 5: Enable Windows optional features and try DISM approach
    CALL :LOG_ENTRY "INFO" "Method 5: Enabling Windows features and DISM approach..."
    "%POWERSHELL_EXE%" -ExecutionPolicy Bypass -Command "try { Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-AppPlatform -All -NoRestart -ErrorAction SilentlyContinue; Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-DesktopExperience -All -NoRestart -ErrorAction SilentlyContinue; dism /online /add-capability /capabilityname:App.Support.QuickAssist~~~~0.0.1.0 /norestart; Write-Host '[INFO] Windows features enabled for App support' } catch { Write-Host '[WARN] Windows features method failed:' $_.Exception.Message }"
    
    REM Try registration again after enabling features
    "%POWERSHELL_EXE%" -ExecutionPolicy Bypass -Command "try { Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe; Write-Host '[INFO] Winget registered after Windows features enabled' } catch { Write-Host '[WARN] Final registration attempt failed:' $_.Exception.Message }"
    
    REM Final check after all methods
    timeout /t 5 /nobreak >nul
    CALL :REFRESH_ENV
    winget --version >nul 2>&1
    IF %ERRORLEVEL% EQU 0 (
        CALL :LOG_ENTRY "INFO" "Method 5 SUCCESS: Winget is now functional after Windows features enabled."
        SET "WINGET_AVAILABLE=YES"
    ) ELSE (
        CALL :LOG_ENTRY "ERROR" "ALL METHODS FAILED: Winget installation unsuccessful after 5 attempts."
        CALL :LOG_ENTRY "WARN" "Will continue with alternative installation methods for other packages."
        SET "WINGET_AVAILABLE=NO"
    )
)

:WINGET_VALIDATION

REM -----------------------------------------------------------------------------
REM Winget Final Validation and Configuration
REM -----------------------------------------------------------------------------
CALL :LOG_ENTRY "INFO" "Performing comprehensive Winget validation..."

IF "%WINGET_AVAILABLE%"=="YES" (
    REM Test basic functionality
    winget --version >nul 2>&1
    IF %ERRORLEVEL% EQU 0 (
        REM Test source access
        winget source list >nul 2>&1
        IF %ERRORLEVEL% EQU 0 (
            REM Test search functionality (quick test)
            winget search Microsoft.VisualStudioCode --exact >nul 2>&1
            IF %ERRORLEVEL% EQU 0 (
                CALL :LOG_ENTRY "INFO" "Winget validation PASSED - All functionality confirmed."
                REM Configure Winget for optimal performance
                "%POWERSHELL_EXE%" -ExecutionPolicy Bypass -Command "try { winget settings --enable LocalManifestFiles; winget settings --enable LocalArchiveMalwareScanOverride; Write-Host '[INFO] Winget settings optimized' } catch { Write-Host '[INFO] Winget settings optimization skipped (not critical)' }"
            ) ELSE (
                CALL :LOG_ENTRY "WARN" "Winget search test failed - basic functionality only."
            )
        ) ELSE (
            CALL :LOG_ENTRY "WARN" "Winget source access failed - limited functionality."
        )
    ) ELSE (
        CALL :LOG_ENTRY "ERROR" "Winget validation failed - marking as unavailable."
        SET "WINGET_AVAILABLE=NO"
    )
) ELSE (
    CALL :LOG_ENTRY "WARN" "Winget is not available - will use alternative package installation methods."
)

REM Show final Winget status
IF "%WINGET_AVAILABLE%"=="YES" (
    FOR /F "tokens=*" %%i IN ('winget --version 2^>nul') DO SET WINGET_VERSION=%%i
    CALL :LOG_ENTRY "INFO" "✓ Winget Status: Available (Version: %WINGET_VERSION%)"
) ELSE (
    CALL :LOG_ENTRY "INFO" "✗ Winget Status: Not Available - Alternative methods will be used"
)

REM =============================================================================
REM PHASE 3: DEVELOPMENT TOOLS (Using validated package managers)
REM =============================================================================
ECHO.
ECHO ----------------------------------------
ECHO   PHASE 3: Development Tools
ECHO ----------------------------------------

REM -----------------------------------------------------------------------------
REM 3A. PowerShell 7 - Modern PowerShell environment
REM -----------------------------------------------------------------------------
CALL :LOG_ENTRY "INFO" "PHASE 3A: Installing PowerShell 7..."

REM Enhanced PowerShell 7 detection with multiple methods
SET "PS7_AVAILABLE=NO"
SET "PS7_VERSION="

REM Method 1: Direct pwsh.exe command test
pwsh.exe -Version >nul 2>&1
IF %ERRORLEVEL% EQU 0 (
    FOR /F "tokens=*" %%i IN ('pwsh.exe -Command "$PSVersionTable.PSVersion.ToString()" 2^>nul') DO SET PS7_VERSION=%%i
    IF NOT "!PS7_VERSION!"=="" (
        CALL :LOG_ENTRY "INFO" "PowerShell 7 detected via direct command: !PS7_VERSION!"
        SET "PS7_AVAILABLE=YES"
    )
)

REM Method 2: Check standard installation paths
IF "!PS7_AVAILABLE!"=="NO" (
    IF EXIST "%ProgramFiles%\PowerShell\7\pwsh.exe" (
        SET "PATH=%PATH%;%ProgramFiles%\PowerShell\7"
        "%ProgramFiles%\PowerShell\7\pwsh.exe" -Version >nul 2>&1
        IF %ERRORLEVEL% EQU 0 (
            FOR /F "tokens=*" %%i IN ('"%ProgramFiles%\PowerShell\7\pwsh.exe" -Command "$PSVersionTable.PSVersion.ToString()" 2^>nul') DO SET PS7_VERSION=%%i
            IF NOT "!PS7_VERSION!"=="" (
                CALL :LOG_ENTRY "INFO" "PowerShell 7 detected via Program Files: !PS7_VERSION!"
                SET "PS7_AVAILABLE=YES"
            )
        )
    )
)

REM Method 3: Check Windows Apps path (Store installation)
IF "!PS7_AVAILABLE!"=="NO" (
    FOR /D %%d IN ("%LocalAppData%\Microsoft\WindowsApps\Microsoft.PowerShell*") DO (
        IF EXIST "%%d\pwsh.exe" (
            "%%d\pwsh.exe" -Version >nul 2>&1
            IF %ERRORLEVEL% EQU 0 (
                FOR /F "tokens=*" %%i IN ('"%%d\pwsh.exe" -Command "$PSVersionTable.PSVersion.ToString()" 2^>nul') DO SET PS7_VERSION=%%i
                IF NOT "!PS7_VERSION!"=="" (
                    CALL :LOG_ENTRY "INFO" "PowerShell 7 detected via Windows Apps: !PS7_VERSION!"
                    SET "PS7_AVAILABLE=YES"
                    GOTO :PS7_DETECTED
                )
            )
        )
    )
)

:PS7_DETECTED
IF "!PS7_AVAILABLE!"=="YES" (
    CALL :LOG_ENTRY "INFO" "✓ PowerShell 7 Status: Available (Version: !PS7_VERSION!)"
    GOTO :SKIP_PS7_INSTALL
)

REM PowerShell 7 not found - proceed with installation
CALL :LOG_ENTRY "INFO" "PowerShell 7 not detected. Beginning installation..."

REM Enhanced PowerShell 7 installation with multiple methods
CALL :INSTALL_POWERSHELL7_MULTI_METHOD

REM Final verification after installation
timeout /t 5 /nobreak >nul
SET "PATH=%PATH%;%ProgramFiles%\PowerShell\7"
pwsh.exe -Version >nul 2>&1
IF %ERRORLEVEL% EQU 0 (
    FOR /F "tokens=*" %%i IN ('pwsh.exe -Command "$PSVersionTable.PSVersion.ToString()" 2^>nul') DO SET PS7_VERSION=%%i
    IF NOT "!PS7_VERSION!"=="" (
        CALL :LOG_ENTRY "INFO" "✓ PowerShell 7 installation successful: !PS7_VERSION!"
        SET "PS7_AVAILABLE=YES"
    ) ELSE (
        CALL :LOG_ENTRY "WARN" "PowerShell 7 command works but version detection failed"
        SET "PS7_AVAILABLE=YES"
    )
) ELSE (
    CALL :LOG_ENTRY "WARN" "PowerShell 7 installation completed but may require system restart"
    SET "PS7_AVAILABLE=NO"
)

:SKIP_PS7_INSTALL

REM =============================================================================
REM PHASE 4: POWERSHELL ENVIRONMENT (Dependencies for PowerShell modules)
REM =============================================================================
ECHO.
ECHO ----------------------------------------
ECHO   PHASE 4: PowerShell Environment
ECHO ----------------------------------------

REM -----------------------------------------------------------------------------
REM 4A. NuGet PackageProvider - Required for PowerShell modules
REM -----------------------------------------------------------------------------
CALL :LOG_ENTRY "INFO" "PHASE 4A: Installing NuGet PackageProvider..."

REM Simple NuGet PackageProvider check and install - Strictly non-interactive/unattended
"%POWERSHELL_EXE%" -NoProfile -ExecutionPolicy Bypass -NonInteractive -Command "try { $ErrorActionPreference='Stop'; $ProgressPreference='SilentlyContinue'; $ConfirmPreference='None'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $env:PackageManagementProvider_ConfirmInstall='Y'; $env:NUGET_XMLDOC_MODE='skip'; if (Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue) { Write-Host '[INFO] NuGet PackageProvider already available' } else { Get-PackageProvider -Name NuGet -ForceBootstrap -ErrorAction Stop | Out-Null; Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.208 -Scope AllUsers -Force -Confirm:`$false -ErrorAction Stop | Out-Null; Import-PackageProvider -Name NuGet -Force -ErrorAction Stop | Out-Null; $v=(Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction Stop | Sort-Object Version -Descending | Select-Object -First 1).Version; Write-Host ('[INFO] NuGet PackageProvider installed successfully (version ' + $v + ')') } } catch { Write-Host '[WARN] Failed to install NuGet PackageProvider:' `$_.Exception.Message }"

CALL :LOG_ENTRY "INFO" "NuGet PackageProvider setup completed."

REM -----------------------------------------------------------------------------
REM 4B. PowerShell Gallery Configuration - Required for module downloads
REM -----------------------------------------------------------------------------
CALL :LOG_ENTRY "INFO" "PHASE 4B: Configuring PowerShell Gallery..."

REM Simple PowerShell Gallery configuration
"%POWERSHELL_EXE%" -ExecutionPolicy Bypass -Command "try { if ((Get-PSRepository -Name 'PSGallery' -ErrorAction SilentlyContinue).InstallationPolicy -eq 'Trusted') { Write-Host '[INFO] PowerShell Gallery already configured as trusted' } else { Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted -Force; Write-Host '[INFO] PowerShell Gallery configured as trusted' } } catch { Write-Host '[WARN] Failed to configure PowerShell Gallery:' `$_.Exception.Message }"

CALL :LOG_ENTRY "INFO" "PowerShell Gallery configuration completed."

REM -----------------------------------------------------------------------------
REM 4C. PSWindowsUpdate Module - PowerShell module for Windows Updates
REM -----------------------------------------------------------------------------
CALL :LOG_ENTRY "INFO" "PHASE 4C: Installing PSWindowsUpdate module..."

REM Simple PSWindowsUpdate module check and install - Fully unattended
REM PSWindowsUpdate works better with Windows PowerShell, so use it for installation
IF "%PS7_AVAILABLE%"=="YES" (
    REM Try PowerShell 7 first, but fallback to Windows PowerShell if needed
    pwsh.exe -ExecutionPolicy Bypass -Command "try { if (Get-Module -ListAvailable -Name PSWindowsUpdate -ErrorAction SilentlyContinue) { Write-Host '[INFO] PSWindowsUpdate module already available in PowerShell 7' } else { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; `$ProgressPreference = 'SilentlyContinue'; Install-Module -Name PSWindowsUpdate -Force -Scope AllUsers -AllowClobber -Confirm:`$false -Repository PSGallery -SkipPublisherCheck -AcceptLicense; Write-Host '[INFO] PSWindowsUpdate module installed successfully in PowerShell 7' } } catch { Write-Host '[WARN] PowerShell 7 install failed, trying Windows PowerShell...' }"
    REM Also ensure it's available in Windows PowerShell for better compatibility
    "%POWERSHELL_EXE%" -ExecutionPolicy Bypass -Command "try { if (Get-Module -ListAvailable -Name PSWindowsUpdate -ErrorAction SilentlyContinue) { Write-Host '[INFO] PSWindowsUpdate module already available in Windows PowerShell' } else { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; `$ProgressPreference = 'SilentlyContinue'; Install-Module -Name PSWindowsUpdate -Force -Scope AllUsers -AllowClobber -Confirm:`$false -Repository PSGallery -SkipPublisherCheck -AcceptLicense; Write-Host '[INFO] PSWindowsUpdate module installed successfully in Windows PowerShell' } } catch { Write-Host '[WARN] Failed to install PSWindowsUpdate module in Windows PowerShell:' `$_.Exception.Message }"
) ELSE (
    "%POWERSHELL_EXE%" -ExecutionPolicy Bypass -Command "try { if (Get-Module -ListAvailable -Name PSWindowsUpdate -ErrorAction SilentlyContinue) { Write-Host '[INFO] PSWindowsUpdate module already available' } else { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; `$ProgressPreference = 'SilentlyContinue'; Install-Module -Name PSWindowsUpdate -Force -Scope AllUsers -AllowClobber -Confirm:`$false -Repository PSGallery -SkipPublisherCheck -AcceptLicense; Write-Host '[INFO] PSWindowsUpdate module installed successfully' } } catch { Write-Host '[WARN] Failed to install PSWindowsUpdate module:' `$_.Exception.Message }"
)

CALL :LOG_ENTRY "INFO" "PSWindowsUpdate module setup completed."

REM -----------------------------------------------------------------------------
REM 4C2. Appx Module - PowerShell module for UWP/Store app management
REM -----------------------------------------------------------------------------
CALL :LOG_ENTRY "INFO" "PHASE 4C2: Ensuring Appx module availability..."

REM Appx module is built into Windows PowerShell but may need import/refresh
REM For PowerShell 7, we need to ensure Windows Compatibility modules are available
IF "%PS7_AVAILABLE%"=="YES" (
    pwsh.exe -ExecutionPolicy Bypass -Command "try { Import-Module -Name Appx -Force -ErrorAction Stop; Write-Host '[INFO] Appx module imported successfully in PowerShell 7' } catch { try { Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-PowerShell-ISE -All -NoRestart -ErrorAction SilentlyContinue; Import-Module -Name WindowsCompatibility -Force -ErrorAction Stop; Import-WinModule -Name Appx -Force; Write-Host '[INFO] Appx module imported via Windows Compatibility in PowerShell 7' } catch { Write-Host '[WARN] Appx module not available in PowerShell 7 - will use Windows PowerShell fallback' } }"
    "%POWERSHELL_EXE%" -ExecutionPolicy Bypass -Command "try { Import-Module -Name Appx -Force -ErrorAction Stop; Write-Host '[INFO] Appx module verified in Windows PowerShell' } catch { Write-Host '[WARN] Appx module not available in Windows PowerShell:' `$_.Exception.Message }"
) ELSE (
    "%POWERSHELL_EXE%" -ExecutionPolicy Bypass -Command "try { Import-Module -Name Appx -Force -ErrorAction Stop; Write-Host '[INFO] Appx module imported successfully' } catch { Write-Host '[WARN] Appx module not available:' `$_.Exception.Message }"
)

CALL :LOG_ENTRY "INFO" "Appx module setup completed."

REM -----------------------------------------------------------------------------
REM 4D. Chocolatey Package Manager - Alternative package manager
REM -----------------------------------------------------------------------------
CALL :LOG_ENTRY "INFO" "Installing Chocolatey package manager..."

REM Simple Chocolatey check and install
choco --version >nul 2>&1
IF %ERRORLEVEL% EQU 0 (
    CALL :LOG_ENTRY "INFO" "Chocolatey is already installed."
) ELSE (
    CALL :LOG_ENTRY "INFO" "Installing Chocolatey..."
    
    REM Install Chocolatey using enhanced method with proper environment
    "%POWERSHELL_EXE%" -NoProfile -ExecutionPolicy Bypass -Command "try { [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; $env:chocolateyUseWindowsCompression = 'true'; Set-ExecutionPolicy Bypass -Scope Process -Force; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1')); Write-Host '[INFO] Chocolatey installed successfully' } catch { Write-Host '[WARN] Chocolatey installation failed:' $_.Exception.Message; exit 1 }"
    
    REM Refresh environment and verify installation
    CALL :REFRESH_ENV
    choco --version >nul 2>&1
    IF %ERRORLEVEL% EQU 0 (
        CALL :LOG_ENTRY "INFO" "Chocolatey installation completed successfully."
    ) ELSE (
        CALL :LOG_ENTRY "WARN" "Chocolatey installation failed, but continuing..."
    )
)

REM -----------------------------------------------------------------------------
REM 4E. PowerShellGet and PackageManagement - Latest Versions
REM -----------------------------------------------------------------------------
CALL :LOG_ENTRY "INFO" "PHASE 4E: Checking PowerShellGet and PackageManagement modules..."

REM Simple PowerShellGet and PackageManagement update
"%POWERSHELL_EXE%" -ExecutionPolicy Bypass -Command "try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; $psGet = (Get-Module -ListAvailable PowerShellGet | Sort-Object Version -Descending | Select-Object -First 1); if ($psGet -and $psGet.Version -ge '2.2.5') { Write-Host '[INFO] PowerShellGet is up to date' } else { Install-Module -Name PowerShellGet -Force -Scope AllUsers -AllowClobber -Confirm:$false -Repository PSGallery; Write-Host '[INFO] PowerShellGet updated successfully' } } catch { Write-Host '[WARN] PowerShellGet update failed:' $_.Exception.Message }"

"%POWERSHELL_EXE%" -ExecutionPolicy Bypass -Command "try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; $pkgMgmt = (Get-Module -ListAvailable PackageManagement | Sort-Object Version -Descending | Select-Object -First 1); if ($pkgMgmt -and $pkgMgmt.Version -ge '1.4.8') { Write-Host '[INFO] PackageManagement is up to date' } else { Install-Module -Name PackageManagement -Force -Scope AllUsers -AllowClobber -Confirm:$false -Repository PSGallery; Write-Host '[INFO] PackageManagement updated successfully' } } catch { Write-Host '[WARN] PackageManagement update failed:' $_.Exception.Message }"

CALL :LOG_ENTRY "INFO" "PowerShell modules setup completed."

REM -----------------------------------------------------------------------------
REM 4F. PowerShell 7 Windows Compatibility - Ensure PSWindowsUpdate and Appx work in PS7
REM -----------------------------------------------------------------------------
IF "%PS7_AVAILABLE%"=="YES" (
    CALL :LOG_ENTRY "INFO" "PHASE 4F: Configuring PowerShell 7 Windows Compatibility..."
    
    REM Install WindowsCompatibility module for PowerShell 7
    pwsh.exe -ExecutionPolicy Bypass -Command "try { if (Get-Module -ListAvailable -Name WindowsCompatibility -ErrorAction SilentlyContinue) { Write-Host '[INFO] WindowsCompatibility module already available' } else { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Install-Module -Name WindowsCompatibility -Force -Scope AllUsers -AllowClobber -Confirm:`$false -Repository PSGallery -AcceptLicense; Write-Host '[INFO] WindowsCompatibility module installed successfully' } } catch { Write-Host '[WARN] WindowsCompatibility module install failed:' `$_.Exception.Message }"
    
    REM Test importing PSWindowsUpdate in PowerShell 7 with Windows Compatibility
    pwsh.exe -ExecutionPolicy Bypass -Command "try { Import-Module -Name WindowsCompatibility -Force -ErrorAction SilentlyContinue; Import-WinModule -Name PSWindowsUpdate -Force -ErrorAction Stop; Write-Host '[INFO] PSWindowsUpdate imported successfully in PowerShell 7 via Windows Compatibility' } catch { Write-Host '[WARN] PSWindowsUpdate not available in PowerShell 7 - using Windows PowerShell fallback' }"
    
    REM Test importing Appx in PowerShell 7 with Windows Compatibility  
    pwsh.exe -ExecutionPolicy Bypass -Command "try { Import-Module -Name WindowsCompatibility -Force -ErrorAction SilentlyContinue; Import-WinModule -Name Appx -Force -ErrorAction Stop; Write-Host '[INFO] Appx imported successfully in PowerShell 7 via Windows Compatibility' } catch { Write-Host '[WARN] Appx not available in PowerShell 7 - using Windows PowerShell fallback' }"
    
    CALL :LOG_ENTRY "INFO" "PowerShell 7 Windows Compatibility setup completed."
) ELSE (
    CALL :LOG_ENTRY "INFO" "PowerShell 7 not available - skipping compatibility setup."
)

REM =============================================================================
REM FINAL VALIDATION AND CLEANUP
REM =============================================================================
ECHO.
ECHO ----------------------------------------
ECHO   Final Validation and Cleanup
ECHO ----------------------------------------

REM Additional PowerShell Modules and Windows Features sections follow below...

REM -----------------------------------------------------------------------------
REM 10. .NET Framework 4.8.1 - Required for many PowerShell modules and applications
REM -----------------------------------------------------------------------------
CALL :LOG_ENTRY "INFO" "Checking .NET Framework 4.8.1..."

REM Unified .NET Framework installation (works with or without Winget)
"%POWERSHELL_EXE%" -ExecutionPolicy Bypass -Command "$ProgressPreference='SilentlyContinue'; try { $netVersion = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full\' -Name Release -ErrorAction SilentlyContinue).Release; if ($netVersion -ge 528040) { Write-Host '[INFO] .NET Framework 4.8.1 or higher already installed' } else { Write-Host '[INFO] Installing .NET Framework 4.8.1...'; if (Get-Command winget -ErrorAction SilentlyContinue) { try { winget install --id Microsoft.DotNet.Framework.DeveloperPack_4 --silent --accept-package-agreements --accept-source-agreements; Write-Host '[INFO] .NET Framework 4.8.1 installed via winget'; exit 0 } catch { Write-Host '[WARN] Winget method failed, using direct download' } }; $dotnetUrl = 'https://go.microsoft.com/fwlink/?LinkId=2203304'; $dotnetFile = $env:TEMP + '\ndp481-web.exe'; Invoke-WebRequest -Uri $dotnetUrl -OutFile $dotnetFile -UseBasicParsing; Start-Process $dotnetFile -ArgumentList '/quiet /norestart' -Wait; Remove-Item $dotnetFile -Force -ErrorAction SilentlyContinue; Write-Host '[INFO] .NET Framework 4.8.1 installation completed' } } catch { Write-Host '[WARN] .NET Framework check failed:' $_.Exception.Message }"

REM -----------------------------------------------------------------------------
REM 11. Additional PowerShell Modules for Enhanced Functionality
REM -----------------------------------------------------------------------------
CALL :LOG_ENTRY "INFO" "Checking additional PowerShell modules..."

"%POWERSHELL_EXE%" -ExecutionPolicy Bypass -Command "$ProgressPreference='SilentlyContinue'; try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; $modules = @('DISM', 'PnpDevice', 'WindowsSearch'); foreach ($module in $modules) { if (-not (Get-Module -ListAvailable -Name $module -ErrorAction SilentlyContinue)) { try { $null = Import-Module $module -ErrorAction Stop; Write-Host ('[INFO] Module ' + $module + ' verified and available') } catch { Write-Host ('[INFO] Module ' + $module + ' not available - will be loaded when needed') } } else { Write-Host ('[INFO] Module ' + $module + ' already available') } } } catch { Write-Host '[WARN] Module check failed:' $_.Exception.Message }"

REM -----------------------------------------------------------------------------
REM 12. Windows Features - Enable required features
REM -----------------------------------------------------------------------------
CALL :LOG_ENTRY "INFO" "Checking Windows features..."

"%POWERSHELL_EXE%" -ExecutionPolicy Bypass -Command "$ProgressPreference='SilentlyContinue'; try { $features = @('NetFx3', 'MSMQ-Container', 'IIS-ManagementConsole'); foreach ($feature in $features) { $featureState = Get-WindowsOptionalFeature -Online -FeatureName $feature -ErrorAction SilentlyContinue; if ($featureState) { if ($featureState.State -eq 'Enabled') { Write-Host ('[INFO] Windows feature ' + $feature + ' already enabled') } elseif ($featureState.State -eq 'Disabled') { Write-Host ('[INFO] Enabling Windows feature: ' + $feature); $null = Enable-WindowsOptionalFeature -Online -FeatureName $feature -All -NoRestart -ErrorAction SilentlyContinue; Write-Host ('[INFO] Windows feature ' + $feature + ' enabled successfully') } } else { Write-Host ('[INFO] Windows feature ' + $feature + ' not available on this system') } } } catch { Write-Host '[INFO] Windows features check completed' }"

REM -----------------------------------------------------------------------------
REM 13. System Performance Optimizations
REM -----------------------------------------------------------------------------
CALL :LOG_ENTRY "INFO" "Checking system performance settings..."

"%POWERSHELL_EXE%" -ExecutionPolicy Bypass -Command "$ProgressPreference='SilentlyContinue'; try { $services = @('Themes', 'UxSms'); foreach ($service in $services) { $svc = Get-Service -Name $service -ErrorAction SilentlyContinue; if ($svc) { if ($svc.StartType -eq 'Automatic') { Write-Host ('[INFO] Service ' + $service + ' already set to Automatic') } else { $null = Set-Service -Name $service -StartupType Automatic -ErrorAction SilentlyContinue; Write-Host ('[INFO] Service ' + $service + ' set to Automatic startup') } } else { Write-Host ('[INFO] Service ' + $service + ' not found on this system') } }; Write-Host '[INFO] System services optimization completed' } catch { Write-Host '[INFO] Service optimization completed with some warnings' }"

CALL :LOG_ENTRY "INFO" "Dependency installation phase completed with comprehensive coverage."

REM -----------------------------------------------------------------------------
REM Note: System restart detection and startup task management is handled 
REM in the "Startup Task Management and Restart Detection Logic" section
REM after monthly task creation (lines ~124-220)
REM -----------------------------------------------------------------------------

REM -----------------------------------------------------------------------------
REM Repository Download - Simplified
REM -----------------------------------------------------------------------------
SET "REPO_URL=https://github.com/ichimbogdancristian/script_mentenanta/archive/refs/heads/main.zip"
SET "ZIP_FILE=%TEMP%\script_mentenanta.zip"
SET "EXTRACT_FOLDER=script_mentenanta-main"

CALL :LOG_ENTRY "INFO" "Downloading latest repository..."

REM Simple repository download
"%POWERSHELL_EXE%" -ExecutionPolicy Bypass -Command "$ProgressPreference='SilentlyContinue'; try { Invoke-WebRequest -Uri '%REPO_URL%' -OutFile '%ZIP_FILE%' -UseBasicParsing -TimeoutSec 60; Write-Host '[INFO] Repository downloaded successfully'; exit 0 } catch { Write-Host '[ERROR] Download failed:' $_.Exception.Message; exit 1 }"
SET "REPO_DOWNLOAD_EXIT=%ERRORLEVEL%"

IF %REPO_DOWNLOAD_EXIT% NEQ 0 (
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
        
        REM Simple folder removal
        "%POWERSHELL_EXE%" -ExecutionPolicy Bypass -Command "try { Remove-Item -Path '%SCRIPT_DIR%%EXTRACT_FOLDER%' -Recurse -Force -ErrorAction Stop; Write-Host '[INFO] Existing folder removed successfully'; exit 0 } catch { Write-Host '[WARN] Failed to remove existing folder:' $_.Exception.Message; exit 1 }"
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

REM Simple repository extraction
"%POWERSHELL_EXE%" -ExecutionPolicy Bypass -Command "try { Add-Type -AssemblyName System.IO.Compression.FileSystem; [System.IO.Compression.ZipFile]::ExtractToDirectory('%ZIP_FILE%', '%SCRIPT_DIR%'); Write-Host '[INFO] Repository extracted successfully'; exit 0 } catch { Write-Host '[ERROR] Extraction failed:' $_.Exception.Message; exit 1 }"
SET "EXTRACT_EXIT=%ERRORLEVEL%"

IF %EXTRACT_EXIT% NEQ 0 (
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
IF %ERRORLEVEL% EQU 0 (
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
IF %ERRORLEVEL% EQU 0 (
    CALL :LOG_ENTRY "INFO" "✓ Winget is available"
) ELSE (
    CALL :LOG_ENTRY "WARN" "✗ Winget not available - some installations may fail"
    SET /A DEPENDENCY_WARNINGS+=1
)

REM Validate Chocolatey
choco --version >nul 2>&1
IF %ERRORLEVEL% EQU 0 (
    CALL :LOG_ENTRY "INFO" "✓ Chocolatey is available"
) ELSE (
    CALL :LOG_ENTRY "WARN" "✗ Chocolatey not available - some installations may fail"
    SET /A DEPENDENCY_WARNINGS+=1
)

REM Validate PowerShell modules in Windows PowerShell
ECHO [INFO] Validating modules in Windows PowerShell...
"%POWERSHELL_EXE%" -ExecutionPolicy Bypass -Command "try { $modules = @('PSWindowsUpdate', 'PackageManagement', 'PowerShellGet', 'Appx'); $moduleStatus = @(); foreach ($module in $modules) { if (Get-Module -ListAvailable -Name $module -ErrorAction SilentlyContinue) { $moduleStatus += '[INFO] ✓ Module ' + $module + ' is available in Windows PowerShell' } else { $moduleStatus += '[WARN] ✗ Module ' + $module + ' not available in Windows PowerShell' } }; foreach ($status in $moduleStatus) { Write-Host $status } } catch { Write-Host '[WARN] Module validation failed' }"

REM Also validate in PowerShell 7 if available
IF "%PS7_AVAILABLE%"=="YES" (
    ECHO [INFO] Validating modules in PowerShell 7...
    pwsh.exe -ExecutionPolicy Bypass -Command "try { $modules = @('PSWindowsUpdate', 'PackageManagement', 'PowerShellGet', 'Appx'); $moduleStatus = @(); foreach ($module in $modules) { if (Get-Module -ListAvailable -Name $module -ErrorAction SilentlyContinue) { $moduleStatus += '[INFO] ✓ Module ' + $module + ' is available in PowerShell 7' } else { try { Import-Module -Name WindowsCompatibility -Force -ErrorAction SilentlyContinue; Import-WinModule -Name $module -Force -ErrorAction Stop; $moduleStatus += '[INFO] ✓ Module ' + $module + ' is available in PowerShell 7 via Windows Compatibility' } catch { $moduleStatus += '[WARN] ✗ Module ' + $module + ' not available in PowerShell 7' } } }; foreach ($status in $moduleStatus) { Write-Host $status } } catch { Write-Host '[WARN] PowerShell 7 module validation failed' }"
)

REM Show dependency summary
ECHO.
ECHO ========================================
ECHO    DEPENDENCY VALIDATION SUMMARY
ECHO ========================================

REM Create temp script for comprehensive dependency check
"%POWERSHELL_EXE%" -ExecutionPolicy Bypass -Command "try { Write-Host ' '; Write-Host '[INFO] === CRITICAL DEPENDENCIES STATUS ==='; if (Get-Command winget -ErrorAction SilentlyContinue) { try { $wingetVer = winget --version 2>$null; if ($wingetVer) { Write-Host '[INFO] ✓ Winget: Available (version:' $wingetVer.Trim() ')' } else { Write-Host '[WARN] ✗ Winget: Not responding properly' } } catch { Write-Host '[WARN] ✗ Winget: Available but not functional' } } else { Write-Host '[WARN] ✗ Winget: Not available' }; if (Get-Command pwsh -ErrorAction SilentlyContinue) { $ps7Ver = pwsh --version 2>$null; Write-Host '[INFO] ✓ PowerShell 7:' $ps7Ver } else { Write-Host '[WARN] ✗ PowerShell 7: Not available' }; if (Get-Command choco -ErrorAction SilentlyContinue) { $chocoVer = choco --version 2>$null; Write-Host '[INFO] ✓ Chocolatey:' $chocoVer } else { Write-Host '[INFO] ○ Chocolatey: Not available (optional)' }; Write-Host '[INFO] === DEPENDENCY CHECK COMPLETE ==='; Write-Host ' ' } catch { Write-Host '[WARN] Dependency summary check failed' }"

IF %DEPENDENCY_WARNINGS% GTR 0 (
    ECHO [%TIME%] [WARN] Found %DEPENDENCY_WARNINGS% dependency warnings. Script will use graceful degradation.
) ELSE (
    ECHO [%TIME%] [INFO] ✓ All critical dependencies verified successfully.
)

ECHO ========================================

CALL :LOG_ENTRY "INFO" "Dependency validation completed."

REM -----------------------------------------------------------------------------
REM Launch PowerShell Script with Priority for PowerShell 7
REM -----------------------------------------------------------------------------
REM Check if we have a local script.ps1 file (direct execution) or extracted folder
SET "PS1_PATH=%SCRIPT_DIR%script.ps1"
IF NOT EXIST "%PS1_PATH%" (
    SET "PS1_PATH=%SCRIPT_DIR%%EXTRACT_FOLDER%\script.ps1"
)

IF NOT EXIST "%PS1_PATH%" (
    CALL :LOG_ENTRY "ERROR" "PowerShell script not found at either location:"
    CALL :LOG_ENTRY "ERROR" "  Local: %SCRIPT_DIR%script.ps1"
    CALL :LOG_ENTRY "ERROR" "  Extracted: %SCRIPT_DIR%%EXTRACT_FOLDER%\script.ps1"
    IF EXIST "%SCRIPT_DIR%%EXTRACT_FOLDER%" (
        CALL :LOG_ENTRY "INFO" "Contents of extracted folder:"
        DIR "%SCRIPT_DIR%%EXTRACT_FOLDER%" /B
    )
    pause
    EXIT /B 4
)

CALL :LOG_ENTRY "INFO" "Launching PowerShell maintenance script..."
CALL :LOG_ENTRY "INFO" "Script path: %PS1_PATH%"

REM Set environment variable for PowerShell script to use same log file
SET "SCRIPT_LOG_FILE=%LOG_FILE%"

IF "%PS7_AVAILABLE%"=="YES" (
    CALL :LOG_ENTRY "INFO" "Using PowerShell 7 environment..."
    ECHO.
    ECHO ========================================
    ECHO    Launching PowerShell 7 Script
    ECHO ========================================
    ECHO.
    REM Launch PowerShell 7 asynchronously with admin rights
    START "" pwsh.exe -ExecutionPolicy Bypass -NoProfile -WindowStyle Normal -File "%PS1_PATH%"
    CALL :LOG_ENTRY "INFO" "PowerShell 7 script launched asynchronously with admin rights"
) ELSE (
    CALL :LOG_ENTRY "INFO" "Using Windows PowerShell environment..."
    ECHO.
    ECHO ================================================
    ECHO    Launching Windows PowerShell Script
    ECHO ================================================
    ECHO.
    REM Launch Windows PowerShell asynchronously with admin rights
    START "" "%POWERSHELL_EXE%" -ExecutionPolicy Bypass -NoProfile -WindowStyle Normal -File "%PS1_PATH%"
    CALL :LOG_ENTRY "INFO" "Windows PowerShell script launched asynchronously with admin rights"
)

CALL :LOG_ENTRY "INFO" "PowerShell script launched successfully."
CALL :LOG_ENTRY "INFO" "Maintenance operations completed."

REM -----------------------------------------------------------------------------
REM Auto-close countdown with abort option
REM -----------------------------------------------------------------------------
ECHO.
ECHO ========================================
ECHO        Script Execution Complete
ECHO ========================================
ECHO.
ECHO [INFO] script.ps1 has been launched with administrator privileges.
ECHO [INFO] The PowerShell maintenance script is now running in a separate window.
ECHO [INFO] Check maintenance.log and maintenance_report.txt for detailed results.
ECHO.
ECHO ========================================
ECHO        AUTO-CLOSE COUNTDOWN
ECHO ========================================
ECHO.
ECHO This launcher window will automatically close in 20 seconds.
ECHO Press any key to abort the countdown and keep this window open.
ECHO.

REM Countdown loop with abort detection
FOR /L %%i IN (20,-1,1) DO (
    IF %%i LSS 10 (
        ECHO Closing in 0%%i seconds... ^(Press any key to abort^)
    ) ELSE (
        ECHO Closing in %%i seconds... ^(Press any key to abort^)
    )
    
    REM Check for key press with 1 second timeout
    timeout /t 1 /nobreak >nul 2>&1
    IF !ERRORLEVEL! NEQ 0 (
        ECHO.
        ECHO [INFO] Countdown aborted by user.
        ECHO [INFO] Window will remain open for manual review.
        ECHO.
        ECHO Press any key to close this window...
        pause >nul
        CALL :CLEANUP_TEMP_FILES
        CALL :LOG_ENTRY "INFO" "Batch launcher completed - countdown aborted by user."
        EXIT /B 0
    )
)

ECHO.
ECHO [INFO] Auto-close timer expired. Closing window...
CALL :CLEANUP_TEMP_FILES
CALL :LOG_ENTRY "INFO" "Batch launcher completed successfully - auto-closed after countdown."
EXIT /B 0

REM -----------------------------------------------------------------------------
REM Environment Refresh Function - Updates PATH and environment variables
REM -----------------------------------------------------------------------------
REM -----------------------------------------------------------------------------
REM Enhanced Environment Refresh Function
REM -----------------------------------------------------------------------------
:REFRESH_ENV
CALL :LOG_ENTRY "INFO" "Refreshing environment variables..."

REM Method 1: Use PowerShell to refresh environment (most reliable)
IF DEFINED POWERSHELL_EXE (
    "!POWERSHELL_EXE!" -ExecutionPolicy Bypass -Command "try { $env:Path = [System.Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [System.Environment]::GetEnvironmentVariable('Path','User'); Write-Host '[INFO] Environment refreshed via PowerShell' } catch { Write-Host '[WARN] PowerShell refresh failed' }" 2>nul
    IF !ERRORLEVEL! EQU 0 (
        CALL :LOG_ENTRY "INFO" "Environment refresh successful (PowerShell method)"
        GOTO :EOF
    )
)

REM Method 2: Manual registry query fallback
CALL :LOG_ENTRY "INFO" "Using registry fallback for environment refresh..."
FOR /F "usebackq skip=2 tokens=1,2*" %%A IN (`REG QUERY "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" /v PATH 2^>nul`) DO (
    IF "%%A"=="PATH" SET "SYSTEM_PATH=%%C"
)
FOR /F "usebackq skip=2 tokens=1,2*" %%A IN (`REG QUERY "HKCU\Environment" /v PATH 2^>nul`) DO (
    IF "%%A"=="PATH" SET "USER_PATH=%%C"
)

REM Combine system and user paths
IF DEFINED USER_PATH (
    SET "PATH=%SYSTEM_PATH%;%USER_PATH%"
    CALL :LOG_ENTRY "INFO" "Environment refresh successful (Registry method)"
) ELSE (
    SET "PATH=%SYSTEM_PATH%"
    CALL :LOG_ENTRY "INFO" "Environment refresh partial (System PATH only)"
)

REM Ensure Chocolatey is in PATH if installed
IF EXIST "%ProgramData%\chocolatey\bin\choco.exe" (
    SET "PATH=%PATH%;%ProgramData%\chocolatey\bin"
    CALL :LOG_ENTRY "INFO" "Added Chocolatey to PATH"
)
GOTO :EOF

REM -----------------------------------------------------------------------------
REM -----------------------------------------------------------------------------
REM PowerShell 7 Direct Installation Function
REM -----------------------------------------------------------------------------
:INSTALL_PS7_DIRECT
"%POWERSHELL_EXE%" -ExecutionPolicy Bypass -Command "try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; $url = 'https://github.com/PowerShell/PowerShell/releases/latest/download/PowerShell-7.4.5-win-x64.msi'; $file = '$env:TEMP\PowerShell7.msi'; Invoke-WebRequest -Uri $url -OutFile $file -UseBasicParsing; Start-Process msiexec -ArgumentList '/i', $file, '/quiet', '/norestart' -Wait; Remove-Item $file -Force; Write-Host '[INFO] PowerShell 7 installed via direct download' } catch { Write-Host '[ERROR] PowerShell 7 install failed:' $_.Exception.Message }"
GOTO :EOF

REM -----------------------------------------------------------------------------
REM Winget Install with Fallbacks Function - Tries Winget first, then alternatives
REM Usage: CALL :WINGET_INSTALL_WITH_FALLBACK "package_id" "fallback_url" "fallback_installer_args"
REM -----------------------------------------------------------------------------
:WINGET_INSTALL_WITH_FALLBACK
SET "PACKAGE_ID=%~1"
SET "FALLBACK_URL=%~2" 
SET "FALLBACK_ARGS=%~3"

REM Try Winget first if available
IF "%WINGET_AVAILABLE%"=="YES" (
    CALL :LOG_ENTRY "INFO" "Attempting to install %PACKAGE_ID% via Winget..."
    winget install --id %PACKAGE_ID% --silent --accept-package-agreements --accept-source-agreements >nul 2>&1
    IF %ERRORLEVEL% EQU 0 (
        CALL :LOG_ENTRY "INFO" "✓ %PACKAGE_ID% installed successfully via Winget"
        GOTO :EOF
    ) ELSE (
        CALL :LOG_ENTRY "WARN" "Winget installation failed for %PACKAGE_ID%, trying fallback..."
    )
)

REM Try direct download fallback if URL provided
IF NOT "%FALLBACK_URL%"=="" (
    CALL :LOG_ENTRY "INFO" "Attempting direct download installation for %PACKAGE_ID%..."
    "%POWERSHELL_EXE%" -ExecutionPolicy Bypass -Command "try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; $url = '%FALLBACK_URL%'; $file = '$env:TEMP\' + [System.IO.Path]::GetFileName($url); if ($file -notmatch '\.(exe|msi)$') { $file += '.exe' }; Invoke-WebRequest -Uri $url -OutFile $file -UseBasicParsing -TimeoutSec 120; if (Test-Path $file) { Write-Host '[INFO] Downloaded fallback installer successfully'; if ($file -match '\.msi$') { Start-Process msiexec -ArgumentList '/i', $file, '%FALLBACK_ARGS%' -Wait } else { Start-Process $file -ArgumentList '%FALLBACK_ARGS%' -Wait }; Remove-Item $file -Force; Write-Host '[INFO] Fallback installation completed' } else { throw 'Download failed' } } catch { Write-Host '[ERROR] Fallback installation failed:' $_.Exception.Message }"
    IF %ERRORLEVEL% EQU 0 (
        CALL :LOG_ENTRY "INFO" "✓ %PACKAGE_ID% installed successfully via fallback download"
        GOTO :EOF
    )
)

CALL :LOG_ENTRY "WARN" "All installation methods failed for %PACKAGE_ID%"
GOTO :EOF

REM -----------------------------------------------------------------------------
REM PowerShell 7 Multi-Method Installation Function
REM -----------------------------------------------------------------------------
:INSTALL_POWERSHELL7_MULTI_METHOD
CALL :LOG_ENTRY "INFO" "Starting PowerShell 7 installation with multiple methods..."

REM Method 1: WinGet installation (primary)
IF "!WINGET_AVAILABLE!"=="YES" (
    CALL :LOG_ENTRY "INFO" "PS7 Method 1: Attempting WinGet installation..."
    winget install --id Microsoft.PowerShell --source winget --accept-package-agreements --accept-source-agreements --silent >nul 2>&1
    IF !ERRORLEVEL! EQU 0 (
        CALL :LOG_ENTRY "INFO" "PS7 Method 1: WinGet installation completed successfully"
        GOTO :PS7_INSTALL_SUCCESS
    ) ELSE (
        CALL :LOG_ENTRY "WARN" "PS7 Method 1: WinGet installation failed (Error: !ERRORLEVEL!)"
    )
)

REM Method 2: Direct MSI download and installation
CALL :LOG_ENTRY "INFO" "PS7 Method 2: Attempting direct MSI download..."
SET "PS7_TEMP_DIR=%TEMP%\PowerShell7_Install_%RANDOM%"
mkdir "!PS7_TEMP_DIR!" >nul 2>&1

REM Try multiple download URLs for different architectures
SET "PS7_URLS=https://github.com/PowerShell/PowerShell/releases/latest/download/PowerShell-7.4.6-win-x64.msi https://github.com/PowerShell/PowerShell/releases/latest/download/PowerShell-7.4.5-win-x64.msi https://github.com/PowerShell/PowerShell/releases/download/v7.4.4/PowerShell-7.4.4-win-x64.msi"

FOR %%U IN (!PS7_URLS!) DO (
    CALL :LOG_ENTRY "INFO" "PS7 Method 2: Downloading from %%U"
    powershell.exe -ExecutionPolicy Bypass -Command "try { Invoke-WebRequest -Uri '%%U' -OutFile '!PS7_TEMP_DIR!\powershell7.msi' -UseBasicParsing; exit 0 } catch { exit 1 }" >nul 2>&1
    IF !ERRORLEVEL! EQU 0 (
        IF EXIST "!PS7_TEMP_DIR!\powershell7.msi" (
            CALL :LOG_ENTRY "INFO" "PS7 Method 2: Download successful, installing MSI..."
            msiexec /i "!PS7_TEMP_DIR!\powershell7.msi" /quiet /norestart /L*v "!PS7_TEMP_DIR!\install.log" >nul 2>&1
            IF !ERRORLEVEL! EQU 0 (
                CALL :LOG_ENTRY "INFO" "PS7 Method 2: MSI installation completed successfully"
                rmdir /s /q "!PS7_TEMP_DIR!" >nul 2>&1
                GOTO :PS7_INSTALL_SUCCESS
            ) ELSE (
                CALL :LOG_ENTRY "WARN" "PS7 Method 2: MSI installation failed (Error: !ERRORLEVEL!)"
            )
        )
    ) ELSE (
        CALL :LOG_ENTRY "WARN" "PS7 Method 2: Download failed from %%U"
    )
)

REM Method 3: Microsoft Store installation (if available)
CALL :LOG_ENTRY "INFO" "PS7 Method 3: Attempting Microsoft Store installation..."
powershell.exe -ExecutionPolicy Bypass -Command "try { Get-AppxPackage -Name Microsoft.PowerShell -AllUsers | Out-Null; Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.PowerShell_8wekyb3d8bbwe; exit 0 } catch { exit 1 }" >nul 2>&1
IF !ERRORLEVEL! EQU 0 (
    CALL :LOG_ENTRY "INFO" "PS7 Method 3: Microsoft Store installation completed"
    GOTO :PS7_INSTALL_SUCCESS
) ELSE (
    CALL :LOG_ENTRY "WARN" "PS7 Method 3: Microsoft Store installation failed"
)

REM Method 4: Chocolatey installation (if available)
WHERE choco >nul 2>&1
IF !ERRORLEVEL! EQU 0 (
    CALL :LOG_ENTRY "INFO" "PS7 Method 4: Attempting Chocolatey installation..."
    choco install powershell-core -y --limit-output >nul 2>&1
    IF !ERRORLEVEL! EQU 0 (
        CALL :LOG_ENTRY "INFO" "PS7 Method 4: Chocolatey installation completed"
        GOTO :PS7_INSTALL_SUCCESS
    ) ELSE (
        CALL :LOG_ENTRY "WARN" "PS7 Method 4: Chocolatey installation failed"
    )
) ELSE (
    CALL :LOG_ENTRY "INFO" "PS7 Method 4: Chocolatey not available, skipping"
)

REM Method 5: Alternative GitHub release download with curl
CALL :LOG_ENTRY "INFO" "PS7 Method 5: Attempting curl-based download..."
WHERE curl >nul 2>&1
IF !ERRORLEVEL! EQU 0 (
    curl -L "https://github.com/PowerShell/PowerShell/releases/latest/download/PowerShell-7.4.6-win-x64.msi" -o "!PS7_TEMP_DIR!\powershell7_curl.msi" >nul 2>&1
    IF !ERRORLEVEL! EQU 0 (
        IF EXIST "!PS7_TEMP_DIR!\powershell7_curl.msi" (
            msiexec /i "!PS7_TEMP_DIR!\powershell7_curl.msi" /quiet /norestart >nul 2>&1
            IF !ERRORLEVEL! EQU 0 (
                CALL :LOG_ENTRY "INFO" "PS7 Method 5: Curl-based installation completed"
                rmdir /s /q "!PS7_TEMP_DIR!" >nul 2>&1
                GOTO :PS7_INSTALL_SUCCESS
            )
        )
    )
)

REM All methods failed
CALL :LOG_ENTRY "ERROR" "All PowerShell 7 installation methods failed"
rmdir /s /q "!PS7_TEMP_DIR!" >nul 2>&1
GOTO :EOF

:PS7_INSTALL_SUCCESS
CALL :LOG_ENTRY "INFO" "PowerShell 7 installation process completed successfully"
REM Cleanup temp directory if it exists
IF EXIST "!PS7_TEMP_DIR!" rmdir /s /q "!PS7_TEMP_DIR!" >nul 2>&1
GOTO :EOF

REM -----------------------------------------------------------------------------
REM Enhanced Admin Privilege Detection Function - CMD Environment Only
REM -----------------------------------------------------------------------------
:DETECT_ADMIN_PRIVILEGES
SET "IS_ADMIN=NO"

REM Method 1: NET SESSION command (most reliable in CMD)
NET SESSION >nul 2>&1
IF %ERRORLEVEL% EQU 0 (
    SET "IS_ADMIN=YES"
    CALL :LOG_ENTRY "INFO" "Admin detection Method 1 (NET SESSION): SUCCESS"
    GOTO :EOF
)

REM Method 2: WHOAMI /PRIV command check
whoami /priv 2>nul | find "SeDebugPrivilege" >nul
IF %ERRORLEVEL% EQU 0 (
    SET "IS_ADMIN=YES"
    CALL :LOG_ENTRY "INFO" "Admin detection Method 2 (WHOAMI): SUCCESS"
    GOTO :EOF
)

REM Method 3: Registry write test (safe for CMD)
REG ADD "HKLM\Software\Microsoft\Windows\CurrentVersion\Policies\System" /v TestAdminAccess /t REG_DWORD /d 1 /f >nul 2>&1
IF %ERRORLEVEL% EQU 0 (
    REG DELETE "HKLM\Software\Microsoft\Windows\CurrentVersion\Policies\System" /v TestAdminAccess /f >nul 2>&1
    SET "IS_ADMIN=YES"
    CALL :LOG_ENTRY "INFO" "Admin detection Method 3 (Registry): SUCCESS"
    GOTO :EOF
)

CALL :LOG_ENTRY "INFO" "No admin privileges detected via CMD methods"
GOTO :EOF
GOTO :EOF

REM -----------------------------------------------------------------------------
REM Enhanced Admin Privilege Request Function
REM -----------------------------------------------------------------------------
:REQUEST_ADMIN_PRIVILEGES
SET "SCRIPT_TO_RUN=%~1"
SET "SCRIPT_ARGS=%~2"
CALL :LOG_ENTRY "INFO" "Requesting administrator privileges for: !SCRIPT_TO_RUN!"
CALL :LOG_ENTRY "INFO" "Arguments to pass: !SCRIPT_ARGS!"

ECHO.
ECHO =========================================================
ECHO   ADMINISTRATOR PRIVILEGES REQUIRED
ECHO =========================================================
ECHO.
ECHO This script requires administrator privileges to:
ECHO   • Install system dependencies
ECHO   • Create scheduled tasks
ECHO   • Manage system services
ECHO   • Write to system directories
ECHO.
ECHO Script to elevate: !SCRIPT_TO_RUN!
IF DEFINED SCRIPT_ARGS (
    ECHO Arguments: !SCRIPT_ARGS!
) ELSE (
    ECHO Arguments: [None]
)
ECHO.
ECHO Attempting to relaunch with administrator privileges...
ECHO.

REM Method 1: PowerShell Start-Process with Verb RunAs (without -Wait)
CALL :LOG_ENTRY "INFO" "Admin request Method 1: PowerShell Start-Process..."
IF DEFINED SCRIPT_ARGS (
    CALL :LOG_ENTRY "INFO" "Using PowerShell with arguments: !SCRIPT_ARGS!"
    powershell.exe -ExecutionPolicy Bypass -Command "try { Start-Process -FilePath '!SCRIPT_TO_RUN!' -Verb RunAs -ArgumentList '!SCRIPT_ARGS!'; Write-Host 'Elevation request sent with arguments'; exit 0 } catch { Write-Host 'Error:' $_.Exception.Message; exit 1 }"
) ELSE (
    CALL :LOG_ENTRY "INFO" "Using PowerShell without arguments"
    powershell.exe -ExecutionPolicy Bypass -Command "try { Start-Process -FilePath '!SCRIPT_TO_RUN!' -Verb RunAs; Write-Host 'Elevation request sent without arguments'; exit 0 } catch { Write-Host 'Error:' $_.Exception.Message; exit 1 }"
)
IF %ERRORLEVEL% EQU 0 (
    CALL :LOG_ENTRY "INFO" "Admin request Method 1: SUCCESS - Elevated process launched"
    ECHO [INFO] Elevated process launched successfully.
    ECHO [INFO] Please check for the elevated window that should appear.
    ECHO [INFO] This window will close now.
    timeout /t 3 /nobreak >nul
    GOTO :EOF
)

REM Method 2: Windows Shell RunAs with VBScript (enhanced)
CALL :LOG_ENTRY "INFO" "Admin request Method 2: VBScript ShellExecute..."
SET "VBS_TEMP=%TEMP%\RunAsAdmin_%RANDOM%.vbs"
(
    ECHO Set objShell = CreateObject^("Shell.Application"^)
    ECHO Set objFSO = CreateObject^("Scripting.FileSystemObject"^)
    ECHO strScript = "!SCRIPT_TO_RUN!"
    ECHO strArgs = "!SCRIPT_ARGS!"
    ECHO strWorkDir = objFSO.GetParentFolderName^(strScript^)
    ECHO objShell.ShellExecute strScript, strArgs, strWorkDir, "runas", 1
    ECHO WScript.Sleep 1000
) > "!VBS_TEMP!"

cscript //NoLogo "!VBS_TEMP!" 2>nul
SET "VBS_RESULT=%ERRORLEVEL%"
DEL "!VBS_TEMP!" >nul 2>&1

IF %VBS_RESULT% EQU 0 (
    CALL :LOG_ENTRY "INFO" "Admin request Method 2: SUCCESS - VBScript elevation completed"
    ECHO [INFO] VBScript elevation completed successfully.
    ECHO [INFO] Please check for the elevated window that should appear.
    ECHO [INFO] This window will close now.
    timeout /t 3 /nobreak >nul
    GOTO :EOF
)

REM Method 3: Alternative PowerShell method with different syntax
CALL :LOG_ENTRY "INFO" "Admin request Method 3: Alternative PowerShell method..."
powershell.exe -ExecutionPolicy Bypass -Command "& { $proc = New-Object System.Diagnostics.ProcessStartInfo; $proc.FileName = '!SCRIPT_TO_RUN!'; $proc.Arguments = '!SCRIPT_ARGS!'; $proc.UseShellExecute = $true; $proc.Verb = 'runas'; $proc.WorkingDirectory = Split-Path '!SCRIPT_TO_RUN!' -Parent; try { [System.Diagnostics.Process]::Start($proc); exit 0 } catch { exit 1 } }"
IF %ERRORLEVEL% EQU 0 (
    CALL :LOG_ENTRY "INFO" "Admin request Method 3: SUCCESS - Alternative PowerShell method completed"
    ECHO [INFO] Alternative PowerShell elevation completed successfully.
    ECHO [INFO] Please check for the elevated window that should appear.
    ECHO [INFO] This window will close now.
    timeout /t 3 /nobreak >nul
    GOTO :EOF
)

REM All methods failed - provide user guidance
CALL :LOG_ENTRY "ERROR" "Failed to obtain administrator privileges with all automatic methods"
ECHO.
ECHO =========================================================
ECHO   AUTOMATIC ELEVATION FAILED
ECHO =========================================================
ECHO.
ECHO All automatic elevation methods failed.
ECHO This may be due to:
ECHO   • Group Policy restrictions
ECHO   • Antivirus interference
ECHO   • UAC being disabled
ECHO   • System security policies
ECHO.
ECHO MANUAL SOLUTION:
ECHO   1. Close this window
ECHO   2. Right-click on the script file: !SCRIPT_TO_RUN!
ECHO   3. Select "Run as administrator"
ECHO   4. Accept the UAC prompt when it appears
ECHO.
ECHO =========================================================
ECHO.
PAUSE
GOTO :EOF

REM -----------------------------------------------------------------------------
REM Enhanced Cleanup Function - Removes temporary files and directories
REM -----------------------------------------------------------------------------
:CLEANUP_TEMP_FILES
CALL :LOG_ENTRY "INFO" "Starting cleanup of temporary files and directories..."

REM Cleanup PowerShell 7 installation files
IF EXIST "%TEMP%\PS7" (
    CALL :LOG_ENTRY "INFO" "Removing PowerShell 7 temp directory..."
    RMDIR /S /Q "%TEMP%\PS7" >nul 2>&1
    IF EXIST "%TEMP%\PS7" (
        CALL :LOG_ENTRY "WARN" "Failed to remove PowerShell 7 temp directory"
    ) ELSE (
        CALL :LOG_ENTRY "INFO" "PowerShell 7 temp directory removed successfully"
    )
)

REM Cleanup WinGet installation files
IF EXIST "%TEMP%\winget" (
    CALL :LOG_ENTRY "INFO" "Removing WinGet temp directory..."
    RMDIR /S /Q "%TEMP%\winget" >nul 2>&1
    IF EXIST "%TEMP%\winget" (
        CALL :LOG_ENTRY "WARN" "Failed to remove WinGet temp directory"
    ) ELSE (
        CALL :LOG_ENTRY "INFO" "WinGet temp directory removed successfully"
    )
)

REM Cleanup VC++ Redistributable files
FOR %%F IN ("%TEMP%\VC_redist.x64.exe" "%TEMP%\vc_redist.x64.exe" "%TEMP%\vcredist_x64.exe") DO (
    IF EXIST "%%F" (
        CALL :LOG_ENTRY "INFO" "Removing VC++ installer: %%F"
        DEL /F /Q "%%F" >nul 2>&1
    )
)

REM Cleanup .NET Framework installers
FOR %%F IN ("%TEMP%\ndp481-web.exe" "%TEMP%\dotnet-installer.exe") DO (
    IF EXIST "%%F" (
        CALL :LOG_ENTRY "INFO" "Removing .NET installer: %%F"
        DEL /F /Q "%%F" >nul 2>&1
    )
)

REM Cleanup script repository if variable is defined
IF DEFINED REPO_DIR (
    IF EXIST "!REPO_DIR!" (
        CALL :LOG_ENTRY "INFO" "Removing script repository directory: !REPO_DIR!"
        RMDIR /S /Q "!REPO_DIR!" >nul 2>&1
        IF EXIST "!REPO_DIR!" (
            CALL :LOG_ENTRY "WARN" "Failed to remove repository directory: !REPO_DIR!"
        ) ELSE (
            CALL :LOG_ENTRY "INFO" "Repository directory removed successfully"
        )
    )
)

REM Cleanup any leftover zip files from repository download
FOR %%F IN ("%TEMP%\*mentenanta*.zip" "%TEMP%\script_mentenanta*.zip") DO (
    IF EXIST "%%F" (
        CALL :LOG_ENTRY "INFO" "Removing repository zip: %%F"
        DEL /F /Q "%%F" >nul 2>&1
    )
)

CALL :LOG_ENTRY "INFO" "Temporary file cleanup completed"
GOTO :EOF

REM -----------------------------------------------------------------------------
REM Enhanced Logging Function - Logs to both console and maintenance.log file
REM -----------------------------------------------------------------------------
:LOG_ENTRY
SET "LEVEL=%~1"
SET "MESSAGE=%~2"

REM Get consistent timestamp format
FOR /F "tokens=1-3 delims=:" %%a IN ("%TIME%") DO (
    SET "HOUR=%%a"
    SET "MINUTE=%%b"
    SET "SECOND=%%c"
)
REM Remove leading spaces from hour
SET "HOUR=%HOUR: =0%"
SET "TIMESTAMP=%HOUR%:%MINUTE%:%SECOND:~0,2%"

REM Console output
ECHO [%TIMESTAMP%] [%LEVEL%] %MESSAGE%

REM File output with error handling
IF DEFINED LOG_FILE (
    ECHO [%DATE% %TIMESTAMP%] [%LEVEL%] %MESSAGE% >> "%LOG_FILE%" 2>nul
) ELSE (
    REM Fallback if LOG_FILE not defined
    ECHO [%DATE% %TIMESTAMP%] [%LEVEL%] %MESSAGE% >> "maintenance.log" 2>nul
)
GOTO :EOF
