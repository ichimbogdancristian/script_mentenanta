# DryRun Removal Implementation Guide

## Status: PARTIALLY COMPLETE

### Completed Modules ✅

1. **BloatwareRemoval.psm1** - 57 references removed
2. **EssentialApps.psm1** - 44 references removed

### Remaining Work

#### Type2 Modules

3. SystemOptimization.psm1 - 45 references
4. TelemetryDisable.psm1 - ~80 references
5. SecurityEnhancement.psm1 - ~30 references
6. WindowsUpdates.psm1 - ~40 references
7. AppUpgrade.psm1 - ~25 references

#### Infrastructure

8. MaintenanceOrchestrator.ps1 - ~20 references
9. script.bat - DryRun menu system

---

## Systematic Replacement Pattern

For each remaining Type2 module, apply these changes:

### 1. Main Function Signature

```powershell
# REMOVE:
param(
    [Parameter(Mandatory=$true)]
    [hashtable]$Config,

    [Parameter()]
    [switch]$DryRun
)

# REPLACE WITH:
param(
    [Parameter(Mandatory=$true)]
    [hashtable]$Config
)
```

### 2. Mode Display

```powershell
# REMOVE:
Write-Host "$(if ($DryRun) { 'DRY-RUN (Simulation)' } else { 'LIVE EXECUTION' })" -ForegroundColor $(if ($DryRun) { 'Cyan' } else { 'Green' })

# REPLACE WITH:
Write-Host "LIVE EXECUTION" -ForegroundColor Green
```

### 3. Conditional Execution Blocks

```powershell
# REMOVE ENTIRE if ($DryRun) BLOCK:
if ($DryRun) {
    Write-StructuredLogEntry -Level 'INFO' -Component 'MODULE' -Message " DRY-RUN: Would process X items" ...
    $processedCount = 0
}
else {
    # Actual execution code
    $results = Process-Items ...
}

# KEEP ONLY THE ELSE BLOCK CONTENT:
# Actual execution code
$results = Process-Items ...
```

### 4. Function Calls

```powershell
# REMOVE -DryRun parameter from ALL function calls:

# BEFORE:
$result = Remove-Something -Items $items -DryRun:$DryRun
$result = Install-Something -Apps $apps -DryRun:$DryRun

# AFTER:
$result = Remove-Something -Items $items
$result = Install-Something -Apps $apps
```

### 5. Execution Mode

```powershell
# REMOVE:
ExecutionMode = if ($DryRun) { 'DryRun' } else { 'Live' }

# REPLACE WITH:
ExecutionMode = 'Live'
```

### 6. Metadata Objects

```powershell
# REMOVE DryRun from ALL metadata:

# BEFORE:
-Metadata @{ DryRun = $DryRun.IsPresent; ItemCount = $count }
DryRun = $DryRun.IsPresent

# AFTER:
-Metadata @{ ItemCount = $count }
# (Remove entire DryRun key-value pair)
```

### 7. Result Objects

```powershell
# REMOVE from return statements:

# BEFORE:
return New-ModuleExecutionResult `
    -Success $true `
    -ItemsDetected $detected `
    -ItemsProcessed $processed `
    -DryRun $DryRun.IsPresent

# AFTER:
return New-ModuleExecutionResult `
    -Success $true `
    -ItemsDetected $detected `
    -ItemsProcessed $processed
```

### 8. Documentation

```powershell
# REMOVE from .SYNOPSIS/.DESCRIPTION:
3. Executes actions (Type2) based on DryRun mode

# REMOVE .PARAMETER DryRun section entirely

# REMOVE from .EXAMPLE:
.EXAMPLE
    $result = Invoke-Module -Config $Config -DryRun
```

### 9. Helper Functions

For ALL internal helper functions (Clear-TemporaryFile, Optimize-StartupProgram, etc.):

- Remove `[switch]$DryRun` parameter
- Remove `if ($DryRun)` conditional blocks
- Keep only actual execution code
- Remove `-DryRun:$DryRun` from nested function calls

---

## MaintenanceOrchestrator.ps1 Changes

```powershell
# 1. Remove top-level parameter:
[switch]$DryRun,

