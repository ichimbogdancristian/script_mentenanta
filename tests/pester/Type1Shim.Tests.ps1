Describe 'Type1 modules import with TestCoreShim' {
    It 'imports shim and BloatwareDetectionAudit and calls Find-InstalledBloatware safely' {
        # Import test shim to provide required CoreInfrastructure functions
        Import-Module "$PSScriptRoot\..\..\modules\core\TestCoreShim.psm1" -Force

        # Import the Type1 module under test
        $type1Path = Join-Path (Split-Path -Parent $PSScriptRoot) '..\modules\type1\BloatwareDetectionAudit.psm1'
        $type1Path = (Resolve-Path $type1Path).Path
        Import-Module $type1Path -Force -ErrorAction Stop

        # Verify function exists (explicit check for older Pester compatibility)
        $cmd = Get-Command -Name 'Find-InstalledBloatware' -ErrorAction SilentlyContinue
        if (-not $cmd) { throw 'Find-InstalledBloatware function not available' }

        # Call detection function in a safe way (UseCache to avoid heavy operations)
        $result = Find-InstalledBloatware -UseCache -Categories @('all') -Context 'UnitTest'

        # Accept either an array or $null result (Type1 modules may return @() or $null in constrained env)
        if ($null -ne $result -and -not ($result -is [array])) { throw 'Find-InstalledBloatware returned unexpected type' }
    }
}
