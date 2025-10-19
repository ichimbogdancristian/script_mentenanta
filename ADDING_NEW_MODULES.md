# 📖 **Complete Guide: Adding a New Type2 Module to the Project**

## 🎯 **Overview**

This guide provides step-by-step instructions for adding a new maintenance task (Type2 module) to the Windows Maintenance Automation system. The v3.0 architecture requires specific patterns for proper integration with the orchestrator, reporting system, and global path discovery.

---

## 📋 **Prerequisites Checklist**

Before creating a new module, ensure you have:
- [ ] Administrator privileges on your development machine
- [ ] PowerShell 7+ installed
- [ ] VS Code with PowerShell extension
- [ ] Understanding of the Type1 (detection) → Type2 (action) flow
- [ ] Familiarity with the project's global path system (`$Global:ProjectPaths`)

---

## 🏗️ **Architecture Understanding**

### **Module Hierarchy**
```
MaintenanceOrchestrator.ps1
├── CoreInfrastructure.psm1 (loaded globally by orchestrator)
│   ├── Configuration Management (Get-MainConfig, Get-BloatwareList, etc.)
│   ├── Logging System (Write-LogEntry, Start-PerformanceTracking, etc.)
│   └── File Organization (Get-SessionPath, Initialize-TempFilesStructure, etc.)
│
├── UserInterface.psm1 (loaded globally by orchestrator)
└── ReportGenerator.psm1 (loaded globally by orchestrator)

Type2 Module: YourNewModule.psm1
├── Imports CoreInfrastructure.psm1 with -Global flag
├── Imports YourNewModuleAudit.psm1 (Type1 dependency)
├── Exports Invoke-YourNewModule function
└── Returns standardized result object
```

### **Data Flow Pattern**
```
1. Orchestrator calls: Invoke-YourNewModule -Config $MainConfig [-DryRun]
2. Type2 module triggers: Get-YourNewModuleAnalysis -Config $Config
3. Type1 module detects: Scans system, creates audit data
4. Type1 saves results: temp_files/data/your-new-module-results.json
5. Type2 analyzes: Compares Type1 data against config
6. Type2 creates diff: temp_files/temp/your-new-module-diff.json
7. Type2 executes: Processes items in diff list (if not dry-run)
8. Type2 logs actions: temp_files/logs/your-new-module/execution.log
9. Type2 returns results: { Success, ItemsDetected, ItemsProcessed, Duration }
10. Orchestrator collects logs: Aggregates all data for reporting
11. ReportGenerator processes: Creates comprehensive HTML report
```

---

## 📝 **Step-by-Step Implementation**

### **Step 1: Create Configuration File (if needed)**

If your module requires configuration data, create a JSON file in `config/`:

**File**: `config/your-new-module-config.json`
```json
{
  "moduleEnabled": true,
  "items": [
    {
      "name": "Example Item 1",
      "category": "ExampleCategory",
      "action": "ExampleAction",
      "priority": "high"
    },
    {
      "name": "Example Item 2",
      "category": "ExampleCategory",
      "action": "ExampleAction",
      "priority": "medium"
    }
  ],
  "options": {
    "verbose": false,
    "timeout": 30
  }
}
```

### **Step 2: Add Configuration Loader to CoreInfrastructure**

**File**: `modules/core/CoreInfrastructure.psm1`

Add a configuration loader function in the Configuration Management section:

```powershell
#region Configuration Management

# ... existing functions ...

function Get-YourNewModuleConfiguration {
    <#
    .SYNOPSIS
        Loads your-new-module-config.json configuration
    #>
    [CmdletBinding()]
    param()
    
    if (-not $script:ConfigData -or -not $script:ConfigData.ContainsKey('YourNewModuleConfig')) {
        throw "Configuration system not initialized or YourNewModuleConfig not loaded"
    }
    
    return $script:ConfigData['YourNewModuleConfig']
}

# ... rest of file ...

# Update Export-ModuleMember at the end of file:
Export-ModuleMember -Function @(
    # ... existing exports ...
    'Get-YourNewModuleConfiguration'  # ADD THIS LINE
)
```

**Also update** `Initialize-ConfigSystem` function to load your config:

