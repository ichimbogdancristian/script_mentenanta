@echo off
REM ============================================================================
REM  Windows Maintenance Automation Launcher v3.0 (Restructured Flow)
REM  Purpose: Universal launcher for modular Windows maintenance system
REM  Flow: Logging → Admin Check → Scheduled Tasks → Restart Handling → Dependencies → Orchestrator
REM  Requirements: Windows 10/11, Administrator privileges
REM  Author: Windows Maintenance Automation Project
REM ============================================================================

SETLOCAL ENABLEDELAYEDEXPANSION

REM -----------------------------------------------------------------------------
REM Step 1: Initialize Logging System (First Priority)
REM -----------------------------------------------------------------------------
REM Set up paths first
SET "SCRIPT_PATH=%~f0"
SET "SCRIPT_DIR=%~dp0"
SET "SCRIPT_NAME=%~nx0"
REM Ensure SCRIPT_DIR ends with backslash
IF NOT "%SCRIPT_DIR:~-1%"=="\" SET "SCRIPT_DIR=%SCRIPT_DIR%\"
SET "WORKING_DIR=%SCRIPT_DIR%"
SET "LOG_FILE=%WORKING_DIR%maintenance.log"

REM Create maintenance.log if it doesn't exist
IF NOT EXIST "%LOG_FILE%" (
    ECHO. > "%LOG_FILE%" 2>nul
    IF !ERRORLEVEL! EQU 0 (
        ECHO [%DATE% %TIME%] [INFO] [LAUNCHER] Created maintenance.log in script directory
        ECHO [%DATE% %TIME%] [INFO] [LAUNCHER] Created maintenance.log in script directory >> "%LOG_FILE%" 2>nul
    ) ELSE (
        ECHO [%DATE% %TIME%] [ERROR] [LAUNCHER] Failed to create maintenance.log
    )
) ELSE (
    ECHO [%DATE% %TIME%] [INFO] [LAUNCHER] Found existing maintenance.log, continuing...
    ECHO [%DATE% %TIME%] [INFO] [LAUNCHER] Found existing maintenance.log, continuing... >> "%LOG_FILE%" 2>nul
)

GOTO :MAIN_SCRIPT

REM -----------------------------------------------------------------------------
REM Logging Function
REM -----------------------------------------------------------------------------
:LOG_MESSAGE
SET "LOG_TIMESTAMP=%TIME:~0,8%"
SET "LEVEL=%~2"
IF "%LEVEL%"=="" SET "LEVEL=INFO"
SET "COMPONENT=%~3"
IF "%COMPONENT%"=="" SET "COMPONENT=LAUNCHER"

SET "LOG_ENTRY=[%DATE% %LOG_TIMESTAMP%] [%LEVEL%] [%COMPONENT%] %~1"

ECHO %LOG_ENTRY%
ECHO %LOG_ENTRY% >> "%LOG_FILE%" 2>nul
EXIT /B

REM -----------------------------------------------------------------------------
REM Helper Functions
REM -----------------------------------------------------------------------------
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

:HANDLE_ERROR
CALL :LOG_MESSAGE "CRITICAL ERROR: Script execution halted" "ERROR" "LAUNCHER"
CALL :LOG_MESSAGE "Please check the log file: %LOG_FILE%" "ERROR" "LAUNCHER"
ECHO.
ECHO =====================================================
ECHO CRITICAL ERROR - EXECUTION STOPPED
ECHO =====================================================
ECHO Check the log file for details: %LOG_FILE%
ECHO.
ECHO Press any key to close...
PAUSE >nul
EXIT /B 1

REM -----------------------------------------------------------------------------
REM Main Script Execution
REM -----------------------------------------------------------------------------
:MAIN_SCRIPT
CALL :LOG_MESSAGE "Starting Windows Maintenance Automation Launcher v3.0" "INFO" "LAUNCHER"
CALL :LOG_MESSAGE "Environment: %USERNAME%@%COMPUTERNAME%" "INFO" "LAUNCHER"
CALL :LOG_MESSAGE "Script location: %SCRIPT_PATH%" "INFO" "LAUNCHER"

