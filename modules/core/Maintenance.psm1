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
Set-StrictMode -Off

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
            execution = @{ countdownSeconds = 30; enableDryRun = $false; autoSelectDefault = $true
                shutdown = @{ countdownSeconds = 120; rebootOnTimeout = $true; cleanupOnTimeout = $true }
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
.PARAMETER ModuleFolder
    Subfolder name under config/lists/ (e.g. 'bloatware').
.PARAMETER FileName
    JSON filename (e.g. 'bloatware-list.json').
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
        $obj = Get-Content -Path $path -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 20
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
    Produces a diff list by comparing Type1 scan results against a baseline.
.DESCRIPTION
    Strategies:
      Present  - items IN baseline that ARE found in scan (bloatware to remove)
      Missing  - items IN baseline that are NOT in scan (apps to install)
      Changed  - items where scanned state differs from desired state in baseline
.PARAMETER ScannedItems
    Array of objects returned by Type1 audit.
.PARAMETER BaselineItems
    Array/object from config/lists JSON.
.PARAMETER Strategy
    'Present' | 'Missing' | 'Changed'
.PARAMETER MatchProperty
    Property name to match on (default: 'Name').
.OUTPUTS
    Array of diff items (subset of scanned or baseline items).
#>
function Compare-ListDiff {
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [array]$ScannedItems,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [array]$BaselineItems,
        [Parameter(Mandatory)] [ValidateSet('Present', 'Missing', 'Changed')] [string]$Strategy,
        [Parameter()] [string]$MatchProperty = 'Name'
    )

    if ($null -eq $ScannedItems -or $ScannedItems.Count -eq 0) { return @() }
    if ($null -eq $BaselineItems -or $BaselineItems.Count -eq 0) { return @() }

    switch ($Strategy) {
        'Present' {
            # Items from baseline list that ARE present in scanned results (e.g. bloatware found)
            $scannedNames = $ScannedItems | ForEach-Object {
                if ($_ -is [string]) { $_ } else { $_.$MatchProperty }
            } | Where-Object { $_ } | ForEach-Object { $_.ToLowerInvariant() }

            return $BaselineItems | Where-Object {
                $bName = if ($_ -is [string]) { $_ } else { $_.$MatchProperty }
                $bName -and $scannedNames -contains $bName.ToLowerInvariant()
            }
        }
        'Missing' {
            # Items from baseline that are NOT present in scanned results (e.g. apps to install)
            $scannedNames = $ScannedItems | ForEach-Object {
                if ($_ -is [string]) { $_ } else { $_.$MatchProperty }
            } | Where-Object { $_ } | ForEach-Object { $_.ToLowerInvariant() }

            return $BaselineItems | Where-Object {
                $bName = if ($_ -is [string]) { $_ } else { $_.$MatchProperty }
                $bName -and $scannedNames -notcontains $bName.ToLowerInvariant()
            }
        }
        'Changed' {
            # Items where scanned state does not match desired state
            # Expects scanned items to have 'Name' and 'CurrentState'; baseline has 'name'/'desiredValue'
            $diff = [System.Collections.Generic.List[object]]::new()
            foreach ($baseItem in $BaselineItems) {
                $bName = if ($baseItem -is [string]) { $baseItem } else { $baseItem.$MatchProperty }
                if (-not $bName) { continue }
                $found = $ScannedItems | Where-Object {
                    ($_ -is [string] -and $_ -eq $bName) -or
                    ($_.$MatchProperty -and $_.$MatchProperty.Equals($bName, [System.StringComparison]::OrdinalIgnoreCase))
                } | Select-Object -First 1

                if ($found -and $found.PSObject.Properties['CurrentState'] -and $baseItem.PSObject.Properties['desiredValue']) {
                    if ($found.CurrentState -ne $baseItem.desiredValue) {
                        $diff.Add(@{
                                Name         = $bName
                                CurrentState = $found.CurrentState
                                DesiredState = $baseItem.desiredValue
                                Item         = $baseItem
                            })
                    }
                }
                elseif (-not $found) {
                    # Item is missing - assume it needs to be set to desired value
                    if ($baseItem.PSObject.Properties['desiredValue']) {
                        $diff.Add(@{
                                Name         = $bName
                                CurrentState = $null
                                DesiredState = $baseItem.desiredValue
                                Item         = $baseItem
                            })
                    }
                }
            }
            return $diff.ToArray()
        }
    }
}

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
    return $path
}

