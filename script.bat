@echo off
setlocal enabledelayedexpansion

echo ========================================
echo Complete WinGet and PowerShell 7 Setup
echo Including ALL required dependencies for fresh Windows installs
echo ========================================

REM Check if running as administrator and relaunch if not
echo Checking administrator privileges...
net session >nul 2>&1
if %errorLevel% NEQ 0 (
    echo This script requires administrator privileges.
    echo Attempting to relaunch with administrator privileges...
    
    REM Get the full path of the current script
    set "SCRIPT_PATH=%~f0"
    echo Script path: !SCRIPT_PATH!
    
    REM Create a VBS script for elevation (more reliable than PowerShell)
    echo Set UAC = CreateObject^("Shell.Application"^) > "%TEMP%\elevate.vbs"
    echo UAC.ShellExecute "cmd.exe", "/c ""!SCRIPT_PATH!""", "", "runas", 1 >> "%TEMP%\elevate.vbs"
    
    REM Try VBS elevation first
    cscript //NoLogo "%TEMP%\elevate.vbs" >nul 2>&1
    if %errorLevel% EQU 0 (
        echo Elevation request sent via VBS
        del "%TEMP%\elevate.vbs" >nul 2>&1
        exit /b 0
    )
    
    REM Fallback to PowerShell elevation
    echo VBS method failed, trying PowerShell elevation...
    powershell -Command "try { Start-Process -FilePath 'cmd.exe' -ArgumentList '/c', '\"!SCRIPT_PATH!\"' -Verb RunAs -WindowStyle Normal } catch { Write-Host 'PowerShell elevation failed'; exit 1 }"
    
    if %errorLevel% NEQ 0 (
        echo Both elevation methods failed.
        echo Please manually right-click this script and select "Run as administrator"
        pause
        exit /b 1
    )
    
    echo Script elevation request sent.
    exit /b 0
)

echo ✓ Running with administrator privileges
timeout /t 2 /nobreak >nul

echo ✓ Running with administrator privileges

REM Get the directory where this script is located
set SCRIPT_DIR=%~dp0
echo Script running from: %SCRIPT_DIR%

REM Add some debug information
echo Current user: %USERNAME%
echo Current directory: %CD%
echo Script directory: %SCRIPT_DIR%
echo System: %OS% %PROCESSOR_ARCHITECTURE%
echo.

REM Verify we actually have admin rights
echo Verifying administrator privileges...
reg query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion" >nul 2>&1
if %errorLevel% NEQ 0 (
    echo ✗ Administrator verification failed
    echo Please ensure you're running as administrator
    pause
    exit /b 1
) else (
    echo ✓ Administrator privileges confirmed
)

REM Create temp directory for downloads
set TEMP_DIR=%TEMP%\winget_complete_setup_%RANDOM%
echo Creating temp directory: %TEMP_DIR%
if not exist "%TEMP_DIR%" (
    mkdir "%TEMP_DIR%"
    if %errorLevel% NEQ 0 (
        echo ✗ Failed to create temp directory
        echo Trying alternative temp location...
        set TEMP_DIR=%USERPROFILE%\Desktop\temp_winget_setup
        mkdir "%TEMP_DIR%" 2>nul
        if not exist "%TEMP_DIR%" (
            echo ✗ Failed to create any temp directory
            pause
            exit /b 1
        )
    )
)
echo ✓ Using temp directory: %TEMP_DIR%

REM Test temp directory access
echo test > "%TEMP_DIR%\test.txt" 2>nul
if exist "%TEMP_DIR%\test.txt" (
    del "%TEMP_DIR%\test.txt"
    echo ✓ Temp directory access confirmed
) else (
    echo ✗ Cannot write to temp directory
    pause
    exit /b 1
)

REM Initialize status variables
set "VCREDIST_INSTALLED=false"
set "VCLIBS_INSTALLED=false"
set "XAML_INSTALLED=false"
set "DESKTOPBRIDGE_INSTALLED=false"
set "STORE_INSTALLED=false"
set "WINGET_INSTALLED=false"
set "PWSH_INSTALLED=false"

echo.
echo Step 1: Installing Visual C++ Redistributable (Required for all dependencies)
echo ========================================

