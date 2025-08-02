@echo off
chcp 65001 >nul 2>&1 || chcp 850 >nul 2>&1
setlocal enabledelayedexpansion

echo ===============================================
echo    Windows Maintenance Script v2.0
echo    Enhanced with repository downloading
echo ===============================================

REM Check if running as administrator
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo [ADMIN] Requesting administrator privileges...
    echo [INFO] This window will close and reopen with admin rights...
    powershell -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit
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

REM Initialize variables
set "SCRIPT_DIR=%~dp0"
set "TEMP_DIR=%TEMP%\windows_maintenance_%RANDOM%"
set "VCLIBS_INSTALLED=false"
set "XAML_INSTALLED=false"
set "WINGET_INSTALLED=false"
set "PS7_INSTALLED=false"
set "ERROR_COUNT=0"
set "USE_LOCAL_FILES=false"

echo [INFO] Script directory: !SCRIPT_DIR!
echo [INFO] Temp directory: !TEMP_DIR!

REM Check if we have local modular files (MaintenanceOrchestrator.ps1 and config)
set "LOCAL_SCRIPT_PATH=%~dp0MaintenanceOrchestrator.ps1"
set "LOCAL_CONFIG_PATH=%~dp0config\maintenance-config.json"

if exist "!LOCAL_SCRIPT_PATH!" if exist "!LOCAL_CONFIG_PATH!" (
    echo [INFO] Local modular files detected - using enhanced architecture
    set "USE_LOCAL_FILES=true"
) else (
    echo [INFO] Local modular files not found - will download repository
    set "USE_LOCAL_FILES=false"
)

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

REM Verify PowerShell availability
powershell -Command "exit 0" >nul 2>&1
if !errorLevel! neq 0 (
    echo [ERROR] PowerShell is not available
    set /a ERROR_COUNT+=1
    goto cleanup
)

REM Check PowerShell execution policy
for /f "tokens=*" %%e in ('powershell -Command "Get-ExecutionPolicy"') do set "PS_EXEC_POLICY=%%e"
echo [INFO] PowerShell execution policy: !PS_EXEC_POLICY!

echo [OK] System requirements check passed

echo.
echo ========================================
echo Step 2: WinGet Dependencies Installation
echo ========================================

call :CHECK_DEPENDENCIES
if %errorLevel% neq 0 (
    echo [ERROR] Dependency check failed
    set /a ERROR_COUNT+=1
    goto cleanup
)

echo.
echo ========================================
echo Step 3: PowerShell 7 Installation
echo ========================================

REM Check for PowerShell 7
where pwsh >nul 2>&1
if %errorLevel% equ 0 (
    echo [OK] PowerShell 7 already installed
    set "PS7_INSTALLED=true"
    set "PWSH_CMD=pwsh"
) else (
    call :check_ps7_paths
    if "!PS7_INSTALLED!"=="false" (
        echo [INSTALL] Installing PowerShell 7...
        call :install_powershell7
    )
)

echo.
echo ========================================
echo Step 4: Scheduled Task & Restart Check
echo ========================================

call :check_scheduled_task_and_restart

echo.
echo ========================================
echo Step 5: Maintenance Script Setup
echo ========================================

if "!USE_LOCAL_FILES!"=="true" (
    call :run_local_maintenance_script
) else (
    call :download_maintenance_script
    call :run_maintenance_script
)

goto cleanup

REM ========================================
REM FUNCTION DEFINITIONS
REM ========================================

:CHECK_DEPENDENCIES
echo [INFO] Checking for required dependencies...

REM Check for WinGet
where winget >nul 2>&1
if %errorLevel% neq 0 (
    echo [INFO] WinGet not found, installing...
    call :check_vclibs
    call :check_xaml
    call :install_winget
    if %errorLevel% neq 0 (
        echo [ERROR] Failed to install WinGet
        exit /b 1
    )
) else (
    echo [OK] WinGet already installed
    set "WINGET_INSTALLED=true"
)

echo [INFO] All dependencies checked
exit /b 0

:check_vclibs
echo [CHECK] Microsoft.VCLibs installation...
powershell -Command "try { $packages = Get-AppxPackage -Name 'Microsoft.VCLibs*'; if ($packages -and ($packages | Where-Object {[version]$_.Version -ge '14.0'})) { exit 0 } else { exit 1 } } catch { exit 1 }" >nul 2>&1
if !errorLevel! equ 0 (
    echo [OK] Microsoft.VCLibs 14.0+ is installed
    set "VCLIBS_INSTALLED=true"
) else (
    echo [INSTALL] Microsoft.VCLibs not found, installing...
    call :install_vclibs
)
goto :eof

