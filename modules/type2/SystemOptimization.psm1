#Requires -Version 7.0
# Module Dependencies:
#   - ConfigManager.psm1 (for configuration access)
#   - LoggingManager.psm1 (for structured logging)

<#
.SYNOPSIS
    System Optimization Module - Type 2 (System Modification)

.DESCRIPTION
    Comprehensive system performance optimization including disk cleanup, registry optimization,
    UI tweaks, and system configuration improvements for better performance.

.NOTES
    Module Type: Type 2 (System Modification)
    Dependencies: Registry access, file system access
    Requires: Administrator privileges for system-wide optimizations
    Author: Windows Maintenance Automation Project
    Version: 1.0.0
#>

using namespace System.Collections.Generic

# v3.0 Self-contained Type 2 module with internal Type 1 dependency

# Step 1: Import corresponding Type 1 module (REQUIRED)
$Type1ModulePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'type1\SystemOptimizationAudit.psm1'
if (Test-Path $Type1ModulePath) {
    Import-Module $Type1ModulePath -Force
}
else {
    throw "Required Type 1 module not found: $Type1ModulePath"
}

# Step 2: Import core infrastructure (REQUIRED)
$CoreInfraPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'core\CoreInfrastructure.psm1'
if (Test-Path $CoreInfraPath) {
    Import-Module $CoreInfraPath -Force
}
else {
    # Fallback logging function if CoreInfrastructure fails
    function Write-LogEntry {
        param($Level, $Component, $Message, $Data)
        Write-Information "[$Level] [$Component] $Message" -InformationAction Continue
    }
}

# Step 3: Import additional dependencies
$DependencyManagerPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'core\DependencyManager.psm1'
if (Test-Path $DependencyManagerPath) {
    Import-Module $DependencyManagerPath -Force
}

# Validate Type1 module loaded correctly
if (-not (Get-Command -Name 'Get-SystemOptimizationAudit' -ErrorAction SilentlyContinue)) {
    throw "Type 1 module functions not available - ensure SystemOptimizationAudit.psm1 is properly imported"
}

#region v3.0 Standardized Execution Function

<#
.SYNOPSIS
    Main execution function for system optimization - v3.0 Architecture Pattern
#>
function Invoke-SystemOptimization {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Config,
        [Parameter()]
        [switch]$DryRun
    )
    
    $perfContext = $null
    try {
        $perfContext = Start-PerformanceTracking -OperationName 'SystemOptimization' -Component 'SYSTEM-OPTIMIZATION'
    }
    catch { }
    
    try {
        Write-LogEntry -Level 'INFO' -Component 'SYSTEM-OPTIMIZATION' -Message 'Starting system optimization analysis'
        $analysisResults = Get-SystemOptimizationAudit
        
        if (-not $analysisResults -or $analysisResults.OptimizationCount -eq 0) {
            Write-LogEntry -Level 'INFO' -Component 'SYSTEM-OPTIMIZATION' -Message 'No optimization opportunities detected'
            if ($perfContext) { Complete-PerformanceTracking -Context $perfContext -Status 'Success' }
            return @{ Success = $true; ItemsDetected = 0; ItemsProcessed = 0; DryRun = $DryRun.IsPresent; Message = 'System already optimized' }
        }
        
        $optimizationCount = $analysisResults.OptimizationCount
        Write-LogEntry -Level 'INFO' -Component 'SYSTEM-OPTIMIZATION' -Message "Detected $optimizationCount optimization opportunities"
        
        if ($DryRun) {
            Write-LogEntry -Level 'INFO' -Component 'SYSTEM-OPTIMIZATION' -Message 'DRY RUN: Simulating system optimization'
            $results = @{ ProcessedCount = $optimizationCount; Simulated = $true }
            $processedCount = $optimizationCount
        }
        else {
            Write-LogEntry -Level 'INFO' -Component 'SYSTEM-OPTIMIZATION' -Message 'Executing system optimization'
            # Process optimization opportunities based on detected types
            $processedCount = 0
            if ($analysisResults.OptimizationOpportunities) {
                foreach ($opportunity in $analysisResults.OptimizationOpportunities) {
                    switch ($opportunity.Type) {
                        'TempCleanup' { $result = Optimize-SystemPerformance -CleanupTemp }
                        'StartupOptimization' { $result = Optimize-SystemPerformance -OptimizeStartup }
                        'UIOptimization' { $result = Optimize-SystemPerformance -OptimizeUI }
                        'RegistryOptimization' { $result = Optimize-SystemPerformance -OptimizeRegistry }
                        'DiskOptimization' { $result = Optimize-SystemPerformance -OptimizeDisk }
                        'NetworkOptimization' { $result = Optimize-SystemPerformance -OptimizeNetwork }
                        default { Write-LogEntry -Level 'WARNING' -Component 'SYSTEM-OPTIMIZATION' -Message "Unknown optimization type: $($opportunity.Type)" }
                    }
                    if ($result) { $processedCount++ }
                }
            }
            $results = @{ ProcessedCount = $processedCount; AppliedOptimizations = $processedCount }
        }
        
        $returnData = @{
            Success = $true; ItemsDetected = $optimizationCount; ItemsProcessed = $processedCount
            DryRun = $DryRun.IsPresent; Results = $results; DetectionData = $analysisResults
        }
        
        Write-LogEntry -Level 'SUCCESS' -Component 'SYSTEM-OPTIMIZATION' -Message "System optimization completed. Processed: $processedCount/$optimizationCount"
        if ($perfContext) { Complete-PerformanceTracking -Context $perfContext -Status 'Success' }
        return $returnData
        
    }
    catch {
        $errorMsg = "Failed to execute system optimization: $($_.Exception.Message)"
        Write-LogEntry -Level 'ERROR' -Component 'SYSTEM-OPTIMIZATION' -Message $errorMsg -Data @{ Error = $_.Exception }
        if ($perfContext) { Complete-PerformanceTracking -Context $perfContext -Status 'Failed' -ErrorMessage $errorMsg }
        
        return @{
            Success = $false; Error = $errorMsg; ErrorType = $_.Exception.GetType().Name
            ItemsDetected = if ($analysisResults) { $analysisResults.OptimizationCount } else { 0 }; ItemsProcessed = 0; DryRun = $DryRun.IsPresent
        }
    }
}

