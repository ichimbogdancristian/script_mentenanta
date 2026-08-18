#Requires -Version 7.0
<#
    Unit tests for ConvertFrom-WingetUpgradeTable in modules/core/Maintenance.psm1.

    This parser feeds the ENTIRE app-upgrade feature: whatever it fails to return is a
    package that is never queued and never upgraded, silently and with no error anywhere.
    Three regressions it exists to prevent, all of which were live defects:

      1. The upgrade query ran without --accept-source-agreements, so on a machine that had
         not accepted the source terms winget printed the agreement prompt INSTEAD of a
         table. No '----' divider, zero rows parsed, "0 upgrade" logged, feature inert.
         Covered here by the 'agreement prompt' case: prompt text must yield no rows and
         must not throw, so the WARN in Get-WingetUpgrade is what surfaces instead.

      2. `winget upgrade` prints a SECOND table ("require explicit targeting for upgrade")
         with its own header row. A parser that remembers the previous line instead of
         looking ahead emits that second header as a data row - producing a package
         literally named "Name" with Id "Id", which Type2 then tries to upgrade.

      3. The single-element array-unrolling trap already documented on
         ConvertFrom-WingetListTable and Get-DiffList.

    Fixture: tests/fixtures/winget-upgrade.txt mirrors real `winget upgrade
    --include-unknown` output, including the second table and an Unknown version. Do not
    hand-edit its spacing - the column-count validation keys on the '\s{2,}' split, so the
    spacing IS the test.
#>

BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:RepoRoot 'modules\core\Maintenance.psm1') -Force -ErrorAction Stop
    $script:FixturePath = Join-Path $PSScriptRoot '..\fixtures\winget-upgrade.txt'
    $script:FixtureLines = @(Get-Content -LiteralPath $script:FixturePath)
}

