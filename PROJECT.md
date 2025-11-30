# Windows Maintenance Automation System

## 📋 Project Overview

**Version:** 3.0.0 (Modular Architecture)  
**Author:** Bogdan Ichim  
**Language:** PowerShell 7.0+  
**Platform:** Windows 10/11  
**License:** Personal Project

A comprehensive, enterprise-grade Windows maintenance automation system featuring modular architecture, robust error handling, detailed logging, and interactive HTML reporting. Designed to streamline system optimization, bloatware removal, essential software installation, privacy controls, and system updates.

---

## 🏗️ Architecture Overview

### System Design Philosophy

The project follows a **3-tier modular architecture** with clear separation of concerns:

```
┌──────────────────────────────────────────────────────────────┐
│                    EXECUTION LAYER                            │
│  script.bat → MaintenanceOrchestrator.ps1                    │
│  (Entry Point)     (Coordination)                             │
└──────────────────────────────────────────────────────────────┘
                              ↓
┌──────────────────────────────────────────────────────────────┐
│                     CORE MODULES LAYER                        │
│  ┌────────────────┐  ┌──────────────┐  ┌─────────────────┐  │
│  │ Infrastructure │  │   Logging    │  │  User Interface │  │
│  │   & Paths      │  │ & Reporting  │  │   & Menus       │  │
│  └────────────────┘  └──────────────┘  └─────────────────┘  │
└──────────────────────────────────────────────────────────────┘
                              ↓
┌──────────────────────────────────────────────────────────────┐
│                  OPERATIONAL MODULES LAYER                    │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐       │
│  │    TYPE 1    │  │    TYPE 2    │  │  Reporting   │       │
│  │   (Audit)    │  │  (Actions)   │  │  Generator   │       │
│  │              │  │              │  │              │       │
│  │ • Detection  │  │ • Execution  │  │ • HTML/Text  │       │
│  │ • Inventory  │  │ • Removal    │  │ • JSON/CSV   │       │
│  │ • Analysis   │  │ • Install    │  │ • Charts     │       │
│  └──────────────┘  └──────────────┘  └──────────────┘       │
└──────────────────────────────────────────────────────────────┘
```

### Architecture Version: v3.0 (Split & Consolidated)

**Key Design Patterns:**
- ✅ **Modular Design** - Self-contained modules with clear interfaces
- ✅ **Type1/Type2 Separation** - Read-only audit vs system-modifying actions
- ✅ **Global Path Discovery** - Centralized path management via environment variables
- ✅ **Result Aggregation** - Unified data collection via LogAggregator
- ✅ **Split Report Generation** - Separate data processing (LogProcessor) from rendering (ReportGenerator)
- ✅ **Error Resilience** - Comprehensive try-catch with fallback mechanisms
- ✅ **Session Management** - GUID-based session tracking for traceability

---

## 📂 Project Structure

