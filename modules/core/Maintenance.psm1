#Requires -Version 7.0

<#
.SYNOPSIS
    Maintenance Core Module - Foundation for Windows Maintenance Automation

.DESCRIPTION
    Single core module providing all shared infrastructure:
    - Path management (project, config, temp files)
    - Configuration loading (JSON deserialization, OS-aware)
    - Structured logging (transcript-compatible output)
    - OS detection (Windows 10 vs 11, build number, feature flags)
    - Diff engine (compare Type1 scan results against preexisting baseline lists)
    - Module result objects (standardized return schema)
    - Shared system queries (installed apps, services, registry helpers)

    Replaces: CoreInfrastructure, CommonUtilities, DiffEngine, LogAggregator, UserInterface

.NOTES
    Module Type: Core Infrastructure
    Version: 5.0.0
    Architecture: v5.0 - Unified single-core design
    Author: Windows Maintenance Automation Project
    Import: Import-Module Maintenance.psm1 -Force -Global
#>

using namespace System.Collections.Generic
Set-StrictMode -Version 1.0

#region ─── INITIALIZATION ────────────────────────────────────────────────────

<#
.SYNOPSIS
    Initializes path environment variables from the known project root.
.PARAMETER ProjectRoot
    Absolute path to the project folder (where script.bat lives).
#>
function Initialize-Maintenance {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectRoot
    )
    $env:MAINT_ROOT = $ProjectRoot
    $env:MAINT_CONFIG = Join-Path $ProjectRoot 'config'
    $env:MAINT_MODULES = Join-Path $ProjectRoot 'modules'
    $env:MAINT_TEMP = Join-Path $ProjectRoot 'temp_files'
    $env:MAINT_LISTS = Join-Path $ProjectRoot 'config\lists'
    $env:MAINT_SETTINGS = Join-Path $ProjectRoot 'config\settings'

    # Guarantee all temp subdirectories exist
    foreach ($sub in 'data', 'logs', 'reports', 'diff') {
        $dir = Join-Path $env:MAINT_TEMP $sub
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    }
    Write-Log -Level INFO -Component CORE -Message "Maintenance initialized. Root: $ProjectRoot"
}

#endregion

#region ─── LOGGING ───────────────────────────────────────────────────────────

<#
.SYNOPSIS
    Writes a structured log line to the console (captured by Start-Transcript).
    Colors are stripped inside non-interactive sessions automatically.
.PARAMETER Level
    INFO | WARN | ERROR | DEBUG | SUCCESS
.PARAMETER Component
    Uppercase short module tag, e.g. BLOATWARE, CORE, ESSENTIALAPPS
.PARAMETER Message
    Free-form message text
#>
function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('INFO', 'WARN', 'ERROR', 'DEBUG', 'SUCCESS')]
        [string]$Level,

        [Parameter(Mandatory)]
        [string]$Component,

        [Parameter(Mandatory)]
        [string]$Message
    )

    $ts = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $line = "[$ts] [$Level] [$Component] $Message"

    $color = switch ($Level) {
        'INFO' { 'Cyan' }
        'WARN' { 'Yellow' }
        'ERROR' { 'Red' }
        'DEBUG' { 'DarkGray' }
        'SUCCESS' { 'Green' }
        default { 'White' }
    }
    Write-Host $line -ForegroundColor $color
}

#endregion

#region ─── OS DETECTION ──────────────────────────────────────────────────────

<#
.SYNOPSIS
    Returns a structured OS context object.
.OUTPUTS
    hashtable with keys: IsWindows11, BuildNumber, MajorVersion, DisplayText,
    Features (hashtable of available OS features)
#>
function Get-OSContext {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        $build = [int]($os.BuildNumber)
        $caption = $os.Caption

        # Windows 11 starts at build 22000
        $isWin11 = $build -ge 22000

        $ctx = @{
            IsWindows11  = $isWin11
            BuildNumber  = $build
            MajorVersion = if ($isWin11) { 11 } else { 10 }
            Caption      = $caption
            DisplayText  = if ($isWin11) { "Windows 11 (build $build)" } else { "Windows 10 (build $build)" }
            Features     = @{
                AndroidApps   = $build -ge 22000
                SnapLayouts   = $build -ge 22000
                DirectStorage = $build -ge 22000
                TPM2Required  = $build -ge 22000
                WinGet        = $build -ge 19041
            }
        }

        Write-Log -Level INFO -Component CORE -Message "OS detected: $($ctx.DisplayText)"
        return $ctx
    }
    catch {
        Write-Log -Level WARN -Component CORE -Message "OS detection failed - assuming Windows 10: $_"
        return @{
            IsWindows11 = $false; BuildNumber = 19041
            MajorVersion = 10; Caption = 'Windows 10'
            DisplayText = 'Windows 10 (detection failed)'
            Features = @{ WinGet = $true }
        }
    }
}

