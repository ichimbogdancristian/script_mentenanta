# Note: PowerShell 7+ verification is handled by the launcher (script.bat).
# The launcher ensures a compatible pwsh.exe is available before invoking this orchestrator.
using namespace System.Collections.Generic
<#
.SYNOPSIS
    Windows Maintenance Automation - Central Orchestrator
.DESCRIPTION
    Central coordination script for the modular Windows maintenance system.
    Handles module loading, configuration management, interactive menus, and task execution.
.PARAMETER LogFilePath
    Path to the log file (optional)
.PARAMETER ConfigPath
    Path to the configuration directory (optional, auto-detected if not provided)
.PARAMETER NonInteractive
    Skip interactive menus and use default settings
.PARAMETER DryRun
    Run in dry-run mode (simulate changes without modifying the system)
.PARAMETER TaskNumbers
    Comma-separated list of task numbers to execute (e.g., "1,3,5")
.EXAMPLE
    .\MaintenanceOrchestrator.ps1
    # Interactive mode with menus
.EXAMPLE
    .\MaintenanceOrchestrator.ps1 -NonInteractive
    # Unattended mode with all tasks
.EXAMPLE
    .\MaintenanceOrchestrator.ps1 -DryRun -TaskNumbers "1,2,3"
    # Dry-run mode with specific tasks
.NOTES
    Author: Windows Maintenance Automation Project
    Version: 2.0.0
    Requires: PowerShell 7.0+, Administrator privileges
#>
param(
    [ValidateScript({ [string]::IsNullOrEmpty($_) -or (Test-Path (Split-Path $_ -Parent)) })]
    [string]$LogFilePath,
    [ValidateScript({ [string]::IsNullOrEmpty($_) -or (Test-Path $_ -PathType Container) })]
    [string]$ConfigPath,
    [switch]$NonInteractive,
    [switch]$DryRun,
    [ValidatePattern('^(\d+)(,\d+)*$|^$')]
    [string]$TaskNumbers
)
# UTF-8 Encoding Configuration - Fix emoji and special character display
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$PSDefaultParameterValues['Out-File:Encoding'] = 'utf8'
$PSDefaultParameterValues['*:Encoding'] = 'utf8'
#region Script Initialization
# Script path detection and environment setup
$ScriptRoot = $PSScriptRoot
if (-not $ScriptRoot) {
    $ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
}
$WorkingDirectory = if ($env:WORKING_DIRECTORY) { $env:WORKING_DIRECTORY } else { $ScriptRoot }
Write-Information "Windows Maintenance Automation - Central Orchestrator v2.0.0" -InformationAction Continue
Write-Information "Working Directory: $WorkingDirectory" -InformationAction Continue
Write-Information "Script Root: $ScriptRoot" -InformationAction Continue
#  Administrator Privilege Verification (Critical for service operations)
Write-Information "[INFO] Verifying administrator privileges..." -InformationAction Continue
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error @"
 ADMINISTRATOR PRIVILEGES REQUIRED
This script requires Administrator privileges to:
• Query all system services (including protected services like McpManagementService)
• Modify system configurations and registry settings
• Install/uninstall applications
• Manage Windows services and scheduled tasks
• Access system-level Windows Update services
Please run this script as Administrator:
• Right-click PowerShell and select "Run as Administrator"
• Or use the script.bat launcher which auto-elevates
• Or run: Start-Process PowerShell -Verb RunAs -ArgumentList "-File `"$($MyInvocation.MyCommand.Path)`""
"@
    exit 1
}
Write-Information "  [OK] Administrator privileges confirmed" -InformationAction Continue
# Initialize Global Path Discovery System
Write-Information "[INFO] Initializing global path discovery..." -InformationAction Continue
$env:MAINTENANCE_PROJECT_ROOT = $ScriptRoot
$env:MAINTENANCE_CONFIG_ROOT = Join-Path $ScriptRoot 'config'
$env:MAINTENANCE_MODULES_ROOT = Join-Path $ScriptRoot 'modules'
$env:MAINTENANCE_TEMP_ROOT = Join-Path $ScriptRoot 'temp_files'
$env:MAINTENANCE_REPORTS_ROOT = $ScriptRoot
Write-Information "   Global environment variables set:" -InformationAction Continue
Write-Information "      PROJECT_ROOT: $env:MAINTENANCE_PROJECT_ROOT" -InformationAction Continue
Write-Information "       CONFIG_ROOT: $env:MAINTENANCE_CONFIG_ROOT" -InformationAction Continue
Write-Information "      MODULES_ROOT: $env:MAINTENANCE_MODULES_ROOT" -InformationAction Continue
Write-Information "      TEMP_ROOT: $env:MAINTENANCE_TEMP_ROOT" -InformationAction Continue
Write-Information "      REPORTS_ROOT: $env:MAINTENANCE_REPORTS_ROOT" -InformationAction Continue
# Detect configuration path (always relative to script location)
if (-not $ConfigPath) {
    $ConfigPath = Join-Path $ScriptRoot 'config'
    if (-not (Test-Path $ConfigPath)) {
        # Fallback to working directory if set by batch script
        $fallbackConfigPath = Join-Path $WorkingDirectory 'config'
        if (Test-Path $fallbackConfigPath) {
            $ConfigPath = $fallbackConfigPath
        }
    }
}
if (-not (Test-Path $ConfigPath)) {
    throw "Configuration directory not found. Expected at: $ConfigPath or $(Join-Path $WorkingDirectory 'config')"
}
Write-Information "Configuration Path: $ConfigPath" -InformationAction Continue
# Initialize session management
$script:MaintenanceSessionId = [guid]::NewGuid().ToString()
$script:MaintenanceSessionTimestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$script:MaintenanceSessionStartTime = Get-Date
$SessionStartTime = $script:MaintenanceSessionStartTime  # For backward compatibility
Write-Information "Session ID: $script:MaintenanceSessionId" -InformationAction Continue
Write-Information "Session Timestamp: $script:MaintenanceSessionTimestamp" -InformationAction Continue
# Set session environment variables for modules to access
$env:MAINTENANCE_SESSION_ID = $script:MaintenanceSessionId
$env:MAINTENANCE_SESSION_TIMESTAMP = $script:MaintenanceSessionTimestamp
# Note: MAINTENANCE_TEMP_ROOT already set above in global path discovery
# Set up temp directories (using global environment variables)
$TempRoot = $env:MAINTENANCE_TEMP_ROOT
$ReportsDir = Join-Path $TempRoot 'reports'
$LogsDir = Join-Path $TempRoot 'logs'
$InventoryDir = Join-Path $TempRoot 'inventory'
@($TempRoot, $ReportsDir, $LogsDir, $InventoryDir) | ForEach-Object {
    if (-not (Test-Path $_)) {
        New-Item -Path $_ -ItemType Directory -Force | Out-Null
        Write-Information "Created directory: $_" -InformationAction Continue
    }
}
Write-Information "Temp Root Directory: $TempRoot" -InformationAction Continue

# Set up log file
if (-not $LogFilePath) {
    $LogFilePath = if ($env:SCRIPT_LOG_FILE) {
        $env:SCRIPT_LOG_FILE
    }
    else {
        Join-Path $ScriptRoot 'maintenance.log'
    }
}
Write-Information "Log File: $LogFilePath" -InformationAction Continue
#endregion

#region Patch 2: Initialize Result Collection (v3.1)
Write-Information "`nInitializing session result collection..." -InformationAction Continue
# Use environment variable directly since $script:ProjectPaths not yet initialized
$ProcessedDataPath = Join-Path $env:MAINTENANCE_TEMP_ROOT 'processed'
if (-not (Test-Path $ProcessedDataPath)) {
    New-Item -Path $ProcessedDataPath -ItemType Directory -Force | Out-Null
}

$script:ResultCollectionEnabled = $false
try {
    if (Get-Command -Name 'Start-ResultCollection' -ErrorAction SilentlyContinue) {
        Start-ResultCollection -SessionId $script:MaintenanceSessionId -CachePath $ProcessedDataPath
        $script:ResultCollectionEnabled = $true
        Write-Information "  [OK] Result collection initialized successfully" -InformationAction Continue
    }
    else {
        Write-Information "  [INFO] LogAggregator result collection not available - using fallback session tracking" -InformationAction Continue
    }
}
catch {
    Write-Warning "Failed to initialize result collection: $($_.Exception.Message) - Using fallback session tracking"
    $script:ResultCollectionEnabled = $false
}
#endregion