```
script_mentenanta/
│
├── 📄 script.bat                          # Entry point - PowerShell 7 launcher with auto-elevation
├── 📄 MaintenanceOrchestrator.ps1         # Central coordinator - module loading & execution flow
│
├── 📁 modules/
│   ├── 📁 core/                           # Foundation modules (always loaded first)
│   │   ├── CoreInfrastructure.psm1       # Path discovery, config loading, logging foundation
│   │   ├── LogAggregator.psm1            # Result collection & correlation (v3.1)
│   │   ├── LogProcessor.psm1             # Data processing pipeline (Type1)
│   │   ├── UserInterface.psm1            # Interactive menus, progress & result presentation
│   │   ├── ReportGenerator.psm1          # HTML/Text report rendering
│   │   └── ModernReportGenerator.psm1    # Modern dashboard reports (v5.0 glassmorphism)
│   │
│   ├── 📁 type1/                          # Audit & Inventory Modules (read-only)
│   │   ├── SystemInventoryAudit.psm1     # System hardware/software inventory
│   │   ├── BloatwareDetectionAudit.psm1  # Detect unwanted pre-installed apps
│   │   ├── EssentialAppsAudit.psm1       # Check for missing essential software
│   │   ├── SystemOptimizationAudit.psm1  # Analyze optimization opportunities
│   │   ├── TelemetryAudit.psm1           # Privacy & telemetry analysis
│   │   ├── WindowsUpdatesAudit.psm1      # Update compliance check
│   │   ├── SecurityAudit.psm1            # Security posture assessment
│   │   ├── PrivacyInventory.psm1         # Privacy settings inventory
│   │   └── AppUpgradeAudit.psm1          # Application upgrade recommendations
│   │
│   └── 📁 type2/                          # Action Modules (system modification)
│       ├── SystemInventory.psm1           # NEW: Collect system info (always runs first)
│       ├── BloatwareRemoval.psm1         # Remove unwanted applications
│       ├── EssentialApps.psm1            # Install essential software
│       ├── SystemOptimization.psm1       # Apply performance optimizations
│       ├── TelemetryDisable.psm1         # Disable telemetry & enhance privacy
│       ├── WindowsUpdates.psm1           # Install Windows updates
│       ├── SecurityEnhancement.psm1      # Apply security hardening
│       └── AppUpgrade.psm1               # Upgrade installed applications
│
├── 📁 config/
│   ├── 📁 settings/                       # Execution & logging configuration
│   │   ├── main-config.json              # Primary configuration file
│   │   └── logging-config.json           # Logging verbosity & formatting
│   │
│   ├── 📁 lists/                          # Data lists for modules
│   │   ├── bloatware-list.json           # Apps to remove
│   │   ├── essential-apps.json           # Apps to install
│   │   └── app-upgrade-config.json       # Upgrade rules
│   │
│   └── 📁 templates/                      # Report templates
│       ├── modern-dashboard.html         # Modern HTML template (v5.0)
│       ├── modern-dashboard.css          # Modern CSS styling (glassmorphism)
│       ├── module-card.html              # Module result card template
│       ├── report-template-v4-enhanced.html  # Legacy v4 template
│       └── report-styles-v4-enhanced.css     # Legacy v4 styles
│
└── 📁 temp_files/                         # Runtime & output directory
    ├── 📁 data/                           # Type1 audit results (JSON)
    ├── 📁 logs/                           # Type2 execution logs (per-module)
    ├── 📁 reports/                        # Generated HTML/text reports
    ├── 📁 processed/                      # Processed data for reports
    ├── 📁 inventory/                      # System inventory snapshots
    └── 📁 temp/                           # Temporary processing files
```

**📝 Note on Orphaned Type1 Modules:**

Some Type1 audit modules exist without corresponding Type2 execution modules. This is **intentional design**:

- **PrivacyInventory.psm1** - Information gathering only, used for manual compliance audits. Privacy actions are handled by `TelemetryDisable.psm1`.

Not all audit modules require automated remediation - some are designed for **manual review**, **compliance reporting**, and **system documentation** purposes.

---

## 🔧 Core Modules Deep Dive

### CoreInfrastructure.psm1
**Purpose:** Foundation module providing unified infrastructure services

**Responsibilities:**
- ✅ **Global Path Discovery** - Auto-detect project structure, set environment variables
- ✅ **Configuration Management** - Load & validate JSON configs with schema validation
- ✅ **Logging System** - Structured logging with ISO 8601 timestamps
- ✅ **Session Management** - GUID-based session tracking with file organization
- ✅ **Standardized Paths** - `Get-AuditResultsPath()`, `Save-DiffResults()` for consistency

**Key Functions:**
```powershell
Initialize-GlobalPathDiscovery   # Setup paths & environment variables
Get-MainConfiguration            # Load main-config.json
Get-BloatwareConfiguration       # Load bloatware-list.json
Get-AuditResultsPath            # Standardized Type1 result paths (FIX #4)
Save-DiffResults                # Standardized Type2 diff persistence (FIX #6)
Write-LogEntry                  # Structured logging with levels & components
```

**Environment Variables Set:**
- `MAINTENANCE_PROJECT_ROOT` - Project directory
- `MAINTENANCE_CONFIG_ROOT` - Config directory
- `MAINTENANCE_MODULES_ROOT` - Modules directory
- `MAINTENANCE_TEMP_ROOT` - Temporary files directory
- `MAINTENANCE_SESSION_ID` - Unique session GUID

### LogAggregator.psm1
**Purpose:** Unified result collection & correlation system (v3.1)

**Responsibilities:**
- ✅ **Result Collection** - Aggregate module execution results
- ✅ **Correlation Tracking** - Generate & track correlation IDs
- ✅ **Standardized Schema** - Normalize results to common structure
- ✅ **Session Management** - Track execution sequence & timing
- ✅ **Error Aggregation** - Collect errors/warnings across modules

