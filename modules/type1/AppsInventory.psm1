<#
.MODULEINFO
Type = "Type1"
Category = "Apps"
DataFile = "apps-inventory.json"
ScanInterval = 3600
Description = "Scans and inventories all installed applications (AppX, MSI, Win32)"
#>

<#
.SYNOPSIS
    Apps inventory module for Windows Maintenance Automation v3.0

.DESCRIPTION
    Type1 module that scans and inventories all installed applications including:
    - AppX packages (Windows Store apps)
    - MSI-installed applications
    - Win32 applications from registry
    Detects bloatware and marks applications accordingly.

.NOTES
    Author: Windows Maintenance Automation Project
    Version: 3.0.0
    Module Type: Type1 (Inventory/Read-only)
    Requires: PowerShell 7.0+, Infrastructure.psm1
#>

#Requires -Version 7.0

<#
.SYNOPSIS
    Gets complete inventory of installed applications.

.DESCRIPTION
    Scans all AppX packages, MSI applications, and Win32 applications.
    Marks bloatware apps and saves inventory to apps-inventory.json.

.PARAMETER UseCache
    If specified and cache is valid, returns cached inventory instead of re-scanning.

.OUTPUTS
    Hashtable with complete apps inventory data.

.EXAMPLE
    $inventory = Get-AppsInventory
    $inventory = Get-AppsInventory -UseCache
#>
function Get-AppsInventory {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $false)]
        [switch]$UseCache
    )
    
    $perf = Start-PerformanceTracking -OperationName 'AppsInventory' -Component 'Apps'
    
    try {
        Write-DetailedLog -Level 'INFO' -Component 'Apps' -Message 'Starting applications inventory scan'
        
        # Check cache if requested
        if ($UseCache) {
            $cached = Import-InventoryFile -Category 'Apps'
            if ($cached -and $cached._metadata) {
                $cacheAge = (Get-Date) - [datetime]$cached._metadata.timestamp
                $maxAge = Get-ConfigValue 'inventory.cacheExpirationMinutes' -Default 60
                
                if ($cacheAge.TotalMinutes -lt $maxAge) {
                    Write-DetailedLog -Level 'INFO' -Component 'Apps' -Message "Using cached inventory (age: $([math]::Round($cacheAge.TotalMinutes, 1)) minutes)"
                    Complete-PerformanceTracking -PerformanceContext $perf -Success $true
                    return $cached
                }
            }
        }
        
        # Scan AppX packages
        Write-DetailedLog -Level 'INFO' -Component 'Apps' -Message 'Scanning AppX packages...'
        $appxPackages = Get-InstalledAppxPackages
        
        # Scan MSI applications
        Write-DetailedLog -Level 'INFO' -Component 'Apps' -Message 'Scanning MSI applications...'
        $msiApps = Get-InstalledMSIPackages
        
        # Scan Win32 applications
        Write-DetailedLog -Level 'INFO' -Component 'Apps' -Message 'Scanning Win32 applications...'
        $win32Apps = Get-InstalledWin32Apps
        
        # Load bloatware list for detection
        $bloatwarePatterns = Get-BloatwarePatterns
        
        # Mark bloatware in AppX packages
        foreach ($app in $appxPackages) {
            $app.isBloatware = Test-BloatwareMatch -AppName $app.Name -Patterns $bloatwarePatterns
        }
        
        # Build complete inventory
        $inventory = @{
            appxPackages = $appxPackages
            msiPackages  = $msiApps
            win32Apps    = $win32Apps
            statistics   = @{
                totalAppX         = $appxPackages.Count
                totalMSI          = $msiApps.Count
                totalWin32        = $win32Apps.Count
                totalApps         = $appxPackages.Count + $msiApps.Count + $win32Apps.Count
                bloatwareDetected = ($appxPackages | Where-Object { $_.isBloatware }).Count
                essentialMissing  = 0  # To be calculated by EssentialApps module
            }
            history      = @()  # Will store change history
        }
        
        # Save inventory
        Save-InventoryFile -Category 'Apps' -Data $inventory
        
        Write-DetailedLog -Level 'SUCCESS' -Component 'Apps' -Message "Inventory complete: $($inventory.statistics.totalApps) applications found ($($inventory.statistics.bloatwareDetected) bloatware)"
        
        Complete-PerformanceTracking -PerformanceContext $perf -Success $true -ResultData $inventory.statistics
        
        return $inventory
    }
    catch {
        Write-DetailedLog -Level 'ERROR' -Component 'Apps' -Message "Inventory scan failed: $_" -Exception $_
        Complete-PerformanceTracking -PerformanceContext $perf -Success $false
        return $null
    }
}

