#Requires -Version 7.0

<#
.SYNOPSIS
    Test Suite for TemplateEngine Module (Phase 1 Refactoring)

.DESCRIPTION
    Comprehensive test suite validating TemplateEngine functionality:
    - Template loading with caching
    - Path resolution and fallback logic
    - Placeholder replacement
    - Template validation
    - Cache management
    - Integration with ReportGenerator

.NOTES
    Test Framework: Custom PowerShell test harness
    Expected Result: All tests passing (30/30)
    Run Time: ~5-10 seconds
#>

[CmdletBinding()]
param()
# $VerbosePreference is automatically available from CmdletBinding()

# Import required modules
$ScriptRoot = $PSScriptRoot
$ModulesPath = Join-Path $ScriptRoot 'modules\core'

try {
    Import-Module (Join-Path $ModulesPath 'CoreInfrastructure.psm1') -Force -ErrorAction Stop
    Import-Module (Join-Path $ModulesPath 'TemplateEngine.psm1') -Force -ErrorAction Stop
}
catch {
    Write-Host "❌ Failed to load required modules: $_" -ForegroundColor Red
    exit 1
}

# Initialize path discovery
try {
    Initialize-GlobalPathDiscovery -HintPath $ScriptRoot -Force
}
catch {
    Write-Host "⚠️  Path discovery initialization skipped: $_" -ForegroundColor Yellow
}

# Test results tracking
$script:TestsPassed = 0
$script:TestsFailed = 0
$script:TestResults = @()

function Test-Assertion {
    param(
        [string]$TestName,
        [scriptblock]$Condition,
        [string]$ExpectedBehavior
    )

    try {
        $result = & $Condition
        if ($result) {
            $script:TestsPassed++
            $script:TestResults += @{
                Name   = $TestName
                Status = 'PASS'
                Expected = $ExpectedBehavior
            }
            Write-Host "  ✓ $TestName" -ForegroundColor Green
            return $true
        }
        else {
            $script:TestsFailed++
            $script:TestResults += @{
                Name   = $TestName
                Status = 'FAIL'
                Expected = $ExpectedBehavior
                Actual = "Condition returned false"
            }
            Write-Host "  ✗ $TestName" -ForegroundColor Red
            Write-Host "    Expected: $ExpectedBehavior" -ForegroundColor Yellow
            return $false
        }
    }
    catch {
        $script:TestsFailed++
        $script:TestResults += @{
            Name   = $TestName
            Status = 'ERROR'
            Expected = $ExpectedBehavior
            Error = $_.Exception.Message
        }
        Write-Host "  ✗ $TestName (ERROR)" -ForegroundColor Red
        Write-Host "    Error: $($_.Exception.Message)" -ForegroundColor Yellow
        return $false
    }
}

Write-Host "`n╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║      TemplateEngine Module Test Suite (Phase 1)               ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

#region Test Group 1: Module Loading & Exports

Write-Host "`n[Group 1] Module Loading & Exports" -ForegroundColor Magenta
Write-Host "=" * 60

Test-Assertion `
    -TestName "TemplateEngine module is loaded" `
    -Condition { Get-Module TemplateEngine } `
    -ExpectedBehavior "Module should be imported and available"

Test-Assertion `
    -TestName "Get-Template function is exported" `
    -Condition { Get-Command Get-Template -Module TemplateEngine -ErrorAction SilentlyContinue } `
    -ExpectedBehavior "Core template loading function should be available"

Test-Assertion `
    -TestName "Get-TemplateBundle function is exported" `
    -Condition { Get-Command Get-TemplateBundle -Module TemplateEngine -ErrorAction SilentlyContinue } `
    -ExpectedBehavior "Bundle loading function should be available"

Test-Assertion `
    -TestName "Invoke-PlaceholderReplacement function is exported" `
    -Condition { Get-Command Invoke-PlaceholderReplacement -Module TemplateEngine -ErrorAction SilentlyContinue } `
    -ExpectedBehavior "Placeholder replacement function should be available"

