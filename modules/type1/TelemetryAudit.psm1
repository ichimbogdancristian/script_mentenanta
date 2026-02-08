#Requires -Version 7.0

<#
.SYNOPSIS
    Telemetry Audit Module - Type 1 (Detection/Analysis)

.DESCRIPTION
    Audits Windows telemetry and privacy-related services, registry settings, and features.
    Identifies active telemetry collection points and privacy-invasive configurations.
    Part of the v3.0 architecture where Type1 modules provide detection/analysis capabilities.

.NOTES
    Module Type: Type 1 (Detection/Analysis)
    Dependencies: CoreInfrastructure.psm1, CommonUtilities.psm1
    Architecture: v3.0 - Self-contained with fallback capabilities
    Author: Windows Maintenance Automation Project
    Version: 3.0.0
#>

using namespace System.Collections.Generic

# Import CommonUtilities for shared functions (Phase B.3 consolidation)
$commonUtilsPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'core\CommonUtilities.psm1'
if (Test-Path $commonUtilsPath) {
    Import-Module $commonUtilsPath -Force -Global
}

# v3.0 Type 1 module - imported by Type 2 modules
# Note: CoreInfrastructure should be loaded by the Type 2 module before importing this module
# Check if CoreInfrastructure functions are available (loaded by Type2 module)
if (Get-Command 'Write-LogEntry' -ErrorAction SilentlyContinue) {
    Write-Verbose "CoreInfrastructure functions detected - using configuration-based functions"
}
else {
    # Non-critical: Function will be available once Type2 module completes global import
    Write-Verbose "CoreInfrastructure global import in progress - Write-LogEntry will be available momentarily"
}

#region Public Functions

<#
.SYNOPSIS
    Performs comprehensive telemetry and privacy audit

.DESCRIPTION
    Analyzes Windows telemetry services, registry settings, and privacy-related configurations
    to identify data collection and privacy-invasive features that are currently active.

.PARAMETER IncludeServices
    Audit telemetry-related Windows services

.PARAMETER IncludeRegistry
    Audit privacy-related registry settings

.PARAMETER IncludeFeatures
    Audit Windows consumer features and notifications

.PARAMETER IncludeApps
    Audit built-in apps with telemetry capabilities

.PARAMETER UseCache
    Use cached results if available

.EXAMPLE
    $audit = Get-TelemetryAudit

.EXAMPLE
    $audit = Get-TelemetryAudit -IncludeServices -IncludeRegistry
