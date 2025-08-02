@echo off
chcp 65001 >nul 2>&1 || chcp 850 >nul 2>&1
setlocal enabledelayedexpansion

echo ===============================================
echo    Windows Maintenance Script v2.0
echo    Modular architecture with configuration
echo ===============================================

REM Check if running as administrator
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo [ERROR] This script must be run as Administrator.
    echo [INFO] Right-click the script and select "Run as administrator"
    pause
    exit /b 1
)

echo [INFO] Running with administrator privileges...

REM Check Windows version (Windows 10 = 10.0.x, Windows 11 = 10.0.x with build 22000+)
for /f "tokens=4-6 delims=. " %%i in ('ver') do (
    set "WIN_MAJOR=%%i"
    set "WIN_MINOR=%%j"
    set "WIN_BUILD=%%k"
)

REM Windows 10 and 11 both report as 10.0.x, so check if major version is 10
if "!WIN_MAJOR!" NEQ "10" (
    echo [ERROR] This script is designed for Windows 10 or 11 only.
    echo [INFO] Detected Windows version: !WIN_MAJOR!.!WIN_MINOR!.!WIN_BUILD!
    pause
    exit /b 1
)

echo [INFO] Windows version detected: !WIN_MAJOR!.!WIN_MINOR!.!WIN_BUILD!

REM Check if MaintenanceOrchestrator.ps1 exists locally
set "SCRIPT_PATH=%~dp0MaintenanceOrchestrator.ps1"
set "CONFIG_PATH=%~dp0config\maintenance-config.json"

if not exist "!SCRIPT_PATH!" (
    echo [ERROR] MaintenanceOrchestrator.ps1 not found in script directory
    echo [INFO] Expected location: !SCRIPT_PATH!
    pause
    exit /b 1
)

if not exist "!CONFIG_PATH!" (
    echo [ERROR] Configuration file not found
    echo [INFO] Expected location: !CONFIG_PATH!
    pause
    exit /b 1
)

echo [INFO] Maintenance script found: !SCRIPT_PATH!
echo [INFO] Configuration found: !CONFIG_PATH!

REM Check for PowerShell 7 first (preferred)
where pwsh >nul 2>&1
if %errorLevel% equ 0 (
    echo [INFO] PowerShell 7 detected, using pwsh.exe
    set "PS_COMMAND=pwsh"
) else (
    echo [WARNING] PowerShell 7 not found, using Windows PowerShell
    set "PS_COMMAND=powershell"
)

REM Check dependencies and install if needed
echo [INFO] Checking dependencies...
call :CHECK_DEPENDENCIES
if %errorLevel% neq 0 (
    echo [ERROR] Dependency check failed
    pause
    exit /b 1
)

REM Parse command line arguments
set "PS_ARGS="
set "TEST_MODE="
set "GENERATE_REPORT="
set "TASK_FILTER="

:PARSE_ARGS
if "%~1"=="" goto :ARGS_DONE
if /i "%~1"=="-test" (
    set "TEST_MODE=-TestMode"
    shift
    goto :PARSE_ARGS
)
if /i "%~1"=="-report" (
    set "GENERATE_REPORT=-GenerateReport"
    shift
    goto :PARSE_ARGS
)
if /i "%~1"=="-tasks" (
    if not "%~2"=="" (
        set "TASK_FILTER=-TaskFilter @('%~2')"
        shift
        shift
        goto :PARSE_ARGS
    )
)
shift
goto :PARSE_ARGS

:ARGS_DONE

REM Build PowerShell command
set "PS_ARGS=-ConfigPath '!CONFIG_PATH!' !TEST_MODE! !GENERATE_REPORT! !TASK_FILTER!"

echo.
echo [INFO] Starting maintenance session...
echo [INFO] Command: !PS_COMMAND! -ExecutionPolicy Bypass -File "!SCRIPT_PATH!" !PS_ARGS!
echo.

REM Execute the maintenance script
!PS_COMMAND! -ExecutionPolicy Bypass -File "!SCRIPT_PATH!" !PS_ARGS!
set "MAINTENANCE_RESULT=%errorLevel%"

