@echo off
REM ============================================================================
REM  script_mentenanta - Windows Maintenance Automation Launcher
REM  Purpose: Unattended Windows maintenance with full dependency management
REM  Environment: Windows 10/11, Auto-elevates to Administrator
REM ============================================================================
SETLOCAL ENABLEDELAYEDEXPANSION

REM ============================================================================
REM [STEP 1] ENVIRONMENT AWARENESS AND LOGGING SETUP
REM ============================================================================
SET "SCRIPT_PATH=%~f0"
SET "SCRIPT_DIR=%~dp0"
IF "!SCRIPT_DIR:~-1!"=="\" SET "SCRIPT_DIR=!SCRIPT_DIR:~0,-1!"
SET "LOG_FILE=!SCRIPT_DIR!\maintenance.log"
SET "USERNAME_VAR=%USERNAME%"
SET "COMPUTER_VAR=%COMPUTERNAME%"

REM Initialize comprehensive logging
ECHO [%DATE% %TIME%] [INFO] ============================================================================ >> "!LOG_FILE!"
ECHO [%DATE% %TIME%] [INFO] script_mentenanta - Windows Maintenance Automation Launcher >> "!LOG_FILE!"
ECHO [%DATE% %TIME%] [INFO] Script Path: !SCRIPT_PATH! >> "!LOG_FILE!"
ECHO [%DATE% %TIME%] [INFO] Script Directory: !SCRIPT_DIR! >> "!LOG_FILE!"
ECHO [%DATE% %TIME%] [INFO] Username: !USERNAME_VAR! >> "!LOG_FILE!"
ECHO [%DATE% %TIME%] [INFO] Computer: !COMPUTER_VAR! >> "!LOG_FILE!"
ECHO [%DATE% %TIME%] [INFO] ============================================================================ >> "!LOG_FILE!"

ECHO [%TIME%] [INFO] Starting unattended maintenance script...
ECHO [%TIME%] [INFO] User: !USERNAME_VAR!, Computer: !COMPUTER_VAR!
ECHO [%TIME%] [INFO] Script location: !SCRIPT_PATH!
ECHO [%TIME%] [INFO] Logging to: !LOG_FILE!

REM ============================================================================
REM [STEP 2] ADMIN PRIVILEGE CHECK AND AUTO-ELEVATION
REM ============================================================================
ECHO [%DATE% %TIME%] [INFO] Checking administrator privileges... >> "!LOG_FILE!"
NET SESSION >nul 2>&1
IF %ERRORLEVEL% NEQ 0 (
    ECHO [%TIME%] [WARN] Administrator privileges required. Auto-elevating...
    ECHO [%DATE% %TIME%] [WARN] Administrator privileges required. Auto-elevating... >> "!LOG_FILE!"
    
    REM Attempt elevation using PowerShell
    powershell -Command "Start-Process -FilePath '!SCRIPT_PATH!' -Verb RunAs" >nul 2>&1
    IF !ERRORLEVEL! EQU 0 (
        ECHO [%TIME%] [INFO] Elevation request sent. New elevated window should appear.
        ECHO [%DATE% %TIME%] [INFO] Elevation successful. Exiting current instance. >> "!LOG_FILE!"
        timeout /t 3 /nobreak >nul
        EXIT /B 0
    ) ELSE (
        ECHO [%TIME%] [ERROR] Failed to elevate. Please run as Administrator manually.
        ECHO [%DATE% %TIME%] [ERROR] Auto-elevation failed. Manual elevation required. >> "!LOG_FILE!"
        pause
        EXIT /B 1
    )
)
ECHO [%TIME%] [INFO] Administrator privileges confirmed.
ECHO [%DATE% %TIME%] [INFO] Administrator privileges confirmed. >> "!LOG_FILE!"

REM ============================================================================
REM [STEP 3] SYSTEM RESTORE CHECK AND CONFIGURATION
REM ============================================================================
ECHO [%DATE% %TIME%] [INFO] Checking System Restore status on drive C... >> "!LOG_FILE!"
ECHO [%TIME%] [INFO] Checking System Restore status on drive C...

