
@echo off
setlocal

REM === Central Coordination and Execution Policy ===
REM Set the URL to the raw script.ps1 in your GitHub repo
set "SCRIPT_URL=https://raw.githubusercontent.com/ichimbogdancristian/script_mentenanta/main/script.ps1"
set "SCRIPT_NAME=script.ps1"

REM Download the latest script.ps1 (overwrite if exists)
powershell -NoProfile -Command "try { Invoke-WebRequest -Uri '%SCRIPT_URL%' -OutFile '%SCRIPT_NAME%' -ErrorAction Stop } catch { Write-Host 'Download failed.'; exit 1 }"
if errorlevel 1 (
    echo Failed to download script.ps1. Exiting.
    exit /b 1
)



echo Before running PowerShell script
REM Execute script.ps1 in PowerShell 5.1, bypassing execution policy for this session only
REM Show all output and errors in the console, and display the exit code
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_NAME%" -Verbose -ErrorAction Continue
set "PS_EXIT_CODE=%ERRORLEVEL%"
echo After running PowerShell script
echo PowerShell script exited with code: %PS_EXIT_CODE%

if not %PS_EXIT_CODE%==0 (
    echo There was an error running script.ps1. Please check your permissions and requirements.
)

REM Prompt to close the window
echo.
set /p CLOSE_PROMPT="Press Enter to close this window..."

REM Centralized logging or coordination can be added here
REM For example, collect exit codes, send logs, etc.

pause

endlocal