**Key Functions:**
```powershell
Start-ResultCollection      # Initialize session
New-CorrelationId          # Generate unique correlation ID
New-ModuleResult           # Create standardized result object
Add-ModuleResult           # Add result to collection
Get-AggregatedResults      # Retrieve all results
Complete-ResultCollection  # Finalize & export session data
```

**Result Object Schema:**
```powershell
@{
    ModuleName = "BloatwareRemoval"
    Status = "Success|Failed|Skipped"
    Metrics = @{
        ItemsDetected = 25
        ItemsProcessed = 18
        DurationSeconds = 34.5
    }
    Results = @{ } # Module-specific data
    Errors = @()
    Warnings = @()
}
```

### LogProcessor.psm1
**Purpose:** Data processing pipeline (Type1 - Read-only)

**Responsibilities:**
- ✅ **Log Aggregation** - Collect Type1 audit results & Type2 execution logs
- ✅ **Data Normalization** - Parse & standardize log formats
- ✅ **Metrics Calculation** - Generate dashboard metrics & statistics
- ✅ **Performance Optimization** - Caching layer with TTL (30 minutes)
- ✅ **Error Parsing** - Extract & categorize errors from logs

**Pipeline Stages:**
1. **Load** - Read raw logs from `temp_files/data/` and `temp_files/logs/`
2. **Parse** - Extract structured data from log entries
3. **Normalize** - Convert to standardized format
4. **Aggregate** - Group by module and calculate metrics
5. **Cache** - Store in memory for repeated queries
6. **Export** - Write to `temp_files/processed/` for ReportGenerator

**Key Functions:**
```powershell
Invoke-LogProcessing              # Full pipeline execution
Get-Type1AuditData               # Load Type1 audit results
Get-Type2ExecutionLogs           # Load Type2 execution logs
Get-ComprehensiveLogAnalysis     # Parse & analyze all logs
Get-ComprehensiveDashboardMetrics # Calculate dashboard KPIs
```

### ReportGenerator.psm1
**Purpose:** Report rendering engine (Type1 - Read-only)

**Responsibilities:**
- ✅ **Template Management** - Load HTML/CSS templates from config
- ✅ **Data Consumption** - Read processed data from LogProcessor
- ✅ **HTML Rendering** - Generate interactive dashboards
- ✅ **Multi-Format Export** - HTML, Text, JSON, Summary
- ✅ **Chart Generation** - Create visualizations for metrics

**Report Formats:**
- **HTML** - Interactive dashboard with glassmorphism design (v5.0)
- **Text** - Plain-text summary for logs/emails
- **JSON** - Machine-readable export for integrations
- **Summary** - Quick overview (1-page)

**Key Functions:**
```powershell
New-MaintenanceReport        # Primary entry point
Get-HtmlTemplates           # Load templates from config
Get-ProcessedLogData        # Load data from LogProcessor
New-HtmlReportContent       # Generate HTML report
New-TextReportContent       # Generate text report
```

### UserInterface.psm1
**Purpose:** Interactive user interface with countdown-based menus

**Features:**
- Main execution menu (Normal vs Dry-Run mode)
- Task selection submenu (All vs Specific tasks)
- Automatic defaults after 20-second countdown
- Real-time progress display
- Task completion tracking
- Formatted result summaries

**Key Features:**
- ✅ **Unattended Fallback** - Auto-select defaults when no user input
- ✅ **Graceful Degradation** - Works in non-interactive contexts (CI/CD)
- ✅ **Comprehensive Feedback** - Clear progress indicators & status

---

## 📦 Module Types & Execution Flow

### Type 1 Modules (Audit/Inventory - Read-Only)

**Purpose:** Detect, analyze, and report system state without modifications

**Execution Pattern:**
```powershell
function Invoke-[ModuleName]Audit {
    param([switch]$DryRun)
    
    # 1. Initialize
    $results = @{ DetectedItems = @(); Analysis = @{} }
    
    # 2. Detect/Scan
    $detectedItems = Get-SystemState
    
    # 3. Analyze
    $results.Analysis = Analyze-DetectedState $detectedItems
    
    # 4. Save to standardized path
    $auditPath = Get-AuditResultsPath -ModuleName $ModuleName
    $results | ConvertTo-Json | Set-Content $auditPath
    
    # 5. Return results
    return $results
}
```

