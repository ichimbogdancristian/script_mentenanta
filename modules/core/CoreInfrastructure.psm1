#Requires -Version 7.0

<#
.SYNOPSIS
    Core Infrastructure Module - Consolidated Configuration, Logging, and File Organization

.DESCRIPTION
    Consolidated core infrastructure module that provides configuration management,
    structured logging, and file organization capabilities in a single module.
    Combines the functionality of ConfigManager, LoggingManager, and FileOrganizationManager.

.NOTES
    Module Type: Core Infrastructure (Consolidated)
    Dependencies: JSON files in config/ directory
    Author: Windows Maintenance Automation Project
    Version: 2.0.0 (Consolidated)
#>

using namespace System.Collections.Generic
using namespace System.IO

#region Module Variables

# Configuration Management Variables
$script:LoadedConfig = $null
$script:ConfigPaths = @{}
$script:BloatwareLists = @{}
$script:EssentialApps = @{}

# Logging Management Variables
$script:LoggingContext = @{
    SessionId          = [guid]::NewGuid().ToString()
    StartTime          = Get-Date
    LogPath            = $null
    Config             = $null
    LogBuffer          = [List[hashtable]]::new()
    PerformanceMetrics = @{}
}

# File Organization Variables
$script:FileOrgContext = @{
    BaseDir            = $null
    CurrentSession     = $null
    DirectoryStructure = @{
        Logs    = @('session.log', 'orchestrator.log', 'modules', 'performance')
        Data    = @('inventory', 'apps', 'security')
        Reports = @()
        Temp    = @()
    }
}

#endregion

#region Configuration Management Functions

<#
.SYNOPSIS
    Initializes the configuration system

.DESCRIPTION
    Sets up configuration paths and performs initial validation of config directory structure.

.PARAMETER ConfigRootPath
    Root path to the config directory

.EXAMPLE
    Initialize-ConfigSystem -ConfigRootPath "C:\MaintenanceScript\config"
#>
function Initialize-ConfigSystem {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({ Test-Path $_ -PathType Container })]
        [string]$ConfigRootPath
    )

    Write-Verbose "Initializing configuration system with root path: $ConfigRootPath"

    if (-not (Test-Path $ConfigRootPath)) {
        throw "Configuration root path does not exist: $ConfigRootPath"
    }

    # Set up configuration paths
    $script:ConfigPaths = @{
        Root          = $ConfigRootPath
        MainConfig    = Join-Path $ConfigRootPath 'main-config.json'
        LoggingConfig = Join-Path $ConfigRootPath 'logging-config.json'
        BloatwareList = Join-Path $ConfigRootPath 'bloatware-list.json'
        EssentialApps = Join-Path $ConfigRootPath 'essential-apps.json'
    }

    # Validate required configuration files exist
    $requiredFiles = @('main-config.json', 'logging-config.json')
    foreach ($file in $requiredFiles) {
        $filePath = Join-Path $ConfigRootPath $file
        if (-not (Test-Path $filePath)) {
            throw "Required configuration file not found: $filePath"
        }
    }

    # Load and validate JSON syntax
    try {
        $script:LoadedConfig = Get-Content $script:ConfigPaths.MainConfig | ConvertFrom-Json
        Write-Verbose "Configuration system initialized successfully"
    }
    catch {
        throw "Failed to load main configuration: $($_.Exception.Message)"
    }
}

<#
.SYNOPSIS
    Gets the main configuration object
#>
function Get-MainConfig {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    if (-not $script:LoadedConfig) {
        throw "Configuration system not initialized. Call Initialize-ConfigSystem first."
    }
    
    return $script:LoadedConfig
}

<#
.SYNOPSIS
    Gets bloatware list by category
#>
function Get-BloatwareList {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter()]
        [ValidateSet('OEM', 'Windows', 'Gaming', 'Security', 'all')]
        [string]$Category = 'all'
    )

    if (-not (Test-Path $script:ConfigPaths.BloatwareList)) {
        Write-Warning "Bloatware list file not found: $($script:ConfigPaths.BloatwareList)"
        return @()
    }

    try {
        $bloatwareData = Get-Content $script:ConfigPaths.BloatwareList | ConvertFrom-Json
        
        if ($Category -eq 'all') {
            return $bloatwareData
        }
        else {
            return $bloatwareData | Where-Object { $_.category -eq $Category }
        }
    }
    catch {
        Write-Error "Failed to load bloatware list: $($_.Exception.Message)"
        return @()
    }
}

<#
.SYNOPSIS
    Gets essential apps list
