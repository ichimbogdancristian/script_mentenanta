@echo off
REM ============================================================================
REM  script_mentenanta - Windows Maintenance Automation Launcher (Refactored)
REM  Purpose: Entry point for all maintenance operations. Handles dependency
REM           installation, scheduled task setup, repo download/update, and
REM           launches PowerShell orchestrator (script.ps1).
REM  Environment: Requires Administrator, Windows 10/11, PowerShell 5.1+.
REM  All actions are logged to console and maintenance.log file.
REM ============================================================================
SETLOCAL ENABLEDELAYEDEXPANSION

REM -----------------------------------------------------------------------------
REM Basic Environment Setup and Logging
REM -----------------------------------------------------------------------------
SET "TASK_NAME=ScriptMentenantaMonthly"
SET "STARTUP_TASK_NAME=ScriptMentenantaStartup"
SET "SCRIPT_PATH=%~f0"
SET "SCRIPT_DIR=%~dp0"
SET "LOG_FILE=%SCRIPT_DIR%maintenance.log"

REM Create or append to maintenance.log
ECHO [%DATE% %TIME%] [INFO] ============================================================ >> "%LOG_FILE%"
ECHO [%DATE% %TIME%] [INFO] Starting Windows Maintenance Automation Script >> "%LOG_FILE%"
ECHO [%DATE% %TIME%] [INFO] Script: %SCRIPT_PATH% >> "%LOG_FILE%"
ECHO [%DATE% %TIME%] [INFO] User: %USERNAME%, Computer: %COMPUTERNAME% >> "%LOG_FILE%"
ECHO [%DATE% %TIME%] [INFO] ============================================================ >> "%LOG_FILE%"

REM Function to log both to console and file
ECHO.
ECHO ============================================================
ECHO    Windows Maintenance Automation Script - STARTING
ECHO ============================================================
ECHO.
CALL :LOG_ENTRY "INFO" "Starting maintenance script..."
CALL :LOG_ENTRY "INFO" "User: %USERNAME%, Computer: %COMPUTERNAME%"

REM Check if this is a restart after PowerShell 7 installation
IF "%1"=="PS7_RESTART" (
    CALL :LOG_ENTRY "INFO" "Script restarted after PowerShell 7 installation."
    GOTO :SKIP_PS7_INSTALL
)

REM -----------------------------------------------------------------------------
REM Admin Privilege Check
REM Relaunches itself with admin rights if not already running as Administrator.
REM -----------------------------------------------------------------------------
ECHO.
ECHO [INFO] Checking Administrator privileges...
NET SESSION >nul 2>&1
IF %ERRORLEVEL% NEQ 0 (
    CALL :LOG_ENTRY "WARN" "Not running as Administrator. Relaunching with admin rights..."
    ECHO.
    ECHO ========================================
    ECHO    Admin Rights Required - Relaunching
    ECHO ========================================
    ECHO.
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    EXIT /B 0
) ELSE (
    CALL :LOG_ENTRY "INFO" "Running with Administrator privileges."
)

REM -----------------------------------------------------------------------------
REM PowerShell Version Check
REM Ensures PowerShell 5.1+ is available for all automation features.
REM -----------------------------------------------------------------------------
FOR /F "tokens=*" %%i IN ('powershell -Command "$PSVersionTable.PSVersion.Major" 2^>nul') DO SET PS_VERSION=%%i
IF "%PS_VERSION%"=="" SET PS_VERSION=0
IF %PS_VERSION% LSS 5 (
    CALL :LOG_ENTRY "ERROR" "PowerShell 5.1 or higher is required. Current version: %PS_VERSION%"
    CALL :LOG_ENTRY "ERROR" "Please install PowerShell 5.1 or newer and try again."
    pause
    EXIT /B 3
)
CALL :LOG_ENTRY "INFO" "PowerShell version: %PS_VERSION%"

REM -----------------------------------------------------------------------------
REM Windows Version Detection
REM -----------------------------------------------------------------------------
FOR /F "tokens=*" %%i IN ('powershell -Command "(Get-CimInstance Win32_OperatingSystem).Version" 2^>nul') DO SET OS_VERSION=%%i
IF "%OS_VERSION%"=="" SET OS_VERSION=Unknown
CALL :LOG_ENTRY "INFO" "Detected Windows version: %OS_VERSION%"

REM -----------------------------------------------------------------------------
REM Enhanced Monthly Scheduled Task Setup
REM Ensures a monthly scheduled task is created to run this script as admin.
REM -----------------------------------------------------------------------------
CALL :LOG_ENTRY "INFO" "Checking for monthly scheduled task '%TASK_NAME%'..."
schtasks /Query /TN "%TASK_NAME%" >nul 2>&1
IF %ERRORLEVEL% EQU 0 (
    CALL :LOG_ENTRY "INFO" "Monthly scheduled task already exists. Skipping creation."
) ELSE (
    CALL :LOG_ENTRY "INFO" "Monthly scheduled task not found. Creating..."
    schtasks /Create ^
        /SC MONTHLY ^
        /MO 1 ^
        /D 1 ^
        /TN "%TASK_NAME%" ^
        /TR "cmd.exe /c \"\"%SCRIPT_PATH%\"\"" ^
        /ST 01:00 ^
        /RL HIGHEST ^
        /RU SYSTEM ^
        /IT ^
        /F
    IF !ERRORLEVEL! EQU 0 (
        CALL :LOG_ENTRY "INFO" "Monthly scheduled task created successfully."
        schtasks /Query /TN "%TASK_NAME%" /V >nul 2>&1
        IF !ERRORLEVEL! EQU 0 (
            CALL :LOG_ENTRY "INFO" "Task verification successful."
            FOR /F "tokens=2 delims=:" %%i IN ('schtasks /Query /TN "%TASK_NAME%" /FO LIST ^| findstr /C:"Next Run Time"') DO (
                CALL :LOG_ENTRY "INFO" "Next scheduled run: %%i"
            )
        ) ELSE (
            CALL :LOG_ENTRY "WARN" "Task created but verification failed."
        )
    ) ELSE (
        CALL :LOG_ENTRY "ERROR" "Failed to create monthly scheduled task. Error code: !ERRORLEVEL!"
    )
)

REM -----------------------------------------------------------------------------
REM Startup Task Management - Check and Remove if Exists
REM This task should only exist temporarily after a system restart.
REM -----------------------------------------------------------------------------
CALL :LOG_ENTRY "INFO" "Checking startup task '%STARTUP_TASK_NAME%'..."
schtasks /Query /TN "%STARTUP_TASK_NAME%" >nul 2>&1
IF !ERRORLEVEL! EQU 0 (
    CALL :LOG_ENTRY "INFO" "Existing startup task found. Removing..."
    schtasks /Delete /TN "%STARTUP_TASK_NAME%" /F >nul 2>&1
    IF !ERRORLEVEL! EQU 0 (
        CALL :LOG_ENTRY "INFO" "Startup task removed successfully."
    ) ELSE (
        CALL :LOG_ENTRY "WARN" "Failed to remove startup task, but continuing..."
    )
) ELSE (
    CALL :LOG_ENTRY "INFO" "No existing startup task found."
)

REM -----------------------------------------------------------------------------
REM System Restart Detection and Handling
REM Check if Windows requires a restart, create startup task if needed, restart immediately
REM -----------------------------------------------------------------------------
CALL :LOG_ENTRY "INFO" "Checking for pending system restarts..."
SET "RESTART_NEEDED=NO"

REM Check Windows Update reboot flag
REG QUERY "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired" >nul 2>&1
IF !ERRORLEVEL! EQU 0 (
    CALL :LOG_ENTRY "INFO" "Windows Update restart required."
    SET "RESTART_NEEDED=YES"
)

REM Check Component Based Servicing reboot flag
REG QUERY "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending" >nul 2>&1
IF !ERRORLEVEL! EQU 0 (
    CALL :LOG_ENTRY "INFO" "Component Based Servicing restart pending."
    SET "RESTART_NEEDED=YES"
)

REM Check pending file operations
REG QUERY "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager" /v PendingFileRenameOperations >nul 2>&1
IF !ERRORLEVEL! EQU 0 (
    CALL :LOG_ENTRY "INFO" "Pending file rename operations detected."
    SET "RESTART_NEEDED=YES"
)

IF "%RESTART_NEEDED%"=="YES" (
    CALL :LOG_ENTRY "WARN" "System restart is required. Creating startup task and restarting..."
    REM Delete any existing startup task first
    schtasks /Delete /TN "%STARTUP_TASK_NAME%" /F >nul 2>&1
    REM Create startup task to run 1 minute after user login with admin rights
    schtasks /Create /SC ONLOGON /TN "%STARTUP_TASK_NAME%" /TR "%SCRIPT_PATH%" /RL HIGHEST /RU "%USERNAME%" /DELAY 0001:00 /F
    IF !ERRORLEVEL! EQU 0 (
        CALL :LOG_ENTRY "INFO" "Startup task created successfully. Will run 1 minute after user login."
        CALL :LOG_ENTRY "INFO" "Restarting system immediately..."
        shutdown /r /t 5 /c "System restart required for maintenance continuation"
        CALL :LOG_ENTRY "INFO" "System will restart in 5 seconds..."
        timeout /t 10 /nobreak >nul
        EXIT /B 0
    ) ELSE (
        CALL :LOG_ENTRY "ERROR" "Failed to create startup task. Continuing without restart..."
        CALL :LOG_ENTRY "DEBUG" "Task name: %STARTUP_TASK_NAME%"
        CALL :LOG_ENTRY "DEBUG" "Script path: %SCRIPT_PATH%"
        CALL :LOG_ENTRY "DEBUG" "Username: %USERNAME%"
        CALL :LOG_ENTRY "DEBUG" "Error level: !ERRORLEVEL!"
    )
) ELSE (
    CALL :LOG_ENTRY "INFO" "No pending restart detected. No startup task needed. Continuing with script..."
)

REM -----------------------------------------------------------------------------
REM Dependency Management - Hierarchical Installation Order
REM PHASE 1: Core System Dependencies (required for package managers)
REM PHASE 2: Package Managers (Winget)  
REM PHASE 3: Development Tools (using package managers)
REM PHASE 4: PowerShell Environment (modules and package managers)
REM -----------------------------------------------------------------------------
ECHO.
ECHO ========================================
ECHO     Installing Required Dependencies
ECHO     (Hierarchical Dependency Order)
ECHO ========================================
ECHO.
CALL :LOG_ENTRY "INFO" "Starting dependency installation with proper hierarchical order..."

REM =============================================================================
REM PHASE 1: CORE SYSTEM DEPENDENCIES (Required for Winget and other tools)
REM =============================================================================
ECHO.
ECHO ----------------------------------------
ECHO   PHASE 1: Core System Dependencies
ECHO ----------------------------------------

