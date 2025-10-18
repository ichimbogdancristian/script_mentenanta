#Requires -Version 7.0
# Module Dependencies:
#   - ConfigManager.psm1 (for essential apps configuration)
#   - LoggingManager.psm1 (for structured logging)

<#
.SYNOPSIS
    Essential Apps Audit Module - Type 1 (Inventory/Reporting)

.DESCRIPTION
    Audits system for missing essential applications and analyzes installation opportunities.
    Detects currently installed software and identifies gaps in essential productivity tools.

.NOTES
    Module Type: Type 1 (Inventory/Reporting)
    Dependencies: ConfigManager.psm1, LoggingManager.psm1
    Author: Windows Maintenance Automation Project
    Version: 1.0.0
#>

using namespace System.Collections.Generic

# Import required modules
$ModuleRoot = Split-Path -Parent $PSScriptRoot
# v3.0 Type 1 module - imported by Type 2 modules
# Import CoreInfrastructure for configuration and logging
$ModuleRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$CoreInfraPath = Join-Path $ModuleRoot 'core\CoreInfrastructure.psm1'
if (Test-Path $CoreInfraPath) {
    Import-Module $CoreInfraPath -Force
}

# Fallback functions if CoreInfrastructure functions not available in this scope
if (-not (Get-Command 'Write-LogEntry' -ErrorAction SilentlyContinue)) {
    function Write-LogEntry {
        param($Level, $Component, $Message, $Data)
        Write-Information "[$Level] [$Component] $Message" -InformationAction Continue
    }
}

if (-not (Get-Command 'Get-SessionPath' -ErrorAction SilentlyContinue)) {
    function Get-SessionPath {
        param($Category, $SubCategory, $FileName)
        
        # Try to construct proper path using environment variables set by orchestrator
        $tempRoot = if ($env:MAINTENANCE_TEMP_ROOT) { $env:MAINTENANCE_TEMP_ROOT } else { Join-Path $env:TEMP 'maintenance' }
        
        if ($Category -and (Test-Path $tempRoot)) {
            $categoryPath = Join-Path $tempRoot $Category
            if (-not (Test-Path $categoryPath)) {
                try { New-Item -Path $categoryPath -ItemType Directory -Force | Out-Null } catch {}
            }
            
            if ($SubCategory) {
                $categoryPath = Join-Path $categoryPath $SubCategory
                if (-not (Test-Path $categoryPath)) {
                    try { New-Item -Path $categoryPath -ItemType Directory -Force | Out-Null } catch {}
                }
            }
            
            return Join-Path $categoryPath $FileName
        }
        else {
            Write-Warning "Session path unavailable - using current directory fallback"
            return $FileName
        }
    }
}

if (-not (Get-Command 'Get-EssentialAppsConfiguration' -ErrorAction SilentlyContinue)) {
    function Get-EssentialAppsConfiguration {
        Write-Warning "CoreInfrastructure not available - using fallback configuration"
        return @{}
    }
}

if (-not (Get-Command 'Get-UnifiedEssentialAppsList' -ErrorAction SilentlyContinue)) {
    function Get-UnifiedEssentialAppsList {
        Write-Warning "CoreInfrastructure not available - using fallback essential apps list"
        
        # Fallback essential apps list to prevent divide by zero error
        return @(
            @{ name = "Microsoft Visual Studio Code"; category = "Editor"; description = "Code editor"; winget = "Microsoft.VisualStudioCode" },
            @{ name = "Google Chrome"; category = "Browsers"; description = "Web browser"; winget = "Google.Chrome" },
            @{ name = "Mozilla Firefox"; category = "Browsers"; description = "Web browser"; winget = "Mozilla.Firefox" },
            @{ name = "7-Zip"; category = "System"; description = "File archiver"; winget = "7zip.7zip" },
            @{ name = "VLC Media Player"; category = "Media"; description = "Media player"; winget = "VideoLAN.VLC" }
        )
    }
}

#region Public Functions

<#
.SYNOPSIS
    Audits system for missing essential applications

