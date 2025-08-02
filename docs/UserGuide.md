# User Guide - Windows Maintenance Script v2.0

## Overview
The Windows Maintenance Script v2.0 is a modular, configuration-driven system maintenance tool that automates various Windows optimization and cleaning tasks.

### Dual-Mode Operation
The script automatically detects and operates in one of two modes:

1. **Modular Mode**: When `MaintenanceOrchestrator.ps1` and `config/maintenance-config.json` are present locally, uses the enhanced modular architecture with JSON configuration
2. **Legacy Mode**: When local modular files are not found, automatically downloads the latest repository version and runs the traditional `script.ps1`

This design ensures backward compatibility while providing enhanced functionality when the full modular system is available.

## Quick Start

### Basic Usage
1. **Right-click** `script.bat` and select **"Run as administrator"**
2. The script will automatically check dependencies and run all enabled maintenance tasks
3. Review the results and generated reports

### Alternative: PowerShell Direct Execution
```powershell
# Run with default configuration
.\MaintenanceOrchestrator.ps1

# Run in test mode (no actual changes)
.\MaintenanceOrchestrator.ps1 -TestMode

# Run specific tasks only
.\MaintenanceOrchestrator.ps1 -TaskFilter @('systemRestore', 'diskCleanup')

# Generate detailed report
.\MaintenanceOrchestrator.ps1 -GenerateReport
```

### Automatic Dependency Management
The script automatically handles all required dependencies:
- **WinGet**: Downloads and installs if not present
- **PowerShell 7**: Preferred execution environment, falls back to Windows PowerShell
- **Microsoft VCLibs**: Runtime libraries for modern Windows applications
- **Microsoft UI.Xaml**: User interface framework components

### Restart Handling
If the system requires a restart (e.g., for pending Windows updates), the script:
1. Creates a scheduled task to continue execution after restart
2. Schedules restart with 1-minute delay for proper initialization
3. Automatically removes the scheduled task after completion

## Configuration

### Main Configuration File
Edit `config\maintenance-config.json` to customize:

- **Enable/disable tasks**: Set `enabled` to `true` or `false`
- **Task priorities**: Lower numbers run first
- **System requirements**: Minimum Windows version, admin requirements
- **Logging levels**: Debug, Info, Warning, Error
- **Reporting options**: HTML reports, system info inclusion

### Example Task Configuration
```json
{
  "maintenanceTasks": {
    "diskCleanup": {
      "enabled": true,
      "description": "Clean temporary files and caches",
      "priority": 3,
      "includeTempFiles": true,
      "includeSystemCache": true,
      "includeRecycleBin": false
    }
  }
}
```

## Available Maintenance Tasks

### 1. System Restore Point
- **Function**: Creates a restore point before maintenance
- **Recommendation**: Always enable this as a safety measure
- **Config Key**: `systemRestore`

### 2. Windows Defender Scan
- **Function**: Runs antivirus scan
- **Options**: Quick or Full scan
- **Config Key**: `defenderScan`

### 3. Disk Cleanup
- **Function**: Removes temporary files and system cache
- **Options**: Include temp files, system cache, recycle bin
- **Config Key**: `diskCleanup`

### 4. System File Check
- **Function**: Runs SFC and DISM to repair system files
- **Options**: Enable/disable SFC or DISM separately
- **Config Key**: `systemFileCheck`

### 5. Windows Updates
- **Function**: Downloads and installs Windows updates
- **Options**: Include optional updates, automatic reboot
- **Config Key**: `windowsUpdates`

### 6. Defragmentation
- **Function**: Defragments hard drives (skips SSDs)
- **Options**: Drive types to include
- **Config Key**: `defragmentation`

### 7. Registry Cleanup
- **Function**: Cleans invalid registry entries
- **Options**: Automatic registry backup
- **Config Key**: `registryCleanup`

### 8. Service Optimization
- **Function**: Optimizes Windows services
- **Options**: Create service backup
- **Config Key**: `serviceOptimization`

### 9. Privacy Settings
- **Function**: Configures Windows privacy settings
- **Options**: Telemetry level (Security, Basic, Enhanced, Full)
- **Config Key**: `privacySettings`

### 10. Startup Optimization
- **Function**: Manages startup programs
- **Options**: Disable unnecessary startup items
- **Config Key**: `startupOptimization`

