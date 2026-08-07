#Requires -Version 7.0
<#
    Unit tests for ConvertFrom-MaintenanceLog (modules/core/ReportGenerator.psm1).

    This parser feeds the in-report log console. It must be lossless: the launcher writes
    plain banners into the same maintenance.log that the orchestrator writes structured
    lines into, so anything that does not match the structured shape has to survive as
    Level='RAW' rather than being dropped.

    It reads through a FileStream with FileShare.ReadWrite specifically so it works while
    the core logger still holds the file open (Stage 4 embeds the log live). The
    "reads a file that is still open for writing" test pins that behaviour.
#>

BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:RepoRoot 'modules\core\Maintenance.psm1') -Force -Global -ErrorAction Stop
    Import-Module (Join-Path $script:RepoRoot 'modules\core\ReportGenerator.psm1') -Force -ErrorAction Stop

    $script:TempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("logparse-{0}" -f [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $script:TempDir -Force | Out-Null

    function New-TestLog {
        param([string[]]$Lines)
        $p = Join-Path $script:TempDir ("log-{0}.log" -f [guid]::NewGuid().ToString('N'))
        Set-Content -LiteralPath $p -Value $Lines -Encoding UTF8
        return $p
    }
}

AfterAll {
    if ($script:TempDir -and (Test-Path $script:TempDir)) {
        Remove-Item -LiteralPath $script:TempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'ConvertFrom-MaintenanceLog' {

    Context 'structured lines' {
        It 'parses ts / component / level / message' {
            $p = New-TestLog @('[2026-08-07 01:00:05] [ORCH] [INFO] Stage 1 starting')
            InModuleScope ReportGenerator -Parameters @{ P = $p } {
                param($P)
                $e = ConvertFrom-MaintenanceLog -Path $P
                $e.Count | Should -Be 1
                $e[0].Level | Should -Be 'INFO'
                $e[0].Component | Should -Be 'ORCH'
                $e[0].Message | Should -Be 'Stage 1 starting'
                $e[0].Ts | Should -Be '2026-08-07 01:00:05'
            }
        }

        It 'extracts a short HH:mm:ss timestamp for the compact column' {
            $p = New-TestLog @('[2026-08-07 13:45:59] [CORE] [DEBUG] x')
            InModuleScope ReportGenerator -Parameters @{ P = $p } {
                param($P)
                (ConvertFrom-MaintenanceLog -Path $P)[0].ShortTs | Should -Be '13:45:59'
            }
        }

        It 'uppercases the level' {
            $p = New-TestLog @('[2026-08-07 01:00:00] [CORE] [warn] lowercase level')
            InModuleScope ReportGenerator -Parameters @{ P = $p } {
                param($P)
                (ConvertFrom-MaintenanceLog -Path $P)[0].Level | Should -Be 'WARN'
            }
        }

        It 'preserves square brackets inside the message body' {
            $p = New-TestLog @('[2026-08-07 01:00:00] [SOFTWARE] [INFO] Removing [Microsoft.BingNews] now')
            InModuleScope ReportGenerator -Parameters @{ P = $p } {
                param($P)
                (ConvertFrom-MaintenanceLog -Path $P)[0].Message | Should -Be 'Removing [Microsoft.BingNews] now'
            }
        }

        It 'handles an empty message after the level' {
            $p = New-TestLog @('[2026-08-07 01:00:00] [CORE] [INFO] ')
            InModuleScope ReportGenerator -Parameters @{ P = $p } {
                param($P)
                $e = ConvertFrom-MaintenanceLog -Path $P
                $e.Count | Should -Be 1
                $e[0].Level | Should -Be 'INFO'
            }
        }

        It 'parses every level the logger emits' {
            $levels = 'DEBUG', 'INFO', 'SUCCESS', 'WARN', 'ERROR', 'FATAL'
            $p = New-TestLog ($levels | ForEach-Object { "[2026-08-07 01:00:00] [CORE] [$_] msg" })
            InModuleScope ReportGenerator -Parameters @{ P = $p; L = $levels } {
                param($P, $L)
                $e = ConvertFrom-MaintenanceLog -Path $P
                $e.Count | Should -Be $L.Count
                foreach ($lvl in $L) { $e.Level | Should -Contain $lvl }
            }
        }
    }

    Context 'unstructured lines must survive as RAW' {
        It 'keeps a launcher banner line' {
            $p = New-TestLog @('======== Windows Maintenance Launcher ========')
            InModuleScope ReportGenerator -Parameters @{ P = $p } {
                param($P)
                $e = ConvertFrom-MaintenanceLog -Path $P
                $e.Count | Should -Be 1
                $e[0].Level | Should -Be 'RAW'
                $e[0].Message | Should -Match 'Windows Maintenance Launcher'
            }
        }

        It 'drops purely blank lines but keeps everything else' {
            $p = New-TestLog @(
                '[2026-08-07 01:00:00] [CORE] [INFO] structured',
                '',
                '   ',
                'loose text line'
            )
            InModuleScope ReportGenerator -Parameters @{ P = $p } {
                param($P)
                $e = ConvertFrom-MaintenanceLog -Path $P
                $e.Count | Should -Be 2
                $e[1].Level | Should -Be 'RAW'
            }
        }

        It 'is lossless across a mixed launcher + orchestrator log' {
            $p = New-TestLog @(
                'Windows Maintenance Automation',
                '[2026-08-07 01:00:00] [LAUNCHER] [INFO] Checking winget',
                '--------------------------------',
                '[2026-08-07 01:00:07] [ORCH] [SUCCESS] Stage 1 complete'
            )
            InModuleScope ReportGenerator -Parameters @{ P = $p } {
                param($P)
                $e = ConvertFrom-MaintenanceLog -Path $P
                $e.Count | Should -Be 4
                @($e | Where-Object Level -EQ 'RAW').Count | Should -Be 2
                @($e | Where-Object Level -NE 'RAW').Count | Should -Be 2
            }
        }
    }

    Context 'live-read behaviour' {
        It 'reads a file that is still open for writing (FileShare.ReadWrite)' {
            # This is why the function uses a FileStream instead of Get-Content: Stage 4
            # embeds maintenance.log while the core logger still holds it open.
            $p = Join-Path $script:TempDir 'live.log'
            $fs = [System.IO.FileStream]::new($p, [System.IO.FileMode]::Create,
                [System.IO.FileAccess]::Write, [System.IO.FileShare]::ReadWrite)
            $sw = [System.IO.StreamWriter]::new($fs, [System.Text.Encoding]::UTF8)
            try {
                $sw.WriteLine('[2026-08-07 01:00:00] [CORE] [INFO] written while open')
                $sw.Flush()
                InModuleScope ReportGenerator -Parameters @{ P = $p } {
                    param($P)
                    $e = ConvertFrom-MaintenanceLog -Path $P
                    $e.Count | Should -Be 1
                    $e[0].Message | Should -Be 'written while open'
                }
            }
            finally { $sw.Dispose(); $fs.Dispose() }
        }
    }

    Context 'degenerate input must yield an EMPTY COLLECTION, never $null' {
        # These assertions are deliberately stronger than "Count -eq 0". PowerShell reports
        # $null.Count as 0, so a plain count check passes against a null return - which is
        # exactly how the original defect survived this test file.
        #
        # The bug: ConvertFrom-MaintenanceLog ended `return $entries`, and PowerShell
        # ENUMERATES a collection on return, so an empty List came back as $null.
        # Build-LogConsole is Mandatory+AllowEmptyCollection, which rejects null, so
        # Build-ReportHtml threw and Stage 4 lost the HTML report - the only artifact that
        # survives cleanup. Fixed with `return , $entries` on every path.

        It 'returns a non-null collection for a missing path' {
            InModuleScope ReportGenerator {
                $r = ConvertFrom-MaintenanceLog -Path 'X:\does\not\exist.log'
                $null -eq $r | Should -BeFalse -Because 'null here is a hard binding error downstream'
                $r.Count | Should -Be 0
            }
        }

        It 'returns a non-null collection for a null/empty path' {
            InModuleScope ReportGenerator {
                foreach ($r in (ConvertFrom-MaintenanceLog -Path ''), (ConvertFrom-MaintenanceLog)) {
                    $null -eq $r | Should -BeFalse
                    $r.Count | Should -Be 0
                }
            }
        }

        It 'returns a non-null collection for an empty file' {
            $p = New-TestLog @()
            InModuleScope ReportGenerator -Parameters @{ P = $p } {
                param($P)
                $r = ConvertFrom-MaintenanceLog -Path $P
                $null -eq $r | Should -BeFalse
                $r.Count | Should -Be 0
            }
        }

        It 'REGRESSION: Build-LogConsole accepts the empty result without a binding error' {
            # End-to-end shape of the original failure: producer output fed straight into the
            # consumer's Mandatory parameter.
            InModuleScope ReportGenerator {
                $empty = ConvertFrom-MaintenanceLog -Path 'X:\does\not\exist.log'
                $html = $null
                { $script:html = Build-LogConsole -Entries $empty } | Should -Not -Throw
                $script:html | Should -Match 'No log entries available'
            }
        }

        It 'REGRESSION: Build-LogConsole survives an outright null (second line of defence)' {
            InModuleScope ReportGenerator {
                { Build-LogConsole -Entries $null } | Should -Not -Throw
            }
        }
    }
}
