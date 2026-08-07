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
.PARAMETER LogPath
    Optional explicit path for maintenance.log. When script.bat has already created and
    migrated the log (passed via $env:MAINTENANCE_LOG), the orchestrator supplies that path
    so both processes append to the SAME file. Defaults to temp_files\logs\maintenance.log.
#>
function Initialize-Maintenance {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectRoot,
        [string]$LogPath
    )
    $env:MAINT_ROOT = $ProjectRoot
    $env:MAINT_CONFIG = Join-Path $ProjectRoot 'config'
    $env:MAINT_MODULES = Join-Path $ProjectRoot 'modules'
    $env:MAINT_TEMP = Join-Path $ProjectRoot 'temp_files'
    $env:MAINT_LISTS = Join-Path $ProjectRoot 'config\lists'
    $env:MAINT_SETTINGS = Join-Path $ProjectRoot 'config\settings'

    # Guarantee all temp subdirectories exist. 'tools' holds externally downloaded binaries
    # (see Get-ExternalTool); it lives under temp_files so Stage 5 deletes it with the rest of
    # the extracted tree and it is already inside the Defender exclusion script.bat adds.
    foreach ($sub in 'data', 'logs', 'reports', 'diff', 'tools') {
        $dir = Join-Path $env:MAINT_TEMP $sub
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    }

    # Open the authoritative, auto-flushed maintenance.log (default levels; the
    # orchestrator re-applies configured levels after main-config.json loads).
    # Prefer the explicit path the launcher already created & migrated, else default.
    if (-not $LogPath) { $LogPath = Join-Path $env:MAINT_TEMP 'logs\maintenance.log' }
    Initialize-LogFile -Path $LogPath

    Write-Log -Level INFO -Component CORE -Message "Maintenance initialized. Root: $ProjectRoot"
}

#endregion

#region ─── LOGGING ───────────────────────────────────────────────────────────

# ── Logger state (module-scoped, persists for the imported module's lifetime) ──
# maintenance.log is written DIRECTLY here (auto-flushed), independent of any
# PowerShell transcript, so log lines survive crashes and the report-generation
# window. The transcript is only a raw sidecar (transcript.log).
$script:LevelRank = @{ DEBUG = 10; INFO = 20; SUCCESS = 20; WARN = 30; ERROR = 40; FATAL = 50 }
$script:LogConsoleRank = 20        # default console threshold = INFO (hides DEBUG)
$script:LogFileRank = 10           # default file threshold    = DEBUG (keeps everything)
$script:LogWriter = $null          # [System.IO.StreamWriter] once opened
$script:LogPath = $null

<#
.SYNOPSIS
    Opens (append) the authoritative maintenance.log for direct, auto-flushed writes.
.DESCRIPTION
    Uses a FileStream with FileShare.ReadWrite so the report generator can read the
    log while it is still held open. Safe to call more than once (re-opens).
.PARAMETER Path
    Full path to maintenance.log.
.PARAMETER ConsoleLevel / FileLevel
    Minimum level emitted to console / file. DEBUG|INFO|SUCCESS|WARN|ERROR|FATAL.
#>
function Initialize-LogFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Path,
        [string]$ConsoleLevel = 'INFO',
        [string]$FileLevel = 'DEBUG'
    )
    Close-LogFile
    try {
        $dir = Split-Path $Path -Parent
        if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $fs = [System.IO.FileStream]::new($Path, [System.IO.FileMode]::Append,
            [System.IO.FileAccess]::Write, [System.IO.FileShare]::ReadWrite)
        $sw = [System.IO.StreamWriter]::new($fs, [System.Text.UTF8Encoding]::new($false))
        $sw.AutoFlush = $true
        $script:LogWriter = $sw
        $script:LogPath = $Path
        Set-LogLevel -Console $ConsoleLevel -File $FileLevel
    }
    catch {
        $script:LogWriter = $null
        Write-Host "[WARN] Could not open log file '$Path': $_" -ForegroundColor Yellow
    }
}

<#
.SYNOPSIS
    Sets the console and/or file minimum log levels at runtime (e.g. from config).
#>
function Set-LogLevel {
    [CmdletBinding()]
    param([string]$Console, [string]$File)
    if ($Console -and $script:LevelRank.ContainsKey($Console.ToString().ToUpper())) {
        $script:LogConsoleRank = $script:LevelRank[$Console.ToString().ToUpper()]
    }
    if ($File -and $script:LevelRank.ContainsKey($File.ToString().ToUpper())) {
        $script:LogFileRank = $script:LevelRank[$File.ToString().ToUpper()]
    }
}

<#
.SYNOPSIS
    Writes a structured log line to the console (level-gated) and to maintenance.log.
.DESCRIPTION
    Format: [HH:mm:ss] [COMPONENT] [LEVEL] message
    Enhanced with visual symbols and color coding for better readability.
    Console output is gated by the console threshold (default INFO); the file always
    receives everything at/above the file threshold (default DEBUG) via a direct,
    auto-flushed write that does not depend on any transcript being active.
.PARAMETER Level
    DEBUG | INFO | SUCCESS | WARN | ERROR | FATAL
.PARAMETER Component
    Uppercase short module tag, e.g. BLOATWARE, CORE, CONFIG.
.PARAMETER Message
    Free-form message text.
.PARAMETER Indented
    If $true, indent the line for sub-items.
#>
function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('DEBUG', 'INFO', 'SUCCESS', 'WARN', 'ERROR', 'FATAL')]
        [string]$Level,

        [Parameter(Mandatory)]
        [string]$Component,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Message,

        [switch]$Indented
    )

    $rank = $script:LevelRank[$Level]
    $ts = (Get-Date).ToString('HH:mm:ss')

    # Log file format: [TIME] [COMPONENT] [LEVEL] message (same order as script.bat's LOG_MESSAGE)
    $logLine = "[$ts] [$Component] [$Level] $Message"

    # Console format with visual symbols
    $symbol, $color = switch ($Level) {
        'INFO'    { 'ℹ', 'Cyan' }
        'WARN'    { '⚠', 'Yellow' }
        'ERROR'   { '✗', 'Red' }
        'FATAL'   { '✗', 'Red' }
        'DEBUG'   { '◦', 'DarkGray' }
        'SUCCESS' { '✓', 'Green' }
        default   { '•', 'White' }
    }

    if ($rank -ge $script:LogConsoleRank) {
        $indent = if ($Indented) { '  ' } else { '' }
        $consoleLine = "$indent[$ts] $symbol [$Component] $Message"
        Write-Host $consoleLine -ForegroundColor $color
    }

    if ($script:LogWriter -and $rank -ge $script:LogFileRank) {
        try { $script:LogWriter.WriteLine($logLine) } catch { }
    }
}

<#
.SYNOPSIS
    Appends a verbatim (already-formatted) line to maintenance.log only.
.DESCRIPTION
    Used to fold pre-formatted external content (e.g. the launcher bootstrap log)
    into maintenance.log without re-wrapping it in another timestamp/level prefix.
#>
function Add-LogRaw {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [AllowEmptyString()] [string]$Text)
    if ($script:LogWriter) {
        try { $script:LogWriter.WriteLine($Text) } catch { }
    }
}

<#
.SYNOPSIS
    Logs a terminating error as FATAL with detailed context: exception type, message,
    position, stack trace, inner exceptions, and HResult for system errors.
    Enhanced with visual formatting for better readability.
.PARAMETER ErrorRecord
    The $_ / ErrorRecord from a catch block or trap.
.PARAMETER Component
    Component tag (default: ORCH)
.PARAMETER Message
    Custom message (default: 'Unhandled error')
