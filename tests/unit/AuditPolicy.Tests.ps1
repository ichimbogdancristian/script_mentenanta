#Requires -Version 7.0
<#
    Unit tests for Compare-AuditPolicyBaseline (modules/core/Maintenance.psm1).

    Covers CIS section 17 (advanced audit policy), which - like the password policy - is not
    registry-backed. It is readable and writable only through auditpol.exe.

    The behaviour that matters most here is the FAIL-OPEN one: auditpol's /r output is
    LOCALISED. The parser matches English inclusion strings ('Success and Failure', etc.),
    and when it cannot match, it must queue the item ANYWAY. auditpol /set is idempotent,
    so a needless re-apply is harmless while a missed one silently leaves the machine
    non-compliant. These tests pin that direction down.

    auditpol.exe is mocked so the tests are deterministic and need no elevation. Note that
    a mock cannot set $LASTEXITCODE the way a real native command does, so the mocked calls
    exercise the "could not read current state" path - which is exactly the path the
    fail-open rule governs.
#>

BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:RepoRoot 'modules\core\Maintenance.psm1') -Force -Global -ErrorAction Stop
}

Describe 'Compare-AuditPolicyBaseline' {

    Context 'fail-open behaviour when current state is unreadable' {
        It 'queues the item when auditpol output cannot be parsed' {
            InModuleScope Maintenance {
                Mock auditpol.exe { @('gibberish that is not CSV') }
                $d = @(Compare-AuditPolicyBaseline -Baseline @(
                        @{ subcategory = 'Credential Validation'; success = $true; failure = $true; cis = '17.1.1' }
                    ))
                $d.Count | Should -Be 1 -Because 'auditpol /set is idempotent - a needless re-apply beats a missed one'
                $d[0].CurrentState | Should -Be '<unreadable>'
            }
        }

        It 'queues the item when auditpol throws' {
            InModuleScope Maintenance {
                Mock auditpol.exe { throw 'access denied' }
                $d = @(Compare-AuditPolicyBaseline -Baseline @(
                        @{ subcategory = 'Logon'; success = $true; failure = $false }
                    ))
                $d.Count | Should -Be 1
            }
        }

        It 'queues the item for localised (non-English) inclusion strings' {
            InModuleScope Maintenance {
                # German-style output: the inclusion setting will not match the English regex.
                Mock auditpol.exe { @('Rechner,Systemrichtlinie,Anmelden,{0CCE9215-69AE-11D9-BED3-505054503030},Erfolg und Fehler,,') }
                $d = @(Compare-AuditPolicyBaseline -Baseline @(
                        @{ subcategory = 'Anmelden'; success = $true; failure = $true }
                    ))
                $d.Count | Should -Be 1 -Because 'a localised machine must not be silently skipped'
            }
        }
    }

    Context 'desired-state string mapping' {
        BeforeEach {
            InModuleScope Maintenance { Mock auditpol.exe { @('unparseable') } }
        }

        It 'maps success+failure to "Success and Failure"' {
            InModuleScope Maintenance {
                $d = @(Compare-AuditPolicyBaseline -Baseline @(
                        @{ subcategory = 'S'; success = $true; failure = $true }))
                $d[0].DesiredState | Should -Be 'Success and Failure'
            }
        }

        It 'maps success only to "Success"' {
            InModuleScope Maintenance {
                $d = @(Compare-AuditPolicyBaseline -Baseline @(
                        @{ subcategory = 'S'; success = $true; failure = $false }))
                $d[0].DesiredState | Should -Be 'Success'
            }
        }

        It 'maps failure only to "Failure"' {
            InModuleScope Maintenance {
                $d = @(Compare-AuditPolicyBaseline -Baseline @(
                        @{ subcategory = 'S'; success = $false; failure = $true }))
                $d[0].DesiredState | Should -Be 'Failure'
            }
        }

        It 'maps neither to "No Auditing"' {
            InModuleScope Maintenance {
                $d = @(Compare-AuditPolicyBaseline -Baseline @(
                        @{ subcategory = 'S'; success = $false; failure = $false }))
                $d[0].DesiredState | Should -Be 'No Auditing'
            }
        }
    }

    Context 'baseline handling' {
        It 'returns nothing for a null baseline' {
            InModuleScope Maintenance {
                @(Compare-AuditPolicyBaseline -Baseline $null).Count | Should -Be 0
            }
        }

        It 'skips entries with no subcategory' {
            InModuleScope Maintenance {
                Mock auditpol.exe { @('unparseable') }
                $d = @(Compare-AuditPolicyBaseline -Baseline @(
                        @{ success = $true; failure = $true },
                        @{ subcategory = ''; success = $true },
                        @{ subcategory = 'Valid'; success = $true }
                    ))
                $d.Count | Should -Be 1
                $d[0].Subcategory | Should -Be 'Valid'
            }
        }

        It 'processes every entry in a multi-subcategory baseline' {
            InModuleScope Maintenance {
                Mock auditpol.exe { @('unparseable') }
                $subs = 'Credential Validation', 'Logon', 'Logoff', 'Special Logon'
                $baseline = $subs | ForEach-Object { @{ subcategory = $_; success = $true; failure = $true } }
                $d = @(Compare-AuditPolicyBaseline -Baseline $baseline)
                $d.Count | Should -Be $subs.Count
            }
        }

        It 'accepts a single (non-array) baseline entry' {
            InModuleScope Maintenance {
                Mock auditpol.exe { @('unparseable') }
                $d = @(Compare-AuditPolicyBaseline -Baseline @{ subcategory = 'Solo'; success = $true })
                $d.Count | Should -Be 1
            }
        }
    }

    Context 'emitted item shape (consumed by Invoke-AuditPolicyChangeItem)' {
        It 'emits every field the apply side needs' {
            InModuleScope Maintenance {
                Mock auditpol.exe { @('unparseable') }
                $item = @(Compare-AuditPolicyBaseline -Baseline @(
                        @{ subcategory = 'Credential Validation'; success = $true; failure = $true; cis = '17.1.1' }))[0]
                foreach ($k in 'Type', 'Name', 'Subcategory', 'WantSuccess', 'WantFailure', 'CurrentState', 'DesiredState', 'Description') {
                    $item.ContainsKey($k) | Should -BeTrue -Because "Invoke-AuditPolicyChangeItem reads '$k'"
                }
                $item.Type | Should -Be 'auditpolicy'
                $item.Subcategory | Should -Be 'Credential Validation'
                $item.CIS | Should -Be '17.1.1'
                $item.WantSuccess | Should -BeOfType [bool]
            }
        }
    }
}
