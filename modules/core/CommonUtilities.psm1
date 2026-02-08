#Requires -Version 7.0

<#
.SYNOPSIS
    Common Utilities - Shared Helper Functions for All Modules

.DESCRIPTION
    Provides reusable utility functions to eliminate code duplication across
    Type1, Type2, and Core modules. Standardizes common patterns like null-safe
    property access, retry logic, and result object creation.

.MODULE ARCHITECTURE
    Purpose:
        Reduce code duplication (~200 lines eliminated across 22 modules)
        Standardize common patterns (null-coalescing, error handling, retries)
        Simplify module development with proven helper functions

    Dependencies:
        None - this is a foundational utility module

    Exports:
        • Get-SafeValue - Null-safe property access with fallback
        • Invoke-WithRetry - Retry logic with exponential backoff
        • ConvertTo-StandardizedResult - Type2 module result normalization
        • Test-PropertyPath - Validate nested property existence
        • New-ErrorObject - Standardized error object creation
        • Format-DurationString - Human-readable duration formatting

    Import Pattern:
        Import-Module CommonUtilities.psm1 -Force
        # Functions available in any module context

    Used By:
        - All Type1 modules (safe configuration access)
        - All Type2 modules (result standardization, retry logic)
        - Core modules (utility functions)

.EXECUTION FLOW
    1. Module imports CommonUtilities
    2. Uses helper functions throughout execution
    3. Reduces boilerplate code significantly

.NOTES
    Module Type: Core Infrastructure (Utilities)
    Architecture: v3.0 - Phase 1 Enhancement
    Version: 1.0.0
    Created: February 4, 2026

    Key Design Patterns:
    - Null-safe operations (PowerShell 7+ ?? operator)
    - Exponential backoff for retries
    - Standardized result objects
    - Defensive programming (validate inputs)
#>

using namespace System.Collections.Generic

#region Configuration & Property Access

<#
.SYNOPSIS
    Safely accesses nested properties with fallback value

.DESCRIPTION
    Navigates nested object properties using dot notation without throwing exceptions
    if properties don't exist. Returns default value if path is invalid or null.

    Replaces manual null-checking patterns scattered across ~45 locations in codebase.

.PARAMETER Object
    The object to navigate (typically configuration object)

.PARAMETER Path
    Dot-separated property path (e.g., "execution.countdownSeconds")

.PARAMETER Default
    Default value to return if path doesn't exist or is null

.OUTPUTS
    [object] Property value or default

.EXAMPLE
    $seconds = Get-SafeValue -Object $config -Path "execution.countdownSeconds" -Default 30

    Returns config.execution.countdownSeconds or 30 if not found

.EXAMPLE
    $mode = Get-SafeValue -Object $config -Path "execution.defaultMode" -Default "interactive"

    Safe navigation with string default

.NOTES
    Performance: ~0.1ms per call (negligible overhead)
    Replaces: Manual null-checking with if/else chains
#>
function Get-SafeValue {
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [object]$Object,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter()]
        [object]$Default = $null
    )

    # Return default immediately if object is null
    if ($null -eq $Object) {
        return $Default
    }

    try {
        $parts = $Path -split '\.'
        $current = $Object

        foreach ($part in $parts) {
            # Check if property exists
            if ($current -is [hashtable]) {
                if (-not $current.ContainsKey($part)) {
                    return $Default
                }
                $current = $current[$part]
            }
            elseif ($null -eq $current -or -not $current.PSObject.Properties[$part]) {
                return $Default
            }
            else {
                $current = $current.$part
            }

            # If we hit null mid-path, return default
            if ($null -eq $current) {
                return $Default
            }
        }

        # Use null-coalescing operator for final value
        return $current ?? $Default
    }
    catch {
        Write-Verbose "COMMON-UTILITIES: Get-SafeValue failed for path '$Path': $_"
        return $Default
    }
}

<#
.SYNOPSIS
    Tests if nested property path exists in object

.DESCRIPTION
    Validates that a dot-separated property path exists without throwing exceptions.
    Useful for conditional logic based on configuration structure.

.PARAMETER Object
    The object to test

.PARAMETER Path
    Dot-separated property path

.OUTPUTS
    [bool] True if path exists and is not null

.EXAMPLE
    if (Test-PropertyPath -Object $config -Path "modules.customModulesPath") {
        # Use custom modules path
    }
#>
function Test-PropertyPath {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [object]$Object,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    if ($null -eq $Object) {
        return $false
    }

    try {
        $parts = $Path -split '\.'
        $current = $Object

        foreach ($part in $parts) {
            if ($current -is [hashtable]) {
                if (-not $current.ContainsKey($part)) {
                    return $false
                }
                $current = $current[$part]
            }
            elseif ($null -eq $current -or -not $current.PSObject.Properties[$part]) {
                return $false
            }
            else {
                $current = $current.$part
            }

            if ($null -eq $current) {
                return $false
            }
        }

        return $true
    }
    catch {
        return $false
    }
}

#endregion

#region Retry Logic & Error Handling

<#
.SYNOPSIS
    Executes scriptblock with automatic retry logic

.DESCRIPTION
    Implements retry pattern with exponential backoff for transient failures.
    Commonly used for network operations, file I/O, and registry access.

    Replaces manual retry loops scattered across ~15 locations in codebase.

.PARAMETER ScriptBlock
    The scriptblock to execute with retry logic

.PARAMETER MaxRetries
    Maximum number of retry attempts (default: 3)

.PARAMETER InitialDelaySeconds
    Initial delay between retries in seconds (default: 2)
    Delay doubles with each retry (exponential backoff)

.PARAMETER Context
    Descriptive name for logging purposes

