---
name: Module Development Request
about: Track development of a new Type1/Type2 module pair
title: '[MODULE] New Module: '
labels: module-development
assignees: ''
---

## Module Information
- **Module Name**: 
- **Category**: [System Optimization / Privacy / Application Management / Updates / Other]
- **Type1 Module**: [Name]Audit.psm1
- **Type2 Module**: [Name].psm1

## Purpose
Describe what this module will detect (Type1) and what actions it will perform (Type2).

## Configuration Requirements
- **Config File**: `config/[module]-config.json`
- **Required Settings**: 
  - List configuration options needed
  - Default values
  - User-configurable toggles

## Type1 Detection Logic
What will the audit module detect?
- Detection method (registry, files, services, etc.)
- Data structure for detection results
- JSON schema for `temp_files/data/[module]-results.json`

## Type2 Action Logic
What actions will the execution module perform?
- Diff creation logic (detected vs config)
- Action methods (remove, install, configure, etc.)
- DryRun simulation behavior
- Logging requirements

## Dependencies
- **PowerShell Modules**: 
- **External Tools**: 
- **Windows Features**: 
- **API Requirements**: 

## Integration Checklist
- [ ] Type1 module created in `modules/type1/`
- [ ] Type2 module created in `modules/type2/`
- [ ] Configuration file created in `config/`
- [ ] Type2 imports Type1 (self-contained pattern)
- [ ] Type2 imports CoreInfrastructure with `-Global`
- [ ] Registered in MaintenanceOrchestrator.ps1 ($type2Modules)
- [ ] Added to $registeredTasks hashtable
- [ ] Added to $taskSequence array
- [ ] Toggle added to config/main-config.json
- [ ] Metadata added to config/report-templates-config.json
- [ ] DryRun mode implemented
- [ ] Error handling implemented
- [ ] Returns standardized result object
- [ ] Zero VS Code diagnostics errors
- [ ] Documentation updated

## Testing Plan
- [ ] Module imports successfully
- [ ] Type1 detection works correctly
- [ ] Type2 creates proper diff lists
- [ ] DryRun mode simulates without OS changes
- [ ] Full execution creates proper logs
- [ ] Execution logs saved to `temp_files/logs/[module]/`
- [ ] Reports include module section
- [ ] Error handling works as expected

## Documentation
- [ ] Add section to ADDING_NEW_MODULES.md
- [ ] Update README.md with module description
- [ ] Add inline code comments
- [ ] Update MODULE_DEVELOPMENT_GUIDE.md if needed

## Related Resources
- Link to MODULE_DEVELOPMENT_GUIDE.md
- Link to ADDING_NEW_MODULES.md
- Link to relevant Windows documentation