**Standard Output:** `temp_files/data/[module]-results.json`

**Examples:**
- `BloatwareDetectionAudit` → Scans for unwanted apps
- `EssentialAppsAudit` → Checks for missing software
- `SystemOptimizationAudit` → Analyzes optimization opportunities

### Type 2 Modules (Action - System Modification)

**Purpose:** Execute system changes based on Type1 audit results

**Execution Pattern:**
```powershell
function Invoke-[ModuleName] {
    param([switch]$DryRun)
    
    # 1. Run Type1 audit internally
    $auditResults = Invoke-[ModuleName]Audit
    
    # 2. Load diff list if exists
    $diffPath = Get-DiffPath -ModuleName $ModuleName
    $diffList = if (Test-Path $diffPath) { Get-Content $diffPath | ConvertFrom-Json }
    
    # 3. Determine actions
    $actionsToPerform = $diffList ?? $auditResults.DetectedItems
    
    # 4. Execute or simulate
    if ($DryRun) {
        Write-LogEntry "DRY-RUN: Would process $($actionsToPerform.Count) items"
    } else {
        foreach ($item in $actionsToPerform) {
            # Perform actual system change
            Process-Item $item
        }
    }
    
    # 5. Save execution log
    $logPath = Get-SessionPath -Category 'logs' -SubCategory $ModuleName -FileName 'execution.log'
    Save-ExecutionLog $logPath
}
```

**Standard Outputs:**
- `temp_files/logs/[module]/execution.log` - Detailed execution log
- `temp_files/temp/[module]-diff.json` - Items to process (optional)

**Examples:**
- `BloatwareRemoval` → Uninstalls unwanted apps
- `EssentialApps` → Installs missing software
- `SystemOptimization` → Applies performance tweaks

---

## 🔄 Execution Flow

### Complete Execution Sequence

```
1. script.bat (Entry Point)
   │
   ├─ Verify PowerShell 7+
   ├─ Request Administrator Elevation (if needed)
   └─ Launch MaintenanceOrchestrator.ps1
       │
       2. MaintenanceOrchestrator.ps1
          │
          ├─ Initialize Global Paths (environment variables)
          ├─ Load Core Modules (CoreInfrastructure, LogAggregator, UserInterface, etc.)
          ├─ Load Type2 Modules (BloatwareRemoval, EssentialApps, etc.)
          ├─ Validate Configuration (JSON syntax & schema)
          ├─ Initialize Result Collection (LogAggregator)
          │
          3. User Interaction (if interactive mode)
             │
             ├─ Show Main Menu (Normal vs Dry-Run)
             ├─ Show Task Selection (All vs Specific)
             └─ Countdown auto-selection after 20 seconds
                 │
                 4. Module Execution (foreach selected task)
                    │
                    ├─ Call Invoke-[ModuleName] with -DryRun if selected
                    ├─ Module runs Type1 audit internally
                    ├─ Module executes Type2 actions (or simulates if dry-run)
                    ├─ Results added to LogAggregator
                    └─ Logs written to temp_files/logs/[module]/
                        │
                        5. Log Processing (after all modules complete)
                           │
                           ├─ LogProcessor aggregates all logs
                           ├─ Calculate metrics & statistics
                           ├─ Export to temp_files/processed/
                           │
                           6. Report Generation
                              │
                              ├─ ReportGenerator loads processed data
                              ├─ Load HTML/CSS templates
                              ├─ Render interactive dashboard
                              ├─ Generate text/JSON exports
                              └─ Save to temp_files/reports/
                                  │
                                  7. Display Results
                                     │
                                     ├─ Show summary on console
                                     ├─ Open HTML report in browser
                                     └─ Log completion status
```

---

## ⚙️ Configuration System

### main-config.json (Settings)

**Location:** `config/settings/main-config.json`

**Key Sections:**
```json
{
  "execution": {
    "defaultMode": "unattended",        // Interactive mode behavior
    "countdownSeconds": 20,             // Menu timeout
    "enableDryRun": true                // Allow simulation mode
  },
  "modules": {
    "skipBloatwareRemoval": false,      // Module toggles
    "skipEssentialApps": false,
    "skipWindowsUpdates": false
  },
  "system": {
    "createSystemRestorePoint": true,   // Safety features
    "maxLogSizeMB": 10,
    "warnOnPendingReboot": true
  },
  "reporting": {
    "enableHtmlReport": true,           // Report formats
    "enableDetailedAudit": true,
    "generateBeforeAfterComparison": true
  }
}
```

