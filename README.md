# Windows Fresh Install Setup & Maintenance Script

A comprehensive automation tool for setting up and maintaining Windows 10/11 systems after fresh installation.

## Project Structure

```
script_mentenanta/
├── setup/
│   ├── setup.bat                 # Main entry point
│   ├── dependencies.bat          # Dependency installation logic
│   ├── functions.bat             # Reusable batch functions
│   └── config.bat                # Configuration variables
├── maintenance/
│   ├── maintenance.ps1           # Main PowerShell maintenance script
│   ├── modules/
│   │   ├── SystemProtection.ps1  # System restore functionality
│   │   ├── PackageManager.ps1    # WinGet operations
│   │   ├── Debloating.ps1        # Bloatware removal
│   │   ├── Privacy.ps1           # Privacy & telemetry settings
│   │   ├── Updates.ps1           # Windows updates
│   │   ├── Cleanup.ps1           # System cleanup
│   │   └── Reporting.ps1         # Logging & reporting
│   └── config/
│       ├── bloatware.json        # Bloatware definitions
│       ├── essential-apps.json   # Essential apps list
│       └── settings.json         # Script configuration
├── logs/                         # Generated logs directory
├── tests/
│   ├── unit-tests.ps1           # PowerShell unit tests
│   └── integration-tests.bat    # Full workflow tests
├── docs/
│   ├── USAGE.md                 # Usage instructions
│   ├── CONFIGURATION.md         # Configuration guide
│   └── TROUBLESHOOTING.md       # Common issues & solutions
├── .github/
│   └── workflows/
│       └── test.yml             # CI/CD pipeline
├── script.bat                   # Legacy entry point (backwards compatibility)
├── script.ps1                  # Legacy maintenance script
├── VERSION                      # Version file
└── CHANGELOG.md                # Version history
```

## Quick Start

1. Right-click `setup/setup.bat` and select "Run as administrator"
2. Follow the on-screen prompts
3. The script will automatically handle all dependencies and run maintenance

## Features

- ✅ Automatic dependency installation (WinGet, PowerShell 7, etc.)
- ✅ Modular architecture with configurable components
- ✅ Comprehensive logging and error reporting
- ✅ Automatic restart handling with scheduled tasks
- ✅ Bloatware removal with smart detection
- ✅ Privacy & telemetry hardening
- ✅ Essential software installation
- ✅ System cleanup and optimization
- ✅ Unit and integration testing
- ✅ CI/CD pipeline for automated testing

## Configuration

See [CONFIGURATION.md](docs/CONFIGURATION.md) for detailed configuration options.

## Troubleshooting

See [TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) for common issues and solutions.
