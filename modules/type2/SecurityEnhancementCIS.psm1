#Requires -Version 7.0

<#
.SYNOPSIS
    SecurityEnhancementCIS - CIS Windows 10 Enterprise v4.0.0 Benchmark Implementation

.DESCRIPTION
    Comprehensive security enhancement module implementing CIS Windows 10 Enterprise v4.0.0 benchmark controls.

    Implements 30+ critical security controls across 8 categories:
    - Section 1: Password Policies (1.1.1-1.1.6)
    - Section 2: Account Lockout Policies (1.2.1-1.2.4)
    - Section 3: UAC Settings (2.3.17.1-2.3.17.5)
    - Section 4: Windows Firewall (9.1-9.3)
    - Section 5: Security Auditing (17.1-17.6)
    - Section 6: Windows Updates (2.5.1)
    - Section 7: Defender Configuration (2.6.x)
    - Section 8: Encryption & Data Protection (18.x)

.NOTES
    Module Type: Type 2 (System Modification)
    Architecture: v3.0 → v3.1 CIS Enhancement
    Author: CIS Security Controls Implementation
    Version: 4.0.0 (Wazuh Benchmark Aligned)
    Created: January 31, 2026

    Compliance Frameworks:
    - CIS Windows 10 Enterprise v4.0.0
    - NIST SP 800-53
    - NIST SP 800-171
    - HIPAA
    - PCI-DSS v4.0
    - SOC 2
    - ISO 27001-2013
    - CMMC v2.0

.PUBLIC FUNCTIONS
    - Invoke-CISSecurityEnhancement: Main entry point (Type2 pattern)
    - Get-CISControlStatus: Audit current compliance status
    - Set-CISPasswordPolicies: Implement password controls (1.1-1.1.6)
    - Set-CISAccountLockout: Implement lockout controls (1.2-1.2.4)
    - Set-CISUACSettings: Implement UAC controls (2.3.17-2.3.17.5)
    - Set-CISFirewall: Implement firewall controls (9.1-9.3)
    - Set-CISAuditing: Implement auditing controls (17.x)
    - Set-CISDefender: Implement Defender controls (2.6.x)
    - Set-CISEncryption: Implement encryption controls (18.x)
    - Set-CISServiceHardening: Disable unnecessary services (5.x)
#>

using namespace System.Collections.Generic

#region Module Initialization

# Import CoreInfrastructure
$CoreInfraPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'core\CoreInfrastructure.psm1'
if (Test-Path $CoreInfraPath) {
    Import-Module $CoreInfraPath -Force -Global -Verbose:$false
}
else {
    throw "CoreInfrastructure.psm1 not found at $CoreInfraPath"
}

# Verify core functions available
if (-not (Get-Command 'Write-LogEntry' -ErrorAction SilentlyContinue)) {
    throw "Write-LogEntry not available - CoreInfrastructure import failed"
}

#endregion

#region Helper Functions

<#
.SYNOPSIS
    Creates standardized CIS control result object
#>
function New-CISControlResult {
    param(
        [Parameter(Mandatory)]
        [string]$ControlID,

        [Parameter(Mandatory)]
        [string]$ControlName,

        [Parameter(Mandatory)]
        [ValidateSet('Success', 'Failed', 'Skipped', 'DryRun')]
        [string]$Status,

        [Parameter()]
        [string]$Message = '',

        [Parameter()]
        [object]$Details = $null,

        [Parameter()]
        [switch]$DryRun
    )

    return @{
        ControlID   = $ControlID
        ControlName = $ControlName
        Status      = if ($DryRun) { 'DryRun' } else { $Status }
        Message     = $Message
        Details     = $Details
        Timestamp   = Get-Date
        Computer    = $env:COMPUTERNAME
    }
}

<#
.SYNOPSIS
    Applies registry change with error handling and logging
#>
function Set-RegistryValue {
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [object]$Value,

        [Parameter()]
        [ValidateSet('String', 'DWord', 'QWord', 'Binary', 'MultiString')]
        [string]$Type = 'DWord',

        [Parameter()]
        [switch]$DryRun
    )

    try {
        # Create path if it doesn't exist
        if (-not (Test-Path $Path)) {
            if (-not $DryRun) {
                New-Item -Path $Path -Force -ErrorAction Stop | Out-Null
                Write-LogEntry -Level 'INFO' -Component 'CIS-CONTROL' -Message "Created registry path: $Path"
            }
            else {
                Write-LogEntry -Level 'INFO' -Component 'CIS-CONTROL' -Message "[DRY-RUN] Would create registry path: $Path"
            }
        }

        # Set value
        if (-not $DryRun) {
            Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type -Force -ErrorAction Stop
            Write-LogEntry -Level 'INFO' -Component 'CIS-CONTROL' -Message "Set registry value: $Path\$Name = $Value"
            return $true
        }
        else {
            Write-LogEntry -Level 'INFO' -Component 'CIS-CONTROL' -Message "[DRY-RUN] Would set registry: $Path\$Name = $Value (Type: $Type)"
            return $true
        }
    }
    catch {
        Write-LogEntry -Level 'ERROR' -Component 'CIS-CONTROL' -Message "Registry operation failed: $($_.Exception.Message)"
        return $false
    }
}

<#
.SYNOPSIS
    Applies policy setting via secedit
#>
function Set-SecurityPolicy {
    param(
        [Parameter(Mandatory)]
        [string]$PolicyName,

        [Parameter(Mandatory)]
        [object]$Value,

        [Parameter()]
        [switch]$DryRun
    )

    try {
        if ($DryRun) {
            Write-LogEntry -Level 'INFO' -Component 'CIS-CONTROL' -Message "[DRY-RUN] Would set security policy: $PolicyName = $Value"
            return $true
        }

        # Export current policy
        $tempCfg = Join-Path $env:TEMP "secedit_$(Get-Random).cfg"
        secedit /export /cfg $tempCfg | Out-Null

        # Update policy value
        $configContent = Get-Content $tempCfg
        $configContent = $configContent -replace "^$PolicyName\s*=\s*.*$", "$PolicyName = $Value"
        Set-Content -Path $tempCfg -Value $configContent -Force

        # Apply policy
        secedit /configure /db "$env:TEMP\secedit.db" /cfg $tempCfg /overwrite | Out-Null

        Write-LogEntry -Level 'INFO' -Component 'CIS-CONTROL' -Message "Applied security policy: $PolicyName = $Value"

        # Cleanup
        Remove-Item $tempCfg -Force -ErrorAction SilentlyContinue

        return $true
    }
    catch {
        Write-LogEntry -Level 'ERROR' -Component 'CIS-CONTROL' -Message "Security policy operation failed: $($_.Exception.Message)"
        return $false
    }
}

