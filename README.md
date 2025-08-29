
# 🚀 Enhanced Windows Maintenance Script (2025)

**Professional-grade Windows 10/11 maintenance automation with unified reporting and categorized bloatware/essential apps management.**

## ⭐ **What's New in 2025 Enhanced Version**

### 🎯 **Enhanced Bloatware Removal**
- **Categorized Approach**: OEM, Gaming, Microsoft, Security, Social Media, Streaming Apps
- **Safety Protection**: Critical apps are automatically protected from removal
- **Multi-Method Removal**: AppX, Winget, Registry, Provisioned packages, and Services
- **Smart Detection**: Multiple detection methods with enhanced pattern matching
- **Rollback Support**: Track removed apps for potential restoration

### 📦 **Enhanced Essential Apps Installation**
- **Priority-Based Installation**: System Core → Browsers → Productivity → Optional
- **Category Controls**: Productivity, Media, Development, Communication, Utilities, Gaming
- **Fallback Methods**: Winget → Chocolatey → Alternative sources
- **Smart Detection**: Avoid duplicate installations across package managers

### 📊 **Unified Reporting System**
- **Single Report File**: Replaces separate log files with comprehensive maintenance_report.txt
- **Categorized Results**: Detailed breakdown by category and operation
- **Performance Metrics**: Execution times, success rates, system impact
- **Professional Format**: Ready for IT documentation and compliance

### ⚙️ **Enhanced Configuration**
- **Granular Controls**: Configure each category independently
- **User Profiles**: Developer, Gamer, Conservative, Aggressive presets
- **Backward Compatibility**: Existing configurations continue to work

## 🔧 **Core Features**

### 📋 **Maintenance Tasks**
- **System Inventory**: Comprehensive AppX, Winget, Chocolatey, and Registry scanning
- **Temp File Cleanup**: Enhanced cleanup with progress tracking
- **Windows Updates**: Automated update check and installation
- **System Restore Protection**: Automatic restore point creation
- **Telemetry Disable**: Privacy-focused Windows telemetry disable
- **Registry Optimization**: Safe registry cleanup and optimization

### 🛡️ **Safety Features**
- **Administrator Check**: Ensures proper permissions
- **Critical App Protection**: Prevents removal of essential system apps
- **PowerShell 7.5.2 Compatibility**: Modern PowerShell features with PS5.1 fallback
- **Error Handling**: Comprehensive error tracking and recovery
- **Backup Support**: System restore points before major changes

## 📁 **Project Structure**

```
script_mentenanta/
├── script.ps1                 # Main enhanced maintenance script
├── script.bat                 # Windows batch launcher
├── config_example.json        # Enhanced configuration example
├── README.md                  # This documentation
└── temp_lists/                # Generated temp files and reports
    ├── maintenance_report.txt  # Unified maintenance report
    ├── bloatware_*.json       # Bloatware analysis results
    └── essential_*.json       # Essential apps analysis results
```

## 🚀 **Quick Start**

### **Method 1: Run with Default Settings**
```cmd
# Right-click "Run as Administrator"
script.bat
```

### **Method 2: PowerShell Direct**
```powershell
# Open PowerShell as Administrator
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
.\script.ps1
```

### **Method 3: Custom Configuration**
```powershell
# 1. Copy config_example.json to config.json
# 2. Edit config.json with your preferences
# 3. Run the script
.\script.ps1
```

## ⚙️ **Enhanced Configuration Guide**

### **Configuration Profiles**

#### 🛡️ **Conservative Profile** (Recommended for business/shared computers)
```json
{
  "KeepSocialApps": true,
  "KeepMediaStreamingApps": true,
  "KeepAlternativeBrowsers": true,
  "KeepGamingApps": true,
  "AggressiveBloatwareRemoval": false,
  "InstallDevelopmentTools": false,
  "InstallGamingApps": false
}
```

#### ⚡ **Aggressive Profile** (Maximum cleanup for personal computers)
```json
{
  "KeepSocialApps": false,
  "KeepMediaStreamingApps": false,
  "KeepAlternativeBrowsers": false,
  "KeepGamingApps": false,
  "AggressiveBloatwareRemoval": true,
  "InstallProductivityApps": true,
  "InstallMediaApps": true,
  "InstallUtilities": true
}
```