.DESCRIPTION
    Analyzes currently installed software and identifies missing essential applications
    based on the configured essential apps list. Provides recommendations for installations.

.PARAMETER Categories
    Specific app categories to audit (System, Runtime, Office, Document, Editor, Browsers, Media)

.PARAMETER IncludeInstalled
    Include information about already installed essential apps

.PARAMETER UseCache
    Use cached results if available and not expired

.EXAMPLE
    $audit = Get-EssentialAppsAudit -Categories @('System', 'Office')

.EXAMPLE
    $audit = Get-EssentialAppsAudit -IncludeInstalled
#>
function Get-EssentialAppsAudit {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [ValidateSet('System', 'Runtime', 'Office', 'Document', 'Editor', 'Browsers', 'Media', 'Development', 'all')]
        [string[]]$Categories = @('all'),

        [Parameter()]
        [switch]$IncludeInstalled,

        [Parameter()]
        [switch]$UseCache
    )

    Write-Information "🔍 Starting essential applications audit..." -InformationAction Continue
    
    # Start performance tracking
    $perfContext = $null
    try {
        $perfContext = Start-PerformanceTracking -OperationName 'EssentialAppsAudit' -Component 'ESSENTIAL-APPS-AUDIT'
        Write-LogEntry -Level 'INFO' -Component 'ESSENTIAL-APPS-AUDIT' -Message 'Starting essential apps audit' -Data @{
            Categories       = $Categories
            IncludeInstalled = $IncludeInstalled
        }
    }
    catch {
        # LoggingManager not available, continue with standard output
        Write-Information "Essential apps audit started" -InformationAction Continue
    }

    try {
        # Check cache first if requested
        if ($UseCache) {
            $cacheFile = Get-SessionPath -Category 'data' -FileName 'essential-apps-audit.json'
            if ($cacheFile -and (Test-Path $cacheFile)) {
                $cacheAge = (Get-Date) - (Get-Item $cacheFile).LastWriteTime
                if ($cacheAge.TotalMinutes -le 10) {
                    Write-Information "Using cached essential apps audit data" -InformationAction Continue
                    $cachedResult = Get-Content $cacheFile | ConvertFrom-Json
                    return $cachedResult
                }
            }
        }

        # Get essential apps configuration
        $essentialAppsList = Get-UnifiedEssentialAppsList

        # Filter by categories if not 'all'
        if ($Categories -notcontains 'all') {
            $essentialAppsList = $essentialAppsList | Where-Object { $_.category -in $Categories }
        }

        Write-Information "Scanning for installed applications..." -InformationAction Continue

        # Get installed applications from multiple sources
        $installedApps = Get-InstalledApplications

        # Initialize audit results
        $auditResults = @{
            AuditTimestamp      = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            Categories          = $Categories
            TotalEssentialApps  = $essentialAppsList.Count
            InstalledApps       = @()
            MissingApps         = @()
            RecommendedInstalls = @()
            Summary             = @{}
        }

        Write-Information "Analyzing $($essentialAppsList.Count) essential applications..." -InformationAction Continue

        foreach ($app in $essentialAppsList) {
            $installationStatus = Test-ApplicationInstallation -AppDefinition $app -InstalledApps $installedApps
            
            if ($installationStatus.IsInstalled) {
                if ($IncludeInstalled) {
                    $auditResults.InstalledApps += [PSCustomObject]@{
                        Name               = $app.name
                        Category           = $app.category
                        Description        = $app.description
                        DetectedVersion    = $installationStatus.Version
                        InstallationSource = $installationStatus.Source
                        InstallPath        = $installationStatus.InstallPath
                    }
                }
            }
            else {
                $missingApp = [PSCustomObject]@{
                    Name              = $app.name
                    Category          = $app.category
                    Description       = $app.description
                    WingetId          = $app.winget
                    ChocoId           = $app.choco
                    Priority          = Get-AppInstallPriority -AppDefinition $app
                    RecommendedMethod = Get-RecommendedInstallMethod -AppDefinition $app
                }
                $auditResults.MissingApps += $missingApp
                
                # Add to recommended installs if high priority
                if ($missingApp.Priority -eq 'High') {
                    $auditResults.RecommendedInstalls += $missingApp
                }
            }
        }

        # Generate summary statistics
        $completionPercentage = if ($essentialAppsList.Count -gt 0) { 
            [math]::Round(($auditResults.InstalledApps.Count / $essentialAppsList.Count) * 100, 2) 
        }
        else { 
            0 
        }
        
        $auditResults.Summary = @{
            TotalScanned         = $essentialAppsList.Count
            InstalledCount       = $auditResults.InstalledApps.Count
            MissingCount         = $auditResults.MissingApps.Count
            RecommendedCount     = $auditResults.RecommendedInstalls.Count
            CompletionPercentage = $completionPercentage
            CategoryBreakdown    = $auditResults.MissingApps | Group-Object Category | ForEach-Object {
                @{ Category = $_.Name; Count = $_.Count }
            }
        }

        Write-Information "✓ Essential apps audit completed: $($auditResults.Summary.InstalledCount) installed, $($auditResults.Summary.MissingCount) missing" -InformationAction Continue

        # Save results to session data using v3.0 global paths
        try {
            # Use global paths if available, fallback to session path
            if ($Global:ProjectPaths -and $Global:ProjectPaths.TempFiles) {
                $outputPath = Join-Path $Global:ProjectPaths.TempFiles "data\essential-apps-results.json"
                # Ensure directory exists
                $dataDir = Split-Path -Parent $outputPath
                if (-not (Test-Path $dataDir)) {
                    New-Item -Path $dataDir -ItemType Directory -Force | Out-Null
                }
            }
            else {
                $outputPath = Get-SessionPath -Category 'data' -FileName 'essential-apps-results.json'
            }
            
            $auditResults | ConvertTo-Json -Depth 10 | Out-File -FilePath $outputPath -Encoding UTF8
            Write-Information "Audit results saved to: $outputPath" -InformationAction Continue
        }
        catch {
            Write-Warning "Failed to save audit results: $($_.Exception.Message)"
        }

        # Complete performance tracking
        try {
            Complete-PerformanceTracking -Context $perfContext -Status 'Success' -ResultCount $auditResults.Summary.TotalScanned
        }
        catch {}

        return [PSCustomObject]$auditResults

    }
    catch {
        $errorMsg = "Essential apps audit failed: $($_.Exception.Message)"
        Write-Error $errorMsg
        
        try {
            Write-LogEntry -Level 'ERROR' -Component 'ESSENTIAL-APPS-AUDIT' -Message $errorMsg -Data @{ Error = $_.Exception }
            Complete-PerformanceTracking -Context $perfContext -Status 'Failed' -ErrorMessage $errorMsg
        }
        catch {}
        
        throw
    }
}

