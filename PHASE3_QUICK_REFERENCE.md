# Phase 3 Quick Reference Guide

## 🚀 Quick Start

### Using Environment Configurations

```powershell
# Development (safe testing with dry-run)
$env = Get-Content "config/settings/environments/development.json" | ConvertFrom-Json
# Dry-run: ✅ Enabled

# Production (live execution)
$env = Get-Content "config/settings/environments/production.json" | ConvertFrom-Json
# Dry-run: ❌ Disabled

# Testing (comprehensive logging)
$env = Get-Content "config/settings/environments/testing.json" | ConvertFrom-Json
# Dry-run: ✅ Enabled
```

## 📁 New Directory Structure

```
config/
├── schemas/                       ⭐ All JSON Schemas centralized here
│   ├── main-config.schema.json
│   ├── logging-config.schema.json
│   ├── security-config.schema.json
│   ├── bloatware-list.schema.json
│   ├── essential-apps.schema.json
│   ├── app-upgrade-config.schema.json
│   └── system-optimization-config.schema.json
│
├── settings/
│   ├── main-config.json
│   ├── logging-config.json
│   ├── security-config.json
│   └── environments/              ⭐ Environment-specific overrides
│       ├── development.json       # Dry-run enabled
│       ├── production.json        # Live execution
│       └── testing.json           # Test configuration
│
├── lists/                         ⭐ Organized by module
│   ├── bloatware/
│   │   └── bloatware-list.json
│   ├── essential-apps/
│   │   └── essential-apps.json
│   ├── system-optimization/
│   │   └── system-optimization-config.json
│   └── app-upgrade/
│       └── app-upgrade-config.json
│
└── templates/
    └── ... (report templates)
```

## 🔧 Configuration File Locations

| Configuration       | New Location (Phase 3)                                      | Legacy Location (Phase 2)                |
| ------------------- | ----------------------------------------------------------- | ---------------------------------------- |
| **Settings**        |                                                             |                                          |
| Main Config         | `settings/main-config.json`                                 | Same (no change)                         |
| Logging Config      | `settings/logging-config.json`                              | Same (no change)                         |
| Security Config     | `settings/security-config.json`                             | Same (no change)                         |
| **Lists**           |                                                             |                                          |
| Bloatware           | `lists/bloatware/bloatware-list.json`                       | `lists/bloatware-list.json`              |
| Essential Apps      | `lists/essential-apps/essential-apps.json`                  | `lists/essential-apps.json`              |
| System Optimization | `lists/system-optimization/system-optimization-config.json` | `lists/system-optimization-config.json`  |
| App Upgrade         | `lists/app-upgrade/app-upgrade-config.json`                 | `lists/app-upgrade-config.json`          |
| **Schemas**         |                                                             |                                          |
| All Schemas         | `schemas/{config-name}.schema.json`                         | `{config-dir}/{config-name}.schema.json` |

## 🎯 Common Tasks

### 1. Load Configuration (Automatic Path Resolution)

```powershell
# These functions automatically use new paths with fallback
$bloatware = Get-BloatwareConfiguration
$essentialApps = Get-EssentialAppsConfiguration
$sysOpt = Get-SystemOptimizationConfiguration
$appUpgrade = Get-AppUpgradeConfiguration
```

### 2. Validate Configuration with Schema

```powershell
# Schema auto-discovered from config/schemas/
$result = Test-ConfigurationWithJsonSchema `
    -ConfigFilePath "config/lists/bloatware/bloatware-list.json"

if ($result.IsValid) {
    Write-Host "✅ Configuration valid"
} else {
    Write-Warning "❌ Validation errors: $($result.ErrorDetails)"
}
```

### 3. Add New Configuration File

```powershell
# Step 1: Create subdirectory under config/lists/
New-Item -Path "config/lists/my-module" -ItemType Directory -Force

