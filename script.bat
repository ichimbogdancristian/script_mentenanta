@echo off
REM ============================================================================
REM  script_mentenanta - Windows Maintenance Automation Launcher
REM  Purpose: Entry point for all maintenance operations. Handles dependency
REM           installation, scheduled task setup, repo download/update, and
REM           launches PowerShell orchestrator (script.ps1).
REM  Environment: Requires Administrator, Windows 10/11, PowerShell 5.1+.
REM  All actions are logged to console; PowerShell script handles file logging.
REM ============================================================================
SETLOCAL ENABLEDELAYEDEXPANSION


REM -----------------------------------------------------------------------------
REM Scheduled Task Setup: Monthly Run
REM Ensures a monthly scheduled task is created to run this script as admin.
REM Deletes any previous task, then creates a new one for reliability.
REM -----------------------------------------------------------------------------
SET "TASK_NAME=ScriptMentenantaMonthly"
SET "SCRIPT_PATH=%~f0"
SET "SCRIPT_DIR=%~dp0"
ECHO [%TIME%] [INFO] Ensuring monthly scheduled task '%TASK_NAME%' is set up...
schtasks /Query /TN "%TASK_NAME%" >nul 2>&1
IF %ERRORLEVEL% EQU 0 (
    ECHO [%TIME%] [INFO] Existing monthly task found. Deleting...
    schtasks /Delete /TN "%TASK_NAME%" /F >nul 2>&1
    IF %ERRORLEVEL% EQU 0 (
        ECHO [%TIME%] [INFO] Previous monthly task deleted.
    ) ELSE (
        ECHO [%TIME%] [WARN] Failed to delete previous monthly task. Continuing...
    )
)
ECHO [%TIME%] [INFO] Creating monthly scheduled task...
schtasks /Create /SC MONTHLY /MO 1 /D 1 /TN "%TASK_NAME%" /TR "cmd /c \"%SCRIPT_PATH%\"" /ST 01:00 /RL HIGHEST /F >nul 2>&1
IF %ERRORLEVEL% EQU 0 (
    ECHO [%TIME%] [INFO] Monthly scheduled task created successfully.
) ELSE (
    ECHO [%TIME%] [ERROR] Failed to create monthly scheduled task. Retrying...
    schtasks /Delete /TN "%TASK_NAME%" /F >nul 2>&1
    schtasks /Create /SC MONTHLY /MO 1 /D 1 /TN "%TASK_NAME%" /TR "cmd /c \"%SCRIPT_PATH%\"" /ST 01:00 /RL HIGHEST /F >nul 2>&1
    IF %ERRORLEVEL% EQU 0 (
        ECHO [%TIME%] [INFO] Monthly scheduled task created on retry.
    ) ELSE (
        ECHO [%TIME%] [ERROR] Could not create monthly scheduled task after retry.
    )
)

ECHO [%TIME%] [INFO] Starting maintenance script...
ECHO [%TIME%] [INFO] User: %USERNAME%, Computer: %COMPUTERNAME%

REM -----------------------------------------------------------------------------
REM Admin Privilege Check
REM Relaunches itself with admin rights if not already running as Administrator.
REM -----------------------------------------------------------------------------
NET SESSION >nul 2>&1
IF %ERRORLEVEL% NEQ 0 (
    ECHO [%TIME%] [WARN] Not running as Administrator. Relaunching with admin rights...
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    EXIT /B 0
)

REM -----------------------------------------------------------------------------
REM PowerShell Version Check
REM Ensures PowerShell 5.1+ is available for all automation features.
REM -----------------------------------------------------------------------------
FOR /F "tokens=*" %%i IN ('powershell -Command "$PSVersionTable.PSVersion.Major"') DO SET PS_VERSION=%%i
IF %PS_VERSION% LSS 5 (
    ECHO [%TIME%] [ERROR] PowerShell 5.1 or higher is required. Current version: %PS_VERSION%
    timeout /t 10 /nobreak >nul
    EXIT /B 3
)

REM -----------------------------------------------------------------------------
REM Windows Version Detection
REM Captures OS version for logging and compatibility checks.
REM -----------------------------------------------------------------------------
FOR /F "tokens=*" %%i IN ('powershell -Command "(Get-CimInstance Win32_OperatingSystem).Version"') DO SET OS_VERSION=%%i
ECHO [%TIME%] [INFO] Detected Windows version: %OS_VERSION%

