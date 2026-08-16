#Requires -Version 7.0
<#
    Unit tests for Test-MicrosoftOfficeInstalled (modules/type1/SoftwareManagementAudit.psm1).

    This gates the LibreOffice entry in essential-apps.json. It was a name match:

        $installedNames -match 'microsoft.*(office|word|excel|outlook)'

    against Get-InstalledApp output, which includes AppX packages by short name. Every stock
    Windows 11 ships Store stubs whose names satisfy that regex - Microsoft.MicrosoftOfficeHub,
    Microsoft.OutlookForWindows, Microsoft.Office.OneNote/.Sway/.Lens/.Todo.List - so
    LibreOffice was skipped on every clean machine while the log claimed "MS Office detected".

    All six of those packages are listed as removable bloat in this project's own
    bloatware-detection.json, so one run would remove Microsoft.MicrosoftOfficeHub in Stage 3
    having already cited its presence in Stage 1 as proof Office was installed.

    The tests below pin the two properties that fix required: stubs must NOT count, and a real
    install must still be found by either signal. Fully mocked - the dev PC's own Office state
    is irrelevant and must stay irrelevant.
#>

BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:RepoRoot 'modules\core\Maintenance.psm1') -Force -Global -ErrorAction Stop
    Import-Module (Join-Path $script:RepoRoot 'modules\type1\SoftwareManagementAudit.psm1') -Force -ErrorAction Stop
}

Describe 'Test-MicrosoftOfficeInstalled' {

    Context 'nothing installed' {
        It 'reports not installed when no key resolves' {
            $r = InModuleScope SoftwareManagementAudit {
                Mock Write-Log { }
                Mock Get-PerUserRegistryRoot { @() }
                Mock Get-ItemProperty { throw [System.Management.Automation.ItemNotFoundException]::new('nope') }
                Test-MicrosoftOfficeInstalled
            }
            $r.Installed | Should -BeFalse
            $r.Evidence | Should -Not -BeNullOrEmpty -Because 'the log line must say why, not just report false'
        }
    }

    Context 'Click-to-Run (Microsoft 365 / Office 2016+)' {
        It 'detects a Click-to-Run install whose InstallationPath exists' {
            $r = InModuleScope SoftwareManagementAudit {
                Mock Write-Log { }
                Mock Get-PerUserRegistryRoot { @() }
                Mock Get-ItemProperty {
                    if ($Path -like '*ClickToRun\Configuration') {
                        [pscustomobject]@{ InstallationPath = 'C:\Program Files\Microsoft Office'; ProductReleaseIds = 'O365ProPlusRetail' }
                    }
                    else { throw 'not found' }
                }
                Mock Test-Path { $true }
                Test-MicrosoftOfficeInstalled
            }
            $r.Installed | Should -BeTrue
            $r.Evidence | Should -Match 'Click-to-Run'
            $r.Evidence | Should -Match 'O365ProPlusRetail' -Because 'the product id makes the log actionable'
        }

        It 'ignores a Click-to-Run key whose InstallationPath no longer exists' {
            # The key survives a failed or partial uninstall; the folder does not.
            $r = InModuleScope SoftwareManagementAudit {
                Mock Write-Log { }
                Mock Get-PerUserRegistryRoot { @() }
                Mock Get-ItemProperty {
                    if ($Path -like '*ClickToRun\Configuration') { [pscustomobject]@{ InstallationPath = 'C:\Gone' } }
                    else { throw 'not found' }
                }
                Mock Test-Path { $false }
                Test-MicrosoftOfficeInstalled
            }
            $r.Installed | Should -BeFalse
        }
    }

    Context 'App Paths' {
        It 'detects Word alone' {
            # Word OR Excel - a Word-only install is still Office.
            $r = InModuleScope SoftwareManagementAudit {
                Mock Write-Log { }
                Mock Get-PerUserRegistryRoot { @() }
                Mock Get-ItemProperty {
                    if ($Path -like '*App Paths\WINWORD.EXE') { [pscustomobject]@{ '(default)' = 'C:\PF\Office16\WINWORD.EXE' } }
                    else { throw 'not found' }
                }
                Mock Test-Path { $true }
                Test-MicrosoftOfficeInstalled
            }
            $r.Installed | Should -BeTrue
            $r.Evidence | Should -Match 'WINWORD\.EXE'
        }

        It 'detects Excel alone' {
            $r = InModuleScope SoftwareManagementAudit {
                Mock Write-Log { }
                Mock Get-PerUserRegistryRoot { @() }
                Mock Get-ItemProperty {
                    if ($Path -like '*App Paths\EXCEL.EXE') { [pscustomobject]@{ '(default)' = 'C:\PF\Office16\EXCEL.EXE' } }
                    else { throw 'not found' }
                }
                Mock Test-Path { $true }
                Test-MicrosoftOfficeInstalled
            }
            $r.Installed | Should -BeTrue
            $r.Evidence | Should -Match 'EXCEL\.EXE'
        }

        It 'ignores a stale App Paths key pointing at a missing exe' {
            $r = InModuleScope SoftwareManagementAudit {
                Mock Write-Log { }
                Mock Get-PerUserRegistryRoot { @() }
                Mock Get-ItemProperty {
                    if ($Path -like '*App Paths\WINWORD.EXE') { [pscustomobject]@{ '(default)' = 'C:\Gone\WINWORD.EXE' } }
                    else { throw 'not found' }
                }
                Mock Test-Path { $false }
                Test-MicrosoftOfficeInstalled
            }
            $r.Installed | Should -BeFalse
        }

        It 'consults per-user hives, because HKCU is the LocalSystem hive under the monthly task' {
            $r = InModuleScope SoftwareManagementAudit {
                Mock Write-Log { }
                Mock Get-PerUserRegistryRoot { @('Registry::HKEY_USERS\S-1-5-21-1-2-3-1001') }
                Mock Get-ItemProperty {
                    if ($Path -like 'Registry::HKEY_USERS\*App Paths\WINWORD.EXE') {
                        [pscustomobject]@{ '(default)' = 'C:\Users\bob\Office\WINWORD.EXE' }
                    }
                    else { throw 'not found' }
                }
                Mock Test-Path { $true }
                Test-MicrosoftOfficeInstalled
            }
            $r.Installed | Should -BeTrue -Because 'a per-user Office install must not be invisible to the SYSTEM task'
        }
    }

    Context 'THE REGRESSION: Windows 11 Store stubs must not count as Office' {

        # Exactly the names Get-InstalledApp returns for the preinstalled AppX packages, and
        # exactly the ones the old regex matched.
        $stubs = @(
            @{ Name = 'Microsoft.MicrosoftOfficeHub' }
            @{ Name = 'Microsoft.OutlookForWindows' }
            @{ Name = 'Microsoft.Office.OneNote' }
            @{ Name = 'Microsoft.Office.Sway' }
            @{ Name = 'Microsoft.Office.Lens' }
            @{ Name = 'Microsoft.Office.Todo.List' }
        )

        It 'the OLD name regex matched <Name> (documents the bug)' -ForEach $stubs {
            # Keeps the bug reproducible, so nobody reinstates the cheap check as a "fallback".
            $Name.ToLowerInvariant() | Should -Match 'microsoft.*(office|word|excel|outlook)'
        }

        It 'the NEW check is unaffected by <Name>, because it never reads package names' -ForEach $stubs {
            $r = InModuleScope SoftwareManagementAudit {
                Mock Write-Log { }
                Mock Get-PerUserRegistryRoot { @() }
                Mock Get-ItemProperty { throw 'not found' }
                Mock Get-InstalledApp { @(@{ Name = 'Microsoft.MicrosoftOfficeHub'; Source = 'AppX' }) }
                Test-MicrosoftOfficeInstalled
            }
            $r.Installed | Should -BeFalse
        }
    }
}

