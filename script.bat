@echo off
setlocal enabledelayedexpansion

echo ========================================
echo Setting up WinGet, PowerShell 7, and running maintenance script
echo ========================================

REM Check if running as administrator and relaunch if not
net session >nul 2>&1
if %errorLevel% NEQ 0 (
    echo This script requires administrator privileges.
    echo Attempting to relaunch with administrator privileges...
    
    REM Get the full path of the current script
    set "SCRIPT_PATH=%~f0"
    
    REM Relaunch with admin privileges using PowerShell
    powershell -Command "Start-Process -FilePath 'cmd.exe' -ArgumentList '/c', '\"!SCRIPT_PATH!\"' -Verb RunAs -Wait"
    
    REM Check if the relaunch was successful
    if %errorLevel% NEQ 0 (
        echo Failed to obtain administrator privileges.
        echo Please manually run this script as administrator.
        pause
        exit /b 1
    )
    
    echo Script relaunched with administrator privileges.
    exit /b 0
)

echo ✓ Running with administrator privileges

REM Get the directory where this script is located
set SCRIPT_DIR=%~dp0
echo Script running from: %SCRIPT_DIR%

REM Create temp directory for downloads only
set TEMP_DIR=%TEMP%\setup_maintenance
if not exist "%TEMP_DIR%" mkdir "%TEMP_DIR%"

echo.
echo Step 1: Checking and Installing WinGet Dependencies
echo ========================================

REM Function to check if a specific AppX package is installed
set "VCLIBS_INSTALLED=false"
set "XAML_INSTALLED=false"
set "WINGET_INSTALLED=false"

REM Check VCLibs installation with error handling
echo Checking Microsoft.VCLibs installation...
cd /d "%TEMP_DIR%"
powershell -Command "try { $packages = Get-AppxPackage -Name 'Microsoft.VCLibs*' -ErrorAction SilentlyContinue; if ($packages -and ($packages | Where-Object {[version]$_.Version -ge '14.0'})) { Write-Host 'VCLIBS_FOUND'; exit 0 } else { Write-Host 'VCLIBS_NOT_FOUND'; exit 1 } } catch { Write-Host 'VCLIBS_ERROR'; exit 1 }" >nul 2>&1
if %errorLevel% EQU 0 (
    echo ✓ Microsoft.VCLibs is already installed
    set "VCLIBS_INSTALLED=true"
) else (
    echo ✗ Microsoft.VCLibs not found or outdated
)

REM Check UI.Xaml installation with error handling
echo Checking Microsoft.UI.Xaml installation...
powershell -Command "try { $packages = Get-AppxPackage -Name 'Microsoft.UI.Xaml*' -ErrorAction SilentlyContinue; if ($packages -and ($packages | Where-Object {[version]$_.Version -ge '2.7'})) { Write-Host 'XAML_FOUND'; exit 0 } else { Write-Host 'XAML_NOT_FOUND'; exit 1 } } catch { Write-Host 'XAML_ERROR'; exit 1 }" >nul 2>&1
if %errorLevel% EQU 0 (
    echo ✓ Microsoft.UI.Xaml 2.7+ is already installed
    set "XAML_INSTALLED=true"
) else (
    echo ✗ Microsoft.UI.Xaml 2.7+ not found
)

REM Check WinGet installation
echo Checking WinGet installation...
where winget >nul 2>&1
if %errorLevel% EQU 0 (
    echo ✓ WinGet is already installed
    winget --version
    set "WINGET_INSTALLED=true"
    goto :check_pwsh
) else (
    echo ✗ WinGet not found
)

