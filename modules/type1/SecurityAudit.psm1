#Requires -Version 7.0
# Module Dependencies:
#   - CoreInfrastructure.psm1 (configuration, logging, paths)

<#
.SYNOPSIS
    Security Audit Module - Type 1 (Inventory/Reporting)

.DESCRIPTION
    Comprehensive security assessment and auditing of Windows systems.
    Evaluates security configurations, services, firewall, and provides recommendations.

.NOTES
    Module Type: Type 1 (Inventory/Reporting)
    Dependencies: Windows security features, registry access
    Requires: Administrator privileges for complete auditing
    Author: Windows Maintenance Automation Project
    Version: 1.0.0
#>

using namespace System.Collections.Generic

#region Module Dependencies Import

# Standard dependency import pattern for Windows Maintenance Automation
$ModuleRoot = Split-Path -Parent $PSScriptRoot

# Import CoreInfrastructure if not already available
$CoreInfraPath = Join-Path $ModuleRoot 'core\CoreInfrastructure.psm1'
if (-not (Get-Command -Name 'Get-SessionPath' -ErrorAction SilentlyContinue)) {
    if (Test-Path $CoreInfraPath) {
        Import-Module $CoreInfraPath -Force -Global
    }
}

#endregion

#region Fallback Functions

# Ensure critical functions are available with graceful degradation
if (-not (Get-Command -Name 'Write-LogEntry' -ErrorAction SilentlyContinue)) {
    function script:Write-LogEntry {
        param(
            [Parameter(Mandatory = $true)]
            [ValidateSet('DEBUG', 'INFO', 'SUCCESS', 'WARNING', 'ERROR', 'CRITICAL')]
            [string]$Level,

            [Parameter(Mandatory = $true)]
            [string]$Component,

            [Parameter(Mandatory = $true)]
            [string]$Message,

            [hashtable]$Data = @{}
        )

        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $logEntry = "[$timestamp] [$Level] [$Component] $Message"
        Write-Information $logEntry -InformationAction Continue
    }
}

if (-not (Get-Command -Name 'Get-OrganizedFilePath' -ErrorAction SilentlyContinue)) {
    function script:Get-OrganizedFilePath {
        param($FileType, $Category, $FileName)

        # Fallback to simple path resolution
        $scriptRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
        return Join-Path $scriptRoot "temp_files\$FileName"
    }
}

#endregion

#region Public Functions

<#
.SYNOPSIS
    Performs comprehensive security audit of the system

.DESCRIPTION
    Evaluates Windows security configurations including Windows Defender,
    Firewall, UAC, services, and provides detailed security recommendations.

.PARAMETER IncludeDefenderScan
    Include a Windows Defender scan in the audit

.PARAMETER CheckFirewall
    Check Windows Firewall configuration and status

.PARAMETER CheckUAC
    Check User Account Control settings

.PARAMETER CheckServices
    Audit security-related Windows services

.PARAMETER CheckUpdates
    Check Windows Update and security update status

.PARAMETER GenerateReport
    Generate a detailed security report

.EXAMPLE
    $audit = Start-SecurityAudit

.EXAMPLE
    $audit = Start-SecurityAudit -IncludeDefenderScan -GenerateReport
