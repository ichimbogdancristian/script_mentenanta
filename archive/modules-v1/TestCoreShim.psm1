# Minimal test shim for CoreInfrastructure functions used by Type1 modules
# This shim is intended for unit tests only. It provides non-destructive stubs.

function Write-LogEntry {
    param(
        [string]$Level,
        [string]$Component,
        [string]$Message,
        $Data
    )
    # Non-destructive: write to information stream
    Write-Information "[$Level] [$Component] $Message" -InformationAction Continue
}

function Start-PerformanceTracking {
    param([string]$OperationName, [string]$Component)
    # Return a simple object that can be passed back to Complete-PerformanceTracking
    return @{ OperationName = $OperationName; Component = $Component; StartTime = Get-Date }
}

function Complete-PerformanceTracking {
    param($Context, [string]$Status, [string]$ErrorMessage)
    # No-op for tests
    return $true
}

function Get-BloatwareList {
    param([string]$Category = 'all')
    # Return an empty array for tests (no bloatware patterns)
    return @()
}

function Get-UnifiedEssentialAppsList {
    param()
    return @()
}

function Get-MaintenanceProjectPath {
    param([ValidateSet('Root', 'Config', 'Modules', 'TempFiles', 'ParentDir')][string]$PathType = 'Root')
    # Return the current working directory for tests
    return (Get-Location).Path
}

Export-ModuleMember -Function @(
    'Write-LogEntry',
    'Start-PerformanceTracking',
    'Complete-PerformanceTracking',
    'Get-BloatwareList',
    'Get-UnifiedEssentialAppsList',
    'Get-MaintenanceProjectPath'
)
