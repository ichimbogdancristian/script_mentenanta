#Requires -Version 7.0
<#
    Unit tests for truncated-Id repair in modules/core/Maintenance.psm1:
    Test-WingetIdTruncated, Resolve-WingetTruncatedId, ConvertFrom-WingetExportJson,
    Get-WingetExportedId.

    `winget upgrade` prints a width-fitted table, so a long Id arrives cut short with an
    ellipsis. That form cannot be handed back to `winget upgrade --id`, so the per-package
    upgrade fell through to the looser --name match or skipped the package. The audit now
    repairs such Ids from `winget export` (complete Ids, JSON).

    The repair must be CONSERVATIVE: an intact Id is never touched, and an ambiguous prefix is
    left alone rather than risk upgrading the wrong package.

    Non-ASCII characters are built from [char] codes so this file stays pure ASCII.
#>

BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:RepoRoot 'modules\core\Maintenance.psm1') -Force -ErrorAction Stop

    $script:Ell = [string][char]0x2026                                   # ...
    $script:Moji437 = [string]::new([char[]](0x0393, 0x00C7, 0x00AA))     # UTF-8 ellipsis read as CP437
    $script:Moji1252 = [string]::new([char[]](0x00E2, 0x20AC, 0x00A6))    # UTF-8 ellipsis read as CP1252

    $script:Known = @(
        'Microsoft.VCRedist.2015+.x64',
        'Microsoft.VCRedist.2015+.x86',
        'Mozilla.Firefox',
        'Adobe.Acrobat.Reader.64-bit',
        'Notepad++.Notepad++'
    )
}

Describe 'Test-WingetIdTruncated' {

    It 'detects the <Label> marker' -ForEach @(
        @{ Label = 'U+2026'; Suffix = 'ELL' }
        @{ Label = 'three-dot'; Suffix = '...' }
        @{ Label = 'question-mark'; Suffix = '?' }
        @{ Label = 'CP437 mojibake'; Suffix = 'M437' }
        @{ Label = 'CP1252 mojibake'; Suffix = 'M1252' }
    ) {
        $s = switch ($Suffix) { 'ELL' { $script:Ell } 'M437' { $script:Moji437 } 'M1252' { $script:Moji1252 } default { $Suffix } }
        Test-WingetIdTruncated -Id "Adobe.Acrobat.Rea$s" | Should -BeTrue
    }

    It 'does not flag intact Ids, including ones with + and -' {
        foreach ($id in $script:Known) { Test-WingetIdTruncated -Id $id | Should -BeFalse }
    }

    It 'returns false for empty and null' {
        Test-WingetIdTruncated -Id '' | Should -BeFalse
        Test-WingetIdTruncated -Id $null | Should -BeFalse
    }
}

Describe 'Resolve-WingetTruncatedId' {

    It 'resolves a uniquely-prefixed truncated Id' {
        Resolve-WingetTruncatedId -Id "Adobe.Acrobat.Rea$script:Ell" -KnownIds $script:Known |
            Should -Be 'Adobe.Acrobat.Reader.64-bit'
    }

    It 'resolves through mojibake and the three-dot form' {
        Resolve-WingetTruncatedId -Id "Adobe.Acrobat.Rea$script:Moji437" -KnownIds $script:Known |
            Should -Be 'Adobe.Acrobat.Reader.64-bit'
        Resolve-WingetTruncatedId -Id 'Adobe.Acrobat.Rea...' -KnownIds $script:Known |
            Should -Be 'Adobe.Acrobat.Reader.64-bit'
    }

    It 'resolves case-insensitively' {
        Resolve-WingetTruncatedId -Id "mozilla.fire$script:Ell" -KnownIds $script:Known |
            Should -Be 'Mozilla.Firefox'
    }

    It 'leaves an AMBIGUOUS prefix unchanged rather than guessing' {
        $id = "Microsoft.VCRedist.2015+.x$script:Ell"
        Resolve-WingetTruncatedId -Id $id -KnownIds $script:Known | Should -Be $id
    }

    It 'leaves a truncated Id with no match unchanged' {
        $id = "Some.Unknown.Pack$script:Ell"
        Resolve-WingetTruncatedId -Id $id -KnownIds $script:Known | Should -Be $id
    }

    It 'never rewrites an intact Id, even when it is a prefix of another known Id' {
        Resolve-WingetTruncatedId -Id 'Mozilla.Fire' -KnownIds $script:Known | Should -Be 'Mozilla.Fire'
    }

    It 'returns an exact known Id unchanged' {
        Resolve-WingetTruncatedId -Id 'Notepad++.Notepad++' -KnownIds $script:Known | Should -Be 'Notepad++.Notepad++'
    }

    It 'returns the input unchanged when the known list is empty or null' {
        $id = "Adobe.Acrobat.Rea$script:Ell"
        Resolve-WingetTruncatedId -Id $id -KnownIds @() | Should -Be $id
        Resolve-WingetTruncatedId -Id $id -KnownIds $null | Should -Be $id
    }

    It 'returns the input unchanged when the Id is ONLY a marker' {
        Resolve-WingetTruncatedId -Id $script:Ell -KnownIds $script:Known | Should -Be $script:Ell
    }
}