### 11. Debloating (Optional)
- **Function**: Removes bloatware applications
- **Options**: Safe mode, automatic restore point
- **Config Key**: `debloating`
- **Default**: Disabled (requires careful configuration)

## Command Line Options

### Batch Script (`script.bat`)
```batch
script.bat                       # Run all enabled tasks
script.bat -test                 # Test mode (no changes)
script.bat -report               # Generate detailed report
script.bat -tasks "diskCleanup,defenderScan"  # Run specific tasks
```

### PowerShell Script (`MaintenanceOrchestrator.ps1`)
```powershell
# Configuration file path
-ConfigPath "path\to\config.json"

# Test mode (simulate actions)
-TestMode

# Filter specific tasks
-TaskFilter @('systemRestore', 'diskCleanup')

# Generate HTML report
-GenerateReport
```

## Output and Logging

### Log Files
- **Location**: `logs\` directory
- **Format**: `maintenance_YYYYMMDD_HHMMSS.log`
- **Retention**: Configurable (default: 30 days)
- **Levels**: Debug, Info, Warning, Error

### Reports
- **Location**: `reports\` directory
- **Format**: HTML with detailed task results
- **Contents**: 
  - Execution summary
  - Individual task status
  - Error messages
  - System information

### Console Output
- Real-time progress updates
- Color-coded status messages
- Summary of completed tasks

## Safety Features

### Automatic Backup
- System restore point creation
- Registry backup (if enabled)
- Service configuration backup

### Test Mode
- Run `-TestMode` to simulate all actions
- No actual changes made to system
- Full logging and reporting

### Error Handling
- Individual task failures don't stop entire session
- Detailed error logging
- Safe fallback options

## Scheduling

### Windows Task Scheduler
The script can create a scheduled task for automatic maintenance:

```json
{
  "scheduling": {
    "taskName": "SystemMaintenance",
    "schedule": "weekly",
    "time": "02:00",
    "dayOfWeek": "Sunday"
  }
}
```

### Manual Scheduling
1. Open Task Scheduler
2. Create Basic Task
3. Set trigger (daily/weekly/monthly)
4. Set action to run `script.bat`
5. Configure to run with highest privileges

## Troubleshooting

### Common Issues

**1. Script won't run**
- Ensure running as administrator
- Check Windows version compatibility (Windows 10/11)
- Verify PowerShell execution policy

**2. Modular vs Legacy mode issues**
- If experiencing issues with modular mode, temporarily rename `MaintenanceOrchestrator.ps1` to force legacy mode
- Ensure `config/maintenance-config.json` exists and is valid JSON for modular mode
- Check internet connectivity if script needs to download repository in legacy mode

**3. Task failures**
- Check log files for detailed error messages
- Ensure sufficient disk space
- Verify internet connection for updates

**4. Dependency issues**
- Script automatically installs WinGet and PowerShell 7
- Manual installation may be required in corporate environments
- Check dependency installation logs in the console output

### Getting Help
1. Check log files in `logs\` directory
2. Review generated reports
3. Run in test mode to identify issues
4. Check Windows Event Viewer for system-level errors

## Customization

### Adding New Tasks
1. Create function in `modules\SystemTasks.psm1`
2. Add task configuration to `config\maintenance-config.json`
3. Update orchestrator switch statement
4. Add unit tests

### Modifying Existing Tasks
1. Edit task settings in configuration file
2. Test changes with `-TestMode` first
3. Monitor logs for any issues

### Custom Configurations
Create multiple configuration files for different scenarios:
- `maintenance-config-minimal.json` - Basic tasks only
- `maintenance-config-complete.json` - All tasks enabled
- `maintenance-config-server.json` - Server-specific tasks

## Best Practices

### Regular Maintenance
- Run weekly for optimal system performance
- Always create restore points before major changes
- Monitor disk space before running cleanup tasks

### Configuration Management
- Keep backup copies of working configurations
- Test configuration changes in test mode first
- Document any custom modifications

### Monitoring
- Review log files regularly
- Check generated reports for trends
- Monitor system performance after maintenance

## Advanced Usage

### Integration with Other Tools
- Use with monitoring systems via exit codes
- Parse JSON logs for automated analysis
- Integrate with backup solutions

### Corporate Deployment
- Deploy configuration files via Group Policy
- Use centralized logging solutions
- Implement approval workflows for updates
