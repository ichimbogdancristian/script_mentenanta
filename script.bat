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

    REM -----------------------------------------------------------------------------
    REM PowerShell Orchestrator Launch (Merged logic from archive/script.bat, no menu)
    REM -----------------------------------------------------------------------------
    CALL :LOG_MESSAGE "Preparing to launch PowerShell orchestrator..." "INFO" "LAUNCHER"

    REM Debug: Show what PowerShell executable was detected
    CALL :LOG_MESSAGE "Detected PowerShell executable: %PS_EXECUTABLE%" "DEBUG" "LAUNCHER"

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

    CALL :LOG_MESSAGE "Using PowerShell 7+ for orchestrator execution" "SUCCESS" "LAUNCHER"

    REM Parse command line arguments for the orchestrator
    SET "PS_ARGS="
    IF "%1"=="-NonInteractive" SET "PS_ARGS=%PS_ARGS% -NonInteractive"
    IF "%1"=="-DryRun" SET "PS_ARGS=%PS_ARGS% -DryRun"
    IF "%2"=="-DryRun" SET "PS_ARGS=%PS_ARGS% -DryRun"
    IF "%1"=="-TaskNumbers" SET "PS_ARGS=%PS_ARGS% -TaskNumbers %2"
    IF "%AUTO_NONINTERACTIVE%"=="YES" (
        IF NOT "%1"=="-NonInteractive" (
            SET "PS_ARGS=%PS_ARGS% -NonInteractive"
            CALL :LOG_MESSAGE "Auto-enabling non-interactive mode due to PowerShell 7+ availability" "INFO" "LAUNCHER"
        )
    )

    CALL :LOG_MESSAGE "Launching orchestrator with arguments: %PS_ARGS%" "INFO" "LAUNCHER"

    REM Always launch orchestrator directly (menu logic handled in orchestrator)
    CD /D "%WORKING_DIR%"
    "%PS_EXECUTABLE%" -ExecutionPolicy Bypass -WindowStyle Normal -File "%ORCHESTRATOR_PATH%" %PS_ARGS%
    SET "ORCHESTRATOR_EXIT_CODE=!ERRORLEVEL!"

    REM Log the final result
    IF %ORCHESTRATOR_EXIT_CODE% EQU 0 (
        CALL :LOG_MESSAGE "Orchestrator completed successfully (exit code: %ORCHESTRATOR_EXIT_CODE%)" "SUCCESS" "LAUNCHER"
    ) ELSE (
        CALL :LOG_MESSAGE "Orchestrator completed with errors (exit code: %ORCHESTRATOR_EXIT_CODE%)" "WARN" "LAUNCHER"
    )

    CALL :LOG_MESSAGE "Batch launcher phase completed" "INFO" "LAUNCHER"
    EXIT /B %ORCHESTRATOR_EXIT_CODE%

    REM -----------------------------------------------------------------------------
    REM End of Script
    REM -----------------------------------------------------------------------------
    ENDLOCAL
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
    PAUSE
    EXIT /B 4
) ELSE (
    CALL :LOG_MESSAGE "Repository structure validated successfully - ready for execution" "SUCCESS" "LAUNCHER"
)

REM -----------------------------------------------------------------------------
REM Enhanced Dependency Management
REM -----------------------------------------------------------------------------
:DEPENDENCY_MANAGEMENT
CALL :LOG_MESSAGE "Starting dependency management..." "INFO" "LAUNCHER"

REM -----------------------------------------------------------------------------
REM PowerShell 7+ Installation and Detection (Critical for Orchestrator)
REM -----------------------------------------------------------------------------
CALL :LOG_MESSAGE "Checking PowerShell 7+ availability..." "INFO" "LAUNCHER"