#>
function Get-TelemetryAnalysis {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [switch]$IncludeServices,

        [Parameter()]
        [switch]$IncludeRegistry,

        [Parameter()]
        [switch]$IncludeFeatures,

        [Parameter()]
        [switch]$IncludeApps,

        [Parameter()]
        [switch]$UseCache
    )

    Write-Information " Starting telemetry and privacy audit..." -InformationAction Continue

    # Start performance tracking
    $perfContext = $null
    try {
        $perfContext = Start-PerformanceTracking -OperationName 'TelemetryAudit' -Component 'TELEMETRY-AUDIT'
        Write-LogEntry -Level 'INFO' -Component 'TELEMETRY-AUDIT' -Message 'Starting telemetry audit' -Data @{
            IncludeServices = $IncludeServices
            IncludeRegistry = $IncludeRegistry
            IncludeFeatures = $IncludeFeatures
            IncludeApps     = $IncludeApps
        }
    }
    catch {
        # LoggingManager not available, continue with standard output
        Write-Information "Telemetry audit started" -InformationAction Continue
    }

    try {
        # Check cache first if requested
        if ($UseCache) {
            $cacheFile = Get-SessionPath -Category 'data' -FileName 'telemetry-audit.json'
            if ($cacheFile -and (Test-Path $cacheFile)) {
                $cacheAge = (Get-Date) - (Get-Item $cacheFile).LastWriteTime
                if ($cacheAge.TotalMinutes -le 10) {
                    Write-Information "Using cached telemetry audit data" -InformationAction Continue
                    return Get-Content $cacheFile | ConvertFrom-Json
                }
            }
        }

        # Default to include all categories if none specified
        if (-not $IncludeServices -and -not $IncludeRegistry -and -not $IncludeFeatures -and -not $IncludeApps) {
            $IncludeServices = $IncludeRegistry = $IncludeFeatures = $IncludeApps = $true
        }

        # Initialize audit results
        $auditResults = @{
            AuditTimestamp      = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            TelemetryFindings   = @()
            PrivacyIssues       = @()
            ActiveServices      = @()
            ActiveTelemetryItems = @()
            ActiveTelemetryCount = 0
            PrivacyScore        = 0
            Recommendations     = @()
        }

        # Audit different categories
        if ($IncludeServices) {
            Write-Information "   Auditing telemetry services..." -InformationAction Continue
            $auditResults.ServicesAudit = Get-TelemetryServicesAudit
            $auditResults.PrivacyIssues += $auditResults.ServicesAudit.Issues
            $auditResults.ActiveServices += $auditResults.ServicesAudit.ActiveServices
        }

        if ($IncludeRegistry) {
            Write-Information "   Auditing privacy registry settings..." -InformationAction Continue
            $auditResults.RegistryAudit = Get-PrivacyRegistryAudit
            $auditResults.PrivacyIssues += $auditResults.RegistryAudit.Issues
        }

        if ($IncludeFeatures) {
            Write-Information "   Auditing consumer features..." -InformationAction Continue
            $auditResults.FeaturesAudit = Get-ConsumerFeaturesAudit
            $auditResults.PrivacyIssues += $auditResults.FeaturesAudit.Issues
        }

        if ($IncludeApps) {
            Write-Information "   Auditing built-in apps..." -InformationAction Continue
            $auditResults.AppsAudit = Get-BuiltInAppsAudit
            $auditResults.PrivacyIssues += $auditResults.AppsAudit.Issues
        }

        # Build telemetry items list for Type2 consumption
        $telemetryItems = [System.Collections.Generic.List[PSCustomObject]]::new()

        if ($auditResults.ServicesAudit -and $auditResults.ServicesAudit.ActiveServices) {
            foreach ($service in $auditResults.ServicesAudit.ActiveServices) {
                $telemetryItems.Add([PSCustomObject]@{
                        Type = 'Service'
                        Name = $service.DisplayName ?? $service.Name
                    })
            }
        }

        if ($auditResults.PrivacyIssues) {
            foreach ($issue in $auditResults.PrivacyIssues) {
                $issueType = switch ($issue.Category) {
                    'Services' { 'Service' }
                    'Features' { 'ConsumerFeature' }
                    'Apps' { 'App' }
                    'Registry' { 'Registry' }
                    default { 'Unknown' }
                }

                $telemetryItems.Add([PSCustomObject]@{
                        Type = $issueType
                        Name = $issue.Description
                    })
            }
        }

        $auditResults.ActiveTelemetryItems = $telemetryItems
        $auditResults.ActiveTelemetryCount = $telemetryItems.Count

        # Calculate privacy score and generate recommendations
        $auditResults.PrivacyScore = Get-PrivacyScore -AuditResults $auditResults
        $auditResults.Recommendations = New-PrivacyRecommendations -AuditResults $auditResults

        Write-Information " Telemetry audit completed. Privacy Score: $($auditResults.PrivacyScore.Overall)/100" -InformationAction Continue

        # FIX #5: Save results using standardized Get-AuditResultsPath function
        try {
            # Use standardized path function if available
            if (Get-Command 'Get-AuditResultsPath' -ErrorAction SilentlyContinue) {
                $outputPath = Get-AuditResultsPath -ModuleName 'Telemetry'
            }
            # Fallback to session path
            else {
                $outputPath = Get-SessionPath -Category 'data' -FileName 'telemetry-results.json'
            }

            $auditResults | ConvertTo-Json -Depth 20 -WarningAction SilentlyContinue | Out-File -FilePath $outputPath -Encoding UTF8
            Write-Information "Audit results saved to standardized path: $outputPath" -InformationAction Continue
        }
        catch {
            Write-Warning "Failed to save audit results: $($_.Exception.Message)"
        }

        # Complete performance tracking
        try {
            Complete-PerformanceTracking -Context $perfContext -Status 'Success' -ResultCount $auditResults.PrivacyIssues.Count
        }
        catch {
            Write-Verbose "Performance tracking completion failed - continuing"
        }

        return [PSCustomObject]$auditResults

    }
    catch {
        $errorMsg = "Telemetry audit failed: $($_.Exception.Message)"
        Write-Error $errorMsg

        try {
            Write-LogEntry -Level 'ERROR' -Component 'TELEMETRY-AUDIT' -Message $errorMsg -Data @{ Error = $_.Exception }
            Complete-PerformanceTracking -Context $perfContext -Status 'Failed' -ErrorMessage $errorMsg
        }
        catch {
            Write-Verbose "Performance tracking cleanup failed: $_"
        }

        throw
    }
}

