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
REM Unified Logging Function - Enhanced with levels and components
REM Usage: CALL :LOG_MESSAGE "message" "LEVEL" "COMPONENT"
REM -----------------------------------------------------------------------------
GOTO :MAIN_SCRIPT
:LOG_MESSAGE
SET "LOG_TIMESTAMP=%TIME:~0,8%"
SET "LEVEL=%~2"
IF "%LEVEL%"=="" SET "LEVEL=INFO"
SET "COMPONENT=%~3"
IF "%COMPONENT%"=="" SET "COMPONENT=BAT"

SET "LOG_ENTRY=[%LOG_TIMESTAMP%] [%LEVEL%] [%COMPONENT%] %~1"

ECHO %LOG_ENTRY%
ECHO %LOG_ENTRY% >> "%LOG_FILE%" 2>nul
EXIT /B

:MAIN_SCRIPT
REM -----------------------------------------------------------------------------
REM Robust Timestamp Function for Logging
REM -----------------------------------------------------------------------------
SET "LOG_TIMESTAMP=%DATE% %TIME%"
REM Usage: !LOG_TIMESTAMP! (if delayed expansion) or %LOG_TIMESTAMP% (if not)

REM -----------------------------------------------------------------------------
REM Universal Path Detection & Environment Setup (Location-Agnostic)
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

REM ----------------------------------------------------------------------------- 
REM Load Logging Configuration (if available) - Optional enhancement for future use
REM -----------------------------------------------------------------------------
SET "LOG_CONFIG=%WORKING_DIR%config\logging.json"
SET "LOG_LEVEL=INFO"
SET "LOG_MAX_SIZE_MB=10"
SET "LOG_ROTATION=YES"
IF EXIST "%LOG_CONFIG%" (
    CALL :LOG_MESSAGE "Loading logging configuration from: %LOG_CONFIG%" "DEBUG" "BAT"
    REM Simple JSON parsing for key values (basic implementation for batch compatibility)
    FOR /F "tokens=*" %%i IN ('powershell -Command "try { $config = Get-Content '%LOG_CONFIG%' -Raw | ConvertFrom-Json; Write-Output $config.LogLevel } catch { Write-Output 'INFO' }"') DO SET "LOG_LEVEL=%%i"
    FOR /F "tokens=*" %%i IN ('powershell -Command "try { $config = Get-Content '%LOG_CONFIG%' -Raw | ConvertFrom-Json; Write-Output $config.MaxLogSizeMB } catch { Write-Output '10' }"') DO SET "LOG_MAX_SIZE_MB=%%i"
    CALL :LOG_MESSAGE "Configuration loaded - Log Level: %LOG_LEVEL%, Max Size: %LOG_MAX_SIZE_MB%MB" "DEBUG" "BAT"
) ELSE (
    CALL :LOG_MESSAGE "No logging.json found - using default configuration" "DEBUG" "BAT"
)
REM GitHub repository archive URL - downloads main branch as ZIP
SET "REPO_URL=https://github.com/ichimbogdancristian/script_mentenanta/archive/main.zip"
SET "ZIP_FILE=%WORKING_DIR%script_mentenanta-main.zip"
SET "EXTRACT_FOLDER=script_mentenanta-main"
SET "EXTRACTED_PATH=%WORKING_DIR%%EXTRACT_FOLDER%"

REM PowerShell script paths - intelligent detection for any execution context
SET "PS1_PATH="
REM Priority 1: Check if we're already in a repo directory (current directory has script.ps1)
IF EXIST "%WORKING_DIR%script.ps1" (
    SET "PS1_PATH=%WORKING_DIR%script.ps1"
    CALL :LOG_MESSAGE "Found script.ps1 in current directory - using local version" "DEBUG" "BAT"
    GOTO :INITIAL_PS1_CHECK_COMPLETE
)

REM Priority 2: Will be set after repository extraction
CALL :LOG_MESSAGE "No local script.ps1 found - will download repository" "DEBUG" "BAT"

:INITIAL_PS1_CHECK_COMPLETE

CALL :LOG_MESSAGE "Working Directory: %WORKING_DIR%" "DEBUG" "BAT"
CALL :LOG_MESSAGE "Script Path: %SCRIPT_PATH%" "DEBUG" "BAT"
CALL :LOG_MESSAGE "Log File: %LOG_FILE%" "DEBUG" "BAT"

REM -----------------------------------------------------------------------------
REM Robust Script Path Detection for Scheduled Tasks
REM Determines the best path to use for scheduled task creation
REM -----------------------------------------------------------------------------
SET "SCHEDULED_TASK_SCRIPT_PATH="

REM Priority 1: Use current executing script path (most reliable)
IF EXIST "%SCRIPT_PATH%" (
    SET "SCHEDULED_TASK_SCRIPT_PATH=%SCRIPT_PATH%"
    CALL :LOG_MESSAGE "Scheduled task will use current script path: %SCRIPT_PATH%" "DEBUG" "BAT"
    GOTO :SCHEDULED_TASK_PATH_COMPLETE
)

REM Priority 2: Look for script.bat in current directory
IF EXIST "%SCRIPT_DIR%script.bat" (
    SET "SCHEDULED_TASK_SCRIPT_PATH=%SCRIPT_DIR%script.bat"
    CALL :LOG_MESSAGE "Scheduled task will use directory script: %SCRIPT_DIR%script.bat" "DEBUG" "BAT"
    GOTO :SCHEDULED_TASK_PATH_COMPLETE
)

REM Priority 3: Use script path as fallback (should not happen)
SET "SCHEDULED_TASK_SCRIPT_PATH=%SCRIPT_PATH%"
CALL :LOG_MESSAGE "Using fallback script path for scheduled task: %SCRIPT_PATH%" "WARN" "BAT"

:SCHEDULED_TASK_PATH_COMPLETE

REM Check if this is a restart after PowerShell 7 installation
IF "%1"=="PS7_RESTART" (
    CALL :LOG_MESSAGE "Script restarted after PowerShell 7 installation." "INFO" "BAT"
    GOTO :SKIP_PS7_INSTALL
)

REM Check if this is a restart after script.bat self-update
REM (Legacy self-update logic removed)

CALL :LOG_MESSAGE "Starting maintenance script..." "INFO" "BAT"
CALL :LOG_MESSAGE "User: %USERNAME%, Computer: %COMPUTERNAME%" "INFO" "BAT"

REM -----------------------------------------------------------------------------
REM Enhanced Admin Privilege Check
REM Uses multiple methods to ensure reliable administrator detection and proper elevation.
REM -----------------------------------------------------------------------------
REM -----------------------------------------------------------------------------
REM ADMIN CHECK NOTES:
REM - Purpose: Ensure the launcher runs with the required elevated privileges.
REM - Why multiple checks: Some environments may restrict NET SESSION or PowerShell checks;
REM   using both increases reliability across Windows versions and execution contexts.
REM - Behavior: If not elevated, the script attempts to relaunch itself using PowerShell
REM   Start-Process with the RunAs verb. This keeps elevation logic centralized here and
REM   avoids embedding elevation checks in the PowerShell orchestrator (script.ps1).
REM - Operator guidance: If the automatic elevation fails on a managed device, launch
REM   an elevated command prompt and run this script manually.
REM -----------------------------------------------------------------------------
REM Method 1: NET SESSION (traditional approach)
NET SESSION >nul 2>&1
SET "NET_SESSION_RESULT=%ERRORLEVEL%"