```powershell
function Initialize-ConfigSystem {
    param([string]$ConfigRootPath)
    
    # ... existing code ...
    
    # Load your new module configuration
    $yourNewModuleConfigPath = Join-Path $ConfigRootPath 'your-new-module-config.json'
    if (Test-Path $yourNewModuleConfigPath) {
        try {
            $yourNewModuleJson = Get-Content $yourNewModuleConfigPath -Raw | ConvertFrom-Json
            $script:ConfigData['YourNewModuleConfig'] = $yourNewModuleJson
        }
        catch {
            Write-Warning "Failed to load your-new-module-config.json: $($_.Exception.Message)"
        }
    }
    
    # ... rest of function ...
}
```

### **Step 3: Create Type1 (Detection) Module**

**File**: `modules/type1/YourNewModuleAudit.psm1`

```powershell
#Requires -Version 7.0

<#
.SYNOPSIS
    Your New Module Audit - Type 1 (Detection/Analysis)

.DESCRIPTION
    Detects and audits [describe what your module detects].
    Part of the v3.0 architecture where Type1 modules provide detection capabilities.

.NOTES
    Module Type: Type 1 (Detection/Analysis)  
    Dependencies: CoreInfrastructure.psm1
    Architecture: v3.0 - Imported by Type2 module
    Author: Your Name
    Version: 1.0.0
#>

using namespace System.Collections.Generic

# v3.0 Type 1 module - imported by Type 2 modules
# Check if CoreInfrastructure functions are available (loaded by Type2 module)
if (Get-Command 'Write-LogEntry' -ErrorAction SilentlyContinue) {
    Write-Verbose "CoreInfrastructure functions detected - using configuration-based functions"
}
else {
    # Non-critical: Function will be available once Type2 module completes global import
    Write-Verbose "CoreInfrastructure global import in progress - Write-LogEntry will be available momentarily"
}

#region Public Functions

<#
.SYNOPSIS
    Performs comprehensive audit of [your detection target]

.DESCRIPTION
    Analyzes system state to identify [what needs to be detected] that match
    configured patterns or requirements.

.PARAMETER Config
    Main configuration object containing module settings

.OUTPUTS
    System.Collections.ArrayList of detected items with metadata

.EXAMPLE
    $results = Get-YourNewModuleAnalysis -Config $mainConfig
#>
function Get-YourNewModuleAnalysis {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Config
    )
    
    Write-Verbose "Starting Your New Module analysis..."
    
    try {
        # Load module-specific configuration
        $moduleConfig = Get-YourNewModuleConfiguration
        
        # Initialize results collection
        $detectedItems = [System.Collections.ArrayList]::new()
        
        # DETECTION LOGIC: Scan system and identify items
        # Example: Scan registry, services, files, etc.
        foreach ($item in $moduleConfig.items) {
            # Your detection logic here
            $isPresent = Test-YourDetectionLogic -Item $item
            
            if ($isPresent) {
                $detectedItem = [PSCustomObject]@{
                    Name        = $item.name
                    Category    = $item.category
                    Action      = $item.action
                    Priority    = $item.priority
                    DetectedAt  = Get-Date -Format 'yyyy-MM-ddTHH:mm:ss'
                    Source      = 'YourSource'  # e.g., Registry, Service, File
                    Path        = 'C:\Example\Path'  # Actual path where found
                    Details     = @{
                        # Additional metadata
                        Version = '1.0.0'
                        Status  = 'Active'
                    }
                }
                [void]$detectedItems.Add($detectedItem)
            }
        }
        
        Write-Verbose "Analysis complete: Found $($detectedItems.Count) items"
        
        return $detectedItems
    }
    catch {
        Write-Error "Your New Module analysis failed: $($_.Exception.Message)"
        return [System.Collections.ArrayList]::new()
    }
}

#endregion

#region Helper Functions

function Test-YourDetectionLogic {
    <#
    .SYNOPSIS
        Tests if a specific item exists on the system
    #>
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Item
    )
    
    # Implement your detection logic here
    # Examples:
    # - Check if a registry key exists
    # - Check if a service is running
    # - Check if a file exists
    # - Check if a scheduled task exists
    
    # Example: Check registry
    try {
        $regPath = "HKLM:\SOFTWARE\Example\$($Item.name)"
        $exists = Test-Path $regPath
        return $exists
    }
    catch {
        return $false
    }
}

#endregion

# Export public functions
Export-ModuleMember -Function @(
    'Get-YourNewModuleAnalysis'
)
```

### **Step 4: Create Type2 (Action) Module**

**File**: `modules/type2/YourNewModule.psm1`

