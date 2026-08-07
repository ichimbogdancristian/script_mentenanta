#Requires -Version 7.0
<#
    Characterization tests for Remove-BloatwareLayered (modules/type2/SoftwareManagement.psm1).

    This is the most intricate logic in the project and it had zero coverage. It is also the
    only remaining Phase 2 extraction target, so these tests exist to make that extraction
    verifiable rather than hopeful.

    THE RULE THESE TESTS EXIST TO PROTECT:

        Only a layer that VERIFIABLY UNINSTALLS may suppress the later layers.

    It has regressed once already, and the failure was silent. Layer 1 (AppX removal) used to
    return nothing, so a failed removal looked like a success. Layer 2 (deprovision) shared the
    same $removed flag. An in-box app is normally installed AND provisioned, so the sequence
    was: Layer 1 silently fails -> Layer 2 deprovisions successfully -> flag goes true ->
    Layers 3/4/5 are ALL skipped -> the winget-by-exact-Id removal that actually works on these
    packages never runs -> the post-removal check correctly reports failure for a package the
    module never really tried to uninstall. Five Xbox apps were reported removed while
    `winget list` still showed every one of them.

    Deprovisioning stops an app returning for NEW profiles. It does not uninstall it for
    existing users. The two are not alternatives and neither gates the other.

    Every AppX/winget/registry call is mocked; nothing here touches the machine.
#>

BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:RepoRoot 'modules\core\Maintenance.psm1') -Force -Global -ErrorAction Stop
    Import-Module (Join-Path $script:RepoRoot 'modules\type2\SoftwareManagement.psm1') -Force -ErrorAction Stop
}