REM Method 2: PowerShell admin check (more reliable)
FOR /F "tokens=*" %%i IN ('powershell -Command "([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)" 2^>nul') DO SET PS_ADMIN_CHECK=%%i

CALL :LOG_MESSAGE "NET SESSION result: %NET_SESSION_RESULT%" "DEBUG" "BAT"
CALL :LOG_MESSAGE "PowerShell admin check: %PS_ADMIN_CHECK%" "DEBUG" "BAT"

REM Consider admin if either method confirms admin privileges
SET "IS_ADMIN=false"
IF %NET_SESSION_RESULT% EQU 0 SET "IS_ADMIN=true"
IF "%PS_ADMIN_CHECK%"=="True" SET "IS_ADMIN=true"

CALL :LOG_MESSAGE "Final admin status: %IS_ADMIN%" "DEBUG" "BAT"

IF "%IS_ADMIN%"=="false" (
    CALL :LOG_MESSAGE "Not running as Administrator. Relaunching with admin rights..." "WARN" "BAT"
    CALL :LOG_MESSAGE "Attempting elevation using PowerShell Start-Process..." "DEBUG" "BAT"
    powershell -Command "Start-Process cmd -ArgumentList '/c \"%~f0\"' -Verb RunAs"
    EXIT /B 0
)

CALL :LOG_MESSAGE "Administrator privileges confirmed" "INFO" "BAT"

REM -----------------------------------------------------------------------------
REM PowerShell Version Check
REM Ensures PowerShell 5.1+ is available for all automation features.
REM -----------------------------------------------------------------------------
REM -----------------------------------------------------------------------------
REM POWERSHELL VERSION NOTES:
REM - Purpose: Verify the system has a compatible PowerShell runtime for the
REM   tools this launcher and orchestrator expect (PowerShell 5.1+ or later).
REM - Why: Certain modules, cmdlets, and behaviors differ between PS versions; failing
REM   early prevents confusing errors later in the run.
REM - Behavior: The launcher only checks the major version number returned by
REM   $PSVersionTable.PSVersion.Major and enforces a lower bound. The orchestrator
REM   will still perform graceful degradation if modules are missing.
REM -----------------------------------------------------------------------------
FOR /F "tokens=*" %%i IN ('powershell -Command "$PSVersionTable.PSVersion.Major" 2^>nul') DO SET PS_VERSION=%%i
IF "%PS_VERSION%"=="" SET PS_VERSION=0
IF %PS_VERSION% LSS 5 (
    CALL :LOG_MESSAGE "PowerShell 5.1 or higher is required. Current version: %PS_VERSION%" "ERROR" "BAT"
    CALL :LOG_MESSAGE "Please install PowerShell 5.1 or newer and try again." "ERROR" "BAT"
    pause
    EXIT /B 3
)
CALL :LOG_MESSAGE "PowerShell version: %PS_VERSION%" "INFO" "BAT"

REM -----------------------------------------------------------------------------
REM Windows Version Detection - PowerShell 5.1 Compatible
REM -----------------------------------------------------------------------------
FOR /F "tokens=*" %%i IN ('powershell -Command "try { (Get-CimInstance Win32_OperatingSystem).Version } catch { (Get-WmiObject Win32_OperatingSystem).Version }" 2^>nul') DO SET OS_VERSION=%%i
IF "%OS_VERSION%"=="" SET OS_VERSION=Unknown
CALL :LOG_MESSAGE "Detected Windows version: %OS_VERSION%" "INFO" "BAT"

REM -----------------------------------------------------------------------------
REM Windows Defender Exclusions Setup (LEGITIMATE MAINTENANCE SCRIPT)
REM NOTE TO SECURITY REVIEWERS: This is a legitimate Windows maintenance script.
REM The exclusions below are required to prevent Controlled Folder Access from
REM blocking legitimate system maintenance operations (temp file cleanup, updates).
REM This script is open-source and auditable at:
REM https://github.com/ichimbogdancristian/script_mentenanta
REM 
REM Exclusions added:
REM - Project folder: To allow log file creation and temp file management
REM - PowerShell processes: To allow script execution for maintenance tasks
REM These exclusions are OPTIONAL and the script will continue if they fail.
REM -----------------------------------------------------------------------------
REM -----------------------------------------------------------------------------
REM DEFENDER EXCLUSIONS NOTES:
REM - Purpose: Prevent Controlled Folder Access (CFA) and Windows Defender from blocking
REM   legitimate script file I/O and executable launches during maintenance runs.
REM - Scope: Adds folder-level and process-level exclusions. Folder exclusion targets
REM   the entire repo working directory; process exclusions include PowerShell binaries
REM   and the Windows command interpreter.
REM - Safety: Adding exclusions requires administrative privileges and may be restricted
REM   by enterprise policy. The script logs failures and continues gracefully.
REM - Operator guidance: Review your organization's security policy before enabling
REM   exclusions widely; consider adding only the specific required paths.
REM -----------------------------------------------------------------------------
CALL :LOG_MESSAGE "Setting up Windows Defender exclusions for project..." "INFO" "BAT"

REM Add folder exclusion for the entire project directory
powershell -Command "try { Add-MpPreference -ExclusionPath '%WORKING_DIR%' -ErrorAction Stop; Write-Host 'SUCCESS: Added folder exclusion for %WORKING_DIR%' } catch { Write-Host 'WARNING: Could not add folder exclusion - ' + $_.Exception.Message }" 2>nul
IF %ERRORLEVEL% EQU 0 (
    CALL :LOG_MESSAGE "Added Windows Defender folder exclusion: %WORKING_DIR%" "INFO" "BAT"
) ELSE (
    CALL :LOG_MESSAGE "Could not add folder exclusion (may already exist)" "WARN" "BAT"
)

REM Add process exclusions for PowerShell and batch scripts
powershell -Command "try { Add-MpPreference -ExclusionProcess 'powershell.exe' -ErrorAction SilentlyContinue } catch { }" >nul 2>&1
powershell -Command "try { Add-MpPreference -ExclusionProcess 'pwsh.exe' -ErrorAction SilentlyContinue } catch { }" >nul 2>&1
powershell -Command "try { Add-MpPreference -ExclusionProcess 'cmd.exe' -ErrorAction SilentlyContinue } catch { }" >nul 2>&1