```powershell
#Requires -Version 7.0

<#
.SYNOPSIS
    Your New Module - Type 2 (System Modification)

.DESCRIPTION
    [Describe what your module does to modify the system]
    Implements the v3.0 architecture pattern with internal Type1 dependency.

.NOTES
    Module Type: Type 2 (System Modification)
    Dependencies: YourNewModuleAudit.psm1 (Type1), CoreInfrastructure.psm1
    Requires: Administrator privileges
    Author: Your Name
    Version: 1.0.0
#>

using namespace System.Collections.Generic

# v3.0 Self-contained Type 2 module with internal Type 1 dependency

# Step 1: Import core infrastructure FIRST (REQUIRED) - Global scope for Type1 access
$ModuleRoot = if ($PSScriptRoot) { Split-Path -Parent $PSScriptRoot } else { Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path) }
$CoreInfraPath = Join-Path $ModuleRoot 'core\CoreInfrastructure.psm1'
if (Test-Path $CoreInfraPath) {
    Import-Module $CoreInfraPath -Force -Global -WarningAction SilentlyContinue
}
else {
    Write-Warning "CoreInfrastructure module not found at: $CoreInfraPath"
}

# Step 2: Import corresponding Type 1 module AFTER CoreInfrastructure (REQUIRED)
$Type1ModulePath = Join-Path $ModuleRoot 'type1\YourNewModuleAudit.psm1'
if (Test-Path $Type1ModulePath) {
    Import-Module $Type1ModulePath -Force
}
else {
    throw "Required Type 1 module not found: $Type1ModulePath"
}

# Validate Type1 module loaded correctly
if (-not (Get-Command -Name 'Get-YourNewModuleAnalysis' -ErrorAction SilentlyContinue)) {
    throw "Type 1 module functions not available - ensure YourNewModuleAudit.psm1 is properly imported"
}

#region v3.0 Standardized Execution Function

<#
.SYNOPSIS
    Main execution function - v3.0 Architecture Pattern

.DESCRIPTION
    Standardized entry point that implements the Type2 → Type1 flow:
    1. Calls YourNewModuleAudit (Type1) to detect items
    2. Validates findings and logs results
    3. Executes modification actions (Type2) based on DryRun mode
    4. Returns standardized results for ReportGeneration

.PARAMETER Config
    Main configuration object from orchestrator

.PARAMETER DryRun
    If specified, simulates actions without making system modifications

.OUTPUTS
    Hashtable with Success, ItemsDetected, ItemsProcessed, Duration

.EXAMPLE
    $result = Invoke-YourNewModule -Config $mainConfig
    $result = Invoke-YourNewModule -Config $mainConfig -DryRun
#>
function Invoke-YourNewModule {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Config,
        
        [Parameter(Mandatory = $false)]
        [switch]$DryRun
    )
    
    # Start performance tracking
    $startTime = Get-Date
    $perfContext = $null
    try {
        $perfContext = Start-PerformanceTracking -OperationName 'YourNewModule' -Component 'YOUR-NEW-MODULE'
    }
    catch {
        # Performance tracking is optional
    }
    
    try {
        Write-Verbose "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Starting Your New Module processing..."
        
        # STEP 1: Run Type1 detection
        Write-Verbose "Running Type1 detection analysis..."
        $detectionResults = Get-YourNewModuleAnalysis -Config $Config
        
        # Save Type1 detection results to temp_files/data/
        $detectionDataPath = Join-Path $Global:ProjectPaths.TempFiles "data\your-new-module-results.json"
        $detectionResults | ConvertTo-Json -Depth 10 | Set-Content $detectionDataPath -Force
        Write-Verbose "Saved detection results to: $detectionDataPath"
        
        # STEP 2: Load configuration and create diff
        $moduleConfig = Get-YourNewModuleConfiguration
        $diffList = Compare-DetectedVsConfig -Detected $detectionResults -Config $moduleConfig
        
        # Save diff to temp_files/temp/
        $diffPath = Join-Path $Global:ProjectPaths.TempFiles "temp\your-new-module-diff.json"
        $diffList | ConvertTo-Json -Depth 10 | Set-Content $diffPath -Force
        Write-Verbose "Created diff list with $($diffList.Count) items"
        
        # STEP 3: Initialize execution logging
        $executionLogDir = Join-Path $Global:ProjectPaths.TempFiles "logs\your-new-module"
        if (-not (Test-Path $executionLogDir)) {
            New-Item -Path $executionLogDir -ItemType Directory -Force | Out-Null
        }
        $executionLogPath = Join-Path $executionLogDir "execution.log"
        
        # Log execution start
        $logHeader = @"
========================================
Your New Module Execution Log
Session: $env:MAINTENANCE_SESSION_ID
Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Mode: $(if ($DryRun) { 'DRY-RUN (Simulation)' } else { 'LIVE (Real Modifications)' })
Detected Items: $($detectionResults.Count)
Items to Process: $($diffList.Count)
========================================

"@
        Add-Content -Path $executionLogPath -Value $logHeader
        
        # STEP 4: Process items (real or simulated)
        $processedCount = 0
        $failedCount = 0
        
        if ($diffList.Count -eq 0) {
            $message = "No items found that require processing"
            Add-Content -Path $executionLogPath -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [INFO] $message"
            Write-Verbose $message
        }
        else {
            foreach ($item in $diffList) {
                try {
                    if ($DryRun) {
                        # Simulation mode
                        $message = "DRY-RUN: Would process '$($item.Name)' (Category: $($item.Category), Action: $($item.Action))"
                        Add-Content -Path $executionLogPath -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [DRY-RUN] $message"
                        Write-Verbose $message
                        $processedCount++
                    }
                    else {
                        # Real execution
                        $message = "Processing '$($item.Name)'..."
                        Add-Content -Path $executionLogPath -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [INFO] $message"
                        Write-Verbose $message
                        
                        # PERFORM ACTUAL SYSTEM MODIFICATION HERE
                        $result = Invoke-YourModuleAction -Item $item
                        
                        if ($result.Success) {
                            $successMessage = "SUCCESS: Processed '$($item.Name)' - $($result.Message)"
                            Add-Content -Path $executionLogPath -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [SUCCESS] $successMessage"
                            Write-Verbose $successMessage
                            $processedCount++
                        }
                        else {
                            $errorMessage = "FAILED: Could not process '$($item.Name)' - $($result.Error)"
                            Add-Content -Path $executionLogPath -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [ERROR] $errorMessage"
                            Write-Warning $errorMessage
                            $failedCount++
                        }
                    }
                }
                catch {
                    $errorMessage = "EXCEPTION: Processing '$($item.Name)' failed - $($_.Exception.Message)"
                    Add-Content -Path $executionLogPath -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [ERROR] $errorMessage"
                    Write-Error $errorMessage
                    $failedCount++
                }
            }
        }
        
        # Log completion summary
        $summaryMessage = @"

========================================
Execution Summary
========================================
Total Detected: $($detectionResults.Count)
Successfully Processed: $processedCount
Failed: $failedCount
Duration: $((Get-Date) - $startTime)
========================================
"@
        Add-Content -Path $executionLogPath -Value $summaryMessage
        
        # Complete performance tracking
        if ($perfContext) {
            try {
                Complete-PerformanceTracking -Context $perfContext
            }
            catch {
                # Performance tracking is optional
            }
        }
        
        # STEP 5: Return standardized result
        $executionTime = (Get-Date) - $startTime
        return @{
            Success         = ($failedCount -eq 0)
            ItemsDetected   = $detectionResults.Count
            ItemsProcessed  = $processedCount
            ItemsFailed     = $failedCount
            Duration        = $executionTime.TotalMilliseconds
            DryRun          = $DryRun.IsPresent
            LogPath         = $executionLogPath
        }
    }
    catch {
        Write-Error "Your New Module execution failed: $($_.Exception.Message)"
        
        # Return failure result
        return @{
            Success         = $false
            ItemsDetected   = 0
            ItemsProcessed  = 0
            ItemsFailed     = 0
            Duration        = ((Get-Date) - $startTime).TotalMilliseconds
            DryRun          = $DryRun.IsPresent
            Error           = $_.Exception.Message
        }
    }
}

#endregion

#region Helper Functions

function Compare-DetectedVsConfig {
    <#
    .SYNOPSIS
        Compares Type1 detection results against configuration to create processing diff
    #>
    param(
        [Parameter(Mandatory = $true)]
        $Detected,
        
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Config
    )
    
    $diffList = [System.Collections.ArrayList]::new()
    
    foreach ($detectedItem in $Detected) {
        # Check if detected item matches any config item
        $configMatch = $Config.items | Where-Object { $_.name -eq $detectedItem.Name }
        
        if ($configMatch) {
            # Item from config was found on system - add to diff for processing
            [void]$diffList.Add($detectedItem)
        }
    }
    
    return $diffList
}

function Invoke-YourModuleAction {
    <#
    .SYNOPSIS
        Performs the actual system modification for a single item
    #>
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Item
    )
    
    try {
        # IMPLEMENT YOUR ACTUAL SYSTEM MODIFICATION HERE
        # Examples:
        # - Modify registry: Set-ItemProperty -Path $regPath -Name $valueName -Value $newValue
        # - Stop/disable service: Stop-Service -Name $serviceName; Set-Service -Name $serviceName -StartupType Disabled
        # - Delete file: Remove-Item -Path $filePath -Force
        # - Modify scheduled task: Disable-ScheduledTask -TaskName $taskName
        
        # Example implementation:
        $regPath = "HKLM:\SOFTWARE\Example\$($Item.Name)"
        if (Test-Path $regPath) {
            Remove-Item -Path $regPath -Recurse -Force
            
            return @{
                Success = $true
                Message = "Successfully removed registry key"
            }
        }
        else {
            return @{
                Success = $false
                Error   = "Registry key not found"
            }
        }
    }
    catch {
        return @{
            Success = $false
            Error   = $_.Exception.Message
        }
    }
}

#endregion

# Export public functions
Export-ModuleMember -Function @(
    'Invoke-YourNewModule'
)
```