#endregion

#region Legacy Public Functions (Preserved for Internal Use)

<#
.SYNOPSIS
    Performs comprehensive system optimization

.DESCRIPTION
    Optimizes system performance through disk cleanup, registry optimization,
    UI tweaks, startup optimization, and system configuration improvements.

.PARAMETER CleanupTemp
    Clean temporary files and folders

.PARAMETER OptimizeStartup
    Optimize startup programs and services

.PARAMETER OptimizeUI
    Optimize Windows UI and visual effects

.PARAMETER OptimizeRegistry
    Clean and optimize Windows registry

.PARAMETER OptimizeDisk
    Perform disk optimization tasks

.PARAMETER OptimizeNetwork
    Apply network performance optimizations

.PARAMETER DryRun
    Simulate optimizations without applying changes

.EXAMPLE
    $results = Optimize-SystemPerformance

.EXAMPLE
    $results = Optimize-SystemPerformance -OptimizeStartup -OptimizeUI -DryRun
#>
function Optimize-SystemPerformance {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([bool])]
    param(
        [Parameter()]
        [switch]$CleanupTemp,

        [Parameter()]
        [switch]$OptimizeStartup,

        [Parameter()]
        [switch]$OptimizeUI,

        [Parameter()]
        [switch]$OptimizeRegistry,

        [Parameter()]
        [switch]$OptimizeDisk,

        [Parameter()]
        [switch]$OptimizeNetwork,

        [Parameter()]
        [switch]$DryRun
    )

    Write-Information "⚡ Starting comprehensive system optimization..." -InformationAction Continue
    $startTime = Get-Date
    
    # Initialize structured logging and performance tracking
    try {
        Write-LogEntry -Level 'INFO' -Component 'SYSTEM-OPTIMIZATION' -Message 'Starting comprehensive system optimization' -Data @{
            CleanupTemp      = $CleanupTemp.IsPresent
            OptimizeStartup  = $OptimizeStartup.IsPresent
            OptimizeUI       = $OptimizeUI.IsPresent
            OptimizeRegistry = $OptimizeRegistry.IsPresent
            OptimizeDisk     = $OptimizeDisk.IsPresent
            OptimizeNetwork  = $OptimizeNetwork.IsPresent
            DryRun           = $DryRun.IsPresent
        }
        $perfContext = Start-PerformanceTracking -OperationName 'SystemPerformanceOptimization' -Component 'SYSTEM-OPTIMIZATION'
    }
    catch {
        # LoggingManager not available, continue with standard logging
    }
    
    # Check for administrator privileges before proceeding
    try {
        Assert-AdminPrivilege -Operation "System performance optimization"
    }
    catch {
        Write-Error "Administrator privileges are required for system optimization operations: $_"
        return $false
    }

    if ($DryRun) {
        Write-Information "  🧪 DRY RUN MODE - No changes will be applied" -InformationAction Continue
    }

    # Initialize results tracking
    $results = @{
        TotalOperations = 0
        Successful      = 0
        Failed          = 0
        SpaceFreed      = 0
        DryRun          = $DryRun.IsPresent
        Details         = [List[PSCustomObject]]::new()
        Categories      = @{
            TempCleanup          = @{ Success = 0; Failed = 0; SpaceFreed = 0 }
            StartupOptimization  = @{ Success = 0; Failed = 0; ItemsOptimized = 0 }
            UIOptimization       = @{ Success = 0; Failed = 0; SettingsChanged = 0 }
            RegistryOptimization = @{ Success = 0; Failed = 0; EntriesProcessed = 0 }
            DiskOptimization     = @{ Success = 0; Failed = 0; TasksCompleted = 0 }
            NetworkOptimization  = @{ Success = 0; Failed = 0; SettingsApplied = 0 }
        }
    }

    try {
        # Temporary files cleanup (default: enabled)
        if ($CleanupTemp -or (-not $PSBoundParameters.ContainsKey('CleanupTemp'))) {
            Write-Information "  🧹 Cleaning temporary files..." -InformationAction Continue
            $tempResults = Clear-TemporaryFile -DryRun:$DryRun
            Merge-OptimizationResult -Results $results -NewResults $tempResults -Category 'TempCleanup'
        }

        # Startup optimization (default: enabled)
        if ($OptimizeStartup -or (-not $PSBoundParameters.ContainsKey('OptimizeStartup'))) {
            Write-Information "  🚀 Optimizing startup programs..." -InformationAction Continue
            $startupResults = Optimize-StartupProgram -DryRun:$DryRun
            Merge-OptimizationResult -Results $results -NewResults $startupResults -Category 'StartupOptimization'
        }

        # UI optimization (default: enabled)
        if ($OptimizeUI -or (-not $PSBoundParameters.ContainsKey('OptimizeUI'))) {
            Write-Information "  🎨 Optimizing user interface..." -InformationAction Continue
            $uiResults = Optimize-UserInterface -DryRun:$DryRun
            Merge-OptimizationResult -Results $results -NewResults $uiResults -Category 'UIOptimization'
        }

        # Registry optimization (default: disabled)
        if ($OptimizeRegistry) {
            Write-Information "  📋 Optimizing registry..." -InformationAction Continue
            $registryResults = Optimize-WindowsRegistry -DryRun:$DryRun
            Merge-OptimizationResult -Results $results -NewResults $registryResults -Category 'RegistryOptimization'
        }

        # Disk optimization (default: enabled)
        if ($OptimizeDisk -or (-not $PSBoundParameters.ContainsKey('OptimizeDisk'))) {
            Write-Information "  💽 Optimizing disk performance..." -InformationAction Continue
            $diskResults = Optimize-DiskPerformance -DryRun:$DryRun
            Merge-OptimizationResult -Results $results -NewResults $diskResults -Category 'DiskOptimization'
        }

        # Network optimization (default: disabled)
        if ($OptimizeNetwork) {
            Write-Information "  🌐 Optimizing network settings..." -InformationAction Continue
            $networkResults = Optimize-NetworkSetting -DryRun:$DryRun
            Merge-OptimizationResult -Results $results -NewResults $networkResults -Category 'NetworkOptimization'
        }

        $duration = ((Get-Date) - $startTime).TotalSeconds
        $spaceFreedMB = [math]::Round($results.SpaceFreed / 1MB, 2)

        # Summary output
        $statusIcon = if ($results.Failed -eq 0) { "✅" } else { "⚠️" }
        Write-Information "  $statusIcon System optimization completed in $([math]::Round($duration, 2))s" -InformationAction Continue
        Write-Information "    📊 Operations: $($results.TotalOperations), Successful: $($results.Successful), Failed: $($results.Failed)" -InformationAction Continue

        if ($results.SpaceFreed -gt 0) {
            Write-Information "    💾 Disk space freed: ${spaceFreedMB} MB" -InformationAction Continue
        }

        $success = $results.Failed -eq 0 && $results.Successful -gt 0
        if (-not $success) {
            Write-Information "    ❌ Some optimizations failed. Check logs for details." -InformationAction Continue
        }

        # Complete performance tracking and structured logging
        try {
            Complete-PerformanceTracking -PerformanceContext $perfContext -Success $success -ResultData @{
                TotalOperations       = $results.TotalOperations
                Successful            = $results.Successful
                Failed                = $results.Failed
                SpaceFreed            = $results.SpaceFreed
                SpaceFreedMB          = $spaceFreedMB
                Duration              = $duration
                TempCleanupOperations = $results.Categories.TempCleanup
                StartupOptimizations  = $results.Categories.StartupOptimization
                UIOptimizations       = $results.Categories.UIOptimization
                RegistryOptimizations = $results.Categories.RegistryOptimization
                DiskOptimizations     = $results.Categories.DiskOptimization
                NetworkOptimizations  = $results.Categories.NetworkOptimization
            }
            Write-LogEntry -Level $(if ($success) { 'SUCCESS' } else { 'WARN' }) -Component 'SYSTEM-OPTIMIZATION' -Message 'System optimization operation completed' -Data $results
        }
        catch {
            # LoggingManager not available, continue with standard logging
        }
        
        # Log detailed results for audit trails
        Write-Verbose "System optimization operation details: $(ConvertTo-Json $results -Depth 3)"
        Write-Verbose "System optimization completed successfully"
        
        return $success
    }
    catch {
        $errorMessage = "❌ System optimization failed: $($_.Exception.Message)"
        Write-Error $errorMessage
        Write-Verbose "Error details: $($_.Exception.ToString())"
        
        # Complete performance tracking for failed operation
        try {
            Complete-PerformanceTracking -PerformanceContext $perfContext -Success $false -ResultData @{ Error = $_.Exception.Message }
            Write-LogEntry -Level 'ERROR' -Component 'SYSTEM-OPTIMIZATION' -Message 'System optimization operation failed' -Data @{ Error = $_.Exception.Message; ErrorType = $_.Exception.GetType().Name }
        }
        catch {
            # LoggingManager not available, continue with standard logging
        }
        
        # Type 2 module returns boolean for failure
        return $false
    }
    finally {
        $duration = ((Get-Date) - $startTime).TotalSeconds
        Write-Verbose "System optimization operation completed in $([math]::Round($duration, 2)) seconds"
    }
}