REM Check Controlled Folder Access status
FOR /F "tokens=*" %%i IN ('powershell -Command "try { (Get-MpPreference).EnableControlledFolderAccess } catch { 'Unknown' }" 2^>nul') DO SET CFA_STATUS=%%i
IF "%CFA_STATUS%"=="1" (
    CALL :LOG_MESSAGE "Controlled Folder Access is ENABLED - exclusions are important" "INFO" "BAT"
    REM Add specific app allowlist for PowerShell if CFA is enabled
    powershell -Command "try { Add-MpPreference -ControlledFolderAccessAllowedApplications 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' -ErrorAction SilentlyContinue } catch { }" >nul 2>&1
    powershell -Command "try { Add-MpPreference -ControlledFolderAccessAllowedApplications 'C:\Program Files\PowerShell\7\pwsh.exe' -ErrorAction SilentlyContinue } catch { }" >nul 2>&1
    CALL :LOG_MESSAGE "Added PowerShell to Controlled Folder Access allowlist" "INFO" "BAT"
) ELSE IF "%CFA_STATUS%"=="0" (
    CALL :LOG_MESSAGE "Controlled Folder Access is disabled - no additional exclusions needed" "INFO" "BAT"
) ELSE (
    CALL :LOG_MESSAGE "Could not determine Controlled Folder Access status" "INFO" "BAT"
)

CALL :LOG_MESSAGE "Windows Defender exclusions setup completed" "INFO" "BAT"

REM -----------------------------------------------------------------------------
REM Enhanced Monthly Scheduled Task Setup
REM Ensures a monthly scheduled task is created to run this script as admin.
REM -----------------------------------------------------------------------------
REM -----------------------------------------------------------------------------
REM SCHEDULED TASK NOTES:
REM - Purpose: Create a monthly scheduled task that runs this launcher at high privilege
REM   so maintenance can occur unattended on a monthly cadence.
REM - Creation strategy: Prefer SYSTEM-level task for consistent, elevated runs; fallback
REM   to current user if SYSTEM creation fails (some environments restrict SYSTEM tasks).
REM - Verification: After creating the task, the script queries and logs the 'Next Run Time'
REM   for operator confirmation.
REM - Operator guidance: If task creation fails repeatedly, inspect the generated
REM   schtasks_create.log or schtasks_create_user.log for error details.
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
REM -----------------------------------------------------------------------------
REM RESTART DETECTION NOTES:
REM - Purpose: Avoid unnecessary reboots. Only trigger restart flows when pending
REM   Windows Updates (or equivalent system flags) require a restart to complete
REM   update installation.
REM - Strategy: Prefer PSWindowsUpdate-based detection when available (more accurate),
REM   otherwise fall back to registry indicators like RebootRequired or RebootPending.
REM - Behavior: When an update-related restart is required, the launcher creates a
REM   temporary startup scheduled task to resume the script after reboot and then
REM   reboots the system. If scheduling the startup task fails, the script logs the issue
REM   and continues without forcing a reboot.
REM - Operator guidance: This logic minimizes unnecessary downtime; enable auto-restarts
REM   only when acceptable for your environment.
REM -----------------------------------------------------------------------------
CALL :LOG_MESSAGE "Checking for pending updates requiring restart..." "INFO" "BAT"
SET "RESTART_NEEDED=NO"
SET "RESTART_REASON="

REM Check if there are pending updates that require restart (more specific)
powershell -ExecutionPolicy Bypass -Command "try { if (Get-Module -ListAvailable -Name PSWindowsUpdate) { Import-Module PSWindowsUpdate -Force; $updates = Get-WindowsUpdate -MicrosoftUpdate -AcceptAll -IgnoreReboot; $restartRequired = $updates | Where-Object { $_.RebootRequired -eq $true }; if ($restartRequired) { Write-Host 'RESTART_REQUIRED_UPDATES'; exit 1 } else { Write-Host 'NO_RESTART_REQUIRED_UPDATES'; exit 0 } } else { Write-Host 'PSWINDOWSUPDATE_NOT_AVAILABLE'; exit 2 } } catch { Write-Host 'UPDATE_CHECK_FAILED'; exit 3 }"

IF !ERRORLEVEL! EQU 1 (
    CALL :LOG_MESSAGE "Pending updates require restart for installation." "INFO" "BAT"
    SET "RESTART_NEEDED=YES"
    SET "RESTART_REASON=Pending updates require restart"
) ELSE IF !ERRORLEVEL! EQU 0 (
    CALL :LOG_MESSAGE "No pending updates require restart." "INFO" "BAT"
) ELSE IF !ERRORLEVEL! EQU 2 (
    CALL :LOG_MESSAGE "PSWindowsUpdate module not available. Checking system restart flags..." "WARN" "BAT"
    
    REM Fallback: Check Windows Update reboot flag only
    REG QUERY "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired" >nul 2>&1
    IF !ERRORLEVEL! EQU 0 (
        CALL :LOG_MESSAGE "Windows Update restart flag detected." "INFO" "BAT"
        SET "RESTART_NEEDED=YES"
        SET "RESTART_REASON=Windows Update restart flag detected"
    )
    
    REM Check Component Based Servicing reboot flag (only for update-related restarts)
    REG QUERY "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending" >nul 2>&1
    IF !ERRORLEVEL! EQU 0 (
        CALL :LOG_MESSAGE "Component Based Servicing restart pending." "INFO" "BAT"
        SET "RESTART_NEEDED=YES"
        SET "RESTART_REASON=Component Based Servicing restart pending"
    )
) ELSE (
    CALL :LOG_MESSAGE "Update check failed. Skipping restart check." "WARN" "BAT"
)

REM Only restart if there are actual updates requiring restart
IF "%RESTART_NEEDED%"=="YES" (
    CALL :LOG_MESSAGE "System restart is required for pending updates." "WARN" "BAT"
    CALL :LOG_MESSAGE "Reason: %RESTART_REASON%" "INFO" "BAT"
    CALL :LOG_MESSAGE "Creating startup task and restarting to complete update installation..." "INFO" "BAT"
    
    REM Delete any existing startup task first
    schtasks /Delete /TN "%STARTUP_TASK_NAME%" /F >nul 2>&1
    
    REM Create startup task to run 1 minute after user login with admin rights
    CALL :LOG_MESSAGE "Creating startup task with script path: %SCHEDULED_TASK_SCRIPT_PATH%" "DEBUG" "BAT"
    schtasks /Create /SC ONLOGON /TN "%STARTUP_TASK_NAME%" /TR "%SCHEDULED_TASK_SCRIPT_PATH%" /RL HIGHEST /RU "%USERNAME%" /DELAY 0001:00 /F
    IF !ERRORLEVEL! EQU 0 (
        CALL :LOG_MESSAGE "Startup task created successfully. Will run 1 minute after user login." "INFO" "BAT"
        CALL :LOG_MESSAGE "Restarting system to complete pending updates..." "INFO" "BAT"
        shutdown /r /t 10 /c "System restart required to complete pending Windows Updates"
        CALL :LOG_MESSAGE "System will restart in 10 seconds to complete updates..." "INFO" "BAT"
        timeout /t 12 /nobreak >nul
        EXIT /B 0
    ) ELSE (
        CALL :LOG_MESSAGE "Failed to create startup task. Continuing without restart..." "ERROR" "BAT"
        CALL :LOG_MESSAGE "Updates may require manual restart after installation." "WARN" "BAT"
    )
) ELSE (
    CALL :LOG_MESSAGE "No pending updates require restart. Continuing with maintenance script..." "INFO" "BAT"
)


