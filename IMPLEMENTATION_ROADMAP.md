# 🎯 Implementation Roadmap - Next Steps

**Audience:** Developer continuing this project  
**Timeframe:** Phased implementation over 2-3 weeks  
**Goal:** Fix broken modules → Consolidate → Enhance → Optimize

---

## PHASE 1: IMMEDIATE FIX (Week 1 - 3 hours)

### 1.1 Create Missing Baseline Files

**Status:** Blocking modules #2, #3, #4, #5, #7

Create these 6 files with initial content:

```bash
# Essential Apps baseline
mkdir -p config/lists/essential-apps
cat > config/lists/essential-apps/essential-apps.json << 'EOF'
{
  "_comment": "Essential applications to install if not already present",
  "common": {
    "apps": []
  },
  "windows11": {
    "apps": []
  },
  "windows10": {
    "apps": []
  }
}
EOF

# App Upgrade baseline
mkdir -p config/lists/app-upgrade
cat > config/lists/app-upgrade/app-upgrade-list.json << 'EOF'
{
  "_comment": "Applications to check for upgrades",
  "common": {
    "apps": []
  }
}
EOF

# Security baseline
mkdir -p config/lists/security
cat > config/lists/security/security-baseline.json << 'EOF'
{
  "_comment": "Security hardening baseline",
  "registry": [],
  "windowsDefender": {
    "realTimeProtection": true,
    "cloudProtection": true,
    "networkProtection": true,
    "pua": true
  }
}
EOF

# Telemetry baseline
mkdir -p config/lists/telemetry
cat > config/lists/telemetry/telemetry-list.json << 'EOF'
{
  "_comment": "Telemetry services and tasks to disable",
  "services": {
    "disable": []
  },
  "registry": {
    "telemetry": [],
    "advertising": [],
    "cortana": [],
    "privacy": []
  },
  "scheduledTasks": {
    "disable": []
  }
}
EOF

# System Optimization baseline
mkdir -p config/lists/system-optimization
cat > config/lists/system-optimization/system-optimization-config.json << 'EOF'
{
  "_comment": "System optimization baseline",
  "common": {
    "services": {
      "safeToDisable": []
    },
    "powerPlan": {
      "defaultPlan": "High performance"
    }
  },
  "windows11": {
    "services": {
      "safeToDisable": []
    }
  },
  "windows10": {
    "services": {
      "safeToDisable": []
    }
  }
}
EOF

# Windows Updates baseline
mkdir -p config/lists/windows-updates
cat > config/lists/windows-updates/updates-list.json << 'EOF'
{
  "_comment": "Windows Updates (primarily uses Windows Update API, this is for reference)"
}
EOF
```

### 1.2 Test All Modules

```powershell
# Run full maintenance cycle
./script.bat

# Expected output in Stage 1:
# ✓ BloatwareDetectionAudit (should find items or report 0)
# ✓ EssentialAppsAudit (should now work, may find 0 items with empty baseline)
# ✓ SecurityAudit (should now work)
# ✓ TelemetryAudit (should now work)
# ✓ SystemOptimizationAudit (should now work)
# ✓ WindowsUpdatesAudit (should work as before)
# ✓ AppUpgradeAudit (should now work)
# ✓ DiskCleanupAudit (should work as before)
# ✓ SystemInventory (should work as before)

# Check HTML report:
# - All 9 modules should appear in Stage 1
# - All 8 actionable modules should show in Stage 2
# - No modules should show "Baseline not found" errors
```

---

## PHASE 2: CONSOLIDATION (Week 1-2 - 5.5 hours)

### 2.1 Security + Telemetry → SystemHardening (3 hours)

**Step 1: Create SecurityAudit → SystemHardeningAudit**

