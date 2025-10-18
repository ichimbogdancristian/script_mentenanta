# Type2→Type1 Integration Pattern - v3.0 Architecture

## Overview
This document defines the standardized pattern for Type2 modules to internally manage their Type1 dependencies in the new v3.0 architecture.

## Pattern Structure

### Required Type2 Module Structure
```powershell
#Requires -Version 7.0
# Self-contained Type 2 module with internal Type 1 dependency

# Step 1: Import corresponding Type 1 module (REQUIRED)
$Type1ModulePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'type1\[Feature]Audit.psm1'
if (Test-Path $Type1ModulePath) {
    Import-Module $Type1ModulePath -Force
} else {
    throw "Required Type 1 module not found: $Type1ModulePath"
}

# Step 2: Import core infrastructure (REQUIRED)
$CoreInfraPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'core\CoreInfrastructure.psm1'
if (Test-Path $CoreInfraPath) {
    Import-Module $CoreInfraPath -Force
} else {
    # Fallback logging function if CoreInfrastructure fails
    function Write-LogEntry {
        param($Level, $Component, $Message, $Data)
        Write-Information "[$Level] [$Component] $Message" -InformationAction Continue
    }
}

# Step 3: Main execution function (REQUIRED PATTERN)
function Invoke-[FeatureName] {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Config,
        
        [Parameter()]
        [switch]$DryRun
    )
    
    # Performance tracking
    $perfContext = Start-PerformanceTracking -OperationName '[FeatureName]' -Component '[COMPONENT-NAME]'
    
    try {
        # Step 1: ALWAYS detect first (Type 1) - MANDATORY
        Write-LogEntry -Level 'INFO' -Component '[COMPONENT-NAME]' -Message 'Starting [Feature] detection'
        $detectionResults = Get-[Feature]Analysis -Config $Config
        
        if (-not $detectionResults -or $detectionResults.Count -eq 0) {
            Write-LogEntry -Level 'INFO' -Component '[COMPONENT-NAME]' -Message 'No [feature] items detected'
            return @{ Success = $true; ItemsProcessed = 0; Message = 'No items found' }
        }
        
        # Step 2: Validate and log findings
        Write-LogEntry -Level 'INFO' -Component '[COMPONENT-NAME]' -Message "Detected $($detectionResults.Count) [feature] items"
        
        # Step 3: Take action (Type 2) based on DryRun mode
        if ($DryRun) {
            Write-LogEntry -Level 'INFO' -Component '[COMPONENT-NAME]' -Message 'DRY RUN: Simulating [feature] actions'
            $results = Simulate-[Feature]Actions -Items $detectionResults
        } else {
            Write-LogEntry -Level 'INFO' -Component '[COMPONENT-NAME]' -Message 'Executing [feature] actions'
            $results = Invoke-[Feature]Actions -Items $detectionResults -Config $Config
        }
        
        # Step 4: Return standardized results for ReportGeneration
        $returnData = @{
            Success = $true
            ItemsDetected = $detectionResults.Count
            ItemsProcessed = $results.ProcessedCount
            DryRun = $DryRun.IsPresent
            Results = $results
            DetectionData = $detectionResults
        }
        
        Complete-PerformanceTracking -Context $perfContext -Status 'Success'
        return $returnData
        
    } catch {
        $errorMsg = "Failed to execute [Feature]: $($_.Exception.Message)"
        Write-LogEntry -Level 'ERROR' -Component '[COMPONENT-NAME]' -Message $errorMsg -Data @{ Error = $_.Exception }
        Complete-PerformanceTracking -Context $perfContext -Status 'Failed' -ErrorMessage $errorMsg
        
        return @{
            Success = $false
            Error = $errorMsg
            ItemsDetected = 0
            ItemsProcessed = 0
        }
    }
}
```

## Module Mappings

