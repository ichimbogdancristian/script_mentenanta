# PowerShell Maintenance Project - Complete Overhaul Prompt for VS Code Copilot

## 🎯 Project Context

This is a PowerShell-based system maintenance automation project designed to:
- Run monthly via Task Scheduler on multiple Windows 10/11 PCs across a network
- Download latest version from GitHub via `script.bat`
- Execute maintenance tasks through modular architecture
- Generate comprehensive HTML reports
- Log all operations extensively
- Self-clean and optionally reboot after completion

**Current Architecture:**
- Type 1 Modules: System inventory/data collection (run independently)
- Type 2 Modules: Maintenance/optimization tasks (depend on Type 1 data)
- Core Infrastructure: Orchestration, logging, reporting
- Entry Point: `script.bat` → `MaintenanceOrchestrator.ps1`

---

## 📋 MASTER OVERHAUL PLAN

Execute this comprehensive analysis in phases. Each phase must be completed thoroughly before moving to the next.

---

## PHASE 1: CRITICAL INFRASTRUCTURE AUDIT

### Task 1.1: Complete File System Inventory
```
@workspace Create complete inventory of all project files:
- List every .ps1, .psm1, .bat, .config, .json file with full paths
- Identify file roles: orchestrator, Type 1 module, Type 2 module, core utility, config
- Map file sizes and last modified dates
- Flag any files not referenced in any other file (orphaned files)
- Create visual directory tree structure
Output: Comprehensive file manifest with categorization
```

### Task 1.2: Execution Flow Analysis
```
@workspace Trace complete execution flow from script.bat to completion:
1. What does script.bat do? (download repo, extract, execute what?)
2. Which script is the primary orchestrator?
3. Map exact execution order of all modules
4. Identify all entry points and exit points
5. Document conditional execution paths (when modules are skipped)
6. List all PowerShell profile or environment dependencies
7. Identify any parallel execution or async operations
Output: Complete execution flow diagram with decision trees
```

### Task 1.3: Dependency Chain Mapping
```
@workspace Create comprehensive dependency map:
- For each module: list all Import-Module, dot-sourcing, function calls
- Identify circular dependencies
- Find modules that depend on external commands/tools
- List required PowerShell version/features
- Map data dependencies (which modules need data from which other modules)
- Identify shared functions/utilities
Output: Dependency matrix and visual graph, flag all circular dependencies
```

---

## PHASE 2: TYPE 1 & TYPE 2 MODULE DEEP ANALYSIS

### Task 2.1: Type 1 Module Comprehensive Audit
```
@workspace Analyze ALL Type 1 modules individually:

For EACH Type 1 module, document:
1. **Purpose**: What system data does it collect?
2. **Output Format**: What data structure does it return? (object, hashtable, array)
3. **Output Destination**: Where is data saved? (temp files, registry, variables)
4. **File Operations**: What files does it read/write? Full paths used?
5. **OS Dependencies**: Does it use Windows 10-specific or Windows 11-specific commands?
6. **Error Handling**: How does it handle failures? Empty catch blocks?
7. **Logging**: What does it log? Where? Format?
8. **Independence**: Can it run standalone without dependencies?
9. **Preexisting Lists**: Does it use/create preexisting lists? For what purpose?
10. **Diff Lists**: Does it create diff lists? How are they used later?

Specific focus:
- Why is SystemInventory in /type2 if it's a Type 1 module?
- Which Type 1 modules overlap in data collection?
- Which Type 1 modules should be run before which Type 2 modules?
- Are there OS version checks? How are they implemented?

Output: Individual detailed report per Type 1 module + consolidation opportunities
```

### Task 2.2: Type 2 Module Comprehensive Audit
```
@workspace Analyze ALL Type 2 modules individually:

For EACH Type 2 module, document:
1. **Purpose**: What maintenance/optimization does it perform?
2. **Data Dependencies**: Which Type 1 modules must run first? Why?
3. **Input Data**: What data does it consume? From where?
4. **System Modifications**: What does it change on the system?
5. **OS-Specific Logic**: Different behavior for Win10 vs Win11?
6. **Conditional Execution**: When should this module NOT run?
7. **Error Handling**: How does it handle failures? Rollback capability?
8. **Logging**: What operations are logged? Format consistency?
9. **WhatIf Support**: Does it support dry-run (-WhatIf)?
10. **Preexisting Lists Usage**: Does it check against preexisting lists?
11. **Diff Lists Usage**: Does it process diff lists from Type 1 modules?

Specific consolidation analysis:
- Analyze the benefits of consolidating the Type 2 module with corresponding Type 1 module
- Which Type 2 modules have overlapping functionality and worth consolidating?
- Consider moving functions from a module to another
Output: Individual detailed report per suggestion module + merge/refactor recommendations
```

