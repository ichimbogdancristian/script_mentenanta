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

#region Privilege Validation
function Test-IsAdministrator {
    <#
    .SYNOPSIS
        Tests if the current PowerShell session is running with Administrator privileges
    .DESCRIPTION  
        Checks Windows identity and role to determine if current session has admin privileges.
        Required for Type2 modules that modify system settings, registry, or services.
    .RETURNS
        Boolean - True if running as administrator, False otherwise
    #>
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        Write-Warning "Failed to check administrator privileges: $_"
        return $false
    }
}

function Assert-AdministratorPrivileges {
    <#
    .SYNOPSIS
        Validates administrator privileges and throws descriptive error if not elevated
    .DESCRIPTION
        Checks for admin privileges and provides clear error message if missing.
        Should be called at the beginning of functions requiring elevation.
    .PARAMETER OperationName
        Name of the operation requiring admin privileges (for error message)
    #>
    param(
        [Parameter(Mandatory)]
        [string]$OperationName
    )
    
    if (-not (Test-IsAdministrator)) {
        $errorMessage = @"
$OperationName requires Administrator privileges.

SOLUTION:
1. Close this PowerShell session
2. Right-click script.bat and select "Run as administrator" 
3. Accept the UAC prompt when it appears
4. Re-run the maintenance script

The script launcher (script.bat) handles privilege elevation automatically,
but the PowerShell session must maintain elevated context.
"@
        throw $errorMessage
    }
}
#endregion


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
    
.PARAMETER ForceInstall
    Force installation even if apps are already installed
    
.PARAMETER DryRun
    Simulate installation without making changes
    
.PARAMETER ParallelInstalls
    Number of parallel installations to run (default: 3)
    
.EXAMPLE
    $results = Install-EssentialApplications -Categories @('Browsers', 'Productivity')
    
.EXAMPLE
    $results = Install-EssentialApplications -CustomApps @('VSCode', 'Git') -DryRun

.EXAMPLE
    $results = Install-EssentialApplications -ForceInstall
    # Forces installation even for apps that appear to be already installed
