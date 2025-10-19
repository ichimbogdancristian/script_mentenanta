#Requires -Version 7.0

<#
.SYNOPSIS
    System Analysis Module - Consolidated System Inventory and Security Audit

.DESCRIPTION
    Consolidated module that provides comprehensive system information collection
    and security auditing capabilities. Combines SystemInventory and SecurityAudit
    functionality into a single cohesive module.

.NOTES
    Module Type: Core Infrastructure (Consolidated)
    Dependencies: Windows WMI/CIM, Registry access
    Author: Windows Maintenance Automation Project
    Version: 2.0.0 (Consolidated)
#>

using namespace System.Collections.Generic

# Import CoreInfrastructure for logging and file operations
$CoreInfraPath = Join-Path $PSScriptRoot 'CoreInfrastructure.psm1'
if (Test-Path $CoreInfraPath) {
    Import-Module $CoreInfraPath -Force
}

#region System Inventory Functions

<#
.SYNOPSIS
    Collects comprehensive system inventory information

.DESCRIPTION
    Gathers detailed system information including hardware specs, installed software,
    running services, network configuration, and security settings.

.PARAMETER UseCache
    Use cached results if available and not expired

.PARAMETER CacheTimeout
    Cache timeout in minutes (default: 30)

.PARAMETER IncludeDetailed
    Include detailed information that may take longer to collect

.EXAMPLE
    $inventory = Get-SystemInventory -IncludeDetailed
#>
function Get-SystemInventory {
    [CmdletBinding()]
    param(
        [Parameter()]
        [switch]$UseCache,

        [Parameter()]
        [int]$CacheTimeout = 30,

        [Parameter()]
        [switch]$IncludeDetailed
    )

    Write-Information "🔍 Starting system inventory collection..." -InformationAction Continue
    
    # Start performance tracking
    $perfContext = $null
    try {
        $perfContext = Start-PerformanceTracking -OperationName 'SystemInventory' -Component 'SYSTEM-ANALYSIS'
        Write-LogEntry -Level 'INFO' -Component 'SYSTEM-ANALYSIS' -Message 'Starting comprehensive system inventory collection' -Data @{
            UseCache        = $UseCache
            CacheTimeout    = $CacheTimeout
            IncludeDetailed = $IncludeDetailed
        }
    }
    catch {
        # CoreInfrastructure not available, continue with standard output
        Write-Information "System inventory collection started" -InformationAction Continue
    }

    try {
        # Check cache first if requested
        if ($UseCache) {
            $cacheFile = Get-SessionPath -Category 'data' -FileName 'system-inventory.json'
            if ($cacheFile -and (Test-Path $cacheFile)) {
                $cacheAge = (Get-Date) - (Get-Item $cacheFile).LastWriteTime
                if ($cacheAge.TotalMinutes -le $CacheTimeout) {
                    Write-Information "Using cached system inventory data" -InformationAction Continue
                    return Get-SessionData -Category 'data' -FileName 'system-inventory.json'
                }
            }
        }

        # Collect system information
        $inventory = @{
            CollectionTimestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            SystemInfo          = Get-BasicSystemInfo
            Hardware            = Get-HardwareInfo
            Software            = Get-SoftwareInfo
            Services            = Get-ServicesInfo
            Network             = Get-NetworkInfo
            Security            = Get-SecurityInfo
        }

        if ($IncludeDetailed) {
            $inventory.DetailedHardware = Get-DetailedHardwareInfo
            $inventory.DetailedSoftware = Get-DetailedSoftwareInfo
        }

        Write-Information "✓ System inventory collection completed" -InformationAction Continue

        # Save results to session data
        try {
            Save-SessionData -Category 'data' -Data $inventory -FileName 'system-inventory.json'
        }
        catch {
            Write-Warning "Failed to save inventory results: $($_.Exception.Message)"
        }

        # Complete performance tracking
        try {
            Complete-PerformanceTracking -Context $perfContext -Status 'Success'
        }
        catch {}

        return [PSCustomObject]$inventory

    }
    catch {
        $errorMsg = "System inventory collection failed: $($_.Exception.Message)"
        Write-Error $errorMsg
        
        try {
            Write-LogEntry -Level 'ERROR' -Component 'SYSTEM-ANALYSIS' -Message $errorMsg -Data @{ Error = $_.Exception }
            Complete-PerformanceTracking -Context $perfContext -Status 'Failed' -ErrorMessage $errorMsg
        }
        catch {}
        
        throw
    }
}