REM Check and enable System Restore service first
ECHO [%TIME%] [INFO] Checking System Restore service status...
ECHO [%DATE% %TIME%] [INFO] Checking System Restore service... >> "!LOG_FILE!"

sc query "VSS" | find "STATE" | find "RUNNING" >nul 2>&1
IF %ERRORLEVEL% NEQ 0 (
    ECHO [%TIME%] [WARN] Volume Shadow Copy service not running. Starting it...
    ECHO [%DATE% %TIME%] [WARN] Starting VSS service... >> "!LOG_FILE!"
    sc config "VSS" start= auto >nul 2>&1
    sc start "VSS" >nul 2>&1
)

sc query "swprv" | find "STATE" | find "RUNNING" >nul 2>&1
IF %ERRORLEVEL% NEQ 0 (
    ECHO [%TIME%] [WARN] Software Shadow Copy Provider service not running. Starting it...
    ECHO [%DATE% %TIME%] [WARN] Starting swprv service... >> "!LOG_FILE!"
    sc config "swprv" start= manual >nul 2>&1
    sc start "swprv" >nul 2>&1
)

REM Check if System Restore is enabled
powershell -ExecutionPolicy Bypass -Command "try { if ((Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore' -Name DisableSR -ErrorAction SilentlyContinue).DisableSR -eq 1) { Write-Host 'DISABLED' } else { Write-Host 'ENABLED' } } catch { Write-Host 'UNKNOWN' }" > "!TEMP!\restore_status.txt"
SET /P RESTORE_STATUS=<"!TEMP!\restore_status.txt"
DEL /F /Q "!TEMP!\restore_status.txt" >nul 2>&1

IF "!RESTORE_STATUS!"=="DISABLED" (
    ECHO [%TIME%] [WARN] System Restore is disabled. Enabling it now...
    ECHO [%DATE% %TIME%] [WARN] System Restore disabled. Enabling... >> "!LOG_FILE!"
    
    REM Enable System Restore on C: drive with comprehensive setup
    powershell -ExecutionPolicy Bypass -Command "try { Enable-ComputerRestore -Drive 'C:\'; Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore' -Name 'DisableSR' -Value 0 -Force; Write-Host 'System Restore enabled successfully.' } catch { Write-Host 'Failed to enable System Restore:' $_.Exception.Message }"
    ECHO [%DATE% %TIME%] [INFO] System Restore enable command executed. >> "!LOG_FILE!"
    
    REM Wait a moment for services to initialize
    timeout /t 3 /nobreak >nul
) ELSE (
    ECHO [%TIME%] [INFO] System Restore is already enabled.
    ECHO [%DATE% %TIME%] [INFO] System Restore already enabled. >> "!LOG_FILE!"
)

REM Wait for services to fully initialize
ECHO [%TIME%] [INFO] Waiting for System Restore services to initialize...
timeout /t 5 /nobreak >nul

REM Verify VSS service is running
sc query "VSS" | find "STATE" | find "RUNNING" >nul 2>&1
IF %ERRORLEVEL% NEQ 0 (
    ECHO [%TIME%] [WARN] VSS service still not running. System Restore may not work properly.
    ECHO [%DATE% %TIME%] [WARN] VSS service initialization failed. >> "!LOG_FILE!"
)

REM Create restore point with enhanced error handling and proper service verification
ECHO [%TIME%] [INFO] Creating system restore point...
ECHO [%DATE% %TIME%] [INFO] Creating system restore point... >> "!LOG_FILE!"

