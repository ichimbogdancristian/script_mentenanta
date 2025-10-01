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

:REFRESH_PATH
REM Refresh PATH environment variable from registry
FOR /F "usebackq tokens=2*" %%A IN (`REG QUERY "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" /v PATH 2^>nul`) DO SET "SYSTEM_PATH=%%B"
FOR /F "usebackq tokens=2*" %%A IN (`REG QUERY "HKCU\Environment" /v PATH 2^>nul`) DO SET "USER_PATH=%%B"
IF DEFINED USER_PATH (
    SET "PATH=%SYSTEM_PATH%;%USER_PATH%"
) ELSE (
    SET "PATH=%SYSTEM_PATH%"
)
EXIT /B

:DETECT_PS7_ALTERNATIVE
REM Try common PowerShell 7 installation paths
SET "PS7_FOUND=NO"
FOR %%P IN (
    "%ProgramFiles%\PowerShell\7\pwsh.exe"
    "%ProgramFiles(x86)%\PowerShell\7\pwsh.exe"
    "%LOCALAPPDATA%\Microsoft\WindowsApps\pwsh.exe"
    "%ProgramFiles%\PowerShell\pwsh.exe"
) DO (
    IF EXIST "%%P" (
        SET "PS7_PATH=%%P"
        SET "PS7_FOUND=YES"
        CALL :LOG_MESSAGE "Found PowerShell 7 at: %%P" "SUCCESS" "LAUNCHER"
        FOR /F "tokens=*" %%V IN ('"%%P" -NoProfile -Command "$PSVersionTable.PSVersion.ToString()" 2^>nul') DO SET PS7_VERSION=%%V
        CALL :LOG_MESSAGE "PowerShell 7 version: !PS7_VERSION!" "INFO" "LAUNCHER"
        GOTO :PS7_FOUND
    )
)
:PS7_FOUND
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

REM Elevation loop prevention marker
SET "ELEVATION_ATTEMPTED=NO"

REM Check if this is an elevated instance (prevent infinite loops)
FOR %%i in (%*) DO (
    IF "%%i"=="ELEVATED_INSTANCE" (
        SET "ELEVATION_ATTEMPTED=YES"
        CALL :LOG_MESSAGE "This is an elevated instance - skipping further elevation checks" "INFO" "LAUNCHER"
    )
)

REM Repository configuration for auto-updates
SET "REPO_URL=https://github.com/ichimbogdancristian/script_mentenanta/archive/refs/heads/main.zip"
SET "ZIP_FILE=%WORKING_DIR%update.zip"
SET "EXTRACT_FOLDER=script_mentenanta-main"

CALL :LOG_MESSAGE "Self-discovery environment initialized" "SUCCESS" "LAUNCHER"

REM -----------------------------------------------------------------------------
REM Administrator Privilege Check
REM -----------------------------------------------------------------------------
CALL :LOG_MESSAGE "Checking administrator privileges..." "INFO" "LAUNCHER"

REM Simple admin check using NET SESSION
NET SESSION >nul 2>&1
IF %ERRORLEVEL% NEQ 0 (
    REM No admin rights - close and relaunch with admin rights
    CALL :LOG_MESSAGE "No admin privileges detected - relaunching with elevation" "WARN" "LAUNCHER"
    GOTO :ELEVATION_HANDLER
) ELSE (
    REM Has admin rights - continue running
    CALL :LOG_MESSAGE "Administrator privileges confirmed - continuing execution" "SUCCESS" "LAUNCHER"
    GOTO :CONTINUE_EXECUTION
)

REM -----------------------------------------------------------------------------
REM Elevation Handler (Used by Early Admin Check)
REM -----------------------------------------------------------------------------
:ELEVATION_HANDLER
CALL :LOG_MESSAGE "Handling privilege elevation..." "INFO" "LAUNCHER"

ECHO.
ECHO ================================================================================
ECHO  ADMINISTRATOR PRIVILEGES REQUIRED
ECHO ================================================================================
ECHO  This Windows Maintenance script requires administrator privileges to:
ECHO  - Install and update system packages
ECHO  - Modify system settings and registry
ECHO  - Install Windows updates
ECHO  - Remove bloatware and system apps
ECHO  
ECHO  The script will now CLOSE and RELAUNCH with elevated privileges.
ECHO  Please ACCEPT the UAC prompt when it appears.
ECHO ================================================================================
ECHO.

