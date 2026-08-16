#Requires -Version 7.0
<#
    Regression tests for HTML report rendering defects found by inspecting a real report
    from a live run (modules/core/ReportGenerator.psm1 + assets/report.css).

    Four independent bugs, all invisible to the existing suite because nothing asserted on
    the rendered markup or the stylesheet:

      1. LAYOUT. .thead/.trow are display:grid, but the column template lived only on
         .uN and .thead.uN. Build-RestorePointSection and the health tables emit
         `class='trow u4'` so they rendered; Build-SystemInventorySection emits a bare
         `class='trow'`, which got display:grid with NO template - every cell collapsed
         into one implicit column, so Local Users and the System Details restore-point
         card rendered as a vertical stack misaligned under their own headers.

      2. SILENT TRUNCATION. The Defender incidents card capped at 20 rows and was the only
         one of the four truncating tables with no "+N more" footer. A run reporting 170
         incidents showed 20 and dropped 150 with nothing to say so.

      3. UNREACHABLE LOG ROWS. Build-LogConsole derives its filter chips from a FIXED level
         list and shows a row only when its data-level matches an active chip, so a row
         carrying any other level could never be displayed by any filter combination.

      4. UNSTABLE ORDER. ExtraData is a plain hashtable, so each module card listed its
         keys in a different order every run.
#>

BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:RepoRoot 'modules\core\Maintenance.psm1') -Force -Global -ErrorAction Stop
    Import-Module (Join-Path $script:RepoRoot 'modules\core\ReportGenerator.psm1') -Force -ErrorAction Stop

    $script:Css = Get-Content (Join-Path $script:RepoRoot 'modules\core\assets\report.css') -Raw
    $script:Gen = Get-Content (Join-Path $script:RepoRoot 'modules\core\ReportGenerator.psm1') -Raw

    $script:TempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("reprender-{0}" -f [guid]::NewGuid().ToString('N'))
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

