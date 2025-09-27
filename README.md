y# Windows Maintenance Automation Toolkit

A comprehensive, modular Windows maintenance automation system built with PowerShell 7+.

## Overview

This toolkit provides automated maintenance operations for Windows systems, organized into specialized modules for better maintainability and extensibility. The system handles system optimization, application management, updates, monitoring, and more.

## Architecture

The system is organized into the following modular components:

### Core Modules (`modules/core/`)
- **Coordinator.psm1**: Central task orchestration and dependency management

### Bootstrap Modules (`modules/bootstrap/`)
- **Bootstrap.psm1**: Environment setup and PowerShell version management

### Environment Modules (`modules/environment/`)
- **Environment.psm1**: System compatibility checks and administrator privilege management

### Dependency Modules (`modules/dependencies/`)
- **Dependencies.psm1**: Tool checking and installation (winget, choco, git, PS7)

### Utility Modules
- **Logging.psm1** (`modules/logging/`): Configuration-based logging system
- **Inventory.psm1** (`modules/inventory/`): System and application data collection

### Specialized Task Modules (`modules/tasks/`)
- **SystemTasks.psm1** (`modules/tasks/system/`): System maintenance (restore points, health optimization, inventory)
- **BloatwareTasks.psm1** (`modules/tasks/applications/`): Bloatware removal and cleanup
- **EssentialApps.psm1** (`modules/tasks/applications/`): Essential application installation
- **UpdateTasks.psm1** (`modules/tasks/applications/`): Application updates and package management
- **RepairTasks.psm1** (`modules/tasks/applications/`): Application repair and troubleshooting
- **CacheTasks.psm1** (`modules/tasks/applications/`): Cache cleaning and temporary file management
- **UpdateTasks.psm1** (`modules/tasks/updates/`): System and application updates (Windows updates, optional features, driver updates)
- **MonitoringTasks.psm1** (`modules/tasks/monitoring/`): System monitoring and telemetry (Sysmon, event logging, reporting)
- **ScheduledTasks.psm1** (`modules/tasks/`): Windows scheduled tasks management and automation

### Main Launcher
- **MaintenanceLauncher.ps1**: Unified entry point that coordinates all modules

### Configuration
- **config.psd1**: User-customizable configuration file with skip flags, thresholds, and scheduled task settings
- **BloatwareList.psd1**: Centralized bloatware definitions organized by categories (Microsoft, OEM, Gaming, etc.)
- **EssentialAppsList.psd1**: Centralized essential applications definitions organized by categories (Browsers, Tools, etc.)

## Project Structure

```
script_mentenanta/
├── MaintenanceLauncher.ps1          # Main launcher script
├── config/                          # Configuration files
│   ├── config.psd1                  # Configuration file
│   ├── BloatwareList.psd1           # Bloatware definitions
│   ├── EssentialAppsList.psd1       # Essential applications definitions
│   ├── logging.json                 # Logging configuration
│   └── sysmonconfig.xml             # Sysmon configuration
├── system_report.txt                # Consolidated system report
├── maintenance.log                  # Main log file
├── modules/                         # Modular components
│   ├── bootstrap/
│   │   └── Bootstrap.psm1          # PowerShell version management
│   ├── core/
│   │   └── Coordinator.psm1        # Task orchestration
│   ├── dependencies/
│   │   └── Dependencies.psm1       # Tool installation
│   ├── environment/
│   │   └── Environment.psm1        # System checks
│   ├── inventory/
│   │   └── Inventory.psm1          # System data collection
│   ├── logging/
│   │   └── Logging.psm1            # Logging system
│   └── tasks/                      # Specialized task modules
│       ├── applications/
│       │   ├── BloatwareTasks.psm1
│       │   ├── InstallationTasks.psm1
│       │   ├── UpdateTasks.psm1
│       │   ├── RepairTasks.psm1
│       │   └── CacheTasks.psm1
│       ├── monitoring/
│       │   └── MonitoringTasks.psm1
│       ├── system/
│       │   └── SystemTasks.psm1
│       ├── updates/
│       │   └── UpdateTasks.psm1
│       └── ScheduledTasks.psm1     # Scheduled task management
├── temp/                           # Temporary files
├── archive/                        # Legacy files
└── .github/
    └── copilot-instructions.md     # AI assistant guidance
```

## Features

### Scheduled Task Automation
The system includes comprehensive scheduled task management:
- **Automated Scheduling**: Create recurring maintenance tasks
- **Task Monitoring**: Check status and execution history of scheduled tasks
- **Flexible Configuration**: Support for daily, weekly, and monthly schedules
- **System Integration**: Native Windows Task Scheduler integration

### Single Report File
- **Consolidated Reporting**: All system reports are saved to a single `system_report.txt` file
- **No File Proliferation**: Eliminates multiple timestamped report files
- **Persistent Data**: Report is overwritten with each run, maintaining current status

## Prerequisites

- Windows 10/11
- PowerShell 7+ (automatically installed if missing)
- Administrator privileges (recommended for full functionality)

## Installation

1. Clone or download the repository
2. Ensure PowerShell execution policy allows script execution:
   ```powershell
   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
   ```

## Usage

### Basic Usage