# Step 2: Create configuration file
$myConfig = @{
    version = "1.0.0"
    enabled = $true
    settings = @{
        option1 = "value1"
    }
}
$myConfig | ConvertTo-Json -Depth 10 | `
    Set-Content "config/lists/my-module/my-config.json"

# Step 3: Create JSON schema in centralized location
$schema = @{
    '$schema' = 'http://json-schema.org/draft-07/schema#'
    title = "My Module Configuration"
    type = "object"
    properties = @{
        version = @{ type = "string" }
        enabled = @{ type = "boolean" }
        settings = @{ type = "object" }
    }
    required = @("version", "enabled")
}
$schema | ConvertTo-Json -Depth 10 | `
    Set-Content "config/schemas/my-config.schema.json"

# Step 4: Update CoreInfrastructure.psm1 Get-JsonConfiguration
# Add to $configFiles hashtable:
# 'MyModule' = 'lists\my-module\my-config.json'
```

### 4. Create Custom Environment Profile

```powershell
# Create new environment (e.g., staging)
$stagingConfig = @{
    execution = @{
        enableDryRun = $false          # Live execution like prod
        countdownSeconds = 15           # Shorter countdown
        mode = "attended"               # Interactive mode
        createRestorePoint = $true      # Safety enabled
    }
    logging = @{
        consoleLevel = "Information"
        fileLevel = "Debug"             # More verbose than prod
        maxLogSizeMB = 100
    }
    tasks = @{
        bloatwareRemoval = @{ enabled = $true }
        essentialApps = @{ enabled = $true }
        systemOptimization = @{ enabled = $true }
        windowsUpdates = @{ enabled = $false }  # Skip in staging
    }
}

$stagingConfig | ConvertTo-Json -Depth 10 | `
    Set-Content "config/settings/environments/staging.json"
```

## 🔍 Path Discovery Logic

### Configuration Files

```powershell
# Get-JsonConfiguration tries paths in order:

1. Phase 3 path: config/lists/{module}/{config}.json
   Example: config/lists/bloatware/bloatware-list.json

2. Phase 2 path: config/lists/{config}.json
   Example: config/lists/bloatware-list.json

3. Legacy path: config/data/{config}.json
   Example: config/data/bloatware-list.json

4. Return default values
```

### Schema Files

```powershell
# Test-ConfigurationWithJsonSchema tries schemas in order:

1. Centralized (Phase 3): config/schemas/{config-name}.schema.json
   Example: config/schemas/bloatware-list.schema.json

2. Same directory (Phase 2): {config-dir}/{config-name}.schema.json
   Example: config/lists/bloatware/bloatware-list.schema.json

3. Skip validation (mark as valid)
```

## ⚡ Environment Configurations

### development.json

**Use Case:** Local development, testing new modules

**Key Settings:**

- ✅ Dry-run enabled (safe)
- Countdown: 10 seconds
- Skip: Windows Updates, Security Enhancement, App Upgrade
- System restore: Disabled (faster)
- Logging: Verbose

**When to use:**

- Developing new features
- Testing module changes
- Learning the codebase
- Safe experimentation

### production.json

**Use Case:** Live deployments, real system changes

**Key Settings:**

- ❌ Dry-run disabled (live execution)
- Countdown: 30 seconds
- Mode: Unattended
- All modules: Enabled
- System restore: Enabled (safety)
- Logging: Minimal

**When to use:**

- Actual system maintenance
- Automated deployments
- Scheduled tasks
- Real bloatware removal

### testing.json

**Use Case:** Comprehensive testing with detailed logs

**Key Settings:**

- ✅ Dry-run enabled (safe)
- Countdown: 5 seconds
- Max log size: 200 MB
- Detailed audit: Enabled
- System inventory: Enabled
- Temp folder: `temp_files_test/`

**When to use:**

- Running test suites
- CI/CD pipelines
- Validation before release
- Debugging complex issues

