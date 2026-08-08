#Requires -Version 7.0
<#
    Tests for the PS7 -> Windows PowerShell 5.1 AppX delegation boundary
    (Invoke-AppxInWinPS in modules/core/Maintenance.psm1).

    WHY THESE ARE NOT MOCKED
    ------------------------
    Every other AppX test in this suite mocks Get-AppxPackageCompat /
    Get-AppxProvisionedPackageCompat. That is correct for testing removal LOGIC, but it meant
    nothing ever crossed the real serialization boundary - and the boundary was broken:

        return & $winPS -NoProfile -Command $ScriptBlock 2>$null

    `powershell.exe -Command` writes the child's CONSOLE TEXT to stdout. PS7 does not
    deserialize it, so callers received [string] lines (including the Format-Table header and
    the '----' separator), and every `$_.Name` / `$_.PackageFullName` read was $null. The
    audit's `Where-Object { $_.Name }` then discarded the entire list.

    Result: the AppX and Provisioned bloatware sources - which between them carry the large
    majority of the detection patterns - reported ZERO detections on every machine, forever.
    Bloatware removal was completely ineffective and nothing in the suite noticed.

    These tests therefore invoke the real function and spawn a real powershell.exe. They use
    pure expressions (no Get-Service, no registry, no AppX) so they stay system-independent
    and unelevated, per the suite's rules.
#>

BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:RepoRoot 'modules\core\Maintenance.psm1') -Force -Global -ErrorAction Stop
}

Describe 'Invoke-AppxInWinPS -AsObject' {

    It 'returns objects whose properties are readable (the whole point)' {
        $r = @(Invoke-AppxInWinPS -AsObject -ScriptBlock `
                "[pscustomobject]@{ Name = 'Microsoft.BingNews'; PackageFullName = 'Microsoft.BingNews_1.0_neutral__8wekyb3d8bbwe' }")
        $r.Count | Should -Be 1
        $r[0].Name | Should -Be 'Microsoft.BingNews'
        $r[0].PackageFullName | Should -Be 'Microsoft.BingNews_1.0_neutral__8wekyb3d8bbwe'
    }

    It 'survives the filter the audit actually applies' {
        # SoftwareManagementAudit does: Get-AppxPackageCompat ... | Where-Object { $_.Name }
        # Before the fix this kept 0 of N.
        $r = @(Invoke-AppxInWinPS -AsObject -ScriptBlock `
                "@([pscustomobject]@{ Name = 'A' }, [pscustomobject]@{ Name = 'B' })")
        @($r | Where-Object { $_.Name }).Count | Should -Be 2
    }

    It 'returns an empty array for no results, not junk' {
        $r = @(Invoke-AppxInWinPS -AsObject -ScriptBlock "@()")
        $r.Count | Should -Be 0
    }

    It 'does not collapse a single result into a bare object' {
        # ConvertTo-Json emits a JSON *object* for one item; the wrapper forces array semantics
        # so callers never have to special-case Count.
        $r = @(Invoke-AppxInWinPS -AsObject -ScriptBlock "[pscustomobject]@{ Name = 'Solo' }")
        $r.Count | Should -Be 1
        $r[0].Name | Should -Be 'Solo'
    }

    It 'returns every result for N > 1' {
        $r = @(Invoke-AppxInWinPS -AsObject -ScriptBlock `
                "1..5 | ForEach-Object { [pscustomobject]@{ Name = `"Pkg`$_`" } }")
        $r.Count | Should -Be 5
        $r[4].Name | Should -Be 'Pkg5'
    }

    It 'preserves non-ASCII publisher strings across the round-trip' {
        $r = @(Invoke-AppxInWinPS -AsObject -ScriptBlock `
                "[pscustomobject]@{ Name = 'X'; Publisher = 'CN=Ünicode Ø, O=Test' }")
        $r[0].Publisher | Should -Be 'CN=Ünicode Ø, O=Test'
    }
}

Describe 'Invoke-AppxInWinPS text mode (unchanged contract)' {

    It 'still returns strings so sentinel-based callers keep working' {
        # Remove-AppxPackageCompat depends on finding an 'APPX_REMOVED' LINE in the output.
        $out = Invoke-AppxInWinPS -ScriptBlock "'APPX_REMOVED'"
        @($out) -contains 'APPX_REMOVED' | Should -BeTrue
    }

    It 'documents the original defect: text mode yields null properties' {
        # This is exactly what every caller used to get. Kept as executable documentation so
        # nobody "simplifies" -AsObject away.
        $out = Invoke-AppxInWinPS -ScriptBlock "[pscustomobject]@{ Name = 'ShouldBeUnreachable' }"
        $mapped = @($out) | ForEach-Object { @{ Name = $_.Name } }
        @($mapped | Where-Object { $_.Name }).Count | Should -Be 0 `
            -Because 'console text has no .Name property - this is why -AsObject exists'
    }
}
