﻿#Requires -Version 7.0
# Module Dependencies:
#   - ConfigManager.psm1 (for essential apps configuration)
#   - LoggingManager.psm1 (for structured logging)
#   - DependencyManager.psm1 (for package management)

<#
.SYNOPSIS
    Essential Apps Installation Module - Type 2 (System Modification)

.DESCRIPTION
    Automated installation of curated essential applications using multiple package managers.
    Provides intelligent duplicate detection, parallel installation, and custom app support.

.NOTES
    Module Type: Type 2 (System Modification)
    Dependencies: ConfigManager.psm1, SystemInventory.psm1
    Requires: Administrator privileges for installations
    Author: Windows Maintenance Automation Project
    Version: 1.0.0
#>

using namespace System.Collections.Generic
using namespace System.Collections.Concurrent

# v3.0 Self-contained Type 2 module with internal Type 1 dependency

# Step 1: Import core infrastructure FIRST (REQUIRED) - Global scope for Type1 access
$ModuleRoot = if ($PSScriptRoot) { Split-Path -Parent $PSScriptRoot } else { Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path) }
$CoreInfraPath = Join-Path $ModuleRoot 'core\CoreInfrastructure.psm1'
if (Test-Path $CoreInfraPath) {
    Import-Module $CoreInfraPath -Force -Global -WarningAction SilentlyContinue
}
else {
    Write-Warning "CoreInfrastructure module not found at: $CoreInfraPath"
}

# Step 2: Import corresponding Type 1 module AFTER CoreInfrastructure (REQUIRED)
$Type1ModulePath = Join-Path $ModuleRoot 'type1\EssentialAppsAudit.psm1'
if (Test-Path $Type1ModulePath) {
    Import-Module $Type1ModulePath -Force
}
else {
    throw "Required Type 1 module not found: $Type1ModulePath"
}

# v3.0 compliance: No fallback functions needed with proper loading order

# Step 3: Import additional dependencies
$DependencyManagerPath = Join-Path $ModuleRoot 'core\DependencyManager.psm1'
if (Test-Path $DependencyManagerPath) {
    Import-Module $DependencyManagerPath -Force
}

# Validate Type1 module loaded correctly
if (-not (Get-Command -Name 'Get-EssentialAppsAudit' -ErrorAction SilentlyContinue)) {
    throw "Type 1 module functions not available - ensure EssentialAppsAudit.psm1 is properly imported"
}

#region v3.0 Standardized Execution Function

<#
.SYNOPSIS
    Main execution function for essential apps installation - v3.0 Architecture Pattern

.DESCRIPTION
    Standardized entry point that implements the Type2 → Type1 flow:
    1. Calls EssentialAppsAudit (Type1) to analyze missing apps
    2. Validates findings and logs results
    3. Executes installation actions (Type2) based on DryRun mode
    4. Returns standardized results for ReportGeneration

.PARAMETER Config
    Main configuration object from orchestrator

.PARAMETER DryRun
    When specified, simulates installation without making changes

.EXAMPLE
    $result = Invoke-EssentialApps -Config $MainConfig -DryRun

.EXAMPLE
    $result = Invoke-EssentialApps -Config $MainConfig
#>
function Invoke-EssentialApps {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Config,
        
        [Parameter()]
        [switch]$DryRun
    )
    
    # Performance tracking
    $perfContext = $null
    try {
        $perfContext = Start-PerformanceTracking -OperationName 'EssentialAppsInstallation' -Component 'ESSENTIAL-APPS'
    }
    catch {
        # CoreInfrastructure not available, continue without performance tracking
    }
    
    try {
        # Track execution duration for v3.0 compliance
        $executionStartTime = Get-Date
        
        # STEP 1: Always run Type1 detection first and save to temp_files/data/
        Write-LogEntry -Level 'INFO' -Component 'ESSENTIAL-APPS' -Message 'Starting essential apps analysis'
        $detectionResults = Get-EssentialAppsAnalysis -Config $Config
        
        # STEP 2: Compare detection with config to create diff list
        $configDataPath = Join-Path $Global:ProjectPaths.Config "essential-apps.json"
        if (-not (Test-Path $configDataPath)) {
            Write-LogEntry -Level 'ERROR' -Component 'ESSENTIAL-APPS' -Message "Config file not found: $configDataPath"
            return @{ Success = $false; ItemsDetected = 0; ItemsProcessed = 0; Message = 'Config file not found' }
        }
        
        # Create diff: Missing apps that need to be installed
        $diffList = if ($detectionResults.MissingApps) { $detectionResults.MissingApps } else { @() }
        $diffPath = Join-Path $Global:ProjectPaths.TempFiles "temp\essential-apps-diff.json"
        $diffList | ConvertTo-Json -Depth 20 -WarningAction SilentlyContinue | Set-Content $diffPath
        
        # STEP 3: Process ONLY items in diff list and log to dedicated directory
        $executionLogDir = Join-Path $Global:ProjectPaths.TempFiles "logs\essential-apps"
        New-Item -Path $executionLogDir -ItemType Directory -Force | Out-Null
        $executionLogPath = Join-Path $executionLogDir "execution.log"
        
        Write-LogEntry -Level 'INFO' -Component 'ESSENTIAL-APPS' -Message "Processing $($diffList.Count) missing apps from diff" -LogPath $executionLogPath
        
        if (-not $diffList -or $diffList.Count -eq 0) {
            Write-LogEntry -Level 'INFO' -Component 'ESSENTIAL-APPS' -Message 'No missing essential apps found' -LogPath $executionLogPath
            if ($perfContext) { Complete-PerformanceTracking -Context $perfContext -Status 'Success' }
            $executionTime = (Get-Date) - $executionStartTime
            return @{ 
                Success        = $true
                ItemsDetected  = if ($detectionResults.Summary) { $detectionResults.Summary.TotalScanned } else { 0 }
                ItemsProcessed = 0
                Duration       = $executionTime.TotalMilliseconds
            }
        }
        
        if ($DryRun) {
            Write-LogEntry -Level 'INFO' -Component 'ESSENTIAL-APPS' -Message "DRY-RUN: Would install $($diffList.Count) missing apps" -LogPath $executionLogPath
            $processedCount = 0
        }
        else {
            # Process only missing apps found in diff comparison
            $installResults = @{ InstalledApps = @(); FailedApps = @() }
            
            foreach ($app in $diffList) {
                try {
                    Write-LogEntry -Level 'INFO' -Component 'ESSENTIAL-APPS' -Message "Installing app: $($app.Name)" -LogPath $executionLogPath
                    
                    # Transform app data for Install-SingleApplication
                    $appHashtable = @{
                        Name   = $app.Name
                        Source = $app.RecommendedMethod
                        Id     = if ($app.RecommendedMethod -eq 'Winget') { $app.WingetId } else { $app.ChocoId }
                    }
                    
                    $result = Install-SingleApplication -AppData $appHashtable -ExecutionLogPath $executionLogPath
                    if ($result.Success) {
                        $installResults.InstalledApps += $app
                        $processedCount++
                        Write-LogEntry -Level 'SUCCESS' -Component 'ESSENTIAL-APPS' -Message "Successfully installed: $($app.Name)" -LogPath $executionLogPath
                    }
                    else {
                        $installResults.FailedApps += $app
                        Write-LogEntry -Level 'ERROR' -Component 'ESSENTIAL-APPS' -Message "Failed to install: $($app.Name) - $($result.ErrorMessage)" -LogPath $executionLogPath
                    }
                }
                catch {
                    $installResults.FailedApps += $app
                    Write-LogEntry -Level 'ERROR' -Component 'ESSENTIAL-APPS' -Message "Error installing $($app.Name): $($_.Exception.Message)" -LogPath $executionLogPath
                }
            }
            
            $processedCount = $installResults.InstalledApps.Count
            Write-LogEntry -Level 'INFO' -Component 'ESSENTIAL-APPS' -Message "Installed $processedCount essential apps" -LogPath $executionLogPath
        }
        
        if ($perfContext) { Complete-PerformanceTracking -Context $perfContext -Status 'Success' }
        
        $executionTime = (Get-Date) - $executionStartTime
        return @{
            Success        = $true
            ItemsDetected  = if ($detectionResults.Summary) { $detectionResults.Summary.TotalScanned } else { 0 }
            ItemsProcessed = $processedCount
            Duration       = $executionTime.TotalMilliseconds
        }
    }
    catch {
        $errorMsg = "Failed to execute essential apps installation: $($_.Exception.Message)"
        Write-LogEntry -Level 'ERROR' -Component 'ESSENTIAL-APPS' -Message $errorMsg
        
        if ($perfContext) { Complete-PerformanceTracking -Context $perfContext -Status 'Failed' -ErrorMessage $errorMsg }
        
        $executionTime = if ($executionStartTime) { (Get-Date) - $executionStartTime } else { New-TimeSpan }
        return @{
            Success        = $false
            ItemsDetected  = 0
            ItemsProcessed = 0
            Duration       = $executionTime.TotalMilliseconds
        }
    }
}