.PARAMETER IncludeInnerExceptions
    If $true, logs all inner exceptions recursively (default: $true)
#>
function Write-LogException {
    [CmdletBinding()]
    param(
        [string]$Component = 'ORCH',
        [string]$Message = 'Unhandled error',
        [Parameter(Mandatory)] $ErrorRecord,
        [bool]$IncludeInnerExceptions = $true
    )

    # Main exception
    $exception = $ErrorRecord.Exception
    $exceptionType = $exception.GetType().FullName

    Write-Log -Level FATAL -Component $Component `
        -Message "$Message : [$exceptionType] $($exception.Message)"

    # HResult for system errors
    if ($exception.HResult) {
        Write-Log -Level FATAL -Component $Component -Message "  └─ HResult: 0x$($exception.HResult.ToString('X8'))" -Indented
    }

    # Position information
    if ($ErrorRecord.InvocationInfo -and $ErrorRecord.InvocationInfo.PositionMessage) {
        $pos = ($ErrorRecord.InvocationInfo.PositionMessage -replace "`r?`n", ' | ')
        Write-Log -Level FATAL -Component $Component -Message "  └─ At: $pos" -Indented
    }

    # Inner exceptions (recursive)
    if ($IncludeInnerExceptions -and $exception.InnerException) {
        $depth = 0
        $innerEx = $exception.InnerException
        while ($innerEx -and $depth -lt 5) {
            $innerType = $innerEx.GetType().FullName
            Write-Log -Level FATAL -Component $Component `
                -Message "  └─ InnerException[$depth]: [$innerType] $($innerEx.Message)" -Indented
            $innerEx = $innerEx.InnerException
            $depth++
        }
    }

    # Stack trace
    if ($ErrorRecord.ScriptStackTrace) {
        $i = 0
        foreach ($frame in ($ErrorRecord.ScriptStackTrace -split "`r?`n")) {
            if ($frame.Trim()) {
                Write-Log -Level FATAL -Component $Component -Message "  ├─ Stack[$i]: $frame" -Indented
                $i++
            }
        }
    }

    # Recent error history (DEBUG-level; file only under default thresholds)
    $i = 0
    foreach ($e in $Error) {
        if ($i -ge 5) { break }
        Write-Log -Level DEBUG -Component $Component -Message "  Error[$i]: $e" -Indented
        $i++
    }
}

<#
.SYNOPSIS
    Categorizes an exception for structured handling and logging.
.DESCRIPTION
    Analyzes exception type and provides category, severity, and suggested action.
    Categories: Permission, Timeout, Network, IO, Invalid, Unknown
.PARAMETER ErrorRecord
    The ErrorRecord to analyze.
.OUTPUTS
    [hashtable] with keys: Category, Severity, Message, Suggestion
#>
function Get-ExceptionCategory {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([Parameter(Mandatory)] $ErrorRecord)

    $exception = $ErrorRecord.Exception
    $exceptionType = $exception.GetType().Name
    $message = $exception.Message

    # Categorize by exception type
    $category = if ($exceptionType -match 'UnauthorizedAccess|AccessDenied|SecurityException') {
        'Permission'
    }
    elseif ($exceptionType -match 'TimeoutException|OperationCanceledException') {
        'Timeout'
    }
    elseif ($exceptionType -match 'IOException|FileNotFound|DirectoryNotFound') {
        'IO'
    }
    elseif ($exceptionType -match 'Net.Http|Net.WebException|TimeoutException') {
        'Network'
    }
    elseif ($exceptionType -match 'ArgumentException|ArgumentNullException|InvalidOperation') {
        'Invalid'
    }
    else {
        'Unknown'
    }

    # Suggest severity
    $severity = if ($category -in 'Permission', 'Network', 'IO') { 'High' } else { 'Medium' }

    # Suggest action
    $suggestion = switch ($category) {
        'Permission' { 'Verify permissions and elevation level' }
        'Timeout' { 'Retry operation or increase timeout' }
        'Network' { 'Check network connectivity and retry' }
        'IO' { 'Verify path exists and is accessible' }
        'Invalid' { 'Review input parameters and state' }
        default { 'Check error details and logs' }
    }

    return @{
        Category = $category
        Severity = $severity
        Message = $message
        Suggestion = $suggestion
        ExceptionType = $exceptionType
    }
}

<#
.SYNOPSIS
    Flushes and closes the maintenance.log writer. Idempotent — safe to call at
    every exit path and again in a finally block.
#>
function Close-LogFile {
    [CmdletBinding()]
    param()
    if ($script:LogWriter) {
        try { $script:LogWriter.Flush(); $script:LogWriter.Dispose() } catch { }
        $script:LogWriter = $null
    }
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
            logging   = @{ consoleLevel = 'INFO'; fileLevel = 'DEBUG' }
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
        [ValidateSet('data', 'logs', 'reports', 'diff', 'tools')]
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
    Compares registry baseline entries against the live registry and returns diff items.
.DESCRIPTION
    For each baseline entry ({ path, name, type, desiredValue, description }), reads the
    current value and emits a standardized diff item when it does not match the desired
    value (or is missing). The emitted items are consumed by Invoke-RegistryChangeItem.
    Used by audit (Type1) modules that harden/optimize via the registry.
.PARAMETER Entries
    Array of baseline registry entries. Each must expose 'path' and 'name'; 'type'
    defaults to 'DWord' and 'desiredValue' supplies the target value.
.OUTPUTS
    [hashtable[]] — diff items with Type='registry'. Empty array when all compliant.
#>
function Compare-RegistryBaseline {
    [CmdletBinding()]
    [OutputType([hashtable[]])]
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [array]$Entries
    )

    $diff = [System.Collections.Generic.List[hashtable]]::new()
    foreach ($entry in $Entries) {
        if (-not $entry) { continue }
        $path = $entry.path ?? $entry.Path
        $vname = $entry.name ?? $entry.Name
        if (-not $path -or -not $vname) { continue }

        $desired = $entry.desiredValue ?? $entry.DesiredValue
        $vtype = $entry.type ?? $entry.Type ?? 'DWord'
        $current = Get-RegistryValue -Path $path -Name $vname

        # A 'nonEmpty' baseline entry is satisfied by any non-empty value (e.g. legal
        # notice text): only flag it when the current value is missing/blank.
        $nonEmpty = [bool]($entry.nonEmpty ?? $entry.NonEmpty ?? $false)
        $isMismatch = if ($nonEmpty) {
            [string]::IsNullOrEmpty([string]$current)
        }
        else {
            "$current" -ne "$desired"
        }

        if ($isMismatch) {
            $diff.Add(@{
                    Type         = 'registry'
                    Name         = $vname
                    ValueName    = $vname
                    Path         = $path
                    DesiredValue = $desired
                    ValueType    = $vtype
                    CurrentState = $current
                    DesiredState = $desired
                    Description  = $entry.description ?? $entry.Description ?? $vname
                })
        }
    }
    return $diff.ToArray()
}

<#
.SYNOPSIS
    Compares service start-type against a desired action and returns diff items.
.PARAMETER ServiceNames
    Array of Windows service short names to evaluate.
.PARAMETER Action
    'EnsureDisabled' — flag services whose StartType is not Disabled.
    'EnsureRunning'  — flag services that are not set to Automatic / not running.
.OUTPUTS
    [hashtable[]] — diff items with Type='service'. Missing services are ignored.
