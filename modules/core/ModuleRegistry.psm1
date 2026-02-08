#Requires -Version 7.0

<#
.SYNOPSIS
    Module Registry - Centralized Type1/Type2 Module Discovery & Management

.DESCRIPTION
    Provides automatic module discovery, metadata management, and dependency validation
    for the Windows Maintenance Automation System. Eliminates manual orchestrator edits
    by dynamically discovering modules from the filesystem.

.MODULE ARCHITECTURE
    Purpose:
        Centralize module management and eliminate manual module registration.
        Provide metadata parsing, dependency validation, and module inventory.

    Dependencies:
        • CoreInfrastructure.psm1 - For path management and logging

    Exports:
        • Get-RegisteredModules - Auto-discover modules from filesystem
        • Get-ModuleMetadata - Parse module headers for metadata
        • Test-ModuleDependencies - Validate Type2 → Type1 dependencies
        • Get-ModuleExecutionOrder - Determine optimal execution sequence
        • Show-ModuleInventory - Display module inventory report

    Import Pattern:
        Import-Module ModuleRegistry.psm1 -Force
        # Functions available in MaintenanceOrchestrator context

    Used By:
        - MaintenanceOrchestrator.ps1 (primary consumer)
        - Diagnostic scripts (module inventory)

.EXECUTION FLOW
    1. Orchestrator imports ModuleRegistry
    2. Calls Get-RegisteredModules to discover Type1/Type2 modules
    3. Validates dependencies with Test-ModuleDependencies
    4. Dynamically loads modules in correct order
    5. Executes modules based on metadata

.DATA STRUCTURES

    Module Object:
    @{
        Name = "BloatwareRemoval"
        Type = "Type2"
        Path = "C:\...\modules\type2\BloatwareRemoval.psm1"
        Metadata = @{
            Synopsis = "Bloatware Removal Module"
            Version = "1.0.0"
            Type1Dependency = "BloatwareDetectionAudit"
            OSRequirements = "Windows 10/11"
            ModuleType = "Type2"
        }
        DependsOn = "BloatwareDetectionAudit"
        IsValid = $true
    }

.NOTES
    Module Type: Core Infrastructure
    Architecture: v3.0 - Phase 1 Enhancement
    Version: 1.0.0
    Created: February 4, 2026

    Key Design Patterns:
    - Filesystem-based discovery (no manual registration)
    - Metadata extraction via regex parsing
    - Dependency graph validation
    - Lazy loading (modules loaded on-demand)
#>

using namespace System.Collections.Generic
using namespace System.IO

#region Module Discovery Functions

<#
.SYNOPSIS
    Discovers all modules of specified type from filesystem

.DESCRIPTION
    Automatically scans modules/type1 and modules/type2 directories to discover
    available modules. Parses module headers to extract metadata and dependencies.
    Returns structured module objects for orchestrator consumption.

.PARAMETER ModuleType
    Type of modules to discover: Type1, Type2, Core, or All

.PARAMETER IncludeMetadata
    When specified, parses module headers and includes full metadata

.PARAMETER ValidateOnly
    When specified, only validates module structure without returning full data

.OUTPUTS
    [hashtable] Dictionary of module objects keyed by module name

.EXAMPLE
    $modules = Get-RegisteredModules -ModuleType 'Type2' -IncludeMetadata

    Returns all Type2 modules with full metadata

.EXAMPLE
    $allModules = Get-RegisteredModules -ModuleType 'All'

    Returns all modules (Type1, Type2, Core) with basic info
