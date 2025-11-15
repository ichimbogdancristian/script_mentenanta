# Standardization Action Plan - Phase 1 (Quick Wins)

**Duration:** 1 week (part-time) or 1-2 days (full-time)  
**Risk Level:** LOW  
**Impact:** High (30% file size reduction; foundation for future work)

---

## Week 1: Quick Wins Schedule

### Monday (2-3 hours) - Audit & Analysis
- [ ] Run duplicate function audit script
- [ ] Identify all duplicate comment blocks
- [ ] List orphaned config flags
- [ ] Document findings in spreadsheet

### Tuesday-Wednesday (4-6 hours) - Remove Duplicate Comments
- [ ] Create backup of script.ps1
- [ ] Remove all verbatim duplicate comment headers
- [ ] Keep only first docstring per function
- [ ] Verify script still runs (no logic changes)
- [ ] Measure new file size (target: ~30% reduction)

### Thursday (2-3 hours) - Clean Config
- [ ] Remove orphaned Skip* flags from $global:Config
- [ ] Document which flags are actually used
- [ ] Verify remaining flags map to active tasks
- [ ] Update config comments

### Friday (2-3 hours) - Consolidate & Extract
- [ ] Consolidate task array (keep only one $global:ScriptTasks)
- [ ] Create bloatware.psm1 module scaffold
- [ ] Begin moving Get-*Bloatware functions to module
- [ ] Test bloatware module loads correctly

---

## Day-by-Day Checklist

### Day 1: Morning - Audit

```powershell
# 1. Find duplicate functions
$functions = @{}
Get-Content script.ps1 | Select-String '^function ' | ForEach-Object {
    if ($_ -match 'function ([\w-]+)') {
        $name = $matches[1]
        if ($functions.ContainsKey($name)) {
            $functions[$name] += $_.LineNumber
        } else {
            $functions[$name] = @($_.LineNumber)
        }
    }
}

# 2. Report duplicates
$duplicates = $functions.GetEnumerator() | Where-Object { $_.Value.Count -gt 1 } | Sort-Object { $_.Value.Count } -Descending
$duplicates | Format-Table @{ n='Function'; e={ $_.Key } }, @{ n='Count'; e={ $_.Value.Count } }, @{ n='Lines'; e={ $_.Value -join ', ' } }

# Export to CSV
$duplicates | Export-Csv -Path ".\analysis\duplicates-audit.csv" -NoTypeInformation
```

**Expected Output:**
```
Function                            Count Lines
Install-WindowsUpdatesCompatible        4 3996, 4009, 8853, 8867
Get-ProvisionedAppxBloatware           3 3783, 3810, 3870
Write-CleanProgress                    2 1290, 1347
Get-AppxPackageCompatible              2 3288, 3301
... (40+ more)
```

**Deliverable:** `analysis/duplicates-audit.csv`

---

### Day 1-2: Morning-Afternoon - Remove Duplicate Comments

**Step 1: Identify Pattern**

```powershell
# Sample from lines 1850-1883 (3 identical comment blocks + function)
<# Block 1: "# Function: Get-RegistryUninstallBloatware" comment header #>
<# Block 2: Identical comment header #>
<# Block 3: Identical comment header #>
function Get-RegistryUninstallBloatware { ... }
```

**Step 2: Create Deduplication Script**

```powershell
# Remove lines that are exact duplicates of previous line
# Particularly: "# Function: [Name]" and doc comment blocks

function Remove-DuplicateCommentBlocks {
    param([string]$FilePath)
    
    $content = Get-Content $FilePath
    $cleaned = @()
    $lastLine = ""
    $skipCount = 0
    
    foreach ($line in $content) {
        # Skip lines that are exactly identical to previous line (duplicate comment)
        if ($line -eq $lastLine -and $line -match '^#') {
            $skipCount++
            continue  # Skip duplicate comment
        }
        
        $cleaned += $line
        $lastLine = $line
    }
    
    Write-Host "Removed $skipCount duplicate comment lines"
    return $cleaned | Out-String
}

# Apply transformation
$cleaned = Remove-DuplicateCommentBlocks -FilePath "script.ps1"
$cleaned | Out-File -FilePath "script.ps1.cleaned" -Force

# Verify syntax is still valid
powershell -NoProfile -Syntax "script.ps1.cleaned" -ErrorVariable syntaxErrors

if ($syntaxErrors.Count -eq 0) {
    Write-Host "✓ Syntax valid; swapping files"
    Move-Item "script.ps1" "script.ps1.backup" -Force
    Move-Item "script.ps1.cleaned" "script.ps1" -Force
    $originalSize = (Get-Item "script.ps1.backup").Length
    $newSize = (Get-Item "script.ps1").Length
    Write-Host "Size: $originalSize → $newSize ($(100*($originalSize-$newSize)/$originalSize)% reduction)"
} else {
    Write-Host "✗ Syntax error detected; keeping backup"
}
```