<#
.SYNOPSIS
    Gets basic system information
#>
function Get-BasicSystemInfo {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    try {
        $computerInfo = Get-ComputerInfo -Property WindowsProductName, WindowsVersion, WindowsBuildLabEx, TotalPhysicalMemory, CsProcessors
        $bootTime = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
        
        return [PSCustomObject]@{
            ComputerName = $env:COMPUTERNAME
            UserName     = $env:USERNAME
            Domain       = $env:USERDOMAIN
            OS           = $computerInfo.WindowsProductName
            Version      = $computerInfo.WindowsVersion
            Build        = $computerInfo.WindowsBuildLabEx
            Architecture = $env:PROCESSOR_ARCHITECTURE
            RAM          = [math]::Round($computerInfo.TotalPhysicalMemory / 1GB, 2)
            Processors   = $computerInfo.CsProcessors.Count
            LastBootTime = $bootTime
            Uptime       = (Get-Date) - $bootTime
        }
    }
    catch {
        Write-Warning "Failed to get basic system info: $($_.Exception.Message)"
        return [PSCustomObject]@{ Error = $_.Exception.Message }
    }
}

<#
.SYNOPSIS
    Gets hardware information
#>
function Get-HardwareInfo {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    try {
        $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
        $memory = Get-CimInstance Win32_PhysicalMemory
        $disks = Get-CimInstance Win32_LogicalDisk | Where-Object { $_.DriveType -eq 3 }
        
        return [PSCustomObject]@{
            CPU     = @{
                Name              = $cpu.Name
                Cores             = $cpu.NumberOfCores
                LogicalProcessors = $cpu.NumberOfLogicalProcessors
                MaxClockSpeed     = $cpu.MaxClockSpeed
            }
            Memory  = @{
                TotalSlots    = $memory.Count
                TotalCapacity = [math]::Round(($memory | Measure-Object Capacity -Sum).Sum / 1GB, 2)
                Speed         = ($memory | Select-Object -First 1).Speed
            }
            Storage = $disks | ForEach-Object {
                @{
                    Drive      = $_.DeviceID
                    Label      = $_.VolumeName
                    Size       = [math]::Round($_.Size / 1GB, 2)
                    FreeSpace  = [math]::Round($_.FreeSpace / 1GB, 2)
                    FileSystem = $_.FileSystem
                }
            }
        }
    }
    catch {
        Write-Warning "Failed to get hardware info: $($_.Exception.Message)"
        return [PSCustomObject]@{ Error = $_.Exception.Message }
    }
}

<#
.SYNOPSIS
    Gets software information
#>
function Get-SoftwareInfo {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    try {
        # Get installed programs from registry
        $programs = @()
        $registryPaths = @(
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
        )

        foreach ($path in $registryPaths) {
            $programs += Get-ItemProperty $path -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -and $_.DisplayName.Trim() -ne '' } |
            Select-Object DisplayName, DisplayVersion, Publisher, InstallDate
        }

        # Get Windows features
        $features = Get-WindowsOptionalFeature -Online | Where-Object { $_.State -eq 'Enabled' }

        return [PSCustomObject]@{
            InstalledPrograms = $programs.Count
            RecentInstalls    = ($programs | Where-Object { $_.InstallDate -gt (Get-Date).AddDays(-30).ToString('yyyyMMdd') }).Count
            EnabledFeatures   = $features.Count
            TopPublishers     = $programs | Group-Object Publisher | Sort-Object Count -Descending | Select-Object -First 5 | ForEach-Object { @{ Publisher = $_.Name; Count = $_.Count } }
        }
    }
    catch {
        Write-Warning "Failed to get software info: $($_.Exception.Message)"
        return [PSCustomObject]@{ Error = $_.Exception.Message }
    }
}

<#
.SYNOPSIS
    Gets services information
