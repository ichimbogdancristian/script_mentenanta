#Requires -Version 7.0

<#
.SYNOPSIS
    OS-Specific Recommendations Engine for Windows Maintenance System

.DESCRIPTION
    Phase C.4 enhancement module that provides OS-aware recommendations
    based on Windows version (10 vs 11), build number, and supported features.

    Integrates with ReportGenerator.psm1 to add OS-specific context and
    tailored recommendations to maintenance reports.

.MODULE ARCHITECTURE
    Purpose:
        Generate OS-specific recommendations and format OS context for reports.
        Separates OS intelligence from report generation for maintainability.

    Dependencies:
        • CoreInfrastructure.psm1 - For Get-WindowsVersionContext and logging

    Exports:
        • Get-OSSpecificRecommendations - Generate OS-aware recommendations
        • Format-OSContextForReport - Format OS context for HTML display
        • Build-OSContextSection - Build complete OS section HTML
        • Test-OSFeatureAvailability - Check feature support for current OS

    Used By:
        - ReportGenerator.psm1 (enhances report generation with OS context)
        - MaintenanceOrchestrator.ps1 (optional - for OS checks)

.NOTES
    Module Type: Type 1 (Analysis/Recommendation - Read-Only)
    Architecture: v4.0 - Phase C.4 (Enhanced Reporting)
    Version: 1.0.0
    Author: Bogdan Ichim
    Created: February 2026

    Key Features:
    - Windows 10 vs 11 differentiation
    - Build-specific recommendations
    - Feature availability checking
    - HTML-formatted output for reports
#>

# Import CoreInfrastructure for OS detection and logging
$CoreInfraPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'core\CoreInfrastructure.psm1'
if (Test-Path $CoreInfraPath) {
    Import-Module $CoreInfraPath -Force -Global
}
else {
    throw "CoreInfrastructure module not found at: $CoreInfraPath"
}

#region OS-Specific Recommendation Functions

<#
.SYNOPSIS
    Generates OS-specific recommendations based on Windows version and maintenance results

.DESCRIPTION
    Analyzes Windows version (10 vs 11), build number, and maintenance results
    to provide tailored recommendations. Returns prioritized list of actionable items.

.PARAMETER OSContext
    OS context object from Get-WindowsVersionContext

.PARAMETER MaintenanceResults
    Aggregated maintenance results (optional - for context-aware recommendations)

.OUTPUTS
    [PSCustomObject] Recommendations object with categories and priorities

.EXAMPLE
    PS> $osContext = Get-WindowsVersionContext
    PS> $recommendations = Get-OSSpecificRecommendations -OSContext $osContext

.NOTES
    Recommendation categories:
    - System: OS updates, feature optimization
    - Security: OS-specific hardening
    - Performance: Version-specific tuning
    - Compatibility: Feature-based suggestions
