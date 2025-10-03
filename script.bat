@echo off
REM ============================================================================
REM  Windows Maintenance Automation Launcher v3.1 (Skip Existing Dependencies)
REM  Purpose: Unattended launcher for Windows maintenance system
REM  Requirements: Windows 10/11, Administrator privileges, PowerShell 5.1+
REM ============================================================================

SETLOCAL ENABLEDELAYEDEXPANSION

REM -----------------------------------------------------------------------------
REM Simple Logging Function
REM -----------------------------------------------------------------------------
GOTO :MAIN_SCRIPT

:LOG
SET "TIMESTAMP=%DATE% %TIME:~0,8%"
ECHO [%TIMESTAMP%] %~1
IF DEFINED LOG_FILE ECHO [%TIMESTAMP%] %~1 >> "%LOG_FILE%" 2>nul
EXIT /B

:MAIN_SCRIPT

REM -----------------------------------------------------------------------------
REM Initialize Environment
REM -----------------------------------------------------------------------------
SET "SCRIPT_DIR=%~dp0"
SET "WORKING_DIR=%SCRIPT_DIR%"

REM Setup single log file
IF NOT EXIST "%WORKING_DIR%temp_files\logs" MD "%WORKING_DIR%temp_files\logs" 2>nul
SET "LOG_FILE=%WORKING_DIR%temp_files\logs\maintenance_%DATE:~-4,4%%DATE:~-10,2%%DATE:~-7,2%_%TIME:~0,2%%TIME:~3,2%%TIME:~6,2%.log"
SET "LOG_FILE=%LOG_FILE: =0%"

CALL :LOG "=========================================="
CALL :LOG "Windows Maintenance Launcher v3.1"
CALL :LOG "=========================================="
CALL :LOG "Log file: %LOG_FILE%"

REM -----------------------------------------------------------------------------
REM Administrator Check
REM -----------------------------------------------------------------------------
CALL :LOG "Checking administrator privileges..."
NET SESSION >nul 2>&1
IF !ERRORLEVEL! NEQ 0 (
    CALL :LOG "ERROR: Administrator privileges required - elevating..."
    powershell -NoProfile -Command "Start-Process cmd -ArgumentList '/c \"%~f0\"' -Verb RunAs" >nul 2>&1
    EXIT /B 0
)
CALL :LOG "Administrator privileges confirmed"

REM -----------------------------------------------------------------------------
REM Verify PowerShell 5.1+
REM -----------------------------------------------------------------------------
CALL :LOG "Checking PowerShell version..."
FOR /F "tokens=*" %%i IN ('powershell -NoProfile -Command "$PSVersionTable.PSVersion.Major" 2^>nul') DO SET "PS_VERSION=%%i"
IF "%PS_VERSION%"=="" SET "PS_VERSION=0"
CALL :LOG "PowerShell version: %PS_VERSION%"

IF %PS_VERSION% LSS 5 (
    CALL :LOG "ERROR: PowerShell 5.1 or higher required"
    TIMEOUT /T 10 /NOBREAK >nul
    EXIT /B 1
)

REM -----------------------------------------------------------------------------
REM Check PowerShell 7
REM -----------------------------------------------------------------------------
CALL :LOG "Checking for PowerShell 7..."
SET "PS7_AVAILABLE=NO"
SET "PS7_PATH="

pwsh.exe -Version >nul 2>&1
IF !ERRORLEVEL! EQU 0 (
    FOR /F "tokens=*" %%i IN ('pwsh.exe -NoProfile -Command "$PSVersionTable.PSVersion.ToString()" 2^>nul') DO SET "PS7_VERSION=%%i"
    SET "PS7_AVAILABLE=YES"
    SET "PS7_PATH=pwsh.exe"
    CALL :LOG "PowerShell 7 found in PATH: !PS7_VERSION!"
    GOTO :CHECK_WINGET
)

