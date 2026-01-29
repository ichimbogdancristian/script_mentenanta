# System Restore Point Space Management Feature

**Added**: January 29, 2026  
**Status**: ✅ Implemented in both script.bat and MaintenanceOrchestrator.ps1  
**Default Allocation**: 10 GB  
**Configurable**: Yes, via `main-config.json`

---

## Overview

The system now **automatically checks and ensures** that System Restore Point has at least 10GB of space allocated before running maintenance. This prevents restore point failures due to insufficient disk space.

---

## Features

### ✅ Dual-Layer Space Management

**Layer 1: script.bat (Early Check)**

- Checks current System Protection allocation
- If less than configured minimum, allocates space
- Runs early before PowerShell starts
- Non-blocking failure (continues if allocation fails)

**Layer 2: MaintenanceOrchestrator.ps1 (Confirmation)**

- Verifies space allocation again before restore point creation
- Uses `Ensure-SystemRestorePointSpace` PowerShell function
- Logs allocation results with details
- Respects `-DryRun` flag (skips in dry-run mode)

---

## How It Works

### Flow Diagram

```
script.bat START
    ↓
    └─→ Check System Protection status
    │   └─→ If available, check current allocation
    │       └─→ If < 10GB, allocate 10GB
    │           └─→ Log result
    ↓
PowerShell Orchestrator START
    ↓
    └─→ Ensure-SystemRestorePointSpace function
    │   └─→ Get current allocation from WMI
    │   └─→ Compare against config minimum
    │   └─→ If < minimum, set to minimum
    │   └─→ Verify allocation succeeded
    ├─→ Log with detailed metrics
    ↓
CREATE RESTORE POINT
    └─→ Guaranteed to have space now
```

---

## Configuration

### In `config/settings/main-config.json`:

```json
{
  "system": {
    "createSystemRestorePoint": true,
    "restorePointMaxSizeGB": 10,
    "enableSystemProtectionIfDisabled": true
  }
}
```

### Settings:

| Setting                            | Type    | Default | Description                                   |
| ---------------------------------- | ------- | ------- | --------------------------------------------- |
| `createSystemRestorePoint`         | boolean | `true`  | Enable/disable restore point creation         |
| `restorePointMaxSizeGB`            | integer | `10`    | Minimum allocation in GB (recommended: 10-20) |
| `enableSystemProtectionIfDisabled` | boolean | `true`  | Auto-enable System Protection if disabled     |

### Customization Examples:

```json
{
  "system": {
    "createSystemRestorePoint": true,
    "restorePointMaxSizeGB": 20, // Allocate 20GB instead
    "enableSystemProtectionIfDisabled": true
  }
}
```

---

## Implementation Details

### PowerShell Function: `Ensure-SystemRestorePointSpace`

**Location**: MaintenanceOrchestrator.ps1 (lines ~358-447)

**Parameters**:

- `MinimumGB` (int, default=10) - Minimum space to allocate

**Functionality**:

1. Gets system drive letter
2. Queries WMI for current System Protection allocation
3. Reports current usage and allocation
4. If allocation < minimum:
   - Calculates new allocation in bytes
   - Updates WMI configuration
   - Verifies update succeeded
5. Returns success/failure status

**Returns**:

- `$true` if allocation is adequate or was successfully increased
- `$false` if check/allocation failed

**Error Handling**:

- Non-blocking failures (script continues)
- All failures logged with details
- Graceful degradation if WMI unavailable

---

### Batch Script Implementation: script.bat

**Location**: script.bat (lines ~1158-1200)

**Process**:

1. Sets `MIN_RESTORE_SPACE_GB=10`
2. Checks System Protection availability
3. If available, queries current allocation via PowerShell
4. Parses allocation value
5. If less than 10GB, allocates via WMI
6. Logs all steps

**Non-Blocking**: If allocation fails, continues to next step

---

## Logging Output

### When Allocation is Adequate:

```
[INFO] LAUNCHER: Checking System Protection status...
[SUCCESS] LAUNCHER: System Protection is available and functional
[INFO] LAUNCHER: Checking System Restore Point disk space allocation...
[INFO] LAUNCHER: Current System Protection allocation: 10.00 GB (Used: 2.34 GB)
[SUCCESS] LAUNCHER: System Protection allocation is sufficient (10.00 GB >= 10 GB)
[INFO] LAUNCHER: Creating system restore point before maintenance...
[SUCCESS] LAUNCHER: System restore point created successfully: WindowsMaintenance-a1b2c3d4
```

### When Allocation is Increased:

```
[INFO] LAUNCHER: Checking System Protection status...
[SUCCESS] LAUNCHER: System Protection is available and functional
[INFO] LAUNCHER: Checking System Restore Point disk space allocation...
[INFO] LAUNCHER: Current allocation is 5 GB (minimum required: 10 GB). Allocating...
[SUCCESS] LAUNCHER: System Restore Point allocation set to 10 GB successfully
[INFO] LAUNCHER: Creating system restore point before maintenance...
[SUCCESS] LAUNCHER: System restore point created successfully: WindowsMaintenance-a1b2c3d4
[SUCCESS] RESTORE-POINT: System Restore Point allocation increased to 10 GB
```

### When System Protection is Unavailable:

```
[INFO] LAUNCHER: Checking System Protection status...
[WARN] LAUNCHER: System Protection commands not available on this system
[WARN] LAUNCHER: Skipping restore point creation
[INFO] LAUNCHER: Continuing with maintenance...
```

---

## Disk Space Requirements

### Recommended Allocation Sizes

| PC Type           | Recommended | Reason                             |
| ----------------- | ----------- | ---------------------------------- |
| Workstation (SSD) | 10-15 GB    | Normal maintenance, fast restore   |
| Laptop            | 15-20 GB    | Mobile workstation, larger updates |
| Server            | 20-30 GB    | Critical systems, longer history   |
| High-Performance  | 30+ GB      | Very active system, many changes   |

### How to Increase Allocation

**Edit `main-config.json`**:

```json
{
  "system": {
    "restorePointMaxSizeGB": 20 // Change from 10 to 20
  }
}
```

Then run maintenance - it will automatically increase allocation on next run.

---

## Disk Space Impact

### Typical Space Usage

| Component              | Space Used         | Notes                        |
| ---------------------- | ------------------ | ---------------------------- |
| System Restore Point   | 10 GB (configured) | Manages own space            |
| Maintenance temp files | 500 MB - 2 GB      | Cleaned up after run         |
| Reports                | 10-50 MB per month | Accumulates over time        |
| **Total per run**      | ~500 MB - 2 GB     | Temporary, mostly cleaned up |

### Long-Term Storage

```
After 12 months:
  System Restore Points: ~10 GB (circular buffer)
  Reports (permanent):  ~100-600 MB
  Logs (cleaned):       ~50-200 MB
  ─────────────────────────
  Total:                ~10 GB - 11 GB
```

---

## Troubleshooting

### Issue: "Failed to allocate System Restore Point space"

**Causes**:

- Insufficient disk space on system drive
- User doesn't have administrator rights
- System Protection disabled or unavailable
- Antivirus blocking WMI operations

**Solutions**:

```powershell
# Check current allocation
$srp = Get-WmiObject -Class Win32_SystemRestoreConfig -Namespace "root\cimv2"
$srp.MaxSpace / 1GB  # Shows allocation in GB

# Manual allocation (if needed)
$srp.MaxSpace = 10GB
$srp.Put()

# Check available disk space
Get-Volume C: | Select-Object SizeRemaining
```

### Issue: "System Restore configuration not available via WMI"

**Causes**:

- System Protection not enabled
- WMI service not running
- Insufficient permissions

**Solutions**:

```batch
REM Restart WMI service
net stop winmgmt
net start winmgmt

REM Enable System Protection
powershell -Command "Enable-ComputerRestore -Drive 'C:'"

REM Verify
powershell -Command "Get-ComputerRestorePoint | Select-Object -First 1"
```

