# GitHub Copilot Instructions for Windows Maintenance Automation System

## ✅ Diagnostics and Analyzer Policy (Mandatory)

When editing or adding PowerShell code:

1. Run PSScriptAnalyzer on all modules and the orchestrator after each change set.
2. Review VS Code diagnostics and resolve all new errors/warnings before completion.
3. Do not introduce unapproved verbs, missing ShouldProcess, unused parameters, or inconsistent whitespace.
4. Keep OutputType attributes accurate for all public functions.

Required commands:

```
pwsh -NoProfile -ExecutionPolicy Bypass -Command "Invoke-ScriptAnalyzer -Path .\modules -Recurse -Settings .\PSScriptAnalyzerSettings.psd1; Invoke-ScriptAnalyzer -Path .\MaintenanceOrchestrator.ps1 -Settings .\PSScriptAnalyzerSettings.psd1"
```

Diagnostics workflow:
- Check VS Code diagnostics after edits.
- Fix all issues introduced by the current change set.
- If a warning must remain, document the rationale in the code.

Common errors to avoid:
- Unapproved verbs (use Get/Set/New/Invoke/Test/Start/Stop/Initialize).
- Missing SupportsShouldProcess on state-changing functions.
- Unused parameters.
- Incorrect or missing OutputType attributes.
- Inconsistent whitespace around operators.

---

## 🚨 Critical Rules & Gotchas

### MUST DO

1. ✅ **Always import CoreInfrastructure first** in any new module
2. ✅ **Use Write-LogEntry** for all logging (structured, traceable)
3. ✅ **Support -DryRun parameter** in Type2 modules
4. ✅ **Return standardized result objects** from modules
5. ✅ **Use Get-AuditResultsPath** for Type1 output paths
6. ✅ **Use Get-SessionPath** for Type2 output paths
7. ✅ **Export functions explicitly** with Export-ModuleMember
8. ✅ **Add comprehensive .SYNOPSIS/.DESCRIPTION** headers
9. ✅ **Use [CmdletBinding()]** for advanced function features
10. ✅ **Validate configuration** before using (Test-ConfigurationSchema)

### NEVER DO

1. ❌ **Don't hardcode paths** - always use path discovery functions
2. ❌ **Don't use Write-Host** for operation logging (use Write-LogEntry)
3. ❌ **Don't skip error handling** - wrap risky operations in try-catch
4. ❌ **Don't modify system without DryRun check**
5. ❌ **Don't create custom path structures** - use standardized locations
6. ❌ **Don't skip module exports** - explicitly export all public functions
7. ❌ **Don't use Get-WmiObject** - use Get-CimInstance (PowerShell 7 best practice)
8. ❌ **Don't assume modules are loaded** - import CoreInfrastructure explicitly
9. ❌ **Don't write logs to random locations** - use Get-SessionPath
10. ❌ **Don't break backward compatibility** without version increment

### Common Pitfalls

**Pitfall 1: Path discovery not initialized**
```powershell
# ❌ Wrong
$configPath = Join-Path $PSScriptRoot '..\config'

# ✅ Correct
Initialize-GlobalPathDiscovery
$configPath = Get-MaintenancePath 'ConfigRoot'
```

**Pitfall 2: Missing null checks**
```powershell
# ❌ Wrong
$value = $config.execution.countdownSeconds

# ✅ Correct
$value = if ($config -and $config.execution) { 
    $config.execution.countdownSeconds ?? 20 
} else { 20 }
```

**Pitfall 3: Incorrect module result structure**
```powershell
# ❌ Wrong
return "Success"

# ✅ Correct
return @{
    Status = 'Success'
    TotalOperations = 10
    SuccessfulOperations = 9
    DurationSeconds = 5.2
}
```

---

## 🎯 Project Context

This is a **PowerShell 7+ enterprise-grade Windows maintenance automation system** with a modular, 3-tier architecture. The system automates bloatware removal, essential software installation, system optimization, privacy controls, and Windows updates.

**Current Version:** 4.0.0 (Phase C Complete - OS-Specific Enhancements)  
**Primary Language:** PowerShell 7.0+  
**Target Platform:** Windows 10/11  
**Author:** Bogdan Ichim

---

## 📋 Architecture Overview

### 3-Tier Modular System

