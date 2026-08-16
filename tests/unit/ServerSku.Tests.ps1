#Requires -Version 7.0
<#
    Unit tests for Windows Server SKU handling.

    These are REGRESSION GUARDS for three failure modes that are invisible on a client and
    that no other test in this suite can catch, because every one of them depends on the SKU
    rather than on any code path a workstation ever takes:

      1. Windows Server 2025 is build 26100, which is >= the 22000 threshold this project uses
         to mean "Windows 11". Its EditionID (ServerStandard / ServerDatacenter) matches
         neither the LTSC skip nor the enterprise-tier test in Get-WindowsLifecycleStatus, so
         it classes as a CONSUMER Windows 11 24H2 machine - whose catalog endOfService is
         2026-10-13. From 2026-10-14 that made NeedsFeatureAdvance true on a SERVER and, with
         autoAdvanceEolFeatureVersion defaulting to true, wrote a TargetReleaseVersion feature
         -update policy pinning a server to a client feature version that does not exist for
         it. Server 2019/2022 escaped only because their DisplayVersion has no catalog row -
         luck, not a guard.

      2. System Restore is client-only (the root/default:SystemRestore WMI class does not
         exist on Server), yet SystemConfigurationAudit queues a restore point unconditionally
         - so the run applied a 300-entry CIS baseline plus secedit/auditpol changes with no
         rollback target while reporting a restore-point failure every month.

      3. Domain controllers must be refused outright: the secedit password/lockout pass is
         overridden there by the Default Domain Policy (silently ineffective), while the
         auditpol changes land on the machine whose Security log IS the domain audit record.

    All of it is mocked and system-independent, exactly like the rest of the suite - these
    must pass on the dev PC, which is a client.
#>

BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:RepoRoot 'modules\core\Maintenance.psm1') -Force -Global -ErrorAction Stop
    Import-Module (Join-Path $script:RepoRoot 'modules\type1\WindowsUpdatesAudit.psm1') -Force -ErrorAction Stop
}

Describe 'Get-OSContext SKU detection' {

    # ProductType comes off the SAME Win32_OperatingSystem object the build number does, so
    # these fields cost no extra query - mocking that one call covers all of them.
    BeforeAll {
        function New-OSContextFor {
            param([int]$ProductType, [int]$Build = 26100, [string]$InstallationType = 'Server', [string]$Caption = 'Microsoft Windows Server 2025 Standard')
            InModuleScope Maintenance -Parameters @{ pt = $ProductType; b = $Build; it = $InstallationType; cap = $Caption } {
                Mock Get-CimInstance { [pscustomobject]@{ BuildNumber = $b; Caption = $cap; ProductType = $pt } }
                Mock Get-ItemProperty { [pscustomobject]@{ InstallationType = $it } }
                Mock Write-Log { }
                Get-OSContext
            }
        }
    }

    Context 'ProductType mapping' {
        It 'treats ProductType 1 as a client' {
            $ctx = New-OSContextFor -ProductType 1 -Build 26100 -InstallationType 'Client' -Caption 'Microsoft Windows 11 Pro'
            $ctx.IsServer | Should -BeFalse
            $ctx.IsDomainController | Should -BeFalse
        }

        It 'treats ProductType 2 as BOTH a server and a domain controller' {
            # A DC is also a server: any server-guarded skip must apply to it too.
            $ctx = New-OSContextFor -ProductType 2
            $ctx.IsServer | Should -BeTrue
            $ctx.IsDomainController | Should -BeTrue
        }

        It 'treats ProductType 3 as a member server, not a domain controller' {
            $ctx = New-OSContextFor -ProductType 3
            $ctx.IsServer | Should -BeTrue
            $ctx.IsDomainController | Should -BeFalse
        }
    }

    Context 'build number cannot substitute for SKU' {
        It 'still reports IsWindows11 for Server 2025 (build 26100) but ALSO reports IsServer' {
            # IsWindows11 deliberately keeps its literal build-threshold meaning; callers that
            # mean "is a client" must test IsServer. This test pins that contract - if someone
            # redefines IsWindows11 to exclude servers, the lifecycle guard's shape changes.
            $ctx = New-OSContextFor -ProductType 3 -Build 26100
            $ctx.IsWindows11 | Should -BeTrue -Because 'build 26100 is over the 22000 threshold'
            $ctx.IsServer | Should -BeTrue -Because 'the build number cannot tell client from server'
        }
    }

    Context 'Server Core' {
        It 'flags Server Core and reports winget as unavailable there' {
            $ctx = New-OSContextFor -ProductType 3 -InstallationType 'Server Core'
            $ctx.IsServerCore | Should -BeTrue
            $ctx.Features.WinGet | Should -BeFalse -Because 'Server Core has no MSIX/AppX runtime for App Installer'
        }

        It 'does not flag Server Core for Desktop Experience' {
            (New-OSContextFor -ProductType 3 -InstallationType 'Server').IsServerCore | Should -BeFalse
        }
    }

    Context 'unreadable values degrade toward client' {
        It 'defaults to client when ProductType is absent' {
            # The conservative direction: every server branch is a SKIP of work that is merely
            # useless on a server, so guessing "client" only ever costs a futile attempt.
            $ctx = InModuleScope Maintenance {
                Mock Get-CimInstance { [pscustomobject]@{ BuildNumber = 19045; Caption = 'Windows 10 Pro'; ProductType = $null } }
                Mock Get-ItemProperty { throw 'no such value' }
                Mock Write-Log { }
                Get-OSContext
            }
            $ctx.IsServer | Should -BeFalse
            $ctx.ProductType | Should -Be 1
        }

        It 'exposes the SKU keys even on the detection-failure fallback path' {
            # Consumers index these by name; a fallback missing them would hand back $null,
            # which is falsy and therefore silently "client" - correct, but only by accident.
            $ctx = InModuleScope Maintenance {
                Mock Get-CimInstance { throw 'CIM broken' }
                Mock Write-Log { }
                Get-OSContext
            }
            foreach ($k in 'ProductType', 'IsServer', 'IsDomainController', 'InstallationType', 'IsServerCore') {
                $ctx.ContainsKey($k) | Should -BeTrue -Because "the fallback must declare '$k' explicitly, not rely on `$null being falsy"
            }
            $ctx.IsServer | Should -BeFalse
        }
    }
}

