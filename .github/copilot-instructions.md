# Copilot Instructions for script_mentenanta

## Project Overview
A modular Windows maintenance automation framework that operates in dual-mode:
1. **Modular Mode**: Uses `MaintenanceOrchestrator.ps1` with JSON configuration and PowerShell modules for local execution
2. **Legacy Mode**: Downloads latest repository version and runs traditional `script.ps1` for backwards compatibility

Entry point is `script.bat` which detects local modular files (`MaintenanceOrchestrator.ps1` + `config/maintenance-config.json`) and switches between modes automatically.

## Architecture Components

### Core Files
- `script.bat`: Dual-mode orchestrator with dependency management and admin privilege checking
- `MaintenanceOrchestrator.ps1`: Modular maintenance coordinator with task filtering and reporting
- `config/maintenance-config.json`: JSON-driven task configuration with priority-based execution
- `modules/`: PowerShell modules for configuration, logging, and system tasks
- `script.ps1`: Legacy monolithic maintenance script (backwards compatibility)

### Module Architecture
- **ConfigManager.psm1**: JSON config loading, task filtering, system requirements validation
- **LoggingManager.psm1**: Centralized logging with levels, retention, and task-specific tracking
- **SystemTasks.psm1**: Individual maintenance task implementations with consistent error handling

## Essential Patterns

### Task Configuration Pattern
```json
"taskName": {
  "enabled": true,
  "description": "Task description",
  "priority": 1,
  "taskSpecificSettings": "value"
}
```
Tasks execute in priority order (lower numbers first). Use `Get-EnabledTasks` to filter active tasks.

### Command Line Arguments
```bash
# Batch entry point
script.bat -test -report -tasks "diskCleanup,defenderScan"

# Direct PowerShell execution  
.\MaintenanceOrchestrator.ps1 -TestMode -TaskFilter @('systemRestore') -GenerateReport
```

### Error Handling Convention
All functions use try/catch with `Write-LogMessage -Level "Error"` and return success/failure booleans. Tasks failures don't stop session execution.

## Developer Workflows

### Run Maintenance
- **Full run**: Right-click `script.bat` → "Run as administrator" 
- **Test mode**: `script.bat -test` (simulates without changes)
- **Specific tasks**: `script.bat -tasks "diskCleanup,systemRestore"`

### Add New Maintenance Task
1. Add function to `modules/SystemTasks.psm1` following `Invoke-TaskName` pattern
2. Add configuration section to `config/maintenance-config.json` with priority
3. Update switch statement in `MaintenanceOrchestrator.ps1` line ~130
4. Add unit test in `tests/unit-tests.ps1`

### Testing & Debugging
- Run `tests/Test-MaintenanceScript.ps1` for comprehensive testing
- Use `-TestMode` for safe execution without system changes
- Check `logs/` directory for detailed execution logs with task-specific tracking
- Generated HTML reports in `reports/` directory

## Critical Dependencies
- **Automatic Installation**: script.bat handles WinGet, PowerShell 7, VCLibs, UI.Xaml
- **Admin Privileges**: Required for all operations, automatically prompted
- **Windows 10/11**: Version detection with compatibility checks
- **Scheduled Tasks**: Auto-creation for restart scenarios with 1-minute startup delay

## Integration Points
- **GitHub Downloads**: Repository self-updating when modular files not present  
- **WinGet Package Management**: Software installation and updates
- **Windows Restart Handling**: Scheduled task continuation after required reboots
- **HTML Report Generation**: Cross-system compatible reporting with error aggregation

---
See `docs/UserGuide.md` for task-specific configurations and `instructions.md` for PowerShell coding standards.
