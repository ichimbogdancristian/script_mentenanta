# 🚀 **Quick Reference: Adding New Type2 Modules**

This is the condensed version for AI coding agents. For the complete guide, see **[ADDING_NEW_MODULES.md](../ADDING_NEW_MODULES.md)**.

> **📊 Current Module Status (v3.0+)**:
> - **Core Modules**: 4 (CoreInfrastructure, UserInterface, LogProcessor, ReportGenerator)
> - **Type1 Modules**: 7 (Detection/Audit services)
> - **Type2 Modules**: 7 (Action/Modification services)
> - **Execution Order**: SystemInventory → BloatwareRemoval → EssentialApps → SystemOptimization → TelemetryDisable → WindowsUpdates → AppUpgrade
> - **Latest Addition**: AppUpgrade module (v3.1) - handles application version upgrades as the final maintenance step

---

## **🎯 10-Step Implementation Procedure**

### **Prerequisites**
- PowerShell 7+ installed
- Understanding of v3.0 self-contained architecture
- Knowledge of `-Global` flag requirement for CoreInfrastructure
- Familiarity with `$Global:ProjectPaths` for file operations

---

### **Step 1: Create Type1 Detection Module**

**File:** `modules/type1/YourNewModuleAudit.psm1`

```powershell
#Requires -Version 7.0

#region Module Initialization
$ModuleRoot = Split-Path -Parent $PSScriptRoot
$CoreInfraPath = Join-Path $ModuleRoot 'core\CoreInfrastructure.psm1'
if (Test-Path $CoreInfraPath) {
    try {
        Import-Module $CoreInfraPath -Force -WarningAction SilentlyContinue
    } catch {
        Write-Verbose "CoreInfrastructure global import in progress"
    }
}
#endregion

#region Public Functions
function Get-YourNewModuleAnalysis {
    [CmdletBinding()]
    param([hashtable]$Config)
    
    $detectedItems = @()
    # YOUR DETECTION LOGIC HERE
    return $detectedItems
}
#endregion

Export-ModuleMember -Function Get-YourNewModuleAnalysis
```

---

### **Step 2: Create Type2 Action Module**

**File:** `modules/type2/YourNewModule.psm1`

```powershell
#Requires -Version 7.0

#region Module Dependencies
$ModuleRoot = Split-Path -Parent $PSScriptRoot

# CRITICAL: Import with -Global flag
$CoreInfraPath = Join-Path $ModuleRoot 'core\CoreInfrastructure.psm1'
if (Test-Path $CoreInfraPath) {
    Import-Module $CoreInfraPath -Force -Global -WarningAction SilentlyContinue
} else {
    throw "CoreInfrastructure module not found"
}

# Import Type1 module (self-contained)
$Type1ModulePath = Join-Path $ModuleRoot 'type1\YourNewModuleAudit.psm1'
if (Test-Path $Type1ModulePath) {
    Import-Module $Type1ModulePath -Force -WarningAction SilentlyContinue
} else {
    throw "Type1 audit module not found"
}
#endregion

#region Public Functions
function Invoke-YourNewModule {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Config,
        [switch]$DryRun
    )
    
    $startTime = Get-Date
    
    # STEP 1: Run Type1 detection
    $detectionResults = Get-YourNewModuleAnalysis -Config $Config
    $dataPath = Join-Path $Global:ProjectPaths.TempFiles "data\your-new-module-results.json"
    $detectionResults | ConvertTo-Json -Depth 10 | Set-Content $dataPath
    
    # STEP 2: Load configuration
    $configDataPath = Join-Path $Global:ProjectPaths.Config "your-new-module-config.json"
    $configData = Get-Content $configDataPath | ConvertFrom-Json
    
    # STEP 3: Create diff list
    $diffList = @()
    foreach ($detected in $detectionResults) {
        if ($configData.Items | Where-Object { $detected.Name -like $_.Pattern }) {
            $diffList += $detected
        }
    }
    
    # STEP 4: Setup logging
    $executionLogDir = Join-Path $Global:ProjectPaths.TempFiles "logs\your-new-module"
    New-Item -Path $executionLogDir -ItemType Directory -Force | Out-Null
    $executionLogPath = Join-Path $executionLogDir "execution.log"
    
    # STEP 5: Process items
    $processedCount = 0
    if (-not $DryRun) {
        foreach ($item in $diffList) {
            # YOUR ACTION LOGIC HERE
            $processedCount++
        }
    }
    
    # STEP 6: Return standardized result
    return @{
        Success = $true
        ItemsDetected = $detectionResults.Count
        ItemsProcessed = $processedCount
        Duration = ((Get-Date) - $startTime).TotalMilliseconds
    }
}
#endregion

Export-ModuleMember -Function Invoke-YourNewModule
```