Describe 'report.css table grid' {

    # Both the desktop rules and the max-width:900px overrides must carry the descendant
    # selector, or the narrow layout drops a header column while rows keep a stale template.
    It 'gives .tbody.u3 > .trow a column template' {
        @([regex]::Matches($script:Css, '\.tbody\.u3>\.trow')).Count |
            Should -BeGreaterOrEqual 2 -Because 'desktop AND the responsive override both need it'
    }

    It 'gives .tbody.u4 > .trow a column template' {
        @([regex]::Matches($script:Css, '\.tbody\.u4>\.trow')).Count |
            Should -BeGreaterOrEqual 2
    }

    It 'still declares display:grid on .trow' {
        # The descendant fix is only meaningful while rows are grid items.
        $script:Css | Should -Match '\.thead,\.trow\{display:grid'
    }

    It 'emits rows inside a .tbody that carries the same modifier' {
        # The fix works by descent, so every tbody must carry u3/u4. If a future section
        # emits <div class="tbody"> with no modifier, its rows silently stack again.
        foreach ($m in [regex]::Matches($script:Gen, '<div class="tbody(?<mod>[^"]*)"')) {
            $m.Groups['mod'].Value.Trim() | Should -Match '^u\d$' `
                -Because 'a .tbody with no u3/u4 modifier gives its rows no column template'
        }
    }
}

Describe 'truncating tables all declare their overflow' {

    # "No silent caps": a table that shows the first N of M must say so. Every table that
    # slices with [0..($max - 1)] needs a matching "+N more" footer.
    It 'every capped table in ReportGenerator emits a tmore footer' {
        $capped = @([regex]::Matches($script:Gen, '\$max = \[Math\]::Min\(20,')).Count
        $footers = @([regex]::Matches($script:Gen, "tmore'>\+\$\(")).Count
        $footers | Should -BeGreaterOrEqual $capped `
            -Because "each of the $capped tables capped at 20 rows needs a '+N more' indicator"
    }

    It 'the Defender incidents card specifically has one' {
        # This is the card that was missing it.
        $block = [regex]::Match($script:Gen, 'DefenderIncidents[\s\S]{0,2600}?"@').Value
        $block | Should -Match 'tmore' -Because '170 incidents showed 20 and dropped 150 silently'
    }
}

Describe 'ConvertFrom-MaintenanceLog level handling' {

    It 'parses each known level' {
        foreach ($lvl in 'FATAL', 'ERROR', 'WARN', 'SUCCESS', 'INFO', 'DEBUG') {
            $p = New-TestLog @("[12:00:00] [ORCH] [$lvl] hello")
            $e = ConvertFrom-MaintenanceLog -Path $p
            @($e).Count | Should -Be 1
            $e[0].Level | Should -Be $lvl
            $e[0].Component | Should -Be 'ORCH'
        }
    }

    It 'degrades an unknown level to RAW instead of inventing one' {
        # The exact line script.bat used to emit: cmd.exe has no backslash escape, so the
        # \" in the message shifted the level/component arguments.
        $p = New-TestLog @('[20:06:05] [DEBUG] [Files\PowerShell\7\pwsh.exe\] Launching: \"C:\Program ')
        $e = ConvertFrom-MaintenanceLog -Path $p
        @($e).Count | Should -Be 1
        $e[0].Level | Should -Be 'RAW' -Because 'no chip exists for an arbitrary level, so the row would be unreachable'
    }

    It 'keeps the whole original line when it degrades to RAW' {
        # Losing the text would be worse than mislabelling it.
        $line = '[20:06:05] [DEBUG] [Files\PowerShell\7\pwsh.exe\] Launching: \"C:\Program '
        $e = ConvertFrom-MaintenanceLog -Path (New-TestLog @($line))
        $e[0].Message | Should -Be $line
    }

    It 'never emits a level that could break a CSS class or HTML attribute' {
        $p = New-TestLog @(
            '[12:00:00] [ORCH] [INFO] fine'
            "[12:00:01] [X] [has space] msg"
            "[12:00:02] [X] [quote'd] msg"
            '[12:00:03] [X] [back\slash] msg'
        )
        foreach ($e in (ConvertFrom-MaintenanceLog -Path $p)) {
            $e.Level | Should -Match '^(FATAL|ERROR|WARN|SUCCESS|INFO|DEBUG|RAW)$'
        }
    }

    It 'still treats a genuinely unstructured line as RAW' {
        $e = ConvertFrom-MaintenanceLog -Path (New-TestLog @('=========== banner ==========='))
        $e[0].Level | Should -Be 'RAW'
    }
}

Describe 'module card ExtraData ordering' {

    It 'sorts keys so the same data renders identically every run' {
        $script:Gen | Should -Match '\$Result\.ExtraData\.GetEnumerator\(\)\s*\|\s*Sort-Object'
    }

    It 'sorts nested keys too, so a group stays contiguous' {
        $script:Gen | Should -Match '\$kv\.Value\.GetEnumerator\(\)\s*\|\s*Sort-Object'
    }
}

Describe 'Defender incident collection is limited to real detections' {

    BeforeAll {
        $script:Audit = Get-Content (Join-Path $script:RepoRoot 'modules\type1\SystemConfigurationAudit.psm1') -Raw
    }

    It 'filters the Operational log by detection event id' {
        # Without this the query returned every 5007 config-change and 1150 health event,
        # so a clean machine reported 170 "incidents".
        $script:Audit | Should -Match 'EventID=' -Because 'the XPath must constrain event ids'
        $script:Audit | Should -Match '1116' -Because '1116 is the primary malware-detected event'
    }

    It 'does not treat 5007 (configuration changed) as an incident' {
        $ids = [regex]::Match($script:Audit, '\$detectionIds\s*=\s*([\d,\s]+)').Groups[1].Value
        $ids | Should -Not -BeNullOrEmpty
        ($ids -split ',').Trim() | Should -Not -Contain '5007'
    }

    It 'reads event payload by name rather than positional index' {
        # Properties[2]/[3]/[7] mean different things per event id - that is how a registry
        # path ended up in the Threat column.
        $script:Audit | Should -Match "named\['Threat Name'\]"
        $script:Audit | Should -Not -Match '\$eventData\[\d\]' -Because 'positional payload access is id-dependent'
    }
}
