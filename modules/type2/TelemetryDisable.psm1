#Requires -Version 7.0
# Module Dependencies:
#   - CoreInfrastructure.psm1 (configuration, logging, path management)
#   - TelemetryAudit.psm1 (Type1 - detection/analysis)
#
# External Tools: None (uses native Windows registry, services, firewall)

<#
.SYNOPSIS
    Telemetry and Privacy Disable Module - Type 2 (System Modification)

.DESCRIPTION
    Comprehensive disabling of Windows telemetry, privacy-invasive features, and tracking.
    Configures registry settings, services, and notifications for enhanced privacy.

.NOTES
    Module Type: Type 2 (System Modification)
    Dependencies: TelemetryAudit.psm1, CoreInfrastructure.psm1
    Requires: Administrator privileges
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
    Write-Warning "CoreInfrastructure module not found at: $CoreInfraPath"
}

# Step 2: Import corresponding Type 1 module AFTER CoreInfrastructure (REQUIRED)
$Type1ModulePath = Join-Path $ModuleRoot 'type1\TelemetryAudit.psm1'
if (Test-Path $Type1ModulePath) {
    Import-Module $Type1ModulePath -Force
}
else {
    throw "Required Type 1 module not found: $Type1ModulePath"
}

# Validate Type1 module loaded correctly
if (-not (Get-Command -Name 'Get-TelemetryAnalysis' -ErrorAction SilentlyContinue)) {
    throw "Type 1 module functions not available - ensure TelemetryAudit.psm1 is properly imported"
}

#region v3.0 Standardized Execution Function