REM -----------------------------------------------------------------------------
REM PowerShell 7 Installation/Update
REM Environment: Windows 10/11 with Winget or internet access for MSI download
REM Purpose: Install/update PowerShell 7 for enhanced script.ps1 features
REM Logic: Check pwsh.exe → Try Winget install → Fallback to MSI → Verify
REM Crash Prevention: Multiple fallback methods, continues with Windows PS if failed
REM -----------------------------------------------------------------------------
ECHO [%TIME%] [INFO] Checking PowerShell 7...
where pwsh.exe >nul 2>&1
IF %ERRORLEVEL% NEQ 0 (
    ECHO [%TIME%] [WARN] PowerShell 7 not found. Attempting to install...
    REM Method 1: Try winget installation
    winget install --id Microsoft.PowerShell --accept-source-agreements --accept-package-agreements --silent >nul 2>&1
    timeout /t 5 /nobreak >nul
    where pwsh.exe >nul 2>&1
    IF %ERRORLEVEL% EQU 0 (
        ECHO [%TIME%] [INFO] PowerShell 7 installed successfully via Winget.
    ) ELSE (
        ECHO [%TIME%] [WARN] Winget installation failed. Trying direct MSI method...
        REM Method 2: Direct MSI installation
        powershell -ExecutionPolicy Bypass -Command "try { $tempPath = $env:TEMP; $scriptPath = Join-Path $tempPath 'install-powershell.ps1'; Invoke-WebRequest -Uri 'https://aka.ms/install-powershell.ps1' -OutFile $scriptPath -UseBasicParsing; & $scriptPath -UseMSI -Quiet; Remove-Item $scriptPath -Force -ErrorAction SilentlyContinue; Write-Host '[INFO] PowerShell 7 installed via MSI.' } catch { Write-Host '[ERROR] PowerShell 7 install failed:' $_.Exception.Message }"
        timeout /t 10 /nobreak >nul
        where pwsh.exe >nul 2>&1
        IF %ERRORLEVEL% EQU 0 (
            ECHO [%TIME%] [INFO] PowerShell 7 installation verified successfully.
        ) ELSE (
            ECHO [%TIME%] [ERROR] PowerShell 7 installation failed completely.
        )
    )
) ELSE (
    ECHO [%TIME%] [INFO] PowerShell 7 already installed. Checking for updates...
    winget upgrade --id Microsoft.PowerShell --accept-source-agreements --accept-package-agreements --silent >nul 2>&1
    IF %ERRORLEVEL% EQU 0 (
        ECHO [%TIME%] [INFO] PowerShell 7 updated.
    ) ELSE (
        ECHO [%TIME%] [INFO] PowerShell 7 is up to date.
    )
)

REM -----------------------------------------------------------------------------
REM Dependency: Winget
REM Installs or updates Winget using multiple fallback methods for reliability.
REM Silent, non-interactive, and robust against errors.
REM -----------------------------------------------------------------------------
ECHO [%TIME%] [INFO] Checking Winget...
where winget.exe >nul 2>&1
IF %ERRORLEVEL% NEQ 0 (
    ECHO [%TIME%] [WARN] Winget not found. Attempting to install...
    REM Method 1: Try installing via PowerShell and App Installer
    powershell -ExecutionPolicy Bypass -Command "try { $tempPath = $env:TEMP; $bundlePath = Join-Path $tempPath 'Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle'; Invoke-WebRequest -Uri 'https://aka.ms/getwinget' -OutFile $bundlePath -UseBasicParsing; Add-AppxPackage -Path $bundlePath; Remove-Item $bundlePath -Force -ErrorAction SilentlyContinue; Write-Host '[INFO] Winget installed via App Installer.' } catch { Write-Host '[ERROR] Winget install failed:' $_.Exception.Message }"
    REM Verify installation
    timeout /t 5 /nobreak >nul
    where winget.exe >nul 2>&1
    IF %ERRORLEVEL% NEQ 0 (
        ECHO [%TIME%] [WARN] Winget installation may have failed. Trying alternative method...
        REM Method 2: Try downloading latest release directly from GitHub
        powershell -ExecutionPolicy Bypass -Command "try { $latestUrl = (Invoke-RestMethod 'https://api.github.com/repos/microsoft/winget-cli/releases/latest').assets | Where-Object { $_.name -like '*msixbundle' } | Select-Object -First 1 -ExpandProperty browser_download_url; $tempPath = $env:TEMP; $bundlePath = Join-Path $tempPath 'winget-latest.msixbundle'; Invoke-WebRequest -Uri $latestUrl -OutFile $bundlePath -UseBasicParsing; Add-AppxPackage -Path $bundlePath; Remove-Item $bundlePath -Force -ErrorAction SilentlyContinue; Write-Host '[INFO] Winget installed via GitHub release.' } catch { Write-Host '[WARN] Alternative Winget install also failed:' $_.Exception.Message }"
    )
) ELSE (
    ECHO [%TIME%] [INFO] Winget already installed. Checking for updates...
    winget upgrade --id Microsoft.DesktopAppInstaller --accept-source-agreements --accept-package-agreements --silent >nul 2>&1
    IF %ERRORLEVEL% EQU 0 (
        ECHO [%TIME%] [INFO] Winget updated.
    ) ELSE (
        ECHO [%TIME%] [INFO] Winget is up to date.
    )
)