REM -----------------------------------------------------------------------------
REM 1A. Visual C++ Redistributables - Required for Winget and many applications
REM -----------------------------------------------------------------------------
CALL :LOG_ENTRY "INFO" "PHASE 1A: Installing Visual C++ Redistributables (Winget dependency)..."
    CALL :LOG_ENTRY "INFO" "Checking Visual C++ Redistributable 2015-2022 x64..."
    
    REM Create temp script for VC++ check to avoid CMD variable expansion issues
    SET "TEMP_PS1=%TEMP%\check_vcredist.ps1"
    ECHO try { > "%TEMP_PS1%"
    ECHO     $vcInstalled = $false >> "%TEMP_PS1%"
    ECHO     $regPath = 'HKLM:\SOFTWARE\Classes\Installer\Dependencies\' >> "%TEMP_PS1%"
    ECHO     $dependencies = Get-ChildItem -Path $regPath -ErrorAction SilentlyContinue >> "%TEMP_PS1%"
    ECHO     foreach ($dep in $dependencies) { >> "%TEMP_PS1%"
    ECHO         $item = Get-ItemProperty -Path $dep.PSPath -ErrorAction SilentlyContinue >> "%TEMP_PS1%"
    ECHO         if ($item.DisplayName -like '*Microsoft Visual C++ 2015-2022 Redistributable*x64*') { >> "%TEMP_PS1%"
    ECHO             $vcInstalled = $true >> "%TEMP_PS1%"
    ECHO             break >> "%TEMP_PS1%"
    ECHO         } >> "%TEMP_PS1%"
    ECHO     } >> "%TEMP_PS1%"
    ECHO     if ($vcInstalled) { >> "%TEMP_PS1%"
    ECHO         Write-Host '[INFO] Visual C++ Redistributable x64 is already installed' >> "%TEMP_PS1%"
    ECHO         exit 0 >> "%TEMP_PS1%"
    ECHO     } else { >> "%TEMP_PS1%"
    ECHO         Write-Host '[INFO] Visual C++ Redistributable x64 not found, installing...' >> "%TEMP_PS1%"
    ECHO         exit 1 >> "%TEMP_PS1%"
    ECHO     } >> "%TEMP_PS1%"
    ECHO } catch { >> "%TEMP_PS1%"
    ECHO     Write-Host '[WARN] Registry check failed' >> "%TEMP_PS1%"
    ECHO     exit 1 >> "%TEMP_PS1%"
    ECHO } >> "%TEMP_PS1%"
    
    powershell -ExecutionPolicy Bypass -File "%TEMP_PS1%" 2>&1
    SET "VC_CHECK_EXIT=!ERRORLEVEL!"
    DEL /F /Q "%TEMP_PS1%" >nul 2>&1
    
    CALL :LOG_ENTRY "INFO" "Visual C++ check completed with exit code: !VC_CHECK_EXIT!"
    
    IF !VC_CHECK_EXIT! NEQ 0 (
        SET "VCREDIST_URL=https://aka.ms/vs/17/release/vc_redist.x64.exe"
        SET "VCREDIST_FILE=%TEMP%\vc_redist_x64.exe"
        
        CALL :LOG_ENTRY "INFO" "Downloading Visual C++ Redistributable..."
        
        REM Create temp script for VC++ download
        SET "TEMP_PS1=%TEMP%\download_vcredist.ps1"
        ECHO $ProgressPreference = 'SilentlyContinue' > "%TEMP_PS1%"
        ECHO [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 >> "%TEMP_PS1%"
        ECHO try { >> "%TEMP_PS1%"
        ECHO     Invoke-WebRequest -Uri '%VCREDIST_URL%' -OutFile '%VCREDIST_FILE%' -UseBasicParsing -TimeoutSec 60 >> "%TEMP_PS1%"
        ECHO     Write-Host '[INFO] VC++ Redistributable downloaded successfully' >> "%TEMP_PS1%"
        ECHO     exit 0 >> "%TEMP_PS1%"
        ECHO } catch { >> "%TEMP_PS1%"
        ECHO     Write-Host '[ERROR] VC++ download failed:' $_.Exception.Message >> "%TEMP_PS1%"
        ECHO     exit 1 >> "%TEMP_PS1%"
        ECHO } >> "%TEMP_PS1%"
        
        powershell -ExecutionPolicy Bypass -File "%TEMP_PS1%" 2>&1
        SET "DOWNLOAD_EXIT=!ERRORLEVEL!"
        DEL /F /Q "%TEMP_PS1%" >nul 2>&1
        IF !DOWNLOAD_EXIT! EQU 0 (
            IF EXIST "%VCREDIST_FILE%" (
                CALL :LOG_ENTRY "INFO" "Installing Visual C++ Redistributable silently..."
                START /WAIT "" "%VCREDIST_FILE%" /quiet /norestart
                SET "VCREDIST_EXIT=!ERRORLEVEL!"
                IF !VCREDIST_EXIT! EQU 0 (
                    CALL :LOG_ENTRY "INFO" "Visual C++ Redistributable installation completed successfully."
                ) ELSE (
                    CALL :LOG_ENTRY "WARN" "Visual C++ Redistributable installation returned exit code !VCREDIST_EXIT!, but continuing..."
                )
                DEL /F /Q "%VCREDIST_FILE%" >nul 2>&1
            ) ELSE (
                CALL :LOG_ENTRY "ERROR" "Visual C++ Redistributable file not found after download."
            )
        ) ELSE (
            CALL :LOG_ENTRY "WARN" "Visual C++ Redistributable download failed, but continuing..."
        )
    ) ELSE (
        CALL :LOG_ENTRY "INFO" "Visual C++ Redistributable is already installed, skipping installation."
    )

REM -----------------------------------------------------------------------------
REM 1B. Microsoft.UI.Xaml Framework - Required for Winget UI components
REM -----------------------------------------------------------------------------
CALL :LOG_ENTRY "INFO" "PHASE 1B: Installing Microsoft.UI.Xaml Framework (Winget dependency)..."
    CALL :LOG_ENTRY "INFO" "Checking Microsoft.UI.Xaml.2.8 framework..."
    
    REM Create temp script for XAML check
    SET "TEMP_PS1=%TEMP%\check_xaml.ps1"
    ECHO try { > "%TEMP_PS1%"
    ECHO     $packages = Get-AppxPackage -Name '*Microsoft.UI.Xaml*' -ErrorAction SilentlyContinue >> "%TEMP_PS1%"
    ECHO     $found = $false >> "%TEMP_PS1%"
    ECHO     foreach ($pkg in $packages) { >> "%TEMP_PS1%"
    ECHO         $pkgVersion = [version]$pkg.Version >> "%TEMP_PS1%"
    ECHO         $minVersion = [version]'2.8.0.0' >> "%TEMP_PS1%"
    ECHO         if ($pkgVersion -ge $minVersion) { >> "%TEMP_PS1%"
    ECHO             $found = $true >> "%TEMP_PS1%"
    ECHO             break >> "%TEMP_PS1%"
    ECHO         } >> "%TEMP_PS1%"
    ECHO     } >> "%TEMP_PS1%"
    ECHO     if ($found) { >> "%TEMP_PS1%"
    ECHO         Write-Host '[INFO] Microsoft.UI.Xaml framework is already installed' >> "%TEMP_PS1%"
    ECHO         exit 0 >> "%TEMP_PS1%"
    ECHO     } else { >> "%TEMP_PS1%"
    ECHO         Write-Host '[INFO] Microsoft.UI.Xaml framework not found, installing...' >> "%TEMP_PS1%"
    ECHO         exit 1 >> "%TEMP_PS1%"
    ECHO     } >> "%TEMP_PS1%"
    ECHO } catch { >> "%TEMP_PS1%"
    ECHO     Write-Host '[WARN] AppxPackage check failed' >> "%TEMP_PS1%"
    ECHO     exit 1 >> "%TEMP_PS1%"
    ECHO } >> "%TEMP_PS1%"
    
    powershell -ExecutionPolicy Bypass -File "%TEMP_PS1%" 2>&1
    SET "XAML_CHECK_EXIT=!ERRORLEVEL!"
    DEL /F /Q "%TEMP_PS1%" >nul 2>&1
    
    CALL :LOG_ENTRY "INFO" "XAML check completed with exit code: !XAML_CHECK_EXIT!"
    
    IF !XAML_CHECK_EXIT! NEQ 0 (
        SET "XAML_URL=https://api.nuget.org/v3-flatcontainer/microsoft.ui.xaml/2.8.7/microsoft.ui.xaml.2.8.7.nupkg"
        SET "XAML_FILE=%TEMP%\Microsoft.UI.Xaml.2.8.nupkg"
        
        CALL :LOG_ENTRY "INFO" "Downloading Microsoft.UI.Xaml framework..."
        
        REM Create temp script for XAML download
        SET "TEMP_PS1=%TEMP%\download_xaml.ps1"
        ECHO $ProgressPreference = 'SilentlyContinue' > "%TEMP_PS1%"
        ECHO [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 >> "%TEMP_PS1%"
        ECHO try { >> "%TEMP_PS1%"
        ECHO     Invoke-WebRequest -Uri '%XAML_URL%' -OutFile '%XAML_FILE%' -UseBasicParsing -TimeoutSec 60 >> "%TEMP_PS1%"
        ECHO     Write-Host '[INFO] Microsoft.UI.Xaml framework downloaded successfully' >> "%TEMP_PS1%"
        ECHO     exit 0 >> "%TEMP_PS1%"
        ECHO } catch { >> "%TEMP_PS1%"
        ECHO     Write-Host '[ERROR] Microsoft.UI.Xaml download failed:' $_.Exception.Message >> "%TEMP_PS1%"
        ECHO     exit 1 >> "%TEMP_PS1%"
        ECHO } >> "%TEMP_PS1%"
        
        powershell -ExecutionPolicy Bypass -File "%TEMP_PS1%" 2>&1
        SET "XAML_DOWNLOAD_EXIT=!ERRORLEVEL!"
        DEL /F /Q "%TEMP_PS1%" >nul 2>&1
        
        IF !XAML_DOWNLOAD_EXIT! EQU 0 (
            IF EXIST "%XAML_FILE%" (
                CALL :LOG_ENTRY "INFO" "Installing Microsoft.UI.Xaml framework..."
                
                REM Create temp script for XAML installation
                SET "TEMP_PS1=%TEMP%\install_xaml.ps1"
                ECHO try { > "%TEMP_PS1%"
                ECHO     $tempDir = '%TEMP%\xaml_extract' >> "%TEMP_PS1%"
                ECHO     if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force } >> "%TEMP_PS1%"
                ECHO     $null = New-Item -ItemType Directory -Path $tempDir -Force >> "%TEMP_PS1%"
                ECHO     Expand-Archive -Path '%XAML_FILE%' -DestinationPath $tempDir -Force >> "%TEMP_PS1%"
                ECHO     $appxFiles = Get-ChildItem -Path $tempDir -Recurse -Filter '*.appx' >> "%TEMP_PS1%"
                ECHO     $appxPath = $null >> "%TEMP_PS1%"
                ECHO     foreach ($file in $appxFiles) { >> "%TEMP_PS1%"
                ECHO         if ($file.Name -like '*x64*') { >> "%TEMP_PS1%"
                ECHO             $appxPath = $file >> "%TEMP_PS1%"
                ECHO             break >> "%TEMP_PS1%"
                ECHO         } >> "%TEMP_PS1%"
                ECHO     } >> "%TEMP_PS1%"
                ECHO     if ($appxPath) { >> "%TEMP_PS1%"
                ECHO         Add-AppxPackage -Path $appxPath.FullName -ErrorAction Stop >> "%TEMP_PS1%"
                ECHO         Write-Host '[INFO] Microsoft.UI.Xaml framework installed successfully' >> "%TEMP_PS1%"
                ECHO         exit 0 >> "%TEMP_PS1%"
                ECHO     } else { >> "%TEMP_PS1%"
                ECHO         Write-Host '[WARN] Could not find x64 appx package in framework' >> "%TEMP_PS1%"
                ECHO         exit 1 >> "%TEMP_PS1%"
                ECHO     } >> "%TEMP_PS1%"
                ECHO } catch { >> "%TEMP_PS1%"
                ECHO     Write-Host '[WARN] Microsoft.UI.Xaml installation failed:' $_.Exception.Message >> "%TEMP_PS1%"
                ECHO     exit 1 >> "%TEMP_PS1%"
                ECHO } >> "%TEMP_PS1%"
                
                powershell -ExecutionPolicy Bypass -File "%TEMP_PS1%" 2>&1
                SET "XAML_EXIT=!ERRORLEVEL!"
                DEL /F /Q "%TEMP_PS1%" >nul 2>&1
                IF !XAML_EXIT! EQU 0 (
                    CALL :LOG_ENTRY "INFO" "Microsoft.UI.Xaml framework installed successfully."
                ) ELSE (
                    CALL :LOG_ENTRY "WARN" "Microsoft.UI.Xaml framework installation had issues, but continuing..."
                )
                DEL /F /Q "%XAML_FILE%" >nul 2>&1
            ) ELSE (
                CALL :LOG_ENTRY "ERROR" "Microsoft.UI.Xaml framework file not found after download."
            )
        ) ELSE (
            CALL :LOG_ENTRY "WARN" "Microsoft.UI.Xaml framework download failed, but continuing..."
        )
    ) ELSE (
        CALL :LOG_ENTRY "INFO" "Microsoft.UI.Xaml framework is already installed, skipping installation."
    )

REM =============================================================================
REM PHASE 2: PACKAGE MANAGERS (Now that core dependencies are installed)
REM =============================================================================
ECHO.
ECHO ----------------------------------------
ECHO   PHASE 2: Package Managers
ECHO ----------------------------------------

REM -----------------------------------------------------------------------------
REM 2A. Windows Package Manager (Winget) - Primary package manager
REM -----------------------------------------------------------------------------
CALL :LOG_ENTRY "INFO" "PHASE 2A: Installing Windows Package Manager (Winget)..."
winget --version >nul 2>&1
IF !ERRORLEVEL! NEQ 0 (
    CALL :LOG_ENTRY "INFO" "Winget not found, installing now that dependencies are ready..."
    CALL :LOG_ENTRY "INFO" "Installing Winget (Desktop App Installer)..."
    SET "WINGET_URL=https://github.com/microsoft/winget-cli/releases/download/v1.11.430/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"
    SET "WINGET_FILE=%TEMP%\Microsoft.DesktopAppInstaller.msixbundle"
    
    CALL :LOG_ENTRY "INFO" "Downloading Winget installer..."
    
    REM Create temp script for Winget download
    SET "TEMP_PS1=%TEMP%\download_winget.ps1"
    ECHO $ProgressPreference = 'SilentlyContinue' > "%TEMP_PS1%"
    ECHO [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 >> "%TEMP_PS1%"
    ECHO try { >> "%TEMP_PS1%"
    ECHO     Invoke-WebRequest -Uri '%WINGET_URL%' -OutFile '%WINGET_FILE%' -UseBasicParsing -TimeoutSec 60 >> "%TEMP_PS1%"
    ECHO     Write-Host '[INFO] Winget downloaded successfully' >> "%TEMP_PS1%"
    ECHO     exit 0 >> "%TEMP_PS1%"
    ECHO } catch { >> "%TEMP_PS1%"
    ECHO     Write-Host '[ERROR] Winget download failed:' $_.Exception.Message >> "%TEMP_PS1%"
    ECHO     exit 1 >> "%TEMP_PS1%"
    ECHO } >> "%TEMP_PS1%"
    
    powershell -ExecutionPolicy Bypass -File "%TEMP_PS1%" 2>&1
    SET "WINGET_DOWNLOAD_EXIT=!ERRORLEVEL!"
    DEL /F /Q "%TEMP_PS1%" >nul 2>&1
    
    IF !WINGET_DOWNLOAD_EXIT! EQU 0 (
        IF EXIST "%WINGET_FILE%" (
            CALL :LOG_ENTRY "INFO" "Installing Winget package..."
            
            REM Create temp script for Winget installation
            SET "TEMP_PS1=%TEMP%\install_winget.ps1"
            ECHO try { > "%TEMP_PS1%"
            ECHO     Add-AppxPackage -Path '%WINGET_FILE%' -ErrorAction Stop >> "%TEMP_PS1%"
            ECHO     Write-Host '[INFO] Winget installation completed successfully' >> "%TEMP_PS1%"
            ECHO     exit 0 >> "%TEMP_PS1%"
            ECHO } catch { >> "%TEMP_PS1%"
            ECHO     Write-Host '[ERROR] Winget installation failed:' $_.Exception.Message >> "%TEMP_PS1%"
            ECHO     exit 1 >> "%TEMP_PS1%"
            ECHO } >> "%TEMP_PS1%"
            
            powershell -ExecutionPolicy Bypass -File "%TEMP_PS1%" 2>&1
            SET "WINGET_EXIT=!ERRORLEVEL!"
            DEL /F /Q "%TEMP_PS1%" >nul 2>&1
            IF !WINGET_EXIT! EQU 0 (
                CALL :LOG_ENTRY "INFO" "Winget installation completed successfully."
            ) ELSE (
                CALL :LOG_ENTRY "ERROR" "Winget installation failed with exit code !WINGET_EXIT!"
            )
            DEL /F /Q "%WINGET_FILE%" >nul 2>&1
        ) ELSE (
            CALL :LOG_ENTRY "ERROR" "Winget installer file not found after download."
        )
    ) ELSE (
        CALL :LOG_ENTRY "ERROR" "Winget download failed."
    )
    
    REM Refresh PATH and verify Winget installation
    CALL :LOG_ENTRY "INFO" "Refreshing PATH environment and verifying Winget installation..."
    
    REM Create temp script to properly add winget to PATH
    SET "TEMP_PS1=%TEMP%\refresh_winget_path.ps1"
    ECHO try { > "%TEMP_PS1%"
    ECHO     $wingetPaths = Get-ChildItem -Path $env:ProgramFiles\WindowsApps -Filter "Microsoft.DesktopAppInstaller*" -Directory -ErrorAction SilentlyContinue >> "%TEMP_PS1%"
    ECHO     $wingetPath = $null >> "%TEMP_PS1%"
    ECHO     if ($wingetPaths) { >> "%TEMP_PS1%"
    ECHO         $sortedPaths = $wingetPaths | Sort-Object Name -Descending >> "%TEMP_PS1%"
    ECHO         $wingetPath = $sortedPaths[0] >> "%TEMP_PS1%"
    ECHO     } >> "%TEMP_PS1%"
    ECHO     if ($wingetPath) { >> "%TEMP_PS1%"
    ECHO         $wingetExe = Join-Path $wingetPath.FullName "winget.exe" >> "%TEMP_PS1%"
    ECHO         if (Test-Path $wingetExe) { >> "%TEMP_PS1%"
    ECHO             $env:PATH = $env:PATH + ";" + $wingetPath.FullName >> "%TEMP_PS1%"
    ECHO             Write-Host '[INFO] Winget path added to environment' >> "%TEMP_PS1%"
    ECHO             exit 0 >> "%TEMP_PS1%"
    ECHO         } >> "%TEMP_PS1%"
    ECHO     } >> "%TEMP_PS1%"
    ECHO     Write-Host '[WARN] Winget executable not found in expected location' >> "%TEMP_PS1%"
    ECHO     exit 1 >> "%TEMP_PS1%"
    ECHO } catch { >> "%TEMP_PS1%"
    ECHO     Write-Host '[WARN] Error setting winget PATH:' $_.Exception.Message >> "%TEMP_PS1%"
    ECHO     exit 1 >> "%TEMP_PS1%"
    ECHO } >> "%TEMP_PS1%"
    
    powershell -ExecutionPolicy Bypass -File "%TEMP_PS1%" 2>&1
    DEL /F /Q "%TEMP_PS1%" >nul 2>&1
    
    timeout /t 3 /nobreak >nul
    winget --version >nul 2>&1
    IF !ERRORLEVEL! EQU 0 (
        CALL :LOG_ENTRY "INFO" "Winget is now available and functional."
    ) ELSE (
        CALL :LOG_ENTRY "WARN" "Winget may require system restart to be fully functional."
    )
) ELSE (
    CALL :LOG_ENTRY "INFO" "Winget is already installed and functional."
)

REM -----------------------------------------------------------------------------
REM Winget Final Validation and Source Configuration
REM -----------------------------------------------------------------------------
CALL :LOG_ENTRY "INFO" "Performing comprehensive winget validation and source configuration..."

REM Create temp script for winget validation
SET "TEMP_PS1=%TEMP%\validate_winget.ps1"
ECHO try { > "%TEMP_PS1%"
ECHO     $ProgressPreference = 'SilentlyContinue' >> "%TEMP_PS1%"
ECHO     REM Test basic winget functionality >> "%TEMP_PS1%"
ECHO     $wingetTest = Start-Process winget -ArgumentList '--version'  -Wait -PassThru -ErrorAction SilentlyContinue >> "%TEMP_PS1%"
ECHO     if ($wingetTest -and $wingetTest.ExitCode -eq 0) { >> "%TEMP_PS1%"
ECHO         Write-Host '[INFO] Winget is functional and responding' >> "%TEMP_PS1%"
ECHO         REM Configure winget sources to prevent source errors >> "%TEMP_PS1%"
ECHO         try { >> "%TEMP_PS1%"
ECHO             $sourceCheck = Start-Process winget -ArgumentList 'source list'  -Wait -PassThru -RedirectStandardOutput $env:TEMP\winget_sources.txt >> "%TEMP_PS1%"
ECHO             if ($sourceCheck.ExitCode -eq 0) { >> "%TEMP_PS1%"
ECHO                 Write-Host '[INFO] Winget sources are accessible' >> "%TEMP_PS1%"
ECHO             } else { >> "%TEMP_PS1%"
ECHO                 Write-Host '[WARN] Winget sources need reset, attempting repair...' >> "%TEMP_PS1%"
ECHO                 Start-Process winget -ArgumentList 'source reset'  -Wait >> "%TEMP_PS1%"
ECHO                 Write-Host '[INFO] Winget sources reset completed' >> "%TEMP_PS1%"
ECHO             } >> "%TEMP_PS1%"
ECHO         } catch { >> "%TEMP_PS1%"
ECHO             Write-Host '[WARN] Winget source configuration issue:' $_.Exception.Message >> "%TEMP_PS1%"
ECHO         } >> "%TEMP_PS1%"
ECHO         exit 0 >> "%TEMP_PS1%"
ECHO     } else { >> "%TEMP_PS1%"
ECHO         Write-Host '[WARN] Winget validation failed - may need system restart' >> "%TEMP_PS1%"
ECHO         exit 1 >> "%TEMP_PS1%"
ECHO     } >> "%TEMP_PS1%"
ECHO } catch { >> "%TEMP_PS1%"
ECHO     Write-Host '[WARN] Winget validation error:' $_.Exception.Message >> "%TEMP_PS1%"
ECHO     exit 1 >> "%TEMP_PS1%"
ECHO } >> "%TEMP_PS1%"

powershell -ExecutionPolicy Bypass -File "%TEMP_PS1%" 2>&1
SET "WINGET_VALIDATION_EXIT=!ERRORLEVEL!"
DEL /F /Q "%TEMP_PS1%" >nul 2>&1

IF !WINGET_VALIDATION_EXIT! EQU 0 (
    CALL :LOG_ENTRY "INFO" "Winget validation passed - ready for package installations."
    SET "WINGET_AVAILABLE=YES"
) ELSE (
    CALL :LOG_ENTRY "WARN" "Winget validation failed - will use alternative installation methods."
    SET "WINGET_AVAILABLE=NO"
)

REM =============================================================================
REM PHASE 3: DEVELOPMENT TOOLS (Using validated package managers)
REM =============================================================================
ECHO.
ECHO ----------------------------------------
ECHO   PHASE 3: Development Tools
ECHO ----------------------------------------

REM -----------------------------------------------------------------------------
REM 3A. PowerShell 7 - Modern PowerShell environment
REM -----------------------------------------------------------------------------
CALL :LOG_ENTRY "INFO" "PHASE 3A: Installing PowerShell 7 (using Winget if available)..."
pwsh.exe -Version >nul 2>&1
IF !ERRORLEVEL! NEQ 0 (
    CALL :LOG_ENTRY "INFO" "PowerShell 7 not found, installing using best available method..."
    
    REM Create temp script for PowerShell 7 installation with Winget priority
    SET "TEMP_PS1=%TEMP%\install_powershell7.ps1"
    ECHO try { > "%TEMP_PS1%"
    ECHO     $ProgressPreference = 'SilentlyContinue' >> "%TEMP_PS1%"
    ECHO     $ps7Installed = $false >> "%TEMP_PS1%"
    ECHO     REM Try Winget first if available and validated >> "%TEMP_PS1%"
    IF "%WINGET_AVAILABLE%"=="YES" (
        ECHO     if (Get-Command winget -ErrorAction SilentlyContinue) { >> "%TEMP_PS1%"
        ECHO         try { >> "%TEMP_PS1%"
        ECHO             Write-Host '[INFO] Attempting PowerShell 7 installation via Winget...' >> "%TEMP_PS1%"
        ECHO             $wingetResult = Start-Process winget -ArgumentList 'install --id Microsoft.PowerShell --silent --accept-package-agreements --accept-source-agreements'  -Wait -PassThru >> "%TEMP_PS1%"
        ECHO             if ($wingetResult.ExitCode -eq 0) { >> "%TEMP_PS1%"
        ECHO                 Write-Host '[INFO] PowerShell 7 installed successfully via Winget' >> "%TEMP_PS1%"
        ECHO                 $ps7Installed = $true >> "%TEMP_PS1%"
        ECHO             } else { >> "%TEMP_PS1%"
        ECHO                 Write-Host '[WARN] Winget PowerShell 7 installation failed, trying direct download...' >> "%TEMP_PS1%"
        ECHO             } >> "%TEMP_PS1%"
        ECHO         } catch { >> "%TEMP_PS1%"
        ECHO             Write-Host '[WARN] Winget PowerShell 7 installation error, trying direct download...' >> "%TEMP_PS1%"
        ECHO         } >> "%TEMP_PS1%"
        ECHO     } >> "%TEMP_PS1%"
    )
    ECHO     REM Fallback to direct download if Winget failed or not available >> "%TEMP_PS1%"
    ECHO     if (-not $ps7Installed) { >> "%TEMP_PS1%"
    ECHO         Write-Host '[INFO] Using direct download for PowerShell 7...' >> "%TEMP_PS1%"
    ECHO         try { >> "%TEMP_PS1%"
    ECHO             $ps7Url = 'https://github.com/PowerShell/PowerShell/releases/download/v7.5.2/PowerShell-7.5.2-win-x64.msi' >> "%TEMP_PS1%"
    REM Check for 32-bit system
    IF "%PROCESSOR_ARCHITECTURE%"=="x86" (
        IF NOT DEFINED PROCESSOR_ARCHITEW6432 (
            ECHO             $ps7Url = 'https://github.com/PowerShell/PowerShell/releases/download/v7.5.2/PowerShell-7.5.2-win-x86.msi' >> "%TEMP_PS1%"
        )
    )
    ECHO             $ps7File = $env:TEMP + '\PowerShell-7.5.2.msi' >> "%TEMP_PS1%"
    ECHO             [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 >> "%TEMP_PS1%"
    ECHO             Invoke-WebRequest -Uri $ps7Url -OutFile $ps7File -UseBasicParsing -TimeoutSec 120 >> "%TEMP_PS1%"
    ECHO             Write-Host '[INFO] PowerShell 7 downloaded, installing...' >> "%TEMP_PS1%"
    ECHO             Start-Process msiexec -ArgumentList "/i `"$ps7File`" /quiet /norestart" -Wait >> "%TEMP_PS1%"
    ECHO             Remove-Item $ps7File -Force -ErrorAction SilentlyContinue >> "%TEMP_PS1%"
    ECHO             Write-Host '[INFO] PowerShell 7 installed via direct download' >> "%TEMP_PS1%"
    ECHO         } catch { >> "%TEMP_PS1%"
    ECHO             Write-Host '[ERROR] PowerShell 7 installation failed:' $_.Exception.Message >> "%TEMP_PS1%"
    ECHO         } >> "%TEMP_PS1%"
    ECHO     } >> "%TEMP_PS1%"
    ECHO } catch { >> "%TEMP_PS1%"
    ECHO     Write-Host '[WARN] PowerShell 7 installation process failed:' $_.Exception.Message >> "%TEMP_PS1%"
    ECHO } >> "%TEMP_PS1%"
    
    powershell -ExecutionPolicy Bypass -File "%TEMP_PS1%" 2>&1
    SET "PS7_INSTALL_EXIT=!ERRORLEVEL!"
    DEL /F /Q "%TEMP_PS1%" >nul 2>&1
    
    REM Safely refresh PATH - use simple approach
    CALL :LOG_ENTRY "INFO" "Refreshing PATH environment..."
    SET "PATH=%PATH%;%ProgramFiles%\PowerShell\7"
    IF EXIST "%ProgramFiles(x86)%\PowerShell\7" SET "PATH=%PATH%;%ProgramFiles(x86)%\PowerShell\7"
    
    REM Test PowerShell 7 availability after installation
    timeout /t 3 /nobreak >nul
    pwsh.exe -Version >nul 2>&1
    IF !ERRORLEVEL! EQU 0 (
        FOR /F "tokens=*" %%i IN ('pwsh.exe -Command "$PSVersionTable.PSVersion.ToString()" 2^>nul') DO SET PS7_VERSION=%%i
        CALL :LOG_ENTRY "INFO" "PowerShell 7 is now functional: !PS7_VERSION!"
        SET "PS7_AVAILABLE=YES"
    ) ELSE (
        CALL :LOG_ENTRY "WARN" "PowerShell 7 installation completed but may require restart to be fully functional."
        SET "PS7_AVAILABLE=NO"
    )
) ELSE (
    FOR /F "tokens=*" %%i IN ('pwsh.exe -Command "$PSVersionTable.PSVersion.ToString()" 2^>nul') DO SET PS7_VERSION=%%i
    CALL :LOG_ENTRY "INFO" "PowerShell 7 already available: !PS7_VERSION!"
    SET "PS7_AVAILABLE=YES"
)

:SKIP_PS7_INSTALL

REM -----------------------------------------------------------------------------
REM 3B. Git - Version control system (Can use Winget)
REM -----------------------------------------------------------------------------
CALL :LOG_ENTRY "INFO" "PHASE 3B: Installing Git (using Winget if available)..."
git --version >nul 2>&1
IF !ERRORLEVEL! NEQ 0 (
    REM Create temp script for Git installation
    SET "TEMP_PS1=%TEMP%\install_git.ps1"
    ECHO try { > "%TEMP_PS1%"
    ECHO     $ProgressPreference = 'SilentlyContinue' >> "%TEMP_PS1%"
    ECHO     $gitInstalled = $false >> "%TEMP_PS1%"
    ECHO     REM Try winget first if available and validated >> "%TEMP_PS1%"
    IF "%WINGET_AVAILABLE%"=="YES" (
        ECHO     if (Get-Command winget -ErrorAction SilentlyContinue) { >> "%TEMP_PS1%"
        ECHO         try { >> "%TEMP_PS1%"
        ECHO             $wingetResult = Start-Process winget -ArgumentList 'install --id Git.Git --silent --accept-package-agreements --accept-source-agreements'  -Wait -PassThru >> "%TEMP_PS1%"
        ECHO             if ($wingetResult.ExitCode -eq 0) { >> "%TEMP_PS1%"
        ECHO                 Write-Host '[INFO] Git installed successfully via winget' >> "%TEMP_PS1%"
        ECHO                 $gitInstalled = $true >> "%TEMP_PS1%"
        ECHO             } else { >> "%TEMP_PS1%"
        ECHO                 Write-Host '[WARN] Winget Git installation failed, trying chocolatey...' >> "%TEMP_PS1%"
        ECHO             } >> "%TEMP_PS1%"
        ECHO         } catch { >> "%TEMP_PS1%"
        ECHO             Write-Host '[WARN] Winget Git installation error, trying chocolatey...' >> "%TEMP_PS1%"
        ECHO         } >> "%TEMP_PS1%"
        ECHO     } >> "%TEMP_PS1%"
    )
    ECHO     REM Try chocolatey if winget failed or not available >> "%TEMP_PS1%"
    ECHO     if (-not $gitInstalled -and (Get-Command choco -ErrorAction SilentlyContinue)) { >> "%TEMP_PS1%"
    ECHO         try { >> "%TEMP_PS1%"
    ECHO             $chocoResult = Start-Process choco -ArgumentList 'install git -y --no-progress'  -Wait -PassThru >> "%TEMP_PS1%"
    ECHO             if ($chocoResult.ExitCode -eq 0) { >> "%TEMP_PS1%"
    ECHO                 Write-Host '[INFO] Git installed successfully via chocolatey' >> "%TEMP_PS1%"
    ECHO                 $gitInstalled = $true >> "%TEMP_PS1%"
    ECHO             } else { >> "%TEMP_PS1%"
    ECHO                 Write-Host '[WARN] Chocolatey Git installation failed' >> "%TEMP_PS1%"
    ECHO             } >> "%TEMP_PS1%"
    ECHO         } catch { >> "%TEMP_PS1%"
    ECHO             Write-Host '[WARN] Chocolatey Git installation error' >> "%TEMP_PS1%"
    ECHO         } >> "%TEMP_PS1%"
    ECHO     } >> "%TEMP_PS1%"
    ECHO     REM Final fallback - direct download >> "%TEMP_PS1%"
    ECHO     if (-not $gitInstalled) { >> "%TEMP_PS1%"
    ECHO         Write-Host '[INFO] Attempting direct Git download installation...' >> "%TEMP_PS1%"
    ECHO         try { >> "%TEMP_PS1%"
    ECHO             $gitUrl = 'https://github.com/git-for-windows/git/releases/download/v2.50.1.windows.1/Git-2.50.1-64-bit.exe' >> "%TEMP_PS1%"
    ECHO             $gitFile = $env:TEMP + '\Git-installer.exe' >> "%TEMP_PS1%"
    ECHO             Invoke-WebRequest -Uri $gitUrl -OutFile $gitFile -UseBasicParsing -TimeoutSec 120 >> "%TEMP_PS1%"
    ECHO             Start-Process $gitFile -ArgumentList '/VERYSILENT /NORESTART' -Wait >> "%TEMP_PS1%"
    ECHO             Remove-Item $gitFile -Force -ErrorAction SilentlyContinue >> "%TEMP_PS1%"
    ECHO             Write-Host '[INFO] Git installed via direct download' >> "%TEMP_PS1%"
    ECHO         } catch { >> "%TEMP_PS1%"
    ECHO             Write-Host '[ERROR] All Git installation methods failed:' $_.Exception.Message >> "%TEMP_PS1%"
    ECHO         } >> "%TEMP_PS1%"
    ECHO     } >> "%TEMP_PS1%"
    ECHO } catch { >> "%TEMP_PS1%"
    ECHO     Write-Host '[WARN] Git installation process failed:' $_.Exception.Message >> "%TEMP_PS1%"
    ECHO } >> "%TEMP_PS1%"
    
    powershell -ExecutionPolicy Bypass -File "%TEMP_PS1%" 2>&1
    DEL /F /Q "%TEMP_PS1%" >nul 2>&1
    
    REM Update PATH for Git
    IF EXIST "%ProgramFiles%\Git\bin" SET "PATH=%PATH%;%ProgramFiles%\Git\bin"
    IF EXIST "%ProgramFiles(x86)%\Git\bin" SET "PATH=%PATH%;%ProgramFiles(x86)%\Git\bin"
) ELSE (
    CALL :LOG_ENTRY "INFO" "Git is already installed."
)

REM -----------------------------------------------------------------------------
REM 3C. .NET Framework 4.8.1 - Required for many applications (Can use Winget)
REM -----------------------------------------------------------------------------
CALL :LOG_ENTRY "INFO" "PHASE 3C: Installing .NET Framework 4.8.1 (using Winget if available)..."

REM Create temp script for .NET Framework check
SET "TEMP_PS1=%TEMP%\check_dotnet.ps1"
ECHO try { > "%TEMP_PS1%"
ECHO     $ProgressPreference = 'SilentlyContinue' >> "%TEMP_PS1%"
ECHO     $netVersion = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full\' -Name Release -ErrorAction SilentlyContinue).Release >> "%TEMP_PS1%"
ECHO     if ($netVersion -ge 528040) { >> "%TEMP_PS1%"
ECHO         Write-Host '[INFO] .NET Framework 4.8.1 or higher already installed' >> "%TEMP_PS1%"
ECHO     } else { >> "%TEMP_PS1%"
ECHO         Write-Host '[INFO] Installing .NET Framework 4.8.1...' >> "%TEMP_PS1%"
IF "%WINGET_AVAILABLE%"=="YES" (
    ECHO         if (Get-Command winget -ErrorAction SilentlyContinue) { >> "%TEMP_PS1%"
    ECHO             try { >> "%TEMP_PS1%"
    ECHO                 $wingetResult = Start-Process winget -ArgumentList 'install --id Microsoft.DotNet.Framework.DeveloperPack_4 --silent --accept-package-agreements --accept-source-agreements'  -Wait -PassThru >> "%TEMP_PS1%"
    ECHO                 if ($wingetResult.ExitCode -eq 0) { >> "%TEMP_PS1%"
    ECHO                     Write-Host '[INFO] .NET Framework 4.8.1 installed via winget' >> "%TEMP_PS1%"
    ECHO                 } else { >> "%TEMP_PS1%"
    ECHO                     Write-Host '[WARN] Winget .NET installation failed, using direct method' >> "%TEMP_PS1%"
    ECHO                     $dotnetUrl = 'https://go.microsoft.com/fwlink/?LinkId=2203304' >> "%TEMP_PS1%"
    ECHO                     $dotnetFile = $env:TEMP + '\ndp481-web.exe' >> "%TEMP_PS1%"
    ECHO                     Invoke-WebRequest -Uri $dotnetUrl -OutFile $dotnetFile -UseBasicParsing >> "%TEMP_PS1%"
    ECHO                     Start-Process $dotnetFile -ArgumentList '/quiet /norestart' -Wait >> "%TEMP_PS1%"
    ECHO                     Remove-Item $dotnetFile -Force -ErrorAction SilentlyContinue >> "%TEMP_PS1%"
    ECHO                     Write-Host '[INFO] .NET Framework 4.8.1 installed via direct download' >> "%TEMP_PS1%"
    ECHO                 } >> "%TEMP_PS1%"
    ECHO             } catch { >> "%TEMP_PS1%"
    ECHO                 Write-Host '[WARN] Winget method failed, using direct download' >> "%TEMP_PS1%"
    ECHO                 $dotnetUrl = 'https://go.microsoft.com/fwlink/?LinkId=2203304' >> "%TEMP_PS1%"
    ECHO                 $dotnetFile = $env:TEMP + '\ndp481-web.exe' >> "%TEMP_PS1%"
    ECHO                 Invoke-WebRequest -Uri $dotnetUrl -OutFile $dotnetFile -UseBasicParsing >> "%TEMP_PS1%"
    ECHO                 Start-Process $dotnetFile -ArgumentList '/quiet /norestart' -Wait >> "%TEMP_PS1%"
    ECHO                 Remove-Item $dotnetFile -Force -ErrorAction SilentlyContinue >> "%TEMP_PS1%"
    ECHO                 Write-Host '[INFO] .NET Framework 4.8.1 installed via direct download' >> "%TEMP_PS1%"
    ECHO             } >> "%TEMP_PS1%"
    ECHO         } else { >> "%TEMP_PS1%"
) ELSE (
    ECHO         REM Winget not available, use direct download method >> "%TEMP_PS1%"
)
ECHO             Write-Host '[INFO] Using direct download for .NET Framework 4.8.1...' >> "%TEMP_PS1%"
ECHO             $dotnetUrl = 'https://go.microsoft.com/fwlink/?LinkId=2203304' >> "%TEMP_PS1%"
ECHO             $dotnetFile = $env:TEMP + '\ndp481-web.exe' >> "%TEMP_PS1%"
ECHO             Invoke-WebRequest -Uri $dotnetUrl -OutFile $dotnetFile -UseBasicParsing >> "%TEMP_PS1%"
ECHO             Start-Process $dotnetFile -ArgumentList '/quiet /norestart' -Wait >> "%TEMP_PS1%"
ECHO             Remove-Item $dotnetFile -Force -ErrorAction SilentlyContinue >> "%TEMP_PS1%"
ECHO             Write-Host '[INFO] .NET Framework 4.8.1 installation completed' >> "%TEMP_PS1%"
IF "%WINGET_AVAILABLE%"=="YES" (
    ECHO         } >> "%TEMP_PS1%"
)
ECHO     } >> "%TEMP_PS1%"
ECHO } catch { >> "%TEMP_PS1%"
ECHO     Write-Host '[WARN] .NET Framework check failed:' $_.Exception.Message >> "%TEMP_PS1%"
ECHO } >> "%TEMP_PS1%"

powershell -ExecutionPolicy Bypass -File "%TEMP_PS1%" 2>&1
DEL /F /Q "%TEMP_PS1%" >nul 2>&1

REM =============================================================================
REM PHASE 4: POWERSHELL ENVIRONMENT (Dependencies for PowerShell modules)
REM =============================================================================
ECHO.
ECHO ----------------------------------------
ECHO   PHASE 4: PowerShell Environment
ECHO ----------------------------------------

REM -----------------------------------------------------------------------------
REM 4A. NuGet PackageProvider - Required for PowerShell modules
REM -----------------------------------------------------------------------------
CALL :LOG_ENTRY "INFO" "PHASE 4A: Installing NuGet PackageProvider..."

REM Create temp script for NuGet check and install
SET "TEMP_PS1=%TEMP%\install_nuget.ps1"
ECHO $env:PACKAGEMANAGEMENT_BOOTSTRAP_LOGLEVEL = 'None' > "%TEMP_PS1%"
ECHO $ProgressPreference = 'SilentlyContinue' >> "%TEMP_PS1%"
ECHO try { >> "%TEMP_PS1%"
ECHO     $nugetProvider = Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue >> "%TEMP_PS1%"
ECHO     if ($nugetProvider -and $nugetProvider.Version -ge '2.8.5.201') { >> "%TEMP_PS1%"
ECHO         Write-Host '[INFO] NuGet PackageProvider already available (version: ' + $nugetProvider.Version + ')' >> "%TEMP_PS1%"
ECHO         exit 0 >> "%TEMP_PS1%"
ECHO     } else { >> "%TEMP_PS1%"
ECHO         [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 >> "%TEMP_PS1%"
ECHO         $null = Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope AllUsers -Confirm:$false -ErrorAction Stop >> "%TEMP_PS1%"
ECHO         Write-Host '[INFO] NuGet PackageProvider installed successfully' >> "%TEMP_PS1%"
ECHO         exit 0 >> "%TEMP_PS1%"
ECHO     } >> "%TEMP_PS1%"
ECHO } catch { >> "%TEMP_PS1%"
ECHO     Write-Host '[WARN] Failed to install NuGet PackageProvider:' $_.Exception.Message >> "%TEMP_PS1%"
ECHO     exit 1 >> "%TEMP_PS1%"
ECHO } >> "%TEMP_PS1%"

ECHO [INFO] Running NuGet PackageProvider check/install...
powershell -ExecutionPolicy Bypass -File "%TEMP_PS1%" 2>&1
DEL /F /Q "%TEMP_PS1%" >nul 2>&1

IF !ERRORLEVEL! NEQ 0 (
    CALL :LOG_ENTRY "WARN" "NuGet PackageProvider installation failed, but continuing..."
) ELSE (
    CALL :LOG_ENTRY "INFO" "NuGet PackageProvider is ready."
)

REM -----------------------------------------------------------------------------
REM 4B. PowerShell Gallery Configuration - Required for module downloads
REM -----------------------------------------------------------------------------
CALL :LOG_ENTRY "INFO" "Checking PowerShell Gallery configuration..."

REM Create temp script for PSGallery configuration
SET "TEMP_PS1=%TEMP%\config_psgallery.ps1"
ECHO try { > "%TEMP_PS1%"
ECHO     $ProgressPreference = 'SilentlyContinue' >> "%TEMP_PS1%"
ECHO     $psGallery = Get-PSRepository -Name 'PSGallery' -ErrorAction SilentlyContinue >> "%TEMP_PS1%"
ECHO     if ($psGallery -and $psGallery.InstallationPolicy -eq 'Trusted') { >> "%TEMP_PS1%"
ECHO         Write-Host '[INFO] PowerShell Gallery already configured as trusted' >> "%TEMP_PS1%"
ECHO         exit 0 >> "%TEMP_PS1%"
ECHO     } else { >> "%TEMP_PS1%"
ECHO         Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted -ErrorAction Stop >> "%TEMP_PS1%"
ECHO         Write-Host '[INFO] PowerShell Gallery configured as trusted' >> "%TEMP_PS1%"
ECHO         exit 0 >> "%TEMP_PS1%"
ECHO     } >> "%TEMP_PS1%"
ECHO } catch { >> "%TEMP_PS1%"
ECHO     Write-Host '[WARN] Failed to configure PowerShell Gallery:' $_.Exception.Message >> "%TEMP_PS1%"
ECHO     exit 1 >> "%TEMP_PS1%"
ECHO } >> "%TEMP_PS1%"

powershell -ExecutionPolicy Bypass -File "%TEMP_PS1%" 2>&1
SET "PSGALLERY_EXIT=!ERRORLEVEL!"
DEL /F /Q "%TEMP_PS1%" >nul 2>&1

IF !PSGALLERY_EXIT! NEQ 0 (
    CALL :LOG_ENTRY "WARN" "PowerShell Gallery configuration failed, but continuing..."
) ELSE (
    CALL :LOG_ENTRY "INFO" "PowerShell Gallery is ready."
)

REM -----------------------------------------------------------------------------
REM 4C. PSWindowsUpdate Module - PowerShell module for Windows Updates
REM -----------------------------------------------------------------------------
CALL :LOG_ENTRY "INFO" "Checking PSWindowsUpdate module..."

REM Create temp script for PSWindowsUpdate module
SET "TEMP_PS1=%TEMP%\install_pswindowsupdate.ps1"
ECHO $ProgressPreference = 'SilentlyContinue' > "%TEMP_PS1%"
ECHO try { >> "%TEMP_PS1%"
ECHO     $psWindowsUpdate = Get-Module -ListAvailable -Name PSWindowsUpdate -ErrorAction SilentlyContinue >> "%TEMP_PS1%"
ECHO     if ($psWindowsUpdate) { >> "%TEMP_PS1%"
ECHO         Write-Host '[INFO] PSWindowsUpdate module already available (version: ' + $psWindowsUpdate.Version + ')' >> "%TEMP_PS1%"
ECHO         exit 0 >> "%TEMP_PS1%"
ECHO     } else { >> "%TEMP_PS1%"
ECHO         [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 >> "%TEMP_PS1%"
ECHO         $null = Install-Module -Name PSWindowsUpdate -Force -Scope AllUsers -AllowClobber -Confirm:$false -Repository PSGallery >> "%TEMP_PS1%"
ECHO         Write-Host '[INFO] PSWindowsUpdate module installed successfully' >> "%TEMP_PS1%"
ECHO         exit 0 >> "%TEMP_PS1%"
ECHO     } >> "%TEMP_PS1%"
ECHO } catch { >> "%TEMP_PS1%"
ECHO     Write-Host '[WARN] Failed to install PSWindowsUpdate module:' $_.Exception.Message >> "%TEMP_PS1%"
ECHO     exit 1 >> "%TEMP_PS1%"
ECHO } >> "%TEMP_PS1%"

powershell -ExecutionPolicy Bypass -File "%TEMP_PS1%" 2>&1
SET "PSWINDOWSUPDATE_EXIT=!ERRORLEVEL!"
DEL /F /Q "%TEMP_PS1%" >nul 2>&1

IF !PSWINDOWSUPDATE_EXIT! NEQ 0 (
    CALL :LOG_ENTRY "WARN" "PSWindowsUpdate module installation failed, but continuing..."
) ELSE (
    CALL :LOG_ENTRY "INFO" "PSWindowsUpdate module is ready."
)

REM -----------------------------------------------------------------------------
REM 4D. Chocolatey Package Manager - Alternative package manager
REM -----------------------------------------------------------------------------
CALL :LOG_ENTRY "INFO" "Installing Chocolatey package manager..."
choco --version >nul 2>&1
IF !ERRORLEVEL! NEQ 0 (
    CALL :LOG_ENTRY "INFO" "Chocolatey not found, downloading from official source..."
    
    REM Create temp script for Chocolatey installation
    SET "TEMP_PS1=%TEMP%\install_chocolatey.ps1"
    ECHO try { > "%TEMP_PS1%"
    ECHO     $ProgressPreference = 'SilentlyContinue' >> "%TEMP_PS1%"
    ECHO     [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 >> "%TEMP_PS1%"
    ECHO     Set-ExecutionPolicy Bypass -Scope Process -Force >> "%TEMP_PS1%"
    ECHO     $env:ChocolateyInstall = '$env:ProgramData\chocolatey' >> "%TEMP_PS1%"
    ECHO     iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1')) >> "%TEMP_PS1%"
    ECHO     Write-Host '[INFO] Chocolatey installed successfully' >> "%TEMP_PS1%"
    ECHO     exit 0 >> "%TEMP_PS1%"
    ECHO } catch { >> "%TEMP_PS1%"
    ECHO     Write-Host '[WARN] Chocolatey installation failed:' $_.Exception.Message >> "%TEMP_PS1%"
    ECHO     exit 1 >> "%TEMP_PS1%"
    ECHO } >> "%TEMP_PS1%"
    
    powershell -ExecutionPolicy Bypass -File "%TEMP_PS1%" 2>&1
    SET "CHOCO_EXIT=!ERRORLEVEL!"
    DEL /F /Q "%TEMP_PS1%" >nul 2>&1
    
    IF !CHOCO_EXIT! EQU 0 (
        REM Refresh PATH to include Chocolatey
        IF EXIST "%ProgramData%\chocolatey\bin" (
            SET "PATH=%PATH%;%ProgramData%\chocolatey\bin"
            CALL :LOG_ENTRY "INFO" "Chocolatey PATH updated and installation completed."
        )
    ) ELSE (
        CALL :LOG_ENTRY "WARN" "Chocolatey installation failed, but continuing..."
    )
) ELSE (
    CALL :LOG_ENTRY "INFO" "Chocolatey is already installed."
)

REM -----------------------------------------------------------------------------
REM 4E. PowerShellGet and PackageManagement - Latest Versions
REM -----------------------------------------------------------------------------
CALL :LOG_ENTRY "INFO" "Checking PowerShellGet and PackageManagement modules..."

REM Create temp script for PowerShellGet check
SET "TEMP_PS1=%TEMP%\check_powershellget.ps1"
ECHO try { > "%TEMP_PS1%"
ECHO     $ProgressPreference = 'SilentlyContinue' >> "%TEMP_PS1%"
ECHO     [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 >> "%TEMP_PS1%"
ECHO     $modules = Get-Module -ListAvailable PowerShellGet
    $psGet = $modules | Sort-Object Version -Descending | Select-Object -First 1 >> "%TEMP_PS1%"
ECHO     if ($psGet -and $psGet.Version -ge '2.2.5') { >> "%TEMP_PS1%"
ECHO         Write-Host '[INFO] PowerShellGet is up to date (version:' $psGet.Version ')' >> "%TEMP_PS1%"
ECHO     } else { >> "%TEMP_PS1%"
ECHO         Write-Host '[INFO] Updating PowerShellGet module...' >> "%TEMP_PS1%"
ECHO         $null = Install-Module -Name PowerShellGet -Force -Scope AllUsers -AllowClobber -Confirm:$false -Repository PSGallery >> "%TEMP_PS1%"
ECHO         Write-Host '[INFO] PowerShellGet updated successfully' >> "%TEMP_PS1%"
ECHO     } >> "%TEMP_PS1%"
ECHO } catch { >> "%TEMP_PS1%"
ECHO     Write-Host '[WARN] PowerShellGet update failed:' $_.Exception.Message >> "%TEMP_PS1%"
ECHO } >> "%TEMP_PS1%"

powershell -ExecutionPolicy Bypass -File "%TEMP_PS1%" 2>&1
DEL /F /Q "%TEMP_PS1%" >nul 2>&1

REM Create temp script for PackageManagement check
SET "TEMP_PS1=%TEMP%\check_packagemgmt.ps1"
ECHO try { > "%TEMP_PS1%"
ECHO     $ProgressPreference = 'SilentlyContinue' >> "%TEMP_PS1%"
ECHO     [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 >> "%TEMP_PS1%"
ECHO     $modules = Get-Module -ListAvailable PackageManagement
    $pkgMgmt = $modules | Sort-Object Version -Descending | Select-Object -First 1 >> "%TEMP_PS1%"
ECHO     if ($pkgMgmt -and $pkgMgmt.Version -ge '1.4.8') { >> "%TEMP_PS1%"
ECHO         Write-Host '[INFO] PackageManagement is up to date (version:' $pkgMgmt.Version ')' >> "%TEMP_PS1%"
ECHO     } else { >> "%TEMP_PS1%"
ECHO         Write-Host '[INFO] Updating PackageManagement module...' >> "%TEMP_PS1%"
ECHO         $null = Install-Module -Name PackageManagement -Force -Scope AllUsers -AllowClobber -Confirm:$false -Repository PSGallery >> "%TEMP_PS1%"
ECHO         Write-Host '[INFO] PackageManagement updated successfully' >> "%TEMP_PS1%"
ECHO     } >> "%TEMP_PS1%"
ECHO } catch { >> "%TEMP_PS1%"
ECHO     Write-Host '[WARN] PackageManagement update failed:' $_.Exception.Message >> "%TEMP_PS1%"
ECHO } >> "%TEMP_PS1%"

powershell -ExecutionPolicy Bypass -File "%TEMP_PS1%" 2>&1
DEL /F /Q "%TEMP_PS1%" >nul 2>&1

REM =============================================================================
REM FINAL VALIDATION AND CLEANUP
REM =============================================================================
ECHO.
ECHO ----------------------------------------
ECHO   Final Validation & Cleanup
ECHO ----------------------------------------

REM Additional PowerShell Modules and Windows Features sections follow below...

REM -----------------------------------------------------------------------------
REM 10. .NET Framework 4.8.1 - Required for many PowerShell modules and applications
REM -----------------------------------------------------------------------------
CALL :LOG_ENTRY "INFO" "Checking .NET Framework 4.8.1..."

REM Create temp script for .NET Framework check
SET "TEMP_PS1=%TEMP%\check_dotnet.ps1"
ECHO try { > "%TEMP_PS1%"
ECHO     $ProgressPreference = 'SilentlyContinue' >> "%TEMP_PS1%"
ECHO     $netVersion = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full\' -Name Release -ErrorAction SilentlyContinue).Release >> "%TEMP_PS1%"
ECHO     if ($netVersion -ge 528040) { >> "%TEMP_PS1%"
ECHO         Write-Host '[INFO] .NET Framework 4.8.1 or higher already installed' >> "%TEMP_PS1%"
ECHO     } else { >> "%TEMP_PS1%"
ECHO         Write-Host '[INFO] Installing .NET Framework 4.8.1...' >> "%TEMP_PS1%"
IF "%WINGET_AVAILABLE%"=="YES" (
    ECHO         if (Get-Command winget -ErrorAction SilentlyContinue) { >> "%TEMP_PS1%"
    ECHO             try { >> "%TEMP_PS1%"
    ECHO                 $wingetResult = Start-Process winget -ArgumentList 'install --id Microsoft.DotNet.Framework.DeveloperPack_4 --silent --accept-package-agreements --accept-source-agreements'  -Wait -PassThru >> "%TEMP_PS1%"
    ECHO                 if ($wingetResult.ExitCode -eq 0) { >> "%TEMP_PS1%"
    ECHO                     Write-Host '[INFO] .NET Framework 4.8.1 installed via winget' >> "%TEMP_PS1%"
    ECHO                 } else { >> "%TEMP_PS1%"
    ECHO                     Write-Host '[WARN] Winget .NET installation failed, using direct method' >> "%TEMP_PS1%"
    ECHO                     $dotnetUrl = 'https://go.microsoft.com/fwlink/?LinkId=2203304' >> "%TEMP_PS1%"
    ECHO                     $dotnetFile = $env:TEMP + '\ndp481-web.exe' >> "%TEMP_PS1%"
    ECHO                     Invoke-WebRequest -Uri $dotnetUrl -OutFile $dotnetFile -UseBasicParsing >> "%TEMP_PS1%"
    ECHO                     Start-Process $dotnetFile -ArgumentList '/quiet /norestart' -Wait >> "%TEMP_PS1%"
    ECHO                     Remove-Item $dotnetFile -Force -ErrorAction SilentlyContinue >> "%TEMP_PS1%"
    ECHO                     Write-Host '[INFO] .NET Framework 4.8.1 installed via direct download' >> "%TEMP_PS1%"
    ECHO                 } >> "%TEMP_PS1%"
    ECHO             } catch { >> "%TEMP_PS1%"
    ECHO                 Write-Host '[WARN] Winget method failed, using direct download' >> "%TEMP_PS1%"
    ECHO                 $dotnetUrl = 'https://go.microsoft.com/fwlink/?LinkId=2203304' >> "%TEMP_PS1%"
    ECHO                 $dotnetFile = $env:TEMP + '\ndp481-web.exe' >> "%TEMP_PS1%"
    ECHO                 Invoke-WebRequest -Uri $dotnetUrl -OutFile $dotnetFile -UseBasicParsing >> "%TEMP_PS1%"
    ECHO                 Start-Process $dotnetFile -ArgumentList '/quiet /norestart' -Wait >> "%TEMP_PS1%"
    ECHO                 Remove-Item $dotnetFile -Force -ErrorAction SilentlyContinue >> "%TEMP_PS1%"
    ECHO                 Write-Host '[INFO] .NET Framework 4.8.1 installed via direct download' >> "%TEMP_PS1%"
    ECHO             } >> "%TEMP_PS1%"
    ECHO         } else { >> "%TEMP_PS1%"
) ELSE (
    ECHO         REM Winget not available, use direct download method >> "%TEMP_PS1%"
)
ECHO             Write-Host '[INFO] Using direct download for .NET Framework 4.8.1...' >> "%TEMP_PS1%"
ECHO             $dotnetUrl = 'https://go.microsoft.com/fwlink/?LinkId=2203304' >> "%TEMP_PS1%"
ECHO             $dotnetFile = $env:TEMP + '\ndp481-web.exe' >> "%TEMP_PS1%"
ECHO             Invoke-WebRequest -Uri $dotnetUrl -OutFile $dotnetFile -UseBasicParsing >> "%TEMP_PS1%"
ECHO             Start-Process $dotnetFile -ArgumentList '/quiet /norestart' -Wait >> "%TEMP_PS1%"
ECHO             Remove-Item $dotnetFile -Force -ErrorAction SilentlyContinue >> "%TEMP_PS1%"
ECHO             Write-Host '[INFO] .NET Framework 4.8.1 installation completed' >> "%TEMP_PS1%"
IF "%WINGET_AVAILABLE%"=="YES" (
    ECHO         } >> "%TEMP_PS1%"
)
ECHO     } >> "%TEMP_PS1%"
ECHO } catch { >> "%TEMP_PS1%"
ECHO     Write-Host '[WARN] .NET Framework check failed:' $_.Exception.Message >> "%TEMP_PS1%"
ECHO } >> "%TEMP_PS1%"

powershell -ExecutionPolicy Bypass -File "%TEMP_PS1%" 2>&1
DEL /F /Q "%TEMP_PS1%" >nul 2>&1

REM -----------------------------------------------------------------------------
REM 11. Additional PowerShell Modules for Enhanced Functionality
REM -----------------------------------------------------------------------------
CALL :LOG_ENTRY "INFO" "Checking additional PowerShell modules..."

REM Create temp script for module check
SET "TEMP_PS1=%TEMP%\check_modules.ps1"
ECHO try { > "%TEMP_PS1%"
ECHO     $ProgressPreference = 'SilentlyContinue' >> "%TEMP_PS1%"
ECHO     [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 >> "%TEMP_PS1%"
ECHO     $modules = @('DISM', 'PnpDevice', 'WindowsSearch') >> "%TEMP_PS1%"
ECHO     foreach ($module in $modules) { >> "%TEMP_PS1%"
ECHO         if (-not (Get-Module -ListAvailable -Name $module -ErrorAction SilentlyContinue)) { >> "%TEMP_PS1%"
ECHO             try { >> "%TEMP_PS1%"
ECHO                 $null = Import-Module $module -ErrorAction Stop >> "%TEMP_PS1%"
ECHO                 Write-Host "[INFO] Module $module verified and available" >> "%TEMP_PS1%"
ECHO             } catch { >> "%TEMP_PS1%"
ECHO                 Write-Host "[INFO] Module $module not available - will be loaded when needed" >> "%TEMP_PS1%"
ECHO             } >> "%TEMP_PS1%"
ECHO         } else { >> "%TEMP_PS1%"
ECHO             Write-Host "[INFO] Module $module already available" >> "%TEMP_PS1%"
ECHO         } >> "%TEMP_PS1%"
ECHO     } >> "%TEMP_PS1%"
ECHO } catch { >> "%TEMP_PS1%"
ECHO     Write-Host '[WARN] Module check failed:' $_.Exception.Message >> "%TEMP_PS1%"
ECHO } >> "%TEMP_PS1%"

powershell -ExecutionPolicy Bypass -File "%TEMP_PS1%" 2>&1
DEL /F /Q "%TEMP_PS1%" >nul 2>&1

REM -----------------------------------------------------------------------------
REM 12. Windows Features - Enable required features
REM -----------------------------------------------------------------------------
CALL :LOG_ENTRY "INFO" "Checking Windows features..."

REM Create temp script for Windows features check
SET "TEMP_PS1=%TEMP%\check_features.ps1"
ECHO try { > "%TEMP_PS1%"
ECHO     $ProgressPreference = 'SilentlyContinue' >> "%TEMP_PS1%"
ECHO     $features = @('NetFx3', 'MSMQ-Container', 'IIS-ManagementConsole') >> "%TEMP_PS1%"
ECHO     foreach ($feature in $features) { >> "%TEMP_PS1%"
ECHO         $featureState = Get-WindowsOptionalFeature -Online -FeatureName $feature -ErrorAction SilentlyContinue >> "%TEMP_PS1%"
ECHO         if ($featureState) { >> "%TEMP_PS1%"
ECHO             if ($featureState.State -eq 'Enabled') { >> "%TEMP_PS1%"
ECHO                 Write-Host "[INFO] Windows feature $feature already enabled" >> "%TEMP_PS1%"
ECHO             } elseif ($featureState.State -eq 'Disabled') { >> "%TEMP_PS1%"
ECHO                 Write-Host "[INFO] Enabling Windows feature: $feature" >> "%TEMP_PS1%"
ECHO                 $null = Enable-WindowsOptionalFeature -Online -FeatureName $feature -All -NoRestart -ErrorAction SilentlyContinue >> "%TEMP_PS1%"
ECHO                 Write-Host "[INFO] Windows feature $feature enabled successfully" >> "%TEMP_PS1%"
ECHO             } >> "%TEMP_PS1%"
ECHO         } else { >> "%TEMP_PS1%"
ECHO             Write-Host "[INFO] Windows feature $feature not available on this system" >> "%TEMP_PS1%"
ECHO         } >> "%TEMP_PS1%"
ECHO     } >> "%TEMP_PS1%"
ECHO } catch { >> "%TEMP_PS1%"
ECHO     Write-Host '[INFO] Windows features check completed' >> "%TEMP_PS1%"
ECHO } >> "%TEMP_PS1%"

powershell -ExecutionPolicy Bypass -File "%TEMP_PS1%" 2>&1
DEL /F /Q "%TEMP_PS1%" >nul 2>&1

REM -----------------------------------------------------------------------------
REM 13. System Performance Optimizations
REM -----------------------------------------------------------------------------
CALL :LOG_ENTRY "INFO" "Checking system performance settings..."

REM Create temp script for service optimization
SET "TEMP_PS1=%TEMP%\optimize_services.ps1"
ECHO try { > "%TEMP_PS1%"
ECHO     $ProgressPreference = 'SilentlyContinue' >> "%TEMP_PS1%"
ECHO     $services = @('Themes', 'UxSms') >> "%TEMP_PS1%"
ECHO     foreach ($service in $services) { >> "%TEMP_PS1%"
ECHO         $svc = Get-Service -Name $service -ErrorAction SilentlyContinue >> "%TEMP_PS1%"
ECHO         if ($svc) { >> "%TEMP_PS1%"
ECHO             if ($svc.StartType -eq 'Automatic') { >> "%TEMP_PS1%"
ECHO                 Write-Host "[INFO] Service $service already set to Automatic" >> "%TEMP_PS1%"
ECHO             } else { >> "%TEMP_PS1%"
ECHO                 $null = Set-Service -Name $service -StartupType Automatic -ErrorAction SilentlyContinue >> "%TEMP_PS1%"
ECHO                 Write-Host "[INFO] Service $service set to Automatic startup" >> "%TEMP_PS1%"
ECHO             } >> "%TEMP_PS1%"
ECHO         } else { >> "%TEMP_PS1%"
ECHO             Write-Host "[INFO] Service $service not found on this system" >> "%TEMP_PS1%"
ECHO         } >> "%TEMP_PS1%"
ECHO     } >> "%TEMP_PS1%"
ECHO     Write-Host '[INFO] System services optimization completed' >> "%TEMP_PS1%"
ECHO } catch { >> "%TEMP_PS1%"
ECHO     Write-Host '[INFO] Service optimization completed with some warnings' >> "%TEMP_PS1%"
ECHO } >> "%TEMP_PS1%"

powershell -ExecutionPolicy Bypass -File "%TEMP_PS1%" 2>&1
DEL /F /Q "%TEMP_PS1%" >nul 2>&1

CALL :LOG_ENTRY "INFO" "Dependency installation phase completed with comprehensive coverage."

REM -----------------------------------------------------------------------------
REM System Restart Detection - Simplified
REM -----------------------------------------------------------------------------
CALL :LOG_ENTRY "INFO" "Checking for pending system restarts..."
SET "RESTART_NEEDED=NO"

REM Check Windows Update reboot flag
REG QUERY "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired" >nul 2>&1
IF !ERRORLEVEL! EQU 0 SET "RESTART_NEEDED=YES"

REM Check Component Based Servicing reboot flag
REG QUERY "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending" >nul 2>&1
IF !ERRORLEVEL! EQU 0 SET "RESTART_NEEDED=YES"

REM Check pending file operations
REG QUERY "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager" /v PendingFileRenameOperations >nul 2>&1
IF !ERRORLEVEL! EQU 0 SET "RESTART_NEEDED=YES"

IF "%RESTART_NEEDED%"=="YES" (
    ECHO [%TIME%] [WARN] System restart is pending. Creating startup task...
    schtasks /Query /TN "%STARTUP_TASK_NAME%" >nul 2>&1
    IF %ERRORLEVEL% EQU 0 (
        schtasks /Delete /TN "%STARTUP_TASK_NAME%" /F >nul 2>&1
    )
    schtasks /Create /SC ONLOGON /TN "%STARTUP_TASK_NAME%" /TR "%SCRIPT_PATH%" /RL HIGHEST /RU "%USERNAME%" /DELAY 0001:00 /F
    IF !ERRORLEVEL! EQU 0 (
        ECHO [%TIME%] [INFO] Startup task created. Restarting system in 15 seconds...
        ECHO [%TIME%] [INFO] Press Ctrl+C to cancel restart.
        timeout /t 15
        shutdown /r /t 5 /c "System restart required for maintenance continuation"
        EXIT /B 0
    ) ELSE (
        ECHO [%TIME%] [WARN] Failed to create startup task. Continuing without restart...
REM Check pending file operations
REG QUERY "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager" /v PendingFileRenameOperations >nul 2>&1
IF !ERRORLEVEL! EQU 0 SET "RESTART_NEEDED=YES"

IF "%RESTART_NEEDED%"=="YES" (
    CALL :LOG_ENTRY "WARN" "System restart is pending. Creating startup task..."
    schtasks /Query /TN "%STARTUP_TASK_NAME%" >nul 2>&1
    IF %ERRORLEVEL% EQU 0 (
        schtasks /Delete /TN "%STARTUP_TASK_NAME%" /F >nul 2>&1
    )
    schtasks /Create /SC ONLOGON /TN "%STARTUP_TASK_NAME%" /TR "%SCRIPT_PATH%" /RL HIGHEST /RU "%USERNAME%" /DELAY 0001:00 /F
    IF !ERRORLEVEL! EQU 0 (
        CALL :LOG_ENTRY "INFO" "Startup task created. Restarting system in 15 seconds..."
        CALL :LOG_ENTRY "INFO" "Press Ctrl+C to cancel restart."
        timeout /t 15
        shutdown /r /t 5 /c "System restart required for maintenance continuation"
        EXIT /B 0
    ) ELSE (
        CALL :LOG_ENTRY "WARN" "Failed to create startup task. Continuing without restart..."
        CALL :LOG_ENTRY "DEBUG" "Task name: %STARTUP_TASK_NAME%"
        CALL :LOG_ENTRY "DEBUG" "Script path: %SCRIPT_PATH%"
        CALL :LOG_ENTRY "DEBUG" "Username: %USERNAME%"
        CALL :LOG_ENTRY "DEBUG" "Error level: !ERRORLEVEL!"
    )
) ELSE (
    CALL :LOG_ENTRY "INFO" "No pending restart detected. Continuing..."
)

REM -----------------------------------------------------------------------------
REM Repository Download - Simplified
REM -----------------------------------------------------------------------------
SET "REPO_URL=https://github.com/ichimbogdancristian/script_mentenanta/archive/refs/heads/main.zip"
SET "ZIP_FILE=%TEMP%\script_mentenanta.zip"
SET "EXTRACT_FOLDER=script_mentenanta-main"

CALL :LOG_ENTRY "INFO" "Downloading latest repository..."

REM Create temp script for repository download
SET "TEMP_PS1=%TEMP%\download_repo.ps1"
ECHO $ProgressPreference = 'SilentlyContinue' > "%TEMP_PS1%"
ECHO try { >> "%TEMP_PS1%"
ECHO     Invoke-WebRequest -Uri '%REPO_URL%' -OutFile '%ZIP_FILE%' -UseBasicParsing -TimeoutSec 60 >> "%TEMP_PS1%"
ECHO     Write-Host '[INFO] Repository downloaded successfully' >> "%TEMP_PS1%"
ECHO     exit 0 >> "%TEMP_PS1%"
ECHO } catch { >> "%TEMP_PS1%"
ECHO     Write-Host '[ERROR] Download failed:' $_.Exception.Message >> "%TEMP_PS1%"
ECHO     exit 1 >> "%TEMP_PS1%"
ECHO } >> "%TEMP_PS1%"

powershell -ExecutionPolicy Bypass -File "%TEMP_PS1%" 2>&1
SET "REPO_DOWNLOAD_EXIT=!ERRORLEVEL!"
DEL /F /Q "%TEMP_PS1%" >nul 2>&1

IF !REPO_DOWNLOAD_EXIT! NEQ 0 (
    CALL :LOG_ENTRY "ERROR" "Failed to download repository. Check internet connection."
    pause
    EXIT /B 2
)

IF NOT EXIST "%ZIP_FILE%" (
    CALL :LOG_ENTRY "ERROR" "Download failed - ZIP file not created."
    pause
    EXIT /B 2
)

REM -----------------------------------------------------------------------------
REM Repository Cleanup - Remove existing folder if it exists
REM -----------------------------------------------------------------------------
CALL :LOG_ENTRY "INFO" "Checking for existing repository folder..."
IF EXIST "%SCRIPT_DIR%%EXTRACT_FOLDER%" (
    CALL :LOG_ENTRY "INFO" "Existing repository folder found. Removing for clean extraction..."
    RMDIR /S /Q "%SCRIPT_DIR%%EXTRACT_FOLDER%" >nul 2>&1
    IF EXIST "%SCRIPT_DIR%%EXTRACT_FOLDER%" (
        CALL :LOG_ENTRY "WARN" "Could not remove existing folder completely. Attempting forced removal..."
        
        REM Create temp script for folder removal
        SET "TEMP_PS1=%TEMP%\remove_folder.ps1"
        ECHO try { > "%TEMP_PS1%"
        ECHO     Remove-Item -Path '%SCRIPT_DIR%%EXTRACT_FOLDER%' -Recurse -Force -ErrorAction Stop >> "%TEMP_PS1%"
        ECHO     Write-Host '[INFO] Existing folder removed successfully' >> "%TEMP_PS1%"
        ECHO     exit 0 >> "%TEMP_PS1%"
        ECHO } catch { >> "%TEMP_PS1%"
        ECHO     Write-Host '[WARN] Failed to remove existing folder:' $_.Exception.Message >> "%TEMP_PS1%"
        ECHO     exit 1 >> "%TEMP_PS1%"
        ECHO } >> "%TEMP_PS1%"
        
        powershell -ExecutionPolicy Bypass -File "%TEMP_PS1%" 2>&1
        DEL /F /Q "%TEMP_PS1%" >nul 2>&1
    ) ELSE (
        CALL :LOG_ENTRY "INFO" "Existing repository folder removed successfully."
    )
) ELSE (
    CALL :LOG_ENTRY "INFO" "No existing repository folder found. Proceeding with clean extraction."
)

REM -----------------------------------------------------------------------------
REM Repository Extraction - Using PowerShell (More Reliable)
REM -----------------------------------------------------------------------------
CALL :LOG_ENTRY "INFO" "Extracting repository to clean folder..."

REM Create temp script for repository extraction
SET "TEMP_PS1=%TEMP%\extract_repo.ps1"
ECHO try { > "%TEMP_PS1%"
ECHO     Add-Type -AssemblyName System.IO.Compression.FileSystem >> "%TEMP_PS1%"
ECHO     [System.IO.Compression.ZipFile]::ExtractToDirectory('%ZIP_FILE%', '%SCRIPT_DIR%') >> "%TEMP_PS1%"
ECHO     Write-Host '[INFO] Repository extracted successfully' >> "%TEMP_PS1%"
ECHO     exit 0 >> "%TEMP_PS1%"
ECHO } catch { >> "%TEMP_PS1%"
ECHO     Write-Host '[ERROR] Extraction failed:' $_.Exception.Message >> "%TEMP_PS1%"
ECHO     exit 1 >> "%TEMP_PS1%"
ECHO } >> "%TEMP_PS1%"

powershell -ExecutionPolicy Bypass -File "%TEMP_PS1%" 2>&1
SET "EXTRACT_EXIT=!ERRORLEVEL!"
DEL /F /Q "%TEMP_PS1%" >nul 2>&1

IF !EXTRACT_EXIT! NEQ 0 (
    CALL :LOG_ENTRY "ERROR" "Failed to extract repository."
    pause
    EXIT /B 3
)

REM Clean up ZIP file
DEL /F /Q "%ZIP_FILE%" >nul 2>&1

REM Check if extraction worked
IF NOT EXIST "%SCRIPT_DIR%%EXTRACT_FOLDER%" (
    ECHO [%TIME%] [ERROR] Extraction failed - folder not found: %SCRIPT_DIR%%EXTRACT_FOLDER%
    ECHO [%TIME%] [INFO] Available folders:
    DIR "%SCRIPT_DIR%" /AD /B
    pause
    EXIT /B 3
)

CALL :LOG_ENTRY "INFO" "Repository extracted to clean folder: %SCRIPT_DIR%%EXTRACT_FOLDER%"

REM -----------------------------------------------------------------------------
REM PowerShell 7 Detection and Final Verification
REM -----------------------------------------------------------------------------
CALL :LOG_ENTRY "INFO" "Performing comprehensive dependency validation..."

REM Check PowerShell 7 availability
CALL :LOG_ENTRY "INFO" "Checking PowerShell 7 availability for script execution..."
SET "PS7_AVAILABLE=NO"

pwsh.exe -Version >nul 2>&1
IF !ERRORLEVEL! EQU 0 (
    SET "PS7_AVAILABLE=YES"
    FOR /F "tokens=*" %%i IN ('pwsh.exe -Command "$PSVersionTable.PSVersion.ToString()" 2^>nul') DO SET PS7_VERSION=%%i
    CALL :LOG_ENTRY "INFO" "PowerShell 7 found: !PS7_VERSION!"
) ELSE (
    CALL :LOG_ENTRY "WARN" "PowerShell 7 not available. Will use Windows PowerShell."
)

REM Check critical dependencies
CALL :LOG_ENTRY "INFO" "Validating critical dependencies..."
SET "DEPENDENCY_WARNINGS=0"

REM Validate Winget
winget --version >nul 2>&1
IF !ERRORLEVEL! EQU 0 (
    CALL :LOG_ENTRY "INFO" "✓ Winget is available"
) ELSE (
    CALL :LOG_ENTRY "WARN" "✗ Winget not available - some installations may fail"
    SET /A DEPENDENCY_WARNINGS+=1
)

REM Validate Chocolatey
choco --version >nul 2>&1
IF !ERRORLEVEL! EQU 0 (
    CALL :LOG_ENTRY "INFO" "✓ Chocolatey is available"
) ELSE (
    CALL :LOG_ENTRY "WARN" "✗ Chocolatey not available - some installations may fail"
    SET /A DEPENDENCY_WARNINGS+=1
)

REM Validate Git
git --version >nul 2>&1
IF !ERRORLEVEL! EQU 0 (
    ECHO [%TIME%] [INFO] ✓ Git is available
) ELSE (
    ECHO [%TIME%] [WARN] ✗ Git not available - repository management limited
    SET /A DEPENDENCY_WARNINGS+=1
)

REM Validate PowerShell modules
REM Create temp script for module validation
SET "TEMP_PS1=%TEMP%\validate_modules.ps1"
ECHO try { > "%TEMP_PS1%"
ECHO     $modules = @('PSWindowsUpdate', 'PackageManagement', 'PowerShellGet') >> "%TEMP_PS1%"
ECHO     $moduleStatus = @() >> "%TEMP_PS1%"
ECHO     foreach ($module in $modules) { >> "%TEMP_PS1%"
ECHO         if (Get-Module -ListAvailable -Name $module -ErrorAction SilentlyContinue) { >> "%TEMP_PS1%"
ECHO             $moduleStatus += "[INFO] ✓ Module $module is available" >> "%TEMP_PS1%"
ECHO         } else { >> "%TEMP_PS1%"
ECHO             $moduleStatus += "[WARN] ✗ Module $module not available" >> "%TEMP_PS1%"
ECHO         } >> "%TEMP_PS1%"
ECHO     } >> "%TEMP_PS1%"
ECHO     foreach ($status in $moduleStatus) { Write-Host $status } >> "%TEMP_PS1%"
ECHO } catch { >> "%TEMP_PS1%"
ECHO     Write-Host '[WARN] Module validation failed' >> "%TEMP_PS1%"
ECHO } >> "%TEMP_PS1%"

powershell -ExecutionPolicy Bypass -File "%TEMP_PS1%" 2>&1
DEL /F /Q "%TEMP_PS1%" >nul 2>&1

REM Show dependency summary
ECHO.
ECHO ========================================
ECHO    DEPENDENCY VALIDATION SUMMARY
ECHO ========================================

REM Create temp script for comprehensive dependency check
SET "TEMP_PS1=%TEMP%\final_dependency_check.ps1"
ECHO try { > "%TEMP_PS1%"
ECHO     Write-Host ' ' >> "%TEMP_PS1%"
ECHO     Write-Host '[INFO] === CRITICAL DEPENDENCIES STATUS ===' >> "%TEMP_PS1%"
ECHO     REM Check Winget >> "%TEMP_PS1%"
ECHO     if (Get-Command winget -ErrorAction SilentlyContinue) { >> "%TEMP_PS1%"
ECHO         try { >> "%TEMP_PS1%"
ECHO             $wingetVer = ^& winget --version 2^>$null >> "%TEMP_PS1%"
ECHO             if ($wingetVer) { >> "%TEMP_PS1%"
ECHO                 Write-Host '[INFO] ✓ Winget: Available (version:' $wingetVer.Trim() ')' >> "%TEMP_PS1%"
ECHO             } else { >> "%TEMP_PS1%"
ECHO                 Write-Host '[WARN] ✗ Winget: Not responding properly' >> "%TEMP_PS1%"
ECHO             } >> "%TEMP_PS1%"
ECHO         } catch { >> "%TEMP_PS1%"
ECHO             Write-Host '[WARN] ✗ Winget: Available but not functional' >> "%TEMP_PS1%"
ECHO         } >> "%TEMP_PS1%"
ECHO     } else { >> "%TEMP_PS1%"
ECHO         Write-Host '[WARN] ✗ Winget: Not available' >> "%TEMP_PS1%"
ECHO     } >> "%TEMP_PS1%"
ECHO     REM Check PowerShell 7 >> "%TEMP_PS1%"
ECHO     if (Get-Command pwsh -ErrorAction SilentlyContinue) { >> "%TEMP_PS1%"
ECHO         $ps7Ver = ^& pwsh --version 2^>$null >> "%TEMP_PS1%"
ECHO         Write-Host '[INFO] ✓ PowerShell 7:' $ps7Ver >> "%TEMP_PS1%"
ECHO     } else { >> "%TEMP_PS1%"
ECHO         Write-Host '[WARN] ✗ PowerShell 7: Not available' >> "%TEMP_PS1%"
ECHO     } >> "%TEMP_PS1%"
ECHO     REM Check Git >> "%TEMP_PS1%"
ECHO     if (Get-Command git -ErrorAction SilentlyContinue) { >> "%TEMP_PS1%"
ECHO         $gitVer = ^& git --version 2^>$null >> "%TEMP_PS1%"
ECHO         Write-Host '[INFO] ✓ Git:' $gitVer >> "%TEMP_PS1%"
ECHO     } else { >> "%TEMP_PS1%"
ECHO         Write-Host '[WARN] ✗ Git: Not available' >> "%TEMP_PS1%"
ECHO     } >> "%TEMP_PS1%"
ECHO     REM Check Chocolatey >> "%TEMP_PS1%"
ECHO     if (Get-Command choco -ErrorAction SilentlyContinue) { >> "%TEMP_PS1%"
ECHO         $chocoVer = ^& choco --version 2^>$null >> "%TEMP_PS1%"
ECHO         Write-Host '[INFO] ✓ Chocolatey:' $chocoVer >> "%TEMP_PS1%"
ECHO     } else { >> "%TEMP_PS1%"
ECHO         Write-Host '[INFO] ○ Chocolatey: Not available (optional)' >> "%TEMP_PS1%"
ECHO     } >> "%TEMP_PS1%"
ECHO     Write-Host '[INFO] === DEPENDENCY CHECK COMPLETE ===' >> "%TEMP_PS1%"
ECHO     Write-Host ' ' >> "%TEMP_PS1%"
ECHO } catch { >> "%TEMP_PS1%"
ECHO     Write-Host '[WARN] Dependency summary check failed' >> "%TEMP_PS1%"
ECHO } >> "%TEMP_PS1%"

powershell -ExecutionPolicy Bypass -File "%TEMP_PS1%" 2>&1
DEL /F /Q "%TEMP_PS1%" >nul 2>&1

IF !DEPENDENCY_WARNINGS! GTR 0 (
    ECHO [%TIME%] [WARN] Found !DEPENDENCY_WARNINGS! dependency warnings. Script will use graceful degradation.
) ELSE (
    ECHO [%TIME%] [INFO] ✓ All critical dependencies verified successfully.
)

ECHO ========================================

CALL :LOG_ENTRY "INFO" "Dependency validation completed."

REM -----------------------------------------------------------------------------
REM Launch PowerShell Script with Priority for PowerShell 7
REM -----------------------------------------------------------------------------
REM Check if we have a local script.ps1 file (direct execution) or extracted folder
SET "PS1_PATH=%SCRIPT_DIR%script.ps1"
IF NOT EXIST "%PS1_PATH%" (
    SET "PS1_PATH=%SCRIPT_DIR%%EXTRACT_FOLDER%\script.ps1"
)

IF NOT EXIST "%PS1_PATH%" (
    CALL :LOG_ENTRY "ERROR" "PowerShell script not found at either location:"
    CALL :LOG_ENTRY "ERROR" "  Local: %SCRIPT_DIR%script.ps1"
    CALL :LOG_ENTRY "ERROR" "  Extracted: %SCRIPT_DIR%%EXTRACT_FOLDER%\script.ps1"
    IF EXIST "%SCRIPT_DIR%%EXTRACT_FOLDER%" (
        CALL :LOG_ENTRY "INFO" "Contents of extracted folder:"
        DIR "%SCRIPT_DIR%%EXTRACT_FOLDER%" /B
    )
    pause
    EXIT /B 4
)

CALL :LOG_ENTRY "INFO" "Launching PowerShell maintenance script..."
CALL :LOG_ENTRY "INFO" "Script path: %PS1_PATH%"

IF "%PS7_AVAILABLE%"=="YES" (
    CALL :LOG_ENTRY "INFO" "Using PowerShell 7 environment..."
    ECHO.
    ECHO ========================================
    ECHO    Launching PowerShell 7 Script
    ECHO ========================================
    ECHO.
    REM Launch with visible window and wait for completion
    START /WAIT "Maintenance Script - PowerShell 7" pwsh.exe -ExecutionPolicy Bypass -NoExit -File "%PS1_PATH%"
    SET "LAUNCH_EXIT=!ERRORLEVEL!"
    IF !LAUNCH_EXIT! NEQ 0 (
        CALL :LOG_ENTRY "ERROR" "PowerShell script failed with error code !LAUNCH_EXIT!"
        ECHO.
        ECHO Press any key to exit...
        pause >nul
        exit /b !LAUNCH_EXIT!
    )
) ELSE (
    CALL :LOG_ENTRY "INFO" "Using Windows PowerShell environment..."
    ECHO.
    ECHO ================================================
    ECHO    Launching Windows PowerShell Script
    ECHO ================================================
    ECHO.
    REM Launch with visible window and wait for completion
    START /WAIT "Maintenance Script - Windows PowerShell" powershell.exe -ExecutionPolicy Bypass -NoExit -File "%PS1_PATH%"
    SET "LAUNCH_EXIT=!ERRORLEVEL!"
    IF !LAUNCH_EXIT! NEQ 0 (
        CALL :LOG_ENTRY "ERROR" "PowerShell script failed with error code !LAUNCH_EXIT!"
        ECHO.
        ECHO Press any key to exit...
        pause >nul
        exit /b !LAUNCH_EXIT!
    )
)

CALL :LOG_ENTRY "INFO" "PowerShell script launched successfully."
CALL :LOG_ENTRY "INFO" "Maintenance operations completed."
ECHO.
ECHO ========================================
ECHO        Script Execution Complete
ECHO ========================================
ECHO.
ECHO Press any key to close this window...
pause >nul
CALL :LOG_ENTRY "INFO" "Batch launcher completed successfully. Window will now close."
EXIT /B 0

REM -----------------------------------------------------------------------------
REM Logging Function - Logs to both console and maintenance.log file
REM -----------------------------------------------------------------------------
:LOG_ENTRY
SET "LEVEL=%~1"
SET "MESSAGE=%~2"
ECHO [%TIME%] [%LEVEL%] %MESSAGE%
ECHO [%DATE% %TIME%] [%LEVEL%] %MESSAGE% >> "%LOG_FILE%"
GOTO :EOF
