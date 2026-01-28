#Requires -Version 7.0
# Module Dependencies:
#   - CoreInfrastructure.psm1 (configuration, logging, path management)
#   - SystemInventory.psm1 (Type1 - detection/analysis)
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
    Dependencies: SystemInventory.psm1, CoreInfrastructure.psm1
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
    $fallbackCorePath = Join-Path $ModuleRoot 'CoreInfrastructure.psm1'
    if (Test-Path $fallbackCorePath) {
        Import-Module $fallbackCorePath -Force -Global -WarningAction SilentlyContinue
    }
    else {
        Write-Warning "CoreInfrastructure module not found at: $CoreInfraPath"
    }
}

# Step 2: Import corresponding Type 1 module AFTER CoreInfrastructure (REQUIRED)
$Type1ModulePath = Join-Path $ModuleRoot 'type1\SystemInventory.psm1'
if (Test-Path $Type1ModulePath) {
    Import-Module $Type1ModulePath -Force -WarningAction SilentlyContinue
}
else {
    throw "Required Type 1 module not found: $Type1ModulePath"
}

# Validate Type1 module loaded correctly
if (-not (Get-Command -Name 'Get-SystemInventoryAnalysis' -ErrorAction SilentlyContinue) -and -not (Get-Command -Name 'Get-SystemInventory' -ErrorAction SilentlyContinue)) {
    throw "Type 1 module functions not available - ensure SystemInventory.psm1 is properly imported"
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
        Write-Verbose "SYSTEM-INVENTORY: Performance tracking unavailable - $_"
        # Performance tracking is optional
    }
    
    try {
        # Display module banner
        Write-Host "`n" -NoNewline
        Write-Host "=================================================" -ForegroundColor Cyan
        Write-Host "  SYSTEM INVENTORY MODULE v3.0" -ForegroundColor White
        Write-Host "=================================================" -ForegroundColor Cyan
        Write-Host "  Type: " -NoNewline -ForegroundColor Gray
        Write-Host "Type 2 (Information Gathering)" -ForegroundColor Yellow
        Write-Host "  Mode: " -NoNewline -ForegroundColor Gray
        Write-Host "Data Collection" -ForegroundColor Green
        Write-Host "=================================================" -ForegroundColor Cyan
        Write-Host ""
        
        Write-Information " Collecting system inventory..." -InformationAction Continue
        
        # Initialize module execution environment
        Initialize-ModuleExecution -ModuleName 'SystemInventory'
        
        # STEP 1: Run Type1 detection (inventory collection)
        # Explicit assignment to prevent pipeline contamination
        $inventoryData = $null
        if (Get-Command -Name 'Get-SystemInventoryAnalysis' -ErrorAction SilentlyContinue) {
            $inventoryData = Get-SystemInventoryAnalysis -Config $Config
        }
        else {
            $inventoryData = Get-SystemInventory -IncludeDetailed:$false
        }
        
        # STEP 2: Save inventory data to temp_files/data/
        $inventoryDataPath = Join-Path (Get-MaintenancePath 'TempRoot') "data\system-inventory.json"
        $null = $inventoryData | ConvertTo-Json -Depth 10 | Set-Content $inventoryDataPath -Encoding UTF8 -ErrorAction Stop
        Write-Information "   System inventory saved to data folder" -InformationAction Continue
        
        # STEP 3: Setup logging (information gathering, minimal logging needed)
        $executionLogDir = Join-Path (Get-MaintenancePath 'TempRoot') "logs\system-inventory"
        if (-not (Test-Path $executionLogDir)) {
            New-Item -Path $executionLogDir -ItemType Directory -Force | Out-Null
        }
        $executionLogPath = Join-Path $executionLogDir "execution.log"
        
        # Log inventory summary
                $computerName = $inventoryData.ComputerName ?? $inventoryData.Metadata.ComputerName ?? $inventoryData.SystemInfo.ComputerName ?? $env:COMPUTERNAME
                $osName = $inventoryData.OperatingSystem.Name ?? $inventoryData.SystemInfo.OSName ?? $inventoryData.SystemInfo.OperatingSystem ?? 'Unknown'
                $osVersion = $inventoryData.OperatingSystem.Version ?? $inventoryData.SystemInfo.OSVersion ?? 'Unknown'
                $osBuild = $inventoryData.OperatingSystem.Build ?? $inventoryData.SystemInfo.Build ?? 'Unknown'
                $cpuName = $inventoryData.Hardware.Processor.Name ?? $inventoryData.Hardware.CPU.Name ?? $inventoryData.SystemInfo.Processor ?? 'Unknown'
                $cpuCores = $inventoryData.Hardware.Processor.Cores ?? $inventoryData.Hardware.CPU.Cores ?? $inventoryData.SystemInfo.Cores ?? 'Unknown'
                $ramGb = $inventoryData.Hardware.Memory.TotalPhysicalGB ?? $inventoryData.SystemInfo.TotalMemoryGB ?? 'Unknown'
                $totalCapacity = $inventoryData.Storage.TotalCapacityGB ?? $inventoryData.Hardware.Storage.TotalCapacityGB ?? 'Unknown'
                $totalFree = $inventoryData.Storage.TotalFreeGB ?? $inventoryData.Hardware.Storage.TotalFreeGB ?? 'Unknown'
                $driveCount = $inventoryData.Storage.Drives.Count ?? $inventoryData.Hardware.Storage.Drives.Count ?? 0
                $adapterCount = $inventoryData.Network.Adapters.Count ?? $inventoryData.Network.AdapterCount ?? 0
                $domainName = $inventoryData.Network.DomainName ?? $inventoryData.SystemInfo.Domain ?? 'Unknown'
                $installedApps = $inventoryData.Software.InstalledApplications ?? $inventoryData.InstalledSoftware.Count ?? 0
                $psVersion = $inventoryData.Software.PowerShellVersion ?? $PSVersionTable.PSVersion.ToString()
                $uptime = $inventoryData.Performance.Uptime ?? $inventoryData.SystemInfo.Uptime ?? 'Unknown'
                $cpuUsage = $inventoryData.Performance.CPUUsage ?? $inventoryData.SystemInfo.CPUUsage ?? 'Unknown'
                $memoryUsage = $inventoryData.Performance.MemoryUsagePercent ?? $inventoryData.SystemInfo.MemoryUsagePercent ?? 'Unknown'

                $logSummary = @"
========================================
System Inventory Collection Log
Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
========================================

COMPUTER INFORMATION:
    Computer Name: $computerName
    OS: $osName
    Version: $osVersion
    Build: $osBuild

HARDWARE:
    CPU: $cpuName
    Cores: $cpuCores
    RAM: $ramGb GB

STORAGE:
    Total Capacity: $totalCapacity GB
    Total Free: $totalFree GB
    Drives: $driveCount

NETWORK:
    Active Adapters: $adapterCount
    Domain: $domainName

SOFTWARE:
    Installed Apps: $installedApps
    PowerShell: $psVersion

PERFORMANCE:
    Uptime: $uptime
    CPU Usage: $cpuUsage
    Memory Usage: $memoryUsage%

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
                ComputerName  = $computerName
                OSVersion     = $osVersion
                TotalRAM      = $ramGb
                InstalledApps = $installedApps
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
                Write-Verbose "SYSTEM-INVENTORY: Performance tracking completion failed - $_"
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
                Write-Verbose "SYSTEM-INVENTORY: Performance tracking error handling failed - $_"
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

