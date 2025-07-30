
@echo off
chcp 65001 >nul 2>&1 || chcp 850 >nul 2>&1
setlocal enabledelayedexpansion

echo ========================================
echo Setting up WinGet, PowerShell 7, and running maintenance script
echo ========================================

REM Check if running as administrator

net session >nul 2>&1
if %errorLevel% NEQ 0 (
    echo Requesting administrator privileges...
    powershell -Command "Start-Process -FilePath '%~f0' -ArgumentList '' -Verb RunAs"
    exit /b
)

echo [OK] Running with administrator privileges

REM Get the directory where this script is located
set SCRIPT_DIR=%~dp0
echo Script running from: %SCRIPT_DIR%

REM Create temp directory for downloads
set TEMP_DIR=%TEMP%\setup_maintenance
if not exist "%TEMP_DIR%" mkdir "%TEMP_DIR%"

echo.
echo Step 1: Checking and Installing WinGet Dependencies
echo ========================================

REM Initialize variables
set "VCLIBS_INSTALLED=false"
set "XAML_INSTALLED=false"
set "WINGET_INSTALLED=false"

REM Check VCLibs installation
echo Checking Microsoft.VCLibs installation...
cd /d "%TEMP_DIR%"
powershell -Command "try { $packages = Get-AppxPackage -Name 'Microsoft.VCLibs*'; if ($packages -and ($packages | Where-Object {[version]$_.Version -ge '14.0'})) { exit 0 } else { exit 1 } } catch { exit 1 }" >nul 2>&1
if %errorLevel% EQU 0 (
    echo [OK] Microsoft.VCLibs is already installed
    set "VCLIBS_INSTALLED=true"
) else (
    echo [FAIL] Microsoft.VCLibs not found or outdated
)

REM Check UI.Xaml installation
echo Checking Microsoft.UI.Xaml installation...
powershell -Command "try { $packages = Get-AppxPackage -Name 'Microsoft.UI.Xaml*'; if ($packages -and ($packages | Where-Object {[version]$_.Version -ge '2.7'})) { exit 0 } else { exit 1 } } catch { exit 1 }" >nul 2>&1
if %errorLevel% EQU 0 (
    echo [OK] Microsoft.UI.Xaml 2.7+ is already installed
    set "XAML_INSTALLED=true"
) else (
    echo [FAIL] Microsoft.UI.Xaml 2.7+ not found
)

REM Check WinGet installation
echo Checking WinGet installation...
where winget >nul 2>&1
if %errorLevel% EQU 0 (
    echo [OK] WinGet is already installed
    winget --version
    set "WINGET_INSTALLED=true"
    goto check_pwsh
) else (
    echo [FAIL] WinGet not found
)

REM Install VCLibs if not installed
if "%VCLIBS_INSTALLED%"=="false" (
    echo.
    echo Installing Microsoft.VCLibs...
    powershell -Command "try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; $ProgressPreference = 'SilentlyContinue'; Invoke-WebRequest -Uri 'https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx' -OutFile 'VCLibs.appx' -UseBasicParsing } catch { Write-Host 'Download failed'; exit 1 }"
    
    if exist "VCLibs.appx" (
        echo Installing VCLibs package...
        powershell -Command "try { Add-AppxPackage -Path 'VCLibs.appx' } catch { Write-Host 'Install failed'; exit 1 }"
        if %errorLevel% EQU 0 (
            echo [OK] VCLibs installed successfully
            set "VCLIBS_INSTALLED=true"
        ) else (
            echo [FAIL] VCLibs installation failed
        )
    ) else (
        echo [FAIL] Failed to download VCLibs
    )
)

REM Install UI.Xaml if not installed
if "%XAML_INSTALLED%"=="false" (
    echo.
    echo Installing Microsoft.UI.Xaml 2.8...
    powershell -Command "try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; $ProgressPreference = 'SilentlyContinue'; Invoke-WebRequest -Uri 'https://www.nuget.org/api/v2/package/Microsoft.UI.Xaml/2.8.6' -OutFile 'xaml.zip' -UseBasicParsing; Expand-Archive -Path 'xaml.zip' -DestinationPath 'xaml' -Force; Copy-Item 'xaml\tools\AppX\x64\Release\Microsoft.UI.Xaml.2.8.appx' -Destination 'Microsoft.UI.Xaml.2.8.appx' } catch { Write-Host 'Download/extract failed'; exit 1 }"
    
    if exist "Microsoft.UI.Xaml.2.8.appx" (
        echo Installing UI.Xaml package...
        powershell -Command "try { Add-AppxPackage -Path 'Microsoft.UI.Xaml.2.8.appx' } catch { Write-Host 'Install failed'; exit 1 }"
        if %errorLevel% EQU 0 (
            echo [OK] UI.Xaml installed successfully
            set "XAML_INSTALLED=true"
        ) else (
            echo [FAIL] UI.Xaml installation failed
        )
    ) else (
        echo [FAIL] Failed to download/extract UI.Xaml
    )
)

