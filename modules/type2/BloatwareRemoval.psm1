#Requires -Version 7.0

<#
.SYNOPSIS
    Bloatware Removal Module - Type 2 (System Modification)

.DESCRIPTION
    Safe and comprehensive bloatware removal across multiple package managers and installation sources.
    Provides multiple removal methods with fallback options and detailed logging.

.NOTES
    Module Type: Type 2 (System Modification)
    Dependencies: BloatwareDetection.psm1, ConfigManager.psm1
    Requires: Administrator privileges
    Author: Windows Maintenance Automation Project
    Version: 1.0.0
#>

using namespace System.Collections.Generic
using namespace System.Collections.Concurrent

# Import required modules
$ModuleRoot = Split-Path -Parent $PSScriptRoot
$BloatwareDetectionPath = Join-Path $ModuleRoot 'type1\BloatwareDetection.psm1'
if (Test-Path $BloatwareDetectionPath) {
    Import-Module $BloatwareDetectionPath -Force
}

#region Public Functions

<#
.SYNOPSIS
    Safely removes detected bloatware applications
    
.DESCRIPTION
    Orchestrates the removal of bloatware using appropriate methods for each source type.
    Supports dry run mode and provides detailed progress reporting.
    
.PARAMETER BloatwareList
    Array of detected bloatware items to remove
    
.PARAMETER DryRun
    When specified, simulates removal without making changes
    
.PARAMETER Force
    Forces removal even for items that might be needed
    
.PARAMETER Categories
    Specific bloatware categories to remove (OEM, Windows, Gaming, Security)
    
.EXAMPLE
    $results = Remove-DetectedBloatware -BloatwareList $detected -DryRun
    
.EXAMPLE
    $results = Remove-DetectedBloatware -Categories @('OEM', 'Gaming') -Force
#>
function Remove-DetectedBloatware {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact='High')]
    param(
        [Parameter()]
        [Array]$BloatwareList,
        
        [Parameter()]
        [switch]$DryRun,
        
        [Parameter()]
        [switch]$Force,
        
        [Parameter()]
        [string[]]$Categories = @('all')
    )
    
    Write-Host "🗑️  Starting bloatware removal process..." -ForegroundColor Yellow
    $startTime = Get-Date
    
    if (-not $BloatwareList) {
        Write-Host "  🔍 No bloatware list provided, detecting automatically..." -ForegroundColor Gray
        $BloatwareList = Find-InstalledBloatware -Categories $Categories -UseCache
    }
    
    if (-not $BloatwareList -or $BloatwareList.Count -eq 0) {
        Write-Host "  ✅ No bloatware detected for removal" -ForegroundColor Green
        return @{
            TotalProcessed = 0
            Successful = 0
            Failed = 0
            Skipped = 0
            DryRun = $DryRun.IsPresent
        }
    }
    
    Write-Host "  📋 Found $($BloatwareList.Count) bloatware items for removal" -ForegroundColor Cyan
    
    if ($DryRun) {
        Write-Host "  🧪 DRY RUN MODE - No changes will be made" -ForegroundColor Magenta
    }
    
    # Initialize results tracking
    $results = @{
        TotalProcessed = 0
        Successful = 0
        Failed = 0
        Skipped = 0
        DryRun = $DryRun.IsPresent
        Details = [List[PSCustomObject]]::new()
        BySource = @{}
    }
    
    # Group by source for efficient removal
    $groupedBloatware = $BloatwareList | Group-Object Source
    
    foreach ($sourceGroup in $groupedBloatware) {
        $source = $sourceGroup.Name
        $items = $sourceGroup.Group
        
        Write-Host "  🔧 Processing $($items.Count) items from $source..." -ForegroundColor Gray
        
        $sourceResults = switch ($source) {
            'AppX' { Remove-AppXBloatware -Items $items -DryRun:$DryRun }
            'Winget' { Remove-WingetBloatware -Items $items -DryRun:$DryRun }
            'Chocolatey' { Remove-ChocolateyBloatware -Items $items -DryRun:$DryRun }
            'Registry' { Remove-RegistryBloatware -Items $items -DryRun:$DryRun }
            default { 
                Write-Warning "Unknown source type: $source"
                @{ Successful = 0; Failed = $items.Count; Details = @() }
            }
        }
        
        # Aggregate results
        $results.Successful += $sourceResults.Successful
        $results.Failed += $sourceResults.Failed
        $results.Skipped += $sourceResults.Skipped
        $results.Details.AddRange($sourceResults.Details)
        $results.BySource[$source] = $sourceResults
    }
    
    $results.TotalProcessed = $BloatwareList.Count
    $duration = ((Get-Date) - $startTime).TotalSeconds
    
    # Summary output
    $statusIcon = if ($results.Failed -eq 0) { "✅" } else { "⚠️" }
    Write-Host "  $statusIcon Bloatware removal completed in $([math]::Round($duration, 2))s" -ForegroundColor Green
    Write-Host "    📊 Processed: $($results.TotalProcessed), Successful: $($results.Successful), Failed: $($results.Failed)" -ForegroundColor Gray
    
    if ($results.Failed -gt 0) {
        Write-Host "    ❌ Some items could not be removed. Check logs for details." -ForegroundColor Yellow
    }
    
    return $results
}

