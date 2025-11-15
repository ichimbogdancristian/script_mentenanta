# Standardization Reference Guide
**For Developers Contributing to Script Maintenance**

---

## Quick Reference: What to Do When...

### When Adding a New Feature

**DO:**
```powershell
# 1. Use standardized function template
function New-FeatureName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$RequiredParam,
        
        [Parameter(HelpMessage = "Optional parameter")]
        [ValidateSet('Option1', 'Option2')]
        [string]$OptionalParam = 'Option1'
    )
    
    try {
        Write-ActionLog -Action "Feature operation" -Status 'START' -Category "Category"
        
        # Validate preconditions
        if (-not (Test-Precondition)) { throw "Precondition failed" }
        
        # Main logic
        $result = Invoke-Operation
        
        Write-ActionLog -Action "Feature operation" -Status 'SUCCESS' -Category "Category"
        return @{ Success = $true; Payload = $result; Duration = ... }
    }
    catch {
        Write-ActionLog -Action "Feature operation" -Status 'FAILURE' -Details $_.Exception.Message -Category "Category"
        return @{ Success = $false; Error = $_.Exception.Message; Duration = ... }
    }
}

# 2. Add to task array if it's a maintenance task
$global:ScriptTasks += @{
    Name = 'FeatureName'
    Function = { New-FeatureName -RequiredParam "value" }
    Description = 'What this feature does'
}

# 3. Add corresponding config flag if optional
$global:Config.SkipFeatureName = $false  # Set to $true to disable
```

**DON'T:**
```powershell
# DON'T use Write-Host directly
Write-Host "Something happened"  # ✗

# DON'T return mixed types
return $result              # ✗ Caller doesn't know type

# DON'T ignore errors
$result = Invoke-Operation  # ✗ What if it fails?

# DON'T create duplicate functions
function Duplicate-Function { ... }  # ✗ Check if it exists first
```

---

### When Fixing a Bug

**DO:**
```powershell
# 1. Add Pester test that reproduces bug
# tests/Unit/bug-fix.tests.ps1
Describe "Bug fix for feature X" {
    It "should handle edge case Y correctly" {
        $result = Feature-X -Param "EdgeCaseValue"
        $result.Success | Should -Be $true
    }
}

# 2. Fix the function (use standardized error handling)
function Feature-X {
    try {
        # Fix logic here
        ...
        return @{ Success = $true; ... }
    }
    catch {
        Write-Log "Feature-X failed: $_" 'ERROR'
        return @{ Success = $false; Error = $_.Exception.Message; ... }
    }
}

# 3. Verify test passes
Invoke-Pester -Path "tests/Unit/bug-fix.tests.ps1"

# 4. Commit with detailed message
# "Fix: Feature-X now handles edge case Y correctly
#  - Added test case in tests/Unit/bug-fix.tests.ps1
#  - Updated Feature-X to validate input before processing
#  - Closes: #123"
```

**DON'T:**
```powershell
# DON'T fix without testing
# DON'T leave debug Write-Host statements
# DON'T modify multiple functions in one commit
# DON'T change unrelated code
```

---

### When Refactoring Code

**DO:**
```powershell
# 1. Create feature branch
git checkout -b refactor/function-consolidation

# 2. Before making changes:
#    - Understand what each version does
#    - Write tests to validate behavior
#    - Create backup

# 3. Use Git to track changes
git add -A
git commit -m "Consolidate duplicate Get-AppX functions
 - Kept canonical version from line 3288
 - Marked other versions as deprecated
 - All tests passing"

# 4. Create pull request for review
# Tag as [REFACTORING] - Low risk, high benefit

# 5. Merge to main after approval
```

**DON'T:**
```powershell
# DON'T refactor without tests
# DON'T change multiple things at once
# DON'T push directly to main
# DON'T skip testing on multiple Windows versions
```

---

### When Reviewing Someone's Code

**Check for:**
- ✅ Standardized error handling (try/catch with Write-ActionLog)
- ✅ Standard return type (@{ Success = bool; Error = string; ... })
- ✅ Parameter validation (types, ValidateSet, ValidatePattern)
- ✅ Proper logging (Write-Log with appropriate level)
- ✅ No duplicate functions (grep for name)
- ✅ Clear docstring (one per function)
- ✅ Tests added (Pester test file)
- ✅ No Write-Host (unless logging)
- ✅ No emoji in logs (unless config flag)
- ✅ Config flags wired to tasks