#endregion

#region Legacy Public Functions (Preserved for Internal Use)

<#
.SYNOPSIS
    Installs essential applications based on configuration

.DESCRIPTION
    Performs intelligent installation of curated essential applications using
    Winget, Chocolatey, or fallback methods. Includes duplicate detection
    and parallel installation optimization.

.PARAMETER Categories
    Specific app categories to install (Browsers, Productivity, Media, Development)

.PARAMETER CustomApps
    Additional custom apps to install beyond the standard list

.PARAMETER SkipDuplicates
    Skip apps that are already installed

.PARAMETER DryRun
    Simulate installation without making changes

.PARAMETER ParallelInstalls
    Number of parallel installations to run (default: 3)

.EXAMPLE
    $results = Install-EssentialApplication -Categories @('Browsers', 'Productivity')

.EXAMPLE
    $results = Install-EssentialApplication -CustomApps @('VSCode', 'Git') -DryRun
#>
function Install-EssentialApplication {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([bool])]
    param(
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string[]]$Categories = @('all'),

        [Parameter()]
        [AllowEmptyCollection()]
        [string[]]$CustomApps = @(),

        [Parameter()]
        [switch]$SkipDuplicates,

        [Parameter()]
        [switch]$DryRun,

        [Parameter()]
        [ValidateRange(1, 8)]
        [int]$ParallelInstalls = 3
    )

    Write-Information "📦 Starting essential applications installation..." -InformationAction Continue
    $startTime = Get-Date
    
    # Initialize structured logging and performance tracking
    try {
        Write-LogEntry -Level 'INFO' -Component 'ESSENTIAL-APPS' -Message 'Starting essential applications installation' -Data @{
            Categories       = $Categories
            CustomAppsCount  = $CustomApps.Count
            SkipDuplicates   = $SkipDuplicates.IsPresent
            DryRun           = $DryRun.IsPresent
            ParallelInstalls = $ParallelInstalls
        }
        $perfContext = Start-PerformanceTracking -OperationName 'EssentialAppsInstallation' -Component 'ESSENTIAL-APPS'
    }
    catch {
        # LoggingManager not available, continue with standard logging
    }
    
    # Check for administrator privileges before proceeding
    try {
        Assert-AdminPrivilege -Operation "Essential applications installation"
    }
    catch {
        Write-Error "Administrator privileges are required for application installation: $_"
        return $false
    }

    try {
        $ErrorActionPreference = 'Stop'
        Write-Verbose "Starting essential applications installation process"

        # Get essential apps from configuration
        $essentialApps = Get-UnifiedEssentialAppsList -IncludeCategories $Categories

        # Add custom apps if specified
        if ($CustomApps.Count -gt 0) {
            $customAppObjects = $CustomApps | ForEach-Object {
                @{
                    Name        = $_
                    Category    = 'Custom'
                    Winget      = $_
                    Chocolatey  = $_
                    Description = "Custom app: $_"
                }
            }
            $essentialApps = $essentialApps + $customAppObjects
        }

        if (-not $essentialApps -or $essentialApps.Count -eq 0) {
            Write-Warning "No essential apps found in configuration"
            return @{
                TotalApps = 0
                Installed = 0
                Skipped   = 0
                Failed    = 0
            }
        }

        Write-Information "  📋 Found $($essentialApps.Count) essential apps across $($Categories.Count) categories" -InformationAction Continue

        if ($DryRun) {
            Write-Information "  🧪 DRY RUN MODE - No installations will be performed" -InformationAction Continue
        }

        # Filter out duplicates by default (skip duplicates unless explicitly disabled)
        $appsToInstall = if ($PSBoundParameters.ContainsKey('SkipDuplicates') -and -not $SkipDuplicates) {
            $essentialApps
        }
        else {
            Get-AppNotInstalled -AppList $essentialApps
        }

        if ($appsToInstall.Count -eq 0) {
            Write-Information "  ✅ All essential apps are already installed" -InformationAction Continue
            return @{
                TotalApps        = $essentialApps.Count
                Installed        = 0
                Skipped          = $essentialApps.Count
                Failed           = 0
                AlreadyInstalled = $true
            }
        }

        Write-Information "  🎯 Installing $($appsToInstall.Count) applications (skipped $($essentialApps.Count - $appsToInstall.Count) duplicates)" -InformationAction Continue

        # Initialize results tracking
        $results = @{
            TotalApps        = $essentialApps.Count
            Installed        = 0
            Skipped          = $essentialApps.Count - $appsToInstall.Count
            Failed           = 0
            Details          = [List[PSCustomObject]]::new()
            ByCategory       = @{}
            ByPackageManager = @{}
        }

        # Group apps by package manager preference for optimal installation
        $wingetApps = $appsToInstall | Where-Object { $_.Winget -and (Test-PackageManagerAvailable -Manager 'Winget') }
        $chocoApps = $appsToInstall | Where-Object { -not $_.Winget -and $_.Chocolatey -and (Test-PackageManagerAvailable -Manager 'Chocolatey') }
        $manualApps = $appsToInstall | Where-Object { -not $_.Winget -and -not $_.Chocolatey }

        # Install apps using preferred package managers
        if ($wingetApps.Count -gt 0) {
            Write-Information "  🔹 Installing $($wingetApps.Count) apps via Winget..." -InformationAction Continue
            $wingetResults = Install-AppViaWinget -Apps $wingetApps -DryRun:$DryRun -ParallelCount $ParallelInstalls
            Merge-InstallationResult -Results $results -NewResults $wingetResults -PackageManager 'Winget'
        }

        if ($chocoApps.Count -gt 0) {
            Write-Information "  🍫 Installing $($chocoApps.Count) apps via Chocolatey..." -InformationAction Continue
            $chocoResults = Install-AppViaChocolatey -Apps $chocoApps -DryRun:$DryRun -ParallelCount $ParallelInstalls
            Merge-InstallationResult -Results $results -NewResults $chocoResults -PackageManager 'Chocolatey'
        }

        if ($manualApps.Count -gt 0) {
            Write-Information "  ⚠️  $($manualApps.Count) apps require manual installation (no package manager available)" -InformationAction Continue
            foreach ($app in $manualApps) {
                Write-Information "    📌 Manual installation needed: $($app.Name) - $($app.Description)" -InformationAction Continue
                $results.Details.Add([PSCustomObject]@{
                        Name           = $app.Name
                        Category       = $app.Category
                        Status         = 'Manual Required'
                        PackageManager = 'None'
                        Error          = 'No supported package manager available'
                    })
            }
            $results.Failed += $manualApps.Count
        }

        $duration = ((Get-Date) - $startTime).TotalSeconds

        # Summary output
        $statusIcon = if ($results.Failed -eq 0) { "✅" } else { "⚠️" }
        Write-Information "  $statusIcon Essential apps installation completed in $([math]::Round($duration, 2))s" -InformationAction Continue
        Write-Information "    📊 Total: $($results.TotalApps), Installed: $($results.Installed), Skipped: $($results.Skipped), Failed: $($results.Failed)" -InformationAction Continue

        $success = $results.Failed -eq 0 && $results.Installed -gt 0
        
        # Complete performance tracking and structured logging
        try {
            Complete-PerformanceTracking -PerformanceContext $perfContext -Success $success -ResultData @{
                TotalApps      = $results.TotalApps
                Installed      = $results.Installed
                Skipped        = $results.Skipped
                Failed         = $results.Failed
                Duration       = $duration
                Categories     = $Categories
                WingetApps     = ($wingetApps | Measure-Object).Count
                ChocolateyApps = ($chocoApps | Measure-Object).Count
                ManualApps     = ($manualApps | Measure-Object).Count
            }
            Write-LogEntry -Level $(if ($success) { 'SUCCESS' } else { 'WARN' }) -Component 'ESSENTIAL-APPS' -Message 'Essential applications installation completed' -Data $results
        }
        catch {
            # LoggingManager not available, continue with standard logging
        }
        
        # Log detailed results for audit trails
        Write-Verbose "Essential apps installation details: $(ConvertTo-Json $results -Depth 3)"
        Write-Verbose "Essential applications installation completed successfully"
        
        return $success
    }
    catch {
        $errorMessage = "❌ Essential applications installation failed: $($_.Exception.Message)"
        Write-Error $errorMessage
        Write-Verbose "Error details: $($_.Exception.ToString())"
        
        # Complete performance tracking for failed operation
        try {
            Complete-PerformanceTracking -PerformanceContext $perfContext -Success $false -ResultData @{ Error = $_.Exception.Message }
            Write-LogEntry -Level 'ERROR' -Component 'ESSENTIAL-APPS' -Message 'Essential applications installation failed' -Data @{ Error = $_.Exception.Message; ErrorType = $_.Exception.GetType().Name }
        }
        catch {
            # LoggingManager not available, continue with standard logging
        }
        
        # Type 2 module returns boolean for failure
        return $false
    }
    finally {
        $ErrorActionPreference = 'Continue'
        $duration = ((Get-Date) - $startTime).TotalSeconds
        Write-Verbose "Essential applications installation completed in $([math]::Round($duration, 2)) seconds"
    }
}