<#
.SYNOPSIS
    Tests bloatware removal capabilities without making changes
    
.DESCRIPTION
    Performs a comprehensive test of removal capabilities for detected bloatware
    without actually removing anything.
    
.PARAMETER BloatwareList
    Array of detected bloatware items to test
    
.EXAMPLE
    $testResults = Test-BloatwareRemoval -BloatwareList $detected
#>
function Test-BloatwareRemoval {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [Array]$BloatwareList
    )
    
    Write-Host "🧪 Testing bloatware removal capabilities..." -ForegroundColor Cyan
    
    $testResults = @{
        TotalItems = $BloatwareList.Count
        RemovableItems = 0
        NonRemovableItems = 0
        BySource = @{}
        ToolAvailability = Get-RemovalToolAvailability
    }
    
    $groupedBloatware = $BloatwareList | Group-Object Source
    
    foreach ($sourceGroup in $groupedBloatware) {
        $source = $sourceGroup.Name
        $items = $sourceGroup.Group
        
        $sourceTest = @{
            Total = $items.Count
            Removable = 0
            NonRemovable = 0
            Method = Get-PreferredRemovalMethod -Source $source
        }
        
        foreach ($item in $items) {
            if (Test-ItemRemovable -Item $item) {
                $sourceTest.Removable++
                $testResults.RemovableItems++
            } else {
                $sourceTest.NonRemovable++
                $testResults.NonRemovableItems++
            }
        }
        
        $testResults.BySource[$source] = $sourceTest
        Write-Host "  📦 $source`: $($sourceTest.Removable)/$($sourceTest.Total) removable" -ForegroundColor Gray
    }
    
    Write-Host "  📊 Overall: $($testResults.RemovableItems)/$($testResults.TotalItems) items can be removed" -ForegroundColor Green
    
    return $testResults
}

#endregion

#region AppX Removal

<#
.SYNOPSIS
    Removes AppX (Windows Store) packages
#>
function Remove-AppXBloatware {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [Array]$Items,
        
        [Parameter()]
        [switch]$DryRun
    )
    
    $results = @{
        Successful = 0
        Failed = 0
        Skipped = 0
        Details = [List[PSCustomObject]]::new()
    }
    
    if (-not (Get-Command Get-AppxPackage -ErrorAction SilentlyContinue)) {
        Write-Warning "AppX module not available, skipping AppX removals"
        $results.Skipped = $Items.Count
        return $results
    }
    
    foreach ($item in $Items) {
        $packageName = $item.Name
        $result = @{
            Name = $packageName
            Source = 'AppX'
            Success = $false
            Action = if ($DryRun) { 'Simulated' } else { 'Removed' }
            Error = $null
        }
        
        try {
            if ($DryRun) {
                Write-Host "    [DRY RUN] Would remove AppX package: $packageName" -ForegroundColor DarkYellow
                $result.Success = $true
            } else {
                Write-Host "    🗑️ Removing AppX package: $packageName" -ForegroundColor Yellow
                
                # Try to remove for all users first
                $package = Get-AppxPackage -Name $packageName -AllUsers -ErrorAction SilentlyContinue
                if ($package) {
                    $package | Remove-AppxPackage -ErrorAction Stop
                }
                
                # Remove provisioned package to prevent reinstallation
                $provisionedPackage = Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -eq $packageName }
                if ($provisionedPackage) {
                    Remove-AppxProvisionedPackage -Online -PackageName $provisionedPackage.PackageName -ErrorAction SilentlyContinue
                }
                
                $result.Success = $true
                Write-Host "      ✅ Successfully removed AppX package: $packageName" -ForegroundColor Green
            }
            
            $results.Successful++
        }
        catch {
            $result.Error = $_.Exception.Message
            $results.Failed++
            Write-Warning "Failed to remove AppX package ${packageName}: $_"
        }
        
        $results.Details.Add([PSCustomObject]$result)
    }
    
    return $results
}