# 2. Remove restore point conditional:
if ($createRestorePoint -and -not $DryRun) {

# REPLACE WITH:
if ($createRestorePoint) {

# 3. Remove execution mode display:
elseif ($DryRun) {
    Write-Host "SIMULATION MODE - No changes will be made" -ForegroundColor Cyan
}

# 4. Remove from Invoke-Type2Module helper:
function Invoke-Type2Module {
    param(
        [string]$ModuleName,
        [hashtable]$Config,
        [switch]$DryRun  # REMOVE THIS
    )

    if ($DryRun) { $params.DryRun = $true }  # REMOVE THIS
}

# 5. Remove from New-SessionMetadata:
[switch]$IsDryRun = $false  # REMOVE THIS
isDryRun = $IsDryRun.IsPresent  # REMOVE THIS
executionMode = if ($IsDryRun) { 'DryRun' } else { 'Live' }  # SIMPLIFY TO 'Live'
```

---

## script.bat Changes

```batch
rem REMOVE entire DryRun menu system:
rem - Remove parameter parsing: IF "%1"=="-DryRun" ...
rem - Remove :DRYRUN_MENU label and menu
rem - Remove :EXECUTE_ALL_DRYRUN label
rem - Remove :EXECUTE_INSERTED_DRYRUN label
rem - Remove all -DryRun flag passing to orchestrator

rem SIMPLIFIED EXECUTION:
rem Instead of:
"%PS_EXECUTABLE%" -ExecutionPolicy Bypass -File "%ORCHESTRATOR_PATH%" -NonInteractive -DryRun

rem Use:
"%PS_EXECUTABLE%" -ExecutionPolicy Bypass -File "%ORCHESTRATOR_PATH%" -NonInteractive
```

---

## Validation Checklist

After completing each module:

- [ ] No syntax errors (`pwsh -NoProfile -Command "Test-ScriptFileInfo -Path module.psm1"`)
- [ ] No PSScriptAnalyzer warnings for DryRun
- [ ] All conditional blocks removed (no orphaned `}`)
- [ ] All function calls updated (no `-DryRun` parameters)
- [ ] Documentation updated (no DryRun references)
- [ ] Test basic execution (module loads without errors)

---

## Batch Processing Recommendation

For efficiency, process modules in this order:

1. **SystemOptimization.psm1** (medium complexity, 45 refs)
2. **SecurityEnhancement.psm1** (low complexity, ~30 refs)
3. **AppUpgrade.psm1** (low complexity, ~25 refs)
4. **WindowsUpdates.psm1** (medium complexity, ~40 refs)
5. **TelemetryDisable.psm1** (high complexity, ~80 refs)
6. **MaintenanceOrchestrator.ps1** (orchestrator, ~20 refs)
7. **script.bat** (entry point, menu system removal)

---

## Testing Strategy

After all modules complete:

```powershell
# 1. Syntax check all modified files
Get-ChildItem modules\type2\*.psm1 | ForEach-Object {
    powershell -NoProfile -Command "& { Import-Module '$($_.FullName)' -Force }"
}

# 2. Run orchestrator in test mode
.\MaintenanceOrchestrator.ps1 -NonInteractive -TaskNumbers "1"

# 3. Check for any DryRun remnants
Get-ChildItem -Recurse -Include *.ps1,*.psm1 | Select-String "DryRun"
```

---

## Notes

- Total estimated removal: ~300+ DryRun references across all files
- Completed: ~100 references (33%)
- Remaining: ~200 references (67%)
- Estimated time: 2-3 hours for remaining work

**Last Updated:** February 7, 2026  
**Author:** Bogdan Ichim / GitHub Copilot
**Status:** Partially complete - BloatwareRemoval & EssentialApps done