REM Test internet connectivity first
echo Testing internet connectivity...
ping -n 1 google.com >nul 2>&1
if %errorLevel% NEQ 0 (
    echo ✗ No internet connection detected
    echo Please check your internet connection and try again
    pause
    exit /b 1
) else (
    echo ✓ Internet connection confirmed
)

REM Check if Visual C++ Redistributable is installed
echo Checking Visual C++ Redistributable 2015-2022...
reg query "HKLM\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\X64" /v "Version" >nul 2>&1
if %errorLevel% EQU 0 (
    echo ✓ Visual C++ Redistributable already installed
    set "VCREDIST_INSTALLED=true"
) else (
    reg query "HKLM\SOFTWARE\WOW6432Node\Microsoft\VisualStudio\14.0\VC\Runtimes\X64" /v "Version" >nul 2>&1
    if %errorLevel% EQU 0 (
        echo ✓ Visual C++ Redistributable already installed (WOW64)
        set "VCREDIST_INSTALLED=true"
    ) else (
        echo ✗ Visual C++ Redistributable not found
    )
)

if "%VCREDIST_INSTALLED%"=="false" (
    echo Installing Visual C++ Redistributable 2015-2022 x64...
    cd /d "%TEMP_DIR%"
    
    REM Method 1: Microsoft download
    echo Downloading VC++ Redistributable (Method 1)...
    powershell -Command "try { Write-Host 'Starting download...'; [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; $ProgressPreference = 'SilentlyContinue'; Invoke-WebRequest -Uri 'https://aka.ms/vs/17/release/vc_redist.x64.exe' -OutFile 'vc_redist.x64.exe' -UseBasicParsing -TimeoutSec 60; Write-Host 'Download completed successfully'; exit 0 } catch { Write-Host ('Download failed: ' + $_.Exception.Message); exit 1 }"
    
    if exist "vc_redist.x64.exe" (
        echo ✓ VC++ Redistributable downloaded successfully
    ) else (
        echo Method 1 failed, trying direct link (Method 2)...
        powershell -Command "try { Write-Host 'Trying alternative download...'; $client = New-Object System.Net.WebClient; $client.DownloadTimeout = 60000; $client.DownloadFile('https://download.microsoft.com/download/9/3/F/93FCF1E7-E6A4-478B-96E7-D4B285925B00/vc_redist.x64.exe', 'vc_redist.x64.exe'); Write-Host 'Alternative download completed' } catch { Write-Host ('WebClient failed: ' + $_.Exception.Message) }"
    )
    
    if not exist "vc_redist.x64.exe" (
        echo Method 2 failed, trying alternative source (Method 3)...
        powershell -Command "try { Invoke-WebRequest -Uri 'https://github.com/abbodi1406/vcredist/releases/latest/download/VisualCppRedist_AIO_x86_x64.exe' -OutFile 'vc_redist_aio.exe' -UseBasicParsing -TimeoutSec 60; Write-Host 'Third method completed' } catch { Write-Host 'Third method failed' }"
        if exist "vc_redist_aio.exe" ren "vc_redist_aio.exe" "vc_redist.x64.exe"
    )
    
    if exist "vc_redist.x64.exe" (
        echo Installing VC++ Redistributable...
        echo This may take a few minutes, please wait...
        start /wait "" "vc_redist.x64.exe" /quiet /norestart
        echo Installation command completed with exit code: %errorLevel%
        
        REM Give more time for installation
        echo Waiting for installation to complete...
        timeout /t 45 /nobreak >nul
        
        REM Verify installation with multiple methods
        echo Verifying installation...
        reg query "HKLM\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\X64" /v "Version" >nul 2>&1
        if %errorLevel% EQU 0 (
            echo ✓ Visual C++ Redistributable installed successfully (x64)
            set "VCREDIST_INSTALLED=true"
        ) else (
            reg query "HKLM\SOFTWARE\WOW6432Node\Microsoft\VisualStudio\14.0\VC\Runtimes\X64" /v "Version" >nul 2>&1
            if %errorLevel% EQU 0 (
                echo ✓ Visual C++ Redistributable installed successfully (WOW64)
                set "VCREDIST_INSTALLED=true"
            ) else (
                echo Warning: VC++ Redistributable installation verification failed
                echo Continuing anyway - some components may not work properly
            )
        )
    ) else (
        echo ✗ All download methods failed for VC++ Redistributable
        echo This may cause issues with other components
        echo Continuing anyway...
        pause
    )
)

