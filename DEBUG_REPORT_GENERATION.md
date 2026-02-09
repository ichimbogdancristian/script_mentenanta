# HTML Report Generation Debugging Guide

## 🔧 Issue Description

**Problem:** HTML reports are not being generated during maintenance execution.

**Impact:** Monthly automation reports are unavailable, preventing:

- Review of system maintenance operations
- Audit trail verification
- Performance metrics analysis

## 🎯 Debugging Enhancements Added

### Phase 1: Enhanced Logging Added to MaintenanceOrchestrator.ps1

Comprehensive debug output has been added at critical checkpoints in the report generation pipeline:

#### 1. Pre-Processing Directory Structure Check

**Location:** Before `Invoke-LogProcessing` call (lines ~2500-2520)

**What It Shows:**

```
DEBUG: Pre-processing directory structure check:
  Temp Root: C:\...\temp_files
  Subdirectories found: data, logs, processed, reports
  Data directory exists: True/False
  Logs directory exists: True/False
  Data files: X
  Log subdirectories: X
```

**Purpose:** Verify that the input data directories exist and contain files before processing begins.

#### 2. LogProcessor Command Discovery

**Location:** Before `Invoke-LogProcessing` call (lines ~2524-2530)

**What It Shows:**

```
DEBUG: Checking for Invoke-LogProcessing command...
  ✓ Found Invoke-LogProcessing in module: LogProcessor
```

**Purpose:** Confirm that the LogProcessor module is properly loaded and the command is available.

#### 3. LogProcessor Execution Tracking

**Location:** During `Invoke-LogProcessing` call (lines ~2532-2560)

**What It Shows:**

```
DEBUG: Calling Invoke-LogProcessing...
DEBUG: Invoke-LogProcessing completed
  Result type: Hashtable
  Result.Success: True/False
  Result.ProcessedDataPath: C:\...\temp_files\processed
```

**Purpose:** Track whether LogProcessor executes successfully and returns expected results.

#### 4. Processed Data File Verification

**Location:** After `Invoke-LogProcessing` (lines ~2547-2558)

**What It Shows:**

```
DEBUG: Checking processed data output...
  JSON files in processed dir: X
    • metrics-summary.json - XX.X KB
    • module-results.json - XX.X KB
    • errors-analysis.json - XX.X KB
    • health-scores.json - XX.X KB
    • aggregated-results.json - XX.X KB
```

**Purpose:** Verify that LogProcessor created the required JSON files that ReportGenerator depends on.

#### 5. ReportGenerator Command Discovery

**Location:** Before `New-MaintenanceReport` call (lines ~2565-2570)

**What It Shows:**

```
DEBUG: Checking for New-MaintenanceReport command...
  ✓ Found New-MaintenanceReport in module: ReportGenerator
```

**Purpose:** Confirm that the ReportGenerator module is properly loaded.

#### 6. Reports Directory Creation

**Location:** Before report generation (lines ~2575-2580)

**What It Shows:**

```
DEBUG: Ensuring reports directory exists: C:\...\temp_files\reports
  Reports directory ready: True/False
DEBUG: Report will be saved to: C:\...\MaintenanceReport_YYYY-MM-DD_HH-mm-ss.html
```

**Purpose:** Verify that the output directory is created and accessible.

#### 7. ReportGenerator Execution Tracking

**Location:** During `New-MaintenanceReport` call (lines ~2585-2595)

**What It Shows:**

```
DEBUG: Calling New-MaintenanceReport with -EnableFallback...
DEBUG: New-MaintenanceReport completed
  Result type: Hashtable
  Result.Success: True/False
  Report Type: enhanced v3.0
  Duration: X.XX seconds
```

**Purpose:** Track report generation execution and performance.

#### 8. Generated Report File Verification

**Location:** After `New-MaintenanceReport` (lines ~2600-2615)

**What It Shows:**

```
DEBUG: Verifying generated report files...
    - C:\...\MaintenanceReport_YYYY-MM-DD_HH-mm-ss.html - XX.X KB
      Exists: True/False
    - C:\...\MaintenanceReport_YYYY-MM-DD_HH-mm-ss.txt - XX.X KB
      Exists: True/False
    - C:\...\MaintenanceReport_YYYY-MM-DD_HH-mm-ss.json - XX.X KB
      Exists: True/False
```