Describe 'LibreOffice / Office gating is self-consistent with the bloatware list' {

    BeforeAll {
        $script:Bloat = Get-Content (Join-Path $script:RepoRoot 'config\lists\bloatware\bloatware-detection.json') -Raw |
            ConvertFrom-Json -Depth 20 -AsHashtable
        $script:Audit = Get-Content (Join-Path $script:RepoRoot 'modules\type1\SoftwareManagementAudit.psm1') -Raw
    }

    It 'still classes the Office stubs as removable bloatware' {
        # If this ever stops being true, the contradiction documented in
        # Test-MicrosoftOfficeInstalled changes shape and its rationale needs revisiting.
        # categories.<name>.apps[] - each category is a { description, apps } object, not a
        # bare list, so .Values must be stepped through .apps to reach the entries.
        $names = @()
        foreach ($cat in $script:Bloat.categories.Values) {
            foreach ($e in @($cat.apps)) { if ($e -is [System.Collections.IDictionary] -and $e.name) { $names += $e.name } }
        }
        $names.Count | Should -BeGreaterThan 100 -Because 'the traversal must actually reach the entries, not vacuously pass'
        $names | Should -Contain 'Microsoft.MicrosoftOfficeHub'
        $names | Should -Contain 'Microsoft.OutlookForWindows'
    }

    It 'no longer decides Office presence from installed package names' {
        # Comment-immune on purpose: Test-MicrosoftOfficeInstalled's own documentation quotes
        # the old regex verbatim to explain the bug, so a raw file-content match would always
        # fail. Assert on the executable shape instead - the old $hasMsOffice variable and the
        # $installedNames pipe that fed it.
        $code = ($script:Audit -split "`n" | Where-Object { $_ -notmatch '^\s*#' }) -join "`n"
        $code | Should -Not -Match '\$hasMsOffice' -Because 'the name-based Office flag is gone'
        $code | Should -Not -Match '\$installedNames\s*\|\s*Where-Object[^\n]*outlook' `
            -Because 'Office presence must not be derived from the installed-package name list'
    }

    It 'routes the LibreOffice gate through Test-MicrosoftOfficeInstalled' {
        $script:Audit | Should -Match '\$officeCheck\s*=\s*Test-MicrosoftOfficeInstalled'
        $script:Audit | Should -Match '\$officeCheck\.Installed'
    }

    It 'still reuses the installed-name list for the ordinary already-installed check' {
        # $installedNames has a second, legitimate consumer ($foundByName). The fix must not
        # have removed it along with the Office misuse.
        $script:Audit | Should -Match '\$foundByName\s*=\s*\$installedNames'
    }
}