**Expected Reduction:** 2,000-3,000 lines (5-15% of file)

**Deliverable:** Cleaned script.ps1; backup saved

---

### Day 2-3: Afternoon - Audit Config Flags

```powershell
# 1. Extract all Skip* flags from $global:Config initialization
$configFlags = Get-Content script.ps1 | Select-String '\$global:Config\.' | Select-String 'Skip' | Sort-Object -Unique

# 2. List all active tasks
$taskLines = Get-Content script.ps1 | Select-String '@{\s*Name\s*=' | Select-String -Pattern "'(.*?)'" | ForEach-Object { $_.Matches[0].Groups[1].Value }

# 3. Cross-reference
$configFlags | ForEach-Object {
    $flag = $_
    if ($flag -match 'Skip(\w+)') {
        $taskName = $matches[1]
        $exists = $taskName -in $taskLines
        Write-Host "Config: $flag → Task: $taskName → $(if($exists) { '✓' } else { '✗ ORPHANED' })"
    }
}
```

**Expected Output:**
```
Config: SkipBloatwareRemoval → Task: BloatwareRemoval → ✓
Config: SkipEssentialApps → Task: EssentialApps → ✓
Config: SkipTelemetryDisable → Task: TelemetryDisable → ✓
Config: SkipTaskbarOptimization → Task: TaskbarOptimization → ✗ ORPHANED
Config: SkipDesktopBackground → Task: DesktopBackground → ✗ ORPHANED
Config: SkipSecurityHardening → Task: SecurityHardening → ✗ ORPHANED
Config: SkipPendingRestartCheck → Task: PendingRestartCheck → ✗ ORPHANED
Config: SkipSystemHealthRepair → Task: SystemHealthRepair → ✗ ORPHANED
```

**Deliverable:** `analysis/config-flag-audit.csv`

---

### Day 3: Morning - Remove Orphaned Flags

**Step 1: Identify Lines to Delete**

Find and remove these lines from $global:Config initialization:
- `SkipTaskbarOptimization = $false`
- `SkipDesktopBackground = $false`
- `SkipSecurityHardening = $false`
- `SkipPendingRestartCheck = $false`
- `SkipSystemHealthRepair = $false`
- (Any others from audit)

**Step 2: Update Script**

```powershell
# Search for each orphaned flag and remove the line
$orphanedFlags = @(
    'SkipTaskbarOptimization',
    'SkipDesktopBackground',
    'SkipSecurityHardening',
    'SkipPendingRestartCheck',
    'SkipSystemHealthRepair'
)

$content = Get-Content "script.ps1"
$cleaned = $content | Where-Object {
    # Keep line unless it contains an orphaned flag
    $line = $_
    -not ($orphanedFlags | Where-Object { $line -match $_ })
}

$cleaned | Out-File "script.ps1" -Force
```

**Step 3: Verify**

```powershell
# Confirm flags are gone
(Get-Content "script.ps1" | Select-String 'Skip') | Measure-Object
# Expected: only wired flags remain
```

**Deliverable:** script.ps1 with orphaned flags removed

---

### Day 4: Morning - Consolidate Task Array

**Problem:** Two different $global:ScriptTasks definitions exist (around lines 250-620 and 10440-10495)

**Step 1: Identify Both**

```powershell
# Find both task array definitions
$content = Get-Content "script.ps1"
$taskArrayLines = $content | Select-String '\$global:ScriptTasks\s*=' -All | ForEach-Object { $_.LineNumber }
# Expected: 2 line numbers

# Show each definition
$taskArrayLines | ForEach-Object {
    Write-Host "Task array at line $_"
    Get-Content "script.ps1" | Select-Object -Index ($_ - 1) -First 5
}
```

**Step 2: Compare**

```powershell
# Extract first array (lines ~250-550)
$array1Lines = 250..550
$array1 = $content[$array1Lines] | Out-String

# Extract second array (lines ~10440-10495)
$array2Lines = 10440..10495
$array2 = $content[$array2Lines] | Out-String

# List tasks in each
"Array 1:" + ($array1 | Select-String "Name = '" | ForEach-Object { $_ -match "Name = '(.*?)'" | Out-Null; $matches[1] } | Join-String -Separator ", ")
"Array 2:" + ($array2 | Select-String "Name = '" | ForEach-Object { $_ -match "Name = '(.*?)'" | Out-Null; $matches[1] } | Join-String -Separator ", ")
```

**Step 3: Decide Canonical Version**

Review both and decide which is authoritative (likely the second, active one):
- Tasks that should exist
- Proper task ordering
- Complete metadata