**Purpose:** Verify that report files were actually created and are accessible.

#### 9. Error Condition Handling

**Location:** catch blocks throughout report section (lines ~2650-2680)

**What It Shows:**

```
DEBUG: Report generation failed!
  Result.Success: False
  Result.Error: [error message]
  Result.Stack: [stack trace]
  Full result: [JSON dump]

DEBUG: Exception details:
  Type: System.Management.Automation.RuntimeException
  Message: [exception message]
  Stack trace: [detailed stack trace]
```

**Purpose:** Capture detailed error information when report generation fails.

## 🚀 How to Use This Debugging

### Step 1: Run Maintenance with Debug Output

Execute the maintenance script normally:

```batch
cd C:\Users\ichim\OneDrive\Desktop\Projects\script_mentenanta
.\script.bat
```

**OR** Run directly in PowerShell with verbose output:

```powershell
cd C:\Users\ichim\OneDrive\Desktop\Projects\script_mentenanta
pwsh -NoProfile -ExecutionPolicy Bypass -File .\MaintenanceOrchestrator.ps1 -Verbose
```

### Step 2: Review Console Output

Watch for the `DEBUG:` prefixed lines during execution. Key checkpoints:

1. **Before LogProcessor:** Verify data/logs directories exist and contain files
2. **LogProcessor Execution:** Confirm successful processing and JSON file creation
3. **Before ReportGenerator:** Verify processed data files exist
4. **ReportGenerator Execution:** Monitor report creation and file verification

### Step 3: Check Log Files

Review the maintenance transcript for detailed execution trace:

```powershell
# Find latest maintenance log
$latestLog = Get-ChildItem C:\Users\ichim\OneDrive\Desktop\Projects\script_mentenanta\temp_files\logs -Filter "Maintenance_*.log" | Sort-Object LastWriteTime -Descending | Select-Object -First 1

# Open in default text editor
notepad $latestLog.FullName

# Or search for DEBUG lines
Select-String -Path $latestLog.FullName -Pattern "DEBUG:" -Context 2, 2
```

### Step 4: Diagnose Issues

Use the debug output to identify where the pipeline fails:

| Debug Output Shows                | Likely Issue                    | Resolution                                   |
| --------------------------------- | ------------------------------- | -------------------------------------------- |
| Data directory missing/empty      | Modules not executing properly  | Check module execution in earlier stages     |
| Logs directory missing/empty      | Type2 modules not creating logs | Verify Type2 modules are running             |
| LogProcessor command not found    | Module loading failure          | Check CoreInfrastructure initialization      |
| Processed JSON files missing      | LogProcessor failing silently   | Review LogProcessor logs for errors          |
| ReportGenerator command not found | Module loading failure          | Verify ReportGenerator.psm1 in modules/core/ |
| Reports directory creation fails  | Permission issues               | Check folder permissions on temp_files/      |
| Report files not created          | Template/data issues            | Review error messages for root cause         |
| Files created but not found       | Path mismatch                   | Check $script:ProjectPaths values            |

## 🔍 Common Failure Scenarios

### Scenario 1: No Processed Data Files

**Symptoms:**

```
DEBUG: Checking processed data output...
  JSON files in processed dir: 0
```

**Cause:** LogProcessor failed to parse audit data or execution logs

**Solution:**

1. Verify Type1 modules created audit files in `temp_files/data/`
2. Verify Type2 modules created execution logs in `temp_files/logs/[module]/`
3. Check LogProcessor logs for parsing errors

### Scenario 2: Template Loading Failure

**Symptoms:**

```
ERROR: Failed to load template: modern-dashboard.html
```

**Cause:** Template files missing or corrupted

**Solution:**

1. Verify templates exist in `config/templates/`
2. Check template file permissions
3. Validate JSON template configuration: `config/templates/report-templates-config.json`

### Scenario 3: Report Files Created But Not Copied

**Symptoms:**

```
Reports generated successfully
Report copied to: [path] - FILE NOT FOUND!
```

**Cause:** Permission issues or path resolution failure

**Solution:**