#>
function Start-SecurityAudit {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
    param(
        [Parameter()]
        [switch]$IncludeDefenderScan,

        [Parameter()]
        [switch]$CheckFirewall,

        [Parameter()]
        [switch]$CheckUAC,

        [Parameter()]
        [switch]$CheckServices,

        [Parameter()]
        [switch]$CheckUpdates,

        [Parameter()]
        [switch]$GenerateReport
    )

    Write-Information "[AUDIT] Starting comprehensive security audit..." -InformationAction Continue
    $startTime = Get-Date

    # Initialize structured logging and performance tracking
    try {
        Write-LogEntry -Level 'INFO' -Component 'SECURITY-AUDIT' -Message 'Starting comprehensive security audit' -Data @{
            IncludeDefenderScan = $IncludeDefenderScan.IsPresent
            CheckFirewall       = $CheckFirewall.IsPresent
            CheckUAC            = $CheckUAC.IsPresent
            CheckServices       = $CheckServices.IsPresent
            CheckUpdates        = $CheckUpdates.IsPresent
            GenerateReport      = $GenerateReport.IsPresent
        }
        $perfContext = Start-PerformanceTracking -OperationName 'SecurityAudit' -Component 'SECURITY-AUDIT'
    }
    catch {
        # LoggingManager not available, continue with standard logging
        Write-Verbose "Performance tracking not available: $_"
        $perfContext = $null
    }

    # Initialize audit results
    $auditResults = @{
        Timestamp       = $startTime
        ComputerName    = $env:COMPUTERNAME
        SecurityScore   = 0
        MaxScore        = 0
        Categories      = @{}
        Recommendations = @()
        Summary         = @{}
    }

    try {
        # Windows Defender Status
        Write-Information "  >> Checking Windows Defender status..." -InformationAction Continue
        $defenderResults = Get-WindowsDefenderStatus -IncludeScan:$IncludeDefenderScan
        $auditResults.Categories['WindowsDefender'] = $defenderResults
        Update-SecurityScore -Results $auditResults -Score $defenderResults.Score -MaxScore 25

        # Firewall Configuration (default: enabled)
        if ($CheckFirewall -or (-not $PSBoundParameters.ContainsKey('CheckFirewall'))) {
            Write-Information "  >> Checking Windows Firewall..." -InformationAction Continue
            $firewallResults = Get-FirewallStatus
            $auditResults.Categories['Firewall'] = $firewallResults
            Update-SecurityScore -Results $auditResults -Score $firewallResults.Score -MaxScore 20
        }

        # User Account Control (default: enabled)
        if ($CheckUAC -or (-not $PSBoundParameters.ContainsKey('CheckUAC'))) {
            Write-Information "  >> Checking User Account Control..." -InformationAction Continue
            $uacResults = Get-UACStatus
            $auditResults.Categories['UAC'] = $uacResults
            Update-SecurityScore -Results $auditResults -Score $uacResults.Score -MaxScore 15
        }

        # Security Services (default: enabled)
        if ($CheckServices -or (-not $PSBoundParameters.ContainsKey('CheckServices'))) {
            Write-Information "  >> Auditing security services..." -InformationAction Continue
            $servicesResults = Get-SecurityServiceStatus
            $auditResults.Categories['Services'] = $servicesResults
            Update-SecurityScore -Results $auditResults -Score $servicesResults.Score -MaxScore 20
        }

        # Windows Updates (default: enabled)
        if ($CheckUpdates -or (-not $PSBoundParameters.ContainsKey('CheckUpdates'))) {
            Write-Information "  >> Checking security updates..." -InformationAction Continue
            $updatesResults = Get-SecurityUpdateStatus
            $auditResults.Categories['Updates'] = $updatesResults
            Update-SecurityScore -Results $auditResults -Score $updatesResults.Score -MaxScore 20
        }

        # Generate security recommendations
        $auditResults.Recommendations = Get-SecurityRecommendation -AuditResults $auditResults

        # Calculate final security score percentage
        $auditResults.Summary = @{
            OverallScore         = $auditResults.SecurityScore
            MaxPossibleScore     = $auditResults.MaxScore
            PercentageScore      = if ($auditResults.MaxScore -gt 0) {
                [math]::Round(($auditResults.SecurityScore / $auditResults.MaxScore) * 100, 1)
            }
            else { 0 }
            RiskLevel            = Get-RiskLevel -Score ($auditResults.SecurityScore / [Math]::Max($auditResults.MaxScore, 1) * 100)
            RecommendationsCount = $auditResults.Recommendations.Count
            CategoriesAudited    = $auditResults.Categories.Keys.Count
        }

        $duration = ((Get-Date) - $startTime).TotalSeconds

        # Display summary
        Write-Information "  [OK] Security audit completed in $([math]::Round($duration, 2))s" -InformationAction Continue
        Write-Information "    Security Score: $($auditResults.Summary.OverallScore)/$($auditResults.Summary.MaxPossibleScore) ($($auditResults.Summary.PercentageScore)%)" -InformationAction Continue
        if ($auditResults.Summary.RiskLevel -eq "High") {
            Write-Warning "    ⚠️  Risk Level: $($auditResults.Summary.RiskLevel)"
        }
        else {
            Write-Information "    [!] Risk Level: $($auditResults.Summary.RiskLevel)" -InformationAction Continue
        }
        Write-Information "    Recommendations: $($auditResults.Summary.RecommendationsCount)" -InformationAction Continue

        # Generate report if requested (default: enabled)
        if ($GenerateReport -or (-not $PSBoundParameters.ContainsKey('GenerateReport'))) {
            if ($PSCmdlet.ShouldProcess("Security audit report", "Generate security audit report files")) {
                $reportPath = New-SecurityReport -AuditResults $auditResults
                Write-Information "    Report saved: $reportPath" -InformationAction Continue
            }
            else {
                Write-Information "    ⏭️ Security report generation skipped (WhatIf mode)" -InformationAction Continue
            }
        }

        # Complete performance tracking and structured logging
        try {
            Complete-PerformanceTracking -PerformanceContext $perfContext -Success $true -ResultData @{
                SecurityScore        = $auditResults.SecurityScore
                MaxScore             = $auditResults.MaxScore
                PercentageScore      = if ($auditResults.MaxScore -gt 0) { [math]::Round(($auditResults.SecurityScore / $auditResults.MaxScore) * 100, 1) } else { 0 }
                CategoriesAudited    = $auditResults.Categories.Keys.Count
                RecommendationsCount = $auditResults.Recommendations.Count
                RiskLevel            = $auditResults.Summary.RiskLevel
            }
            Write-LogEntry -Level 'SUCCESS' -Component 'SECURITY-AUDIT' -Message 'Security audit completed successfully' -Data $auditResults.Summary
        }
        catch {
            # LoggingManager not available, continue with standard logging
            Write-Verbose "Structured logging not available for audit completion: $_"
        }

        return $auditResults
    }
    catch {
        Write-Error "Security audit failed: $_"

        # Complete performance tracking for failed operation
        try {
            Complete-PerformanceTracking -PerformanceContext $perfContext -Success $false -ResultData @{ Error = $_.Exception.Message }
            Write-LogEntry -Level 'ERROR' -Component 'SECURITY-AUDIT' -Message 'Security audit failed' -Data @{ Error = $_.Exception.Message; ErrorType = $_.Exception.GetType().Name }
        }
        catch {
            # LoggingManager not available, continue with standard logging
            Write-Verbose "Structured logging not available for error reporting: $_"
        }

        throw
    }
}

