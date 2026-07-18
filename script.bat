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

REM Use DELAYED expansion (!LOG_ENTRY!) for the echoed text: with %LOG_ENTRY% the value is
REM substituted at parse time, so any >, <, & or | inside a message is treated as a shell
REM operator. That silently truncated messages and created stray files
REM (e.g. "...allocation is sufficient (5 GB >= 10 GB)" echoed only "...sufficient (5 GB").
REM Delayed expansion substitutes AFTER parsing, so the text stays literal.
REM Console shows INFO/SUCCESS/WARN/ERROR; DEBUG goes to maintenance.log only.
IF /I NOT "%LEVEL%"=="DEBUG" ECHO !LOG_ENTRY!
IF EXIST "%LOG_FILE%" ECHO !LOG_ENTRY!>>"%LOG_FILE%" 2>nul
EXIT /B

:REFRESH_TOOL_PATHS
REM Make freshly-installed tools reachable by APPENDING their known install directories
REM to the CURRENT PATH.
REM
REM Do NOT rebuild PATH from the registry. HKLM/HKCU PATH are REG_EXPAND_SZ values holding
REM unexpanded placeholders (e.g. "%SystemRoot%\system32"). REG QUERY returns that text
REM verbatim, and assigning it to PATH leaves literal "%SystemRoot%" entries Windows cannot
REM resolve - which silently breaks EVERY command, including powershell.exe and pwsh.exe.
REM (That is exactly what happened: a PATH "refresh" after installing PS7 wiped the PATH,
REM  causing the Chocolatey/MSI fallbacks, PSWindowsUpdate, Defender exclusions and all
REM  PS7 detection to fail with "'powershell' is not recognized".)
REM Appending known-good absolute directories can never destroy a working PATH.
IF EXIST "%ProgramFiles%\PowerShell\7\pwsh.exe" SET "PATH=%PATH%;%ProgramFiles%\PowerShell\7"
IF EXIST "%ProgramData%\chocolatey\bin\choco.exe" SET "PATH=%PATH%;%ProgramData%\chocolatey\bin"
IF EXIST "%LocalAppData%\Microsoft\WindowsApps\pwsh.exe" SET "PATH=%PATH%;%LocalAppData%\Microsoft\WindowsApps"
EXIT /B

:FIND_PWSH
REM Locate a usable PowerShell 7+ and set PWSH_PATH (empty when none is usable).
REM
REM Batch PATH probing alone cannot find every install shape:
REM   * PATH is stale in this session right after an install.
REM   * A Store / winget "msstore" install puts the real binary under
REM     Program Files\WindowsApps and only exposes a per-user App Execution Alias.
REM   * Side-by-side installs are not always under ...\PowerShell\7\.
REM So we hand the search to Windows PowerShell 5.1 (always present): it collects every
REM candidate (PATH, MSI/ZIP/Chocolatey dirs, the AppX package InstallLocation, the alias)
REM and VALIDATES each by running it and requiring PSVersion.Major >= 7. First hit wins.
REM
REM BATCH ESCAPING RULES for the line below - do not "tidy" these away:
REM   * The PowerShell code sits inside a double-quoted -Command argument, so cmd already
REM     protects | & > inside it. Adding ^ escapes there would pass a LITERAL ^ to
REM     PowerShell and break its syntax (that made this return nothing every time).
REM   * It therefore uses NO carets and NO pipes at all (foreach loops instead), and only
REM     single quotes, no % and no ! - so batch parsing and delayed expansion leave it intact.
REM   * The trailing 2^>nul IS outside the quotes and must stay escaped for FOR /F.
SET "PWSH_PATH="
FOR /F "usebackq delims=" %%i IN (`powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='SilentlyContinue'; $c=@(); $g=@(Get-Command pwsh.exe -CommandType Application -EA 0); if($g.Count -gt 0){$c+=$g[0].Source}; foreach($r in @((Join-Path $env:ProgramFiles 'PowerShell'),(Join-Path $env:LOCALAPPDATA 'Microsoft\powershell'),(Join-Path $env:ProgramData 'chocolatey\lib\powershell-core\tools'))){ if($r -and (Test-Path $r)){ foreach($f in @(Get-ChildItem $r -Filter pwsh.exe -Recurse -EA 0)){ $c+=$f.FullName } } }; foreach($a in @(Get-AppxPackage -Name Microsoft.PowerShell -EA 0)){ if($a.InstallLocation){ $c+=(Join-Path $a.InstallLocation 'pwsh.exe') } }; $c+=(Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\pwsh.exe'); foreach($p in $c){ if($p -and (Test-Path $p)){ $v=(& $p -NoProfile -NoLogo -Command '$PSVersionTable.PSVersion.Major'); if($v -and [int]$v -ge 7){ Write-Output $p; break } } }" 2^>nul`) DO SET "PWSH_PATH=%%i"
EXIT /B

:INIT_LOG
REM Append a session banner to %LOG_FILE% (creates the file if it does not exist).
REM Append mode means elevation/PS7 relaunches continue the same maintenance.log.
FOR /F "tokens=1-4 delims=/ " %%A IN ('DATE /T') DO SET "BANNER_DATE=%%A %%B %%C %%D"
FOR /F "tokens=1-2 delims=/:" %%A IN ('TIME /T') DO SET "BANNER_TIME=%%A:%%B"
(
    ECHO.
    ECHO ================================================
    ECHO  Windows Maintenance Automation - Launcher
    ECHO  Session: %COMPUTERNAME% \ %USERNAME%
    ECHO  Date: %BANNER_DATE%  Time: %BANNER_TIME%
    ECHO ================================================
) >> "%LOG_FILE%" 2>nul
EXIT /B

:MIGRATE_LOG
REM Move maintenance.log from next-to-script.bat into the extracted repo's
REM temp_files\logs and repoint LOG_FILE so the rest of the launcher (and then the
REM orchestrator) keep writing to the same file in its permanent location.
SET "MAINT_LOG_DEST_DIR=%EXTRACTED_PATH%\temp_files\logs"
IF NOT EXIST "%MAINT_LOG_DEST_DIR%" MKDIR "%MAINT_LOG_DEST_DIR%" >nul 2>&1
SET "MAINT_LOG_DEST=%MAINT_LOG_DEST_DIR%\maintenance.log"
IF EXIST "%LOG_FILE%" MOVE /Y "%LOG_FILE%" "%MAINT_LOG_DEST%" >nul 2>&1
SET "LOG_FILE=%MAINT_LOG_DEST%"
CALL :LOG_MESSAGE "maintenance.log migrated to: %LOG_FILE%" "INFO" "LAUNCHER"
EXIT /B