### logging-config.json (Logging)

**Location:** `config/settings/logging-config.json`

**Verbosity Levels:**
- **Minimal** - Start/end/results only
- **Normal** - Important operations (default)
- **Detailed** - Full context + troubleshooting
- **Debug** - Everything including internal state

**Log Components:**
- `ORCHESTRATOR` - Main coordination
- `TYPE1` - Audit modules
- `TYPE2` - Action modules
- `BLOATWARE`, `APPS`, `UPDATES`, etc. - Module-specific

### Configuration Lists

**bloatware-list.json** - Apps to remove
```json
{
  "all": [
    "Microsoft.BingNews",
    "Microsoft.GetHelp",
    "Microsoft.Getstarted",
    // ... more pre-installed apps
  ]
}
```

**essential-apps.json** - Apps to install
```json
{
  "all": [
    {
      "name": "7-Zip",
      "wingetId": "7zip.7zip",
      "chocoId": "7zip"
    },
    // ... more essential apps
  ]
}
```

---

## 🚀 Usage Guide

### Basic Usage

**Interactive Mode (Recommended):**
```powershell
.\script.bat
```
- Launches with menus
- 20-second countdown auto-selection
- Choose Normal or Dry-Run
- Select All Tasks or Specific numbers

**Unattended Mode:**
```powershell
.\script.bat -NonInteractive
```
- No menus - runs all tasks immediately
- Uses defaults from `main-config.json`

**Dry-Run Mode:**
```powershell
.\script.bat -DryRun
```
- Simulates changes without modifying system
- Useful for testing configurations
- Generates reports as if executed

**Specific Tasks:**
```powershell
.\script.bat -TaskNumbers "1,3,5"
```
- Executes only tasks 1, 3, and 5
- Useful for selective maintenance

### Advanced Usage

**Custom Configuration Path:**
```powershell
.\MaintenanceOrchestrator.ps1 -ConfigPath "C:\CustomConfig"
```

**Custom Log Path:**
```powershell
.\MaintenanceOrchestrator.ps1 -LogFilePath "C:\Logs\maintenance.log"
```

**Programmatic Execution:**
```powershell
# Example: Automated daily maintenance
$result = & .\MaintenanceOrchestrator.ps1 -NonInteractive -DryRun:$false
if ($result.Success) {
    Write-Host "Maintenance completed successfully"
}
```

---

## 📊 Reports & Outputs

### Generated Reports

**HTML Report** - `temp_files/reports/Maintenance_Report_[timestamp].html`
- Interactive dashboard with glassmorphism design
- Module cards with expand/collapse
- Charts & visualizations
- Before/after comparisons
- Error analysis section

**Text Report** - `temp_files/reports/Maintenance_Report_[timestamp].txt`
- Plain-text summary
- Module execution results
- Error summary
- Health scores

**JSON Export** - `temp_files/reports/Maintenance_Report_[timestamp].json`
- Machine-readable data
- Full execution details
- Metrics & statistics
- For integration with other tools

**Summary Report** - `temp_files/reports/Maintenance_Report_[timestamp]_summary.txt`
- One-page quick overview
- Key metrics only
- For email/notification

### Logs Structure

```
temp_files/logs/
├── maintenance.log              # Central orchestrator log
├── bloatware-removal/
│   └── execution.log           # Module-specific log
├── essential-apps/
│   └── execution.log
├── system-optimization/
│   └── execution.log
└── [module]/
    └── execution.log
```

---

## 🔐 Security & Safety

### Built-in Safety Features

✅ **Administrator Verification** - Ensures proper privileges  
✅ **System Restore Points** - Optional before changes  
✅ **Dry-Run Mode** - Test without modifying system  
✅ **Extensive Logging** - Complete audit trail  
✅ **Error Recovery** - Graceful fallback mechanisms  
✅ **Diff-Based Processing** - Only process verified changes  

### Best Practices

1. **Always test with Dry-Run first**
   ```powershell
   .\script.bat -DryRun
   ```