#>
function Get-ServicesInfo {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    try {
        # Get services with permission handling - some services may be inaccessible
        $services = @()
        $accessibleServices = @()
        $deniedServices = @()
        
        try {
            # First try to get all services at once
            $allServices = Get-Service -ErrorAction SilentlyContinue
            if ($allServices) {
                $services = $allServices
            }
            else {
                # If that fails, get services individually and handle permission errors
                $serviceNames = Get-Service | Select-Object -ExpandProperty Name -ErrorAction SilentlyContinue
                foreach ($serviceName in $serviceNames) {
                    try {
                        $service = Get-Service -Name $serviceName -ErrorAction Stop
                        $accessibleServices += $service
                    }
                    catch [System.Security.SecurityException], [System.UnauthorizedAccessException] {
                        $deniedServices += $serviceName
                        # Silently skip permission denied services
                    }
                    catch {
                        # Skip other service errors
                    }
                }
                $services = $accessibleServices
            }
        }
        catch {
            # Fallback: try WMI if Get-Service fails entirely
            try {
                $services = Get-CimInstance -ClassName Win32_Service -ErrorAction SilentlyContinue | ForEach-Object {
                    [PSCustomObject]@{
                        Name      = $_.Name
                        Status    = if ($_.State -eq 'Running') { 'Running' } else { 'Stopped' }
                        StartType = switch ($_.StartMode) {
                            'Auto' { 'Automatic' }
                            'Manual' { 'Manual' }
                            'Disabled' { 'Disabled' }
                            default { 'Manual' }
                        }
                    }
                }
            }
            catch {
                Write-Warning "Failed to enumerate services via both Get-Service and WMI: $($_.Exception.Message)"
                return [PSCustomObject]@{ 
                    Error          = "Permission denied accessing service information"
                    DeniedServices = $deniedServices.Count
                }
            }
        }
        
        if ($deniedServices.Count -gt 0) {
            Write-Information "Note: $($deniedServices.Count) services were inaccessible due to permissions (e.g., McpManagementService)" -InformationAction Continue
        }
        
        return [PSCustomObject]@{
            Total              = $services.Count
            Running            = ($services | Where-Object { $_.Status -eq 'Running' }).Count
            Stopped            = ($services | Where-Object { $_.Status -eq 'Stopped' }).Count
            Automatic          = ($services | Where-Object { $_.StartType -eq 'Automatic' }).Count
            Manual             = ($services | Where-Object { $_.StartType -eq 'Manual' }).Count
            Disabled           = ($services | Where-Object { $_.StartType -eq 'Disabled' }).Count
            AccessibleServices = $services.Count
            DeniedServices     = $deniedServices.Count
        }
    }
    catch {
        Write-Warning "Failed to get services info: $($_.Exception.Message)"
        return [PSCustomObject]@{ Error = $_.Exception.Message }
    }
}

<#
.SYNOPSIS
    Gets network information
#>
function Get-NetworkInfo {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    try {
        $adapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' }
        $ipConfig = Get-NetIPConfiguration | Where-Object { $_.NetAdapter.Status -eq 'Up' }
        
        return [PSCustomObject]@{
            ActiveAdapters  = $adapters.Count
            NetworkProfiles = ($ipConfig | Group-Object NetProfile.Name).Count
            IPv4Addresses   = ($ipConfig | ForEach-Object { $_.IPv4Address.IPAddress } | Where-Object { $_ }).Count
            IPv6Addresses   = ($ipConfig | ForEach-Object { $_.IPv6Address.IPAddress } | Where-Object { $_ }).Count
            DNSServers      = ($ipConfig | ForEach-Object { $_.DNSServer.ServerAddresses } | Sort-Object -Unique).Count
        }
    }
    catch {
        Write-Warning "Failed to get network info: $($_.Exception.Message)"
        return [PSCustomObject]@{ Error = $_.Exception.Message }
    }
}

<#
.SYNOPSIS
    Gets security information
#>
function Get-SecurityInfo {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    try {
        # Get Windows Defender status
        $defenderStatus = $null
        try {
            $defenderStatus = Get-MpComputerStatus -ErrorAction SilentlyContinue
        }
        catch {}

        # Get UAC status
        $uacEnabled = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "EnableLUA" -ErrorAction SilentlyContinue).EnableLUA

        # Get firewall status
        $firewallProfiles = Get-NetFirewallProfile

        return [PSCustomObject]@{
            WindowsDefender = if ($defenderStatus) {
                @{
                    AntivirusEnabled          = $defenderStatus.AntivirusEnabled
                    RealTimeProtectionEnabled = $defenderStatus.RealTimeProtectionEnabled
                    LastFullScan              = $defenderStatus.FullScanAge
                    LastQuickScan             = $defenderStatus.QuickScanAge
                }
            }
            else { $null }
            UAC             = @{
                Enabled = $uacEnabled -eq 1
            }
            Firewall        = $firewallProfiles | ForEach-Object {
                @{
                    Profile = $_.Name
                    Enabled = $_.Enabled
                }
            }
        }
    }
    catch {
        Write-Warning "Failed to get security info: $($_.Exception.Message)"
        return [PSCustomObject]@{ Error = $_.Exception.Message }
    }
}

