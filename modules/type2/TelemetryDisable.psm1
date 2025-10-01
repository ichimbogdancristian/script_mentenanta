#Requires -Version 7.0

<#
.SYNOPSIS
    Telemetry and Privacy Disable Module - Type 2 (System Modification)

.DESCRIPTION
    Comprehensive disabling of Windows telemetry, privacy-invasive features, and tracking.
    Configures registry settings, services, and notifications for enhanced privacy.

.NOTES
    Module Type: Type 2 (System Modification)
    Dependencies: Registry access, service control capabilities
    Requires: Administrator privileges
    Author: Windows Maintenance Automation Project
    Version: 1.0.0
#>

using namespace System.Collections.Generic

#region Public Functions

<#
.SYNOPSIS
    Disables Windows telemetry and privacy-invasive features
    
.DESCRIPTION
    Performs comprehensive privacy hardening by disabling telemetry collection,
    data sharing, consumer features, and various tracking mechanisms.
    
.PARAMETER DisableServices
    Disable telemetry-related Windows services
    
.PARAMETER DisableNotifications
    Disable Windows notifications and suggestions
    
.PARAMETER DisableConsumerFeatures
    Disable Windows consumer features and suggestions
    
.PARAMETER DisableCortana
    Disable Cortana voice assistant
    
.PARAMETER DisableLocationTracking
    Disable location tracking and services
    
.PARAMETER DryRun
    Simulate changes without applying them
    
.EXAMPLE
    $results = Disable-WindowsTelemetry
    
.EXAMPLE
    $results = Disable-WindowsTelemetry -DisableCortana -DisableLocationTracking -DryRun
#>
function Disable-WindowsTelemetry {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact='Medium')]
    param(
        [Parameter()]
        [switch]$DisableServices = $true,
        
        [Parameter()]
        [switch]$DisableNotifications = $true,
        
        [Parameter()]
        [switch]$DisableConsumerFeatures = $true,
        
        [Parameter()]
        [switch]$DisableCortana = $false,
        
        [Parameter()]
        [switch]$DisableLocationTracking = $false,
        
        [Parameter()]
        [switch]$DryRun
    )
    
    Write-Host "🔒 Starting Windows telemetry and privacy hardening..." -ForegroundColor Cyan
    $startTime = Get-Date
    
    if ($DryRun) {
        Write-Host "  🧪 DRY RUN MODE - No changes will be applied" -ForegroundColor Magenta
    }
    
    # Initialize results tracking
    $results = @{
        TotalOperations = 0
        Successful = 0
        Failed = 0
        Skipped = 0
        DryRun = $DryRun.IsPresent
        Details = [List[PSCustomObject]]::new()
        Categories = @{
            Registry = @{ Applied = 0; Failed = 0 }
            Services = @{ Disabled = 0; Failed = 0 }
            Notifications = @{ Disabled = 0; Failed = 0 }
            Features = @{ Disabled = 0; Failed = 0 }
        }
    }
    
    try {
        # Apply core telemetry registry settings
        Write-Host "  📝 Configuring telemetry registry settings..." -ForegroundColor Gray
        $regResults = Set-TelemetryRegistrySettings -DryRun:$DryRun
        Merge-Results -Results $results -NewResults $regResults -Category 'Registry'
        
        # Disable telemetry services
        if ($DisableServices) {
            Write-Host "  🛑 Disabling telemetry services..." -ForegroundColor Gray
            $serviceResults = Disable-TelemetryServices -DryRun:$DryRun
            Merge-Results -Results $results -NewResults $serviceResults -Category 'Services'
        }
        
        # Disable notifications and suggestions
        if ($DisableNotifications) {
            Write-Host "  🔕 Disabling notifications and suggestions..." -ForegroundColor Gray
            $notifyResults = Disable-WindowsNotifications -DryRun:$DryRun
            Merge-Results -Results $results -NewResults $notifyResults -Category 'Notifications'
        }
        
        # Disable consumer features
        if ($DisableConsumerFeatures) {
            Write-Host "  🛒 Disabling consumer features..." -ForegroundColor Gray
            $consumerResults = Disable-ConsumerFeatures -DryRun:$DryRun
            Merge-Results -Results $results -NewResults $consumerResults -Category 'Features'
        }
        
        # Disable Cortana if requested
        if ($DisableCortana) {
            Write-Host "  🎤 Disabling Cortana..." -ForegroundColor Gray
            $cortanaResults = Disable-CortanaFeature -DryRun:$DryRun
            Merge-Results -Results $results -NewResults $cortanaResults -Category 'Features'
        }
        
        # Disable location tracking if requested
        if ($DisableLocationTracking) {
            Write-Host "  📍 Disabling location tracking..." -ForegroundColor Gray
            $locationResults = Disable-LocationServices -DryRun:$DryRun
            Merge-Results -Results $results -NewResults $locationResults -Category 'Features'
        }
        
        $duration = ((Get-Date) - $startTime).TotalSeconds
        
        # Summary output
        $statusIcon = if ($results.Failed -eq 0) { "✅" } else { "⚠️" }
        Write-Host "  $statusIcon Privacy hardening completed in $([math]::Round($duration, 2))s" -ForegroundColor Green
        Write-Host "    📊 Operations: $($results.TotalOperations), Successful: $($results.Successful), Failed: $($results.Failed)" -ForegroundColor Gray
        
        if ($results.Failed -gt 0) {
            Write-Host "    ❌ Some operations failed. Check logs for details." -ForegroundColor Yellow
        }
        
        return $results
    }
    catch {
        Write-Error "Privacy hardening failed: $_"
        throw
    }
}

