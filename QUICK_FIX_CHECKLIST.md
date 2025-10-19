# ⚡ **Quick Fix Checklist - Critical Issues Only**

## 🔴 **CRITICAL FIX #1: LogProcessor Log Levels**
**File:** `modules/core/LogProcessor.psm1`  
**Action:** Replace 'WARNING' with 'WARN' (11 instances)

```powershell
# Lines to fix: 1639, 1647, 1655, 1677, 1705, 1714, 1733, 1741, 1749, 1757, 1863

# Find & Replace:
Find:    -Level 'WARNING'
Replace: -Level 'WARN'
```

**Verification:**
```powershell
grep -n "Level 'WARNING'" modules/core/LogProcessor.psm1
# Should return: 0 matches
```

---

## 🔴 **CRITICAL FIX #2: AppUpgrade Parameter Type**
**File:** `modules/type2/AppUpgrade.psm1`  
**Action:** Change line 81 parameter type

```powershell
# BEFORE (Line 81):
[PSCustomObject]$Config,

# AFTER:
[hashtable]$Config,
```

**Verification:**
```powershell
# Test module loading:
Import-Module ".\modules\type2\AppUpgrade.psm1" -Force
$testConfig = @{ test = 'value' }
Get-Command Invoke-AppUpgrade | Select-Object -ExpandProperty Parameters | Select-Object -ExpandProperty Config
# Should show: ParameterType = System.Collections.Hashtable
```

---

## 🔴 **CRITICAL FIX #3: Batch File PowerShell Syntax**
**File:** `script.bat`  
**Action:** Escape curly braces or restructure (lines 1196-1210)

### **Option A: Quick Escape (Minimal Change)**
```batch
# Line 1197:
SET "PS_ARGS=!PS_ARGS!& ^{ "
```

### **Option B: Restructure (Recommended)**
```batch
# Replace lines 1196-1210 with:
SET "PS_ARGS=-ExecutionPolicy Bypass -NoExit -Command ""Set-Location '%WORKING_DIR%'; & '%ORCHESTRATOR_PATH%' -NonInteractive"""
```

**Verification:**
Run script.bat and check for:
- ✅ No `'{' is not recognized` error
- ✅ PowerShell window launches successfully

---

## ✅ **Post-Fix Validation**

### **Test 1: Module Loading**
```powershell
# Load all modules and check for errors
Import-Module ".\modules\core\CoreInfrastructure.psm1" -Force -Global
Import-Module ".\modules\type2\AppUpgrade.psm1" -Force
Get-Command Invoke-AppUpgrade
# Should succeed without errors
```

### **Test 2: Log Processing**
```powershell
# Verify no log level errors
.\MaintenanceOrchestrator.ps1 -NonInteractive -DryRun
# Check temp_files/processed/ - should contain all 5 files:
# - health-scores.json
# - metrics-summary.json
# - module-results.json
# - maintenance-log.json
# - errors-analysis.json
```

### **Test 3: AppUpgrade Execution**
```powershell
# Run specific task
.\MaintenanceOrchestrator.ps1 -NonInteractive -TaskNumbers 6
# Should complete without "Cannot convert PSCustomObject to Hashtable" error
```

---

## 📋 **Expected Results**

### **Before Fixes:**
- ❌ AppUpgrade fails with type mismatch
- ❌ LogProcessor crashes with 'WARNING' validation error
- ❌ Batch launcher shows syntax errors
- ⚠️ 5 processed files missing
- ⚠️ Incomplete reports

### **After Fixes:**
- ✅ All 6/6 modules execute successfully
- ✅ LogProcessor completes without errors
- ✅ Batch launcher runs cleanly
- ✅ All 5 processed files created
- ✅ Complete reports with full analytics

---

## ⏱️ **Estimated Time**
- **Fix #1:** 2 minutes (Find & Replace)
- **Fix #2:** 1 minute (Single line change)
- **Fix #3:** 3 minutes (Restructure batch command)
- **Validation:** 5 minutes (Run tests)
- **Total:** ~11 minutes

---

## 🚨 **If Issues Persist After Fixes:**

1. **Check VS Code Diagnostics:** `Ctrl+Shift+M` for Problems panel
2. **Review detailed analysis:** See `FAULT_ANALYSIS.md` for complete breakdown
3. **Run with verbose logging:**
   ```powershell
   .\MaintenanceOrchestrator.ps1 -NonInteractive -Verbose
   ```
4. **Check execution logs:**
   ```
   temp_files/logs/app-upgrade/execution.log
   temp_files/processed/*.json
   ```

---

**Last Updated:** 2025-10-19  
**Related Document:** FAULT_ANALYSIS.md (comprehensive version)
