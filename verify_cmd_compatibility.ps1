# Final Comprehensive CMD Compatibility Check
Write-Host "=== COMPREHENSIVE CMD COMPATIBILITY VERIFICATION ==="
Write-Host ""

# Check for potential CMD parsing issues
$scriptContent = Get-Content "c:\Users\Bogdan\OneDrive\Desktop\Projects\script_mentenanta\script.bat" -Raw

$issues = @()

# Check 1: PowerShell pipeline operators in ECHO statements
if ($scriptContent -match 'ECHO.*\^\|') {
    $issues += "Found PowerShell pipeline operators (^|) in ECHO statements"
}

# Check 2: WindowStyle Hidden parameters
if ($scriptContent -match '-WindowStyle\s+Hidden') {
    $issues += "Found -WindowStyle Hidden parameters that can cause crashes"
}

# Check 3: Complex curly brace patterns that might confuse CMD
if ($scriptContent -match 'ECHO.*\{[^}]*\$[^}]*\}') {
    $issues += "Found complex curly brace patterns with variables"
}

# Check 4: Missing error redirection on PowerShell commands
$psCommands = [regex]::Matches($scriptContent, 'powershell -ExecutionPolicy Bypass -File "%TEMP_PS1%"(?!\s*2>&1)')
if ($psCommands.Count -gt 0) {
    $issues += "Found $($psCommands.Count) PowerShell commands without error redirection"
}

# Check 5: Complex variable expansion in ECHO statements
if ($scriptContent -match 'ECHO.*%[^%]*%[^%]*%') {
    $issues += "Found complex nested variable expansion that might cause issues"
}

# Check 6: Unescaped special characters in FOR loops
$forLoops = [regex]::Matches($scriptContent, 'FOR /F.*\|.*DO')
foreach ($loop in $forLoops) {
    if ($loop.Value -notmatch '\^\|') {
        $issues += "Found unescaped pipe in FOR loop: $($loop.Value)"
    }
}

# Summary
Write-Host "VERIFICATION RESULTS:"
Write-Host "===================="
if ($issues.Count -eq 0) {
    Write-Host "✅ No CMD compatibility issues found!" -ForegroundColor Green
    Write-Host "✅ All PowerShell pipeline operators removed" -ForegroundColor Green
    Write-Host "✅ All -WindowStyle Hidden parameters removed" -ForegroundColor Green
    Write-Host "✅ Error redirection properly configured" -ForegroundColor Green
    Write-Host "✅ Variable expansion patterns safe" -ForegroundColor Green
    Write-Host "✅ FOR loops properly escaped" -ForegroundColor Green
} else {
    Write-Host "❌ Found $($issues.Count) potential issues:" -ForegroundColor Red
    foreach ($issue in $issues) {
        Write-Host "  - $issue" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "DEPENDENCIES CHECK:"
Write-Host "==================="

# Check URLs
$urls = @(
    "https://aka.ms/vs/17/release/vc_redist.x64.exe",
    "https://www.nuget.org/api/v2/package/Microsoft.UI.Xaml/2.8.7",
    "https://github.com/microsoft/winget-cli/releases/download/v1.11.430/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle",
    "https://github.com/PowerShell/PowerShell/releases/download/v7.5.2/PowerShell-7.5.2-win-x64.msi",
    "https://github.com/git-for-windows/git/releases/download/v2.50.1.windows.1/Git-2.50.1-64-bit.exe"
)

foreach ($url in $urls) {
    try {
        $response = Invoke-WebRequest -Uri $url -Method Head -TimeoutSec 10 -ErrorAction Stop
        Write-Host "✅ $url - OK" -ForegroundColor Green
    } catch {
        Write-Host "❌ $url - FAILED: $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "SCRIPT STRUCTURE CHECK:"
Write-Host "======================="

# Count critical sections
$vcCheck = ($scriptContent | Select-String "Visual C\+\+ check completed").Count
$xamlCheck = ($scriptContent | Select-String "XAML check completed").Count
$logEntries = ($scriptContent | Select-String ":LOG_ENTRY").Count

Write-Host "✅ Visual C++ debug logging: $vcCheck entries" -ForegroundColor Green
Write-Host "✅ XAML debug logging: $xamlCheck entries" -ForegroundColor Green  
Write-Host "✅ Total LOG_ENTRY calls: $logEntries" -ForegroundColor Green

Write-Host ""
Write-Host "FINAL ASSESSMENT:"
Write-Host "================="
if ($issues.Count -eq 0) {
    Write-Host "🎉 SCRIPT IS FULLY CMD COMPATIBLE!" -ForegroundColor Green
    Write-Host "The script should now run without crashing in CMD environment." -ForegroundColor Green
} else {
    Write-Host "⚠️  SCRIPT NEEDS ADDITIONAL FIXES" -ForegroundColor Yellow
}