#endregion

#region ─── CONFIGURATION ─────────────────────────────────────────────────────

<#
.SYNOPSIS
    Loads and returns the main configuration hashtable from main-config.json.
#>
function Get-MainConfig {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    $path = Join-Path $env:MAINT_SETTINGS 'main-config.json'
    if (-not (Test-Path $path)) {
        Write-Log -Level WARN -Component CORE -Message "main-config.json not found at $path. Using built-in defaults."
        return @{
            execution = @{
                shutdown = @{ countdownSeconds = 120; rebootOnTimeout = $true; cleanupOnTimeout = $true; rebootOnlyWhenRequired = $true }
            }
            modules   = @{}
            reporting = @{ enableHtmlReport = $true }
        }
    }

    try {
        $raw = Get-Content -Path $path -Raw -Encoding UTF8
        $obj = $raw | ConvertFrom-Json -Depth 20 -AsHashtable
        Write-Log -Level DEBUG -Component CORE -Message "main-config.json loaded"
        return $obj
    }
    catch {
        Write-Log -Level ERROR -Component CORE -Message "Failed to parse main-config.json: $_"
        throw
    }
}

<#
.SYNOPSIS
    Loads a preexisting baseline list for a module from config/lists/[folder]/[file].
.DESCRIPTION
    Returns the baseline data as a nested [hashtable] (using -AsHashtable) so that
    all JSON objects become case-insensitive hashtables — consistent with
    Get-MainConfig.  This ensures uniform dot-access, index-access, and
    .ContainsKey() behaviour throughout the project.
.PARAMETER ModuleFolder
    Subfolder name under config/lists/ (e.g. 'bloatware').
.PARAMETER FileName
    JSON filename (e.g. 'bloatware-list.json').
.OUTPUTS
    [hashtable] or $null on failure.  Arrays in the JSON become [object[]].
#>
function Get-BaselineList {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$ModuleFolder,
        [Parameter(Mandatory)] [string]$FileName
    )

    $path = Join-Path $env:MAINT_LISTS "$ModuleFolder\$FileName"
    if (-not (Test-Path $path)) {
        Write-Log -Level WARN -Component CORE -Message "Baseline list not found: $path"
        return $null
    }
    try {
        # -AsHashtable: returns [hashtable] instead of [PSCustomObject].
        # This keeps return types consistent with Get-MainConfig and allows
        # callers to use .ContainsKey(), case-insensitive key lookup, and
        # index-access ($obj['key']) uniformly.
        $obj = Get-Content -Path $path -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 20 -AsHashtable
        Write-Log -Level DEBUG -Component CORE -Message "Loaded baseline: $path"
        return $obj
    }
    catch {
        Write-Log -Level ERROR -Component CORE -Message "Failed to parse $path : $_"
        return $null
    }
}

#endregion

#region ─── TEMP FILE PATHS ───────────────────────────────────────────────────

<#
.SYNOPSIS
    Returns an absolute path inside temp_files, creating the parent directory if needed.
.PARAMETER Category
    Subfolder: 'data' | 'logs' | 'reports' | 'diff'
.PARAMETER SubFolder
    Optional sub-subfolder (e.g. module name for logs).
.PARAMETER FileName
    Optional file name; if omitted returns the folder path.
#>
function Get-TempPath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('data', 'logs', 'reports', 'diff')]
        [string]$Category,

        [Parameter()] [string]$SubFolder,
        [Parameter()] [string]$FileName
    )

    $dir = Join-Path $env:MAINT_TEMP $Category
    if ($SubFolder) { $dir = Join-Path $dir $SubFolder }
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

    if ($FileName) { return Join-Path $dir $FileName }
    return $dir
}

#endregion

#region ─── DIFF ENGINE ───────────────────────────────────────────────────────

