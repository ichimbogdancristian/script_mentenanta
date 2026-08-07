#Requires -Version 7.0
<#
    Characterization tests for Invoke-SystemConfiguration (modules/type2/SystemConfiguration.psm1).

    This is Type2 code: it WRITES to the registry, services, Defender, the firewall and the
    restore point store. It had no coverage at all, and it is the next Phase 2 extraction
    target - its four switch arms mutate six enclosing variables ($changed, $errors, $failed,
    $rpCreated, $rpRemoved, $rebootNeeded), so extracting them is a real transformation rather
    than the verbatim move the audit phases were. These tests pin the observable behaviour
    FIRST so that transformation can be verified rather than hoped at.

    Nothing here touches the machine: Get-DiffList and every applier
    (New-SystemRestorePoint, Remove-SystemRestorePoint, Invoke-RegistryChangeItem, ...) is
    mocked, so the tests assert dispatch, ordering and accounting - not real system changes.

    THE ORDERING TEST IS THE IMPORTANT ONE. Get-ConfigItemRank exists because folding the
    restore point into this module removed the orchestrator's ability to sequence it via
    $Stage3Order. Creation must precede every other mutation or the snapshot is of an
    already-modified system; pruning must follow everything or it discards the very rollback
    targets a failed run would need.
#>

BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:RepoRoot 'modules\core\Maintenance.psm1') -Force -Global -ErrorAction Stop
    Import-Module (Join-Path $script:RepoRoot 'modules\type2\SystemConfiguration.psm1') -Force -ErrorAction Stop
}