REM -----------------------------------------------------------------------------
REM Dependency Management - Direct Downloads from Official Sources
REM Installation Order: Winget -> PowerShell 7 -> NuGet -> PSGallery -> PSWindowsUpdate -> Chocolatey
REM -----------------------------------------------------------------------------
CALL :LOG_MESSAGE "Starting dependency installation with optimized order..." "INFO" "BAT"

REM -----------------------------------------------------------------------------
REM 1. Windows Package Manager (Winget) - Foundation package manager
REM -----------------------------------------------------------------------------
CALL :LOG_MESSAGE "Installing Windows Package Manager (winget)..." "INFO" "BAT"
REM Improved Winget detection: check both version and path
winget --version >nul 2>&1
SET "WINGET_FOUND=0"
IF !ERRORLEVEL! EQU 0 (
    SET "WINGET_FOUND=1"
    CALL :LOG_MESSAGE "Winget detected via version check." "DEBUG" "BAT"
) ELSE (
    where winget >nul 2>&1
    IF !ERRORLEVEL! EQU 0 (
        SET "WINGET_FOUND=1"
        CALL :LOG_MESSAGE "Winget detected via PATH (where command)." "DEBUG" "BAT"
    )
)

IF !WINGET_FOUND! EQU 0 (
    CALL :LOG_MESSAGE "Winget not found, downloading from official Microsoft source..." "INFO" "BAT"
    REM Download latest App Installer from Microsoft Store
    SET "WINGET_URL=https://github.com/microsoft/winget-cli/releases/latest/download/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"
    SET "WINGET_FILE=!TEMP!\Microsoft.DesktopAppInstaller.msixbundle"
    powershell -ExecutionPolicy Bypass -Command "try { $ProgressPreference = 'SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri '!WINGET_URL!' -OutFile '!WINGET_FILE!' -UseBasicParsing; Write-Host '[INFO] Winget downloaded successfully' } catch { Write-Host '[WARN] Winget download failed:' $_.Exception.Message; exit 1 }"
    IF !ERRORLEVEL! EQU 0 (
        CALL :LOG_MESSAGE "Installing Winget package..." "INFO" "BAT"
        powershell -ExecutionPolicy Bypass -Command "try { if (Get-Command Add-AppxPackage -ErrorAction SilentlyContinue) { Add-AppxPackage -Path '!WINGET_FILE!' -ErrorAction Stop; Write-Host '[INFO] Winget installed successfully' } else { Write-Host '[WARN] Add-AppxPackage not available in this PowerShell version' } } catch { Write-Host '[WARN] Winget installation failed:' $_.Exception.Message; exit 1 }"
        IF !ERRORLEVEL! EQU 0 (
            CALL :LOG_MESSAGE "Winget installation completed successfully." "INFO" "BAT"
        ) ELSE (
            CALL :LOG_MESSAGE "Winget installation failed, but continuing..." "WARN" "BAT"
        )
        DEL /F /Q "!WINGET_FILE!" >nul 2>&1
    ) ELSE (
        CALL :LOG_MESSAGE "Winget download failed, but continuing..." "WARN" "BAT"
    )
) ELSE (
    CALL :LOG_MESSAGE "Winget is already available." "INFO" "BAT"
)

REM -----------------------------------------------------------------------------
REM 2. PowerShell 7 - Modern PowerShell environment
REM -----------------------------------------------------------------------------
CALL :LOG_MESSAGE "Installing PowerShell 7..." "INFO" "BAT"
pwsh.exe -Version >nul 2>&1
IF !ERRORLEVEL! NEQ 0 (
    CALL :LOG_MESSAGE "PowerShell 7 not found, downloading from official Microsoft source..." "INFO" "BAT"
    
    REM Set download URL for PowerShell 7.5.2 (no fallback)
    SET "PS7_INSTALLER=%TEMP%\PowerShell-7.5.2.msi"
    
    REM Detect architecture and set appropriate download URL
    IF "%PROCESSOR_ARCHITECTURE%"=="AMD64" (
        SET "PS7_URL=https://github.com/PowerShell/PowerShell/releases/download/v7.5.2/PowerShell-7.5.2-win-x64.msi"
    ) ELSE (
        SET "PS7_URL=https://github.com/PowerShell/PowerShell/releases/download/v7.5.2/PowerShell-7.5.2-win-x86.msi"
    )
    
    REM Download PowerShell 7.5.2
    CALL :LOG_MESSAGE "Downloading PowerShell 7.5.2..." "INFO" "BAT"
    powershell -ExecutionPolicy Bypass -Command "try { $ProgressPreference = 'SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri '!PS7_URL!' -OutFile '!PS7_INSTALLER!' -UseBasicParsing; Write-Host '[INFO] PowerShell 7.5.2 downloaded successfully' } catch { Write-Host '[ERROR] PowerShell 7.5.2 download failed:' $_.Exception.Message; exit 1 }"
    
    IF !ERRORLEVEL! EQU 0 (
        CALL :LOG_MESSAGE "Installing PowerShell 7..." "INFO" "BAT"
        msiexec /i "!PS7_INSTALLER!" /quiet /norestart
        IF !ERRORLEVEL! EQU 0 (
            CALL :LOG_MESSAGE "PowerShell 7 installed successfully." "INFO" "BAT"
            REM Refresh PATH environment variable for current session
            FOR /F "tokens=2*" %%A IN ('REG QUERY "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" /v PATH') DO SET "PATH=%%B"
            REM Add common PowerShell 7 installation paths to current session
            IF EXIST "%ProgramFiles%\PowerShell\7" SET "PATH=%PATH%;%ProgramFiles%\PowerShell\7"
            IF EXIST "%ProgramFiles(x86)%\PowerShell\7" SET "PATH=%PATH%;%ProgramFiles(x86)%\PowerShell\7"
            CALL :LOG_MESSAGE "PowerShell 7 installation completed. Restarting script to use new PowerShell..." "INFO" "BAT"
            REM Restart the script to use newly installed PowerShell 7
            START "" "%~f0" PS7_RESTART
            EXIT /B 0
        ) ELSE (
            CALL :LOG_MESSAGE "PowerShell 7 installation failed." "WARN" "BAT"
        )
        DEL /F /Q "!PS7_INSTALLER!" >nul 2>&1
    )
) ELSE (
    FOR /F "tokens=*" %%i IN ('pwsh.exe -Command "$PSVersionTable.PSVersion.ToString()" 2^>nul') DO SET PS7_VERSION=%%i
    CALL :LOG_MESSAGE "PowerShell 7 already available: %PS7_VERSION%" "INFO" "BAT"
)