<#
.SYNOPSIS
    Tests current privacy and telemetry settings
    
.DESCRIPTION
    Evaluates the current state of Windows privacy and telemetry settings
    to determine what changes would be made.
    
.EXAMPLE
    $status = Test-PrivacySettings
#>
function Test-PrivacySettings {
    [CmdletBinding()]
    param()
    
    Write-Host "🔍 Analyzing current privacy and telemetry settings..." -ForegroundColor Cyan
    
    $analysis = @{
        TelemetryLevel = Get-TelemetryLevel
        ServicesRunning = Get-TelemetryServiceStatus
        NotificationsEnabled = Test-NotificationsEnabled
        ConsumerFeaturesEnabled = Test-ConsumerFeaturesEnabled
        CortanaEnabled = Test-CortanaEnabled
        LocationServicesEnabled = Test-LocationServicesEnabled
        Recommendations = [List[string]]::new()
    }
    
    # Generate recommendations
    if ($analysis.TelemetryLevel -gt 0) {
        $analysis.Recommendations.Add("Reduce telemetry level from $($analysis.TelemetryLevel) to 0")
    }
    
    if ($analysis.ServicesRunning -gt 0) {
        $analysis.Recommendations.Add("Disable $($analysis.ServicesRunning) telemetry services")
    }
    
    if ($analysis.NotificationsEnabled) {
        $analysis.Recommendations.Add("Disable Windows notifications and suggestions")
    }
    
    if ($analysis.ConsumerFeaturesEnabled) {
        $analysis.Recommendations.Add("Disable Windows consumer features")
    }
    
    Write-Host "  📊 Telemetry Level: $($analysis.TelemetryLevel)" -ForegroundColor Gray
    Write-Host "  🛑 Telemetry Services Running: $($analysis.ServicesRunning)" -ForegroundColor Gray
    Write-Host "  💡 Recommendations: $($analysis.Recommendations.Count)" -ForegroundColor Gray
    
    return $analysis
}

#endregion

#region Registry Configuration

<#
.SYNOPSIS
    Configures telemetry-related registry settings