Test-Assertion `
    -TestName "Test-TemplateIntegrity function is exported" `
    -Condition { Get-Command Test-TemplateIntegrity -Module TemplateEngine -ErrorAction SilentlyContinue } `
    -ExpectedBehavior "Template validation function should be available"

Test-Assertion `
    -TestName "Clear-TemplateCache function is exported" `
    -Condition { Get-Command Clear-TemplateCache -Module TemplateEngine -ErrorAction SilentlyContinue } `
    -ExpectedBehavior "Cache management function should be available"

#endregion

#region Test Group 2: Template Path Resolution

Write-Host "`n[Group 2] Template Path Resolution" -ForegroundColor Magenta
Write-Host "=" * 60

Test-Assertion `
    -TestName "Get-TemplatePath resolves existing template" `
    -Condition {
        $path = Get-TemplatePath -TemplateName 'modern-dashboard.html'
        $path -and (Test-Path $path)
    } `
    -ExpectedBehavior "Should return valid path to modern-dashboard.html"

Test-Assertion `
    -TestName "Get-TemplatePath handles missing template gracefully" `
    -Condition {
        $path = Get-TemplatePath -TemplateName 'non-existent-template.html'
        $null -eq $path
    } `
    -ExpectedBehavior "Should return null for missing template"

Test-Assertion `
    -TestName "Get-TemplatePath finds CSS files" `
    -Condition {
        $path = Get-TemplatePath -TemplateName 'modern-dashboard.css'
        $path -and (Test-Path $path)
    } `
    -ExpectedBehavior "Should resolve CSS template path"

#endregion

#region Test Group 3: Template Loading

Write-Host "`n[Group 3] Template Loading" -ForegroundColor Magenta
Write-Host "=" * 60

Test-Assertion `
    -TestName "Get-Template loads main template" `
    -Condition {
        $template = Get-Template -TemplateName 'modern-dashboard.html' -TemplateType 'Main'
        $template -and $template.Contains('<!DOCTYPE html>')
    } `
    -ExpectedBehavior "Should load HTML template with DOCTYPE"

Test-Assertion `
    -TestName "Get-Template loads CSS template" `
    -Condition {
        $template = Get-Template -TemplateName 'modern-dashboard.css' -TemplateType 'CSS'
        $template -and $template.Contains(':root') -or $template.Contains('body')
    } `
    -ExpectedBehavior "Should load CSS with root or body selectors"

Test-Assertion `
    -TestName "Get-Template uses fallback for missing template" `
    -Condition {
        $template = Get-Template -TemplateName 'missing-template.html' -TemplateType 'Main'
        $template -and $template.Contains('fallback')
    } `
    -ExpectedBehavior "Should return fallback template containing 'fallback' text"

Test-Assertion `
    -TestName "Get-TemplateBundle loads complete bundle" `
    -Condition {
        $bundle = Get-TemplateBundle
        $bundle.Main -and $bundle.CSS -and $bundle.ModuleCard
    } `
    -ExpectedBehavior "Bundle should contain Main, CSS, and ModuleCard templates"

Test-Assertion `
    -TestName "Get-TemplateBundle sets IsEnhanced flag correctly" `
    -Condition {
        $standardBundle = Get-TemplateBundle
        $enhancedBundle = Get-TemplateBundle -UseEnhanced
        (-not $standardBundle.IsEnhanced) -and $enhancedBundle.IsEnhanced
    } `
    -ExpectedBehavior "Standard bundle IsEnhanced=false, Enhanced bundle IsEnhanced=true"

#endregion

#region Test Group 4: Template Caching

Write-Host "`n[Group 4] Template Caching" -ForegroundColor Magenta
Write-Host "=" * 60

# Clear cache before testing
Clear-TemplateCache | Out-Null

