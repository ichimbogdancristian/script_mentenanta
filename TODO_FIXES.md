# 🔧 TODO: Comprehensive Project Fixes

**Date Created:** October 23, 2025  
**Status:** In Progress  
**Priority:** High

---

## 📋 **CRITICAL ISSUES IDENTIFIED**

### **From Terminal Log Analysis:**

1. ❌ **UTF-8 Encoding Issues in Terminal**
   - **Problem:** Special characters appearing as `≡ƒÜÇ`, `≡ƒôü`, `≡ƒöº` instead of emojis
   - **Cause:** Terminal not set to UTF-8 encoding
   - **Impact:** Unreadable logs in terminal output

2. ❌ **maintenance.log Overwriting Issue**
   - **Problem:** Module logs overwriting script.bat initial logs
   - **Current:** Both script.bat and modules write to same maintenance.log
   - **Impact:** Loss of bootstrap logging history

3. ❌ **Module Log Structure Incomplete**
   - **Problem:** No dedicated log files for each Type2 module
   - **Current:** Logs scattered, not organized per module
   - **Impact:** Report generator cannot parse module-specific logs

4. ❌ **Missing System Summary Module**
   - **Problem:** No PC hardware/software summary at report beginning
   - **Impact:** Reports lack context about system being maintained

5. ❌ **Timestamp Format Too Verbose**
   - **Problem:** `[2025-10-23 14:49:34.521]` includes full date on every line
   - **Impact:** Log files are harder to read, waste space

6. ⚠️ **Report Generation Warnings**
   - **Problem:** Multiple parsing failures for module data
   - **Examples:**

     ```
     Failed to parse module data for essential-apps
     Failed to parse module data for system-optimization
     Failed to parse module data for telemetry-audit
     ```

   - **Impact:** Incomplete report generation

7. ⚠️ **LogProcessor Null Reference Errors**
   - **Problem:** `You cannot call a method on a null-valued expression`
   - **Location:** LogProcessor comprehensive analysis
   - **Impact:** Missing metrics in reports

8. ⚠️ **AppUpgrade Module Failure**
   - **Problem:** `Cannot bind argument to parameter 'DetectionResults' because it is null`
   - **Impact:** AppUpgrade functionality broken

9. ❌ **Installation Failures (EssentialApps)**
   - **Problem:** All apps fail to install (winget AND chocolatey)
   - **Examples:** Java, LibreOffice, Adobe Reader, PDF24, Notepad++, Chrome, Firefox
   - **Impact:** Essential apps module not functional

10. ⚠️ **Windows Updates Module - Restart Required**
    - **Problem:** 8 updates found, 0 installed, 8 failed
    - **Warning:** System restart required
    - **Impact:** Updates not completing

---

## 🎯 **SOLUTION ROADMAP**

### **Phase 1: Logging System Restructure (HIGH PRIORITY)**

#### **Task 1.1: Separate script.bat Logging**

- [ ] **Change script.bat log location**
  - Current: `%WORKING_DIR%maintenance.log`
  - New: `%WORKING_DIR%bootstrap-launcher.log`
  - Location: Same as script.bat (before temp_files creation)

- [ ] **Move bootstrap log after temp_files creation**
  - Copy `bootstrap-launcher.log` to `temp_files/logs/bootstrap-launcher.log`
  - Keep original for reference
  - Update MaintenanceOrchestrator to reference moved file

#### **Task 1.2: Create Dedicated Module Logs**

- [ ] **Ensure each Type2 module creates own log**
  - Path pattern: `temp_files/logs/[module-name]/execution.log`
  - Required modules:
    - `temp_files/logs/bloatware-removal/execution.log`
    - `temp_files/logs/essential-apps/execution.log`
    - `temp_files/logs/system-optimization/execution.log`
    - `temp_files/logs/telemetry-disable/execution.log`
    - `temp_files/logs/windows-updates/execution.log`
    - `temp_files/logs/app-upgrade/execution.log`