### Type2 → Type1 Module Pairs
| Type2 Module | Type1 Module | Component Name |
|-------------|-------------|----------------|
| BloatwareRemoval.psm1 | BloatwareDetection.psm1 | BLOATWARE-REMOVAL |
| EssentialApps.psm1 | EssentialAppsAudit.psm1 | ESSENTIAL-APPS |
| SystemOptimization.psm1 | SystemOptimizationAudit.psm1 | SYSTEM-OPTIMIZATION |
| TelemetryDisable.psm1 | TelemetryAudit.psm1 | TELEMETRY-DISABLE |
| WindowsUpdates.psm1 | WindowsUpdatesAudit.psm1 | WINDOWS-UPDATES |

### Required Functions in Each Type2 Module
1. **`Invoke-[ModuleName]`** - Main execution function (orchestrator calls this)
2. **`Simulate-[Feature]Actions`** - DryRun simulation function
3. **`Invoke-[Feature]Actions`** - Actual system modification function

### Required Functions in Each Type1 Module (Called by Type2)
1. **`Get-[Feature]Analysis`** - Main detection/audit function
2. **Helper functions** - Specific detection logic

## Error Handling Standards

### Graceful Degradation Pattern
```powershell
try {
    Write-LogEntry -Level 'INFO' -Component 'MODULE-NAME' -Message 'Operation starting'
} catch {
    # CoreInfrastructure not available, use fallback logging
    Write-Information "[$Component] $Message" -InformationAction Continue
}
```

### Required Error Data Structure
```powershell
@{
    Success = $false
    Error = "Descriptive error message"
    ErrorType = $_.Exception.GetType().Name
    ItemsDetected = $detectedCount
    ItemsProcessed = $processedCount
    StackTrace = $_.ScriptStackTrace
}
```

## Return Data Standards

### Successful Execution Return
```powershell
@{
    Success = $true
    ItemsDetected = [int]
    ItemsProcessed = [int]
    DryRun = [bool]
    Results = @{ ProcessedCount = [int]; Details = [array] }
    DetectionData = [array] # Raw Type1 results for ReportGeneration
    PerformanceMetrics = @{ Duration = [timespan]; MemoryUsed = [long] }
}
```

### Failed Execution Return
```powershell
@{
    Success = $false
    Error = "Error message"
    ErrorType = "Exception type"
    ItemsDetected = [int]
    ItemsProcessed = [int]
    PartialResults = [array] # If some items processed before failure
}
```

## Configuration Access Pattern

### Type2 modules access config through CoreInfrastructure functions:
```powershell
# Get main config
$mainConfig = Get-MainConfig

# Get specific config items
$bloatwareList = Get-BloatwareList -Category 'OEM'
$essentialApps = Get-UnifiedEssentialAppsList

# Save session data for ReportGeneration
Save-SessionData -Category 'results' -Data $results -FileName "[module]-results.json"
```

## Import Validation Pattern

### Validate Dependencies at Module Load
```powershell
# Validate Type1 module loaded
if (-not (Get-Command -Name 'Get-[Feature]Analysis' -ErrorAction SilentlyContinue)) {
    throw "Type 1 module functions not available - ensure [Feature]Audit.psm1 is properly imported"
}

# Validate CoreInfrastructure functions
if (-not (Get-Command -Name 'Write-LogEntry' -ErrorAction SilentlyContinue)) {
    Write-Warning "CoreInfrastructure logging functions not available - using fallback logging"
}
```

## Transition Steps

1. **Update imports** - Replace old v1 module imports with CoreInfrastructure
2. **Add Type1 import** - Each Type2 must import its corresponding Type1 module
3. **Implement Invoke-[ModuleName]** - Standardized main function
4. **Update function calls** - Use Type1 detection functions before actions
5. **Standardize return data** - Consistent structure for ReportGeneration
6. **Add error handling** - Graceful degradation and proper error reporting

## Testing Validation

### Each Type2 module must pass:
1. **Independence test** - Can load and execute without orchestrator
2. **Type1 integration test** - Properly calls and uses Type1 functions
3. **DryRun test** - Simulation mode works correctly
4. **Error handling test** - Graceful failure and proper error reporting
5. **Return data test** - Standardized return structure for ReportGeneration