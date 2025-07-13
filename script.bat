@echo on
setlocal

REM Get the directory where this script is located (removes trailing backslash)
set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
echo [INFO] Script directory is: %SCRIPT_DIR%

REM Set variables
set "REPO_URL=https://github.com/ichimbogdancristian/script_mentenanta/archive/refs/heads/main.zip"
set "ZIP_NAME=%SCRIPT_DIR%script_mentenanta.zip"
set "EXTRACTED_DIR=%SCRIPT_DIR%script_mentenanta"
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

REM Remove any previous extraction
if exist "%EXTRACTED_DIR%" (
    echo [STEP] Removing previous folder: %EXTRACTED_DIR%
    rmdir /s /q "%EXTRACTED_DIR%"
    if errorlevel 1 (
        echo [ERROR] Failed to remove previous folder: %EXTRACTED_DIR%
        goto END
    )
)

REM Extract the zip (requires PowerShell 5+)
echo [STEP] Extracting repository to %EXTRACTED_DIR% ...
powershell -NoProfile -Command "try { Expand-Archive -Path '%ZIP_NAME%' -DestinationPath '%EXTRACTED_DIR%' -Force -ErrorAction Stop } catch { Write-Host '[ERROR] Extraction failed.'; if ($_.Exception) { Write-Host $_.Exception.Message }; exit 1 }"
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

REM Move extracted content from subfolder to %EXTRACTED_DIR% if needed
for /d %%D in ("%EXTRACTED_DIR%\script_mentenanta-*") do (
    echo [STEP] Moving extracted files from %%D to %EXTRACTED_DIR%
    xcopy /e /h /y "%%D\*" "%EXTRACTED_DIR%\"
    if errorlevel 1 (
        echo [ERROR] Failed to move files from %%D to %EXTRACTED_DIR%
        goto END
    )
    rmdir /s /q "%%D"
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