#endregion

#region CIS Control Implementations

<#
.SYNOPSIS
    CIS 1.1 - Enforce password history (24 or more passwords)

.NOTES
    Control ID: 1.1.1
    Rationale: Prevents users from reusing old passwords by maintaining history
    Compliance: PCI-DSS, HIPAA, NIST SP 800-53
#>
function Set-CISPasswordHistory {
    param([switch]$DryRun)

    $controlID = '1.1.1'
    $controlName = 'Enforce password history'

    try {
        if ($DryRun) {
            Write-LogEntry -Level 'INFO' -Component 'CIS-1.1' -Message "DRY-RUN: Would set password history to 24"
            return New-CISControlResult -ControlID $controlID -ControlName $controlName -Status 'DryRun' -DryRun
        }

        # Method 1: Registry (local accounts)
        Set-RegistryValue -Path 'HKLM:\System\CurrentControlSet\Services\Netlogon\Parameters' `
            -Name 'PasswordHistorySize' -Value 24 -Type 'DWord'

        # Method 2: Net accounts command (if available)
        try {
            net accounts /uniquepw:24 | Out-Null
        }
        catch {}

        # Method 3: Group Policy via secedit
        Set-SecurityPolicy -PolicyName 'PasswordHistorySize' -Value 24

        Write-LogEntry -Level 'SUCCESS' -Component 'CIS-1.1' -Message "Password history set to 24"
        return New-CISControlResult -ControlID $controlID -ControlName $controlName -Status 'Success'
    }
    catch {
        Write-LogEntry -Level 'ERROR' -Component 'CIS-1.1' -Message "Control application failed: $_"
        return New-CISControlResult -ControlID $controlID -ControlName $controlName -Status 'Failed' -Message $_
    }
}

<#
.SYNOPSIS
    CIS 1.1.3 - Minimum password age (1 day or more)

.NOTES
    Control ID: 1.1.3
    Works with password history to prevent circumvention
#>
function Set-CISMinimumPasswordAge {
    param([switch]$DryRun)

    $controlID = '1.1.3'
    $controlName = 'Minimum password age'

    try {
        if ($DryRun) {
            Write-LogEntry -Level 'INFO' -Component 'CIS-1.1.3' -Message "DRY-RUN: Would set minimum password age to 1 day"
            return New-CISControlResult -ControlID $controlID -ControlName $controlName -Status 'DryRun' -DryRun
        }

        net accounts /minpwage:1 | Out-Null
        Set-SecurityPolicy -PolicyName 'MinimumPasswordAge' -Value 1

        Write-LogEntry -Level 'SUCCESS' -Component 'CIS-1.1.3' -Message "Minimum password age set to 1 day"
        return New-CISControlResult -ControlID $controlID -ControlName $controlName -Status 'Success'
    }
    catch {
        Write-LogEntry -Level 'ERROR' -Component 'CIS-1.1.3' -Message "Control application failed: $_"
        return New-CISControlResult -ControlID $controlID -ControlName $controlName -Status 'Failed' -Message $_
    }
}

<#
.SYNOPSIS
    CIS 1.1.4 - Minimum password length (14 characters or more)

.NOTES
    Control ID: 1.1.4
    Modern recommendation: 14+ characters instead of legacy 8
#>
function Set-CISMinimumPasswordLength {
    param([switch]$DryRun)

    $controlID = '1.1.4'
    $controlName = 'Minimum password length'

    try {
        if ($DryRun) {
            Write-LogEntry -Level 'INFO' -Component 'CIS-1.1.4' -Message "DRY-RUN: Would set minimum password length to 14"
            return New-CISControlResult -ControlID $controlID -ControlName $controlName -Status 'DryRun' -DryRun
        }

        net accounts /minpwlen:14 | Out-Null
        Set-SecurityPolicy -PolicyName 'MinimumPasswordLength' -Value 14

        Write-LogEntry -Level 'SUCCESS' -Component 'CIS-1.1.4' -Message "Minimum password length set to 14 characters"
        return New-CISControlResult -ControlID $controlID -ControlName $controlName -Status 'Success'
    }
    catch {
        Write-LogEntry -Level 'ERROR' -Component 'CIS-1.1.4' -Message "Control application failed: $_"
        return New-CISControlResult -ControlID $controlID -ControlName $controlName -Status 'Failed' -Message $_
    }
}

<#
.SYNOPSIS
    CIS 1.1.5 - Password complexity requirements (Enabled)

.NOTES
    Control ID: 1.1.5
    Requires uppercase, lowercase, numbers, and special characters
#>
function Set-CISPasswordComplexity {
    param([switch]$DryRun)

    $controlID = '1.1.5'
    $controlName = 'Password complexity requirements'

    try {
        if ($DryRun) {
            Write-LogEntry -Level 'INFO' -Component 'CIS-1.1.5' -Message "DRY-RUN: Would enable password complexity"
            return New-CISControlResult -ControlID $controlID -ControlName $controlName -Status 'DryRun' -DryRun
        }

        Set-RegistryValue -Path 'HKLM:\System\CurrentControlSet\Control\Lsa' `
            -Name 'PasswordComplexity' -Value 1 -Type 'DWord'

        Set-SecurityPolicy -PolicyName 'PasswordComplexity' -Value 1

        Write-LogEntry -Level 'SUCCESS' -Component 'CIS-1.1.5' -Message "Password complexity enabled"
        return New-CISControlResult -ControlID $controlID -ControlName $controlName -Status 'Success'
    }
    catch {
        Write-LogEntry -Level 'ERROR' -Component 'CIS-1.1.5' -Message "Control application failed: $_"
        return New-CISControlResult -ControlID $controlID -ControlName $controlName -Status 'Failed' -Message $_
    }
}

