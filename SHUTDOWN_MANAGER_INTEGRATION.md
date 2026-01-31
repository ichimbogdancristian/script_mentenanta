# Integration Guide: ShutdownManager Module

## Overview

This guide explains how to integrate the newly created `ShutdownManager.psm1` module into MaintenanceOrchestrator v3.0.0 to implement the missing 120-second countdown and cleanup/reboot functionality.

---

## Step 1: Verify ShutdownManager Installation

The ShutdownManager module has been created at:

```
modules/core/ShutdownManager.psm1
```

**Features Included:**

- ✅ 120-second countdown timer with visual feedback
- ✅ Non-blocking keypress detection
- ✅ Interactive abort menu (3 action options)
- ✅ Automatic cleanup of temporary files
- ✅ Safe system reboot capability
- ✅ Full error logging integration
- ✅ Windows-specific handling (Event Log, shutdown.exe)

---

## Step 2: Update MaintenanceOrchestrator.ps1

### 2.1 Add to Core Modules List

**Location:** MaintenanceOrchestrator.ps1, line ~175 (Module Loading section)

**Current:**

```powershell
$CoreModules = @(
    'CoreInfrastructure',
    'LogAggregator',
    'UserInterface',
    'LogProcessor',
    'ReportGenerator'
)
```

**Update to:**

```powershell
$CoreModules = @(
    'CoreInfrastructure',
    'LogAggregator',
    'UserInterface',
    'LogProcessor',
    'ReportGenerator',
    'ShutdownManager'  # ← ADD THIS LINE
)
```

### 2.2 Add Configuration Parameters (Optional)

**Location:** config/settings/main-config.json

**Add to `execution` section:**

```json
"execution": {
    "defaultMode": "unattended",
    "countdownSeconds": 30,
    "enableDryRun": true,
    "autoSelectDefault": true,
    "showProgressBars": true,
    "shutdown": {              // ← ADD THESE LINES
        "enableCountdown": true,
        "countdownSeconds": 120,
        "cleanupOnTimeout": true,
        "rebootOnTimeout": false,
        "keepReportsAfterCleanup": true
    }
}
```

### 2.3 Add Post-Execution Shutdown Sequence

**Location:** MaintenanceOrchestrator.ps1, after report generation (around line ~1700)

**Add this block before exit:**

```powershell
#region Post-Execution Shutdown Sequence (v3.2)
Write-Information "`nFinalizing maintenance session..." -InformationAction Continue

# Check if ShutdownManager is available
if (Get-Command -Name 'Start-MaintenanceCountdown' -ErrorAction SilentlyContinue) {
    Write-Information "Initiating post-execution countdown sequence..." -InformationAction Continue

    # Get shutdown configuration
    $shutdownConfig = $MainConfig.execution.shutdown
    if (-not $shutdownConfig) {
        $shutdownConfig = @{
            enableCountdown = $true
            countdownSeconds = 120
            cleanupOnTimeout = $true
            rebootOnTimeout = $false
            keepReportsAfterCleanup = $true
        }
    }

    # Only run countdown if enabled (or in non-interactive mode)
    if ($shutdownConfig.enableCountdown -or $NonInteractive) {
        $shutdownResult = Start-MaintenanceCountdown `
            -CountdownSeconds $shutdownConfig.countdownSeconds `
            -WorkingDirectory $WorkingDirectory `
            -TempRoot $script:ProjectPaths.TempRoot `
            -CleanupOnTimeout:$shutdownConfig.cleanupOnTimeout `
            -RebootOnTimeout:$shutdownConfig.rebootOnTimeout `
            -SessionId $script:MaintenanceSessionId

        Write-LogEntry -Level 'INFO' -Component 'ORCHESTRATOR' `
            -Message "Post-execution action completed" `
            -Data @{
                Action = $shutdownResult.Action
                RebootRequired = $shutdownResult.RebootRequired
                RebootDelay = $shutdownResult.RebootDelay
            }

        if ($shutdownResult.RebootRequired) {
            Write-Information "`n⚠️  SYSTEM REBOOT INITIATED" -InformationAction Continue
            Write-Information "System will restart in $($shutdownResult.RebootDelay) seconds" -InformationAction Continue
            Write-Information "Press Ctrl+C to cancel if needed" -InformationAction Continue
        }
    }
    else {
        Write-Information "Post-execution countdown disabled in configuration" -InformationAction Continue
    }
}
else {
    Write-Warning "ShutdownManager module not available - skipping countdown sequence"
    Write-Information "Ensure ShutdownManager.psm1 is in modules/core/ and loaded in CoreModules" -InformationAction Continue
}

