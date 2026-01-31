#!/usr/bin/env pwsh
<#
.SYNOPSIS
    CIS Security Enhancement Module - Quick Test & Validation Script

.DESCRIPTION
    This script validates the SecurityEnhancementCIS module implementation and demonstrates usage.
    Run this after module installation to verify all controls are working correctly.

.PARAMETER DryRun
    Run in dry-run mode (simulate changes without modifying the system)

.PARAMETER Categories
    Specific control categories to test (All, PasswordPolicy, AccountLockout, UAC, Firewall, Auditing, Services, Defender, Encryption)

.PARAMETER Verbose
    Enable verbose output for debugging

.EXAMPLE
    # Test all controls in dry-run mode
    .\Test-CISSecurityEnhancement.ps1 -DryRun

.EXAMPLE
    # Test password policies only
    .\Test-CISSecurityEnhancement.ps1 -Categories 'PasswordPolicy' -DryRun

.EXAMPLE
    # Execute firewall configuration for real
    .\Test-CISSecurityEnhancement.ps1 -Categories 'Firewall'

.NOTES
    Author: CIS Implementation Team
    Version: 1.0.0
    Status: Testing & Validation
    Requires: PowerShell 7.0+, Administrator privileges
#>

[CmdletBinding()]
param(
    [switch]$DryRun = $true,
    [ValidateSet('All', 'PasswordPolicy', 'AccountLockout', 'UAC', 'Firewall', 'Auditing', 'Services', 'Defender', 'Encryption')]
    [string[]]$Categories = 'All',
    [switch]$Verbose
)

# Ensure admin privileges
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "This script requires administrator privileges. Please run PowerShell as Administrator."
    exit 1
}

Write-Host "`n" + ("=" * 80) -ForegroundColor Cyan
Write-Host "CIS Security Enhancement Module - Validation Test" -ForegroundColor Cyan
Write-Host ("=" * 80) -ForegroundColor Cyan

# Get module path
$ModuleRoot = Split-Path -Parent $PSScriptRoot
$ModulePath = Join-Path $ModuleRoot 'modules\type2\SecurityEnhancementCIS.psm1'

if (-not (Test-Path $ModulePath)) {
    Write-Error "Module not found at: $ModulePath"
    exit 1
}

Write-Host "`n[1/5] Loading module..." -ForegroundColor Yellow
try {
    Import-Module $ModulePath -Force -Verbose:$Verbose
    Write-Host "✓ Module loaded successfully" -ForegroundColor Green
}
catch {
    Write-Error "Failed to load module: $_"
    exit 1
}

# Check exported functions
Write-Host "`n[2/5] Verifying exported functions..." -ForegroundColor Yellow
$exportedFunctions = Get-Command -Module SecurityEnhancementCIS -ErrorAction SilentlyContinue
if ($exportedFunctions) {
    Write-Host "✓ Found $(($exportedFunctions | Measure-Object).Count) exported functions:" -ForegroundColor Green
    $exportedFunctions | ForEach-Object { Write-Host "   - $($_.Name)" -ForegroundColor Green }
}
else {
    Write-Error "No exported functions found"
    exit 1
}

# Check configuration file
Write-Host "`n[3/5] Verifying CIS configuration file..." -ForegroundColor Yellow
$configPath = Join-Path $ModuleRoot 'config\settings\cis-baseline-v4.0.0.json'
if (Test-Path $configPath) {
    $config = Get-Content $configPath -Raw | ConvertFrom-Json
    Write-Host "✓ Configuration file found" -ForegroundColor Green
    Write-Host "   Version: $($config.metadata.version)" -ForegroundColor Green
    Write-Host "   Benchmark: $($config.metadata.benchmark)" -ForegroundColor Green
    Write-Host "   Controls defined: $($config.PSObject.Properties.Count)" -ForegroundColor Green
}
else {
    Write-Warning "Configuration file not found: $configPath (optional)"
}

# Test current status check
Write-Host "`n[4/5] Testing Get-CISControlStatus function..." -ForegroundColor Yellow
try {
    $status = Get-CISControlStatus
    if ($status) {
        Write-Host "✓ Status check successful" -ForegroundColor Green
        Write-Host "   Current controls status:" -ForegroundColor Gray
        $status.GetEnumerator() | ForEach-Object {
            $check = if ($_.Value) { "✓ Enabled" } else { "✗ Disabled" }
            Write-Host "     $($_.Key): $check" -ForegroundColor Gray
        }
    }
    else {
        Write-Warning "Status check returned empty results"
    }
}
catch {
    Write-Error "Status check failed: $_"
}

# Run CIS enhancement in specified mode
Write-Host "`n[5/5] Running CIS Security Enhancement..." -ForegroundColor Yellow
Write-Host "Mode: $(if ($DryRun) { 'DRY-RUN (simulated)' } else { 'LIVE EXECUTION' })" -ForegroundColor $(if ($DryRun) { 'Blue' } else { 'Red' })
Write-Host "Categories: $($Categories -join ', ')" -ForegroundColor Gray

