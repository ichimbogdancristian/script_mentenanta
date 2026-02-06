#Requires -Version 7.0
# Module Dependencies:
#   - CoreInfrastructure.psm1 (configuration, logging, path management)
#   - SystemOptimizationAudit.psm1 (Type1 - detection/analysis)
#
# External Tools: None (uses native Windows APIs and registry)

<#
.SYNOPSIS
    System Optimization Module - Type 2 (System Modification)

.DESCRIPTION
    Comprehensive system performance optimization including disk cleanup, registry optimization,
    UI tweaks, and system configuration improvements for better performance.

.NOTES
    Module Type: Type 2 (System Modification)
    Dependencies: SystemOptimizationAudit.psm1, CoreInfrastructure.psm1
    Requires: Administrator privileges for system-wide optimizations
    Author: Windows Maintenance Automation Project
    Version: 1.0.0
#>

using namespace System.Collections.Generic

# v3.0 Self-contained Type 2 module with internal Type 1 dependency

# Step 1: Import core infrastructure FIRST (REQUIRED) - Global scope for Type1 access
$ModuleRoot = if ($PSScriptRoot) { Split-Path -Parent $PSScriptRoot } else { Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path) }
$CoreInfraPath = Join-Path $ModuleRoot 'core\CoreInfrastructure.psm1'
if (Test-Path $CoreInfraPath) {
    Import-Module $CoreInfraPath -Force -Global -WarningAction SilentlyContinue
}
else {
    throw "CoreInfrastructure module not found at: $CoreInfraPath - v3.0 requires proper module loading order"
}

# Step 2: Import corresponding Type 1 module AFTER CoreInfrastructure (REQUIRED)
$Type1ModulePath = Join-Path $ModuleRoot 'type1\SystemOptimizationAudit.psm1'
if (Test-Path $Type1ModulePath) {
    Import-Module $Type1ModulePath -Force
}
else {
    throw "Required Type 1 module not found: $Type1ModulePath"
}

# Note: System optimization primarily uses registry and Windows APIs
# No external package manager dependencies required

# Validate Type1 module loaded correctly
if (-not (Get-Command -Name 'Get-SystemOptimizationAnalysis' -ErrorAction SilentlyContinue)) {
    throw "Type 1 module functions not available - ensure SystemOptimizationAudit.psm1 is properly imported"
}

#region v3.0 Standardized Execution Function

<#
.SYNOPSIS
    Main execution function for system optimization - v3.0 Architecture Pattern
