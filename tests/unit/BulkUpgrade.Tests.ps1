#Requires -Version 7.0
<#
    Tests for the bulk `winget upgrade --all` path in Phase 3 of Invoke-SoftwareManagement.

    WHY THE BULK PATH EXISTS. The per-package ladder re-selects each package by Id/Name, so it
    depends on identifiers recovered from winget's rendered table. That table is width-fitted:
    long Ids come back truncated with an ellipsis, and rows whose columns collapse are rejected
    by the parser. Neither is repairable downstream. `winget upgrade --all` never serialises an
    identifier through text at all - it upgrades the package objects winget already resolved -
    which is why running it by hand works on machines where this module reported nothing to do.

    THE TWO RULES THESE TESTS PROTECT:

      1. `--all` runs ONLY when nothing upgradable was excluded. It has no per-package
         exemption, so using it while an ExcludePatterns match is present would upgrade exactly
         the packages (Visual Studio, SQL Server, Docker, pinned toolchains) the exclusion list
         exists to protect. This is the dangerous direction to get wrong.

      2. Success is VERIFIED by re-enumerating, never inferred from the exit code. `--all`
         returns non-zero when any single package fails, so the code says nothing about the
         rest. A failed verification query must NOT be read as "everything upgraded".

    Every external process call is mocked; nothing here touches the machine or winget.
#>

BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:RepoRoot 'modules\core\Maintenance.psm1') -Force -Global -ErrorAction Stop
    Import-Module (Join-Path $script:RepoRoot 'modules\type2\SoftwareManagement.psm1') -Force -ErrorAction Stop
}