if !MAINTENANCE_RESULT! equ 0 (
    echo.
    echo [SUCCESS] Maintenance session completed successfully
) else (
    echo.
    echo [ERROR] Maintenance session failed with exit code: !MAINTENANCE_RESULT!
)

echo.
echo Press any key to exit...
pause >nul
exit /b !MAINTENANCE_RESULT!

REM ========================================
REM Dependency checking functions
REM ========================================

:CHECK_DEPENDENCIES
echo [INFO] Checking for required dependencies...

REM Check for WinGet
where winget >nul 2>&1
if %errorLevel% neq 0 (
    echo [INFO] WinGet not found, installing...
    call :INSTALL_WINGET
    if %errorLevel% neq 0 (
        echo [ERROR] Failed to install WinGet
        exit /b 1
    )
)

REM Check for PowerShell 7 (recommended but not required)
where pwsh >nul 2>&1
if %errorLevel% neq 0 (
    echo [INFO] PowerShell 7 not found, installing...
    call :INSTALL_POWERSHELL7
    if %errorLevel% neq 0 (
        echo [WARNING] Failed to install PowerShell 7, will use Windows PowerShell
    )
)

echo [INFO] All dependencies checked
exit /b 0

:INSTALL_WINGET
echo [INFO] Installing WinGet and dependencies...

REM Check for Microsoft.VCLibs
powershell -Command "if (!(Get-AppxPackage -Name 'Microsoft.VCLibs.140.00.UWPDesktop')) { exit 1 }" >nul 2>&1
if %errorLevel% neq 0 (
    echo [INFO] Installing Microsoft.VCLibs...
    curl -L -o "%TEMP%\Microsoft.VCLibs.x64.14.00.Desktop.appx" "https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx"
    powershell -Command "Add-AppxPackage -Path '%TEMP%\Microsoft.VCLibs.x64.14.00.Desktop.appx'" >nul 2>&1
    del "%TEMP%\Microsoft.VCLibs.x64.14.00.Desktop.appx" >nul 2>&1
)

REM Check for Microsoft.UI.Xaml
powershell -Command "if (!(Get-AppxPackage -Name 'Microsoft.UI.Xaml.2.*')) { exit 1 }" >nul 2>&1
if %errorLevel% neq 0 (
    echo [INFO] Installing Microsoft.UI.Xaml...
    curl -L -o "%TEMP%\microsoft.ui.xaml.2.8.6.nupkg" "https://www.nuget.org/api/v2/package/Microsoft.UI.Xaml/2.8.6"
    powershell -Command "Expand-Archive -Path '%TEMP%\microsoft.ui.xaml.2.8.6.nupkg' -DestinationPath '%TEMP%\xaml'; Add-AppxPackage -Path '%TEMP%\xaml\tools\AppX\x64\Release\Microsoft.UI.Xaml.2.8.appx'" >nul 2>&1
    rmdir /s /q "%TEMP%\xaml" >nul 2>&1
    del "%TEMP%\microsoft.ui.xaml.2.8.6.nupkg" >nul 2>&1
)

REM Install WinGet
powershell -Command "if (!(Get-AppxPackage -Name 'Microsoft.DesktopAppInstaller')) { exit 1 }" >nul 2>&1
if %errorLevel% neq 0 (
    echo [INFO] Installing WinGet (Microsoft.DesktopAppInstaller)...
    curl -L -o "%TEMP%\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle" "https://aka.ms/getwinget"
    powershell -Command "Add-AppxPackage -Path '%TEMP%\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle'" >nul 2>&1
    del "%TEMP%\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle" >nul 2>&1
)

echo [INFO] WinGet installation completed
exit /b 0

:INSTALL_POWERSHELL7
echo [INFO] Installing PowerShell 7...
winget install --id Microsoft.PowerShell --silent --accept-package-agreements --accept-source-agreements >nul 2>&1
if %errorLevel% equ 0 (
    echo [INFO] PowerShell 7 installed successfully
    REM Refresh PATH to include PowerShell 7
    call refreshenv >nul 2>&1
    exit /b 0
) else (
    echo [WARNING] PowerShell 7 installation failed
    exit /b 1
)