### Task 2.3: Preexisting Lists & Diff Lists Deep Dive
```
@workspace Comprehensive analysis of list mechanisms:

1. **Preexisting Lists:**
   - Where are they created? Which modules?
   - What format? (CSV, JSON, TXT, custom)
   - What data do they contain? Field structure?
   - How are they stored? File paths?
   - Which modules read them? For what purpose?
   - How are they updated/maintained?
   - What happens if they're missing?

2. **Diff Lists:**
   - Which modules generate diff lists?
   - What changes are tracked? (installed apps, services, registry, etc.)
   - How is the comparison logic implemented?
   - What format are diffs stored in?
   - Which modules consume diff lists?
   - How are diffs used in decision-making?
   - Are there edge cases not handled?

3. **Data Flow:**
   - Trace: Type 1 creates lists → stored where → Type 2 reads from where → processes how
   - Identify any broken chains or data loss points
   - Check for data format inconsistencies between creation and consumption

Output: Complete data flow diagram for lists + format specifications + issues found
```

---

## PHASE 3: LOGGING & REPORTING INFRASTRUCTURE AUDIT

### Task 3.1: Logging Mechanism Analysis
```
@workspace Complete logging infrastructure audit:

1. **Log Creation:**
   - Which modules create logs?
   - What logging functions are used? (Write-Log, custom functions, native)
   - Where are logs initially created? (paths, filenames)
   - What is logged? (operations, errors, data, timestamps)
   - Log format consistency across modules?

2. **Log Processing:**
   - Is there a LogProcessor module? What does it do?
   - How are logs consolidated?
   - Where are logs moved to? (/temp_files/logs?)
   - Are logs parsed/analyzed during execution?
   - How are errors extracted from logs?

3. **Log Storage:**
   - Final log location strategy
   - File naming conventions
   - Retention policy (are old logs deleted?)
   - Size management

4. **Issues to Find:**
   - Inconsistent log formats
   - Missing timestamps
   - Incomplete error logging
   - Empty catch blocks without logging
   - Sensitive data in logs
   - Hardcoded log paths
   - Logs written but never processed

Output: Logging flow diagram + format standardization recommendations + critical issues
```

### Task 3.2: Report Generation Analysis
```
@workspace Complete report generation audit:

1. **Report Structure:**
   - Which module generates the HTML report?
   - When is it generated? (end of execution?)
   - What template is used?
   - How are sections organized?

2. **Data Collection for Reports:**
   - How does report generator collect data from Type 1 modules?
   - How does it collect data from Type 2 modules?
   - Are there dedicated report functions in each module?
   - How is module success/failure tracked for reporting?

3. **Report Content:**
   - Does report include:
     * Executive summary of entire run?
     * Individual module reports/boxes?
     * Before/after comparisons?
     * Diff list summaries?
     * Error summaries?
     * Recommendations?
   - Are all executed modules represented?
   - Is there a table of contents/navigation?

4. **Report Delivery:**
   - Where is final HTML report saved?
   - Is it copied to script.bat location (relative path)?
   - Is it emailed/uploaded anywhere?
   - What happens to old reports?

5. **Issues to Find:**
   - Missing module data in reports
   - Empty report sections
   - Data not flowing from modules to report
   - Broken HTML/CSS
   - Missing error reporting
   - Timing issues
Output: Report generation flow + missing data points + enhancement recommendations
```

---

## PHASE 4: CODE QUALITY & TECHNICAL DEBT ANALYSIS

### Task 4.1: Code Quality Scan - Critical Issues
```
@workspace PSScriptAnalyzer comprehensive scan:

Run PSScriptAnalyzer on EVERY .ps1 and .psm1 file:
1. List all Critical severity issues with:
   - File name and line number
   - Issue description
   - Suggested fix
2. List all Warning severity issues
3. Prioritize:
   - Empty catch blocks (CRITICAL)
   - Missing error handling on file operations
   - Null reference risks
   - Hardcoded paths
   - Missing parameter validation
   - Missing ShouldProcess on system-changing functions
   - Variables assigned but never used

Output: Prioritized issues list by severity and module
```