try {
    $results = Invoke-CISSecurityEnhancement -DryRun:$DryRun -ControlCategories $Categories -Verbose:$Verbose
    
    Write-Host "`n✓ Execution completed" -ForegroundColor Green
    Write-Host "`nExecution Summary:" -ForegroundColor Cyan
    Write-Host "   Status: $($results.Status)" -ForegroundColor $(if ($results.Status -eq 'Success') { 'Green' } else { 'Yellow' })
    Write-Host "   Total Controls: $($results.TotalControls)" -ForegroundColor Gray
    Write-Host "   Applied: $($results.AppliedControls)" -ForegroundColor Green
    Write-Host "   Failed: $($results.FailedControls)" -ForegroundColor $(if ($results.FailedControls -gt 0) { 'Red' } else { 'Green' })
    Write-Host "   Skipped: $($results.SkippedControls)" -ForegroundColor Yellow
    Write-Host "   Duration: $([math]::Round($results.DurationSeconds, 2))s" -ForegroundColor Gray
    
    # Show detailed results
    Write-Host "`nDetailed Control Results:" -ForegroundColor Cyan
    Write-Host ("=" * 80) -ForegroundColor Cyan
    
    $successControls = @($results.ControlDetails | Where-Object { $_.Status -eq 'Success' })
    $failedControls = @($results.ControlDetails | Where-Object { $_.Status -eq 'Failed' })
    $skippedControls = @($results.ControlDetails | Where-Object { $_.Status -eq 'Skipped' })
    $dryRunControls = @($results.ControlDetails | Where-Object { $_.Status -eq 'DryRun' })
    
    if ($successControls.Count -gt 0) {
        Write-Host "`n✓ Successful Controls ($($successControls.Count)):" -ForegroundColor Green
        $successControls | Format-Table -Property @(
            @{ Name = 'ID'; Expression = { $_.ControlID } },
            @{ Name = 'Name'; Expression = { $_.ControlName } },
            @{ Name = 'Status'; Expression = { $_.Status } }
        ) -AutoSize | Out-String | Write-Host
    }
    
    if ($failedControls.Count -gt 0) {
        Write-Host "`n✗ Failed Controls ($($failedControls.Count)):" -ForegroundColor Red
        $failedControls | Format-Table -Property @(
            @{ Name = 'ID'; Expression = { $_.ControlID } },
            @{ Name = 'Name'; Expression = { $_.ControlName } },
            @{ Name = 'Status'; Expression = { $_.Status } },
            @{ Name = 'Message'; Expression = { $_.Message } }
        ) -AutoSize | Out-String | Write-Host
    }
    
    if ($skippedControls.Count -gt 0) {
        Write-Host "`n⊘ Skipped Controls ($($skippedControls.Count)):" -ForegroundColor Yellow
        $skippedControls | Format-Table -Property @(
            @{ Name = 'ID'; Expression = { $_.ControlID } },
            @{ Name = 'Name'; Expression = { $_.ControlName } },
            @{ Name = 'Status'; Expression = { $_.Status } }
        ) -AutoSize | Out-String | Write-Host
    }
    
    if ($dryRunControls.Count -gt 0) {
        Write-Host "`nℹ Dry-Run Controls ($($dryRunControls.Count)):" -ForegroundColor Blue
        $dryRunControls | Format-Table -Property @(
            @{ Name = 'ID'; Expression = { $_.ControlID } },
            @{ Name = 'Name'; Expression = { $_.ControlName } },
            @{ Name = 'Status'; Expression = { $_.Status } }
        ) -AutoSize | Out-String | Write-Host
    }
    
    Write-Host "`n" + ("=" * 80) -ForegroundColor Cyan
    
    # Recommendations
    Write-Host "`nRecommendations:" -ForegroundColor Cyan
    if ($DryRun) {
        Write-Host "✓ Dry-run completed successfully. Results show what would be changed." -ForegroundColor Green
        Write-Host "  Run without -DryRun to apply changes to the actual system." -ForegroundColor Yellow
    }
    else {
        if ($results.FailedControls -eq 0) {
            Write-Host "✓ All controls applied successfully!" -ForegroundColor Green
            Write-Host "  System is now hardened according to CIS v4.0.0 benchmark." -ForegroundColor Green
        }
        else {
            Write-Host "⚠ Some controls failed. Review the errors above and remediate." -ForegroundColor Yellow
            Write-Host "  Run with -DryRun to test changes first in future." -ForegroundColor Yellow
        }
    }
    
    Write-Host "`nNext Steps:" -ForegroundColor Cyan
    Write-Host "1. Review the detailed results above" -ForegroundColor Gray
    Write-Host "2. If satisfied with dry-run results, run without -DryRun to apply changes" -ForegroundColor Gray
    Write-Host "3. Run 'Get-CISControlStatus' monthly to verify controls remain applied" -ForegroundColor Gray
    Write-Host "4. Submit results to your Wazuh server for updated CIS benchmark score" -ForegroundColor Gray
    
}
catch {
    Write-Error "CIS enhancement failed: $_"
    Write-Error $_.ScriptStackTrace
    exit 1
}

Write-Host "`n" + ("=" * 80) -ForegroundColor Cyan
Write-Host "Validation Complete" -ForegroundColor Cyan
Write-Host ("=" * 80) -ForegroundColor Cyan
Write-Host ""