REM Install VCLibs if not installed
if "%VCLIBS_INSTALLED%"=="false" (
    echo.
    echo Installing Microsoft.VCLibs...
    echo Downloading VCLibs...
    powershell -Command "try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; $ProgressPreference = 'SilentlyContinue'; Invoke-WebRequest -Uri 'https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx' -OutFile 'VCLibs.appx' -UseBasicParsing; Write-Host 'Download completed' } catch { Write-Host 'Download failed:' $_.Exception.Message; exit 1 }"
    
    if %errorLevel% NEQ 0 (
        echo Failed to download VCLibs, trying alternative...
        powershell -Command "try { $client = New-Object System.Net.WebClient; $client.DownloadFile('https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx', 'VCLibs.appx'); Write-Host 'Alternative download completed' } catch { Write-Host 'Alternative download failed'; exit 1 }"
    )
    
    if exist "VCLibs.appx" (
        echo Installing VCLibs package...
        powershell -Command "try { Add-AppxPackage -Path 'VCLibs.appx' -ErrorAction Stop; Write-Host '✓ VCLibs installed successfully' } catch { Write-Host '✗ VCLibs install failed:' $_.Exception.Message; exit 1 }"
        if %errorLevel% EQU 0 set "VCLIBS_INSTALLED=true"
    ) else (
        echo ✗ VCLibs.appx file not found after download
    )
) else (
    echo Skipping VCLibs installation - already present
)

REM Install UI.Xaml if not installed
if "%XAML_INSTALLED%"=="false" (
    echo.
    echo Installing Microsoft.UI.Xaml 2.8...
    echo Downloading UI.Xaml package...
    powershell -Command "try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; $ProgressPreference = 'SilentlyContinue'; Invoke-WebRequest -Uri 'https://www.nuget.org/api/v2/package/Microsoft.UI.Xaml/2.8.6' -OutFile 'xaml.zip' -UseBasicParsing; Write-Host 'NuGet package downloaded'; Expand-Archive -Path 'xaml.zip' -DestinationPath 'xaml' -Force; Copy-Item 'xaml\tools\AppX\x64\Release\Microsoft.UI.Xaml.2.8.appx' -Destination 'Microsoft.UI.Xaml.2.8.appx'; Write-Host 'Package extracted' } catch { Write-Host 'NuGet method failed, trying GitHub...'; try { Invoke-WebRequest -Uri 'https://github.com/microsoft/microsoft-ui-xaml/releases/download/v2.8.6/Microsoft.UI.Xaml.2.8.x64.appx' -OutFile 'Microsoft.UI.Xaml.2.8.appx' -UseBasicParsing; Write-Host 'GitHub download completed' } catch { Write-Host 'All download methods failed'; exit 1 } }"
    
    if exist "Microsoft.UI.Xaml.2.8.appx" (
        echo Installing UI.Xaml package...
        powershell -Command "try { Add-AppxPackage -Path 'Microsoft.UI.Xaml.2.8.appx' -ErrorAction Stop; Write-Host '✓ UI.Xaml installed successfully' } catch { Write-Host '✗ UI.Xaml install failed:' $_.Exception.Message; exit 1 }"
        if %errorLevel% EQU 0 set "XAML_INSTALLED=true"
    ) else (
        echo ✗ Microsoft.UI.Xaml.2.8.appx file not found after download
    )
) else (
    echo Skipping UI.Xaml installation - already present
)

REM Install WinGet if not installed
if "%WINGET_INSTALLED%"=="false" (
    echo.
    echo Installing WinGet (App Installer)...
    echo Downloading WinGet package...
    powershell -Command "try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; $ProgressPreference = 'SilentlyContinue'; $response = Invoke-RestMethod -Uri 'https://api.github.com/repos/microsoft/winget-cli/releases/latest' -UseBasicParsing; $downloadUrl = ($response.assets | Where-Object { $_.name -like '*msixbundle' }).browser_download_url; Invoke-WebRequest -Uri $downloadUrl -OutFile 'Microsoft.DesktopAppInstaller.msixbundle' -UseBasicParsing; Write-Host 'Latest WinGet downloaded' } catch { Write-Host 'API failed, using direct link...'; try { Invoke-WebRequest -Uri 'https://github.com/microsoft/winget-cli/releases/latest/download/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle' -OutFile 'Microsoft.DesktopAppInstaller.msixbundle' -UseBasicParsing; Write-Host 'Direct download completed' } catch { Write-Host 'All download methods failed'; exit 1 } }"
    
    if exist "Microsoft.DesktopAppInstaller.msixbundle" (
        echo Installing WinGet package...
        powershell -Command "try { Add-AppxPackage -Path 'Microsoft.DesktopAppInstaller.msixbundle' -ErrorAction Stop; Write-Host '✓ WinGet installed successfully' } catch { Write-Host '✗ WinGet install failed:' $_.Exception.Message; exit 1 }"
        
        if %errorLevel% EQU 0 (
            set "WINGET_INSTALLED=true"
            echo Waiting for WinGet to be available...
            timeout /t 10 /nobreak >nul
            
            REM Add WindowsApps to PATH if not already there
            echo %PATH% | find /i "WindowsApps" >nul
            if %errorLevel% NEQ 0 (
                set "PATH=%PATH%;%LOCALAPPDATA%\Microsoft\WindowsApps"
                echo Added WindowsApps to PATH
            )
        )
    ) else (
        echo ✗ Microsoft.DesktopAppInstaller.msixbundle file not found after download
    )
) else (
    echo Skipping WinGet installation - already present
)

