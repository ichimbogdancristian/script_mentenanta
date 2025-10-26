# Pull Request

## Description
Provide a clear and concise description of what this PR accomplishes.

## Type of Change
- [ ] Bug fix (non-breaking change which fixes an issue)
- [ ] New feature (non-breaking change which adds functionality)
- [ ] Breaking change (fix or feature that would cause existing functionality to not work as expected)
- [ ] Documentation update
- [ ] Code refactoring (no functional changes)
- [ ] Configuration change
- [ ] Module development (new Type1/Type2 module pair)

## Related Issues
Closes #(issue number)

## Changes Made
List the specific changes made in this PR:
- 
- 
- 

## Module Changes (if applicable)
### Modified Modules
- [ ] CoreInfrastructure
- [ ] UserInterface
- [ ] ReportGenerator
- [ ] BloatwareRemoval / BloatwareDetectionAudit
- [ ] EssentialApps / EssentialAppsAudit
- [ ] SystemOptimization / SystemOptimizationAudit
- [ ] TelemetryDisable / TelemetryAudit
- [ ] WindowsUpdates / WindowsUpdatesAudit
- [ ] AppUpgrade / AppUpgradeAudit
- [ ] MaintenanceOrchestrator.ps1
- [ ] Other: ___________

### Configuration Changes
- [ ] main-config.json
- [ ] logging-config.json
- [ ] bloatware-list.json
- [ ] essential-apps.json
- [ ] report-templates-config.json
- [ ] New config file: ___________

## Testing Performed
- [ ] Tested with DryRun mode
- [ ] Tested with full execution
- [ ] Tested on Windows 10
- [ ] Tested on Windows 11
- [ ] Validated JSON configuration files
- [ ] Ran PSScriptAnalyzer with zero errors
- [ ] Verified temp_files structure creation
- [ ] Checked report generation
- [ ] Tested menu navigation
- [ ] Verified logging functionality

## Test Results
```
Paste relevant test output or logs here
```

## VS Code Diagnostics
- [ ] Zero critical errors in Problems panel
- [ ] Zero warnings in Problems panel
- [ ] PSScriptAnalyzer validation passed

## Architecture Compliance (v3.0)
- [ ] Type2 modules internally import Type1 modules (self-contained)
- [ ] Type2 modules import CoreInfrastructure with `-Global` flag
- [ ] Uses `$Global:ProjectPaths` for all file operations
- [ ] Type1 saves results to `temp_files/data/`
- [ ] Type2 creates logs in `temp_files/logs/[module]/`
- [ ] Follows standardized return object structure
- [ ] Implements DryRun mode correctly
- [ ] No hardcoded absolute paths (uses path variables)

## Breaking Changes
If this PR introduces breaking changes, describe them here:
- 
- 

## Migration Guide (if breaking changes)
Provide steps users need to take to adapt to breaking changes:
1. 
2. 

## Documentation
- [ ] Updated README.md
- [ ] Updated ADDING_NEW_MODULES.md (if new module)
- [ ] Updated inline code comments
- [ ] Updated copilot-instructions.md (if architecture changes)
- [ ] Added/updated configuration documentation

## Screenshots (if applicable)
Add screenshots showing:
- Menu changes
- Report output
- Terminal execution

## Checklist
- [ ] My code follows the PowerShell 7+ syntax standards
- [ ] I have performed a self-review of my code
- [ ] I have commented my code, particularly in hard-to-understand areas
- [ ] My changes generate no new warnings or errors
- [ ] I have tested my changes thoroughly
- [ ] I have updated the documentation accordingly
- [ ] All temp files use organized `temp_files/` structure
- [ ] Reports are generated in parent directory correctly
- [ ] Module follows v3.0 self-contained architecture pattern

## Additional Notes
Any additional information reviewers should know:
