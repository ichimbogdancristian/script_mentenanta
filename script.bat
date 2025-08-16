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
REM Log file is in the same directory as script.bat (main directory)
SET "LOG_FILE=%SCRIPT_DIR%maintenance.log"

REM Create or append to maintenance.log
ECHO [%DATE% %TIME%] [INFO] ============================================================ >> "%LOG_FILE%"
ECHO [%DATE% %TIME%] [INFO] Starting Windows Maintenance Automation Script >> "%LOG_FILE%"
ECHO [%DATE% %TIME%] [INFO] Batch Script: %SCRIPT_PATH% >> "%LOG_FILE%"
ECHO [%DATE% %TIME%] [INFO] Batch Script Directory: %SCRIPT_DIR% >> "%LOG_FILE%"
ECHO [%DATE% %TIME%] [INFO] Log File: %LOG_FILE% >> "%LOG_FILE%"
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
    IF %ERRORLEVEL% EQU 0 (
        CALL :LOG_ENTRY "INFO" "Monthly scheduled task created successfully."
        schtasks /Query /TN "%TASK_NAME%" /V >nul 2>&1
        IF %ERRORLEVEL% EQU 0 (
            CALL :LOG_ENTRY "INFO" "Task verification successful."
            FOR /F "tokens=2 delims=:" %%i IN ('schtasks /Query /TN "%TASK_NAME%" /FO LIST ^| findstr /C:"Next Run Time"') DO (
                CALL :LOG_ENTRY "INFO" "Next scheduled run: %%i"
            )
        ) ELSE (
            CALL :LOG_ENTRY "WARN" "Task created but verification failed."
        )
    ) ELSE (
        CALL :LOG_ENTRY "ERROR" "Failed to create monthly scheduled task. Error code: %ERRORLEVEL%"
    )
)

REM -----------------------------------------------------------------------------
REM Startup Task Management and Restart Detection Logic
REM Step 1: Check if startup task exists - if yes, delete it
REM Step 2: Check for pending restarts using comprehensive detection
REM Step 3: If pending restarts found, create startup task with 1-minute delay
REM Step 4: Restart the system
REM -----------------------------------------------------------------------------

REM Step 1: Check and remove existing startup task if it exists
CALL :LOG_ENTRY "INFO" "Step 1: Checking startup task '%STARTUP_TASK_NAME%'..."
schtasks /Query /TN "%STARTUP_TASK_NAME%" >nul 2>&1
IF %ERRORLEVEL% EQU 0 (
    CALL :LOG_ENTRY "INFO" "Existing startup task found. Removing..."
    schtasks /Delete /TN "%STARTUP_TASK_NAME%" /F >nul 2>&1
    IF %ERRORLEVEL% EQU 0 (
        CALL :LOG_ENTRY "INFO" "Startup task removed successfully."
    ) ELSE (
        CALL :LOG_ENTRY "WARN" "Failed to remove startup task, but continuing..."
    )
) ELSE (
    CALL :LOG_ENTRY "INFO" "No existing startup task found."
)

REM Step 2: Comprehensive restart detection - Using individual checks
CALL :LOG_ENTRY "INFO" "Step 2: Checking for pending system restarts..."
SET "RESTART_NEEDED=NO"
SET "RESTART_COUNT=0"

REM Check Windows Update reboot flag
REG QUERY "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired" >nul 2>&1
IF %ERRORLEVEL% EQU 0 (
    SET "RESTART_NEEDED=YES"
    SET /A RESTART_COUNT+=1
    CALL :LOG_ENTRY "INFO" "Windows Update reboot flag detected"
)

REM Check Component Based Servicing reboot flag
REG QUERY "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending" >nul 2>&1
IF %ERRORLEVEL% EQU 0 (
    SET "RESTART_NEEDED=YES"
    SET /A RESTART_COUNT+=1
    CALL :LOG_ENTRY "INFO" "Component Based Servicing reboot detected"
)

REM Check pending file operations
REG QUERY "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager" /v PendingFileRenameOperations >nul 2>&1
IF %ERRORLEVEL% EQU 0 (
    SET "RESTART_NEEDED=YES"
    SET /A RESTART_COUNT+=1
    CALL :LOG_ENTRY "INFO" "Pending file operations detected"
)

REM Check Windows Feature installation requiring restart
REG QUERY "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\PackagesPending" >nul 2>&1
IF %ERRORLEVEL% EQU 0 (
    SET "RESTART_NEEDED=YES"
    SET /A RESTART_COUNT+=1
    CALL :LOG_ENTRY "INFO" "Windows Features pending restart detected"
)

REM Check for computer name change using simple approach
FOR /F "tokens=3" %%A IN ('REG QUERY "HKLM\SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName" /v ComputerName 2^>nul') DO SET "CURRENT_NAME=%%A"
FOR /F "tokens=3" %%B IN ('REG QUERY "HKLM\SYSTEM\CurrentControlSet\Control\ComputerName\ActiveComputerName" /v ComputerName 2^>nul') DO SET "ACTIVE_NAME=%%B"
IF NOT "%CURRENT_NAME%"=="%ACTIVE_NAME%" (
    SET "RESTART_NEEDED=YES"
    SET /A RESTART_COUNT+=1
    CALL :LOG_ENTRY "INFO" "Computer name change pending restart detected"
)

REM Debug and proceed with restart logic
CALL :LOG_ENTRY "DEBUG" "RESTART_NEEDED=%RESTART_NEEDED%, RESTART_COUNT=%RESTART_COUNT%"

REM Step 3 & 4: Handle restart using simple conditional logic
IF "%RESTART_NEEDED%"=="YES" (
    CALL :LOG_ENTRY "WARN" "System restart required - %RESTART_COUNT% conditions detected"
    CALL :LOG_ENTRY "INFO" "Step 3: Creating startup task for post-restart continuation..."
    
    REM Show task creation parameters
    CALL :LOG_ENTRY "DEBUG" "Task name: %STARTUP_TASK_NAME%"
    CALL :LOG_ENTRY "DEBUG" "Script path: %SCRIPT_PATH%"
    CALL :LOG_ENTRY "DEBUG" "User: %USERNAME%"
    
    REM Create startup task - simplified command
    schtasks /Create /SC ONLOGON /TN "%STARTUP_TASK_NAME%" /TR "%SCRIPT_PATH%" /RL HIGHEST /RU "%USERNAME%" /DELAY 0001:00 /F
    IF %ERRORLEVEL% EQU 0 (
        CALL :LOG_ENTRY "INFO" "Startup task created successfully"
        CALL :LOG_ENTRY "INFO" "Step 4: Initiating system restart in 20 seconds..."
        ECHO.
        ECHO =====================================================
        ECHO   SYSTEM RESTART REQUIRED
        ECHO   %RESTART_COUNT% restart conditions detected
        ECHO   Restarting in 20 seconds...
        ECHO   Press Ctrl+C to abort restart
        ECHO =====================================================
        ECHO.
        timeout /t 20
        shutdown /r /t 5 /c "System restart required for maintenance"
        EXIT /B 0
    ) ELSE (
        CALL :LOG_ENTRY "ERROR" "Failed to create startup task (Error: %ERRORLEVEL%)"
        CALL :LOG_ENTRY "INFO" "Continuing without restart..."
    )
) ELSE (
    CALL :LOG_ENTRY "INFO" "No pending restart detected. Continuing with maintenance..."
)
    CALL :LOG_ENTRY "INFO" "No pending restart detected. Continuing with maintenance..."
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

REM Simple check using registry
REG QUERY "HKLM\SOFTWARE\Classes\Installer\Dependencies" /s | FIND "Microsoft Visual C++ 2015-2022 Redistributable" >nul 2>&1
IF %ERRORLEVEL% EQU 0 (
    CALL :LOG_ENTRY "INFO" "Visual C++ Redistributable is already installed, skipping installation."
) ELSE (
    CALL :LOG_ENTRY "INFO" "Installing Visual C++ Redistributable..."
    
    REM Download and install in one command
    powershell -Command "try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; $file = '$env:TEMP\vc_redist.exe'; Invoke-WebRequest -Uri 'https://aka.ms/vs/17/release/vc_redist.x64.exe' -OutFile $file -UseBasicParsing; Start-Process $file -ArgumentList '/quiet /norestart' -Wait; Remove-Item $file -Force; Write-Host '[INFO] Visual C++ installed successfully' } catch { Write-Host '[ERROR] Visual C++ install failed:' $_.Exception.Message }"
    
    CALL :LOG_ENTRY "INFO" "Visual C++ Redistributable installation completed."
)