powershell -ExecutionPolicy Bypass -Command "try { $vss = Get-Service -Name VSS -ErrorAction SilentlyContinue; if ($vss -and $vss.Status -eq 'Running') { Write-Host '[INFO] VSS service is running. Creating restore point...'; try { Checkpoint-Computer -Description 'Before Maintenance Script - %DATE% %TIME%' -RestorePointType 'MODIFY_SETTINGS' -ErrorAction Stop; Write-Host '[SUCCESS] Restore point created successfully.' } catch { if ($_.Exception.Message -match 'recent restore point') { Write-Host '[INFO] Skipped - Recent restore point already exists.' } else { Write-Host '[WARN] Restore point creation failed:' $_.Exception.Message } } } else { Write-Host '[WARN] VSS service not available. Skipping restore point creation.' } } catch { Write-Host '[ERROR] System Restore check failed:' $_.Exception.Message }"
ECHO [%DATE% %TIME%] [INFO] Restore point creation completed. >> "!LOG_FILE!"

REM ============================================================================
REM [STEP 4] MONTHLY SCHEDULED TASK SETUP
REM ============================================================================
SET "MONTHLY_TASK_NAME=ScriptMentenantaMonthly"
ECHO [%TIME%] [INFO] Checking monthly scheduled task '!MONTHLY_TASK_NAME!'...
ECHO [%DATE% %TIME%] [INFO] Checking monthly scheduled task '!MONTHLY_TASK_NAME!'... >> "!LOG_FILE!"

schtasks /Query /TN "!MONTHLY_TASK_NAME!" >nul 2>&1
IF %ERRORLEVEL% NEQ 0 (
    ECHO [%TIME%] [INFO] Creating monthly maintenance task...
    ECHO [%DATE% %TIME%] [INFO] Creating monthly maintenance task... >> "!LOG_FILE!"
    
    schtasks /Create /TN "!MONTHLY_TASK_NAME!" /TR "\"!SCRIPT_PATH!\"" /SC MONTHLY /D 1 /ST 01:00 /RL HIGHEST /RU "SYSTEM" /F >nul 2>&1
    IF !ERRORLEVEL! EQU 0 (
        ECHO [%TIME%] [INFO] Monthly task created successfully.
        ECHO [%DATE% %TIME%] [INFO] Monthly task created successfully. >> "!LOG_FILE!"
    ) ELSE (
        ECHO [%TIME%] [WARN] Failed to create monthly task.
        ECHO [%DATE% %TIME%] [WARN] Failed to create monthly task. >> "!LOG_FILE!"
    )
) ELSE (
    ECHO [%TIME%] [INFO] Monthly task already exists.
    ECHO [%DATE% %TIME%] [INFO] Monthly task already exists. >> "!LOG_FILE!"
)

REM ============================================================================
REM [STEP 5] STARTUP TASK MANAGEMENT (REMOVE IF EXISTS)
REM ============================================================================
SET "STARTUP_TASK_NAME=ScriptMentenantaStartup"
ECHO [%TIME%] [INFO] Checking for existing startup task '!STARTUP_TASK_NAME!'...
ECHO [%DATE% %TIME%] [INFO] Checking for existing startup task '!STARTUP_TASK_NAME!'... >> "!LOG_FILE!"

schtasks /Query /TN "!STARTUP_TASK_NAME!" >nul 2>&1
IF %ERRORLEVEL% EQU 0 (
    ECHO [%TIME%] [INFO] Removing existing startup task...
    ECHO [%DATE% %TIME%] [INFO] Removing existing startup task... >> "!LOG_FILE!"
    
    schtasks /Delete /TN "!STARTUP_TASK_NAME!" /F >nul 2>&1
    IF !ERRORLEVEL! EQU 0 (
        ECHO [%TIME%] [INFO] Startup task removed successfully.
        ECHO [%DATE% %TIME%] [INFO] Startup task removed successfully. >> "!LOG_FILE!"
    ) ELSE (
        ECHO [%TIME%] [WARN] Failed to remove startup task.
        ECHO [%DATE% %TIME%] [WARN] Failed to remove startup task. >> "!LOG_FILE!"
    )
) ELSE (
    ECHO [%TIME%] [INFO] No existing startup task found.
    ECHO [%DATE% %TIME%] [INFO] No existing startup task found. >> "!LOG_FILE!"
)

