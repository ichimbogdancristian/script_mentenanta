#Requires -Version 7.0
#Requires -RunAsAdministrator
<#
.SYNOPSIS
Test script for new multi-source bloatware detection system.
.DESCRIPTION
Validates configuration files, detection accuracy, and removal strategy.
Run this BEFORE and AFTER bloatware removal to verify the system works.
.EXAMPLE
pwsh -File .\test-bloatware-detection.ps1
#>

param(
    [switch]$Verbose
)

# ─── SETUP ──────────────────────────────────────────────────────────────
Write-Host "`n╔═══════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║   Bloatware Detection & Removal System Test Suite       ║" -ForegroundColor Cyan
Write-Host "║   v1.0 - Multi-Source Detection Validation               ║" -ForegroundColor Cyan
Write-Host "╚═══════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

$testPassed = 0
$testFailed = 0
$tests = @()

function Test-Configuration {
    param([string]$Name, [scriptblock]$Test)

    Write-Host "Testing: $Name..." -ForegroundColor Yellow
    try {
        $result = & $Test
        if ($result) {
            Write-Host "  ✓ PASS`n" -ForegroundColor Green
            $script:testPassed++
        }
        else {
            Write-Host "  ✗ FAIL`n" -ForegroundColor Red
            $script:testFailed++
        }
    }
    catch {
        Write-Host "  ✗ ERROR: $_`n" -ForegroundColor Red
        $script:testFailed++
    }
}

# ─── TEST 1: Configuration Files Exist ──────────────────────────────────
Test-Configuration "Config files exist" {
    $configs = @(
        'config/lists/bloatware/protected-packages.json',
        'config/lists/bloatware/dependency-matrix.json',
        'config/lists/bloatware/bloatware-detection.json'
    )
    $allExist = $true
    foreach ($cfg in $configs) {
        if (-not (Test-Path $cfg)) {
            Write-Host "    Missing: $cfg" -ForegroundColor Red
            $allExist = $false
        }
        else {
            Write-Host "    Found: $cfg" -ForegroundColor Gray
        }
    }
    $allExist
}

# ─── TEST 2: JSON Config Validity ──────────────────────────────────────
Test-Configuration "Protected packages JSON valid" {
    $json = Get-Content 'config/lists/bloatware/protected-packages.json' | ConvertFrom-Json
    if ($json -and $json.critical_dependencies) {
        Write-Host "    Entries: $($json.critical_dependencies.PSObject.Properties.Count)" -ForegroundColor Gray
        $true
    }
    else { $false }
}

Test-Configuration "Dependency matrix JSON valid" {
    $json = Get-Content 'config/lists/bloatware/dependency-matrix.json' | ConvertFrom-Json
    if ($json -and $json.dependencies) {
        Write-Host "    Entries: $($json.dependencies.PSObject.Properties.Count)" -ForegroundColor Gray
        $true
    }
    else { $false }
}

Test-Configuration "Bloatware detection config valid" {
    $json = Get-Content 'config/lists/bloatware/bloatware-detection.json' | ConvertFrom-Json
    if ($json -and $json.categories) {
        $appCount = 0
        foreach ($cat in $json.categories.PSObject.Properties) {
            $appCount += $cat.Value.apps.Count
        }
        Write-Host "    Categories: $($json.categories.PSObject.Properties.Count)" -ForegroundColor Gray
        Write-Host "    Total apps: $appCount" -ForegroundColor Gray
        $true
    }
    else { $false }
}

# ─── TEST 3: Detection Accuracy ────────────────────────────────────────
Write-Host "`n╔═══════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║         Multi-Source Detection Test (Current System)     ║" -ForegroundColor Cyan
Write-Host "╚═══════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

# Check AppX packages
Write-Host "Scanning AppX packages..." -ForegroundColor Yellow
try {
    $appx = Get-AppxPackage -AllUsers -ErrorAction Stop | Select-Object -ExpandProperty Name
    Write-Host "  Found: $($appx.Count) AppX packages" -ForegroundColor Gray

    # Cross-reference with bloatware list
    $bloatConfig = Get-Content 'config/lists/bloatware/bloatware-detection.json' | ConvertFrom-Json
    $patterns = @()
    foreach ($cat in $bloatConfig.categories.PSObject.Properties) {
        foreach ($app in $cat.Value.apps) {
            if ($app.removable -ne $false) {
                $patterns += $app.name
            }
        }
    }

    $detected = 0
    Write-Host "  Bloatware patterns to check: $($patterns.Count)" -ForegroundColor Gray
    foreach ($pattern in $patterns | Select-Object -First 10) {
        $matches = $appx | Where-Object { $_ -like $pattern }
        if ($matches) {
            Write-Host "    ✓ Found: $($matches | Select-Object -First 1)" -ForegroundColor Green
            $detected++
        }
    }
    Write-Host "  Detection rate: $detected / 10 checked" -ForegroundColor Green
}
catch {
    Write-Host "  ✗ Error: $_" -ForegroundColor Red
}