echo.
echo Step 2: Installing Desktop Bridge Framework Dependencies
echo ========================================

REM Install VCLibs Desktop (Desktop Bridge C++ Runtime)
echo Checking Microsoft.VCLibs.Desktop.14...
powershell -Command "try { $packages = Get-AppxPackage -Name 'Microsoft.VCLibs.Desktop.14' -ErrorAction SilentlyContinue; if ($packages) { exit 0 } else { exit 1 } } catch { exit 1 }" >nul 2>&1
if %errorLevel% EQU 0 (
    echo ✓ Microsoft.VCLibs.Desktop.14 already installed
    set "DESKTOPBRIDGE_INSTALLED=true"
) else (
    echo ✗ Microsoft.VCLibs.Desktop.14 not found, installing...
    
    REM Method 1: Direct Microsoft link for Desktop Bridge
    echo Downloading VCLibs Desktop Bridge (Method 1)...
    powershell -Command "try { Invoke-WebRequest -Uri 'https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx' -OutFile 'VCLibs.Desktop.appx' -UseBasicParsing -TimeoutSec 30 } catch { exit 1 }"
    
    if not exist "VCLibs.Desktop.appx" (
        echo Method 1 failed, trying store API (Method 2)...
        powershell -Command "try { $response = Invoke-RestMethod -Uri 'https://store.rg-adguard.net/api/GetFiles' -Method Post -Body 'type=ProductId&url=9PMMSR1CGPWG&ring=Retail&lang=en-US' -ContentType 'application/x-www-form-urlencoded'; $downloadUrl = ($response | Select-String -Pattern 'https://[^\"]*Microsoft\.VCLibs[^\"]*\.appx').Matches[0].Value; Invoke-WebRequest -Uri $downloadUrl -OutFile 'VCLibs.Desktop.appx' -UseBasicParsing } catch { }"
    )
    
    if not exist "VCLibs.Desktop.appx" (
        echo Method 2 failed, trying GitHub mirror (Method 3)...
        powershell -Command "try { Invoke-WebRequest -Uri 'https://github.com/gabriel-vanca/VCLibs/releases/latest/download/Microsoft.VCLibs.x64.14.00.Desktop.appx' -OutFile 'VCLibs.Desktop.appx' -UseBasicParsing } catch { }"
    )
    
    if exist "VCLibs.Desktop.appx" (
        echo Installing VCLibs Desktop Bridge...
        powershell -Command "try { Add-AppxPackage -Path 'VCLibs.Desktop.appx' -ErrorAction Stop; Write-Host '✓ VCLibs Desktop installed' } catch { Write-Host 'Installation failed, trying alternative'; Add-AppxPackage -Path 'VCLibs.Desktop.appx' -ForceApplicationShutdown }"
        set "DESKTOPBRIDGE_INSTALLED=true"
    )
)

REM Install regular VCLibs (UWP Runtime)
echo Checking Microsoft.VCLibs.140.00...
powershell -Command "try { $packages = Get-AppxPackage -Name 'Microsoft.VCLibs.140.00*' -ErrorAction SilentlyContinue; if ($packages) { exit 0 } else { exit 1 } } catch { exit 1 }" >nul 2>&1
if %errorLevel% EQU 0 (
    echo ✓ Microsoft.VCLibs.140.00 already installed
    set "VCLIBS_INSTALLED=true"
) else (
    echo ✗ Microsoft.VCLibs.140.00 not found, installing...
    
    REM Multiple methods for VCLibs
    echo Downloading VCLibs UWP Runtime (Method 1)...
    powershell -Command "try { Invoke-WebRequest -Uri 'https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx' -OutFile 'VCLibs.UWP.appx' -UseBasicParsing } catch { exit 1 }"
    
    if not exist "VCLibs.UWP.appx" (
        echo Method 1 failed, trying NuGet source (Method 2)...
        powershell -Command "try { Invoke-WebRequest -Uri 'https://www.nuget.org/api/v2/package/Microsoft.VCLibs.x64.14.00.Desktop/14.0.33519' -OutFile 'vclibs.zip'; Expand-Archive -Path 'vclibs.zip' -DestinationPath 'vclibs'; Copy-Item 'vclibs\runtimes\win10-x64\native\Microsoft.VCLibs.x64.14.00.Desktop.appx' -Destination 'VCLibs.UWP.appx' -ErrorAction SilentlyContinue } catch { }"
    )
    
    if not exist "VCLibs.UWP.appx" (
        echo Method 2 failed, using DISM capability (Method 3)...
        dism /online /add-capability /capabilityname:Microsoft.VCLibs.140.00.UWPDesktop~~~~0.0.1.0 /quiet
        if %errorLevel% EQU 0 (
            echo ✓ VCLibs installed via DISM
            set "VCLIBS_INSTALLED=true"
        )
    )
    
    if exist "VCLibs.UWP.appx" (
        if "%VCLIBS_INSTALLED%"=="false" (
            echo Installing VCLibs UWP Runtime...
            powershell -Command "try { Add-AppxPackage -Path 'VCLibs.UWP.appx' -ErrorAction Stop; Write-Host '✓ VCLibs UWP installed' } catch { Add-AppxPackage -Path 'VCLibs.UWP.appx' -ForceApplicationShutdown }"
            set "VCLIBS_INSTALLED=true"
        )
    )
)

