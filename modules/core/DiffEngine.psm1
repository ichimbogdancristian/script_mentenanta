#Requires -Version 7.0

<#
.SYNOPSIS
    Diff Engine - Centralized Type1/Type2 diff list generation

.DESCRIPTION
    Creates standardized diff lists by comparing Type1 audit results against
    preexisting configuration lists or settings. Produces module-specific
    diff lists used by Type2 modules to decide whether execution is required.

.NOTES
    Module Type: Core Infrastructure
    Architecture: v4.1 - Diff-based execution pipeline
    Dependencies: CoreInfrastructure.psm1
#>

using namespace System.Collections.Generic

# Import CoreInfrastructure first (required)
$ModuleRoot = Split-Path -Parent $PSScriptRoot
$CoreInfraPath = Join-Path $ModuleRoot 'core\CoreInfrastructure.psm1'
if (Test-Path $CoreInfraPath) {
    Import-Module $CoreInfraPath -Force -Global
}
else {
    throw "CoreInfrastructure module not found at: $CoreInfraPath"
}

function Get-ModuleDiffPlan {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$MainConfig,

        [Parameter()]
        [PSCustomObject]$OSContext
    )

    $plan = @(
        @{
            Type2Module  = 'BloatwareRemoval'
            Type1Key     = 'BloatwareDetection'
            DiffStrategy = 'DetectedVsConfig'
            MatchField   = 'Name'
            ConfigType   = 'Bloatware'
            Enabled      = (-not $MainConfig.modules.skipBloatwareRemoval)
        },
        @{
            Type2Module  = 'EssentialApps'
            Type1Key     = 'EssentialApps'
            DiffStrategy = 'DetectedVsConfig'
            MatchField   = 'name'
            ConfigType   = 'EssentialApps'
            Enabled      = (-not $MainConfig.modules.skipEssentialApps)
        },
        @{
            Type2Module  = 'SystemOptimization'
            Type1Key     = 'SystemOptimization'
            DiffStrategy = 'OptimizationConfig'
            MatchField   = 'Target'
            ConfigType   = 'SystemOptimization'
            Enabled      = (-not $MainConfig.modules.skipSystemOptimization)
        },
        @{
            Type2Module  = 'TelemetryDisable'
            Type1Key     = 'Telemetry'
            DiffStrategy = 'TelemetryConfig'
            MatchField   = 'Type'
            ConfigType   = 'Security'
            Enabled      = (-not $MainConfig.modules.skipTelemetryDisable)
        },
        @{
            Type2Module  = 'WindowsUpdates'
            Type1Key     = 'WindowsUpdates'
            DiffStrategy = 'PendingUpdates'
            MatchField   = 'Title'
            ConfigType   = 'Security'
            Enabled      = (-not $MainConfig.modules.skipWindowsUpdates)
        },
        @{
            Type2Module  = 'AppUpgrade'
            Type1Key     = 'AppUpgrade'
            DiffStrategy = 'AppUpgradeFilter'
            MatchField   = 'Name'
            ConfigType   = 'AppUpgrade'
            Enabled      = (-not $MainConfig.modules.skipAppUpgrade)
        },
        @{
            Type2Module  = 'SecurityEnhancement'
            Type1Key     = 'Security'
            DiffStrategy = 'SecurityRecommendations'
            MatchField   = 'Title'
            ConfigType   = 'Security'
            Enabled      = (-not $MainConfig.modules.skipSecurityEnhancement)
        }
    )

    return $plan | Where-Object { $_.Enabled }
}

