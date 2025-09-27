# MaintenanceLauncher.ps1 - Unified PowerShell launcher for Windows Maintenance Automation
# Combines environment setup, dependency checks, and orchestrates the modular maintenance system

#Requires -Version 7.0

param(
    [string]$LogFilePath,
    [switch]$SkipAdminCheck,
    [switch]$SkipDependencyCheck
)

# ================================================================
# Environment Setup and Path Detection
# ================================================================

# Script path and environment detection
$ScriptFullPath = $MyInvocation.MyCommand.Path
$ScriptDir = Split-Path -Parent $ScriptFullPath

# Working directory - use script directory
$WorkingDirectory = $ScriptDir

# Log file setup
if ($LogFilePath) {
    $LogFile = $LogFilePath
}
else {
    $LogFile = Join-Path $WorkingDirectory 'maintenance.log'
}

# Ensure log file directory exists
$logDir = Split-Path $LogFile -Parent
if (-not (Test-Path $logDir)) {
    New-Item -Path $logDir -ItemType Directory -Force | Out-Null
}

# Temp folder setup
$TempFolder = Join-Path $WorkingDirectory 'temp'
if (-not (Test-Path $TempFolder)) {
    New-Item -Path $TempFolder -ItemType Directory -Force | Out-Null
}

# ================================================================
# Import Required Modules
# ================================================================

$modulesPath = Join-Path $ScriptDir 'modules'

# Import bootstrap module first (handles PS version and initial setup)
$bootstrapModule = Join-Path $modulesPath 'bootstrap\Bootstrap.psm1'
if (Test-Path $bootstrapModule) {
    Import-Module $bootstrapModule -Force
    Initialize-BootstrapEnvironment
}
else {
    Write-Host "Bootstrap module not found at $bootstrapModule" -ForegroundColor Red
    exit 1
}

# Import logging module
$loggingModule = Join-Path $modulesPath 'logging\Logging.psm1'
if (Test-Path $loggingModule) {
    Import-Module $loggingModule -Force
    # Initialize logging
    Initialize-Logging -ConfigPath (Join-Path $WorkingDirectory 'config\logging.json')
    $global:LoggingConfig.LogFile = $LogFile
}
else {
    # Fallback logging if module not found
    function Write-Log {
        param($Message, $Level = 'INFO', $Component = 'Launcher')
        $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        $line = "[$ts] [$Level] [$Component] $Message"
        Write-Host $line
        Add-Content -Path $LogFile -Value $line -ErrorAction SilentlyContinue
    }
    Write-Log "Logging module not found, using fallback logging" 'WARN'
}

# Import environment module
$environmentModule = Join-Path $modulesPath 'environment\Environment.psm1'
if (Test-Path $environmentModule) {
    Import-Module $environmentModule -Force
}
else {
    Write-Log "Environment module not found at $environmentModule" 'ERROR'
    exit 1
}

# Import dependencies module
$dependenciesModule = Join-Path $modulesPath 'dependencies\Dependencies.psm1'
if (Test-Path $dependenciesModule) {
    Import-Module $dependenciesModule -Force
}
else {
    Write-Log "Dependencies module not found at $dependenciesModule" 'ERROR'
    exit 1
}

# Import inventory module
$inventoryModule = Join-Path $modulesPath 'inventory\Inventory.psm1'
if (Test-Path $inventoryModule) {
    Import-Module $inventoryModule -Force
}
else {
    Write-Log "Inventory module not found at $inventoryModule" 'ERROR'
    exit 1
}

# Import coordinator module (imports task modules internally)
$coordinatorModule = Join-Path $modulesPath 'core\Coordinator.psm1'
if (Test-Path $coordinatorModule) {
    Import-Module $coordinatorModule -Force
}
else {
    Write-Log "Coordinator module not found at $coordinatorModule" 'ERROR'
    exit 1
}

# ================================================================
# Global Configuration Setup
# ================================================================

# Load configuration from config.psd1 if it exists
$configFile = Join-Path $ScriptDir 'config\config.psd1'
if (Test-Path $configFile) {
    try {
        $global:Config = Import-PowerShellDataFile -Path $configFile
        Write-Log "Configuration loaded from $configFile" 'INFO' 'Launcher'
    }
    catch {
        Write-Log "Failed to load configuration from ${configFile}: $_" 'WARN' 'Launcher'
        Write-Log "Using default configuration" 'INFO' 'Launcher'
    }
}

# Set default configuration if not loaded from file
if (-not $global:Config) {
    $global:Config = @{
        # Skip flags for system tasks
        SkipSystemRestore       = $false
        SkipSystemHealth        = $false

        # Skip flags for application tasks
        SkipBloatwareRemoval    = $false
        SkipEssentialApps       = $false
        SkipAppUpdates          = $false
        SkipCacheCleanup        = $false
        SkipAppRepair           = $false

        # Skip flags for update tasks
        SkipWindowsUpdates      = $false
        SkipOptionalUpdates     = $false
        SkipDriverUpdates       = $false
        SkipHealthCheck         = $false
        SkipUpdateOptimization  = $false

        # Skip flags for monitoring tasks
        SkipMonitoringSetup     = $false
        SkipEventLogging        = $false
        SkipTelemetry           = $false
        SkipResourceMonitoring  = $false
        SkipReportGeneration    = $false

        # Legacy skip flags (maintained for compatibility)
        SkipTelemetryDisable    = $false
        SkipEventLogAnalysis    = $false
        SkipPendingRestartCheck = $false
        SkipSystemHealthRepair  = $false
        SkipPackageUpdates      = $false

        # Logging and customization
        EnableVerboseLogging    = $false
        CustomEssentialApps     = @()
        CustomBloatwareList     = @()
        ExcludeTasks            = @()

        # Monitoring thresholds
        CPUThreshold            = 90
        MemoryThreshold         = 90
        DiskThreshold           = 90
        TelemetryLevel          = 2
        ClearOldEventLogs       = $false
        InstallLanguagePacks    = $false
    }
}