#region Module Loading
Write-Information "`nLoading modules..." -InformationAction Continue
# Import core modules (always relative to script location)
$ModulesPath = Join-Path $ScriptRoot 'modules'
if (-not (Test-Path $ModulesPath)) {
    # Fallback to working directory if set by batch script
    $fallbackModulesPath = Join-Path $WorkingDirectory 'modules'
    if (Test-Path $fallbackModulesPath) {
        $ModulesPath = $fallbackModulesPath
    }
}
Write-Information "Modules Path: $ModulesPath" -InformationAction Continue
# v3.1 Split Architecture: Load essential core modules + split report architecture
$CoreModules = @(
    'CoreInfrastructure',
    'LogAggregator',       # v3.1: Moved earlier to prevent race conditions
    'UserInterface',
    'LogProcessor',
    'ReportGenerator',
    'ShutdownManager'      # v3.2: Post-execution countdown and cleanup
)
# Type2 modules (self-contained with internal Type1 dependencies)
$Type2Modules = @(
    'SystemInventory',     # NEW: System information collection (always first)
    'BloatwareRemoval',
    'EssentialApps',
    'SystemOptimization',
    'TelemetryDisable',
    'SecurityEnhancement', # Security hardening and enhancements
    'SecurityEnhancementCIS', # CIS v4.0.0 Benchmark implementation
    'WindowsUpdates',
    'AppUpgrade'
)
$Type2ModulesPath = Join-Path $ModulesPath 'type2'
$CoreModulesPath = Join-Path $ModulesPath 'core'
foreach ($moduleName in $CoreModules) {
    $modulePath = Join-Path $CoreModulesPath "$moduleName.psm1"
    try {
        if (-not (Test-Path $modulePath)) {
            throw "Module file not found: $modulePath"
        }
        # Import PowerShell script module directly (no manifest validation needed for .psm1 files)
        Import-Module $modulePath -Force -Global -ErrorAction Stop
        Write-Information "   Loaded: $moduleName" -InformationAction Continue
        # Verify module loaded successfully
        $loadedModule = Get-Module -Name $moduleName -ErrorAction SilentlyContinue
        if (-not $loadedModule) {
            throw "Module $moduleName failed to load properly - not found in loaded modules"
        }
    }
    catch [System.UnauthorizedAccessException] {
        Write-Error "Access denied loading module $moduleName. Ensure you have administrator privileges and the file is not blocked."
        Write-Information "  ℹ Try running: Unblock-File '$modulePath'" -InformationAction Continue
        exit 1
    }
    catch [System.Security.SecurityException] {
        Write-Error "Security error loading module $moduleName. Check execution policy and file permissions."
        Write-Information "  ℹ Current execution policy: $(Get-ExecutionPolicy)" -InformationAction Continue
        exit 1
    }
    catch [System.IO.FileNotFoundException] {
        Write-Error "Module file not found: $modulePath"
        Write-Information "  ℹ Ensure all module files are present in the modules/core directory" -InformationAction Continue
        exit 1
    }
    catch {
        Write-Error "Failed to load core module $moduleName`: $_"
        Write-Information "  ℹ Error Type: $($_.Exception.GetType().Name)" -InformationAction Continue
        Write-Information "  ℹ Error Details: $($_.Exception.Message)" -InformationAction Continue
        if ($_.ScriptStackTrace) {
            Write-Information "  ℹ Stack Trace: $($_.ScriptStackTrace)" -InformationAction Continue
        }
        exit 1
    }
}
# Load Type2 modules (self-contained with internal Type1 dependencies)
Write-Information "`nLoading Type2 modules..." -InformationAction Continue
foreach ($moduleName in $Type2Modules) {
    $modulePath = Join-Path $Type2ModulesPath "$moduleName.psm1"
    try {
        if (-not (Test-Path $modulePath)) {
            Write-Warning "Type2 module not found: $modulePath - will be skipped"
            continue
        }
        Import-Module $modulePath -Force -Global -ErrorAction Stop
        Write-Information "   Loaded: $moduleName (Type2 - self-contained)" -InformationAction Continue
        # Verify the standardized Invoke-[ModuleName] function is available
        $invokeFunction = "Invoke-$moduleName"
        if (Get-Command -Name $invokeFunction -ErrorAction SilentlyContinue) {
            Write-Information "     $invokeFunction function available" -InformationAction Continue
        }
        else {
            Write-Warning "     $invokeFunction function not found - module may not be v3.0 compliant"
        }
    }
    catch {
        Write-Warning "Failed to load Type2 module $moduleName`: $($_.Exception.Message)"
        Write-Information "  ℹ This module will be skipped during execution" -InformationAction Continue
        # Additional diagnostic information
        if ($_.Exception.InnerException) {
            Write-Information "   Inner exception: $($_.Exception.InnerException.Message)" -InformationAction Continue
        }
        if ($_.ScriptStackTrace) {
            Write-Information "   Stack trace: $((($_.ScriptStackTrace -split "`n") | Select-Object -First 2) -join '; ')" -InformationAction Continue
        }
        # Check common issues
        if ($_.Exception.Message -like "*access*denied*" -or $_.Exception.Message -like "*unauthorized*") {
            Write-Information "  [HINT] Suggestion: Run as Administrator or unblock files with Unblock-File '$modulePath'" -InformationAction Continue
        }
        elseif ($_.Exception.Message -like "*execution*policy*") {
            Write-Information "   Suggestion: Check PowerShell execution policy with Get-ExecutionPolicy" -InformationAction Continue
        }
        elseif ($_.Exception.Message -like "*dependency*" -or $_.Exception.Message -like "*import*") {
            Write-Information "   Suggestion: Check module dependencies and verify all required modules are available" -InformationAction Continue
        }
    }
}

#region FIX #2: Validate CoreInfrastructure Functions
Write-Information "`nValidating CoreInfrastructure module..." -InformationAction Continue
try {
    $requiredCoreFunctions = @(
        'Initialize-GlobalPathDiscovery',
        'Get-MaintenancePaths',
        'Get-AuditResultsPath',
        'Save-DiffResults'
    )
    $missingFunctions = @()
    foreach ($funcName in $requiredCoreFunctions) {
        if (-not (Get-Command -Name $funcName -ErrorAction SilentlyContinue)) {
            $missingFunctions += $funcName
        }
    }
    if ($missingFunctions.Count -gt 0) {
        throw "CoreInfrastructure missing required functions: $($missingFunctions -join ', ')"
    }
    Write-Information "   CoreInfrastructure validation passed" -InformationAction Continue
}
catch {
    Write-Error "CoreInfrastructure validation failed: $($_.Exception.Message)"
    exit 1
}
#endregion
#region Initialize Global Path Discovery System
Write-Information "`n Initializing global path discovery..." -InformationAction Continue
try {
    Initialize-GlobalPathDiscovery -HintPath $ScriptRoot -Force
    
    # Populate $script:ProjectPaths for use throughout the script
    $script:ProjectPaths = Get-MaintenancePaths
    
    Write-Information "   Global path discovery initialized successfully" -InformationAction Continue
}
catch {
    Write-Error "Failed to initialize global path discovery: $($_.Exception.Message)"
    exit 1
}
#endregion

#region Validate Critical Paths
Write-Information "`nValidating critical paths..." -InformationAction Continue
$criticalPaths = @('ProjectRoot', 'ConfigRoot', 'ModulesRoot', 'TempRoot')
foreach ($pathKey in $criticalPaths) {
    if (-not (Test-Path $script:ProjectPaths[$pathKey])) {
        Write-Error "Required path not found: $pathKey = $($script:ProjectPaths[$pathKey])"
        exit 1
    }
}
Write-Information "   Critical paths validated" -InformationAction Continue
#endregion

#region System Readiness Validation
Write-Information "`nPerforming system readiness check..." -InformationAction Continue
try {
    # Check if Test-SystemReadiness function is available
    if (Get-Command -Name 'Test-SystemReadiness' -ErrorAction SilentlyContinue) {
        $systemReady = Test-SystemReadiness
        
        if (-not $systemReady) {
            Write-Warning "System requirements not fully met. Continuing with caution..."
            Write-Information "Press Ctrl+C within 10 seconds to abort, or wait to continue..." -InformationAction Continue
            Start-Sleep -Seconds 10
        }
    }
    else {
        Write-Information "   System readiness check not available (continuing without validation)" -InformationAction Continue
    }
}
catch {
    Write-Warning "System readiness check failed: $($_.Exception.Message)"
    Write-Information "   Continuing with maintenance execution..." -InformationAction Continue
}
#endregion

#region System Restore Point Space Management & Creation

<#
.SYNOPSIS
    Ensures System Restore Point has minimum 10GB allocation

.DESCRIPTION
    Checks current System Protection storage allocation
    If less than 10GB, allocates 10GB for restore points
    Non-blocking: continues even if allocation fails
#>
function Ensure-SystemRestorePointSpace {
    [CmdletBinding()]
    param(
        [int]$MinimumGB = 10
    )
    
    try {
        Write-Information "   Checking System Restore Point disk space allocation..." -InformationAction Continue
        
        # Get system drive
        $systemDrive = $env:SystemDrive
        $driveLetter = $systemDrive.TrimEnd(':')
        
        # Check if System Protection is enabled
        try {
            $volume = Get-Volume -DriveLetter $driveLetter -ErrorAction SilentlyContinue
            if (-not $volume) {
                Write-Information "   Could not access volume information for $systemDrive" -InformationAction Continue
                return $false
            }
        }
        catch {
            Write-Information "   Could not query volume for System Restore Point space check: $_" -InformationAction Continue
            return $false
        }
        
        # Ensure System Protection is enabled (attempt best-effort enablement)
        try {
            if (Get-Command -Name 'Enable-ComputerRestore' -ErrorAction SilentlyContinue) {
                Enable-ComputerRestore -Drive $systemDrive -ErrorAction SilentlyContinue | Out-Null
            }
        }
        catch {
            Write-Information "   Unable to enable System Protection via Enable-ComputerRestore: $_" -InformationAction Continue
        }

        # Get current System Protection usage via CIM
        try {
            $srp = Get-CimInstance -ClassName Win32_SystemRestoreConfig -Namespace "root\cimv2" -ErrorAction SilentlyContinue
            
            if ($srp) {
                # ShadowCopy size is in bytes; convert to GB
                $currentAllocationGB = [math]::Round($srp.MaxSpace / 1GB, 2)
                $allocatedBytes = $srp.AllocatedSpace
                $usedSpaceGB = [math]::Round($allocatedBytes / 1GB, 2)
                
                Write-Information "   Current System Protection allocation: $currentAllocationGB GB (Used: $usedSpaceGB GB)" -InformationAction Continue
                
                if ($currentAllocationGB -lt $MinimumGB) {
                    Write-Information "   Allocation is below minimum ($MinimumGB GB). Attempting to allocate..." -InformationAction Continue
                    
                    # Set minimum allocation in bytes
                    $newAllocationBytes = [int64]($MinimumGB * 1GB)
                    
                    try {
                        $srp.MaxSpace = $newAllocationBytes
                        $srp.Put() | Out-Null
                        
                        Write-Information "   [OK] System Restore Point allocation set to $MinimumGB GB" -InformationAction Continue
                        Write-LogEntry -Level 'SUCCESS' -Component 'RESTORE-POINT' -Message "System Restore Point allocation increased to $MinimumGB GB"
                        return $true
                    }
                    catch {
                        Write-Information "   Failed to allocate System Restore Point space: $_" -InformationAction Continue
                        Write-LogEntry -Level 'WARN' -Component 'RESTORE-POINT' -Message "Could not allocate $MinimumGB GB for System Restore Point: $_"
                        return $false
                    }
                }
                else {
                    Write-Information "   [OK] System Protection allocation is sufficient ($currentAllocationGB GB >= $MinimumGB GB)" -InformationAction Continue
                    return $true
                }
            }
            else {
                Write-Information "   System Restore configuration not available via WMI" -InformationAction Continue
                return $false
            }
        }
        catch {
            Write-Information "   Error checking System Restore Point allocation: $_" -InformationAction Continue
            return $false
        }
    }
    catch {
        Write-Warning "   Unexpected error in System Restore Point space check: $_"
        return $false
    }
}

Write-Information "`nChecking System Restore Point configuration..." -InformationAction Continue
try {
    $mainConfig = Get-MainConfiguration
    $createRestorePoint = $mainConfig.system.createSystemRestorePoint ?? $true
    $restorePointMinSizeGB = $mainConfig.system.restorePointMaxSizeGB ?? 10
    
    # First, ensure adequate disk space allocation for restore points
    if ($createRestorePoint -and -not $DryRun) {
        Ensure-SystemRestorePointSpace -MinimumGB $restorePointMinSizeGB | Out-Null
    }
    
    if ($createRestorePoint -and -not $DryRun) {
        Write-Information "   Creating system restore point before maintenance..." -InformationAction Continue
        
        $restoreDescription = "Before Windows Maintenance - $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
        if (Get-Command -Name 'New-SystemRestorePoint' -ErrorAction SilentlyContinue) {
            $restoreResult = New-SystemRestorePoint -Description $restoreDescription
        }
        elseif (Get-Command -Name 'Checkpoint-Computer' -ErrorAction SilentlyContinue) {
            Checkpoint-Computer -Description $restoreDescription -RestorePointType 'MODIFY_SETTINGS' -ErrorAction Stop
            $restoreResult = @{
                Success     = $true
                Description = $restoreDescription
            }
        }
        else {
            # Fallback to Windows PowerShell for Checkpoint-Computer if available
            $psExe = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
            if (Test-Path $psExe) {
                $psArgs = @(
                    '-NoProfile',
                    '-Command',
                    "Checkpoint-Computer -Description `"$restoreDescription`" -RestorePointType 'MODIFY_SETTINGS'"
                )
                $proc = Start-Process -FilePath $psExe -ArgumentList $psArgs -Wait -PassThru -WindowStyle Hidden
                if ($proc.ExitCode -eq 0) {
                    $restoreResult = @{
                        Success     = $true
                        Description = $restoreDescription
                    }
                }
                else {
                    throw "Checkpoint-Computer failed in Windows PowerShell (ExitCode: $($proc.ExitCode))"
                }
            }
            else {
                throw "System restore point cmdlet not available (New-SystemRestorePoint or Checkpoint-Computer)."
            }
        }
        
        if ($restoreResult.Success) {
            if ($restoreResult.SequenceNumber) {
                Write-Information "   [OK] Restore point created successfully (Sequence: $($restoreResult.SequenceNumber))" -InformationAction Continue
            }
            else {
                Write-Information "   [OK] Restore point created: $($restoreResult.Description)" -InformationAction Continue
            }
        }
        else {
            Write-Warning "   Failed to create restore point: $($restoreResult.Message)"
            Write-Warning "   Continuing without restore point - you may want to create one manually"
        }
    }
    elseif ($DryRun) {
        Write-Information "   [DRY-RUN] Restore point creation skipped in dry-run mode" -InformationAction Continue
    }
    else {
        Write-Information "   Restore point creation disabled in configuration" -InformationAction Continue
    }
}
catch {
    Write-Warning "Failed to create restore point: $($_.Exception.Message)"
    Write-Warning "Continuing without restore point - you may want to create one manually"
}
#endregion

# Ensure Write-LogEntry is available after module loading (modules may have overridden it)
if (-not (Get-Command -Name 'Write-LogEntry' -ErrorAction SilentlyContinue)) {
    function global:Write-LogEntry {
        param($Level, $Component, $Message, $Data)
        Write-Information "[$Level] [$Component] $Message" -InformationAction Continue
    }
    Write-Information "   Write-LogEntry function was lost during module loading, reinstated fallback" -InformationAction Continue
}
else {
    $logFunction = Get-Command -Name 'Write-LogEntry'
    Write-Information "   Write-LogEntry available from: $($logFunction.Source)" -InformationAction Continue
}
#  System Access Verification
Write-Information "`n Verifying system access permissions..." -InformationAction Continue
try {
    # Test service enumeration capability
    $testServiceCount = (Get-Service -ErrorAction SilentlyContinue | Measure-Object).Count
    Write-Information "   Service enumeration: $testServiceCount services accessible" -InformationAction Continue
    # Test registry access
    try {
        $testRegRead = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion" -Name "ProductName" -ErrorAction SilentlyContinue
        if ($testRegRead) {
            Write-Information "   Registry access: HKLM accessible" -InformationAction Continue
        }
    }
    catch {
        Write-Warning "   Limited registry access detected"
    }
    # Test WMI access
    try {
        $testWmi = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
        if ($testWmi) {
            Write-Information "   WMI access: System information accessible" -InformationAction Continue
        }
    }
    catch {
        Write-Warning "   Limited WMI access detected"
    }
}
catch {
    Write-Warning "   System access verification encountered issues: $($_.Exception.Message)"
    Write-Information "  ℹ Some operations may have limited functionality" -InformationAction Continue
}
#endregion
#region Configuration Loading
Write-Information "`nInitializing configuration..." -InformationAction Continue
#region FIX #8: JSON Configuration Validation Function
<#
.SYNOPSIS
    Validates JSON configuration files for syntax and structure
.DESCRIPTION
    FIX #8: Comprehensive JSON validation during orchestrator initialization.
    Validates both syntax (valid JSON) and basic structure (required keys).
.PARAMETER FilePath
    Full path to the JSON file to validate
.PARAMETER FileName
    Name of the file (for display purposes)
.OUTPUTS
    $true if valid, throws error if invalid
#>
function Test-ConfigurationJsonValidity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,
        [Parameter(Mandatory = $false)]
        [string]$FileName = (Split-Path $FilePath -Leaf)
    )
    try {
        # Check file exists
        if (-not (Test-Path $FilePath)) {
            throw "Configuration file not found: $FileName at $FilePath"
        }
        # Validate JSON syntax
        $content = Get-Content $FilePath -Raw
        $jsonObject = $content | ConvertFrom-Json -ErrorAction Stop
        # Validate not empty
        if (-not $jsonObject) {
            throw "Configuration file is empty: $FileName"
        }
        Write-Verbose " JSON syntax valid for $FileName"
        return $true
    }
    catch {
        throw "JSON validation failed for $($FileName): $($_.Exception.Message)"
    }
}
#endregion
try {
    # Validate all critical configuration files using standardized paths
    Write-Information "  Validating configuration file syntax and structure..." -InformationAction Continue
    
    # Required configuration files in standardized locations
    $requiredConfigs = @(
        @{ Name = 'main-config.json'; Path = (Join-Path $ConfigPath 'settings\main-config.json') },
        @{ Name = 'logging-config.json'; Path = (Join-Path $ConfigPath 'settings\logging-config.json') },
        @{ Name = 'bloatware-list.json'; Path = (Join-Path $ConfigPath 'lists\bloatware-list.json') },
        @{ Name = 'essential-apps.json'; Path = (Join-Path $ConfigPath 'lists\essential-apps.json') },
        @{ Name = 'app-upgrade-config.json'; Path = (Join-Path $ConfigPath 'lists\app-upgrade-config.json') }
    )
    # Validate all configuration files
    foreach ($config in $requiredConfigs) {
        if (-not (Test-Path $config.Path)) {
            throw "Required configuration file not found: $($config.Name) at $($config.Path)"
        }
        try {
            Test-ConfigurationJsonValidity -FilePath $config.Path -FileName $config.Name
            Write-Information "     $($config.Name) validated" -InformationAction Continue
        }
        catch {
            Write-Error "Configuration validation error: $_"
            throw $_
        }
    }
    Write-Information "   All configuration files validated successfully" -InformationAction Continue
    try {
        # Validate configuration directory structure using standardized paths
        $requiredConfigFiles = @(
            (Join-Path $ConfigPath 'settings\main-config.json'),
            (Join-Path $ConfigPath 'settings\logging-config.json')
        )
        foreach ($configFile in $requiredConfigFiles) {
            if (-not (Test-Path $configFile)) {
                throw "Required configuration file not found: $configFile"
            }
            # Validate JSON syntax
            try {
                $null = Get-Content $configFile | ConvertFrom-Json -ErrorAction Stop
            }
            catch {
                throw "Invalid JSON syntax in configuration file $(Split-Path $configFile -Leaf): $($_.Exception.Message)"
            }
        }
        # Initialize configuration system with error handling
        try {
            Write-Information "  Checking for Initialize-ConfigSystem function..." -InformationAction Continue
            # First, check if CoreInfrastructure module is loaded
            $coreModule = Get-Module -Name CoreInfrastructure -ErrorAction SilentlyContinue
            if (-not $coreModule) {
                Write-Information "  CoreInfrastructure module not found, attempting to re-import..." -InformationAction Continue
                $coreModulePath = Join-Path $script:ProjectPaths.Core "CoreInfrastructure.psm1"
                Import-Module $coreModulePath -Force -Global -ErrorAction Stop
                Write-Information "   CoreInfrastructure module re-imported" -InformationAction Continue
            }
            else {
                Write-Information "  CoreInfrastructure module is loaded (Version: $($coreModule.Version))" -InformationAction Continue
            }
            # Check for the specific function (use actual name, not alias)
            $configFunction = Get-Command Initialize-ConfigurationSystem -ErrorAction SilentlyContinue
            if (-not $configFunction) {
                Write-Information "  Available functions from CoreInfrastructure:" -InformationAction Continue
                $availableFunctions = Get-Command -Module CoreInfrastructure -ErrorAction SilentlyContinue
                if ($availableFunctions) {
                    $availableFunctions | ForEach-Object { Write-Information "    $($_.Name)" -InformationAction Continue }
                }
                else {
                    Write-Information "    No functions found from CoreInfrastructure module" -InformationAction Continue
                }
                # Also check all available functions with this name pattern
                Write-Information "  Searching for Initialize-Configuration in all modules:" -InformationAction Continue
                Get-Command "*Initialize-Configuration*" -ErrorAction SilentlyContinue | ForEach-Object {
                    Write-Information "    Found: $($_.Name) in module: $($_.ModuleName)" -InformationAction Continue
                }
                throw "Initialize-ConfigurationSystem function not found"
            }
            Write-Information "  Found Initialize-ConfigurationSystem (Source: $($configFunction.Source)), calling with path: $ConfigPath" -InformationAction Continue
            Initialize-ConfigurationSystem -ConfigRootPath $ConfigPath -ErrorAction Stop
            Write-Information "   Configuration system initialized" -InformationAction Continue
        }
        catch {
            throw "Failed to initialize configuration system: $($_.Exception.Message)"
        }
        # Load configurations with validation
        try {
            # Get configuration as hashtable for Type2 module compatibility
            $MainConfig = Get-MainConfiguration -ConfigPath $ConfigPath -ErrorAction Stop
            if (-not $MainConfig) {
                throw "Main configuration is null or empty"
            }
            Write-Information "   Main configuration loaded (converted to hashtable)" -InformationAction Continue
        }
        catch {
            throw "Failed to load main configuration: $($_.Exception.Message)"
        }
        try {
            $LoggingConfig = Get-LoggingConfiguration -ErrorAction Stop
            if (-not $LoggingConfig) {
                throw "Logging configuration is null or empty"
            }
            Write-Information "   Logging configuration loaded" -InformationAction Continue
        }
        catch {
            throw "Failed to load logging configuration: $($_.Exception.Message)"
        }
        
        # v3.1: Comprehensive schema validation beyond JSON syntax
        Write-Information "  Validating configuration schemas..." -InformationAction Continue
        try {
            if (Get-Command -Name 'Test-ConfigurationSchema' -ErrorAction SilentlyContinue) {
                # Validate main configuration
                $mainConfigValid = Test-ConfigurationSchema -ConfigObject $MainConfig -ConfigName 'main-config.json'
                if ($mainConfigValid) {
                    Write-Information "     main-config.json schema validated" -InformationAction Continue
                }
                else {
                    Write-Warning "     main-config.json has schema issues (see warnings above)"
                }
                
                # Validate logging configuration
                $loggingConfigValid = Test-ConfigurationSchema -ConfigObject $LoggingConfig -ConfigName 'logging-config.json'
                if ($loggingConfigValid) {
                    Write-Information "     logging-config.json schema validated" -InformationAction Continue
                }
                else {
                    Write-Warning "     logging-config.json has schema issues (see warnings above)"
                }
                
                # Optionally validate data lists if needed
                # (bloatware-list.json, essential-apps.json validated on first use)
            }
            else {
                Write-Information "     Schema validation function not available (using basic validation only)" -InformationAction Continue
            }
        }
        catch {
            Write-Warning "  Configuration schema validation error: $($_.Exception.Message)"
            Write-Information "  ℹ Continuing with basic validation - some configuration issues may cause runtime errors" -InformationAction Continue
        }
        
        # Initialize file organization system first (required by logging system)
        try {
            $fileOrgResult = Initialize-SessionFileOrganization -SessionRoot $script:ProjectPaths.TempRoot -ErrorAction Stop
            if ($fileOrgResult) {
                Write-Information "   File organization system initialized" -InformationAction Continue
            }
            else {
                throw "File organization initialization returned false"
            }
        }
        catch {
            Write-Information "   File organization system failed to initialize: $($_.Exception.Message)" -InformationAction Continue
            Write-Information "  ℹ Continuing with basic file operations - some features may be limited" -InformationAction Continue
            # Don't exit here as this is not critical for basic operation
        }
        # Initialize temp_files directory structure (v3.0 requirement for Type1/Type2 module flow)
        try {
            Write-Information "  Initializing temp_files directory structure..." -InformationAction Continue
            $tempStructureValid = Initialize-SessionFileOrganization -SessionRoot $script:ProjectPaths.TempRoot
            if ($tempStructureValid) {
                Write-Information "   Temp files directory structure validated/created" -InformationAction Continue
            }
            else {
                Write-Information "   Some temp files directories could not be created - continuing with available structure" -InformationAction Continue
            }
        }
        catch {
            Write-Information "   Temp files structure validation failed: $($_.Exception.Message)" -InformationAction Continue
            Write-Information "  ℹ Modules will attempt to create directories as needed" -InformationAction Continue
        }
        # Initialize logging system (depends on file organization)
        try {
            $baseLogPath = $script:ProjectPaths.MainLogFile
            if ([string]::IsNullOrWhiteSpace($baseLogPath)) {
                $fallbackRoot = if ($script:ProjectPaths.TempRoot) { $script:ProjectPaths.TempRoot } else { $env:MAINTENANCE_TEMP_ROOT }
                if (-not [string]::IsNullOrWhiteSpace($fallbackRoot)) {
                    $baseLogPath = Join-Path $fallbackRoot 'logs\maintenance.log'
                }
            }

            if ([string]::IsNullOrWhiteSpace($baseLogPath)) {
                throw "Logging base path is empty. Ensure temp paths are initialized."
            }

            $loggingInitResult = Initialize-LoggingSystem -BaseLogPath $baseLogPath -ErrorAction Stop
            if ($loggingInitResult) {
                Write-Information "   Logging system initialized" -InformationAction Continue
                # LoggingManager functions are now available
            }
            else {
                throw "Logging system initialization returned false"
            }
        }
        catch {
            Write-Information "   Logging system failed to initialize: $($_.Exception.Message)" -InformationAction Continue
            Write-Information "  ℹ Continuing without enhanced logging - basic console output only" -InformationAction Continue
        }
        # Ensure Write-LogEntry is always available (fallback if LoggingManager failed)
        if (-not (Get-Command -Name 'Write-LogEntry' -ErrorAction SilentlyContinue)) {
            function global:Write-LogEntry {
                param($Level, $Component, $Message, $Data)
                Write-Information "[$Level] [$Component] $Message" -InformationAction Continue
            }
            Write-Information "   Using fallback Write-LogEntry function" -InformationAction Continue
        }
        else {
            Write-Information "   Write-LogEntry function available from LoggingManager" -InformationAction Continue
        }
    }
    catch [System.IO.DirectoryNotFoundException] {
        Write-Error "Configuration directory not found: $ConfigPath"
        Write-Information "  ℹ Ensure the 'config' directory exists and contains required configuration files" -InformationAction Continue
        exit 1
    }
    catch [System.IO.FileNotFoundException] {
        Write-Error "Required configuration file not found: $($_.Exception.Message)"
        Write-Information "  ℹ Ensure all required configuration files are present in: $ConfigPath" -InformationAction Continue
        exit 1
    }
    catch [System.Management.Automation.RuntimeException] {
        Write-Error "Configuration system error: $($_.Exception.Message)"
        Write-Information "  ℹ Check configuration file syntax and module dependencies" -InformationAction Continue
        exit 1
    }
    catch {
        Write-Error "Failed to initialize configuration: $($_.Exception.Message)"
        Write-Information "  ℹ Error Type: $($_.Exception.GetType().Name)" -InformationAction Continue
        Write-Information "  ℹ This may indicate missing dependencies or corrupted configuration files" -InformationAction Continue
        exit 1
    }
    # Load app configurations with comprehensive error handling
    try {
        Write-Information "`nLoading application configurations..." -InformationAction Continue
        try {
            $BloatwareLists = Get-BloatwareConfiguration -ErrorAction Stop
            if (-not $BloatwareLists) {
                Write-Warning "Bloatware configuration is empty or null - bloatware removal tasks may be limited"
            }
            else {
                Write-Information "   Bloatware configuration loaded" -InformationAction Continue
            }
        }
        catch {
            Write-Information "   Failed to load bloatware configuration: $($_.Exception.Message)" -InformationAction Continue
            Write-Information "  ℹ Bloatware removal tasks will be skipped" -InformationAction Continue
            $BloatwareLists = @()
        }
        try {
            $EssentialApps = Get-EssentialAppsConfiguration -ErrorAction Stop
            if (-not $EssentialApps) {
                Write-Warning "Essential apps configuration is empty or null - app installation tasks may be limited"
            }
            else {
                Write-Information "   Essential apps configuration loaded" -InformationAction Continue
            }
        }
        catch {
            Write-Information "   Failed to load essential apps configuration: $($_.Exception.Message)" -InformationAction Continue
            Write-Information "  ℹ Essential app installation tasks will be skipped" -InformationAction Continue
            $EssentialApps = @()
        }
        # Calculate configuration statistics with error handling
        try {
            $totalBloatware = if ($BloatwareLists -and $BloatwareLists.ContainsKey('all')) { $BloatwareLists['all'].Count } else { 0 }
            $totalEssentialApps = if ($EssentialApps -and $EssentialApps.ContainsKey('all')) { $EssentialApps['all'].Count } else { 0 }
            Write-Information "   Bloatware list: $totalBloatware total entries" -InformationAction Continue
            Write-Information "   Essential apps: $totalEssentialApps total entries" -InformationAction Continue
        }
        catch {
            Write-Information "   Error calculating configuration statistics: $($_.Exception.Message)" -InformationAction Continue
            $totalBloatware = 0
            $totalEssentialApps = 0
        }
    }
    catch [System.IO.FileNotFoundException] {
        Write-Error "App configuration file not found: $($_.Exception.Message)"
        Write-Information "  ℹ Ensure bloatware-list.json and essential-apps.json exist in: $ConfigPath" -InformationAction Continue
        exit 1
    }
    catch [System.ArgumentException] {
        Write-Error "Invalid app configuration format: $($_.Exception.Message)"
        Write-Information "  ℹ Check JSON syntax and structure in app configuration files" -InformationAction Continue
        exit 1
    }
    catch {
        Write-Error "Failed to load app configurations: $($_.Exception.Message)"
        Write-Information "  ℹ Error Type: $($_.Exception.GetType().Name)" -InformationAction Continue
        Write-Information "  ℹ Check app configuration files in: $ConfigPath" -InformationAction Continue
        exit 1
    }
    #endregion
    #region Session Management Functions
    #endregion
    #region Helper Functions
    function Invoke-TaskWithParameters {
        param(
            [string]$TaskName,
            [string]$FunctionName,
            [hashtable]$Config,
            [switch]$DryRun
        )
        # Prepare task-specific parameters for Type2 modules
        switch ($TaskName) {
            'EssentialApps' {
                $params = @{ Config = $Config }
                if ($DryRun) { $params.DryRun = $true }
                return & $FunctionName @params
            }
            'BloatwareRemoval' {
                $params = @{ Config = $Config }
                if ($DryRun) { $params.DryRun = $true }
                return & $FunctionName @params
            }
            'TelemetryDisable' {
                $params = @{ Config = $Config }
                if ($DryRun) { $params.DryRun = $true }
                return & $FunctionName @params
            }
            'BloatwareDetection' {
                # Call without caching (not implemented in module)
                $params = @{ Config = $Config }
                return & $FunctionName @params
            }
            'SystemInventory' {
                # Call with detailed information (caching not implemented)
                $params = @{ Config = $Config; IncludeDetailed = $true }
                return & $FunctionName @params
            }
            default {
                # For other tasks, call with Config parameter
                return & $FunctionName -Config $Config
            }
        }
    }
    <#
.SYNOPSIS
    Collects all log files from temp_files/data/ and temp_files/logs/ for comprehensive reporting
.DESCRIPTION
    Aggregates Type1 audit results and Type2 execution logs into a comprehensive collection
    for LogProcessor → ReportGenerator pipeline. This implements the v3.0 split architecture
    where orchestrator prepares data for the two-step processing flow.
.EXAMPLE
    $logCollection = Get-ComprehensiveLogCollection
#>
    function Get-ComprehensiveLogCollection {
        [CmdletBinding()]
        param()
        Write-Information "   Collecting comprehensive log data..." -InformationAction Continue
        try {
            $logCollection = @{
                Type1AuditData      = @{}
                Type2ExecutionLogs  = @{}
                CollectionTimestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                SessionId           = $script:MaintenanceSessionId
            }
            # Collect Type1 audit results from temp_files/data/
            $dataPath = Join-Path $env:MAINTENANCE_TEMP_ROOT "data"
            if (Test-Path $dataPath) {
                $auditFiles = Get-ChildItem -Path $dataPath -Filter "*.json" -ErrorAction SilentlyContinue
                foreach ($file in $auditFiles) {
                    try {
                        $moduleName = $file.BaseName -replace '-results$', ''
                        $auditData = Get-Content $file.FullName | ConvertFrom-Json
                        $logCollection.Type1AuditData[$moduleName] = $auditData
                        Write-Information "     Collected Type1 data: $($file.Name)" -InformationAction Continue
                    }
                    catch {
                        Write-Warning "     Failed to parse audit data: $($file.Name) - $($_.Exception.Message)"
                    }
                }
            }
            # Collect Type2 execution logs from temp_files/logs/
            $logsPath = Join-Path $env:MAINTENANCE_TEMP_ROOT "logs"
            if (Test-Path $logsPath) {
                $logDirectories = Get-ChildItem -Path $logsPath -Directory -ErrorAction SilentlyContinue
                foreach ($dir in $logDirectories) {
                    $executionLogPath = Join-Path $dir.FullName "execution.log"
                    if (Test-Path $executionLogPath) {
                        try {
                            $logContent = Get-Content $executionLogPath -Raw
                            $logCollection.Type2ExecutionLogs[$dir.Name] = $logContent
                            Write-Information "     Collected Type2 logs: $($dir.Name)" -InformationAction Continue
                        }
                        catch {
                            Write-Warning "     Failed to read execution log: $($dir.Name) - $($_.Exception.Message)"
                        }
                    }
                }
            }
            $auditDataCount = $logCollection.Type1AuditData.Keys.Count
            $executionLogsCount = $logCollection.Type2ExecutionLogs.Keys.Count
            Write-Information "   Log collection summary: $auditDataCount Type1 modules, $executionLogsCount Type2 modules" -InformationAction Continue
            Write-LogEntry -Level 'INFO' -Component 'ORCHESTRATOR' -Message "Comprehensive log collection completed" -Data @{
                Type1ModulesCollected = $auditDataCount
                Type2ModulesCollected = $executionLogsCount
                CollectionTimestamp   = $logCollection.CollectionTimestamp
            }
            return $logCollection
        }
        catch {
            Write-LogEntry -Level 'ERROR' -Component 'ORCHESTRATOR' -Message "Failed to collect comprehensive logs: $($_.Exception.Message)"
            return @{
                Type1AuditData      = @{}
                Type2ExecutionLogs  = @{}
                CollectionTimestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                Error               = $_.Exception.Message
            }
        }
    }
    #region FIX #9: Session Manifest Function
    <#
.SYNOPSIS
    Creates a session manifest file documenting the execution session
.DESCRIPTION
    FIX #9: Creates session.json file that captures complete session metadata:
    - Unique session identifier (GUID)
    - Execution timestamp (ISO 8601)
    - Execution mode (interactive/unattended/dry-run)
    - Module execution results
    - Total session duration
    - Final execution status
.PARAMETER SessionId
    Unique session identifier (GUID)
.PARAMETER ExecutionMode
    Mode of execution: 'Interactive', 'Unattended', or 'DryRun'
.PARAMETER ModuleResults
    Array of module execution results with timestamps
.PARAMETER ExecutionStartTime
    DateTime when execution began
.OUTPUTS
    Path to created session.json manifest file
#>
    function New-SessionManifest {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory = $true)]
            [string]$SessionId,
            [Parameter(Mandatory = $true)]
            [string]$ExecutionMode,
            [Parameter(Mandatory = $false)]
            [array]$ModuleResults = @(),
            [Parameter(Mandatory = $true)]
            [datetime]$ExecutionStartTime,
            [Parameter(Mandatory = $false)]
            [switch]$IsDryRun = $false
        )
        try {
            # Calculate execution duration
            $executionEndTime = Get-Date
            $totalDuration = ($executionEndTime - $ExecutionStartTime).TotalSeconds
            # Count successful and failed modules
            $successfulModules = @($ModuleResults | Where-Object { $_.Success -eq $true }).Count
            $failedModules = @($ModuleResults | Where-Object { $_.Success -eq $false }).Count
            # Determine final execution status
            $executionStatus = if ($IsDryRun) {
                'DryRun - No changes made'
            }
            elseif ($failedModules -eq 0) {
                'Success - All modules completed'
            }
            elseif ($failedModules -lt $ModuleResults.Count) {
                'Partial - Some modules failed'
            }
            else {
                'Failed - All modules failed'
            }
            # Build session manifest
            $sessionManifest = @{
                sessionId            = $SessionId
                sessionTimestamp     = $ExecutionStartTime.ToString('o')  # ISO 8601 format
                sessionEndTime       = $executionEndTime.ToString('o')
                executionMode        = $ExecutionMode
                isDryRun             = $IsDryRun.IsPresent
                executionStartTime   = $ExecutionStartTime.ToString('yyyy-MM-dd HH:mm:ss')
                executionEndTime     = $executionEndTime.ToString('yyyy-MM-dd HH:mm:ss')
                totalDurationSeconds = $totalDuration
                moduleResults        = @($ModuleResults | ForEach-Object {
                        @{
                            moduleName     = $_.TaskName
                            success        = $_.Success
                            itemsDetected  = $_.ItemsDetected
                            itemsProcessed = $_.ItemsProcessed
                            duration       = $_.Duration
                            startTime      = $_.StartTime
                            endTime        = $_.EndTime
                            executionMode  = if ($IsDryRun) { 'DryRun' } else { 'Live' }
                        }
                    })
                executionStatus      = $executionStatus
                systemInfo           = @{
                    computerName      = $env:COMPUTERNAME
                    userName          = $env:USERNAME
                    osVersion         = [System.Environment]::OSVersion.VersionString
                    powershellVersion = $PSVersionTable.PSVersion.ToString()
                }
                summaryMetrics       = @{
                    totalModules      = $ModuleResults.Count
                    successfulModules = $successfulModules
                    failedModules     = $failedModules
                    successRate       = if ($ModuleResults.Count -gt 0) {
                        [math]::Round(($successfulModules / $ModuleResults.Count) * 100, 2)
                    }
                    else { 0 }
                }
            }
            # Save session manifest to temp_files/data/ with formatted date naming
            $dataPath = Join-Path $env:MAINTENANCE_TEMP_ROOT 'data'
            if (-not (Test-Path $dataPath)) {
                New-Item -Path $dataPath -ItemType Directory -Force | Out-Null
            }
            # Format: session-YYYY-MM-DD-HHmmss.json
            $sessionDateFormat = $ExecutionStartTime.ToString('yyyy-MM-dd-HHmmss')
            $manifestPath = Join-Path $dataPath "session-$sessionDateFormat.json"
            $sessionManifest | ConvertTo-Json -Depth 20 | Set-Content -Path $manifestPath -Encoding UTF8 -Force
            Write-Information "   Session manifest created: $manifestPath" -InformationAction Continue
            Write-LogEntry -Level 'INFO' -Component 'ORCHESTRATOR' -Message "Session manifest created: session-$sessionDateFormat.json" -Data @{
                SessionId         = $SessionId
                ExecutionMode     = $ExecutionMode
                TotalDuration     = $totalDuration
                SuccessfulModules = $successfulModules
                FailedModules     = $failedModules
                ExecutionStatus   = $executionStatus
            }
            return $manifestPath
        }
        catch {
            Write-Error "Failed to create session manifest: $($_.Exception.Message)"
            Write-LogEntry -Level 'ERROR' -Component 'ORCHESTRATOR' -Message "Session manifest creation failed: $($_.Exception.Message)"
            return $null
        }
    }
    #endregion
    
    #region Maintenance Log Organization (v3.1 - Early organization)
    # NEW v3.1: Organize bootstrap maintenance.log to temp_files/logs/ early
    # This ensures logs are properly organized even if execution fails later
    Write-Information "`nOrganizing maintenance logs..." -InformationAction Continue
    
    if (Get-Command -Name 'Move-MaintenanceLogToOrganized' -ErrorAction SilentlyContinue) {
        try {
            $logOrganized = Move-MaintenanceLogToOrganized
            if ($logOrganized) {
                Write-Information "   [OK] Maintenance log organized successfully" -InformationAction Continue
            }
            else {
                Write-Information "   [INFO] Maintenance log already organized or not found at root" -InformationAction Continue
            }
        }
        catch {
            Write-Warning "   Failed to organize maintenance log: $($_.Exception.Message)"
            Write-Information "   [INFO] Continuing execution (non-critical)" -InformationAction Continue
        }
    }
    else {
        Write-Information "   [INFO] Log organization function not available (continuing)" -InformationAction Continue
    }
    #endregion
    
    #region Task Definitions
    Write-Information "`nRegistering maintenance tasks..." -InformationAction Continue
    # v3.0 Architecture: Define standardized maintenance tasks using Invoke-[ModuleName] pattern
    $MaintenanceTasks = @(
        @{
            Name        = 'SystemInventory'
            Description = 'Collect comprehensive system inventory (Type2→Type1 flow)'
            ModuleName  = 'SystemInventory'
            Function    = 'Invoke-SystemInventory'
            Type        = 'Type2'
            Category    = 'Information'
            Enabled     = $true  # Always enabled
        },
        @{
            Name        = 'BloatwareRemoval'
            Description = 'Detect and remove bloatware applications (Type2→Type1 flow)'
            ModuleName  = 'BloatwareRemoval'
            Function    = 'Invoke-BloatwareRemoval'
            Type        = 'Type2'
            Category    = 'Cleanup'
            Enabled     = (-not $MainConfig.modules.skipBloatwareRemoval)
        },
        @{
            Name        = 'EssentialApps'
            Description = 'Analyze and install essential applications (Type2→Type1 flow)'
            ModuleName  = 'EssentialApps'
            Function    = 'Invoke-EssentialApps'
            Type        = 'Type2'
            Category    = 'Installation'
            Enabled     = (-not $MainConfig.modules.skipEssentialApps)
        },
        @{
            Name        = 'SystemOptimization'
            Description = 'Analyze and optimize system performance (Type2→Type1 flow)'
            ModuleName  = 'SystemOptimization'
            Function    = 'Invoke-SystemOptimization'
            Type        = 'Type2'
            Category    = 'Optimization'
            Enabled     = (-not $MainConfig.modules.skipSystemOptimization)
        },
        @{
            Name        = 'TelemetryDisable'
            Description = 'Analyze and disable Windows telemetry (Type2→Type1 flow)'
            ModuleName  = 'TelemetryDisable'
            Function    = 'Invoke-TelemetryDisable'
            Type        = 'Type2'
            Category    = 'Privacy'
            Enabled     = (-not $MainConfig.modules.skipTelemetryDisable)
        },
        @{
            Name        = 'WindowsUpdates'
            Description = 'Analyze and install Windows updates (Type2→Type1 flow)'
            ModuleName  = 'WindowsUpdates'
            Function    = 'Invoke-WindowsUpdates'
            Type        = 'Type2'
            Category    = 'Updates'
            Enabled     = (-not $MainConfig.modules.skipWindowsUpdates)
        },
        @{
            Name        = 'AppUpgrade'
            Description = 'Analyze and upgrade applications via Winget/Chocolatey (Type2→Type1 flow)'
            ModuleName  = 'AppUpgrade'
            Function    = 'Invoke-AppUpgrade'
            Type        = 'Type2'
            Category    = 'Updates'
            Enabled     = (-not $MainConfig.modules.skipAppUpgrade)
        },
        @{
            Name        = 'SecurityEnhancement'
            Description = 'Analyze and enhance system security posture (Type2→Type1 flow)'
            ModuleName  = 'SecurityEnhancement'
            Function    = 'Invoke-SecurityEnhancement'
            Type        = 'Type2'
            Category    = 'Security'
            Enabled     = (-not $MainConfig.modules.skipSecurityEnhancement)
        }
    )
    # v3.0: Filter enabled tasks and verify functions are available
    $AvailableTasks = @()
    foreach ($task in $MaintenanceTasks) {
        if ($task.Enabled) {
            # Verify the standardized Invoke-[ModuleName] function is available
            if (Get-Command -Name $task.Function -ErrorAction SilentlyContinue) {
                $AvailableTasks += $task
                Write-Information "   Available: $($task.Name) - $($task.Function)" -InformationAction Continue
            }
            else {
                Write-Warning "   Skipped: $($task.Name) - function $($task.Function) not available (module may not be v3.0 compliant)"
            }
        }
        else {
            Write-Information "  ⊝ Disabled: $($task.Name) (disabled in configuration)" -InformationAction Continue
        }
    }
    Write-Information "   Registered $($AvailableTasks.Count) available tasks" -InformationAction Continue
    #endregion
    #region Execution Mode Selection
    $ExecutionParams = @{
        Mode          = 'Execute'
        DryRun        = $false
        SelectedTasks = $AvailableTasks
    }
    if (-not $NonInteractive) {
        Write-Information "`nStarting interactive mode..." -InformationAction Continue
        # Show hierarchical menu with integrated task selection
        $menuResult = Show-MainMenu -CountdownSeconds $MainConfig.execution.countdownSeconds -AvailableTasks $AvailableTasks
        # Apply menu selections
        $ExecutionParams.DryRun = $menuResult.DryRun
        if (-not $TaskNumbers) {
            # Use tasks selected from the integrated menu system
            $ExecutionParams.SelectedTasks = @()
            foreach ($taskIndex in $menuResult.SelectedTasks) {
                if ($taskIndex -ge 1 -and $taskIndex -le $AvailableTasks.Count) {
                    $ExecutionParams.SelectedTasks += $AvailableTasks[$taskIndex - 1]
                }
            }
            Write-Information "   Menu selections applied:" -InformationAction Continue
            Write-Information "    - Execution mode: $(if ($ExecutionParams.DryRun) { 'DRY-RUN' } else { 'NORMAL' })" -InformationAction Continue
            Write-Information "    - Selected tasks: $($ExecutionParams.SelectedTasks.Count)/$($AvailableTasks.Count)" -InformationAction Continue
        }
    }
    else {
        Write-Information "`nNon-interactive mode enabled" -InformationAction Continue
        if ($DryRun) {
            $ExecutionParams.DryRun = $true
            Write-Information "   Dry-run mode enabled" -InformationAction Continue
        }
    }
    # Handle TaskNumbers parameter
    if ($TaskNumbers) {
        try {
            $taskNumbersArray = $TaskNumbers -split ',' | ForEach-Object { [int]$_.Trim() }
            $selectedTasks = @()
            foreach ($taskNum in $taskNumbersArray) {
                if ($taskNum -ge 1 -and $taskNum -le $AvailableTasks.Count) {
                    $selectedTasks += $AvailableTasks[$taskNum - 1]
                }
                else {
                    Write-Warning "Invalid task number: $taskNum (valid range: 1-$($AvailableTasks.Count))"
                }
            }
            $ExecutionParams.SelectedTasks = $selectedTasks
            Write-Information "   Task selection: $($taskNumbersArray -join ', ')" -InformationAction Continue
        }
        catch {
            Write-Error "Invalid TaskNumbers parameter format: $TaskNumbers"
            exit 1
        }
    }
    #endregion
    #region Task Execution
    Write-Information "`nStarting maintenance execution..." -InformationAction Continue
    $executionMode = if ($ExecutionParams.DryRun) { "DRY-RUN" } else { "LIVE" }
    Write-Information "Execution Mode: $executionMode" -InformationAction Continue
    Write-Information "Selected Tasks: $($ExecutionParams.SelectedTasks.Count)/$($AvailableTasks.Count)" -InformationAction Continue
    # Log execution start
    Write-LogEntry -Level 'INFO' -Component 'ORCHESTRATOR' -Message "Starting maintenance execution" -Data @{
        ExecutionMode      = $executionMode
        SelectedTasksCount = $ExecutionParams.SelectedTasks.Count
        TotalTasksCount    = $AvailableTasks.Count
        DryRun             = $ExecutionParams.DryRun
    }
    if ($ExecutionParams.SelectedTasks.Count -eq 0) {
        Write-Warning "No tasks selected for execution"
        exit 0
    }
    # Show final confirmation for system modification tasks
    $type2Tasks = $ExecutionParams.SelectedTasks | Where-Object { $_.Type -eq 'Type2' }
    if ($type2Tasks.Count -gt 0 -and -not $ExecutionParams.DryRun -and -not $NonInteractive) {
        $confirmMessage = "About to execute $($type2Tasks.Count) system modification task(s). Continue?"
        $confirmed = Show-ConfirmationDialog -Message $confirmMessage -CountdownSeconds 10
        if (-not $confirmed) {
            Write-Information "Operation cancelled by user" -InformationAction Continue
            exit 0
        }
    }
    # Initialize execution tracking
    $TaskResults = @()
    $StartTime = Get-Date
    Write-Information "`nExecuting tasks..." -InformationAction Continue
    Write-Information "" -InformationAction Continue
    for ($i = 0; $i -lt $ExecutionParams.SelectedTasks.Count; $i++) {
        $task = $ExecutionParams.SelectedTasks[$i]
        $taskNumber = $i + 1
        $totalTasks = $ExecutionParams.SelectedTasks.Count
        Write-Information "" -InformationAction Continue
        Write-Information "[$taskNumber/$totalTasks] $($task.Name)" -InformationAction Continue
        Write-Information "Description: $($task.Description)" -InformationAction Continue
        Write-Information "Type: $($task.Type) | Category: $($task.Category)" -InformationAction Continue
        if ($ExecutionParams.DryRun) {
            Write-Information "Mode: DRY-RUN (simulation)" -InformationAction Continue
        }
        $taskStartTime = Get-Date
        $taskResult = @{
            TaskName    = $task.Name
            Description = $task.Description
            Type        = $task.Type
            Category    = $task.Category
            StartTime   = $taskStartTime
            Success     = $false
            DryRun      = $ExecutionParams.DryRun
            Output      = ''
            Error       = $null
            Duration    = $null
        }
        try {
            # v3.0 Architecture: Simplified execution using standardized Invoke-[ModuleName] functions
            # Type2 modules are already loaded and self-contained with their Type1 dependencies
            # Log task start
            Write-LogEntry -Level 'INFO' -Component 'ORCHESTRATOR' -Message "Starting task: $($task.Name)" -Data @{
                TaskType     = $task.Type
                TaskCategory = $task.Category
                Function     = $task.Function
                DryRun       = $ExecutionParams.DryRun
                Architecture = 'v3.1'
            }
            # Verify function is available (already checked during module loading)
            if (-not (Get-Command -Name $task.Function -ErrorAction SilentlyContinue)) {
                throw "Function '$($task.Function)' not available - ensure $($task.ModuleName) module is properly loaded"
            }
            # Execute the standardized v3.0 function with consistent parameters
            $result = $null
            try {
                if ($ExecutionParams.DryRun) {
                    Write-Information "   Simulating: $($task.Function)" -InformationAction Continue
                    $result = & $task.Function -Config $MainConfig -DryRun
                }
                else {
                    Write-Information "   Executing: $($task.Function)" -InformationAction Continue
                    $result = & $task.Function -Config $MainConfig
                }
                # Validate standardized return structure (support both hashtable and PSCustomObject)
                $hasValidStructure = $false
                if ($result) {
                    if ($result -is [hashtable] -and $result.ContainsKey('Success')) {
                        $hasValidStructure = $true
                    }
                    elseif ($result -is [PSCustomObject] -and (Get-Member -InputObject $result -Name 'Success' -ErrorAction SilentlyContinue)) {
                        $hasValidStructure = $true
                    }
                }
                if ($hasValidStructure) {
                    Write-Information "   v3.0 compliant result: Success=$($result.Success), Items Detected=$($result.ItemsDetected), Items Processed=$($result.ItemsProcessed)" -InformationAction Continue
                    
                    # Patch 3: Collect module result for aggregation
                    if ($script:ResultCollectionEnabled) {
                        try {
                            $moduleDuration = ((Get-Date) - $taskStartTime).TotalSeconds
                            $moduleStatus = if ($result.Success) { 'Success' } else { 'Failed' }
                            $moduleResultObj = New-ModuleResult `
                                -ModuleName $task.Name `
                                -Status $moduleStatus `
                                -ItemsDetected $($result.ItemsDetected -as [int]) `
                                -ItemsProcessed $($result.ItemsProcessed -as [int]) `
                                -DurationSeconds $moduleDuration
                            Add-ModuleResult -Result $moduleResultObj
                            Write-Information "     [Aggregation] Module result collected for reporting" -InformationAction Continue
                        }
                        catch {
                            Write-Warning "     [Aggregation] Failed to collect module result: $($_.Exception.Message)"
                        }
                    }
                }
                else {
                    $resultType = if ($result) { $result.GetType().Name } else { 'null' }
                    $resultCount = if ($result -is [array]) { $result.Count } else { 1 }
                    $hasSuccessKey = if ($result -is [array] -and $result.Count -gt 0) { 
                        ($result[0] -is [hashtable] -and $result[0].ContainsKey('Success')) -or 
                        ($result[0] -is [PSCustomObject] -and (Get-Member -InputObject $result[0] -Name 'Success' -ErrorAction SilentlyContinue))
                    }
                    elseif ($result) {
                        ($result -is [hashtable] -and $result.ContainsKey('Success')) -or 
                        ($result -is [PSCustomObject] -and (Get-Member -InputObject $result -Name 'Success' -ErrorAction SilentlyContinue))
                    }
                    else { $false }
                    
                    # If it's an array, search for a valid result object anywhere in the array (pipeline contamination fix)
                    if ($result -is [array]) {
                        $validResult = $result | Where-Object { ($_ -is [hashtable] -and $_.ContainsKey('Success')) -or ($_ -is [PSCustomObject] -and (Get-Member -InputObject $_ -Name 'Success' -ErrorAction SilentlyContinue)) } | Select-Object -First 1
                        if ($validResult) {
                            Write-LogEntry -Level 'DEBUG' -Component 'ORCHESTRATOR' -Message "Extracted valid result from array" -Data @{ Module = $task.Function; ArrayCount = $result.Count }
                            $result = $validResult
                            $hasValidStructure = $true
                            Write-Information "   v3.0 compliant result: Success=$($result.Success), Items Detected=$($result.ItemsDetected), Items Processed=$($result.ItemsProcessed)" -InformationAction Continue
                        }
                        else {
                            Write-Warning "   Non-standard result format from $($task.Function) - Result type: $resultType, Count: $resultCount, Has Success key: $hasSuccessKey"
                        }
                    }
                    else {
                        Write-Warning "   Non-standard result format from $($task.Function) - Result type: $resultType, Count: $resultCount, Has Success key: $hasSuccessKey"
                        
                        # Collect module result for aggregation after fixing the format
                        if ($script:ResultCollectionEnabled -and $hasValidStructure) {
                            try {
                                $moduleDuration = ((Get-Date) - $taskStartTime).TotalSeconds
                                $moduleStatus = if ($result.Success) { 'Success' } else { 'Failed' }
                                $moduleResultObj = New-ModuleResult `
                                    -ModuleName $task.Name `
                                    -Status $moduleStatus `
                                    -ItemsDetected $($result.ItemsDetected -as [int]) `
                                    -ItemsProcessed $($result.ItemsProcessed -as [int]) `
                                    -DurationSeconds $moduleDuration
                                Add-ModuleResult -Result $moduleResultObj
                                Write-LogEntry -Level 'DEBUG' -Component 'ORCHESTRATOR' -Message "Module result collected for reporting (format corrected)" -Data @{ Module = $task.Name }
                            }
                            catch {
                                Write-Warning "     [Aggregation] Failed to collect module result: $($_.Exception.Message)"
                            }
                        }
                    }
                }
            }
            catch {
                # Capture detailed error information for debugging
                $errorDetails = @{
                    Message    = $_.Exception.Message
                    Type       = $_.Exception.GetType().Name
                    StackTrace = $_.ScriptStackTrace
                    Function   = $task.Function
                    Line       = $_.InvocationInfo.ScriptLineNumber
                }
                # Log detailed error information with structured logging
                Write-LogEntry -Level 'ERROR' -Component 'ORCHESTRATOR' -Message "Task execution failed: $($task.Name)" -Data $errorDetails
                Write-Information "[ERROR] [ORCHESTRATOR] Task failed: $($task.Name)" -InformationAction Continue
                Write-Information "  Error Type: $($errorDetails.Type)" -InformationAction Continue
                Write-Information "  Message: $($errorDetails.Message)" -InformationAction Continue
                Write-Information "  Function: $($errorDetails.Function) at line $($errorDetails.Line)" -InformationAction Continue
                throw "Task execution failed: $($_.Exception.Message)"
            }
            $taskResult.Success = $true
            $taskResult.Output = $result
            Write-Information "   Completed successfully" -InformationAction Continue
            # Log task success with detailed metrics
            Write-LogEntry -Level 'SUCCESS' -Component 'ORCHESTRATOR' -Message "Task completed successfully: $($task.Name)" -Data @{
                Duration   = ((Get-Date) - $taskStartTime).TotalSeconds
                OutputType = if ($null -ne $result) { $result.GetType().Name } else { 'null' }
                ResultSize = if ($null -ne $result -and $result -is [string]) { $result.Length } elseif ($null -ne $result -and $result -is [array]) { $result.Count } else { 0 }
            }
        }
        catch [System.OperationCanceledException] {
            $taskResult.Success = $false
            $taskResult.Error = "Task was cancelled by user or system"
            Write-Information "  ⏸ Cancelled: Task was cancelled" -InformationAction Continue
            Write-LogEntry -Level 'WARNING' -Component 'ORCHESTRATOR' -Message "Task cancelled: $($task.Name)" -Data @{
                Duration = ((Get-Date) - $taskStartTime).TotalSeconds
            }
        }
        catch [System.TimeoutException] {
            $taskResult.Success = $false
            $taskResult.Error = "Task timed out: $($_.Exception.Message)"
            Write-Information "  ⏱ Timeout: $($_.Exception.Message)" -InformationAction Continue
            Write-LogEntry -Level 'ERROR' -Component 'ORCHESTRATOR' -Message "Task timeout: $($task.Name)" -Data @{
                Error    = $_.Exception.Message
                Duration = ((Get-Date) - $taskStartTime).TotalSeconds
            }
        }
        catch [System.OutOfMemoryException] {
            $taskResult.Success = $false
            $taskResult.Error = "Out of memory error during task execution"
            Write-Information "   Memory Error: Insufficient memory to complete task" -InformationAction Continue
            Write-LogEntry -Level 'CRITICAL' -Component 'ORCHESTRATOR' -Message "Out of memory error: $($task.Name)" -Data @{
                Duration    = ((Get-Date) - $taskStartTime).TotalSeconds
                MemoryUsage = [System.GC]::GetTotalMemory($false)
            }
            # Force garbage collection
            [System.GC]::Collect()
            [System.GC]::WaitForPendingFinalizers()
        }
        catch {
            $taskResult.Success = $false
            $taskResult.Error = $_.Exception.Message
            Write-Information "   Failed: $($_.Exception.Message)" -InformationAction Continue
            # Enhanced error logging with full context
            $errorContext = @{
                Error        = $_.Exception.Message
                ErrorType    = $_.Exception.GetType().Name
                Duration     = ((Get-Date) - $taskStartTime).TotalSeconds
                StackTrace   = $_.ScriptStackTrace
                TaskFunction = $task.Function
                ModulePath   = $task.ModulePath
                ScriptLine   = $_.InvocationInfo.ScriptLineNumber
                Command      = $_.InvocationInfo.MyCommand.Name
            }
            Write-LogEntry -Level 'ERROR' -Component 'ORCHESTRATOR' -Message "Task failed: $($task.Name)" -Data $errorContext
            # Additional troubleshooting information
            Write-Information "  ℹ Error Type: $($_.Exception.GetType().Name)" -InformationAction Continue
            if ($_.InvocationInfo.ScriptLineNumber) {
                Write-Information "  ℹ Error at line: $($_.InvocationInfo.ScriptLineNumber)" -InformationAction Continue
            }
            if ($_.ScriptStackTrace) {
                Write-Verbose "Full stack trace: $($_.ScriptStackTrace)"
            }
        }
        finally {
            $taskResult.Duration = ((Get-Date) - $taskStartTime).TotalSeconds
            $TaskResults += $taskResult
            Write-Information "  Duration: $([math]::Round($taskResult.Duration, 2)) seconds" -InformationAction Continue
        }
    }
    #endregion
    #region Report Generation (v3.1 Architecture - Enhanced)
    # Generate comprehensive reports using v3.0 split architecture: LogProcessor → ReportGenerator
    Write-Information "" -InformationAction Continue
    Write-Information " Generating maintenance reports..." -InformationAction Continue
    try {
        # SystemAnalysis module is optional in v3.0 - not loaded by default for performance
        # All necessary data comes from Type1/Type2 module logs processed by LogProcessor
        # If needed in future, add SystemAnalysis to core modules list and use inventory here
        # v3.0 Split Architecture: LogProcessor → ReportGenerator pipeline
        Write-Information "`nProcessing logs and generating reports using split architecture..." -InformationAction Continue
        
        # Patch 4: Finalize and export aggregated results
        if ($script:ResultCollectionEnabled) {
            Write-Information "`n  Finalizing session result collection..." -InformationAction Continue
            try {
                $aggregatedResultsPath = Join-Path $ProcessedDataPath 'aggregated-results.json'
                $aggregatedResults = Complete-ResultCollection -ExportPath $aggregatedResultsPath
                if ($aggregatedResults) {
                    Write-Information "    [OK] Result collection finalized" -InformationAction Continue
                    Write-Information "    [INFO] Summary: Total modules=$($aggregatedResults.Summary.TotalModules), Success=$($aggregatedResults.Summary.SuccessfulModules), Failed=$($aggregatedResults.Summary.FailedModules)" -InformationAction Continue
                    Write-Information "    [INFO] Aggregated results exported to: $aggregatedResultsPath" -InformationAction Continue
                    $script:MaintenanceSessionData.AggregatedResults = $aggregatedResults
                    $script:MaintenanceSessionData.Summary = $aggregatedResults.Summary
                }
            }
            catch {
                Write-Warning "  Failed to finalize result collection: $($_.Exception.Message)"
            }
        }
        
        try {
            # Step 1: Process logs using LogProcessor module
            if (Get-Command -Name 'Invoke-LogProcessing' -ErrorAction SilentlyContinue) {
                Write-Information "  Step 1: Processing logs with LogProcessor..." -InformationAction Continue
                # LogProcessor reads directly from temp_files/data and temp_files/logs
                # It does not accept TaskResults, SystemInventory, or Configuration parameters
                Invoke-LogProcessing
                Write-Information "  Log processing completed successfully" -InformationAction Continue
            }
            else {
                throw "LogProcessor module (Invoke-LogProcessing) not available"
            }
            # Step 2: Generate reports using ReportGenerator module
            if (Get-Command -Name 'New-MaintenanceReport' -ErrorAction SilentlyContinue) {
                Write-Information "  Step 2: Generating reports with ReportGenerator..." -InformationAction Continue
                # Create reports directory
                $reportsDir = Join-Path $Global:ProjectPaths.TempFiles "reports"
                New-Item -Path $reportsDir -ItemType Directory -Force | Out-Null
                $reportBasePath = Join-Path $reportsDir "MaintenanceReport_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').html"
                # Generate report using processed data (with fallback capability)
                $reportResult = New-MaintenanceReport -OutputPath $reportBasePath -EnableFallback
                if ($reportResult -and $reportResult.Success) {
                    Write-Information "   Reports generated successfully using split architecture" -InformationAction Continue
                    if ($reportResult.ReportPaths) {
                        foreach ($reportPath in $reportResult.ReportPaths) {
                            Write-Information "    • $reportPath" -InformationAction Continue
                        }
                    }
                    # Copy main HTML report to parent directory (Desktop/Documents/USB root)
                    if ($reportResult.HtmlReport -and (Test-Path $reportResult.HtmlReport)) {
                        try {
                            $parentHtmlPath = Join-Path $script:ProjectPaths.ParentDir (Split-Path -Leaf $reportResult.HtmlReport)
                            Copy-Item -Path $reportResult.HtmlReport -Destination $parentHtmlPath -Force
                            Write-Information "   HTML report copied to: $parentHtmlPath" -InformationAction Continue
                            # Update result to include parent copy location
                            if (-not $reportResult.ParentCopy) {
                                $reportResult | Add-Member -NotePropertyName 'ParentCopy' -NotePropertyValue $parentHtmlPath -Force
                            }
                        }
                        catch {
                            Write-Warning "   Failed to copy HTML report to parent directory: $($_.Exception.Message)"
                        }
                    }
                }
                else {
                    throw "ReportGenerator failed: $(if ($reportResult.Error) { $reportResult.Error } else { 'Unknown error' })"
                }
            }
            else {
                throw "ReportGenerator module (New-MaintenanceReport) not available"
            }
        }
        catch {
            Write-Warning "   Split architecture report generation failed: $($_.Exception.Message)"
            Write-Information "   Attempting fallback report generation..." -InformationAction Continue
            # Fallback: Try to generate basic report with available data
            if (Get-Command -Name 'New-MaintenanceReport' -ErrorAction SilentlyContinue) {
                try {
                    $reportsDir = Join-Path $script:ProjectPaths.TempFiles "reports"
                    New-Item -Path $reportsDir -ItemType Directory -Force | Out-Null
                    $fallbackReportPath = Join-Path $reportsDir "MaintenanceReport_Fallback_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').html"
                    $fallbackResult = New-MaintenanceReport -OutputPath $fallbackReportPath -EnableFallback
                    if ($fallbackResult -and $fallbackResult.Success) {
                        Write-Information "   Fallback report generated successfully" -InformationAction Continue
                    }
                }
                catch {
                    Write-Warning "   Both split architecture and fallback report generation failed"
                }
            }
        }
    }
    catch {
        Write-Warning "   Error during report generation: $($_.Exception.Message)"
    }
    #endregion

    #region Report Index Generation
    Write-Information "" -InformationAction Continue
    Write-Information " Generating report index..." -InformationAction Continue
    try {
        $reportsDir = Join-Path $Global:ProjectPaths.TempFiles "reports"
        if ((Get-Command -Name 'New-ReportIndex' -ErrorAction SilentlyContinue) -and (Test-Path $reportsDir)) {
            $indexResult = New-ReportIndex -ReportsPath $reportsDir
            if ($indexResult.Success) {
                Write-Information "  Report index generated: $($indexResult.IndexPath)" -InformationAction Continue
                Write-Information "  Indexed $($indexResult.ReportCount) reports" -InformationAction Continue
            }
            else {
                Write-Warning "  Failed to generate report index: $($indexResult.Errors -join '; ')"
            }
        }
    }
    catch {
        Write-Warning "  Error generating report index: $($_.Exception.Message)"
    }
    #endregion

    #region Execution Summary
    Write-Information "" -InformationAction Continue
    Write-Information "" -InformationAction Continue
    Write-Information "    EXECUTION SUMMARY" -InformationAction Continue
    Write-Information "" -InformationAction Continue
    $totalDuration = ((Get-Date) - $StartTime).TotalSeconds
    $successfulTasks = ($TaskResults | Where-Object { $_.Success }).Count
    $failedTasks = ($TaskResults | Where-Object { -not $_.Success }).Count
    Write-Information "" -InformationAction Continue
    Write-Information "Execution Mode: $executionMode" -InformationAction Continue
    Write-Information "Task Duration: $([math]::Round($totalDuration, 2)) seconds" -InformationAction Continue
    Write-Information "Total Session: $([math]::Round(((Get-Date) - $SessionStartTime).TotalSeconds, 2)) seconds" -InformationAction Continue
    Write-Information "Tasks Executed: $($TaskResults.Count)" -InformationAction Continue
    Write-Information "Successful: $successfulTasks" -InformationAction Continue
    Write-Information "Failed: $failedTasks" -InformationAction Continue
    Write-Information "" -InformationAction Continue
    Write-Information "Task Results:" -InformationAction Continue
    Write-Information "" -InformationAction Continue
    foreach ($result in $TaskResults) {
        $status = if ($result.Success) { '' } else { '' }
        $statusColor = if ($result.Success) { 'Green' } else { 'Red' }
        $durationText = "$([math]::Round($result.Duration, 2))s"
        # Use colored output for better visual feedback
        Write-Host "  $status $($result.TaskName) ($durationText)" -ForegroundColor $statusColor
        if (-not $result.Success -and $result.Error) {
            Write-Host "    Error: $($result.Error)" -ForegroundColor Red
        }
    }
    # Save execution results
    $executionSummary = @{
        ExecutionMode          = $executionMode
        SessionStartTime       = $SessionStartTime
        TaskExecutionStartTime = $StartTime
        EndTime                = Get-Date
        TotalDuration          = $totalDuration
        SessionDuration        = ((Get-Date) - $SessionStartTime).TotalSeconds
        TasksExecuted          = $TaskResults.Count
        SuccessfulTasks        = $successfulTasks
        FailedTasks            = $failedTasks
        TaskResults            = $TaskResults
        Configuration          = $MainConfig
    }
    $reportsDir = Join-Path $script:ProjectPaths.TempRoot "reports"
    $summaryPath = Join-Path $reportsDir "execution-summary-$script:MaintenanceSessionTimestamp.json"
    $executionSummary | ConvertTo-Json -Depth 20 -WarningAction SilentlyContinue | Out-File -FilePath $summaryPath -Encoding UTF8
    Write-Information "" -InformationAction Continue
    Write-Information "Execution summary saved to: $summaryPath" -InformationAction Continue
    # FIX #9: Create session manifest with complete execution metadata
    Write-Information "" -InformationAction Continue
    Write-Information " Creating session manifest..." -InformationAction Continue
    $manifestPath = New-SessionManifest -SessionId $script:MaintenanceSessionId `
        -ExecutionMode $executionMode `
        -ModuleResults $TaskResults `
        -ExecutionStartTime $StartTime `
        -IsDryRun:($executionMode -eq 'DryRun')
    if ($manifestPath) {
        if (Test-Path $manifestPath) {
            Write-Information "   Session manifest successfully created" -InformationAction Continue
        }
        else {
            Write-Information "   Session manifest path returned but file not found" -InformationAction Continue
        }
    }
    else {
        Write-Information "   Session manifest creation encountered issues" -InformationAction Continue
    }
    # Copy final reports to parent directory (same level as repo folder)
    Write-Information "" -InformationAction Continue
    Write-Information " Copying final reports to parent directory..." -InformationAction Continue
    # Get parent directory of the script root (one level up from repo folder)
    $ParentDir = Split-Path $ScriptRoot -Parent
    Write-Information "   Target directory: $ParentDir" -InformationAction Continue
    $finalReports = @()
    $reportsToMove = @(
        @{ Pattern = "maintenance-report-$script:MaintenanceSessionTimestamp.html"; Description = "HTML maintenance report" }
        @{ Pattern = "maintenance-report-$script:MaintenanceSessionTimestamp.txt"; Description = "Text maintenance report" }
        @{ Pattern = "maintenance-log-$script:MaintenanceSessionTimestamp.log"; Description = "Maintenance log file" }
    )
    foreach ($reportInfo in $reportsToMove) {
        $sourcePattern = $reportInfo.Pattern
        $description = $reportInfo.Description
        # Look for the file in temp directories
        $sourceFile = $null
        $reportsDir = Join-Path $script:ProjectPaths.TempRoot "reports"
        $logsDir = Join-Path $script:ProjectPaths.TempRoot "logs"
        $searchPaths = @($reportsDir, $logsDir, $script:ProjectPaths.TempRoot) | Where-Object { $_ -and (Test-Path $_) }
        foreach ($searchPath in $searchPaths) {
            $potentialPath = Join-Path $searchPath $sourcePattern
            if (Test-Path $potentialPath) {
                $sourceFile = $potentialPath
                break
            }
        }
        if ($sourceFile) {
            $fileName = Split-Path $sourceFile -Leaf
            $destPath = Join-Path $ParentDir $fileName
            try {
                # Ensure parent directory is accessible
                if (-not (Test-Path $ParentDir)) {
                    Write-Information "   Parent directory not accessible: $ParentDir" -InformationAction Continue
                    continue
                }
                Copy-Item -Path $sourceFile -Destination $destPath -Force
                Write-Information "   Copied $description to: $destPath" -InformationAction Continue
                $finalReports += $destPath
            }
            catch {
                Write-Information "   Failed to copy $description`: $_" -InformationAction Continue
            }
        }
    }
}
catch {
    Write-Error "Fatal error in maintenance orchestration: $($_.Exception.Message)"
    Write-Information "  Stack Trace: $($_.ScriptStackTrace)" -InformationAction Continue
    exit 1
}
if ($finalReports.Count -gt 0) {
    Write-Information "" -InformationAction Continue
    Write-Information " Final reports available in parent directory:" -InformationAction Continue
    Write-Information "   Location: $ParentDir" -InformationAction Continue
    foreach ($report in $finalReports) {
        Write-Information "  • $(Split-Path $report -Leaf)" -InformationAction Continue
    }
}

# v3.2 Post-Execution Shutdown Sequence
if (Get-Command -Name 'Start-MaintenanceCountdown' -ErrorAction SilentlyContinue) {
    Write-Information "`n" -InformationAction Continue
    try {
        # Load shutdown configuration
        $shutdownConfig = @{
            CountdownSeconds = $MainConfig.execution.shutdown.countdownSeconds ?? 120
            CleanupOnTimeout = $MainConfig.execution.shutdown.cleanupOnTimeout ?? $true
            RebootOnTimeout  = $MainConfig.execution.shutdown.rebootOnTimeout ?? $false
        }
        
        Write-Information " Starting post-execution shutdown sequence..." -InformationAction Continue
        Write-LogEntry -Level 'INFO' -Component 'ORCHESTRATOR' -Message "Initiating shutdown sequence with config: $($shutdownConfig | ConvertTo-Json -Compress)"
        
        $shutdownResult = Start-MaintenanceCountdown `
            -CountdownSeconds $shutdownConfig.CountdownSeconds `
            -WorkingDirectory $ScriptRoot `
            -TempRoot $script:ProjectPaths.TempRoot `
            -CleanupOnTimeout:$shutdownConfig.CleanupOnTimeout `
            -RebootOnTimeout:$shutdownConfig.RebootOnTimeout
        
        Write-LogEntry -Level 'INFO' -Component 'ORCHESTRATOR' -Message "Shutdown sequence completed" -Data $shutdownResult
        Write-Information " Shutdown sequence action: $($shutdownResult.Action)" -InformationAction Continue
    }
    catch {
        Write-LogEntry -Level 'ERROR' -Component 'ORCHESTRATOR' -Message "Shutdown sequence failed: $($_.Exception.Message)"
        Write-Warning " Shutdown sequence error: $_"
    }
}
else {
    Write-LogEntry -Level 'WARNING' -Component 'ORCHESTRATOR' -Message "ShutdownManager module not available - skipping post-execution shutdown sequence"
}

if ($failedTasks -gt 0) {
    Write-Information "" -InformationAction Continue
    Write-Information "  Some tasks failed. Check the logs for detailed error information." -InformationAction Continue
    exit 1
}
else {
    Write-Information "" -InformationAction Continue
    Write-Information " All tasks completed successfully!" -InformationAction Continue
    exit 0
}
#endregion