SET "PS7_FOUND=NO"
SET "WINGET_AVAILABLE=NO"
SET "WINGET_EXE="

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
            CALL :LOG_MESSAGE "Chocolatey not available - installing Chocolatey first..." "INFO" "LAUNCHER"
            powershell -NoProfile -ExecutionPolicy Bypass -Command "try { Set-ExecutionPolicy Bypass -Scope Process -Force; [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; iex ((New-Object Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1')); Write-Host 'CHOCO_INSTALLED' } catch { Write-Host 'CHOCO_INSTALL_FAILED'; exit 1 }"
            IF !ERRORLEVEL! EQU 0 (
                CALL :LOG_MESSAGE "Chocolatey installed successfully - now installing PowerShell 7..." "SUCCESS" "LAUNCHER"
                TIMEOUT /T 2 >nul 2>&1
                
                REM Update Chocolatey path after installation
                IF EXIST "%ProgramData%\chocolatey\bin\choco.exe" SET "CHOCO_EXE=%ProgramData%\chocolatey\bin\choco.exe"
                
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
                CALL :LOG_MESSAGE "Chocolatey installation failed - proceeding to MSI fallback" "WARN" "LAUNCHER"
            )
        )
    )

    REM 3) MSI fallback from GitHub Releases (latest stable)
    IF NOT "%INSTALL_STATUS%"=="SUCCESS" (
        CALL :LOG_MESSAGE "Attempting MSI fallback from GitHub Releases (latest stable)..." "INFO" "LAUNCHER"
        DEL /Q "%WORKING_DIR%pwsh.msi" >nul 2>&1
        powershell -NoProfile -ExecutionPolicy Bypass -Command "try { $ProgressPreference='SilentlyContinue'; $headers=@{ 'User-Agent'='WinMaintLauncher' }; $arch = if([Environment]::Is64BitOperatingSystem){ 'x64' } else { 'x86' }; $rel = Invoke-RestMethod -Headers $headers -Uri 'https://api.github.com/repos/PowerShell/PowerShell/releases/latest'; $asset = $rel.assets | Where-Object { $_.name -match ('win-' + $arch + '\\.msi$') } | Select-Object -First 1; if(-not $asset){ Write-Host 'ASSET_NOT_FOUND'; exit 2 }; $url = $asset.browser_download_url; Invoke-WebRequest -Headers $headers -Uri $url -OutFile '%WORKING_DIR%pwsh.msi'; Write-Host 'MSI_DOWNLOADED' } catch { Write-Host 'MSI_DOWNLOAD_FAILED'; exit 1 }" >nul 2>&1
        IF !ERRORLEVEL! EQU 0 (
            CALL :LOG_MESSAGE "PowerShell MSI downloaded. Installing silently..." "INFO" "LAUNCHER"
            msiexec /i "%WORKING_DIR%pwsh.msi" /qn ADD_EXPLORER_CONTEXT_MENU_OPENPOWERSHELL=1 ENABLE_PSREMOTING=1 REGISTER_MANIFEST=1 >nul 2>&1
            IF !ERRORLEVEL! EQU 0 (
                CALL :LOG_MESSAGE "PowerShell 7 installed successfully via MSI" "SUCCESS" "LAUNCHER"
                SET "INSTALL_STATUS=SUCCESS"
                SET "PS7_FOUND=YES"
            ) ELSE (
                CALL :LOG_MESSAGE "MSI installation failed" "ERROR" "LAUNCHER"
            )
        ) ELSE (
            CALL :LOG_MESSAGE "Failed to download PowerShell MSI from GitHub (network or API blocked)" "WARN" "LAUNCHER"
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
    PAUSE
    EXIT /B 1
)

CALL :LOG_MESSAGE "PowerShell 7+ ready for orchestrator execution: %PS_VERSION_STRING%" "SUCCESS" "LAUNCHER"

REM =============================================================================
REM Windows Defender Exclusions (Using PowerShell 7)
REM =============================================================================
CALL :LOG_MESSAGE "Setting up Windows Defender exclusions..." "INFO" "LAUNCHER"
%PS_EXECUTABLE% -ExecutionPolicy Bypass -Command "try { Add-MpPreference -ExclusionPath '%WORKING_DIR%' -ErrorAction SilentlyContinue; Add-MpPreference -ExclusionProcess 'powershell.exe' -ErrorAction SilentlyContinue; Add-MpPreference -ExclusionProcess 'pwsh.exe' -ErrorAction SilentlyContinue; Write-Host 'EXCLUSIONS_ADDED' } catch { Write-Host 'EXCLUSIONS_FAILED' }"

REM =============================================================================
REM Package Manager Verification Summary
REM =============================================================================
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

REM =============================================================================
REM System Restore Point Creation (Using PowerShell 7)
REM =============================================================================
CALL :LOG_MESSAGE "Checking System Protection status..." "INFO" "LAUNCHER"

SET "SYS_DRIVE=%SystemDrive%"
SET "SR_STATUS=UNKNOWN"
SET "SR_VERIFY_STATUS=UNKNOWN"

REM Simple check for System Protection availability
FOR /F "usebackq tokens=* delims=" %%i IN (`%PS_EXECUTABLE% -NoProfile -ExecutionPolicy Bypass -Command "try { $ErrorActionPreference='Stop'; if (Get-Command 'Get-ComputerRestorePoint' -ErrorAction SilentlyContinue) { try { $rp = Get-ComputerRestorePoint -ErrorAction SilentlyContinue; Write-Host 'SR_AVAILABLE' } catch { Write-Host 'SR_ERROR' } } else { Write-Host 'SR_NOT_SUPPORTED' } } catch { Write-Host 'SR_FAILED' }" 2^>nul`) DO SET "SR_CHECK=%%i"

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

CALL :LOG_MESSAGE "Using PowerShell 7+ for orchestrator execution" "SUCCESS" "LAUNCHER"

REM Parse command line arguments for the orchestrator
SET "PS_ARGS_ORCHESTRATOR="
IF "%1"=="-NonInteractive" SET "PS_ARGS_ORCHESTRATOR=-NonInteractive"
IF "%1"=="-DryRun" SET "PS_ARGS_ORCHESTRATOR=-DryRun"
IF "%2"=="-DryRun" SET "PS_ARGS_ORCHESTRATOR=%PS_ARGS_ORCHESTRATOR% -DryRun"
IF "%1"=="-TaskNumbers" SET "PS_ARGS_ORCHESTRATOR=-TaskNumbers %2"

REM Auto-enable non-interactive mode if PowerShell 7+ was detected automatically
IF "%AUTO_NONINTERACTIVE%"=="YES" (
    IF NOT "%1"=="-NonInteractive" (
        SET "PS_ARGS_ORCHESTRATOR=%PS_ARGS_ORCHESTRATOR% -NonInteractive"
        CALL :LOG_MESSAGE "Auto-enabling non-interactive mode due to PowerShell 7+ availability" "INFO" "LAUNCHER"
    )
)

CALL :LOG_MESSAGE "Orchestrator arguments: %PS_ARGS_ORCHESTRATOR%" "DEBUG" "LAUNCHER"

REM Critical: Use PowerShell 7+ (pwsh.exe) for MaintenanceOrchestrator.ps1 due to #Requires directive
CALL :LOG_MESSAGE "Launching PowerShell 7+ orchestrator..." "SUCCESS" "LAUNCHER"

REM Choose execution method based on arguments
IF "%1"=="-NonInteractive" (
    REM Direct execution for non-interactive mode (preserves admin privileges)
    CALL :LOG_MESSAGE "Executing in non-interactive mode with preserved admin privileges..." "INFO" "LAUNCHER"
    CD /D "%WORKING_DIR%"
    "%PS_EXECUTABLE%" -ExecutionPolicy Bypass -WindowStyle Normal -File "%ORCHESTRATOR_PATH%" %PS_ARGS_ORCHESTRATOR%
    SET "ORCHESTRATOR_EXIT_CODE=!ERRORLEVEL!"
) ELSE (
    REM Interactive mode with enhanced PowerShell window
    CALL :LOG_MESSAGE "Launching interactive PowerShell 7+ window for optimal experience..." "INFO" "LAUNCHER"
    
    REM Prepare arguments for the new PowerShell window
    SET "PS_ARGS=-ExecutionPolicy Bypass -NoExit -Command ""Set-Location '%WORKING_DIR%'; Write-Host '🚀 Windows Maintenance Automation - PowerShell 7+ Mode' -ForegroundColor Green; Write-Host '📁 Working Directory: %WORKING_DIR%' -ForegroundColor Cyan; Write-Host '🔧 Launching MaintenanceOrchestrator...' -ForegroundColor Yellow; Write-Host ''; $exitCode = 0; try { ^& '%ORCHESTRATOR_PATH%' %PS_ARGS_ORCHESTRATOR%; $exitCode = $LASTEXITCODE } catch { $exitCode = 1 }; Write-Host ''; if($exitCode -eq 0){ Write-Host '✅ Maintenance session completed successfully.' -ForegroundColor Green } else { Write-Host '⚠️ Maintenance session completed with errors (exit code: $exitCode)' -ForegroundColor Yellow }; Write-Host 'You can close this window or run additional commands.' -ForegroundColor Cyan; exit $exitCode"""
    
    REM Launch new PowerShell 7 window preserving Administrator privileges
    "%PS_EXECUTABLE%" !PS_ARGS!
    SET "ORCHESTRATOR_EXIT_CODE=!ERRORLEVEL!"
)

REM Log the final result
IF %ORCHESTRATOR_EXIT_CODE% EQU 0 (
    CALL :LOG_MESSAGE "Orchestrator completed successfully (exit code: %ORCHESTRATOR_EXIT_CODE%)" "SUCCESS" "LAUNCHER"
) ELSE (
    CALL :LOG_MESSAGE "Orchestrator completed with errors (exit code: %ORCHESTRATOR_EXIT_CODE%)" "WARN" "LAUNCHER"
)

CALL :LOG_MESSAGE "Batch launcher phase completed" "INFO" "LAUNCHER"
EXIT /B %ORCHESTRATOR_EXIT_CODE%

REM -----------------------------------------------------------------------------
REM End of Script
REM -----------------------------------------------------------------------------
ENDLOCAL