#endregion

#region Winget Removal

<#
.SYNOPSIS
    Removes packages using Winget package manager
#>
function Remove-WingetBloatware {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [Array]$Items,
        
        [Parameter()]
        [switch]$DryRun
    )
    
    $results = @{
        Successful = 0
        Failed = 0
        Skipped = 0
        Details = [List[PSCustomObject]]::new()
    }
    
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Warning "Winget not available, skipping Winget removals"
        $results.Skipped = $Items.Count
        return $results
    }
    
    foreach ($item in $Items) {
        $packageName = $item.Name
        $result = @{
            Name = $packageName
            Source = 'Winget'
            Success = $false
            Action = if ($DryRun) { 'Simulated' } else { 'Removed' }
            Error = $null
        }
        
        try {
            if ($DryRun) {
                Write-Host "    [DRY RUN] Would uninstall Winget package: $packageName" -ForegroundColor DarkYellow
                $result.Success = $true
            } else {
                Write-Host "    🗑️ Uninstalling Winget package: $packageName" -ForegroundColor Yellow
                
                $wingetArgs = @(
                    'uninstall',
                    '--id', $packageName,
                    '--silent',
                    '--accept-source-agreements'
                )
                
                $process = Start-Process -FilePath 'winget' -ArgumentList $wingetArgs -Wait -PassThru -NoNewWindow
                
                if ($process.ExitCode -eq 0) {
                    $result.Success = $true
                    Write-Host "      ✅ Successfully uninstalled Winget package: $packageName" -ForegroundColor Green
                } else {
                    throw "Winget uninstall failed with exit code $($process.ExitCode)"
                }
            }
            
            $results.Successful++
        }
        catch {
            $result.Error = $_.Exception.Message
            $results.Failed++
            Write-Warning "Failed to uninstall Winget package ${packageName}: $_"
        }
        
        $results.Details.Add([PSCustomObject]$result)
    }
    
    return $results
}

#endregion

#region Chocolatey Removal

<#
.SYNOPSIS
    Removes packages using Chocolatey package manager
#>
function Remove-ChocolateyBloatware {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [Array]$Items,
        
        [Parameter()]
        [switch]$DryRun
    )
    
    $results = @{
        Successful = 0
        Failed = 0
        Skipped = 0
        Details = [List[PSCustomObject]]::new()
    }
    
    if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
        Write-Warning "Chocolatey not available, skipping Chocolatey removals"
        $results.Skipped = $Items.Count
        return $results
    }
    
    foreach ($item in $Items) {
        $packageName = $item.Name
        $result = @{
            Name = $packageName
            Source = 'Chocolatey'
            Success = $false
            Action = if ($DryRun) { 'Simulated' } else { 'Removed' }
            Error = $null
        }
        
        try {
            if ($DryRun) {
                Write-Host "    [DRY RUN] Would uninstall Chocolatey package: $packageName" -ForegroundColor DarkYellow
                $result.Success = $true
            } else {
                Write-Host "    🗑️ Uninstalling Chocolatey package: $packageName" -ForegroundColor Yellow
                
                $chocoArgs = @(
                    'uninstall',
                    $packageName,
                    '-y',
                    '--limit-output'
                )
                
                $process = Start-Process -FilePath 'choco' -ArgumentList $chocoArgs -Wait -PassThru -NoNewWindow
                
                if ($process.ExitCode -eq 0) {
                    $result.Success = $true
                    Write-Host "      ✅ Successfully uninstalled Chocolatey package: $packageName" -ForegroundColor Green
                } else {
                    throw "Chocolatey uninstall failed with exit code $($process.ExitCode)"
                }
            }
            
            $results.Successful++
        }
        catch {
            $result.Error = $_.Exception.Message
            $results.Failed++
            Write-Warning "Failed to uninstall Chocolatey package ${packageName}: $_"
        }
        
        $results.Details.Add([PSCustomObject]$result)
    }
    
    return $results
}

