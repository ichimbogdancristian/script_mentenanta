#Requires -Version 7.0
# Module Dependencies:
#   - CoreInfrastructure.psm1 (for configuration and logging - loaded globally)
#   - SystemInventory.psm1 (for system analysis)

<#
.SYNOPSIS
    Essential Apps Audit Module - Type 1 (Inventory/Reporting)

.DESCRIPTION
    Audits system for missing essential applications and analyzes installation opportunities.
    Detects currently installed software and identifies gaps in essential productivity tools.

.NOTES
    Module Type: Type 1 (Inventory/Reporting)
    Dependencies: CoreInfrastructure.psm1, SystemInventory.psm1
    Author: Windows Maintenance Automation Project
    Version: 1.0.0
#>

using namespace System.Collections.Generic

# Import required modules
# v3.0 Type 1 module - imported by Type 2 modules
# Note: CoreInfrastructure should be loaded by the Type 2 module before importing this module
# This module provides fallback functions if CoreInfrastructure is not available

# Check if CoreInfrastructure functions are available (loaded by Type2 module)
if (Get-Command 'Get-UnifiedEssentialAppsList' -ErrorAction SilentlyContinue) {
    Write-Verbose "CoreInfrastructure functions detected - using configuration-based essential apps list"
}
else {
    # Non-critical: Function will be available once Type2 module completes global import
    Write-Verbose "CoreInfrastructure global import in progress - Get-UnifiedEssentialAppsList will be available momentarily"
}

