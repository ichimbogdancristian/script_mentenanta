#Requires -Version 7.0

using namespace System.Collections.Generic

<#
.SYNOPSIS
    Windows Maintenance Automation - Enhanced Central Orchestrator v2.1

.DESCRIPTION
    Next-generation central coordination script with comprehensive module execution protocol,
    dependency management, completion reporting, and robust error handling.

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

.PARAMETER ModuleName
    Execute a specific module by name

.PARAMETER EnableDetailedLogging
    Enable comprehensive logging including dependency tracking

.PARAMETER ForceAllModules
    Execute all modules regardless of privilege level (may cause failures)

.EXAMPLE
    .\EnhancedMaintenanceOrchestrator.ps1
    # Interactive mode with enhanced protocol

.EXAMPLE
    .\EnhancedMaintenanceOrchestrator.ps1 -NonInteractive -DryRun
    # Unattended dry-run with full dependency validation

.EXAMPLE
    .\EnhancedMaintenanceOrchestrator.ps1 -ModuleName "SystemInventory" -EnableDetailedLogging
    # Execute specific module with detailed logging

.NOTES
    Author: Windows Maintenance Automation Project
    Version: 2.1.0
    Requires: PowerShell 7.0+, Administrator privileges for Type2 modules
#>

param(
    [string]$LogFilePath,
    [string]$ConfigPath,
    [switch]$NonInteractive,
    [switch]$DryRun,
    [string]$TaskNumbers,
    [string]$ModuleName,
    [switch]$EnableDetailedLogging,
    [switch]$ForceAllModules
)

#region Enhanced Self-Discovery Environment Setup

# Universal path detection - works from any location on any PC
function Get-ScriptEnvironment {
    $environment = @{}
    
    # Method 1: PSScriptRoot (PowerShell 3.0+)
    if ($PSScriptRoot) {
        $environment.ScriptRoot = $PSScriptRoot
    }
    # Method 2: MyInvocation path
    elseif ($MyInvocation.MyCommand.Path) {
        $environment.ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
    }
    # Method 3: Current execution context
    elseif ($MyInvocation.MyCommand.Definition) {
        $environment.ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
    }
    # Method 4: Working directory fallback
    else {
        $environment.ScriptRoot = Get-Location
    }
    
    # Resolve to absolute path
    $environment.ScriptRoot = Resolve-Path $environment.ScriptRoot -ErrorAction SilentlyContinue
    if (-not $environment.ScriptRoot) {
        $environment.ScriptRoot = (Get-Location).Path
    }
    
    # Enhanced working directory detection
    $environment.WorkingDirectory = $environment.ScriptRoot
    
    # Check if we're in a maintenance automation repository structure
    $repoIndicators = @('MaintenanceOrchestrator.ps1', 'script.bat', 'modules', 'config')
    $foundIndicators = 0
    
    foreach ($indicator in $repoIndicators) {
        $testPath = Join-Path $environment.ScriptRoot $indicator
        if (Test-Path $testPath) {
            $foundIndicators++
        }
    }
    
    # If we found most indicators, we're in the right place
    $environment.IsValidRepo = ($foundIndicators -ge 2)
    
    # Environment variable overrides
    if ($env:MAINTENANCE_ROOT) {
        $environment.WorkingDirectory = $env:MAINTENANCE_ROOT
        $environment.ScriptRoot = $env:MAINTENANCE_ROOT
    }
    
    # Network path handling
    if ($environment.ScriptRoot -like "\\*") {
        Write-Verbose "Detected network path execution"
        $environment.IsNetworkPath = $true
    }
    else {
        $environment.IsNetworkPath = $false
    }
    
    # Drive letter detection for Windows
    $environment.DriveLetter = if ($environment.ScriptRoot -match "^([A-Z]):") { $matches[1] } else { "C" }
    
    return $environment
}

# Initialize environment
$ScriptEnvironment = Get-ScriptEnvironment
$ScriptRoot = $ScriptEnvironment.ScriptRoot
$WorkingDirectory = $ScriptEnvironment.WorkingDirectory
$StartTime = Get-Date

Write-Verbose "Script Environment Detected:"
Write-Verbose "  ScriptRoot: $ScriptRoot"
Write-Verbose "  WorkingDirectory: $WorkingDirectory"
Write-Verbose "  IsValidRepo: $($ScriptEnvironment.IsValidRepo)"
Write-Verbose "  IsNetworkPath: $($ScriptEnvironment.IsNetworkPath)"
Write-Verbose "  DriveLetter: $($ScriptEnvironment.DriveLetter)"

Write-Host "╔══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║                          Windows Maintenance Automation - Enhanced Orchestrator v2.1                                       ║" -ForegroundColor Cyan
Write-Host "║                                     Advanced Module Execution Protocol                                                      ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan

# Set up temp directories
$TempRoot = Join-Path $WorkingDirectory 'temp_files'
$ReportsDir = Join-Path $TempRoot 'reports'
$LogsDir = Join-Path $TempRoot 'logs'
$InventoryDir = Join-Path $TempRoot 'inventory'