<#
.SYNOPSIS
    Persists a diff list to temp_files/diff/[ModuleName]-diff.json.
#>
function Save-DiffList {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$ModuleName,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [array]$DiffList
    )

    $path = Get-TempPath -Category 'diff' -FileName "$ModuleName-diff.json"
    $DiffList | ConvertTo-Json -Depth 10 | Set-Content -Path $path -Encoding UTF8 -Force
    Write-Log -Level DEBUG -Component CORE -Message "Diff saved: $path ($($DiffList.Count) items)"
}

<#
.SYNOPSIS
    Loads a previously saved diff list. Returns empty array if not found.
.DESCRIPTION
    Reads the diff JSON produced by a Type1 module (via Save-DiffList) and
    returns it as an array of hashtables.  Using -AsHashtable ensures each
    diff item is a [hashtable] — matching the format originally saved —
    so Type2 modules get consistent key access (case-insensitive, indexable).
.PARAMETER ModuleName
    DiffKey identifier (e.g. 'BloatwareRemoval', 'EssentialApps').
.OUTPUTS
    [hashtable[]] — array of diff items, or empty array on failure / not found.
#>
function Get-DiffList {
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)] [string]$ModuleName
    )

    $path = Get-TempPath -Category 'diff' -FileName "$ModuleName-diff.json"
    if (-not (Test-Path $path)) { return , @() }
    try {
        # -AsHashtable: keeps diff items as [hashtable] for uniform access.
        # Type1 modules save hashtable arrays via Save-DiffList;
        # Type2 modules consume them — both sides now use the same type.
        $items = Get-Content -Path $path -Raw | ConvertFrom-Json -Depth 10 -AsHashtable
        if ($null -eq $items) { return , @() }
        # The unary comma forces PowerShell to preserve array-shape on return.
        # Without it, a diff list with EXACTLY ONE item collapses into the bare
        # hashtable itself when the caller assigns the result to a variable —
        # $diff.Count then silently returns the number of KEYS in that one
        # hashtable (e.g. 9) instead of the number of diff items (1). The
        # foreach-based consumption loops happen to still work by accident
        # (foreach over a bare hashtable treats it as one iteration), but every
        # item-count log line and report field would be wrong whenever a
        # module has exactly one pending diff item.
        return , @($items)
    }
    catch { return , @() }
}

#endregion

#region ─── MODULE RESULT OBJECTS ─────────────────────────────────────────────

<#
.SYNOPSIS
    Creates a standardized module result hashtable used by the orchestrator.
.PARAMETER ModuleType
    'Type1' for audit/scan modules, 'Type2' for action/modification modules.
    Used by the report generator to group results by phase.
#>
function New-ModuleResult {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)] [string]$ModuleName,
        [Parameter(Mandatory)] [ValidateSet('Success', 'Failed', 'Skipped', 'Warning')] [string]$Status,
        [Parameter()] [ValidateSet('Type1', 'Type2')] [string]$ModuleType = 'Type1',
        [Parameter()] [int]$ItemsDetected = 0,
        [Parameter()] [int]$ItemsProcessed = 0,
        [Parameter()] [int]$ItemsSkipped = 0,
        [Parameter()] [int]$ItemsFailed = 0,
        [Parameter()] [string]$Message = '',
        [Parameter()] [object[]]$Errors = @(),
        [Parameter()] [bool]$RebootRequired = $false,
        [Parameter()] [hashtable]$ExtraData = @{}
    )
    return @{
        ModuleName     = $ModuleName
        ModuleType     = $ModuleType
        Status         = $Status
        Timestamp      = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        ItemsDetected  = $ItemsDetected
        ItemsProcessed = $ItemsProcessed
        ItemsSkipped   = $ItemsSkipped
        ItemsFailed    = $ItemsFailed
        Message        = $Message
        Errors         = $Errors
        RebootRequired = $RebootRequired
        ExtraData      = $ExtraData
    }
}

#endregion

#region ─── APPX COMPATIBILITY LAYER ──────────────────────────────────────────

<#
.SYNOPSIS
    Executes an AppX-related command, delegating to Windows PowerShell 5.1 when
    running under PS7 Core (where the Appx module is unreliable).
.PARAMETER ScriptBlock
    The PowerShell command string to execute (must use AppX cmdlets).
.OUTPUTS
    Raw output from the command (deserialized objects when via powershell.exe).
