#Requires -Version 7.0

<#
.SYNOPSIS
    Security Enhancement Module - Type 2 (System Modification)

.DESCRIPTION
    Performs security enhancements based on audit findings from SecurityAudit module.
    Implements security best practices, hardens system configuration, and applies
    security policies defined in security-config.json.

.NOTES
    Module Type: Type 2 (System Modification)
    Dependencies: SecurityAudit.psm1 (Type1), CoreInfrastructure.psm1
    Architecture: v3.0 - Self-contained with Type1 dependency
    Author: Windows Maintenance Automation Project
    Version: 1.0.0
    Created: November 30, 2025
#>

using namespace System.Collections.Generic

#region Module Dependencies and Initialization

# v3.0 Self-contained Type2 module with Type1 dependency
$ModuleRoot = Split-Path -Parent $PSScriptRoot

# Import CoreInfrastructure (loaded by orchestrator)
$CoreInfraPath = Join-Path $ModuleRoot 'core\CoreInfrastructure.psm1'
if (-not (Get-Command 'Write-LogEntry' -ErrorAction SilentlyContinue)) {
    if (Test-Path $CoreInfraPath) {
        Import-Module $CoreInfraPath -Force -Global
    }
}

# Import Type1 dependency: SecurityAudit
$SecurityAuditPath = Join-Path $ModuleRoot 'type1\SecurityAudit.psm1'
if (Test-Path $SecurityAuditPath) {
    Import-Module $SecurityAuditPath -Force
    Write-Verbose "SecurityAudit module imported successfully"
}
else {
    throw "SecurityAudit.psm1 not found - required dependency missing"
}

# Validate Type1 module loaded correctly
if (-not (Get-Command -Name 'Get-SecurityAuditAnalysis' -ErrorAction SilentlyContinue)) {
    throw "Type 1 module functions not available - ensure SecurityAudit.psm1 is properly imported"
}

#endregion

#region v3.0 Standardized Execution Function

<#
.SYNOPSIS
    Main execution function for security enhancements - v3.0 Architecture Pattern

.DESCRIPTION
    Standardized entry point that implements the Type2 → Type1 flow:
    1. Loads security configuration from security-config.json
    2. Calls SecurityAudit (Type1) to analyze current security posture
    3. Validates findings and logs results
    4. Executes security enhancement actions based on DryRun mode
    5. Returns standardized results for ReportGeneration

.PARAMETER Config
    Main configuration object from orchestrator

.PARAMETER DryRun
    If specified, simulates changes without modifying the system

.EXAMPLE
    Invoke-SecurityEnhancement -Config $MainConfig

.EXAMPLE
    Invoke-SecurityEnhancement -Config $MainConfig -DryRun

.OUTPUTS
    PSCustomObject with standardized result structure:
    - Success: Boolean indicating overall success
    - ItemsDetected: Number of security issues found
    - ItemsProcessed: Number of enhancements applied
    - DryRun: Boolean indicating if this was a dry run
    - Results: Detailed results array