<#
.SYNOPSIS
    Gets list of essential apps that are not currently installed

.DESCRIPTION
    Performs intelligent detection to identify which essential apps
    are missing from the system across multiple installation sources.

.PARAMETER AppList
    Array of essential apps to check

.EXAMPLE
    $missingApps = Get-AppNotInstalled -AppList $essentialApps
#>
function Get-AppNotInstalled {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory)]
        [Array]$AppList
    )

    # Get system inventory for duplicate detection
    $inventory = Get-SystemInventory -UseCache

    if (-not $inventory.InstalledSoftware -or -not $inventory.InstalledSoftware.Programs) {
        Write-Warning "No system inventory available, cannot check for duplicates"
        return $AppList
    }

    # Build lookup table of installed apps
    $installedApps = [HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

    foreach ($app in $inventory.InstalledSoftware.Programs) {
        if ($app.Name) { $installedApps.Add($app.Name) | Out-Null }
        if ($app.DisplayName) { $installedApps.Add($app.DisplayName) | Out-Null }
        if ($app.Id) { $installedApps.Add($app.Id) | Out-Null }
        # Also add publisher information for better matching
        if ($app.Publisher) { $installedApps.Add($app.Publisher) | Out-Null }
    }

    # Check for Microsoft Office installation for LibreOffice logic
    $hasMicrosoftOffice = $inventory.InstalledSoftware.Programs | Where-Object {
        ($_.Name -like "*Microsoft Office*") -or
        ($_.DisplayName -like "*Microsoft Office*") -or
        ($_.Publisher -like "*Microsoft*" -and ($_.Name -like "*Office*" -or $_.DisplayName -like "*Office*")) -or
        ($_.Name -like "*Microsoft 365*") -or
        ($_.DisplayName -like "*Microsoft 365*")
    }

    # Filter out already installed apps
    $notInstalled = @()
    $alreadyInstalled = @()
    foreach ($app in $AppList) {
        $isInstalled = $false

        # Special logic for LibreOffice: Skip if Microsoft Office is installed
        if ($app.Name -like "*LibreOffice*" -and $hasMicrosoftOffice) {
            Write-Information "    🏢 Skipping LibreOffice: Microsoft Office detected" -InformationAction Continue
            continue
        }

        # Enhanced detection with multiple matching strategies
        $isInstalled = Test-AppInstallationStatus -App $app -InstalledApps $installedApps -InstalledPrograms $inventory.InstalledSoftware.Programs

        if (-not $isInstalled) {
            $notInstalled += $app
        }
        else {
            $alreadyInstalled += $app
        }
    }

    # Save diff lists to temp_files folder for analysis
    Save-AppDiffList -EssentialApps $AppList -InstalledApps $alreadyInstalled -MissingApps $notInstalled -InstalledSoftware $inventory.InstalledSoftware

    return $notInstalled
}

<#
.SYNOPSIS
    Saves app comparison diff lists to temp_files folder

.DESCRIPTION
    Creates comprehensive diff lists showing essential apps vs installed apps
    and saves them to the temp_files folder for analysis and reporting.

.PARAMETER EssentialApps
    Complete list of essential apps from configuration

.PARAMETER InstalledApps
    Essential apps that are already installed

.PARAMETER MissingApps
    Essential apps that are missing/not installed

.PARAMETER InstalledSoftware
    Complete system inventory of installed software

.EXAMPLE
    $result = Save-AppDiffList -EssentialApps $essential -InstalledApps $installed -MissingApps $missing -InstalledSoftware $inventory
    Creates diff files showing app comparison analysis