```
┌─────────────────────────────────────────────────┐
│  LAYER 1: Execution (Entry Point)              │
│  - script.bat → MaintenanceOrchestrator.ps1    │
└─────────────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────────────┐
│  LAYER 2: Core Infrastructure (Phase 1 Enhanced)│
│  - CoreInfrastructure (paths, config, logging) │
│  - ModuleRegistry (auto-discovery) ⭐ NEW      │
│  - CommonUtilities (shared helpers) ⭐ NEW     │
│  - LogAggregator (result collection)           │
│  - LogProcessor (data processing)              │
│  - ReportGenerator (HTML/text reports)         │
│  - UserInterface (menus, progress)             │
└─────────────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────────────┐
│  LAYER 3: Operational Modules                  │
│  - Type1 (Audit - read-only)                   │
│  - Type2 (Action - system modification)        │
└─────────────────────────────────────────────────┘
```

### Phase 1 Enhancements (February 2026)

✅ **ModuleRegistry.psm1** - Automatic module discovery & validation  
✅ **CommonUtilities.psm1** - Shared helper functions (eliminated ~200 lines duplication)  
✅ **ShutdownManager merged** - Consolidated into CoreInfrastructure  
✅ **Orchestrator enhanced** - Dynamic module loading with dependency validation

### Phase 2 Enhancements (February 2026)

✅ **JSON Schema Validation** - Draft-07 schemas for all configurations  
✅ **Test-ConfigurationWithJsonSchema** - Centralized validation function  
✅ **Test-AllConfigurationsWithSchema** - Batch validation support  
✅ **Orchestrator integration** - Fail-fast validation before execution

### Phase 3 Enhancements (February 2026)

✅ **Centralized Schemas** - All schemas in `config/schemas/` directory  
✅ **Subdirectory Organization** - Configs organized by module under `config/lists/`  
✅ **Environment-Specific Configs** - Dev/Prod/Test profiles in `config/settings/environments/`  
✅ **Enhanced Path Discovery** - Multi-tier fallback with backward compatibility  
✅ **Schema Auto-Discovery** - Centralized-first approach with legacy fallback

### Phase 4 Enhancements: Reporting Refactoring (February 2026)

✅ **Phase 1 Complete: TemplateEngine.psm1** - Centralized template management  
  - Template caching (~90% faster repeated loads)  
  - Multi-tier path resolution (Phase 3 aware)  
  - Standardized placeholder replacement  
  - Template validation and integrity checks  
  - Embedded fallback templates for reliability  
  - **Test Coverage:** 32/32 tests passing (100%)  
  - **Impact:** -480 lines from ReportGenerator, +972 lines new module

⏳ **Phase 2 Pending: HTML Component Library** - Extract reusable HTML components  
⏳ **Phase 3 Pending: Chart Data Provider** - Extract chart data formatting  
⏳ **Phase 4 Pending: LogProcessor Analytics** - Enhanced analytics capabilities

### Phase C Enhancements: OS-Specific Intelligence (February 2026)

✅ **Phase C.1 Complete: OS Detection** - Windows version detection  
  - Get-WindowsVersionContext function in CoreInfrastructure  
  - Windows 10/11 differentiation with build numbers  
  - Feature availability mapping (TPM 2.0, Android Apps, Snap Layouts, etc.)  
  - Comprehensive OS context object with metadata  

✅ **Phase C.2 Complete: Advanced Configuration** - JSON schema validation  
  - Draft-07 JSON schemas for all configurations  
  - Centralized schema validation (Test-ConfigurationWithJsonSchema)  
  - Fail-fast validation before execution  
  - Phase 3 path discovery integration  

✅ **Phase C.3 Complete: Intelligent Orchestration** - Audit-first execution  
  - ExecutionPlanner.psm1 (620 lines) - Intelligent task selection  
  - 3 execution modes: Intelligent/Manual/Audit-Only  
  - Automatic module prioritization based on audit results  
  - Time estimation and resource optimization  
  - **Test Coverage:** 16/16 tests passing (100% + 5/5 regression)  
  - **Impact:** -47% to -86% time savings on typical systems  

✅ **Phase C.4 Complete: OS-Specific Recommendations** - Enhanced reporting  
  - OSRecommendations.psm1 (609 lines) - Windows 10/11 tailored advice  
  - ReportGenerator integration with OS context display  
  - Template enhancements (OS version in header, recommendations section)  
  - Comprehensive CSS styling (~310 new lines) with glassmorphism design  
  - 12+ recommendation rules (High/Medium/Low priority)  
  - OS-specific badges, feature indicators, priority color coding  
  - **Test Coverage:** 45/45 tests passing (100%)  
  - **Impact:** +0.28s report generation overhead, enhanced user guidance

### Critical Design Patterns

1. **Type1/Type2 Separation**
   - Type1 = Read-only audit/inventory modules
   - Type2 = System-modifying action modules
   - Type2 modules internally call Type1 for detection

2. **Global Path Discovery**
   - All paths managed via environment variables
   - `$env:MAINTENANCE_PROJECT_ROOT`, `$env:MAINTENANCE_TEMP_ROOT`, etc.
   - Centralized via `CoreInfrastructure.psm1`

