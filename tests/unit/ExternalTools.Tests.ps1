#Requires -Version 7.0
<#
    Tests for the external-tool acquisition layer (Phase 4) and the MoveFile boot-time
    deletion it enables in DiskCleanup (Phase 5).

    No network, no downloads, no registry writes, no system changes. Invoke-WebRequest,
    Expand-Archive, the signature check and the external process runner are all mocked.

    The safety assertions matter more than the happy paths here. Add-BootTimeDelete writes to
    PendingFileRenameOperations, which Session Manager executes at next boot as SYSTEM, with
    nothing watching and no undo. A path escaping the validated cleanup root would be deleted
    with no way to intervene.
#>

BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:RepoRoot 'modules\core\Maintenance.psm1') -Force -Global -ErrorAction Stop
    Import-Module (Join-Path $script:RepoRoot 'modules\type2\DiskCleanup.psm1') -Force -ErrorAction Stop

    $script:Sandbox = Join-Path ([System.IO.Path]::GetTempPath()) ("tools-{0}" -f [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $script:Sandbox -Force | Out-Null
}

AfterAll {
    if ($script:Sandbox -and (Test-Path $script:Sandbox)) {
        Remove-Item -LiteralPath $script:Sandbox -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Resolve-ExternalToolPath' {
    It 'prefers the 64-bit build when both are present' {
        $d = Join-Path $script:Sandbox 'both'; New-Item -ItemType Directory -Path $d -Force | Out-Null
        Set-Content (Join-Path $d 'handle.exe') 'x'; Set-Content (Join-Path $d 'handle64.exe') 'x'
        (Split-Path (Resolve-ExternalToolPath -BaseName 'handle' -Directory $d) -Leaf) | Should -Be 'handle64.exe'
    }

    It 'falls back to the unsuffixed build' {
        $d = Join-Path $script:Sandbox 'plain'; New-Item -ItemType Directory -Path $d -Force | Out-Null
        Set-Content (Join-Path $d 'movefile.exe') 'x'
        (Split-Path (Resolve-ExternalToolPath -BaseName 'movefile' -Directory $d) -Leaf) | Should -Be 'movefile.exe'
    }

    It 'returns null when neither form exists' {
        $d = Join-Path $script:Sandbox 'empty'; New-Item -ItemType Directory -Path $d -Force | Out-Null
        Resolve-ExternalToolPath -BaseName 'nothing' -Directory $d | Should -BeNullOrEmpty
    }
}

Describe 'Get-ExternalTool' {

    It 'returns null rather than throwing when the download fails' {
        InModuleScope Maintenance {
            Mock Get-TempPath { $env:TEMP }
            Mock Resolve-ExternalToolPath { $null }
            Mock Invoke-WebRequest { throw 'no such host' }
            $r = $null
            { $script:r = Get-ExternalTool -Name 'nope' -Url 'https://invalid.invalid/x.zip' } | Should -Not -Throw
            $script:r | Should -BeNullOrEmpty
        }
    }

    It 'returns null when the archive contains no matching executable' {
        InModuleScope Maintenance {
            Mock Get-TempPath { $env:TEMP }
            Mock Invoke-WebRequest { }
            Mock Expand-Archive { }
            Mock Resolve-ExternalToolPath { $null }
            Get-ExternalTool -Name 'ghost' -Url 'https://example.invalid/g.zip' | Should -BeNullOrEmpty
        }
    }

    It 'REJECTS a binary that is not Microsoft-signed' {
        InModuleScope Maintenance {
            Mock Get-TempPath { $env:TEMP }
            Mock Invoke-WebRequest { }
            Mock Expand-Archive { }
            Mock Resolve-ExternalToolPath { 'C:\fake\tool.exe' } -ParameterFilter { $BaseName -eq 'tool' }
            Mock Test-MicrosoftSignedBinary { $false }
            Get-ExternalTool -Name 'tool' -Url 'https://example.invalid/t.zip' |
                Should -BeNullOrEmpty -Because 'an unverified downloaded binary must never be executed'
        }
    }

    It 'skips the download entirely when the tool is already present AND still verifies' {
        InModuleScope Maintenance {
            Mock Get-TempPath { $env:TEMP }
            Mock Resolve-ExternalToolPath { 'C:\cached\handle64.exe' }
            Mock Test-MicrosoftSignedBinary { $true }
            Mock Invoke-WebRequest { }
            Get-ExternalTool -Name 'handle' -Url 'https://example.invalid/h.zip' | Should -Be 'C:\cached\handle64.exe'
            Should -Invoke Invoke-WebRequest -Times 0 -Exactly
            Should -Invoke Test-MicrosoftSignedBinary -Times 1 `
                -Because 'a cached binary is re-verified, not trusted on the basis of being present'
        }
    }

    It 'DISCARDS a cached binary that fails verification instead of returning it' {
        # Found by this test file. The first version returned early on a cache hit without
        # verifying, and left a rejected binary on disk after a failed download-path check -
        # so the next call would hand back the exact file the gate had just refused.
        InModuleScope Maintenance {
            Mock Get-TempPath { $env:TEMP }
            Mock Resolve-ExternalToolPath { 'C:\cached\tainted64.exe' }
            Mock Test-MicrosoftSignedBinary { $false }
            Mock Remove-Item { }
            Get-ExternalTool -Name 'tainted' -Url 'https://example.invalid/t.zip' | Should -BeNullOrEmpty
            Should -Invoke Remove-Item -Times 1 -Because 'the rejected binary must not survive for the next call'
        }
    }
}

Describe 'Invoke-CapturedCommand' {
    It 'captures stdout and the exit code' {
        $r = Invoke-CapturedCommand -FilePath 'cmd.exe' -ArgumentList @('/c', 'echo', 'hello-capture') -TimeoutSeconds 20
        $r.ExitCode | Should -Be 0
        $r.StdOut.Trim() | Should -Be 'hello-capture'
        $r.TimedOut | Should -BeFalse
    }

    It 'reports a non-zero exit code' {
        (Invoke-CapturedCommand -FilePath 'cmd.exe' -ArgumentList @('/c', 'exit', '7') -TimeoutSeconds 20).ExitCode |
            Should -Be 7
    }

    It 'kills the process tree and reports TimedOut on timeout' {
        $r = Invoke-CapturedCommand -FilePath 'cmd.exe' -ArgumentList @('/c', 'ping', '-n', '30', '127.0.0.1') -TimeoutSeconds 2
        $r.TimedOut | Should -BeTrue
        $r.ExitCode | Should -Be -1
    }

    It 'returns a sentinel instead of throwing when the process cannot start' {
        $r = Invoke-CapturedCommand -FilePath 'C:\does\not\exist\nope.exe' -TimeoutSeconds 5
        $r.ExitCode | Should -Be -2147483648
    }
}

Describe 'Add-BootTimeDelete - SAFETY' {
    # PendingFileRenameOperations runs as Session Manager at boot with no undo. These are the
    # tests that keep it pointed only at files the caller already validated.

    BeforeAll {
        $script:Root = Join-Path $script:Sandbox 'cleanroot'
        New-Item -ItemType Directory -Path $script:Root -Force | Out-Null
        $script:Inside = Join-Path $script:Root 'locked.tmp'
        Set-Content -LiteralPath $script:Inside 'x'
        $script:Outside = Join-Path $script:Sandbox 'outside.tmp'
        Set-Content -LiteralPath $script:Outside 'x'
    }

    It 'queues a file that lives inside the cleanup root' {
        InModuleScope DiskCleanup -Parameters @{ P = $script:Inside; R = $script:Root } {
            param($P, $R)
            Mock Invoke-ExternalPackageCommand { 0 }
            (Add-BootTimeDelete -Path @($P) -UnderRoot $R -MoveFileExe 'movefile.exe') | Should -Be 1
        }
    }

    It 'REFUSES a file outside the cleanup root' {
        InModuleScope DiskCleanup -Parameters @{ P = $script:Outside; R = $script:Root } {
            param($P, $R)
            Mock Invoke-ExternalPackageCommand { 0 }
            (Add-BootTimeDelete -Path @($P) -UnderRoot $R -MoveFileExe 'movefile.exe') | Should -Be 0
            Should -Invoke Invoke-ExternalPackageCommand -Times 0 -Exactly `
                -Because 'a path escaping the validated root must never be queued'
        }
    }

    It 'REFUSES traversal back out of the root' {
        InModuleScope DiskCleanup -Parameters @{ P = (Join-Path $script:Root '..\outside.tmp'); R = $script:Root } {
            param($P, $R)
            Mock Invoke-ExternalPackageCommand { 0 }
            (Add-BootTimeDelete -Path @($P) -UnderRoot $R -MoveFileExe 'movefile.exe') | Should -Be 0
        }
    }

    It 'REFUSES to operate on a system-critical root at all' {
        InModuleScope DiskCleanup {
            Mock Invoke-ExternalPackageCommand { 0 }
            foreach ($bad in $env:SystemRoot, (Join-Path $env:SystemRoot 'System32'), $env:ProgramFiles) {
                (Add-BootTimeDelete -Path @("$bad\anything.tmp") -UnderRoot $bad -MoveFileExe 'movefile.exe') |
                    Should -Be 0 -Because "$bad must never accept boot-time deletes"
            }
            Should -Invoke Invoke-ExternalPackageCommand -Times 0 -Exactly
        }
    }

    It 'skips paths that no longer exist' {
        InModuleScope DiskCleanup -Parameters @{ R = $script:Root } {
            param($R)
            Mock Invoke-ExternalPackageCommand { 0 }
            (Add-BootTimeDelete -Path @((Join-Path $R 'vanished.tmp')) -UnderRoot $R -MoveFileExe 'movefile.exe') |
                Should -Be 0
        }
    }

    It 'does not count a MoveFile invocation that failed' {
        InModuleScope DiskCleanup -Parameters @{ P = $script:Inside; R = $script:Root } {
            param($P, $R)
            Mock Invoke-ExternalPackageCommand { 1 }
            (Add-BootTimeDelete -Path @($P) -UnderRoot $R -MoveFileExe 'movefile.exe') | Should -Be 0
        }
    }

    It 'passes -accepteula and an EMPTY destination, which is what means "delete"' {
        InModuleScope DiskCleanup -Parameters @{ P = $script:Inside; R = $script:Root } {
            param($P, $R)
            $script:sentArgs = $null
            Mock Invoke-ExternalPackageCommand { $script:sentArgs = $ArgumentList; 0 }
            $null = Add-BootTimeDelete -Path @($P) -UnderRoot $R -MoveFileExe 'movefile.exe'
            $script:sentArgs[0] | Should -Be '-accepteula' -Because 'a EULA prompt would hang the unattended run'
            $script:sentArgs[-1] | Should -Be '""' -Because 'an empty destination is what schedules a delete'
        }
    }
}

Describe 'Get-MoveFileTool gating' {
    It 'returns null when the tools layer is disabled in config' {
        InModuleScope DiskCleanup {
            $script:MoveFileResolved = $false; $script:MoveFileExe = $null
            Mock Get-MainConfig { @{ tools = @{ enabled = $false } } }
            Mock Get-ExternalTool { 'should-not-be-called' }
            Get-MoveFileTool | Should -BeNullOrEmpty
            Should -Invoke Get-ExternalTool -Times 0 -Exactly
        }
    }

    It 'returns null when movefile specifically is disabled' {
        InModuleScope DiskCleanup {
            $script:MoveFileResolved = $false; $script:MoveFileExe = $null
            Mock Get-MainConfig { @{ tools = @{ enabled = $true; sysinternals = @{ movefile = @{ enabled = $false; url = 'x' } } } } }
            Mock Get-ExternalTool { 'should-not-be-called' }
            Get-MoveFileTool | Should -BeNullOrEmpty
            Should -Invoke Get-ExternalTool -Times 0 -Exactly
        }
    }

    It 'resolves only ONCE per run even across repeated calls' {
        InModuleScope DiskCleanup {
            $script:MoveFileResolved = $false; $script:MoveFileExe = $null
            Mock Get-MainConfig { @{ tools = @{ enabled = $true; sysinternals = @{ movefile = @{ enabled = $true; url = 'https://x/y.zip' } } } } }
            Mock Initialize-SysinternalsEula { $true }
            Mock Get-ExternalTool { 'C:\tools\movefile.exe' }
            $a = Get-MoveFileTool; $b = Get-MoveFileTool; $c = Get-MoveFileTool
            $a | Should -Be 'C:\tools\movefile.exe'
            $b | Should -Be $a; $c | Should -Be $a
            Should -Invoke Get-ExternalTool -Times 1 -Exactly -Because 'one download attempt per run, not per locked file'
        }
    }

    It 'degrades to null when config access throws' {
        InModuleScope DiskCleanup {
            $script:MoveFileResolved = $false; $script:MoveFileExe = $null
            Mock Get-MainConfig { throw 'config unreadable' }
            { Get-MoveFileTool | Should -BeNullOrEmpty } | Should -Not -Throw
        }
    }
}