REM Install WinGet if not installed
if "%WINGET_INSTALLED%"=="false" (
    echo.
    echo Installing WinGet (App Installer)...
    powershell -Command "try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; $ProgressPreference = 'SilentlyContinue'; $response = Invoke-RestMethod -Uri 'https://api.github.com/repos/microsoft/winget-cli/releases/latest'; $downloadUrl = ($response.assets | Where-Object { $_.name -like '*msixbundle' }).browser_download_url; Invoke-WebRequest -Uri $downloadUrl -OutFile 'Microsoft.DesktopAppInstaller.msixbundle' -UseBasicParsing } catch { Write-Host 'Download failed'; exit 1 }"
    
    if exist "Microsoft.DesktopAppInstaller.msixbundle" (
        echo Installing WinGet package...
        powershell -Command "try { Add-AppxPackage -Path 'Microsoft.DesktopAppInstaller.msixbundle' } catch { Write-Host 'Install failed'; exit 1 }"
        
        if %errorLevel% EQU 0 (
            echo [OK] WinGet installed successfully
            set "WINGET_INSTALLED=true"
            echo Waiting for WinGet to be available...
            timeout /t 10 /nobreak >nul
            
            REM Add WindowsApps to PATH if not already there
            echo %PATH% | find /i "WindowsApps" >nul
            if %errorLevel% NEQ 0 (
                set "PATH=%PATH%;%LOCALAPPDATA%\Microsoft\WindowsApps"
            )
        ) else (
            echo [FAIL] WinGet installation failed
        )
    ) else (
        echo ✗ Failed to download WinGet
    )
)

:check_pwsh
echo.
echo Step 2: Checking and Installing PowerShell 7
echo ========================================

REM Check if PowerShell 7 is already installed
echo Checking PowerShell 7 installation...
where pwsh >nul 2>&1
if %errorLevel% EQU 0 (
    echo [OK] PowerShell 7 is already installed
    pwsh --version
    set "PWSH_CMD=pwsh"
    goto check_repo
)

REM Check common installation paths
set "PS7_FOUND=false"
if exist "%ProgramFiles%\PowerShell\7\pwsh.exe" (
    echo [OK] PowerShell 7 found at: %ProgramFiles%\PowerShell\7\pwsh.exe
    set "PWSH_CMD=%ProgramFiles%\PowerShell\7\pwsh.exe"
    set "PS7_FOUND=true"
    goto check_repo
)

if exist "%ProgramFiles(x86)%\PowerShell\7\pwsh.exe" (
    echo [OK] PowerShell 7 found at: %ProgramFiles(x86)%\PowerShell\7\pwsh.exe
    set "PWSH_CMD=%ProgramFiles(x86)%\PowerShell\7\pwsh.exe"
    set "PS7_FOUND=true"
    goto check_repo
)