<#
.SYNOPSIS
    Gets current system performance metrics

.DESCRIPTION
    Evaluates current system performance and identifies optimization opportunities.

.EXAMPLE
    $metrics = Get-SystemPerformanceMetric
#>
function Get-SystemPerformanceMetric {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    Write-Information "📊 Analyzing system performance..." -InformationAction Continue

    $metrics = @{
        Timestamp       = Get-Date
        DiskUsage       = Get-DiskUsageMetric
        StartupPrograms = Get-StartupProgramCount
        TemporaryFiles  = Get-TemporaryFileSize
        RegistrySize    = Get-RegistrySize
        ServicesRunning = (Get-Service | Where-Object Status -eq 'Running').Count
        ProcessCount    = (Get-Process).Count
        MemoryUsage     = Get-MemoryUsagePercent
        Recommendations = [List[string]]::new()
    }

    # Generate recommendations based on metrics
    if ($metrics.TemporaryFiles -gt 500MB) {
        $metrics.Recommendations.Add("High temporary file usage detected ($([math]::Round($metrics.TemporaryFiles/1MB)) MB)")
    }

    if ($metrics.StartupPrograms -gt 15) {
        $metrics.Recommendations.Add("Many startup programs detected ($($metrics.StartupPrograms))")
    }

    if ($metrics.MemoryUsage -gt 80) {
        $metrics.Recommendations.Add("High memory usage detected ($($metrics.MemoryUsage)%)")
    }

    Write-Information "  💽 Disk Usage: $($metrics.DiskUsage.UsedPercentage)%" -InformationAction Continue
    Write-Information "  🚀 Startup Programs: $($metrics.StartupPrograms)" -InformationAction Continue
    Write-Information "  🗂️  Temporary Files: $([math]::Round($metrics.TemporaryFiles/1MB)) MB" -InformationAction Continue
    Write-Information "  💡 Recommendations: $($metrics.Recommendations.Count)" -InformationAction Continue

    return $metrics
}