#>
function Invoke-AppxInWinPS {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ScriptBlock
    )

    if ($PSVersionTable.PSEdition -eq 'Core') {
        Write-Verbose 'Delegating AppX operation to Windows PowerShell 5.1'
        $winPS = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        return & $winPS -NoProfile -Command $ScriptBlock 2>$null
    }

    # Desktop edition — run directly
    return & ([scriptblock]::Create($ScriptBlock))
}

<#
.SYNOPSIS
    PS7-safe wrapper for Get-AppxPackage. Returns an array of hashtables with
    Name, Version, Publisher and PackageFullName properties.
.PARAMETER Name
    Optional wildcard filter for package names.
.PARAMETER AllUsers
    Query packages for all user accounts.
#>
function Get-AppxPackageCompat {
    [CmdletBinding()]
    [OutputType([hashtable[]])]
    param(
        [string]$Name,
        [switch]$AllUsers
    )

    $cmd = 'Get-AppxPackage'
    if ($AllUsers) { $cmd += ' -AllUsers' }
    if ($Name) { $cmd += " -Name '$Name'" }
    $cmd += ' -ErrorAction SilentlyContinue'
    $cmd += ' | Select-Object Name, Version, Publisher, PackageFullName'

    $raw = Invoke-AppxInWinPS -ScriptBlock $cmd
    if (-not $raw) { return @() }

    # Normalise into plain hashtables (deserialized objects lose methods)
    @($raw) | ForEach-Object {
        @{
            Name            = $_.Name
            Version         = "$($_.Version)"
            Publisher       = $_.Publisher
            PackageFullName = $_.PackageFullName
        }
    }
}

<#
.SYNOPSIS
    PS7-safe wrapper for Remove-AppxPackage.
.PARAMETER PackageFullName
    Full name of the package to remove.
.PARAMETER AllUsers
    Remove for all user accounts.
#>
function Remove-AppxPackageCompat {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$PackageFullName,
        [switch]$AllUsers
    )

    $cmd = "Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue | Where-Object { `$_.PackageFullName -eq '$PackageFullName' } | Remove-AppxPackage"
    if ($AllUsers) { $cmd += ' -AllUsers' }
    $cmd += ' -ErrorAction SilentlyContinue'

    Invoke-AppxInWinPS -ScriptBlock $cmd
}

<#
.SYNOPSIS
    PS7-safe wrapper for Get-AppxProvisionedPackage -Online.
    Returns an array of hashtables with PackageName and DisplayName.
#>
function Get-AppxProvisionedPackageCompat {
    [CmdletBinding()]
    [OutputType([hashtable[]])]
    param()

    $cmd = 'Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Select-Object PackageName, DisplayName'
    $raw = Invoke-AppxInWinPS -ScriptBlock $cmd
    if (-not $raw) { return @() }

    @($raw) | ForEach-Object {
        @{
            PackageName = $_.PackageName
            DisplayName = $_.DisplayName
        }
    }
}

<#
.SYNOPSIS
    PS7-safe wrapper for Remove-AppxProvisionedPackage -Online.
.PARAMETER PackageName
    The provisioned package name to remove.
#>
function Remove-AppxProvisionedPackageCompat {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$PackageName
    )

    $cmd = "Remove-AppxProvisionedPackage -Online -PackageName '$PackageName' -ErrorAction SilentlyContinue"
    Invoke-AppxInWinPS -ScriptBlock $cmd
}

#endregion

#region ─── SHARED SYSTEM QUERIES ─────────────────────────────────────────────

<#
.SYNOPSIS
    Returns a list of installed applications from the Windows registry.
    Covers both 32-bit and 64-bit entry points plus AppX packages.
#>
function Get-InstalledApp {
    [CmdletBinding()]
    [OutputType([object[]])]
    param()

    $apps = [System.Collections.Generic.List[hashtable]]::new()

    $regPaths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )

    foreach ($path in $regPaths) {
        try {
            Get-ItemProperty -Path $path -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName } |
            ForEach-Object {
                $regApp = @{
                    Name      = $_.DisplayName
                    Version   = $_.DisplayVersion
                    Publisher = $_.Publisher
                    Source    = 'Registry'
                }
                $apps.Add($regApp)
            }
        }
        catch { Write-Verbose "Registry path skipped: $_" }
    }

    # Add AppX / MSIX packages via PS7-safe compatibility layer
    try {
        $appxPkgs = Get-AppxPackageCompat
        $appxPkgs | Where-Object { $_.Name -and $_.PackageFullName } | ForEach-Object {
            $apps.Add(@{
                    Name      = $_.Name
                    Version   = $_.Version
                    Publisher = $_.Publisher
                    Source    = 'AppX'
                })
        }
    }
    catch { Write-Verbose "AppX enumeration skipped: $_" }

    # Unary comma preserves array-shape on return even with exactly one app —
    # see the comment in Get-DiffList for why this matters.
    return , $apps.ToArray()
}

