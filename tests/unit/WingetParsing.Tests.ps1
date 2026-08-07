#Requires -Version 7.0
<#
    Unit tests for the winget output parsers in SoftwareManagementAudit.psm1.

    These two functions are the reason the winget detection source works at all. Before
    stem matching existed, the source was blind to every one of the ~100 exact-identifier
    entries in bloatware-detection.json, because winget reports a *display* Name and a
    source-prefixed, version-suffixed Id and the patterns match neither.

    Fixture: tests/fixtures/winget-list.txt is REAL `winget list` output (captured on a
    live machine, curated down to representative rows with the original column formatting
    byte-for-byte intact). Do not hand-edit its spacing - the column-count validation in
    ConvertFrom-WingetListTable keys on the '\s{2,}' split, so the spacing IS the test.
#>

BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:RepoRoot 'modules\type1\SoftwareManagementAudit.psm1') -Force -ErrorAction Stop
    $script:FixturePath = Join-Path $PSScriptRoot '..\fixtures\winget-list.txt'
    $script:FixtureLines = @(Get-Content -LiteralPath $script:FixturePath)
}

Describe 'ConvertFrom-WingetPackageId' {

    Context 'MSIX ids (prefix + version/arch/publisher tail)' {
        It 'reduces an MSIX id to the bare package stem' {
            InModuleScope SoftwareManagementAudit {
                ConvertFrom-WingetPackageId -PackageId 'MSIX\Microsoft.AV1VideoExtension_2.0.24.0_x64__8wekyb3d8bbwe' |
                    Should -Be 'Microsoft.AV1VideoExtension'
            }
        }

        It 'handles a publisher name that starts with a digit' {
            InModuleScope SoftwareManagementAudit {
                ConvertFrom-WingetPackageId -PackageId 'MSIX\8bitSolutionsLLC.bitwardendesktop_2026.7.0.0_x64__h4e712dmw3xyy' |
                    Should -Be '8bitSolutionsLLC.bitwardendesktop'
            }
        }

        It 'splits at the FIRST underscore that precedes a digit, not the last' {
            # The tail is _<version>_<arch>__<hash>; splitting anywhere later would leave
            # version fragments glued to the stem and break every exact-identifier pattern.
            InModuleScope SoftwareManagementAudit {
                ConvertFrom-WingetPackageId -PackageId 'MSIX\Microsoft.WindowsMaps_11.2110.4.0_x64__8wekyb3d8bbwe' |
                    Should -Be 'Microsoft.WindowsMaps'
            }
        }
    }

    Context 'ARP ids (source prefix only)' {
        It 'strips ARP\Machine\X64\' {
            InModuleScope SoftwareManagementAudit {
                ConvertFrom-WingetPackageId -PackageId 'ARP\Machine\X64\BabyWare' | Should -Be 'BabyWare'
            }
        }

        It 'strips ARP\Machine\X86\' {
            InModuleScope SoftwareManagementAudit {
                ConvertFrom-WingetPackageId -PackageId 'ARP\Machine\X86\ConfigTool' | Should -Be 'ConfigTool'
            }
        }

        It 'strips the ARP User-scope prefix with an architecture segment' {
            InModuleScope SoftwareManagementAudit {
                ConvertFrom-WingetPackageId -PackageId 'ARP\User\X64\SomeUserApp' | Should -Be 'SomeUserApp'
            }
        }

        It 'keeps a trailing version that is part of the name, not a tail' {
            InModuleScope SoftwareManagementAudit {
                ConvertFrom-WingetPackageId -PackageId 'ARP\Machine\X86\DSSPlugin2.2' | Should -Be 'DSSPlugin2.2'
            }
        }

        It 'does NOT strip an underscore-letter suffix such as the Inno Setup _is1 marker' {
            # The tail rule is _<digit>. '_is1' starts with a letter, so the whole token is
            # the identifier. Stripping it here would produce 'HD Tune', which is a
            # different (and wrong) package key.
            InModuleScope SoftwareManagementAudit {
                ConvertFrom-WingetPackageId -PackageId 'ARP\Machine\X86\HD Tune_is1' | Should -Be 'HD Tune_is1'
            }
        }
    }

    Context 'plain winget ids and degenerate input' {
        It 'leaves an unprefixed winget id unchanged' {
            InModuleScope SoftwareManagementAudit {
                ConvertFrom-WingetPackageId -PackageId 'angryziber.AngryIPScanner' | Should -Be 'angryziber.AngryIPScanner'
            }
        }

        It 'returns empty string unchanged' {
            InModuleScope SoftwareManagementAudit {
                ConvertFrom-WingetPackageId -PackageId '' | Should -Be ''
            }
        }

        It 'returns null unchanged rather than throwing' {
            InModuleScope SoftwareManagementAudit {
                { ConvertFrom-WingetPackageId -PackageId $null } | Should -Not -Throw
            }
        }
    }

    Context 'regression guard: stems must match how bloatware patterns are written' {
        It 'produces the exact AppX short name that bloatware-detection.json targets' {
            # This is the bug the stem logic exists to fix. If this fails, the winget
            # detection source has gone blind to every exact-identifier baseline entry.
            InModuleScope SoftwareManagementAudit {
                $cases = @{
                    'MSIX\Microsoft.BingNews_2019.616.2027.0_neutral_~_8wekyb3d8bbwe' = 'Microsoft.BingNews'
                    'MSIX\Microsoft.XboxGamingOverlay_5.721.10202.0_x64__8wekyb3d8bbwe' = 'Microsoft.XboxGamingOverlay'
                    'MSIX\Microsoft.ZuneMusic_11.2306.7.0_x64__8wekyb3d8bbwe' = 'Microsoft.ZuneMusic'
                }
                foreach ($id in $cases.Keys) {
                    ConvertFrom-WingetPackageId -PackageId $id | Should -Be $cases[$id] -Because "pattern matching depends on '$id' reducing to '$($cases[$id])'"
                }
            }
        }
    }
}

