<#
.MODULEINFO
Type = "Type1"
Category = "Security"
MenuText = "Security Posture Assessment"
Description = "Audits Windows security configuration and provides security recommendations"
DataFile = "security-inventory.json"
ScanInterval = 3600
DependsOn = @("Infrastructure")
#>

<#
.SYNOPSIS
    Security Inventory Module v3.0 - Type 1 (Read-Only)

.DESCRIPTION
    Comprehensive security assessment scanner that audits:
    - Windows Defender status and configuration
    - Windows Firewall status
    - User Account Control (UAC) settings
    - Security-critical services
    - User accounts and administrator groups
    - Security policies and settings

.NOTES
    Author: Windows Maintenance Automation Project
    Version: 3.0.0
    Module Type: Type1 (Read-Only)
    Requires: PowerShell 7.0+, Administrator privileges
    Dependencies: Infrastructure.psm1
#>

#Requires -Version 7.0
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Gets security posture inventory.

.DESCRIPTION
    Performs comprehensive security audit of Windows configuration.

.PARAMETER ForceRefresh
    Force a fresh scan even if cached data exists.

.OUTPUTS
    PSCustomObject containing security inventory.

.EXAMPLE
    Get-SecurityInventory
    
.EXAMPLE
    Get-SecurityInventory -ForceRefresh