#endregion

#region Private Helper Functions

<#
.SYNOPSIS
    Gets installed applications from multiple sources
#>
function Get-InstalledApplications {
    [CmdletBinding()]
    [OutputType([array])]
    param()

    $installedApps = @()

    try {
        # Get from Programs and Features (Registry)
        $registryPaths = @(
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
        )

        foreach ($path in $registryPaths) {
            $apps = Get-ItemProperty $path -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -and $_.DisplayName.Trim() -ne '' } |
            Select-Object DisplayName, DisplayVersion, InstallLocation, Publisher
            $installedApps += $apps
        }

        # Get from Winget (if available)
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            try {
                $wingetList = winget list --accept-source-agreements 2>$null | 
                ConvertFrom-String -PropertyNames Name, Id, Version, Source -Delimiter "`t"
                $installedApps += $wingetList | Where-Object { $_.Name -and $_.Name.Trim() -ne '' }
            }
            catch {
                Write-Verbose "Failed to get Winget applications list: $($_.Exception.Message)"
            }
        }

        # Get from AppX packages
        try {
            $appxPackages = Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue |
            Select-Object Name, Version, InstallLocation, Publisher
            $installedApps += $appxPackages
        }
        catch {
            Write-Verbose "Failed to get AppX packages: $($_.Exception.Message)"
        }

    }
    catch {
        Write-Warning "Error getting installed applications: $($_.Exception.Message)"
    }

    return $installedApps
}