echo.
echo Dependencies check completed:
echo - VCLibs: %VCLIBS_INSTALLED%
echo - UI.Xaml: %XAML_INSTALLED%
echo - WinGet: %WINGET_INSTALLED%

:check_pwsh
echo.
echo Step 2: Checking and Installing PowerShell 7
echo ========================================

REM Check if PowerShell 7 is already installed
echo Checking PowerShell 7 installation...
where pwsh >nul 2>&1
if %errorLevel% EQU 0 (
    echo ✓ PowerShell 7 is already installed
    pwsh --version
    set "PWSH_CMD=pwsh"
    goto :check_repo
) else (
    echo ✗ PowerShell 7 not found in PATH
)

REM Check common installation paths
echo Checking common PowerShell 7 installation paths...
set "PS7_PATHS[0]=%ProgramFiles%\PowerShell\7\pwsh.exe"
set "PS7_PATHS[1]=%ProgramFiles(x86)%\PowerShell\7\pwsh.exe"
set "PS7_PATHS[2]=%LOCALAPPDATA%\Microsoft\powershell\pwsh.exe"
set "PS7_PATHS[3]=%USERPROFILE%\AppData\Local\Microsoft\powershell\pwsh.exe"

for /L %%i in (0,1,3) do (
    if exist "!PS7_PATHS[%%i]!" (
        echo ✓ PowerShell 7 found at: !PS7_PATHS[%%i]!
        set "PWSH_PATH=!PS7_PATHS[%%i]!"
        set "PWSH_CMD=!PS7_PATHS[%%i]!"
        
        REM Add to PATH for this session
        for %%p in ("!PS7_PATHS[%%i]!") do set "PATH=%PATH%;%%~dpp"
        echo Added PowerShell 7 directory to PATH
        goto :check_repo
    )
)

echo PowerShell 7 not found in common paths, proceeding with installation...

REM Try WinGet first if available
where winget >nul 2>&1
if %errorLevel% EQU 0 (
    echo Trying WinGet installation...
    winget install --id Microsoft.PowerShell --source winget --accept-package-agreements --accept-source-agreements --silent --disable-interactivity
    
    REM Wait longer for installation to complete
    echo Waiting for WinGet installation to complete...
    timeout /t 30 /nobreak >nul
    
    REM Check if installation succeeded
    where pwsh >nul 2>&1
    if %errorLevel% EQU 0 (
        echo ✓ PowerShell 7 installed successfully via WinGet
        pwsh --version
        set "PWSH_CMD=pwsh"
        goto :check_repo
    ) else (
        REM Check again in common paths after WinGet installation
        for /L %%i in (0,1,3) do (
            if exist "!PS7_PATHS[%%i]!" (
                echo ✓ PowerShell 7 found after WinGet at: !PS7_PATHS[%%i]!
                set "PWSH_PATH=!PS7_PATHS[%%i]!"
                set "PWSH_CMD=!PS7_PATHS[%%i]!"
                
                REM Add to PATH for this session
                for %%p in ("!PS7_PATHS[%%i]!") do set "PATH=%PATH%;%%~dpp"
                echo Added PowerShell 7 directory to PATH
                goto :check_repo
            )
        )
        echo WinGet installation may have failed, trying manual download...
    )
) else (
    echo WinGet not available, downloading PowerShell 7 directly...
)

REM Manual installation method
echo Downloading PowerShell 7 manually...