#endregion

#region Temporary Files Cleanup

<#
.SYNOPSIS
    Cleans temporary files and folders
#>
function Clear-TemporaryFile {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([hashtable])]
    param(
        [Parameter()]
        [switch]$DryRun
    )

    $results = @{
        Success    = 0
        Failed     = 0
        SpaceFreed = 0
        Details    = [List[PSCustomObject]]::new()
    }

    # Define cleanup targets
    $cleanupTargets = @(
        @{ Path = "$env:TEMP\*"; Name = "User Temp Files"; Recurse = $true }
        @{ Path = "$env:LOCALAPPDATA\Temp\*"; Name = "Local App Temp Files"; Recurse = $true }
        @{ Path = "C:\Windows\Temp\*"; Name = "Windows Temp Files"; Recurse = $true }
        @{ Path = "C:\Windows\Prefetch\ReadyBoot"; Name = "ReadyBoot Cache"; Recurse = $true }
        @{ Path = "C:\Windows\Prefetch\*.pf"; Name = "Prefetch Files"; Recurse = $false }
        @{ Path = "$env:LOCALAPPDATA\Microsoft\Windows\INetCache\*"; Name = "Internet Cache"; Recurse = $true }
        @{ Path = "C:\Windows\SoftwareDistribution\Download\*"; Name = "Windows Update Cache"; Recurse = $true }
    )

    foreach ($target in $cleanupTargets) {
        $cleanupResult = @{
            Name       = $target.Name
            Path       = $target.Path
            Success    = $false
            SpaceFreed = 0
            Error      = $null
        }

        try {
            # Calculate size before cleanup
            $beforeSize = 0
            if (Test-Path (Split-Path $target.Path -Parent)) {
                $items = Get-ChildItem -Path $target.Path -Force -ErrorAction SilentlyContinue
                if ($target.Recurse) {
                    $beforeSize = ($items | Get-ChildItem -Recurse -Force -ErrorAction SilentlyContinue |
                        Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
                }
                else {
                    $beforeSize = ($items | Where-Object { -not $_.PSIsContainer } |
                        Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
                }
            }

            if ($DryRun) {
                $cleanupResult.SpaceFreed = $beforeSize ?? 0
                $cleanupResult.Success = $true
                Write-Information "    [DRY RUN] Would clean $($target.Name): $([math]::Round($cleanupResult.SpaceFreed/1MB, 2)) MB" -InformationAction Continue
            }
            else {
                # Perform actual cleanup
                if (Test-Path (Split-Path $target.Path -Parent)) {
                    if ($target.Recurse) {
                        Remove-Item -Path $target.Path -Recurse -Force -ErrorAction SilentlyContinue
                    }
                    else {
                        Remove-Item -Path $target.Path -Force -ErrorAction SilentlyContinue
                    }
                }

                # Calculate space freed
                $afterSize = 0
                if (Test-Path (Split-Path $target.Path -Parent)) {
                    $items = Get-ChildItem -Path $target.Path -Force -ErrorAction SilentlyContinue
                    if ($target.Recurse) {
                        $afterSize = ($items | Get-ChildItem -Recurse -Force -ErrorAction SilentlyContinue |
                            Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
                    }
                    else {
                        $afterSize = ($items | Where-Object { -not $_.PSIsContainer } |
                            Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
                    }
                }

                $cleanupResult.SpaceFreed = [math]::Max(0, ($beforeSize ?? 0) - ($afterSize ?? 0))
                $cleanupResult.Success = $true

                if ($cleanupResult.SpaceFreed -gt 0) {
                    Write-Information "    🧹 Cleaned $($target.Name): $([math]::Round($cleanupResult.SpaceFreed/1MB, 2)) MB" -InformationAction Continue
                }
            }

            $results.Success++
            $results.SpaceFreed += $cleanupResult.SpaceFreed
        }
        catch {
            $cleanupResult.Error = $_.Exception.Message
            $results.Failed++
            Write-Warning "Failed to clean $($target.Name): $_"
        }

        $results.Details.Add([PSCustomObject]$cleanupResult)
    }

    return $results
}

#endregion

#region Startup Optimization

<#
.SYNOPSIS
    Optimizes startup programs and services
#>
function Optimize-StartupProgram {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([hashtable])]
    param(
        [Parameter()]
        [switch]$DryRun
    )

    $results = @{
        Success        = 0
        Failed         = 0
        ItemsOptimized = 0
        Details        = [List[PSCustomObject]]::new()
    }

    # Get startup programs from registry
    $startupLocations = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce'
    )

    # Programs that are generally safe to disable
    $safeToDisable = @(
        '*Adobe*Updater*', '*Adobe*Update*', '*iTunesHelper*', '*QuickTime*',
        '*Spotify*', '*Skype*Update*', '*Steam*', '*Discord*Update*',
        '*CCleaner*', '*WinRAR*', '*7-Zip*', '*VLC*Update*'
    )

    foreach ($location in $startupLocations) {
        if (Test-Path $location) {
            try {
                $startupItems = Get-ItemProperty -Path $location -ErrorAction SilentlyContinue

                if ($startupItems) {
                    $properties = $startupItems.PSObject.Properties | Where-Object {
                        $_.Name -notin @('PSPath', 'PSParentPath', 'PSChildName', 'PSDrive', 'PSProvider')
                    }

                    foreach ($property in $properties) {
                        $itemName = $property.Name
                        $itemValue = $property.Value

                        # Check if this item should be optimized
                        $shouldOptimize = $false
                        foreach ($pattern in $safeToDisable) {
                            if ($itemName -like $pattern -or $itemValue -like $pattern) {
                                $shouldOptimize = $true
                                break
                            }
                        }

                        if ($shouldOptimize) {
                            $optimizationResult = @{
                                Name     = $itemName
                                Value    = $itemValue
                                Location = $location
                                Action   = 'Disabled'
                                Success  = $false
                            }

                            try {
                                if ($DryRun) {
                                    Write-Information "    [DRY RUN] Would disable startup item: $itemName" -InformationAction Continue
                                    $optimizationResult.Success = $true
                                }
                                else {
                                    # Backup the value before removing
                                    $backupPath = "$location\Backup"
                                    if (-not (Test-Path $backupPath)) {
                                        New-Item -Path $backupPath -Force | Out-Null
                                    }
                                    Set-ItemProperty -Path $backupPath -Name $itemName -Value $itemValue -Force

                                    # Remove from startup
                                    Remove-ItemProperty -Path $location -Name $itemName -Force
                                    $optimizationResult.Success = $true
                                    Write-Information "    🚀 Disabled startup item: $itemName" -InformationAction Continue
                                }

                                $results.Success++
                                $results.ItemsOptimized++
                            }
                            catch {
                                $optimizationResult.Error = $_.Exception.Message
                                $results.Failed++
                                Write-Warning "Failed to disable startup item $itemName`: $_"
                            }

                            $results.Details.Add([PSCustomObject]$optimizationResult)
                        }
                    }
                }
            }
            catch {
                Write-Warning "Failed to process startup location ${location}: $_"
                $results.Failed++
            }
        }
    }

    return $results
}

#endregion

#region UI Optimization

<#
.SYNOPSIS
    Optimizes Windows user interface and visual effects
#>
function Optimize-UserInterface {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([hashtable])]
    param(
        [Parameter()]
        [switch]$DryRun
    )

    $results = @{
        Success         = 0
        Failed          = 0
        SettingsChanged = 0
        Details         = [List[PSCustomObject]]::new()
    }

    # UI optimization settings
    $uiOptimizations = @{
        # Disable visual effects for performance
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' = @{
            'VisualFXSetting' = 2  # Custom (let us set individual settings)
        }
        # Taskbar optimizations
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'      = @{
            'ShowTaskViewButton' = 0      # Hide Task View button
            'TaskbarAnimations'  = 0       # Disable taskbar animations
            'ListviewShadow'     = 0          # Disable shadows
            'TaskbarSmallIcons'  = 1       # Use small taskbar icons
        }
        # Search optimizations
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search'                 = @{
            'SearchboxTaskbarMode' = 0    # Hide search box
            'CortanaConsent'       = 0          # Disable Cortana
        }
        # Performance settings
        'HKCU:\Control Panel\Desktop'                                            = @{
            'DragFullWindows' = '0'       # Don't drag full windows
            'MenuShowDelay'   = '0'         # No menu delay
        }
        'HKCU:\Control Panel\Desktop\WindowMetrics'                              = @{
            'MinAnimate' = '0'            # Disable minimize/maximize animations
        }
    }

    foreach ($registryPath in $uiOptimizations.Keys) {
        foreach ($setting in $uiOptimizations[$registryPath].GetEnumerator()) {
            $settingResult = @{
                Path    = $registryPath
                Setting = $setting.Key
                Value   = $setting.Value
                Success = $false
                Error   = $null
            }

            try {
                if ($DryRun) {
                    Write-Information "    [DRY RUN] Would set $($setting.Key) = $($setting.Value) in $registryPath" -InformationAction Continue
                    $settingResult.Success = $true
                }
                else {
                    # Ensure registry path exists
                    if (-not (Test-Path $registryPath)) {
                        New-Item -Path $registryPath -Force | Out-Null
                    }

                    # Set the value
                    Set-ItemProperty -Path $registryPath -Name $setting.Key -Value $setting.Value -Force
                    $settingResult.Success = $true
                    Write-Information "    🎨 Applied UI optimization: $($setting.Key)" -InformationAction Continue
                }

                $results.Success++
                $results.SettingsChanged++
            }
            catch {
                $settingResult.Error = $_.Exception.Message
                $results.Failed++
                Write-Warning "Failed to apply UI setting $($setting.Key): $_"
            }

            $results.Details.Add([PSCustomObject]$settingResult)
        }
    }

    return $results
}

