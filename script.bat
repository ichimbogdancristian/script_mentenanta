@echo off
setlocal

REM Set variables
set "REPO_URL=https://github.com/ichimbogdancristian/script_mentenanta/archive/refs/heads/main.zip"
set "ZIP_NAME=repo.zip"
set "EXTRACTED_DIR=script_mentenanta-main"
set "PS_SCRIPT=script.ps1"

REM Download the repo as zip
echo Downloading repository...
powershell -NoProfile -Command "try { Invoke-WebRequest -Uri '%REPO_URL%' -OutFile '%ZIP_NAME%' -ErrorAction Stop } catch { Write-Host 'Download failed.'; exit 1 }"
if errorlevel 1 (
    echo Failed to download repository. Exiting.
    goto END
)

REM Extract the zip (requires PowerShell 5+)
echo Extracting repository...
powershell -NoProfile -Command "Expand-Archive -Path '%ZIP_NAME%' -DestinationPath . -Force"
if errorlevel 1 (
    echo Failed to extract repository. Exiting.
    goto END
)

REM Delete the zip file
del "%ZIP_NAME%"

REM Run the PowerShell script from the extracted repo
echo Running PowerShell script...
powershell -NoProfile -ExecutionPolicy Bypass -File "%EXTRACTED_DIR%\%PS_SCRIPT%" -Verbose -ErrorAction Continue
set "PS_EXIT_CODE=%ERRORLEVEL%"
echo PowerShell script exited with code: %PS_EXIT_CODE%

if not %PS_EXIT_CODE%==0 (
    echo There was an error running script.ps1. Please check your permissions and requirements.
)

:END
echo.
set /p CLOSE_PROMPT="Press Enter to close this window..."
endlocal