:MAIN_SCRIPT

REM -----------------------------------------------------------------------------
REM Self-Discovery Environment Setup
REM -----------------------------------------------------------------------------
REM Path detection FIRST - needed to place maintenance.log next to script.bat.
SET "SCRIPT_PATH=%~f0"
SET "SCRIPT_DIR=%~dp0"
SET "SCRIPT_NAME=%~nx0"
SET "WORKING_DIR=%SCRIPT_DIR%"

REM Store original script directory BEFORE any updates (log location + report copy target)
SET "ORIGINAL_SCRIPT_DIR=%SCRIPT_DIR%"

REM -----------------------------------------------------------------------------
REM Unified maintenance.log - created next to script.bat immediately so the whole run
REM is captured from launch. After extraction it is migrated into temp_files\logs
REM (see :MIGRATE_LOG) and both the launcher and orchestrator keep appending to it.
REM -----------------------------------------------------------------------------
SET "LOG_FILE=%ORIGINAL_SCRIPT_DIR%maintenance.log"
CALL :INIT_LOG

CALL :LOG_MESSAGE "Starting Windows Maintenance Automation Launcher v2.0" "INFO" "LAUNCHER"
CALL :LOG_MESSAGE "Environment: %USERNAME%@%COMPUTERNAME%" "INFO" "LAUNCHER"
CALL :LOG_MESSAGE "Original script directory stored: %ORIGINAL_SCRIPT_DIR%" "DEBUG" "LAUNCHER"
CALL :LOG_MESSAGE "maintenance.log created next to script.bat: %LOG_FILE%" "INFO" "LAUNCHER"

REM Robust Script Path Detection for Scheduled Tasks (use the exact running script path)
SET "SCHEDULED_TASK_SCRIPT_PATH="
IF EXIST "%SCRIPT_PATH%" (
    SET "SCHEDULED_TASK_SCRIPT_PATH=%SCRIPT_PATH%"
    CALL :LOG_MESSAGE "Scheduled tasks will use current script path: !SCHEDULED_TASK_SCRIPT_PATH!" "DEBUG" "LAUNCHER"
)
IF NOT DEFINED SCHEDULED_TASK_SCRIPT_PATH IF EXIST "%SCRIPT_DIR%script.bat" (
    SET "SCHEDULED_TASK_SCRIPT_PATH=%SCRIPT_DIR%script.bat"
    CALL :LOG_MESSAGE "Scheduled tasks will use directory script path: !SCHEDULED_TASK_SCRIPT_PATH!" "DEBUG" "LAUNCHER"
)
IF NOT DEFINED SCHEDULED_TASK_SCRIPT_PATH (
    SET "SCHEDULED_TASK_SCRIPT_PATH=%SCRIPT_PATH%"
    CALL :LOG_MESSAGE "Using fallback script path for scheduled tasks: !SCHEDULED_TASK_SCRIPT_PATH!" "WARN" "LAUNCHER"
)

REM Detect if running from a network location
IF "%SCRIPT_PATH:~0,2%"=="\\" (
    SET "IS_NETWORK_LOCATION=YES"
    CALL :LOG_MESSAGE "Running from network location: %SCRIPT_PATH%" "INFO" "LAUNCHER"
) ELSE (
    SET "IS_NETWORK_LOCATION=NO"
    CALL :LOG_MESSAGE "Running from local location: %SCRIPT_PATH%" "INFO" "LAUNCHER"
)

REM Environment variables for PowerShell orchestrator (maintenance.log already open above).
REM (WORKING_DIRECTORY removed - it was assigned here and again after extraction but read by
REM  nothing; the orchestrator derives its own root from $PSScriptRoot.)
SET "SCRIPT_LOG_FILE=%LOG_FILE%"

