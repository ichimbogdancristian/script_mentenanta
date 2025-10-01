# Windows Maintenance Automation v2.0

A completely redesigned, modular Windows maintenance automation system with interactive execution modes, comprehensive reporting, and self-discovery capabilities.

## 🚀 Features

### ✨ New in v2.0 - Complete Modular Redesign
- **Modular Architecture**: Separated Type 1 (inventory/reporting) and Type 2 (system modification) modules
- **Interactive Menu System**: 20-second countdown menus with automatic fallback
- **Dry-Run Mode**: Test changes without modifying your system
- **Self-Discovery Environment**: Works from any folder on any PC
- **Enhanced Configuration**: JSON-based configuration files for easy maintenance
- **Comprehensive Reporting**: HTML and text reports with detailed audit trails
- **Advanced Dependency Management**: Automatic package manager installation and validation
- **Task Scheduling**: Windows scheduled task creation and management
- **Security Hardening**: Comprehensive telemetry disabling and privacy optimization

📊 **[View Architecture Diagrams](ARCHITECTURE-DIAGRAM.md)** - Visual system flow and module interactions

### 🛠️ Core Capabilities
- **Bloatware Removal**: Remove unwanted OEM, Windows, gaming, and security software
- **Essential Apps Installation**: Install curated lists of essential applications  
- **Windows Updates**: Automated Windows update management
- **System Optimization**: Performance tuning and cleanup
- **Security Audit**: Security posture analysis and hardening
- **Telemetry Disable**: Privacy optimization and telemetry disabling

## 📁 Project Structure

```
script_mentenanta/
├── script.bat                     # Enhanced launcher with self-discovery
├── MaintenanceOrchestrator.ps1    # Central coordination script
├── modules/
│   ├── type1/                     # Type 1: Inventory & Reporting (Read-Only)
│   │   ├── SystemInventory.psm1   # System information collection
│   │   ├── BloatwareDetection.psm1 # Bloatware identification  
│   │   ├── SecurityAudit.psm1     # Security posture analysis
│   │   └── ReportGeneration.psm1  # HTML/Log report generation
│   ├── type2/                     # Type 2: System Modification (Changes System)
│   │   ├── BloatwareRemoval.psm1  # Application removal
│   │   ├── EssentialApps.psm1     # Application installation
│   │   ├── WindowsUpdates.psm1    # Update management
│   │   ├── TelemetryDisable.psm1  # Privacy hardening
│   │   └── SystemOptimization.psm1 # Performance tuning
│   └── core/                      # Core Infrastructure Modules
│       ├── ConfigManager.psm1     # Configuration & JSON management
│       ├── MenuSystem.psm1        # Interactive menu system
│       ├── DependencyManager.psm1 # Package manager dependencies
│       └── TaskScheduler.psm1     # Windows scheduled tasks
├── config/
│   ├── bloatware-lists/           # Categorized bloatware definitions
│   ├── essential-apps/            # Essential app definitions
│   ├── main-config.json          # Main configuration
│   └── logging-config.json       # Logging configuration
├── temp_files/                    # Runtime files (auto-created)
│   ├── inventory/                 # System inventory cache
│   ├── reports/                   # Generated reports
│   └── logs/                      # Detailed logs
└── docs/
    ├── README.md                  # This file
    ├── ARCHITECTURE.md           # Architecture documentation
    ├── ARCHITECTURE-DIAGRAM.md   # Visual architecture diagrams
    └── MODULE-GUIDE.md           # Module development guide
```

## 🎮 Usage

### Quick Start
1. **Download and run** from any location:
   ```batch
   # Copy script.bat to any folder and run as Administrator
   script.bat
   ```

2. **Interactive Mode** (default):
   - Shows 20-second countdown menus
   - Choose between normal execution and dry-run mode
   - Select all tasks or specific task numbers
   - Automatic fallback to safe defaults

3. **Non-Interactive Mode**:
   ```batch
   script.bat -NonInteractive
   ```

4. **Dry-Run Mode**:
   ```batch
   script.bat -DryRun
   ```

5. **Specific Tasks**:
   ```batch
   script.bat -TaskNumbers 1,3,5
   ```

### PowerShell Direct Execution
```powershell
# Run the orchestrator directly
.\MaintenanceOrchestrator.ps1

# With parameters
.\MaintenanceOrchestrator.ps1 -NonInteractive -DryRun -TaskNumbers "1,2,3"
```

## 📋 Available Modules

### Type 1 Modules (Inventory & Reporting) - Read-Only Operations
| Module | Function | Description | Status |
|--------|----------|-------------|---------|
| **SystemInventory** | `Get-SystemInventory` | Comprehensive system information collection | ✅ Active |
| **BloatwareDetection** | `Find-BloatwareApplications` | Scan for unwanted OEM and system bloatware | ✅ Active |
| **SecurityAudit** | `Start-SecurityAudit` | Security posture analysis with scoring | ✅ Active |
| **ReportGeneration** | `New-MaintenanceReport` | HTML and text report generation | ✅ Active |

### Type 2 Modules (System Modification) - Changes System State
| Module | Function | Description | Status |
|--------|----------|-------------|---------|
| **BloatwareRemoval** | `Remove-BloatwareApplications` | Remove detected bloatware using multiple methods | ✅ Active |
| **EssentialApps** | `Install-EssentialApplications` | Install curated essential software lists | ✅ Active |
| **WindowsUpdates** | `Install-WindowsUpdates` | Windows Update installation and management | ✅ Active |
| **TelemetryDisable** | `Disable-TelemetryFeatures` | Windows telemetry disabling and privacy hardening | ✅ Active |
| **SystemOptimization** | `Optimize-SystemPerformance` | Performance tuning, cleanup, and optimization | ✅ Active |

