#Requires -Version 7.0
# Module Dependencies:
#   - CoreInfrastructure.psm1 (configuration, logging, path management)
#   - SystemInventoryAudit.psm1 (Type1 - detection/analysis)
#
# External Tools: None (uses native Windows WMI/CIM queries)

<#
.SYNOPSIS
    System Inventory - Type 2 (Information Collection)

.DESCRIPTION
    Collects and stores comprehensive system inventory data for reporting.
    This is a read-only module that doesn't modify the system.

.NOTES
    Module Type: Type 2 (Information Collection - No Modifications)
    Dependencies: SystemInventoryAudit.psm1, CoreInfrastructure.psm1
    Requires: Administrator privileges (for full system access)
    Author: Windows Maintenance Automation Project
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
$Type1ModulePath = Join-Path $ModuleRoot 'type1\SystemInventoryAudit.psm1'
if (Test-Path $Type1ModulePath) {
    Import-Module $Type1ModulePath -Force -WarningAction SilentlyContinue
}
else {
    throw "Required Type 1 module not found: $Type1ModulePath"
}

# Validate Type1 module loaded correctly
if (-not (Get-Command -Name 'Get-SystemInventoryAnalysis' -ErrorAction SilentlyContinue)) {
    throw "Type 1 module functions not available - ensure SystemInventoryAudit.psm1 is properly imported"
}

#region v3.0 Standardized Execution Function

<#
.SYNOPSIS
    Main execution function - System Inventory Collection

.DESCRIPTION
    Collects comprehensive system inventory data including:
    - Operating System details
    - Hardware specifications
    - Network configuration
    - Storage information
    - Software summary
    - Security status
    - Performance metrics

.PARAMETER Config
    Main configuration object from orchestrator

.PARAMETER DryRun
    Not applicable for this module (information gathering only)

.OUTPUTS
    Hashtable with Success, ItemsDetected (always 1), ItemsProcessed, Duration

.EXAMPLE
    $result = Invoke-SystemInventory -Config $mainConfig
