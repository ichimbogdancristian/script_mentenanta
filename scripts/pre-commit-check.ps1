#Requires -Version 7.0

<#
.SYNOPSIS
    Pre-commit quality validation script

.DESCRIPTION
    Validates code quality before allowing commits.
    Checks PowerShell, JSON, and HTML files for compliance.

.PARAMETER Fix
    Attempt to fix issues automatically where possible

.PARAMETER Detailed
    Show detailed analysis results

.PARAMETER ExitOnError
    Exit with error code if issues are found (default: true)

.EXAMPLE
    .\pre-commit-check.ps1
    Run basic quality checks

.EXAMPLE
    .\pre-commit-check.ps1 -Detailed
    Run quality checks with detailed output

.EXAMPLE
    .\pre-commit-check.ps1 -Fix
    Run quality checks and attempt to fix issues

.NOTES
    Author: Windows Maintenance Automation Team
    Version: 1.0.0
    Last Updated: October 28, 2025
#>

[CmdletBinding()]
param(
    [switch]$Fix,           # Attempt to fix issues automatically
    [switch]$Detailed,      # Show detailed analysis
    [switch]$ExitOnError = $true  # Exit with error code if issues found
)

# Initialize
$ErrorActionPreference = 'Stop'
$totalIssues = 0
$startTime = Get-Date

# Color output functions
function Write-Success { param($Message) Write-Host $Message -ForegroundColor Green }
function Write-Warning { param($Message) Write-Host $Message -ForegroundColor Yellow }
function Write-Error { param($Message) Write-Host $Message -ForegroundColor Red }
function Write-Info { param($Message) Write-Host $Message -ForegroundColor Cyan }

Write-Info "🔍 Running pre-commit quality checks..."
Write-Host ""

#region PowerShell Analysis

Write-Info "📝 PowerShell Analysis"
Write-Host "─" * 50

# Find all PowerShell files
$psFiles = @()
$psFiles += Get-ChildItem -Path . -Filter "*.ps1" -Recurse -ErrorAction SilentlyContinue
$psFiles += Get-ChildItem -Path . -Filter "*.psm1" -Recurse -ErrorAction SilentlyContinue
$psFiles += Get-ChildItem -Path . -Filter "*.psd1" -Recurse -ErrorAction SilentlyContinue

if ($psFiles.Count -eq 0) {
    Write-Warning "No PowerShell files found."
}
else {
    Write-Host "Found $($psFiles.Count) PowerShell file(s)"

    # Check if PSScriptAnalyzer is available
    try {
        Import-Module PSScriptAnalyzer -ErrorAction Stop
    }
    catch {
        Write-Warning "PSScriptAnalyzer not found. Installing..."
        try {
            Install-Module -Name PSScriptAnalyzer -Force -SkipPublisherCheck -Scope CurrentUser
            Import-Module PSScriptAnalyzer
            Write-Success "PSScriptAnalyzer installed successfully"
        }
        catch {
            Write-Error "Failed to install PSScriptAnalyzer: $($_.Exception.Message)"
            $totalIssues++
        }
    }

    if (Get-Module PSScriptAnalyzer) {
        $analysisResults = @()

        foreach ($file in $psFiles) {
            try {
                $results = Invoke-ScriptAnalyzer -Path $file.FullName -Severity Warning, Error -ExcludeRule PSAvoidUsingWriteHost
                if ($results) {
                    $analysisResults += $results
                }
            }
            catch {
                Write-Error "Failed to analyze $($file.Name): $($_.Exception.Message)"
                $totalIssues++
            }
        }

        if ($analysisResults.Count -gt 0) {
            Write-Error "❌ PSScriptAnalyzer found $($analysisResults.Count) issues:"

            if ($Detailed) {
                $analysisResults | Format-Table -Property Severity, RuleName, Line, Message, ScriptName -Wrap
            }
            else {
                $grouped = $analysisResults | Group-Object RuleName | Sort-Object Count -Descending
                foreach ($group in $grouped) {
                    Write-Host "  • $($group.Name): $($group.Count) occurrence(s)" -ForegroundColor Red
                }

                if ($analysisResults.Count -gt 20) {
                    Write-Host "  Run with -Detailed to see all issues" -ForegroundColor Yellow
                }
            }

            $totalIssues += $analysisResults.Count

            # Attempt to fix some issues if requested
            if ($Fix) {
                Write-Info "Attempting to fix PowerShell issues..."
                # This would implement auto-fixing logic for common issues
                Write-Warning "Auto-fix for PowerShell issues not yet implemented"
            }
        }
        else {
            Write-Success "✅ All PowerShell files pass PSScriptAnalyzer validation"
        }
    }
}

#endregion

#region JSON Validation

Write-Host ""
Write-Info "📄 JSON Validation"
Write-Host "─" * 50