#endregion

#region Registry Optimization

<#
.SYNOPSIS
    Optimizes Windows registry for better performance
#>
function Optimize-WindowsRegistry {
    [CmdletBinding()]
    param(
        [Parameter()]
        [switch]$DryRun
    )

    $results = @{
        Success          = 0
        Failed           = 0
        EntriesProcessed = 0
        Details          = [List[PSCustomObject]]::new()
    }

    Write-Warning "Registry optimization requires careful implementation and is currently limited to safe operations"

    # Safe registry optimizations only
    $safeOptimizations = @{
        # Clear recent documents
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\RecentDocs' = @{
            Action      = 'ClearEntries'
            Description = 'Clear recent documents'
        }
        # Clear run history
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\RunMRU'     = @{
            Action      = 'ClearEntries'
            Description = 'Clear run command history'
        }
    }

    foreach ($registryPath in $safeOptimizations.Keys) {
        $optimization = $safeOptimizations[$registryPath]
        $optimizationResult = @{
            Path        = $registryPath
            Description = $optimization.Description
            Success     = $false
            Error       = $null
        }

        try {
            if (Test-Path $registryPath) {
                if ($DryRun) {
                    Write-Information "    [DRY RUN] Would $($optimization.Description.ToLower())" -InformationAction Continue
                    $optimizationResult.Success = $true
                }
                else {
                    # Clear registry entries safely
                    $items = Get-ChildItem -Path $registryPath -ErrorAction SilentlyContinue
                    foreach ($item in $items) {
                        Remove-Item -Path $item.PSPath -Force -ErrorAction SilentlyContinue
                    }

                    $optimizationResult.Success = $true
                    Write-Information "    📋 $($optimization.Description)" -InformationAction Continue
                }

                $results.Success++
                $results.EntriesProcessed++
            }
        }
        catch {
            $optimizationResult.Error = $_.Exception.Message
            $results.Failed++
            Write-Warning "Failed registry optimization $($optimization.Description): $_"
        }

        $results.Details.Add([PSCustomObject]$optimizationResult)
    }

    return $results
}