<#
.SYNOPSIS
    Gets current Windows Defender status and configuration

.DESCRIPTION
    Evaluates Windows Defender antivirus status, configuration,
    and optionally performs a security scan.

.PARAMETER IncludeScan
    Perform a quick security scan

.EXAMPLE
    $defenderStatus = Get-WindowsDefenderStatus -IncludeScan
#>
<#
.SYNOPSIS
    Retrieves comprehensive Windows Defender security status and configuration

.DESCRIPTION
    Analyzes Windows Defender status including real-time protection, definition updates,
    scan history, and threat detection. Calculates security score based on configuration
    and provides detailed assessment of protection status.

.PARAMETER IncludeScan
    Include detailed scan history and threat detection information in the analysis

.OUTPUTS
    [hashtable] Defender status including Enabled, RealTimeProtectionEnabled,
    DefinitionsUpToDate, LastScanDate, ThreatsDetected, Score, and detailed Issues

.EXAMPLE
    $defenderStatus = Get-WindowsDefenderStatus -IncludeScan
    Write-Information "Defender Score: $($defenderStatus.Score)/$($defenderStatus.MaxScore)" -InformationAction Continue

.NOTES
    Part of the SecurityAudit module for comprehensive system security assessment.
    Requires Windows Defender PowerShell module for full functionality.
