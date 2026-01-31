#Requires -Version 7.0
# Module Dependencies:
#   - CoreInfrastructure.psm1 (for configuration and logging - loaded globally)
#   - SystemInventory.psm1 (for system data collection)

<#
.SYNOPSIS
    Bloatware Detection Module - Type 1 (Inventory/Reporting)

.DESCRIPTION
    Comprehensive bloatware detection across multiple package managers and installation sources.
    Identifies unwanted software through pattern matching against configurable bloatware lists.

.NOTES
    Module Type: Type 1 (Inventory/Reporting)
    Dependencies: CoreInfrastructure.psm1, SystemInventory.psm1
    Author: Windows Maintenance Automation Project
    Version: 1.0.0
#>

using namespace System.Collections.Generic
using namespace System.Collections.Concurrent

# Import required modules
$ModuleRoot = Split-Path -Parent $PSScriptRoot
$SystemAnalysisPath = Join-Path $ModuleRoot 'core\SystemAnalysis.psm1'
if (Test-Path $SystemAnalysisPath) {
    Import-Module $SystemAnalysisPath -Force
}

# v3.0 Type 1 module - imported by Type 2 modules
# Note: CoreInfrastructure should be loaded by the Type 2 module before importing this module
# Check if CoreInfrastructure functions are available (loaded by Type2 module)
if (Get-Command 'Get-BloatwareConfiguration' -ErrorAction SilentlyContinue) {
    Write-Verbose "CoreInfrastructure functions detected - using configuration-based bloatware list"
}
else {
    # Non-critical: Function will be available once Type2 module completes global import
    Write-Verbose "CoreInfrastructure global import in progress - Get-BloatwareConfiguration will be available momentarily"
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
    [OutputType([hashtable])]`nparam(
        [Parameter()]
        [switch]$UseCache,

        [Parameter()]
        [string[]]$Categories = @('all'),

        [Parameter()]
        [string]$Context = "Bloatware Detection"
    )

    Write-Information " Scanning for installed bloatware..." -InformationAction Continue
    $startTime = Get-Date

    # Start performance tracking and centralized logging
    $perfContext = $null
    try {
        $perfContext = Start-PerformanceTracking -OperationName 'BloatwareDetection' -Component 'BLOATWARE-DETECTION'
        Write-LogEntry -Level 'INFO' -Component 'BLOATWARE-DETECTION' -Message 'Starting comprehensive bloatware detection' -Data @{
            Categories = $Categories -join ', '
            UseCache   = $UseCache
            Context    = $Context
        }
    }
    catch {
        Write-Verbose "BLOATWARE-DETECTION: Logging initialization failed - $_"
        # LoggingManager not available, continue
    }

    try {
        # Get bloatware patterns from configuration
        $bloatwareList = $null
        try {
            # Handle multiple categories by combining results
            if ($Categories.Count -eq 1 -and $Categories[0] -eq 'all') {
                $bloatwareConfig = Get-BloatwareConfiguration
                $bloatwareList = if ($bloatwareConfig.all) { $bloatwareConfig.all } else { @() }
            }
            else {
                $bloatwareList = @()
                $bloatwareConfig = Get-BloatwareConfiguration
                foreach ($category in $Categories) {
                    if ($bloatwareConfig.$category) {
                        $bloatwareList += $bloatwareConfig.$category
                    }
                }
            }
        }
        catch {
            Write-Warning "Failed to get bloatware configuration: $_"
            return @()
        }

        if ($null -eq $bloatwareList -or $bloatwareList.Count -eq 0) {
            Write-Warning "No bloatware patterns found in configuration"
            return @()
        }

        Write-Information "   Loaded $($bloatwareList.Count) bloatware patterns from $($Categories.Count) categories" -InformationAction Continue

        # Initialize results collection with explicit capacity for better memory management
        $allBloatware = [List[PSCustomObject]]::new(200)  # Pre-allocate capacity to reduce reallocations

        # Variables for cleanup tracking
        $installedPrograms = $null

        # Collect installed programs directly from registry (SystemAnalysis only provides summary metrics)
        Write-Information "   Collecting installed programs from registry..." -InformationAction Continue
        try {
            $programs = @()
            $registryPaths = @(
                'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
                'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
                'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
            )

            foreach ($path in $registryPaths) {
                try {
                    $programs += Get-ItemProperty $path -ErrorAction SilentlyContinue |
                    Where-Object { $_.DisplayName -and $_.DisplayName.Trim() -ne '' } |
                    ForEach-Object {
                        [PSCustomObject]@{
                            Name            = $_.DisplayName
                            DisplayName     = $_.DisplayName
                            DisplayVersion  = $_.DisplayVersion
                            Publisher       = $_.Publisher
                            InstallDate     = $_.InstallDate
                            InstallLocation = $_.InstallLocation
                            EstimatedSize   = $_.EstimatedSize
                            UninstallString = $_.UninstallString
                            PSPath          = $_.PSPath
                            Source          = 'Registry'
                        }
                    }
                }
                catch {
                    Write-Verbose "Failed to read registry path ${path}: $($_.Exception.Message)"
                }
            }

            $installedPrograms = $programs
            Write-Information "   Found $($installedPrograms.Count) installed programs" -InformationAction Continue
        }
        catch {
            Write-Warning "Failed to collect installed programs: $($_.Exception.Message)"
            $installedPrograms = @()
        }

        # Collect AppX packages for Store apps
        try {
            if (Get-Command Get-AppxPackage -ErrorAction SilentlyContinue) {
                Write-Information "   Collecting AppX packages..." -InformationAction Continue
                $appxPackages = Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue
                if ($appxPackages) {
                    $appxItems = $appxPackages | ForEach-Object {
                        [PSCustomObject]@{
                            Name             = $_.Name
                            DisplayName      = $_.Name
                            Version          = $_.Version
                            Publisher        = $_.Publisher
                            InstallDate      = $null
                            InstallLocation  = $_.InstallLocation
                            PackageFullName  = $_.PackageFullName
                            PackageFamilyName= $_.PackageFamilyName
                            Source           = 'AppX'
                        }
                    }
                    $installedPrograms += $appxItems
                    Write-Information "   Found $($appxItems.Count) AppX packages" -InformationAction Continue
                }
            }
        }
        catch {
            Write-Verbose "Failed to collect AppX packages: $($_.Exception.Message)"
        }

        if ($null -eq $installedPrograms -or $installedPrograms.Count -eq 0) {
            Write-Warning "No installed programs found in registry"
            # Continue anyway - AppX, Winget, Chocolatey scans can still work
        }

        # Scan AppX packages
        Write-Information "   Scanning AppX packages..." -InformationAction Continue
        $appxBloatware = Get-AppXBloatware -BloatwarePatterns $bloatwareList -InstalledPrograms $installedPrograms -Context $Context
        if ($appxBloatware -and $appxBloatware.Count -gt 0) {
            # Ensure we have an array and add each item individually
            $appxArray = @($appxBloatware)
            foreach ($item in $appxArray) {
                if ($null -ne $item) { $allBloatware.Add($item) }
            }
        }

        # Scan Winget packages
        Write-Information "   Scanning Winget packages..." -InformationAction Continue
        $wingetBloatware = Get-WingetBloatware -BloatwarePatterns $bloatwareList -InstalledPrograms $installedPrograms -Context $Context
        if ($wingetBloatware -and $wingetBloatware.Count -gt 0) {
            $wingetArray = @($wingetBloatware)
            foreach ($item in $wingetArray) {
                if ($null -ne $item) { $allBloatware.Add($item) }
            }
        }

        # Scan Chocolatey packages
        Write-Information "   Scanning Chocolatey packages..." -InformationAction Continue
        $chocoBloatware = Get-ChocolateyBloatware -BloatwarePatterns $bloatwareList -InstalledPrograms $installedPrograms -Context $Context
        if ($chocoBloatware -and $chocoBloatware.Count -gt 0) {
            $chocoArray = @($chocoBloatware)
            foreach ($item in $chocoArray) {
                if ($null -ne $item) { $allBloatware.Add($item) }
            }
        }

        # Scan Registry entries
        Write-Information "   Scanning Registry entries..." -InformationAction Continue
        $registryBloatware = Get-RegistryBloatware -BloatwarePatterns $bloatwareList -InstalledPrograms $installedPrograms -Context $Context
        if ($registryBloatware -and $registryBloatware.Count -gt 0) {
            $registryArray = @($registryBloatware)
            foreach ($item in $registryArray) {
                if ($null -ne $item) { $allBloatware.Add($item) }
            }
        }

        # Remove duplicates and sort results - ensure we always return an array
        $uniqueBloatware = @()
        if ($allBloatware.Count -gt 0) {
            $uniqueBloatware = @($allBloatware |
                Sort-Object Name, Source |
                Group-Object Name |
                ForEach-Object { $_.Group | Select-Object -First 1 })
        }

        $duration = ((Get-Date) - $startTime).TotalSeconds
        $sourceStats = if ($allBloatware.Count -gt 0) {
            $allBloatware | Group-Object Source | ForEach-Object { "$($_.Name): $($_.Count)" }
        }
        else {
            @("No sources")
        }

        Write-Information "   Found $($uniqueBloatware.Count) unique bloatware items in $([math]::Round($duration, 2))s" -InformationAction Continue
        Write-Information "   Sources: $($sourceStats -join ', ')" -InformationAction Continue

        # Create final result array to return
        $resultArray = [Array]$uniqueBloatware

        # Explicit memory cleanup before return
        Write-Verbose "Performing memory cleanup for bloatware detection"
        $allBloatware.Clear()
        $allBloatware = $null

        # Clear large variables
        $installedPrograms = $null

        # Force garbage collection if collection was large
        if ($resultArray.Count -gt 50) {
            Write-Verbose "Large result set detected, triggering garbage collection"
            [System.GC]::Collect()
            [System.GC]::WaitForPendingFinalizers()
        }

        # Complete performance tracking and log success
        try {
            if ($perfContext) {
                Complete-PerformanceTracking -PerformanceContext $perfContext -Success $true
            }

            Write-LogEntry -Level 'INFO' -Component 'BLOATWARE-DETECTION' -Message 'Bloatware detection completed successfully' -Data @{
                BloatwareItemsFound = $resultArray.Count
                ExecutionTime       = [math]::Round($duration, 2)
                Sources             = $sourceStats -join ', '
                Categories          = $Categories -join ', '
            }
        }
        catch {
            Write-Verbose "BLOATWARE-DETECTION: Logging completion failed - $_"
            # LoggingManager not available, continue
        }

        return $resultArray
    }
    catch {
        # Complete performance tracking with failure
        try {
            if ($perfContext) {
                Complete-PerformanceTracking -PerformanceContext $perfContext -Success $false
            }

            Write-LogEntry -Level 'ERROR' -Component 'BLOATWARE-DETECTION' -Message 'Bloatware detection failed' -Data @{
                Error         = $_.Exception.Message
                ExecutionTime = [math]::Round((Get-Date - $startTime).TotalSeconds, 2)
                Categories    = $Categories -join ', '
            }
        }
        catch {
            Write-Verbose "BLOATWARE-DETECTION: Error logging failed - $_"
            # LoggingManager not available, continue
        }

        Write-Error "Failed to detect bloatware: $_"
        Write-Warning "Returning empty array due to error"

        # Cleanup on error
        if ($null -ne $allBloatware) {
            $allBloatware.Clear()
            $allBloatware = $null
        }
        $installedPrograms = $null

        return @()
    }
    finally {
        # Final cleanup in case variables weren't cleared
        if ($null -ne $allBloatware) {
            $allBloatware.Clear()
        }
        Write-Verbose "Memory cleanup completed for bloatware detection"
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
    $stats = Get-BloatwareStatistic -BloatwareList $detectedBloatware
#>
function Get-BloatwareStatistic {
    [CmdletBinding()]
    [OutputType([hashtable])]`nparam(
        [Parameter(Mandatory)]
        [Array]$BloatwareList
    )

    if ($null -eq $BloatwareList -or $BloatwareList.Count -eq 0) {
        return @{
            TotalItems        = 0
            BySource          = @{}
            ByCategory        = @{}
            TotalSizeEstimate = "Unknown"
        }
    }

    $bySource = @{}
    $byCategory = @{}

    try {
        $sourceGroups = $BloatwareList | Where-Object { $null -ne $_ } | Group-Object Source
        foreach ($group in $sourceGroups) {
            if ($null -ne $group -and $null -ne $group.Name) {
                $bySource[$group.Name] = $group.Count
            }
        }

        $categoryGroups = $BloatwareList | Where-Object { $null -ne $_ } | Group-Object MatchedPattern
        foreach ($group in $categoryGroups) {
            if ($null -ne $group -and $null -ne $group.Name) {
                $byCategory[$group.Name] = $group.Count
            }
        }

        $mostCommonSource = ($BloatwareList | Where-Object { $null -ne $_ } | Group-Object Source | Sort-Object Count -Descending | Select-Object -First 1)?.Name
        $mostCommonPattern = ($BloatwareList | Where-Object { $null -ne $_ } | Group-Object MatchedPattern | Sort-Object Count -Descending | Select-Object -First 1)?.Name
    }
    catch {
        Write-Warning "Error calculating bloatware statistics: $_"
    }

    return @{
        TotalItems        = $BloatwareList.Count
        BySource          = $bySource
        ByCategory        = $byCategory
        TotalSizeEstimate = "Calculation not available"
        MostCommonSource  = $mostCommonSource
        MostCommonPattern = $mostCommonPattern
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
    [OutputType([hashtable])]`nparam(
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
            # Skip null apps to prevent null reference exceptions
            if ($null -eq $app) { continue }

            foreach ($pattern in $BloatwarePatterns) {
                $matched = $false
                $matchType = ""

                # Exact match (highest priority)
                if ($app.Name -eq $pattern -or $app.DisplayName -eq $pattern) {
                    $matched = $true
                    $matchType = "Exact"
                }
                # Publisher + partial name match
                elseif ($app.Publisher -and $pattern -match '(\w+)\.(.+)') {
                    $publisherPart = $matches[1]
                    $namePart = $matches[2]
                    if ($app.Publisher -like "*$publisherPart*" -and ($app.Name -like "*$namePart*" -or $app.DisplayName -like "*$namePart*")) {
                        $matched = $true
                        $matchType = "Publisher+Name"
                    }
                }
                # Wildcard match
                elseif ($app.Name -like "*$pattern*" -or $app.DisplayName -like "*$pattern*") {
                    $matched = $true
                    $matchType = "Wildcard"
                }
                # Publisher contains pattern
                elseif ($app.Publisher -and $app.Publisher -like "*$pattern*") {
                    $matched = $true
                    $matchType = "Publisher"
                }

                if ($matched) {
                    $detectedItem = [PSCustomObject]@{
                        Name           = $app.Name
                        DisplayName    = $app.DisplayName
                        Version        = $app.Version
                        Publisher      = $app.Publisher
                        InstallDate    = $app.InstallDate
                        Source         = 'AppX'
                        MatchedPattern = $pattern
                        MatchType      = $matchType
                        Context        = $Context
                        RemovalMethod  = 'Remove-AppxPackage'
                        Confidence     = switch ($matchType) {
                            "Exact" { 100 }
                            "Publisher+Name" { 95 }
                            "Wildcard" { 80 }
                            "Publisher" { 70 }
                            default { 50 }
                        }
                    }

                    # Log detailed detection information
                    Write-DetectionLog -Operation 'Detect' -Target $app.DisplayName -Component 'BLOATWARE-APPX' -AdditionalInfo @{
                        PackageName    = $app.Name
                        Version        = $app.Version
                        Publisher      = $app.Publisher
                        InstallDate    = $app.InstallDate
                        MatchedPattern = $pattern
                        MatchType      = $matchType
                        Confidence     = $detectedItem.Confidence
                        RemovalMethod  = 'Remove-AppxPackage'
                        MatchReason    = switch ($matchType) {
                            "Exact" { "Exact match with pattern '$pattern'" }
                            "Publisher+Name" { "Publisher and name match pattern '$pattern'" }
                            "Wildcard" { "Wildcard match with pattern '$pattern'" }
                            "Publisher" { "Publisher contains pattern '$pattern'" }
                            default { "Unknown match type" }
                        }
                    }

                    $found += $detectedItem
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
    [OutputType([hashtable])]`nparam(
        [Parameter()]
        [string[]]$BloatwarePatterns,

        [Parameter()]
        [array]$InstalledPrograms,

        [Parameter()]
        [string]$Context = "Winget Scan"
    )

    try {
        if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
            Write-Verbose "Winget not available for detection"
            return @()
        }

        $wingetApps = @()

        # Prefer JSON output when available
        try {
            $jsonOutput = & winget list --output json --accept-source-agreements 2>$null
            if ($LASTEXITCODE -eq 0 -and $jsonOutput) {
                $parsed = $jsonOutput | ConvertFrom-Json -ErrorAction Stop
                $data = if ($parsed.Data) { $parsed.Data } elseif ($parsed -is [array]) { $parsed } else { @() }
                $wingetApps = $data | ForEach-Object {
                    [PSCustomObject]@{
                        Name       = $_.Id
                        DisplayName= $_.Name
                        Version    = $_.Version
                        Publisher  = $_.Publisher
                        Source     = 'Winget'
                        WingetId   = $_.Id
                    }
                }
            }
        }
        catch {
            Write-Verbose "Winget JSON list failed, falling back to text parsing: $($_.Exception.Message)"
        }

        if (-not $wingetApps -or $wingetApps.Count -eq 0) {
            # Fallback text parsing
            $listOutput = & winget list --accept-source-agreements 2>$null
            if ($LASTEXITCODE -eq 0 -and $listOutput) {
                $lines = $listOutput | Select-Object -Skip 2
                foreach ($line in $lines) {
                    if ([string]::IsNullOrWhiteSpace($line)) { continue }
                    $parts = $line -split '\s{2,}'
                    if ($parts.Count -ge 2) {
                        $wingetApps += [PSCustomObject]@{
                            Name        = $parts[0]
                            DisplayName = $parts[0]
                            Version     = if ($parts.Count -ge 3) { $parts[2] } else { $null }
                            Publisher   = $null
                            Source      = 'Winget'
                            WingetId    = $null
                        }
                    }
                }
            }
        }

        $found = @()
        foreach ($app in $wingetApps) {
            # Skip null apps to prevent null reference exceptions
            if ($null -eq $app) { continue }

            foreach ($pattern in $BloatwarePatterns) {
                $matched = $false
                $matchType = ""

                # Exact match (highest priority)
                if ($app.Name -eq $pattern -or $app.DisplayName -eq $pattern -or $app.WingetId -eq $pattern) {
                    $matched = $true
                    $matchType = "Exact"
                }
                # Publisher + partial name match
                elseif ($app.Publisher -and $pattern -match '(\w+)\.(.+)') {
                    $publisherPart = $matches[1]
                    $namePart = $matches[2]
                    if ($app.Publisher -like "*$publisherPart*" -and ($app.Name -like "*$namePart*" -or $app.DisplayName -like "*$namePart*")) {
                        $matched = $true
                        $matchType = "Publisher+Name"
                    }
                }
                # Wildcard match
                elseif ($app.Name -like "*$pattern*" -or $app.DisplayName -like "*$pattern*") {
                    $matched = $true
                    $matchType = "Wildcard"
                }
                # Publisher contains pattern
                elseif ($app.Publisher -and $app.Publisher -like "*$pattern*") {
                    $matched = $true
                    $matchType = "Publisher"
                }

                if ($matched) {
                    $detectedItem = [PSCustomObject]@{
                        Name           = if ($app.WingetId) { $app.WingetId } else { $app.Name }
                        DisplayName    = $app.DisplayName
                        Version        = $app.Version
                        Publisher      = $app.Publisher
                        InstallDate    = $app.InstallDate
                        Source         = 'Winget'
                        MatchedPattern = $pattern
                        MatchType      = $matchType
                        Context        = $Context
                        RemovalMethod  = 'winget uninstall'
                        WingetId       = $app.WingetId
                        Confidence     = switch ($matchType) {
                            "Exact" { 100 }
                            "Publisher+Name" { 95 }
                            "Wildcard" { 80 }
                            "Publisher" { 70 }
                            default { 50 }
                        }
                    }

                    # Log detailed detection information
                    Write-DetectionLog -Operation 'Detect' -Target $app.DisplayName -Component 'BLOATWARE-WINGET' -AdditionalInfo @{
                        PackageName    = $app.Name
                        Version        = $app.Version
                        Publisher      = $app.Publisher
                        InstallDate    = $app.InstallDate
                        MatchedPattern = $pattern
                        MatchType      = $matchType
                        Confidence     = $detectedItem.Confidence
                        RemovalMethod  = 'winget uninstall'
                        MatchReason    = switch ($matchType) {
                            "Exact" { "Exact match with pattern '$pattern'" }
                            "Publisher+Name" { "Publisher and name match pattern '$pattern'" }
                            "Wildcard" { "Wildcard match with pattern '$pattern'" }
                            "Publisher" { "Publisher contains pattern '$pattern'" }
                            default { "Unknown match type" }
                        }
                    }

                    $found += $detectedItem
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
    [OutputType([hashtable])]`nparam(
        [Parameter()]
        [string[]]$BloatwarePatterns,

        [Parameter()]
        [array]$InstalledPrograms,

        [Parameter()]
        [string]$Context = "Chocolatey Scan"
    )

    try {
        if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
            Write-Verbose "Chocolatey not available for detection"
            return @()
        }

        $chocoApps = @()
        try {
            $chocoList = & choco list --local-only --limit-output 2>$null
            if ($LASTEXITCODE -eq 0 -and $chocoList) {
                foreach ($line in $chocoList) {
                    if ([string]::IsNullOrWhiteSpace($line)) { continue }
                    $parts = $line -split '\|', 2
                    $chocoApps += [PSCustomObject]@{
                        Name        = $parts[0]
                        DisplayName = $parts[0]
                        Version     = if ($parts.Count -gt 1) { $parts[1] } else { $null }
                        Publisher   = $null
                        InstallDate = $null
                        Source      = 'Chocolatey'
                        ChocolateyId= $parts[0]
                    }
                }
            }
        }
        catch {
            Write-Verbose "Chocolatey list failed: $($_.Exception.Message)"
        }

        $found = @()
        foreach ($app in $chocoApps) {
            # Skip null apps to prevent null reference exceptions
            if ($null -eq $app) { continue }

            foreach ($pattern in $BloatwarePatterns) {
                if ($app.Name -like "*$pattern*" -or $app.DisplayName -like "*$pattern*") {
                    $detectedItem = [PSCustomObject]@{
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

                    # Log detailed detection information
                    Write-DetectionLog -Operation 'Detect' -Target $app.DisplayName -Component 'BLOATWARE-CHOCO' -AdditionalInfo @{
                        PackageName    = $app.Name
                        Version        = $app.Version
                        Publisher      = $app.Publisher
                        InstallDate    = $app.InstallDate
                        MatchedPattern = $pattern
                        MatchType      = 'Wildcard'
                        RemovalMethod  = 'choco uninstall'
                        MatchReason    = "Name or DisplayName matches pattern '$pattern'"
                    }

                    $found += $detectedItem
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
    [OutputType([hashtable])]`nparam(
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
            # Skip null apps to prevent null reference exceptions
            if ($null -eq $app) { continue }

            foreach ($pattern in $BloatwarePatterns) {
                if ($app.Name -like "*$pattern*" -or $app.DisplayName -like "*$pattern*") {
                    $detectedItem = [PSCustomObject]@{
                        Name            = $app.Name
                        DisplayName     = $app.DisplayName
                        Version         = $app.Version
                        Publisher       = $app.Publisher
                        InstallDate     = $app.InstallDate
                        Source          = 'Registry'
                        MatchedPattern  = $pattern
                        Context         = $Context
                        RemovalMethod   = 'Registry-based uninstall'
                        UninstallString = $app.UninstallString
                    }

                    # Log detailed detection information
                    Write-DetectionLog -Operation 'Detect' -Target $app.DisplayName -Component 'BLOATWARE-REGISTRY' -AdditionalInfo @{
                        PackageName     = $app.Name
                        Version         = $app.Version
                        Publisher       = $app.Publisher
                        InstallDate     = $app.InstallDate
                        MatchedPattern  = $pattern
                        MatchType       = 'Wildcard'
                        RemovalMethod   = 'Registry-based uninstall'
                        UninstallString = $app.UninstallString
                        MatchReason     = "Name or DisplayName matches pattern '$pattern'"
                    }

                    $found += $detectedItem
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
    [OutputType([hashtable])]`nparam(
        [Parameter(Mandatory)]
        [Array]$DetectedItems
    )

    $validationResults = @{
        TotalItems        = $DetectedItems.Count
        ValidItems        = 0
        InvalidItems      = 0
        MissingProperties = @()
        Sources           = @()
    }

    $requiredProperties = @('Name', 'Source', 'MatchedPattern')

    foreach ($item in $DetectedItems) {
        # Skip null items to prevent null reference exceptions
        if ($null -eq $item) {
            $validationResults.InvalidItems++
            continue
        }

        $isValid = $true

        foreach ($property in $requiredProperties) {
            if (-not $item.$property) {
                $validationResults.MissingProperties += "$($item.Name ?? 'Unknown') missing $property"
                $isValid = $false
            }
        }

        if ($isValid) {
            $validationResults.ValidItems++
        }
        else {
            $validationResults.InvalidItems++
        }

        if ($item.Source -notin $validationResults.Sources) {
            $validationResults.Sources += $item.Source
        }
    }

    return $validationResults
}

#endregion

<#
.SYNOPSIS
    v3.0 Wrapper function for Type2 modules to get bloatware analysis and save to temp_files/data

.DESCRIPTION
    Standardized analysis function that Type2 modules call to get bloatware detection results.
    Automatically saves results to temp_files/data/bloatware-results.json using global paths.

.PARAMETER Config
    Configuration hashtable from orchestrator

.EXAMPLE
    $results = Get-BloatwareAnalysis -Config $Config
#>
function Get-BloatwareAnalysis {
    [CmdletBinding()]
    [OutputType([hashtable])]`nparam(
        [Parameter(Mandatory)]
        [hashtable]$Config
    )

    Write-LogEntry -Level 'INFO' -Component 'BLOATWARE-DETECTION' -Message 'Starting bloatware analysis for Type2 module'

    try {
        # Perform the bloatware detection
        $detectionResults = Find-InstalledBloatware -Categories @('all')

        # FIX #5: Use standardized Get-AuditResultsPath function for consistent path
        if (Get-Command 'Get-AuditResultsPath' -ErrorAction SilentlyContinue) {
            $dataPath = Get-AuditResultsPath -ModuleName 'BloatwareDetection'
        }
        else {
            # Fallback to direct path construction if function not available
            $dataPath = Join-Path (Get-MaintenancePath 'TempRoot') "data\bloatware-results.json"
        }

        # Save results to standardized temp_files/data/ location
        if ($dataPath) {
            # Ensure directory exists
            $dataDir = Split-Path -Parent $dataPath
            if (-not (Test-Path $dataDir)) {
                New-Item -Path $dataDir -ItemType Directory -Force | Out-Null
            }

            # Save results as JSON with standardized format
            $detectionResults | ConvertTo-Json -Depth 20 -WarningAction SilentlyContinue | Set-Content $dataPath -Encoding UTF8
            Write-LogEntry -Level 'INFO' -Component 'BLOATWARE-DETECTION' -Message "Saved $($detectionResults.Count) detection results to standardized path: $dataPath"
        }
        else {
            Write-Warning "Could not determine audit results path - results not saved to file"
        }

        return $detectionResults
    }
    catch {
        Write-LogEntry -Level 'ERROR' -Component 'BLOATWARE-DETECTION' -Message "Bloatware analysis failed: $($_.Exception.Message)"
        return @()
    }
}

# Export module functions
Export-ModuleMember -Function @(
    'Get-BloatwareAnalysis',  #  v3.0 PRIMARY function
    'Get-BloatwareStatistic',
    'Test-BloatwareDetection',
    'Find-InstalledBloatware'  # Public function for Type2 modules
)