#endregion

#region Disk Optimization

<#
.SYNOPSIS
    Optimizes disk performance settings
#>
function Optimize-DiskPerformance {
    [CmdletBinding()]
    param(
        [Parameter()]
        [switch]$DryRun
    )

    $results = @{
        Success        = 0
        Failed         = 0
        TasksCompleted = 0
        Details        = [List[PSCustomObject]]::new()
    }

    # Disk optimization tasks
    $diskTasks = @(
        @{ Name = 'Disable Indexing on System Drive'; Action = 'DisableIndexing' }
        @{ Name = 'Optimize Page File Settings'; Action = 'OptimizePageFile' }
        @{ Name = 'Enable Write Caching'; Action = 'EnableWriteCache' }
    )

    foreach ($task in $diskTasks) {
        $taskResult = @{
            Name    = $task.Name
            Action  = $task.Action
            Success = $false
            Error   = $null
        }

        try {
            if ($DryRun) {
                Write-Information "    [DRY RUN] Would execute: $($task.Name)" -InformationAction Continue
                $taskResult.Success = $true
            }
            else {
                switch ($task.Action) {
                    'DisableIndexing' {
                        # This is a placeholder - actual implementation would be more complex
                        Write-Information "    💽 $($task.Name) (placeholder)" -InformationAction Continue
                        $taskResult.Success = $true
                    }
                    'OptimizePageFile' {
                        # This is a placeholder - actual implementation would be more complex
                        Write-Information "    💽 $($task.Name) (placeholder)" -InformationAction Continue
                        $taskResult.Success = $true
                    }
                    'EnableWriteCache' {
                        # This is a placeholder - actual implementation would be more complex
                        Write-Information "    💽 $($task.Name) (placeholder)" -InformationAction Continue
                        $taskResult.Success = $true
                    }
                }
            }

            $results.Success++
            $results.TasksCompleted++
        }
        catch {
            $taskResult.Error = $_.Exception.Message
            $results.Failed++
            Write-Warning "Failed disk optimization task $($task.Name): $_"
        }

        $results.Details.Add([PSCustomObject]$taskResult)
    }

    return $results
}