<#
.SYNOPSIS
    Tests if a specific application is installed
#>
function Test-ApplicationInstallation {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$AppDefinition,

        [Parameter(Mandatory)]
        [array]$InstalledApps
    )

    $result = [PSCustomObject]@{
        IsInstalled = $false
        Version     = $null
        Source      = $null
        InstallPath = $null
    }

    # Search patterns for the application
    $searchTerms = @($AppDefinition.name)
    if ($AppDefinition.winget) { $searchTerms += $AppDefinition.winget.Split('.') }

    foreach ($term in $searchTerms) {
        $matchedApp = $InstalledApps | Where-Object {
            ($_.DisplayName -like "*$term*") -or 
            ($_.Name -like "*$term*") -or
            ($_.Id -like "*$term*")
        } | Select-Object -First 1

        if ($matchedApp) {
            $result.IsInstalled = $true
            $result.Version = $matchedApp.DisplayVersion ?? $matchedApp.Version
            $result.InstallPath = $matchedApp.InstallLocation
            $result.Source = if ($matchedApp.Source) { $matchedApp.Source } else { 'Registry' }
            break
        }
    }

    return $result
}

<#
.SYNOPSIS
    Determines installation priority for an application
#>
function Get-AppInstallPriority {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$AppDefinition
    )

    # High priority categories
    $highPriorityCategories = @('System', 'Runtime', 'Security')
    $highPriorityApps = @('PowerShell 7', 'Windows Terminal', 'Java Runtime Environment')

    if ($AppDefinition.category -in $highPriorityCategories -or $AppDefinition.name -in $highPriorityApps) {
        return 'High'
    }

    # Medium priority categories
    $mediumPriorityCategories = @('Office', 'Editor', 'Browsers')
    if ($AppDefinition.category -in $mediumPriorityCategories) {
        return 'Medium'
    }

    return 'Low'
}

<#
.SYNOPSIS
    Gets recommended installation method for an application
#>
function Get-RecommendedInstallMethod {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$AppDefinition
    )

    # Prefer Winget if available
    if ($AppDefinition.winget -and (Get-Command winget -ErrorAction SilentlyContinue)) {
        return 'Winget'
    }

    # Fallback to Chocolatey
    if ($AppDefinition.choco -and (Get-Command choco -ErrorAction SilentlyContinue)) {
        return 'Chocolatey'
    }

    return 'Manual'
}

<#
.SYNOPSIS
    v3.0 Wrapper function for Type2 modules to get essential apps analysis

.DESCRIPTION
    Standardized analysis function that Type2 modules call to get essential apps audit results.
    Automatically saves results to temp_files/data/essential-apps-results.json.

.PARAMETER Config
    Configuration hashtable from orchestrator

.EXAMPLE
    $results = Get-EssentialAppsAnalysis -Config $Config
#>
function Get-EssentialAppsAnalysis {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config
    )
    
    Write-LogEntry -Level 'INFO' -Component 'ESSENTIAL-APPS-AUDIT' -Message 'Starting essential apps analysis for Type2 module'
    
    try {
        # Call the main audit function
        $auditResults = Get-EssentialAppsAudit -Categories @('all')
        
        Write-LogEntry -Level 'INFO' -Component 'ESSENTIAL-APPS-AUDIT' -Message "Essential apps analysis completed: $($auditResults.Summary.MissingCount) missing apps found"
        
        return $auditResults
    }
    catch {
        Write-LogEntry -Level 'ERROR' -Component 'ESSENTIAL-APPS-AUDIT' -Message "Essential apps analysis failed: $($_.Exception.Message)"
        return @()
    }
}

#endregion

# Export public functions
Export-ModuleMember -Function @(
    'Get-EssentialAppsAudit',
    'Get-EssentialAppsAnalysis'  # v3.0 wrapper for Type2 modules
)