$jsonFiles = Get-ChildItem -Path . -Filter "*.json" -Recurse -ErrorAction SilentlyContinue
$jsonIssues = 0

if ($jsonFiles.Count -eq 0) {
    Write-Warning "No JSON files found."
}
else {
    Write-Host "Found $($jsonFiles.Count) JSON file(s)"

    foreach ($file in $jsonFiles) {
        try {
            $content = Get-Content $file.FullName -Raw -ErrorAction Stop
            $json = $content | ConvertFrom-Json -ErrorAction Stop

            # Check schema compliance for config files
            $schemaIssues = @()
            if ($file.DirectoryName -like "*config*") {
                if (-not $json.PSObject.Properties['_comment']) {
                    $schemaIssues += "Missing _comment field"
                }
                if (-not $json.PSObject.Properties['version']) {
                    $schemaIssues += "Missing version field"
                }
                if (-not $json.PSObject.Properties['lastModified']) {
                    $schemaIssues += "Missing lastModified field"
                }

                # Validate version format
                if ($json.version -and $json.version -notmatch '^\d+\.\d+\.\d+$') {
                    $schemaIssues += "Invalid version format (should be x.y.z)"
                }

                # Validate timestamp format
                if ($json.lastModified -and $json.lastModified -notmatch '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$') {
                    $schemaIssues += "Invalid lastModified format (should be ISO 8601)"
                }
            }

            if ($schemaIssues.Count -gt 0) {
                Write-Warning "⚠️  Schema issues in $($file.Name):"
                $schemaIssues | ForEach-Object { Write-Host "    • $_" -ForegroundColor Yellow }
                $jsonIssues += $schemaIssues.Count

                # Attempt to fix schema issues if requested
                if ($Fix) {
                    Write-Info "Attempting to fix JSON schema issues in $($file.Name)..."

                    # Add missing fields with default values
                    $updated = $false
                    if (-not $json.PSObject.Properties['_comment']) {
                        $json | Add-Member -NotePropertyName '_comment' -NotePropertyValue "Configuration file for Windows Maintenance Automation"
                        $updated = $true
                    }
                    if (-not $json.PSObject.Properties['version']) {
                        $json | Add-Member -NotePropertyName 'version' -NotePropertyValue "1.0.0"
                        $updated = $true
                    }
                    if (-not $json.PSObject.Properties['lastModified']) {
                        $json | Add-Member -NotePropertyName 'lastModified' -NotePropertyValue (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
                        $updated = $true
                    }

                    if ($updated) {
                        try {
                            $json | ConvertTo-Json -Depth 10 | Set-Content $file.FullName -Encoding UTF8
                            Write-Success "Fixed schema issues in $($file.Name)"
                            $jsonIssues -= $schemaIssues.Count  # Remove from issue count since fixed
                        }
                        catch {
                            Write-Error "Failed to fix $($file.Name): $($_.Exception.Message)"
                        }
                    }
                }
            }
            else {
                Write-Host "✅ Valid JSON: $($file.Name)" -ForegroundColor Green
            }
        }
        catch {
            Write-Error "❌ Invalid JSON: $($file.Name) - $($_.Exception.Message)"
            $jsonIssues++
        }
    }

    if ($jsonIssues -eq 0) {
        Write-Success "✅ All JSON files are valid and compliant"
    }
}

$totalIssues += $jsonIssues

#endregion

#region HTML Validation

Write-Host ""
Write-Info "🌐 HTML Validation"
Write-Host "─" * 50

$htmlFiles = Get-ChildItem -Path . -Filter "*.html" -Recurse -ErrorAction SilentlyContinue
$htmlIssues = 0

if ($htmlFiles.Count -eq 0) {
    Write-Warning "No HTML files found."
}
else {
    Write-Host "Found $($htmlFiles.Count) HTML file(s)"

    foreach ($file in $htmlFiles) {
        try {
            $content = Get-Content $file.FullName -Raw -ErrorAction Stop
            $issues = @()

            # Basic HTML structure checks
            if ($content -notmatch '<!DOCTYPE html>') {
                $issues += "Missing DOCTYPE declaration"
            }
            if ($content -notmatch '<html.*?lang="[^"]*".*?>') {
                $issues += "Missing or invalid lang attribute in html tag"
            }
            if ($content -notmatch '<head>.*</head>') {
                $issues += "Missing head section"
            }
            if ($content -notmatch '<title>.*</title>') {
                $issues += "Missing title tag"
            }
            if ($content -notmatch '<meta charset="UTF-8">') {
                $issues += "Missing UTF-8 charset declaration"
            }
            if ($content -notmatch '<meta name="viewport"') {
                $issues += "Missing viewport meta tag"
            }

            # Accessibility checks
            $imgTags = [regex]::Matches($content, '<img[^>]+>')
            foreach ($imgMatch in $imgTags) {
                if ($imgMatch.Value -notmatch 'alt="[^"]*"') {
                    $issues += "Image missing alt attribute: $($imgMatch.Value.Substring(0, [Math]::Min(50, $imgMatch.Value.Length)))..."
                }
            }

            # Check for unreplaced template variables
            $unreplacedVars = [regex]::Matches($content, '\{\{[A-Z_]+\}\}') | ForEach-Object { $_.Value }
            if ($unreplacedVars.Count -gt 0 -and $file.Name -notlike "*template*") {
                $issues += "Unreplaced template variables: $($unreplacedVars -join ', ')"
            }

            if ($issues.Count -gt 0) {
                Write-Warning "⚠️  HTML issues in $($file.Name):"
                $issues | ForEach-Object { Write-Host "    • $_" -ForegroundColor Yellow }
                $htmlIssues += $issues.Count
            }
            else {
                Write-Success "✅ Valid HTML: $($file.Name)"
            }
        }
        catch {
            Write-Error "❌ Error checking HTML: $($file.Name) - $($_.Exception.Message)"
            $htmlIssues++
        }
    }
}

$totalIssues += $htmlIssues

#endregion

#region File Encoding Check

Write-Host ""
Write-Info "📝 File Encoding Check"
Write-Host "─" * 50

$encodingIssues = 0
$textFiles = @()
$textFiles += Get-ChildItem -Path . -Filter "*.ps1" -Recurse -ErrorAction SilentlyContinue
$textFiles += Get-ChildItem -Path . -Filter "*.psm1" -Recurse -ErrorAction SilentlyContinue
$textFiles += Get-ChildItem -Path . -Filter "*.json" -Recurse -ErrorAction SilentlyContinue
$textFiles += Get-ChildItem -Path . -Filter "*.html" -Recurse -ErrorAction SilentlyContinue
$textFiles += Get-ChildItem -Path . -Filter "*.css" -Recurse -ErrorAction SilentlyContinue
$textFiles += Get-ChildItem -Path . -Filter "*.md" -Recurse -ErrorAction SilentlyContinue

if ($textFiles.Count -gt 0) {
    Write-Host "Checking encoding for $($textFiles.Count) text file(s)"

    foreach ($file in $textFiles) {
        try {
            $bytes = Get-Content $file.FullName -AsByteStream -TotalCount 3

            # Check for BOM
            $hasBOM = $false
            if ($bytes.Count -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
                $hasBOM = $true
            }

            # PowerShell files should have UTF-8 BOM
            if ($file.Extension -in @('.ps1', '.psm1', '.psd1') -and -not $hasBOM) {
                Write-Warning "⚠️  PowerShell file without UTF-8 BOM: $($file.Name)"
                $encodingIssues++

                if ($Fix) {
                    try {
                        $content = Get-Content $file.FullName -Raw
                        $content | Set-Content $file.FullName -Encoding UTF8BOM
                        Write-Success "Fixed encoding for $($file.Name)"
                        $encodingIssues--
                    }
                    catch {
                        Write-Error "Failed to fix encoding for $($file.Name): $($_.Exception.Message)"
                    }
                }
            }
        }
        catch {
            Write-Warning "Could not check encoding for $($file.Name): $($_.Exception.Message)"
        }
    }

    if ($encodingIssues -eq 0) {
        Write-Success "✅ All files have correct encoding"
    }
}

$totalIssues += $encodingIssues

#endregion

#region Summary

Write-Host ""
Write-Info "📊 Quality Check Summary"
Write-Host "─" * 50

$duration = (Get-Date) - $startTime
Write-Host "Duration: $($duration.TotalSeconds.ToString('F2')) seconds"
Write-Host "Files checked:"
Write-Host "  • PowerShell: $($psFiles.Count)"
Write-Host "  • JSON: $($jsonFiles.Count)"
Write-Host "  • HTML: $($htmlFiles.Count)"
Write-Host "  • Total: $($psFiles.Count + $jsonFiles.Count + $htmlFiles.Count)"

if ($totalIssues -eq 0) {
    Write-Host ""
    Write-Success "🎉 All quality checks passed!"
    Write-Success "Code is ready for commit."

    if ($ExitOnError) {
        exit 0
    }
}
else {
    Write-Host ""
    Write-Error "❌ Quality check failed with $totalIssues issue(s)"
    Write-Host ""

    if ($Fix) {
        Write-Info "Some issues may have been automatically fixed."
        Write-Info "Re-run the quality check to verify all issues are resolved."
    }
    else {
        Write-Info "Run with -Fix to attempt automatic fixes for some issues."
    }

    if (-not $Detailed) {
        Write-Info "Run with -Detailed for more information."
    }

    Write-Host ""
    Write-Host "To commit anyway (not recommended): git commit --no-verify" -ForegroundColor DarkGray

    if ($ExitOnError) {
        exit 1
    }
}

#endregion