3. **Result Aggregation**
   - `LogAggregator.psm1` collects all module results
   - Standardized schema: `New-ModuleResult` creates uniform objects
   - Correlation tracking via unique session IDs

4. **Split Report Generation**
   - `LogProcessor.psm1` = Data processing (Type1)
   - `ReportGenerator.psm1` = Rendering (Type1)
   - Clean separation of concerns

5. **Session Management**
   - GUID-based session tracking
   - All outputs tagged with session ID
   - Enables traceability and parallel execution analysis

6. **Configuration Organization (Phase 3)**
   - Centralized schemas: `config/schemas/` for all `.schema.json` files
   - Subdirectory structure: `config/lists/{module}/{config}.json`
   - Environment profiles: `config/settings/environments/{env}.json`
   - Multi-tier path fallback: Phase 3 → Phase 2 → Legacy → Defaults
   - Schema auto-discovery: Centralized first, then legacy location

7. **Template Management (Phase 4.1)**
   - `TemplateEngine.psm1` - Centralized template loading and caching
   - Template caching: ~90% faster on repeated loads
   - Multi-tier path resolution: config/templates/ → config/templates/components/ → templates/ (legacy)
   - Standardized placeholder replacement: `{{PLACEHOLDER}}` format
   - Template validation with required placeholder checking
   - Embedded fallback templates for reliability

8. **OS-Specific Intelligence (Phase C.1-C.4)**
   - `Get-WindowsVersionContext` - Windows 10/11 detection with feature mapping
   - `ExecutionPlanner.psm1` - Audit-first intelligent orchestration
   - `OSRecommendations.psm1` - OS-aware recommendation engine (12+ rules)
   - ReportGenerator OS integration - Version badges, recommendations section
   - Template enhancements: `{{OS_VERSION}}`, `{{OS_RECOMMENDATIONS}}` placeholders
   - Priority-based recommendations: High/Medium/Low with color coding

---

## 🔧 Key File Locations

### Core Modules (Always Load These First)
```
modules/core/
├── CoreInfrastructure.psm1    # Foundation - paths, config, logging, OS detection
├── TemplateEngine.psm1         # Template management (Phase 4.1)
├── OSRecommendations.psm1      # OS-specific recommendations (Phase C.4) ⭐ NEW
├── ExecutionPlanner.psm1       # Intelligent task planning (Phase C.3) ⭐ NEW
├── LogAggregator.psm1         # Result collection (v3.1)
├── LogProcessor.psm1          # Data processing pipeline
├── ReportGenerator.psm1       # Report rendering engine with OS integration
├── UserInterface.psm1         # UI & menus
└── ModernReportGenerator.psm1 # Modern dashboard (v5.0)
```

### Operational Modules
```
modules/type1/                 # Audit/Inventory (read-only)
├── BloatwareDetectionAudit.psm1
├── EssentialAppsAudit.psm1
├── SystemOptimizationAudit.psm1
└── ... (14 total)

modules/type2/                 # Action (system modification)
├── BloatwareRemoval.psm1
├── EssentialApps.psm1
├── SystemOptimization.psm1
└── ... (8 total)
```

### Configuration Files (Phase 3 Structure)
```
config/
├── schemas/                    # ⭐ NEW - Centralized JSON Schemas
│   ├── main-config.schema.json
│   ├── logging-config.schema.json
│   ├── security-config.schema.json
│   ├── bloatware-list.schema.json
│   ├── essential-apps.schema.json
│   ├── app-upgrade-config.schema.json
│   └── system-optimization-config.schema.json
├── settings/
│   ├── main-config.json       # Primary configuration
│   ├── logging-config.json    # Logging verbosity
│   ├── security-config.json   # Security baseline
│   └── environments/          # ⭐ NEW - Environment profiles
│       ├── development.json   # Dev settings (dry-run enabled)
│       ├── production.json    # Prod settings (live execution)
│       └── testing.json       # Test settings
├── lists/                     # ⭐ REORGANIZED - Subdirectories per module
│   ├── bloatware/
│   │   └── bloatware-list.json
│   ├── essential-apps/
│   │   └── essential-apps.json
│   ├── system-optimization/
│   │   └── system-optimization-config.json
│   └── app-upgrade/
│       └── app-upgrade-config.json
└── templates/
    ├── modern-dashboard.html   # Modern report template
    ├── modern-dashboard.css    # Glassmorphism styles
    └── module-card.html        # Module card template
```

### Runtime Directories
```
temp_files/
├── data/           # Type1 audit results (JSON)
├── logs/           # Type2 execution logs (per-module)
├── reports/        # Generated HTML/text reports
├── processed/      # Processed data for reports
├── inventory/      # System inventory snapshots
└── temp/           # Temporary processing files
```

