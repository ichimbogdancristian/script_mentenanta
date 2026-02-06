#Requires -Version 7.0
# Module Dependencies:
#   - CoreInfrastructure.psm1 (for logging and configuration)

<#
.SYNOPSIS
    Application Upgrade Audit Module - Type 1 (Inventory/Reporting)

.DESCRIPTION
    Detects available application upgrades across multiple package managers.
    Identifies outdated software through winget and Chocolatey package manager queries.

.NOTES
    Module Type: Type 1 (Inventory/Reporting)
    Dependencies: winget, chocolatey (optional)
    Author: Windows Maintenance Automation Project
    Version: 1.0.0
#>

using namespace System.Collections.Generic

# v3.0 Type 1 module - imported by Type 2 modules
# Note: CoreInfrastructure should be loaded by the Type 2 module before importing this module
if (Get-Command 'Write-LogEntry' -ErrorAction SilentlyContinue) {
    Write-Verbose "CoreInfrastructure functions detected - logging available"
}
else {
    Write-Verbose "CoreInfrastructure global import in progress"
}

#region Public Functions

<#
.SYNOPSIS
    Analyzes system for available application upgrades

.DESCRIPTION
    Scans winget and Chocolatey package managers to identify applications
    with available updates. Returns structured data for upgrade execution.

.PARAMETER Config
    Configuration hashtable from main-config.json

.EXAMPLE
    $upgrades = Get-AppUpgradeAnalysis -Config $MainConfig

.OUTPUTS
    Array of hashtables with upgrade information:
    @{
        Name = 'Application Name'
        Id = 'Publisher.AppName' (for winget)
        CurrentVersion = '1.0.0'
        AvailableVersion = '2.0.0'
        Source = 'Winget' or 'Chocolatey'
        UpdateSize = '125 MB' (if available)
    }
#>
function Get-AppUpgradeAnalysis {
    [CmdletBinding()]
    [OutputType([Array])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config
    )

    Write-Information " Analyzing available application upgrades..." -InformationAction Continue
    $startTime = Get-Date

    # Start performance tracking
    $perfContext = $null
    try {
        $perfContext = Start-PerformanceTracking -OperationName 'AppUpgradeAudit' -Component 'APP-UPGRADE-AUDIT'
        Write-LogEntry -Level 'INFO' -Component 'APP-UPGRADE-AUDIT' -Message 'Starting application upgrade analysis'
    }
    catch {
        # CoreInfrastructure not available, continue
        Write-Verbose "Logging not available - continuing with analysis"
    }

    try {
        # Initialize results collection
        $allUpgrades = [List[PSCustomObject]]::new()

        # Scan winget for upgrades
        Write-Information "   Scanning winget for upgrades..." -InformationAction Continue
        $wingetUpgrades = Get-WingetUpgrades
        if ($wingetUpgrades -and $wingetUpgrades.Count -gt 0) {
            foreach ($item in $wingetUpgrades) {
                if ($null -ne $item) { $allUpgrades.Add($item) }
            }
            Write-Information "     Found $($wingetUpgrades.Count) winget upgrades" -InformationAction Continue
        }
        else {
            Write-Information "    ℹ  No winget upgrades available" -InformationAction Continue
        }

        # Scan Chocolatey for upgrades
        Write-Information "   Scanning Chocolatey for upgrades..." -InformationAction Continue
        $chocoUpgrades = Get-ChocolateyUpgrades
        if ($chocoUpgrades -and $chocoUpgrades.Count -gt 0) {
            foreach ($item in $chocoUpgrades) {
                if ($null -ne $item) { $allUpgrades.Add($item) }
            }
            Write-Information "     Found $($chocoUpgrades.Count) Chocolatey upgrades" -InformationAction Continue
        }
        else {
            Write-Information "    ℹ  No Chocolatey upgrades available" -InformationAction Continue
        }

        $duration = (Get-Date) - $startTime
        Write-Information "   Found $($allUpgrades.Count) total upgrades in $([math]::Round($duration.TotalSeconds, 2))s" -InformationAction Continue

        # Convert to array for return
        $resultArray = [Array]$allUpgrades

        # Complete performance tracking
        try {
            if ($perfContext) {
                Complete-PerformanceTracking -PerformanceContext $perfContext -Success $true
            }
            Write-LogEntry -Level 'SUCCESS' -Component 'APP-UPGRADE-AUDIT' -Message 'Application upgrade analysis completed' -Data @{
                UpgradesFound = $resultArray.Count
                ExecutionTime = [math]::Round($duration.TotalSeconds, 2)
            }
        }
        catch {
            Write-Verbose "APP-UPGRADE-AUDIT: Logging completion failed - $_"
            # Logging not available, continue
        }

        return $resultArray
    }
    catch {
        try {
            if ($perfContext) {
                Complete-PerformanceTracking -PerformanceContext $perfContext -Success $false
            }
            Write-LogEntry -Level 'ERROR' -Component 'APP-UPGRADE-AUDIT' -Message 'Application upgrade analysis failed' -Data @{
                Error = $_.Exception.Message
            }
        }
        catch {
            Write-Verbose "APP-UPGRADE-AUDIT: Logging cleanup failed - $_"
            # Logging not available, continue
        }

        Write-Error "Failed to analyze upgrades: $_"
        return @()
    }
}