REM Check if this is a post-restart execution
IF "%1"=="POST_RESTART" (
    CALL :LOG_MESSAGE "Post-restart execution detected - cleaning up startup task" "INFO" "LAUNCHER"
    schtasks /delete /tn "ScriptMentenantaStartup" /f >nul 2>&1
    IF !ERRORLEVEL! EQU 0 (
        CALL :LOG_MESSAGE "Startup task removed successfully after restart" "SUCCESS" "LAUNCHER"
    ) ELSE (
        CALL :LOG_MESSAGE "Failed to remove startup task (may not exist)" "WARN" "LAUNCHER"
    )
    CALL :LOG_MESSAGE "Continuing maintenance execution after system restart" "INFO" "LAUNCHER"
)

REM -----------------------------------------------------------------------------
REM Step 2: Administrator Privilege Check (Second Priority)
REM -----------------------------------------------------------------------------
CALL :LOG_MESSAGE "Checking administrator privileges..." "INFO" "LAUNCHER"

REM Check for elevation marker to prevent infinite loops
FOR %%i in (%*) DO (
    IF "%%i"=="ELEVATED_INSTANCE" (
        CALL :LOG_MESSAGE "Running as elevated instance" "INFO" "LAUNCHER"
        GOTO :CONTINUE_EXECUTION
    )
)

REM Test admin rights using NET SESSION
NET SESSION >nul 2>&1
IF %ERRORLEVEL% NEQ 0 (
    CALL :LOG_MESSAGE "No administrator privileges detected - relaunching with elevation" "WARN" "LAUNCHER"
    ECHO.
    ECHO ================================================================================
    ECHO  ADMINISTRATOR PRIVILEGES REQUIRED
    ECHO ================================================================================
    ECHO  This script requires administrator privileges. Relaunching with elevation...
    ECHO  Please accept the UAC prompt when it appears.
    ECHO ================================================================================
    ECHO.
    
    REM Relaunch with admin rights
    powershell -NoProfile -Command "Start-Process cmd -ArgumentList '/c \"%SCRIPT_PATH%\" ELEVATED_INSTANCE' -Verb RunAs"
    IF !ERRORLEVEL! NEQ 0 (
        CALL :LOG_MESSAGE "Elevation failed or was cancelled by user" "ERROR" "LAUNCHER"
        ECHO ERROR: Failed to elevate privileges. Please run as Administrator or accept the UAC prompt.
        PAUSE
        EXIT /B 1
    )
    
    REM Exit current non-elevated instance
    CALL :LOG_MESSAGE "Elevation initiated - terminating current instance" "INFO" "LAUNCHER"
    EXIT /B 0
) ELSE (
    CALL :LOG_MESSAGE "Administrator privileges confirmed" "SUCCESS" "LAUNCHER"
)

:CONTINUE_EXECUTION

REM -----------------------------------------------------------------------------
REM Step 3: Scheduled Task Management (Third Priority)
REM -----------------------------------------------------------------------------
CALL :LOG_MESSAGE "Managing scheduled tasks..." "INFO" "LAUNCHER"

REM Define task names
SET "STARTUP_TASK_NAME=ScriptMentenantaStartup"
SET "MONTHLY_TASK_NAME=ScriptMentenantaMonthly"

REM Always check for and remove existing startup task first (clean slate approach)
CALL :LOG_MESSAGE "Checking for existing startup task..." "INFO" "LAUNCHER"
schtasks /query /tn "!STARTUP_TASK_NAME!" >nul 2>&1
IF !ERRORLEVEL! EQU 0 (
    CALL :LOG_MESSAGE "Found existing startup task - removing for clean slate" "INFO" "LAUNCHER"
    schtasks /delete /tn "!STARTUP_TASK_NAME!" /f >nul 2>&1
    IF !ERRORLEVEL! EQU 0 (
        CALL :LOG_MESSAGE "Successfully removed existing startup task" "SUCCESS" "LAUNCHER"
    ) ELSE (
        CALL :LOG_MESSAGE "Failed to remove existing startup task" "WARN" "LAUNCHER"
    )
) ELSE (
    CALL :LOG_MESSAGE "No existing startup task found" "INFO" "LAUNCHER"
)

REM -----------------------------------------------------------------------------
REM Step 4: Check for Pending Restarts (Fourth Priority)
REM -----------------------------------------------------------------------------
CALL :LOG_MESSAGE "Checking for pending restarts..." "INFO" "LAUNCHER"

REM Check multiple registry locations for pending restarts
SET "PENDING_RESTART=NO"

REM Check for Windows Update restarts
REG QUERY "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired" >nul 2>&1
IF !ERRORLEVEL! EQU 0 SET "PENDING_RESTART=YES"