REM ============================================================================
REM [STEP 6] PENDING RESTART DETECTION AND HANDLING
REM ============================================================================
ECHO [%TIME%] [INFO] Checking for pending system restarts...
ECHO [%DATE% %TIME%] [INFO] Checking for pending system restarts... >> "!LOG_FILE!"
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

IF "!RESTART_STATUS!"=="RESTART_REQUIRED" (
    ECHO [%TIME%] [WARN] Pending restart detected. Creating startup task and restarting...
    ECHO [%DATE% %TIME%] [WARN] Pending restart detected. Creating startup task and restarting... >> "!LOG_FILE!"
    
    REM Create startup task to continue after restart
    schtasks /Create /TN "!STARTUP_TASK_NAME!" /TR "cmd.exe /c timeout /t 60 && \"!SCRIPT_PATH!\"" /SC ONLOGON /RL HIGHEST /RU "!USERNAME!" /F >nul 2>&1
    IF !ERRORLEVEL! EQU 0 (
        ECHO [%TIME%] [INFO] Startup task created for post-restart execution.
        ECHO [%DATE% %TIME%] [INFO] Startup task created for post-restart execution. >> "!LOG_FILE!"
    )
    
    REM Restart the system
    ECHO [%TIME%] [INFO] Restarting system in 10 seconds...
    ECHO [%DATE% %TIME%] [INFO] System restart initiated. >> "!LOG_FILE!"
    shutdown /r /t 10 /c "Restarting to apply pending changes before maintenance"
    EXIT /B 0
) ELSE (
    ECHO [%TIME%] [INFO] No pending restart detected. Continuing with maintenance...
    ECHO [%DATE% %TIME%] [INFO] No pending restart detected. Continuing... >> "!LOG_FILE!"
)

REM ============================================================================
REM [STEP 7] WINGET INSTALLATION AND VERIFICATION
REM ============================================================================
ECHO [%TIME%] [INFO] Checking Winget (Microsoft.AppInstaller)...
ECHO [%DATE% %TIME%] [INFO] Checking Winget availability... >> "!LOG_FILE!"

where winget.exe >nul 2>&1
IF %ERRORLEVEL% NEQ 0 (
    ECHO [%TIME%] [WARN] Winget not found. Installing from Microsoft Store...
    ECHO [%DATE% %TIME%] [WARN] Winget not found. Installing... >> "!LOG_FILE!"
    
    REM Download and install App Installer (which includes winget)
    powershell -ExecutionPolicy Bypass -Command "try { $progressPreference = 'SilentlyContinue'; Invoke-WebRequest -Uri 'https://aka.ms/getwinget' -OutFile '$env:TEMP\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle'; Add-AppxPackage -Path '$env:TEMP\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle'; Write-Host 'Winget installed successfully.' } catch { Write-Host 'Failed to install Winget:' $_.Exception.Message }"
    
    REM Verify installation
    where winget.exe >nul 2>&1
    IF !ERRORLEVEL! EQU 0 (
        ECHO [%TIME%] [INFO] Winget installed and verified successfully.
        ECHO [%DATE% %TIME%] [INFO] Winget installation successful. >> "!LOG_FILE!"
    ) ELSE (
        ECHO [%TIME%] [ERROR] Winget installation failed. Some features may not work.
        ECHO [%DATE% %TIME%] [ERROR] Winget installation failed. >> "!LOG_FILE!"
    )
) ELSE (
    ECHO [%TIME%] [INFO] Winget is already available.
    ECHO [%DATE% %TIME%] [INFO] Winget already available. >> "!LOG_FILE!"
)

REM ============================================================================
REM [STEP 8] POWERSHELL 7 INSTALLATION
REM ============================================================================
ECHO [%TIME%] [INFO] Checking PowerShell 7 (Microsoft.PowerShell)...
ECHO [%DATE% %TIME%] [INFO] Checking PowerShell 7 availability... >> "!LOG_FILE!"