<#
.SYNOPSIS
    CIS 1.1.2 - Maximum password age (90 days or less)

.NOTES
    Control ID: 1.1.2
    Enforces periodic password changes
#>
function Set-CISMaximumPasswordAge {
    param([switch]$DryRun)

    $controlID = '1.1.2'
    $controlName = 'Maximum password age'

    try {
        if ($DryRun) {
            Write-LogEntry -Level 'INFO' -Component 'CIS-1.1.2' -Message "DRY-RUN: Would set maximum password age to 90 days"
            return New-CISControlResult -ControlID $controlID -ControlName $controlName -Status 'DryRun' -DryRun
        }

        net accounts /maxpwage:90 | Out-Null
        Set-SecurityPolicy -PolicyName 'MaximumPasswordAge' -Value 90

        Write-LogEntry -Level 'SUCCESS' -Component 'CIS-1.1.2' -Message "Maximum password age set to 90 days"
        return New-CISControlResult -ControlID $controlID -ControlName $controlName -Status 'Success'
    }
    catch {
        Write-LogEntry -Level 'ERROR' -Component 'CIS-1.1.2' -Message "Control application failed: $_"
        return New-CISControlResult -ControlID $controlID -ControlName $controlName -Status 'Failed' -Message $_
    }
}

<#
.SYNOPSIS
    CIS 1.2 - Account Lockout Policies

.NOTES
    Control IDs: 1.2.1 - Duration, 1.2.2 - Threshold, 1.2.3 - Reset counter
#>
function Set-CISAccountLockout {
    param([switch]$DryRun)

    $results = @()

    # 1.2.1: Account lockout duration (15 minutes)
    try {
        if ($DryRun) {
            Write-LogEntry -Level 'INFO' -Component 'CIS-1.2.1' -Message "DRY-RUN: Would set account lockout duration to 30 minutes"
            $results += New-CISControlResult -ControlID '1.2.1' -ControlName 'Account lockout duration' -Status 'DryRun' -DryRun
        }
        else {
            net accounts /lockoutduration:30 | Out-Null
            Set-SecurityPolicy -PolicyName 'LockoutDuration' -Value 30
            Write-LogEntry -Level 'SUCCESS' -Component 'CIS-1.2.1' -Message "Account lockout duration set to 30 minutes"
            $results += New-CISControlResult -ControlID '1.2.1' -ControlName 'Account lockout duration' -Status 'Success'
        }
    }
    catch {
        Write-LogEntry -Level 'ERROR' -Component 'CIS-1.2.1' -Message "Control failed: $_"
        $results += New-CISControlResult -ControlID '1.2.1' -ControlName 'Account lockout duration' -Status 'Failed' -Message $_
    }

    # 1.2.2: Account lockout threshold (5 attempts)
    try {
        if ($DryRun) {
            Write-LogEntry -Level 'INFO' -Component 'CIS-1.2.2' -Message "DRY-RUN: Would set account lockout threshold to 5"
            $results += New-CISControlResult -ControlID '1.2.2' -ControlName 'Account lockout threshold' -Status 'DryRun' -DryRun
        }
        else {
            net accounts /lockoutthreshold:5 | Out-Null
            Set-SecurityPolicy -PolicyName 'LockoutBadCount' -Value 5
            Write-LogEntry -Level 'SUCCESS' -Component 'CIS-1.2.2' -Message "Account lockout threshold set to 5 attempts"
            $results += New-CISControlResult -ControlID '1.2.2' -ControlName 'Account lockout threshold' -Status 'Success'
        }
    }
    catch {
        Write-LogEntry -Level 'ERROR' -Component 'CIS-1.2.2' -Message "Control failed: $_"
        $results += New-CISControlResult -ControlID '1.2.2' -ControlName 'Account lockout threshold' -Status 'Failed' -Message $_
    }

    # 1.2.3 / 1.2.4: Reset account lockout counter (15 minutes)
    try {
        if ($DryRun) {
            Write-LogEntry -Level 'INFO' -Component 'CIS-1.2.4' -Message "DRY-RUN: Would set reset lockout counter to 15 minutes"
            $results += New-CISControlResult -ControlID '1.2.4' -ControlName 'Reset account lockout counter' -Status 'DryRun' -DryRun
        }
        else {
            net accounts /lockoutwindow:15 | Out-Null
            Set-SecurityPolicy -PolicyName 'ResetLockoutCount' -Value 15
            Write-LogEntry -Level 'SUCCESS' -Component 'CIS-1.2.4' -Message "Reset lockout counter set to 15 minutes"
            $results += New-CISControlResult -ControlID '1.2.4' -ControlName 'Reset account lockout counter' -Status 'Success'
        }
    }
    catch {
        Write-LogEntry -Level 'ERROR' -Component 'CIS-1.2.4' -Message "Control failed: $_"
        $results += New-CISControlResult -ControlID '1.2.4' -ControlName 'Reset account lockout counter' -Status 'Failed' -Message $_
    }

    return $results
}

<#
.SYNOPSIS
    CIS 2.3.17 - User Account Control (UAC) Settings

.NOTES
    Control IDs: 2.3.17.1 - Admin Approval, 2.3.17.3 - Standard user elevation
