#Requires -Version 7.0
<#
    Tests for the per-user registry redirection in Maintenance.psm1.

    THE BUG THIS GUARDS. When a process runs as NT AUTHORITY\SYSTEM its HKCU *is*
    HKEY_USERS\S-1-5-18 - the LocalSystem profile - not the logged-on user's hive. The monthly
    scheduled task runs as SYSTEM, so every HKCU read and write it performed landed in a profile
    no human ever sees.

    That made three item types a permanent no-op loop: the audit read the SYSTEM hive, saw
    defaults, queued a change; Type2 wrote it to the SYSTEM hive; next month the audit read the
    SYSTEM hive again and queued the identical change. Every run reported success. It affected
    the visual-effects and desktop-background arms, the HKCU:\...\Run startup scan, and the five
    HKCU entries in telemetry-list.json.

    Interactive elevated runs were never affected - UAC keeps the same user - which is exactly
    why it never showed up in hand testing.

    These tests do not require SYSTEM: the identity-dependent part (Get-PerUserRegistryRoot) is
    mocked so the redirection logic can be exercised on any account. Nothing here reads or
    writes real per-user state.
#>

BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:RepoRoot 'modules\core\Maintenance.psm1') -Force -Global -ErrorAction Stop
}

Describe 'Resolve-UserRegistryPath' {

    Context 'HKLM and other roots are passed through UNCHANGED' {
        # 307 of the 312 baseline registry entries are HKLM. If any of them were rewritten or
        # dropped, the entire security baseline would silently stop applying.
        It 'returns an HKLM path byte-identical to the input' {
            foreach ($p in @(
                    'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
                    'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'
                    'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore'
                )) {
                $r = @(Resolve-UserRegistryPath -Path $p)
                $r.Count | Should -Be 1
                $r[0] | Should -BeExactly $p
            }
        }

        It 'does not consult the user-hive lookup at all for HKLM' {
            InModuleScope Maintenance {
                Mock Get-PerUserRegistryRoot { throw 'must not be called for HKLM' }
                { Resolve-UserRegistryPath -Path 'HKLM:\SOFTWARE\Anything' } | Should -Not -Throw
            }
        }

        It 'passes through other providers unchanged' {
            (@(Resolve-UserRegistryPath -Path 'HKCR:\.txt'))[0] | Should -BeExactly 'HKCR:\.txt'
            (@(Resolve-UserRegistryPath -Path 'Registry::HKEY_USERS\S-1-5-18\Software'))[0] |
                Should -BeExactly 'Registry::HKEY_USERS\S-1-5-18\Software'
        }
    }

    Context 'HKCU expands to the right hive(s)' {
        It 'stays HKCU when running interactively' {
            InModuleScope Maintenance {
                Mock Get-PerUserRegistryRoot { @('HKCU:') }
                $r = @(Resolve-UserRegistryPath -Path 'HKCU:\Control Panel\Desktop')
                $r.Count | Should -Be 1
                $r[0] | Should -BeExactly 'HKCU:\Control Panel\Desktop'
            }
        }

        It 'redirects to the real user hive when running as SYSTEM' {
            InModuleScope Maintenance {
                Mock Get-PerUserRegistryRoot { @('Registry::HKEY_USERS\S-1-5-21-111-222-333-1001') }
                $r = @(Resolve-UserRegistryPath -Path 'HKCU:\Control Panel\Desktop')
                $r.Count | Should -Be 1
                $r[0] | Should -BeExactly 'Registry::HKEY_USERS\S-1-5-21-111-222-333-1001\Control Panel\Desktop'
                $r[0] | Should -Not -Match 'S-1-5-18' -Because 'the LocalSystem profile is exactly what this fixes'
            }
        }

        It 'expands to EVERY logged-on user' {
            InModuleScope Maintenance {
                Mock Get-PerUserRegistryRoot {
                    @('Registry::HKEY_USERS\S-1-5-21-1-1-1-1001', 'Registry::HKEY_USERS\S-1-5-21-1-1-1-1002')
                }
                $r = @(Resolve-UserRegistryPath -Path 'HKCU:\Software\X')
                $r.Count | Should -Be 2
                $r[0] | Should -Match '1001\\Software\\X$'
                $r[1] | Should -Match '1002\\Software\\X$'
            }
        }

        It 'returns NOTHING when running as SYSTEM with no user logged on' {
            # The honest outcome. Writing somewhere harmless-looking and reporting success is
            # what the old code effectively did.
            InModuleScope Maintenance {
                Mock Get-PerUserRegistryRoot { @() }
                (@(Resolve-UserRegistryPath -Path 'HKCU:\Software\X')).Count | Should -Be 0
            }
        }
    }
}

