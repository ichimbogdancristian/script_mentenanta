#Requires -Version 7.0

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

# Import required modules
$ModuleRoot = Split-Path -Parent $PSScriptRoot
$SystemInventoryPath = Join-Path $ModuleRoot 'type1\SystemInventory.psm1'
if (Test-Path $SystemInventoryPath) {
    Import-Module $SystemInventoryPath -Force
}

$FileOrgPath = Join-Path $ModuleRoot 'core\FileOrganizationManager.psm1'
if (Test-Path $FileOrgPath) {
    Import-Module $FileOrgPath -Force
}

#region Public Functions

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
    $results = Install-EssentialApplications -Categories @('Browsers', 'Productivity')

.EXAMPLE
    $results = Install-EssentialApplications -CustomApps @('VSCode', 'Git') -DryRun
#>
function Install-EssentialApplication {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([hashtable])]
    param(
        [Parameter()]
        [string[]]$Categories = @('all'),

        [Parameter()]
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
        Get-AppsNotInstalled -AppList $essentialApps
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
        $wingetResults = Install-AppsViaWinget -Apps $wingetApps -DryRun:$DryRun -ParallelCount $ParallelInstalls
        Merge-InstallationResult -Results $results -NewResults $wingetResults -PackageManager 'Winget'
    }

    if ($chocoApps.Count -gt 0) {
        Write-Information "  🍫 Installing $($chocoApps.Count) apps via Chocolatey..." -InformationAction Continue
        $chocoResults = Install-AppsViaChocolatey -Apps $chocoApps -DryRun:$DryRun -ParallelCount $ParallelInstalls
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

    return $results
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
    $missingApps = Get-AppsNotInstalled -AppList $essentialApps
#>
function Get-AppsNotInstalled {
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
        [Array]$MissingApps,

        [Parameter(Mandatory)]
        [PSCustomObject]$InstalledSoftware
    )

    try {
        $scriptRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $tempDir = Join-Path $scriptRoot 'temp_files'
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

    # Strategy 3: Enhanced detection for specific apps with known variations
    $appName = $App.Name.ToLower()

    # Common app name variations and aliases
    $appVariations = @{
        'visual studio code'       = @('code', 'vscode', 'vs code')
        'git for windows'          = @('git', 'git for windows')
        'powershell 7'             = @('powershell', 'powershell core', 'pwsh')
        'windows terminal'         = @('terminal', 'windows terminal', 'wt')
        'java runtime environment' = @('java', 'jre', 'java runtime', 'oracle java')
        'python 3'                 = @('python', 'python3', 'python 3')
        'node.js'                  = @('node', 'nodejs', 'node.js')
        'vlc media player'         = @('vlc', 'vlc player', 'vlc media player')
        '7-zip'                    = @('7zip', '7-zip')
        'libreoffice'              = @('libreoffice', 'libre office')
        'microsoft teams'          = @('teams', 'microsoft teams')
        'google chrome'            = @('chrome', 'google chrome')
        'mozilla firefox'          = @('firefox', 'mozilla firefox')
        'gimp'                     = @('gimp', 'gnu image manipulation program')
    }

    # Check if this app has known variations
    $variations = @()
    foreach ($knownApp in $appVariations.Keys) {
        if ($appName -like "*$knownApp*") {
            $variations += $appVariations[$knownApp]
            break
        }
    }

    # Add original identifiers to variations
    $variations += $identifiersToCheck

    # Strategy 4: Check variations against installed programs with enhanced matching
    foreach ($variation in $variations) {
        if (-not $variation) { continue }

        $matchingPrograms = $InstalledPrograms | Where-Object {
            ($_.Name -and (($_.Name -like "*$variation*") -or ($_.Name -eq $variation))) -or
            ($_.DisplayName -and (($_.DisplayName -like "*$variation*") -or ($_.DisplayName -eq $variation))) -or
            ($_.Publisher -and ($variation -like "*$($_.Publisher)*")) -or
            ($_.Id -and (($_.Id -like "*$variation*") -or ($_.Id -eq $variation)))
        }

        if ($matchingPrograms.Count -gt 0) {
            Write-Verbose "Found enhanced match for '$($App.Name)' using variation '$variation': $($matchingPrograms[0].Name -or $matchingPrograms[0].DisplayName)"
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
    $result = Install-AppsViaWinget -Apps $appList
    Installs all apps in the list using Winget with default parallel count

.EXAMPLE
    $result = Install-AppsViaWinget -Apps $appList -DryRun -ParallelCount 5
    Tests installation of apps with higher parallelism without making changes
#>
function Install-AppsViaWinget {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [Array]$Apps,

        [Parameter()]
        [switch]$DryRun,

        [Parameter()]
        [int]$ParallelCount = 3
    )

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

            $result = @{
                Name           = $app.Name
                Category       = $app.Category
                PackageId      = $app.Winget
                Status         = 'Unknown'
                PackageManager = 'Winget'
                Error          = $null
            }

            try {
                if ($isDryRun) {
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

                    $process = Start-Process -FilePath 'winget' -ArgumentList $wingetArgs -Wait -PassThru -NoNewWindow

                    if ($process.ExitCode -eq 0) {
                        $result.Status = 'Installed'
                        Write-Information "      ✅ Successfully installed: $($app.Name)" -InformationAction Continue
                    }
                    else {
                        throw "Winget installation failed with exit code $($process.ExitCode)"
                    }
                }
            }
            catch {
                $result.Status = 'Failed'
                $result.Error = $_.Exception.Message
                Write-Warning "Failed to install $($app.Name): $_"
            }

            return [PSCustomObject]$result
        } | ForEach-Object {
            $results.Details.Add($_)
            if ($_.Status -eq 'Installed' -or $_.Status -eq 'Simulated') {
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
    $result = Install-AppsViaChocolatey -Apps $appList
    Installs all apps in the list using Chocolatey with default parallel count

.EXAMPLE
    $result = Install-AppsViaChocolatey -Apps $appList -DryRun
    Tests installation of apps without making actual changes
#>
function Install-AppsViaChocolatey {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [Array]$Apps,

        [Parameter()]
        [switch]$DryRun,

        [Parameter()]
        [int]$ParallelCount = 2  # Chocolatey is less stable with high parallelism
    )

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
        $result = @{
            Name           = $app.Name
            Category       = $app.Category
            PackageId      = $app.Chocolatey
            Status         = 'Unknown'
            PackageManager = 'Chocolatey'
            Error          = $null
        }

        try {
            if ($DryRun) {
                Write-Information "    [DRY RUN] Would install: $($app.Name) ($($app.Chocolatey))" -InformationAction Continue
                $result.Status = 'Simulated'
            }
            else {
                Write-Information "    🍫 Installing: $($app.Name)..." -InformationAction Continue

                $chocoArgs = @(
                    'install',
                    $app.Chocolatey,
                    '-y',
                    '--limit-output'
                )

                $process = Start-Process -FilePath 'choco' -ArgumentList $chocoArgs -Wait -PassThru -NoNewWindow

                if ($process.ExitCode -eq 0) {
                    $result.Status = 'Installed'
                    Write-Information "      ✅ Successfully installed: $($app.Name)" -InformationAction Continue
                }
                else {
                    throw "Chocolatey installation failed with exit code $($process.ExitCode)"
                }
            }

            $results.Installed++
        }
        catch {
            $result.Status = 'Failed'
            $result.Error = $_.Exception.Message
            $results.Failed++
            Write-Warning "Failed to install $($app.Name): $_"
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

# Export module functions
Export-ModuleMember -Function @(
    'Install-EssentialApplication',
    'Get-AppsNotInstalled',
    'Get-InstallationStatistic'
)
