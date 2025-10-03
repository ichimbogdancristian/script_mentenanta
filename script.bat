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
REM Create log file if it doesn't exist and LOG_FILE is defined
IF DEFINED LOG_FILE (
    IF NOT EXIST "%LOG_FILE%" (
        REM Create the log file directory if needed
        FOR %%F IN ("%LOG_FILE%") DO (
            IF NOT EXIST "%%~dpF" MD "%%~dpF" 2>nul
        )
        REM Create empty log file
        ECHO. > "%LOG_FILE%" 2>nul
    )
    ECHO %LOG_ENTRY% >> "%LOG_FILE%" 2>nul
)
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

:DIAGNOSE_POWERSHELL
REM Comprehensive PowerShell diagnostic function
CALL :LOG_MESSAGE "=== PowerShell Diagnostic Information ===" "DEBUG" "LAUNCHER"

REM Check Windows PowerShell 5.1
CALL :LOG_MESSAGE "Checking Windows PowerShell 5.1..." "DEBUG" "LAUNCHER"
powershell.exe -NoProfile -Command "echo 'Windows PowerShell Version:'; $PSVersionTable.PSVersion; echo 'Execution Policy:'; Get-ExecutionPolicy" 2>&1 | (
    FOR /F "tokens=*" %%A IN ('MORE') DO CALL :LOG_MESSAGE "WinPS: %%A" "DEBUG" "LAUNCHER"
)

REM Check PowerShell 7
CALL :LOG_MESSAGE "Checking PowerShell 7..." "DEBUG" "LAUNCHER"
pwsh.exe -NoProfile -Command "echo 'PowerShell 7 Version:'; $PSVersionTable.PSVersion; echo 'Execution Policy:'; Get-ExecutionPolicy" 2>&1 | (
    FOR /F "tokens=*" %%A IN ('MORE') DO CALL :LOG_MESSAGE "PS7: %%A" "DEBUG" "LAUNCHER"
)

REM Check PATH for PowerShell executables
CALL :LOG_MESSAGE "Checking PATH for PowerShell executables..." "DEBUG" "LAUNCHER"
WHERE powershell.exe 2>nul | (
    FOR /F "tokens=*" %%A IN ('MORE') DO CALL :LOG_MESSAGE "Found powershell.exe: %%A" "DEBUG" "LAUNCHER"
)
WHERE pwsh.exe 2>nul | (
    FOR /F "tokens=*" %%A IN ('MORE') DO CALL :LOG_MESSAGE "Found pwsh.exe: %%A" "DEBUG" "LAUNCHER"
)

REM Check file associations
CALL :LOG_MESSAGE "Checking .ps1 file association..." "DEBUG" "LAUNCHER"
ASSOC .ps1 2>nul | (
    FOR /F "tokens=*" %%A IN ('MORE') DO CALL :LOG_MESSAGE "PS1 ASSOC: %%A" "DEBUG" "LAUNCHER"
)

REM Test simple PowerShell execution
CALL :LOG_MESSAGE "Testing simple PowerShell 7 execution..." "DEBUG" "LAUNCHER"
pwsh.exe -NoProfile -Command "Write-Output 'PowerShell 7 execution test successful'" 2>&1 | (
    FOR /F "tokens=*" %%A IN ('MORE') DO CALL :LOG_MESSAGE "PS7 Test: %%A" "DEBUG" "LAUNCHER"
)

CALL :LOG_MESSAGE "=== End PowerShell Diagnostics ===" "DEBUG" "LAUNCHER"
EXIT /B