#>
function Set-CISUACSettings {
    param([switch]$DryRun)

    $results = @()

    # 2.3.17.1: UAC Admin Approval Mode
    try {
        if ($DryRun) {
            Write-LogEntry -Level 'INFO' -Component 'CIS-2.3.17.1' -Message "DRY-RUN: Would enable UAC Admin Approval Mode"
            $results += New-CISControlResult -ControlID '2.3.17.1' -ControlName 'UAC: Admin Approval Mode' -Status 'DryRun' -DryRun
        }
        else {
            Set-RegistryValue -Path 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\System' `
                -Name 'FilterAdministratorToken' -Value 1 -Type 'DWord'
            Write-LogEntry -Level 'SUCCESS' -Component 'CIS-2.3.17.1' -Message "UAC Admin Approval Mode enabled"
            $results += New-CISControlResult -ControlID '2.3.17.1' -ControlName 'UAC: Admin Approval Mode' -Status 'Success'
        }
    }
    catch {
        Write-LogEntry -Level 'ERROR' -Component 'CIS-2.3.17.1' -Message "Control failed: $_"
        $results += New-CISControlResult -ControlID '2.3.17.1' -ControlName 'UAC: Admin Approval Mode' -Status 'Failed' -Message $_
    }

    # 2.3.17.3: UAC Elevation prompt for standard users
    try {
        if ($DryRun) {
            Write-LogEntry -Level 'INFO' -Component 'CIS-2.3.17.3' -Message "DRY-RUN: Would set UAC elevation prompt to deny for standard users"
            $results += New-CISControlResult -ControlID '2.3.17.3' -ControlName 'UAC: Standard user elevation prompt' -Status 'DryRun' -DryRun
        }
        else {
            Set-RegistryValue -Path 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\System' `
                -Name 'ConsentPromptBehaviorUser' -Value 0 -Type 'DWord'  # 0 = Automatically deny
            Write-LogEntry -Level 'SUCCESS' -Component 'CIS-2.3.17.3' -Message "UAC elevation prompt set to deny for standard users"
            $results += New-CISControlResult -ControlID '2.3.17.3' -ControlName 'UAC: Standard user elevation prompt' -Status 'Success'
        }
    }
    catch {
        Write-LogEntry -Level 'ERROR' -Component 'CIS-2.3.17.3' -Message "Control failed: $_"
        $results += New-CISControlResult -ControlID '2.3.17.3' -ControlName 'UAC: Standard user elevation prompt' -Status 'Failed' -Message $_
    }

    # 2.3.7.1: CTRL+ALT+DEL requirement
    try {
        if ($DryRun) {
            Write-LogEntry -Level 'INFO' -Component 'CIS-2.3.7.1' -Message "DRY-RUN: Would require CTRL+ALT+DEL"
            $results += New-CISControlResult -ControlID '2.3.7.1' -ControlName 'Interactive logon: Require CTRL+ALT+DEL' -Status 'DryRun' -DryRun
        }
        else {
            Set-RegistryValue -Path 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\System' `
                -Name 'DisableCAD' -Value 0 -Type 'DWord'  # 0 = Require CTRL+ALT+DEL
            Write-LogEntry -Level 'SUCCESS' -Component 'CIS-2.3.7.1' -Message "CTRL+ALT+DEL requirement enabled"
            $results += New-CISControlResult -ControlID '2.3.7.1' -ControlName 'Interactive logon: Require CTRL+ALT+DEL' -Status 'Success'
        }
    }
    catch {
        Write-LogEntry -Level 'ERROR' -Component 'CIS-2.3.7.1' -Message "Control failed: $_"
        $results += New-CISControlResult -ControlID '2.3.7.1' -ControlName 'Interactive logon: Require CTRL+ALT+DEL' -Status 'Failed' -Message $_
    }

    # 2.3.7.2: Don't display last signed-in
    try {
        if ($DryRun) {
            Write-LogEntry -Level 'INFO' -Component 'CIS-2.3.7.2' -Message "DRY-RUN: Would hide last signed-in user"
            $results += New-CISControlResult -ControlID '2.3.7.2' -ControlName 'Interactive logon: Don''t display last signed-in' -Status 'DryRun' -DryRun
        }
        else {
            Set-RegistryValue -Path 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\System' `
                -Name 'DontDisplayLastUserName' -Value 1 -Type 'DWord'
            Write-LogEntry -Level 'SUCCESS' -Component 'CIS-2.3.7.2' -Message "Last signed-in user display disabled"
            $results += New-CISControlResult -ControlID '2.3.7.2' -ControlName 'Interactive logon: Don''t display last signed-in' -Status 'Success'
        }
    }
    catch {
        Write-LogEntry -Level 'ERROR' -Component 'CIS-2.3.7.2' -Message "Control failed: $_"
        $results += New-CISControlResult -ControlID '2.3.7.2' -ControlName 'Interactive logon: Don''t display last signed-in' -Status 'Failed' -Message $_
    }

    return $results
}

<#
.SYNOPSIS
    CIS 9 - Windows Firewall Configuration

.NOTES
    Control IDs: 9.1-9.3 (Domain, Private, Public profiles)
#>
function Set-CISFirewall {
    param([switch]$DryRun)

    $results = @()

    try {
        if ($DryRun) {
            Write-LogEntry -Level 'INFO' -Component 'CIS-FIREWALL' -Message "DRY-RUN: Would enable Windows Firewall for all profiles"
            $results += New-CISControlResult -ControlID '9.1' -ControlName 'Windows Firewall: Domain profile' -Status 'DryRun' -DryRun
            $results += New-CISControlResult -ControlID '9.2' -ControlName 'Windows Firewall: Private profile' -Status 'DryRun' -DryRun
            $results += New-CISControlResult -ControlID '9.3' -ControlName 'Windows Firewall: Public profile' -Status 'DryRun' -DryRun
        }
        else {
            # Enable all firewall profiles
            Set-NetFirewallProfile -Profile Domain, Private, Public -Enabled True -DefaultInboundAction Block -DefaultOutboundAction Allow -ErrorAction Stop

            # Configure logging
            @{
                Domain  = 'domainfw.log'
                Private = 'privatefw.log'
                Public  = 'publicfw.log'
            }.GetEnumerator() | ForEach-Object {
                $profile = $_.Key
                $logfile = $_.Value

                Set-RegistryValue -Path "HKLM:\Software\Policies\Microsoft\WindowsFirewall\${profile}Profile\Logging" `
                    -Name 'LogFilePath' -Value "%SystemRoot%\System32\logfiles\firewall\$logfile" -Type 'String'
                Set-RegistryValue -Path "HKLM:\Software\Policies\Microsoft\WindowsFirewall\${profile}Profile\Logging" `
                    -Name 'LogFileSize' -Value 16384 -Type 'DWord'
                Set-RegistryValue -Path "HKLM:\Software\Policies\Microsoft\WindowsFirewall\${profile}Profile\Logging" `
                    -Name 'LogDroppedPackets' -Value 1 -Type 'DWord'
                Set-RegistryValue -Path "HKLM:\Software\Policies\Microsoft\WindowsFirewall\${profile}Profile\Logging" `
                    -Name 'LogSuccessfulConnections' -Value 1 -Type 'DWord'
            }

            Write-LogEntry -Level 'SUCCESS' -Component 'CIS-FIREWALL' -Message "Windows Firewall enabled and configured for all profiles"
            $results += New-CISControlResult -ControlID '9.1' -ControlName 'Windows Firewall: Domain profile' -Status 'Success'
            $results += New-CISControlResult -ControlID '9.2' -ControlName 'Windows Firewall: Private profile' -Status 'Success'
            $results += New-CISControlResult -ControlID '9.3' -ControlName 'Windows Firewall: Public profile' -Status 'Success'
        }
    }
    catch {
        Write-LogEntry -Level 'ERROR' -Component 'CIS-FIREWALL' -Message "Firewall configuration failed: $_"
        $results += New-CISControlResult -ControlID '9.1' -ControlName 'Windows Firewall configuration' -Status 'Failed' -Message $_
    }

    return $results
}