.PARAMETER ExponentialBackoff
    Use exponential backoff (delay doubles each retry). Default: $true

.OUTPUTS
    [object] Result of scriptblock execution

.EXAMPLE
    $data = Invoke-WithRetry -ScriptBlock {
        Get-Content "\\network\share\file.txt"
    } -Context "Network File Read"

    Retries network file read with exponential backoff

.EXAMPLE
    Invoke-WithRetry -ScriptBlock {
        Set-ItemProperty -Path "HKLM:\..." -Name "..." -Value "..."
    } -MaxRetries 5 -Context "Registry Write"

    Retries registry write up to 5 times

.NOTES
    Backoff Pattern: 2s, 4s, 8s (exponential)
    Total Max Time: ~14s for 3 retries at 2s initial delay
#>
function Invoke-WithRetry {
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock,

        [Parameter()]
        [ValidateRange(1, 10)]
        [int]$MaxRetries = 3,

        [Parameter()]
        [ValidateRange(1, 60)]
        [int]$InitialDelaySeconds = 2,

        [Parameter()]
        [string]$Context = 'Operation',

        [Parameter()]
        [bool]$ExponentialBackoff = $true
    )

    $lastError = $null

    for ($attempt = 1; $attempt -le $MaxRetries; $attempt++) {
        try {
            Write-Verbose "COMMON-UTILITIES: $Context - Attempt $attempt of $MaxRetries"
            return & $ScriptBlock
        }
        catch {
            $lastError = $_

            if ($attempt -eq $MaxRetries) {
                Write-Verbose "COMMON-UTILITIES: $Context failed after $MaxRetries attempts"
                throw $lastError
            }

            # Calculate delay with exponential backoff
            $delay = if ($ExponentialBackoff) {
                $InitialDelaySeconds * [Math]::Pow(2, $attempt - 1)
            }
            else {
                $InitialDelaySeconds
            }

            Write-Verbose "COMMON-UTILITIES: $Context failed (attempt $attempt/$MaxRetries), retrying in ${delay}s: $_"
            Start-Sleep -Seconds $delay
        }
    }

    # Should never reach here, but just in case
    throw $lastError
}

<#
.SYNOPSIS
    Creates standardized error object

.DESCRIPTION
    Generates consistent error object structure for module results.
    Ensures all modules report errors in the same format.

.PARAMETER Exception
    The exception object

.PARAMETER Context
    Contextual information about where error occurred

.PARAMETER Severity
    Error severity: Critical, Error, Warning

.OUTPUTS
    [hashtable] Standardized error object

.EXAMPLE
    $error = New-ErrorObject -Exception $_.Exception -Context "Bloatware Removal" -Severity "Error"
#>
function New-ErrorObject {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [System.Exception]$Exception,

        [Parameter()]
        [string]$Context = 'Unknown',

        [Parameter()]
        [ValidateSet('Critical', 'Error', 'Warning')]
        [string]$Severity = 'Error'
    )

    return @{
        Message = $Exception.Message
        Context = $Context
        Severity = $Severity
        Type = $Exception.GetType().Name
        Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        StackTrace = if ($Severity -eq 'Critical') { $Exception.StackTrace } else { $null }
    }
}

#endregion

#region Result Standardization

<#
.SYNOPSIS
    Converts raw module result to standardized format

.DESCRIPTION
    Normalizes Type2 module results into consistent structure for LogAggregator.
    Ensures all modules return results in same format regardless of internal structure.

    Replaces custom result object creation in ~14 Type2 modules.

.PARAMETER RawResult
    Raw result hashtable from module execution

.PARAMETER ModuleName
    Name of the module producing the result

.PARAMETER DurationSeconds
    Execution duration in seconds

.PARAMETER Status
    Override status if different from RawResult.Status

.OUTPUTS
    [hashtable] Standardized module result object

