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
REM Time-only timestamp for consistency with PowerShell modules' console format
FOR /F "tokens=1-3 delims=:. " %%a IN ("%TIME%") DO (
    SET "LOG_TIME=%%a:%%b:%%c"
)

SET "LEVEL=%~2"
IF "%LEVEL%"=="" SET "LEVEL=INFO"
SET "COMPONENT=%~3"
IF "%COMPONENT%"=="" SET "COMPONENT=LAUNCHER"

REM Unified format: [TIME] [COMPONENT] [LEVEL] MESSAGE
SET "LOG_ENTRY=[%LOG_TIME%] [%COMPONENT%] [%LEVEL%] %~1"

ECHO %LOG_ENTRY%
IF EXIST "%LOG_FILE%" ECHO %LOG_ENTRY% >> "%LOG_FILE%" 2>nul
EXIT /B

:REFRESH_PATH_FROM_REGISTRY
REM Make freshly-installed tools (pwsh / choco / winget) reachable WITHOUT clobbering the working
REM PATH. We only PREPEND the known install dirs onto the CURRENT PATH, using immediate %VAR%
REM expansion only (no delayed expansion, no registry parsing) so this can never corrupt PATH.
REM We must NOT overwrite PATH from the raw registry value: it is stored as REG_EXPAND_SZ with
REM literal %SystemRoot% tokens that batch will not re-expand, which previously made
REM powershell.exe / pwsh.exe unresolvable and cascaded into "is not recognized" for the run.
SET "PATH=%ProgramFiles%\PowerShell\7;%LocalAppData%\Microsoft\WindowsApps;%ProgramData%\chocolatey\bin;%PATH%"
EXIT /B

:VERIFY_PS7_AFTER_INSTALL
REM Called right after a PowerShell 7 install. A freshly-installed pwsh (especially the winget
REM Store/MSIX build under WindowsApps) is not always immediately resolvable, so give the system
REM time to register it: up to 3 attempts with a ~5s cooldown each, refreshing PATH before every
REM probe. Sets PS7_FOUND=YES on the first hit. Fully unattended - uses ping as a headless-safe
REM sleep (TIMEOUT cannot actually wait when stdin is redirected, e.g. under a scheduled task).
SET "PS7_FOUND=NO"
FOR /L %%R IN (1,1,3) DO (
    IF "!PS7_FOUND!"=="NO" (
        CALL :LOG_MESSAGE "Waiting 5s for PowerShell 7 registration to settle (attempt %%R/3)..." "INFO" "LAUNCHER"
        ping -n 6 127.0.0.1 >nul 2>&1
        CALL :REFRESH_PATH_FROM_REGISTRY
        IF EXIST "%ProgramFiles%\PowerShell\7\pwsh.exe" (
            SET "PS7_FOUND=YES"
            CALL :LOG_MESSAGE "PowerShell 7 discovered at %ProgramFiles%\PowerShell\7 (attempt %%R/3)" "SUCCESS" "LAUNCHER"
        )
        IF "!PS7_FOUND!"=="NO" IF EXIST "%LocalAppData%\Microsoft\WindowsApps\pwsh.exe" (
            SET "PS7_FOUND=YES"
            CALL :LOG_MESSAGE "PowerShell 7 discovered via WindowsApps alias (attempt %%R/3)" "SUCCESS" "LAUNCHER"
        )
        IF "!PS7_FOUND!"=="NO" (
            pwsh.exe -NoProfile -Command "exit 0" >nul 2>&1
            IF !ERRORLEVEL! EQU 0 (
                SET "PS7_FOUND=YES"
                CALL :LOG_MESSAGE "PowerShell 7 discovered via PATH (attempt %%R/3)" "SUCCESS" "LAUNCHER"
            )
        )
        IF "!PS7_FOUND!"=="NO" CALL :LOG_MESSAGE "PowerShell 7 not yet discoverable (attempt %%R/3) - retrying" "WARN" "LAUNCHER"
    )
)
EXIT /B

:FIND_OTHER_INSTANCES
REM Sets OTHER_INSTANCES to a comma-separated list of OTHER cmd.exe PIDs whose command
REM line references script.bat. Empty when this is the only instance.
REM
REM Concurrent launcher instances are mutually DESTRUCTIVE: every instance deletes and
REM re-extracts the SAME %WORKING_DIR%script_mentenanta-master folder, downloads to the
REM SAME update.zip, and moves the SAME maintenance.log. A second instance therefore makes
REM the first one fail mid-run with "No valid PowerShell orchestrator found" /
REM "config\lists directory not found" while both logs interleave with silent gaps.
REM
REM Self-exclusion MUST cover the probe's whole ANCESTOR CHAIN, not just its parent:
REM FOR /F executes the backquoted command through an ephemeral child cmd.exe, so the
REM chain is: this batch's cmd -> FOR /F child cmd -> powershell. Excluding only the
REM powershell's parent (the FOR /F child) would leave the batch's own cmd "visible" and
REM make the guard detect ITSELF as a foreign instance. INSTANCE_ID is excluded too as a
REM belt-and-suspenders (covers an ancestor walk cut short).
REM Process-based detection (instead of a lock file) self-heals after crashes: a dead
REM instance simply stops matching, so nothing stale ever blocks the next run.
SET "OTHER_INSTANCES="
FOR /F "usebackq delims=" %%i IN (`powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='SilentlyContinue'; $skip='%INSTANCE_ID%'; $all=@(Get-CimInstance Win32_Process); $byId=@{}; foreach($p in $all){ $byId[[int]$p.ProcessId]=$p }; $anc=@(); $cur=[int]$PID; for($i=0; $i -lt 10; $i++){ $anc += $cur; $proc=$byId[$cur]; if(-not $proc){ break }; $cur=[int]$proc.ParentProcessId; if($cur -le 0){ break } }; $hits=@(); foreach($p in $all){ if($p.Name -eq 'cmd.exe' -and ($anc -notcontains [int]$p.ProcessId) -and ([string]$p.ProcessId -ne $skip) -and $p.CommandLine -match 'script\.bat'){ $hits += [int]$p.ProcessId } }; if($hits.Count -gt 0){ Write-Output ($hits -join ',') }" 2^>nul`) DO SET "OTHER_INSTANCES=%%i"
EXIT /B

