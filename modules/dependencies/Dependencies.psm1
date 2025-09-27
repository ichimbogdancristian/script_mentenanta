# Dependencies.psm1 - System dependencies management module
# Handles checking, installing, and managing required tools and packages

# ================================================================
# Function: Test-Dependency
# ================================================================
# Purpose: Test if a specific dependency is available
# ================================================================
function Test-Dependency {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [string]$Command,
        [string]$Path,
        [string]$VersionCommand,
        [scriptblock]$CustomTest
    )

    $result = @{
        Name = $Name
        Available = $false
        Version = $null
        Path = $null
        Status = 'Unknown'
    }

    try {
        if ($CustomTest) {
            # Use custom test logic
            $testResult = & $CustomTest
            $result.Available = $testResult.Available
            $result.Version = $testResult.Version
            $result.Path = $testResult.Path
        }
        elseif ($Command) {
            # Test by command
            $cmdInfo = Get-Command $Command -ErrorAction Stop
            $result.Available = $true
            $result.Path = $cmdInfo.Source

            # Try to get version
            if ($VersionCommand) {
                try {
                    $versionOutput = & $Command $VersionCommand 2>$null
                    $result.Version = $versionOutput | Select-Object -First 1
                }
                catch {
                    $result.Version = "Unknown"
                }
            }
        }
        elseif ($Path) {
            # Test by path
            $result.Available = Test-Path $Path
            if ($result.Available) {
                $result.Path = $Path
            }
        }

        $result.Status = if ($result.Available) { 'Available' } else { 'NotFound' }
    }
    catch {
        $result.Status = 'Error'
        $result.Error = $_.ToString()
    }

    return $result
}

# ================================================================
# Function: Get-SystemDependencies
# ================================================================
# Purpose: Get the list of all system dependencies to check
# ================================================================
function Get-SystemDependencies {
    return @(
        @{
            Name = 'Winget'
            Command = 'winget'
            VersionCommand = '--version'
            Installer = 'Install-Winget'
            Description = 'Windows Package Manager'
            Required = $false
        },
        @{
            Name = 'Chocolatey'
            Command = 'choco'
            VersionCommand = '--version'
            Installer = 'Install-Chocolatey'
            Description = 'Package Manager for Windows'
            Required = $false
        },
        @{
            Name = 'Git'
            Command = 'git'
            VersionCommand = '--version'
            Installer = 'Install-Git'
            Description = 'Version Control System'
            Required = $false
        },
        @{
            Name = 'PowerShell7'
            CustomTest = {
                $ps7Path = Get-Command pwsh -ErrorAction SilentlyContinue
                if ($ps7Path) {
                    $version = & pwsh -Command '$PSVersionTable.PSVersion.ToString()'
                    return @{
                        Available = $true
                        Version = $version
                        Path = $ps7Path.Source
                    }
                }
                return @{ Available = $false }
            }
            Installer = 'Install-PowerShell7'
            Description = 'PowerShell 7 Runtime'
            Required = $false
        },
        @{
            Name = 'DISM'
            Command = 'dism.exe'
            VersionCommand = '/?'
            Description = 'Deployment Image Servicing and Management'
            Required = $true
        },
        @{
            Name = 'SFC'
            Command = 'sfc.exe'
            VersionCommand = '/?'
            Description = 'System File Checker'
            Required = $true
        }
    )
}

# ================================================================
# Function: Test-SystemDependencies
# ================================================================
# Purpose: Test all system dependencies and return status
# ================================================================
function Test-SystemDependencies {
    param(
        [switch]$ShowProgress,
        [string[]]$IncludeDependencies,
        [string[]]$ExcludeDependencies
    )

    $allDeps = Get-SystemDependencies
    $depsToTest = $allDeps

    # Filter dependencies if specified
    if ($IncludeDependencies) {
        $depsToTest = $allDeps | Where-Object { $_.Name -in $IncludeDependencies }
    }
    elseif ($ExcludeDependencies) {
        $depsToTest = $allDeps | Where-Object { $_.Name -notin $ExcludeDependencies }
    }

    $results = @{
        Timestamp = Get-Date
        Dependencies = @()
        Summary = @{
            Total = $depsToTest.Count
            Available = 0
            Missing = 0
            RequiredMissing = 0
        }
    }

    foreach ($dep in $depsToTest) {
        if ($ShowProgress) {
            Write-Host "Checking $($dep.Name)..." -ForegroundColor Yellow -NoNewline
        }

        $testResult = Test-Dependency @dep

        if ($ShowProgress) {
            $color = if ($testResult.Available) { "Green" } else { "Red" }
            Write-Host " $($testResult.Status)" -ForegroundColor $color
        }

        # Add additional info
        $testResult.Description = $dep.Description
        $testResult.Required = $dep.Required
        $testResult.Installer = $dep.Installer

        $results.Dependencies += $testResult

        # Update summary
        if ($testResult.Available) {
            $results.Summary.Available++
        }
        else {
            $results.Summary.Missing++
            if ($testResult.Required) {
                $results.Summary.RequiredMissing++
            }
        }
    }

    $results.Summary.AvailabilityRate = [math]::Round($results.Summary.Available / $results.Summary.Total * 100, 1)

    return $results
}