#endregion

#region Winget Upgrade Detection

<#
.SYNOPSIS
    Detects available winget package upgrades
#>
function Get-WingetUpgrades {
    [CmdletBinding()]
    [OutputType([Array])]
    param()

    try {
        # Check if winget is available
        if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
            Write-Verbose "Winget not available - skipping winget upgrade detection"
            return @()
        }

        $upgrades = @()

        # Run winget upgrade with --include-unknown flag
        # Format: Name | Id | Version | Available | Source
        $wingetOutput = winget upgrade --include-unknown 2>&1 | Out-String

        if ([string]::IsNullOrWhiteSpace($wingetOutput)) {
            Write-Verbose "No output from winget upgrade command"
            return @()
        }

        # Parse winget output (skip header lines and separator lines)
        $lines = $wingetOutput -split "`n"
        $dataStarted = $false

        foreach ($line in $lines) {
            # Skip null or whitespace lines
            if ($null -eq $line -or [string]::IsNullOrWhiteSpace($line)) {
                continue
            }

            $lineTrimmed = $line.Trim()

            # Skip header and separator lines
            if ($lineTrimmed -match '^Name' -or $lineTrimmed -match '^-+' -or $lineTrimmed.Length -lt 10) {
                $dataStarted = $true
                continue
            }

            # Skip informational lines
            if ($lineTrimmed -match 'upgrades available' -or $lineTrimmed -match 'winget upgrade' -or $lineTrimmed -match 'The following') {
                continue
            }

            # Parse data lines (after header started)
            if ($dataStarted) {
                # Try to parse the line (format varies, be flexible)
                # Typical format: "AppName  PublisherId  1.0.0  2.0.0  winget"
                $parts = $lineTrimmed -split '\s{2,}'  # Split on 2+ spaces

                if ($parts.Count -ge 4) {
                    $appName = $parts[0].Trim()
                    $appId = $parts[1].Trim()
                    $currentVersion = $parts[2].Trim()
                    $availableVersion = $parts[3].Trim()
                    $source = if ($parts.Count -ge 5) { $parts[4].Trim() } else { 'winget' }

                    # Skip if versions are same or invalid
                    if ($currentVersion -eq $availableVersion -or $currentVersion -eq '') {
                        continue
                    }

                    $upgradeItem = [PSCustomObject]@{
                        Name             = $appName
                        Id               = $appId
                        CurrentVersion   = $currentVersion
                        AvailableVersion = $availableVersion
                        Source           = 'Winget'
                        SourceDetail     = $source
                        UpdateSize       = 'Unknown'
                    }

                    # Log detected upgrade opportunity
                    Write-DetectionLog -Operation 'Detect' -Target $appName -Component 'APP-UPGRADE-WINGET' -AdditionalInfo @{
                        ApplicationId    = $appId
                        CurrentVersion   = $currentVersion
                        AvailableVersion = $availableVersion
                        Source           = 'Winget'
                        SourceDetail     = $source
                        Status           = 'Upgrade Available'
                        UpgradeCommand   = "winget upgrade --id $appId"
                        Reason           = "Newer version available: $currentVersion → $availableVersion"
                    }

                    $upgrades += $upgradeItem
                }
            }
        }

        return $upgrades
    }
    catch {
        Write-Verbose "Error detecting winget upgrades: $($_.Exception.Message)"
        return @()
    }
}