#endregion

#region Registry Removal

<#
.SYNOPSIS
    Removes applications using Registry uninstall strings
#>
function Remove-RegistryBloatware {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [Array]$Items,
        
        [Parameter()]
        [switch]$DryRun
    )
    
    $results = @{
        Successful = 0
        Failed = 0
        Skipped = 0
        Details = [List[PSCustomObject]]::new()
    }
    
    foreach ($item in $Items) {
        $appName = $item.DisplayName ?? $item.Name
        $uninstallString = $item.UninstallString
        
        $result = @{
            Name = $appName
            Source = 'Registry'
            Success = $false
            Action = if ($DryRun) { 'Simulated' } else { 'Removed' }
            Error = $null
        }
        
        try {
            if (-not $uninstallString) {
                throw "No uninstall string available"
            }
            
            if ($DryRun) {
                Write-Host "    [DRY RUN] Would execute uninstaller: $appName" -ForegroundColor DarkYellow
                $result.Success = $true
            } else {
                Write-Host "    🗑️ Executing uninstaller: $appName" -ForegroundColor Yellow
                
                # Parse uninstall string to extract executable and arguments
                if ($uninstallString -match '^"([^"]+)"(.*)') {
                    $executable = $matches[1]
                    $arguments = $matches[2].Trim()
                } else {
                    $parts = $uninstallString -split ' ', 2
                    $executable = $parts[0]
                    $arguments = if ($parts.Count -gt 1) { $parts[1] } else { '' }
                }
                
                # Add silent flags if not present
                if ($arguments -notmatch '/S|/silent|/quiet|/q') {
                    $arguments += ' /S'
                }
                
                $process = Start-Process -FilePath $executable -ArgumentList $arguments -Wait -PassThru -NoNewWindow
                
                if ($process.ExitCode -eq 0) {
                    $result.Success = $true
                    Write-Host "      ✅ Successfully uninstalled: $appName" -ForegroundColor Green
                } else {
                    throw "Uninstaller failed with exit code $($process.ExitCode)"
                }
            }
            
            $results.Successful++
        }
        catch {
            $result.Error = $_.Exception.Message
            $results.Failed++
            Write-Warning "Failed to uninstall ${appName}: $_"
        }
        
        $results.Details.Add([PSCustomObject]$result)
    }
    
    return $results
}

#endregion

#region Helper Functions

<#
.SYNOPSIS
    Gets availability of removal tools
#>
function Get-RemovalToolAvailability {
    return @{
        AppX = $null -ne (Get-Command Get-AppxPackage -ErrorAction SilentlyContinue)
        Winget = $null -ne (Get-Command winget -ErrorAction SilentlyContinue)
        Chocolatey = $null -ne (Get-Command choco -ErrorAction SilentlyContinue)
        PowerShell = $PSVersionTable.PSVersion.Major -ge 5
    }
}

<#
.SYNOPSIS
    Gets the preferred removal method for a given source
#>
function Get-PreferredRemovalMethod {
    param([string]$Source)
    
    switch ($Source) {
        'AppX' { 'Remove-AppxPackage' }
        'Winget' { 'winget uninstall' }
        'Chocolatey' { 'choco uninstall' }
        'Registry' { 'Registry uninstaller' }
        default { 'Unknown' }
    }
}

<#
.SYNOPSIS
    Tests if an item can be removed
#>
function Test-ItemRemovable {
    param([PSCustomObject]$Item)
    
    switch ($Item.Source) {
        'AppX' { 
            return $null -ne (Get-Command Get-AppxPackage -ErrorAction SilentlyContinue)
        }
        'Winget' { 
            return $null -ne (Get-Command winget -ErrorAction SilentlyContinue)
        }
        'Chocolatey' { 
            return $null -ne (Get-Command choco -ErrorAction SilentlyContinue)
        }
        'Registry' { 
            return $null -ne $Item.UninstallString
        }
        default { 
            return $false
        }
    }
}

#endregion

# Export module functions
Export-ModuleMember -Function @(
    'Remove-DetectedBloatware',
    'Test-BloatwareRemoval'
)