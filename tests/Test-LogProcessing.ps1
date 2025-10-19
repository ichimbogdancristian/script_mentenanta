#Requires -Version 7.0

<#
.SYNOPSIS
    Validates the complete log processing pipeline

.DESCRIPTION
    TODO-005: Validate Log Processing Pipeline
    Tests LogProcessor execution with verbose logging to identify any issues
#>

[CmdletBinding()]
param(
    [switch]$DryRun
)

Write-Host "`n🔍 Testing Log Processing Pipeline" -ForegroundColor Cyan
Write-Host "=" * 60

try {
    # Import CoreInfrastructure
    Write-Host "`n📦 Loading CoreInfrastructure module..." -ForegroundColor Yellow
    $coreInfraPath = Join-Path $PSScriptRoot "..\modules\core\CoreInfrastructure.psm1"
    Import-Module $coreInfraPath -Force -Global
    Write-Host "✅ CoreInfrastructure loaded" -ForegroundColor Green
    
    # Import LogProcessor
    Write-Host "📦 Loading LogProcessor module..." -ForegroundColor Yellow
    $logProcessorPath = Join-Path $PSScriptRoot "..\modules\core\LogProcessor.psm1"
    Import-Module $logProcessorPath -Force
    Write-Host "✅ LogProcessor loaded" -ForegroundColor Green
    
    # Check for log files
    Write-Host "`n📁 Checking for log files..." -ForegroundColor Yellow
    $tempFilesPath = Join-Path $PSScriptRoot "..\temp_files"
    
    $dataFiles = Get-ChildItem -Path (Join-Path $tempFilesPath "data") -Filter "*.json" -ErrorAction SilentlyContinue
    $logDirs = Get-ChildItem -Path (Join-Path $tempFilesPath "logs") -Directory -ErrorAction SilentlyContinue
    
    Write-Host "   Data files: $($dataFiles.Count)" -ForegroundColor Cyan
    Write-Host "   Log directories: $($logDirs.Count)" -ForegroundColor Cyan
    
    if ($dataFiles.Count -eq 0 -and $logDirs.Count -eq 0) {
        Write-Host "⚠️ WARNING: No log files found - need to run maintenance first" -ForegroundColor Yellow
        Write-Host "   Run: .\MaintenanceOrchestrator.ps1 -NonInteractive -DryRun" -ForegroundColor Cyan
        return
    }
    
    # Try to process logs
    Write-Host "`n🔄 Attempting to process logs..." -ForegroundColor Yellow
    Write-Host "   (This will test if TODO-001 fix resolved the validation error)" -ForegroundColor Gray
    
    try {
        $result = Process-MaintenanceLogs -Verbose
        
        if ($result) {
            Write-Host "`n✅ SUCCESS: Log processing completed without errors" -ForegroundColor Green
            
            # Verify processed files created
            Write-Host "`n📊 Verifying processed files..." -ForegroundColor Yellow
            $processedPath = Join-Path $tempFilesPath "processed"
            $requiredFiles = @(
                'health-scores.json',
                'metrics-summary.json',
                'module-results.json',
                'maintenance-log.json',
                'errors-analysis.json'
            )
            
            $allFound = $true
            foreach ($file in $requiredFiles) {
                $filePath = Join-Path $processedPath $file
                if (Test-Path $filePath) {
                    $size = (Get-Item $filePath).Length
                    Write-Host "   ✅ $file ($size bytes)" -ForegroundColor Green
                }
                else {
                    Write-Host "   ❌ $file MISSING" -ForegroundColor Red
                    $allFound = $false
                }
            }
            
            if ($allFound) {
                Write-Host "`n✅ TEST PASSED: All processed files created successfully" -ForegroundColor Green
                Write-Host "   TODO-001 fix confirmed working!" -ForegroundColor Green
                exit 0
            }
            else {
                Write-Host "`n⚠️ TEST WARNING: Processing succeeded but some files missing" -ForegroundColor Yellow
                exit 2
            }
        }
        else {
            Write-Host "`n⚠️ WARNING: Process-MaintenanceLogs returned null/false" -ForegroundColor Yellow
            exit 2
        }
    }
    catch {
        Write-Host "`n❌ ERROR: Log processing failed" -ForegroundColor Red
        Write-Host "   Exception: $($_.Exception.Message)" -ForegroundColor Red
        
        # Check if it's the old validation error
        if ($_.Exception.Message -match "WARNING.*does not belong to the set") {
            Write-Host "`n🔴 CRITICAL: Still seeing 'WARNING' validation error!" -ForegroundColor Red
            Write-Host "   TODO-001 fix may not have been applied correctly" -ForegroundColor Red
            Write-Host "   Verify all 11 instances changed from 'WARNING' to 'WARN'" -ForegroundColor Yellow
        }
        
        Write-Host "`n📋 Error Details:" -ForegroundColor Yellow
        Write-Host $_.Exception | Format-List -Force | Out-String
        
        exit 1
    }
}
catch {
    Write-Host "`n❌ TEST FAILED: Module loading error" -ForegroundColor Red
    Write-Host "   $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