#endregion

#region Chocolatey Upgrade Detection

<#
.SYNOPSIS
    Detects available Chocolatey package upgrades
#>
function Get-ChocolateyUpgrades {
    [CmdletBinding()]
    [OutputType([Array])]
    param()

    try {
        # Check if choco is available
        if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
            Write-Verbose "Chocolatey not available - skipping choco upgrade detection"
            return @()
        }

        $upgrades = @()

        # Run choco outdated with limit-output for easier parsing
        # Format: PackageName|CurrentVersion|AvailableVersion|Pinned
        $chocoOutput = choco outdated --limit-output 2>&1 | Out-String

        if ([string]::IsNullOrWhiteSpace($chocoOutput)) {
            Write-Verbose "No outdated packages from Chocolatey"
            return @()
        }

        # Parse choco output (pipe-delimited)
        $lines = $chocoOutput -split "`n"

        foreach ($line in $lines) {
            # Skip null or empty lines
            if ($null -eq $line -or [string]::IsNullOrWhiteSpace($line)) {
                continue
            }

            $lineTrimmed = $line.Trim()

            # Skip non-data lines
            if ($lineTrimmed -notmatch '\|') {
                continue
            }

            # Parse pipe-delimited format: Name|Current|Available|Pinned
            $parts = $lineTrimmed -split '\|'

            if ($parts.Count -ge 3) {
                $packageName = $parts[0].Trim()
                $currentVersion = $parts[1].Trim()
                $availableVersion = $parts[2].Trim()
                $pinned = if ($parts.Count -ge 4) { $parts[3].Trim() -eq 'true' } else { $false }

                # Skip pinned packages
                if ($pinned) {
                    Write-Verbose "Skipping pinned package: $packageName"
                    continue
                }

                $upgradeItem = [PSCustomObject]@{
                    Name             = $packageName
                    Id               = $packageName  # Choco uses name as ID
                    CurrentVersion   = $currentVersion
                    AvailableVersion = $availableVersion
                    Source           = 'Chocolatey'
                    SourceDetail     = 'chocolatey'
                    UpdateSize       = 'Unknown'
                }

                # Log detected upgrade opportunity
                Write-DetectionLog -Operation 'Detect' -Target $packageName -Component 'APP-UPGRADE-CHOCO' -AdditionalInfo @{
                    PackageName      = $packageName
                    CurrentVersion   = $currentVersion
                    AvailableVersion = $availableVersion
                    Source           = 'Chocolatey'
                    Status           = 'Upgrade Available'
                    UpgradeCommand   = "choco upgrade $packageName -y"
                    Reason           = "Newer version available: $currentVersion → $availableVersion"
                }

                $upgrades += $upgradeItem
            }
        }

        return $upgrades
    }
    catch {
        Write-Verbose "Error detecting Chocolatey upgrades: $($_.Exception.Message)"
        return @()
    }
}

#endregion

# Export public function
Export-ModuleMember -Function Get-AppUpgradeAnalysis