#>
function Compare-ServiceBaseline {
    [CmdletBinding()]
    [OutputType([hashtable[]])]
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [string[]]$ServiceNames,
        [Parameter(Mandatory)] [ValidateSet('EnsureDisabled', 'EnsureRunning')] [string]$Action
    )

    $diff = [System.Collections.Generic.List[hashtable]]::new()
    foreach ($svcName in $ServiceNames) {
        if (-not $svcName) { continue }
        $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
        if (-not $svc) { continue }   # Not present on this SKU — nothing to do

        if ($Action -eq 'EnsureDisabled' -and $svc.StartType -ne 'Disabled') {
            $diff.Add(@{
                    Type             = 'service'
                    Name             = $svcName
                    ServiceName      = $svcName
                    DesiredStartType = 'Disabled'
                    CurrentState     = $svc.StartType.ToString()
                    DesiredState     = 'Disabled'
                })
        }
        elseif ($Action -eq 'EnsureRunning' -and ($svc.StartType -eq 'Disabled' -or $svc.Status -ne 'Running')) {
            $diff.Add(@{
                    Type             = 'service'
                    Name             = $svcName
                    ServiceName      = $svcName
                    DesiredStartType = 'Automatic'
                    CurrentState     = "$($svc.StartType)/$($svc.Status)"
                    DesiredState     = 'Automatic/Running'
                })
        }
    }
    return $diff.ToArray()
}

<#
.SYNOPSIS
    Applies a single registry diff item produced by Compare-RegistryBaseline.
.PARAMETER Item
    Diff item exposing Path, ValueName, DesiredValue, ValueType.
.PARAMETER Component
    Log component tag for the calling module.
.OUTPUTS
    [bool] — $true if a change was written, $false if already compliant.
#>
function Invoke-RegistryChangeItem {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)] [hashtable]$Item,
        [Parameter()] [string]$Component = 'CORE'
    )

    $path = $Item.Path ?? $Item.RegistryPath
    $vname = $Item.ValueName ?? $Item.Name
    $val = $Item.DesiredValue
    $vtype = $Item.ValueType ?? 'DWord'

    if (-not $path -or -not $vname -or $null -eq $val) {
        Write-Log -Level WARN -Component $Component -Message "Registry item incomplete, skipped: $($Item.Name)"
        return $false
    }

    $changed = Set-RegistryValue -Path $path -Name $vname -Value $val -Type $vtype
    if ($changed) {
        Write-Log -Level SUCCESS -Component $Component -Message "Registry set: $path\$vname = $val"
    }
    return $changed
}

<#
.SYNOPSIS
    Applies a single service diff item produced by Compare-ServiceBaseline.
.PARAMETER Item
    Diff item exposing ServiceName and DesiredStartType.
.PARAMETER Component
    Log component tag for the calling module.
.OUTPUTS
    [bool] — $true if the service start-type/state was changed.
#>
function Invoke-ServiceChangeItem {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)] [hashtable]$Item,
        [Parameter()] [string]$Component = 'CORE'
    )

    $svcName = $Item.ServiceName ?? $Item.Name
    $start = $Item.DesiredStartType ?? $Item.DesiredState ?? 'Disabled'
    if (-not $svcName) {
        Write-Log -Level WARN -Component $Component -Message 'Service item missing name, skipped'
        return $false
    }

    if ($start -eq 'Disabled') {
        Stop-Service -Name $svcName -Force -ErrorAction SilentlyContinue
        Set-Service -Name $svcName -StartupType Disabled -ErrorAction Stop
        Write-Log -Level SUCCESS -Component $Component -Message "Service '$svcName' -> Disabled"
    }
    else {
        Set-Service -Name $svcName -StartupType $start -ErrorAction Stop
        Start-Service -Name $svcName -ErrorAction SilentlyContinue
        Write-Log -Level SUCCESS -Component $Component -Message "Service '$svcName' -> $start"
    }
    return $true
}

#region ─── LOCAL SECURITY POLICY (secedit) ───────────────────────────────────

<#
.SYNOPSIS
    Reads the local [System Access] security policy via secedit /export.
.DESCRIPTION
    CIS password and account-lockout rules (benchmark sections 1.1 and 1.2) are NOT
    registry values - they live in the Local Security Policy database and are only
    reachable through secedit. That is why they cannot be expressed as registry entries
    in security-baseline.json, and why they were silently never applied before: the
    baseline declared a securityPolicy block that no module read.
    Requires elevation; returns an empty hashtable when it cannot export.
.OUTPUTS
    [hashtable] setting name -> raw string value.
#>
function Get-SecurityPolicyExport {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    $result = @{}
    $cfg = Join-Path ([System.IO.Path]::GetTempPath()) ("secpol-{0}.cfg" -f ([guid]::NewGuid().ToString('N')))
    try {
        $p = Start-Process -FilePath 'secedit.exe' `
            -ArgumentList @('/export', '/cfg', "`"$cfg`"", '/areas', 'SECURITYPOLICY', '/quiet') `
            -Wait -PassThru -WindowStyle Hidden -ErrorAction Stop
        if ($p.ExitCode -ne 0 -or -not (Test-Path $cfg)) {
            Write-Log -Level WARN -Component CORE -Message "secedit /export failed (exit $($p.ExitCode)) - security policy cannot be audited"
            return $result
        }
        # secedit writes UTF-16LE with a BOM; Get-Content detects it from the BOM.
        foreach ($line in (Get-Content -Path $cfg -ErrorAction Stop)) {
            if ($line -match '^\s*([A-Za-z][A-Za-z0-9_]*)\s*=\s*(.+?)\s*$') {
                $result[$Matches[1]] = $Matches[2]
            }
        }
    }
    catch {
        Write-Log -Level WARN -Component CORE -Message "Could not export security policy: $_"
    }
    finally {
        if (Test-Path $cfg) { Remove-Item $cfg -Force -ErrorAction SilentlyContinue }
    }
    return $result
}

<#
.SYNOPSIS
    Compares the live local security policy against the baseline's securityPolicy block.
.DESCRIPTION
    Only the numeric password/lockout settings are compared. Account-RENAMING entries
    (NewAdministratorName / NewGuestName) are deliberately ignored: renaming built-in
    accounts on an unattended personal machine is a surprising, hard-to-undo change that
    none of the supplied CIS checks actually test for.
.OUTPUTS
    [hashtable[]] diff items with Type = 'secpolicy'.
#>
function Compare-SecurityPolicyBaseline {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory)] [AllowNull()] $Baseline
    )

    $diff = [System.Collections.Generic.List[hashtable]]::new()
    if (-not $Baseline) { return $diff.ToArray() }

    # name -> comparison direction. CIS phrases these as "N or more" / "N or fewer".
    $rules = @{
        PasswordHistorySize   = 'AtLeast'
        MinimumPasswordAge    = 'AtLeast'
        MinimumPasswordLength = 'AtLeast'
        LockoutDuration       = 'AtLeast'
        ResetLockoutCount     = 'AtLeast'
        LockoutBadCount       = 'AtMostNonZero'
    }

    $current = Get-SecurityPolicyExport
    if ($current.Count -eq 0) { return $diff.ToArray() }

    foreach ($name in $rules.Keys) {
        if (-not $Baseline.ContainsKey($name)) { continue }
        $desired = [int]$Baseline[$name]
        $rawCur = $current[$name]
        $curVal = 0
        $haveCur = [int]::TryParse($rawCur, [ref]$curVal)

        $compliant = $false
        if ($haveCur) {
            switch ($rules[$name]) {
                'AtLeast' { $compliant = ($curVal -ge $desired) }
                # "5 or fewer, but not 0" - 0 disables lockout entirely and fails the benchmark.
                'AtMostNonZero' { $compliant = ($curVal -le $desired -and $curVal -gt 0) }
            }
        }
        if ($compliant) { continue }

        $diff.Add(@{
                Type         = 'secpolicy'
                Name         = $name
                SettingName  = $name
                CurrentState = $(if ($haveCur) { "$curVal" } else { '<unset>' })
                DesiredState = "$desired"
                DesiredValue = $desired
                Description  = "Local security policy $name -> $desired"
            })
    }

    return $diff.ToArray()
}