REM -----------------------------------------------------------------------------
REM Dependency: Chocolatey
REM Checks for Chocolatey in PATH and common locations, fixes PATH if needed.
REM Installs silently if missing, verifies installation, and updates if present.
REM -----------------------------------------------------------------------------
ECHO [%TIME%] [INFO] Checking Chocolatey installation...
SET "CHOCO_INSTALLED=NO"
SET "CHOCO_PATH_ISSUE=NO"

REM Method 1: Check if choco command is accessible
choco --version >nul 2>&1
IF %ERRORLEVEL% EQU 0 (
    SET "CHOCO_INSTALLED=YES"
    ECHO [%TIME%] [INFO] Chocolatey is accessible via command line.
) ELSE (
    REM Method 2: Check if chocolatey.exe exists in common locations
    IF EXIST "%ProgramData%\chocolatey\bin\choco.exe" (
        SET "CHOCO_INSTALLED=YES"
        SET "CHOCO_PATH_ISSUE=YES"
        ECHO [%TIME%] [WARN] Chocolatey is installed but not in PATH. Adding to PATH...
        SET "PATH=%PATH%;%ProgramData%\chocolatey\bin"
        choco --version >nul 2>&1
        IF %ERRORLEVEL% EQU 0 (
            SET "CHOCO_PATH_ISSUE=NO"
            ECHO [%TIME%] [INFO] Chocolatey is now accessible after PATH correction.
        ) ELSE (
            ECHO [%TIME%] [WARN] Chocolatey still not accessible after PATH correction.
        )
    ) ELSE (
        REM Method 3: Check alternative installation location
        IF EXIST "%ALLUSERSPROFILE%\chocolatey\bin\choco.exe" (
            SET "CHOCO_INSTALLED=YES"
            SET "CHOCO_PATH_ISSUE=YES"
            ECHO [%TIME%] [WARN] Chocolatey found in alternative location. Adding to PATH...
            SET "PATH=%PATH%;%ALLUSERSPROFILE%\chocolatey\bin"
            choco --version >nul 2>&1
            IF %ERRORLEVEL% EQU 0 (
                SET "CHOCO_PATH_ISSUE=NO"
                ECHO [%TIME%] [INFO] Chocolatey is now accessible from alternative location.
            )
        ) ELSE (
            ECHO [%TIME%] [INFO] Chocolatey not found in any standard locations.
        )
    )
)

IF "%CHOCO_INSTALLED%"=="NO" (
    ECHO [%TIME%] [WARN] Chocolatey not found. Attempting to install...
    powershell -ExecutionPolicy Bypass -Command "Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; try { Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1')); Write-Host '[INFO] Chocolatey installation completed.' } catch { Write-Host '[ERROR] Chocolatey install failed:' $_.Exception.Message }"
    
    REM Refresh environment variables and verify installation
    CALL refreshenv.cmd >nul 2>&1
    timeout /t 5 /nobreak >nul
    
    REM Re-verify installation with multiple methods
    choco --version >nul 2>&1
    IF %ERRORLEVEL% EQU 0 (
        ECHO [%TIME%] [INFO] Chocolatey installation verified successfully.
        SET "CHOCO_INSTALLED=YES"
    ) ELSE (
        ECHO [%TIME%] [WARN] Chocolatey command not accessible. Checking installation manually...
        IF EXIST "%ProgramData%\chocolatey\bin\choco.exe" (
            ECHO [%TIME%] [INFO] Chocolatey executable found. Adding to PATH manually...
            SET "PATH=%PATH%;%ProgramData%\chocolatey\bin"
            choco --version >nul 2>&1
            IF %ERRORLEVEL% EQU 0 (
                ECHO [%TIME%] [INFO] Chocolatey is now accessible after manual PATH correction.
                SET "CHOCO_INSTALLED=YES"
            ) ELSE (
                ECHO [%TIME%] [ERROR] Chocolatey installation failed - executable found but not functional.
            )
        ) ELSE (
            ECHO [%TIME%] [ERROR] Chocolatey installation failed completely - no executable found.
        )
    )
) ELSE (
    IF "%CHOCO_PATH_ISSUE%"=="NO" (
        ECHO [%TIME%] [INFO] Chocolatey is properly installed and accessible. Checking for updates...
        choco upgrade chocolatey -y --limit-output >nul 2>&1
        IF %ERRORLEVEL% EQU 0 (
            ECHO [%TIME%] [INFO] Chocolatey updated successfully.
        ) ELSE (
            ECHO [%TIME%] [INFO] Chocolatey is up to date or update not needed.
        )
    ) ELSE (
        ECHO [%TIME%] [WARN] Chocolatey installation has PATH issues but is accessible now.
    )
)

REM -----------------------------------------------------------------------------
REM NuGet CLI Installation
REM Environment: Internet connection, %ProgramData% write access, admin rights
REM Purpose: Install/update nuget.exe for package management operations
REM Logic: Check nuget command → Download to ProgramData → Add to PATH → Verify
REM Crash Prevention: Silent download, PATH checks, continues on failure
REM -----------------------------------------------------------------------------
ECHO [%TIME%] [INFO] Checking NuGet (unattended)...
SET "NUGET_PATH=%ProgramData%\nuget"
SET "NUGET_EXE=%NUGET_PATH%\nuget.exe"
IF NOT EXIST "%NUGET_PATH%" MKDIR "%NUGET_PATH%" >nul 2>&1