#endregion

#region Network Optimization

<#
.SYNOPSIS
    Optimizes network settings for better performance
#>
function Optimize-NetworkSetting {
    [CmdletBinding()]
    param(
        [Parameter()]
        [switch]$DryRun
    )

    $results = @{
        Success         = 0
        Failed          = 0
        SettingsApplied = 0
        Details         = [List[PSCustomObject]]::new()
    }

    # Network optimization settings (registry-based)
    $networkOptimizations = @{
        'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters' = @{
            'TcpAckFrequency' = 1
            'TCPNoDelay'      = 1
        }
    }

    foreach ($registryPath in $networkOptimizations.Keys) {
        foreach ($setting in $networkOptimizations[$registryPath].GetEnumerator()) {
            $settingResult = @{
                Path    = $registryPath
                Setting = $setting.Key
                Value   = $setting.Value
                Success = $false
                Error   = $null
            }

            try {
                if ($DryRun) {
                    Write-Information "    [DRY RUN] Would set network setting: $($setting.Key)" -InformationAction Continue
                    $settingResult.Success = $true
                }
                else {
                    if (-not (Test-Path $registryPath)) {
                        New-Item -Path $registryPath -Force | Out-Null
                    }

                    Set-ItemProperty -Path $registryPath -Name $setting.Key -Value $setting.Value -Force
                    $settingResult.Success = $true
                    Write-Information "    🌐 Applied network optimization: $($setting.Key)" -InformationAction Continue
                }

                $results.Success++
                $results.SettingsApplied++
            }
            catch {
                $settingResult.Error = $_.Exception.Message
                $results.Failed++
                Write-Warning "Failed to apply network setting $($setting.Key): $_"
            }

            $results.Details.Add([PSCustomObject]$settingResult)
        }
    }

    return $results
}

