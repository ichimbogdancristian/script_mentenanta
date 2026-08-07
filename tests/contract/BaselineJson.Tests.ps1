#Requires -Version 7.0
<#
    Contract tests for the shipped baseline JSON under config/.

    Every one of these encodes a bug that actually shipped:

      * "Many UWP apps" as a dependency-matrix dependent - prose, -like-matched against real
        package names, so it silently matched nothing.
      * Microsoft.XboxGameCallableUI (a PROTECTED package) listed as a dependent of
        Microsoft.Xbox* - a protected package can never be queued for removal, so the cascade
        rule became unsatisfiable and permanently blocked EVERY Xbox detection.
      * A blanket "Adobe*" in app-upgrade ExcludePatterns while essential-apps.json installs
        Adobe Acrobat Reader - pinning a heavily-targeted PDF reader at its install version
        forever, the exact opposite of the project's CVE-reduction goal.

    Baselines are data, and data drifts. Nothing else in the pipeline validates it.
#>

BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:ConfigRoot = Join-Path $script:RepoRoot 'config'

    function Read-Json { param([string]$Rel) Get-Content (Join-Path $script:ConfigRoot $Rel) -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 20 -AsHashtable }

    $script:DepMatrix = Read-Json 'lists\bloatware\dependency-matrix.json'
    $script:Protected = Read-Json 'lists\bloatware\protected-packages.json'
    $script:Detection = Read-Json 'lists\bloatware\bloatware-detection.json'
    $script:Essential = Read-Json 'lists\essential-apps\essential-apps.json'
    $script:AppUpgrade = Read-Json 'lists\app-upgrade\app-upgrade-config.json'
    $script:Security = Read-Json 'lists\security\security-baseline.json'

    # Flatten protected-packages.json: category -> package key -> { protected, reason, severity }
    #
    # ONLY protected:true counts. Test-PackageProtected filters on `.protected -eq $true`
    # (SoftwareManagementAudit.psm1), and the file carries an 'optional_but_safe' section
    # that is explicitly DOCUMENTATION ONLY - entries there sit at protected:false and have
    # no effect on behaviour. Treating those as protected would produce false alarms.
    function Get-ProtectedEntries {
        param([hashtable]$Doc, [bool]$OnlyTrue = $true)
        foreach ($cat in $Doc.Keys) {
            if ($cat -like '_*') { continue }
            $group = $Doc[$cat]
            if ($group -isnot [hashtable]) { continue }
            foreach ($pkg in $group.Keys) {
                if ($pkg -like '_*') { continue }
                if ($OnlyTrue -and $group[$pkg].protected -ne $true) { continue }
                [pscustomobject]@{ Category = $cat; Package = $pkg; Protected = [bool]$group[$pkg].protected; Reason = $group[$pkg].reason }
            }
        }
    }

    $script:ProtectedAll = @(Get-ProtectedEntries -Doc $script:Protected -OnlyTrue $false)
    $script:ProtectedKeys = @((Get-ProtectedEntries -Doc $script:Protected -OnlyTrue $true).Package)
}

Describe 'All shipped JSON parses' {
    It 'parses every file under config/' {
        $files = Get-ChildItem $script:ConfigRoot -Recurse -Filter *.json
        $files.Count | Should -BeGreaterThan 0
        foreach ($f in $files) {
            { Get-Content $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 30 } |
                Should -Not -Throw -Because "$($f.Name) must be valid JSON"
        }
    }
}