REM Check for Component Based Servicing restarts
REG QUERY "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending" >nul 2>&1
IF !ERRORLEVEL! EQU 0 SET "PENDING_RESTART=YES"

REM Check for Session Manager restarts (PendingFileRenameOperations)
REG QUERY "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager" /v PendingFileRenameOperations >nul 2>&1
IF !ERRORLEVEL! EQU 0 SET "PENDING_RESTART=YES"

IF "%PENDING_RESTART%"=="YES" (
    CALL :LOG_MESSAGE "Pending restart detected - creating startup task and restarting system" "WARN" "LAUNCHER"
    
    REM Create startup task to continue after restart (using original working approach)
    CALL :LOG_MESSAGE "Creating startup task to continue maintenance after restart..." "INFO" "LAUNCHER"
    CALL :LOG_MESSAGE "Creating startup task with script path: !SCRIPT_PATH!" "DEBUG" "LAUNCHER"
    schtasks /create /tn "!STARTUP_TASK_NAME!" /tr "'!SCRIPT_PATH!' POST_RESTART" /sc ONLOGON /ru "!COMPUTERNAME!\!USERNAME!" /rl HIGHEST /delay 0001:00 /f
    IF !ERRORLEVEL! EQU 0 (
        CALL :LOG_MESSAGE "Startup task created successfully" "SUCCESS" "LAUNCHER"
        
        ECHO.
        ECHO ================================================================================
        ECHO  SYSTEM RESTART REQUIRED
        ECHO ================================================================================
        ECHO  Pending updates require a system restart.
        ECHO  A startup task has been created to continue maintenance after restart.
        ECHO  The system will restart in 30 seconds...
        ECHO  Press Ctrl+C to cancel if needed.
        ECHO ================================================================================
        ECHO.
        
        REM Schedule restart in 30 seconds
        shutdown /r /t 30 /c "Windows Maintenance: Restarting to complete updates. Maintenance will continue after restart."
        CALL :LOG_MESSAGE "System restart scheduled - exiting launcher" "INFO" "LAUNCHER"
        EXIT /B 0
    ) ELSE (
        CALL :LOG_MESSAGE "Failed to create startup task - continuing without restart" "ERROR" "LAUNCHER"
    )
) ELSE (
    CALL :LOG_MESSAGE "No pending restarts detected - continuing with normal execution" "INFO" "LAUNCHER"
)

REM -----------------------------------------------------------------------------
REM Create Monthly Maintenance Scheduled Task
REM -----------------------------------------------------------------------------
CALL :LOG_MESSAGE "Setting up monthly maintenance scheduled task..." "INFO" "LAUNCHER"
schtasks /query /tn "!MONTHLY_TASK_NAME!" >nul 2>&1
IF !ERRORLEVEL! EQU 0 (
    CALL :LOG_MESSAGE "Monthly task already exists - updating it" "INFO" "LAUNCHER"
    schtasks /delete /tn "!MONTHLY_TASK_NAME!" /f >nul 2>&1
)

REM Create monthly task for first day of month at 1AM
SET "MONTHLY_WRAPPER=!SCRIPT_DIR!startup-wrapper.bat"
schtasks /create /tn "!MONTHLY_TASK_NAME!" /tr "\"!MONTHLY_WRAPPER!\"" /sc MONTHLY /d 1 /st 01:00 /ru "SYSTEM" /rl HIGHEST /f >nul 2>&1
IF !ERRORLEVEL! EQU 0 (
    CALL :LOG_MESSAGE "Monthly maintenance task created successfully (1st of month at 1AM)" "SUCCESS" "LAUNCHER"
) ELSE (
    CALL :LOG_MESSAGE "Failed to create monthly maintenance task" "WARN" "LAUNCHER"
)

REM -----------------------------------------------------------------------------
REM Step 5: Dependency Installation (Using cmd/PowerShell 5 syntax until PS7 available)
REM -----------------------------------------------------------------------------
CALL :LOG_MESSAGE "Starting dependency installation phase..." "INFO" "LAUNCHER"

REM Temp directory creation is handled by the PowerShell orchestrator (MaintenanceOrchestrator.ps1)
REM Do NOT create `temp_files` here to avoid race conditions; the orchestrator will create and manage the folder.

REM -----------------------------------------------------------------------------
REM 5.1: Install Windows Package Manager (winget) - First Priority Dependency
REM -----------------------------------------------------------------------------
CALL :LOG_MESSAGE "Checking Windows Package Manager (winget)..." "INFO" "LAUNCHER"