#>
function Invoke-SystemOptimization {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config,
        [Parameter()]
        [switch]$DryRun
    )

    $perfContext = $null
    try {
        $perfContext = Start-PerformanceTracking -OperationName 'SystemOptimization' -Component 'SYSTEM-OPTIMIZATION'
    }
    catch {
        Write-Verbose "Performance tracking initialization failed - continuing without it"
    }

    try {
        # Track execution duration for v3.0 compliance
        $executionStartTime = Get-Date

        # Display module banner
        Write-Host "`n" -NoNewline
        Write-Host "=================================================" -ForegroundColor Cyan
        Write-Host "  SYSTEM OPTIMIZATION MODULE v3.0" -ForegroundColor White
        Write-Host "=================================================" -ForegroundColor Cyan
        Write-Host "  Type: " -NoNewline -ForegroundColor Gray
        Write-Host "Type 2 (System Modification)" -ForegroundColor Yellow
        Write-Host "  Mode: " -NoNewline -ForegroundColor Gray
        Write-Host "$(if ($DryRun) { 'DRY-RUN (Simulation)' } else { 'LIVE EXECUTION' })" -ForegroundColor $(if ($DryRun) { 'Cyan' } else { 'Green' })
        Write-Host "=================================================" -ForegroundColor Cyan
        Write-Host ""

        # Initialize module execution environment
        Initialize-ModuleExecution -ModuleName 'SystemOptimization'

        Write-LogEntry -Level 'INFO' -Component 'SYSTEM-OPTIMIZATION' -Message 'Starting system optimization analysis'
        $analysisResults = Get-SystemOptimizationAnalysis

        $optimizationCount = if ($analysisResults -and $analysisResults.OptimizationOpportunities) { $analysisResults.OptimizationOpportunities.Count } else { 0 }

        if (-not $analysisResults -or $optimizationCount -eq 0) {
            Write-LogEntry -Level 'INFO' -Component 'SYSTEM-OPTIMIZATION' -Message 'No optimization opportunities detected'
            if ($perfContext) { Complete-PerformanceTracking -Context $perfContext -Status 'Success' | Out-Null }
            $executionTime = (Get-Date) - $executionStartTime
            return New-ModuleExecutionResult `
                -Success $true `
                -ItemsDetected 0 `
                -ItemsProcessed 0 `
                -DurationMilliseconds $executionTime.TotalMilliseconds `
                -LogPath "" `
                -ModuleName 'SystemOptimization' `
                -DryRun $DryRun.IsPresent
        }

        # STEP 3: Setup execution logging directory
        $executionLogPath = Get-SessionPath -Category 'logs' -SubCategory 'system-optimization' -FileName 'execution.log'
        $executionLogDir = Split-Path -Parent $executionLogPath


        Write-StructuredLogEntry -Level 'INFO' -Component 'SYSTEM-OPTIMIZATION' -Message "Detected $optimizationCount optimization opportunities" -LogPath $executionLogPath -Operation 'Detect' -Metadata @{ OpportunityCount = $optimizationCount }

        if ($DryRun) {
            Write-StructuredLogEntry -Level 'INFO' -Component 'SYSTEM-OPTIMIZATION' -Message ' DRY-RUN: Simulating system optimization' -LogPath $executionLogPath -Operation 'Simulate' -Metadata @{ DryRun = $true; ItemCount = $optimizationCount }
            $results = @{ ProcessedCount = $optimizationCount; Simulated = $true }
            [void]$results
            $processedCount = $optimizationCount
        }
        else {
            Write-StructuredLogEntry -Level 'INFO' -Component 'SYSTEM-OPTIMIZATION' -Message 'Executing enhanced system optimization' -LogPath $executionLogPath -Operation 'Execute' -Metadata @{ OpportunityCount = $optimizationCount }

            # Load enhanced configuration
            $enhancedConfig = Get-EnhancedOptimizationConfig
            $systemProfile = Get-SystemPerformanceProfile

            # Process optimization opportunities with enhanced logic
            $processedCount = 0
            $optimizationResults = @{
                Startup  = @{ Applied = 0; Failed = 0; Skipped = 0 }
                UI       = @{ Applied = 0; Failed = 0; Skipped = 0 }
                Disk     = @{ Applied = 0; Failed = 0; Skipped = 0; SpaceFreed = 0 }
                Registry = @{ Applied = 0; Failed = 0; Skipped = 0 }
                Network  = @{ Applied = 0; Failed = 0; Skipped = 0 }
                Modern   = @{ Applied = 0; Failed = 0; Skipped = 0 }
            }

            if ($analysisResults.OptimizationOpportunities) {
                # Group opportunities by category with enhanced processing
                $opportunitiesByCategory = $analysisResults.OptimizationOpportunities | Group-Object Category

                foreach ($categoryGroup in $opportunitiesByCategory) {
                    $category = $categoryGroup.Name
                    $opportunities = $categoryGroup.Group

                    Write-StructuredLogEntry -Level 'INFO' -Component 'SYSTEM-OPTIMIZATION' -Message "Processing $category optimizations" -LogPath $executionLogPath -Operation 'ProcessCategory' -Target $category -Metadata @{ OpportunityCount = $opportunities.Count }

                    try {
                        $categoryResult = switch ($category) {
                            'Startup' {
                                Invoke-EnhancedStartupOptimization -Opportunities $opportunities -Config $enhancedConfig -SystemProfile $systemProfile -LogPath $executionLogPath
                            }
                            'UI' {
                                Invoke-EnhancedUIOptimization -Opportunities $opportunities -Config $enhancedConfig -SystemProfile $systemProfile -LogPath $executionLogPath
                            }
                            'Disk' {
                                Invoke-EnhancedDiskOptimization -Opportunities $opportunities -Config $enhancedConfig -SystemProfile $systemProfile -LogPath $executionLogPath
                            }
                            'Registry' {
                                if ($enhancedConfig.systemOptimizations.registry.enabled) {
                                    Invoke-EnhancedRegistryOptimization -Opportunities $opportunities -Config $enhancedConfig -LogPath $executionLogPath
                                }
                                else {
                                    Write-StructuredLogEntry -Level 'INFO' -Component 'SYSTEM-OPTIMIZATION' -Message "Registry optimization disabled in configuration" -LogPath $executionLogPath -Operation 'Skip' -Target $category
                                    @{ Applied = 0; Failed = 0; Skipped = $opportunities.Count }
                                }
                            }
                            'Network' {
                                if ($enhancedConfig.systemOptimizations.network.enabled) {
                                    Invoke-EnhancedNetworkOptimization -Opportunities $opportunities -Config $enhancedConfig -LogPath $executionLogPath
                                }
                                else {
                                    Write-StructuredLogEntry -Level 'INFO' -Component 'SYSTEM-OPTIMIZATION' -Message "Network optimization disabled in configuration" -LogPath $executionLogPath -Operation 'Skip' -Target $category
                                    @{ Applied = 0; Failed = 0; Skipped = $opportunities.Count }
                                }
                            }
                            default {
                                Write-StructuredLogEntry -Level 'WARNING' -Component 'SYSTEM-OPTIMIZATION' -Message "Unknown optimization category: $category" -LogPath $executionLogPath -Operation 'ProcessCategory' -Target $category -Result 'Unknown'
                                @{ Applied = 0; Failed = $opportunities.Count; Skipped = 0 }
                            }
                        }

                        # Merge category results
                        $optimizationResults[$category] = $categoryResult
                        $processedCount += $categoryResult.Applied

                        if ($categoryResult.Applied -gt 0) {
                            Write-StructuredLogEntry -Level 'SUCCESS' -Component 'SYSTEM-OPTIMIZATION' -Message "Successfully applied $($categoryResult.Applied) $category optimizations" -LogPath $executionLogPath -Operation 'Apply' -Target $category -Result 'Success' -Metadata $categoryResult
                        }
                    }
                    catch {
                        $optimizationResults[$category].Failed += $opportunities.Count
                        Write-StructuredLogEntry -Level 'ERROR' -Component 'SYSTEM-OPTIMIZATION' -Message "Error processing $category optimizations: $($_.Exception.Message)" -LogPath $executionLogPath -Operation 'Apply' -Target $category -Result 'Error' -Metadata @{ Error = $_.Exception.Message; OpportunityCount = $opportunities.Count }
                    }
                }

                # Apply Windows 11 specific optimizations if detected
                if ($systemProfile.WindowsVersion -ge 11 -and $enhancedConfig.systemOptimizations.modern.windows11.enabled) {
                    try {
                        $modernResult = Invoke-ModernWindowsOptimization -Config $enhancedConfig -SystemProfile $systemProfile -LogPath $executionLogPath
                        $optimizationResults.Modern = $modernResult
                        $processedCount += $modernResult.Applied

                        if ($modernResult.Applied -gt 0) {
                            Write-StructuredLogEntry -Level 'SUCCESS' -Component 'SYSTEM-OPTIMIZATION' -Message "Applied $($modernResult.Applied) modern Windows optimizations" -LogPath $executionLogPath -Operation 'Apply' -Target 'Modern' -Result 'Success' -Metadata $modernResult
                        }
                    }
                    catch {
                        Write-StructuredLogEntry -Level 'ERROR' -Component 'SYSTEM-OPTIMIZATION' -Message "Error applying modern optimizations: $($_.Exception.Message)" -LogPath $executionLogPath -Operation 'Apply' -Target 'Modern' -Result 'Error' -Metadata @{ Error = $_.Exception.Message }
                    }
                }
            }
            $results = @{ ProcessedCount = $processedCount; AppliedOptimizations = $processedCount }
            [void]$results
        }

        Write-StructuredLogEntry -Level 'SUCCESS' -Component 'SYSTEM-OPTIMIZATION' -Message "System optimization completed: $processedCount optimizations applied" -LogPath $executionLogPath -Operation 'Complete' -Result 'Success' -Metadata @{ ProcessedCount = $processedCount; TotalOpportunities = $optimizationCount }

        # Create execution summary JSON
        $summaryPath = Join-Path $executionLogDir "execution-summary.json"
        $executionTime = (Get-Date) - $executionStartTime
        $executionSummary = @{
            ModuleName    = 'SystemOptimization'
            ExecutionTime = @{
                Start      = $executionStartTime.ToString('o')
                End        = (Get-Date).ToString('o')
                DurationMs = $executionTime.TotalMilliseconds
            }
            Results       = @{
                Success        = $true
                ItemsDetected  = $optimizationCount
                ItemsProcessed = $processedCount
                ItemsFailed    = 0
                ItemsSkipped   = ($optimizationCount - $processedCount)
            }
            ExecutionMode = if ($DryRun) { 'DryRun' } else { 'Live' }
            LogFiles      = @{
                TextLog = $executionLogPath
                JsonLog = $executionLogPath -replace '\.log$', '-data.json'
                Summary = $summaryPath
            }
            SessionInfo   = @{
                SessionId    = $env:MAINTENANCE_SESSION_ID
                ComputerName = $env:COMPUTERNAME
                UserName     = $env:USERNAME
                PSVersion    = $PSVersionTable.PSVersion.ToString()
            }
        }

        try {
            $executionSummary | ConvertTo-Json -Depth 10 | Set-Content $summaryPath -Force
            Write-Verbose "Execution summary saved to: $summaryPath"
        }
        catch {
            Write-Warning "Failed to create execution summary: $($_.Exception.Message)"
        }

        $returnData = New-ModuleExecutionResult `
            -Success $true `
            -ItemsDetected $optimizationCount `
            -ItemsProcessed $processedCount `
            -DurationMilliseconds $executionTime.TotalMilliseconds `
            -LogPath $executionLogPath `
            -ModuleName 'SystemOptimization' `
            -DryRun $DryRun.IsPresent

        Write-LogEntry -Level 'SUCCESS' -Component 'SYSTEM-OPTIMIZATION' -Message "System optimization completed. Processed: $processedCount/$optimizationCount"
        if ($perfContext) { Complete-PerformanceTracking -Context $perfContext -Status 'Success' | Out-Null }
        return $returnData

    }
    catch {
        $errorMsg = "Failed to execute system optimization: $($_.Exception.Message)"
        Write-LogEntry -Level 'ERROR' -Component 'SYSTEM-OPTIMIZATION' -Message $errorMsg -Data @{ Error = $_.Exception }
        if ($perfContext) { Complete-PerformanceTracking -Context $perfContext -Status 'Failed' -ErrorMessage $errorMsg | Out-Null }

        $executionTime = if ($executionStartTime) { (Get-Date) - $executionStartTime } else { New-TimeSpan }
        return New-ModuleExecutionResult `
            -Success $false `
            -ItemsDetected (if ($analysisResults -and $analysisResults.OptimizationOpportunities) { $analysisResults.OptimizationOpportunities.Count } else { 0 }) `
            -ItemsProcessed 0 `
            -DurationMilliseconds $executionTime.TotalMilliseconds `
            -LogPath $executionLogPath `
            -ModuleName 'SystemOptimization' `
            -ErrorMessage $errorMsg
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
# DEPRECATED: Legacy function maintained for backward compatibility
# Use Invoke-SystemOptimization instead (v3.0 API with enhanced optimization logic)
function Optimize-SystemPerformance {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([bool])]
    [Obsolete("This function is deprecated. Use Invoke-SystemOptimization instead. Will be removed in v4.0.", false)]
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

    Write-Information " Starting comprehensive system optimization..." -InformationAction Continue
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
        Write-Verbose "SYSTEM-OPTIMIZATION: Logging initialization failed - $_"
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
        Write-Information "   DRY RUN MODE - No changes will be applied" -InformationAction Continue
    }

    # Initialize results tracking
    $results = @{
        TotalOperations = 0
        Successful      = 0
        Failed          = 0
        SpaceFreed      = 0
        DryRun          = $DryRun.IsPresent
        Details         = [System.Collections.ArrayList]::new()
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
            Write-Information "   Cleaning temporary files..." -InformationAction Continue
            $tempResults = Clear-TemporaryFile -DryRun:$DryRun
            Merge-OptimizationResult -Results $results -NewResults $tempResults -Category 'TempCleanup'
        }

        # Startup optimization (default: enabled)
        if ($OptimizeStartup -or (-not $PSBoundParameters.ContainsKey('OptimizeStartup'))) {
            Write-Information "   Optimizing startup programs..." -InformationAction Continue
            $startupResults = Optimize-StartupProgram -DryRun:$DryRun
            Merge-OptimizationResult -Results $results -NewResults $startupResults -Category 'StartupOptimization'
        }

        # UI optimization (default: enabled)
        if ($OptimizeUI -or (-not $PSBoundParameters.ContainsKey('OptimizeUI'))) {
            Write-Information "   Optimizing user interface..." -InformationAction Continue
            $uiResults = Optimize-UserInterface -DryRun:$DryRun
            Merge-OptimizationResult -Results $results -NewResults $uiResults -Category 'UIOptimization'
        }

        # Registry optimization (default: disabled)
        if ($OptimizeRegistry) {
            Write-Information "   Optimizing registry..." -InformationAction Continue
            $registryResults = Optimize-WindowsRegistry -DryRun:$DryRun
            Merge-OptimizationResult -Results $results -NewResults $registryResults -Category 'RegistryOptimization'
        }

        # Disk optimization (default: enabled)
        if ($OptimizeDisk -or (-not $PSBoundParameters.ContainsKey('OptimizeDisk'))) {
            Write-Information "   Optimizing disk performance..." -InformationAction Continue
            $diskResults = Optimize-DiskPerformance -DryRun:$DryRun
            Merge-OptimizationResult -Results $results -NewResults $diskResults -Category 'DiskOptimization'
        }

        # Network optimization (default: disabled)
        if ($OptimizeNetwork) {
            Write-Information "   Optimizing network settings..." -InformationAction Continue
            $networkResults = Optimize-NetworkSetting -DryRun:$DryRun
            Merge-OptimizationResult -Results $results -NewResults $networkResults -Category 'NetworkOptimization'
        }

        $duration = ((Get-Date) - $startTime).TotalSeconds
        $spaceFreedMB = [math]::Round($results.SpaceFreed / 1MB, 2)

        # Summary output
        $statusIcon = if ($results.Failed -eq 0) { "" } else { "" }
        Write-Information "  $statusIcon System optimization completed in $([math]::Round($duration, 2))s" -InformationAction Continue
        Write-Information "     Operations: $($results.TotalOperations), Successful: $($results.Successful), Failed: $($results.Failed)" -InformationAction Continue

        if ($results.SpaceFreed -gt 0) {
            Write-Information "     Disk space freed: ${spaceFreedMB} MB" -InformationAction Continue
        }

        $success = $results.Failed -eq 0 -and $results.Successful -gt 0
        if (-not $success) {
            Write-Information "     Some optimizations failed. Check logs for details." -InformationAction Continue
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
            } | Out-Null
            Write-LogEntry -Level $(if ($success) { 'SUCCESS' } else { 'WARNING' }) -Component 'SYSTEM-OPTIMIZATION' -Message 'System optimization operation completed' -Data $results
        }
        catch {
            Write-Verbose "SYSTEM-OPTIMIZATION: Logging completion failed - $_"
            # LoggingManager not available, continue with standard logging
        }

        # Log detailed results for audit trails
        Write-Verbose "System optimization operation details: $(ConvertTo-Json $results -Depth 3)"
        Write-Verbose "System optimization completed successfully"

        return $success
    }
    catch {
        $errorMessage = " System optimization failed: $($_.Exception.Message)"
        Write-Error $errorMessage
        Write-Verbose "Error details: $($_.Exception.ToString())"

        # Complete performance tracking for failed operation
        try {
            Complete-PerformanceTracking -PerformanceContext $perfContext -Success $false -ResultData @{ Error = $_.Exception.Message } | Out-Null
            Write-LogEntry -Level 'ERROR' -Component 'SYSTEM-OPTIMIZATION' -Message 'System optimization operation failed' -Data @{ Error = $_.Exception.Message; ErrorType = $_.Exception.GetType().Name }
        }
        catch {
            Write-Verbose "SYSTEM-OPTIMIZATION: Error logging failed - $_"
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
    Write-Information "   Disk Usage: $($metrics.DiskUsage.UsedPercentage)%" -InformationAction Continue
    Write-Information "   Startup Programs: $($metrics.StartupPrograms)" -InformationAction Continue
    Write-Information "    Temporary Files: $([math]::Round($metrics.TemporaryFiles/1MB)) MB" -InformationAction Continue
    Write-Information "   Recommendations: $($metrics.Recommendations.Count)" -InformationAction Continue

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
        Details    = [System.Collections.ArrayList]::new()
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
                    Write-Information "     Cleaned $($target.Name): $([math]::Round($cleanupResult.SpaceFreed/1MB, 2)) MB" -InformationAction Continue
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
# DEPRECATED: Legacy function for backward compatibility
# Use Invoke-SystemOptimization which calls Invoke-EnhancedStartupOptimization internally
function Optimize-StartupProgram {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([hashtable])]
    [Obsolete("This function is deprecated. Use Invoke-SystemOptimization instead. Will be removed in v4.0.", false)]
    param(
        [Parameter()]
        [switch]$DryRun
    )

    $results = @{
        Success        = 0
        Failed         = 0
        ItemsOptimized = 0
        Details        = [System.Collections.ArrayList]::new()
    }

    # Get startup programs from registry
    $startupLocations = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce'
    )

    # v3.0 compliance: Get safe-to-disable startup programs from configuration
    try {
        $optimizationConfig = Get-SystemOptimizationConfiguration
        $safeToDisable = $optimizationConfig.startupPrograms.safeToDisablePatterns
        if (-not $safeToDisable) {
            # Fallback to defaults if config not available
            $safeToDisable = @('*Updater*', '*Update*Helper*', '*AutoUpdate*', '*UpdateChecker*')
        }
    }
    catch {
        Write-LogEntry -Level 'WARNING' -Component 'SYSTEM-OPTIMIZATION' -Message "Failed to load optimization config, using defaults: $_"
        $safeToDisable = @('*Updater*', '*Update*Helper*', '*AutoUpdate*', '*UpdateChecker*')
    }

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
                            $operationStart = Get-Date
                            $optimizationResult = @{
                                Name     = $itemName
                                Value    = $itemValue
                                Location = $location
                                Action   = 'Disabled'
                                Success  = $false
                            }

                            try {
                                # Enhanced logging: Pre-action state
                                Write-OperationStart -Component 'SYSTEM-OPTIMIZATION' -Operation 'Disable' -Target $itemName -AdditionalInfo @{
                                    Location = $location
                                    Value    = $itemValue
                                    Type     = 'StartupProgram'
                                }

                                if ($DryRun) {
                                    Write-Information "    [DRY RUN] Would disable startup item: $itemName" -InformationAction Continue
                                    Write-OperationSkipped -Component 'SYSTEM-OPTIMIZATION' -Operation 'Disable' -Target $itemName -Reason 'DryRun mode enabled'
                                    $optimizationResult.Success = $true
                                }
                                else {
                                    # Backup the value before removing
                                    $backupPath = "$location\Backup"
                                    if (-not (Test-Path $backupPath)) {
                                        New-Item -Path $backupPath -Force | Out-Null
                                    }
                                    Write-LogEntry -Level 'INFO' -Component 'SYSTEM-OPTIMIZATION' -Message "Backing up startup item to: $backupPath"
                                    Set-ItemProperty -Path $backupPath -Name $itemName -Value $itemValue -Force

                                    # Remove from startup
                                    Write-LogEntry -Level 'INFO' -Component 'SYSTEM-OPTIMIZATION' -Message "Executing: Remove-ItemProperty -Path $location -Name $itemName"
                                    Remove-ItemProperty -Path $location -Name $itemName -Force

                                    # Verification
                                    $stillExists = Get-ItemProperty -Path $location -Name $itemName -ErrorAction SilentlyContinue
                                    $operationDuration = ((Get-Date) - $operationStart).TotalSeconds

                                    if (-not $stillExists) {
                                        Write-OperationSuccess -Component 'SYSTEM-OPTIMIZATION' -Operation 'Disable' -Target $itemName -Metrics @{
                                            Duration = $operationDuration
                                            Location = $location
                                            BackedUp = $true
                                            Verified = $true
                                        }
                                        $optimizationResult.Success = $true
                                        Write-Information "     Disabled startup item: $itemName (${operationDuration}s)" -InformationAction Continue
                                    }
                                    else {
                                        throw "Verification failed: Item still exists after removal"
                                    }
                                }

                                $results.Success++
                                $results.ItemsOptimized++
                            }
                            catch {
                                $optimizationResult.Error = $_.Exception.Message
                                $results.Failed++
                                Write-OperationFailure -Component 'SYSTEM-OPTIMIZATION' -Operation 'Disable' -Target $itemName -Error $_
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
# DEPRECATED: Legacy function for backward compatibility
# Use Invoke-SystemOptimization which calls Invoke-EnhancedUIOptimization internally
function Optimize-UserInterface {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([hashtable])]
    [Obsolete("This function is deprecated. Use Invoke-SystemOptimization instead. Will be removed in v4.0.", false)]
    param(
        [Parameter()]
        [switch]$DryRun
    )

    $results = @{
        Success         = 0
        Failed          = 0
        SettingsChanged = 0
        Details         = [System.Collections.ArrayList]::new()
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
            $operationStart = Get-Date
            $settingResult = @{
                Path    = $registryPath
                Setting = $setting.Key
                Value   = $setting.Value
                Success = $false
                Error   = $null
            }

            try {
                # Enhanced logging: Pre-action state
                $oldValue = $null
                if (Test-Path $registryPath) {
                    $oldValue = (Get-ItemProperty -Path $registryPath -Name $setting.Key -ErrorAction SilentlyContinue).($setting.Key)
                }

                Write-OperationStart -Component 'SYSTEM-OPTIMIZATION' -Operation 'Modify' -Target "$registryPath\$($setting.Key)" -AdditionalInfo @{
                    OldValue = $oldValue
                    NewValue = $setting.Value
                    Type     = 'UIOptimization'
                }

                if ($DryRun) {
                    Write-Information "    [DRY RUN] Would set $($setting.Key) = $($setting.Value) in $registryPath" -InformationAction Continue
                    Write-OperationSkipped -Component 'SYSTEM-OPTIMIZATION' -Operation 'Modify' -Target "$registryPath\$($setting.Key)" -Reason 'DryRun mode enabled'
                    $settingResult.Success = $true
                }
                else {
                    # Ensure registry path exists
                    if (-not (Test-Path $registryPath)) {
                        Write-LogEntry -Level 'INFO' -Component 'SYSTEM-OPTIMIZATION' -Message "Creating registry path: $registryPath"
                        New-Item -Path $registryPath -Force | Out-Null
                    }

                    # Set the value
                    Write-LogEntry -Level 'INFO' -Component 'SYSTEM-OPTIMIZATION' -Message "Executing: Set-ItemProperty -Path $registryPath -Name $($setting.Key) -Value $($setting.Value)"
                    Set-ItemProperty -Path $registryPath -Name $setting.Key -Value $setting.Value -Force

                    # Verification
                    Write-StructuredLogEntry -Level 'INFO' -Component 'SYSTEM-OPTIMIZATION' -Operation 'Verify' -Target "$registryPath\$($setting.Key)" -Message 'Verifying registry value change'

                    $newValue = (Get-ItemProperty -Path $registryPath -Name $setting.Key -ErrorAction SilentlyContinue).($setting.Key)
                    $operationDuration = ((Get-Date) - $operationStart).TotalSeconds

                    if ($newValue -eq $setting.Value) {
                        # Log successful verification
                        Write-OperationSuccess -Component 'SYSTEM-OPTIMIZATION' -Operation 'Verify' -Target "$registryPath\$($setting.Key)" -Metrics @{
                            ExpectedValue      = $setting.Value
                            ActualValue        = $newValue
                            VerificationPassed = $true
                        }

                        # Log successful modification
                        Write-OperationSuccess -Component 'SYSTEM-OPTIMIZATION' -Operation 'Modify' -Target "$registryPath\$($setting.Key)" -Metrics @{
                            Duration = $operationDuration
                            OldValue = $oldValue
                            NewValue = $newValue
                            Verified = $true
                        }
                        $settingResult.Success = $true
                        Write-Information "     Applied UI optimization: $($setting.Key) (${operationDuration}s)" -InformationAction Continue
                    }
                    else {
                        # Log failed verification
                        Write-OperationFailure -Component 'SYSTEM-OPTIMIZATION' -Operation 'Verify' -Target "$registryPath\$($setting.Key)" -Error (New-Object Exception("Expected value: $($setting.Value), Actual value: $newValue"))
                        throw "Verification failed: Value not set correctly"
                    }
                }

                $results.Success++
                $results.SettingsChanged++
            }
            catch {
                $settingResult.Error = $_.Exception.Message
                $results.Failed++
                Write-OperationFailure -Component 'SYSTEM-OPTIMIZATION' -Operation 'Modify' -Target "$registryPath\$($setting.Key)" -Error $_
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
# DEPRECATED: Legacy function for backward compatibility
# Use Invoke-SystemOptimization which calls Invoke-EnhancedRegistryOptimization internally
function Optimize-WindowsRegistry {
    [CmdletBinding()]
    [Obsolete("This function is deprecated. Use Invoke-SystemOptimization instead. Will be removed in v4.0.", false)]
    param(
        [Parameter()]
        [switch]$DryRun
    )

    $results = @{
        Success          = 0
        Failed           = 0
        EntriesProcessed = 0
        Details          = [System.Collections.ArrayList]::new()
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
                    Write-Information "     $($optimization.Description)" -InformationAction Continue
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
# DEPRECATED: Legacy function for backward compatibility
# Use Invoke-SystemOptimization which calls Invoke-EnhancedDiskOptimization internally
function Optimize-DiskPerformance {
    [CmdletBinding()]
    [Obsolete("This function is deprecated. Use Invoke-SystemOptimization instead. Will be removed in v4.0.", false)]
    param(
        [Parameter()]
        [switch]$DryRun
    )

    $results = @{
        Success        = 0
        Failed         = 0
        TasksCompleted = 0
        Details        = [System.Collections.ArrayList]::new()
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
                        Write-Information "     $($task.Name) (placeholder)" -InformationAction Continue
                        $taskResult.Success = $true
                    }
                    'OptimizePageFile' {
                        # This is a placeholder - actual implementation would be more complex
                        Write-Information "     $($task.Name) (placeholder)" -InformationAction Continue
                        $taskResult.Success = $true
                    }
                    'EnableWriteCache' {
                        # This is a placeholder - actual implementation would be more complex
                        Write-Information "     $($task.Name) (placeholder)" -InformationAction Continue
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
# DEPRECATED: Legacy function for backward compatibility
# Use Invoke-SystemOptimization which calls Invoke-EnhancedNetworkOptimization internally
function Optimize-NetworkSetting {
    [CmdletBinding()]
    [Obsolete("This function is deprecated. Use Invoke-SystemOptimization instead. Will be removed in v4.0.", false)]
    param(
        [Parameter()]
        [switch]$DryRun
    )

    $results = @{
        Success         = 0
        Failed          = 0
        SettingsApplied = 0
        Details         = [System.Collections.ArrayList]::new()
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
                    Write-Information "     Applied network optimization: $($setting.Key)" -InformationAction Continue
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

<#
.SYNOPSIS
    Merges optimization results into consolidated results object

.DESCRIPTION
    Combines optimization results from a specific category into the main results object.
    Aggregates counters (successful, failed operations), tracks space freed, and updates
    category-specific statistics for performance analysis.

.PARAMETER Results
    Main results hashtable to merge into (contains aggregated totals and categories)

.PARAMETER NewResults
    New results from an optimization operation to add (contains success/failed counts, space freed)

.PARAMETER Category
    Name of the optimization category being processed (e.g., 'DiskCleanup', 'MemoryOptimization')

.OUTPUTS
    [hashtable] Modified Results object with updated statistics (passed by reference)

.EXAMPLE
    PS> $mainResults = @{ TotalOperations = 0; Successful = 0; Failed = 0; SpaceFreed = 0; Categories = @{} }
    PS> $diskResults = @{ Success = 5; Failed = 1; SpaceFreed = 2GB }
    PS> Merge-OptimizationResult -Results $mainResults -NewResults $diskResults -Category 'DiskCleanup'

    Adds disk cleanup results to main results, updating category-specific statistics.

.NOTES
    Used internally for aggregating results from multiple optimization categories.
    Updates both global totals and per-category statistics in place.
#>
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

#region Enhanced Optimization Functions (v3.1)

<#
.SYNOPSIS
    Gets enhanced optimization configuration with system adaptation
#>
function Get-EnhancedOptimizationConfig {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    try {
        $configRoot = $null
        if (Get-Command 'Get-MaintenancePath' -ErrorAction SilentlyContinue) {
            $configRoot = Get-MaintenancePath 'ConfigRoot'
        }
        elseif ($env:MAINTENANCE_CONFIG_ROOT) {
            $configRoot = $env:MAINTENANCE_CONFIG_ROOT
        }
        else {
            $configRoot = Join-Path $PSScriptRoot '..\..\config'
        }

        $candidatePaths = @(
            'lists\system-optimization\system-optimization-config.json',  # Phase 3
            'lists\system-optimization-enhanced.json',                     # Legacy
            'lists\system-optimization-config.json',                       # Legacy
            'settings\system-optimization-enhanced.json'                   # Legacy
        )

        foreach ($relativePath in $candidatePaths) {
            $configPath = Join-Path $configRoot $relativePath
            if (Test-Path $configPath) {
                $config = Get-Content $configPath -Raw | ConvertFrom-Json
                Write-Verbose "Loaded optimization configuration from: $configPath"

                if ($config.PSObject.Properties.Name -contains 'systemOptimizations') {
                    return $config
                }

                # Map legacy list-based config into enhanced schema
                $defaultConfig = [PSCustomObject]@{
                    systemOptimizations   = [PSCustomObject]@{
                        startup  = [PSCustomObject]@{ enabled = $true; aggressiveMode = $false; safeToDisablePatterns = @(); neverDisablePatterns = @() }
                        ui       = [PSCustomObject]@{
                            enabled = $true
                            profileBased = $true
                            profiles = [PSCustomObject]@{
                                balanced    = [PSCustomObject]@{ disableAnimations = $false; useSmallTaskbarIcons = $false; hideSearchBox = $false; disableVisualEffects = $false }
                                performance = [PSCustomObject]@{ disableAnimations = $true; useSmallTaskbarIcons = $true; hideSearchBox = $true; disableVisualEffects = $true }
                            }
                        }
                        disk     = [PSCustomObject]@{ enabled = $true; cleanupTargets = @() }
                        registry = [PSCustomObject]@{ enabled = $false; safeOptimizations = @() }
                        network  = [PSCustomObject]@{ enabled = $false; tcpOptimizations = [PSCustomObject]@{ enabled = $false; settings = @{} }; dnsOptimizations = [PSCustomObject]@{ enabled = $false; flushDNSCache = $false } }
                        modern   = [PSCustomObject]@{ windows11 = [PSCustomObject]@{ enabled = $true; optimizations = @() } }
                    }
                    performanceThresholds = [PSCustomObject]@{
                        diskSpace = [PSCustomObject]@{ critical = 5; warning = 15; optimal = 25 }
                        memory    = [PSCustomObject]@{ high = 85; warning = 70; optimal = 60 }
                        startup   = [PSCustomObject]@{ tooMany = 15; optimal = 8; minimal = 5 }
                    }
                    adaptiveSettings      = [PSCustomObject]@{ enabled = $true }
                }

                if ($config.startupPrograms) {
                    $defaultConfig.systemOptimizations.startup.safeToDisablePatterns = $config.startupPrograms.safeToDisablePatterns
                    $defaultConfig.systemOptimizations.startup.neverDisablePatterns = $config.startupPrograms.neverDisable
                }

                if ($config.visualEffects -and $config.visualEffects.performance) {
                    $defaultConfig.systemOptimizations.ui.profiles.performance.disableAnimations = -not [bool]$config.visualEffects.performance.animations
                    $defaultConfig.systemOptimizations.ui.profiles.performance.disableVisualEffects = -not [bool]$config.visualEffects.performance.shadows
                }

                return $defaultConfig
            }
        }
    }
    catch {
        Write-Warning "Failed to load enhanced configuration: $($_.Exception.Message)"
    }

    # Return minimal default configuration if file not found
    return @{
        systemOptimizations   = @{
            startup  = @{ enabled = $true; aggressiveMode = $false }
            ui       = @{ enabled = $true; profileBased = $true }
            disk     = @{ enabled = $true }
            registry = @{ enabled = $false }
            network  = @{ enabled = $false }
            modern   = @{ windows11 = @{ enabled = $true } }
        }
        performanceThresholds = @{
            diskSpace = @{ critical = 5; warning = 15; optimal = 25 }
            memory    = @{ high = 85; warning = 70; optimal = 60 }
            startup   = @{ tooMany = 15; optimal = 8; minimal = 5 }
        }
        adaptiveSettings      = @{ enabled = $true }
    }
}

<#
.SYNOPSIS
    Determines system performance profile for adaptive optimization
#>
function Get-SystemPerformanceProfile {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    try {
        $computerInfo = Get-ComputerInfo -Property TotalPhysicalMemory, CsProcessors
        $ramGB = [math]::Round($computerInfo.TotalPhysicalMemory / 1GB, 2)
        $cpuCores = $computerInfo.CsProcessors.Count
        $osVersion = [Environment]::OSVersion.Version

        # Determine performance profile
        $performanceProfile = 'midRange'
        if ($ramGB -le 8 -or $cpuCores -le 4) {
            $performanceProfile = 'lowEnd'
        }
        elseif ($ramGB -ge 32 -and $cpuCores -ge 12) {
            $performanceProfile = 'highEnd'
        }

        return @{
            RAM            = $ramGB
            CPUCores       = $cpuCores
            WindowsVersion = $osVersion.Major
            WindowsBuild   = $osVersion.Build
            Profile        = $performanceProfile
            IsLowEnd       = ($performanceProfile -eq 'lowEnd')
            IsHighEnd      = ($performanceProfile -eq 'highEnd')
        }
    }
    catch {
        Write-Warning "Failed to determine system profile: $($_.Exception.Message)"
        return @{
            RAM            = 8
            CPUCores       = 4
            WindowsVersion = 10
            WindowsBuild   = 19044
            Profile        = 'midRange'
            IsLowEnd       = $false
            IsHighEnd      = $false
        }
    }
}

<#
.SYNOPSIS
    Enhanced startup optimization with intelligent pattern matching
#>
function Invoke-EnhancedStartupOptimization {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [array]$Opportunities,

        [Parameter(Mandatory)]
        [PSCustomObject]$Config,

        [Parameter(Mandatory)]
        [PSCustomObject]$SystemProfile,

        [Parameter(Mandatory)]
        [string]$LogPath
    )

    $results = @{ Applied = 0; Failed = 0; Skipped = 0 }
    $startupConfig = $Config.systemOptimizations.startup

    if (-not $startupConfig.enabled) {
        Write-StructuredLogEntry -Level 'INFO' -Component 'SYSTEM-OPTIMIZATION' -Message "Startup optimization disabled in configuration" -LogPath $LogPath
        $results.Skipped = $Opportunities.Count
        return $results
    }

    Write-StructuredLogEntry -Level 'INFO' -Component 'SYSTEM-OPTIMIZATION' -Message "Starting enhanced startup optimization" -LogPath $LogPath -Metadata @{ OpportunityCount = $Opportunities.Count; SystemProfile = $SystemProfile.Profile }

    foreach ($opportunity in $Opportunities) {
        try {
            $shouldOptimize = $false
            $reason = ""

            # Enhanced pattern matching
            foreach ($pattern in $startupConfig.safeToDisablePatterns) {
                if ($opportunity.Target -like $pattern) {
                    $shouldOptimize = $true
                    $reason = "Matched safe-to-disable pattern: $pattern"
                    break
                }
            }

            # Safety check - never disable critical items
            foreach ($pattern in $startupConfig.neverDisablePatterns) {
                if ($opportunity.Target -like $pattern) {
                    $shouldOptimize = $false
                    $reason = "Matched never-disable pattern: $pattern"
                    break
                }
            }

            # Adaptive optimization based on system profile
            if ($SystemProfile.IsLowEnd -and $startupConfig.aggressiveMode) {
                # More aggressive on low-end systems
                if ($opportunity.Impact -eq 'Medium' -and -not $shouldOptimize) {
                    $shouldOptimize = $true
                    $reason = "Aggressive mode for low-end system"
                }
            }

            if ($shouldOptimize) {
                if ($opportunity.Type -eq 'DisableStartupApp') {
                    $optimizeResult = Disable-StartupApplication -AppName $opportunity.Target -Reason $reason -LogPath $LogPath
                    if ($optimizeResult) {
                        $results.Applied++
                        Write-StructuredLogEntry -Level 'SUCCESS' -Component 'SYSTEM-OPTIMIZATION' -Message "Disabled startup app: $($opportunity.Target)" -LogPath $LogPath -Operation 'Disable' -Target $opportunity.Target -Result 'Success' -Metadata @{ Reason = $reason }
                    }
                    else {
                        $results.Failed++
                        Write-StructuredLogEntry -Level 'ERROR' -Component 'SYSTEM-OPTIMIZATION' -Message "Failed to disable startup app: $($opportunity.Target)" -LogPath $LogPath -Operation 'Disable' -Target $opportunity.Target -Result 'Failed'
                    }
                }
                elseif ($opportunity.Type -eq 'OptimizeService') {
                    $optimizeResult = Optimize-WindowsService -ServiceName $opportunity.Target -Reason $reason -LogPath $LogPath
                    if ($optimizeResult) {
                        $results.Applied++
                        Write-StructuredLogEntry -Level 'SUCCESS' -Component 'SYSTEM-OPTIMIZATION' -Message "Optimized service: $($opportunity.Target)" -LogPath $LogPath -Operation 'Optimize' -Target $opportunity.Target -Result 'Success' -Metadata @{ Reason = $reason }
                    }
                    else {
                        $results.Failed++
                        Write-StructuredLogEntry -Level 'ERROR' -Component 'SYSTEM-OPTIMIZATION' -Message "Failed to optimize service: $($opportunity.Target)" -LogPath $LogPath -Operation 'Optimize' -Target $opportunity.Target -Result 'Failed'
                    }
                }
            }
            else {
                $results.Skipped++
                Write-StructuredLogEntry -Level 'INFO' -Component 'SYSTEM-OPTIMIZATION' -Message "Skipped startup item: $($opportunity.Target)" -LogPath $LogPath -Operation 'Skip' -Target $opportunity.Target -Metadata @{ Reason = $reason }
            }
        }
        catch {
            $results.Failed++
            Write-StructuredLogEntry -Level 'ERROR' -Component 'SYSTEM-OPTIMIZATION' -Message "Error processing startup opportunity: $($_.Exception.Message)" -LogPath $LogPath -Operation 'Process' -Target $opportunity.Target -Result 'Error' -Metadata @{ Error = $_.Exception.Message }
        }
    }

    return $results
}

<#
.SYNOPSIS
    Enhanced UI optimization with profile-based settings
#>
function Invoke-EnhancedUIOptimization {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [array]$Opportunities,

        [Parameter(Mandatory)]
        [PSCustomObject]$Config,

        [Parameter(Mandatory)]
        [PSCustomObject]$SystemProfile,

        [Parameter(Mandatory)]
        [string]$LogPath
    )

    $results = @{ Applied = 0; Failed = 0; Skipped = 0 }
    $uiConfig = $Config.systemOptimizations.ui

    if (-not $uiConfig.enabled) {
        $results.Skipped = $Opportunities.Count
        return $results
    }

    # Select profile based on system capabilities
    $selectedProfile = 'balanced'
    if ($SystemProfile.IsLowEnd) {
        $selectedProfile = 'performance'
    }

    $profileSettings = $uiConfig.profiles.$selectedProfile

    Write-StructuredLogEntry -Level 'INFO' -Component 'SYSTEM-OPTIMIZATION' -Message "Applying UI optimizations with profile: $selectedProfile" -LogPath $LogPath -Metadata @{ Profile = $selectedProfile; SystemProfile = $SystemProfile.Profile }

    # Apply UI optimizations based on profile
    $uiOptimizations = @{
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' = @{}
        'HKCU:\Control Panel\Desktop'                                       = @{}
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search'            = @{}
    }

    # Configure based on profile
    if ($profileSettings.disableAnimations) {
        $uiOptimizations['HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced']['TaskbarAnimations'] = 0
        $uiOptimizations['HKCU:\Control Panel\Desktop']['MenuShowDelay'] = '0'
        $uiOptimizations['HKCU:\Control Panel\Desktop\WindowMetrics'] = @{ 'MinAnimate' = '0' }
    }

    if ($profileSettings.useSmallTaskbarIcons) {
        $uiOptimizations['HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced']['TaskbarSmallIcons'] = 1
    }

    if ($profileSettings.hideSearchBox) {
        $uiOptimizations['HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search']['SearchboxTaskbarMode'] = 0
    }

    if ($profileSettings.disableVisualEffects) {
        $uiOptimizations['HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects'] = @{ 'VisualFXSetting' = 2 }
        $uiOptimizations['HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced']['ListviewShadow'] = 0
    }

    # Apply the optimizations
    foreach ($registryPath in $uiOptimizations.Keys) {
        foreach ($setting in $uiOptimizations[$registryPath].GetEnumerator()) {
            try {
                if (-not (Test-Path $registryPath)) {
                    New-Item -Path $registryPath -Force | Out-Null
                }

                Set-ItemProperty -Path $registryPath -Name $setting.Key -Value $setting.Value -Force

                # Verify the change
                $newValue = (Get-ItemProperty -Path $registryPath -Name $setting.Key -ErrorAction SilentlyContinue).($setting.Key)
                if ($newValue -eq $setting.Value) {
                    $results.Applied++
                    Write-StructuredLogEntry -Level 'SUCCESS' -Component 'SYSTEM-OPTIMIZATION' -Message "Applied UI setting: $($setting.Key)" -LogPath $LogPath -Operation 'Apply' -Target "$registryPath\$($setting.Key)" -Result 'Success' -Metadata @{ OldValue = $null; NewValue = $newValue; Profile = $selectedProfile }
                }
                else {
                    $results.Failed++
                    Write-StructuredLogEntry -Level 'ERROR' -Component 'SYSTEM-OPTIMIZATION' -Message "Failed to verify UI setting: $($setting.Key)" -LogPath $LogPath -Operation 'Apply' -Target "$registryPath\$($setting.Key)" -Result 'Failed' -Metadata @{ ExpectedValue = $setting.Value; ActualValue = $newValue }
                }
            }
            catch {
                $results.Failed++
                Write-StructuredLogEntry -Level 'ERROR' -Component 'SYSTEM-OPTIMIZATION' -Message "Error applying UI setting: $($_.Exception.Message)" -LogPath $LogPath -Operation 'Apply' -Target "$registryPath\$($setting.Key)" -Result 'Error' -Metadata @{ Error = $_.Exception.Message }
            }
        }
    }

    return $results
}

<#
.SYNOPSIS
    Enhanced disk optimization with intelligent cleanup and modern storage awareness
#>
function Invoke-EnhancedDiskOptimization {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [array]$Opportunities,

        [Parameter(Mandatory)]
        [PSCustomObject]$Config,

        [Parameter(Mandatory)]
        [PSCustomObject]$SystemProfile,

        [Parameter(Mandatory)]
        [string]$LogPath
    )

    $results = @{ Applied = 0; Failed = 0; Skipped = 0; SpaceFreed = 0 }
    $diskConfig = $Config.systemOptimizations.disk

    if (-not $diskConfig.enabled) {
        $results.Skipped = $Opportunities.Count
        return $results
    }

    Write-StructuredLogEntry -Level 'INFO' -Component 'SYSTEM-OPTIMIZATION' -Message "Starting enhanced disk optimization" -LogPath $LogPath -Metadata @{ OpportunityCount = $Opportunities.Count; SystemProfile = $SystemProfile.Profile }

    # Process cleanup targets from configuration
    foreach ($cleanupTarget in $diskConfig.cleanupTargets) {
        try {
            $targetPath = [Environment]::ExpandEnvironmentVariables($cleanupTarget.path)
            $parentPath = Split-Path $targetPath -Parent

            if (Test-Path $parentPath) {
                # Calculate current size
                $beforeSize = 0
                if (Test-Path $targetPath) {
                    $items = Get-ChildItem -Path $targetPath -Force -ErrorAction SilentlyContinue
                    if ($cleanupTarget.recurse) {
                        $beforeSize = ($items | Get-ChildItem -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
                    }
                    else {
                        $beforeSize = ($items | Where-Object { -not $_.PSIsContainer } | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
                    }
                }

                # Check if cleanup is needed based on thresholds
                $minSizeBytes = ConvertTo-Bytes -SizeString $cleanupTarget.minSize
                $shouldClean = ($beforeSize -gt $minSizeBytes)

                if ($shouldClean) {
                    Write-StructuredLogEntry -Level 'INFO' -Component 'SYSTEM-OPTIMIZATION' -Message "Cleaning: $($cleanupTarget.name)" -LogPath $LogPath -Operation 'Clean' -Target $cleanupTarget.name -Metadata @{ Path = $targetPath; SizeBefore = $beforeSize; MinSize = $minSizeBytes }

                    # Perform cleanup with age filtering if specified
                    if ($cleanupTarget.maxAge -and $cleanupTarget.maxAge -ne "0days") {
                        $maxAge = ConvertTo-TimeSpan -AgeString $cleanupTarget.maxAge
                        $cutoffDate = (Get-Date).Subtract($maxAge)

                        if ($cleanupTarget.recurse) {
                            Get-ChildItem -Path $targetPath -Recurse -Force -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt $cutoffDate } | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
                        }
                        else {
                            Get-ChildItem -Path $targetPath -Force -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt $cutoffDate } | Remove-Item -Force -ErrorAction SilentlyContinue
                        }
                    }
                    else {
                        # Clean all files
                        if ($cleanupTarget.recurse) {
                            Remove-Item -Path $targetPath -Recurse -Force -ErrorAction SilentlyContinue
                        }
                        else {
                            Remove-Item -Path $targetPath -Force -ErrorAction SilentlyContinue
                        }
                    }

                    # Calculate space freed
                    $afterSize = 0
                    if (Test-Path $targetPath) {
                        $items = Get-ChildItem -Path $targetPath -Force -ErrorAction SilentlyContinue
                        if ($cleanupTarget.recurse) {
                            $afterSize = ($items | Get-ChildItem -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
                        }
                        else {
                            $afterSize = ($items | Where-Object { -not $_.PSIsContainer } | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
                        }
                    }

                    $spaceFreed = [math]::Max(0, ($beforeSize ?? 0) - ($afterSize ?? 0))
                    $results.SpaceFreed += $spaceFreed

                    if ($spaceFreed -gt 0) {
                        $results.Applied++
                        Write-StructuredLogEntry -Level 'SUCCESS' -Component 'SYSTEM-OPTIMIZATION' -Message "Cleaned $($cleanupTarget.name): $([math]::Round($spaceFreed/1MB, 2)) MB freed" -LogPath $LogPath -Operation 'Clean' -Target $cleanupTarget.name -Result 'Success' -Metadata @{ SpaceFreedMB = [math]::Round($spaceFreed / 1MB, 2); BeforeSize = $beforeSize; AfterSize = $afterSize }
                    }
                    else {
                        Write-StructuredLogEntry -Level 'INFO' -Component 'SYSTEM-OPTIMIZATION' -Message "No space freed for: $($cleanupTarget.name)" -LogPath $LogPath -Operation 'Clean' -Target $cleanupTarget.name -Result 'NoChange'
                    }
                }
                else {
                    $results.Skipped++
                    Write-StructuredLogEntry -Level 'INFO' -Component 'SYSTEM-OPTIMIZATION' -Message "Skipped cleanup: $($cleanupTarget.name) (below threshold)" -LogPath $LogPath -Operation 'Skip' -Target $cleanupTarget.name -Metadata @{ CurrentSize = $beforeSize; MinSize = $minSizeBytes }
                }
            }
            else {
                $results.Skipped++
                Write-StructuredLogEntry -Level 'INFO' -Component 'SYSTEM-OPTIMIZATION' -Message "Skipped cleanup: $($cleanupTarget.name) (path not found)" -LogPath $LogPath -Operation 'Skip' -Target $cleanupTarget.name -Metadata @{ Path = $parentPath }
            }
        }
        catch {
            $results.Failed++
            Write-StructuredLogEntry -Level 'ERROR' -Component 'SYSTEM-OPTIMIZATION' -Message "Error cleaning $($cleanupTarget.name): $($_.Exception.Message)" -LogPath $LogPath -Operation 'Clean' -Target $cleanupTarget.name -Result 'Error' -Metadata @{ Error = $_.Exception.Message }
        }
    }

    return $results
}

<#
.SYNOPSIS
    Enhanced registry optimization with safety checks
#>
function Invoke-EnhancedRegistryOptimization {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [array]$Opportunities,

        [Parameter(Mandatory)]
        [PSCustomObject]$Config,

        [Parameter(Mandatory)]
        [string]$LogPath
    )

    $results = @{ Applied = 0; Failed = 0; Skipped = 0 }
    $registryConfig = $Config.systemOptimizations.registry

    Write-StructuredLogEntry -Level 'INFO' -Component 'SYSTEM-OPTIMIZATION' -Message "Starting enhanced registry optimization" -LogPath $LogPath -Metadata @{ SafeOptimizationsCount = $registryConfig.safeOptimizations.Count }

    # Only perform safe optimizations from configuration
    foreach ($optimization in $registryConfig.safeOptimizations) {
        try {
            $registryPath = $optimization.path
            if (Test-Path $registryPath) {
                Write-StructuredLogEntry -Level 'INFO' -Component 'SYSTEM-OPTIMIZATION' -Message "Applying registry optimization: $($optimization.name)" -LogPath $LogPath -Operation 'Clean' -Target $optimization.name -Metadata @{ Path = $registryPath; Action = $optimization.action }

                switch ($optimization.action) {
                    'clearEntries' {
                        $items = Get-ChildItem -Path $registryPath -ErrorAction SilentlyContinue
                        $itemCount = $items.Count

                        foreach ($item in $items) {
                            Remove-Item -Path $item.PSPath -Force -ErrorAction SilentlyContinue
                        }

                        $results.Applied++
                        Write-StructuredLogEntry -Level 'SUCCESS' -Component 'SYSTEM-OPTIMIZATION' -Message "Cleared registry entries: $($optimization.name) ($itemCount items)" -LogPath $LogPath -Operation 'Clean' -Target $optimization.name -Result 'Success' -Metadata @{ ItemsCleared = $itemCount }
                    }
                    default {
                        Write-StructuredLogEntry -Level 'WARNING' -Component 'SYSTEM-OPTIMIZATION' -Message "Unknown registry action: $($optimization.action)" -LogPath $LogPath -Operation 'Clean' -Target $optimization.name -Result 'Unknown'
                        $results.Skipped++
                    }
                }
            }
            else {
                $results.Skipped++
                Write-StructuredLogEntry -Level 'INFO' -Component 'SYSTEM-OPTIMIZATION' -Message "Registry path not found: $($optimization.name)" -LogPath $LogPath -Operation 'Skip' -Target $optimization.name -Metadata @{ Path = $registryPath }
            }
        }
        catch {
            $results.Failed++
            Write-StructuredLogEntry -Level 'ERROR' -Component 'SYSTEM-OPTIMIZATION' -Message "Error in registry optimization $($optimization.name): $($_.Exception.Message)" -LogPath $LogPath -Operation 'Clean' -Target $optimization.name -Result 'Error' -Metadata @{ Error = $_.Exception.Message }
        }
    }

    return $results
}

<#
.SYNOPSIS
    Enhanced network optimization with modern TCP settings
#>
function Invoke-EnhancedNetworkOptimization {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [array]$Opportunities,

        [Parameter(Mandatory)]
        [PSCustomObject]$Config,

        [Parameter(Mandatory)]
        [string]$LogPath
    )

    $results = @{ Applied = 0; Failed = 0; Skipped = 0 }
    $networkConfig = $Config.systemOptimizations.network

    Write-StructuredLogEntry -Level 'INFO' -Component 'SYSTEM-OPTIMIZATION' -Message "Starting enhanced network optimization" -LogPath $LogPath

    # Apply TCP optimizations if enabled
    if ($networkConfig.tcpOptimizations.enabled) {
        $tcpSettings = $networkConfig.tcpOptimizations.settings
        $tcpRegistryPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters'

        foreach ($setting in $tcpSettings.PSObject.Properties) {
            try {
                if (-not (Test-Path $tcpRegistryPath)) {
                    New-Item -Path $tcpRegistryPath -Force | Out-Null
                }

                Set-ItemProperty -Path $tcpRegistryPath -Name $setting.Name -Value $setting.Value -Force

                # Verify the change
                $newValue = (Get-ItemProperty -Path $tcpRegistryPath -Name $setting.Name -ErrorAction SilentlyContinue).($setting.Name)
                if ($newValue -eq $setting.Value) {
                    $results.Applied++
                    Write-StructuredLogEntry -Level 'SUCCESS' -Component 'SYSTEM-OPTIMIZATION' -Message "Applied TCP setting: $($setting.Name)" -LogPath $LogPath -Operation 'Apply' -Target $setting.Name -Result 'Success' -Metadata @{ NewValue = $newValue }
                }
                else {
                    $results.Failed++
                    Write-StructuredLogEntry -Level 'ERROR' -Component 'SYSTEM-OPTIMIZATION' -Message "Failed to verify TCP setting: $($setting.Name)" -LogPath $LogPath -Operation 'Apply' -Target $setting.Name -Result 'Failed' -Metadata @{ ExpectedValue = $setting.Value; ActualValue = $newValue }
                }
            }
            catch {
                $results.Failed++
                Write-StructuredLogEntry -Level 'ERROR' -Component 'SYSTEM-OPTIMIZATION' -Message "Error applying TCP setting $($setting.Name): $($_.Exception.Message)" -LogPath $LogPath -Operation 'Apply' -Target $setting.Name -Result 'Error' -Metadata @{ Error = $_.Exception.Message }
            }
        }
    }

    # Apply DNS optimizations if enabled
    if ($networkConfig.dnsOptimizations.enabled) {
        try {
            if ($networkConfig.dnsOptimizations.flushDNSCache) {
                Write-StructuredLogEntry -Level 'INFO' -Component 'SYSTEM-OPTIMIZATION' -Message "Flushing DNS cache" -LogPath $LogPath -Operation 'Flush' -Target 'DNSCache'
                $null = & ipconfig /flushdns 2>&1
                $results.Applied++
                Write-StructuredLogEntry -Level 'SUCCESS' -Component 'SYSTEM-OPTIMIZATION' -Message "DNS cache flushed successfully" -LogPath $LogPath -Operation 'Flush' -Target 'DNSCache' -Result 'Success'
            }
        }
        catch {
            $results.Failed++
            Write-StructuredLogEntry -Level 'ERROR' -Component 'SYSTEM-OPTIMIZATION' -Message "Error flushing DNS cache: $($_.Exception.Message)" -LogPath $LogPath -Operation 'Flush' -Target 'DNSCache' -Result 'Error' -Metadata @{ Error = $_.Exception.Message }
        }
    }

    return $results
}

<#
.SYNOPSIS
    Modern Windows optimization for Windows 11 specific features
#>
function Invoke-ModernWindowsOptimization {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Config,

        [Parameter(Mandatory)]
        [PSCustomObject]$SystemProfile,

        [Parameter(Mandatory)]
        [string]$LogPath
    )

    $results = @{ Applied = 0; Failed = 0; Skipped = 0 }
    $modernConfig = $Config.systemOptimizations.modern.windows11

    if (-not $modernConfig.enabled -or $SystemProfile.WindowsVersion -lt 11) {
        Write-StructuredLogEntry -Level 'INFO' -Component 'SYSTEM-OPTIMIZATION' -Message "Modern Windows optimizations not applicable" -LogPath $LogPath -Metadata @{ WindowsVersion = $SystemProfile.WindowsVersion; Enabled = $modernConfig.enabled }
        return $results
    }

    Write-StructuredLogEntry -Level 'INFO' -Component 'SYSTEM-OPTIMIZATION' -Message "Applying Windows 11 specific optimizations" -LogPath $LogPath -Metadata @{ OptimizationCount = $modernConfig.optimizations.Count }

    foreach ($optimization in $modernConfig.optimizations) {
        try {
            $registryPath = $optimization.registry

            Write-StructuredLogEntry -Level 'INFO' -Component 'SYSTEM-OPTIMIZATION' -Message "Applying modern optimization: $($optimization.name)" -LogPath $LogPath -Operation 'Apply' -Target $optimization.name -Metadata @{ Path = $registryPath }

            # Ensure registry path exists
            if (-not (Test-Path $registryPath)) {
                New-Item -Path $registryPath -Force | Out-Null
            }

            # Apply the setting
            if ($optimization.key) {
                Set-ItemProperty -Path $registryPath -Name $optimization.key -Value $optimization.value -Type $optimization.type -Force

                # Verify the change
                $newValue = (Get-ItemProperty -Path $registryPath -Name $optimization.key -ErrorAction SilentlyContinue).($optimization.key)
                if ($newValue -eq $optimization.value) {
                    $results.Applied++
                    Write-StructuredLogEntry -Level 'SUCCESS' -Component 'SYSTEM-OPTIMIZATION' -Message "Applied modern optimization: $($optimization.name)" -LogPath $LogPath -Operation 'Apply' -Target $optimization.name -Result 'Success' -Metadata @{ Key = $optimization.key; Value = $newValue }
                }
                else {
                    $results.Failed++
                    Write-StructuredLogEntry -Level 'ERROR' -Component 'SYSTEM-OPTIMIZATION' -Message "Failed to verify modern optimization: $($optimization.name)" -LogPath $LogPath -Operation 'Apply' -Target $optimization.name -Result 'Failed' -Metadata @{ ExpectedValue = $optimization.value; ActualValue = $newValue }
                }
            }
            else {
                # Special case for empty string value (like context menu fix)
                Set-ItemProperty -Path $registryPath -Name '(Default)' -Value $optimization.value -Type $optimization.type -Force
                $results.Applied++
                Write-StructuredLogEntry -Level 'SUCCESS' -Component 'SYSTEM-OPTIMIZATION' -Message "Applied modern optimization: $($optimization.name)" -LogPath $LogPath -Operation 'Apply' -Target $optimization.name -Result 'Success'
            }
        }
        catch {
            $results.Failed++
            Write-StructuredLogEntry -Level 'ERROR' -Component 'SYSTEM-OPTIMIZATION' -Message "Error applying modern optimization $($optimization.name): $($_.Exception.Message)" -LogPath $LogPath -Operation 'Apply' -Target $optimization.name -Result 'Error' -Metadata @{ Error = $_.Exception.Message }
        }
    }

    return $results
}

<#
.SYNOPSIS
    Helper function to convert size strings to bytes
#>
function ConvertTo-Bytes {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([string]$SizeString)

    if ($SizeString -match '(\d+)(MB|GB|KB)') {
        $size = [int]$matches[1]
        $unit = $matches[2]

        switch ($unit) {
            'KB' { return $size * 1KB }
            'MB' { return $size * 1MB }
            'GB' { return $size * 1GB }
        }
    }

    return 0
}

<#
.SYNOPSIS
    Helper function to convert age strings to TimeSpan
#>
function ConvertTo-TimeSpan {
    [CmdletBinding()]
    [OutputType([System.TimeSpan])]
    param(
        [Parameter(Mandatory)]
        [string]$AgeString
    )

    if ($AgeString -match '(\d+)days') {
        return New-TimeSpan -Days $matches[1]
    }
    elseif ($AgeString -match '(\d+)hours') {
        return New-TimeSpan -Hours $matches[1]
    }

    return New-TimeSpan -Days 7  # Default to 7 days
}

<#
.SYNOPSIS
    Disable specific startup application with enhanced safety checks
#>
function Disable-StartupApplication {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [string]$AppName,
        [string]$Reason,
        [string]$LogPath
    )

    try {
        $startupLocations = @(
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
            'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
        )

        foreach ($location in $startupLocations) {
            if (Test-Path $location) {
                $property = Get-ItemProperty -Path $location -Name $AppName -ErrorAction SilentlyContinue
                if ($property) {
                    # Create backup
                    $backupPath = "$location\Disabled"
                    if (-not (Test-Path $backupPath)) {
                        New-Item -Path $backupPath -Force | Out-Null
                    }

                    Set-ItemProperty -Path $backupPath -Name $AppName -Value $property.$AppName -Force
                    Remove-ItemProperty -Path $location -Name $AppName -Force

                    Write-StructuredLogEntry -Level 'SUCCESS' -Component 'SYSTEM-OPTIMIZATION' -Message "Disabled startup app: $AppName" -LogPath $LogPath -Operation 'Disable' -Target $AppName -Result 'Success' -Metadata @{ Location = $location; Reason = $Reason; BackedUp = $true }
                    return $true
                }
            }
        }

        return $false
    }
    catch {
        Write-StructuredLogEntry -Level 'ERROR' -Component 'SYSTEM-OPTIMIZATION' -Message "Error disabling startup app $AppName`: $($_.Exception.Message)" -LogPath $LogPath -Operation 'Disable' -Target $AppName -Result 'Error' -Metadata @{ Error = $_.Exception.Message }
        return $false
    }
}