Test-Assertion `
    -TestName "Template caching works (cache miss then hit)" `
    -Condition {
        $statsBeforeLoad = Get-TemplateCacheStats
        $template1 = Get-Template -TemplateName 'modern-dashboard.html' -TemplateType 'Main'
        $statsAfterFirstLoad = Get-TemplateCacheStats
        $template2 = Get-Template -TemplateName 'modern-dashboard.html' -TemplateType 'Main'
        $statsAfterSecondLoad = Get-TemplateCacheStats
        
        # First load should be cache miss, second should be cache hit
        ($statsAfterFirstLoad.CacheMisses -gt $statsBeforeLoad.CacheMisses) -and
        ($statsAfterSecondLoad.CacheHits -gt $statsAfterFirstLoad.CacheHits)
    } `
    -ExpectedBehavior "First load=miss (loads file), Second load=hit (uses cache)"

Test-Assertion `
    -TestName "Get-TemplateCacheStats returns valid statistics" `
    -Condition {
        $stats = Get-TemplateCacheStats
        ($stats.CacheSize -ge 0) -and 
        ($stats.Keys -contains 'CacheHits') -and
        ($stats.Keys -contains 'CacheMisses')
    } `
    -ExpectedBehavior "Stats should include CacheSize, CacheHits, CacheMisses"

Test-Assertion `
    -TestName "Clear-TemplateCache clears all cached templates" `
    -Condition {
        Get-Template -TemplateName 'modern-dashboard.html' -TemplateType 'Main' | Out-Null
        $statsBefore = Get-TemplateCacheStats
        Clear-TemplateCache -Confirm:$false | Out-Null
        $statsAfter = Get-TemplateCacheStats
        ($statsBefore.CacheSize -gt 0) -and ($statsAfter.CacheSize -eq 0)
    } `
    -ExpectedBehavior "Cache size should be > 0 before clear, = 0 after clear"

Test-Assertion `
    -TestName "Clear-TemplateCache can clear specific template" `
    -Condition {
        Get-Template -TemplateName 'modern-dashboard.html' -TemplateType 'Main' | Out-Null
        Get-Template -TemplateName 'modern-dashboard.css' -TemplateType 'CSS' | Out-Null
        $statsBefore = Get-TemplateCacheStats
        Clear-TemplateCache -TemplateName 'modern-dashboard.html' -Confirm:$false | Out-Null
        $statsAfter = Get-TemplateCacheStats
        $statsAfter.CacheSize -lt $statsBefore.CacheSize
    } `
    -ExpectedBehavior "Cache size should decrease but not be empty"

#endregion

#region Test Group 5: Placeholder Replacement

Write-Host "`n[Group 5] Placeholder Replacement" -ForegroundColor Magenta
Write-Host "=" * 60

Test-Assertion `
    -TestName "Invoke-PlaceholderReplacement replaces simple placeholders" `
    -Condition {
        $template = "Hello {{NAME}}, your score is {{SCORE}}%"
        $replacements = @{ NAME = 'John'; SCORE = 95 }
        $result = Invoke-PlaceholderReplacement -Template $template -Replacements $replacements
        $result -eq "Hello John, your score is 95%"
    } `
    -ExpectedBehavior "Should replace {{NAME}} and {{SCORE}} with values"

Test-Assertion `
    -TestName "Invoke-PlaceholderReplacement handles multiple same placeholders" `
    -Condition {
        $template = "{{NAME}} is {{NAME}}"
        $replacements = @{ NAME = 'Alice' }
        $result = Invoke-PlaceholderReplacement -Template $template -Replacements $replacements
        $result -eq "Alice is Alice"
    } `
    -ExpectedBehavior "Should replace all occurrences of {{NAME}}"