REM Get system architecture
set "ARCH=x64"
if "%PROCESSOR_ARCHITECTURE%"=="AMD64" set "ARCH=x64"
if "%PROCESSOR_ARCHITECTURE%"=="x86" set "ARCH=x86"
if "%PROCESSOR_ARCHITEW6432%"=="AMD64" set "ARCH=x64"

echo Detected architecture: %ARCH%

REM Download the latest PowerShell 7 release
echo Getting latest PowerShell 7 release information...
powershell -Command "try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; $ProgressPreference = 'SilentlyContinue'; Write-Host 'Fetching release info...'; $response = Invoke-RestMethod -Uri 'https://api.github.com/repos/PowerShell/PowerShell/releases/latest' -UseBasicParsing; $asset = $response.assets | Where-Object { $_.name -like '*win-%ARCH%.msi' -and $_.name -notlike '*arm*' } | Select-Object -First 1; if ($asset) { Write-Host ('Found asset: ' + $asset.name); Invoke-WebRequest -Uri $asset.browser_download_url -OutFile 'PowerShell-7-win-%ARCH%.msi' -UseBasicParsing; Write-Host 'Downloaded successfully' } else { throw 'No suitable MSI found for %ARCH%' } } catch { Write-Host ('API method failed: ' + $_.Exception.Message); Write-Host 'Trying direct download...'; try { Invoke-WebRequest -Uri 'https://github.com/PowerShell/PowerShell/releases/download/v7.4.6/PowerShell-7.4.6-win-%ARCH%.msi' -OutFile 'PowerShell-7-win-%ARCH%.msi' -UseBasicParsing; Write-Host 'Direct download completed' } catch { Write-Host ('Direct download failed: ' + $_.Exception.Message); exit 1 } }"

if not exist "PowerShell-7-win-%ARCH%.msi" (
    echo Failed to download PowerShell 7 MSI, trying alternative method...
    powershell -Command "try { $client = New-Object System.Net.WebClient; $client.DownloadFile('https://github.com/PowerShell/PowerShell/releases/download/v7.4.6/PowerShell-7.4.6-win-%ARCH%.msi', 'PowerShell-7-win-%ARCH%.msi'); Write-Host 'WebClient download completed' } catch { Write-Host ('WebClient failed: ' + $_.Exception.Message) }"
)

if exist "PowerShell-7-win-%ARCH%.msi" (
    echo ✓ PowerShell 7 MSI downloaded successfully
    echo Installing PowerShell 7 (this may take a few minutes)...
    
    REM Create a detailed log file
    set "LOG_FILE=%TEMP_DIR%\ps7_install.log"
    
    REM Install with more verbose logging
    msiexec /i "PowerShell-7-win-%ARCH%.msi" /quiet /norestart /l*v "%LOG_FILE%" ADD_EXPLORER_CONTEXT_MENU_OPENPOWERSHELL=1 ENABLE_PSREMOTING=1 REGISTER_MANIFEST=1
    
    REM Store the exit code
    set "INSTALL_EXIT_CODE=%errorLevel%"
    
    echo MSI installer exit code: %INSTALL_EXIT_CODE%
    
    if %INSTALL_EXIT_CODE% EQU 0 (
        echo ✓ MSI installation completed successfully
    ) else if %INSTALL_EXIT_CODE% EQU 3010 (
        echo ✓ MSI installation completed successfully (reboot required)
    ) else (
        echo ✗ MSI installation failed with exit code: %INSTALL_EXIT_CODE%
        echo Check log file: %LOG_FILE%
        
        REM Show last few lines of log for debugging
        echo Last few lines of installation log:
        powershell -Command "Get-Content '%LOG_FILE%' | Select-Object -Last 10"
    )
    
    echo Waiting for installation to complete...
    timeout /t 20 /nobreak >nul
    
    REM Refresh environment variables
    echo Refreshing environment variables...
    for /f "tokens=2*" %%a in ('reg query "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" /v PATH 2^>nul') do set "SYSTEM_PATH=%%b"
    for /f "tokens=2*" %%a in ('reg query "HKCU\Environment" /v PATH 2^>nul') do set "USER_PATH=%%b"
    
    REM Combine paths
    if defined USER_PATH (
        set "PATH=%SYSTEM_PATH%;%USER_PATH%"
    ) else (
        set "PATH=%SYSTEM_PATH%"
    )
    
    REM Also add common PowerShell 7 paths manually
    set "PATH=%PATH%;%ProgramFiles%\PowerShell\7;%ProgramFiles(x86)%\PowerShell\7"
    
    echo Updated PATH for this session
    
) else (
    echo ✗ Failed to download PowerShell 7 MSI
    echo Will use Windows PowerShell instead...
    set "PWSH_CMD=powershell"
    goto :check_repo
)