#endregion

#region Security Audit Functions

<#
.SYNOPSIS
    Performs comprehensive security audit

.DESCRIPTION
    Analyzes system security configuration, identifies vulnerabilities,
    and provides security recommendations for system hardening.

.PARAMETER IncludeNetworkScan
    Include network security analysis

.PARAMETER IncludeRegistryAudit
    Include registry security audit

.PARAMETER UseCache
    Use cached results if available

.EXAMPLE
    $audit = Get-SecurityAudit -IncludeNetworkScan
#>
function Get-SecurityAudit {
    [CmdletBinding()]
    param(
        [Parameter()]
        [switch]$IncludeNetworkScan,

        [Parameter()]
        [switch]$IncludeRegistryAudit,

        [Parameter()]
        [switch]$UseCache
    )

    Write-Information "🔒 Starting security audit..." -InformationAction Continue
    
    # Start performance tracking
    $perfContext = $null
    try {
        $perfContext = Start-PerformanceTracking -OperationName 'SecurityAudit' -Component 'SYSTEM-ANALYSIS'
        Write-LogEntry -Level 'INFO' -Component 'SYSTEM-ANALYSIS' -Message 'Starting comprehensive security audit' -Data @{
            IncludeNetworkScan   = $IncludeNetworkScan
            IncludeRegistryAudit = $IncludeRegistryAudit
        }
    }
    catch {
        Write-Information "Security audit started" -InformationAction Continue
    }

    try {
        # Check cache first if requested
        if ($UseCache) {
            $cacheFile = Get-SessionPath -Category 'data' -FileName 'security-audit.json'
            if ($cacheFile -and (Test-Path $cacheFile)) {
                $cacheAge = (Get-Date) - (Get-Item $cacheFile).LastWriteTime
                if ($cacheAge.TotalMinutes -le 15) {
                    Write-Information "Using cached security audit data" -InformationAction Continue
                    return Get-SessionData -Category 'data' -FileName 'security-audit.json'
                }
            }
        }

        # Perform security audit
        $auditResults = @{
            AuditTimestamp   = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            SystemSecurity   = Get-SystemSecurityAudit
            UserSecurity     = Get-UserSecurityAudit
            NetworkSecurity  = if ($IncludeNetworkScan) { Get-NetworkSecurityAudit } else { $null }
            RegistrySecurity = if ($IncludeRegistryAudit) { Get-RegistrySecurityAudit } else { $null }
            SecurityScore    = 0
            Recommendations  = @()
        }

        # Calculate security score
        $auditResults.SecurityScore = Get-SecurityScore -AuditResults $auditResults
        $auditResults.Recommendations = New-SecurityRecommendations -AuditResults $auditResults

        Write-Information "✓ Security audit completed. Score: $($auditResults.SecurityScore)/100" -InformationAction Continue

        # Save results to session data
        try {
            Save-SessionData -Category 'data' -Data $auditResults -FileName 'security-audit.json'
        }
        catch {
            Write-Warning "Failed to save audit results: $($_.Exception.Message)"
        }

        # Complete performance tracking
        try {
            Complete-PerformanceTracking -Context $perfContext -Status 'Success'
        }
        catch {}

        return [PSCustomObject]$auditResults

    }
    catch {
        $errorMsg = "Security audit failed: $($_.Exception.Message)"
        Write-Error $errorMsg
        
        try {
            Write-LogEntry -Level 'ERROR' -Component 'SYSTEM-ANALYSIS' -Message $errorMsg -Data @{ Error = $_.Exception }
            Complete-PerformanceTracking -Context $perfContext -Status 'Failed' -ErrorMessage $errorMsg
        }
        catch {}
        
        throw
    }
}

<#
.SYNOPSIS
    Gets system security audit results