REM -----------------------------------------------------------------------------
REM 1B. Microsoft.UI.Xaml Framework - Skipped (handled by Winget installer)
CALL :LOG_ENTRY "INFO" "PHASE 1B: Sapplykipping Microsoft.UI.Xaml; Winget installer will handle dependencies if required."

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

REM Simple Winget check and install
winget --version >nul 2>&1
IF %ERRORLEVEL% EQU 0 (
    CALL :LOG_ENTRY "INFO" "Winget is already installed and functional."
    SET "WINGET_AVAILABLE=YES"
) ELSE (
    CALL :LOG_ENTRY "INFO" "Installing Winget..."
    
    REM Try to install Winget using PowerShell in one command
    powershell -Command "try { Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe; Write-Host '[INFO] Winget registered successfully' } catch { try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; $url = 'https://github.com/microsoft/winget-cli/releases/latest/download/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle'; $file = '$env:TEMP\winget.msixbundle'; Invoke-WebRequest -Uri $url -OutFile $file -UseBasicParsing; Add-AppxPackage -Path $file; Remove-Item $file -Force; Write-Host '[INFO] Winget installed successfully' } catch { Write-Host '[ERROR] Winget install failed:' $_.Exception.Message } }"
    
    REM Check if Winget is now available
    timeout /t 3 /nobreak >nul
    winget --version >nul 2>&1
    IF %ERRORLEVEL% EQU 0 (
        CALL :LOG_ENTRY "INFO" "Winget is now available and functional."
        SET "WINGET_AVAILABLE=YES"
    ) ELSE (
        CALL :LOG_ENTRY "WARN" "Winget installation failed - will use alternative methods."
        SET "WINGET_AVAILABLE=NO"
    )
)

REM -----------------------------------------------------------------------------
REM Winget Final Validation
REM -----------------------------------------------------------------------------
CALL :LOG_ENTRY "INFO" "Validating Winget functionality..."

