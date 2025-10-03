#Requires -Version 5.1

<#
.SYNOPSIS
    PowerShell Compatibility Wrapper for Windows Maintenance Automation

.DESCRIPTION
    This wrapper ensures PowerShell 7+ is available for running the MaintenanceOrchestrator.ps1
    On fresh Windows systems, it will attempt to install PowerShell 7 automatically.
    Falls back to basic maintenance tasks if PowerShell 7 installation fails.

.PARAMETER DryRun
    Run in simulation mode without making system changes

.PARAMETER NonInteractive
    Run without user prompts

.PARAMETER TaskNumbers
    Specific task numbers to execute

.PARAMETER PostRestart
    Indicates this is a post-restart execution
#>

param(
    [switch]$DryRun,
    [switch]$NonInteractive,
    [string]$TaskNumbers,
    [switch]$PostRestart
)

# Function to write timestamped log entries
function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logEntry = "[$timestamp] [$Level] [COMPATIBILITY] $Message"
    Write-Host $logEntry
    
    # Also write to main maintenance log if it exists
    $logFile = Join-Path $PSScriptRoot 'temp_files\logs\maintenance.log'
    if (Test-Path (Split-Path $logFile)) {
        $logEntry | Add-Content -Path $logFile -ErrorAction SilentlyContinue
    }
}

Write-Log "Windows Maintenance Automation - Compatibility Wrapper v2.1"
Write-Log "PowerShell Version: $($PSVersionTable.PSVersion) on $($PSVersionTable.PSEdition)"

# Check if PowerShell 7+ is available
$pwsh7Available = $false
$pwsh7Path = $null

# Try to find PowerShell 7
$pwsh7Locations = @(
    'pwsh.exe',
    "$env:ProgramFiles\PowerShell\7\pwsh.exe",
    "${env:ProgramFiles(x86)}\PowerShell\7\pwsh.exe",
    "$env:LOCALAPPDATA\Microsoft\WindowsApps\pwsh.exe",
    "$env:ProgramFiles\PowerShell\pwsh.exe"
)

foreach ($location in $pwsh7Locations) {
    try {
        if (Get-Command $location -ErrorAction SilentlyContinue) {
            $version = & $location -Command '$PSVersionTable.PSVersion.ToString()' 2>$null
            if ($version -and [version]$version.Split('-')[0] -ge [version]'7.0') {
                $pwsh7Available = $true
                $pwsh7Path = $location
                Write-Log "Found PowerShell 7+ at: $location (Version: $version)" 'SUCCESS'
                break
            }
        }
    }
    catch {
        # Continue searching
    }
}

if (-not $pwsh7Available) {
    Write-Log "PowerShell 7+ not found. Attempting automatic installation..." 'WARN'
    
    # Try to install PowerShell 7 via winget
    try {
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            Write-Log "Installing PowerShell 7 via winget..." 'INFO'
            $result = winget install --id Microsoft.PowerShell --silent --accept-package-agreements --accept-source-agreements 2>&1
            
            if ($LASTEXITCODE -eq 0) {
                Write-Log "PowerShell 7 installation completed via winget" 'SUCCESS'
                
                # Try to find it again
                Start-Sleep -Seconds 3
                foreach ($location in $pwsh7Locations) {
                    try {
                        if (Get-Command $location -ErrorAction SilentlyContinue) {
                            $version = & $location -Command '$PSVersionTable.PSVersion.ToString()' 2>$null
                            if ($version -and [version]$version.Split('-')[0] -ge [version]'7.0') {
                                $pwsh7Available = $true
                                $pwsh7Path = $location
                                Write-Log "PowerShell 7 now available at: $location" 'SUCCESS'
                                break
                            }
                        }
                    }
                    catch { }
                }
            }
            else {
                Write-Log "PowerShell 7 installation via winget failed" 'ERROR'
            }
        }
        else {
            Write-Log "Winget not available for automatic PowerShell 7 installation" 'WARN'
        }
    }
    catch {
        Write-Log "Failed to install PowerShell 7: $_" 'ERROR'
    }
}