<#
.SYNOPSIS
    Returns winget upgrade list as an array of hashtables.
    Returns empty array if winget is not available.
#>
function Get-WingetUpgrade {
    [CmdletBinding()]
    [OutputType([object[]])]
    param()

    if (-not (Test-CommandAvailable 'winget')) { return , @() }

    try {
        $raw = & winget upgrade --include-unknown 2>&1 | Where-Object { $_ -is [string] }
        $result = [System.Collections.Generic.List[hashtable]]::new()

        $inTable = $false
        foreach ($line in $raw) {
            if ($line -match '^-+') { $inTable = $true; continue }
            if (-not $inTable) { continue }
            if ($line -match '^\s*$') { continue }

            $parts = $line -split '\s{2,}'
            if ($parts.Count -ge 4) {
                $wingetItem = @{
                    Name             = $parts[0].Trim()
                    Id               = $parts[1].Trim()
                    CurrentVersion   = $parts[2].Trim()
                    AvailableVersion = $parts[3].Trim()
                    Source           = 'Winget'
                }
                $result.Add($wingetItem)
            }
        }
        # Unary comma preserves array-shape on return even with exactly one
        # upgrade — see the comment in Get-DiffList for why this matters.
        return , $result.ToArray()
    }
    catch {
        Write-Log -Level WARN -Component CORE -Message "winget upgrade query failed: $_"
        return , @()
    }
}

<#
.SYNOPSIS
    Checks whether a command is available in the current session.
#>
function Test-CommandAvailable {
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)] [string]$Command)

    # Fast path: command is already on $PATH
    if ($null -ne (Get-Command $Command -ErrorAction SilentlyContinue)) { return $true }

    # winget lives in a per-user WindowsApps folder that is often absent from PS7's
    # elevated session PATH. Try the two known locations before giving up.
    if ($Command -eq 'winget') {
        $candidates = @(
            (Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\winget.exe'),
            (Join-Path $env:ProgramFiles  'WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe')
        )
        foreach ($pattern in $candidates) {
            $resolved = Get-Item -Path $pattern -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($resolved) {
                # Add the directory to the current session's PATH so subsequent calls work
                $wingetDir = Split-Path $resolved.FullName
                if ($env:PATH -notlike "*$wingetDir*") {
                    $env:PATH = "$($env:PATH);$wingetDir"
                }
                return $true
            }
        }
    }

    return $false
}

<#
.SYNOPSIS
    Reads a registry value safely, returning $null on failure.
#>
function Get-RegistryValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [string]$Name
    )
    return (Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue).$Name
}

<#
.SYNOPSIS
    Sets or creates a registry value. Skips if value AND type already correct.
.DESCRIPTION
    Compares both the current value and its on-disk registry type against the
    desired value/type before short-circuiting — a string "0" and a DWord 0
    compare equal in PowerShell but are not the same on-disk representation,
    so a type-only mismatch is still corrected. Write failures (access-denied,
    GPO-locked keys) are caught explicitly rather than silently swallowed by
    the default non-terminating ErrorActionPreference, so a failed write
    returns $false instead of falsely reporting success.
.OUTPUTS
    bool - $true if a change was made, $false if already correct or the write failed.
#>
function Set-RegistryValue {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [string]$Name,
        [Parameter(Mandatory)] [object]$Value,
        [Parameter(Mandatory)] [string]$Type
    )

    $current = Get-RegistryValue -Path $Path -Name $Name
    $currentType = $null
    if (Test-Path $Path) {
        try {
            $item = Get-Item -Path $Path -ErrorAction Stop
            $currentType = $item.GetValueKind($Name)
        }
        catch { $currentType = $null }
    }

    $valueMatches = ($null -ne $current) -and ($current -eq $Value)
    $typeMatches = ($null -ne $currentType) -and ($currentType.ToString() -eq $Type)
    if ($valueMatches -and $typeMatches) { return $false }

    try {
        if (-not (Test-Path $Path)) {
            New-Item -Path $Path -Force -ErrorAction Stop | Out-Null
        }
        Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type -Force -ErrorAction Stop
        return $true
    }
    catch {
        Write-Log -Level ERROR -Component CORE -Message "Failed to set $Path\$Name = $Value ($Type): $_"
        return $false
    }
}