:install_vclibs
cd /d "!TEMP_DIR!"
echo [DOWNLOAD] Microsoft.VCLibs.x64.14.00.Desktop.appx...
powershell -NoProfile -Command "try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; $ProgressPreference = 'SilentlyContinue'; Invoke-WebRequest -Uri 'https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx' -OutFile 'VCLibs.appx' -UseBasicParsing; exit 0 } catch { Write-Host '[ERROR] Download failed:' $_.Exception.Message; exit 1 }"

if exist "VCLibs.appx" (
    echo [INSTALL] Installing Microsoft.VCLibs...
    powershell -NoProfile -Command "try { Add-AppxPackage -Path 'VCLibs.appx'; exit 0 } catch { Write-Host '[ERROR] Installation failed:' $_.Exception.Message; exit 1 }"
    if !errorLevel! equ 0 (
        echo [OK] VCLibs installed successfully
        set "VCLIBS_INSTALLED=true"
        del "VCLibs.appx" >nul 2>&1
    ) else (
        echo [ERROR] VCLibs installation failed
        set /a ERROR_COUNT+=1
    )
) else (
    echo [ERROR] Failed to download VCLibs
    set /a ERROR_COUNT+=1
)
goto :eof

:check_xaml
echo [CHECK] Microsoft.UI.Xaml installation...
powershell -Command "try { $packages = Get-AppxPackage -Name 'Microsoft.UI.Xaml*'; if ($packages -and ($packages | Where-Object {[version]$_.Version -ge '2.7'})) { exit 0 } else { exit 1 } } catch { exit 1 }" >nul 2>&1
if !errorLevel! equ 0 (
    echo [OK] Microsoft.UI.Xaml 2.7+ is installed
    set "XAML_INSTALLED=true"
) else (
    echo [INSTALL] Microsoft.UI.Xaml not found, installing...
    call :install_xaml
)
goto :eof

:install_xaml
cd /d "!TEMP_DIR!"
echo [DOWNLOAD] Microsoft.UI.Xaml 2.8...
powershell -NoProfile -Command "try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; $ProgressPreference = 'SilentlyContinue'; Invoke-WebRequest -Uri 'https://www.nuget.org/api/v2/package/Microsoft.UI.Xaml/2.8.6' -OutFile 'xaml.zip' -UseBasicParsing; Expand-Archive -Path 'xaml.zip' -DestinationPath 'xaml' -Force; Copy-Item 'xaml\tools\AppX\x64\Release\Microsoft.UI.Xaml.2.8.appx' -Destination 'Microsoft.UI.Xaml.2.8.appx'; exit 0 } catch { Write-Host '[ERROR] Download/extract failed:' $_.Exception.Message; exit 1 }"

if exist "Microsoft.UI.Xaml.2.8.appx" (
    echo [INSTALL] Installing Microsoft.UI.Xaml...
    powershell -NoProfile -Command "try { Add-AppxPackage -Path 'Microsoft.UI.Xaml.2.8.appx'; exit 0 } catch { Write-Host '[ERROR] Installation failed:' $_.Exception.Message; exit 1 }"
    if !errorLevel! equ 0 (
        echo [OK] UI.Xaml installed successfully
        set "XAML_INSTALLED=true"
        rmdir /s /q "xaml" >nul 2>&1
        del "xaml.zip" >nul 2>&1
        del "Microsoft.UI.Xaml.2.8.appx" >nul 2>&1
    ) else (
        echo [ERROR] UI.Xaml installation failed
        set /a ERROR_COUNT+=1
    )
) else (
    echo [ERROR] Failed to download/extract UI.Xaml
    set /a ERROR_COUNT+=1
)
goto :eof

:install_winget
cd /d "!TEMP_DIR!"
echo [CHECK] WinGet (App Installer) installation...
powershell -Command "try { $packages = Get-AppxPackage -Name 'Microsoft.DesktopAppInstaller'; if ($packages) { exit 0 } else { exit 1 } } catch { exit 1 }" >nul 2>&1
if !errorLevel! equ 0 (
    echo [OK] WinGet already installed
    set "WINGET_INSTALLED=true"
    goto :eof
)