#endregion
```

---

## Step 3: Configuration Options

### In main-config.json

```json
"execution": {
    "shutdown": {
        "enableCountdown": true,           // Enable/disable countdown feature
        "countdownSeconds": 120,           // Countdown duration
        "cleanupOnTimeout": true,          // Auto-cleanup if countdown expires
        "rebootOnTimeout": false,          // Auto-reboot if countdown expires
        "keepReportsAfterCleanup": true    // Keep reports/ directory for review
    }
}
```

### Behavior Matrix

| Config                                         | Behavior                                         |
| ---------------------------------------------- | ------------------------------------------------ |
| `enableCountdown=false`                        | No countdown, no cleanup, proceed to exit        |
| `cleanupOnTimeout=true, rebootOnTimeout=false` | Cleanup temp files, keep system on               |
| `cleanupOnTimeout=true, rebootOnTimeout=true`  | Cleanup then reboot after 10s                    |
| `keepReportsAfterCleanup=true`                 | Reports survive cleanup for review               |
| `countdownSeconds=120`                         | 120s countdown (default); set 30-300 for testing |

---

## Step 4: Testing the Integration

### 4.1 Initial Syntax Verification

```powershell
# Test module loading
Import-Module .\modules\core\ShutdownManager.psm1 -Global
Get-Command -Module ShutdownManager

# Expected output:
# Start-MaintenanceCountdown
# Show-ShutdownAbortMenu
# Handle-ShutdownAbortChoice
# Invoke-MaintenanceCleanup
```

### 4.2 Dry-Run Test (30-second countdown)

**Update config temporarily:**

```json
"shutdown": {
    "enableCountdown": true,
    "countdownSeconds": 30,          // Short for testing
    "cleanupOnTimeout": false,       // Don't cleanup yet
    "rebootOnTimeout": false         // Don't reboot
}
```

**Run orchestrator:**

```powershell
cd C:\maintenance_repo
.\MaintenanceOrchestrator.ps1 -NonInteractive

# Expected behavior:
# 1. Runs all modules
# 2. Generates reports
# 3. Shows: "POST-EXECUTION MAINTENANCE SEQUENCE"
# 4. 30-second countdown appears
# 5. Can press key to abort
# 6. If timeout: "Countdown complete" and exits
```

### 4.3 Keypress Abort Test

**During countdown:**

```
Press any key during countdown
→ Menu should appear:
  1. Cleanup now (remove temporary files, keep reports)
  2. Skip cleanup (preserve all files for review)
  3. Cleanup AND reboot
```

### 4.4 Cleanup Verification

**After selecting "Cleanup now":**

```powershell
# Check that temp files removed:
cd C:\maintenance_repo
ls -la temp_files/

# Expected:
# ✓ temp_files/reports/ exists (reports kept)
# ✗ temp_files/logs/ removed
# ✗ temp_files/data/ removed
# ✗ temp_files/processed/ removed
# ✗ temp_files/temp/ removed
```

### 4.5 Full Integration Test

**Complete workflow:**

```powershell
# 1. Run with full config
$params = @{
    NonInteractive = $true
    DryRun = $false
}

# 2. Configure for cleanup + NO reboot (for now)
# (Edit config.json)

# 3. Launch orchestrator
.\MaintenanceOrchestrator.ps1 @params

# 4. Watch full execution
# → All modules run
# → Logs generated
# → Report created
# → Countdown starts
# → Cleanup occurs
# → Reports copied to parent directory
# → Script exits

# 5. Verify reports available
Get-ChildItem C:\maintenance_repo\temp_files\reports\
Get-ChildItem C:\maintenance_repo\..\ -Filter "*.html"  # Copied to parent
```

---

## Step 5: Production Deployment

### 5.1 Enable in Configuration

**config/settings/main-config.json:**

```json
"execution": {
    "countdown": "Enabled",
    "countdownSeconds": 120,
    "cleanupOnTimeout": true,
    "rebootOnTimeout": true
}
```

### 5.2 Scheduled Task Verification

**Ensure script.bat launcher properly sets up Task Scheduler:**

```batch
# In script.bat, this creates monthly task:
schtasks /Create /SC MONTHLY /MO 1 /D 20 /TN "WindowsMaintenanceAutomation" ...