# Import shared utilities for fallback functions (only if needed)
$ModuleRoot = Split-Path -Parent $PSScriptRoot
# Legacy import removed - utility functions now available via CoreInfrastructure global import

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
function Get-EssentialAppsAnalysis {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [PSCustomObject]$Config,

        [Parameter()]
        [ValidateSet('System', 'Runtime', 'Office', 'Document', 'Editor', 'Browsers', 'Media', 'Development', 'all')]
        [string[]]$Categories = @('all'),

        [Parameter()]
        [switch]$IncludeInstalled,

        [Parameter()]
        [switch]$UseCache
    )

    Write-Information " Starting essential applications audit..." -InformationAction Continue

    # Start performance tracking
    $perfContext = $null
    try {
        $perfContext = Start-PerformanceTracking -OperationName 'EssentialAppsAudit' -Component 'ESSENTIAL-APPS-AUDIT'
        Write-LogEntry -Level 'INFO' -Component 'ESSENTIAL-APPS-AUDIT' -Message 'Starting essential apps audit' -Data @{
            Categories       = $Categories
            IncludeInstalled = $IncludeInstalled
            Config           = if ($Config) { 'Provided' } else { 'Not provided' }
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

        # Check for Microsoft Office before processing LibreOffice
        $isMicrosoftOfficeInstalled = Test-MicrosoftOfficeInstallation -InstalledApps $installedApps

        foreach ($app in $essentialAppsList) {
            # Skip LibreOffice if Microsoft Office is installed
            if ($app.name -eq 'LibreOffice' -and $isMicrosoftOfficeInstalled) {
                Write-LogEntry -Level 'INFO' -Component 'ESSENTIAL-APPS-SKIP' -Message "Skipped LibreOffice - Microsoft Office detected" -Data @{
                    SkipReason  = 'Microsoft Office already installed'
                    Status      = 'Not Needed'
                    Category    = $app.category
                    Description = $app.description
                }
                continue
            }

            $installationStatus = Test-ApplicationInstallation -AppDefinition $app -InstalledApps $installedApps

            if ($installationStatus.IsInstalled) {
                if ($IncludeInstalled) {
                    $installedItem = [PSCustomObject]@{
                        Name               = $app.name
                        Category           = $app.category
                        Description        = $app.description
                        DetectedVersion    = $installationStatus.Version
                        InstallationSource = $installationStatus.Source
                        InstallPath        = $installationStatus.InstallPath
                    }

                    # Log detected installed application
                    Write-LogEntry -Level 'INFO' -Component 'ESSENTIAL-APPS-INSTALLED' -Message "Detected installed: $($app.name)" -Data @{
                        Status      = 'Already Installed'
                        Category    = $app.category
                        Version     = $installationStatus.Version
                        Source      = $installationStatus.Source
                        InstallPath = $installationStatus.InstallPath
                        Description = $app.description
                    }

                    $auditResults.InstalledApps += $installedItem
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

                # Log detected missing application with detailed metadata
                Write-LogEntry -Level 'INFO' -Component 'ESSENTIAL-APPS-MISSING' -Message "Missing app: $($app.name)" -Data @{
                    Status            = 'Not Installed'
                    Category          = $app.category
                    Description       = $app.description
                    WingetId          = $app.winget
                    ChocolateyId      = $app.choco
                    Priority          = $missingApp.Priority
                    RecommendedMethod = $missingApp.RecommendedMethod
                    InstallReason     = "Essential $($app.category) application not found on system"
                }

                $auditResults.MissingApps += $missingApp

                # Add to recommended installs if high priority
                if ($missingApp.Priority -eq 'High') {
                    $auditResults.RecommendedInstalls += $missingApp

                    # Log high priority recommendation
                    Write-LogEntry -Level 'INFO' -Component 'ESSENTIAL-APPS-PRIORITY' -Message "High priority app missing: $($app.name)" -Data @{
                        Status            = 'High Priority Missing'
                        Category          = $app.category
                        Priority          = 'High'
                        RecommendedMethod = $missingApp.RecommendedMethod
                        ActionRequired    = 'Install recommended'
                    }
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

        Write-Information " Essential apps audit completed: $($auditResults.Summary.InstalledCount) installed, $($auditResults.Summary.MissingCount) missing" -InformationAction Continue

        # FIX #5: Save results using standardized Get-AuditResultsPath function
        try {
            # Use standardized path function if available
            if (Get-Command 'Get-AuditResultsPath' -ErrorAction SilentlyContinue) {
                $outputPath = Get-AuditResultsPath -ModuleName 'EssentialApps'
            }
            # Fallback to path retrieval function
            elseif (Get-Command 'Get-MaintenancePath' -ErrorAction SilentlyContinue) {
                $outputPath = Join-Path (Get-MaintenancePath 'TempRoot') "data\essential-apps-results.json"
                # Ensure directory exists
                $dataDir = Split-Path -Parent $outputPath
                if (-not (Test-Path $dataDir)) {
                    New-Item -Path $dataDir -ItemType Directory -Force | Out-Null
                }
            }
            # Final fallback to session path
            else {
                $outputPath = Get-SessionPath -Category 'data' -FileName 'essential-apps-results.json'
            }

            $auditResults | ConvertTo-Json -Depth 20 -WarningAction SilentlyContinue | Out-File -FilePath $outputPath -Encoding UTF8
            Write-Information "Audit results saved to standardized path: $outputPath" -InformationAction Continue
        }
        catch {
            Write-Warning "Failed to save audit results: $($_.Exception.Message)"
        }

        # Complete performance tracking
        try {
            Complete-PerformanceTracking -Context $perfContext -Status 'Success' -ResultCount $auditResults.Summary.TotalScanned
        }
        catch {
            Write-Verbose "Performance tracking completion failed - continuing"
        }

        return [PSCustomObject]$auditResults

    }
    catch {
        $errorMsg = "Essential apps audit failed: $($_.Exception.Message)"
        Write-Error $errorMsg

        try {
            Write-LogEntry -Level 'ERROR' -Component 'ESSENTIAL-APPS-AUDIT' -Message $errorMsg -Data @{ Error = $_.Exception }
            Complete-PerformanceTracking -Context $perfContext -Status 'Failed' -ErrorMessage $errorMsg
        }
        catch {
            Write-Verbose "Performance tracking cleanup failed: $_"
        }

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

        # Get from AppX packages (check availability first to avoid module initialization errors)
        if (Get-Command Get-AppxPackage -ErrorAction SilentlyContinue) {
            try {
                $appxPackages = Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue |
                Select-Object Name, Version, InstallLocation, Publisher
                $installedApps += $appxPackages
            }
            catch {
                Write-Verbose "Failed to get AppX packages: $($_.Exception.Message)"
            }
        }
        else {
            Write-Verbose "AppX cmdlets not available - skipping AppX package detection"
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
    Tests if Microsoft Office is installed on the system
#>
function Test-MicrosoftOfficeInstallation {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [array]$InstalledApps
    )

    # Microsoft Office detection patterns
    $officePatterns = @(
        '*Microsoft Office*',
        '*Microsoft 365*',
        '*Office 365*',
        '*Word 20*',
        '*Excel 20*',
        '*PowerPoint 20*',
        '*Outlook 20*'
    )

    foreach ($pattern in $officePatterns) {
        $matchedOffice = $InstalledApps | Where-Object {
            ($_.DisplayName -like $pattern) -or
            ($_.Name -like $pattern) -or
            ($_.Publisher -like "*Microsoft Corporation*" -and $_.DisplayName -like "*Office*")
        } | Select-Object -First 1

        if ($matchedOffice) {
            Write-LogEntry -Level 'INFO' -Component 'ESSENTIAL-APPS-OFFICE' -Message "Microsoft Office detected: $($matchedOffice.DisplayName)" -Data @{
                ProductName      = $matchedOffice.DisplayName
                Version          = $matchedOffice.DisplayVersion
                Publisher        = $matchedOffice.Publisher
                InstallDate      = $matchedOffice.InstallDate
                DetectionPattern = $pattern
            }
            return $true
        }
    }

    # Additional check via registry for Office installations
    try {
        $officeRegistryPaths = @(
            'HKLM:\SOFTWARE\Microsoft\Office',
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Office'
        )

        foreach ($regPath in $officeRegistryPaths) {
            if (Test-Path $regPath) {
                $officeVersions = Get-ChildItem -Path $regPath -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match '\d+\.\d+' } |
                Select-Object -First 1

                if ($officeVersions) {
                    Write-LogEntry -Level 'INFO' -Component 'ESSENTIAL-APPS-OFFICE' -Message "Microsoft Office detected via registry: $regPath" -Data @{
                        RegistryPath     = $regPath
                        DetectedVersions = @($officeVersions.Name)
                    }
                    return $true
                }
            }
        }
    }
    catch {
        Write-Verbose "Registry check for Office failed: $($_.Exception.Message)"
    }

    Write-LogEntry -Level 'INFO' -Component 'ESSENTIAL-APPS-OFFICE' -Message "No Microsoft Office installation detected" -Data @{
        CheckedPatterns = $officePatterns.Count
        CheckedRegistry = $true
        Result          = 'Not Found'
    }
    return $false
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

#endregion

# Backward compatibility alias
New-Alias -Name 'Get-EssentialAppsAudit' -Value 'Get-EssentialAppsAnalysis'

# Export public functions
Export-ModuleMember -Function @(
    'Get-EssentialAppsAnalysis'  #  v3.0 PRIMARY function
) -Alias @('Get-EssentialAppsAudit')  # Backward compatibility



