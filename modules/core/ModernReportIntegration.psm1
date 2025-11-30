# Modern Report Integration Script
# Integrates the new modern dashboard system with existing ReportGenerator.psm1

<#
.SYNOPSIS
    Integration layer for modern dashboard report generation

.DESCRIPTION
    This script provides integration functions that connect the existing
    ReportGenerator.psm1 with the new modern dashboard system, allowing
    for seamless transition and backward compatibility.
#>

# Import required modules
Import-Module (Join-Path $PSScriptRoot 'ModernReportGenerator.psm1') -Force

<#
.SYNOPSIS
    Enhanced New-MaintenanceReport function that uses modern dashboard templates

.DESCRIPTION
    Wraps the existing report generation functionality to use the new modern
    dashboard templates while maintaining compatibility with existing code.
#>
function New-EnhancedMaintenanceReport {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$SessionId,
        
        [Parameter()]
        [hashtable]$ProcessedData,
        
        [Parameter()]
        [string]$OutputPath,
        
        [Parameter()]
        [bool]$UseModernTemplate = $true
    )
    
    Write-LogEntry -Level 'INFO' -Component 'ENHANCED-REPORT' -Message "Generating enhanced maintenance report with modern templates"
    
    try {
        if ($UseModernTemplate) {
            # Use the new modern dashboard system
            $reportPath = New-ModernMaintenanceReport -SessionId $SessionId -ProcessedData $ProcessedData -OutputPath $OutputPath
            Write-LogEntry -Level 'SUCCESS' -Component 'ENHANCED-REPORT' -Message "Modern dashboard report generated: $reportPath"
        }
        else {
            # Fall back to original report generation
            Write-LogEntry -Level 'INFO' -Component 'ENHANCED-REPORT' -Message "Using legacy report template"
            # Call original New-MaintenanceReport function here if needed
            throw "Legacy template not implemented in this version"
        }
        
        return $reportPath
    }
    catch {
        Write-LogEntry -Level 'ERROR' -Component 'ENHANCED-REPORT' -Message "Failed to generate enhanced report: $($_.Exception.Message)"
        throw
    }
}

<#
.SYNOPSIS
    Test function to validate the modern report generation system

.DESCRIPTION
    Creates a sample report with mock data to test the modern dashboard
    templates and ensure proper rendering.
#>
function Test-ModernReportGeneration {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$TestOutputPath = (Join-Path $PSScriptRoot "..\..\temp_files\reports\test_modern_report.html")
    )
    
    Write-LogEntry -Level 'INFO' -Component 'REPORT-TEST' -Message "Testing modern report generation system"
    
    try {
        # Create mock processed data for testing
        $mockData = @{
            ModuleResults  = @{
                'BloatwareRemoval'   = @{
                    Status               = 'Success'
                    Duration             = '45s'
                    TotalOperations      = 15
                    SuccessfulOperations = 12
                    FailedOperations     = 2
                    SkippedOperations    = 1
                    ProgressPercent      = 100
                }
                'EssentialApps'      = @{
                    Status               = 'Completed'
                    Duration             = '120s'
                    TotalOperations      = 8
                    SuccessfulOperations = 8
                    FailedOperations     = 0
                    SkippedOperations    = 0
                    ProgressPercent      = 100
                }
                'SystemOptimization' = @{
                    Status               = 'Warning'
                    Duration             = '78s'
                    TotalOperations      = 23
                    SuccessfulOperations = 20
                    FailedOperations     = 1
                    SkippedOperations    = 2
                    ProgressPercent      = 95
                }
                'TelemetryDisable'   = @{
                    Status               = 'Success'
                    Duration             = '32s'
                    TotalOperations      = 12
                    SuccessfulOperations = 12
                    FailedOperations     = 0
                    SkippedOperations    = 0
                    ProgressPercent      = 100
                }
                'WindowsUpdates'     = @{
                    Status               = 'Success'
                    Duration             = '156s'
                    TotalOperations      = 6
                    SuccessfulOperations = 6
                    FailedOperations     = 0
                    SkippedOperations    = 0
                    ProgressPercent      = 100
                }
            }
            SessionSummary = @{
                TotalModules       = 5
                SuccessfulModules  = 4
                TotalExecutionTime = '7 minutes 31 seconds'
                OverallHealthScore = 89
                SecurityScore      = 92
            }
        }
        
        # Generate test report
        $testSessionId = "TEST-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        $reportPath = New-ModernMaintenanceReport -SessionId $testSessionId -ProcessedData $mockData -OutputPath $TestOutputPath
        
        Write-LogEntry -Level 'SUCCESS' -Component 'REPORT-TEST' -Message "Test report generated successfully: $reportPath"
        
        # Optionally open the report in default browser
        if (Test-Path $reportPath) {
            Write-Host "Test report generated at: $reportPath" -ForegroundColor Green
            Write-Host "Opening report in default browser..." -ForegroundColor Cyan
            Start-Process $reportPath
        }
        
        return $reportPath
    }
    catch {
        Write-LogEntry -Level 'ERROR' -Component 'REPORT-TEST' -Message "Test report generation failed: $($_.Exception.Message)"
        Write-Error "Failed to generate test report: $($_.Exception.Message)"
        throw
    }
}

<#
.SYNOPSIS
    Validates that all required template files exist for modern report generation

.DESCRIPTION
    Checks for the presence of modern-dashboard.html, modern-dashboard.css,
    and module-card.html templates required for the enhanced report system.