## 🛠️ Migration from Phase 2

### No Action Required ✅

Phase 3 includes automatic fallback to Phase 2 structure.

**What happens:**

1. System tries new Phase 3 path
2. If not found, falls back to Phase 2 path
3. If not found, uses default values
4. **Result:** Everything continues working

### Optional Manual Migration

If you want to fully adopt Phase 3 structure:

```powershell
# 1. Create new directory structure
New-Item -Path "config/schemas" -ItemType Directory -Force
New-Item -Path "config/lists/bloatware" -ItemType Directory -Force
New-Item -Path "config/lists/essential-apps" -ItemType Directory -Force
New-Item -Path "config/lists/system-optimization" -ItemType Directory -Force
New-Item -Path "config/lists/app-upgrade" -ItemType Directory -Force
New-Item -Path "config/settings/environments" -ItemType Directory -Force

# 2. Move configuration files
Move-Item "config/lists/bloatware-list.json" "config/lists/bloatware/"
Move-Item "config/lists/essential-apps.json" "config/lists/essential-apps/"
Move-Item "config/lists/system-optimization-config.json" "config/lists/system-optimization/"
Move-Item "config/lists/app-upgrade-config.json" "config/lists/app-upgrade/"

# 3. Move all schemas to centralized location
Move-Item "config/settings/*.schema.json" "config/schemas/"
Move-Item "config/lists/*.schema.json" "config/schemas/"

# 4. Copy environment templates
Copy-Item "config/settings/environments/*.json" "config/settings/environments/" -Force

# 5. Verify with test suite
pwsh -File .\Test-Phase3.ps1
# Expected: 32/32 tests passing
```

## 🧪 Testing & Validation

### Run Phase 3 Test Suite

```powershell
pwsh -File .\Test-Phase3.ps1
# Expected: 32/32 tests passing (100%)
```

### Manual Validation

```powershell
# Test configuration loading
$bloatware = Get-BloatwareConfiguration
Write-Host "Loaded items: $($bloatware.applications.Count)"

# Test schema validation
$result = Test-ConfigurationWithJsonSchema `
    -ConfigFilePath "config/lists/bloatware/bloatware-list.json"
Write-Host "Valid: $($result.IsValid)"

# Test environment configs
$dev = Get-Content "config/settings/environments/development.json" | ConvertFrom-Json
Write-Host "Dev dry-run: $($dev.execution.enableDryRun)"
```

## 📝 Best Practices

### 1. Always Use Centralized Schemas

✅ **Do:**

```powershell
# Put schema in centralized location
Set-Content "config/schemas/my-config.schema.json" -Value $schema
```

❌ **Don't:**

```powershell
# Don't put schema next to config file anymore
Set-Content "config/lists/my-module/my-config.schema.json" -Value $schema
```

### 2. Organize Config Files by Module

✅ **Do:**

```powershell
# Create subdirectory per module
New-Item "config/lists/my-module" -ItemType Directory
Set-Content "config/lists/my-module/config.json" -Value $config
```

❌ **Don't:**

```powershell
# Don't put all configs in flat structure
Set-Content "config/lists/my-module-config.json" -Value $config
```

### 3. Use Environment Configs for Different Scenarios

✅ **Do:**

```powershell
# Load appropriate environment
if ($IsProduction) {
    $env = Get-Content "config/settings/environments/production.json" | ConvertFrom-Json
} else {
    $env = Get-Content "config/settings/environments/development.json" | ConvertFrom-Json
}
```

❌ **Don't:**

```powershell
# Don't manually toggle dry-run in main-config.json
$config.execution.enableDryRun = $false
```

### 4. Validate Before Deployment

✅ **Do:**

```powershell
# Always validate with schema before deploying
$result = Test-ConfigurationWithJsonSchema -ConfigFilePath $configPath
if (-not $result.IsValid) {
    throw "Configuration invalid: $($result.ErrorDetails)"
}
```

❌ **Don't:**

```powershell
# Don't skip validation
$config = Get-Content $configPath | ConvertFrom-Json
# Deploy without validation
```

## 🔗 Related Documentation

- **Full Implementation Details:** [PHASE3_IMPLEMENTATION_SUMMARY.md](PHASE3_IMPLEMENTATION_SUMMARY.md)
- **Project Architecture:** [PROJECT.md](PROJECT.md)
- **Refactoring Analysis:** [COMPREHENSIVE_REFACTORING_ANALYSIS.md](COMPREHENSIVE_REFACTORING_ANALYSIS.md)
- **Copilot Instructions:** [.github/copilot-instructions.md](.github/copilot-instructions.md)

## 💡 Tips & Tricks

### Find All Configuration Files

```powershell
Get-ChildItem -Path "config/lists" -Filter "*.json" -Recurse |
    Where-Object { $_.Name -notlike "*.schema.json" } |
    Select-Object FullName