#### 💻 **Developer Profile**
```json
{
  "InstallDevelopmentTools": true,
  "InstallUtilities": true,
  "KeepAlternativeBrowsers": true,
  "AggressiveBloatwareRemoval": true
}
```

#### 🎮 **Gamer Profile**
```json
{
  "KeepGamingApps": true,
  "InstallGamingApps": true,
  "InstallMediaApps": true,
  "KeepAlternativeBrowsers": true
}
```

### **Configuration Options Reference**

#### **Bloatware Control Options**
| Option | Default | Description |
|--------|---------|-------------|
| `KeepSocialApps` | `false` | Keep Facebook, Twitter, Instagram, TikTok, Discord |
| `KeepMediaStreamingApps` | `false` | Keep Netflix, Spotify, Amazon Prime Video, Hulu |
| `KeepAlternativeBrowsers` | `false` | Keep Opera, Vivaldi, Brave, Tor Browser |
| `KeepGamingApps` | `false` | Keep Xbox apps, game launchers, King games |
| `AggressiveBloatwareRemoval` | `true` | Remove Microsoft built-in apps (Paint, Calculator) |

#### **Essential Apps Control Options**
| Option | Default | Description |
|--------|---------|-------------|
| `InstallProductivityApps` | `true` | LibreOffice, PDF readers, WinRAR, Total Commander |
| `InstallMediaApps` | `true` | VLC, GIMP, Audacity, Paint.NET |
| `InstallDevelopmentTools` | `false` | VS Code, Git, Python, Node.js, Windows Terminal |
| `InstallCommunicationApps` | `true` | Teams, Zoom, Thunderbird |
| `InstallUtilities` | `true` | PowerToys, Everything Search, CCleaner |
| `InstallGamingApps` | `false` | Steam, Epic Games Launcher |

## 📊 **Enhanced Reporting**

The script generates a comprehensive `maintenance_report.txt` with:

### **Report Sections**
1. **System Information**: OS version, hardware specs, PowerShell version
2. **Performance Metrics**: Execution times, memory usage, disk space saved
3. **Inventory Summary**: Installed apps by source (AppX, Winget, Chocolatey, Registry)
4. **Bloatware Removal Results**: By category with detailed statistics
5. **Essential Apps Installation**: Priority-based installation results
6. **Task Execution Summary**: Success/failure rates for all maintenance tasks
7. **Temp Lists Generated**: References to detailed analysis files

### **Sample Report Output**
```
=== WINDOWS MAINTENANCE REPORT ===
Generated: 2025-01-02 10:30:45
Duration: 15.3 minutes
System: Windows 11 Pro (22H2)

PERFORMANCE METRICS:
- Disk Space Freed: 2.1 GB
- Apps Removed: 15 bloatware apps
- Apps Installed: 8 essential apps
- Registry Entries Cleaned: 47

BLOATWARE REMOVAL BY CATEGORY:
- OEM: Found 8, Removed 8, Failed 0
- Gaming: Found 5, Removed 5, Failed 0
- Microsoft: Found 12, Removed 10, Failed 2
- Security: Found 3, Removed 3, Failed 0
- Protected: 4 apps safely skipped

ESSENTIAL APPS BY CATEGORY:
- SystemCore: 4 apps installed
- Browsers: 2 apps already present
- Productivity: 3 apps installed
- Utilities: 2 apps installed
```

## 🏢 **Enterprise Features**

### **IT Admin Benefits**
- **Unified Reporting**: Single comprehensive report for compliance
- **Customizable Policies**: Configuration-driven deployment
- **Bulk Deployment**: JSON configuration for multiple machines
- **Audit Trail**: Detailed tracking of all system changes
- **Safety First**: Critical system protection built-in

### **Deployment Scenarios**
- **New Computer Setup**: Automated bloatware removal + essential apps installation
- **Regular Maintenance**: Scheduled cleanup with reporting
- **User Onboarding**: Role-based app installation (Developer, Gamer, Office Worker)
- **Compliance Checks**: Generate reports for IT audits

## 🔧 **Technical Implementation**

### **Research-Based Enhancements**
Based on analysis of leading Windows debloating projects:
- **Windows10Debloater**: Multi-method removal approach
- **ChrisTitusTech/WinUtil**: Category-based organization
- **W4RH4WK/Debloat-Windows-10**: Safety checks and rollback support

