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
REM Get the absolute path of this batch file and its directory
SET "SCRIPT_PATH=%~f0"
SET "SCRIPT_DIR=%~dp0"
IF "!SCRIPT_DIR:~-1!"=="\" SET "SCRIPT_DIR=!SCRIPT_DIR:~0,-1!"
SET "LOG_FILE=!SCRIPT_DIR!\maintenance.log"
SET "USERNAME_VAR=%USERNAME%"
SET "COMPUTER_VAR=%COMPUTERNAME%"
SET "WINVER=%OS%"

REM Simple environment detection using CMD-native commands
SET "FULL_USERNAME=%USERDOMAIN%\%USERNAME%"
SET "OS_CAPTION=%OS%"

REM Try to get more detailed OS info if available
FOR /F "tokens=4-5 delims=. " %%A IN ('ver') DO SET "OS_VERSION=%%A.%%B"

REM Initialize comprehensive logging
ECHO [%DATE% %TIME%] [INFO] ============================================================================ >> "!LOG_FILE!"
ECHO [%DATE% %TIME%] [INFO] script_mentenanta - Windows Maintenance Automation Launcher >> "!LOG_FILE!"
ECHO [%DATE% %TIME%] [INFO] Script Path: !SCRIPT_PATH! >> "!LOG_FILE!"
ECHO [%DATE% %TIME%] [INFO] Script Directory: !SCRIPT_DIR! >> "!LOG_FILE!"
ECHO [%DATE% %TIME%] [INFO] Username: !USERNAME_VAR! ^(!FULL_USERNAME!^) >> "!LOG_FILE!"
ECHO [%DATE% %TIME%] [INFO] Computer: !COMPUTER_VAR! >> "!LOG_FILE!"
ECHO [%DATE% %TIME%] [INFO] OS Version: !OS_CAPTION! !OS_VERSION! >> "!LOG_FILE!"
ECHO [%DATE% %TIME%] [INFO] Log File Location: !LOG_FILE! >> "!LOG_FILE!"
ECHO [%DATE% %TIME%] [INFO] Current Directory: %CD% >> "!LOG_FILE!"
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

REM Check Volume Shadow Copy Service (required for System Restore)
sc query "VSS" | find "STATE" | find "RUNNING" >nul 2>&1
IF %ERRORLEVEL% NEQ 0 (
    ECHO [%TIME%] [WARN] Volume Shadow Copy service not running. Starting it...
    ECHO [%DATE% %TIME%] [WARN] Starting VSS service... >> "!LOG_FILE!"
    sc config "VSS" start= auto >nul 2>&1
    sc start "VSS" >nul 2>&1
    timeout /t 3 /nobreak >nul
)

REM Check Software Shadow Copy Provider Service
sc query "swprv" | find "STATE" | find "RUNNING" >nul 2>&1
IF %ERRORLEVEL% NEQ 0 (
    ECHO [%TIME%] [WARN] Software Shadow Copy Provider service not running. Starting it...
    ECHO [%DATE% %TIME%] [WARN] Starting swprv service... >> "!LOG_FILE!"
    sc config "swprv" start= manual >nul 2>&1
    sc start "swprv" >nul 2>&1
    timeout /t 3 /nobreak >nul
)

REM Check System Restore Service
sc query "SRService" | find "STATE" | find "RUNNING" >nul 2>&1
IF %ERRORLEVEL% NEQ 0 (
    ECHO [%TIME%] [WARN] System Restore service not running. Starting it...
    ECHO [%DATE% %TIME%] [WARN] Starting SRService... >> "!LOG_FILE!"
    sc config "SRService" start= auto >nul 2>&1
    sc start "SRService" >nul 2>&1
    timeout /t 3 /nobreak >nul
)

REM Use WMIC to check if System Restore is enabled (CMD-native approach)
ECHO [%TIME%] [INFO] Checking System Restore status with WMIC...
wmic /namespace:\\root\default path SystemRestore get DisableSR /value | find "DisableSR" > "!TEMP!\sr_status.txt" 2>nul
IF EXIST "!TEMP!\sr_status.txt" (
    SET /P SR_DISABLED=<"!TEMP!\sr_status.txt"
    DEL /F /Q "!TEMP!\sr_status.txt" >nul 2>&1
    ECHO !SR_DISABLED! | find "FALSE" >nul 2>&1
    IF !ERRORLEVEL! EQU 0 (
        ECHO [%TIME%] [INFO] System Restore is enabled.
        ECHO [%DATE% %TIME%] [INFO] System Restore is enabled. >> "!LOG_FILE!"
    ) ELSE (
        ECHO [%TIME%] [WARN] System Restore appears disabled. Attempting to enable...
        ECHO [%DATE% %TIME%] [WARN] System Restore disabled. Enabling... >> "!LOG_FILE!"
        wmic /namespace:\\root\default path SystemRestore call Enable "C:\" >nul 2>&1
        timeout /t 2 /nobreak >nul
    )
) ELSE (
    ECHO [%TIME%] [WARN] Could not check System Restore status. Continuing anyway...
    ECHO [%DATE% %TIME%] [WARN] Could not check System Restore status. >> "!LOG_FILE!"
)

REM Wait for services to fully initialize
ECHO [%TIME%] [INFO] Waiting for System Restore services to initialize...
timeout /t 5 /nobreak >nul