:DETECT_PS7_ALTERNATIVE
REM Try common PowerShell 7 installation paths (Enhanced with more locations)
SET "PS7_FOUND=NO"
FOR %%P IN (
    "%ProgramFiles%\PowerShell\7\pwsh.exe"
    "%ProgramFiles(x86)%\PowerShell\7\pwsh.exe"
    "%LOCALAPPDATA%\Microsoft\WindowsApps\pwsh.exe"
    "%ProgramFiles%\PowerShell\pwsh.exe"
    "%ProgramFiles%\PowerShell\7.5.3\pwsh.exe"
    "%ProgramFiles%\PowerShell\7.5\pwsh.exe"
    "%ProgramFiles%\PowerShell\7.4\pwsh.exe"
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

REM Setup logging - ensure logs directory exists
IF NOT EXIST "%WORKING_DIR%temp_files" MD "%WORKING_DIR%temp_files" 2>nul
IF NOT EXIST "%WORKING_DIR%temp_files\logs" MD "%WORKING_DIR%temp_files\logs" 2>nul
SET "LOG_FILE=%WORKING_DIR%temp_files\logs\maintenance.log"
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

REM -----------------------------------------------------------------------------
REM Robust Script Path Detection for Scheduled Tasks
REM Determines the best path to use for scheduled task creation
REM -----------------------------------------------------------------------------
SET "SCHEDULED_TASK_SCRIPT_PATH="

REM Priority 1: Use current executing script path (most reliable)
IF EXIST "%SCRIPT_PATH%" (
    SET "SCHEDULED_TASK_SCRIPT_PATH=%SCRIPT_PATH%"
    CALL :LOG_MESSAGE "Scheduled task will use current script path: %SCRIPT_PATH%" "DEBUG" "LAUNCHER"
    GOTO :SCHEDULED_TASK_PATH_COMPLETE
)

REM Priority 2: Look for script.bat in current directory
IF EXIST "%SCRIPT_DIR%script.bat" (
    SET "SCHEDULED_TASK_SCRIPT_PATH=%SCRIPT_DIR%script.bat"
    CALL :LOG_MESSAGE "Scheduled task will use directory script: %SCRIPT_DIR%script.bat" "DEBUG" "LAUNCHER"
    GOTO :SCHEDULED_TASK_PATH_COMPLETE
)

REM Priority 3: Use script path as fallback (should not happen)
SET "SCHEDULED_TASK_SCRIPT_PATH=%SCRIPT_PATH%"
CALL :LOG_MESSAGE "Using fallback script path for scheduled task: %SCRIPT_PATH%" "WARN" "LAUNCHER"

:SCHEDULED_TASK_PATH_COMPLETE

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
powershell -NoProfile -ExecutionPolicy Bypass -Command "try { $ProgressPreference = 'SilentlyContinue'; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri '%REPO_URL%' -OutFile '%ZIP_FILE%' -UseBasicParsing -TimeoutSec 60; Write-Host 'DOWNLOAD_SUCCESS' } catch { Write-Host 'DOWNLOAD_FAILED'; Write-Error $_.Exception.Message }"

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
powershell -NoProfile -ExecutionPolicy Bypass -Command "try { Add-Type -AssemblyName System.IO.Compression.FileSystem; [System.IO.Compression.ZipFile]::ExtractToDirectory('%ZIP_FILE%', '%WORKING_DIR%'); Write-Host 'EXTRACTION_SUCCESS' } catch { Write-Host 'EXTRACTION_FAILED'; Write-Error $_.Exception.Message }"

IF !ERRORLEVEL! NEQ 0 (
    CALL :LOG_MESSAGE "Repository extraction failed" "ERROR" "LAUNCHER"
    PAUSE
    EXIT /B 3
)

REM Verify extraction
SET "EXTRACTED_PATH=%WORKING_DIR%%EXTRACT_FOLDER%"
IF EXIST "%EXTRACTED_PATH%" (
    CALL :LOG_MESSAGE "Repository extracted to: %EXTRACTED_PATH%" "SUCCESS" "LAUNCHER"
    
    REM Update working directory to use extracted repository
    SET "WORKING_DIR=%EXTRACTED_PATH%\"
    SET "WORKING_DIRECTORY=%EXTRACTED_PATH%\"
    
    REM Check for orchestrator in extracted files
    IF EXIST "%EXTRACTED_PATH%\MaintenanceOrchestrator.ps1" (
        SET "ORCHESTRATOR_PATH=%EXTRACTED_PATH%\MaintenanceOrchestrator.ps1"
        CALL :LOG_MESSAGE "Using extracted orchestrator: !ORCHESTRATOR_PATH!" "INFO" "LAUNCHER"
    ) ELSE IF EXIST "%EXTRACTED_PATH%\script.ps1" (
        SET "ORCHESTRATOR_PATH=%EXTRACTED_PATH%\script.ps1"
        CALL :LOG_MESSAGE "Using extracted legacy orchestrator: !ORCHESTRATOR_PATH!" "INFO" "LAUNCHER"
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

REM Clean up ZIP file
DEL /Q "%ZIP_FILE%" >nul 2>&1

REM -----------------------------------------------------------------------------
REM Enhanced Dependency Management
REM -----------------------------------------------------------------------------
:DEPENDENCY_MANAGEMENT
CALL :LOG_MESSAGE "Starting dependency management..." "INFO" "LAUNCHER"

REM Windows Defender Exclusions (Enhanced) - Non-blocking
CALL :LOG_MESSAGE "Setting up Windows Defender exclusions..." "INFO" "LAUNCHER"
powershell -NoProfile -ExecutionPolicy Bypass -Command "try { Add-MpPreference -ExclusionPath '%WORKING_DIR%' -ErrorAction SilentlyContinue; Add-MpPreference -ExclusionProcess 'powershell.exe' -ErrorAction SilentlyContinue; Add-MpPreference -ExclusionProcess 'pwsh.exe' -ErrorAction SilentlyContinue; Write-Host 'EXCLUSIONS_ADDED' } catch { Write-Host 'EXCLUSIONS_FAILED' }" 2>nul

REM -----------------------------------------------------------------------------
REM Dependency Management - Direct Downloads from Official Sources
REM Installation Order: Winget -> PowerShell 7 -> NuGet -> PSGallery -> PSWindowsUpdate -> Chocolatey
REM -----------------------------------------------------------------------------
CALL :LOG_MESSAGE "Starting dependency installation with optimized order..." "INFO" "LAUNCHER"
CALL :LOG_MESSAGE "EMERGENCY: If process hangs for >5 minutes, press Ctrl+C and run MaintenanceOrchestrator.ps1 directly" "WARN" "LAUNCHER"

REM -----------------------------------------------------------------------------
REM 1. Windows Package Manager (Winget) - Foundation package manager
REM -----------------------------------------------------------------------------
CALL :LOG_MESSAGE "Installing Windows Package Manager (winget)..." "INFO" "LAUNCHER"

REM Improved Winget detection: check both version and path (Original Method)
winget --version >nul 2>&1
SET "WINGET_FOUND=0"
IF !ERRORLEVEL! EQU 0 (
    SET "WINGET_FOUND=1"
    CALL :LOG_MESSAGE "Winget detected via version check." "DEBUG" "LAUNCHER"
) ELSE (
    where winget >nul 2>&1
    IF !ERRORLEVEL! EQU 0 (
        SET "WINGET_FOUND=1"
        CALL :LOG_MESSAGE "Winget detected via PATH (where command)." "DEBUG" "LAUNCHER"
    )
)

IF !WINGET_FOUND! EQU 0 (
    CALL :LOG_MESSAGE "Winget not found, downloading from official Microsoft source..." "INFO" "LAUNCHER"
    REM Download latest App Installer from Microsoft Store (Original Method)
    SET "WINGET_URL=https://github.com/microsoft/winget-cli/releases/latest/download/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"
    SET "WINGET_FILE=!TEMP!\Microsoft.DesktopAppInstaller.msixbundle"
    powershell -ExecutionPolicy Bypass -Command "try { $ProgressPreference = 'SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri '!WINGET_URL!' -OutFile '!WINGET_FILE!' -UseBasicParsing -TimeoutSec 30; Write-Host '[INFO] Winget downloaded successfully' } catch { Write-Host '[WARN] Winget download failed:' $_.Exception.Message }"
    IF !ERRORLEVEL! EQU 0 (
        CALL :LOG_MESSAGE "Installing Winget package..." "INFO" "LAUNCHER"
        powershell -ExecutionPolicy Bypass -Command "try { Add-AppxPackage -Path '!WINGET_FILE!' -ErrorAction SilentlyContinue; Write-Host '[INFO] Winget installation attempted' } catch { Write-Host '[WARN] Winget installation failed:' $_.Exception.Message }"
        
        REM Always continue regardless of winget installation result
        CALL :LOG_MESSAGE "Winget installation process completed, checking availability..." "INFO" "LAUNCHER"
        DEL /F /Q "!WINGET_FILE!" >nul 2>&1
        
        REM Refresh PATH and test again
        CALL :REFRESH_PATH
        timeout /t 3 /nobreak >nul 2>&1
        winget --version >nul 2>&1
        IF !ERRORLEVEL! EQU 0 (
            CALL :LOG_MESSAGE "Winget is now available after installation" "SUCCESS" "LAUNCHER"
        ) ELSE (
            CALL :LOG_MESSAGE "Winget installation completed but may require system restart" "WARN" "LAUNCHER"
        )
    ) ELSE (
        CALL :LOG_MESSAGE "Winget download failed, but continuing..." "WARN" "LAUNCHER"
    )
) ELSE (
    CALL :LOG_MESSAGE "Winget is already available." "INFO" "LAUNCHER"
)

REM -----------------------------------------------------------------------------
REM 2. PowerShell 7 - Modern PowerShell environment
REM -----------------------------------------------------------------------------
CALL :LOG_MESSAGE "Installing PowerShell 7..." "INFO" "LAUNCHER"

REM Initial detection
pwsh.exe -Version >nul 2>&1
IF !ERRORLEVEL! EQU 0 (
    FOR /F "tokens=*" %%i IN ('pwsh.exe -NoProfile -Command "$PSVersionTable.PSVersion.ToString()" 2^>nul') DO SET PS7_VERSION=%%i
    CALL :LOG_MESSAGE "PowerShell 7 available: %PS7_VERSION%" "SUCCESS" "LAUNCHER"
    GOTO :PS7_DETECTION_COMPLETE
)

REM Try alternative detection methods first
CALL :LOG_MESSAGE "PowerShell 7 not found in PATH, trying alternative detection..." "INFO" "LAUNCHER"
CALL :DETECT_PS7_ALTERNATIVE

IF "%PS7_FOUND%"=="YES" (
    FOR /F "tokens=*" %%i IN ('"%PS7_PATH%" -NoProfile -Command "$PSVersionTable.PSVersion.ToString()" 2^>nul') DO SET PS7_VERSION=%%i
    CALL :LOG_MESSAGE "PowerShell 7 found via alternative detection: %PS7_VERSION%" "SUCCESS" "LAUNCHER"
    GOTO :PS7_DETECTION_COMPLETE
)

REM PowerShell 7 not found - attempt installation
CALL :LOG_MESSAGE "PowerShell 7 not found. Attempting installation..." "WARN" "LAUNCHER"

REM Try multiple installation methods
SET "PS7_INSTALL_SUCCESS=NO"

REM Method 1: Winget PowerShell 7.5.3 Installation (if available)
winget --version >nul 2>&1
IF !ERRORLEVEL! EQU 0 (
    CALL :LOG_MESSAGE "Installing PowerShell 7.5.3 via winget..." "INFO" "LAUNCHER"
    ECHO Installing PowerShell 7.5.3... This may take a few minutes.
    
    REM Try winget installation with timeout
    CALL :LOG_MESSAGE "Attempting winget PowerShell installation with 3-minute timeout..." "INFO" "LAUNCHER"
    timeout /t 3 /nobreak >nul 2>&1
    START /WAIT /B "" cmd /c "winget install Microsoft.PowerShell --silent --accept-package-agreements --accept-source-agreements --disable-interactivity && echo WINGET_PS7_SUCCESS || echo WINGET_PS7_FAILED" >"%TEMP%\winget_ps7.log" 2>&1
    
    REM Check result
    FIND "WINGET_PS7_SUCCESS" "%TEMP%\winget_ps7.log" >nul 2>&1
    IF !ERRORLEVEL! EQU 0 (
        CALL :LOG_MESSAGE "PowerShell 7 installation completed via winget" "SUCCESS" "LAUNCHER"
        SET "PS7_INSTALL_SUCCESS=YES"
    ) ELSE (
        CALL :LOG_MESSAGE "PowerShell 7 installation via winget failed or timed out" "WARN" "LAUNCHER"
    )
    DEL /F /Q "%TEMP%\winget_ps7.log" >nul 2>&1
) ELSE (
    CALL :LOG_MESSAGE "Winget not available - using direct download method..." "INFO" "LAUNCHER"
)

REM Method 2: PowerShell 7.5.3 Direct Download (Original Working Method)
IF "%PS7_INSTALL_SUCCESS%"=="NO" (
    CALL :LOG_MESSAGE "Attempting PowerShell 7.5.3 installation via direct download..." "INFO" "LAUNCHER"
    
    REM Set download URL for PowerShell 7.5.3 (latest stable)
    SET "PS7_INSTALLER=%TEMP%\PowerShell-7.5.3.msi"
    
    REM Detect architecture and set appropriate download URL
    IF "%PROCESSOR_ARCHITECTURE%"=="AMD64" (
        SET "PS7_URL=https://github.com/PowerShell/PowerShell/releases/download/v7.5.3/PowerShell-7.5.3-win-x64.msi"
    ) ELSE (
        SET "PS7_URL=https://github.com/PowerShell/PowerShell/releases/download/v7.5.3/PowerShell-7.5.3-win-x86.msi"
    )
    
    REM Download PowerShell 7.5.3 (Original Method)
    CALL :LOG_MESSAGE "Downloading PowerShell 7.5.3..." "INFO" "LAUNCHER"
    powershell -ExecutionPolicy Bypass -Command "try { $ProgressPreference = 'SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri '!PS7_URL!' -OutFile '!PS7_INSTALLER!' -UseBasicParsing -TimeoutSec 60; Write-Host '[INFO] PowerShell 7.5.3 downloaded successfully' } catch { Write-Host '[ERROR] PowerShell 7.5.3 download failed:' $_.Exception.Message }"
    
    IF !ERRORLEVEL! EQU 0 (
        CALL :LOG_MESSAGE "Installing PowerShell 7.5.3..." "INFO" "LAUNCHER"
        msiexec /i "!PS7_INSTALLER!" /quiet /norestart
        IF !ERRORLEVEL! EQU 0 (
            CALL :LOG_MESSAGE "PowerShell 7.5.3 installed successfully" "SUCCESS" "LAUNCHER"
            SET "PS7_INSTALL_SUCCESS=YES"
            
            REM Refresh PATH environment variable for current session (Original Method)
            FOR /F "tokens=2*" %%A IN ('REG QUERY "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" /v PATH') DO SET "PATH=%%B"
            REM Add common PowerShell 7 installation paths to current session
            IF EXIST "%ProgramFiles%\PowerShell\7" SET "PATH=%PATH%;%ProgramFiles%\PowerShell\7"
            IF EXIST "%ProgramFiles(x86)%\PowerShell\7" SET "PATH=%PATH%;%ProgramFiles(x86)%\PowerShell\7"
            
            CALL :LOG_MESSAGE "PowerShell 7.5.3 installation completed successfully" "SUCCESS" "LAUNCHER"
        ) ELSE (
            CALL :LOG_MESSAGE "PowerShell 7.5.3 installation failed" "WARN" "LAUNCHER"
        )
        REM Cleanup installer file
        DEL /F /Q "!PS7_INSTALLER!" >nul 2>&1
    ) ELSE (
        CALL :LOG_MESSAGE "PowerShell 7.5.3 download failed" "WARN" "LAUNCHER"
    )
)

REM Method 3: Try Chocolatey if available
IF "%PS7_INSTALL_SUCCESS%"=="NO" (
    choco --version >nul 2>&1
    IF !ERRORLEVEL! EQU 0 (
        CALL :LOG_MESSAGE "Attempting PowerShell 7 installation via Chocolatey..." "INFO" "LAUNCHER"
        choco install powershell-core -y --no-progress >nul 2>&1
        IF !ERRORLEVEL! EQU 0 (
            CALL :LOG_MESSAGE "PowerShell 7 installation completed via Chocolatey" "SUCCESS" "LAUNCHER"
            SET "PS7_INSTALL_SUCCESS=YES"
        ) ELSE (
            CALL :LOG_MESSAGE "PowerShell 7 installation via Chocolatey failed" "WARN" "LAUNCHER"
        )
    )
)

REM Post-installation verification
IF "%PS7_INSTALL_SUCCESS%"=="YES" (
    REM Refresh PATH environment variable
    CALL :LOG_MESSAGE "Refreshing PATH environment variable..." "INFO" "LAUNCHER"
    CALL :REFRESH_PATH
    
    REM Wait a moment for the installation to settle
    timeout /t 5 /nobreak >nul 2>&1
    
    REM Try detection again
    pwsh.exe -Version >nul 2>&1
    IF !ERRORLEVEL! EQU 0 (
        FOR /F "tokens=*" %%i IN ('pwsh.exe -NoProfile -Command "$PSVersionTable.PSVersion.ToString()" 2^>nul') DO SET PS7_VERSION=%%i
        CALL :LOG_MESSAGE "PowerShell 7 successfully installed and detected: %PS7_VERSION%" "SUCCESS" "LAUNCHER"
    ) ELSE (
        CALL :LOG_MESSAGE "PowerShell 7 installed but not immediately available. Trying alternative detection..." "INFO" "LAUNCHER"
        CALL :DETECT_PS7_ALTERNATIVE
        IF "%PS7_FOUND%"=="YES" (
            FOR /F "tokens=*" %%i IN ('"%PS7_PATH%" -NoProfile -Command "$PSVersionTable.PSVersion.ToString()" 2^>nul') DO SET PS7_VERSION=%%i
            CALL :LOG_MESSAGE "PowerShell 7 detected via alternative path: %PS7_VERSION%" "SUCCESS" "LAUNCHER"
        ) ELSE (
            CALL :LOG_MESSAGE "PowerShell 7 installation succeeded but detection failed" "WARN" "LAUNCHER"
            CALL :LOG_MESSAGE "You may need to restart your terminal or computer" "WARN" "LAUNCHER"
        )
    )
) ELSE (
    CALL :LOG_MESSAGE "All PowerShell 7 installation methods failed" "ERROR" "LAUNCHER"
    CALL :LOG_MESSAGE "Manual installation required from: https://github.com/PowerShell/PowerShell/releases/latest" "INFO" "LAUNCHER"
)

:PS7_DETECTION_COMPLETE

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
REM Initial Cleanup - Remove any leftover startup tasks from previous runs
REM -----------------------------------------------------------------------------
CALL :LOG_MESSAGE "Performing initial cleanup..." "INFO" "LAUNCHER"

REM Remove all possible startup task variations from previous versions
schtasks /delete /tn "Windows Maintenance Post-Restart Startup" /f >nul 2>&1
schtasks /delete /tn "Windows Maintenance Startup" /f >nul 2>&1 
schtasks /delete /tn "WindowsMaintenanceStartup" /f >nul 2>&1
schtasks /delete /tn "WindowsMaintenanceStartupFallback" /f >nul 2>&1
schtasks /delete /tn "ScriptMentenantaStartup" /f >nul 2>&1

CALL :LOG_MESSAGE "Initial cleanup completed" "DEBUG" "LAUNCHER"

REM -----------------------------------------------------------------------------
REM Enhanced Pending Restart Detection (Based on Archived Script Logic)
REM -----------------------------------------------------------------------------
CALL :LOG_MESSAGE "Checking for pending system restarts..." "INFO" "LAUNCHER"

SET "PENDING_RESTART=NO"

REM Primary method: Use PSWindowsUpdate module if available (most accurate)
IF "%POWERSHELL_EXE%"=="" (
    SET "POWERSHELL_EXE=powershell.exe"
)

CALL :LOG_MESSAGE "Attempting PSWindowsUpdate restart detection..." "DEBUG" "LAUNCHER"
"%POWERSHELL_EXE%" -NoProfile -NonInteractive -Command ^
    "try { Import-Module PSWindowsUpdate -ErrorAction Stop; $reboot = Get-WURebootStatus -Silent; if ($reboot -eq $true) { exit 1 } else { exit 0 } } catch { exit 2 }" 2>nul

IF !ERRORLEVEL! EQU 1 (
    SET "PENDING_RESTART=YES"
    CALL :LOG_MESSAGE "PSWindowsUpdate module detected restart required" "INFO" "LAUNCHER"
    GOTO :RESTART_DETECTION_COMPLETE
)

IF !ERRORLEVEL! EQU 0 (
    CALL :LOG_MESSAGE "PSWindowsUpdate module reports no restart required" "DEBUG" "LAUNCHER"
    GOTO :RESTART_DETECTION_COMPLETE
)

REM Fallback methods: Registry-based detection
CALL :LOG_MESSAGE "PSWindowsUpdate unavailable, using registry-based detection..." "DEBUG" "LAUNCHER"

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

:RESTART_DETECTION_COMPLETE
CALL :LOG_MESSAGE "Pending restart status: %PENDING_RESTART%" "INFO" "LAUNCHER"

REM -----------------------------------------------------------------------------
REM Simple Startup Task Management
REM -----------------------------------------------------------------------------
CALL :LOG_MESSAGE "Managing startup task..." "INFO" "LAUNCHER"

SET "TASK_NAME=ScriptMentenantaMonthly"
SET "STARTUP_TASK_NAME=ScriptMentenantaStartup"

REM Simple Startup Task Logic - Check → Remove → Check Pending → Create+Restart OR Continue
CALL :LOG_MESSAGE "Startup Task Management: Simple Logic Implementation" "INFO" "LAUNCHER"

REM Step 1: Check if startup task exists, if yes remove it
CALL :LOG_MESSAGE "Checking for existing startup task '%STARTUP_TASK_NAME%'..." "DEBUG" "LAUNCHER"
schtasks /Query /TN "%STARTUP_TASK_NAME%" >nul 2>&1
IF !ERRORLEVEL! EQU 0 (
    CALL :LOG_MESSAGE "Startup task exists - removing it..." "INFO" "LAUNCHER"
    schtasks /Delete /TN "%STARTUP_TASK_NAME%" /F >nul 2>&1
    IF !ERRORLEVEL! EQU 0 (
        CALL :LOG_MESSAGE "Startup task removed successfully" "SUCCESS" "LAUNCHER"
    ) ELSE (
        CALL :LOG_MESSAGE "Failed to remove existing startup task" "WARN" "LAUNCHER"
    )
) ELSE (
    CALL :LOG_MESSAGE "No existing startup task found" "DEBUG" "LAUNCHER"
)

REM Step 2: Check for pending restarts
CALL :LOG_MESSAGE "Checking for pending system restarts..." "DEBUG" "LAUNCHER"
IF "%PENDING_RESTART%"=="YES" (
    REM Step 3a: Pending restart detected - create startup task and restart system
    CALL :LOG_MESSAGE "Pending restart detected - creating startup task and restarting system" "INFO" "LAUNCHER"
    
    REM Create startup task to continue after restart
    CALL :LOG_MESSAGE "Creating startup task: %SCHEDULED_TASK_SCRIPT_PATH%" "DEBUG" "LAUNCHER"
    schtasks /Create /SC ONLOGON /TN "%STARTUP_TASK_NAME%" /TR "%SCHEDULED_TASK_SCRIPT_PATH%" /RL HIGHEST /RU "%USERNAME%" /DELAY 0001:00 /F >nul 2>&1
    
    IF !ERRORLEVEL! EQU 0 (
        CALL :LOG_MESSAGE "Startup task created successfully" "SUCCESS" "LAUNCHER"
        
        REM Initiate system restart
        ECHO.
        ECHO ================================================================================
        ECHO  SYSTEM RESTART REQUIRED
        ECHO ================================================================================
        ECHO  Pending updates require a restart. System will restart in 10 seconds.
        ECHO  Maintenance script will continue automatically after restart.
        ECHO ================================================================================
        ECHO.
        
        shutdown /r /t 10 /c "System restart required to complete pending updates"
        CALL :LOG_MESSAGE "System restarting in 10 seconds..." "INFO" "LAUNCHER"
        timeout /t 12 /nobreak >nul
        EXIT /B 0
        
    ) ELSE (
        CALL :LOG_MESSAGE "Failed to create startup task - continuing without restart" "ERROR" "LAUNCHER"
    )
) ELSE (
    REM Step 3b: No pending restart - continue with script execution
    CALL :LOG_MESSAGE "No pending restart required - continuing with script execution" "INFO" "LAUNCHER"
)

REM Enhanced Monthly Scheduled Task Setup (Original Working Method)
CALL :LOG_MESSAGE "Checking for monthly scheduled task '%TASK_NAME%'..." "INFO" "LAUNCHER"
schtasks /Query /TN "%TASK_NAME%" >nul 2>&1
IF !ERRORLEVEL! EQU 0 (
    CALL :LOG_MESSAGE "Monthly scheduled task already exists. Skipping creation." "INFO" "LAUNCHER"
) ELSE (
    CALL :LOG_MESSAGE "Monthly scheduled task not found. Creating..." "INFO" "LAUNCHER"
    CALL :LOG_MESSAGE "Using script path for task: %SCHEDULED_TASK_SCRIPT_PATH%" "DEBUG" "LAUNCHER"
    
    REM Create scheduled task with proper escaping (ORIGINAL METHOD)
    schtasks /Create ^
        /SC MONTHLY ^
        /MO 1 ^
        /TN "%TASK_NAME%" ^
        /TR "%SCHEDULED_TASK_SCRIPT_PATH%" ^
        /ST 01:00 ^
        /RL HIGHEST ^
        /RU SYSTEM ^
        /F >"%WORKING_DIR%schtasks_create.log" 2>&1
        
    IF !ERRORLEVEL! EQU 0 (
        CALL :LOG_MESSAGE "Monthly scheduled task created successfully." "SUCCESS" "LAUNCHER"
        schtasks /Query /TN "%TASK_NAME%" /V >nul 2>&1
        IF !ERRORLEVEL! EQU 0 (
            CALL :LOG_MESSAGE "Task verification successful." "INFO" "LAUNCHER"
            FOR /F "tokens=2 delims=:" %%i IN ('schtasks /Query /TN "%TASK_NAME%" /FO LIST ^| findstr /C:"Next Run Time"') DO (
                CALL :LOG_MESSAGE "Next scheduled run: %%i" "INFO" "LAUNCHER"
            )
        )
    ) ELSE (
        CALL :LOG_MESSAGE "Failed to create monthly scheduled task. See schtasks_create.log for details." "ERROR" "LAUNCHER"
        REM Display the actual error for debugging
        IF EXIST "%WORKING_DIR%schtasks_create.log" (
            CALL :LOG_MESSAGE "Scheduled task creation error details:" "ERROR" "LAUNCHER"
            TYPE "%WORKING_DIR%schtasks_create.log"
        ) ELSE (
            CALL :LOG_MESSAGE "No error log file created." "ERROR" "LAUNCHER"
        )
        
        REM Try alternative approach with current user instead of SYSTEM (ORIGINAL FALLBACK)
        CALL :LOG_MESSAGE "Attempting to create task under current user account..." "INFO" "LAUNCHER"
        CALL :LOG_MESSAGE "Using script path for user task: %SCHEDULED_TASK_SCRIPT_PATH%" "DEBUG" "LAUNCHER"
        schtasks /Create ^
            /SC MONTHLY ^
            /MO 1 ^
            /TN "%TASK_NAME%" ^
            /TR "%SCHEDULED_TASK_SCRIPT_PATH%" ^
            /ST 01:00 ^
            /RL HIGHEST ^
            /F >"%WORKING_DIR%schtasks_create_user.log" 2>&1
            
        IF !ERRORLEVEL! EQU 0 (
            CALL :LOG_MESSAGE "Monthly scheduled task created successfully under current user." "SUCCESS" "LAUNCHER"
        ) ELSE (
            CALL :LOG_MESSAGE "Failed to create scheduled task under current user as well." "WARN" "LAUNCHER"
            IF EXIST "%WORKING_DIR%schtasks_create_user.log" TYPE "%WORKING_DIR%schtasks_create_user.log"
        )
    )
)

REM -----------------------------------------------------------------------------
REM Dependency Management Completion Check
REM -----------------------------------------------------------------------------
CALL :LOG_MESSAGE "Dependency management section completed - proceeding to orchestrator..." "INFO" "LAUNCHER"

REM Verify we have a valid orchestrator path
IF "%ORCHESTRATOR_PATH%"=="" (
    CALL :LOG_MESSAGE "Orchestrator path not set - attempting to find orchestrator..." "WARN" "LAUNCHER"
    IF EXIST "%WORKING_DIR%MaintenanceOrchestrator.ps1" (
        SET "ORCHESTRATOR_PATH=%WORKING_DIR%MaintenanceOrchestrator.ps1"
        CALL :LOG_MESSAGE "Found orchestrator in working directory" "SUCCESS" "LAUNCHER"
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

REM Determine PowerShell executable to use - MUST be PowerShell 7
SET "PS_EXECUTABLE="
SET "PS7_AVAILABLE=NO"

REM First check: pwsh.exe in PATH
pwsh.exe -Version >nul 2>&1
IF !ERRORLEVEL! EQU 0 (
    SET "PS_EXECUTABLE=pwsh.exe"
    SET "PS7_AVAILABLE=YES"
    CALL :LOG_MESSAGE "Using PowerShell 7 for execution (pwsh.exe)" "INFO" "LAUNCHER"
) ELSE (
    REM Second check: Alternative PS7 detection
    IF "%PS7_FOUND%"=="YES" (
        SET "PS_EXECUTABLE=%PS7_PATH%"
        SET "PS7_AVAILABLE=YES"
        CALL :LOG_MESSAGE "Using PowerShell 7 from alternative path for execution" "INFO" "LAUNCHER"
    ) ELSE (
        CALL :LOG_MESSAGE "PowerShell 7 not available - orchestrator requires PS7" "ERROR" "LAUNCHER"
        SET "PS7_AVAILABLE=NO"
    )
)

REM Verify PowerShell 7 is available before proceeding
IF "%PS7_AVAILABLE%"=="NO" (
    ECHO.
    ECHO ================================================================================
    ECHO  POWERSHELL 7 INSTALLATION REQUIRED
    ECHO ================================================================================
    ECHO  The maintenance orchestrator requires PowerShell 7.0 or later to function.
    ECHO  Windows PowerShell 5.1 is not compatible due to modern language features.
    ECHO.
    ECHO  Automatic installation failed. Please install PowerShell 7 manually:
    ECHO.
    ECHO  QUICK INSTALLATION OPTIONS:
    ECHO  1. Download installer: https://github.com/PowerShell/PowerShell/releases/latest
    ECHO  2. Via Microsoft Store: Search for "PowerShell"
    ECHO  3. Via winget (if available): winget install Microsoft.PowerShell
    ECHO  4. Via Chocolatey: choco install powershell-core
    ECHO.
    ECHO  RECOMMENDED: Download the .msi installer from GitHub releases for easiest setup.
    ECHO  After installation, restart this script or open a new command prompt.
    ECHO ================================================================================
    ECHO.
    CALL :LOG_MESSAGE "Maintenance cannot continue without PowerShell 7" "ERROR" "LAUNCHER"
    
    REM Offer to open download page
    SET /P "OPEN_BROWSER=Would you like to open the PowerShell download page? (Y/N): "
    IF /I "%OPEN_BROWSER%"=="Y" (
        CALL :LOG_MESSAGE "Opening PowerShell download page..." "INFO" "LAUNCHER"
        start "" "https://github.com/PowerShell/PowerShell/releases/latest"
    )
    
    PAUSE
    EXIT /B 5
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

REM Enhanced debugging - verify all paths and executables exist
CALL :LOG_MESSAGE "Verifying PowerShell executable: %PS_EXECUTABLE%" "DEBUG" "LAUNCHER"
IF NOT EXIST "%PS_EXECUTABLE%" (
    CALL :LOG_MESSAGE "ERROR: PowerShell executable not found at: %PS_EXECUTABLE%" "ERROR" "LAUNCHER"
    CALL :LOG_MESSAGE "Attempting to locate PowerShell..." "INFO" "LAUNCHER"
    WHERE pwsh.exe >nul 2>&1
    IF !ERRORLEVEL! EQU 0 (
        FOR /F "tokens=*" %%i IN ('WHERE pwsh.exe') DO (
            CALL :LOG_MESSAGE "Found pwsh.exe at: %%i" "INFO" "LAUNCHER"
        )
    ) ELSE (
        CALL :LOG_MESSAGE "pwsh.exe not found in PATH" "ERROR" "LAUNCHER"
    )
    GOTO :HANDLE_ERROR
)

CALL :LOG_MESSAGE "Verifying orchestrator script: %ORCHESTRATOR_PATH%" "DEBUG" "LAUNCHER"
IF NOT EXIST "%ORCHESTRATOR_PATH%" (
    CALL :LOG_MESSAGE "ERROR: Orchestrator script not found at: %ORCHESTRATOR_PATH%" "ERROR" "LAUNCHER"
    CALL :LOG_MESSAGE "Current working directory: %CD%" "DEBUG" "LAUNCHER"
    DIR "%SCRIPT_DIR%" | FINDSTR "MaintenanceOrchestrator"
    GOTO :HANDLE_ERROR
)

REM Launch the PowerShell orchestrator with enhanced error capture
CALL :LOG_MESSAGE "Running comprehensive PowerShell diagnostics before execution..." "INFO" "LAUNCHER"
CALL :DIAGNOSE_POWERSHELL

CALL :LOG_MESSAGE "Executing: %PS_EXECUTABLE% -ExecutionPolicy Bypass -File \"%ORCHESTRATOR_PATH%\" %PS_ARGS%" "DEBUG" "LAUNCHER"
CALL :LOG_MESSAGE "Working directory: %SCRIPT_DIR%" "DEBUG" "LAUNCHER"

REM Execute with enhanced output capture and error handling
PUSHD "%SCRIPT_DIR%"

CALL :LOG_MESSAGE "Starting PowerShell execution with timeout monitoring..." "INFO" "LAUNCHER"
START /WAIT /B "" "%PS_EXECUTABLE%" -ExecutionPolicy Bypass -NoProfile -WindowStyle Hidden -File "%ORCHESTRATOR_PATH%" %PS_ARGS% ^> "%TEMP%\ps_output.log" 2^>^&1
SET "ORCHESTRATOR_EXIT_CODE=!ERRORLEVEL!"

REM Display captured output
IF EXIST "%TEMP%\ps_output.log" (
    CALL :LOG_MESSAGE "PowerShell execution output captured:" "DEBUG" "LAUNCHER"
    FOR /F "tokens=*" %%A IN (%TEMP%\ps_output.log) DO (
        CALL :LOG_MESSAGE "PS_OUTPUT: %%A" "DEBUG" "LAUNCHER"
        ECHO %%A
    )
    REM Clean up temp file
    DEL "%TEMP%\ps_output.log" >nul 2>&1
) ELSE (
    CALL :LOG_MESSAGE "No PowerShell output captured - execution may have failed immediately" "WARN" "LAUNCHER"
)

POPD

REM If PowerShell execution failed, try fallback method
IF %ORCHESTRATOR_EXIT_CODE% NEQ 0 (
    CALL :LOG_MESSAGE "Primary PowerShell execution failed with exit code %ORCHESTRATOR_EXIT_CODE%" "ERROR" "LAUNCHER"
    CALL :LOG_MESSAGE "Attempting fallback execution method..." "WARN" "LAUNCHER"
    
    REM Try direct execution without output capture
    PUSHD "%SCRIPT_DIR%"
    "%PS_EXECUTABLE%" -ExecutionPolicy Bypass -NoProfile -File "%ORCHESTRATOR_PATH%" %PS_ARGS%
    SET "FALLBACK_EXIT_CODE=!ERRORLEVEL!"
    POPD
    
    IF !FALLBACK_EXIT_CODE! EQU 0 (
        CALL :LOG_MESSAGE "Fallback execution succeeded" "SUCCESS" "LAUNCHER"
        SET "ORCHESTRATOR_EXIT_CODE=0"
    ) ELSE (
        CALL :LOG_MESSAGE "Fallback execution also failed with exit code !FALLBACK_EXIT_CODE!" "ERROR" "LAUNCHER"
        CALL :LOG_MESSAGE "This indicates a serious PowerShell compatibility or script error" "ERROR" "LAUNCHER"
        
        REM Try with Windows PowerShell 5.1 as last resort
        CALL :LOG_MESSAGE "Attempting last resort with Windows PowerShell 5.1..." "WARN" "LAUNCHER"
        powershell.exe -ExecutionPolicy Bypass -NoProfile -File "%ORCHESTRATOR_PATH%" %PS_ARGS%
        SET "WPS_EXIT_CODE=!ERRORLEVEL!"
        
        IF !WPS_EXIT_CODE! EQU 0 (
            CALL :LOG_MESSAGE "Windows PowerShell 5.1 execution succeeded" "SUCCESS" "LAUNCHER"
            SET "ORCHESTRATOR_EXIT_CODE=0"
        ) ELSE (
            CALL :LOG_MESSAGE "All PowerShell execution methods failed" "ERROR" "LAUNCHER"
            SET "ORCHESTRATOR_EXIT_CODE=!WPS_EXIT_CODE!"
        )
    )
)

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

REM Enhanced post-restart cleanup (based on archived script logic)
IF "%IS_POST_RESTART%"=="YES" (
    CALL :LOG_MESSAGE "Performing comprehensive post-restart cleanup..." "INFO" "LAUNCHER"
    
    REM Remove all possible startup task variations (archived script approach)
    schtasks /delete /tn "Windows Maintenance Post-Restart Startup" /f >nul 2>&1
    schtasks /delete /tn "Windows Maintenance Startup" /f >nul 2>&1
    schtasks /delete /tn "WindowsMaintenanceStartup" /f >nul 2>&1
    schtasks /delete /tn "%STARTUP_TASK_NAME%" /f >nul 2>&1
    
    IF %ERRORLEVEL% EQU 0 (
        CALL :LOG_MESSAGE "Post-restart startup task cleanup completed" "SUCCESS" "LAUNCHER"
    ) ELSE (
        CALL :LOG_MESSAGE "Post-restart cleanup: no startup tasks found" "DEBUG" "LAUNCHER"
    )
) ELSE (
    CALL :LOG_MESSAGE "Normal execution - no post-restart cleanup needed" "DEBUG" "LAUNCHER"
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

REM Enhanced error logging for orchestrator execution
CALL :LOG_MESSAGE "Orchestrator execution completed with exit code: %ORCHESTRATOR_EXIT_CODE%" "INFO" "LAUNCHER"

IF %ORCHESTRATOR_EXIT_CODE% NEQ 0 (
    CALL :LOG_MESSAGE "ERROR: Orchestrator execution failed with exit code %ORCHESTRATOR_EXIT_CODE%" "ERROR" "LAUNCHER"
    CALL :LOG_MESSAGE "This may indicate PowerShell version compatibility issues or missing dependencies" "WARN" "LAUNCHER"
    
    REM Additional debugging for exit codes
    IF %ORCHESTRATOR_EXIT_CODE% EQU 1 (
        CALL :LOG_MESSAGE "Exit code 1: General PowerShell error - check if PowerShell 7 is properly installed" "ERROR" "LAUNCHER"
    ) ELSE IF %ORCHESTRATOR_EXIT_CODE% EQU -1 (
        CALL :LOG_MESSAGE "Exit code -1: PowerShell startup failure - try running compatibility wrapper" "ERROR" "LAUNCHER"
    ) ELSE (
        CALL :LOG_MESSAGE "Unexpected exit code: %ORCHESTRATOR_EXIT_CODE%" "ERROR" "LAUNCHER"
    )
)

GOTO :CLEANUP_AND_EXIT

:HANDLE_ERROR
CALL :LOG_MESSAGE "CRITICAL ERROR: Script execution halted due to missing requirements" "ERROR" "LAUNCHER"
CALL :LOG_MESSAGE "Please check the log file for detailed error information" "ERROR" "LAUNCHER"
CALL :LOG_MESSAGE "Log file location: %SCRIPT_DIR%\launcher-*.log" "INFO" "LAUNCHER"

REM Don't auto-close on error so user can see the problem
ECHO.
ECHO =====================================================
ECHO CRITICAL ERROR - EXECUTION STOPPED
ECHO =====================================================
ECHO Check the log file for details:
ECHO %SCRIPT_DIR%\launcher-*.log
ECHO.
ECHO Press any key to close...
PAUSE >nul
EXIT /B 1

:CLEANUP_AND_EXIT
REM Cleanup temporary scheduled task log files
IF EXIST "%WORKING_DIR%schtasks_create.log" (
    CALL :LOG_MESSAGE "Cleaning up task creation log files" "DEBUG" "LAUNCHER"
    DEL "%WORKING_DIR%schtasks_create.log" >nul 2>&1
)
IF EXIST "%WORKING_DIR%schtasks_create_user.log" (
    DEL "%WORKING_DIR%schtasks_create_user.log" >nul 2>&1
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