:PROMPT_BRANCH_CHOICE
REM Interactive-only 30s "press any key for the Testing branch" prompt. Sets SELECTED_BRANCH
REM (no SETLOCAL here, so the assignment is visible to the caller).
REM
REM TIMEOUT CANNOT BE USED HERE, and this is the bug this subroutine exists to fix.
REM timeout.exe exits 0 for BOTH "the wait expired" AND "a key was pressed" - it aborts the
REM wait on a keypress but reports the same code either way (measured: keypress ended a
REM /T 10 wait after 3.16s, ERRORLEVEL 0; natural expiry, ERRORLEVEL 0). The ONLY thing that
REM makes TIMEOUT return 1 is redirected stdin ("ERROR: Input redirection is not supported",
REM returns in ~0.15s). So the previous `TIMEOUT /T 30` + `IF ERRORLEVEL EQU 1` had it exactly
REM backwards: a real keypress could never select Testing, while any redirected-stdin run that
REM slipped past the %1 gate selected Testing every time. Do not "restore" TIMEOUT here.
REM
REM CHOICE distinguishes the cases correctly but only for a fixed key list, and the requirement
REM is ANY key - so poll [Console]::KeyAvailable instead, which gives true any-key semantics,
REM a real countdown, and an unambiguous exit code (1 = key pressed, 0 = expired).
REM Fail-safe by construction: with no console or redirected input KeyAvailable throws, which
REM is caught and returns 0 (master) in ~0.4s rather than hanging or defaulting to Testing.
REM Buffered keys are drained first so a stray earlier keystroke cannot phantom-select Testing.
ECHO.
ECHO   Downloading master branch in 30 seconds - press any key to download the Testing branch instead... >> "%LOG_FILE%" 2>nul
powershell -NoProfile -ExecutionPolicy Bypass -Command "try { [void][Console]::KeyAvailable } catch { exit 0 }; try { while ([Console]::KeyAvailable) { [void][Console]::ReadKey($true) } } catch { exit 0 }; $end=(Get-Date).AddSeconds(30); while ((Get-Date) -lt $end) { if ([Console]::KeyAvailable) { [void][Console]::ReadKey($true); Write-Host ''; exit 1 }; $left=[int][math]::Ceiling(($end-(Get-Date)).TotalSeconds); Write-Host -NoNewline (\"`r  Downloading master branch in {0,3}s - press any key to download the Testing branch instead... \" -f $left); Start-Sleep -Milliseconds 200 }; Write-Host ''; exit 0"
IF !ERRORLEVEL! EQU 1 SET "SELECTED_BRANCH=Testing"
EXIT /B

:MAIN_SCRIPT

REM ============================================================================
REM Unified maintenance.log - created IMMEDIATELY next to the launcher so the very first
REM line onward is captured. It is migrated into <extracted>\temp_files\logs after
REM extraction (see the migration block below) and the orchestrator then appends to the
REM SAME file via $env:MAINTENANCE_LOG. This is the single log for the whole run.
REM ============================================================================
SET "ORIGINAL_SCRIPT_DIR=%~dp0"
SET "LOG_FILE=%~dp0maintenance.log"
IF NOT EXIST "%LOG_FILE%" TYPE NUL > "%LOG_FILE%"

REM Instance identity used to exclude THIS process's own ancestor chain from the
REM single-instance guard below (see :FIND_OTHER_INSTANCES). %RANDOM% fallback if the
REM PowerShell probe fails, so interleaved instances still get distinct tags.
SET "INSTANCE_ID=R%RANDOM%"
FOR /F "usebackq delims=" %%i IN (`powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='SilentlyContinue'; $all=@(Get-CimInstance Win32_Process); $byId=@{}; foreach($p in $all){ $byId[[int]$p.ProcessId]=$p }; $cur=[int]$PID; $best=''; $firstCmd=''; for($i=0; $i -lt 10; $i++){ $proc=$byId[$cur]; if(-not $proc){ break }; $par=[int]$proc.ParentProcessId; $pp=$byId[$par]; if(-not $pp){ break }; if($pp.Name -eq 'cmd.exe'){ if($firstCmd -eq ''){ $firstCmd=$par }; if($pp.CommandLine -match 'script\.bat'){ $best=$par; break } }; $cur=$par }; if($best -ne ''){ Write-Output $best } elseif($firstCmd -ne ''){ Write-Output $firstCmd }" 2^>nul`) DO SET "INSTANCE_ID=%%i"

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

REM ============================================================================
REM Write the session banner into the unified maintenance.log (append - the file was
REM created at launch above and may already hold lines from a prior resumed run).
REM ============================================================================
FOR /F "tokens=1-4 delims=/ " %%A IN ('DATE /T') DO SET "BANNER_DATE=%%A %%B %%C %%D"
FOR /F "tokens=1-2 delims=/:" %%A IN ('TIME /T') DO SET "BANNER_TIME=%%A:%%B"

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
) >> "%LOG_FILE%"

CALL :LOG_MESSAGE "Unified maintenance.log initialized: %LOG_FILE% (migrates to temp_files\logs after extraction)" "DEBUG" "LAUNCHER"

REM Environment variables for PowerShell orchestrator. MAINTENANCE_LOG is the name the
REM orchestrator actually reads ($env:MAINTENANCE_LOG), so it appends to this SAME file.
SET "WORKING_DIRECTORY=%WORKING_DIR%"
SET "MAINTENANCE_LOG=%LOG_FILE%"
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
REM Single-Instance Guard
REM Concurrent runs corrupt each other's downloaded/extracted files and shared log (see
REM :FIND_OTHER_INSTANCES above). Only ONE instance may pass. Placed AFTER elevation so
REM the un-elevated parent (which exits within ~1s of spawning the elevated child) is not
REM counted against its own child.
REM -----------------------------------------------------------------------------
CALL :LOG_MESSAGE "Checking for other running launcher instances..." "INFO" "LAUNCHER"
CALL :FIND_OTHER_INSTANCES
IF DEFINED OTHER_INSTANCES (
    REM One retry: an elevation parent or a just-finished run may still be exiting.
    CALL :LOG_MESSAGE "Other launcher cmd process(es) detected: !OTHER_INSTANCES! - rechecking in 8s..." "WARN" "LAUNCHER"
    TIMEOUT /T 8 >nul 2>&1
    CALL :FIND_OTHER_INSTANCES
)
IF DEFINED OTHER_INSTANCES (
    CALL :LOG_MESSAGE "Another script.bat instance is still running (cmd PID(s): !OTHER_INSTANCES!)" "ERROR" "LAUNCHER"
    CALL :LOG_MESSAGE "Concurrent runs delete each other's downloaded/extracted files and move the shared log - aborting THIS instance (PID %INSTANCE_ID%)." "ERROR" "LAUNCHER"
    CALL :LOG_MESSAGE "Let the other run finish, then run script.bat again." "ERROR" "LAUNCHER"
    TIMEOUT /T 20 >nul 2>&1
    EXIT /B 9
)
CALL :LOG_MESSAGE "No other launcher instances running - continuing" "SUCCESS" "LAUNCHER"

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

REM Prefer Windows Update reboot status when PSWindowsUpdate is available
powershell -ExecutionPolicy Bypass -Command "try { if (Get-Module -ListAvailable -Name PSWindowsUpdate) { Import-Module PSWindowsUpdate -Force; if (Get-Command Get-WURebootStatus -ErrorAction SilentlyContinue) { $status = Get-WURebootStatus -Silent -ErrorAction SilentlyContinue; if ($status -and $status.RebootRequired) { Write-Host 'WU_REBOOT_REQUIRED'; exit 1 } else { Write-Host 'WU_REBOOT_NOT_REQUIRED'; exit 0 } } else { Write-Host 'WU_REBOOT_CMD_MISSING'; exit 2 } } else { Write-Host 'PSWINDOWSUPDATE_NOT_AVAILABLE'; exit 3 } } catch { Write-Host 'UPDATE_CHECK_FAILED'; exit 4 }" >nul 2>&1
IF !ERRORLEVEL! EQU 1 (
    SET "RESTART_NEEDED=YES"
    IF NOT DEFINED RESTART_SIGNALS (SET "RESTART_SIGNALS=PSWindowsUpdate-RebootRequired") ELSE (SET "RESTART_SIGNALS=!RESTART_SIGNALS!,PSWindowsUpdate-RebootRequired")
    SET "RESTART_NEEDED_WU=YES"
    IF NOT DEFINED RESTART_SIGNALS_WU (SET "RESTART_SIGNALS_WU=PSWindowsUpdate-RebootRequired") ELSE (SET "RESTART_SIGNALS_WU=!RESTART_SIGNALS_WU!,PSWindowsUpdate-RebootRequired")
)
IF !ERRORLEVEL! EQU 2 CALL :LOG_MESSAGE "PSWindowsUpdate Get-WURebootStatus not available. Continuing with registry reboot signals." "INFO" "LAUNCHER"
IF !ERRORLEVEL! EQU 3 CALL :LOG_MESSAGE "PSWindowsUpdate not available. Continuing with registry reboot signals." "INFO" "LAUNCHER"
IF !ERRORLEVEL! EQU 4 CALL :LOG_MESSAGE "PSWindowsUpdate reboot check failed. Continuing with registry reboot signals." "WARN" "LAUNCHER"

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

    REM Create startup task to resume after user logon with admin rights.
    REM -NonInteractive is explicit: this is an automatic resume of an interrupted run, and
    REM the launcher no longer forces non-interactive mode on every invocation (that is what
    REM used to suppress the Stage 1 menu for real, user-started runs).
    CALL :LOG_MESSAGE "Creating ONLOGON startup task with script: %SCHEDULED_TASK_SCRIPT_PATH%" "DEBUG" "LAUNCHER"
    schtasks /Create ^
        /SC ONLOGON ^
        /TN "%STARTUP_TASK_NAME%" ^
        /TR "\"%SCHEDULED_TASK_SCRIPT_PATH%\" -NonInteractive" ^
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