#>
function Get-RegisteredModules {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter()]
        [ValidateSet('Type1', 'Type2', 'Core', 'All')]
        [string]$ModuleType = 'All',

        [Parameter()]
        [switch]$IncludeMetadata,

        [Parameter()]
        [switch]$ValidateOnly
    )

    try {
        Write-Verbose "MODULE-REGISTRY: Discovering $ModuleType modules..."

        # Get project root from environment or fallback
        $projectRoot = $env:MAINTENANCE_PROJECT_ROOT
        if (-not $projectRoot -or -not (Test-Path $projectRoot)) {
            $projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        }

        $modulesPath = Join-Path $projectRoot 'modules'
        if (-not (Test-Path $modulesPath)) {
            throw "Modules directory not found: $modulesPath"
        }

        $discoveredModules = @{}

        # Scan Type1 modules
        if ($ModuleType -in 'Type1', 'All') {
            $type1Path = Join-Path $modulesPath 'type1'
            if (Test-Path $type1Path) {
                Get-ChildItem -Path $type1Path -Filter '*.psm1' -ErrorAction SilentlyContinue | ForEach-Object {
                    $moduleName = $_.BaseName
                    $metadata = if ($IncludeMetadata) { Get-ModuleMetadata -Path $_.FullName } else { $null }

                    $discoveredModules[$moduleName] = @{
                        Name = $moduleName
                        Type = 'Type1'
                        Path = $_.FullName
                        Metadata = $metadata
                        DependsOn = $null  # Type1 modules don't depend on other modules
                        IsValid = $true
                    }

                    Write-Verbose "MODULE-REGISTRY: Discovered Type1 module: $moduleName"
                }
            }
        }

        # Scan Type2 modules
        if ($ModuleType -in 'Type2', 'All') {
            $type2Path = Join-Path $modulesPath 'type2'
            if (Test-Path $type2Path) {
                Get-ChildItem -Path $type2Path -Filter '*.psm1' -ErrorAction SilentlyContinue | ForEach-Object {
                    $moduleName = $_.BaseName
                    $metadata = if ($IncludeMetadata) { Get-ModuleMetadata -Path $_.FullName } else { $null }

                    $type1Dependency = if ($metadata) { $metadata.Type1Dependency } else { $null }

                    $discoveredModules[$moduleName] = @{
                        Name = $moduleName
                        Type = 'Type2'
                        Path = $_.FullName
                        Metadata = $metadata
                        DependsOn = $type1Dependency
                        IsValid = $true
                    }

                    Write-Verbose "MODULE-REGISTRY: Discovered Type2 module: $moduleName (depends on: $type1Dependency)"
                }
            }
        }

        # Scan Core modules
        if ($ModuleType -in 'Core', 'All') {
            $corePath = Join-Path $modulesPath 'core'
            if (Test-Path $corePath) {
                Get-ChildItem -Path $corePath -Filter '*.psm1' -ErrorAction SilentlyContinue | ForEach-Object {
                    $moduleName = $_.BaseName
                    $metadata = if ($IncludeMetadata) { Get-ModuleMetadata -Path $_.FullName } else { $null }

                    $discoveredModules[$moduleName] = @{
                        Name = $moduleName
                        Type = 'Core'
                        Path = $_.FullName
                        Metadata = $metadata
                        DependsOn = $null
                        IsValid = $true
                    }

                    Write-Verbose "MODULE-REGISTRY: Discovered Core module: $moduleName"
                }
            }
        }

        if ($ValidateOnly) {
            return @{ TotalModules = $discoveredModules.Count; IsValid = $true }
        }

        Write-Verbose "MODULE-REGISTRY: Discovery complete - found $($discoveredModules.Count) modules"
        return $discoveredModules
    }
    catch {
        Write-Warning "MODULE-REGISTRY: Module discovery failed: $_"
        return @{}
    }
}

<#
.SYNOPSIS
    Extracts metadata from module header comments

.DESCRIPTION
    Parses module .SYNOPSIS, .DESCRIPTION, .NOTES sections to extract:
    - Module synopsis (brief description)
    - Version number
    - Type1 dependency (for Type2 modules)
    - OS requirements
    - Module type classification

.PARAMETER Path
    Full path to the module .psm1 file

.OUTPUTS
    [hashtable] Module metadata object

.EXAMPLE
    $metadata = Get-ModuleMetadata -Path "C:\modules\type2\BloatwareRemoval.psm1"

    Returns metadata for BloatwareRemoval module
#>
function Get-ModuleMetadata {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [ValidateScript({ Test-Path $_ })]
        [string]$Path
    )

    try {
        $content = Get-Content -Path $Path -Raw -ErrorAction Stop

        # Extract synopsis
        $synopsis = if ($content -match '(?ms)\.SYNOPSIS\s+(.*?)\.(DESCRIPTION|PARAMETER|EXAMPLE|NOTES)') {
            $Matches[1].Trim() -replace '\r?\n', ' '
        }
        else {
            "No synopsis available"
        }

        # Extract version
        $version = if ($content -match 'Version:\s*(\d+\.\d+\.\d+)') {
            $Matches[1]
        }
        else {
            '1.0.0'
        }

        # Extract Type1 dependency (for Type2 modules)
        $type1Dependency = $null
        if ($content -match 'Dependencies:\s*([A-Za-z]+)Audit\.psm1') {
            $type1Dependency = $Matches[1] + 'Audit'
        }
        elseif ($content -match "Import-Module.*\\type1\\([A-Za-z]+Audit)\.psm1") {
            $type1Dependency = $Matches[1]
        }

        # Extract OS requirements
        $osRequirements = if ($content -match 'OS:\s*(Windows\s*\d+[/\s]*\d*)') {
            $Matches[1]
        }
        else {
            'Windows 10/11'
        }

        # Determine module type from content
        $moduleType = if ($content -match 'Module Type:\s*(Type\s*[12]|Core)') {
            $Matches[1] -replace '\s', ''
        }
        else {
            # Infer from path
            if ($Path -match '\\type1\\') { 'Type1' }
            elseif ($Path -match '\\type2\\') { 'Type2' }
            elseif ($Path -match '\\core\\') { 'Core' }
            else { 'Unknown' }
        }

        return @{
            Synopsis = $synopsis
            Version = $version
            Type1Dependency = $type1Dependency
            OSRequirements = $osRequirements
            ModuleType = $moduleType
            LastModified = (Get-Item $Path).LastWriteTime
            SizeKB = [math]::Round((Get-Item $Path).Length / 1KB, 2)
        }
    }
    catch {
        Write-Warning "MODULE-REGISTRY: Failed to parse metadata from $Path`: $_"
        return @{
            Synopsis = "Metadata parsing failed"
            Version = '0.0.0'
            Type1Dependency = $null
            OSRequirements = 'Unknown'
            ModuleType = 'Unknown'
        }
    }
}