---

## 🎨 Coding Standards & Conventions

### PowerShell Best Practices

1. **Function Naming**
   ```powershell
   # ✅ Approved Verbs Only (Get, Set, New, Invoke, Test, etc.)
   function Get-SystemInformation { }
   function Invoke-BloatwareRemoval { }
   function Test-ConfigurationIntegrity { }
   
   # ❌ Avoid Custom Verbs
   function Fetch-Data { }        # Use Get-Data
   function Execute-Task { }      # Use Invoke-Task
   ```

2. **Parameter Validation**
   ```powershell
   function My-Function {
       [CmdletBinding()]
       param(
           [Parameter(Mandatory=$true)]
           [ValidateNotNullOrEmpty()]
           [string]$RequiredParam,
           
           [Parameter()]
           [ValidateSet('Option1', 'Option2')]
           [string]$LimitedChoices = 'Option1',
           
           [switch]$DryRun
       )
   }
   ```

3. **Error Handling**
   ```powershell
   try {
       # Risky operation
       $result = Get-SomethingDangerous -ErrorAction Stop
   }
   catch [System.UnauthorizedAccessException] {
       Write-LogEntry -Level 'ERROR' -Component 'MODULE' -Message "Access denied: $_"
       throw
   }
   catch {
       Write-LogEntry -Level 'ERROR' -Component 'MODULE' -Message "Unexpected error: $_"
       return @{ Success = $false; Error = $_.Exception.Message }
   }
   ```

4. **Structured Logging**
   ```powershell
   # ✅ Always use Write-LogEntry (from CoreInfrastructure)
   Write-LogEntry -Level 'INFO' -Component 'MODULE-NAME' -Message "Operation started" -Data @{ ItemCount = 10 }
   
   # ❌ Don't use raw Write-Host/Write-Output for important operations
   Write-Host "Starting..."  # Only for user-facing UI messages
   ```

5. **Module Exports**
   ```powershell
   # At end of module file
   Export-ModuleMember -Function @(
       'Invoke-ModuleName',
       'Get-ModuleStatus',
       'Test-ModulePrerequisites'
   )
   
   # Don't export internal helpers
   ```

### Naming Conventions

| Type | Convention | Example |
|------|-----------|---------|
| Functions | `Verb-NounName` | `Get-AuditResultsPath` |
| Modules | `PascalCase.psm1` | `CoreInfrastructure.psm1` |
| Variables | `$camelCase` | `$sessionId`, `$moduleResults` |
| Constants | `$PascalCase` | `$ConfigPath`, `$TempRoot` |
| Private Functions | `Verb-NounName` (internal) | `ConvertTo-Hashtable` |
| Log Components | `UPPER-CASE` | `ORCHESTRATOR`, `TYPE1`, `BLOATWARE` |

### Comment Standards

```powershell
<#
.SYNOPSIS
    Brief one-line description

.DESCRIPTION
    Detailed description of what the function does.
    Include architecture context, dependencies, and usage patterns.

.PARAMETER ParamName
    Description of parameter

.OUTPUTS
    [Type] Description of return value

.EXAMPLE
    PS> Example-Function -Param "Value"
    
    Description of what this example demonstrates

.NOTES
    Module Type: Core/Type1/Type2
    Architecture: v3.0 context
    Dependencies: List required modules
#>
```

---

## 🔄 Common Development Patterns

### Pattern 1: Creating a New Type2 Module

```powershell
#Requires -Version 7.0

<#
.SYNOPSIS
    MyNewModule - Brief description
.DESCRIPTION
    Detailed description of module purpose
#>

# Import CoreInfrastructure for paths, config, logging
$CoreInfraPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'core\CoreInfrastructure.psm1'
if (Test-Path $CoreInfraPath) {
    Import-Module $CoreInfraPath -Force -Global
}

function Invoke-MyNewModule {
    [CmdletBinding()]
    param(
        [Parameter()]
        [switch]$DryRun
    )
    
    Write-LogEntry -Level 'INFO' -Component 'MY-MODULE' -Message "Starting MyNewModule execution"
    
    try {
        # 1. Run Type1 audit internally (if exists)
        $auditResults = Invoke-MyNewModuleAudit
        
        # 2. Get standardized audit results path
        $auditPath = Get-AuditResultsPath -ModuleName 'MyNewModule'
        
        # 3. Process detected items
        $processedCount = 0
        foreach ($item in $auditResults.DetectedItems) {
            if ($DryRun) {
                Write-LogEntry -Level 'INFO' -Component 'MY-MODULE' -Message "DRY-RUN: Would process $($item.Name)"
            } else {
                # Perform actual system change
                try {
                    Process-Item $item
                    $processedCount++
                    Write-LogEntry -Level 'SUCCESS' -Component 'MY-MODULE' -Message "Processed: $($item.Name)"
                } catch {
                    Write-LogEntry -Level 'ERROR' -Component 'MY-MODULE' -Message "Failed to process $($item.Name): $_"
                }
            }
        }
        
        # 4. Return standardized result object
        return @{
            Status = 'Success'
            TotalOperations = $auditResults.DetectedItems.Count
            SuccessfulOperations = $processedCount
            FailedOperations = $auditResults.DetectedItems.Count - $processedCount
            DurationSeconds = 10.5
        }
    }
    catch {
        Write-LogEntry -Level 'ERROR' -Component 'MY-MODULE' -Message "Module execution failed: $_"
        return @{
            Status = 'Failed'
            Error = $_.Exception.Message
        }
    }
}

Export-ModuleMember -Function 'Invoke-MyNewModule'
```

