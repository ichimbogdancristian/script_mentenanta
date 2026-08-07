#Requires -Version 7.0
<#
    Contract tests for $ModulePairs - the single source of truth for what actually runs.

    These catch the "silently does nothing" bug class. DiffKey is the contract between a
    Type1 module, its Type2 partner and the orchestrator; if any of the three drift apart,
    Stage 2 finds an empty diff, skips the pair, and the run reports success while having
    done nothing. Nothing in the codebase notices. These tests notice.

    The orchestrator is NOT dot-sourced - it carries '#Requires -RunAsAdministrator' and
    executing it would run the entire five-stage pipeline. $ModulePairs and $Stage3Order are
    extracted from the abstract syntax tree instead, which is both safe and side-effect free.
#>

BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:OrchPath = Join-Path $script:RepoRoot 'MaintenanceOrchestrator.ps1'

    function Get-AstArrayVariable {
        # PSReviewUnusedParameter cannot see through the FindAll() predicate scriptblock,
        # where $VariableName is captured from this scope and genuinely used.
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'VariableName',
            Justification = 'Used inside the FindAll predicate scriptblock below')]
        param([string]$Path, [string]$VariableName)
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$null)
        $assign = $ast.FindAll({
                param($n)
                $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                $n.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and
                $n.Left.VariablePath.UserPath -eq $VariableName
            }, $true) | Select-Object -First 1
        if (-not $assign) { return $null }
        # The right-hand side is a literal array of literal hashtables in this file, so
        # evaluating just that sub-expression is safe and runs none of the script body.
        return (& ([scriptblock]::Create($assign.Right.Extent.Text)))
    }

    $script:Pairs = @(Get-AstArrayVariable -Path $script:OrchPath -VariableName 'ModulePairs')
    $script:Stage3Order = @(Get-AstArrayVariable -Path $script:OrchPath -VariableName 'Stage3Order')
    $script:MainConfig = Get-Content (Join-Path $script:RepoRoot 'config\settings\main-config.json') -Raw |
        ConvertFrom-Json -AsHashtable
}

Describe '$ModulePairs extraction' {
    It 'finds the $ModulePairs array in the orchestrator' {
        $script:Pairs.Count | Should -BeGreaterThan 0
    }

    It 'finds the $Stage3Order array in the orchestrator' {
        $script:Stage3Order.Count | Should -BeGreaterThan 0
    }
}

Describe 'Module pair integrity' {

    It 'declares every required key on every pair' {
        foreach ($p in $script:Pairs) {
            foreach ($k in 'Num', 'Label', 'DiffKey', 'Type1File', 'Type1Func', 'Type2File', 'Type2Func', 'ConfigSkip') {
                $p.ContainsKey($k) | Should -BeTrue -Because "pair '$($p.Label)' must declare '$k'"
                $p[$k] | Should -Not -BeNullOrEmpty -Because "pair '$($p.Label)' has an empty '$k'"
            }
        }
    }

    It 'uses unique Num values (the stable id for -TaskNumbers and the menu)' {
        $nums = $script:Pairs.Num
        ($nums | Select-Object -Unique).Count | Should -Be $nums.Count
    }

    It 'uses unique DiffKey values (the diff filename stem)' {
        $keys = $script:Pairs.DiffKey
        ($keys | Select-Object -Unique).Count | Should -Be $keys.Count
    }

    It 'points Type1File at a file that exists' {
        foreach ($p in $script:Pairs) {
            $full = Join-Path $script:RepoRoot $p.Type1File
            Test-Path -LiteralPath $full | Should -BeTrue -Because "$($p.DiffKey) Type1File '$($p.Type1File)' must exist"
        }
    }

    It 'points Type2File at a file that exists' {
        foreach ($p in $script:Pairs) {
            $full = Join-Path $script:RepoRoot $p.Type2File
            Test-Path -LiteralPath $full | Should -BeTrue -Because "$($p.DiffKey) Type2File '$($p.Type2File)' must exist"
        }
    }

    It 'places Type1 modules under modules\type1 and Type2 under modules\type2' {
        foreach ($p in $script:Pairs) {
            $p.Type1File | Should -Match 'type1' -Because "$($p.DiffKey) audit module belongs in type1"
            $p.Type2File | Should -Match 'type2' -Because "$($p.DiffKey) action module belongs in type2"
        }
    }
}