@($TempRoot, $ReportsDir, $LogsDir, $InventoryDir) | ForEach-Object {
    if (-not (Test-Path $_)) {
        New-Item -Path $_ -ItemType Directory -Force | Out-Null
    }
}

# If there's an existing maintenance.log in the working directory (created by the batch launcher),
# move it into the orchestrator-managed logs folder so all runtime logs are centralized.
$LauncherLog = Join-Path $WorkingDirectory 'maintenance.log'
try {
    if (Test-Path $LauncherLog) {
        $TargetLog = Join-Path $LogsDir 'maintenance.log'

        # If file already exists in target, append a timestamp to the existing backup first
        if (Test-Path $TargetLog) {
            $timeSuffix = (Get-Date).ToString('yyyyMMdd-HHmmss')
            $backup = "$TargetLog.$timeSuffix.bak"
            Move-Item -LiteralPath $TargetLog -Destination $backup -Force -ErrorAction SilentlyContinue
        }

        # Attempt to move the launcher log into the logs folder. If Move-Item fails (locked), fall back to Copy+Remove.
        try {
            Move-Item -LiteralPath $LauncherLog -Destination $TargetLog -Force -ErrorAction Stop
        } catch {
            Copy-Item -LiteralPath $LauncherLog -Destination $TargetLog -Force -ErrorAction SilentlyContinue
            Start-Sleep -Milliseconds 200
            try { Remove-Item -LiteralPath $LauncherLog -Force -ErrorAction SilentlyContinue } catch { }
        }
        Write-Verbose "Moved launcher maintenance.log to $TargetLog"
    }
} catch {
    Write-Warning "Failed to relocate launcher maintenance.log: $($_.Exception.Message)"
}

# Set up log file
if (-not $LogFilePath) {
    $LogFilePath = if ($env:SCRIPT_LOG_FILE) { 
        $env:SCRIPT_LOG_FILE 
    }
    else { 
        Join-Path $LogsDir 'maintenance.log' 
    }
}

$Global:MaintenanceLogFile = $LogFilePath

# Universal configuration and modules path discovery
function Find-MaintenanceStructure {
    param([string]$BaseDirectory)
    
    $structure = @{
        ConfigPath  = $null
        ModulesPath = $null
        IsComplete  = $false
    }
    
    # Enhanced search strategies for any PC/path scenario
    $searchStrategies = @(
        # Strategy 1: Direct subdirectories
        @{
            Config  = Join-Path $BaseDirectory 'config'
            Modules = Join-Path $BaseDirectory 'modules'
        },
        # Strategy 2: Parent directory (extracted zip scenario)
        @{
            Config  = Join-Path (Split-Path $BaseDirectory -Parent) 'config'
            Modules = Join-Path (Split-Path $BaseDirectory -Parent) 'modules'
        },
        # Strategy 3: Sibling directories
        @{
            Config  = Join-Path (Split-Path $BaseDirectory -Parent) "config"
            Modules = Join-Path (Split-Path $BaseDirectory -Parent) "modules"
        },
        # Strategy 4: Environment variable paths
        @{
            Config  = if ($env:MAINTENANCE_CONFIG) { $env:MAINTENANCE_CONFIG } else { $null }
            Modules = if ($env:MAINTENANCE_MODULES) { $env:MAINTENANCE_MODULES } else { $null }
        },
        # Strategy 5: Common installation locations
        @{
            Config  = "C:\MaintenanceAutomation\config"
            Modules = "C:\MaintenanceAutomation\modules"
        },
        # Strategy 6: User profile locations  
        @{
            Config  = Join-Path $env:USERPROFILE "MaintenanceAutomation\config"
            Modules = Join-Path $env:USERPROFILE "MaintenanceAutomation\modules"
        },
        # Strategy 7: Recursive search up to 3 levels
        @{
            Config  = $null  # Will be populated by recursive search
            Modules = $null
        }
    )
    
    foreach ($strategy in $searchStrategies) {
        if ($strategy.Config -and $strategy.Modules) {
            if ((Test-Path $strategy.Config) -and (Test-Path $strategy.Modules)) {
                $structure.ConfigPath = $strategy.Config
                $structure.ModulesPath = $strategy.Modules
                $structure.IsComplete = $true
                return $structure
            }
        }
    }
    
    # Strategy 7 implementation: Recursive search
    $searchRoot = $BaseDirectory
    for ($level = 0; $level -lt 3; $level++) {
        Get-ChildItem -Path $searchRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            $testConfig = Join-Path $_.FullName 'config'
            $testModules = Join-Path $_.FullName 'modules'
            
            if ((Test-Path $testConfig) -and (Test-Path $testModules)) {
                $structure.ConfigPath = $testConfig
                $structure.ModulesPath = $testModules  
                $structure.IsComplete = $true
                return $structure
            }
        }
        
        # Move up one level
        $searchRoot = Split-Path $searchRoot -Parent
        if (-not $searchRoot) { break }
    }
    
    return $structure
}

