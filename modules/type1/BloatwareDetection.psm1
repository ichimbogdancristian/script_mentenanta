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

#region Private Functions

<#
.SYNOPSIS
    Gets unified bloatware patterns from configuration files

.DESCRIPTION
    Loads bloatware patterns from the ConfigManager and combines them into a single list
    based on the requested categories.

.PARAMETER IncludeCategories
    Array of category names to include (e.g., @('OEM', 'Windows', 'Gaming', 'Security'))

.EXAMPLE
    $patterns = Get-UnifiedBloatwareList -IncludeCategories @('OEM', 'Windows')
#>
function Get-UnifiedBloatwareList {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string[]]$IncludeCategories = @('OEM', 'Windows', 'Gaming', 'Security')
    )
    
    try {
        # Import ConfigManager module if not already available
        if (-not (Get-Module ConfigManager)) {
            Import-Module (Join-Path $PSScriptRoot '..\core\ConfigManager.psm1') -Force
        }
        
        # Import SystemInventory module if not already available
        if (-not (Get-Module SystemInventory)) {
            Import-Module (Join-Path $PSScriptRoot 'SystemInventory.psm1') -Force
        }
        
        # Get bloatware configuration from ConfigManager
        $bloatwareConfig = Get-BloatwareConfiguration
        
        if (-not $bloatwareConfig -or $bloatwareConfig.Count -eq 0) {
            Write-Warning "No bloatware configuration loaded"
            return @()
        }
        
        $allPatterns = @()
        
        foreach ($category in $IncludeCategories) {
            # Map common category names to file names
            $categoryKey = switch ($category.ToLower()) {
                'oem' { 'oem-bloatware' }
                'windows' { 'windows-bloatware' }
                'gaming' { 'gaming-bloatware' }
                'security' { 'security-bloatware' }
                default { $category }
            }
            
            if ($bloatwareConfig.ContainsKey($categoryKey)) {
                $categoryPatterns = $bloatwareConfig[$categoryKey]
                $allPatterns += $categoryPatterns
                Write-Verbose "Loaded $($categoryPatterns.Count) patterns from category '$category'"
            } else {
                Write-Warning "Bloatware category not found: $category"
            }
        }
        
        Write-Verbose "Total bloatware patterns loaded: $($allPatterns.Count)"
        return $allPatterns
    }
    catch {
        Write-Error "Failed to load bloatware patterns: $_"
        return @()
    }
}