REM Try to run nuget help to check if NuGet is available
nuget help >nul 2>&1
IF %ERRORLEVEL% NEQ 0 (
    ECHO [%TIME%] [WARN] NuGet not found. Installing silently...
    REM Attempt silent download using PowerShell with robust error handling
    powershell -ExecutionPolicy Bypass -WindowStyle Hidden -Command "try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri 'https://dist.nuget.org/win-x86-commandline/latest/nuget.exe' -OutFile \"%NUGET_EXE%\" -UseBasicParsing -TimeoutSec 30; Write-Host '[INFO] NuGet downloaded successfully.' } catch { Write-Host '[ERROR] NuGet download failed. Continuing without NuGet.' }"
    IF EXIST "%NUGET_EXE%" (
        ECHO [%TIME%] [INFO] NuGet download successful. Adding to PATH silently...
        ECHO %PATH% | FIND /I "%NUGET_PATH%" >nul 2>&1
        IF %ERRORLEVEL% NEQ 0 (
            setx PATH "%NUGET_PATH%;%PATH%" /M >nul 2>&1
            SET "PATH=%NUGET_PATH%;%PATH%"
        )
        "%NUGET_EXE%" help >nul 2>&1
        IF %ERRORLEVEL% EQU 0 (
            ECHO [%TIME%] [INFO] NuGet installation verified successfully.
        ) ELSE (
            ECHO [%TIME%] [ERROR] NuGet executable found but not functional. Will continue without NuGet.
        )
    ) ELSE (
        ECHO [%TIME%] [ERROR] NuGet download failed - file not found. Will continue without NuGet.
    )
) ELSE (
    ECHO [%TIME%] [INFO] NuGet already installed. Updating to latest version silently...
    powershell -ExecutionPolicy Bypass -WindowStyle Hidden -Command "try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri 'https://dist.nuget.org/win-x86-commandline/latest/nuget.exe' -OutFile \"%NUGET_EXE%\" -UseBasicParsing -TimeoutSec 30; Write-Host '[INFO] NuGet updated successfully.' } catch { Write-Host '[ERROR] NuGet update failed. Continuing with current version.' }"
)

REM -----------------------------------------------------------------------------
REM PowerShell NuGet Provider Installation
REM Environment: Requires PowerShell 5.1+, internet connection, admin rights
REM Purpose: Installs/updates NuGet provider for PowerShell package management
REM Logic: Check version → Set PSGallery trusted → Install silently with all flags
REM Crash Prevention: Wrapped in try/catch, uses -ErrorAction SilentlyContinue
REM -----------------------------------------------------------------------------
ECHO [%TIME%] [INFO] Checking NuGet PowerShell Provider...
powershell -ExecutionPolicy Bypass -WindowStyle Hidden -Command "try { $ErrorActionPreference = 'SilentlyContinue'; $ProgressPreference = 'SilentlyContinue'; $WarningPreference = 'SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; $env:PACKAGEMANAGEMENT_PROVIDER_AUTODOWNLOAD = 'true'; $provider = Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue; if (-not $provider -or $provider.Version -lt [version]'2.8.5.201') { Write-Host '[INFO] Installing NuGet provider silently...'; try { Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted -ErrorAction SilentlyContinue } catch { }; $null = Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -ForceBootstrap -Scope AllUsers -Confirm:$false -SkipPublisherCheck -AllowClobber -ErrorAction SilentlyContinue; Write-Host '[INFO] NuGet PowerShell provider installed.' } else { Write-Host '[INFO] NuGet PowerShell provider already available.' } } catch { Write-Host '[WARN] NuGet provider install failed. Continuing...' }"

REM -----------------------------------------------------------------------------
REM PowerShell Module Installation: PSWindowsUpdate
REM Environment: Requires PowerShell 5.1+, NuGet provider, internet connection
REM Purpose: Installs PSWindowsUpdate module for automated Windows Updates
REM Logic: Check if module exists → Set PSGallery trusted → Install with all flags
REM Crash Prevention: Wrapped in try/catch, continues on failure with warning
REM -----------------------------------------------------------------------------
ECHO [%TIME%] [INFO] Installing required PowerShell modules...
powershell -ExecutionPolicy Bypass -WindowStyle Hidden -Command "try { $ErrorActionPreference = 'SilentlyContinue'; $ProgressPreference = 'SilentlyContinue'; $WarningPreference = 'SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; $env:PACKAGEMANAGEMENT_PROVIDER_AUTODOWNLOAD = 'true'; try { Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted -ErrorAction SilentlyContinue } catch { }; if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate -ErrorAction SilentlyContinue)) { Write-Host '[INFO] Installing PSWindowsUpdate module...'; Install-Module -Name PSWindowsUpdate -Force -Scope AllUsers -Confirm:$false -SkipPublisherCheck -AllowClobber -AcceptLicense -ErrorAction SilentlyContinue; Write-Host '[INFO] PSWindowsUpdate module installed.' } else { Write-Host '[INFO] PSWindowsUpdate module already available.' } } catch { Write-Host '[WARN] PSWindowsUpdate install failed. Continuing...' }"