# Discover maintenance structure
if (-not $ConfigPath) {
    Write-Host "🔍 Discovering maintenance automation structure..." -ForegroundColor Yellow
    
    $structure = Find-MaintenanceStructure -BaseDirectory $WorkingDirectory
    
    if ($structure.IsComplete) {
        $ConfigPath = $structure.ConfigPath
        $ModulesPath = $structure.ModulesPath
        Write-Host "✅ Found complete structure:" -ForegroundColor Green
        Write-Host "   Config: $ConfigPath" -ForegroundColor Gray
        Write-Host "   Modules: $ModulesPath" -ForegroundColor Gray
    }
    else {
        Write-Host "⚠️  Complete structure not found. Will create minimal structure..." -ForegroundColor Yellow
        $ConfigPath = Join-Path $WorkingDirectory 'config'
        $ModulesPath = Join-Path $WorkingDirectory 'modules'
    }
}

# Create minimal config structure if not found
if (-not (Test-Path $ConfigPath)) {
    Write-Host "⚠️  Configuration directory not found. Creating minimal structure..." -ForegroundColor Yellow
    
    try {
        # Create config directory in working directory
        $ConfigPath = Join-Path $WorkingDirectory 'config'
        New-Item -Path $ConfigPath -ItemType Directory -Force | Out-Null
        
        # Create essential subdirectories
        $bloatwarePath = Join-Path $ConfigPath 'bloatware-lists'
        $essentialPath = Join-Path $ConfigPath 'essential-apps'
        New-Item -Path $bloatwarePath -ItemType Directory -Force | Out-Null
        New-Item -Path $essentialPath -ItemType Directory -Force | Out-Null
        
        # Create minimal configuration files
        $mainConfig = Join-Path $ConfigPath 'main-config.json'
        $loggingConfig = Join-Path $ConfigPath 'logging-config.json'
        
        @'
{
    "systemSettings": {
        "performanceMode": "balanced",
        "enableTelemetryDisabling": true,
        "enableStartupOptimization": true
    },
    "maintenanceSettings": {
        "createSystemRestore": true,
        "cleanupTemporaryFiles": true,
        "defragmentationEnabled": false
    }
}
'@ | Out-File -FilePath $mainConfig -Encoding utf8 -Force
        
        @'
{
    "logLevel": "INFO",
    "enableFileLogging": true,
    "enableConsoleLogging": true,
    "logRetentionDays": 30,
    "maxLogFileSizeMB": 10
}
'@ | Out-File -FilePath $loggingConfig -Encoding utf8 -Force
        
        # Create empty bloatware lists
        @('gaming-bloatware.json', 'oem-bloatware.json', 'security-bloatware.json', 'windows-bloatware.json') | ForEach-Object {
            $filePath = Join-Path $bloatwarePath $_
            '{ "applications": [] }' | Out-File -FilePath $filePath -Encoding utf8 -Force
        }
        
        # Create empty essential apps lists  
        @('development.json', 'media.json', 'productivity.json', 'web-browsers.json') | ForEach-Object {
            $filePath = Join-Path $essentialPath $_
            '{ "applications": [] }' | Out-File -FilePath $filePath -Encoding utf8 -Force
        }
        
        Write-Host "✅ Minimal configuration structure created at: $ConfigPath" -ForegroundColor Green
    }
    catch {
        throw "Failed to create configuration structure: $($_.Exception.Message)"
    }
}

Write-Host ""
Write-Host "🔧 System Initialization:" -ForegroundColor Yellow
Write-Host "  Working Directory: $WorkingDirectory" -ForegroundColor Gray
Write-Host "  Configuration: $ConfigPath" -ForegroundColor Gray
Write-Host "  Log File: $LogFilePath" -ForegroundColor Gray
Write-Host "  Execution Mode: $(if($DryRun){'DRY-RUN'}else{'LIVE'})" -ForegroundColor $(if ($DryRun) { 'Blue' }else { 'Green' })

#endregion

#region Enhanced Privilege Validation

Write-Host ""
Write-Host "🔐 Enhanced Privilege Validation:" -ForegroundColor Yellow

try {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    
    if ($isAdmin) {
        Write-Host "  ✅ Administrator privileges confirmed" -ForegroundColor Green
        Write-Host "  🔑 Elevation Context: PowerShell $($PSVersionTable.PSVersion)" -ForegroundColor Green
        Write-Host "  🚀 All modules (Type1 + Type2) available for execution" -ForegroundColor Green
    }
    else {
        Write-Host "  ⚠️  Running without Administrator privileges" -ForegroundColor Yellow
        Write-Host "  � Available: Type1 modules (inventory/reporting)" -ForegroundColor Cyan
        Write-Host "  🔒 Restricted: Type2 modules (system modification)" -ForegroundColor Yellow
        if (-not $DryRun -and -not $NonInteractive) {
            Write-Host "  🛠️  For full functionality: Right-click script.bat → 'Run as administrator'" -ForegroundColor Cyan
            Write-Host "  📋 Current mode: Safe inventory and reporting only" -ForegroundColor Gray
        }
    }
}
catch {
    Write-Host "  ❌ Unable to determine privilege level: $_" -ForegroundColor Red
}

#endregion

#region Core Module Loading

Write-Host ""
Write-Host "📦 Loading Enhanced Core Modules:" -ForegroundColor Yellow

