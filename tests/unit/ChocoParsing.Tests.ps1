#Requires -Version 7.0
<#
    Unit tests for ConvertFrom-ChocoOutdatedTable in SoftwareManagementAudit.psm1.

    Regression origin: the parser used to be `$line -match '^(\S+)\|(\S+)\|(\S+)'`. '\S'
    matches '|' as well as everything else, so the greedy groups swallowed a delimiter and
    shifted every field one place left. Because `choco outdated --limit-output` ALWAYS emits
    four fields (name|current|available|pinned), this mis-parsed every chocolatey package on
    every run - it was never an edge case.

    The mangled name went into the diff verbatim and reached Type2, which ran
    `choco upgrade 'chocolatey|2.6.0'`. Chocolatey answered "is not installed. Installing..."
    then "not installed. The package was not found with the source(s) listed", exited 1, and
    Invoke-SoftwareManagement finished Failed with 0 processed.

    The first test below is that exact production row.
#>

BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:RepoRoot 'modules\type1\SoftwareManagementAudit.psm1') -Force -ErrorAction Stop
}

Describe 'ConvertFrom-ChocoOutdatedTable' {

    Context 'the production regression row' {
        It 'splits chocolatey|2.6.0|2.7.3|false into the correct three fields' {
            InModuleScope SoftwareManagementAudit {
                $rows = ConvertFrom-ChocoOutdatedTable -Lines @('chocolatey|2.6.0|2.7.3|false')
                $rows.Count | Should -Be 1
                $rows[0].Name | Should -Be 'chocolatey'
                $rows[0].CurrentVersion | Should -Be '2.6.0'
                $rows[0].AvailableVersion | Should -Be '2.7.3'
            }
        }

        It 'never leaves a delimiter inside the parsed Name' {
            # This is the specific defect: Name came back as 'chocolatey|2.6.0'.
            InModuleScope SoftwareManagementAudit {
                $lines = @(
                    'chocolatey|2.6.0|2.7.3|false'
                    'git|2.44.0|2.45.1|false'
                    '7zip|23.01|24.08|false'
                )
                foreach ($row in (ConvertFrom-ChocoOutdatedTable -Lines $lines)) {
                    $row.Name | Should -Not -Match '\|'
                    $row.CurrentVersion | Should -Not -Match '\|'
                    $row.AvailableVersion | Should -Not -Match '\|'
                }
            }
        }

        It 'never yields the pin flag as a version' {
            InModuleScope SoftwareManagementAudit {
                $rows = ConvertFrom-ChocoOutdatedTable -Lines @('git|2.44.0|2.45.1|false')
                $rows[0].AvailableVersion | Should -Not -BeIn @('true', 'false')
                $rows[0].AvailableVersion | Should -Be '2.45.1'
            }
        }
    }

    # NOTE on asserting an EMPTY result: the function returns `, $rows.ToArray()`, so an empty
    # result is EMITTED as a single object that happens to be an empty array. That makes both
    # `func | Should -HaveCount 0` and `@(func).Count` report 1 - the pipeline/array-subexpression
    # sees one emitted object and does not look inside it. Assign first, then count: `$rows = func`
    # binds $rows to that empty array and `$rows.Count` is 0. This mirrors the real caller,
    # `foreach ($row in (ConvertFrom-ChocoOutdatedTable ...))`, which iterates 0 times for an
    # empty result and once per row otherwise (verified directly against the module).
    Context 'pinned packages' {
        It 'drops a pinned package (a pin means hold this version deliberately)' {
            InModuleScope SoftwareManagementAudit {
                $rows = ConvertFrom-ChocoOutdatedTable -Lines @('notepadplusplus.install|8.6.4|8.6.9|true')
                $rows.Count | Should -Be 0
            }
        }

        It 'keeps unpinned packages alongside pinned ones' {
            InModuleScope SoftwareManagementAudit {
                $rows = ConvertFrom-ChocoOutdatedTable -Lines @(
                    'pinned.pkg|1.0|2.0|true'
                    'normal.pkg|1.0|2.0|false'
                )
                $rows.Count | Should -Be 1
                $rows[0].Name | Should -Be 'normal.pkg'
            }
        }

        It 'treats the pin flag case-insensitively' {
            InModuleScope SoftwareManagementAudit {
                $rows = ConvertFrom-ChocoOutdatedTable -Lines @('pkg|1.0|2.0|True')
                $rows.Count | Should -Be 0
            }
        }
    }

    Context 'non-data and malformed lines' {
        It 'skips banner text, blanks and rows with too few fields' {
            InModuleScope SoftwareManagementAudit {
                $rows = ConvertFrom-ChocoOutdatedTable -Lines @(
                    'Chocolatey v2.6.0'
                    ''
                    '   '
                    'onlytwo|fields'
                    'Outdated Packages'
                    'good.pkg|1.0|2.0|false'
                )
                $rows.Count | Should -Be 1
                $rows[0].Name | Should -Be 'good.pkg'
            }
        }

        It 'accepts a 3-field row (no pin column)' {
            InModuleScope SoftwareManagementAudit {
                $rows = ConvertFrom-ChocoOutdatedTable -Lines @('pkg|1.0|2.0')
                $rows.Count | Should -Be 1
                $rows[0].AvailableVersion | Should -Be '2.0'
            }
        }

        It 'skips a row with an empty name or empty available version' {
            InModuleScope SoftwareManagementAudit {
                $noName = ConvertFrom-ChocoOutdatedTable -Lines @('|1.0|2.0|false')
                $noName.Count | Should -Be 0
                $noVersion = ConvertFrom-ChocoOutdatedTable -Lines @('pkg|1.0||false')
                $noVersion.Count | Should -Be 0
            }
        }

        It 'returns an empty collection for empty input' {
            InModuleScope SoftwareManagementAudit {
                $rows = ConvertFrom-ChocoOutdatedTable -Lines @()
                $rows.Count | Should -Be 0
            }
        }
    }

    Context 'return shape' {
        It 'reports Count 1 for a single row rather than unrolling to a bare hashtable' {
            # Same array-wrap trap documented on ConvertFrom-WingetListTable: without the
            # leading `,` a one-row result unrolls and .Count returns the KEY count (3).
            InModuleScope SoftwareManagementAudit {
                $rows = ConvertFrom-ChocoOutdatedTable -Lines @('solo|1.0|2.0|false')
                @($rows).Count | Should -Be 1
                $rows[0] | Should -BeOfType [hashtable]
            }
        }
    }
}