REM -----------------------------------------------------------------------------
REM PowerShell Module Check: Appx
REM Environment: Windows 10/11 with UWP support (not available on Server Core)
REM Purpose: Verify Appx module availability for UWP/Store app management
REM Logic: Check if module exists → Try to import → Log status/warning
REM Crash Prevention: Uses try/catch, graceful degradation if unavailable
REM -----------------------------------------------------------------------------
ECHO [%TIME%] [INFO] Checking Appx module availability...
powershell -ExecutionPolicy Bypass -WindowStyle Hidden -Command "try { if (Get-Module -ListAvailable -Name Appx -ErrorAction SilentlyContinue) { Import-Module Appx -ErrorAction SilentlyContinue; Write-Host '[INFO] Appx module is available and functional.' } else { Write-Host '[WARN] Appx module not available on this platform. UWP app management will be limited.' } } catch { Write-Host '[WARN] Appx module cannot be imported on this platform.' }"

REM -----------------------------------------------------------------------------
REM System Component Verification
REM Environment: Windows 10/11 system with standard tools and PowerShell cmdlets
REM Purpose: Verify essential Windows components needed by script.ps1
REM Logic: Check file paths and cmdlet availability → Report missing components
REM Crash Prevention: Uses try/catch, continues even if checks fail
REM -----------------------------------------------------------------------------
ECHO [%TIME%] [INFO] Checking essential Windows components...
powershell -ExecutionPolicy Bypass -WindowStyle Hidden -Command "try { $components = @(); if (-not (Test-Path '$env:SystemRoot\System32\cleanmgr.exe')) { $components += 'cleanmgr.exe (Disk Cleanup)' }; if (-not (Get-Command Get-ComputerInfo -ErrorAction SilentlyContinue)) { $components += 'Get-ComputerInfo cmdlet' }; if (-not (Get-Command Get-CimInstance -ErrorAction SilentlyContinue)) { $components += 'Get-CimInstance cmdlet' }; if ($components.Count -gt 0) { Write-Host '[WARN] Missing components:' ($components -join ', ') } else { Write-Host '[INFO] All essential Windows components are available.' } } catch { Write-Host '[WARN] Error checking Windows components. Continuing...' }"

REM -----------------------------------------------------------------------------
REM Dependency Status Summary Report
REM Environment: After all dependency installation attempts completed
REM Purpose: Generate comprehensive status report of all package managers/modules
REM Logic: Test each dependency → Categorize as working/missing → Report status
REM Crash Prevention: Individual checks isolated, script continues regardless
REM -----------------------------------------------------------------------------
ECHO [%TIME%] [INFO] Performing comprehensive dependency verification...
SET "DEPS_MISSING="
SET "DEPS_WORKING="

REM Check Winget
winget --version >nul 2>&1
IF %ERRORLEVEL% EQU 0 (
    SET "DEPS_WORKING=%DEPS_WORKING% Winget"
) ELSE (
    SET "DEPS_MISSING=%DEPS_MISSING% Winget"
)

REM Check Chocolatey
choco --version >nul 2>&1
IF %ERRORLEVEL% EQU 0 (
    SET "DEPS_WORKING=%DEPS_WORKING% Chocolatey"
) ELSE (
    SET "DEPS_MISSING=%DEPS_MISSING% Chocolatey"
)

REM Check NuGet
nuget help >nul 2>&1
IF %ERRORLEVEL% EQU 0 (
    SET "DEPS_WORKING=%DEPS_WORKING% NuGet"
) ELSE (
    SET "DEPS_MISSING=%DEPS_MISSING% NuGet"
)

REM Check PowerShell modules
powershell -ExecutionPolicy Bypass -Command "try { if (Get-Module -ListAvailable -Name PSWindowsUpdate -ErrorAction SilentlyContinue) { Write-Host 'PSWindowsUpdate-OK' } else { Write-Host 'PSWindowsUpdate-MISSING' } } catch { Write-Host 'PSWindowsUpdate-ERROR' }" > %TEMP%\psmodule_check.txt
SET /P PSMODULE_STATUS=<%TEMP%\psmodule_check.txt
DEL /F /Q %TEMP%\psmodule_check.txt >nul 2>&1
IF "%PSMODULE_STATUS%"=="PSWindowsUpdate-OK" (
    SET "DEPS_WORKING=%DEPS_WORKING% PSWindowsUpdate"
) ELSE (
    SET "DEPS_MISSING=%DEPS_MISSING% PSWindowsUpdate"
)