- [ ] **Update CoreInfrastructure.psm1**
  - Modify `Write-LogEntry` to handle module-specific logs
  - Ensure `-LogPath` parameter correctly routes to module log
  - Prevent writing to maintenance.log when `-LogPath` specified

#### **Task 1.3: Orchestrator maintenance.log Scope**

- [ ] **Restrict maintenance.log to orchestrator only**
  - Location: `temp_files/maintenance.log`
  - Content: ONLY orchestrator-level operations
  - Include: Module loading, task sequencing, high-level results
  - Exclude: Individual module operation details

#### **Task 1.4: Simplify Timestamp Format**

- [ ] **Change timestamp in all modules**
  - Current: `[2025-10-23 14:49:34.521]`
  - New: `[14:49:34]` (HH:mm:ss only)
  - Location: `CoreInfrastructure.psm1` line ~700
  - Update: `Get-Date -Format "HH:mm:ss"` instead of `"yyyy-MM-dd HH:mm:ss.fff"`

- [ ] **Add date header to log files**
  - Add single date header at top of each log file
  - Format: `=== Maintenance Log - 2025-10-23 ===`
  - Apply to: bootstrap-launcher.log, maintenance.log, execution.log files

---

### **Phase 2: Terminal Encoding Fix (HIGH PRIORITY)**

#### **Task 2.1: Fix UTF-8 Output in PowerShell**

- [ ] **Add encoding configuration to MaintenanceOrchestrator**
  - Location: MaintenanceOrchestrator.ps1, beginning of file
  - Add:

    ```powershell
    # Set console output encoding to UTF-8
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $PSDefaultParameterValues['*:Encoding'] = 'utf8'
    ```

- [ ] **Update script.bat PowerShell invocation**
  - Add UTF-8 encoding parameter
  - Change from: `pwsh.exe -ExecutionPolicy Bypass -File ...`
  - Change to: `pwsh.exe -ExecutionPolicy Bypass -NoProfile -Command "[Console]::OutputEncoding=[System.Text.Encoding]::UTF8; & 'script.ps1' @args"`

- [ ] **Alternative: Replace emojis with ASCII**
  - Create mapping table for emoji → ASCII equivalents
  - Example: `🔍` → `[*]`, `✓` → `[OK]`, `❌` → `[X]`
  - Apply consistently across all modules

#### **Task 2.2: Create Terminal Compatibility Mode**

- [ ] **Add config option for ASCII-only output**
  - Location: `config/main-config.json`
  - Add: `"terminalEncoding": "UTF-8"` or `"ASCII"`
  - Update UserInterface module to check this setting

---

### **Phase 3: Create System Summary Module (MEDIUM PRIORITY)**

#### **Task 3.1: Create SystemInventory Module (Type1)**

- [ ] **File:** `modules/type1/SystemInventoryAudit.psm1`
- [ ] **Exports:** `Get-SystemInventory`
- [ ] **Collects:**
  - Computer name, domain/workgroup
  - OS version, build, edition
  - CPU: Name, cores, threads, speed
  - RAM: Total, available, usage %
  - Disk: C: drive size, free space, usage %
  - Network: IP address, MAC address, connection type
  - Last boot time, uptime
  - PowerShell version
  - .NET Framework version

- [ ] **Saves to:** `temp_files/data/system-inventory.json`

#### **Task 3.2: Integrate into Report Generation**

- [ ] **Update ReportGenerator.psm1**
  - Add system summary section before module sections
  - Create new template: `config/system-summary-template.html`
  - Display system info in card layout

- [ ] **Update LogProcessor.psm1**
  - Load system inventory data
  - Include in processed data output

---

### **Phase 4: Fix Report Generation Issues (HIGH PRIORITY)**

#### **Task 4.1: Fix Module Data Parsing Errors**