FOR %%P IN (
    "%ProgramFiles%\PowerShell\7\pwsh.exe"
    "%ProgramFiles(x86)%\PowerShell\7\pwsh.exe"
    "%LOCALAPPDATA%\Microsoft\WindowsApps\pwsh.exe"
) DO (
    IF EXIST "%%~P" (
        SET "PS7_PATH=%%~P"
        SET "PS7_AVAILABLE=YES"
        FOR /F "tokens=*" %%V IN ('"%%~P" -NoProfile -Command "$PSVersionTable.PSVersion.ToString()" 2^>nul') DO SET "PS7_VERSION=%%V"
        CALL :LOG "PowerShell 7 found at: %%~P (version !PS7_VERSION!)"
        GOTO :CHECK_WINGET
    )
)

CALL :LOG "PowerShell 7 not found - installing..."
CALL :INSTALL_PS7

REM -----------------------------------------------------------------------------
REM Check and Install Winget
REM -----------------------------------------------------------------------------
:CHECK_WINGET
CALL :LOG "Checking for Winget..."
winget --version >nul 2>&1
IF !ERRORLEVEL! EQU 0 (
    FOR /F "tokens=*" %%i IN ('winget --version 2^>nul') DO SET "WINGET_VERSION=%%i"
    CALL :LOG "Winget already installed: !WINGET_VERSION! - skipping"
    GOTO :CHECK_NUGET
)

CALL :LOG "Winget not found - installing..."
SET "WINGET_URL=https://github.com/microsoft/winget-cli/releases/latest/download/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"
SET "WINGET_FILE=%TEMP%\Microsoft.DesktopAppInstaller.msixbundle"

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$ProgressPreference = 'SilentlyContinue'; " ^
    "try { " ^
    "    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; " ^
    "    Invoke-WebRequest -Uri '%WINGET_URL%' -OutFile '%WINGET_FILE%' -UseBasicParsing -TimeoutSec 120; " ^
    "    Add-AppxPackage -Path '%WINGET_FILE%'; " ^
    "    Write-Host 'Winget installed'; " ^
    "} catch { " ^
    "    Write-Host 'Winget installation failed:' $_.Exception.Message; " ^
    "}"

DEL /F /Q "%WINGET_FILE%" >nul 2>&1
CALL :LOG "Winget installation attempted"

REM -----------------------------------------------------------------------------
REM Check and Install NuGet
REM -----------------------------------------------------------------------------
:CHECK_NUGET
CALL :LOG "Checking for NuGet PackageProvider..."
powershell -NoProfile -Command "if (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue) { exit 0 } else { exit 1 }" >nul 2>&1
IF !ERRORLEVEL! EQU 0 (
    CALL :LOG "NuGet PackageProvider already installed - skipping"
    GOTO :CHECK_PSGALLERY
)

CALL :LOG "NuGet PackageProvider not found - installing..."
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$ProgressPreference = 'SilentlyContinue'; " ^
    "$ErrorActionPreference = 'SilentlyContinue'; " ^
    "$ConfirmPreference = 'None'; " ^
    "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; " ^
    "Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope AllUsers -Confirm:$false -ForceBootstrap | Out-Null; " ^
    "Write-Host 'NuGet installed'"

CALL :LOG "NuGet installation complete"

REM -----------------------------------------------------------------------------
REM Check and Configure PSGallery
REM -----------------------------------------------------------------------------
:CHECK_PSGALLERY
CALL :LOG "Checking PSGallery configuration..."
powershell -NoProfile -Command "$repo = Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue; if ($repo -and $repo.InstallationPolicy -eq 'Trusted') { exit 0 } else { exit 1 }" >nul 2>&1
IF !ERRORLEVEL! EQU 0 (
    CALL :LOG "PSGallery already configured as trusted - skipping"
    GOTO :CHECK_PSWINDOWSUPDATE
)

CALL :LOG "PSGallery not configured - setting as trusted..."
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$ErrorActionPreference = 'SilentlyContinue'; " ^
    "$ConfirmPreference = 'None'; " ^
    "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; " ^
    "if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) { " ^
    "    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope AllUsers -Confirm:$false -ForceBootstrap | Out-Null; " ^
    "}; " ^
    "Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -Confirm:$false | Out-Null; " ^
    "Write-Host 'PSGallery configured'"