REM Repository configuration for auto-updates
REM Extraction target is a stable per-machine location, NOT next to script.bat:
REM   - Keeps OneDrive/Desktop (or any synced folder) from seeing the working tree,
REM     logs, or reports mid-run - no sync-lock fights when Stage 5 deletes it.
REM   - Makes the Stage-5 delete target unambiguous and independent of where the
REM     user double-clicked script.bat from.
REM   - USB-stick / network launches still work unchanged: ORIGINAL_SCRIPT_DIR keeps
REM     pointing at the launch folder, and the HTML report is still copied back there.
SET "REPO_URL=https://github.com/ichimbogdancristian/script_mentenanta/archive/refs/heads/master.zip"
SET "EXTRACT_ROOT=%ProgramData%\WindowsMaintenance"
SET "ZIP_FILE=%EXTRACT_ROOT%\update.zip"
SET "EXTRACT_FOLDER=script_mentenanta-master"
IF NOT EXIST "%EXTRACT_ROOT%" MKDIR "%EXTRACT_ROOT%" >nul 2>&1

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
    powershell -Command "Start-Process cmd -ArgumentList '/c \"%~f0\" %*' -Verb RunAs -WindowStyle Normal"
    IF !ERRORLEVEL! NEQ 0 (
        CALL :LOG_MESSAGE "Elevation failed or was cancelled by user" "ERROR" "LAUNCHER"
        TIMEOUT /T 20 >nul 2>&1   & REM was PAUSE - must not block unattended runs
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

REM Detect pending restart from Windows Update authoritative signals only (Win10/11)
CALL :LOG_MESSAGE "Checking for pending Windows Update restart status..." "INFO" "LAUNCHER"
CALL :LOG_MESSAGE "Reboot detection version: 3.2.0 (authoritative WU markers only - boot loop fix)" "DEBUG" "LAUNCHER"
SET "RESTART_NEEDED=NO"
SET "RESTART_SIGNALS="
SET "RESTART_NEEDED_WU=NO"
SET "RESTART_SIGNALS_WU="

REM FIX: Reboot guard functionality removed per user request

REM PSWindowsUpdate-based probe removed: on the fresh machines this launcher targets,
REM PSWindowsUpdate is not installed yet at this point (it is installed later, in
REM Dependency Management), so the probe always fell through to "not available" and
REM cost 2-15s doing nothing. The registry markers below are already the authoritative
REM signals per this script's own design - detect from them directly.

REM Windows Update-specific registry checks (authoritative markers only)
REM -----------------------------------------------------------------------
REM CHECK 2: Windows Update Auto Update RebootRequired (most reliable)
REM Set by: WU after installing updates that require reboot
REM Cleared: Automatically after successful reboot
REM -----------------------------------------------------------------------
REG QUERY "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired" >nul 2>&1
IF !ERRORLEVEL! EQU 0 (
    SET "RESTART_NEEDED=YES"
    IF NOT DEFINED RESTART_SIGNALS (SET "RESTART_SIGNALS=WU-AutoUpdate-RebootRequired") ELSE (SET "RESTART_SIGNALS=!RESTART_SIGNALS!,WU-AutoUpdate-RebootRequired")
    SET "RESTART_NEEDED_WU=YES"
    IF NOT DEFINED RESTART_SIGNALS_WU (SET "RESTART_SIGNALS_WU=WU-AutoUpdate-RebootRequired") ELSE (SET "RESTART_SIGNALS_WU=!RESTART_SIGNALS_WU!,WU-AutoUpdate-RebootRequired")
)

REM -----------------------------------------------------------------------
REM CHECK 3: Windows Update Orchestrator RebootRequired (Win10 1903+ / Win11)
REM Set by: WaaS orchestrator - PRIMARY signal used by Windows 11 Update UI
REM Cleared: Automatically after successful reboot
REM -----------------------------------------------------------------------
REG QUERY "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Orchestrator\RebootRequired" >nul 2>&1
IF !ERRORLEVEL! EQU 0 (
    SET "RESTART_NEEDED=YES"
    IF NOT DEFINED RESTART_SIGNALS (SET "RESTART_SIGNALS=WU-Orchestrator-RebootRequired") ELSE (SET "RESTART_SIGNALS=!RESTART_SIGNALS!,WU-Orchestrator-RebootRequired")
    SET "RESTART_NEEDED_WU=YES"
    IF NOT DEFINED RESTART_SIGNALS_WU (SET "RESTART_SIGNALS_WU=WU-Orchestrator-RebootRequired") ELSE (SET "RESTART_SIGNALS_WU=!RESTART_SIGNALS_WU!,WU-Orchestrator-RebootRequired")
)

REM -----------------------------------------------------------------------
REM CHECK 4: Windows Update Orchestrator PostRebootReporting (Win10 1903+ / Win11)
REM Set by: WaaS pipeline when reboot is needed for post-reboot reporting
REM -----------------------------------------------------------------------
REG QUERY "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Orchestrator\PostRebootReporting" >nul 2>&1
IF !ERRORLEVEL! EQU 0 (
    SET "RESTART_NEEDED=YES"
    IF NOT DEFINED RESTART_SIGNALS (SET "RESTART_SIGNALS=WU-Orchestrator-PostRebootReporting") ELSE (SET "RESTART_SIGNALS=!RESTART_SIGNALS!,WU-Orchestrator-PostRebootReporting")
    SET "RESTART_NEEDED_WU=YES"
    IF NOT DEFINED RESTART_SIGNALS_WU (SET "RESTART_SIGNALS_WU=WU-Orchestrator-PostRebootReporting") ELSE (SET "RESTART_SIGNALS_WU=!RESTART_SIGNALS_WU!,WU-Orchestrator-PostRebootReporting")
)

REM -----------------------------------------------------------------------
REM REMOVED CHECKS (caused boot loops - DO NOT RE-ADD):
REM   WU\Services\Pending       - populated during downloads, not just post-install
REM   UpdateExeVolatile         - MSI/legacy installer flag, NOT a WU signal;
REM                               frequently non-zero on healthy systems (Office,
REM                               VC++ runtimes, etc.) - primary boot loop cause
REM   CBS\RebootPending         - triggered by DISM/feature installs, not WU-only
REM   PendingFileRenameOperations - set by any installer, guaranteed false positives
REM -----------------------------------------------------------------------

IF /I "%RESTART_NEEDED_WU%"=="YES" (
    IF NOT DEFINED RESTART_SIGNALS_WU SET "RESTART_SIGNALS_WU=Unknown"
    CALL :LOG_MESSAGE "Pending Windows Update restart signals detected: %RESTART_SIGNALS_WU%" "WARN" "LAUNCHER"
)

IF /I "%RESTART_NEEDED_WU%"=="YES" (
    CALL :LOG_MESSAGE "Pending Windows Update restart detected (signals: %RESTART_SIGNALS_WU%). Creating startup task and restarting..." "WARN" "LAUNCHER"

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

:AFTER_RESTART_CHECK

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
    TIMEOUT /T 20 >nul 2>&1   & REM was PAUSE - must not block unattended runs
    EXIT /B 2
)

CALL :LOG_MESSAGE "System requirements verified" "SUCCESS" "LAUNCHER"

REM -----------------------------------------------------------------------------
REM Repository Download and Extraction (Moved before structure discovery)
REM -----------------------------------------------------------------------------
:DOWNLOAD_REPOSITORY
CALL :LOG_MESSAGE "Downloading latest repository from GitHub..." "INFO" "LAUNCHER"

REM Clean up existing files (in the stable extraction root, not the launch folder)
IF EXIST "%ZIP_FILE%" DEL /Q "%ZIP_FILE%" >nul 2>&1
IF EXIST "%EXTRACT_ROOT%\%EXTRACT_FOLDER%" RMDIR /S /Q "%EXTRACT_ROOT%\%EXTRACT_FOLDER%" >nul 2>&1

REM Download repository
CALL :LOG_MESSAGE "Downloading from: %REPO_URL%" "DEBUG" "LAUNCHER"
powershell -ExecutionPolicy Bypass -Command "try { $ProgressPreference = 'SilentlyContinue'; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri '%REPO_URL%' -OutFile '%ZIP_FILE%' -UseBasicParsing; Write-Host 'DOWNLOAD_SUCCESS' } catch { Write-Host 'DOWNLOAD_FAILED'; Write-Error $_.Exception.Message; exit 1 }"

IF !ERRORLEVEL! NEQ 0 (
    CALL :LOG_MESSAGE "Repository download failed. Check internet connection." "ERROR" "LAUNCHER"
    TIMEOUT /T 20 >nul 2>&1   & REM was PAUSE - must not block unattended runs
    EXIT /B 3
)

IF NOT EXIST "%ZIP_FILE%" (
    CALL :LOG_MESSAGE "Download verification failed - ZIP file not found" "ERROR" "LAUNCHER"
    TIMEOUT /T 20 >nul 2>&1   & REM was PAUSE - must not block unattended runs
    EXIT /B 3
)

CALL :LOG_MESSAGE "Repository downloaded successfully" "SUCCESS" "LAUNCHER"

REM Extract repository
CALL :LOG_MESSAGE "Extracting repository..." "INFO" "LAUNCHER"
powershell -ExecutionPolicy Bypass -Command "try { Add-Type -AssemblyName System.IO.Compression.FileSystem; [System.IO.Compression.ZipFile]::ExtractToDirectory('%ZIP_FILE%', '%EXTRACT_ROOT%'); Write-Host 'EXTRACTION_SUCCESS' } catch { Write-Host 'EXTRACTION_FAILED'; Write-Error $_.Exception.Message; exit 1 }"

IF !ERRORLEVEL! NEQ 0 (
    CALL :LOG_MESSAGE "Repository extraction failed" "ERROR" "LAUNCHER"
    TIMEOUT /T 20 >nul 2>&1   & REM was PAUSE - must not block unattended runs
    EXIT /B 3
)

REM Verify extraction (now rooted under %EXTRACT_ROOT%, not next to script.bat)
SET "EXTRACTED_PATH=%EXTRACT_ROOT%\%EXTRACT_FOLDER%"
IF EXIST "%EXTRACTED_PATH%" (
    CALL :LOG_MESSAGE "Repository extracted to: %EXTRACTED_PATH%" "SUCCESS" "LAUNCHER"
    
    REM ---------------------------------------------------------------------------------
    REM Self-update: DEFERRED ON PURPOSE - do NOT overwrite script.bat while it is running.
    REM
    REM cmd.exe streams a .bat file from disk by BYTE OFFSET as it executes. Replacing the
    REM file mid-run makes execution resume at that same offset inside the NEW content, so
    REM it jumps into the middle of unrelated code. Observed symptoms: the launcher skipped
    REM the whole PS7-detection section, logged mutually exclusive IF/ELSE branches together,
    REM and then launched the orchestrator with an EMPTY PS_EXECUTABLE (the "crash").
    REM
    REM The orchestrator (a separate pwsh process that starts after this launcher exits)
    REM performs the copy instead - see PENDING_SCRIPT_UPDATE below.
    REM ---------------------------------------------------------------------------------
    IF EXIST "%EXTRACTED_PATH%\script.bat" (
        SET "PENDING_SCRIPT_UPDATE=%EXTRACTED_PATH%\script.bat"
        CALL :LOG_MESSAGE "script.bat self-update deferred to the orchestrator (a running .bat cannot safely overwrite itself)" "INFO" "LAUNCHER"
    ) ELSE (
        CALL :LOG_MESSAGE "No script.bat found in extracted repository" "WARN" "LAUNCHER"
    )
    
    REM Update working directory to extracted folder for proper module loading
    SET "WORKING_DIR=%EXTRACTED_PATH%\"
    CALL :LOG_MESSAGE "Updated working directory to: !WORKING_DIR!" "INFO" "LAUNCHER"

    REM Migrate maintenance.log from next-to-script.bat into temp_files\logs and keep
    REM writing there. The orchestrator appends to this same file (via MAINTENANCE_LOG).
    CALL :MIGRATE_LOG
    REM !LOG_FILE! (delayed) - %LOG_FILE% would capture the stale PRE-migration path, and the
    REM orchestrator would then open/append to the wrong maintenance.log.
    SET "SCRIPT_LOG_FILE=!LOG_FILE!"
    SET "MAINTENANCE_LOG=!LOG_FILE!"
    CALL :LOG_MESSAGE "Orchestrator will append to: !MAINTENANCE_LOG!" "DEBUG" "LAUNCHER"
    
    REM Set orchestrator path within the extracted folder
    IF EXIST "%EXTRACTED_PATH%\MaintenanceOrchestrator.ps1" (
        SET "ORCHESTRATOR_PATH=%EXTRACTED_PATH%\MaintenanceOrchestrator.ps1"
        CALL :LOG_MESSAGE "Using extracted orchestrator" "INFO" "LAUNCHER"
    ) ELSE IF EXIST "%EXTRACTED_PATH%\script.ps1" (
        SET "ORCHESTRATOR_PATH=%EXTRACTED_PATH%\script.ps1"
        CALL :LOG_MESSAGE "Using extracted legacy orchestrator" "INFO" "LAUNCHER"
    ) ELSE (
        CALL :LOG_MESSAGE "No valid orchestrator found in extracted files" "ERROR" "LAUNCHER"
        TIMEOUT /T 20 >nul 2>&1   & REM was PAUSE - must not block unattended runs
        EXIT /B 3
    )
) ELSE (
    CALL :LOG_MESSAGE "Repository extraction verification failed" "ERROR" "LAUNCHER"
    TIMEOUT /T 20 >nul 2>&1   & REM was PAUSE - must not block unattended runs
    EXIT /B 3
)

REM Clean up ZIP file
DEL /Q "%ZIP_FILE%" >nul 2>&1

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
    CALL :LOG_MESSAGE "[OK] Found orchestrator: MaintenanceOrchestrator.ps1" "SUCCESS" "LAUNCHER"
    SET /A COMPONENTS_FOUND+=1
) ELSE IF EXIST "%WORKING_DIR%script.ps1" (
    SET "ORCHESTRATOR_PATH=%WORKING_DIR%script.ps1"
    CALL :LOG_MESSAGE "[OK] Found legacy orchestrator: script.ps1" "INFO" "LAUNCHER"
    SET /A COMPONENTS_FOUND+=1
) ELSE (
    CALL :LOG_MESSAGE "[X] No PowerShell orchestrator found in current directory" "WARN" "LAUNCHER"
    SET "STRUCTURE_VALID=NO"
)