**Comment Template:**
```powershell
# For good code:
# "✓ Looks good! Proper error handling, clear docstring, test coverage."

# For issues:
# "⚠ Please standardize error handling - use Write-ActionLog before throwing"
# "⚠ Return type should be @{ Success = bool; Error = string; ... }"
# "⚠ Missing test coverage for this function"
```

---

## Standard Patterns by Scenario

### Pattern 1: Query/Detection Function

```powershell
function Get-SomethingBloatware {
    <#
    .SYNOPSIS
        Detect bloatware via [detection method]
    
    .DESCRIPTION
        Queries [source] for apps matching $BloatwareList patterns
        and returns array of detected apps.
    
    .OUTPUTS
        Array of @{ Name; Version; MatchedPattern; Source }
    #>
    [CmdletBinding()]
    param(
        [string[]]$BloatwarePatterns = @(),
        [string]$Context = "Detection"
    )
    
    try {
        Write-ActionLog -Action "Detecting bloatware via [source]" -Status 'START' -Category "Bloatware Detection"
        
        if ($BloatwarePatterns.Count -eq 0) {
            throw "Bloatware patterns list is empty"
        }
        
        # Query source
        $detected = @()
        foreach ($item in (Get-ItemsFromSource)) {
            if ($BloatwarePatterns | Where-Object { $item.Name -like $_ }) {
                $detected += @{
                    Name           = $item.Name
                    Version        = $item.Version
                    MatchedPattern = $_
                    Source         = "[source name]"
                }
            }
        }
        
        Write-ActionLog -Action "Detected bloatware" -Details "$($detected.Count) apps found" -Status 'SUCCESS' -Category "Bloatware Detection"
        
        return @{
            Success   = $true
            Payload   = $detected
            Duration  = $duration
            Error     = $null
            Status    = 'Completed'
        }
    }
    catch {
        Write-ActionLog -Action "Bloatware detection failed" -Details $_.Exception.Message -Status 'FAILURE' -Category "Bloatware Detection"
        Write-Log "Detailed error: $($_ | Format-List * | Out-String)" 'ERROR'
        
        return @{
            Success  = $false
            Error    = $_.Exception.Message
            Duration = $duration
            Payload  = @()
            Status   = 'Failed'
        }
    }
}
```

### Pattern 2: Installation/Removal Function

```powershell
function Install-ThingViaPackageManager {
    <#
    .SYNOPSIS
        Install app via package manager with fallback
    
    .DESCRIPTION
        Attempts installation via Winget first, then Chocolatey.
    
    .OUTPUTS
        @{ Success = bool; Error = string; Duration = double; ... }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidatePattern('^[a-zA-Z0-9._-]+$')]
        [string]$WingetId,
        
        [Parameter(Mandatory = $true)]
        [ValidatePattern('^[a-zA-Z0-9._-]+$')]
        [string]$ChocoId
    )
    
    $opStart = Get-Date
    
    try {
        Write-ActionLog -Action "Installing $WingetId" -Status 'START' -Category "Package Management"
        
        # Try Winget first
        if (Test-CommandAvailable 'winget') {
            Write-Log "Attempting installation via Winget" 'INFO'
            $result = Invoke-LoggedCommand -FilePath 'winget.exe' `
                -ArgumentList @('install', '--id', $WingetId, '--silent') `
                -Context "Installing $WingetId"
            
            if ($result.ExitCode -eq 0) {
                Write-ActionLog -Action "Installation successful" -Details "Winget: $WingetId" -Status 'SUCCESS' -Category "Package Management"
                return @{
                    Success  = $true
                    Duration = ((Get-Date) - $opStart).TotalSeconds
                    Started  = $opStart
                    Ended    = Get-Date
                    Status   = 'Completed'
                    Payload  = @{ Method = 'Winget'; AppId = $WingetId }
                }
            }
        }
        
        # Fallback to Chocolatey
        if (Test-CommandAvailable 'choco') {
            Write-Log "Winget failed; attempting Chocolatey" 'WARN'
            $result = Invoke-LoggedCommand -FilePath 'choco.exe' `
                -ArgumentList @('install', $ChocoId, '-y') `
                -Context "Installing $ChocoId"
            
            if ($result.ExitCode -eq 0) {
                Write-ActionLog -Action "Installation successful" -Details "Chocolatey: $ChocoId" -Status 'SUCCESS' -Category "Package Management"
                return @{
                    Success  = $true
                    Duration = ((Get-Date) - $opStart).TotalSeconds
                    Started  = $opStart
                    Ended    = Get-Date
                    Status   = 'Completed'
                    Payload  = @{ Method = 'Chocolatey'; AppId = $ChocoId }
                }
            }
        }
        
        # Both failed
        throw "Installation failed via all package managers"
    }
    catch {
        Write-ActionLog -Action "Installation failed" -Details $_.Exception.Message -Status 'FAILURE' -Category "Package Management"
        Write-Log "Installation error: $($_ | Format-List * | Out-String)" 'ERROR'
        
        return @{
            Success  = $false
            Error    = $_.Exception.Message
            Duration = ((Get-Date) - $opStart).TotalSeconds
            Started  = $opStart
            Ended    = Get-Date
            Status   = 'Failed'
            Payload  = $null
        }
    }
}
```

