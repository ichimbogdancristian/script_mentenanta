#Requires -Version 7.0

<#
.SYNOPSIS
    Core Infrastructure Module v3.0 - Unified Infrastructure Provider

.DESCRIPTION
    Consolidated infrastructure providing unified access to all core system functions:
    - Configuration management (loading, validation, caching)
    - Structured logging (multiple output formats, performance tracking)
    - File organization (session management, temp directory structure)
    - Audit path standardization (Type1 results, Type2 diffs)

.MODULE ARCHITECTURE
    Purpose: 
        Serve as the single point of entry for all core infrastructure functions.
        All modules import this with -Global flag to make functions available to all dependencies.
    
    Dependencies:
        None - this is the foundation module
    
    Exports:
        • Get-InfrastructureStatus - Check infrastructure health
        • Initialize-MaintenanceInfrastructure - Initialize all systems
        • Get-AuditResultsPath - Standard Type1 audit result paths (FIX #4)
        • Save-DiffResults - Standard Type2 diff persistence (FIX #6)
    
    Import Pattern:
        Import-Module CoreInfrastructure.psm1 -Force -Global
        # Makes all functions available to importing module and its dependencies
    
    Used By:
        - UserInterface.psm1
        - LogProcessor.psm1
        - ReportGenerator.psm1
        - All Type2 modules (internally)
        - All Type1 modules (via global scope)

.EXECUTION FLOW
    1. MaintenanceOrchestrator imports CoreInfrastructure with -Global
    2. All functions become available globally in PowerShell session
    3. Other core modules import CoreInfrastructure (functions already available)
    4. Type2 modules import CoreInfrastructure with -Global (availability cascades)
    5. Type1 modules access CoreInfrastructure functions via inherited global scope

.DATA ORGANIZATION
    - Config: config/lists/ (bloatware-list.json, essential-apps.json, app-upgrade-config.json)
    - Config: config/settings/ (main-config.json, logging-config.json)
    - Audit Results: temp_files/data/[module]-results.json (Type1 output)
    - Diff Lists: temp_files/temp/[module]-diff.json (Type2 processing)
    - Execution Logs: temp_files/logs/[module]/execution.log (Type2 output)
    - Session Manifest: temp_files/data/session-[sessionId].json (FIX #9)

.NOTES
    Module Type: Core Infrastructure (Unified Interface - v3.0)
    Architecture: v3.0 - Split with Consolidated Core
    Line Count: 263 lines
    Version: 3.0

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

<#
.SYNOPSIS
    Check infrastructure initialization status and health

.DESCRIPTION
    Validates that all core infrastructure systems are properly initialized.
    Tests path integrity, configuration loading, and session setup.
    
    This function is called during initialization to verify that CoreInfrastructure
    has successfully loaded all dependencies and is ready for use by other modules.

.OUTPUTS
    PSCustomObject with properties:
    - PathsInitialized: Boolean indicating if paths are valid
    - PathErrors: Array of path validation errors (if any)
    - ConfigsLoaded: Boolean indicating if configs loaded successfully
    - ConfigErrors: Array of config validation errors (if any)
    - SessionId: Current session GUID
    - Timestamp: Current time in ISO 8601 format

.EXAMPLE
    $status = Get-InfrastructureStatus
    if ($status.PathsInitialized -and $status.ConfigsLoaded) {
        Write-Host "Infrastructure ready"
    }
#>
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

<#
.SYNOPSIS
    Initialize all maintenance infrastructure systems

.DESCRIPTION
    Consolidated initialization function that sets up all infrastructure:
    1. Global path discovery (project structure auto-detection)
    2. Configuration system (load and validate all configs)
    3. Logging system (initialize structured logging)
    4. File organization (create session directories)
    
    Called once during MaintenanceOrchestrator initialization.
    All functions become available globally after this completes.

.PARAMETER ProjectRootPath
    Optional hint for project root directory

.PARAMETER ConfigRootPath
    Optional override for configuration directory

.PARAMETER TempRootPath
    Optional override for temporary files directory

.OUTPUTS
    Boolean: $true if all systems initialized successfully, $false otherwise

.NOTES
    Called During: MaintenanceOrchestrator.ps1 startup (after module load)
    Critical For: All subsequent module operations
    Side Effects: Creates temp_files directory structure, sets environment variables

.EXAMPLE
    $initialized = Initialize-MaintenanceInfrastructure
    if (-not $initialized) { exit 1 }
#>
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

#region v3.0 FIX #4: Standardized Audit Results Path Function

<#
.SYNOPSIS
    Gets the standardized path for Type1 audit results

.DESCRIPTION
    FIX #4: Provides centralized, standardized path for all Type1 modules to save detection results.
    This ensures consistent file organization and prevents path inconsistencies across different modules.

.PARAMETER ModuleName
    Name of the Type1 module (e.g., 'BloatwareDetection', 'EssentialApps', 'SystemOptimization')

.OUTPUTS
    System.String - Full path to audit results JSON file

.EXAMPLE
    $auditPath = Get-AuditResultsPath -ModuleName 'BloatwareDetection'
    # Returns: C:\...\temp_files\data\bloatware-detection-results.json
#>
function Get-AuditResultsPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ModuleName
    )
    
    try {
        # Get base data directory path
        $dataDir = Get-SessionDirectoryPath -Category 'data'
        
        # Standardize module name format: convert to lowercase with hyphens
        $normalizedName = $ModuleName -replace 'Detection|Audit', '' -replace '(?<=[a-z])(?=[A-Z])', '-' | ForEach-Object { $_.ToLower() }
        
        # Build standardized path: temp_files/data/[module-name]-results.json
        $resultFileName = "$normalizedName-results.json"
        $fullPath = Join-Path $dataDir $resultFileName
        
        return $fullPath
    }
    catch {
        Write-Error "Failed to get audit results path for module '$ModuleName': $($_.Exception.Message)"
        return $null
    }
}

#endregion

#region v3.0 FIX #6: Standardized Diff Results Persistence Function

<#
.SYNOPSIS
    Saves Type2 module diff results to standardized location

.DESCRIPTION
    FIX #6: Provides centralized function for Type2 modules to persist diff lists.
    Diff lists contain only items from configuration that were actually detected on the system.
    These are saved for audit compliance and can be referenced for validation.

.PARAMETER ModuleName
    Name of the Type2 module (e.g., 'BloatwareRemoval', 'EssentialApps', 'SystemOptimization')

.PARAMETER DiffData
    Array of diff items to save (items matched from config)

.PARAMETER Component
    Component name for logging (e.g., 'BLOATWARE-REMOVAL', 'ESSENTIAL-APPS')

.OUTPUTS
    System.String - Full path where diff was saved

.EXAMPLE
    $diffPath = Save-DiffResults -ModuleName 'BloatwareRemoval' -DiffData $diffList -Component 'BLOATWARE-REMOVAL'
    # Returns: C:\...\temp_files\temp\bloatware-removal-diff.json
#>
function Save-DiffResults {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ModuleName,
        
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [array]$DiffData,
        
        [Parameter(Mandatory = $false)]
        [string]$Component = 'CORE'
    )
    
    try {
        # Get base temp directory path for diff storage
        $tempDir = Get-SessionDirectoryPath -Category 'temp'
        
        # Standardize module name format: convert to lowercase with hyphens
        $normalizedName = $ModuleName -replace 'Type2|Module|Removal|Disable|Optimization', '' -replace '(?<=[a-z])(?=[A-Z])', '-' | ForEach-Object { $_.ToLower() }
        
        # Build standardized path: temp_files/temp/[module-name]-diff.json
        $diffFileName = "$normalizedName-diff.json"
        $diffPath = Join-Path $tempDir $diffFileName
        
        # Ensure temp directory exists
        if (-not (Test-Path $tempDir)) {
            New-Item -Path $tempDir -ItemType Directory -Force | Out-Null
        }
        
        # Save diff data as JSON
        $DiffData | ConvertTo-Json -Depth 20 -WarningAction SilentlyContinue | Set-Content $diffPath -Encoding UTF8 -Force
        
        # Log the operation
        Write-ModuleLogEntry -Level 'DEBUG' -Component $Component -Message "Saved diff list for $ModuleName`: $($DiffData.Count) items to $diffPath"
        
        return $diffPath
    }
    catch {
        Write-Error "Failed to save diff results for module '$ModuleName': $($_.Exception.Message)"
        return $null
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
    'Initialize-MaintenanceInfrastructure', 'Get-InfrastructureStatus',
    'Get-AuditResultsPath', 'Save-DiffResults'
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
