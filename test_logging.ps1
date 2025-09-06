# Simple test script to verify enhanced logging functionality
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$global:LogFile = Join-Path $ScriptDir "test_logging.log"

# Simplified versions of the logging functions for testing
function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR', 'SUCCESS', 'PROGRESS', 'ACTION', 'COMMAND')]
        [string]$Level = 'INFO'
    )
    
    $timestamp = Get-Date -Format 'MM/dd/yyyy HH:mm:ss'
    $logEntry = "[$timestamp] [$Level] $Message"
    
    # Write to file with enhanced error handling
    try {
        Add-Content -Path $global:LogFile -Value $logEntry -ErrorAction SilentlyContinue -Encoding UTF8
    }
    catch {
        Write-Host "Failed to write to log file: $_" -ForegroundColor Red
    }
    
    # Write to console with enhanced color coding
    $color = switch ($Level) {
        'INFO' { 'White' }
        'WARN' { 'Yellow' }
        'ERROR' { 'Red' }
        'SUCCESS' { 'Green' }
        'PROGRESS' { 'Cyan' }
        'ACTION' { 'Magenta' }
        'COMMAND' { 'DarkCyan' }
        default { 'White' }
    }
    
    Write-Host $logEntry -ForegroundColor $color
    
    # For important actions, also write to host using Write-Output for comprehensive logging
    if ($Level -in @('ACTION', 'COMMAND', 'ERROR', 'SUCCESS')) {
        Write-Output $logEntry
    }
}

function Write-ActionLog {
    param(
        [string]$Action,
        [string]$Details = "",
        [string]$Category = "General",
        [ValidateSet('START', 'SUCCESS', 'FAILURE', 'INFO')]
        [string]$Status = 'INFO'
    )
    
    $contextInfo = ""
    if ($Details) {
        $contextInfo = " | Details: $Details"
    }
    
    $fullMessage = "[$Category] $Action$contextInfo"
    
    $logLevel = switch ($Status) {
        'START' { 'ACTION' }
        'SUCCESS' { 'SUCCESS' }
        'FAILURE' { 'ERROR' }
        'INFO' { 'INFO' }
        default { 'INFO' }
    }
    
    Write-Log $fullMessage $logLevel
}

function Write-CommandLog {
    param(
        [string]$Command,
        [string[]]$Arguments = @(),
        [string]$Context = "",
        [ValidateSet('START', 'SUCCESS', 'FAILURE')]
        [string]$Status = 'START'
    )
    
    $fullCommand = $Command
    if ($Arguments.Count -gt 0) {
        $argString = $Arguments -join " "
        $fullCommand = "$Command $argString"
    }
    
    $contextInfo = if ($Context) { " | Context: $Context" } else { "" }
    $message = "COMMAND: $fullCommand$contextInfo"
    
    $logLevel = switch ($Status) {
        'START' { 'COMMAND' }
        'SUCCESS' { 'SUCCESS' }
        'FAILURE' { 'ERROR' }
        default { 'COMMAND' }
    }
    
    Write-Log $message $logLevel
}

# Test the logging functions
Write-Host "=== Testing Enhanced Logging System ===" -ForegroundColor Cyan

# Test basic logging
Write-Log "Testing basic INFO logging" 'INFO'
Write-Log "Testing WARNING logging" 'WARN'
Write-Log "Testing ERROR logging" 'ERROR'
Write-Log "Testing SUCCESS logging" 'SUCCESS'
Write-Log "Testing ACTION logging" 'ACTION'
Write-Log "Testing COMMAND logging" 'COMMAND'

# Test action logging
Write-ActionLog -Action "Testing action logging" -Details "Sample details for testing" -Category "Testing" -Status 'START'
Write-ActionLog -Action "Action completed" -Details "Testing successful" -Category "Testing" -Status 'SUCCESS'
Write-ActionLog -Action "Action failed" -Details "Testing failure scenario" -Category "Testing" -Status 'FAILURE'

# Test command logging
Write-CommandLog -Command "dir" -Arguments @("C:\", "/B") -Context "Testing directory listing" -Status 'START'
Write-CommandLog -Command "dir" -Arguments @("C:\", "/B") -Context "Testing directory listing" -Status 'SUCCESS'

Write-Log "Logging test completed. Check test_logging.log for results." 'SUCCESS'

# Show log file contents
if (Test-Path $global:LogFile) {
    Write-Host "`n=== Log File Contents ===" -ForegroundColor Cyan
    Get-Content $global:LogFile | ForEach-Object { Write-Host $_ }
} else {
    Write-Host "Log file was not created!" -ForegroundColor Red
}
