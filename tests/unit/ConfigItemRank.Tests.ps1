#Requires -Version 7.0
<#
    Unit tests for Get-ConfigItemRank (modules/type2/SystemConfiguration.psm1).

    This function is a CORRECTNESS guarantee, not a style choice. When RestorePointManagement
    was folded into the SystemConfiguration pair, the orchestrator lost the ability to sequence
    the restore point via $Stage3Order, so the ordering guarantee moved inside the module:

      restore point 'create' (0)  MUST precede every other mutation, or the snapshot is of an
                                  already-modified system and is useless for rollback.
      security (1) -> telemetry (2) -> optimization (3)
      restore point 'remove'  (4)  MUST come last - pruning is destructive and irreversible,
                                  and pruning first would discard the very rollback targets a
                                  failed run would need.

    If these tests fail, the rollback safety net is broken.
#>

BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:RepoRoot 'modules\core\Maintenance.psm1') -Force -Global -ErrorAction Stop
    Import-Module (Join-Path $script:RepoRoot 'modules\type2\SystemConfiguration.psm1') -Force -ErrorAction Stop
}

Describe 'Get-ConfigItemRank' {

    Context 'individual ranks' {
        It 'ranks restore point creation first (0)' {
            InModuleScope SystemConfiguration {
                Get-ConfigItemRank -Item @{ ConfigType = 'restorepoint'; Action = 'create' } | Should -Be 0
            }
        }

        It 'ranks security second (1)' {
            InModuleScope SystemConfiguration {
                Get-ConfigItemRank -Item @{ ConfigType = 'security' } | Should -Be 1
            }
        }

        It 'ranks telemetry third (2)' {
            InModuleScope SystemConfiguration {
                Get-ConfigItemRank -Item @{ ConfigType = 'telemetry' } | Should -Be 2
            }
        }

        It 'ranks optimization fourth (3)' {
            InModuleScope SystemConfiguration {
                Get-ConfigItemRank -Item @{ ConfigType = 'optimization' } | Should -Be 3
            }
        }

        It 'ranks restore point removal last (4)' {
            InModuleScope SystemConfiguration {
                Get-ConfigItemRank -Item @{ ConfigType = 'restorepoint'; Action = 'remove' } | Should -Be 4
            }
        }

        It 'ranks an unknown ConfigType in the middle (3), never first or last' {
            InModuleScope SystemConfiguration {
                $r = Get-ConfigItemRank -Item @{ ConfigType = 'somethingNew' }
                $r | Should -Be 3
                $r | Should -BeGreaterThan 0 -Because 'an unknown type must never pre-empt the restore point'
                $r | Should -BeLessThan 4 -Because 'an unknown type must never run after destructive pruning'
            }
        }

        It 'treats a restore point item with no Action as a removal (4), not a creation' {
            # Fail-safe direction: an ambiguous restore point item must not be allowed to
            # masquerade as the safety-net creation step.
            InModuleScope SystemConfiguration {
                Get-ConfigItemRank -Item @{ ConfigType = 'restorepoint' } | Should -Be 4
            }
        }
    }

    Context 'end-to-end ordering guarantee' {
        It 'sorts a shuffled diff into create -> security -> telemetry -> optimization -> remove' {
            InModuleScope SystemConfiguration {
                $shuffled = @(
                    @{ ConfigType = 'optimization'; Name = 'opt1' }
                    @{ ConfigType = 'restorepoint'; Action = 'remove'; Name = 'prune1' }
                    @{ ConfigType = 'telemetry'; Name = 'tel1' }
                    @{ ConfigType = 'restorepoint'; Action = 'create'; Name = 'create1' }
                    @{ ConfigType = 'security'; Name = 'sec1' }
                )
                $sorted = @($shuffled | Sort-Object -Stable { Get-ConfigItemRank -Item $_ })
                $sorted[0].Name | Should -Be 'create1'
                $sorted[1].Name | Should -Be 'sec1'
                $sorted[2].Name | Should -Be 'tel1'
                $sorted[3].Name | Should -Be 'opt1'
                $sorted[4].Name | Should -Be 'prune1'
            }
        }

        It 'always places creation before every mutating item' {
            InModuleScope SystemConfiguration {
                $items = @(
                    @{ ConfigType = 'security' }, @{ ConfigType = 'telemetry' },
                    @{ ConfigType = 'optimization' }, @{ ConfigType = 'restorepoint'; Action = 'create' }
                )
                $sorted = @($items | Sort-Object -Stable { Get-ConfigItemRank -Item $_ })
                $sorted[0].ConfigType | Should -Be 'restorepoint'
                $sorted[0].Action | Should -Be 'create'
            }
        }

        It 'always places pruning after every other item' {
            InModuleScope SystemConfiguration {
                $items = @(
                    @{ ConfigType = 'restorepoint'; Action = 'remove' }, @{ ConfigType = 'security' },
                    @{ ConfigType = 'restorepoint'; Action = 'create' }, @{ ConfigType = 'optimization' }
                )
                $sorted = @($items | Sort-Object -Stable { Get-ConfigItemRank -Item $_ })
                $sorted[-1].Action | Should -Be 'remove'
            }
        }

        It 'preserves within-rank ordering from the audit (stable sort)' {
            InModuleScope SystemConfiguration {
                $items = @(
                    @{ ConfigType = 'security'; Name = 'first' }
                    @{ ConfigType = 'security'; Name = 'second' }
                    @{ ConfigType = 'security'; Name = 'third' }
                )
                $sorted = @($items | Sort-Object -Stable { Get-ConfigItemRank -Item $_ })
                $sorted.Name -join ',' | Should -Be 'first,second,third'
            }
        }
    }
}
