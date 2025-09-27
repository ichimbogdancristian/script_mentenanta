# Windows Maintenance Automation Configuration
# This file contains customizable settings for the maintenance system
# Modify these values to customize the behavior of maintenance tasks

@{
    # ============================================================================
    # GENERAL SETTINGS
    # ============================================================================

    # Working directory for temporary files and logs
    WorkingDirectory = $null  # null = use script directory

    # Log file path (null = auto-generate in working directory)
    LogFile = $null

    # Maximum log file size in MB before rotation
    MaxLogSizeMB = 10

    # ============================================================================
    # TASK EXECUTION CONTROL
    # ============================================================================

    # Skip entire task categories
    SkipSystemTasks = $false
    SkipApplicationTasks = $false
    SkipUpdateTasks = $false
    SkipMonitoringTasks = $false

    # ============================================================================
    # SYSTEM TASKS CONFIGURATION
    # ============================================================================

    # System Restore
    SkipSystemRestoreProtection = $false
    SystemRestoreDescription = "Pre-maintenance checkpoint"

    # System Health
    SkipSystemHealthOptimization = $false
    SkipSystemInventory = $false

    # ============================================================================
    # APPLICATION TASKS CONFIGURATION
    # ============================================================================

    # Bloatware Removal
    SkipRemoveBloatware = $false
    BloatwareApps = @(
        "Microsoft.BingWeather"
        "Microsoft.GetHelp"
        "Microsoft.Getstarted"
        "Microsoft.Messaging"
        "Microsoft.Microsoft3DViewer"
        "Microsoft.MicrosoftOfficeHub"
        "Microsoft.MicrosoftSolitaireCollection"
        "Microsoft.MixedReality.Portal"
        "Microsoft.Office.OneNote"
        "Microsoft.People"
        "Microsoft.SkypeApp"
        "Microsoft.Wallet"
        "Microsoft.WindowsAlarms"
        "Microsoft.WindowsCamera"
        "Microsoft.WindowsFeedbackHub"
        "Microsoft.WindowsMaps"
        "Microsoft.WindowsSoundRecorder"
        "Microsoft.Xbox.TCUI"
        "Microsoft.XboxApp"
        "Microsoft.XboxGameOverlay"
        "Microsoft.XboxGamingOverlay"
        "Microsoft.XboxSpeechToTextOverlay"
        "Microsoft.YourPhone"
        "Microsoft.ZuneMusic"
        "Microsoft.ZuneVideo"
    )

    # Essential Apps Installation
    SkipInstallEssentialApps = $false
    EssentialApps = @(
        @{ Id = "7zip.7zip"; Name = "7-Zip" }
        @{ Id = "Mozilla.Firefox"; Name = "Firefox" }
        @{ Id = "VideoLAN.VLC"; Name = "VLC Media Player" }
        @{ Id = "Notepad++.Notepad++"; Name = "Notepad++" }
    )

    # Application Updates
    SkipUpdateInstalledApplications = $false
    SkipClearApplicationCache = $false
    SkipRepairBrokenApplications = $false

    # ============================================================================
    # UPDATE TASKS CONFIGURATION
    # ============================================================================

    # Windows Updates
    SkipInstallWindowsUpdates = $false
    SkipInstallOptionalUpdates = $false
    SkipUpdateDeviceDrivers = $false
    SkipTestSystemHealth = $false
    SkipOptimizeWindowsUpdate = $false

    # Optional Windows Features to install
    OptionalFeatures = @(
        "NetFx3"
        "Microsoft-Windows-Subsystem-Linux"
        "VirtualMachinePlatform"
        "Containers-DisposableClientVM"
    )

    # ============================================================================
    # MONITORING TASKS CONFIGURATION
    # ============================================================================

    # System Monitoring
    SkipEnableSystemMonitoring = $false
    SkipSetEventLogging = $false
    SkipEnableTelemetryReporting = $false
    SkipWatchSystemResources = $false
    SkipNewSystemReport = $false
    SkipCompressEventLogs = $false

    # Telemetry Level (0=Off, 1=Basic, 2=Enhanced, 3=Full)
    TelemetryLevel = 2

    # Resource Monitoring Thresholds (%)
    CpuThreshold = 80
    MemoryThreshold = 90
    DiskThreshold = 95

    # Event Log Settings
    MaxEventLogSizeMB = 50
    EventLogRetentionDays = 30

    # ============================================================================
    # SCHEDULED TASKS CONFIGURATION
    # ============================================================================

    # Scheduled Task Management
    SkipSchedulingSetup = $false
    SkipScheduledTaskStatus = $false

    # Scheduled Task Settings
    ScheduledTaskName = "WindowsMaintenance"
    ScheduledTaskSchedule = "Weekly"  # Daily, Weekly, Monthly
    ScheduledTaskStartTime = "02:00"  # 2 AM
    ScheduledTaskRunAsSystem = $false
    ScheduledTaskInterval = 1  # Every X days/weeks/months

    # ============================================================================
    # DEPENDENCY MANAGEMENT
    # ============================================================================

    # Auto-install missing dependencies
    AutoInstallDependencies = $true

    # Dependency installation settings
    InstallPowerShell7 = $true
    InstallWinget = $true
    InstallChocolatey = $true
    InstallGit = $true

    # ============================================================================
    # ADVANCED SETTINGS
    # ============================================================================

    # Execution timeouts (seconds)
    TaskTimeoutSeconds = 300
    DependencyInstallTimeoutSeconds = 600

    # Retry settings
    MaxRetryAttempts = 3
    RetryDelaySeconds = 5

    # Cleanup settings
    MaxTempFilesAgeDays = 7
    CleanupOldLogs = $true

    # Debug settings
    EnableDebugLogging = $false
    VerboseOutput = $false

    # ============================================================================
    # CUSTOM TASKS
    # ============================================================================

    # Add custom tasks here (will be loaded from CustomTasks.psm1 if it exists)
    CustomTasks = @()

    # ============================================================================
    # EXCLUSION LISTS
    # ============================================================================

    # Tasks to exclude from execution
    ExcludeTasks = @()

    # Applications to exclude from updates
    ExcludeAppsFromUpdate = @()

    # Drives to exclude from cleanup
    ExcludeDrivesFromCleanup = @("C:")
}