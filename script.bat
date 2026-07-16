@echo off
REM ============================================================================
REM  Windows Maintenance Automation Launcher - Simple Batch Launcher
REM  Purpose: Install PowerShell 7 if missing, then launch orchestrator
REM  Requirements: Windows 10/11, Administrator privileges
REM ============================================================================

setlocal enabledelayedexpansion

echo.
echo ============================================================================
echo   Windows Maintenance Automation Launcher
echo ============================================================================
echo.

REM Get current directory
cd /d "%~dp0"
set WORKING_DIR=%cd%

echo Working Directory: %WORKING_DIR%
echo.

REM Check for admin privileges
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo.
    echo ERROR: This script requires Administrator privileges!
    echo Please right-click and select "Run as administrator"
    echo.
    pause
    exit /b 1
)

echo [OK] Running with Administrator privileges
echo.

REM ============================================================================
REM Step 1: Check for PowerShell 7
REM ============================================================================
echo ============================================================================
echo Step 1: Checking for PowerShell 7+
echo ============================================================================
echo.

set PS7_FOUND=NO
set PS7_EXE=

REM Check common PowerShell 7 installation locations
if exist "%ProgramFiles%\PowerShell\7\pwsh.exe" (
    set PS7_EXE=%ProgramFiles%\PowerShell\7\pwsh.exe
    set PS7_FOUND=YES
)

if "!PS7_FOUND!"=="NO" if exist "%LocalAppData%\Microsoft\WindowsApps\pwsh.exe" (
    set PS7_EXE=%LocalAppData%\Microsoft\WindowsApps\pwsh.exe
    set PS7_FOUND=YES
)

if "!PS7_FOUND!"=="NO" (
    pwsh.exe -version >nul 2>&1
    if !errorlevel! equ 0 (
        for /f "delims=" %%A in ('where pwsh.exe 2^>nul') do (
            set PS7_EXE=%%A
            set PS7_FOUND=YES
        )
    )
)

if "!PS7_FOUND!"=="YES" (
    echo [OK] PowerShell 7 found: !PS7_EXE!
    echo.
) else (
    echo [NOT FOUND] PowerShell 7 is not installed
    echo.
    echo ============================================================================
    echo Step 2: Installing PowerShell 7
    echo ============================================================================
    echo.

    REM Try winget first
    echo Attempting installation via winget...
    winget install Microsoft.PowerShell --silent --accept-package-agreements --accept-source-agreements >nul 2>&1

    if !errorlevel! equ 0 (
        echo [OK] PowerShell 7 installed successfully via winget

        REM Try to find it
        if exist "%ProgramFiles%\PowerShell\7\pwsh.exe" (
            set PS7_EXE=%ProgramFiles%\PowerShell\7\pwsh.exe
            set PS7_FOUND=YES
        )

        if "!PS7_FOUND!"=="NO" if exist "%LocalAppData%\Microsoft\WindowsApps\pwsh.exe" (
            set PS7_EXE=%LocalAppData%\Microsoft\WindowsApps\pwsh.exe
            set PS7_FOUND=YES
        )
    ) else (
        echo [FAILED] Winget installation failed or winget not available
        echo.
        echo Please install PowerShell 7 manually:
        echo https://github.com/PowerShell/PowerShell/releases
        echo.
        echo Or install via PowerShell 5:
        echo   winget install Microsoft.PowerShell
        echo.
        pause
        exit /b 1
    )
)

if "!PS7_FOUND!"=="NO" (
    echo.
    echo ERROR: Could not locate PowerShell 7 after installation attempt
    echo.
    echo Please install manually from:
    echo https://github.com/PowerShell/PowerShell/releases
    echo.
    pause
    exit /b 1
)

echo.
echo ============================================================================
echo Step 3: Launching Orchestrator
echo ============================================================================
echo.

REM Verify orchestrator exists
if not exist "%WORKING_DIR%\MaintenanceOrchestrator.ps1" (
    echo ERROR: MaintenanceOrchestrator.ps1 not found in %WORKING_DIR%
    echo.
    pause
    exit /b 1
)

echo Launching MaintenanceOrchestrator.ps1 with PowerShell 7...
echo.

REM Launch PowerShell 7 with the orchestrator
REM Use -NoExit so window stays open after script completes
"!PS7_EXE!" -NoExit -ExecutionPolicy Bypass -Command "cd '!WORKING_DIR!'; & '!WORKING_DIR!\MaintenanceOrchestrator.ps1' @args" %*

exit /b %errorlevel%