REM The monthly task is the project's ONLY unattended entry point, so its command line must
REM carry -NonInteractive. Simply skipping creation when a task already exists would strand
REM every machine that registered one with an older script.bat (whose /TR had no arguments):
REM it would keep running in interactive mode as SYSTEM forever. So verify the registered
REM command and RE-CREATE it when the flag is missing - /F makes that idempotent.
SET "TASK_NEEDS_CREATE=YES"
schtasks /Query /TN "%TASK_NAME%" >nul 2>&1
IF !ERRORLEVEL! EQU 0 (
    SET "TASK_NEEDS_CREATE=NO"
    FOR /F "tokens=*" %%i IN ('schtasks /Query /TN "%TASK_NAME%" /FO LIST /V 2^>nul ^| findstr /C:"Task To Run"') DO (
        ECHO %%i | findstr /I /C:"-NonInteractive" >nul 2>&1
        IF ERRORLEVEL 1 SET "TASK_NEEDS_CREATE=STALE"
    )
)

IF "!TASK_NEEDS_CREATE!"=="NO" (
    CALL :LOG_MESSAGE "Monthly scheduled task exists and is unattended-ready: %TASK_NAME%" "SUCCESS" "LAUNCHER"
    FOR /F "tokens=*" %%i IN ('schtasks /Query /TN "%TASK_NAME%" /FO LIST ^| findstr /R /C:"Task To Run" /C:"Next Run Time"') DO (
        CALL :LOG_MESSAGE "Monthly task detail: %%i" "INFO" "LAUNCHER"
    )
) ELSE (
    IF "!TASK_NEEDS_CREATE!"=="STALE" (
        CALL :LOG_MESSAGE "Monthly task exists but its command line lacks -NonInteractive (registered by an older script.bat) - re-creating it" "WARN" "LAUNCHER"
    ) ELSE (
        CALL :LOG_MESSAGE "Creating monthly scheduled task: %TASK_NAME%" "INFO" "LAUNCHER"
    )
    REM -NonInteractive is explicit: this runs as SYSTEM at 01:00 with no console attached,
    REM so the Stage 1 menu/countdown must be skipped outright rather than polled for keys.
    schtasks /Create ^
        /SC MONTHLY ^
        /MO 1 ^
        /D 20 ^
        /TN "%TASK_NAME%" ^
        /TR "\"%SCHEDULED_TASK_SCRIPT_PATH%\" -NonInteractive" ^
        /ST 01:00 ^
        /RL HIGHEST ^
        /RU SYSTEM ^
        /F >nul 2>&1
    IF !ERRORLEVEL! EQU 0 (
        CALL :LOG_MESSAGE "Monthly scheduled task registered successfully" "SUCCESS" "LAUNCHER"
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

REM ---------------------------------------------------------------------------------
REM Branch selection: master is the default; Testing exists so in-progress changes can
REM be verified before they merge. Pressing any key during the 30s countdown selects Testing.
REM
REM Two independent guards, because each covers a case the other does not:
REM   1. The %1 gate (the same early invocation-argument check used later for
REM      ORCH_EXTRA_ARGS) skips the prompt outright for the two unattended entry points,
REM      so the monthly SYSTEM task and any -NonInteractive/-TaskNumbers run never wait at
REM      all - there is no human who could press a key, so there is nothing to wait for.
REM      (Unlike the later pre-orchestrator cooldown, which waits even unattended because
REM      it is masking real file-lock settling time, not a human decision.)
REM   2. :PROMPT_BRANCH_CHOICE itself fails safe to master when it has no usable console,
REM      so a redirected-stdin run that slips past guard 1 still gets master rather than
REM      silently pulling an in-progress branch onto a machine.
REM
REM The keypress detection deliberately does NOT use TIMEOUT - see :PROMPT_BRANCH_CHOICE for
REM the measurements showing why that never worked.
REM ---------------------------------------------------------------------------------
SET "SELECTED_BRANCH=master"
SET "EARLY_UNATTENDED=NO"
IF "%1"=="-TaskNumbers" SET "EARLY_UNATTENDED=YES"
IF "%1"=="-NonInteractive" SET "EARLY_UNATTENDED=YES"

IF "%EARLY_UNATTENDED%"=="YES" (
    CALL :LOG_MESSAGE "Unattended run - using master branch" "INFO" "LAUNCHER"
) ELSE (
    CALL :PROMPT_BRANCH_CHOICE
)

IF "%SELECTED_BRANCH%"=="Testing" (
    SET "REPO_URL=https://github.com/ichimbogdancristian/script_mentenanta/archive/refs/heads/Testing.zip"
    SET "EXTRACT_FOLDER=script_mentenanta-Testing"
    CALL :LOG_MESSAGE "User pressed a key - switching to the Testing branch" "WARN" "LAUNCHER"
) ELSE (
    CALL :LOG_MESSAGE "Repository branch: master" "INFO" "LAUNCHER"
)

REM Clean up leftovers from a previous run. If the extracted folder cannot be fully
REM removed (files held open by another process), abort NOW instead of extracting
REM into a half-deleted tree: ZipFile.ExtractToDirectory fails on existing files and
REM the run would otherwise die much later with a confusing "orchestrator not found".
REM Both possible branch folders are removed here (not just the one selected this run) -
REM otherwise a folder left behind by a crashed run on the OTHER branch would never get
REM cleaned up, since a normal run only ever looks at its own EXTRACT_FOLDER.
IF EXIST "%ZIP_FILE%" DEL /Q "%ZIP_FILE%" >nul 2>&1
IF EXIST "%WORKING_DIR%script_mentenanta-master" RMDIR /S /Q "%WORKING_DIR%script_mentenanta-master" >nul 2>&1
IF EXIST "%WORKING_DIR%script_mentenanta-Testing" RMDIR /S /Q "%WORKING_DIR%script_mentenanta-Testing" >nul 2>&1
IF EXIST "%WORKING_DIR%%EXTRACT_FOLDER%" (
    CALL :LOG_MESSAGE "Could not remove previous extracted folder - files are in use (a previous run's window still open? antivirus scan?)" "ERROR" "LAUNCHER"
    CALL :LOG_MESSAGE "Close anything using %WORKING_DIR%%EXTRACT_FOLDER%, then run script.bat again." "ERROR" "LAUNCHER"
    TIMEOUT /T 20 >nul 2>&1   & REM was PAUSE - must not block unattended runs
    EXIT /B 3
)

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
powershell -ExecutionPolicy Bypass -Command "try { Add-Type -AssemblyName System.IO.Compression.FileSystem; [System.IO.Compression.ZipFile]::ExtractToDirectory('%ZIP_FILE%', '%WORKING_DIR%'); Write-Host 'EXTRACTION_SUCCESS' } catch { Write-Host 'EXTRACTION_FAILED'; Write-Error $_.Exception.Message; exit 1 }"

IF !ERRORLEVEL! NEQ 0 (
    CALL :LOG_MESSAGE "Repository extraction failed" "ERROR" "LAUNCHER"
    TIMEOUT /T 20 >nul 2>&1   & REM was PAUSE - must not block unattended runs
    EXIT /B 3
)

REM Verify extraction
SET "EXTRACTED_PATH=%WORKING_DIR%%EXTRACT_FOLDER%"
IF EXIST "%EXTRACTED_PATH%" (
    CALL :LOG_MESSAGE "Repository extracted to: %EXTRACTED_PATH%" "SUCCESS" "LAUNCHER"
    
    REM ---------------------------------------------------------------------------------
    REM Self-update: DEFERRED ON PURPOSE - do NOT overwrite script.bat while it is running.
    REM
    REM cmd.exe streams a .bat file from disk by BYTE OFFSET as it executes. Replacing the
    REM file mid-run makes execution resume at that same offset inside the NEW content, so
    REM it jumps into the middle of unrelated code (this is what caused the crash mid-way
    REM through the PowerShell 7 install section: overwriting script.bat here desyncs the
    REM byte offset cmd.exe is reading from against the new file's different structure).
    REM
    REM The orchestrator (a separate pwsh process that starts after this launcher exits)
    REM performs the copy instead - see $env:PENDING_SCRIPT_UPDATE in MaintenanceOrchestrator.ps1.
    REM ---------------------------------------------------------------------------------
    IF EXIST "%EXTRACTED_PATH%\script.bat" (
        SET "PENDING_SCRIPT_UPDATE=%EXTRACTED_PATH%\script.bat"
        CALL :LOG_MESSAGE "script.bat self-update deferred to the orchestrator (a running .bat cannot safely overwrite itself)" "INFO" "LAUNCHER"
    ) ELSE (
        CALL :LOG_MESSAGE "No script.bat found in extracted repository" "WARN" "LAUNCHER"
    )
    
    REM Update working directory to extracted folder for proper module loading
    SET "WORKING_DIR=%EXTRACTED_PATH%\"
    SET "WORKING_DIRECTORY=%WORKING_DIR%"
    CALL :LOG_MESSAGE "Updated working directory to: %WORKING_DIR%" "INFO" "LAUNCHER"
    
    REM ---- Migrate the unified maintenance.log into temp_files\logs and keep writing ----
    REM The log has been accumulating next to the launcher since startup. Now that the repo is
    REM extracted, move it into <extracted>\temp_files\logs\maintenance.log and repoint LOG_FILE
    REM so every subsequent line continues in the SAME file. The orchestrator opens this exact
    REM path via $env:MAINTENANCE_LOG. Delayed expansion (!VAR!) is required: WORKING_DIR and the
    REM NEW_LOG_* vars are set inside this parenthesised block, so %VAR% would read stale values.
    SET "NEW_LOG_DIR=!WORKING_DIR!temp_files\logs"
    IF NOT EXIST "!NEW_LOG_DIR!" MD "!NEW_LOG_DIR!" >nul 2>&1
    SET "NEW_LOG_FILE=!NEW_LOG_DIR!\maintenance.log"
    IF EXIST "!LOG_FILE!" (
        MOVE /Y "!LOG_FILE!" "!NEW_LOG_FILE!" >nul 2>&1
        IF ERRORLEVEL 1 COPY /Y "!LOG_FILE!" "!NEW_LOG_FILE!" >nul 2>&1
    )
    SET "LOG_FILE=!NEW_LOG_FILE!"
    SET "MAINTENANCE_LOG=!NEW_LOG_FILE!"
    SET "SCRIPT_LOG_FILE=!NEW_LOG_FILE!"
    CALL :LOG_MESSAGE "maintenance.log migrated to: !LOG_FILE! (continuing here)" "DEBUG" "LAUNCHER"
    
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
    
    REM Check for lists subdirectory (data lists). The bloatware baseline lives in the
    REM 'bloatware' SUBFOLDER (config\lists\bloatware\), and the primary config is
    REM bloatware-detection.json (bloatware-list.json is only the legacy fallback).
    IF EXIST "%WORKING_DIR%config\lists" (
        CALL :LOG_MESSAGE "  [OK] config\lists directory present" "SUCCESS" "LAUNCHER"
        IF EXIST "%WORKING_DIR%config\lists\bloatware\bloatware-detection.json" (
            CALL :LOG_MESSAGE "    [OK] bloatware\bloatware-detection.json present" "SUCCESS" "LAUNCHER"
        ) ELSE (
            CALL :LOG_MESSAGE "    [X] bloatware\bloatware-detection.json missing" "WARN" "LAUNCHER"
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
        
        IF "%WINGET_AVAILABLE%"=="NO" (
            CALL :LOG_MESSAGE "All winget installation methods failed" "WARN" "LAUNCHER"
        )
    )

REM -----------------------------------------------------------------------------
REM Winget Self-Update (keep App Installer / winget current before we rely on it).
REM Only runs when winget is available; fully non-fatal and non-interactive so an
REM unattended run is never blocked by "already current" or an update being unavailable.
REM
REM "winget upgrade --id Microsoft.AppInstaller" (the old approach here) is NOT a
REM reliable self-update path: winget's own package-matching does not reliably see
REM itself as an installed/upgradable package, so this consistently failed with
REM APPINSTALLER_CLI_ERROR_NO_APPLICATIONS_FOUND ("No installed package found matching
REM input criteria") regardless of whether a newer version existed - confirmed against
REM multiple open microsoft/winget-cli issues, not a local misconfiguration. The
REM officially documented fix (same sequence Microsoft Learn's troubleshooting page
REM prescribes, and the same one already used above for a from-scratch install) is the
REM Microsoft.WinGet.Client module's Repair-WinGetPackageManager cmdlet, which operates
REM via the AppX/MSIX APIs directly rather than asking winget.exe to find itself.
REM
REM Caveat that is NOT fixable from here: Microsoft's own docs state winget.exe is not
REM supported under NT AUTHORITY\SYSTEM at all (MSIX packages register per-user, and
REM SYSTEM is explicitly excluded), and multiple issues report Repair-WinGetPackageManager
REM itself silently reporting "already in a good state" under SYSTEM without actually
REM updating anything. The monthly scheduled task runs this launcher as SYSTEM, so on
REM that path treat this as "best effort" - the before/after version is logged so the
REM real behaviour is visible rather than just trusting the exit code.
REM -----------------------------------------------------------------------------
IF "!WINGET_AVAILABLE!"=="YES" (
    CALL :LOG_MESSAGE "Refreshing winget sources..." "INFO" "LAUNCHER"
    "!WINGET_EXE!" source update >nul 2>&1

    FOR /F "tokens=*" %%W IN ('whoami 2^>nul') DO SET "CURRENT_RUN_USER=%%W"
    IF /I "!CURRENT_RUN_USER!"=="nt authority\system" (
        CALL :LOG_MESSAGE "Running as NT AUTHORITY\SYSTEM - winget/App Installer self-update is documented by Microsoft as unsupported in this context; attempting anyway via Repair-WinGetPackageManager, but treat the outcome as best-effort" "WARN" "LAUNCHER"
    )

    FOR /F "tokens=*" %%V IN ('"!WINGET_EXE!" --version 2^>nul') DO SET "WINGET_VERSION_BEFORE=%%V"
    CALL :LOG_MESSAGE "winget version before self-update attempt: !WINGET_VERSION_BEFORE!" "DEBUG" "LAUNCHER"

    CALL :LOG_MESSAGE "Attempting to update winget (App Installer) via Repair-WinGetPackageManager..." "INFO" "LAUNCHER"
    powershell -NoProfile -ExecutionPolicy Bypass -Command "try { $ProgressPreference='SilentlyContinue'; if (-not (Get-Module -ListAvailable -Name Microsoft.WinGet.Client)) { Install-PackageProvider -Name NuGet -Force -Scope CurrentUser | Out-Null; Install-Module -Name Microsoft.WinGet.Client -Force -Repository PSGallery -Scope CurrentUser | Out-Null }; Import-Module Microsoft.WinGet.Client -Force; Repair-WinGetPackageManager -AllUsers -Force -Latest; Write-Host 'WINGET_REPAIR_DONE' } catch { Write-Host 'WINGET_REPAIR_FAILED'; Write-Host $_.Exception.Message; exit 1 }" >nul 2>&1
    SET "WINGET_REPAIR_RC=!ERRORLEVEL!"

    CALL :REFRESH_PATH_FROM_REGISTRY
    FOR /F "tokens=*" %%V IN ('"!WINGET_EXE!" --version 2^>nul') DO SET "WINGET_VERSION_AFTER=%%V"

    IF "!WINGET_VERSION_AFTER!" NEQ "!WINGET_VERSION_BEFORE!" (
        CALL :LOG_MESSAGE "winget updated: !WINGET_VERSION_BEFORE! -> !WINGET_VERSION_AFTER!" "SUCCESS" "LAUNCHER"
    ) ELSE IF !WINGET_REPAIR_RC! EQU 0 (
        CALL :LOG_MESSAGE "Repair-WinGetPackageManager completed - winget version unchanged (!WINGET_VERSION_AFTER!), which is expected if already current" "INFO" "LAUNCHER"
    ) ELSE (
        CALL :LOG_MESSAGE "winget self-update attempt failed - continuing with version !WINGET_VERSION_AFTER!" "WARN" "LAUNCHER"
    )
)

REM ============================================================================
REM PowerShell 7 Installation - Enhanced Strategy (v2.0)
REM Method priority: GitHub MSI (most reliable) ? Winget ? Chocolatey
REM Path verification: 4-tier system for all installation types
REM ============================================================================

REM Phase 1: Comprehensive path verification (4-tier system)
CALL :LOG_MESSAGE "Checking PowerShell 7 availability..." "INFO" "LAUNCHER"

SET "PS7_EXECUTABLE="

REM Priority 1: Standard path (MSI, Chocolatey installations)
IF EXIST "%ProgramFiles%\PowerShell\7\pwsh.exe" (
    "%ProgramFiles%\PowerShell\7\pwsh.exe" -Version >nul 2>&1
    IF !ERRORLEVEL! EQU 0 (
        SET "PS7_EXECUTABLE=%ProgramFiles%\PowerShell\7\pwsh.exe"
        CALL :LOG_MESSAGE "PowerShell 7 found at standard path" "SUCCESS" "LAUNCHER"
        GOTO :PS7_FOUND_COMPLETE
    )
)

REM Priority 2: MSIX packages directory (actual location for Winget/Store installs)
FOR /D %%D IN ("%ProgramFiles%\WindowsApps\Microsoft.PowerShell_*") DO (
    IF EXIST "%%D\pwsh.exe" (
        "%%D\pwsh.exe" -Version >nul 2>&1
        IF !ERRORLEVEL! EQU 0 (
            SET "PS7_EXECUTABLE=%%D\pwsh.exe"
            CALL :LOG_MESSAGE "PowerShell 7 found at MSIX packages path" "SUCCESS" "LAUNCHER"
            GOTO :PS7_FOUND_COMPLETE
        )
    )
)

REM Priority 3: PATH-based discovery
pwsh.exe -Version >nul 2>&1
IF !ERRORLEVEL! EQU 0 (
    FOR /F "tokens=*" %%P IN ('where pwsh.exe 2^>nul') DO (
        "%%P" -Version >nul 2>&1
        IF !ERRORLEVEL! EQU 0 (
            SET "PS7_EXECUTABLE=%%P"
            CALL :LOG_MESSAGE "PowerShell 7 found via PATH" "SUCCESS" "LAUNCHER"
            GOTO :PS7_FOUND_COMPLETE
        )
    )
)

REM Priority 4: Per-user alias (least reliable in elevated context)
IF EXIST "%LocalAppData%\Microsoft\WindowsApps\pwsh.exe" (
    "%LocalAppData%\Microsoft\WindowsApps\pwsh.exe" -Version >nul 2>&1
    IF !ERRORLEVEL! EQU 0 (
        SET "PS7_EXECUTABLE=%LocalAppData%\Microsoft\WindowsApps\pwsh.exe"
        CALL :LOG_MESSAGE "PowerShell 7 found via WindowsApps alias" "INFO" "LAUNCHER"
        GOTO :PS7_FOUND_COMPLETE
    )
)

REM Phase 2: Installation needed - try methods in priority order
CALL :LOG_MESSAGE "PowerShell 7 not found. Starting installation..." "INFO" "LAUNCHER"
SET "PS7_INSTALL_SUCCESS=NO"

REM Method 1: GitHub MSI Download (MOST RELIABLE - no dependencies)
CALL :LOG_MESSAGE "Method 1/3: Attempting GitHub MSI download..." "INFO" "LAUNCHER"

REM Detect architecture
FOR /F "tokens=*" %%A IN ('powershell -NoProfile -ExecutionPolicy Bypass -Command "if([Environment]::Is64BitOperatingSystem){ Write-Host 'x64' } else { Write-Host 'x86' }" 2^>nul') DO SET "SYS_ARCH=%%A"
IF NOT DEFINED SYS_ARCH SET "SYS_ARCH=x64"

REM Download from GitHub API
REM MUST be a single line: cmd.exe does NOT treat an unclosed quote in a plain (or even
REM parenthesized-block) statement as continuing onto the next physical line - each line
REM is parsed as its own separate command. The previous multi-line form silently split into
REM "'try' is not recognized...", "'$ProgressPreference' is not recognized...", etc., and the
REM line with two unescaped pipes (the Where-Object/Select-Object chain) made cmd.exe hang
REM indefinitely on an empty pipeline segment - this was the actual launcher "crash".
powershell -NoProfile -ExecutionPolicy Bypass -Command "try { $ProgressPreference = 'SilentlyContinue'; $headers = @{'User-Agent' = 'WinMaintLauncher/2.0'}; $rel = Invoke-RestMethod -Headers $headers -Uri 'https://api.github.com/repos/PowerShell/PowerShell/releases/latest' -TimeoutSec 30; $asset = $rel.assets | Where-Object { $_.name -match 'win-!SYS_ARCH!\.msi$' } | Select-Object -First 1; if(-not $asset){ Write-Host 'ASSET_NOT_FOUND'; exit 2 }; Invoke-WebRequest -Headers $headers -Uri $asset.browser_download_url -OutFile '%WORKING_DIR%pwsh-github.msi' -UseBasicParsing -TimeoutSec 60; Write-Host 'DOWNLOAD_SUCCESS' } catch { Write-Host 'DOWNLOAD_FAILED'; exit 1 }" >nul 2>&1

IF !ERRORLEVEL! EQU 0 (
    IF EXIST "%WORKING_DIR%pwsh-github.msi" (
        CALL :LOG_MESSAGE "GitHub MSI downloaded, installing..." "SUCCESS" "LAUNCHER"
        msiexec /i "%WORKING_DIR%pwsh-github.msi" /qn ADD_EXPLORER_CONTEXT_MENU_OPENPOWERSHELL=1 ENABLE_PSREMOTING=1 REGISTER_MANIFEST=1 >nul 2>&1
        IF !ERRORLEVEL! EQU 0 (
            timeout /t 5 >nul
            CALL :REFRESH_PATH_FROM_REGISTRY
            IF EXIST "%ProgramFiles%\PowerShell\7\pwsh.exe" (
                "%ProgramFiles%\PowerShell\7\pwsh.exe" -Version >nul 2>&1
                IF !ERRORLEVEL! EQU 0 (
                    SET "PS7_EXECUTABLE=%ProgramFiles%\PowerShell\7\pwsh.exe"
                    SET "PS7_INSTALL_SUCCESS=YES"
                    CALL :LOG_MESSAGE "GitHub MSI installation verified" "SUCCESS" "LAUNCHER"
                )
            )
        )
        DEL /Q "%WORKING_DIR%pwsh-github.msi" >nul 2>&1
    )
) ELSE (
    CALL :LOG_MESSAGE "GitHub API download failed (network or GitHub blocked)" "WARN" "LAUNCHER"
)

REM Method 2: Winget (if available and GitHub failed)
IF "!PS7_INSTALL_SUCCESS!"=="NO" IF "!WINGET_AVAILABLE!"=="YES" (
    CALL :LOG_MESSAGE "Method 2/3: Attempting Winget installation..." "INFO" "LAUNCHER"
    "!WINGET_EXE!" install Microsoft.PowerShell --silent --accept-package-agreements --accept-source-agreements >nul 2>&1
    IF !ERRORLEVEL! EQU 0 (
        timeout /t 5 >nul
        CALL :REFRESH_PATH_FROM_REGISTRY

        REM Check all possible locations for Winget installation
        IF EXIST "%ProgramFiles%\PowerShell\7\pwsh.exe" (
            "%ProgramFiles%\PowerShell\7\pwsh.exe" -Version >nul 2>&1
            IF !ERRORLEVEL! EQU 0 (
                SET "PS7_EXECUTABLE=%ProgramFiles%\PowerShell\7\pwsh.exe"
                SET "PS7_INSTALL_SUCCESS=YES"
                CALL :LOG_MESSAGE "Winget installation verified at standard path" "SUCCESS" "LAUNCHER"
            )
        ) ELSE (
            FOR /D %%D IN ("%ProgramFiles%\WindowsApps\Microsoft.PowerShell_*") DO (
                IF EXIST "%%D\pwsh.exe" (
                    "%%D\pwsh.exe" -Version >nul 2>&1
                    IF !ERRORLEVEL! EQU 0 (
                        SET "PS7_EXECUTABLE=%%D\pwsh.exe"
                        SET "PS7_INSTALL_SUCCESS=YES"
                        CALL :LOG_MESSAGE "Winget installation verified at MSIX path" "SUCCESS" "LAUNCHER"
                    )
                )
            )
        )
    ) ELSE (
        CALL :LOG_MESSAGE "Winget installation failed" "WARN" "LAUNCHER"
    )
)

REM Method 3: Chocolatey (last resort)
IF "!PS7_INSTALL_SUCCESS!"=="NO" (
    CALL :LOG_MESSAGE "Method 3/3: Attempting Chocolatey installation..." "INFO" "LAUNCHER"

    SET "CHOCO_EXE=choco"
    IF EXIST "%ProgramData%\chocolatey\bin\choco.exe" SET "CHOCO_EXE=%ProgramData%\chocolatey\bin\choco.exe"

    "!CHOCO_EXE!" --version >nul 2>&1
    IF !ERRORLEVEL! EQU 0 (
        CALL :LOG_MESSAGE "Chocolatey found, installing PowerShell..." "INFO" "LAUNCHER"
        "!CHOCO_EXE!" install powershell-core -y --no-progress >nul 2>&1
        IF !ERRORLEVEL! EQU 0 (
            timeout /t 5 >nul
            CALL :REFRESH_PATH_FROM_REGISTRY
            IF EXIST "%ProgramFiles%\PowerShell\7\pwsh.exe" (
                "%ProgramFiles%\PowerShell\7\pwsh.exe" -Version >nul 2>&1
                IF !ERRORLEVEL! EQU 0 (
                    SET "PS7_EXECUTABLE=%ProgramFiles%\PowerShell\7\pwsh.exe"
                    SET "PS7_INSTALL_SUCCESS=YES"
                    CALL :LOG_MESSAGE "Chocolatey installation verified" "SUCCESS" "LAUNCHER"
                )
            )
        )
    ) ELSE (
        CALL :LOG_MESSAGE "Chocolatey not found, bootstrapping..." "INFO" "LAUNCHER"
        REM MUST be a single line - see the GitHub MSI download comment above for why a
        REM multi-line -Command string silently breaks (and can hang) cmd.exe.
        powershell -NoProfile -ExecutionPolicy Bypass -Command "try { $ProgressPreference='SilentlyContinue'; Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1')); Write-Host 'BOOTSTRAP_SUCCESS' } catch { Write-Host 'BOOTSTRAP_FAILED'; exit 1 }" >nul 2>&1

        IF !ERRORLEVEL! EQU 0 (
            timeout /t 3 >nul
            CALL :REFRESH_PATH_FROM_REGISTRY
            IF EXIST "%ProgramData%\chocolatey\bin\choco.exe" (
                CALL :LOG_MESSAGE "Chocolatey bootstrapped, installing PowerShell..." "SUCCESS" "LAUNCHER"
                "%ProgramData%\chocolatey\bin\choco.exe" install powershell-core -y --no-progress >nul 2>&1
                IF !ERRORLEVEL! EQU 0 (
                    timeout /t 5 >nul
                    CALL :REFRESH_PATH_FROM_REGISTRY
                    IF EXIST "%ProgramFiles%\PowerShell\7\pwsh.exe" (
                        "%ProgramFiles%\PowerShell\7\pwsh.exe" -Version >nul 2>&1
                        IF !ERRORLEVEL! EQU 0 (
                            SET "PS7_EXECUTABLE=%ProgramFiles%\PowerShell\7\pwsh.exe"
                            SET "PS7_INSTALL_SUCCESS=YES"
                            CALL :LOG_MESSAGE "Chocolatey installation verified" "SUCCESS" "LAUNCHER"
                        )
                    )
                )
            ) ELSE (
                CALL :LOG_MESSAGE "Chocolatey bootstrap completed but choco.exe not found" "ERROR" "LAUNCHER"
            )
        ) ELSE (
            CALL :LOG_MESSAGE "Chocolatey bootstrap failed" "ERROR" "LAUNCHER"
        )
    )
)

REM Phase 3: Final result
IF "!PS7_INSTALL_SUCCESS!"=="YES" (
    FOR /F "tokens=*" %%V IN ('"!PS7_EXECUTABLE!" -Command "$PSVersionTable.PSVersion.ToString()" 2^>nul') DO (
        CALL :LOG_MESSAGE "PowerShell 7 installation complete (version %%V)" "SUCCESS" "LAUNCHER"
    )
    GOTO :PS7_COMPLETE
) ELSE (
    CALL :LOG_MESSAGE "All PowerShell 7 installation methods failed" "ERROR" "LAUNCHER"
    CALL :LOG_MESSAGE "Please manually install from: https://github.com/PowerShell/PowerShell/releases" "ERROR" "LAUNCHER"
    TIMEOUT /T 20 >nul 2>&1   & REM was PAUSE - must not block unattended runs
    EXIT /B 1
)

:PS7_FOUND_COMPLETE
FOR /F "tokens=*" %%V IN ('"!PS7_EXECUTABLE!" -Command "$PSVersionTable.PSVersion.ToString()" 2^>nul') DO (
    CALL :LOG_MESSAGE "PowerShell 7 available (version %%V)" "SUCCESS" "LAUNCHER"
)

:PS7_COMPLETE

REM -----------------------------------------------------------------------------
REM PowerShell Module Dependencies (PSWindowsUpdate)
REM -----------------------------------------------------------------------------
REM MOVED to the orchestrator's Stage 0 preflight (Install-PSWindowsUpdateModule in
REM MaintenanceOrchestrator.ps1). It was a 616-character `pwsh -Command "..."` string here:
REM unlintable, untestable, and with no error handling beyond ERRORLEVEL. Everything past
REM :PS7_COMPLETE runs with pwsh already proven present, so it does not have to be batch.
REM
REM Nothing in the launcher depends on PSWindowsUpdate. The only consumer is the
REM WindowsUpdates Type2 module in Stage 3, and even there it is a fallback - the primary
REM path is the Windows Update COM API. The AllUsers scope rationale moved with the code.
REM
REM (The pending-reboot probe near the top of this script also prefers PSWindowsUpdate when
REM present, but it runs long before this point and already falls back to registry reboot
REM signals - that ordering is unchanged by this move.)

REM -----------------------------------------------------------------------------
REM Windows Defender Exclusions (Moved after PowerShell installation)
REM -----------------------------------------------------------------------------
REM Two paths need excluding, not one: %WORKING_DIR% is the EXTRACTED tree (re-assigned at
REM :DOWNLOAD_REPOSITORY to %EXTRACTED_PATH%, e.g. script_mentenanta-master\), which Stage 5
REM deletes every run - but script.bat ITSELF lives one level up, in the stable launcher
REM folder (%ORIGINAL_SCRIPT_DIR%, e.g. the Desktop), which is never covered by that
REM exclusion. A batch file that self-elevates, downloads a zip from GitHub, extracts it and
REM launches PowerShell is exactly the heuristic Defender flags, so excluding only the
REM extracted subfolder still leaves script.bat itself exposed on every run.
REM This stays in the launcher ON PURPOSE, and must not be moved into the orchestrator's
REM Stage 0 preflight the way the PSWindowsUpdate install was. The exclusions have to be in
REM place BEFORE pwsh.exe starts and BEFORE the orchestrator imports its modules out of the
REM extracted tree - both of which happen before any orchestrator code could run. Moving the
REM add would leave the process launch and the module load unprotected, which is strictly
REM worse than today. Stage 5 still removes them (Remove-DefenderSessionExclusions).
REM
REM The result is captured into the log rather than only echoed: this call used to Write-Host
REM 'EXCLUSIONS_ADDED'/'EXCLUSIONS_FAILED' to a console nobody reads on an unattended run, so
REM a failure to exclude - the thing most likely to make Defender interfere with the run -
REM left no trace anywhere in maintenance.log.
REM PATH exclusions ONLY - no -ExclusionProcess. Two process exclusions
REM ('powershell.exe' and 'pwsh.exe') were removed deliberately and must not come back:
REM   * -ExclusionProcess does not exclude the binary, it excludes EVERY FILE THAT PROCESS
REM     OPENS from scanning, and it matches on process NAME rather than full path. Excluding
REM     powershell.exe therefore left any process of that name, anywhere on the machine, doing
REM     unscanned file I/O for the whole run. PowerShell is the most abused living-off-the-land
REM     binary on Windows, so that single line undercut both the Sysmon install and the CIS
REM     baseline this project applies.
REM   * They were also redundant. The stated reason for excluding anything at all is that
REM     script.bat's self-elevate/download/extract/launch pattern trips Defender's heuristics -
REM     that is about THIS PROJECT'S OWN FILES, which the two path exclusions below already
REM     cover. All the process exclusions added on top was cover for files our PowerShell
REM     touches outside those folders (winget/MSI downloads in %TEMP%), and Defender scanning
REM     a signed installer is fast and correct.
REM   * And they could leak permanently: exclusion removal used to run only in Stage 5, so any
REM     crash before that point left powershell.exe excluded forever. Removal now also runs in
REM     the orchestrator's finally block, but the narrower exclusion set is the real fix.
CALL :LOG_MESSAGE "Setting up Windows Defender path exclusions..." "INFO" "LAUNCHER"
SET "EXCL_RESULT="
FOR /F "usebackq tokens=* delims=" %%i IN (`powershell -NoProfile -ExecutionPolicy Bypass -Command "try { Add-MpPreference -ExclusionPath '%WORKING_DIR%' -ErrorAction Stop; Add-MpPreference -ExclusionPath '%ORIGINAL_SCRIPT_DIR%' -ErrorAction SilentlyContinue; Write-Output 'EXCLUSIONS_ADDED' } catch { Write-Output ('EXCLUSIONS_FAILED: ' + $_.Exception.Message) }" 2^>nul`) DO SET "EXCL_RESULT=%%i"
IF "!EXCL_RESULT!"=="EXCLUSIONS_ADDED" (
    CALL :LOG_MESSAGE "Defender path exclusions added: %WORKING_DIR% + %ORIGINAL_SCRIPT_DIR%" "SUCCESS" "LAUNCHER"
) ELSE (
    IF DEFINED EXCL_RESULT (
        CALL :LOG_MESSAGE "Defender exclusions not fully applied - !EXCL_RESULT!" "WARN" "LAUNCHER"
    ) ELSE (
        CALL :LOG_MESSAGE "Defender exclusion command produced no result (Defender may be disabled or managed by policy)" "WARN" "LAUNCHER"
    )
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
    TIMEOUT /T 20 >nul 2>&1   & REM was PAUSE - must not block unattended runs
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
    TIMEOUT /T 20 >nul 2>&1   & REM was PAUSE - must not block unattended runs
    EXIT /B 1
)

REM -----------------------------------------------------------------------------
REM System Restore Point
REM -----------------------------------------------------------------------------
REM MOVED to the orchestrator: New-SystemRestorePoint in modules/type2/SystemConfiguration.psm1,
REM which SystemConfigurationAudit queues UNCONDITIONALLY every run (ConfigType=restorepoint,
REM Action=create) and Get-ConfigItemRank sorts to rank 0 - so the restore point is still the
REM first thing that happens before any other change, it is just no longer done twice.
REM
REM The ~119 lines removed here created a SECOND restore point via Checkpoint-Computer /
REM Enable-ComputerRestore / Get-ComputerRestorePoint in 7 embedded PowerShell one-liners.
REM That duplicated the orchestrator path and was strictly worse than it:
REM   - it never cleared SystemRestorePointCreationFrequency, so Windows silently throttled
REM     it to a no-op whenever a restore point already existed from the past 24h (it then
REM     reported "created" and only half-noticed via "verification inconclusive");
REM   - those three cmdlets are not native to PowerShell 7. They resolve only through the
REM     Windows PowerShell compatibility layer as implicit-remoting proxy functions, which
REM     spins up a background WinPS 5.1 session - slow, and not something to depend on under
REM     SYSTEM in session 0. The orchestrator uses root/default:SystemRestore via
REM     Invoke-CimMethod instead, which is native to PS7.
REM
REM The one piece worth keeping - sizing shadow storage to 10GB via vssadmin, without which
REM a created restore point can be discarded immediately - moved into New-SystemRestorePoint
REM alongside the code that depends on it.

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

REM Parse command line arguments for the orchestrator. -TaskNumbers implies non-interactive
REM (per CLAUDE.md).
REM
REM NOTE: this used to also add -NonInteractive whenever AUTO_NONINTERACTIVE was YES. That
REM variable does NOT mean "run unattended" - it is set at every PowerShell 7 DETECTION site
REM below and simply means "a usable pwsh.exe was found". Since the launcher refuses to run
REM the orchestrator at all without PS7 (see the IF below), it was always YES on every real
REM run, so -NonInteractive was passed unconditionally and the orchestrator's Stage 1 module
REM menu / 10s countdown never appeared. Unattended callers (the scheduled tasks created
REM above) now pass -NonInteractive explicitly instead.
SET "ORCH_EXTRA_ARGS="
IF "%1"=="-TaskNumbers" (
    SET "ORCH_EXTRA_ARGS= -NonInteractive -TaskNumbers %2"
) ELSE IF "%1"=="-NonInteractive" (
    SET "ORCH_EXTRA_ARGS= -NonInteractive"
) ELSE (
    CALL :LOG_MESSAGE "Interactive mode - Stage 1 module menu will be shown (10s countdown)" "INFO" "LAUNCHER"
)

CALL :LOG_MESSAGE "Launching orchestrator with arguments:!ORCH_EXTRA_ARGS!" "INFO" "LAUNCHER"

REM Setup complete - transitioning to dedicated PowerShell 7 window for better performance and UI
CALL :LOG_MESSAGE "Setup phase completed - launching dedicated PowerShell 7+ window" "INFO" "LAUNCHER"
CALL :LOG_MESSAGE "This will provide better performance and eliminate visual glitches" "INFO" "LAUNCHER"

REM Critical: Use PowerShell 7+ (pwsh.exe) for MaintenanceOrchestrator.ps1 due to #Requires directive
IF "%AUTO_NONINTERACTIVE%"=="YES" (
    CALL :LOG_MESSAGE "Launching PowerShell 7+ in dedicated window for optimal experience" "SUCCESS" "LAUNCHER"
    
    REM Prepare arguments for the new PowerShell window.
    REM
    REM -NoExit is INTERACTIVE-ONLY. It keeps the pwsh host sitting at a prompt after the
    REM orchestrator returns, which is what you want when a human is watching, but under the
    REM monthly Task Scheduler run (SYSTEM, session 0, no visible window) it leaves an
    REM orphaned pwsh process alive forever - one more every month - and the task never
    REM really finishes. Unattended runs must let the host exit on its own.
    IF DEFINED ORCH_EXTRA_ARGS (
        SET "PS_ARGS=-ExecutionPolicy Bypass -NonInteractive -Command "
    ) ELSE (
        SET "PS_ARGS=-ExecutionPolicy Bypass -NoExit -Command "
    )
    SET "PS_ARGS=!PS_ARGS!& { "
    SET "PS_ARGS=!PS_ARGS!Set-Location '%WORKING_DIR%'; "
    SET "PS_ARGS=!PS_ARGS!Write-Host 'Windows Maintenance Automation - PowerShell 7+ Mode' -ForegroundColor Green; "
    SET "PS_ARGS=!PS_ARGS!Write-Host 'Working Directory: %WORKING_DIR%' -ForegroundColor Cyan; "
    SET "PS_ARGS=!PS_ARGS!Write-Host 'Launching MaintenanceOrchestrator...' -ForegroundColor Yellow; "
    SET "PS_ARGS=!PS_ARGS!Write-Host ''; "

    REM Pass through the same non-interactive/-TaskNumbers arguments resolved above
    SET "PS_ARGS=!PS_ARGS!& '%ORCHESTRATOR_PATH%'!ORCH_EXTRA_ARGS!; "

    SET "PS_ARGS=!PS_ARGS!Write-Host ''; "
    SET "PS_ARGS=!PS_ARGS!Write-Host 'Maintenance session completed.' -ForegroundColor Green; "
    SET "PS_ARGS=!PS_ARGS!}"
    
    REM ---------------------------------------------------------------------------------
    REM 30s cooldown before handing off to the orchestrator.
    REM
    REM The bootstrap phase immediately above may have installed PowerShell 7, winget/App
    REM Installer and PSWindowsUpdate, and added Defender exclusions. Those leave work in
    REM flight for a few seconds - MSI/winget file locks, registry and PATH writes, service
    REM registration, Defender picking up the new exclusions. Handing straight over means the
    REM orchestrator's first module can hit a half-registered dependency. This is the same
    REM reasoning as the existing "wait for PowerShell 7 registration to settle" retry loop.
    REM
    REM DO NOT use TIMEOUT here. TIMEOUT aborts instantly ("Input redirection is not
    REM supported") whenever stdin is redirected - which is precisely the unattended
    REM Task Scheduler case, i.e. the fresh-machine run that needs the settle time most.
    REM Measured: TIMEOUT /T 5 /NOBREAK returned in 0.05s with stdin redirected, while
    REM `ping -n 6` waited the full 5s. So: ping for unattended (reliable, silent),
    REM TIMEOUT for interactive (visible countdown, and a keypress can skip it).
    CALL :LOG_MESSAGE "Cooling down 30s to let freshly installed dependencies settle before handing off..." "INFO" "LAUNCHER"
    IF DEFINED ORCH_EXTRA_ARGS (
        ping -n 31 127.0.0.1 >nul 2>&1
    ) ELSE (
        ECHO.
        ECHO   Starting the maintenance orchestrator in 30 seconds - press any key to skip...
        ECHO   Starting the maintenance orchestrator in 30 seconds - press any key to skip... >> "%LOG_FILE%" 2>nul
        TIMEOUT /T 30
    )
    CALL :LOG_MESSAGE "Cooldown complete - handing off to the orchestrator" "INFO" "LAUNCHER"

    REM Write all remaining launcher messages BEFORE START so the bootstrap log
    REM is complete by the time the orchestrator reads and deletes it.
    CALL :LOG_MESSAGE "Launching: \"%PS_EXECUTABLE%\" !PS_ARGS!" "DEBUG" "LAUNCHER"
    CALL :LOG_MESSAGE "PowerShell 7+ window launching - batch launcher exiting" "SUCCESS" "LAUNCHER"
    CALL :LOG_MESSAGE "All further operations will run in the dedicated PowerShell window" "INFO" "LAUNCHER"
    CALL :LOG_MESSAGE "=== END OF LAUNCHER LOG ===" "INFO" "LAUNCHER"

    REM Clear LOG_FILE now so no stray write can race with the orchestrator's delete
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

REM -----------------------------------------------------------------------------
REM End of Script
REM -----------------------------------------------------------------------------
ENDLOCAL
