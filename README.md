# Windows Maintenance Script

## Overview
This script performs comprehensive Windows maintenance including:
- System inventory collection
- Bloatware removal using multiple methods
- Essential application installation
- Windows updates
- Telemetry disabling
- System restore point creation

## Configuration
The script supports configuration via a `config.json` file. Copy `config.json.sample` to `config.json` and customize:

### Configuration Options
- `SkipBloatwareRemoval`: Skip the bloatware removal process
- `SkipEssentialApps`: Skip essential application installation
- `SkipWindowsUpdates`: Skip Windows update check/installation
- `SkipTelemetryDisable`: Skip telemetry and privacy tweaks
- `SkipSystemRestore`: Skip system restore point creation
- `EnableVerboseLogging`: Enable detailed verbose logging
- `CustomEssentialApps`: Array of additional apps to install
- `CustomBloatwareList`: Array of additional apps to remove

### Custom Apps Format
```json
{
  "Name": "App Display Name",
  "Winget": "Publisher.AppId",
  "Choco": "chocolatey-package-name"
}
```

## Usage
1. Run as Administrator
2. Place custom `config.json` in script directory if needed
3. Execute `script.bat` or run `script.ps1` directly

## Logging
All operations are logged to `maintenance.log` in the script directory.

## Features

### Enhanced Bloatware Removal
- AppX package removal (user and provisioned)
- DISM-based removal
- Winget uninstallation
- Chocolatey uninstallation
- Windows Capabilities removal
- Registry deprovisioning

### Browser Management
- Removes unwanted browsers (configurable whitelist)
- Configures Firefox, Chrome, and Edge policies
- Sets Firefox as default browser when possible

### Inventory Collection
Comprehensive system inventory including:
- Installed applications (AppX, Winget, Chocolatey, Registry)
- System information
- Services
- Scheduled tasks
- Drivers
- Windows updates

### Privacy & Telemetry
- Disables Windows telemetry services
- Configures browser privacy settings
- Disables scheduled data collection tasks
- Modifies registry for enhanced privacy

## Prerequisites
- Windows 10/11
- PowerShell 5.1 or later
- Administrator privileges
- Internet connection for package managers

## Package Manager Support
- Winget (Windows Package Manager)
- Chocolatey
- AppX/MSIX packages
- Traditional Windows installers