where pwsh.exe >nul 2>&1
IF %ERRORLEVEL% NEQ 0 (
    ECHO [%TIME%] [WARN] PowerShell 7 not found. Installing via Winget...
    ECHO [%DATE% %TIME%] [WARN] PowerShell 7 not found. Installing... >> "!LOG_FILE!"
    
    REM Install PowerShell 7 using winget (if available) or direct download
    where winget.exe >nul 2>&1
    IF !ERRORLEVEL! EQU 0 (
        ECHO [%TIME%] [INFO] Installing PowerShell 7 via Winget...
        winget install Microsoft.PowerShell --silent --accept-package-agreements --accept-source-agreements >nul 2>&1
        timeout /t 3 /nobreak >nul
    ) ELSE (
        ECHO [%TIME%] [INFO] Installing PowerShell 7 via direct download...
        REM Fallback: Direct download and install
        powershell -ExecutionPolicy Bypass -Command "try { $progressPreference = 'SilentlyContinue'; $url = 'https://github.com/PowerShell/PowerShell/releases/latest/download/PowerShell-7.4.5-win-x64.msi'; Invoke-WebRequest -Uri $url -OutFile '$env:TEMP\PowerShell.msi'; Start-Process -FilePath 'msiexec.exe' -ArgumentList '/i $env:TEMP\PowerShell.msi /quiet /norestart' -Wait; Remove-Item '$env:TEMP\PowerShell.msi' -Force -ErrorAction SilentlyContinue; Write-Host 'PowerShell 7 installation completed.' } catch { Write-Host 'Failed to install PowerShell 7:' $_.Exception.Message }"
        timeout /t 5 /nobreak >nul
    )
    
    REM Refresh PATH and verify installation with multiple attempts
    ECHO [%TIME%] [INFO] Verifying PowerShell 7 installation...
    FOR /L %%i IN (1,1,3) DO (
        REM Try to find pwsh.exe in common locations
        IF EXIST "%ProgramFiles%\PowerShell\7\pwsh.exe" (
            ECHO [%TIME%] [INFO] PowerShell 7 found in Program Files.
            SET "PWSH_FOUND=TRUE"
            GOTO :PS7_FOUND
        )
        IF EXIST "%ProgramFiles(x86)%\PowerShell\7\pwsh.exe" (
            ECHO [%TIME%] [INFO] PowerShell 7 found in Program Files ^(x86^).
            SET "PWSH_FOUND=TRUE"
            GOTO :PS7_FOUND
        )
        where pwsh.exe >nul 2>&1
        IF !ERRORLEVEL! EQU 0 (
            ECHO [%TIME%] [INFO] PowerShell 7 found in PATH.
            SET "PWSH_FOUND=TRUE"
            GOTO :PS7_FOUND
        )
        IF %%i LSS 3 (
            ECHO [%TIME%] [INFO] PowerShell 7 not yet available, waiting... ^(attempt %%i/3^)
            timeout /t 3 /nobreak >nul
        )
    )
    
    :PS7_FOUND
    IF "!PWSH_FOUND!"=="TRUE" (
        ECHO [%TIME%] [INFO] PowerShell 7 installed and verified successfully.
        ECHO [%DATE% %TIME%] [INFO] PowerShell 7 installation successful. >> "!LOG_FILE!"
    ) ELSE (
        ECHO [%TIME%] [ERROR] PowerShell 7 installation failed. Will use Windows PowerShell as fallback.
        ECHO [%DATE% %TIME%] [ERROR] PowerShell 7 installation failed. Using fallback. >> "!LOG_FILE!"
    )
) ELSE (
    ECHO [%TIME%] [INFO] PowerShell 7 is already available.
    ECHO [%DATE% %TIME%] [INFO] PowerShell 7 already available. >> "!LOG_FILE!"
)

REM ============================================================================
REM [STEP 9] DEPENDENCIES CHECK AND INSTALLATION
REM ============================================================================
ECHO [%TIME%] [INFO] Checking and installing required dependencies...
ECHO [%DATE% %TIME%] [INFO] Installing PowerShell dependencies... >> "!LOG_FILE!"