### **Modern PowerShell Features**
- **PowerShell 7.5.2 Optimized**: Modern async patterns, improved process management
- **Cross-Version Compatibility**: Automatic fallback to Windows PowerShell 5.1
- **Enhanced Error Handling**: Timeout protection, robust exception management
- **Performance Monitoring**: Built-in execution time and resource tracking

### **System Requirements**
- **OS**: Windows 10 (1809+) or Windows 11
- **PowerShell**: 5.1+ (PowerShell 7.5.2 recommended)
- **Permissions**: Administrator rights required
- **Architecture**: x64 systems (x86 compatible)

## 🚨 **Important Notes**

### **Safety Guidelines**
- ⚠️ **Administrator Required**: Script must run with elevated permissions
- 🛡️ **System Restore**: Automatic restore point created before major changes
- 🔒 **Critical Apps Protected**: Essential system apps are never removed
- 💾 **Backup Recommended**: Create system backup before first run
- 🔄 **Rollback Available**: System restore can undo changes if needed

### **What Gets Removed (Bloatware Categories)**
- **OEM Bloatware**: Acer, ASUS, Dell, HP, Lenovo manufacturer apps
- **Gaming Apps**: King games, casual games, Xbox apps (if not kept)
- **Microsoft Bloatware**: Bing apps, Office hub, unused productivity apps
- **3D/AR Apps**: 3D Builder, Paint 3D, Mixed Reality Portal
- **Security Trials**: Trial antivirus, system optimizers
- **Social Media**: Facebook, Instagram, TikTok (if not kept)
- **Streaming Services**: Netflix, Spotify trials (if not kept)

### **What Gets Installed (Essential Categories)**
- **System Core**: Visual C++ Redistributables, .NET Runtime, PowerShell 7
- **Browsers**: Chrome, Firefox (configurable)
- **Productivity**: Adobe Reader, 7-Zip, Notepad++, LibreOffice
- **Communication**: Teams, Zoom, Thunderbird (if enabled)
- **Media**: VLC, GIMP, Paint.NET (if enabled)
- **Development**: VS Code, Git, Python (if enabled)
- **Utilities**: PowerToys, Everything Search (if enabled)

## 📋 **Changelog**

### **Version 2025.1.0 - Enhanced Release**
- ✨ **NEW**: Categorized bloatware removal with safety protection
- ✨ **NEW**: Priority-based essential apps installation
- ✨ **NEW**: Unified reporting system replacing dual logs
- ✨ **NEW**: Enhanced configuration with granular controls
- ✨ **NEW**: Multi-method app detection and removal
- ✨ **NEW**: Research-based improvements from leading projects
- 🔧 **IMPROVED**: PowerShell 7.5.2 optimization with PS5.1 fallback
- 🔧 **IMPROVED**: Better error handling and timeout protection
- 🔧 **IMPROVED**: Performance metrics and execution tracking
- 🛡️ **SECURITY**: Critical app protection and safety checks

### **Previous Versions**
- **2024.x.x**: Basic bloatware removal and essential apps installation
- **2023.x.x**: Initial maintenance automation features

## 📞 **Support & Contributing**

### **Getting Help**
- 📖 Check this README for configuration guidance
- 🔍 Review the generated `maintenance_report.txt` for detailed results
- ⚠️ Check Windows Event Logs for system-level issues
- 🛠️ Run with `EnableVerboseLogging: true` for detailed debugging

### **Contributing**
- 🐛 Report issues with detailed system information
- 💡 Suggest new bloatware apps or essential apps
- 🔧 Submit configuration improvements
- 📚 Help improve documentation

### **License**
This project is provided as-is for educational and maintenance purposes. Use at your own discretion on your own systems.

---
**🔄 Last Updated**: January 2025 | **⚡ Version**: 2025.1.0 Enhanced | **👨‍💻 Optimized for**: Windows 10/11 with PowerShell 7.5.2
- **Config (`config.json`)**: JSON format. Customizes task execution, exclusions, and reporting.

## Modern PowerShell 7.5.2 Features
- **Parallel Processing**: `ForEach-Object -Parallel` for significantly faster inventory collection
- **Enhanced JSON Operations**: Improved parsing with `-AsHashtable` and better error handling
- **Modern Process Management**: `Invoke-ModernPackageManager` with timeout and retry logic
- **Async File I/O**: UTF-8 encoding and improved file operations
- **Thread-Safe Collections**: Using `System.Collections.Concurrent` for reliability
- **Smart Compatibility**: Automatic detection and fallback to Windows PowerShell for legacy modules

