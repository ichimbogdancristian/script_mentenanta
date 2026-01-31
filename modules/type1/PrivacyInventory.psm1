<#
.MODULEINFO
Type = "Type1"
Category = "Privacy"
MenuText = "Audit Privacy & Telemetry Settings"
Description = "Audits Windows telemetry, diagnostic data collection, and privacy settings"
DataFile = "privacy-inventory.json"
ScanInterval = 3600
DependsOn = @("Infrastructure")
#>

<#
.SYNOPSIS
    Privacy Inventory Module v3.0 - Type 1 (Read-Only)

.DESCRIPTION
    Comprehensive privacy and telemetry audit scanner that collects:
    - Telemetry and diagnostic data settings
    - Privacy-related services status
    - Scheduled tasks that collect data
    - Registry keys controlling privacy
    - Windows features affecting privacy

.NOTES
    Author: Windows Maintenance Automation Project
    Version: 3.0.0
    Module Type: Type1 (Read-Only)
    Requires: PowerShell 7.0+
    Dependencies: Infrastructure.psm1
#>

#Requires -Version 7.0

<#
.SYNOPSIS
    Gets comprehensive privacy and telemetry inventory.

.DESCRIPTION
    Audits Windows privacy settings including telemetry levels, diagnostic data,
    privacy-related services, scheduled tasks, and registry configuration.

.PARAMETER UseCache
    Use cached data if available and not expired (default: true).

.PARAMETER ForceRefresh
    Force a fresh scan even if cached data exists.

.OUTPUTS
    PSCustomObject containing complete privacy inventory.

.EXAMPLE
    Get-PrivacyInventory

.EXAMPLE
    Get-PrivacyInventory -ForceRefresh
