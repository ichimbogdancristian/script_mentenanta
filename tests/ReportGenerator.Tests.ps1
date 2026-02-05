#Requires -Version 7.0

$modulePath = Join-Path $PSScriptRoot '..\modules\core\ReportGenerator.psm1'
Import-Module $modulePath -Force

Describe 'ReportGenerator module details' {
    It 'Adds diff coverage section when diff items exist' {
        InModuleScope ReportGenerator {
            $moduleData = [PSCustomObject]@{
                DiffItems = @(
                    @{ Name = 'ItemA' },
                    @{ Name = 'ItemB' }
                )
                DiffSummary = @{ Total = 2 }
            }

            $html = Build-ModuleDetailsSection -ModuleData $moduleData -ModuleKey 'TestModule'

            $html | Should -Match 'Diff Coverage'
            $html | Should -Match 'ItemA'
        }
    }
}