<#
.SYNOPSIS
    Gets all installed AppX packages.

.DESCRIPTION
    Scans all AppX packages for all users and extracts key information.

.OUTPUTS
    Array of AppX package hashtables.
#>
function Get-InstalledAppxPackages {
    [CmdletBinding()]
    [OutputType([array])]
    param()
    
    try {
        # Try to get AppX packages - may fail on Windows Server or modified editions
        $packages = Get-AppxPackage -AllUsers -ErrorAction Stop
        
        $results = @()
        foreach ($pkg in $packages) {
            $results += @{
                Name              = $pkg.Name
                PackageFullName   = $pkg.PackageFullName
                Version           = $pkg.Version.ToString()
                Publisher         = $pkg.Publisher
                InstallLocation   = $pkg.InstallLocation
                IsFramework       = $pkg.IsFramework
                IsResourcePackage = $pkg.IsResourcePackage
                Type              = 'AppX'
                isBloatware       = $false  # Will be set later
            }
        }
        
        Write-Verbose "Found $($results.Count) AppX packages"
        return $results
    }
    catch [System.PlatformNotSupportedException] {
        # Platform doesn't support AppX (e.g., Windows Server or modified editions)
        Write-DetailedLog -Level 'INFO' -Component 'Apps' -Message "AppX packages not supported on this platform (Windows Server or modified edition) - skipping AppX scan"
        Write-Verbose "AppX platform not supported - this is normal on Windows Server editions"
        return @()
    }
    catch {
        # Check if it's the specific platform error code 0x80131539
        if ($_.Exception.HResult -eq 0x80131539 -or $_.Exception.Message -match '0x80131539') {
            Write-DetailedLog -Level 'INFO' -Component 'Apps' -Message "AppX subsystem not available on this Windows edition - skipping AppX scan"
            Write-Verbose "AppX not available (error 0x80131539) - skipping AppX package inventory"
            return @()
        }
        
        # Other errors - log as warning
        Write-DetailedLog -Level 'WARNING' -Component 'Apps' -Message "Failed to scan AppX packages: $_"
        Write-Verbose "AppX scan error: $($_.Exception.Message)"
        return @()
    }
}

<#
.SYNOPSIS
    Gets all MSI-installed applications from registry.

.DESCRIPTION
    Queries both 32-bit and 64-bit registry uninstall keys for MSI applications.

.OUTPUTS
    Array of MSI application hashtables.
#>
function Get-InstalledMSIPackages {
    [CmdletBinding()]
    [OutputType([array])]
    param()
    
    try {
        $results = @()
        
        # 64-bit applications
        $uninstallPath64 = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
        $apps64 = Get-ItemProperty $uninstallPath64 -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -and $_.UninstallString -match 'msiexec' } |
        Select-Object DisplayName, DisplayVersion, Publisher, InstallDate, InstallLocation, UninstallString
        
        foreach ($app in $apps64) {
            $results += @{
                Name            = $app.DisplayName
                Version         = $app.DisplayVersion
                Publisher       = $app.Publisher
                InstallDate     = $app.InstallDate
                InstallLocation = $app.InstallLocation
                UninstallString = $app.UninstallString
                Architecture    = 'x64'
                Type            = 'MSI'
            }
        }
        
        # 32-bit applications on 64-bit Windows
        if ([Environment]::Is64BitOperatingSystem) {
            $uninstallPath32 = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
            $apps32 = Get-ItemProperty $uninstallPath32 -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -and $_.UninstallString -match 'msiexec' } |
            Select-Object DisplayName, DisplayVersion, Publisher, InstallDate, InstallLocation, UninstallString
            
            foreach ($app in $apps32) {
                $results += @{
                    Name            = $app.DisplayName
                    Version         = $app.DisplayVersion
                    Publisher       = $app.Publisher
                    InstallDate     = $app.InstallDate
                    InstallLocation = $app.InstallLocation
                    UninstallString = $app.UninstallString
                    Architecture    = 'x86'
                    Type            = 'MSI'
                }
            }
        }
        
        Write-Verbose "Found $($results.Count) MSI applications"
        Register-RegistryOperation -Operation 'READ' -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall' -Component 'Apps'
        
        return $results
    }
    catch {
        Write-DetailedLog -Level 'WARNING' -Component 'Apps' -Message "Failed to scan MSI applications: $_"
        return @()
    }
}