# Ensure modules path exists (from earlier discovery or default)
if (-not $ModulesPath) {
    $ModulesPath = Join-Path $WorkingDirectory 'modules'
}

$CoreModulesPath = Join-Path $ModulesPath 'core'

# Create minimal module structure if not found
if (-not (Test-Path $CoreModulesPath)) {
    Write-Host "⚠️  Core modules not found. Creating minimal structure..." -ForegroundColor Yellow
    
    try {
        New-Item -Path $CoreModulesPath -ItemType Directory -Force | Out-Null
        New-Item -Path (Join-Path $ModulesPath 'type1') -ItemType Directory -Force | Out-Null
        New-Item -Path (Join-Path $ModulesPath 'type2') -ItemType Directory -Force | Out-Null
        
        Write-Host "✅ Minimal modules structure created" -ForegroundColor Green
        Write-Host "⚠️  Running in limited mode - some features may be unavailable" -ForegroundColor Yellow
    }
    catch {
        Write-Host "❌ Failed to create modules structure: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "🔧 Continuing in standalone mode..." -ForegroundColor Yellow
    }
}

# Core modules in load order with graceful fallback
$CoreModules = @(
    @{Name = 'ConfigManager'; Essential = $true; Description = 'Configuration management' },
    @{Name = 'MenuSystem'; Essential = $false; Description = 'Interactive menus' },
    @{Name = 'ModuleExecutionProtocol'; Essential = $false; Description = 'Advanced execution engine' }
)

$LoadedModules = @()
$SkippedModules = @()

foreach ($coreModule in $CoreModules) {
    $coreModuleName = $coreModule.Name
    $modulePath = Join-Path $CoreModulesPath "$coreModuleName.psm1"
    
    if (Test-Path $modulePath) {
        try {
            Import-Module $modulePath -Force -ErrorAction Stop
            Write-Host "  ✅ Loaded: $coreModuleName" -ForegroundColor Green
            $LoadedModules += $coreModuleName
        }
        catch {
            Write-Host "  ⚠️  Failed to load $coreModuleName`: $($_.Exception.Message)" -ForegroundColor Yellow
            $SkippedModules += @{Name = $coreModuleName; Reason = "Load error" }
            
            if ($coreModule.Essential) {
                Write-Host "  ❌ Essential module $coreModuleName failed - continuing in limited mode" -ForegroundColor Red
            }
        }
    }
    else {
        Write-Host "  ⚠️  Module not found: $coreModuleName ($($coreModule.Description))" -ForegroundColor Yellow
        $SkippedModules += @{Name = $coreModuleName; Reason = "Not found" }
        
        if ($coreModule.Essential) {
            Write-Host "  💡 Essential module missing - will use built-in alternatives" -ForegroundColor Cyan
        }
    }
}

# Module loading summary
Write-Host ""
if ($LoadedModules.Count -gt 0) {
    Write-Host "✅ Successfully loaded $($LoadedModules.Count) core modules" -ForegroundColor Green
}

if ($SkippedModules.Count -gt 0) {
    Write-Host "⚠️  $($SkippedModules.Count) modules unavailable - running in compatibility mode" -ForegroundColor Yellow
}

# Determine execution mode based on available modules
$ExecutionMode = if ('ModuleExecutionProtocol' -in $LoadedModules) {
    'Enhanced'
}
elseif ('ConfigManager' -in $LoadedModules) {
    'Standard'
}
else {
    'Minimal'
}

Write-Host "🔧 Execution mode: $ExecutionMode" -ForegroundColor Cyan

# Log orchestrator startup and mode (only if ConfigManager is available)
if ('ConfigManager' -in $LoadedModules) {
    Write-Log "Windows Maintenance Automation - Enhanced Orchestrator v2.1 started" -Level INFO -Component ORCHESTRATOR
    Write-Log "Execution mode set to: $ExecutionMode" -Level INFO -Component ORCHESTRATOR
    if ($DryRun) {
        Write-Log "DRY-RUN MODE activated - no changes will be applied" -Level INFO -Component ORCHESTRATOR
    }
}

#endregion

#region Configuration Loading

Write-Host ""
Write-Host "⚙️  Enhanced Configuration Loading:" -ForegroundColor Yellow

