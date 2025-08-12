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
REM Dependency Management System - Centralized & Improved
REM Environment: Windows 10/11 with admin rights, internet connection
REM Purpose: Install and verify all required dependencies using unified approach
REM Architecture: Configuration-driven, ordered installation, unified error handling
REM -----------------------------------------------------------------------------

REM Dependency Configuration - Easy to modify and extend
SET "DEP_COUNT=6"
SET "DEP_1_NAME=PowerShell 7"
SET "DEP_1_CHECK=pwsh.exe --version"
SET "DEP_1_INSTALL_PRIMARY=winget install --id Microsoft.PowerShell --accept-source-agreements --accept-package-agreements --silent"
SET "DEP_1_INSTALL_FALLBACK=powershell -ExecutionPolicy Bypass -Command \"try { $tempPath = $env:TEMP; $scriptPath = Join-Path $tempPath 'install-powershell.ps1'; Invoke-WebRequest -Uri 'https://aka.ms/install-powershell.ps1' -OutFile $scriptPath -UseBasicParsing; & $scriptPath -UseMSI -Quiet; Remove-Item $scriptPath -Force -ErrorAction SilentlyContinue } catch { exit 1 }\""
SET "DEP_1_UPDATE=winget upgrade --id Microsoft.PowerShell --accept-source-agreements --accept-package-agreements --silent"
SET "DEP_1_CRITICAL=NO"

SET "DEP_2_NAME=Winget"
SET "DEP_2_CHECK=winget.exe --version"
SET "DEP_2_INSTALL_PRIMARY=powershell -ExecutionPolicy Bypass -Command \"try { $tempPath = $env:TEMP; $bundlePath = Join-Path $tempPath 'Microsoft.DesktopAppInstaller.msixbundle'; Invoke-WebRequest -Uri 'https://aka.ms/getwinget' -OutFile $bundlePath -UseBasicParsing; Add-AppxPackage -Path $bundlePath; Remove-Item $bundlePath -Force -ErrorAction SilentlyContinue } catch { exit 1 }\""
SET "DEP_2_INSTALL_FALLBACK=powershell -ExecutionPolicy Bypass -Command \"try { $latestUrl = (Invoke-RestMethod 'https://api.github.com/repos/microsoft/winget-cli/releases/latest').assets | Where-Object { $_.name -like '*msixbundle' } | Select-Object -First 1 -ExpandProperty browser_download_url; $tempPath = $env:TEMP; $bundlePath = Join-Path $tempPath 'winget-latest.msixbundle'; Invoke-WebRequest -Uri $latestUrl -OutFile $bundlePath -UseBasicParsing; Add-AppxPackage -Path $bundlePath; Remove-Item $bundlePath -Force -ErrorAction SilentlyContinue } catch { exit 1 }\""
SET "DEP_2_UPDATE=winget upgrade --id Microsoft.DesktopAppInstaller --accept-source-agreements --accept-package-agreements --silent"
SET "DEP_2_CRITICAL=NO"

SET "DEP_3_NAME=Chocolatey"
SET "DEP_3_CHECK=choco --version"
SET "DEP_3_INSTALL_PRIMARY=powershell -ExecutionPolicy Bypass -Command \"Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; try { Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1')) } catch { exit 1 }\""
SET "DEP_3_INSTALL_FALLBACK="
SET "DEP_3_UPDATE=choco upgrade chocolatey -y --limit-output"
SET "DEP_3_CRITICAL=NO"
SET "DEP_3_PATH_LOCATIONS=%ProgramData%\chocolatey\bin;%ALLUSERSPROFILE%\chocolatey\bin"

SET "DEP_4_NAME=NuGet CLI"
SET "DEP_4_CHECK=nuget help"
SET "DEP_4_INSTALL_PRIMARY=powershell -ExecutionPolicy Bypass -Command \"try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; $nugetPath = '%ProgramData%\nuget'; if (-not (Test-Path $nugetPath)) { New-Item -Path $nugetPath -ItemType Directory -Force }; Invoke-WebRequest -Uri 'https://dist.nuget.org/win-x86-commandline/latest/nuget.exe' -OutFile (Join-Path $nugetPath 'nuget.exe') -UseBasicParsing -TimeoutSec 30 } catch { exit 1 }\""
SET "DEP_4_INSTALL_FALLBACK="
SET "DEP_4_UPDATE=powershell -ExecutionPolicy Bypass -Command \"try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri 'https://dist.nuget.org/win-x86-commandline/latest/nuget.exe' -OutFile '%ProgramData%\nuget\nuget.exe' -UseBasicParsing -TimeoutSec 30 } catch { exit 1 }\""
SET "DEP_4_CRITICAL=NO"
SET "DEP_4_PATH_LOCATIONS=%ProgramData%\nuget"

