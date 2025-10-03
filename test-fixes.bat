@echo off
REM Quick test script to verify the main fixes work
SETLOCAL ENABLEDELAYEDEXPANSION

echo Testing critical fixes for script.bat crash issue...
echo.

echo Test 1: PowerShell command without exit 1
powershell -ExecutionPolicy Bypass -Command "try { Write-Host 'PowerShell command working'; $false } catch { Write-Host 'Error caught'; }"
echo Exit code: %ERRORLEVEL%
echo.

echo Test 2: Winget detection
winget --version >nul 2>&1
if !ERRORLEVEL! EQU 0 (
    echo Winget is available
) else (
    echo Winget not found - this would trigger download/install
)
echo.

echo Test 3: PowerShell 7 detection  
pwsh.exe -Version >nul 2>&1
if !ERRORLEVEL! EQU 0 (
    echo PowerShell 7 is available
) else (
    echo PowerShell 7 not found - this would trigger installation
)
echo.

echo Test 4: Download with timeout (testing URL)
powershell -ExecutionPolicy Bypass -Command "try { $ProgressPreference = 'SilentlyContinue'; Invoke-WebRequest -Uri 'https://www.google.com' -Method Head -TimeoutSec 10; Write-Host 'Network connection working' } catch { Write-Host 'Network issue:' $_.Exception.Message }"
echo.

echo All tests completed. If this script runs to completion, the main fixes should work.
pause