REM Create a system restore point using WMIC (simplest CMD-native method)
ECHO [%TIME%] [INFO] Creating system restore point with WMIC...
ECHO [%DATE% %TIME%] [INFO] Creating system restore point with WMIC... >> "!LOG_FILE!"

REM Use WMIC with explicit parameters and capture output for better debugging
wmic /namespace:\\root\default path SystemRestore call CreateRestorePoint "Before Maintenance Script", 100, 7 > "!TEMP!\restore_result.txt" 2>&1
SET WMIC_RESULT=%ERRORLEVEL%

IF EXIST "!TEMP!\restore_result.txt" (
    TYPE "!TEMP!\restore_result.txt" | find "ReturnValue = 0" >nul 2>&1
    IF !ERRORLEVEL! EQU 0 (
        ECHO [%TIME%] [SUCCESS] Restore point created successfully with WMIC.
        ECHO [%DATE% %TIME%] [SUCCESS] Restore point created successfully. >> "!LOG_FILE!"
    ) ELSE (
        ECHO [%TIME%] [WARN] Restore point creation may have failed. Checking output...
        ECHO [%DATE% %TIME%] [WARN] Restore point creation uncertain. Output: >> "!LOG_FILE!"
        TYPE "!TEMP!\restore_result.txt" >> "!LOG_FILE!" 2>nul
        
        REM Try alternative WMIC syntax
        ECHO [%TIME%] [INFO] Trying alternative WMIC syntax...
        wmic computersystem where name="%COMPUTERNAME%" call CreateSystemRestorePoint "Before Maintenance Script" > "!TEMP!\restore_result2.txt" 2>&1
        IF EXIST "!TEMP!\restore_result2.txt" (
            TYPE "!TEMP!\restore_result2.txt" | find "ReturnValue = 0" >nul 2>&1
            IF !ERRORLEVEL! EQU 0 (
                ECHO [%TIME%] [SUCCESS] Restore point created with alternative WMIC method.
                ECHO [%DATE% %TIME%] [SUCCESS] Restore point created with alternative method. >> "!LOG_FILE!"
            ) ELSE (
                ECHO [%TIME%] [WARN] Alternative WMIC method also failed.
                ECHO [%DATE% %TIME%] [WARN] All restore point methods failed. >> "!LOG_FILE!"
                TYPE "!TEMP!\restore_result2.txt" >> "!LOG_FILE!" 2>nul
            )
            DEL /F /Q "!TEMP!\restore_result2.txt" >nul 2>&1
        )
    )
    DEL /F /Q "!TEMP!\restore_result.txt" >nul 2>&1
) ELSE (
    ECHO [%TIME%] [ERROR] WMIC command failed to execute or produce output.
    ECHO [%DATE% %TIME%] [ERROR] WMIC restore point command failed. >> "!LOG_FILE!"
)

REM Final verification - check if any restore points exist
ECHO [%TIME%] [INFO] Verifying restore point creation...
wmic /namespace:\\root\default path SystemRestore get Description,CreationTime /format:list | find "Description" >nul 2>&1
IF %ERRORLEVEL% EQU 0 (
    ECHO [%TIME%] [INFO] System restore points are available on this system.
    ECHO [%DATE% %TIME%] [INFO] System restore points verified. >> "!LOG_FILE!"
) ELSE (
    ECHO [%TIME%] [WARN] No restore points found or System Restore not functional.
    ECHO [%DATE% %TIME%] [WARN] System Restore may not be functional on this system. >> "!LOG_FILE!"
)

ECHO [%DATE% %TIME%] [INFO] Restore point creation process completed. >> "!LOG_FILE!"

REM ============================================================================
REM [STEP 4] MONTHLY SCHEDULED TASK SETUP
REM ============================================================================
SET "MONTHLY_TASK_NAME=ScriptMentenantaMonthly"
ECHO [%TIME%] [INFO] Checking monthly scheduled task '!MONTHLY_TASK_NAME!'...
ECHO [%DATE% %TIME%] [INFO] Checking monthly scheduled task '!MONTHLY_TASK_NAME!'... >> "!LOG_FILE!"