## Environment of Execution
- **OS:** Windows 10/11 (x64, ARM64 supported)
- **Shell:** **PowerShell 7.5.2+ preferred**, with automatic fallback to PowerShell 5.1 for compatibility
- **Dependencies:** Winget, Chocolatey, NuGet, PSWindowsUpdate, Appx (checked/installed at runtime)
- **Execution:** Always run as administrator (auto-elevated by batch file)
- **Scheduled Tasks:** Monthly/startup tasks auto-created for recurring runs and post-restart continuation
- **Repo Update:** Batch file downloads/extracts latest repo ZIP from GitHub before each run

## Usage
1. **Double-click `script.bat`** or run it from an elevated command prompt.
2. **Watch the progress bars** in the console for real-time feedback.
3. Optionally edit `config.json` to customize tasks, exclusions, or reporting.
4. Review `maintenance.log` (clean, timestamped entries) and `maintenance_report.txt` (unified enhanced report with comprehensive system information and performance metrics) after each run.
5. Check `inventory.json` for comprehensive system state information.

## Configuration (`config.json`)
All keys are optional. The script intelligently handles missing configurations.

```json
{
  "SkipBloatwareRemoval": false,
  "SkipEssentialApps": false,
  "SkipWindowsUpdates": false,
  "SkipTelemetryDisable": false,
  "SkipSystemRestore": false,
  "EnableVerboseLogging": false,
  "ExcludeTasks": ["TaskName1", "TaskName2"],
  "AppWhitelist": ["Firefox", "LibreOffice"],
  "ReportLevel": "detailed"
}
```

## Enhanced Execution Flow
1. User runs `script.bat` (double-click or scheduled task).
2. Batch file checks dependencies, auto-elevates, updates repo, launches `script.ps1` as admin.
3. **PowerShell 7.5.2 script** executes with enhanced progress tracking:
   - **System inventory collection** (parallel processing for speed)
   - **Bloatware removal** (diff-based analysis with progress bars)
   - **Essential app installation** (modern package managers with status)
   - **Package updates** (winget/chocolatey with enhanced reliability)
   - **Windows updates** (with progress indication)
   - **Telemetry/privacy tweaks**
   - **Temp file cleanup** (detailed progress with folder/item counts)
   - **System restore and cleanup**
   - **Final reporting** with structured output
4. **Enhanced logging**: Progress bars in console, clean timestamped entries in log files.
5. **Comprehensive reports**: Detailed inventory, operation results, and temp list files for analysis.

## Key Improvements
### **Performance**
- **Parallel inventory collection** reduces execution time significantly
- **Async package operations** with proper timeout handling
- **Modern process management** for better reliability

### **User Experience**
- **Real-time progress bars** for visual feedback
- **Enhanced color coding** for different message types
- **Clean separation** between console display and file logging

### **Reliability**
- **Enhanced error handling** with detailed exception information
- **Graceful degradation** when dependencies are missing
- **Automatic compatibility detection** and fallback mechanisms

### **Maintainability**
- **Standardized temp lists** with JSON metadata for debugging
- **Modular logging functions** for different output needs
- **Comprehensive documentation** and clear code structure

## Troubleshooting
- **Check `maintenance.log`** for clean, timestamped operational logs without progress noise.
- **Review `maintenance_report.txt`** for the unified enhanced report with comprehensive system information, execution metrics, and performance data.
- **Examine `inventory.json`** for comprehensive system state information.
- **Check temp list files** (JSON format) for bloatware/essential app operation details.
- **Ensure PowerShell 7.5.2+** is installed for optimal performance (script will auto-fallback if needed).
- **Verify all dependencies** are installed and up to date.

## Performance Notes
- **Significantly faster** inventory collection using parallel processing
- **Improved package management** with modern timeout and retry logic
- **Better memory usage** with thread-safe concurrent collections
- **Enhanced file I/O** with UTF-8 encoding and async operations

## Contributing
Pull requests and feedback are welcome! See `.github/copilot-instructions.md` for AI agent conventions and PowerShell 7.5.2 best practices.

## License
[MIT](LICENSE)
  ```powershell
  # Remove non-whitelisted browsers
  # Configure Firefox, Chrome, Edge policies
  # Set Firefox as default browser
  ```

---