Describe 'Phase 3 bulk upgrade (winget upgrade --all)' {

    Context 'rule 1: --all only when nothing upgradable was excluded' {

        It 'uses --all when every winget item is BulkUpgradeEligible' {
            InModuleScope SoftwareManagement {
                $script:cmds = [System.Collections.Generic.List[string]]::new()
                Mock Get-DiffList { , @(
                        @{ Action = 'upgrade'; Name = 'Mozilla Firefox'; Id = 'Mozilla.Firefox'
                            Source = 'winget'; BulkUpgradeEligible = $true; BulkTimeoutSeconds = 7200 }
                        @{ Action = 'upgrade'; Name = '7-Zip'; Id = '7zip.7zip'
                            Source = 'winget'; BulkUpgradeEligible = $true; BulkTimeoutSeconds = 7200 }
                    ) }
                Mock Get-OSContext { @{ IsWindows11 = $true } }
                Mock Test-CommandAvailable { $true }
                Mock Resolve-WingetPath { 'winget.exe' }
                Mock Invoke-ExternalPackageCommand { $script:cmds.Add(($ArgumentList -join ' ')); 0 }
                # Verification re-query: nothing left, exit 0 -> both upgraded.
                Mock Invoke-CapturedCommand { @{ ExitCode = 0; StdOut = ''; StdErr = ''; TimedOut = $false } }

                $r = Invoke-SoftwareManagement -OSContext @{ IsWindows11 = $true }

                @($script:cmds | Where-Object { $_ -like 'upgrade --all*' }).Count | Should -Be 1
                @($script:cmds | Where-Object { $_ -like 'upgrade --id*' }).Count | Should -Be 0 `
                    -Because 'the bulk pass already confirmed both, so no per-package retry is needed'
                $r.ItemsProcessed | Should -Be 2
            }
        }

        It 'does NOT use --all when any winget item is not BulkUpgradeEligible' {
            InModuleScope SoftwareManagement {
                $script:cmds = [System.Collections.Generic.List[string]]::new()
                Mock Get-DiffList { , @(
                        @{ Action = 'upgrade'; Name = 'Mozilla Firefox'; Id = 'Mozilla.Firefox'
                            Source = 'winget'; BulkUpgradeEligible = $false }
                    ) }
                Mock Get-OSContext { @{ IsWindows11 = $true } }
                Mock Test-CommandAvailable { $true }
                Mock Resolve-WingetPath { 'winget.exe' }
                Mock Invoke-ExternalPackageCommand { $script:cmds.Add(($ArgumentList -join ' ')); 0 }
                Mock Invoke-CapturedCommand { @{ ExitCode = 0; StdOut = ''; StdErr = ''; TimedOut = $false } }

                $null = Invoke-SoftwareManagement -OSContext @{ IsWindows11 = $true }

                @($script:cmds | Where-Object { $_ -like 'upgrade --all*' }).Count | Should -Be 0 `
                    -Because '--all cannot exempt the excluded package, so it must not run at all'
                @($script:cmds | Where-Object { $_ -like 'upgrade --id*' }).Count | Should -Be 1
            }
        }

        It 'treats a MISSING BulkUpgradeEligible key as not eligible' {
            # Fail-safe direction: an old diff, or a future code path that forgets the key,
            # must never silently enable an unfiltered --all.
            InModuleScope SoftwareManagement {
                $script:cmds = [System.Collections.Generic.List[string]]::new()
                Mock Get-DiffList { , @(@{ Action = 'upgrade'; Name = 'App'; Id = 'A.B'; Source = 'winget' }) }
                Mock Get-OSContext { @{ IsWindows11 = $true } }
                Mock Test-CommandAvailable { $true }
                Mock Resolve-WingetPath { 'winget.exe' }
                Mock Invoke-ExternalPackageCommand { $script:cmds.Add(($ArgumentList -join ' ')); 0 }
                Mock Invoke-CapturedCommand { @{ ExitCode = 0; StdOut = ''; StdErr = ''; TimedOut = $false } }

                $null = Invoke-SoftwareManagement -OSContext @{ IsWindows11 = $true }
                @($script:cmds | Where-Object { $_ -like 'upgrade --all*' }).Count | Should -Be 0
            }
        }

        It 'does not run --all when there are only chocolatey items' {
            InModuleScope SoftwareManagement {
                $script:cmds = [System.Collections.Generic.List[string]]::new()
                Mock Get-DiffList { , @(@{ Action = 'upgrade'; Name = 'np.install'; Id = 'np.install'
                            Source = 'choco'; BulkUpgradeEligible = $false }) }
                Mock Get-OSContext { @{ IsWindows11 = $true } }
                Mock Test-CommandAvailable { $true }
                Mock Resolve-WingetPath { 'winget.exe' }
                Mock Invoke-ExternalPackageCommand { $script:cmds.Add(($ArgumentList -join ' ')); 0 }
                Mock Invoke-CapturedCommand { @{ ExitCode = 0; StdOut = ''; StdErr = ''; TimedOut = $false } }

                $r = Invoke-SoftwareManagement -OSContext @{ IsWindows11 = $true }
                @($script:cmds | Where-Object { $_ -like 'upgrade --all*' }).Count | Should -Be 0
                $r.ItemsProcessed | Should -Be 1
            }
        }
    }

    Context 'rule 2: results are verified by re-enumeration, not by exit code' {

        It 'retries individually the packages still listed after --all' {
            InModuleScope SoftwareManagement {
                $script:cmds = [System.Collections.Generic.List[string]]::new()
                Mock Get-DiffList { , @(
                        @{ Action = 'upgrade'; Name = 'Mozilla Firefox'; Id = 'Mozilla.Firefox'
                            Source = 'winget'; BulkUpgradeEligible = $true }
                        @{ Action = 'upgrade'; Name = 'Stubborn App'; Id = 'Stub.App'
                            Source = 'winget'; BulkUpgradeEligible = $true }
                    ) }
                Mock Get-OSContext { @{ IsWindows11 = $true } }
                Mock Test-CommandAvailable { $true }
                Mock Resolve-WingetPath { 'winget.exe' }
                Mock Invoke-ExternalPackageCommand { $script:cmds.Add(($ArgumentList -join ' ')); 0 }
                # Stubborn App is STILL listed after --all; Firefox is gone.
                Mock Invoke-CapturedCommand {
                    @{ ExitCode = 0; TimedOut = $false; StdErr = ''; StdOut = @(
                            'Name           Id          Version  Available  Source'
                            '------------------------------------------------------'
                            'Stubborn App   Stub.App    1.0      2.0        winget'
                        ) -join "`r`n" }
                }

                $r = Invoke-SoftwareManagement -OSContext @{ IsWindows11 = $true }

                @($script:cmds | Where-Object { $_ -like 'upgrade --all*' }).Count | Should -Be 1
                $idRetries = @($script:cmds | Where-Object { $_ -like 'upgrade --id*' })
                $idRetries.Count | Should -Be 1 -Because 'only the straggler needs a retry'
                $idRetries[0] | Should -BeLike '*Stub.App*'
                $r.ItemsProcessed | Should -Be 2 -Because 'Firefox via --all, Stubborn App via the retry'
            }
        }

        It 'does NOT claim success when the verification query fails' {
            InModuleScope SoftwareManagement {
                $script:cmds = [System.Collections.Generic.List[string]]::new()
                Mock Get-DiffList { , @(@{ Action = 'upgrade'; Name = 'App One'; Id = 'One.App'
                            Source = 'winget'; BulkUpgradeEligible = $true }) }
                Mock Get-OSContext { @{ IsWindows11 = $true } }
                Mock Test-CommandAvailable { $true }
                Mock Resolve-WingetPath { 'winget.exe' }
                Mock Invoke-ExternalPackageCommand { $script:cmds.Add(($ArgumentList -join ' ')); 0 }
                # Query itself failed: non-zero exit AND no parsable table.
                Mock Invoke-CapturedCommand { @{ ExitCode = 1; StdOut = 'catastrophic failure'; StdErr = ''; TimedOut = $false } }

                $null = Invoke-SoftwareManagement -OSContext @{ IsWindows11 = $true }

                @($script:cmds | Where-Object { $_ -like 'upgrade --id*' }).Count | Should -Be 1 `
                    -Because 'an unusable verification must fall back to per-package attempts, not assume success'
            }
        }

        It 'does NOT claim success when the verification query times out' {
            InModuleScope SoftwareManagement {
                $script:cmds = [System.Collections.Generic.List[string]]::new()
                Mock Get-DiffList { , @(@{ Action = 'upgrade'; Name = 'App One'; Id = 'One.App'
                            Source = 'winget'; BulkUpgradeEligible = $true }) }
                Mock Get-OSContext { @{ IsWindows11 = $true } }
                Mock Test-CommandAvailable { $true }
                Mock Resolve-WingetPath { 'winget.exe' }
                Mock Invoke-ExternalPackageCommand { $script:cmds.Add(($ArgumentList -join ' ')); 0 }
                Mock Invoke-CapturedCommand { @{ ExitCode = -1; StdOut = ''; StdErr = ''; TimedOut = $true } }

                $null = Invoke-SoftwareManagement -OSContext @{ IsWindows11 = $true }
                @($script:cmds | Where-Object { $_ -like 'upgrade --id*' }).Count | Should -Be 1
            }
        }

        It 'still verifies (and does not double-count) when --all exits non-zero' {
            # --all returns non-zero if ANY package failed. The packages that DID upgrade must
            # still be credited, and the exit code alone must not condemn them.
            InModuleScope SoftwareManagement {
                Mock Get-DiffList { , @(@{ Action = 'upgrade'; Name = 'App One'; Id = 'One.App'
                            Source = 'winget'; BulkUpgradeEligible = $true }) }
                Mock Get-OSContext { @{ IsWindows11 = $true } }
                Mock Test-CommandAvailable { $true }
                Mock Resolve-WingetPath { 'winget.exe' }
                Mock Invoke-ExternalPackageCommand { -1978335215 }
                Mock Invoke-CapturedCommand { @{ ExitCode = 0; StdOut = ''; StdErr = ''; TimedOut = $false } }

                $r = Invoke-SoftwareManagement -OSContext @{ IsWindows11 = $true }
                $r.ItemsProcessed | Should -Be 1
                $r.ItemsFailed | Should -Be 0
            }
        }
    }

    Context 'bulk timeout' {

        It 'uses BulkTimeoutSeconds for the --all command, not the per-item timeout' {
            InModuleScope SoftwareManagement {
                $script:bulkTimeout = $null
                Mock Get-DiffList { , @(@{ Action = 'upgrade'; Name = 'App One'; Id = 'One.App'
                            Source = 'winget'; BulkUpgradeEligible = $true
                            TimeoutSeconds = 1800; BulkTimeoutSeconds = 7200 }) }
                Mock Get-OSContext { @{ IsWindows11 = $true } }
                Mock Test-CommandAvailable { $true }
                Mock Resolve-WingetPath { 'winget.exe' }
                Mock Invoke-ExternalPackageCommand {
                    if (($ArgumentList -join ' ') -like 'upgrade --all*') { $script:bulkTimeout = $TimeoutSeconds }
                    0
                }
                Mock Invoke-CapturedCommand { @{ ExitCode = 0; StdOut = ''; StdErr = ''; TimedOut = $false } }

                $null = Invoke-SoftwareManagement -OSContext @{ IsWindows11 = $true }
                $script:bulkTimeout | Should -Be 7200 `
                    -Because 'the batch covers many packages; the 1800s per-item budget would kill it partway'
            }
        }
    }
}