### **Step 5: Register Module in Orchestrator**

**File**: `MaintenanceOrchestrator.ps1`

**Location 1** - Add to Type2 modules array (around line 230):
```powershell
# Type2 modules (self-contained with internal Type1 dependencies)
$Type2Modules = @(
    'BloatwareRemoval',
    'EssentialApps',
    'SystemOptimization',
    'TelemetryDisable',
    'WindowsUpdates',
    'YourNewModule'  # ADD THIS LINE
)
```

**Location 2** - Add task definition (around line 787):
```powershell
$MaintenanceTasks = @(
    # ... existing tasks ...
    @{
        Name        = 'YourNewModule'
        Description = 'Describe what your module does (Type2→Type1 flow)'
        ModuleName  = 'YourNewModule'
        Function    = 'Invoke-YourNewModule'
        Type        = 'Type2'
        Category    = 'YourCategory'  # e.g., Cleanup, Installation, Optimization, Privacy
        Enabled     = (-not $MainConfig.modules.skipYourNewModule)
    }
)
```

### **Step 6: Add Module Toggle to Configuration**

**File**: `config/main-config.json`

Add your module toggle to the `modules` section:
```json
{
  "modules": {
    "skipBloatwareRemoval": false,
    "skipEssentialApps": false,
    "skipSystemOptimization": false,
    "skipTelemetryDisable": false,
    "skipWindowsUpdates": false,
    "skipYourNewModule": false
  }
}
```