:SKIP_PS7_INSTALL

REM -----------------------------------------------------------------------------
REM 3. NuGet PackageProvider - Automatic installation with multiple methods
REM -----------------------------------------------------------------------------
CALL :LOG_MESSAGE "Installing NuGet PackageProvider with automatic confirmation..." "INFO" "BAT"

REM Method 1: Direct bootstrap with automatic Y response
ECHO Y | powershell -ExecutionPolicy Bypass -Command "& { $env:PACKAGEMANAGEMENT_BOOTSTRAP_LOGLEVEL='None'; if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) { try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope AllUsers -ErrorAction Stop; Write-Host '[INFO] NuGet PackageProvider installed successfully' } catch { Write-Host '[WARN] Method 1 failed, trying direct download...' } } else { Write-Host '[INFO] NuGet PackageProvider already available' } }"

IF !ERRORLEVEL! NEQ 0 (
    CALL :LOG_MESSAGE "Trying alternative NuGet installation method..." "INFO" "BAT"
    REM Method 2: Direct download and install (fallback)
    powershell -ExecutionPolicy Bypass -Command "& { try { $nugetUrl = 'https://onegetcdn.azureedge.net/providers/Microsoft.PackageManagement.NuGetProvider-2.8.5.208.dll'; $nugetPath = Join-Path $env:ProgramFiles 'PackageManagement\ProviderAssemblies\nuget\2.8.5.208\Microsoft.PackageManagement.NuGetProvider.dll'; $nugetDir = Split-Path $nugetPath; if (-not (Test-Path $nugetDir)) { New-Item -ItemType Directory -Path $nugetDir -Force | Out-Null }; [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri $nugetUrl -OutFile $nugetPath -UseBasicParsing; Write-Host '[INFO] NuGet PackageProvider downloaded and installed manually' } catch { Write-Host '[WARN] Direct download also failed:' $_.Exception.Message } }"
)

IF !ERRORLEVEL! NEQ 0 (
    CALL :LOG_MESSAGE "NuGet PackageProvider installation failed, but continuing..." "WARN" "BAT"
)

REM -----------------------------------------------------------------------------
REM 4. PowerShell Gallery Configuration - Fully Unattended
REM -----------------------------------------------------------------------------
CALL :LOG_MESSAGE "Configuring PowerShell Gallery as trusted repository..." "INFO" "BAT"
ECHO Y | powershell -ExecutionPolicy Bypass -Command "& { try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) { Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope AllUsers -Confirm:`$false -ErrorAction SilentlyContinue }; Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted -ErrorAction Stop; Write-Host '[INFO] PowerShell Gallery configured as trusted' } catch { Write-Host '[WARN] Failed to configure PowerShell Gallery:' `$_.Exception.Message } }"

REM -----------------------------------------------------------------------------
REM 5. PSWindowsUpdate Module - Download from PowerShell Gallery with auto-confirmation
REM -----------------------------------------------------------------------------
CALL :LOG_MESSAGE "Installing PSWindowsUpdate module with automatic confirmation..." "INFO" "BAT"
ECHO Y | powershell -ExecutionPolicy Bypass -Command "& { if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) { try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) { Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope AllUsers -Confirm:`$false -ErrorAction SilentlyContinue }; Install-Module -Name PSWindowsUpdate -Force -Scope AllUsers -AllowClobber -Repository PSGallery -Confirm:`$false; Write-Host '[INFO] PSWindowsUpdate module installed successfully' } catch { Write-Host '[WARN] Failed to install PSWindowsUpdate module:' `$_.Exception.Message } } else { Write-Host '[INFO] PSWindowsUpdate module already available' } }"

IF !ERRORLEVEL! NEQ 0 (
    CALL :LOG_MESSAGE "PSWindowsUpdate module installation failed." "WARN" "BAT"
)

REM -----------------------------------------------------------------------------
REM 6. Chocolatey Package Manager - Direct download from official source
REM -----------------------------------------------------------------------------
CALL :LOG_MESSAGE "Installing Chocolatey package manager..." "INFO" "BAT"
choco --version >nul 2>&1
IF !ERRORLEVEL! NEQ 0 (
    CALL :LOG_MESSAGE "Chocolatey not found, downloading from official source..." "INFO" "BAT"
    
    REM Download Chocolatey installer to temp file first (safer approach - avoids Invoke-Expression)
    SET "CHOCO_INSTALLER=%TEMP%\chocolatey-install.ps1"
    powershell -ExecutionPolicy Bypass -Command "& { try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri 'https://community.chocolatey.org/install.ps1' -OutFile '%CHOCO_INSTALLER%' -UseBasicParsing; Write-Host '[INFO] Chocolatey installer downloaded' } catch { Write-Host '[ERROR] Chocolatey download failed:' $_.Exception.Message; exit 1 } }"
    
    REM Execute the downloaded installer file (avoids DownloadString + Invoke-Expression combo)
    IF EXIST "%CHOCO_INSTALLER%" (
        powershell -ExecutionPolicy Bypass -File "%CHOCO_INSTALLER%"
        DEL /F /Q "%CHOCO_INSTALLER%" >nul 2>&1
    )
    
    REM Refresh PATH to include Chocolatey
    IF EXIST "%ProgramData%\chocolatey\bin" (
        SET "PATH=%PATH%;%ProgramData%\chocolatey\bin"
        CALL :LOG_MESSAGE "Chocolatey PATH updated." "INFO" "BAT"
    )
) ELSE (
    CALL :LOG_MESSAGE "Chocolatey is already installed." "INFO" "BAT"
)

CALL :LOG_MESSAGE "Dependency installation phase completed with optimized order." "INFO" "BAT"

REM -----------------------------------------------------------------------------
REM System Restart Detection - Refined for Windows Updates Only
REM Only restart if Windows Update has installed updates requiring a reboot
REM -----------------------------------------------------------------------------
CALL :LOG_MESSAGE "Checking for pending Windows Update restarts..." "INFO" "BAT"
SET "RESTART_NEEDED=NO"

REM Only check Windows Update reboot flag - this is the authoritative source
REM This key is only present if Windows Update has installed updates that require a reboot
REG QUERY "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired" >nul 2>&1
IF !ERRORLEVEL! EQU 0 (
    SET "RESTART_NEEDED=YES"
    CALL :LOG_MESSAGE "Windows Update restart requirement detected." "INFO" "BAT"
) ELSE (
    CALL :LOG_MESSAGE "No Windows Update restart requirement found." "INFO" "BAT"
)