Describe 'Remove-BloatwareLayered' {

    Context 'Layer 1 verifiably uninstalls' {
        It 'reports Removed + Verified and does NOT fall through to winget' {
            InModuleScope SoftwareManagement {
                # Layer 1 calls this ONCE on a hit (the '*stem*' fallback is only used when the
                # exact-stem lookup misses). Call 2 onward is the post-removal re-query, which
                # must come back empty for the removal to verify.
                $script:appxCalls = 0
                Mock Get-AppxPackageCompat {
                    $script:appxCalls++
                    if ($script:appxCalls -eq 1) { [pscustomobject]@{ PackageFullName = 'Microsoft.Test_1.0_x64__abc' } }
                    else { $null }   # post-removal check: gone
                }
                Mock Remove-AppxPackageCompat { $true }
                Mock Get-AppxProvisionedPackageCompat { @() }
                Mock Invoke-ExternalPackageCommand { 0 }

                $r = Remove-BloatwareLayered -PackageName 'Microsoft.Test' -WingetId 'MSIX\Microsoft.Test' -HasWinget
                $r.Removed | Should -BeTrue
                $r.Verified | Should -BeTrue
                $r.Attempts | Should -Contain 'AppX'
                Should -Invoke Invoke-ExternalPackageCommand -Times 0 -Exactly `
                    -Because 'a verified Layer 1 removal must suppress the later layers'
            }
        }
    }

    Context 'THE REGRESSION: Layer 2 must never suppress Layers 3/4/5' {
        It 'still reaches the winget layer when Layer 1 FAILS but Layer 2 deprovisions' {
            # This is the exact shape of the shipped bug. If this test fails, the winget
            # removal that actually works on MSIX packages has become unreachable again.
            InModuleScope SoftwareManagement {
                Mock Get-AppxPackageCompat { [pscustomobject]@{ PackageFullName = 'Microsoft.Test_1.0_x64__abc' } }
                Mock Remove-AppxPackageCompat { $false }        # Layer 1 fails
                Mock Get-AppxProvisionedPackageCompat { @([pscustomobject]@{ PackageName = 'Microsoft.Test_1.0'; DisplayName = 'Microsoft.Test' }) }
                Mock Remove-AppxProvisionedPackageCompat { $true }   # Layer 2 succeeds
                Mock Invoke-ExternalPackageCommand { 1 }             # winget tried, fails
                Mock Resolve-WingetPath { 'winget.exe' }

                $r = Remove-BloatwareLayered -PackageName 'Microsoft.Test' -WingetId 'MSIX\Microsoft.Test' -HasWinget

                Should -Invoke Invoke-ExternalPackageCommand -Times 1 -Because 'Layer 4 must still be attempted'
                $r.Deprovisioned | Should -BeTrue
                $r.Removed | Should -BeFalse -Because 'deprovisioning is not removal'
            }
        }

        It 'records AppX(failed) rather than AppX when Layer 1 does not take effect' {
            InModuleScope SoftwareManagement {
                Mock Get-AppxPackageCompat { [pscustomobject]@{ PackageFullName = 'Microsoft.Test_1.0_x64__abc' } }
                Mock Remove-AppxPackageCompat { $false }
                Mock Get-AppxProvisionedPackageCompat { @() }
                Mock Invoke-ExternalPackageCommand { 1 }
                Mock Resolve-WingetPath { 'winget.exe' }

                $r = Remove-BloatwareLayered -PackageName 'Microsoft.Test' -HasWinget
                $r.Attempts | Should -Contain 'AppX(failed)'
                $r.Attempts | Should -Not -Contain 'AppX'
            }
        }

        It 'reports Deprovisioned without Removed when only Layer 2 succeeds' {
            InModuleScope SoftwareManagement {
                Mock Get-AppxPackageCompat { $null }             # nothing installed to remove
                Mock Get-AppxProvisionedPackageCompat { @([pscustomobject]@{ PackageName = 'Microsoft.Test_1.0' }) }
                Mock Remove-AppxProvisionedPackageCompat { $true }
                Mock Invoke-ExternalPackageCommand { 1 }
                Mock Resolve-WingetPath { 'winget.exe' }

                $r = Remove-BloatwareLayered -PackageName 'Microsoft.Test' -HasWinget
                $r.Deprovisioned | Should -BeTrue
                $r.Removed | Should -BeFalse
                $r.Verified | Should -BeFalse
            }
        }
    }

    Context 'post-removal validation is keyed on whether an AppX package was SEEN' {
        It 'flips Removed back to false when the package is still installed afterwards' {
            InModuleScope SoftwareManagement {
                # Layer 1 claims success, but the package is still there on re-query.
                Mock Get-AppxPackageCompat { [pscustomobject]@{ PackageFullName = 'Microsoft.Test_1.0_x64__abc' } }
                Mock Remove-AppxPackageCompat { $true }
                Mock Get-AppxProvisionedPackageCompat { @() }

                $r = Remove-BloatwareLayered -PackageName 'Microsoft.Test'
                $r.Removed | Should -BeFalse -Because 'live state overrides the layer''s own report'
                $r.Verified | Should -BeFalse
            }
        }

        It 'does not claim verification for a package that was never AppX-shaped' {
            # Get-AppxPackageCompat returns nothing for a Win32 program whether or not the
            # uninstall worked, so "not found" must never be treated as proof of removal.
            InModuleScope SoftwareManagement {
                Mock Get-AppxPackageCompat { $null }
                Mock Get-AppxProvisionedPackageCompat { @() }
                Mock Invoke-ExternalPackageCommand { 0 }          # winget reports success
                Mock Resolve-WingetPath { 'winget.exe' }

                $r = Remove-BloatwareLayered -PackageName 'SomeWin32App' -WingetId 'Vendor.App' -HasWinget
                $r.Removed | Should -BeTrue -Because 'the uninstaller reported success'
                $r.Verified | Should -BeFalse -Because 'no AppX package was ever seen, so nothing is verifiable'
            }
        }
    }

    Context 'winget layers' {
        It 'skips the winget layers entirely when winget is unavailable' {
            InModuleScope SoftwareManagement {
                Mock Get-AppxPackageCompat { $null }
                Mock Get-AppxProvisionedPackageCompat { @() }
                Mock Invoke-ExternalPackageCommand { 0 }
                Mock Resolve-WingetPath { 'winget.exe' }

                $r = Remove-BloatwareLayered -PackageName 'Whatever' -WingetId 'Vendor.App'
                Should -Invoke Invoke-ExternalPackageCommand -Times 0 -Exactly
                $r.Removed | Should -BeFalse
            }
        }

        It 'routes every winget call through the timeout-guarded helper' {
            # A bare winget invocation could hang the unattended run forever.
            InModuleScope SoftwareManagement {
                Mock Get-AppxPackageCompat { $null }
                Mock Get-AppxProvisionedPackageCompat { @() }
                Mock Invoke-ExternalPackageCommand { 0 }
                Mock Resolve-WingetPath { 'winget.exe' }

                $null = Remove-BloatwareLayered -PackageName 'Whatever' -WingetId 'Vendor.App' -HasWinget
                Should -Invoke Invoke-ExternalPackageCommand -Times 1
            }
        }
    }

    Context 'nothing found anywhere' {
        It 'reports not-removed with no attempts rather than throwing' {
            InModuleScope SoftwareManagement {
                Mock Get-AppxPackageCompat { $null }
                Mock Get-AppxProvisionedPackageCompat { @() }

                $r = $null
                { $script:r = Remove-BloatwareLayered -PackageName 'DoesNotExist' } | Should -Not -Throw
                $script:r.Removed | Should -BeFalse
                $script:r.Deprovisioned | Should -BeFalse
                @($script:r.Attempts).Count | Should -Be 0
            }
        }
    }

    Context 'result contract' {
        It 'always returns every field Invoke-SoftwareManagement reads' {
            InModuleScope SoftwareManagement {
                Mock Get-AppxPackageCompat { $null }
                Mock Get-AppxProvisionedPackageCompat { @() }
                $r = Remove-BloatwareLayered -PackageName 'X'
                foreach ($k in 'Removed', 'Deprovisioned', 'RebootRequired', 'Attempts', 'Verified') {
                    $r.ContainsKey($k) | Should -BeTrue -Because "the caller reads '$k'"
                }
            }
        }
    }
}