<#
.SYNOPSIS
    Compares baseline registry entries against live system state and returns diff items.
.DESCRIPTION
    Shared audit-side registry comparison, factored out of SecurityAudit.psm1 and
    TelemetryAudit.psm1 (both previously hand-rolled the identical loop). Each
    entry is a hashtable shaped { path, name, desiredValue, type, description, nonEmpty }.
    When an entry sets nonEmpty = $true (e.g. a legal-notice banner that just needs
    to be non-blank, not match a specific placeholder string), the comparison checks
    for a non-whitespace current value instead of exact equality.
.PARAMETER Entries
    Array of baseline registry entries to check.
.OUTPUTS
    [hashtable[]] — diff items shaped { Type='registry'; Name; Description; Path;
    ValueName; DesiredValue; ValueType; CurrentState; DesiredState }.
#>
function Compare-RegistryBaseline {
    [CmdletBinding()]
    [OutputType([hashtable[]])]
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [array]$Entries
    )

    $diff = [System.Collections.Generic.List[hashtable]]::new()
    foreach ($entry in $Entries) {
        $current = Get-RegistryValue -Path $entry.path -Name $entry.name
        $desired = $entry.desiredValue

        $mismatch = if ($entry.nonEmpty) {
            [string]::IsNullOrWhiteSpace("$current")
        }
        else {
            ($null -eq $current) -or ("$current" -ne "$desired")
        }

        if ($mismatch) {
            $diff.Add(@{
                    Type         = 'registry'
                    Name         = "$($entry.path)\$($entry.name)"
                    Description  = $entry.description
                    Path         = $entry.path
                    ValueName    = $entry.name
                    DesiredValue = $desired
                    ValueType    = if ($entry.type) { $entry.type } else { 'DWord' }
                    CurrentState = $current
                    DesiredState = $desired
                })
        }
    }
    # Unary comma preserves array-shape on return even when $diff has exactly
    # one element — see the comment in Get-DiffList for why this matters.
    return , $diff.ToArray()
}

<#
.SYNOPSIS
    Applies a single registry-typed diff item (writes the registry value).
.DESCRIPTION
    Shared action-side registry writer, factored out of SecurityEnhancement.psm1,
    TelemetryDisable.psm1, and SystemOptimization.psm1 (all three previously
    hand-rolled the identical Path/ValueName/DesiredValue/ValueType extraction
    and Set-RegistryValue call). Callers pass a -Component tag so log lines
    still attribute back to the calling domain module.
.PARAMETER Item
    Diff item hashtable with Path/RegistryPath, ValueName/Name, DesiredValue, ValueType.
.PARAMETER Component
    Log component tag to attribute this write to (e.g. 'SECURITY', 'TELEMETRY', 'SYSOPT').
.OUTPUTS
    bool - $true if the value was changed, $false if already correct, malformed, or the write failed.
#>
function Invoke-RegistryChangeItem {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)] [hashtable]$Item,
        [Parameter(Mandatory)] [string]$Component
    )

    $path = $Item.Path ?? $Item.RegistryPath
    $vname = $Item.ValueName ?? $Item.Name
    $val = $Item.DesiredValue
    $vtype = $Item.ValueType ?? 'DWord'

    if (-not $path -or -not $vname -or $null -eq $val) { return $false }

    $changed = Set-RegistryValue -Path $path -Name $vname -Value $val -Type $vtype
    if ($changed) {
        Write-Log -Level SUCCESS -Component $Component -Message "Registry: $path\$vname = $val"
    }
    return $changed
}

<#
.SYNOPSIS
    Compares a list of service names against a desired running/disabled state.
.DESCRIPTION
    Shared audit-side service comparison, factored out of SecurityAudit.psm1,
    TelemetryAudit.psm1, and SystemOptimizationAudit.psm1 (all three previously
    hand-rolled the identical Get-Service + StartType/Status check).