---

### **Step 3: Create Configuration File**

**File:** `config/your-new-module-config.json`

```json
{
  "ModuleName": "YourNewModule",
  "Enabled": true,
  "Items": [
    {
      "Name": "ExampleItem1",
      "Pattern": "Example*",
      "Action": "Process"
    }
  ]
}
```

---

### **Step 4: Register in Orchestrator**

**File:** `MaintenanceOrchestrator.ps1`

**Three locations to update:**

1. **Module loading (~line 280)**:
```powershell
$type2Modules = @(
    'SystemInventory',       # Always first
    'BloatwareRemoval',
    'EssentialApps',
    'SystemOptimization',
    'TelemetryDisable',
    'WindowsUpdates',
    'AppUpgrade',            # Always last
    'YourNewModule'  # ADD THIS
)
```

2. **Task registration (~line 800)**:
```powershell
$registeredTasks = @{
    1 = @{ Name = 'SystemInventory'; Function = 'Invoke-SystemInventory' }
    2 = @{ Name = 'BloatwareRemoval'; Function = 'Invoke-BloatwareRemoval' }
    3 = @{ Name = 'EssentialApps'; Function = 'Invoke-EssentialApps' }
    4 = @{ Name = 'SystemOptimization'; Function = 'Invoke-SystemOptimization' }
    5 = @{ Name = 'TelemetryDisable'; Function = 'Invoke-TelemetryDisable' }
    6 = @{ Name = 'WindowsUpdates'; Function = 'Invoke-WindowsUpdates' }
    7 = @{ Name = 'AppUpgrade'; Function = 'Invoke-AppUpgrade' }
    8 = @{ Name = 'YourNewModule'; Function = 'Invoke-YourNewModule' }  # ADD THIS
}
```

3. **Execution sequence (~line 900)**:
```powershell
$taskSequence = @(
    'SystemInventory',
    'BloatwareRemoval',
    'EssentialApps',
    'SystemOptimization',
    'TelemetryDisable',
    'WindowsUpdates',
    'AppUpgrade',
    'YourNewModule'  # ADD THIS
)
```

---

### **Step 5: Update main-config.json**

```json
{
  "Execution": {
    "Modules": {
      "YourNewModule": true
    }
  }
}
```

---

### **Step 6: Update report-templates-config.json**

```json
{
  "YourNewModule": {
    "DisplayName": "Your Feature Name",
    "Icon": "🎯",
    "Description": "Brief description",
    "Category": "Maintenance"
  }
}
```

---

### **Step 7: Test Module Loading**

```powershell
# Test script
Import-Module ".\modules\type2\YourNewModule.psm1" -Force
$available = Get-Command Invoke-YourNewModule -ErrorAction SilentlyContinue
Write-Host "Module loaded: $($null -ne $available)"
```

---

### **Step 8: Test with Orchestrator DryRun**

```powershell
.\MaintenanceOrchestrator.ps1
# Select: [2] Dry-run mode → [2] Execute specific numbers → "6"
```

---

### **Step 9: VS Code Diagnostics Check**

- Open Problems panel (Ctrl+Shift+M)
- Verify zero critical errors
- Fix warnings: null comparison order, unused variables

---

### **Step 10: Full Integration Test**

```powershell
.\MaintenanceOrchestrator.ps1
# Select: [1] Execute normally → [2] Execute specific numbers → "6"
```

---

## **✅ Validation Checklist**

- [ ] Type1 exports `Get-[ModuleName]Analysis`
- [ ] Type2 imports CoreInfrastructure with `-Global`
- [ ] Type2 imports Type1 internally
- [ ] Type2 exports `Invoke-[ModuleName]`
- [ ] Configuration file exists
- [ ] Registered in orchestrator (3 locations)
- [ ] Toggle in main-config.json
- [ ] Metadata in report-templates-config.json
- [ ] Loads without errors
- [ ] DryRun works
- [ ] Creates proper logs
- [ ] Returns standardized result object

---

## **⚠️ Critical Requirements**

1. **MUST** use `-Global` flag when importing CoreInfrastructure in Type2
2. **MUST** use `$Global:ProjectPaths` for all file paths
3. **MUST** return `@{Success, ItemsDetected, ItemsProcessed, Duration}`
4. **MUST** save detection to `temp_files/data/[module]-results.json`
5. **MUST** save execution logs to `temp_files/logs/[module]/execution.log`
6. **MUST** handle DryRun mode correctly (no OS modifications)

---

## **📚 Full Documentation**

See **[ADDING_NEW_MODULES.md](../ADDING_NEW_MODULES.md)** for:
- Extended code templates (400+ lines)
- Detailed troubleshooting
- Common issues and solutions
- Advanced testing strategies
- Complete validation procedures