### **Step 7: Add Report Template Configuration**

**File**: `config/report-templates-config.json`

Add your module's report configuration:
```json
{
  "modules": {
    "YourNewModule": {
      "displayName": "Your New Module",
      "icon": "🔧",
      "category": "System Maintenance",
      "description": "Describes what your module does for the report",
      "enabled": true
    }
  }
}
```

### **Step 8: Test Module Loading**

Create a test script to verify your module loads correctly:

**File**: `TestYourNewModule.ps1`
```powershell
#Requires -Version 7.0

$ScriptRoot = $PSScriptRoot

# Set up environment
$env:MAINTENANCE_PROJECT_ROOT = $ScriptRoot
$env:MAINTENANCE_CONFIG_ROOT = Join-Path $ScriptRoot 'config'
$env:MAINTENANCE_MODULES_ROOT = Join-Path $ScriptRoot 'modules'
$env:MAINTENANCE_TEMP_ROOT = Join-Path $ScriptRoot 'temp_files'

Write-Host "`n🧪 Testing YourNewModule Loading`n" -ForegroundColor Cyan

# Load CoreInfrastructure first
Write-Host "Loading CoreInfrastructure..." -ForegroundColor Yellow
Import-Module (Join-Path $ScriptRoot 'modules\core\CoreInfrastructure.psm1') -Force -Global

# Load your Type2 module
Write-Host "Loading YourNewModule..." -ForegroundColor Yellow
try {
    Import-Module (Join-Path $ScriptRoot 'modules\type2\YourNewModule.psm1') -Force
    
    if (Get-Command 'Invoke-YourNewModule' -ErrorAction SilentlyContinue) {
        Write-Host "✅ SUCCESS: YourNewModule loaded, Invoke-YourNewModule available" -ForegroundColor Green
        
        # Test if Type1 function is accessible from Type2 module
        if (Get-Command 'Get-YourNewModuleAnalysis' -ErrorAction SilentlyContinue) {
            Write-Host "✅ Type1 function Get-YourNewModuleAnalysis also available" -ForegroundColor Green
        }
        else {
            Write-Host "⚠️  Type1 function not in global scope (expected - only accessible within Type2)" -ForegroundColor Yellow
        }
    }
    else {
        Write-Host "❌ FAILED: Invoke-YourNewModule not found" -ForegroundColor Red
    }
}
catch {
    Write-Host "❌ ERROR: $($_.Exception.Message)" -ForegroundColor Red
}
```