.PARAMETER ServiceNames
    Array of Windows service names to check.
.PARAMETER Action
    'EnsureRunning' checks Status -ne 'Running'; 'EnsureDisabled' (default) checks
    StartType -ne 'Disabled'.
.OUTPUTS
    [hashtable[]] — diff items shaped { Type='service'; Name; ServiceName; Action;
    CurrentState; DesiredState }.
#>
function Compare-ServiceBaseline {
    [CmdletBinding()]
    [OutputType([hashtable[]])]
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [array]$ServiceNames,
        [Parameter()] [ValidateSet('EnsureRunning', 'EnsureDisabled')] [string]$Action = 'EnsureDisabled'
    )

    $diff = [System.Collections.Generic.List[hashtable]]::new()
    foreach ($svcName in $ServiceNames) {
        try {
            $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
            if (-not $svc) { continue }

            if ($Action -eq 'EnsureRunning' -and $svc.Status -ne 'Running') {
                $diff.Add(@{
                        Type         = 'service'
                        Name         = $svcName
                        ServiceName  = $svcName
                        Action       = 'EnsureRunning'
                        CurrentState = $svc.Status.ToString()
                        DesiredState = 'Running'
                    })
            }
            elseif ($Action -eq 'EnsureDisabled' -and $svc.StartType -ne 'Disabled') {
                $diff.Add(@{
                        Type         = 'service'
                        Name         = $svcName
                        ServiceName  = $svcName
                        Action       = 'EnsureDisabled'
                        CurrentState = $svc.StartType.ToString()
                        DesiredState = 'Disabled'
                    })
            }
        }
        catch { Write-Log -Level WARN -Component CORE -Message "Service query failed '$svcName': $_" }
    }
    # Unary comma preserves array-shape on return even when $diff has exactly
    # one element — see the comment in Get-DiffList for why this matters.
    return , $diff.ToArray()
}

<#
.SYNOPSIS
    Applies a single service-typed diff item (starts/stops and sets startup type).
.DESCRIPTION
    Shared action-side service toggler, factored out of SecurityEnhancement.psm1,
    TelemetryDisable.psm1, and SystemOptimization.psm1. Supports both calling
    conventions already in use: an Action field ('EnsureRunning'/'EnsureDisabled',
    Security/Telemetry style) or a literal DesiredStartType/DesiredState value
    (SystemOptimization style, defaults to 'Disabled' when absent).
.PARAMETER Item
    Diff item hashtable with ServiceName/Name and either Action or DesiredStartType/DesiredState.
.PARAMETER Component
    Log component tag to attribute this change to.
.OUTPUTS
    bool - $true if a change was applied, $false if the item was malformed.
#>
function Invoke-ServiceChangeItem {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)] [hashtable]$Item,
        [Parameter(Mandatory)] [string]$Component
    )

    $svc = $Item.ServiceName ?? $Item.Name
    if (-not $svc) { return $false }

    if ($Item.Action -eq 'EnsureRunning') {
        Set-Service -Name $svc -StartupType Automatic -ErrorAction Stop
        Start-Service -Name $svc -ErrorAction Stop
        Write-Log -Level SUCCESS -Component $Component -Message "Service started: $svc"
        return $true
    }

    $targetType = $Item.DesiredStartType ?? $Item.DesiredState
    if (-not $targetType -or $Item.Action -eq 'EnsureDisabled') { $targetType = 'Disabled' }

    try { Stop-Service -Name $svc -Force -ErrorAction Stop }
    catch { Write-Log -Level WARN -Component $Component -Message "Could not stop service $svc (may be protected): $_" }

    Set-Service -Name $svc -StartupType $targetType -ErrorAction Stop
    Write-Log -Level SUCCESS -Component $Component -Message "Service '$svc' -> $targetType"
    return $true
}

#endregion

#region ─── EXTERNAL PROCESS HELPER ───────────────────────────────────────────

<#
.SYNOPSIS
    Runs an external executable (e.g. winget, choco) and returns its exit code.