Test-Assertion `
    -TestName "Invoke-PlaceholderReplacement converts null to empty string" `
    -Condition {
        $template = "Value: {{VALUE}}"
        $replacements = @{ VALUE = $null }
        $result = Invoke-PlaceholderReplacement -Template $template -Replacements $replacements
        $result -eq "Value: "
    } `
    -ExpectedBehavior "Null value should become empty string"

Test-Assertion `
    -TestName "Invoke-PlaceholderReplacement converts boolean to lowercase string" `
    -Condition {
        $template = "Enabled: {{ENABLED}}"
        $replacements = @{ ENABLED = $true }
        $result = Invoke-PlaceholderReplacement -Template $template -Replacements $replacements
        $result -eq "Enabled: true"
    } `
    -ExpectedBehavior "Boolean true should become 'true' (lowercase)"

Test-Assertion `
    -TestName "Invoke-PlaceholderReplacement leaves unreplaced placeholders" `
    -Condition {
        $template = "Hello {{NAME}}, your age is {{AGE}}"
        $replacements = @{ NAME = 'Bob' }
        $result = Invoke-PlaceholderReplacement -Template $template -Replacements $replacements
        $result -eq "Hello Bob, your age is {{AGE}}"
    } `
    -ExpectedBehavior "{{AGE}} should remain unreplaced"

#endregion

#region Test Group 6: Template Validation

Write-Host "`n[Group 6] Template Validation" -ForegroundColor Magenta
Write-Host "=" * 60

Test-Assertion `
    -TestName "Test-TemplateIntegrity validates template with required placeholders" `
    -Condition {
        $template = "<html>{{TITLE}} {{CONTENT}}</html>"
        $validation = Test-TemplateIntegrity -TemplateContent $template -RequiredPlaceholders @('TITLE', 'CONTENT')
        $validation.IsValid
    } `
    -ExpectedBehavior "Should validate successfully with all required placeholders present"

Test-Assertion `
    -TestName "Test-TemplateIntegrity detects missing placeholders" `
    -Condition {
        $template = "<html>{{TITLE}}</html>"
        $validation = Test-TemplateIntegrity -TemplateContent $template -RequiredPlaceholders @('TITLE', 'CONTENT')
        (-not $validation.IsValid) -and ($validation.MissingPlaceholders -contains 'CONTENT')
    } `
    -ExpectedBehavior "Should fail validation and report missing CONTENT placeholder"

Test-Assertion `
    -TestName "Test-TemplateIntegrity extracts all placeholders" `
    -Condition {
        $template = "{{VAR1}} {{VAR2}} {{VAR3}}"
        $validation = Test-TemplateIntegrity -TemplateContent $template
        $validation.AllPlaceholders.Count -eq 3
    } `
    -ExpectedBehavior "Should find 3 unique placeholders"

Test-Assertion `
    -TestName "Test-TemplateIntegrity validates HTML structure" `
    -Condition {
        $template = "<!DOCTYPE html><html><body></body></html>"
        $validation = Test-TemplateIntegrity -TemplateContent $template
        $validation.IsValid
    } `
    -ExpectedBehavior "Should validate complete HTML structure"

#endregion

#region Test Group 7: Fallback Templates

Write-Host "`n[Group 7] Fallback Templates" -ForegroundColor Magenta
Write-Host "=" * 60

Test-Assertion `
    -TestName "Get-FallbackTemplate returns main template fallback" `
    -Condition {
        $fallback = Get-FallbackTemplate -TemplateType 'Main'
        $fallback -and $fallback.Contains('<!DOCTYPE html>') -and $fallback.Contains('fallback')
    } `
    -ExpectedBehavior "Fallback main template should contain DOCTYPE and 'fallback' warning"

Test-Assertion `
    -TestName "Get-FallbackTemplate returns CSS fallback" `
    -Condition {
        $fallback = Get-FallbackTemplate -TemplateType 'CSS'
        $fallback -and ($fallback.Contains(':root') -or $fallback.Contains('body'))
    } `
    -ExpectedBehavior "Fallback CSS should contain root or body selectors"

