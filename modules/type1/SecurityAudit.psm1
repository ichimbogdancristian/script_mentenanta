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

        Write-Log -Level INFO -Component SEC-AUDIT -Message "Security gaps: $($diff.Count)"

        # 7. Save diff
        Save-DiffList -ModuleName 'SecurityEnhancement' -DiffList $diff.ToArray()

        # 8. Persist
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
