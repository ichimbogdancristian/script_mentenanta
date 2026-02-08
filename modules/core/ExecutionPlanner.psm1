#Requires -Version 7.0

<#
.SYNOPSIS
    Execution Planner Module - Intelligent Orchestration (v4.0)

.DESCRIPTION
    Analyzes Type1 audit results and creates intelligent execution plans.
    Determines which Type2 modules need to run based on detected issues.

    This module enables audit-first execution where the system:
    1. Runs all Type1 audits to detect issues
    2. Creates an execution plan based on findings
    3. Only runs Type2 modules that have detected issues
    4. Skips modules with nothing to do

.NOTES
    Module Type: Core Infrastructure
    Architecture: v4.0 - Intelligent Orchestration (Phase C.3)
    Author: Windows Maintenance Automation Project
    Version: 4.0.0

    Key Design Patterns:
    - Audit-first execution (Type1 before Type2)
    - Intelligent module skipping (saves time)
    - Priority-based execution ordering
    - User-friendly plan display
#>

# Import dependencies
$ModuleRoot = Split-Path -Parent $PSScriptRoot
$CoreInfraPath = Join-Path $ModuleRoot 'core\CoreInfrastructure.psm1'
if (Test-Path $CoreInfraPath) {
    Import-Module $CoreInfraPath -Force -Global
}

#region Public Functions

<#
.SYNOPSIS
    Creates intelligent execution plan based on audit results

.DESCRIPTION
    Analyzes Type1 audit results to determine which Type2 modules need execution.
    Skips modules that have nothing to do, saving time and resources.

    Module Decision Logic:
    - BloatwareRemoval: Run if bloatware detected (count > 0)
    - EssentialApps: Run if missing apps detected (count > 0)
    - SystemOptimization: Run if optimization opportunities found (count > 0)
    - TelemetryDisable: Run if active telemetry services found (count > 0)
    - SecurityEnhancement: Run if security score < 85%
    - WindowsUpdates: Run if pending updates detected (count > 0)
    - AppUpgrade: Run if app upgrades available (count > 0)

.PARAMETER AuditResults
    Hashtable containing results from all Type1 audit modules
    Expected keys: Bloatware, EssentialApps, SystemOptimization, Telemetry,
                   Security, WindowsUpdates, AppUpgrade

.PARAMETER Config
    Main configuration object (must include OSContext)

.OUTPUTS
    PSCustomObject with execution plan details:
    - RequiredModules: Array of modules that need to run
    - SkippedModules: Array of modules with nothing to do
    - TotalRequiredModules: Count of required modules
    - TotalSkippedModules: Count of skipped modules
    - TotalItemsDetected: Total items found across all audits
    - EstimatedDurationMinutes: Estimated execution time

.EXAMPLE
    $auditResults = @{
        Bloatware = @{ DetectedItems = @(...) }
        EssentialApps = @{ MissingApps = @(...) }
    }
    $plan = New-ExecutionPlan -AuditResults $auditResults -Config $Config
    Show-ExecutionPlan -ExecutionPlan $plan