#>
function Get-WindowsDefenderStatus {
    [CmdletBinding()]
    [OutputType([hashtable])]`nparam(
        [Parameter()]
        [switch]$IncludeScan
    )

    # Start structured logging for Windows Defender status check
    try {
        Write-LogEntry -Level 'INFO' -Component 'SECURITY-AUDIT' -Message 'Checking Windows Defender status' -Data @{ IncludeScan = $IncludeScan.IsPresent }
    }
    catch {
        # LoggingManager not available, continue with standard logging
        Write-Verbose "Structured logging not available for Defender status check: $_"
    }

    $results = @{
        Enabled                   = $false
        RealTimeProtectionEnabled = $false
        DefinitionsUpToDate       = $false
        LastScanDate              = $null
        ThreatsDetected           = 0
        Score                     = 0
        MaxScore                  = 25
        Details                   = @{}
        Issues                    = (New-Object 'System.Collections.Generic.List[System.String]')
    }
    try {
        # Check if Defender module is available
        if (Get-Command Get-MpComputerStatus -ErrorAction SilentlyContinue) {
            $defenderStatus = Get-MpComputerStatus -ErrorAction SilentlyContinue

            if ($defenderStatus) {
                $results.Enabled = $defenderStatus.AntivirusEnabled
                $results.RealTimeProtectionEnabled = $defenderStatus.RealTimeProtectionEnabled
                $results.DefinitionsUpToDate = ((Get-Date) - $defenderStatus.AntivirusSignatureLastUpdated).TotalDays -lt 7
                $results.LastScanDate = $defenderStatus.FullScanStartTime

                $results.Details = @{
                    AntivirusEnabled          = $defenderStatus.AntivirusEnabled
                    AntispywareEnabled        = $defenderStatus.AntispywareEnabled
                    RealTimeProtectionEnabled = $defenderStatus.RealTimeProtectionEnabled
                    OnAccessProtectionEnabled = $defenderStatus.OnAccessProtectionEnabled
                    IoavProtectionEnabled     = $defenderStatus.IoavProtectionEnabled
                    BehaviorMonitorEnabled    = $defenderStatus.BehaviorMonitorEnabled
                    SignatureLastUpdated      = $defenderStatus.AntivirusSignatureLastUpdated
                    EngineVersion             = $defenderStatus.AMEngineVersion
                }

                # Calculate score based on security features
                if ($results.Enabled) { $results.Score += 10 }
                if ($results.RealTimeProtectionEnabled) { $results.Score += 8 }
                if ($results.DefinitionsUpToDate) { $results.Score += 5 }
                if ($defenderStatus.BehaviorMonitorEnabled) { $results.Score += 2 }

                # Check for issues
                if (-not $results.Enabled) {
                    $results.Issues.Add("Windows Defender is not enabled")
                }
                if (-not $results.RealTimeProtectionEnabled) {
                    $results.Issues.Add("Real-time protection is disabled")
                }
                if (-not $results.DefinitionsUpToDate) {
                    $results.Issues.Add("Antivirus definitions are outdated")
                }
            }
            else {
                $results.Issues.Add("Unable to retrieve Windows Defender status")
            }

            # Perform scan if requested
            if ($IncludeScan) {
                Write-Information "    [SCAN] Initiating quick security scan (background)..." -InformationAction Continue
                try {
                    # Run scan as background job without waiting
                    $scanJob = Start-MpScan -ScanType QuickScan -AsJob -ErrorAction Stop
                    $results.Details.ScanInitiated = $true
                    $results.Details.ScanJobId = $scanJob.Id
                    Write-Verbose "Security scan job started with ID: $($scanJob.Id)"
                }
                catch {
                    $results.Issues.Add("Failed to initiate security scan: $_")
                    Write-Verbose "Scan initiation error: $_"
                }
            }
        }
        else {
            $results.Issues.Add("Windows Defender PowerShell module not available")
        }
    }
    catch {
        $results.Issues.Add("Error checking Windows Defender: $_")
    }

    return $results
}

#endregion

#region Firewall Assessment

<#
.SYNOPSIS
    Gets Windows Firewall status and configuration
#>
function Get-FirewallStatus {
    [CmdletBinding()]
    [OutputType([hashtable])]`nparam()

    $results = @{
        DomainEnabled  = $false
        PrivateEnabled = $false
        PublicEnabled  = $false
        Score          = 0
        MaxScore       = 20
        Details        = @{}
        Issues         = (New-Object 'System.Collections.Generic.List[System.String]')
    }

    try {
        if (Get-Command Get-NetFirewallProfile -ErrorAction SilentlyContinue) {
            $profiles = Get-NetFirewallProfile

            foreach ($firewallProfile in $profiles) {
                $profileName = $firewallProfile.Name
                $enabled = $firewallProfile.Enabled

                $results.Details[$profileName] = @{
                    Enabled               = $enabled
                    DefaultInboundAction  = $firewallProfile.DefaultInboundAction
                    DefaultOutboundAction = $firewallProfile.DefaultOutboundAction
                }

                # Update status based on profile
                switch ($profileName) {
                    'Domain' {
                        $results.DomainEnabled = $enabled
                        if ($enabled) { $results.Score += 5 }
                    }
                    'Private' {
                        $results.PrivateEnabled = $enabled
                        if ($enabled) { $results.Score += 8 }
                    }
                    'Public' {
                        $results.PublicEnabled = $enabled
                        if ($enabled) { $results.Score += 7 }
                    }
                }

                if (-not $enabled) {
                    $results.Issues.Add("$profileName firewall profile is disabled")
                }
            }
        }
        else {
            # Fallback to registry check
            $firewallKeys = @{
                'Domain'  = 'HKLM:\SYSTEM\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy\DomainProfile'
                'Private' = 'HKLM:\SYSTEM\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy\PrivateProfile'
                'Public'  = 'HKLM:\SYSTEM\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy\PublicProfile'
            }

            foreach ($firewallProfile in $firewallKeys.Keys) {
                try {
                    $enabled = (Get-ItemProperty -Path $firewallKeys[$firewallProfile] -Name EnableFirewall -ErrorAction SilentlyContinue).EnableFirewall -eq 1
                    $results.Details[$firewallProfile] = @{ Enabled = $enabled }

                    switch ($firewallProfile) {
                        'Domain' { $results.DomainEnabled = $enabled }
                        'Private' { $results.PrivateEnabled = $enabled }
                        'Public' { $results.PublicEnabled = $enabled }
                    }

                    if ($enabled) {
                        $results.Score += switch ($firewallProfile) { 'Domain' { 5 } 'Private' { 8 } 'Public' { 7 } }
                    }
                    else {
                        $results.Issues.Add("$firewallProfile firewall profile is disabled")
                    }
                }
                catch {
                    $results.Issues.Add("Unable to check $firewallProfile firewall status")
                }
            }
        }
    }
    catch {
        $results.Issues.Add("Error checking firewall status: $_")
    }

    return $results
}

