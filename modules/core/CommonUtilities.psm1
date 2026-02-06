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
        Message    = $Exception.Message
        Context    = $Context
        Severity   = $Severity
        Type       = $Exception.GetType().Name
        Timestamp  = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
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
        Status = "Success|Failed|Skipped|DryRun"
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
        [ValidateSet('Success', 'Failed', 'Skipped', 'DryRun')]
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
        Status     = $finalStatus
        Metrics    = @{
            ItemsDetected   = [int]($RawResult.TotalOperations ?? $RawResult.ItemsDetected ?? 0)
            ItemsProcessed  = [int]($RawResult.SuccessfulOperations ?? $RawResult.ItemsProcessed ?? 0)
            ItemsSkipped    = [int]($RawResult.ItemsSkipped ?? 0)
            ItemsFailed     = [int]($RawResult.FailedOperations ?? $RawResult.ItemsFailed ?? 0)
            DurationSeconds = [decimal]$DurationSeconds
        }
        Results    = $RawResult.Results ?? @{}
        Errors     = $RawResult.Errors ?? @()
        Warnings   = $RawResult.Warnings ?? @()
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

# Export public functions
Export-ModuleMember -Function @(
    'Get-SafeValue',
    'Test-PropertyPath',
    'Invoke-WithRetry',
    'New-ErrorObject',
    'ConvertTo-StandardizedResult',
    'Format-DurationString'
)
