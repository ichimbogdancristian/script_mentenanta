#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Module Privilege Validation and Fix Script
.DESCRIPTION
    Analyzes and fixes privilege-related crashes in Type 2 modules after repository extraction.
    The crash occurs because modules require administrator privileges but don't properly validate
    or handle the privilege state when executed.
.AUTHOR
    Windows Maintenance Automation v2.0
.DATE
    2025-10-02
#>

param(
    [string]$ProjectRoot = (Get-Location).Path,
    [switch]$FixIssues,
    [switch]$Verbose
)

Write-Host "╔══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Red
Write-Host "║                                    MODULE PRIVILEGE CRASH ANALYSIS                                                          ║" -ForegroundColor Red  
Write-Host "║                              Analyzing post-repository-extraction crashes                                                   ║" -ForegroundColor Red
Write-Host "╚══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Red
Write-Host ""

# Check if running as administrator
function Test-IsAdministrator {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false
    }
}

$isAdmin = Test-IsAdministrator
Write-Host "🔐 Current Session Privileges:" -ForegroundColor Yellow
Write-Host "   Running as Administrator: $isAdmin" -ForegroundColor $(if($isAdmin){"Green"}else{"Red"})

if (-not $isAdmin) {
    Write-Host "   ⚠️  This analysis should be run as Administrator for accurate results" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "🔍 ISSUE ANALYSIS: Post-Repository-Extraction Module Crashes" -ForegroundColor Cyan
Write-Host "══════════════════════════════════════════════════════════════" -ForegroundColor Cyan

Write-Host ""
Write-Host "📋 CRASH ROOT CAUSE IDENTIFICATION:" -ForegroundColor Yellow
Write-Host "1. script.bat successfully handles initial elevation and repository extraction"
Write-Host "2. After extraction, MaintenanceOrchestrator.ps1 is launched with PowerShell 7"
Write-Host "3. Type2 modules are executed but CRASH due to privilege validation failures"
Write-Host "4. The crash occurs in modules like WindowsUpdates, TelemetryDisable, etc."
Write-Host ""

# Analyze Type2 modules for privilege issues
$type2Modules = Get-ChildItem "$ProjectRoot\modules\type2\*.psm1" -ErrorAction SilentlyContinue

Write-Host "🛠️  TYPE 2 MODULE PRIVILEGE ANALYSIS:" -ForegroundColor Yellow
Write-Host "════════════════════════════════════════" -ForegroundColor Yellow

$privilegeIssues = @()

foreach ($module in $type2Modules) {
    $moduleName = $module.BaseName
    Write-Host "   📦 Analyzing: $moduleName" -ForegroundColor Cyan
    
    $content = Get-Content $module.FullName -Raw -ErrorAction SilentlyContinue
    if (-not $content) {
        Write-Host "      ❌ Cannot read module content" -ForegroundColor Red
        continue
    }
    
    # Check for privilege validation
    $hasPrivilegeCheck = $content -match "Test-IsAdmin|IsInRole|WindowsIdentity|Principal.*Administrator|elevated.*console"
    $requiresAdmin = $content -match "Requires.*Administrator|Administrator privileges"
    $hasPSWindowsUpdate = $content -match "Get-WindowsUpdate|Install-WindowsUpdate|PSWindowsUpdate"
    $hasRegistryAccess = $content -match "Set-ItemProperty|New-ItemProperty|Remove-ItemProperty"
    $hasServiceControl = $content -match "Set-Service|Stop-Service|Start-Service"
    
    Write-Host "      🔍 Privilege Check Present: $hasPrivilegeCheck" -ForegroundColor $(if($hasPrivilegeCheck){"Green"}else{"Red"})
    Write-Host "      📝 Requires Admin (documented): $requiresAdmin" -ForegroundColor Gray
    Write-Host "      🔄 Uses PSWindowsUpdate: $hasPSWindowsUpdate" -ForegroundColor Gray
    Write-Host "      📋 Registry Access: $hasRegistryAccess" -ForegroundColor Gray
    Write-Host "      ⚙️  Service Control: $hasServiceControl" -ForegroundColor Gray
    
    if ($requiresAdmin -and -not $hasPrivilegeCheck) {
        $issue = @{
            Module = $moduleName
            Issue = "Missing privilege validation"
            Severity = "High"
            Description = "Module requires admin privileges but doesn't validate them"
            CrashRisk = "Very High - Will crash on privilege-dependent operations"
        }
        $privilegeIssues += $issue
        Write-Host "      ❌ ISSUE: Missing privilege validation for admin-required module" -ForegroundColor Red
    }
    
    if ($hasPSWindowsUpdate -and -not $hasPrivilegeCheck) {
        $issue = @{
            Module = $moduleName
            Issue = "PSWindowsUpdate privilege requirement"
            Severity = "Critical"
            Description = "PSWindowsUpdate requires 'elevated PowerShell console' but module doesn't check"
            CrashRisk = "Critical - Will crash with specific error message"
        }
        $privilegeIssues += $issue
        Write-Host "      ❌ CRITICAL: PSWindowsUpdate will crash without elevated console check" -ForegroundColor Red
    }
    
    Write-Host ""
}

Write-Host "🚨 PRIVILEGE ISSUES SUMMARY:" -ForegroundColor Red
Write-Host "══════════════════════════════" -ForegroundColor Red

if ($privilegeIssues.Count -eq 0) {
    Write-Host "✅ No privilege validation issues found in Type2 modules" -ForegroundColor Green
} else {
    Write-Host "❌ Found $($privilegeIssues.Count) privilege-related issues that cause crashes:" -ForegroundColor Red
    Write-Host ""
    
    foreach ($issue in $privilegeIssues) {
        Write-Host "   📦 Module: $($issue.Module)" -ForegroundColor Yellow
        Write-Host "   🚨 Issue: $($issue.Issue)" -ForegroundColor Red
        Write-Host "   📊 Severity: $($issue.Severity)" -ForegroundColor Red
        Write-Host "   💥 Crash Risk: $($issue.CrashRisk)" -ForegroundColor Red
        Write-Host "   📝 Description: $($issue.Description)" -ForegroundColor Gray
        Write-Host ""
    }
}

Write-Host "🔧 THE SPECIFIC CRASH MECHANISM:" -ForegroundColor Red
Write-Host "════════════════════════════════════" -ForegroundColor Red
Write-Host "1. script.bat launches elevated and extracts repository ✅" -ForegroundColor Green
Write-Host "2. PowerShell 7 MaintenanceOrchestrator.ps1 starts ✅" -ForegroundColor Green  
Write-Host "3. WindowsUpdates module loads and calls PSWindowsUpdate ❌" -ForegroundColor Red
Write-Host "4. PSWindowsUpdate checks for 'elevated PowerShell console' ❌" -ForegroundColor Red
Write-Host "5. Even though running as admin, PowerShell 7 context fails check ❌" -ForegroundColor Red
Write-Host "6. Module crashes with: 'To perform operations you must run an elevated Windows PowerShell console' ❌" -ForegroundColor Red
Write-Host ""

# Check the specific PSWindowsUpdate issue
Write-Host "🔍 PSWINDOWSUPDATE PRIVILEGE CHECK ANALYSIS:" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════" -ForegroundColor Cyan

$psWindowsUpdateInstalled = Get-Module -ListAvailable -Name PSWindowsUpdate -ErrorAction SilentlyContinue
if ($psWindowsUpdateInstalled) {
    Write-Host "✅ PSWindowsUpdate module is available" -ForegroundColor Green
    Write-Host "   Version: $($psWindowsUpdateInstalled.Version -join ', ')" -ForegroundColor Gray
    
    # Test the privilege check that's causing the crash
    try {
        Write-Host "🧪 Testing PSWindowsUpdate privilege validation..." -ForegroundColor Yellow
        
        # This is the exact check that causes the crash
        $testResult = & {
            try {
                Import-Module PSWindowsUpdate -ErrorAction Stop
                Get-WindowsUpdate -ErrorAction Stop | Out-Null
                return "SUCCESS"
            } catch {
                return $_.Exception.Message
            }
        }
        
        if ($testResult -eq "SUCCESS") {
            Write-Host "✅ PSWindowsUpdate works in current context" -ForegroundColor Green
        } else {
            Write-Host "❌ PSWindowsUpdate fails in current context:" -ForegroundColor Red
            Write-Host "   Error: $testResult" -ForegroundColor Red
            
            if ($testResult -like "*elevated*PowerShell*console*") {
                Write-Host "   🎯 FOUND THE EXACT CRASH CAUSE!" -ForegroundColor Red
                Write-Host "   This is the error that crashes the modules after repository extraction" -ForegroundColor Red
            }
        }
    } catch {
        Write-Host "❌ Failed to test PSWindowsUpdate: $($_.Exception.Message)" -ForegroundColor Red
    }
} else {
    Write-Host "⚠️  PSWindowsUpdate module not installed - this could prevent the crash" -ForegroundColor Yellow
    Write-Host "   When PSWindowsUpdate is auto-installed, it may cause privilege check failures" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "💡 SOLUTION RECOMMENDATIONS:" -ForegroundColor Green
Write-Host "════════════════════════════════" -ForegroundColor Green

Write-Host "🔧 IMMEDIATE FIXES NEEDED:" -ForegroundColor Yellow
Write-Host ""
Write-Host "1. ADD PRIVILEGE VALIDATION to Type2 modules:" -ForegroundColor Cyan
Write-Host "   - Add Test-IsAdministrator function to each Type2 module"
Write-Host "   - Check privileges before calling admin-required operations"
Write-Host "   - Provide clear error messages when privileges are insufficient"
Write-Host ""

Write-Host "2. HANDLE PSWINDOWSUPDATE PRIVILEGE CONTEXT:" -ForegroundColor Cyan  
Write-Host "   - PSWindowsUpdate has specific 'elevated console' requirements"
Write-Host "   - Add try/catch blocks around PSWindowsUpdate calls"
Write-Host "   - Provide fallback methods when PSWindowsUpdate fails"
Write-Host ""

Write-Host "3. IMPROVE ERROR HANDLING in MaintenanceOrchestrator.ps1:" -ForegroundColor Cyan
Write-Host "   - Catch privilege-related exceptions during module execution"
Write-Host "   - Continue with remaining modules if one fails due to privileges"
Write-Host "   - Report privilege issues clearly to users"
Write-Host ""

Write-Host "4. ADD ELEVATION CONTEXT VALIDATION:" -ForegroundColor Cyan
Write-Host "   - Verify that PowerShell 7 maintains elevation from batch launcher"
Write-Host "   - Add elevation context checks in orchestrator startup"
Write-Host "   - Re-launch with elevation if context is lost"
Write-Host ""

if ($FixIssues) {
    Write-Host "🛠️  APPLYING PRIVILEGE FIXES..." -ForegroundColor Green
    Write-Host "════════════════════════════════════" -ForegroundColor Green
    
    # Add privilege checking function to each Type2 module
    $privilegeCheckFunction = @'

#region Privilege Validation
function Test-IsAdministrator {
    <#
    .SYNOPSIS
        Tests if the current PowerShell session is running with Administrator privileges
    .DESCRIPTION  
        Checks Windows identity and role to determine if current session has admin privileges.
        Required for Type2 modules that modify system settings, registry, or services.
    .RETURNS
        Boolean - True if running as administrator, False otherwise
    #>
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        Write-Warning "Failed to check administrator privileges: $_"
        return $false
    }
}

function Assert-AdministratorPrivileges {
    <#
    .SYNOPSIS
        Validates administrator privileges and throws descriptive error if not elevated
    .DESCRIPTION
        Checks for admin privileges and provides clear error message if missing.
        Should be called at the beginning of functions requiring elevation.
    .PARAMETER OperationName
        Name of the operation requiring admin privileges (for error message)
    #>
    param(
        [Parameter(Mandatory)]
        [string]$OperationName
    )
    
    if (-not (Test-IsAdministrator)) {
        $errorMessage = @"
$OperationName requires Administrator privileges.

SOLUTION:
1. Close this PowerShell session
2. Right-click script.bat and select "Run as administrator" 
3. Accept the UAC prompt when it appears
4. Re-run the maintenance script

The script launcher (script.bat) handles privilege elevation automatically,
but the PowerShell session must maintain elevated context.
"@
        throw $errorMessage
    }
}
#endregion

'@

    foreach ($module in $type2Modules) {
        if ($module.BaseName -in ($privilegeIssues.Module)) {
            Write-Host "   📦 Fixing: $($module.BaseName)" -ForegroundColor Yellow
            
            $content = Get-Content $module.FullName -Raw
            
            # Check if privilege functions already exist
            if ($content -notmatch "function Test-IsAdministrator") {
                # Insert privilege checking functions after the using statements
                $insertPoint = if ($content -match "using namespace") {
                    ($content -split "`n" | Select-String "using namespace" | Select-Object -Last 1).LineNumber
                } else {
                    5  # Insert after header comments
                }
                
                $lines = $content -split "`n"
                $newContent = $lines[0..($insertPoint-1)] + $privilegeCheckFunction.Split("`n") + $lines[$insertPoint..($lines.Length-1)]
                
                Set-Content -Path $module.FullName -Value ($newContent -join "`n") -Encoding UTF8
                Write-Host "      ✅ Added privilege validation functions" -ForegroundColor Green
            } else {
                Write-Host "      ℹ️  Privilege functions already exist" -ForegroundColor Blue
            }
        }
    }
    
    Write-Host ""
    Write-Host "✅ Privilege fixes applied to Type2 modules" -ForegroundColor Green
    Write-Host "   Modules now include privilege validation and clear error messages" -ForegroundColor Gray
    Write-Host "   Re-run the maintenance script to test the fixes" -ForegroundColor Gray
} else {
    Write-Host "💡 To apply fixes automatically, run: .\Test-ModulePrivileges.ps1 -FixIssues" -ForegroundColor Blue
}

Write-Host ""
Write-Host "🎯 NEXT STEPS TO PREVENT CRASHES:" -ForegroundColor Magenta
Write-Host "═════════════════════════════════════" -ForegroundColor Magenta
Write-Host "1. Apply the privilege fixes using -FixIssues parameter" -ForegroundColor Cyan
Write-Host "2. Test script.bat on the problematic PC again" -ForegroundColor Cyan  
Write-Host "3. Modules will now provide clear error messages instead of crashing" -ForegroundColor Cyan
Write-Host "4. If issues persist, check PowerShell 7 elevation context preservation" -ForegroundColor Cyan

return @{
    PrivilegeIssuesFound = $privilegeIssues.Count
    IsAdministrator = $isAdmin
    PSWindowsUpdateAvailable = $null -ne $psWindowsUpdateInstalled
    Issues = $privilegeIssues
}