### Pattern 3: Registry Operation

```powershell
function Set-PrivacySetting {
    <#
    .SYNOPSIS
        Set privacy registry value with fallback
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SettingName,
        
        [Parameter(Mandatory = $true)]
        [ValidateSet('Enable', 'Disable')]
        [string]$Action
    )
    
    $opStart = Get-Date
    
    try {
        Write-ActionLog -Action "Setting $SettingName to $Action" -Status 'START' -Category "System Configuration"
        
        $value = if ($Action -eq 'Enable') { 1 } else { 0 }
        $primaryPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"
        $fallbackPath = "HKCU:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"
        
        # Test access first
        $access = Test-RegistryAccess -RegistryPath $primaryPath -CreatePath
        
        if ($access.Success) {
            $result = Set-RegistryValueSafely -RegistryPath $primaryPath `
                -ValueName "AllowTelemetry" -Value $value -ValueType "DWord" `
                -Description "$SettingName via $Action"
            
            if ($result.Success) {
                Write-ActionLog -Action "$SettingName set" -Details "Primary path: $primaryPath" -Status 'SUCCESS' -Category "System Configuration"
                return @{
                    Success  = $true
                    Duration = ((Get-Date) - $opStart).TotalSeconds
                    Payload  = @{ Path = $primaryPath; Value = $value }
                    Status   = 'Completed'
                }
            }
        }
        
        # Fallback to user registry
        Write-Log "Primary registry path failed; using fallback" 'WARN'
        $result = Set-RegistryValueSafely -RegistryPath $fallbackPath `
            -ValueName "AllowTelemetry" -Value $value -ValueType "DWord" `
            -Description "$SettingName via $Action (fallback)"
        
        if ($result.Success) {
            Write-ActionLog -Action "$SettingName set (fallback)" -Details "Fallback path: $fallbackPath" -Status 'SUCCESS' -Category "System Configuration"
            return @{
                Success  = $true
                Duration = ((Get-Date) - $opStart).TotalSeconds
                Payload  = @{ Path = $fallbackPath; Value = $value }
                Status   = 'Completed'
            }
        }
        
        throw "Could not set registry value via primary or fallback path"
    }
    catch {
        Write-ActionLog -Action "$SettingName failed" -Details $_.Exception.Message -Status 'FAILURE' -Category "System Configuration"
        return @{
            Success  = $false
            Error    = $_.Exception.Message
            Duration = ((Get-Date) - $opStart).TotalSeconds
            Status   = 'Failed'
        }
    }
}
```

---

## Logging Best Practices

### ✅ DO: Use Write-Log with Correct Level

```powershell
# For success
Write-Log "Operation completed successfully" 'SUCCESS'

# For warnings
Write-Log "Optional feature unavailable; skipping" 'WARN'

# For errors
Write-Log "Critical operation failed: $errorMsg" 'ERROR'

# For progress (sparingly)
Write-Log "Processing item 10 of 100" 'INFO'

# For debugging
Write-Log "Variable state: $($debugInfo | ConvertTo-Json)" 'DEBUG'
```

### ✅ DO: Log with Context

```powershell
Write-Log "Removed 15 bloatware apps in 12.3 seconds" 'SUCCESS'
Write-Log "Registry path does not exist: HKLM:\Path\To\Setting" 'WARN'
Write-Log "Winget failed with exit code 1; trying Chocolatey" 'WARN'
```

