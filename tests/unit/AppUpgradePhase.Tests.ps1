#Requires -Version 7.0
<#
    Behavioural tests for Phase 3 (UPGRADE) of Invoke-SoftwareManagement
    (modules/type2/SoftwareManagement.psm1).

    The upgrade phase had no coverage at all, and three defects lived in it at once:

      1. ARGUMENT QUOTING. Invoke-ExternalPackageCommand builds its command line with
         `$ArgumentList -join ' '`, so an unquoted multi-word display Name was torn into
         separate arguments - verified directly against a child process: 'Mozilla Firefox'
         arrived as '--name Mozilla' plus a stray positional 'Firefox'. winget display Names
         are usually multi-word, so the --name and positional fallbacks could essentially
         never bind for the packages that needed them.

      2. THE LADDER STOPPED TOO EARLY. --name and the positional query were only tried when
         --id returned -1978335212 (NO_APPLICATIONS_FOUND). Any other failing code ended the
         attempt, even though --id (strict ARP-correlation), --name (the looser match the bulk
         `winget upgrade --all` path uses) and the positional query (name/moniker/tag search)
         are genuinely different match paths.

      3. FALSE FAILURES. A package no form could match was counted as ItemsFailed, which put
         phantom errors in the report and dropped the module to Warning/Failed on runs where
         nothing was actually wrong. "Nothing here matched" is a skip, not a failure.

    Every external process call is mocked; nothing here touches the machine or winget.
#>

BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:RepoRoot 'modules\core\Maintenance.psm1') -Force -Global -ErrorAction Stop
    Import-Module (Join-Path $script:RepoRoot 'modules\type2\SoftwareManagement.psm1') -Force -ErrorAction Stop
}

