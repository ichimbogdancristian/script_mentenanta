#Requires -Version 7.0

<#
.SYNOPSIS
    Common Utilities Module - Shared Fallback Functions

.DESCRIPTION
    Provides shared fallback functions for modules when CoreInfrastructure is not available.
    Eliminates duplication of fallback functions across Type1 and Type2 modules.

.NOTES
    Module Type: Core Utilities
    Dependencies: None (standalone fallbacks)
    Author: Windows Maintenance Automation Project
    Version: 1.0.0
#>

#region Shared Fallback Functions

<#
.SYNOPSIS
    Fallback logging function when CoreInfrastructure is not available
#>
function Write-LogEntryFallback {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('DEBUG', 'INFO', 'WARN', 'ERROR', 'FATAL', 'SUCCESS')]
        [string]$Level,

        [Parameter(Mandatory)]
        [string]$Component,

        [Parameter(Mandatory)]
        [string]$Message,

        [Parameter()]
        [hashtable]$Data = @{},
        
        [Parameter()]
        [string]$LogPath  # Optional specific log file path
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
    $logMessage = "[$timestamp] [$Level] [$Component] $Message"
    
    # Output to console based on level
    switch ($Level) {
        'DEBUG' { Write-Verbose $logMessage }
        'INFO' { Write-Information $logMessage -InformationAction Continue }
        'WARN' { Write-Warning $logMessage }
        'ERROR' { Write-Error $logMessage }
        'FATAL' { Write-Error $logMessage }
        'SUCCESS' { Write-Information $logMessage -InformationAction Continue }
    }

    # Write to specific log file if provided
    if ($LogPath) {
        try {
            # Ensure the directory exists
            $logDir = Split-Path -Parent $LogPath
            if (-not (Test-Path $logDir)) {
                New-Item -Path $logDir -ItemType Directory -Force | Out-Null
            }
            $logMessage | Out-File -FilePath $LogPath -Append -Encoding UTF8
        }
        catch {
            Write-Warning "Failed to write to specific log path $LogPath`: $($_.Exception.Message)"
        }
    }
}

<#
.SYNOPSIS
    Fallback session path function when CoreInfrastructure is not available
#>
function Get-SessionPathFallback {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Category,
        
        [Parameter()]
        [string]$SubCategory,
        
        [Parameter()]
        [string]$FileName
    )
    
    # Try to construct proper path using environment variables set by orchestrator
    $tempRoot = if ($env:MAINTENANCE_TEMP_ROOT) { 
        $env:MAINTENANCE_TEMP_ROOT 
    }
    else { 
        Join-Path $env:TEMP 'maintenance' 
    }
    
    if ($Category -and (Test-Path $tempRoot)) {
        $categoryPath = Join-Path $tempRoot $Category
        if (-not (Test-Path $categoryPath)) {
            try { 
                New-Item -Path $categoryPath -ItemType Directory -Force | Out-Null 
            }
            catch {
                Write-Warning "Failed to create category directory: $categoryPath"
            }
        }
        
        if ($SubCategory) {
            $categoryPath = Join-Path $categoryPath $SubCategory
            if (-not (Test-Path $categoryPath)) {
                try { 
                    New-Item -Path $categoryPath -ItemType Directory -Force | Out-Null 
                }
                catch {
                    Write-Warning "Failed to create subcategory directory: $categoryPath"
                }
            }
        }
        
        return Join-Path $categoryPath $FileName
    }
    else {
        Write-Warning "Session path unavailable - using current directory fallback"
        return $FileName
    }
}

<#
.SYNOPSIS
    Fallback configuration function when CoreInfrastructure is not available
#>
function Get-ConfigurationFallback {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$ConfigType = 'General'
    )
    
    Write-Warning "CoreInfrastructure not available - using fallback configuration for $ConfigType"
    return @{
        Fallback   = $true
        ConfigType = $ConfigType
        LoadedAt   = Get-Date
    }
}