#>
function Get-UnifiedEssentialAppsList {
    [CmdletBinding()]
    [OutputType([array])]
    param()

    if (-not (Test-Path $script:ConfigPaths.EssentialApps)) {
        Write-Warning "Essential apps list file not found: $($script:ConfigPaths.EssentialApps)"
        return @()
    }

    try {
        $essentialApps = Get-Content $script:ConfigPaths.EssentialApps | ConvertFrom-Json
        return $essentialApps
    }
    catch {
        Write-Error "Failed to load essential apps list: $($_.Exception.Message)"
        return @()
    }
}

#endregion

#region Logging Management Functions

<#
.SYNOPSIS
    Gets the logging configuration from JSON file or returns defaults
#>
function Get-LoggingConfiguration {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    $configPath = $script:ConfigPaths.LoggingConfig

    if (-not (Test-Path $configPath)) {
        Write-Verbose "Logging configuration file not found. Using defaults."
        return @{
            logLevel                  = 'INFO'
            enableConsoleLog          = $true
            enableFileLog             = $true
            enablePerformanceTracking = $true
            logBufferSize             = 1000
        }
    }

    try {
        Write-Verbose "Loading logging configuration from: $configPath"
        $configJson = Get-Content $configPath -Raw -ErrorAction Stop
        $config = $configJson | ConvertFrom-Json -ErrorAction Stop
        
        # Convert to hashtable
        $configHash = @{}
        foreach ($property in $config.PSObject.Properties) {
            $configHash[$property.Name] = $property.Value
        }
        
        return $configHash
    }
    catch {
        Write-Warning "Failed to load logging configuration: $($_.Exception.Message). Using defaults."
        return @{
            logLevel                  = 'INFO'
            enableConsoleLog          = $true
            enableFileLog             = $true
            enablePerformanceTracking = $true
            logBufferSize             = 1000
        }
    }
}

<#
.SYNOPSIS
    Initializes the logging system
#>
function Initialize-LoggingSystem {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$LoggingConfig,

        [Parameter()]
        [string]$BaseLogPath
    )

    try {
        Write-Verbose "Initializing logging system..."
        
        # Store configuration
        $script:LoggingContext.Config = $LoggingConfig
        
        # Set up log path
        if ($BaseLogPath) {
            $script:LoggingContext.LogPath = $BaseLogPath
        }
        else {
            $script:LoggingContext.LogPath = Join-Path (Get-Location) 'maintenance.log'
        }

        Write-Verbose "Logging system initialized with path: $($script:LoggingContext.LogPath)"
        return $true
    }
    catch {
        Write-Error "Failed to initialize logging system: $($_.Exception.Message)"
        throw
    }
}

<#
.SYNOPSIS
    Writes a structured log entry
#>
function Write-LogEntry {
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
        [hashtable]$Data = @{}
    )

    try {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
        $sessionId = $script:LoggingContext.SessionId
        
        $logEntry = @{
            Timestamp = $timestamp
            Level     = $Level
            Component = $Component
            Message   = $Message
            SessionId = $sessionId
            Data      = $Data
        }

        # Add to buffer
        $script:LoggingContext.LogBuffer.Add($logEntry)

        # Format for console and file
        $formattedMessage = "[$timestamp] [$Level] [$Component] $Message"
        
        # Output to console based on level
        switch ($Level) {
            'DEBUG' { Write-Verbose $formattedMessage }
            'INFO' { Write-Information $formattedMessage -InformationAction Continue }
            'WARN' { Write-Warning $formattedMessage }
            'ERROR' { Write-Error $formattedMessage }
            'FATAL' { Write-Error $formattedMessage }
        }

        # Write to log file if available
        if ($script:LoggingContext.LogPath) {
            $formattedMessage | Out-File -FilePath $script:LoggingContext.LogPath -Append -Encoding UTF8
        }

    }
    catch {
        Write-Warning "Failed to write log entry: $($_.Exception.Message)"
    }
}

<#
.SYNOPSIS
    Starts performance tracking for an operation
#>
function Start-PerformanceTracking {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string]$OperationName,

        [Parameter(Mandatory)]
        [string]$Component
    )

    $perfId = [guid]::NewGuid().ToString()
    $perfContext = @{
        Id            = $perfId
        OperationName = $OperationName
        Component     = $Component
        StartTime     = Get-Date
        StartTicks    = [System.Diagnostics.Stopwatch]::GetTimestamp()
    }

    $script:LoggingContext.PerformanceMetrics[$perfId] = $perfContext
    
    Write-LogEntry -Level 'DEBUG' -Component $Component -Message "Started operation: $OperationName" -Data @{ PerformanceId = $perfId }
    
    return $perfContext
}

