#Requires -Version 7.0

<#
.SYNOPSIS
    Bloatware Detection Module - Type 1 (Inventory/Reporting)

.DESCRIPTION
    Comprehensive bloatware detection across multiple package managers and installation sources.
    Identifies unwanted software through pattern matching against configurable bloatware lists.

.NOTES
    Module Type: Type 1 (Inventory/Reporting)
    Dependencies: ConfigManager.psm1, SystemInventory.psm1
    Author: Windows Maintenance Automation Project
    Version: 1.0.0
#>

using namespace System.Collections.Generic
using namespace System.Collections.Concurrent

# Import required modules
$ModuleRoot = Split-Path -Parent $PSScriptRoot
$SystemInventoryPath = Join-Path $ModuleRoot 'type1\SystemInventory.psm1'
if (Test-Path $SystemInventoryPath) {
    Import-Module $SystemInventoryPath -Force
}

#region Public Functions

<#
.SYNOPSIS
    Performs comprehensive bloatware detection across all sources
    
.DESCRIPTION
    Scans AppX packages, Winget, Chocolatey, and registry entries to identify
    potentially unwanted software based on configurable pattern lists.
    
.PARAMETER UseCache
    Use cached system inventory data if available
    
.PARAMETER Categories
    Specific bloatware categories to check (OEM, Windows, Gaming, Security)
    
.PARAMETER Context
    Context for logging and progress tracking
    
.EXAMPLE
    $bloatware = Find-InstalledBloatware -Categories @('OEM', 'Windows')
    
.EXAMPLE
    $allBloatware = Find-InstalledBloatware -UseCache
#>
function Find-InstalledBloatware {
    [CmdletBinding()]
    param(
        [Parameter()]
        [switch]$UseCache,
        
        [Parameter()]
        [string[]]$Categories = @('all'),
        
        [Parameter()]
        [string]$Context = "Bloatware Detection"
    )
    
    Write-Host "🔍 Scanning for installed bloatware..." -ForegroundColor Cyan
    $startTime = Get-Date
    
    try {
        # Get bloatware patterns from configuration
        $bloatwareList = Get-UnifiedBloatwareList -IncludeCategories $Categories
        if (-not $bloatwareList -or $bloatwareList.Count -eq 0) {
            Write-Warning "No bloatware patterns found in configuration"
            return @()
        }
        
        Write-Host "  📋 Loaded $($bloatwareList.Count) bloatware patterns from $($Categories.Count) categories" -ForegroundColor Gray
        
        # Initialize results collection
        $allBloatware = [List[PSCustomObject]]::new()
        
        # Get system inventory once to avoid repeated calls
        Write-Host "  📊 Collecting system inventory..." -ForegroundColor Gray
        $systemInventory = Get-SystemInventory -UseCache:$UseCache
        
        if (-not $systemInventory.InstalledSoftware -or -not $systemInventory.InstalledSoftware.Programs) {
            Write-Warning "No installed software inventory found"
            return @()
        }
        
        $installedPrograms = $systemInventory.InstalledSoftware.Programs
        
        # Scan AppX packages
        Write-Host "  📱 Scanning AppX packages..." -ForegroundColor Gray
        $appxBloatware = Get-AppXBloatware -BloatwarePatterns $bloatwareList -InstalledPrograms $installedPrograms -Context $Context
        if ($appxBloatware) { $allBloatware.AddRange($appxBloatware) }
        
        # Scan Winget packages
        Write-Host "  📦 Scanning Winget packages..." -ForegroundColor Gray
        $wingetBloatware = Get-WingetBloatware -BloatwarePatterns $bloatwareList -InstalledPrograms $installedPrograms -Context $Context
        if ($wingetBloatware) { $allBloatware.AddRange($wingetBloatware) }
        
        # Scan Chocolatey packages
        Write-Host "  🍫 Scanning Chocolatey packages..." -ForegroundColor Gray
        $chocoBloatware = Get-ChocolateyBloatware -BloatwarePatterns $bloatwareList -InstalledPrograms $installedPrograms -Context $Context
        if ($chocoBloatware) { $allBloatware.AddRange($chocoBloatware) }
        
        # Scan Registry entries
        Write-Host "  📋 Scanning Registry entries..." -ForegroundColor Gray
        $registryBloatware = Get-RegistryBloatware -BloatwarePatterns $bloatwareList -InstalledPrograms $installedPrograms -Context $Context
        if ($registryBloatware) { $allBloatware.AddRange($registryBloatware) }
        
        # Remove duplicates and sort results
        $uniqueBloatware = $allBloatware | 
            Sort-Object Name, Source | 
            Group-Object Name | 
            ForEach-Object { $_.Group | Select-Object -First 1 }
        
        $duration = ((Get-Date) - $startTime).TotalSeconds
        $sourceStats = $allBloatware | Group-Object Source | ForEach-Object { "$($_.Name): $($_.Count)" }
        
        Write-Host "  ✅ Found $($uniqueBloatware.Count) unique bloatware items in $([math]::Round($duration, 2))s" -ForegroundColor Green
        Write-Host "  📊 Sources: $($sourceStats -join ', ')" -ForegroundColor Gray
        
        return $uniqueBloatware
    }
    catch {
        Write-Error "Failed to detect bloatware: $_"
        throw
    }
}