# ================================================================
# Function: Install-Dependency
# ================================================================
# Purpose: Install a specific dependency
# ================================================================
function Install-Dependency {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [switch]$Force,
        [switch]$Quiet
    )

    $deps = Get-SystemDependencies
    $dep = $deps | Where-Object { $_.Name -eq $Name }

    if (-not $dep) {
        throw "Dependency '$Name' not found"
    }

    if (-not $dep.Installer) {
        throw "No installer available for '$Name'"
    }

    # Check if already installed
    $testResult = Test-Dependency @dep
    if ($testResult.Available -and -not $Force) {
        if (-not $Quiet) {
            Write-Host "$Name is already installed" -ForegroundColor Green
        }
        return $true
    }

    if (-not $Quiet) {
        Write-Host "Installing $Name..." -ForegroundColor Yellow
    }

    try {
        & $dep.Installer -Quiet:$Quiet
        if (-not $Quiet) {
            Write-Host "$Name installed successfully" -ForegroundColor Green
        }
        return $true
    }
    catch {
        if (-not $Quiet) {
            Write-Warning "Failed to install $Name`: $_"
        }
        return $false
    }
}

# ================================================================
# Function: Install-Winget
# ================================================================
# Purpose: Install Windows Package Manager (Winget)
# ================================================================
function Install-Winget {
    param([switch]$Quiet)

    try {
        # Check if App Installer is installed (prerequisite for winget)
        $appInstaller = Get-AppxPackage -Name "Microsoft.DesktopAppInstaller" -ErrorAction SilentlyContinue
        if (-not $appInstaller) {
            if (-not $Quiet) { Write-Host "Installing App Installer..." }
            # This would require downloading and installing the MSIX bundle
            # For now, we'll note that manual installation may be required
            throw "App Installer not found. Winget requires manual installation on some systems."
        }

        # Try to update App Installer to get latest winget
        if (-not $Quiet) { Write-Host "Ensuring Winget is up to date..." }
        # winget should be available if App Installer is installed

        return $true
    }
    catch {
        throw "Failed to install Winget: $_"
    }
}

# ================================================================
# Function: Install-Chocolatey
# ================================================================
# Purpose: Install Chocolatey package manager
# ================================================================
function Install-Chocolatey {
    param([switch]$Quiet)

    try {
        if (-not $Quiet) { Write-Host "Installing Chocolatey..." }

        # Set execution policy for installation
        $originalPolicy = Get-ExecutionPolicy
        Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force

        # Download and install Chocolatey
        $installScript = Invoke-WebRequest -Uri "https://chocolatey.org/install.ps1" -UseBasicParsing
        $installScriptBlock = [scriptblock]::Create($installScript.Content)
        & $installScriptBlock

        # Restore execution policy
        Set-ExecutionPolicy -ExecutionPolicy $originalPolicy -Scope Process -Force

        # Refresh environment
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")

        return $true
    }
    catch {
        throw "Failed to install Chocolatey: $_"
    }
}