#>
function Set-TelemetryRegistrySettings {
    [CmdletBinding()]
    param(
        [Parameter()]
        [switch]$DryRun
    )
    
    $results = @{
        Applied = 0
        Failed = 0
        Details = [List[PSCustomObject]]::new()
    }
    
    # Core telemetry registry settings
    $telemetrySettings = @{
        'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' = @{
            'AllowTelemetry' = 0
            'DoNotShowFeedbackNotifications' = 1
            'AllowCommercialDataPipeline' = 0
            'AllowDeviceNameInTelemetry' = 0
        }
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection' = @{
            'AllowTelemetry' = 0
            'MaxTelemetryAllowed' = 0
        }
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' = @{
            'ContentDeliveryAllowed' = 0
            'OemPreInstalledAppsEnabled' = 0
            'PreInstalledAppsEnabled' = 0
            'SilentInstalledAppsEnabled' = 0
            'SubscribedContentEnabled' = 0
            'SystemPaneSuggestionsEnabled' = 0
            'SoftLandingEnabled' = 0
        }
        'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' = @{
            'DisableWindowsConsumerFeatures' = 1
            'DisableCloudOptimizedContent' = 1
            'DisableSoftLanding' = 1
        }
    }
    
    foreach ($registryPath in $telemetrySettings.Keys) {
        $pathResult = @{
            Path = $registryPath
            Settings = 0
            Success = $true
            Error = $null
        }
        
        try {
            # Check if path exists, create if not
            if (-not (Test-Path $registryPath)) {
                if ($DryRun) {
                    Write-Host "    [DRY RUN] Would create registry path: $registryPath" -ForegroundColor DarkYellow
                } else {
                    New-Item -Path $registryPath -Force | Out-Null
                }
            }
            
            $settings = $telemetrySettings[$registryPath]
            foreach ($setting in $settings.GetEnumerator()) {
                try {
                    if ($DryRun) {
                        Write-Host "    [DRY RUN] Would set $($setting.Key) = $($setting.Value) in $registryPath" -ForegroundColor DarkYellow
                        $pathResult.Settings++
                    } else {
                        # Check if value needs to be changed (idempotent operation)
                        $currentValue = $null
                        try {
                            $currentValue = (Get-ItemProperty -Path $registryPath -Name $setting.Key -ErrorAction SilentlyContinue).$($setting.Key)
                        } catch { 
                            $currentValue = $null 
                        }
                        
                        if ($currentValue -ne $setting.Value) {
                            Set-ItemProperty -Path $registryPath -Name $setting.Key -Value $setting.Value -Force
                            $pathResult.Settings++
                        }
                    }
                    
                    $results.Applied++
                }
                catch {
                    $pathResult.Success = $false
                    $pathResult.Error = $_.Exception.Message
                    $results.Failed++
                    Write-Warning "Failed to set registry value $($setting.Key): $_"
                    break
                }
            }
        }
        catch {
            $pathResult.Success = $false
            $pathResult.Error = $_.Exception.Message
            $results.Failed++
            Write-Warning "Failed to access registry path ${registryPath}: $_"
        }
        
        $results.Details.Add([PSCustomObject]$pathResult)
    }
    
    return $results
}

#endregion

#region Service Management

<#
.SYNOPSIS
    Disables telemetry-related Windows services
#>
function Disable-TelemetryServices {
    [CmdletBinding()]
    param(
        [Parameter()]
        [switch]$DryRun
    )
    
    $results = @{
        Disabled = 0
        Failed = 0
        Details = [List[PSCustomObject]]::new()
    }
    
    # Telemetry services to disable
    $telemetryServices = @(
        'DiagTrack',           # Connected User Experiences and Telemetry
        'dmwappushservice',    # Device Management Wireless Application Protocol
        'RetailDemo',          # Retail Demo Service
        'WerSvc'              # Windows Error Reporting (optional)
    )
    
    foreach ($serviceName in $telemetryServices) {
        $serviceResult = @{
            Name = $serviceName
            Success = $false
            Action = 'None'
            Error = $null
        }
        
        try {
            $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
            
            if (-not $service) {
                $serviceResult.Action = 'Not Found'
                $serviceResult.Success = $true
                Write-Host "    ℹ️  Service $serviceName not found on this system" -ForegroundColor Gray
            }
            elseif ($service.StartType -eq 'Disabled') {
                $serviceResult.Action = 'Already Disabled'
                $serviceResult.Success = $true
                Write-Host "    ✅ Service $serviceName already disabled" -ForegroundColor Green
            }
            else {
                if ($DryRun) {
                    $serviceResult.Action = 'Would Disable'
                    $serviceResult.Success = $true
                    Write-Host "    [DRY RUN] Would disable service: $serviceName" -ForegroundColor DarkYellow
                } else {
                    # Stop the service if running
                    if ($service.Status -eq 'Running') {
                        Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
                    }
                    
                    # Disable the service
                    Set-Service -Name $serviceName -StartupType Disabled
                    $serviceResult.Action = 'Disabled'
                    $serviceResult.Success = $true
                    Write-Host "    🛑 Disabled service: $serviceName" -ForegroundColor Yellow
                }
                
                $results.Disabled++
            }
        }
        catch {
            $serviceResult.Error = $_.Exception.Message
            $results.Failed++
            Write-Warning "Failed to disable service ${serviceName}: $_"
        }
        
        $results.Details.Add([PSCustomObject]$serviceResult)
    }
    
    return $results
}

#endregion

#region Notification Management

<#
.SYNOPSIS
    Disables Windows notifications and suggestions