REM Launch elevated instance and close current instance immediately
CALL :LOG_MESSAGE "Launching elevated instance and closing current process..." "INFO" "LAUNCHER"
powershell -NoProfile -Command "Start-Process cmd -ArgumentList '/c \"%~f0\" ELEVATED_INSTANCE' -Verb RunAs"

REM Check if elevation was successful
IF !ERRORLEVEL! NEQ 0 (
    CALL :LOG_MESSAGE "Elevation failed or was cancelled by user" "ERROR" "LAUNCHER"
    ECHO ERROR: Failed to elevate privileges. UAC prompt may have been cancelled.
    ECHO Please run this script as Administrator or accept the UAC prompt.
    PAUSE
    EXIT /B 1
)

REM Exit current non-elevated instance
CALL :LOG_MESSAGE "Elevation initiated - terminating current instance" "INFO" "LAUNCHER"
EXIT /B 0

:CONTINUE_EXECUTION
REM -----------------------------------------------------------------------------
REM System Requirements Verification
REM -----------------------------------------------------------------------------
CALL :LOG_MESSAGE "Verifying system requirements..." "INFO" "LAUNCHER"

REM Windows version detection
FOR /F "tokens=*" %%i IN ('powershell -NoProfile -Command "try { (Get-CimInstance Win32_OperatingSystem).Version } catch { (Get-WmiObject Win32_OperatingSystem).Version }"') DO SET OS_VERSION=%%i
CALL :LOG_MESSAGE "Windows version: %OS_VERSION%" "INFO" "LAUNCHER"

REM PowerShell version check
FOR /F "tokens=*" %%i IN ('powershell -NoProfile -Command "$PSVersionTable.PSVersion.Major" 2^>nul') DO SET PS_VERSION=%%i
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

REM Check for required components
SET "STRUCTURE_VALID=YES"
SET "ORCHESTRATOR_PATH="

REM Look for MaintenanceOrchestrator.ps1
IF EXIST "%WORKING_DIR%MaintenanceOrchestrator.ps1" (
    SET "ORCHESTRATOR_PATH=%WORKING_DIR%MaintenanceOrchestrator.ps1"
    CALL :LOG_MESSAGE "Found orchestrator: MaintenanceOrchestrator.ps1" "SUCCESS" "LAUNCHER"
) ELSE IF EXIST "%WORKING_DIR%script.ps1" (
    SET "ORCHESTRATOR_PATH=%WORKING_DIR%script.ps1"
    CALL :LOG_MESSAGE "Found legacy orchestrator: script.ps1" "INFO" "LAUNCHER"
) ELSE (
    CALL :LOG_MESSAGE "No PowerShell orchestrator found in current directory" "WARN" "LAUNCHER"
    SET "STRUCTURE_VALID=NO"
)

REM Check for config directory
IF EXIST "%WORKING_DIR%config" (
    CALL :LOG_MESSAGE "Found configuration directory" "SUCCESS" "LAUNCHER"
) ELSE (
    CALL :LOG_MESSAGE "Configuration directory not found" "WARN" "LAUNCHER"
    SET "STRUCTURE_VALID=NO"
)

REM Check for modules directory
IF EXIST "%WORKING_DIR%modules" (
    CALL :LOG_MESSAGE "Found modules directory" "SUCCESS" "LAUNCHER"
) ELSE (
    CALL :LOG_MESSAGE "Modules directory not found" "WARN" "LAUNCHER"
    SET "STRUCTURE_VALID=NO"
)

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
powershell -NoProfile -ExecutionPolicy Bypass -Command "try { $ProgressPreference = 'SilentlyContinue'; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri '%REPO_URL%' -OutFile '%ZIP_FILE%' -UseBasicParsing; Write-Host 'DOWNLOAD_SUCCESS' } catch { Write-Host 'DOWNLOAD_FAILED'; Write-Error $_.Exception.Message; exit 1 }"

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
powershell -NoProfile -ExecutionPolicy Bypass -Command "try { Add-Type -AssemblyName System.IO.Compression.FileSystem; [System.IO.Compression.ZipFile]::ExtractToDirectory('%ZIP_FILE%', '%WORKING_DIR%'); Write-Host 'EXTRACTION_SUCCESS' } catch { Write-Host 'EXTRACTION_FAILED'; Write-Error $_.Exception.Message; exit 1 }"

