@echo off
setlocal enabledelayedexpansion

REM --- [SETUP] Get script directory ---
set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
echo [INFO] Script directory: "%SCRIPT_DIR%"

REM --- [VARIABLES] ---
set "REPO_URL=https://github.com/ichimbogdancristian/script_mentenanta/archive/refs/heads/main.zip"
set "ZIP_PATH=%SCRIPT_DIR%\script_mentenanta.zip"
set "EXTRACT_DIR=%SCRIPT_DIR%\script_mentenanta"
set "PS_SCRIPT=script.ps1"

REM --- [DEPENDENCY TASK] Ensure Winget and PowerShell 7 are available ---
REM Check for admin rights
net session >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] This script requires administrator privileges.
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

echo [DEPENDENCY] Checking for Winget and PowerShell 7...
powershell -NoProfile -Command "
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $winget) {
        Write-Host '[INFO] Winget not found. Installing...'
        $frameworkUrl = 'https://www.nuget.org/api/v2/package/Microsoft.UI.Xaml/2.8.6'
        $frameworkPath = \"$env:TEMP\Microsoft.UI.Xaml.2.8.6.zip\"
        Invoke-WebRequest -Uri $frameworkUrl -OutFile $frameworkPath
        $frameworkExtract = \"$env:TEMP\Microsoft.UI.Xaml.2.8.6\"
        Expand-Archive -Path $frameworkPath -DestinationPath $frameworkExtract -Force
        $appx = Get-ChildItem -Path $frameworkExtract -Filter *.appx -Recurse | Select-Object -First 1
        if ($appx) { Add-AppxPackage -Path $appx.FullName }
        Invoke-WebRequest -Uri 'https://aka.ms/getwinget' -OutFile \"$env:TEMP\AppInstaller.msixbundle\"
        Add-AppxPackage -Path \"$env:TEMP\AppInstaller.msixbundle\"
        Write-Host '[INFO] Winget installed.'
        exit 301
    }
    $pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
    if (-not $pwsh) {
        Write-Host '[INFO] PowerShell 7 not found. Installing...'
        winget install --id Microsoft.Powershell --accept-source-agreements --accept-package-agreements --silent
        Write-Host '[INFO] PowerShell 7 installed.'
    } else {
        Write-Host '[INFO] PowerShell 7 found.'
    }
    exit 0
"
if %ERRORLEVEL%==301 (
    echo [INFO] Winget was just installed. The script will restart in 5 seconds...
    echo [%date% %time%] [INFO] Winget installed, restarting script. >> "%SCRIPT_DIR%\script_mentenanta.log"
    timeout /t 5 >nul
    powershell -NoProfile -Command "Start-Process -FilePath 'cmd.exe' -ArgumentList '/k \"%~f0\"' -WindowStyle Normal"
    exit /b
)

REM --- [TASK 3] Download repository ZIP ---
echo [TASK] Downloading repository...
powershell -NoProfile -Command ^
    "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; ^
    try { Invoke-WebRequest -Uri '%REPO_URL%' -OutFile '%ZIP_PATH%' -ErrorAction Stop } ^
    catch { Write-Host '[ERROR] Download failed.'; if ($_.Exception) { Write-Host $_.Exception.Message }; exit 1 }"
if errorlevel 1 (
    echo [ERROR] Failed to download repository.
    goto END
)

REM --- [TASK 4] Remove previous extraction ---
if exist "%EXTRACT_DIR%" (
    echo [TASK] Removing previous folder: "%EXTRACT_DIR%"
    rmdir /s /q "%EXTRACT_DIR%"
    if errorlevel 1 (
        echo [ERROR] Failed to remove previous folder.
        goto END
    )
)

REM --- [TASK 5] Extract ZIP ---
echo [TASK] Extracting repository...
powershell -NoProfile -Command ^
    "try { Expand-Archive -Path '%ZIP_PATH%' -DestinationPath '%EXTRACT_DIR%' -Force -ErrorAction Stop } ^
    catch { Write-Host '[ERROR] Extraction failed.'; if ($_.Exception) { Write-Host $_.Exception.Message }; exit 1 }"
if errorlevel 1 (
    echo [ERROR] Failed to extract repository.
    goto END
)

REM --- [TASK 6] Delete ZIP file ---
echo [TASK] Deleting ZIP file...
del "%ZIP_PATH%"
if errorlevel 1 (
    echo [ERROR] Failed to delete ZIP file.
)

REM --- [TASK 7] Move extracted content if in subfolder ---
for /d %%D in ("%EXTRACT_DIR%\script_mentenanta-*") do (
    echo [TASK] Moving files from "%%D" to "%EXTRACT_DIR%"
    xcopy /e /h /y "%%D\*" "%EXTRACT_DIR%\"
    if errorlevel 1 (
        echo [ERROR] Failed to move files.
        goto END
    )
    rmdir /s /q "%%D"
)

REM --- [TASK 8] Run PowerShell script ---
echo [TASK] Running PowerShell script: "%EXTRACT_DIR%\%PS_SCRIPT%"
pwsh -NoProfile -ExecutionPolicy Bypass -File "%EXTRACT_DIR%\%PS_SCRIPT%" -Verbose
set "PS_EXIT_CODE=%ERRORLEVEL%"
echo [INFO] PowerShell script exited with code: %PS_EXIT_CODE%

if not "%PS_EXIT_CODE%"=="0" (
    echo [ERROR] script.ps1 failed. Check permissions and requirements.
)

:END
echo.
echo [INFO] Script finished.
pause
endlocal