@echo off
chcp 65001 >nul 2>&1 || chcp 850 >nul 2>&1
setlocal enabledelayedexpansion

echo ========================================
echo Windows Fresh Install Setup Script
echo Setting up WinGet, PowerShell 7, and maintenance tools
echo ========================================

REM Check if running as administrator
net session >nul 2>&1
if !errorLevel! neq 0 (
    echo [ADMIN] Requesting administrator privileges...
    powershell -Command "Start-Process -FilePath '!~f0!' -ArgumentList '' -Verb RunAs"
    exit /b 1
)

echo [OK] Running with administrator privileges

REM Initialize variables
set "SCRIPT_DIR=%~dp0"
set "TEMP_DIR=%TEMP%\windows_setup_%RANDOM%"
set "VCLIBS_INSTALLED=false"
set "XAML_INSTALLED=false"
set "WINGET_INSTALLED=false"
set "PS7_INSTALLED=false"
set "ERROR_COUNT=0"

echo [INFO] Script directory: !SCRIPT_DIR!
echo [INFO] Temp directory: !TEMP_DIR!

REM Create temp directory
if not exist "!TEMP_DIR!" (
    mkdir "!TEMP_DIR!" || (
        echo [ERROR] Failed to create temp directory
        exit /b 1
    )
)

echo.
echo ========================================
echo Step 1: System Requirements Check
echo ========================================

REM Check Windows version
for /f "tokens=4-5 delims=. " %%i in ('ver') do set VERSION=%%i.%%j
echo [INFO] Windows version: !VERSION!

REM Verify PowerShell availability
powershell -Command "exit 0" >nul 2>&1
if !errorLevel! neq 0 (
    echo [ERROR] PowerShell is not available
    set /a ERROR_COUNT+=1
    goto cleanup
)

echo [OK] System requirements check passed

echo.
echo ========================================
echo Step 2: WinGet Dependencies Installation
echo ========================================

cd /d "!TEMP_DIR!"

REM Function: Check VCLibs
echo [CHECK] Microsoft.VCLibs installation...
powershell -Command "try { $packages = Get-AppxPackage -Name 'Microsoft.VCLibs*'; if ($packages -and ($packages | Where-Object {[version]$_.Version -ge '14.0'})) { exit 0 } else { exit 1 } } catch { exit 1 }" >nul 2>&1
if !errorLevel! equ 0 (
    echo [OK] Microsoft.VCLibs 14.0+ is installed
    set "VCLIBS_INSTALLED=true"
) else (
    echo [INSTALL] Installing Microsoft.VCLibs...
    call :install_vclibs
)

REM Function: Check UI.Xaml
echo [CHECK] Microsoft.UI.Xaml installation...
powershell -Command "try { $packages = Get-AppxPackage -Name 'Microsoft.UI.Xaml*'; if ($packages -and ($packages | Where-Object {[version]$_.Version -ge '2.7'})) { exit 0 } else { exit 1 } } catch { exit 1 }" >nul 2>&1
if !errorLevel! equ 0 (
    echo [OK] Microsoft.UI.Xaml 2.7+ is installed
    set "XAML_INSTALLED=true"
) else (
    echo [INSTALL] Installing Microsoft.UI.Xaml...
    call :install_xaml
)

REM Function: Check WinGet
echo [CHECK] WinGet installation...
where winget >nul 2>&1
if !errorLevel! equ 0 (
    echo [OK] WinGet is installed
    for /f "tokens=*" %%a in ('winget --version 2^>nul') do echo [INFO] Version: %%a
    set "WINGET_INSTALLED=true"
) else (
    echo [INSTALL] Installing WinGet...
    call :install_winget
)

echo.
echo ========================================
echo Step 3: PowerShell 7 Installation
echo ========================================

REM Check PowerShell 7
echo [CHECK] PowerShell 7 installation...
where pwsh >nul 2>&1
if !errorLevel! equ 0 (
    echo [OK] PowerShell 7 is installed
    for /f "tokens=*" %%a in ('pwsh --version 2^>nul') do echo [INFO] Version: %%a
    set "PWSH_CMD=pwsh"
    set "PS7_INSTALLED=true"
) else (
    call :check_ps7_paths
    if "!PS7_INSTALLED!"=="false" (
        echo [INSTALL] Installing PowerShell 7...
        call :install_powershell7
    )
)

echo.
echo ========================================
echo Step 4: Maintenance Script Setup
echo ========================================

call :download_maintenance_script

