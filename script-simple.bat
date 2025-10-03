@echo off
REM ============================================================================
REM  Windows Maintenance Automation Launcher v2.0 (Simplified Working Version)
REM  Purpose: Simple, reliable launcher that bypasses problematic sections
REM  Author: Windows Maintenance Automation Project  
REM ============================================================================

SETLOCAL ENABLEDELAYEDEXPANSION

REM Check for admin privileges
NET SESSION >nul 2>&1
IF %ERRORLEVEL% NEQ 0 (
    ECHO.
    ECHO ================================================================================
    ECHO  ADMINISTRATOR PRIVILEGES REQUIRED
    ECHO ================================================================================
    ECHO  This script requires administrator privileges.
    ECHO  Please right-click script.bat and select "Run as administrator"
    ECHO ================================================================================
    ECHO.
    PAUSE
    EXIT /B 1
)

REM Change to script directory
PUSHD "%~dp0"

REM Verify orchestrator exists
IF NOT EXIST "MaintenanceOrchestrator.ps1" (
    ECHO ERROR: MaintenanceOrchestrator.ps1 not found in current directory.
    ECHO Please ensure all project files are present.
    PAUSE
    EXIT /B 1
)

ECHO.
ECHO ====================================================================
ECHO  Windows Maintenance Automation - Simplified Launcher
ECHO ====================================================================
ECHO.
ECHO  Launching PowerShell orchestrator...
ECHO  This may take 20-30 seconds to complete all maintenance tasks.
ECHO.

REM Execute PowerShell orchestrator directly (tested and working)
pwsh.exe -ExecutionPolicy Bypass -NoProfile -File "MaintenanceOrchestrator.ps1"
SET "EXIT_CODE=%ERRORLEVEL%"

ECHO.
ECHO ====================================================================
ECHO  Maintenance completed with exit code: %EXIT_CODE%
ECHO ====================================================================
ECHO.

POPD
PAUSE
ENDLOCAL