<#
.SYNOPSIS
    Initializes fallback functions if CoreInfrastructure functions are not available
#>
function Initialize-FallbackFunctions {
    [CmdletBinding()]
    param()
    
    $functionsInitialized = 0
    
    # Initialize Write-LogEntry fallback - only if CoreInfrastructure function is not available
    $existingLogFunction = Get-Command 'Write-LogEntry' -ErrorAction SilentlyContinue
    if (-not $existingLogFunction) {
        # No Write-LogEntry exists, create alias to our fallback
        Set-Alias -Name 'Write-LogEntry' -Value 'Write-LogEntryFallback' -Scope Global -Force
        $functionsInitialized++
        Write-Verbose "Created Write-LogEntry alias to Write-LogEntryFallback"
    }
    elseif ($existingLogFunction.CommandType -eq 'Function' -and $existingLogFunction.Source -eq 'CoreInfrastructure') {
        # CoreInfrastructure function exists, don't override it
        Write-Verbose "Write-LogEntry function from CoreInfrastructure detected, skipping fallback initialization"
    }
    elseif ($existingLogFunction.CommandType -eq 'Alias' -and $existingLogFunction.ResolvedCommandName -eq 'Write-LogEntryFallback') {
        # Already using our fallback, that's fine
        Write-Verbose "Write-LogEntry fallback already active"
    }
    else {
        Write-Verbose "Write-LogEntry already available from $($existingLogFunction.Source), type: $($existingLogFunction.CommandType)"
    }

    if (-not (Get-Command 'Write-DetailedLog' -ErrorAction SilentlyContinue)) {
        $detailedLogFallback = {
            param(
                [Parameter(Mandatory = $true)][string]$Level,
                [Parameter(Mandatory = $true)][string]$Component,
                [Parameter(Mandatory = $true)][string]$Message,
                [hashtable]$Data,
                [string]$OpId,
                [System.Management.Automation.ErrorRecord]$Exception
            )

            $normalizedLevel = ($Level ?? 'INFO').ToUpperInvariant()
            if ($normalizedLevel -eq 'WARNING') { $normalizedLevel = 'WARN' }
            elseif ($normalizedLevel -eq 'FATAL') { $normalizedLevel = 'CRITICAL' }

            if ($null -eq $Data) {
                $Data = @{}
            }
            elseif ($Data -isnot [hashtable]) {
                $Data = @{ Value = $Data }
            }

            if ($Exception) {
                $Data['ExceptionMessage'] = $Exception.Exception.Message
                $Data['ExceptionType'] = $Exception.Exception.GetType().FullName
            }

            Write-LogEntry -Level $normalizedLevel -Component $Component -Message $Message -Data $Data -OperationId $OpId
        }.GetNewClosure()

        Set-Item -Path 'function:global:Write-DetailedLog' -Value $detailedLogFallback -Force
        $functionsInitialized++
        Write-Verbose "Created Write-DetailedLog fallback function"
    }
    
    # Initialize Get-SessionPath fallback
    if (-not (Get-Command 'Get-SessionPath' -ErrorAction SilentlyContinue)) {
        Set-Alias -Name 'Get-SessionPath' -Value 'Get-SessionPathFallback' -Scope Global -Force
        $functionsInitialized++
    }
    
    # Initialize common configuration fallbacks
    $configFunctions = @(
        'Get-BloatwareConfiguration',
        'Get-EssentialAppsConfiguration',
        'Get-BloatwareList',
        'Get-UnifiedEssentialAppsList'
    )
    
    foreach ($funcName in $configFunctions) {
        if (-not (Get-Command $funcName -ErrorAction SilentlyContinue)) {
            # Create a dynamic function that calls the generic fallback
            $scriptBlock = {
                param($Category)
                Get-ConfigurationFallback -ConfigType $funcName
            }.GetNewClosure()
            
            Set-Item -Path "function:global:$funcName" -Value $scriptBlock -Force
            $functionsInitialized++
        }
    }
    
    if ($functionsInitialized -gt 0) {
        Write-Information "Initialized $functionsInitialized fallback functions" -InformationAction Continue
    }
    
    return $functionsInitialized
}