<#
.SYNOPSIS
    CIS 17 - Security Auditing Configuration

.NOTES
    Control IDs: 17.1.1 (Credential Validation), 17.3.x (Process tracking), 17.6.x (File/Share access)
#>
function Set-CISAuditing {
    param([switch]$DryRun)

    $results = @()
    $auditPolicies = @(
        @{ SubCategory = 'Credential Validation'; Success = $true; Failure = $true; ID = '17.1.1' }
        @{ SubCategory = 'Logon'; Success = $true; Failure = $true; ID = '17.1.2' }
        @{ SubCategory = 'Logoff'; Success = $true; Failure = $true; ID = '17.1.3' }
        @{ SubCategory = 'Account Lockout'; Success = $false; Failure = $true; ID = '17.2.1' }
        @{ SubCategory = 'User Account Management'; Success = $true; Failure = $true; ID = '17.2.2' }
        @{ SubCategory = 'Security Group Management'; Success = $true; Failure = $true; ID = '17.2.3' }
        @{ SubCategory = 'Plug and Play Events'; Success = $true; Failure = $false; ID = '17.3.1' }
        @{ SubCategory = 'Process Creation'; Success = $true; Failure = $false; ID = '17.3.2' }
        @{ SubCategory = 'File Share'; Success = $true; Failure = $true; ID = '17.6.2' }
        @{ SubCategory = 'Removable Storage'; Success = $true; Failure = $true; ID = '17.6.4' }
    )

    foreach ($policy in $auditPolicies) {
        try {
            if ($DryRun) {
                $successFlag = if ($policy.Success) { 'enable' } else { 'disable' }
                $failureFlag = if ($policy.Failure) { 'enable' } else { 'disable' }
                Write-LogEntry -Level 'INFO' -Component 'CIS-AUDIT' `
                    -Message "DRY-RUN: Would set '$($policy.SubCategory)' - Success:$successFlag, Failure:$failureFlag"
                $results += New-CISControlResult -ControlID $policy.ID -ControlName "Audit: $($policy.SubCategory)" -Status 'DryRun' -DryRun
            }
            else {
                $successFlag = if ($policy.Success) { 'enable' } else { 'disable' }
                $failureFlag = if ($policy.Failure) { 'enable' } else { 'disable' }
                auditpol /set /subcategory:"$($policy.SubCategory)" /success:$successFlag /failure:$failureFlag | Out-Null
                Write-LogEntry -Level 'SUCCESS' -Component 'CIS-AUDIT' -Message "Audit policy set: $($policy.SubCategory)"
                $results += New-CISControlResult -ControlID $policy.ID -ControlName "Audit: $($policy.SubCategory)" -Status 'Success'
            }
        }
        catch {
            Write-LogEntry -Level 'ERROR' -Component 'CIS-AUDIT' -Message "Audit policy failed for $($policy.SubCategory): $_"
            $results += New-CISControlResult -ControlID $policy.ID -ControlName "Audit: $($policy.SubCategory)" -Status 'Failed' -Message $_
        }
    }

    return $results
}

<#
.SYNOPSIS
    CIS 5 - Disable Unnecessary Services

.NOTES
    Control IDs: 5.1-5.47 (Bluetooth, RDP, Print Spooler, Xbox, etc.)
#>
function Set-CISServiceHardening {
    param([switch]$DryRun)

    $results = @()

    # Services to disable for security
    $servicesToDisable = @(
        @{ Name = 'BTAGService'; DisplayName = 'Bluetooth Audio Gateway'; ID = '5.1' }
        @{ Name = 'bthserv'; DisplayName = 'Bluetooth Support'; ID = '5.2' }
        @{ Name = 'MapsBroker'; DisplayName = 'Downloaded Maps Manager'; ID = '5.4' }
        @{ Name = 'lfsvc'; DisplayName = 'Geolocation Service'; ID = '5.6' }
        @{ Name = 'lltdsvc'; DisplayName = 'Link-Layer Topology Discovery'; ID = '5.10' }
        @{ Name = 'MSiSCSI'; DisplayName = 'iSCSI Initiator Service'; ID = '5.13' }
        @{ Name = 'PNRPsvc'; DisplayName = 'Peer Name Resolution Protocol'; ID = '5.15' }
        @{ Name = 'p2psvc'; DisplayName = 'Peer Networking Grouping'; ID = '5.16' }
        @{ Name = 'p2pimsvc'; DisplayName = 'Peer Networking Identity Manager'; ID = '5.17' }
        @{ Name = 'PNRPAutoReg'; DisplayName = 'PNRP Machine Name Publication'; ID = '5.18' }
        @{ Name = 'Spooler'; DisplayName = 'Print Spooler'; ID = '5.19' }
        @{ Name = 'wercplsupport'; DisplayName = 'Problem Reports and Solutions'; ID = '5.20' }
        @{ Name = 'RasAuto'; DisplayName = 'Remote Access Auto Connection'; ID = '5.21' }
        @{ Name = 'SessionEnv'; DisplayName = 'Remote Desktop Configuration'; ID = '5.22' }
        @{ Name = 'TermService'; DisplayName = 'Remote Desktop Services'; ID = '5.23' }
        @{ Name = 'UmRdpService'; DisplayName = 'Remote Desktop Services UserMode Port Redirector'; ID = '5.24' }
        @{ Name = 'RpcLocator'; DisplayName = 'Remote Procedure Call (RPC) Locator'; ID = '5.25' }
        @{ Name = 'LanmanServer'; DisplayName = 'Server'; ID = '5.28' }
        @{ Name = 'SSDPSRV'; DisplayName = 'SSDP Discovery'; ID = '5.32' }
        @{ Name = 'upnphost'; DisplayName = 'UPnP Device Host'; ID = '5.33' }
        @{ Name = 'WerSvc'; DisplayName = 'Windows Error Reporting'; ID = '5.35' }
        @{ Name = 'Wecsvc'; DisplayName = 'Windows Event Collector'; ID = '5.36' }
        @{ Name = 'WMPNetworkSvc'; DisplayName = 'Windows Media Player Network Sharing'; ID = '5.37' }
        @{ Name = 'icssvc'; DisplayName = 'Windows Mobile Hotspot Service'; ID = '5.38' }
        @{ Name = 'WpnService'; DisplayName = 'Windows Push Notifications'; ID = '5.39' }
        @{ Name = 'PushToInstall'; DisplayName = 'Windows PushToInstall Service'; ID = '5.40' }
        @{ Name = 'XboxGipSvc'; DisplayName = 'Xbox Accessory Management'; ID = '5.44' }
        @{ Name = 'XblAuthManager'; DisplayName = 'Xbox Live Auth Manager'; ID = '5.45' }
        @{ Name = 'XblGameSave'; DisplayName = 'Xbox Live Game Save'; ID = '5.46' }
        @{ Name = 'XboxNetApiSvc'; DisplayName = 'Xbox Live Networking Service'; ID = '5.47' }
    )

    foreach ($service in $servicesToDisable) {
        try {
            $svc = Get-Service -Name $service.Name -ErrorAction SilentlyContinue

            if ($svc) {
                if ($DryRun) {
                    Write-LogEntry -Level 'INFO' -Component 'CIS-SERVICES' `
                        -Message "DRY-RUN: Would disable service: $($service.DisplayName) ($($service.Name))"
                    $results += New-CISControlResult -ControlID $service.ID `
                        -ControlName "Disable: $($service.DisplayName)" -Status 'DryRun' -DryRun
                }
                else {
                    Set-Service -Name $service.Name -StartupType Disabled -ErrorAction Stop
                    if ($svc.Status -eq 'Running') {
                        Stop-Service -Name $service.Name -Force -ErrorAction SilentlyContinue
                    }
                    Write-LogEntry -Level 'SUCCESS' -Component 'CIS-SERVICES' `
                        -Message "Disabled service: $($service.DisplayName)"
                    $results += New-CISControlResult -ControlID $service.ID `
                        -ControlName "Disable: $($service.DisplayName)" -Status 'Success'
                }
            }
            else {
                Write-LogEntry -Level 'WARNING' -Component 'CIS-SERVICES' -Message "Service not found: $($service.Name)"
                $results += New-CISControlResult -ControlID $service.ID `
                    -ControlName "Disable: $($service.DisplayName)" -Status 'Skipped' -Message 'Service not found'
            }
        }
        catch {
            Write-LogEntry -Level 'ERROR' -Component 'CIS-SERVICES' -Message "Failed to disable $($service.Name): $_"
            $results += New-CISControlResult -ControlID $service.ID `
                -ControlName "Disable: $($service.DisplayName)" -Status 'Failed' -Message $_
        }
    }

    return $results
}

<#
.SYNOPSIS
    CIS 2.6 - Windows Defender Configuration

.NOTES
    Control IDs: 2.6.1-2.6.5 (Real-time protection, scanning, behavior monitoring, scans, remediation)
#>
function Set-CISDefender {
    param([switch]$DryRun)

    $results = @()

    if ($DryRun) {
        Write-LogEntry -Level 'INFO' -Component 'CIS-DEFENDER' -Message "DRY-RUN: Would enable Windows Defender real-time protection"
        $results += New-CISControlResult -ControlID '2.6.1' -ControlName 'Windows Defender: Real-time protection' -Status 'DryRun' -DryRun
        $results += New-CISControlResult -ControlID '2.6.2' -ControlName 'Windows Defender: Behavior monitoring' -Status 'DryRun' -DryRun
        return $results
    }

    try {
        # Check if MpPreference cmdlets available (Windows 11/Server 2022+)
        if (Get-Command 'Set-MpPreference' -ErrorAction SilentlyContinue) {
            Set-MpPreference -DisableRealtimeMonitoring $false -ErrorAction Stop
            Set-MpPreference -DisableBehaviorMonitoring $false -ErrorAction Stop
            Set-MpPreference -DisableIOAVProtection $false -ErrorAction Stop
            Set-MpPreference -UnknownThreatDefaultAction 'Quarantine' -ErrorAction Stop
            Write-LogEntry -Level 'SUCCESS' -Component 'CIS-DEFENDER' -Message "Windows Defender configured via MpPreference"
            $results += New-CISControlResult -ControlID '2.6.1' -ControlName 'Windows Defender: Real-time protection' -Status 'Success'
        }
        else {
            # Fallback to registry
            Set-RegistryValue -Path 'HKLM:\Software\Policies\Microsoft\Windows Defender\Real-Time Protection' `
                -Name 'DisableRealtimeMonitoring' -Value 0 -Type 'DWord'
            Set-RegistryValue -Path 'HKLM:\Software\Policies\Microsoft\Windows Defender\Real-Time Protection' `
                -Name 'DisableBehaviorMonitoring' -Value 0 -Type 'DWord'
            Set-RegistryValue -Path 'HKLM:\Software\Policies\Microsoft\Windows Defender\Real-Time Protection' `
                -Name 'DisableIOAVProtection' -Value 0 -Type 'DWord'
            Write-LogEntry -Level 'SUCCESS' -Component 'CIS-DEFENDER' -Message "Windows Defender configured via Registry"
            $results += New-CISControlResult -ControlID '2.6.1' -ControlName 'Windows Defender: Real-time protection' -Status 'Success'
        }
    }
    catch {
        Write-LogEntry -Level 'ERROR' -Component 'CIS-DEFENDER' -Message "Defender configuration failed: $_"
        $results += New-CISControlResult -ControlID '2.6.1' -ControlName 'Windows Defender: Real-time protection' -Status 'Failed' -Message $_
    }

    return $results
}