Copy and merge:
```powershell
# modules/type1/SystemHardeningAudit.psm1
# Start with SecurityAudit.psm1 content
# Add: Telemetry audit logic at the end
# Modify: Load BOTH baselines
$securityBaseline = Get-BaselineList -ModuleFolder 'security' -FileName 'security-baseline.json'
$telemetryBaseline = Get-BaselineList -ModuleFolder 'telemetry' -FileName 'telemetry-list.json'

# Add Type field to distinguish items in diff:
$securityItem | Add-Member -Type NoteProperty -Name 'HardeningType' -Value 'security'
$telemetryItem | Add-Member -Type NoteProperty -Name 'HardeningType' -Value 'telemetry'

# Save single diff:
Save-DiffList -ModuleName 'SystemHardening' -DiffList $diff.ToArray()
```

**Step 2: Create SecurityEnhancement + TelemetryDisable → SystemHardening (Type2)**

```powershell
# modules/type2/SystemHardening.psm1
function Invoke-SystemHardening {
    param([Parameter()][hashtable]$OSContext)
    
    $diff = Get-DiffList -ModuleName 'SystemHardening'
    
    $processed = 0; $failed = 0; $errors = @(); $rebootRequired = $false
    
    foreach ($item in $diff) {
        $type = $item.HardeningType ?? 'security'
        
        try {
            if ($type -eq 'security') {
                # Process security items (registry, defender)
                if ($item.Type -eq 'registry') {
                    Invoke-RegistryChangeItem -Item $item -Component 'HARDENING'
                } elseif ($item.Type -eq 'defender') {
                    # Defender logic from SecurityEnhancement
                }
            } elseif ($type -eq 'telemetry') {
                # Process telemetry items (services, tasks, registry)
                if ($item.Type -eq 'service') {
                    Invoke-ServiceChangeItem -Item $item -Component 'HARDENING'
                } elseif ($item.Type -eq 'scheduledtask') {
                    Disable-ScheduledTask ...
                }
            }
            $processed++
        } catch {
            $failed++; $errors += "[$($item.Name)] $_"
        }
    }
    
    return New-ModuleResult -ModuleName 'SystemHardening' -Status ... `
        -ItemsProcessed $processed -ItemsFailed $failed -ExtraData @{ RebootRequired = $rebootRequired }
}
```

**Step 3: Update MaintenanceOrchestrator.ps1**

Replace two entries:
```powershell
# OLD:
@{ Num = 3; Label = 'Security Enhancement'; DiffKey = 'SecurityEnhancement'; ... },
@{ Num = 4; Label = 'Telemetry & Privacy'; DiffKey = 'TelemetryDisable'; ... },

# NEW:
@{ Num = 3; Label = 'System Hardening (Security & Privacy)'; DiffKey = 'SystemHardening'; 
  Type1File = 'modules\type1\SystemHardeningAudit.psm1'
  Type1Func = 'Invoke-SystemHardeningAudit'
  Type2File = 'modules\type2\SystemHardening.psm1'
  Type2Func = 'Invoke-SystemHardening'
  ConfigSkip = 'skipSystemHardening' },
```

**Step 4: Update config files**

```json
// main-config.json - replace:
"skipSecurityEnhancement": false,
"skipTelemetryDisable": false,

// WITH:
"skipSystemHardening": false,
```

**Step 5: Verify and test**

```powershell
./script.bat
# Module count goes from 9 → 8 in Stage 1 menu
# Module #3 now shows: "System Hardening (Security & Privacy)"
# HTML report shows single card with both security + telemetry results
```

### 2.2 EssentialApps + AppUpgrade → AppManagement (2.5 hours)

**Similar process:**

**Create modules/type1/AppManagementAudit.psm1**
```powershell
# Load both baselines:
$essentialBaseline = Get-BaselineList -ModuleFolder 'essential-apps' -FileName 'essential-apps.json'
$upgradeBaseline = Get-BaselineList -ModuleFolder 'app-upgrade' -FileName 'app-upgrade-list.json'

