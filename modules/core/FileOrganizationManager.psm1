#Requires -Version 7.0

<#
.SYNOPSIS
    File Organization Manager - Centralized temp_files Management

.DESCRIPTION
    Manages the temp_files directory structure, implements session-based organization,
    handles file cleanup, and provides standardized file operations for all modules.

.NOTES
    Module Type: Core (Infrastructure)
    Dependencies: ConfigManager, LoggingManager
    Author: Windows Maintenance Automation Project
    Version: 2.0.0
#>

using namespace System.Collections.Generic
using namespace System.IO

#region Module Variables

$script:FileOrgContext = @{
    BaseDir = $null
    CurrentSession = $null
    SessionDir = $null
    CleanupPolicy = $null
    DirectoryStructure = @{
        Logs = @('session.log', 'orchestrator.log', 'modules', 'performance')
        Data = @('inventory', 'apps', 'security')
        Reports = @()
        Temp = @()
    }
}

#endregion

#region Public Functions

<#
.SYNOPSIS
    Initializes the file organization system for current session

.DESCRIPTION
    Creates the standardized temp_files directory structure, sets up session
    management, and configures cleanup policies.

.PARAMETER BaseDir
    Base directory for temp_files (usually script root)

.PARAMETER SessionId
    Current session identifier (from LoggingManager)

.EXAMPLE
    Initialize-FileOrganization -BaseDir "C:\Script" -SessionId "20251012-122824"
#>
function Initialize-FileOrganization {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$BaseDir,

        [Parameter(Mandatory)]
        [string]$SessionId
    )

    try {
        # Set up base context
        $script:FileOrgContext.BaseDir = Join-Path $BaseDir 'temp_files'
        $script:FileOrgContext.CurrentSession = $SessionId
        $script:FileOrgContext.SessionDir = Join-Path $script:FileOrgContext.BaseDir "session-$SessionId"

        # Ensure base directory exists
        if (-not (Test-Path $script:FileOrgContext.BaseDir)) {
            New-Item -Path $script:FileOrgContext.BaseDir -ItemType Directory -Force | Out-Null
            Write-Verbose "Created temp_files base directory: $($script:FileOrgContext.BaseDir)"
        }

    # Create session directory structure
    New-SessionDirectoryStructure -SessionPath $script:FileOrgContext.SessionDir

        # Load or create cleanup policy
        Initialize-CleanupPolicy

        # Clean up old sessions based on policy
        Invoke-SessionCleanup

        Write-Information "📁 File organization initialized for session: $SessionId" -InformationAction Continue
        Write-Verbose "Session directory: $($script:FileOrgContext.SessionDir)"

        return $true
    }
    catch {
        Write-Error "Failed to initialize file organization: $_"
        return $false
    }
}

<#
.SYNOPSIS
    Gets the appropriate file path for a specific file type and category

.DESCRIPTION
    Returns standardized file paths based on the organized directory structure.
    Handles different file types (logs, data, reports, temp) and categories.

.PARAMETER FileType
    Type of file: 'Log', 'Data', 'Report', 'Temp'

.PARAMETER Category
    Subcategory within the file type (e.g., 'modules', 'inventory', 'apps')

.PARAMETER FileName
    Name of the file (with or without extension)

.PARAMETER IncludeTimestamp
    Whether to include session timestamp in filename

.EXAMPLE
    $logPath = Get-OrganizedFilePath -FileType 'Log' -Category 'modules' -FileName 'essential-apps.log'
    Returns: temp_files/session-20251012-122824/logs/modules/essential-apps.log

.EXAMPLE
    $dataPath = Get-OrganizedFilePath -FileType 'Data' -Category 'apps' -FileName 'analysis' -IncludeTimestamp
    Returns: temp_files/session-20251012-122824/data/apps/analysis-20251012-122824.json
#>
function Get-OrganizedFilePath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Log', 'Data', 'Report', 'Temp')]
        [string]$FileType,

        [Parameter()]
        [string]$Category,

        [Parameter(Mandatory)]
        [string]$FileName,

        [Parameter()]
        [switch]$IncludeTimestamp
    )

    if (-not $script:FileOrgContext.SessionDir) {
        throw "File organization not initialized. Call Initialize-FileOrganization first."
    }

    # Build base path
    $basePath = switch ($FileType.ToLower()) {
        'log' { Join-Path $script:FileOrgContext.SessionDir 'logs' }
        'data' { Join-Path $script:FileOrgContext.SessionDir 'data' }
        'report' { Join-Path $script:FileOrgContext.SessionDir 'reports' }
        'temp' { Join-Path $script:FileOrgContext.SessionDir 'temp' }
    }

    # Add category if specified
    if ($Category) {
        $basePath = Join-Path $basePath $Category
    }

    # Ensure directory exists
    if (-not (Test-Path $basePath)) {
        New-Item -Path $basePath -ItemType Directory -Force | Out-Null
        Write-Verbose "Created directory: $basePath"
    }

    # Process filename
    $processedFileName = $FileName
    if ($IncludeTimestamp -and $script:FileOrgContext.CurrentSession) {
        $nameWithoutExt = [Path]::GetFileNameWithoutExtension($FileName)
        $extension = [Path]::GetExtension($FileName)
        
        # Add timestamp if not already present
        if ($nameWithoutExt -notmatch '\d{8}-\d{6}$') {
            $processedFileName = "$nameWithoutExt-$($script:FileOrgContext.CurrentSession)$extension"
        }
    }

    # Add default extension for data files if missing
    if ($FileType -eq 'Data' -and [string]::IsNullOrEmpty([Path]::GetExtension($processedFileName))) {
        $processedFileName += '.json'
    }

    return Join-Path $basePath $processedFileName
}