<#
.SYNOPSIS
    Applies one local-security-policy diff item through secedit /configure.
.DESCRIPTION
    Writes a minimal UTF-16LE INF containing only the [System Access] key being changed -
    secedit applies exactly what the file contains, so this stays surgical instead of
    re-imposing a whole exported policy. Uses a throwaway .sdb so the system database is
    not rewritten.
.OUTPUTS
    [bool] $true when secedit reported success.
#>
function Invoke-SecurityPolicyChangeItem {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)] [hashtable]$Item,
        [Parameter()] [string]$Component = 'CORE'
    )

    $name = $Item.SettingName ?? $Item.Name
    $value = $Item.DesiredValue
    if (-not $name -or $null -eq $value) {
        Write-Log -Level WARN -Component $Component -Message 'Security policy item incomplete, skipped'
        return $false
    }

    $stamp = [guid]::NewGuid().ToString('N')
    $inf = Join-Path ([System.IO.Path]::GetTempPath()) "secpol-$stamp.inf"
    $sdb = Join-Path ([System.IO.Path]::GetTempPath()) "secpol-$stamp.sdb"
    try {
        $body = @(
            '[Unicode]'
            'Unicode=yes'
            '[Version]'
            'signature="$CHICAGO$"'
            'Revision=1'
            '[System Access]'
            "$name = $value"
        ) -join "`r`n"
        # secedit requires UTF-16LE when the INF declares Unicode=yes.
        [System.IO.File]::WriteAllText($inf, $body, [System.Text.UnicodeEncoding]::new($false, $true))

        $p = Start-Process -FilePath 'secedit.exe' `
            -ArgumentList @('/configure', '/db', "`"$sdb`"", '/cfg', "`"$inf`"", '/areas', 'SECURITYPOLICY', '/quiet') `
            -Wait -PassThru -WindowStyle Hidden -ErrorAction Stop

        if ($p.ExitCode -eq 0) {
            Write-Log -Level SUCCESS -Component $Component -Message "Security policy: $name -> $value"
            return $true
        }
        Write-Log -Level WARN -Component $Component -Message "secedit /configure returned exit $($p.ExitCode) for $name"
        return $false
    }
    catch {
        Write-Log -Level ERROR -Component $Component -Message "Security policy change failed for ${name}: $_"
        return $false
    }
    finally {
        foreach ($f in $inf, $sdb) { if (Test-Path $f) { Remove-Item $f -Force -ErrorAction SilentlyContinue } }
    }
}

#endregion

#region ─── ADVANCED AUDIT POLICY (auditpol) ──────────────────────────────────

<#
.SYNOPSIS
    Compares advanced audit policy subcategories against the baseline's auditPolicy block.
.DESCRIPTION
    Like the password policy, CIS section 17 is not registry-backed - it is the advanced
    audit policy, readable and writable only through auditpol.exe. The baseline listed all
    18 subcategories but nothing consumed them.

    NOTE: these subcategory settings only take effect when
    HKLM\System\CurrentControlSet\Control\Lsa\SCENoApplyLegacyAuditPolicy = 1, otherwise
    legacy category-level policy overrides them. That registry value is part of the same
    baseline for exactly this reason.
.OUTPUTS
    [hashtable[]] diff items with Type = 'auditpolicy'.
#>
function Compare-AuditPolicyBaseline {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory)] [AllowNull()] $Baseline
    )

    $diff = [System.Collections.Generic.List[hashtable]]::new()
    if (-not $Baseline) { return $diff.ToArray() }

    foreach ($entry in @($Baseline)) {
        $sub = $entry.subcategory
        if (-not $sub) { continue }
        $wantSuccess = [bool]$entry.success
        $wantFailure = [bool]$entry.failure

        $curSuccess = $false; $curFailure = $false; $known = $false
        try {
            # /r emits CSV: Machine Name,Policy Target,Subcategory,Subcategory GUID,Inclusion Setting,...
            $raw = & auditpol.exe /get /subcategory:"$sub" /r 2>&1
            if ($LASTEXITCODE -eq 0) {
                $row = @($raw | Where-Object { $_ -match [regex]::Escape($sub) }) | Select-Object -First 1
                if ($row) {
                    $cols = $row -split ','
                    if ($cols.Count -ge 5) {
                        $setting = $cols[4].Trim()
                        # English inclusion-setting strings. On a localised Windows this will not
                        # match, $known stays false, and the item is queued anyway - auditpol /set
                        # is idempotent, so re-applying a already-correct setting is harmless.
                        if ($setting -match '^(Success and Failure|Success|Failure|No Auditing)$') {
                            $known = $true
                            $curSuccess = $setting -in 'Success', 'Success and Failure'
                            $curFailure = $setting -in 'Failure', 'Success and Failure'
                        }
                    }
                }
            }
        }
        catch {
            Write-Log -Level DEBUG -Component CORE -Message "auditpol query failed for '$sub': $_"
        }

        if ($known -and $curSuccess -eq $wantSuccess -and $curFailure -eq $wantFailure) { continue }

        $desired = if ($wantSuccess -and $wantFailure) { 'Success and Failure' }
        elseif ($wantSuccess) { 'Success' }
        elseif ($wantFailure) { 'Failure' }
        else { 'No Auditing' }

        $diff.Add(@{
                Type         = 'auditpolicy'
                Name         = "Audit: $sub"
                Subcategory  = $sub
                WantSuccess  = $wantSuccess
                WantFailure  = $wantFailure
                CIS          = $entry.cis
                CurrentState = $(if ($known) { "Success=$curSuccess,Failure=$curFailure" } else { '<unreadable>' })
                DesiredState = $desired
                Description  = "Audit subcategory '$sub' -> $desired"
            })
    }

    return $diff.ToArray()
}

<#
.SYNOPSIS
    Applies one advanced-audit-policy diff item through auditpol /set.
.OUTPUTS
    [bool] $true when auditpol reported success.
#>
function Invoke-AuditPolicyChangeItem {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)] [hashtable]$Item,
        [Parameter()] [string]$Component = 'CORE'
    )

    $sub = $Item.Subcategory
    if (-not $sub) {
        Write-Log -Level WARN -Component $Component -Message 'Audit policy item missing Subcategory, skipped'
        return $false
    }
    $succ = if ($Item.WantSuccess) { 'enable' } else { 'disable' }
    $fail = if ($Item.WantFailure) { 'enable' } else { 'disable' }

    try {
        $null = & auditpol.exe /set /subcategory:"$sub" /success:$succ /failure:$fail 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Log -Level SUCCESS -Component $Component -Message "Audit policy '$sub' -> success:$succ failure:$fail"
            return $true
        }
        Write-Log -Level WARN -Component $Component -Message "auditpol /set returned exit $LASTEXITCODE for '$sub'"
        return $false
    }
    catch {
        Write-Log -Level ERROR -Component $Component -Message "Audit policy change failed for '$sub': $_"
        return $false
    }
}

#endregion

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
    # `,@()` for the same unrolling reason as below: a bare `return @()` yields $null to the
    # caller, so Get-DiffList would sometimes hand back $null and sometimes an array. Always
    # returning a real array keeps the Type2 contract uniform.
    if (-not (Test-Path $path)) { return , @() }
    try {
        # -AsHashtable: keeps diff items as [hashtable] for uniform access.
        # Type1 modules save hashtable arrays via Save-DiffList;
        # Type2 modules consume them — both sides now use the same type.
        $items = Get-Content -Path $path -Raw | ConvertFrom-Json -Depth 10 -AsHashtable
        if ($null -eq $items) { return , @() }
        # `,` (array-wrap) is REQUIRED. PowerShell unrolls a single-element array on return,
        # so `return @($items)` handed back the bare hashtable whenever the diff held exactly
        # ONE item. Callers then read $diff.Count as the item's KEY COUNT (e.g. 5) instead of
        # 1 - corrupting every "N item(s)" log line, ItemsDetected in the module result, and
        # the report's diff table (which indexes $diffData[0..n] and got $null rows).
        # ConvertTo-Json also serialises a 1-element array as a bare JSON OBJECT, so this is
        # the single point where both collapses have to be undone.
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
    PS7-safe wrapper for Remove-AppxPackage. Returns $true only when the package is
    VERIFIED gone afterwards.
.PARAMETER PackageFullName
    Full name of the package to remove.
.PARAMETER AllUsers
    Remove for all user accounts.
.OUTPUTS
    [bool] $true if the package is no longer present, $false otherwise.
#>
function Remove-AppxPackageCompat {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$PackageFullName,
        [switch]$AllUsers
    )

    # Return value is VERIFIED against the live AppX list inside the SAME child process, never
    # assumed - exactly like Remove-AppxProvisionedPackageCompat below, and for the same reason:
    # Invoke-AppxInWinPS shells out to powershell.exe with 2>$null, so a failing CHILD PROCESS
    # raises no PowerShell exception here and '-ErrorAction SilentlyContinue' discards the error
    # inside the child too. This function used to return nothing at all, so Layer 1 of
    # Remove-BloatwareLayered declared success merely because Get-AppxPackageCompat had FOUND a
    # package - printing "[OK] Removed AppX" for packages that were still fully installed, and
    # (worse) setting its $removed flag, which SKIPPED the winget-by-exact-Id layer that would
    # actually have removed them. Verifying in-process also avoids a second powershell.exe launch
    # per package.
    $allUsersArg = if ($AllUsers) { ' -AllUsers' } else { '' }
    $cmd = @"
`$ErrorActionPreference = 'SilentlyContinue'
Get-AppxPackage -AllUsers | Where-Object { `$_.PackageFullName -eq '$PackageFullName' } | Remove-AppxPackage$allUsersArg
`$still = Get-AppxPackage -AllUsers | Where-Object { `$_.PackageFullName -eq '$PackageFullName' }
if (`$still) { 'APPX_PRESENT' } else { 'APPX_REMOVED' }
"@

    $out = Invoke-AppxInWinPS -ScriptBlock $cmd
    # Absent output means the child process died before printing a sentinel - treat as failure
    # rather than success, so callers fall through to their next removal layer.
    return ([bool](@($out) -contains 'APPX_REMOVED'))
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

    $result = [System.Collections.Generic.List[hashtable]]::new()

    # Try PowerShell method first (PS5.1 via AppX module).
    # -Online is MANDATORY: without it the cmdlet cannot bind a parameter set at all and
    # fails with "Parameter set cannot be resolved using the specified named parameters",
    # so this path silently produced nothing and every call fell through to DISM below.
    try {
        $cmd = 'Get-AppxProvisionedPackage -Online -ErrorAction Stop | Select-Object PackageName, DisplayName'
        $raw = Invoke-AppxInWinPS -ScriptBlock $cmd
        if ($raw) {
            @($raw) | ForEach-Object {
                $result.Add(@{ PackageName = $_.PackageName; DisplayName = $_.DisplayName })
            }
            return $result.ToArray()
        }
    }
    catch { Write-Verbose "AppX PowerShell method failed: $_" }

    # Fallback: DISM (more reliable, works on all SKUs)
    try {
        $dismExe = Join-Path $env:SystemRoot 'System32\dism.exe'
        $output = & $dismExe /Online /Get-ProvisionedAppxPackages 2>&1 | Where-Object { $_ -is [string] }

        # DISM emits DisplayName BEFORE PackageName within each record:
        #     DisplayName  : Microsoft.BingNews
        #     Version      : ...
        #     PackageName  : Microsoft.BingNews_2019.616.2027.0_neutral_~_8wekyb3d8bbwe
        # The previous parser required PackageName FIRST and only then accepted a DisplayName,
        # which silently produced MISALIGNED records: the first DisplayName was discarded and
        # every later DisplayName was paired with the PREVIOUS record's PackageName. That was
        # invisible while only PackageName was consumed, but callers now match on DisplayName,
        # so the pairing has to be right. Latch DisplayName, then emit the record when its
        # PackageName arrives.
        $pendingDisplayName = $null
        foreach ($line in $output) {
            if ($line -match '^\s*DisplayName\s*:\s*(.+)$') {
                $pendingDisplayName = $Matches[1].Trim()
            }
            elseif ($line -match '^\s*PackageName\s*:\s*(.+)$') {
                $result.Add(@{ PackageName = $Matches[1].Trim(); DisplayName = $pendingDisplayName })
                $pendingDisplayName = $null
            }
        }
        if ($result.Count -gt 0) { return $result.ToArray() }
    }
    catch { Write-Verbose "DISM fallback failed: $_" }

    return @()
}