<#
.SYNOPSIS
    Gets bloatware detection summary statistics
    
.DESCRIPTION
    Provides statistical analysis of detected bloatware by source, category, and risk level.
    
.PARAMETER BloatwareList
    Array of detected bloatware items
    
.EXAMPLE
    $stats = Get-BloatwareStatistics -BloatwareList $detectedBloatware
#>
function Get-BloatwareStatistics {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [Array]$BloatwareList
    )
    
    if ($BloatwareList.Count -eq 0) {
        return @{
            TotalItems = 0
            BySource = @{}
            ByCategory = @{}
            TotalSizeEstimate = "Unknown"
        }
    }
    
    $bySource = $BloatwareList | Group-Object Source | ForEach-Object {
        @{ $_.Name = $_.Count }
    } | ForEach-Object { $_ }
    
    $byCategory = $BloatwareList | Group-Object MatchedPattern | ForEach-Object {
        @{ $_.Name = $_.Count }
    } | ForEach-Object { $_ }
    
    return @{
        TotalItems = $BloatwareList.Count
        BySource = $bySource
        ByCategory = $byCategory
        TotalSizeEstimate = "Calculation not available"
        MostCommonSource = ($BloatwareList | Group-Object Source | Sort-Object Count -Descending | Select-Object -First 1).Name
        MostCommonPattern = ($BloatwareList | Group-Object MatchedPattern | Sort-Object Count -Descending | Select-Object -First 1).Name
    }
}

#endregion

#region AppX Bloatware Detection

<#
.SYNOPSIS
    Discovers bloatware in AppX packages (Windows Store apps)
#>
function Get-AppXBloatware {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string[]]$BloatwarePatterns,
        
        [Parameter()]
        [array]$InstalledPrograms,
        
        [Parameter()]
        [string]$Context = "AppX Scan"
    )
    
    try {
        if (-not $InstalledPrograms) {
            Write-Warning "No app inventory available for AppX scan"
            return @()
        }
        
        $appXApps = $InstalledPrograms | Where-Object { $_.Source -eq 'AppX' }
        
        $found = @()
        foreach ($app in $appXApps) {
            foreach ($pattern in $BloatwarePatterns) {
                if ($app.Name -like "*$pattern*" -or $app.DisplayName -like "*$pattern*") {
                    $found += [PSCustomObject]@{
                        Name           = $app.Name
                        DisplayName    = $app.DisplayName
                        Version        = $app.Version
                        Publisher      = $app.Publisher
                        InstallDate    = $app.InstallDate
                        Source         = 'AppX'
                        MatchedPattern = $pattern
                        Context        = $Context
                        RemovalMethod  = 'Remove-AppxPackage'
                    }
                    break  # Only match first pattern to avoid duplicates
                }
            }
        }
        
        return $found
    }
    catch {
        Write-Warning "Error in AppX bloatware scan: $_"
        return @()
    }
}

#endregion

#region Winget Bloatware Detection

<#
.SYNOPSIS
    Discovers bloatware in Winget packages
#>
function Get-WingetBloatware {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string[]]$BloatwarePatterns,
        
        [Parameter()]
        [array]$InstalledPrograms,
        
        [Parameter()]
        [string]$Context = "Winget Scan"
    )
    
    try {
        if (-not $InstalledPrograms) {
            Write-Warning "No app inventory available for Winget scan"
            return @()
        }
        
        $wingetApps = $InstalledPrograms | Where-Object { $_.Source -eq 'Winget' }
        
        $found = @()
        foreach ($app in $wingetApps) {
            foreach ($pattern in $BloatwarePatterns) {
                if ($app.Name -like "*$pattern*" -or $app.DisplayName -like "*$pattern*") {
                    $found += [PSCustomObject]@{
                        Name           = $app.Name
                        DisplayName    = $app.DisplayName
                        Version        = $app.Version
                        Publisher      = $app.Publisher
                        InstallDate    = $app.InstallDate
                        Source         = 'Winget'
                        MatchedPattern = $pattern
                        Context        = $Context
                        RemovalMethod  = 'winget uninstall'
                    }
                    break  # Only match first pattern to avoid duplicates
                }
            }
        }
        
        return $found
    }
    catch {
        Write-Warning "Error in Winget bloatware scan: $_"
        return @()
    }
}

