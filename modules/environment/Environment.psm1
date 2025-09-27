# Environment.psm1 - System environment validation and setup module
# Handles administrator privileges, system compatibility checks, and environment validation

# ================================================================
# Function: Test-AdministratorPrivileges
# ================================================================
# Purpose: Check if the current process has administrator privileges
# ================================================================
function Test-AdministratorPrivileges {
    param(
        [switch]$RequireElevation
    )

    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    $result = @{
        IsAdministrator = $isAdmin
        UserName = $env:USERNAME
        Domain = $env:USERDOMAIN
    }

    if (-not $isAdmin -and $RequireElevation) {
        $result.RequiresElevation = $true
        $result.Status = 'ElevationRequired'
    }
    elseif ($isAdmin) {
        $result.Status = 'Administrator'
    }
    else {
        $result.Status = 'StandardUser'
    }

    return $result
}

# ================================================================
# Function: Request-AdministratorPrivileges
# ================================================================
# Purpose: Attempt to elevate the current process to administrator
# ================================================================
function Request-AdministratorPrivileges {
    param(
        [string]$ScriptPath,
        [string[]]$Arguments = @(),
        [switch]$WaitForCompletion,
        [switch]$Silent
    )

    $adminCheck = Test-AdministratorPrivileges
    if ($adminCheck.IsAdministrator) {
        if (-not $Silent) {
            Write-Host "Already running as administrator" -ForegroundColor Green
        }
        return @{ Status = 'AlreadyElevated'; Process = $null }
    }

    try {
        $argList = @("-ExecutionPolicy", "Bypass", "-File", "`"$ScriptPath`"")
        if ($Arguments) {
            $argList += $Arguments
        }

        $startInfo = @{
            FilePath = "pwsh.exe"
            ArgumentList = $argList
            Verb = "RunAs"
            PassThru = $true
        }

        if ($WaitForCompletion) {
            $startInfo.NoWait = $false
        }
        else {
            $startInfo.NoWait = $true
        }

        $process = Start-Process @startInfo

        return @{
            Status = 'Elevated'
            Process = $process
            ProcessId = $process.Id
        }
    }
    catch {
        return @{
            Status = 'Failed'
            Error = $_.ToString()
        }
    }
}

# ================================================================
# Function: Test-SystemCompatibility
# ================================================================
# Purpose: Check if the system meets minimum requirements
# ================================================================
function Test-SystemCompatibility {
    param(
        [string[]]$RequiredFeatures = @('WMI', 'CIM', 'Registry', 'FileSystem')
    )

    $results = @{
        OverallCompatible = $true
        Checks = @{}
        Recommendations = @()
    }

    # Windows Version Check
    try {
        $osInfo = Get-CimInstance -Class Win32_OperatingSystem -ErrorAction Stop
        $version = [version]$osInfo.Version
        $minVersion = [version]"10.0.10240"  # Windows 10 1507 minimum

        $results.Checks.WindowsVersion = @{
            Compatible = $version -ge $minVersion
            CurrentVersion = $osInfo.Caption
            VersionNumber = $version.ToString()
            MinimumVersion = $minVersion.ToString()
        }

        if (-not $results.Checks.WindowsVersion.Compatible) {
            $results.OverallCompatible = $false
            $results.Recommendations += "Windows 10 version 1507 or higher is required"
        }
    }
    catch {
        $results.Checks.WindowsVersion = @{
            Compatible = $false
            Error = "Failed to detect Windows version: $_"
        }
        $results.OverallCompatible = $false
    }

    # Architecture Check
    $architecture = $env:PROCESSOR_ARCHITECTURE
    $supportedArchs = @('AMD64', 'ARM64')

    $results.Checks.Architecture = @{
        Compatible = $architecture -in $supportedArchs
        CurrentArchitecture = $architecture
        SupportedArchitectures = $supportedArchs
    }

    if (-not $results.Checks.Architecture.Compatible) {
        $results.OverallCompatible = $false
        $results.Recommendations += "64-bit architecture required"
    }

    # Required Features Check
    foreach ($feature in $RequiredFeatures) {
        $featureCheck = Test-SystemFeature -Feature $feature
        $results.Checks.$feature = $featureCheck

        if (-not $featureCheck.Available) {
            $results.OverallCompatible = $false
            $results.Recommendations += $featureCheck.Recommendation
        }
    }

    # Memory Check
    try {
        $memory = Get-CimInstance -Class Win32_ComputerSystem -ErrorAction Stop
        $totalMemoryGB = [math]::Round($memory.TotalPhysicalMemory / 1GB, 2)
        $minMemoryGB = 4

        $results.Checks.Memory = @{
            Compatible = $totalMemoryGB -ge $minMemoryGB
            TotalMemoryGB = $totalMemoryGB
            MinimumMemoryGB = $minMemoryGB
        }

        if (-not $results.Checks.Memory.Compatible) {
            $results.Recommendations += "At least ${minMemoryGB}GB RAM recommended"
        }
    }
    catch {
        $results.Checks.Memory = @{
            Compatible = $true  # Don't fail on memory check
            Error = "Could not determine memory: $_"
        }
    }

    return $results
}

# ================================================================
# Function: Test-SystemFeature
# ================================================================
# Purpose: Test availability of specific system features
# ================================================================
function Test-SystemFeature {
    param(
        [ValidateSet('WMI', 'CIM', 'Registry', 'FileSystem', 'Network', 'ScheduledTasks')]
        [string]$Feature
    )

    switch ($Feature) {
        'WMI' {
            try {
                $null = Get-WmiObject -Class Win32_OperatingSystem -ErrorAction Stop
                return @{ Available = $true; Feature = $Feature }
            }
            catch {
                return @{
                    Available = $false
                    Feature = $Feature
                    Error = $_.ToString()
                    Recommendation = "WMI service may be disabled or inaccessible"
                }
            }
        }

        'CIM' {
            try {
                $null = Get-CimInstance -Class Win32_OperatingSystem -ErrorAction Stop
                return @{ Available = $true; Feature = $Feature }
            }
            catch {
                return @{
                    Available = $false
                    Feature = $Feature
                    Error = $_.ToString()
                    Recommendation = "CIM/WMI service may be disabled or inaccessible"
                }
            }
        }

        'Registry' {
            try {
                $null = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion" -ErrorAction Stop
                return @{ Available = $true; Feature = $Feature }
            }
            catch {
                return @{
                    Available = $false
                    Feature = $Feature
                    Error = $_.ToString()
                    Recommendation = "Registry access may be restricted"
                }
            }
        }

        'FileSystem' {
            try {
                $testPath = Join-Path $global:TempFolder "test.tmp"
                "test" | Out-File -FilePath $testPath -ErrorAction Stop
                Remove-Item -Path $testPath -ErrorAction Stop
                return @{ Available = $true; Feature = $Feature }
            }
            catch {
                return @{
                    Available = $false
                    Feature = $Feature
                    Error = $_.ToString()
                    Recommendation = "File system access may be restricted"
                }
            }
        }

        'Network' {
            try {
                $null = Test-Connection -ComputerName "8.8.8.8" -Count 1 -ErrorAction Stop
                return @{ Available = $true; Feature = $Feature }
            }
            catch {
                return @{
                    Available = $false
                    Feature = $Feature
                    Error = $_.ToString()
                    Recommendation = "Network connectivity may be limited"
                }
            }
        }

        'ScheduledTasks' {
            try {
                $null = Get-ScheduledTask -ErrorAction Stop
                return @{ Available = $true; Feature = $Feature }
            }
            catch {
                return @{
                    Available = $false
                    Feature = $Feature
                    Error = $_.ToString()
                    Recommendation = "Scheduled Tasks service may be disabled"
                }
            }
        }
    }
}

# ================================================================
# Function: Get-EnvironmentReport
# ================================================================
# Purpose: Generate a comprehensive environment report
# ================================================================
function Get-EnvironmentReport {
    $report = @{
        Timestamp = Get-Date
        SystemInfo = Get-SystemInfo
        Compatibility = Test-SystemCompatibility
        Administrator = Test-AdministratorPrivileges
        PowerShell = Test-PowerShellVersion -RecommendedVersion 7
    }

    # Calculate overall readiness
    $readinessFactors = @(
        $report.Compatibility.OverallCompatible
        $report.Administrator.IsAdministrator
        $report.PowerShell.IsCompatible
    )

    $report.OverallReady = -not ($readinessFactors -contains $false)
    $report.ReadinessScore = [math]::Round(($readinessFactors | Where-Object { $_ } | Measure-Object).Count / $readinessFactors.Count * 100, 1)

    return $report
}

# ================================================================
# Function: Show-EnvironmentReport
# ================================================================
# Purpose: Display the environment report in a user-friendly format
# ================================================================
function Show-EnvironmentReport {
    param(
        [Parameter(ValueFromPipeline = $true)]
        $Report
    )

    if (-not $Report) {
        $Report = Get-EnvironmentReport
    }

    Write-Host "`n=== Environment Report ===" -ForegroundColor Cyan
    Write-Host "Generated: $($Report.Timestamp)" -ForegroundColor Gray

    # Overall Status
    $statusColor = if ($Report.OverallReady) { "Green" } else { "Red" }
    Write-Host "`nOverall Status: " -NoNewline
    Write-Host $(if ($Report.OverallReady) { "READY" } else { "NOT READY" }) -ForegroundColor $statusColor
    Write-Host "Readiness Score: $($Report.ReadinessScore)%" -ForegroundColor $(if ($Report.ReadinessScore -ge 80) { "Green" } else { "Yellow" })

    # System Information
    Write-Host "`nSystem Information:" -ForegroundColor Yellow
    Write-Host "  Computer: $($Report.SystemInfo.ComputerName)"
    Write-Host "  User: $($Report.SystemInfo.UserName)"
    Write-Host "  OS: $($Report.SystemInfo.OSVersion)"
    Write-Host "  PowerShell: $($Report.SystemInfo.PSVersion)"
    Write-Host "  Architecture: $($Report.SystemInfo.Architecture)"

    # Administrator Status
    $adminColor = if ($Report.Administrator.IsAdministrator) { "Green" } else { "Red" }
    Write-Host "`nAdministrator Privileges: " -NoNewline
    Write-Host $(if ($Report.Administrator.IsAdministrator) { "YES" } else { "NO" }) -ForegroundColor $adminColor

    # Compatibility
    Write-Host "`nCompatibility Checks:" -ForegroundColor Yellow
    foreach ($check in $Report.Compatibility.Checks.GetEnumerator()) {
        $checkColor = if ($check.Value.Compatible) { "Green" } else { "Red" }
        Write-Host "  $($check.Key): " -NoNewline
        Write-Host $(if ($check.Value.Compatible) { "PASS" } else { "FAIL" }) -ForegroundColor $checkColor
    }

    # Recommendations
    if ($Report.Compatibility.Recommendations) {
        Write-Host "`nRecommendations:" -ForegroundColor Yellow
        foreach ($rec in $Report.Compatibility.Recommendations) {
            Write-Host "  - $rec" -ForegroundColor Magenta
        }
    }

    Write-Host "`n=== End Report ===" -ForegroundColor Cyan
}

# Export functions
Export-ModuleMember -Function Test-AdministratorPrivileges, Request-AdministratorPrivileges, Test-SystemCompatibility, Test-SystemFeature, Get-EnvironmentReport, Show-EnvironmentReport