Describe 'ConvertFrom-WingetUpgradeTable' {

    Context 'real two-table `winget upgrade --include-unknown` output' {

        It 'returns every data row from BOTH tables' {
            $rows = ConvertFrom-WingetUpgradeTable -Lines $script:FixtureLines
            $rows.Count | Should -Be 6
        }

        It 'never emits the second table header as a package (regression 2)' {
            $rows = ConvertFrom-WingetUpgradeTable -Lines $script:FixtureLines
            @($rows | Where-Object { $_.Name -eq 'Name' -or $_.Id -eq 'Id' }).Count | Should -Be 0
        }

        It 'never emits the "N upgrades available." summary as a package' {
            $rows = ConvertFrom-WingetUpgradeTable -Lines $script:FixtureLines
            @($rows | Where-Object { $_.Name -like '*upgrades available*' }).Count | Should -Be 0
        }

        It 'picks up rows from the second (explicit-targeting) table' {
            $rows = ConvertFrom-WingetUpgradeTable -Lines $script:FixtureLines
            @($rows | Where-Object Name -eq 'Wazuh Agent').Count | Should -Be 1
        }

        It 'maps the columns to the right fields' {
            $rows = ConvertFrom-WingetUpgradeTable -Lines $script:FixtureLines
            $ff = $rows | Where-Object Name -eq 'Mozilla Firefox'
            $ff.Id | Should -Be 'Mozilla.Firefox'
            $ff.CurrentVersion | Should -Be '140.0.4'
            $ff.AvailableVersion | Should -Be '141.0.2'
            $ff.Source | Should -Be 'Winget'
        }

        It 'keeps multi-word names intact rather than splitting on the single space' {
            $rows = ConvertFrom-WingetUpgradeTable -Lines $script:FixtureLines
            @($rows | Where-Object Name -eq 'Adobe Acrobat Reader (64-bit)').Count | Should -Be 1
        }
    }

    Context 'VersionUnknown flagging (--include-unknown rows are kept, not dropped)' {

        It 'flags a row whose installed version is Unknown' {
            $rows = ConvertFrom-WingetUpgradeTable -Lines $script:FixtureLines
            ($rows | Where-Object Name -eq 'Wazuh Agent').VersionUnknown | Should -BeTrue
        }

        It 'does not flag a row with a real installed version' {
            $rows = ConvertFrom-WingetUpgradeTable -Lines $script:FixtureLines
            ($rows | Where-Object Name -eq '7-Zip').VersionUnknown | Should -BeFalse
        }

        It 'still QUEUES the unknown-version row - it must be attempted, not dropped' {
            $rows = ConvertFrom-WingetUpgradeTable -Lines $script:FixtureLines
            @($rows | Where-Object VersionUnknown).Count | Should -Be 1
        }
    }

    Context 'progress-spinner contamination (regression: header column count)' {

        It 'keeps only the text after the last carriage return on a line' {
            # winget overwrites one physical line with spinner frames; only the final chunk
            # was ever on screen. If those frames survive onto the HEADER line, the header
            # column count is wrong and every data row is then rejected against it.
            $lines = @(
                "  -`r  \`r  |`rName          Id            Version   Available   Source",
                '------------------------------------------------------------------',
                'Solo App      Solo.App      1.0       2.0         winget'
            )
            $rows = ConvertFrom-WingetUpgradeTable -Lines $lines
            $rows.Count | Should -Be 1
            $rows[0].Name | Should -Be 'Solo App'
        }
    }

    Context 'source-agreement prompt instead of a table (regression 1)' {

        It 'returns no rows and does not throw when winget printed a prompt' {
            $lines = @(
                'The `msstore` source requires that you view the following agreements before using.',
                'Terms of Transaction: https://aka.ms/microsoft-store-terms',
                'The source requires the current machine''s 2-letter geographic region to be sent.',
                'Do you agree to all the source agreements terms? [Y] Yes  [N] No: '
            )
            $rows = ConvertFrom-WingetUpgradeTable -Lines $lines
            $rows.Count | Should -Be 0
        }
    }

    Context 'malformed and degenerate input' {

        It 'rejects a row with more columns than the header declared' {
            $lines = @(
                'Name  Id  Version  Available  Source',
                '-----------------------------------',
                'App  Weird  Name  A.B  1.0  2.0  winget'
            )
            (ConvertFrom-WingetUpgradeTable -Lines $lines).Count | Should -Be 0
        }

        It 'rejects a row with fewer than four columns' {
            $lines = @('Name  Id  Version  Available  Source', '-----', 'Broken  Row')
            (ConvertFrom-WingetUpgradeTable -Lines $lines).Count | Should -Be 0
        }

        It 'rejects a data row with an empty name' {
            $lines = @('Name  Id  Version  Available  Source', '-----', '   ')
            (ConvertFrom-WingetUpgradeTable -Lines $lines).Count | Should -Be 0
        }

        It 'returns an empty array for empty input' {
            (ConvertFrom-WingetUpgradeTable -Lines @()).Count | Should -Be 0
        }

        It 'tolerates null entries among the lines without throwing' {
            # [string[]] coerces $null to '', which the parser then treats as a blank line -
            # i.e. end of table. That is the intended reading (winget separates its tables
            # with a blank line and never puts one mid-table), so the row BEFORE the null
            # survives and the row after it starts outside a table. Asserted explicitly so
            # the behaviour is a decision rather than an accident.
            $lines = @('Name  Id  Version  Available  Source', '-----',
                'A  A.A  1.0  2.0  winget', $null, 'B  B.B  3.0  4.0  winget')
            $rows = ConvertFrom-WingetUpgradeTable -Lines $lines
            $rows.Count | Should -Be 1
            $rows[0].Name | Should -Be 'A'
        }
    }

    Context 'single-element array unrolling (regression 3)' {

        # Same trap documented on ConvertFrom-WingetListTable: without the `,` array-wrap a
        # one-row result is returned as a BARE HASHTABLE, whose .Count reports the KEY count
        # (6) instead of 1 - so any "did I get exactly one row?" test silently never matches.
        It 'returns a one-row result as a one-element ARRAY, not a bare hashtable' {
            $lines = @('Name  Id  Version  Available  Source', '-----', 'Solo  Solo.App  1.0  2.0  winget')
            $rows = ConvertFrom-WingetUpgradeTable -Lines $lines
            $rows.Count | Should -Be 1
            $rows[0].Name | Should -Be 'Solo'
        }

        It 'iterates exactly once in the foreach shape the audit actually uses' {
            $lines = @('Name  Id  Version  Available  Source', '-----', 'Solo  Solo.App  1.0  2.0  winget')
            $n = 0
            foreach ($r in (ConvertFrom-WingetUpgradeTable -Lines $lines)) { $n++ }
            $n | Should -Be 1
        }

        It 'iterates zero times for an empty result' {
            $n = 0
            foreach ($r in (ConvertFrom-WingetUpgradeTable -Lines @())) { $n++ }
            $n | Should -Be 0
        }
    }
}