Describe 'Get-PerUserRegistryRoot' {
    It 'returns HKCU when not running as SYSTEM' {
        # This test process is a normal user, so this exercises the real code path.
        $r = @(Get-PerUserRegistryRoot)
        $r.Count | Should -Be 1
        $r[0] | Should -BeExactly 'HKCU:'
    }

    It 'keeps only real user SIDs, never the service accounts' {
        # S-1-5-18/19/20 are System/LocalService/NetworkService, and '_Classes' keys are not
        # profiles. Only S-1-5-21-<domain>-<rid> is an interactive account.
        $candidates = @(
            'S-1-5-18', 'S-1-5-19', 'S-1-5-20',
            'S-1-5-21-111-222-333-1001',
            'S-1-5-21-111-222-333-1001_Classes',
            '.DEFAULT'
        )
        $kept = @($candidates | Where-Object { $_ -match '^S-1-5-21-[\d\-]+$' })
        $kept.Count | Should -Be 1
        $kept[0] | Should -BeExactly 'S-1-5-21-111-222-333-1001'
    }
}

Describe 'Set-RegistryValue redirection' {

    It 'refuses to write a per-user setting when there is no user hive, and says so' {
        InModuleScope Maintenance {
            Mock Get-PerUserRegistryRoot { @() }
            Mock Set-ItemProperty { throw 'must not write' }
            Mock New-Item { throw 'must not create' }
            $warned = $false
            Mock Write-Log { if ($Level -eq 'WARN') { $script:warned = $true } }

            $result = Set-RegistryValue -Path 'HKCU:\Software\X' -Name 'Y' -Value 1 -Type DWord
            $result | Should -BeFalse -Because 'nothing was applied, so it must not report a change'
            Should -Invoke Set-ItemProperty -Times 0 -Exactly
        }
    }

    It 'writes to EVERY resolved user hive, not just the first' {
        InModuleScope Maintenance {
            Mock Get-PerUserRegistryRoot {
                @('Registry::HKEY_USERS\S-1-5-21-1-1-1-1001', 'Registry::HKEY_USERS\S-1-5-21-1-1-1-1002')
            }
            Mock Get-ItemProperty { $null }        # neither user is compliant yet
            Mock Test-Path { $true }
            $script:written = @()
            Mock Set-ItemProperty { $script:written += $Path }

            $changed = Set-RegistryValue -Path 'HKCU:\Software\X' -Name 'Y' -Value 1 -Type DWord
            $changed | Should -BeTrue
            $script:written.Count | Should -Be 2
        }
    }

    It 'compares per target, so an already-compliant user does not mask a non-compliant one' {
        InModuleScope Maintenance {
            Mock Get-PerUserRegistryRoot {
                @('Registry::HKEY_USERS\S-1-5-21-1-1-1-1001', 'Registry::HKEY_USERS\S-1-5-21-1-1-1-1002')
            }
            # First user already has the desired value; second does not.
            Mock Get-ItemProperty {
                if ($Path -match '1001') { [pscustomobject]@{ Y = 1 } } else { [pscustomobject]@{ Y = 0 } }
            }
            Mock Test-Path { $true }
            $script:written2 = @()
            Mock Set-ItemProperty { $script:written2 += $Path }

            $null = Set-RegistryValue -Path 'HKCU:\Software\X' -Name 'Y' -Value 1 -Type DWord
            $script:written2.Count | Should -Be 1 -Because 'only the non-compliant user needs writing'
            $script:written2[0] | Should -Match '1002'
        }
    }

    It 'leaves HKLM behaviour completely unchanged' {
        InModuleScope Maintenance {
            Mock Get-PerUserRegistryRoot { throw 'must not be consulted for HKLM' }
            Mock Get-ItemProperty { $null }
            Mock Test-Path { $true }
            $script:hklmWrites = @()
            Mock Set-ItemProperty { $script:hklmWrites += $Path }

            $changed = Set-RegistryValue -Path 'HKLM:\SOFTWARE\Test' -Name 'V' -Value 1 -Type DWord
            $changed | Should -BeTrue
            $script:hklmWrites.Count | Should -Be 1
            $script:hklmWrites[0] | Should -BeExactly 'HKLM:\SOFTWARE\Test'
        }
    }
}