#>
function New-ExecutionPlan {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$AuditResults,

        [Parameter(Mandatory)]
        [hashtable]$Config
    )

    Write-LogEntry -Level 'INFO' -Component 'EXECUTION-PLANNER' -Message 'Creating execution plan from audit results'

    $plan = @{
        RequiredModules = [System.Collections.Generic.List[PSCustomObject]]::new()
        SkippedModules = [System.Collections.Generic.List[PSCustomObject]]::new()
        TotalDetected = 0
        TotalToProcess = 0
        AnalysisTime = Get-Date
    }

    # Priority order for modules (1 = highest priority)
    $modulePriority = @{
        'BloatwareRemoval' = 1
        'SecurityEnhancement' = 2
        'SystemOptimization' = 3
        'TelemetryDisable' = 4
        'EssentialApps' = 5
        'WindowsUpdates' = 6
        'AppUpgrade' = 7
    }

    # === Bloatware Removal === $bloatwareCount = 0
    if ($AuditResults.Bloatware) {
        if ($AuditResults.Bloatware -is [Array]) {
            $bloatwareCount = $AuditResults.Bloatware.Count
        }
        elseif ($AuditResults.Bloatware.DetectedItems) {
            $bloatwareCount = $AuditResults.Bloatware.DetectedItems.Count
        }
    }

    if ($bloatwareCount -gt 0) {
        $plan.RequiredModules.Add([PSCustomObject]@{
                Name = 'BloatwareRemoval'
                Reason = "$bloatwareCount bloatware item(s) detected"
                Priority = $modulePriority['BloatwareRemoval']
                ItemCount = $bloatwareCount
                EstimatedDurationSec = [math]::Max(10, $bloatwareCount * 3)
                Category = 'Cleanup'
            })
        $plan.TotalDetected += $bloatwareCount
        $plan.TotalToProcess += $bloatwareCount
    }
    else {
        $plan.SkippedModules.Add([PSCustomObject]@{
                Name = 'BloatwareRemoval'
                Reason = 'No bloatware detected'
            })
    }

    # === Essential Apps Installation === $missingApps = 0
    if ($AuditResults.EssentialApps) {
        if ($AuditResults.EssentialApps.MissingApps) {
            $missingApps = $AuditResults.EssentialApps.MissingApps.Count
        }
        elseif ($AuditResults.EssentialApps -is [Array]) {
            $missingApps = $AuditResults.EssentialApps.Count
        }
    }

    if ($missingApps -gt 0) {
        $plan.RequiredModules.Add([PSCustomObject]@{
                Name = 'EssentialApps'
                Reason = "$missingApps missing essential app(s)"
                Priority = $modulePriority['EssentialApps']
                ItemCount = $missingApps
                EstimatedDurationSec = [math]::Max(30, $missingApps * 15)  # Longer for installations
                Category = 'Installation'
            })
        $plan.TotalDetected += $missingApps
        $plan.TotalToProcess += $missingApps
    }
    else {
        $plan.SkippedModules.Add([PSCustomObject]@{
                Name = 'EssentialApps'
                Reason = 'All essential apps already installed'
            })
    }

    # === System Optimization === $optimizationCount = 0
    if ($AuditResults.SystemOptimization) {
        if ($AuditResults.SystemOptimization.OptimizationOpportunities) {
            $optimizationCount = $AuditResults.SystemOptimization.OptimizationOpportunities.Count
        }
    }

    if ($optimizationCount -gt 0) {
        $plan.RequiredModules.Add([PSCustomObject]@{
                Name = 'SystemOptimization'
                Reason = "$optimizationCount optimization(s) available"
                Priority = $modulePriority['SystemOptimization']
                ItemCount = $optimizationCount
                EstimatedDurationSec = [math]::Max(15, $optimizationCount * 5)
                Category = 'Optimization'
            })
        $plan.TotalDetected += $optimizationCount
        $plan.TotalToProcess += $optimizationCount
    }
    else {
        $plan.SkippedModules.Add([PSCustomObject]@{
                Name = 'SystemOptimization'
                Reason = 'System already optimized'
            })
    }

    # === Telemetry Disable === $telemetryCount = 0
    if ($AuditResults.Telemetry) {
        if ($AuditResults.Telemetry.ActiveTelemetryCount) {
            $telemetryCount = $AuditResults.Telemetry.ActiveTelemetryCount
        }
        elseif ($AuditResults.Telemetry.ActiveServices) {
            $telemetryCount = $AuditResults.Telemetry.ActiveServices.Count
        }
    }

    if ($telemetryCount -gt 0) {
        $plan.RequiredModules.Add([PSCustomObject]@{
                Name = 'TelemetryDisable'
                Reason = "$telemetryCount active telemetry service(s)"
                Priority = $modulePriority['TelemetryDisable']
                ItemCount = $telemetryCount
                EstimatedDurationSec = [math]::Max(10, $telemetryCount * 2)
                Category = 'Privacy'
            })
        $plan.TotalDetected += $telemetryCount
        $plan.TotalToProcess += $telemetryCount
    }
    else {
        $plan.SkippedModules.Add([PSCustomObject]@{
                Name = 'TelemetryDisable'
                Reason = 'Telemetry already minimized'
            })
    }

    # === Security Enhancement === $securityScore = 100
    $needsSecurity = $false
    if ($AuditResults.Security) {
        if ($AuditResults.Security.SecurityScore) {
            $securityScore = $AuditResults.Security.SecurityScore
        }
        elseif ($AuditResults.Security.Summary -and $AuditResults.Security.Summary.PercentageScore) {
            $securityScore = $AuditResults.Security.Summary.PercentageScore
        }

        # Run security if score below 85%
        $needsSecurity = $securityScore -lt 85
    }

    if ($needsSecurity) {
        $issueCount = if ($AuditResults.Security.Issues) { $AuditResults.Security.Issues.Count } else { 1 }
        $plan.RequiredModules.Add([PSCustomObject]@{
                Name = 'SecurityEnhancement'
                Reason = "Security score: $securityScore% (below 85% threshold)"
                Priority = $modulePriority['SecurityEnhancement']
                ItemCount = $issueCount
                EstimatedDurationSec = 20
                Category = 'Security'
            })
        $plan.TotalDetected += $issueCount
        $plan.TotalToProcess += $issueCount
    }
    else {
        $plan.SkippedModules.Add([PSCustomObject]@{
                Name = 'SecurityEnhancement'
                Reason = "Security score acceptable ($securityScore%)"
            })
    }

    # === Windows Updates === $pendingUpdates = 0
    if ($AuditResults.WindowsUpdates) {
        if ($AuditResults.WindowsUpdates.PendingUpdatesCount) {
            $pendingUpdates = $AuditResults.WindowsUpdates.PendingUpdatesCount
        }
        elseif ($AuditResults.WindowsUpdates.PendingAudit) {
            $pendingUpdates = $AuditResults.WindowsUpdates.PendingAudit.PendingCount
        }
    }

    if ($pendingUpdates -gt 0) {
        $plan.RequiredModules.Add([PSCustomObject]@{
                Name = 'WindowsUpdates'
                Reason = "$pendingUpdates pending update(s)"
                Priority = $modulePriority['WindowsUpdates']
                ItemCount = $pendingUpdates
                EstimatedDurationSec = [math]::Max(60, $pendingUpdates * 30)  # Updates take longer
                Category = 'Updates'
            })
        $plan.TotalDetected += $pendingUpdates
        $plan.TotalToProcess += $pendingUpdates
    }
    else {
        $plan.SkippedModules.Add([PSCustomObject]@{
                Name = 'WindowsUpdates'
                Reason = 'System is up to date'
            })
    }

    # === App Upgrades === $upgradeCount = 0
    if ($AuditResults.AppUpgrade) {
        if ($AuditResults.AppUpgrade -is [Array]) {
            $upgradeCount = $AuditResults.AppUpgrade.Count
        }
        elseif ($AuditResults.AppUpgrade.AvailableUpgrades) {
            $upgradeCount = $AuditResults.AppUpgrade.AvailableUpgrades.Count
        }
    }

    if ($upgradeCount -gt 0) {
        $plan.RequiredModules.Add([PSCustomObject]@{
                Name = 'AppUpgrade'
                Reason = "$upgradeCount app upgrade(s) available"
                Priority = $modulePriority['AppUpgrade']
                ItemCount = $upgradeCount
                EstimatedDurationSec = [math]::Max(20, $upgradeCount * 10)
                Category = 'Updates'
            })
        $plan.TotalDetected += $upgradeCount
        $plan.TotalToProcess += $upgradeCount
    }
    else {
        $plan.SkippedModules.Add([PSCustomObject]@{
                Name = 'AppUpgrade'
                Reason = 'All apps up to date'
            })
    }

    # Sort required modules by priority
    $plan.RequiredModules = [System.Collections.Generic.List[PSCustomObject]]($plan.RequiredModules | Sort-Object Priority)

    # Calculate total estimated time
    $totalEstimatedSeconds = ($plan.RequiredModules | Measure-Object -Property EstimatedDurationSec -Sum).Sum
    $estimatedMinutes = [math]::Ceiling($totalEstimatedSeconds / 60)

    # Create final plan object
    $executionPlan = [PSCustomObject]@{
        RequiredModules = $plan.RequiredModules
        SkippedModules = $plan.SkippedModules
        TotalRequiredModules = $plan.RequiredModules.Count
        TotalSkippedModules = $plan.SkippedModules.Count
        TotalItemsDetected = $plan.TotalDetected
        TotalItemsToProcess = $plan.TotalToProcess
        EstimatedDurationSeconds = $totalEstimatedSeconds
        EstimatedDurationMinutes = $estimatedMinutes
        AnalysisTime = $plan.AnalysisTime
        OSContext = if ($Config.OSContext) { $Config.OSContext.DisplayText } else { 'Unknown' }
    }

    Write-LogEntry -Level 'SUCCESS' -Component 'EXECUTION-PLANNER' -Message "Execution plan created: $($executionPlan.TotalRequiredModules) required, $($executionPlan.TotalSkippedModules) skipped" -Data @{
        RequiredModules = $executionPlan.TotalRequiredModules
        SkippedModules = $executionPlan.TotalSkippedModules
        EstimatedDuration = "$estimatedMinutes minutes"
    }

    return $executionPlan
}

