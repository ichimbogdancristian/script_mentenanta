#Requires -Version 7.0
<#
.SYNOPSIS    Security Audit - Type 1
.DESCRIPTION Audits system security against the security baseline.
             Diff = security settings that don't match the desired baseline values.
.NOTES       Module Type: Type1 | DiffKey: SecurityEnhancement | Version: 5.0
#>

$_corePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'core\Maintenance.psm1'
if (-not (Get-Command 'Write-Log' -ErrorAction SilentlyContinue)) {
    Import-Module $_corePath -Force -Global -WarningAction SilentlyContinue
}

function Invoke-SecurityAudit {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    Write-Log -Level INFO -Component SEC-AUDIT -Message 'Starting security audit'

    try {
        # 1. Load baseline
        $baseline = Get-BaselineList -ModuleFolder 'security' -FileName 'security-baseline.json'
        if (-not $baseline) {
            return New-ModuleResult -ModuleName 'SecurityAudit' -Status 'Failed' `
                -Message 'Security baseline not found'
        }
        if (-not $baseline.registry -and -not $baseline.windowsDefender) {
            return New-ModuleResult -ModuleName 'SecurityAudit' -Status 'Failed' `
                -Message 'Invalid security baseline structure (missing registry and windowsDefender)'
        }

        $diff = [System.Collections.Generic.List[hashtable]]::new()

        # 2. Registry security checks
        foreach ($entry in $baseline.registry) {
            $current = Get-RegistryValue -Path $entry.path -Name $entry.name
            if ($null -eq $current -or "$current" -ne "$($entry.desiredValue)") {
                $diff.Add(@{
                        Type         = 'registry'
                        Name         = "$($entry.path)\$($entry.name)"
                        Description  = $entry.description
                        Path         = $entry.path
                        ValueName    = $entry.name
                        DesiredValue = $entry.desiredValue
                        ValueType    = if ($entry.type) { $entry.type } else { 'DWord' }
                        CurrentState = $current
                        DesiredState = $entry.desiredValue
                    })
                Write-Log -Level DEBUG -Component SEC-AUDIT -Message "Security mismatch: $($entry.description)"
            }
        }

        # 3. Windows Defender real-time protection + optional features
        if ($baseline.windowsDefender.realTimeProtection) {
            try {
                $mpStatus = Get-MpComputerStatus -ErrorAction Stop
                if (-not $mpStatus.RealTimeProtectionEnabled) {
                    $diff.Add(@{
                            Type         = 'defender'
                            Name         = 'RealTimeProtection'
                            Feature      = 'RealTimeProtection'
                            ShouldEnable = $true
                            Description  = 'Windows Defender real-time protection'
                            CurrentState = $false
                            DesiredState = $true
                        })
                    Write-Log -Level WARN -Component SEC-AUDIT -Message 'Defender real-time protection is DISABLED'
                }
                if (-not $mpStatus.AntivirusEnabled) {
                    $diff.Add(@{
                            Type         = 'defender'
                            Name         = 'AntivirusEnabled'
                            Feature      = 'AntivirusEnabled'
                            ShouldEnable = $true
                            Description  = 'Windows Defender antivirus service'
                            CurrentState = $false
                            DesiredState = $true
                        })
                }
            }
            catch {
                Write-Log -Level WARN -Component SEC-AUDIT -Message "Defender status query failed: $_"
                $diff.Add(@{
                        Type         = 'defender'
                        Name         = 'DefenderStatusUnknown'
                        Feature      = 'RealTimeProtection'
                        ShouldEnable = $true
                        Description  = 'Windows Defender status could not be verified'
                        CurrentState = 'Unknown'
                        DesiredState = $true
                    })
            }

            # Check cloud protection, network protection, and PUA via Get-MpPreference
            try {
                $mpPrefs = Get-MpPreference -ErrorAction Stop
                if ($baseline.windowsDefender.cloudProtection -and $mpPrefs.MAPSReporting -eq 0) {
                    $diff.Add(@{
                            Type         = 'defender'
                            Name         = 'CloudProtection'
                            Feature      = 'CloudProtection'
                            ShouldEnable = $true
                            Description  = 'Windows Defender cloud-delivered protection'
                            CurrentState = $false
                            DesiredState = $true
                        })
                    Write-Log -Level WARN -Component SEC-AUDIT -Message 'Defender cloud protection is DISABLED'
                }
                if ($baseline.windowsDefender.networkProtection -and $mpPrefs.EnableNetworkProtection -eq 0) {
                    $diff.Add(@{
                            Type         = 'defender'
                            Name         = 'NetworkProtection'
                            Feature      = 'NetworkProtection'
                            ShouldEnable = $true
                            Description  = 'Windows Defender network protection'
                            CurrentState = $false
                            DesiredState = $true
                        })
                    Write-Log -Level WARN -Component SEC-AUDIT -Message 'Defender network protection is DISABLED'
                }
                if ($baseline.windowsDefender.pua -and $mpPrefs.PUAProtection -eq 0) {
                    $diff.Add(@{
                            Type         = 'defender'
                            Name         = 'PUAProtection'
                            Feature      = 'PUAProtection'
                            ShouldEnable = $true
                            Description  = 'Windows Defender PUA (Potentially Unwanted App) protection'
                            CurrentState = $false
                            DesiredState = $true
                        })
                    Write-Log -Level WARN -Component SEC-AUDIT -Message 'Defender PUA protection is DISABLED'
                }
            }
            catch {
                Write-Log -Level WARN -Component SEC-AUDIT -Message "Defender preference query failed: $_"
                foreach ($feat in @('CloudProtection', 'NetworkProtection', 'PUAProtection')) {
                    $diff.Add(@{
                            Type         = 'defender'
                            Name         = $feat
                            Feature      = $feat
                            ShouldEnable = $true
                            Description  = "Defender $feat status could not be verified"
                            CurrentState = 'Unknown'
                            DesiredState = $true
                        })
                }
            }
        }

        # 3b. Controlled Folder Access
        if ($baseline.windowsDefender.controlledFolderAccess) {
            try {
                $mpPrefs = if ($mpPrefs) { $mpPrefs } else { Get-MpPreference -ErrorAction Stop }
                if ($mpPrefs.EnableControlledFolderAccess -ne 1) {
                    $diff.Add(@{
                            Type         = 'defender'
                            Name         = 'ControlledFolderAccess'
                            Feature      = 'ControlledFolderAccess'
                            ShouldEnable = $true
                            Description  = 'Windows Defender Controlled Folder Access'
                            CurrentState = $mpPrefs.EnableControlledFolderAccess
                            DesiredState = 1
                        })
                    Write-Log -Level WARN -Component SEC-AUDIT -Message 'Controlled Folder Access is not enabled'
                }
            }
            catch { Write-Log -Level WARN -Component SEC-AUDIT -Message "Controlled Folder Access query failed: $_" }
        }

        # 3c. Automatic Sample Submission
        if ($baseline.windowsDefender.automaticSampleSubmission) {
            try {
                $mpPrefs = if ($mpPrefs) { $mpPrefs } else { Get-MpPreference -ErrorAction Stop }
                if ($mpPrefs.SubmitSamplesConsent -eq 0) {
                    $diff.Add(@{
                            Type         = 'defender'
                            Name         = 'AutomaticSampleSubmission'
                            Feature      = 'AutomaticSampleSubmission'
                            ShouldEnable = $true
                            Description  = 'Windows Defender automatic sample submission'
                            CurrentState = $mpPrefs.SubmitSamplesConsent
                            DesiredState = 1
                        })
                    Write-Log -Level WARN -Component SEC-AUDIT -Message 'Automatic sample submission is disabled'
                }
            }
            catch { Write-Log -Level WARN -Component SEC-AUDIT -Message "Sample submission query failed: $_" }
        }

        # 4. Firewall status
        if ($baseline.firewall) {
            try {
                $fwProfiles = Get-NetFirewallProfile -ErrorAction Stop
                foreach ($fwProfile in $fwProfiles) {
                    $desiredEnabled = $baseline.firewall.enabled.($fwProfile.Name.ToLower())
                    if ($null -ne $desiredEnabled -and $fwProfile.Enabled -ne $desiredEnabled) {
                        $diff.Add(@{
                                Type         = 'firewall'
                                Name         = "Firewall-$($fwProfile.Name)"
                                Profile      = $fwProfile.Name
                                Description  = "Windows Firewall $($fwProfile.Name) profile"
                                CurrentState = $fwProfile.Enabled
                                DesiredState = $desiredEnabled
                            })
                        Write-Log -Level WARN -Component SEC-AUDIT -Message "Firewall $($fwProfile.Name) profile mismatch"
                    }
                }
            }
            catch {
                Write-Log -Level WARN -Component SEC-AUDIT -Message "Firewall query failed: $_"
                $diff.Add(@{
                        Type         = 'firewall'
                        Name         = 'FirewallStatusUnknown'
                        Profile      = 'Domain,Private,Public'
                        Description  = 'Firewall status could not be verified'
                        CurrentState = 'Unknown'
                        DesiredState = $true
                    })
            }
        }

        # 5. Services that must be running
        foreach ($svcName in $baseline.services.ensureRunning) {
            try {
                $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
                if ($svc -and $svc.Status -ne 'Running') {
                    $diff.Add(@{
                            Type         = 'service'
                            Name         = $svcName
                            ServiceName  = $svcName
                            Action       = 'EnsureRunning'
                            Description  = "Service $svcName must be Running"
                            CurrentState = $svc.Status.ToString()
                            DesiredState = 'Running'
                        })
                }
            }
            catch { Write-Log -Level WARN -Component SEC-AUDIT -Message "Service query failed '$svcName': $_" }
        }

        # 6. Services that must be disabled
        foreach ($svcName in $baseline.services.ensureDisabled) {
            try {
                $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
                if ($svc -and $svc.StartType -ne 'Disabled') {
                    $diff.Add(@{
                            Type         = 'service'
                            Name         = $svcName
                            ServiceName  = $svcName
                            Action       = 'EnsureDisabled'
                            Description  = "Service $svcName must be Disabled"
                            CurrentState = $svc.StartType.ToString()
                            DesiredState = 'Disabled'
                        })
                }
            }
            catch { Write-Log -Level WARN -Component SEC-AUDIT -Message "Service query failed '$svcName': $_" }
        }

        # 7. Security policy audit via secedit (password/lockout/account rename)
        if ($baseline.securityPolicy) {
            try {
                $cfgPath = Join-Path $env:TEMP 'secaudit_secedit.cfg'
                & secedit /export /cfg $cfgPath /quiet 2>&1 | Out-Null
                $cfgContent = Get-Content -Path $cfgPath -Raw -ErrorAction Stop

                # Password / lockout numeric policies
                $policyChecks = @(
                    @{ Key = 'PasswordHistorySize'; Section = 'System Access'; CfgName = 'PasswordHistorySize'; Compare = 'ge' }
                    @{ Key = 'MinimumPasswordAge'; Section = 'System Access'; CfgName = 'MinimumPasswordAge'; Compare = 'ge' }
                    @{ Key = 'MinimumPasswordLength'; Section = 'System Access'; CfgName = 'MinimumPasswordLength'; Compare = 'ge' }
                    @{ Key = 'LockoutDuration'; Section = 'System Access'; CfgName = 'LockoutDuration'; Compare = 'ge' }
                    @{ Key = 'LockoutBadCount'; Section = 'System Access'; CfgName = 'LockoutBadCount'; Compare = 'le' }
                    @{ Key = 'ResetLockoutCount'; Section = 'System Access'; CfgName = 'ResetLockoutCount'; Compare = 'ge' }
                )
                foreach ($pc in $policyChecks) {
                    $desired = $baseline.securityPolicy.($pc.Key)
                    if ($null -eq $desired) { continue }
                    $current = $null
                    if ($cfgContent -match "(?m)^\s*$($pc.CfgName)\s*=\s*(\d+)") {
                        $current = [int]$Matches[1]
                    }
                    $mismatch = if ($null -eq $current) { $true }
                    elseif ($pc.Compare -eq 'ge') { $current -lt $desired }
                    elseif ($pc.Compare -eq 'le') { $current -gt $desired -or $current -eq 0 }
                    else { "$current" -ne "$desired" }
                    if ($mismatch) {
                        $diff.Add(@{
                                Type         = 'securitypolicy'
                                Name         = $pc.Key
                                CfgName      = $pc.CfgName
                                Description  = "Security policy: $($pc.Key) should be $desired"
                                CurrentState = $current
                                DesiredState = $desired
                            })
                        Write-Log -Level WARN -Component SEC-AUDIT -Message "SecPolicy mismatch: $($pc.Key) current=$current desired=$desired"
                    }
                }

                # Account rename checks
                foreach ($renameKey in @('NewAdministratorName', 'NewGuestName')) {
                    $desired = $baseline.securityPolicy.$renameKey
                    if (-not $desired) { continue }
                    $current = $null
                    if ($cfgContent -match "(?m)^\s*$renameKey\s*=\s*""?(.+?)""?\s*$") {
                        $current = $Matches[1].Trim('"')
                    }
                    if ($current -ne $desired) {
                        $diff.Add(@{
                                Type         = 'securitypolicy'
                                Name         = $renameKey
                                CfgName      = $renameKey
                                Description  = "Account rename: $renameKey should be '$desired'"
                                CurrentState = $current
                                DesiredState = "`"$desired`""
                            })
                        Write-Log -Level WARN -Component SEC-AUDIT -Message "Account rename needed: $renameKey current='$current' desired='$desired'"
                    }
                }
                Remove-Item -Path $cfgPath -Force -ErrorAction SilentlyContinue
            }
            catch { Write-Log -Level WARN -Component SEC-AUDIT -Message "Security policy (secedit) query failed: $_" }
        }

        # 8. Audit policy check (array-based with per-subcategory success/failure)
        if ($baseline.auditPolicy -and $baseline.auditPolicy -is [System.Collections.IEnumerable]) {
            try {
                $auditpolOutput = & auditpol /get /category:* 2>&1 | Out-String
                foreach ($ap in $baseline.auditPolicy) {
                    $subcategory = $ap.subcategory
                    $wantSuccess = if ($null -ne $ap.success) { $ap.success } else { $false }
                    $wantFailure = if ($null -ne $ap.failure) { $ap.failure } else { $false }
                    $desiredStr = @(
                        $(if ($wantSuccess) { 'Success' })
                        $(if ($wantFailure) { 'Failure' })
                    ) -join ' and '
                    if (-not $desiredStr) { $desiredStr = 'No Auditing' }

                    # Parse current setting from auditpol output
                    $currentStr = 'Unknown'
                    if ($auditpolOutput -match "(?m)^\s*$([regex]::Escape($subcategory))\s+(.+)$") {
                        $currentStr = $Matches[1].Trim()
                    }
                    $hasSuccess = $currentStr -match 'Success'
                    $hasFailure = $currentStr -match 'Failure'
                    if ($hasSuccess -ne $wantSuccess -or $hasFailure -ne $wantFailure) {
                        $diff.Add(@{
                                Type         = 'auditpolicy'
                                Name         = $subcategory
                                Subcategory  = $subcategory
                                Success      = $wantSuccess
                                Failure      = $wantFailure
                                Description  = "Audit policy '$subcategory' should be: $desiredStr"
                                CurrentState = $currentStr
                                DesiredState = $desiredStr
                            })
                        Write-Log -Level WARN -Component SEC-AUDIT -Message "Audit policy mismatch: $subcategory current='$currentStr' desired='$desiredStr'"
                    }
                }
            }
            catch { Write-Log -Level WARN -Component SEC-AUDIT -Message "Audit policy query failed: $_" }
        }

        Write-Log -Level INFO -Component SEC-AUDIT -Message "Security gaps: $($diff.Count)"

        # 9. Save diff
        Save-DiffList -ModuleName 'SecurityEnhancement' -DiffList $diff.ToArray()

        # 10. Persist
        $auditPath = Get-TempPath -Category 'data' -FileName 'security-audit.json'
        @{ Timestamp = (Get-Date -Format 'o'); Gaps = $diff.ToArray() } `
        | ConvertTo-Json -Depth 8 | Set-Content -Path $auditPath -Encoding UTF8 -Force

        $status = if ($diff.Count -eq 0) { 'Success' } else { 'Warning' }
        Write-Log -Level INFO -Component SEC-AUDIT -Message "Security audit complete: $($diff.Count) gaps"
        return New-ModuleResult -ModuleName 'SecurityAudit' -Status $status `
            -ItemsDetected $diff.Count `
            -Message "$($diff.Count) security settings need attention"
    }
    catch {
        Write-Log -Level ERROR -Component SEC-AUDIT -Message "Audit failed: $_"
        return New-ModuleResult -ModuleName 'SecurityAudit' -Status 'Failed' -Errors @($_.ToString())
    }
}

Export-ModuleMember -Function 'Invoke-SecurityAudit'