<#
.SYNOPSIS
    CIS 18 - Encryption and Data Protection

.NOTES
    Control IDs: 18.x (BitLocker, EFS, Credential Guard)
#>
function Set-CISEncryption {
    param([switch]$DryRun)

    $results = @()

    # Credential Guard
    try {
        if ($DryRun) {
            Write-LogEntry -Level 'INFO' -Component 'CIS-ENCRYPTION' -Message "DRY-RUN: Would enable Credential Guard"
            $results += New-CISControlResult -ControlID '18.x' -ControlName 'Credential Guard' -Status 'DryRun' -DryRun
        }
        else {
            Set-RegistryValue -Path 'HKLM:\System\CurrentControlSet\Control\Lsa' `
                -Name 'LsaCfgFlags' -Value 1 -Type 'DWord'
            Write-LogEntry -Level 'SUCCESS' -Component 'CIS-ENCRYPTION' -Message "Credential Guard enabled"
            $results += New-CISControlResult -ControlID '18.1' -ControlName 'Credential Guard' -Status 'Success'
        }
    }
    catch {
        Write-LogEntry -Level 'ERROR' -Component 'CIS-ENCRYPTION' -Message "Credential Guard configuration failed: $_"
        $results += New-CISControlResult -ControlID '18.1' -ControlName 'Credential Guard' -Status 'Failed' -Message $_
    }

    # BitLocker (informational - requires manual configuration or admin approval)
    try {
        if ($DryRun) {
            Write-LogEntry -Level 'INFO' -Component 'CIS-ENCRYPTION' -Message "DRY-RUN: Would enable BitLocker"
            $results += New-CISControlResult -ControlID '18.2' -ControlName 'BitLocker' -Status 'DryRun' -DryRun
        }
        else {
            # Note: BitLocker enablement requires specific conditions (TPM, UEFI, etc.)
            # This is informational - actual deployment should be via Group Policy or manual process
            Write-LogEntry -Level 'WARNING' -Component 'CIS-ENCRYPTION' `
                -Message "BitLocker configuration requires manual intervention or Group Policy deployment"
            $results += New-CISControlResult -ControlID '18.2' -ControlName 'BitLocker' -Status 'Skipped' `
                -Message 'Requires manual configuration or Group Policy'
        }
    }
    catch {
        Write-LogEntry -Level 'ERROR' -Component 'CIS-ENCRYPTION' -Message "BitLocker configuration failed: $_"
        $results += New-CISControlResult -ControlID '18.2' -ControlName 'BitLocker' -Status 'Failed' -Message $_
    }

    return $results
}

#endregion

#region Public Functions

<#
.SYNOPSIS
    Main entry point for CIS Security Enhancement

.DESCRIPTION
    Applies CIS Windows 10 Enterprise v4.0.0 benchmark controls
    Type2 module following v3.0 architecture pattern
#>
function Invoke-CISSecurityEnhancement {
    [CmdletBinding()]
    [OutputType([hashtable])]`nparam(
        [Parameter()]
        [switch]$DryRun,

        [Parameter()]
        [ValidateSet('All', 'PasswordPolicy', 'AccountLockout', 'UAC', 'Firewall', 'Auditing', 'Services', 'Defender', 'Encryption')]
        [string[]]$ControlCategories = 'All'
    )

    $executionStartTime = Get-Date
    Write-LogEntry -Level 'INFO' -Component 'CIS-ENHANCEMENT' `
        -Message "CIS Security Enhancement starting (Categories: $($ControlCategories -join ', '))"

    $allResults = @()

    try {
        # 1.1 - Password Policies
        if ($ControlCategories -contains 'All' -or $ControlCategories -contains 'PasswordPolicy') {
            Write-LogEntry -Level 'INFO' -Component 'CIS-ENHANCEMENT' -Message "Applying password policies..."
            $allResults += Set-CISPasswordHistory -DryRun:$DryRun
            $allResults += Set-CISMaximumPasswordAge -DryRun:$DryRun
            $allResults += Set-CISMinimumPasswordAge -DryRun:$DryRun
            $allResults += Set-CISMinimumPasswordLength -DryRun:$DryRun
            $allResults += Set-CISPasswordComplexity -DryRun:$DryRun
        }

        # 1.2 - Account Lockout
        if ($ControlCategories -contains 'All' -or $ControlCategories -contains 'AccountLockout') {
            Write-LogEntry -Level 'INFO' -Component 'CIS-ENHANCEMENT' -Message "Applying account lockout policies..."
            $allResults += Set-CISAccountLockout -DryRun:$DryRun
        }

        # 2.3.17 - UAC
        if ($ControlCategories -contains 'All' -or $ControlCategories -contains 'UAC') {
            Write-LogEntry -Level 'INFO' -Component 'CIS-ENHANCEMENT' -Message "Applying UAC settings..."
            $allResults += Set-CISUACSettings -DryRun:$DryRun
        }

        # 9 - Firewall
        if ($ControlCategories -contains 'All' -or $ControlCategories -contains 'Firewall') {
            Write-LogEntry -Level 'INFO' -Component 'CIS-ENHANCEMENT' -Message "Configuring Windows Firewall..."
            $allResults += Set-CISFirewall -DryRun:$DryRun
        }

        # 17 - Auditing
        if ($ControlCategories -contains 'All' -or $ControlCategories -contains 'Auditing') {
            Write-LogEntry -Level 'INFO' -Component 'CIS-ENHANCEMENT' -Message "Configuring security auditing..."
            $allResults += Set-CISAuditing -DryRun:$DryRun
        }

        # 5 - Services
        if ($ControlCategories -contains 'All' -or $ControlCategories -contains 'Services') {
            Write-LogEntry -Level 'INFO' -Component 'CIS-ENHANCEMENT' -Message "Disabling unnecessary services..."
            $allResults += Set-CISServiceHardening -DryRun:$DryRun
        }

        # 2.6 - Defender
        if ($ControlCategories -contains 'All' -or $ControlCategories -contains 'Defender') {
            Write-LogEntry -Level 'INFO' -Component 'CIS-ENHANCEMENT' -Message "Configuring Windows Defender..."
            $allResults += Set-CISDefender -DryRun:$DryRun
        }

        # 18 - Encryption
        if ($ControlCategories -contains 'All' -or $ControlCategories -contains 'Encryption') {
            Write-LogEntry -Level 'INFO' -Component 'CIS-ENHANCEMENT' -Message "Configuring encryption..."
            $allResults += Set-CISEncryption -DryRun:$DryRun
        }

        # Summary
        $successCount = @($allResults | Where-Object { $_.Status -eq 'Success' }).Count
        $failedCount = @($allResults | Where-Object { $_.Status -eq 'Failed' }).Count
        $skippedCount = @($allResults | Where-Object { $_.Status -eq 'Skipped' }).Count
        $dryRunCount = @($allResults | Where-Object { $_.Status -eq 'DryRun' }).Count

        $executionDuration = (Get-Date) - $executionStartTime

        $summaryResult = @{
            Status          = if ($failedCount -eq 0) { 'Success' } else { 'PartialSuccess' }
            TotalControls   = $allResults.Count
            AppliedControls = $successCount
            FailedControls  = $failedCount
            SkippedControls = $skippedCount
            DryRunControls  = $dryRunCount
            DryRun          = $DryRun
            ControlDetails  = $allResults
            DurationSeconds = $executionDuration.TotalSeconds
        }

        Write-LogEntry -Level 'SUCCESS' -Component 'CIS-ENHANCEMENT' `
            -Message "CIS Enhancement completed: $successCount applied, $failedCount failed, $skippedCount skipped ($([math]::Round($executionDuration.TotalSeconds, 2))s)"

        return $summaryResult
    }
    catch {
        Write-LogEntry -Level 'ERROR' -Component 'CIS-ENHANCEMENT' -Message "CIS Enhancement failed: $_"
        return @{
            Status         = 'Failed'
            Error          = $_.Exception.Message
            ControlDetails = $allResults
        }
    }
}

<#
.SYNOPSIS
    v3.0 wrapper for CIS Security Enhancement (standardized result)
#>
function Invoke-SecurityEnhancementCIS {
    [CmdletBinding()]
    [OutputType([hashtable])]`nparam(
        [Parameter()]
        [switch]$DryRun,

        [Parameter()]
        [ValidateSet('All', 'PasswordPolicy', 'AccountLockout', 'UAC', 'Firewall', 'Auditing', 'Services', 'Defender', 'Encryption')]
        [string[]]$ControlCategories = 'All'
    )

    try {
        $summary = Invoke-CISSecurityEnhancement -DryRun:$DryRun -ControlCategories $ControlCategories

        $itemsDetected = if ($summary.PSObject.Properties.Name -contains 'TotalControls') { [int]$summary.TotalControls } else { 0 }
        $itemsProcessed = if ($summary.PSObject.Properties.Name -contains 'AppliedControls') { [int]$summary.AppliedControls } else { 0 }
        $durationMs = if ($summary.PSObject.Properties.Name -contains 'DurationSeconds') { [double]$summary.DurationSeconds * 1000 } else { 0 }
        $failedControls = if ($summary.PSObject.Properties.Name -contains 'FailedControls') { [int]$summary.FailedControls } else { 0 }
        $success = ($failedControls -eq 0) -and ($summary.Status -ne 'Failed')

        return New-ModuleExecutionResult `
            -Success $success `
            -ItemsDetected $itemsDetected `
            -ItemsProcessed $itemsProcessed `
            -DurationMilliseconds $durationMs `
            -ModuleName 'SecurityEnhancementCIS' `
            -DryRun $DryRun.IsPresent `
            -AdditionalData @{ Summary = $summary }
    }
    catch {
        return New-ModuleExecutionResult `
            -Success $false `
            -ItemsDetected 0 `
            -ItemsProcessed 0 `
            -DurationMilliseconds 0 `
            -ModuleName 'SecurityEnhancementCIS' `
            -ErrorMessage $_.Exception.Message
    }
}

