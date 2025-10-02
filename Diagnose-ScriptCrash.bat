@echo off
REM ============================================================================
REM  Script.bat Crash Diagnostic Tool
REM  Purpose: Diagnose common crash issues when script.bat is run on new PCs
REM  Author: Windows Maintenance Automation Project
REM ============================================================================

SETLOCAL ENABLEDELAYEDEXPANSION

ECHO ================================================================
ECHO  SCRIPT.BAT CRASH DIAGNOSTIC TOOL
ECHO  Analyzing system for common crash causes...
ECHO ================================================================
ECHO.

REM Get script location
SET "SCRIPT_PATH=%~f0"
SET "SCRIPT_DIR=%~dp0"
SET "WORKING_DIR=%SCRIPT_DIR%"

ECHO [STEP 1] Environment Analysis
ECHO ------------------------------
ECHO Script Location: %SCRIPT_PATH%
ECHO Working Directory: %WORKING_DIR%
ECHO Computer Name: %COMPUTERNAME%
ECHO User: %USERNAME%
ECHO Windows Version: 

REM Check Windows version
FOR /F "tokens=*" %%i IN ('powershell -NoProfile -Command "try { (Get-CimInstance Win32_OperatingSystem).Caption } catch { (Get-WmiObject Win32_OperatingSystem).Caption }"') DO SET OS_NAME=%%i
ECHO   %OS_NAME%

ECHO.
ECHO [STEP 2] Administrator Privileges Check
ECHO ----------------------------------------
NET SESSION >nul 2>&1
IF %ERRORLEVEL% NEQ 0 (
    ECHO ❌ NOT running as Administrator
    ECHO    This is the most common crash cause!
    ECHO    Right-click script.bat and select "Run as administrator"
) ELSE (
    ECHO ✅ Running as Administrator
)

ECHO.
ECHO [STEP 3] PowerShell Availability Check
ECHO ---------------------------------------
ECHO Windows PowerShell 5.1:
powershell.exe -Version >nul 2>&1
IF %ERRORLEVEL% EQU 0 (
    FOR /F "tokens=*" %%i IN ('powershell -NoProfile -Command "$PSVersionTable.PSVersion.ToString()" 2^>nul') DO SET PS51_VERSION=%%i
    ECHO   ✅ Available - Version: !PS51_VERSION!
) ELSE (
    ECHO   ❌ NOT Available - Critical dependency missing!
)

ECHO PowerShell 7:
pwsh.exe -Version >nul 2>&1
IF %ERRORLEVEL% EQU 0 (
    FOR /F "tokens=*" %%i IN ('pwsh.exe -NoProfile -Command "$PSVersionTable.PSVersion.ToString()" 2^>nul') DO SET PS7_VERSION=%%i
    ECHO   ✅ Available - Version: !PS7_VERSION!
) ELSE (
    ECHO   ⚠️  Not available - will be installed automatically
)

ECHO.
ECHO [STEP 4] Package Manager Check
ECHO -------------------------------
ECHO Winget:
winget --version >nul 2>&1
IF %ERRORLEVEL% EQU 0 (
    FOR /F "tokens=*" %%i IN ('winget --version 2^>nul') DO SET WINGET_VERSION=%%i
    ECHO   ✅ Available - Version: !WINGET_VERSION!
) ELSE (
    ECHO   ⚠️  Not available - will be installed automatically
)

ECHO Chocolatey:
choco --version >nul 2>&1
IF %ERRORLEVEL% EQU 0 (
    FOR /F "tokens=*" %%i IN ('choco --version 2^>nul') DO SET CHOCO_VERSION=%%i
    ECHO   ✅ Available - Version: !CHOCO_VERSION!
) ELSE (
    ECHO   ⚠️  Not available - will be installed automatically
)

ECHO.
ECHO [STEP 5] Internet Connectivity Check
ECHO -------------------------------------
ECHO Testing GitHub connectivity:
ping -n 1 github.com >nul 2>&1
IF %ERRORLEVEL% EQU 0 (
    ECHO   ✅ GitHub reachable
) ELSE (
    ECHO   ❌ GitHub not reachable - Network/Firewall issue!
)

ECHO Testing PowerShell Gallery connectivity:
powershell -NoProfile -Command "try { Test-NetConnection -ComputerName powershellgallery.com -Port 443 -InformationLevel Quiet } catch { $false }" >nul 2>&1
IF %ERRORLEVEL% EQU 0 (
    ECHO   ✅ PowerShell Gallery reachable
) ELSE (
    ECHO   ⚠️  PowerShell Gallery connectivity issues
)

ECHO.
ECHO [STEP 6] File System Check
ECHO ---------------------------
ECHO Checking required files:
IF EXIST "%WORKING_DIR%script.bat" (
    ECHO   ✅ script.bat exists
) ELSE (
    ECHO   ❌ script.bat missing!
)

IF EXIST "%WORKING_DIR%MaintenanceOrchestrator.ps1" (
    ECHO   ✅ MaintenanceOrchestrator.ps1 exists
) ELSE (
    ECHO   ⚠️  MaintenanceOrchestrator.ps1 missing - will be downloaded
)

IF EXIST "%WORKING_DIR%config" (
    ECHO   ✅ config directory exists
) ELSE (
    ECHO   ⚠️  config directory missing - will be downloaded
)

IF EXIST "%WORKING_DIR%modules" (
    ECHO   ✅ modules directory exists
) ELSE (
    ECHO   ⚠️  modules directory missing - will be downloaded
)