#>
function Install-EssentialApplications {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact='Medium')]
    param(
        [Parameter()]
        [string[]]$Categories = @('Browsers', 'Productivity', 'Media', 'Development'),
        
        [Parameter()]
        [string[]]$CustomApps = @(),
        
        [Parameter()]
        [switch]$ForceInstall,
        
        [Parameter()]
        [switch]$DryRun,
        
        [Parameter()]
        [ValidateRange(1, 8)]
        [int]$ParallelInstalls = 3
    )
    
    Write-Host "📦 Starting essential applications installation..." -ForegroundColor Cyan
    $startTime = Get-Date
    
    # Get essential apps from configuration
    $essentialApps = Get-UnifiedEssentialAppsList -IncludeCategories $Categories
    
    # Add custom apps if specified
    if ($CustomApps.Count -gt 0) {
        $customAppObjects = $CustomApps | ForEach-Object {
            @{
                Name = $_
                Category = 'Custom'
                Winget = $_
                Chocolatey = $_
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
            Skipped = 0
            Failed = 0
        }
    }
    
    Write-Host "  📋 Found $($essentialApps.Count) essential apps across $($Categories.Count) categories" -ForegroundColor Gray
    
    if ($DryRun) {
        Write-Host "  🧪 DRY RUN MODE - No installations will be performed" -ForegroundColor Magenta
    }
    
    # Apply conditional installation rules (e.g., LibreOffice only if MS Office not present)
    Write-Host "  🔍 Applying conditional installation rules..." -ForegroundColor Cyan
    $conditionallyFilteredApps = Get-ConditionallyFilteredApps -AppList $essentialApps
    
    # Filter out duplicates (default behavior, unless ForceInstall is specified)
    $appsToInstall = if ($ForceInstall) {
        Write-Host "  🔄 Force install mode - will attempt to install all apps regardless of current installation status" -ForegroundColor Yellow
        $conditionallyFilteredApps
    } else {
        Get-AppsNotInstalled -AppList $conditionallyFilteredApps
    }
    
    if ($appsToInstall.Count -eq 0) {
        Write-Host "  ✅ All essential apps are already installed" -ForegroundColor Green
        return @{
            TotalApps = $essentialApps.Count
            Installed = 0
            Skipped = $conditionallyFilteredApps.Count
            Failed = 0
            ConditionallyFiltered = $essentialApps.Count - $conditionallyFilteredApps.Count
            AlreadyInstalled = $true
        }
    }
    
    Write-Host "  🎯 Installing $($appsToInstall.Count) applications (skipped $($essentialApps.Count - $appsToInstall.Count) duplicates)" -ForegroundColor Gray
    
    # Initialize results tracking
    $results = @{
        TotalApps = $essentialApps.Count
        Installed = 0
        Skipped = $conditionallyFilteredApps.Count - $appsToInstall.Count
        ConditionallyFiltered = $essentialApps.Count - $conditionallyFilteredApps.Count
        Failed = 0
        Details = [List[PSCustomObject]]::new()
        ByCategory = @{}
        ByPackageManager = @{}
    }
    
    # Group apps by package manager preference for optimal installation
    $wingetApps = $appsToInstall | Where-Object { $_.Winget -and (Test-PackageManagerAvailable -Manager 'Winget') }
    $chocoApps = $appsToInstall | Where-Object { -not $_.Winget -and $_.Chocolatey -and (Test-PackageManagerAvailable -Manager 'Chocolatey') }
    $manualApps = $appsToInstall | Where-Object { -not $_.Winget -and -not $_.Chocolatey }
    
    # Install apps using preferred package managers
    if ($wingetApps.Count -gt 0) {
        Write-Host "  🔹 Installing $($wingetApps.Count) apps via Winget..." -ForegroundColor Blue
        $wingetResults = Install-AppsViaWinget -Apps $wingetApps -DryRun:$DryRun -ParallelCount $ParallelInstalls
        Merge-InstallationResults -Results $results -NewResults $wingetResults -PackageManager 'Winget'
    }
    
    if ($chocoApps.Count -gt 0) {
        Write-Host "  🍫 Installing $($chocoApps.Count) apps via Chocolatey..." -ForegroundColor Brown
        $chocoResults = Install-AppsViaChocolatey -Apps $chocoApps -DryRun:$DryRun -ParallelCount $ParallelInstalls
        Merge-InstallationResults -Results $results -NewResults $chocoResults -PackageManager 'Chocolatey'
    }
    
    if ($manualApps.Count -gt 0) {
        Write-Host "  ⚠️  $($manualApps.Count) apps require manual installation (no package manager available)" -ForegroundColor Yellow
        foreach ($app in $manualApps) {
            Write-Host "    📌 Manual installation needed: $($app.Name) - $($app.Description)" -ForegroundColor Gray
            $results.Details.Add([PSCustomObject]@{
                Name = $app.Name
                Category = $app.Category
                Status = 'Manual Required'
                PackageManager = 'None'
                Error = 'No supported package manager available'
            })
        }
        $results.Failed += $manualApps.Count
    }
    
    $duration = ((Get-Date) - $startTime).TotalSeconds
    
    # Summary output
    $statusIcon = if ($results.Failed -eq 0) { "✅" } else { "⚠️" }
    Write-Host "  $statusIcon Essential apps installation completed in $([math]::Round($duration, 2))s" -ForegroundColor Green
    Write-Host "    📊 Total: $($results.TotalApps), Installed: $($results.Installed), Skipped: $($results.Skipped), Conditionally Filtered: $($results.ConditionallyFiltered), Failed: $($results.Failed)" -ForegroundColor Gray
    
    if ($results.ConditionallyFiltered -gt 0) {
        Write-Host "    ℹ️  Conditionally filtered apps are skipped based on system state (e.g., LibreOffice skipped if MS Office present)" -ForegroundColor Cyan
    }
    
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
    param(
        [Parameter(Mandatory)]
        [Array]$AppList
    )
    
    # Get system inventory for duplicate detection
    $inventory = Get-SystemInventory -UseCache
    
    if (-not $inventory.InstalledApps) {
        Write-Warning "No system inventory available, cannot check for duplicates"
        return $AppList
    }
    
    # Build lookup table of installed apps
    $installedApps = [HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    
    foreach ($app in $inventory.InstalledApps) {
        if ($app.Name) { $installedApps.Add($app.Name) | Out-Null }
        if ($app.DisplayName) { $installedApps.Add($app.DisplayName) | Out-Null }
        if ($app.Id) { $installedApps.Add($app.Id) | Out-Null }
    }
    
    # Filter out already installed apps
    $notInstalled = @()
    foreach ($app in $AppList) {
        $isInstalled = $false
        
        # Check multiple identifiers
        $identifiersToCheck = @()
        if ($app.Name) { $identifiersToCheck += $app.Name }
        if ($app.Winget) { $identifiersToCheck += $app.Winget }
        if ($app.Chocolatey) { $identifiersToCheck += $app.Chocolatey }
        
        foreach ($identifier in $identifiersToCheck) {
            if ($installedApps.Contains($identifier) -or 
                ($installedApps | Where-Object { $_ -like "*$identifier*" }).Count -gt 0) {
                $isInstalled = $true
                break
            }
        }
        
        if (-not $isInstalled) {
            $notInstalled += $app
        }
    }
    
    return $notInstalled
}

<#
.SYNOPSIS
    Checks if Microsoft Office is installed on the system
    
.DESCRIPTION
    Scans the system for various versions and distributions of Microsoft Office
    including Office 365, Office 2016, 2019, 2021, and standalone applications.
    
.EXAMPLE
    $hasMSOffice = Test-MicrosoftOfficeInstalled
#>
function Test-MicrosoftOfficeInstalled {
    [CmdletBinding()]
    param()
    
    Write-Verbose "Checking for Microsoft Office installation..."
    
    # Get system inventory for Office detection
    $inventory = Get-SystemInventory -UseCache
    
    if (-not $inventory.InstalledApps) {
        Write-Warning "No system inventory available for Office detection"
        return $false
    }
    
    # Microsoft Office identifiers to check for
    $officeIdentifiers = @(
        # Office Suites
        "Microsoft Office", "Office 365", "Microsoft 365", 
        "Office Professional", "Office Home", "Office Standard",
        "Office 2016", "Office 2019", "Office 2021", "Office 2024",
        
        # Individual Office Apps
        "Microsoft Word", "Microsoft Excel", "Microsoft PowerPoint",
        "Microsoft Outlook", "Microsoft Access", "Microsoft Publisher",
        "Microsoft OneNote", "Microsoft Project", "Microsoft Visio",
        
        # Package identifiers
        "Microsoft.Office", "Microsoft.OfficeHome", "Microsoft.OfficeProfessional",
        "Microsoft.Office365ProPlus", "Microsoft.Office365Business"
    )
    
    # Check installed applications
    foreach ($app in $inventory.InstalledApps) {
        if ($app.Name -or $app.DisplayName -or $app.Id) {
            $appIdentifiers = @($app.Name, $app.DisplayName, $app.Id) | Where-Object { $_ }
            
            foreach ($appId in $appIdentifiers) {
                foreach ($officeId in $officeIdentifiers) {
                    if ($appId -like "*$officeId*") {
                        Write-Verbose "Found Microsoft Office: $appId"
                        return $true
                    }
                }
            }
        }
    }
    
    Write-Verbose "Microsoft Office not detected on system"
    return $false
}

<#
.SYNOPSIS
    Filters apps based on conditional installation rules
    
.DESCRIPTION
    Processes the app list and removes apps that have conditional installation
    rules that are not met (e.g., LibreOffice when Microsoft Office is present).
    
.PARAMETER AppList
    Array of applications to filter
    
.EXAMPLE
    $filteredApps = Get-ConditionallyFilteredApps -AppList $apps
#>
function Get-ConditionallyFilteredApps {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [Array]$AppList
    )
    
    $filteredApps = @()
    $skippedApps = 0
    
    foreach ($app in $AppList) {
        $shouldInstall = $true
        
        # Check if app has conditional installation rules
        if ($app.conditional -eq $true -and $app.condition) {
            switch ($app.condition) {
                "not_has_msoffice" {
                    $hasMSOffice = Test-MicrosoftOfficeInstalled
                    if ($hasMSOffice) {
                        Write-Host "  🔄 Skipping $($app.name) - Microsoft Office is already installed" -ForegroundColor Yellow
                        $shouldInstall = $false
                        $skippedApps++
                    } else {
                        Write-Host "  ✅ Including $($app.name) - Microsoft Office not detected" -ForegroundColor Green
                    }
                }
                default {
                    Write-Warning "Unknown conditional installation rule: $($app.condition)"
                }
            }
        }
        
        if ($shouldInstall) {
            $filteredApps += $app
        }
    }
    
    if ($skippedApps -gt 0) {
        Write-Host "  📊 Filtered out $skippedApps app(s) based on conditional installation rules" -ForegroundColor Gray
    }
    
    return $filteredApps
}

