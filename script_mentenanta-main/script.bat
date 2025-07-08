@echo off
setlocal


REM Get the directory where this script is located
set "SCRIPT_DIR=%~dp0"

REM Set variables
set "REPO_URL=https://github.com/ichimbogdancristian/script_mentenanta/archive/refs/heads/main.zip"
set "ZIP_NAME=%SCRIPT_DIR%repo.zip"
set "EXTRACTED_DIR=%SCRIPT_DIR%script_mentenanta-main"
set "PS_SCRIPT=script.ps1"

REM Download the repo as zip (force TLS 1.2 for GitHub compatibility)
echo Downloading repository to %ZIP_NAME% ...
powershell -NoProfile -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; try { Invoke-WebRequest -Uri '%REPO_URL%' -OutFile '%ZIP_NAME%' -ErrorAction Stop } catch { Write-Host 'Download failed.'; if ($_.Exception) { Write-Host $_.Exception.Message }; exit 1 }"
if errorlevel 1 (
    echo Failed to download repository. See the error message above for details.
    goto END
)

REM Extract the zip (requires PowerShell 5+)
echo Extracting repository to %SCRIPT_DIR% ...
powershell -NoProfile -Command "Expand-Archive -Path '%ZIP_NAME%' -DestinationPath '%SCRIPT_DIR%' -Force"
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