#>
function Disable-WindowsNotifications {
    [CmdletBinding()]
    param(
        [Parameter()]
        [switch]$DryRun
    )
    
    $results = @{
        Disabled = 0
        Failed = 0
        Details = [List[PSCustomObject]]::new()
    }
    
    try {
        $notificationPath = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Notifications\Settings'
        
        if (-not (Test-Path $notificationPath)) {
            if ($DryRun) {
                Write-Host "    [DRY RUN] Would create notification settings path" -ForegroundColor DarkYellow
            } else {
                New-Item -Path $notificationPath -Force | Out-Null
            }
        }
        
        # Global notification settings
        $globalSettings = @{
            'NOC_GLOBAL_SETTING_TOASTS_ENABLED' = 0
            'NOC_GLOBAL_SETTING_BADGE_ENABLED' = 0
            'NOC_GLOBAL_SETTING_SOUND_ENABLED' = 0
        }
        
        foreach ($setting in $globalSettings.GetEnumerator()) {
            try {
                if ($DryRun) {
                    Write-Host "    [DRY RUN] Would disable global notification: $($setting.Key)" -ForegroundColor DarkYellow
                } else {
                    Set-ItemProperty -Path $notificationPath -Name $setting.Key -Value $setting.Value -Force
                    Write-Host "    🔕 Disabled notification setting: $($setting.Key)" -ForegroundColor Yellow
                }
                
                $results.Disabled++
            }
            catch {
                $results.Failed++
                Write-Warning "Failed to disable notification setting $($setting.Key): $_"
            }
        }
        
        # Disable per-app notifications
        $appNotifications = Get-ChildItem -Path $notificationPath -ErrorAction SilentlyContinue | 
            Where-Object { $_.PSChildName -notin $globalSettings.Keys }
        
        foreach ($app in $appNotifications) {
            try {
                if ($DryRun) {
                    Write-Host "    [DRY RUN] Would disable notifications for: $($app.PSChildName)" -ForegroundColor DarkYellow
                } else {
                    Set-ItemProperty -Path $app.PSPath -Name 'Enabled' -Value 0 -Force -ErrorAction SilentlyContinue
                }
                
                $results.Disabled++
            }
            catch {
                $results.Failed++
                continue
            }
        }
        
    }
    catch {
        $results.Failed++
        Write-Warning "Failed to disable notifications: $_"
    }
    
    return $results
}

#endregion

#region Consumer Features

<#
.SYNOPSIS
    Disables Windows consumer features and suggestions
#>
function Disable-ConsumerFeatures {
    [CmdletBinding()]
    param(
        [Parameter()]
        [switch]$DryRun
    )
    
    $results = @{
        Disabled = 0
        Failed = 0
        Details = [List[PSCustomObject]]::new()
    }
    
    # Consumer features registry settings
    $consumerSettings = @{
        'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' = @{
            'DisableWindowsConsumerFeatures' = 1
            'DisableConsumerAccountStateContent' = 1
            'DisableCloudOptimizedContent' = 1
        }
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' = @{
            'SystemPaneSuggestionsEnabled' = 0
            'SilentInstalledAppsEnabled' = 0
            'PreInstalledAppsEnabled' = 0
            'OemPreInstalledAppsEnabled' = 0
        }
    }
    
    foreach ($registryPath in $consumerSettings.Keys) {
        try {
            if (-not (Test-Path $registryPath)) {
                if ($DryRun) {
                    Write-Host "    [DRY RUN] Would create consumer features path: $registryPath" -ForegroundColor DarkYellow
                } else {
                    New-Item -Path $registryPath -Force | Out-Null
                }
            }
            
            $settings = $consumerSettings[$registryPath]
            foreach ($setting in $settings.GetEnumerator()) {
                try {
                    if ($DryRun) {
                        Write-Host "    [DRY RUN] Would set $($setting.Key) = $($setting.Value)" -ForegroundColor DarkYellow
                    } else {
                        Set-ItemProperty -Path $registryPath -Name $setting.Key -Value $setting.Value -Force
                    }
                    
                    $results.Disabled++
                }
                catch {
                    $results.Failed++
                    Write-Warning "Failed to set consumer feature setting $($setting.Key): $_"
                }
            }
        }
        catch {
            $results.Failed++
            Write-Warning "Failed to configure consumer features at ${registryPath}: $_"
        }
    }
    
    return $results
}

#endregion

#region Feature-Specific Functions

<#
.SYNOPSIS
    Disables Cortana voice assistant