.EXAMPLE
    Save-AppDiffList -EssentialApps $apps -InstalledApps @() -MissingApps $apps -InstalledSoftware $systemInventory
    Creates diff files when no essential apps are currently installed
#>
function Save-AppDiffList {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [Array]$EssentialApps,

        [Parameter(Mandatory)]
        [Array]$InstalledApps,

        [Parameter(Mandatory)]
        [Array]$MissingApps
    )

    try {
        $scriptRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        # Use ConfigManager for path resolution if available
        try {
            $ConfigManagerPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'core\ConfigManager.psm1'
            if (Test-Path $ConfigManagerPath) {
                Import-Module $ConfigManagerPath -Force
                $tempDir = Get-TempDirectoryPath
            }
            else {
                $tempDir = Join-Path $scriptRoot 'temp_files'
            }
        }
        catch {
            $tempDir = Join-Path $scriptRoot 'temp_files'
        }
        if (-not (Test-Path $tempDir)) { Write-Verbose "temp_files directory not found: $tempDir"; return }

        # Categorization
        $categoryGroups = $EssentialApps | Group-Object { if ([string]::IsNullOrWhiteSpace($_.Category)) { 'Uncategorized' } else { $_.Category } }
        $byCategory = @{}
        foreach ($g in $categoryGroups) {
            $name = $g.Name
            $appsInCat = $g.Group
            $installedInCat = $InstalledApps | Where-Object { 
                $cat = if ([string]::IsNullOrWhiteSpace($_.Category)) { 'Uncategorized' } else { $_.Category }
                $cat -eq $name
            }
            $missingInCat = $MissingApps | Where-Object { 
                $cat = if ([string]::IsNullOrWhiteSpace($_.Category)) { 'Uncategorized' } else { $_.Category }
                $cat -eq $name
            }
            $rate = if ($appsInCat.Count -gt 0) { [math]::Round(($installedInCat.Count / $appsInCat.Count) * 100, 2) } else { 0 }
            $byCategory[$name] = @{ Total = $appsInCat.Count; Installed = $installedInCat.Count; Missing = $missingInCat.Count; InstallationRate = $rate; MissingAppNames = ($missingInCat | ForEach-Object { $_.Name }) }
        }

        # Package manager buckets
        $wingetApps = $MissingApps | Where-Object { $_.Winget }
        $chocoApps = $MissingApps | Where-Object { -not $_.Winget -and $_.Chocolatey }
        $manualApps = $MissingApps | Where-Object { -not $_.Winget -and -not $_.Chocolatey }

        $wingetPkgArr = @()
        if ($wingetApps) { 
            foreach ($a in $wingetApps) { 
                if ($null -ne $a) { 
                    $wingetPkgArr += @{ Name = $a.Name; Id = $a.Winget } 
                } 
            } 
        }
        
        $chocoPkgArr = @()
        if ($chocoApps) { 
            foreach ($a in $chocoApps) { 
                if ($null -ne $a) { 
                    $chocoPkgArr += @{ Name = $a.Name; Id = $a.Chocolatey } 
                } 
            } 
        }
        
        $manualPkgArr = @()
        if ($manualApps) { 
            foreach ($a in $manualApps) { 
                if ($null -ne $a) { 
                    $manualPkgArr += @{ Name = $a.Name; Description = $a.Description } 
                } 
            } 
        }

        # Recommendations
        $recs = @()
        if ($MissingApps.Count -gt 0) {
            $recs += "Install $($MissingApps.Count) missing essential applications"
            if ($wingetApps.Count -gt 0) { $recs += "Use Winget to install $($wingetApps.Count) apps: $($wingetApps.Name -join ', ')" }
            if ($chocoApps.Count -gt 0) { $recs += "Use Chocolatey to install $($chocoApps.Count) apps: $($chocoApps.Name -join ', ')" }
            if ($manualApps.Count -gt 0) { $recs += "Manually install $($manualApps.Count) apps: $($manualApps.Name -join ', ')" }
        }
        else {
            $recs += "All essential applications are installed"
        }

        # Build analysis object
        $diffAnalysis = [ordered]@{}
        $diffAnalysis.Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        $diffAnalysis.Summary = @{ TotalEssentialApps = $EssentialApps.Count; AlreadyInstalled = $InstalledApps.Count; MissingApps = $MissingApps.Count; InstallationRate = if ($EssentialApps.Count -gt 0) { [math]::Round(($InstalledApps.Count / $EssentialApps.Count) * 100, 2) } else { 0 } }
        $diffAnalysis.EssentialApps = $EssentialApps
        $diffAnalysis.AlreadyInstalled = $InstalledApps
        $diffAnalysis.MissingApps = $MissingApps
        $diffAnalysis.DetailedAnalysis = @{ ByCategory = $byCategory; ByPackageManager = @{ Winget = @{ Count = $wingetPkgArr.Count; Apps = $wingetPkgArr }; Chocolatey = @{ Count = $chocoPkgArr.Count; Apps = $chocoPkgArr }; Manual = @{ Count = $manualPkgArr.Count; Apps = $manualPkgArr } }; RecommendedActions = $recs }

        # Save outputs
        $diffPath = Save-OrganizedFile -Data $diffAnalysis -FileType 'Data' -Category 'apps' -FileName 'essential-apps-analysis' -Format 'JSON'
        if ($diffPath) { Write-Information "  📋 App diff analysis saved to: $diffPath" -InformationAction Continue }

        $missingAppsPath = $null
        $installDataPath = $null
        if ($MissingApps.Count -gt 0) {
            $missingAppsPath = Save-OrganizedFile -Data $MissingApps -FileType 'Data' -Category 'apps' -FileName 'missing-apps' -Format 'JSON'
            if ($missingAppsPath) { Write-Information "  ❌ Missing apps list saved to: $missingAppsPath" -InformationAction Continue }

            $installationData = @{ Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss"); TotalMissingApps = $MissingApps.Count; InstallationMethods = @{ Winget = @{ Count = $wingetApps.Count; Apps = $wingetPkgArr }; Chocolatey = @{ Count = $chocoApps.Count; Apps = $chocoPkgArr }; Manual = @{ Count = $manualApps.Count; Apps = $manualPkgArr } } }
            $installDataPath = Save-OrganizedFile -Data $installationData -FileType 'Data' -Category 'apps' -FileName 'installation-methods' -Format 'JSON'
            if ($installDataPath) { Write-Information "  🔧 Installation methods data saved to: $installDataPath" -InformationAction Continue }
        }

        $installedAppsPath = $null
        if ($InstalledApps.Count -gt 0) {
            $installedAppsPath = Save-OrganizedFile -Data $InstalledApps -FileType 'Data' -Category 'apps' -FileName 'installed-essential-apps' -Format 'JSON'
            if ($installedAppsPath) { Write-Information "  ✅ Installed essential apps list saved to: $installedAppsPath" -InformationAction Continue }
        }

        return @{ DiffPath = $diffPath; MissingAppsPath = $missingAppsPath; InstallDataPath = $installDataPath; InstalledAppsPath = $installedAppsPath }
    }
    catch {
        Write-Warning "Failed to save app diff lists: $_"
        return $null
    }
}

<#
.SYNOPSIS
    Enhanced application installation status detection

.DESCRIPTION
    Uses multiple detection strategies to accurately determine if an application
    is already installed, including exact matches, partial matches, and common variations.