# ================================================================
# Function: Install-Git
# ================================================================
# Purpose: Install Git version control system
# ================================================================
function Install-Git {
    param([switch]$Quiet)

    try {
        if (-not $Quiet) { Write-Host "Installing Git..." }

        # Try winget first
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            $process = Start-Process winget -ArgumentList "install --id Git.Git --accept-source-agreements --accept-package-agreements -e" -NoNewWindow -Wait -PassThru
            if ($process.ExitCode -eq 0) {
                return $true
            }
        }

        # Try Chocolatey
        if (Get-Command choco -ErrorAction SilentlyContinue) {
            $process = Start-Process choco -ArgumentList "install git -y" -NoNewWindow -Wait -PassThru
            if ($process.ExitCode -eq 0) {
                return $true
            }
        }

        # Manual download as fallback
        $gitUrl = "https://github.com/git-for-windows/git/releases/latest/download/Git-2.40.0-64-bit.exe"
        $installerPath = Join-Path $global:TempFolder "git-installer.exe"

        if (-not $Quiet) { Write-Host "Downloading Git installer..." }
        Invoke-WebRequest -Uri $gitUrl -OutFile $installerPath

        if (-not $Quiet) { Write-Host "Running Git installer..." }
        $process = Start-Process $installerPath -ArgumentList "/VERYSILENT /NORESTART" -NoNewWindow -Wait -PassThru

        if ($process.ExitCode -eq 0) {
            return $true
        }
        else {
            throw "Git installer exited with code $($process.ExitCode)"
        }
    }
    catch {
        throw "Failed to install Git: $_"
    }
}

# ================================================================
# Function: Install-PowerShell7
# ================================================================
# Purpose: Install PowerShell 7
# ================================================================
function Install-PowerShell7 {
    param([switch]$Quiet)

    try {
        if (-not $Quiet) { Write-Host "Installing PowerShell 7..." }

        # Try winget first
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            $process = Start-Process winget -ArgumentList "install --id Microsoft.PowerShell --accept-source-agreements --accept-package-agreements -e" -NoNewWindow -Wait -PassThru
            if ($process.ExitCode -eq 0) {
                return $true
            }
        }

        # MSI installer as fallback
        $msiUrl = "https://github.com/PowerShell/PowerShell/releases/latest/download/PowerShell-7.4.5-win-x64.msi"
        $msiPath = Join-Path $global:TempFolder "PowerShell7.msi"

        if (-not $Quiet) { Write-Host "Downloading PowerShell 7 MSI..." }
        Invoke-WebRequest -Uri $msiUrl -OutFile $msiPath

        if (-not $Quiet) { Write-Host "Installing PowerShell 7..." }
        $process = Start-Process msiexec.exe -ArgumentList "/i `"$msiPath`" /quiet /norestart" -NoNewWindow -Wait -PassThru

        if ($process.ExitCode -eq 0) {
            return $true
        }
        else {
            throw "PowerShell 7 installer exited with code $($process.ExitCode)"
        }
    }
    catch {
        throw "Failed to install PowerShell 7: $_"
    }
}

# ================================================================
# Function: Install-MissingDependencies
# ================================================================
# Purpose: Install all missing dependencies
# ================================================================
function Install-MissingDependencies {
    param(
        [switch]$Quiet,
        [switch]$Force,
        [string[]]$IncludeDependencies,
        [string[]]$ExcludeDependencies
    )

    $testResults = Test-SystemDependencies -IncludeDependencies $IncludeDependencies -ExcludeDependencies $ExcludeDependencies

    $missingDeps = $testResults.Dependencies | Where-Object { -not $_.Available -and $_.Installer }

    if (-not $missingDeps) {
        if (-not $Quiet) {
            Write-Host "All dependencies are already installed" -ForegroundColor Green
        }
        return $true
    }

    $installed = 0
    $failed = 0

    foreach ($dep in $missingDeps) {
        try {
            if (Install-Dependency -Name $dep.Name -Force:$Force -Quiet:$Quiet) {
                $installed++
            }
        }
        catch {
            if (-not $Quiet) {
                Write-Warning "Failed to install $($dep.Name): $_"
            }
            $failed++
        }
    }

    if (-not $Quiet) {
        Write-Host "`nInstallation Summary:" -ForegroundColor Cyan
        Write-Host "  Installed: $installed" -ForegroundColor Green
        Write-Host "  Failed: $failed" -ForegroundColor Red
    }

    return $failed -eq 0
}

# Export functions
Export-ModuleMember -Function Test-Dependency, Get-SystemDependencies, Test-SystemDependencies, Install-Dependency, Install-Winget, Install-Chocolatey, Install-Git, Install-PowerShell7, Install-MissingDependencies