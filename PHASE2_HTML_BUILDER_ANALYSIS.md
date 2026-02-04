# Phase 2 Analysis: HTML Component Library Extraction

**Phase:** 2 of 4 - HTML Component Library  
**Date:** February 4, 2026  
**Status:** 🔄 Analysis Complete - Ready for Implementation  
**Prerequisites:** Phase 1 (TemplateEngine) Complete ✅

---

## Executive Summary

Phase 2 will extract ~1,000 lines of repetitive HTML generation code from ReportGenerator.psm1 into a dedicated HTMLBuilder.psm1 component library. This will reduce code duplication, improve maintainability, and enable consistent styling across all reports.

### Key Findings

📊 **HTML Generation Functions Identified:** 15 functions  
🔄 **Code Duplication:** ~700 lines of repeated HTML patterns  
🎯 **Extraction Target:** ~1,000 lines → HTMLBuilder (~600 lines)  
✅ **Net Reduction:** ~400 lines  
🔧 **Backward Compatibility:** 100% maintained

---

## Current State Analysis

### ReportGenerator.psm1 HTML Generation Functions

| Function                       | Lines | Purpose                       | Extraction Candidate                |
| ------------------------------ | ----- | ----------------------------- | ----------------------------------- |
| **Build-ModuleCard**           | ~100  | Generate module result card   | ✅ Extract to composite component   |
| **Build-ModuleDetailsSection** | ~130  | Generate module details list  | ✅ Extract to New-HtmlDetailList    |
| **Build-ModuleLogsSection**    | ~80   | Generate log entries display  | ✅ Extract to New-HtmlLogList       |
| **Build-ErrorAnalysis**        | ~150  | Generate error categorization | ✅ Extract to composite component   |
| **New-DashboardSection**       | ~85   | Generate 4-card dashboard     | ✅ Extract to New-DashboardCardGrid |
| **New-ModuleSection**          | ~100  | Generate module sections grid | ✅ Extract to composite component   |
| **New-SummarySection**         | ~60   | Generate execution summary    | ✅ Extract to composite component   |
| **New-MaintenanceLogSection**  | ~80   | Generate system changes log   | ✅ Extract to New-HtmlLogTable      |
| **New-OperationLogTable**      | ~110  | Generate operation log table  | ✅ Extract to New-HtmlTable         |
| **Status Badge Generation**    | ~40   | Inline status badge HTML      | ✅ Extract to New-HtmlStatusBadge   |
| **Card Generation**            | ~80   | Inline dashboard card HTML    | ✅ Extract to New-HtmlCard          |
| **Detail Item Generation**     | ~50   | Inline detail list items      | ✅ Extract to New-HtmlDetailItem    |
| **Log Entry Generation**       | ~45   | Inline log entry HTML         | ✅ Extract to New-HtmlLogEntry      |
| **Table Row Generation**       | ~30   | Inline table row HTML         | ✅ Extract to New-HtmlTableRow      |
| **Section Header Generation**  | ~20   | Inline section headers        | ✅ Extract to New-HtmlSectionHeader |

**Total Lines to Extract:** ~1,160 lines

---

## Code Duplication Analysis

### Pattern 1: Status Badges (7 occurrences, ~40 lines each)

**Current Implementation:**

```powershell
# In Build-ModuleDetailsSection
$statusBadgeClass = switch ($itemStatus.ToLower()) {
    'success' { 'success' }
    'removed' { 'success' }
    'installed' { 'success' }
    'warning' { 'warning' }
    'skipped' { 'warning' }
    'error' { 'error' }
    'failed' { 'error' }
    default { 'info' }
}
$detailsHtml += "<div class='detail-item-status'><span class='status-badge $statusBadgeClass'>$itemStatus</span></div>"
```

**Proposed Component:**

```powershell
function New-HtmlStatusBadge {
    param([string]$Status, [string]$Text)
    $class = Get-StatusClass -Status $Status
    return "<span class='status-badge $class'>$Text</span>"
}
```

**Savings:** ~280 lines → ~30 lines = **-250 lines**

---

### Pattern 2: Dashboard Cards (4 occurrences, ~80 lines each)

**Current Implementation:**

```powershell
# In New-DashboardSection
$html.AppendLine(@"
    <div class="dashboard-card $healthClass">
        <div class="card-icon">🏥</div>
        <h3>System Health</h3>
        <div class="card-value">$healthScore</div>
        <p class="card-description">Overall system health score</p>
    </div>
"@)
```