.EXAMPLE
    $standardResult = ConvertTo-StandardizedResult `
        -RawResult $result `
        -ModuleName 'BloatwareRemoval' `
        -DurationSeconds 45.3

    Converts raw result to standard format

.NOTES
    Standard Format:
    @{
        ModuleName = "..."
        Status = "Success|Failed|Skipped"
        Metrics = @{
            ItemsDetected = 0
            ItemsProcessed = 0
            ItemsFailed = 0
            DurationSeconds = 0.0
        }
        Results = @{}
        Errors = @()
    }
#>
function ConvertTo-StandardizedResult {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$RawResult,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ModuleName,

        [Parameter()]
        [decimal]$DurationSeconds = 0,

        [Parameter()]
        [ValidateSet('Success', 'Failed', 'Skipped')]
        [string]$Status
    )

    # Determine status (prefer parameter, then RawResult.Status, then infer from errors)
    $finalStatus = if ($Status) {
        $Status
    }
    elseif ($RawResult.Status) {
        $RawResult.Status
    }
    elseif ($RawResult.Errors -and $RawResult.Errors.Count -gt 0) {
        'Failed'
    }
    elseif ($RawResult.Success -eq $false) {
        'Failed'
    }
    else {
        'Success'
    }

    return @{
        ModuleName = $ModuleName
        Status = $finalStatus
        Metrics = @{
            ItemsDetected = [int]($RawResult.TotalOperations ?? $RawResult.ItemsDetected ?? 0)
            ItemsProcessed = [int]($RawResult.SuccessfulOperations ?? $RawResult.ItemsProcessed ?? 0)
            ItemsSkipped = [int]($RawResult.ItemsSkipped ?? 0)
            ItemsFailed = [int]($RawResult.FailedOperations ?? $RawResult.ItemsFailed ?? 0)
            DurationSeconds = [decimal]$DurationSeconds
        }
        Results = $RawResult.Results ?? @{}
        Errors = $RawResult.Errors ?? @()
        Warnings = $RawResult.Warnings ?? @()
    }
}

#endregion

#region Formatting & Display

<#
.SYNOPSIS
    Formats duration as human-readable string

.DESCRIPTION
    Converts seconds to human-readable format (e.g., "2m 30s", "45.3s")

.PARAMETER Seconds
    Duration in seconds

.OUTPUTS
    [string] Formatted duration string

.EXAMPLE
    $duration = Format-DurationString -Seconds 150.5
    # Returns: "2m 30s"
#>
function Format-DurationString {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [decimal]$Seconds
    )

    if ($Seconds -lt 60) {
        return "{0:F1}s" -f $Seconds
    }

    $minutes = [Math]::Floor($Seconds / 60)
    $remainingSeconds = [Math]::Round($Seconds % 60)

    if ($minutes -lt 60) {
        return "${minutes}m ${remainingSeconds}s"
    }

    $hours = [Math]::Floor($minutes / 60)
    $remainingMinutes = $minutes % 60

    return "${hours}h ${remainingMinutes}m ${remainingSeconds}s"
}

#endregion

#region OS-Specific Helper Functions (v4.0 - Phase A.1.6)

<#
.SYNOPSIS
    Determines if a feature or app is available on current OS version

.DESCRIPTION
    Checks if a specific Windows feature is available on the current OS version.
    Used to enable/disable functionality based on Windows 10 vs Windows 11.

.PARAMETER FeatureName
    Name of the feature to check. Valid values include:
    - 'Widgets': Windows 11 widgets panel
    - 'Chat': Windows 11 Teams integration
    - 'ModernStartMenu': Windows 11 centered start menu
    - 'LegacyStartMenu': Windows 10 classic start menu
    - 'TaskbarAlignment': Windows 11 taskbar positioning
    - 'SnapLayouts': Windows 11 snap layouts
    - 'DirectStorage': Windows 11 DirectStorage API
    - 'AndroidApps': Windows 11 Android app support

.PARAMETER OSContext
    Optional OS context object from Get-WindowsVersionContext.
    If not provided, will be detected automatically.

.OUTPUTS
    Boolean indicating if the feature is available

.EXAMPLE
    if (Test-OSFeatureAvailable -FeatureName 'Widgets') {
        # Disable Windows 11 widgets
        Disable-WidgetsPanel
    }

.EXAMPLE
    $osContext = Get-WindowsVersionContext
    $hasModernUI = Test-OSFeatureAvailable -FeatureName 'ModernStartMenu' -OSContext $osContext

.NOTES
    Added in v4.0 - Phase A.1.6
    Requires CoreInfrastructure.psm1 for Get-WindowsVersionContext
#>
function Test-OSFeatureAvailable {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet(
            'Widgets', 'Chat', 'ModernStartMenu', 'LegacyStartMenu',
            'TaskbarAlignment', 'SnapLayouts', 'DirectStorage', 'AndroidApps',
            'TPM2Required', 'VBS', 'HVCI', 'CenteredTaskbar', 'ModernUI'
        )]
        [string]$FeatureName,

        [Parameter()]
        [PSCustomObject]$OSContext
    )

    # Get OS context if not provided
    if (-not $OSContext) {
        if (Get-Command -Name 'Get-WindowsVersionContext' -ErrorAction SilentlyContinue) {
            $OSContext = Get-WindowsVersionContext
        }
        else {
            Write-Warning "Get-WindowsVersionContext not available. Import CoreInfrastructure.psm1 first."
            return $false
        }
    }

    # Feature availability map
    $featureMap = @{
        # UI Features
        'Widgets' = $OSContext.IsWindows11
        'Chat' = $OSContext.IsWindows11
        'ModernStartMenu' = $OSContext.IsWindows11
        'CenteredTaskbar' = $OSContext.IsWindows11
        'ModernUI' = $OSContext.IsWindows11
        'LegacyStartMenu' = $OSContext.IsWindows10

        # System Features
        'TaskbarAlignment' = $OSContext.IsWindows11
        'SnapLayouts' = $OSContext.IsWindows11
        'DirectStorage' = $OSContext.IsWindows11
        'AndroidApps' = $OSContext.IsWindows11
        'TPM2Required' = $OSContext.IsWindows11

        # Security Features
        'VBS' = $OSContext.IsWindows11
        'HVCI' = $OSContext.IsWindows11
    }

    $isAvailable = $featureMap[$FeatureName]

    if ($null -eq $isAvailable) {
        Write-Warning "Unknown feature: $FeatureName. Defaulting to false."
        return $false
    }

    return $isAvailable
}

<#
.SYNOPSIS
    Gets OS-specific registry path for a given setting

.DESCRIPTION
    Returns the correct registry path for a setting based on the Windows version.
    Registry paths may differ between Windows 10 and Windows 11 for the same functionality.

.PARAMETER SettingName
    Name of the setting. Valid values include:
    - 'Taskbar': Taskbar customization settings
    - 'StartMenu': Start menu configuration
    - 'Widgets': Windows 11 widgets settings
    - 'Explorer': File Explorer settings
    - 'Search': Windows Search settings

.PARAMETER OSContext
    Optional OS context object from Get-WindowsVersionContext.
    If not provided, will be detected automatically.

.OUTPUTS
    String containing the registry path, or $null if not available for current OS

.EXAMPLE
    $taskbarPath = Get-OSSpecificRegistryPath -SettingName 'Taskbar'
    Set-ItemProperty -Path $taskbarPath -Name 'TaskbarAl' -Value 0

.EXAMPLE
    $osContext = Get-WindowsVersionContext
    $widgetsPath = Get-OSSpecificRegistryPath -SettingName 'Widgets' -OSContext $osContext

    if ($widgetsPath) {
        # Disable widgets (Windows 11 only)
        Set-ItemProperty -Path $widgetsPath -Name 'TaskbarDa' -Value 0
    }

.NOTES
    Added in v4.0 - Phase A.1.6
    Returns $null if setting doesn't apply to current OS version
#>
function Get-OSSpecificRegistryPath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Taskbar', 'StartMenu', 'Widgets', 'Explorer', 'Search', 'Chat', 'Telemetry')]
        [string]$SettingName,

        [Parameter()]
        [PSCustomObject]$OSContext
    )

    # Get OS context if not provided
    if (-not $OSContext) {
        if (Get-Command -Name 'Get-WindowsVersionContext' -ErrorAction SilentlyContinue) {
            $OSContext = Get-WindowsVersionContext
        }
        else {
            Write-Warning "Get-WindowsVersionContext not available. Import CoreInfrastructure.psm1 first."
            return $null
        }
    }

    # Define OS-specific registry paths
    $pathMap = @{
        'Taskbar' = @{
            'Windows10' = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
            'Windows11' = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
            # Note: Same path, but different values (e.g., TaskbarAl for alignment)
        }
        'StartMenu' = @{
            'Windows10' = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
            'Windows11' = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
        }
        'Widgets' = @{
            'Windows11' = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
            # Windows 10 doesn't have widgets panel
        }
        'Chat' = @{
            'Windows11' = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
            # TaskbarMn value controls chat icon
        }
        'Explorer' = @{
            'Windows10' = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
            'Windows11' = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
        }
        'Search' = @{
            'Windows10' = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search'
            'Windows11' = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search'
        }
        'Telemetry' = @{
            'Windows10' = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'
            'Windows11' = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'
        }
    }

    # Determine OS key
    $osKey = "Windows$($OSContext.Version)"

    # Get path for setting and OS version
    if ($pathMap[$SettingName] -and $pathMap[$SettingName][$osKey]) {
        return $pathMap[$SettingName][$osKey]
    }

    # Return null if setting doesn't apply to this OS version
    Write-Verbose "Setting '$SettingName' not available for $osKey"
    return $null
}

<#
.SYNOPSIS
    Gets OS-specific configuration values

.DESCRIPTION
    Retrieves configuration values that differ between Windows 10 and Windows 11.
    Used to load correct settings from configuration files based on OS version.

.PARAMETER ConfigKey
    Configuration key to retrieve (e.g., 'bloatware', 'optimizations', 'telemetry')

.PARAMETER Config
    Configuration object containing OS-specific sections

.PARAMETER OSContext
    Optional OS context object from Get-WindowsVersionContext

.OUTPUTS
    Configuration object with OS-specific values merged with common values

.EXAMPLE
    $config = Get-Content 'config.json' | ConvertFrom-Json
    $osBloatware = Get-OSSpecificConfig -ConfigKey 'bloatware' -Config $config

    # Returns common bloatware + Windows 11 specific items

.NOTES
    Added in v4.0 - Phase A.1.6
    Merges common configuration with OS-specific overrides
#>
function Get-OSSpecificConfig {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$ConfigKey,

        [Parameter(Mandatory)]
        [PSCustomObject]$Config,

        [Parameter()]
        [PSCustomObject]$OSContext
    )

    # Get OS context if not provided
    if (-not $OSContext) {
        if (Get-Command -Name 'Get-WindowsVersionContext' -ErrorAction SilentlyContinue) {
            $OSContext = Get-WindowsVersionContext
        }
        else {
            Write-Warning "Get-WindowsVersionContext not available. Import CoreInfrastructure.psm1 first."
            return $Config.$ConfigKey
        }
    }

    $osKey = "windows$($OSContext.Version)"
    $merged = @()

    # Add common items (apply to all OS versions)
    if ($Config.common -and $Config.common.$ConfigKey) {
        $merged += $Config.common.$ConfigKey
    }

    # Add OS-specific items
    if ($Config.$osKey -and $Config.$osKey.$ConfigKey) {
        $merged += $Config.$osKey.$ConfigKey
        Write-Verbose "Merged $($Config.$osKey.$ConfigKey.Count) OS-specific items for Windows $($OSContext.Version)"
    }

    return $merged
}

<#
.SYNOPSIS
    Calculate a health/quality score based on issues or opportunities

.DESCRIPTION
    Generic scoring function used across all audit modules. Starts with a base
    score of 100 and deducts points based on impact levels of detected issues.

    Consolidates duplicate implementations from:
    - Get-OptimizationScore (SystemOptimizationAudit)
    - Get-PrivacyScore (TelemetryAudit)
    - Get-UpdateHealthScore (WindowsUpdatesAudit)

.PARAMETER Issues
    Array of issue/opportunity objects with 'Impact' property

.PARAMETER DeductionMap
    Hashtable mapping impact levels to deduction amounts
    Default: @{ High = 20; Medium = 10; Low = 5 }

.PARAMETER ScoreType
    Name for the score type (used in Category property)
    Example: 'Optimization', 'Privacy', 'Update Health'

.PARAMETER BaseScore
    Starting score before deductions. Default: 100

.OUTPUTS
    PSCustomObject with score details:
    @{
        Overall = <score>
        MaxScore = <baseScore>
        Deductions = <total deducted>
        IssueCount = <count of issues>
        Category = 'Excellent' | 'Good' | 'Fair' | 'Needs Improvement'
    }

.EXAMPLE
    $score = Get-GenericHealthScore `
        -Issues $auditResults.OptimizationOpportunities `
        -ScoreType 'Optimization'

.EXAMPLE
    # Custom deduction amounts
    $score = Get-GenericHealthScore `
        -Issues $auditResults.PrivacyIssues `
        -ScoreType 'Privacy' `
        -DeductionMap @{ High = 30; Medium = 15; Low = 5 }

