@echo on
setlocal


REM Get the directory where this script is located (removes trailing backslash)
echo [INFO] Determining script directory...
set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
echo [INFO] Script directory is: %SCRIPT_DIR%

REM Set repo folder name (matches the extracted folder name from the zip)
set "REPO_FOLDER=script_mentenanta-master"
echo [INFO] Repository folder will be: %REPO_FOLDER%

REM Set variables
set "REPO_URL=https://github.com/ichimbogdancristian/script_mentenanta/archive/refs/heads/master.zip"
set "ZIP_NAME=%SCRIPT_DIR%repo.zip"
set "EXTRACTED_DIR=%SCRIPT_DIR%%REPO_FOLDER%"
set "PS_SCRIPT=script.ps1"
echo [INFO] Variables set:
echo   REPO_URL: %REPO_URL%
echo   ZIP_NAME: %ZIP_NAME%
echo   EXTRACTED_DIR: %EXTRACTED_DIR%
echo   PS_SCRIPT: %PS_SCRIPT%

REM Download the repo as zip (force TLS 1.2 for GitHub compatibility)
echo [STEP] Downloading repository to %ZIP_NAME% ...
powershell -NoProfile -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; try { Invoke-WebRequest -Uri '%REPO_URL%' -OutFile '%ZIP_NAME%' -ErrorAction Stop } catch { Write-Host '[ERROR] Download failed.'; if ($_.Exception) { Write-Host $_.Exception.Message }; exit 1 }"
if errorlevel 1 (
    echo [ERROR] Failed to download repository. See the error message above for details.
    goto END
)

REM Extract the zip (requires PowerShell 5+)
echo [STEP] Extracting repository to %SCRIPT_DIR% ...
powershell -NoProfile -Command "try { Expand-Archive -Path '%ZIP_NAME%' -DestinationPath '%SCRIPT_DIR%' -Force -ErrorAction Stop } catch { Write-Host '[ERROR] Extraction failed.'; if ($_.Exception) { Write-Host $_.Exception.Message }; exit 1 }"
if errorlevel 1 (
    echo [ERROR] Failed to extract repository. Exiting.
    goto END
)

REM Delete the zip file
echo [STEP] Deleting zip file: %ZIP_NAME%
del "%ZIP_NAME%"
if errorlevel 1 (
    echo [ERROR] Failed to delete zip file: %ZIP_NAME%
)



REM Run the PowerShell script from the extracted repo
echo [STEP] Running PowerShell script from: %EXTRACTED_DIR%\%PS_SCRIPT%
powershell -NoProfile -ExecutionPolicy Bypass -File "%EXTRACTED_DIR%\%PS_SCRIPT%" -Verbose -ErrorAction Continue
set "PS_EXIT_CODE=%ERRORLEVEL%"
echo [INFO] PowerShell script exited with code: %PS_EXIT_CODE%

if not %PS_EXIT_CODE%==0 (
    echo [ERROR] There was an error running script.ps1. Please check your permissions and requirements.
)

:END
echo.
echo [INFO] Script finished.
set /p CLOSE_PROMPT="Press Enter to close this window..."
endlocal