### Pattern 2: Using LogAggregator for Results

```powershell
# In MaintenanceOrchestrator.ps1 or calling script

# Initialize session
Start-ResultCollection -SessionId $sessionId

# Execute module and collect result
$result = Invoke-MyModule -DryRun:$DryRun

# Create standardized result object
$moduleResult = New-ModuleResult `
    -ModuleName 'MyModule' `
    -Status $result.Status `
    -ItemsDetected $result.TotalOperations `
    -ItemsProcessed $result.SuccessfulOperations `
    -DurationSeconds $result.DurationSeconds

# Add to aggregated results
Add-ModuleResult -Result $moduleResult

# At end of all modules
$sessionData = Complete-ResultCollection -ExportPath "temp_files/processed/aggregated-results.json"
```

### Pattern 3: Configuration Loading (Phase 3)

```powershell
# Always use CoreInfrastructure functions - Phase 3 aware
$mainConfig = Get-MainConfiguration
$bloatwareConfig = Get-BloatwareConfiguration    # Loads from config/lists/bloatware/
$essentialAppsConfig = Get-EssentialAppsConfiguration  # Loads from config/lists/essential-apps/

# Load environment-specific configuration
$envConfig = Get-Content "config/settings/environments/development.json" | ConvertFrom-Json
$isDryRun = $envConfig.execution.enableDryRun  # true for dev, false for prod

# Access nested properties safely
$countdownSeconds = $mainConfig.execution.countdownSeconds ?? 20
$dryRunEnabled = $mainConfig.execution.enableDryRun ?? $true

# Validate configuration with centralized schema (Phase 3)
$validation = Test-ConfigurationWithJsonSchema `
    -ConfigFilePath "config/lists/bloatware/bloatware-list.json"
# Schema auto-discovered from config/schemas/bloatware-list.schema.json

if (-not $validation.IsValid) {
    Write-LogEntry -Level 'ERROR' -Component 'CONFIG' -Message "Invalid configuration: $($validation.ErrorDetails)"
}
```

### Pattern 4: Template Loading (Phase 4.1)

```powershell
# Always use TemplateEngine for template management
Import-Module .\modules\core\TemplateEngine.psm1 -Force

# Load single template (auto-cached)
$mainTemplate = Get-Template -TemplateName 'modern-dashboard.html' -TemplateType 'Main'

# Load complete template bundle
$bundle = Get-TemplateBundle  # Standard templates
$enhancedBundle = Get-TemplateBundle -UseEnhanced  # Enhanced templates

# Templates are cached - second load is ~90% faster
$mainTemplate2 = Get-Template -TemplateName 'modern-dashboard.html' -TemplateType 'Main'  # From cache

# Replace placeholders in template
$replacements = @{
    TITLE = 'System Maintenance Report'
    DATE = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    MODULE_COUNT = 15
    STATUS = 'Success'
}
$rendered = Invoke-PlaceholderReplacement -Template $mainTemplate -Replacements $replacements

# Validate template has required placeholders
$validation = Test-TemplateIntegrity `
    -TemplateContent $mainTemplate `
    -RequiredPlaceholders @('TITLE', 'DATE', 'MODULE_COUNT')

if (-not $validation.IsValid) {
    Write-LogEntry -Level 'ERROR' -Component 'MODULE' `
        -Message "Template missing placeholders: $($validation.MissingPlaceholders -join ', ')"
}

# Get cache statistics (for debugging/monitoring)
$stats = Get-TemplateCacheStats
Write-LogEntry -Level 'DEBUG' -Component 'MODULE' `
    -Message "Template cache: $($stats.CacheSize) entries, $($stats.HitRate)% hit rate"

# Clear cache after template file updates
Clear-TemplateCache -TemplateName 'modern-dashboard.html' -Confirm:$false
```