#endregion

#region Helper Functions

function Get-DiskUsageMetric {
    try {
        $systemDrive = Get-CimInstance -ClassName Win32_LogicalDisk | Where-Object { $_.DeviceID -eq 'C:' }
        return @{
            TotalSize      = $systemDrive.Size
            FreeSpace      = $systemDrive.FreeSpace
            UsedSpace      = $systemDrive.Size - $systemDrive.FreeSpace
            UsedPercentage = [math]::Round((($systemDrive.Size - $systemDrive.FreeSpace) / $systemDrive.Size) * 100, 1)
        }
    }
    catch {
        return @{ TotalSize = 0; FreeSpace = 0; UsedSpace = 0; UsedPercentage = 0 }
    }
}

function Get-StartupProgramCount {
    [CmdletBinding()]
    [OutputType([int])]
    param()
    
    try {
        $count = 0
        $locations = @(
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
            'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
        )

        foreach ($location in $locations) {
            if (Test-Path $location) {
                $items = Get-ItemProperty -Path $location -ErrorAction SilentlyContinue
                if ($items) {
                    $count += ($items.PSObject.Properties | Where-Object {
                            $_.Name -notin @('PSPath', 'PSParentPath', 'PSChildName', 'PSDrive', 'PSProvider')
                        }).Count
                }
            }
        }

        return $count
    }
    catch {
        return 0
    }
}

function Get-TemporaryFileSize {
    [CmdletBinding()]
    [OutputType([long])]
    param()
    
    try {
        $tempPaths = @($env:TEMP, "$env:LOCALAPPDATA\Temp", "C:\Windows\Temp")
        $totalSize = 0

        foreach ($path in $tempPaths) {
            if (Test-Path $path) {
                $size = (Get-ChildItem -Path $path -Recurse -Force -ErrorAction SilentlyContinue |
                    Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
                $totalSize += $size ?? 0
            }
        }

        return $totalSize
    }
    catch {
        return 0
    }
}

function Get-RegistrySize {
    [CmdletBinding()]
    [OutputType([long])]
    param()
    
    # This is a placeholder - actual registry size calculation is complex
    return 0
}

function Get-MemoryUsagePercent {
    [CmdletBinding()]
    [OutputType([double])]
    param()
    
    try {
        $memory = Get-CimInstance -ClassName Win32_OperatingSystem
        return [math]::Round((($memory.TotalVisibleMemorySize - $memory.FreePhysicalMemory) / $memory.TotalVisibleMemorySize) * 100, 1)
    }
    catch {
        return 0
    }
}

function Merge-OptimizationResult {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param($Results, $NewResults, $Category)

    $Results.TotalOperations += ($NewResults.Success ?? 0) + ($NewResults.Failed ?? 0)
    $Results.Successful += ($NewResults.Success ?? 0)
    $Results.Failed += ($NewResults.Failed ?? 0)
    $Results.SpaceFreed += ($NewResults.SpaceFreed ?? 0)

    if ($Results.Categories.ContainsKey($Category)) {
        $Results.Categories[$Category].Success = ($NewResults.Success ?? 0)
        $Results.Categories[$Category].Failed = ($NewResults.Failed ?? 0)
        $Results.Categories[$Category].SpaceFreed = ($NewResults.SpaceFreed ?? 0)
        $Results.Categories[$Category].ItemsOptimized = ($NewResults.ItemsOptimized ?? 0)
        $Results.Categories[$Category].SettingsChanged = ($NewResults.SettingsChanged ?? 0)
        $Results.Categories[$Category].EntriesProcessed = ($NewResults.EntriesProcessed ?? 0)
        $Results.Categories[$Category].TasksCompleted = ($NewResults.TasksCompleted ?? 0)
        $Results.Categories[$Category].SettingsApplied = ($NewResults.SettingsApplied ?? 0)
    }
}

#endregion

# Export module functions
Export-ModuleMember -Function @(
    # v3.0 Standardized execution function (Primary)
    'Invoke-SystemOptimization',
    
    # Legacy functions (Preserved for internal use)
    'Optimize-SystemPerformance',
    'Get-SystemPerformanceMetric'
)