<#
.SYNOPSIS
    PS7-safe wrapper for Remove-AppxProvisionedPackage with DISM fallback.
.PARAMETER PackageName
    The provisioned package name to remove.
#>
function Remove-AppxProvisionedPackageCompat {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$PackageName
    )

    # Return value is VERIFIED against the live provisioned list, never assumed.
    #
    # This function used to `return $true` immediately after invoking the PS path. Two
    # things made that a guaranteed false positive:
    #   1. The command omitted -Online, so Get/Remove-AppxProvisionedPackage could not even
    #      bind a parameter set ("Parameter set cannot be resolved") and removed nothing.
    #   2. Invoke-AppxInWinPS shells out to powershell.exe with 2>$null; a failing CHILD
    #      PROCESS does not raise a PowerShell exception, so the catch never fired.
    # Callers therefore logged "Removed Provisioned" for packages that were still fully
    # provisioned AND still installed, and the correct DISM fallback below was dead code.
    $stillProvisioned = {
        $current = Get-AppxProvisionedPackageCompat -ErrorAction SilentlyContinue
        return [bool](@($current) | Where-Object { $_.PackageName -eq $PackageName })
    }

    # Attempt 1: PS5.1 AppX module (needs -Online, and elevation).
    try {
        $cmd = "Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | " +
        "Where-Object { `$_.PackageName -eq '$PackageName' } | " +
        "Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue"
        Invoke-AppxInWinPS -ScriptBlock $cmd
    }
    catch { Write-Verbose "PowerShell provisioned removal failed: $_" }

    if (-not (& $stillProvisioned)) { return $true }

    # Attempt 2: DISM (works on SKUs/contexts where the AppX module misbehaves).
    try {
        $dismExe = Join-Path $env:SystemRoot 'System32\dism.exe'
        $null = & $dismExe /Online /Remove-ProvisionedAppxPackage /PackageName:"$PackageName" /Quiet /NoRestart 2>&1
    }
    catch { Write-Verbose "DISM provisioned removal failed: $_" }

    return (-not (& $stillProvisioned))
}

#endregion

#region ─── SHARED SYSTEM QUERIES ─────────────────────────────────────────────

<#
.SYNOPSIS
    Detects whether Windows has a pending reboot from Component Based Servicing (CBS) or
    Windows Update, which blocks operations like DISM /StartComponentCleanup.