winget --version >nul 2>&1
IF !ERRORLEVEL! EQU 0 (
    FOR /F "tokens=*" %%i IN ('winget --version 2^>nul') DO SET WINGET_VERSION=%%i
    CALL :LOG_MESSAGE "Winget already available: !WINGET_VERSION!" "SUCCESS" "LAUNCHER"
) ELSE (
    CALL :LOG_MESSAGE "Winget not found - installing using multiple methods..." "INFO" "LAUNCHER"
    
    REM Try modern PowerShell method first (recommended by Microsoft)
    CALL :LOG_MESSAGE "Attempting Microsoft.WinGet.Client PowerShell module installation..." "INFO" "LAUNCHER"
    powershell -ExecutionPolicy Bypass -Command "try { Install-PackageProvider -Name NuGet -Force -Scope CurrentUser | Out-Null; Install-Module -Name Microsoft.WinGet.Client -Force -Repository PSGallery -Scope CurrentUser | Out-Null; Repair-WinGetPackageManager -AllUsers -ErrorAction Stop; Write-Host 'PS_MODULE_SUCCESS' } catch { Write-Host 'PS_MODULE_FAILED'; Write-Error $_.Exception.Message }"
    
    IF !ERRORLEVEL! EQU 0 (
        CALL :LOG_MESSAGE "WinGet installed via PowerShell module successfully" "SUCCESS" "LAUNCHER"
        REM Refresh PATH and verify installation
        CALL :REFRESH_PATH
        winget --version >nul 2>&1
        IF !ERRORLEVEL! EQU 0 (
            FOR /F "tokens=*" %%i IN ('winget --version 2^>nul') DO CALL :LOG_MESSAGE "WinGet confirmed: %%i" "SUCCESS" "LAUNCHER"
        ) ELSE (
            CALL :LOG_MESSAGE "WinGet installation verification failed" "WARN" "LAUNCHER"
        )
    ) ELSE (
        CALL :LOG_MESSAGE "PowerShell module method failed, trying direct download..." "WARN" "LAUNCHER"
        
        REM Fallback to direct MSIX bundle download
        SET "WINGET_URL=https://aka.ms/getwingetpreview"
        SET "WINGET_FILE=%TEMP%\Microsoft.DesktopAppInstaller.msixbundle"
        
        powershell -ExecutionPolicy Bypass -Command "try { $ProgressPreference = 'SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri '!WINGET_URL!' -OutFile '!WINGET_FILE!' -UseBasicParsing; Write-Host 'DOWNLOAD_SUCCESS' } catch { Write-Host 'DOWNLOAD_FAILED'; Write-Error $_.Exception.Message }"
        
        IF !ERRORLEVEL! EQU 0 (
            CALL :LOG_MESSAGE "Installing winget package..." "INFO" "LAUNCHER"
            powershell -ExecutionPolicy Bypass -Command "try { Add-AppxPackage -Path '%WINGET_FILE%' -ErrorAction Stop; Write-Host 'INSTALL_SUCCESS' } catch { Write-Host 'INSTALL_FAILED'; Write-Error $_.Exception.Message }"
            
            IF !ERRORLEVEL! EQU 0 (
                CALL :LOG_MESSAGE "Winget installed successfully" "SUCCESS" "LAUNCHER"
                REM Refresh PATH and verify installation
                CALL :REFRESH_PATH
                winget --version >nul 2>&1
                IF !ERRORLEVEL! EQU 0 (
                    FOR /F "tokens=*" %%i IN ('winget --version 2^>nul') DO CALL :LOG_MESSAGE "Winget confirmed: %%i" "SUCCESS" "LAUNCHER"
                ) ELSE (
                    CALL :LOG_MESSAGE "Winget installation verification failed" "WARN" "LAUNCHER"
                )
            ) ELSE (
                CALL :LOG_MESSAGE "Winget installation failed" "ERROR" "LAUNCHER"
            )
            
            REM Cleanup
            DEL /F /Q "%WINGET_FILE%" >nul 2>&1
        ) ELSE (
            CALL :LOG_MESSAGE "Failed to download winget" "ERROR" "LAUNCHER"
        )
    )
)

REM -----------------------------------------------------------------------------
REM 5.2: Install PowerShell 7 (pwsh v7.5.3) - Second Priority Dependency  
REM -----------------------------------------------------------------------------
CALL :LOG_MESSAGE "Checking PowerShell 7..." "INFO" "LAUNCHER"