REM Simple validation
winget source list >nul 2>&1
IF %ERRORLEVEL% EQU 0 (
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
CALL :LOG_ENTRY "INFO" "PHASE 3A: Installing PowerShell 7..."

REM Simple PowerShell 7 check and install
pwsh.exe -Version >nul 2>&1
IF %ERRORLEVEL% EQU 0 (
    FOR /F "tokens=*" %%i IN ('pwsh.exe -Command "$PSVersionTable.PSVersion.ToString()" 2^>nul') DO SET PS7_VERSION=%%i
    CALL :LOG_ENTRY "INFO" "PowerShell 7 already available: !PS7_VERSION!"
    SET "PS7_AVAILABLE=YES"
) ELSE (
    CALL :LOG_ENTRY "INFO" "Installing PowerShell 7..."
    
    REM Try Winget first, then fallback to direct download
    IF "%WINGET_AVAILABLE%"=="YES" (
        CALL :LOG_ENTRY "INFO" "Attempting PowerShell 7 installation via Winget..."
        winget install --id Microsoft.PowerShell --silent --accept-package-agreements --accept-source-agreements >nul 2>&1
        IF %ERRORLEVEL% EQU 0 (
            CALL :LOG_ENTRY "INFO" "PowerShell 7 installed successfully via Winget."
        ) ELSE (
            CALL :LOG_ENTRY "WARN" "Winget install failed, trying direct download..."
            CALL :INSTALL_PS7_DIRECT
        )
    ) ELSE (
        CALL :LOG_ENTRY "INFO" "Installing PowerShell 7 via direct download..."
        CALL :INSTALL_PS7_DIRECT
    )
    
    REM Update PATH and check if PowerShell 7 is now available
    SET "PATH=%PATH%;%ProgramFiles%\PowerShell\7"
    timeout /t 3 /nobreak >nul
    pwsh.exe -Version >nul 2>&1
    IF %ERRORLEVEL% EQU 0 (
        FOR /F "tokens=*" %%i IN ('pwsh.exe -Command "$PSVersionTable.PSVersion.ToString()" 2^>nul') DO SET PS7_VERSION=%%i
        CALL :LOG_ENTRY "INFO" "PowerShell 7 is now functional: !PS7_VERSION!"
        SET "PS7_AVAILABLE=YES"
    ) ELSE (
        CALL :LOG_ENTRY "WARN" "PowerShell 7 installation completed but may require restart."
        SET "PS7_AVAILABLE=NO"
    )
)

:SKIP_PS7_INSTALL

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

REM Simple NuGet PackageProvider check and install - Fully unattended
powershell -Command "try { if (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue) { Write-Host '[INFO] NuGet PackageProvider already available' } else { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; $env:PackageManagementProvider_ConfirmInstall = 'Y'; $env:NUGET_XMLDOC_MODE = 'skip'; [System.Environment]::SetEnvironmentVariable('NUGET_XMLDOC_MODE', 'skip', 'Process'); Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope AllUsers -Confirm:`$false -SkipPublisherCheck -AllowClobber -ForceBootstrap; Write-Host '[INFO] NuGet PackageProvider installed successfully' } } catch { Write-Host '[WARN] Failed to install NuGet PackageProvider:' `$_.Exception.Message }"

CALL :LOG_ENTRY "INFO" "NuGet PackageProvider setup completed."

REM -----------------------------------------------------------------------------
REM 4B. PowerShell Gallery Configuration - Required for module downloads
REM -----------------------------------------------------------------------------
CALL :LOG_ENTRY "INFO" "PHASE 4B: Configuring PowerShell Gallery..."

REM Simple PowerShell Gallery configuration
powershell -Command "try { if ((Get-PSRepository -Name 'PSGallery' -ErrorAction SilentlyContinue).InstallationPolicy -eq 'Trusted') { Write-Host '[INFO] PowerShell Gallery already configured as trusted' } else { Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted -Force; Write-Host '[INFO] PowerShell Gallery configured as trusted' } } catch { Write-Host '[WARN] Failed to configure PowerShell Gallery:' `$_.Exception.Message }"

CALL :LOG_ENTRY "INFO" "PowerShell Gallery configuration completed."

REM -----------------------------------------------------------------------------
REM 4C. PSWindowsUpdate Module - PowerShell module for Windows Updates
REM -----------------------------------------------------------------------------
CALL :LOG_ENTRY "INFO" "PHASE 4C: Installing PSWindowsUpdate module..."

REM Simple PSWindowsUpdate module check and install - Fully unattended
powershell -Command "try { if (Get-Module -ListAvailable -Name PSWindowsUpdate -ErrorAction SilentlyContinue) { Write-Host '[INFO] PSWindowsUpdate module already available' } else { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; `$ProgressPreference = 'SilentlyContinue'; Install-Module -Name PSWindowsUpdate -Force -Scope AllUsers -AllowClobber -Confirm:`$false -Repository PSGallery -SkipPublisherCheck -AcceptLicense; Write-Host '[INFO] PSWindowsUpdate module installed successfully' } } catch { Write-Host '[WARN] Failed to install PSWindowsUpdate module:' `$_.Exception.Message }"

CALL :LOG_ENTRY "INFO" "PSWindowsUpdate module setup completed."

REM -----------------------------------------------------------------------------
REM 4D. Chocolatey Package Manager - Alternative package manager
REM -----------------------------------------------------------------------------
CALL :LOG_ENTRY "INFO" "Installing Chocolatey package manager..."

REM Simple Chocolatey check and install
choco --version >nul 2>&1
IF %ERRORLEVEL% EQU 0 (
    CALL :LOG_ENTRY "INFO" "Chocolatey is already installed."
) ELSE (
    CALL :LOG_ENTRY "INFO" "Installing Chocolatey..."
    
    REM Install Chocolatey using one-liner
    powershell -Command "try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Set-ExecutionPolicy Bypass -Scope Process -Force; $env:ChocolateyInstall = '$env:ProgramData\chocolatey'; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1')); Write-Host '[INFO] Chocolatey installed successfully' } catch { Write-Host '[WARN] Chocolatey installation failed:' $_.Exception.Message }"
    
    REM Update PATH and verify
    SET "PATH=%PATH%;%ProgramData%\chocolatey\bin"
    choco --version >nul 2>&1
    IF %ERRORLEVEL% EQU 0 (
        CALL :LOG_ENTRY "INFO" "Chocolatey installation completed successfully."
    ) ELSE (
        CALL :LOG_ENTRY "WARN" "Chocolatey installation failed, but continuing..."
    )
)

REM -----------------------------------------------------------------------------
REM 4E. PowerShellGet and PackageManagement - Latest Versions
REM -----------------------------------------------------------------------------
CALL :LOG_ENTRY "INFO" "PHASE 4E: Checking PowerShellGet and PackageManagement modules..."

REM Simple PowerShellGet and PackageManagement update
powershell -Command "try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; $psGet = (Get-Module -ListAvailable PowerShellGet | Sort-Object Version -Descending | Select-Object -First 1); if ($psGet -and $psGet.Version -ge '2.2.5') { Write-Host '[INFO] PowerShellGet is up to date' } else { Install-Module -Name PowerShellGet -Force -Scope AllUsers -AllowClobber -Confirm:$false -Repository PSGallery; Write-Host '[INFO] PowerShellGet updated successfully' } } catch { Write-Host '[WARN] PowerShellGet update failed:' $_.Exception.Message }"

powershell -Command "try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; $pkgMgmt = (Get-Module -ListAvailable PackageManagement | Sort-Object Version -Descending | Select-Object -First 1); if ($pkgMgmt -and $pkgMgmt.Version -ge '1.4.8') { Write-Host '[INFO] PackageManagement is up to date' } else { Install-Module -Name PackageManagement -Force -Scope AllUsers -AllowClobber -Confirm:$false -Repository PSGallery; Write-Host '[INFO] PackageManagement updated successfully' } } catch { Write-Host '[WARN] PackageManagement update failed:' $_.Exception.Message }"

CALL :LOG_ENTRY "INFO" "PowerShell modules setup completed."

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

REM Unified .NET Framework installation (works with or without Winget)
powershell -Command "$ProgressPreference='SilentlyContinue'; try { $netVersion = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full\' -Name Release -ErrorAction SilentlyContinue).Release; if ($netVersion -ge 528040) { Write-Host '[INFO] .NET Framework 4.8.1 or higher already installed' } else { Write-Host '[INFO] Installing .NET Framework 4.8.1...'; if (Get-Command winget -ErrorAction SilentlyContinue) { try { winget install --id Microsoft.DotNet.Framework.DeveloperPack_4 --silent --accept-package-agreements --accept-source-agreements; Write-Host '[INFO] .NET Framework 4.8.1 installed via winget'; exit 0 } catch { Write-Host '[WARN] Winget method failed, using direct download' } }; $dotnetUrl = 'https://go.microsoft.com/fwlink/?LinkId=2203304'; $dotnetFile = $env:TEMP + '\ndp481-web.exe'; Invoke-WebRequest -Uri $dotnetUrl -OutFile $dotnetFile -UseBasicParsing; Start-Process $dotnetFile -ArgumentList '/quiet /norestart' -Wait; Remove-Item $dotnetFile -Force -ErrorAction SilentlyContinue; Write-Host '[INFO] .NET Framework 4.8.1 installation completed' } } catch { Write-Host '[WARN] .NET Framework check failed:' $_.Exception.Message }"

REM -----------------------------------------------------------------------------
REM 11. Additional PowerShell Modules for Enhanced Functionality
REM -----------------------------------------------------------------------------
CALL :LOG_ENTRY "INFO" "Checking additional PowerShell modules..."

powershell -Command "$ProgressPreference='SilentlyContinue'; try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; $modules = @('DISM', 'PnpDevice', 'WindowsSearch'); foreach ($module in $modules) { if (-not (Get-Module -ListAvailable -Name $module -ErrorAction SilentlyContinue)) { try { $null = Import-Module $module -ErrorAction Stop; Write-Host ('[INFO] Module ' + $module + ' verified and available') } catch { Write-Host ('[INFO] Module ' + $module + ' not available - will be loaded when needed') } } else { Write-Host ('[INFO] Module ' + $module + ' already available') } } } catch { Write-Host '[WARN] Module check failed:' $_.Exception.Message }"

REM -----------------------------------------------------------------------------
REM 12. Windows Features - Enable required features
REM -----------------------------------------------------------------------------
CALL :LOG_ENTRY "INFO" "Checking Windows features..."

powershell -Command "$ProgressPreference='SilentlyContinue'; try { $features = @('NetFx3', 'MSMQ-Container', 'IIS-ManagementConsole'); foreach ($feature in $features) { $featureState = Get-WindowsOptionalFeature -Online -FeatureName $feature -ErrorAction SilentlyContinue; if ($featureState) { if ($featureState.State -eq 'Enabled') { Write-Host ('[INFO] Windows feature ' + $feature + ' already enabled') } elseif ($featureState.State -eq 'Disabled') { Write-Host ('[INFO] Enabling Windows feature: ' + $feature); $null = Enable-WindowsOptionalFeature -Online -FeatureName $feature -All -NoRestart -ErrorAction SilentlyContinue; Write-Host ('[INFO] Windows feature ' + $feature + ' enabled successfully') } } else { Write-Host ('[INFO] Windows feature ' + $feature + ' not available on this system') } } } catch { Write-Host '[INFO] Windows features check completed' }"

REM -----------------------------------------------------------------------------
REM 13. System Performance Optimizations
REM -----------------------------------------------------------------------------
CALL :LOG_ENTRY "INFO" "Checking system performance settings..."

powershell -Command "$ProgressPreference='SilentlyContinue'; try { $services = @('Themes', 'UxSms'); foreach ($service in $services) { $svc = Get-Service -Name $service -ErrorAction SilentlyContinue; if ($svc) { if ($svc.StartType -eq 'Automatic') { Write-Host ('[INFO] Service ' + $service + ' already set to Automatic') } else { $null = Set-Service -Name $service -StartupType Automatic -ErrorAction SilentlyContinue; Write-Host ('[INFO] Service ' + $service + ' set to Automatic startup') } } else { Write-Host ('[INFO] Service ' + $service + ' not found on this system') } }; Write-Host '[INFO] System services optimization completed' } catch { Write-Host '[INFO] Service optimization completed with some warnings' }"

CALL :LOG_ENTRY "INFO" "Dependency installation phase completed with comprehensive coverage."

REM -----------------------------------------------------------------------------
REM Note: System restart detection and startup task management is handled 
REM in the "Startup Task Management and Restart Detection Logic" section
REM after monthly task creation (lines ~124-220)
REM -----------------------------------------------------------------------------

REM -----------------------------------------------------------------------------
REM Repository Download - Simplified
REM -----------------------------------------------------------------------------
SET "REPO_URL=https://github.com/ichimbogdancristian/script_mentenanta/archive/refs/heads/main.zip"
SET "ZIP_FILE=%TEMP%\script_mentenanta.zip"
SET "EXTRACT_FOLDER=script_mentenanta-main"

CALL :LOG_ENTRY "INFO" "Downloading latest repository..."

REM Simple repository download
powershell -Command "$ProgressPreference='SilentlyContinue'; try { Invoke-WebRequest -Uri '%REPO_URL%' -OutFile '%ZIP_FILE%' -UseBasicParsing -TimeoutSec 60; Write-Host '[INFO] Repository downloaded successfully'; exit 0 } catch { Write-Host '[ERROR] Download failed:' $_.Exception.Message; exit 1 }"
SET "REPO_DOWNLOAD_EXIT=%ERRORLEVEL%"

IF %REPO_DOWNLOAD_EXIT% NEQ 0 (
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
        
        REM Simple folder removal
        powershell -Command "try { Remove-Item -Path '%SCRIPT_DIR%%EXTRACT_FOLDER%' -Recurse -Force -ErrorAction Stop; Write-Host '[INFO] Existing folder removed successfully'; exit 0 } catch { Write-Host '[WARN] Failed to remove existing folder:' $_.Exception.Message; exit 1 }"
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

REM Simple repository extraction
powershell -Command "try { Add-Type -AssemblyName System.IO.Compression.FileSystem; [System.IO.Compression.ZipFile]::ExtractToDirectory('%ZIP_FILE%', '%SCRIPT_DIR%'); Write-Host '[INFO] Repository extracted successfully'; exit 0 } catch { Write-Host '[ERROR] Extraction failed:' $_.Exception.Message; exit 1 }"
SET "EXTRACT_EXIT=%ERRORLEVEL%"

IF %EXTRACT_EXIT% NEQ 0 (
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
IF %ERRORLEVEL% EQU 0 (
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
IF %ERRORLEVEL% EQU 0 (
    CALL :LOG_ENTRY "INFO" "✓ Winget is available"
) ELSE (
    CALL :LOG_ENTRY "WARN" "✗ Winget not available - some installations may fail"
    SET /A DEPENDENCY_WARNINGS+=1
)

REM Validate Chocolatey
choco --version >nul 2>&1
IF %ERRORLEVEL% EQU 0 (
    CALL :LOG_ENTRY "INFO" "✓ Chocolatey is available"
) ELSE (
    CALL :LOG_ENTRY "WARN" "✗ Chocolatey not available - some installations may fail"
    SET /A DEPENDENCY_WARNINGS+=1
)

REM Validate PowerShell modules
powershell -Command "try { $modules = @('PSWindowsUpdate', 'PackageManagement', 'PowerShellGet'); $moduleStatus = @(); foreach ($module in $modules) { if (Get-Module -ListAvailable -Name $module -ErrorAction SilentlyContinue) { $moduleStatus += '[INFO] ✓ Module ' + $module + ' is available' } else { $moduleStatus += '[WARN] ✗ Module ' + $module + ' not available' } }; foreach ($status in $moduleStatus) { Write-Host $status } } catch { Write-Host '[WARN] Module validation failed' }"

REM Show dependency summary
ECHO.
ECHO ========================================
ECHO    DEPENDENCY VALIDATION SUMMARY
ECHO ========================================

REM Create temp script for comprehensive dependency check
powershell -Command "try { Write-Host ' '; Write-Host '[INFO] === CRITICAL DEPENDENCIES STATUS ==='; if (Get-Command winget -ErrorAction SilentlyContinue) { try { $wingetVer = winget --version 2>$null; if ($wingetVer) { Write-Host '[INFO] ✓ Winget: Available (version:' $wingetVer.Trim() ')' } else { Write-Host '[WARN] ✗ Winget: Not responding properly' } } catch { Write-Host '[WARN] ✗ Winget: Available but not functional' } } else { Write-Host '[WARN] ✗ Winget: Not available' }; if (Get-Command pwsh -ErrorAction SilentlyContinue) { $ps7Ver = pwsh --version 2>$null; Write-Host '[INFO] ✓ PowerShell 7:' $ps7Ver } else { Write-Host '[WARN] ✗ PowerShell 7: Not available' }; if (Get-Command choco -ErrorAction SilentlyContinue) { $chocoVer = choco --version 2>$null; Write-Host '[INFO] ✓ Chocolatey:' $chocoVer } else { Write-Host '[INFO] ○ Chocolatey: Not available (optional)' }; Write-Host '[INFO] === DEPENDENCY CHECK COMPLETE ==='; Write-Host ' ' } catch { Write-Host '[WARN] Dependency summary check failed' }"

IF %DEPENDENCY_WARNINGS% GTR 0 (
    ECHO [%TIME%] [WARN] Found %DEPENDENCY_WARNINGS% dependency warnings. Script will use graceful degradation.
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

REM Set environment variable for PowerShell script to use same log file
SET "SCRIPT_LOG_FILE=%LOG_FILE%"

IF "%PS7_AVAILABLE%"=="YES" (
    CALL :LOG_ENTRY "INFO" "Using PowerShell 7 environment..."
    ECHO.
    ECHO ========================================
    ECHO    Launching PowerShell 7 Script
    ECHO ========================================
    ECHO.
    REM Launch with visible window and wait for completion
    START /WAIT "Maintenance Script - PowerShell 7" pwsh.exe -ExecutionPolicy Bypass -NoExit -File "%PS1_PATH%"
    SET "LAUNCH_EXIT=%ERRORLEVEL%"
    IF %LAUNCH_EXIT% NEQ 0 (
        CALL :LOG_ENTRY "ERROR" "PowerShell script failed with error code %LAUNCH_EXIT%"
        ECHO.
        ECHO Press any key to exit...
        pause >nul
        exit /b %LAUNCH_EXIT%
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
    SET "LAUNCH_EXIT=%ERRORLEVEL%"
    IF %LAUNCH_EXIT% NEQ 0 (
        CALL :LOG_ENTRY "ERROR" "PowerShell script failed with error code %LAUNCH_EXIT%"
        ECHO.
        ECHO Press any key to exit...
        pause >nul
        exit /b %LAUNCH_EXIT%
    )
)

CALL :LOG_ENTRY "INFO" "PowerShell script launched successfully."
CALL :LOG_ENTRY "INFO" "Maintenance operations completed."

REM -----------------------------------------------------------------------------
REM Auto-close countdown with abort option
REM -----------------------------------------------------------------------------
ECHO.
ECHO ========================================
ECHO        Script Execution Complete
ECHO ========================================
ECHO.
ECHO [INFO] All maintenance operations have been completed successfully.
ECHO [INFO] Check maintenance.log and maintenance_report.txt for detailed results.
ECHO.
ECHO ========================================
ECHO        AUTO-CLOSE COUNTDOWN
ECHO ========================================
ECHO.
ECHO This window will automatically close in 20 seconds.
ECHO Press any key to abort the countdown and keep window open.
ECHO.

REM Countdown loop with abort detection
FOR /L %%i IN (20,-1,1) DO (
    SET "COUNTDOWN=%%i"
    IF %COUNTDOWN% LSS 10 (
        ECHO Closing in 0%COUNTDOWN% seconds... ^(Press any key to abort^)
    ) ELSE (
        ECHO Closing in %COUNTDOWN% seconds... ^(Press any key to abort^)
    )
    
    REM Check for key press with 1 second timeout
    timeout /t 1 /nobreak >nul 2>&1
    IF %ERRORLEVEL% NEQ 0 (
        ECHO.
        ECHO [INFO] Countdown aborted by user.
        ECHO [INFO] Window will remain open for manual review.
        ECHO.
        ECHO Press any key to close this window...
        pause >nul
        CALL :LOG_ENTRY "INFO" "Batch launcher completed - countdown aborted by user."
        EXIT /B 0
    )
)

ECHO.
ECHO [INFO] Auto-close timer expired. Closing window...
CALL :LOG_ENTRY "INFO" "Batch launcher completed successfully - auto-closed after countdown."
EXIT /B 0

REM -----------------------------------------------------------------------------
REM -----------------------------------------------------------------------------
REM PowerShell 7 Direct Installation Function
REM -----------------------------------------------------------------------------
:INSTALL_PS7_DIRECT
powershell -Command "try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; $url = 'https://github.com/PowerShell/PowerShell/releases/latest/download/PowerShell-7.4.5-win-x64.msi'; $file = '$env:TEMP\PowerShell7.msi'; Invoke-WebRequest -Uri $url -OutFile $file -UseBasicParsing; Start-Process msiexec -ArgumentList '/i', $file, '/quiet', '/norestart' -Wait; Remove-Item $file -Force; Write-Host '[INFO] PowerShell 7 installed via direct download' } catch { Write-Host '[ERROR] PowerShell 7 install failed:' $_.Exception.Message }"
GOTO :EOF

REM -----------------------------------------------------------------------------
REM Logging Function - Logs to both console and maintenance.log file
REM -----------------------------------------------------------------------------
:LOG_ENTRY
SET "LEVEL=%~1"
SET "MESSAGE=%~2"
ECHO [%TIME%] [%LEVEL%] %MESSAGE%
ECHO [%DATE% %TIME%] [%LEVEL%] %MESSAGE% >> "%LOG_FILE%"
GOTO :EOF