.PARAMETER App
    Essential app object to check

.PARAMETER InstalledApps
    HashSet of installed app names for fast lookup

.PARAMETER InstalledPrograms
    Complete list of installed programs from system inventory

.EXAMPLE
    $isInstalled = Test-AppInstallationStatus -App $appObject -InstalledApps $installedHashSet -InstalledPrograms $programList
    Returns $true if the app is detected as installed

.EXAMPLE
    if (Test-AppInstallationStatus -App $chromeApp -InstalledApps $apps -InstalledPrograms $programs) {
        Write-Information "Chrome is already installed" -InformationAction Continue
    }
#>
function Test-AppInstallationStatus {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$App,

        [Parameter(Mandatory)]
        $InstalledApps,

        [Parameter(Mandatory)]
        [Array]$InstalledPrograms
    )

    # Strategy 1: Exact name matches
    $identifiersToCheck = @()
    if ($App.Name) { $identifiersToCheck += $App.Name }
    if ($App.Winget) { $identifiersToCheck += $App.Winget }
    if ($App.Chocolatey) { $identifiersToCheck += $App.Chocolatey }

    foreach ($identifier in $identifiersToCheck) {
        if ($InstalledApps.Contains($identifier)) {
            Write-Verbose "Found exact match for '$($App.Name)': $identifier"
            return $true
        }
    }

    # Strategy 2: Partial matches with wildcards
    foreach ($identifier in $identifiersToCheck) {
        $matchingApps = $InstalledApps | Where-Object { $_ -like "*$identifier*" }
        if ($matchingApps.Count -gt 0) {
            Write-Verbose "Found partial match for '$($App.Name)': $($matchingApps -join ', ')"
            return $true
        }
    }

    # Strategy 3: Configuration-only detection (v3.0 compliance)
    # No hardcoded variations - uses only configured identifiers

    # v3.0 compliance: Strict configuration-only approach
    # Get configured apps from configuration file - no fallbacks or variations
    try {
        $configuredApps = Get-UnifiedEssentialAppsList
        if (-not $configuredApps -or $configuredApps.Count -eq 0) {
            throw "Essential apps configuration is empty or not found in config/essential-apps.json"
        }
    }
    catch {
        throw "Failed to load essential apps configuration: $($_.Exception.Message). Ensure config/essential-apps.json exists and is properly formatted."
    }

    # Use exact app name match only - no variations or aliases
    # This enforces precise configuration control

    # Strategy 4: Check against installed programs using exact identifiers only
    # v3.0 compliance: Use only configured identifiers, no variations or aliases
    foreach ($identifier in $identifiersToCheck) {
        if (-not $identifier) { continue }

        $matchingPrograms = $InstalledPrograms | Where-Object {
            ($_.Name -and (($_.Name -like "*$identifier*") -or ($_.Name -eq $identifier))) -or
            ($_.DisplayName -and (($_.DisplayName -like "*$identifier*") -or ($_.DisplayName -eq $identifier))) -or
            ($_.Id -and (($_.Id -like "*$identifier*") -or ($_.Id -eq $identifier)))
        }

        if ($matchingPrograms.Count -gt 0) {
            Write-Verbose "Found match for '$($App.Name)' using identifier '$identifier': $($matchingPrograms[0].Name -or $matchingPrograms[0].DisplayName)"
            return $true
        }
    }

    # Strategy 5: Publisher-based detection for Microsoft apps
    if ($App.Name -like "*Microsoft*" -or $App.Winget -like "*Microsoft*") {
        $microsoftPrograms = $InstalledPrograms | Where-Object {
            ($_.Publisher -like "*Microsoft*") -and
            ($_.Name -or $_.DisplayName) -and
            (($_.Name -like "*$($App.Name.Replace('Microsoft ', ''))*") -or
            ($_.DisplayName -like "*$($App.Name.Replace('Microsoft ', ''))*"))
        }

        if ($microsoftPrograms.Count -gt 0) {
            Write-Verbose "Found Microsoft app match for '$($App.Name)': $($microsoftPrograms[0].Name -or $microsoftPrograms[0].DisplayName)"
            return $true
        }
    }

    # Strategy 6: Version-agnostic matching (remove version numbers and check again)
    $cleanAppName = $App.Name -replace '\s+\d+(\.\d+)*(\s|$)', '' -replace '\s+$', ''
    if ($cleanAppName -ne $App.Name) {
        $versionAgnosticMatch = $InstalledPrograms | Where-Object {
            ($_.Name -and $_.Name -like "*$cleanAppName*") -or
            ($_.DisplayName -and $_.DisplayName -like "*$cleanAppName*")
        }

        if ($versionAgnosticMatch.Count -gt 0) {
            Write-Verbose "Found version-agnostic match for '$($App.Name)' using '$cleanAppName': $($versionAgnosticMatch[0].Name -or $versionAgnosticMatch[0].DisplayName)"
            return $true
        }
    }

    Write-Verbose "No installation found for '$($App.Name)'"
    return $false
}

#endregion

#region Winget Installation

<#
.SYNOPSIS
    Installs applications using Winget package manager

.DESCRIPTION
    Performs parallel installation of applications using Windows Package Manager (winget).
    Includes intelligent retry logic, error handling, and detailed progress tracking.
    Supports dry-run mode for testing without actual installations.

.PARAMETER Apps
    Array of application objects to install via Winget

.PARAMETER DryRun
    When specified, simulates installation without making actual changes

.PARAMETER ParallelCount
    Number of parallel installations to run simultaneously (default: 3)

.EXAMPLE
    $result = Install-AppViaWinget -Apps $appList
    Installs all apps in the list using Winget with default parallel count

.EXAMPLE
    $result = Install-AppViaWinget -Apps $appList -DryRun -ParallelCount 5
    Tests installation of apps with higher parallelism without making changes