.DESCRIPTION
    DISM's component-store cleanup fails with 0x800F0806 ("the operation could not be
    completed due to pending operations") whenever a prior servicing operation - most
    commonly a .NET Framework update - is waiting for a reboot to finish applying. Retrying
    the same cleanup without rebooting just repeats the same failure every run. This checks
    the well-known registry indicators for that state so a caller can skip the attempt
    entirely and signal RebootRequired instead of logging a hard error for a condition a
    reboot (handled centrally at Stage 5, per the operating contract - modules never reboot
    themselves) will resolve on its own.
.OUTPUTS
    [bool] $true if a reboot is pending for any of these reasons.
#>
function Test-CbsRebootPending {
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    $indicators = @(
        @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'; Kind = 'KeyExists' }
        @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootInProgress'; Kind = 'KeyExists' }
        @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\PackagesPending'; Kind = 'HasSubkeys' }
        @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'; Kind = 'KeyExists' }
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager'; Kind = 'ValueExists'; Name = 'PendingFileRenameOperations' }
    )

    foreach ($indicator in $indicators) {
        try {
            switch ($indicator.Kind) {
                'KeyExists' {
                    if (Test-Path -Path $indicator.Path -ErrorAction SilentlyContinue) { return $true }
                }
                'HasSubkeys' {
                    if (Test-Path -Path $indicator.Path -ErrorAction SilentlyContinue) {
                        if (@(Get-ChildItem -Path $indicator.Path -ErrorAction SilentlyContinue).Count -gt 0) { return $true }
                    }
                }
                'ValueExists' {
                    $val = (Get-ItemProperty -Path $indicator.Path -Name $indicator.Name -ErrorAction SilentlyContinue).($indicator.Name)
                    if ($val) { return $true }
                }
            }
        }
        catch {
            Write-Log -Level DEBUG -Component CORE -Message "Reboot-pending indicator check failed for $($indicator.Path): $_"
        }
    }

    return $false
}

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
        $wingetExe = Resolve-WingetPath
        $raw = & $wingetExe upgrade --include-unknown 2>&1 | Where-Object { $_ -is [string] }
        $result = [System.Collections.Generic.List[hashtable]]::new()

        # winget has no machine-readable output for this command (confirmed against current
        # winget CLI docs - no --output/-o option exists for 'upgrade' or 'list' as of mid-2026),
        # so the fixed-width table has to be parsed. Capture the HEADER row's column count (the
        # line immediately before the '----' divider) and require each data row's split to fall
        # within [4, headerCols] - too few means a wrapped/misaligned row, too many means the
        # split caught a double-space inside a single field (e.g. a name like "App  Name") rather
        # than a real column boundary.
        $inTable = $false
        $headerCols = 0
        $prevLine = $null
        foreach ($line in $raw) {
            if ($line -match '^-+') {
                $inTable = $true
                if ($prevLine) { $headerCols = @($prevLine -split '\s{2,}').Count }
                continue
            }
            if (-not $inTable) { $prevLine = $line; continue }
            if ($line -match '^\s*$') { continue }

            $parts = @($line -split '\s{2,}')
            if ($parts.Count -ge 4 -and ($headerCols -eq 0 -or $parts.Count -le $headerCols) -and $parts[0].Trim()) {
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

$script:ResolvedWingetPath = $null

<#
.SYNOPSIS
    Resolves and caches the most reliable winget.exe path for this session.
.DESCRIPTION
    Prefers the REAL, machine-wide winget.exe under Program Files\WindowsApps over the
    per-user WindowsApps App Execution Alias stub (…\Microsoft\WindowsApps\winget.exe).
    The alias is a reparse-point activation shim for the packaged app, and is a
    well-documented source of unreliable/failing invocations when the calling process is
    ELEVATED (as this project's orchestrator always is, #Requires -RunAsAdministrator) -
    the alias's packaged-app activation depends on per-user context an elevated token
    doesn't consistently carry, whereas the real exe under Program Files is a normal PE
    any elevated process can launch directly.
    Each candidate is VALIDATED by actually running `--version` before being trusted, so
    this can never behave worse than the previous bare 'winget' PATH lookup - it only
    upgrades to a better-resolved path when one is proven to work.
.OUTPUTS
    [string] - a winget.exe path (or literal 'winget' as a last-resort fallback) that
    has been confirmed runnable in this session.
#>
function Resolve-WingetPath {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    if ($script:ResolvedWingetPath) { return $script:ResolvedWingetPath }

    $candidates = [System.Collections.Generic.List[string]]::new()
    $realExe = Get-Item -Path (Join-Path $env:ProgramFiles 'WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe') `
        -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($realExe) { $candidates.Add($realExe.FullName) }
    $candidates.Add((Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\winget.exe'))
    $candidates.Add('winget')   # last resort: today's PATH-based resolution

    foreach ($cand in $candidates) {
        try {
            if ($cand -ne 'winget' -and -not (Test-Path -Path $cand -ErrorAction SilentlyContinue)) { continue }
            $null = & $cand --version 2>$null
            if ($LASTEXITCODE -eq 0) {
                $script:ResolvedWingetPath = $cand
                Write-Log -Level DEBUG -Component CORE -Message "Resolved winget to: $cand"
                return $cand
            }
        }
        catch { Write-Log -Level DEBUG -Component CORE -Message "winget candidate failed validation ($cand): $_" }
    }

    Write-Log -Level WARN -Component CORE -Message 'No winget.exe candidate validated - falling back to bare "winget" (PATH resolution)'
    $script:ResolvedWingetPath = 'winget'
    return 'winget'
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
    Sets or creates a registry value. Skips if value already correct.
.OUTPUTS
    bool - $true if a change was made.
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
    if ($current -eq $Value) { return $false }

    if (-not (Test-Path $Path)) {
        New-Item -Path $Path -Force | Out-Null
    }
    Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type -Force
    return $true
}

#endregion

#region ─── EXTERNAL PROCESS HELPER ───────────────────────────────────────────

<#
.SYNOPSIS
    Runs an external executable (e.g. winget, choco, dism) and returns its exit code.
.DESCRIPTION
    Wraps System.Diagnostics.Process for silent, non-interactive external command
    execution. Captures stdout/stderr so they don't pollute the console and returns
    only the integer exit code.

    Two deliberate implementation details:

    * BOTH pipes are drained ASYNCHRONOUSLY (ReadToEndAsync) before waiting. A
      sequential `StandardOutput.ReadToEnd()` then `StandardError.ReadToEnd()` can
      deadlock: if the child fills the stderr pipe buffer (~4KB) while we are blocked
      reading stdout, neither side can progress. Verbose winget/DISM output reaches
      that easily.
    * WaitForExit takes a TIMEOUT and the process tree is killed if it elapses, so a
      hung package manager can never hang the whole maintenance run.
.PARAMETER FilePath
    Full path or name of the executable (resolved by the OS PATH).
.PARAMETER ArgumentList
    Array of arguments passed to the executable.
.PARAMETER TimeoutSeconds
    Max seconds to wait before killing the process tree. Default 600. Pass 0 (or a
    negative value) to wait indefinitely. Long operations should pass an explicit
    value (e.g. DISM component cleanup uses 1800).
.OUTPUTS
    [int] — process exit code (0 typically means success); -1 if the call timed out
    and the process tree was killed.
#>
function Invoke-ExternalPackageCommand {
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)] [string]$FilePath,
        [Parameter(Mandatory)] [string[]]$ArgumentList,
        [int]$TimeoutSeconds = 600
    )

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $FilePath
    $psi.Arguments = $ArgumentList -join ' '
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true

    $proc = [System.Diagnostics.Process]::new()
    $proc.StartInfo = $psi
    try {
        try {
            $null = $proc.Start()
        }
        catch {
            Write-Log -Level ERROR -Component CORE `
                -Message "Failed to start process '$FilePath': $($_.Exception.Message)"
            return -2147483648
        }

        # Start draining both pipes before waiting - see deadlock note above.
        $outTask = $proc.StandardOutput.ReadToEndAsync()
        $errTask = $proc.StandardError.ReadToEndAsync()

        $exited = if ($TimeoutSeconds -gt 0) {
            $proc.WaitForExit([int][Math]::Min($TimeoutSeconds * 1000L, [int]::MaxValue))
        }
        else {
            $proc.WaitForExit(); $true
        }

        if (-not $exited) {
            try { $proc.Kill($true) } catch { try { $proc.Kill() } catch { } }
            Write-Log -Level WARN -Component CORE `
                -Message "Timed out after ${TimeoutSeconds}s, process tree killed: $FilePath $($ArgumentList -join ' ')"
            return -1
        }

        # Reap the readers so the pipes are fully consumed before we read ExitCode. Capture
        # (rather than discard) the text: on a non-zero exit this is the only place that
        # ever sees WHY the external command failed - every call site only gets the bare
        # int back, so without this a failure like winget returning 0x8A15003A leaves no
        # trace beyond an opaque negative number in the log.
        $outText = $null; $errText = $null
        try { $outText = $outTask.GetAwaiter().GetResult() } catch { }
        try { $errText = $errTask.GetAwaiter().GetResult() } catch { }

        if ($proc.ExitCode -ne 0) {
            $detail = @($errText, $outText) | Where-Object { $_ -and $_.Trim() } | Select-Object -First 1
            if ($detail) {
                $detail = $detail.Trim()
                if ($detail.Length -gt 600) { $detail = $detail.Substring(0, 600) + '...' }
                Write-Log -Level WARN -Component CORE -Message "$FilePath exited $($proc.ExitCode): $detail"
            }
        }

        return $proc.ExitCode
    }
    finally {
        $proc.Dispose()
    }
}

#endregion

#region ─── EXTERNAL TOOL ACQUISITION ─────────────────────────────────────────
# Downloads a self-contained third-party binary at runtime, verifies it, and hands back a
# path. Built for the Sysinternals tools (see Sysinternals_Suite_Reference.md), but nothing
# here is Sysinternals-specific.
#
# WHY RUNTIME DOWNLOAD RATHER THAN VENDORING THE BINARIES:
#   - The Sysinternals licence forbids "publishing the software for others to copy". This
#     repo's whole delivery mechanism is "anyone downloads master.zip", so committing the
#     .exe files would be exactly that. Each machine fetches its own copy from Microsoft.
#   - winget is the WRONG channel for these. Microsoft.Sysinternals.Suite resolves to the
#     Store MSIX: per-user install, app-execution-alias reparse points under %LOCALAPPDATA%,
#     invisible to SYSTEM, and a fail-fast 0xC0000409 crash under redirected stdio - the
#     exact trap Install-SysmonWithConfig already works around. Sysmon works via winget only
#     because installing it produces a SERVICE whose binary lands in %windir%.
#
# Nothing here may ever be a hard dependency: every caller must tolerate $null and degrade to
# Warning, the same rule winget already lives under.

<#
.SYNOPSIS
    Accepts the Sysinternals EULA non-interactively for both the current user and SYSTEM.
.DESCRIPTION
    On first run a Sysinternals tool pops a MODAL GUI licence dialog. Under the monthly SYSTEM
    task there is no desktop to show it on, so the process just sits there until the timeout
    kills it - precisely the "blocks waiting for a human" failure the operating contract
    forbids.

    Belt and braces, because neither mechanism alone is sufficient:
      - Most tools accept -accepteula, but the Learn parameter tables are inconsistent about
        documenting it and a few ignore it. Callers should still pass it.
      - The registry flag covers the rest.

    Both HKCU and HKU\S-1-5-18 are written. When running as SYSTEM, HKCU *is* S-1-5-18 (and
    HKU\.DEFAULT is an alias for the same hive), so writing HKCU alone would seed the wrong
    hive during an interactive admin run and leave the scheduled run unseeded.

    Note this registry write is a MONITORED behaviour - published Sigma rules watch
    ...\Sysinternals\*\EulaAccepted because attackers set it for renamed tools. Ours is benign
    and under our own filename, but expect it to show up in EDR telemetry and in our own
    Sysmon registry events.
.OUTPUTS
    [bool] $true when at least one hive was seeded.
#>
function Initialize-SysinternalsEula {
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    $ok = $false
    foreach ($root in 'HKCU:\Software\Sysinternals', 'Registry::HKEY_USERS\S-1-5-18\Software\Sysinternals') {
        try {
            if (-not (Test-Path -LiteralPath $root)) {
                $null = New-Item -Path $root -Force -ErrorAction Stop
            }
            Set-ItemProperty -LiteralPath $root -Name 'EulaAccepted' -Value 1 -Type DWord -Force -ErrorAction Stop
            $ok = $true
        }
        catch {
            # SYSTEM's hive is not always reachable from an interactive session and vice versa.
            Write-Log -Level DEBUG -Component TOOLS -Message "Could not seed Sysinternals EULA at ${root}: $_"
        }
    }
    if ($ok) { Write-Log -Level DEBUG -Component TOOLS -Message 'Sysinternals EULA pre-accepted' }
    return $ok
}

<#
.SYNOPSIS
    Verifies a downloaded binary carries a valid Microsoft Authenticode signature.
.DESCRIPTION
    The binary arrives over the network at runtime, so it is checked before it is executed.
    This is PowerShell-native, so there is no bootstrapping problem.
.OUTPUTS
    [bool] $true only when the signature is Valid AND the signer is Microsoft.
#>
function Test-MicrosoftSignedBinary {
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)] [string]$Path)

    try {
        $sig = Get-AuthenticodeSignature -LiteralPath $Path -ErrorAction Stop
    }
    catch {
        Write-Log -Level WARN -Component TOOLS -Message "Signature check failed for ${Path}: $_"
        return $false
    }
    if ($sig.Status -ne 'Valid') {
        Write-Log -Level WARN -Component TOOLS -Message "Rejected (signature $($sig.Status)): $Path"
        return $false
    }
    if ($sig.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation') {
        Write-Log -Level WARN -Component TOOLS -Message "Rejected (not Microsoft-signed): $Path"
        return $false
    }
    return $true
}

<#
.SYNOPSIS
    Resolves an already-extracted tool executable, preferring the 64-bit build.
.DESCRIPTION
    The unpackaged Sysinternals downloads ship both architectures side by side
    (handle.exe + handle64.exe). Prefer the 64-bit build, same shape as the Sysmon binary
    resolution in SystemConfiguration.psm1.
.OUTPUTS
    [string] full path, or $null when neither form is present.
#>
function Resolve-ExternalToolPath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [string]$BaseName,
        [Parameter(Mandatory)] [string]$Directory
    )

    foreach ($candidate in "$BaseName`64.exe", "$BaseName.exe") {
        $p = Join-Path $Directory $candidate
        if (Test-Path -LiteralPath $p -PathType Leaf) { return $p }
    }
    return $null
}

<#
.SYNOPSIS
    Downloads, extracts and verifies an external tool; returns its path or $null.
.DESCRIPTION
    Idempotent within a run: if the executable is already present in temp_files/tools it is
    returned without re-downloading.

    BEST-EFFORT BY CONTRACT. Returns $null on any failure - no network, bad zip, missing
    binary, failed signature check. The caller MUST handle $null and degrade to Warning; a
    tool download can never fail the run.
.PARAMETER Name
    Base name of the executable WITHOUT extension or architecture suffix, e.g. 'handle'.
.PARAMETER Url
    Zip to download, e.g. https://download.sysinternals.com/files/Handle.zip
.PARAMETER SkipSignatureCheck
    Escape hatch for a non-Microsoft tool. Off by default and should stay off.
.OUTPUTS
    [string] full path to the verified executable, or $null.
#>
function Get-ExternalTool {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [string]$Name,
        [Parameter(Mandatory)] [string]$Url,
        [Parameter()] [switch]$SkipSignatureCheck,
        [Parameter()] [int]$TimeoutSeconds = 120
    )

    try {
        $toolDir = Get-TempPath -Category 'tools'
    }
    catch {
        Write-Log -Level WARN -Component TOOLS -Message "Tool directory unavailable: $_"
        return $null
    }

    # Already fetched this run? Re-verify rather than trusting the cache. temp_files/tools is
    # wiped every run and only this function writes there, so a cached file was almost
    # certainly verified on the way in - but "almost certainly" is not a basis for executing a
    # binary. Re-checking is cheap and closes the case where anything else drops a file here.
    $existing = Resolve-ExternalToolPath -BaseName $Name -Directory $toolDir
    if ($existing) {
        if ($SkipSignatureCheck -or (Test-MicrosoftSignedBinary -Path $existing)) { return $existing }
        Write-Log -Level WARN -Component TOOLS -Message "Cached $Name failed verification - discarding"
        Remove-Item -LiteralPath $existing -Force -ErrorAction SilentlyContinue
        return $null
    }

    $zip = Join-Path $toolDir "$Name.zip"
    try {
        Write-Log -Level INFO -Component TOOLS -Message "Downloading $Name from $Url"
        $prevProgress = $ProgressPreference
        $ProgressPreference = 'SilentlyContinue'
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $Url -OutFile $zip -UseBasicParsing -TimeoutSec $TimeoutSeconds -ErrorAction Stop
    }
    catch {
        Write-Log -Level WARN -Component TOOLS -Message "Download failed for ${Name}: $($_.Exception.Message)"
        return $null
    }
    finally {
        if ($null -ne $prevProgress) { $ProgressPreference = $prevProgress }
    }

    try {
        # Expand-Archive (not the Shell.Application COM object): the COM extractor propagates
        # Mark-of-the-Web onto every extracted file, which can make Windows refuse to run them.
        Expand-Archive -LiteralPath $zip -DestinationPath $toolDir -Force -ErrorAction Stop
    }
    catch {
        Write-Log -Level WARN -Component TOOLS -Message "Extract failed for ${Name}: $($_.Exception.Message)"
        return $null
    }
    finally {
        if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue }
    }

    $exe = Resolve-ExternalToolPath -BaseName $Name -Directory $toolDir
    if (-not $exe) {
        Write-Log -Level WARN -Component TOOLS -Message "$Name not found in the extracted archive"
        return $null
    }

    if (-not $SkipSignatureCheck -and -not (Test-MicrosoftSignedBinary -Path $exe)) {
        # DELETE the rejected binary. Leaving it on disk meant the next call's cache-hit path
        # would hand back the very file this check just refused.
        Remove-Item -LiteralPath $exe -Force -ErrorAction SilentlyContinue
        return $null
    }

    Write-Log -Level SUCCESS -Component TOOLS -Message "Tool ready: $exe"
    return $exe
}

