@echo off
REM ============================================================================
REM  script_mentenanta - Windows Maintenance Automation Launcher (Repaired)
REM  Purpose: Entry point for all maintenance operations. Handles dependency
REM           installation, scheduled task setup, repo download/update, and
REM           launches PowerShell orchestrator (script.ps1).
REM  Environment: Requires Administrator, Windows 10/11, PowerShell 5.1+.
REM  All actions are logged to console; PowerShell script handles file logging.
REM ============================================================================
SETLOCAL ENABLEDELAYEDEXPANSION

REM -----------------------------------------------------------------------------
REM Basic Environment Setup
REM -----------------------------------------------------------------------------
SET "TASK_NAME=ScriptMentenantaMonthly"
SET "STARTUP_TASK_NAME=ScriptMentenantaStartup"
SET "SCRIPT_PATH=%~f0"
SET "SCRIPT_DIR=%~dp0"

ECHO [%TIME%] [INFO] Starting maintenance script...
ECHO [%TIME%] [INFO] User: %USERNAME%, Computer: %COMPUTERNAME%

REM -----------------------------------------------------------------------------
REM Admin Privilege Check
REM Relaunches itself with admin rights if not already running as Administrator.
REM -----------------------------------------------------------------------------
NET SESSION >nul 2>&1
IF %ERRORLEVEL% NEQ 0 (
    ECHO [%TIME%] [WARN] Not running as Administrator. Relaunching with admin rights...
    powershell -Command "Start-Process '%~f0' -Verb RunAs" >nul 2>&1
    EXIT /B 0
)

REM -----------------------------------------------------------------------------
REM PowerShell Version Check
REM Ensures PowerShell 5.1+ is available for all automation features.
REM -----------------------------------------------------------------------------
FOR /F "tokens=*" %%i IN ('powershell -Command "$PSVersionTable.PSVersion.Major" 2^>nul') DO SET PS_VERSION=%%i
IF "%PS_VERSION%"=="" SET PS_VERSION=0
IF %PS_VERSION% LSS 5 (
    ECHO [%TIME%] [ERROR] PowerShell 5.1 or higher is required. Current version: %PS_VERSION%
    ECHO [%TIME%] [ERROR] Please install PowerShell 5.1 or newer and try again.
    timeout /t 30 /nobreak >nul
    EXIT /B 3
)
ECHO [%TIME%] [INFO] PowerShell version: %PS_VERSION%

REM -----------------------------------------------------------------------------
REM Windows Version Detection
REM -----------------------------------------------------------------------------
FOR /F "tokens=*" %%i IN ('powershell -Command "(Get-CimInstance Win32_OperatingSystem).Version" 2^>nul') DO SET OS_VERSION=%%i
IF "%OS_VERSION%"=="" SET OS_VERSION=Unknown
ECHO [%TIME%] [INFO] Detected Windows version: %OS_VERSION%

REM -----------------------------------------------------------------------------
REM Enhanced Monthly Scheduled Task Setup - FIXED
REM Ensures a monthly scheduled task is created to run this script as admin.
REM -----------------------------------------------------------------------------
ECHO [%TIME%] [INFO] Setting up enhanced monthly scheduled task '%TASK_NAME%'...

REM Check if task already exists and delete it
schtasks /Query /TN "%TASK_NAME%" >nul 2>&1
IF %ERRORLEVEL% EQU 0 (
    ECHO [%TIME%] [INFO] Existing monthly task found. Deleting for recreation...
    schtasks /Delete /TN "%TASK_NAME%" /F >nul 2>&1
)