- [ ] **Investigate LogProcessor.psm1**
  - Location: Lines parsing module-specific data
  - Issue: Attempting to index PSObject instead of hashtable
  - Solution: Add proper type conversion:

    ```powershell
    if ($content -is [PSCustomObject]) {
        $content = @{}
        foreach ($prop in $content.PSObject.Properties) {
            $content[$prop.Name] = $prop.Value
        }
    }
    ```

- [ ] **Add null checks before processing**
  - Check if data exists before parsing
  - Provide fallback empty data structure
  - Log warnings instead of errors

#### **Task 4.2: Fix LogProcessor Null Reference**

- [ ] **Location:** `LogProcessor.psm1` - comprehensive analysis function
- [ ] **Add null guards:**

  ```powershell
  if ($null -eq $data -or $data.Count -eq 0) {
      Write-LogEntry -Level 'WARN' -Message 'No data to analyze'
      return $emptyAnalysis
  }
  ```

- [ ] **Validate required properties exist:**
  - Check for Type1Results, Type2Results before accessing
  - Provide default values for missing properties

---

### **Phase 5: Fix Module Execution Errors (MEDIUM PRIORITY)**

#### **Task 5.1: Fix AppUpgrade Module**

- [ ] **Location:** `modules/type2/AppUpgrade.psm1`
- [ ] **Issue:** Null DetectionResults parameter
- [ ] **Fix:**
  - Ensure detection phase returns valid results
  - Add null check: `if ($null -eq $detectionResults) { $detectionResults = @() }`
  - Update function signature to make parameter optional

#### **Task 5.2: Fix EssentialApps Installation**

- [ ] **Investigate winget/chocolatey failure**
  - Check if package managers are properly initialized
  - Verify package IDs are correct
  - Add retry logic with exponential backoff

- [ ] **Add package manager verification**
  - Test winget availability: `Get-Command winget`
  - Test chocolatey availability: `Get-Command choco`
  - Log detailed error messages

- [ ] **Implement fallback download**
  - If winget fails, try direct download URLs
  - Store download URLs in essential-apps.json
  - Use `Invoke-WebRequest` + silent installer

#### **Task 5.3: Windows Updates Module**

- [ ] **Investigate why updates fail to install**
  - Check COM API permissions
  - Verify Windows Update service is running
  - Add restart scheduling after updates

- [ ] **Add restart handling**
  - Detect if restart required
  - Schedule task to continue after restart
  - Resume from last successful update

---

### **Phase 6: Improve Report Generator Template Integration (LOW PRIORITY)**

#### **Task 6.1: Verify Template Loading**

- [ ] **Check all template files exist:**
  - `config/report-template.html`
  - `config/task-card-template.html`
  - `config/report-styles.css`
  - `config/report-templates-config.json`

- [ ] **Add template validation**
  - Check for required placeholders: `{{REPORT_TITLE}}`, `{{MODULE_SECTIONS}}`, etc.
  - Warn if placeholders missing
  - Provide default templates if files missing

#### **Task 6.2: Enhance Report Styling**

- [ ] **Update report-styles.css**
  - Ensure proper responsive design
  - Add print-friendly styles
  - Improve table formatting for operation logs

- [ ] **Create operation log table template**
  - Consistent formatting for all modules
  - Sortable columns
  - Color-coded by result (success/failure)

---

## 📝 **IMPLEMENTATION PLAN**

### **Week 1: Critical Logging Fixes**

- Day 1-2: Task 1.1, 1.2, 1.3 (Logging restructure)
- Day 3: Task 1.4 (Timestamp simplification)
- Day 4-5: Task 2.1, 2.2 (UTF-8 encoding)

### **Week 2: Module Fixes & System Summary**

- Day 1-2: Task 3.1, 3.2 (System inventory module)
- Day 3-4: Task 4.1, 4.2 (Report generation fixes)
- Day 5: Task 5.1 (AppUpgrade fix)

### **Week 3: Installation & Updates**

- Day 1-3: Task 5.2 (EssentialApps installation)
- Day 4-5: Task 5.3 (Windows Updates fix)

### **Week 4: Polish & Documentation**

