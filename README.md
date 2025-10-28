# Windows Maintenance Automation

A comprehensive PowerShell 7+ system for enterprise-grade Windows maintenance with modular architecture, comprehensive reporting, and built-in safety mechanisms.

## 🚀 Quick Start

```powershell
# Clone the repository
git clone https://github.com/ichimbogdancristian/script_mentenanta.git
cd script_mentenanta

# Run the maintenance script (requires administrator privileges)
.\script.bat
```

## ✨ Features

- **Three-tier modular architecture** (Core → Type1 Audit → Type2 Action)
- **Comprehensive system analysis** and remediation
- **Rich HTML/JSON reporting** with audit trails
- **Safety mechanisms**: dry-run mode, restore points, admin verification
- **Batch processing** of multiple maintenance tasks
- **Self-contained deployment** with automatic dependency installation

## 📋 System Requirements

- Windows 10/11 or Windows Server 2016+
- Administrator privileges
- PowerShell 7+ (auto-installed if missing)
- .NET Framework 4.7.2+ (usually pre-installed)

## 🏗️ Architecture Overview

### Three-Tier Module System

```
Core Modules (Global Infrastructure)
├── CoreInfrastructure.psm1    # Configuration, logging, paths
├── UserInterface.psm1         # Interactive menus, countdowns
├── ReportGenerator.psm1       # HTML/JSON report generation
└── LogAggregator.psm1         # Centralized logging

Type1 Modules (Read-Only Audit)
├── BloatwareDetectionAudit.psm1
├── WindowsUpdateAudit.psm1
└── SystemHealthAudit.psm1

Type2 Modules (Modification Actions)
├── BloatwareRemoval.psm1
├── EssentialAppsInstallation.psm1
└── WindowsUpdateInstallation.psm1
```

### Execution Flow

```
script.bat → MaintenanceOrchestrator.ps1 → Module Discovery → Task Execution → Report Generation
```

## 🛠️ Development

### Code Quality Standards

This project maintains strict code quality standards:

- **PSScriptAnalyzer compliance** for all PowerShell files
- **JSON schema validation** for configuration files
- **HTML accessibility standards** (WCAG 2.1 AA) for reports
- **UTF-8 BOM encoding** for PowerShell files
- **Comprehensive error handling** and logging

### Running Quality Checks

```powershell
# Run comprehensive quality validation
.\scripts\pre-commit-check.ps1 -Detailed

# Auto-fix common issues
.\scripts\pre-commit-check.ps1 -Fix

# VS Code tasks (Ctrl+Shift+P → "Tasks: Run Task")
# - Quality Check - Full
# - PSScriptAnalyzer - All Files
# - Validate JSON Files
```

### VS Code Setup

The project includes comprehensive VS Code configuration:

```json
// Automatic setup included:
// - PSScriptAnalyzer integration
// - JSON schema validation
// - HTML formatting and validation
// - Consistent file encoding (UTF-8 BOM)
// - Code formatting on save
```

**Recommended extensions** (auto-suggested):
- PowerShell Extension
- JSON Tools
- HTML CSS Support
- Error Lens
- Auto Rename Tag

## 📁 Project Structure

```
script_mentenanta/
├── 📜 script.bat                    # Entry point launcher
├── 📜 MaintenanceOrchestrator.ps1   # PowerShell orchestrator
├── 📁 modules/
│   ├── 📁 core/                     # Infrastructure modules
│   ├── 📁 type1/                    # Audit modules (read-only)
│   └── 📁 type2/                    # Action modules (modifications)
├── 📁 config/
│   ├── 📁 settings/                 # Execution configuration
│   ├── 📁 lists/                    # Data lists (bloatware, apps)
│   └── 📁 templates/                # HTML report templates
├── 📁 docs/
│   ├── 📁 guides/                   # Development guides
│   ├── 📁 architecture/             # Architecture documentation
│   └── 📁 modules/                  # Module API reference
├── 📁 scripts/                      # Utility scripts
├── 📁 .vscode/                      # VS Code configuration
└── 📁 temp_files/                   # Runtime output (auto-created)
    ├── 📁 logs/                     # Execution logs
    ├── 📁 reports/                  # Generated reports
    ├── 📁 data/                     # Audit results
    └── 📁 temp/                     # Temporary files
```

## 🎯 Usage Examples

### Interactive Mode

```powershell
# Full interactive experience with countdown timers
.\script.bat

# PowerShell direct execution
.\MaintenanceOrchestrator.ps1
```

### Non-Interactive Mode

```powershell
# Execute all default tasks
.\MaintenanceOrchestrator.ps1 -NonInteractive

# Execute specific tasks
.\MaintenanceOrchestrator.ps1 -NonInteractive -TaskNumbers "1,3,5"

# Dry-run mode (safe testing)
.\MaintenanceOrchestrator.ps1 -DryRun -TaskNumbers "1,2"
```

### Command-Line Parameters