<#
.SYNOPSIS
    Gets all Win32 applications from registry.

.DESCRIPTION
    Queries registry uninstall keys for Win32 applications (non-MSI installers).

.OUTPUTS
    Array of Win32 application hashtables.
#>
function Get-InstalledWin32Apps {
    [CmdletBinding()]
    [OutputType([array])]
    param()
    
    try {
        $results = @()
        
        # 64-bit applications
        $uninstallPath64 = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
        $apps64 = Get-ItemProperty $uninstallPath64 -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -and $_.UninstallString -and $_.UninstallString -notmatch 'msiexec' } |
        Select-Object DisplayName, DisplayVersion, Publisher, InstallDate, InstallLocation, UninstallString
        
        foreach ($app in $apps64) {
            $results += @{
                Name            = $app.DisplayName
                Version         = $app.DisplayVersion
                Publisher       = $app.Publisher
                InstallDate     = $app.InstallDate
                InstallLocation = $app.InstallLocation
                UninstallString = $app.UninstallString
                Architecture    = 'x64'
                Type            = 'Win32'
            }
        }
        
        # 32-bit applications on 64-bit Windows
        if ([Environment]::Is64BitOperatingSystem) {
            $uninstallPath32 = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
            $apps32 = Get-ItemProperty $uninstallPath32 -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -and $_.UninstallString -and $_.UninstallString -notmatch 'msiexec' } |
            Select-Object DisplayName, DisplayVersion, Publisher, InstallDate, InstallLocation, UninstallString
            
            foreach ($app in $apps32) {
                $results += @{
                    Name            = $app.DisplayName
                    Version         = $app.DisplayVersion
                    Publisher       = $app.Publisher
                    InstallDate     = $app.InstallDate
                    InstallLocation = $app.InstallLocation
                    UninstallString = $app.UninstallString
                    Architecture    = 'x86'
                    Type            = 'Win32'
                }
            }
        }
        
        Write-Verbose "Found $($results.Count) Win32 applications"
        return $results
    }
    catch {
        Write-DetailedLog -Level 'WARNING' -Component 'Apps' -Message "Failed to scan Win32 applications: $_"
        return @()
    }
}

<#
.SYNOPSIS
    Gets bloatware patterns from configuration.

.DESCRIPTION
    Loads bloatware-list.json and returns array of patterns for matching.

.OUTPUTS
    Array of bloatware pattern strings.
#>
function Get-BloatwarePatterns {
    [CmdletBinding()]
    [OutputType([array])]
    param()
    
    try {
        $context = Get-InfrastructureContext
        if (-not $context) {
            Write-Warning "Infrastructure not initialized"
            return @()
        }
        
        $configPath = Join-Path $context.ScriptRoot "config\bloatware-list.json"
        
        if (-not (Test-Path $configPath)) {
            Write-DetailedLog -Level 'WARNING' -Component 'Apps' -Message "Bloatware list not found at $configPath"
            return @()
        }
        
        $bloatwareConfig = Get-Content $configPath -Raw | ConvertFrom-Json
        
        $patterns = @()
        if ($bloatwareConfig.appxPackages) {
            $patterns += $bloatwareConfig.appxPackages.packageName
        }
        
        Register-FileOperation -Operation 'READ' -Path $configPath -Component 'Apps'
        Write-Verbose "Loaded $($patterns.Count) bloatware patterns"
        
        return $patterns
    }
    catch {
        Write-DetailedLog -Level 'WARNING' -Component 'Apps' -Message "Failed to load bloatware patterns: $_"
        return @()
    }
}

<#
.SYNOPSIS
    Tests if an app name matches bloatware patterns.

.DESCRIPTION
    Checks app name against bloatware patterns using wildcard matching.

.PARAMETER AppName
    Application name to test.

.PARAMETER Patterns
    Array of bloatware patterns.

.OUTPUTS
    Boolean indicating if app is bloatware.

.EXAMPLE
    $isBloat = Test-BloatwareMatch -AppName 'Microsoft.BingWeather' -Patterns $patterns
#>
function Test-BloatwareMatch {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$AppName,
        
        [Parameter(Mandatory = $false)]
        [array]$Patterns = @()
    )
    
    foreach ($pattern in $Patterns) {
        if ($AppName -like $pattern) {
            return $true
        }
    }
    
    return $false
}

# Export public functions
Export-ModuleMember -Function @(
    'Get-AppsInventory',
    'Test-BloatwareMatch'
)