#>
function Invoke-SecurityEnhancement {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Config,
        
        [Parameter()]
        [switch]$DryRun
    )
    
    $perfContext = $null
    try { 
        $perfContext = Start-PerformanceTracking -OperationName 'SecurityEnhancement' -Component 'SECURITY-ENHANCEMENT'
    } 
    catch { 
        Write-Verbose "Performance tracking not available: $($_.Exception.Message)"
    }
    
    try {
        # Track execution duration
        $executionStartTime = Get-Date
        
        Write-Information "🔒 Security Enhancement Module v3.0" -InformationAction Continue
        Write-Information "   Type: Type 2 (System Modification)" -InformationAction Continue
        Write-Information "   Mode: $(if ($DryRun) { 'DRY-RUN (Simulation)' } else { 'LIVE EXECUTION' })" -InformationAction Continue
        Write-Information "" -InformationAction Continue
        
        # Step 1: Load security configuration
        Write-Information "📋 Step 1: Loading security configuration..." -InformationAction Continue
        $securityConfig = Get-SecurityConfiguration -ErrorAction Stop
        
        if ($securityConfig) {
            Write-Information "   ✅ Security configuration loaded successfully" -InformationAction Continue
            Write-Information "   • CIS Baseline: $($securityConfig.compliance.enableCISBaseline)" -InformationAction Continue
            Write-Information "   • Digital Signature Verification: $($securityConfig.security.enableDigitalSignatureVerification)" -InformationAction Continue
            Write-Information "   • Malware Scanning: $($securityConfig.security.enableMalwareScan)" -InformationAction Continue
        }
        else {
            Write-Warning "   Security configuration not found - using default policies"
            $securityConfig = Get-DefaultSecurityConfiguration
        }
        
        # Step 2: Call Type1 module for security audit
        Write-Information "" -InformationAction Continue
        Write-Information "🔍 Step 2: Analyzing current security posture..." -InformationAction Continue
        
        # Explicit assignment to prevent pipeline contamination
        $auditResults = $null
        $auditResults = Get-SecurityAuditAnalysis -Config $Config
        
        if (-not $auditResults) {
            throw "SecurityAudit returned no results"
        }
        
        # Extract metrics from audit
        $issuesDetected = 0
        if ($auditResults.Issues) {
            $issuesDetected = $auditResults.Issues.Count
        }
        elseif ($auditResults.TotalIssues) {
            $issuesDetected = $auditResults.TotalIssues
        }
        
        Write-Information "   ✅ Security audit completed" -InformationAction Continue
        Write-Information "   • Security issues detected: $issuesDetected" -InformationAction Continue
        
        # Step 3: Apply security enhancements
        Write-Information "" -InformationAction Continue
        Write-Information "🛡️ Step 3: Applying security enhancements..." -InformationAction Continue
        
        $enhancementResults = @{
            WindowsDefender    = $null
            Firewall           = $null
            UserAccountControl = $null
            ExecutionPolicy    = $null
            AuditPolicies      = $null
            NetworkSecurity    = $null
        }
        
        $itemsProcessed = 0
        
        # Apply Windows Defender enhancements
        if ($securityConfig.security.enableRealTimeProtection) {
            Write-Information "   🛡️ Configuring Windows Defender..." -InformationAction Continue
            $enhancementResults.WindowsDefender = Set-WindowsDefenderConfiguration -Config $securityConfig -DryRun:$DryRun
            if ($enhancementResults.WindowsDefender.Success) {
                $itemsProcessed += $enhancementResults.WindowsDefender.ItemsProcessed
            }
        }
        
        # Configure Firewall
        Write-Information "   🔥 Verifying Windows Firewall..." -InformationAction Continue
        $enhancementResults.Firewall = Set-FirewallConfiguration -Config $securityConfig -DryRun:$DryRun
        if ($enhancementResults.Firewall.Success) {
            $itemsProcessed += $enhancementResults.Firewall.ItemsProcessed
        }
        
        # Configure UAC
        Write-Information "   🔐 Configuring User Account Control..." -InformationAction Continue
        $enhancementResults.UserAccountControl = Set-UACConfiguration -Config $securityConfig -DryRun:$DryRun
        if ($enhancementResults.UserAccountControl.Success) {
            $itemsProcessed += $enhancementResults.UserAccountControl.ItemsProcessed
        }
        
        # Set PowerShell Execution Policy
        if ($securityConfig.compliance.enforceExecutionPolicy) {
            Write-Information "   📜 Setting PowerShell Execution Policy..." -InformationAction Continue
            $enhancementResults.ExecutionPolicy = Set-PowerShellExecutionPolicy -Config $securityConfig -DryRun:$DryRun
            if ($enhancementResults.ExecutionPolicy.Success) {
                $itemsProcessed += $enhancementResults.ExecutionPolicy.ItemsProcessed
            }
        }
        
        # Configure Audit Policies
        if ($securityConfig.security.enableAuditLogging) {
            Write-Information "   📋 Configuring system audit policies..." -InformationAction Continue
            $enhancementResults.AuditPolicies = Set-SystemAuditPolicies -Config $securityConfig -DryRun:$DryRun
            if ($enhancementResults.AuditPolicies.Success) {
                $itemsProcessed += $enhancementResults.AuditPolicies.ItemsProcessed
            }
        }
        
        # Network Security
        Write-Information "   🌐 Applying network security settings..." -InformationAction Continue
        $enhancementResults.NetworkSecurity = Set-NetworkSecurityConfiguration -Config $securityConfig -DryRun:$DryRun
        if ($enhancementResults.NetworkSecurity.Success) {
            $itemsProcessed += $enhancementResults.NetworkSecurity.ItemsProcessed
        }
        
        # Calculate execution duration
        $executionDuration = ((Get-Date) - $executionStartTime).TotalSeconds
        
        Write-Information "" -InformationAction Continue
        Write-Information "✅ Security enhancement completed" -InformationAction Continue
        Write-Information "   • Security issues detected: $issuesDetected" -InformationAction Continue
        Write-Information "   • Enhancements applied: $itemsProcessed" -InformationAction Continue
        Write-Information "   • Execution time: $([math]::Round($executionDuration, 2)) seconds" -InformationAction Continue
        
        # Return standardized v3.0 result structure
        return [PSCustomObject]@{
            Success            = $true
            ItemsDetected      = $issuesDetected
            ItemsProcessed     = $itemsProcessed
            DryRun             = $DryRun.IsPresent
            ExecutionTime      = $executionDuration
            AuditResults       = $auditResults
            EnhancementResults = $enhancementResults
            Message            = "Security enhancements completed successfully"
        }
    }
    catch {
        Write-LogEntry -Level 'ERROR' -Component 'SECURITY-ENHANCEMENT' -Message "Security enhancement failed: $($_.Exception.Message)"
        
        return [PSCustomObject]@{
            Success        = $false
            ItemsDetected  = 0
            ItemsProcessed = 0
            DryRun         = $DryRun.IsPresent
            Error          = $_.Exception.Message
            Message        = "Security enhancement failed"
        }
    }
    finally {
        if ($perfContext) {
            try { Stop-PerformanceTracking -Context $perfContext } catch { Write-Verbose "Failed to stop performance tracking: $($_.Exception.Message)" }
        }
    }
}

