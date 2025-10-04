@echo off
REM Test script to simulate how the scheduled task would run

ECHO Testing startup task simulation...
ECHO Current directory: %CD%
ECHO Script directory should be set correctly...

REM Simulate the fixed scheduled task command
SET "SCRIPT_DIR=C:\Users\Bogdan\OneDrive\Desktop\Projects\script_mentenanta\"
SET "SCRIPT_PATH=C:\Users\Bogdan\OneDrive\Desktop\Projects\script_mentenanta\script.bat"

ECHO.
ECHO Simulating: cmd.exe /c "cd /d "%SCRIPT_DIR%" && "%SCRIPT_PATH%" ELEVATED_INSTANCE"
ECHO.

REM Change to script directory first
cd /d "%SCRIPT_DIR%"
ECHO Now in directory: %CD%

REM Check if MaintenanceOrchestrator.ps1 exists
IF EXIST "MaintenanceOrchestrator.ps1" (
    ECHO ✅ SUCCESS: MaintenanceOrchestrator.ps1 found in current directory
) ELSE (
    ECHO ❌ FAIL: MaintenanceOrchestrator.ps1 NOT found in current directory
)

ECHO.
ECHO Test completed. Press any key to continue...
PAUSE >nul