# Check Provisioned packages
Write-Host "`nScanning Provisioned packages..." -ForegroundColor Yellow
try {
    $prov = Get-AppxProvisionedPackage -Online -ErrorAction Stop | Select-Object -ExpandProperty PackageName
    Write-Host "  Found: $($prov.Count) Provisioned packages" -ForegroundColor Gray
}
catch {
    Write-Host "  Note: Provisioned packages not available on this system" -ForegroundColor Gray
}

# Check Registry installed apps
Write-Host "`nScanning Registry (Win32 programs)..." -ForegroundColor Yellow
try {
    $reg = @(
        Get-ChildItem "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty PSChildName,
        Get-ChildItem "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty PSChildName
    )
    Write-Host "  Found: $($reg.Count) Registry entries" -ForegroundColor Gray
}
catch {
    Write-Host "  Note: Registry query had issues: $_" -ForegroundColor Gray
}

# ─── TEST 4: Protected Packages Not Listed for Removal ────────────────
Write-Host "`n╔═══════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║         Safety Validation (Protected Packages)           ║" -ForegroundColor Cyan
Write-Host "╚═══════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

Test-Configuration "Protected packages not in removal list" {
    $protected = Get-Content 'config/lists/bloatware/protected-packages.json' | ConvertFrom-Json
    $bloatware = Get-Content 'config/lists/bloatware/bloatware-detection.json' | ConvertFrom-Json

    $protectedNames = @()
    foreach ($section in $protected.PSObject.Properties) {
        foreach ($pkg in $section.Value.PSObject.Properties) {
            if ($pkg.Value.protected -eq $true) {
                $protectedNames += $pkg.Name
            }
        }
    }

    $violations = @()
    foreach ($cat in $bloatware.categories.PSObject.Properties) {
        foreach ($app in $cat.Value.apps) {
            if ($protectedNames -contains $app.name) {
                $violations += $app.name
            }
        }
    }

    if ($violations.Count -eq 0) {
        Write-Host "    ✓ No protected packages in removal list" -ForegroundColor Green
        $true
    }
    else {
        Write-Host "    ✗ CRITICAL: Protected packages in removal list!" -ForegroundColor Red
        foreach ($v in $violations) {
            Write-Host "      - $v" -ForegroundColor Red
        }
        $false
    }
}

# ─── TEST 5: Dependency Information Complete ────────────────────────────
Test-Configuration "Dependency matrix populated" {
    $deps = Get-Content 'config/lists/bloatware/dependency-matrix.json' | ConvertFrom-Json
    if ($deps.dependencies -and $deps.dependencies.PSObject.Properties.Count -gt 3) {
        Write-Host "    Dependencies mapped: $($deps.dependencies.PSObject.Properties.Count)" -ForegroundColor Gray
        $true
    }
    else { $false }
}

# ─── SUMMARY ────────────────────────────────────────────────────────────
Write-Host "`n╔═══════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║                    Test Summary                           ║" -ForegroundColor Cyan
Write-Host "╚═══════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

Write-Host "Configuration Tests:  $testPassed passed, $testFailed failed" -ForegroundColor $(if ($testFailed -eq 0) { 'Green' } else { 'Red' })

if ($testFailed -eq 0) {
    Write-Host "`n✓ All tests PASSED - Bloatware system ready for deployment`n" -ForegroundColor Green
}
else {
    Write-Host "`n✗ Some tests FAILED - Fix issues before running maintenance`n" -ForegroundColor Red
}

Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  1. Review detected bloatware above" -ForegroundColor Gray
Write-Host "  2. Run: pwsh -File .\MaintenanceOrchestrator.ps1" -ForegroundColor Gray
Write-Host "  3. Review HTML report for removal results" -ForegroundColor Gray
Write-Host "  4. Re-run this test after cleanup to verify success" -ForegroundColor Gray
Write-Host ""