| Parameter | Description | Example |
|-----------|-------------|---------|
| `-NonInteractive` | Skip menus, execute default tasks | `-NonInteractive` |
| `-DryRun` | Simulate changes without modifying system | `-DryRun` |
| `-TaskNumbers` | Execute specific tasks only | `-TaskNumbers "1,3,5"` |

## 📊 Reports and Logging

### Generated Reports

All executions generate comprehensive reports:

```
temp_files/reports/
├── MaintenanceReport_20241028_143022.html    # Rich HTML report
├── MaintenanceReport_20241028_143022.json    # Machine-readable data
└── MaintenanceReport_20241028_143022.txt     # Plain text summary
```

### Report Features

- **Executive summary** with task success rates
- **Detailed task results** with before/after comparisons
- **System information** and environment details
- **Performance metrics** and execution timings
- **Error tracking** and troubleshooting information
- **Accessibility compliant** HTML (WCAG 2.1 AA)

### Logging System

Structured logging across all modules:

```
temp_files/logs/
├── core/                           # Core module logs
├── type1/                          # Audit module logs
├── type2/                          # Action module logs
└── session-{sessionId}.json        # Session manifest
```

## 🔧 Configuration

### Main Configuration

Edit `config/settings/main-config.json`:

```json
{
  \"execution\": {
    \"countdownSeconds\": 20,
    \"dryRunByDefault\": false,
    \"autoCreateRestorePoint\": true
  },
  \"reporting\": {
    \"generateHtmlReport\": true,
    \"copyToParentDirectory\": true,
    \"detailedLogging\": true
  }
}
```

### Data Lists

Customize behavior via JSON lists:

- `config/lists/bloatware-list.json` - Apps to detect/remove
- `config/lists/essential-apps.json` - Apps to install/maintain
- `config/lists/app-upgrade-config.json` - App upgrade definitions

## 🛡️ Safety Mechanisms

### Pre-Execution Safety

- **Administrator privilege verification** (auto-elevation)
- **PowerShell 7+ requirement** (auto-installation)
- **System Restore Point creation** (with System Protection verification)
- **Dry-run validation** before any system modifications

### Recovery Options

- **System Restore**: Restore to `WindowsMaintenance-{ID}` restore point
- **Detailed logs**: Complete execution trail in `temp_files/logs/`
- **Before/after reports**: Compare system state changes
- **Rollback guidance**: Module-specific recovery instructions

## 🤝 Contributing

### Development Workflow

1. **Fork and clone** the repository
2. **Set up VS Code** with recommended extensions
3. **Run quality checks**: `.\scripts\pre-commit-check.ps1 -Detailed`
4. **Create feature branch**: `git checkout -b feature/my-feature`
5. **Follow coding standards** (see [Code Quality Guide](docs/guides/CODE_QUALITY.md))
6. **Test thoroughly**: Include dry-run testing
7. **Submit pull request** with clear description

### Creating Custom Modules

See the [Module Development Guide](docs/guides/MODULE_DEVELOPMENT.md) for detailed instructions on creating Type1 (audit) and Type2 (action) modules.

### Code Quality Requirements

All contributions must pass:

- ✅ **PSScriptAnalyzer** validation (no warnings/errors)
- ✅ **JSON schema** compliance for configuration files
- ✅ **HTML accessibility** standards for templates
- ✅ **UTF-8 BOM encoding** for PowerShell files
- ✅ **Comprehensive error handling** in all functions
- ✅ **Comment-based help** for all public functions

## 📚 Documentation

### For Users
- **[Quick Start Guide](docs/QUICK_START.md)** - Get up and running quickly
- **[Configuration Reference](docs/guides/CONFIGURATION.md)** - Customize behavior
- **[FAQ](docs/guides/FAQ.md)** - Common questions and solutions

### For Developers
- **[Architecture Overview](docs/architecture/README.md)** - System design and patterns
- **[Module Development](docs/guides/MODULE_DEVELOPMENT.md)** - Create custom modules
- **[Code Quality Standards](docs/guides/CODE_QUALITY.md)** - Coding best practices
- **[API Reference](docs/modules/)** - Module APIs and interfaces

## 🔗 External Dependencies

The system automatically installs and manages:

- **PowerShell 7+** (Microsoft Store, GitHub, or direct download)
- **Winget** (App Installer from Microsoft Store)
- **Chocolatey** (Community package manager)
- **PSWindowsUpdate** (PowerShell Gallery module)

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🏷️ Version Information

- **Current Version**: 3.1.0
- **PowerShell Requirements**: 7.0+
- **Windows Compatibility**: Windows 10/11, Server 2016+
- **Last Updated**: October 28, 2025

## 📞 Support

- **Issues**: [GitHub Issues](https://github.com/ichimbogdancristian/script_mentenanta/issues)
- **Discussions**: [GitHub Discussions](https://github.com/ichimbogdancristian/script_mentenanta/discussions)
- **Documentation**: [Project Wiki](https://github.com/ichimbogdancristian/script_mentenanta/wiki)

---

**⚡ Powered by PowerShell 7+ | 🏗️ Built for Enterprise | 🛡️ Safety First**