#endregion

#region Chocolatey Bloatware Detection

<#
.SYNOPSIS
    Discovers bloatware in Chocolatey packages
#>
function Get-ChocolateyBloatware {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string[]]$BloatwarePatterns,
        
        [Parameter()]
        [array]$InstalledPrograms,
        
        [Parameter()]
        [string]$Context = "Chocolatey Scan"
    )
    
    try {
        if (-not $InstalledPrograms) {
            Write-Warning "No app inventory available for Chocolatey scan"
            return @()
        }
        
        $chocoApps = $InstalledPrograms | Where-Object { $_.Source -eq 'Chocolatey' }
        
        $found = @()
        foreach ($app in $chocoApps) {
            foreach ($pattern in $BloatwarePatterns) {
                if ($app.Name -like "*$pattern*" -or $app.DisplayName -like "*$pattern*") {
                    $found += [PSCustomObject]@{
                        Name           = $app.Name
                        DisplayName    = $app.DisplayName
                        Version        = $app.Version
                        Publisher      = $app.Publisher
                        InstallDate    = $app.InstallDate
                        Source         = 'Chocolatey'
                        MatchedPattern = $pattern
                        Context        = $Context
                        RemovalMethod  = 'choco uninstall'
                    }
                    break  # Only match first pattern to avoid duplicates
                }
            }
        }
        
        return $found
    }
    catch {
        Write-Warning "Error in Chocolatey bloatware scan: $_"
        return @()
    }
}

#endregion

#region Registry Bloatware Detection

<#
.SYNOPSIS
    Discovers bloatware in Windows Registry uninstall keys
#>
function Get-RegistryBloatware {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string[]]$BloatwarePatterns,
        
        [Parameter()]
        [array]$InstalledPrograms,
        
        [Parameter()]
        [string]$Context = "Registry Scan"
    )
    
    try {
        if (-not $InstalledPrograms) {
            Write-Warning "No app inventory available for Registry scan"
            return @()
        }
        
        $registryApps = $InstalledPrograms | Where-Object { $_.Source -eq 'Registry' }
        
        $found = @()
        foreach ($app in $registryApps) {
            foreach ($pattern in $BloatwarePatterns) {
                if ($app.Name -like "*$pattern*" -or $app.DisplayName -like "*$pattern*") {
                    $found += [PSCustomObject]@{
                        Name           = $app.Name
                        DisplayName    = $app.DisplayName
                        Version        = $app.Version
                        Publisher      = $app.Publisher
                        InstallDate    = $app.InstallDate
                        Source         = 'Registry'
                        MatchedPattern = $pattern
                        Context        = $Context
                        RemovalMethod  = 'Registry-based uninstall'
                        UninstallString = $app.UninstallString
                    }
                    break  # Only match first pattern to avoid duplicates
                }
            }
        }
        
        return $found
    }
    catch {
        Write-Warning "Error in Registry bloatware scan: $_"
        return @()
    }
}

#endregion

#region Helper Functions

<#
.SYNOPSIS
    Validates bloatware detection results
#>
function Test-BloatwareDetection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [Array]$DetectedItems
    )
    
    $validationResults = @{
        TotalItems = $DetectedItems.Count
        ValidItems = 0
        InvalidItems = 0
        MissingProperties = @()
        Sources = @()
    }
    
    $requiredProperties = @('Name', 'Source', 'MatchedPattern')
    
    foreach ($item in $DetectedItems) {
        $isValid = $true
        
        foreach ($property in $requiredProperties) {
            if (-not $item.$property) {
                $validationResults.MissingProperties += "$($item.Name ?? 'Unknown') missing $property"
                $isValid = $false
            }
        }
        
        if ($isValid) {
            $validationResults.ValidItems++
        } else {
            $validationResults.InvalidItems++
        }
        
        if ($item.Source -notin $validationResults.Sources) {
            $validationResults.Sources += $item.Source
        }
    }
    
    return $validationResults
}

#endregion

# Export module functions
Export-ModuleMember -Function @(
    'Find-InstalledBloatware',
    'Get-BloatwareStatistics',
    'Test-BloatwareDetection'
)