SET "DEP_5_NAME=NuGet PowerShell Provider"
SET "DEP_5_CHECK=powershell -Command \"(Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue).Version -ge [version]'2.8.5.201'\""
SET "DEP_5_INSTALL_PRIMARY=powershell -ExecutionPolicy Bypass -Command \"try { $ErrorActionPreference = 'SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted -ErrorAction SilentlyContinue; Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -ForceBootstrap -Scope AllUsers -Confirm:$false -SkipPublisherCheck -AllowClobber -ErrorAction Stop } catch { exit 1 }\""
SET "DEP_5_INSTALL_FALLBACK="
SET "DEP_5_UPDATE="
SET "DEP_5_CRITICAL=NO"

SET "DEP_6_NAME=PSWindowsUpdate Module"
SET "DEP_6_CHECK=powershell -Command \"Get-Module -ListAvailable -Name PSWindowsUpdate -ErrorAction SilentlyContinue\""
SET "DEP_6_INSTALL_PRIMARY=powershell -ExecutionPolicy Bypass -Command \"try { $ErrorActionPreference = 'SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted -ErrorAction SilentlyContinue; Install-Module -Name PSWindowsUpdate -Force -Scope AllUsers -Confirm:$false -SkipPublisherCheck -AllowClobber -AcceptLicense -ErrorAction Stop } catch { exit 1 }\""
SET "DEP_6_INSTALL_FALLBACK="
SET "DEP_6_UPDATE=powershell -Command \"try { Update-Module -Name PSWindowsUpdate -Force -ErrorAction Stop } catch { exit 1 }\""
SET "DEP_6_CRITICAL=NO"

ECHO [%TIME%] [INFO] Starting centralized dependency management...
SET "DEPS_SUCCESS=0"
SET "DEPS_FAILED=0"
SET "DEPS_WORKING="
SET "DEPS_MISSING="

REM Process each dependency in order
FOR /L %%i IN (1,1,%DEP_COUNT%) DO (
    CALL :ProcessDependency %%i
)

REM Final status report
ECHO [%TIME%] [INFO] === Dependency Installation Summary ===
ECHO [%TIME%] [INFO] Successfully processed: %DEPS_SUCCESS%/%DEP_COUNT% dependencies
IF %DEPS_FAILED% GTR 0 (
    ECHO [%TIME%] [WARN] Failed dependencies: %DEPS_FAILED%
    ECHO [%TIME%] [WARN] Missing:%DEPS_MISSING%
    ECHO [%TIME%] [WARN] Some maintenance features may be limited.
) ELSE (
    ECHO [%TIME%] [INFO] All dependencies are working correctly.
)
IF NOT "%DEPS_WORKING%"=="" (
    ECHO [%TIME%] [INFO] Working:%DEPS_WORKING%
)
ECHO [%TIME%] [INFO] === End Dependency Summary ===

REM Final PATH update for current session
CALL :UpdateSessionPath

GOTO :ContinueAfterDependencies

REM -----------------------------------------------------------------------------
REM Unified Dependency Processing Function
REM Handles installation, update, verification, and PATH management
REM -----------------------------------------------------------------------------
:ProcessDependency
SETLOCAL EnableDelayedExpansion
SET "DEP_NUM=%1"
SET "DEP_NAME=!DEP_%DEP_NUM%_NAME!"
SET "DEP_CHECK=!DEP_%DEP_NUM%_CHECK!"
SET "DEP_INSTALL_PRIMARY=!DEP_%DEP_NUM%_INSTALL_PRIMARY!"
SET "DEP_INSTALL_FALLBACK=!DEP_%DEP_NUM%_INSTALL_FALLBACK!"
SET "DEP_UPDATE=!DEP_%DEP_NUM%_UPDATE!"
SET "DEP_CRITICAL=!DEP_%DEP_NUM%_CRITICAL!"
SET "DEP_PATH_LOCATIONS=!DEP_%DEP_NUM%_PATH_LOCATIONS!"

ECHO [%TIME%] [INFO] Processing dependency: !DEP_NAME!

REM Check if already installed
!DEP_CHECK! >nul 2>&1
IF !ERRORLEVEL! EQU 0 (
    ECHO [%TIME%] [INFO] !DEP_NAME! is already available.
    IF NOT "!DEP_UPDATE!"=="" (
        ECHO [%TIME%] [INFO] Checking for updates...
        !DEP_UPDATE! >nul 2>&1
        IF !ERRORLEVEL! EQU 0 (
            ECHO [%TIME%] [INFO] !DEP_NAME! updated successfully.
        ) ELSE (
            ECHO [%TIME%] [INFO] !DEP_NAME! is up to date or update not needed.
        )
    )
    SET /A DEPS_SUCCESS+=1
    SET "DEPS_WORKING=!DEPS_WORKING! !DEP_NAME!"
    GOTO :ProcessDependency_End
)