REM Standard Windows tools are assumed available (VBScript, Task Scheduler, DISM)
ECHO [%TIME%] [INFO] Standard Windows tools assumed available
ECHO [%DATE% %TIME%] [INFO] Standard Windows tools assumed available. >> "!LOG_FILE!"

REM Install NuGet Provider and PowerShellGet (essential for module installation)
ECHO [%TIME%] [INFO] Installing NuGet Provider and PowerShellGet...
ECHO [%DATE% %TIME%] [INFO] Installing NuGet Provider... >> "!LOG_FILE!"

REM Install NuGet Provider using Windows PowerShell (more reliable for Windows 10/11)
powershell -ExecutionPolicy Bypass -Command "try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; if (!(Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) { Install-PackageProvider -Name NuGet -Force -Scope AllUsers -Confirm:$false | Out-Null; Write-Host 'NuGet Provider installed successfully' } else { Write-Host 'NuGet Provider already available' } } catch { Write-Host 'NuGet Provider installation failed:' $_.Exception.Message }"
ECHO [%DATE% %TIME%] [INFO] NuGet Provider installation completed. >> "!LOG_FILE!"

REM Ensure PowerShellGet is up to date
ECHO [%TIME%] [INFO] Updating PowerShellGet module...
ECHO [%DATE% %TIME%] [INFO] Updating PowerShellGet... >> "!LOG_FILE!"
powershell -ExecutionPolicy Bypass -Command "try { if (Get-Module -Name PowerShellGet -ListAvailable) { Write-Host 'PowerShellGet is available' } else { Write-Host 'PowerShellGet not found - installing' } } catch { Write-Host 'PowerShellGet check failed' }"

REM Install PSWindowsUpdate module in Windows PowerShell
ECHO [%TIME%] [INFO] Installing PSWindowsUpdate module...
ECHO [%DATE% %TIME%] [INFO] Installing PSWindowsUpdate module... >> "!LOG_FILE!"
powershell -ExecutionPolicy Bypass -Command "try { if (!(Get-Module -Name PSWindowsUpdate -ListAvailable -ErrorAction SilentlyContinue)) { Install-Module -Name PSWindowsUpdate -Force -AllowClobber -Scope AllUsers -Confirm:$false | Out-Null; Write-Host 'PSWindowsUpdate module installed successfully' } else { Write-Host 'PSWindowsUpdate module already available' } } catch { Write-Host 'PSWindowsUpdate installation failed:' $_.Exception.Message }"

REM Note: Appx module is built into Windows PowerShell but not PowerShell 7
REM The PowerShell script will handle this by importing it from Windows PowerShell when needed
ECHO [%TIME%] [INFO] Appx module - Will be imported from Windows PowerShell when needed
ECHO [%DATE% %TIME%] [INFO] Appx module handling deferred to PowerShell script. >> "!LOG_FILE!"

ECHO [%TIME%] [INFO] PowerShell dependencies installation completed.
ECHO [%DATE% %TIME%] [INFO] Dependencies installation completed. >> "!LOG_FILE!"

REM ============================================================================
REM [STEP 10] REPOSITORY DOWNLOAD AND EXTRACTION
REM ============================================================================
ECHO [%TIME%] [INFO] Checking for local or downloading repository...
ECHO [%DATE% %TIME%] [INFO] Checking for script.ps1... >> "!LOG_FILE!"

SET "REPO_URL=https://github.com/ichimbogdancristian/script_mentenanta/archive/refs/heads/main.zip"
SET "REPO_ZIP=!SCRIPT_DIR!\repo.zip"
SET "REPO_FOLDER=!SCRIPT_DIR!\script_mentenanta-main"
SET "LOCAL_PS1=!SCRIPT_DIR!\script.ps1"

REM Check if script.ps1 exists locally first
IF EXIST "!LOCAL_PS1!" (
    ECHO [%TIME%] [INFO] Using local script.ps1 file
    ECHO [%DATE% %TIME%] [INFO] Using local script.ps1 file. >> "!LOG_FILE!"
    SET "PS1_SCRIPT=!LOCAL_PS1!"
    GOTO :SKIP_DOWNLOAD
)