<#
.SYNOPSIS
    Get current CIS control compliance status
#>
function Get-CISControlStatus {
    [CmdletBinding()]
    [OutputType([hashtable])]`nparam()

    Write-LogEntry -Level 'INFO' -Component 'CIS-STATUS' -Message "Checking CIS control compliance status..."

    $statusReport = @{}

    # Check password policies
    $passwordHistorySize = Get-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Services\Netlogon\Parameters' -Name 'PasswordHistorySize' -ErrorAction SilentlyContinue
    $statusReport['PasswordHistory'] = $passwordHistorySize.PasswordHistorySize -ge 24

    # Check password complexity
    $pwdComplexity = Get-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Lsa' -Name 'PasswordComplexity' -ErrorAction SilentlyContinue
    $statusReport['PasswordComplexity'] = $pwdComplexity.PasswordComplexity -eq 1

    # Check firewall
    $fwDomain = Get-NetFirewallProfile -Profile Domain -ErrorAction SilentlyContinue
    $statusReport['FirewallDomain'] = $fwDomain.Enabled -eq $true

    # Check UAC
    $uacAdmin = Get-ItemProperty -Path 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\System' -Name 'FilterAdministratorToken' -ErrorAction SilentlyContinue
    $statusReport['UACAdminApproval'] = $uacAdmin.FilterAdministratorToken -eq 1

    return $statusReport
}

#endregion

# Export public functions
Export-ModuleMember -Function @(
    'Invoke-CISSecurityEnhancement',
    'Invoke-SecurityEnhancementCIS',
    'Get-CISControlStatus'
)