- Day 1-2: Task 6.1, 6.2 (Template improvements)
- Day 3-4: Testing all fixes
- Day 5: Documentation updates

---

## ✅ **TESTING CHECKLIST**

After each phase:

- [ ] Run script.bat in clean environment
- [ ] Verify bootstrap-launcher.log created correctly
- [ ] Verify module logs created in proper directories
- [ ] Verify maintenance.log contains only orchestrator entries
- [ ] Check terminal output is readable (no encoding issues)
- [ ] Verify reports generate without errors
- [ ] Verify system summary appears in report
- [ ] Test all modules in DryRun mode
- [ ] Test all modules in Live mode
- [ ] Verify report includes all module data

---

## 🔍 **SPECIFIC CODE CHANGES NEEDED**

### **Change 1: script.bat (Line 86)**

```batch
REM Current:
SET "LOG_FILE=%WORKING_DIR%maintenance.log"

REM Change to:
SET "LOG_FILE=%WORKING_DIR%bootstrap-launcher.log"
```

### **Change 2: MaintenanceOrchestrator.ps1 (Line 1-10)**

```powershell
# Add at the very beginning:
#Requires -Version 7.0
#Requires -RunAsAdministrator

# Fix UTF-8 encoding for terminal output
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding = [System.Text.Encoding]::UTF8
$PSDefaultParameterValues['*:Encoding'] = 'utf8'
$OutputEncoding = [System.Text.Encoding]::UTF8
```

### **Change 3: CoreInfrastructure.psm1 (Line ~680)**

```powershell
# Current:
$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"

# Change to:
$timestamp = Get-Date -Format "HH:mm:ss"
```

### **Change 4: All Type2 Modules**

```powershell
# Ensure every module creates execution log:
$executionLogDir = Join-Path $Global:ProjectPaths.TempFiles "logs\[module-name]"
if (-not (Test-Path $executionLogDir)) {
    New-Item -Path $executionLogDir -ItemType Directory -Force | Out-Null
}
$executionLogPath = Join-Path $executionLogDir "execution.log"

# Add log header
$logHeader = @"
=== [Module Name] Execution Log ===
Date: $(Get-Date -Format 'yyyy-MM-dd')
Session: $env:MAINTENANCE_SESSION_ID
Mode: $(if ($DryRun) { 'DRY-RUN' } else { 'LIVE' })
===================================

"@
Add-Content -Path $executionLogPath -Value $logHeader
```

---

## 🚨 **PRIORITY ORDER**

1. **CRITICAL (Do First):**
   - Task 1.1, 1.2, 1.3 (Logging separation)
   - Task 2.1 (UTF-8 encoding)
   - Task 4.1, 4.2 (Report parsing fixes)

2. **HIGH (Do Soon):**
   - Task 1.4 (Timestamp format)
   - Task 5.1 (AppUpgrade fix)

3. **MEDIUM (Do When Possible):**
   - Task 3.1, 3.2 (System summary)
   - Task 5.2 (EssentialApps fix)
   - Task 5.3 (Windows Updates)

4. **LOW (Nice to Have):**
   - Task 2.2 (ASCII compatibility mode)
   - Task 6.1, 6.2 (Template polish)

---

## 📊 **SUCCESS CRITERIA**

✅ **Project is FIXED when:**

1. Terminal output displays correctly without encoding issues
2. bootstrap-launcher.log exists with only script.bat logs
3. maintenance.log exists with only orchestrator logs
4. Each Type2 module has dedicated execution.log
5. Report generator processes all logs without errors
6. System summary appears at top of report
7. Timestamps are simplified to HH:mm:ss format
8. AppUpgrade module executes without null errors
9. EssentialApps installs at least some applications
10. Windows Updates completes without failures
11. All reports generate successfully
12. LogProcessor processes data without null reference errors

---

**Last Updated:** October 23, 2025  
**Estimated Completion:** 3-4 weeks  
**Contributors:** AI Coding Agent