**Step 4: Delete Obsolete Version**

Remove the first (or second, depending on decision) task array definition entirely.

**Deliverable:** Single $global:ScriptTasks definition at one location

---

### Day 4-5: Afternoon - Extract Bloatware Module

**Step 1: Create Module Scaffold**

```powershell
# Create bloatware.psm1 module file
@"
<#
.SYNOPSIS
    Bloatware detection and removal functions

.DESCRIPTION
    Comprehensive bloatware discovery across 8 different sources:
    - AppX packages (UWP Store apps)
    - DISM provisioned packages
    - Registry uninstall keys (Win32)
    - Windows Capabilities
    - Package manager lists (Winget, Chocolatey)
    - Browser extensions
    - Context menu entries
    - Startup programs
    - And more...

.NOTES
    Module: bloatware.psm1
    Version: 2025.1
#>

# Require parent script context
#Requires -Version 7.0

# Import logging functions from parent
# (These will be available when parent script imports this module)

# ============================================
# Bloatware Detection Functions
# ============================================

# (Move all Get-*Bloatware functions here)

# ============================================
# Bloatware Removal Functions
# ============================================

# (Move Remove-Bloatware and related functions here)

Export-ModuleMember -Function @(
    'Get-AppXBloatware',
    'Get-WingetBloatware',
    'Get-ChocolateyBloatware',
    'Get-RegistryBloatware',
    'Get-BrowserExtensionsBloatware',
    'Get-ContextMenuBloatware',
    'Get-StartupProgramsBloatware',
    'Get-ProvisionedAppxBloatware',
    'Get-WindowsFeaturesBloatware',
    'Get-ServicesBloatware',
    'Get-ScheduledTasksBloatware',
    'Get-StartMenuBloatware',
    'Get-ComprehensiveBloatwareInventory',
    'Remove-Bloatware'
)
"@ | Out-File ".\bloatware.psm1" -Force

Write-Host "✓ Created bloatware.psm1 module scaffold"
```

**Step 2: Move Functions**

For each bloatware function:

1. Find all instances (using grep)
2. Select the canonical version
3. Copy to bloatware.psm1
4. Mark other versions as `## DEPRECATED - Moved to bloatware.psm1`

```powershell
# Example: Move Get-AppXBloatware

# Find all instances
$instanceLines = (Get-Content "script.ps1" | Select-String '^function Get-AppXBloatware' -All).LineNumber

# For each instance, decide canonical (usually the fuller one)
# Keep canonical, mark others as deprecated
foreach ($line in $instanceLines | Sort-Object -Descending | Select-Object -Skip 1) {
    # Replace with comment marker
    $content = Get-Content "script.ps1"
    $content[$line - 1] = "## DEPRECATED - Function moved to bloatware.psm1; see Get-AppXBloatware there"
    $content | Out-File "script.ps1" -Force
}
```

**Step 3: Update Script to Import Module**

At top of script.ps1, after loading logging functions:

```powershell
# Import bloatware module
Import-Module .\bloatware.psm1 -Force -ErrorAction Stop
```

**Step 4: Test**

```powershell
# Verify functions are still accessible
Get-Command Get-AppXBloatware
Get-Command Remove-Bloatware

# Verify they work
Get-AppXBloatware | Measure-Object  # Should return results
```

**Deliverable:** `bloatware.psm1` module with all bloatware functions; deprecated markers in script.ps1

---

## Success Criteria - Phase 1

- [ ] **File Size:** Reduced to ~8,500 lines (from 11,067; ~23% reduction)
  - [ ] Duplicate comments removed (saves ~2,000 lines)
  - [ ] Orphaned config flags removed
  - [ ] Dead code removed (optional)

- [ ] **Code Quality:** No functionality changes, but cleaner
  - [ ] Script still runs without errors
  - [ ] All tasks execute correctly
  - [ ] Logs still generated

- [ ] **Maintainability:** Foundation for Phase 2
  - [ ] Single task array definition
  - [ ] Config flags all wired to tasks
  - [ ] Bloatware module created
  - [ ] Duplicates audited and documented

- [ ] **Documentation:** Clear before/after artifacts
  - [ ] `analysis/duplicates-audit.csv` - All duplicate functions listed
  - [ ] `analysis/config-flag-audit.csv` - Config flag mapping
  - [ ] Git commit with detailed message explaining each change

---

## Execution Commands

**Save this as `run-phase1.ps1` for easy execution:**

