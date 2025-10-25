#Requires -Version 7.0

<#
.SYNOPSIS
    File Organization Module - Specialized session and temporary file management

.DESCRIPTION
    Extracted file organization component from CoreInfrastructure.psm1.
    Manages session-based file structure, temp file organization, and
    data persistence for all maintenance operations.

.NOTES
    Module Type: Core Infrastructure (File Organization Specialist)
    Dependencies: None
    Extracted from: CoreInfrastructure.psm1
    Version: 1.0.0
    Architecture: v3.0
#>

using namespace System.Collections.Generic
using namespace System.IO

#region Private Variables

# Session management
$script:SessionData = @{
    SessionId = $null
    Timestamp = $null
    DirectoryStructure = @{}
    Initialized = $false
}

#endregion

#region Session Initialization

<#
.SYNOPSIS
    Initializes session-based file organization

.DESCRIPTION
    Creates session ID and timestamp, initializes temp_files directory structure.
    Sets up organized subdirectories for data, logs, temp, and reports.

.PARAMETER TempRootPath
    Path to temp_files directory root

.OUTPUTS
    Hashtable with session details
#>
function Initialize-SessionFileOrganization {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TempRootPath
    )
    
    Write-Verbose "Initializing session file organization in: $TempRootPath"
    
    # Generate session identifiers
    $script:SessionData.SessionId = [guid]::NewGuid().ToString()
    $script:SessionData.Timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    
    # Ensure temp root exists
    if (-not (Test-Path $TempRootPath)) {
        New-Item -Path $TempRootPath -ItemType Directory -Force | Out-Null
    }
    
    # Initialize subdirectory structure
    $subdirectories = @('data', 'logs', 'temp', 'reports')
    
    foreach ($subdir in $subdirectories) {
        $fullPath = Join-Path $TempRootPath $subdir
        if (-not (Test-Path $fullPath)) {
            New-Item -Path $fullPath -ItemType Directory -Force | Out-Null
            Write-Verbose "Created session subdirectory: $subdir"
        }
        $script:SessionData.DirectoryStructure[$subdir] = $fullPath
    }
    
    # Create module-specific log directories
    $logsDir = $script:SessionData.DirectoryStructure['logs']
    $moduleLogDirs = @(
        'bloatware-removal',
        'essential-apps',
        'system-optimization',
        'telemetry-disable',
        'windows-updates',
        'app-upgrade',
        'system-inventory'
    )
    
    foreach ($moduleLogDir in $moduleLogDirs) {
        $modulePath = Join-Path $logsDir $moduleLogDir
        if (-not (Test-Path $modulePath)) {
            New-Item -Path $modulePath -ItemType Directory -Force | Out-Null
        }
    }
    
    $script:SessionData.Initialized = $true
    
    Write-Verbose "Session file organization initialized - SessionId: $($script:SessionData.SessionId)"
    
    return $script:SessionData
}

#endregion

#region Directory Management

<#
.SYNOPSIS
    Gets the path for a session file with organized categorization

.DESCRIPTION
    Constructs and returns organized file path using category, subcategory, and filename.
    Automatically creates parent directories if they don't exist.

.PARAMETER Category
    Main category (data, logs, temp, reports)

.PARAMETER SubCategory
    Subcategory within category (optional)

.PARAMETER FileName
    Name of the file

.OUTPUTS
    System.String - Full path to the file location
#>
function Get-SessionFilePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('data', 'logs', 'temp', 'reports')]
        [string]$Category,
        
        [Parameter(Mandatory = $false)]
        [string]$SubCategory,
        
        [Parameter(Mandatory = $true)]
        [string]$FileName
    )
    
    if (-not $script:SessionData.Initialized) {
        throw "Session file organization not initialized - call Initialize-SessionFileOrganization first"
    }
    
    $basePath = $script:SessionData.DirectoryStructure[$Category]
    
    # Build path with subcategory if provided
    if ($SubCategory) {
        $fullPath = Join-Path $basePath $SubCategory $FileName
        $directory = Join-Path $basePath $SubCategory
    }
    else {
        $fullPath = Join-Path $basePath $FileName
        $directory = $basePath
    }
    
    # Ensure directory exists
    if (-not (Test-Path $directory)) {
        New-Item -Path $directory -ItemType Directory -Force | Out-Null
    }
    
    return $fullPath
}

<#
.SYNOPSIS
    Saves data to organized session storage

.DESCRIPTION
    Converts data to JSON format and saves to appropriate session location.
    Automatically creates parent directories.

.PARAMETER Data
    Data object to save

.PARAMETER Category
    File organization category

.PARAMETER SubCategory
    Optional subcategory

.PARAMETER FileName
    Name of the file to save

.OUTPUTS
    System.String - Path where data was saved