<#
.SYNOPSIS
    Runs an external command and CAPTURES its stdout, with the same timeout guarantees as
    Invoke-ExternalPackageCommand.
.DESCRIPTION
    Invoke-ExternalPackageCommand returns only an exit code, which is right for installers but
    useless for the audit-shaped tools (autorunsc, sigcheck, du, handle) whose entire value is
    their stdout.

    Same deadlock-safe shape: start draining BOTH pipes before waiting, kill the process TREE
    on timeout, and only read ExitCode after the readers are reaped.

    Keep timeouts SHORT. These are audit tools, not installers - 60-180s is generous. Only
    package installs deserve the 600s default of the sibling function.
.OUTPUTS
    [hashtable] @{ ExitCode = [int]; StdOut = [string]; StdErr = [string]; TimedOut = [bool] }
    ExitCode is -1 on timeout and -2147483648 when the process could not be started at all.
#>
function Invoke-CapturedCommand {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)] [string]$FilePath,
        [Parameter()] [string[]]$ArgumentList = @(),
        [Parameter()] [int]$TimeoutSeconds = 180
    )

    $result = @{ ExitCode = -2147483648; StdOut = ''; StdErr = ''; TimedOut = $false }

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $FilePath
    $psi.Arguments = $ArgumentList -join ' '
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true

    $proc = [System.Diagnostics.Process]::new()
    $proc.StartInfo = $psi
    try {
        try { $null = $proc.Start() }
        catch {
            Write-Log -Level WARN -Component TOOLS -Message "Failed to start '$FilePath': $($_.Exception.Message)"
            return $result
        }

        # Drain before waiting - a full pipe buffer deadlocks the child otherwise.
        $outTask = $proc.StandardOutput.ReadToEndAsync()
        $errTask = $proc.StandardError.ReadToEndAsync()

        $exited = if ($TimeoutSeconds -gt 0) {
            $proc.WaitForExit([int][Math]::Min($TimeoutSeconds * 1000L, [int]::MaxValue))
        }
        else { $proc.WaitForExit(); $true }

        if (-not $exited) {
            try { $proc.Kill($true) } catch { try { $proc.Kill() } catch { } }
            $result.TimedOut = $true
            $result.ExitCode = -1
            Write-Log -Level WARN -Component TOOLS -Message "Timed out after ${TimeoutSeconds}s, process tree killed: $FilePath"
            return $result
        }

        try { $result.StdOut = $outTask.GetAwaiter().GetResult() } catch { }
        try { $result.StdErr = $errTask.GetAwaiter().GetResult() } catch { }
        $result.ExitCode = $proc.ExitCode
        return $result
    }
    finally {
        $proc.Dispose()
    }
}