try {
    Initialize-ConfigSystem -ConfigRootPath $ConfigPath
    $MainConfig = Get-MainConfiguration
    $null = Get-LoggingConfiguration
    
    Write-Host "  ✅ Main configuration loaded successfully" -ForegroundColor Green
    Write-Host "  ✅ Logging configuration loaded successfully" -ForegroundColor Green
    
    # Move launcher log if configuration allows it
    if ($MainConfig.system.moveBatchLogToOrchestrator -and (Test-Path $LauncherLog)) {
        try {
            $TargetLog = Join-Path $LogsDir 'maintenance.log'

            # If file already exists in target, append a timestamp to the existing backup first
            if (Test-Path $TargetLog) {
                $timeSuffix = (Get-Date).ToString('yyyyMMdd-HHmmss')
                $backup = "$TargetLog.$timeSuffix.bak"
                Move-Item -LiteralPath $TargetLog -Destination $backup -Force -ErrorAction SilentlyContinue
            }

            # Attempt to move the launcher log into the logs folder. If Move-Item fails (locked), fall back to Copy+Remove.
            try {
                Move-Item -LiteralPath $LauncherLog -Destination $TargetLog -Force -ErrorAction Stop
            } catch {
                Copy-Item -LiteralPath $LauncherLog -Destination $TargetLog -Force -ErrorAction SilentlyContinue
                Start-Sleep -Milliseconds 200
                try { Remove-Item -LiteralPath $LauncherLog -Force -ErrorAction SilentlyContinue } catch { }
            }
            
            Write-Host "  📝 Moved batch launcher log to orchestrator logs folder" -ForegroundColor Green
        } catch {
            Write-Warning "Failed to relocate launcher maintenance.log: $($_.Exception.Message)"
        }
    } elseif (Test-Path $LauncherLog) {
        Write-Host "  📋 Keeping batch launcher log separate (moveBatchLogToOrchestrator = false)" -ForegroundColor Gray
    }
    
    # Load app configurations for dependency validation
    $BloatwareLists = Get-BloatwareConfiguration
    $EssentialApps = Get-EssentialAppsConfiguration
    
    $totalBloatware = ($BloatwareLists.Values | Measure-Object -Sum { $_.Count }).Sum
    $totalEssentialApps = ($EssentialApps.Values | Measure-Object -Sum { $_.Count }).Sum
    
    Write-Host "  📋 Bloatware lists: $($BloatwareLists.Keys.Count) categories, $totalBloatware total entries" -ForegroundColor Green
    Write-Host "  📱 Essential apps: $($EssentialApps.Keys.Count) categories, $totalEssentialApps total entries" -ForegroundColor Green
    
}
catch {
    Write-Host "  ❌ Configuration loading failed: $_" -ForegroundColor Red
    exit 1
}

#endregion

#region Enhanced Module Registration with Dependencies

Write-Host ""
Write-Host "🏗️  Enhanced Module Registration with Dependency Analysis:" -ForegroundColor Yellow

# Create module executor
# Convert PSCustomObject to hashtable for compatibility
if ($MainConfig -is [PSCustomObject]) {
    $configHash = @{}
    $MainConfig.PSObject.Properties | ForEach-Object { $configHash[$_.Name] = $_.Value }
    $MainConfig = $configHash
}
$moduleExecutor = New-ModuleExecutor -Configuration $MainConfig -DryRun $DryRun