#>
function Get-PrivacyInventory {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $false)]
        [switch]$ForceRefresh
    )

    $perf = Start-PerformanceTracking -OperationName 'PrivacyInventoryScan' -Component 'Privacy'

    try {
        Write-DetailedLog -Level 'INFO' -Component 'Privacy' -Message 'Starting privacy and telemetry inventory scan'

        # Check for cached data (unless ForceRefresh specified)
        if (-not $ForceRefresh) {
            Write-DetailedLog -Level 'INFO' -Component 'Privacy' -Message 'Checking for cached privacy inventory'

            $cachedData = Import-InventoryFile -Category 'Privacy'

            if ($cachedData -and $cachedData.metadata -and $cachedData.metadata.scanDate) {
                $scanDate = [datetime]::Parse($cachedData.metadata.scanDate)
                $age = (Get-Date) - $scanDate
                $cacheExpiration = Get-ConfigValue -Path 'inventory.cacheExpirationMinutes' -Default 60

                if ($age.TotalMinutes -lt $cacheExpiration) {
                    Write-DetailedLog -Level 'INFO' -Component 'Privacy' -Message "Using cached data (age: $([math]::Round($age.TotalMinutes, 1)) minutes)"
                    Write-Information "ℹ️  Using cached privacy data (scanned $([math]::Round($age.TotalMinutes, 1)) minutes ago)" -InformationAction Continue
                    Complete-PerformanceTracking -PerformanceContext $perf -Success $true
                    return $cachedData
                }
            }
        }

        Write-Information "[PRIVACY] Scanning privacy and telemetry settings..." -InformationAction Continue

        # Initialize inventory structure
        $inventory = @{
            metadata          = @{
                scanDate      = (Get-Date).ToString('o')
                computerName  = $env:COMPUTERNAME
                scanDuration  = 0
                moduleVersion = '3.0.0'
            }

            telemetrySettings = @{
                diagnosticDataLevel = $null
                tailoredExperiences = $null
                advertisingId       = $null
                activityHistory     = $null
            }

            services          = @()
            scheduledTasks    = @()
            registryKeys      = @()

            statistics        = @{
                totalServicesRunning = 0
                totalTasksEnabled    = 0
                privacyIssuesFound   = 0
                recommendedActions   = 0
            }

            recommendations   = @()
        }

        # Step 1: Check telemetry settings
        Write-DetailedLog -Level 'INFO' -Component 'Privacy' -Message 'Auditing telemetry settings'
        Write-Information "  >> Checking telemetry settings..." -InformationAction Continue
        $inventory.telemetrySettings = Get-TelemetryConfiguration

        # Step 2: Audit privacy-related services
        Write-DetailedLog -Level 'INFO' -Component 'Privacy' -Message 'Auditing privacy-related services'
        Write-Information "  🔧 Auditing services..." -InformationAction Continue
        $inventory.services = Get-PrivacyRelatedService
        $inventory.statistics.totalServicesRunning = ($inventory.services | Where-Object { $_.Status -eq 'Running' }).Count

        # Step 3: Audit scheduled tasks
        Write-DetailedLog -Level 'INFO' -Component 'Privacy' -Message 'Auditing scheduled tasks'
        Write-Information "  📅 Auditing scheduled tasks..." -InformationAction Continue
        $inventory.scheduledTasks = Get-PrivacyRelatedTask
        $inventory.statistics.totalTasksEnabled = ($inventory.scheduledTasks | Where-Object { $_.State -eq 'Ready' -or $_.State -eq 'Running' }).Count

        # Step 4: Audit registry keys
        Write-DetailedLog -Level 'INFO' -Component 'Privacy' -Message 'Auditing registry keys'
        Write-Information "  🔑 Auditing registry keys..." -InformationAction Continue
        $inventory.registryKeys = Get-PrivacyRegistryKey

        # Step 5: Generate recommendations
        Write-DetailedLog -Level 'INFO' -Component 'Privacy' -Message 'Generating privacy recommendations'
        $inventory.recommendations = Get-PrivacyRecommendation -Inventory $inventory
        $inventory.statistics.recommendedActions = $inventory.recommendations.Count

        # Calculate privacy issues
        $inventory.statistics.privacyIssuesFound = 0

        if ($inventory.telemetrySettings.diagnosticDataLevel -ne 'Security' -and
            $inventory.telemetrySettings.diagnosticDataLevel -ne 'Basic') {
            $inventory.statistics.privacyIssuesFound++
        }

        $inventory.statistics.privacyIssuesFound += $inventory.statistics.totalServicesRunning
        $inventory.statistics.privacyIssuesFound += $inventory.statistics.totalTasksEnabled

        # Update scan duration
        $inventory.metadata.scanDuration = $perf.StartTime ? ((Get-Date) - $perf.StartTime).TotalSeconds : 0

        # Save inventory
        Write-DetailedLog -Level 'INFO' -Component 'Privacy' -Message 'Saving privacy inventory'
        Save-InventoryFile -Category 'Privacy' -Data $inventory

        # Display summary
        Write-Information "`n  Privacy Inventory Summary:" -InformationAction Continue
        Write-Information "    Diagnostic Data Level: $($inventory.telemetrySettings.diagnosticDataLevel)" -InformationAction Continue
        Write-Information "    Privacy Services Running: $($inventory.statistics.totalServicesRunning)" -InformationAction Continue
        Write-Information "    Data Collection Tasks Enabled: $($inventory.statistics.totalTasksEnabled)" -InformationAction Continue
        Write-Information "    Privacy Issues Found: $($inventory.statistics.privacyIssuesFound)" -InformationAction Continue
        Write-Information "    Recommended Actions: $($inventory.statistics.recommendedActions)" -InformationAction Continue
        Write-Information "" -InformationAction Continue

        Write-DetailedLog -Level 'SUCCESS' -Component 'Privacy' -Message "Privacy inventory scan completed: $($inventory.statistics.privacyIssuesFound) issues found"

        Complete-PerformanceTracking -PerformanceContext $perf -Success $true -ResultData @{
            PrivacyIssues      = $inventory.statistics.privacyIssuesFound
            RecommendedActions = $inventory.statistics.recommendedActions
        }

        return $inventory
    }
    catch {
        Write-DetailedLog -Level 'ERROR' -Component 'Privacy' -Message "Privacy inventory scan failed: $_" -Exception $_
        Write-Information "`n[ERROR] Privacy inventory scan failed: $_" -InformationAction Continue
        Complete-PerformanceTracking -PerformanceContext $perf -Success $false
        return $null
    }
}