<#
.SYNOPSIS
    Validates Type2 → Type1 module dependencies

.DESCRIPTION
    Checks if specified Type2 module has its required Type1 dependency available.
    Validates that Type1 module exists and can be loaded.

.PARAMETER ModuleName
    Name of the Type2 module to validate

.PARAMETER Modules
    Optional pre-loaded module dictionary from Get-RegisteredModules

.OUTPUTS
    [bool] True if dependencies are satisfied, False otherwise

.EXAMPLE
    $isValid = Test-ModuleDependencies -ModuleName 'BloatwareRemoval'

    Validates BloatwareRemoval → BloatwareDetectionAudit dependency
#>
function Test-ModuleDependencies {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$ModuleName,

        [Parameter()]
        [hashtable]$Modules
    )

    try {
        # Load modules if not provided
        if (-not $Modules) {
            $Modules = Get-RegisteredModules -ModuleType 'All' -IncludeMetadata
        }

        # Check if module exists
        if (-not $Modules.ContainsKey($ModuleName)) {
            Write-Warning "MODULE-REGISTRY: Module not found: $ModuleName"
            return $false
        }

        $targetModule = $Modules[$ModuleName]

        # Type1 and Core modules have no dependencies
        if ($targetModule.Type -in 'Type1', 'Core') {
            return $true
        }

        # Type2 modules require Type1 dependency
        if ($targetModule.DependsOn) {
            $dependency = $Modules[$targetModule.DependsOn]
            if (-not $dependency) {
                Write-Warning "MODULE-REGISTRY: Missing Type1 dependency '$($targetModule.DependsOn)' required by '$ModuleName'"
                return $false
            }

            # Verify Type1 module file exists
            if (-not (Test-Path $dependency.Path)) {
                Write-Warning "MODULE-REGISTRY: Type1 dependency file not found: $($dependency.Path)"
                return $false
            }

            Write-Verbose "MODULE-REGISTRY: Dependency validated: $ModuleName → $($targetModule.DependsOn)"
            return $true
        }

        # Type2 module without dependency (unusual but valid)
        Write-Verbose "MODULE-REGISTRY: Module $ModuleName has no Type1 dependency"
        return $true
    }
    catch {
        Write-Warning "MODULE-REGISTRY: Dependency validation failed for $ModuleName`: $_"
        return $false
    }
}

<#
.SYNOPSIS
    Determines optimal module execution order based on dependencies

.DESCRIPTION
    Analyzes module dependency graph and returns execution order that ensures
    Type1 modules are loaded before their corresponding Type2 modules.

.PARAMETER Modules
    Module dictionary from Get-RegisteredModules

.OUTPUTS
    [string[]] Array of module names in execution order

.EXAMPLE
    $executionOrder = Get-ModuleExecutionOrder -Modules $allModules

    Returns ordered list: Type1 modules first, then Type2 modules
#>
function Get-ModuleExecutionOrder {
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Modules
    )

    $executionOrder = [List[string]]::new()

    # Phase 1: Core modules (already loaded by orchestrator)
    $coreModules = $Modules.Values | Where-Object { $_.Type -eq 'Core' } | Sort-Object Name
    foreach ($module in $coreModules) {
        $executionOrder.Add($module.Name)
    }

    # Phase 2: Type1 modules (audit/inventory - no dependencies)
    $type1Modules = $Modules.Values | Where-Object { $_.Type -eq 'Type1' } | Sort-Object Name
    foreach ($module in $type1Modules) {
        $executionOrder.Add($module.Name)
    }

    # Phase 3: Type2 modules (system modification - depend on Type1)
    # Sort by dependency to ensure Type1 loaded first if needed
    $type2Modules = $Modules.Values | Where-Object { $_.Type -eq 'Type2' }
    $sortedType2 = $type2Modules | Sort-Object @{Expression = { $_.DependsOn }; Ascending = $true }, Name

    foreach ($module in $sortedType2) {
        # Verify dependency exists in execution order
        if ($module.DependsOn -and $module.DependsOn -notin $executionOrder) {
            Write-Warning "MODULE-REGISTRY: Dependency '$($module.DependsOn)' not in execution order for '$($module.Name)'"
        }
        $executionOrder.Add($module.Name)
    }

    return $executionOrder.ToArray()
}