<#
.SYNOPSIS
    Standardized performance tracking wrapper with error handling
#>
function Invoke-WithPerformanceTracking {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$OperationName,
        
        [Parameter(Mandatory)]
        [string]$Component,
        
        [Parameter(Mandatory)]
        [ScriptBlock]$ScriptBlock,
        
        [Parameter()]
        [hashtable]$Parameters = @{}
    )
    
    $perfContext = $null
    try {
        # Try to start performance tracking if available
        if (Get-Command 'Start-PerformanceTracking' -ErrorAction SilentlyContinue) {
            $perfContext = Start-PerformanceTracking -OperationName $OperationName -Component $Component
        }
        
        # Execute the operation
        $result = & $ScriptBlock @Parameters
        
        # Complete performance tracking on success
        if ($perfContext -and (Get-Command 'Complete-PerformanceTracking' -ErrorAction SilentlyContinue)) {
            Complete-PerformanceTracking -Context $perfContext -Status 'Success'
        }
        
        return $result
    }
    catch {
        $errorMsg = "Failed to execute $OperationName`: $($_.Exception.Message)"
        
        # Complete performance tracking on failure
        if ($perfContext -and (Get-Command 'Complete-PerformanceTracking' -ErrorAction SilentlyContinue)) {
            Complete-PerformanceTracking -Context $perfContext -Status 'Failed' -ErrorMessage $errorMsg
        }
        
        # Re-throw the error
        throw
    }
}

#endregion

#region Error Handling Utilities

<#
.SYNOPSIS
    Standardized error handling wrapper for Type2 module operations

.DESCRIPTION
    Provides consistent error handling, logging, and user feedback for Type2 module operations
#>
function Invoke-WithErrorHandling {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock,
        
        [Parameter(Mandatory)]
        [string]$OperationName,
        
        [Parameter(Mandatory)]
        [string]$ComponentName,
        
        [Parameter()]
        [hashtable]$OperationData = @{},
        
        [Parameter()]
        [string]$LogPath,
        
        [Parameter()]
        [switch]$ContinueOnError,
        
        [Parameter()]
        [string]$FallbackMessage = "Operation completed with warnings"
    )
    
    $result = @{
        Success  = $false
        Error    = $null
        Data     = $null
        Duration = 0
    }
    
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    
    try {
        Write-LogEntry -Level 'INFO' -Component $ComponentName -Message "Starting $OperationName" -Data $OperationData -LogPath $LogPath
        
        $result.Data = & $ScriptBlock
        $result.Success = $true
        
        Write-LogEntry -Level 'INFO' -Component $ComponentName -Message "Successfully completed $OperationName" -LogPath $LogPath
    }
    catch {
        $result.Error = $_
        $result.Success = $false
        
        $errorData = @{
            Operation  = $OperationName
            Error      = $_.Exception.Message
            StackTrace = $_.ScriptStackTrace
        } + $OperationData
        
        Write-LogEntry -Level 'ERROR' -Component $ComponentName -Message "Failed to complete $OperationName`: $($_.Exception.Message)" -Data $errorData -LogPath $LogPath
        
        if (-not $ContinueOnError) {
            throw $_
        }
        else {
            Write-LogEntry -Level 'WARN' -Component $ComponentName -Message $FallbackMessage -LogPath $LogPath
        }
    }
    finally {
        $stopwatch.Stop()
        $result.Duration = $stopwatch.ElapsedMilliseconds
        
        Write-LogEntry -Level 'DEBUG' -Component $ComponentName -Message "$OperationName completed in $($result.Duration)ms" -LogPath $LogPath
    }
    
    return $result
}

<#
.SYNOPSIS
    Standardized validation wrapper for Type2 module prerequisites