.NOTES
    Added in Phase B.3 - Consolidation (Feb 2026)
    Eliminates duplicate scoring logic across 3+ modules
#>
function Get-GenericHealthScore {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [array]$Issues,

        [Parameter()]
        [hashtable]$DeductionMap = @{
            High = 20
            Medium = 10
            Low = 5
        },

        [Parameter()]
        [string]$ScoreType = 'Health',

        [Parameter()]
        [ValidateRange(0, 100)]
        [int]$BaseScore = 100
    )

    $deductions = 0

    # Calculate deductions based on impact levels
    foreach ($issue in $Issues) {
        $impactLevel = $issue.Impact
        if ($DeductionMap.ContainsKey($impactLevel)) {
            $deductions += $DeductionMap[$impactLevel]
        }
        else {
            # Default to Low impact if not specified
            $deductions += $DeductionMap['Low']
        }
    }

    $overallScore = [math]::Max(0, $BaseScore - $deductions)

    # Determine category based on percentage of max score
    $percentage = ($overallScore / $BaseScore) * 100
    $category = if ($percentage -ge 90) { "Excellent $ScoreType" }
    elseif ($percentage -ge 75) { "Good $ScoreType" }
    elseif ($percentage -ge 60) { "Fair $ScoreType" }
    else { "Needs Improvement" }

    return [PSCustomObject]@{
        Overall = $overallScore
        MaxScore = $BaseScore
        Deductions = $deductions
        IssueCount = $Issues.Count
        Category = $category
        ScoreType = $ScoreType
    }
}