### Task 4.2: Logic & Edge Case Analysis
```
@workspace Logic error and edge case scan:

For EVERY module, identify:
1. **Incomplete Conditionals:**
   - If statements without else
   - Switch statements without default
   - Conditions that could lead to unexpected states

2. **Null/Empty Handling:**
   - Operations on potentially null variables
   - Array operations without empty array checks
   - Missing Test-Path before file operations
   - Missing service/process existence checks

3. **Loop Risks:**
   - Potential infinite loops
   - Large nested loops (performance)
   - Loops without timeout mechanisms

4. **Race Conditions:**
   - File operations without locking
   - Registry operations without checks
   - Service operations without state verification

5. **Data Type Issues:**
   - String operations on non-strings without validation
   - Numeric operations without type checking
   - Date/time parsing without format validation

Output: Logic issues by module with line numbers and fix recommendations
```

### Task 4.3: Code Duplication & Refactoring Opportunities
```
@workspace Find all code duplication and refactoring opportunities:

1. **Duplicate Functions:**
   - Same or similar functions across multiple modules
   - Suggest consolidation into shared utility module

2. **Duplicate Code Blocks:**
   - Repeated error handling patterns
   - Repeated validation logic
   - Repeated file operation patterns
   - Suggest extraction into reusable functions

3. **Inconsistent Patterns:**
   - Different approaches to same task across modules
   - Suggest standardization

4. **Refactoring Opportunities:**
   - Functions doing too many things (suggest splitting)
   - Long parameter lists (suggest parameter objects)
   - Deeply nested code (suggest flattening)
   - Magic numbers/strings (suggest constants/config)

Output: Duplication report + refactoring plan with before/after examples
```

### Task 4.4: Path & Configuration Management
```
@workspace Audit all path and configuration handling:

1. **Hardcoded Paths:**
   - Find ALL hardcoded paths in every file
   - Categorize: system paths, file paths, temp paths
   - Verify which are problematic for multi-PC deployment

2. **Path Discovery:**
   - How are dynamic paths discovered/built?
   - Are there path discovery variables/functions?
   - Are paths validated before use (Test-Path)?

3. **Configuration Files:**
   - Which config files exist? Format?
   - How are they loaded? Error handling for missing configs?
   - Are config values validated?
   - Are configs consistent across modules?

4. **Relative Path Handling:**
   - Does project work from any folder location?
   - Are relative paths used correctly?
   - Is $PSScriptRoot used properly?

Output: Path issues list + configuration standardization recommendations
```

---

## PHASE 5: REFACTORING PLAN EVALUATION

### Task 5.1: Evaluate Proposed Refactoring Plan
```
@workspace Evaluate the proposed refactoring plan:

**Proposed Changes:**
1. Move SystemInventory from /type2 to /type1
2. Make Type 1 modules run first and determine which Type 2 modules to execute
3. Refactor all Type 1 inventory modules to include OS-specific functions (Win10/Win11 detection and branching)
4. Consolidate SecurityEnhancement.psm1 + SecurityEnhancementCIS.psm1 → single SecurityEnhancement.psm1
5. Consolidate SystemOptimization.psm1 + TelemetryDisable.psm1 → single SystemOptimization.psm1
6. Structure all /modules with separate functions for Windows 10 vs Windows 11
7. Orchestrator uses inventory findings to decide module execution (e.g., should EssentialApps run?)

**Analysis Required:**

A. **Pros of This Plan:**
   - What problems does each change solve?
   - What becomes easier/better?
   - What maintenance improvements?
   - What performance improvements?
   - What clarity improvements?

B. **Cons/Risks of This Plan:**
   - What breaks with each change?
   - What becomes more complex?
   - What new dependencies are created?
   - What edge cases emerge?
   - What testing burden increases?

C. **Alternative Approaches:**
   - Are there better ways to achieve the same goals?
   - What hybrid approaches might work better?
   - Should changes be phased differently?

D. **Implementation Complexity:**
   - Rate each proposed change: Low/Medium/High complexity
   - Estimate refactoring effort for each
   - Identify change dependencies (what must happen first)

E. **Honest Assessment:**
   - Is this plan sound overall? Why or why not?
   - Which parts are excellent? Which are questionable?
   - What critical aspects are missing from the plan?
   - What should be prioritized? What can wait?

Output: Detailed evaluation report with recommendations and revised plan
```