Describe 'Invoke-SoftwareManagement - Phase 3 upgrade' {

    Context 'argument quoting for multi-word package names (defect 1)' {

        It 'quotes a multi-word name so it survives the -join as ONE argument' {
            InModuleScope SoftwareManagement {
                $script:seen = [System.Collections.Generic.List[string]]::new()
                Mock Get-DiffList { , @(@{ Action = 'upgrade'; Name = 'Mozilla Firefox'
                            Id = 'Mozilla.Firefox'; Source = 'winget' }) }
                Mock Get-OSContext { @{ IsWindows11 = $true } }
                Mock Test-CommandAvailable { $true }
                Mock Resolve-WingetPath { 'winget.exe' }
                # --id misses, so the ladder proceeds to --name.
                Mock Invoke-ExternalPackageCommand {
                    $script:seen.Add(($ArgumentList -join ' '))
                    -1978335212
                }

                $null = Invoke-SoftwareManagement -OSContext @{ IsWindows11 = $true }

                $nameForm = $script:seen | Where-Object { $_ -like '*--name*' }
                $nameForm | Should -Not -BeNullOrEmpty
                $nameForm | Should -BeLike '*--name "Mozilla Firefox"*' `
                    -Because 'an unquoted name is split into two arguments by the -join'
            }
        }

        It 'does not add quotes to a single-word id' {
            InModuleScope SoftwareManagement {
                $script:seen = [System.Collections.Generic.List[string]]::new()
                Mock Get-DiffList { , @(@{ Action = 'upgrade'; Name = 'SevenZip'
                            Id = '7zip.7zip'; Source = 'winget' }) }
                Mock Get-OSContext { @{ IsWindows11 = $true } }
                Mock Test-CommandAvailable { $true }
                Mock Resolve-WingetPath { 'winget.exe' }
                Mock Invoke-ExternalPackageCommand { $script:seen.Add(($ArgumentList -join ' ')); 0 }

                $null = Invoke-SoftwareManagement -OSContext @{ IsWindows11 = $true }

                ($script:seen | Where-Object { $_ -like '*--id*' }) | Should -BeLike '*--id 7zip.7zip *'
            }
        }
    }

    Context 'the full fallback ladder is attempted (defect 2)' {

        It 'tries all three forms when --id fails to MATCH (NO_APPLICATIONS_FOUND)' {
            InModuleScope SoftwareManagement {
                $script:forms = [System.Collections.Generic.List[string]]::new()
                Mock Get-DiffList { , @(@{ Action = 'upgrade'; Name = 'Some App'
                            Id = 'Vendor.SomeApp'; Source = 'winget' }) }
                Mock Get-OSContext { @{ IsWindows11 = $true } }
                Mock Test-CommandAvailable { $true }
                Mock Resolve-WingetPath { 'winget.exe' }
                Mock Invoke-ExternalPackageCommand {
                    $joined = $ArgumentList -join ' '
                    if ($joined -like 'upgrade*') { $script:forms.Add($joined) }
                    -1978335212   # NO_APPLICATIONS_FOUND - a matching failure
                }

                $null = Invoke-SoftwareManagement -OSContext @{ IsWindows11 = $true }

                $script:forms.Count | Should -Be 3 `
                    -Because 'all three match paths must be tried before giving up on resolving it'
                @($script:forms | Where-Object { $_ -like '*--id*' }).Count | Should -Be 1
                @($script:forms | Where-Object { $_ -like '*--name*' }).Count | Should -Be 1
            }
        }

        It 'continues the ladder on an AMBIGUOUS match (-1978335129)' {
            InModuleScope SoftwareManagement {
                $script:forms = [System.Collections.Generic.List[string]]::new()
                Mock Get-DiffList { , @(@{ Action = 'upgrade'; Name = 'Some App'
                            Id = 'Vendor.SomeApp'; Source = 'winget' }) }
                Mock Get-OSContext { @{ IsWindows11 = $true } }
                Mock Test-CommandAvailable { $true }
                Mock Resolve-WingetPath { 'winget.exe' }
                Mock Invoke-ExternalPackageCommand {
                    $joined = $ArgumentList -join ' '
                    if ($joined -like 'upgrade*') { $script:forms.Add($joined) }
                    -1978335129   # MULTIPLE_APPLICATIONS_FOUND - also a matching failure
                }

                $null = Invoke-SoftwareManagement -OSContext @{ IsWindows11 = $true }
                $script:forms.Count | Should -Be 3
            }
        }

        It 'STOPS the ladder once a form binds and the operation itself fails' {
            # Re-running the ladder there would re-invoke the same installer through a
            # different selector - no new information, and on an unattended run it spends the
            # whole per-item timeout again for every remaining form.
            InModuleScope SoftwareManagement {
                $script:forms = [System.Collections.Generic.List[string]]::new()
                Mock Get-DiffList { , @(@{ Action = 'upgrade'; Name = 'Some App'
                            Id = 'Vendor.SomeApp'; Source = 'winget' }) }
                Mock Get-OSContext { @{ IsWindows11 = $true } }
                Mock Test-CommandAvailable { $true }
                Mock Resolve-WingetPath { 'winget.exe' }
                Mock Invoke-ExternalPackageCommand {
                    $joined = $ArgumentList -join ' '
                    if ($joined -like 'upgrade*') { $script:forms.Add($joined) }
                    -1978335215   # INSTALLER_HASH_MISMATCH - winget DID resolve the package
                }

                $r = Invoke-SoftwareManagement -OSContext @{ IsWindows11 = $true }
                $script:forms.Count | Should -Be 1 `
                    -Because 'the installer already ran and failed; other selectors reach the same installer'
                $r.ItemsFailed | Should -Be 1
            }
        }

        It 'stops at the first form that succeeds' {
            InModuleScope SoftwareManagement {
                $script:n = 0
                Mock Get-DiffList { , @(@{ Action = 'upgrade'; Name = 'Some App'
                            Id = 'Vendor.SomeApp'; Source = 'winget' }) }
                Mock Get-OSContext { @{ IsWindows11 = $true } }
                Mock Test-CommandAvailable { $true }
                Mock Resolve-WingetPath { 'winget.exe' }
                Mock Invoke-ExternalPackageCommand {
                    if (($ArgumentList -join ' ') -like 'upgrade*') { $script:n++ }
                    0
                }

                $r = Invoke-SoftwareManagement -OSContext @{ IsWindows11 = $true }
                $script:n | Should -Be 1
                $r.ItemsProcessed | Should -Be 1
            }
        }

        It 'treats UPDATE_NOT_APPLICABLE (-1978335189) as already-current, not a failure' {
            InModuleScope SoftwareManagement {
                Mock Get-DiffList { , @(@{ Action = 'upgrade'; Name = 'Some App'
                            Id = 'Vendor.SomeApp'; Source = 'winget' }) }
                Mock Get-OSContext { @{ IsWindows11 = $true } }
                Mock Test-CommandAvailable { $true }
                Mock Resolve-WingetPath { 'winget.exe' }
                Mock Invoke-ExternalPackageCommand { -1978335189 }

                $r = Invoke-SoftwareManagement -OSContext @{ IsWindows11 = $true }
                $r.ItemsProcessed | Should -Be 1
                $r.ItemsFailed | Should -Be 0
            }
        }
    }

    Context 'outcome classification: skipped vs failed (defect 3)' {

        It 'counts an unmatchable package as SKIPPED, not failed' {
            InModuleScope SoftwareManagement {
                Mock Get-DiffList { , @(@{ Action = 'upgrade'; Name = 'Ghost App'
                            Id = 'Ghost.App'; Source = 'winget'; VersionUnknown = $true }) }
                Mock Get-OSContext { @{ IsWindows11 = $true } }
                Mock Test-CommandAvailable { $true }
                Mock Resolve-WingetPath { 'winget.exe' }
                Mock Invoke-ExternalPackageCommand { -1978335212 }   # every form: no match

                $r = Invoke-SoftwareManagement -OSContext @{ IsWindows11 = $true }
                $r.ItemsSkipped | Should -Be 1
                $r.ItemsFailed | Should -Be 0
                $r.Status | Should -Be 'Success' `
                    -Because 'nothing went wrong - winget simply does not manage this package'
            }
        }

        It 'counts a package that BOUND and then errored as FAILED' {
            InModuleScope SoftwareManagement {
                Mock Get-DiffList { , @(@{ Action = 'upgrade'; Name = 'Real App'
                            Id = 'Real.App'; Source = 'winget' }) }
                Mock Get-OSContext { @{ IsWindows11 = $true } }
                Mock Test-CommandAvailable { $true }
                Mock Resolve-WingetPath { 'winget.exe' }
                Mock Invoke-ExternalPackageCommand { -1978335215 }   # bound, installer failed

                $r = Invoke-SoftwareManagement -OSContext @{ IsWindows11 = $true }
                $r.ItemsFailed | Should -Be 1
                $r.ItemsSkipped | Should -Be 0
            }
        }

        It 'skips (does not fail) when no upgrade mechanism is available at all' {
            InModuleScope SoftwareManagement {
                Mock Get-DiffList { , @(@{ Action = 'upgrade'; Name = 'Orphan'
                            Id = 'Orphan.App'; Source = 'winget' }) }
                Mock Get-OSContext { @{ IsWindows11 = $true } }
                Mock Test-CommandAvailable { $false }   # no winget, no choco
                Mock Resolve-WingetPath { 'winget.exe' }
                Mock Invoke-ExternalPackageCommand { 0 }

                $r = Invoke-SoftwareManagement -OSContext @{ IsWindows11 = $true }
                $r.ItemsSkipped | Should -Be 1
                $r.ItemsFailed | Should -Be 0
            }
        }
    }

    Context 'per-item timeout threading' {

        It 'passes the diff item TimeoutSeconds through to the upgrade command' {
            InModuleScope SoftwareManagement {
                $script:timeouts = [System.Collections.Generic.List[object]]::new()
                Mock Get-DiffList { , @(@{ Action = 'upgrade'; Name = 'Slow Suite'
                            Id = 'Slow.Suite'; Source = 'winget'; TimeoutSeconds = 1800 }) }
                Mock Get-OSContext { @{ IsWindows11 = $true } }
                Mock Test-CommandAvailable { $true }
                Mock Resolve-WingetPath { 'winget.exe' }
                Mock Invoke-ExternalPackageCommand {
                    if (($ArgumentList -join ' ') -like 'upgrade*') { $script:timeouts.Add($TimeoutSeconds) }
                    0
                }

                $null = Invoke-SoftwareManagement -OSContext @{ IsWindows11 = $true }
                $script:timeouts[0] | Should -Be 1800 `
                    -Because 'without this an upgrade silently used the 600s default and large suites were killed mid-write'
            }
        }
    }

    Context 'chocolatey items are not cross-attempted with winget' {

        It 'never runs a winget upgrade for a choco-sourced item' {
            # `choco upgrade` INSTALLS a package that is not present, so a cross-source
            # fallback would silently ADD software rather than upgrade it. The reverse
            # direction is guarded the same way, by source.
            InModuleScope SoftwareManagement {
                $script:wingetUpgrades = 0
                Mock Get-DiffList { , @(@{ Action = 'upgrade'; Name = 'notepadplusplus.install'
                            Id = 'notepadplusplus.install'; Source = 'choco' }) }
                Mock Get-OSContext { @{ IsWindows11 = $true } }
                Mock Test-CommandAvailable { $true }
                Mock Resolve-WingetPath { 'winget.exe' }
                Mock Invoke-ExternalPackageCommand {
                    if ($FilePath -like '*winget*' -and ($ArgumentList -join ' ') -like 'upgrade*') {
                        $script:wingetUpgrades++
                    }
                    0
                }

                $r = Invoke-SoftwareManagement -OSContext @{ IsWindows11 = $true }
                $script:wingetUpgrades | Should -Be 0
                $r.ItemsProcessed | Should -Be 1
            }
        }
    }
}