#>
function Save-SessionData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Data,
        
        [Parameter(Mandatory = $true)]
        [ValidateSet('data', 'logs', 'temp', 'reports')]
        [string]$Category,
        
        [Parameter(Mandatory = $false)]
        [string]$SubCategory,
        
        [Parameter(Mandatory = $true)]
        [string]$FileName
    )
    
    try {
        $filePath = Get-SessionFilePath -Category $Category -SubCategory $SubCategory -FileName $FileName
        
        # Convert to JSON if not already a string
        if ($Data -is [string]) {
            $content = $Data
        }
        else {
            $content = $Data | ConvertTo-Json -Depth 10
        }
        
        # Write to file
        Set-Content -Path $filePath -Value $content -Encoding UTF8 -Force
        
        Write-Verbose "Saved session data to: $filePath"
        return $filePath
    }
    catch {
        Write-Error "Failed to save session data: $($_.Exception.Message)"
        return $null
    }
}

<#
.SYNOPSIS
    Retrieves data from organized session storage

.DESCRIPTION
    Loads and returns data from session storage location.
    Automatically handles JSON deserialization.

.PARAMETER Category
    File organization category

.PARAMETER SubCategory
    Optional subcategory

.PARAMETER FileName
    Name of the file to retrieve

.OUTPUTS
    Retrieved data object (or null if file not found)
#>
function Get-SessionData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('data', 'logs', 'temp', 'reports')]
        [string]$Category,
        
        [Parameter(Mandatory = $false)]
        [string]$SubCategory,
        
        [Parameter(Mandatory = $true)]
        [string]$FileName
    )
    
    try {
        $filePath = Get-SessionFilePath -Category $Category -SubCategory $SubCategory -FileName $FileName
        
        if (-not (Test-Path $filePath)) {
            Write-Verbose "Session data file not found: $filePath"
            return $null
        }
        
        $content = Get-Content -Path $filePath -Raw -Encoding UTF8
        
        # Try to parse as JSON
        try {
            $data = $content | ConvertFrom-Json
            return $data
        }
        catch {
            # Return as raw string if not JSON
            return $content
        }
    }
    catch {
        Write-Error "Failed to retrieve session data: $($_.Exception.Message)"
        return $null
    }
}

<#
.SYNOPSIS
    Gets the directory path for a category

.PARAMETER Category
    File organization category

.OUTPUTS
    System.String - Directory path
#>
function Get-SessionDirectoryPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('data', 'logs', 'temp', 'reports')]
        [string]$Category
    )
    
    if (-not $script:SessionData.Initialized) {
        throw "Session file organization not initialized"
    }
    
    return $script:SessionData.DirectoryStructure[$Category]
}

#endregion

#region Cleanup and Maintenance

<#
.SYNOPSIS
    Cleans up temporary session files

.DESCRIPTION
    Removes temporary processing files while preserving data, logs, and reports.
    Can be called after task completion to free resources.

.PARAMETER RetainDays
    Keep temp files created within this many days (0 = keep all recent)
#>
function Clear-SessionTemporaryFiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [int]$RetainDays = 0
    )
    
    try {
        $tempDir = $script:SessionData.DirectoryStructure['temp']
        
        if (-not (Test-Path $tempDir)) {
            return
        }
        
        $files = Get-ChildItem -Path $tempDir -File
        
        foreach ($file in $files) {
            if ($RetainDays -gt 0) {
                $fileAge = (Get-Date) - $file.LastWriteTime
                if ($fileAge.Days -le $RetainDays) {
                    continue
                }
            }
            
            Remove-Item -Path $file.FullName -Force
            Write-Verbose "Removed temporary file: $($file.Name)"
        }
    }
    catch {
        Write-Warning "Failed to clean temporary files: $($_.Exception.Message)"
    }
}

<#
.SYNOPSIS
    Gets session statistics

.OUTPUTS
    Hashtable with session information and file counts
#>
function Get-SessionStatistics {
    [CmdletBinding()]
    param()
    
    if (-not $script:SessionData.Initialized) {
        return $null
    }
    
    $stats = @{
        SessionId = $script:SessionData.SessionId
        Timestamp = $script:SessionData.Timestamp
        DirectoryStructure = @{}
    }
    
    foreach ($category in $script:SessionData.DirectoryStructure.Keys) {
        $dirPath = $script:SessionData.DirectoryStructure[$category]
        $itemCount = (Get-ChildItem -Path $dirPath -Recurse -File -ErrorAction SilentlyContinue).Count
        $stats.DirectoryStructure[$category] = @{
            Path = $dirPath
            FileCount = $itemCount
        }
    }
    
    return [PSCustomObject]$stats
}

#endregion

#region Module Exports

Export-ModuleMember -Function @(
    'Initialize-SessionFileOrganization',
    'Get-SessionFilePath',
    'Save-SessionData',
    'Get-SessionData',
    'Get-SessionDirectoryPath',
    'Clear-SessionTemporaryFiles',
    'Get-SessionStatistics'
)

#endregion