```

### Find All Schema Files

```powershell
Get-ChildItem -Path "config/schemas" -Filter "*.schema.json"
```

### Compare Environment Configs

```powershell
$dev = Get-Content "config/settings/environments/development.json" | ConvertFrom-Json
$prod = Get-Content "config/settings/environments/production.json" | ConvertFrom-Json

Write-Host "Dev dry-run: $($dev.execution.enableDryRun)"
Write-Host "Prod dry-run: $($prod.execution.enableDryRun)"
```

### Validate All Configs at Once

```powershell
$configs = @(
    "config/lists/bloatware/bloatware-list.json",
    "config/lists/essential-apps/essential-apps.json",
    "config/lists/system-optimization/system-optimization-config.json",
    "config/lists/app-upgrade/app-upgrade-config.json",
    "config/settings/main-config.json",
    "config/settings/logging-config.json"
)

foreach ($configPath in $configs) {
    $result = Test-ConfigurationWithJsonSchema -ConfigFilePath $configPath
    $status = if ($result.IsValid) { "✅" } else { "❌" }
    Write-Host "$status $(Split-Path $configPath -Leaf)"
}
```

## 🚨 Troubleshooting

### Issue: "Configuration file not found"

**Cause:** File moved but old path still referenced

**Solution:**

```powershell
# Check both new and legacy paths
$newPath = "config/lists/bloatware/bloatware-list.json"
$legacyPath = "config/lists/bloatware-list.json"

if (Test-Path $newPath) {
    Write-Host "Using Phase 3 path: $newPath"
} elseif (Test-Path $legacyPath) {
    Write-Host "Using Phase 2 path: $legacyPath"
} else {
    Write-Warning "File not found in either location"
}
```

### Issue: "Schema not found"

**Cause:** Schema not in centralized location

**Solution:**

```powershell
# Move schema to centralized location
$schemaName = "bloatware-list.schema.json"
$centralizedPath = "config/schemas/$schemaName"

if (-not (Test-Path $centralizedPath)) {
    # Check legacy location
    $legacyPath = "config/lists/$schemaName"
    if (Test-Path $legacyPath) {
        Move-Item $legacyPath $centralizedPath
        Write-Host "✅ Moved schema to centralized location"
    }
}
```

### Issue: "Environment config not loading"

**Cause:** Environment directory not created

**Solution:**

```powershell
# Ensure environment directory exists
$envDir = "config/settings/environments"
if (-not (Test-Path $envDir)) {
    New-Item -Path $envDir -ItemType Directory -Force
    Write-Host "✅ Created environment directory"
}

# Copy templates from source
Copy-Item "path/to/templates/environments/*.json" $envDir -Force
```

---

**Phase 3 Status:** ✅ Complete  
**Test Results:** 32/32 passing (100%)  
**Backward Compatibility:** ✅ Fully maintained  
**Ready for:** Phase 4 (Testing & Documentation)