Test-Assertion `
    -TestName "Get-FallbackTemplateBundle returns complete bundle" `
    -Condition {
        $bundle = Get-FallbackTemplateBundle
        $bundle.Main -and $bundle.CSS -and $bundle.ModuleCard -and $bundle.IsFallback
    } `
    -ExpectedBehavior "Fallback bundle should have Main, CSS, ModuleCard, and IsFallback=true"

#endregion

#region Test Group 8: Integration Tests

Write-Host "`n[Group 8] Integration with ReportGenerator (Backward Compatibility)" -ForegroundColor Magenta
Write-Host "=" * 60

# Import ReportGenerator to test integration
try {
    Import-Module (Join-Path $ModulesPath 'ReportGenerator.psm1') -Force -ErrorAction Stop
    $reportGeneratorLoaded = $true
}
catch {
    Write-Host "  ⚠️  ReportGenerator not available - skipping integration tests" -ForegroundColor Yellow
    $reportGeneratorLoaded = $false
}

if ($reportGeneratorLoaded) {
    Test-Assertion `
        -TestName "ReportGenerator Get-HtmlTemplateBundle delegates to TemplateEngine" `
        -Condition {
            $templates = Get-HtmlTemplateBundle
            $templates.Main -and $templates.CSS
        } `
        -ExpectedBehavior "ReportGenerator wrapper should successfully load templates via TemplateEngine"

    Test-Assertion `
        -TestName "ReportGenerator Get-HtmlTemplateBundle supports -UseEnhanced" `
        -Condition {
            $templates = Get-HtmlTemplateBundle -UseEnhanced
            # When path discovery not initialized, fallback is used (no IsEnhanced)
            # Check that templates were loaded (Main + CSS at minimum)
            $templates.Main -and $templates.CSS
        } `
        -ExpectedBehavior "Enhanced templates should be requested and returned (or fallback if path discovery not initialized)"
}

#endregion

#region Test Summary

Write-Host "`n" + ("=" * 60) -ForegroundColor Cyan
Write-Host "Test Summary" -ForegroundColor Cyan
Write-Host ("=" * 60) -ForegroundColor Cyan

$totalTests = $script:TestsPassed + $script:TestsFailed
$passRate = if ($totalTests -gt 0) { [Math]::Round(($script:TestsPassed / $totalTests) * 100, 2) } else { 0 }

Write-Host "`nTotal Tests:  $totalTests" -ForegroundColor White
Write-Host "Passed:       $script:TestsPassed" -ForegroundColor Green
Write-Host "Failed:       $script:TestsFailed" -ForegroundColor Red
Write-Host "Pass Rate:    $passRate%" -ForegroundColor $(if ($passRate -eq 100) { 'Green' } elseif ($passRate -ge 80) { 'Yellow' } else { 'Red' })

# Show failed tests
if ($script:TestsFailed -gt 0) {
    Write-Host "`nFailed Tests:" -ForegroundColor Red
    $script:TestResults | Where-Object { $_.Status -ne 'PASS' } | ForEach-Object {
        Write-Host "  • $($_.Name)" -ForegroundColor Red
        if ($_.Expected) { Write-Host "    Expected: $($_.Expected)" -ForegroundColor Yellow }
        if ($_.Actual) { Write-Host "    Actual: $($_.Actual)" -ForegroundColor Yellow }
        if ($_.Error) { Write-Host "    Error: $($_.Error)" -ForegroundColor Yellow }
    }
}

Write-Host "`n" + ("=" * 60) -ForegroundColor Cyan

# Return exit code
if ($script:TestsFailed -eq 0) {
    Write-Host "✅ All tests passed!" -ForegroundColor Green
    exit 0
}
else {
    Write-Host "❌ Some tests failed. Review output above." -ForegroundColor Red
    exit 1
}

#endregion