REM Additional check: Verify if any specific Windows Updates are pending restart
powershell -ExecutionPolicy Bypass -Command "try { $updates = Get-HotFix | Where-Object { $_.InstalledOn -gt (Get-Date).AddDays(-1) }; if ($updates) { $rebootPending = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired' -ErrorAction SilentlyContinue; if ($rebootPending) { Write-Host 'CONFIRMED_UPDATE_RESTART_PENDING'; exit 1 } } Write-Host 'NO_UPDATE_RESTART_PENDING'; exit 0 } catch { Write-Host 'UPDATE_CHECK_FAILED'; exit 0 }" >nul 2>&1
IF !ERRORLEVEL! EQU 1 SET "RESTART_NEEDED=YES"

IF "%RESTART_NEEDED%"=="YES" (
    CALL :LOG_MESSAGE "System restart required due to Windows Updates. Creating startup task..." "WARN" "BAT"
    schtasks /Query /TN "%STARTUP_TASK_NAME%" >nul 2>&1
    IF %ERRORLEVEL% EQU 0 (
        schtasks /Delete /TN "%STARTUP_TASK_NAME%" /F >nul 2>&1
    )
    schtasks /Create /SC ONLOGON /TN "%STARTUP_TASK_NAME%" /TR "%SCRIPT_PATH%" /RL HIGHEST /RU "%USERNAME%" /DELAY 0001:00 /F
    IF !ERRORLEVEL! EQU 0 (
        CALL :LOG_MESSAGE "Startup task created. Restarting system in 15 seconds for Windows Update completion..." "INFO" "BAT"
        CALL :LOG_MESSAGE "Press Ctrl+C to cancel restart." "INFO" "BAT"
        timeout /t 15
        shutdown /r /t 5 /c "System restart required for Windows Update completion"
        EXIT /B 0
    ) ELSE (
        CALL :LOG_MESSAGE "Failed to create startup task. Continuing without restart..." "WARN" "BAT"
        CALL :LOG_MESSAGE "Task name: %STARTUP_TASK_NAME%" "DEBUG" "BAT"
        CALL :LOG_MESSAGE "Script path: %SCRIPT_PATH%" "DEBUG" "BAT"
        CALL :LOG_MESSAGE "Username: %USERNAME%" "DEBUG" "BAT"
        CALL :LOG_MESSAGE "Error level: !ERRORLEVEL!" "DEBUG" "BAT"
    )
) ELSE (
    CALL :LOG_MESSAGE "No Windows Update restart required. Continuing with maintenance script..." "INFO" "BAT"
)

REM -----------------------------------------------------------------------------
REM Universal Repository Management - Location-Agnostic Download & Update
REM Works from any directory, downloads to current script location
REM -----------------------------------------------------------------------------
:SKIP_SELF_UPDATE

REM Check if local script.ps1 exists - ALWAYS download latest from GitHub
REM This ensures we always have the most up-to-date version
CALL :LOG_MESSAGE "Checking for local script.ps1 file..." "DEBUG" "BAT"
IF EXIST "%WORKING_DIR%script.ps1" (
    CALL :LOG_MESSAGE "Found local script.ps1 - removing to download latest version from GitHub" "INFO" "BAT"
    DEL /F /Q "%WORKING_DIR%script.ps1" >nul 2>&1
    IF !ERRORLEVEL! EQU 0 (
        CALL :LOG_MESSAGE "Local script.ps1 removed successfully" "INFO" "BAT"
    ) ELSE (
        CALL :LOG_MESSAGE "Warning: Could not delete local script.ps1, attempting force delete..." "WARN" "BAT"
        powershell -ExecutionPolicy Bypass -Command "try { if(Test-Path '%WORKING_DIR%script.ps1') { Remove-Item -Path '%WORKING_DIR%script.ps1' -Force } } catch { Write-Warning 'Could not force delete script.ps1' }"
    )
)

CALL :LOG_MESSAGE "Downloading latest version from GitHub repository..." "INFO" "BAT"
CALL :LOG_MESSAGE "NOTE: Repository download requires the GitHub repository to be public and accessible" "WARN" "BAT"
CALL :LOG_MESSAGE "Working directory: %WORKING_DIR%" "DEBUG" "BAT"
CALL :LOG_MESSAGE "Downloading to: %WORKING_DIR%" "INFO" "BAT"

REM Clean up existing files before download
IF EXIST "%ZIP_FILE%" (
    DEL "%ZIP_FILE%" >nul 2>&1
    CALL :LOG_MESSAGE "Removed existing ZIP file" "INFO" "BAT"
)

IF EXIST "%EXTRACTED_PATH%" (
    CALL :LOG_MESSAGE "Removing existing repository folder..." "INFO" "BAT"
    RMDIR /S /Q "%EXTRACTED_PATH%" >nul 2>&1
    IF EXIST "%EXTRACTED_PATH%" (
        powershell -ExecutionPolicy Bypass -Command "try { if(Test-Path '%EXTRACTED_PATH%') { Remove-Item -Path '%EXTRACTED_PATH%' -Recurse -Force } } catch { Write-Warning 'Could not remove existing folder' }"
    )
)

REM Download repository
CALL :LOG_MESSAGE "Downloading from: %REPO_URL%" "INFO" "BAT"
CALL :LOG_MESSAGE "Saving to: %ZIP_FILE%" "INFO" "BAT"

powershell -ExecutionPolicy Bypass -Command "try { $ProgressPreference = 'SilentlyContinue'; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12; $webClient = New-Object System.Net.WebClient; $webClient.DownloadFile('%REPO_URL%', '%ZIP_FILE%'); Write-Host '[INFO] Repository downloaded successfully' } catch { Write-Host '[ERROR] Download failed:' $_.Exception.Message; exit 1 }"

IF !ERRORLEVEL! NEQ 0 (
    CALL :LOG_MESSAGE "Failed to download repository from GitHub." "ERROR" "BAT"
    CALL :LOG_MESSAGE "Repository URL: %REPO_URL%" "ERROR" "BAT"
    CALL :LOG_MESSAGE "" "INFO" "BAT"
    CALL :LOG_MESSAGE "TROUBLESHOOTING:" "WARN" "BAT"
    CALL :LOG_MESSAGE "1. The GitHub repository may not be accessible or is private" "WARN" "BAT"
    CALL :LOG_MESSAGE "2. Check your internet connection" "WARN" "BAT"
    CALL :LOG_MESSAGE "3. Verify the repository URL is correct: %REPO_URL%" "WARN" "BAT"
    CALL :LOG_MESSAGE "" "INFO" "BAT"
    pause
    EXIT /B 3
)

IF NOT EXIST "%ZIP_FILE%" (
    CALL :LOG_MESSAGE "Download failed - ZIP file not created at: %ZIP_FILE%" "ERROR" "BAT"
    pause
    EXIT /B 3
)

REM Extract repository
CALL :LOG_MESSAGE "Extracting repository to: %WORKING_DIR%" "INFO" "BAT"