Describe 'Invoke-SystemConfiguration' {

    Context 'empty diff' {
        It 'returns Skipped without touching anything' {
            InModuleScope SystemConfiguration {
                Mock Get-DiffList { @() }
                Mock New-SystemRestorePoint { $true }
                $r = Invoke-SystemConfiguration
                $r.Status | Should -Be 'Skipped'
                $r.ModuleType | Should -Be 'Type2'
                Should -Invoke New-SystemRestorePoint -Times 0 -Exactly
            }
        }
    }

    Context 'ORDERING - the rollback safety net' {
        It 'creates the restore point before any other change and prunes after all of them' {
            InModuleScope SystemConfiguration {
                $script:order = [System.Collections.Generic.List[string]]::new()
                Mock Get-DiffList {
                    @(
                        # DesiredValue is required: the apply path feeds it to
                        # Test-RegistryValueApplied -ExpectedValue, which is Mandatory.
                        @{ ConfigType = 'optimization'; Type = 'startup'; Name = 'opt1'; RegistryPath = 'HKCU:\X' }
                        @{ ConfigType = 'restorepoint'; Action = 'remove'; Name = 'prune'; ShadowId = 'sid1' }
                        @{ ConfigType = 'telemetry'; Type = 'registry'; Name = 'tel1'; Path = 'HKLM:\T'; DesiredValue = 1 }
                        @{ ConfigType = 'restorepoint'; Action = 'create'; Name = 'create'; Description = 'd' }
                        @{ ConfigType = 'security'; Type = 'registry'; Name = 'sec1'; Path = 'HKLM:\S'; DesiredValue = 1 }
                    )
                }
                Mock New-SystemRestorePoint { $script:order.Add('create'); $true }
                Mock Remove-SystemRestorePoint { $script:order.Add('prune'); $true }
                Mock Backup-RegistryValue { $null }
                Mock Test-RegistryValueApplied { $true }
                Mock Invoke-RegistryChangeItem { $script:order.Add($Item.Name); $true }
                Mock Remove-ItemProperty { $script:order.Add('opt1') }

                $null = Invoke-SystemConfiguration

                $script:order[0] | Should -Be 'create' -Because 'the snapshot must precede every mutation'
                $script:order[-1] | Should -Be 'prune' -Because 'pruning discards rollback targets and must go last'
                $script:order.IndexOf('sec1') | Should -BeLessThan $script:order.IndexOf('tel1')
                $script:order.IndexOf('tel1') | Should -BeLessThan $script:order.IndexOf('opt1')
            }
        }
    }

    Context 'restore point accounting' {
        It 'counts created and removed restore points into ExtraData' {
            InModuleScope SystemConfiguration {
                Mock Get-DiffList {
                    @(
                        @{ ConfigType = 'restorepoint'; Action = 'create'; Name = 'c'; Description = 'd' }
                        @{ ConfigType = 'restorepoint'; Action = 'remove'; Name = 'r1'; ShadowId = 's1' }
                        @{ ConfigType = 'restorepoint'; Action = 'remove'; Name = 'r2'; ShadowId = 's2' }
                    )
                }
                Mock New-SystemRestorePoint { $true }
                Mock Remove-SystemRestorePoint { $true }
                $r = Invoke-SystemConfiguration
                $r.ExtraData.RestorePointsCreated | Should -Be 1
                $r.ExtraData.RestorePointsRemoved | Should -Be 2
                $r.ItemsProcessed | Should -Be 3
            }
        }

        It 'records a failure when the restore point cannot be created but keeps going' {
            # The safety net failing is worth surfacing, but must not stop the run.
            InModuleScope SystemConfiguration {
                Mock Get-DiffList {
                    @(
                        @{ ConfigType = 'restorepoint'; Action = 'create'; Name = 'c'; Description = 'd' }
                        @{ ConfigType = 'security'; Type = 'registry'; Name = 'sec1'; Path = 'HKLM:\S'; DesiredValue = 1 }
                    )
                }
                Mock New-SystemRestorePoint { $false }
                Mock Backup-RegistryValue { $null }
                Mock Test-RegistryValueApplied { $true }
                Mock Invoke-RegistryChangeItem { $true }
                $r = Invoke-SystemConfiguration
                $r.ItemsFailed | Should -Be 1
                $r.ItemsProcessed | Should -Be 1 -Because 'the security change must still be applied'
                $r.Status | Should -Be 'Warning'
                ($r.Errors -join ' ') | Should -Match 'RestorePoint'
            }
        }

        It 'fails a removal that carries no ShadowId' {
            InModuleScope SystemConfiguration {
                Mock Get-DiffList { @(@{ ConfigType = 'restorepoint'; Action = 'remove'; Name = 'noshadow' }) }
                Mock Remove-SystemRestorePoint { $true }
                $r = Invoke-SystemConfiguration
                $r.ItemsFailed | Should -Be 1
                Should -Invoke Remove-SystemRestorePoint -Times 0 -Exactly
                ($r.Errors -join ' ') | Should -Match 'ShadowId'
            }
        }
    }

    Context 'unknown discriminators are surfaced, never silently skipped' {
        It 'records an error for an unknown ConfigType' {
            InModuleScope SystemConfiguration {
                Mock Get-DiffList { @(@{ ConfigType = 'somethingNew'; Type = 'x'; Name = 'weird' }) }
                $r = Invoke-SystemConfiguration
                $r.ItemsFailed | Should -Be 1
                ($r.Errors -join ' ') | Should -Match 'Unknown ConfigType'
            }
        }

        It 'records an error for an unknown restore point action' {
            InModuleScope SystemConfiguration {
                Mock Get-DiffList { @(@{ ConfigType = 'restorepoint'; Action = 'frobnicate'; Name = 'x' }) }
                $r = Invoke-SystemConfiguration
                $r.ItemsFailed | Should -Be 1
                ($r.Errors -join ' ') | Should -Match 'Unknown action'
            }
        }

        It 'records an error for an unknown optimization type' {
            InModuleScope SystemConfiguration {
                Mock Get-DiffList { @(@{ ConfigType = 'optimization'; Type = 'nonsense'; Name = 'x' }) }
                $r = Invoke-SystemConfiguration
                $r.ItemsFailed | Should -Be 1
                ($r.Errors -join ' ') | Should -Match 'Unknown type'
            }
        }
    }

    Context 'status derivation' {
        It 'reports Success when nothing failed' {
            InModuleScope SystemConfiguration {
                Mock Get-DiffList { @(@{ ConfigType = 'restorepoint'; Action = 'create'; Name = 'c'; Description = 'd' }) }
                Mock New-SystemRestorePoint { $true }
                (Invoke-SystemConfiguration).Status | Should -Be 'Success'
            }
        }

        It 'reports Warning when some succeeded and some failed' {
            InModuleScope SystemConfiguration {
                Mock Get-DiffList {
                    @(
                        @{ ConfigType = 'restorepoint'; Action = 'create'; Name = 'c'; Description = 'd' }
                        @{ ConfigType = 'bogus'; Name = 'x' }
                    )
                }
                Mock New-SystemRestorePoint { $true }
                (Invoke-SystemConfiguration).Status | Should -Be 'Warning'
            }
        }

        It 'reports Failed when nothing succeeded' {
            InModuleScope SystemConfiguration {
                Mock Get-DiffList { @(@{ ConfigType = 'bogus'; Name = 'x' }, @{ ConfigType = 'bogus'; Name = 'y' }) }
                (Invoke-SystemConfiguration).Status | Should -Be 'Failed'
            }
        }

        It 'never throws out to the orchestrator when an applier throws' {
            # A module failing must not fail the run - it returns Failed/Warning instead.
            InModuleScope SystemConfiguration {
                Mock Get-DiffList { @(@{ ConfigType = 'restorepoint'; Action = 'create'; Name = 'c'; Description = 'd' }) }
                Mock New-SystemRestorePoint { throw 'catastrophic' }
                $r = $null
                { $script:r = Invoke-SystemConfiguration } | Should -Not -Throw
                $script:r.Status | Should -Be 'Failed'
                $script:r.ItemsFailed | Should -Be 1
            }
        }
    }

    Context 'result contract' {
        It 'always returns a Type2 module result with the counters the report reads' {
            InModuleScope SystemConfiguration {
                Mock Get-DiffList { @(@{ ConfigType = 'restorepoint'; Action = 'create'; Name = 'c'; Description = 'd' }) }
                Mock New-SystemRestorePoint { $true }
                $r = Invoke-SystemConfiguration
                $r.ModuleName | Should -Be 'SystemConfiguration'
                $r.ModuleType | Should -Be 'Type2'
                foreach ($k in 'Status', 'ItemsDetected', 'ItemsProcessed', 'ItemsFailed', 'RebootRequired', 'ExtraData') {
                    $r.ContainsKey($k) | Should -BeTrue
                }
            }
        }
    }
}