#>
function Get-OSSpecificRecommendations {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$OSContext,

        [Parameter()]
        [hashtable]$MaintenanceResults
    )

    Write-Verbose "Generating OS-specific recommendations for $($OSContext.DisplayText)"

    $recommendations = [System.Collections.Generic.List[PSCustomObject]]::new()

    # Windows 11 Specific Recommendations
    if ($OSContext.IsWindows11) {
        # Security recommendations
        $recommendations.Add([PSCustomObject]@{
                Category = 'Security'
                Priority = 'High'
                Title = 'TPM 2.0 Security Verification'
                Description = 'Windows 11 requires TPM 2.0. Verify TPM is enabled and firmware is up-to-date for optimal security.'
                Action = 'Run tpm.msc to verify TPM status'
                Icon = '🔐'
                OSSpecific = $true
            })

        # Feature recommendations
        if ($OSContext.SupportedFeatures.AndroidApps) {
            $recommendations.Add([PSCustomObject]@{
                    Category = 'Features'
                    Priority = 'Low'
                    Title = 'Windows Subsystem for Android'
                    Description = 'Your system supports Android apps. Consider installing WSA if you need mobile app functionality.'
                    Action = 'Install from Microsoft Store: Windows Subsystem for Android'
                    Icon = '📱'
                    OSSpecific = $true
                })
        }

        if ($OSContext.SupportedFeatures.DirectStorage) {
            $recommendations.Add([PSCustomObject]@{
                    Category = 'Performance'
                    Priority = 'Medium'
                    Title = 'DirectStorage Optimization'
                    Description = 'Windows 11 supports DirectStorage for faster game loading. Ensure NVMe drivers are current.'
                    Action = 'Update NVMe drivers and enable DirectStorage in supported games'
                    Icon = '⚡'
                    OSSpecific = $true
                })
        }

        # Snap Layouts recommendation
        $recommendations.Add([PSCustomObject]@{
                Category = 'Productivity'
                Priority = 'Low'
                Title = 'Snap Layouts for Multitasking'
                Description = 'Use Windows 11 Snap Layouts (hover over maximize button) for efficient window management.'
                Action = 'Enable: Settings > System > Multitasking > Snap windows'
                Icon = '🪟'
                OSSpecific = $true
            })

        # Widget customization
        $recommendations.Add([PSCustomObject]@{
                Category = 'Productivity'
                Priority = 'Low'
                Title = 'Widgets Panel Optimization'
                Description = 'Customize Windows 11 Widgets panel for quick access to news, weather, and system info.'
                Action = 'Open Widgets panel (Win + W) and customize feed'
                Icon = '📊'
                OSSpecific = $true
            })
    }

    # Windows 10 Specific Recommendations
    if ($OSContext.IsWindows10) {
        # Update path recommendation
        $recommendations.Add([PSCustomObject]@{
                Category = 'System'
                Priority = 'High'
                Title = 'Windows 11 Upgrade Consideration'
                Description = 'Windows 10 reaches end of support October 2025. Evaluate Windows 11 upgrade for continued security updates.'
                Action = 'Check compatibility: Settings > Update & Security > Windows Update'
                Icon = '⚠️'
                OSSpecific = $true
            })

        # Classic features
        $recommendations.Add([PSCustomObject]@{
                Category = 'Features'
                Priority = 'Medium'
                Title = 'Classic Start Menu Customization'
                Description = 'Windows 10 supports Live Tiles. Pin frequently used apps for quick access.'
                Action = 'Right-click apps > Pin to Start'
                Icon = '📌'
                OSSpecific = $true
            })

        # Taskbar positioning
        $recommendations.Add([PSCustomObject]@{
                Category = 'Productivity'
                Priority = 'Low'
                Title = 'Taskbar Positioning'
                Description = 'Windows 10 allows taskbar on any screen edge. Optimize for your workflow (unavailable in Windows 11).'
                Action = 'Taskbar Settings > Taskbar location on screen'
                Icon = '🎯'
                OSSpecific = $true
            })
    }

    # Universal recommendations (all Windows versions)

    # Disk cleanup based on OS
    $diskRecommendation = if ($OSContext.IsWindows11) {
        'Use Settings > System > Storage > Cleanup recommendations for intelligent storage management.'
    }
    else {
        'Use Disk Cleanup utility or Storage Sense to free up disk space.'
    }

    $recommendations.Add([PSCustomObject]@{
            Category = 'Maintenance'
            Priority = 'Medium'
            Title = 'Regular Disk Cleanup'
            Description = $diskRecommendation
            Action = 'Run disk cleanup monthly'
            Icon = '🗑️'
            OSSpecific = $false
        })

    # Windows Update recommendation
    $updateRecommendation = if ($OSContext.BuildNumber) {
        "Current build: $($OSContext.BuildNumber). Check for the latest quality and feature updates."
    }
    else {
        "Keep Windows updated for security and performance improvements."
    }

    $recommendations.Add([PSCustomObject]@{
            Category = 'Security'
            Priority = 'High'
            Title = 'Windows Update Status'
            Description = $updateRecommendation
            Action = 'Settings > Update & Security > Check for updates'
            Icon = '🔄'
            OSSpecific = $false
        })

    # Driver updates
    $recommendations.Add([PSCustomObject]@{
            Category = 'Performance'
            Priority = 'Medium'
            Title = 'Driver Updates'
            Description = 'Outdated drivers can cause performance and stability issues. Check for updates regularly.'
            Action = 'Device Manager > Scan for hardware changes, or use manufacturer tools'
            Icon = '🔧'
            OSSpecific = $false
        })

    # Add maintenance-result-based recommendations if available
    if ($MaintenanceResults) {
        # Security score-based recommendation
        if ($MaintenanceResults.ContainsKey('SecurityScore') -and $MaintenanceResults.SecurityScore -lt 80) {
            $recommendations.Add([PSCustomObject]@{
                    Category = 'Security'
                    Priority = 'High'
                    Title = 'Security Hardening Required'
                    Description = "System security score is below optimal ($($MaintenanceResults.SecurityScore)%). Review security audit results."
                    Action = 'Run SecurityEnhancement module and review recommendations'
                    Icon = '🛡️'
                    OSSpecific = $false
                })
        }

        # Bloatware detection-based recommendation
        if ($MaintenanceResults.ContainsKey('BloatwareCount') -and $MaintenanceResults.BloatwareCount -gt 5) {
            $recommendations.Add([PSCustomObject]@{
                    Category = 'Performance'
                    Priority = 'Medium'
                    Title = 'Excessive Bloatware Detected'
                    Description = "$($MaintenanceResults.BloatwareCount) bloatware items found. Remove unnecessary applications to improve performance."
                    Action = 'Run BloatwareRemoval module to clean system'
                    Icon = '🧹'
                    OSSpecific = $false
                })
        }
    }

    # Sort recommendations by priority
    $priorityOrder = @{
        'High' = 1
        'Medium' = 2
        'Low' = 3
    }

    $sortedRecommendations = $recommendations | Sort-Object { $priorityOrder[$_.Priority] }

    return [PSCustomObject]@{
        OSVersion = $OSContext.DisplayText
        IsWindows11 = $OSContext.IsWindows11
        IsWindows10 = $OSContext.IsWindows10
        TotalRecommendations = $sortedRecommendations.Count
        HighPriority = ($sortedRecommendations | Where-Object Priority -eq 'High').Count
        MediumPriority = ($sortedRecommendations | Where-Object Priority -eq 'Medium').Count
        LowPriority = ($sortedRecommendations | Where-Object Priority -eq 'Low').Count
        OSSpecificCount = ($sortedRecommendations | Where-Object OSSpecific -eq $true).Count
        Recommendations = $sortedRecommendations
        GeneratedAt = Get-Date
    }
}