<#
.SYNOPSIS
    Saves data to organized file location with proper formatting

.DESCRIPTION
    Standardized method for saving data files with consistent formatting,
    error handling, and logging integration.

.PARAMETER Data
    Data object to save

.PARAMETER FileType
    Type of file: 'Log', 'Data', 'Report', 'Temp'

.PARAMETER Category
    Subcategory within the file type

.PARAMETER FileName
    Name of the file

.PARAMETER Format
    Output format: 'JSON', 'Text', 'CSV', 'XML'

.EXAMPLE
    Save-OrganizedFile -Data $inventory -FileType 'Data' -Category 'inventory' -FileName 'system-inventory' -Format 'JSON'
#>
function Save-OrganizedFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Data,

        [Parameter(Mandatory)]
        [ValidateSet('Log', 'Data', 'Report', 'Temp')]
        [string]$FileType,

        [Parameter()]
        [string]$Category,

        [Parameter(Mandatory)]
        [string]$FileName,

        [Parameter()]
        [ValidateSet('JSON', 'Text', 'CSV', 'XML')]
        [string]$Format = 'JSON',

        [Parameter()]
        [switch]$IncludeTimestamp
    )

    try {
        # Get organized file path
        $filePath = Get-OrganizedFilePath -FileType $FileType -Category $Category -FileName $FileName -IncludeTimestamp:$IncludeTimestamp

        # Add appropriate extension based on format
        $extension = switch ($Format) {
            'JSON' { '.json' }
            'Text' { '.txt' }
            'CSV' { '.csv' }
            'XML' { '.xml' }
        }

        if (-not $filePath.EndsWith($extension)) {
            $filePath = [Path]::ChangeExtension($filePath, $extension)
        }

        # Save data in specified format
        switch ($Format) {
            'JSON' { 
                $Data | ConvertTo-Json -Depth 10 | Out-File -FilePath $filePath -Encoding UTF8
            }
            'Text' { 
                # Handle both string content and objects
                if ($Data -is [string]) {
                    $Data | Out-File -FilePath $filePath -Encoding UTF8
                } else {
                    $Data | Out-String | Out-File -FilePath $filePath -Encoding UTF8
                }
            }
            'CSV' { 
                $Data | Export-Csv -Path $filePath -NoTypeInformation -Encoding UTF8
            }
            'XML' { 
                $Data | Export-Clixml -Path $filePath -Encoding UTF8
            }
        }

        Write-Verbose "Saved $Format file: $filePath"
        return $filePath
    }
    catch {
        Write-Error "Failed to save organized file: $_"
        return $null
    }
}

<#
.SYNOPSIS
    Gets list of files from previous sessions for cleanup or analysis

.DESCRIPTION
    Retrieves files from previous sessions based on age, type, and other criteria.
    Used for cleanup operations and historical analysis.

.PARAMETER MaxAge
    Maximum age in days for files to include

.PARAMETER FileType
    Filter by file type

.PARAMETER Category
    Filter by category

.EXAMPLE
    $oldFiles = Get-SessionFiles -MaxAge 7 -FileType 'Data'
    Gets data files older than 7 days
#>
function Get-SessionFiles {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter()]
        [int]$MaxAge,

        [Parameter()]
        [ValidateSet('Log', 'Data', 'Report', 'Temp')]
        [string]$FileType,

        [Parameter()]
        [string]$Category
    )

    if (-not $script:FileOrgContext.BaseDir -or -not (Test-Path $script:FileOrgContext.BaseDir)) {
        Write-Warning "temp_files directory not found or not initialized"
        return @()
    }

    $sessionDirs = Get-ChildItem -Path $script:FileOrgContext.BaseDir -Directory | 
                   Where-Object { $_.Name -match '^session-\d{8}-\d{6}$' }

    $files = @()
    foreach ($sessionDir in $sessionDirs) {
        # Skip current session
        if ($sessionDir.Name -eq "session-$($script:FileOrgContext.CurrentSession)") {
            continue
        }

        # Apply age filter
        if ($MaxAge -and $sessionDir.CreationTime -gt (Get-Date).AddDays(-$MaxAge)) {
            continue
        }

        # Build search path
        $searchPath = $sessionDir.FullName
        if ($FileType) {
            $searchPath = Join-Path $searchPath $FileType.ToLower()
            if ($Category) {
                $searchPath = Join-Path $searchPath $Category
            }
        }

        if (Test-Path $searchPath) {
            $sessionFiles = Get-ChildItem -Path $searchPath -Recurse -File
            $files += $sessionFiles | ForEach-Object {
                [PSCustomObject]@{
                    FullName = $_.FullName
                    Name = $_.Name
                    Directory = $_.Directory.Name
                    Session = $sessionDir.Name
                    LastWriteTime = $_.LastWriteTime
                    Size = $_.Length
                    Type = $FileType
                    Category = $Category
                }
            }
        }
    }

    return $files
}