**Proposed Component:**

```powershell
function New-HtmlCard {
    param(
        [string]$Title,
        [string]$Value,
        [string]$Description,
        [string]$Icon,
        [string]$StatusClass
    )
    return @"
<div class="dashboard-card $StatusClass">
    <div class="card-icon">$Icon</div>
    <h3>$Title</h3>
    <div class="card-value">$Value</div>
    <p class="card-description">$Description</p>
</div>
"@
}
```

**Savings:** ~320 lines → ~60 lines = **-260 lines**

---

### Pattern 3: Detail Items (2 occurrences, ~50 lines each)

**Current Implementation:**

```powershell
# In Build-ModuleDetailsSection
$detailsHtml += '<div class="detail-item">'
$detailsHtml += '<div class="detail-item-icon">📄</div>'
$detailsHtml += '<div class="detail-item-content">'
$detailsHtml += "<div class='detail-item-name'>$itemName</div>"
if ($item.Version) {
    $detailsHtml += "<div class='detail-item-description'>Version: $($item.Version)</div>"
}
$detailsHtml += '</div>'
$detailsHtml += "<div class='detail-item-status'><span class='status-badge $statusBadgeClass'>$itemStatus</span></div>"
$detailsHtml += '</div>'
```

**Proposed Component:**

```powershell
function New-HtmlDetailItem {
    param(
        [string]$Name,
        [string]$Description,
        [string]$Icon = '📄',
        [string]$Status,
        [hashtable]$Metadata
    )
    # Component handles all HTML generation and conditional display
}
```

**Savings:** ~100 lines → ~30 lines = **-70 lines**

---

### Pattern 4: Log Entries (2 occurrences, ~45 lines each)

**Current Implementation:**

```powershell
# In Build-ModuleLogsSection
$logsHtml += "<div class='log-entry $level'>"
$logsHtml += "<div class='log-timestamp'>$timestamp</div>"
$logsHtml += "<div class='log-level-icon'>$levelIcon</div>"
$logsHtml += "<div class='log-message'>$message</div>"
$logsHtml += '</div>'
```

**Proposed Component:**

```powershell
function New-HtmlLogEntry {
    param(
        [string]$Level,
        [string]$Message,
        [datetime]$Timestamp,
        [string]$Component
    )
    # Component handles icon selection, timestamp formatting, CSS class
}
```

**Savings:** ~90 lines → ~25 lines = **-65 lines**

---

### Pattern 5: Tables (3 occurrences, ~110 lines each)

**Current Implementation:**

```powershell
# In New-OperationLogTable
$tableHtml = @"
<table class="data-table">
    <thead>
        <tr>
            <th>Module</th>
            <th>Status</th>
            <th>Duration</th>
        </tr>
    </thead>
    <tbody>
"@

foreach ($row in $data) {
    $tableHtml += "<tr><td>$($row.Module)</td><td>$($row.Status)</td><td>$($row.Duration)</td></tr>"
}

$tableHtml += @"
    </tbody>
</table>
"@
```

**Proposed Component:**

```powershell
function New-HtmlTable {
    param(
        [string[]]$Headers,
        [PSCustomObject[]]$Rows,
        [string]$CssClass = 'data-table',
        [switch]$Sortable,
        [switch]$Striped
    )
    # Component handles headers, rows, CSS classes, sorting attributes
}
```

**Savings:** ~330 lines → ~80 lines = **-250 lines**

---

## Proposed HTMLBuilder Module Structure

### Core Components (8 functions)

