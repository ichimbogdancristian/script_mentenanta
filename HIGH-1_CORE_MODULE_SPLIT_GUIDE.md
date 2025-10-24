# 🔧 **HIGH-1: Core Infrastructure Module Split Guide**

## 📊 **Project Status**

**Current State**: CoreInfrastructure.psm1 is 2,810 lines (after recent additions)  
**Target**: Split into 3 focused modules of ~600 lines each  
**Complexity**: High (cross-cutting concerns)

---

## 🎯 **Proposed Architecture**

### **Module 1: ConfigurationManager.psm1** (~600 lines)
**Purpose**: Configuration loading, parsing, and access  
**Functions to migrate**:
- `Initialize-ConfigSystem`
- `Get-MainConfig`
- `Get-MainConfigHashtable`
- `ConvertTo-HashtableDeep`
- `Get-BloatwareList`
- `Get-UnifiedEssentialAppsList`
- `Get-BloatwareConfiguration`
- `Get-EssentialAppsConfiguration`
- `Get-LoggingConfiguration`
- `Get-YourNewModuleConfiguration` (pattern for new modules)

**Dependencies**: None (standalone)  
**Exports**: 10 configuration-related functions

### **Module 2: LoggingSystem.psm1** (~600 lines)
**Purpose**: Logging, performance tracking, operation logging  
**Functions to migrate**:
- `Initialize-LoggingSystem`
- `Get-VerbositySetting`
- `Test-ShouldLogOperation`
- `Write-LogEntry` (existing)
- `Write-StructuredLogEntry` (existing)
- `Write-ModuleLogEntry` (new unified function)
- `Write-OperationStart`
- `Write-OperationSuccess`
- `Write-OperationFailure`
- `Write-OperationSkipped`
- `Write-DetectionLog`
- `Start-PerformanceTracking`
- `Complete-PerformanceTracking`

**Dependencies**: None (standalone)  
**Exports**: 13 logging-related functions

### **Module 3: FileOrganization.psm1** (~600 lines)
**Purpose**: File and directory management for session data  
**Functions to migrate**:
- `Initialize-FileOrganization`
- `Initialize-TempFilesStructure`
- `Validate-TempFilesStructure`
- `Initialize-ProcessedDataStructure`
- `Get-SessionPath`
- `Get-ProcessedDataPath`
- `Save-SessionData`
- `Get-SessionData`
- `Save-OrganizedFile`

**Dependencies**: None (standalone)  
**Exports**: 9 file organization functions

### **Refactored CoreInfrastructure.psm1** (~400 lines)
**Purpose**: Module orchestration and common utilities  
**Functions to keep**:
- `Initialize-GlobalPathDiscovery` (path system initialization)
- `Assert-AdminPrivilege`
- `New-ModuleExecutionResult` (standardized returns)
- `Compare-DetectedVsConfig` (core utility)

**Imports**: ConfigurationManager, LoggingSystem, FileOrganization  
**Exports**: 4 core functions + re-exports from sub-modules

---

## 📋 **Implementation Steps**

### **Phase 1: Create Sub-Modules (Manual Extraction)**

1. **Create ConfigurationManager.psm1**:
   - Copy ConfigurationManager template from `HIGH-1_TEMPLATES` folder
   - Extract functions from CoreInfrastructure.psm1 lines 270-450
   - Update function dependencies
   - Test: `Import-Module ConfigurationManager.psm1`

2. **Create LoggingSystem.psm1**:
   - Extract functions from CoreInfrastructure.psm1 lines 600-1400
   - Test: `Import-Module LoggingSystem.psm1`

3. **Create FileOrganization.psm1**:
   - Extract functions from CoreInfrastructure.psm1 lines 1450-2100
   - Test: `Import-Module FileOrganization.psm1`

### **Phase 2: Update Existing CoreInfrastructure**

1. Remove extracted functions
2. Add imports for new modules
3. Add re-export statements
4. Test module loads correctly

### **Phase 3: Update Dependent Modules**

1. Update Type1 modules to import ConfigurationManager if needed
2. Update Type2 modules (may need logging functions)
3. Update UserInterface.psm1 (uses logging)
4. Update ReportGenerator.psm1 (uses file organization)

### **Phase 4: Comprehensive Testing**

1. Import each new module standalone
2. Import CoreInfrastructure which imports all three
3. Test full orchestrator execution
4. Run DryRun on all modules

---

## 🔍 **Extraction Guidelines**

### **Do NOT Split These:**
- Global path discovery system
- Module result standardization
- Config comparison logic
- Admin privilege checks

### **DO Split These:**
- Configuration loading (each file type separate)
- Logging functions (text, structured, operation, performance)
- File organization utilities
- Session data management

### **Handle With Care:**
- Error handling patterns (maintain consistency)
- Performance tracking (may span modules)
- Global variable initialization
- Cross-module dependencies

---

## ✅ **Validation Checklist**

- [ ] Each new module has `#Requires -Version 7.0`
- [ ] Each new module has proper `Export-ModuleMember`
- [ ] Each module imports dependencies correctly
- [ ] Zero circular dependencies between modules
- [ ] All functions properly documented with XML comments
- [ ] CoreInfrastructure.psm1 reduced to <600 lines
- [ ] All 3 sub-modules approximately 600 lines each
- [ ] Backward compatibility maintained (re-exports in CoreInfrastructure)
- [ ] Tests pass with new module structure
- [ ] No increase in load time (lazy loading may improve it)

---

## 🚀 **Next Steps**

1. Review this guide with team
2. Create ConfigurationManager.psm1 template
3. Extract and test each module individually
4. Update all dependent modules
5. Full integration testing
6. Performance benchmarking

---

## 📚 **Related Files**

- `COMPREHENSIVE_TODO_LIST.md` - Master task list
- `IMPLEMENTATION_GUIDE.md` - Phase 1 & 2 (completed)
- `PROJECT_ANALYSIS_FINDINGS.md` - Architecture analysis
- `.github/copilot-instructions.md` - Architecture documentation

---

**Estimated Effort**: 6-8 hours  
**Risk Level**: Medium (high complexity, but well-scoped)  
**Priority**: High (improves maintainability significantly)