Run the test:
```powershell
.\TestYourNewModule.ps1
```

### **Step 9: Test Module Execution**

Test your module in dry-run mode first:

```powershell
# Load the orchestrator environment
$env:MAINTENANCE_PROJECT_ROOT = "C:\path\to\script_mentenanta"
$env:MAINTENANCE_CONFIG_ROOT = "$env:MAINTENANCE_PROJECT_ROOT\config"
$env:MAINTENANCE_MODULES_ROOT = "$env:MAINTENANCE_PROJECT_ROOT\modules"
$env:MAINTENANCE_TEMP_ROOT = "$env:MAINTENANCE_PROJECT_ROOT\temp_files"

# Load CoreInfrastructure
Import-Module "$env:MAINTENANCE_MODULES_ROOT\core\CoreInfrastructure.psm1" -Force -Global

# Initialize configuration
Initialize-ConfigSystem -ConfigRootPath $env:MAINTENANCE_CONFIG_ROOT

# Load your module
Import-Module "$env:MAINTENANCE_MODULES_ROOT\type2\YourNewModule.psm1" -Force

# Test in dry-run mode
$config = Get-MainConfig
$result = Invoke-YourNewModule -Config $config -DryRun

# Check results
Write-Host "`nExecution Results:" -ForegroundColor Cyan
Write-Host "Success: $($result.Success)" -ForegroundColor $(if ($result.Success) { 'Green' } else { 'Red' })
Write-Host "Items Detected: $($result.ItemsDetected)" -ForegroundColor Cyan
Write-Host "Items Processed: $($result.ItemsProcessed)" -ForegroundColor Cyan
Write-Host "Duration: $($result.Duration)ms" -ForegroundColor Cyan
```

### **Step 10: Verify Integration with Orchestrator**

Run the full orchestrator to verify complete integration:

```powershell
# Run orchestrator with your module only (as administrator)
.\MaintenanceOrchestrator.ps1 -NonInteractive -TaskNumbers 6 -DryRun
```

Check that:
- [ ] Module loads without errors
- [ ] `Invoke-YourNewModule` is registered as available
- [ ] Task appears in the available tasks list
- [ ] Module executes without errors
- [ ] Logs are created in `temp_files/logs/your-new-module/`
- [ ] Detection results saved to `temp_files/data/your-new-module-results.json`
- [ ] Diff created in `temp_files/temp/your-new-module-diff.json`
- [ ] Report includes your module's data

---

## ✅ **Validation Checklist**

Before considering your module complete, verify:

### **Code Quality**
- [ ] PowerShell 7+ `#Requires` directive at top of file
- [ ] Proper `using namespace` declarations
- [ ] Comprehensive XML documentation for all functions
- [ ] Consistent naming: `Invoke-YourNewModule`, `Get-YourNewModuleAnalysis`
- [ ] All paths use `$Global:ProjectPaths` variables (never hardcoded paths)
- [ ] Module imports CoreInfrastructure with `-Global -Force` flags
- [ ] Export-ModuleMember explicitly lists exported functions

### **Functionality**
- [ ] Type1 module detects items correctly
- [ ] Type2 module processes items correctly
- [ ] DryRun mode simulates without making changes
- [ ] Live mode performs actual system modifications
- [ ] Error handling catches and logs all exceptions
- [ ] Standardized return object with required properties