ECHO [%TIME%] [INFO] Dependency Status Summary:
IF NOT "%DEPS_WORKING%"=="" (
    ECHO [%TIME%] [INFO] Working dependencies:%DEPS_WORKING%
)
IF NOT "%DEPS_MISSING%"=="" (
    ECHO [%TIME%] [WARN] Missing dependencies:%DEPS_MISSING%
    ECHO [%TIME%] [WARN] Some maintenance features may be limited.
) ELSE (
    ECHO [%TIME%] [INFO] All dependencies are working correctly.
)

REM -----------------------------------------------------------------------------
REM ...existing code...


REM -----------------------------------------------------------------------------
REM Startup Task Management
REM Environment: Windows Task Scheduler with admin rights
REM Purpose: Create startup task only if system restart is required
REM Logic: Check for existing task → Delete if present → Wait for restart logic
REM Crash Prevention: Continues even if task operations fail
REM -----------------------------------------------------------------------------
SET "STARTUP_TASK_NAME=ScriptMentenantaStartup"
ECHO [%TIME%] [INFO] Ensuring startup scheduled task '%STARTUP_TASK_NAME%' is set up...
schtasks /Query /TN "%STARTUP_TASK_NAME%" >nul 2>&1
IF %ERRORLEVEL% EQU 0 (
    ECHO [%TIME%] [INFO] Existing startup task found. Deleting...
    schtasks /Delete /TN "%STARTUP_TASK_NAME%" /F >nul 2>&1
    IF %ERRORLEVEL% EQU 0 (
        ECHO [%TIME%] [INFO] Previous startup task deleted.
    ) ELSE (
        ECHO [%TIME%] [WARN] Failed to delete previous startup task. Continuing...
    )
)
REM Only create startup task if needed (pending restart logic below)

REM -----------------------------------------------------------------------------
REM System Restart Detection and Handling
REM Environment: Windows registry access for checking pending operations
REM Purpose: Detect if restart required → Create startup task → Restart system
REM Logic: Check 3 registry keys → If any true, create task and restart
REM Crash Prevention: Registry checks use >nul 2>&1, task creation has fallback
REM -----------------------------------------------------------------------------
ECHO [%TIME%] [INFO] Checking for pending system restarts...
SET "RESTART_STATUS=NO_RESTART"
REM Check for Windows Update reboot required
REG QUERY "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired" >nul 2>&1
IF %ERRORLEVEL% EQU 0 SET "RESTART_STATUS=RESTART_REQUIRED"
REM Check for Component Based Servicing reboot pending
REG QUERY "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending" >nul 2>&1
IF %ERRORLEVEL% EQU 0 SET "RESTART_STATUS=RESTART_REQUIRED"
REM Check for pending file rename operations
REG QUERY "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager" /v PendingFileRenameOperations >nul 2>&1
IF %ERRORLEVEL% EQU 0 SET "RESTART_STATUS=RESTART_REQUIRED"
ECHO [%TIME%] [DEBUG] Restart status check completed: %RESTART_STATUS%

IF "%RESTART_STATUS%"=="RESTART_REQUIRED" (
    ECHO [%TIME%] [WARN] Pending system restart detected. Creating startup task and restarting...
    schtasks /Create /SC ONSTART /TN "%STARTUP_TASK_NAME%" /TR "cmd /c \"timeout /t 60 /nobreak >nul && \"%SCRIPT_PATH%\"\"" /RL HIGHEST /DELAY 01:00 /F >nul 2>&1
    IF %ERRORLEVEL% EQU 0 (
        ECHO [%TIME%] [INFO] Startup task created successfully with 1-minute delay. System will restart now...
        shutdown /r /t 10 /c "System restart required for maintenance script continuation"
        ECHO [%TIME%] [INFO] System will restart in 10 seconds...
        timeout /t 15 /nobreak >nul
        EXIT /B 0
    ) ELSE (
        ECHO [%TIME%] [ERROR] Failed to create startup task. Continuing without restart...
    )
) ELSE (
    ECHO [%TIME%] [INFO] No pending restarts detected. Continuing with maintenance...
)

REM -----------------------------------------------------------------------------
REM Final Pre-Download Dependency Check
REM Environment: After all installation attempts, before repo operations
REM Purpose: Final verification that critical tools are working before proceeding
REM Logic: Test Winget, Chocolatey, PowerShell 7 → Set status flag → Log warnings
REM Crash Prevention: Individual checks isolated, continues with limited functionality
REM -----------------------------------------------------------------------------
ECHO [%TIME%] [INFO] Performing final dependency verification...
SET "FINAL_STATUS=OK"

winget --version >nul 2>&1
IF %ERRORLEVEL% NEQ 0 (
    ECHO [%TIME%] [WARN] Winget is not accessible. Package management may be limited.
    SET "FINAL_STATUS=LIMITED"
)

choco --version >nul 2>&1
IF %ERRORLEVEL% NEQ 0 (
    ECHO [%TIME%] [WARN] Chocolatey is not accessible. Package management may be limited.
    SET "FINAL_STATUS=LIMITED"
)