#>
function Invoke-SystemInventory {
    [CmdletBinding()]
    [OutputType([hashtable])]
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
        $perfContext = Start-PerformanceTracking -OperationName 'SystemInventory' -Component 'SYSTEM-INVENTORY'
    }
    catch {
        # Performance tracking is optional
    }
    
    try {
        Write-Information " Collecting system inventory..." -InformationAction Continue
        
        # Initialize module execution environment
        Initialize-ModuleExecution -ModuleName 'SystemInventory'
        
        # STEP 1: Run Type1 detection (inventory collection)
        # Explicit assignment to prevent pipeline contamination
        $inventoryData = $null
        $inventoryData = Get-SystemInventoryAnalysis -Config $Config
        
        # STEP 2: Save inventory data to temp_files/data/
        $inventoryDataPath = Join-Path (Get-MaintenancePath 'TempRoot') "system-inventory.json"
        $null = $inventoryData | ConvertTo-Json -Depth 10 | Set-Content $inventoryDataPath -Encoding UTF8 -ErrorAction Stop
        Write-Information "   System inventory saved to data folder" -InformationAction Continue
        
        # STEP 3: Setup logging (information gathering, minimal logging needed)
        $executionLogDir = Join-Path (Get-MaintenancePath 'TempRoot') "logs\system-inventory"
        if (-not (Test-Path $executionLogDir)) {
            New-Item -Path $executionLogDir -ItemType Directory -Force | Out-Null
        }
        $executionLogPath = Join-Path $executionLogDir "execution.log"
        
        # Log inventory summary
        $logSummary = @"
========================================
System Inventory Collection Log
Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
========================================

COMPUTER INFORMATION:
  Computer Name: $($inventoryData.ComputerName)
  OS: $($inventoryData.OperatingSystem.Name)
  Version: $($inventoryData.OperatingSystem.Version)
  Build: $($inventoryData.OperatingSystem.Build)

HARDWARE:
  CPU: $($inventoryData.Hardware.Processor.Name)
  Cores: $($inventoryData.Hardware.Processor.Cores)
  RAM: $($inventoryData.Hardware.Memory.TotalPhysicalGB) GB

STORAGE:
  Total Capacity: $($inventoryData.Storage.TotalCapacityGB) GB
  Total Free: $($inventoryData.Storage.TotalFreeGB) GB
  Drives: $($inventoryData.Storage.Drives.Count)

NETWORK:
  Active Adapters: $($inventoryData.Network.Adapters.Count)
  Domain: $($inventoryData.Network.DomainName)

SOFTWARE:
  Installed Apps: $($inventoryData.Software.InstalledApplications)
  PowerShell: $($inventoryData.Software.PowerShellVersion)

PERFORMANCE:
  Uptime: $($inventoryData.Performance.Uptime)
  CPU Usage: $($inventoryData.Performance.CPUUsage)
  Memory Usage: $($inventoryData.Performance.MemoryUsagePercent)%

========================================
Collection completed successfully
========================================
"@
        
        Add-Content -Path $executionLogPath -Value $logSummary -Encoding UTF8 | Out-Null
        
        Write-Information "   Inventory collection complete" -InformationAction Continue
        
        # Create execution summary JSON
        $summaryPath = Join-Path $executionLogDir "execution-summary.json"
        $executionTime = (Get-Date) - $startTime
        $executionSummary = @{
            ModuleName       = 'SystemInventory'
            ExecutionTime    = @{
                Start      = $startTime.ToString('o')
                End        = (Get-Date).ToString('o')
                DurationMs = $executionTime.TotalMilliseconds
            }
            Results          = @{
                Success        = $true
                ItemsDetected  = 1
                ItemsProcessed = 1
                ItemsFailed    = 0
                ItemsSkipped   = 0
            }
            ExecutionMode    = 'Live'  # Always live - info gathering
            LogFiles         = @{
                TextLog = $executionLogPath
                JsonLog = $inventoryDataPath  # Inventory data IS the JSON log
                Summary = $summaryPath
            }
            SessionInfo      = @{
                SessionId    = $env:MAINTENANCE_SESSION_ID
                ComputerName = $env:COMPUTERNAME
                UserName     = $env:USERNAME
                PSVersion    = $PSVersionTable.PSVersion.ToString()
            }
            InventoryDetails = @{
                ComputerName  = $inventoryData.ComputerName
                OSVersion     = $inventoryData.OperatingSystem.Version
                TotalRAM      = $inventoryData.Hardware.Memory.TotalPhysicalGB
                InstalledApps = $inventoryData.Software.InstalledApplications
            }
        }
        
        try {
            $executionSummary | ConvertTo-Json -Depth 10 | Set-Content $summaryPath -Force | Out-Null
            Write-Verbose "Execution summary saved to: $summaryPath"
        }
        catch {
            Write-Warning "Failed to create execution summary: $($_.Exception.Message)"
        }
        
        # Complete performance tracking
        if ($perfContext) {
            try {
                Complete-PerformanceTracking -Context $perfContext -Status 'Success'
            }
            catch {
                # Performance tracking is optional
            }
        }
        
        # STEP 4: Return standardized result (explicit return to prevent pipeline contamination)
        $result = New-ModuleExecutionResult `
            -Success $true `
            -ItemsDetected 1 `
            -ItemsProcessed 1 `
            -DurationMilliseconds $executionTime.TotalMilliseconds `
            -LogPath $executionLogPath `
            -ModuleName 'SystemInventory' `
            -AdditionalData @{ DataPath = $inventoryDataPath }
        
        return $result
    }
    catch {
        $errorMsg = "System inventory collection failed: $($_.Exception.Message)"
        Write-Error $errorMsg
        
        # Complete performance tracking with failure
        if ($perfContext) {
            try {
                Complete-PerformanceTracking -Context $perfContext -Status 'Failed' -ErrorMessage $errorMsg
            }
            catch {
                # Performance tracking is optional
            }
        }
        
        # Return failure result (explicit assignment to prevent pipeline contamination)
        $errorResult = New-ModuleExecutionResult `
            -Success $false `
            -ItemsDetected 0 `
            -ItemsProcessed 0 `
            -DurationMilliseconds ((Get-Date) - $startTime).TotalMilliseconds `
            -LogPath $executionLogPath `
            -ModuleName 'SystemInventory' `
            -ErrorMessage $errorMsg
        
        return $errorResult
    }
}

#endregion

# Export public functions
Export-ModuleMember -Function @(
    'Invoke-SystemInventory'
)