echo [DOWNLOAD] WinGet (App Installer)...
powershell -NoProfile -Command "try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; $ProgressPreference = 'SilentlyContinue'; $response = Invoke-RestMethod -Uri 'https://api.github.com/repos/microsoft/winget-cli/releases/latest'; $downloadUrl = ($response.assets | Where-Object { $_.name -like '*msixbundle' }).browser_download_url; Invoke-WebRequest -Uri $downloadUrl -OutFile 'Microsoft.DesktopAppInstaller.msixbundle' -UseBasicParsing; exit 0 } catch { Write-Host '[ERROR] Download failed:' $_.Exception.Message; exit 1 }"

if exist "Microsoft.DesktopAppInstaller.msixbundle" (
    echo [INSTALL] Installing WinGet...
    powershell -NoProfile -Command "try { Add-AppxPackage -Path 'Microsoft.DesktopAppInstaller.msixbundle'; exit 0 } catch { Write-Host '[ERROR] Installation failed:' $_.Exception.Message; exit 1 }"
    if !errorLevel! equ 0 (
        echo [OK] WinGet installed successfully
        set "WINGET_INSTALLED=true"
        del "Microsoft.DesktopAppInstaller.msixbundle" >nul 2>&1
        
        REM Wait for WinGet to be available
        echo [WAIT] Waiting for WinGet to initialize...
        timeout /t 5 /nobreak >nul
        
        REM Verify WinGet is working
        winget --version >nul 2>&1
        if !errorLevel! equ 0 (
            echo [OK] WinGet is working
        ) else (
            echo [WARNING] WinGet installation may need a restart to work properly
        )
    ) else (
        echo [ERROR] WinGet installation failed
        set /a ERROR_COUNT+=1
    )
) else (
    echo [ERROR] Failed to download WinGet
    set /a ERROR_COUNT+=1
)
goto :eof

:check_ps7_paths
echo [CHECK] Checking PowerShell 7 installation paths...
set "PWSH_CMD="

REM Common PowerShell 7 installation paths
set "PS7_PATHS=%ProgramFiles%\PowerShell\7\pwsh.exe;%LocalAppData%\Microsoft\WindowsApps\pwsh.exe;%ProgramFiles(x86)%\PowerShell\7\pwsh.exe"

for %%p in (%PS7_PATHS:;= %) do (
    if exist "%%p" (
        echo [OK] Found PowerShell 7 at: %%p
        set "PWSH_CMD=%%p"
        set "PS7_INSTALLED=true"
        goto ps7_found
    )
)

echo [INFO] PowerShell 7 not found in standard paths
set "PS7_INSTALLED=false"
goto :eof

:ps7_found
echo [OK] PowerShell 7 is available
goto :eof

:install_powershell7
echo [INSTALL] Installing PowerShell 7...

REM Try WinGet first if available
winget --version >nul 2>&1
if !errorLevel! equ 0 (
    echo [INSTALL] Using WinGet to install PowerShell 7...
    winget install --id Microsoft.PowerShell --silent --accept-package-agreements --accept-source-agreements >nul 2>&1
    if !errorLevel! equ 0 (
        echo [OK] PowerShell 7 installed via WinGet
        set "PS7_INSTALLED=true"
        set "PWSH_CMD=pwsh"
        goto :eof
    ) else (
        echo [WARNING] WinGet installation failed, trying manual download...
    )
)

REM Manual installation
cd /d "!TEMP_DIR!"

REM Detect architecture
set "ARCH=x64"
if "%PROCESSOR_ARCHITECTURE%"=="x86" if not defined PROCESSOR_ARCHITEW6432 set "ARCH=x86"

echo [DOWNLOAD] PowerShell 7 manually...

REM Download PowerShell 7.4.6 installer
set "PS7_VERSION=7.4.6"
powershell -NoProfile -Command "try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; $ProgressPreference = 'SilentlyContinue'; $arch = '%ARCH%'; $version = '7.4.6'; $url = \"https://github.com/PowerShell/PowerShell/releases/download/v$version/PowerShell-$version-win-$arch.msi\"; Invoke-WebRequest -Uri $url -OutFile \"PowerShell-7-win-$arch.msi\" -UseBasicParsing; exit 0 } catch { Write-Host '[ERROR] Download failed:' $_.Exception.Message; exit 1 }"