#endregion

#region Bloatware Removal

<#
.SYNOPSIS
    Generic bloatware item removal with standardized logging and verification

.DESCRIPTION
    Provides a unified removal pattern for all bloatware sources (AppX, Winget, Chocolatey, Registry).
    Eliminates ~400 lines of duplicate code across 4 removal functions by centralizing:
    - Tool availability checking
    - Pre-action state detection
    - Removal execution with logging
    - Post-action verification
    - Result aggregation

    This is a Phase B.3 consolidation function that standardizes the removal workflow
    used by Remove-AppXBloatware, Remove-WingetBloatware, Remove-ChocolateyBloatware,
    and Remove-RegistryBloatware.

.PARAMETER Items
    Array of bloatware items to remove

.PARAMETER SourceName
    Source identifier for logging ('AppX', 'Winget', 'Chocolatey', 'Registry')

.PARAMETER ToolAvailabilityChecker
    Scriptblock that returns $true if removal tool is available, $false otherwise.
    Called once before processing items.

.PARAMETER GetItemName
    Scriptblock that extracts the item name/identifier from an item object.
    Example: { param($item) $item.Name }

.PARAMETER PreActionDetector
    Scriptblock that detects pre-action state for an item.
    Returns PSCustomObject with state properties for logging.
    Example: { param($item) Get-AppxPackage -Name $item.Name }

.PARAMETER RemovalExecutor
    Scriptblock that executes the removal operation.
    Returns hashtable with: @{ Success = $bool; ExitCode = $int; Error = $string }
    Example: { param($item) Remove-AppxPackage -Package $item.Name }

.PARAMETER PostActionVerifier
    Scriptblock that verifies removal was successful.
    Returns $true if item still exists (failed), $false if removed (success).
    Example: { param($item) $null -ne (Get-AppxPackage -Name $item.Name) }

.OUTPUTS
    [hashtable] Results with Successful, Failed, Skipped counts and Details collection