#>
function Get-SystemSecurityAudit {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    try {
        $issues = @()

        # Check Windows Defender
        try {
            $defenderStatus = Get-MpComputerStatus -ErrorAction SilentlyContinue
            if (-not $defenderStatus.AntivirusEnabled) {
                $issues += [PSCustomObject]@{
                    Category       = 'Antivirus'
                    Severity       = 'High'
                    Issue          = 'Windows Defender antivirus is disabled'
                    Recommendation = 'Enable Windows Defender or install alternative antivirus'
                }
            }
        }
        catch {}

        # Check UAC
        $uacEnabled = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "EnableLUA" -ErrorAction SilentlyContinue).EnableLUA
        if ($uacEnabled -ne 1) {
            $issues += [PSCustomObject]@{
                Category       = 'AccessControl'
                Severity       = 'High'
                Issue          = 'User Account Control (UAC) is disabled'
                Recommendation = 'Enable UAC for better security'
            }
        }

        # Check automatic updates
        $auOptions = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update" -Name "AUOptions" -ErrorAction SilentlyContinue).AUOptions
        if ($auOptions -eq 1) {
            $issues += [PSCustomObject]@{
                Category       = 'Updates'
                Severity       = 'Medium'
                Issue          = 'Automatic updates are disabled'
                Recommendation = 'Enable automatic updates for security patches'
            }
        }

        return [PSCustomObject]@{
            IssuesFound    = $issues.Count
            HighSeverity   = ($issues | Where-Object { $_.Severity -eq 'High' }).Count
            MediumSeverity = ($issues | Where-Object { $_.Severity -eq 'Medium' }).Count
            Issues         = $issues
        }
    }
    catch {
        Write-Warning "Failed to perform system security audit: $($_.Exception.Message)"
        return [PSCustomObject]@{ Error = $_.Exception.Message }
    }
}

<#
.SYNOPSIS
    Gets user security audit results
#>
function Get-UserSecurityAudit {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    try {
        $issues = @()

        # Check for users with blank passwords
        $users = Get-LocalUser | Where-Object { $_.Enabled -eq $true }
        foreach ($user in $users) {
            # This is a simplified check - in practice, you'd need more sophisticated password policy checking
            if ($null -eq $user.PasswordExpires -and $user.Name -ne 'DefaultAccount') {
                $issues += [PSCustomObject]@{
                    Category       = 'PasswordPolicy'
                    Severity       = 'Medium'
                    Issue          = "User '$($user.Name)' may have weak password policy"
                    Recommendation = 'Review and strengthen password policies'
                }
            }
        }

        # Check for administrator accounts
        $adminUsers = Get-LocalGroupMember -Group "Administrators" -ErrorAction SilentlyContinue
        if ($adminUsers.Count -gt 2) {
            $issues += [PSCustomObject]@{
                Category       = 'AccessControl'
                Severity       = 'Medium'
                Issue          = "Multiple administrator accounts detected ($($adminUsers.Count))"
                Recommendation = 'Review administrator access and remove unnecessary admin privileges'
            }
        }

        return [PSCustomObject]@{
            IssuesFound = $issues.Count
            ActiveUsers = $users.Count
            AdminUsers  = $adminUsers.Count
            Issues      = $issues
        }
    }
    catch {
        Write-Warning "Failed to perform user security audit: $($_.Exception.Message)"
        return [PSCustomObject]@{ Error = $_.Exception.Message }
    }
}

<#
.SYNOPSIS
    Gets network security audit results
#>
function Get-NetworkSecurityAudit {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    try {
        $issues = @()

        # Check firewall status
        $firewallProfiles = Get-NetFirewallProfile
        foreach ($firewallProfile in $firewallProfiles) {
            if (-not $firewallProfile.Enabled) {
                $issues += [PSCustomObject]@{
                    Category       = 'Firewall'
                    Severity       = 'High'
                    Issue          = "Windows Firewall is disabled for $($firewallProfile.Name) profile"
                    Recommendation = 'Enable Windows Firewall for all network profiles'
                }
            }
        }

        # Check for open ports
        $openPorts = Get-NetTCPConnection | Where-Object { $_.State -eq 'Listen' -and $_.LocalAddress -eq '0.0.0.0' }
        if ($openPorts.Count -gt 10) {
            $issues += [PSCustomObject]@{
                Category       = 'Network'
                Severity       = 'Medium'
                Issue          = "Multiple services listening on all interfaces ($($openPorts.Count) ports)"
                Recommendation = 'Review and restrict network service exposure'
            }
        }

        return [PSCustomObject]@{
            IssuesFound      = $issues.Count
            FirewallProfiles = $firewallProfiles.Count
            OpenPorts        = $openPorts.Count
            Issues           = $issues
        }
    }
    catch {
        Write-Warning "Failed to perform network security audit: $($_.Exception.Message)"
        return [PSCustomObject]@{ Error = $_.Exception.Message }
    }
}

<#
.SYNOPSIS
    Gets registry security audit results