if exist "PowerShell-7-win-!ARCH!.msi" (
    echo [INSTALL] Installing PowerShell 7 (!ARCH!)...
    msiexec /i "PowerShell-7-win-!ARCH!.msi" /quiet /norestart
    if !errorLevel! equ 0 (
        echo [OK] PowerShell 7 installed successfully
        set "PS7_INSTALLED=true"
        
        REM Update PATH and check
        call refreshenv >nul 2>&1
        where pwsh >nul 2>&1
        if !errorLevel! equ 0 (
            set "PWSH_CMD=pwsh"
        ) else (
            set "PWSH_CMD=%ProgramFiles%\PowerShell\7\pwsh.exe"
        )
        
        del "PowerShell-7-win-!ARCH!.msi" >nul 2>&1
    ) else (
        echo [ERROR] PowerShell 7 installation failed
        set /a ERROR_COUNT+=1
    )
) else (
    echo [ERROR] Failed to download PowerShell 7
    set /a ERROR_COUNT+=1
)

if "!PS7_INSTALLED!"=="false" (
    echo [FALLBACK] Using Windows PowerShell instead...
    set "PWSH_CMD=powershell"
    set /a ERROR_COUNT+=1
)
goto :eof

:check_scheduled_task_and_restart
echo [CHECK] Checking for existing scheduled task...
powershell -NoProfile -Command "try { $task = Get-ScheduledTask -TaskName 'ScriptMentenantaStartup' -ErrorAction SilentlyContinue; if ($task) { Unregister-ScheduledTask -TaskName 'ScriptMentenantaStartup' -Confirm:$false; Write-Host '[REMOVED] Existing scheduled task removed'; exit 0 } else { Write-Host '[INFO] No existing scheduled task found'; exit 1 } } catch { Write-Host '[INFO] No existing scheduled task found'; exit 1 }" 2>nul
if !errorLevel! equ 0 (
    echo [OK] Removed existing scheduled task
) else (
    echo [OK] No existing scheduled task to remove
)

echo [CHECK] Checking for pending OS restarts...
powershell -NoProfile -Command "try { $restartPending = $false; if (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired' -ErrorAction SilentlyContinue) { $restartPending = $true } if (Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name 'PendingFileRenameOperations' -ErrorAction SilentlyContinue) { $restartPending = $true } if (Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending' -ErrorAction SilentlyContinue) { $restartPending = $true } if ($restartPending) { exit 0 } else { exit 1 } } catch { exit 1 }" 2>nul