if "%PS7_FOUND%"=="false" (
    echo [FAIL] PowerShell 7 not found, installing...
    
    REM Try WinGet first if available
    where winget >nul 2>&1
    if %errorLevel% EQU 0 (
        echo Installing PowerShell 7 via WinGet...
        winget install --id Microsoft.PowerShell --source winget --accept-package-agreements --accept-source-agreements --silent
        timeout /t 15 /nobreak >nul
        
        REM Check if installation succeeded
        where pwsh >nul 2>&1
        if %errorLevel% EQU 0 (
            echo [OK] PowerShell 7 installed successfully via WinGet
            set "PWSH_CMD=pwsh"
            goto check_repo
        )
    )
    
    REM Manual installation if WinGet failed
    echo Downloading PowerShell 7 manually...
    set "ARCH=x64"
    if "%PROCESSOR_ARCHITECTURE%"=="x86" set "ARCH=x86"
    
    powershell -Command "try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; $ProgressPreference = 'SilentlyContinue'; Invoke-WebRequest -Uri 'https://github.com/PowerShell/PowerShell/releases/download/v7.4.6/PowerShell-7.4.6-win-%ARCH%.msi' -OutFile 'PowerShell-7-win-%ARCH%.msi' -UseBasicParsing } catch { Write-Host 'Download failed'; exit 1 }"
    
    if exist "PowerShell-7-win-%ARCH%.msi" (
        echo Installing PowerShell 7...
        msiexec /i "PowerShell-7-win-%ARCH%.msi" /quiet /norestart
        timeout /t 20 /nobreak >nul
        
        REM Check installation
        where pwsh >nul 2>&1
        if %errorLevel% EQU 0 (
        echo [OK] PowerShell 7 installed successfully
            set "PWSH_CMD=pwsh"
        ) else if exist "%ProgramFiles%\PowerShell\7\pwsh.exe" (
        echo [OK] PowerShell 7 installed at: %ProgramFiles%\PowerShell\7\pwsh.exe
            set "PWSH_CMD=%ProgramFiles%\PowerShell\7\pwsh.exe"
        ) else (
        echo [FAIL] PowerShell 7 installation verification failed
        echo [INFO] Using Windows PowerShell instead...
            set "PWSH_CMD=powershell"
        )
    ) else (
    echo [FAIL] Failed to download PowerShell 7
    echo [INFO] Using Windows PowerShell instead...
        set "PWSH_CMD=powershell"
    )
)

:check_repo
echo.
echo Step 3: Downloading maintenance script repository
echo ========================================

cd /d "%SCRIPT_DIR%"

REM Remove existing repository if it exists
if exist "script_mentenanta" (
    echo Removing existing repository...
    rmdir /s /q "script_mentenanta" >nul 2>&1
)

echo Downloading repository...
cd /d "%TEMP_DIR%"

powershell -Command "try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; $ProgressPreference = 'SilentlyContinue'; Invoke-WebRequest -Uri 'https://github.com/ichimbogdancristian/script_mentenanta/archive/refs/heads/main.zip' -OutFile 'script_mentenanta.zip' -UseBasicParsing } catch { Write-Host 'Download failed'; exit 1 }"

if exist "script_mentenanta.zip" (
    echo ✓ Repository downloaded successfully
    echo Extracting...
    
    powershell -Command "Expand-Archive -Path 'script_mentenanta.zip' -DestinationPath '.' -Force"
    
    if exist "script_mentenanta-main" (
        echo Moving to script directory...
        move "script_mentenanta-main" "%SCRIPT_DIR%\script_mentenanta" >nul
        if %errorLevel% EQU 0 (
            echo ✓ Repository extracted successfully
        ) else (
            echo ✗ Failed to move repository
            exit /b 1
        )
    ) else (
        echo ✗ Extraction failed
        exit /b 1
    )
) else (
    echo ✗ Failed to download repository
    exit /b 1
)

:run_script
echo.
echo Step 4: Running maintenance script
echo ========================================

cd /d "%SCRIPT_DIR%\script_mentenanta"

if not exist "script.ps1" (
    echo [FAIL] script.ps1 not found
    exit /b 1
)

echo [OK] Found script.ps1
echo Running with: %PWSH_CMD%

if "%PWSH_CMD%"=="pwsh" (
    pwsh -ExecutionPolicy Bypass -File "script.ps1"
) else if "%PWSH_CMD%"=="powershell" (
    powershell -ExecutionPolicy Bypass -File "script.ps1"
) else (
    "%PWSH_CMD%" -ExecutionPolicy Bypass -File "script.ps1"
)

set SCRIPT_EXIT_CODE=%errorLevel%

echo.
echo ========================================
echo Setup completed!
echo ========================================

if %SCRIPT_EXIT_CODE% EQU 0 (
    echo [OK] All operations completed successfully
) else (
    echo [WARN] Script completed with exit code: %SCRIPT_EXIT_CODE%
)

REM Cleanup
echo Cleaning up temporary files...
cd /d "%TEMP%.."
rmdir /s /q "%TEMP_DIR%" >nul 2>&1

echo.
echo Press any key to exit...
pause >nul

exit /b %SCRIPT_EXIT_CODE%