REM Create monthly task with corrected XML approach for better compatibility
powershell -ExecutionPolicy Bypass -Command ^
"$xml = @'^
<?xml version='1.0' encoding='UTF-16'?>^
<Task version='1.2' xmlns='http://schemas.microsoft.com/windows/2004/02/mit/task'>^
  <RegistrationInfo>^
    <Description>Monthly Windows Maintenance Script</Description>^
  </RegistrationInfo>^
  <Triggers>^
    <CalendarTrigger>^
      <StartBoundary>2025-01-01T01:00:00</StartBoundary>^
      <Enabled>true</Enabled>^
      <ScheduleByMonth>^
        <DaysOfMonth>^
          <Day>1</Day>^
        </DaysOfMonth>^
        <Months>^
          <January /><February /><March /><April /><May /><June />^
          <July /><August /><September /><October /><November /><December />^
        </Months>^
      </ScheduleByMonth>^
    </CalendarTrigger>^
  </Triggers>^
  <Principals>^
    <Principal id='Author'>^
      <UserId>S-1-5-18</UserId>^
      <RunLevel>HighestAvailable</RunLevel>^
    </Principal>^
  </Principals>^
  <Settings>^
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>^
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>^
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>^
    <AllowHardTerminate>true</AllowHardTerminate>^
    <StartWhenAvailable>true</StartWhenAvailable>^
    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>^
    <IdleSettings>^
      <StopOnIdleEnd>false</StopOnIdleEnd>^
      <RestartOnIdle>false</RestartOnIdle>^
    </IdleSettings>^
    <AllowStartOnDemand>true</AllowStartOnDemand>^
    <Enabled>true</Enabled>^
    <Hidden>false</Hidden>^
    <RunOnlyIfIdle>false</RunOnlyIfIdle>^
    <WakeToRun>false</WakeToRun>^
    <ExecutionTimeLimit>PT2H</ExecutionTimeLimit>^
    <Priority>7</Priority>^
  </Settings>^
  <Actions Context='Author'>^
    <Exec>^
      <Command>cmd.exe</Command>^
      <Arguments>/c \`"%SCRIPT_PATH%\`"</Arguments>^
      <WorkingDirectory>%SCRIPT_DIR%</WorkingDirectory>^
    </Exec>^
  </Actions>^
</Task>^
'@; try { Register-ScheduledTask -TaskName '%TASK_NAME%' -Xml $xml -Force; Write-Host '[INFO] Monthly scheduled task created successfully' } catch { Write-Host '[ERROR] Failed to create monthly task:' $_.Exception.Message; exit 1 }"

IF %ERRORLEVEL% EQU 0 (
    ECHO [%TIME%] [INFO] Monthly scheduled task created successfully.
    
    REM Verify task was created
    schtasks /Query /TN "%TASK_NAME%" >nul 2>&1
    IF %ERRORLEVEL% EQU 0 (
        ECHO [%TIME%] [INFO] Task verification successful.
    )
) ELSE (
    ECHO [%TIME%] [ERROR] Failed to create monthly scheduled task with XML method.
    ECHO [%TIME%] [INFO] Attempting simplified creation...
    
    REM Fallback to simplified method
    schtasks /Create /SC MONTHLY /D 1 /TN "%TASK_NAME%" /TR "cmd.exe /c \"%SCRIPT_PATH%\"" /ST 01:00 /RL HIGHEST /F >nul 2>&1
    IF %ERRORLEVEL% EQU 0 (
        ECHO [%TIME%] [INFO] Monthly task created with simplified method.
    ) ELSE (
        ECHO [%TIME%] [WARN] Monthly scheduling failed with both methods.
    )
)

REM -----------------------------------------------------------------------------
REM Startup Task Management - Check and Remove if Exists
REM -----------------------------------------------------------------------------
ECHO [%TIME%] [INFO] Checking startup task '%STARTUP_TASK_NAME%'...
schtasks /Query /TN "%STARTUP_TASK_NAME%" >nul 2>&1
IF %ERRORLEVEL% EQU 0 (
    ECHO [%TIME%] [INFO] Removing existing startup task...
    schtasks /Delete /TN "%STARTUP_TASK_NAME%" /F >nul 2>&1
    IF %ERRORLEVEL% EQU 0 (
        ECHO [%TIME%] [INFO] Startup task removed successfully.
    )
)

REM -----------------------------------------------------------------------------
REM System Restart Detection and Handling - SIMPLIFIED AND FIXED
REM -----------------------------------------------------------------------------
ECHO [%TIME%] [INFO] Checking for pending system restarts...
SET "RESTART_NEEDED=NO"

REM Check multiple restart indicators
powershell -ExecutionPolicy Bypass -Command ^
"$restartNeeded = $false; ^
if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') { $restartNeeded = $true }; ^
if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') { $restartNeeded = $true }; ^
if (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name 'PendingFileRenameOperations' -ErrorAction SilentlyContinue) { $restartNeeded = $true }; ^
if ($restartNeeded) { Write-Output 'YES' } else { Write-Output 'NO' }" > "%TEMP%\restart_check.txt"

SET /P RESTART_NEEDED=<"%TEMP%\restart_check.txt"
DEL "%TEMP%\restart_check.txt" >nul 2>&1

IF "%RESTART_NEEDED%"=="YES" (
    ECHO [%TIME%] [WARN] System restart is required. Creating startup task and restarting...
    
    REM Create startup task
    powershell -ExecutionPolicy Bypass -Command ^
    "$xml = @'^
    <?xml version='1.0' encoding='UTF-16'?>^
    <Task version='1.2' xmlns='http://schemas.microsoft.com/windows/2004/02/mit/task'>^
      <Triggers>^
        <BootTrigger>^
          <Enabled>true</Enabled>^
          <Delay>PT2M</Delay>^
        </BootTrigger>^
      </Triggers>^
      <Principals>^
        <Principal>^
          <UserId>S-1-5-18</UserId>^
          <RunLevel>HighestAvailable</RunLevel>^
        </Principal>^
      </Principals>^
      <Settings>^
        <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>^
        <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>^
        <AllowStartOnDemand>true</AllowStartOnDemand>^
        <StartWhenAvailable>true</StartWhenAvailable>^
        <DeleteExpiredTaskAfter>PT0S</DeleteExpiredTaskAfter>^
      </Settings>^
      <Actions>^
        <Exec>^
          <Command>cmd.exe</Command>^
          <Arguments>/c \`"%SCRIPT_PATH%\`"</Arguments>^
        </Exec>^
      </Actions>^
    </Task>^
    '@; try { Register-ScheduledTask -TaskName '%STARTUP_TASK_NAME%' -Xml $xml -Force; Write-Host '[INFO] Startup task created' } catch { Write-Host '[ERROR] Failed to create startup task' }"
    
    ECHO [%TIME%] [INFO] Restarting system in 10 seconds...
    ECHO [%TIME%] [INFO] Script will continue automatically after restart.
    timeout /t 10 /nobreak >nul
    shutdown /r /t 0 /c "System restart required for maintenance continuation" /f
    EXIT /B 0
) ELSE (
    ECHO [%TIME%] [INFO] No pending restart detected. Continuing...
)

REM -----------------------------------------------------------------------------
REM Dependency Management - FIXED FOR UNATTENDED INSTALLATION
REM -----------------------------------------------------------------------------
ECHO [%TIME%] [INFO] Starting dependency installation (fully unattended)...

REM Set TLS 1.2 and install NuGet PackageProvider completely unattended
ECHO [%TIME%] [INFO] Installing NuGet PackageProvider (unattended)...
powershell -ExecutionPolicy Bypass -Command ^
"[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; ^
if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) { ^
    try { ^
        $null = Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope AllUsers -Confirm:`$false -ForceBootstrap; ^
        Write-Host '[INFO] NuGet PackageProvider installed successfully' ^
    } catch { ^
        Write-Host '[WARN] NuGet installation failed:' $_.Exception.Message ^
    } ^
} else { ^
    Write-Host '[INFO] NuGet PackageProvider already available' ^
}"