### ❌ DON'T: Log Verbatim Duplication

```powershell
# NO
Write-Log "✓ Task complete ✓"
Write-Log "Processing 30%... processing 40%... processing 50%..."  # Pollution
Write-Log "Item 1 of 100"
Write-Log "Item 2 of 100"
Write-Log "Item 3 of 100"  # Endless repetition

# YES
Write-Log "Starting task" 'INFO'
Show-OperationProgress -Activity "Processing items" -PercentComplete 30
# (progress bar shown; no log entry)
Write-Log "Task complete: processed 100 items in 45.2s" 'SUCCESS'
```

### ❌ DON'T: Mix Logging Styles

```powershell
# NO
Write-Log "✅ Task succeeded"  # Emoji shouldn't be in log
Write-Host "Important message"  # Use Write-Log instead
$variable | Out-String | Write-Output  # Unstructured

# YES
Write-Log "Task succeeded" 'SUCCESS'  # Emoji handled by Write-Log
Write-ActionLog -Action "Important message" -Status 'SUCCESS'  # Structured
Write-Log "Variable state: $variable" 'DEBUG'  # Structured logging
```

---

## Configuration Management

### Standard Config Structure

```powershell
$global:Config = @{
    # Task control flags (one per task)
    SkipBloatwareRemoval        = $false
    SkipEssentialApps           = $false
    SkipTelemetryDisable        = $false
    SkipWindowsUpdates          = $false
    SkipSystemHealthRepair      = $false
    SkipSecurityHardening       = $false
    
    # Custom app lists
    CustomBloatwareList         = @()  # Add app patterns user wants removed
    CustomEssentialApps         = @()  # Add apps user wants installed
    
    # Feature flags
    EnableEmoji                 = $false  # ASCII-safe for scheduled tasks
    EnableVerboseLogging        = $false  # Debug output
    AutoRestart                 = $false  # Automatic restart after updates
    
    # Merge strategy for custom apps
    MergeStrategy               = 'Union'  # 'Union' or 'Replace'
}
```

### When to Add Config Flag

✅ **DO add flag if:**
- Feature can be disabled/enabled
- User might want different behavior
- Task is optional

❌ **DON'T add flag if:**
- Feature is mandatory
- Task doesn't exist (orphaned flag)
- Flag is never checked in code

### Example: Wiring Config Flag to Task

```powershell
# In task array
@{
    Name = 'BloatwareRemoval'
    Function = {
        # Check config flag
        if ($global:Config.SkipBloatwareRemoval) {
            Write-Log "Skipped (per config)" 'INFO'
            return @{ Success = $true; Status = 'Skipped' }
        }
        
        # Execute task
        return (Remove-Bloatware)
    }
    Description = 'Remove known bloatware'
}
```

---

## Testing Guidelines

### Write Tests For:
- ✅ All public functions
- ✅ All parameter validation
- ✅ All error paths
- ✅ All return types
- ✅ Integration with other functions

### Test File Structure

```powershell
# tests/Unit/function-name.tests.ps1

Describe "Function-Name" {
    
    BeforeAll {
        # Setup (mock files, dependencies, etc.)
    }
    
    AfterAll {
        # Cleanup (remove temp files, etc.)
    }
    
    Context "Valid inputs" {
        It "should return success for valid input" {
            $result = Function-Name -ValidParam "value"
            $result.Success | Should -Be $true
        }
    }
    
    Context "Invalid inputs" {
        It "should fail on invalid parameter" {
            { Function-Name -InvalidParam "bad" } | Should -Throw
        }
    }
    
    Context "Error handling" {
        It "should handle exception gracefully" {
            Mock Get-Something { throw "Test error" }
            $result = Function-Name -Param "value"
            $result.Success | Should -Be $false
            $result.Error | Should -Match "error"
        }
    }
}
```

---

## Common Mistakes & Fixes

### Mistake 1: Inconsistent Return Types

```powershell
# BEFORE (❌ Inconsistent)
function Do-Something {
    if ($success) {
        return $true  # Boolean
    } else {
        return @{ Error = "Something" }  # Hashtable
    }
}

# AFTER (✅ Consistent)
function Do-Something {
    if ($success) {
        return @{ Success = $true; Error = $null }
    } else {
        return @{ Success = $false; Error = "Something" }
    }
}
```