#>
function Get-SecurityInventory {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $false)]
        [switch]$ForceRefresh
    )
    
    $perf = Start-PerformanceTracking -OperationName 'SecurityInventoryScan' -Component 'Security'
    
    try {
        Write-DetailedLog -Level 'INFO' -Component 'Security' -Message 'Starting security inventory scan'
        
        # Check for cached data (unless ForceRefresh specified)
        if (-not $ForceRefresh) {
            Write-DetailedLog -Level 'INFO' -Component 'Security' -Message 'Checking for cached security inventory'
            
            $cachedData = Import-InventoryFile -Category 'Security'
            
            if ($cachedData -and $cachedData.metadata -and $cachedData.metadata.scanDate) {
                $scanDate = [datetime]::Parse($cachedData.metadata.scanDate)
                $age = (Get-Date) - $scanDate
                $cacheExpiration = Get-ConfigValue -Path 'inventory.cacheExpirationMinutes' -Default 60
                
                if ($age.TotalMinutes -lt $cacheExpiration) {
                    Write-DetailedLog -Level 'INFO' -Component 'Security' -Message "Using cached data (age: $([math]::Round($age.TotalMinutes, 1)) minutes)"
                    Write-Information "ℹ️  Using cached security data (scanned $([math]::Round($age.TotalMinutes, 1)) minutes ago)" -InformationAction Continue
                    Complete-PerformanceTracking -PerformanceContext $perf -Success $true
                    return $cachedData
                }
            }
        }
        
        Write-Information "🔍 Scanning security posture..." -InformationAction Continue
        
        # Initialize inventory structure
        $inventory = @{
            metadata        = @{
                scanDate      = (Get-Date).ToString('o')
                computerName  = $env:COMPUTERNAME
                scanDuration  = 0
                moduleVersion = '3.0.0'
            }
            
            windowsDefender = @{
                isEnabled            = $false
                realTimeProtection   = $false
                definitionsUpToDate  = $false
                lastScan             = $null
                lastDefinitionUpdate = $null
            }
            
            firewall        = @{
                domainProfile  = $null
                privateProfile = $null
                publicProfile  = $null
            }
            
            uac             = @{
                enabled = $false
                level   = 'Unknown'
            }
            
            services        = @()
            
            userAccounts    = @{
                totalUsers         = 0
                administratorCount = 0
                disabledCount      = 0
                accounts           = @()
            }
            
            statistics      = @{
                securityScore  = 100
                criticalIssues = 0
                warnings       = 0
                defenderIssues = 0
                firewallIssues = 0
                uacIssues      = 0
            }
            
            recommendations = @()
        }
        
        # Step 1: Check Windows Defender status
        Write-DetailedLog -Level 'INFO' -Component 'Security' -Message 'Auditing Windows Defender'
        Write-Information "  🛡️  Checking Windows Defender..." -InformationAction Continue
        
        try {
            $defenderStatus = Get-MpComputerStatus -ErrorAction Stop
            
            $inventory.windowsDefender.isEnabled = $defenderStatus.AntivirusEnabled
            $inventory.windowsDefender.realTimeProtection = $defenderStatus.RealTimeProtectionEnabled
            $inventory.windowsDefender.definitionsUpToDate = -not $defenderStatus.AntivirusSignatureOutOfDate
            $inventory.windowsDefender.lastScan = $defenderStatus.FullScanEndTime
            $inventory.windowsDefender.lastDefinitionUpdate = $defenderStatus.AntivirusSignatureLastUpdated
            
            # Track issues
            if (-not $defenderStatus.AntivirusEnabled) {
                $inventory.statistics.defenderIssues++
                $inventory.statistics.criticalIssues++
            }
            if (-not $defenderStatus.RealTimeProtectionEnabled) {
                $inventory.statistics.defenderIssues++
                $inventory.statistics.criticalIssues++
            }
            if ($defenderStatus.AntivirusSignatureOutOfDate) {
                $inventory.statistics.defenderIssues++
                $inventory.statistics.warnings++
            }
        }
        catch {
            Write-Verbose "Error checking Windows Defender: $_"
            $inventory.statistics.criticalIssues++
        }
        
        # Step 2: Check Windows Firewall
        Write-DetailedLog -Level 'INFO' -Component 'Security' -Message 'Auditing Windows Firewall'
        Write-Information "  🔥 Checking Windows Firewall..." -InformationAction Continue
        
        try {
            $firewallProfiles = Get-NetFirewallProfile -ErrorAction Stop
            
            foreach ($firewallProfileItem in $firewallProfiles) {
                $profileData = @{
                    Name    = $firewallProfileItem.Name
                    Enabled = $firewallProfileItem.Enabled
                    Status  = if ($firewallProfileItem.Enabled) { 'Enabled' } else { 'Disabled' }
                }
                
                switch ($firewallProfileItem.Name) {
                    'Domain' { $inventory.firewall.domainProfile = $profileData }
                    'Private' { $inventory.firewall.privateProfile = $profileData }
                    'Public' { $inventory.firewall.publicProfile = $profileData }
                }
                
                # Track firewall issues
                if (-not $fwProfile.Enabled) {
                    $inventory.statistics.firewallIssues++
                    $inventory.statistics.criticalIssues++
                }
            }
        }
        catch {
            Write-Verbose "Error checking Windows Firewall: $_"
            $inventory.statistics.criticalIssues++
        }
        
        # Step 3: Check UAC settings
        Write-DetailedLog -Level 'INFO' -Component 'Security' -Message 'Auditing UAC settings'
        Write-Information "  🔐 Checking UAC settings..." -InformationAction Continue
        
        try {
            $uacPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
            $uacValue = (Get-ItemProperty -Path $uacPath -Name 'EnableLUA' -ErrorAction Stop).EnableLUA
            
            $inventory.uac.enabled = ($uacValue -eq 1)
            
            $promptBehavior = (Get-ItemProperty -Path $uacPath -Name 'ConsentPromptBehaviorAdmin' -ErrorAction SilentlyContinue).ConsentPromptBehaviorAdmin
            $inventory.uac.level = switch ($promptBehavior) {
                0 { 'Never notify' }
                1 { 'Notify without secure desktop' }
                2 { 'Always notify' }
                5 { 'Default - Notify on change' }
                default { 'Unknown' }
            }
            
            # Track UAC issues
            if (-not $inventory.uac.enabled) {
                $inventory.statistics.uacIssues++
                $inventory.statistics.criticalIssues++
            }
            elseif ($promptBehavior -eq 0) {
                $inventory.statistics.uacIssues++
                $inventory.statistics.warnings++
            }
        }
        catch {
            Write-Verbose "Error checking UAC: $_"
            $inventory.statistics.warnings++
        }
        
        # Step 4: Check security-critical services
        Write-DetailedLog -Level 'INFO' -Component 'Security' -Message 'Auditing security services'
        Write-Information "  🔧 Checking security services..." -InformationAction Continue
        
        $securityServices = @(
            'WinDefend',     # Windows Defender Antivirus Service
            'WdNisSvc',      # Windows Defender Network Inspection Service
            'mpssvc',        # Windows Firewall
            'wscsvc',        # Security Center
            'EventLog'       # Windows Event Log
        )
        
        foreach ($svcName in $securityServices) {
            try {
                $service = Get-Service -Name $svcName -ErrorAction SilentlyContinue
                
                if ($service) {
                    $inventory.services += @{
                        Name        = $service.Name
                        DisplayName = $service.DisplayName
                        Status      = $service.Status.ToString()
                        StartType   = $service.StartType.ToString()
                        IsHealthy   = ($service.Status -eq 'Running')
                    }
                    
                    # Track service issues
                    if ($service.Status -ne 'Running' -and $service.StartType -ne 'Disabled') {
                        $inventory.statistics.criticalIssues++
                    }
                }
            }
            catch {
                Write-Verbose "Error checking service $svcName : $_"
            }
        }
        
        # Step 5: Audit user accounts
        Write-DetailedLog -Level 'INFO' -Component 'Security' -Message 'Auditing user accounts'
        Write-Information "  👤 Auditing user accounts..." -InformationAction Continue
        
        try {
            $users = Get-LocalUser -ErrorAction Stop
            $administrators = Get-LocalGroupMember -Group 'Administrators' -ErrorAction Stop
            
            $inventory.userAccounts.totalUsers = $users.Count
            $inventory.userAccounts.administratorCount = $administrators.Count
            $inventory.userAccounts.disabledCount = ($users | Where-Object { -not $_.Enabled }).Count
            
            foreach ($user in $users) {
                $isAdmin = $administrators.Name -contains $user.Name
                
                $inventory.userAccounts.accounts += @{
                    Name            = $user.Name
                    Enabled         = $user.Enabled
                    IsAdmin         = $isAdmin
                    PasswordExpires = $user.PasswordExpires
                    LastLogon       = $user.LastLogon
                }
            }
            
            # Warn if too many administrators
            if ($administrators.Count -gt 2) {
                $inventory.statistics.warnings++
            }
        }
        catch {
            Write-Verbose "Error auditing user accounts: $_"
        }
        
        # Step 6: Calculate security score
        Write-DetailedLog -Level 'INFO' -Component 'Security' -Message 'Calculating security score'
        
        $securityScore = 100
        
        # Major deductions for critical issues
        $securityScore -= ($inventory.statistics.defenderIssues * 15)
        $securityScore -= ($inventory.statistics.firewallIssues * 15)
        $securityScore -= ($inventory.statistics.uacIssues * 10)
        
        # Minor deductions for warnings
        $securityScore -= ($inventory.statistics.warnings * 5)
        
        $inventory.statistics.securityScore = [math]::Max(0, $securityScore)
        
        # Step 7: Generate recommendations
        Write-DetailedLog -Level 'INFO' -Component 'Security' -Message 'Generating security recommendations'
        $inventory.recommendations = Get-SecurityRecommendation -Inventory $inventory
        
        # Update scan duration
        $inventory.metadata.scanDuration = $perf.StartTime ? ((Get-Date) - $perf.StartTime).TotalSeconds : 0
        
        # Save inventory
        Write-DetailedLog -Level 'INFO' -Component 'Security' -Message 'Saving security inventory'
        Save-InventoryFile -Category 'Security' -Data $inventory
        
        # Display summary
        Write-Information "`n  🔒 Security Assessment Summary:" -InformationAction Continue
        Write-Information "    Security Score: $($inventory.statistics.securityScore)/100" -InformationAction Continue
        Write-Information "    Windows Defender: $(if ($inventory.windowsDefender.isEnabled -and $inventory.windowsDefender.realTimeProtection) { '✓ Protected' } else { '❌ Issues Found' })" -InformationAction Continue
        Write-Information "    Windows Firewall: $(if ($inventory.statistics.firewallIssues -eq 0) { '✓ Enabled' } else { '❌ Issues Found' })" -InformationAction Continue
        Write-Information "    UAC: $(if ($inventory.uac.enabled) { '✓ Enabled' } else { '❌ Disabled' })" -InformationAction Continue
        Write-Information "    Critical Issues: $($inventory.statistics.criticalIssues), Warnings: $($inventory.statistics.warnings)" -InformationAction Continue
        Write-Information "" -InformationAction Continue
        
        Write-DetailedLog -Level 'SUCCESS' -Component 'Security' -Message "Security inventory scan completed: Security Score $($inventory.statistics.securityScore)"
        
        Complete-PerformanceTracking -PerformanceContext $perf -Success $true -ResultData @{
            SecurityScore  = $inventory.statistics.securityScore
            CriticalIssues = $inventory.statistics.criticalIssues
            Warnings       = $inventory.statistics.warnings
        }
        
        return $inventory
    }
    catch {
        Write-DetailedLog -Level 'ERROR' -Component 'Security' -Message "Security inventory scan failed: $_" -Exception $_
        Write-Information "`n❌ Security inventory scan failed: $_" -InformationAction Continue
        Complete-PerformanceTracking -PerformanceContext $perf -Success $false
        return $null
    }
}