<#
.SYNOPSIS
    Formats OS context for HTML display in maintenance reports

.DESCRIPTION
    Converts OS context object into HTML-formatted string with badges,
    icons, and version information suitable for report headers.

.PARAMETER OSContext
    OS context object from Get-WindowsVersionContext

.OUTPUTS
    [string] HTML-formatted OS context display

.EXAMPLE
    PS> $osContext = Get-WindowsVersionContext
    PS> $html = Format-OSContextForReport -OSContext $osContext
#>
function Format-OSContextForReport {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$OSContext
    )

    $badgeClass = if ($OSContext.IsWindows11) { 'os-badge-win11' } else { 'os-badge-win10' }
    $osIcon = if ($OSContext.IsWindows11) { '🪟' } else { '🖥️' }

    $html = @"
<div class="os-context-section">
    <div class="os-badge $badgeClass">
        <span class="os-icon">$osIcon</span>
        <span class="os-version">Windows $($OSContext.Version)</span>
    </div>
    <div class="os-details">
        <div class="os-detail-item">
            <span class="detail-label">Build:</span>
            <span class="detail-value">$($OSContext.BuildNumber)</span>
        </div>
        <div class="os-detail-item">
            <span class="detail-label">Architecture:</span>
            <span class="detail-value">$($OSContext.Architecture)</span>
        </div>
        <div class="os-detail-item">
            <span class="detail-label">Edition:</span>
            <span class="detail-value">$($OSContext.Caption)</span>
        </div>
    </div>
</div>
"@

    return $html
}

<#
.SYNOPSIS
    Builds complete OS context section HTML for maintenance reports

.DESCRIPTION
    Creates comprehensive OS section including version info, recommendations,
    and feature availability. Designed for insertion in report templates.

.PARAMETER OSContext
    OS context object from Get-WindowsVersionContext

.PARAMETER MaintenanceResults
    Aggregated maintenance results (optional - for context-aware recommendations)

.PARAMETER MaxRecommendations
    Maximum number of recommendations to display (default: 8)

.OUTPUTS
    [string] Complete HTML section with OS context and recommendations

.EXAMPLE
    PS> $osContext = Get-WindowsVersionContext
    PS> $section = Build-OSContextSection -OSContext $osContext
