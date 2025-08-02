@echo off
chcp 65001 >nul 2>&1 || chcp 850 >nul 2>&1
setlocal enabledelayedexpansion

echo ========================================
echo Windows Fresh Install Setup Script
echo Setting up WinGet, PowerShell 7, and maintenance tools
echo ========================================

REM ========================================
REM Windows 10/11 Compatibility & Reliability Enhancements
REM ========================================
ver | findstr /i "10.0.\|11.0." >nul 2>&1
if !errorLevel! neq 0 (
    echo [ERROR] This script is designed for Windows 10 or 11 only.
    pause
    exit /b 1
)

REM Check if running as administrator
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo [ADMIN] Requesting administrator privileges...
    echo [INFO] This window will close and reopen with admin rights...
    powershell -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit
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

REM Check PowerShell execution policy
for /f "tokens=*" %%e in ('powershell -Command "Get-ExecutionPolicy"') do set "PS_EXEC_POLICY=%%e"
echo [INFO] PowerShell execution policy: !PS_EXEC_POLICY!
if /i "!PS_EXEC_POLICY!" NEQ "Bypass" if /i "!PS_EXEC_POLICY!" NEQ "Unrestricted" (
    echo [WARN] PowerShell execution policy is not Bypass/Unrestricted. For best results, set to Bypass.
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

REM Final check for admin rights before running maintenance script
net session >nul 2>&1
if !errorLevel! neq 0 (
    echo [ERROR] Lost admin privileges before running maintenance script. Please re-run as administrator.
    exit /b 1
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

call :download_maintenance_script

echo.
echo ========================================
echo Step 6: Running Maintenance Script
echo ========================================

call :run_maintenance_script

REM ========================================
REM User Instructions for Fresh Install
REM ========================================
echo.
echo [INFO] For best results, run this script immediately after a fresh install of Windows 10 or 11.
echo [INFO] Always right-click and select "Run as administrator".
echo [INFO] If you see any errors, check the log and re-run the script.
echo.

goto cleanup

REM ========================================
REM FUNCTION DEFINITIONS
REM ========================================

:check_scheduled_task_and_restart
echo [CHECK] Checking for existing scheduled task for script.bat...
powershell -NoProfile -Command "try { $task = Get-ScheduledTask -TaskName 'ScriptMentenantaStartup' -ErrorAction SilentlyContinue; if ($task) { Unregister-ScheduledTask -TaskName 'ScriptMentenantaStartup' -Confirm:$false; Write-Host '[REMOVED] Existing scheduled task for script.bat removed'; exit 0 } else { Write-Host '[INFO] No existing scheduled task found'; exit 1 } } catch { Write-Host '[INFO] No existing scheduled task found'; exit 1 }" 2>nul
if !errorLevel! equ 0 (
    echo [OK] Removed existing scheduled task
) else (
    echo [OK] No existing scheduled task to remove
)

echo [CHECK] Checking for pending OS restarts...
powershell -NoProfile -Command "try { $restartPending = $false; if (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired' -ErrorAction SilentlyContinue) { $restartPending = $true } if (Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name 'PendingFileRenameOperations' -ErrorAction SilentlyContinue) { $restartPending = $true } if (Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending' -ErrorAction SilentlyContinue) { $restartPending = $true } if ($restartPending) { exit 0 } else { exit 1 } } catch { exit 1 }" 2>nul

if !errorLevel! equ 0 (
    echo [WARNING] Pending OS restart detected!
    echo [CREATE] Creating scheduled task to run script.bat at startup with 1-minute delay...
    
    REM Create scheduled task with proper admin rights and 1-minute delay
    powershell -NoProfile -Command "try { $action = New-ScheduledTaskAction -Execute '%~f0'; $trigger = New-ScheduledTaskTrigger -AtStartup; $trigger.Delay = 'PT1M'; $principal = New-ScheduledTaskPrincipal -UserId 'BUILTIN\Administrators' -LogonType ServiceAccount -RunLevel Highest; $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable; Register-ScheduledTask -TaskName 'ScriptMentenantaStartup' -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description 'Windows Fresh Install Setup Script - Auto-restart continuation'; Write-Host '[OK] Scheduled task created successfully'; exit 0 } catch { Write-Host '[ERROR] Failed to create scheduled task:' $_.Exception.Message; exit 1 }"
    
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
echo [LAUNCH] Starting PowerShell 7 with admin rights in new window...

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
    echo [INFO] The maintenance script has been launched in a separate window.
) else (
    echo [WARNING] Setup completed with !ERROR_COUNT! error(s).
    echo [INFO] Some components may not be fully functional.
    echo [INFO] The maintenance script has been launched in a separate window.
)

echo.
echo [INFO] This window will close automatically in 10 seconds...
echo [INFO] The maintenance script continues running in the new PowerShell window.
timeout /t 10 /nobreak >nul

exit /b !ERROR_COUNT!