# If PowerShell 7+ is available, use the full orchestrator
if ($pwsh7Available) {
    Write-Log "Using PowerShell 7+ for full maintenance orchestrator" 'INFO'
    
    $orchestratorPath = Join-Path $PSScriptRoot 'MaintenanceOrchestrator.ps1'
    
    if (Test-Path $orchestratorPath) {
        $arguments = @('-ExecutionPolicy', 'Bypass', '-File', $orchestratorPath)
        
        if ($DryRun) { $arguments += '-DryRun' }
        if ($NonInteractive) { $arguments += '-NonInteractive' }
        if ($TaskNumbers) { $arguments += @('-TaskNumbers', $TaskNumbers) }
        if ($PostRestart) { $arguments += '-PostRestart' }
        
        Write-Log "Executing: $pwsh7Path $($arguments -join ' ')" 'DEBUG'
        
        try {
            & $pwsh7Path @arguments
            $exitCode = $LASTEXITCODE
            Write-Log "MaintenanceOrchestrator.ps1 completed with exit code: $exitCode" 'INFO'
            exit $exitCode
        }
        catch {
            Write-Log "Error executing MaintenanceOrchestrator.ps1: $_" 'ERROR'
            exit 1
        }
    }
    else {
        Write-Log "MaintenanceOrchestrator.ps1 not found at: $orchestratorPath" 'ERROR'
        exit 1
    }
}
else {
    # Fallback: Basic maintenance using Windows PowerShell 5.1
    Write-Log "PowerShell 7 not available. Running basic maintenance with Windows PowerShell 5.1" 'WARN'
    
    if (-not $NonInteractive) {
        Write-Host ""
        Write-Host "===============================================================================" -ForegroundColor Yellow
        Write-Host " BASIC MAINTENANCE MODE" -ForegroundColor Yellow
        Write-Host "===============================================================================" -ForegroundColor Yellow
        Write-Host " PowerShell 7+ is required for full maintenance features."
        Write-Host " Running in basic maintenance mode with limited functionality."
        Write-Host ""
        Write-Host " To get full functionality, please install PowerShell 7:"
        Write-Host " https://github.com/PowerShell/PowerShell/releases/latest"
        Write-Host "===============================================================================" -ForegroundColor Yellow
        Write-Host ""
    }
    
    Write-Log "Starting basic maintenance tasks..." 'INFO'
    
    # Basic system information collection
    try {
        Write-Log "Collecting basic system information..." 'INFO'
        $computerInfo = Get-ComputerInfo -ErrorAction SilentlyContinue
        if ($computerInfo) {
            Write-Log "System: $($computerInfo.WindowsProductName) $($computerInfo.WindowsVersion)" 'INFO'
            Write-Log "Computer: $($computerInfo.CsName)" 'INFO'
        }
    }
    catch {
        Write-Log "Failed to collect system information: $_" 'ERROR'
    }
    
    # Basic Windows Update check
    if (-not $DryRun) {
        try {
            Write-Log "Checking for Windows Updates..." 'INFO'
            if (Get-Module -ListAvailable -Name PSWindowsUpdate) {
                Import-Module PSWindowsUpdate -Force
                $updates = Get-WUList -ErrorAction SilentlyContinue
                if ($updates) {
                    Write-Log "Found $($updates.Count) available updates" 'INFO'
                }
                else {
                    Write-Log "No updates available" 'SUCCESS'
                }
            }
            else {
                Write-Log "PSWindowsUpdate module not available" 'WARN'
            }
        }
        catch {
            Write-Log "Failed to check Windows Updates: $_" 'ERROR'
        }
    }
    else {
        Write-Log "DRY-RUN: Skipping Windows Update check" 'INFO'
    }
    
    Write-Log "Basic maintenance completed" 'SUCCESS'
    
    if (-not $NonInteractive) {
        Write-Host ""
        Write-Host "Basic maintenance completed. For full features, install PowerShell 7+." -ForegroundColor Green
        Read-Host "Press Enter to continue"
    }
    
    exit 0
}