1. Check write permissions on destination directory
2. Verify `$env:ORIGINAL_SCRIPT_DIR` or `$script:ProjectPaths.ParentDir` is valid
3. Run as Administrator if necessary

### Scenario 4: Silent Failure with Success=False

**Symptoms:**

```
DEBUG: New-MaintenanceReport completed
  Result.Success: False
  Result.Error: [empty or unclear message]
```

**Cause:** Exception caught but not properly reported

**Solution:**

1. Review full stack trace in debug output
2. Add -Verbose parameter to execution
3. Check ReportGenerator.psm1 logs for detailed errors

## 📂 Key File Locations

| File/Directory          | Purpose              | Expected Content                                |
| ----------------------- | -------------------- | ----------------------------------------------- |
| `temp_files/data/`      | Type1 audit results  | JSON files per module                           |
| `temp_files/logs/`      | Type2 execution logs | Subdirectories per module                       |
| `temp_files/processed/` | LogProcessor output  | metrics-summary.json, module-results.json, etc. |
| `temp_files/reports/`   | Generated reports    | HTML, TXT, JSON report files                    |
| `config/templates/`     | HTML templates       | modern-dashboard.html, module-card.html, etc.   |

## 🧪 Manual Testing Commands

### Test LogProcessor Independently

```powershell
# Load CoreInfrastructure and LogProcessor
Import-Module .\modules\core\CoreInfrastructure.psm1 -Force
Import-Module .\modules\core\LogProcessor.psm1 -Force

# Initialize paths
Initialize-GlobalPathDiscovery

# Run log processing
$result = Invoke-LogProcessing

# Check result
$result.Success
$result.ProcessedDataPath
Get-ChildItem $result.ProcessedDataPath -Filter *.json
```

### Test ReportGenerator Independently

```powershell
# Load required modules
Import-Module .\modules\core\CoreInfrastructure.psm1 -Force
Import-Module .\modules\core\TemplateEngine.psm1 -Force
Import-Module .\modules\core\OSRecommendations.psm1 -Force
Import-Module .\modules\core\ReportGenerator.psm1 -Force

# Initialize paths
Initialize-GlobalPathDiscovery

# Generate report
$reportPath = "C:\Users\ichim\OneDrive\Desktop\Projects\script_mentenanta\temp_files\reports\TestReport.html"
$result = New-MaintenanceReport -OutputPath $reportPath -EnableFallback -Verbose

# Check result
$result.Success
$result.ReportPaths
Test-Path $reportPath
```

### Verify Template Files

```powershell
# Check all templates exist
$templatesDir = "C:\Users\ichim\OneDrive\Desktop\Projects\script_mentenanta\config\templates"
$requiredTemplates = @(
    'modern-dashboard.html',
    'modern-dashboard.css',
    'module-card.html'
)

foreach ($template in $requiredTemplates) {
    $path = Join-Path $templatesDir $template
    $exists = Test-Path $path
    $size = if ($exists) { (Get-Item $path).Length } else { 0 }
    Write-Host "$template : $exists ($size bytes)"
}
```

## 📝 Next Steps

1. **Run maintenance with debugging:** Execute script and capture full console output
2. **Identify failure point:** Use debug checkpoints to pinpoint where pipeline fails
3. **Review error details:** Examine exception messages and stack traces
4. **Apply targeted fix:** Based on failure point, implement appropriate solution
5. **Verify fix:** Re-run maintenance and confirm reports generate successfully

## 🆘 If Still Failing

If debugging doesn't reveal the issue:

1. **Capture full output:**

   ```powershell
   .\script.bat *>&1 | Tee-Object -FilePath debug_output.txt
   ```

2. **Check all prerequisites:**
   - PowerShell 7.0+ installed
   - All modules in `modules/core/` and `modules/type1/`, `modules/type2/`
   - Configuration files in `config/settings/` and `config/lists/`
   - Template files in `config/templates/`

3. **Review PROJECT.md:** Ensure architecture is correctly implemented

4. **Escalate with details:**
   - Full debug output
   - Error messages and stack traces
   - File listing of temp_files/ directory
   - Module list (`Get-Module`)

---

**Created:** February 2026  
**Version:** 1.0.0  
**Status:** Active Debugging Documentation
