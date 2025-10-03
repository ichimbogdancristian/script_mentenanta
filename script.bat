@echo off
REM ============================================================================
REM  Windows Maintenance Automation Launcher v2.2 (Enhanced Debugging)
REM  Purpose: Universal launcher for modular Windows maintenance system
REM  Requirements: Windows 10/11, Administrator privileges
REM ============================================================================

SETLOCAL ENABLEDELAYEDEXPANSION

REM -----------------------------------------------------------------------------
REM Enhanced Logging System with Verbose Output
REM -----------------------------------------------------------------------------
GOTO :MAIN_SCRIPT

:LOG_MESSAGE
SET "LOG_TIMESTAMP=%TIME:~0,8%"
SET "LEVEL=%~2"
IF "%LEVEL%"=="" SET "LEVEL=INFO"
SET "COMPONENT=%~3"
IF "%COMPONENT%"=="" SET "COMPONENT=LAUNCHER"

SET "LOG_ENTRY=[%DATE% %LOG_TIMESTAMP%] [%LEVEL%] [%COMPONENT%] %~1"

REM Color coding for console output
IF "%LEVEL%"=="ERROR" (
    ECHO [91m%LOG_ENTRY%[0m
) ELSE IF "%LEVEL%"=="WARN" (
    ECHO [93m%LOG_ENTRY%[0m
) ELSE IF "%LEVEL%"=="SUCCESS" (
    ECHO [92m%LOG_ENTRY%[0m
) ELSE IF "%LEVEL%"=="DEBUG" (
    ECHO [96m%LOG_ENTRY%[0m
) ELSE (
    ECHO %LOG_ENTRY%
)

IF DEFINED LOG_FILE (
    IF NOT EXIST "%LOG_FILE%" (
        FOR %%F IN ("%LOG_FILE%") DO (
            IF NOT EXIST "%%~dpF" MD "%%~dpF" 2>nul
        )
        ECHO. > "%LOG_FILE%" 2>nul
    )
    ECHO %LOG_ENTRY% >> "%LOG_FILE%" 2>nul
)
EXIT /B

:REFRESH_PATH
CALL :LOG_MESSAGE "Refreshing PATH environment variable..." "DEBUG" "LAUNCHER"
FOR /F "usebackq tokens=2*" %%A IN (`REG QUERY "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" /v PATH 2^>nul`) DO SET "SYSTEM_PATH=%%B"
FOR /F "usebackq tokens=2*" %%A IN (`REG QUERY "HKCU\Environment" /v PATH 2^>nul`) DO SET "USER_PATH=%%B"
IF DEFINED USER_PATH (
    SET "PATH=%SYSTEM_PATH%;%USER_PATH%"
    CALL :LOG_MESSAGE "PATH updated with SYSTEM and USER paths" "DEBUG" "LAUNCHER"
) ELSE (
    SET "PATH=%SYSTEM_PATH%"
    CALL :LOG_MESSAGE "PATH updated with SYSTEM path only" "DEBUG" "LAUNCHER"
)
CALL :LOG_MESSAGE "Current PATH: %PATH%" "DEBUG" "LAUNCHER"
EXIT /B

:CHECK_POWERSHELL7
CALL :LOG_MESSAGE "=== PowerShell 7 Detection Start ===" "DEBUG" "PS7_CHECK"

REM Method 1: Check pwsh.exe in PATH
CALL :LOG_MESSAGE "Checking for pwsh.exe in PATH..." "DEBUG" "PS7_CHECK"
pwsh.exe -Version >nul 2>&1
SET "PWSH_CHECK_RESULT=!ERRORLEVEL!"
CALL :LOG_MESSAGE "pwsh.exe -Version returned exit code: !PWSH_CHECK_RESULT!" "DEBUG" "PS7_CHECK"

IF !PWSH_CHECK_RESULT! EQU 0 (
    FOR /F "tokens=*" %%i IN ('pwsh.exe -NoProfile -Command "$PSVersionTable.PSVersion.ToString()" 2^>nul') DO SET "PS7_VERSION=%%i"
    CALL :LOG_MESSAGE "PowerShell 7 found via PATH: !PS7_VERSION!" "SUCCESS" "PS7_CHECK"
    SET "PS7_AVAILABLE=YES"
    SET "PS7_PATH=pwsh.exe"
    GOTO :PS7_CHECK_COMPLETE
)

REM Method 2: Check common installation paths
CALL :LOG_MESSAGE "pwsh.exe not in PATH, checking common installation directories..." "DEBUG" "PS7_CHECK"

SET "PS7_AVAILABLE=NO"
FOR %%P IN (
    "%ProgramFiles%\PowerShell\7\pwsh.exe"
    "%ProgramFiles(x86)%\PowerShell\7\pwsh.exe"
    "%LOCALAPPDATA%\Microsoft\WindowsApps\pwsh.exe"
    "%ProgramFiles%\PowerShell\pwsh.exe"
) DO (
    CALL :LOG_MESSAGE "Checking path: %%P" "DEBUG" "PS7_CHECK"
    IF EXIST "%%~P" (
        CALL :LOG_MESSAGE "Found PowerShell 7 at: %%~P" "SUCCESS" "PS7_CHECK"
        SET "PS7_PATH=%%~P"
        SET "PS7_AVAILABLE=YES"
        
        REM Get version
        FOR /F "tokens=*" %%V IN ('"%%~P" -NoProfile -Command "$PSVersionTable.PSVersion.ToString()" 2^>nul') DO SET "PS7_VERSION=%%V"
        CALL :LOG_MESSAGE "PowerShell 7 version: !PS7_VERSION!" "INFO" "PS7_CHECK"
        GOTO :PS7_CHECK_COMPLETE
    )
)

CALL :LOG_MESSAGE "PowerShell 7 not found in any known location" "WARN" "PS7_CHECK"

:PS7_CHECK_COMPLETE
CALL :LOG_MESSAGE "=== PowerShell 7 Detection Complete ===" "DEBUG" "PS7_CHECK"
CALL :LOG_MESSAGE "PS7_AVAILABLE: %PS7_AVAILABLE%" "DEBUG" "PS7_CHECK"
CALL :LOG_MESSAGE "PS7_PATH: %PS7_PATH%" "DEBUG" "PS7_CHECK"
EXIT /B

:INSTALL_POWERSHELL7
CALL :LOG_MESSAGE "=== PowerShell 7 Installation Start ===" "INFO" "PS7_INSTALL"

REM Determine architecture
CALL :LOG_MESSAGE "Detecting system architecture..." "DEBUG" "PS7_INSTALL"
CALL :LOG_MESSAGE "PROCESSOR_ARCHITECTURE: %PROCESSOR_ARCHITECTURE%" "DEBUG" "PS7_INSTALL"

IF "%PROCESSOR_ARCHITECTURE%"=="AMD64" (
    SET "PS7_URL=https://github.com/PowerShell/PowerShell/releases/download/v7.5.2/PowerShell-7.5.2-win-x64.msi"
    CALL :LOG_MESSAGE "Using x64 installer" "INFO" "PS7_INSTALL"
) ELSE IF "%PROCESSOR_ARCHITECTURE%"=="ARM64" (
    SET "PS7_URL=https://github.com/PowerShell/PowerShell/releases/download/v7.5.2/PowerShell-7.5.2-win-arm64.msi"
    CALL :LOG_MESSAGE "Using ARM64 installer" "INFO" "PS7_INSTALL"
) ELSE (
    SET "PS7_URL=https://github.com/PowerShell/PowerShell/releases/download/v7.5.2/PowerShell-7.5.2-win-x86.msi"
    CALL :LOG_MESSAGE "Using x86 installer" "INFO" "PS7_INSTALL"
)

SET "PS7_INSTALLER=%TEMP%\PowerShell-7.5.2-Setup.msi"
CALL :LOG_MESSAGE "Download URL: %PS7_URL%" "DEBUG" "PS7_INSTALL"
CALL :LOG_MESSAGE "Installer path: %PS7_INSTALLER%" "DEBUG" "PS7_INSTALL"

REM Clean up any existing installer
IF EXIST "%PS7_INSTALLER%" (
    CALL :LOG_MESSAGE "Removing existing installer file..." "DEBUG" "PS7_INSTALL"
    DEL /F /Q "%PS7_INSTALLER%" >nul 2>&1
)

REM Download PowerShell 7
CALL :LOG_MESSAGE "Downloading PowerShell 7.5.2..." "INFO" "PS7_INSTALL"
CALL :LOG_MESSAGE "This may take several minutes depending on connection speed..." "INFO" "PS7_INSTALL"

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$ProgressPreference = 'SilentlyContinue'; " ^
    "Write-Host '[DEBUG] Starting download...'; " ^
    "try { " ^
    "    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; " ^
    "    Write-Host '[DEBUG] TLS 1.2 enabled'; " ^
    "    Write-Host '[DEBUG] Downloading from: %PS7_URL%'; " ^
    "    Write-Host '[DEBUG] Saving to: %PS7_INSTALLER%'; " ^
    "    $startTime = Get-Date; " ^
    "    Invoke-WebRequest -Uri '%PS7_URL%' -OutFile '%PS7_INSTALLER%' -UseBasicParsing -TimeoutSec 300; " ^
    "    $duration = ((Get-Date) - $startTime).TotalSeconds; " ^
    "    Write-Host '[SUCCESS] Download completed in' $duration 'seconds'; " ^
    "    $fileSize = (Get-Item '%PS7_INSTALLER%').Length / 1MB; " ^
    "    Write-Host '[DEBUG] Downloaded file size:' ([math]::Round($fileSize, 2)) 'MB'; " ^
    "    exit 0; " ^
    "} catch { " ^
    "    Write-Host '[ERROR] Download failed:' $_.Exception.Message; " ^
    "    Write-Host '[ERROR] Exception type:' $_.Exception.GetType().FullName; " ^
    "    exit 1; " ^
    "}"

SET "DOWNLOAD_RESULT=!ERRORLEVEL!"
CALL :LOG_MESSAGE "Download command exit code: %DOWNLOAD_RESULT%" "DEBUG" "PS7_INSTALL"

IF %DOWNLOAD_RESULT% NEQ 0 (
    CALL :LOG_MESSAGE "PowerShell 7 download failed with exit code %DOWNLOAD_RESULT%" "ERROR" "PS7_INSTALL"
    EXIT /B 1
)

REM Verify download
IF NOT EXIST "%PS7_INSTALLER%" (
    CALL :LOG_MESSAGE "Installer file not found after download" "ERROR" "PS7_INSTALL"
    EXIT /B 1
)

FOR %%F IN ("%PS7_INSTALLER%") DO SET "FILE_SIZE=%%~zF"
CALL :LOG_MESSAGE "Installer file size: %FILE_SIZE% bytes" "DEBUG" "PS7_INSTALL"

IF %FILE_SIZE% LSS 100000 (
    CALL :LOG_MESSAGE "Installer file too small - download likely failed" "ERROR" "PS7_INSTALL"
    TYPE "%PS7_INSTALLER%"
    EXIT /B 1
)

REM Install PowerShell 7
CALL :LOG_MESSAGE "Installing PowerShell 7..." "INFO" "PS7_INSTALL"
CALL :LOG_MESSAGE "Running msiexec with /i /quiet /norestart flags..." "DEBUG" "PS7_INSTALL"

msiexec /i "%PS7_INSTALLER%" /quiet /norestart /log "%TEMP%\PS7_Install.log"
SET "INSTALL_RESULT=!ERRORLEVEL!"

CALL :LOG_MESSAGE "msiexec exit code: %INSTALL_RESULT%" "DEBUG" "PS7_INSTALL"

REM Display installation log if available
IF EXIST "%TEMP%\PS7_Install.log" (
    CALL :LOG_MESSAGE "Installation log created at: %TEMP%\PS7_Install.log" "DEBUG" "PS7_INSTALL"
    CALL :LOG_MESSAGE "Last 10 lines of installation log:" "DEBUG" "PS7_INSTALL"
    powershell -NoProfile -Command "Get-Content '%TEMP%\PS7_Install.log' -Tail 10 | ForEach-Object { Write-Host '[LOG] ' + $_ }"
)

IF %INSTALL_RESULT% EQU 0 (
    CALL :LOG_MESSAGE "PowerShell 7 installation completed successfully" "SUCCESS" "PS7_INSTALL"
) ELSE IF %INSTALL_RESULT% EQU 3010 (
    CALL :LOG_MESSAGE "PowerShell 7 installation completed (restart required)" "SUCCESS" "PS7_INSTALL"
) ELSE (
    CALL :LOG_MESSAGE "PowerShell 7 installation failed with exit code %INSTALL_RESULT%" "ERROR" "PS7_INSTALL"
    CALL :LOG_MESSAGE "Check log at: %TEMP%\PS7_Install.log" "ERROR" "PS7_INSTALL"
    EXIT /B 1
)

REM Wait for installation to settle
CALL :LOG_MESSAGE "Waiting 5 seconds for installation to settle..." "DEBUG" "PS7_INSTALL"
timeout /t 5 /nobreak >nul

REM Refresh PATH
CALL :REFRESH_PATH

REM Add PowerShell 7 paths to current session
CALL :LOG_MESSAGE "Adding PowerShell 7 paths to current session..." "DEBUG" "PS7_INSTALL"
IF EXIST "%ProgramFiles%\PowerShell\7" (
    SET "PATH=%PATH%;%ProgramFiles%\PowerShell\7"
    CALL :LOG_MESSAGE "Added to PATH: %ProgramFiles%\PowerShell\7" "DEBUG" "PS7_INSTALL"
)

REM Clean up installer
CALL :LOG_MESSAGE "Cleaning up installer file..." "DEBUG" "PS7_INSTALL"
DEL /F /Q "%PS7_INSTALLER%" >nul 2>&1

REM Verify installation
CALL :LOG_MESSAGE "Verifying PowerShell 7 installation..." "DEBUG" "PS7_INSTALL"
CALL :CHECK_POWERSHELL7

IF "%PS7_AVAILABLE%"=="YES" (
    CALL :LOG_MESSAGE "PowerShell 7 successfully installed and verified" "SUCCESS" "PS7_INSTALL"
    EXIT /B 0
) ELSE (
    CALL :LOG_MESSAGE "PowerShell 7 installation verification failed" "WARN" "PS7_INSTALL"
    CALL :LOG_MESSAGE "Installation may require a system restart to take effect" "WARN" "PS7_INSTALL"
    EXIT /B 1
)

CALL :LOG_MESSAGE "=== PowerShell 7 Installation Complete ===" "INFO" "PS7_INSTALL"
EXIT /B

:MAIN_SCRIPT

REM -----------------------------------------------------------------------------
REM Self-Discovery Environment Setup
REM -----------------------------------------------------------------------------
ECHO.
ECHO ================================================================================
ECHO  Windows Maintenance Automation Launcher v2.2
ECHO ================================================================================
ECHO.

SET "SCRIPT_PATH=%~f0"
SET "SCRIPT_DIR=%~dp0"
SET "SCRIPT_NAME=%~nx0"
SET "WORKING_DIR=%SCRIPT_DIR%"

CALL :LOG_MESSAGE "Starting Windows Maintenance Automation Launcher v2.2" "INFO" "LAUNCHER"
CALL :LOG_MESSAGE "Script path: %SCRIPT_PATH%" "DEBUG" "LAUNCHER"
CALL :LOG_MESSAGE "Script directory: %SCRIPT_DIR%" "DEBUG" "LAUNCHER"
CALL :LOG_MESSAGE "Working directory: %WORKING_DIR%" "DEBUG" "LAUNCHER"

REM Setup logging
IF NOT EXIST "%WORKING_DIR%temp_files\logs" (
    CALL :LOG_MESSAGE "Creating logs directory..." "DEBUG" "LAUNCHER"
    MD "%WORKING_DIR%temp_files\logs" 2>nul
)
SET "LOG_FILE=%WORKING_DIR%temp_files\logs\maintenance_%DATE:~-4,4%%DATE:~-10,2%%DATE:~-7,2%_%TIME:~0,2%%TIME:~3,2%%TIME:~6,2%.log"
SET "LOG_FILE=%LOG_FILE: =0%"
SET "WORKING_DIRECTORY=%WORKING_DIR%"
SET "SCRIPT_LOG_FILE=%LOG_FILE%"

CALL :LOG_MESSAGE "Log file: %LOG_FILE%" "INFO" "LAUNCHER"

REM Check if this is a post-restart execution
SET "IS_POST_RESTART=NO"
SET "ELEVATION_ATTEMPTED=NO"

CALL :LOG_MESSAGE "Parsing command line arguments..." "DEBUG" "LAUNCHER"
FOR %%i in (%*) DO (
    CALL :LOG_MESSAGE "Argument: %%i" "DEBUG" "LAUNCHER"
    IF "%%i"=="-PostRestart" SET "IS_POST_RESTART=YES"
    IF "%%i"=="ELEVATED_INSTANCE" SET "ELEVATION_ATTEMPTED=YES"
)

CALL :LOG_MESSAGE "IS_POST_RESTART: %IS_POST_RESTART%" "DEBUG" "LAUNCHER"
CALL :LOG_MESSAGE "ELEVATION_ATTEMPTED: %ELEVATION_ATTEMPTED%" "DEBUG" "LAUNCHER"

REM Repository configuration
SET "REPO_URL=https://github.com/ichimbogdancristian/script_mentenanta/archive/refs/heads/main.zip"
SET "ZIP_FILE=%WORKING_DIR%update.zip"
SET "EXTRACT_FOLDER=script_mentenanta-main"

REM Task names
SET "TASK_NAME=ScriptMentenantaMonthly"
SET "STARTUP_TASK_NAME=ScriptMentenantaStartup"

REM -----------------------------------------------------------------------------
REM Post-Restart Cleanup (Do this BEFORE anything else)
REM -----------------------------------------------------------------------------
IF "%IS_POST_RESTART%"=="YES" (
    CALL :LOG_MESSAGE "=== POST-RESTART EXECUTION DETECTED ===" "INFO" "LAUNCHER"
    CALL :LOG_MESSAGE "Performing post-restart cleanup..." "INFO" "LAUNCHER"
    
    REM Remove startup task
    CALL :LOG_MESSAGE "Removing startup task: %STARTUP_TASK_NAME%" "DEBUG" "LAUNCHER"
    schtasks /delete /tn "%STARTUP_TASK_NAME%" /f >nul 2>&1
    SET "TASK_DELETE_RESULT=!ERRORLEVEL!"
    
    IF !TASK_DELETE_RESULT! EQU 0 (
        CALL :LOG_MESSAGE "Startup task removed successfully" "SUCCESS" "LAUNCHER"
    ) ELSE (
        CALL :LOG_MESSAGE "No startup task found to remove (exit code: !TASK_DELETE_RESULT!)" "DEBUG" "LAUNCHER"
    )
    
    CALL :LOG_MESSAGE "Proceeding with normal maintenance execution" "INFO" "LAUNCHER"
)

REM -----------------------------------------------------------------------------
REM Administrator Privilege Check
REM -----------------------------------------------------------------------------
CALL :LOG_MESSAGE "Checking administrator privileges..." "INFO" "LAUNCHER"

NET SESSION >nul 2>&1
SET "ADMIN_CHECK_RESULT=!ERRORLEVEL!"
CALL :LOG_MESSAGE "NET SESSION returned exit code: %ADMIN_CHECK_RESULT%" "DEBUG" "LAUNCHER"

IF %ADMIN_CHECK_RESULT% NEQ 0 (
    CALL :LOG_MESSAGE "No admin privileges detected - elevation required" "WARN" "LAUNCHER"
    ECHO.
    ECHO ================================================================================
    ECHO  ADMINISTRATOR PRIVILEGES REQUIRED
    ECHO ================================================================================
    ECHO  This script will now close and relaunch with elevated privileges.
    ECHO  Please accept the UAC prompt when it appears.
    ECHO ================================================================================
    ECHO.
    
    CALL :LOG_MESSAGE "Launching elevated instance..." "DEBUG" "LAUNCHER"
    powershell -NoProfile -Command "Start-Process cmd -ArgumentList '/c \"%~f0\" ELEVATED_INSTANCE %*' -Verb RunAs"
    EXIT /B 0
)

CALL :LOG_MESSAGE "Administrator privileges confirmed" "SUCCESS" "LAUNCHER"

REM -----------------------------------------------------------------------------
REM System Requirements Verification
REM -----------------------------------------------------------------------------
CALL :LOG_MESSAGE "Verifying system requirements..." "INFO" "LAUNCHER"

REM Get OS information
FOR /F "tokens=*" %%i IN ('powershell -NoProfile -Command "[System.Environment]::OSVersion.Version.ToString()" 2^>nul') DO SET "OS_VERSION=%%i"
CALL :LOG_MESSAGE "OS Version: %OS_VERSION%" "INFO" "LAUNCHER"

REM Get PowerShell version
FOR /F "tokens=*" %%i IN ('powershell -NoProfile -Command "$PSVersionTable.PSVersion.Major" 2^>nul') DO SET "PS_VERSION=%%i"
IF "%PS_VERSION%"=="" SET "PS_VERSION=0"
CALL :LOG_MESSAGE "Windows PowerShell version: %PS_VERSION%" "INFO" "LAUNCHER"

IF %PS_VERSION% LSS 5 (
    CALL :LOG_MESSAGE "PowerShell 5.1 or higher required (found: %PS_VERSION%)" "ERROR" "LAUNCHER"
    PAUSE
    EXIT /B 2
)

REM -----------------------------------------------------------------------------
REM Project Structure Discovery
REM -----------------------------------------------------------------------------
CALL :LOG_MESSAGE "Discovering project structure..." "INFO" "LAUNCHER"

SET "STRUCTURE_VALID=YES"
SET "ORCHESTRATOR_PATH="

REM Check for orchestrator
IF EXIST "%WORKING_DIR%MaintenanceOrchestrator.ps1" (
    SET "ORCHESTRATOR_PATH=%WORKING_DIR%MaintenanceOrchestrator.ps1"
    CALL :LOG_MESSAGE "Found orchestrator: MaintenanceOrchestrator.ps1" "SUCCESS" "LAUNCHER"
) ELSE IF EXIST "%WORKING_DIR%script.ps1" (
    SET "ORCHESTRATOR_PATH=%WORKING_DIR%script.ps1"
    CALL :LOG_MESSAGE "Found legacy orchestrator: script.ps1" "INFO" "LAUNCHER"
) ELSE (
    CALL :LOG_MESSAGE "No orchestrator found" "WARN" "LAUNCHER"
    SET "STRUCTURE_VALID=NO"
)

REM Check for config directory
IF EXIST "%WORKING_DIR%config" (
    CALL :LOG_MESSAGE "Found config directory" "SUCCESS" "LAUNCHER"
) ELSE (
    CALL :LOG_MESSAGE "Config directory not found" "WARN" "LAUNCHER"
    SET "STRUCTURE_VALID=NO"
)

REM Check for modules directory
IF EXIST "%WORKING_DIR%modules" (
    CALL :LOG_MESSAGE "Found modules directory" "SUCCESS" "LAUNCHER"
) ELSE (
    CALL :LOG_MESSAGE "Modules directory not found" "WARN" "LAUNCHER"
    SET "STRUCTURE_VALID=NO"
)

IF "%STRUCTURE_VALID%"=="NO" (
    CALL :LOG_MESSAGE "Project structure incomplete - attempting repository download" "INFO" "LAUNCHER"
    GOTO :DOWNLOAD_REPOSITORY
) ELSE (
    CALL :LOG_MESSAGE "Project structure validated" "SUCCESS" "LAUNCHER"
    GOTO :DEPENDENCY_MANAGEMENT
)

REM -----------------------------------------------------------------------------
REM Repository Download
REM -----------------------------------------------------------------------------
:DOWNLOAD_REPOSITORY
CALL :LOG_MESSAGE "=== Repository Download Start ===" "INFO" "LAUNCHER"

IF EXIST "%ZIP_FILE%" (
    CALL :LOG_MESSAGE "Removing existing ZIP file..." "DEBUG" "LAUNCHER"
    DEL /Q "%ZIP_FILE%" >nul 2>&1
)

CALL :LOG_MESSAGE "Downloading from: %REPO_URL%" "INFO" "LAUNCHER"

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$ProgressPreference = 'SilentlyContinue'; " ^
    "try { " ^
    "    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12; " ^
    "    Write-Host '[DEBUG] Starting download...'; " ^
    "    Invoke-WebRequest -Uri '%REPO_URL%' -OutFile '%ZIP_FILE%' -UseBasicParsing -TimeoutSec 60; " ^
    "    Write-Host '[SUCCESS] Download completed'; " ^
    "    exit 0; " ^
    "} catch { " ^
    "    Write-Host '[ERROR]' $_.Exception.Message; " ^
    "    exit 1; " ^
    "}"

IF !ERRORLEVEL! NEQ 0 (
    CALL :LOG_MESSAGE "Repository download failed" "ERROR" "LAUNCHER"
    PAUSE
    EXIT /B 3
)

CALL :LOG_MESSAGE "Extracting repository..." "INFO" "LAUNCHER"
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "try { " ^
    "    Add-Type -AssemblyName System.IO.Compression.FileSystem; " ^
    "    [System.IO.Compression.ZipFile]::ExtractToDirectory('%ZIP_FILE%', '%WORKING_DIR%'); " ^
    "    Write-Host '[SUCCESS] Extraction completed'; " ^
    "    exit 0; " ^
    "} catch { " ^
    "    Write-Host '[ERROR]' $_.Exception.Message; " ^
    "    exit 1; " ^
    "}"

IF !ERRORLEVEL! NEQ 0 (
    CALL :LOG_MESSAGE "Repository extraction failed" "ERROR" "LAUNCHER"
    PAUSE
    EXIT /B 3
)

SET "EXTRACTED_PATH=%WORKING_DIR%%EXTRACT_FOLDER%"
IF EXIST "%EXTRACTED_PATH%\MaintenanceOrchestrator.ps1" (
    SET "ORCHESTRATOR_PATH=%EXTRACTED_PATH%\MaintenanceOrchestrator.ps1"
    SET "WORKING_DIR=%EXTRACTED_PATH%\"
    CALL :LOG_MESSAGE "Updated working directory to: %WORKING_DIR%" "SUCCESS" "LAUNCHER"
) ELSE (
    CALL :LOG_MESSAGE "No orchestrator found in extracted files" "ERROR" "LAUNCHER"
    PAUSE
    EXIT /B 3
)

DEL /Q "%ZIP_FILE%" >nul 2>&1

REM -----------------------------------------------------------------------------
REM Dependency Management
REM -----------------------------------------------------------------------------
:DEPENDENCY_MANAGEMENT
CALL :LOG_MESSAGE "=== Dependency Management Start ===" "INFO" "LAUNCHER"

REM Install Winget
CALL :LOG_MESSAGE "Checking for Windows Package Manager (winget)..." "INFO" "LAUNCHER"
winget --version >nul 2>&1
IF !ERRORLEVEL! NEQ 0 (
    CALL :LOG_MESSAGE "Winget not found - installing..." "INFO" "LAUNCHER"
    SET "WINGET_URL=https://github.com/microsoft/winget-cli/releases/latest/download/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"
    SET "WINGET_FILE=!TEMP!\Microsoft.DesktopAppInstaller.msixbundle"
    
    powershell -ExecutionPolicy Bypass -Command ^
        "$ProgressPreference = 'SilentlyContinue'; " ^
        "try { " ^
        "    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; " ^
        "    Invoke-WebRequest -Uri '!WINGET_URL!' -OutFile '!WINGET_FILE!' -UseBasicParsing; " ^
        "    Add-AppxPackage -Path '!WINGET_FILE!' -ErrorAction Stop; " ^
        "    Write-Host '[SUCCESS] Winget installed'; " ^
        "} catch { " ^
        "    Write-Host '[WARN] Winget installation failed'; " ^
        "}" 2>nul
    DEL /F /Q "!WINGET_FILE!" >nul 2>&1
) ELSE (
    FOR /F "tokens=*" %%i IN ('winget --version 2^>nul') DO SET "WINGET_VERSION=%%i"
    CALL :LOG_MESSAGE "Winget already installed: %WINGET_VERSION%" "SUCCESS" "LAUNCHER"
)

REM Check and Install PowerShell 7
CALL :LOG_MESSAGE "Checking for PowerShell 7..." "INFO" "LAUNCHER"
CALL :CHECK_POWERSHELL7

IF "%PS7_AVAILABLE%"=="NO" (
    CALL :LOG_MESSAGE "PowerShell 7 not found - installing..." "INFO" "LAUNCHER"
    CALL :INSTALL_POWERSHELL7
    
    IF !ERRORLEVEL! NEQ 0 (
        CALL :LOG_MESSAGE "PowerShell 7 installation failed" "ERROR" "LAUNCHER"
        CALL :LOG_MESSAGE "Manual installation required from: https://github.com/PowerShell/PowerShell/releases/latest" "ERROR" "LAUNCHER"
        
        ECHO.
        ECHO ================================================================================
        ECHO  POWERSHELL 7 INSTALLATION FAILED
        ECHO ================================================================================
        ECHO  The maintenance orchestrator requires PowerShell 7.0 or later.
        ECHO  Automatic installation failed. Please install manually:
        ECHO.
        ECHO  Download: https://github.com/PowerShell/PowerShell/releases/latest
        ECHO  OR use winget: winget install Microsoft.PowerShell
        ECHO  OR use Chocolatey: choco install powershell-core
        ECHO ================================================================================
        ECHO.
        PAUSE
        EXIT /B 5
    )
) ELSE (
    CALL :LOG_MESSAGE "PowerShell 7 is available: %PS7_VERSION%" "SUCCESS" "LAUNCHER"
)

REM Install NuGet
CALL :LOG_MESSAGE "Installing NuGet PackageProvider..." "INFO" "LAUNCHER"
ECHO Y | powershell -ExecutionPolicy Bypass -Command ^
    "& { " ^
    "    $env:PACKAGEMANAGEMENT_BOOTSTRAP_LOGLEVEL='None'; " ^
    "    if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) { " ^
    "        try { " ^
    "            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; " ^
    "            Write-Host '[DEBUG] Installing NuGet...'; " ^
    "            Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope AllUsers -ErrorAction Stop; " ^
    "            Write-Host '[SUCCESS] NuGet installed'; " ^
    "        } catch { " ^
    "            Write-Host '[WARN] NuGet installation failed:' $_.Exception.Message; " ^
    "        } " ^
    "    } else { " ^
    "        Write-Host '[INFO] NuGet already installed'; " ^
    "    } " ^
    "}"

REM Configure PSGallery
CALL :LOG_MESSAGE "Configuring PowerShell Gallery..." "INFO" "LAUNCHER"
ECHO Y | powershell -ExecutionPolicy Bypass -Command ^
    "& { " ^
    "    try { " ^
    "        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; " ^
    "        if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) { " ^
    "            Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope AllUsers -Confirm:`$false -ErrorAction SilentlyContinue " ^
    "        }; " ^
    "        Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted -ErrorAction Stop; " ^
    "        Write-Host '[SUCCESS] PowerShell Gallery configured as trusted'; " ^
    "    } catch { " ^
    "        Write-Host '[WARN] Failed to configure PowerShell Gallery:' `$_.Exception.Message; " ^
    "    } " ^
    "}"

REM Install PSWindowsUpdate Module
CALL :LOG_MESSAGE "Installing PSWindowsUpdate module..." "INFO" "LAUNCHER"
ECHO Y | powershell -ExecutionPolicy Bypass -Command ^
    "& { " ^
    "    if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) { " ^
    "        try { " ^
    "            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; " ^
    "            Install-Module -Name PSWindowsUpdate -Force -Scope AllUsers -AllowClobber -Repository PSGallery -Confirm:`$false; " ^
    "            Write-Host '[SUCCESS] PSWindowsUpdate module installed'; " ^
    "        } catch { " ^
    "            Write-Host '[WARN] Failed to install PSWindowsUpdate module:' `$_.Exception.Message; " ^
    "        } " ^
    "    } else { " ^
    "        Write-Host '[INFO] PSWindowsUpdate module already available'; " ^
    "    } " ^
    "}"

REM Install Chocolatey
CALL :LOG_MESSAGE "Installing Chocolatey package manager..." "INFO" "LAUNCHER"
choco --version >nul 2>&1
IF !ERRORLEVEL! NEQ 0 (
    CALL :LOG_MESSAGE "Chocolatey not found - installing..." "INFO" "LAUNCHER"
    powershell -ExecutionPolicy Bypass -Command ^
        "& { " ^
        "    try { " ^
        "        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; " ^
        "        Set-ExecutionPolicy Bypass -Scope Process -Force; " ^
        "        `$chocoInstallScript = (New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'); " ^
        "        Invoke-Expression `$chocoInstallScript; " ^
        "        Write-Host '[SUCCESS] Chocolatey installed'; " ^
        "    } catch { " ^
        "        Write-Host '[WARN] Chocolatey installation failed:' `$_.Exception.Message; " ^
        "    } " ^
        "}"
    
    IF EXIST "%ProgramData%\chocolatey\bin" (
        SET "PATH=%PATH%;%ProgramData%\chocolatey\bin"
        CALL :LOG_MESSAGE "Chocolatey PATH updated" "INFO" "LAUNCHER"
    )
) ELSE (
    FOR /F "tokens=*" %%i IN ('choco --version 2^>nul') DO SET "CHOCO_VERSION=%%i"
    CALL :LOG_MESSAGE "Chocolatey already installed: %CHOCO_VERSION%" "SUCCESS" "LAUNCHER"
)

CALL :LOG_MESSAGE "=== Dependency Management Complete ===" "SUCCESS" "LAUNCHER"

REM -----------------------------------------------------------------------------
REM PowerShell Orchestrator Execution
REM -----------------------------------------------------------------------------
:ORCHESTRATOR_EXECUTION
CALL :LOG_MESSAGE "=== PowerShell Orchestrator Execution ===" "INFO" "LAUNCHER"

IF NOT DEFINED ORCHESTRATOR_PATH (
    CALL :LOG_MESSAGE "No orchestrator path defined" "ERROR" "LAUNCHER"
    PAUSE
    EXIT /B 4
)

IF NOT EXIST "%ORCHESTRATOR_PATH%" (
    CALL :LOG_MESSAGE "Orchestrator not found: %ORCHESTRATOR_PATH%" "ERROR" "LAUNCHER"
    PAUSE
    EXIT /B 4
)

CALL :LOG_MESSAGE "Executing orchestrator: %ORCHESTRATOR_PATH%" "INFO" "LAUNCHER"
CALL :LOG_MESSAGE "Working directory: %WORKING_DIR%" "DEBUG" "LAUNCHER"

REM Execute with PowerShell 7 if available, otherwise Windows PowerShell
IF "%PS7_AVAILABLE%"=="YES" (
    CALL :LOG_MESSAGE "Using PowerShell 7: %PS7_PATH%" "INFO" "LAUNCHER"
    "%PS7_PATH%" -NoProfile -ExecutionPolicy Bypass -File "%ORCHESTRATOR_PATH%" -WorkingDirectory "%WORKING_DIR%" -LogFile "%LOG_FILE%"
) ELSE (
    CALL :LOG_MESSAGE "Using Windows PowerShell 5.1" "INFO" "LAUNCHER"
    powershell -NoProfile -ExecutionPolicy Bypass -File "%ORCHESTRATOR_PATH%" -WorkingDirectory "%WORKING_DIR%" -LogFile "%LOG_FILE%"
)

SET "ORCHESTRATOR_RESULT=!ERRORLEVEL!"
CALL :LOG_MESSAGE "Orchestrator execution completed with exit code: %ORCHESTRATOR_RESULT%" "INFO" "LAUNCHER"

IF %ORCHESTRATOR_RESULT% EQU 0 (
    CALL :LOG_MESSAGE "Maintenance script completed successfully" "SUCCESS" "LAUNCHER"
) ELSE (
    CALL :LOG_MESSAGE "Maintenance script completed with errors (exit code: %ORCHESTRATOR_RESULT%)" "WARN" "LAUNCHER"
)

REM -----------------------------------------------------------------------------
REM Cleanup and Exit
REM -----------------------------------------------------------------------------
:CLEANUP
CALL :LOG_MESSAGE "=== Cleanup Phase ===" "INFO" "LAUNCHER"

REM Remove temporary files
IF EXIST "%ZIP_FILE%" (
    DEL /F /Q "%ZIP_FILE%" >nul 2>&1
    CALL :LOG_MESSAGE "Removed temporary ZIP file" "DEBUG" "LAUNCHER"
)

CALL :LOG_MESSAGE "Maintenance automation launcher completed" "SUCCESS" "LAUNCHER"
CALL :LOG_MESSAGE "Log file: %LOG_FILE%" "INFO" "LAUNCHER"

ECHO.
ECHO ================================================================================
ECHO  Maintenance Complete
ECHO ================================================================================
ECHO  Check the log file for detailed results: %LOG_FILE%
ECHO ================================================================================
ECHO.

PAUSE
EXIT /B %ORCHESTRATOR_RESULT%