```powershell
# Phase 1 Quick Wins Execution Script

Write-Host "=" * 60
Write-Host "PHASE 1: QUICK WINS - Standardization Audit"
Write-Host "=" * 60
Write-Host ""

# 1. Audit duplicates
Write-Host "[1/4] Running duplicate function audit..."
$functions = @{}
Get-Content script.ps1 | Select-String '^function ' | ForEach-Object {
    if ($_ -match 'function ([\w-]+)') {
        $name = $matches[1]
        if ($functions.ContainsKey($name)) { $functions[$name] += $_.LineNumber }
        else { $functions[$name] = @($_.LineNumber) }
    }
}
$duplicates = $functions.GetEnumerator() | Where-Object { $_.Value.Count -gt 1 }
$duplicates | Export-Csv "analysis/duplicates-audit.csv" -NoTypeInformation
Write-Host "✓ Found $($duplicates.Count) duplicate functions"
Write-Host "  Results: analysis/duplicates-audit.csv"
Write-Host ""

# 2. Audit config flags
Write-Host "[2/4] Running config flag audit..."
$orphaned = @()
$wired = 0
# ... (audit code here)
Write-Host "✓ Config audit complete"
Write-Host "  Results: analysis/config-flag-audit.csv"
Write-Host ""

# 3. Remove comment blocks (with backup)
Write-Host "[3/4] Removing duplicate comment blocks..."
$origSize = (Get-Item "script.ps1").Length
# ... (cleanup code here)
$newSize = (Get-Item "script.ps1").Length
$reduction = [Math]::Round(100 * ($origSize - $newSize) / $origSize, 1)
Write-Host "✓ Removed duplicate comments"
Write-Host "  Size: $origSize → $newSize bytes ($reduction% reduction)"
Write-Host ""

# 4. Create bloatware module
Write-Host "[4/4] Creating bloatware module scaffold..."
# ... (module creation code here)
Write-Host "✓ Bloatware module created: bloatware.psm1"
Write-Host ""

Write-Host "=" * 60
Write-Host "PHASE 1 COMPLETE"
Write-Host "=" * 60
Write-Host ""
Write-Host "Next steps:"
Write-Host "1. Review duplicates in analysis/duplicates-audit.csv"
Write-Host "2. Consolidate task array"
Write-Host "3. Remove orphaned config flags"
Write-Host "4. Test script execution"
Write-Host "5. Commit changes"
Write-Host ""
```

---

## Rollback Plan

If anything goes wrong:

```powershell
# 1. Restore backup
Copy-Item "script.ps1.backup" "script.ps1" -Force

# 2. Verify restoration
powershell -NoProfile -Syntax "script.ps1" 

# 3. Delete bloatware module (if created)
Remove-Item "bloatware.psm1" -Force -ErrorAction SilentlyContinue
```

---

## Estimated Timeline

| Task | Duration | Start | End |
|------|----------|-------|-----|
| Audit & analysis | 1 hour | Mon 9 AM | Mon 10 AM |
| Remove duplicate comments | 2 hours | Mon 10 AM | Mon 12 PM |
| Config flag audit | 1 hour | Tue 9 AM | Tue 10 AM |
| Remove orphaned flags | 1 hour | Tue 10 AM | Tue 11 AM |
| Consolidate task array | 1 hour | Wed 9 AM | Wed 10 AM |
| Create bloatware module | 2 hours | Wed 10 AM | Wed 12 PM |
| Testing & verification | 2 hours | Thu 9 AM | Thu 11 AM |
| Documentation & commit | 1 hour | Thu 11 AM | Thu 12 PM |
| **TOTAL** | **11 hours** | Mon 9 AM | Thu 12 PM |

---

## Key Wins After Phase 1

✅ **30% smaller file** (easier to work with)  
✅ **No duplicate comments** (cleaner diffs)  
✅ **Honest config** (no orphaned flags)  
✅ **Single task array** (no shadowing)  
✅ **Module foundation** (ready for Phase 2)  
✅ **Better understanding** of codebase structure  

---

## Questions During Execution?

1. **"Which version of duplicated function should I keep?"**
   - Usually the more complete/recent one
   - Check git history if available
   - Test both versions and keep the one that works

2. **"What if removing comments breaks something?"**
   - They don't; comments are non-functional
   - But test anyway to be safe

3. **"Can I skip the bloatware module creation?"**
   - Yes; it's the most complex part
   - Can be done in Phase 2 instead

4. **"How do I verify the script still works?"**
   - Run: `powershell -NoProfile -Syntax script.ps1` (syntax check)
   - Or manually run each task with `-WhatIf`

---

## Next: Phase 2 Preview

After Phase 1 completes successfully, Phase 2 will tackle:

- Complete deduplication (all 50+ functions)
- Error handling standardization
- Return type unification
- Parameter validation framework
- Progress tracking API

**Estimated:** 2-3 weeks (1 FTE) or 4-6 weeks (part-time)

See `standardization-audit.md` for full Phase 2 details.