### Mistake 2: Missing Error Handling

```powershell
# BEFORE (❌ Silent Failure)
function Install-App {
    Invoke-LoggedCommand -FilePath 'winget' -ArgumentList @('install', $AppId)
}

# AFTER (✅ Proper Error Handling)
function Install-App {
    try {
        $result = Invoke-LoggedCommand -FilePath 'winget' -ArgumentList @('install', $AppId)
        if ($result.ExitCode -ne 0) {
            throw "Installation failed with exit code $($result.ExitCode)"
        }
        return @{ Success = $true }
    }
    catch {
        Write-Log "Installation failed: $_" 'ERROR'
        return @{ Success = $false; Error = $_.Exception.Message }
    }
}
```

### Mistake 3: No Parameter Validation

```powershell
# BEFORE (❌ No Validation)
function Process-Apps {
    param($AppList, $Action)  # What type? What values?
    ...
}

# AFTER (✅ Validated)
function Process-Apps {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string[]]$AppList,
        
        [Parameter(Mandatory = $true)]
        [ValidateSet('Install', 'Remove', 'Update')]
        [string]$Action
    )
    ...
}
```

### Mistake 4: Emoji in Logs

```powershell
# BEFORE (❌ Scheduled Task Unfriendly)
Write-Log "✅ App installed successfully"

# AFTER (✅ ASCII-Safe)
Write-Log "App installed successfully" 'SUCCESS'
# (If $global:Config.EnableEmoji, emoji is added by Write-Log)
```

---

## Pre-Commit Checklist

Before committing code:

- [ ] No syntax errors: `powershell -NoProfile -Syntax script.ps1`
- [ ] Tests pass: `Invoke-Pester -Path .\tests\`
- [ ] No duplicate functions: `grep 'function Name' script.ps1 | wc -l` should return 1
- [ ] Logging consistent: No `Write-Host`, all logs via `Write-Log`/`Write-ActionLog`
- [ ] Error handling present: All functions have try/catch
- [ ] Return types standard: Check for @{ Success = bool; Error = ... }
- [ ] Parameters validated: Type checks and ValidateSet/Pattern
- [ ] Docstring complete: One per function, matches implementation
- [ ] No debug code left: No commented-out Write-Log lines
- [ ] Git message clear: Explains what & why

---

## Useful Commands

```powershell
# Find all function definitions
grep 'function ' script.ps1

# Find duplicates
grep 'function ' script.ps1 | sort | uniq -d

# Syntax check
powershell -NoProfile -Syntax script.ps1

# Run tests
Invoke-Pester -Path .\tests\ -OutputFormat Detailed

# Check code with PSScriptAnalyzer
Invoke-ScriptAnalyzer -Path script.ps1 -Recurse

# Count lines
(Get-Content script.ps1).Count

# Search for errors in logs
Select-String '\[ERROR\]' maintenance.log

# View recent changes
git log --oneline -20
```

---

## Support & Resources

- **Full audit:** See `standardization-audit.md`
- **Executive summary:** See `standardization-executive-summary.md`
- **Phase 1 tasks:** See `phase1-quick-wins.md`
- **Original findings:** See `project-findings.md`
- **Previous fixes:** See `project-recommendations.md`

---

## Questions?

1. **"What's the standard return object?"**
   ```powershell
   @{
       Success  = [bool]
       Error    = [string] or $null
       Duration = [double] seconds
       Started  = [datetime]
       Ended    = [datetime]
       Context  = [string]
       Payload  = [object] optional
       Status   = 'Completed' | 'Skipped' | 'Failed' | 'Partial'
   }
   ```

2. **"When should I use Write-Log vs. Write-ActionLog?"**
   - Use `Write-Log` for: General logging, progress, debug output
   - Use `Write-ActionLog` for: Task boundaries, major operations

3. **"Can I use emoji in logs?"**
   - Only if `$global:Config.EnableEmoji = $true`
   - Never hardcode emoji; let Write-Log decide

4. **"What if my function needs a unique return type?"**
   - Always include the standard fields (Success, Error, Duration, etc.)
   - Add your custom fields in Payload: `@{ Success = $true; Payload = @{ CustomData = $value } }`

---

*Last Updated: November 2025*  
*Standardization Roadmap v2025.1*