Describe 'Get-WindowsLifecycleStatus excludes Windows Server' {

    BeforeAll {
        # The exact shape Windows Server 2025 presents: over the Win11 build threshold, and a
        # DisplayVersion that DOES have a consumer row in os-lifecycle.json.
        $script:Server2025 = @{
            IsWindows11 = $true; BuildNumber = 26100; MajorVersion = 11
            Caption = 'Microsoft Windows Server 2025 Standard'
            ProductType = 3; IsServer = $true; IsDomainController = $false
            InstallationType = 'Server'; IsServerCore = $false
        }
    }

    It 'returns Applicable = false for a server' {
        $r = InModuleScope WindowsUpdatesAudit -Parameters @{ ctx = $script:Server2025 } {
            Mock Write-Log { }
            Get-WindowsLifecycleStatus -OSContext $ctx
        }
        $r.Applicable | Should -BeFalse
    }

    It 'never sets NeedsFeatureAdvance for a server' {
        # THE regression guard: this is the flag that writes TargetReleaseVersion policy.
        $r = InModuleScope WindowsUpdatesAudit -Parameters @{ ctx = $script:Server2025 } {
            Mock Write-Log { }
            Get-WindowsLifecycleStatus -OSContext $ctx
        }
        $r.NeedsFeatureAdvance | Should -BeFalse
        $r.LatestSupportedVersion | Should -BeNullOrEmpty
    }

    It 'short-circuits before reading DisplayVersion/EditionID from the registry' {
        # Proves the guard is FIRST. If it ever moves below the registry read, a server could
        # reach the catalog again the moment the edition-tier regex changes.
        $reads = InModuleScope WindowsUpdatesAudit -Parameters @{ ctx = $script:Server2025 } {
            $script:Hits = 0
            Mock Write-Log { }
            Mock Get-ItemProperty { $script:Hits++; [pscustomobject]@{ DisplayVersion = '24H2'; EditionID = 'ServerStandard' } }
            $null = Get-WindowsLifecycleStatus -OSContext $ctx
            $script:Hits
        }
        $reads | Should -Be 0 -Because 'the server guard must run before any registry read'
    }

    It 'explains itself rather than returning a silent blank' {
        $r = InModuleScope WindowsUpdatesAudit -Parameters @{ ctx = $script:Server2025 } {
            Mock Write-Log { }
            Get-WindowsLifecycleStatus -OSContext $ctx
        }
        $r.Guidance | Should -Match 'Server'
    }

    It 'still evaluates a genuine client' {
        # Guard against the guard: an over-broad skip would silently disable lifecycle
        # detection for the clients this feature exists to serve. The real os-lifecycle.json
        # is fed in via the mock (Get-BaselineList resolves paths from the runtime project
        # root, which does not exist under Pester) so this also pins the catalog's own shape.
        $client = @{
            IsWindows11 = $true; BuildNumber = 22631; MajorVersion = 11; Caption = 'Microsoft Windows 11 Pro'
            ProductType = 1; IsServer = $false; IsDomainController = $false
            InstallationType = 'Client'; IsServerCore = $false
        }
        $catalog = Get-Content (Join-Path $script:RepoRoot 'config\lists\windows-updates\os-lifecycle.json') -Raw |
            ConvertFrom-Json -Depth 20 -AsHashtable
        $r = InModuleScope WindowsUpdatesAudit -Parameters @{ ctx = $client; cat = $catalog } {
            Mock Write-Log { }
            Mock Get-ItemProperty { [pscustomobject]@{ DisplayVersion = '23H2'; EditionID = 'Professional' } }
            Mock Get-BaselineList { $cat }
            Get-WindowsLifecycleStatus -OSContext $ctx
        }
        $r.Applicable | Should -BeTrue -Because 'a Windows 11 client with a catalogued version must still be evaluated'
        $r.EditionTier | Should -Be 'consumer'
    }

    It 'would have mis-resolved Server 2025 as a consumer client without the guard' {
        # Documents the exact bug, so the guard can never be removed as "redundant". Feeding
        # the server's real registry values through a CLIENT context reproduces the original
        # three-step mis-resolution: Win11 branch -> consumer tier -> 24H2 catalog row.
        $asClient = @{
            IsWindows11 = $true; BuildNumber = 26100; MajorVersion = 11
            Caption = 'Microsoft Windows Server 2025 Standard'
            ProductType = 1; IsServer = $false; IsDomainController = $false
            InstallationType = 'Client'; IsServerCore = $false
        }
        $catalog = Get-Content (Join-Path $script:RepoRoot 'config\lists\windows-updates\os-lifecycle.json') -Raw |
            ConvertFrom-Json -Depth 20 -AsHashtable
        $r = InModuleScope WindowsUpdatesAudit -Parameters @{ ctx = $asClient; cat = $catalog } {
            Mock Write-Log { }
            Mock Get-ItemProperty { [pscustomobject]@{ DisplayVersion = '24H2'; EditionID = 'ServerStandard' } }
            Mock Get-BaselineList { $cat }
            Get-WindowsLifecycleStatus -OSContext $ctx
        }
        $r.Applicable | Should -BeTrue -Because 'this is the mis-resolution the IsServer guard prevents'
        $r.EditionTier | Should -Be 'consumer' -Because 'ServerStandard matches neither the LTSC skip nor the enterprise-tier regex'
    }
}