#endregion

#region ─── EXPORTS ───────────────────────────────────────────────────────────

Export-ModuleMember -Function @(
    'Initialize-Maintenance',
    'Initialize-LogFile',
    'Set-LogLevel',
    'Write-Log',
    'Add-LogRaw',
    'Write-LogException',
    'Get-ExceptionCategory',
    'Close-LogFile',
    'Get-OSContext',
    'Get-MainConfig',
    'Get-BaselineList',
    'Get-TempPath',
    'Compare-ListDiff',
    'Compare-RegistryBaseline',
    'Compare-ServiceBaseline',
    'Invoke-RegistryChangeItem',
    'Invoke-ServiceChangeItem',
    'Get-SecurityPolicyExport',
    'Compare-SecurityPolicyBaseline',
    'Invoke-SecurityPolicyChangeItem',
    'Compare-AuditPolicyBaseline',
    'Invoke-AuditPolicyChangeItem',
    'Save-DiffList',
    'Get-DiffList',
    'New-ModuleResult',
    'Test-CbsRebootPending',
    'Get-InstalledApp',
    'Get-WingetUpgrade',
    'Test-CommandAvailable',
    'Resolve-WingetPath',
    'Get-RegistryValue',
    'Set-RegistryValue',
    'Invoke-ExternalPackageCommand',
    'Invoke-CapturedCommand',
    'Get-ExternalTool',
    'Resolve-ExternalToolPath',
    'Test-MicrosoftSignedBinary',
    'Initialize-SysinternalsEula',
    'Invoke-AppxInWinPS',
    'Get-AppxPackageCompat',
    'Remove-AppxPackageCompat',
    'Get-AppxProvisionedPackageCompat',
    'Remove-AppxProvisionedPackageCompat'
)

#endregion