echo.
echo Step 3: Installing Microsoft.UI.Xaml Framework
echo ========================================

echo Checking Microsoft.UI.Xaml installation...
powershell -Command "try { $packages = Get-AppxPackage -Name 'Microsoft.UI.Xaml*' -ErrorAction SilentlyContinue; if ($packages -and ($packages | Where-Object {[version]$_.Version -ge '2.7'})) { exit 0 } else { exit 1 } } catch { exit 1 }" >nul 2>&1
if %errorLevel% EQU 0 (
    echo ✓ Microsoft.UI.Xaml 2.7+ already installed
    set "XAML_INSTALLED=true"
) else (
    echo ✗ Microsoft.UI.Xaml 2.7+ not found, installing...
    
    REM Method 1: NuGet package
    echo Downloading UI.Xaml from NuGet (Method 1)...
    powershell -Command "try { Invoke-WebRequest -Uri 'https://www.nuget.org/api/v2/package/Microsoft.UI.Xaml/2.8.6' -OutFile 'xaml.zip' -UseBasicParsing; Expand-Archive -Path 'xaml.zip' -DestinationPath 'xaml' -Force; Copy-Item 'xaml\tools\AppX\x64\Release\Microsoft.UI.Xaml.2.8.appx' -Destination 'Microsoft.UI.Xaml.2.8.appx' } catch { exit 1 }"
    
    if not exist "Microsoft.UI.Xaml.2.8.appx" (
        echo Method 1 failed, trying GitHub release (Method 2)...
        powershell -Command "try { Invoke-WebRequest -Uri 'https://github.com/microsoft/microsoft-ui-xaml/releases/download/v2.8.6/Microsoft.UI.Xaml.2.8.x64.appx' -OutFile 'Microsoft.UI.Xaml.2.8.appx' -UseBasicParsing } catch { }"
    )
    
    if not exist "Microsoft.UI.Xaml.2.8.appx" (
        echo Method 2 failed, trying store API (Method 3)...
        powershell -Command "try { $response = Invoke-RestMethod -Uri 'https://store.rg-adguard.net/api/GetFiles' -Method Post -Body 'type=ProductId&url=9P3395VX91NR&ring=Retail&lang=en-US' -ContentType 'application/x-www-form-urlencoded'; $downloadUrl = ($response | Select-String -Pattern 'https://[^\"]*Microsoft\.UI\.Xaml[^\"]*\.appx').Matches[0].Value; Invoke-WebRequest -Uri $downloadUrl -OutFile 'Microsoft.UI.Xaml.2.8.appx' -UseBasicParsing } catch { }"
    )
    
    if not exist "Microsoft.UI.Xaml.2.8.appx" (
        echo Method 3 failed, trying alternative NuGet version (Method 4)...
        powershell -Command "try { Invoke-WebRequest -Uri 'https://www.nuget.org/api/v2/package/Microsoft.UI.Xaml/2.7.3' -OutFile 'xaml27.zip' -UseBasicParsing; Expand-Archive -Path 'xaml27.zip' -DestinationPath 'xaml27' -Force; Copy-Item 'xaml27\tools\AppX\x64\Release\Microsoft.UI.Xaml.2.7.appx' -Destination 'Microsoft.UI.Xaml.2.7.appx' } catch { }"
        if exist "Microsoft.UI.Xaml.2.7.appx" ren "Microsoft.UI.Xaml.2.7.appx" "Microsoft.UI.Xaml.2.8.appx"
    )
    
    if exist "Microsoft.UI.Xaml.2.8.appx" (
        echo Installing UI.Xaml package...
        powershell -Command "try { Add-AppxPackage -Path 'Microsoft.UI.Xaml.2.8.appx' -ErrorAction Stop; Write-Host '✓ UI.Xaml installed successfully' } catch { Write-Host 'Standard install failed, trying force install'; Add-AppxPackage -Path 'Microsoft.UI.Xaml.2.8.appx' -ForceApplicationShutdown }"
        set "XAML_INSTALLED=true"
    ) else (
        echo Warning: Could not install UI.Xaml, WinGet may not work properly
    )
)