#>
function Install-AppViaWinget {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [Array]$Apps,

        [Parameter()]
        [switch]$DryRun,

        [Parameter()]
        [int]$ParallelCount = 3
    )

    # Start structured logging for Winget installation batch
    try {
        Write-LogEntry -Level 'INFO' -Component 'ESSENTIAL-APPS' -Message 'Starting Winget batch installation' -Data @{ AppCount = $Apps.Count; ParallelCount = $ParallelCount; DryRun = $DryRun.IsPresent }
    }
    catch {
        # LoggingManager not available, continue with standard logging
    }
    
    $results = @{
        Installed = 0
        Failed    = 0
        Details   = [List[PSCustomObject]]::new()
    }

    if (-not (Test-PackageManagerAvailable -Manager 'Winget')) {
        Write-Warning "Winget not available"
        $results.Failed = $Apps.Count
        return $results
    }

    # Process apps in batches to avoid overwhelming the system
    $batches = Split-ArrayIntoBatch -Array $Apps -BatchSize $ParallelCount

    foreach ($batch in $batches) {
        $batch | ForEach-Object -ThrottleLimit $ParallelCount -Parallel {
            $app = $_
            $isDryRun = $using:DryRun
            $operationStart = Get-Date

            $result = @{
                Name           = $app.Name
                Category       = $app.Category
                PackageId      = $app.Winget
                Status         = 'Unknown'
                PackageManager = 'Winget'
                Error          = $null
            }

            try {
                # Enhanced logging: Pre-check if app is already installed
                $wingetListArgs = @('list', '--id', $app.Winget, '--accept-source-agreements')
                $listOutput = & winget @wingetListArgs 2>&1 | Out-String
                $alreadyInstalled = $LASTEXITCODE -eq 0 -and $listOutput -match $app.Winget
                
                # Log operation start with pre-check state
                Write-Information "    📦 [WINGET] Processing: $($app.Name) (ID: $($app.Winget)) - Already installed: $alreadyInstalled" -InformationAction Continue
                
                if ($alreadyInstalled -and -not $isDryRun) {
                    Write-Information "      ℹ️  App already installed, skipping: $($app.Name)" -InformationAction Continue
                    $result.Status = 'AlreadyInstalled'
                }
                elseif ($isDryRun) {
                    Write-Information "    [DRY RUN] Would install: $($app.Name) ($($app.Winget))" -InformationAction Continue
                    $result.Status = 'Simulated'
                }
                else {
                    Write-Information "    📦 Installing: $($app.Name)..." -InformationAction Continue

                    $wingetArgs = @(
                        'install',
                        '--id', $app.Winget,
                        '--silent',
                        '--accept-package-agreements',
                        '--accept-source-agreements'
                    )
                    
                    # Log the exact command being executed
                    Write-Information "      🔧 Executing: winget $($wingetArgs -join ' ')" -InformationAction Continue

                    $process = Start-Process -FilePath 'winget' -ArgumentList $wingetArgs -Wait -PassThru -NoNewWindow

                    if ($process.ExitCode -eq 0) {
                        # Post-installation verification
                        Write-LogEntry -Level 'INFO' -Component 'ESSENTIAL-APPS' -Operation 'Verify' -Target $app.Name -Message 'Verifying Winget package installation'
                        
                        $verifyOutput = & winget @wingetListArgs 2>&1 | Out-String
                        $verifyInstalled = $LASTEXITCODE -eq 0 -and $verifyOutput -match $app.Winget
                        
                        $operationDuration = ((Get-Date) - $operationStart).TotalSeconds
                        
                        if ($verifyInstalled) {
                            # Log successful verification
                            Write-OperationSuccess -Component 'ESSENTIAL-APPS' -Operation 'Verify' -Target $app.Name -Metrics @{
                                PackageId          = $app.Winget
                                VerificationPassed = $true
                                IsInstalled        = $true
                            }
                            
                            # Log successful installation
                            Write-OperationSuccess -Component 'ESSENTIAL-APPS' -Operation 'Install' -Target $app.Name -Metrics @{
                                Duration       = $operationDuration
                                PackageManager = 'Winget'
                                PackageId      = $app.Winget
                                Verified       = $true
                            }
                            
                            $result.Status = 'Installed'
                            Write-Information "      ✅ Successfully installed: $($app.Name) (Duration: ${operationDuration}s, Verified: True)" -InformationAction Continue
                        }
                        else {
                            # Log failed verification
                            Write-OperationFailure -Component 'ESSENTIAL-APPS' -Operation 'Verify' -Target $app.Name -Error (New-Object Exception("Package not found after installation (exit code 0)"))
                            
                            Write-Information "      ⚠️  Installation exit code 0, but verification failed: $($app.Name)" -InformationAction Continue
                            $result.Status = 'Installed'  # Trust exit code
                        }
                    }
                    else {
                        throw "Winget installation failed with exit code $($process.ExitCode)"
                    }
                }
            }
            catch {
                $result.Status = 'Failed'
                $result.Error = $_.Exception.Message
                Write-Warning "Failed to install $($app.Name): $($_.Exception.Message)"
            }

            return [PSCustomObject]$result
        } | ForEach-Object {
            $results.Details.Add($_)
            if ($_.Status -eq 'Installed' -or $_.Status -eq 'Simulated' -or $_.Status -eq 'AlreadyInstalled') {
                $results.Installed++
            }
            else {
                $results.Failed++
            }
        }
    }

    return $results
}

#endregion

#region Chocolatey Installation

<#
.SYNOPSIS
    Installs applications using Chocolatey package manager

.DESCRIPTION
    Performs parallel installation of applications using Chocolatey package manager.
    Uses lower parallelism than Winget for stability. Includes comprehensive error
    handling and supports dry-run mode for testing installations.

.PARAMETER Apps
    Array of application objects to install via Chocolatey

.PARAMETER DryRun
    When specified, simulates installation without making actual changes

.PARAMETER ParallelCount
    Number of parallel installations to run simultaneously (default: 2, lower than Winget for stability)

.EXAMPLE
    $result = Install-AppViaChocolatey -Apps $appList
    Installs all apps in the list using Chocolatey with default parallel count

.EXAMPLE
    $result = Install-AppViaChocolatey -Apps $appList -DryRun
    Tests installation of apps without making actual changes