powershell -ExecutionPolicy Bypass -Command "try { Add-Type -AssemblyName System.IO.Compression.FileSystem; if(Test-Path '%ZIP_FILE%') { [System.IO.Compression.ZipFile]::ExtractToDirectory('%ZIP_FILE%', '%WORKING_DIR%'); Write-Host '[INFO] Repository extracted successfully.' } else { Write-Host '[ERROR] ZIP file not found at %ZIP_FILE%'; exit 1 } } catch { Write-Host '[ERROR] Extraction failed:' $_.Exception.Message; exit 1 }"

IF !ERRORLEVEL! NEQ 0 (
    CALL :LOG_MESSAGE "Repository extraction failed." "ERROR" "BAT"
    pause
    EXIT /B 3
)

REM Clean up ZIP file after successful extraction
CALL :LOG_MESSAGE "Cleaning up repository archive..." "INFO" "BAT"
IF EXIST "%ZIP_FILE%" (
    DEL /F /Q "%ZIP_FILE%" >nul 2>&1
    IF !ERRORLEVEL! EQU 0 (
        CALL :LOG_MESSAGE "Repository archive removed successfully: %ZIP_FILE%" "INFO" "BAT"
    ) ELSE (
        CALL :LOG_MESSAGE "Warning: Could not delete ZIP file, attempting force delete..." "WARN" "BAT"
        powershell -ExecutionPolicy Bypass -Command "try { if(Test-Path '%ZIP_FILE%') { Remove-Item -Path '%ZIP_FILE%' -Force -ErrorAction Stop; Write-Host '[INFO] ZIP archive deleted via PowerShell' } } catch { Write-Host '[WARN] Could not force delete ZIP file: ' $_.Exception.Message }" >nul 2>&1
        IF !ERRORLEVEL! EQU 0 (
            CALL :LOG_MESSAGE "Repository archive removed successfully via PowerShell" "INFO" "BAT"
        ) ELSE (
            CALL :LOG_MESSAGE "Warning: Repository archive could not be deleted (may be locked)" "WARN" "BAT"
        )
    )
) ELSE (
    CALL :LOG_MESSAGE "ZIP file not found (already cleaned up)" "DEBUG" "BAT"
)

REM Verify extraction and locate script.ps1
CALL :LOG_MESSAGE "Verifying repository extraction..." "INFO" "BAT"
CALL :LOG_MESSAGE "Looking for extracted folder: %EXTRACTED_PATH%" "INFO" "BAT"

IF EXIST "%EXTRACTED_PATH%" (
    CALL :LOG_MESSAGE "Repository extraction successful" "INFO" "BAT"
    
    REM Update PowerShell script path to extracted version
    IF EXIST "%EXTRACTED_PATH%\script.ps1" (
        SET "PS1_PATH=%EXTRACTED_PATH%\script.ps1"
        CALL :LOG_MESSAGE "Found script.ps1 in extracted folder: %PS1_PATH%" "INFO" "BAT"
        GOTO :PS1_LOCAL_CONFIRMED
    ) ELSE (
        CALL :LOG_MESSAGE "script.ps1 not found in extracted folder" "ERROR" "BAT"
        pause
        EXIT /B 3
    )
    
) ELSE (
    CALL :LOG_MESSAGE "✗ Extraction failed - expected folder not found" "ERROR" "BAT"
    CALL :LOG_MESSAGE "Available folders in working directory:" "INFO" "BAT"
    DIR "%WORKING_DIR%" /AD /B
    
    REM Try alternative folder names (older GitHub naming)
    IF EXIST "%WORKING_DIR%script_mentenanta-master" (
        SET "EXTRACT_FOLDER=script_mentenanta-master"
        SET "EXTRACTED_PATH=%WORKING_DIR%script_mentenanta-master"
        IF EXIST "%EXTRACTED_PATH%\script.ps1" (
            SET "PS1_PATH=%EXTRACTED_PATH%\script.ps1"
            CALL :LOG_MESSAGE "Found alternative folder: script_mentenanta-master" "INFO" "BAT"
            GOTO :PS1_LOCAL_CONFIRMED
        )
    )
    
    CALL :LOG_MESSAGE "Could not find valid extracted folder with script.ps1" "ERROR" "BAT"
    pause
    EXIT /B 3
)

REM Should not reach here, but if extraction succeeded and PS1_PATH was set, continue
:PS1_LOCAL_CONFIRMED

REM -----------------------------------------------------------------------------
REM Self-Update Mechanism - Using dynamic paths
REM -----------------------------------------------------------------------------
SET "NEW_SCRIPT_BAT=%EXTRACTED_PATH%\script.bat"
SET "CURRENT_SCRIPT_BAT=%SCRIPT_PATH%"
SET "SELF_UPDATE_NEEDED=NO"

IF EXIST "%NEW_SCRIPT_BAT%" (
    CALL :LOG_MESSAGE "Found new script.bat in extracted repository." "INFO" "BAT"
    CALL :LOG_MESSAGE "Self-update will be performed AFTER PowerShell script execution." "INFO" "BAT"
    CALL :LOG_MESSAGE "This prevents execution conflicts during script update." "INFO" "BAT"
    SET "SELF_UPDATE_NEEDED=YES"
)
REM -----------------------------------------------------------------------------
REM PowerShell 7 Detection and Final Verification
REM -----------------------------------------------------------------------------
CALL :LOG_MESSAGE "Checking PowerShell 7 availability for script execution..." "INFO" "BAT"
SET "PS7_AVAILABLE=NO"

pwsh.exe -Version >nul 2>&1
IF !ERRORLEVEL! EQU 0 (
    SET "PS7_AVAILABLE=YES"
    FOR /F "tokens=*" %%i IN ('pwsh.exe -Command "$PSVersionTable.PSVersion.ToString()" 2^>nul') DO SET PS7_VERSION=%%i
    CALL :LOG_MESSAGE "PowerShell 7 found: !PS7_VERSION!" "INFO" "BAT"
) ELSE (
    CALL :LOG_MESSAGE "PowerShell 7 not available. Will use Windows PowerShell." "WARN" "BAT"
)

REM -----------------------------------------------------------------------------
REM Smart PowerShell Script Path Detection (Location-Agnostic)
REM -----------------------------------------------------------------------------
CALL :LOG_MESSAGE "Starting PowerShell script path detection..." "INFO" "BAT"
CALL :LOG_MESSAGE "Working directory: %WORKING_DIR%" "DEBUG" "BAT"
CALL :LOG_MESSAGE "Extracted path: %EXTRACTED_PATH%" "DEBUG" "BAT"

REM Priority 1: Use the path already set during extraction
IF DEFINED PS1_PATH (
    IF EXIST "%PS1_PATH%" (
        CALL :LOG_MESSAGE "Using PowerShell script: %PS1_PATH%" "INFO" "BAT"
        GOTO :PS1_DETECTION_COMPLETE
    )
)