### **Integration**
- [ ] Module registered in orchestrator's `$Type2Modules` array
- [ ] Task definition added to `$MaintenanceTasks` array
- [ ] Configuration toggle added to `main-config.json`
- [ ] Report template configured in `report-templates-config.json`
- [ ] Module appears in available tasks list (5/5 becomes 6/6)
- [ ] Module executes successfully via orchestrator

### **File Organization**
- [ ] Detection results saved to correct path: `temp_files/data/your-new-module-results.json`
- [ ] Execution logs saved to correct path: `temp_files/logs/your-new-module/execution.log`
- [ ] Diff saved to correct path: `temp_files/temp/your-new-module-diff.json`
- [ ] All paths use `$Global:ProjectPaths.TempFiles` as base

### **VS Code Diagnostics**
- [ ] No PSScriptAnalyzer errors
- [ ] No unused variables
- [ ] No incorrect null comparisons
- [ ] No unapproved verbs in function names
- [ ] All functions have proper parameter validation

---

## 🐛 **Common Issues & Solutions**

### **Issue 1: Module Not Loading**
**Error**: `Failed to load Type2 module YourNewModule: ...`

**Solution**:
- Check file exists at correct path
- Verify `#Requires -Version 7.0` at top
- Ensure CoreInfrastructure import path is correct
- Run `Unblock-File` on module files if downloaded

### **Issue 2: Function Not Available**
**Error**: `Invoke-YourNewModule not found`

**Solution**:
- Check `Export-ModuleMember` at end of module
- Verify function name matches exactly (case-sensitive)
- Ensure module loaded without errors (check `Get-Module`)

### **Issue 3: Configuration Not Found**
**Error**: `Configuration system not initialized or YourNewModuleConfig not loaded`

**Solution**:
- Verify config file exists in `config/` directory
- Check JSON syntax is valid
- Ensure `Initialize-ConfigSystem` loads your config
- Add configuration loader function to CoreInfrastructure

### **Issue 4: Type1 Module Can't Access CoreInfrastructure**
**Error**: `Write-LogEntry function not available`

**Solution**:
- Ensure Type2 imports CoreInfrastructure with `-Global` flag
- Check import order: CoreInfrastructure BEFORE Type1
- Verify CoreInfrastructure exports the function you need

### **Issue 5: Paths Not Found**
**Error**: `Cannot find path 'temp_files/data/...'`

**Solution**:
- Always use `$Global:ProjectPaths.TempFiles` as base path
- Never use relative paths or `$PSScriptRoot` for temp files
- Ensure `Initialize-TempFilesStructure` was called
- Create directories before writing files

---

## 📊 **Testing Strategy**

### **Unit Testing (Module Level)**
```powershell
# Test Type1 detection
$config = Get-MainConfig
$detected = Get-YourNewModuleAnalysis -Config $config
Write-Host "Detected $($detected.Count) items"

# Test Type2 execution (dry-run)
$result = Invoke-YourNewModule -Config $config -DryRun
Write-Host "Would process $($result.ItemsProcessed) items"
```

### **Integration Testing (Orchestrator Level)**
```powershell
# Test with orchestrator (as admin)
.\MaintenanceOrchestrator.ps1 -NonInteractive -TaskNumbers 6 -DryRun

# Check logs
Get-Content "temp_files\logs\your-new-module\execution.log"
```

### **System Testing (Full Run)**
```powershell
# Run full maintenance with your module (as admin, production)
.\script.bat
# Select your module from menu
```

---

## 📚 **Additional Resources**

- **Project Architecture**: See `.github/copilot-instructions.md` for detailed architecture
- **Existing Modules**: Reference `modules/type2/BloatwareRemoval.psm1` for complete example
- **Global Paths**: See `modules/core/CoreInfrastructure.psm1` for path system
- **Report Generation**: See `modules/core/ReportGenerator.psm1` for reporting integration

---

## 🎉 **Completion**

Once all validation checks pass, your module is ready for production use!

Your module will now:
- ✅ Load automatically with the orchestrator
- ✅ Appear in the interactive menu
- ✅ Execute in proper sequence
- ✅ Generate comprehensive logs
- ✅ Integrate with report generation
- ✅ Support both dry-run and live modes

**Next Steps**:
1. Test thoroughly in dry-run mode
2. Test with small datasets in live mode
3. Document any specific requirements or limitations
4. Add to project README in the module list
5. Commit changes to version control

---

**Happy Coding! 🚀**