### Pattern 5: Error Handling with Fallback

```powershell
# Always use standardized path functions
$auditPath = Get-AuditResultsPath -ModuleName 'BloatwareDetection'
$sessionDataPath = Get-SessionPath -Category 'data' -FileName 'results.json'
$logPath = Get-SessionPath -Category 'logs' -SubCategory 'module-name' -FileName 'execution.log'

# Access global paths
$tempRoot = $env:MAINTENANCE_TEMP_ROOT
$configRoot = $env:MAINTENANCE_CONFIG_ROOT

# Or via Get-MaintenancePaths
$paths = Get-MaintenancePaths
$projectRoot = $paths.ProjectRoot
```

### Pattern 5: Error Handling with Fallback

```powershell
function Process-DataWithFallback {
    try {
        # Primary operation
        $data = Get-ProcessedData
        return $data
    }
    catch {
        Write-LogEntry -Level 'WARNING' -Component 'PROCESSOR' -Message "Primary method failed, trying fallback: $_"
        
        try {
            # Fallback operation
            $data = Get-RawData
            return $data
        }
        catch {
            Write-LogEntry -Level 'ERROR' -Component 'PROCESSOR' -Message "Both primary and fallback failed: $_"
            
            # Return minimal safe structure
            return @{
                Success = $false
                Error = $_.Exception.Message
                Data = @()
            }
        }
    }
}
```

---

## 🔍 Architecture-Specific Guidance

### When Working with CoreInfrastructure.psm1

**Purpose:** Foundation module - paths, config, logging  
**Critical Functions:**
- `Initialize-GlobalPathDiscovery` - MUST be called first
- `Get-MaintenancePaths` - Returns all paths
- `Get-AuditResultsPath` - Type1 standardized output
- `Save-DiffResults` - Type2 diff persistence
- `Write-LogEntry` - Structured logging

**Usage Context:**
```powershell
# Every module should start with:
$CoreInfraPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'core\CoreInfrastructure.psm1'
Import-Module $CoreInfraPath -Force -Global

# Then can use any CoreInfrastructure function
$paths = Get-MaintenancePaths
$config = Get-MainConfiguration
```

### When Working with LogAggregator.psm1

**Purpose:** Result collection & correlation (v3.1)  
**Key Workflow:**
1. `Start-ResultCollection` at orchestrator start
2. Modules return results to orchestrator
3. Orchestrator calls `New-ModuleResult` + `Add-ModuleResult`
4. `Complete-ResultCollection` exports to JSON

**Result Schema:**
```powershell
@{
    ModuleName = "String"
    Status = "Success|Failed|Skipped|DryRun"
    Metrics = @{
        ItemsDetected = Int
        ItemsProcessed = Int
        ItemsSkipped = Int
        ItemsFailed = Int
        DurationSeconds = Decimal
    }
    Results = @{ }  # Module-specific data
    Errors = @()
    Warnings = @()
}
```

### When Working with LogProcessor.psm1

**Purpose:** Data processing pipeline (Type1 - read-only)  
**Pipeline:** Load → Parse → Normalize → Aggregate → Export  
**Key Functions:**
- `Invoke-LogProcessing` - Full pipeline
- `Initialize-ProcessedDataPath` - Ensure processed output paths
- `Get-Type1AuditData` - Load audit results
- `Get-Type2ExecutionLog` - Load execution logs
- `Get-ComprehensiveLogAnalysis` - Parse & analyze
- `Get-ComprehensiveDashboardMetricSet` - Dashboard metrics
- `Get-ExecutionLogErrorReport` - Error aggregation
- `Get-SafeDirectoryContent` - Safe directory enumeration

**Context:**
- Runs AFTER all modules complete
- Reads from `temp_files/data/` and `temp_files/logs/`
- Writes to `temp_files/processed/`
- ReportGenerator consumes its output

### When Working with ReportGenerator.psm1

**Purpose:** Report rendering engine (Type1 - read-only)  
**Key Functions:**
- `New-MaintenanceReport` - Primary entry point
- `Get-HtmlTemplateBundle` - Load templates
- `Get-FallbackTemplateBundle` - Built-in template fallback
- `Get-ProcessedLogData` - Load LogProcessor output

**Template System:**
- Templates in `config/templates/`
- Modern design: `modern-dashboard.html` + `modern-dashboard.css`
- Legacy v4: `report-template-v4-enhanced.html`
- Module cards: `module-card.html`

**Context:**
- Runs AFTER LogProcessor completes
- Reads from `temp_files/processed/`
- Writes to `temp_files/reports/`
- Generates: HTML, Text, JSON, Summary

---