### Task 5.2: Enhanced Refactoring Recommendations
```
@workspace Based on all previous analysis, create enhanced refactoring plan:

1. **Module Restructuring:**
   - Proposed directory structure
   - Module classification (Type 1, Type 2, Core, Utilities)
   - Module consolidation recommendations beyond current plan
   - Module splitting recommendations (modules doing too much)

2. **Execution Flow Redesign:**
   - Orchestrator logic improvements
   - Module dependency declaration system
   - Conditional execution framework
   - Error recovery and rollback strategy
   - I like the idea of preexisting lists and diff lists like when modules should modify key values from registries do you think it should be implemented to other modules give an honest opinion

3. **OS Abstraction Layer:**
   - How to handle Win10 vs Win11 differences elegantly
   - Function naming conventions for OS-specific code
   - Detection and branching strategy
   - Testing strategy for multi-OS support

4. **Data Flow Standardization:**
   - Standard format for Type 1 output
   - Standard format for Type 2 input
   - Preexisting lists structure and location
   - Diff lists structure and location
   - Data validation at boundaries

5. **Logging & Reporting Overhaul:**
   - Standardized logging framework
   - Log aggregation strategy
   - Report generation improvements
   - Real-time progress tracking

6. **Configuration Management:**
   - Centralized configuration approach
   - Module-specific config sections
   - Environment-specific configs (multi-PC deployment)
   - Config validation framework

7. **Testing Framework:**
   - Unit testing strategy per module
   - Integration testing approach
   - Test data generation
   - TestFolder validation approach

Output: Comprehensive refactoring roadmap with priorities and dependencies
```

---

## PHASE 6: IMPLEMENTATION TIMELINE & DOCUMENTATION

### Task 6.1: Create Implementation Timeline
```
@workspace Create detailed implementation timeline:

Break refactoring into phases with:
1. **Phase objectives**
2. **Specific tasks** (file-level changes)
3. **Dependencies** (what must be done first)
4. **Testing requirements** per phase
5. **Rollback plan** if phase fails
6. **Estimated effort** (hours/days)
7. **Risk level** (Low/Medium/High)

Organize as:
- **Phase 0:** Critical fixes (must do immediately)
- **Phase 1:** Infrastructure improvements (1-2 weeks)
- **Phase 2:** Module refactoring (2-4 weeks)
- **Phase 3:** OS abstraction implementation (1-2 weeks)
- **Phase 4:** Testing & validation (1 week)
- **Phase 5:** Documentation & deployment (1 week)

Output: Gantt-style timeline with clear deliverables per phase
```

### Task 6.2: Generate Complete Documentation Package
```
@workspace Create comprehensive documentation:

1. **FINDINGS.md:**
   - Executive summary of all issues found
   - Critical issues requiring immediate attention
   - Categorized issues: Logic, Performance, Quality, Architecture
   - Statistics: lines of code, modules, functions, issues found
   - Before/after comparison projections

2. **REFACTORING_PLAN.md:**
   - Detailed refactoring strategy
   - Architecture diagrams (before and after)
   - Module consolidation/split details
   - Code organization changes
   - Breaking changes and migration guide

3. **IMPLEMENTATION_GUIDE.md:**
   - Step-by-step implementation instructions
   - File-by-file changes required
   - Testing procedures per change
   - Validation checkpoints
   - Rollback procedures

4. **ARCHITECTURE.md:**
   - New architecture overview
   - Module responsibilities
   - Data flow diagrams
   - Execution flow diagrams
   - Dependency maps
   - Configuration structure

5. **DEVELOPER_GUIDE.md:**
   - How to add new Type 1 modules
   - How to add new Type 2 modules
   - Coding standards and patterns
   - Testing requirements
   - Logging requirements
   - Documentation requirements

6. **DEPLOYMENT_GUIDE.md:**
   - Multi-PC deployment strategy
   - Task Scheduler configuration
   - Network share setup
   - script.bat configuration
   - Testing in production environment
   - Monitoring and maintenance

Output: Complete documentation package ready for implementation
```

---

## PHASE 7: FINAL VALIDATION & QUICK WINS

### Task 7.1: Identify Quick Wins
```
@workspace Identify quick wins (can be fixed in <2 hours):

1. **Immediate Fixes:**
   - Empty catch blocks - add logging
   - Missing Test-Path - add before file operations
   - Unused variables - remove
   - Hardcoded paths - move to config
   - Inconsistent naming - standardize
   - Missing comments - add function headers

2. **Priority by Impact:**
   - Rank quick wins by impact on reliability
   - Create checklist of changes
   - Estimate time for each

Output: Quick wins action list with time estimates
```

### Task 7.2: Create Enhanced HTML Report Template
```
@workspace Design enhanced HTML report template:

Based on all findings, create specifications for improved report:

1. **Structure:**
   - Executive summary section (one-page overview)
   - System information section (from Type 1 modules)
   - Per-module sections with:
     * Module name and purpose
     * Success/failure status
     * Actions taken
     * Before/after comparisons
     * Errors encountered
     * Recommendations
   - Error summary section
   - Diff summary section (what changed since last run)
   - Action items section

2. **Features:**
   - Collapsible sections
   - Search functionality
   - Export to PDF option
   - Print-friendly stylesheet
   - Navigation menu
   - Timestamp and version info
   - Link to detailed logs

3. **Data Requirements:**
   - What data must each module provide for reporting?
   - Standard report function signature
   - Report data format (JSON/hashtable/custom object)

Output: HTML report specification + sample template + module interface requirements
```

