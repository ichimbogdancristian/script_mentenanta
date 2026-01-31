#Requires -Version 7.0

<#
.SYNOPSIS
    Windows Updates Audit Module - Type 1 (Detection/Analysis)

.DESCRIPTION
    Audits Windows Update status, pending updates, update history, and system update configuration.
    Provides comprehensive analysis of update health and security posture.
    Part of the v3.0 architecture where Type1 modules provide detection/analysis capabilities.

.NOTES
    Module Type: Type 1 (Detection/Analysis)
    Dependencies: CoreInfrastructure.psm1, CommonUtilities.psm1, DependencyManager.psm1
    Architecture: v3.0 - Self-contained with fallback capabilities
    Author: Windows Maintenance Automation Project
    Version: 3.0.0
#>

using namespace System.Collections.Generic

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
    Performs comprehensive Windows Update audit

.DESCRIPTION
    Analyzes Windows Update status, pending updates, update configuration, and system update health.
    Provides detailed reporting on security update compliance and update management.

.PARAMETER IncludePending
    Audit pending and available updates

.PARAMETER IncludeHistory
    Include recent update installation history

.PARAMETER IncludeConfiguration
    Audit Windows Update service configuration

.PARAMETER IncludeSecurityAnalysis
    Perform security-focused update analysis

.PARAMETER UseCache
    Use cached results if available

.EXAMPLE
    $audit = Get-WindowsUpdatesAudit

.EXAMPLE
    $audit = Get-WindowsUpdatesAudit -IncludePending -IncludeHistory