REM Final verification with multiple methods
echo Verifying PowerShell 7 installation...

REM Method 1: Check if pwsh is in PATH
where pwsh >nul 2>&1
if %errorLevel% EQU 0 (
    echo ✓ PowerShell 7 found in PATH!
    pwsh --version
    set "PWSH_CMD=pwsh"
    goto :check_repo
)

REM Method 2: Check common installation paths again
for /L %%i in (0,1,3) do (
    if exist "!PS7_PATHS[%%i]!" (
        echo ✓ PowerShell 7 found at: !PS7_PATHS[%%i]!
        set "PWSH_PATH=!PS7_PATHS[%%i]!"
        set "PWSH_CMD=!PS7_PATHS[%%i]!"
        
        REM Test if it works
        "!PS7_PATHS[%%i]!" --version >nul 2>&1
        if !errorLevel! EQU 0 (
            echo ✓ PowerShell 7 is working correctly
            "!PS7_PATHS[%%i]!" --version
            goto :check_repo
        ) else (
            echo ✗ PowerShell 7 found but not working properly
        )
    )
)

REM Method 3: Search for pwsh.exe in Program Files
echo Searching for PowerShell 7 in Program Files...
for /r "%ProgramFiles%" %%f in (pwsh.exe) do (
    if exist "%%f" (
        echo ✓ Found PowerShell 7 at: %%f
        set "PWSH_CMD=%%f"
        
        REM Test if it works
        "%%f" --version >nul 2>&1
        if !errorLevel! EQU 0 (
            echo ✓ PowerShell 7 is working correctly
            "%%f" --version
            goto :check_repo
        )
    )
)

echo ✗ PowerShell 7 installation verification failed
echo Falling back to Windows PowerShell...
set "PWSH_CMD=powershell"

:check_repo
echo.
echo Step 3: Checking and Downloading maintenance script repository
echo ========================================

REM Switch to script directory for repository operations
cd /d "%SCRIPT_DIR%"

REM Check if repository already exists in script directory
if exist "script_mentenanta" (
    echo ✓ Repository already exists in script directory
    echo Clearing existing repository contents to download latest version...
    
    REM Remove existing repository completely
    rmdir /s /q "script_mentenanta" >nul 2>&1
    if exist "script_mentenanta" (
        echo Warning: Could not completely remove existing repository
        echo Attempting force removal...
        powershell -Command "Remove-Item -Path 'script_mentenanta' -Recurse -Force -ErrorAction SilentlyContinue"
    )
    
    if exist "script_mentenanta" (
        echo Error: Failed to remove existing repository
        echo Please manually delete the 'script_mentenanta' folder and run this script again
        pause
        exit /b 1
    )
    
    echo ✓ Existing repository cleared successfully
)

echo Downloading latest repository version...

REM Switch to temp directory for download
cd /d "%TEMP_DIR%"
if exist "script_mentenanta.zip" del "script_mentenanta.zip"

echo Downloading repository as ZIP to temp directory...
powershell -Command "try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; $ProgressPreference = 'SilentlyContinue'; Invoke-WebRequest -Uri 'https://github.com/ichimbogdancristian/script_mentenanta/archive/refs/heads/main.zip' -OutFile 'script_mentenanta.zip' -UseBasicParsing; Write-Host 'Download completed successfully' } catch { Write-Host 'Download failed:' $_.Exception.Message; exit 1 }"