Describe 'ConvertFrom-WingetExportJson' {

    It 'extracts every PackageIdentifier across all sources' {
        $json = @'
{
  "$schema": "https://aka.ms/winget-packages.schema.2.0.json",
  "Sources": [
    { "Packages": [ { "PackageIdentifier": "Mozilla.Firefox" }, { "PackageIdentifier": "Microsoft.VCRedist.2015+.x64" } ],
      "SourceDetails": { "Name": "winget" } },
    { "Packages": [ { "PackageIdentifier": "9NBLGGH4NNS1" } ],
      "SourceDetails": { "Name": "msstore" } }
  ],
  "WinGetVersion": "1.9.25200"
}
'@
        $ids = ConvertFrom-WingetExportJson -Json $json
        $ids.Count | Should -Be 3
        $ids | Should -Contain 'Microsoft.VCRedist.2015+.x64'
        $ids | Should -Contain '9NBLGGH4NNS1'
    }

    It 'returns an empty array for <Label> without throwing' -ForEach @(
        @{ Label = 'empty'; Json = '' }
        @{ Label = 'malformed JSON'; Json = '{ not json' }
        @{ Label = 'no Sources key'; Json = '{ "WinGetVersion": "1.9" }' }
        @{ Label = 'source without Packages'; Json = '{ "Sources": [ { "SourceDetails": {} } ] }' }
    ) {
        $ids = ConvertFrom-WingetExportJson -Json $Json
        $ids.Count | Should -Be 0
    }

    It 'returns a real array for a single package (unrolling trap)' {
        $ids = ConvertFrom-WingetExportJson -Json '{ "Sources": [ { "Packages": [ { "PackageIdentifier": "A.B" } ] } ] }'
        $ids.Count | Should -Be 1
        $ids[0] | Should -Be 'A.B'
    }
}

Describe 'Get-WingetExportedId' {

    BeforeEach {
        $env:MAINT_TEMP_SAVED = $env:MAINT_TEMP
        $env:MAINT_TEMP = Join-Path $TestDrive 'temp'
    }
    AfterEach {
        $env:MAINT_TEMP = $env:MAINT_TEMP_SAVED
        Remove-Item Env:\MAINT_TEMP_SAVED -ErrorAction SilentlyContinue
    }

    It 'reads the exported file even when winget exits non-zero, then deletes it' {
        InModuleScope Maintenance {
            Mock Test-CommandAvailable { $true }
            Mock Resolve-WingetPath { 'winget.exe' }
            Mock Write-Log { }
            Mock Invoke-CapturedCommand {
                $path = $ArgumentList[2].Trim('"')
                Set-Content -LiteralPath $path -Encoding UTF8 -Value '{ "Sources": [ { "Packages": [ { "PackageIdentifier": "Mozilla.Firefox" } ] } ] }'
                $script:ExportPath = $path
                @{ ExitCode = -1978335138; StdOut = ''; StdErr = ''; TimedOut = $false }
            }

            $ids = Get-WingetExportedId
            $ids.Count | Should -Be 1
            $ids[0] | Should -Be 'Mozilla.Firefox'
            Test-Path -LiteralPath $script:ExportPath | Should -BeFalse
            Should -Invoke Invoke-CapturedCommand -Times 1 -ParameterFilter {
                $ArgumentList[0] -eq 'export' -and $ArgumentList -contains '--disable-interactivity' -and
                $ArgumentList -contains '--accept-source-agreements'
            }
        }
    }

    It 'returns empty and warns when no file is produced' {
        InModuleScope Maintenance {
            Mock Test-CommandAvailable { $true }
            Mock Resolve-WingetPath { 'winget.exe' }
            Mock Write-Log { }
            Mock Invoke-CapturedCommand { @{ ExitCode = 1; StdOut = ''; StdErr = ''; TimedOut = $false } }

            $ids = Get-WingetExportedId
            $ids.Count | Should -Be 0
            Should -Invoke Write-Log -ParameterFilter { $Level -eq 'WARN' }
        }
    }

    It 'returns empty without running anything when winget is unavailable' {
        InModuleScope Maintenance {
            Mock Test-CommandAvailable { $false }
            Mock Invoke-CapturedCommand { throw 'should not run' }

            $ids = Get-WingetExportedId
            $ids.Count | Should -Be 0
            Should -Invoke Invoke-CapturedCommand -Times 0
        }
    }
}