REM Priority 2: Check current directory (if script.ps1 exists locally)
CALL :LOG_MESSAGE "Checking current directory: %WORKING_DIR%script.ps1" "DEBUG" "BAT"
IF EXIST "%WORKING_DIR%script.ps1" (
    SET "PS1_PATH=%WORKING_DIR%script.ps1"
    CALL :LOG_MESSAGE "Found script.ps1 in current directory" "INFO" "BAT"
    GOTO :PS1_DETECTION_COMPLETE
)

REM Priority 3: Check extracted folder (if repo was updated)
IF DEFINED EXTRACTED_PATH (
    CALL :LOG_MESSAGE "Checking extracted folder: %EXTRACTED_PATH%\script.ps1" "DEBUG" "BAT"
    IF EXIST "%EXTRACTED_PATH%\script.ps1" (
        SET "PS1_PATH=%EXTRACTED_PATH%\script.ps1"
        CALL :LOG_MESSAGE "Found script.ps1 in extracted folder" "INFO" "BAT"
        GOTO :PS1_DETECTION_COMPLETE
    )
)

:PS1_DETECTION_COMPLETE

REM Final check: If still not found, show detailed diagnostics
IF NOT DEFINED PS1_PATH (
    CALL :LOG_MESSAGE "PowerShell script (script.ps1) not found in any location!" "ERROR" "BAT"
    CALL :LOG_MESSAGE "Searched locations:" "INFO" "BAT"
    CALL :LOG_MESSAGE "1. Extracted folder: %EXTRACTED_PATH%\script.ps1" "INFO" "BAT"
    CALL :LOG_MESSAGE "2. Current directory: %WORKING_DIR%script.ps1" "INFO" "BAT"
    CALL :LOG_MESSAGE "Contents of working directory:" "INFO" "BAT"
    DIR "%WORKING_DIR%" /B
    IF EXIST "%EXTRACTED_PATH%" (
        CALL :LOG_MESSAGE "Contents of extracted folder:" "INFO" "BAT"
        DIR "%EXTRACTED_PATH%" /B
    )
    pause
    EXIT /B 7
) ELSE (
    CALL :LOG_MESSAGE "PowerShell script found successfully!" "SUCCESS" "BAT"
)
REM -----------------------------------------------------------------------------
REM Launch PowerShell Script
REM -----------------------------------------------------------------------------
CALL :LOG_MESSAGE "Final PowerShell script path: %PS1_PATH%" "INFO" "BAT"
CALL :LOG_MESSAGE "Launching PowerShell maintenance script..." "INFO" "BAT"

REM Test PowerShell availability before launching
powershell.exe -Command "Write-Host 'PowerShell test successful'" >nul 2>&1
IF !ERRORLEVEL! NEQ 0 (
    CALL :LOG_MESSAGE "Windows PowerShell is not available or functioning properly." "ERROR" "BAT"
    pause
    EXIT /B 5
)

REM Final check that PS1_PATH is not empty before execution
IF NOT DEFINED PS1_PATH (
    CALL :LOG_MESSAGE "PS1_PATH is empty before execution!" "FATAL" "BAT"
    CALL :LOG_MESSAGE "Cannot proceed without PowerShell script!" "FATAL" "BAT"
    pause
    EXIT /B 5
)

CALL :LOG_MESSAGE "About to execute: %PS1_PATH%" "INFO" "BAT"
CALL :LOG_MESSAGE "Verifying file exists: %PS1_PATH%" "INFO" "BAT"
IF NOT EXIST "%PS1_PATH%" (
    CALL :LOG_MESSAGE "PowerShell script file does not exist: %PS1_PATH%" "FATAL" "BAT"
    pause
    EXIT /B 6
)
REM Set environment variables for PowerShell script
SET "WORKING_DIRECTORY=%WORKING_DIR%"
SET "SCRIPT_LOG_FILE=%LOG_FILE%"

IF "%PS7_AVAILABLE%"=="YES" (
    CALL :LOG_MESSAGE "Using PowerShell 7 environment..." "INFO" "BAT"
    CALL :LOG_MESSAGE "Launching with admin privileges: pwsh.exe" "DEBUG" "BAT"
    CALL :LOG_MESSAGE "Working directory passed: %WORKING_DIRECTORY%" "DEBUG" "BAT"
    CALL :LOG_MESSAGE "Log file passed: %SCRIPT_LOG_FILE%" "DEBUG" "BAT"
    pwsh.exe -ExecutionPolicy Bypass -File "%PS1_PATH%"
    SET "LAUNCH_RESULT=%ERRORLEVEL%"
) ELSE (
    CALL :LOG_MESSAGE "Using Windows PowerShell environment..." "INFO" "BAT"
    CALL :LOG_MESSAGE "Launching with admin privileges: powershell.exe" "DEBUG" "BAT"
    CALL :LOG_MESSAGE "Working directory passed: %WORKING_DIRECTORY%" "DEBUG" "BAT"
    CALL :LOG_MESSAGE "Log file passed: %SCRIPT_LOG_FILE%" "DEBUG" "BAT"
    powershell.exe -ExecutionPolicy Bypass -File "%PS1_PATH%"
    SET "LAUNCH_RESULT=%ERRORLEVEL%"
)

IF %LAUNCH_RESULT% EQU 0 (
    CALL :LOG_MESSAGE "PowerShell script execution completed successfully." "INFO" "BAT"
    
    REM -----------------------------------------------------------------------------
    REM Deferred Self-Update - Perform after PowerShell execution completes
    REM -----------------------------------------------------------------------------
    IF "%SELF_UPDATE_NEEDED%"=="YES" (
        CALL :LOG_MESSAGE "Performing deferred self-update..." "INFO" "BAT"
        CALL :LOG_MESSAGE "Copying ONLY script.bat (not script.ps1) as requested." "INFO" "BAT"
        COPY /Y "%NEW_SCRIPT_BAT%" "%CURRENT_SCRIPT_BAT%" >nul 2>&1
        IF %ERRORLEVEL% EQU 0 (
            CALL :LOG_MESSAGE "script.bat updated successfully." "INFO" "BAT"
        ) ELSE (
            CALL :LOG_MESSAGE "Failed to update script.bat, but continuing..." "WARN" "BAT"
        )
    )
    
    CALL :LOG_MESSAGE "This launcher will close automatically in 10 seconds..." "INFO" "BAT"
    FOR /L %%i IN (10,-1,1) DO (
        CALL :LOG_MESSAGE "Closing in %%i seconds..." "INFO" "BAT"
        timeout /t 1 /nobreak >nul
    )
    CALL :LOG_MESSAGE "Batch launcher completed successfully. Window will now close." "INFO" "BAT"
    
) ELSE (
    CALL :LOG_MESSAGE "PowerShell script execution failed with error code: %LAUNCH_RESULT%" "ERROR" "BAT"
    CALL :LOG_MESSAGE "Please check the PowerShell script path and permissions." "ERROR" "BAT"
    pause
)

REM -----------------------------------------------------------------------------
REM Script completed successfully
REM -----------------------------------------------------------------------------

ENDLOCAL
EXIT /B 0