echo.
echo ========================================
echo Step 5: Running Maintenance Script
echo ========================================

call :run_maintenance_script

goto cleanup

REM ========================================
REM FUNCTION DEFINITIONS
REM ========================================

:install_vclibs
echo [DOWNLOAD] Microsoft.VCLibs.x64.14.00.Desktop.appx...
powershell -NoProfile -Command "try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; $ProgressPreference = 'SilentlyContinue'; Invoke-WebRequest -Uri 'https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx' -OutFile 'VCLibs.appx' -UseBasicParsing; exit 0 } catch { Write-Host '[ERROR] Download failed:' $_.Exception.Message; exit 1 }"

if exist "VCLibs.appx" (
    echo [INSTALL] Installing VCLibs package...
    powershell -NoProfile -Command "try { Add-AppxPackage -Path 'VCLibs.appx'; exit 0 } catch { Write-Host '[ERROR] Installation failed:' $_.Exception.Message; exit 1 }"
    if !errorLevel! equ 0 (
        echo [OK] VCLibs installed successfully
        set "VCLIBS_INSTALLED=true"
    ) else (
        echo [ERROR] VCLibs installation failed
        set /a ERROR_COUNT+=1
    )
    del "VCLibs.appx" >nul 2>&1
) else (
    echo [ERROR] Failed to download VCLibs
    set /a ERROR_COUNT+=1
)
goto :eof

:install_xaml
echo [DOWNLOAD] Microsoft.UI.Xaml 2.8...
powershell -NoProfile -Command "try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; $ProgressPreference = 'SilentlyContinue'; Invoke-WebRequest -Uri 'https://www.nuget.org/api/v2/package/Microsoft.UI.Xaml/2.8.6' -OutFile 'xaml.zip' -UseBasicParsing; Expand-Archive -Path 'xaml.zip' -DestinationPath 'xaml' -Force; Copy-Item 'xaml\tools\AppX\x64\Release\Microsoft.UI.Xaml.2.8.appx' -Destination 'Microsoft.UI.Xaml.2.8.appx'; exit 0 } catch { Write-Host '[ERROR] Download/extract failed:' $_.Exception.Message; exit 1 }"

if exist "Microsoft.UI.Xaml.2.8.appx" (
    echo [INSTALL] Installing UI.Xaml package...
    powershell -NoProfile -Command "try { Add-AppxPackage -Path 'Microsoft.UI.Xaml.2.8.appx'; exit 0 } catch { Write-Host '[ERROR] Installation failed:' $_.Exception.Message; exit 1 }"
    if !errorLevel! equ 0 (
        echo [OK] UI.Xaml installed successfully
        set "XAML_INSTALLED=true"
    ) else (
        echo [ERROR] UI.Xaml installation failed
        set /a ERROR_COUNT+=1
    )
    del "Microsoft.UI.Xaml.2.8.appx" >nul 2>&1
    rmdir /s /q "xaml" >nul 2>&1
    del "xaml.zip" >nul 2>&1
) else (
    echo [ERROR] Failed to download/extract UI.Xaml
    set /a ERROR_COUNT+=1
)
goto :eof

:install_winget
if "!VCLIBS_INSTALLED!"=="false" (
    echo [ERROR] VCLibs must be installed before WinGet
    set /a ERROR_COUNT+=1
    goto :eof
)

if "!XAML_INSTALLED!"=="false" (
    echo [ERROR] UI.Xaml must be installed before WinGet
    set /a ERROR_COUNT+=1
    goto :eof
)

echo [DOWNLOAD] WinGet (App Installer)...
powershell -NoProfile -Command "try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; $ProgressPreference = 'SilentlyContinue'; $response = Invoke-RestMethod -Uri 'https://api.github.com/repos/microsoft/winget-cli/releases/latest'; $downloadUrl = ($response.assets | Where-Object { $_.name -like '*msixbundle' }).browser_download_url; Invoke-WebRequest -Uri $downloadUrl -OutFile 'Microsoft.DesktopAppInstaller.msixbundle' -UseBasicParsing; exit 0 } catch { Write-Host '[ERROR] Download failed:' $_.Exception.Message; exit 1 }"