pwsh.exe -Version >nul 2>&1
IF %ERRORLEVEL% NEQ 0 (
    ECHO [%TIME%] [WARN] PowerShell 7 is not accessible. Using Windows PowerShell instead.
)

IF "%FINAL_STATUS%"=="OK" (
    ECHO [%TIME%] [INFO] All dependencies verified. System ready for maintenance.
) ELSE (
    ECHO [%TIME%] [WARN] Some dependencies are missing. Maintenance will proceed with limited functionality.
)

REM -----------------------------------------------------------------------------
REM Checkpoint: About to start repo download
REM -----------------------------------------------------------------------------
ECHO [%TIME%] [DEBUG] Checkpoint: Reached repo download step.

REM -----------------------------------------------------------------------------
REM Repo Download Setup
REM Sets repo ZIP URL, output file, and extraction folder for update/download.
REM -----------------------------------------------------------------------------
REM Set repo URL for ZIP download (main branch) and note .git URL for reference
REM To clone via git: https://github.com/ichimbogdancristian/script_mentenanta.git
REM To download ZIP: https://github.com/ichimbogdancristian/script_mentenanta/archive/refs/heads/main.zip
SET "REPO_URL=https://github.com/ichimbogdancristian/script_mentenanta/archive/refs/heads/main.zip"
SET "ZIP_NAME=script_mentenanta.zip"
SET "EXTRACT_FOLDER=script_mentenanta-main"

REM -----------------------------------------------------------------------------
REM Debugging: Show current directory and environment variables
REM -----------------------------------------------------------------------------
ECHO [%TIME%] [DEBUG] Current directory: %CD%
ECHO [%TIME%] [DEBUG] SCRIPT_DIR: %SCRIPT_DIR%
ECHO [%TIME%] [DEBUG] ZIP_NAME: %ZIP_NAME%
ECHO [%TIME%] [DEBUG] EXTRACT_FOLDER: %EXTRACT_FOLDER%
ECHO [%TIME%] [DEBUG] REPO_URL: %REPO_URL%
ECHO [%TIME%] [DEBUG] PATH: %PATH%

REM -----------------------------------------------------------------------------
REM PowerShell Availability Check
REM Ensures PowerShell is available before attempting repo download.
REM -----------------------------------------------------------------------------
powershell -Command "Write-Host '[DEBUG] PowerShell available.'" >nul 2>&1
IF %ERRORLEVEL% NEQ 0 (
    ECHO [%TIME%] [ERROR] PowerShell is not available. Cannot download repo.
    EXIT /B 10
)

REM -----------------------------------------------------------------------------
REM Repository Download and Update
REM Environment: Internet connection, PowerShell, GitHub access
REM Purpose: Download latest repo ZIP from GitHub for script updates
REM Logic: Set URLs → Download ZIP → Verify file exists → Handle errors
REM Crash Prevention: Multiple verification steps, detailed error logging
REM -----------------------------------------------------------------------------
ECHO [%TIME%] [INFO] Downloading repository...
ECHO [%TIME%] [INFO] Downloading from: %REPO_URL%
ECHO [%TIME%] [INFO] Download target: %SCRIPT_DIR%%ZIP_NAME%
ECHO [%TIME%] [DEBUG] Running PowerShell download command...
powershell -ExecutionPolicy Bypass -Command "try { Write-Host '[DEBUG] Starting download...'; Invoke-WebRequest -Uri \"%REPO_URL%\" -OutFile \"%SCRIPT_DIR%%ZIP_NAME%\" -UseBasicParsing; Write-Host '[INFO] Repository downloaded successfully.' } catch { Write-Host '[ERROR] Download failed:' $_.Exception.Message; exit 1 }"
ECHO [%TIME%] [DEBUG] PowerShell download command finished. Checking for ZIP file...
IF %ERRORLEVEL% NEQ 0 (
    ECHO [%TIME%] [ERROR] PowerShell download command failed. ErrorLevel: %ERRORLEVEL%
    timeout /t 10 /nobreak >nul
    EXIT /B 2
)
IF NOT EXIST "%SCRIPT_DIR%%ZIP_NAME%" (
    ECHO [%TIME%] [ERROR] Download failed - ZIP file not found at %SCRIPT_DIR%%ZIP_NAME%.
    DIR "%SCRIPT_DIR%" /B
    timeout /t 10 /nobreak >nul
    EXIT /B 2
)