.EXAMPLE
    $results = Invoke-BloatwareItemRemoval `
        -Items $appxPackages `
        -SourceName 'AppX' `
        -ToolAvailabilityChecker { Get-Command Get-AppxPackage -ErrorAction SilentlyContinue } `
        -GetItemName { param($item) $item.WingetId ?? $item.Name } `
        -PreActionDetector { param($item) Get-AppxPackage -Name $item.Name -AllUsers } `
        -RemovalExecutor { param($item, $preState) Remove-AppxPackage -Package $preState.PackageFullName } `
        -PostActionVerifier { param($item) $null -ne (Get-AppxPackage -Name $item.Name) }

.NOTES
    Module Type: Core Infrastructure (Utilities)
    Architecture: v3.0 - Phase B.3 Consolidation
    Version: 1.0.0

    Performance: ~2-5 seconds per item (depends on removal tool)
    Replaces: 4 functions × ~100 lines = ~400 lines eliminated
#>
function Invoke-BloatwareItemRemoval {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [Array]$Items,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$SourceName,

        [Parameter(Mandatory)]
        [scriptblock]$ToolAvailabilityChecker,

        [Parameter(Mandatory)]
        [scriptblock]$GetItemName,

        [Parameter(Mandatory)]
        [scriptblock]$PreActionDetector,

        [Parameter(Mandatory)]
        [scriptblock]$RemovalExecutor,

        [Parameter(Mandatory)]
        [scriptblock]$PostActionVerifier
    )

    # Initialize results
    $results = @{
        Successful = 0
        Failed = 0
        Skipped = 0
        Details = [List[PSCustomObject]]::new()
    }

    # Check tool availability
    $toolAvailable = & $ToolAvailabilityChecker
    if (-not $toolAvailable) {
        Write-Verbose "$SourceName removal tool not available - skipping $($Items.Count) items"
        $results.Skipped = $Items.Count
        return $results
    }

    # Process each item
    foreach ($item in $Items) {
        $itemName = & $GetItemName $item
        $operationStart = Get-Date
        $result = @{
            Name = $itemName
            Source = $SourceName
            Success = $false
            Action = 'Removed'
            Error = $null
        }

        try {
            # Pre-action state detection
            $preActionState = & $PreActionDetector $item

            # Log operation start
            $additionalInfo = if ($preActionState) {
                "$SourceName Package"
            }
            else {
                "$SourceName Package (not found, may already be removed)"
            }
            Write-OperationStart -Component 'BLOATWARE-REMOVAL' -Operation 'Remove' -Target $itemName -AdditionalInfo $additionalInfo

            Write-Information "     Removing $SourceName package: $itemName" -InformationAction Continue

            # Execute removal
            $removalResult = & $RemovalExecutor $item $preActionState

            if ($removalResult.Success -or ($null -eq $removalResult.ExitCode) -or $removalResult.ExitCode -eq 0) {
                # Post-action verification
                Write-LogEntry -Level 'INFO' -Component 'BLOATWARE-REMOVAL' -Operation 'Verify' -Target $itemName -Message "Verifying $SourceName package removal"

                $stillInstalled = & $PostActionVerifier $item

                if (-not $stillInstalled) {
                    $operationDuration = ((Get-Date) - $operationStart).TotalSeconds

                    # Log successful verification
                    Write-OperationSuccess -Component 'BLOATWARE-REMOVAL' -Operation 'Verify' -Target $itemName -Metrics @{
                        StillInstalled = $false
                        VerificationPassed = $true
                    }

                    # Log successful removal
                    Write-OperationSuccess -Component 'BLOATWARE-REMOVAL' -Operation 'Remove' -Target $itemName -Metrics @{
                        Duration = $operationDuration
                        Source = $SourceName
                        Verified = $true
                    }

                    $result.Success = $true
                    Write-Information "       Successfully removed $SourceName package: $itemName (${operationDuration}s)" -InformationAction Continue
                    $results.Successful++
                }
                else {
                    # Verification failed - package still present
                    $errorMsg = "Package still present after removal attempt"
                    Write-OperationFailure -Component 'BLOATWARE-REMOVAL' -Operation 'Verify' -Target $itemName -ErrorMessage $errorMsg
                    $result.Error = $errorMsg
                    Write-Warning "   Failed to verify removal of $itemName"
                    $results.Failed++
                }
            }
            else {
                # Removal command failed
                $errorMsg = "$SourceName removal failed: $($removalResult.Error ?? "Exit code $($removalResult.ExitCode)")"
                Write-OperationFailure -Component 'BLOATWARE-REMOVAL' -Operation 'Remove' -Target $itemName -ErrorMessage $errorMsg
                $result.Error = $errorMsg
                Write-Warning "   Failed to remove $itemName`: $errorMsg"
                $results.Failed++
            }
        }
        catch {
            # Unexpected exception
            $errorMsg = $_.Exception.Message
            Write-OperationFailure -Component 'BLOATWARE-REMOVAL' -Operation 'Remove' -Target $itemName -ErrorMessage $errorMsg
            $result.Error = $errorMsg
            Write-Warning "   Exception removing $itemName`: $errorMsg"
            $results.Failed++
        }
        finally {
            # Add result to collection
            $results.Details.Add([PSCustomObject]$result) | Out-Null
        }
    }

    return $results
}

#endregion

#region Recommendation Generation

<#
.SYNOPSIS
    Generic impact-based recommendation generator

.DESCRIPTION
    Generates prioritized recommendations based on issue impact levels (High, Medium, Low).
    Eliminates ~60 lines of duplicate code across 3 audit modules by centralizing the common
    recommendation generation pattern.

    This is a Phase B.3 consolidation function that standardizes recommendation generation
    used by New-OptimizationRecommendations, New-PrivacyRecommendations, and New-UpdateRecommendations.

.PARAMETER Issues
    Array of issue objects with Impact property (High, Medium, Low)

.PARAMETER IssueType
    Type of issues for naming (e.g., "optimization", "privacy", "update")

.PARAMETER AdditionalIssues
    Optional additional issues array to include in impact counting (e.g., SecurityFindings for updates)

.PARAMETER SpecificChecks
    Optional hashtable of specific check scriptblocks that return recommendation strings
    Keys: 'ActiveServices', 'PendingUpdates', 'RebootRequired', etc.
    Values: Scriptblocks that accept $AuditResults and return string or $null

.PARAMETER AuditResults
    Full audit results hashtable for specific checks

.OUTPUTS
    [array] Array of recommendation strings

.EXAMPLE
    $recommendations = New-ImpactBasedRecommendations `
        -Issues $auditResults.OptimizationOpportunities `
        -IssueType 'optimization'

.EXAMPLE
    $recommendations = New-ImpactBasedRecommendations `
        -Issues $auditResults.PrivacyIssues `
        -IssueType 'privacy' `
        -SpecificChecks @{
            ActiveServices = { param($results)
                if ($results.ActiveServices.Count -gt 0) {
                    " Services: Consider disabling $($results.ActiveServices.Count) telemetry services"
                }
            }
        } `
        -AuditResults $auditResults

.NOTES
    Module Type: Core Infrastructure (Utilities)
    Architecture: v3.0 - Phase B.3 Consolidation
    Version: 1.0.0

    Replaces: 3 functions × ~60 lines = ~180 lines eliminated
