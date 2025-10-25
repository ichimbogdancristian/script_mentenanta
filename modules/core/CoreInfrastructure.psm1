#Requires -Version 7.0

<#
.SYNOPSIS
    Core Infrastructure Module v3.0 (Refactored) - Unified Interface

.DESCRIPTION
    Refactored CoreInfrastructure delegating to four specialized modules:
    - CorePaths.psm1: Global path discovery and management
    - ConfigurationManager.psm1: Configuration loading and validation
    - LoggingSystem.psm1: Structured logging and performance tracking
    - FileOrganization.psm1: Session file organization and management

.NOTES
    Module Type: Core Infrastructure (Unified Interface - v3.0 Refactored)
    Version: 3.0.0 (Refactored - Modular Architecture)
#>

using namespace System.Collections.Generic
using namespace System.IO

#region Module Imports

Write-Verbose "CoreInfrastructure: Importing specialized modules..."

$CorePathsPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'core\CorePaths.psm1'
if (Test-Path $CorePathsPath) {
    Import-Module $CorePathsPath -Force -Global -WarningAction SilentlyContinue
    Write-Verbose "CoreInfrastructure: CorePaths module imported"
}

$ConfigManagerPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'core\ConfigurationManager.psm1'
if (Test-Path $ConfigManagerPath) {
    Import-Module $ConfigManagerPath -Force -WarningAction SilentlyContinue
    Write-Verbose "CoreInfrastructure: ConfigurationManager module imported"
}

$LoggingSystemPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'core\LoggingSystem.psm1'
if (Test-Path $LoggingSystemPath) {
    Import-Module $LoggingSystemPath -Force -WarningAction SilentlyContinue
    Write-Verbose "CoreInfrastructure: LoggingSystem module imported"
}

$FileOrgPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'core\FileOrganization.psm1'
if (Test-Path $FileOrgPath) {
    Import-Module $FileOrgPath -Force -WarningAction SilentlyContinue
    Write-Verbose "CoreInfrastructure: FileOrganization module imported"
}

#endregion

#region Backward Compatibility Aliases

New-Alias -Name 'Initialize-ConfigSystem' -Value 'Initialize-ConfigurationSystem' -Force
New-Alias -Name 'Get-MainConfig' -Value 'Get-MainConfiguration' -Force
New-Alias -Name 'Get-BloatwareList' -Value 'Get-BloatwareConfiguration' -Force
New-Alias -Name 'Get-UnifiedEssentialAppsList' -Value 'Get-EssentialAppsConfiguration' -Force

#endregion

#region Infrastructure Status Function

function Get-InfrastructureStatus {
    [CmdletBinding()]
    param()
    
    $pathsTest = Test-MaintenancePathsIntegrity
    $configTest = Test-ConfigurationIntegrity
    
    return [PSCustomObject]@{
        PathsInitialized = $pathsTest.IsValid
        PathErrors       = $pathsTest.Errors
        ConfigsLoaded    = $configTest.IsValid
        ConfigErrors     = $configTest.Errors
        SessionId        = $env:MAINTENANCE_SESSION_ID
        Timestamp        = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    }
}

function Initialize-MaintenanceInfrastructure {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$ProjectRootPath,
        [Parameter(Mandatory = $false)]
        [string]$ConfigRootPath,
        [Parameter(Mandatory = $false)]
        [string]$TempRootPath
    )
    
    Write-Verbose "Initializing Maintenance Infrastructure..."
    
    try {
        Initialize-GlobalPathDiscovery -HintPath $ProjectRootPath -Force
        $paths = Get-MaintenancePaths
        $configPath = $ConfigRootPath -or $paths.ConfigRoot
        Initialize-ConfigurationSystem -ConfigRootPath $configPath
        Initialize-LoggingSystem -DefaultLogPath (Join-Path $paths.TempRoot 'logs\maintenance.log')
        $tempPath = $TempRootPath -or $paths.TempRoot
        Initialize-SessionFileOrganization -TempRootPath $tempPath
        Write-Verbose "Maintenance Infrastructure initialization complete"
        return $true
    }
    catch {
        Write-Error "Infrastructure initialization failed: $($_.Exception.Message)"
        return $false
    }
}

#endregion

#region Module Exports

Export-ModuleMember -Function @(
    'Initialize-GlobalPathDiscovery', 'Get-MaintenancePaths', 'Get-MaintenancePath', 'Test-MaintenancePathsIntegrity',
    'Initialize-ConfigurationSystem', 'Get-ConfigFilePath', 'Get-MainConfiguration', 'Get-LoggingConfiguration',
    'Get-BloatwareConfiguration', 'Get-EssentialAppsConfiguration', 'Get-AppUpgradeConfiguration', 'Get-ReportTemplatesConfiguration',
    'Get-CachedConfiguration', 'Test-ConfigurationIntegrity',
    'Initialize-LoggingSystem', 'Write-ModuleLogEntry', 'Write-OperationStart', 'Write-OperationSuccess', 'Write-OperationFailure',
    'Start-PerformanceTracking', 'Complete-PerformanceTracking', 'Set-LoggingVerbosity', 'Set-LoggingEnabled',
    'Initialize-SessionFileOrganization', 'Get-SessionFilePath', 'Save-SessionData', 'Get-SessionData', 'Get-SessionDirectoryPath',
    'Clear-SessionTemporaryFiles', 'Get-SessionStatistics',
    'Initialize-MaintenanceInfrastructure', 'Get-InfrastructureStatus'
) -Alias @('Initialize-ConfigSystem', 'Get-MainConfig', 'Get-BloatwareList', 'Get-UnifiedEssentialAppsList')

#endregion

#region Auto-Initialization

try {
    if (-not $env:MAINTENANCE_SESSION_ID) {
        Write-Verbose "Auto-initializing maintenance infrastructure on module import"
        Initialize-MaintenanceInfrastructure -ErrorAction SilentlyContinue | Out-Null
    }
}
catch {
    Write-Verbose "Infrastructure auto-initialization deferred: $($_.Exception.Message)"
}

#endregion