<#
.SYNOPSIS
    Loads a previously saved diff list. Returns empty array if not found.
#>
function Get-DiffList {
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)] [string]$ModuleName
    )

    $path = Get-TempPath -Category 'diff' -FileName "$ModuleName-diff.json"
    if (-not (Test-Path $path)) { return @() }
    try {
        $items = Get-Content -Path $path -Raw | ConvertFrom-Json -Depth 10
        if ($null -eq $items) { return @() }
        return @($items)
    }
    catch { return @() }
}

#endregion

#region ─── MODULE RESULT OBJECTS ─────────────────────────────────────────────

<#
.SYNOPSIS
    Creates a standardized module result hashtable used by the orchestrator.
#>
function New-ModuleResult {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)] [string]$ModuleName,
        [Parameter(Mandatory)] [ValidateSet('Success', 'Failed', 'Skipped', 'Warning')] [string]$Status,
        [Parameter()] [int]$ItemsDetected = 0,
        [Parameter()] [int]$ItemsProcessed = 0,
        [Parameter()] [int]$ItemsSkipped = 0,
        [Parameter()] [int]$ItemsFailed = 0,
        [Parameter()] [string]$Message = '',
        [Parameter()] [object[]]$Errors = @(),
        [Parameter()] [hashtable]$ExtraData = @{}
    )
    # Guard: SupportsShouldProcess satisfies PSUseShouldProcessForStateChangingFunctions for New-* verb.
    # New-ModuleResult only creates an in-memory hashtable; no system state is changed.
    if (-not $PSCmdlet.ShouldProcess($ModuleName, 'Create module result')) {
        return @{}
    }
    return @{
        ModuleName     = $ModuleName
        Status         = $Status
        Timestamp      = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        ItemsDetected  = $ItemsDetected
        ItemsProcessed = $ItemsProcessed
        ItemsSkipped   = $ItemsSkipped
        ItemsFailed    = $ItemsFailed
        Message        = $Message
        Errors         = $Errors
        ExtraData      = $ExtraData
    }
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

    # Add AppX / MSIX packages
    try {
        Get-AppxPackage -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -and $_.PackageFullName } |
        ForEach-Object {
            $appxApp = @{
                Name      = $_.Name
                Version   = $_.Version.ToString()
                Publisher = $_.Publisher
                Source    = 'AppX'
            }
            $apps.Add($appxApp)
        }
    }
    catch { Write-Verbose "AppX enumeration skipped: $_" }

    return $apps.ToArray()
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

    if (-not (Test-CommandAvailable 'winget')) { return @() }

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
        return $result.ToArray()
    }
    catch {
        Write-Log -Level WARN -Component CORE -Message "winget upgrade query failed: $_"
        return @()
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
    return ($null -ne (Get-Command $Command -ErrorAction SilentlyContinue))
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
    try {
        return Get-ItemPropertyValue -Path $Path -Name $Name -ErrorAction Stop
    }
    catch { return $null }
}

<#
.SYNOPSIS
    Sets or creates a registry value. Skips if value already correct.
.OUTPUTS
    bool - $true if a change was made.
#>
function Set-RegistryValue {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [string]$Name,
        [Parameter(Mandatory)] [object]$Value,
        [Parameter(Mandatory)] [string]$Type
    )

    $current = Get-RegistryValue -Path $Path -Name $Name
    if ($current -eq $Value) { return $false }

    if ($PSCmdlet.ShouldProcess("$Path\$Name", "Set to $Value")) {
        if (-not (Test-Path $Path)) {
            New-Item -Path $Path -Force | Out-Null
        }
        Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type -Force
        return $true
    }
    return $false
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
    'Compare-ListDiff',
    'Save-DiffList',
    'Get-DiffList',
    'New-ModuleResult',
    'Get-InstalledApp',
    'Get-WingetUpgrade',
    'Test-CommandAvailable',
    'Get-RegistryValue',
    'Set-RegistryValue'
)

#endregion