Describe 'main-config.json has no DEAD keys' {
    # A config key that nothing reads is worse than no key: it advertises behaviour the code
    # does not implement, and an operator who sets it gets silence instead of an effect. Three
    # were found this way - reporting.enableHtmlReport (never checked; the report was always
    # generated), tools.verifySignature and tools.sysinternals.handle (declared for code that
    # did not exist).
    #
    # Leaf-name matching, so it is a smoke test rather than a proof: a key whose leaf name
    # coincides with an unrelated identifier will pass. It still catches the case that actually
    # occurs - a key added to config and never wired up at all.

    BeforeAll {
        # main-config.json is loaded here rather than reused from ModulePairs.Tests.ps1 -
        # $script: scope does not cross test files, and assuming it did made the first version
        # of these tests silently examine $null and pass vacuously.
        $script:MainConfig = Get-Content (Join-Path $script:RepoRoot 'config\settings\main-config.json') -Raw |
            ConvertFrom-Json -Depth 20 -AsHashtable

        $script:ShippedCode = (Get-ChildItem (Join-Path $script:RepoRoot 'modules') -Recurse -Include *.psm1 |
                Get-Content -Raw) -join "`n"
        $script:ShippedCode += "`n" + (Get-Content (Join-Path $script:RepoRoot 'MaintenanceOrchestrator.ps1') -Raw)

        function Get-ConfigLeafKey {
            param([hashtable]$Node, [string]$Prefix = '')
            foreach ($k in $Node.Keys) {
                if ($k -like '_*') { continue }          # _comment / _note documentation keys
                if ($Node[$k] -is [hashtable]) { Get-ConfigLeafKey -Node $Node[$k] -Prefix "$Prefix$k." }
                else { "$Prefix$k" }
            }
        }
        $script:ConfigLeaves = @(Get-ConfigLeafKey -Node $script:MainConfig)
    }

    It 'declares at least one key (sanity)' {
        $script:ConfigLeaves.Count | Should -BeGreaterThan 0
    }

    It 'has every declared key referenced somewhere in the shipped code' {
        $dead = foreach ($path in $script:ConfigLeaves) {
            $leaf = ($path -split '\.')[-1]
            if ($script:ShippedCode -notmatch "(?<![A-Za-z0-9_])$([regex]::Escape($leaf))(?![A-Za-z0-9_])") { $path }
        }
        @($dead) -join ', ' | Should -BeNullOrEmpty -Because 'a config key nothing reads silently does nothing'
    }

    It 'honours reporting.enableHtmlReport at the report choke point' {
        # Regression guard for the specific key that was dead: it must be consulted, and the
        # report is the only artifact surviving Stage 5, so absence must default to ON.
        $orch = Get-Content (Join-Path $script:RepoRoot 'MaintenanceOrchestrator.ps1') -Raw
        $orch | Should -Match 'enableHtmlReport' -Because 'Stage 4 must actually check the flag'
        $orch | Should -Match 'enableHtmlReport -eq \$false' -Because 'a missing key must default to generating the report'
    }
}

Describe 'dependency-matrix.json' {

    It 'exposes a .dependencies map' {
        $script:DepMatrix.dependencies | Should -Not -BeNullOrEmpty
    }

    It 'lists only package-shaped dependents, never prose' {
        # Values are -like-matched against live package names. A phrase with spaces can
        # never match anything, so the rule it belongs to is dead config.
        foreach ($pkg in $script:DepMatrix.dependencies.Keys) {
            foreach ($dep in @($script:DepMatrix.dependencies[$pkg].dependents)) {
                if (-not $dep) { continue }
                $dep | Should -Match '^[A-Za-z0-9._\-*]+$' `
                    -Because "'$dep' (dependent of '$pkg') must be a package identifier, not prose"
                $dep | Should -Not -Match '\s' -Because "'$dep' contains whitespace and can never -like match"
            }
        }
    }

    It 'never lists a PROTECTED package as a dependent' {
        # A protected package can never be queued for removal, so the cascade condition
        # "installed but not queued" is permanently true - an unconditional block on the
        # parent. This is the Xbox bug.
        foreach ($pkg in $script:DepMatrix.dependencies.Keys) {
            foreach ($dep in @($script:DepMatrix.dependencies[$pkg].dependents)) {
                if (-not $dep) { continue }
                $script:ProtectedKeys | Should -Not -Contain $dep `
                    -Because "'$dep' is protected; listing it as a dependent of '$pkg' makes the cascade rule unsatisfiable"
            }
        }
    }

    It 'gives every entry a reason' {
        foreach ($pkg in $script:DepMatrix.dependencies.Keys) {
            $script:DepMatrix.dependencies[$pkg].reason | Should -Not -BeNullOrEmpty `
                -Because "'$pkg' needs a documented reason"
        }
    }
}

Describe 'protected-packages.json' {

    It 'never declares the same package both protected:true and protected:false' {
        # The Microsoft.Paint contradiction: it sat in 'essential_system' at protected:true
        # AND in 'optional_but_safe' at protected:false. Test-PackageProtected returns on the
        # first protected:true match, so which one "wins" depends on hashtable enumeration
        # order - a coin flip. The file must never contain that ambiguity again.
        $dupes = $script:ProtectedAll | Group-Object Package | Where-Object { $_.Count -gt 1 }
        foreach ($d in $dupes) {
            $states = @($d.Group.Protected | Select-Object -Unique)
            $states.Count | Should -Be 1 `
                -Because "'$($d.Name)' is declared in $($d.Group.Category -join ' and ') with conflicting protected values"
        }
    }

    It 'gives every entry a reason' {
        foreach ($e in $script:ProtectedAll) {
            $e.Reason | Should -Not -BeNullOrEmpty -Because "'$($e.Package)' needs a documented reason"
        }
    }

    It 'protects Microsoft.XboxGameCallableUI (reachable from the broad Microsoft.Xbox* pattern)' {
        $script:ProtectedKeys | Should -Contain 'Microsoft.XboxGameCallableUI'
    }
}