```powershell
HTMLBuilder.psm1

#region Core Components

function New-HtmlCard {
    <#
    .SYNOPSIS Creates styled card with title, value, description, icon
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Title,

        [Parameter()]
        [string]$Value,

        [Parameter()]
        [string]$Description,

        [Parameter()]
        [string]$Icon,

        [Parameter()]
        [ValidateSet('success', 'warning', 'error', 'info', '')]
        [string]$StatusClass = ''
    )
    # Implementation: ~40 lines
}

function New-HtmlTable {
    <#
    .SYNOPSIS Creates data table with headers and rows
    #>
    param(
        [Parameter(Mandatory)]
        [string[]]$Headers,

        [Parameter(Mandatory)]
        [PSCustomObject[]]$Rows,

        [Parameter()]
        [string]$CssClass = 'data-table',

        [Parameter()]
        [switch]$Sortable,

        [Parameter()]
        [switch]$Striped,

        [Parameter()]
        [switch]$Hoverable
    )
    # Implementation: ~80 lines
}

function New-HtmlSection {
    <#
    .SYNOPSIS Creates content section with header and body
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Title,

        [Parameter(Mandatory)]
        [string]$Content,

        [Parameter()]
        [string]$Icon,

        [Parameter()]
        [switch]$Collapsible,

        [Parameter()]
        [string]$Id
    )
    # Implementation: ~50 lines
}

function New-HtmlStatusBadge {
    <#
    .SYNOPSIS Creates status indicator badge
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Status,

        [Parameter()]
        [string]$Text,

        [Parameter()]
        [ValidateSet('pill', 'square', 'rounded')]
        [string]$Style = 'pill'
    )
    # Implementation: ~30 lines
}

function New-HtmlDetailItem {
    <#
    .SYNOPSIS Creates detail list item with icon, name, description, status
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter()]
        [string]$Description,

        [Parameter()]
        [string]$Icon = '📄',

        [Parameter()]
        [string]$Status,

        [Parameter()]
        [hashtable]$Metadata
    )
    # Implementation: ~60 lines
}

function New-HtmlLogEntry {
    <#
    .SYNOPSIS Creates log entry with timestamp, level icon, message
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [Parameter()]
        [ValidateSet('success', 'info', 'warning', 'error', 'debug')]
        [string]$Level = 'info',

        [Parameter()]
        [datetime]$Timestamp = (Get-Date),

        [Parameter()]
        [string]$Component
    )
    # Implementation: ~40 lines
}

function New-HtmlMetric {
    <#
    .SYNOPSIS Creates metric display with label and value
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Label,

        [Parameter(Mandatory)]
        [string]$Value,

        [Parameter()]
        [string]$Unit,

        [Parameter()]
        [string]$Icon,

        [Parameter()]
        [string]$TrendIndicator  # '↑', '↓', '→'
    )
    # Implementation: ~35 lines
}

function New-HtmlIcon {
    <#
    .SYNOPSIS Creates icon element (emoji or font icon)
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Icon,

        [Parameter()]
        [string]$Size = 'md',

        [Parameter()]
        [string]$Color
    )
    # Implementation: ~20 lines
}

#endregion

#region Composite Components

function New-DashboardCardGrid {
    <#
    .SYNOPSIS Creates 4-card dashboard grid with system metrics
    #>
    param(
        [Parameter(Mandatory)]
        [hashtable]$Metrics
    )
    # Uses: New-HtmlCard (4x)
    # Implementation: ~70 lines
}

function New-ModuleDetailsCard {
    <#
    .SYNOPSIS Creates module result card with details and logs
    #>
    param(
        [Parameter(Mandatory)]
        [PSObject]$ModuleResult,

        [Parameter()]
        [string]$CardTemplate
    )
    # Uses: New-HtmlDetailItem, New-HtmlLogEntry, New-HtmlStatusBadge
    # Implementation: ~100 lines
}

function New-ExecutionLogTable {
    <#
    .SYNOPSIS Creates execution log table with operation results
    #>
    param(
        [Parameter(Mandatory)]
        [PSCustomObject[]]$Operations
    )
    # Uses: New-HtmlTable, New-HtmlStatusBadge
    # Implementation: ~60 lines
}

function New-ErrorAnalysisSection {
    <#
    .SYNOPSIS Creates error categorization section (critical/error/warning)
    #>
    param(
        [Parameter(Mandatory)]
        [hashtable]$AggregatedResults
    )
    # Uses: New-HtmlSection, New-HtmlDetailItem
    # Implementation: ~120 lines
}

#endregion

#region Utilities

function Get-StatusClass {
    <#
    .SYNOPSIS Maps status strings to CSS classes
    #>
    param([string]$Status)
    # Implementation: ~20 lines
}

function Format-Duration {
    <#
    .SYNOPSIS Formats seconds to readable duration (5.2s, 1m 30s, 2h 15m)
    #>
    param([double]$Seconds)
    # Implementation: ~30 lines
}

function Format-FileSize {
    <#
    .SYNOPSIS Formats bytes to readable size (KB, MB, GB)
    #>
    param([long]$Bytes)
    # Implementation: ~25 lines
}

function Escape-HtmlContent {
    <#
    .SYNOPSIS HTML-escapes user input for safe display
    #>
    param([string]$Content)
    # Implementation: ~15 lines
}

function Get-LevelIcon {
    <#
    .SYNOPSIS Returns emoji icon for log level
    #>
    param([string]$Level)
    # Implementation: ~15 lines
}

#endregion
```