#>
function New-ImpactBasedRecommendations {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [Array]$Issues,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$IssueType,

        [Parameter()]
        [AllowEmptyCollection()]
        [Array]$AdditionalIssues = @(),

        [Parameter()]
        [hashtable]$SpecificChecks = @{},

        [Parameter()]
        [hashtable]$AuditResults = @{}
    )

    $recommendations = @()

    # Combine all issues for comprehensive impact analysis
    $allIssues = @($Issues) + @($AdditionalIssues)

    # Count issues by impact level
    $highImpact = $allIssues | Where-Object { $_.Impact -eq 'High' }
    $mediumImpact = $allIssues | Where-Object { $_.Impact -eq 'Medium' }
    $lowImpact = $allIssues | Where-Object { $_.Impact -eq 'Low' }

    # Generate impact-based recommendations
    if ($highImpact.Count -gt 0) {
        switch ($IssueType) {
            'optimization' {
                $recommendations += "Priority 1: Address $($highImpact.Count) high-impact optimizations for immediate performance gains"
            }
            'privacy' {
                $recommendations += " Critical: Address $($highImpact.Count) high-impact privacy issues immediately"
                $recommendations += "   Focus on telemetry services, data collection settings, and consumer features"
            }
            'update' {
                $recommendations += " Critical: Address $($highImpact.Count) high-impact update issues immediately"
                $recommendations += "   Priority: Security updates, service configuration, and failed installations"
            }
            default {
                $recommendations += "Priority 1: Address $($highImpact.Count) high-impact $IssueType issues immediately"
            }
        }
    }

    # Medium impact recommendations
    if ($mediumImpact.Count -gt 0) {
        switch ($IssueType) {
            'optimization' {
                $recommendations += "Priority 2: Implement $($mediumImpact.Count) medium-impact optimizations for steady improvements"
            }
            'privacy' {
                $recommendations += " Important: Fix $($mediumImpact.Count) medium-impact privacy settings"
                $recommendations += "   Review advertising settings, app permissions, and feature configurations"
            }
            'update' {
                $recommendations += " Important: Resolve $($mediumImpact.Count) medium-impact update issues"
                $recommendations += "   Review update policies and installation schedules"
            }
            default {
                $recommendations += "Priority 2: Implement $($mediumImpact.Count) medium-impact $IssueType improvements"
            }
        }
    }

    # Low impact recommendations (typically only for privacy)
    if ($lowImpact.Count -gt 0 -and $IssueType -eq 'privacy') {
        $recommendations += " Optional: Optimize $($lowImpact.Count) low-impact settings for enhanced privacy"
    }

    # Execute specific checks
    foreach ($checkName in $SpecificChecks.Keys) {
        $checkResult = & $SpecificChecks[$checkName] $AuditResults
        if ($checkResult) {
            $recommendations += $checkResult
        }
    }

    # No issues detected - positive feedback
    if ($allIssues.Count -eq 0) {
        switch ($IssueType) {
            'optimization' {
                $recommendations += "System is well-optimized. Consider periodic maintenance and monitoring."
            }
            'privacy' {
                $recommendations += " Excellent! Your system has strong privacy protections in place"
                $recommendations += " Continue monitoring and reviewing new Windows updates for privacy changes"
            }
            'update' {
                $recommendations += " Excellent! Windows Update system is healthy and current"
                $recommendations += " Continue monitoring for new updates and maintain regular update schedule"
            }
            default {
                $recommendations += "No $IssueType issues detected. System is in good condition."
            }
        }
    }

    return $recommendations
}

#endregion

#region OS-Aware Configuration Loading (Phase B.4.1 - v4.0)

<#
.SYNOPSIS
    Generic OS-aware configuration loader with automatic merging

.DESCRIPTION
    Loads configuration with OS-specific sections (common/windows10/windows11)
    and merges them based on current OS context. Handles both simple concatenation
    (bloatware lists) and complex nested merging (system optimization settings).

.PARAMETER ConfigData
    Full configuration object (from Get-JsonConfiguration)

.PARAMETER OSContext
    OS context object (from Get-WindowsVersionContext). Auto-detected if not provided.

.PARAMETER MergeStrategy
    Merge strategy: 'Simple' (concatenate arrays) or 'Complex' (deep merge properties)

.PARAMETER ReturnFormat
    Output format: 'Hashtable' (with 'all' key) or 'Direct' (merged data directly)

.PARAMETER FallbackProperty
    Property name for backward compatibility (default: 'all' for v3.x configs)

.OUTPUTS
    Hashtable or direct object with merged configuration

.EXAMPLE
    # Simple concatenation (Bloatware)
    $config = Get-JsonConfiguration -ConfigType 'Bloatware'
    $merged = Invoke-OSAwareConfigMerge -ConfigData $config -MergeStrategy 'Simple' -ReturnFormat 'Hashtable'

.EXAMPLE
    # Complex merging (SystemOptimization)
    $config = Get-JsonConfiguration -ConfigType 'SystemOptimization'
    $merged = Invoke-OSAwareConfigMerge -ConfigData $config -MergeStrategy 'Complex' -ReturnFormat 'Direct'

.NOTES
    Module: CommonUtilities
    Architecture: v4.0 - Phase B.4.1 Generic Configuration Consolidation
    Pattern: Eliminates ~70 lines of duplicate OS detection/merging logic per config loader