.DESCRIPTION
    Wraps System.Diagnostics.Process for silent, non-interactive external
    command execution.  Reads stdout/stderr asynchronously via output/error
    event handlers rather than sequential ReadToEnd() calls — reading stdout
    to completion before touching stderr is a classic .NET deadlock: if the
    child fills the stderr OS pipe buffer while the parent is still blocked
    on stdout, the child blocks trying to write and the whole process (and
    the entire unattended maintenance run) hangs forever. A hard timeout
    with kill-on-expiry is included since an unattended run has no one
    watching to notice a hung external tool.
    Used by Type2 modules (EssentialApps, AppUpgrade) that invoke package
    managers to install or upgrade software.
.PARAMETER FilePath
    Full path or name of the executable (resolved by the OS PATH).
.PARAMETER ArgumentList
    Array of arguments passed to the executable. Each element is passed as a
    single argument via ProcessStartInfo.ArgumentList (not a joined string),
    so elements containing embedded spaces (paths, quoted pass-through flags)
    are not mis-split by the child process's command-line parser.
.PARAMETER TimeoutSeconds
    Maximum time to wait for the process before killing it. Default 600s (10 min).
.OUTPUTS
    [int] — process exit code (0 typically means success). Returns -1 if the
    process had to be killed after exceeding TimeoutSeconds.
#>
function Invoke-ExternalPackageCommand {
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)] [string]$FilePath,
        [Parameter(Mandatory)] [string[]]$ArgumentList,
        [Parameter()] [int]$TimeoutSeconds = 600
    )

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $FilePath
    foreach ($a in $ArgumentList) { $psi.ArgumentList.Add($a) }
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true

    $proc = [System.Diagnostics.Process]::new()
    $proc.StartInfo = $psi
    $proc.EnableRaisingEvents = $true

    $stdout = [System.Text.StringBuilder]::new()
    $stderr = [System.Text.StringBuilder]::new()
    $outEvent = Register-ObjectEvent -InputObject $proc -EventName OutputDataReceived -Action {
        if ($null -ne $Event.SourceEventArgs.Data) { $Event.MessageData.Append($Event.SourceEventArgs.Data) | Out-Null }
    } -MessageData $stdout
    $errEvent = Register-ObjectEvent -InputObject $proc -EventName ErrorDataReceived -Action {
        if ($null -ne $Event.SourceEventArgs.Data) { $Event.MessageData.Append($Event.SourceEventArgs.Data) | Out-Null }
    } -MessageData $stderr

    try {
        $null = $proc.Start()
        $proc.BeginOutputReadLine()
        $proc.BeginErrorReadLine()

        $exited = $proc.WaitForExit($TimeoutSeconds * 1000)
        if (-not $exited) {
            Write-Log -Level ERROR -Component CORE -Message "$FilePath timed out after ${TimeoutSeconds}s - killing process"
            try { $proc.Kill($true) } catch { Write-Log -Level WARN -Component CORE -Message "Failed to kill timed-out process: $_" }
            return -1
        }

        # WaitForExit(int) does not guarantee async output/error buffers are fully flushed;
        # the parameterless overload after it blocks until stream handlers have completed.
        $proc.WaitForExit()
        return $proc.ExitCode
    }
    finally {
        Unregister-Event -SourceIdentifier $outEvent.Name -ErrorAction SilentlyContinue
        Unregister-Event -SourceIdentifier $errEvent.Name -ErrorAction SilentlyContinue
        Remove-Job -Name $outEvent.Name -Force -ErrorAction SilentlyContinue
        Remove-Job -Name $errEvent.Name -Force -ErrorAction SilentlyContinue
    }
}

#endregion

#region ─── EXPORTS ───────────────────────────────────────────────────────────

Export-ModuleMember -Function @(
    'Initialize-Maintenance',
    'Write-Log',
    'Get-OSContext',
    'Get-MainConfig',
    'Get-BaselineList',
    'Get-TempPath',
    'Save-DiffList',
    'Get-DiffList',
    'New-ModuleResult',
    'Get-InstalledApp',
    'Get-WingetUpgrade',
    'Test-CommandAvailable',
    'Get-RegistryValue',
    'Set-RegistryValue',
    'Compare-RegistryBaseline',
    'Invoke-RegistryChangeItem',
    'Compare-ServiceBaseline',
    'Invoke-ServiceChangeItem',
    'Invoke-ExternalPackageCommand',
    'Invoke-AppxInWinPS',
    'Get-AppxPackageCompat',
    'Remove-AppxPackageCompat',
    'Get-AppxProvisionedPackageCompat',
    'Remove-AppxProvisionedPackageCompat'
)

#endregion