IF !ERRORLEVEL! NEQ 0 (
    CALL :LOG_MESSAGE "Repository extraction failed" "ERROR" "LAUNCHER"
    PAUSE
    EXIT /B 3
)

REM Verify extraction
SET "EXTRACTED_PATH=%WORKING_DIR%%EXTRACT_FOLDER%"
IF EXIST "%EXTRACTED_PATH%" (
    CALL :LOG_MESSAGE "Repository extracted to: %EXTRACTED_PATH%" "SUCCESS" "LAUNCHER"
    
    REM Copy files to working directory if needed
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
powershell -NoProfile -ExecutionPolicy Bypass -Command "try { Add-MpPreference -ExclusionPath '%WORKING_DIR%' -ErrorAction SilentlyContinue; Add-MpPreference -ExclusionProcess 'powershell.exe' -ErrorAction SilentlyContinue; Add-MpPreference -ExclusionProcess 'pwsh.exe' -ErrorAction SilentlyContinue; Write-Host 'EXCLUSIONS_ADDED' } catch { Write-Host 'EXCLUSIONS_FAILED' }"

REM PowerShell 7 Detection and Installation
CALL :LOG_MESSAGE "Checking PowerShell 7 availability..." "INFO" "LAUNCHER"
pwsh.exe -Version >nul 2>&1
IF !ERRORLEVEL! NEQ 0 (
    CALL :LOG_MESSAGE "PowerShell 7 not found. Checking installation options..." "INFO" "LAUNCHER"
    
    REM Check if winget is available for PS7 installation
    winget --version >nul 2>&1
    IF !ERRORLEVEL! EQU 0 (
        CALL :LOG_MESSAGE "Installing PowerShell 7 via winget..." "INFO" "LAUNCHER"
        winget install Microsoft.PowerShell --silent --accept-package-agreements --accept-source-agreements
        IF !ERRORLEVEL! EQU 0 (
            CALL :LOG_MESSAGE "PowerShell 7 installed successfully via winget" "SUCCESS" "LAUNCHER"
            
            REM Refresh PATH environment variable to detect newly installed PowerShell 7
            CALL :LOG_MESSAGE "Refreshing PATH environment variable..." "INFO" "LAUNCHER"
            CALL :REFRESH_PATH
            
            REM Try to detect PowerShell 7 again after PATH refresh
            pwsh.exe -Version >nul 2>&1
            IF !ERRORLEVEL! EQU 0 (
                FOR /F "tokens=*" %%i IN ('pwsh.exe -NoProfile -Command "$PSVersionTable.PSVersion.ToString()" 2^>nul') DO SET PS7_VERSION=%%i
                CALL :LOG_MESSAGE "PowerShell 7 detected after installation: !PS7_VERSION!" "SUCCESS" "LAUNCHER"
            ) ELSE (
                CALL :LOG_MESSAGE "PowerShell 7 installed but not yet available in PATH" "WARN" "LAUNCHER"
                CALL :LOG_MESSAGE "Trying alternative detection methods..." "INFO" "LAUNCHER"
                CALL :DETECT_PS7_ALTERNATIVE
            )
        ) ELSE (
            CALL :LOG_MESSAGE "PowerShell 7 installation via winget failed" "WARN" "LAUNCHER"
        )
    ) ELSE (
        CALL :LOG_MESSAGE "Winget not available for PowerShell 7 installation" "INFO" "LAUNCHER"
    )
) ELSE (
    FOR /F "tokens=*" %%i IN ('pwsh.exe -NoProfile -Command "$PSVersionTable.PSVersion.ToString()" 2^>nul') DO SET PS7_VERSION=%%i
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
    CALL :LOG_MESSAGE "Winget not available - some features may be limited" "INFO" "LAUNCHER"
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
REM Pending Restart Detection and Management
REM -----------------------------------------------------------------------------
CALL :LOG_MESSAGE "Checking for pending system restarts..." "INFO" "LAUNCHER"

SET "PENDING_RESTART=NO"

REM Check Windows Update pending restart registry keys
REG QUERY "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired" >nul 2>&1
IF !ERRORLEVEL! EQU 0 (
    SET "PENDING_RESTART=YES"
    CALL :LOG_MESSAGE "Windows Update restart required (RebootRequired key found)" "INFO" "LAUNCHER"
)

REG QUERY "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending" >nul 2>&1
IF !ERRORLEVEL! EQU 0 (
    SET "PENDING_RESTART=YES"
    CALL :LOG_MESSAGE "Component Based Servicing restart pending" "INFO" "LAUNCHER"
)

REG QUERY "HKLM\SOFTWARE\Microsoft\Updates\UpdateExeVolatile" >nul 2>&1
IF !ERRORLEVEL! EQU 0 (
    SET "PENDING_RESTART=YES"
    CALL :LOG_MESSAGE "Update installer restart pending" "INFO" "LAUNCHER"
)

REM Check for SCCM/ConfigMgr pending restart
REG QUERY "HKLM\SOFTWARE\Microsoft\SMS\Mobile Client\Reboot Management\RebootData" >nul 2>&1
IF !ERRORLEVEL! EQU 0 (
    SET "PENDING_RESTART=YES"
    CALL :LOG_MESSAGE "SCCM restart pending" "INFO" "LAUNCHER"
)

CALL :LOG_MESSAGE "Pending restart status: %PENDING_RESTART%" "INFO" "LAUNCHER"

REM -----------------------------------------------------------------------------
REM Modular Task Scheduler Management
REM -----------------------------------------------------------------------------
CALL :LOG_MESSAGE "Managing scheduled tasks..." "INFO" "LAUNCHER"

SET "TASK_NAME=WindowsMaintenanceAutomation"
SET "STARTUP_TASK_NAME=WindowsMaintenanceStartup"

REM Always check and clean up existing startup task first
schtasks /Query /TN "%STARTUP_TASK_NAME%" >nul 2>&1
IF !ERRORLEVEL! EQU 0 (
    CALL :LOG_MESSAGE "Found existing startup task - removing it" "INFO" "LAUNCHER"
    schtasks /Delete /TN "%STARTUP_TASK_NAME%" /F >nul 2>&1
    IF !ERRORLEVEL! EQU 0 (
        CALL :LOG_MESSAGE "Startup task removed successfully" "SUCCESS" "LAUNCHER"
    ) ELSE (
        CALL :LOG_MESSAGE "Failed to remove startup task" "WARN" "LAUNCHER"
    )
)

REM Create startup task if pending restart detected
IF "%PENDING_RESTART%"=="YES" (
    CALL :LOG_MESSAGE "Creating startup task for post-restart continuation..." "INFO" "LAUNCHER"
    schtasks /Create ^
        /SC ONSTART ^
        /TN "%STARTUP_TASK_NAME%" ^
        /TR "\"%SCRIPT_PATH%\" -NonInteractive -PostRestart" ^
        /RL HIGHEST ^
        /RU SYSTEM ^
        /F >nul 2>&1
        
    IF !ERRORLEVEL! EQU 0 (
        CALL :LOG_MESSAGE "Startup task created successfully" "SUCCESS" "LAUNCHER"
        
        REM Initiate system restart to complete updates
        ECHO.
        ECHO ================================================================================
        ECHO  SYSTEM RESTART REQUIRED
        ECHO ================================================================================
        ECHO  Windows Updates or system components require a restart to complete installation.
        ECHO  The system will restart automatically in 30 seconds.
        ECHO  The maintenance script will continue automatically after restart.
        ECHO.
        ECHO  Press Ctrl+C to cancel the restart if needed.
        ECHO ================================================================================
        ECHO.
        
        CALL :LOG_MESSAGE "Initiating system restart in 30 seconds..." "INFO" "LAUNCHER"
        shutdown /r /t 30 /c "Windows Maintenance: Restarting to complete system updates"
        
        REM Exit script - it will continue after restart via the startup task
        CALL :LOG_MESSAGE "System restart initiated - script will continue after reboot" "INFO" "LAUNCHER"
        EXIT /B 0
        
    ) ELSE (
        CALL :LOG_MESSAGE "Startup task creation failed - cannot safely restart" "WARN" "LAUNCHER"
        CALL :LOG_MESSAGE "Manual restart may be required to complete updates" "WARN" "LAUNCHER"
    )
)

REM Check/Create monthly maintenance task using global path discovery
schtasks /Query /TN "%TASK_NAME%" >nul 2>&1
IF !ERRORLEVEL! EQU 0 (
    CALL :LOG_MESSAGE "Monthly scheduled task exists: %TASK_NAME%" "INFO" "LAUNCHER"
) ELSE (
    CALL :LOG_MESSAGE "Creating monthly scheduled task: %TASK_NAME%" "INFO" "LAUNCHER"
    schtasks /Create ^
        /SC MONTHLY ^
        /MO 1 ^
        /TN "%TASK_NAME%" ^
        /TR "\"%SCRIPT_PATH%\" -NonInteractive" ^
        /ST 02:00 ^
        /RL HIGHEST ^
        /RU SYSTEM ^
        /F >nul 2>&1
        
    IF !ERRORLEVEL! EQU 0 (
        CALL :LOG_MESSAGE "Monthly scheduled task created successfully" "SUCCESS" "LAUNCHER"
    ) ELSE (
        CALL :LOG_MESSAGE "Monthly scheduled task creation failed - continuing without scheduling" "WARN" "LAUNCHER"
    )
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

REM Determine PowerShell executable to use
SET "PS_EXECUTABLE=powershell.exe"
pwsh.exe -Version >nul 2>&1
IF !ERRORLEVEL! EQU 0 (
    SET "PS_EXECUTABLE=pwsh.exe"
    CALL :LOG_MESSAGE "Using PowerShell 7 for execution" "INFO" "LAUNCHER"
) ELSE (
    REM Check if we found PowerShell 7 via alternative detection
    IF "%PS7_FOUND%"=="YES" (
        SET "PS_EXECUTABLE=%PS7_PATH%"
        CALL :LOG_MESSAGE "Using PowerShell 7 from alternative path for execution" "INFO" "LAUNCHER"
    ) ELSE (
        CALL :LOG_MESSAGE "Using Windows PowerShell for execution" "INFO" "LAUNCHER"
    )
)

REM Parse command line arguments for the orchestrator
SET "PS_ARGS="
IF "%1"=="-NonInteractive" SET "PS_ARGS=%PS_ARGS% -NonInteractive"
IF "%1"=="-DryRun" SET "PS_ARGS=%PS_ARGS% -DryRun"
IF "%2"=="-DryRun" SET "PS_ARGS=%PS_ARGS% -DryRun"
IF "%1"=="-TaskNumbers" SET "PS_ARGS=%PS_ARGS% -TaskNumbers %2"
IF "%2"=="-PostRestart" SET "PS_ARGS=%PS_ARGS% -PostRestart"
IF "%3"=="-PostRestart" SET "PS_ARGS=%PS_ARGS% -PostRestart"

CALL :LOG_MESSAGE "Launching orchestrator with arguments: %PS_ARGS%" "INFO" "LAUNCHER"

REM Launch the PowerShell orchestrator
CALL :LOG_MESSAGE "Executing: %PS_EXECUTABLE% -ExecutionPolicy Bypass -File \"%ORCHESTRATOR_PATH%\" %PS_ARGS%" "DEBUG" "LAUNCHER"

%PS_EXECUTABLE% -ExecutionPolicy Bypass -File "%ORCHESTRATOR_PATH%" %PS_ARGS%
SET "ORCHESTRATOR_EXIT_CODE=!ERRORLEVEL!"

REM -----------------------------------------------------------------------------
REM Post-Execution Restart Logic
REM -----------------------------------------------------------------------------
CALL :LOG_MESSAGE "Checking post-execution restart requirements..." "INFO" "LAUNCHER"

REM Check if this was a post-restart execution
SET "IS_POST_RESTART=NO"
FOR %%i in (%*) DO (
    IF "%%i"=="-PostRestart" (
        SET "IS_POST_RESTART=YES"
        CALL :LOG_MESSAGE "This is a post-restart execution - cleaning up startup task" "INFO" "LAUNCHER"
    )
)

REM If this was a post-restart execution, remove the startup task
IF "%IS_POST_RESTART%"=="YES" (
    schtasks /Query /TN "%STARTUP_TASK_NAME%" >nul 2>&1
    IF !ERRORLEVEL! EQU 0 (
        CALL :LOG_MESSAGE "Removing startup task after successful post-restart execution" "INFO" "LAUNCHER"
        schtasks /Delete /TN "%STARTUP_TASK_NAME%" /F >nul 2>&1
        IF !ERRORLEVEL! EQU 0 (
            CALL :LOG_MESSAGE "Startup task cleanup completed" "SUCCESS" "LAUNCHER"
        ) ELSE (
            CALL :LOG_MESSAGE "Failed to remove startup task" "WARN" "LAUNCHER"
        )
    )
)

REM If pending restart was detected and this is not a post-restart execution, initiate restart
IF "%PENDING_RESTART%"=="YES" (
    IF "%IS_POST_RESTART%"=="NO" (
        CALL :LOG_MESSAGE "Pending restart detected - initiating system restart in 60 seconds..." "INFO" "LAUNCHER"
        ECHO.
        ECHO ================================================================================
        ECHO  SYSTEM RESTART REQUIRED
        ECHO ================================================================================
        ECHO  Windows updates require a system restart to complete installation.
        ECHO  A startup task has been created to continue maintenance after restart.
        ECHO.
        ECHO  The system will restart in 60 seconds...
        ECHO  Press Ctrl+C to cancel the restart if needed.
        ECHO ================================================================================
        ECHO.
        
        REM Give user 60 seconds to cancel if needed
        shutdown /r /t 60 /c "Windows Maintenance: Restarting to complete Windows updates. Maintenance will continue after restart."
        
        IF !ERRORLEVEL! EQU 0 (
            CALL :LOG_MESSAGE "System restart scheduled successfully" "SUCCESS" "LAUNCHER"
        ) ELSE (
            CALL :LOG_MESSAGE "Failed to schedule system restart" "ERROR" "LAUNCHER"
        )
        
        REM Exit immediately after scheduling restart
        CALL :LOG_MESSAGE "Maintenance launcher exiting - system will restart shortly" "INFO" "LAUNCHER"
        EXIT /B 0
    )
)

REM -----------------------------------------------------------------------------
REM Post-Execution Cleanup and Reporting
REM -----------------------------------------------------------------------------
CALL :LOG_MESSAGE "PowerShell orchestrator completed with exit code: %ORCHESTRATOR_EXIT_CODE%" "INFO" "LAUNCHER"

IF %ORCHESTRATOR_EXIT_CODE% EQU 0 (
    CALL :LOG_MESSAGE "Maintenance execution completed successfully" "SUCCESS" "LAUNCHER"
) ELSE (
    CALL :LOG_MESSAGE "Maintenance execution completed with errors (exit code: %ORCHESTRATOR_EXIT_CODE%)" "WARN" "LAUNCHER"
)

REM Check for generated reports
IF EXIST "%WORKING_DIR%temp_files\reports" (
    FOR %%F IN ("%WORKING_DIR%temp_files\reports\*.html") DO (
        CALL :LOG_MESSAGE "Generated report: %%~nxF" "INFO" "LAUNCHER"
    )
)

REM Auto-close behavior
IF "%1"=="-NonInteractive" (
    CALL :LOG_MESSAGE "Non-interactive mode - closing automatically" "INFO" "LAUNCHER"
    EXIT /B %ORCHESTRATOR_EXIT_CODE%
) ELSE (
    CALL :LOG_MESSAGE "Interactive mode - press any key to close" "INFO" "LAUNCHER"
    PAUSE >nul
    EXIT /B %ORCHESTRATOR_EXIT_CODE%
)

REM -----------------------------------------------------------------------------
REM End of Script
REM -----------------------------------------------------------------------------
ENDLOCAL