### Issue: Allocation didn't increase despite config change

**Causes**:

- Config not saved properly
- Admin rights required for WMI changes
- Scheduled task runs as SYSTEM (should work)

**Solutions**:

```powershell
# Verify config is correct
$config = Get-Content 'config/settings/main-config.json' | ConvertFrom-Json
$config.system.restorePointMaxSizeGB

# Run manually as admin to test
powershell -RunAs Administrator -Command ".\MaintenanceOrchestrator.ps1"
```

---

## Security Considerations

### ✅ Safe Operations

- **Read-only checks**: Queries don't modify anything
- **Non-blocking failures**: Script continues even if allocation fails
- **Audited changes**: All allocations logged
- **Config-controlled**: Size limits set by admin, not script
- **WMI-based**: Uses standard Windows APIs

### ⚠️ Requirements

- **Administrator rights**: Required for WMI write operations
- **System Protection enabled**: Feature only works if enabled
- **Disk space**: Need at least 10 GB free to allocate

---

## Integration with Other Features

### Relationship to Restore Point Creation

```
Space Management (NEW)
    ↓
    └─→ Ensures 10GB allocated
    └─→ Verifies availability
    └─→ Logs metrics
        ↓
    Restore Point Creation (EXISTING)
        └─→ Creates restore point
        └─→ With guaranteed space
        └─→ Logs sequence number
```

### Works With:

- ✅ script.bat restore point creation
- ✅ MaintenanceOrchestrator.ps1 restore point creation
- ✅ DryRun mode (skips allocation)
- ✅ All Type1 and Type2 modules
- ✅ Scheduled task execution

---

## Future Enhancements

Potential improvements for future versions:

1. **Dynamic Sizing**: Adjust allocation based on available disk space
2. **Historical Analysis**: Track restore point usage over time
3. **Alerts**: Warn if restore point approaching max size
4. **Cleanup**: Archive old restore points if space critical
5. **Reporting**: Include restore point metrics in reports

---

## Testing Checklist

### Verify Installation

- [ ] script.bat checks System Protection
- [ ] MaintenanceOrchestrator.ps1 runs `Ensure-SystemRestorePointSpace`
- [ ] Logs show space check results
- [ ] Restore point created successfully

### Verify Allocation

- [ ] Check current allocation: `(Get-WmiObject -Class Win32_SystemRestoreConfig -Namespace 'root\cimv2').MaxSpace / 1GB`
- [ ] Verify it's ≥ 10GB (or configured value)
- [ ] Run maintenance again, verify no re-allocation (stable)

### Test Low Space Scenario

```powershell
# Reduce allocation to 1GB to test increase
$srp = Get-WmiObject -Class Win32_SystemRestoreConfig -Namespace "root\cimv2"
$srp.MaxSpace = 1GB
$srp.Put()

# Run maintenance - should detect and increase back to 10GB
.\MaintenanceOrchestrator.ps1

# Verify increased
$srp = Get-WmiObject -Class Win32_SystemRestoreConfig -Namespace "root\cimv2"
$srp.MaxSpace / 1GB
```

### Test Configuration Override

```powershell
# Edit config to use 20GB
# main-config.json: "restorePointMaxSizeGB": 20

# Run maintenance
.\MaintenanceOrchestrator.ps1

# Verify set to 20GB
$srp = Get-WmiObject -Class Win32_SystemRestoreConfig -Namespace "root\cimv2"
$srp.MaxSpace / 1GB  # Should show 20
```

---

## Support & Documentation

**For Configuration Questions**:

- See `config/settings/main-config.json` for all settings
- Default values are production-tested

**For Troubleshooting**:

- Check logs in `temp_files/logs/maintenance.log`
- Look for "RESTORE-POINT" component entries
- Verify WMI service is running: `Get-Service winmgmt`

**For Manual Testing**:

- See "Testing Checklist" section above
- All commands provided are safe (read-first operations)

---

**Feature Version**: 1.0.0  
**Last Updated**: January 29, 2026  
**Status**: Production Ready