#>
function Invoke-OSAwareConfigMerge {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [ValidateScript({
                $_ -is [hashtable] -or $_ -is [PSCustomObject]
            })]
        $ConfigData,

        [Parameter()]
        [PSCustomObject]$OSContext,

        [Parameter()]
        [ValidateSet('Simple', 'Complex')]
        [string]$MergeStrategy = 'Simple',

        [Parameter()]
        [ValidateSet('Hashtable', 'Direct')]
        [string]$ReturnFormat = 'Hashtable',

        [Parameter()]
        [string]$FallbackProperty = 'all'
    )

    # Get OS context if not provided
    if (-not $OSContext) {
        if (Get-Command -Name 'Get-WindowsVersionContext' -ErrorAction SilentlyContinue) {
            $OSContext = Get-WindowsVersionContext
        }
        else {
            Write-Warning "Get-WindowsVersionContext not available. Returning config without OS-specific merging."

            # Return fallback configuration
            if ($ConfigData.common) {
                return if ($ReturnFormat -eq 'Hashtable') {
                    @{ $FallbackProperty = $ConfigData.common }
                } else {
                    $ConfigData.common
                }
            }
            elseif ($ConfigData.$FallbackProperty) {
                return if ($ReturnFormat -eq 'Hashtable') {
                    $ConfigData
                } else {
                    $ConfigData.$FallbackProperty
                }
            }
            else {
                return $ConfigData
            }
        }
    }

    # Execute merge based on strategy
    $merged = switch ($MergeStrategy) {
        'Simple' {
            # Simple array concatenation (for bloatware lists, essential apps, etc.)
            $result = @()

            # Add common items
            if ($ConfigData.common) {
                $result += $ConfigData.common
                Write-Verbose "Added $($ConfigData.common.Count) common items"
            }
            elseif ($ConfigData.$FallbackProperty) {
                # Backward compatibility: v3.x format
                $result += $ConfigData.$FallbackProperty
                Write-Verbose "Using legacy '$FallbackProperty' property: $($ConfigData.$FallbackProperty.Count) items"
            }

            # Add OS-specific items
            if ($OSContext.IsWindows11 -and $ConfigData.windows11) {
                $result += $ConfigData.windows11
                Write-Verbose "Added $($ConfigData.windows11.Count) Windows 11 specific items"
            }
            elseif ($OSContext.IsWindows10 -and $ConfigData.windows10) {
                $result += $ConfigData.windows10
                Write-Verbose "Added $($ConfigData.windows10.Count) Windows 10 specific items"
            }

            Write-Verbose "Total items after simple merge: $($result.Count)"
            $result
        }

        'Complex' {
            # Complex nested property merging (for system optimization, security config, etc.)

            # Helper function to convert PSCustomObject to hashtable recursively
            function ConvertTo-Hashtable {
                param($InputObject)

                if ($null -eq $InputObject) { return $null }

                if ($InputObject -is [hashtable]) {
                    $output = @{}
                    foreach ($key in $InputObject.Keys) {
                        $output[$key] = ConvertTo-Hashtable $InputObject[$key]
                    }
                    return $output
                }

                if ($InputObject -is [PSCustomObject]) {
                    $output = @{}
                    foreach ($property in $InputObject.PSObject.Properties) {
                        $output[$property.Name] = ConvertTo-Hashtable $property.Value
                    }
                    return $output
                }

                if ($InputObject -is [Array]) {
                    $output = @()
                    foreach ($item in $InputObject) {
                        $output += ConvertTo-Hashtable $item
                    }
                    return , $output
                }

                return $InputObject
            }

            # Convert common base to hashtable for mutable merging
            $result = if ($ConfigData.common) {
                ConvertTo-Hashtable $ConfigData.common
            }
            else {
                # Backward compatibility: no OS sections
                Write-Verbose "Using legacy configuration format (no OS-specific sections)"
                return $ConfigData
            }

            Write-Verbose "Loaded common configuration as base (converted to hashtable)"

            # Merge OS-specific settings
            $osKey = "windows$($OSContext.Version)"
            if ($ConfigData.$osKey) {
                $osConfig = ConvertTo-Hashtable $ConfigData.$osKey
                Write-Verbose "Merging Windows $($OSContext.Version) specific configuration"

                # Recursive merge function for nested properties
                function Merge-HashTables {
                    param(
                        [hashtable]$Base,
                        [hashtable]$Override
                    )

                    foreach ($key in $Override.Keys) {
                        if ($Override[$key] -is [hashtable] -and $Base[$key] -is [hashtable]) {
                            # Recursively merge nested hashtables
                            Merge-HashTables -Base $Base[$key] -Override $Override[$key]
                        }
                        elseif ($Override[$key] -is [Array] -and $Base[$key] -is [Array]) {
                            # Concatenate arrays
                            $Base[$key] = @($Base[$key]) + @($Override[$key])
                            Write-Verbose "Merged array '$key': added $($Override[$key].Count) items (total: $($Base[$key].Count))"
                        }
                        else {
                            # Override scalar or add new property
                            $Base[$key] = $Override[$key]
                            Write-Verbose "Set property '$key' from OS-specific config"
                        }
                    }
                }

                Merge-HashTables -Base $result -Override $osConfig
            }

            $result
        }
    }

    # Return in requested format
    if ($ReturnFormat -eq 'Hashtable') {
        return @{ $FallbackProperty = $merged }
    }
    else {
        return $merged
    }
}

#endregion

# Export public functions
Export-ModuleMember -Function @(
    'Get-SafeValue',
    'Test-PropertyPath',
    'Invoke-WithRetry',
    'New-ErrorObject',
    'ConvertTo-StandardizedResult',
    'Format-DurationString',
    'Test-OSFeatureAvailable',
    'Get-OSSpecificRegistryPath',
    'Get-OSSpecificConfig',
    'Get-GenericHealthScore',
    'Invoke-BloatwareItemRemoval',
    'New-ImpactBasedRecommendations',
    'Invoke-OSAwareConfigMerge'
)