echo.
echo Step 4: Ensuring Microsoft Store Components
echo ========================================

REM Check if Microsoft Store is available
echo Checking Microsoft Store availability...
powershell -Command "try { Get-AppxPackage -Name 'Microsoft.WindowsStore' | Select-Object -First 1 | Out-Null; exit 0 } catch { exit 1 }" >nul 2>&1
if %errorLevel% EQU 0 (
    echo ✓ Microsoft Store is available
    set "STORE_INSTALLED=true"
) else (
    echo ✗ Microsoft Store not found
    echo Note: WinGet may have limited functionality without Microsoft Store
    
    REM Try to install essential store components
    echo Attempting to install essential store components...
    powershell -Command "try { Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.WindowsStore_8wekyb3d8bbwe } catch { Write-Host 'Store registration failed' }"
    
    REM Enable Windows Store via features
    dism /online /enable-feature /featurename:Microsoft-Windows-Store /all /quiet
)

echo.
echo Step 5: Installing WinGet (Windows Package Manager)
echo ========================================

REM Check if WinGet is already installed
echo Checking WinGet installation...
where winget >nul 2>&1
if %errorLevel% EQU 0 (
    echo ✓ WinGet is already installed
    winget --version
    set "WINGET_INSTALLED=true"
    goto :install_pwsh
) else (
    echo ✗ WinGet not found, proceeding with installation...
)

echo Installing WinGet (App Installer)...

REM Method 1: Latest GitHub release
echo Downloading WinGet from GitHub (Method 1)...
powershell -Command "try { $response = Invoke-RestMethod -Uri 'https://api.github.com/repos/microsoft/winget-cli/releases/latest' -UseBasicParsing; $downloadUrl = ($response.assets | Where-Object { $_.name -like '*msixbundle' }).browser_download_url; Invoke-WebRequest -Uri $downloadUrl -OutFile 'Microsoft.DesktopAppInstaller.msixbundle' -UseBasicParsing -TimeoutSec 60 } catch { exit 1 }"

if not exist "Microsoft.DesktopAppInstaller.msixbundle" (
    echo Method 1 failed, trying direct link (Method 2)...
    powershell -Command "try { Invoke-WebRequest -Uri 'https://github.com/microsoft/winget-cli/releases/latest/download/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle' -OutFile 'Microsoft.DesktopAppInstaller.msixbundle' -UseBasicParsing } catch { }"
)

if not exist "Microsoft.DesktopAppInstaller.msixbundle" (
    echo Method 2 failed, trying Microsoft Store API (Method 3)...
    powershell -Command "try { $response = Invoke-RestMethod -Uri 'https://store.rg-adguard.net/api/GetFiles' -Method Post -Body 'type=ProductId&url=9NBLGGH4NNS1&ring=Retail&lang=en-US' -ContentType 'application/x-www-form-urlencoded'; $downloadUrl = ($response | Select-String -Pattern 'https://[^\"]*DesktopAppInstaller[^\"]*\.msixbundle').Matches[0].Value; Invoke-WebRequest -Uri $downloadUrl -OutFile 'Microsoft.DesktopAppInstaller.msixbundle' -UseBasicParsing } catch { }"
)