if exist "Microsoft.DesktopAppInstaller.msixbundle" (
    echo [INSTALL] Installing WinGet package...
    powershell -NoProfile -Command "try { Add-AppxPackage -Path 'Microsoft.DesktopAppInstaller.msixbundle'; exit 0 } catch { Write-Host '[ERROR] Installation failed:' $_.Exception.Message; exit 1 }"
    
    if !errorLevel! equ 0 (
        echo [OK] WinGet installed successfully
        echo [WAIT] Waiting for WinGet to be available...
        timeout /t 15 /nobreak >nul
        
        REM Add WindowsApps to PATH if not already there
        echo !PATH! | findstr /i "WindowsApps" >nul
        if !errorLevel! neq 0 (
            set "PATH=!PATH!;%LOCALAPPDATA%\Microsoft\WindowsApps"
        )
        
        REM Verify installation
        where winget >nul 2>&1
        if !errorLevel! equ 0 (
            set "WINGET_INSTALLED=true"
            echo [OK] WinGet is now available
        ) else (
            echo [WARN] WinGet installed but not immediately available
            set "WINGET_INSTALLED=false"
        )
    ) else (
        echo [ERROR] WinGet installation failed
        set /a ERROR_COUNT+=1
    )
    del "Microsoft.DesktopAppInstaller.msixbundle" >nul 2>&1
) else (
    echo [ERROR] Failed to download WinGet
    set /a ERROR_COUNT+=1
)
goto :eof

:check_ps7_paths
set "PS7_PATHS[0]=%ProgramFiles%\PowerShell\7\pwsh.exe"
set "PS7_PATHS[1]=%ProgramFiles(x86)%\PowerShell\7\pwsh.exe"
set "PS7_PATHS[2]=%LOCALAPPDATA%\Microsoft\powershell\pwsh.exe"

for /l %%i in (0,1,2) do (
    if exist "!PS7_PATHS[%%i]!" (
        echo [OK] PowerShell 7 found at: !PS7_PATHS[%%i]!
        set "PWSH_CMD=!PS7_PATHS[%%i]!"
        set "PS7_INSTALLED=true"
        goto :eof
    )
)
goto :eof

:install_powershell7
REM Try WinGet first if available
if "!WINGET_INSTALLED!"=="true" (
    echo [WINGET] Installing PowerShell 7 via WinGet...
    winget install --id Microsoft.PowerShell --source winget --accept-package-agreements --accept-source-agreements --silent --force
    timeout /t 20 /nobreak >nul
    
    REM Check if installation succeeded
    where pwsh >nul 2>&1
    if !errorLevel! equ 0 (
        echo [OK] PowerShell 7 installed successfully via WinGet
        set "PWSH_CMD=pwsh"
        set "PS7_INSTALLED=true"
        goto :eof
    ) else (
        call :check_ps7_paths
        if "!PS7_INSTALLED!"=="true" goto :eof
    )
)

REM Manual installation
echo [DOWNLOAD] PowerShell 7 manually...
set "ARCH=x64"
if "%PROCESSOR_ARCHITECTURE%"=="x86" set "ARCH=x86"
if "%PROCESSOR_ARCHITECTURE%"=="ARM64" set "ARCH=arm64"

powershell -NoProfile -Command "try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; $ProgressPreference = 'SilentlyContinue'; $arch = '%ARCH%'; $version = '7.4.6'; $url = \"https://github.com/PowerShell/PowerShell/releases/download/v$version/PowerShell-$version-win-$arch.msi\"; Invoke-WebRequest -Uri $url -OutFile \"PowerShell-7-win-$arch.msi\" -UseBasicParsing; exit 0 } catch { Write-Host '[ERROR] Download failed:' $_.Exception.Message; exit 1 }"

if exist "PowerShell-7-win-!ARCH!.msi" (
    echo [INSTALL] Installing PowerShell 7...
    msiexec /i "PowerShell-7-win-!ARCH!.msi" /quiet /norestart ADD_EXPLORER_CONTEXT_MENU_OPENPOWERSHELL=1 ADD_FILE_CONTEXT_MENU_RUNPOWERSHELL=1 ENABLE_PSREMOTING=1 REGISTER_MANIFEST=1
    timeout /t 30 /nobreak >nul
    
    REM Check installation
    where pwsh >nul 2>&1
    if !errorLevel! equ 0 (
        echo [OK] PowerShell 7 installed successfully
        set "PWSH_CMD=pwsh"
        set "PS7_INSTALLED=true"
    ) else (
        call :check_ps7_paths
        if "!PS7_INSTALLED!"=="false" (
            echo [ERROR] PowerShell 7 installation verification failed
            echo [FALLBACK] Using Windows PowerShell instead...
            set "PWSH_CMD=powershell"
            set /a ERROR_COUNT+=1
        )
    )
    del "PowerShell-7-win-!ARCH!.msi" >nul 2>&1
) else (
    echo [ERROR] Failed to download PowerShell 7
    echo [FALLBACK] Using Windows PowerShell instead...
    set "PWSH_CMD=powershell"
    set /a ERROR_COUNT+=1
)
goto :eof

