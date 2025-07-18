@echo off
setlocal enabledelayedexpansion

REM === [SETUP] ===
set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
set "REPO_URL=https://github.com/ichimbogdancristian/script_mentenanta/archive/refs/heads/main.zip"
set "ZIP_PATH=%SCRIPT_DIR%\script_mentenanta.zip"
set "EXTRACT_DIR=%SCRIPT_DIR%\script_mentenanta"
set "PS_SCRIPT=script.ps1"
set "LOG_FILE=%SCRIPT_DIR%\script_mentenanta.log"

echo [INFO] Script directory: "%SCRIPT_DIR%"

REM === [ADMIN CHECK] ===
net session >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Administrator privileges required.
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

REM === [DEPENDENCY CHECK] ===
where winget >nul 2>&1
if errorlevel 1 (
    echo [INFO] Winget not found. Please install Winget manually.
    goto END
)
where pwsh >nul 2>&1
if errorlevel 1 (
    echo [INFO] PowerShell 7 (pwsh) not found. Installing...
    winget install --id Microsoft.Powershell --accept-source-agreements --accept-package-agreements --silent
    if errorlevel 1 (
        echo [ERROR] Failed to install PowerShell 7.
        goto END
    )
)

REM === [DOWNLOAD REPO] ===
echo [TASK] Downloading repository ZIP...
powershell -NoProfile -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; try { Invoke-WebRequest -Uri '%REPO_URL%' -OutFile '%ZIP_PATH%' -ErrorAction Stop } catch { Write-Host '[ERROR] Download failed.'; exit 1 }"
if errorlevel 1 (
    echo [ERROR] Failed to download repository.
    goto END
)
pause

REM === [REMOVE OLD EXTRACTION] ===
if exist "%EXTRACT_DIR%" (
    echo [TASK] Removing previous extraction...
    rmdir /s /q "%EXTRACT_DIR%"
    if errorlevel 1 (
        echo [ERROR] Failed to remove previous extraction.
        goto END
    )
)
pause

REM === [EXTRACT ZIP] ===
echo [TASK] Extracting ZIP...
powershell -NoProfile -Command "try { Expand-Archive -Path '%ZIP_PATH%' -DestinationPath '%EXTRACT_DIR%' -Force -ErrorAction Stop } catch { Write-Host '[ERROR] Extraction failed.'; exit 1 }"
if errorlevel 1 (
    echo [ERROR] Failed to extract ZIP.
    goto END
)
pause

REM === [DELETE ZIP] ===
echo [TASK] Deleting ZIP file...
del "%ZIP_PATH%"
if errorlevel 1 (
    echo [ERROR] Failed to delete ZIP file.
)
pause

REM === [MOVE FILES IF SUBFOLDER] ===
for /d %%D in ("%EXTRACT_DIR%\script_mentenanta-*") do (
    echo [TASK] Moving files from "%%D" to "%EXTRACT_DIR%"
    xcopy /e /h /y "%%D\*" "%EXTRACT_DIR%\\"
    rmdir /s /q "%%D"
)
pause

REM === [RUN POWERSHELL SCRIPT] ===
echo [TASK] Running PowerShell script...
pwsh -NoProfile -ExecutionPolicy Bypass -File "%EXTRACT_DIR%\%PS_SCRIPT%" -Verbose
set "PS_EXIT_CODE=%ERRORLEVEL%"
echo [INFO] PowerShell script exited with code: %PS_EXIT_CODE%
if not "%PS_EXIT_CODE%"=="0" (
    echo [ERROR] script.ps1 failed with exit code %PS_EXIT_CODE%. See log: %LOG_FILE%
    echo [%date% %time%] [ERROR] script.ps1 failed with exit code %PS_EXIT_CODE%. >> "%LOG_FILE%"
    pause
    goto END
)
pause

:END
echo [INFO] Script finished.
pause
endlocal