Describe 'ConvertFrom-WingetListTable' {

    Context 'parsing real winget output' {
        It 'returns one row per package line and skips header + separator' {
            InModuleScope SoftwareManagementAudit -Parameters @{ Lines = $script:FixtureLines } {
                param($Lines)
                $rows = ConvertFrom-WingetListTable -Lines $Lines
                # Fixture has 2 header lines + 8 package rows.
                $rows.Count | Should -Be 8
                $rows.Name | Should -Not -Contain 'Name'
            }
        }

        It 'populates Name, Id and Stem on every row' {
            InModuleScope SoftwareManagementAudit -Parameters @{ Lines = $script:FixtureLines } {
                param($Lines)
                foreach ($r in (ConvertFrom-WingetListTable -Lines $Lines)) {
                    $r.Name | Should -Not -BeNullOrEmpty
                    $r.Id | Should -Not -BeNullOrEmpty
                    $r.ContainsKey('Stem') | Should -BeTrue
                }
            }
        }

        It 'preserves spaces inside a display Name' {
            InModuleScope SoftwareManagementAudit -Parameters @{ Lines = $script:FixtureLines } {
                param($Lines)
                $rows = ConvertFrom-WingetListTable -Lines $Lines
                ($rows | Where-Object { $_.Name -eq 'Angry IP Scanner' }) | Should -Not -BeNullOrEmpty
                ($rows | Where-Object { $_.Name -eq 'ConfigTool 5.001.0000003.1' }) | Should -Not -BeNullOrEmpty
            }
        }

        It 'carries the normalised Stem so callers never re-derive it' {
            InModuleScope SoftwareManagementAudit -Parameters @{ Lines = $script:FixtureLines } {
                param($Lines)
                $rows = ConvertFrom-WingetListTable -Lines $Lines
                ($rows | Where-Object { $_.Name -eq 'AV1 Video Extension' }).Stem | Should -Be 'Microsoft.AV1VideoExtension'
                ($rows | Where-Object { $_.Name -eq 'BabyWare' }).Stem | Should -Be 'BabyWare'
            }
        }
    }

    Context 'table-shape validation' {
        It 'emits nothing when there is no dashed separator line' {
            # Without the separator the parser never enters table mode - this is what
            # stops winget banners/progress text being mistaken for package rows.
            InModuleScope SoftwareManagementAudit {
                $rows = ConvertFrom-WingetListTable -Lines @(
                    'Some banner text',
                    'Name        Id',
                    'Foo         Bar.Baz'
                )
                $rows.Count | Should -Be 0
            }
        }

        It 'rejects a row with MORE columns than the header declared' {
            InModuleScope SoftwareManagementAudit {
                $rows = ConvertFrom-WingetListTable -Lines @(
                    'Name        Id',
                    '----------  ----------',
                    'Good        Good.Id',
                    'Too   many  columns  here  indeed  really'
                )
                $rows.Count | Should -Be 1
                $rows[0].Name | Should -Be 'Good'
            }
        }

        It 'skips blank lines inside the table' {
            InModuleScope SoftwareManagementAudit {
                $rows = ConvertFrom-WingetListTable -Lines @(
                    'Name        Id',
                    '----------  ----------',
                    'Alpha       A.Id',
                    '',
                    '   ',
                    'Beta        B.Id'
                )
                $rows.Count | Should -Be 2
            }
        }

        It 'ignores a single-column line (no Id to act on)' {
            InModuleScope SoftwareManagementAudit {
                $rows = ConvertFrom-WingetListTable -Lines @(
                    'Name        Id',
                    '----------  ----------',
                    'LonelyValue'
                )
                $rows.Count | Should -Be 0
            }
        }
    }

    Context 'REGRESSION: single-element array must not unroll' {
        # Found by this test suite. PowerShell unrolls a one-element array on return, so
        # the caller received a bare hashtable and $rows.Count reported its KEY count (3)
        # instead of 1. Resolve-WingetIdForCandidate keys on exactly "Count -eq 1" as its
        # success condition, so Pass B of the bloatware Id resolution could NEVER resolve
        # an Id - it always took the "ambiguous" branch and returned $null.
        # Same bug class as the one Get-DiffList documents a `, @()` guard for.
        It 'returns a real 1-element array when the table has exactly one row' {
            InModuleScope SoftwareManagementAudit {
                $rows = ConvertFrom-WingetListTable -Lines @(
                    'Name        Id',
                    '----------  ----------',
                    'Solo        Solo.Package'
                )
                , $rows | Should -BeOfType [System.Object[]]
                $rows.Count | Should -Be 1 -Because 'a bare hashtable would report its key count (3) here'
                $rows[0].Id | Should -Be 'Solo.Package' -Because 'indexing [0] on a bare hashtable yields $null'
            }
        }

        It 'keeps Count accurate across 1, 2 and many rows' {
            InModuleScope SoftwareManagementAudit {
                $header = @('Name        Id', '----------  ----------')
                foreach ($n in 1, 2, 5) {
                    $body = 1..$n | ForEach-Object { "Pkg$_        Vendor.Pkg$_" }
                    $rows = ConvertFrom-WingetListTable -Lines ($header + $body)
                    $rows.Count | Should -Be $n -Because "a $n-row table must report Count $n"
                }
            }
        }
    }

    Context 'degenerate input' {
        It 'returns an empty array for empty input rather than throwing' {
            InModuleScope SoftwareManagementAudit {
                $rows = ConvertFrom-WingetListTable -Lines @()
                $rows.Count | Should -Be 0
            }
        }

        It 'accepts the default (omitted) parameter' {
            InModuleScope SoftwareManagementAudit {
                { ConvertFrom-WingetListTable } | Should -Not -Throw
            }
        }
    }
}
