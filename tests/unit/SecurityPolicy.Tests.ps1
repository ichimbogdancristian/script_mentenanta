#Requires -Version 7.0
<#
    Unit tests for Compare-SecurityPolicyBaseline (modules/core/Maintenance.psm1).

    This covers CIS sections 1.1 (password policy) and 1.2 (account lockout), which are NOT
    registry-backed - they live in the local security policy, readable only via
    `secedit /export`. The baseline declared them for a long time before any module read
    them, so every rule in those sections stayed non-compliant no matter how many runs
    succeeded.

    Get-SecurityPolicyExport (which shells out to secedit.exe) is mocked, so these tests
    are deterministic and need no elevation.

    THE load-bearing case: LockoutBadCount is "N or fewer BUT NOT ZERO". Zero disables
    lockout entirely and fails the benchmark, so a naive "is it <= desired" check would
    score the least secure possible setting as the most compliant one.
#>

BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:RepoRoot 'modules\core\Maintenance.psm1') -Force -Global -ErrorAction Stop
}

Describe 'Compare-SecurityPolicyBaseline' {

    Context 'AtLeast rules (password history, ages, length, lockout duration)' {
        It 'reports compliant when the current value meets the minimum' {
            InModuleScope Maintenance {
                Mock Get-SecurityPolicyExport { @{ MinimumPasswordLength = '14' } }
                $d = @(Compare-SecurityPolicyBaseline -Baseline @{ MinimumPasswordLength = 14 })
                $d.Count | Should -Be 0
            }
        }

        It 'reports compliant when the current value EXCEEDS the minimum' {
            InModuleScope Maintenance {
                Mock Get-SecurityPolicyExport { @{ MinimumPasswordLength = '20' } }
                $d = @(Compare-SecurityPolicyBaseline -Baseline @{ MinimumPasswordLength = 14 })
                $d.Count | Should -Be 0
            }
        }

        It 'queues an item when the current value is below the minimum' {
            InModuleScope Maintenance {
                Mock Get-SecurityPolicyExport { @{ MinimumPasswordLength = '8' } }
                $d = @(Compare-SecurityPolicyBaseline -Baseline @{ MinimumPasswordLength = 14 })
                $d.Count | Should -Be 1
                $d[0].Type | Should -Be 'secpolicy'
                $d[0].Name | Should -Be 'MinimumPasswordLength'
                $d[0].CurrentState | Should -Be '8'
                $d[0].DesiredState | Should -Be '14'
                $d[0].DesiredValue | Should -Be 14
            }
        }

        It 'applies the AtLeast rule to every documented setting' {
            InModuleScope Maintenance {
                Mock Get-SecurityPolicyExport {
                    @{ PasswordHistorySize = '0'; MinimumPasswordAge = '0'
                        MinimumPasswordLength = '0'; LockoutDuration = '0'; ResetLockoutCount = '0'
                    }
                }
                $d = @(Compare-SecurityPolicyBaseline -Baseline @{
                        PasswordHistorySize = 24; MinimumPasswordAge = 1
                        MinimumPasswordLength = 14; LockoutDuration = 15; ResetLockoutCount = 15
                    })
                $d.Count | Should -Be 5
            }
        }
    }

    Context 'LockoutBadCount: AtMostNonZero (the load-bearing rule)' {
        It 'treats 0 as NON-compliant - 0 disables lockout entirely' {
            InModuleScope Maintenance {
                Mock Get-SecurityPolicyExport { @{ LockoutBadCount = '0' } }
                $d = @(Compare-SecurityPolicyBaseline -Baseline @{ LockoutBadCount = 5 })
                $d.Count | Should -Be 1 -Because '0 means lockout is OFF, which fails the benchmark'
                $d[0].CurrentState | Should -Be '0'
                $d[0].DesiredState | Should -Be '5'
            }
        }

        It 'accepts a value at the threshold' {
            InModuleScope Maintenance {
                Mock Get-SecurityPolicyExport { @{ LockoutBadCount = '5' } }
                @(Compare-SecurityPolicyBaseline -Baseline @{ LockoutBadCount = 5 }).Count | Should -Be 0
            }
        }

        It 'accepts a stricter (lower, non-zero) value' {
            InModuleScope Maintenance {
                Mock Get-SecurityPolicyExport { @{ LockoutBadCount = '3' } }
                @(Compare-SecurityPolicyBaseline -Baseline @{ LockoutBadCount = 5 }).Count | Should -Be 0
            }
        }

        It 'queues a value above the threshold' {
            InModuleScope Maintenance {
                Mock Get-SecurityPolicyExport { @{ LockoutBadCount = '10' } }
                @(Compare-SecurityPolicyBaseline -Baseline @{ LockoutBadCount = 5 }).Count | Should -Be 1
            }
        }
    }

    Context 'unreadable or missing current values' {
        It 'queues the item and marks it <unset> when the value is absent from the export' {
            InModuleScope Maintenance {
                Mock Get-SecurityPolicyExport { @{ SomethingElse = '1' } }
                $d = @(Compare-SecurityPolicyBaseline -Baseline @{ MinimumPasswordLength = 14 })
                $d.Count | Should -Be 1
                $d[0].CurrentState | Should -Be '<unset>'
            }
        }

        It 'queues the item when the value is non-numeric' {
            InModuleScope Maintenance {
                Mock Get-SecurityPolicyExport { @{ MinimumPasswordLength = 'garbage' } }
                $d = @(Compare-SecurityPolicyBaseline -Baseline @{ MinimumPasswordLength = 14 })
                $d.Count | Should -Be 1
                $d[0].CurrentState | Should -Be '<unset>'
            }
        }

        It 'returns nothing when secedit produced no output at all' {
            # A failed export must not be read as "everything is non-compliant" and trigger
            # a blind re-apply of the whole policy.
            InModuleScope Maintenance {
                Mock Get-SecurityPolicyExport { @{} }
                @(Compare-SecurityPolicyBaseline -Baseline @{ MinimumPasswordLength = 14 }).Count | Should -Be 0
            }
        }
    }

    Context 'baseline scoping' {
        It 'returns nothing for a null baseline' {
            InModuleScope Maintenance {
                @(Compare-SecurityPolicyBaseline -Baseline $null).Count | Should -Be 0
            }
        }

        It 'ignores baseline keys that are not tracked rules' {
            InModuleScope Maintenance {
                Mock Get-SecurityPolicyExport { @{ MinimumPasswordLength = '14' } }
                $d = @(Compare-SecurityPolicyBaseline -Baseline @{
                        MinimumPasswordLength = 14
                        SomeUntrackedSetting  = 999
                    })
                $d.Count | Should -Be 0
            }
        }

        It 'deliberately ignores account RENAMING entries' {
            # NewAdministratorName / NewGuestName are intentionally not applied: none of the
            # tracked CIS checks test for them and they are hard to undo unattended.
            InModuleScope Maintenance {
                Mock Get-SecurityPolicyExport { @{ NewAdministratorName = 'Administrator' } }
                $d = @(Compare-SecurityPolicyBaseline -Baseline @{
                        NewAdministratorName = 'RenamedAdmin'
                        NewGuestName         = 'RenamedGuest'
                    })
                $d.Count | Should -Be 0 -Because 'account renaming is a deliberate non-goal'
            }
        }
    }

    Context 'emitted item shape (consumed by Invoke-SecurityPolicyChangeItem)' {
        It 'emits every field the apply side needs' {
            InModuleScope Maintenance {
                Mock Get-SecurityPolicyExport { @{ LockoutBadCount = '0' } }
                $item = @(Compare-SecurityPolicyBaseline -Baseline @{ LockoutBadCount = 5 })[0]
                foreach ($k in 'Type', 'Name', 'SettingName', 'CurrentState', 'DesiredState', 'DesiredValue', 'Description') {
                    $item.ContainsKey($k) | Should -BeTrue -Because "Invoke-SecurityPolicyChangeItem reads '$k'"
                }
                $item.SettingName | Should -Be 'LockoutBadCount'
                $item.DesiredValue | Should -BeOfType [int]
            }
        }
    }
}
