# Windows Maintenance Automation - Deployment & Operations Guide

**Document Version**: 1.0.0  
**Date**: January 29, 2026  
**Audience**: IT Administrators, System Operators  
**Status**: Pre-Release (v3.2)

---

## Table of Contents

1. [Quick Start](#quick-start)
2. [Architecture Overview](#architecture-overview)
3. [Network Deployment](#network-deployment)
4. [Scheduled Task Configuration](#scheduled-task-configuration)
5. [Report Management](#report-management)
6. [Troubleshooting Guide](#troubleshooting-guide)
7. [FAQ](#faq)

---

## Quick Start

### Local PC Installation

```batch
REM 1. Place script.bat in desired location (e.g., C:\Maintenance\)
REM 2. Open cmd as Administrator

cd C:\Maintenance
script.bat

REM 3. Follow interactive menu to execute maintenance
REM 4. System will automatically:
REM    - Create system restore point (automatic rollback protection)
REM    - Run maintenance tasks
REM    - Generate report in %ProgramData%\WindowsMaintenance\reports\
REM    - Prompt for reboot after 120-second countdown

REM To enable scheduled execution:
schtasks /Create /SC MONTHLY /MO 1 /D 20 /TN "WindowsMaintenanceAutomation" ^
    /TR "C:\Maintenance\script.bat" /ST 01:00 /RL HIGHEST /RU SYSTEM /F
```

### Key Feature: Automatic System Restore Points

Before any maintenance operations, the script creates a **system restore point** for rollback protection:

```
✓ Checks if System Protection is enabled
✓ Enables System Protection if necessary
✓ Creates restore point: WindowsMaintenance-[GUID]
✓ Verifies restore point creation
✓ Logs sequence number for manual recovery if needed
✓ Continues gracefully if restore point creation fails
```

If something goes wrong during maintenance, you can roll back to the restore point:

- **Windows Settings** → **System** → **System Restore** → **Choose Restore Point**
- Or use: `rstrui.exe` at command line

---

## Architecture Overview

### Component Stack & Execution Flow

```
LAYER 1: Local Execution (script.bat)
  ↓
  1. Create System Restore Point (rollback safety)
  2. Check/Install PowerShell 7 dependencies
  3. Download latest repo from GitHub
  4. Extract to temp directory

  ↓ Launch MaintenanceOrchestrator.ps1

LAYER 2: Infrastructure Modules
  CoreInfrastructure.psm1 (paths, config, logging)
  LogAggregator.psm1 (result collection)
  LogProcessor.psm1 (data aggregation)
  ReportGenerator.psm1 (report rendering)

LAYER 3: Operations Modules
  Type1: Audit modules (read-only detection)
    - BloatwareDetectionAudit
    - EssentialAppsAudit
    - SystemOptimizationAudit
    - WindowsUpdatesAudit
    - TelemetryAudit
    - SecurityAudit
    - PrivacyInventory
    - SystemInformationAudit

  Type2: Execution modules (system modification)
    - BloatwareRemoval (calls Type1 internally)
    - EssentialApps (calls Type1 internally)
    - SystemOptimization (calls Type1 internally)
    - TelemetryDisable (calls Type1 internally)
    - WindowsUpdates (calls Type1 internally)
    - AppUpgrade (calls Type1 internally)
    - SecurityEnhancement (calls Type1 internally)
    - SystemInventory (calls Type1 internally)

OUTPUT GENERATION:
  ↓ LogProcessor: Aggregate audit results + execution logs
  ↓ ReportGenerator: Render HTML/text/JSON reports

FINAL OUTPUT:
  Reports → %ProgramData%\WindowsMaintenance\reports\
  Logs → [extraction folder]\temp_files\logs\
  Session data → [extraction folder]\temp_files\processed\
  System Restore Point → Windows System Recovery

POST-EXECUTION:
  ↓ Cleanup temporary files
  ↓ Display 120-second countdown to reboot
  ↓ Automatic system reboot (or user cancellation)
```

### Key Feature: System Restore Point

Every execution automatically creates a **system restore point** for protection:

1. **Checks** if System Protection is available
2. **Enables** System Protection if needed (one-time)
3. **Creates** unique restore point: `WindowsMaintenance-[8-char-GUID]`
4. **Logs** sequence number for manual recovery
5. **Continues gracefully** if restore point creation fails

**Manual Recovery**:

```batch
REM Open System Restore UI
rstrui.exe

REM Or via Settings → System → System Restore → Choose Different Restore Point
```

---

## Network Deployment

### Local Deployment Architecture

This system is designed for **local execution on each PC independently**. Each machine downloads the latest version from GitHub and runs maintenance autonomously.

```
PC 1: Downloads → Maintenance → Report (local)
PC 2: Downloads → Maintenance → Report (local)
PC 3: Downloads → Maintenance → Report (local)
...
PC N: Downloads → Maintenance → Report (local)
```

### Deployment Scenarios

#### Scenario 1: Individual PC (Recommended for Small Environments)

**Setup**:

1. Copy `script.bat` to each PC: `C:\Maintenance\`
2. Create scheduled task on each PC

**Pros**:

- Complete autonomy - no dependencies
- Auto-downloads latest version from GitHub
- No network share required
- Works in isolated/offline environments (after first run)

**Cons**:

- More deployment work per PC
- Each PC downloads independently (more bandwidth)

**Implementation**:

```batch
REM On each PC (as Administrator)

REM 1. Create directory
mkdir C:\Maintenance

REM 2. Copy script.bat to C:\Maintenance\

REM 3. Create scheduled task
schtasks /Create ^
    /SC MONTHLY ^
    /MO 1 ^
    /D 20 ^
    /TN "WindowsMaintenanceAutomation" ^
    /TR "C:\Maintenance\script.bat" ^
    /ST 01:00 ^
    /RL HIGHEST ^
    /RU SYSTEM ^
    /F

REM 4. Verify task created
schtasks /Query /TN "WindowsMaintenanceAutomation" /FO LIST
```

#### Scenario 2: Bulk Deployment via Group Policy (Enterprise)

**Setup**:

1. Create GPO with startup script that copies script.bat
2. Deploy to multiple PCs via domain

**Pros**:

- Centralized deployment
- Automatic across domain

**Cons**:

- Requires Active Directory
- More complex setup

**Implementation**:

```batch
REM Group Policy Startup Script (Startup.bat)
REM Deploy via: GPO → Computer Configuration → Windows Settings → Scripts → Startup

@ECHO OFF
SETLOCAL ENABLEDELAYEDEXPANSION

REM Copy from network share or UNC path
COPY "\\fileserver\software\script.bat" "C:\Maintenance\" /Y

REM Create scheduled task if it doesn't exist
schtasks /Query /TN "WindowsMaintenanceAutomation" >nul 2>&1
IF ERRORLEVEL 1 (
    schtasks /Create ^
        /SC MONTHLY ^
        /MO 1 ^
        /D 20 ^
        /TN "WindowsMaintenanceAutomation" ^
        /TR "C:\Maintenance\script.bat" ^
        /ST 01:00 ^
        /RL HIGHEST ^
        /RU SYSTEM ^
        /F
)

EXIT /B 0
```

#### Scenario 3: USB/Removable Media (Portable)

**Setup**:

1. Copy entire repo to USB drive: `E:\Maintenance\`
2. Run from USB on each PC

**Pros**:

- Portable - no installation needed
- Works completely offline
- Useful for air-gapped networks

**Cons**:

- Manual execution on each PC
- Reports scattered across USB
- Not suitable for automated scheduling

**Implementation**:

```batch
REM Run from USB (as Administrator)
E:\Maintenance\script.bat

REM After execution, reports available in:
E:\Maintenance\temp_files\reports\
```

#### Scenario 4: Pre-staged on Fleet (For OEM/Imaging)

**Setup**:

1. Include script.bat in master Windows image
2. Deploy to all PCs via image
3. Create scheduled task during post-deployment

**Pros**:

- Fastest deployment
- Already present on all PCs
- No manual distribution

**Cons**:

- Requires imaging process
- Harder to update all PCs

**Implementation**:

```batch
REM In post-deployment script / OOBE customizations
REM Create scheduled task during first boot

schtasks /Create ^
    /SC MONTHLY ^
    /MO 1 ^
    /D 20 ^
    /TN "WindowsMaintenanceAutomation" ^
    /TR "C:\Maintenance\script.bat" ^
    /ST 01:00 ^
    /RL HIGHEST ^
    /RU SYSTEM ^
    /F
```

---

## Scheduled Task Configuration

### Monthly Execution (Recommended)

**Create Monthly Task** (20th of each month at 1:00 AM):

```batch
schtasks /Create ^
    /SC MONTHLY ^
    /MO 1 ^
    /D 20 ^
    /TN "WindowsMaintenanceAutomation" ^
    /TR "C:\Maintenance\script.bat" ^
    /ST 01:00 ^
    /RL HIGHEST ^
    /RU SYSTEM ^
    /F
```

**Key Parameters**:

- `/SC MONTHLY` = Monthly schedule
- `/MO 1` = First occurrence
- `/D 20` = Day of month (20th)
- `/ST 01:00` = Time (1:00 AM)
- `/RL HIGHEST` = Highest privileges
- `/RU SYSTEM` = Run as SYSTEM account (highest privs)

### Query Task Status

```batch
REM View task details
schtasks /Query /TN "WindowsMaintenanceAutomation" /FO LIST /V

REM View next run time
schtasks /Query /TN "WindowsMaintenanceAutomation" /FO LIST | findstr /C:"Next Run Time"
```

### Manual Execution

```batch
REM Run task immediately (for testing)
schtasks /Run /TN "WindowsMaintenanceAutomation" /F

REM View task history
Event Viewer → Windows Logs → System → Find "WindowsMaintenanceAutomation"
```

### Delete Task

```batch
schtasks /Delete /TN "WindowsMaintenanceAutomation" /F
```

---

## Report Management

### Report Location

**Primary Storage** (Recommended access):

```
%ProgramData%\WindowsMaintenance\reports\
C:\ProgramData\WindowsMaintenance\reports\
```

**Files**:

- `MaintenanceReport_YYYY-MM-DD_HHmmss.html` - Full interactive HTML report
- `MaintenanceReport_YYYY-MM-DD_HHmmss.txt` - Text summary
- `reports-index.json` - Report catalog with session metadata

### Access Reports

**Method 1**: File Explorer

```
C:\ProgramData\WindowsMaintenance\reports\
```

**Method 2**: Report Browser (if available)

```
C:\ProgramData\WindowsMaintenance\index.html
```

**Method 3**: Command Line

```powershell
Get-ChildItem "C:\ProgramData\WindowsMaintenance\reports\" -Filter "*.html" | Select-Object FullName, LastWriteTime
```

### Report Retention

**Default Policy**:

- Keep last 24 months of reports
- Older reports automatically removed from index
- Physical files kept unless manually deleted

**Manual Cleanup** (if needed):

```batch
REM Remove reports older than 6 months
forfiles /S /D +180 /M "MaintenanceReport_*.html" /C "cmd /c del @file"
```

### Export Reports

**Copy to USB**:

```batch
xcopy C:\ProgramData\WindowsMaintenance\reports\ D:\Maintenance_Reports\ /E /Y
```

**Compress for Email**:

```powershell
Compress-Archive -Path "C:\ProgramData\WindowsMaintenance\reports\MaintenanceReport_*.html" -DestinationPath "C:\Reports_Archive.zip" -Force
```

---

## Troubleshooting Guide

### Common Issues

#### Issue #1: Scheduled Task Fails Silently

**Symptoms**:

- Task appears in Task Scheduler
- Task doesn't execute
- No error message

**Diagnosis**:

```batch
REM Check task last result
schtasks /Query /TN "WindowsMaintenanceAutomation" /FO LIST | findstr /C:"Last Result"

REM Common result codes:
REM 0 = Success
REM 1 = Incorrect function
REM 2 = File not found
REM 268 = Already running
REM 2147485651 = Access denied
```

**Solutions**:

```batch
REM 1. Verify script path exists
IF NOT EXIST "C:\Maintenance\script.bat" (
    Echo Script not found!
    GOTO :FAIL
)

REM 2. Verify SYSTEM account permissions
icacls "C:\Maintenance" /grant "SYSTEM:(OI)(CI)F"

REM 3. Recreate the task
schtasks /Delete /TN "WindowsMaintenanceAutomation" /F
schtasks /Create /SC MONTHLY /MO 1 /D 20 /TN "WindowsMaintenanceAutomation" ^
    /TR "C:\Maintenance\script.bat" /ST 01:00 /RL HIGHEST /RU SYSTEM /F
```

---

#### Issue #2: PowerShell 7 Installation Hangs

**Symptoms**:

- Script.bat runs but seems to hang
- No output for 5-10 minutes
- PowerShell 7 being installed

**Why**: PowerShell 7 installation via winget can take 5-10 minutes on first run

**Solutions**:

```batch
REM 1. Wait longer (may take 10+ minutes first run)

REM 2. Or pre-install PowerShell 7 on all PCs:
winget install Microsoft.PowerShell

REM 3. Or install via Chocolatey (faster):
choco install powershell-core -y

REM 4. Check installation status
pwsh.exe -Version
```

---

#### Issue #3: Reports Not Found in %ProgramData%

**Symptoms**:

- Script runs successfully
- No reports in `C:\ProgramData\WindowsMaintenance\reports\`
- Report location unknown

**Diagnosis**:

```batch
REM Check if temp directory has reports
dir C:\Users\%USERNAME%\AppData\Local\Temp\script_mentenanta*\temp_files\reports\

REM Check maintenance.log for clues
C:\ProgramData\WindowsMaintenance\logs\maintenance.log
REM or
[Extracted folder]\temp_files\logs\maintenance.log
```

**Solutions**:

```batch
REM 1. Check permissions on ProgramData
icacls C:\ProgramData\WindowsMaintenance

REM 2. Ensure directory exists
IF NOT EXIST C:\ProgramData\WindowsMaintenance MKDIR C:\ProgramData\WindowsMaintenance
IF NOT EXIST C:\ProgramData\WindowsMaintenance\reports MKDIR C:\ProgramData\WindowsMaintenance\reports

REM 3. Check temp folder for reports (fallback location)
dir "%TEMP%\script_mentenanta*\temp_files\reports\"
```

---

#### Issue #4: Reboot Not Happening

**Symptoms**:

- Scheduled task completes
- System does NOT reboot
- Countdown timer never appears

**Diagnosis**:

```batch
REM Check if script.bat passed -NonInteractive flag
REM (interactive mode doesn't auto-reboot)

REM Check maintenance.log for reboot messages
findstr /C:"Initiating automatic system reboot" C:\ProgramData\WindowsMaintenance\logs\maintenance.log
```

**Solutions**:

```batch
REM 1. Ensure scheduled task runs non-interactive
REM   (should be automatic for scheduled tasks)

REM 2. Check for pending Windows Updates preventing reboot
REM   (reboot deferred until updates applied)

REM 3. Manually restart if needed
shutdown /r /t 5 /c "Completing Windows Maintenance"

REM 4. Check Event Log for shutdown errors
Event Viewer → Windows Logs → System → Filter by Shutdown/Restart events
```

---

#### Issue #5: Module-Specific Failures

**Symptoms**:

- One or more modules fail
- Execution continues but some tasks skipped
- Error messages in log file

**Module Failure Troubleshooting**:

```
BloatwareRemoval Failed:
  → Check WinGet availability: winget --version
  → Check config: config/lists/bloatware-list.json

EssentialApps Failed:
  → Check package manager: winget --version or choco --version
  → Check network connectivity

WindowsUpdates Failed:
  → Check PSWindowsUpdate module: Get-Module PSWindowsUpdate -ListAvailable
  → Check Windows Update service: Get-Service wuauserv

SystemOptimization Failed:
  → Check SYSTEM permissions: whoami /priv
  → Check registry access: reg query HKLM\SYSTEM

TelemetryDisable Failed:
  → Check group policies: gpresult /h report.html
  → Some telemetry changes may require group policy override
```

---

### Emergency Recovery

**If system is in inconsistent state**:

```batch
REM 1. Delete all maintenance environment variables
for /f "delims==" %A in ('set WMA_') do @set %A=

REM 2. Delete the scheduled task
schtasks /Delete /TN "WindowsMaintenanceAutomation" /F

REM 3. Delete extracted folders
for /d %A in (%TEMP%\script_mentenanta*) do rmdir /s /q %A

REM 4. Recreate the scheduled task cleanly
schtasks /Create /SC MONTHLY /MO 1 /D 20 /TN "WindowsMaintenanceAutomation" ^
    /TR "C:\Maintenance\script.bat" /ST 01:00 /RL HIGHEST /RU SYSTEM /F
```

---

## FAQ

### Q: How often should maintenance run?

**A**: Default is monthly (20th of each month at 1:00 AM). You can change:

- `/D 1` for 1st of month
- `/SC WEEKLY` for weekly execution
- `/ST 02:00` for different time

### Q: What if I don't want automatic reboot?

**A**: Run in interactive mode instead of scheduled task:

```batch
C:\Maintenance\script.bat
```

Press any key during 120-second countdown to abort reboot.

### Q: What's the system restore point for?

**A**: Every maintenance run creates an automatic system restore point before any changes:

```
✓ WindowsMaintenance-[GUID] = Automatic rollback protection
✓ If something goes wrong, you can roll back
✓ Created by: Checkpoint-Computer -RestorePointType 'MODIFY_SETTINGS'
✓ Manual recovery: rstrui.exe or Settings → System → System Restore
```

**To check if restore points were created**:

```powershell
Get-ComputerRestorePoint | Where-Object Description -like "WindowsMaintenance*" | Select-Object SequenceNumber, CreationTime, Description
```

**To manually restore**:

```batch
rstrui.exe
REM Choose the WindowsMaintenance-* restore point and click Restore
```

### Q: What if System Protection is disabled on my PC?

**A**: The script will attempt to enable it automatically. If that fails, maintenance continues without a restore point (non-blocking failure). To manually enable:

```powershell
Enable-ComputerRestore -Drive $env:SystemDrive
```

### Q: Can I customize what maintenance tasks run?

**A**: Yes, edit `config/settings/main-config.json`:

```json
{
  "modules": {
    "skipBloatwareRemoval": false,
    "skipWindowsUpdates": true, // Skip Windows Updates
    "skipTelemetryDisable": false
  }
}
```

### Q: Where are reports stored permanently?

**A**: `C:\ProgramData\WindowsMaintenance\reports\`

- Persistent across reboots
- Not deleted by Windows Temp cleanup
- Searchable via reports-index.json

### Q: Can I run this on a domain-joined PC?

**A**: Yes, but:

- Ensure SYSTEM account has local admin rights
- Group policy may restrict some operations (telemetry disabling)
- Test on a few PCs first

### Q: What if my organization blocks GitHub downloads?

**A**: Pre-download repo and place on network share instead of using auto-update feature.

### Q: Can I run multiple maintenance jobs in parallel?

**A**: Not recommended. System modifications may conflict. Run sequentially once per month.

### Q: How do I know if maintenance completed successfully?

**A**: Check:

1. Report exists in `C:\ProgramData\WindowsMaintenance\reports\`
2. No errors in `temp_files\logs\maintenance.log`
3. System rebooted successfully

### Q: What's the difference between Type1 and Type2 modules?

**A**:

- **Type1 (Audit)**: Read-only detection (no changes to system)
- **Type2 (Execution)**: Modifies system (removes apps, installs updates, etc.)
- Type2 calls Type1 internally to detect before modifying

### Q: How long does maintenance take?

**A**: 10-30 minutes depending on:

- System age and number of packages to remove
- Available updates
- Antivirus scanning delays
- Network connectivity

### Q: Do I need administrator rights?

**A**: Yes, mandatory. Most operations require:

- Registry modifications
- Service management
- Application installation/removal

---

## Support & Additional Resources

### Getting Help

**For Errors**:

1. Check `C:\ProgramData\WindowsMaintenance\logs\maintenance.log`
2. Look up error code in Troubleshooting Guide
3. Contact IT Support with:
   - Error message
   - Last few lines from maintenance.log
   - Windows version and build number

**For Feature Requests**:

- Document desired functionality
- Provide business justification
- Submit to project maintainer

### Documentation

- [ANALYSIS_FINDINGS.md](ANALYSIS_FINDINGS.md) - Detailed analysis of current system
- [RECOMMENDATIONS.md](RECOMMENDATIONS.md) - Proposed improvements
- [IMPLEMENTATION_TIMELINE.md](IMPLEMENTATION_TIMELINE.md) - Project roadmap

---

**Document Version**: 1.0.0  
**Last Updated**: January 29, 2026  
**Next Update**: Post-deployment (feedback-based)
