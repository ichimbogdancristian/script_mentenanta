@echo off
setlocal

REM Download the latest script.ps1 (overwrite if exists)
powershell -NoProfile -Command "try { Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/ichimbogdancristian/script_mentenanta/main/script.ps1' -OutFile 'script.ps1' -ErrorAction Stop } catch { Write-Host 'Download failed.'; exit 1 }"
if errorlevel 1 (
    echo Failed to download script.ps1. Exiting.
    goto END
)

echo Running PowerShell script...
powershell -NoProfile -ExecutionPolicy Bypass -File "script.ps1" -Verbose -ErrorAction Continue
set "PS_EXIT_CODE=%ERRORLEVEL%"
echo PowerShell script exited with code: %PS_EXIT_CODE%

if not %PS_EXIT_CODE%==0 (
    echo There was an error running script.ps1. Please check your permissions and requirements.
)

:END
echo.
set /p CLOSE_PROMPT="Press Enter to close this window..."
endlocal