# Define enhanced module manifests with explicit dependencies
$ModuleManifests = @(
    @{
        Name                      = 'SystemInventory'
        Version                   = '1.0.0'
        Description               = 'Collect comprehensive system information and generate inventory reports'
        Type                      = 'Type1'
        Category                  = 'Inventory'
        ModulePath                = Join-Path $ModulesPath 'type1\SystemInventory.psm1'
        EntryFunction             = 'Get-SystemInventory'
        Dependencies              = @()  # No dependencies - foundational module
        RequiresElevation         = $false
        TimeoutSeconds            = 180
        ConfigurationDependencies = @()
    },
    @{
        Name                      = 'BloatwareDetection'
        Version                   = '1.0.0'
        Description               = 'Scan for bloatware applications and system components'
        Type                      = 'Type1'
        Category                  = 'Detection'
        ModulePath                = Join-Path $ModulesPath 'type1\BloatwareDetection.psm1'
        EntryFunction             = 'Find-InstalledBloatware'
        Dependencies              = @('SystemInventory')  # Depends on system inventory for comprehensive scanning
        RequiresElevation         = $false
        TimeoutSeconds            = 300
        ConfigurationDependencies = @('bloatware-lists')
    },
    @{
        Name                      = 'SecurityAudit'
        Version                   = '1.0.0'
        Description               = 'Perform security audit and apply hardening recommendations'
        Type                      = 'Type1'
        Category                  = 'Security'
        ModulePath                = Join-Path $ModulesPath 'type1\SecurityAudit.psm1'
        EntryFunction             = 'Start-SecurityAudit'
        Dependencies              = @('SystemInventory')  # Uses system info for context
        RequiresElevation         = $false
        TimeoutSeconds            = 240
        ConfigurationDependencies = @()
    },
    @{
        Name                      = 'BloatwareRemoval'
        Version                   = '1.0.0'
        Description               = 'Remove detected bloatware applications using multiple methods'
        Type                      = 'Type2'
        Category                  = 'Cleanup'
        ModulePath                = Join-Path $ModulesPath 'type2\BloatwareRemoval.psm1'
        EntryFunction             = 'Remove-DetectedBloatware'
        Dependencies              = @('BloatwareDetection')  # Must run after detection
        RequiresElevation         = $true
        TimeoutSeconds            = 600
        ConfigurationDependencies = @('bloatware-lists')
    },
    @{
        Name                      = 'EssentialApps'
        Version                   = '1.0.0'
        Description               = 'Install essential applications from curated lists'
        Type                      = 'Type2'
        Category                  = 'Installation'
        ModulePath                = Join-Path $ModulesPath 'type2\EssentialApps.psm1'
        EntryFunction             = 'Install-EssentialApplications'
        Dependencies              = @('SystemInventory')  # Uses system info to avoid conflicts
        RequiresElevation         = $true
        TimeoutSeconds            = 1800  # 30 minutes for installations
        ConfigurationDependencies = @('essential-apps')
    },
    @{
        Name                      = 'WindowsUpdates'
        Version                   = '1.0.0'
        Description               = 'Check for and install Windows updates'
        Type                      = 'Type2'
        Category                  = 'Updates'
        ModulePath                = Join-Path $ModulesPath 'type2\WindowsUpdates.psm1'
        EntryFunction             = 'Install-WindowsUpdates'
        Dependencies              = @()  # Independent operation
        RequiresElevation         = $true
        TimeoutSeconds            = 3600  # 60 minutes for updates
        ConfigurationDependencies = @()
    },
    @{
        Name                      = 'TelemetryDisable'
        Version                   = '1.0.0'
        Description               = 'Disable Windows telemetry and privacy-invasive features'
        Type                      = 'Type2'
        Category                  = 'Privacy'
        ModulePath                = Join-Path $ModulesPath 'type2\TelemetryDisable.psm1'
        EntryFunction             = 'Disable-WindowsTelemetry'
        Dependencies              = @()  # Independent operation
        RequiresElevation         = $true
        TimeoutSeconds            = 300
        ConfigurationDependencies = @()
    },
    @{
        Name                      = 'SystemOptimization'
        Version                   = '1.0.0'
        Description               = 'Apply performance optimizations and cleanup temporary files'
        Type                      = 'Type2'
        Category                  = 'Optimization'
        ModulePath                = Join-Path $ModulesPath 'type2\SystemOptimization.psm1'
        EntryFunction             = 'Optimize-SystemPerformance'
        Dependencies              = @('SystemInventory')  # Uses system info for optimization decisions
        RequiresElevation         = $true
        TimeoutSeconds            = 600
        ConfigurationDependencies = @()
    },
    @{
        Name                      = 'SecurityServicesOptimization'
        Version                   = '1.0.0'
        Description               = 'Configure and optimize critical Windows security services'
        Type                      = 'Type2'
        Category                  = 'Security'
        ModulePath                = Join-Path $ModulesPath 'type2\SystemOptimization.psm1'
        EntryFunction             = 'Optimize-SecurityServices'
        Dependencies              = @('SecurityAudit')  # Run after security audit to address findings
        RequiresElevation         = $true
        TimeoutSeconds            = 180
        ConfigurationDependencies = @()
    },
    @{
        Name                      = 'ReportGeneration'
        Version                   = '1.0.0'
        Description               = 'Generate comprehensive HTML and text reports of all operations'
        Type                      = 'Type1'
        Category                  = 'Reporting'
        ModulePath                = Join-Path $ModulesPath 'type1\ReportGeneration.psm1'
        EntryFunction             = 'New-MaintenanceReport'
        Dependencies              = @('SystemInventory', 'SecurityAudit')  # Aggregates results from other modules
        RequiresElevation         = $false
        TimeoutSeconds            = 120
        ConfigurationDependencies = @()
    }
)

# Register all modules and validate dependencies
$registeredModules = @()
foreach ($manifestData in $ModuleManifests) {
    try {
        # Validate module file exists
        if (-not (Test-Path $manifestData.ModulePath)) {
            Write-Host "  ⚠️  Module file not found: $($manifestData.Name) at $($manifestData.ModulePath)" -ForegroundColor Yellow
            continue
        }
        
        # Validate configuration dependencies
        $configErrors = @()
        foreach ($configDep in $manifestData.ConfigurationDependencies) {
            $configDepPath = Join-Path $ConfigPath $configDep
            if (-not (Test-Path $configDepPath)) {
                $configErrors += "Missing configuration: $configDep"
            }
        }
        
        if ($configErrors.Count -gt 0) {
            Write-Host "  ⚠️  Configuration dependencies missing for $($manifestData.Name): $($configErrors -join ', ')" -ForegroundColor Yellow
        }
        
        # Create and register manifest
        $manifest = New-ModuleManifest -Properties $manifestData
        $moduleExecutor.RegisterModule($manifest)
        $registeredModules += $manifest
        
        $depStr = if ($manifest.Dependencies.Count -gt 0) { " (depends: $($manifest.Dependencies -join ', '))" } else { " (no dependencies)" }
        $elevStr = if ($manifest.RequiresElevation) { " [ADMIN]" } else { " [USER]" }
        
        Write-Host "  ✅ $($manifest.Name)$elevStr$depStr" -ForegroundColor Green
        
        if ($EnableDetailedLogging) {
            Write-Host "    📋 Timeout: $($manifest.TimeoutSeconds)s, Config deps: $($manifest.ConfigurationDependencies -join ', ')" -ForegroundColor Gray
        }
        
    }
    catch {
        Write-Host "  ❌ Failed to register module $($manifestData.Name): $_" -ForegroundColor Red
    }
}

Write-Host "  📊 Total registered modules: $($registeredModules.Count)" -ForegroundColor Cyan

#endregion

#region Module Selection & Execution Planning