Run the maintenance launcher:
```powershell
.\MaintenanceLauncher.ps1
```

### Command Line Options

- `-SkipAdminCheck`: Skip administrator privilege verification
- `-SkipDependencyCheck`: Skip dependency verification
- `-LogFilePath <path>`: Specify custom log file path

### Configuration

The system uses a global configuration object (`$global:Config`) with the following key settings:

```powershell
$global:Config = @{
    # Skip flags for different task categories
    SkipSystemTasks = $false
    SkipApplicationTasks = $false
    SkipUpdateTasks = $false
    SkipMonitoringTasks = $false

    # Specific task skip flags
    SkipSystemRestoreProtection = $false
    SkipSystemHealthOptimization = $false
    SkipSystemInventory = $false
    # ... additional flags

    # Thresholds and limits
    MaxLogSizeMB = 10
    MaxTempFilesAgeDays = 7
    MaxEventLogSizeMB = 50

    # Feature toggles
    EnableTelemetry = $true
    EnableMonitoring = $true
    AutoInstallDependencies = $true
}
```

## Task Categories

### System Tasks (3 tasks)
- **System Restore Protection**: Enable System Restore and create maintenance checkpoints
- **System Health Optimization**: Run DISM and SFC health checks and repairs
- **System Inventory**: Collect comprehensive system information

### Application Tasks (6 tasks)
- **Remove Bloatware**: Remove unwanted Windows apps via AppX, DISM, and registry
- **Install Essential Apps**: Install curated essential applications via Winget
- **Update Installed Applications**: Update all applications via Winget, Chocolatey, and Store
- **Clear Application Cache**: Clean browser and application caches
- **Repair Broken Applications**: Attempt to repair corrupted applications

### Update Tasks (5 tasks)
- **Install Windows Updates**: Install pending Windows updates and security patches
- **Install Optional Updates**: Install optional Windows features and updates
- **Update Device Drivers**: Update device drivers using Windows Update
- **Test System Health**: Run system health checks and repairs
- **Optimize Windows Update**: Optimize Windows Update settings and cleanup

### Monitoring Tasks (5 tasks)
- **Enable System Monitoring**: Enable system monitoring services and Sysmon
- **Set Event Logging**: Configure Windows Event Log settings and retention
- **Enable Telemetry Reporting**: Configure Windows telemetry and diagnostics
- **Watch System Resources**: Monitor system resources and generate alerts
- **New System Report**: Generate comprehensive system monitoring reports

### Scheduled Tasks (2 tasks)
- **Enable Maintenance Scheduling**: Create automated recurring maintenance tasks
- **Check Scheduled Task Status**: Monitor status and execution history of scheduled tasks

## Logging

The system uses a structured logging system with the following levels:
- `DEBUG`: Detailed debugging information
- `INFO`: General information messages
- `WARN`: Warning messages for non-critical issues
- `ERROR`: Error messages for failed operations
- `SUCCESS`: Success messages for completed operations
- `ACTION`: Action messages for major operations

Logs are written to `maintenance.log` by default and can be configured via `logging.json`.

## Error Handling

The system includes comprehensive error handling:
- Tasks continue execution even if individual operations fail
- Detailed error logging with context information
- Graceful degradation when admin privileges are unavailable
- Automatic retry mechanisms for transient failures

## Extending the System

### Adding New Tasks

1. Create a new function in the appropriate task module:
```powershell
function New-CustomTask {
    [CmdletBinding()]
    param()
    # Task implementation
}
```

2. Add the task to the Coordinator module's `$global:ScriptTasks` array:
```powershell
$global:ScriptTasks += @{
    Name = 'CustomTask'
    Function = { New-CustomTask }
    Description = 'Description of the custom task'
}
```

3. Export the function in the module manifest.

### Creating New Modules

1. Create a new PowerShell module file (`.psm1`)
2. Implement functions following the established patterns
3. Add proper error handling and logging
4. Update the main launcher to import the new module
5. Add configuration flags if needed

## Troubleshooting

### Common Issues

1. **"Access denied" errors**: Run with administrator privileges
2. **PowerShell version errors**: The system will attempt to install PowerShell 7 automatically
3. **Dependency installation failures**: Check internet connection and administrator privileges
4. **Task execution failures**: Check the log file for detailed error information

### Log Analysis

Check the `maintenance.log` file for detailed execution information:
- Task execution status and duration
- Error messages with context
- Performance metrics
- System state information

### Recovery

If a task fails:
1. Check the log file for error details
2. Verify system prerequisites (admin rights, dependencies)
3. Run individual task functions manually for debugging
4. Report issues with full log excerpts

## Security Considerations

- The system requires administrator privileges for many operations
- All external downloads use official sources (Microsoft, Winget, Chocolatey)
- Registry modifications are logged and reversible
- System restore points are created before major changes
- Telemetry settings can be controlled via configuration

## Performance

- Tasks are designed to run efficiently with minimal system impact
- Parallel processing is used where appropriate
- Resource monitoring prevents excessive system load
- Caching mechanisms reduce redundant operations

## Support

For issues and questions:
1. Check the log files for error details
2. Verify system requirements are met
3. Test individual components in isolation
4. Review configuration settings

## License

This project is provided as-is for educational and maintenance purposes.