<#
.SYNOPSIS
    Generates security recommendations.

.DESCRIPTION
    Analyzes inventory and provides actionable security recommendations.

.PARAMETER Inventory
    Security inventory data.

.OUTPUTS
    Array of recommendations.
#>
function Get-SecurityRecommendation {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Inventory
    )
    
    $recommendations = @()
    
    # Windows Defender issues
    if (-not $Inventory.windowsDefender.isEnabled) {
        $recommendations += @{
            Priority = 'Critical'
            Category = 'WindowsDefender'
            Issue    = 'Windows Defender is disabled'
            Action   = 'Enable Windows Defender antivirus protection'
            Impact   = 'Critical protection against malware and threats'
        }
    }
    
    if (-not $Inventory.windowsDefender.realTimeProtection) {
        $recommendations += @{
            Priority = 'Critical'
            Category = 'WindowsDefender'
            Issue    = 'Real-time protection is disabled'
            Action   = 'Enable real-time protection in Windows Defender'
            Impact   = 'Provides continuous threat monitoring'
        }
    }
    
    if (-not $Inventory.windowsDefender.definitionsUpToDate) {
        $recommendations += @{
            Priority = 'High'
            Category = 'WindowsDefender'
            Issue    = 'Virus definitions are out of date'
            Action   = 'Update Windows Defender definitions'
            Impact   = 'Ensures protection against latest threats'
        }
    }
    
    # Firewall issues
    foreach ($profileName in @('domainProfile', 'privateProfile', 'publicProfile')) {
        $firewallProfile = $Inventory.firewall[$profileName]
        if ($firewallProfile -and -not $firewallProfile.Enabled) {
            $recommendations += @{
                Priority = 'Critical'
                Category = 'Firewall'
                Issue    = "$($firewallProfile.Name) firewall profile is disabled"
                Action   = "Enable $($fwProfile.Name) firewall profile"
                Impact   = 'Protects against network-based attacks'
            }
        }
    }
    
    # UAC issues
    if (-not $Inventory.uac.enabled) {
        $recommendations += @{
            Priority = 'Critical'
            Category = 'UAC'
            Issue    = 'User Account Control is disabled'
            Action   = 'Enable UAC for security'
            Impact   = 'Prevents unauthorized system changes'
        }
    }
    elseif ($Inventory.uac.level -eq 'Never notify') {
        $recommendations += @{
            Priority = 'High'
            Category = 'UAC'
            Issue    = 'UAC is set to never notify'
            Action   = 'Increase UAC notification level'
            Impact   = 'Improves security awareness'
        }
    }
    
    # Too many administrators
    if ($Inventory.userAccounts.administratorCount -gt 2) {
        $recommendations += @{
            Priority = 'Medium'
            Category = 'UserAccounts'
            Issue    = "$($Inventory.userAccounts.administratorCount) administrator accounts detected"
            Action   = 'Reduce number of administrator accounts'
            Impact   = 'Reduces attack surface'
        }
    }
    
    # Stopped security services
    $stoppedServices = $Inventory.services | Where-Object { -not $_.IsHealthy -and $_.StartType -ne 'Disabled' }
    if ($stoppedServices.Count -gt 0) {
        $recommendations += @{
            Priority = 'Critical'
            Category = 'Services'
            Issue    = "$($stoppedServices.Count) security services are not running"
            Action   = 'Start critical security services'
            Impact   = 'Ensures security protection is active'
        }
    }
    
    return $recommendations
}

# Export public functions
Export-ModuleMember -Function @(
    'Get-SecurityInventory'
)