<#
.SYNOPSIS
    Displays execution plan in user-friendly format

.DESCRIPTION
    Creates a formatted display of the execution plan with:
    - Analysis summary (total items, estimated duration, OS context)
    - Required tasks list with priorities and estimates
    - Skipped tasks list with reasons

    Uses color-coding and Unicode symbols for visual clarity.

.PARAMETER ExecutionPlan
    Execution plan object from New-ExecutionPlan

.EXAMPLE
    $plan = New-ExecutionPlan -AuditResults $results -Config $config
    Show-ExecutionPlan -ExecutionPlan $plan
#>
function Show-ExecutionPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$ExecutionPlan
    )

    Write-Host "`n" -NoNewline
    Write-Host "╔════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║          INTELLIGENT EXECUTION PLAN (v4.0)                 ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""

    Write-Host "📊 Analysis Summary:" -ForegroundColor Yellow
    Write-Host "   Total items detected: $($ExecutionPlan.TotalItemsDetected)" -ForegroundColor White
    Write-Host "   Estimated duration: $($ExecutionPlan.EstimatedDurationMinutes) minutes" -ForegroundColor White
    Write-Host "   Operating System: $($ExecutionPlan.OSContext)" -ForegroundColor White
    Write-Host ""

    if ($ExecutionPlan.TotalRequiredModules -gt 0) {
        Write-Host "✅ Required Tasks: $($ExecutionPlan.TotalRequiredModules)" -ForegroundColor Green
        $index = 1
        foreach ($module in $ExecutionPlan.RequiredModules) {
            $durationMin = [math]::Ceiling($module.EstimatedDurationSec / 60)
            Write-Host "   $index. " -NoNewline -ForegroundColor Gray
            Write-Host "$($module.Name) " -NoNewline -ForegroundColor White
            Write-Host "[$($module.Category)]" -NoNewline -ForegroundColor DarkGray
            Write-Host ""
            Write-Host "      → $($module.Reason)" -ForegroundColor DarkCyan
            Write-Host "      ⏱ Est. $durationMin min | 📦 $($module.ItemCount) items" -ForegroundColor DarkGray
            $index++
        }
        Write-Host ""
    }

    if ($ExecutionPlan.TotalSkippedModules -gt 0) {
        Write-Host "⏩ Skipped Tasks: $($ExecutionPlan.TotalSkippedModules) " -NoNewline -ForegroundColor DarkYellow
        Write-Host "(Nothing to do)" -ForegroundColor DarkGray
        foreach ($module in $ExecutionPlan.SkippedModules) {
            Write-Host "   ✓ " -NoNewline -ForegroundColor DarkGreen
            Write-Host "$($module.Name) " -NoNewline -ForegroundColor DarkGray
            Write-Host "- $($module.Reason)" -ForegroundColor DarkGray
        }
        Write-Host ""
    }

    Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
}

#endregion

# Export functions
Export-ModuleMember -Function @(
    'New-ExecutionPlan',
    'Show-ExecutionPlan'
)