# ================================================================
# Environment and Dependency Validation
# ================================================================

Write-Log "Starting Windows Maintenance Automation Launcher" 'INFO' 'Launcher'
Write-Log "User: $env:USERNAME, Computer: $env:COMPUTERNAME" 'INFO' 'Launcher'

# Perform comprehensive environment check
if (-not $SkipAdminCheck) {
    Write-Log "Performing environment validation..." 'INFO' 'Launcher'
    $envReport = Get-EnvironmentReport

    if (-not $envReport.IsAdministrator) {
        Write-Log "Administrator privileges required. Attempting elevation..." 'WARN' 'Launcher'

        # Attempt to relaunch with elevation
        try {
            $arguments = "& '$ScriptFullPath'"
            if ($LogFilePath) { $arguments += " -LogFilePath '$LogFilePath'" }
            if ($SkipDependencyCheck) { $arguments += " -SkipDependencyCheck" }

            Start-Process pwsh.exe -ArgumentList "-ExecutionPolicy Bypass -Command $arguments" -Verb RunAs -Wait
            exit
        }
        catch {
            Write-Log "Failed to elevate privileges: $_" 'ERROR' 'Launcher'
            Write-Log "Please run this script as Administrator" 'ERROR' 'Launcher'
            Read-Host "Press Enter to exit"
            exit 1
        }
    }
    else {
        Write-Log "Administrator privileges confirmed" 'INFO' 'Launcher'
    }

    # Check system compatibility
    if (-not $envReport.IsCompatible) {
        Write-Log "System compatibility issues detected:" 'WARN' 'Launcher'
        foreach ($issue in $envReport.CompatibilityIssues) {
            Write-Log "  - $issue" 'WARN' 'Launcher'
        }
        Write-Log "Continuing despite compatibility warnings..." 'INFO' 'Launcher'
    }
}

# Check and install dependencies
if (-not $SkipDependencyCheck) {
    Write-Log "Checking system dependencies..." 'INFO' 'Launcher'

    $depResult = Test-SystemDependencies
    if (-not $depResult.AllPresent) {
        Write-Log "Some dependencies are missing. Attempting installation..." 'WARN' 'Launcher'

        foreach ($missingDep in $depResult.Missing) {
            Write-Log "Installing missing dependency: $($missingDep.Name)" 'INFO' 'Launcher'
            $installResult = Install-Dependency -DependencyName $missingDep.Name

            if (-not $installResult) {
                Write-Log "Failed to install $($missingDep.Name). Some features may not work." 'WARN' 'Launcher'
            }
        }
    }
    else {
        Write-Log "All system dependencies are available" 'SUCCESS' 'Launcher'
    }
}

# ================================================================
# Windows Version Detection
# ================================================================

try {
    $osInfo = Get-ComputerInfo -ErrorAction SilentlyContinue
    if ($osInfo) {
        Write-Log "Detected Windows version: $($osInfo.WindowsProductName) $($osInfo.WindowsVersion)" 'INFO' 'Launcher'
    }
}
catch {
    Write-Log "Could not detect Windows version details" 'WARN' 'Launcher'
}

# Import tasks module
$tasksModule = Join-Path $modulesPath 'tasks\Tasks.psm1'
if (Test-Path $tasksModule) {
    Import-Module $tasksModule -Force
    Write-Log "Tasks module loaded" 'INFO' 'Launcher'
}

# Import coordinator module
$coordinatorModule = Join-Path $modulesPath 'core\Coordinator.psm1'
if (Test-Path $coordinatorModule) {
    Import-Module $coordinatorModule -Force
    Write-Log "Coordinator module loaded" 'INFO' 'Launcher'
}

# ================================================================
# Main Execution
# ================================================================

Write-Log "Starting maintenance task execution..." 'INFO' 'Launcher'

try {
    # Execute all maintenance tasks
    $results = Use-AllScriptTasks

    # Generate summary
    $successfulTasks = ($results.Values | Where-Object { $_.Success }).Count
    $totalTasks = $results.Count

    Write-Log "Maintenance completed: $successfulTasks/$totalTasks tasks successful" 'SUCCESS' 'Launcher'

    # Save results to file
    $resultsPath = Join-Path $TempFolder 'execution_results.json'
    $results | ConvertTo-Json -Depth 3 | Out-File -FilePath $resultsPath -Encoding UTF8
    Write-Log "Execution results saved to $resultsPath" 'INFO' 'Launcher'

}
catch {
    Write-Log "Critical error during maintenance execution: $_" 'ERROR' 'Launcher'
    Write-Log "Check the log file for detailed error information" 'ERROR' 'Launcher'
}

Write-Log "Maintenance launcher completed" 'INFO' 'Launcher'

# Pause for user to see results (optional)
if ($Host.Name -eq 'ConsoleHost') {
    Read-Host "Press Enter to exit"
}