#endregion

#region Winget Installation

<#
.SYNOPSIS
    Installs applications using Winget package manager
#>
function Install-AppsViaWinget {
    [CmdletBinding()]
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
        Failed = 0
        Details = [List[PSCustomObject]]::new()
    }
    
    if (-not (Test-PackageManagerAvailable -Manager 'Winget')) {
        Write-Warning "Winget not available"
        $results.Failed = $Apps.Count
        return $results
    }
    
    # Process apps in batches to avoid overwhelming the system
    $batches = Split-ArrayIntoBatches -Array $Apps -BatchSize $ParallelCount
    
    foreach ($batch in $batches) {
        $batch | ForEach-Object -ThrottleLimit $ParallelCount -Parallel {
            $app = $_
            $isDryRun = $using:DryRun
            
            $result = @{
                Name = $app.Name
                Category = $app.Category
                PackageId = $app.Winget
                Status = 'Unknown'
                PackageManager = 'Winget'
                Error = $null
            }
            
            try {
                if ($isDryRun) {
                    Write-Host "    [DRY RUN] Would install: $($app.Name) ($($app.Winget))" -ForegroundColor DarkYellow
                    $result.Status = 'Simulated'
                } else {
                    Write-Host "    📦 Installing: $($app.Name)..." -ForegroundColor Blue
                    
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
                        Write-Host "      ✅ Successfully installed: $($app.Name)" -ForegroundColor Green
                    } else {
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
            } else {
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
#>
function Install-AppsViaChocolatey {
    [CmdletBinding()]
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
        Failed = 0
        Details = [List[PSCustomObject]]::new()
    }
    
    if (-not (Test-PackageManagerAvailable -Manager 'Chocolatey')) {
        Write-Warning "Chocolatey not available"
        $results.Failed = $Apps.Count
        return $results
    }
    
    foreach ($app in $Apps) {
        $result = @{
            Name = $app.Name
            Category = $app.Category
            PackageId = $app.Chocolatey
            Status = 'Unknown'
            PackageManager = 'Chocolatey'
            Error = $null
        }
        
        try {
            if ($DryRun) {
                Write-Host "    [DRY RUN] Would install: $($app.Name) ($($app.Chocolatey))" -ForegroundColor DarkYellow
                $result.Status = 'Simulated'
            } else {
                Write-Host "    🍫 Installing: $($app.Name)..." -ForegroundColor Brown
                
                $chocoArgs = @(
                    'install',
                    $app.Chocolatey,
                    '-y',
                    '--limit-output'
                )
                
                $process = Start-Process -FilePath 'choco' -ArgumentList $chocoArgs -Wait -PassThru -NoNewWindow
                
                if ($process.ExitCode -eq 0) {
                    $result.Status = 'Installed'
                    Write-Host "      ✅ Successfully installed: $($app.Name)" -ForegroundColor Green
                } else {
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
#>
function Test-PackageManagerAvailable {
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
#>
function Split-ArrayIntoBatches {
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
#>
function Merge-InstallationResults {
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
        } else {
            $Results.ByCategory[$detail.Category].Failed++
        }
    }
}

<#
.SYNOPSIS
    Gets installation statistics and summary
#>
function Get-InstallationStatistics {
    param([hashtable]$Results)
    
    return @{
        TotalProcessed = $Results.TotalApps
        SuccessRate = if ($Results.TotalApps -gt 0) { 
            [math]::Round(($Results.Installed / $Results.TotalApps) * 100, 1) 
        } else { 0 }
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
    'Install-EssentialApplications',
    'Get-AppsNotInstalled',
    'Get-InstallationStatistics',
    'Test-MicrosoftOfficeInstalled',
    'Get-ConditionallyFilteredApps'
)
