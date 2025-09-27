# Bootstrap.psm1 - Initial setup and environment bootstrap module
# Handles PowerShell version management, basic environment setup, and initial configuration

# ================================================================
# Function: Initialize-BootstrapEnvironment
# ================================================================
# Purpose: Set up the basic environment for the maintenance system
# ================================================================
function Initialize-BootstrapEnvironment {
    param(
        [string]$WorkingDirectory = (Get-Location).Path,
        [string]$LogFilePath
    )

    # Script path detection
    $script:ScriptFullPath = $MyInvocation.PSCommandPath
    $script:ScriptDir = Split-Path -Parent $script:ScriptFullPath
    $script:ScriptName = Split-Path -Leaf $script:ScriptFullPath

    # Working directory setup
    $script:WorkingDirectory = $WorkingDirectory

    # Log file setup
    if ($LogFilePath) {
        $script:LogFile = $LogFilePath
    }
    else {
        $script:LogFile = Join-Path $script:WorkingDirectory 'maintenance.log'
    }

    # Ensure log directory exists
    $logDir = Split-Path $script:LogFile -Parent
    if (-not (Test-Path $logDir)) {
        New-Item -Path $logDir -ItemType Directory -Force | Out-Null
    }

    # Temp folder setup
    $script:TempFolder = Join-Path $script:WorkingDirectory 'temp'
    if (-not (Test-Path $script:TempFolder)) {
        New-Item -Path $script:TempFolder -ItemType Directory -Force | Out-Null
    }

    # Global temp folder for modules to use
    $global:TempFolder = $script:TempFolder
    $global:LogFile = $script:LogFile
    $global:WorkingDirectory = $script:WorkingDirectory

    return @{
        ScriptDir = $script:ScriptDir
        WorkingDirectory = $script:WorkingDirectory
        LogFile = $script:LogFile
        TempFolder = $script:TempFolder
    }
}

# ================================================================
# Function: Test-PowerShellVersion
# ================================================================
# Purpose: Check PowerShell version and handle compatibility
# ================================================================
function Test-PowerShellVersion {
    param(
        [int]$MinimumVersion = 5,
        [int]$RecommendedVersion = 7
    )

    $currentVersion = $PSVersionTable.PSVersion.Major
    $isCompatible = $currentVersion -ge $MinimumVersion
    $isRecommended = $currentVersion -ge $RecommendedVersion

    $result = @{
        CurrentVersion = $currentVersion
        MinimumVersion = $MinimumVersion
        RecommendedVersion = $RecommendedVersion
        IsCompatible = $isCompatible
        IsRecommended = $isRecommended
        NeedsUpgrade = -not $isRecommended
    }

    if (-not $isCompatible) {
        Write-Warning "PowerShell $MinimumVersion or higher is required. Current version: $currentVersion"
        $result.Status = 'Incompatible'
    }
    elseif (-not $isRecommended) {
        Write-Warning "PowerShell $RecommendedVersion is recommended for optimal performance. Current version: $currentVersion"
        $result.Status = 'CompatibleButNotRecommended'
    }
    else {
        $result.Status = 'Recommended'
    }

    return $result
}