<#
.SYNOPSIS
    Gets Windows telemetry configuration.

.DESCRIPTION
    Reads telemetry and diagnostic data settings from registry.

.OUTPUTS
    Hashtable with telemetry configuration.
#>
function Get-TelemetryConfiguration {
    [CmdletBinding()]
    [OutputType([hashtable])]
param(

    $config = @{
        diagnosticDataLevel = 'Unknown'
        tailoredExperiences = $null
        advertisingId       = $null
        activityHistory     = $null
    }

    try {
        # Diagnostic data level
        $telemetryPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'
        if (Test-Path $telemetryPath) {
            $allowTelemetry = (Get-ItemProperty -Path $telemetryPath -Name 'AllowTelemetry' -ErrorAction SilentlyContinue).AllowTelemetry

            $config.diagnosticDataLevel = switch ($allowTelemetry) {
                0 { 'Security' }
                1 { 'Basic' }
                2 { 'Enhanced' }
                3 { 'Full' }
                default { 'Unknown' }
            }
        }
        else {
            $config.diagnosticDataLevel = 'Full' # Default Windows setting
        }

        # Tailored experiences
        $contentPath = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
        if (Test-Path $contentPath) {
            $config.tailoredExperiences = (Get-ItemProperty -Path $contentPath -Name 'SubscribedContent-338393Enabled' -ErrorAction SilentlyContinue).'SubscribedContent-338393Enabled' -eq 0
        }

        # Advertising ID
        $advertisingPath = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo'
        if (Test-Path $advertisingPath) {
            $config.advertisingId = (Get-ItemProperty -Path $advertisingPath -Name 'Enabled' -ErrorAction SilentlyContinue).Enabled -eq 0
        }

        # Activity history
        $activityPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'
        if (Test-Path $activityPath) {
            $config.activityHistory = (Get-ItemProperty -Path $activityPath -Name 'EnableActivityFeed' -ErrorAction SilentlyContinue).EnableActivityFeed -eq 0
        }
    }
    catch {
        Write-Verbose "Error reading telemetry configuration: $_"
    }

    return $config
}

<#
.SYNOPSIS
    Gets privacy-related Windows services.

.DESCRIPTION
    Audits services that collect diagnostic and telemetry data.

.OUTPUTS
    Array of service information.
#>
function Get-PrivacyRelatedService {
    [CmdletBinding()]
    [OutputType([array])]
    param()

    $privacyServices = @(
        'DiagTrack',                      # Connected User Experiences and Telemetry
        'dmwappushservice',               # Device Management Wireless Application Protocol
        'WerSvc',                         # Windows Error Reporting
        'OneSyncSvc',                     # Sync settings and data
        'PcaSvc',                         # Program Compatibility Assistant
        'WMPNetworkSvc'                   # Windows Media Player Network Sharing
    )

    $services = @()

    foreach ($serviceName in $privacyServices) {
        try {
            $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue

            if ($service) {
                $services += @{
                    Name        = $service.Name
                    DisplayName = $service.DisplayName
                    Status      = $service.Status.ToString()
                    StartType   = $service.StartType.ToString()
                    Description = 'Privacy-related telemetry service'
                }
            }
        }
        catch {
            Write-Verbose "Service not found or error: $serviceName - $_"
        }
    }

    return $services
}

<#
.SYNOPSIS
    Gets privacy-related scheduled tasks.

.DESCRIPTION
    Audits scheduled tasks that collect diagnostic data.

.OUTPUTS
    Array of task information.
#>
function Get-PrivacyRelatedTask {
    [CmdletBinding()]
    [OutputType([array])]
    param()

    $taskPaths = @(
        '\Microsoft\Windows\Application Experience\*',
        '\Microsoft\Windows\Customer Experience Improvement Program\*',
        '\Microsoft\Windows\Feedback\*',
        '\Microsoft\Windows\CloudExperienceHost\*'
    )

    $tasks = @()

    foreach ($taskPath in $taskPaths) {
        try {
            $scheduledTasks = Get-ScheduledTask -TaskPath $taskPath -ErrorAction SilentlyContinue

            foreach ($task in $scheduledTasks) {
                $tasks += @{
                    Name        = $task.TaskName
                    Path        = $task.TaskPath
                    State       = $task.State.ToString()
                    Description = $task.Description
                }
            }
        }
        catch {
            Write-Verbose "Error getting tasks from path $taskPath : $_"
        }
    }

    return $tasks
}

<#
.SYNOPSIS
    Gets privacy-related registry keys.

.DESCRIPTION
    Audits important registry keys controlling privacy settings.

.OUTPUTS
    Array of registry key information.
#>
function Get-PrivacyRegistryKey {
    [CmdletBinding()]
    [OutputType([array])]
    param()

    $registryKeys = @(
        @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'; Name = 'AllowTelemetry'; Expected = 0 },
        @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection'; Name = 'AllowTelemetry'; Expected = 0 },
        @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo'; Name = 'DisabledByGroupPolicy'; Expected = 1 },
        @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat'; Name = 'AITEnable'; Expected = 0 },
        @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer'; Name = 'NoRecentDocsHistory'; Expected = 1 }
    )

    $keys = @()

    foreach ($regKey in $registryKeys) {
        try {
            $value = $null
            $compliant = $false

            if (Test-Path $regKey.Path) {
                $value = (Get-ItemProperty -Path $regKey.Path -Name $regKey.Name -ErrorAction SilentlyContinue).($regKey.Name)
                $compliant = ($value -eq $regKey.Expected)
            }

            $keys += @{
                Path      = $regKey.Path
                Name      = $regKey.Name
                Value     = $value
                Expected  = $regKey.Expected
                Compliant = $compliant
            }
        }
        catch {
            Write-Verbose "Error reading registry key $($regKey.Path)\$($regKey.Name) : $_"
        }
    }

    return $keys
}

<#
.SYNOPSIS
    Generates privacy recommendations.

.DESCRIPTION
    Analyzes inventory and provides actionable privacy recommendations.

.PARAMETER Inventory
    Privacy inventory data.

.OUTPUTS
    Array of recommendations.
#>
function Get-PrivacyRecommendation {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Inventory
    )

    $recommendations = @()

    # Telemetry level
    if ($Inventory.telemetrySettings.diagnosticDataLevel -notin @('Security', 'Basic')) {
        $recommendations += @{
            Priority = 'High'
            Category = 'Telemetry'
            Issue    = "Diagnostic data level is set to '$($Inventory.telemetrySettings.diagnosticDataLevel)'"
            Action   = 'Set diagnostic data level to Basic or Security'
            Impact   = 'Reduces data collection by Microsoft'
        }
    }

    # Running services
    $runningServices = $Inventory.services | Where-Object { $_.Status -eq 'Running' }
    if ($runningServices.Count -gt 0) {
        $recommendations += @{
            Priority = 'Medium'
            Category = 'Services'
            Issue    = "$($runningServices.Count) privacy-related services are running"
            Action   = 'Disable telemetry and diagnostic services'
            Impact   = 'Prevents background data collection'
        }
    }

    # Enabled tasks
    $enabledTasks = $Inventory.scheduledTasks | Where-Object { $_.State -in @('Ready', 'Running') }
    if ($enabledTasks.Count -gt 0) {
        $recommendations += @{
            Priority = 'Medium'
            Category = 'ScheduledTasks'
            Issue    = "$($enabledTasks.Count) data collection tasks are enabled"
            Action   = 'Disable telemetry scheduled tasks'
            Impact   = 'Prevents scheduled data collection'
        }
    }

    # Non-compliant registry keys
    $nonCompliant = $Inventory.registryKeys | Where-Object { -not $_.Compliant }
    if ($nonCompliant.Count -gt 0) {
        $recommendations += @{
            Priority = 'Low'
            Category = 'Registry'
            Issue    = "$($nonCompliant.Count) registry keys not configured for privacy"
            Action   = 'Update registry keys to privacy-focused values'
            Impact   = 'Enhances overall privacy configuration'
        }
    }

    return $recommendations
}

# Export public functions
Export-ModuleMember -Function @(
    'Get-PrivacyInventory'
)