CALL :LOG "PSGallery configuration complete"

REM -----------------------------------------------------------------------------
REM Check and Install PSWindowsUpdate
REM -----------------------------------------------------------------------------
:CHECK_PSWINDOWSUPDATE
CALL :LOG "Checking for PSWindowsUpdate module..."
powershell -NoProfile -Command "if (Get-Module -ListAvailable -Name PSWindowsUpdate) { exit 0 } else { exit 1 }" >nul 2>&1
IF !ERRORLEVEL! EQU 0 (
    CALL :LOG "PSWindowsUpdate module already installed - skipping"
    GOTO :CHECK_CHOCOLATEY
)

CALL :LOG "PSWindowsUpdate module not found - installing..."
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$ProgressPreference = 'SilentlyContinue'; " ^
    "$ErrorActionPreference = 'SilentlyContinue'; " ^
    "$ConfirmPreference = 'None'; " ^
    "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; " ^
    "Install-Module -Name PSWindowsUpdate -Force -Scope AllUsers -AllowClobber -Confirm:$false -SkipPublisherCheck | Out-Null; " ^
    "Write-Host 'PSWindowsUpdate installed'"

CALL :LOG "PSWindowsUpdate installation complete"

REM -----------------------------------------------------------------------------
REM Check and Install Chocolatey
REM -----------------------------------------------------------------------------
:CHECK_CHOCOLATEY
CALL :LOG "Checking for Chocolatey..."
choco --version >nul 2>&1
IF !ERRORLEVEL! EQU 0 (
    FOR /F "tokens=*" %%i IN ('choco --version 2^>nul') DO SET "CHOCO_VERSION=%%i"
    CALL :LOG "Chocolatey already installed: !CHOCO_VERSION! - skipping"
    GOTO :FIND_ORCHESTRATOR
)

CALL :LOG "Chocolatey not found - installing..."
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$ProgressPreference = 'SilentlyContinue'; " ^
    "try { " ^
    "    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; " ^
    "    Set-ExecutionPolicy Bypass -Scope Process -Force; " ^
    "    $chocoScript = (New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'); " ^
    "    Invoke-Expression $chocoScript; " ^
    "    Write-Host 'Chocolatey installed'; " ^
    "} catch { " ^
    "    Write-Host 'Chocolatey installation failed:' $_.Exception.Message; " ^
    "}"

IF EXIST "%ProgramData%\chocolatey\bin" SET "PATH=%PATH%;%ProgramData%\chocolatey\bin"
CALL :LOG "Chocolatey installation attempted"

REM -----------------------------------------------------------------------------
REM Find Orchestrator
REM -----------------------------------------------------------------------------
:FIND_ORCHESTRATOR
CALL :LOG "Locating orchestrator script..."
SET "ORCHESTRATOR_PATH="

IF EXIST "%WORKING_DIR%MaintenanceOrchestrator.ps1" (
    SET "ORCHESTRATOR_PATH=%WORKING_DIR%MaintenanceOrchestrator.ps1"
) ELSE IF EXIST "%WORKING_DIR%script.ps1" (
    SET "ORCHESTRATOR_PATH=%WORKING_DIR%script.ps1"
) ELSE (
    CALL :LOG "ERROR: No orchestrator found"
    TIMEOUT /T 10 /NOBREAK >nul
    EXIT /B 2
)

CALL :LOG "Orchestrator: %ORCHESTRATOR_PATH%"

REM -----------------------------------------------------------------------------
REM Execute Orchestrator
REM -----------------------------------------------------------------------------
CALL :LOG "Starting maintenance execution..."