#endregion

#region Private Helper Functions

<#
.SYNOPSIS
    Loads security configuration from security-config.json
#>
function Get-SecurityConfiguration {
    [CmdletBinding()]
    param()
    
    try {
        # Use CoreInfrastructure function if available
        if (Get-Command 'Get-SecurityConfiguration' -Module 'CoreInfrastructure' -ErrorAction SilentlyContinue) {
            $config = & (Get-Module CoreInfrastructure) { Get-SecurityConfiguration }
            if ($config) {
                Write-LogEntry -Level 'INFO' -Component 'SECURITY-ENHANCEMENT' -Message "Security configuration loaded via CoreInfrastructure"
                return $config
            }
        }
        
        # Fallback to direct file access
        $configRoot = $env:MAINTENANCE_CONFIG_ROOT
        if (-not $configRoot) {
            $configRoot = Join-Path $PSScriptRoot '..\..\config'
        }
        
        $securityConfigPath = Join-Path $configRoot 'settings\security-config.json'
        
        if (-not (Test-Path $securityConfigPath)) {
            Write-Warning "security-config.json not found at: $securityConfigPath"
            return $null
        }
        
        $configJson = Get-Content $securityConfigPath -Raw -ErrorAction Stop
        $config = $configJson | ConvertFrom-Json -ErrorAction Stop
        
        Write-LogEntry -Level 'INFO' -Component 'SECURITY-ENHANCEMENT' -Message "Security configuration loaded from: $securityConfigPath"
        
        return $config
    }
    catch {
        Write-LogEntry -Level 'ERROR' -Component 'SECURITY-ENHANCEMENT' -Message "Failed to load security configuration: $($_.Exception.Message)"
        return $null
    }
}

<#
.SYNOPSIS
    Provides default security configuration if file is missing
#>
function Get-DefaultSecurityConfiguration {
    return [PSCustomObject]@{
        security   = [PSCustomObject]@{
            enableDigitalSignatureVerification = $true
            enableRealTimeProtection           = $true
            defenderIntegration                = $true
            enableAuditLogging                 = $true
        }
        compliance = [PSCustomObject]@{
            enableCISBaseline      = $true
            enforceExecutionPolicy = 'RemoteSigned'
        }
    }
}

<#
.SYNOPSIS
    Configures Windows Defender settings