#endregion

#region Private Helper Functions

<#
.SYNOPSIS
    Audits telemetry-related Windows services
#>
function Get-TelemetryServicesAudit {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    $issues = @()
    $activeServices = @()

    # Known telemetry services
    $telemetryServices = @{
        'DiagTrack'        = 'Connected User Experiences and Telemetry'
        'dmwappushservice' = 'Device Management Wireless Application Protocol'
        'RetailDemo'       = 'Retail Demo Service'
        'WerSvc'           = 'Windows Error Reporting Service'
        'PcaSvc'           = 'Program Compatibility Assistant'
        'DusmSvc'          = 'Data Usage'
        'MapsBroker'       = 'Downloaded Maps Manager'
        'lfsvc'            = 'Geolocation Service'
        'SharedAccess'     = 'Internet Connection Sharing (ICS)'
        'TrkWks'           = 'Distributed Link Tracking Client'
    }

    try {
        foreach ($serviceName in $telemetryServices.Keys) {
            $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
            if ($service) {
                $serviceInfo = [PSCustomObject]@{
                    Name        = $serviceName
                    DisplayName = $service.DisplayName
                    Status      = $service.Status
                    StartType   = $service.StartType
                    Description = $telemetryServices[$serviceName]
                }

                if ($service.Status -eq 'Running' -or $service.StartType -eq 'Automatic') {
                    $activeServices += $serviceInfo
                    $issueItem = [PSCustomObject]@{
                        Category         = 'Services'
                        Type             = 'ActiveTelemetryService'
                        Description      = "Active telemetry service: $($service.DisplayName)"
                        Impact           = 'High'
                        Service          = $serviceName
                        CurrentStatus    = $service.Status
                        CurrentStartType = $service.StartType
                        Recommendation   = 'Disable service to improve privacy'
                    }

                    # Log detected active telemetry service
                    Write-DetectionLog -Operation 'Detect' -Target $serviceName -Component 'TELEMETRY-SERVICE' -AdditionalInfo @{
                        Category       = 'Telemetry Service'
                        DisplayName    = $service.DisplayName
                        Description    = $telemetryServices[$serviceName]
                        Status         = $service.Status
                        StartType      = $service.StartType
                        Impact         = 'High'
                        PrivacyRisk    = 'Service actively collecting or transmitting telemetry data'
                        Recommendation = 'Stop and disable service'
                        Reason         = "Telemetry service running or set to automatic start"
                    }

                    $issues += $issueItem
                }
            }
        }
    }
    catch {
        Write-Warning "Failed to audit telemetry services: $($_.Exception.Message)"
    }

    return [PSCustomObject]@{
        TotalServicesChecked = $telemetryServices.Count
        ActiveServices       = $activeServices
        Issues               = $issues
    }
}

<#
.SYNOPSIS
    Audits privacy-related registry settings