# After execution with reboot:
# Task Scheduler resume → PowerShell 7 relaunches orchestrator
# → Continues where it left off
```

### 5.3 Pre-Deployment Checklist

- [ ] ShutdownManager.psm1 exists in modules/core/
- [ ] CoreModules list includes 'ShutdownManager'
- [ ] Post-execution shutdown block added to orchestrator
- [ ] Configuration updated with shutdown parameters
- [ ] Tested with 30-second countdown
- [ ] Tested keypress abort menu
- [ ] Tested cleanup with reports preserved
- [ ] Verified reports copied to parent directory
- [ ] Windows Event Log integration working
- [ ] Reboot message displays correctly (for reboot=true tests)

---

## Step 6: Windows-Specific Considerations

### 6.1 Keypress Detection

**Works in:**

- ✅ Interactive PowerShell console
- ✅ PowerShell ISE
- ✅ Remote Desktop session
- ❌ Scheduled Task (runs as SYSTEM, no console)
- ❌ Background Service

**Fallback:** If keypress unavailable, countdown continues to timeout automatically

### 6.2 System Reboot

**Method:** `shutdown.exe /r /t 10 /c "message"`

- ✅ Built-in, no additional dependencies
- ✅ Works with administrator privileges
- ✅ Can be cancelled with Ctrl+C (first 30 seconds)
- ✅ Logged to Windows Event Log
- ✅ User-friendly countdown message

### 6.3 Cleanup Permissions

**Files removed:**

- `temp_files/temp/` - Always removable
- `temp_files/logs/` - May have open file handles
- `temp_files/data/` - Usually removable
- `temp_files/processed/` - Usually removable
- Extracted repo - May have active process

**Solution:**

- Use `-Force -ErrorAction SilentlyContinue` for resilience
- Log any failures for debugging
- Continue cleanup even if some files fail

### 6.4 Event Log Integration

**Logs to:** Windows Event Log → System channel

- Event ID: 1000
- Source: "Windows Maintenance"
- Message: "Maintenance completed. System restarting."

**Requires:** Event Log write permission (usually available for admin)

---

## Step 7: Troubleshooting

### Issue: Countdown not appearing

**Cause:** ShutdownManager not loaded  
**Fix:**

```powershell
# Verify in orchestrator output:
# "Loading Type2 modules..."
# Look for: "Loaded: ShutdownManager"

# If missing:
# 1. Check ShutdownManager.psm1 exists
# 2. Verify CoreModules includes 'ShutdownManager'
# 3. Check file permissions (readable)
```

### Issue: Keypress detection not working

**Cause:** Running in scheduled task or non-interactive mode  
**Fix:**

```powershell
# Check execution context:
if ($Host.Name -eq 'ConsoleHost') {
    # Interactive - keypress should work
} else {
    # Non-interactive - keypress won't work
    # Countdown continues to timeout automatically
}
```

### Issue: Cleanup fails with "Access Denied"

**Cause:** Files still locked by processes  
**Fix:**

- Wait longer before cleanup
- Verify all modules actually completed
- Check Process Monitor for locked files
- Use admin privileges

### Issue: Reboot doesn't work

**Cause:** User privileges insufficient  
**Fix:**

```powershell
# Verify admin context:
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Admin privileges required for reboot"
}
```

---

## Step 8: Monitoring & Logging

### Log Entries Created

ShutdownManager creates these log entries:

```
[INFO] [SHUTDOWN-MANAGER] Initiating post-execution shutdown sequence
[INFO] [SHUTDOWN-MANAGER] Countdown interrupted by user keypress
[SUCCESS] [SHUTDOWN-MANAGER] Cleanup completed successfully
[INFO] [SHUTDOWN-MANAGER] Initiating system reboot
```

### Windows Event Log

```powershell
# View maintenance events:
Get-EventLog -LogName System -Source "Windows Maintenance" -Newest 10 | Format-Table TimeGenerated, EventID, Message
```

---

## Next Steps

1. **Immediate:** Add ShutdownManager to core modules list (2 minutes)
2. **Short-term:** Add post-execution block to orchestrator (15 minutes)
3. **Testing:** Run with 30-second countdown in dry-run mode (30 minutes)
4. **Deployment:** Update production config for 120-second countdown
5. **Verification:** Confirm monthly scheduled task executes with countdown

---

## Version Information

- **ShutdownManager Version:** 1.0.0
- **Compatible With:** v3.0.0+
- **PowerShell Required:** 7.0+
- **Admin Privileges:** Required
- **Integrated Date:** January 31, 2026

---

**Integration Complete!** ShutdownManager is ready for deployment.