## 📝 Documentation Standards

### Module Header Template

```powershell
<#
.SYNOPSIS
    [Module Name] - [One-line description]

.DESCRIPTION
    [Detailed description of module purpose and functionality]
    
    Architecture Context:
    - Module Type: Core/Type1/Type2
    - Version: 3.0.0
    - Dependencies: [List modules this depends on]

.MODULE ARCHITECTURE
    Purpose:
        [What problem does this solve?]
    
    Dependencies:
        • [Module1.psm1] - [Why needed]
        • [Module2.psm1] - [Why needed]
    
    Exports:
        • [Function1] - [What it does]
        • [Function2] - [What it does]
    
    Import Pattern:
        Import-Module [ModuleName].psm1 -Force [-Global]
        # [Usage context]

    Used By:
        - [Consumer1.ps1] - [How used]
        - [Consumer2.psm1] - [How used]

.EXECUTION FLOW
    1. [Step 1 description]
    2. [Step 2 description]
    ...

.DATA ORGANIZATION
    Input:
        • [Input source 1]
        • [Input source 2]
    
    Output:
        • [Output location 1]
        • [Output location 2]

.NOTES
    Module Type: [Core/Type1/Type2]
    Architecture: v3.0 - [Context]
    Version: [X.Y.Z]
    Author: [Name]
    
    Key Design Patterns:
    - [Pattern 1]
    - [Pattern 2]
#>
```

### Function Comment Template

```powershell
<#
.SYNOPSIS
    [One-line description]

.DESCRIPTION
    [Detailed description of what the function does]
    [Include architecture context if relevant]

.PARAMETER ParamName
    [Description of parameter]
    [Valid values if applicable]
    [Default value if applicable]

.OUTPUTS
    [Type] Description of return value
    [Include structure if complex object]

.EXAMPLE
    PS> [Example-Function] -Param "Value"
    
    [Description of what this example demonstrates]

.EXAMPLE
    PS> [Example-Function] -Param1 "X" -Param2 "Y"
    
    [Description of second example]

.NOTES
    [Additional context]
    [Dependencies]
    [Common pitfalls]
#>
```

---

## 🧪 Testing Guidelines

### Manual Testing Commands

```powershell
# Test dry-run mode
.\script.bat -DryRun

# Test specific tasks
.\script.bat -TaskNumbers "1,3,5"

# Test unattended mode
.\script.bat -NonInteractive

# Test configuration validation
$config = Get-MainConfiguration
Test-ConfigurationSchema -ConfigObject $config -ConfigName "main-config.json"

# Test path discovery
Initialize-GlobalPathDiscovery
$paths = Get-MaintenancePaths
$paths | Format-List

# Test module loading
Import-Module .\modules\type2\BloatwareRemoval.psm1 -Force
Get-Command -Module BloatwareRemoval
```

### Validation Checklist

Before committing changes:
- [ ] Ran with `-DryRun` successfully
- [ ] No PSScriptAnalyzer warnings
- [ ] All functions have `.SYNOPSIS` and `.DESCRIPTION`
- [ ] Error handling with try-catch
- [ ] Logging with Write-LogEntry
- [ ] Path discovery functions used (no hardcoded paths)
- [ ] Configuration validated before use
- [ ] Module exports explicit with Export-ModuleMember
- [ ] Tested in both interactive and non-interactive mode
- [ ] Updated PROJECT.md if architecture changed

---

## 🎓 Learning Resources

### Understanding the Codebase

**Start Here:**
1. Read `PROJECT.md` - Complete architecture overview
2. Read `MaintenanceOrchestrator.ps1` - Entry point & flow
3. Study `CoreInfrastructure.psm1` - Foundation patterns
4. Examine `BloatwareRemoval.psm1` - Type2 module example
5. Review `LogAggregator.psm1` - Result collection pattern

**Key Concepts to Master:**
- PowerShell 7 module system
- Type1 vs Type2 module separation
- Global path discovery pattern
- Result aggregation via LogAggregator
- Split report generation (LogProcessor + ReportGenerator)
- Session management with GUIDs

### PowerShell 7 Resources