#endregion

#region UAC Assessment

<#
.SYNOPSIS
    Gets User Account Control status and configuration
#>
function Get-UACStatus {
    [CmdletBinding()]
    [OutputType([hashtable])]`nparam()

    $results = @{
        Enabled  = $false
        Level    = 'Unknown'
        Score    = 0
        MaxScore = 15
        Details  = @{}
        Issues   = (New-Object 'System.Collections.Generic.List[System.String]')
    }

    try {
        $uacPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'

        if (Test-Path $uacPath) {
            $enableLUA = (Get-ItemProperty -Path $uacPath -Name EnableLUA -ErrorAction SilentlyContinue).EnableLUA
            $consentPromptBehaviorAdmin = (Get-ItemProperty -Path $uacPath -Name ConsentPromptBehaviorAdmin -ErrorAction SilentlyContinue).ConsentPromptBehaviorAdmin
            $promptOnSecureDesktop = (Get-ItemProperty -Path $uacPath -Name PromptOnSecureDesktop -ErrorAction SilentlyContinue).PromptOnSecureDesktop

            $results.Enabled = $enableLUA -eq 1
            $results.Details = @{
                EnableLUA                  = $enableLUA
                ConsentPromptBehaviorAdmin = $consentPromptBehaviorAdmin
                PromptOnSecureDesktop      = $promptOnSecureDesktop
            }

            # Determine UAC level
            if ($enableLUA -eq 1) {
                $results.Score += 10

                switch ($consentPromptBehaviorAdmin) {
                    0 { $results.Level = 'Never notify'; $results.Score -= 5 }
                    1 { $results.Level = 'Prompt for credentials on secure desktop'; $results.Score += 3 }
                    2 { $results.Level = 'Always notify'; $results.Score += 5 }
                    5 { $results.Level = 'Prompt for consent for non-Windows binaries'; $results.Score += 2 }
                    default { $results.Level = "Custom ($consentPromptBehaviorAdmin)" }
                }

                if ($promptOnSecureDesktop -eq 1) {
                    $results.Score += 2
                }
            }
            else {
                $results.Level = 'Disabled'
                $results.Issues.Add("User Account Control is disabled")
            }
        }
        else {
            $results.Issues.Add("Unable to access UAC registry settings")
        }
    }
    catch {
        $results.Issues.Add("Error checking UAC status: $_")
    }

    return $results
}

#endregion

#region Services Assessment

<#
.SYNOPSIS
    Gets security-related Windows services status
#>
function Get-SecurityServiceStatus {
    [CmdletBinding()]
    [OutputType([hashtable])]`nparam()

    $results = @{
        Score    = 0
        MaxScore = 20
        Details  = @{}
        Issues   = (New-Object 'System.Collections.Generic.List[System.String]')
    }

    # Critical security services
    $securityServices = @{
        'WinDefend' = @{ Name = 'Windows Defender Antivirus Service'; Critical = $true; Points = 5 }
        'WdNisSvc'  = @{ Name = 'Windows Defender Network Inspection Service'; Critical = $true; Points = 3 }
        'Sense'     = @{ Name = 'Windows Defender Advanced Threat Protection'; Critical = $false; Points = 2 }
        'wscsvc'    = @{ Name = 'Windows Security Center'; Critical = $true; Points = 3 }
        'Wuauserv'  = @{ Name = 'Windows Update'; Critical = $true; Points = 3 }
        'BITS'      = @{ Name = 'Background Intelligent Transfer Service'; Critical = $false; Points = 2 }
        'CryptSvc'  = @{ Name = 'Cryptographic Services'; Critical = $true; Points = 2 }
    }

    foreach ($serviceName in $securityServices.Keys) {
        $serviceInfo = $securityServices[$serviceName]

        try {
            $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue

            if ($service) {
                $serviceDetails = @{
                    DisplayName = $service.DisplayName
                    Status      = $service.Status
                    StartType   = $service.StartType
                    Critical    = $serviceInfo.Critical
                }

                $results.Details[$serviceName] = $serviceDetails

                # Award points based on service status
                if ($service.Status -eq 'Running' -and $service.StartType -eq 'Automatic') {
                    $results.Score += $serviceInfo.Points
                }
                elseif ($serviceInfo.Critical -and $service.Status -ne 'Running') {
                    $results.Issues.Add("Critical security service '$($serviceInfo.Name)' is not running")
                }
                elseif ($serviceInfo.Critical -and $service.StartType -ne 'Automatic') {
                    $results.Issues.Add("Critical security service '$($serviceInfo.Name)' is not set to automatic startup")
                }
            }
            else {
                $results.Details[$serviceName] = @{ Status = 'Not Found'; Critical = $serviceInfo.Critical }
                if ($serviceInfo.Critical) {
                    $results.Issues.Add("Critical security service '$($serviceInfo.Name)' not found")
                }
            }
        }
        catch {
            $results.Issues.Add("Error checking service $serviceName`: $_")
        }
    }

    return $results
}