if !errorLevel! equ 0 (
    echo [WARNING] Pending OS restart detected!
    echo [CREATE] Creating scheduled task to run script at startup with 1-minute delay...
    
    REM Create scheduled task with proper admin rights and 1-minute delay
    powershell -NoProfile -Command "try { $action = New-ScheduledTaskAction -Execute '%~f0'; $trigger = New-ScheduledTaskTrigger -AtStartup; $trigger.Delay = 'PT1M'; $principal = New-ScheduledTaskPrincipal -UserId 'BUILTIN\Administrators' -LogonType ServiceAccount -RunLevel Highest; $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable; Register-ScheduledTask -TaskName 'ScriptMentenantaStartup' -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description 'Windows Maintenance Script - Auto-restart continuation'; Write-Host '[OK] Scheduled task created successfully'; exit 0 } catch { Write-Host '[ERROR] Failed to create scheduled task:' $_.Exception.Message; exit 1 }"
    
    if !errorLevel! equ 0 (
        echo [OK] Scheduled task created successfully
        echo [INFO] Task will run at next startup with 1-minute delay and admin rights
        echo [RESTART] System will restart now to apply pending changes...
        echo [INFO] After restart, this script will continue automatically
        timeout /t 10 /nobreak >nul
        shutdown /r /t 0 /c "Restarting to apply pending OS updates - Script will continue automatically"
        exit
    ) else (
        echo [ERROR] Failed to create scheduled task
        echo [WARNING] Continuing without restart - some updates may not be applied
        set /a ERROR_COUNT+=1
    )
) else (
    echo [OK] No pending OS restart detected, continuing...
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
echo [LAUNCH] Starting PowerShell with admin rights in new window...

REM Check if PowerShell 7 is available and launch it with admin rights in a new window
if "!PS7_INSTALLED!"=="true" (
    if "!PWSH_CMD!"=="pwsh" (
        echo [INFO] Using system-available PowerShell 7
        powershell -Command "Start-Process -FilePath 'pwsh' -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', '!SCRIPT_DIR!\script_mentenanta\script.ps1' -Verb RunAs"
    ) else (
        echo [INFO] Using PowerShell 7 from: !PWSH_CMD!
        powershell -Command "Start-Process -FilePath '!PWSH_CMD!' -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', '!SCRIPT_DIR!\script_mentenanta\script.ps1' -Verb RunAs"
    )
    echo [OK] PowerShell 7 launched with admin rights in new window
    echo [INFO] The maintenance script is now running in a separate window
) else (
    echo [FALLBACK] PowerShell 7 not available, using Windows PowerShell...
    powershell -Command "Start-Process -FilePath 'powershell' -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', '!SCRIPT_DIR!\script_mentenanta\script.ps1' -Verb RunAs"
    echo [OK] Windows PowerShell launched with admin rights in new window
    echo [INFO] The maintenance script is now running in a separate window
    set /a ERROR_COUNT+=1
)
goto :eof

:run_local_maintenance_script
echo [LOCAL] Using local modular maintenance script...

REM Parse command line arguments for the new modular script
set "PS_ARGS="
set "TEST_MODE="
set "GENERATE_REPORT="
set "TASK_FILTER="

:PARSE_ARGS_LOCAL
if "%~1"=="" goto :ARGS_DONE_LOCAL
if /i "%~1"=="-test" (
    set "TEST_MODE=-TestMode"
    shift
    goto :PARSE_ARGS_LOCAL
)
if /i "%~1"=="-report" (
    set "GENERATE_REPORT=-GenerateReport"
    shift
    goto :PARSE_ARGS_LOCAL
)
if /i "%~1"=="-tasks" (
    if not "%~2"=="" (
        set "TASK_FILTER=-TaskFilter @('%~2')"
        shift
        shift
        goto :PARSE_ARGS_LOCAL
    )
)
shift
goto :PARSE_ARGS_LOCAL

:ARGS_DONE_LOCAL

REM Check for PowerShell 7 first (preferred)
where pwsh >nul 2>&1
if %errorLevel% equ 0 (
    echo [INFO] PowerShell 7 detected, using pwsh.exe
    set "PS_COMMAND=pwsh"
) else (
    echo [WARNING] PowerShell 7 not found, using Windows PowerShell
    set "PS_COMMAND=powershell"
)

REM Build PowerShell command
set "PS_ARGS=-ConfigPath '!LOCAL_CONFIG_PATH!' !TEST_MODE! !GENERATE_REPORT! !TASK_FILTER!"

echo.
echo [INFO] Starting modular maintenance session...
echo [INFO] Command: !PS_COMMAND! -ExecutionPolicy Bypass -File "!LOCAL_SCRIPT_PATH!" !PS_ARGS!
echo.

REM Execute the maintenance script
!PS_COMMAND! -ExecutionPolicy Bypass -File "!LOCAL_SCRIPT_PATH!" !PS_ARGS!
set "MAINTENANCE_RESULT=%errorLevel%"

if !MAINTENANCE_RESULT! equ 0 (
    echo.
    echo [SUCCESS] Modular maintenance session completed successfully
) else (
    echo.
    echo [ERROR] Modular maintenance session failed with exit code: !MAINTENANCE_RESULT!
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
echo Local Files Used:     !USE_LOCAL_FILES!
echo Errors encountered:   !ERROR_COUNT!
echo ========================================

if !ERROR_COUNT! equ 0 (
    echo [SUCCESS] Setup completed successfully!
    echo [INFO] Your system is now ready for use.
    if "!USE_LOCAL_FILES!"=="true" (
        echo [INFO] The modular maintenance script has been executed.
    ) else (
        echo [INFO] The maintenance script has been launched in a separate window.
    )
) else (
    echo [WARNING] Setup completed with !ERROR_COUNT! error(s).
    echo [INFO] Some components may not be fully functional.
    if "!USE_LOCAL_FILES!"=="true" (
        echo [INFO] The modular maintenance script execution may have issues.
    ) else (
        echo [INFO] The maintenance script has been launched in a separate window.
    )
)

echo.
echo [INFO] For best results, run this script immediately after a fresh install of Windows 10 or 11.
echo [INFO] Always right-click and select "Run as administrator".
echo [INFO] If you see any errors, check the log and re-run the script.
echo.

echo Press any key to exit...
pause >nul
exit /b !ERROR_COUNT!