#>
function Get-PrivacyRegistryAudit {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    $issues = @()

    # Registry locations and their privacy implications
    $privacySettings = @{
        'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection\AllowTelemetry'                                                          = @{
            ExpectedValue = 0
            Description   = 'Telemetry data collection level'
            Impact        = 'High'
        }
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection\AllowTelemetry'                                           = @{
            ExpectedValue = 0
            Description   = 'Alternative telemetry setting'
            Impact        = 'High'
        }
        'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo\DisabledByGroupPolicy'                                                  = @{
            ExpectedValue = 1
            Description   = 'Advertising ID for apps'
            Impact        = 'Medium'
        }
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo\Enabled'                                                          = @{
            ExpectedValue = 0
            Description   = 'User advertising ID'
            Impact        = 'Medium'
        }
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\EnableActivityFeed'                                               = @{
            ExpectedValue = 0
            Description   = 'Activity feed and timeline'
            Impact        = 'Medium'
        }
        'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System\EnableActivityFeed'                                                              = @{
            ExpectedValue = 0
            Description   = 'Activity feed policy setting'
            Impact        = 'Medium'
        }
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced\Start_TrackProgs'                                               = @{
            ExpectedValue = 0
            Description   = 'Track program launches in Start menu'
            Impact        = 'Low'
        }
        'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Sensor\Overrides\{BFA794E4-F964-4FDB-90F6-51056BFE4B44}\SensorPermissionState' = @{
            ExpectedValue = 0
            Description   = 'Location sensor permission'
            Impact        = 'High'
        }
    }

    try {
        foreach ($registryPath in $privacySettings.Keys) {
            $setting = $privacySettings[$registryPath]
            $pathParts = $registryPath.Split('\')
            $valueName = $pathParts[-1]
            $keyPath = ($pathParts[0..($pathParts.Length - 2)]) -join '\'

            try {
                $currentValue = Get-ItemProperty -Path $keyPath -Name $valueName -ErrorAction SilentlyContinue
                if ($null -ne $currentValue) {
                    $actualValue = $currentValue.$valueName
                    if ($actualValue -ne $setting.ExpectedValue) {
                        $issues += [PSCustomObject]@{
                            Category       = 'Registry'
                            Type           = 'PrivacySetting'
                            Description    = "Privacy setting not optimal: $($setting.Description)"
                            Impact         = $setting.Impact
                            RegistryPath   = $registryPath
                            CurrentValue   = $actualValue
                            ExpectedValue  = $setting.ExpectedValue
                            Recommendation = "Set to $($setting.ExpectedValue) for better privacy"
                        }
                    }
                }
                else {
                    # Setting doesn't exist, might be default (potentially privacy-invasive)
                    $issues += [PSCustomObject]@{
                        Category       = 'Registry'
                        Type           = 'MissingPrivacySetting'
                        Description    = "Privacy setting not configured: $($setting.Description)"
                        Impact         = $setting.Impact
                        RegistryPath   = $registryPath
                        CurrentValue   = 'Not Set'
                        ExpectedValue  = $setting.ExpectedValue
                        Recommendation = "Create setting with value $($setting.ExpectedValue)"
                    }
                }
            }
            catch {
                Write-Verbose "Could not check registry path: $registryPath - $($_.Exception.Message)"
            }
        }
    }
    catch {
        Write-Warning "Failed to audit privacy registry settings: $($_.Exception.Message)"
    }

    return [PSCustomObject]@{
        SettingsChecked = $privacySettings.Count
        Issues          = $issues
    }
}

<#
.SYNOPSIS
    Audits Windows consumer features and notifications