ECHO.
ECHO [STEP 7] Antivirus/Security Check
ECHO ----------------------------------
ECHO Windows Defender status:
powershell -NoProfile -Command "try { Get-MpComputerStatus | Select-Object -ExpandProperty RealTimeProtectionEnabled } catch { 'Unknown' }" >temp_av.txt 2>nul
SET /P AV_STATUS=<temp_av.txt
DEL temp_av.txt >nul 2>&1
IF "%AV_STATUS%"=="True" (
    ECHO   ✅ Windows Defender active - may need exclusions
) ELSE IF "%AV_STATUS%"=="False" (
    ECHO   ⚠️  Windows Defender disabled - third-party AV may interfere
) ELSE (
    ECHO   ⚠️  Cannot determine antivirus status
)

ECHO.
ECHO [STEP 8] Execution Policy Check
ECHO --------------------------------
FOR /F "tokens=*" %%i IN ('powershell -NoProfile -Command "Get-ExecutionPolicy" 2^>nul') DO SET EXEC_POLICY=%%i
ECHO Current execution policy: %EXEC_POLICY%
IF "%EXEC_POLICY%"=="Restricted" (
    ECHO   ❌ Execution policy too restrictive - may cause crashes
    ECHO      Script uses -ExecutionPolicy Bypass to work around this
) ELSE (
    ECHO   ✅ Execution policy allows script execution
)

ECHO.
ECHO [STEP 9] Memory and Disk Check
ECHO -------------------------------
FOR /F "tokens=*" %%i IN ('powershell -NoProfile -Command "'{0:N2} GB' -f ((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory/1GB)" 2^>nul') DO SET TOTAL_RAM=%%i
ECHO Total RAM: %TOTAL_RAM%

FOR /F "tokens=*" %%i IN ('powershell -NoProfile -Command "'{0:N2} GB' -f ((Get-CimInstance Win32_LogicalDisk -Filter \"DeviceID='%SystemDrive%'\").FreeSpace/1GB)" 2^>nul') DO SET FREE_SPACE=%%i
ECHO Free space on %SystemDrive%: %FREE_SPACE%

ECHO.
ECHO [STEP 10] Common Crash Simulation
ECHO ----------------------------------
ECHO Testing PowerShell execution:
powershell -NoProfile -ExecutionPolicy Bypass -Command "Write-Host 'PowerShell execution test successful'" 2>test_error.txt
IF %ERRORLEVEL% EQU 0 (
    ECHO   ✅ PowerShell execution works
) ELSE (
    ECHO   ❌ PowerShell execution failed!
    ECHO   Error details:
    TYPE test_error.txt
)
DEL test_error.txt >nul 2>&1

ECHO.
ECHO ================================================================
ECHO  DIAGNOSTIC COMPLETE - ANALYSIS AND RECOMMENDATIONS
ECHO ================================================================

ECHO.
ECHO MOST COMMON CRASH CAUSES AND SOLUTIONS:
ECHO.
ECHO 1. NOT RUNNING AS ADMINISTRATOR
ECHO    ➤ Right-click script.bat and select "Run as administrator"
ECHO.
ECHO 2. ANTIVIRUS INTERFERENCE
ECHO    ➤ Add script folder to antivirus exclusions
ECHO    ➤ Temporarily disable real-time protection during first run
ECHO.
ECHO 3. NETWORK/FIREWALL BLOCKING DOWNLOADS
ECHO    ➤ Ensure GitHub.com is accessible
ECHO    ➤ Check corporate firewall settings
ECHO    ➤ Try running on different network (mobile hotspot)
ECHO.
ECHO 4. POWERSHELL EXECUTION POLICY
ECHO    ➤ Run: Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
ECHO.
ECHO 5. INSUFFICIENT DISK SPACE
ECHO    ➤ Ensure at least 1GB free space on system drive
ECHO.
ECHO 6. CORRUPTED DOWNLOAD
ECHO    ➤ Re-download script.bat from GitHub
ECHO    ➤ Verify file integrity
ECHO.

ECHO TO ENABLE DETAILED CRASH DIAGNOSTICS:
ECHO 1. Open Command Prompt as Administrator
ECHO 2. Navigate to script folder: cd /d "%WORKING_DIR%"
ECHO 3. Run with verbose logging: script.bat ^>debug_log.txt 2^>^&1
ECHO 4. Check debug_log.txt for exact error location
ECHO.

ECHO IMMEDIATE TROUBLESHOOTING STEPS:
ECHO 1. Ensure Administrator privileges ✓
ECHO 2. Add folder to AV exclusions ✓  
ECHO 3. Check internet connectivity ✓
ECHO 4. Re-run script.bat ✓
ECHO.

SET /P "RUN_SCRIPT=Would you like to try running script.bat now? (Y/N): "
IF /I "%RUN_SCRIPT%"=="Y" (
    ECHO.
    ECHO Running script.bat with diagnostic logging...
    ECHO ================================================================
    CALL "%WORKING_DIR%script.bat" >debug_output.txt 2>&1
    SET "SCRIPT_EXIT_CODE=!ERRORLEVEL!"
    
    IF !SCRIPT_EXIT_CODE! EQU 0 (
        ECHO ✅ Script completed successfully!
    ) ELSE (
        ECHO ❌ Script failed with exit code: !SCRIPT_EXIT_CODE!
        ECHO.
        ECHO Last 20 lines of output:
        powershell -Command "Get-Content debug_output.txt | Select-Object -Last 20"
        ECHO.
        ECHO Full log saved to: debug_output.txt
    )
)

PAUSE
ENDLOCAL