# Single app enumeration (expensive operation):
$installedApps = Get-InstalledApp  # Called ONCE

# Check missing essentials:
foreach ($app in $essentialBaseline.common.apps) {
    if (-not ($installedApps | Where-Object { $_.Name -like "*$app*" })) {
        $diff.Add(@{ Type = 'install'; Name = $app; ... })
    }
}

# Check outdated apps:
$wingetUpgrades = Get-WingetUpgrade  # Get upgrade list once
foreach ($app in $upgradeBaseline.common.apps) {
    if ($upgrade = $wingetUpgrades | Where-Object { $_.Name -eq $app -and $_.Upgrade -gt 1 }) {
        $diff.Add(@{ Type = 'upgrade'; Name = $app; Version = $upgrade.Version; ... })
    }
}

Save-DiffList -ModuleName 'AppManagement' -DiffList $diff.ToArray()
```

**Create modules/type2/AppManagement.psm1**
```powershell
# Process Type = 'install' items:
foreach ($item in @($diff | Where-Object { $_.Type -eq 'install' })) {
    # winget install ...
}

# Process Type = 'upgrade' items:
foreach ($item in @($diff | Where-Object { $_.Type -eq 'upgrade' })) {
    # winget upgrade ...
}
```

**Update MaintenanceOrchestrator.ps1**
```powershell
# Merge module pair #2 and #7 into single entry
@{ Num = 2; Label = 'Application Management'; DiffKey = 'AppManagement'; ... }

# Remove old #7 entry (AppUpgrade)
# Renumber remaining modules (WindowsUpdates becomes #6, etc.)
```

---

## PHASE 3: CODE CLEANUP (Week 2 - 1.5 hours)

### 3.1 Remove DiskCleanup Snapshot Write

**File:** modules/type1/DiskCleanupAudit.psm1
**Lines:** 176-178 (remove these 3 lines)

```powershell
# REMOVE:
$auditPath = Get-TempPath -Category 'data' -FileName 'disk-cleanup-audit.json'
@{ Timestamp = (Get-Date -Format 'o'); Candidates = $diff.ToArray(); EstimatedTotalMB = $totalMB } `
| ConvertTo-Json -Depth 8 | Set-Content -Path $auditPath -Encoding UTF8 -Force

# The diff list itself (already saved) is sufficient.
# This snapshot was never used downstream.
```

### 3.2 Add Comment to script.bat PATH Refresh

**File:** script.bat
**Location:** Lines 47-78
**Add comment block:**

```batch
REM ─── CRITICAL PATH REFRESH LOGIC ───────────────────────────────────────────────────
REM When REG QUERY returns REG_EXPAND_SZ values, they contain literal tokens like %SystemRoot%.
REM Plain SET ("SET PATH=...") stores these tokens verbatim, silently corrupting PATH.
REM CALL SET (calling SET a second time) forces PowerShell-style token expansion, so the
REM final PATH contains actual paths like C:\Windows\System32 instead of literal %SystemRoot%.
REM
REM This is necessary because:
REM 1. Registry tokens like %SystemRoot% aren't expanded by REG QUERY itself
REM 2. cmd.exe's normal SET doesn't expand AFTER reading from registry
REM 3. Many downstream tools will fail if they find literal "%SystemRoot%" in PATH
REM ─────────────────────────────────────────────────────────────────────────────────────
```

### 3.3 Consolidate Logging Level Definitions

**File:** modules/core/Maintenance.psm1

Add validation:
```powershell
function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('INFO', 'WARN', 'ERROR', 'DEBUG', 'SUCCESS')]  # Already exists
        [string]$Level,
        ...
    )
    # Good: Prevents invalid log levels at call site
}
```

---

## PHASE 4: ENHANCEMENT (Week 2-3 - 6-8 hours)

### 4.1 BloatwareRemoval: Add Pre-Removal Validation

**File:** modules/type2/BloatwareRemoval.psm1

