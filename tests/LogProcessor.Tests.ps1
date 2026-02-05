#Requires -Version 7.0

$modulePath = Join-Path $PSScriptRoot '..\modules\core\LogProcessor.psm1'
Import-Module $modulePath -Force

Describe 'LogProcessor diff ingestion' {
    It 'Returns empty diff summary when temp folder missing' {
        InModuleScope LogProcessor {
            Mock Get-MaintenancePath { Join-Path $TestDrive 'temp_files' }

            $result = Get-DiffLists

            $result.Summary.TotalModules | Should -Be 0
            $result.Summary.TotalItems | Should -Be 0
        }
    }

    It 'Loads diff lists when files are present' {
        InModuleScope LogProcessor {
            $tempRoot = Join-Path $TestDrive 'temp_files'
            $tempDir = Join-Path $tempRoot 'temp'
            New-Item -Path $tempDir -ItemType Directory -Force | Out-Null

            $diffPath = Join-Path $tempDir 'bloatware-diff.json'
            @(@{ Name = 'App1' }, @{ Name = 'App2' }) | ConvertTo-Json -Depth 5 | Set-Content $diffPath -Encoding UTF8

            Mock Get-MaintenancePath { $tempRoot }

            $result = Get-DiffLists

            $result.Summary.TotalModules | Should -Be 1
            $result.Summary.TotalItems | Should -Be 2
            $result.DiffLists.ContainsKey('bloatware') | Should -BeTrue
        }
    }
}