REM Check for PATH issues if locations are specified
IF NOT "!DEP_PATH_LOCATIONS!"=="" (
    CALL :CheckAndFixPath "!DEP_PATH_LOCATIONS!" "!DEP_CHECK!" "!DEP_NAME!"
    IF !ERRORLEVEL! EQU 0 (
        SET /A DEPS_SUCCESS+=1
        SET "DEPS_WORKING=!DEPS_WORKING! !DEP_NAME!"
        GOTO :ProcessDependency_End
    )
)

REM Install using primary method
ECHO [%TIME%] [INFO] Installing !DEP_NAME! (primary method)...
!DEP_INSTALL_PRIMARY! >nul 2>&1
timeout /t 3 /nobreak >nul

REM Verify primary installation
!DEP_CHECK! >nul 2>&1
IF !ERRORLEVEL! EQU 0 (
    ECHO [%TIME%] [INFO] !DEP_NAME! installed successfully (primary method).
    SET /A DEPS_SUCCESS+=1
    SET "DEPS_WORKING=!DEPS_WORKING! !DEP_NAME!"
    GOTO :ProcessDependency_End
)

REM Try fallback method if available
IF NOT "!DEP_INSTALL_FALLBACK!"=="" (
    ECHO [%TIME%] [WARN] Primary installation failed. Trying fallback method...
    !DEP_INSTALL_FALLBACK! >nul 2>&1
    timeout /t 5 /nobreak >nul
    
    REM Verify fallback installation
    !DEP_CHECK! >nul 2>&1
    IF !ERRORLEVEL! EQU 0 (
        ECHO [%TIME%] [INFO] !DEP_NAME! installed successfully (fallback method).
        SET /A DEPS_SUCCESS+=1
        SET "DEPS_WORKING=!DEPS_WORKING! !DEP_NAME!"
        GOTO :ProcessDependency_End
    )
)

REM Installation failed
IF "!DEP_CRITICAL!"=="YES" (
    ECHO [%TIME%] [ERROR] Critical dependency !DEP_NAME! installation failed.
) ELSE (
    ECHO [%TIME%] [WARN] Optional dependency !DEP_NAME! installation failed.
)
SET /A DEPS_FAILED+=1
SET "DEPS_MISSING=!DEPS_MISSING! !DEP_NAME!"

:ProcessDependency_End
ENDLOCAL & SET "DEPS_SUCCESS=%DEPS_SUCCESS%" & SET "DEPS_FAILED=%DEPS_FAILED%" & SET "DEPS_WORKING=%DEPS_WORKING%" & SET "DEPS_MISSING=%DEPS_MISSING%"
GOTO :EOF

REM -----------------------------------------------------------------------------
REM PATH Management Function
REM Checks common installation locations and fixes PATH if needed
REM -----------------------------------------------------------------------------
:CheckAndFixPath
SETLOCAL
SET "LOCATIONS=%~1"
SET "CHECK_COMMAND=%~2"
SET "TOOL_NAME=%~3"
SET "FOUND=NO"

FOR %%P IN (%LOCATIONS%) DO (
    IF EXIST "%%P" (
        ECHO [%TIME%] [INFO] Found !TOOL_NAME! at %%P, adding to PATH...
        SET "PATH=%PATH%;%%P"
        %CHECK_COMMAND% >nul 2>&1
        IF !ERRORLEVEL! EQU 0 (
            ECHO [%TIME%] [INFO] !TOOL_NAME! is now accessible after PATH correction.
            SET "FOUND=YES"
            GOTO :CheckAndFixPath_End
        )
    )
)

:CheckAndFixPath_End
IF "%FOUND%"=="YES" (
    ENDLOCAL & SET "PATH=%PATH%"
    EXIT /B 0
) ELSE (
    ENDLOCAL
    EXIT /B 1
)

REM -----------------------------------------------------------------------------
REM Session PATH Update Function
REM Updates PATH for current session with all dependency locations
REM -----------------------------------------------------------------------------
:UpdateSessionPath
ECHO %PATH% | FIND /I "%ProgramData%\chocolatey\bin" >nul 2>&1
IF %ERRORLEVEL% NEQ 0 (
    IF EXIST "%ProgramData%\chocolatey\bin" SET "PATH=%PATH%;%ProgramData%\chocolatey\bin"
)
ECHO %PATH% | FIND /I "%ProgramData%\nuget" >nul 2>&1
IF %ERRORLEVEL% NEQ 0 (
    IF EXIST "%ProgramData%\nuget" SET "PATH=%PATH%;%ProgramData%\nuget"
)
GOTO :EOF

:ContinueAfterDependencies

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