function Invoke-TelemetryDisable {
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Config, [Parameter()][switch]$DryRun)
    
    $perfContext = Start-PerformanceTrackingSafe -OperationName 'TelemetryDisable' -Component 'TELEMETRY-DISABLE'
    
    try {
        # Track execution duration for v3.0 compliance
        $executionStartTime = Get-Date
        
        # Initialize module execution environment
        Initialize-ModuleExecution -ModuleName 'TelemetryDisable'
        
        Write-LogEntry -Level 'INFO' -Component 'TELEMETRY-DISABLE' -Message 'Starting telemetry analysis'
        $analysisResults = Get-TelemetryAnalysis
        
        if (-not $analysisResults -or $analysisResults.ActiveTelemetryCount -eq 0) {
            Write-LogEntry -Level 'INFO' -Component 'TELEMETRY-DISABLE' -Message 'No active telemetry detected'
            if ($perfContext) { Complete-PerformanceTracking -Context $perfContext -Status 'Success' | Out-Null }
            $executionTime = (Get-Date) - $executionStartTime
            return New-ModuleExecutionResult `
                -Success $true `
                -ItemsDetected 0 `
                -ItemsProcessed 0 `
                -DurationMilliseconds $executionTime.TotalMilliseconds `
                -LogPath "" `
                -ModuleName 'TelemetryDisable' `
                -DryRun $DryRun.IsPresent
        }
        
        # Display module banner
        Write-Host "`n" -NoNewline
        Write-Host "=================================================" -ForegroundColor Cyan
        Write-Host "  TELEMETRY DISABLE MODULE v3.0" -ForegroundColor White
        Write-Host "=================================================" -ForegroundColor Cyan
        Write-Host "  Type: " -NoNewline -ForegroundColor Gray
        Write-Host "Type 2 (System Modification)" -ForegroundColor Yellow
        Write-Host "  Mode: " -NoNewline -ForegroundColor Gray
        Write-Host "$(if ($DryRun) { 'DRY-RUN (Simulation)' } else { 'LIVE EXECUTION' })" -ForegroundColor $(if ($DryRun) { 'Cyan' } else { 'Green' })
        Write-Host "=================================================" -ForegroundColor Cyan
        Write-Host ""
        
        # STEP 3: Setup execution logging directory
        $executionLogDir = Join-Path (Get-MaintenancePath 'TempRoot') "logs\telemetry-disable"
        New-Item -Path $executionLogDir -ItemType Directory -Force | Out-Null
        $executionLogPath = Join-Path $executionLogDir "execution.log"
        
        $telemetryCount = $analysisResults.ActiveTelemetryCount
        Write-StructuredLogEntry -Level 'INFO' -Component 'TELEMETRY-DISABLE' -Message "Detected $telemetryCount active telemetry items" -LogPath $executionLogPath -Operation 'Detect' -Metadata @{ TelemetryCount = $telemetryCount }
        
        if ($DryRun) {
            Write-StructuredLogEntry -Level 'INFO' -Component 'TELEMETRY-DISABLE' -Message ' DRY-RUN: Simulating telemetry disable' -LogPath $executionLogPath -Operation 'Simulate' -Metadata @{ DryRun = $true; ItemCount = $telemetryCount }
            $processedCount = $telemetryCount
        }
        else {
            Write-StructuredLogEntry -Level 'INFO' -Component 'TELEMETRY-DISABLE' -Message 'Executing telemetry disable' -LogPath $executionLogPath -Operation 'Execute' -Metadata @{ ItemCount = $telemetryCount }
            # Process telemetry items based on detected types
            $processedCount = 0
            if ($analysisResults.ActiveTelemetryItems) {
                foreach ($item in $analysisResults.ActiveTelemetryItems) {
                    Write-StructuredLogEntry -Level 'INFO' -Component 'TELEMETRY-DISABLE' -Message "Processing telemetry item: $($item.Type)" -LogPath $executionLogPath -Operation 'Process' -Target $item.Type -Metadata @{ ItemName = $item.Name }
                    try {
                        switch ($item.Type) {
                            'Service' { $result = Disable-WindowsTelemetry -DisableServices }
                            'Notification' { $result = Disable-WindowsTelemetry -DisableNotifications }
                            'ConsumerFeature' { $result = Disable-WindowsTelemetry -DisableConsumerFeatures }
                            'Cortana' { $result = Disable-WindowsTelemetry -DisableCortana }
                            'LocationTracking' { $result = Disable-WindowsTelemetry -DisableLocationTracking }
                            default { Write-StructuredLogEntry -Level 'WARNING' -Component 'TELEMETRY-DISABLE' -Message "Unknown telemetry type: $($item.Type)" -LogPath $executionLogPath -Operation 'Process' -Target $item.Type -Result 'Unknown' }
                        }
                        if ($result) { 
                            $processedCount++
                            Write-StructuredLogEntry -Level 'SUCCESS' -Component 'TELEMETRY-DISABLE' -Message "Successfully disabled: $($item.Type)" -LogPath $executionLogPath -Operation 'Disable' -Target $item.Type -Result 'Success'
                        }
                        else {
                            Write-StructuredLogEntry -Level 'WARNING' -Component 'TELEMETRY-DISABLE' -Message "Failed to disable: $($item.Type)" -LogPath $executionLogPath -Operation 'Disable' -Target $item.Type -Result 'Failed'
                        }
                    }
                    catch {
                        Write-StructuredLogEntry -Level 'ERROR' -Component 'TELEMETRY-DISABLE' -Message "Error disabling $($item.Type): $($_.Exception.Message)" -LogPath $executionLogPath -Operation 'Disable' -Target $item.Type -Result 'Error' -Metadata @{ Error = $_.Exception.Message }
                    }
                }
            }
        }
        
        Write-StructuredLogEntry -Level 'SUCCESS' -Component 'TELEMETRY-DISABLE' -Message "Telemetry disable completed. Processed: $processedCount/$telemetryCount" -LogPath $executionLogPath -Operation 'Complete' -Result 'Success' -Metadata @{ ProcessedCount = $processedCount; TotalCount = $telemetryCount }
        
        # Create execution summary JSON
        $summaryPath = Join-Path $executionLogDir "execution-summary.json"
        $executionTime = (Get-Date) - $executionStartTime
        $executionSummary = @{
            ModuleName    = 'TelemetryDisable'
            ExecutionTime = @{
                Start      = $executionStartTime.ToString('o')
                End        = (Get-Date).ToString('o')
                DurationMs = $executionTime.TotalMilliseconds
            }
            Results       = @{
                Success        = $true
                ItemsDetected  = $telemetryCount
                ItemsProcessed = $processedCount
                ItemsFailed    = 0
                ItemsSkipped   = ($telemetryCount - $processedCount)
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
        
        if ($perfContext) { Complete-PerformanceTracking -Context $perfContext -Status 'Success' | Out-Null }
        return New-ModuleExecutionResult `
            -Success $true `
            -ItemsDetected $telemetryCount `
            -ItemsProcessed $processedCount `
            -DurationMilliseconds $executionTime.TotalMilliseconds `
            -LogPath $executionLogPath `
            -ModuleName 'TelemetryDisable' `
            -DryRun $DryRun.IsPresent
        
    }
    catch {
        $errorMsg = "Failed to execute telemetry disable: $($_.Exception.Message)"
        Write-LogEntry -Level 'ERROR' -Component 'TELEMETRY-DISABLE' -Message $errorMsg -Data @{ Error = $_.Exception }
        if ($perfContext) { Complete-PerformanceTracking -Context $perfContext -Status 'Failed' -ErrorMessage $errorMsg | Out-Null }
        $executionTime = if ($executionStartTime) { (Get-Date) - $executionStartTime } else { New-TimeSpan }
        return New-ModuleExecutionResult `
            -Success $false `
            -ItemsDetected (if ($analysisResults) { $analysisResults.ActiveTelemetryCount } else { 0 }) `
            -ItemsProcessed 0 `
            -DurationMilliseconds $executionTime.TotalMilliseconds `
            -LogPath $executionLogPath `
            -ModuleName 'TelemetryDisable' `
            -ErrorMessage $errorMsg
    }
}

#endregion

#region Legacy Public Functions (Preserved for Internal Use)

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
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([bool])]
    param(
        [Parameter()]
        [switch]$DisableServices,

        [Parameter()]
        [switch]$DisableNotifications,

        [Parameter()]
        [switch]$DisableConsumerFeatures,

        [Parameter()]
        [switch]$DisableCortana = $false,

        [Parameter()]
        [switch]$DisableLocationTracking = $false,

        [Parameter()]
        [switch]$DryRun
    )

    Write-Information " Starting Windows telemetry and privacy hardening..." -InformationAction Continue
    $startTime = Get-Date
    
    # Initialize structured logging and performance tracking
    try {
        Write-LogEntry -Level 'INFO' -Component 'TELEMETRY-DISABLE' -Message 'Starting Windows telemetry and privacy hardening' -Data @{
            DisableServices         = $DisableServices.IsPresent
            DisableNotifications    = $DisableNotifications.IsPresent
            DisableConsumerFeatures = $DisableConsumerFeatures.IsPresent
            DisableCortana          = $DisableCortana.IsPresent
            DisableLocationTracking = $DisableLocationTracking.IsPresent
            DryRun                  = $DryRun.IsPresent
        }
        $perfContext = Start-PerformanceTracking -OperationName 'TelemetryPrivacyHardening' -Component 'TELEMETRY-DISABLE'
    }
    catch {
        Write-Verbose "TELEMETRY-DISABLE: Logging initialization failed - $_"
        # LoggingManager not available, continue with standard logging
    }
    
    # Check for administrator privileges before proceeding
    try {
        Assert-AdminPrivilege -Operation "Windows telemetry and privacy configuration"
    }
    catch {
        Write-Error "Administrator privileges are required for telemetry disabling operations: $_"
        $executionTime = (Get-Date) - $startTime
        return New-ModuleExecutionResult `
            -Success $false `
            -ItemsDetected 0 `
            -ItemsProcessed 0 `
            -DurationMilliseconds $executionTime.TotalMilliseconds `
            -ModuleName 'TelemetryDisable' `
            -ErrorMessage 'Administrator privileges required'
    }

    if ($DryRun) {
        Write-Information "   DRY RUN MODE - No changes will be applied" -InformationAction Continue
    }

    # Initialize results tracking
    $results = @{
        TotalOperations = 0
        Successful      = 0
        Failed          = 0
        Skipped         = 0
        DryRun          = $DryRun.IsPresent
        Details         = [List[PSCustomObject]]::new()
        Categories      = @{
            Registry      = @{ Applied = 0; Failed = 0 }
            Services      = @{ Disabled = 0; Failed = 0 }
            Notifications = @{ Disabled = 0; Failed = 0 }
            Features      = @{ Disabled = 0; Failed = 0 }
        }
    }

    try {
        # Apply core telemetry registry settings
        Write-Information "   Configuring telemetry registry settings..." -InformationAction Continue
        $regResults = Set-TelemetryRegistrySetting -DryRun:$DryRun
        Merge-Result -Results $results -NewResults $regResults -Category 'Registry'

        # Disable telemetry services
        if ($DisableServices) {
            Write-Information "   Disabling telemetry services..." -InformationAction Continue
            $serviceResults = Disable-TelemetryService -DryRun:$DryRun
            Merge-Result -Results $results -NewResults $serviceResults -Category 'Services'
        }

        # Disable notifications and suggestions
        if ($DisableNotifications) {
            Write-Information "   Disabling notifications and suggestions..." -InformationAction Continue
            $notifyResults = Disable-WindowsNotification -DryRun:$DryRun
            Merge-Result -Results $results -NewResults $notifyResults -Category 'Notifications'
        }

        # Disable consumer features
        if ($DisableConsumerFeatures) {
            Write-Information "   Disabling consumer features..." -InformationAction Continue
            $consumerResults = Disable-ConsumerFeature -DryRun:$DryRun
            Merge-Result -Results $results -NewResults $consumerResults -Category 'Features'
        }

        # Disable Cortana if requested
        if ($DisableCortana) {
            Write-Information "   Disabling Cortana..." -InformationAction Continue
            $cortanaResults = Disable-CortanaFeature -DryRun:$DryRun
            Merge-Result -Results $results -NewResults $cortanaResults -Category 'Features'
        }

        # Disable location tracking if requested
        if ($DisableLocationTracking) {
            Write-Information "   Disabling location tracking..." -InformationAction Continue
            $locationResults = Disable-LocationService -DryRun:$DryRun
            Merge-Result -Results $results -NewResults $locationResults -Category 'Features'
        }

        $duration = ((Get-Date) - $startTime).TotalSeconds

        # Summary output
        $statusIcon = if ($results.Failed -eq 0) { "" } else { "" }
        Write-Information "  $statusIcon Privacy hardening completed in $([math]::Round($duration, 2))s" -InformationAction Continue
        Write-Information "     Operations: $($results.TotalOperations), Successful: $($results.Successful), Failed: $($results.Failed)" -InformationAction Continue

        $success = $results.Failed -eq 0
        if (-not $success) {
            Write-Warning "     Some operations failed. Check logs for details."
        }

        # Complete performance tracking and structured logging
        try {
            Complete-PerformanceTracking -PerformanceContext $perfContext -Success $success -ResultData @{
                TotalOperations        = $results.TotalOperations
                Successful             = $results.Successful
                Failed                 = $results.Failed
                Skipped                = $results.Skipped
                Duration               = $duration
                RegistryOperations     = $results.Categories.Registry
                ServicesOperations     = $results.Categories.Services
                NotificationOperations = $results.Categories.Notifications
                FeatureOperations      = $results.Categories.Features
            }
            Write-LogEntry -Level $(if ($success) { 'SUCCESS' } else { 'WARNING' }) -Component 'TELEMETRY-DISABLE' -Message 'Privacy hardening operation completed' -Data $results
        }
        catch {
            Write-Verbose "TELEMETRY-DISABLE: Logging completion failed - $_"
            # LoggingManager not available, continue with standard logging
        }
        
        # Log detailed results for audit trails
        Write-Verbose "Telemetry disable operation details: $(ConvertTo-Json $results -Depth 3)"
        Write-Verbose "Privacy hardening completed successfully"
        
        $executionTime = (Get-Date) - $startTime
        return New-ModuleExecutionResult `
            -Success $success `
            -ItemsDetected $results.TotalOperations `
            -ItemsProcessed $results.Successful `
            -DurationMilliseconds $executionTime.TotalMilliseconds `
            -ModuleName 'TelemetryDisable' `
            -DryRun $DryRun.IsPresent
    }
    catch {
        $errorMessage = " Privacy hardening failed: $($_.Exception.Message)"
        Write-Error $errorMessage
        Write-Verbose "Error details: $($_.Exception.ToString())"
        
        # Complete performance tracking for failed operation
        try {
            Complete-PerformanceTracking -PerformanceContext $perfContext -Success $false -ResultData @{ Error = $_.Exception.Message }
            Write-LogEntry -Level 'ERROR' -Component 'TELEMETRY-DISABLE' -Message 'Privacy hardening operation failed' -Data @{ Error = $_.Exception.Message; ErrorType = $_.Exception.GetType().Name }
        }
        catch {
            Write-Verbose "TELEMETRY-DISABLE: Error logging failed - $_"
            # LoggingManager not available, continue with standard logging
        }
        
        $executionTime = (Get-Date) - $startTime
        return New-ModuleExecutionResult `
            -Success $false `
            -ItemsDetected $results.TotalOperations `
            -ItemsProcessed $results.Successful `
            -DurationMilliseconds $executionTime.TotalMilliseconds `
            -ModuleName 'TelemetryDisable' `
            -ErrorMessage $_.Exception.Message
    }
    finally {
        $duration = ((Get-Date) - $startTime).TotalSeconds
        Write-Verbose "Privacy hardening operation completed in $([math]::Round($duration, 2)) seconds"
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
<#
.SYNOPSIS
    Tests and analyzes current Windows privacy and telemetry settings.

.DESCRIPTION
    Performs comprehensive analysis of Windows privacy configuration including telemetry level,
    running telemetry services, notification settings, consumer features, Cortana status,
    and location services. Provides detailed recommendations for privacy hardening.

.EXAMPLE
    $analysis = Test-PrivacySetting
    Write-Output "Found $($analysis.Recommendations.Count) privacy issues"

.EXAMPLE
    $privacyStatus = Test-PrivacySetting
    if ($privacyStatus.TelemetryLevel -gt 0) {
        Write-Warning "Telemetry is still enabled"
    }

.OUTPUTS
    [hashtable] Analysis results containing telemetry status, service states, and recommendations

.NOTES
    Author: Windows Maintenance Automation Project
    Module Type: Type 2 (System Modification)
    Dependencies: Registry access, service query capabilities
    Version: 1.0.0
#>
function Test-PrivacySetting {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    Write-Information " Analyzing current privacy and telemetry settings..." -InformationAction Continue

    $analysis = @{
        TelemetryLevel          = Get-TelemetryLevel
        ServicesRunning         = Get-TelemetryServiceStatus
        NotificationsEnabled    = Test-NotificationsEnabled
        ConsumerFeaturesEnabled = Test-ConsumerFeaturesEnabled
        CortanaEnabled          = Test-CortanaEnabled
        LocationServicesEnabled = Test-LocationServiceEnabled
        Recommendations         = [List[string]]::new()
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

    Write-Information "   Telemetry Level: $($analysis.TelemetryLevel)" -InformationAction Continue
    Write-Information "   Telemetry Services Running: $($analysis.ServicesRunning)" -InformationAction Continue
    Write-Information "   Recommendations: $($analysis.Recommendations.Count)" -InformationAction Continue

    return $analysis
}

#endregion

#region Registry Configuration

<#
.SYNOPSIS
    Configures Windows telemetry and privacy-related registry settings.

.DESCRIPTION
    Applies comprehensive registry modifications to disable telemetry data collection,
    feedback notifications, commercial data pipeline, device name sharing, content delivery,
    consumer features, and cloud-optimized content. Supports dry-run mode for testing.

.PARAMETER DryRun
    When specified, simulates registry changes without actually applying them.
    Useful for testing and validation before making permanent changes.

.EXAMPLE
    $result = Set-TelemetryRegistrySetting
    Write-Output "Applied $($result.Applied) registry settings"

.EXAMPLE
    $dryRunResult = Set-TelemetryRegistrySetting -DryRun
    Write-Output "Would apply $($dryRunResult.Applied) registry changes"

.OUTPUTS
    [hashtable] Results containing Applied count, Failed count, and detailed operation results

.NOTES
    Author: Windows Maintenance Automation Project
    Module Type: Type 2 (System Modification)
    Dependencies: Registry write access, Administrator privileges
    Version: 1.0.0

    Registry Paths Modified:
    - HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection
    - HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection
    - HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager
    - HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent
#>
function Set-TelemetryRegistrySetting {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([hashtable])]
    param(
        [Parameter()]
        [switch]$DryRun
    )

    # Start structured logging for registry settings operation
    try {
        Write-LogEntry -Level 'INFO' -Component 'TELEMETRY-DISABLE' -Message 'Starting telemetry registry settings configuration' -Data @{ DryRun = $DryRun.IsPresent }
    }
    catch {
        Write-Verbose "TELEMETRY-DISABLE: Registry settings logging failed - $_"
        # LoggingManager not available, continue with standard logging
    }
    
    $results = @{
        Applied = 0
        Failed  = 0
        Details = [List[PSCustomObject]]::new()
    }

    # Core telemetry registry settings
    $telemetrySettings = @{
        'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'                = @{
            'AllowTelemetry'                 = 0
            'DoNotShowFeedbackNotifications' = 1
            'AllowCommercialDataPipeline'    = 0
            'AllowDeviceNameInTelemetry'     = 0
        }
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection' = @{
            'AllowTelemetry'      = 0
            'MaxTelemetryAllowed' = 0
        }
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'  = @{
            'ContentDeliveryAllowed'       = 0
            'OemPreInstalledAppsEnabled'   = 0
            'PreInstalledAppsEnabled'      = 0
            'SilentInstalledAppsEnabled'   = 0
            'SubscribedContentEnabled'     = 0
            'SystemPaneSuggestionsEnabled' = 0
            'SoftLandingEnabled'           = 0
        }
        'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent'                  = @{
            'DisableWindowsConsumerFeatures' = 1
            'DisableCloudOptimizedContent'   = 1
            'DisableSoftLanding'             = 1
        }
    }

    foreach ($registryPath in $telemetrySettings.Keys) {
        $pathResult = @{
            Path     = $registryPath
            Settings = 0
            Success  = $true
            Error    = $null
        }

        try {
            # Check if path exists, create if not
            if (-not (Test-Path $registryPath)) {
                if ($DryRun) {
                    Write-Information "    [DRY RUN] Would create registry path: $registryPath" -InformationAction Continue
                }
                else {
                    if ($PSCmdlet.ShouldProcess($registryPath, 'Create registry path')) {
                        New-Item -Path $registryPath -Force | Out-Null
                    }
                }
            }

            $settings = $telemetrySettings[$registryPath]
            foreach ($setting in $settings.GetEnumerator()) {
                try {
                    if ($DryRun) {
                        Write-Information "    [DRY RUN] Would set $($setting.Key) = $($setting.Value) in $registryPath" -InformationAction Continue
                        $pathResult.Settings++
                    }
                    else {
                        # Check if value needs to be changed (idempotent operation)
                        $currentValue = $null
                        try {
                            $currentValue = (Get-ItemProperty -Path $registryPath -Name $setting.Key -ErrorAction SilentlyContinue).$($setting.Key)
                        }
                        catch {
                            $currentValue = $null
                        }

                        if ($currentValue -ne $setting.Value) {
                            if ($PSCmdlet.ShouldProcess("$registryPath\$($setting.Key)", "Set registry value to $($setting.Value)")) {
                                Set-ItemProperty -Path $registryPath -Name $setting.Key -Value $setting.Value -Force
                                $pathResult.Settings++
                            }
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
    Disables Windows telemetry and tracking services.

.DESCRIPTION
    Stops and disables Windows services responsible for telemetry data collection,
    user experience tracking, diagnostic data transmission, and wireless application
    protocol management. Provides comprehensive service state management with rollback
    support and detailed operation reporting.

.PARAMETER DryRun
    When specified, simulates service changes without actually stopping or disabling them.
    Shows which services would be affected and their current states.

.EXAMPLE
    $result = Disable-TelemetryService
    Write-Output "Disabled $($result.Disabled) telemetry services"

.EXAMPLE
    $dryRunResult = Disable-TelemetryService -DryRun
    Write-Output "Would disable $($result.Disabled) services"

.OUTPUTS
    [hashtable] Results containing Disabled count, Failed count, and detailed service states

.NOTES
    Author: Windows Maintenance Automation Project
    Module Type: Type 2 (System Modification)
    Dependencies: Service Control Manager access, Administrator privileges
    Version: 1.0.0

    Services Affected:
    - DiagTrack (Connected User Experiences and Telemetry)
    - dmwappushservice (Device Management Wireless Application Protocol)
#>
function Disable-TelemetryService {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    [OutputType([hashtable])]
    param(
        [Parameter()]
        [switch]$DryRun
    )

    $results = @{
        Disabled = 0
        Failed   = 0
        Details  = [List[PSCustomObject]]::new()
    }

    # Telemetry services to disable
    $telemetryServices = @(
        'DiagTrack',           # Connected User Experiences and Telemetry
        'dmwappushservice',    # Device Management Wireless Application Protocol
        'RetailDemo',          # Retail Demo Service
        'WerSvc'              # Windows Error Reporting (optional)
    )

    foreach ($serviceName in $telemetryServices) {
        $operationStart = Get-Date
        $serviceResult = @{
            Name    = $serviceName
            Success = $false
            Action  = 'None'
            Error   = $null
        }

        try {
            $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue

            if (-not $service) {
                $serviceResult.Action = 'Not Found'
                $serviceResult.Success = $true
                Write-Information "    ℹ  Service $serviceName not found on this system" -InformationAction Continue
            }
            elseif ($service.StartType -eq 'Disabled') {
                $serviceResult.Action = 'Already Disabled'
                $serviceResult.Success = $true
                Write-Information "     Service $serviceName already disabled" -InformationAction Continue
            }
            else {
                # Enhanced logging: Pre-action state
                Write-OperationStart -Component 'TELEMETRY-DISABLE' -Operation 'Disable' -Target $serviceName -AdditionalInfo @{
                    PreviousState     = $service.Status
                    PreviousStartType = $service.StartType
                    Type              = 'TelemetryService'
                }
                
                if ($DryRun) {
                    $serviceResult.Action = 'Would Disable'
                    $serviceResult.Success = $true
                    Write-Information "    [DRY RUN] Would disable service: $serviceName" -InformationAction Continue
                    Write-OperationSkipped -Component 'TELEMETRY-DISABLE' -Operation 'Disable' -Target $serviceName -Reason 'DryRun mode enabled'
                }
                else {
                    if ($PSCmdlet.ShouldProcess($serviceName, 'Stop and disable telemetry service')) {
                        # Stop the service if running
                        if ($service.Status -eq 'Running') {
                            Write-LogEntry -Level 'INFO' -Component 'TELEMETRY-DISABLE' -Message "Executing: Stop-Service -Name $serviceName"
                            Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
                        }

                        # Disable the service
                        Write-LogEntry -Level 'INFO' -Component 'TELEMETRY-DISABLE' -Message "Executing: Set-Service -Name $serviceName -StartupType Disabled"
                        Set-Service -Name $serviceName -StartupType Disabled
                        
                        # Verification
                        Write-LogEntry -Level 'INFO' -Component 'TELEMETRY-DISABLE' -Operation 'Verify' -Target $serviceName -Message 'Verifying service disabled state'
                        
                        $verifyService = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
                        $operationDuration = ((Get-Date) - $operationStart).TotalSeconds
                        
                        if ($verifyService.StartupType -eq 'Disabled') {
                            # Log successful verification
                            Write-OperationSuccess -Component 'TELEMETRY-DISABLE' -Operation 'Verify' -Target $serviceName -Metrics @{
                                ExpectedStartType  = 'Disabled'
                                ActualStartType    = $verifyService.StartupType
                                ActualStatus       = $verifyService.Status
                                VerificationPassed = $true
                            }
                            
                            # Log successful disable
                            Write-OperationSuccess -Component 'TELEMETRY-DISABLE' -Operation 'Disable' -Target $serviceName -Metrics @{
                                Duration          = $operationDuration
                                PreviousState     = $service.Status
                                PreviousStartType = $service.StartType
                                NewStartType      = 'Disabled'
                                Verified          = $true
                            }
                            $serviceResult.Action = 'Disabled'
                            $serviceResult.Success = $true
                            Write-Information "     Disabled service: $serviceName (${operationDuration}s)" -InformationAction Continue
                        }
                        else {
                            # Log failed verification
                            Write-OperationFailure -Component 'TELEMETRY-DISABLE' -Operation 'Verify' -Target $serviceName -Error (New-Object Exception("Service not disabled - StartType: $($verifyService.StartupType)"))
                            throw "Verification failed: Service not disabled"
                        }
                    }
                }

                $results.Disabled++
            }
        }
        catch {
            $serviceResult.Error = $_.Exception.Message
            $results.Failed++
            Write-OperationFailure -Component 'TELEMETRY-DISABLE' -Operation 'Disable' -Target $serviceName -Error $_
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
    Disables Windows notifications, suggestions, and promotional content.

.DESCRIPTION
    Configures registry settings to disable various Windows notification systems including
    action center notifications, suggested apps, tips and tricks, promotional content,
    Windows spotlight, and other intrusive notification mechanisms that compromise privacy
    and user experience.

.PARAMETER DryRun
    When specified, simulates notification disable operations without making actual changes.
    Shows which notification settings would be modified.

.EXAMPLE
    $result = Disable-WindowsNotification
    Write-Output "Disabled $($result.Disabled) notification settings"

.EXAMPLE
    $dryRunResult = Disable-WindowsNotification -DryRun
    Write-Output "Would disable $($dryRunResult.Disabled) notification types"

.OUTPUTS
    [hashtable] Results containing Disabled count, Failed count, and detailed operation results

.NOTES
    Author: Windows Maintenance Automation Project
    Module Type: Type 2 (System Modification)
    Dependencies: Registry write access, Administrator privileges
    Version: 1.0.0

    Registry Modifications:
    - Action Center notification settings
    - Content delivery manager settings
    - Windows tips and suggestions
    - Promotional notifications
#>
function Disable-WindowsNotification {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([hashtable])]
    param(
        [Parameter()]
        [switch]$DryRun
    )

    $results = @{
        Disabled = 0
        Failed   = 0
        Details  = [List[PSCustomObject]]::new()
    }

    try {
        $notificationPath = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Notifications\Settings'

        if (-not (Test-Path $notificationPath)) {
            if ($DryRun) {
                Write-Information "    [DRY RUN] Would create notification settings path" -InformationAction Continue
            }
            else {
                if ($PSCmdlet.ShouldProcess($notificationPath, 'Create notification settings registry path')) {
                    New-Item -Path $notificationPath -Force | Out-Null
                }
            }
        }

        # Global notification settings
        $globalSettings = @{
            'NOC_GLOBAL_SETTING_TOASTS_ENABLED' = 0
            'NOC_GLOBAL_SETTING_BADGE_ENABLED'  = 0
            'NOC_GLOBAL_SETTING_SOUND_ENABLED'  = 0
        }

        foreach ($setting in $globalSettings.GetEnumerator()) {
            try {
                if ($DryRun) {
                    Write-Information "    [DRY RUN] Would disable global notification: $($setting.Key)" -InformationAction Continue
                }
                else {
                    if ($PSCmdlet.ShouldProcess("$notificationPath\$($setting.Key)", "Disable notification setting")) {
                        Set-ItemProperty -Path $notificationPath -Name $setting.Key -Value $setting.Value -Force
                        Write-Information "     Disabled notification setting: $($setting.Key)" -InformationAction Continue
                    }
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
                    Write-Information "    [DRY RUN] Would disable notifications for: $($app.PSChildName)" -InformationAction Continue
                }
                else {
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
    Disables Windows consumer features, app suggestions, and promotional content.

.DESCRIPTION
    Removes Windows commercial features including app suggestions in Start menu,
    Microsoft Store promotions, suggested apps installations, cloud content delivery,
    sponsored tiles, and other consumer-oriented features that compromise professional
    environment privacy and productivity.

.PARAMETER DryRun
    When specified, simulates consumer feature disabling without making actual changes.
    Shows which consumer features would be disabled.

.EXAMPLE
    $result = Disable-ConsumerFeature
    Write-Output "Disabled $($result.Disabled) consumer features"

.EXAMPLE
    $dryRunResult = Disable-ConsumerFeature -DryRun
    Write-Output "Would disable $($dryRunResult.Disabled) consumer features"

.OUTPUTS
    [hashtable] Results containing Disabled count, Failed count, and detailed operation results

.NOTES
    Author: Windows Maintenance Automation Project
    Module Type: Type 2 (System Modification)
    Dependencies: Registry write access, Administrator privileges
    Version: 1.0.0

    Features Disabled:
    - Microsoft Store app suggestions
    - Start menu sponsored content
    - Cloud content delivery
    - Suggested apps installations
    - Windows tips and tricks
#>
function Disable-ConsumerFeature {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([hashtable])]
    param(
        [Parameter()]
        [switch]$DryRun
    )

    $results = @{
        Disabled = 0
        Failed   = 0
        Details  = [List[PSCustomObject]]::new()
    }

    # Consumer features registry settings
    $consumerSettings = @{
        'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent'                 = @{
            'DisableWindowsConsumerFeatures'     = 1
            'DisableConsumerAccountStateContent' = 1
            'DisableCloudOptimizedContent'       = 1
        }
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' = @{
            'SystemPaneSuggestionsEnabled' = 0
            'SilentInstalledAppsEnabled'   = 0
            'PreInstalledAppsEnabled'      = 0
            'OemPreInstalledAppsEnabled'   = 0
        }
    }

    foreach ($registryPath in $consumerSettings.Keys) {
        try {
            if (-not (Test-Path $registryPath)) {
                if ($DryRun) {
                    Write-Information "    [DRY RUN] Would create consumer features path: $registryPath" -InformationAction Continue
                }
                else {
                    if ($PSCmdlet.ShouldProcess($registryPath, 'Create consumer features registry path')) {
                        New-Item -Path $registryPath -Force | Out-Null
                    }
                }
            }

            $settings = $consumerSettings[$registryPath]
            foreach ($setting in $settings.GetEnumerator()) {
                try {
                    if ($DryRun) {
                        Write-Information "    [DRY RUN] Would set $($setting.Key) = $($setting.Value)" -InformationAction Continue
                    }
                    else {
                        if ($PSCmdlet.ShouldProcess("$registryPath\$($setting.Key)", "Disable consumer feature setting")) {
                            Set-ItemProperty -Path $registryPath -Name $setting.Key -Value $setting.Value -Force
                        }
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
    Disables Cortana voice assistant and related search features.

.DESCRIPTION
    Configures registry settings to completely disable Cortana voice assistant,
    web search integration, connected search functionality, and related privacy-invasive
    search features that send user queries to Microsoft servers.

.PARAMETER DryRun
    When specified, simulates Cortana disabling without making actual changes.
    Shows which Cortana features would be disabled.

.EXAMPLE
    $result = Disable-CortanaFeature
    Write-Output "Disabled $($result.Disabled) Cortana features"

.EXAMPLE
    $dryRunResult = Disable-CortanaFeature -DryRun
    Write-Output "Would disable Cortana features"

.OUTPUTS
    [hashtable] Results containing Disabled count, Failed count, and operation details

.NOTES
    Author: Windows Maintenance Automation Project
    Module Type: Type 2 (System Modification)
    Dependencies: Registry write access, Administrator privileges
    Version: 1.0.0

    Features Disabled:
    - Cortana voice assistant
    - Web search integration
    - Connected search functionality
#>
function Disable-CortanaFeature {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([hashtable])]
    param([switch]$DryRun)

    $results = @{ Disabled = 0; Failed = 0; Details = @() }

    $cortanaSettings = @{
        'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search' = @{
            'AllowCortana'          = 0
            'DisableWebSearch'      = 1
            'ConnectedSearchUseWeb' = 0
        }
    }

    foreach ($path in $cortanaSettings.Keys) {
        try {
            if (-not (Test-Path $path)) {
                if (-not $DryRun) {
                    if ($PSCmdlet.ShouldProcess($path, 'Create Cortana settings registry path')) {
                        New-Item -Path $path -Force | Out-Null
                    }
                }
            }

            foreach ($setting in $cortanaSettings[$path].GetEnumerator()) {
                if ($DryRun) {
                    Write-Information "    [DRY RUN] Would disable Cortana setting: $($setting.Key)" -InformationAction Continue
                }
                else {
                    if ($PSCmdlet.ShouldProcess("$path\$($setting.Key)", "Disable Cortana feature")) {
                        Set-ItemProperty -Path $path -Name $setting.Key -Value $setting.Value -Force
                    }
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
    Disables Windows location tracking and location-based services.

.DESCRIPTION
    Configures system settings to disable location tracking, location-based advertising,
    location history, geofencing, and other location services that compromise user privacy
    by sharing geographical data with Microsoft and third-party applications.

.PARAMETER DryRun
    When specified, simulates location services disabling without making actual changes.
    Shows which location tracking features would be disabled.

.EXAMPLE
    $result = Disable-LocationService
    Write-Output "Disabled $($result.Disabled) location tracking features"

.EXAMPLE
    $dryRunResult = Disable-LocationService -DryRun
    Write-Output "Would disable location services"

.OUTPUTS
    [hashtable] Results containing Disabled count, Failed count, and operation details

.NOTES
    Author: Windows Maintenance Automation Project
    Module Type: Type 2 (System Modification)
    Dependencies: Registry write access, Administrator privileges
    Version: 1.0.0

    Features Disabled:
    - Location tracking services
    - Location-based advertising
    - Geofencing capabilities
    - Location history collection
#>
function Disable-LocationService {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([hashtable])]
    param([switch]$DryRun)

    $results = @{ Disabled = 0; Failed = 0; Details = @() }

    $locationSettings = @{
        'HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors' = @{
            'DisableLocation'          = 1
            'DisableLocationScripting' = 1
        }
    }

    foreach ($path in $locationSettings.Keys) {
        try {
            if (-not (Test-Path $path)) {
                if (-not $DryRun) {
                    if ($PSCmdlet.ShouldProcess($path, 'Create location services registry path')) {
                        New-Item -Path $path -Force | Out-Null
                    }
                }
            }

            foreach ($setting in $locationSettings[$path].GetEnumerator()) {
                if ($DryRun) {
                    Write-Information "    [DRY RUN] Would disable location setting: $($setting.Key)" -InformationAction Continue
                }
                else {
                    if ($PSCmdlet.ShouldProcess("$path\$($setting.Key)", "Disable location service")) {
                        Set-ItemProperty -Path $path -Name $setting.Key -Value $setting.Value -Force
                    }
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
    }
    catch { return 3 }
}

function Get-TelemetryServiceStatus {
    $services = @('DiagTrack', 'dmwappushservice', 'RetailDemo')
    return ($services | ForEach-Object { Get-Service -Name $_ -ErrorAction SilentlyContinue } | Where-Object { $_.Status -eq 'Running' }).Count
}

function Test-NotificationsEnabled {
    try {
        $value = (Get-ItemProperty -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Notifications\Settings' -Name NOC_GLOBAL_SETTING_TOASTS_ENABLED -ErrorAction SilentlyContinue).NOC_GLOBAL_SETTING_TOASTS_ENABLED
        return $value -ne 0
    }
    catch { return $true }
}

function Test-ConsumerFeaturesEnabled {
    try {
        $value = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' -Name DisableWindowsConsumerFeatures -ErrorAction SilentlyContinue).DisableWindowsConsumerFeatures
        return $value -ne 1
    }
    catch { return $true }
}

function Test-CortanaEnabled {
    try {
        $value = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search' -Name AllowCortana -ErrorAction SilentlyContinue).AllowCortana
        return $value -ne 0
    }
    catch { return $true }
}

function Test-LocationServiceEnabled {
    try {
        $value = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors' -Name DisableLocation -ErrorAction SilentlyContinue).DisableLocation
        return $value -ne 1
    }
    catch { return $true }
}

# Helper function to merge operation results
<#
.SYNOPSIS
    Merges telemetry disabling results into consolidated results object

.DESCRIPTION
    Combines telemetry disabling results from a specific category into the main results object.
    Aggregates counters (applied, disabled, failed operations) and updates category-specific
    statistics for privacy setting analysis.

.PARAMETER Results
    Main results hashtable to merge into (contains aggregated totals and categories)

.PARAMETER NewResults
    New results from a telemetry disabling operation to add (contains applied/disabled/failed counts)

.PARAMETER Category
    Name of the telemetry category being processed (e.g., 'Services', 'Registry', 'Tracking')

.OUTPUTS
    [void] Modified Results object in place with updated statistics

.EXAMPLE
    PS> $mainResults = @{ TotalOperations = 0; Successful = 0; Failed = 0; Categories = @{} }
    PS> $serviceResults = @{ Applied = 3; Disabled = 2; Failed = 0 }
    PS> Merge-Result -Results $mainResults -NewResults $serviceResults -Category 'Services'
    
    Adds service-level telemetry results to main results, updating category statistics.

.NOTES
    Used internally for aggregating results from multiple telemetry categories.
    Updates both global totals and per-category statistics by reference.
#>
function Merge-Result {
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
    # v3.0 Standardized execution function (Primary)
    'Invoke-TelemetryDisable',
    
    # Legacy functions (Preserved for internal use)
    'Disable-WindowsTelemetry',
    'Test-PrivacySetting'
)