Describe 'bloatware-detection.json' {

    BeforeAll {
        $script:AllApps = @(
            foreach ($cat in $script:Detection.categories.Keys) {
                foreach ($app in @($script:Detection.categories[$cat].apps)) { $app }
            }
        )
    }

    It 'declares at least one app' {
        $script:AllApps.Count | Should -BeGreaterThan 0
    }

    It 'gives every entry a name' {
        foreach ($a in $script:AllApps) { $a.name | Should -Not -BeNullOrEmpty }
    }

    It 'uses only declared detection sources' {
        $valid = @($script:Detection.metadata.detection_sources)
        $valid.Count | Should -BeGreaterThan 0
        foreach ($a in $script:AllApps) {
            foreach ($s in @($a.detection)) {
                if (-not $s) { continue }
                $valid | Should -Contain $s -Because "'$($a.name)' declares unknown detection source '$s'"
            }
        }
    }

    It 'uses only the recognised tier value' {
        # Only 'broad' is meaningful - it is what aggressiveOemRemoval gates on. A typo here
        # silently promotes a whole-vendor wildcard into the default detection set.
        foreach ($a in $script:AllApps) {
            if ($a.ContainsKey('tier')) {
                $a.tier | Should -Be 'broad' -Because "'$($a.name)' has an unrecognised tier '$($a.tier)'"
            }
        }
    }

    It 'keeps every tier:broad entry gated behind aggressiveOemRemoval' {
        # 'broad' is the only tier value the audit understands, and it is what
        # aggressiveOemRemoval gates on. There is deliberately NO test asserting which
        # patterns *ought* to be broad: distinguishing a whole-vendor wildcard (*ASUS*)
        # from a legitimately-targeted single app (*Minecraft*) is a judgement call about
        # the software, not a property of the string. Mechanising it produced false
        # positives on Minecraft/Roblox/Netflix, so that judgement stays with the reviewer.
        $broad = @($script:AllApps | Where-Object { $_.tier -eq 'broad' })
        $broad.Count | Should -BeGreaterThan 0 -Because 'the broad tier is expected to be in use'
        foreach ($a in $broad) {
            $a.name | Should -Not -BeNullOrEmpty
        }
    }

    It 'never targets a package that protected-packages.json protects outright' {
        foreach ($a in $script:AllApps) {
            $pattern = if ($a.appx_pattern) { $a.appx_pattern } else { $a.name }
            if ($pattern -match '[*?]') { continue }   # wildcards are gated at runtime instead
            $script:ProtectedKeys | Should -Not -Contain $pattern `
                -Because "'$pattern' is both a removal target and a protected package"
        }
    }
}

Describe 'app-upgrade-config.json vs essential-apps.json' {

    It 'never excludes from upgrade something the essential list installs' {
        # The Adobe* bug: pinning an installed-by-us app at its first version, forever.
        $patterns = @($script:AppUpgrade.ExcludePatterns)
        foreach ($app in $script:Essential) {
            foreach ($p in $patterns) {
                if (-not $p) { continue }
                ($app.name -like $p) | Should -BeFalse `
                    -Because "ExcludePattern '$p' pins essential app '$($app.name)' at its installed version forever"
                if ($app.winget) {
                    ($app.winget -like $p) | Should -BeFalse `
                        -Because "ExcludePattern '$p' matches essential winget id '$($app.winget)'"
                }
            }
        }
    }

    It 'declares a non-empty ExcludePatterns list' {
        @($script:AppUpgrade.ExcludePatterns).Count | Should -BeGreaterThan 0
    }
}

Describe 'essential-apps.json' {
    It 'gives every app a name and a winget id' {
        foreach ($a in $script:Essential) {
            $a.name | Should -Not -BeNullOrEmpty
            $a.winget | Should -Not -BeNullOrEmpty -Because "'$($a.name)' needs a winget id to be installable"
        }
    }

    It 'uses a positive integer timeout where one is declared' {
        # The per-app timeout is threaded through the diff as TimeoutSeconds. When it was
        # dropped, LibreOffice (900s) was killed by the 600s default and reported as failed.
        foreach ($a in $script:Essential) {
            if ($a.ContainsKey('timeout')) {
                $a.timeout | Should -BeOfType [long]
                $a.timeout | Should -BeGreaterThan 0
            }
        }
    }

    It 'has no duplicate winget ids' {
        $ids = @($script:Essential.winget | Where-Object { $_ })
        ($ids | Select-Object -Unique).Count | Should -Be $ids.Count
    }
}

Describe 'security-baseline.json' {

    It 'declares all three enforcement blocks' {
        # Three different mechanisms: registry -> Set-RegistryValue, securityPolicy -> secedit,
        # auditPolicy -> auditpol. A rule in the wrong block is silently never enforced.
        foreach ($block in 'registry', 'securityPolicy', 'auditPolicy') {
            $script:Security.ContainsKey($block) | Should -BeTrue -Because "the '$block' block drives its own compare/apply pair"
        }
    }

    It 'gives every registry entry a path and a name' {
        foreach ($e in @($script:Security.registry)) {
            $e.path | Should -Not -BeNullOrEmpty
            $e.name | Should -Not -BeNullOrEmpty
        }
    }

    It 'gives every auditPolicy entry a subcategory' {
        foreach ($e in @($script:Security.auditPolicy)) {
            $e.subcategory | Should -Not -BeNullOrEmpty -Because 'entries with no subcategory are skipped outright'
        }
    }

    It 'keeps SCENoApplyLegacyAuditPolicy = 1 in the registry block' {
        # Load-bearing: without it, legacy category-level audit policy overrides every
        # section-17 subcategory setting and they silently do nothing.
        $entry = @($script:Security.registry) | Where-Object { $_.name -eq 'SCENoApplyLegacyAuditPolicy' } | Select-Object -First 1
        $entry | Should -Not -BeNullOrEmpty -Because 'section 17 audit settings are inert without it'
        $entry.desiredValue | Should -Be 1
    }

    It 'keeps the deliberate EnableAppInstaller deviation at 1 (winget must keep working)' {
        # CIS 18.10.17.1/18.1 says 0, which disables winget - SoftwareManagement and the
        # Sysmon install both depend on it. This deviation is chosen, not an oversight.
        $entry = @($script:Security.registry) | Where-Object { $_.name -eq 'EnableAppInstaller' } | Select-Object -First 1
        if ($entry) {
            $entry.desiredValue | Should -Be 1 -Because 'setting this to 0 would break winget and the whole SoftwareManagement pair'
        }
    }

    It 'declares LockoutBadCount as a non-zero threshold' {
        if ($script:Security.securityPolicy.ContainsKey('LockoutBadCount')) {
            $script:Security.securityPolicy.LockoutBadCount | Should -BeGreaterThan 0 `
                -Because '0 disables account lockout entirely and fails the benchmark'
        }
    }
}