Describe 'Windows Server config gate' {

    BeforeAll {
        $script:MainConfig = Get-Content (Join-Path $script:RepoRoot 'config\settings\main-config.json') -Raw |
            ConvertFrom-Json -Depth 20 -AsHashtable
        $script:Orchestrator = Get-Content (Join-Path $script:RepoRoot 'MaintenanceOrchestrator.ps1') -Raw
    }

    It 'declares the server block with both flags as booleans' {
        $script:MainConfig.server | Should -Not -BeNullOrEmpty
        $script:MainConfig.server.allowServerSku | Should -BeOfType [bool]
        $script:MainConfig.server.allowDomainController | Should -BeOfType [bool]
    }

    It 'refuses domain controllers by default' {
        $script:MainConfig.server.allowDomainController | Should -BeFalse `
            -Because 'the CIS Workstation benchmark is actively wrong on a DC - opt-in only'
    }

    It 'allows member servers by default' {
        $script:MainConfig.server.allowServerSku | Should -BeTrue `
            -Because 'a member server still benefits from updates, cleanup and the registry baseline'
    }

    It 'checks the SKU gate before Stage 0 runs' {
        # Ordering is the whole point: a gate that fires after the first module has already
        # written to the system is not a gate.
        $gateAt = $script:Orchestrator.IndexOf('IsDomainController')
        $stage0At = $script:Orchestrator.IndexOf('STAGE 0')
        $gateAt | Should -BeGreaterThan 0
        $stage0At | Should -BeGreaterThan 0
        $gateAt | Should -BeLessThan $stage0At -Because 'the DC refusal must precede any module execution'
    }
}

Describe 'telemetry baseline is safe on a server' {

    BeforeAll {
        $script:Telemetry = Get-Content (Join-Path $script:RepoRoot 'config\lists\telemetry\telemetry-list.json') -Raw |
            ConvertFrom-Json -Depth 20 -AsHashtable
    }

    It 'does not disable NetTcpPortSharing' {
        # WCF net.tcp hosting. Inert on a client, an outage on an app server - and the Stage 5
        # reboot is what would make it visible, long after the cause scrolled past.
        $script:Telemetry.services.disable | Should -Not -Contain 'NetTcpPortSharing'
    }

    It 'records why it was excluded' {
        # Same contract as security-baseline.json's _excluded entries: an exclusion with no
        # rationale gets "tidied" back in by the next person who reads the list.
        $script:Telemetry.services._excludedFromDisable.NetTcpPortSharing | Should -Not -BeNullOrEmpty
    }
}
