# Contributing to Windows Maintenance Automation

Thank you for your interest in contributing! This document provides guidelines for contributing to this project.

## 📋 Table of Contents
- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [Development Setup](#development-setup)
- [Project Architecture](#project-architecture)
- [Contribution Workflow](#contribution-workflow)
- [Coding Standards](#coding-standards)
- [Testing Requirements](#testing-requirements)
- [Documentation](#documentation)
- [Pull Request Process](#pull-request-process)

## Code of Conduct
- Be respectful and professional
- Provide constructive feedback
- Focus on what is best for the project
- Show empathy towards other contributors

## Getting Started

### Prerequisites
- Windows 10/11 (64-bit)
- PowerShell 7.0 or higher
- Administrator privileges
- Git for version control
- VS Code with PowerShell extension (recommended)

### Development Setup
1. **Clone the repository**
   ```powershell
   git clone https://github.com/ichimbogdancristian/script_mentenanta.git
   cd script_mentenanta
   ```

2. **Install development dependencies**
   ```powershell
   Set-PSRepository PSGallery -InstallationPolicy Trusted
   Install-Module -Name PSScriptAnalyzer -Scope CurrentUser
   Install-Module -Name Pester -Scope CurrentUser
   ```

3. **Configure VS Code**
   - Install PowerShell extension
   - Enable PSScriptAnalyzer in settings
   - Configure auto-formatting on save

## Project Architecture

### v3.0 Self-Contained Module Pattern
- **Type2 modules** are primary execution units (user-triggered)
- **Type1 modules** are audit/detection services (Type2-triggered)
- **Type2 modules** internally import their Type1 counterparts
- **Orchestrator** loads only core services (CoreInfrastructure, UserInterface, ReportGenerator)

### Key Principles
1. **Detection Before Action**: Type1 must run before Type2 acts
2. **Diff-Based Execution**: Only process items found in diff (detected ∩ config)
3. **DryRun Support**: All Type2 modules must support simulation mode
4. **Structured Logging**: Use organized `temp_files/` structure
5. **Standardized Returns**: All modules return consistent result objects

See `.github/copilot-instructions.md` for complete architecture details.

## Contribution Workflow

### 1. Create an Issue
Before starting work, create an issue describing:
- Problem you're solving or feature you're adding
- Proposed solution approach
- Expected impact on existing functionality

### 2. Fork and Branch
```powershell
# Fork the repository on GitHub
git checkout -b feature/your-feature-name
# or
git checkout -b bugfix/issue-description
```

### 3. Make Your Changes
- Follow coding standards (see below)
- Add appropriate comments
- Update documentation
- Test thoroughly

### 4. Commit Your Changes
```powershell
git add .
git commit -m "Type: Brief description

Detailed explanation of changes:
- Change 1
- Change 2

Closes #issue-number"
```

**Commit types:**
- `feat:` New feature
- `fix:` Bug fix
- `docs:` Documentation changes
- `refactor:` Code refactoring
- `test:` Test additions/changes
- `config:` Configuration changes

### 5. Push and Create PR
```powershell
git push origin feature/your-feature-name
```
Then create a Pull Request on GitHub.

## Coding Standards

### PowerShell Style Guide
```powershell
# ✅ GOOD: Use approved verbs
function Get-SystemInfo { }
function Set-Configuration { }
function Invoke-Maintenance { }

# ❌ BAD: Non-approved verbs
function Fetch-SystemInfo { }
function Change-Configuration { }
function Run-Maintenance { }

# ✅ GOOD: Use PascalCase for functions/parameters
function Get-WindowsUpdate {
    param(
        [Parameter(Mandatory)]
        [string]$ComputerName,
        
        [switch]$IncludeHidden
    )
}

# ✅ GOOD: Use comment-based help
<#
.SYNOPSIS
    Brief description of function
.DESCRIPTION
    Detailed description
.PARAMETER ParameterName
    Description of parameter
.EXAMPLE
    Example usage
#>

# ✅ GOOD: Use global paths from CoreInfrastructure
$dataPath = Join-Path $Global:ProjectPaths.TempFiles "data\module-results.json"

# ❌ BAD: Hardcoded or relative paths
$dataPath = "C:\Temp\data\module-results.json"
$dataPath = ".\temp_files\data\module-results.json"

# ✅ GOOD: Proper error handling
try {
    $result = Invoke-SomeOperation
    Write-LogEntry -Level 'INFO' -Message "Operation succeeded"
}
catch {
    Write-LogEntry -Level 'ERROR' -Message "Operation failed: $_"
    throw
}

# ✅ GOOD: DryRun mode implementation
if ($DryRun) {
    Write-LogEntry -Level 'INFO' -Message "DRY-RUN: Would remove $itemName"
    return
}
# Actual operation
Remove-Item $itemPath
```

### Module Development Standards

**Type1 Module (Detection):**
```powershell
#Requires -Version 7.0

function Get-ModuleNameAnalysis {
    param([hashtable]$Config)
    
    # Use Write-Verbose, not throw, for CoreInfrastructure
    if ($null -eq $Global:ProjectPaths) {
        Write-Verbose "CoreInfrastructure not loaded"
    }
    
    # Detection logic here
    $results = @()
    
    # Return array of hashtables
    return $results
}

Export-ModuleMember -Function Get-ModuleNameAnalysis
```

**Type2 Module (Action):**
```powershell
#Requires -Version 7.0

# Import CoreInfrastructure with -Global (CRITICAL)
$corePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'core\CoreInfrastructure.psm1'
Import-Module $corePath -Force -Global

# Import Type1 module (self-contained)
$type1Path = Join-Path (Split-Path -Parent $PSScriptRoot) 'type1\ModuleNameAudit.psm1'
Import-Module $type1Path -Force

function Invoke-ModuleName {
    param([hashtable]$Config, [switch]$DryRun)
    
    # 1. Run Type1 detection
    # 2. Create diff
    # 3. Process items
    # 4. Return standardized result
    
    return @{
        Success = $true
        ItemsDetected = 0
        ItemsProcessed = 0
        Duration = 0
    }
}

Export-ModuleMember -Function Invoke-ModuleName
```

### File Organization
- Type1 modules: `modules/type1/[Name]Audit.psm1`
- Type2 modules: `modules/type2/[Name].psm1`
- Configuration: `config/[module-name]-config.json`
- Detection results: `temp_files/data/[module]-results.json`
- Execution logs: `temp_files/logs/[module-name]/execution.log`

## Testing Requirements

### Manual Testing Checklist
- [ ] Module imports without errors
- [ ] DryRun mode works (no OS modifications)
- [ ] Full execution creates proper temp_files structure
- [ ] Execution logs are detailed and accurate
- [ ] Reports include module section
- [ ] Error handling works correctly
- [ ] Zero VS Code diagnostics errors

### PSScriptAnalyzer Validation
```powershell
# Run before committing
Invoke-ScriptAnalyzer -Path . -Recurse -Severity Error,Warning
```

### Test on Multiple Environments
- Windows 10 (21H2 or later)
- Windows 11 (22H2 or later)
- Different hardware configurations

## Documentation

### Required Documentation Updates
1. **Inline comments** for complex logic
2. **README.md** for user-facing changes
3. **ADDING_NEW_MODULES.md** for new modules
4. **copilot-instructions.md** for architecture changes
5. **Configuration examples** in config files

### Documentation Style
- Use clear, concise language
- Include code examples
- Add troubleshooting sections
- Document all parameters and return values

## Pull Request Process

### Before Submitting
1. ✅ Run PSScriptAnalyzer with zero errors
2. ✅ Test DryRun mode thoroughly
3. ✅ Test full execution
4. ✅ Update relevant documentation
5. ✅ Check VS Code Problems panel (zero errors)
6. ✅ Verify temp_files structure is correct
7. ✅ Ensure reports generate properly

### PR Description Requirements
- Clear description of changes
- Link to related issue
- List of modified modules
- Test results summary
- Screenshots (if UI changes)
- Breaking changes (if any)

### Review Process
1. Automated checks must pass (GitHub Actions)
2. Code review by maintainer
3. Testing verification
4. Documentation review
5. Approval and merge

### After Merge
- Delete your branch
- Close related issues
- Update any dependent documentation

## Adding New Modules

See **[MODULE_DEVELOPMENT_GUIDE.md](.github/MODULE_DEVELOPMENT_GUIDE.md)** for condensed 10-step guide.
See **[ADDING_NEW_MODULES.md](../ADDING_NEW_MODULES.md)** for complete 883-line guide with templates.

### Quick Checklist
- [ ] Create Type1 audit module
- [ ] Create Type2 action module
- [ ] Create configuration file
- [ ] Register in MaintenanceOrchestrator.ps1
- [ ] Add toggle to main-config.json
- [ ] Add metadata to report-templates-config.json
- [ ] Test thoroughly
- [ ] Update documentation

## Questions or Problems?

- **Documentation**: Check `.github/copilot-instructions.md`
- **Module Development**: See `.github/MODULE_DEVELOPMENT_GUIDE.md`
- **Issues**: Create a GitHub issue with `question` label
- **Discussion**: Start a GitHub Discussion

## License
By contributing, you agree that your contributions will be licensed under the same license as the project.

---

Thank you for contributing to Windows Maintenance Automation! 🚀