Write-Host ""
Write-Host "🎯 Module Selection & Execution Planning:" -ForegroundColor Yellow

$selectedModules = @()

if ($ModuleName) {
    # Single module execution
    Write-Host "  🔍 Debug: Looking for module '$ModuleName' among $($registeredModules.Count) registered modules" -ForegroundColor Gray
    $selectedModule = $registeredModules | Where-Object { $_.Name -eq $ModuleName }
    if ($selectedModule) {
        $selectedModules = @($ModuleName)
        Write-Host "  🎯 Single module selected: $ModuleName" -ForegroundColor Cyan
    }
    else {
        Write-Host "  ❌ Module not found: $ModuleName" -ForegroundColor Red
        Write-Host "  Available modules: $($registeredModules.Name -join ', ')" -ForegroundColor Gray
        exit 1
    }
}
elseif ($TaskNumbers) {
    # Task number selection (backward compatibility)
    $taskNums = $TaskNumbers.Split(',') | ForEach-Object { $_.Trim() }
    $selectedModules = @()
    foreach ($num in $taskNums) {
        if ([int]$num -le $registeredModules.Count) {
            $selectedModules += $registeredModules[[int]$num - 1].Name
        }
    }
    Write-Host "  🔢 Selected by task numbers: $($selectedModules -join ', ')" -ForegroundColor Cyan
}
elseif ($NonInteractive) {
    # Smart module selection in non-interactive mode
    if ($isAdmin -or $ForceAllModules) {
        $selectedModules = $registeredModules.Name
        $modeDesc = if ($isAdmin) { "admin privileges" } else { "forced execution" }
        Write-Host "  🤖 Non-interactive mode: All modules selected ($modeDesc)" -ForegroundColor Cyan
        if ($ForceAllModules -and -not $isAdmin) {
            Write-Host "  ⚠️  Warning: Some modules may fail due to insufficient privileges" -ForegroundColor Yellow
        }
    }
    else {
        # Filter to user-level modules only
        $userModules = $registeredModules | Where-Object { -not $_.RequiresElevation }
        $selectedModules = $userModules.Name
        Write-Host "  🤖 Non-interactive mode: User-level modules selected (safe mode)" -ForegroundColor Cyan
        Write-Host "  📊 Smart filtering: $($selectedModules.Count) user modules, $($registeredModules.Count - $selectedModules.Count) admin modules excluded" -ForegroundColor Gray
        Write-Host "  💡 Use -ForceAllModules to override filtering" -ForegroundColor Gray
    }
}
else {
    # Interactive selection with privilege-aware filtering
    if ($isAdmin -or $ForceAllModules) {
        $modeDesc = if ($isAdmin) { "admin privileges" } else { "forced execution" }
        Write-Host "  🖱️  Interactive mode: All modules available ($modeDesc)" -ForegroundColor Cyan
        if ($ForceAllModules -and -not $isAdmin) {
            Write-Host "  ⚠️  Warning: Some modules may fail due to insufficient privileges" -ForegroundColor Yellow
        }
        $selectedModules = $registeredModules.Name
    }
    else {
        # Smart filtering for non-admin users
        $userModules = $registeredModules | Where-Object { -not $_.RequiresElevation }
        Write-Host "  🖱️  Interactive mode: User-level modules selected (safe mode)" -ForegroundColor Cyan
        Write-Host "  📋 Available: $($userModules.Name -join ', ')" -ForegroundColor Gray
        Write-Host "  🔒 Excluded: $((($registeredModules | Where-Object { $_.RequiresElevation }).Name) -join ', ')" -ForegroundColor Yellow
        Write-Host "  💡 Use -ForceAllModules to override smart filtering" -ForegroundColor Gray
        $selectedModules = $userModules.Name
    }
}

Write-Host "  📋 Modules to execute: $($selectedModules.Count)" -ForegroundColor Green
if ($EnableDetailedLogging) {
    Write-Host "  📝 Module list: $($selectedModules -join ' → ')" -ForegroundColor Gray
}

#endregion

#region Enhanced Module Execution

Write-Host ""
Write-Host "🚀 Enhanced Module Execution Engine:" -ForegroundColor Yellow
Write-Host "══════════════════════════════════════════════════════════════" -ForegroundColor Cyan

# Log execution start (only if ConfigManager is available)
if ('ConfigManager' -in $LoadedModules) {
    Write-Log "Starting enhanced module execution engine with $($selectedModules.Count) selected modules" -Level INFO -Component ORCHESTRATOR
}