#>
function Get-RegistrySecurityAudit {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    try {
        $issues = @()

        # Check for dangerous registry settings
        $dangerousSettings = @{
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\EnableLUA'                  = @{ ExpectedValue = 1; Description = 'UAC enabled' }
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\ConsentPromptBehaviorAdmin' = @{ ExpectedValue = 2; Description = 'UAC prompt for administrators' }
        }

        foreach ($setting in $dangerousSettings.Keys) {
            $pathParts = $setting.Split('\')
            $valueName = $pathParts[-1]
            $keyPath = ($pathParts[0..($pathParts.Length - 2)]) -join '\'
            
            try {
                $currentValue = (Get-ItemProperty -Path $keyPath -Name $valueName -ErrorAction SilentlyContinue).$valueName
                $expectedValue = $dangerousSettings[$setting].ExpectedValue
                
                if ($currentValue -ne $expectedValue) {
                    $issues += [PSCustomObject]@{
                        Category       = 'Registry'
                        Severity       = 'Medium'
                        Issue          = "Insecure registry setting: $($dangerousSettings[$setting].Description)"
                        Recommendation = "Set $setting to $expectedValue"
                    }
                }
            }
            catch {}
        }

        return [PSCustomObject]@{
            IssuesFound     = $issues.Count
            SettingsChecked = $dangerousSettings.Count
            Issues          = $issues
        }
    }
    catch {
        Write-Warning "Failed to perform registry security audit: $($_.Exception.Message)"
        return [PSCustomObject]@{ Error = $_.Exception.Message }
    }
}

<#
.SYNOPSIS
    Calculates overall security score
#>
function Get-SecurityScore {
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$AuditResults
    )

    $baseScore = 100
    $deductions = 0

    # Collect all issues
    $allIssues = @()
    if ($AuditResults.SystemSecurity.Issues) { $allIssues += $AuditResults.SystemSecurity.Issues }
    if ($AuditResults.UserSecurity.Issues) { $allIssues += $AuditResults.UserSecurity.Issues }
    if ($AuditResults.NetworkSecurity.Issues) { $allIssues += $AuditResults.NetworkSecurity.Issues }
    if ($AuditResults.RegistrySecurity.Issues) { $allIssues += $AuditResults.RegistrySecurity.Issues }

    # Deduct points based on severity
    foreach ($issue in $allIssues) {
        switch ($issue.Severity) {
            'High' { $deductions += 20 }
            'Medium' { $deductions += 10 }
            'Low' { $deductions += 5 }
        }
    }

    return [math]::Max(0, $baseScore - $deductions)
}

<#
.SYNOPSIS
    Generates security recommendations
#>
function New-SecurityRecommendations {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$AuditResults
    )

    $recommendations = @()

    # Collect all issues
    $allIssues = @()
    if ($AuditResults.SystemSecurity.Issues) { $allIssues += $AuditResults.SystemSecurity.Issues }
    if ($AuditResults.UserSecurity.Issues) { $allIssues += $AuditResults.UserSecurity.Issues }
    if ($AuditResults.NetworkSecurity.Issues) { $allIssues += $AuditResults.NetworkSecurity.Issues }
    if ($AuditResults.RegistrySecurity.Issues) { $allIssues += $AuditResults.RegistrySecurity.Issues }

    $highIssues = $allIssues | Where-Object { $_.Severity -eq 'High' }
    $mediumIssues = $allIssues | Where-Object { $_.Severity -eq 'Medium' }

    if ($highIssues.Count -gt 0) {
        $recommendations += "🔴 Critical: Address $($highIssues.Count) high-severity security issues immediately"
    }

    if ($mediumIssues.Count -gt 0) {
        $recommendations += "🟡 Important: Review $($mediumIssues.Count) medium-severity security concerns"
    }

    if ($allIssues.Count -eq 0) {
        $recommendations += "✅ Excellent! No major security issues detected"
    }

    return $recommendations
}

#endregion

# Helper functions for detailed information (simplified versions)
function Get-DetailedHardwareInfo { return @{} }
function Get-DetailedSoftwareInfo { return @{} }

# Export all public functions
Export-ModuleMember -Function @(
    # System Inventory
    'Get-SystemInventory',
    'Get-BasicSystemInfo',
    'Get-HardwareInfo',
    'Get-SoftwareInfo',
    'Get-ServicesInfo',
    'Get-NetworkInfo',
    'Get-SecurityInfo',
    
    # Security Audit
    'Get-SecurityAudit',
    'Get-SystemSecurityAudit',
    'Get-UserSecurityAudit',
    'Get-NetworkSecurityAudit',
    'Get-RegistrySecurityAudit'
)