<#
.SYNOPSIS
    Displays comprehensive module inventory report

.DESCRIPTION
    Generates formatted console output showing all discovered modules,
    their metadata, dependencies, and validation status.

.PARAMETER Modules
    Optional pre-loaded module dictionary

.EXAMPLE
    Show-ModuleInventory

    Displays full module inventory report
#>
function Show-ModuleInventory {
    [CmdletBinding()]
    param(
        [Parameter()]
        [hashtable]$Modules
    )

    # Load modules if not provided
    if (-not $Modules) {
        $Modules = Get-RegisteredModules -ModuleType 'All' -IncludeMetadata
    }

    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "  MODULE REGISTRY INVENTORY" -ForegroundColor White
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  Total Modules: " -NoNewline -ForegroundColor Gray
    Write-Host $Modules.Count -ForegroundColor Green
    Write-Host ""

    # Group by type
    $type1Count = ($Modules.Values | Where-Object { $_.Type -eq 'Type1' }).Count
    $type2Count = ($Modules.Values | Where-Object { $_.Type -eq 'Type2' }).Count
    $coreCount = ($Modules.Values | Where-Object { $_.Type -eq 'Core' }).Count

    Write-Host "  Type1 (Audit): " -NoNewline -ForegroundColor Gray
    Write-Host $type1Count -ForegroundColor Cyan
    Write-Host "  Type2 (Action): " -NoNewline -ForegroundColor Gray
    Write-Host $type2Count -ForegroundColor Yellow
    Write-Host "  Core (Infrastructure): " -NoNewline -ForegroundColor Gray
    Write-Host $coreCount -ForegroundColor Magenta
    Write-Host ""

    # Display Type1 modules
    Write-Host "Type1 Modules (Audit/Inventory):" -ForegroundColor Cyan
    Write-Host "─────────────────────────────────" -ForegroundColor Gray
    $Modules.Values | Where-Object { $_.Type -eq 'Type1' } | Sort-Object Name | ForEach-Object {
        Write-Host "  • " -NoNewline -ForegroundColor Cyan
        Write-Host "$($_.Name)" -NoNewline -ForegroundColor White
        if ($_.Metadata) {
            Write-Host " (v$($_.Metadata.Version))" -ForegroundColor Gray
        }
        else {
            Write-Host ""
        }
    }
    Write-Host ""

    # Display Type2 modules with dependencies
    Write-Host "Type2 Modules (System Modification):" -ForegroundColor Yellow
    Write-Host "─────────────────────────────────────" -ForegroundColor Gray
    $Modules.Values | Where-Object { $_.Type -eq 'Type2' } | Sort-Object Name | ForEach-Object {
        Write-Host "  • " -NoNewline -ForegroundColor Yellow
        Write-Host "$($_.Name)" -NoNewline -ForegroundColor White
        if ($_.DependsOn) {
            Write-Host " → $($_.DependsOn)" -NoNewline -ForegroundColor Gray
        }
        if ($_.Metadata) {
            Write-Host " (v$($_.Metadata.Version))" -ForegroundColor Gray
        }
        else {
            Write-Host ""
        }
    }
    Write-Host ""

    # Display Core modules
    Write-Host "Core Modules (Infrastructure):" -ForegroundColor Magenta
    Write-Host "──────────────────────────────" -ForegroundColor Gray
    $Modules.Values | Where-Object { $_.Type -eq 'Core' } | Sort-Object Name | ForEach-Object {
        Write-Host "  • " -NoNewline -ForegroundColor Magenta
        Write-Host "$($_.Name)" -NoNewline -ForegroundColor White
        if ($_.Metadata) {
            Write-Host " (v$($_.Metadata.Version))" -ForegroundColor Gray
        }
        else {
            Write-Host ""
        }
    }
    Write-Host "========================================`n" -ForegroundColor Cyan
}

#endregion

# Export public functions
Export-ModuleMember -Function @(
    'Get-RegisteredModules',
    'Get-ModuleMetadata',
    'Test-ModuleDependencies',
    'Get-ModuleExecutionOrder',
    'Show-ModuleInventory'
)