#>
function Get-ConsumerFeaturesAudit {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    $issues = @()

    # Consumer features to check
    $consumerFeatures = @{
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager\SystemPaneSuggestionsEnabled' = @{
            ExpectedValue = 0
            Description   = 'System pane suggestions'
            Impact        = 'Medium'
        }
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager\SilentInstalledAppsEnabled'   = @{
            ExpectedValue = 0
            Description   = 'Silent app installations'
            Impact        = 'High'
        }
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager\PreInstalledAppsEnabled'      = @{
            ExpectedValue = 0
            Description   = 'Pre-installed app suggestions'
            Impact        = 'Medium'
        }
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager\SoftLandingEnabled'           = @{
            ExpectedValue = 0
            Description   = 'Windows tips and suggestions'
            Impact        = 'Low'
        }
        'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent\DisableWindowsConsumerFeatures'               = @{
            ExpectedValue = 1
            Description   = 'Windows consumer features'
            Impact        = 'High'
        }
    }

    try {
        foreach ($registryPath in $consumerFeatures.Keys) {
            $setting = $consumerFeatures[$registryPath]
            $pathParts = $registryPath.Split('\')
            $valueName = $pathParts[-1]
            $keyPath = ($pathParts[0..($pathParts.Length - 2)]) -join '\'

            try {
                $currentValue = Get-ItemProperty -Path $keyPath -Name $valueName -ErrorAction SilentlyContinue
                if ($null -ne $currentValue) {
                    $actualValue = $currentValue.$valueName
                    if ($actualValue -ne $setting.ExpectedValue) {
                        $issues += [PSCustomObject]@{
                            Category       = 'Features'
                            Type           = 'ConsumerFeature'
                            Description    = "Consumer feature enabled: $($setting.Description)"
                            Impact         = $setting.Impact
                            RegistryPath   = $registryPath
                            CurrentValue   = $actualValue
                            ExpectedValue  = $setting.ExpectedValue
                            Recommendation = "Disable for reduced tracking and ads"
                        }
                    }
                }
                else {
                    $issues += [PSCustomObject]@{
                        Category       = 'Features'
                        Type           = 'UnconfiguredFeature'
                        Description    = "Consumer feature not configured: $($setting.Description)"
                        Impact         = $setting.Impact
                        RegistryPath   = $registryPath
                        CurrentValue   = 'Default (Likely Enabled)'
                        ExpectedValue  = $setting.ExpectedValue
                        Recommendation = "Configure to improve privacy"
                    }
                }
            }
            catch {
                Write-Verbose "Could not check consumer feature: $registryPath - $($_.Exception.Message)"
            }
        }
    }
    catch {
        Write-Warning "Failed to audit consumer features: $($_.Exception.Message)"
    }

    return [PSCustomObject]@{
        FeaturesChecked = $consumerFeatures.Count
        Issues          = $issues
    }
}

<#
.SYNOPSIS
    Audits built-in apps with telemetry capabilities