```powershell
# Before AppX removal:
function Test-ProcessRunning {
    param([string]$PackageName)
    $procName = $PackageName -replace '[^a-zA-Z0-9]', ''
    Get-Process | Where-Object { $_.ProcessName -like "*$procName*" }
}

# In main loop:
foreach ($item in $diff) {
    ...
    if ($pkg) {
        # Check if running
        $runningProc = Test-ProcessRunning -PackageName $pkgName
        if ($runningProc) {
            Write-Log -Level WARN -Component BLOATWARE -Message "Process running: $($runningProc.Name). Attempting graceful termination..."
            try {
                $runningProc | Stop-Process -Force -ErrorAction Stop
                Start-Sleep -Milliseconds 500
            } catch {
                Write-Log -Level WARN -Component BLOATWARE -Message "Could not terminate process: $_"
            }
        }
        
        # Remove AppX
        Remove-AppxPackageCompat -PackageFullName $_.PackageFullName -AllUsers
        
        # Verify removal
        $stillPresent = Get-AppxPackageCompat -Name "*$pkgName*"
        if ($stillPresent) {
            Write-Log -Level WARN -Component BLOATWARE -Message "App still present after removal (protected?): $pkgName"
        }
    }
}
```

### 4.2 SecurityEnhancement (→ SystemHardening): Export Pre-Hardening State

**File:** modules/type2/SystemHardening.psm1

```powershell
# Before making changes:
$preHardeningState = @{
    Timestamp = Get-Date -Format 'o'
    DefenderPreferences = Get-MpPreference | Select-Object *
    FirewallProfiles = Get-NetFirewallProfile | Select-Object *
    ImportantRegistryKeys = @()  # Selectively export critical keys
}

# Save backup
$backupPath = Get-TempPath -Category 'data' -FileName "hardening-pre-state-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
$preHardeningState | ConvertTo-Json -Depth 10 | Set-Content -Path $backupPath -Encoding UTF8 -Force
Write-Log -Level INFO -Component HARDENING -Message "Pre-hardening state saved: $backupPath"
```

### 4.3 DiskCleanup: Add Space Reclamation Breakdown

**File:** modules/type2/DiskCleanup.psm1

```powershell
# Track reclamation by category:
$reclaimedByCategory = @{
    'temp' = 0
    'browser-cache' = 0
    'browser-cookies' = 0
    'update-cleanup' = 0
    'recyclebin' = 0
}

foreach ($item in $diff) {
    $type = $item.Type
    
    # ... perform cleanup ...
    
    if ($changed) {
        $reclaimedByCategory[$type] += [double]($item.SizeMB ?? 0)
    }
}

# Return detailed breakdown:
return New-ModuleResult -ModuleName 'DiskCleanup' -Status ... `
    -ExtraData @{
        ReclaimedMB = $reclaimedMB
        BreakdownByCategory = $reclaimedByCategory
        BreakdownByDrive = $reclaimedByDrive
    }
```

### 4.4 WindowsUpdates: Add Update Categorization

**File:** modules/type1/WindowsUpdatesAudit.psm1

```powershell
# When building diff list, add Category field:
$update | Add-Member -NotePropertyName 'Category' -NotePropertyValue $(
    if ($update.Title -match 'Security|Critical') { 'Security' }
    elseif ($update.Title -match 'Important') { 'Important' }
    else { 'Optional' }
)

# Count by category:
$securityCount = @($diff | Where-Object { $_.Category -eq 'Security' }).Count
$importantCount = @($diff | Where-Object { $_.Category -eq 'Important' }).Count
$optionalCount = @($diff | Where-Object { $_.Category -eq 'Optional' }).Count