- [PowerShell 7 Documentation](https://docs.microsoft.com/powershell)
- [About Modules](https://docs.microsoft.com/powershell/module/microsoft.powershell.core/about/about_modules)
- [Advanced Functions](https://docs.microsoft.com/powershell/module/microsoft.powershell.core/about/about_functions_advanced)
- [Error Handling](https://docs.microsoft.com/powershell/module/microsoft.powershell.core/about/about_try_catch_finally)

---

## 💡 AI Assistant Guidelines

### When Generating New Code

1. **Always check existing patterns** in similar modules first
2. **Import CoreInfrastructure** at the top of any new module
3. **Use Write-LogEntry** instead of Write-Host for operations
4. **Include comprehensive error handling** with try-catch
5. **Return standardized objects** matching existing module results
6. **Add .SYNOPSIS and .DESCRIPTION** headers to all functions
7. **Follow naming conventions** (Verb-Noun, PascalCase modules, etc.)
8. **Test with -DryRun** before suggesting actual execution

### When Modifying Existing Code

1. **Preserve existing patterns** - don't introduce new paradigms
2. **Maintain backward compatibility** - especially for module exports
3. **Update documentation** if changing module behavior
4. **Keep consistent logging format** - use existing Write-LogEntry calls
5. **Test thoroughly** with both dry-run and actual execution
6. **Update version numbers** if changing public APIs

### When Debugging Issues

1. **Check logs first** - `temp_files/logs/` has detailed execution logs
2. **Validate paths** - ensure path discovery initialized correctly
3. **Check module imports** - verify CoreInfrastructure loaded
4. **Review configuration** - validate JSON syntax and schema
5. **Enable Debug logging** - Set logging-config.json to Debug level
6. **Check PSScriptAnalyzer** - Run for code quality issues

### When Explaining Code

1. **Reference architecture** - Explain which tier/layer code belongs to
2. **Show data flow** - Trace how data moves through the system
3. **Cite patterns** - Point to documented patterns in this file
4. **Provide examples** - Show usage in context of existing modules
5. **Explain dependencies** - Clarify module relationships
6. **Link to PROJECT.md** - Reference comprehensive documentation

---

## 🔗 Quick Reference Links

| Topic | Location |
|-------|----------|
| Project Architecture | `PROJECT.md` |
| Core Infrastructure | `modules/core/CoreInfrastructure.psm1` |
| Result Aggregation | `modules/core/LogAggregator.psm1` |
| Data Processing | `modules/core/LogProcessor.psm1` |
| Report Generation | `modules/core/ReportGenerator.psm1` |
| Main Configuration | `config/settings/main-config.json` |
| Logging Configuration | `config/settings/logging-config.json` |
| Bloatware List | `config/lists/bloatware-list.json` |
| Essential Apps | `config/lists/essential-apps.json` |
| Main Orchestrator | `MaintenanceOrchestrator.ps1` |
| Entry Point | `script.bat` |

---

## 📊 Module Dependency Graph

```
script.bat
    ↓
MaintenanceOrchestrator.ps1
    ↓
CoreInfrastructure.psm1 (Foundation - loads first, includes OS detection)
    ↓
    ├─→ ExecutionPlanner.psm1 (Phase C.3 - Intelligent orchestration) ⭐ NEW
    ├─→ LogAggregator.psm1 (Result collection)
    ├─→ UserInterface.psm1 (UI & menus)
    │
    └─→ Type2 Modules (self-contained)
        ├─→ BloatwareRemoval.psm1
        │   └─→ [Internal] BloatwareDetectionAudit.psm1 (Type1)
        ├─→ EssentialApps.psm1
        │   └─→ [Internal] EssentialAppsAudit.psm1 (Type1)
        └─→ ... (other Type2 modules)
    
After All Modules Complete:
    ↓
LogProcessor.psm1 (Aggregate logs)
    ↓
ReportGenerator.psm1 (Generate reports with OS integration)
    ↓
    └─→ OSRecommendations.psm1 (Phase C.4 - OS-specific recommendations) ⭐ NEW
        └─→ CoreInfrastructure::Get-WindowsVersionContext (OS detection)
```

---

## 🎯 Final Checklist for AI Assistance

When GitHub Copilot assists with this project:

✅ **Understand the context** - This is a modular PowerShell 7 system  
✅ **Follow established patterns** - Don't invent new paradigms  
✅ **Use standardized functions** - CoreInfrastructure paths, logging, config  
✅ **Use TemplateEngine** - All template loading via TemplateEngine module  
✅ **Leverage OS intelligence** - Use Get-WindowsVersionContext for OS-aware features  
✅ **Maintain separation** - Type1 (read) vs Type2 (modify)  
✅ **Comprehensive error handling** - Always wrap risky operations  
✅ **Structured logging** - Use Write-LogEntry consistently  
✅ **Document thoroughly** - Add .SYNOPSIS/.DESCRIPTION headers  
✅ **Export explicitly** - Use Export-ModuleMember  
✅ **Test with DryRun** - Validate before suggesting execution  
✅ **Reference PROJECT.md** - Complete architecture documentation  

---

**Last Updated:** February 7, 2026  
**Instructions Version:** 1.2.0 (Phase C.4 - OS-Specific Recommendations Complete)  
**Project Version:** 4.0.0