#endregion

#region Updates Assessment

<#
.SYNOPSIS
    Gets security updates status
#>
function Get-SecurityUpdateStatus {
    [CmdletBinding()]
    [OutputType([hashtable])]`nparam()

    $results = @{
        Score           = 0
        MaxScore        = 20
        LastInstallDate = $null
        PendingReboot   = $false
        Details         = @{}
        Issues          = (New-Object 'System.Collections.Generic.List[System.String]')
    }

    try {
        # Check Windows Update service
        $wuService = Get-Service -Name wuauserv -ErrorAction SilentlyContinue
        if ($wuService -and $wuService.Status -eq 'Running') {
            $results.Score += 5
        }
        else {
            $results.Issues.Add("Windows Update service is not running")
        }

        # Check for pending reboot
        $rebootKeys = @(
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired",
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending"
        )

        foreach ($key in $rebootKeys) {
            if (Test-Path $key) {
                $results.PendingReboot = $true
                $results.Issues.Add("System reboot required to complete updates")
                break
            }
        }

        if (-not $results.PendingReboot) {
            $results.Score += 5
        }

        # Try to get last update installation date
        try {
            $lastUpdate = Get-CimInstance -ClassName Win32_QuickFixEngineering -ErrorAction SilentlyContinue |
            Sort-Object InstalledOn -Descending | Select-Object -First 1

            if ($lastUpdate -and $lastUpdate.InstalledOn) {
                $results.LastInstallDate = $lastUpdate.InstalledOn
                $daysSinceUpdate = ((Get-Date) - $lastUpdate.InstalledOn).Days

                # Award points based on update recency
                if ($daysSinceUpdate -le 7) { $results.Score += 10 }
                elseif ($daysSinceUpdate -le 30) { $results.Score += 5 }
                elseif ($daysSinceUpdate -le 90) { $results.Score += 2 }
                else {
                    $results.Issues.Add("No recent security updates installed (last: $($daysSinceUpdate) days ago)")
                }
            }
        }
        catch {
            $results.Issues.Add("Unable to determine last update installation date")
        }

    }
    catch {
        $results.Issues.Add("Error checking security updates: $_")
    }

    return $results
}

#endregion

#region Helper Functions

<#
.SYNOPSIS
    Updates security score for a category
#>
function Update-SecurityScore {
    param($Results, $Score, $MaxScore)

    $Results.SecurityScore += $Score
    $Results.MaxScore += $MaxScore
}

<#
.SYNOPSIS
    Determines risk level based on security score
#>
function Get-RiskLevel {
    param([double]$Score)

    if ($Score -ge 80) { return 'Low' }
    elseif ($Score -ge 60) { return 'Medium' }
    else { return 'High' }
}

<#
.SYNOPSIS
    Generates security recommendations based on audit results
#>
function Get-SecurityRecommendation {
    param($AuditResults)

    $recommendations = New-Object System.Collections.ArrayList

    foreach ($category in $AuditResults.Categories.Keys) {
        $categoryData = $AuditResults.Categories[$category]

        if ($categoryData.Issues -and $categoryData.Issues.Count -gt 0) {
            foreach ($issue in $categoryData.Issues) {
                $null = $recommendations.Add([PSCustomObject]@{
                        Category       = $category
                        Priority       = Get-IssuePriority -Issue $issue
                        Issue          = $issue
                        Recommendation = Get-IssueRecommendation -Issue $issue
                    })
            }
        }
    }

    return $recommendations | Sort-Object Priority
}

<#
.SYNOPSIS
    Gets priority level for a security issue
#>
function Get-IssuePriority {
    param([string]$Issue)

    if ($Issue -like "*disabled*" -or $Issue -like "*not enabled*") { return 'High' }
    elseif ($Issue -like "*outdated*" -or $Issue -like "*not running*") { return 'Medium' }
    else { return 'Low' }
}

<#
.SYNOPSIS
    Gets recommendation for a security issue
#>
function Get-IssueRecommendation {
    param([string]$Issue)

    switch -Wildcard ($Issue) {
        "*Defender*disabled*" { "Enable Windows Defender Antivirus" }
        "*firewall*disabled*" { "Enable Windows Firewall for all network profiles" }
        "*UAC*disabled*" { "Enable User Account Control" }
        "*definitions*outdated*" { "Update antivirus definitions" }
        "*service*not running*" { "Start and configure security services" }
        "*reboot required*" { "Restart system to complete security updates" }
        default { "Review and address security configuration" }
    }
}

<#
.SYNOPSIS
    Creates a detailed security report
#>
function New-SecurityReport {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
    param($AuditResults)

    if ($PSCmdlet.ShouldProcess("Security audit report", "Generate security audit report and data files")) {
        # Save audit results using standardized path function
        try {
            if (Get-Command 'Get-AuditResultsPath' -ErrorAction SilentlyContinue) {
                $auditDataPath = Get-AuditResultsPath -ModuleName 'Security'
            }
            else {
                $auditDataPath = Get-SessionPath -Category 'data' -FileName 'security-audit.json'
            }
            $AuditResults | ConvertTo-Json -Depth 20 -WarningAction SilentlyContinue | Out-File -FilePath $auditDataPath -Encoding UTF8
        }
        catch {
            Write-Warning "Failed to save audit results: $($_.Exception.Message)"
            $auditDataPath = "N/A"
        }

        # Generate text report path
        $reportPath = Join-Path $env:MAINTENANCE_TEMP_ROOT 'reports\security-audit.txt'
        $reportDir = Split-Path -Parent $reportPath
        if (-not (Test-Path $reportDir)) {
            New-Item -Path $reportDir -ItemType Directory -Force | Out-Null
        }

        $report = @"
WINDOWS SECURITY AUDIT REPORT
==============================
Generated: $($AuditResults.Timestamp)
Computer: $($AuditResults.ComputerName)
Overall Score: $($AuditResults.Summary.OverallScore)/$($AuditResults.Summary.MaxPossibleScore) ($($AuditResults.Summary.PercentageScore)%)
Risk Level: $($AuditResults.Summary.RiskLevel)
JSON Data: $auditDataPath

CATEGORY DETAILS:
"@

        foreach ($category in $AuditResults.Categories.Keys) {
            $categoryData = $AuditResults.Categories[$category]
            $report += "`n`n$category Security Assessment:"
            $report += "`n  Score: $($categoryData.Score)/$($categoryData.MaxScore)"

            if ($categoryData.Issues -and $categoryData.Issues.Count -gt 0) {
                $report += "`n  Issues:"
                foreach ($issue in $categoryData.Issues) {
                    $report += "`n    - $issue"
                }
            }
        }

        if ($AuditResults.Recommendations.Count -gt 0) {
            $report += "`n`nRECOMMENDATIONS:"
            foreach ($rec in $AuditResults.Recommendations) {
                $report += "`n[$($rec.Priority)] $($rec.Recommendation)"
            }
        }

        $report | Out-File -FilePath $reportPath -Encoding UTF8
        return $reportPath
    }
    else {
        Write-Verbose "Security report generation skipped (WhatIf mode)"
        return "security-audit-report-whatif.txt"
    }
}