<#
.SYNOPSIS
    Completes performance tracking for an operation
#>
function Complete-PerformanceTracking {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Context,

        [Parameter(Mandatory)]
        [ValidateSet('Success', 'Failed', 'Cancelled')]
        [string]$Status,

        [Parameter()]
        [string]$ErrorMessage,

        [Parameter()]
        [int]$ResultCount = 0
    )

    try {
        $endTime = Get-Date
        $endTicks = [System.Diagnostics.Stopwatch]::GetTimestamp()
        $duration = [TimeSpan]::FromTicks($endTicks - $Context.StartTicks)
        
        $Context.EndTime = $endTime
        $Context.Duration = $duration
        $Context.Status = $Status
        $Context.ResultCount = $ResultCount
        
        if ($ErrorMessage) {
            $Context.ErrorMessage = $ErrorMessage
        }

        $logData = @{
            PerformanceId = $Context.Id
            Duration      = $duration.TotalMilliseconds
            Status        = $Status
            ResultCount   = $ResultCount
        }

        Write-LogEntry -Level 'INFO' -Component $Context.Component -Message "Completed operation: $($Context.OperationName) in $([math]::Round($duration.TotalMilliseconds, 2))ms" -Data $logData

    }
    catch {
        Write-Warning "Failed to complete performance tracking: $($_.Exception.Message)"
    }
}

#endregion

#region File Organization Functions

<#
.SYNOPSIS
    Initializes the file organization system
#>
function Initialize-FileOrganization {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$BaseDirectory
    )

    try {
        $script:FileOrgContext.BaseDir = $BaseDirectory
        
        # Create directory structure
        $directories = @('logs', 'data', 'temp', 'reports')
        foreach ($dir in $directories) {
            $fullPath = Join-Path $BaseDirectory $dir
            if (-not (Test-Path $fullPath)) {
                New-Item -Path $fullPath -ItemType Directory -Force | Out-Null
                Write-Verbose "Created directory: $fullPath"
            }
        }

        Write-Verbose "File organization initialized with base directory: $BaseDirectory"
    }
    catch {
        Write-Error "Failed to initialize file organization: $($_.Exception.Message)"
        throw
    }
}

<#
.SYNOPSIS
    Gets a session-specific file path
#>
function Get-SessionPath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('logs', 'data', 'temp', 'reports')]
        [string]$Category,

        [Parameter()]
        [string]$SubCategory,

        [Parameter(Mandatory)]
        [string]$FileName
    )

    if (-not $script:FileOrgContext.BaseDir) {
        throw "File organization not initialized. Call Initialize-FileOrganization first."
    }

    $categoryPath = Join-Path $script:FileOrgContext.BaseDir $Category
    
    if ($SubCategory) {
        $categoryPath = Join-Path $categoryPath $SubCategory
        # Ensure subcategory directory exists
        if (-not (Test-Path $categoryPath)) {
            New-Item -Path $categoryPath -ItemType Directory -Force | Out-Null
        }
    }
    
    return Join-Path $categoryPath $FileName
}

<#
.SYNOPSIS
    Saves session data to organized file structure
#>
function Save-SessionData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('logs', 'data', 'temp', 'reports')]
        [string]$Category,

        [Parameter(Mandatory)]
        [object]$Data,

        [Parameter(Mandatory)]
        [string]$FileName
    )

    try {
        $filePath = Get-SessionPath -Category $Category -FileName $FileName
        
        if ($Data -is [string]) {
            $Data | Out-File -FilePath $filePath -Encoding UTF8
        }
        else {
            $Data | ConvertTo-Json -Depth 10 | Out-File -FilePath $filePath -Encoding UTF8
        }
        
        Write-Verbose "Saved session data to: $filePath"
        return $filePath
    }
    catch {
        Write-Error "Failed to save session data: $($_.Exception.Message)"
        throw
    }
}

<#
.SYNOPSIS
    Gets session data from organized file structure
#>
function Get-SessionData {
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('logs', 'data', 'temp', 'reports')]
        [string]$Category,

        [Parameter(Mandatory)]
        [string]$FileName
    )

    try {
        $filePath = Get-SessionPath -Category $Category -FileName $FileName
        
        if (-not (Test-Path $filePath)) {
            Write-Warning "Session data file not found: $filePath"
            return $null
        }

        $content = Get-Content $filePath -Raw
        
        # Try to parse as JSON, fallback to raw content
        try {
            return $content | ConvertFrom-Json
        }
        catch {
            return $content
        }
    }
    catch {
        Write-Error "Failed to get session data: $($_.Exception.Message)"
        return $null
    }
}

