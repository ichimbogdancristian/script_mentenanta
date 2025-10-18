#Requires -Version 7.0
# Module Dependencies:
#   - LoggingManager.psm1 (for structured logging)

<#
.SYNOPSIS
    Telemetry Audit Module - Type 1 (Inventory/Reporting)

.DESCRIPTION
    Audits Windows telemetry and privacy-related services, registry settings, and features.
    Identifies active telemetry collection points and privacy-invasive configurations.

.NOTES
    Module Type: Type 1 (Inventory/Reporting)
    Dependencies: Registry access, service enumeration
    Author: Windows Maintenance Automation Project
    Version: 1.0.0
#>

using namespace System.Collections.Generic

# Import required modules
$ModuleRoot = Split-Path -Parent $PSScriptRoot
# v3.0 Type 1 module - imported by Type 2 modules
# Import CoreInfrastructure for configuration and logging
$ModuleRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$CoreInfraPath = Join-Path $ModuleRoot 'core\CoreInfrastructure.psm1'
if (Test-Path $CoreInfraPath) {
    Import-Module $CoreInfraPath -Force
}

# Fallback functions if CoreInfrastructure functions not available in this scope
if (-not (Get-Command 'Write-LogEntry' -ErrorAction SilentlyContinue)) {
    function Write-LogEntry {
        param($Level, $Component, $Message, $Data)
        Write-Information "[$Level] [$Component] $Message" -InformationAction Continue
    }
}

