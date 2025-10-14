#Requires -Version 7.0
# Module Dependencies:
#   - ConfigManager.psm1 (for configuration access)
#   - LoggingManager.psm1 (for structured logging)

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

# Import required modules
$ModuleRoot = Split-Path -Parent $PSScriptRoot
$FileOrgPath = Join-Path $ModuleRoot 'core\FileOrganizationManager.psm1'
if (Test-Path $FileOrgPath) {
    Import-Module $FileOrgPath -Force
}

$LoggingManagerPath = Join-Path $ModuleRoot 'core\LoggingManager.psm1'
if (Test-Path $LoggingManagerPath) {
    Import-Module $LoggingManagerPath -Force
}

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
    [CmdletBinding()]
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

    Write-Information "🔒 Starting comprehensive security audit..." -InformationAction Continue
    $startTime = Get-Date
    
    # Initialize structured logging and performance tracking
    try {
        Write-LogEntry -Level 'INFO' -Component 'SECURITY-AUDIT' -Message 'Starting comprehensive security audit' -Data @{
            IncludeDefenderScan = $IncludeDefenderScan.IsPresent
            CheckFirewall = $CheckFirewall.IsPresent
            CheckUAC = $CheckUAC.IsPresent
            CheckServices = $CheckServices.IsPresent
            CheckUpdates = $CheckUpdates.IsPresent
            GenerateReport = $GenerateReport.IsPresent
        }
        $perfContext = Start-PerformanceTracking -OperationName 'SecurityAudit' -Component 'SECURITY-AUDIT'
    } catch {
        # LoggingManager not available, continue with standard logging
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
        Write-Information "  🛡️  Checking Windows Defender status..." -InformationAction Continue
        $defenderResults = Get-WindowsDefenderStatus -IncludeScan:$IncludeDefenderScan
        $auditResults.Categories['WindowsDefender'] = $defenderResults
        Update-SecurityScore -Results $auditResults -Score $defenderResults.Score -MaxScore 25

        # Firewall Configuration (default: enabled)
        if ($CheckFirewall -or (-not $PSBoundParameters.ContainsKey('CheckFirewall'))) {
            Write-Information "  🔥 Checking Windows Firewall..." -InformationAction Continue
            $firewallResults = Get-FirewallStatus
            $auditResults.Categories['Firewall'] = $firewallResults
            Update-SecurityScore -Results $auditResults -Score $firewallResults.Score -MaxScore 20
        }

        # User Account Control (default: enabled)
        if ($CheckUAC -or (-not $PSBoundParameters.ContainsKey('CheckUAC'))) {
            Write-Information "  👤 Checking User Account Control..." -InformationAction Continue
            $uacResults = Get-UACStatus
            $auditResults.Categories['UAC'] = $uacResults
            Update-SecurityScore -Results $auditResults -Score $uacResults.Score -MaxScore 15
        }

        # Security Services (default: enabled)
        if ($CheckServices -or (-not $PSBoundParameters.ContainsKey('CheckServices'))) {
            Write-Information "  ⚙️  Auditing security services..." -InformationAction Continue
            $servicesResults = Get-SecurityServicesStatus
            $auditResults.Categories['Services'] = $servicesResults
            Update-SecurityScore -Results $auditResults -Score $servicesResults.Score -MaxScore 20
        }

        # Windows Updates (default: enabled)
        if ($CheckUpdates -or (-not $PSBoundParameters.ContainsKey('CheckUpdates'))) {
            Write-Information "  📥 Checking security updates..." -InformationAction Continue
            $updatesResults = Get-SecurityUpdatesStatus
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
        Write-Information "  ✅ Security audit completed in $([math]::Round($duration, 2))s" -InformationAction Continue
        Write-Information "    📊 Security Score: $($auditResults.Summary.OverallScore)/$($auditResults.Summary.MaxPossibleScore) ($($auditResults.Summary.PercentageScore)%)" -InformationAction Continue
        if ($auditResults.Summary.RiskLevel -eq "High") {
            Write-Warning "    ⚠️  Risk Level: $($auditResults.Summary.RiskLevel)"
        }
        else {
            Write-Information "    ⚠️  Risk Level: $($auditResults.Summary.RiskLevel)" -InformationAction Continue
        }
        Write-Information "    💡 Recommendations: $($auditResults.Summary.RecommendationsCount)" -InformationAction Continue

        # Generate report if requested (default: enabled)
        if ($GenerateReport -or (-not $PSBoundParameters.ContainsKey('GenerateReport'))) {
            $reportPath = New-SecurityReport -AuditResults $auditResults
            Write-Information "    📄 Security report: $reportPath" -InformationAction Continue
        }
        
        # Complete performance tracking and structured logging
        try {
            Complete-PerformanceTracking -PerformanceContext $perfContext -Success $true -ResultData @{
                SecurityScore = $auditResults.SecurityScore
                MaxScore = $auditResults.MaxScore
                PercentageScore = if ($auditResults.MaxScore -gt 0) { [math]::Round(($auditResults.SecurityScore / $auditResults.MaxScore) * 100, 1) } else { 0 }
                CategoriesAudited = $auditResults.Categories.Keys.Count
                RecommendationsCount = $auditResults.Recommendations.Count
                RiskLevel = $auditResults.Summary.RiskLevel
            }
            Write-LogEntry -Level 'SUCCESS' -Component 'SECURITY-AUDIT' -Message 'Security audit completed successfully' -Data $auditResults.Summary
        } catch {
            # LoggingManager not available, continue with standard logging
        }

        return $auditResults
    }
    catch {
        Write-Error "Security audit failed: $_"
        
        # Complete performance tracking for failed operation
        try {
            Complete-PerformanceTracking -PerformanceContext $perfContext -Success $false -ResultData @{ Error = $_.Exception.Message }
            Write-LogEntry -Level 'ERROR' -Component 'SECURITY-AUDIT' -Message 'Security audit failed' -Data @{ Error = $_.Exception.Message; ErrorType = $_.Exception.GetType().Name }
        } catch {
            # LoggingManager not available, continue with standard logging
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
    param(
        [Parameter()]
        [switch]$IncludeScan
    )

    # Start structured logging for Windows Defender status check
    try {
        Write-LogEntry -Level 'INFO' -Component 'SECURITY-AUDIT' -Message 'Checking Windows Defender status' -Data @{ IncludeScan = $IncludeScan.IsPresent }
    } catch {
        # LoggingManager not available, continue with standard logging
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
                Write-Information "    🔍 Performing quick security scan..." -InformationAction Continue
                try {
                    Start-MpScan -ScanType QuickScan -AsJob | Out-Null
                    Start-Sleep -Seconds 2  # Brief pause to let scan start
                    $results.Details.ScanInitiated = $true
                }
                catch {
                    $results.Issues.Add("Failed to initiate security scan: $_")
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
    param()

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
    param()

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
function Get-SecurityServicesStatus {
    [CmdletBinding()]
    param()

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
function Get-SecurityUpdatesStatus {
    [CmdletBinding()]
    param()

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
            $lastUpdate = Get-WmiObject -Class Win32_QuickFixEngineering -ErrorAction SilentlyContinue |
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
    param($AuditResults)

    # Save audit results using organized file system  
    $auditDataPath = Save-OrganizedFile -Data $AuditResults -FileType 'Data' -Category 'security' -FileName 'security-audit' -Format 'JSON'
    
    # Generate text report path
    $reportPath = Get-OrganizedFilePath -FileType 'Report' -FileName 'security-audit.txt'

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

#endregion

# Export module functions
Export-ModuleMember -Function @(
    'Start-SecurityAudit',
    'Get-WindowsDefenderStatus'
)

