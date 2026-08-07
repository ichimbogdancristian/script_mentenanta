#Requires -Version 7.0
<#
    Unit tests for Compare-ListDiff (modules/core/Maintenance.psm1).

    This is the generic diff engine behind the Type1 -> Type2 contract. It is exported,
    so no InModuleScope is needed.

    Note the 'Changed' strategy uses .PSObject.Properties[...] to test for a key. Baseline
    JSON is loaded with -AsHashtable, so the inputs in production ARE hashtables - and
    .PSObject.Properties on a hashtable is the exact anti-pattern that once made the
    bloatware protection list a no-op. These tests pin down what it actually does for both
    hashtable and PSCustomObject inputs rather than assuming.
#>

BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:RepoRoot 'modules\core\Maintenance.psm1') -Force -Global -ErrorAction Stop
}

Describe 'Compare-ListDiff' {

    Context 'Present strategy (baseline items found on the system)' {
        It 'returns only baseline items that appear in the scan' {
            $scanned = @('Microsoft.BingNews', 'Microsoft.ZuneMusic', 'SomethingElse')
            $baseline = @('Microsoft.BingNews', 'Microsoft.NotInstalled')
            $r = @(Compare-ListDiff -ScannedItems $scanned -BaselineItems $baseline -Strategy 'Present')
            $r | Should -Contain 'Microsoft.BingNews'
            $r | Should -Not -Contain 'Microsoft.NotInstalled'
            $r.Count | Should -Be 1
        }

        It 'matches case-insensitively' {
            $r = @(Compare-ListDiff -ScannedItems @('MICROSOFT.BINGNEWS') `
                    -BaselineItems @('microsoft.bingnews') -Strategy 'Present')
            $r.Count | Should -Be 1
        }

        It 'matches on the named property for object inputs' {
            $scanned = @([pscustomobject]@{ Name = 'AppA' }, [pscustomobject]@{ Name = 'AppB' })
            $baseline = @([pscustomobject]@{ Name = 'AppB' })
            $r = @(Compare-ListDiff -ScannedItems $scanned -BaselineItems $baseline `
                    -Strategy 'Present' -MatchProperty 'Name')
            $r.Count | Should -Be 1
            $r[0].Name | Should -Be 'AppB'
        }

        It 'honours a non-default MatchProperty' {
            $scanned = @([pscustomobject]@{ Id = 'X.1' })
            $baseline = @([pscustomobject]@{ Id = 'X.1' }, [pscustomobject]@{ Id = 'Y.2' })
            $r = @(Compare-ListDiff -ScannedItems $scanned -BaselineItems $baseline `
                    -Strategy 'Present' -MatchProperty 'Id')
            $r.Count | Should -Be 1
            $r[0].Id | Should -Be 'X.1'
        }
    }

    Context 'Missing strategy (baseline items absent from the system)' {
        It 'returns only baseline items not present in the scan' {
            $scanned = @('Installed.App')
            $baseline = @('Installed.App', 'Absent.App')
            $r = @(Compare-ListDiff -ScannedItems $scanned -BaselineItems $baseline -Strategy 'Missing')
            $r | Should -Contain 'Absent.App'
            $r | Should -Not -Contain 'Installed.App'
        }

        It 'returns every baseline item when nothing matches' {
            $r = @(Compare-ListDiff -ScannedItems @('Totally.Different') `
                    -BaselineItems @('A', 'B', 'C') -Strategy 'Missing')
            $r.Count | Should -Be 3
        }
    }

    Context 'Changed strategy' {
        It 'emits an item when CurrentState differs from desiredValue' {
            $scanned = @([pscustomobject]@{ Name = 'Setting1'; CurrentState = 0 })
            $baseline = @([pscustomobject]@{ Name = 'Setting1'; desiredValue = 1 })
            $r = @(Compare-ListDiff -ScannedItems $scanned -BaselineItems $baseline -Strategy 'Changed')
            $r.Count | Should -Be 1
            $r[0].CurrentState | Should -Be 0
            $r[0].DesiredState | Should -Be 1
        }

        It 'emits nothing when CurrentState already equals desiredValue' {
            $scanned = @([pscustomobject]@{ Name = 'Setting1'; CurrentState = 1 })
            $baseline = @([pscustomobject]@{ Name = 'Setting1'; desiredValue = 1 })
            $r = @(Compare-ListDiff -ScannedItems $scanned -BaselineItems $baseline -Strategy 'Changed')
            $r.Count | Should -Be 0
        }

        It 'treats a baseline item absent from the scan as needing the desired value' {
            $scanned = @([pscustomobject]@{ Name = 'Other'; CurrentState = 1 })
            $baseline = @([pscustomobject]@{ Name = 'NotScanned'; desiredValue = 1 })
            $r = @(Compare-ListDiff -ScannedItems $scanned -BaselineItems $baseline -Strategy 'Changed')
            $r.Count | Should -Be 1
            $r[0].CurrentState | Should -BeNullOrEmpty
            $r[0].DesiredState | Should -Be 1
        }

        It 'carries the original baseline entry through as .Item' {
            $baseline = @([pscustomobject]@{ Name = 'S'; desiredValue = 1; description = 'why' })
            $r = @(Compare-ListDiff -ScannedItems @([pscustomobject]@{ Name = 'S'; CurrentState = 0 }) `
                    -BaselineItems $baseline -Strategy 'Changed')
            $r[0].Item.description | Should -Be 'why'
        }
    }

    Context 'hashtable inputs (what production actually passes)' {
        # Get-BaselineList uses ConvertFrom-Json -AsHashtable, so real baseline entries are
        # hashtables. These tests document the ACTUAL behaviour of the Changed strategy's
        # .PSObject.Properties[...] key test against a hashtable.
        It 'handles hashtable baseline entries in the Changed strategy without throwing' {
            $scanned = @(@{ Name = 'S'; CurrentState = 0 })
            $baseline = @(@{ Name = 'S'; desiredValue = 1 })
            { Compare-ListDiff -ScannedItems $scanned -BaselineItems $baseline -Strategy 'Changed' } |
                Should -Not -Throw
        }

        It 'matches hashtable entries in the Present strategy' {
            $scanned = @(@{ Name = 'AppA' })
            $baseline = @(@{ Name = 'AppA' }, @{ Name = 'AppB' })
            $r = @(Compare-ListDiff -ScannedItems $scanned -BaselineItems $baseline -Strategy 'Present')
            $r.Count | Should -Be 1
        }
    }

    Context 'empty and degenerate input' {
        It 'returns empty when the scan is empty' {
            $r = @(Compare-ListDiff -ScannedItems @() -BaselineItems @('A') -Strategy 'Missing')
            $r.Count | Should -Be 0
        }

        It 'returns empty when the baseline is empty' {
            $r = @(Compare-ListDiff -ScannedItems @('A') -BaselineItems @() -Strategy 'Present')
            $r.Count | Should -Be 0
        }

        It 'skips baseline entries with a null/blank match value' {
            $r = @(Compare-ListDiff -ScannedItems @('A') `
                    -BaselineItems @([pscustomobject]@{ Name = $null }, [pscustomobject]@{ Name = 'A' }) `
                    -Strategy 'Present' -MatchProperty 'Name')
            $r.Count | Should -Be 1
        }

        It 'rejects an invalid strategy at parameter binding' {
            { Compare-ListDiff -ScannedItems @('A') -BaselineItems @('A') -Strategy 'Nonsense' } |
                Should -Throw
        }
    }

    Context 'single-result array shape' {
        # Same bug class as the ConvertFrom-WingetListTable unrolling defect. Callers in
        # this repo all wrap with @() or pipe, so this documents the contract rather than
        # asserting a guarantee the function makes on its own.
        It 'yields exactly one item when one baseline entry matches' {
            $r = @(Compare-ListDiff -ScannedItems @('Only') -BaselineItems @('Only') -Strategy 'Present')
            $r.Count | Should -Be 1
        }
    }
}