function New-DiffListSet {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$MainConfig,

        [Parameter(Mandatory)]
        [hashtable]$AuditResults,

        [Parameter()]
        [PSCustomObject]$OSContext
    )

    $plan = Get-ModuleDiffPlan -MainConfig $MainConfig -OSContext $OSContext
    $diffLists = @{}
    $summary = [ordered]@{}

    foreach ($entry in $plan) {
        $type2Module = $entry.Type2Module
        $type1Key = $entry.Type1Key

        $detectionList = Get-AuditDetectionList -ModuleKey $type1Key -AuditResults $AuditResults
        $detectedCount = $detectionList.Count

        $diffList = @()
        $reason = 'No changes required'

        switch ($entry.DiffStrategy) {
            'DetectedVsConfig' {
                $configData = switch ($entry.ConfigType) {
                    'Bloatware' { Get-BloatwareConfiguration -OSContext $OSContext }
                    'EssentialApps' { Get-EssentialAppsConfiguration }
                    default { $null }
                }

                if ($configData) {
                    $diffList = Compare-DetectedVsConfig -DetectionResults $detectionList -ConfigData $configData -MatchField $entry.MatchField
                }
                else {
                    $diffList = $detectionList
                }
            }
            'OptimizationConfig' {
                $configData = Get-SystemOptimizationConfiguration -OSContext $OSContext
                $diffList = Get-OptimizationDiffList -DetectionResults $detectionList -ConfigData $configData
            }
            'TelemetryConfig' {
                $configData = Get-SecurityConfiguration
                $diffList = Get-TelemetryDiffList -DetectionResults $detectionList -ConfigData $configData
            }
            'PendingUpdates' {
                $configData = Get-SecurityConfiguration
                $diffList = Get-UpdatesDiffList -DetectionResults $detectionList -ConfigData $configData
            }
            'AppUpgradeFilter' {
                $configData = Get-AppUpgradeConfiguration
                $diffList = Get-AppUpgradeDiffList -DetectionResults $detectionList -ConfigData $configData
            }
            'SecurityRecommendations' {
                $configData = Get-SecurityConfiguration
                $diffList = Get-SecurityDiffList -DetectionResults $detectionList -ConfigData $configData
            }
            default {
                $diffList = $detectionList
            }
        }

        if ($diffList.Count -gt 0) {
            $reason = "${detectedCount} detected, ${($diffList.Count)} actionable"
        }

        $diffPath = Save-DiffResults -ModuleName $type2Module -DiffData $diffList -Component 'DIFF-ENGINE'

        $diffLists[$type2Module] = @{
            DiffList      = $diffList
            DiffPath      = $diffPath
            DetectedCount = $detectedCount
            DiffCount     = $diffList.Count
            Reason        = $reason
        }

        $summary[$type2Module] = @{
            DetectedCount = $detectedCount
            DiffCount     = $diffList.Count
        }
    }

    return @{
        DiffLists = $diffLists
        Summary   = $summary
    }
}

function Get-AuditDetectionList {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory)]
        [string]$ModuleKey,

        [Parameter(Mandatory)]
        [hashtable]$AuditResults
    )

    if (-not $AuditResults.ContainsKey($ModuleKey)) {
        return @()
    }

    $auditData = $AuditResults[$ModuleKey]
    if ($null -eq $auditData) {
        return @()
    }

    switch ($ModuleKey) {
        'BloatwareDetection' {
            return (Ensure-Array $auditData)
        }
        'EssentialApps' {
            if ($auditData.MissingApps) { return (Ensure-Array $auditData.MissingApps) }
            return (Ensure-Array $auditData)
        }
        'SystemOptimization' {
            if ($auditData.OptimizationOpportunities) { return (Ensure-Array $auditData.OptimizationOpportunities) }
            return (Ensure-Array $auditData)
        }
        'Telemetry' {
            if ($auditData.ActiveTelemetryItems) { return (Ensure-Array $auditData.ActiveTelemetryItems) }
            return (Ensure-Array $auditData)
        }
        'WindowsUpdates' {
            if ($auditData.PendingAudit -and $auditData.PendingAudit.PendingUpdates) {
                return (Ensure-Array $auditData.PendingAudit.PendingUpdates)
            }
            if ($auditData.PendingUpdates) { return (Ensure-Array $auditData.PendingUpdates) }
            return @()
        }
        'AppUpgrade' {
            return (Ensure-Array $auditData)
        }
        'Security' {
            if ($auditData.Recommendations) { return (Ensure-Array $auditData.Recommendations) }
            return @()
        }
        default {
            if ($auditData.DetectedItems) { return (Ensure-Array $auditData.DetectedItems) }
            return (Ensure-Array $auditData)
        }
    }
}

function Ensure-Array {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory)]
        $InputObject
    )

    if ($null -eq $InputObject) {
        return @()
    }

    if ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string]) {
        return @($InputObject)
    }

    return @($InputObject)
}