IF "%PS7_AVAILABLE%"=="YES" (
    CALL :LOG "Using PowerShell 7"
    "%PS7_PATH%" -NoProfile -ExecutionPolicy Bypass -File "%ORCHESTRATOR_PATH%" -WorkingDirectory "%WORKING_DIR%" -LogFile "%LOG_FILE%"
) ELSE (
    CALL :LOG "Using PowerShell 5.1"
    powershell -NoProfile -ExecutionPolicy Bypass -File "%ORCHESTRATOR_PATH%" -WorkingDirectory "%WORKING_DIR%" -LogFile "%LOG_FILE%"
)

SET "RESULT=!ERRORLEVEL!"
CALL :LOG "Maintenance completed with exit code: %RESULT%"
CALL :LOG "=========================================="

EXIT /B %RESULT%

REM -----------------------------------------------------------------------------
REM Install PowerShell 7 Function
REM -----------------------------------------------------------------------------
:INSTALL_PS7
CALL :LOG "Determining system architecture..."
IF "%PROCESSOR_ARCHITECTURE%"=="AMD64" (
    SET "PS7_URL=https://github.com/PowerShell/PowerShell/releases/download/v7.5.2/PowerShell-7.5.2-win-x64.msi"
) ELSE IF "%PROCESSOR_ARCHITECTURE%"=="ARM64" (
    SET "PS7_URL=https://github.com/PowerShell/PowerShell/releases/download/v7.5.2/PowerShell-7.5.2-win-arm64.msi"
) ELSE (
    SET "PS7_URL=https://github.com/PowerShell/PowerShell/releases/download/v7.5.2/PowerShell-7.5.2-win-x86.msi"
)

SET "PS7_INSTALLER=%TEMP%\PowerShell-7-Setup.msi"
CALL :LOG "Downloading PowerShell 7..."

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$ProgressPreference = 'SilentlyContinue'; " ^
    "try { " ^
    "    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; " ^
    "    Invoke-WebRequest -Uri '%PS7_URL%' -OutFile '%PS7_INSTALLER%' -UseBasicParsing -TimeoutSec 300; " ^
    "    Write-Host 'Download complete'; " ^
    "} catch { " ^
    "    Write-Host 'Download failed:' $_.Exception.Message; " ^
    "    exit 1; " ^
    "}"

IF !ERRORLEVEL! NEQ 0 (
    CALL :LOG "ERROR: PowerShell 7 download failed"
    EXIT /B 1
)

CALL :LOG "Installing PowerShell 7..."
msiexec /i "%PS7_INSTALLER%" /quiet /norestart /log "%TEMP%\PS7_Install.log"
SET "INSTALL_RESULT=!ERRORLEVEL!"

IF %INSTALL_RESULT% EQU 0 (
    CALL :LOG "PowerShell 7 installed successfully"
) ELSE IF %INSTALL_RESULT% EQU 3010 (
    CALL :LOG "PowerShell 7 installed (restart required)"
) ELSE (
    CALL :LOG "WARNING: PowerShell 7 installation returned code %INSTALL_RESULT%"
)

DEL /F /Q "%PS7_INSTALLER%" >nul 2>&1

REM Wait and refresh PATH
TIMEOUT /T 5 /NOBREAK >nul
FOR /F "usebackq tokens=2*" %%A IN (`REG QUERY "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" /v PATH 2^>nul`) DO SET "PATH=%%B"
IF EXIST "%ProgramFiles%\PowerShell\7" SET "PATH=%PATH%;%ProgramFiles%\PowerShell\7"

REM Verify installation
pwsh.exe -Version >nul 2>&1
IF !ERRORLEVEL! EQU 0 (
    SET "PS7_AVAILABLE=YES"
    SET "PS7_PATH=pwsh.exe"
    FOR /F "tokens=*" %%V IN ('pwsh.exe -NoProfile -Command "$PSVersionTable.PSVersion.ToString()" 2^>nul') DO SET "PS7_VERSION=%%V"
    CALL :LOG "PowerShell 7 verified and ready: !PS7_VERSION!"
) ELSE (
    CALL :LOG "WARNING: PowerShell 7 not available after installation"
)

EXIT /B 0