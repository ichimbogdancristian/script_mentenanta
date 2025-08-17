@ECHO OFF
SETLOCAL ENABLEDELAYEDEXPANSION

ECHO Testing admin privilege detection and elevation...
ECHO.

REM Set basic variables
SET "SCRIPT_PATH=%~f0"
SET "LOG_FILE=admin_test.log"

REM Test admin detection
CALL :DETECT_ADMIN_PRIVILEGES
ECHO Admin status: !IS_ADMIN!

IF "!IS_ADMIN!"=="NO" (
    ECHO Script not running with admin privileges
    ECHO Attempting elevation...
    CALL :REQUEST_ADMIN_PRIVILEGES "!SCRIPT_PATH!" "%*"
    ECHO Elevation attempt completed.
    PAUSE
    EXIT /B 0
) ELSE (
    ECHO ✓ Running with administrator privileges!
    ECHO SUCCESS: Admin elevation test passed!
    PAUSE
    EXIT /B 0
)

:DETECT_ADMIN_PRIVILEGES
SET "IS_ADMIN=NO"

REM Method 1: NET SESSION command
NET SESSION >nul 2>&1
IF !ERRORLEVEL! EQU 0 (
    SET "IS_ADMIN=YES"
    ECHO [INFO] Admin detected via NET SESSION
    GOTO :EOF
)

REM Method 2: WHOAMI /PRIV command check
whoami /priv 2>nul | find "SeDebugPrivilege" >nul
IF !ERRORLEVEL! EQU 0 (
    SET "IS_ADMIN=YES"
    ECHO [INFO] Admin detected via WHOAMI
    GOTO :EOF
)

ECHO [INFO] No admin privileges detected
GOTO :EOF

:REQUEST_ADMIN_PRIVILEGES
SET "SCRIPT_TO_RUN=%~1"
SET "SCRIPT_ARGS=%~2"

ECHO.
ECHO Requesting administrator privileges...
ECHO Script: !SCRIPT_TO_RUN!
ECHO.

REM PowerShell elevation method
ECHO Attempting PowerShell elevation...
powershell.exe -ExecutionPolicy Bypass -Command "try { Start-Process -FilePath '!SCRIPT_TO_RUN!' -Verb RunAs; Write-Host 'Elevation request sent'; exit 0 } catch { Write-Host 'Error:' $_.Exception.Message; exit 1 }"
IF !ERRORLEVEL! EQU 0 (
    ECHO PowerShell elevation successful!
    GOTO :EOF
)

ECHO PowerShell elevation failed.
ECHO Please right-click the script and select "Run as administrator"
GOTO :EOF