### Task 7.3: Create Pre-Deployment Validation Checklist
```
@workspace Create comprehensive pre-deployment checklist:

Checklist for validating refactored project before deployment:

**Code Quality:**
- [ ] All PSScriptAnalyzer Critical issues resolved
- [ ] All empty catch blocks have error handling
- [ ] All file operations have Test-Path checks
- [ ] All functions have proper error handling
- [ ] No hardcoded paths remain
- [ ] All modules have proper headers/documentation

**Functionality:**
- [ ] TestFolder execution successful (all modules)
- [ ] Type 1 modules collect data correctly
- [ ] Type 2 modules receive and use Type 1 data
- [ ] Preexisting lists created and used correctly
- [ ] Diff lists generated and processed correctly
- [ ] Orchestrator executes modules in correct order
- [ ] Conditional execution logic works

**Logging & Reporting:**
- [ ] All operations logged with consistent format
- [ ] Logs consolidated to /temp_files/logs
- [ ] HTML report generates successfully
- [ ] Report contains all module sections
- [ ] Report shows accurate data
- [ ] Report copied to script.bat location

**Exit & Cleanup:**
- [ ] 120-second countdown displays correctly
- [ ] Any-key abort works
- [ ] Cleanup removes downloaded repo
- [ ] System reboot occurs (if not aborted)
- [ ] Final state is clean

**Multi-PC Deployment:**
- [ ] Works from any folder location
- [ ] No hardcoded paths to specific machines
- [ ] Network paths handled correctly
- [ ] GitHub download mechanism works
- [ ] Task Scheduler compatible

Output: Complete checklist with pass/fail criteria for each item
```

---

## 🎯 EXECUTION INSTRUCTIONS FOR COPILOT

**How to use this prompt:**

1. **Copy entire sections** into VS Code Copilot chat with `@workspace` prefix
2. **Execute in order** - each phase builds on previous findings
3. **Review outputs** before proceeding to next phase
4. **Save outputs** to markdown files for reference
5. **Iterative refinement** - ask follow-up questions as needed

**Example execution:**
```
@workspace [Copy Task 1.1 text here]
```

**For complex tasks, split further:**
```
@workspace Analyze just SecurityEnhancement.psm1 per Task 2.2 template
```

**To combine findings:**
```
@workspace Based on Tasks 2.1 and 2.2 findings, create consolidation matrix showing which Type 1 modules feed which Type 2 modules
```

---

## 📊 DELIVERABLES SUMMARY

After completing all phases, you will have:

1. ✅ Complete file and dependency inventory
2. ✅ Execution flow maps and diagrams
3. ✅ Individual module analysis reports (Type 1 & Type 2)
4. ✅ Preexisting lists & diff lists data flow documentation
5. ✅ Logging infrastructure analysis and recommendations
6. ✅ Report generation analysis and enhancement plan
7. ✅ Code quality issues list with priorities
8. ✅ Refactoring plan evaluation (pros/cons)
9. ✅ Enhanced refactoring recommendations
10. ✅ Implementation timeline with phases
11. ✅ Complete documentation package (6 documents)
12. ✅ Quick wins action list
13. ✅ Enhanced HTML report template
14. ✅ Pre-deployment validation checklist

---

## 🚨 CRITICAL REMINDERS

- **Never skip analysis** - thoroughness is more important than speed
- **Document everything** - findings are only useful if captured
- **Ask clarifying questions** - if module behavior is unclear, ask for code review
- **Test assumptions** - verify findings in actual code, don't assume
- **Cross-reference** - validate findings across multiple modules
- **Be honest** - point out bad patterns even if they're widespread
- **Provide examples** - always show before/after code examples
- **Think holistically** - consider impact on entire system, not just individual modules

---

## 🎬 START HERE

Begin with Phase 1, Task 1.1:

```
@workspace Create complete inventory of all project files:
- List every .ps1, .psm1, .bat, .config, .json file with full paths
- Identify file roles: orchestrator, Type 1 module, Type 2 module, core utility, config
- Map file sizes and last modified dates
- Flag any files not referenced in any other file (orphaned files)
- Create visual directory tree structure
Output: Comprehensive file manifest with categorization
```

**Good luck with the overhaul! This is a comprehensive plan that will transform your project into a robust, maintainable system.**