2. **Review bloatware list before removal**
   - Edit `config/lists/bloatware-list.json`
   - Remove apps you want to keep

3. **Create System Restore Point**
   - Enable in `main-config.json`: `"createSystemRestorePoint": true`

4. **Monitor execution logs**
   - Check `temp_files/logs/` for errors
   - Review HTML report for warnings

5. **Keep backups of configurations**
   - Version control `config/` directory
   - Test configuration changes in isolated environment

---

## 🐛 Troubleshooting

### Common Issues

**1. "Administrator privileges required"**
```
Solution: Run script.bat as Administrator or use auto-elevation
```

**2. "Module failed to load"**
```
Check: PowerShell execution policy
Fix: Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
```

**3. "Configuration file not found"**
```
Check: Project structure is intact
Verify: config/settings/ and config/lists/ exist
```

**4. "WinGet/Choco not found"**
```
Solution: Install package managers first
- WinGet: Install via Microsoft Store (App Installer)
- Chocolatey: https://chocolatey.org/install
```

**5. "Report generation failed"**
```
Check: temp_files/processed/ has data
Verify: Template files exist in config/templates/
```

### Debug Mode

Enable detailed logging:
```json
// logging-config.json
{
  "verbosity": {
    "currentLevel": "Debug"
  }
}
```

---

## 🔄 Module Development Guide

### Creating a New Type2 Module

**Template:**
```powershell
#Requires -Version 7.0

function Invoke-MyNewModule {
    [CmdletBinding()]
    param(
        [Parameter()]
        [switch]$DryRun
    )
    
    # 1. Import CoreInfrastructure
    $CoreInfraPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'core\CoreInfrastructure.psm1'
    Import-Module $CoreInfraPath -Force -Global
    
    # 2. Run Type1 audit (if exists)
    $auditResults = Invoke-MyNewModuleAudit
    
    # 3. Process items
    foreach ($item in $auditResults.DetectedItems) {
        if ($DryRun) {
            Write-LogEntry -Level 'INFO' -Component 'MY-MODULE' -Message "DRY-RUN: Would process $item"
        } else {
            # Actual system change
            Process-Item $item
        }
    }
    
    # 4. Return results
    return @{
        Status = 'Success'
        TotalOperations = $auditResults.DetectedItems.Count
        DurationSeconds = 10.5
    }
}

Export-ModuleMember -Function 'Invoke-MyNewModule'
```

### Module Checklist

- [ ] Follow naming convention: `Invoke-[ModuleName]`
- [ ] Import CoreInfrastructure for paths & logging
- [ ] Use `Write-LogEntry` for structured logging
- [ ] Support `-DryRun` parameter
- [ ] Return standardized result object
- [ ] Export function with `Export-ModuleMember`
- [ ] Add to `MaintenanceOrchestrator.ps1` module list

---

## 📚 API Reference

### Core Infrastructure

```powershell
# Path Management
Initialize-GlobalPathDiscovery -HintPath $ScriptRoot
$paths = Get-MaintenancePaths
$auditPath = Get-AuditResultsPath -ModuleName 'BloatwareDetection'
Save-DiffResults -ModuleName 'BloatwareRemoval' -DiffData $data

# Configuration
$config = Get-MainConfiguration
$bloatware = Get-BloatwareConfiguration
$apps = Get-EssentialAppsConfiguration

# Logging
Write-LogEntry -Level 'INFO' -Component 'MODULE' -Message 'Message' -Data @{ Key = 'Value' }
$context = Start-PerformanceTracking -OperationName 'Task' -Component 'MODULE'
Complete-PerformanceTracking -Context $context -Status 'Success'
```

### Log Aggregation

```powershell
# Session Management
Start-ResultCollection -SessionId $sessionId
$result = New-ModuleResult -ModuleName 'Module' -Status 'Success' -ItemsProcessed 10
Add-ModuleResult -Result $result
$allResults = Get-AggregatedResults
Complete-ResultCollection -ExportPath "path/to/results.json"
```

### User Interface

```powershell
# Interactive Menus
$menuResult = Show-MainMenu -CountdownSeconds 20 -AvailableTasks $tasks
# Returns: @{ DryRun = $false; SelectedTasks = @(1,2,3) }

# Progress Display
Show-Progress -Activity "Installing Apps" -Status "App 3 of 10" -PercentComplete 30

# Result Summary
Show-ResultSummary -Title "Maintenance Complete" -Results @{ Success=5; Failed=1 }
```