Describe 'Declared functions are actually exported' {
    # Invoke-ModuleFunction imports the file then resolves the function by name. If the name
    # is wrong or not exported, the orchestrator logs an error and returns $null - the pair
    # silently does nothing for the whole run.

    It 'exports every Type1Func from its declared module' {
        foreach ($p in $script:Pairs) {
            $full = Join-Path $script:RepoRoot $p.Type1File
            Import-Module $full -Force -Global -WarningAction SilentlyContinue -ErrorAction Stop
            $modName = [System.IO.Path]::GetFileNameWithoutExtension($p.Type1File)
            $exported = (Get-Module $modName).ExportedFunctions.Keys
            $exported | Should -Contain $p.Type1Func -Because "$($p.DiffKey): orchestrator calls '$($p.Type1Func)'"
        }
    }

    It 'exports every Type2Func from its declared module' {
        foreach ($p in $script:Pairs) {
            $full = Join-Path $script:RepoRoot $p.Type2File
            Import-Module $full -Force -Global -WarningAction SilentlyContinue -ErrorAction Stop
            $modName = [System.IO.Path]::GetFileNameWithoutExtension($p.Type2File)
            $exported = (Get-Module $modName).ExportedFunctions.Keys
            $exported | Should -Contain $p.Type2Func -Because "$($p.DiffKey): orchestrator calls '$($p.Type2Func)'"
        }
    }
}

Describe 'DiffKey is used consistently on both sides of the pair' {
    # Save-DiffList -ModuleName <DiffKey> on the Type1 side must match
    # Get-DiffList  -ModuleName <DiffKey> on the Type2 side.

    It 'has the Type1 module save a diff under its declared DiffKey' {
        foreach ($p in $script:Pairs) {
            $src = Get-Content (Join-Path $script:RepoRoot $p.Type1File) -Raw
            $src | Should -Match "Save-DiffList[\s\S]{0,120}$([regex]::Escape($p.DiffKey))" `
                -Because "$($p.Type1File) must Save-DiffList under '$($p.DiffKey)'"
        }
    }

    It 'has the Type2 module read a diff under its declared DiffKey' {
        foreach ($p in $script:Pairs) {
            $src = Get-Content (Join-Path $script:RepoRoot $p.Type2File) -Raw
            $src | Should -Match "Get-DiffList[\s\S]{0,120}$([regex]::Escape($p.DiffKey))" `
                -Because "$($p.Type2File) must Get-DiffList under '$($p.DiffKey)'"
        }
    }
}

Describe 'ConfigSkip keys resolve in main-config.json' {
    It 'defines every ConfigSkip flag under .modules' {
        foreach ($p in $script:Pairs) {
            $script:MainConfig.modules.ContainsKey($p.ConfigSkip) | Should -BeTrue `
                -Because "main-config.json .modules must define '$($p.ConfigSkip)' or the pair can never be skipped"
        }
    }

    It 'declares every ConfigSkip flag as a boolean' {
        foreach ($p in $script:Pairs) {
            $script:MainConfig.modules[$p.ConfigSkip] | Should -BeOfType [bool]
        }
    }
}

Describe 'Stage 3 execution order' {
    It 'references only real DiffKeys' {
        foreach ($k in $script:Stage3Order) {
            $script:Pairs.DiffKey | Should -Contain $k -Because "'$k' in \$Stage3Order matches no pair"
        }
    }

    It 'covers every pair, so nothing falls through to the unordered 999 bucket' {
        foreach ($p in $script:Pairs) {
            $script:Stage3Order | Should -Contain $p.DiffKey `
                -Because "$($p.DiffKey) has no explicit Stage 3 position"
        }
    }

    It 'runs SystemConfiguration first (it owns the restore point safety net)' {
        $script:Stage3Order[0] | Should -Be 'SystemConfiguration' `
            -Because 'the restore point must precede every other mutating module'
    }

    It 'runs DiskCleanup last (it sweeps residue the earlier modules created)' {
        $script:Stage3Order[-1] | Should -Be 'DiskCleanup'
    }
}

Describe 'Module file hygiene' {
    It 'requires PowerShell 7 in every module' {
        $mods = Get-ChildItem (Join-Path $script:RepoRoot 'modules') -Recurse -Filter *.psm1
        foreach ($m in $mods) {
            ((Get-Content $m.FullName -TotalCount 5) -join "`n") | Should -Match '#Requires -Version 7' `
                -Because "$($m.Name) runs only under pwsh 7"
        }
    }

    It 'parses every module and script without syntax errors' {
        $files = @(Get-ChildItem (Join-Path $script:RepoRoot 'modules') -Recurse -Filter *.psm1) +
                 @(Get-Item $script:OrchPath)
        foreach ($f in $files) {
            $errors = $null
            [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$null, [ref]$errors) | Out-Null
            $errors.Count | Should -Be 0 -Because "$($f.Name) must parse cleanly"
        }
    }
}