#>
function Set-WindowsDefenderConfiguration {
    param(
        [PSCustomObject]$Config,
        [switch]$DryRun
    )
    
    $itemsProcessed = 0
    
    try {
        if ($DryRun) {
            Write-Information "      [DRY-RUN] Would configure Windows Defender real-time protection" -InformationAction Continue
            $itemsProcessed = 3  # Simulated: Real-time, Cloud-delivered, Behavior monitoring
        }
        else {
            # Enable real-time protection
            Set-MpPreference -DisableRealtimeMonitoring $false -ErrorAction SilentlyContinue
            $itemsProcessed++
            
            # Enable cloud-delivered protection
            Set-MpPreference -MAPSReporting Advanced -ErrorAction SilentlyContinue
            $itemsProcessed++
            
            # Enable behavior monitoring
            Set-MpPreference -DisableBehaviorMonitoring $false -ErrorAction SilentlyContinue
            $itemsProcessed++
            
            Write-Information "      ✅ Windows Defender configured successfully" -InformationAction Continue
        }
        
        return New-ModuleExecutionResult -Success $true -ItemsDetected $itemsProcessed -ItemsProcessed $itemsProcessed -DurationMilliseconds 0
    }
    catch {
        Write-Warning "      Failed to configure Windows Defender: $($_.Exception.Message)"
        return New-ModuleExecutionResult -Success $false -ItemsDetected 0 -ItemsProcessed 0 -DurationMilliseconds 0 -ErrorMessage $_.Exception.Message
    }
}

<#
.SYNOPSIS
    Verifies and enables Windows Firewall
#>
function Set-FirewallConfiguration {
    param(
        [PSCustomObject]$Config,
        [switch]$DryRun
    )
    
    $itemsProcessed = 0
    
    try {
        if ($DryRun) {
            Write-Information "      [DRY-RUN] Would enable Windows Firewall for all profiles" -InformationAction Continue
            $itemsProcessed = 3  # Domain, Private, Public profiles
        }
        else {
            Set-NetFirewallProfile -Profile Domain, Public, Private -Enabled True -ErrorAction SilentlyContinue
            $itemsProcessed = 3
            Write-Information "      ✅ Windows Firewall enabled for all profiles" -InformationAction Continue
        }
        
        return New-ModuleExecutionResult -Success $true -ItemsDetected $itemsProcessed -ItemsProcessed $itemsProcessed -DurationMilliseconds 0
    }
    catch {
        Write-Warning "      Failed to configure firewall: $($_.Exception.Message)"
        return New-ModuleExecutionResult -Success $false -ItemsDetected 0 -ItemsProcessed 0 -DurationMilliseconds 0 -ErrorMessage $_.Exception.Message
    }
}

<#
.SYNOPSIS
    Configures User Account Control (UAC) settings
#>
function Set-UACConfiguration {
    param(
        [PSCustomObject]$Config,
        [switch]$DryRun
    )
    
    $itemsProcessed = 0
    $uacRegPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
    
    try {
        if ($DryRun) {
            Write-Information "      [DRY-RUN] Would configure UAC to prompt for consent" -InformationAction Continue
            $itemsProcessed = 1
        }
        else {
            # Set UAC to prompt for consent on the secure desktop
            Set-ItemProperty -Path $uacRegPath -Name "ConsentPromptBehaviorAdmin" -Value 2 -Type DWord -ErrorAction Stop
            $itemsProcessed++
            Write-Information "      ✅ UAC configured successfully" -InformationAction Continue
        }
        
        return New-ModuleExecutionResult -Success $true -ItemsDetected $itemsProcessed -ItemsProcessed $itemsProcessed -DurationMilliseconds 0
    }
    catch {
        Write-Warning "      Failed to configure UAC: $($_.Exception.Message)"
        return New-ModuleExecutionResult -Success $false -ItemsDetected 0 -ItemsProcessed 0 -DurationMilliseconds 0 -ErrorMessage $_.Exception.Message
    }
}

<#
.SYNOPSIS
    Sets PowerShell execution policy