#>
function Install-AppViaChocolatey {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [Array]$Apps,

        [Parameter()]
        [switch]$DryRun
    )

    # Start structured logging for Chocolatey installation batch
    try {
        Write-LogEntry -Level 'INFO' -Component 'ESSENTIAL-APPS' -Message 'Starting Chocolatey batch installation' -Data @{ AppCount = $Apps.Count; DryRun = $DryRun.IsPresent }
    }
    catch {
        # LoggingManager not available, continue with standard logging
    }
    
    $results = @{
        Installed = 0
        Failed    = 0
        Details   = [List[PSCustomObject]]::new()
    }

    if (-not (Test-PackageManagerAvailable -Manager 'Chocolatey')) {
        Write-Warning "Chocolatey not available"
        $results.Failed = $Apps.Count
        return $results
    }

    foreach ($app in $Apps) {
        $operationStart = Get-Date
        $result = @{
            Name           = $app.Name
            Category       = $app.Category
            PackageId      = $app.Chocolatey
            Status         = 'Unknown'
            PackageManager = 'Chocolatey'
            Error          = $null
        }

        try {
            # Enhanced logging: Pre-check if app is already installed
            $chocoListArgs = @('list', '--local-only', '--exact', $app.Chocolatey, '--limit-output')
            $listOutput = & choco @chocoListArgs 2>&1
            $alreadyInstalled = $LASTEXITCODE -eq 0 -and $listOutput -match $app.Chocolatey
            $installedVersion = if ($alreadyInstalled -and $listOutput -match "$($app.Chocolatey)\|(.+)") { $matches[1] } else { 'N/A' }
            
            # Log operation start with pre-check state
            Write-Information "    🍫 [CHOCO] Processing: $($app.Name) (ID: $($app.Chocolatey)) - Already installed: $alreadyInstalled" -InformationAction Continue
            if ($alreadyInstalled) {
                Write-Information "      ℹ️  Current version: $installedVersion" -InformationAction Continue
            }
            
            if ($alreadyInstalled -and -not $DryRun) {
                Write-Information "      ℹ️  App already installed, skipping: $($app.Name)" -InformationAction Continue
                $result.Status = 'AlreadyInstalled'
                $results.Installed++
            }
            elseif ($DryRun) {
                Write-Information "    [DRY RUN] Would install: $($app.Name) ($($app.Chocolatey))" -InformationAction Continue
                $result.Status = 'Simulated'
                $results.Installed++
            }
            else {
                Write-Information "    🍫 Installing: $($app.Name)..." -InformationAction Continue

                $chocoArgs = @(
                    'install',
                    $app.Chocolatey,
                    '-y',
                    '--limit-output'
                )
                
                # Log the exact command being executed
                Write-Information "      🔧 Executing: choco $($chocoArgs -join ' ')" -InformationAction Continue

                $process = Start-Process -FilePath 'choco' -ArgumentList $chocoArgs -Wait -PassThru -NoNewWindow

                if ($process.ExitCode -eq 0) {
                    # Post-installation verification
                    Write-LogEntry -Level 'INFO' -Component 'ESSENTIAL-APPS' -Operation 'Verify' -Target $app.Name -Message 'Verifying Chocolatey package installation'
                    
                    $verifyOutput = & choco @chocoListArgs 2>&1
                    $verifyInstalled = $LASTEXITCODE -eq 0 -and $verifyOutput -match $app.Chocolatey
                    $newVersion = if ($verifyInstalled -and $verifyOutput -match "$($app.Chocolatey)\|(.+)") { $matches[1] } else { 'Unknown' }
                    
                    $operationDuration = ((Get-Date) - $operationStart).TotalSeconds
                    
                    if ($verifyInstalled) {
                        # Log successful verification
                        Write-OperationSuccess -Component 'ESSENTIAL-APPS' -Operation 'Verify' -Target $app.Name -Metrics @{
                            PackageId          = $app.Chocolatey
                            InstalledVersion   = $newVersion
                            VerificationPassed = $true
                            IsInstalled        = $true
                        }
                        
                        # Log successful installation
                        Write-OperationSuccess -Component 'ESSENTIAL-APPS' -Operation 'Install' -Target $app.Name -Metrics @{
                            Duration       = $operationDuration
                            PackageManager = 'Chocolatey'
                            PackageId      = $app.Chocolatey
                            Version        = $newVersion
                            Verified       = $true
                        }
                        
                        $result.Status = 'Installed'
                        Write-Information "      ✅ Successfully installed: $($app.Name) v$newVersion (Duration: ${operationDuration}s, Verified: True)" -InformationAction Continue
                    }
                    else {
                        # Log failed verification
                        Write-OperationFailure -Component 'ESSENTIAL-APPS' -Operation 'Verify' -Target $app.Name -Error (New-Object Exception("Package not found after installation (exit code 0)"))
                        
                        Write-Information "      ⚠️  Installation exit code 0, but verification failed: $($app.Name)" -InformationAction Continue
                        $result.Status = 'Installed'  # Trust exit code
                    }
                    $results.Installed++
                }
                else {
                    throw "Chocolatey installation failed with exit code $($process.ExitCode)"
                }
            }
        }
        catch {
            $result.Status = 'Failed'
            $result.Error = $_.Exception.Message
            $results.Failed++
            Write-Warning "Failed to install $($app.Name): $($_.Exception.Message)"
        }

        $results.Details.Add([PSCustomObject]$result)
    }

    return $results
}

#endregion

#region Helper Functions

<#
.SYNOPSIS
    Tests if a package manager is available and functional

.DESCRIPTION
    Performs availability check for the specified package manager by verifying
    the executable is available in the system PATH. Returns boolean result
    indicating whether the package manager can be used for installations.

.PARAMETER Manager
    Package manager to test ('Winget' or 'Chocolatey')

.EXAMPLE
    if (Test-PackageManagerAvailable -Manager 'Winget') {
        Write-Information "Winget is available for use" -InformationAction Continue
    }

.EXAMPLE
    $chocoAvailable = Test-PackageManagerAvailable -Manager 'Chocolatey'
    Tests if Chocolatey package manager is installed and accessible
#>
function Test-PackageManagerAvailable {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Winget', 'Chocolatey')]
        [string]$Manager
    )

    switch ($Manager) {
        'Winget' {
            return $null -ne (Get-Command winget -ErrorAction SilentlyContinue)
        }
        'Chocolatey' {
            return $null -ne (Get-Command choco -ErrorAction SilentlyContinue)
        }
        default {
            return $false
        }
    }
}

<#
.SYNOPSIS
    Splits an array into smaller batches for parallel processing

.DESCRIPTION
    Divides a large array into smaller chunks of specified size to enable
    efficient parallel processing. Handles edge cases where the array size
    is not evenly divisible by the batch size.

.PARAMETER Array
    The array to split into batches

.PARAMETER BatchSize
    Maximum number of items per batch

.EXAMPLE
    $batches = Split-ArrayIntoBatch -Array $apps -BatchSize 3
    Splits the apps array into batches of 3 items each

.EXAMPLE
    $chunks = Split-ArrayIntoBatch -Array @(1..10) -BatchSize 4
    Creates batches: @(1,2,3,4), @(5,6,7,8), @(9,10)
#>
function Split-ArrayIntoBatch {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Array]$Array,
        [int]$BatchSize
    )

    $batches = @()
    for ($i = 0; $i -lt $Array.Count; $i += $BatchSize) {
        $endIndex = [Math]::Min($i + $BatchSize - 1, $Array.Count - 1)
        $batches += , $Array[$i..$endIndex]
    }

    return $batches
}

<#
.SYNOPSIS
    Merges installation results into main results object

.DESCRIPTION
    Combines installation results from different package managers into a single
    consolidated results object. Updates counters, merges details, and maintains
    statistics by package manager and category.

.PARAMETER Results
    Main results hashtable to merge into

.PARAMETER NewResults
    New results from a package manager to add

.PARAMETER PackageManager
    Name of the package manager that generated the new results

.EXAMPLE
    Merge-InstallationResult -Results $mainResults -NewResults $wingetResults -PackageManager 'Winget'
    Merges Winget installation results into the main results object

.EXAMPLE
    Merge-InstallationResult -Results $results -NewResults $chocoResults -PackageManager 'Chocolatey'
    Adds Chocolatey results to the consolidated installation results
#>
function Merge-InstallationResult {
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [hashtable]$Results,
        [hashtable]$NewResults,
        [string]$PackageManager
    )

    $Results.Installed += $NewResults.Installed
    $Results.Failed += $NewResults.Failed
    $Results.Details.AddRange($NewResults.Details)
    $Results.ByPackageManager[$PackageManager] = $NewResults

    # Update category statistics
    foreach ($detail in $NewResults.Details) {
        if (-not $Results.ByCategory.ContainsKey($detail.Category)) {
            $Results.ByCategory[$detail.Category] = @{ Installed = 0; Failed = 0 }
        }

        if ($detail.Status -eq 'Installed' -or $detail.Status -eq 'Simulated') {
            $Results.ByCategory[$detail.Category].Installed++
        }
        else {
            $Results.ByCategory[$detail.Category].Failed++
        }
    }
}

<#
.SYNOPSIS
    Gets installation statistics and summary

.DESCRIPTION
    Calculates comprehensive statistics from installation results including
    success rates, most used package manager, and category performance metrics.
    Provides insights for installation process optimization.

.PARAMETER Results
    Installation results hashtable containing detailed installation data

.EXAMPLE
    $stats = Get-InstallationStatistic -Results $installationResults
    Gets comprehensive statistics from the installation results

.EXAMPLE
    $summary = Get-InstallationStatistic -Results $results
    Write-Information "Success rate: $($summary.SuccessRate)%" -InformationAction Continue