function Get-OptimizationDiffList {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory)]
        [array]$DetectionResults,

        [Parameter(Mandatory)]
        $ConfigData
    )

    if (-not $DetectionResults) {
        return @()
    }

    $safeStartupPatterns = @()
    $neverDisablePatterns = @()
    $safeServices = @()

    if ($ConfigData.startupPrograms) {
        $safeStartupPatterns = $ConfigData.startupPrograms.safeToDisablePatterns
        $neverDisablePatterns = $ConfigData.startupPrograms.neverDisable
    }
    if ($ConfigData.services) {
        $safeServices = $ConfigData.services.safeToDisable
    }

    $filtered = foreach ($item in $DetectionResults) {
        if (-not $item) { continue }

        $category = $item.Category
        $target = $item.Target

        if ($category -eq 'Startup') {
            if ($neverDisablePatterns -and (Test-NamePattern -Name $target -Patterns $neverDisablePatterns)) {
                continue
            }
            if ($safeStartupPatterns -and (Test-NamePattern -Name $target -Patterns $safeStartupPatterns)) {
                $item
            }
        }
        elseif ($category -eq 'Services') {
            if ($safeServices -and $safeServices -contains $target) {
                $item
            }
        }
        else {
            $item
        }
    }

    return @($filtered)
}

function Get-TelemetryDiffList {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory)]
        [array]$DetectionResults,

        [Parameter(Mandatory)]
        $ConfigData
    )

    if (-not $DetectionResults) {
        return @()
    }

    $privacyConfig = if ($ConfigData.privacy) { $ConfigData.privacy } else { @{} }
    if (-not ($privacyConfig.disableTelemetry -or $privacyConfig.disableDiagnosticData)) {
        return @()
    }

    $filtered = foreach ($item in $DetectionResults) {
        if (-not $item) { continue }

        $type = $item.Type
        switch ($type) {
            'LocationTracking' { if ($privacyConfig.disableLocationTracking) { $item } }
            'Cortana' { if ($privacyConfig.disableTelemetry) { $item } }
            default { if ($privacyConfig.disableTelemetry) { $item } }
        }
    }

    return @($filtered)
}

function Get-UpdatesDiffList {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory)]
        [array]$DetectionResults,

        [Parameter(Mandatory)]
        $ConfigData
    )

    if (-not $DetectionResults) {
        return @()
    }

    $updatesConfig = if ($ConfigData.updates) { $ConfigData.updates } else { @{} }
    if ($updatesConfig.enableAutomaticUpdates -eq $false) {
        return @()
    }

    return @($DetectionResults)
}

function Get-AppUpgradeDiffList {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory)]
        [array]$DetectionResults,

        [Parameter(Mandatory)]
        $ConfigData
    )

    if (-not $DetectionResults) {
        return @()
    }

    $excludePatterns = @()
    $enabledSources = @('Winget', 'Chocolatey')

    if ($ConfigData) {
        if ($ConfigData.ExcludePatterns) { $excludePatterns = $ConfigData.ExcludePatterns }
        if ($ConfigData.EnabledSources) { $enabledSources = $ConfigData.EnabledSources }
    }

    $filtered = foreach ($item in $DetectionResults) {
        if (-not $item) { continue }

        $name = $item.Name
        $source = $item.Source

        if ($enabledSources -and ($enabledSources -notcontains $source)) {
            continue
        }

        if ($excludePatterns -and (Test-NamePattern -Name $name -Patterns $excludePatterns)) {
            continue
        }

        $item
    }

    return @($filtered)
}

function Get-SecurityDiffList {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory)]
        [array]$DetectionResults,

        [Parameter(Mandatory)]
        $ConfigData
    )

    if (-not $DetectionResults) {
        return @()
    }

    $recConfig = if ($ConfigData.recommendations) { $ConfigData.recommendations } else { @{} }
    if ($recConfig.enforceRecommendations -eq $false) {
        return @()
    }

    return @($DetectionResults)
}

function Test-NamePattern {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [array]$Patterns
    )

    foreach ($pattern in $Patterns) {
        if ([string]::IsNullOrWhiteSpace($pattern)) { continue }
        if ($Name -like $pattern) { return $true }
    }

    return $false
}

Export-ModuleMember -Function @(
    'Get-ModuleDiffPlan',
    'New-DiffListSet'
)
