#Requires -Version 7.0
<#
    Regression tests for KB-number matching in modules/type2/WindowsUpdates.psm1.

    Origin: both the pre-install check (Test-UpdateAlreadyInstalled) and the post-install
    verification (Test-UpdateIsInstalled) compared KB numbers with -match, which is a REGEX
    SUBSTRING test, not equality. Callers pass the BARE digit run captured from an update
    title ('KB(\d+)' -> '5001234'), while HotFixID is 'KB5001234', so:

        'KB5001234'  -match '5001234'  -> True   (intended)
        'KB15001234' -match '5001234'  -> True   (WRONG - a different, longer KB)

    Consequences, both silent:
      * pre-check  - an unrelated installed KB satisfied the test, so a genuinely missing
                     update was logged "Already installed, skipping" and counted as processed.
      * post-check - an unrelated installed KB was accepted as proof that THIS update landed,
                     turning a failed install into a logged success.

    The registry layers were worse: DisplayName is free text such as
    'Security Update for Microsoft Windows (KB5001234)', so a bare digit run could match
    anywhere inside any product name.

    These tests pin the canonical form and both comparison shapes. The comparison expressions
    below mirror exactly what the module now does (-eq for HotFixID, word-bounded -match for
    DisplayName), so a regression to substring matching fails here.
#>

BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:RepoRoot 'modules\core\Maintenance.psm1') -Force -Global -ErrorAction Stop
    Import-Module (Join-Path $script:RepoRoot 'modules\type2\WindowsUpdates.psm1') -Force -ErrorAction Stop
}

Describe 'ConvertTo-CanonicalKB' {

    It 'prefixes a bare digit run (the form callers actually pass)' {
        InModuleScope WindowsUpdates {
            ConvertTo-CanonicalKB -KBNumber '5001234' | Should -Be 'KB5001234'
        }
    }

    It 'leaves an already-prefixed id unchanged' {
        InModuleScope WindowsUpdates {
            ConvertTo-CanonicalKB -KBNumber 'KB5001234' | Should -Be 'KB5001234'
        }
    }

    It 'normalises lowercase prefixes' {
        InModuleScope WindowsUpdates {
            ConvertTo-CanonicalKB -KBNumber 'kb5001234' | Should -Be 'KB5001234'
        }
    }

    It 'returns empty for null, blank or digit-less input' {
        InModuleScope WindowsUpdates {
            ConvertTo-CanonicalKB -KBNumber $null    | Should -BeNullOrEmpty
            ConvertTo-CanonicalKB -KBNumber ''       | Should -BeNullOrEmpty
            ConvertTo-CanonicalKB -KBNumber '   '    | Should -BeNullOrEmpty
            ConvertTo-CanonicalKB -KBNumber 'notakb' | Should -BeNullOrEmpty
        }
    }
}

Describe 'KB comparison semantics' {

    Context 'HotFixID (Win32_QuickFixEngineering) must be an EXACT match' {
        BeforeAll {
            $script:Target = InModuleScope WindowsUpdates { ConvertTo-CanonicalKB -KBNumber '5001234' }
        }

        It 'matches the intended hotfix' {
            'KB5001234' -eq $script:Target | Should -BeTrue
        }

        It 'rejects a longer KB that CONTAINS the wanted digits (the original defect)' {
            # 'KB15001234' -match '5001234' was True and skipped a real update.
            'KB15001234' -eq $script:Target | Should -BeFalse
        }

        It 'rejects a KB that merely starts with the wanted digits' {
            'KB50012345' -eq $script:Target | Should -BeFalse
        }
    }

    Context 'Registry DisplayName is free text and must be word-bounded' {
        BeforeAll {
            $script:Target = InModuleScope WindowsUpdates { ConvertTo-CanonicalKB -KBNumber '5001234' }
            $script:Pattern = "\b$([regex]::Escape($script:Target))\b"
        }

        It 'matches the KB embedded in a real product name' {
            'Security Update for Microsoft Windows (KB5001234)' -match $script:Pattern | Should -BeTrue
        }

        It 'rejects a different KB containing the wanted digits' {
            'Update for Windows (KB15001234)' -match $script:Pattern | Should -BeFalse
        }

        It 'rejects a longer KB sharing the prefix' {
            'Hotfix (KB50012345)' -match $script:Pattern | Should -BeFalse
        }

        It 'the OLD bare-digit pattern would have matched all three (documents the defect)' {
            'Security Update for Microsoft Windows (KB5001234)' -match '5001234' | Should -BeTrue
            'Update for Windows (KB15001234)'                   -match '5001234' | Should -BeTrue
            'Hotfix (KB50012345)'                               -match '5001234' | Should -BeTrue
        }
    }
}