:download_maintenance_script
echo [DOWNLOAD] Maintenance script repository...

cd /d "!SCRIPT_DIR!"

REM Remove existing repository if it exists
if exist "script_mentenanta" (
    echo [CLEANUP] Removing existing repository...
    rmdir /s /q "script_mentenanta" >nul 2>&1
)

cd /d "!TEMP_DIR!"

powershell -NoProfile -Command "try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; $ProgressPreference = 'SilentlyContinue'; Invoke-WebRequest -Uri 'https://github.com/ichimbogdancristian/script_mentenanta/archive/refs/heads/main.zip' -OutFile 'script_mentenanta.zip' -UseBasicParsing; exit 0 } catch { Write-Host '[ERROR] Download failed:' $_.Exception.Message; exit 1 }"

if exist "script_mentenanta.zip" (
    echo [OK] Repository downloaded successfully
    echo [EXTRACT] Extracting repository...
    
    powershell -NoProfile -Command "try { Expand-Archive -Path 'script_mentenanta.zip' -DestinationPath '.' -Force; exit 0 } catch { Write-Host '[ERROR] Extraction failed:' $_.Exception.Message; exit 1 }"
    
    if exist "script_mentenanta-main" (
        echo [MOVE] Moving repository to script directory...
        move "script_mentenanta-main" "!SCRIPT_DIR!\script_mentenanta" >nul 2>&1
        if !errorLevel! equ 0 (
            echo [OK] Repository extracted successfully
        ) else (
            echo [ERROR] Failed to move repository
            set /a ERROR_COUNT+=1
        )
    ) else (
        echo [ERROR] Extraction failed - directory not found
        set /a ERROR_COUNT+=1
    )
    del "script_mentenanta.zip" >nul 2>&1
) else (
    echo [ERROR] Failed to download repository
    set /a ERROR_COUNT+=1
)
goto :eof

:run_maintenance_script
cd /d "!SCRIPT_DIR!\script_mentenanta"

if not exist "script.ps1" (
    echo [ERROR] script.ps1 not found in repository
    set /a ERROR_COUNT+=1
    goto :eof
)

echo [OK] Found maintenance script: script.ps1
echo [RUN] Executing with: !PWSH_CMD!

if "!PWSH_CMD!"=="pwsh" (
    pwsh -NoProfile -ExecutionPolicy Bypass -File "script.ps1"
) else if "!PWSH_CMD!"=="powershell" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "script.ps1"
) else (
    "!PWSH_CMD!" -NoProfile -ExecutionPolicy Bypass -File "script.ps1"
)

set "SCRIPT_EXIT_CODE=!errorLevel!"

if !SCRIPT_EXIT_CODE! equ 0 (
    echo [OK] Maintenance script completed successfully
) else (
    echo [WARN] Maintenance script exited with code: !SCRIPT_EXIT_CODE!
    set /a ERROR_COUNT+=1
)
goto :eof

:cleanup
echo.
echo ========================================
echo Cleanup and Summary
echo ========================================

echo [CLEANUP] Removing temporary files...
cd /d "%TEMP%"
if exist "!TEMP_DIR!" rmdir /s /q "!TEMP_DIR!" >nul 2>&1

echo.
echo ========================================
echo Installation Summary
echo ========================================
echo VCLibs 14.0+:        !VCLIBS_INSTALLED!
echo UI.Xaml 2.7+:        !XAML_INSTALLED!
echo WinGet:               !WINGET_INSTALLED!
echo PowerShell 7:         !PS7_INSTALLED!
echo Errors encountered:   !ERROR_COUNT!
echo ========================================

if !ERROR_COUNT! equ 0 (
    echo [SUCCESS] Setup completed successfully!
    echo [INFO] Your system is now ready for use.
) else (
    echo [WARNING] Setup completed with !ERROR_COUNT! error(s).
    echo [INFO] Some components may not be fully functional.
)

echo.
echo Press any key to exit...
pause >nul

if defined SCRIPT_EXIT_CODE (
    exit /b !SCRIPT_EXIT_CODE!
) else (
    exit /b !ERROR_COUNT!
)