if exist "Microsoft.DesktopAppInstaller.msixbundle" (
    echo Installing WinGet package...
    powershell -Command "try { Add-AppxPackage -Path 'Microsoft.DesktopAppInstaller.msixbundle' -ErrorAction Stop; Write-Host '✓ WinGet installed successfully' } catch { Write-Host 'Standard install failed, trying alternatives'; try { Add-AppxPackage -Path 'Microsoft.DesktopAppInstaller.msixbundle' -ForceApplicationShutdown } catch { Write-Host 'Force install failed, trying registration'; Add-AppxPackage -Path 'Microsoft.DesktopAppInstaller.msixbundle' -Register -DisableDevelopmentMode } }"
    
    echo Waiting for WinGet to be available...
    timeout /t 15 /nobreak >nul
    
    REM Add WindowsApps to PATH if not already there
    echo %PATH% | find /i "WindowsApps" >nul
    if %errorLevel% NEQ 0 (
        set "PATH=%PATH%;%LOCALAPPDATA%\Microsoft\WindowsApps"
        echo Added WindowsApps to PATH
    )
    
    REM Verify WinGet installation
    where winget >nul 2>&1
    if %errorLevel% EQU 0 (
        echo ✓ WinGet installation verified
        winget --version
        set "WINGET_INSTALLED=true"
    ) else (
        echo Warning: WinGet installed but not found in PATH
        echo Trying to locate WinGet...
        for /r "%LOCALAPPDATA%\Microsoft\WindowsApps" %%f in (winget.exe) do (
            if exist "%%f" (
                echo Found WinGet at: %%f
                set "PATH=%PATH%;%%~dpf"
                set "WINGET_INSTALLED=true"
            )
        )
    )
) else (
    echo ✗ Failed to download WinGet installer
    echo WinGet installation failed - continuing without it
)

:install_pwsh
echo.
echo Step 6: Installing PowerShell 7
echo ========================================

REM Check if PowerShell 7 is already installed
echo Checking PowerShell 7 installation...
where pwsh >nul 2>&1
if %errorLevel% EQU 0 (
    echo ✓ PowerShell 7 is already installed
    pwsh --version
    set "PWSH_INSTALLED=true"
    set "PWSH_CMD=pwsh"
    goto :download_repo
) else (
    echo ✗ PowerShell 7 not found in PATH
)

REM Check common installation paths
echo Checking common PowerShell 7 installation paths...
set "PS7_PATHS[0]=%ProgramFiles%\PowerShell\7\pwsh.exe"
set "PS7_PATHS[1]=%ProgramFiles(x86)%\PowerShell\7\pwsh.exe"
set "PS7_PATHS[2]=%LOCALAPPDATA%\Microsoft\powershell\pwsh.exe"

for /L %%i in (0,1,2) do (
    if exist "!PS7_PATHS[%%i]!" (
        echo ✓ PowerShell 7 found at: !PS7_PATHS[%%i]!
        set "PWSH_CMD=!PS7_PATHS[%%i]!"
        set "PWSH_INSTALLED=true"
        goto :download_repo
    )
)

echo PowerShell 7 not found, proceeding with installation...

REM Try WinGet first if available
if "%WINGET_INSTALLED%"=="true" (
    echo Trying WinGet installation (Method 1)...
    winget install --id Microsoft.PowerShell --source winget --accept-package-agreements --accept-source-agreements --silent --disable-interactivity
    
    timeout /t 30 /nobreak >nul
    
    where pwsh >nul 2>&1
    if %errorLevel% EQU 0 (
        echo ✓ PowerShell 7 installed successfully via WinGet
        pwsh --version
        set "PWSH_CMD=pwsh"
        set "PWSH_INSTALLED=true"
        goto :download_repo
    )
)

REM Manual installation method
echo Downloading PowerShell 7 manually (Method 2)...

REM Get system architecture
set "ARCH=x64"
if "%PROCESSOR_ARCHITECTURE%"=="x86" set "ARCH=x86"
echo Detected architecture: %ARCH%