#>
function Build-OSContextSection {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$OSContext,

        [Parameter()]
        [hashtable]$MaintenanceResults,

        [Parameter()]
        [int]$MaxRecommendations = 8
    )

    # Get OS-specific recommendations
    $params = @{ OSContext = $OSContext }
    if ($MaintenanceResults) { $params.MaintenanceResults = $MaintenanceResults }

    $recommendationsData = Get-OSSpecificRecommendations @params

    # Format OS context
    $osContextHtml = Format-OSContextForReport -OSContext $OSContext

    # Build recommendations HTML
    $recommendationsHtml = ""
    $displayedRecommendations = $recommendationsData.Recommendations | Select-Object -First $MaxRecommendations

    foreach ($rec in $displayedRecommendations) {
        $priorityClass = switch ($rec.Priority) {
            'High' { 'priority-high' }
            'Medium' { 'priority-medium' }
            'Low' { 'priority-low' }
            default { 'priority-medium' }
        }

        $osTag = if ($rec.OSSpecific) { '<span class="os-specific-tag">OS-Specific</span>' } else { '' }

        $recommendationsHtml += @"
<div class="recommendation-item $priorityClass">
    <div class="rec-header">
        <span class="rec-icon">$($rec.Icon)</span>
        <div class="rec-title-group">
            <h4 class="rec-title">$($rec.Title)</h4>
            <span class="rec-category">$($rec.Category)</span>
            $osTag
        </div>
        <span class="rec-priority">$($rec.Priority)</span>
    </div>
    <p class="rec-description">$($rec.Description)</p>
    <div class="rec-action">
        <strong>Action:</strong> $($rec.Action)
    </div>
</div>
"@
    }

    # Build complete section
    $sectionHtml = @"
<section class="card os-recommendations-section">
    <div class="card-header">
        <h3 class="card-title">🖥️ Operating System Context & Recommendations</h3>
        <div class="card-subtitle">
            Tailored for your Windows configuration
        </div>
    </div>
    <div class="card-content">
        $osContextHtml

        <div class="recommendations-summary">
            <div class="summary-stat">
                <span class="stat-value">$($recommendationsData.TotalRecommendations)</span>
                <span class="stat-label">Total Recommendations</span>
            </div>
            <div class="summary-stat priority-high">
                <span class="stat-value">$($recommendationsData.HighPriority)</span>
                <span class="stat-label">High Priority</span>
            </div>
            <div class="summary-stat priority-medium">
                <span class="stat-value">$($recommendationsData.MediumPriority)</span>
                <span class="stat-label">Medium Priority</span>
            </div>
            <div class="summary-stat priority-low">
                <span class="stat-value">$($recommendationsData.LowPriority)</span>
                <span class="stat-label">Low Priority</span>
            </div>
            <div class="summary-stat os-specific">
                <span class="stat-value">$($recommendationsData.OSSpecificCount)</span>
                <span class="stat-label">OS-Specific</span>
            </div>
        </div>

        <div class="recommendations-container">
            <h4 class="recommendations-title">📋 Recommended Actions</h4>
            $recommendationsHtml
        </div>
    </div>
</section>
"@

    return $sectionHtml
}

<#
.SYNOPSIS
    Tests if a specific Windows feature is available on the current OS

.DESCRIPTION
    Checks OS context for feature availability flags. Useful for conditional
    recommendations or feature-specific guidance.

.PARAMETER OSContext
    OS context object from Get-WindowsVersionContext

.PARAMETER FeatureName
    Name of feature to check (e.g., 'ModernUI', 'AndroidApps', 'SnapLayouts')

.OUTPUTS
    [bool] True if feature is supported, False otherwise

.EXAMPLE
    PS> $osContext = Get-WindowsVersionContext
    PS> $hasAndroidSupport = Test-OSFeatureAvailability -OSContext $osContext -FeatureName 'AndroidApps'
#>
function Test-OSFeatureAvailability {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$OSContext,

        [Parameter(Mandatory)]
        [string]$FeatureName
    )

    if (-not $OSContext.SupportedFeatures) {
        Write-Warning "OS context does not contain SupportedFeatures property"
        return $false
    }

    if ($OSContext.SupportedFeatures.ContainsKey($FeatureName)) {
        return [bool]$OSContext.SupportedFeatures[$FeatureName]
    }

    Write-Verbose "Feature '$FeatureName' not found in OS context"
    return $false
}

#endregion

#region Export Module Members

Export-ModuleMember -Function @(
    'Get-OSSpecificRecommendations',
    'Format-OSContextForReport',
    'Build-OSContextSection',
    'Test-OSFeatureAvailability'
)

#endregion