try {
    # Execute modules with full dependency management
    if ('ConfigManager' -in $LoadedModules) {
        Write-Log "Executing modules: $($selectedModules -join ', ')" -Level INFO -Component ORCHESTRATOR
    }
    $executionResults = $moduleExecutor.ExecuteAllModules($selectedModules)
    
    Write-Host ""
    Write-Host "📊 Execution Results Summary:" -ForegroundColor Yellow
    Write-Host "────────────────────────────────" -ForegroundColor DarkCyan
    
    foreach ($result in $executionResults) {
        $statusIcon = switch ($result.CompletionStatus) {
            'Success' { '✅' }
            'Failed' { '❌' }
            'Timeout' { '⏱️' }
            'Cancelled' { '🚫' }
            'DependencyFailure' { '🔗' }
            default { '❓' }
        }
        
        $statusColor = switch ($result.CompletionStatus) {
            'Success' { 'Green' }
            'Failed' { 'Red' }
            'Timeout' { 'Yellow' }
            'Cancelled' { 'Gray' }
            'DependencyFailure' { 'Magenta' }
            default { 'White' }
        }
        
        Write-Host "  $statusIcon " -NoNewline
        Write-Host "$($result.ModuleName) " -NoNewline -ForegroundColor White
        Write-Host "($([math]::Round($result.DurationSeconds, 2))s) " -NoNewline -ForegroundColor Gray
        Write-Host "- $($result.CompletionStatus)" -ForegroundColor $statusColor
        
        if ($result.Error -and $EnableDetailedLogging) {
            Write-Host "    💬 Error: $($result.Error)" -ForegroundColor Red
        }
        
        if ($result.ConfigurationErrors.Count -gt 0) {
            Write-Host "    ⚠️  Config Issues: $($result.ConfigurationErrors -join ', ')" -ForegroundColor Yellow
        }
    }
    
}
catch {
    Write-Host "❌ Critical execution engine failure: $_" -ForegroundColor Red
    if ('ConfigManager' -in $LoadedModules) {
        Write-Log "Critical execution engine failure: $_" -Level ERROR -Component ORCHESTRATOR
    }
    exit 1
}

#endregion

#region Enhanced Execution Summary

Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║                                            ENHANCED EXECUTION SUMMARY                                                       ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan

$totalDuration = ((Get-Date) - $StartTime).TotalSeconds
$successfulModules = ($executionResults | Where-Object { $_.Success }).Count
$failedModules = ($executionResults | Where-Object { -not $_.Success }).Count
$dependencyFailures = ($executionResults | Where-Object { $_.CompletionStatus -eq 'DependencyFailure' }).Count
$timeouts = ($executionResults | Where-Object { $_.CompletionStatus -eq 'Timeout' }).Count

Write-Host ""
Write-Host "📊 Overall Statistics:" -ForegroundColor Yellow
Write-Host "  🕒 Total Duration: $([math]::Round($totalDuration, 2)) seconds" -ForegroundColor White
Write-Host "  📦 Modules Executed: $($executionResults.Count)" -ForegroundColor White
Write-Host "  ✅ Successful: $successfulModules" -ForegroundColor Green
Write-Host "  ❌ Failed: $failedModules" -ForegroundColor $(if ($failedModules -gt 0) { 'Red' } else { 'Green' })
Write-Host "  🔗 Dependency Failures: $dependencyFailures" -ForegroundColor $(if ($dependencyFailures -gt 0) { 'Magenta' } else { 'Green' })
Write-Host "  ⏱️ Timeouts: $timeouts" -ForegroundColor $(if ($timeouts -gt 0) { 'Yellow' } else { 'Green' })

if ($executionResults.Count -gt 0) {
    $successRate = [math]::Round(($successfulModules / $executionResults.Count) * 100, 1)
    Write-Host "  📈 Success Rate: $successRate%" -ForegroundColor $(if ($successRate -ge 80) { 'Green' } elseif ($successRate -ge 60) { 'Yellow' } else { 'Red' })
}

# Save enhanced execution summary
$enhancedSummary = @{
    StartTime          = $StartTime
    EndTime            = Get-Date
    TotalDuration      = $totalDuration
    ExecutionMode      = if ($DryRun) { 'DRY-RUN' } else { 'LIVE' }
    ModulesExecuted    = $executionResults.Count
    SuccessfulModules  = $successfulModules
    FailedModules      = $failedModules
    DependencyFailures = $dependencyFailures
    Timeouts           = $timeouts
    SuccessRate        = if ($executionResults.Count -gt 0) { ($successfulModules / $executionResults.Count) * 100 } else { 0 }
    Configuration      = $MainConfig
    ExecutionResults   = $executionResults
    DependencyGraph    = $moduleExecutor.DependencyResolver.DependencyGraph
}

$summaryPath = Join-Path $ReportsDir "enhanced-execution-summary-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
try {
    $enhancedSummary | ConvertTo-Json -Depth 10 | Set-Content -Path $summaryPath -Encoding UTF8
    Write-Host ""
    Write-Host "📄 Enhanced execution summary saved: $summaryPath" -ForegroundColor Cyan
}
catch {
    Write-Host "⚠️  Could not save execution summary: $_" -ForegroundColor Yellow
}

Write-Host ""
if ($failedModules -eq 0 -and $dependencyFailures -eq 0 -and $timeouts -eq 0) {
    Write-Host "🎉 All modules completed successfully with enhanced protocol!" -ForegroundColor Green
}
elseif ($successfulModules -gt 0) {
    Write-Host "⚠️  Execution completed with some issues - see detailed logs above" -ForegroundColor Yellow
}
else {
    Write-Host "❌ Execution completed with significant failures" -ForegroundColor Red
}

#endregion

# Exit with appropriate code
exit $(if ($failedModules -gt $successfulModules) { 1 } else { 0 })