#endregion

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
        [string[]]$Categories = @('OEM', 'Windows', 'Gaming', 'Security'),
        
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
        
        # Scan AppX packages
        Write-Host "  📱 Scanning AppX packages..." -ForegroundColor Gray
        $appxBloatware = Get-AppXBloatware -BloatwarePatterns $bloatwareList -Context $Context -UseCache:$UseCache
        if ($appxBloatware) { $allBloatware.AddRange($appxBloatware) }
        
        # Scan Winget packages
        Write-Host "  📦 Scanning Winget packages..." -ForegroundColor Gray
        $wingetBloatware = Get-WingetBloatware -BloatwarePatterns $bloatwareList -Context $Context -UseCache:$UseCache
        if ($wingetBloatware) { $allBloatware.AddRange($wingetBloatware) }
        
        # Scan Chocolatey packages
        Write-Host "  🍫 Scanning Chocolatey packages..." -ForegroundColor Gray
        $chocoBloatware = Get-ChocolateyBloatware -BloatwarePatterns $bloatwareList -Context $Context -UseCache:$UseCache
        if ($chocoBloatware) { $allBloatware.AddRange($chocoBloatware) }
        
        # Scan Registry entries
        Write-Host "  📋 Scanning Registry entries..." -ForegroundColor Gray
        $registryBloatware = Get-RegistryBloatware -BloatwarePatterns $bloatwareList -Context $Context -UseCache:$UseCache
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
        [string]$Context = "AppX Scan",
        
        [Parameter()]
        [switch]$UseCache
    )
    
    try {
        # Import SystemInventory module if not already available
        if (-not (Get-Module SystemInventory)) {
            Import-Module (Join-Path $PSScriptRoot 'SystemInventory.psm1') -Force
        }
        
        $appInventory = Get-SystemInventory -UseCache:$UseCache
        if (-not $appInventory.InstalledSoftware -or -not $appInventory.InstalledSoftware.Programs) {
            Write-Warning "No software inventory available for AppX scan"
            return @()
        }
        
        # For AppX packages, we need to get them directly since InstalledSoftware doesn't categorize by source
        # Get AppX packages for current user (safer than -AllUsers which requires admin)
        try {
            $appXApps = Get-AppxPackage -ErrorAction Stop | Where-Object { $_.Name -and $_.PublisherDisplayName }
        }
        catch {
            Write-Warning "Failed to get AppX packages: $_"
            return @()
        }
        
        $found = @()
        foreach ($app in $appXApps) {
            foreach ($pattern in $BloatwarePatterns) {
                if ($app.Name -like "*$pattern*" -or $app.PackageFullName -like "*$pattern*") {
                    $found += [PSCustomObject]@{
                        Name           = $app.Name
                        DisplayName    = $app.PackageFullName
                        Version        = $app.Version
                        Publisher      = $app.PublisherDisplayName
                        InstallDate    = $app.InstallDate
                        Source         = 'AppX'
                        MatchedPattern = $pattern
                        Context        = $Context
                        RemovalMethod  = 'Remove-AppxPackage'
                        PackageFullName = $app.PackageFullName
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
        [string]$Context = "Winget Scan",
        
        [Parameter()]
        [switch]$UseCache
    )
    
    try {
        # Import SystemInventory module if not already available
        if (-not (Get-Module SystemInventory)) {
            Import-Module (Join-Path $PSScriptRoot 'SystemInventory.psm1') -Force
        }
        
        $appInventory = Get-SystemInventory -UseCache:$UseCache
        if (-not $appInventory.InstalledSoftware -or -not $appInventory.InstalledSoftware.Programs) {
            Write-Warning "No software inventory available for Winget scan"
            return @()
        }
        
        # Use the installed software data (since we can't easily distinguish Winget vs other sources in registry)
        # We'll scan all installed programs for bloatware patterns
        $installedPrograms = $appInventory.InstalledSoftware.Programs
        
        $found = @()
        foreach ($app in $installedPrograms) {
            foreach ($pattern in $BloatwarePatterns) {
                if ($app.Name -like "*$pattern*" -or $app.Publisher -like "*$pattern*") {
                    $found += [PSCustomObject]@{
                        Name           = $app.Name
                        DisplayName    = $app.Name
                        Version        = $app.Version
                        Publisher      = $app.Publisher
                        InstallDate    = $app.InstallDate
                        Source         = 'Registry'
                        MatchedPattern = $pattern
                        Context        = $Context
                        RemovalMethod  = 'Registry Uninstall'
                        UninstallString = $app.UninstallString
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
        [string]$Context = "Chocolatey Scan",
        
        [Parameter()]
        [switch]$UseCache
    )
    
    try {
        # Import SystemInventory module if not already available
        if (-not (Get-Module SystemInventory)) {
            Import-Module (Join-Path $PSScriptRoot 'SystemInventory.psm1') -Force
        }
        
        # Chocolatey apps are typically not in the registry, so try to get them directly from Chocolatey
        # If Chocolatey is not available, return empty array
        if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
            Write-Warning "Chocolatey not available for scan"
            return @()
        }
        
        # Get Chocolatey installed packages
        try {
            $chocoOutput = & choco list --local-only --no-color 2>$null
            $chocoApps = @()
            foreach ($line in $chocoOutput) {
                if ($line -match '^(\S+)\s+(.+)$' -and $line -notlike '*packages installed*') {
                    $chocoApps += [PSCustomObject]@{
                        Name = $matches[1]
                        Version = $matches[2]
                    }
                }
            }
        }
        catch {
            Write-Warning "Failed to get Chocolatey packages: $_"
            return @()
        }
        
        $found = @()
        foreach ($app in $chocoApps) {
            foreach ($pattern in $BloatwarePatterns) {
                if ($app.Name -like "*$pattern*") {
                    $found += [PSCustomObject]@{
                        Name           = $app.Name
                        DisplayName    = $app.Name
                        Version        = $app.Version
                        Publisher      = 'Chocolatey'
                        InstallDate    = $null
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
        [string]$Context = "Registry Scan",
        
        [Parameter()]
        [switch]$UseCache
    )
    
    try {
        $registryPaths = @(
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
        )
        
        $found = @()
        foreach ($path in $registryPaths) {
            try {
                $apps = Get-ItemProperty $path -ErrorAction SilentlyContinue |
                    Where-Object { 
                        $_.DisplayName -and 
                        $_.DisplayName -notmatch '^KB[0-9]+' -and
                        $_.DisplayName -notmatch '^Update for'
                    }
                
                foreach ($app in $apps) {
                    foreach ($pattern in $BloatwarePatterns) {
                        if ($app.DisplayName -like "*$pattern*" -or $app.PSChildName -like "*$pattern*") {
                            $found += [PSCustomObject]@{
                                Name           = $app.PSChildName
                                DisplayName    = $app.DisplayName
                                Version        = $app.DisplayVersion
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
            }
            catch {
                Write-Warning "Error accessing registry path ${path}: $_"
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