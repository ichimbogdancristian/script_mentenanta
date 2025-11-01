# System Protection & Restore Point Implementation

**Date:** November 1, 2025  
**Status:** ✅ Complete and Deployed

## Overview

Added automatic System Protection verification, enablement, and restore point creation to the Windows Maintenance Automation script. The system now verifies System Protection status at startup and attempts to enable it if disabled.

## Changes Made

### 1. CoreInfrastructure.psm1 - New Function

Added `Enable-SystemProtectionAndRestorePoint` function with the following capabilities:

**Status Checking:**
- Verifies System Protection via WMI (Win32_SystemRestore)
- Fallback registry check (DisableSR registry value)
- Detects current enable/disable state

**Enable Methods (Priority Order):**
1. **PowerShell Cmdlet** - `Enable-ComputerRestore` (most reliable)
2. **Registry Configuration** - Sets `DisableSR = 0` in registry
3. **VSS Service** - Starts Volume Shadow Copy Service if stopped

**Restore Point Creation Methods:**
1. **COM Object** - System.Restoration.SystemRestore COM interface
2. **WMIC** - `wmic.exe os call CreateRestorePoint` as fallback

**Return Value:**
```powershell
@{
    Success                  = [bool]          # Overall success status
    IsEnabled                = [bool]          # System Protection enabled
    RestorePointCreated      = [bool]          # Restore point created
    RestorePointId           = [object|null]   # Restore point identifier if created
    Message                  = [string]        # Detailed status message
    ProtectionEnableMethod   = [string]        # Method used: "PowerShell-EnableComputerRestore", "Registry-DisableSR", "None"
}
```

### 2. MaintenanceOrchestrator.ps1 - Integration

Added new execution phase after system readiness check:

```
1. System Readiness Check
2. [NEW] Enable System Protection & Create Restore Point
3. Initialize Global Path Discovery
4. Load Modules
5. Execute Tasks
```

**Output Examples:**
```
Ensuring System Protection is enabled...
   ✓ System Protection enabled
   ✓ Restore point created successfully
   Enable method: Registry-DisableSR
```

or

```
Ensuring System Protection is enabled...
   Could not enable System Protection: [error message]
   Continuing with maintenance (restore point unavailable)...
```

### 3. Error Handling

- **Graceful Degradation**: Maintenance continues if System Protection cannot be enabled
- **Multiple Fallback Methods**: If one method fails, automatically tries next method
- **Verbose Logging**: Can enable with `-Verbose` flag to troubleshoot enable attempts
- **Non-Destructive**: Safe to run multiple times - checks before modifying

## Usage

### Automatic (Default)

System Protection verification and enablement runs automatically when MaintenanceOrchestrator.ps1 is executed:

```powershell
.\MaintenanceOrchestrator.ps1
```

### Manual Function Call

```powershell
Import-Module .\modules\core\CoreInfrastructure.psm1 -Force -Global

# Run the function
$result = Enable-SystemProtectionAndRestorePoint

# Check results
if ($result.Success) {
    Write-Host "System Protection is enabled"
    if ($result.RestorePointCreated) {
        Write-Host "Restore point created"
    }
}
else {
    Write-Host "Could not enable System Protection: $($result.Message)"
}
```

### With Verbose Output

```powershell
Enable-SystemProtectionAndRestorePoint -Verbose
```

## Technical Details

### Registry Modification
- **Path**: `HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore`
- **Value**: `DisableSR` (REG_DWORD)
- **Setting**: `0` = Enabled, `1` = Disabled

### COM Object Used
- **ProgID**: `System.Restoration.SystemRestore`
- **Method**: `CreateRestorePoint(description, restorePointType, eventType)`

### Restore Point Description
Format: `WindowsMaintenance-YYYYMMDD-HHmmss`
Example: `WindowsMaintenance-20251101-144530`

## System Requirements

- **OS**: Windows 7 or later (Vista+ for registry method)
- **Privileges**: Administrator
- **Services**: VSS (Volume Shadow Copy Service)
- **Disk Space**: At least 300MB for first restore point, ~100MB each additional

## Known Limitations

1. **Registry-only enablement**: Registry modification alone doesn't create snapshots immediately
   - Full enablement requires system service restart
   - VSS service needs to be running
   - May require system restart for full functionality

2. **WMIC Deprecation**: Microsoft is deprecating WMIC
   - COM method is preferred for future compatibility
   - WMIC kept as fallback for older systems

3. **Restore Point Timing**: 
   - First restore point may take a few seconds to appear
   - Requires VSS service to be running
   - Shadow storage must be allocated on the volume

## Troubleshooting

### "Access Denied" Error
- **Cause**: May occur even with admin privileges if UAC is actively restricting
- **Solution**: Restart PowerShell as Administrator, or disable UAC temporarily

### Restore Point Not Created
- **Cause**: VSS service not running, or shadow storage not allocated
- **Solutions**:
  1. Check VSS service: `Get-Service VSS | Start-Service`
  2. Check shadow storage: `vssadmin list shadowstorage`
  3. Allocate storage: `vssadmin resize shadowstorage`

### Registry Method Fails
- **Cause**: Registry path doesn't exist or insufficient permissions
- **Solution**: Ensure admin privileges, check registry permissions with regedit

## Future Enhancements

- [ ] Add Group Policy configuration method for domain-managed systems
- [ ] Schedule automatic restore point creation (daily, before updates)
- [ ] Export restore point list for reporting
- [ ] Add restore point rollback capability
- [ ] Monitor shadow storage usage and warn if low

## Testing

Tested with:
- ✅ PowerShell 7.5.4
- ✅ Windows with Admin privileges
- ✅ Registry modification fallback
- ✅ Multiple function calls (safe re-run)

## References

- [Enable-ComputerRestore Documentation](https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.management/enable-computerrestore)
- [Win32_SystemRestore Class](https://docs.microsoft.com/en-us/windows/win32/cimwin32prov/win32-systemrestore)
- [VSS Administration](https://docs.microsoft.com/en-us/windows-server/administration/windows-commands/vssadmin)
- [System Restore API](https://docs.microsoft.com/en-us/windows/win32/api/srrestoreptapi/ns-srrestoreptapi-restorepointinfoa)

## Commits

- **Commit**: `4ee0011` - feat: Add automatic System Protection and restore point creation
- **Date**: November 1, 2025
- **Files Modified**: 2
  - `MaintenanceOrchestrator.ps1`
  - `modules/core/CoreInfrastructure.psm1`