#>
function Get-BuiltInAppsAudit {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    $issues = @()

    # Apps known for telemetry collection
    $telemetryApps = @{
        'Microsoft.BingWeather'         = 'Weather app with location tracking'
        'Microsoft.BingNews'            = 'News app with usage tracking'
        'Microsoft.BingFinance'         = 'Finance app with usage tracking'
        'Microsoft.BingSports'          = 'Sports app with usage tracking'
        'Microsoft.Xbox*'               = 'Xbox apps with gaming telemetry'
        'Microsoft.XboxGameOverlay'     = 'Xbox Game Bar with performance tracking'
        'Microsoft.XboxGamingOverlay'   = 'Xbox Gaming Overlay'
        'Microsoft.YourPhone'           = 'Your Phone app with device sync'
        'Microsoft.People'              = 'People app with contact sync'
        'Microsoft.MixedReality.Portal' = 'Mixed Reality Portal'
        'Microsoft.Advertising.Xaml'    = 'Advertising framework'
    }

    try {
        # Check if Get-AppxPackage cmdlet is available without importing module
        # This avoids triggering Windows AppX module initialization bugs
        $appxAvailable = $null -ne (Get-Command Get-AppxPackage -ErrorAction SilentlyContinue)

        if (-not $appxAvailable) {
            Write-Verbose "AppX cmdlets not available - skipping AppX package telemetry scan"
        }

        if ($appxAvailable) {
            foreach ($appPattern in $telemetryApps.Keys) {
                try {
                    $apps = Get-AppxPackage -AllUsers -Name $appPattern -ErrorAction SilentlyContinue
                    if ($apps) {
                        foreach ($app in $apps) {
                            $issues += [PSCustomObject]@{
                                Category        = 'Apps'
                                Type            = 'TelemetryApp'
                                Description     = "Telemetry-enabled app installed: $($app.Name)"
                                Impact          = 'Medium'
                                AppName         = $app.Name
                                Version         = $app.Version
                                InstallLocation = $app.InstallLocation
                                Recommendation  = $telemetryApps[$appPattern]
                            }
                        }
                    }
                }
                catch {
                    Write-Verbose "Could not check AppX package $appPattern`: $($_.Exception.Message)"
                }
            }

            # Check Cortana specifically
            try {
                $cortana = Get-AppxPackage -AllUsers -Name 'Microsoft.549981C3F5F10' -ErrorAction SilentlyContinue
                if ($cortana) {
                    $issues += [PSCustomObject]@{
                        Category        = 'Apps'
                        Type            = 'CortanaApp'
                        Description     = 'Cortana voice assistant is installed'
                        Impact          = 'High'
                        AppName         = $cortana.Name
                        Version         = $cortana.Version
                        InstallLocation = $cortana.InstallLocation
                        Recommendation  = 'Remove for enhanced privacy (collects voice data)'
                    }
                }
            }
            catch {
                Write-Verbose "Could not check Cortana AppX package: $($_.Exception.Message)"
            }
        }
        else {
            # Add a notification about AppX not being available
            $issues += [PSCustomObject]@{
                Category        = 'Apps'
                Type            = 'PlatformLimitation'
                Description     = 'AppX package auditing not available on this platform'
                Impact          = 'Low'
                AppName         = 'N/A'
                Version         = 'N/A'
                InstallLocation = 'N/A'
                Recommendation  = 'Manual review of installed apps recommended'
            }
        }

    }
    catch {
        Write-Warning "Failed to audit built-in apps: $($_.Exception.Message)"
    }

    return [PSCustomObject]@{
        AppsChecked = $telemetryApps.Count
        Issues      = $issues
    }
}

<#
.SYNOPSIS
    Calculates overall privacy score
#>
function Get-PrivacyScore {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$AuditResults
    )

    # Use generic scoring function from CommonUtilities (Phase B.3 consolidation)
    return Get-GenericHealthScore `
        -Issues $AuditResults.PrivacyIssues `
        -ScoreType 'Privacy' `
        -DeductionMap @{ High = 20; Medium = 10; Low = 5 }
}

<#
.SYNOPSIS
    Generates privacy improvement recommendations
#>
<#
.SYNOPSIS
    Generates privacy recommendations based on audit results

.DESCRIPTION
    Uses generic New-ImpactBasedRecommendations from CommonUtilities.
    Phase B.3 consolidation - reduced from ~45 lines to ~15 lines.
#>
function New-PrivacyRecommendations {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$AuditResults
    )

    return New-ImpactBasedRecommendations `
        -Issues $AuditResults.PrivacyIssues `
        -IssueType 'privacy' `
        -SpecificChecks @{
            ActiveServices = { param($results) 
                if ($results.ActiveServices.Count -gt 0) {
                    " Services: Consider disabling $($results.ActiveServices.Count) telemetry services"
                }
            }
        } `
        -AuditResults $AuditResults
}

<#
.SYNOPSIS
    Type2 wrapper function for telemetry analysis

.DESCRIPTION
    Wrapper function that performs telemetry audit and saves results to temp_files/data/
    for consumption by Type2 modules. This is the v3.0 standardized interface between
    Type1 (detection) and Type2 (action) modules.

    Automatically saves results to temp_files/data/telemetry-results.json using global paths.

.PARAMETER Config
    Configuration hashtable from orchestrator

.EXAMPLE
    $results = Get-TelemetryAnalysis -Config $Config
#>

#endregion

# Backward compatibility alias
New-Alias -Name 'Get-TelemetryAudit' -Value 'Get-TelemetryAnalysis'

# Export public functions
Export-ModuleMember -Function @(
    'Get-TelemetryAnalysis'  #  v3.0 PRIMARY function
) -Alias @('Get-TelemetryAudit')  # Backward compatibility