#>
function Get-InstallationStatistic {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([hashtable]$Results)

    return @{
        TotalProcessed         = $Results.TotalApps
        SuccessRate            = if ($Results.TotalApps -gt 0) {
            [math]::Round(($Results.Installed / $Results.TotalApps) * 100, 1)
        }
        else { 0 }
        MostUsedPackageManager = ($Results.ByPackageManager.GetEnumerator() |
            Sort-Object { $_.Value.Installed } -Descending |
            Select-Object -First 1).Key
        MostSuccessfulCategory = ($Results.ByCategory.GetEnumerator() |
            Sort-Object { $_.Value.Installed } -Descending |
            Select-Object -First 1).Key
    }
}

#endregion

# v3.0 Individual app installation function (Internal use)
function Install-SingleApplication {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$AppData,
        
        [Parameter(Mandatory)]
        [string]$ExecutionLogPath
    )
    
    $appName = $AppData.Name
    $appId = $AppData.Id
    $source = $AppData.Source
    
    # Validate required fields
    if (-not $source -or [string]::IsNullOrWhiteSpace($source)) {
        $errorMsg = "Installation source not specified for $appName"
        Write-LogEntry -Level 'ERROR' -Component 'ESSENTIAL-APPS' -Message $errorMsg -LogPath $ExecutionLogPath
        return @{ Success = $false; Method = 'Unknown'; AppName = $appName; ErrorMessage = $errorMsg }
    }
    
    if (-not $appId -or [string]::IsNullOrWhiteSpace($appId)) {
        $errorMsg = "Application ID not specified for $appName"
        Write-LogEntry -Level 'ERROR' -Component 'ESSENTIAL-APPS' -Message $errorMsg -LogPath $ExecutionLogPath
        return @{ Success = $false; Method = $source; AppName = $appName; ErrorMessage = $errorMsg }
    }
    
    Write-LogEntry -Level 'INFO' -Component 'ESSENTIAL-APPS' -Message "Starting installation: $appName via $source" -LogPath $ExecutionLogPath
    
    try {
        switch ($source.ToLower()) {
            'winget' {
                Write-LogEntry -Level 'INFO' -Component 'ESSENTIAL-APPS' -Message "Executing: winget install --id $appId --silent --accept-package-agreements" -LogPath $ExecutionLogPath
                $installProcess = Start-Process -FilePath 'winget' -ArgumentList @('install', '--id', $appId, '--silent', '--accept-package-agreements', '--accept-source-agreements') -Wait -PassThru -NoNewWindow
                
                if ($installProcess.ExitCode -eq 0) {
                    Write-LogEntry -Level 'SUCCESS' -Component 'ESSENTIAL-APPS' -Message "Winget installation successful: $appName" -LogPath $ExecutionLogPath
                    return @{ Success = $true; Method = 'Winget'; AppName = $appName }
                }
                else {
                    Write-LogEntry -Level 'ERROR' -Component 'ESSENTIAL-APPS' -Message "Winget installation failed: $appName (Exit code: $($installProcess.ExitCode))" -LogPath $ExecutionLogPath
                    return @{ Success = $false; Method = 'Winget'; AppName = $appName; ErrorMessage = "Exit code: $($installProcess.ExitCode)" }
                }
            }
            
            'chocolatey' {
                Write-LogEntry -Level 'INFO' -Component 'ESSENTIAL-APPS' -Message "Executing: choco install $appName --force --yes" -LogPath $ExecutionLogPath
                $installProcess = Start-Process -FilePath 'choco' -ArgumentList @('install', $appName, '--force', '--yes') -Wait -PassThru -NoNewWindow
                
                if ($installProcess.ExitCode -eq 0) {
                    Write-LogEntry -Level 'SUCCESS' -Component 'ESSENTIAL-APPS' -Message "Chocolatey installation successful: $appName" -LogPath $ExecutionLogPath
                    return @{ Success = $true; Method = 'Chocolatey'; AppName = $appName }
                }
                else {
                    Write-LogEntry -Level 'ERROR' -Component 'ESSENTIAL-APPS' -Message "Chocolatey installation failed: $appName (Exit code: $($installProcess.ExitCode))" -LogPath $ExecutionLogPath
                    return @{ Success = $false; Method = 'Chocolatey'; AppName = $appName; ErrorMessage = "Exit code: $($installProcess.ExitCode)" }
                }
            }
            
            'direct' {
                if ($AppData.DownloadUrl) {
                    Write-LogEntry -Level 'INFO' -Component 'ESSENTIAL-APPS' -Message "Direct download installation: $appName from $($AppData.DownloadUrl)" -LogPath $ExecutionLogPath
                    $tempPath = Join-Path $env:TEMP "$appName-installer.exe"
                    
                    # Download installer
                    Invoke-WebRequest -Uri $AppData.DownloadUrl -OutFile $tempPath -UseBasicParsing
                    
                    # Execute installer
                    $installArgs = if ($AppData.InstallArgs) { $AppData.InstallArgs } else { @('/S') }
                    $installProcess = Start-Process -FilePath $tempPath -ArgumentList $installArgs -Wait -PassThru
                    
                    # Cleanup
                    Remove-Item $tempPath -ErrorAction SilentlyContinue
                    
                    if ($installProcess.ExitCode -eq 0) {
                        Write-LogEntry -Level 'SUCCESS' -Component 'ESSENTIAL-APPS' -Message "Direct installation successful: $appName" -LogPath $ExecutionLogPath
                        return @{ Success = $true; Method = 'Direct'; AppName = $appName }
                    }
                    else {
                        Write-LogEntry -Level 'ERROR' -Component 'ESSENTIAL-APPS' -Message "Direct installation failed: $appName (Exit code: $($installProcess.ExitCode))" -LogPath $ExecutionLogPath
                        return @{ Success = $false; Method = 'Direct'; AppName = $appName; ErrorMessage = "Exit code: $($installProcess.ExitCode)" }
                    }
                }
                else {
                    Write-LogEntry -Level 'ERROR' -Component 'ESSENTIAL-APPS' -Message "Direct installation failed: No download URL provided for $appName" -LogPath $ExecutionLogPath
                    return @{ Success = $false; Method = 'Direct'; AppName = $appName; ErrorMessage = "No download URL provided" }
                }
            }
            
            default {
                Write-LogEntry -Level 'ERROR' -Component 'ESSENTIAL-APPS' -Message "Unknown installation source: $source for $appName" -LogPath $ExecutionLogPath
                return @{ Success = $false; Method = $source; AppName = $appName; ErrorMessage = "Unknown installation source: $source" }
            }
        }
    }
    catch {
        Write-LogEntry -Level 'ERROR' -Component 'ESSENTIAL-APPS' -Message "Installation exception for $appName`: $($_.Exception.Message)" -LogPath $ExecutionLogPath
        return @{ Success = $false; Method = $source; AppName = $appName; ErrorMessage = $_.Exception.Message }
    }
}

# Export module functions
Export-ModuleMember -Function @(
    # v3.0 Standardized execution function (Primary interface)
    'Invoke-EssentialApps'
    
    # Note: Legacy functions (Install-EssentialApplication, Get-AppNotInstalled, Get-InstallationStatistic) 
    # are used internally but not exported to maintain clean module interface
)
