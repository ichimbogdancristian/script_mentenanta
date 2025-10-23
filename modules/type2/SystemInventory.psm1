#Requires -Version 7.0

<#
.SYNOPSIS
    System Inventory - Type 2 (Information Collection)

.DESCRIPTION
    Collects and stores comprehensive system inventory data for reporting.
    This is a read-only module that doesn't modify the system.

.NOTES
    Module Type: Type 2 (Information Collection - No Modifications)
    Dependencies: SystemInventoryAudit.psm1 (Type1), CoreInfrastructure.psm1
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
        Write-Information "📊 Collecting system inventory..." -InformationAction Continue
        
        # STEP 1: Run Type1 detection (inventory collection)
        $inventoryData = Get-SystemInventoryAnalysis -Config $Config
        
        # STEP 2: Save inventory data to temp_files/data/
        $inventoryDataPath = Join-Path $Global:ProjectPaths.TempFiles "data\system-inventory.json"
        $inventoryData | ConvertTo-Json -Depth 10 | Set-Content $inventoryDataPath -Encoding UTF8
        Write-Information "  ✓ System inventory saved to data folder" -InformationAction Continue
        
        # STEP 3: Setup logging (information gathering, minimal logging needed)
        $executionLogDir = Join-Path $Global:ProjectPaths.TempFiles "logs\system-inventory"
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
        
        Add-Content -Path $executionLogPath -Value $logSummary -Encoding UTF8
        
        Write-Information "  ✓ Inventory collection complete" -InformationAction Continue
        
        # Complete performance tracking
        if ($perfContext) {
            try {
                Complete-PerformanceTracking -Context $perfContext
            }
            catch {
                # Performance tracking is optional
            }
        }
        
        # STEP 4: Return standardized result
        $executionTime = (Get-Date) - $startTime
        return @{
            Success        = $true
            ItemsDetected  = 1  # One complete inventory
            ItemsProcessed = 1  # One inventory collected
            ItemsFailed    = 0
            Duration       = $executionTime.TotalMilliseconds
            DryRun         = $false  # Not applicable for info gathering
            LogPath        = $executionLogPath
            DataPath       = $inventoryDataPath
        }
    }
    catch {
        Write-Error "System inventory collection failed: $($_.Exception.Message)"
        
        # Return failure result
        return @{
            Success        = $false
            ItemsDetected  = 0
            ItemsProcessed = 0
            ItemsFailed    = 1
            Duration       = ((Get-Date) - $startTime).TotalMilliseconds
            DryRun         = $false
            Error          = $_.Exception.Message
        }
    }
}

#endregion

# Export public functions
Export-ModuleMember -Function @(
    'Invoke-SystemInventory'
)