REM Set PowerShell Gallery as trusted
ECHO [%TIME%] [INFO] Configuring PowerShell Gallery as trusted...
powershell -ExecutionPolicy Bypass -Command ^
"try { ^
    Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted -ErrorAction Stop; ^
    Write-Host '[INFO] PowerShell Gallery configured as trusted' ^
} catch { ^
    Write-Host '[WARN] Failed to configure PowerShell Gallery:' $_.Exception.Message ^
}"

REM Install PSWindowsUpdate module
ECHO [%TIME%] [INFO] Installing PSWindowsUpdate module (unattended)...
powershell -ExecutionPolicy Bypass -Command ^
"if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) { ^
    try { ^
        $null = Install-Module -Name PSWindowsUpdate -Force -Scope AllUsers -AllowClobber -Confirm:`$false -SkipPublisherCheck; ^
        Write-Host '[INFO] PSWindowsUpdate module installed successfully' ^
    } catch { ^
        Write-Host '[WARN] PSWindowsUpdate installation failed:' $_.Exception.Message ^
    } ^
} else { ^
    Write-Host '[INFO] PSWindowsUpdate module already available' ^
}"

REM Install Chocolatey (optional)
ECHO [%TIME%] [INFO] Checking Chocolatey installation...
WHERE choco >nul 2>&1
IF %ERRORLEVEL% NEQ 0 (
    ECHO [%TIME%] [INFO] Installing Chocolatey (unattended)...
    powershell -ExecutionPolicy Bypass -Command ^
    "try { ^
        Set-ExecutionPolicy Bypass -Scope Process -Force; ^
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; ^
        $env:chocolateyUseWindowsCompression = 'true'; ^
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1')); ^
        Write-Host '[INFO] Chocolatey installed successfully' ^
    } catch { ^
        Write-Host '[WARN] Chocolatey installation failed (optional):' $_.Exception.Message ^
    }"
    
    REM Refresh environment variables
    CALL refreshenv >nul 2>&1
    IF EXIST "%ProgramData%\chocolatey\bin" SET "PATH=%PATH%;%ProgramData%\chocolatey\bin"
) ELSE (
    ECHO [%TIME%] [INFO] Chocolatey is already installed.
)

REM Check for winget and attempt installation if needed
ECHO [%TIME%] [INFO] Checking Windows Package Manager (winget)...
WHERE winget >nul 2>&1
IF %ERRORLEVEL% NEQ 0 (
    ECHO [%TIME%] [INFO] Attempting winget installation...
    powershell -ExecutionPolicy Bypass -Command ^
    "try { ^
        $progressPreference = 'silentlyContinue'; ^
        Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe -ErrorAction Stop; ^
        Write-Host '[INFO] Winget registration attempted' ^
    } catch { ^
        Write-Host '[WARN] Winget installation failed (optional for Windows 10):' $_.Exception.Message ^
    }"
) ELSE (
    ECHO [%TIME%] [INFO] Winget is already available.
)

ECHO [%TIME%] [INFO] Dependency installation phase completed.

REM -----------------------------------------------------------------------------
REM Repository Download and Extraction - SIMPLIFIED
REM -----------------------------------------------------------------------------
SET "REPO_URL=https://github.com/ichimbogdancristian/script_mentenanta/archive/refs/heads/main.zip"
SET "ZIP_FILE=%TEMP%\script_mentenanta.zip"
SET "EXTRACT_FOLDER=script_mentenanta-main"

ECHO [%TIME%] [INFO] Downloading latest repository...
powershell -ExecutionPolicy Bypass -Command ^
"try { ^
    $ProgressPreference = 'SilentlyContinue'; ^
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; ^
    Invoke-WebRequest -Uri '%REPO_URL%' -OutFile '%ZIP_FILE%' -UseBasicParsing -TimeoutSec 60; ^
    Write-Host '[INFO] Repository downloaded successfully' ^
} catch { ^
    Write-Host '[ERROR] Download failed:' $_.Exception.Message; ^
    exit 1 ^
}"

IF %ERRORLEVEL% NEQ 0 (
    ECHO [%TIME%] [ERROR] Failed to download repository. Check internet connection.
    timeout /t 30 /nobreak >nul
    EXIT /B 2
)

REM Clean up existing extraction folder
ECHO [%TIME%] [INFO] Cleaning up existing repository folder...
IF EXIST "%SCRIPT_DIR%%EXTRACT_FOLDER%" (
    RMDIR /S /Q "%SCRIPT_DIR%%EXTRACT_FOLDER%" >nul 2>&1
    IF EXIST "%SCRIPT_DIR%%EXTRACT_FOLDER%" (
        powershell -ExecutionPolicy Bypass -Command ^
        "try { Remove-Item -Path '%SCRIPT_DIR%%EXTRACT_FOLDER%' -Recurse -Force; Write-Host '[INFO] Existing folder removed' } catch { Write-Host '[WARN] Could not remove existing folder' }"
    )
)

REM Extract repository
ECHO [%TIME%] [INFO] Extracting repository...
powershell -ExecutionPolicy Bypass -Command ^
"try { ^
    Add-Type -AssemblyName System.IO.Compression.FileSystem; ^
    [System.IO.Compression.ZipFile]::ExtractToDirectory('%ZIP_FILE%', '%SCRIPT_DIR%'); ^
    Write-Host '[INFO] Repository extracted successfully' ^
} catch { ^
    Write-Host '[ERROR] Extraction failed:' $_.Exception.Message; ^
    exit 1 ^
}"

IF %ERRORLEVEL% NEQ 0 (
    ECHO [%TIME%] [ERROR] Failed to extract repository.
    timeout /t 30 /nobreak >nul
    EXIT /B 3
)

REM Clean up ZIP file
DEL /F /Q "%ZIP_FILE%" >nul 2>&1

REM Verify extraction
IF NOT EXIST "%SCRIPT_DIR%%EXTRACT_FOLDER%" (
    ECHO [%TIME%] [ERROR] Extraction failed - folder not found.
    timeout /t 30 /nobreak >nul
    EXIT /B 3
)

ECHO [%TIME%] [INFO] Repository extracted successfully to: %SCRIPT_DIR%%EXTRACT_FOLDER%

REM -----------------------------------------------------------------------------
REM PowerShell 7 Detection and Installation - IMPROVED
REM -----------------------------------------------------------------------------
ECHO [%TIME%] [INFO] Checking for PowerShell 7...
SET "PS7_AVAILABLE=NO"
SET "PS7_PATH="

REM Check common PowerShell 7 locations
WHERE pwsh.exe >nul 2>&1
IF %ERRORLEVEL% EQU 0 (
    SET "PS7_AVAILABLE=YES"
    FOR /F "tokens=*" %%i IN ('pwsh.exe -Command "$PSVersionTable.PSVersion.ToString()" 2^>nul') DO SET PS7_VERSION=%%i
    ECHO [%TIME%] [INFO] PowerShell 7 found in PATH: %PS7_VERSION%
    SET "PS7_PATH=pwsh.exe"
) ELSE (
    REM Check default installation paths
    IF EXIST "%ProgramFiles%\PowerShell\7\pwsh.exe" (
        SET "PS7_AVAILABLE=YES"
        SET "PS7_PATH=%ProgramFiles%\PowerShell\7\pwsh.exe"
        FOR /F "tokens=*" %%i IN ('"%PS7_PATH%" -Command "$PSVersionTable.PSVersion.ToString()" 2^>nul') DO SET PS7_VERSION=%%i
        ECHO [%TIME%] [INFO] PowerShell 7 found at default location: %PS7_VERSION%
    ) ELSE (
        ECHO [%TIME%] [WARN] PowerShell 7 not found. Attempting installation...
        
        REM Try winget installation
        WHERE winget >nul 2>&1
        IF %ERRORLEVEL% EQU 0 (
            winget install --id Microsoft.Powershell --source winget --silent --accept-package-agreements --accept-source-agreements >nul 2>&1
            IF %ERRORLEVEL% EQU 0 (
                ECHO [%TIME%] [INFO] PowerShell 7 installation completed.
                REM Check again after installation
                WHERE pwsh.exe >nul 2>&1
                IF %ERRORLEVEL% EQU 0 (
                    SET "PS7_AVAILABLE=YES"
                    SET "PS7_PATH=pwsh.exe"
                    FOR /F "tokens=*" %%i IN ('pwsh.exe -Command "$PSVersionTable.PSVersion.ToString()" 2^>nul') DO SET PS7_VERSION=%%i
                    ECHO [%TIME%] [INFO] PowerShell 7 installed successfully: %PS7_VERSION%
                ) ELSE IF EXIST "%ProgramFiles%\PowerShell\7\pwsh.exe" (
                    SET "PS7_AVAILABLE=YES"
                    SET "PS7_PATH=%ProgramFiles%\PowerShell\7\pwsh.exe"
                    FOR /F "tokens=*" %%i IN ('"%PS7_PATH%" -Command "$PSVersionTable.PSVersion.ToString()" 2^>nul') DO SET PS7_VERSION=%%i
                    ECHO [%TIME%] [INFO] PowerShell 7 installed at default location: %PS7_VERSION%
                )
            ) ELSE (
                ECHO [%TIME%] [WARN] PowerShell 7 installation via winget failed.
            )
        ) ELSE (
            ECHO [%TIME%] [WARN] Winget not available for PowerShell 7 installation.
        )
    )
)

REM -----------------------------------------------------------------------------
REM Launch PowerShell Script - FIXED TO PRIORITIZE POWERSHELL 7
REM -----------------------------------------------------------------------------
SET "PS1_PATH=%SCRIPT_DIR%%EXTRACT_FOLDER%\script.ps1"

IF NOT EXIST "%PS1_PATH%" (
    ECHO [%TIME%] [ERROR] PowerShell script not found: %PS1_PATH%
    timeout /t 30 /nobreak >nul
    EXIT /B 4
)

ECHO [%TIME%] [INFO] Launching PowerShell maintenance script...

IF "%PS7_AVAILABLE%"=="YES" (
    ECHO [%TIME%] [INFO] Using PowerShell 7: %PS7_VERSION%
    CD /D "%SCRIPT_DIR%%EXTRACT_FOLDER%"
    START "Maintenance Script - PowerShell 7" "%PS7_PATH%" -ExecutionPolicy Bypass -File "%PS1_PATH%"
) ELSE (
    ECHO [%TIME%] [INFO] Using Windows PowerShell as fallback...
    CD /D "%SCRIPT_DIR%%EXTRACT_FOLDER%"
    START "Maintenance Script - Windows PowerShell" powershell.exe -ExecutionPolicy Bypass -File "%PS1_PATH%"
)

IF %ERRORLEVEL% EQU 0 (
    ECHO [%TIME%] [INFO] PowerShell script launched successfully.
    ECHO [%TIME%] [INFO] Maintenance operations are now running in a separate window.
    ECHO [%TIME%] [INFO] This launcher will close in 10 seconds...
    timeout /t 10 /nobreak >nul
    ECHO [%TIME%] [INFO] Batch launcher completed successfully.
) ELSE (
    ECHO [%TIME%] [ERROR] Failed to launch PowerShell script.
    timeout /t 30 /nobreak >nul
)

ENDLOCAL
EXIT /B 0