**Total Estimated Lines:** ~600 lines (including documentation)

---

## Implementation Plan

### Phase 2.1: Create Core Components ✅ (This Step)

**Timeline:** 2-3 hours  
**Risk:** Low

**Tasks:**

1. Create `HTMLBuilder.psm1` skeleton with module header
2. Implement 8 core components:
   - New-HtmlCard
   - New-HtmlTable
   - New-HtmlSection
   - New-HtmlStatusBadge
   - New-HtmlDetailItem
   - New-HtmlLogEntry
   - New-HtmlMetric
   - New-HtmlIcon
3. Implement 5 utility functions:
   - Get-StatusClass
   - Format-Duration
   - Format-FileSize
   - Escape-HtmlContent
   - Get-LevelIcon
4. Add comprehensive documentation and examples

**Deliverable:** `modules/core/HTMLBuilder.psm1` (~350 lines)

---

### Phase 2.2: Create Composite Components

**Timeline:** 2-3 hours  
**Risk:** Low

**Tasks:**

1. Implement 4 composite components using core components:
   - New-DashboardCardGrid
   - New-ModuleDetailsCard
   - New-ExecutionLogTable
   - New-ErrorAnalysisSection
2. Test component composition
3. Validate HTML output matches current format

**Deliverable:** Updated `HTMLBuilder.psm1` (~600 lines total)

---

### Phase 2.3: Update ReportGenerator

**Timeline:** 3-4 hours  
**Risk:** Medium (HTML structure changes)

**Tasks:**

1. Import HTMLBuilder module in ReportGenerator
2. Replace HTML generation in **Build-ModuleCard** (~100 lines → ~30 lines)
3. Replace HTML generation in **Build-ModuleDetailsSection** (~130 lines → ~40 lines)
4. Replace HTML generation in **Build-ModuleLogsSection** (~80 lines → ~25 lines)
5. Replace HTML generation in **Build-ErrorAnalysis** (~150 lines → ~50 lines)
6. Replace HTML generation in **New-DashboardSection** (~85 lines → ~20 lines)
7. Replace HTML generation in **New-ModuleSection** (~100 lines → ~30 lines)
8. Replace HTML generation in **New-SummarySection** (~60 lines → ~20 lines)
9. Replace HTML generation in **New-MaintenanceLogSection** (~80 lines → ~25 lines)
10. Replace HTML generation in **New-OperationLogTable** (~110 lines → ~30 lines)
11. Test report generation end-to-end
12. Visual regression testing

**Deliverable:** Updated `ReportGenerator.psm1` (~3,300 lines, -1,000 lines)

---

### Phase 2.4: Create Test Suite

**Timeline:** 3-4 hours  
**Risk:** Low

**Tasks:**

1. Create `Test-HTMLBuilder.ps1` with ~40 test cases:
   - Core component tests (8 × 3 tests = 24)
   - Composite component tests (4 × 3 tests = 12)
   - Utility function tests (5 × 2 tests = 10)
   - Integration tests with ReportGenerator (4 tests)
2. Visual regression testing (compare HTML output before/after)
3. Run full test suite
4. Validate 100% pass rate

**Deliverable:** `Test-HTMLBuilder.ps1` (~1,200 lines)

---

### Phase 2.5: Documentation

**Timeline:** 1-2 hours  
**Risk:** Low

**Tasks:**

1. Update `.github/copilot-instructions.md` with HTMLBuilder patterns
2. Create `PHASE2_HTML_BUILDER_SUMMARY.md` with:
   - Implementation details
   - Before/after code comparisons
   - Usage examples
   - Migration guide
3. Update module documentation

**Deliverable:** Documentation files

---

## Expected Outcomes

### Code Metrics

**Before Phase 2:**

```
ReportGenerator.psm1:  ~4,293 lines (48 functions)
HTMLBuilder.psm1:      -
Total:                 4,293 lines
```

**After Phase 2:**

```
ReportGenerator.psm1:  ~3,293 lines (48 functions)  [-1,000 lines, -23%]
HTMLBuilder.psm1:      ~600 lines (17 functions)    [+600 lines, NEW]
Total:                 3,893 lines                   [-400 lines net, -9%]
```

### Quality Improvements

- **Code Duplication:** -700 lines (15% → 8%)
- **Modularity:** +100% (HTML generation self-contained)
- **Testability:** +100% (components independently testable)
- **Maintainability:** +60% (single source of truth for HTML patterns)
- **Reusability:** Components usable for new report types