if not exist "script_mentenanta.zip" (
    echo Download failed, trying alternative method...
    powershell -Command "try { $client = New-Object System.Net.WebClient; $client.DownloadFile('https://github.com/ichimbogdancristian/script_mentenanta/archive/refs/heads/main.zip', 'script_mentenanta.zip'); Write-Host 'Alternative download completed' } catch { Write-Host 'Alternative download failed'; exit 1 }"
)

if not exist "script_mentenanta.zip" (
    echo Failed to download repository with all methods
    pause
    exit /b 1
)

echo ✓ Repository downloaded successfully
echo Extracting repository to script directory...

REM Clean any existing extracted folders first
if exist "script_mentenanta-main" rmdir /s /q "script_mentenanta-main" >nul 2>&1
if exist "script_mentenanta-master" rmdir /s /q "script_mentenanta-master" >nul 2>&1

REM Try Windows 10/11 native tar first
where tar >nul 2>&1
if %errorLevel% EQU 0 (
    tar -xf "script_mentenanta.zip" >nul 2>&1
    if %errorLevel% EQU 0 (
        echo ✓ Successfully extracted with tar
    ) else (
        echo tar failed, using PowerShell...
        powershell -Command "Expand-Archive -Path 'script_mentenanta.zip' -DestinationPath '.' -Force"
    )
) else (
    echo Using PowerShell to extract...
    powershell -Command "Expand-Archive -Path 'script_mentenanta.zip' -DestinationPath '.' -Force"
)

REM Handle the extracted folder name and move to script directory
if exist "script_mentenanta-main" (
    echo Moving repository to script directory...
    move "script_mentenanta-main" "%SCRIPT_DIR%\script_mentenanta" >nul 2>&1
    if %errorLevel% EQU 0 (
        echo ✓ Repository moved to script directory successfully
    ) else (
        echo Failed to move repository, trying copy method...
        xcopy "script_mentenanta-main" "%SCRIPT_DIR%\script_mentenanta\" /E /I /Q
        if %errorLevel% EQU 0 (
            rmdir /s /q "script_mentenanta-main" >nul 2>&1
            echo ✓ Repository copied to script directory successfully
        ) else (
            echo ✗ Failed to copy repository
        )
    )
) else if exist "script_mentenanta-master" (
    echo Moving repository to script directory...
    move "script_mentenanta-master" "%SCRIPT_DIR%\script_mentenanta" >nul 2>&1
    if %errorLevel% EQU 0 (
        echo ✓ Repository moved to script directory successfully
    ) else (
        echo Failed to move repository, trying copy method...
        xcopy "script_mentenanta-master" "%SCRIPT_DIR%\script_mentenanta\" /E /I /Q
        if %errorLevel% EQU 0 (
            rmdir /s /q "script_mentenanta-master" >nul 2>&1
            echo ✓ Repository copied to script directory successfully
        ) else (
            echo ✗ Failed to copy repository
        )
    )
) else (
    echo ✗ No extracted folder found
    echo Available files/folders in temp directory:
    dir /b
)

REM Switch back to script directory to verify
cd /d "%SCRIPT_DIR%"

if not exist "script_mentenanta" (
    echo ✗ Failed to extract repository to script directory
    echo Available folders in script directory:
    dir /b /ad
    echo Available folders in temp directory:
    cd /d "%TEMP_DIR%"
    dir /b /ad
    pause
    exit /b 1
)

echo ✓ Repository successfully updated with latest version

:run_script

REM Ensure we're in the script directory
cd /d "%SCRIPT_DIR%"
cd script_mentenanta

REM Check if script.ps1 exists
if not exist "script.ps1" (
    echo ✗ script.ps1 not found in the repository
    echo Available files:
    dir /b
    pause
    exit /b 1
)

echo ✓ Found script.ps1
echo Launching script.ps1 in a new PowerShell 7 window with administrator rights...

REM Launch script.ps1 in a new PowerShell 7 window as administrator
REM If PWSH_CMD is not set, fallback to pwsh
if not defined PWSH_CMD set "PWSH_CMD=pwsh"

REM Use PowerShell to start a new window with admin rights
powershell -Command "Start-Process -FilePath '%PWSH_CMD%' -ArgumentList '-ExecutionPolicy','Bypass','-File','script.ps1' -Verb RunAs"

REM Immediately close the batch window
exit /b 0