pwsh.exe -Version >nul 2>&1
IF !ERRORLEVEL! EQU 0 (
    FOR /F "tokens=*" %%i IN ('pwsh.exe -Command "$PSVersionTable.PSVersion.ToString()" 2^>nul') DO SET PS7_VERSION=%%i
    CALL :LOG_MESSAGE "PowerShell 7 already available: !PS7_VERSION!" "SUCCESS" "LAUNCHER"
) ELSE (
    CALL :LOG_MESSAGE "PowerShell 7 not found - downloading and installing v7.5.3..." "INFO" "LAUNCHER"
    
    REM Set architecture-specific download URL
    IF "%PROCESSOR_ARCHITECTURE%"=="AMD64" (
        SET "PS7_URL=https://github.com/PowerShell/PowerShell/releases/download/v7.5.3/PowerShell-7.5.3-win-x64.msi"
    ) ELSE (
        SET "PS7_URL=https://github.com/PowerShell/PowerShell/releases/download/v7.5.3/PowerShell-7.5.3-win-x86.msi"
    )
    SET "PS7_INSTALLER=%TEMP%\PowerShell-7.5.3.msi"
    
    REM Download PowerShell 7.5.3
    CALL :LOG_MESSAGE "Downloading PowerShell 7.5.3..." "INFO" "LAUNCHER"
    powershell -ExecutionPolicy Bypass -Command "try { $ProgressPreference = 'SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri '!PS7_URL!' -OutFile '!PS7_INSTALLER!' -UseBasicParsing; Write-Host 'DOWNLOAD_SUCCESS' } catch { Write-Host 'DOWNLOAD_FAILED'; Write-Error $_.Exception.Message }"
    
    IF !ERRORLEVEL! EQU 0 (
        CALL :LOG_MESSAGE "Installing PowerShell 7..." "INFO" "LAUNCHER"
        msiexec /i "%PS7_INSTALLER%" /quiet /norestart
        IF !ERRORLEVEL! EQU 0 (
            CALL :LOG_MESSAGE "PowerShell 7 installed successfully" "SUCCESS" "LAUNCHER"
            REM Refresh PATH and verify installation
            CALL :REFRESH_PATH
            pwsh.exe -Version >nul 2>&1
            IF !ERRORLEVEL! EQU 0 (
                FOR /F "tokens=*" %%i IN ('pwsh.exe -Command "$PSVersionTable.PSVersion.ToString()" 2^>nul') DO CALL :LOG_MESSAGE "PowerShell 7 confirmed: %%i" "SUCCESS" "LAUNCHER"
            ) ELSE (
                CALL :LOG_MESSAGE "PowerShell 7 installation verification failed" "WARN" "LAUNCHER"
            )
        ) ELSE (
            CALL :LOG_MESSAGE "PowerShell 7 installation failed" "ERROR" "LAUNCHER"
        )
        
        REM Cleanup
        DEL /F /Q "%PS7_INSTALLER%" >nul 2>&1
    ) ELSE (
        CALL :LOG_MESSAGE "Failed to download PowerShell 7" "ERROR" "LAUNCHER"
    )
)

REM -----------------------------------------------------------------------------
REM Step 6: PowerShell 7 Dependencies (Now PS7 should be available)
REM -----------------------------------------------------------------------------
CALL :LOG_MESSAGE "Installing PowerShell 7 dependencies..." "INFO" "LAUNCHER"

REM Verify PowerShell 7 is available before proceeding
pwsh.exe -Version >nul 2>&1
IF !ERRORLEVEL! NEQ 0 (
    CALL :LOG_MESSAGE "ERROR: PowerShell 7 not available - cannot install PS modules" "ERROR" "LAUNCHER"
    CALL :LOG_MESSAGE "Continuing with PowerShell 5.1 fallback..." "WARN" "LAUNCHER"
    SET "PS_EXECUTABLE=powershell.exe"
) ELSE (
    CALL :LOG_MESSAGE "PowerShell 7 confirmed - using pwsh for module installation" "SUCCESS" "LAUNCHER"
    SET "PS_EXECUTABLE=pwsh.exe"
)

REM -----------------------------------------------------------------------------
REM 6.1: Install NuGet PackageProvider (Auto-confirm with Y)
REM -----------------------------------------------------------------------------
CALL :LOG_MESSAGE "Installing NuGet PackageProvider..." "INFO" "LAUNCHER"
ECHO Y | %PS_EXECUTABLE% -ExecutionPolicy Bypass -Command "try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) { Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope AllUsers -Confirm:$false; Write-Host 'NUGET_INSTALLED' } else { Write-Host 'NUGET_EXISTS' } } catch { Write-Host 'NUGET_FAILED'; Write-Error $_.Exception.Message }"