### Backward Compatibility

✅ **100% maintained** - All existing reports generate identical HTML

---

## Risk Assessment

| Risk                                       | Probability | Impact | Mitigation                               |
| ------------------------------------------ | ----------- | ------ | ---------------------------------------- |
| HTML structure changes break styling       | Low         | High   | Visual regression testing                |
| Component abstraction increases complexity | Medium      | Low    | Comprehensive documentation and examples |
| Performance degradation                    | Very Low    | Low    | Benchmark report generation time         |
| Breaking changes to existing code          | Very Low    | High   | Extensive integration testing            |

---

## Success Criteria

✅ **All 40 test cases passing** (100%)  
✅ **Visual regression tests pass** (HTML identical)  
✅ **Performance maintained** (report generation time ±5%)  
✅ **Backward compatibility** (100%)  
✅ **Code reduction** (≥900 lines from ReportGenerator)  
✅ **Documentation complete** (patterns, examples, migration guide)

---

## Appendix A: Component Usage Examples

### Example 1: Dashboard Card Grid

**Before (85 lines):**

```powershell
function New-DashboardSection {
    $html = [System.Text.StringBuilder]::new()
    $html.AppendLine('<div class="dashboard">')
    # ... 80 lines of HTML generation
    return $html.ToString()
}
```

**After (20 lines):**

```powershell
function New-DashboardSection {
    param([hashtable]$Metrics)

    return New-DashboardCardGrid -Metrics @{
        HealthScore = $Metrics.OverallHealthScore
        SecurityScore = $Metrics.SecurityScore
        SuccessRate = $Metrics.SuccessRate
        TotalTasks = $Metrics.TotalTasks
    }
}
```

### Example 2: Module Card

**Before (100 lines):**

```powershell
function Build-ModuleCard {
    $cardHtml = $CardTemplate
    $cardHtml = $cardHtml -replace '\{\{MODULE_ICON\}\}', $info.Icon
    # ... 95 lines of placeholder replacement and HTML generation
    return $cardHtml
}
```

**After (30 lines):**

```powershell
function Build-ModuleCard {
    param([PSObject]$ModuleResult)

    $details = New-ModuleDetailsCard -ModuleResult $ModuleResult
    return $details
}
```

### Example 3: Status Badge

**Before (repeated 7× across functions):**

```powershell
$statusBadgeClass = switch ($itemStatus.ToLower()) {
    'success' { 'success' }
    'warning' { 'warning' }
    'error' { 'error' }
    default { 'info' }
}
$detailsHtml += "<span class='status-badge $statusBadgeClass'>$itemStatus</span>"
```

**After (single call):**

```powershell
$badge = New-HtmlStatusBadge -Status $itemStatus
$detailsHtml += $badge
```

---

## Appendix B: Test Suite Structure

```powershell
Test-HTMLBuilder.ps1

#region Core Component Tests (24 tests)

Describe "New-HtmlCard" {
    It "Creates card with all parameters" { }
    It "Handles missing optional parameters" { }
    It "Applies correct status class" { }
}

Describe "New-HtmlTable" {
    It "Creates table with headers and rows" { }
    It "Supports sortable attribute" { }
    It "Handles empty rows" { }
}

# ... (8 components × 3 tests each)

#endregion

#region Composite Component Tests (12 tests)

Describe "New-DashboardCardGrid" {
    It "Creates 4-card grid" { }
    It "Applies correct CSS classes" { }
    It "Handles missing metrics" { }
}

# ... (4 composites × 3 tests each)

#endregion

#region Utility Function Tests (10 tests)

Describe "Get-StatusClass" {
    It "Maps success statuses correctly" { }
    It "Maps error statuses correctly" { }
}

Describe "Format-Duration" {
    It "Formats seconds correctly" { }
    It "Formats minutes correctly" { }
}

# ... (5 utilities × 2 tests each)

#endregion

#region Integration Tests (4 tests)

Describe "ReportGenerator Integration" {
    It "Generate report with HTMLBuilder components" { }
    It "HTML output matches previous version" { }
    It "All placeholders replaced" { }
    It "CSS classes applied correctly" { }
}

#endregion
```

---

**Document Version:** 1.0  
**Last Updated:** February 4, 2026  
**Author:** Bogdan Ichim  
**Status:** 📋 Analysis Complete - Ready for Phase 2.1 Implementation