.DESCRIPTION
    Validates common prerequisites like admin rights, module availability, and configuration
#>
function Test-ModulePrerequisites {
    [CmdletBinding()]
    param(
        [Parameter()]
        [switch]$RequireAdminRights,
        
        [Parameter()]
        [string[]]$RequiredModules = @(),
        
        [Parameter()]
        [string[]]$RequiredCommands = @(),
        
        [Parameter()]
        [hashtable]$RequiredPaths = @{},
        
        [Parameter()]
        [string]$ComponentName,
        
        [Parameter()]
        [string]$LogPath
    )
    
    $validationResults = @{
        Success  = $true
        Failures = @()
    }
    
    try {
        # Check admin rights if required
        if ($RequireAdminRights) {
            $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
            if (-not $isAdmin) {
                $validationResults.Failures += "Administrator privileges required"
                $validationResults.Success = $false
            }
        }
        
        # Check required modules
        foreach ($module in $RequiredModules) {
            if (-not (Get-Module -Name $module -ListAvailable)) {
                $validationResults.Failures += "Required module not available: $module"
                $validationResults.Success = $false
            }
        }
        
        # Check required commands
        foreach ($command in $RequiredCommands) {
            if (-not (Get-Command -Name $command -ErrorAction SilentlyContinue)) {
                $validationResults.Failures += "Required command not available: $command"  
                $validationResults.Success = $false
            }
        }
        
        # Check required paths
        foreach ($pathName in $RequiredPaths.Keys) {
            $path = $RequiredPaths[$pathName]
            if (-not (Test-Path $path)) {
                $validationResults.Failures += "Required path not found: $pathName ($path)"
                $validationResults.Success = $false
            }
        }
        
        # Log results
        if ($validationResults.Success) {
            Write-LogEntry -Level 'INFO' -Component $ComponentName -Message "All prerequisites validated successfully" -LogPath $LogPath
        }
        else {
            Write-LogEntry -Level 'ERROR' -Component $ComponentName -Message "Prerequisites validation failed" -Data @{ Failures = $validationResults.Failures } -LogPath $LogPath
        }
    }
    catch {
        $validationResults.Success = $false
        $validationResults.Failures += "Prerequisite validation error: $($_.Exception.Message)"
        Write-LogEntry -Level 'ERROR' -Component $ComponentName -Message "Prerequisites validation error: $_" -LogPath $LogPath
    }
    
    return $validationResults
}

<#
.SYNOPSIS
    Standardized result object creation for Type2 modules

.DESCRIPTION
    Creates consistent result objects for Type2 module operations
#>
function New-ModuleResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ModuleName,
        
        [Parameter()]
        [bool]$Success = $true,
        
        [Parameter()]
        [int]$ItemsDetected = 0,
        
        [Parameter()]
        [int]$ItemsProcessed = 0,
        
        [Parameter()]
        [string]$Status = 'Completed',
        
        [Parameter()]
        [string]$Message,
        
        [Parameter()]
        [hashtable]$Data = @{},
        
        [Parameter()]
        [string[]]$Errors = @(),
        
        [Parameter()]
        [double]$Duration = 0
    )
    
    return @{
        ModuleName     = $ModuleName
        Success        = $Success
        Status         = $Status
        Message        = $Message
        ItemsDetected  = $ItemsDetected
        ItemsProcessed = $ItemsProcessed
        Duration       = $Duration
        Timestamp      = Get-Date
        Data           = $Data
        Errors         = $Errors
    }
}

#endregion Error Handling Utilities

# Export functions for direct use
Export-ModuleMember -Function @(
    'Write-LogEntryFallback',
    'Get-SessionPathFallback', 
    'Get-ConfigurationFallback',
    'Initialize-FallbackFunctions',
    'Invoke-WithPerformanceTracking',
    'Invoke-WithErrorHandling',
    'Test-ModulePrerequisites',
    'New-ModuleResult'
)