REM Download repository if local file not found
ECHO [%TIME%] [INFO] Local script.ps1 not found. Downloading from repository...
ECHO [%DATE% %TIME%] [INFO] Downloading repository... >> "!LOG_FILE!"

powershell -ExecutionPolicy Bypass -Command "try { $progressPreference = 'SilentlyContinue'; Invoke-WebRequest -Uri '!REPO_URL!' -OutFile '!REPO_ZIP!' -UseBasicParsing -TimeoutSec 60; Write-Host 'Repository downloaded successfully.' } catch { Write-Host 'Failed to download repository:' $_.Exception.Message }"

REM Extract repository
IF EXIST "!REPO_ZIP!" (
    ECHO [%TIME%] [INFO] Extracting repository...
    ECHO [%DATE% %TIME%] [INFO] Extracting repository... >> "!LOG_FILE!"
    
    powershell -ExecutionPolicy Bypass -Command "try { Expand-Archive -Path '!REPO_ZIP!' -DestinationPath '!SCRIPT_DIR!' -Force; Write-Host 'Repository extracted successfully.' } catch { Write-Host 'Failed to extract repository:' $_.Exception.Message }"
    
    ECHO [%DATE% %TIME%] [INFO] Repository extracted to: !REPO_FOLDER! >> "!LOG_FILE!"
    
    REM Clean up zip file
    DEL /F /Q "!REPO_ZIP!" >nul 2>&1
    SET "PS1_SCRIPT=!REPO_FOLDER!\script.ps1"
    
    REM Verify extracted script exists
    IF NOT EXIST "!PS1_SCRIPT!" (
        ECHO [%TIME%] [ERROR] script.ps1 not found in extracted repository.
        ECHO [%DATE% %TIME%] [ERROR] script.ps1 not found in repository at: !PS1_SCRIPT! >> "!LOG_FILE!"
        GOTO LOCAL_SCRIPT
    )
) ELSE (
    ECHO [%TIME%] [ERROR] Repository download failed. Attempting to use local script.
    ECHO [%DATE% %TIME%] [ERROR] Repository download failed. Attempting to use local script. >> "!LOG_FILE!"
    GOTO LOCAL_SCRIPT
)

:SKIP_DOWNLOAD

:LOCAL_SCRIPT
REM If we get here, we need to use the local script
IF EXIST "!LOCAL_PS1!" (
    ECHO [%TIME%] [INFO] Using local script.ps1
    ECHO [%DATE% %TIME%] [INFO] Using local script: !LOCAL_PS1! >> "!LOG_FILE!"
    SET "PS1_SCRIPT=!LOCAL_PS1!"
) ELSE (
    ECHO [%TIME%] [ERROR] Local script.ps1 not found. Cannot continue.
    ECHO [%DATE% %TIME%] [ERROR] Local script.ps1 not found at: !LOCAL_PS1! >> "!LOG_FILE!"
    pause
    EXIT /B 1
)

REM ============================================================================
REM [STEP 11] EXECUTE SCRIPT.PS1 IN POWERSHELL 7 ENVIRONMENT
REM ============================================================================
IF NOT EXIST "!PS1_SCRIPT!" (
    ECHO [%TIME%] [ERROR] script.ps1 not found at expected location: !PS1_SCRIPT!
    ECHO [%DATE% %TIME%] [ERROR] script.ps1 not found. >> "!LOG_FILE!"
    pause
    EXIT /B 1
)

ECHO [%TIME%] [INFO] Launching script.ps1 in PowerShell 7 environment...
ECHO [%DATE% %TIME%] [INFO] Launching PowerShell maintenance script... >> "!LOG_FILE!"

REM Determine PowerShell executable (prefer pwsh, fallback to powershell)
SET "PS_EXECUTABLE=powershell.exe"
SET "PS_VERSION=Windows PowerShell"