### Report Generation

```powershell
# Generate Reports
$result = New-MaintenanceReport -OutputPath "path/to/report.html" -UseEnhancedReports
# Returns: @{ Success=$true; HtmlReport="...", TextReport="...", Duration=45.2 }

# Process Logs First
Invoke-LogProcessing -Force

# Then Generate Reports
New-MaintenanceReport -OutputPath $reportPath -EnableFallback
```

---

## 📈 Performance & Optimization

### Caching Strategy

**LogProcessor Cache:**
- TTL: 30 minutes
- Max Size: 100MB
- Batch Size: 50 items
- Auto-cleanup on 10th batch

**Inventory Cache:**
- Session-based: 5 minutes
- Reduces redundant WMI/CIM calls
- Stored in `temp_files/inventory/`

### Performance Tips

1. **Use batch operations** - Process items in groups
2. **Enable caching** - `$UseInventoryCache = $true`
3. **Parallel processing** - Where supported (bloatware removal)
4. **Minimize disk I/O** - Cache frequently accessed data
5. **Optimize regex** - Use compiled regex for repeated matches

### Metrics Tracking

Automatic performance tracking:
- Module execution duration
- Items processed per second
- Memory usage (optional)
- CPU usage (optional)

View in HTML report → Performance section

---

## 🧪 Testing

### Manual Testing

**Dry-Run Test:**
```powershell
.\script.bat -DryRun -TaskNumbers "1,2,3"
```

**Module-Specific Test:**
```powershell
Import-Module .\modules\type2\BloatwareRemoval.psm1
Invoke-BloatwareRemoval -DryRun
```

### Validation Tests

**Configuration Validation:**
```powershell
Test-ConfigurationIntegrity
Test-ConfigurationSchema -ConfigObject $config -ConfigName "main-config.json"
```

**Path Validation:**
```powershell
Test-MaintenancePathsIntegrity
```

**Template Validation:**
```powershell
$templates = Get-HtmlTemplates -UseEnhanced
if ($templates.Main -and $templates.CSS) { "✓ Templates OK" }
```

---

## 🔮 Future Enhancements

### Planned Features

- [ ] **Scheduled Task Integration** - Auto-schedule monthly maintenance
- [ ] **Email Notifications** - Send reports via SMTP
- [ ] **Remote Execution** - Execute on remote machines via PowerShell Remoting
- [ ] **REST API** - Web interface for triggering maintenance
- [ ] **Database Logging** - Store results in SQL Server/SQLite
- [ ] **Machine Learning** - Predict optimization recommendations
- [ ] **Cloud Sync** - Backup reports to OneDrive/Azure
- [ ] **Multi-Language Support** - Localization for international use

### Contribution Guidelines

1. Fork repository
2. Create feature branch (`feature/amazing-feature`)
3. Follow PowerShell best practices
4. Add comprehensive comments
5. Test with `-DryRun` first
6. Update documentation
7. Submit pull request

---

## 📝 Changelog

### Version 3.0.0 (Current)
- ✅ Split architecture (LogProcessor + ReportGenerator)
- ✅ Enhanced LogAggregator with correlation tracking
- ✅ Modern dashboard reports with glassmorphism design
- ✅ Session-based result collection
- ✅ Global path discovery system
- ✅ Comprehensive error handling
- ✅ Configuration schema validation

### Version 2.0.0
- Modular architecture with Type1/Type2 separation
- Interactive menu system with countdown
- HTML report generation
- Dry-run mode support

### Version 1.0.0
- Initial release
- Basic bloatware removal
- Essential apps installation
- System optimization

---

## 📞 Support & Contact

**Project:** Windows Maintenance Automation  
**Repository:** script_mentenanta  
**Author:** Bogdan Ichim (ichimbogdancristian)  

**Issues:** Open GitHub issue for bug reports or feature requests  
**Documentation:** Refer to module inline comments for detailed API docs  

---

## 📄 License

This project is a personal automation tool created by Bogdan Ichim for Windows system maintenance. 

**Usage Rights:** Free for personal use. Modification and distribution permitted with attribution.

---

**Last Updated:** November 30, 2025  
**Documentation Version:** 1.0.0  
**Project Version:** 3.0.0