#endregion

#region Private Functions

function New-SessionDirectoryStructure {
    [CmdletBinding()]
    param([string]$SessionPath)

    # Create main session directory
    if (-not (Test-Path $SessionPath)) {
        New-Item -Path $SessionPath -ItemType Directory -Force | Out-Null
    }

    # Create standard subdirectories
    $directories = @(
        'logs',
        'logs\modules',
        'logs\performance',
        'data',
        'data\inventory',
        'data\apps',
        'data\security',
        'reports',
        'temp'
    )

    foreach ($dir in $directories) {
        $fullPath = Join-Path $SessionPath $dir
        if (-not (Test-Path $fullPath)) {
            New-Item -Path $fullPath -ItemType Directory -Force | Out-Null
        }
    }

    Write-Verbose "Created session directory structure: $SessionPath"
}

function Initialize-CleanupPolicy {
    [CmdletBinding()]
    param()

    $policyPath = Join-Path $script:FileOrgContext.BaseDir 'cleanup-policy.json'
    
    if (Test-Path $policyPath) {
        try {
            $script:FileOrgContext.CleanupPolicy = Get-Content $policyPath | ConvertFrom-Json
            Write-Verbose "Loaded cleanup policy from: $policyPath"
        }
        catch {
            Write-Warning "Failed to load cleanup policy, using defaults"
            $script:FileOrgContext.CleanupPolicy = Get-DefaultCleanupPolicy
        }
    }
    else {
        $script:FileOrgContext.CleanupPolicy = Get-DefaultCleanupPolicy
        $script:FileOrgContext.CleanupPolicy | ConvertTo-Json -Depth 5 | Out-File -FilePath $policyPath -Encoding UTF8
        Write-Verbose "Created default cleanup policy: $policyPath"
    }
}

function Get-DefaultCleanupPolicy {
    return @{
        RetentionPeriods = @{
            Sessions = 30        # Keep sessions for 30 days
            Logs = 14           # Keep detailed logs for 14 days
            Data = 7            # Keep data files for 7 days
            Reports = 90        # Keep reports for 90 days
            Temp = 1            # Keep temp files for 1 day
        }
        MaxSessions = 10        # Maximum number of sessions to keep
        CleanupOnStartup = $true
        PreserveFinalReports = $true
    }
}

function Invoke-SessionCleanup {
    [CmdletBinding()]
    param()

    if (-not $script:FileOrgContext.CleanupPolicy.CleanupOnStartup) {
        return
    }

    try {
        $policy = $script:FileOrgContext.CleanupPolicy
        $sessionDirs = Get-ChildItem -Path $script:FileOrgContext.BaseDir -Directory | 
                      Where-Object { $_.Name -match '^session-\d{8}-\d{6}$' } |
                      Sort-Object Name -Descending

        $cleanupCount = 0

        # Remove old sessions based on max count
        if ($sessionDirs.Count -gt $policy.MaxSessions) {
            $excessSessions = $sessionDirs | Select-Object -Skip $policy.MaxSessions
            foreach ($session in $excessSessions) {
                Remove-Item -Path $session.FullName -Recurse -Force -ErrorAction SilentlyContinue
                $cleanupCount++
            }
        }

        # Remove sessions older than retention period
        $cutoffDate = (Get-Date).AddDays(-$policy.RetentionPeriods.Sessions)
        $oldSessions = $sessionDirs | Where-Object { $_.CreationTime -lt $cutoffDate }
        foreach ($session in $oldSessions) {
            if ($policy.PreserveFinalReports) {
                # Move final reports to base directory before cleanup
                $reportsDir = Join-Path $session.FullName 'reports'
                if (Test-Path $reportsDir) {
                    $reports = Get-ChildItem -Path $reportsDir -Filter "*maintenance-report*"
                    foreach ($report in $reports) {
                        $archiveName = "$($session.Name)-$($report.Name)"
                        $archivePath = Join-Path $script:FileOrgContext.BaseDir $archiveName
                        Copy-Item -Path $report.FullName -Destination $archivePath -Force -ErrorAction SilentlyContinue
                    }
                }
            }
            
            Remove-Item -Path $session.FullName -Recurse -Force -ErrorAction SilentlyContinue
            $cleanupCount++
        }

        if ($cleanupCount -gt 0) {
            Write-Information "🧹 Cleaned up $cleanupCount old session directories" -InformationAction Continue
        }
    }
    catch {
        Write-Warning "Session cleanup failed: $_"
    }
}

#endregion

#region Export Module Members

Export-ModuleMember -Function @(
    'Initialize-FileOrganization',
    'Get-OrganizedFilePath',
    'Save-OrganizedFile',
    'Get-SessionFiles'
)

#endregion