IF !ERRORLEVEL! EQU 0 (
    CALL :LOG_MESSAGE "NuGet PackageProvider configured successfully" "SUCCESS" "LAUNCHER"
) ELSE (
    CALL :LOG_MESSAGE "NuGet PackageProvider installation failed" "WARN" "LAUNCHER"
)

REM -----------------------------------------------------------------------------
REM 6.2: Configure PSGallery as trusted repository
REM -----------------------------------------------------------------------------
CALL :LOG_MESSAGE "Configuring PSGallery as trusted repository..." "INFO" "LAUNCHER"
%PS_EXECUTABLE% -ExecutionPolicy Bypass -Command "try { Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted -ErrorAction Stop; Write-Host 'PSGALLERY_TRUSTED' } catch { Write-Host 'PSGALLERY_FAILED'; Write-Error $_.Exception.Message }"

IF !ERRORLEVEL! EQU 0 (
    CALL :LOG_MESSAGE "PSGallery configured as trusted successfully" "SUCCESS" "LAUNCHER"
) ELSE (
    CALL :LOG_MESSAGE "PSGallery configuration failed" "WARN" "LAUNCHER"
)

REM -----------------------------------------------------------------------------
REM 6.3: Install PSWindowsUpdate PowerShell module
REM -----------------------------------------------------------------------------
CALL :LOG_MESSAGE "Installing PSWindowsUpdate module..." "INFO" "LAUNCHER"
%PS_EXECUTABLE% -ExecutionPolicy Bypass -Command "try { if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) { Install-Module -Name PSWindowsUpdate -Force -Scope AllUsers -AllowClobber -Repository PSGallery -Confirm:$false; Write-Host 'PSWINDOWSUPDATE_INSTALLED' } else { Write-Host 'PSWINDOWSUPDATE_EXISTS' } } catch { Write-Host 'PSWINDOWSUPDATE_FAILED'; Write-Error $_.Exception.Message }"

IF !ERRORLEVEL! EQU 0 (
    CALL :LOG_MESSAGE "PSWindowsUpdate module configured successfully" "SUCCESS" "LAUNCHER"
) ELSE (
    CALL :LOG_MESSAGE "PSWindowsUpdate module installation failed" "WARN" "LAUNCHER"
)

REM -----------------------------------------------------------------------------
REM Step 7: Launch PowerShell Orchestrator with Admin Rights
REM -----------------------------------------------------------------------------
CALL :LOG_MESSAGE "All dependencies installed - launching PowerShell orchestrator..." "INFO" "LAUNCHER"

REM Set environment variables for orchestrator
SET "WORKING_DIRECTORY=%WORKING_DIR%"
SET "SCRIPT_LOG_FILE=%LOG_FILE%"

REM Check for orchestrator file
SET "ORCHESTRATOR_PATH=%WORKING_DIR%MaintenanceOrchestrator.ps1"
IF NOT EXIST "%ORCHESTRATOR_PATH%" (
    SET "ORCHESTRATOR_PATH=%WORKING_DIR%script.ps1"
    IF NOT EXIST "%ORCHESTRATOR_PATH%" (
        CALL :LOG_MESSAGE "ERROR: No PowerShell orchestrator found" "ERROR" "LAUNCHER"
        CALL :LOG_MESSAGE "Expected: %WORKING_DIR%MaintenanceOrchestrator.ps1 or %WORKING_DIR%script.ps1" "ERROR" "LAUNCHER"
        GOTO :HANDLE_ERROR
    )
)

CALL :LOG_MESSAGE "Launching orchestrator: %ORCHESTRATOR_PATH%" "INFO" "LAUNCHER"
CALL :LOG_MESSAGE "Using PowerShell executable: %PS_EXECUTABLE%" "INFO" "LAUNCHER"

REM Launch orchestrator with admin rights using preferred PowerShell version
%PS_EXECUTABLE% -ExecutionPolicy Bypass -File "%ORCHESTRATOR_PATH%"
SET "ORCHESTRATOR_EXIT_CODE=%ERRORLEVEL%"

REM -----------------------------------------------------------------------------
REM Post-Execution Reporting and Cleanup
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

GOTO :CLEANUP_AND_EXIT

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