#>
function Set-PowerShellExecutionPolicy {
    param(
        [PSCustomObject]$Config,
        [switch]$DryRun
    )
    
    $itemsProcessed = 0
    $policy = $Config.compliance.enforceExecutionPolicy
    
    try {
        if ($DryRun) {
            Write-Information "      [DRY-RUN] Would set execution policy to: $policy" -InformationAction Continue
            $itemsProcessed = 1
        }
        else {
            Set-ExecutionPolicy -ExecutionPolicy $policy -Scope LocalMachine -Force -ErrorAction Stop
            $itemsProcessed++
            Write-Information "      ✅ Execution policy set to: $policy" -InformationAction Continue
        }
        
        return New-ModuleExecutionResult -Success $true -ItemsDetected $itemsProcessed -ItemsProcessed $itemsProcessed -DurationMilliseconds 0
    }
    catch {
        Write-Warning "      Failed to set execution policy: $($_.Exception.Message)"
        return New-ModuleExecutionResult -Success $false -ItemsDetected 0 -ItemsProcessed 0 -DurationMilliseconds 0 -ErrorMessage $_.Exception.Message
    }
}

<#
.SYNOPSIS
    Configures system audit policies
#>
function Set-SystemAuditPolicies {
    param(
        [PSCustomObject]$Config,
        [switch]$DryRun
    )
    
    $itemsProcessed = 0
    
    try {
        if ($DryRun) {
            Write-Information "      [DRY-RUN] Would enable audit policies for security events" -InformationAction Continue
            $itemsProcessed = 5  # Various audit categories
        }
        else {
            # Enable audit policies using auditpol
            $auditCategories = @(
                "Logon/Logoff",
                "Account Management",
                "Policy Change",
                "Privilege Use",
                "System"
            )
            
            foreach ($category in $auditCategories) {
                auditpol /set /category:"$category" /success:enable /failure:enable 2>&1 | Out-Null
                $itemsProcessed++
            }
            
            Write-Information "      ✅ Audit policies configured successfully" -InformationAction Continue
        }
        
        return New-ModuleExecutionResult -Success $true -ItemsDetected $itemsProcessed -ItemsProcessed $itemsProcessed -DurationMilliseconds 0
    }
    catch {
        Write-Warning "      Failed to configure audit policies: $($_.Exception.Message)"
        return New-ModuleExecutionResult -Success $false -ItemsDetected 0 -ItemsProcessed 0 -DurationMilliseconds 0 -ErrorMessage $_.Exception.Message
    }
}

<#
.SYNOPSIS
    Applies network security settings
#>
function Set-NetworkSecurityConfiguration {
    param(
        [PSCustomObject]$Config,
        [switch]$DryRun
    )
    
    $itemsProcessed = 0
    
    try {
        if ($DryRun) {
            Write-Information "      [DRY-RUN] Would apply network security hardening" -InformationAction Continue
            $itemsProcessed = 3  # SMB, LLMNR, NetBIOS
        }
        else {
            # Disable SMBv1
            Disable-WindowsOptionalFeature -Online -FeatureName "SMB1Protocol" -NoRestart -ErrorAction SilentlyContinue | Out-Null
            $itemsProcessed++
            
            # Disable LLMNR
            $llmnrPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient"
            if (-not (Test-Path $llmnrPath)) {
                New-Item -Path $llmnrPath -Force | Out-Null
            }
            Set-ItemProperty -Path $llmnrPath -Name "EnableMulticast" -Value 0 -Type DWord -ErrorAction SilentlyContinue
            $itemsProcessed++
            
            # Disable NetBIOS over TCP/IP
            $adapters = Get-WmiObject Win32_NetworkAdapterConfiguration -Filter "IPEnabled=True" -ErrorAction SilentlyContinue
            foreach ($adapter in $adapters) {
                $adapter.SetTcpipNetbios(2) | Out-Null  # 2 = Disable
            }
            $itemsProcessed++
            
            Write-Information "      ✅ Network security configured successfully" -InformationAction Continue
        }
        
        return New-ModuleExecutionResult -Success $true -ItemsDetected $itemsProcessed -ItemsProcessed $itemsProcessed -DurationMilliseconds 0
    }
    catch {
        Write-Warning "      Failed to configure network security: $($_.Exception.Message)"
        return New-ModuleExecutionResult -Success $false -ItemsDetected 0 -ItemsProcessed 0 -DurationMilliseconds 0 -ErrorMessage $_.Exception.Message
    }
}

#endregion

# Export public functions
Export-ModuleMember -Function @(
    'Invoke-SecurityEnhancement'
)