# ================================================================
# Function: Install-PowerShell7
# ================================================================
# Purpose: Attempt to install PowerShell 7 if not available
# ================================================================
function Install-PowerShell7 {
    param(
        [switch]$Force,
        [switch]$Quiet
    )

    $psVersion = Test-PowerShellVersion -RecommendedVersion 7

    if ($psVersion.IsRecommended -and -not $Force) {
        if (-not $Quiet) {
            Write-Host "PowerShell 7 is already available" -ForegroundColor Green
        }
        return $true
    }

    if (-not $Quiet) {
        Write-Host "Attempting to install PowerShell 7..." -ForegroundColor Yellow
    }

    try {
        # Method 1: Use winget if available
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            if (-not $Quiet) { Write-Host "Using winget to install PowerShell 7..." }
            $process = Start-Process winget -ArgumentList "install --id Microsoft.PowerShell --accept-source-agreements --accept-package-agreements -e" -NoNewWindow -Wait -PassThru
            if ($process.ExitCode -eq 0) {
                if (-not $Quiet) { Write-Host "PowerShell 7 installed successfully via winget" -ForegroundColor Green }
                return $true
            }
        }

        # Method 2: Use MSI installer download
        if (-not $Quiet) { Write-Host "Downloading PowerShell 7 MSI installer..." }
        $msiUrl = "https://github.com/PowerShell/PowerShell/releases/latest/download/PowerShell-7.4.5-win-x64.msi"
        $msiPath = Join-Path $global:TempFolder "PowerShell7.msi"

        Invoke-WebRequest -Uri $msiUrl -OutFile $msiPath -ErrorAction Stop

        if (-not $Quiet) { Write-Host "Installing PowerShell 7..." }
        $process = Start-Process msiexec.exe -ArgumentList "/i `"$msiPath`" /quiet /norestart" -NoNewWindow -Wait -PassThru

        if ($process.ExitCode -eq 0) {
            if (-not $Quiet) { Write-Host "PowerShell 7 installed successfully" -ForegroundColor Green }
            return $true
        }
        else {
            if (-not $Quiet) { Write-Warning "MSI installation failed with exit code: $($process.ExitCode)" }
        }
    }
    catch {
        if (-not $Quiet) { Write-Warning "Failed to install PowerShell 7: $_" }
    }

    return $false
}

# ================================================================
# Function: Initialize-GlobalConfig
# ================================================================
# Purpose: Set up the global configuration object
# ================================================================
function Initialize-GlobalConfig {
    $global:Config = @{
        # Skip flags for tasks
        SkipBloatwareRemoval    = $false
        SkipEssentialApps       = $false
        SkipWindowsUpdates      = $false
        SkipTelemetryDisable    = $false
        SkipSystemRestore       = $false
        SkipEventLogAnalysis    = $false
        SkipPendingRestartCheck = $false
        SkipSystemHealthRepair  = $false
        SkipPackageUpdates      = $false

        # Feature flags
        EnableVerboseLogging    = $false
        EnableParallelProcessing = $true
        EnableCaching          = $true

        # Customization
        CustomEssentialApps     = @()
        CustomBloatwareList     = @()
        ExcludeTasks           = @()

        # Performance settings
        MaxParallelTasks       = 3
        TaskTimeoutSeconds     = 300
        RetryAttempts         = 2
    }

    return $global:Config
}

# ================================================================
# Function: Test-ExecutionPolicy
# ================================================================
# Purpose: Check and set execution policy if needed
# ================================================================
function Test-ExecutionPolicy {
    param(
        [string]$RequiredPolicy = "RemoteSigned"
    )

    $currentPolicy = Get-ExecutionPolicy

    if ($currentPolicy -eq $RequiredPolicy) {
        return @{ Status = 'OK'; CurrentPolicy = $currentPolicy }
    }

    try {
        Set-ExecutionPolicy -ExecutionPolicy $RequiredPolicy -Scope Process -Force
        return @{ Status = 'Set'; CurrentPolicy = $RequiredPolicy; PreviousPolicy = $currentPolicy }
    }
    catch {
        return @{ Status = 'Failed'; CurrentPolicy = $currentPolicy; Error = $_.ToString() }
    }
}

# ================================================================
# Function: Get-SystemInfo
# ================================================================
# Purpose: Gather basic system information for logging
# ================================================================
function Get-SystemInfo {
    return @{
        ComputerName = $env:COMPUTERNAME
        UserName = $env:USERNAME
        OSVersion = (Get-CimInstance -Class Win32_OperatingSystem -ErrorAction SilentlyContinue).Caption
        PSVersion = $PSVersionTable.PSVersion.ToString()
        Architecture = $env:PROCESSOR_ARCHITECTURE
        IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        WorkingDirectory = $global:WorkingDirectory
        LogFile = $global:LogFile
    }
}

# ================================================================
# Function: Restart-InPowerShell7
# ================================================================
# Purpose: Restart the current script in PowerShell 7 if available
# ================================================================
function Restart-InPowerShell7 {
    param(
        [string]$ScriptPath,
        [string[]]$Arguments = @()
    )

    # Check if we're already in PS7
    if ($PSVersionTable.PSVersion.Major -ge 7) {
        return $false
    }

    # Check if pwsh is available
    try {
        $null = Get-Command pwsh -ErrorAction Stop

        $argString = "-ExecutionPolicy Bypass -File `"$ScriptPath`""
        if ($Arguments) {
            $argString += " " + ($Arguments -join " ")
        }

        Start-Process pwsh.exe -ArgumentList $argString -Verb RunAs -Wait
        return $true
    }
    catch {
        return $false
    }
}

# Export functions
Export-ModuleMember -Function Initialize-BootstrapEnvironment, Test-PowerShellVersion, Install-PowerShell7, Initialize-GlobalConfig, Test-ExecutionPolicy, Get-SystemInfo, Restart-InPowerShell7