Write-Log -Level INFO -Component WINUPDATE-AUDIT -Message "Updates: $securityCount security, $importantCount important, $optionalCount optional"
```

---

## PHASE 5: FUTURE MODULES (Week 3+)

### Pattern for Adding New Modules

When you want to add module pair #7 "Network Optimization":

1. **Create Type1:** `modules/type1/NetworkOptimizationAudit.psm1` (follow the pattern from Part 11 of DEEP_ANALYSIS.md)
2. **Create Type2:** `modules/type2/NetworkOptimization.psm1`
3. **Create baseline:** `config/lists/network-optimization/network-optimization-config.json`
4. **Register:** Add entry to `$ModulePairs` array in MaintenanceOrchestrator.ps1
5. **Config flag:** Add `skipNetworkOptimization` to main-config.json

---

## TESTING CHECKLIST

### After Phase 1 (Baselines Created)
```
✓ Run ./script.bat
✓ Stage 1 shows all 9 modules
✓ Each module reports Status: Success/Skipped/Warning/Failed (NOT errors)
✓ HTML report generated without JavaScript errors
✓ No "baseline not found" error messages
```

### After Phase 2 (Consolidation)
```
✓ Run ./script.bat with consolidation
✓ Stage 1 menu shows 7 modules instead of 9
✓ "System Hardening" (merged #3+#4) completes successfully
✓ "Application Management" (merged #2+#7) completes successfully
✓ HTML report shows consolidated modules with both results in one card
✓ Performance improved (fewer enumerations)
```

### After Phase 3 (Cleanup)
```
✓ DiskCleanup audit no longer creates unused JSON snapshot
✓ No functional changes, just code cleanup
✓ script.bat still works identically
```

### After Phase 4 (Enhancements)
```
✓ BloatwareRemoval: Pre-removal process checking works
✓ SystemHardening: Pre-state backup JSON created
✓ DiskCleanup: ExtraData includes breakdown by category
✓ WindowsUpdates: Log shows category breakdown
✓ HTML report shows new data in module cards
```

---

## TIME ESTIMATE SUMMARY

| Phase | Tasks | Time | Priority |
|-------|-------|------|----------|
| 1 | Create 6 baseline files + test | 3h | 🔴 CRITICAL |
| 2 | Consolidate 2 module pairs | 5.5h | 🟠 HIGH |
| 3 | Code cleanup | 1.5h | 🟡 MEDIUM |
| 4 | Add 4 enhancements | 6-8h | 🟡 MEDIUM |
| **Total** | | **16-17.5h** | |

**Recommended Schedule:**
- Week 1: Phase 1 (3h) + Start Phase 2 (3h)
- Week 2: Finish Phase 2 (2.5h) + Phase 3 (1.5h) + Start Phase 4 (3h)
- Week 3: Finish Phase 4 (3-5h) + Testing + Documentation

---

## VERSION BUMPING

After each phase completes, update version:

**File:** modules/core/Maintenance.psm1
```powershell
# Change from:
.NOTES
    ...
    Version: 5.0.0
    Architecture: v5.0 - Unified single-core design

# To (after consolidation):
.NOTES
    ...
    Version: 5.1.0
    Architecture: v5.1 - Consolidated module pairs (7 total)
```

**File:** MaintenanceOrchestrator.ps1
```powershell
# Change from:
.SYNOPSIS
    ...
    Stage 1 – System Inventory (Type1 modules, interactive menu, 10 s countdown)
    ...

# To:
.SYNOPSIS
    ...
    Stage 1 – System Inventory (Type1 modules [7 total], interactive menu, 10 s countdown)
    ...
```

---

## ROLLBACK STRATEGY

If consolidation breaks something:

```bash
# Revert to commit before consolidation
git revert --no-edit [consolidation-commit-hash]

# Or manually restore:
# 1. Delete merged modules (SystemHardening.psm1)
# 2. Restore original modules (SecurityAudit.psm1, TelemetryAudit.psm1)
# 3. Revert MaintenanceOrchestrator.ps1 changes
# 4. Test
```

---

**End of Roadmap**