REM Download PowerShell 7
echo Getting latest PowerShell 7 release...
powershell -Command "try { $response = Invoke-RestMethod -Uri 'https://api.github.com/repos/PowerShell/PowerShell/releases/latest' -UseBasicParsing; $asset = $response.assets | Where-Object { $_.name -like '*win-%ARCH%.msi' -and $_.name -notlike '*arm*' } | Select-Object -First 1; if ($asset) { Invoke-WebRequest -Uri $asset.browser_download_url -OutFile 'PowerShell-7-win-%ARCH%.msi' -UseBasicParsing } else { throw 'No MSI found' } } catch { Invoke-WebRequest -Uri 'https://github.com/PowerShell/PowerShell/releases/download/v7.4.6/PowerShell-7.4.6-win-%ARCH%.msi' -OutFile 'PowerShell-7-win-%ARCH%.msi' -UseBasicParsing }"

if exist "PowerShell-7-win-%ARCH%.msi" (
    echo Installing PowerShell 7...
    msiexec /i "PowerShell-7-win-%ARCH%.msi" /quiet /norestart ADD_EXPLORER_CONTEXT_MENU_OPENPOWERSHELL=1 ENABLE_PSREMOTING=1 REGISTER_MANIFEST=1
    
    timeout /t 30 /nobreak >nul
    
    REM Refresh PATH
    for /f "tokens=2*" %%a in ('reg query "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" /v PATH 2^>nul') do set "PATH=%%b;%PATH%"
    
    where pwsh >nul 2>&1
    if %errorLevel% EQU 0 (
        echo ✓ PowerShell 7 installed successfully
        pwsh --version
        set "PWSH_CMD=pwsh"
        set "PWSH_INSTALLED=true"
    ) else (
        REM Check installation paths again
        for /L %%i in (0,1,2) do (
            if exist "!PS7_PATHS[%%i]!" (
                echo ✓ PowerShell 7 found at: !PS7_PATHS[%%i]!
                set "PWSH_CMD=!PS7_PATHS[%%i]!"
                set "PWSH_INSTALLED=true"
                goto :download_repo
            )
        )
        echo Warning: PowerShell 7 installation may have failed
        set "PWSH_CMD=powershell"
    )
) else (
    echo ✗ Failed to download PowerShell 7
    echo Using Windows PowerShell instead
    set "PWSH_CMD=powershell"
)

:download_repo
echo.
echo Step 7: Downloading Maintenance Script Repository
echo ========================================

cd /d "%SCRIPT_DIR%"

if exist "script_mentenanta" (
    echo Clearing existing repository...
    rmdir /s /q "script_mentenanta" >nul 2>&1
)

cd /d "%TEMP_DIR%"

echo Downloading repository...
powershell -Command "try { Invoke-WebRequest -Uri 'https://github.com/ichimbogdancristian/script_mentenanta/archive/refs/heads/main.zip' -OutFile 'script_mentenanta.zip' -UseBasicParsing } catch { exit 1 }"

if exist "script_mentenanta.zip" (
    echo Extracting repository...
    powershell -Command "Expand-Archive -Path 'script_mentenanta.zip' -DestinationPath '.' -Force"
    
    if exist "script_mentenanta-main" (
        move "script_mentenanta-main" "%SCRIPT_DIR%\script_mentenanta" >nul 2>&1
        echo ✓ Repository downloaded and extracted successfully
    )
)

:summary
echo.
echo ========================================
echo Installation Summary
echo ========================================
echo Visual C++ Redistributable: %VCREDIST_INSTALLED%
echo VCLibs Desktop Bridge: %DESKTOPBRIDGE_INSTALLED%
echo VCLibs UWP Runtime: %VCLIBS_INSTALLED%
echo Microsoft.UI.Xaml: %XAML_INSTALLED%
echo Microsoft Store: %STORE_INSTALLED%
echo WinGet: %WINGET_INSTALLED%
echo PowerShell 7: %PWSH_INSTALLED%
echo.

cd /d "%SCRIPT_DIR%"
if exist "script_mentenanta\script.ps1" (
    echo Launching maintenance script...
    if not defined PWSH_CMD set "PWSH_CMD=powershell"
    powershell -Command "Start-Process -FilePath '%PWSH_CMD%' -ArgumentList '-ExecutionPolicy','Bypass','-File','script_mentenanta\script.ps1' -Verb RunAs"
    exit /b 0
) else (
    echo ✗ Maintenance script not found
    pause
    exit /b 1
)

REM Cleanup
rmdir /s /q "%TEMP_DIR%" >nul 2>&1