#>
function Disable-CortanaFeature {
    [CmdletBinding()]
    param([switch]$DryRun)
    
    $results = @{ Disabled = 0; Failed = 0; Details = @() }
    
    $cortanaSettings = @{
        'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search' = @{
            'AllowCortana' = 0
            'DisableWebSearch' = 1
            'ConnectedSearchUseWeb' = 0
        }
    }
    
    foreach ($path in $cortanaSettings.Keys) {
        try {
            if (-not (Test-Path $path)) {
                if (-not $DryRun) { New-Item -Path $path -Force | Out-Null }
            }
            
            foreach ($setting in $cortanaSettings[$path].GetEnumerator()) {
                if ($DryRun) {
                    Write-Host "    [DRY RUN] Would disable Cortana setting: $($setting.Key)" -ForegroundColor DarkYellow
                } else {
                    Set-ItemProperty -Path $path -Name $setting.Key -Value $setting.Value -Force
                }
                $results.Disabled++
            }
        }
        catch {
            $results.Failed++
            Write-Warning "Failed to disable Cortana: $_"
        }
    }
    
    return $results
}

<#
.SYNOPSIS
    Disables location tracking services
#>
function Disable-LocationServices {
    [CmdletBinding()]
    param([switch]$DryRun)
    
    $results = @{ Disabled = 0; Failed = 0; Details = @() }
    
    $locationSettings = @{
        'HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors' = @{
            'DisableLocation' = 1
            'DisableLocationScripting' = 1
        }
    }
    
    foreach ($path in $locationSettings.Keys) {
        try {
            if (-not (Test-Path $path)) {
                if (-not $DryRun) { New-Item -Path $path -Force | Out-Null }
            }
            
            foreach ($setting in $locationSettings[$path].GetEnumerator()) {
                if ($DryRun) {
                    Write-Host "    [DRY RUN] Would disable location setting: $($setting.Key)" -ForegroundColor DarkYellow
                } else {
                    Set-ItemProperty -Path $path -Name $setting.Key -Value $setting.Value -Force
                }
                $results.Disabled++
            }
        }
        catch {
            $results.Failed++
            Write-Warning "Failed to disable location services: $_"
        }
    }
    
    return $results
}

#endregion

#region Helper Functions

function Get-TelemetryLevel {
    try {
        $value = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection' -Name AllowTelemetry -ErrorAction SilentlyContinue).AllowTelemetry
        return [int]($value ?? 3)
    } catch { return 3 }
}

function Get-TelemetryServiceStatus {
    $services = @('DiagTrack', 'dmwappushservice', 'RetailDemo')
    return ($services | ForEach-Object { Get-Service -Name $_ -ErrorAction SilentlyContinue } | Where-Object { $_.Status -eq 'Running' }).Count
}

function Test-NotificationsEnabled {
    try {
        $value = (Get-ItemProperty -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Notifications\Settings' -Name NOC_GLOBAL_SETTING_TOASTS_ENABLED -ErrorAction SilentlyContinue).NOC_GLOBAL_SETTING_TOASTS_ENABLED
        return $value -ne 0
    } catch { return $true }
}

function Test-ConsumerFeaturesEnabled {
    try {
        $value = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' -Name DisableWindowsConsumerFeatures -ErrorAction SilentlyContinue).DisableWindowsConsumerFeatures
        return $value -ne 1
    } catch { return $true }
}

function Test-CortanaEnabled {
    try {
        $value = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search' -Name AllowCortana -ErrorAction SilentlyContinue).AllowCortana
        return $value -ne 0
    } catch { return $true }
}

function Test-LocationServicesEnabled {
    try {
        $value = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors' -Name DisableLocation -ErrorAction SilentlyContinue).DisableLocation
        return $value -ne 1
    } catch { return $true }
}

function Merge-Results {
    param($Results, $NewResults, $Category)
    
    $Results.TotalOperations += ($NewResults.Applied ?? 0) + ($NewResults.Disabled ?? 0)
    $Results.Successful += ($NewResults.Applied ?? 0) + ($NewResults.Disabled ?? 0)
    $Results.Failed += ($NewResults.Failed ?? 0)
    
    if ($Results.Categories.ContainsKey($Category)) {
        $Results.Categories[$Category].Applied = ($NewResults.Applied ?? 0)
        $Results.Categories[$Category].Failed = ($NewResults.Failed ?? 0)
    }
}

#endregion

# Export module functions
Export-ModuleMember -Function @(
    'Disable-WindowsTelemetry',
    'Test-PrivacySettings'
)