REM -----------------------------------------------------------------------------
REM Repository Extraction Process
REM Environment: Windows VBScript support, Shell.Application COM object
REM Purpose: Extract downloaded ZIP to target folder using native Windows tools
REM Logic: Create VBScript → Run extraction → Wait → Verify → Cleanup
REM Crash Prevention: Checks for extracted folder, lists contents on failure
REM -----------------------------------------------------------------------------
ECHO [%TIME%] [INFO] Extracting repository...
ECHO [%TIME%] [INFO] Extracting from: %SCRIPT_DIR%%ZIP_NAME%
ECHO [%TIME%] [INFO] Extracting to: %SCRIPT_DIR%
REM Create VBScript for extraction
ECHO Set objShell = CreateObject("Shell.Application") > "%TEMP%\extract.vbs"
ECHO Set objFolder = objShell.NameSpace("%SCRIPT_DIR%") >> "%TEMP%\extract.vbs"
ECHO Set objZip = objShell.NameSpace("%SCRIPT_DIR%%ZIP_NAME%") >> "%TEMP%\extract.vbs"
ECHO objFolder.CopyHere objZip.Items, 256 >> "%TEMP%\extract.vbs"
REM Run extraction
cscript //nologo "%TEMP%\extract.vbs"
DEL /F /Q "%TEMP%\extract.vbs" >nul 2>&1
REM Wait for extraction to complete
timeout /t 3 /nobreak >nul
IF %ERRORLEVEL% NEQ 0 (
    ECHO [%TIME%] [ERROR] VBScript extraction command failed.
    timeout /t 10 /nobreak >nul
    EXIT /B 3
)
IF NOT EXIST "%SCRIPT_DIR%%EXTRACT_FOLDER%" (
    ECHO [%TIME%] [ERROR] Extraction failed - folder %SCRIPT_DIR%%EXTRACT_FOLDER% not found.
    ECHO [%TIME%] [INFO] Checking what was extracted...
    DIR "%SCRIPT_DIR%" /B
    timeout /t 10 /nobreak >nul
    EXIT /B 3
)
REM Cleanup ZIP file
DEL /F /Q "%SCRIPT_DIR%%ZIP_NAME%"

ECHO [%TIME%] [INFO] Repository downloaded and extracted to %SCRIPT_DIR%%EXTRACT_FOLDER%.
ECHO [%TIME%] [INFO] Dependencies installation completed.
ECHO [%TIME%] [INFO] Starting PowerShell maintenance script...

REM -----------------------------------------------------------------------------
REM PowerShell Script Execution
REM Environment: Extracted repo folder, PowerShell 7 or Windows PowerShell, admin rights
REM Purpose: Launch script.ps1 in new admin window for maintenance operations
REM Logic: Change to repo folder → Find script.ps1 → Choose PS version → Launch
REM Crash Prevention: Checks file existence, lists contents on failure, waits for user
REM -----------------------------------------------------------------------------
SET "EXTRACTED_PATH=%SCRIPT_DIR%%EXTRACT_FOLDER%"
ECHO [%TIME%] [DEBUG] Looking for script.ps1 in: %EXTRACTED_PATH%
CD /D "%EXTRACTED_PATH%"
IF EXIST "%EXTRACTED_PATH%\script.ps1" (
    ECHO [%TIME%] [INFO] Found script.ps1 in extracted folder.
    SET "PS1_FULLPATH=%EXTRACTED_PATH%\script.ps1"
    ECHO [%TIME%] [INFO] Script path: !PS1_FULLPATH!
    REM Check if PowerShell 7 is available, fallback to Windows PowerShell
    pwsh.exe -Version >nul 2>&1
    IF %ERRORLEVEL% EQU 0 (
        ECHO [%TIME%] [INFO] Launching PowerShell 7 in new admin window...
        REM Launch PowerShell 7 in new window with admin rights
        powershell -Command "Start-Process 'pwsh.exe' -ArgumentList '-ExecutionPolicy Bypass -File \"!PS1_FULLPATH!\"' -Verb RunAs"
        ECHO [%TIME%] [INFO] PowerShell 7 launched in new admin window.
    ) ELSE (
        ECHO [%TIME%] [WARN] PowerShell 7 not available, using Windows PowerShell in new admin window...
        REM Launch Windows PowerShell in new window with admin rights
        powershell -Command "Start-Process 'powershell.exe' -ArgumentList '-ExecutionPolicy Bypass -File \"!PS1_FULLPATH!\"' -Verb RunAs"
        ECHO [%TIME%] [INFO] Windows PowerShell launched in new admin window.
    )
    ECHO [%TIME%] [INFO] Maintenance script launched successfully.
    ECHO [%TIME%] [INFO] This window will close in 120 seconds. Press any key to close immediately.
    timeout /t 120
    ECHO [%TIME%] [INFO] Batch script launcher completed.
) ELSE (
    ECHO [%TIME%] [ERROR] script.ps1 not found in extracted folder: %EXTRACTED_PATH%
    ECHO [%TIME%] [INFO] Contents of extracted folder:
    DIR "%EXTRACTED_PATH%" /B
    ECHO [%TIME%] [INFO] Current working directory:
    ECHO %CD%
    ECHO [%TIME%] [INFO] Press any key to continue...
    pause >nul
    EXIT /B 4
)

REM -----------------------------------------------------------------------------
REM Script Completion
REM All maintenance operations finished. End batch session.
REM -----------------------------------------------------------------------------
ECHO [%TIME%] [INFO] Maintenance script completed.
ENDLOCAL