REM Use simpler method to check for task existence
schtasks /Query /TN "!MONTHLY_TASK_NAME!" 2>nul >nul
IF %ERRORLEVEL% NEQ 0 (
    ECHO [%TIME%] [INFO] Creating monthly maintenance task (first day of month at 1am)...
    ECHO [%DATE% %TIME%] [INFO] Creating monthly maintenance task... >> "!LOG_FILE!"
    
    REM Use simple schtasks command (CMD-native approach)
    ECHO [%TIME%] [INFO] Creating task with basic schtasks command...
    schtasks /Create /TN "!MONTHLY_TASK_NAME!" /TR "\"!SCRIPT_PATH!\"" /SC MONTHLY /D 1 /ST 01:00 /RL HIGHEST /F 2>nul >nul
    
    IF %ERRORLEVEL% EQU 0 (
        ECHO [%TIME%] [INFO] Monthly task created successfully.
        ECHO [%DATE% %TIME%] [INFO] Monthly task created successfully. >> "!LOG_FILE!"
    ) ELSE (
        ECHO [%TIME%] [WARN] Failed to create monthly task. Trying with different parameters...
        
        REM Try without /RL parameter (some Windows versions don't support it)
        schtasks /Create /TN "!MONTHLY_TASK_NAME!" /TR "\"!SCRIPT_PATH!\"" /SC MONTHLY /D 1 /ST 01:00 /F 2>nul >nul
        
        IF !ERRORLEVEL! EQU 0 (
            ECHO [%TIME%] [INFO] Monthly task created successfully without /RL parameter.
            ECHO [%DATE% %TIME%] [INFO] Monthly task created without /RL parameter. >> "!LOG_FILE!"
        ) ELSE (
            ECHO [%TIME%] [ERROR] Failed to create monthly task with all methods.
            ECHO [%DATE% %TIME%] [ERROR] Monthly task creation failed. >> "!LOG_FILE!"
        )
    )
) ELSE (
    ECHO [%TIME%] [INFO] Monthly task already exists.
    ECHO [%DATE% %TIME%] [INFO] Monthly task already exists. >> "!LOG_FILE!"
    
    REM Check if task points to current script location
    schtasks /Query /TN "!MONTHLY_TASK_NAME!" /FO LIST | find "!SCRIPT_PATH!" >nul 2>&1
    IF !ERRORLEVEL! NEQ 0 (
        ECHO [%TIME%] [INFO] Updating existing task with current script path...
        schtasks /Delete /TN "!MONTHLY_TASK_NAME!" /F 2>nul >nul
        schtasks /Create /TN "!MONTHLY_TASK_NAME!" /TR "\"!SCRIPT_PATH!\"" /SC MONTHLY /D 1 /ST 01:00 /RL HIGHEST /F 2>nul >nul
        IF !ERRORLEVEL! EQU 0 (
            ECHO [%TIME%] [INFO] Monthly task updated successfully.
            ECHO [%DATE% %TIME%] [INFO] Monthly task updated with new path. >> "!LOG_FILE!"
        ) ELSE (
            REM Try without /RL parameter
            schtasks /Create /TN "!MONTHLY_TASK_NAME!" /TR "\"!SCRIPT_PATH!\"" /SC MONTHLY /D 1 /ST 01:00 /F 2>nul >nul
            IF !ERRORLEVEL! EQU 0 (
                ECHO [%TIME%] [INFO] Monthly task updated successfully without /RL parameter.
                ECHO [%DATE% %TIME%] [INFO] Monthly task updated without /RL parameter. >> "!LOG_FILE!"
            ) ELSE (
                ECHO [%TIME%] [WARN] Could not update monthly task path.
                ECHO [%DATE% %TIME%] [WARN] Could not update monthly task path. >> "!LOG_FILE!"
            )
        )
    ) ELSE (
        ECHO [%TIME%] [INFO] Monthly task already points to correct script location.
        ECHO [%DATE% %TIME%] [INFO] Monthly task path is correct. >> "!LOG_FILE!"
    )
)

REM ============================================================================
REM [STEP 5] STARTUP TASK MANAGEMENT (REMOVE IF EXISTS)
REM ============================================================================
SET "STARTUP_TASK_NAME=ScriptMentenantaStartup"
ECHO [%TIME%] [INFO] Checking for existing startup task '!STARTUP_TASK_NAME!'...
ECHO [%DATE% %TIME%] [INFO] Checking for existing startup task '!STARTUP_TASK_NAME!'... >> "!LOG_FILE!"

REM Use a safer method to check for task existence (avoiding potential errors)
schtasks /Query /TN "!STARTUP_TASK_NAME!" 2>nul >nul
IF %ERRORLEVEL% EQU 0 (
    ECHO [%TIME%] [INFO] Found existing startup task - removing it...
    ECHO [%DATE% %TIME%] [INFO] Removing existing startup task... >> "!LOG_FILE!"
    
    REM Try with basic command
    schtasks /Delete /TN "!STARTUP_TASK_NAME!" /F 2>nul >nul
    
    REM Verify it was actually removed
    schtasks /Query /TN "!STARTUP_TASK_NAME!" 2>nul >nul
    IF !ERRORLEVEL! NEQ 0 (
        ECHO [%TIME%] [INFO] Startup task removed successfully.
        ECHO [%DATE% %TIME%] [INFO] Startup task removed successfully. >> "!LOG_FILE!"
    ) ELSE (
        ECHO [%TIME%] [WARN] Could not remove startup task with basic command, trying PowerShell...
        powershell -ExecutionPolicy Bypass -Command "try { Unregister-ScheduledTask -TaskName '!STARTUP_TASK_NAME!' -Confirm:$false -ErrorAction Stop; Write-Host 'SUCCESS' } catch { Write-Host 'FAILED' }" > "!TEMP!\taskresult.txt" 2>nul
        SET /P PS_RESULT=<"!TEMP!\taskresult.txt"
        IF "!PS_RESULT!"=="SUCCESS" (
            ECHO [%TIME%] [INFO] Startup task removed successfully with PowerShell.
            ECHO [%DATE% %TIME%] [INFO] Startup task removed with PowerShell. >> "!LOG_FILE!"
        ) ELSE (
            ECHO [%TIME%] [ERROR] Could not remove startup task - will be overwritten if needed.
            ECHO [%DATE% %TIME%] [ERROR] Could not remove startup task. >> "!LOG_FILE!"
        )
        IF EXIST "!TEMP!\taskresult.txt" DEL /F /Q "!TEMP!\taskresult.txt" 2>nul >nul
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
    
    REM Create startup task to continue after restart using simple schtasks
    schtasks /Create /TN "!STARTUP_TASK_NAME!" /TR "\"!SCRIPT_PATH!\"" /SC ONLOGON /DELAY 0001:00 /F 2>nul >nul
    IF %ERRORLEVEL% NEQ 0 (
        REM Try without DELAY parameter (older Windows versions)
        schtasks /Create /TN "!STARTUP_TASK_NAME!" /TR "\"!SCRIPT_PATH!\"" /SC ONLOGON /F 2>nul >nul
    )
    
    IF %ERRORLEVEL% EQU 0 (
        ECHO [%TIME%] [INFO] Startup task created for post-restart execution.
        ECHO [%DATE% %TIME%] [INFO] Startup task created for post-restart execution. >> "!LOG_FILE!"
    ) ELSE (
        ECHO [%TIME%] [WARN] Could not create startup task. Restart will proceed anyway.
        ECHO [%DATE% %TIME%] [WARN] Startup task creation failed. >> "!LOG_FILE!"
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
    
    REM Try simple PowerShell command for App Installer download
    powershell -Command "try { Invoke-WebRequest -Uri 'https://aka.ms/getwinget' -OutFile '$env:TEMP\Microsoft.DesktopAppInstaller.msixbundle'; Add-AppxPackage -Path '$env:TEMP\Microsoft.DesktopAppInstaller.msixbundle'; Write-Host 'SUCCESS' } catch { Write-Host 'FAILED' }" > "!TEMP!\winget_result.txt" 2>nul
    
    SET /P WINGET_RESULT=<"!TEMP!\winget_result.txt"
    DEL /F /Q "!TEMP!\winget_result.txt" >nul 2>&1
    
    REM Verify installation
    timeout /t 3 /nobreak >nul
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
    ECHO [%TIME%] [WARN] PowerShell 7 not found. Installing...
    ECHO [%DATE% %TIME%] [WARN] PowerShell 7 not found. Installing... >> "!LOG_FILE!"
    
    REM Try winget first if available
    where winget.exe >nul 2>&1
    IF !ERRORLEVEL! EQU 0 (
        ECHO [%TIME%] [INFO] Installing PowerShell 7 via Winget...
        winget install Microsoft.PowerShell --silent --accept-package-agreements --accept-source-agreements >nul 2>&1
    ) ELSE (
        ECHO [%TIME%] [INFO] Installing PowerShell 7 via direct download...
        powershell -Command "try { Invoke-WebRequest -Uri 'https://github.com/PowerShell/PowerShell/releases/latest/download/PowerShell-7.4.5-win-x64.msi' -OutFile '$env:TEMP\PowerShell.msi'; Start-Process -FilePath 'msiexec.exe' -ArgumentList '/i $env:TEMP\PowerShell.msi /quiet /norestart' -Wait; Write-Host 'SUCCESS' } catch { Write-Host 'FAILED' }" > "!TEMP!\ps7_result.txt" 2>nul
    )
    
    REM Wait for installation to complete
    timeout /t 5 /nobreak >nul
    
    REM Verify installation with simple checks
    ECHO [%TIME%] [INFO] Verifying PowerShell 7 installation...
    where pwsh.exe >nul 2>&1
    IF !ERRORLEVEL! EQU 0 (
        ECHO [%TIME%] [INFO] PowerShell 7 found in PATH.
        SET "PWSH_FOUND=TRUE"
    ) ELSE (
        REM Check common installation paths
        IF EXIST "%ProgramFiles%\PowerShell\7\pwsh.exe" (
            ECHO [%TIME%] [INFO] PowerShell 7 found in Program Files.
            SET "PWSH_FOUND=TRUE"
        ) ELSE IF EXIST "%ProgramFiles(x86)%\PowerShell\7\pwsh.exe" (
            ECHO [%TIME%] [INFO] PowerShell 7 found in Program Files ^(x86^).
            SET "PWSH_FOUND=TRUE"
        ) ELSE (
            SET "PWSH_FOUND=FALSE"
        )
    )
    
    IF "!PWSH_FOUND!"=="TRUE" (
        ECHO [%TIME%] [INFO] PowerShell 7 installed successfully.
        ECHO [%DATE% %TIME%] [INFO] PowerShell 7 installation successful. >> "!LOG_FILE!"
    ) ELSE (
        ECHO [%TIME%] [ERROR] PowerShell 7 installation failed. Will use Windows PowerShell.
        ECHO [%DATE% %TIME%] [ERROR] PowerShell 7 installation failed. Using fallback. >> "!LOG_FILE!"
    )
    
    REM Clean up temp files
    IF EXIST "!TEMP!\ps7_result.txt" DEL /F /Q "!TEMP!\ps7_result.txt" >nul 2>&1
    IF EXIST "%TEMP%\PowerShell.msi" DEL /F /Q "%TEMP%\PowerShell.msi" >nul 2>&1
) ELSE (
    ECHO [%TIME%] [INFO] PowerShell 7 is already available.
    ECHO [%DATE% %TIME%] [INFO] PowerShell 7 already available. >> "!LOG_FILE!"
)

REM ============================================================================
REM [STEP 9] DEPENDENCIES CHECK AND INSTALLATION
REM ============================================================================
ECHO [%TIME%] [INFO] Checking and installing required dependencies...
ECHO [%DATE% %TIME%] [INFO] Checking all required dependencies... >> "!LOG_FILE!"

REM Checking VBScript (cscript.exe) as specified in somefile.txt
ECHO [%TIME%] [INFO] Checking VBScript (cscript.exe)...
where cscript.exe >nul 2>&1
IF %ERRORLEVEL% NEQ 0 (
    ECHO [%TIME%] [WARN] VBScript (cscript.exe) not found. This should be a standard Windows component.
    ECHO [%DATE% %TIME%] [WARN] VBScript not found. >> "!LOG_FILE!"
) ELSE (
    ECHO [%TIME%] [INFO] VBScript (cscript.exe) is available.
    ECHO [%DATE% %TIME%] [INFO] VBScript is available. >> "!LOG_FILE!"
)

REM Checking Windows Task Scheduler (schtasks.exe) as specified in somefile.txt
ECHO [%TIME%] [INFO] Checking Windows Task Scheduler (schtasks.exe)...
where schtasks.exe >nul 2>&1
IF %ERRORLEVEL% NEQ 0 (
    ECHO [%TIME%] [WARN] Windows Task Scheduler (schtasks.exe) not found. This should be a standard Windows component.
    ECHO [%DATE% %TIME%] [WARN] Task Scheduler not found. >> "!LOG_FILE!"
) ELSE (
    ECHO [%TIME%] [INFO] Windows Task Scheduler (schtasks.exe) is available.
    ECHO [%DATE% %TIME%] [INFO] Task Scheduler is available. >> "!LOG_FILE!"
)

REM Checking DISM as specified in somefile.txt
ECHO [%TIME%] [INFO] Checking DISM...
where dism.exe >nul 2>&1
IF %ERRORLEVEL% NEQ 0 (
    ECHO [%TIME%] [WARN] DISM not found. This should be a standard Windows component.
    ECHO [%DATE% %TIME%] [WARN] DISM not found. >> "!LOG_FILE!"
) ELSE (
    ECHO [%TIME%] [INFO] DISM is available.
    ECHO [%DATE% %TIME%] [INFO] DISM is available. >> "!LOG_FILE!"
)

REM Install NuGet Provider and PowerShellGet (essential for module installation) with simplified approach
ECHO [%TIME%] [INFO] Installing NuGet Provider and PowerShellGet...
ECHO [%DATE% %TIME%] [INFO] Installing NuGet Provider... >> "!LOG_FILE!"

REM Simple NuGet Provider installation
powershell -Command "try { Install-PackageProvider -Name NuGet -Force -Scope CurrentUser -MinimumVersion 2.8.5.201; Write-Host 'SUCCESS' } catch { Write-Host 'FAILED' }" > "!TEMP!\nuget_result.txt" 2>nul
SET /P NUGET_RESULT=<"!TEMP!\nuget_result.txt"
IF EXIST "!TEMP!\nuget_result.txt" DEL /F /Q "!TEMP!\nuget_result.txt" >nul 2>&1

IF "!NUGET_RESULT!"=="SUCCESS" (
    ECHO [%TIME%] [INFO] NuGet Provider installed successfully.
    ECHO [%DATE% %TIME%] [INFO] NuGet Provider installation successful. >> "!LOG_FILE!"
) ELSE (
    ECHO [%TIME%] [WARN] NuGet Provider installation failed or already exists.
    ECHO [%DATE% %TIME%] [WARN] NuGet Provider installation uncertain. >> "!LOG_FILE!"
)

REM Install NuGet CLI if needed as specified in somefile.txt
ECHO [%TIME%] [INFO] Checking NuGet CLI (nuget.exe)...
where nuget.exe >nul 2>&1
IF %ERRORLEVEL% NEQ 0 (
    ECHO [%TIME%] [INFO] Installing NuGet CLI...
    ECHO [%DATE% %TIME%] [INFO] Installing NuGet CLI... >> "!LOG_FILE!"
    powershell -Command "try { Invoke-WebRequest -Uri 'https://dist.nuget.org/win-x86-commandline/latest/nuget.exe' -OutFile '$env:TEMP\nuget.exe'; Copy-Item '$env:TEMP\nuget.exe' '$env:SystemRoot\System32\nuget.exe' -Force; Write-Host 'SUCCESS' } catch { Write-Host 'FAILED' }" > "!TEMP!\nugcli_result.txt" 2>nul
    SET /P NUGCLI_RESULT=<"!TEMP!\nugcli_result.txt"
    IF EXIST "!TEMP!\nugcli_result.txt" DEL /F /Q "!TEMP!\nugcli_result.txt" >nul 2>&1
    
    IF "!NUGCLI_RESULT!"=="SUCCESS" (
        ECHO [%TIME%] [INFO] NuGet CLI installed successfully.
    ) ELSE (
        ECHO [%TIME%] [WARN] NuGet CLI installation failed.
    )
) ELSE (
    ECHO [%TIME%] [INFO] NuGet CLI (nuget.exe) already available.
    ECHO [%DATE% %TIME%] [INFO] NuGet CLI already available. >> "!LOG_FILE!"
)

REM Simple PowerShellGet check
ECHO [%TIME%] [INFO] Checking PowerShellGet module...
ECHO [%DATE% %TIME%] [INFO] Checking PowerShellGet... >> "!LOG_FILE!"
powershell -Command "if (Get-Module -Name PowerShellGet -ListAvailable) { Write-Host 'AVAILABLE' } else { Write-Host 'MISSING' }" > "!TEMP!\psget_result.txt" 2>nul
SET /P PSGET_RESULT=<"!TEMP!\psget_result.txt"
IF EXIST "!TEMP!\psget_result.txt" DEL /F /Q "!TEMP!\psget_result.txt" >nul 2>&1

IF "!PSGET_RESULT!"=="AVAILABLE" (
    ECHO [%TIME%] [INFO] PowerShellGet is available.
) ELSE (
    ECHO [%TIME%] [WARN] PowerShellGet not found - may affect module installation.
)

REM Install PSWindowsUpdate module simply
ECHO [%TIME%] [INFO] Installing PSWindowsUpdate module...
ECHO [%DATE% %TIME%] [INFO] Installing PSWindowsUpdate module... >> "!LOG_FILE!"
powershell -Command "try { Set-PSRepository -Name PSGallery -InstallationPolicy Trusted; Install-Module -Name PSWindowsUpdate -Force -Scope CurrentUser; Write-Host 'SUCCESS' } catch { Write-Host 'FAILED' }" > "!TEMP!\psupdate_result.txt" 2>nul
SET /P PSUPDATE_RESULT=<"!TEMP!\psupdate_result.txt"
IF EXIST "!TEMP!\psupdate_result.txt" DEL /F /Q "!TEMP!\psupdate_result.txt" >nul 2>&1

IF "!PSUPDATE_RESULT!"=="SUCCESS" (
    ECHO [%TIME%] [INFO] PSWindowsUpdate module installed successfully.
) ELSE (
    ECHO [%TIME%] [WARN] PSWindowsUpdate module installation failed.
)

REM Check Appx module as specified in somefile.txt
ECHO [%TIME%] [INFO] Checking Appx module...
powershell -Command "if (Get-Module -Name Appx -ListAvailable) { Write-Host 'AVAILABLE' } else { Write-Host 'MISSING' }" > "!TEMP!\appx_result.txt" 2>nul
SET /P APPX_RESULT=<"!TEMP!\appx_result.txt"
IF EXIST "!TEMP!\appx_result.txt" DEL /F /Q "!TEMP!\appx_result.txt" >nul 2>&1

IF "!APPX_RESULT!"=="AVAILABLE" (
    ECHO [%TIME%] [INFO] Appx module is available.
) ELSE (
    ECHO [%TIME%] [INFO] Appx module not directly available - will be handled in script.ps1.
)
ECHO [%DATE% %TIME%] [INFO] Appx module handling deferred to PowerShell script. >> "!LOG_FILE!"

ECHO [%TIME%] [INFO] PowerShell dependencies installation completed unattended.
ECHO [%DATE% %TIME%] [INFO] Dependencies installation completed. >> "!LOG_FILE!"

REM ============================================================================
REM [STEP 10] REPOSITORY DOWNLOAD AND EXTRACTION
REM ============================================================================
ECHO [%TIME%] [INFO] Checking for local or downloading repository...
ECHO [%DATE% %TIME%] [INFO] Checking for script.ps1... >> "!LOG_FILE!"

REM Ensure all paths are relative to script.bat location regardless of where it's launched from
SET "REPO_URL=https://github.com/ichimbogdancristian/script_mentenanta/archive/refs/heads/main.zip"
SET "REPO_ZIP=!SCRIPT_DIR!\repo.zip"
SET "REPO_FOLDER=!SCRIPT_DIR!\script_mentenanta-main"
SET "LOCAL_PS1=!SCRIPT_DIR!\script.ps1"
SET "REPO_PS1=!REPO_FOLDER!\script.ps1"

REM Log path information for environmental awareness
ECHO [%DATE% %TIME%] [INFO] Repository paths set: >> "!LOG_FILE!"
ECHO [%DATE% %TIME%] [INFO] - Zip file: !REPO_ZIP! >> "!LOG_FILE!"
ECHO [%DATE% %TIME%] [INFO] - Repo folder: !REPO_FOLDER! >> "!LOG_FILE!"
ECHO [%DATE% %TIME%] [INFO] - Local PS1: !LOCAL_PS1! >> "!LOG_FILE!"
ECHO [%DATE% %TIME%] [INFO] - Repo PS1: !REPO_PS1! >> "!LOG_FILE!"

REM Check if script.ps1 exists locally first
IF EXIST "!LOCAL_PS1!" (
    ECHO [%TIME%] [INFO] Using local script.ps1 file
    ECHO [%DATE% %TIME%] [INFO] Using local script.ps1 file. >> "!LOG_FILE!"
    SET "PS1_SCRIPT=!LOCAL_PS1!"
    GOTO :SKIP_DOWNLOAD
)

REM Download repository to the same path as script.bat as specified in somefile.txt
ECHO [%TIME%] [INFO] Local script.ps1 not found. Downloading from repository...
ECHO [%DATE% %TIME%] [INFO] Downloading repository to: !SCRIPT_DIR! >> "!LOG_FILE!"

REM Simple download with basic PowerShell
powershell -Command "try { Invoke-WebRequest -Uri '!REPO_URL!' -OutFile '!REPO_ZIP!' -UseBasicParsing; Write-Host 'SUCCESS' } catch { Write-Host 'FAILED' }" > "!TEMP!\download_result.txt" 2>nul
SET /P DOWNLOAD_RESULT=<"!TEMP!\download_result.txt"
IF EXIST "!TEMP!\download_result.txt" DEL /F /Q "!TEMP!\download_result.txt" >nul 2>&1

IF "!DOWNLOAD_RESULT!"=="SUCCESS" (
    IF EXIST "!REPO_ZIP!" (
        ECHO [%TIME%] [INFO] Repository downloaded successfully. Extracting...
        ECHO [%DATE% %TIME%] [INFO] Repository downloaded. Extracting... >> "!LOG_FILE!"
        
        REM Simple extraction
        powershell -Command "try { Expand-Archive -Path '!REPO_ZIP!' -DestinationPath '!SCRIPT_DIR!' -Force; Write-Host 'SUCCESS' } catch { Write-Host 'FAILED' }" > "!TEMP!\extract_result.txt" 2>nul
        SET /P EXTRACT_RESULT=<"!TEMP!\extract_result.txt"
        IF EXIST "!TEMP!\extract_result.txt" DEL /F /Q "!TEMP!\extract_result.txt" >nul 2>&1
        
        IF "!EXTRACT_RESULT!"=="SUCCESS" (
            ECHO [%TIME%] [INFO] Repository extracted successfully.
            ECHO [%DATE% %TIME%] [INFO] Repository extracted to: !REPO_FOLDER! >> "!LOG_FILE!"
            DEL /F /Q "!REPO_ZIP!" >nul 2>&1
            SET "PS1_SCRIPT=!REPO_FOLDER!\script.ps1"
        ) ELSE (
            ECHO [%TIME%] [ERROR] Repository extraction failed.
            ECHO [%DATE% %TIME%] [ERROR] Repository extraction failed. >> "!LOG_FILE!"
            GOTO LOCAL_SCRIPT
        )
    ) ELSE (
        ECHO [%TIME%] [ERROR] Download completed but file not found.
        ECHO [%DATE% %TIME%] [ERROR] Download file not found. >> "!LOG_FILE!"
        GOTO LOCAL_SCRIPT
    )
) ELSE (
    ECHO [%TIME%] [ERROR] Repository download failed. Attempting to use local script.
    ECHO [%DATE% %TIME%] [ERROR] Repository download failed. >> "!LOG_FILE!"
    GOTO LOCAL_SCRIPT
)

:SKIP_DOWNLOAD

:LOCAL_SCRIPT
REM Try to locate script.ps1 in various locations
SET "SCRIPT_FOUND=0"

REM Check original location first
IF EXIST "!LOCAL_PS1!" (
    ECHO [%TIME%] [INFO] Using local script.ps1
    ECHO [%DATE% %TIME%] [INFO] Using local script: !LOCAL_PS1! >> "!LOG_FILE!"
    SET "PS1_SCRIPT=!LOCAL_PS1!"
    SET "SCRIPT_FOUND=1"
    GOTO SCRIPT_FOUND
)

REM Check if script exists in the current directory (regardless of how we got here)
IF EXIST "script.ps1" (
    SET "PS1_SCRIPT=%CD%\script.ps1"
    ECHO [%TIME%] [INFO] Found script.ps1 in current directory: !PS1_SCRIPT!
    ECHO [%DATE% %TIME%] [INFO] Found script.ps1 in current directory: !PS1_SCRIPT! >> "!LOG_FILE!"
    SET "SCRIPT_FOUND=1"
    GOTO SCRIPT_FOUND
)

REM Check if the repository extraction succeeded but we didn't find script.ps1 in expected location
IF EXIST "!REPO_FOLDER!" (
    REM Check if script.ps1 exists somewhere in the repository folder
    FOR /R "!REPO_FOLDER!" %%F IN (script.ps1) DO (
        IF EXIST "%%F" (
            SET "PS1_SCRIPT=%%F"
            ECHO [%TIME%] [INFO] Found script.ps1 in repository subdirectory: !PS1_SCRIPT!
            ECHO [%DATE% %TIME%] [INFO] Found script.ps1 in repository subdirectory: !PS1_SCRIPT! >> "!LOG_FILE!"
            SET "SCRIPT_FOUND=1"
            GOTO SCRIPT_FOUND
        )
    )
)

IF !SCRIPT_FOUND! EQU 0 (
    ECHO [%TIME%] [ERROR] script.ps1 not found in any location. Cannot continue.
    ECHO [%DATE% %TIME%] [ERROR] script.ps1 not found in any location. Cannot continue. >> "!LOG_FILE!"
    ECHO Locations checked:
    ECHO   - !LOCAL_PS1!
    ECHO   - %CD%\script.ps1
    ECHO   - !REPO_FOLDER!\script.ps1 (and subdirectories)
    pause
    EXIT /B 1
)

:SCRIPT_FOUND

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

REM Determine PowerShell executable (prefer pwsh, fallback to powershell) - simplified
SET "PS_EXECUTABLE=powershell.exe"
SET "PS_VERSION=Windows PowerShell"

REM Simple check for PowerShell 7
where pwsh.exe >nul 2>&1
IF %ERRORLEVEL% EQU 0 (
    SET "PS_EXECUTABLE=pwsh.exe"
    SET "PS_VERSION=PowerShell 7"
    GOTO :PS_FOUND
)

REM Check common PowerShell 7 paths
IF EXIST "%ProgramFiles%\PowerShell\7\pwsh.exe" (
    SET "PS_EXECUTABLE=%ProgramFiles%\PowerShell\7\pwsh.exe"
    SET "PS_VERSION=PowerShell 7"
    GOTO :PS_FOUND
)

IF EXIST "%ProgramFiles(x86)%\PowerShell\7\pwsh.exe" (
    SET "PS_EXECUTABLE=%ProgramFiles(x86)%\PowerShell\7\pwsh.exe"
    SET "PS_VERSION=PowerShell 7"
    GOTO :PS_FOUND
)

REM If PowerShell 7 not found, use Windows PowerShell
ECHO [%TIME%] [WARN] PowerShell 7 not found. Using Windows PowerShell.
ECHO [%DATE% %TIME%] [WARN] Using Windows PowerShell fallback. >> "!LOG_FILE!"

:PS_FOUND
ECHO [%TIME%] [INFO] Using !PS_VERSION!: !PS_EXECUTABLE!
ECHO [%DATE% %TIME%] [INFO] Using !PS_VERSION!: !PS_EXECUTABLE! >> "!LOG_FILE!"

REM Launch script.ps1 in PowerShell 7 environment with admin rights as specified in somefile.txt
REM Pass repo folder information for cleanup purposes
ECHO [%TIME%] [INFO] Executing script.ps1 in a PowerShell 7 environment with admin rights...
ECHO [%DATE% %TIME%] [INFO] Executing script.ps1 with PowerShell: !PS_EXECUTABLE! >> "!LOG_FILE!"

IF "!PS1_SCRIPT!"=="!LOCAL_PS1!" (
    REM Using local script - check if repo folder exists
    IF EXIST "!REPO_FOLDER!" (
        ECHO [%TIME%] [INFO] Using local script with repo folder: !REPO_FOLDER!
        ECHO [%DATE% %TIME%] [INFO] Using local script with repo folder: !REPO_FOLDER! >> "!LOG_FILE!"
        START "PowerShell Maintenance Script" "!PS_EXECUTABLE!" -ExecutionPolicy Bypass -WindowStyle Normal -NoExit -File "!PS1_SCRIPT!" -LogFilePath "!LOG_FILE!" -RepoFolderPath "!REPO_FOLDER!" -ScriptDir "!SCRIPT_DIR!"
    ) ELSE (
        ECHO [%TIME%] [INFO] Using local script without repo folder
        ECHO [%DATE% %TIME%] [INFO] Using local script without repo folder >> "!LOG_FILE!"
        START "PowerShell Maintenance Script" "!PS_EXECUTABLE!" -ExecutionPolicy Bypass -WindowStyle Normal -NoExit -File "!PS1_SCRIPT!" -LogFilePath "!LOG_FILE!" -RepoFolderPath "" -ScriptDir "!SCRIPT_DIR!"
    )
) ELSE (
    REM Using downloaded script - pass repo folder for cleanup
    ECHO [%TIME%] [INFO] Using downloaded script with repo folder: !REPO_FOLDER!
    ECHO [%DATE% %TIME%] [INFO] Using downloaded script with repo folder: !REPO_FOLDER! >> "!LOG_FILE!"
    ECHO [92mScript launching successful! Running PowerShell maintenance script in a new window...[0m
    START "PowerShell Maintenance Script" "!PS_EXECUTABLE!" -ExecutionPolicy Bypass -WindowStyle Normal -NoExit -File "!PS1_SCRIPT!" -LogFilePath "!LOG_FILE!" -RepoFolderPath "!REPO_FOLDER!" -ScriptDir "!SCRIPT_DIR!"
)

REM ============================================================================
REM [STEP 12] COUNTDOWN AND CLEANUP
REM ============================================================================
ECHO [%TIME%] [INFO] PowerShell maintenance script launched successfully.
ECHO [%DATE% %TIME%] [INFO] PowerShell script launched. Starting 20-second countdown... >> "!LOG_FILE!"

ECHO.
ECHO ========================================
ECHO   Maintenance Script Launched
ECHO ========================================
ECHO.
ECHO PowerShell maintenance script is now running in a separate window.
ECHO This launcher window will close automatically in 20 seconds.
ECHO Press Ctrl+C to abort the countdown and keep this window open.
ECHO.

REM 20-second countdown with abort option as specified in somefile.txt
ECHO [%TIME%] [INFO] Starting 20-second countdown before closing...
FOR /L %%i IN (20,-1,1) DO (
    ECHO Closing in %%i seconds... ^(Press Ctrl+C to abort the countdown^)
    timeout /t 1 /nobreak >nul 2>&1
    IF !ERRORLEVEL! NEQ 0 (
        ECHO.
        ECHO Countdown aborted by user. Window will remain open.
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