<#
.SYNOPSIS
    Optimize Windows service with enhanced configuration
#>
# DEPRECATED: Legacy function for backward compatibility
# Used internally by enhanced optimization functions
function Optimize-WindowsService {
    [CmdletBinding()]
    [Obsolete("This function is deprecated and may be removed in v4.0.", false)]
    param(
        [string]$ServiceName,
        [string]$Reason,
        [string]$LogPath
    )

    try {
        $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
        if ($service) {
            # Get current startup type
            $currentStartup = (Get-CimInstance -ClassName Win32_Service -Filter "Name='$ServiceName'").StartMode

            # Set to manual if currently automatic
            if ($currentStartup -eq 'Auto') {
                Set-Service -Name $ServiceName -StartupType Manual
                Write-StructuredLogEntry -Level 'SUCCESS' -Component 'SYSTEM-OPTIMIZATION' -Message "Changed service startup: $ServiceName (Auto -> Manual)" -LogPath $LogPath -Operation 'Optimize' -Target $ServiceName -Result 'Success' -Metadata @{ OldStartup = $currentStartup; NewStartup = 'Manual'; Reason = $Reason }
                return $true
            }
        }

        return $false
    }
    catch {
        Write-StructuredLogEntry -Level 'ERROR' -Component 'SYSTEM-OPTIMIZATION' -Message "Error optimizing service $ServiceName`: $($_.Exception.Message)" -LogPath $LogPath -Operation 'Optimize' -Target $ServiceName -Result 'Error' -Metadata @{ Error = $_.Exception.Message }
        return $false
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