if (-not (Get-Command 'Get-SessionPath' -ErrorAction SilentlyContinue)) {
    function Get-SessionPath {
        param($Category, $SubCategory, $FileName)
        
        # Try to construct proper path using environment variables set by orchestrator
        $tempRoot = if ($env:MAINTENANCE_TEMP_ROOT) { $env:MAINTENANCE_TEMP_ROOT } else { Join-Path $env:TEMP 'maintenance' }
        
        if ($Category -and (Test-Path $tempRoot)) {
            $categoryPath = Join-Path $tempRoot $Category
            if (-not (Test-Path $categoryPath)) {
                try { New-Item -Path $categoryPath -ItemType Directory -Force | Out-Null } catch {}
            }
            
            if ($SubCategory) {
                $categoryPath = Join-Path $categoryPath $SubCategory
                if (-not (Test-Path $categoryPath)) {
                    try { New-Item -Path $categoryPath -ItemType Directory -Force | Out-Null } catch {}
                }
            }
            
            return Join-Path $categoryPath $FileName
        }
        else {
            Write-Warning "Session path unavailable - using current directory fallback"
            return $FileName
        }
    }
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
function Get-TelemetryAudit {
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

    Write-Information "🔍 Starting telemetry and privacy audit..." -InformationAction Continue
    
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
            AuditTimestamp    = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            TelemetryFindings = @()
            PrivacyIssues     = @()
            ActiveServices    = @()
            PrivacyScore      = 0
            Recommendations   = @()
        }

        # Audit different categories
        if ($IncludeServices) {
            Write-Information "  🔧 Auditing telemetry services..." -InformationAction Continue
            $auditResults.ServicesAudit = Get-TelemetryServicesAudit
            $auditResults.PrivacyIssues += $auditResults.ServicesAudit.Issues
            $auditResults.ActiveServices += $auditResults.ServicesAudit.ActiveServices
        }

        if ($IncludeRegistry) {
            Write-Information "  📝 Auditing privacy registry settings..." -InformationAction Continue
            $auditResults.RegistryAudit = Get-PrivacyRegistryAudit
            $auditResults.PrivacyIssues += $auditResults.RegistryAudit.Issues
        }

        if ($IncludeFeatures) {
            Write-Information "  ✨ Auditing consumer features..." -InformationAction Continue
            $auditResults.FeaturesAudit = Get-ConsumerFeaturesAudit
            $auditResults.PrivacyIssues += $auditResults.FeaturesAudit.Issues
        }

        if ($IncludeApps) {
            Write-Information "  📱 Auditing built-in apps..." -InformationAction Continue
            $auditResults.AppsAudit = Get-BuiltInAppsAudit
            $auditResults.PrivacyIssues += $auditResults.AppsAudit.Issues
        }

        # Calculate privacy score and generate recommendations
        $auditResults.PrivacyScore = Get-PrivacyScore -AuditResults $auditResults
        $auditResults.Recommendations = New-PrivacyRecommendations -AuditResults $auditResults

        Write-Information "✓ Telemetry audit completed. Privacy Score: $($auditResults.PrivacyScore.Overall)/100" -InformationAction Continue

        # Save results to session data
        try {
            $outputPath = Get-SessionPath -Category 'data' -FileName 'telemetry-audit.json'
            $auditResults | ConvertTo-Json -Depth 10 | Out-File -FilePath $outputPath -Encoding UTF8
            Write-Information "Audit results saved to: $outputPath" -InformationAction Continue
        }
        catch {
            Write-Warning "Failed to save audit results: $($_.Exception.Message)"
        }

        # Complete performance tracking
        try {
            Complete-PerformanceTracking -Context $perfContext -Status 'Success' -ResultCount $auditResults.PrivacyIssues.Count
        }
        catch {}

        return [PSCustomObject]$auditResults

    }
    catch {
        $errorMsg = "Telemetry audit failed: $($_.Exception.Message)"
        Write-Error $errorMsg
        
        try {
            Write-LogEntry -Level 'ERROR' -Component 'TELEMETRY-AUDIT' -Message $errorMsg -Data @{ Error = $_.Exception }
            Complete-PerformanceTracking -Context $perfContext -Status 'Failed' -ErrorMessage $errorMsg
        }
        catch {}
        
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
                    $issues += [PSCustomObject]@{
                        Category         = 'Services'
                        Type             = 'ActiveTelemetryService'
                        Description      = "Active telemetry service: $($service.DisplayName)"
                        Impact           = 'High'
                        Service          = $serviceName
                        CurrentStatus    = $service.Status
                        CurrentStartType = $service.StartType
                        Recommendation   = 'Disable service to improve privacy'
                    }
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
        foreach ($appPattern in $telemetryApps.Keys) {
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

        # Check Cortana specifically
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

    $baseScore = 100
    $deductions = 0

    # Deduct points based on privacy issues
    foreach ($issue in $AuditResults.PrivacyIssues) {
        switch ($issue.Impact) {
            'High' { $deductions += 20 }
            'Medium' { $deductions += 10 }
            'Low' { $deductions += 5 }
        }
    }

    $overallScore = [math]::Max(0, $baseScore - $deductions)

    return [PSCustomObject]@{
        Overall    = $overallScore
        MaxScore   = $baseScore
        Deductions = $deductions
        IssueCount = $AuditResults.PrivacyIssues.Count
        Category   = if ($overallScore -ge 90) { 'Excellent Privacy' } 
        elseif ($overallScore -ge 70) { 'Good Privacy' } 
        elseif ($overallScore -ge 50) { 'Fair Privacy' } 
        else { 'Poor Privacy - Needs Attention' }
    }
}

<#
.SYNOPSIS
    Generates privacy improvement recommendations
#>
function New-PrivacyRecommendations {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$AuditResults
    )

    $recommendations = @()

    # Count issues by impact
    $highImpact = $AuditResults.PrivacyIssues | Where-Object { $_.Impact -eq 'High' }
    $mediumImpact = $AuditResults.PrivacyIssues | Where-Object { $_.Impact -eq 'Medium' }
    $lowImpact = $AuditResults.PrivacyIssues | Where-Object { $_.Impact -eq 'Low' }

    if ($highImpact.Count -gt 0) {
        $recommendations += "🔴 Critical: Address $($highImpact.Count) high-impact privacy issues immediately"
        $recommendations += "   Focus on telemetry services, data collection settings, and consumer features"
    }

    if ($mediumImpact.Count -gt 0) {
        $recommendations += "🟡 Important: Fix $($mediumImpact.Count) medium-impact privacy settings"
        $recommendations += "   Review advertising settings, app permissions, and feature configurations"
    }

    if ($lowImpact.Count -gt 0) {
        $recommendations += "🟢 Optional: Optimize $($lowImpact.Count) low-impact settings for enhanced privacy"
    }

    # Specific recommendations based on active services
    if ($AuditResults.ActiveServices.Count -gt 0) {
        $recommendations += "🔧 Services: Consider disabling $($AuditResults.ActiveServices.Count) telemetry services"
    }

    if ($AuditResults.PrivacyIssues.Count -eq 0) {
        $recommendations += "✅ Excellent! Your system has strong privacy protections in place"
        $recommendations += "💡 Continue monitoring and reviewing new Windows updates for privacy changes"
    }

    return $recommendations
}

#endregion

# Export public functions
Export-ModuleMember -Function 'Get-TelemetryAudit'