#>
function Get-WindowsUpdatesAnalysis {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [switch]$IncludePending,

        [Parameter()]
        [switch]$IncludeHistory,

        [Parameter()]
        [switch]$IncludeConfiguration,

        [Parameter()]
        [switch]$IncludeSecurityAnalysis,

        [Parameter()]
        [switch]$UseCache
    )

    Write-Information " Starting Windows Updates audit..." -InformationAction Continue

    # Start performance tracking
    $perfContext = $null
    try {
        $perfContext = Start-PerformanceTracking -OperationName 'WindowsUpdatesAudit' -Component 'WINDOWS-UPDATES-AUDIT'
        Write-LogEntry -Level 'INFO' -Component 'WINDOWS-UPDATES-AUDIT' -Message 'Starting Windows updates audit' -Data @{
            IncludePending          = $IncludePending
            IncludeHistory          = $IncludeHistory
            IncludeConfiguration    = $IncludeConfiguration
            IncludeSecurityAnalysis = $IncludeSecurityAnalysis
        }
    }
    catch {
        # LoggingManager not available, continue with standard output
        Write-Information "Windows updates audit started" -InformationAction Continue
    }

    try {
        # Check cache first if requested
        if ($UseCache) {
            $cacheFile = Get-SessionPath -Category 'data' -FileName 'windows-updates-audit.json'
            if ($cacheFile -and (Test-Path $cacheFile)) {
                $cacheAge = (Get-Date) - (Get-Item $cacheFile).LastWriteTime
                if ($cacheAge.TotalMinutes -le 30) {
                    Write-Information "Using cached Windows updates audit data" -InformationAction Continue
                    return Get-Content $cacheFile | ConvertFrom-Json
                }
            }
        }

        # Default to include all categories if none specified
        if (-not $IncludePending -and -not $IncludeHistory -and -not $IncludeConfiguration -and -not $IncludeSecurityAnalysis) {
            $IncludePending = $IncludeHistory = $IncludeConfiguration = $IncludeSecurityAnalysis = $true
        }

        # Initialize audit results
        $auditResults = @{
            AuditTimestamp   = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            UpdateStatus     = Get-WindowsUpdateStatus
            SecurityFindings = @()
            UpdateIssues     = @()
            SecurityScore    = 0
            Recommendations  = @()
        }

        # Audit different categories
        if ($IncludePending) {
            Write-Information "   Auditing pending updates..." -InformationAction Continue
            $auditResults.PendingAudit = Get-PendingUpdatesAudit
            $auditResults.UpdateIssues += $auditResults.PendingAudit.Issues
        }

        if ($IncludeHistory) {
            Write-Information "   Auditing update history..." -InformationAction Continue
            $auditResults.HistoryAudit = Get-UpdateHistoryAudit
            $auditResults.UpdateIssues += $auditResults.HistoryAudit.Issues
        }

        if ($IncludeConfiguration) {
            Write-Information "   Auditing update configuration..." -InformationAction Continue
            $auditResults.ConfigurationAudit = Get-UpdateConfigurationAudit
            $auditResults.UpdateIssues += $auditResults.ConfigurationAudit.Issues
        }

        if ($IncludeSecurityAnalysis) {
            Write-Information "   Performing security analysis..." -InformationAction Continue
            $auditResults.SecurityAudit = Get-UpdateSecurityAudit
            $auditResults.SecurityFindings += $auditResults.SecurityAudit.Findings
        }

        # Calculate update health score and generate recommendations
        $auditResults.UpdateScore = Get-UpdateHealthScore -AuditResults $auditResults
        $auditResults.Recommendations = New-UpdateRecommendations -AuditResults $auditResults

        Write-Information " Windows Updates audit completed. Health Score: $($auditResults.UpdateScore.Overall)/100" -InformationAction Continue

        # FIX #5: Save results using standardized Get-AuditResultsPath function
        try {
            # Use standardized path function if available
            if (Get-Command 'Get-AuditResultsPath' -ErrorAction SilentlyContinue) {
                $outputPath = Get-AuditResultsPath -ModuleName 'WindowsUpdates'
            }
            # Fallback to session path
            else {
                $outputPath = Get-SessionPath -Category 'data' -FileName 'windows-updates-results.json'
            }

            $auditResults | ConvertTo-Json -Depth 20 -WarningAction SilentlyContinue | Out-File -FilePath $outputPath -Encoding UTF8
            Write-Information "Audit results saved to standardized path: $outputPath" -InformationAction Continue
        }
        catch {
            Write-Warning "Failed to save audit results: $($_.Exception.Message)"
        }

        # Complete performance tracking
        try {
            Complete-PerformanceTracking -Context $perfContext -Status 'Success' -ResultCount $auditResults.UpdateIssues.Count
        }
        catch {
            Write-Verbose "Performance tracking completion failed - continuing"
        }

        return [PSCustomObject]$auditResults

    }
    catch {
        $errorMsg = "Windows Updates audit failed: $($_.Exception.Message)"
        Write-Error $errorMsg

        try {
            Write-LogEntry -Level 'ERROR' -Component 'WINDOWS-UPDATES-AUDIT' -Message $errorMsg -Data @{ Error = $_.Exception }
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
    Gets basic Windows Update status
#>
function Get-WindowsUpdateStatus {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    try {
        # Check Windows Update service
        $wuauserv = Get-Service -Name 'wuauserv' -ErrorAction SilentlyContinue

        # Get last successful scan time
        $lastScanTime = $null
        try {
            $au = New-Object -ComObject "Microsoft.Update.AutoUpdate"
            $lastScanTime = $au.Results.LastSearchSuccessDate
        }
        catch {
            Write-Verbose "Could not get last scan time: $($_.Exception.Message)"
        }

        # Check if reboot is pending
        $rebootPending = Test-PendingReboot

        return [PSCustomObject]@{
            ServiceName      = $wuauserv.Name
            ServiceStatus    = $wuauserv.Status
            ServiceStartType = $wuauserv.StartType
            LastScanTime     = $lastScanTime
            RebootPending    = $rebootPending
            OSVersion        = (Get-CimInstance Win32_OperatingSystem).Version
            OSBuild          = (Get-CimInstance Win32_OperatingSystem).BuildNumber
        }
    }
    catch {
        Write-Warning "Failed to get Windows Update status: $($_.Exception.Message)"
        return [PSCustomObject]@{ Error = $_.Exception.Message }
    }
}

<#
.SYNOPSIS
    Tests if a system reboot is pending
#>
function Test-PendingReboot {
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    try {
        # Check various registry locations for pending reboot
        $pendingReboot = $false

        # Check Component Based Servicing
        $cbs = Get-ChildItem "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending" -ErrorAction SilentlyContinue
        if ($cbs) { $pendingReboot = $true }

        # Check Windows Update
        $wu = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired" -ErrorAction SilentlyContinue
        if ($wu) { $pendingReboot = $true }

        # Check PendingFileRenameOperations
        $fileRename = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" -Name "PendingFileRenameOperations" -ErrorAction SilentlyContinue
        if ($fileRename) { $pendingReboot = $true }

        return $pendingReboot
    }
    catch {
        Write-Verbose "Could not determine pending reboot status: $($_.Exception.Message)"
        return $false
    }
}

<#
.SYNOPSIS
    Audits pending Windows Updates
#>
function Get-PendingUpdatesAudit {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    $issues = @()
    $pendingUpdates = @()

    try {
        # Try using PSWindowsUpdate module first
        if (Get-Module -ListAvailable -Name PSWindowsUpdate) {
            try {
                Import-Module PSWindowsUpdate -Force
                $updates = Get-WUList -ErrorAction SilentlyContinue
                if ($updates) {
                    foreach ($update in $updates) {
                        $updateInfo = [PSCustomObject]@{
                            Title          = $update.Title
                            Size           = $update.Size
                            Category       = $update.Categories -join ', '
                            Severity       = $update.MsrcSeverity
                            IsDownloaded   = $update.IsDownloaded
                            KBArticleIDs   = $update.KBArticleIDs -join ', '
                            RebootRequired = $update.RebootRequired
                        }
                        $pendingUpdates += $updateInfo

                        # Log detected pending update
                        Write-DetectionLog -Operation 'Detect' -Target $update.Title -Component 'WINDOWS-UPDATES' -AdditionalInfo @{
                            KB             = $update.KBArticleIDs -join ', '
                            Size           = "$([math]::Round($update.Size / 1MB, 2)) MB"
                            Category       = $update.Categories -join ', '
                            Severity       = $update.MsrcSeverity
                            IsDownloaded   = $update.IsDownloaded
                            RebootRequired = $update.RebootRequired
                            Status         = 'Pending Installation'
                            Source         = 'PSWindowsUpdate'
                        }

                        # Create issues for critical updates
                        if ($update.MsrcSeverity -eq 'Critical' -or $update.Categories -match 'Security') {
                            $issueItem = [PSCustomObject]@{
                                Category       = 'Security'
                                Type           = 'CriticalUpdatePending'
                                Description    = "Critical security update pending: $($update.Title)"
                                Impact         = 'High'
                                UpdateTitle    = $update.Title
                                KBArticleIDs   = $update.KBArticleIDs -join ', '
                                Recommendation = 'Install immediately for security'
                            }

                            # Log critical update alert
                            Write-DetectionLog -Operation 'Detect' -Target $update.Title -Component 'WINDOWS-UPDATES-CRITICAL' -AdditionalInfo @{
                                KB             = $update.KBArticleIDs -join ', '
                                Severity       = $update.MsrcSeverity
                                Category       = $update.Categories -join ', '
                                Priority       = 'CRITICAL'
                                SecurityRisk   = 'High - Unpatched security vulnerability'
                                Recommendation = 'Install immediately for security'
                                Reason         = "Critical security update not installed"
                            }

                            $issues += $issueItem
                        }
                    }
                }
            }
            catch {
                Write-Verbose "PSWindowsUpdate module failed: $($_.Exception.Message)"
            }
        }

        # Fallback to COM objects if PSWindowsUpdate not available
        if ($pendingUpdates.Count -eq 0) {
            try {
                $session = New-Object -ComObject Microsoft.Update.Session
                $searcher = $session.CreateUpdateSearcher()
                $searchResult = $searcher.Search("IsInstalled=0")

                foreach ($update in $searchResult.Updates) {
                    $updateInfo = [PSCustomObject]@{
                        Title          = $update.Title
                        Size           = $update.MaxDownloadSize
                        Category       = ($update.Categories | ForEach-Object { $_.Name }) -join ', '
                        Severity       = $update.MsrcSeverity
                        IsDownloaded   = $update.IsDownloaded
                        KBArticleIDs   = $update.KBArticleIDs -join ', '
                        RebootRequired = $update.RebootRequired
                    }
                    $pendingUpdates += $updateInfo

                    # Log detected pending update
                    Write-DetectionLog -Operation 'Detect' -Target $update.Title -Component 'WINDOWS-UPDATES' -AdditionalInfo @{
                        KB             = $update.KBArticleIDs -join ', '
                        Size           = "$([math]::Round($update.MaxDownloadSize / 1MB, 2)) MB"
                        Category       = ($update.Categories | ForEach-Object { $_.Name }) -join ', '
                        Severity       = $update.MsrcSeverity
                        IsDownloaded   = $update.IsDownloaded
                        RebootRequired = $update.RebootRequired
                        Status         = 'Pending Installation'
                        Source         = 'Windows Update COM API'
                    }

                    if ($update.MsrcSeverity -eq 'Critical' -or $update.Categories.Name -match 'Security') {
                        $issueItem = [PSCustomObject]@{
                            Category       = 'Security'
                            Type           = 'CriticalUpdatePending'
                            Description    = "Critical security update pending: $($update.Title)"
                            Impact         = 'High'
                            UpdateTitle    = $update.Title
                            KBArticleIDs   = $update.KBArticleIDs -join ', '
                            Recommendation = 'Install immediately for security'
                        }

                        # Log critical update alert
                        Write-DetectionLog -Operation 'Detect' -Target $update.Title -Component 'WINDOWS-UPDATES-CRITICAL' -AdditionalInfo @{
                            KB             = $update.KBArticleIDs -join ', '
                            Severity       = $update.MsrcSeverity
                            Category       = ($update.Categories | ForEach-Object { $_.Name }) -join ', '
                            Priority       = 'CRITICAL'
                            SecurityRisk   = 'High - Unpatched security vulnerability'
                            Recommendation = 'Install immediately for security'
                            Reason         = "Critical security update not installed"
                        }

                        $issues += $issueItem
                    }
                }
            }
            catch {
                Write-Warning "Failed to get pending updates via COM: $($_.Exception.Message)"
            }
        }

        # Create issues for large number of pending updates
        if ($pendingUpdates.Count -gt 10) {
            $issues += [PSCustomObject]@{
                Category       = 'Maintenance'
                Type           = 'ExcessivePendingUpdates'
                Description    = "Large number of pending updates: $($pendingUpdates.Count)"
                Impact         = 'Medium'
                UpdateCount    = $pendingUpdates.Count
                Recommendation = 'Schedule regular update installation'
            }
        }

    }
    catch {
        Write-Warning "Failed to audit pending updates: $($_.Exception.Message)"
    }

    return [PSCustomObject]@{
        PendingCount    = $pendingUpdates.Count
        SecurityUpdates = ($pendingUpdates | Where-Object { $_.Category -match 'Security' }).Count
        CriticalUpdates = ($pendingUpdates | Where-Object { $_.Severity -eq 'Critical' }).Count
        PendingUpdates  = $pendingUpdates
        Issues          = $issues
    }
}

<#
.SYNOPSIS
    Audits Windows Update installation history
#>
function Get-UpdateHistoryAudit {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    $issues = @()
    $recentUpdates = @()

    try {
        # Get update history from Windows Update log or registry
        $session = New-Object -ComObject Microsoft.Update.Session
        $searcher = $session.CreateUpdateSearcher()
        $historyCount = $searcher.GetTotalHistoryCount()

        if ($historyCount -gt 0) {
            # Get last 30 updates
            $history = $searcher.QueryHistory(0, [Math]::Min(30, $historyCount))

            foreach ($update in $history) {
                $updateInfo = [PSCustomObject]@{
                    Title      = $update.Title
                    Date       = $update.Date
                    Operation  = $update.Operation
                    ResultCode = $update.ResultCode
                    HResult    = $update.HResult
                    Categories = ($update.Categories | ForEach-Object { $_.Name }) -join ', '
                }
                $recentUpdates += $updateInfo

                # Check for failed updates
                if ($update.ResultCode -eq 4 -or $update.ResultCode -eq 5) {
                    # Failed or Aborted
                    $issues += [PSCustomObject]@{
                        Category       = 'Installation'
                        Type           = 'FailedUpdate'
                        Description    = "Failed update installation: $($update.Title)"
                        Impact         = 'Medium'
                        UpdateTitle    = $update.Title
                        FailureDate    = $update.Date
                        ErrorCode      = $update.HResult
                        Recommendation = 'Investigate and retry failed update'
                    }
                }
            }
        }

        # Check if no updates in last 30 days
        $recentSecurityUpdates = $recentUpdates | Where-Object {
            $_.Categories -match 'Security' -and $_.Date -gt (Get-Date).AddDays(-30)
        }

        if ($recentSecurityUpdates.Count -eq 0) {
            $issues += [PSCustomObject]@{
                Category           = 'Security'
                Type               = 'NoRecentSecurityUpdates'
                Description        = 'No security updates installed in the last 30 days'
                Impact             = 'High'
                LastSecurityUpdate = ($recentUpdates | Where-Object { $_.Categories -match 'Security' } | Sort-Object Date -Descending | Select-Object -First 1)?.Date
                Recommendation     = 'Check for and install available security updates'
            }
        }

    }
    catch {
        Write-Warning "Failed to audit update history: $($_.Exception.Message)"
    }

    return [PSCustomObject]@{
        TotalInHistory        = $recentUpdates.Count
        RecentSecurityUpdates = ($recentUpdates | Where-Object { $_.Categories -match 'Security' -and $_.Date -gt (Get-Date).AddDays(-30) }).Count
        FailedUpdates         = ($recentUpdates | Where-Object { $_.ResultCode -eq 4 -or $_.ResultCode -eq 5 }).Count
        RecentUpdates         = $recentUpdates
        Issues                = $issues
    }
}

<#
.SYNOPSIS
    Audits Windows Update service configuration
#>
function Get-UpdateConfigurationAudit {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    $issues = @()

    try {
        # Check Windows Update service status
        $wuService = Get-Service -Name 'wuauserv' -ErrorAction SilentlyContinue
        if (-not $wuService -or $wuService.Status -ne 'Running') {
            $issues += [PSCustomObject]@{
                Category       = 'Service'
                Type           = 'UpdateServiceNotRunning'
                Description    = 'Windows Update service is not running'
                Impact         = 'High'
                ServiceStatus  = $wuService?.Status ?? 'Not Found'
                Recommendation = 'Start and configure Windows Update service'
            }
        }

        # Check automatic update configuration
        $auSettings = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update" -ErrorAction SilentlyContinue
        if ($auSettings -and $auSettings.AUOptions -eq 1) {
            $issues += [PSCustomObject]@{
                Category       = 'Configuration'
                Type           = 'AutoUpdatesDisabled'
                Description    = 'Automatic updates are disabled'
                Impact         = 'High'
                CurrentSetting = 'Disabled'
                Recommendation = 'Enable automatic updates for security'
            }
        }

        # Check Windows Update for Business settings
        $wufbSettings = Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -ErrorAction SilentlyContinue
        if ($wufbSettings) {
            if ($wufbSettings.DeferFeatureUpdates -gt 365) {
                $issues += [PSCustomObject]@{
                    Category       = 'Configuration'
                    Type           = 'ExcessiveUpdateDeferral'
                    Description    = "Feature updates deferred for $($wufbSettings.DeferFeatureUpdates) days"
                    Impact         = 'Medium'
                    DeferralDays   = $wufbSettings.DeferFeatureUpdates
                    Recommendation = 'Review update deferral policy'
                }
            }
        }

        # Check for WSUS configuration
        $wsusServer = Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -Name "WUServer" -ErrorAction SilentlyContinue
        if ($wsusServer) {
            $issues += [PSCustomObject]@{
                Category       = 'Configuration'
                Type           = 'WSUSConfigured'
                Description    = "System configured to use WSUS server: $($wsusServer.WUServer)"
                Impact         = 'Low'
                WSUSServer     = $wsusServer.WUServer
                Recommendation = 'Verify WSUS server accessibility and configuration'
            }
        }

    }
    catch {
        Write-Warning "Failed to audit update configuration: $($_.Exception.Message)"
    }

    return [PSCustomObject]@{
        ServiceStatus     = (Get-Service -Name 'wuauserv' -ErrorAction SilentlyContinue)?.Status ?? 'Unknown'
        AutoUpdateEnabled = $auSettings?.AUOptions -ne 1
        WSUSConfigured    = $null -ne $wsusServer
        Issues            = $issues
    }
}

<#
.SYNOPSIS
    Performs security-focused update analysis
#>
function Get-UpdateSecurityAudit {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    $findings = @()

    try {
        # Check OS build and support status
        $osInfo = Get-CimInstance Win32_OperatingSystem
        $osVersion = $osInfo.Version
        $buildNumber = $osInfo.BuildNumber

        # Windows 10/11 support lifecycle check (simplified)
        $supportedBuilds = @{
            '10.0.19041' = 'Windows 10 20H1 - Extended support'
            '10.0.19042' = 'Windows 10 20H2 - Extended support'
            '10.0.19043' = 'Windows 10 21H1 - Extended support'
            '10.0.19044' = 'Windows 10 21H2 - Current support'
            '10.0.22000' = 'Windows 11 21H2 - Current support'
            '10.0.22621' = 'Windows 11 22H2 - Current support'
        }

        $currentBuildSupport = $supportedBuilds[$osVersion]
        if (-not $currentBuildSupport) {
            $findings += [PSCustomObject]@{
                Category       = 'Security'
                Type           = 'UnsupportedOSVersion'
                Description    = "OS version may not be receiving security updates: $osVersion (Build $buildNumber)"
                Impact         = 'High'
                OSVersion      = $osVersion
                BuildNumber    = $buildNumber
                Recommendation = 'Upgrade to supported Windows version'
            }
        }

        # Check last patch Tuesday
        $today = Get-Date
        $thisMonth = Get-Date -Day 1
        $patchTuesday = $thisMonth.AddDays((2 - [int]$thisMonth.DayOfWeek + 7) % 7 + 7)
        if ($patchTuesday -gt $today) {
            $patchTuesday = $patchTuesday.AddMonths(-1)
        }

        $daysSincePatchTuesday = ($today - $patchTuesday).Days
        if ($daysSincePatchTuesday -gt 14) {
            $findings += [PSCustomObject]@{
                Category         = 'Security'
                Type             = 'MissedPatchTuesday'
                Description      = "Last Patch Tuesday was $daysSincePatchTuesday days ago, updates may be missing"
                Impact           = 'Medium'
                LastPatchTuesday = $patchTuesday
                DaysSince        = $daysSincePatchTuesday
                Recommendation   = 'Check for and install latest security updates'
            }
        }

    }
    catch {
        Write-Warning "Failed to perform security analysis: $($_.Exception.Message)"
    }

    return [PSCustomObject]@{
        OSVersion      = $osInfo.Caption
        BuildNumber    = $osInfo.BuildNumber
        SecurityStatus = if ($findings.Count -eq 0) { 'Good' } else { 'Needs Attention' }
        Findings       = $findings
    }
}

<#
.SYNOPSIS
    Calculates overall Windows Update health score
#>
function Get-UpdateHealthScore {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$AuditResults
    )

    $baseScore = 100
    $deductions = 0

    # Deduct points based on update issues
    foreach ($issue in $AuditResults.UpdateIssues) {
        switch ($issue.Impact) {
            'High' { $deductions += 25 }
            'Medium' { $deductions += 15 }
            'Low' { $deductions += 5 }
        }
    }

    # Additional deductions for security findings
    foreach ($finding in $AuditResults.SecurityFindings) {
        switch ($finding.Impact) {
            'High' { $deductions += 30 }
            'Medium' { $deductions += 20 }
            'Low' { $deductions += 10 }
        }
    }

    $overallScore = [math]::Max(0, $baseScore - $deductions)

    return [PSCustomObject]@{
        Overall            = $overallScore
        MaxScore           = $baseScore
        Deductions         = $deductions
        IssueCount         = $AuditResults.UpdateIssues.Count
        SecurityIssueCount = $AuditResults.SecurityFindings.Count
        Category           = if ($overallScore -ge 90) { 'Excellent Update Health' }
        elseif ($overallScore -ge 70) { 'Good Update Health' }
        elseif ($overallScore -ge 50) { 'Fair Update Health' }
        else { 'Poor Update Health - Immediate Action Required' }
    }
}

<#
.SYNOPSIS
    Generates Windows Update recommendations
#>
function New-UpdateRecommendations {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$AuditResults
    )

    $recommendations = @()

    # Count issues by impact
    $highImpact = ($AuditResults.UpdateIssues + $AuditResults.SecurityFindings) | Where-Object { $_.Impact -eq 'High' }
    $mediumImpact = ($AuditResults.UpdateIssues + $AuditResults.SecurityFindings) | Where-Object { $_.Impact -eq 'Medium' }
    $securityIssues = $AuditResults.SecurityFindings

    if ($highImpact.Count -gt 0) {
        $recommendations += " Critical: Address $($highImpact.Count) high-impact update issues immediately"
        $recommendations += "   Priority: Security updates, service configuration, and failed installations"
    }

    if ($securityIssues.Count -gt 0) {
        $recommendations += " Security: $($securityIssues.Count) security-related findings require attention"
        $recommendations += "   Focus on OS support status and missing security patches"
    }

    if ($mediumImpact.Count -gt 0) {
        $recommendations += " Important: Resolve $($mediumImpact.Count) medium-impact update issues"
        $recommendations += "   Review update policies and installation schedules"
    }

    # Specific recommendations
    if ($AuditResults.PendingAudit -and $AuditResults.PendingAudit.SecurityUpdates -gt 0) {
        $recommendations += " Action: Install $($AuditResults.PendingAudit.SecurityUpdates) pending security updates"
    }

    if ($AuditResults.UpdateStatus -and $AuditResults.UpdateStatus.RebootPending) {
        $recommendations += " Action: System reboot required to complete previous updates"
    }

    if (($AuditResults.UpdateIssues + $AuditResults.SecurityFindings).Count -eq 0) {
        $recommendations += " Excellent! Windows Update system is healthy and current"
        $recommendations += " Continue monitoring for new updates and maintain regular update schedule"
    }

    return $recommendations
}

<#
.SYNOPSIS
    Type2 wrapper function for Windows Updates analysis

.DESCRIPTION
    Wrapper function that performs Windows Updates audit and saves results to temp_files/data/
    for consumption by Type2 modules. This is the v3.0 standardized interface between
    Type1 (detection) and Type2 (action) modules.

    Automatically saves results to temp_files/data/windows-updates-results.json using global paths.

.PARAMETER Config
    Configuration hashtable from orchestrator

.EXAMPLE
    $results = Get-WindowsUpdatesAnalysis -Config $Config
#>

#endregion

# Backward compatibility alias
New-Alias -Name 'Get-WindowsUpdatesAudit' -Value 'Get-WindowsUpdatesAnalysis'

# Export public functions
Export-ModuleMember -Function @(
    'Get-WindowsUpdatesAnalysis'  #  v3.0 PRIMARY function
) -Alias @('Get-WindowsUpdatesAudit')  # Backward compatibility