#endregion

#region Compatibility Functions for Orchestrator

<#
.SYNOPSIS
    Gets bloatware configuration in the format expected by orchestrator (compatibility wrapper)
#>
function Get-BloatwareConfiguration {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    try {
        $bloatwareData = Get-BloatwareList -Category 'all'
        
        # Return in expected format with categorized data
        $result = @{
            all = $bloatwareData
        }
        
        # Group by category for compatibility
        $categories = @('OEM', 'Windows', 'Gaming', 'Security')
        foreach ($category in $categories) {
            $categoryData = $bloatwareData | Where-Object { $_.category -eq $category }
            if ($categoryData) {
                $result[$category.ToLower()] = $categoryData
            }
        }
        
        return $result
    }
    catch {
        Write-LogEntry -Level 'ERROR' -Component 'CORE-INFRASTRUCTURE' -Message "Failed to load bloatware configuration: $($_.Exception.Message)"
        return @{ all = @() }
    }
}

<#
.SYNOPSIS
    Gets essential apps configuration in the format expected by orchestrator (compatibility wrapper)
#>
function Get-EssentialAppsConfiguration {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    try {
        $essentialApps = Get-UnifiedEssentialAppsList
        
        # Return in expected format with categorized data
        $result = @{
            all = $essentialApps
        }
        
        # Group by category for compatibility
        $categories = @('productivity', 'development', 'multimedia', 'utilities', 'security')
        foreach ($category in $categories) {
            $categoryData = $essentialApps | Where-Object { $_.category -eq $category }
            if ($categoryData) {
                $result[$category] = $categoryData
            }
        }
        
        return $result
    }
    catch {
        Write-LogEntry -Level 'ERROR' -Component 'CORE-INFRASTRUCTURE' -Message "Failed to load essential apps configuration: $($_.Exception.Message)"
        return @{ all = @() }
    }
}

#endregion

#region Save-OrganizedFile Function
function Save-OrganizedFile {
    <#
    .SYNOPSIS
        Saves content to a file in an organized directory structure
    .DESCRIPTION
        Creates an organized file with proper directory structure and content
    .PARAMETER Content
        The content to save to the file
    .PARAMETER FilePath
        The full path where to save the file
    .PARAMETER Category
        Optional category for session-based organization
    .PARAMETER FileName
        Optional filename for session-based organization
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Content,

        [Parameter(ParameterSetName = 'DirectPath', Mandatory)]
        [string]$FilePath,

        [Parameter(ParameterSetName = 'SessionPath')]
        [ValidateSet('logs', 'data', 'temp', 'reports')]
        [string]$Category,

        [Parameter(ParameterSetName = 'SessionPath')]
        [string]$FileName
    )

    try {
        # Determine the target path
        if ($PSCmdlet.ParameterSetName -eq 'SessionPath') {
            $targetPath = Get-SessionPath -Category $Category -FileName $FileName
        }
        else {
            $targetPath = $FilePath
        }

        # Ensure directory exists
        $directory = Split-Path -Parent $targetPath
        if (-not (Test-Path $directory)) {
            New-Item -Path $directory -ItemType Directory -Force | Out-Null
        }

        # Save the content
        $Content | Out-File -FilePath $targetPath -Encoding UTF8 -Force

        Write-LogEntry -Level 'DEBUG' -Component 'FILE-ORGANIZATION' -Message "File saved successfully" -Data @{
            TargetPath    = $targetPath
            ContentLength = $Content.Length
        }

        return @{
            Success  = $true
            FilePath = $targetPath
            Size     = $Content.Length
        }
    }
    catch {
        Write-LogEntry -Level 'ERROR' -Component 'FILE-ORGANIZATION' -Message "Failed to save file" -Data @{
            TargetPath = $targetPath
            Error      = $_.Exception.Message
        }
        
        return @{
            Success = $false
            Error   = $_.Exception.Message
        }
    }
}
#endregion

# Export all public functions
Export-ModuleMember -Function @(
    # Configuration Management
    'Initialize-ConfigSystem',
    'Get-MainConfig',
    'Get-BloatwareList',
    'Get-UnifiedEssentialAppsList',
    'Get-BloatwareConfiguration',
    'Get-EssentialAppsConfiguration',
    
    # Logging Management
    'Get-LoggingConfiguration',
    'Initialize-LoggingSystem',
    'Write-LogEntry',
    'Start-PerformanceTracking',
    'Complete-PerformanceTracking',
    
    # File Organization
    'Initialize-FileOrganization',
    'Get-SessionPath',
    'Save-SessionData',
    'Get-SessionData',
    'Save-OrganizedFile'
)