### Core Infrastructure Modules
| Module | Function | Description | Status |
|--------|----------|-------------|---------|
| **ConfigManager** | `Get-MainConfiguration` | JSON configuration loading and management | ✅ Active |
| **MenuSystem** | `Show-MainMenu` | Interactive countdown menus with fallbacks | ✅ Active |
| **DependencyManager** | `Install-AllDependencies` | Package manager dependency installation | ✅ Active |
| **TaskScheduler** | `New-MaintenanceTask` | Windows scheduled task automation | ✅ Active |

## 📋 Available Tasks

| # | Task Name | Type | Description |
|---|-----------|------|-------------|
| 1 | SystemInventory | Type1 | Collect system information and generate reports |
| 2 | BloatwareDetection | Type1 | Scan for bloatware applications |
| 3 | BloatwareRemoval | Type2 | Remove detected bloatware |
| 4 | EssentialApps | Type2 | Install essential applications |
| 5 | WindowsUpdates | Type2 | Check and install Windows updates |
| 6 | TelemetryDisable | Type2 | Disable telemetry and privacy features |
| 7 | SecurityAudit | Type1 | Perform security analysis |
| 8 | SystemOptimization | Type2 | Apply performance optimizations |
| 9 | ReportGeneration | Type1 | Generate comprehensive reports |

## ⚙️ Configuration

### Main Configuration (`config/main-config.json`)
```json
{
  "execution": {
    "defaultMode": "unattended",
    "countdownSeconds": 20,
    "enableDryRun": true
  },
  "modules": {
    "skipBloatwareRemoval": false,
    "skipEssentialApps": false,
    "skipWindowsUpdates": false
  }
}
```

### Bloatware Lists (`config/bloatware-lists/`)
- `oem-bloatware.json` - OEM manufacturer bloatware
- `windows-bloatware.json` - Microsoft Windows bloatware
- `gaming-bloatware.json` - Gaming and social apps
- `security-bloatware.json` - Third-party security software

### Essential Apps (`config/essential-apps/`)
- `web-browsers.json` - Web browsers
- `productivity.json` - Office and productivity tools
- `media.json` - Media players and editors
- `development.json` - Development tools

## 📊 Reporting

### Generated Reports
- **maintenance.log** - Comprehensive text log
- **maintenance-report.html** - Interactive HTML report
- **execution-summary.json** - Detailed execution metadata

### Report Locations
- Main directory: `maintenance.log`
- Reports directory: `temp_files/reports/`
- Detailed logs: `temp_files/logs/`

## 🔧 System Requirements

- **Operating System**: Windows 10 or Windows 11
- **PowerShell**: Version 5.1+ (PowerShell 7+ recommended)
- **Privileges**: Administrator rights required
- **Network**: Internet connection for updates and downloads
- **Disk Space**: ~100MB for temporary files and reports

## 🛡️ Security Features

- **Windows Defender Exclusions**: Automatic setup for smooth operation
- **Digital Signatures**: Module integrity verification (planned)
- **Controlled Folder Access**: Automatic allowlist configuration
- **Safe Mode**: Dry-run capabilities for testing changes
- **Audit Trail**: Comprehensive logging of all operations

## 🔄 Self-Discovery & Portability

The system automatically:
- **Detects execution environment** (local vs network)
- **Discovers project structure** or downloads missing components
- **Installs dependencies** as needed
- **Configures Windows Defender exclusions**
- **Sets up scheduled tasks** for automated maintenance

## 🆕 Migration from v1.0

### For Users
1. **Backup your current setup** (optional)
2. **Copy `script-new.bat`** to your preferred location
3. **Run as Administrator** - it will auto-download the new structure
4. **Configure as needed** using the new JSON config files

### For Developers
1. **Review ARCHITECTURE.md** for design principles
2. **Check MODULE-GUIDE.md** for module development
3. **Existing functions** are being migrated to new modules
4. **Configuration system** now uses JSON instead of PowerShell variables

## 📝 Changelog

### v2.0.0 (Latest)
- ✅ Complete modular architecture redesign
- ✅ Interactive menu system with countdown timers
- ✅ Self-discovery environment capabilities
- ✅ JSON-based configuration system
- ✅ Enhanced logging and HTML reporting
- ✅ Dry-run mode for safe testing
- ✅ Type 1/Type 2 module separation
- ✅ Improved dependency management

### v1.0.0 (Legacy)
- Basic maintenance automation
- Single monolithic PowerShell script
- Limited configuration options
- Basic bloatware removal and app installation

## 🤝 Contributing

1. **Fork the repository**
2. **Create a feature branch** (`git checkout -b feature/new-module`)
3. **Follow the module architecture** (see MODULE-GUIDE.md)
4. **Test thoroughly** using dry-run mode
5. **Submit a pull request**

## 📞 Support

- **Issues**: Use GitHub Issues for bug reports and feature requests
- **Documentation**: Check `docs/` folder for detailed guides
- **Logs**: Include `maintenance.log` when reporting issues
- **Community**: Share configurations and custom modules

## ⚖️ License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🙏 Acknowledgments

- Inspired by Chris Titus Tech's Windows Utility and similar projects
- Community contributions for bloatware identification
- Microsoft documentation for Windows automation best practices
- PowerShell community for module development patterns

---

**Made with ❤️ for the Windows automation community**