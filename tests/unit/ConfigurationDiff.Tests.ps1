#Requires -Version 7.0
<#
    Unit tests for the Phase A2/A3 helpers extracted out of Invoke-SystemConfigurationAudit
    (Phase 2 of ARCHITECTURE_AND_EXTENSION_GUIDE.md).

    These were previously ~145 lines buried inside a 446-line function and could not be
    tested at all. Extraction is what makes them reachable - that is the point of it.

    The invariant that matters most is the DISCRIMINATOR TAG. Type2's Invoke-SystemConfiguration
    dispatches on ConfigType, and Get-ConfigItemRank sorts on it. An item that arrives untagged
    falls to the switch's default branch and to rank 3 - silently applied in the wrong phase,
    or not at all. Every item these functions emit must carry the right ConfigType.

    Live-system cmdlets (Get-Service, Get-MpComputerStatus, Get-NetFirewallProfile) and the
    shared Compare-* helpers are mocked, so the suite stays deterministic and unelevated.
#>

BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:RepoRoot 'modules\core\Maintenance.psm1') -Force -Global -ErrorAction Stop
    Import-Module (Join-Path $script:RepoRoot 'modules\type1\SystemConfigurationAudit.psm1') -Force -ErrorAction Stop
}

Describe 'Get-SecurityConfigurationDiff' {

    Context 'degenerate input' {
        It 'returns an empty array for a null baseline' {
            InModuleScope SystemConfigurationAudit {
                $r = @(Get-SecurityConfigurationDiff -Baseline $null -SkipPasswordPolicy $false -SkipAuditPolicy $false)
                $r.Count | Should -Be 0
            }
        }

        It 'returns an empty array for an empty baseline' {
            InModuleScope SystemConfigurationAudit {
                Mock Get-Service { [pscustomobject]@{ Name = 'Sysmon64' } }
                $r = @(Get-SecurityConfigurationDiff -Baseline @{} -SkipPasswordPolicy $true -SkipAuditPolicy $true)
                $r.Count | Should -Be 0
            }
        }
    }

    Context 'discriminator tagging' {
        It "tags registry-sourced items ConfigType 'security'" {
            InModuleScope SystemConfigurationAudit {
                Mock Get-Service { [pscustomobject]@{ Name = 'Sysmon64' } }
                Mock Compare-RegistryBaselineWithFallback {
                    @(@{ Type = 'registry'; Name = 'SomeValue'; CurrentState = 0; DesiredState = 1 })
                }
                $r = @(Get-SecurityConfigurationDiff -Baseline @{ registry = @(@{ path = 'HKLM:\X'; name = 'Y' }) } `
                        -SkipPasswordPolicy $true -SkipAuditPolicy $true)
                $r.Count | Should -Be 1
                $r[0].ConfigType | Should -Be 'security' -Because 'Type2 dispatches on ConfigType'
            }
        }

        It "tags securityPolicy items ConfigType 'security'" {
            InModuleScope SystemConfigurationAudit {
                Mock Get-Service { [pscustomobject]@{ Name = 'Sysmon64' } }
                Mock Compare-SecurityPolicyBaseline { @(@{ Type = 'secpolicy'; Name = 'LockoutBadCount' }) }
                $r = @(Get-SecurityConfigurationDiff -Baseline @{ securityPolicy = @{ LockoutBadCount = 5 } } `
                        -SkipPasswordPolicy $false -SkipAuditPolicy $true)
                $r.Count | Should -Be 1
                $r[0].ConfigType | Should -Be 'security'
                $r[0].Type | Should -Be 'secpolicy'
            }
        }

        It "tags auditPolicy items ConfigType 'security'" {
            InModuleScope SystemConfigurationAudit {
                Mock Get-Service { [pscustomobject]@{ Name = 'Sysmon64' } }
                Mock Compare-AuditPolicyBaseline { @(@{ Type = 'auditpolicy'; Name = 'Audit: Logon' }) }
                $r = @(Get-SecurityConfigurationDiff -Baseline @{ auditPolicy = @(@{ subcategory = 'Logon' }) } `
                        -SkipPasswordPolicy $true -SkipAuditPolicy $false)
                $r.Count | Should -Be 1
                $r[0].ConfigType | Should -Be 'security'
            }
        }
    }

    Context 'skip flags' {
        It 'does not consult the password policy when SkipPasswordPolicy is set' {
            InModuleScope SystemConfigurationAudit {
                Mock Get-Service { [pscustomobject]@{ Name = 'Sysmon64' } }
                Mock Compare-SecurityPolicyBaseline { @(@{ Type = 'secpolicy'; Name = 'X' }) }
                $r = @(Get-SecurityConfigurationDiff -Baseline @{ securityPolicy = @{ LockoutBadCount = 5 } } `
                        -SkipPasswordPolicy $true -SkipAuditPolicy $true)
                $r.Count | Should -Be 0
                Should -Invoke Compare-SecurityPolicyBaseline -Times 0 -Exactly
            }
        }

        It 'does not consult the audit policy when SkipAuditPolicy is set' {
            InModuleScope SystemConfigurationAudit {
                Mock Get-Service { [pscustomobject]@{ Name = 'Sysmon64' } }
                Mock Compare-AuditPolicyBaseline { @(@{ Type = 'auditpolicy'; Name = 'X' }) }
                $r = @(Get-SecurityConfigurationDiff -Baseline @{ auditPolicy = @(@{ subcategory = 'Logon' }) } `
                        -SkipPasswordPolicy $true -SkipAuditPolicy $true)
                $r.Count | Should -Be 0
                Should -Invoke Compare-AuditPolicyBaseline -Times 0 -Exactly
            }
        }
    }

    Context 'Sysmon presence' {
        It 'queues a Sysmon install when the service is absent' {
            InModuleScope SystemConfigurationAudit {
                Mock Get-Service { $null }
                $r = @(Get-SecurityConfigurationDiff -Baseline @{} -SkipPasswordPolicy $true -SkipAuditPolicy $true)
                $r.Count | Should -Be 1
                $r[0].Type | Should -Be 'sysmon'
                $r[0].ConfigType | Should -Be 'security'
            }
        }

        It 'queues nothing when the Sysmon service is present' {
            InModuleScope SystemConfigurationAudit {
                Mock Get-Service { [pscustomobject]@{ Name = 'Sysmon64' } }
                @(Get-SecurityConfigurationDiff -Baseline @{} -SkipPasswordPolicy $true -SkipAuditPolicy $true).Count |
                    Should -Be 0
            }
        }
    }

    Context 'REGRESSION: return shape must survive @() at the call site' {
        # Found by this test file. The first version of these functions used
        # `return , $items.ToArray()`, copying the idiom from Get-DiffList. That is WRONG
        # here: the comma emits the array as ONE pipeline element, so `@(Get-...)` yields a
        # 1-element array CONTAINING the array rather than the items. The callers inside
        # Invoke-SystemConfigurationAudit do `foreach ($item in @(Get-...)) { $diff.Add($item) }`,
        # so they would have tried to add a Hashtable[] to a List[hashtable].
        # Get-DiffList gets away with the comma only because ITS callers use plain assignment.
        It 'yields the ITEMS, not a nested array, when wrapped in @()' {
            InModuleScope SystemConfigurationAudit {
                Mock Get-Service { $null }   # yields exactly one item (the Sysmon queue)
                $r = @(Get-SecurityConfigurationDiff -Baseline @{} -SkipPasswordPolicy $true -SkipAuditPolicy $true)
                $r.Count | Should -Be 1
                $r[0] | Should -BeOfType [hashtable] -Because 'a nested array here would break $diff.Add()'
                $r[0].Type | Should -Be 'sysmon'
            }
        }

        It 'yields zero items - not one empty array - when there is nothing to do' {
            InModuleScope SystemConfigurationAudit {
                Mock Get-Service { [pscustomobject]@{ Name = 'Sysmon64' } }
                @(Get-SecurityConfigurationDiff -Baseline $null -SkipPasswordPolicy $true -SkipAuditPolicy $true).Count |
                    Should -Be 0
                @(Get-TelemetryConfigurationDiff -Baseline $null).Count | Should -Be 0
            }
        }
    }
}

Describe 'Get-RestorePointConfigurationDiff' {
    # This one guards the rollback safety net. If the 'create' item stops being queued
    # unconditionally, two things break at once: the run loses its restore point, AND the
    # SystemConfiguration diff can become empty - at which point Stage 2 skips the whole pair
    # and none of the security/telemetry/optimization work runs either.

    Context 'the create item is unconditional' {
        It 'queues exactly one create when there are no existing restore points' {
            InModuleScope SystemConfigurationAudit {
                Mock Get-SystemRestorePointList { @() }
                $r = Get-RestorePointConfigurationDiff -SkipRestorePoint $false -MinimumToKeep 5
                $create = @($r.Items | Where-Object { $_.Action -eq 'create' })
                $create.Count | Should -Be 1
                $create[0].ConfigType | Should -Be 'restorepoint'
                $r.ToRemove | Should -Be 0
            }
        }

        It 'still queues the create when enumeration THROWS' {
            # A failed query must not cost the run its safety net.
            InModuleScope SystemConfigurationAudit {
                Mock Get-SystemRestorePointList { throw 'WMI unavailable' }
                $r = Get-RestorePointConfigurationDiff -SkipRestorePoint $false
                @($r.Items | Where-Object { $_.Action -eq 'create' }).Count | Should -Be 1 `
                    -Because 'the rollback net must survive a failed enumeration'
                @($r.Items | Where-Object { $_.Action -eq 'remove' }).Count | Should -Be 0
            }
        }

        It 'queues nothing at all when management is skipped by config' {
            InModuleScope SystemConfigurationAudit {
                Mock Get-SystemRestorePointList { @() }
                $r = Get-RestorePointConfigurationDiff -SkipRestorePoint $true
                @($r.Items).Count | Should -Be 0
                Should -Invoke Get-SystemRestorePointList -Times 0 -Exactly
            }
        }
    }

    Context 'pruning' {
        It 'keeps MinimumToKeep and queues the rest for removal' {
            InModuleScope SystemConfigurationAudit {
                Mock Get-SystemRestorePointList {
                    1..8 | ForEach-Object {
                        [pscustomobject]@{ SequenceNumber = $_; ShadowId = "id$_"; Description = "rp$_"
                            CreationTimeText = '2026-08-01'; EventType = 'BEGIN'; RestorePointType = 'MODIFY'
                        }
                    }
                }
                $r = Get-RestorePointConfigurationDiff -SkipRestorePoint $false -MinimumToKeep 5
                $r.ToRemove | Should -Be 3 -Because '8 points minus the 5 newest kept'
                @($r.Items | Where-Object { $_.Action -eq 'remove' }).Count | Should -Be 3
                @($r.Items | Where-Object { $_.Action -eq 'create' }).Count | Should -Be 1
                @($r.RestorePoints).Count | Should -Be 8 -Because 'the caller needs these for the report'
            }
        }

        It 'prunes nothing when the count is at or below the threshold' {
            InModuleScope SystemConfigurationAudit {
                Mock Get-SystemRestorePointList {
                    1..5 | ForEach-Object { [pscustomobject]@{ SequenceNumber = $_; Description = "rp$_" } }
                }
                $r = Get-RestorePointConfigurationDiff -SkipRestorePoint $false -MinimumToKeep 5
                $r.ToRemove | Should -Be 0
                @($r.Items).Count | Should -Be 1 -Because 'only the create item'
            }
        }
    }

    Context 'result shape' {
        It 'returns a hashtable carrying Items, RestorePoints and ToRemove' {
            InModuleScope SystemConfigurationAudit {
                Mock Get-SystemRestorePointList { @() }
                $r = Get-RestorePointConfigurationDiff -SkipRestorePoint $false
                $r | Should -BeOfType [hashtable]
                foreach ($k in 'Items', 'RestorePoints', 'ToRemove') {
                    $r.ContainsKey($k) | Should -BeTrue -Because "the caller reads '$k'"
                }
            }
        }
    }
}

Describe 'Get-OptimizationConfigurationDiff' {

    It 'returns an empty array for a null baseline' {
        InModuleScope SystemConfigurationAudit {
            @(Get-OptimizationConfigurationDiff -Baseline $null -OSContext @{ IsWindows11 = $true }).Count |
                Should -Be 0
        }
    }

    It 'returns an empty array when the baseline has no .common block' {
        InModuleScope SystemConfigurationAudit {
            @(Get-OptimizationConfigurationDiff -Baseline @{ windows11 = @{} } -OSContext @{ IsWindows11 = $true }).Count |
                Should -Be 0
        }
    }

    It "tags service items ConfigType 'optimization'" {
        InModuleScope SystemConfigurationAudit {
            Mock Compare-ServiceBaseline { @(@{ Type = 'service'; Name = 'SysMain' }) }
            $r = @(Get-OptimizationConfigurationDiff `
                    -Baseline @{ common = @{ services = @{ safeToDisable = @('SysMain') } } } `
                    -OSContext @{ IsWindows11 = $true })
            @($r | Where-Object { $_.Type -eq 'service' }).Count | Should -BeGreaterThan 0
            foreach ($i in $r) { $i.ConfigType | Should -Be 'optimization' }
        }
    }

    It 'merges the OS-specific service list with the common one' {
        InModuleScope SystemConfigurationAudit {
            $script:seen = $null
            Mock Compare-ServiceBaseline { $script:seen = $ServiceNames; @() }
            $null = Get-OptimizationConfigurationDiff -Baseline @{
                common    = @{ services = @{ safeToDisable = @('CommonSvc') } }
                windows11 = @{ services = @{ safeToDisable = @('Win11Svc') } }
                windows10 = @{ services = @{ safeToDisable = @('Win10Svc') } }
            } -OSContext @{ IsWindows11 = $true }
            $script:seen | Should -Contain 'CommonSvc'
            $script:seen | Should -Contain 'Win11Svc'
            $script:seen | Should -Not -Contain 'Win10Svc' -Because 'OSContext says Windows 11'
        }
    }

    It 'picks the windows10 list when OSContext is not Windows 11' {
        InModuleScope SystemConfigurationAudit {
            $script:seen = $null
            Mock Compare-ServiceBaseline { $script:seen = $ServiceNames; @() }
            $null = Get-OptimizationConfigurationDiff -Baseline @{
                common    = @{ services = @{ safeToDisable = @('CommonSvc') } }
                windows11 = @{ services = @{ safeToDisable = @('Win11Svc') } }
                windows10 = @{ services = @{ safeToDisable = @('Win10Svc') } }
            } -OSContext @{ IsWindows11 = $false }
            $script:seen | Should -Contain 'Win10Svc'
            $script:seen | Should -Not -Contain 'Win11Svc'
        }
    }
}

Describe 'Get-TelemetryConfigurationDiff' {

    It 'returns an empty array for a null baseline' {
        InModuleScope SystemConfigurationAudit {
            @(Get-TelemetryConfigurationDiff -Baseline $null).Count | Should -Be 0
        }
    }

    It "tags service items ConfigType 'telemetry'" {
        InModuleScope SystemConfigurationAudit {
            Mock Compare-ServiceBaseline { @(@{ Type = 'service'; Name = 'DiagTrack' }) }
            $r = @(Get-TelemetryConfigurationDiff -Baseline @{ services = @{ disable = @('DiagTrack') } })
            $r.Count | Should -Be 1
            $r[0].ConfigType | Should -Be 'telemetry'
        }
    }

    It "tags registry items ConfigType 'telemetry' across every declared group" {
        InModuleScope SystemConfigurationAudit {
            Mock Compare-RegistryBaselineWithFallback { @(@{ Type = 'registry'; Name = 'V' }) }
            $r = @(Get-TelemetryConfigurationDiff -Baseline @{
                    registry = @{
                        telemetry   = @(@{ path = 'HKLM:\A'; name = 'a' })
                        advertising = @(@{ path = 'HKLM:\B'; name = 'b' })
                        cortana     = @(@{ path = 'HKLM:\C'; name = 'c' })
                        privacy     = @(@{ path = 'HKLM:\D'; name = 'd' })
                    }
                })
            $r.Count | Should -Be 4 -Because 'all four registry groups are audited'
            foreach ($i in $r) { $i.ConfigType | Should -Be 'telemetry' }
        }
    }

    It 'ignores registry groups the baseline does not declare' {
        InModuleScope SystemConfigurationAudit {
            Mock Compare-RegistryBaselineWithFallback { @(@{ Type = 'registry'; Name = 'V' }) }
            $r = @(Get-TelemetryConfigurationDiff -Baseline @{
                    registry = @{ telemetry = @(@{ path = 'HKLM:\A'; name = 'a' }) }
                })
            $r.Count | Should -Be 1
        }
    }
}