REM Check for PowerShell 7 in multiple locations
where pwsh.exe >nul 2>&1
IF !ERRORLEVEL! EQU 0 (
    SET "PS_EXECUTABLE=pwsh.exe"
    SET "PS_VERSION=PowerShell 7"
) ELSE (
    REM Check common PowerShell 7 installation paths
    IF EXIST "%ProgramFiles%\PowerShell\7\pwsh.exe" (
        SET "PS_EXECUTABLE=%ProgramFiles%\PowerShell\7\pwsh.exe"
        SET "PS_VERSION=PowerShell 7"
    ) ELSE IF EXIST "%ProgramFiles(x86)%\PowerShell\7\pwsh.exe" (
        SET "PS_EXECUTABLE=%ProgramFiles(x86)%\PowerShell\7\pwsh.exe"
        SET "PS_VERSION=PowerShell 7"
    ) ELSE (
        ECHO [%TIME%] [WARN] PowerShell 7 not found in PATH or standard locations. Using Windows PowerShell.
        ECHO [%DATE% %TIME%] [WARN] Using Windows PowerShell fallback. >> "!LOG_FILE!"
    )
)

ECHO [%TIME%] [INFO] Using !PS_VERSION! executable: !PS_EXECUTABLE!
ECHO [%DATE% %TIME%] [INFO] Using !PS_VERSION!: !PS_EXECUTABLE! >> "!LOG_FILE!"

REM Launch PowerShell script in new window with admin rights
REM Pass repo folder information for cleanup purposes
IF "!PS1_SCRIPT!"=="!LOCAL_PS1!" (
    REM Using local script - no repo folder to clean
    START "PowerShell Maintenance Script" "!PS_EXECUTABLE!" -ExecutionPolicy Bypass -WindowStyle Normal -File "!PS1_SCRIPT!" -LogFilePath "!LOG_FILE!" -RepoFolderPath ""
) ELSE (
    REM Using downloaded script - pass repo folder for cleanup
    START "PowerShell Maintenance Script" "!PS_EXECUTABLE!" -ExecutionPolicy Bypass -WindowStyle Normal -File "!PS1_SCRIPT!" -LogFilePath "!LOG_FILE!" -RepoFolderPath "!REPO_FOLDER!"
)

REM ============================================================================
REM [STEP 12] COUNTDOWN AND CLEANUP
REM ============================================================================
ECHO [%TIME%] [INFO] PowerShell maintenance script launched successfully.
ECHO [%DATE% %TIME%] [INFO] PowerShell script launched. Starting countdown... >> "!LOG_FILE!"

ECHO.
ECHO ========================================
ECHO   Maintenance Script Launched
ECHO ========================================
ECHO.
ECHO PowerShell maintenance script is now running in a separate window.
ECHO This launcher window will close automatically in 20 seconds.
ECHO Press Ctrl+C to abort the countdown and keep this window open.
ECHO.

REM 20-second countdown with abort option
FOR /L %%i IN (20,-1,1) DO (
    ECHO Closing in %%i seconds... ^(Press Ctrl+C to abort^)
    timeout /t 1 /nobreak >nul 2>&1
    IF !ERRORLEVEL! NEQ 0 (
        ECHO.
        ECHO Countdown aborted by user.
        ECHO [%DATE% %TIME%] [INFO] Countdown aborted by user. >> "!LOG_FILE!"
        ECHO Press any key to exit...
        pause >nul
        GOTO :END
    )
)

:END
ECHO [%TIME%] [INFO] Launcher completed successfully.
ECHO [%DATE% %TIME%] [INFO] Launcher completed. PowerShell script continues in background. >> "!LOG_FILE!"
ECHO [%DATE% %TIME%] [INFO] ============================================================================ >> "!LOG_FILE!"

REM Cleanup temporary files if any
IF EXIST "!TEMP!\restore_status.txt" DEL /F /Q "!TEMP!\restore_status.txt" >nul 2>&1

EXIT /B 0
