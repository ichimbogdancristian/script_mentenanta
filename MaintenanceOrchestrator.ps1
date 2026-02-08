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
.PARAMETER TaskNumbers
    Comma-separated list of task numbers to execute (e.g., "1,3,5")
.EXAMPLE
    .\MaintenanceOrchestrator.ps1
    # Interactive mode with menus
.EXAMPLE
    .\MaintenanceOrchestrator.ps1 -NonInteractive
    # Unattended mode with all tasks
.EXAMPLE
    .\MaintenanceOrchestrator.ps1 -TaskNumbers "1,2,3"
    # Run specific tasks
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
$ProjectRoot = if ($WorkingDirectory -and (Test-Path $WorkingDirectory)) { $WorkingDirectory } else { $ScriptRoot }
Write-Information "Windows Maintenance Automation - Central Orchestrator v3.1.0" -InformationAction Continue
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
$env:MAINTENANCE_PROJECT_ROOT = $ProjectRoot
$env:MAINTENANCE_CONFIG_ROOT = Join-Path $ProjectRoot 'config'
$env:MAINTENANCE_MODULES_ROOT = Join-Path $ProjectRoot 'modules'
$env:MAINTENANCE_TEMP_ROOT = Join-Path $ProjectRoot 'temp_files'
$env:MAINTENANCE_REPORTS_ROOT = $ProjectRoot
Write-Information "   Global environment variables set:" -InformationAction Continue
Write-Information "      PROJECT_ROOT: $env:MAINTENANCE_PROJECT_ROOT" -InformationAction Continue
Write-Information "       CONFIG_ROOT: $env:MAINTENANCE_CONFIG_ROOT" -InformationAction Continue
Write-Information "      MODULES_ROOT: $env:MAINTENANCE_MODULES_ROOT" -InformationAction Continue
Write-Information "      TEMP_ROOT: $env:MAINTENANCE_TEMP_ROOT" -InformationAction Continue
Write-Information "      REPORTS_ROOT: $env:MAINTENANCE_REPORTS_ROOT" -InformationAction Continue
# Detect configuration path (always relative to script location)
if (-not $ConfigPath) {
    $ConfigPath = Join-Path $ProjectRoot 'config'
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

# Set up log file (transcript) in temp_files/logs
if (-not $LogFilePath) {
    $LogFilePath = Join-Path $LogsDir 'maintenance.log'
}
$env:SCRIPT_LOG_FILE = $LogFilePath
Write-Information "Log File: $LogFilePath" -InformationAction Continue

# Start transcript for full project execution
$script:TranscriptStarted = $false
try {
    Start-Transcript -Path $LogFilePath -Append -ErrorAction Stop | Out-Null
    $script:TranscriptStarted = $true
    Write-Information "Transcript started: $LogFilePath" -InformationAction Continue
}
catch {
    Write-Warning "Failed to start transcript: $($_.Exception.Message)"
}
#endregion

#region Module Loading
Write-Information "`nLoading modules..." -InformationAction Continue
# Import core modules (always relative to project root)
$script:ModulesPath = Join-Path $ProjectRoot 'modules'
if (-not (Test-Path $script:ModulesPath)) {
    # Fallback to working directory if set by batch script
    $fallbackModulesPath = Join-Path $WorkingDirectory 'modules'
    if (Test-Path $fallbackModulesPath) {
        $script:ModulesPath = $fallbackModulesPath
    }
}
Write-Information "Modules Path: $script:ModulesPath" -InformationAction Continue
# v3.1 Split Architecture + Phase 1 Module Registry: Load essential core modules
$CoreModules = @(
    'CoreInfrastructure',  # Foundation (now includes ShutdownManager functions)
    'ModuleRegistry',      # Phase 1: Auto-discovery system
    'CommonUtilities',     # Phase 1: Shared helper functions
    'LogAggregator',       # v3.1: Result collection
    'UserInterface',       # UI & menus
    'LogProcessor',        # Data processing pipeline
    'ReportGenerator'      # Report rendering engine
)
# Type2 modules (self-contained with internal Type1 dependencies)
# Note: SystemInventory removed from Type2 - now called directly from Type1 before Type2 execution
$Type2Modules = @(
    'BloatwareRemoval',
    'EssentialApps',
    'SystemOptimization',
    'TelemetryDisable',
    'SecurityEnhancement', # Security hardening and enhancements
    'WindowsUpdates',
    'AppUpgrade'
)
$Type2ModulesPath = Join-Path $script:ModulesPath 'type2'
$script:CoreModulesPath = Join-Path $script:ModulesPath 'core'
foreach ($moduleName in $CoreModules) {
    $modulePath = Join-Path $script:CoreModulesPath "$moduleName.psm1"
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

#region Phase 2: JSON Schema Configuration Validation
# Validate all configuration files against JSON schemas (fail-fast pattern)
Write-Information "`n[Phase 2] Validating configuration files against schemas..." -InformationAction Continue
try {
    $validationResult = Test-AllConfigurationsWithSchema -ConfigRoot $env:MAINTENANCE_CONFIG_ROOT
    
    if ($validationResult.AllValid) {
        Write-Information "   ✓ All $($validationResult.ValidConfigs) configuration files validated successfully" -InformationAction Continue
    }
    else {
        Write-Error "Configuration validation failed:`n$($validationResult.Summary)"
        Write-Information "`nValidation Details:" -InformationAction Continue
        foreach ($result in $validationResult.Results) {
            if (-not $result.IsValid) {
                Write-Information "   ✗ $($result.Name): $($result.Errors -join '; ')" -InformationAction Continue
            }
        }
        Write-Information "`n[ACTION REQUIRED] Fix configuration errors and re-run the script." -InformationAction Continue
        exit 1
    }
}
catch {
    Write-Warning "Configuration validation error: $($_.Exception.Message)"
    Write-Information "   Continuing with legacy validation fallback..." -InformationAction Continue
}
#endregion

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

#region Phase 1: Module Discovery & Validation
Write-Information "`nDiscovering available modules..." -InformationAction Continue
try {
    # Use ModuleRegistry to discover Type2 modules automatically
    if (Get-Command -Name 'Get-RegisteredModules' -ErrorAction SilentlyContinue) {
        $discoveredModules = Get-RegisteredModules -ModuleType 'Type2' -IncludeMetadata
        $Type2Modules = $discoveredModules.Keys | Sort-Object
        
        Write-Information "   Discovered $($Type2Modules.Count) Type2 modules via ModuleRegistry" -InformationAction Continue
        foreach ($moduleName in $Type2Modules) {
            $module = $discoveredModules[$moduleName]
            $dependencyInfo = if ($module.DependsOn) { " → $($module.DependsOn)" } else { "" }
            Write-Information "     • $moduleName$dependencyInfo" -InformationAction Continue
        }
        
        # Validate dependencies
        Write-Information "`n   Validating module dependencies..." -InformationAction Continue
        $dependencyFailures = @()
        foreach ($moduleName in $Type2Modules) {
            if (-not (Test-ModuleDependencies -ModuleName $moduleName -Modules $discoveredModules)) {
                $dependencyFailures += $moduleName
            }
        }
        
        if ($dependencyFailures.Count -gt 0) {
            Write-Warning "   Module dependency validation failed for: $($dependencyFailures -join ', ')"
            Write-Information "   These modules will be skipped during execution" -InformationAction Continue
            # Remove failed modules from execution list
            $Type2Modules = $Type2Modules | Where-Object { $_ -notin $dependencyFailures }
        }
        else {
            Write-Information "   ✓ All module dependencies validated successfully" -InformationAction Continue
        }
    }
    else {
        # Fallback to hardcoded list if ModuleRegistry unavailable
        Write-Information "   ModuleRegistry unavailable - using hardcoded Type2 module list" -InformationAction Continue
        $Type2Modules = @(
            'BloatwareRemoval',
            'EssentialApps',
            'SystemOptimization',
            'TelemetryDisable',
            'SecurityEnhancement',
            'WindowsUpdates',
            'AppUpgrade'
        )
    }
}
catch {
    Write-Warning "Module discovery failed: $_ - using fallback list"
    $Type2Modules = @(
        'BloatwareRemoval',
        'EssentialApps',
        'SystemOptimization',
        'TelemetryDisable',
        'SecurityEnhancement',
        'WindowsUpdates',
        'AppUpgrade'
    )
}
#endregion

#region FIX #2: Validate CoreInfrastructure Functions
Write-Information "`nValidating CoreInfrastructure module..." -InformationAction Continue
try {
    $requiredCoreFunctions = @(
        'Initialize-GlobalPathDiscovery',
        'Get-MaintenancePaths',
        'Get-AuditResultsPath',
        'Save-DiffResults',
        'Start-MaintenanceCountdown'  # Phase 1: Now in CoreInfrastructure
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

#region OS Version Detection (v4.0 - Phase A.1.2)
Write-Information "`n🔍 Detecting Windows Version..." -InformationAction Continue
try {
    # Detect OS version for OS-specific operations
    $global:OSContext = Get-WindowsVersionContext
    
    if ($OSContext) {
        Write-Host "   Detected: " -NoNewline -ForegroundColor Gray
        Write-Host "$($OSContext.DisplayText)" -ForegroundColor Yellow
        Write-Host "   Architecture: $($OSContext.Architecture)" -ForegroundColor Gray
        
        # Store in script scope for later use
        $script:OSContext = $OSContext
        
        Write-Information "   OS detection completed successfully" -InformationAction Continue
    }
    else {
        Write-Warning "OS detection returned null - using safe defaults"
        # Create minimal context for failsafe operation
        $script:OSContext = [PSCustomObject]@{
            Version     = 'Unknown'
            IsWindows11 = $false
            IsWindows10 = $false
            DisplayText = 'Unknown Windows Version'
        }
    }
}
catch {
    Write-Warning "OS detection failed: $($_.Exception.Message)"
    Write-Information "   Continuing with OS-agnostic operation..." -InformationAction Continue
    
    # Create minimal context for failsafe operation
    $script:OSContext = [PSCustomObject]@{
        Version     = 'Unknown'
        IsWindows11 = $false
        IsWindows10 = $false
        DisplayText = 'Unknown Windows Version'
    }
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
    if ($createRestorePoint) {
        Ensure-SystemRestorePointSpace -MinimumGB $restorePointMinSizeGB | Out-Null
    }

    if ($createRestorePoint) {
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
            # PowerShell 7 on Windows includes Checkpoint-Computer via compatibility layer
            # If not available, system restore point creation requires Windows PowerShell
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
#region Phase 2/3: Configuration Validation
<#
    Configuration validation is handled by Phase 2 JSON Schema system:
    - Test-ConfigurationWithJsonSchema validates individual configs
    - Test-AllConfigurationsWithSchema validates all 7 configs in batch
    - Phase 3 subdirectory paths (config/lists/bloatware/, etc.) fully supported
    
    Legacy Test-ConfigurationJsonValidity removed - use schema validation instead.
#>
#endregion

#region Configuration Loading
<#
    Phase 2 JSON Schema validation already completed successfully above.
    Phase 3 subdirectory paths (config/lists/bloatware/, config/lists/essential-apps/, etc.)
    are automatically validated by Test-AllConfigurationsWithSchema.
    
    Legacy validation code removed - no need to duplicate validation.
#>
try {
    try {
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
            
            # Add OS context to configuration (v4.0 - Phase A.1.2)
            # This makes OS information available to all modules
            if ($script:OSContext) {
                $MainConfig | Add-Member -NotePropertyName 'OSContext' -NotePropertyValue $script:OSContext -Force
                Write-Information "   OS context added to configuration ($($script:OSContext.DisplayText))" -InformationAction Continue
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
            [hashtable]$Config
        )
        # Prepare task-specific parameters for Type2 modules
        switch ($TaskName) {
            'EssentialApps' {
                $params = @{ Config = $Config }
                return & $FunctionName @params
            }
            'BloatwareRemoval' {
                $params = @{ Config = $Config }
                return & $FunctionName @params
            }
            'TelemetryDisable' {
                $params = @{ Config = $Config }
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
    
    #region v4.0: Intelligent Orchestration Functions (Phase C.3)
    
    <#
.SYNOPSIS
    Shows execution mode selection menu (v4.0)
.DESCRIPTION
    Presents three execution modes:
    1. Intelligent Mode (Recommended) - Audit first, run only what's needed
    2. Manual Task Selection - Traditional mode with task picker
    3. Full System Audit Only - Scan without modifications
.OUTPUTS
    String indicating selected mode: 'Intelligent', 'Manual', or 'AuditOnly'
#>
    function Show-ExecutionModeMenu {
        [CmdletBinding()]
        [OutputType([string])]
        param()
        
        Write-Host "`n" -NoNewline
        Write-Host "╔════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
        Write-Host "║          WINDOWS MAINTENANCE SYSTEM v4.0                   ║" -ForegroundColor Cyan
        Write-Host "║          Intelligent Orchestration Ready                   ║" -ForegroundColor Cyan
        Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
        Write-Host ""
        
        Write-Host "Select Execution Mode:" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  1. " -NoNewline -ForegroundColor White
        Write-Host "Intelligent Mode " -NoNewline -ForegroundColor Green
        Write-Host "(Recommended)" -ForegroundColor DarkGray
        Write-Host "     → Audit system first, then run only required tasks" -ForegroundColor DarkCyan
        Write-Host "     → Saves time by skipping modules with nothing to do" -ForegroundColor DarkCyan
        Write-Host "     → Shows execution plan before starting" -ForegroundColor DarkCyan
        Write-Host ""
        
        Write-Host "  2. " -NoNewline -ForegroundColor White
        Write-Host "Manual Task Selection" -ForegroundColor Cyan
        Write-Host "     → Choose specific tasks to run" -ForegroundColor DarkCyan
        Write-Host "     → Traditional mode with full control" -ForegroundColor DarkCyan
        Write-Host ""
        
        Write-Host "  3. " -NoNewline -ForegroundColor White
        Write-Host "Full System Audit Only" -ForegroundColor Magenta
        Write-Host "     → Scan system without making changes" -ForegroundColor DarkCyan
        Write-Host "     → Generate comprehensive audit report" -ForegroundColor DarkCyan
        Write-Host ""
        
        Write-Host "  0. " -NoNewline -ForegroundColor DarkRed
        Write-Host "Exit" -ForegroundColor Red
        Write-Host ""
        Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
        Write-Host ""
        
        $validChoice = $false
        $selectedMode = 'Intelligent'  # Default
        
        while (-not $validChoice) {
            $choice = Read-Host "Enter your choice (1-3, or 0 to exit) [1]"
            
            # Default to 1 if empty
            if ([string]::IsNullOrWhiteSpace($choice)) {
                $choice = '1'
            }
            
            switch ($choice) {
                '1' {
                    $selectedMode = 'Intelligent'
                    $validChoice = $true
                    Write-Host "`n✓ Selected: Intelligent Mode" -ForegroundColor Green
                }
                '2' {
                    $selectedMode = 'Manual'
                    $validChoice = $true
                    Write-Host "`n✓ Selected: Manual Task Selection" -ForegroundColor Cyan
                }
                '3' {
                    $selectedMode = 'AuditOnly'
                    $validChoice = $true
                    Write-Host "`n✓ Selected: Audit Only Mode" -ForegroundColor Magenta
                }
                '0' {
                    Write-Host "`nExiting..." -ForegroundColor Yellow
                    exit 0
                }
                default {
                    Write-Host "Invalid choice. Please enter 1, 2, 3, or 0." -ForegroundColor Red
                }
            }
        }
        
        return $selectedMode
    }
    
    <#
.SYNOPSIS
    Executes intelligent audit-first mode (v4.0)
.DESCRIPTION
    Phase 1: Runs all Type1 audit modules to detect issues
    Phase 2: Creates intelligent execution plan based on findings
    Phase 3: Shows plan and gets user confirmation
    Phase 4: Executes only required Type2 modules
    Phase 5: Generates final report
.PARAMETER AvailableTasks
    Array of available task definitions
.PARAMETER MainConfig
    Main configuration object
.PARAMETER NonInteractive
    Skip interactive confirmations
.OUTPUTS
    Array of task results from execution
#>
    function Start-IntelligentExecution {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [array]$AvailableTasks,
            
            [Parameter(Mandatory)]
            [hashtable]$MainConfig,
            
            [switch]$NonInteractive
        )
        
        Write-Host "`n" -NoNewline
        Write-Host "╔════════════════════════════════════════════════════════════╗" -ForegroundColor Green
        Write-Host "║          INTELLIGENT EXECUTION MODE                        ║" -ForegroundColor Green
        Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Green
        Write-Host ""
        
        # === Phase 1: Run All Type1 Audits ===
        Write-Host "Phase 1: System Analysis" -ForegroundColor Yellow
        Write-Host "Running comprehensive system audit..." -ForegroundColor Cyan
        Write-Host ""
        
        $auditResults = @{}
        $auditModules = @{
            'Bloatware'          = 'BloatwareDetectionAudit'
            'EssentialApps'      = 'EssentialAppsAudit'
            'SystemOptimization' = 'SystemOptimizationAudit'
            'Telemetry'          = 'TelemetryAudit'
            'Security'           = 'SecurityAudit'
            'WindowsUpdates'     = 'WindowsUpdatesAudit'
            'AppUpgrade'         = 'AppUpgradeAudit'
        }
        
        $type1Path = Join-Path $script:ModulesPath 'type1'
        
        foreach ($auditKey in $auditModules.Keys) {
            $moduleName = $auditModules[$auditKey]
            $modulePath = Join-Path $type1Path "$moduleName.psm1"
            
            Write-Host "  → Auditing: $auditKey..." -NoNewline -ForegroundColor White
            
            try {
                if (Test-Path $modulePath) {
                    Import-Module $modulePath -Force -ErrorAction Stop
                    
                    # Call the audit function based on module name
                    switch ($moduleName) {
                        'BloatwareDetectionAudit' {
                            $result = Get-BloatwareAnalysis
                            $auditResults[$auditKey] = $result
                        }
                        'EssentialAppsAudit' {
                            $result = Get-EssentialAppsAnalysis
                            $auditResults[$auditKey] = $result
                        }
                        'SystemOptimizationAudit' {
                            $result = Get-SystemOptimizationAnalysis
                            $auditResults[$auditKey] = $result
                        }
                        'TelemetryAudit' {
                            $result = Get-TelemetryAnalysis
                            $auditResults[$auditKey] = $result
                        }
                        'SecurityAudit' {
                            $result = Get-SecurityAuditAnalysis
                            $auditResults[$auditKey] = $result
                        }
                        'WindowsUpdatesAudit' {
                            $result = Get-WindowsUpdatesAnalysis
                            $auditResults[$auditKey] = $result
                        }
                        'AppUpgradeAudit' {
                            $result = Get-AppUpgradeAnalysis
                            $auditResults[$auditKey] = $result
                        }
                    }
                    Write-Host " ✓" -ForegroundColor Green
                }
                else {
                    Write-Host " ⊝ Not Found" -ForegroundColor DarkGray
                    $auditResults[$auditKey] = @{ DetectedItems = @() }
                }
            }
            catch {
                Write-Host " ✗ Failed" -ForegroundColor Red
                Write-Warning "  Error: $($_.Exception.Message)"
                $auditResults[$auditKey] = @{ DetectedItems = @() }
            }
        }
        
        Write-Host "`n  ✓ Audit phase completed" -ForegroundColor Green
        Write-Host ""
        
        # === Phase 2: Create Execution Plan ===
        Write-Host "Phase 2: Creating Execution Plan" -ForegroundColor Yellow
        
        try {
            # Import ExecutionPlanner module
            $plannerPath = Join-Path $script:CoreModulesPath 'ExecutionPlanner.psm1'
            if (Test-Path $plannerPath) {
                Import-Module $plannerPath -Force -ErrorAction Stop
                
                $executionPlan = New-ExecutionPlan -AuditResults $auditResults -Config $MainConfig
                
                # === Phase 3: Show Plan and Get Confirmation ===
                Write-Host ""
                Show-ExecutionPlan -ExecutionPlan $executionPlan
                
                if ($executionPlan.TotalRequiredModules -eq 0) {
                    Write-Host "`n✓ System Analysis Complete!" -ForegroundColor Green
                    Write-Host "  No maintenance tasks required - system is already optimized." -ForegroundColor Cyan
                    Write-Host ""
                    return @()
                }
                
                # Get user confirmation
                if (-not $NonInteractive) {
                    Write-Host ""
                    $confirm = Read-Host "Execute this plan? (Y/N) [Y]"
                    if ([string]::IsNullOrWhiteSpace($confirm)) {
                        $confirm = 'Y'
                    }
                    
                    if ($confirm -notmatch '^[Yy]') {
                        Write-Host "`nExecution cancelled by user" -ForegroundColor Yellow
                        return @()
                    }
                }
                
                # === Phase 4: Execute Required Modules ===
                Write-Host "`n" -NoNewline
                Write-Host "Phase 3: Executing Required Tasks" -ForegroundColor Yellow
                Write-Host ""
                
                $taskResults = @()
                $taskNumber = 1
                
                foreach ($module in $executionPlan.RequiredModules) {
                    $moduleName = $module.Name
                    $taskInfo = $AvailableTasks | Where-Object { $_.Name -eq $moduleName } | Select-Object -First 1
                    
                    if ($taskInfo) {
                        Write-Host "[$taskNumber/$($executionPlan.RequiredModules.Count)] Executing: $moduleName" -ForegroundColor Cyan
                        
                        try {
                            $taskStartTime = Get-Date
                            
                            # Execute the module
                            $result = & $taskInfo.Function
                            
                            $taskEndTime = Get-Date
                            $duration = ($taskEndTime - $taskStartTime).TotalSeconds
                            
                            $taskResults += @{
                                TaskName       = $moduleName
                                Success        = ($result.Status -eq 'Success')
                                ItemsDetected  = $module.ItemCount
                                ItemsProcessed = if ($result.SuccessfulOperations) { $result.SuccessfulOperations } else { 0 }
                                Duration       = $duration
                                StartTime      = $taskStartTime.ToString('yyyy-MM-dd HH:mm:ss')
                                EndTime        = $taskEndTime.ToString('yyyy-MM-dd HH:mm:ss')
                            }
                            
                            Write-Host "  ✓ Completed in $([math]::Round($duration, 1))s" -ForegroundColor Green
                        }
                        catch {
                            Write-Host "  ✗ Execution failed: $($_.Exception.Message)" -ForegroundColor Red
                            
                            $taskResults += @{
                                TaskName       = $moduleName
                                Success        = $false
                                ItemsDetected  = $module.ItemCount
                                ItemsProcessed = 0
                                Duration       = 0
                                Error          = $_.Exception.Message
                            }
                        }
                        
                        $taskNumber++
                    }
                }
                
                Write-Host "`n✓ Intelligent Execution Complete!" -ForegroundColor Green
                return $taskResults
            }
            else {
                Write-Warning "ExecutionPlanner module not found: $plannerPath"
                Write-Host "Falling back to manual mode..." -ForegroundColor Yellow
                return $null
            }
        }
        catch {
            Write-Error "Failed to create execution plan: $($_.Exception.Message)"
            Write-Host "Falling back to manual mode..." -ForegroundColor Yellow
            return $null
        }
    }
    
    <#
.SYNOPSIS
    Executes audit-only mode without system modifications (v4.0)
.DESCRIPTION
    Runs all Type1 audit modules to scan the system
    Generates comprehensive audit report
    Does not execute any Type2 modules (no system changes)
.OUTPUTS
    Array of audit results
#>
    function Start-AuditOnlyMode {
        [CmdletBinding()]
        param()
        
        Write-Host "`n" -NoNewline
        Write-Host "╔════════════════════════════════════════════════════════════╗" -ForegroundColor Magenta
        Write-Host "║          AUDIT-ONLY MODE                                   ║" -ForegroundColor Magenta
        Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Magenta
        Write-Host ""
        Write-Host "Scanning system (read-only, no modifications)..." -ForegroundColor Cyan
        Write-Host ""
        
        $auditResults = @{}
        $auditModules = @{
            'SystemInventory'    = 'SystemInventory'
            'Bloatware'          = 'BloatwareDetectionAudit'
            'EssentialApps'      = 'EssentialAppsAudit'
            'SystemOptimization' = 'SystemOptimizationAudit'
            'Telemetry'          = 'TelemetryAudit'
            'Security'           = 'SecurityAudit'
            'WindowsUpdates'     = 'WindowsUpdatesAudit'
            'AppUpgrade'         = 'AppUpgradeAudit'
        }
        
        $type1Path = Join-Path $script:ModulesPath 'type1'
        
        foreach ($auditKey in $auditModules.Keys) {
            $moduleName = $auditModules[$auditKey]
            $modulePath = Join-Path $type1Path "$moduleName.psm1"
            
            Write-Host "  → $auditKey..." -NoNewline -ForegroundColor White
            
            try {
                if (Test-Path $modulePath) {
                    Import-Module $modulePath -Force -ErrorAction Stop
                    
                    # Call the audit function based on module name
                    switch ($moduleName) {
                        'SystemInventory' {
                            $result = Get-SystemInventory -IncludeDetailed:$false
                            $auditResults[$auditKey] = $result
                        }
                        'BloatwareDetectionAudit' {
                            $result = Get-BloatwareAnalysis
                            $auditResults[$auditKey] = $result
                        }
                        'EssentialAppsAudit' {
                            $result = Get-EssentialAppsAnalysis
                            $auditResults[$auditKey] = $result
                        }
                        'SystemOptimizationAudit' {
                            $result = Get-SystemOptimizationAnalysis
                            $auditResults[$auditKey] = $result
                        }
                        'TelemetryAudit' {
                            $result = Get-TelemetryAnalysis
                            $auditResults[$auditKey] = $result
                        }
                        'SecurityAudit' {
                            $result = Get-SecurityAuditAnalysis
                            $auditResults[$auditKey] = $result
                        }
                        'WindowsUpdatesAudit' {
                            $result = Get-WindowsUpdatesAnalysis
                            $auditResults[$auditKey] = $result
                        }
                        'AppUpgradeAudit' {
                            $result = Get-AppUpgradeAnalysis
                            $auditResults[$auditKey] = $result
                        }
                    }
                    Write-Host " ✓" -ForegroundColor Green
                }
                else {
                    Write-Host " ⊝ Not Found" -ForegroundColor DarkGray
                    $auditResults[$auditKey] = @{}
                }
            }
            catch {
                Write-Host " ✗ Failed" -ForegroundColor Red
                Write-Warning "  Error: $($_.Exception.Message)"
                $auditResults[$auditKey] = @{}
            }
        }
        
        Write-Host "`n✓ System audit completed" -ForegroundColor Green
        Write-Host "  Results saved to temp_files/data/" -ForegroundColor Cyan
        Write-Host "  Report will be generated after this session" -ForegroundColor Cyan
        Write-Host ""
        
        # Save audit results to JSON for report generation
        $dataPath = Join-Path $env:MAINTENANCE_TEMP_ROOT 'data'
        if (-not (Test-Path $dataPath)) {
            New-Item -Path $dataPath -ItemType Directory -Force | Out-Null
        }
        
        $auditJsonPath = Join-Path $dataPath "audit-only-$(Get-Date -Format 'yyyy-MM-dd-HHmmss').json"
        $auditResults | ConvertTo-Json -Depth 20 | Set-Content -Path $auditJsonPath -Encoding UTF8
        Write-Host "  Audit data exported: $auditJsonPath" -ForegroundColor Green
        
        return $auditResults
    }
    
    #endregion
    
    #region FIX #9: Session Manifest Function
    <#
.SYNOPSIS
    Creates a session manifest file documenting the execution session
.DESCRIPTION
    FIX #9: Creates session.json file that captures complete session metadata:
    - Unique session identifier (GUID)
    - Execution timestamp (ISO 8601)
    - Execution mode (interactive/unattended)
    - Module execution results
    - Total session duration
    - Final execution status
.PARAMETER SessionId
    Unique session identifier (GUID)
.PARAMETER ExecutionMode
    Mode of execution: 'Interactive', 'Unattended', or 'Live'
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
            [datetime]$ExecutionStartTime
        )
        try {
            # Calculate execution duration
            $executionEndTime = Get-Date
            $totalDuration = ($executionEndTime - $ExecutionStartTime).TotalSeconds
            # Count successful and failed modules
            $successfulModules = @($ModuleResults | Where-Object { $_.Success -eq $true }).Count
            $failedModules = @($ModuleResults | Where-Object { $_.Success -eq $false }).Count
            # Determine final execution status
            $executionStatus = if ($failedModules -eq 0) {
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
                            executionMode  = 'Live'
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
    # Note: SystemInventory is Type1 and handled separately before Type2 modules (see line 1339)
    $MaintenanceTasks = @(
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
    
    #region v4.0: Execution Mode Selection (Phase C.3 - Intelligent Orchestration)
    $ExecutionParams = @{
        Mode          = 'Execute'
        SelectedTasks = $AvailableTasks
    }
    
    $selectedExecutionMode = 'Manual'  # Default to Manual for backward compatibility
    
    # v4.0: Show execution mode menu if interactive
    if (-not $NonInteractive -and -not $TaskNumbers) {
        Write-Information "`nStarting interactive mode..." -InformationAction Continue

        # === Stage 1: System Inventory (Type1 Modules) ===
        $type1Path = Join-Path $script:ModulesPath 'type1'
        $type1ModulesAvailable = @()

        if (Test-Path $type1Path) {
            $type1Files = Get-ChildItem -Path $type1Path -Filter "*.psm1"
            foreach ($file in $type1Files) {
                $type1ModulesAvailable += @{
                    Name = $file.BaseName
                    Path = $file.FullName
                }
            }
        }

        if ($type1ModulesAvailable.Count -gt 0) {
            $selectedIndices = Show-Type1ModuleMenu -CountdownSeconds 10 -AvailableModules $type1ModulesAvailable

            $selectedModules = @()
            if ($selectedIndices -contains 0) {
                $selectedModules = $type1ModulesAvailable
            }
            else {
                foreach ($index in $selectedIndices) {
                    if ($index -ge 1 -and $index -le $type1ModulesAvailable.Count) {
                        $selectedModules += $type1ModulesAvailable[$index - 1]
                    }
                }
            }

            if ($selectedModules.Count -gt 0) {
                Write-Host "`nExecuting selected Type1 audit modules..." -ForegroundColor Cyan

                foreach ($selectedModule in $selectedModules) {
                    Write-Host "  → Running: $($selectedModule.Name)..." -NoNewline -ForegroundColor White

                    try {
                        Import-Module $selectedModule.Path -Force -ErrorAction Stop

                        $moduleBase = $selectedModule.Name
                        $rootName = $moduleBase
                        if ($moduleBase -match 'DetectionAudit$') { $rootName = $moduleBase -replace 'DetectionAudit$', '' }
                        elseif ($moduleBase -match 'Audit$') { $rootName = $moduleBase -replace 'Audit$', '' }

                        $candidateFunctions = @(
                            "Get-$rootName`Analysis",
                            "Get-$moduleBase`Analysis",
                            "Get-$moduleBase",
                            "Start-$moduleBase",
                            "Get-$rootName",
                            "Start-$rootName"
                        )

                        $functionName = $candidateFunctions | Where-Object { Get-Command -Name $_ -ErrorAction SilentlyContinue } | Select-Object -First 1
                        if ($functionName) {
                            & $functionName | Out-Null
                            Write-Host " ✓" -ForegroundColor Green
                        }
                        else {
                            Write-Host " ⚠ (No execution function found)" -ForegroundColor Yellow
                        }
                    }
                    catch {
                        Write-Host " ✗ (Error: $_)" -ForegroundColor Red
                    }
                }

                Write-Host "`nType1 audit execution complete.`n" -ForegroundColor Green
            }
            else {
                Write-Host "`nNo Type1 modules selected. Continuing...`n" -ForegroundColor Yellow
            }
        }
        else {
            Write-Host "`nNo Type1 modules found in: $type1Path`n" -ForegroundColor Yellow
        }

        # Show execution mode selector (Intelligent/Manual/AuditOnly)
        $selectedExecutionMode = Show-ExecutionModeMenu
        
        # Handle each execution mode
        switch ($selectedExecutionMode) {
            'Intelligent' {
                # Intelligent Mode: Audit first, then run only required modules
                Write-Information "Executing in Intelligent Mode" -InformationAction Continue
                
                $intelligentResults = Start-IntelligentExecution `
                    -AvailableTasks $AvailableTasks `
                    -MainConfig $MainConfig `
                    -NonInteractive:$false
                
                if ($null -eq $intelligentResults) {
                    # Fallback to manual mode if intelligent mode fails
                    Write-Warning "Intelligent mode failed, falling back to manual task selection"
                    $selectedExecutionMode = 'Manual'
                }
                else {
                    # Intelligent mode completed - skip to report generation
                    $TaskResults = $intelligentResults
                    $ExecutionParams.Mode = 'IntelligentComplete'
                }
            }
            
            'AuditOnly' {
                # Audit-Only Mode: Scan without modifications
                Write-Information "Executing in Audit-Only Mode" -InformationAction Continue
                
                $auditResults = Start-AuditOnlyMode
                
                # Skip Type2 execution, jump straight to reporting
                $ExecutionParams.Mode = 'AuditOnlyComplete'
                $TaskResults = @()
            }
            
            'Manual' {
                # Manual Mode: Traditional task selection menu
                Write-Information "Executing in Manual Mode" -InformationAction Continue
                # Fall through to existing manual task selection logic below
            }
        }
    }
    
    # Manual mode or fallback: Use existing hierarchical menu system
    if ($selectedExecutionMode -eq 'Manual' -and -not $NonInteractive -and -not $TaskNumbers) {
        # Show hierarchical menu with integrated task selection
        $menuResult = Show-MainMenu -CountdownSeconds $MainConfig.execution.countdownSeconds -AvailableTasks $AvailableTasks
        
        # Apply menu selections
        $ExecutionParams.SelectedTasks = @()
        foreach ($taskIndex in $menuResult.SelectedTasks) {
            if ($taskIndex -ge 1 -and $taskIndex -le $AvailableTasks.Count) {
                $ExecutionParams.SelectedTasks += $AvailableTasks[$taskIndex - 1]
            }
        }
        Write-Information "   Menu selections applied:" -InformationAction Continue
        Write-Information "    - Selected tasks: $($ExecutionParams.SelectedTasks.Count)/$($AvailableTasks.Count)" -InformationAction Continue
    }
    elseif ($NonInteractive) {
        Write-Information "`nNon-interactive mode enabled" -InformationAction Continue
        Write-Information "Running all Type1 audit modules (non-interactive)..." -InformationAction Continue

        $type1Path = Join-Path $script:ModulesPath 'type1'
        if (Test-Path $type1Path) {
            $type1Files = Get-ChildItem -Path $type1Path -Filter "*.psm1"
            foreach ($file in $type1Files) {
                Write-Information "  → Running: $($file.BaseName)..." -InformationAction Continue
                try {
                    Import-Module $file.FullName -Force -ErrorAction Stop
                    $moduleBase = $file.BaseName
                    $rootName = $moduleBase
                    if ($moduleBase -match 'DetectionAudit$') { $rootName = $moduleBase -replace 'DetectionAudit$', '' }
                    elseif ($moduleBase -match 'Audit$') { $rootName = $moduleBase -replace 'Audit$', '' }

                    $candidateFunctions = @(
                        "Get-$rootName`Analysis",
                        "Get-$moduleBase`Analysis",
                        "Get-$moduleBase",
                        "Start-$moduleBase",
                        "Get-$rootName",
                        "Start-$rootName"
                    )

                    $functionName = $candidateFunctions | Where-Object { Get-Command -Name $_ -ErrorAction SilentlyContinue } | Select-Object -First 1
                    if ($functionName) {
                        & $functionName | Out-Null
                        Write-Information "    [OK] $($file.BaseName)" -InformationAction Continue
                    }
                    else {
                        Write-Warning "    No execution function found for $($file.BaseName)"
                    }
                }
                catch {
                    Write-Warning "    Failed to run $($file.BaseName): $($_.Exception.Message)"
                }
            }
        }
        else {
            Write-Warning "Type1 modules directory not found: $type1Path"
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
    
    # Initialize StartTime for all execution paths to prevent null reference errors
    $StartTime = Get-Date
    
    # Skip task execution if Intelligent or Audit-Only mode already completed
    if ($ExecutionParams.Mode -eq 'IntelligentComplete' -or $ExecutionParams.Mode -eq 'AuditOnlyComplete') {
        Write-Information "`n=== Skipping manual task execution (completed via $($ExecutionParams.Mode)) ===" -InformationAction Continue
        # Initialize empty TaskResults for report generation
        if (-not $TaskResults) {
            $TaskResults = @()
        }
        # Jump to report generation (below)
    }
    else {
        #region Task Execution
        Write-Information "`nStarting maintenance execution..." -InformationAction Continue
        $executionMode = "LIVE"
        Write-Information "Execution Mode: $executionMode" -InformationAction Continue
        Write-Information "Selected Tasks: $($ExecutionParams.SelectedTasks.Count)/$($AvailableTasks.Count)" -InformationAction Continue

        # v4.0 FIX: Run SystemInventory from Type1 before Type2 modules
        # SystemInventory is a pure read-only audit module that should not be in Type2
        Write-Information "`n=== Phase 1: System Inventory (Type1) ===" -InformationAction Continue
        try {
            Write-Information "Running system inventory audit..." -InformationAction Continue
            $inventoryStartTime = Get-Date
        
            # Import Type1 SystemInventory module
            $type1InventoryPath = Join-Path $script:ModulesPath 'type1\SystemInventory.psm1'
            if (Test-Path $type1InventoryPath) {
                Import-Module $type1InventoryPath -Force -ErrorAction Stop
            
                # Execute Type1 SystemInventory
                $systemInventory = Get-SystemInventory -IncludeDetailed:$false
            
                if ($systemInventory) {
                    Write-Information "  ✓ System inventory completed" -InformationAction Continue
                
                    # Add to result collection for reporting
                    if ($script:ResultCollectionEnabled) {
                        $inventoryDuration = ((Get-Date) - $inventoryStartTime).TotalSeconds
                        $inventoryResult = New-ModuleResult `
                            -ModuleName 'SystemInventory' `
                            -Status 'Success' `
                            -ItemsDetected 1 `
                            -ItemsProcessed 1 `
                            -DurationSeconds $inventoryDuration
                        Add-ModuleResult -Result $inventoryResult
                        Write-Information "  ✓ Inventory result collected for reporting" -InformationAction Continue
                    }
                }
                else {
                    Write-Warning "System inventory returned no data"
                }
            }
            else {
                Write-Warning "Type1 SystemInventory module not found at: $type1InventoryPath"
            }
        }
        catch {
            Write-Warning "Failed to run system inventory: $($_.Exception.Message)"
            Write-LogEntry -Level 'ERROR' -Component 'ORCHESTRATOR' -Message "System inventory failed" -Data @{
                Error = $_.Exception.Message
            }
        }
        # Pre-Type2 planning: process Type1 logs and decide which Type2 tasks to run
        Write-Information "`n=== Phase 1.5: Log Processing for Action Planning ===" -InformationAction Continue
        $preExecutionSkipped = @()

        try {
            if (Get-Command -Name 'Invoke-LogProcessing' -ErrorAction SilentlyContinue) {
                Invoke-LogProcessing | Out-Null
            }
            else {
                Write-Warning "LogProcessor not available - skipping log-based action planning"
            }
        }
        catch {
            Write-Warning "Log processing failed during action planning: $($_.Exception.Message)"
        }

        $moduleResultsPath = Join-Path $env:MAINTENANCE_TEMP_ROOT 'processed\module-results.json'
        $type1AuditResults = @{}
        if (Test-Path $moduleResultsPath) {
            try {
                $moduleResults = Get-Content $moduleResultsPath -Raw | ConvertFrom-Json -AsHashtable
                if ($moduleResults.Type1AuditResults) {
                    $type1AuditResults = $moduleResults.Type1AuditResults
                }
            }
            catch {
                Write-Warning "Failed to read module results for action planning: $($_.Exception.Message)"
            }
        }
        else {
            Write-Warning "Module results not found for action planning: $moduleResultsPath"
        }

        function Get-CountFromAuditData {
            param([object]$Data, [string[]]$PropertyPaths = @())

            if ($null -eq $Data) { return 0 }

            foreach ($path in $PropertyPaths) {
                $value = $Data
                foreach ($segment in ($path -split '\.')) {
                    if ($null -eq $value) { break }
                    if ($value -is [hashtable] -and $value.ContainsKey($segment)) {
                        $value = $value[$segment]
                    }
                    elseif ($value.PSObject.Properties[$segment]) {
                        $value = $value.$segment
                    }
                    else {
                        $value = $null
                    }
                }
                if ($value -is [System.Collections.ICollection]) { return $value.Count }
                if ($value -is [int]) { return $value }
            }

            if ($Data -is [System.Collections.ICollection]) { return $Data.Count }
            return 0
        }

        $skipTasks = @()
        foreach ($task in $ExecutionParams.SelectedTasks) {
            if ($task.Type -ne 'Type2') { continue }

            $auditKey = $null
            $shouldRun = $true
            $reason = $null

            switch ($task.Name) {
                'BloatwareRemoval' { $auditKey = 'bloatware-detection' }
                'EssentialApps' { $auditKey = 'essential-apps' }
                'SystemOptimization' { $auditKey = 'system-optimization' }
                'TelemetryDisable' { $auditKey = 'telemetry' }
                'WindowsUpdates' { $auditKey = 'windows-updates' }
                'AppUpgrade' { $auditKey = 'app-upgrade' }
                'SecurityEnhancement' { $auditKey = 'security-audit' }
            }

            $auditData = if ($auditKey -and $type1AuditResults.ContainsKey($auditKey)) { $type1AuditResults[$auditKey] } else { $null }

            if (-not $auditData) {
                $shouldRun = $false
                $reason = 'No audit data available'
            }
            elseif ($task.Name -eq 'SecurityEnhancement') {
                $score = 100
                if ($auditData.Summary -and $auditData.Summary.PercentageScore) { $score = [int]$auditData.Summary.PercentageScore }
                elseif ($auditData.SecurityScore -and $auditData.MaxScore) { $score = [int]([math]::Round(($auditData.SecurityScore / [Math]::Max($auditData.MaxScore, 1)) * 100)) }
                if ($score -ge 85) {
                    $shouldRun = $false
                    $reason = "Security score $score% (no actions needed)"
                }
            }
            else {
                $count = switch ($task.Name) {
                    'BloatwareRemoval' { Get-CountFromAuditData -Data $auditData }
                    'EssentialApps' { Get-CountFromAuditData -Data $auditData -PropertyPaths @('MissingApps', 'Summary.MissingCount') }
                    'SystemOptimization' { Get-CountFromAuditData -Data $auditData -PropertyPaths @('OptimizationOpportunities') }
                    'TelemetryDisable' { Get-CountFromAuditData -Data $auditData -PropertyPaths @('ActiveTelemetryCount') }
                    'WindowsUpdates' { Get-CountFromAuditData -Data $auditData -PropertyPaths @('PendingUpdatesCount', 'PendingAudit.PendingCount') }
                    'AppUpgrade' { Get-CountFromAuditData -Data $auditData }
                    default { Get-CountFromAuditData -Data $auditData }
                }

                if ($count -le 0) {
                    $shouldRun = $false
                    $reason = 'No actions required based on audit data'
                }
            }

            if (-not $shouldRun) {
                $skipTasks += $task
                Write-Information "  Skipping $($task.Name): $reason" -InformationAction Continue
                Write-LogEntry -Level 'INFO' -Component 'ORCHESTRATOR' -Message "Skipping $($task.Name)" -Data @{ Reason = $reason }

                if ($script:ResultCollectionEnabled) {
                    try {
                        $moduleResultObj = New-ModuleResult -ModuleName $task.Name -Status 'Skipped' -ItemsDetected 0 -ItemsProcessed 0 -DurationSeconds 0
                        Add-ModuleResult -Result $moduleResultObj
                    }
                    catch {
                        Write-Warning "Failed to record skipped result for $($task.Name): $($_.Exception.Message)"
                    }
                }

                $preExecutionSkipped += [PSCustomObject]@{
                    TaskName    = $task.Name
                    Description = $task.Description
                    Type        = $task.Type
                    Category    = $task.Category
                    StartTime   = Get-Date
                    Success     = $true
                    Output      = 'Skipped'
                    Error       = $null
                    Duration    = 0
                    Skipped     = $true
                }
            }
        }

        if ($skipTasks.Count -gt 0) {
            $ExecutionParams.SelectedTasks = $ExecutionParams.SelectedTasks | Where-Object { $_ -notin $skipTasks }
        }

        Write-Information "`n=== Phase 2: System Modifications (Type2) ===" -InformationAction Continue
        # Log execution start
        Write-LogEntry -Level 'INFO' -Component 'ORCHESTRATOR' -Message "Starting maintenance execution" -Data @{
            ExecutionMode      = $executionMode
            SelectedTasksCount = $ExecutionParams.SelectedTasks.Count
            TotalTasksCount    = $AvailableTasks.Count
        }
        if ($ExecutionParams.SelectedTasks.Count -eq 0) {
            Write-Warning "No tasks selected for execution"
            exit 0
        }
        # Show final confirmation for system modification tasks
        $type2Tasks = $ExecutionParams.SelectedTasks | Where-Object { $_.Type -eq 'Type2' }
        if ($type2Tasks.Count -gt 0 -and -not $NonInteractive) {
            $confirmMessage = "About to execute $($type2Tasks.Count) system modification task(s). Continue?"
            $confirmed = Show-ConfirmationDialog -Message $confirmMessage -CountdownSeconds 10
            if (-not $confirmed) {
                Write-Information "Operation cancelled by user" -InformationAction Continue
                exit 0
            }
        }
        # Initialize execution tracking
        $TaskResults = @()
        if ($preExecutionSkipped.Count -gt 0) {
            $TaskResults += $preExecutionSkipped
        }
        # $StartTime already initialized above for all execution paths
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
            $taskStartTime = Get-Date
            $taskResult = @{
                TaskName    = $task.Name
                Description = $task.Description
                Type        = $task.Type
                Category    = $task.Category
                StartTime   = $taskStartTime
                Success     = $false
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
                    Architecture = 'v3.1'
                }
                # Verify function is available (already checked during module loading)
                if (-not (Get-Command -Name $task.Function -ErrorAction SilentlyContinue)) {
                    throw "Function '$($task.Function)' not available - ensure $($task.ModuleName) module is properly loaded"
                }
                # Execute the standardized v3.0 function with consistent parameters
                $result = $null
                try {
                    Write-Information "   Executing: $($task.Function)" -InformationAction Continue
                    $result = & $task.Function -Config $MainConfig
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
                        $resultCount = if ($result -is [array]) { $result.Count } elseif ($result -is [System.Collections.ICollection]) { $result.Count } else { 1 }
                        $hasSuccessKey = if ($result -is [array] -and $result.Count -gt 0) {
                            ($result[0] -is [hashtable] -and $result[0].ContainsKey('Success')) -or
                            ($result[0] -is [PSCustomObject] -and (Get-Member -InputObject $result[0] -Name 'Success' -ErrorAction SilentlyContinue))
                        }
                        elseif ($result -is [System.Collections.IEnumerable] -and -not ($result -is [string]) -and -not ($result -is [hashtable]) -and -not ($result -is [PSCustomObject])) {
                            $firstItem = $result | Select-Object -First 1
                            ($firstItem -is [hashtable] -and $firstItem.ContainsKey('Success')) -or
                            ($firstItem -is [PSCustomObject] -and (Get-Member -InputObject $firstItem -Name 'Success' -ErrorAction SilentlyContinue))
                        }
                        elseif ($result) {
                            ($result -is [hashtable] -and $result.ContainsKey('Success')) -or
                            ($result -is [PSCustomObject] -and (Get-Member -InputObject $result -Name 'Success' -ErrorAction SilentlyContinue))
                        }
                        else { $false }

                        # If it's an enumerable collection, search for a valid result object (pipeline contamination fix)
                        if ($result -is [System.Collections.IEnumerable] -and -not ($result -is [string]) -and -not ($result -is [hashtable]) -and -not ($result -is [PSCustomObject])) {
                            $validResult = $result | Where-Object { ($_ -is [hashtable] -and $_.ContainsKey('Success')) -or ($_ -is [PSCustomObject] -and (Get-Member -InputObject $_ -Name 'Success' -ErrorAction SilentlyContinue)) } | Select-Object -First 1
                            if ($validResult) {
                                Write-LogEntry -Level 'DEBUG' -Component 'ORCHESTRATOR' -Message "Extracted valid result from enumerable" -Data @{ Module = $task.Function; Count = $resultCount; ResultType = $resultType }
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
    }  # End of else block for Manual/NonInteractive task execution
    #endregion
    
    # Stop transcript before report generation
    if ($script:TranscriptStarted) {
        Write-Information " Finalizing transcript logging (pre-report)..." -InformationAction Continue
        try {
            Stop-Transcript -ErrorAction Stop | Out-Null
            $script:TranscriptStarted = $false
            Write-Information "  [OK] Transcript stopped and saved" -InformationAction Continue
        }
        catch {
            Write-Warning "Transcript stop error: $($_.Exception.Message)"
        }
    }

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

        # Expose execution mode to downstream processors
        $env:MAINTENANCE_EXECUTION_MODE = $executionMode

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

                    # Track generated report artifacts for downstream copy/summary
                    # Only copy the main HTML report to script.bat location
                    $script:ReportArtifacts = @()
                    if ($reportResult.HtmlReport -and (Test-Path $reportResult.HtmlReport)) {
                        $script:ReportArtifacts += $reportResult.HtmlReport
                    }

                    # Copy report artifacts to original script.bat location when available
                    $reportCopyTarget = if ($env:ORIGINAL_SCRIPT_DIR -and (Test-Path $env:ORIGINAL_SCRIPT_DIR)) {
                        $env:ORIGINAL_SCRIPT_DIR
                    }
                    else {
                        $script:ProjectPaths.ParentDir
                    }

                    $copiedReportCount = 0
                    foreach ($artifactPath in $script:ReportArtifacts) {
                        try {
                            $destPath = Join-Path $reportCopyTarget (Split-Path -Leaf $artifactPath)
                            Copy-Item -Path $artifactPath -Destination $destPath -Force
                            # VERIFY FILE EXISTS AFTER COPY (critical check)
                            if (Test-Path $destPath) {
                                Write-Information "   Report copied to: $destPath" -InformationAction Continue
                                $finalReports += $destPath
                                $copiedReportCount++
                            }
                            else {
                                Write-Warning "   Report copy verification failed: File not found after copy at $destPath"
                            }
                        }
                        catch {
                            Write-Warning "   Failed to copy report to target directory: $($_.Exception.Message)"
                        }
                    }

                    if ($copiedReportCount -eq 0) {
                        Write-Warning "   No reports were successfully copied to target directory"
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
        -ExecutionStartTime $StartTime
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
    # Copy final reports to target directory (script.bat location when available)
    Write-Information "" -InformationAction Continue
    Write-Information " Copying final reports to target directory..." -InformationAction Continue

    $reportCopyTarget = if ($env:ORIGINAL_SCRIPT_DIR -and (Test-Path $env:ORIGINAL_SCRIPT_DIR)) {
        $env:ORIGINAL_SCRIPT_DIR
    }
    else {
        $script:ProjectPaths.ParentDir
    }

    Write-Information "   Target directory: $reportCopyTarget" -InformationAction Continue
    $finalReports = @()

    if ($script:ReportArtifacts -and $script:ReportArtifacts.Count -gt 0) {
        foreach ($artifactPath in $script:ReportArtifacts) {
            try {
                $destPath = Join-Path $reportCopyTarget (Split-Path -Leaf $artifactPath)
                Copy-Item -Path $artifactPath -Destination $destPath -Force
                Write-Information "   Copied report to: $destPath" -InformationAction Continue
                $finalReports += $destPath
            }
            catch {
                Write-Information "   Failed to copy report artifact`: $_" -InformationAction Continue
            }
        }
    }
    else {
        $reportsDir = Join-Path $script:ProjectPaths.TempRoot "reports"
        $logsDir = Join-Path $script:ProjectPaths.TempRoot "logs"
        $searchPaths = @($reportsDir, $logsDir, $script:ProjectPaths.TempRoot) | Where-Object { $_ -and (Test-Path $_) }
        # Only copy the main HTML report to script.bat location
        $reportPatterns = @(
            @{ Pattern = 'MaintenanceReport_*.html'; Description = 'HTML maintenance report' }
        )

        foreach ($reportInfo in $reportPatterns) {
            $sourceFile = $null
            foreach ($searchPath in $searchPaths) {
                $candidate = Get-ChildItem -Path $searchPath -Filter $reportInfo.Pattern -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
                if ($candidate) {
                    $sourceFile = $candidate.FullName
                    break
                }
            }

            if ($sourceFile) {
                try {
                    $destPath = Join-Path $reportCopyTarget (Split-Path $sourceFile -Leaf)
                    Copy-Item -Path $sourceFile -Destination $destPath -Force
                    Write-Information "   Copied $($reportInfo.Description) to: $destPath" -InformationAction Continue
                    $finalReports += $destPath
                }
                catch {
                    Write-Information "   Failed to copy $($reportInfo.Description)`: $_" -InformationAction Continue
                }
            }
        }
    }
}
catch {
    Write-Error "Fatal error in maintenance orchestration: $($_.Exception.Message)"
    Write-Information "  Stack Trace: $($_.ScriptStackTrace)" -InformationAction Continue
    exit 1
}

# Display final report locations BEFORE countdown (user needs to know where to find them)
if ($finalReports.Count -gt 0) {
    Write-Information "" -InformationAction Continue
    Write-Information " ═══════════════════════════════════════════════════════" -InformationAction Continue
    Write-Information " 📊 Final Reports Available (Safe Location):" -ForegroundColor Green -InformationAction Continue
    Write-Information " ═══════════════════════════════════════════════════════" -InformationAction Continue
    Write-Information "   Location: $reportCopyTarget" -ForegroundColor Cyan -InformationAction Continue
    foreach ($report in $finalReports) {
        $fileName = Split-Path $report -Leaf
        Write-Information "    ✓ $fileName" -ForegroundColor Green -InformationAction Continue
    }
    Write-Information " ═══════════════════════════════════════════════════════" -InformationAction Continue
    Write-Information "" -InformationAction Continue
    Write-Information "   These reports have been copied to the script.bat directory" -ForegroundColor Yellow -InformationAction Continue
    Write-Information "   They will remain even if temporary files are cleaned up" -ForegroundColor Yellow -InformationAction Continue
    Write-Information "" -InformationAction Continue
}
else {
    Write-Warning "No reports were generated or copied. Check logs for errors."
}

#region Stop Transcript
if ($script:TranscriptStarted) {
    Write-Information "" -InformationAction Continue
    Write-Information " Finalizing transcript logging..." -InformationAction Continue
    try {
        Stop-Transcript -ErrorAction Stop | Out-Null
        $script:TranscriptStarted = $false
        Write-Information "  [OK] Transcript stopped and saved" -InformationAction Continue
    }
    catch {
        Write-Verbose "Transcript stop error (expected if not started): $_"
    }
}
#endregion

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
            -WorkingDirectory $ProjectRoot `
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