REM Check for config directory and its contents (FIX #7: Check new subdirectory structure)
IF EXIST "%WORKING_DIR%config" (
    CALL :LOG_MESSAGE "[OK] Found configuration directory" "SUCCESS" "LAUNCHER"
    SET /A COMPONENTS_FOUND+=1
    
    REM Check for settings subdirectory (execution configs)
    IF EXIST "%WORKING_DIR%config\settings" (
        CALL :LOG_MESSAGE "  [OK] config\settings directory present" "SUCCESS" "LAUNCHER"
        IF EXIST "%WORKING_DIR%config\settings\main-config.json" (
            CALL :LOG_MESSAGE "    [OK] main-config.json present" "SUCCESS" "LAUNCHER"
        ) ELSE (
            CALL :LOG_MESSAGE "    [X] main-config.json missing" "WARN" "LAUNCHER"
        )
    ) ELSE (
        CALL :LOG_MESSAGE "  [X] config\settings directory not found" "WARN" "LAUNCHER"
    )
    
    REM Check for lists subdirectory (data lists)
    IF EXIST "%WORKING_DIR%config\lists" (
        CALL :LOG_MESSAGE "  [OK] config\lists directory present" "SUCCESS" "LAUNCHER"
        IF EXIST "%WORKING_DIR%config\lists\bloatware\bloatware-list.json" (
            CALL :LOG_MESSAGE "    [OK] bloatware-list.json present" "SUCCESS" "LAUNCHER"
        ) ELSE (
            CALL :LOG_MESSAGE "    [X] bloatware-list.json missing" "WARN" "LAUNCHER"
        )
    ) ELSE (
        CALL :LOG_MESSAGE "  [X] config\lists directory not found" "WARN" "LAUNCHER"
    )
) ELSE (
    CALL :LOG_MESSAGE "[X] Configuration directory not found" "WARN" "LAUNCHER"
    SET "STRUCTURE_VALID=NO"
)

REM Check for modules directory and core modules
IF EXIST "%WORKING_DIR%modules" (
    CALL :LOG_MESSAGE "[OK] Found modules directory" "SUCCESS" "LAUNCHER"
    SET /A COMPONENTS_FOUND+=1
    
    IF EXIST "%WORKING_DIR%modules\core" (
        CALL :LOG_MESSAGE "  [OK] Core modules directory present" "SUCCESS" "LAUNCHER"
    ) ELSE (
        CALL :LOG_MESSAGE "  [X] Core modules directory missing" "WARN" "LAUNCHER"
    )
    
    IF EXIST "%WORKING_DIR%modules\type1" (
        CALL :LOG_MESSAGE "  [OK] Type1 modules directory present" "SUCCESS" "LAUNCHER"
    ) ELSE (
        CALL :LOG_MESSAGE "  [X] Type1 modules directory missing" "WARN" "LAUNCHER"
    )
    
    IF EXIST "%WORKING_DIR%modules\type2" (
        CALL :LOG_MESSAGE "  [OK] Type2 modules directory present" "SUCCESS" "LAUNCHER"
    ) ELSE (
        CALL :LOG_MESSAGE "  [X] Type2 modules directory missing" "WARN" "LAUNCHER"
    )
) ELSE (
    CALL :LOG_MESSAGE "[X] Modules directory not found" "WARN" "LAUNCHER"
    SET "STRUCTURE_VALID=NO"
)

CALL :LOG_MESSAGE "Project structure verification: %COMPONENTS_FOUND%/3 major components found" "INFO" "LAUNCHER"

IF "%STRUCTURE_VALID%"=="NO" (
    CALL :LOG_MESSAGE "Project structure incomplete but repository already downloaded. Check extraction." "ERROR" "LAUNCHER"
    TIMEOUT /T 20 >nul 2>&1   & REM was PAUSE - must not block unattended runs
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
                    powershell -NoProfile -ExecutionPolicy Bypass -Command "try { $ProgressPreference='SilentlyContinue'; Write-Host 'Trying fallback URL 2 (GitHub API latest)...'; $headers=@{'User-Agent'='WinMaintLauncher'}; $rel=Invoke-RestMethod -Headers $headers -Uri 'https://api.github.com/repos/microsoft/winget-cli/releases/latest' -TimeoutSec 30; $asset=$rel.assets | Where-Object { $_.name -match 'msixbundle$' } | Select-Object -First 1; if(-not $asset){ Write-Host 'FALLBACK2_ASSET_NOT_FOUND'; exit 2 }; Invoke-WebRequest -Headers $headers -Uri $asset.browser_download_url -OutFile '%WORKING_DIR%AppInstaller.msixbundle' -UseBasicParsing -TimeoutSec 60; Write-Host 'FALLBACK2_MSIX_DOWNLOADED' } catch { Write-Host 'FALLBACK2_MSIX_FAILED'; Write-Host $_.Exception.Message; exit 1 }" >nul 2>&1
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
        
        REM !WINGET_AVAILABLE! (delayed): WINGET_AVAILABLE is re-assigned above inside this same
        REM block, so a %-read here resolves at parse time to the enclosing block's "NO" and this
        REM warning fired even when winget had just been installed successfully.
        IF "!WINGET_AVAILABLE!"=="NO" (
            CALL :LOG_MESSAGE "All winget installation methods failed" "WARN" "LAUNCHER"
        )
    )

REM -----------------------------------------------------------------------------
REM PowerShell 7 Detection and Installation (Moved after winget setup)
REM -----------------------------------------------------------------------------
CALL :LOG_MESSAGE "Checking PowerShell 7 availability..." "INFO" "LAUNCHER"

REM One robust locator (see :FIND_PWSH) replaces the old PATH/known-path probes, which
REM could not see a Store/MSIX install and so reported "not found" with PS7 installed.
SET "PS7_FOUND=NO"
CALL :FIND_PWSH
IF DEFINED PWSH_PATH (
    SET "PS7_FOUND=YES"
    CALL :LOG_MESSAGE "PowerShell 7 found: !PWSH_PATH! - skipping installation" "SUCCESS" "LAUNCHER"
)

IF "%PS7_FOUND%"=="NO" (
    CALL :LOG_MESSAGE "PowerShell 7 not found. Attempting installation..." "INFO" "LAUNCHER"
    SET "INSTALL_STATUS=FAILED"
    SET "WINGET_LOG=%WORKING_DIR%winget-pwsh-install.log"

    REM 1) Try installing PowerShell via winget (if available)
    IF "%WINGET_AVAILABLE%"=="YES" (
        CALL :LOG_MESSAGE "Installing PowerShell 7 via winget..." "INFO" "LAUNCHER"
        REM --source winget --exact is REQUIRED: without it winget may resolve to the
        REM msstore package, which installs an MSIX into WindowsApps instead of the MSI in
        REM "%ProgramFiles%\PowerShell\7" - and then none of the detection paths find pwsh.exe.
        "%WINGET_EXE%" install --id Microsoft.PowerShell --source winget --exact --silent --accept-package-agreements --accept-source-agreements
        IF !ERRORLEVEL! EQU 0 (
            CALL :LOG_MESSAGE "PowerShell 7 installed successfully via winget" "SUCCESS" "LAUNCHER"
            SET "INSTALL_STATUS=SUCCESS"
            SET "PS7_FOUND=YES"
            
            REM Refresh PATH environment to pick up newly installed PowerShell
            CALL :LOG_MESSAGE "Refreshing PATH environment after PowerShell 7 installation..." "DEBUG" "LAUNCHER"
            CALL :REFRESH_TOOL_PATHS
        ) ELSE (
            CALL :LOG_MESSAGE "PowerShell 7 installation via winget failed" "WARN" "LAUNCHER"
        )
    ) ELSE (
        CALL :LOG_MESSAGE "Winget not available for PowerShell 7 installation" "WARN" "LAUNCHER"
    )

    REM 2) Try Chocolatey (prioritize existing installation or install it first)
    IF NOT "!INSTALL_STATUS!"=="SUCCESS" (
        REM Check if Chocolatey is available.
        REM !CHOCO_EXE! (delayed) is REQUIRED: CHOCO_EXE is assigned inside this same block, so a
        REM %CHOCO_EXE% read resolves at PARSE time - before the SET runs - and expands to EMPTY.
        REM That turned every probe into `"" --version`, which always fails, so this whole
        REM Chocolatey path was dead and always reported "Chocolatey not available".
        SET "CHOCO_EXE=choco"
        IF EXIST "%ProgramData%\chocolatey\bin\choco.exe" SET "CHOCO_EXE=%ProgramData%\chocolatey\bin\choco.exe"

        "!CHOCO_EXE!" --version >nul 2>&1
        IF !ERRORLEVEL! EQU 0 (
            CALL :LOG_MESSAGE "Chocolatey found - installing PowerShell 7..." "INFO" "LAUNCHER"
            "!CHOCO_EXE!" install powershell-core -y --no-progress
            IF !ERRORLEVEL! EQU 0 (
                CALL :LOG_MESSAGE "PowerShell 7 installed successfully via Chocolatey" "SUCCESS" "LAUNCHER"
                SET "INSTALL_STATUS=SUCCESS"
                SET "PS7_FOUND=YES"
                
                REM Refresh PATH after installation
                CALL :LOG_MESSAGE "Refreshing PATH after PowerShell 7 installation..." "DEBUG" "LAUNCHER"
                CALL :REFRESH_TOOL_PATHS
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
                "!CHOCO_EXE!" install powershell-core -y --no-progress
                IF !ERRORLEVEL! EQU 0 (
                    CALL :LOG_MESSAGE "PowerShell 7 installed successfully via newly installed Chocolatey" "SUCCESS" "LAUNCHER"
                    SET "INSTALL_STATUS=SUCCESS"
                    SET "PS7_FOUND=YES"
                    
                    REM Refresh PATH after installation
                    CALL :LOG_MESSAGE "Refreshing PATH after PowerShell 7 installation..." "DEBUG" "LAUNCHER"
                    CALL :REFRESH_TOOL_PATHS
                ) ELSE (
                    CALL :LOG_MESSAGE "PowerShell 7 installation failed even with fresh Chocolatey" "WARN" "LAUNCHER"
                )
            ) ELSE (
                CALL :LOG_MESSAGE "Chocolatey installation failed - proceeding to MSI fallback for PowerShell 7" "WARN" "LAUNCHER"
            )
        )
    )

    REM 3) MSI fallback from GitHub Releases (latest stable PowerShell)
    IF NOT "!INSTALL_STATUS!"=="SUCCESS" (
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

    REM Post-install verification: re-run the full locator (handles MSI, Store/MSIX, alias,
    REM Chocolatey and registry installs). If it resolves we continue in THIS process - no
    REM relaunch, which also avoids a second download/extract cycle.
    IF "!INSTALL_STATUS!"=="SUCCESS" (
        CALL :FIND_PWSH
        IF DEFINED PWSH_PATH (
            SET "PS7_FOUND=YES"
            CALL :LOG_MESSAGE "PowerShell 7 installed and reachable: !PWSH_PATH! - continuing" "SUCCESS" "LAUNCHER"
        ) ELSE (
            CALL :LOG_MESSAGE "Restarting script with fresh environment to detect PowerShell 7..." "INFO" "LAUNCHER"

            REM Preserve the log across the relaunch: copy it back next to script.bat so the
            REM new instance's :INIT_LOG appends to it (the relaunched instance wipes and
            REM re-extracts the repo folder, taking the migrated copy with it).
            IF EXIST "!LOG_FILE!" COPY /Y "!LOG_FILE!" "%ORIGINAL_SCRIPT_DIR%maintenance.log" >nul 2>&1

            REM Create restart flag with timestamp to prevent infinite loops
            ECHO POWERSHELL_RESTART_%DATE:~-4,4%%DATE:~-10,2%%DATE:~-7,2%_%TIME:~0,2%%TIME:~3,2%%TIME:~6,2% > "%WORKING_DIR%restart_flag.tmp"

            REM Restart the script with a fresh environment (give Windows a moment to update PATH).
            REM No /WAIT: the relaunched instance takes over, so this window must close instead
            REM of sitting idle behind it until the whole run finishes.
            TIMEOUT /T 3 /NOBREAK >nul 2>&1
            START "" cmd.exe /C ""%SCRIPT_PATH%" %*"

            REM Hand off to the new instance and close this window
            EXIT /B 0
        )
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
    CALL :LOG_MESSAGE "PowerShell 7 available: !PS7_VERSION!" "SUCCESS" "LAUNCHER"
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

REM NOTE: winget/Chocolatey re-verification and the monthly/startup scheduled-task
REM status pass used to be repeated here - both were exact duplicates of the checks
REM already done in Dependency Management (winget) and at script start / :MAIN_SCRIPT
REM (scheduled tasks). Removed; nothing downstream reads WINGET_VERSION/CHOCO_VERSION.

REM -----------------------------------------------------------------------------
REM PowerShell Executable Selection (before system operations)
REM -----------------------------------------------------------------------------
CALL :LOG_MESSAGE "Detecting PowerShell executable for system operations..." "INFO" "LAUNCHER"

SET "PS_EXECUTABLE="
SET "AUTO_NONINTERACTIVE=NO"

REM Single source of truth: :FIND_PWSH validates every candidate by running it, so anything
REM it returns is a working PowerShell 7+. This replaces six brittle probes (default path /
REM PATH / extra paths / where / registry / PATH scan) that could not see a Store-MSIX
REM install and aborted the run with "PowerShell 7+ not found" while PS7 was installed.
REM
REM PWSH_PATH is REUSED here rather than re-probed: it was already resolved either by the
REM initial availability check above, or (if PS7 had to be installed) by the post-install
REM verification's own :FIND_PWSH call - both set PWSH_PATH in this same environment (CALL
REM does not create a new variable scope). Re-running the full probe a third time here
REM cost 3-8s for a result we already have. Only fall back to a fresh probe if PWSH_PATH is
REM somehow still empty (e.g. a code path above that didn't resolve one).
IF DEFINED PWSH_PATH (
    SET "PS_EXECUTABLE=!PWSH_PATH!"
    SET "AUTO_NONINTERACTIVE=YES"
    CALL :LOG_MESSAGE "Using PowerShell 7+ (already resolved): !PWSH_PATH!" "SUCCESS" "LAUNCHER"
) ELSE (
    REM PWSH_PATH still unresolved - refresh PATH and probe once more (handles a stale
    REM WindowsApps alias immediately after install)
    CALL :LOG_MESSAGE "PowerShell 7+ not resolved yet, refreshing PATH and retrying..." "WARN" "LAUNCHER"
    CALL :REFRESH_TOOL_PATHS
    CALL :FIND_PWSH

    IF DEFINED PWSH_PATH (
        SET "PS_EXECUTABLE=!PWSH_PATH!"
        SET "AUTO_NONINTERACTIVE=YES"
        CALL :LOG_MESSAGE "Using PowerShell 7+ (found after PATH refresh): !PWSH_PATH!" "SUCCESS" "LAUNCHER"
    ) ELSE (
        REM Final fallback: check known installation path directly
        IF EXIST "C:\Program Files\PowerShell\7\pwsh.exe" (
            SET "PS_EXECUTABLE=C:\Program Files\PowerShell\7\pwsh.exe"
            SET "AUTO_NONINTERACTIVE=YES"
            CALL :LOG_MESSAGE "Using PowerShell 7+ (direct path fallback): !PS_EXECUTABLE!" "SUCCESS" "LAUNCHER"
        ) ELSE (
            CALL :LOG_MESSAGE "CRITICAL: no usable PowerShell 7+ found after install attempts" "ERROR" "LAUNCHER"
            CALL :LOG_MESSAGE "The orchestrator requires PS7+; Windows PowerShell 5.1 cannot run it." "ERROR" "LAUNCHER"
            CALL :LOG_MESSAGE "Install manually: winget install --id Microsoft.PowerShell --source winget" "ERROR" "LAUNCHER"
            CALL :LOG_MESSAGE "  or download from https://github.com/PowerShell/PowerShell/releases" "ERROR" "LAUNCHER"
            REM No PAUSE here: a PAUSE blocks an unattended/scheduled run forever. Short timeout so
            REM an interactive user can read the error, then exit with a failure code.
            TIMEOUT /T 20 >nul 2>&1
            EXIT /B 1
        )
    )
)

REM -----------------------------------------------------------------------------
REM System Restore Point Creation (before orchestrator execution)
REM Includes: Availability check, space allocation (minimum 10GB), and creation
REM DEFENSIVE: Verify PS_EXECUTABLE is actually set and accessible before using it
REM -----------------------------------------------------------------------------
IF NOT DEFINED PS_EXECUTABLE (
    CALL :LOG_MESSAGE "System Protection check failed (PowerShell not available) - skipping restore point" "WARN" "LAUNCHER"
    GOTO SKIP_RESTORE_POINT
)

IF NOT EXIST "%PS_EXECUTABLE%" (
    CALL :LOG_MESSAGE "System Protection check failed (PowerShell executable not found) - skipping restore point" "WARN" "LAUNCHER"
    GOTO SKIP_RESTORE_POINT
)

CALL :LOG_MESSAGE "Checking System Protection status..." "INFO" "LAUNCHER"

SET "SYS_DRIVE=%SystemDrive%"
SET "SR_STATUS=UNKNOWN"
SET "SR_VERIFY_STATUS=UNKNOWN"
SET "MIN_RESTORE_SPACE_GB=10"

REM Simple check for System Protection availability
FOR /F "usebackq tokens=* delims=" %%i IN (`"%PS_EXECUTABLE%" -NoProfile -ExecutionPolicy Bypass -Command "try { $ErrorActionPreference='Stop'; if (Get-Command 'Get-ComputerRestorePoint' -ErrorAction SilentlyContinue) { try { $rp = Get-ComputerRestorePoint -ErrorAction SilentlyContinue; Write-Host 'SR_AVAILABLE' } catch { Write-Host 'SR_ERROR' } } else { Write-Host 'SR_NOT_SUPPORTED' } } catch { Write-Host 'SR_FAILED' }" 2^>nul`) DO SET "SR_CHECK=%%i"

REM Check and allocate System Restore Point space (minimum 10GB)
IF /I "!SR_CHECK!"=="SR_AVAILABLE" (
    CALL :LOG_MESSAGE "Checking System Protection disk space allocation..." "INFO" "LAUNCHER"
    
    REM Use vssadmin to check current shadow storage allocation (modern method)
    FOR /F "usebackq tokens=* delims=" %%i IN (`"%PS_EXECUTABLE%" -NoProfile -ExecutionPolicy Bypass -Command "try { $vssOutput = & vssadmin list shadowstorage 2>&1 | Out-String; if ($vssOutput -match 'Maximum Shadow Copy Storage space.*?([0-9.]+)\s*(GB|MB|TB)') { $size = [decimal]$matches[1]; $unit = $matches[2]; $sizeGB = switch ($unit) { 'TB' { $size * 1024 } 'GB' { $size } 'MB' { $size / 1024 } default { 0 } }; Write-Host ('CURRENT:' + [math]::Round($sizeGB, 2)) } elseif ($vssOutput -match 'UNBOUNDED|No.*found') { Write-Host 'UNBOUNDED' } else { Write-Host 'NO_CONFIG' } } catch { Write-Host 'ERROR' }" 2^>nul`) DO SET "SR_SPACE_CHECK=%%i"
    
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

REM Only create a new restore point if the most recent existing one is older than the
REM threshold - Checkpoint-Computer is throttled by Windows to one per ~24h by default
REM anyway, and there is no value in re-running the (slow, WinPS-compat-routed) creation
REM flow when a recent enough snapshot already exists.
SET "MIN_RESTORE_AGE_HOURS=96"
SET "RP_AGE_CHECK=RP_NONE"
FOR /F "usebackq tokens=* delims=" %%i IN (`%PS_EXECUTABLE% -NoProfile -ExecutionPolicy Bypass -Command "try { $rps = @(Get-ComputerRestorePoint -ErrorAction Stop); if ($rps.Count -eq 0) { Write-Host 'RP_NONE' } else { $latest = $rps | Sort-Object -Property CreationTime -Descending | Select-Object -First 1; $ct = $latest.CreationTime; if ($ct -isnot [datetime]) { $ct = [System.Management.ManagementDateTimeConverter]::ToDateTime($ct) }; $ageH = [math]::Round(((Get-Date) - $ct).TotalHours, 1); Write-Host ('RP_AGE:' + $ageH) } } catch { Write-Host 'RP_CHECK_FAILED' }" 2^>nul`) DO SET "RP_AGE_CHECK=%%i"

SET "SKIP_RP_CREATE=NO"
IF "!RP_AGE_CHECK:~0,7!"=="RP_AGE:" (
    SET "RP_AGE_HOURS=!RP_AGE_CHECK:~7!"
    FOR /F "tokens=1 delims=." %%a IN ("!RP_AGE_HOURS!") DO SET "RP_AGE_HOURS_INT=%%a"
    IF !RP_AGE_HOURS_INT! LSS !MIN_RESTORE_AGE_HOURS! (
        CALL :LOG_MESSAGE "Most recent restore point is !RP_AGE_HOURS! hour(s) old (below !MIN_RESTORE_AGE_HOURS!h threshold) - skipping creation" "INFO" "LAUNCHER"
        SET "SKIP_RP_CREATE=YES"
    ) ELSE (
        CALL :LOG_MESSAGE "Most recent restore point is !RP_AGE_HOURS! hour(s) old (>= !MIN_RESTORE_AGE_HOURS!h threshold) - creating a new one" "INFO" "LAUNCHER"
    )
) ELSE (
    CALL :LOG_MESSAGE "No prior restore point found or age check inconclusive (!RP_AGE_CHECK!) - creating one" "INFO" "LAUNCHER"
)

IF /I "!SKIP_RP_CREATE!"=="YES" GOTO :SKIP_RESTORE_POINT

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
    TIMEOUT /T 20 >nul 2>&1   & REM was PAUSE - must not block unattended runs
    EXIT /B 4
)

CALL :LOG_MESSAGE "Orchestrator path: %ORCHESTRATOR_PATH%" "DEBUG" "LAUNCHER"

REM Verify orchestrator file exists
IF NOT EXIST "%ORCHESTRATOR_PATH%" (
    CALL :LOG_MESSAGE "Orchestrator file not found: %ORCHESTRATOR_PATH%" "ERROR" "LAUNCHER"
    TIMEOUT /T 20 >nul 2>&1   & REM was PAUSE - must not block unattended runs
    EXIT /B 4
)

REM Check if we have PowerShell 7+ for the orchestrator (required)
REM Use AUTO_NONINTERACTIVE as a reliable marker that PS 7+ was detected above
REM [REMOVED: Legacy PowerShell 7+ orchestrator check. Now handled by consolidated detection above.]

CALL :LOG_MESSAGE "Using PowerShell 7+ for orchestrator execution" "SUCCESS" "LAUNCHER"

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
    SET "PS_ARGS=!PS_ARGS!Write-Host 'Windows Maintenance Automation - PowerShell 7+ Mode' -ForegroundColor Green; "
    SET "PS_ARGS=!PS_ARGS!Write-Host 'Working Directory: %WORKING_DIR%' -ForegroundColor Cyan; "
    SET "PS_ARGS=!PS_ARGS!Write-Host 'Launching MaintenanceOrchestrator...' -ForegroundColor Yellow; "
    SET "PS_ARGS=!PS_ARGS!Write-Host ''; "
    
    REM Check for command line arguments to pass through
    IF "%1"=="-NonInteractive" (
        SET "PS_ARGS=!PS_ARGS!& '%ORCHESTRATOR_PATH%' -NonInteractive; "
    ) ELSE IF "%1"=="-TaskNumbers" (
        SET "PS_ARGS=!PS_ARGS!& '%ORCHESTRATOR_PATH%' -NonInteractive -TaskNumbers '%~2'; "
        CALL :LOG_MESSAGE "Forwarding task selection to orchestrator: %~2" "INFO" "LAUNCHER"
    ) ELSE (
        SET "PS_ARGS=!PS_ARGS!& '%ORCHESTRATOR_PATH%'; "
    )
    
    SET "PS_ARGS=!PS_ARGS!Write-Host ''; "
    SET "PS_ARGS=!PS_ARGS!Write-Host 'Maintenance session completed. You can close this window or run additional commands.' -ForegroundColor Green; "
    SET "PS_ARGS=!PS_ARGS!}"
    
    REM Write all remaining launcher lines BEFORE START so maintenance.log is complete
    REM (the orchestrator opens the same file in append mode via MAINTENANCE_LOG).
    CALL :LOG_MESSAGE "Launching: \"%PS_EXECUTABLE%\" !PS_ARGS!" "DEBUG" "LAUNCHER"
    CALL :LOG_MESSAGE "PowerShell 7+ window launching - batch launcher exiting" "SUCCESS" "LAUNCHER"
    CALL :LOG_MESSAGE "All further operations will run in the dedicated PowerShell window" "INFO" "LAUNCHER"
    CALL :LOG_MESSAGE "=== LAUNCHER HANDING OFF TO ORCHESTRATOR ===" "INFO" "LAUNCHER"

    REM Stop launcher file writes so nothing races the orchestrator appending to the same log
    SET "LOG_FILE="
    
    START "Windows Maintenance Automation - PowerShell 7" "%PS_EXECUTABLE%" !PS_ARGS!
    
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
    TIMEOUT /T 20 >nul 2>&1   & REM was PAUSE - must not block unattended runs
    EXIT /B 1
)

REM Batch script execution completed - PowerShell 7+ window is now handling all operations
CALL :LOG_MESSAGE "Batch launcher phase completed successfully" "SUCCESS" "LAUNCHER"

REM -----------------------------------------------------------------------------
REM End of Script
REM (Both branches above already EXIT /B, so nothing after this point ever runs.)
REM -----------------------------------------------------------------------------
ENDLOCAL