#>
function Test-ModernTemplateFiles {
    [CmdletBinding()]
    param()
    
    Write-LogEntry -Level 'INFO' -Component 'TEMPLATE-VALIDATION' -Message "Validating modern template files"
    
    $templateDir = Join-Path $PSScriptRoot "..\..\config\templates"
    $requiredFiles = @(
        'modern-dashboard.html',
        'modern-dashboard.css', 
        'module-card.html'
    )
    
    $missingFiles = @()
    $validFiles = @()
    
    foreach ($file in $requiredFiles) {
        $filePath = Join-Path $templateDir $file
        if (Test-Path $filePath) {
            $validFiles += $file
            Write-LogEntry -Level 'SUCCESS' -Component 'TEMPLATE-VALIDATION' -Message "✓ Found: $file"
        }
        else {
            $missingFiles += $file
            Write-LogEntry -Level 'ERROR' -Component 'TEMPLATE-VALIDATION' -Message "✗ Missing: $file"
        }
    }
    
    $result = @{
        Valid             = ($missingFiles.Count -eq 0)
        ValidFiles        = $validFiles
        MissingFiles      = $missingFiles
        TemplateDirectory = $templateDir
    }
    
    if ($result.Valid) {
        Write-LogEntry -Level 'SUCCESS' -Component 'TEMPLATE-VALIDATION' -Message "All required template files are present"
        Write-Host "✅ Template validation passed - all files present" -ForegroundColor Green
    }
    else {
        Write-LogEntry -Level 'ERROR' -Component 'TEMPLATE-VALIDATION' -Message "Missing template files: $($missingFiles -join ', ')"
        Write-Host "❌ Template validation failed - missing files: $($missingFiles -join ', ')" -ForegroundColor Red
    }
    
    return $result
}

<#
.SYNOPSIS
    Comprehensive test of the entire modern report generation pipeline

.DESCRIPTION
    Runs a complete test that validates templates, generates a test report,
    and verifies the output HTML structure and content.
#>
function Invoke-CompleteReportTest {
    [CmdletBinding()]
    param(
        [Parameter()]
        [bool]$OpenInBrowser = $true
    )
    
    Write-Host "`n🚀 Starting Complete Modern Report Generation Test" -ForegroundColor Cyan
    Write-Host "=" * 60 -ForegroundColor Gray
    
    try {
        # Step 1: Validate template files
        Write-Host "`n1️⃣  Validating Template Files..." -ForegroundColor Yellow
        $templateValidation = Test-ModernTemplateFiles
        if (-not $templateValidation.Valid) {
            throw "Template validation failed. Missing files: $($templateValidation.MissingFiles -join ', ')"
        }
        
        # Step 2: Test report generation
        Write-Host "`n2️⃣  Generating Test Report..." -ForegroundColor Yellow
        $testReportPath = Test-ModernReportGeneration
        if (-not (Test-Path $testReportPath)) {
            throw "Test report was not generated successfully"
        }
        
        # Step 3: Validate HTML structure
        Write-Host "`n3️⃣  Validating HTML Structure..." -ForegroundColor Yellow
        $htmlContent = Get-Content $testReportPath -Raw
        $validations = @()
        
        # Check for key elements
        if ($htmlContent -match 'class="dashboard"') { $validations += "✓ Dashboard container found" }
        if ($htmlContent -match 'class="module-card"') { $validations += "✓ Module cards found" }
        if ($htmlContent -match 'data-theme="dark"') { $validations += "✓ Theme system present" }
        if ($htmlContent -match 'modern-dashboard\.css') { $validations += "✓ CSS stylesheet linked" }
        if ($htmlContent -match 'toggleTheme\(\)') { $validations += "✓ JavaScript functionality present" }
        
        foreach ($validation in $validations) {
            Write-Host "  $validation" -ForegroundColor Green
        }
        
        # Step 4: Display results
        Write-Host "`n4️⃣  Test Results:" -ForegroundColor Yellow
        Write-Host "  📄 Report Path: $testReportPath" -ForegroundColor Cyan
        Write-Host "  📏 File Size: $([math]::Round((Get-Item $testReportPath).Length / 1KB, 2)) KB" -ForegroundColor Cyan
        Write-Host "  🕒 Generated: $(Get-Date)" -ForegroundColor Cyan
        
        if ($OpenInBrowser -and (Test-Path $testReportPath)) {
            Write-Host "`n🌐 Opening report in default browser..." -ForegroundColor Green
            Start-Process $testReportPath
        }
        
        Write-Host "`n✅ Complete Report Generation Test PASSED" -ForegroundColor Green
        Write-Host "=" * 60 -ForegroundColor Gray
        
        return @{
            Success            = $true
            ReportPath         = $testReportPath
            TemplateValidation = $templateValidation
            ValidationResults  = $validations
        }
    }
    catch {
        Write-Host "`n❌ Complete Report Generation Test FAILED" -ForegroundColor Red
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "=" * 60 -ForegroundColor Gray
        
        return @{
            Success = $false
            Error   = $_.Exception.Message
        }
    }
}

# Export functions for use in other modules
Export-ModuleMember -Function @(
    'New-EnhancedMaintenanceReport',
    'Test-ModernReportGeneration',
    'Test-ModernTemplateFiles',
    'Invoke-CompleteReportTest'
)

# Display information when module is imported
Write-Host "`n🎨 Modern Report Integration Module Loaded" -ForegroundColor Cyan
Write-Host "Available functions:" -ForegroundColor Gray
Write-Host "  • New-EnhancedMaintenanceReport - Generate modern dashboard reports" -ForegroundColor Green
Write-Host "  • Test-ModernReportGeneration - Test with sample data" -ForegroundColor Green
Write-Host "  • Test-ModernTemplateFiles - Validate template files" -ForegroundColor Green
Write-Host "  • Invoke-CompleteReportTest - Run comprehensive test" -ForegroundColor Green
Write-Host "`nRun 'Invoke-CompleteReportTest' to test the entire system!`n" -ForegroundColor Yellow