#endregion

#region v3.0 Standardized Interface for Type2 Modules

<#
.SYNOPSIS
    v3.0 Wrapper function for Type2 modules to get security audit analysis

.DESCRIPTION
    Standardized analysis function that Type2 modules call to get security audit results.
    Automatically saves results to temp_files/data/security-audit-results.json using global paths.

.PARAMETER Config
    Configuration hashtable from orchestrator

.EXAMPLE
    $results = Get-SecurityAuditAnalysis -Config $Config
#>
function Get-SecurityAuditAnalysis {
    [CmdletBinding()]
    [OutputType([hashtable])]`nparam(
        [Parameter(Mandatory)]
        [hashtable]$Config
    )

    Write-LogEntry -Level 'INFO' -Component 'SECURITY-AUDIT' -Message 'Starting security audit for Type2 module'

    try {
        # Perform the security audit
        $auditResults = Start-SecurityAudit

        # Use standardized Get-AuditResultsPath function for consistent path
        if (Get-Command 'Get-AuditResultsPath' -ErrorAction SilentlyContinue) {
            $dataPath = Get-AuditResultsPath -ModuleName 'SecurityAudit'
        }
        else {
            # Fallback to direct path construction if function not available
            $dataPath = Join-Path (Get-MaintenancePath 'TempRoot') "data\security-audit-results.json"
        }

        # Save results to standardized temp_files/data/ location
        if ($dataPath) {
            # Ensure directory exists
            $dataDir = Split-Path -Parent $dataPath
            if (-not (Test-Path $dataDir)) {
                New-Item -Path $dataDir -ItemType Directory -Force | Out-Null
            }

            # Save JSON results
            $auditResults | ConvertTo-Json -Depth 10 | Set-Content -Path $dataPath -Encoding UTF8
            Write-LogEntry -Level 'INFO' -Component 'SECURITY-AUDIT' -Message "Audit results saved to: $dataPath"
        }

        Write-LogEntry -Level 'INFO' -Component 'SECURITY-AUDIT' -Message 'Security audit completed successfully'

        return $auditResults
    }
    catch {
        Write-LogEntry -Level 'ERROR' -Component 'SECURITY-AUDIT' -Message "Security audit failed: $($_.Exception.Message)"
        throw
    }
}

#endregion

# Export module functions
Export-ModuleMember -Function @(
    'Start-SecurityAudit',
    'Get-SecurityAuditAnalysis'  # v3.0 PRIMARY function for Type2 integration
    'Get-WindowsDefenderStatus'
)



